# Backend — 1of1

Gateway NestJS entre la app y Notion. Centraliza el token de Notion
**server-side** (la app ya no lo embebe), autentica con JWT propio y expone la
API por dominio. Es la "Fase A"; la migración del front a esta API es la
Fase A'.

## Correr

```bash
npm install
cp .env.example .env   # completar NOTION_TOKEN y JWT_SECRET
npm run start:dev      # http://localhost:3000
npm run build          # compila a dist/
```

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
| `DELETE /pickups/:pageId` | — (solo el creador) | `{ok}` — archiva pickup + chat asociado |
| `POST /chats` | `{name, pickupId, date?, teamA/BName?, teamA/BColor?, lastMessage?}` | `CrewChat` (503 si `NOTION_DB_CHATS` no está configurada) |

Los MENSAJES de chat no pasan por acá: viven locales en la app. `/chats` es
solo la metadata (ficha del chat de crew).

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
