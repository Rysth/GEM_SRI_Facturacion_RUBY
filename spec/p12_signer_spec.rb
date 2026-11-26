# frozen_string_literal: true

require "openssl"

RSpec.describe SriFacturacion::Signer do
  def make_cert(subject, key, issuer: nil, issuer_key: nil, ca: false, not_after: Time.now + (365 * 24 * 3600),
                extensions: [])
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = rand(1_000_000)
    cert.subject = OpenSSL::X509::Name.parse(subject)
    cert.issuer = issuer ? issuer.subject : cert.subject
    cert.public_key = key.public_key
    cert.not_before = Time.now - 3600
    cert.not_after = not_after
    factory = OpenSSL::X509::ExtensionFactory.new
    factory.subject_certificate = cert
    factory.issuer_certificate = issuer || cert
    cert.add_extension(factory.create_extension("basicConstraints", ca ? "CA:TRUE" : "CA:FALSE", true))
    extensions.each { |oid, value| cert.add_extension(OpenSSL::X509::Extension.new(oid, OpenSSL::ASN1::UTF8String.new(value).to_der)) }
    cert.sign(issuer_key || key, OpenSSL::Digest::SHA256.new)
    cert
  end

  let(:ca_key) { OpenSSL::PKey::RSA.new(2048) }
  let(:ca) { make_cert("/CN=Entidad de prueba/O=CA/C=EC", ca_key, ca: true) }
  let(:key) { OpenSSL::PKey::RSA.new(2048) }
  # Como las entidades del Ecuador: la cédula del titular en una extensión propia.
  let(:cert) do
    make_cert("/CN=JUAN PEREZ/serialNumber=171234567/C=EC", key, issuer: ca, issuer_key: ca_key,
                                                                 extensions: [["1.3.6.1.4.1.37746.3.1", "1712345678"]])
  end
  let(:p12_bytes) { OpenSSL::PKCS12.create("clave-secreta", "firma", key, cert, [ca]).to_der }

  it "abre el .p12 desde memoria y usa el certificado de la clave, no el de la CA" do
    signer = described_class.from_p12(p12_bytes, "clave-secreta")
    expect(signer.certificate.subject.to_s).to include("JUAN PEREZ")
    expect(signer.certificate.check_private_key(signer.key)).to be(true)
  end

  it "una contraseña equivocada da un error claro" do
    expect { described_class.from_p12(p12_bytes, "otra") }
      .to raise_error(SriFacturacion::SignatureError, /contraseña no es correcta/)
  end

  it "informa titular, cédula y vencimiento, y si pertenece a un RUC" do
    signer = described_class.from_p12(p12_bytes, "clave-secreta")
    info = signer.certificate_info
    expect(info[:subject]).to eq("JUAN PEREZ")
    expect(info[:cedula]).to eq("1712345678")
    expect(info[:expires_at]).to be > Time.now
    expect(signer.belongs_to?("1712345678001")).to be(true)
    expect(signer.belongs_to?("0999999999001")).to be(false)
    expect(signer.expired?).to be(false)
  end

  it "detecta un certificado vencido" do
    old = make_cert("/CN=VENCIDO/C=EC", key, not_after: Time.now - 60)
    expect(described_class.new(key: key, certificate: old).expired?).to be(true)
  end

  it "firma con el certificado cargado desde memoria" do
    signer = described_class.from_p12(p12_bytes, "clave-secreta")
    factura = build_sample_factura
    clave = SriFacturacion::AccessKey.generate(fecha_emision: factura.fecha_emision, ruc: factura.emisor.ruc,
                                                establecimiento: "001", punto_emision: "001", secuencial: factura.secuencial)
    signed = signer.sign(SriFacturacion::XmlBuilder.new(factura, clave_acceso: clave, ambiente: "1").build)
    expect(described_class.verify_signature(signed, signer)).to be_truthy
  end
end
