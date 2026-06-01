# frozen_string_literal: true

# Port de factura-totales.spec.ts — aritmética fiscal con BigDecimal.
RSpec.describe SriFacturacion::Totales do
  def detalle(precio_total, descuento, impuestos)
    SriFacturacion::Detalle.new(
      descripcion: "x",
      precio_total_sin_impuesto: precio_total,
      descuento: descuento,
      impuestos: impuestos.map { |i| SriFacturacion::Impuesto.new(**i) }
    )
  end

  it "suma totales sin pérdida de precisión IEEE-754" do
    detalles = [
      detalle(0.1, 0, [{ codigo: "2", codigo_porcentaje: "4", tarifa: 15, base_imponible: 0.1, valor: 0.015 }]),
      detalle(0.2, 0, [{ codigo: "2", codigo_porcentaje: "4", tarifa: 15, base_imponible: 0.2, valor: 0.03 }])
    ]
    r = described_class.calculate(detalles)
    expect(r.total_sin_impuestos.to_f).to eq(0.3)
    expect(r.total_descuento.to_f).to eq(0.0)
  end

  it "acumula impuestos por código correctamente" do
    detalles = [
      detalle(10, 0, [{ codigo: "2", codigo_porcentaje: "4", tarifa: 15, base_imponible: 10, valor: 1.5 }]),
      detalle(20, 0, [{ codigo: "2", codigo_porcentaje: "4", tarifa: 15, base_imponible: 20, valor: 3.0 }])
    ]
    r = described_class.calculate(detalles)
    expect(r.total_sin_impuestos.to_f).to eq(30.0)
    expect(r.total_con_impuestos.length).to eq(1)
    expect(r.total_con_impuestos[0].base_imponible.to_f).to eq(30.0)
    expect(r.total_con_impuestos[0].valor.to_f).to eq(4.5)
    expect(r.importe_total.to_f).to eq(34.5)
  end

  it "maneja múltiples tarifas de impuesto separadas" do
    detalles = [
      detalle(100, 0, [{ codigo: "2", codigo_porcentaje: "4", tarifa: 15, base_imponible: 100, valor: 15 }]),
      detalle(50, 0, [{ codigo: "2", codigo_porcentaje: "0", tarifa: 0, base_imponible: 50, valor: 0 }])
    ]
    r = described_class.calculate(detalles)
    expect(r.total_sin_impuestos.to_f).to eq(150.0)
    expect(r.total_con_impuestos.length).to eq(2)
    expect(r.importe_total.to_f).to eq(165.0)
  end

  it "redondea importeTotal a 2 decimales" do
    detalles = [
      detalle(0.17, 0, [{ codigo: "2", codigo_porcentaje: "4", tarifa: 15, base_imponible: 0.17, valor: 0.03 }]),
      detalle(0.19, 0, [{ codigo: "2", codigo_porcentaje: "4", tarifa: 15, base_imponible: 0.19, valor: 0.03 }])
    ]
    r = described_class.calculate(detalles)
    expect(r.total_sin_impuestos.to_f).to eq(0.36)
    expect(r.total_con_impuestos[0].valor.to_f).to eq(0.06)
    expect(r.importe_total.to_f).to eq(0.42)
  end

  it "acumula descuentos correctamente" do
    detalles = [
      detalle(8, 2, [{ codigo: "2", codigo_porcentaje: "4", tarifa: 15, base_imponible: 8, valor: 1.2 }]),
      detalle(15, 5, [{ codigo: "2", codigo_porcentaje: "4", tarifa: 15, base_imponible: 15, valor: 2.25 }])
    ]
    r = described_class.calculate(detalles)
    expect(r.total_descuento.to_f).to eq(7.0)
    expect(r.total_sin_impuestos.to_f).to eq(23.0)
    expect(r.importe_total.to_f).to eq(26.45)
  end

  it "maneja un solo detalle con IVA 0%" do
    detalles = [
      detalle(100, 0, [{ codigo: "2", codigo_porcentaje: "0", tarifa: 0, base_imponible: 100, valor: 0 }])
    ]
    r = described_class.calculate(detalles)
    expect(r.total_sin_impuestos.to_f).to eq(100.0)
    expect(r.importe_total.to_f).to eq(100.0)
  end
end
