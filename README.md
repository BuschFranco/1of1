# 1of1 — Monorepo

Repo con tres subproyectos:

| Carpeta | Qué es | Stack |
| --- | --- | --- |
| [`app/`](app/) | App móvil 1of1 (canchas de básquet, detección de partidos, perfil) | Flutter / Dart |
| [`backend/`](backend/) | API REST que consume la app (JWT propio) | NestJS + Prisma |
| [`web/`](web/) | Sitio público de la app (landing + documentos legales) | Astro |

## App (`app/`)

Toda la documentación de setup, comandos y arquitectura está en
[`app/CLAUDE.md`](app/CLAUDE.md).

```bash
cd app
flutter pub get
flutter run --dart-define-from-file=dart_defines.json
```

> `app/dart_defines.json` (`MAPS_API_KEY` + `API_BASE_URL`) **no se commitea**
> (está en `.gitignore`). El formato está en
> [`app/lib/config.template.dart`](app/lib/config.template.dart). Sin
> `API_BASE_URL` la app arranca en modo offline (listas vacías, sin red).

Referencias útiles: [detección de partidos](app/docs/deteccion-partidos.md) (el
sistema más delicado de la app: GPS, isolates y alarmas del SO),
[caché](app/docs/cache.md), [sistema de ranking](docs/SISTEMA_RANKING.md).

## Backend (`backend/`)

NestJS + Prisma sobre **Supabase Postgres**, desplegado en **Render**
(`https://oneofone-backend.onrender.com`). Contratos de los endpoints en
[`backend/README.md`](backend/README.md).

```bash
cd backend
npm install
npm run start:dev
```

> Deploy automático: un push a `main` hace que Render redeploye (lee
> [`render.yaml`](render.yaml)). Las variables de entorno viven en el dashboard
> de Render, no en el repo. El free tier duerme tras ~15 min sin tráfico
> (cold start de 30-60 s), mitigado con un ping externo a `GET /health`.

## Web (`web/`)

Sitio estático con i18n español/inglés (`/` y `/en/`).

```bash
cd web
npm install
npm run dev      # http://localhost:4321
npm run build
```

> Las páginas `/privacidad` y `/terminos` replican los textos legales de la app
> ([`app/lib/data/legal_content.dart`](app/lib/data/legal_content.dart)). **Si
> cambiás uno hay que cambiar el otro**: son la misma política y tienen que
> coincidir.

## Pendientes / Roadmap

### Pickups públicos (UI lista, sin funcionalidad)

Marcado "EN CONSTRUCCIÓN" en la app y "Próximamente" en la web. Hoy es **solo
visual**: el toggle *"Pickup público"*
([`pickup_create_screen.dart`](app/lib/screens/pickup_create_screen.dart)) no
persiste nada, y la sección *"Partidas públicas"* del detalle de cancha
([`detail_screen.dart`](app/lib/screens/detail_screen.dart)) muestra una fila de
ejemplo. Falta:

- Campo `isPublic` en `Pickup` (app + entidad del backend + schema).
- Endpoint para listar pickups públicos por cancha
  (`GET /pickups/public?courtId=`).
- Unión abierta sin invitación, respetando `maxPlayers`.
- Reemplazar el mock por la lista real y quitar los badges de "EN CONSTRUCCIÓN"
  (app) y la mención de "Próximamente" (web, `community.pickups.soonBody`).

### Publicación en las tiendas

- **URLs legales públicas**: `kPrivacyPolicyUrl` / `kTermsUrl` en
  [`legal_content.dart`](app/lib/data/legal_content.dart) están vacías. Google
  Play exige una URL de política de privacidad en la ficha; las páginas del sitio
  (`/privacidad`, `/terminos`) ya sirven para eso una vez que el sitio esté
  publicado.
- **Declaraciones del Play Console**: formulario de permiso de ubicación en
  segundo plano (con video), aprobación de Health Connect, y el *Data Safety
  form* alineado con la política de privacidad.
- Los botones de tienda del sitio son placeholders con etiqueta "Próximamente"
  ([`DownloadCta.astro`](web/src/components/sections/DownloadCta.astro)): al
  publicar, pasarlos a `<a href>` y quitar el `aria-disabled`.

### Notificaciones entre usuarios

**No existe canal push server→cliente** (no hay FCM;
[`notifications_service.dart`](app/lib/services/notifications_service.dart) es
100% local). Los avisos que dependen de otro usuario —invitación a un pickup,
pickup reprogramado— se resuelven por *polling* y disparan **cuando el otro abre
la app**. Si algún día hace falta aviso inmediato, hay que sumar Firebase +
tabla de tokens + endpoint en el backend.

## Estructura

```
.
├── app/        # Flutter (lib/, android/, ios/, assets/, docs/, pubspec.yaml)
├── backend/    # NestJS + Prisma (src/, prisma/)
├── web/        # Astro (src/pages, src/components/sections, src/i18n)
├── docs/       # Documentación de producto (ranking, almacenamiento, Play Store)
├── render.yaml # Blueprint de deploy del backend
└── README.md   # Este archivo
```
