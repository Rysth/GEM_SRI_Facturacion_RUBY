# frozen_string_literal: true

module SriFacturacion
  # Valida identificaciones ecuatorianas (cédula módulo 10, RUC módulo 11 según
  # el tipo de contribuyente, pasaporte y consumidor final). Port de
  # identificacion-validator.service.ts.
  #
  # Útil para no enviar al SRI un comprobante con una identificación de comprador
  # mal formada (causa de rechazo). Devuelve un Resultado(valido?, error).
  module IdentificacionValidator
    Resultado = Struct.new(:valido, :error) do
      def valido?
        valido
      end
    end

    CONSUMIDOR_FINAL = "9999999999999"

    module_function

    # tipo: "04" RUC, "05" cédula, "06" pasaporte, "07" consumidor final, "08" exterior.
    def validar(tipo, identificacion)
      case tipo.to_s
      when "04" then validar_ruc(identificacion)
      when "05" then validar_cedula(identificacion)
      when "06" then validar_pasaporte(identificacion)
      when "07" then validar_consumidor_final(identificacion)
      when "08" then ok # identificación del exterior: no se valida estructura
      else
        Resultado.new(false, "Tipo de identificación #{tipo} no reconocido")
      end
    end

    # Conveniencia booleana.
    def valido?(tipo, identificacion)
      validar(tipo, identificacion).valido?
    end

    def validar_cedula(cedula)
      cedula = cedula.to_s
      return Resultado.new(false, "La cédula debe tener exactamente 10 dígitos numéricos") unless cedula.match?(/\A\d{10}\z/)

      provincia = cedula[0, 2].to_i
      return Resultado.new(false, "Código de provincia #{provincia} inválido (debe ser 01-24)") unless provincia.between?(1, 24)

      tercer = cedula[2].to_i
      return Resultado.new(false, "El tercer dígito de la cédula debe ser menor o igual a 5") if tercer > 5

      esperado = modulo10(cedula)
      return Resultado.new(false, "Dígito verificador incorrecto. Esperado: #{esperado}") unless esperado == cedula[9].to_i

      ok
    end

    def validar_ruc(ruc)
      ruc = ruc.to_s
      return Resultado.new(false, "El RUC debe tener exactamente 13 dígitos numéricos") unless ruc.match?(/\A\d{13}\z/)

      provincia = ruc[0, 2].to_i
      return Resultado.new(false, "Código de provincia #{provincia} inválido (debe ser 01-24)") unless provincia.between?(1, 24)

      case ruc[2].to_i
      when 0..5 then validar_ruc_persona_natural(ruc)
      when 6 then validar_ruc_sociedad_publica(ruc)
      when 9 then validar_ruc_sociedad_privada(ruc)
      else
        Resultado.new(false, "Tercer dígito del RUC inválido")
      end
    end

    def validar_pasaporte(pasaporte)
      pasaporte = pasaporte.to_s
      return Resultado.new(false, "El pasaporte debe tener entre 5 y 20 caracteres") unless pasaporte.length.between?(5, 20)

      ok
    end

    def validar_consumidor_final(identificacion)
      return ok if identificacion.to_s == CONSUMIDOR_FINAL

      Resultado.new(false, "Consumidor final debe usar identificación #{CONSUMIDOR_FINAL}")
    end

    # ---- helpers privados ----

    def ok
      Resultado.new(true)
    end

    # Cédula: módulo 10 sobre los 9 primeros dígitos.
    def modulo10(cedula)
      coef = [2, 1, 2, 1, 2, 1, 2, 1, 2]
      suma = (0..8).sum do |i|
        valor = cedula[i].to_i * coef[i]
        valor > 9 ? valor - 9 : valor
      end
      residuo = suma % 10
      residuo.zero? ? 0 : 10 - residuo
    end

    def validar_ruc_persona_natural(ruc)
      return Resultado.new(false, "Código de establecimiento del RUC inválido") if ruc[10, 3].to_i < 1

      cedula = validar_cedula(ruc[0, 10])
      return Resultado.new(false, "RUC persona natural: #{cedula.error}") unless cedula&.valido?

      ok
    end

    # Sociedad privada: módulo 11 con coeficientes [4,3,2,7,6,5,4,3,2], DV en pos 10, termina en 001.
    def validar_ruc_sociedad_privada(ruc)
      dv = modulo11(ruc, [4, 3, 2, 7, 6, 5, 4, 3, 2], 9)
      return Resultado.new(false, "RUC sociedad privada: dígito verificador incorrecto") unless dv == ruc[9].to_i
      return Resultado.new(false, "RUC sociedad privada debe terminar en 001") unless ruc[10, 3] == "001"

      ok
    end

    # Sociedad pública: módulo 11 con coeficientes [3,2,7,6,5,4,3,2], DV en pos 9, termina en 0001.
    def validar_ruc_sociedad_publica(ruc)
      dv = modulo11(ruc, [3, 2, 7, 6, 5, 4, 3, 2], 8)
      return Resultado.new(false, "RUC sociedad pública: dígito verificador incorrecto") unless dv == ruc[8].to_i
      return Resultado.new(false, "RUC sociedad pública debe terminar en 0001") unless ruc[9, 4] == "0001"

      ok
    end

    def modulo11(numero, coeficientes, count)
      suma = (0...count).sum { |i| numero[i].to_i * coeficientes[i] }
      residuo = suma % 11
      residuo.zero? ? 0 : 11 - residuo
    end
  end
end
