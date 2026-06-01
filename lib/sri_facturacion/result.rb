# frozen_string_literal: true

module SriFacturacion
  # Resultado de la emisión de un comprobante.
  class Result
    attr_reader :estado, :clave_acceso, :numero_autorizacion, :fecha_autorizacion,
                :xml_firmado, :xml_autorizado, :mensajes, :ride_pdf

    def initialize(success:, estado:, clave_acceso:, numero_autorizacion: nil, fecha_autorizacion: nil,
                   xml_firmado: nil, xml_autorizado: nil, mensajes: [], ride_pdf: nil)
      @success = success
      @estado = estado
      @clave_acceso = clave_acceso
      @numero_autorizacion = numero_autorizacion
      @fecha_autorizacion = fecha_autorizacion
      @xml_firmado = xml_firmado
      @xml_autorizado = xml_autorizado
      @mensajes = mensajes || []
      @ride_pdf = ride_pdf
    end

    def success?
      @success
    end

    def autorizado?
      estado == "AUTORIZADO"
    end

    def to_h
      {
        success: success?,
        estado: estado,
        clave_acceso: clave_acceso,
        numero_autorizacion: numero_autorizacion,
        fecha_autorizacion: fecha_autorizacion,
        mensajes: mensajes
      }
    end
  end
end
