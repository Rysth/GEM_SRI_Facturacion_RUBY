# frozen_string_literal: true

require "bigdecimal"

module SriFacturacion
  module Models
    # Emisor de la factura (contribuyente que factura).
    # agente_retencion / contribuyente_rimpe: leyendas opcionales del SRI (infoTributaria).
    class Emisor
      attr_reader :ruc, :razon_social, :nombre_comercial, :dir_matriz, :dir_establecimiento,
                  :establecimiento, :punto_emision, :obligado_contabilidad, :contribuyente_especial,
                  :agente_retencion, :contribuyente_rimpe, :logo_data, :logo_content_type

      def initialize(ruc:, razon_social:, dir_matriz:, establecimiento: "001", punto_emision: "001",
                      nombre_comercial: nil, dir_establecimiento: nil, obligado_contabilidad: "NO",
                      contribuyente_especial: nil, agente_retencion: nil, contribuyente_rimpe: nil,
                      logo_data: nil, logo_content_type: nil)
        @ruc = ruc.to_s
        @razon_social = razon_social
        @nombre_comercial = nombre_comercial
        @dir_matriz = dir_matriz
        @dir_establecimiento = dir_establecimiento || dir_matriz
        @establecimiento = establecimiento.to_s.rjust(3, "0")
        @punto_emision = punto_emision.to_s.rjust(3, "0")
        @obligado_contabilidad = obligado_contabilidad
        @contribuyente_especial = contribuyente_especial
        @agente_retencion = agente_retencion
        @contribuyente_rimpe = contribuyente_rimpe
        @logo_data = logo_data
        @logo_content_type = logo_content_type
      end
    end

    # Comprador / cliente. tipo_identificacion: 04=RUC, 05=cédula, 06=pasaporte, 07=consumidor final.
    class Comprador
      CONSUMIDOR_FINAL = "9999999999999"

      attr_reader :tipo_identificacion, :identificacion, :razon_social, :direccion, :email, :telefono

      def initialize(razon_social:, tipo_identificacion: "07", identificacion: CONSUMIDOR_FINAL,
                     direccion: nil, email: nil, telefono: nil)
        @tipo_identificacion = tipo_identificacion.to_s
        @identificacion = identificacion.to_s
        @razon_social = razon_social
        @direccion = direccion
        @email = email
        @telefono = telefono
      end

      def self.consumidor_final
        new(razon_social: "CONSUMIDOR FINAL", tipo_identificacion: "07", identificacion: CONSUMIDOR_FINAL)
      end
    end

    # Impuesto de una línea. codigo "2"=IVA. codigo_porcentaje: "0"=0%, "4"=15% (vigente Ecuador 2024+).
    class Impuesto
      attr_reader :codigo, :codigo_porcentaje, :tarifa, :base_imponible, :valor

      def initialize(base_imponible:, valor:, codigo: "2", codigo_porcentaje: "4", tarifa: 15)
        @codigo = codigo.to_s
        @codigo_porcentaje = codigo_porcentaje.to_s
        @tarifa = tarifa
        @base_imponible = BigDecimal(base_imponible.to_s)
        @valor = BigDecimal(valor.to_s)
      end

      # IVA calculado sobre la base. Por defecto 15% (codigo_porcentaje "4").
      def self.iva(base, tarifa: 15, codigo_porcentaje: "4")
        base_d = BigDecimal(base.to_s)
        valor = (base_d * BigDecimal(tarifa.to_s) / 100).round(2)
        new(codigo: "2", codigo_porcentaje: codigo_porcentaje, tarifa: tarifa, base_imponible: base_d, valor: valor)
      end

      def self.iva_cero(base)
        new(codigo: "2", codigo_porcentaje: "0", tarifa: 0, base_imponible: BigDecimal(base.to_s), valor: 0)
      end

      # IVA 12% (codigo_porcentaje "2") — tarifa histórica anterior a abril 2024.
      def self.iva_doce(base)
        iva(base, tarifa: 12, codigo_porcentaje: "2")
      end

      # IVA exento (codigo_porcentaje "7"): base sin impuesto, valor 0.
      def self.iva_exento(base)
        new(codigo: "2", codigo_porcentaje: "7", tarifa: 0, base_imponible: BigDecimal(base.to_s), valor: 0)
      end

      # IVA no objeto de impuesto (codigo_porcentaje "6"): base sin impuesto, valor 0.
      def self.iva_no_objeto(base)
        new(codigo: "2", codigo_porcentaje: "6", tarifa: 0, base_imponible: BigDecimal(base.to_s), valor: 0)
      end
    end

    # Línea de detalle (compartida por factura y nota de crédito).
    # detalles_adicionales: lista opcional de hashes {nombre:, valor:} (solo nota de crédito).
    class Detalle
      attr_reader :codigo_principal, :codigo_auxiliar, :descripcion, :unidad_medida,
                  :cantidad, :precio_unitario, :descuento, :impuestos, :detalles_adicionales

      def initialize(descripcion:, cantidad: 1, precio_unitario: 0, descuento: 0, impuestos: [],
                     codigo_principal: nil, codigo_auxiliar: nil, unidad_medida: nil,
                     precio_total_sin_impuesto: nil, detalles_adicionales: [])
        @descripcion = descripcion
        @cantidad = BigDecimal(cantidad.to_s)
        @precio_unitario = BigDecimal(precio_unitario.to_s)
        @descuento = BigDecimal(descuento.to_s)
        @impuestos = impuestos
        @codigo_principal = codigo_principal
        @codigo_auxiliar = codigo_auxiliar
        @unidad_medida = unidad_medida
        @detalles_adicionales = detalles_adicionales || []
        @precio_total_sin_impuesto_override = precio_total_sin_impuesto && BigDecimal(precio_total_sin_impuesto.to_s)
      end

      # Precio total de la línea sin impuestos: cantidad * precio - descuento (o el override dado).
      def precio_total_sin_impuesto
        @precio_total_sin_impuesto_override || (@cantidad * @precio_unitario - @descuento)
      end
    end

    # Forma de pago. forma_pago "01"=sin sistema financiero, "20"=otros, "19"=tarjeta, etc.
    class Pago
      attr_reader :forma_pago, :total, :plazo, :unidad_tiempo

      def initialize(total:, forma_pago: "01", plazo: nil, unidad_tiempo: nil)
        @forma_pago = forma_pago.to_s
        @total = BigDecimal(total.to_s)
        @plazo = plazo
        @unidad_tiempo = unidad_tiempo
      end
    end

    # Factura completa.
    class Factura
      attr_reader :emisor, :comprador, :detalles, :pagos, :fecha_emision, :secuencial,
                  :moneda, :info_adicional, :tipo_emision

      def initialize(emisor:, comprador:, detalles:, fecha_emision: Date.today, secuencial: "1",
                     pagos: nil, moneda: "DOLAR", info_adicional: [], tipo_emision: "1")
        @emisor = emisor
        @comprador = comprador
        @detalles = detalles
        @fecha_emision = fecha_emision
        @secuencial = secuencial.to_s.rjust(9, "0")
        @moneda = moneda
        @info_adicional = info_adicional
        @tipo_emision = tipo_emision.to_s
        @totales = Totales.calculate(detalles)
        @pagos = pagos || [Pago.new(total: @totales.importe_total)]
      end

      def totales
        @totales
      end
    end

    # Nota de crédito (comprobante 04). Modifica un documento previamente emitido
    # (normalmente una factura): devoluciones, anulaciones o ajustes a la baja.
    #
    #   cod_doc_modificado:          tipo del documento modificado ("01" = factura)
    #   num_doc_modificado:          número del doc modificado, formato "001-001-000000001"
    #   fecha_emision_doc_sustento:  fecha del doc modificado (Date o "dd/mm/aaaa")
    #   motivo:                      razón de la nota de crédito
    #
    # Los totales (totalSinImpuestos, totalConImpuestos y valorModificacion) se calculan
    # a partir de los detalles, igual que en la factura.
    class NotaCredito
      attr_reader :emisor, :comprador, :detalles, :fecha_emision, :secuencial,
                  :cod_doc_modificado, :num_doc_modificado, :fecha_emision_doc_sustento,
                  :motivo, :moneda, :info_adicional, :tipo_emision

      def initialize(emisor:, comprador:, detalles:, cod_doc_modificado:, num_doc_modificado:,
                     fecha_emision_doc_sustento:, motivo:, fecha_emision: Date.today, secuencial: "1",
                     moneda: "DOLAR", info_adicional: [], tipo_emision: "1")
        @emisor = emisor
        @comprador = comprador
        @detalles = detalles
        @cod_doc_modificado = cod_doc_modificado.to_s.rjust(2, "0")
        @num_doc_modificado = num_doc_modificado.to_s
        @fecha_emision_doc_sustento = fecha_emision_doc_sustento
        @motivo = motivo
        @fecha_emision = fecha_emision
        @secuencial = secuencial.to_s.rjust(9, "0")
        @moneda = moneda
        @info_adicional = info_adicional
        @tipo_emision = tipo_emision.to_s
        @totales = Totales.calculate(detalles)
      end

      # valorModificacion (total de la nota) == importe_total de los totales calculados.
      def totales
        @totales
      end
    end
  end
end
