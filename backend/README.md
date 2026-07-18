# Backend — 1of1

API NestJS de la app, respaldada por **Supabase Postgres vía Prisma** (migrada
desde Notion; el gateway de Notion quedó solo como legado para el script de
migración). Autentica con JWT propio y expone la API por dominio.

## Correr

```bash
npm install
cp .env.example .env       # completar DATABASE_URL/DIRECT_URL y JWT_SECRET
npx prisma migrate deploy  # aplica migraciones (crea/actualiza tablas)
npm run start:dev          # http://localhost:3000
npm run build              # compila a dist/
```

## Base de datos

- **Supabase Postgres** (proyecto `mwkrsqgdfnfidchotjel`, São Paulo). Data API
  apagada: el ÚNICO cliente es este backend, por connection string.
- `DATABASE_URL` = pooler transaccional (puerto 6543, `?pgbouncer=true`) para
  runtime; `DIRECT_URL` = puerto 5432 para `prisma migrate`.
- Esquema en `prisma/schema.prisma`; cambios de esquema =
  `npx prisma migrate dev --name <nombre>` (nunca tocar tablas a mano).
- **IDs**: PKs UUID; los datos migrados conservan los pageId de Notion, así los
  JWT y los ids cacheados en la app siguieron válidos tras la migración.
- **Borrado lógico**: `archived=true` (nunca hard-delete); toda lectura filtra
  `archived=false`.
- **Fechas**: regla heredada — un ISO sin offset se interpreta como **UTC**
  (`domain/wire.ts: parseUtc`). No cambiar: el dedup del backfill de la app
  compara el reloj de pared de los primeros 16 chars.
- Migración one-off de datos: `node scripts/migrate-notion.mjs` (idempotente;
  requiere `NOTION_TOKEN` legado en `.env`).

## Auth

- JWT Bearer (30 días por default). Payload: `{ sub, email, profileId, isAdmin }`.
- Hash de password: `sha256("<email_lowercase>:<password>")` hex — compatible
  con las cuentas creadas por la app contra Notion directo.
- Cuentas de Google: `PasswordHash = 'google:'` (sin contraseña; solo entran
  por `/auth/google`).

## Contratos (endpoint → request → response)

Todos protegidos con `Authorization: Bearer <jwt>` salvo los de `/auth`.

### Auth (públicos)

| Endpoint | Body | Devuelve |
| --- | --- | --- |
| `POST /auth/login` | `{email, password}` | `{token, profile}` |
| `POST /auth/register` | `{email, password, name, city?, phone?, birthdate?}` | `{token, profile}` |
| `POST /auth/google` | `{idToken}` (verificado server-side; `GOOGLE_CLIENT_IDS` restringe el aud) | `{token, profile}` — find-or-create |

### Perfil propio

| Endpoint | Body / Query | Devuelve |
| --- | --- | --- |
| `GET /me` | — | `Profile` |
| `PATCH /me` | `Partial<Profile>` (flush de stats/clan/título/privacidad; `Adm` NO es escribible) | `Profile` |
| `POST /me/handle` | `{handle}` (valida formato + unicidad) | `Profile` |
| `PATCH /me/presence` | `{playing, courtId?, since?}` | `Profile` |
| `DELETE /me` | — | `{ok, archived}` — archiva matches/reseñas/amistades/pickups/perfil/usuario (requisito de tiendas) |

### Perfiles públicos

| Endpoint | Query | Devuelve |
| --- | --- | --- |
| `GET /profiles` | — | `Profile[]` (amigos/proponentes/presencia) |
| `GET /profiles/by-handle` | `?handle=` | `Profile` (404 si no existe) |

### Canchas y reseñas

| Endpoint | Body / Query | Devuelve |
| --- | --- | --- |
| `GET /courts` | — | `Court[]` (solo `Aprobacion == "Aprobado"`) |
| `GET /courts/mine` | — | `Court[]` propias (TODOS los estados; el cliente detecta aprobación/rechazo comparando `approval`) |
| `POST /courts` | `ProposeCourtDto` (autor sale del token; entra "Sin definir") | `Court` |
| `GET /courts/:courtId/reviews` | — | `Review[]` |
| `POST /courts/:courtId/reviews` | `{rating (1-5), comment}` (email+handle del token) | `Review` |
| `DELETE /courts/:courtId` | — (solo `isAdmin`) | `{ok}` — archiva la cancha Y sus reseñas |
| `DELETE /reviews/:pageId` | — (dueño de la reseña o `isAdmin`) | `{ok}` |

### Amistades

| Endpoint | Body | Devuelve |
| --- | --- | --- |
| `GET /friends` | — | `Friend[]` (por OwnerEmail del token) |
| `POST /friends` | `{friendHandle, friendName, friendEmail}` | `Friend` |
| `DELETE /friends/:pageId` | — | `{ok}` |

### Pickups y chats

| Endpoint | Body | Devuelve |
| --- | --- | --- |
| `GET /pickups` | — | `Pickup[]` míos (creador O miembro de un equipo) |
| `POST /pickups` | `{title, courtId, dateTime?, maxPlayers?, vibe?, notes?, teamSize?, teamA/BName?, teamA/BColor?, teamA/BMembers?, targetScore?, accepted/declinedMembers?}` — el `inviteCode` de 5 dígitos lo genera el server | `Pickup` |
| `POST /pickups/join` | `{code}` (5 dígitos) — entra al equipo con espacio (menos miembros primero) como aceptado | `Pickup` (404 código inválido / 403 propio, lleno, ya unido o expirado) |
| `PATCH /pickups/:pageId` | mismos campos opcionales (update parcial; solo creador/miembro) — cubre aceptar/rechazar/mover/quitar/abandonar/reenviar | `Pickup` |
| `DELETE /pickups/:pageId` | — (solo el creador) | `{ok}` — archiva pickup + chat + mensajes |
| `GET /pickups/:pageId/messages` | `?after=<ISO>` (opcional, polling incremental) — solo creador/miembro (403 si no) | `{messages: [{id, email, text, createdAt}]}` orden asc, máx 200 |
| `POST /pickups/:pageId/messages` | `{text}` (1–500 chars) — solo creador/miembro | `{id, email, text, createdAt}` |
| `POST /chats` | `{name, pickupId, date?, teamA/BName?, teamA/BColor?, lastMessage?}` | `CrewChat` (metadata del chat de crew) |

El chat de pickups es **server-backed** (tabla `messages`): mensajes reales,
polling incremental cada 4 s en la app. `/chats` sigue siendo solo la metadata.

### Uploads (Supabase Storage)

| Endpoint | Body | Devuelve |
| --- | --- | --- |
| `POST /uploads/court-image` | multipart `file` (webp/jpeg/png, máx 8 MB; la app comprime a WebP antes) | `{url}` pública del bucket `media` (503 si falta `SUPABASE_SERVICE_KEY`) |

Sube con la service key server-side (bypassa RLS); la URL pública se guarda como
texto en `courts.img`. La DB nunca ve bytes de imagen.

### Historial de partidos (ranking)

| Endpoint | Body / Query | Devuelve |
| --- | --- | --- |
| `POST /matches` | `{matches: [{points, endedAt, courtId?, courtName?, result?, seconds?}]}` — lote; el email sale del token | `{results: [{ok}]}` por ítem (el cliente reintenta solo los fallidos) |
| `GET /matches/ranking` | `?since=<ISO>&emails=a,b,c` (máx 100) | `[{email, points}]` |

## Notion

- `notion/notion.service.ts` es el único cliente (portado del NotionService de
  la app: mismos builders/parsers/filtros + `queryDatabaseAll` paginado y los
  filtros `filterOr/filterAnd/filterTextContains/filterDateOnOrAfter`).
- `ProfilesService.onModuleInit()` corre al arrancar y asegura (idempotente) las
  columnas de las bases — espejo del `_ensureNotionSchema` de la app. **Nunca
  declara columnas `select` existentes** (`Aprobacion`, `Status`, `Result`):
  el PATCH de Notion las dejaría sin opciones y borraría los valores.
- Bases (env `NOTION_DB_*`, defaults embebidos): users, profiles, courts,
  reviews, pickups, friends, matches, chats (vacío = feature off).
- Google sign-in: `POST /auth/google` verifica el idToken server-side con
  `google-auth-library`; `GOOGLE_CLIENT_IDS` (CSV) restringe el `aud`.

## Estado

- La app YA consume esta API (Fase A' completada): el token de Notion salió de
  la APK y vive solo en `.env`. En beta el server corre en la PC del dev
  (`app.listen` en `0.0.0.0`; la app se conecta por la IP LAN, ver
  `app/dart_defines.json` → `API_BASE_URL`).
- Smoke tests end-to-end pasados contra el workspace real (register, PATCH /me,
  courts con `openTime/closeTime`, review propia crear/borrar, DELETE /me).

## Pendiente

- Hosting con TLS (al migrar, borrar `network_security_config.xml` de la app).
- Hardening producción: migrar hash a bcrypt (re-hash en login), rate limiting,
  helmet.
