# frozen_string_literal: true

require "prawn"
require "prawn/table"
require "rqrcode"

module SriFacturacion
  # Genera el RIDE (Representación Impresa del Documento Electrónico) en PDF.
  # PDF en Ruby puro con Prawn; QR con la clave de acceso vía rqrcode.
  class Ride
    NAVY   = "0F2742"
    BLUE   = "2563EB"
    GREEN  = "15803D"
    GRAY   = "64748B"
    LIGHT  = "F1F5F9"
    ZEBRA  = "F8FAFC"
    BORDER = "CBD5E1"
    ACCENT = "EFF6FF" # fondo sección cliente

    def initialize(factura, clave_acceso:, numero_autorizacion: nil, fecha_autorizacion: nil, ambiente: "1")
      @factura = factura
      @clave_acceso = clave_acceso
      @numero_autorizacion = numero_autorizacion
      @fecha_autorizacion = fecha_autorizacion
      @ambiente = ambiente.to_s
    end

    def render
      f = @factura
      emisor    = f.emisor
      comprador = f.comprador
      totales   = f.totales

      Prawn::Document.new(page_size: "A4", margin: 36) do |pdf|
        Prawn::Fonts::AFM.hide_m17n_warning = true if defined?(Prawn::Fonts::AFM)
        full_width = pdf.bounds.width

        # ── Banda de acento superior ──────────────────────────────────────
        pdf.fill_color NAVY
        pdf.fill_rectangle [0, pdf.cursor], full_width, 6
        pdf.move_down 20

        # ── Encabezado: Emisor (izq) + Caja FACTURA (der) ────────────────
        header_top = pdf.cursor
        box_w  = 202
        box_h  = 128

        pdf.bounding_box([0, header_top], width: full_width - box_w - 16, height: box_h) do
          pdf.fill_color NAVY
          pdf.text emisor.razon_social.to_s.upcase, size: 16, style: :bold, leading: 2
          if emisor.nombre_comercial.to_s.strip.length > 0 && emisor.nombre_comercial != emisor.razon_social
            pdf.fill_color BLUE
            pdf.text emisor.nombre_comercial.to_s, size: 10, style: :bold
          end
          pdf.move_down 6
          pdf.fill_color GRAY
          pdf.text "RUC: #{emisor.ruc}", size: 9, style: :bold
          pdf.text emisor.dir_matriz.to_s, size: 9 if emisor.dir_matriz.to_s.length > 0
          if emisor.dir_establecimiento.to_s.length > 0 && emisor.dir_establecimiento != emisor.dir_matriz
            pdf.text "Sucursal: #{emisor.dir_establecimiento}", size: 8
          end
          pdf.text "Obligado a llevar contabilidad: #{emisor.obligado_contabilidad}", size: 8 if emisor.obligado_contabilidad.to_s.length > 0
          pdf.text "Contribuyente especial Nro: #{emisor.contribuyente_especial}", size: 8 if emisor.contribuyente_especial.to_s.strip.length > 0
          pdf.text emisor.contribuyente_rimpe.to_s, size: 8 if emisor.contribuyente_rimpe.to_s.strip.length > 0
        end

        # Caja FACTURA
        pdf.bounding_box([full_width - box_w, header_top], width: box_w, height: box_h) do
          pdf.fill_color LIGHT
          pdf.fill_rounded_rectangle [0, box_h], box_w, box_h, 8
          pdf.stroke_color BORDER
          pdf.line_width 0.75
          pdf.stroke_rounded_rectangle [0, box_h], box_w, box_h, 8

          pad   = 14
          inner = box_w - (pad * 2)

          # Título FACTURA
          pdf.fill_color NAVY
          pdf.text_box "FACTURA", at: [pad, box_h - 12], width: inner, size: 16, style: :bold

          # Separador interior
          pdf.stroke_color BORDER
          pdf.line_width 0.5
          pdf.stroke do
            pdf.move_to  pad, box_h - 26
            pdf.line_to  box_w - pad, box_h - 26
          end

          # No. Comprobante
          pdf.fill_color GRAY
          pdf.text_box "No. Comprobante", at: [pad, box_h - 35], width: inner, size: 7
          pdf.fill_color "000000"
          pdf.text_box "#{emisor.establecimiento}-#{emisor.punto_emision}-#{f.secuencial}",
                       at: [pad, box_h - 47], width: inner, size: 11, style: :bold

          # Ambiente y fecha
          pdf.fill_color GRAY
          pdf.text_box "Ambiente: #{@ambiente == '2' ? 'PRODUCCION' : 'PRUEBAS'}",
                       at: [pad, box_h - 70], width: inner, size: 8
          pdf.text_box "Fecha de emision: #{format_fecha(f.fecha_emision)}",
                       at: [pad, box_h - 83], width: inner, size: 8

          # Badge AUTORIZADO
          pdf.fill_color GREEN
          pdf.fill_rounded_rectangle [pad, box_h - 97], inner, 20, 4
          pdf.fill_color "FFFFFF"
          pdf.text_box "DOCUMENTO AUTORIZADO",
                       at: [pad, box_h - 101], width: inner, size: 8.5, style: :bold, align: :center
        end

        # Línea separadora
        pdf.move_cursor_to header_top - box_h - 14
        pdf.stroke_color BORDER
        pdf.line_width 0.5
        pdf.stroke_horizontal_rule
        pdf.move_down 14

        # ── Sección Cliente + Claves + QR ────────────────────────────────
        info_top = pdf.cursor
        qr_size  = 106
        text_w   = full_width - qr_size - 14

        # Fondo sutil para el bloque de cliente
        pdf.fill_color ACCENT
        pdf.fill_rounded_rectangle [0, info_top + 2], full_width, qr_size + 4, 6
        pdf.fill_color "000000"

        # Bloque de texto: cliente + claves
        pdf.bounding_box([8, info_top - 2], width: text_w - 8, height: qr_size) do
          pdf.fill_color NAVY
          pdf.text "DATOS DEL COMPRADOR", size: 7.5, style: :bold
          pdf.move_down 4
          pdf.fill_color NAVY
          pdf.text comprador.razon_social.to_s, size: 12, style: :bold
          pdf.fill_color "000000"
          pdf.text "Identificacion: #{comprador.identificacion}", size: 9
          pdf.text "Direccion: #{comprador.direccion}", size: 9 if comprador.direccion.to_s.length > 0
          pdf.move_down 5

          # Claves en dos columnas
          half = (text_w - 8) / 2
          cur  = pdf.cursor
          pdf.bounding_box([0, cur], width: half - 4) do
            pdf.fill_color NAVY
            pdf.text "NUMERO DE AUTORIZACION", size: 7, style: :bold
            pdf.fill_color "000000"
            pdf.text (@numero_autorizacion || @clave_acceso).to_s, size: 7
          end
          pdf.bounding_box([half, cur], width: half) do
            pdf.fill_color NAVY
            pdf.text "CLAVE DE ACCESO", size: 7, style: :bold
            pdf.fill_color "000000"
            pdf.text @clave_acceso.to_s, size: 7
          end
        end

        # QR
        pdf.bounding_box([full_width - qr_size, info_top], width: qr_size, height: qr_size) do
          pdf.fill_color "FFFFFF"
          pdf.fill_rounded_rectangle [2, qr_size], qr_size - 4, qr_size, 6
          pdf.stroke_color BORDER
          pdf.line_width 0.75
          pdf.stroke_rounded_rectangle [2, qr_size], qr_size - 4, qr_size, 6
          pdf.image qr_png_io(@clave_acceso), width: qr_size - 20, at: [10, qr_size - 8]
        end

        pdf.move_cursor_to info_top - qr_size - 16
        pdf.fill_color "000000"

        # ── Tabla de detalle ──────────────────────────────────────────────
        table_width = pdf.bounds.width
        # Columnas: SKU, Descripción, Cant., P.Unit., Desc., Total
        # SKU puede tener hasta ~15 chars (NIK-36-GRIS-C7B6) — le damos más espacio
        sku_w  = 70
        qty_w  = 44
        pu_w   = 58
        dsc_w  = 48
        tot_w  = 52
        desc_w = table_width - sku_w - qty_w - pu_w - dsc_w - tot_w

        rows = [["CODIGO", "DESCRIPCION", "CANT.", "P. UNIT.", "DESC.", "TOTAL"]]
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
                        cell_style: { size: 8, padding: [6, 7], border_width: 0.4, border_color: BORDER },
                        column_widths: [sku_w, desc_w, qty_w, pu_w, dsc_w, tot_w]) do
          row(0).font_style    = :bold
          row(0).background_color = NAVY
          row(0).text_color    = "FFFFFF"
          row(0).size          = 7.5
          row(0).padding       = [7, 7]
          columns(2..5).align  = :right
          columns(0).overflow  = :shrink_to_fit
          columns(0).min_font_size = 6.5
          (1...rows.length).each do |i|
            row(i).background_color = ZEBRA if i.even?
          end
        end

        # ── Totales ───────────────────────────────────────────────────────
        pdf.move_down 16
        totals_rows = [
          ["Subtotal sin impuestos", "$#{fmt(totales.total_sin_impuestos)}"],
          ["Descuento",              "$#{fmt(totales.total_descuento)}"]
        ]
        totales.total_con_impuestos.each do |imp|
          totals_rows << ["IVA #{imp.tarifa.to_i}%", "$#{fmt(imp.valor)}"]
        end
        totals_rows << ["VALOR TOTAL", "$#{fmt(totales.importe_total)}"]

        totals_w = 245
        pdf.bounding_box([table_width - totals_w, pdf.cursor], width: totals_w) do
          pdf.table(totals_rows, width: totals_w,
                                 cell_style: { size: 9, padding: [6, 10], border_width: 0.4, border_color: BORDER },
                                 column_widths: [155, 90]) do
            columns(0).align = :left
            columns(1).align = :right
            (0...-1).each do |i|
              row(i).background_color = ZEBRA if i.even?
            end
            row(-1).font_style       = :bold
            row(-1).size             = 11
            row(-1).background_color = NAVY
            row(-1).text_color       = "FFFFFF"
            row(-1).padding          = [8, 10]
          end
        end

        # ── Pie de página ─────────────────────────────────────────────────
        pdf.repeat(:all) do
          pdf.bounding_box([0, 30], width: pdf.bounds.width, height: 22) do
            pdf.fill_color NAVY
            pdf.fill_rectangle [0, 1], pdf.bounds.width, 1
            pdf.move_down 7
            pdf.fill_color GRAY
            pdf.text "RIDE generado por StockManager by RysthDesign  ·  www.rysthdesign.com",
                     size: 7.5, align: :center
          end
        end
      end.render
    end

    private

    def qr_png_io(content)
      qr  = RQRCode::QRCode.new(content)
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
