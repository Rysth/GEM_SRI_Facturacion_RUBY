# sri_facturacion

Facturación electrónica del **SRI Ecuador** (comprobante **factura 01**) en **Ruby puro**.
Genera la clave de acceso (módulo 11), construye el XML 1.1.0, lo firma con **XAdES-BES**
(RSA-SHA1) usando un certificado `.p12`, lo envía a los web services SOAP de **recepción** y
**autorización**, y opcionalmente genera el **RIDE** en PDF con su código QR.

- ✅ Factura (comprobante `01`)
- ✅ Nota de crédito (comprobante `04`)
- ✅ RIDE en PDF (Prawn + QR)
- ✅ Validación de identificación (cédula, RUC, pasaporte, consumidor final)
- ✅ **Sin dependencias de Rails** — funciona en cualquier proyecto Ruby
- 🧪 Por defecto opera en el ambiente de **PRUEBAS** (`1`)

> ⚠️ El **RUC del emisor debe coincidir** con el RUC para el que se emitió el certificado `.p12`,
> o el SRI rechaza el comprobante (DEVUELTA / NO AUTORIZADO).

## Instalación

En el `Gemfile`:

```ruby
# Por path local
gem "sri_facturacion", path: "vendor/gems/sri_facturacion"

# O por git (fijando la versión)
gem "sri_facturacion", git: "https://github.com/Rysth/GEM_SRI_Facturacion_RUBY", tag: "v0.2.0"

# O publicada en RubyGems
gem "sri_facturacion"
```

Requiere **Ruby >= 3.1**. Dependencias: `nokogiri`, `prawn`, `prawn-table`, `rqrcode`, `bigdecimal`, `base64`.

## Configuración

```ruby
SriFacturacion.configure do |c|
  c.ambiente      = "1"                       # "1" pruebas (default) · "2" producción
  c.cert_path     = "/ruta/al/certificado.p12"
  c.cert_password = "clave_del_certificado"
  c.max_retries   = 3                         # reintentos de autorización
  c.retry_delay   = 2                         # segundos entre reintentos
end
```

También puedes pasar una `Configuration` por instancia a `Client.new(config: ...)` (útil para
multi-emisor / multi-negocio sin estado global).

## Uso: emitir una factura

```ruby
emisor = SriFacturacion::Emisor.new(
  ruc: "1790012345001",
  razon_social: "Comercial Ejemplo S.A.",
  nombre_comercial: "Mi Tienda",
  dir_matriz: "Av. Principal 123, Guayaquil",
  establecimiento: "001",
  punto_emision: "001",
  obligado_contabilidad: "SI"
)

comprador = SriFacturacion::Comprador.new(
  razon_social: "Juan Pérez",
  tipo_identificacion: "05",      # 04=RUC · 05=cédula · 06=pasaporte · 07=consumidor final
  identificacion: "0912345678",
  direccion: "Cdla. Kennedy",
  email: "juan@example.com"
)

detalles = [
  SriFacturacion::Detalle.new(
    codigo_principal: "SKU-001",
    descripcion: "Producto de ejemplo",
    cantidad: 2,
    precio_unitario: 25.00,
    descuento: 0,
    impuestos: [SriFacturacion::Impuesto.iva(50.00)]  # IVA 15% sobre la base
  )
]

factura = SriFacturacion::Factura.new(
  emisor: emisor,
  comprador: comprador,
  detalles: detalles,
  secuencial: "1"
)

result = SriFacturacion.emitir!(factura, generar_ride: true)

if result.autorizado?
  puts "Autorizada: #{result.numero_autorizacion}"
  File.binwrite("factura.xml", result.xml_autorizado)
  File.binwrite("factura.pdf", result.ride_pdf)   # presente si generar_ride: true
else
  puts "Estado: #{result.estado}"
  puts result.mensajes   # [{ tipo:, identificador:, mensaje:, informacion_adicional: }, ...]
end
```

### El `Result`

| Atributo | Descripción |
|----------|-------------|
| `success?` / `autorizado?` | Booleanos de éxito / autorización |
| `estado` | `AUTORIZADO`, `NO AUTORIZADO`, `DEVUELTA`, `EN PROCESO`, `RECIBIDA` |
| `clave_acceso` | Clave de acceso de 49 dígitos |
| `numero_autorizacion` | Número de autorización del SRI |
| `fecha_autorizacion` | Fecha/hora de autorización |
| `xml_firmado` / `xml_autorizado` | XML firmado / autorizado |
| `ride_pdf` | Bytes del PDF del RIDE (si `generar_ride: true`) |
| `mensajes` | Mensajes del SRI (errores/avisos) |

## Generar solo el RIDE (PDF)

```ruby
pdf = SriFacturacion::Ride.new(
  factura,
  clave_acceso: result.clave_acceso,
  numero_autorizacion: result.numero_autorizacion,
  ambiente: "1"
).render

File.binwrite("ride.pdf", pdf)
```

## Previsualizar el XML sin firmar/enviar

```ruby
xml = SriFacturacion::Client.new.preview_xml(factura)
```

## Paso a paso (sistemas con cola de trabajos)

Para no perder nunca un comprobante, guarde la clave y el XML firmado **antes** de
enviarlos; envíe y consulte la autorización desde un job con reintentos:

```ruby
signer = SriFacturacion::Signer.from_p12(p12_bytes, password) # desde memoria
signer.expired?                     # => false
signer.certificate_info             # => { subject:, issuer:, ruc:, cedula:, expires_at: }
signer.belongs_to?("1712345678001") # => true (persona natural: cédula + 001)

config = SriFacturacion::Configuration.new.tap do |c|
  c.ambiente = "1"
  c.proveedor_ruc = "1790000000001" # RUCProveedorSistema en infoAdicional
  c.ride_footer = "RIDE generado por Mi Sistema"
end
client = SriFacturacion::Client.new(config: config, signer: signer)

firmado = client.firmar(factura_o_nota_credito)   # { clave_acceso:, xml_firmado: } (sin red)
# ...guardar firmado en la base de datos...
client.recepcion(firmado[:xml_firmado], firmado[:clave_acceso]) # { estado: "RECIBIDA" | "DEVUELTA", mensajes: }
client.autorizacion(firmado[:clave_acceso])       # { estado: "AUTORIZADO" | "NO AUTORIZADO" | nil, ... }
pdf = client.ride_pdf(comprobante, clave_acceso: firmado[:clave_acceso], numero_autorizacion: "...")
```

El ambiente de `recepcion` y `autorizacion` sale de la clave de acceso, no de la configuración.
`Detalle` acepta `precio_total_sin_impuesto` e `Impuesto` un `valor` explícito, para enviar
exactamente lo que se cobró.

## Nota de crédito (comprobante 04)

```ruby
nota = SriFacturacion::NotaCredito.new(
  emisor: emisor,
  comprador: comprador,
  detalles: detalles,
  cod_doc_modificado: "01",
  num_doc_modificado: "001-001-000000001",
  fecha_emision_doc_sustento: Date.new(2026, 1, 10),
  motivo: "Devolución parcial"
)

result = SriFacturacion.emitir_nota_credito!(nota)
```

## Impuestos disponibles

```ruby
SriFacturacion::Impuesto.iva(base)        # 15% (vigente Ecuador 2024+)
SriFacturacion::Impuesto.iva_doce(base)   # 12% (histórico)
SriFacturacion::Impuesto.iva_cero(base)   # 0%
SriFacturacion::Impuesto.iva_exento(base) # exento
SriFacturacion::Impuesto.iva_no_objeto(base)
```

## Desarrollo

```bash
bundle install
bundle exec rspec
```

## Seguridad

No incluyas certificados `.p12`/`.pfx` ni contraseñas en el control de versiones. Cárgalos por
configuración/variables de entorno y mantén la clave cifrada en tu aplicación.

## Licencia

MIT © RysthDesign
