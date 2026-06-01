# frozen_string_literal: true

require "nokogiri"
require "bigdecimal"

module SriFacturacion
  # Construye el XML de la factura electrónica versión 1.1.0 según el XSD del SRI.
  # Port de XmlBuilderService#buildFactura.
  class XmlBuilder
    include XmlSupport

    FACTURA_VERSION = "1.1.0"
    COD_DOC_FACTURA = "01"

    def initialize(factura, clave_acceso:, ambiente:, tipo_emision: "1")
      @factura = factura
      @clave_acceso = clave_acceso
      @ambiente = ambiente.to_s
      @tipo_emision = tipo_emision.to_s
    end

    def build
      f = @factura
      emisor = f.emisor
      comprador = f.comprador
      totales = f.totales

      builder = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
        xml.factura(id: "comprobante", version: FACTURA_VERSION) do
          build_info_tributaria(xml, emisor: emisor, clave_acceso: @clave_acceso, ambiente: @ambiente,
                                     tipo_emision: @tipo_emision, cod_doc: COD_DOC_FACTURA, secuencial: f.secuencial)

          xml.infoFactura do
            xml.fechaEmision fecha(f.fecha_emision)
            xml.dirEstablecimiento emisor.dir_establecimiento if emisor.dir_establecimiento
            xml.contribuyenteEspecial emisor.contribuyente_especial if emisor.contribuyente_especial
            xml.obligadoContabilidad emisor.obligado_contabilidad
            xml.tipoIdentificacionComprador comprador.tipo_identificacion
            xml.razonSocialComprador comprador.razon_social
            xml.identificacionComprador comprador.identificacion
            xml.direccionComprador comprador.direccion if comprador.direccion
            xml.totalSinImpuestos money(totales.total_sin_impuestos)
            xml.totalDescuento money(totales.total_descuento)
            xml.totalConImpuestos do
              totales.total_con_impuestos.each do |imp|
                xml.totalImpuesto do
                  xml.codigo imp.codigo
                  xml.codigoPorcentaje imp.codigo_porcentaje
                  xml.baseImponible money(imp.base_imponible)
                  xml.tarifa money(imp.tarifa) unless imp.tarifa.nil?
                  xml.valor money(imp.valor)
                end
              end
            end
            xml.importeTotal money(totales.importe_total)
            xml.moneda f.moneda if f.moneda
            xml.pagos do
              f.pagos.each do |pago|
                xml.pago do
                  xml.formaPago pago.forma_pago
                  xml.total money(pago.total)
                  if pago.plazo
                    xml.plazo pago.plazo
                    xml.unidadTiempo(pago.unidad_tiempo || "dias")
                  end
                end
              end
            end
          end

          xml.detalles do
            f.detalles.each do |d|
              xml.detalle do
                xml.codigoPrincipal(d.codigo_principal) if d.codigo_principal
                xml.codigoAuxiliar(d.codigo_auxiliar) if d.codigo_auxiliar
                xml.descripcion d.descripcion
                xml.unidadMedida(d.unidad_medida) if d.unidad_medida
                xml.cantidad qty(d.cantidad)
                xml.precioUnitario qty(d.precio_unitario)
                xml.descuento money(d.descuento)
                xml.precioTotalSinImpuesto money(d.precio_total_sin_impuesto)
                if d.respond_to?(:detalles_adicionales) && !Array(d.detalles_adicionales).empty?
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

          unless Array(f.info_adicional).empty?
            xml.infoAdicional do
              f.info_adicional.each do |campo|
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
