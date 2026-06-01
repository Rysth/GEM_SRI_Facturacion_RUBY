# frozen_string_literal: true

require "bigdecimal"

module SriFacturacion
  # Aritmética fiscal de la factura con BigDecimal (sin pérdida de precisión IEEE-754).
  # Port de FacturaService#calculateTotales.
  module Totales
    Resultado = Struct.new(:total_sin_impuestos, :total_descuento, :total_con_impuestos, :importe_total)

    # ImpuestoTotal agrupado por codigo + codigo_porcentaje.
    ImpuestoTotal = Struct.new(:codigo, :codigo_porcentaje, :base_imponible, :valor, :tarifa)

    module_function

    # detalles: array de objetos que responden a precio_total_sin_impuesto, descuento, impuestos.
    # Cada impuesto responde a codigo, codigo_porcentaje, base_imponible, valor, tarifa.
    def calculate(detalles)
      total_sin = BigDecimal("0")
      total_desc = BigDecimal("0")
      grupos = {}

      detalles.each do |d|
        total_sin += to_d(d.precio_total_sin_impuesto)
        total_desc += to_d(d.descuento)

        Array(d.impuestos).each do |imp|
          key = "#{imp.codigo}|#{imp.codigo_porcentaje}"
          grupo = grupos[key] ||= ImpuestoTotal.new(imp.codigo, imp.codigo_porcentaje, BigDecimal("0"), BigDecimal("0"), imp.tarifa)
          grupo.base_imponible += to_d(imp.base_imponible)
          grupo.valor += to_d(imp.valor)
        end
      end

      total_con = grupos.values.map do |g|
        ImpuestoTotal.new(g.codigo, g.codigo_porcentaje, round2(g.base_imponible), round2(g.valor), g.tarifa)
      end

      total_impuestos = grupos.values.sum(BigDecimal("0"), &:valor)
      importe_total = round2(total_sin + total_impuestos)

      Resultado.new(round2(total_sin), round2(total_desc), total_con, importe_total)
    end

    def to_d(value)
      value.is_a?(BigDecimal) ? value : BigDecimal(value.to_s)
    end

    def round2(value)
      to_d(value).round(2)
    end
  end
end
