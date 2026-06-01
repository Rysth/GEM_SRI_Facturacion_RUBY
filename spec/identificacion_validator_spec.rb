# frozen_string_literal: true

RSpec.describe SriFacturacion::IdentificacionValidator do
  describe ".validar_cedula" do
    it "acepta una cédula válida (módulo 10)" do
      expect(described_class.validar_cedula("0926789017").valido?).to be(true)
    end

    it "rechaza longitud incorrecta" do
      r = described_class.validar_cedula("123")
      expect(r.valido?).to be(false)
      expect(r.error).to match(/10 dígitos/)
    end

    it "rechaza provincia fuera de 01-24" do
      expect(described_class.validar_cedula("9926789017").valido?).to be(false)
    end

    it "rechaza un dígito verificador incorrecto" do
      expect(described_class.validar_cedula("0926789010").valido?).to be(false)
    end
  end

  describe ".validar_ruc" do
    it "acepta un RUC de persona natural válido (cédula + 001)" do
      expect(described_class.validar_ruc("0926789017001").valido?).to be(true)
    end

    it "rechaza un RUC con longitud incorrecta" do
      expect(described_class.validar_ruc("092678901").valido?).to be(false)
    end

    it "rechaza persona natural que no termina en establecimiento válido" do
      expect(described_class.validar_ruc("0926789017000").valido?).to be(false)
    end
  end

  describe ".validar (por tipo)" do
    it "consumidor final exige 9999999999999" do
      expect(described_class.validar("07", "9999999999999").valido?).to be(true)
      expect(described_class.validar("07", "123").valido?).to be(false)
    end

    it "pasaporte acepta 5-20 caracteres" do
      expect(described_class.validar("06", "AB12345").valido?).to be(true)
      expect(described_class.validar("06", "X").valido?).to be(false)
    end

    it "tipo desconocido es inválido" do
      expect(described_class.validar("99", "x").valido?).to be(false)
    end
  end
end
