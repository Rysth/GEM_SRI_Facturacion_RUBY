# Changelog

All notable changes to this project will be documented in this file.

## [0.1.0] - 2026-05-31

### Added
- Emisión de **factura** (comprobante 01): clave de acceso (módulo 11), XML 1.1.0,
  firma XAdES-BES (RSA-SHA1) con certificado `.p12`, envío SOAP de recepción y autorización.
- Emisión de **nota de crédito** (comprobante 04).
- Generación del **RIDE** en PDF (Prawn + QR con la clave de acceso).
- Validación de identificación: cédula, RUC, pasaporte y consumidor final.
- Configuración global o por instancia (`ambiente`, certificado, reintentos, timeouts).
- Ruby puro, sin dependencias de Rails.
