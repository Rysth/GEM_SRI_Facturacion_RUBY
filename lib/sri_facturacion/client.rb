# frozen_string_literal: true

module SriFacturacion
  # Orquestador de la emisión de una factura electrónica (comprobante 01).
  # Pipeline: clave de acceso -> XML -> firma XAdES-BES -> recepción -> autorización.
  # Por defecto opera en el ambiente de la configuración (PRUEBAS si no se cambia).
  class Client
    def initialize(config: SriFacturacion.configuration, signer: nil, soap_client: nil)
      @config = config
      @signer = signer
      @soap_client = soap_client || SoapClient.new(config: config)
    end

    # Genera, firma, envía y autoriza una factura. Devuelve un Result.
    #
    #   factura: SriFacturacion::Models::Factura
    #   codigo_numerico / secuencial: opcionales (override de la clave de acceso)
    #   generar_ride: si true, adjunta el PDF del RIDE al resultado autorizado.
    def emitir!(factura, codigo_numerico: nil, generar_ride: false)
      ambiente = @config.ambiente.to_s

      clave_acceso = AccessKey.generate(
        fecha_emision: factura.fecha_emision,
        ruc: factura.emisor.ruc,
        establecimiento: factura.emisor.establecimiento,
        punto_emision: factura.emisor.punto_emision,
        secuencial: factura.secuencial,
        ambiente: ambiente,
        tipo_emision: factura.tipo_emision,
        codigo_numerico: codigo_numerico
      )

      xml = XmlBuilder.new(factura, clave_acceso: clave_acceso, ambiente: ambiente,
                                    tipo_emision: factura.tipo_emision).build

      xml_firmado = signer.sign(xml)

      result = @soap_client.enviar_y_autorizar(xml_firmado, clave_acceso, ambiente: ambiente)

      if result.autorizado? && generar_ride
        pdf = Ride.new(factura, clave_acceso: clave_acceso,
                                numero_autorizacion: result.numero_autorizacion,
                                fecha_autorizacion: result.fecha_autorizacion,
                                ambiente: ambiente).render
        return Result.new(success: result.success?, estado: result.estado, clave_acceso: result.clave_acceso,
                          numero_autorizacion: result.numero_autorizacion,
                          fecha_autorizacion: result.fecha_autorizacion,
                          xml_firmado: result.xml_firmado, xml_autorizado: result.xml_autorizado,
                          mensajes: result.mensajes, ride_pdf: pdf)
      end

      result
    end

    # Genera, firma, envía y autoriza una nota de crédito (comprobante 04). Devuelve un Result.
    # La nota de crédito modifica un documento previo (ver SriFacturacion::Models::NotaCredito).
    def emitir_nota_credito!(nota_credito, codigo_numerico: nil)
      ambiente = @config.ambiente.to_s

      clave_acceso = AccessKey.generate(
        fecha_emision: nota_credito.fecha_emision,
        ruc: nota_credito.emisor.ruc,
        establecimiento: nota_credito.emisor.establecimiento,
        punto_emision: nota_credito.emisor.punto_emision,
        secuencial: nota_credito.secuencial,
        ambiente: ambiente,
        tipo_emision: nota_credito.tipo_emision,
        tipo_comprobante: AccessKey::NOTA_CREDITO,
        codigo_numerico: codigo_numerico
      )

      xml = NotaCreditoXmlBuilder.new(nota_credito, clave_acceso: clave_acceso, ambiente: ambiente,
                                                    tipo_emision: nota_credito.tipo_emision).build

      xml_firmado = signer.sign(xml)

      @soap_client.enviar_y_autorizar(xml_firmado, clave_acceso, ambiente: ambiente)
    end

    # Solo construye el XML sin firmar (útil para previsualizar).
    def preview_xml(factura, codigo_numerico: nil)
      ambiente = @config.ambiente.to_s
      clave_acceso = AccessKey.generate(
        fecha_emision: factura.fecha_emision, ruc: factura.emisor.ruc,
        establecimiento: factura.emisor.establecimiento, punto_emision: factura.emisor.punto_emision,
        secuencial: factura.secuencial, ambiente: ambiente, tipo_emision: factura.tipo_emision,
        codigo_numerico: codigo_numerico
      )
      XmlBuilder.new(factura, clave_acceso: clave_acceso, ambiente: ambiente,
                              tipo_emision: factura.tipo_emision).build
    end

    # Solo construye el XML de la nota de crédito sin firmar (útil para previsualizar).
    def preview_nota_credito_xml(nota_credito, codigo_numerico: nil)
      ambiente = @config.ambiente.to_s
      clave_acceso = AccessKey.generate(
        fecha_emision: nota_credito.fecha_emision, ruc: nota_credito.emisor.ruc,
        establecimiento: nota_credito.emisor.establecimiento, punto_emision: nota_credito.emisor.punto_emision,
        secuencial: nota_credito.secuencial, ambiente: ambiente, tipo_emision: nota_credito.tipo_emision,
        tipo_comprobante: AccessKey::NOTA_CREDITO, codigo_numerico: codigo_numerico
      )
      NotaCreditoXmlBuilder.new(nota_credito, clave_acceso: clave_acceso, ambiente: ambiente,
                                              tipo_emision: nota_credito.tipo_emision).build
    end

    private

    def signer
      @signer ||= begin
        unless @config.cert_path && @config.cert_password
          raise SignatureError, "Falta configurar cert_path y cert_password para firmar."
        end

        Signer.load(@config.cert_path, @config.cert_password)
      end
    end
  end
end
