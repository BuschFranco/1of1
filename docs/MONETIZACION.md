# Monetización — 1of1

Documento de producto: oportunidades de ingresos, ordenadas por impacto vs.
esfuerzo, con una prioridad sugerida. No hay código atado a esto todavía —
primero hay que elegir dirección.

## Contexto

La app ya tiene piezas que habilitan cobrar:

- Pickups públicos y por código, con equipos A/B y chat server-backed.
- `rewards` en el pickup: `monetaria` ("Partido de $b"), `indumentaria`,
  `accesorios`, `otro` — el jugador paga al organizador, hoy en mano.
- `settings` de partido: edad/altura/peso/nivel/modalidad/marca (informativas).
- Canchas con detalle público, reseñas, ranking/clanes.

Hoy **no hay manejo de dinero dentro de la plataforma**: se paga en efectivo
fuera de la app y la app no ve transacciones.

## 1. B2B — canchas, marcas y ligas (organizadores) — el más natural

El usuario más valioso es quien organiza partidos con continuidad: la cancha
con horario fijo, la marca que quiere sponsorear una liga, el organizador del
"Partido de $b". Paga porque necesita visibilidad y operación.

### Badge "Oficial" / verificado + destaque

- Mensualidad por ser cancha/marca verificada.
- Su pickup sale primero o con sello ("Oficial") en la lista y en el chat.
- MVP sin pagos reales: **activación manual admin** (flag en el perfil) para
  probar la demanda antes de meter infra de cobro.

### Comisión sobre pickups pagos

- Hoy "Partido de $b" cobra a los jugadores (en mano, invisible para la app).
- El salto es cobrar digitalmente dentro de la app y quedarse un %
  (5–10%) de cada entrada.

### Sponsor de cancha

- Una marca paga por aparecer como "Cancha oficial" / sponsor destacado en el
  detalle de los pickups de esa zona, con su logo.

## 2. B2C — jugadores (premium)

Freemium clásico: el perfil gratis es funcional y se paga por algo que tenga
valor real — stats avanzadas, historial, insignias, perfil destacado.

**Cuándo vale la pena:** hoy la app todavía no genera suficientes datos
(historial, ELO, estadísticas) como para que un plan premium justifique su
precio. Esto es plata **cuando haya volumen y ranking/estadísticas**.

## 3. La palanca de todas: pagos in-app

Todo lo anterior (comisión, mensualidad, badge, sponsor) necesita que la
plataforma maneje dinero. Sin eso, la monetización real es manual: cobrar la
mensualidad por fuera y activar el badge a mano.

## Prioridad sugerida

1. **Badge "Oficial" + destaque con activación manual** — probar la demanda sin
   infra de pagos. La pieza más rápida de validar.
2. **Cobro digital + comisión sobre pickups pagos** — cuando haya tracción.
3. **Premium B2C** — después del ELO/volumen.

## Decisiones abiertas

- Precio de la mensualidad del badge.
- Qué incluye el "destaque" (orden en lista, sello en chat, filtro).
- % de comisión sobre pickups pagos.
- Proveedor de pagos (Stripe / Mercado Pago) y quién integra.
