# frozen_string_literal: true

require "net/http"
require "uri"
require "base64"
require "nokogiri"

module SriFacturacion
  # Cliente SOAP para los web services offline del SRI: recepción y autorización.
  # Port de SriSoapClient (envelopes SOAP crudos, sin dependencia de WSDL).
  class SoapClient
    RECEPCION_NS = "http://ec.gob.sri.ws.recepcion"
    AUTORIZACION_NS = "http://ec.gob.sri.ws.autorizacion"

    def initialize(config: SriFacturacion.configuration)
      @config = config
    end

    # Devuelve un hash { estado:, mensajes: [...] }.
    def validar_comprobante(xml_firmado, ambiente:)
      xml_b64 = Base64.strict_encode64(xml_firmado)
      envelope = <<~XML
        <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ec="#{RECEPCION_NS}">
          <soapenv:Header/>
          <soapenv:Body>
            <ec:validarComprobante>
              <xml>#{xml_b64}</xml>
            </ec:validarComprobante>
          </soapenv:Body>
        </soapenv:Envelope>
      XML

      doc = post(@config.recepcion_url(ambiente), envelope)
      parse_recepcion(doc)
    end

    # Devuelve un hash { estado:, numero_autorizacion:, fecha_autorizacion:, comprobante:, mensajes: }.
    def autorizar_comprobante(clave_acceso, ambiente:)
      envelope = <<~XML
        <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ec="#{AUTORIZACION_NS}">
          <soapenv:Header/>
          <soapenv:Body>
            <ec:autorizacionComprobante>
              <claveAccesoComprobante>#{clave_acceso}</claveAccesoComprobante>
            </ec:autorizacionComprobante>
          </soapenv:Body>
        </soapenv:Envelope>
      XML

      doc = post(@config.autorizacion_url(ambiente), envelope)
      parse_autorizacion(doc)
    end

    # Recepción + autorización con reintentos. Devuelve un Result.
    def enviar_y_autorizar(xml_firmado, clave_acceso, ambiente:)
      recepcion = validar_comprobante(xml_firmado, ambiente: ambiente)

      if recepcion[:estado] == "DEVUELTA"
        return Result.new(success: false, estado: "DEVUELTA", clave_acceso: clave_acceso,
                          xml_firmado: xml_firmado, mensajes: recepcion[:mensajes])
      end

      retries = @config.max_retries.to_i
      delay = @config.retry_delay.to_f

      (1..retries).each do |intento|
        sleep(delay) if intento > 1
        auth = autorizar_comprobante(clave_acceso, ambiente: ambiente)

        case auth[:estado]
        when "AUTORIZADO"
          return Result.new(success: true, estado: "AUTORIZADO", clave_acceso: clave_acceso,
                            numero_autorizacion: auth[:numero_autorizacion],
                            fecha_autorizacion: auth[:fecha_autorizacion],
                            xml_firmado: xml_firmado, xml_autorizado: auth[:comprobante],
                            mensajes: auth[:mensajes])
        when "NO AUTORIZADO", "RECHAZADA"
          return Result.new(success: false, estado: "NO AUTORIZADO", clave_acceso: clave_acceso,
                            xml_firmado: xml_firmado, mensajes: auth[:mensajes])
        end
      end

      Result.new(success: false, estado: "EN PROCESO", clave_acceso: clave_acceso,
                 xml_firmado: xml_firmado,
                 mensajes: [{ identificador: "TIMEOUT", mensaje: "Se agotaron los reintentos de autorización", tipo: "ADVERTENCIA" }])
    end

    # Expuestos para pruebas unitarias de parseo.
    def parse_recepcion(doc)
      doc = ensure_doc(doc)
      doc.remove_namespaces!
      estado = doc.at_xpath("//estado")&.text
      { estado: estado || "DEVUELTA", mensajes: extract_mensajes(doc) }
    end

    def parse_autorizacion(doc)
      doc = ensure_doc(doc)
      doc.remove_namespaces!
      auth = doc.at_xpath("//autorizacion")
      {
        estado: auth&.at_xpath("estado")&.text,
        numero_autorizacion: auth&.at_xpath("numeroAutorizacion")&.text,
        fecha_autorizacion: auth&.at_xpath("fechaAutorizacion")&.text,
        comprobante: auth&.at_xpath("comprobante")&.text,
        mensajes: extract_mensajes(doc)
      }
    end

    private

    def post(url, body)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = @config.open_timeout
      http.read_timeout = @config.read_timeout

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "text/xml; charset=utf-8"
      request["SOAPAction"] = ""
      request.body = body

      response = http.request(request)
      unless response.is_a?(Net::HTTPSuccess)
        raise SoapError, "El SRI respondió HTTP #{response.code}: #{response.body.to_s[0, 300]}"
      end

      Nokogiri::XML(response.body)
    rescue SoapError
      raise
    rescue StandardError => e
      raise SoapError, "Error de comunicación con el SRI (#{url}): #{e.message}"
    end

    def ensure_doc(doc)
      doc.is_a?(Nokogiri::XML::Document) ? doc : Nokogiri::XML(doc.to_s)
    end

    def extract_mensajes(doc)
      doc.xpath("//mensaje").map do |m|
        {
          identificador: m.at_xpath("identificador")&.text,
          mensaje: m.at_xpath("mensaje")&.text,
          informacion_adicional: m.at_xpath("informacionAdicional")&.text,
          tipo: m.at_xpath("tipo")&.text
        }.compact
      end
    end
  end
end
