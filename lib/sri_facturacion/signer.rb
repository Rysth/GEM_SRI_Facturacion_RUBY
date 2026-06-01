# frozen_string_literal: true

require "nokogiri"
require "openssl"
require "base64"
require "securerandom"
require "time"

module SriFacturacion
  # Firma XAdES-BES (enveloped) compatible con el SRI Ecuador, en Ruby puro.
  #
  # Parámetros exigidos por el SRI:
  #   - SignatureMethod  : RSA-SHA1
  #   - DigestMethod     : SHA-1
  #   - Canonicalización : C14N 1.0 (inclusive)
  #   - Transform        : enveloped-signature sobre la referencia #comprobante
  #   - QualifyingProperties / SignedProperties (XAdES) con SigningCertificate y DataObjectFormat
  #
  # Port estructural de XmlSignerService#signXml. La firma se ANEXA como hijo del nodo raíz
  # (id="comprobante").
  #
  # NOTA: la validación final real depende del SRI; ver README. Esta implementación verifica su
  # propia consistencia criptográfica (specs) pero no sustituye una prueba contra celcer.sri.gob.ec.
  class Signer
    DS = "http://www.w3.org/2000/09/xmldsig#"
    ETSI = "http://uri.etsi.org/01903/v1.3.2#"
    C14N_ALG = "http://www.w3.org/TR/2001/REC-xml-c14n-20010315"
    RSA_SHA1 = "http://www.w3.org/2000/09/xmldsig#rsa-sha1"
    SHA1_ALG = "http://www.w3.org/2000/09/xmldsig#sha1"
    ENVELOPED = "http://www.w3.org/2000/09/xmldsig#enveloped-signature"
    SIGNED_PROPS_TYPE = "http://uri.etsi.org/01903#SignedProperties"

    attr_reader :key, :certificate

    def initialize(key:, certificate:)
      @key = key
      @certificate = certificate
    end

    # Carga el certificado .p12 desde disco.
    def self.load(path, password)
      raise SignatureError, "El certificado no existe: #{path}" unless File.exist?(path)

      load_legacy_provider
      p12 = OpenSSL::PKCS12.new(File.binread(path), password.to_s)
      new(key: p12.key, certificate: p12.certificate)
    rescue OpenSSL::PKCS12::PKCS12Error => e
      raise SignatureError, "No se pudo abrir el .p12 (¿clave incorrecta?): #{e.message}"
    end

    def self.load_legacy_provider
      return unless OpenSSL.const_defined?(:Provider)

      OpenSSL::Provider.load("legacy")
    rescue OpenSSL::OpenSSLError
      nil
    end

    # Firma el XML y devuelve el XML firmado (string).
    def sign(xml_string)
      doc = Nokogiri::XML(xml_string) { |c| c.noblanks }
      root = doc.root
      raise SignatureError, "El XML no tiene elemento raíz" unless root

      root["id"] = "comprobante" unless root["id"] || root["Id"]
      ref_uri = root["id"] || root["Id"]

      # Digest de la referencia enveloped (#comprobante): SHA1 sobre la canonicalización del raíz
      # ANTES de anexar la firma (equivalente a aplicar enveloped-signature en validación).
      digest_comprobante = sha1_b64(canonicalize(root))

      ids = build_ids
      cert_der = certificate.to_der
      cert_b64 = base64(cert_der)
      cert_digest = sha1_b64(cert_der)
      signing_time = Time.now.iso8601

      # 1) Construir la firma con los DigestValue de SP/Cert vacíos para canonicalizar esos nodos.
      sig_doc = Nokogiri::XML(signature_template(
        ids: ids,
        ref_uri: ref_uri,
        digest_comprobante: digest_comprobante,
        cert_b64: cert_b64,
        cert_digest: cert_digest,
        signing_time: signing_time
      )) { |c| c.noblanks }

      sig_root = sig_doc.root

      keyinfo = at(sig_root, "ds:KeyInfo")
      signed_props = at(sig_root, "ds:Object/etsi:QualifyingProperties/etsi:SignedProperties")

      digest_cert = sha1_b64(canonicalize(keyinfo))
      digest_sp = sha1_b64(canonicalize(signed_props))

      # 2) Colocar los digests calculados en las referencias del SignedInfo.
      set_text(at(sig_root, "ds:SignedInfo/ds:Reference[@Type]/ds:DigestValue"), digest_sp)
      set_text(reference_to(sig_root, "#" + ids[:certificate]), digest_cert)

      # 3) Firmar la canonicalización del SignedInfo con RSA-SHA1.
      signed_info = at(sig_root, "ds:SignedInfo")
      signature_value = base64(key.sign(OpenSSL::Digest::SHA1.new, canonicalize(signed_info)))
      set_text(at(sig_root, "ds:SignatureValue"), signature_value)

      # 4) Anexar la firma al comprobante y serializar. add_child reparenta el nodo
      # de sig_doc al documento del comprobante (Nokogiri lo adopta automáticamente).
      root.add_child(sig_root)
      doc.to_xml(indent: 0, save_with: Nokogiri::XML::Node::SaveOptions::AS_XML)
    end

    private

    def build_ids
      rnd = SecureRandom.random_number(900_000) + 100_000
      sig = "Signature#{rnd}"
      {
        signature: sig,
        signed_info: "#{sig}-SignedInfo#{rnd}",
        signed_props: "#{sig}-SignedProperties#{rnd}",
        signed_props_ref: "SignedPropertiesID#{rnd}",
        signature_value: "SignatureValue#{rnd}",
        certificate: "Certificate#{rnd}",
        object: "#{sig}-Object#{rnd}",
        reference_id: "Reference-ID-#{rnd}"
      }
    end

    def signature_template(ids:, ref_uri:, digest_comprobante:, cert_b64:, cert_digest:, signing_time:)
      modulus = base64(certificate.public_key.n.to_s(2))
      exponent = base64(certificate.public_key.e.to_s(2))
      issuer = certificate.issuer.to_s(OpenSSL::X509::Name::RFC2253)
      serial = certificate.serial.to_s

      <<~XML
        <ds:Signature xmlns:ds="#{DS}" xmlns:etsi="#{ETSI}" Id="#{ids[:signature]}">
          <ds:SignedInfo Id="#{ids[:signed_info]}">
            <ds:CanonicalizationMethod Algorithm="#{C14N_ALG}"></ds:CanonicalizationMethod>
            <ds:SignatureMethod Algorithm="#{RSA_SHA1}"></ds:SignatureMethod>
            <ds:Reference Id="#{ids[:signed_props_ref]}" Type="#{SIGNED_PROPS_TYPE}" URI="##{ids[:signed_props]}">
              <ds:DigestMethod Algorithm="#{SHA1_ALG}"></ds:DigestMethod>
              <ds:DigestValue></ds:DigestValue>
            </ds:Reference>
            <ds:Reference URI="##{ids[:certificate]}">
              <ds:DigestMethod Algorithm="#{SHA1_ALG}"></ds:DigestMethod>
              <ds:DigestValue></ds:DigestValue>
            </ds:Reference>
            <ds:Reference Id="#{ids[:reference_id]}" URI="##{ref_uri}">
              <ds:Transforms>
                <ds:Transform Algorithm="#{ENVELOPED}"></ds:Transform>
              </ds:Transforms>
              <ds:DigestMethod Algorithm="#{SHA1_ALG}"></ds:DigestMethod>
              <ds:DigestValue>#{digest_comprobante}</ds:DigestValue>
            </ds:Reference>
          </ds:SignedInfo>
          <ds:SignatureValue Id="#{ids[:signature_value]}"></ds:SignatureValue>
          <ds:KeyInfo Id="#{ids[:certificate]}">
            <ds:X509Data>
              <ds:X509Certificate>#{cert_b64}</ds:X509Certificate>
            </ds:X509Data>
            <ds:KeyValue>
              <ds:RSAKeyValue>
                <ds:Modulus>#{modulus}</ds:Modulus>
                <ds:Exponent>#{exponent}</ds:Exponent>
              </ds:RSAKeyValue>
            </ds:KeyValue>
          </ds:KeyInfo>
          <ds:Object Id="#{ids[:object]}">
            <etsi:QualifyingProperties Target="##{ids[:signature]}">
              <etsi:SignedProperties Id="#{ids[:signed_props]}">
                <etsi:SignedSignatureProperties>
                  <etsi:SigningTime>#{signing_time}</etsi:SigningTime>
                  <etsi:SigningCertificate>
                    <etsi:Cert>
                      <etsi:CertDigest>
                        <ds:DigestMethod Algorithm="#{SHA1_ALG}"></ds:DigestMethod>
                        <ds:DigestValue>#{cert_digest}</ds:DigestValue>
                      </etsi:CertDigest>
                      <etsi:IssuerSerial>
                        <ds:X509IssuerName>#{issuer}</ds:X509IssuerName>
                        <ds:X509SerialNumber>#{serial}</ds:X509SerialNumber>
                      </etsi:IssuerSerial>
                    </etsi:Cert>
                  </etsi:SigningCertificate>
                </etsi:SignedSignatureProperties>
                <etsi:SignedDataObjectProperties>
                  <etsi:DataObjectFormat ObjectReference="##{ids[:reference_id]}">
                    <etsi:Description>contenido comprobante</etsi:Description>
                    <etsi:MimeType>text/xml</etsi:MimeType>
                  </etsi:DataObjectFormat>
                </etsi:SignedDataObjectProperties>
              </etsi:SignedProperties>
            </etsi:QualifyingProperties>
          </ds:Object>
        </ds:Signature>
      XML
    end

    NS = { "ds" => DS, "etsi" => ETSI }.freeze

    def at(node, xpath)
      node.at_xpath(xpath, NS) || raise(SignatureError, "No se encontró el nodo #{xpath} en la firma")
    end

    def reference_to(sig_root, uri)
      ref = sig_root.xpath("ds:SignedInfo/ds:Reference", NS).find { |r| r["URI"] == uri }
      raise SignatureError, "No se encontró la referencia #{uri}" unless ref

      ref.at_xpath("ds:DigestValue", NS)
    end

    def set_text(node, text)
      node.content = text
    end

    def canonicalize(node)
      node.canonicalize(Nokogiri::XML::XML_C14N_1_0)
    end

    def sha1_b64(bytes)
      base64(OpenSSL::Digest::SHA1.digest(bytes))
    end

    def base64(bytes)
      Base64.strict_encode64(bytes)
    end
  end
end
