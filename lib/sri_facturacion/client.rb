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
                                    tipo_emision: factura.tipo_emision, info_extra: info_extra(factura)).build

      xml_firmado = signer.sign(xml)

      result = @soap_client.enviar_y_autorizar(xml_firmado, clave_acceso, ambiente: ambiente)

      if result.autorizado? && generar_ride
        pdf = ride_pdf(factura, clave_acceso: clave_acceso, numero_autorizacion: result.numero_autorizacion,
                                fecha_autorizacion: result.fecha_autorizacion)
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
                                                    tipo_emision: nota_credito.tipo_emision,
                                                    info_extra: info_extra(nota_credito)).build

      xml_firmado = signer.sign(xml)

      @soap_client.enviar_y_autorizar(xml_firmado, clave_acceso, ambiente: ambiente)
    end

    # ── Paso a paso (para un job en segundo plano) ──────────────────────
    #
    # El sistema guarda la clave y el XML firmado ANTES de enviar, así un corte
    # de red nunca pierde el comprobante:
    #
    #   firmado = client.firmar(factura)          # sin red
    #   client.recepcion(firmado[:xml_firmado])   # { estado: "RECIBIDA" | "DEVUELTA", mensajes: }
    #   client.autorizacion(firmado[:clave_acceso]) # { estado: "AUTORIZADO" | "NO AUTORIZADO" | nil, ... }

    # Clave de acceso + XML + firma, para una factura o una nota de crédito.
    def firmar(comprobante, codigo_numerico: nil)
      ambiente = @config.ambiente.to_s
      nota = comprobante.is_a?(Models::NotaCredito)
      clave_acceso = AccessKey.generate(
        fecha_emision: comprobante.fecha_emision, ruc: comprobante.emisor.ruc,
        establecimiento: comprobante.emisor.establecimiento, punto_emision: comprobante.emisor.punto_emision,
        secuencial: comprobante.secuencial, ambiente: ambiente, tipo_emision: comprobante.tipo_emision,
        tipo_comprobante: nota ? AccessKey::NOTA_CREDITO : AccessKey::FACTURA, codigo_numerico: codigo_numerico
      )
      builder = nota ? NotaCreditoXmlBuilder : XmlBuilder
      xml = builder.new(comprobante, clave_acceso: clave_acceso, ambiente: ambiente,
                                     tipo_emision: comprobante.tipo_emision, info_extra: info_extra(comprobante)).build
      { clave_acceso: clave_acceso, xml_firmado: signer.sign(xml) }
    end

    # Envía el XML firmado a recepción. El ambiente sale de la clave de acceso.
    def recepcion(xml_firmado, clave_acceso)
      @soap_client.validar_comprobante(xml_firmado, ambiente: ambiente_de(clave_acceso))
    end

    # Consulta la autorización. estado nil = el SRI todavía no la procesa.
    def autorizacion(clave_acceso)
      @soap_client.autorizar_comprobante(clave_acceso, ambiente: ambiente_de(clave_acceso))
    end

    # RIDE (PDF) de una factura o nota de crédito ya autorizada.
    def ride_pdf(comprobante, clave_acceso:, numero_autorizacion: nil, fecha_autorizacion: nil)
      Ride.new(comprobante, clave_acceso: clave_acceso, numero_autorizacion: numero_autorizacion,
                            fecha_autorizacion: fecha_autorizacion, ambiente: ambiente_de(clave_acceso),
                            verification_url: @config.ride_verification_url, footer: @config.ride_footer).render
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
                              tipo_emision: factura.tipo_emision, info_extra: info_extra(factura)).build
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
                                              tipo_emision: nota_credito.tipo_emision,
                                              info_extra: info_extra(nota_credito)).build
    end

    private

    PROVEEDOR_CAMPO = "RUCProveedorSistema"

    # Resolución NAC-DGERCGC26-00000027: el RUC del proveedor del sistema va en
    # infoAdicional, salvo que el comprobante ya lo traiga.
    def info_extra(comprobante)
      ruc = @config.proveedor_ruc.to_s.strip
      return [] unless ruc.match?(/\A\d{13}\z/)
      return [] if Array(comprobante.info_adicional).any? { |c| (c[:nombre] || c["nombre"]) == PROVEEDOR_CAMPO }

      [{ nombre: PROVEEDOR_CAMPO, valor: ruc }]
    end

    # Posición 24 de la clave de acceso: 1 pruebas, 2 producción.
    def ambiente_de(clave_acceso)
      clave_acceso.to_s[23] || @config.ambiente.to_s
    end

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
