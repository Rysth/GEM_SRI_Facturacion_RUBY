# frozen_string_literal: true

require "prawn"
require "prawn/table"
require "rqrcode"

module SriFacturacion
  # Genera el RIDE (Representación Impresa del Documento Electrónico) en PDF.
  # PDF en Ruby puro con Prawn; QR con la clave de acceso vía rqrcode.
  class Ride
    # Paleta de colores del documento.
    NAVY   = "0F2742"
    BLUE   = "2563EB"
    GREEN  = "15803D"
    GRAY   = "64748B"
    LIGHT  = "F1F5F9"
    ZEBRA  = "F8FAFC"
    BORDER = "CBD5E1"

    def initialize(factura, clave_acceso:, numero_autorizacion: nil, fecha_autorizacion: nil, ambiente: "1")
      @factura = factura
      @clave_acceso = clave_acceso
      @numero_autorizacion = numero_autorizacion
      @fecha_autorizacion = fecha_autorizacion
      @ambiente = ambiente.to_s
    end

    # Devuelve el PDF como string binario.
    def render
      f = @factura
      emisor = f.emisor
      comprador = f.comprador
      totales = f.totales

      Prawn::Document.new(page_size: "A4", margin: 36) do |pdf|
        Prawn::Fonts::AFM.hide_m17n_warning = true if defined?(Prawn::Fonts::AFM)
        full_width = pdf.bounds.width

        # --- Banda de acento superior ---------------------------------------
        pdf.fill_color NAVY
        pdf.fill_rectangle [0, pdf.cursor], full_width, 5
        pdf.move_down 18

        # --- Encabezado: emisor (izq) + caja FACTURA (der) ------------------
        header_top = pdf.cursor
        box_w = 200
        box_h = 124

        pdf.bounding_box([0, header_top], width: full_width - box_w - 18, height: box_h) do
          pdf.fill_color NAVY
          pdf.text emisor.razon_social.to_s.upcase, size: 16, style: :bold, leading: 1
          if emisor.nombre_comercial.to_s.strip != "" && emisor.nombre_comercial != emisor.razon_social
            pdf.fill_color BLUE
            pdf.text emisor.nombre_comercial.to_s, size: 10, style: :bold
          end
          pdf.move_down 5
          pdf.fill_color GRAY
          pdf.text "RUC: #{emisor.ruc}", size: 9, style: :bold
          pdf.text emisor.dir_matriz.to_s, size: 9 if emisor.dir_matriz
          if emisor.dir_establecimiento && emisor.dir_establecimiento != emisor.dir_matriz
            pdf.text "Sucursal: #{emisor.dir_establecimiento}", size: 8
          end
          pdf.text "Obligado a llevar contabilidad: #{emisor.obligado_contabilidad}", size: 8 if emisor.obligado_contabilidad
          pdf.text "Contribuyente especial Nro: #{emisor.contribuyente_especial}", size: 8 if emisor.contribuyente_especial.to_s.strip != ""
          pdf.text emisor.contribuyente_rimpe.to_s, size: 8 if emisor.contribuyente_rimpe.to_s.strip != ""
        end

        pdf.bounding_box([full_width - box_w, header_top], width: box_w, height: box_h) do
          pdf.fill_color LIGHT
          pdf.fill_rounded_rectangle [0, box_h], box_w, box_h, 8
          pdf.stroke_color BORDER
          pdf.stroke_rounded_rectangle [0, box_h], box_w, box_h, 8

          pad = 14
          inner = box_w - (pad * 2)
          pdf.fill_color NAVY
          pdf.text_box "FACTURA", at: [pad, box_h - 12], width: inner, size: 15, style: :bold
          pdf.fill_color GRAY
          pdf.text_box "No. Comprobante", at: [pad, box_h - 38], width: inner, size: 7.5
          pdf.fill_color "000000"
          pdf.text_box "#{emisor.establecimiento}-#{emisor.punto_emision}-#{f.secuencial}",
                       at: [pad, box_h - 49], width: inner, size: 11, style: :bold
          pdf.fill_color GRAY
          pdf.text_box "Ambiente: #{@ambiente == '2' ? 'PRODUCCION' : 'PRUEBAS'}", at: [pad, box_h - 72], width: inner, size: 8
          pdf.text_box "Fecha de emision: #{format_fecha(f.fecha_emision)}", at: [pad, box_h - 85], width: inner, size: 8

          pdf.fill_color GREEN
          pdf.fill_rounded_rectangle [pad, box_h - 96], inner, 18, 4
          pdf.fill_color "FFFFFF"
          pdf.text_box "DOCUMENTO AUTORIZADO", at: [pad, box_h - 100], width: inner, size: 8, style: :bold, align: :center
        end

        pdf.move_cursor_to header_top - box_h - 16
        pdf.stroke_color BORDER
        pdf.stroke_horizontal_rule
        pdf.move_down 16

        # --- Cliente + claves (izq) y QR (der) ------------------------------
        info_top = pdf.cursor
        qr_box = 104
        text_width = full_width - qr_box - 16

        pdf.bounding_box([0, info_top], width: text_width, height: qr_box) do
          pdf.fill_color GRAY
          pdf.text "CLIENTE", size: 8, style: :bold
          pdf.move_down 3
          pdf.fill_color NAVY
          pdf.text comprador.razon_social.to_s, size: 12, style: :bold
          pdf.fill_color "000000"
          pdf.text "Identificacion: #{comprador.identificacion}", size: 9
          pdf.text "Direccion: #{comprador.direccion}", size: 9 if comprador.direccion
          pdf.move_down 6
          pdf.fill_color GRAY
          pdf.text "NUMERO DE AUTORIZACION", size: 7.5, style: :bold
          pdf.fill_color "000000"
          pdf.text (@numero_autorizacion || @clave_acceso).to_s, size: 8
          pdf.move_down 2
          pdf.fill_color GRAY
          pdf.text "CLAVE DE ACCESO", size: 7.5, style: :bold
          pdf.fill_color "000000"
          pdf.text @clave_acceso.to_s, size: 8
        end

        pdf.bounding_box([full_width - qr_box, info_top], width: qr_box, height: qr_box) do
          pdf.fill_color "FFFFFF"
          pdf.fill_rounded_rectangle [0, qr_box], qr_box, qr_box, 6
          pdf.stroke_color BORDER
          pdf.stroke_rounded_rectangle [0, qr_box], qr_box, qr_box, 6
          pdf.image qr_png_io(@clave_acceso), width: qr_box - 18, at: [9, qr_box - 9]
        end

        pdf.move_cursor_to info_top - qr_box - 18
        pdf.fill_color "000000" # las celdas heredan el fill_color como color de texto

        # --- Tabla de detalle (filas alternas) ------------------------------
        table_width = pdf.bounds.width
        rows = [["Codigo", "Descripcion", "Cant.", "P. Unit.", "Desc.", "Total"]]
        f.detalles.each do |d|
          rows << [
            d.codigo_principal.to_s,
            d.descripcion.to_s,
            fmt(d.cantidad),
            fmt(d.precio_unitario),
            fmt(d.descuento),
            fmt(d.precio_total_sin_impuesto)
          ]
        end

        pdf.table(rows, header: true, width: table_width,
                        cell_style: { size: 8, padding: [6, 8], border_width: 0.5, border_color: BORDER },
                        column_widths: [52, table_width - 265, 48, 60, 50, 55]) do
          row(0).font_style = :bold
          row(0).background_color = NAVY
          row(0).text_color = "FFFFFF"
          row(0).padding = [7, 8]
          columns(2..5).align = :right
          (1...rows.length).each do |i|
            row(i).background_color = ZEBRA if i.even?
          end
        end

        # --- Totales (caja a la derecha) ------------------------------------
        pdf.move_down 18
        totals_rows = [
          ["Subtotal sin impuestos", "$#{fmt(totales.total_sin_impuestos)}"],
          ["Descuento", "$#{fmt(totales.total_descuento)}"]
        ]
        totales.total_con_impuestos.each do |imp|
          totals_rows << ["IVA #{imp.tarifa.to_i}%", "$#{fmt(imp.valor)}"]
        end
        totals_rows << ["VALOR TOTAL", "$#{fmt(totales.importe_total)}"]

        totals_w = 240
        pdf.bounding_box([table_width - totals_w, pdf.cursor], width: totals_w) do
          pdf.table(totals_rows, width: totals_w,
                                 cell_style: { size: 9, padding: [6, 10], border_width: 0.5, border_color: BORDER },
                                 column_widths: [150, 90]) do
            columns(0).align = :left
            columns(1).align = :right
            row(-1).font_style = :bold
            row(-1).size = 11
            row(-1).background_color = NAVY
            row(-1).text_color = "FFFFFF"
          end
        end

        # --- Pie en todas las páginas ---------------------------------------
        pdf.repeat(:all) do
          pdf.bounding_box([0, 30], width: pdf.bounds.width, height: 22) do
            pdf.stroke_color BORDER
            pdf.stroke_horizontal_rule
            pdf.move_down 6
            pdf.fill_color GRAY
            pdf.text "RIDE generado por StockManager by RysthDesign", size: 8, align: :center
          end
        end
      end.render
    end

    private

    def qr_png_io(content)
      qr = RQRCode::QRCode.new(content)
      png = qr.as_png(size: 220, border_modules: 2)
      StringIO.new(png.to_s)
    end

    def fmt(value)
      format("%.2f", value.to_f)
    end

    def format_fecha(date)
      d = date.respond_to?(:to_date) ? date.to_date : date
      format("%02d/%02d/%04d", d.day, d.month, d.year)
    end
  end
end
