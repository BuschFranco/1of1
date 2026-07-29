# 1of1 — Monorepo

Repo con dos subproyectos:

| Carpeta | Qué es | Stack |
| --- | --- | --- |
| [`app/`](app/) | App móvil 1of1 (buscador de canchas de básquet) | Flutter / Dart |
| [`backend/`](backend/) | Backend de la app (en construcción) | TBD |

## App (`app/`)

La app Flutter. Toda la documentación de setup, comandos y arquitectura está en
[`app/README.md`](app/README.md).

```bash
cd app
flutter pub get
flutter run --dart-define-from-file=dart_defines.json
```

> El archivo `app/dart_defines.json` (token de Notion + API key de Maps) **no se
> commitea** (está en `.gitignore`). Pedíselo a alguien del equipo o configuralo
> a mano.

## Backend (`backend/`)

Todavía no implementado. Ver [`backend/README.md`](backend/README.md).

## Pendientes / Roadmap

Features con UI ya presente pero **todavía no funcionales** (marcadas
"EN CONSTRUCCIÓN" en la app):

- **Pickups públicos.** Al crear un pickup hay un toggle *"Pickup público"*
  ([`pickup_create_screen.dart`](app/lib/screens/pickup_create_screen.dart)) y en
  el detalle de cada cancha una sección *"Partidas públicas"*
  ([`detail_screen.dart`](app/lib/screens/detail_screen.dart)). Hoy son **solo
  visuales**. Falta:
  - Modelo/backend: campo `isPublic` en `Pickup` (app + `entities.ts` + schema
    del backend) y endpoint para listar pickups públicos por cancha
    (`GET /courts/:id/pickups` o `GET /pickups/public?courtId=`).
  - Unión abierta sin invitación (respetar `maxPlayers`).
  - Reemplazar la fila de ejemplo mock del detalle por la lista real y quitar
    los badges "EN CONSTRUCCIÓN".

## Estructura

```
.
├── app/        # Flutter (lib/, android/, ios/, test/, pubspec.yaml, …)
├── backend/    # Backend (TBD)
├── .vscode/    # Launch configs compartidas
└── README.md   # Este archivo
```
