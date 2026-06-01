# frozen_string_literal: true

require "nokogiri"
require "bigdecimal"

module SriFacturacion
  # Construye el XML de la nota de crédito electrónica versión 1.1.0 según el XSD del SRI.
  # Port de XmlBuilderService#buildNotaCredito.
  #
  # A diferencia de la factura: el detalle usa codigoInterno/codigoAdicional (no
  # codigoPrincipal/codigoAuxiliar) y no lleva unidadMedida; el bloque infoNotaCredito
  # añade la referencia al documento modificado (codDocModificado, numDocModificado,
  # fechaEmisionDocSustento), valorModificacion y motivo. En totalConImpuestos NO se
  # incluye la tarifa (a diferencia de la factura).
  class NotaCreditoXmlBuilder
    include XmlSupport

    NOTA_CREDITO_VERSION = "1.1.0"
    COD_DOC_NOTA_CREDITO = "04"

    def initialize(nota_credito, clave_acceso:, ambiente:, tipo_emision: "1")
      @nc = nota_credito
      @clave_acceso = clave_acceso
      @ambiente = ambiente.to_s
      @tipo_emision = tipo_emision.to_s
    end

    def build
      nc = @nc
      emisor = nc.emisor
      comprador = nc.comprador
      totales = nc.totales

      builder = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
        xml.notaCredito(id: "comprobante", version: NOTA_CREDITO_VERSION) do
          build_info_tributaria(xml, emisor: emisor, clave_acceso: @clave_acceso, ambiente: @ambiente,
                                     tipo_emision: @tipo_emision, cod_doc: COD_DOC_NOTA_CREDITO,
                                     secuencial: nc.secuencial)

          xml.infoNotaCredito do
            xml.fechaEmision fecha(nc.fecha_emision)
            xml.dirEstablecimiento emisor.dir_establecimiento if emisor.dir_establecimiento
            xml.tipoIdentificacionComprador comprador.tipo_identificacion
            xml.razonSocialComprador comprador.razon_social
            xml.identificacionComprador comprador.identificacion
            xml.contribuyenteEspecial emisor.contribuyente_especial if emisor.contribuyente_especial
            xml.obligadoContabilidad emisor.obligado_contabilidad
            xml.codDocModificado nc.cod_doc_modificado
            xml.numDocModificado nc.num_doc_modificado
            xml.fechaEmisionDocSustento fecha(nc.fecha_emision_doc_sustento)
            xml.totalSinImpuestos money(totales.total_sin_impuestos)
            xml.valorModificacion money(totales.importe_total)
            xml.moneda nc.moneda if nc.moneda
            xml.totalConImpuestos do
              totales.total_con_impuestos.each do |imp|
                xml.totalImpuesto do
                  xml.codigo imp.codigo
                  xml.codigoPorcentaje imp.codigo_porcentaje
                  xml.baseImponible money(imp.base_imponible)
                  xml.valor money(imp.valor)
                end
              end
            end
            xml.motivo nc.motivo
          end

          xml.detalles do
            nc.detalles.each do |d|
              xml.detalle do
                xml.codigoInterno(d.codigo_principal) if d.codigo_principal
                xml.codigoAdicional(d.codigo_auxiliar) if d.codigo_auxiliar
                xml.descripcion d.descripcion
                xml.cantidad qty(d.cantidad)
                xml.precioUnitario qty(d.precio_unitario)
                xml.descuento money(d.descuento)
                xml.precioTotalSinImpuesto money(d.precio_total_sin_impuesto)
                unless Array(d.detalles_adicionales).empty?
                  xml.detallesAdicionales do
                    d.detalles_adicionales.each do |da|
                      xml.detAdicional(nombre: da[:nombre] || da["nombre"], valor: da[:valor] || da["valor"])
                    end
                  end
                end
                xml.impuestos do
                  Array(d.impuestos).each do |imp|
                    xml.impuesto do
                      xml.codigo imp.codigo
                      xml.codigoPorcentaje imp.codigo_porcentaje
                      xml.tarifa money(imp.tarifa)
                      xml.baseImponible money(imp.base_imponible)
                      xml.valor money(imp.valor)
                    end
                  end
                end
              end
            end
          end

          unless Array(nc.info_adicional).empty?
            xml.infoAdicional do
              nc.info_adicional.each do |campo|
                xml.campoAdicional(campo[:valor] || campo["valor"], nombre: campo[:nombre] || campo["nombre"])
              end
            end
          end
        end
      end

      builder.to_xml
    end
  end
end
