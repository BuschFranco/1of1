# Estimación de almacenamiento por cantidad de usuarios — 1of1

Referencia para dimensionar la base y el plan de Supabase. **Actualizado con
mediciones reales** de la base en producción (Supabase Postgres, proyecto
`mwkrsqgdfnfidchotjel`, post-migración desde Notion — 18/07/2026).

Separa **datos estructurados** (filas en Postgres) de **media** (imágenes),
porque escalan muy distinto: las filas son diminutas, las imágenes son lo que
realmente pesa.

---

## 1. Medición real (base en producción)

Tamaño promedio por fila medido con `pg_column_size` sobre los datos reales:

| Tabla | Bytes/fila (medido) | Estimación previa | Con índices (×2.5) |
|---|---|---|---|
| matches | **161 B** | 400 B | ~0,4 KB |
| profiles | **414 B** | 2 KB | ~1 KB |
| users | **200 B** | 1 KB | ~0,5 KB |
| courts | **362 B** | 1 KB | ~0,9 KB |
| reviews | **157 B** | 500 B | ~0,4 KB |
| friends | **145 B** | 300 B | ~0,36 KB |
| pickups | **261 B** | 1 KB | ~0,65 KB |

- **Base completa hoy: ~11 MB** — casi todo es el piso fijo de un Postgres
  vacío (catálogos + overhead de Supabase). Los datos propios (~40 filas +
  índices) suman <0,5 MB.
- Las filas reales resultaron **3–5× más chicas** que la estimación original.
- Actualización (chat server-backed): desde la implementación del chat real, los
  **mensajes de pickup SÍ van a la base** (~160 B/fila, como matches). Se
  archivan en cascada al borrar el pickup o la cuenta, así que no se acumulan
  indefinidamente. Impacto: sumar ~30–60 mensajes/usuario activo/año ≈ **+10 KB**
  al número de abajo — despreciable frente al piso fijo.

## 2. Supuestos por usuario activo / año (recalibrados)

| Concepto | Volumen/año | Con índices | Subtotal |
|---|---|---|---|
| Partidos (matches) | ~208 (4/semana) | 0,4 KB | ~83 KB |
| Pickups | ~30 | 0,65 KB | ~20 KB |
| Chats (solo metadata) | ~30 | 0,6 KB | ~18 KB |
| Reseñas | ~5 | 0,4 KB | ~2 KB |
| **Variable/usuario activo/año** | | | **~125 KB** |

Fijo por usuario (una vez): profile + user + amistades ≈ **2 KB**.

> Número de trabajo redondeado con margen: **≈ 0,15 MB por usuario activo por
> año** (la estimación original decía 0,6 — era 4× conservadora).

"Activo" es la métrica que importa: 100 registrados con 20 activos pesan como
~20 activos. Los inactivos solo aportan sus ~2 KB de perfil.

## 3. Datos estructurados (acumulado, sin contar el piso fijo de ~11 MB)

A ~0,15 MB por usuario activo por año:

| Usuarios activos | Año 1 | Año 3 | Año 5 |
|---|---|---|---|
| 20 | ~3 MB | ~9 MB | ~15 MB |
| 100 | ~15 MB | ~45 MB | ~75 MB |
| 500 | ~75 MB | ~225 MB | ~375 MB |
| 1.000 | ~150 MB | ~450 MB | ~750 MB |
| 5.000 | ~750 MB | ~2,3 GB | ~3,8 GB |

Conclusión (mejor que la estimación previa): el **free tier de Supabase
(500 MB)** aguanta hasta ~**500 activos durante 3+ años** o ~1.000 activos por
más de 2 años, contando el piso de 11 MB.

## 4. Media (imágenes) — el driver real

Sin cambios de fondo: una foto de cancha (~1,5 MB) pesa más que **miles** de
filas de partidos. Hoy la base solo guarda **URLs** (avatar de Google, fotos
externas); cuando se hosteen imágenes propias van a **Supabase Storage** (1 GB
free) o **Cloudflare R2**, NUNCA a la base.

| Usuarios | Avatares (~0,3 MB) | Fotos de cancha (~1,5 MB, 1 c/5 usuarios) | Total media |
|---|---|---|---|
| 20 | ~6 MB | ~60 MB | **~66 MB** |
| 100 | ~30 MB | ~300 MB | **~330 MB** |
| 500 | ~150 MB | ~1,5 GB | **~1,65 GB** |
| 1.000 | ~300 MB | ~3 GB | **~3,3 GB** |

Comprimiendo al subir (máx 1280px, WebP ~200 KB) esto baja **5–10×**. Muy
recomendable implementarlo en la subida.

## 5. Recomendación de plan por escala (actualizada)

| Escala | DB (con piso) | Media | Plan | Costo |
|---|---|---|---|---|
| **20–500 activos** (hoy) | 15–90 MB | <1,7 GB* | **Supabase Free** | US$0 |
| 500–2.000 | 90–350 MB | 1,7–7 GB* | Free si se comprime media; si no, **Pro** | US$0–25/mes |
| 2.000–10.000 | 0,4–1,6 GB | 7–35 GB* | **Supabase Pro** (8 GB DB + 100 GB storage) | ~US$25/mes |

\* La media es lo único que empuja a pagar antes: el límite free de Storage es
1 GB. Con compresión al subir, el free tier alcanza mucho más lejos.

## 6. Resumen ejecutivo

- **Medido, no estimado**: hoy la base pesa 11 MB (piso fijo) y cada usuario
  activo agrega ~0,15 MB/año — 4× menos que la estimación original.
- Con 20 activos: ~3 MB/año de datos. El free tier alcanza para **años**, hasta
  ~500–1.000 activos.
- El único límite que se acerca antes es el **Storage de imágenes (1 GB free)**
  cuando se empiecen a hostear fotos propias: comprimir al subir lo estira 5–10×.
- Próximo escalón de pago: Supabase Pro (~US$25/mes), recién con miles de
  activos o mucha media sin comprimir.
