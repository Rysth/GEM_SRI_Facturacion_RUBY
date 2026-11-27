# Changelog

All notable changes to this project will be documented in this file.

## [0.2.1] - 2026-11-26

### Changed
- RIDE rediseñado: logo del emisor más grande (hasta 170×60), etiquetas completas y con tildes
  ("Obligado a llevar contabilidad", "Dirección sucursal" solo si difiere de la matriz), R.U.C. en el
  recuadro del comprobante, emisión "Normal", recuadro del cliente a la medida de sus datos.
- Totales como el RIDE del SRI: un subtotal por tarifa de IVA (15 %, 0 %, no objeto, exento),
  descuento solo si lo hay, IVA y valor total.
- Forma de pago con su plazo ("30 días") y nombres con tildes.
- Ambiente de pruebas: sello "PRUEBAS · SIN VALIDEZ TRIBUTARIA" en cada página.

## [0.2.0] - 2026-11-26

### Added
- `Signer.from_p12(bytes, password)`: abre la firma desde memoria y elige el certificado
  de la clave privada cuando el archivo trae la cadena de la CA.
- `Signer#certificate_info`, `#expires_at`, `#expired?` y `#belongs_to?(ruc)`.
- `Client#firmar`, `#recepcion`, `#autorizacion` y `#ride_pdf`: emisión paso a paso para
  jobs en segundo plano (el XML firmado se guarda antes de enviar). El ambiente sale de la clave.
- `config.proveedor_ruc`: agrega `RUCProveedorSistema` en infoAdicional (NAC-DGERCGC26-00000027).
- RIDE de **nota de crédito** (documento modificado y motivo) y pie configurable (`config.ride_footer`).

### Fixed
- Ruby 3.4: `base64` declarado como dependencia (ya no viene por defecto).
- Los mensajes del SRI ya no incluyen entradas vacías del `<mensaje>` interno.

## [0.1.0] - 2026-05-31

### Added
- Emisión de **factura** (comprobante 01): clave de acceso (módulo 11), XML 1.1.0,
  firma XAdES-BES (RSA-SHA1) con certificado `.p12`, envío SOAP de recepción y autorización.
- Emisión de **nota de crédito** (comprobante 04).
- Generación del **RIDE** en PDF (Prawn + QR con la clave de acceso).
- Validación de identificación: cédula, RUC, pasaporte y consumidor final.
- Configuración global o por instancia (`ambiente`, certificado, reintentos, timeouts).
- Ruby puro, sin dependencias de Rails.
