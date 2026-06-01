# frozen_string_literal: true

require "nokogiri"

RSpec.describe SriFacturacion::SoapClient do
  subject(:client) { described_class.new }

  describe "#parse_recepcion" do
    it "extrae el estado RECIBIDA" do
      xml = <<~XML
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body><ns2:validarComprobanteResponse xmlns:ns2="http://ec.gob.sri.ws.recepcion">
            <RespuestaRecepcionComprobante><estado>RECIBIDA</estado><comprobantes/></RespuestaRecepcionComprobante>
          </ns2:validarComprobanteResponse></s:Body>
        </s:Envelope>
      XML
      result = client.parse_recepcion(Nokogiri::XML(xml))
      expect(result[:estado]).to eq("RECIBIDA")
      expect(result[:mensajes]).to be_empty
    end

    it "extrae los mensajes cuando es DEVUELTA" do
      xml = <<~XML
        <Envelope><Body><RespuestaRecepcionComprobante>
          <estado>DEVUELTA</estado>
          <comprobantes><comprobante><claveAcceso>x</claveAcceso><mensajes>
            <mensaje><identificador>43</identificador><mensaje>RUC no existe</mensaje><tipo>ERROR</tipo></mensaje>
          </mensajes></comprobante></comprobantes>
        </RespuestaRecepcionComprobante></Body></Envelope>
      XML
      result = client.parse_recepcion(Nokogiri::XML(xml))
      expect(result[:estado]).to eq("DEVUELTA")
      expect(result[:mensajes].first[:mensaje]).to eq("RUC no existe")
      expect(result[:mensajes].first[:tipo]).to eq("ERROR")
    end
  end

  describe "#parse_autorizacion" do
    it "extrae estado, número y fecha de autorización" do
      xml = <<~XML
        <Envelope><Body><RespuestaAutorizacionComprobante>
          <claveAccesoConsultada>123</claveAccesoConsultada>
          <numeroComprobantes>1</numeroComprobantes>
          <autorizaciones><autorizacion>
            <estado>AUTORIZADO</estado>
            <numeroAutorizacion>0123456789</numeroAutorizacion>
            <fechaAutorizacion>2026-05-31T10:00:00-05:00</fechaAutorizacion>
            <comprobante>&lt;factura/&gt;</comprobante>
            <mensajes/>
          </autorizacion></autorizaciones>
        </RespuestaAutorizacionComprobante></Body></Envelope>
      XML
      result = client.parse_autorizacion(Nokogiri::XML(xml))
      expect(result[:estado]).to eq("AUTORIZADO")
      expect(result[:numero_autorizacion]).to eq("0123456789")
      expect(result[:fecha_autorizacion]).to eq("2026-05-31T10:00:00-05:00")
      expect(result[:comprobante]).to eq("<factura/>")
    end
  end

  describe "#enviar_y_autorizar" do
    it "devuelve DEVUELTA sin consultar autorización" do
      allow(client).to receive(:validar_comprobante).and_return(estado: "DEVUELTA", mensajes: [{ mensaje: "err" }])
      expect(client).not_to receive(:autorizar_comprobante)
      result = client.enviar_y_autorizar("<xml/>", "clave", ambiente: "1")
      expect(result.estado).to eq("DEVUELTA")
      expect(result.success?).to be(false)
    end

    it "devuelve AUTORIZADO cuando recepción y autorización son exitosas" do
      allow(client).to receive(:validar_comprobante).and_return(estado: "RECIBIDA", mensajes: [])
      allow(client).to receive(:autorizar_comprobante).and_return(
        estado: "AUTORIZADO", numero_autorizacion: "999", fecha_autorizacion: "2026-05-31", comprobante: "<f/>", mensajes: []
      )
      result = client.enviar_y_autorizar("<xml/>", "clave", ambiente: "1")
      expect(result.autorizado?).to be(true)
      expect(result.numero_autorizacion).to eq("999")
      expect(result.xml_autorizado).to eq("<f/>")
    end
  end
end
