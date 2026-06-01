# frozen_string_literal: true

require "bigdecimal"

module SriFacturacion
  # Helpers compartidos por los constructores de XML de los distintos comprobantes:
  # el bloque infoTributaria (idéntico en todos) y los formateadores numéricos/fecha
  # exigidos por los XSD del SRI (montos a 2 decimales, cantidades a 6, fechas dd/mm/aaaa).
  module XmlSupport
    private

    # infoTributaria es común a factura, nota de crédito, nota de débito, retención y guía.
    # Port de XmlBuilderService#buildInfoTributaria. Recibe el contexto `xml` del
    # Nokogiri::XML::Builder y emite los nodos en orden.
    def build_info_tributaria(xml, emisor:, clave_acceso:, ambiente:, tipo_emision:, cod_doc:, secuencial:)
      xml.infoTributaria do
        xml.ambiente ambiente.to_s
        xml.tipoEmision tipo_emision.to_s
        xml.razonSocial emisor.razon_social
        xml.nombreComercial emisor.nombre_comercial if emisor.nombre_comercial
        xml.ruc emisor.ruc
        xml.claveAcceso clave_acceso
        xml.codDoc cod_doc
        xml.estab emisor.establecimiento
        xml.ptoEmi emisor.punto_emision
        xml.secuencial secuencial
        xml.dirMatriz emisor.dir_matriz
        xml.agenteRetencion emisor.agente_retencion if emisor.respond_to?(:agente_retencion) && emisor.agente_retencion
        if emisor.respond_to?(:contribuyente_rimpe) && emisor.contribuyente_rimpe
          xml.contribuyenteRimpe emisor.contribuyente_rimpe
        end
      end
    end

    def fecha(date)
      return date if date.is_a?(String)

      d = date.respond_to?(:to_date) ? date.to_date : date
      format("%02d/%02d/%04d", d.day, d.month, d.year)
    end

    def money(value)
      format("%.2f", to_f(value))
    end

    def qty(value)
      format("%.6f", to_f(value))
    end

    def to_f(value)
      value.is_a?(BigDecimal) ? value.to_f : value.to_f
    end
  end
end
