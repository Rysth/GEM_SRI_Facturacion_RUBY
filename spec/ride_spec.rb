# frozen_string_literal: true

require "spec_helper"
require "chunky_png"

RSpec.describe SriFacturacion::Ride do
  include FacturaHelpers

  let(:clave) { "3105202601092438363100110010010000000011234567813" }

  def pages(pdf) = pdf.scan(%r{/Type /Page\b}).size

  def png_logo
    image = ChunkyPNG::Image.new(300, 100, ChunkyPNG::Color.rgb(37, 99, 235))
    image.to_blob
  end

  it "draws the issuer's logo, a subtotal per IVA rate and the credit term" do
    sample = build_sample_factura
    sample.emisor.instance_variable_set(:@logo_data, png_logo)
    sample.emisor.instance_variable_set(:@logo_content_type, "image/png")
    envio = SriFacturacion::Detalle.new(codigo_principal: "ENVIO", descripcion: "Envío", cantidad: 1, precio_unitario: 3.0,
                                        descuento: 0, impuestos: [SriFacturacion::Impuesto.iva_cero(3.0)])
    factura = SriFacturacion::Factura.new(
      emisor: sample.emisor, comprador: sample.comprador, detalles: sample.detalles + [envio],
      fecha_emision: sample.fecha_emision, secuencial: "000000002",
      pagos: [SriFacturacion::Pago.new(forma_pago: "20", total: 10, plazo: 30, unidad_tiempo: "dias")]
    )
    ride = described_class.new(factura, clave_acceso: clave, numero_autorizacion: clave, fecha_autorizacion: "2026-05-31T10:00:00-05:00")

    rows = ride.send(:totals_rows).map(&:first)
    expect(rows).to eq(["Subtotal 15%", "Subtotal 0%", "Subtotal sin impuestos", "Descuento", "IVA 15%", "VALOR TOTAL"])
    expect(ride.send(:payment_term, factura.pagos.last)).to eq("30 días")
    pdf = ride.render
    expect(pdf).to start_with("%PDF")
    expect(pdf).to include("/Subtype /Image")
  end

  it "skips a logo it can't draw and flows onto more pages with many lines" do
    sample = build_sample_factura
    sample.emisor.instance_variable_set(:@logo_data, "not an image")
    sample.emisor.instance_variable_set(:@logo_content_type, "image/png")
    detalles = Array.new(80) do |index|
      SriFacturacion::Detalle.new(codigo_principal: "P#{index}", descripcion: "Producto #{index}", cantidad: 1,
                                  precio_unitario: 1.0, descuento: 0, impuestos: [SriFacturacion::Impuesto.iva(1.0)])
    end
    factura = SriFacturacion::Factura.new(emisor: sample.emisor, comprador: sample.comprador, detalles: detalles,
                                          fecha_emision: sample.fecha_emision, secuencial: "000000003")
    pdf = described_class.new(factura, clave_acceso: clave, ambiente: "2").render
    expect(pdf).to start_with("%PDF")
    expect(pages(pdf)).to be >= 2
  end
end
