# frozen_string_literal: true

require "date"
require "securerandom"

module SriFacturacion
  # Genera y valida la clave de acceso de 49 dígitos del SRI.
  #
  # Estructura (49 dígitos):
  #   [0-7]   fecha de emisión ddmmaaaa
  #   [8-9]   tipo de comprobante (01=factura)
  #   [10-22] RUC del emisor (13)
  #   [23]    ambiente (1=pruebas, 2=producción)
  #   [24-26] establecimiento (3)
  #   [27-29] punto de emisión (3)
  #   [30-38] secuencial (9)
  #   [39-46] código numérico (8)
  #   [47]    tipo de emisión (1=normal)
  #   [48]    dígito verificador (módulo 11)
  #
  # Port fiel de clave-acceso.service.ts.
  class AccessKey
    FACTURA = "01"
    NOTA_CREDITO = "04"
    NOTA_DEBITO = "05"
    GUIA_REMISION = "06"
    COMPROBANTE_RETENCION = "07"
    NORMAL = "1"
    PRUEBAS = "1"

    class << self
      # data: hash con :fecha_emision (Date/Time), :tipo_comprobante, :ruc, :ambiente,
      # :establecimiento, :punto_emision, :secuencial, :codigo_numerico (opcional), :tipo_emision
      def generate(fecha_emision:, ruc:, establecimiento:, punto_emision:, secuencial:,
                   tipo_comprobante: FACTURA, ambiente: PRUEBAS, codigo_numerico: nil, tipo_emision: NORMAL)
        fecha = format_date(fecha_emision)
        tipo = tipo_comprobante.to_s.rjust(2, "0")
        ruc_v = validate_ruc(ruc)
        amb = ambiente.to_s
        estab = establecimiento.to_s.rjust(3, "0")
        punto = punto_emision.to_s.rjust(3, "0")
        sec = secuencial.to_s.rjust(9, "0")
        codigo = (codigo_numerico || random_codigo_numerico).to_s.rjust(8, "0")
        emision = tipo_emision.to_s

        base = "#{fecha}#{tipo}#{ruc_v}#{amb}#{estab}#{punto}#{sec}#{codigo}#{emision}"
        "#{base}#{modulo11(base)}"
      end

      def valid?(clave)
        return false unless clave.is_a?(String) && clave.length == 49
        return false unless clave.match?(/\A\d{49}\z/)

        base = clave[0, 48]
        clave[48] == modulo11(base)
      end

      # Devuelve un hash con los componentes, o nil si la clave es inválida.
      def parse(clave)
        return nil unless valid?(clave)

        fecha_str = clave[0, 8]
        {
          fecha_emision: Date.new(fecha_str[4, 4].to_i, fecha_str[2, 2].to_i, fecha_str[0, 2].to_i),
          tipo_comprobante: clave[8, 2],
          ruc: clave[10, 13],
          ambiente: clave[23],
          establecimiento: clave[24, 3],
          punto_emision: clave[27, 3],
          secuencial: clave[30, 9],
          codigo_numerico: clave[39, 8],
          tipo_emision: clave[47]
        }
      end

      private

      def format_date(date)
        d = date.respond_to?(:to_date) ? date.to_date : date
        format("%02d%02d%04d", d.day, d.month, d.year)
      end

      def validate_ruc(ruc)
        clean = ruc.to_s.gsub(/\D/, "")
        raise ValidationError, "RUC inválido: debe tener 13 dígitos" unless clean.length == 13

        clean
      end

      def random_codigo_numerico
        SecureRandom.random_number(90_000_000) + 10_000_000 # 8 dígitos
      end

      # Módulo 11 con factores cíclicos [2..7] recorriendo de derecha a izquierda.
      def modulo11(base)
        factores = [2, 3, 4, 5, 6, 7]
        suma = 0
        j = 0
        (base.length - 1).downto(0) do |i|
          suma += base[i].to_i * factores[j % factores.length]
          j += 1
        end

        dv = 11 - (suma % 11)
        dv = 0 if dv == 11
        dv = 1 if dv == 10
        dv.to_s
      end
    end
  end
end
