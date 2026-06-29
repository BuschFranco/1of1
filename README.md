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

## Estructura

```
.
├── app/        # Flutter (lib/, android/, ios/, test/, pubspec.yaml, …)
├── backend/    # Backend (TBD)
├── .vscode/    # Launch configs compartidas
└── README.md   # Este archivo
```
