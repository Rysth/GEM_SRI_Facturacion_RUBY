# frozen_string_literal: true

require "sri_facturacion"
require "openssl"
require "date"

module FacturaHelpers
  # Factura de ejemplo: 2 productos con IVA 15%.
  def build_sample_factura
    emisor = SriFacturacion::Emisor.new(
      ruc: "0924383631001",
      razon_social: "EDLU STORE S.A.",
      nombre_comercial: "EDLU Store",
      dir_matriz: "Guayaquil, Av. Principal 123",
      establecimiento: "001",
      punto_emision: "001",
      obligado_contabilidad: "NO"
    )
    comprador = SriFacturacion::Comprador.new(
      razon_social: "JUAN PEREZ",
      tipo_identificacion: "05",
      identificacion: "0926789017",
      direccion: "Quito",
      email: "juan@example.com"
    )
    detalles = [
      SriFacturacion::Detalle.new(
        codigo_principal: "GORRA-001", descripcion: "Gorra 9FORTY",
        cantidad: 2, precio_unitario: 20.0, descuento: 0,
        impuestos: [SriFacturacion::Impuesto.iva(40.0)]
      ),
      SriFacturacion::Detalle.new(
        codigo_principal: "ZAP-010", descripcion: "Zapato deportivo",
        cantidad: 1, precio_unitario: 55.0, descuento: 5.0,
        impuestos: [SriFacturacion::Impuesto.iva(50.0)]
      )
    ]
    SriFacturacion::Factura.new(
      emisor: emisor, comprador: comprador, detalles: detalles,
      fecha_emision: Date.new(2026, 5, 31), secuencial: "000000001"
    )
  end

  # Nota de crédito de ejemplo: devuelve una de las dos líneas de la factura de ejemplo.
  def build_sample_nota_credito
    emisor = SriFacturacion::Emisor.new(
      ruc: "0924383631001",
      razon_social: "EDLU STORE S.A.",
      nombre_comercial: "EDLU Store",
      dir_matriz: "Guayaquil, Av. Principal 123",
      establecimiento: "001",
      punto_emision: "001",
      obligado_contabilidad: "NO"
    )
    comprador = SriFacturacion::Comprador.new(
      razon_social: "JUAN PEREZ",
      tipo_identificacion: "05",
      identificacion: "0926789017",
      direccion: "Quito"
    )
    detalles = [
      SriFacturacion::Detalle.new(
        codigo_principal: "GORRA-001", descripcion: "Gorra 9FORTY",
        cantidad: 1, precio_unitario: 20.0, descuento: 0,
        impuestos: [SriFacturacion::Impuesto.iva(20.0)]
      )
    ]
    SriFacturacion::NotaCredito.new(
      emisor: emisor, comprador: comprador, detalles: detalles,
      cod_doc_modificado: "01", num_doc_modificado: "001-001-000000001",
      fecha_emision_doc_sustento: Date.new(2026, 5, 30),
      motivo: "Devolución de mercadería",
      fecha_emision: Date.new(2026, 5, 31), secuencial: "000000007"
    )
  end

  # Genera una clave RSA + certificado autofirmado para pruebas de firma (sin .p12 real del SRI).
  def build_test_signer
    key = OpenSSL::PKey::RSA.new(2048)
    name = OpenSSL::X509::Name.parse("/CN=Test Emisor/O=EDLU/C=EC")
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 12_345
    cert.subject = name
    cert.issuer = name
    cert.public_key = key.public_key
    cert.not_before = Time.now - 3600
    cert.not_after = Time.now + (365 * 24 * 3600)
    cert.sign(key, OpenSSL::Digest::SHA256.new)
    SriFacturacion::Signer.new(key: key, certificate: cert)
  end
end

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.include FacturaHelpers
  config.before { SriFacturacion.reset_configuration! }
end
