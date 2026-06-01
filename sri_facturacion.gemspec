# frozen_string_literal: true

require_relative "lib/sri_facturacion/version"

Gem::Specification.new do |spec|
  spec.name = "sri_facturacion"
  spec.version = SriFacturacion::VERSION
  spec.authors = ["RysthDesign"]
  spec.summary = "Facturación electrónica SRI Ecuador (factura 01) en Ruby puro — modo pruebas por defecto."
  spec.description = <<~DESC
    Gema reutilizable para emitir facturas electrónicas (comprobante 01) ante el SRI de Ecuador.
    Genera la clave de acceso (módulo 11), construye el XML 1.1.0, lo firma con XAdES-BES
    (RSA-SHA1) usando un certificado .p12, y lo envía a los web services SOAP de recepción y
    autorización. Por defecto opera en el ambiente de PRUEBAS (1). No depende de Rails.
  DESC
  spec.homepage = "https://github.com/Rysth/GEM_SRI_Facturacion_RUBY"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "bigdecimal", "~> 3.1"
  spec.add_dependency "nokogiri", ">= 1.13"
  spec.add_dependency "prawn", ">= 2.4"
  spec.add_dependency "prawn-table", ">= 0.2"
  spec.add_dependency "rqrcode", ">= 2.0"

  spec.add_development_dependency "rspec", ">= 3.12"
end
