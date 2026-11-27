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
      "01" => "Sin utilización del sistema financiero",
      "15" => "Compensación de deudas",
      "16" => "Tarjeta de débito",
      "17" => "Dinero electrónico",
      "18" => "Tarjeta prepago",
      "19" => "Tarjeta de crédito",
      "20" => "Otros con utilización del sistema financiero",
      "21" => "Endoso de títulos"
    }.freeze

    # factura: una Models::Factura o una Models::NotaCredito.
    def initialize(factura, clave_acceso:, numero_autorizacion: nil, fecha_autorizacion: nil, ambiente: "1",
                   verification_url: nil, qr_content: nil, footer: nil)
      @factura = factura
      @nota_credito = factura.is_a?(Models::NotaCredito)
      @footer = footer || Configuration::DEFAULT_RIDE_FOOTER
      @clave_acceso = clave_acceso.to_s
      @numero_autorizacion = numero_autorizacion
      @fecha_autorizacion = fecha_autorizacion
      @ambiente = ambiente.to_s
      @verification_url = verification_url
      @qr_content = qr_content
    end

    def render
      Prawn::Document.new(page_size: "A4", margin: [30, 34, 46, 34], info: { Title: "#{document_title} #{document_number}" }) do |pdf|
        Prawn::Fonts::AFM.hide_m17n_warning = true if defined?(Prawn::Fonts::AFM)
        pdf.font "Helvetica"

        draw_header(pdf)
        draw_authorization_panel(pdf)
        draw_buyer_panel(pdf)
        draw_details_table(pdf)
        draw_totals_and_payments(pdf)
        draw_additional_info(pdf)
        draw_test_watermark(pdf) unless @ambiente == "2"
        draw_page_numbers(pdf)
        stamp_footers(pdf)
      end.render
    end

    private

    def document_title = @nota_credito ? "NOTA DE CRÉDITO" : "FACTURA"

    def draw_header(pdf)
      emisor = @factura.emisor
      full_width = pdf.bounds.width
      box_width = 214
      issuer_width = full_width - box_width - 18

      pdf.fill_color DARK
      pdf.fill_rectangle [0, pdf.cursor], full_width, 4
      pdf.move_down 16
      top = pdf.cursor

      pdf.bounding_box([0, top], width: issuer_width) do
        draw_logo(pdf, emisor, max_width: 170, max_height: 60)

        pdf.fill_color INK
        pdf.text safe_upcase(emisor.razon_social), size: 14, style: :bold, leading: 1
        if present?(emisor.nombre_comercial) && emisor.nombre_comercial.to_s.strip.casecmp?(emisor.razon_social.to_s.strip) == false
          pdf.move_down 1
          pdf.fill_color BLUE
          pdf.text emisor.nombre_comercial.to_s, size: 9.5, style: :bold
        end

        pdf.move_down 7
        inline_value(pdf, "Dirección matriz", emisor.dir_matriz)
        if present?(emisor.dir_establecimiento) && emisor.dir_establecimiento.to_s != emisor.dir_matriz.to_s
          inline_value(pdf, "Dirección sucursal", emisor.dir_establecimiento)
        end
        inline_value(pdf, "Contribuyente especial Nro.", emisor.contribuyente_especial) if present?(emisor.contribuyente_especial)
        inline_value(pdf, "Obligado a llevar contabilidad", emisor.obligado_contabilidad) if present?(emisor.obligado_contabilidad)
        if present?(emisor.contribuyente_rimpe)
          pdf.move_down 2
          pdf.fill_color MUTED
          pdf.text emisor.contribuyente_rimpe.to_s, size: 7.5, style: :bold
        end
      end
      issuer_bottom = pdf.cursor

      box_height = 136
      pdf.bounding_box([full_width - box_width, top], width: box_width, height: box_height) do
        rounded_panel(pdf, box_width, box_height, fill: PANEL)
        pdf.move_down 11
        pdf.indent(14, 14) do
          pdf.fill_color MUTED
          pdf.text "R.U.C. #{emisor.ruc}", size: 8.5, style: :bold, align: :right
          pdf.move_down 3
          pdf.fill_color DARK
          pdf.text document_title, size: @nota_credito ? 16 : 20, style: :bold, align: :right
          pdf.fill_color INK
          pdf.text "No. #{document_number}", size: 11, style: :bold, align: :right, character_spacing: 0.3
          pdf.move_down 9
          badge(pdf, "AMBIENTE: #{ambiente_label}", @ambiente == "2" ? GREEN : AMBER, width: box_width - 28)
          pdf.move_down 8
          key_value(pdf, "Fecha de emisión", format_fecha(@factura.fecha_emision), label_width: 84, size: 8.3)
          key_value(pdf, "Emisión", @factura.tipo_emision.to_s == "1" ? "Normal" : @factura.tipo_emision, label_width: 84, size: 8.3)
        end
      end

      pdf.move_cursor_to [issuer_bottom, top - box_height].min - 14
    end

    def draw_logo(pdf, emisor, max_width:, max_height:)
      return unless logo_present?(emisor)
      return unless supported_logo?(emisor)

      pdf.image StringIO.new(emisor.logo_data), fit: [max_width, max_height], position: :left
      pdf.move_down 8
    rescue StandardError
      nil # a broken logo never stops the RIDE
    end

    def logo_present?(emisor)
      emisor.respond_to?(:logo_data) && present?(emisor.logo_data)
    end

    def supported_logo?(emisor)
      %w[image/png image/jpeg image/jpg].include?(emisor.logo_content_type.to_s.downcase)
    end

    def draw_authorization_panel(pdf)
      full_width = pdf.bounds.width
      qr_size = 88
      panel_height = 112
      top = pdf.cursor

      rounded_panel(pdf, full_width, panel_height, fill: WHITE)

      pdf.bounding_box([14, top - 12], width: full_width - qr_size - 40, height: panel_height - 22) do
        section_label(pdf, "AUTORIZACIÓN DEL SRI")
        key_value(pdf, "Estado", "DOCUMENTO AUTORIZADO", label_width: 132, value_color: GREEN, bold_value: true)
        key_value(pdf, "Número de autorización", authorization_number, label_width: 132, size: 7.6)
        key_value(pdf, "Fecha de autorización", format_datetime(@fecha_autorizacion), label_width: 132)
        pdf.move_down 6
        pdf.fill_color MUTED
        pdf.text "CLAVE DE ACCESO", size: 7, style: :bold, character_spacing: 0.4
        pdf.move_down 2
        pdf.fill_color INK
        pdf.text @clave_acceso, size: 8.6, style: :bold, character_spacing: 0.35
      end

      pdf.bounding_box([full_width - qr_size - 12, top - 10], width: qr_size, height: qr_size + 4) do
        pdf.image qr_png_io(qr_payload), width: qr_size - 4, at: [2, qr_size + 2]
      end

      pdf.move_cursor_to top - panel_height - 12
    end

    def draw_buyer_panel(pdf)
      comprador = @factura.comprador
      full_width = pdf.bounds.width
      left = [
        ["Razón social / Nombres", comprador.razon_social],
        ["Identificación", comprador.identificacion],
        ["Dirección", comprador.direccion]
      ].select { |_, value| present?(value) }
      right = [
        ["Fecha de emisión", format_fecha(@factura.fecha_emision)],
        ["Teléfono", comprador.telefono],
        ["Correo", comprador.email]
      ].select { |_, value| present?(value) }
      panel_height = 32 + ([left.size, right.size].max * 12)
      top = pdf.cursor

      pdf.fill_color SOFT
      pdf.fill_rounded_rectangle [0, top], full_width, panel_height, 6
      pdf.stroke_color BORDER
      pdf.line_width 0.6
      pdf.stroke_rounded_rectangle [0, top], full_width, panel_height, 6

      pdf.bounding_box([14, top - 11], width: full_width - 28, height: panel_height - 16) do
        section_label(pdf, "DATOS DEL CLIENTE")
        left_width = (pdf.bounds.width - 16) * 0.6
        current = pdf.cursor
        pdf.bounding_box([0, current], width: left_width) do
          left.each { |label, value| key_value(pdf, label, value, label_width: 112) }
        end
        pdf.bounding_box([left_width + 16, current], width: pdf.bounds.width - left_width - 16) do
          right.each { |label, value| key_value(pdf, label, value, label_width: 90) }
        end
      end

      pdf.move_cursor_to top - panel_height - 16
    end

    def draw_details_table(pdf)
      section_label(pdf, @nota_credito ? "DETALLE DE LA NOTA DE CRÉDITO" : "DETALLE DE LA FACTURA")

      table_width = pdf.bounds.width
      widths = { code: 70, qty: 40, unit: 62, discount: 54, total: 62 }
      desc_w = table_width - widths.values.sum

      rows = [["Código", "Descripción", "Cant.", "P. unitario", "Descuento", "Subtotal"]]
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
                      cell_style: { size: 8, padding: [6, 7], borders: [:bottom], border_width: 0.5, border_color: BORDER },
                      column_widths: [widths[:code], desc_w, widths[:qty], widths[:unit], widths[:discount], widths[:total]]) do
        row(0).background_color = DARK
        row(0).text_color = WHITE
        row(0).font_style = :bold
        row(0).size = 7.5
        row(0).borders = []
        columns(2..5).align = :right
        columns(0).text_color = MUTED
        row(0).text_color = WHITE
        columns(0).overflow = :shrink_to_fit
        columns(0).min_font_size = 5.8
        columns(5).font_style = :bold
        (1...rows.length).each { |index| row(index).background_color = SOFT if index.even? }
      end
    end

    def draw_totals_and_payments(pdf)
      pdf.move_down 14
      pdf.start_new_page if pdf.cursor < 150
      full_width = pdf.bounds.width
      totals_width = 240
      left_width = full_width - totals_width - 20
      top = pdf.cursor

      pdf.bounding_box([0, top], width: left_width) do
        if @nota_credito
          draw_modified_document(pdf, left_width)
        else
          draw_payments(pdf, left_width)
        end
      end
      left_bottom = pdf.cursor

      pdf.bounding_box([full_width - totals_width, top], width: totals_width) do
        rows = totals_rows
        pdf.table(rows, width: totals_width,
                        cell_style: { size: 8.5, padding: [5, 9], borders: [:bottom], border_width: 0.5, border_color: BORDER },
                        column_widths: [totals_width - 92, 92]) do
          columns(0).text_color = MUTED
          columns(1).align = :right
          columns(1).font_style = :bold
          row(-1).background_color = DARK
          row(-1).text_color = WHITE
          row(-1).font_style = :bold
          row(-1).size = 11
          row(-1).padding = [9, 9]
          row(-1).borders = []
        end
      end

      pdf.move_cursor_to [left_bottom, pdf.cursor].min
    end

    # As the SRI's RIDE: a subtotal per IVA rate, the discount, the IVA, the total.
    def totals_rows
      totals = @factura.totales
      groups = totals.total_con_impuestos.sort_by { |tax| -tax.tarifa.to_f }
      rows = groups.map { |tax| [subtotal_label(tax), money(tax.base_imponible)] }
      rows << ["Subtotal sin impuestos", money(totals.total_sin_impuestos)] if groups.size != 1
      rows << ["Descuento", money(totals.total_descuento)] if totals.total_descuento.to_f.positive?
      groups.select { |tax| tax.valor.to_f.positive? || tax.tarifa.to_f.positive? }.each do |tax|
        rows << ["IVA #{fmt(tax.tarifa)}%", money(tax.valor)]
      end
      rows << ["VALOR TOTAL", money(totals.importe_total)]
    end

    def subtotal_label(tax)
      case tax.codigo_porcentaje.to_s
      when "6" then "Subtotal no objeto de IVA"
      when "7" then "Subtotal exento de IVA"
      else "Subtotal #{fmt(tax.tarifa)}%"
      end
    end

    def draw_payments(pdf, width)
      section_label(pdf, "FORMA DE PAGO")
      rows = [["Forma de pago", "Valor", "Plazo"]]
      @factura.pagos.each do |payment|
        rows << [payment_label(payment.forma_pago), money(payment.total), payment_term(payment)]
      end
      rows << ["No especificada", money(@factura.totales.importe_total), "—"] if rows.size == 1

      pdf.table(rows, width: width, cell_style: { size: 8, padding: [5, 7], borders: [:bottom], border_width: 0.5, border_color: BORDER },
                      column_widths: [width - 124, 70, 54]) do
        row(0).font_style = :bold
        row(0).text_color = MUTED
        row(0).size = 7.3
        columns(1..2).align = :right
        columns(1).font_style = :bold
        row(0).font_style = :bold
      end
    end

    def payment_term(payment)
      return "—" unless present?(payment.plazo)

      unit = { "dias" => "días", "meses" => "meses" }.fetch(payment.unidad_tiempo.to_s, payment.unidad_tiempo.to_s)
      "#{payment.plazo} #{unit}".strip
    end

    # Nota de crédito: qué factura modifica y por qué.
    def draw_modified_document(pdf, width)
      section_label(pdf, "COMPROBANTE QUE SE MODIFICA")
      rows = [
        ["Comprobante", "#{@factura.cod_doc_modificado == "01" ? "Factura" : "Documento"} #{@factura.num_doc_modificado}"],
        ["Fecha de emisión", format_fecha(@factura.fecha_emision_doc_sustento)],
        ["Motivo", @factura.motivo.to_s]
      ]
      pdf.table(rows, width: width, cell_style: { size: 8, padding: [5, 7], borders: [:bottom], border_width: 0.5, border_color: BORDER },
                      column_widths: [96, width - 96]) do
        columns(0).text_color = MUTED
        columns(1).font_style = :bold
      end
    end

    def draw_additional_info(pdf)
      return unless @factura.info_adicional.respond_to?(:any?) && @factura.info_adicional.any?

      pdf.move_down 16
      section_label(pdf, "INFORMACIÓN ADICIONAL")
      rows = @factura.info_adicional.map do |item|
        if item.respond_to?(:fetch)
          [item[:nombre] || item["nombre"], item[:valor] || item["valor"]]
        else
          ["Info", item.to_s]
        end
      end

      pdf.table(rows, width: pdf.bounds.width,
                      cell_style: { size: 8, padding: [5, 7], borders: [:bottom], border_width: 0.5, border_color: BORDER },
                      column_widths: [120, pdf.bounds.width - 120]) do
        columns(0).text_color = MUTED
      end
    end

    # Pruebas: a faint stamp across every page, so it is never mistaken for a real one.
    def draw_test_watermark(pdf)
      (1..pdf.page_count).each do |page_num|
        pdf.go_to_page(page_num)
        pdf.transparent(0.07) do
          pdf.fill_color AMBER
          pdf.rotate(32, origin: [pdf.bounds.width / 2, pdf.bounds.height / 2]) do
            pdf.text_box "PRUEBAS · SIN VALIDEZ TRIBUTARIA", at: [-60, (pdf.bounds.height / 2) + 20], width: pdf.bounds.width + 120,
                                                          height: 40, size: 30, style: :bold, align: :center
          end
        end
      end
    end

    def stamp_footers(pdf)
      pdf.canvas do
        (1..pdf.page_count).each do |page_num|
          pdf.go_to_page(page_num)
          y = pdf.bounds.bottom + 24
          pdf.bounding_box([pdf.bounds.left, y], width: pdf.bounds.width, height: 22) do
            pdf.stroke_color BORDER
            pdf.stroke_horizontal_rule
            pdf.move_down 6
            pdf.fill_color MUTED
            pdf.text @footer.to_s, size: 7, align: :center
          end
        end
      end
    end

    def draw_page_numbers(pdf)
      pdf.number_pages "Página <page> de <total>", at: [pdf.bounds.right - 76, 16], width: 76,
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

    def badge(pdf, text, color, width: 176)
      pdf.fill_color color
      pdf.fill_rounded_rectangle [0, pdf.cursor], width, 17, 4
      pdf.fill_color WHITE
      pdf.text_box text, at: [0, pdf.cursor - 4.5], width: width, height: 12, size: 7.8, style: :bold, align: :center,
                         character_spacing: 0.4
      pdf.move_down 17
    end

    def section_label(pdf, text)
      pdf.fill_color DARK
      pdf.text text, size: 7.8, style: :bold, character_spacing: 0.5
      pdf.move_down 6
    end

    def key_value(pdf, label, value, label_width: 92, size: 8.5, value_color: INK, bold_value: false)
      return unless present?(value)

      y = pdf.cursor
      pdf.fill_color MUTED
      pdf.text_box label.to_s, at: [0, y], width: label_width, height: 12, size: size, style: :bold
      pdf.fill_color value_color
      pdf.text_box value.to_s, at: [label_width, y], width: pdf.bounds.width - label_width, height: 16,
                             size: size, style: bold_value ? :bold : :normal, overflow: :shrink_to_fit,
                             min_font_size: 6
      pdf.move_down 12
    end

    # "Label: value" on one line, wrapping under itself if long.
    def inline_value(pdf, label, value)
      pdf.formatted_text [
        { text: "#{label}: ", styles: [:bold], color: MUTED },
        { text: value.to_s, color: INK }
      ], size: 8, leading: 1
      pdf.move_down 2
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
        @nota_credito ? "RIDE NOTA DE CREDITO" : "RIDE FACTURA",
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
