# frozen_string_literal: true

module SriFacturacion
  # Error base de la gema.
  class Error < StandardError; end

  # Datos de entrada inválidos (RUC, clave de acceso, etc.).
  class ValidationError < Error; end

  # Problema al cargar el certificado o al firmar el XML.
  class SignatureError < Error; end

  # Falla de transporte/protocolo al comunicarse con los web services del SRI.
  class SoapError < Error; end

  # El SRI devolvió el comprobante en recepción (estado DEVUELTA).
  class RecepcionError < Error
    attr_reader :mensajes

    def initialize(message, mensajes = [])
      super(message)
      @mensajes = mensajes
    end
  end
end
