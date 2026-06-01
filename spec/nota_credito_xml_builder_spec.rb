# frozen_string_literal: true

require "nokogiri"

RSpec.describe SriFacturacion::NotaCreditoXmlBuilder do
  let(:nota_credito) { build_sample_nota_credito }
  let(:clave) do
    SriFacturacion::AccessKey.generate(
      fecha_emision: nota_credito.fecha_emision, ruc: nota_credito.emisor.ruc,
      establecimiento: "001", punto_emision: "001", secuencial: nota_credito.secuencial,
      tipo_comprobante: SriFacturacion::AccessKey::NOTA_CREDITO
    )
  end
  let(:xml) { described_class.new(nota_credito, clave_acceso: clave, ambiente: "1").build }
  let(:doc) { Nokogiri::XML(xml) }

  it "genera una notaCredito 1.1.0 con id=comprobante" do
    expect(doc.root.name).to eq("notaCredito")
    expect(doc.root["version"]).to eq("1.1.0")
    expect(doc.root["id"]).to eq("comprobante")
  end

  it "usa codDoc 04 en la infoTributaria" do
    expect(doc.at_xpath("//infoTributaria/codDoc").text).to eq("04")
    expect(doc.at_xpath("//infoTributaria/ruc").text).to eq("0924383631001")
    expect(doc.at_xpath("//infoTributaria/claveAcceso").text).to eq(clave)
  end

  it "referencia el documento modificado (factura original)" do
    info = doc.at_xpath("//infoNotaCredito")
    expect(info.at_xpath("codDocModificado").text).to eq("01")
    expect(info.at_xpath("numDocModificado").text).to eq("001-001-000000001")
    expect(info.at_xpath("fechaEmisionDocSustento").text).to eq("30/05/2026")
    expect(info.at_xpath("motivo").text).to eq("Devolución de mercadería")
  end

  it "calcula totalSinImpuestos y valorModificacion" do
    # 1 * 20 = 20 sin impuestos; IVA 15% de 20 = 3.00; valorModificacion = 23.00
    expect(doc.at_xpath("//infoNotaCredito/totalSinImpuestos").text).to eq("20.00")
    expect(doc.at_xpath("//infoNotaCredito/valorModificacion").text).to eq("23.00")
  end

  it "el totalImpuesto de la NC no incluye tarifa (a diferencia de la factura)" do
    total_imp = doc.at_xpath("//infoNotaCredito/totalConImpuestos/totalImpuesto")
    expect(total_imp.at_xpath("codigo").text).to eq("2")
    expect(total_imp.at_xpath("baseImponible").text).to eq("20.00")
    expect(total_imp.at_xpath("valor").text).to eq("3.00")
    expect(total_imp.at_xpath("tarifa")).to be_nil
  end

  it "el detalle usa codigoInterno y conserva su impuesto con tarifa" do
    detalle = doc.at_xpath("//detalles/detalle")
    expect(detalle.at_xpath("codigoInterno").text).to eq("GORRA-001")
    expect(detalle.at_xpath("descripcion").text).to eq("Gorra 9FORTY")
    expect(detalle.at_xpath("cantidad").text).to eq("1.000000")
    expect(detalle.at_xpath("impuestos/impuesto/tarifa").text).to eq("15.00")
    expect(detalle.at_xpath("impuestos/impuesto/valor").text).to eq("3.00")
  end

  it "produce un XML que la firma XAdES-BES puede procesar" do
    signed = build_test_signer.sign(xml)
    signed_doc = Nokogiri::XML(signed)
    ns = { "ds" => "http://www.w3.org/2000/09/xmldsig#" }
    expect(signed_doc.at_xpath("//ds:Signature", ns)).not_to be_nil
    expect(signed_doc.root.name).to eq("notaCredito")
  end
end
