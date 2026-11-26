# frozen_string_literal: true

require "nokogiri"

RSpec.describe SriFacturacion::Client do
  # Responde como el SRI, sin red.
  class FakeSoap
    attr_reader :calls

    def initialize(recepcion: { estado: "RECIBIDA", mensajes: [] }, autorizacion: nil)
      @recepcion = recepcion
      @autorizacion = autorizacion
      @calls = []
    end

    def validar_comprobante(xml, ambiente:)
      @calls << [:recepcion, ambiente, xml]
      @recepcion
    end

    def autorizar_comprobante(clave, ambiente:)
      @calls << [:autorizacion, ambiente, clave]
      @autorizacion
    end
  end

  let(:soap) { FakeSoap.new(autorizacion: { estado: "AUTORIZADO", numero_autorizacion: "123", mensajes: [] }) }
  let(:client) { described_class.new(signer: build_test_signer, soap_client: soap) }

  it "firma sin red y devuelve la clave y el XML firmado" do
    firmado = client.firmar(build_sample_factura, codigo_numerico: "12345678")
    expect(firmado[:clave_acceso]).to match(/\A\d{49}\z/)
    expect(firmado[:clave_acceso][8, 2]).to eq("01")
    expect(firmado[:xml_firmado]).to include("ds:Signature")
    expect(soap.calls).to be_empty
  end

  it "firma una nota de crédito con su tipo de comprobante" do
    firmado = client.firmar(build_sample_nota_credito)
    expect(firmado[:clave_acceso][8, 2]).to eq("04")
    expect(Nokogiri::XML(firmado[:xml_firmado]).root.name).to eq("notaCredito")
  end

  it "envía y consulta en el ambiente que dice la clave, no el de la configuración" do
    SriFacturacion.configuration.ambiente = "2"
    firmado = client.firmar(build_sample_factura)
    SriFacturacion.configuration.ambiente = "1"

    client.recepcion(firmado[:xml_firmado], firmado[:clave_acceso])
    auth = client.autorizacion(firmado[:clave_acceso])
    expect(soap.calls.map { |call| call[0..1] }).to eq([[:recepcion, "2"], [:autorizacion, "2"]])
    expect(auth[:estado]).to eq("AUTORIZADO")
  end

  it "agrega el RUC del proveedor del sistema una sola vez" do
    SriFacturacion.configuration.proveedor_ruc = "1790012345001"
    doc = Nokogiri::XML(client.firmar(build_sample_factura)[:xml_firmado])
    campos = doc.xpath("//campoAdicional[@nombre='RUCProveedorSistema']")
    expect(campos.map(&:text)).to eq(["1790012345001"])
  end

  it "sin RUC de proveedor configurado no agrega el campo" do
    doc = Nokogiri::XML(client.firmar(build_sample_factura)[:xml_firmado])
    expect(doc.at_xpath("//campoAdicional[@nombre='RUCProveedorSistema']")).to be_nil
  end

  it "respeta los montos de línea que manda el sistema (precio al público exacto)" do
    emisor = build_sample_factura.emisor
    detalle = SriFacturacion::Detalle.new(
      descripcion: "Taza", cantidad: 3, precio_unitario: "8.695652", descuento: 0,
      precio_total_sin_impuesto: "26.09",
      impuestos: [SriFacturacion::Impuesto.new(base_imponible: "26.09", valor: "3.91", codigo_porcentaje: "4", tarifa: 15)]
    )
    factura = SriFacturacion::Factura.new(emisor: emisor, comprador: SriFacturacion::Comprador.consumidor_final,
                                          detalles: [detalle], secuencial: "7")
    doc = Nokogiri::XML(client.firmar(factura)[:xml_firmado])
    expect(doc.at_xpath("//infoFactura/totalSinImpuestos").text).to eq("26.09")
    expect(doc.at_xpath("//infoFactura/importeTotal").text).to eq("30.00")
  end

  it "genera el RIDE de una factura y de una nota de crédito" do
    factura_pdf = client.ride_pdf(build_sample_factura, clave_acceso: client.firmar(build_sample_factura)[:clave_acceso])
    nota = build_sample_nota_credito
    nota_pdf = client.ride_pdf(nota, clave_acceso: client.firmar(nota)[:clave_acceso], numero_autorizacion: "999")
    [factura_pdf, nota_pdf].each { |pdf| expect(pdf).to start_with("%PDF") }
    expect(nota_pdf.bytesize).to be > 1000
  end
end

RSpec.describe SriFacturacion::SoapClient do
  it "lee solo los mensajes reales (no el <mensaje> interno con el texto)" do
    xml = <<~XML
      <respuestaSolicitud><estado>DEVUELTA</estado><comprobantes><comprobante><mensajes>
        <mensaje><identificador>45</identificador><mensaje>SECUENCIAL REGISTRADO</mensaje><tipo>ERROR</tipo></mensaje>
      </mensajes></comprobante></comprobantes></respuestaSolicitud>
    XML
    result = described_class.new.parse_recepcion(xml)
    expect(result[:mensajes]).to eq([{ identificador: "45", mensaje: "SECUENCIAL REGISTRADO", tipo: "ERROR" }])
  end
end
