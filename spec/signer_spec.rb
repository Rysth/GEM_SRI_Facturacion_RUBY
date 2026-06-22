# frozen_string_literal: true

require "nokogiri"
require "openssl"
require "base64"

RSpec.describe SriFacturacion::Signer do
  let(:signer) { build_test_signer }
  let(:factura) { build_sample_factura }
  let(:clave) do
    SriFacturacion::AccessKey.generate(
      fecha_emision: factura.fecha_emision, ruc: factura.emisor.ruc,
      establecimiento: "001", punto_emision: "001", secuencial: factura.secuencial
    )
  end
  let(:xml) { SriFacturacion::XmlBuilder.new(factura, clave_acceso: clave, ambiente: "1").build }
  let(:signed) { signer.sign(xml) }
  let(:doc) { Nokogiri::XML(signed) }
  let(:ns) { { "ds" => SriFacturacion::Signer::DS, "etsi" => SriFacturacion::Signer::ETSI } }

  it "anexa una ds:Signature dentro del comprobante" do
    expect(doc.root.name).to eq("factura")
    expect(doc.at_xpath("//ds:Signature", ns)).not_to be_nil
  end

  it "usa RSA-SHA1 y SHA-1 como exige el SRI" do
    expect(doc.at_xpath("//ds:SignatureMethod", ns)["Algorithm"]).to include("rsa-sha1")
    expect(doc.at_xpath("//ds:SignedInfo/ds:Reference[3]/ds:Transforms/ds:Transform", ns)["Algorithm"]).to include("enveloped-signature")
  end

  it "incluye QualifyingProperties/SignedProperties (XAdES)" do
    expect(doc.at_xpath("//etsi:QualifyingProperties/etsi:SignedProperties", ns)).not_to be_nil
    expect(doc.at_xpath("//etsi:SigningCertificate/etsi:Cert/etsi:CertDigest/ds:DigestValue", ns).text).not_to be_empty
  end

  it "el SignatureValue verifica criptográficamente sobre el SignedInfo canonicalizado" do
    signed_info = doc.at_xpath("//ds:SignedInfo", ns)
    c14n = signed_info.canonicalize(Nokogiri::XML::XML_C14N_1_0)
    sig_value = Base64.decode64(doc.at_xpath("//ds:SignatureValue", ns).text)
    expect(signer.certificate.public_key.verify(OpenSSL::Digest::SHA1.new, sig_value, c14n)).to be(true)
  end

  it "el digest de la referencia #comprobante coincide con el comprobante sin la firma (enveloped)" do
    ref = doc.xpath("//ds:SignedInfo/ds:Reference", ns).find { |r| r["URI"] == "#comprobante" }
    expected = ref.at_xpath("ds:DigestValue", ns).text

    stripped = Nokogiri::XML(signed)
    stripped.at_xpath("//ds:Signature", ns).remove
    actual = Base64.strict_encode64(OpenSSL::Digest::SHA1.digest(stripped.root.canonicalize(Nokogiri::XML::XML_C14N_1_0)))
    expect(actual).to eq(expected)
  end

  it "el digest del KeyInfo coincide con su canonicalización" do
    ref_uri = doc.at_xpath("//ds:KeyInfo", ns)["Id"]
    ref = doc.xpath("//ds:SignedInfo/ds:Reference", ns).find { |r| r["URI"] == "##{ref_uri}" }
    expected = ref.at_xpath("ds:DigestValue", ns).text
    keyinfo = doc.at_xpath("//ds:KeyInfo", ns)
    actual = Base64.strict_encode64(OpenSSL::Digest::SHA1.digest(keyinfo.canonicalize(Nokogiri::XML::XML_C14N_1_0)))
    expect(actual).to eq(expected)
  end

  it "verifica localmente todos los digests y SignatureValue del XML final" do
    expect(described_class.verify_signature(signed, signer)).to be(true)
  end
end
