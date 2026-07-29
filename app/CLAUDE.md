# CLAUDE.md — Guía de trabajo para la app 1of1

Instrucciones para modificar o extender **1of1** (app Flutter de básquet: buscador
de canchas + detección/registro de partidos + perfil/logros). Leé esto **antes**
de tocar código. Está pensado para que cualquier cambio salga sin romper features
existentes.

> **Idioma:** el código, los comentarios y los textos de UI están en **español**.
> Mantené ese estilo (comentarios que explican el *porqué*, no el *qué*).

---

## 0. Ubicación y arranque

- Monorepo: la raíz git es `D:\dev\1of1`. **Todo el código de la app vive
  en `app/`** (este directorio). `backend/` es el gateway NestJS que la app
  consume (la app nunca habla con la base directamente: ver §2).
- Entorno de desarrollo: **Windows + PowerShell**. Hay un shell Bash (Git Bash)
  disponible para scripts POSIX.

### Comandos esenciales (siempre desde `app/`)

```bash
flutter pub get                                             # dependencias
flutter run   --dart-define-from-file=dart_defines.json     # correr en device
flutter build apk --release --dart-define-from-file=dart_defines.json
flutter analyze lib                                         # linter (dejar en 0 issues nuevos)
dart run build_runner build --delete-conflicting-outputs   # regenerar freezed/json (ver §4)
```

- **Secretos:** `dart_defines.json` (`MAPS_API_KEY` + `API_BASE_URL`) **no se
  commitea** (`.gitignore`). Ver `lib/config.template.dart` para el formato.
  Por defecto `API_BASE_URL` apunta al backend de producción (Render), así que
  **no hace falta levantar nada local** para correr la app. Si querés trabajar
  contra un backend local: `cd backend && npm run start:dev` y apuntá
  `API_BASE_URL` a la IP LAN de esa PC.
- **Instalar en el device** (adb no está en PATH; usar ruta completa):

  ```bash
  "C:\Android\platform-tools\adb.exe" install -r build/app/outputs/flutter-apk/app-release.apk
  ```

  Si da `INSTALL_FAILED_UPDATE_INCOMPATIBLE` (firma distinta), desinstalá primero:
  `adb uninstall com.buschfranco.oneofone` (se pierden datos locales; las stats se
  vuelven a sembrar desde el perfil del backend al loguear).

### Reglas de commits / push

- Rama principal: `main`. Commiteá/pusheá **solo cuando el usuario lo pida**.
- El remoto muestra un aviso de "repository moved" a
  `https://github.com/BuschFranco/1of1.git`; el push funciona igual por redirección.

---

## 1. Arquitectura en 30 segundos

```
Postgres (Supabase) ◀─Prisma─▶ backend/ (NestJS, JWT) ◀─HTTP─▶ ApiClient ◀── Providers ◀── UI
                                                      ▲
                                            SyncCoordinator (pegamento)
```

- **Estado:** `provider` + `ChangeNotifier`. Todos los providers se registran en
  el `MultiProvider` de [`lib/main.dart`](lib/main.dart).
- **Modelos:** `freezed` + `json_serializable` (solo `Profile`; el resto son
  clases planas). Ver §4.
- **Persistencia local:** `SharedPreferences`, con claves **namespaced por usuario**
  (`base::$userKey`, con `userKey = email.trim().toLowerCase()`) para aislar datos
  entre cuentas en el mismo device.
- **Caché en memoria (stale-while-revalidate):** `ApiCache`
  ([`lib/services/cache/api_cache.dart`](lib/services/cache/api_cache.dart)) evita
  recargar reseñas/publicaciones/rey/clan/puntos/listas cada vez que se reentra a
  una pantalla. Es en memoria (no persiste) y se limpia en el logout. Cómo usarlo,
  qué está cacheado y cuándo se invalida: [`docs/cache.md`](docs/cache.md). Si
  agregás una lectura que se repite al navegar, cacheala ahí en vez de pegar a la
  red cada vez.

### Providers / servicios clave (`lib/services/`)

| Archivo | Rol |
| --- | --- |
| `api/api_client.dart` | **Único** cliente HTTP del backend. JWT (memoria + prefs `session_jwt`) + métodos tipados por dominio. |
| `api/api_config.dart` | `API_BASE_URL` (const de compile-time) + clave del JWT en prefs. |
| `session.dart` | Login/signup/Google (vía `/auth`), perfil, batch (`stageStats` + `flush` → `PATCH /me`), presencia. |
| `courts_provider.dart` | Lista de canchas (`GET /courts`), propuesta, moderación (`/courts/mine`), delete admin. |
| `profiles_provider.dart` | Perfiles públicos (amigos, presencia) — `GET /profiles`. |
| `court_rating_service.dart` | Reseñas: rating con cache + `listReviews/createReview/deleteReview`. |
| `favorites_provider.dart` | Favoritos (local). |
| `friends_service.dart` | Amistades (`/friends`) y búsqueda por handle (`/profiles/by-handle`). |
| `pickups_provider.dart` | Pickups (`/pickups` CRUD + join por código + chats). |
| `play_session_service.dart` | **Núcleo**: detección de partido (GPS/dwell), cronómetro, puntos, logros, historial, notificaciones. |
| `session_alarms.dart` | Arranque/cierre automático del partido en background (AlarmManager, isolates). |
| `sync_coordinator.dart` | Cablea todo: presencia→API, batch, flush de partidos (`POST /matches`), geofences, callbacks. |
| `notifications_service.dart` | Notificaciones locales del sistema. |
| `app_permissions.dart` | Chequeo/pedido de permisos (ubicación, notif, alarmas exactas). |
| `geofence_service.dart` | Geofences del SO por cancha (vía rápida de detección con la app cerrada). |
| `health_service.dart` | Métricas del partido desde Health Connect (pulso, calorías, pasos, distancia). |
| `court_owner_cache.dart` | Clan que conquistó la cancha y rey de la cancha, con cache. |
| `blocked_provider.dart` | Usuarios bloqueados (local). |
| `report_service.dart` | Reporte de contenido/usuarios (abre el cliente de mail). |

### Widgets compartidos que conviene reusar (`lib/widgets/`)

| Archivo | Para qué |
| --- | --- |
| `busy_overlay.dart` | `runBusy()` + `BusySpinner`: feedback de escrituras sin botón propio (ver §3). |
| `pickup_schedule_picker.dart` | `pickPickupDateTime()`: fecha + horarios válidos de la cancha. Lo comparten crear pickup y reprogramarlo desde el chat. |
| `pressable_widget.dart` | Scale-down al presionar. Envolvé con esto, no con `GestureDetector` pelado. |
| `section_title.dart` | Etiqueta de sección (13px, sin halo). |
| `under_construction.dart` | `showUnderConstruction()` + badge, para features todavía no operativas. |

- **`SyncCoordinator`** se crea con `lazy: false` en `main.dart`: es donde se
  conectan los callbacks entre servicios. Si agregás un evento nuevo entre
  servicios (p.ej. `onAlgo`), **cableálo acá**, no dentro de la UI.
- La UI **no llama a `ApiClient` directamente**: siempre pasa por un provider.

---

## 2. Backend propio (la app no toca la base directamente)

La app consume la API REST de `backend/` (NestJS) con **JWT propio**; el backend
es quien habla con la base (**Supabase Postgres vía Prisma**). El schema lo
gobiernan las migraciones de Prisma, no código que corre al arrancar. Contratos
completos en `backend/README.md`.

> Queda `backend/src/notion/` de la etapa anterior: es **código muerto**, no está
> registrado en `app.module.ts`. No lo tomes como referencia.

### Cómo funciona la capa de datos

- `lib/services/api/api_client.dart` es el **único** cliente HTTP: métodos
  tipados por endpoint que devuelven JSON plano. Los modelos parsean con
  `fromApi(Map)` (o `fromJson` en `Profile`, cuyas claves coinciden con la
  entidad del backend) y serializan con `toApiJson()`.
- **JWT**: se emite en `/auth/*`, se guarda en memoria (campo **estático**, así
  los servicios instanciados sueltos comparten sesión) y persistido en prefs
  bajo la clave **global** `session_jwt` (no namespaced: el isolate de
  background no conoce el userKey). Expira a los 30 días; ante 401 en
  `GET /me`, `Session` cierra la sesión → pantalla de login.
- `ApiConfig.baseUrl` es **const de compile-time** (dart-define `API_BASE_URL`)
  por la misma razón que antes lo era el token de Notion: los **isolates de
  background** no comparten memoria. El isolate escribe presencia leyendo el
  JWT desde prefs (`_setNotionPresence` en `session_alarms.dart`); si el token
  falta/venció, deja `presence_dirty` y el isolate principal reconcilia.
- Sin `API_BASE_URL` la app degrada a modo offline (listas vacías, sin red).

### Hosting (producción)

El backend corre en **Render** (`https://oneofone-backend.onrender.com`, HTTPS),
con la base en **Supabase Postgres**. `dart_defines.json` apunta ahí. Ya no hay
cleartext ni IP LAN: se borró `network_security_config.xml` y su atributo en
`AndroidManifest.xml`. El free tier de Render duerme tras ~15 min sin tráfico
(cold start ~30-60s); mitigado con un ping keep-alive externo a `GET /health`
cada ~10 min (cron-job.org u otro). Variables de entorno del backend en el
dashboard de Render (no en un `.env` de producción). Deploy: push a `main` →
Render redeploya solo (lee `render.yaml` en la raíz del repo).

---

## 3. Cómo agregar o cambiar una funcionalidad

### Agregar un campo al perfil del usuario (patrón más común)

1. **Modelo (app)** — agregá el campo a `Profile` en [`lib/data/models.dart`](lib/data/models.dart)
   con `@Default(...)`. El `toJson/fromJson` generado ya viaja por la API.
2. **Backend** — sumá la columna a `backend/prisma/schema.prisma`, corré
   `npx prisma migrate dev --name <algo>` y mapeala en `profileWire` /
   `profilePatchToData` de `backend/src/domain/wire.ts` (ese archivo es el
   traductor entre la fila de Postgres y el JSON que consume la app).
3. **Codegen** — corré `dart run build_runner build --delete-conflicting-outputs`
   (regenera `models.freezed.dart` y `models.g.dart`). Ver §4.
4. **Escritura** — si el usuario lo edita, agregá un setter en `session.dart` que
   haga `copyWith` + marque `_dirty` (se sube en el próximo `flush()`, no pega a la
   red al toque salvo que sea presencia).

### Agregar una pantalla / pestaña

- Las pestañas están en el enum `AppTab` de [`lib/widgets/app_tab_bar.dart`](lib/widgets/app_tab_bar.dart)
  y se ruteán en [`lib/screens/main_shell.dart`](lib/screens/main_shell.dart) (switch
  sobre `_tab`). El **mapa (Home)** queda siempre montado (`Offstage`) para no
  recrear el platform view; el resto se anima con slide.
- El **swipe horizontal** entre pestañas (todas menos el mapa) está en `main_shell`
  (`_handleTabSwipe` + `_swipeTabs`). Si sumás una pestaña, decidí si entra en
  `_swipeTabs`.

### Escrituras: SIEMPRE con feedback de carga

Toda operación que cree, modifique o borre algo en el server tiene que mostrar que
está en curso. El backend duerme (cold start de 30-60 s), así que sin feedback el
usuario toca dos veces y se duplica la operación.

- Si la acción tiene un **botón propio**: spinner dentro del botón + `onTap: null`
  mientras vuela (patrón de `auth_screen`, `pickup_create_screen`).
- Si **no** tiene botón (menú contextual, fila de un sheet, algo que cierra la
  pantalla al terminar): `runBusy(context, action)` de
  [`lib/widgets/busy_overlay.dart`](lib/widgets/busy_overlay.dart) — overlay
  bloqueante que resuelve navigator y messenger **antes** de empezar, así se puede
  cerrar aunque el árbol se desmonte. `BusySpinner` es el spinner de la app.
  - **La navegación no va adentro de `runBusy`**: con el overlay arriba del stack,
    un `Navigator.pop` cerraría el overlay en vez de la pantalla. Que la acción
    devuelva si salió bien y navegá afuera (ver `_confirmDelete` del chat).
- Escrituras **locales** (SharedPreferences: favoritos, privacidad, cosméticos, el
  resultado del partido) son instantáneas y **no** llevan loader.
- El chat de pickups usa **mensaje optimista**: la burbuja aparece en gris con
  "Enviando" y se reemplaza por la real al confirmar (`ChatMessage.pending`).

### Notificaciones a OTROS usuarios: no hay push

**No existe canal server→cliente** (nada de FCM; `notifications_service.dart` es
100% local). Un aviso que dependa de otro usuario —invitación a un pickup, pickup
reprogramado— se resuelve por *polling* y dispara **cuando el otro abre la app**
(patrón de `PickupsProvider.pollRescheduled` + `SyncCoordinator`). No prometas
inmediatez en la UI; si algún día hace falta, es infra nueva (Firebase + tabla de
tokens + endpoint).

### Puntos, logros, niveles, detección de partido

- Todo vive en [`lib/services/play_session_service.dart`](lib/services/play_session_service.dart).
  Constantes clave arriba del archivo: `radiusMeters`, `dwellThreshold` (6 min para
  arrancar), `exitGrace` (6 min para cerrar), `minMatch` (13 min mínimo para contar),
  `multiplierCap`/`maxMultiplier` (multiplicador por duración), `pointsTimeCap` (2 h),
  `gpsJitterGrace` (tolerancia GPS). Cambiá números **acá** y no dupliques la lógica.
- Cambios en cómo se puntúa → `resolvePending()`. El multiplicador solo afecta los
  **puntos por tiempo**, no los bonus (resultado/racha/cancha nueva).
- Catálogos de logros/títulos/niveles: `lib/data/achievements.dart`,
  `lib/data/cosmetics.dart`.

### Rating por período y TEMPORADAS (importante)

- El ranking del perfil (StatBox "Rating" → `_showRanking` en `profile_screen.dart`)
  se puede filtrar por **Semana / Mes / Temporada / Total**. Getters de puntos por
  período en `play_session_service.dart`: `pointsThisWeek`, `pointsThisMonth`,
  `pointsSeason`.
- **Temporada = SEMESTRE de calendario**, NO una ventana móvil de 6 meses. Hay dos
  temporadas por año: **1 ene – 30 jun** y **1 jul – 31 dic**. La fuente única del
  corte es `PlaySessionService.seasonStart([now])` (devuelve el 1/1 o el 1/7 del año
  en curso); la usan tanto el getter `pointsSeason` como la UI del ranking. Si cambiás
  la definición de temporada, cambiala **solo ahí**.
- Los puntos por período de **amigos** salen del backend (`GET /matches/ranking`,
  que agrupa y suma por email server-side sobre la tabla `matches`). Se escribe con
  staging+flush offline-resiliente: `resolvePending()` encola en
  `pending_matches::$userKey` y `SyncCoordinator._flushPendingMatches()` sube el
  lote con `POST /matches` (los ítems con `ok:false` quedan en el buffer).
  Mis propios puntos del período salen del historial local (frescos), los de amigos de
  esa tabla — así no hay doble conteo. "Total" sigue usando el acumulado `Profile.points`.

### Background / notificaciones (leer antes de tocar)

- **Referencia completa del sistema de detección** (estados, capas de
  background, reconciliación, gotchas, cómo verificarlo en la calle):
  [`docs/deteccion-partidos.md`](docs/deteccion-partidos.md).
- Samsung y otros fabricantes **matan** el proceso y el foreground-service. El
  arranque/cierre automático del partido con la app cerrada se hace con
  **alarmas exactas del SO** (`android_alarm_manager_plus`) en
  [`lib/services/session_alarms.dart`](lib/services/session_alarms.dart), con
  callbacks `@pragma('vm:entry-point')` que corren en un **isolate de background**.
- Esos isolates **no comparten memoria** con el principal: se comunican por
  `SharedPreferences` + `IsolateNameServer` (puerto). Si cambiás el estado
  persistido del partido, actualizá **ambos** lados (servicio principal + alarmas).
- Las notificaciones que requieren acción del usuario abren la app; los botones que
  ejecutan lógica usan `showsUserInterface: true` (si no, en background el handler
  es no-op).
- **Constantes duplicadas a propósito**: `session_alarms.dart` tiene copias de
  algunas constantes (`_kRadiusMeters`, `_kMinMatchSeconds`, …) porque el isolate no
  puede leer las del servicio. Si cambiás una, **cambiá su gemela**.

### Permisos

- Política de pedidos (decisión de producto, jul 2026):
  - **Notificaciones**: diálogo directo del sistema UNA vez, en el primer
    arranque tras login/registro (`PermissionsModal.showOnceIfNeeded`). Si el
    usuario acepta, la fila ni aparece en el modal.
  - **Ubicación**: se pide EN CONTEXTO — al tocar "mi ubicación" en el mapa
    (`_goToMyLocation`) o desde el switch del modal (que encadena con
    "Permitir todo el tiempo" tras la divulgación destacada).
  - El **modal de permisos** ([`lib/widgets/permissions_modal.dart`](lib/widgets/permissions_modal.dart))
    en su flujo automático muestra SOLO lo que falta; abierto a mano desde el
    perfil muestra todo como panel de gestión.
  - Fuera de esos puntos, **no agregues auto-requests** en
    `initState`/`onMapCreated`/etc. La divulgación destacada de Google Play es
    obligatoria antes de pedir background ("Permitir siempre").

---

## 4. Codegen (freezed / json_serializable)

- Archivos generados: `lib/data/models.freezed.dart`, `lib/data/models.g.dart`.
  **No se editan a mano.**
- Después de tocar `@freezed` en `models.dart` **siempre** corré:
  `dart run build_runner build --delete-conflicting-outputs`.
- Si el build de codegen falla, suele ser por un `@Default` mal tipado o un import
  faltante. Los mapeos `fromApi`/`toApiJson` de los modelos planos (Court, Review,
  Friend, Pickup, CrewChat, CourtPost, PostComment, ChatMessage) son
  **manuales**: actualizalos vos (y su gemelo en `backend/src/domain/wire.ts`).

---

## 5. Rebranding (cambiar nombre / colores / identidad) sin romper nada

El branding está centralizado. Seguí este checklist en orden.

### 5.1 Colores y tipografía (bajo riesgo)

- **Todo el color y la tipografía** salen de [`lib/theme/app_theme.dart`](lib/theme/app_theme.dart):
  - `AppColors`. La paleta está **alineada con el sitio web**
    (`web/src/styles/tokens.css`): azules muy oscuros, no negro puro. La rampa de
    superficies, de más oscura a más clara, es
    `lilac` #080E18 → `bg` #0D141E → `bgElev` #141B26 → `card`/`panel` #1A202A.
    - `lilac` es el fondo de **Canchas y Crew**, más oscuro que `bg` a propósito.
    - `bgElev` es un paso **intermedio** entre `bg` y `card`: los modales se
      pintan con `bgElev` y sus secciones con `card`, así que igualarlos aplana
      los sheets y los diálogos.
    - Acento `accent` #FF6B1A (idéntico al del sitio) / `accentDark`; estados
      `open`/`busy`/`closed`; borde `line` #2B3444.
    - `sun`/`red`/`cream`/`olive`/`blush` son **aliases históricos** de `bg` y
      `charcoal`/`paper`/`glass` de `bgElev`: se conservan para no romper
      call-sites, pero ya no tienen color propio.
    - `lineWarm`, `inkVariant`, `inkMuted` existen pero **todavía no se usan**:
      son los tokens cálidos del sitio, para una pasada futura. La jerarquía
      secundaria de la app se sigue expresando con `AppColors.white(op)`.
  - **Efectos: [`lib/theme/app_fx.dart`](lib/theme/app_fx.dart)**. Para texto,
    `AppFx.accentGlow()` (halo naranja sobre texto de acento, como el titular del
    sitio), `AppFx.inkGlow()` (halo blanco muy tenue para titulares en tinta) y
    `AppFx.readableGlow()` (halo negro de legibilidad sobre foto). Para cajas,
    `AppFx.ambientShadow()` (sombra difusa de lo que flota sobre el mapa) además
    de las sombras duras históricas. Los tres helpers de `AppText` aceptan
    `shadows:`, así que el patrón es
    `AppText.display(..., shadows: AppFx.inkGlow())` — **no** uses `.copyWith`.
    Los titulares grandes van con halo; los `SectionTitle` (13px) no, porque a
    ese tamaño cualquier blur se lee como texto sucio.
  - `AppText`, con un helper por rol tipográfico. Las tres familias son **las
    mismas que la web** (`web/src/styles/tokens.css`) y están **bundleadas** en
    `assets/fonts/` (no se bajan en runtime):

    | Helper | Familia | Rol |
    | --- | --- | --- |
    | `AppText.display()` | Anton | titulares |
    | `AppText.archivo()` | Anybody | etiquetas y títulos de sección |
    | `AppText.grotesk()` | Archivo Narrow | texto corrido |

  - **Anybody y Archivo Narrow son fuentes variables**: el `fontWeight` solo no
    mueve el trazo, hace falta el eje `wght` vía `fontVariations`. Los helpers
    ya mandan las dos cosas; si escribís un `TextStyle` a mano con esas
    familias, acordate de la variación o vas a ver todo en peso 400.
  - **Anton viene en un solo peso** (400) y sin itálica: pasarle `weight` no
    cambia nada.
  - `GoogleFonts` sigue en uso **solo** para las fuentes cosméticas de clan que
    elige el usuario (`clanFontStyle` en `lib/data/cosmetics.dart`), no para la
    tipografía de la app.
- Cambiá los valores ahí y se propaga a toda la app. **No** hay colores hardcodeados
  sueltos que valga la pena migrar salvo tints puntuales (buscá `Color(0x...)` en
  `profile_screen.dart` si querés afinar).

### 5.2 Nombre visible ("1of1")

El string `"1of1"` aparece como marca en varios lugares. Al renombrar, cambiá
**todos**:

- `lib/main.dart` → `MaterialApp(title: ...)`.
- `lib/widgets/app_loader.dart` → texto del loader de arranque.
- Notificaciones y textos: `play_session_service.dart` (`notificationTitle`),
  `session_alarms.dart`, `sync_coordinator.dart`, `geofence_service.dart`,
  `permissions_modal.dart`. (Buscá `1of1` en `lib/`.)
- Nombre de la app en el launcher:
  - Android: `android:label` en `android/app/src/main/AndroidManifest.xml`.
  - iOS: `CFBundleDisplayName` / `CFBundleName` en `ios/Runner/Info.plist`.

> El nombre de la clase raíz `OneOfOneApp` es interno: renombrarla es cosmético y
> opcional (si lo hacés, ajustá el import/uso en `main.dart`).

### 5.3 Package / applicationId (alto riesgo — cambia identidad de instalación)

Hoy es `com.buschfranco.oneofone` (el histórico `com.example.triplesapp` se
migró para cumplir requisitos de las tiendas). Cambiarlo de nuevo es opcional y
**rompe la actualización in-place** (hay que desinstalar).
Si lo hacés, cambiá **de forma consistente**:

- `android/app/build.gradle` → `namespace` y `applicationId`.
- Carpeta del `MainActivity.kt`:
  `android/app/src/main/kotlin/com/buschfranco/oneofone/MainActivity.kt` (mover a
  la ruta del package nuevo y actualizar el `package` del archivo).
- iOS: `PRODUCT_BUNDLE_IDENTIFIER` en `ios/Runner.xcodeproj/project.pbxproj`.
- El `name:` de `pubspec.yaml` (`triplesapp`) afecta los imports
  `package:triplesapp/...`; si lo cambiás, hay que actualizar **todos** los imports.
  **Recomendación:** salvo necesidad real, no toques `pubspec name` ni el package —
  el costo/riesgo es alto y el usuario ya no ve ese identificador.

### 5.4 Íconos / assets

- Ícono de app: assets nativos en `android/app/src/main/res/mipmap-*` e
  `ios/Runner/Assets.xcassets`. El glyph in-app es `lib/widgets/bball_glyph.dart`.

---

## 6. Convenciones y gotchas

- **`flutter analyze lib` está en CERO issues.** Mantenelo así: cualquier cosa
  que aparezca es de tu cambio, no ruido preexistente.
- **google_maps_flutter_android está pineado a `2.19.7`** en `pubspec.yaml`: la
  2.19.8 migró a Pigeon/Kotlin y **rompe el build**. No lo actualices sin verificar.
- **Windows/adb:** `adb` no está en PATH; usá la ruta completa (§0).
- **Datos por usuario:** cualquier estado local nuevo debe ir namespaced por
  `userKey` (patrón `base::$userKey`) para no filtrarse entre cuentas. Al cerrar
  sesión, limpialo (`resetForLogout` / `clearForLogout`).
- **Batch, no spam:** las escrituras de stats van por `stageStats()` + `flush()`
  (cada ~2 min / al pausar / al cerrar), no una petición por evento. La presencia
  "Jugando" sí se escribe al instante (con reintento vía `_dirty`).
- **Fallback offline:** si el backend falla o no hay `API_BASE_URL`, la app
  degrada a listas vacías/mock y no debe crashear. Mantené ese comportamiento (try/catch que preserva el fallback).
- **Isolates de background:** `Date.now()`/red/estado compartido se manejan distinto
  ahí. Si algo "no anda con la app cerrada pero sí abierta", el problema está en el
  isolate (§3).

---

## 7. Checklist antes de dar por terminado un cambio

1. `flutter analyze lib` → 0 issues nuevos.
2. Si tocaste `@freezed` → corriste `build_runner` y compila.
3. Si agregaste un campo de la BD → está en `fromApi`/`toApiJson` (app), en
   `prisma/schema.prisma` con su migración corrida, y en `domain/wire.ts`.
4. Si tocaste estado del partido → revisaste el **servicio principal y**
   `session_alarms.dart` (isolate), y las constantes gemelas.
5. Estado local nuevo → namespaced por usuario y limpiado en logout.
6. `flutter build apk --release --dart-define-from-file=dart_defines.json` compila.
7. Commit/push **solo si el usuario lo pidió**.
