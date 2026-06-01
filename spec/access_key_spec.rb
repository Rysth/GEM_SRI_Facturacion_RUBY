# frozen_string_literal: true

require "date"

RSpec.describe SriFacturacion::AccessKey do
  base = {
    fecha_emision: Date.new(2026, 2, 7), # 07/02/2026
    tipo_comprobante: "01",
    ruc: "0924383631001",
    ambiente: "1",
    establecimiento: "001",
    punto_emision: "001",
    secuencial: "000000001",
    codigo_numerico: "12345678",
    tipo_emision: "1"
  }

  describe ".generate" do
    it "produce una clave de exactamente 49 dígitos numéricos" do
      clave = described_class.generate(**base)
      expect(clave.length).to eq(49)
      expect(clave).to match(/\A\d{49}\z/)
    end

    it "incluye la fecha en ddmmaaaa (0-7)" do
      expect(described_class.generate(**base)[0, 8]).to eq("07022026")
    end

    it "incluye tipo de comprobante (8-9)" do
      expect(described_class.generate(**base)[8, 2]).to eq("01")
    end

    it "incluye el RUC (10-22)" do
      expect(described_class.generate(**base)[10, 13]).to eq("0924383631001")
    end

    it "incluye el ambiente (23)" do
      expect(described_class.generate(**base)[23]).to eq("1")
    end

    it "incluye establecimiento y punto de emisión (24-29)" do
      clave = described_class.generate(**base)
      expect(clave[24, 3]).to eq("001")
      expect(clave[27, 3]).to eq("001")
    end

    it "incluye el secuencial (30-38)" do
      expect(described_class.generate(**base)[30, 9]).to eq("000000001")
    end

    it "incluye el código numérico (39-46) y tipo de emisión (47)" do
      clave = described_class.generate(**base)
      expect(clave[39, 8]).to eq("12345678")
      expect(clave[47]).to eq("1")
    end

    it "genera un código numérico aleatorio cuando no se da" do
      data = base.reject { |k, _| k == :codigo_numerico }
      c1 = described_class.generate(**data)
      c2 = described_class.generate(**data)
      expect(c1.length).to eq(49)
      expect(c2.length).to eq(49)
    end

    it "lanza error con RUC inválido" do
      expect { described_class.generate(**base.merge(ruc: "12345")) }
        .to raise_error(SriFacturacion::ValidationError, /RUC inválido/)
    end

    it "genera claves distintas para secuenciales distintos" do
      c1 = described_class.generate(**base.merge(secuencial: "000000001"))
      c2 = described_class.generate(**base.merge(secuencial: "000000002"))
      expect(c1).not_to eq(c2)
    end
  end

  describe ".valid?" do
    it "valida una clave generada por la propia gema" do
      clave = described_class.generate(**base.merge(ruc: "1790016919001", secuencial: "000000012", codigo_numerico: "87654321"))
      expect(described_class.valid?(clave)).to be(true)
    end

    it "rechaza longitud incorrecta y caracteres no numéricos" do
      expect(described_class.valid?("1234567890")).to be(false)
      expect(described_class.valid?("070220260109243836310011001000000001ABCD123411")).to be(false)
    end

    it "rechaza dígito verificador incorrecto" do
      clave = described_class.generate(**base)
      alterada = clave[0, 48] + ((clave[48].to_i + 1) % 10).to_s
      expect(described_class.valid?(alterada)).to be(false)
    end

    it "produce dígito verificador válido para varios RUCs" do
      %w[0924383631001 1790016919001 0991234567001].each do |ruc|
        clave = described_class.generate(**base.merge(ruc: ruc, codigo_numerico: "11111111"))
        expect(described_class.valid?(clave)).to be(true)
      end
    end

    it "produce dígito verificador válido para todos los tipos de comprobante" do
      %w[01 04 05 06 07].each do |tipo|
        clave = described_class.generate(**base.merge(tipo_comprobante: tipo, secuencial: "000000050", codigo_numerico: "99999999"))
        expect(described_class.valid?(clave)).to be(true)
      end
    end
  end

  describe ".parse" do
    it "extrae los componentes de una clave válida" do
      clave = described_class.generate(**base.merge(secuencial: "000000016", codigo_numerico: "12452940"))
      parsed = described_class.parse(clave)
      expect(parsed[:ruc]).to eq("0924383631001")
      expect(parsed[:tipo_comprobante]).to eq("01")
      expect(parsed[:ambiente]).to eq("1")
      expect(parsed[:establecimiento]).to eq("001")
      expect(parsed[:punto_emision]).to eq("001")
      expect(parsed[:secuencial]).to eq("000000016")
      expect(parsed[:codigo_numerico]).to eq("12452940")
      expect(parsed[:tipo_emision]).to eq("1")
    end

    it "devuelve nil para clave inválida" do
      expect(described_class.parse("0000")).to be_nil
    end
  end
end
