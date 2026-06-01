# frozen_string_literal: true

module SriFacturacion
  # Configuración global de la gema. El ambiente por defecto es "1" (PRUEBAS).
  #
  #   SriFacturacion.configure do |c|
  #     c.ambiente      = "1"            # "1" pruebas (default), "2" producción
  #     c.cert_path     = "/ruta/certificado.p12"
  #     c.cert_password = "clave"
  #     c.max_retries   = 3
  #     c.retry_delay   = 2              # segundos entre reintentos de autorización
  #   end
  class Configuration
    AMBIENTE_PRUEBAS = "1"
    AMBIENTE_PRODUCCION = "2"

    # WSDL/endpoints SOAP del SRP por ambiente (offline).
    ENDPOINTS = {
      AMBIENTE_PRUEBAS => {
        recepcion: "https://celcer.sri.gob.ec/comprobantes-electronicos-ws/RecepcionComprobantesOffline",
        autorizacion: "https://celcer.sri.gob.ec/comprobantes-electronicos-ws/AutorizacionComprobantesOffline"
      },
      AMBIENTE_PRODUCCION => {
        recepcion: "https://cel.sri.gob.ec/comprobantes-electronicos-ws/RecepcionComprobantesOffline",
        autorizacion: "https://cel.sri.gob.ec/comprobantes-electronicos-ws/AutorizacionComprobantesOffline"
      }
    }.freeze

    attr_accessor :ambiente, :cert_path, :cert_password, :max_retries, :retry_delay, :open_timeout, :read_timeout

    def initialize
      @ambiente = AMBIENTE_PRUEBAS # PRUEBAS por defecto
      @cert_path = nil
      @cert_password = nil
      @max_retries = 3
      @retry_delay = 2
      @open_timeout = 15
      @read_timeout = 30
    end

    def pruebas?
      ambiente.to_s == AMBIENTE_PRUEBAS
    end

    def recepcion_url(ambiente_override = nil)
      endpoints(ambiente_override).fetch(:recepcion)
    end

    def autorizacion_url(ambiente_override = nil)
      endpoints(ambiente_override).fetch(:autorizacion)
    end

    private

    def endpoints(ambiente_override)
      amb = (ambiente_override || ambiente).to_s
      ENDPOINTS[amb] || raise(ValidationError, "Ambiente inválido: #{amb.inspect} (use \"1\" o \"2\")")
    end
  end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
      configuration
    end

    # Restablece la configuración (útil en tests).
    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
