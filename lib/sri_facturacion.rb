# frozen_string_literal: true

require_relative "sri_facturacion/version"
require_relative "sri_facturacion/errors"
require_relative "sri_facturacion/configuration"
require_relative "sri_facturacion/access_key"
require_relative "sri_facturacion/identificacion_validator"
require_relative "sri_facturacion/totales"
require_relative "sri_facturacion/models"
require_relative "sri_facturacion/xml_support"
require_relative "sri_facturacion/xml_builder"
require_relative "sri_facturacion/nota_credito_xml_builder"
require_relative "sri_facturacion/signer"
require_relative "sri_facturacion/result"
require_relative "sri_facturacion/soap_client"
require_relative "sri_facturacion/ride"
require_relative "sri_facturacion/client"

# Facturación electrónica SRI Ecuador (factura 01) en Ruby puro.
# Modo PRUEBAS (ambiente "1") por defecto. Ver README.
module SriFacturacion
  # Atajos a los modelos para no escribir el namespace Models:: cada vez.
  Emisor = Models::Emisor
  Comprador = Models::Comprador
  Impuesto = Models::Impuesto
  Detalle = Models::Detalle
  Pago = Models::Pago
  Factura = Models::Factura
  NotaCredito = Models::NotaCredito

  # Conveniencia: emite una factura con la configuración global.
  #   SriFacturacion.emitir!(factura)
  def self.emitir!(factura, **opts)
    Client.new.emitir!(factura, **opts)
  end

  # Conveniencia: emite una nota de crédito con la configuración global.
  #   SriFacturacion.emitir_nota_credito!(nota_credito)
  def self.emitir_nota_credito!(nota_credito, **opts)
    Client.new.emitir_nota_credito!(nota_credito, **opts)
  end
end
