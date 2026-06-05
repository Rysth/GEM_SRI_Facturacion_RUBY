# frozen_string_literal: true

require "prawn"
require "prawn/table"
require "rqrcode"
require "date"
require "stringio"
require "time"

module SriFacturacion
  # Genera el RIDE (Representacion Impresa del Documento Electronico) en PDF.
  # PDF en Ruby puro con Prawn; QR con URL verificable o datos clave del comprobante.
  class Ride
    INK = "111827"
    MUTED = "64748B"
    BORDER = "D1D5DB"
    SOFT = "F8FAFC"
    PANEL = "F1F5F9"
    DARK = "0F172A"
    BLUE = "1D4ED8"
    GREEN = "15803D"
    AMBER = "B45309"
    WHITE = "FFFFFF"

    PAYMENT_LABELS = {
      "01" => "Sin utilizacion del sistema financiero",
      "15" => "Compensacion de deudas",
      "16" => "Tarjeta de debito",
      "17" => "Dinero electronico",
      "18" => "Tarjeta prepago",
      "19" => "Tarjeta de credito",
      "20" => "Otros con utilizacion del sistema financiero",
      "21" => "Endoso de titulos"
    }.freeze

    def initialize(factura, clave_acceso:, numero_autorizacion: nil, fecha_autorizacion: nil, ambiente: "1",
                   verification_url: nil, qr_content: nil)
      @factura = factura
      @clave_acceso = clave_acceso.to_s
      @numero_autorizacion = numero_autorizacion
      @fecha_autorizacion = fecha_autorizacion
      @ambiente = ambiente.to_s
      @verification_url = verification_url
      @qr_content = qr_content
    end

    def render
      Prawn::Document.new(page_size: "A4", margin: [28, 32, 42, 32]) do |pdf|
        Prawn::Fonts::AFM.hide_m17n_warning = true if defined?(Prawn::Fonts::AFM)
        pdf.font "Helvetica"

        draw_footer(pdf)
        draw_header(pdf)
        draw_authorization_panel(pdf)
        draw_buyer_panel(pdf)
        draw_details_table(pdf)
        draw_totals_and_payments(pdf)
        draw_additional_info(pdf)
        draw_page_numbers(pdf)
      end.render
    end

    private

    def draw_header(pdf)
      emisor = @factura.emisor
      number = document_number
      top = pdf.cursor
      full_width = pdf.bounds.width
      document_box_width = 205
      issuer_width = full_width - document_box_width - 18

      pdf.fill_color DARK
      pdf.fill_rectangle [0, top], full_width, 5
      pdf.move_down 18
      top = pdf.cursor

      pdf.bounding_box([0, top], width: issuer_width, height: 122) do
        if draw_logo(pdf, emisor, max_width: 110, max_height: 34)
          pdf.move_down 40
        end

        pdf.fill_color INK
        pdf.text safe_upcase(emisor.razon_social), size: 15, style: :bold, leading: 1

        if present?(emisor.nombre_comercial) && emisor.nombre_comercial.to_s != emisor.razon_social.to_s
          pdf.move_down 2
          pdf.fill_color BLUE
          pdf.text emisor.nombre_comercial.to_s, size: 10, style: :bold
        end

        pdf.move_down 8
        key_value(pdf, "RUC", emisor.ruc)
        key_value(pdf, "Direccion matriz", emisor.dir_matriz)
        key_value(pdf, "Direccion establecimiento", emisor.dir_establecimiento) if present?(emisor.dir_establecimiento)
        key_value(pdf, "Obligado contabilidad", emisor.obligado_contabilidad) if present?(emisor.obligado_contabilidad)
        key_value(pdf, "Contribuyente especial", emisor.contribuyente_especial) if present?(emisor.contribuyente_especial)
        pdf.fill_color MUTED
        pdf.text emisor.contribuyente_rimpe.to_s, size: 8 if present?(emisor.contribuyente_rimpe)
      end

      pdf.bounding_box([full_width - document_box_width, top], width: document_box_width, height: 122) do
        rounded_panel(pdf, document_box_width, 122, fill: PANEL)
        pdf.move_down 12
        pdf.indent(13, 13) do
          pdf.fill_color DARK
          pdf.text "FACTURA", size: 19, style: :bold, align: :right
          pdf.fill_color MUTED
          pdf.text "No. #{number}", size: 10, style: :bold, align: :right
          pdf.move_down 10
          badge(pdf, ambiente_label, @ambiente == "2" ? GREEN : AMBER)
          pdf.move_down 9
          key_value(pdf, "Fecha emision", format_fecha(@factura.fecha_emision), label_width: 78, size: 8.3)
          key_value(pdf, "Tipo emision", @factura.tipo_emision, label_width: 78, size: 8.3)
          key_value(pdf, "Moneda", @factura.moneda, label_width: 78, size: 8.3)
        end
      end

      pdf.move_cursor_to top - 136
    end

    def draw_logo(pdf, emisor, max_width:, max_height:)
      return unless logo_present?(emisor)
      return unless supported_logo?(emisor)

      pdf.image StringIO.new(emisor.logo_data), fit: [max_width, max_height], at: [0, pdf.cursor]
      true
    rescue StandardError
      nil
    end

    def logo_present?(emisor)
      emisor.respond_to?(:logo_data) && present?(emisor.logo_data)
    end

    def supported_logo?(emisor)
      %w[image/png image/jpeg image/jpg].include?(emisor.logo_content_type.to_s.downcase)
    end

    def draw_authorization_panel(pdf)
      full_width = pdf.bounds.width
      qr_size = 92
      panel_height = 120
      top = pdf.cursor

      rounded_panel(pdf, full_width, panel_height, fill: WHITE)

      pdf.bounding_box([12, top - 12], width: full_width - qr_size - 34, height: panel_height - 24) do
        section_label(pdf, "AUTORIZACION SRI")
        key_value(pdf, "Estado", "DOCUMENTO AUTORIZADO", label_width: 98, value_color: GREEN, bold_value: true)
        key_value(pdf, "Numero autorizacion", authorization_number, label_width: 98, size: 7.4)
        key_value(pdf, "Fecha autorizacion", format_datetime(@fecha_autorizacion), label_width: 98)
        pdf.move_down 5
        pdf.fill_color MUTED
        pdf.text "Clave de acceso", size: 7.5, style: :bold
        pdf.fill_color INK
        pdf.text @clave_acceso, size: 8, style: :bold, character_spacing: 0.2
      end

      pdf.bounding_box([full_width - qr_size - 12, top - 12], width: qr_size, height: qr_size + 16) do
        pdf.fill_color SOFT
        pdf.fill_rounded_rectangle [0, qr_size + 12], qr_size, qr_size + 12, 5
        pdf.stroke_color BORDER
        pdf.stroke_rounded_rectangle [0, qr_size + 12], qr_size, qr_size + 12, 5
        pdf.image qr_png_io(qr_payload), width: qr_size - 16, at: [8, qr_size + 4]
        pdf.fill_color MUTED
        pdf.text_box "Verificacion", at: [0, 10], width: qr_size, height: 9, size: 6.5, align: :center
      end

      pdf.move_cursor_to top - panel_height - 14
    end

    def draw_buyer_panel(pdf)
      comprador = @factura.comprador
      full_width = pdf.bounds.width
      top = pdf.cursor
      panel_height = 84

      pdf.fill_color SOFT
      pdf.fill_rounded_rectangle [0, top], full_width, panel_height, 6
      pdf.stroke_color BORDER
      pdf.stroke_rounded_rectangle [0, top], full_width, panel_height, 6

      pdf.bounding_box([12, top - 11], width: full_width - 24, height: panel_height - 18) do
        section_label(pdf, "DATOS DEL COMPRADOR")
        left_width = (full_width - 34) * 0.55
        right_width = full_width - 34 - left_width
        current = pdf.cursor

        pdf.bounding_box([0, current], width: left_width, height: 48) do
          key_value(pdf, "Razon social", comprador.razon_social, label_width: 82)
          key_value(pdf, "Identificacion", comprador.identificacion, label_width: 82)
          key_value(pdf, "Direccion", comprador.direccion, label_width: 82) if present?(comprador.direccion)
        end

        pdf.bounding_box([left_width + 10, current], width: right_width, height: 48) do
          key_value(pdf, "Email", comprador.email, label_width: 58) if present?(comprador.email)
          key_value(pdf, "Telefono", comprador.telefono, label_width: 58) if present?(comprador.telefono)
          key_value(pdf, "Fecha", format_fecha(@factura.fecha_emision), label_width: 58)
        end
      end

      pdf.move_cursor_to top - panel_height - 14
    end

    def draw_details_table(pdf)
      pdf.fill_color DARK
      pdf.text "DETALLE DE LA FACTURA", size: 9, style: :bold
      pdf.move_down 6

      table_width = pdf.bounds.width
      code_w = 67
      qty_w = 42
      unit_w = 58
      discount_w = 48
      total_w = 58
      desc_w = table_width - code_w - qty_w - unit_w - discount_w - total_w

      rows = [["Codigo", "Descripcion", "Cant.", "P. Unit.", "Desc.", "Subtotal"]]
      @factura.detalles.each do |detail|
        rows << [
          detail.codigo_principal.to_s,
          detail.descripcion.to_s,
          fmt(detail.cantidad),
          money(detail.precio_unitario),
          money(detail.descuento),
          money(detail.precio_total_sin_impuesto)
        ]
      end

      pdf.table(rows, header: true, width: table_width,
                      cell_style: { size: 7.8, padding: [6, 6], border_width: 0.35, border_color: BORDER },
                      column_widths: [code_w, desc_w, qty_w, unit_w, discount_w, total_w]) do
        row(0).background_color = DARK
        row(0).text_color = WHITE
        row(0).font_style = :bold
        row(0).size = 7.3
        columns(2..5).align = :right
        columns(0).overflow = :shrink_to_fit
        columns(0).min_font_size = 5.8
        columns(1).overflow = :shrink_to_fit
        columns(1).min_font_size = 6.2
        (1...rows.length).each { |index| row(index).background_color = SOFT if index.even? }
      end
    end

    def draw_totals_and_payments(pdf)
      pdf.move_down 14
      full_width = pdf.bounds.width
      payments_width = full_width - 255 - 18
      totals_width = 255
      top = pdf.cursor

      pdf.bounding_box([0, top], width: payments_width) do
        section_label(pdf, "FORMA DE PAGO")
        payment_rows = @factura.pagos.map do |payment|
          [payment_label(payment.forma_pago), money(payment.total)]
        end
        payment_rows = [["No especificada", money(@factura.totales.importe_total)]] if payment_rows.empty?

        pdf.table(payment_rows, width: payments_width,
                              cell_style: { size: 8, padding: [6, 7], border_width: 0.35, border_color: BORDER },
                              column_widths: [payments_width - 76, 76]) do
          columns(1).align = :right
          columns(1).font_style = :bold
        end
      end

      pdf.bounding_box([full_width - totals_width, top], width: totals_width) do
        totals = @factura.totales
        rows = [
          ["Subtotal sin impuestos", money(totals.total_sin_impuestos)],
          ["Descuento", money(totals.total_descuento)]
        ]
        totals.total_con_impuestos.each do |tax|
          rows << ["IVA #{fmt(tax.tarifa)}%", money(tax.valor)]
        end
        rows << ["VALOR TOTAL", money(totals.importe_total)]

        pdf.table(rows, width: totals_width,
                        cell_style: { size: 8.5, padding: [6, 8], border_width: 0.35, border_color: BORDER },
                        column_widths: [158, 97]) do
          columns(1).align = :right
          columns(1).font_style = :bold
          (0...rows.length - 1).each { |index| row(index).background_color = SOFT if index.even? }
          row(-1).background_color = DARK
          row(-1).text_color = WHITE
          row(-1).font_style = :bold
          row(-1).size = 10.5
          row(-1).padding = [8, 8]
        end
      end

      pdf.move_cursor_to [pdf.cursor, top - 88].min
    end

    def draw_additional_info(pdf)
      return unless @factura.info_adicional.respond_to?(:any?) && @factura.info_adicional.any?

      pdf.move_down 10
      section_label(pdf, "INFORMACION ADICIONAL")
      rows = @factura.info_adicional.map do |item|
        if item.respond_to?(:fetch)
          [item[:nombre] || item["nombre"], item[:valor] || item["valor"]]
        else
          ["Info", item.to_s]
        end
      end

      pdf.table(rows, width: pdf.bounds.width,
                      cell_style: { size: 8, padding: [5, 7], border_width: 0.35, border_color: BORDER },
                      column_widths: [120, pdf.bounds.width - 120]) do
        columns(0).font_style = :bold
        columns(0).text_color = MUTED
      end
    end

    def draw_footer(pdf)
      pdf.repeat(:all) do
        pdf.canvas do
          pdf.bounding_box([pdf.bounds.left, pdf.bounds.bottom + 24], width: pdf.bounds.width, height: 22) do
            pdf.stroke_color BORDER
            pdf.stroke_horizontal_rule
            pdf.move_down 6
            pdf.fill_color MUTED
            pdf.text "RIDE generado por StockManager by RysthDesign  ·  www.rysthdesign.com",
                     size: 7, align: :center
          end
        end
      end
    end

    def draw_page_numbers(pdf)
      pdf.number_pages "Pagina <page> de <total>", at: [pdf.bounds.right - 76, 16], width: 76,
                                                   size: 7, align: :right, color: MUTED
    end

    def rounded_panel(pdf, width, height, fill: SOFT)
      top = pdf.cursor
      pdf.fill_color fill
      pdf.fill_rounded_rectangle [0, top], width, height, 6
      pdf.stroke_color BORDER
      pdf.line_width 0.6
      pdf.stroke_rounded_rectangle [0, top], width, height, 6
    end

    def badge(pdf, text, color)
      pdf.fill_color color
      pdf.fill_rounded_rectangle [0, pdf.cursor], 176, 18, 4
      pdf.fill_color WHITE
      pdf.text_box text, at: [0, pdf.cursor - 4], width: 176, height: 12, size: 8, style: :bold, align: :center
      pdf.move_down 18
    end

    def section_label(pdf, text)
      pdf.fill_color DARK
      pdf.text text, size: 7.8, style: :bold, character_spacing: 0.4
      pdf.move_down 5
    end

    def key_value(pdf, label, value, label_width: 92, size: 8.5, value_color: INK, bold_value: false)
      return unless present?(value)

      y = pdf.cursor
      pdf.fill_color MUTED
      pdf.text_box "#{label}:", at: [0, y], width: label_width, height: 12, size: size, style: :bold
      pdf.fill_color value_color
      pdf.text_box value.to_s, at: [label_width, y], width: pdf.bounds.width - label_width, height: 16,
                             size: size, style: bold_value ? :bold : :normal, overflow: :shrink_to_fit,
                             min_font_size: 6
      pdf.move_down 12
    end

    def qr_png_io(content)
      qr = RQRCode::QRCode.new(content.to_s)
      png = qr.as_png(size: 260, border_modules: 2)
      StringIO.new(png.to_s)
    end

    def qr_payload
      return @qr_content.to_s if present?(@qr_content)
      return verification_url if present?(@verification_url)

      [
        "RIDE FACTURA",
        "RUC=#{@factura.emisor.ruc}",
        "COMPROBANTE=#{document_number}",
        "CLAVE=#{@clave_acceso}",
        "AUTORIZACION=#{authorization_number}",
        "FECHA=#{format_fecha(@factura.fecha_emision)}",
        "TOTAL=#{amount(@factura.totales.importe_total)}",
        "AMBIENTE=#{ambiente_label}"
      ].join("\n")
    end

    def verification_url
      base = @verification_url.to_s.strip.sub(%r{/+\z}, "")
      "#{base}/#{@clave_acceso}"
    end

    def document_number
      emisor = @factura.emisor
      "#{emisor.establecimiento}-#{emisor.punto_emision}-#{@factura.secuencial}"
    end

    def authorization_number
      (@numero_autorizacion || @clave_acceso).to_s
    end

    def ambiente_label
      @ambiente == "2" ? "PRODUCCION" : "PRUEBAS"
    end

    def payment_label(code)
      code = code.to_s
      PAYMENT_LABELS.fetch(code, "Forma de pago #{code}")
    end

    def money(value)
      "$#{amount(value)}"
    end

    def amount(value)
      format("%.2f", value.to_f)
    end

    def fmt(value)
      number = value.to_f
      number == number.to_i ? format("%d", number) : format("%.2f", number)
    end

    def format_fecha(date)
      d = date.respond_to?(:to_date) ? date.to_date : Date.parse(date.to_s)
      format("%02d/%02d/%04d", d.day, d.month, d.year)
    rescue StandardError
      date.to_s
    end

    def format_datetime(value)
      return "" unless present?(value)

      time = Time.parse(value.to_s)
      time.strftime("%d/%m/%Y %H:%M:%S")
    rescue StandardError
      value.to_s
    end

    def present?(value)
      !value.nil? && value.to_s.strip != ""
    end

    def safe_upcase(value)
      value.to_s.upcase
    end
  end
end
