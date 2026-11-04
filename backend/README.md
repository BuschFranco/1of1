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
- Hash de password: **bcrypt** (`bcryptjs`, costo 10) para cuentas nuevas.
  Los hashes legados de Notion (`sha256("<email_lowercase>:<password>")` hex,
  sin salt) siguen verificándose en el login y se reemplazan por bcrypt en el
  momento (migración lazy, sin interrumpir a nadie).
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
| `DELETE /me` | — | `{ok, archived}` — archiva matches/historial/listas/reseñas/amistades/pickups/perfil/usuario (requisito de tiendas) |

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
| `POST /pickups` | `{title, courtId, dateTime, maxPlayers?, vibe?, notes?, teamSize?, teamA/BName?, teamA/BColor?, teamA/BMembers?, targetScore?, accepted/declinedMembers?, isPublic?, rewards?, settings?}` — `dateTime` es **obligatorio** (ISO); el `inviteCode` de 5 dígitos lo genera el server; **el creador entra al equipo que elija** (A o B; clientes viejos que no lo mandan: equipo con lugar, A primero) y a `acceptedMembers`. `rewards` (opcional): `[{type, amount?, detail?}]` con `type` ∈ `monetaria` (exige `amount` ARS ≥ 1) / `indumentaria` / `accesorios` / `otro` (exigen `detail` ≤ 40 chars); 1 solo reward por tipo, combinables. `settings` (opcional, informativos): `[{type, min?/minCm?/maxKg?, value?, brand?, useKit?}]` con `type` ∈ `edad` (min años, 1–120) / `altura` (minCm, 100–260) / `peso` (maxKg, 35–250) / `nivel` (`value`: `profesional`\|`amateur`) / `modalidad` (`value`: `competencia`\|`casual`) / `marca` (`brand` ≤ 40 chars, `useKit?`); 1 sola config por tipo, se descartan las mal formadas | `Pickup` |
| `POST /pickups/join` | `{code}` (5 dígitos) — entra al equipo con espacio (menos miembros primero) como aceptado | `Pickup` (404 código inválido / 403 propio, lleno, ya unido o expirado) |
| `PATCH /pickups/:pageId` | mismos campos opcionales (update parcial; solo creador/miembro) — cubre aceptar/rechazar/mover/quitar/abandonar/reenviar | `Pickup` |
| `DELETE /pickups/:pageId` | — (solo el creador) | `{ok}` — archiva pickup + chat + mensajes |
| `GET /pickups/:pageId/messages` | `?after=<ISO>` (opcional, polling incremental) — solo creador/miembro (403 si no) | `{messages: [{id, email, text, createdAt}]}` orden asc, máx 200 |
| `POST /pickups/:pageId/messages` | `{text}` (1–500 chars) — solo creador/miembro | `{id, email, text, createdAt}` |
| `POST /chats` | `{name, pickupId, date?, teamA/BName?, teamA/BColor?, lastMessage?}` | `CrewChat` (metadata del chat de crew) |

El chat de pickups es **server-backed** (tabla `messages`): mensajes reales,
polling incremental cada 4 s en la app. `/chats` sigue siendo solo la metadata.

### Uploads (R2 o Supabase Storage)

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
| `GET /matches/mine` | — | partidos del usuario del token |
| `GET /matches/court-king` | `?courtId=` | `{name, handle, points}` — rey de la cancha en la temporada |
| `GET /matches/court-points` | `?courtId=` | mis puntos acumulados en esa cancha |

### Respaldo del historial (sync)

Lo que la app guardaba SOLO en el teléfono, para que reinstalar o cambiar de
celular no lo borre. **Nunca guarda datos de salud**: el cliente no los manda y
el servidor aplica una lista blanca (`sanitizeSessionData`) que descarta todo lo
que no esté permitido. No toca `matches` (los rankings leen de ahí).

| Endpoint | Body / Query | Devuelve |
| --- | --- | --- |
| `POST /sync/sessions` | `{sessions: [{endedAtMs, data}]}` — lote de hasta **50**; `endedAtMs` (epoch ms) es la identidad | `{results: [{ok}]}` por ítem. **Upsert** por `(email, endedAtMs)`: reintentar no duplica |
| `GET /sync/sessions` | `?limit=100&before=<ms>` (tope 200) | `{sessions: [{endedAtMs, data}]}`, más nuevas primero |
| `DELETE /sync/sessions/:endedAtMs` | — | `{ok: true}`. El usuario la borró del historial: queda **archivada** (no vuelve al restaurar). Si no estaba subida se crea archivada, así un upload en cola no la revive |
| `GET /sync/data` | — | `{streak_history?, favorites?, blocked?}`. Un `kind` **ausente** = nunca sincronizado; **vacío** = el usuario lo vació |
| `PUT /sync/data/:kind` | `{data: [...]}` — `kind` ∈ `streak_history`, `favorites`, `blocked` | `{ok, count}`. **Reemplaza** el contenido |

`data` de una sesión admite solo: `courtId`, `courtName`, `seconds`, `result`,
`points`, `uPts`, `u3`, `u2`, `uFT`, `nMatches`, `nTrainings`, `nWins`, `gamePts[]`,
`gameFmt[]`, `hidden[]` (los mismos que `PlaySession.toSyncJson` en la app). Los
emails se guardan en minúsculas y `DELETE /me` archiva ambas tablas.

### Rankings y clanes

| Endpoint | Request | Response |
| --- | --- | --- |
| `GET /rankings/global` | `?since=<ISO>` | ranking global del período |
| `GET /clans/ranking` | `?since=<ISO>` | ranking por insignia de clan |
| `GET /clans/court-owner` | `?courtId=` | `{clan, points}` — clan que conquistó la cancha |

### Publicaciones de cancha

| Endpoint | Request | Response |
| --- | --- | --- |
| `GET /courts/:courtId/posts` | `?limit=&cursor=` | página de publicaciones |
| `POST /courts/:courtId/posts` | `{content}` | la publicación creada |
| `DELETE /posts/:id` | — | archiva (dueño o admin) |
| `POST /posts/:id/comments` | `{content}` | el comentario creado |

### Otros

| Endpoint | Request | Response |
| --- | --- | --- |
| `POST /uploads/court-image` | multipart | `{url}` — sube a R2 (o a Supabase Storage sin las `R2_*`) |
| `GET /health` | — | `1` (texto). Health check del deploy y de Render |
| `GET /news?league=nba\|wnba\|lnb\|3x3` | — | `[{title, summary, url, imageUrl, source, publishedAt}]`. Caché 30 min |
| `GET /scores/games?league=nba\|wnba` | — | `[{id, date, state (pre/in/post), status, home, away}]`: hoy y los 3 días anteriores, más nuevos primero. Fuente: ESPN (no oficial). Caché 1 min con partidos en vivo, si no 10 min |
| `GET /scores/games/:id?league=` | — | `{game, columns, teams, timeline, preview}` o `null`. `teams`: box por equipo (colores, puntos por cuarto, jugadores con id/foto). `timeline`: jugada a jugada clasificada (la app arma el box de cualquier momento). `preview`: pronóstico ESPN, últimos 5, cara a cara, comparativa, líderes y lesionados (también para partidos sin jugar, con `teams` vacío) |
| `GET /scores/standings?league=` | — | `[{name (conferencia), rows: [{id, seed, name, abbr, logo, wins, losses, pct, gamesBehind, streak}]}]`. Caché 30 min |
| `GET /scores/power?league=` | — | Power ranking ESPN BPI: `[{id, name, abbr, logo, rank, bpi, projW, projL, playoffs, playIn, finals, title}]` (porcentajes 0-100). Caché 6 h |
| `GET /scores/players/:id?league=` | — | `{name, headshot, position, jersey, team, info, season, career, lastGames}` (promedios de temporada y carrera, últimos partidos) o `null`. Caché 1 h |
| `GET /scores/teams/:id?league=` | — | `{name, abbr, logo, color, record, standing, power, averages, roster}` (plantel con promedios de cada jugador) o `null`. Caché 1 h |

> `PATCH /pickups/:pageId` también cubre la **reprogramación** (campo `dateTime`):
> es lo que usa el creador para mover fecha/hora desde el chat del pickup. El
> guard del endpoint es "miembro del pickup", no "creador": la restricción a
> creador la impone el cliente.

## Base de datos

- **Prisma sobre Supabase Postgres.** El schema es
  [`prisma/schema.prisma`](prisma/schema.prisma) y se cambia con migraciones
  (`npx prisma migrate dev --name <algo>`); no hay código de arranque que ajuste
  columnas.
- **`src/domain/wire.ts`** es el traductor entre la fila de la base y el JSON que
  consume la app (`profileWire` / `profilePatchToData` y sus pares por dominio).
  Si agregás un campo, va acá además del schema.
- Google sign-in: `POST /auth/google` verifica el idToken server-side con
  `google-auth-library`; `GOOGLE_CLIENT_IDS` (CSV) restringe el `aud`.

> **`src/notion/` es código muerto**: quedó de la etapa en que la base era Notion
> y **no está registrado en `app.module.ts`**. No lo tomes como referencia; se
> conserva solo por el script de migración.

## Estado

Corre en la **VPS de Hetzner** (`https://api.buschfranco.com`) con la base en
PostgreSQL local; `app/dart_defines.json` apunta ahí, así que la app no necesita
un backend local. Deploy: push a `main` que toque `backend/` → GitHub Actions
compila y publica. Las variables viven en `/etc/oneofone/oneofone.env`.

**Mudado a la VPS** (3/11/2026, ver la sección siguiente). Render quedó solo
como reenvío para las apps ya instaladas y Supabase ya no se usa.

## VPS (Hetzner) — `https://api.buschfranco.com`

El backend se suma a la VPS que ya corre Rebound y el portafolio (`2.31.106.97`,
Ubuntu, 1 GB de RAM + 2 GB de swap), con el mismo esquema que esos proyectos.

- **Cómo funciona:** cada push a `main` que toque `backend/` dispara
  `.github/workflows/backend-vps.yml`. GitHub compila (la VPS no compila), sube
  `dist` + `node_modules` de producción por SSH con el usuario `deploy` y corre
  `oneofone-deploy <commit>`. Ese script descomprime en
  `/srv/oneofone/releases/<commit>`, corre `prisma migrate deploy` (si falla,
  no cambia nada), apunta `/srv/oneofone/current` ahí, reinicia y chequea
  `/health`; si no responde, vuelve sola a la versión anterior. Guarda las
  últimas 3.
- **En el servidor:** servicio `oneofone` (systemd, usuario `oneofone`, puerto
  **3002** local, tope de 300 MB), Caddy adelante (`api-buschfranco.caddy`),
  Cloudflare con proxy. Variables en `/etc/oneofone/oneofone.env`.
- **Base:** `oneofone` en el PostgreSQL 16 de la VPS (solo local), rol dueño
  `oneofone` (contraseña en `/root/oneofone-db.env`). Conexión directa, sin
  pgbouncer: `DATABASE_URL` y `DIRECT_URL` son la misma. Backup semanal a R2
  (`rebound-backups/oneofone/`, se borran a los 90 días).
- **Fotos:** Cloudflare R2, bucket `oneofone-media`, dominio
  `https://img.buschfranco.com`. Con las `R2_*` cargadas el backend sube ahí;
  sin ellas, a Supabase Storage (lo que usa Render hasta el corte).
- **Puertos en la VPS:** 3000 Rebound, 3001 portafolio, 3002 1of1, 3010
  PostgREST, 5432 Postgres (todos locales; afuera solo 22/80/443).

### Scripts (`backend/deploy/vps/`, se corren como root en la VPS)

| Script | Qué hace |
| --- | --- |
| `provision.sh "<clave pública>"` | Usuario, carpetas, servicio, sudoers del deploy y sitio de Caddy. Repetible. |
| `provision-db.sh` | Rol y base `oneofone`; escribe `DATABASE_URL`/`DIRECT_URL`. Las tablas las crea el primer deploy. |
| `oneofone-deploy` | Publica una versión (lo instala `provision.sh` en `/usr/local/bin`). |
| `migrate-from-supabase.sh` | Copia los datos de Supabase y las fotos a R2, y reescribe las URLs. Repetible (vuelve a copiar todo). |
| `provision-backups.sh` | Backup semanal a R2 (`oneofone-backup` a mano). |
| `render-proxy.mjs` | Reenvío de Render a la VPS para las apps ya instaladas (corte). |

### Alta (una vez)

1. **Cloudflare:** registro A `api` → `2.31.106.97` con proxy (nube naranja).
2. **R2:** bucket `oneofone-media`, dominio público `img.buschfranco.com` y un
   token con escritura en ese bucket. Las claves van en
   `/root/.r2-oneofone.env` (`R2_ACCESS_KEY_ID=…`, `R2_SECRET_ACCESS_KEY=…`).
3. **Clave de deploy:** `ssh-keygen -t ed25519 -N "" -C github-1of1 -f oneofone_deploy`.
   En GitHub → Settings → Secrets → Actions: `VPS_HOST` = `2.31.106.97`,
   `VPS_SSH_KEY` = contenido de `oneofone_deploy` (privada) y
   `VPS_KNOWN_HOSTS` = salida de `ssh-keyscan 2.31.106.97`.
4. **En la VPS:** copiar `backend/deploy/vps/` (p. ej. a `/root/oneofone-vps/`) y
   correr `bash provision.sh "<contenido de oneofone_deploy.pub>"` y
   `bash provision-db.sh`.
5. **Variables** en `/etc/oneofone/oneofone.env` (además de las que escribió
   `provision-db.sh`): `JWT_SECRET` (**el mismo de Render**, así las sesiones
   abiertas siguen valiendo), `JWT_EXPIRES_IN=30d`, `CORS_ORIGIN=*`,
   `GOOGLE_CLIENT_IDS`, `MAPS_API_KEY`, `NEWSDATA_API_KEY`, `R2_ACCOUNT_ID`,
   `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET=oneofone-media`,
   `R2_PUBLIC_URL=https://img.buschfranco.com`.
6. **Primera publicación:** GitHub → Actions → "Backend VPS" → Run workflow.
   Crea las tablas. Probar `curl https://api.buschfranco.com/health`.
7. `bash migrate-from-supabase.sh` (pide la contraseña de la base de Supabase) y
   `bash provision-backups.sh`.

### Corte (cuando la VPS esté probada)

1. Volver a correr `migrate-from-supabase.sh` para traer lo último.
2. `render.yaml`: `startCommand: node deploy/vps/render-proxy.mjs` y env
   `UPSTREAM_URL=https://api.buschfranco.com` (sin build de Nest). Desde ahí
   las apps instaladas siguen andando por el reenvío, y la base es una sola.
3. App: `API_BASE_URL=https://api.buschfranco.com` en `dart_defines.json` y
   nueva versión. Actualizar los textos legales (app y web) y `app/CLAUDE.md`.
4. Cuando casi nadie use versiones viejas: apagar Render, el ping keep-alive y
   el proyecto de Supabase.

### Comandos útiles (como root)

`systemctl status oneofone`, `journalctl -u oneofone -n 100`,
`ls -lt /srv/oneofone/releases`. Volver a una versión anterior:
`ln -sfn /srv/oneofone/releases/<commit> /srv/oneofone/current && systemctl restart oneofone`
(ojo: las migraciones no se deshacen solas).

## Pendiente

- Hardening producción: rate limiting y helmet.
- **No hay push a los clientes** (ni FCM ni websockets): todo lo que un usuario
  tiene que saber de otro se resuelve con polling desde la app.
