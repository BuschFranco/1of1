# 1of1 — app (Flutter)

App de básquet: encontrá canchas en el mapa, registrá tus partidos
automáticamente por GPS, seguí tus stats y competí por temporada con tu crew.

> **La documentación de trabajo vive en [`CLAUDE.md`](CLAUDE.md)**: arquitectura,
> comandos, convenciones y los gotchas que hay que conocer antes de tocar código.
> Este archivo es solo la presentación, y se mantiene corto a propósito: cuando la
> misma cosa está explicada en dos lugares, uno de los dos queda desactualizado.

## Arranque

```bash
flutter pub get
flutter run --dart-define-from-file=dart_defines.json
```

`dart_defines.json` (`MAPS_API_KEY` + `API_BASE_URL`) **no se commitea** — el
formato está en [`lib/config.template.dart`](lib/config.template.dart). Por
defecto apunta al backend de producción, así que no hace falta levantar nada
local.

## Qué hace

- **Mapa de canchas** con estado, rating, reseñas y publicaciones. Las canchas las
  propone la comunidad (pasan por moderación) y quedan firmadas con el clan y el
  handle de quien las descubrió.
- **Detección automática de partidos**: 6 min dentro de un radio de 110 m arrancan
  el registro, y funciona con la app cerrada (geofences + alarmas exactas del SO +
  un radar de respaldo). Es el sistema más delicado de la app:
  [`docs/deteccion-partidos.md`](docs/deteccion-partidos.md).
- **Puntos, niveles, logros y títulos**, con ranking por semana / mes / temporada /
  total. La temporada es un semestre de calendario:
  [`../docs/SISTEMA_RANKING.md`](../docs/SISTEMA_RANKING.md).
- **Salud** (opcional): pulso, calorías, pasos y distancia de cada partido vía
  Health Connect. Esos datos **nunca salen del dispositivo**.
- **Crew y pickups**: armá un partido en una cancha, invitá por código, coordinen
  en el chat. El creador puede reprogramarlo.

## Backend

La app no habla con la base directamente: consume la API REST de
[`../backend/`](../backend/) (NestJS + Prisma sobre Supabase Postgres) con JWT
propio. Contratos en [`../backend/README.md`](../backend/README.md).

## Documentación

| Archivo | Qué cubre |
| --- | --- |
| [`CLAUDE.md`](CLAUDE.md) | **Empezá por acá.** Arquitectura, convenciones, rebranding, checklist. |
| [`docs/deteccion-partidos.md`](docs/deteccion-partidos.md) | Detección de partidos: estados, capas de background, cómo verificarla en la calle. |
| [`docs/cache.md`](docs/cache.md) | Caché en memoria: qué está cacheado, TTLs, cuándo se invalida. |
| [`docs/google-signin-sha.md`](docs/google-signin-sha.md) | Huellas SHA-1 para Google Sign-In. |
| [`../docs/SISTEMA_RANKING.md`](../docs/SISTEMA_RANKING.md) | Fórmula de puntos, niveles y temporadas. |

## Build de release

```bash
flutter build apk --release --dart-define-from-file=dart_defines.json
```

Se firma con la keystore de upload (`android/key.properties` +
`upload-keystore.jks`, ninguno commiteado). Lo que falta para publicar en las
tiendas está en el roadmap del [README de la raíz](../README.md).
