# CLAUDE.md — Guía de trabajo para la app 1of1

Instrucciones para modificar o extender **1of1** (app Flutter de básquet: buscador
de canchas + detección/registro de partidos + perfil/logros). Leé esto **antes**
de tocar código. Está pensado para que cualquier cambio salga sin romper features
existentes.

> **Idioma:** el código, los comentarios y los textos de UI están en **español**.
> Mantené ese estilo (comentarios que explican el *porqué*, no el *qué*).

---

## 0. Ubicación y arranque

- Monorepo: la raíz git es `C:\ProyectosF\1of1`. **Todo el código de la app vive
  en `app/`** (este directorio). `backend/` está sin implementar (TBD).
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

- **Secretos:** `dart_defines.json` (token de Notion + `MAPS_API_KEY`) **no se
  commitea** (`.gitignore`). Ver `lib/config.template.dart` para el formato.
  **Nunca** hardcodees el token ni lo imprimas en logs.
- **Instalar en el device** (adb no está en PATH; usar ruta completa):

  ```bash
  "C:\Users\yochi\AppData\Local\Android\Sdk\platform-tools\adb.exe" install -r build/app/outputs/flutter-apk/app-release.apk
  ```

  Si da `INSTALL_FAILED_UPDATE_INCOMPATIBLE` (firma distinta), desinstalá primero:
  `adb uninstall com.example.triplesapp` (se pierden datos locales; las stats se
  recuperan de Notion al loguear).

### Reglas de commits / push

- Rama principal: `main`. Commiteá/pusheá **solo cuando el usuario lo pida**.
- El remoto muestra un aviso de "repository moved" a
  `https://github.com/BuschFranco/1of1.git`; el push funciona igual por redirección.

---

## 1. Arquitectura en 30 segundos

```
Notion (BD)  ◀──HTTP──▶  NotionService  ◀──  Providers (estado, ChangeNotifier)  ◀──  UI (screens/widgets)
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

### Providers / servicios clave (`lib/services/`)

| Archivo | Rol |
| --- | --- |
| `notion_service.dart` | **Único** cliente HTTP de la BD. Query/create/update + builders/parsers de propiedades. |
| `session.dart` | Login/signup, perfil del usuario, batch (`stageStats` + `flush`), presencia. |
| `courts_provider.dart` | Lista de canchas (Notion → fallback mock `kCourts`). |
| `profiles_provider.dart` | Perfiles públicos (amigos, presencia). |
| `favorites_provider.dart` | Favoritos (local). |
| `friends_service.dart` | Amistades. |
| `play_session_service.dart` | **Núcleo**: detección de partido (GPS/dwell), cronómetro, puntos, logros, historial, notificaciones. |
| `session_alarms.dart` | Arranque/cierre automático del partido en background (AlarmManager, isolates). |
| `sync_coordinator.dart` | Cablea todo: presencia→Notion, batch, geofences, notificaciones, callbacks. |
| `notifications_service.dart` | Notificaciones locales del sistema. |
| `app_permissions.dart` | Chequeo/pedido de permisos (ubicación, notif, alarmas exactas). |

- **`SyncCoordinator`** se crea con `lazy: false` en `main.dart`: es donde se
  conectan los callbacks entre servicios. Si agregás un evento nuevo entre
  servicios (p.ej. `onAlgo`), **cableálo acá**, no dentro de la UI.
- La UI **no llama a `NotionService` directamente**: siempre pasa por un provider.

---

## 2. Base de datos (Notion) — cómo funciona y cómo cambiarla

Hoy la "BD" es **Notion** (6 databases) vía su API REST. El acceso está
**centralizado**, lo que permite cambiar de base o de backend sin tocar la UI.

### Configuración — cambiar de una base a otra

Los IDs de las databases viven en [`lib/notion/notion_config.dart`](lib/notion/notion_config.dart).
No son secretos: tienen default embebido y se pueden sobrescribir por
`--dart-define` sin recompilar el código:

```bash
flutter run --dart-define-from-file=dart_defines.json \
  --dart-define=NOTION_DB_PROFILES=<nuevo_id> \
  --dart-define=NOTION_DB_COURTS=<nuevo_id>
```

Para apuntar a **otro workspace/copia de Notion** (staging, otra cuenta):
1. Cambiá los defaults en `notion_config.dart` **o** pasá los `--dart-define`.
2. Cambiá `NOTION_TOKEN` en `dart_defines.json` por el de la nueva integración.
3. Compartí las 6 databases con esa integración en Notion.

`NotionConfig.isConfigured` es `false` si no hay token → la app **degrada a datos
mock** (`kCourts`) y no intenta red. Útil para demos offline.

### Schema auto-gestionado

`_ensureNotionSchema()` en [`lib/main.dart`](lib/main.dart) crea (idempotente) las
columnas que usan las features nuevas al arrancar. **Si agregás un campo nuevo a
Notion, sumalo a ese mapa** (`nombre: 'tipo'`) para que se cree solo en cualquier
workspace. Tipos soportados por los helpers: `title`, `rich_text`, `number`,
`checkbox`, `select`, `multi_select`, `url`, `phone_number`, `date`.

### Cambiar de backend (Notion → REST propio / Supabase / Firebase)

El diseño ya está preparado para esto. Regla de oro: **nada fuera de la capa de
datos sabe que existe Notion**.

1. Definí una **interfaz** con las operaciones que usan los providers
   (`queryDatabase`, `createPage`, `updatePage`, `archivePage`, `retrievePage`).
2. Implementá esa interfaz contra el backend nuevo (`SupabaseDataService`, etc.),
   respetando la forma de dato que esperan los `fromNotion`/`toNotionProperties`
   de `models.dart` **o** adaptá también esos mapeos.
3. Inyectá la nueva implementación en los providers (todos aceptan
   `NotionService?` por constructor: `CourtsProvider({NotionService? notion})`,
   `Session({NotionService? notion})`, …). Cambiá el `create:` en `main.dart`.
4. Puntos de contacto a revisar (los únicos que referencian Notion):
   `notion_service.dart`, `notion_config.dart`, los `fromNotion/toNotionProperties`
   en `data/models.dart` y `data/courts.dart`, y el `_ensureNotionSchema` de
   `main.dart`. **También** los isolates de background
   (`session_alarms.dart`) usan `NotionService` directo para escribir presencia:
   actualizalos ahí.

> Cuidado: `NotionConfig.token` es `const` de compile-time para poder usarse desde
> los **isolates de background** (que no comparten memoria con el isolate
> principal). Cualquier reemplazo de backend debe seguir siendo accesible desde un
> isolate sin estado compartido.

---

## 3. Cómo agregar o cambiar una funcionalidad

### Agregar un campo al perfil del usuario (patrón más común)

1. **Modelo** — agregá el campo a `Profile` en [`lib/data/models.dart`](lib/data/models.dart)
   con `@Default(...)`.
2. **Mapeo Notion** — mapealo en `fromNotion` (lectura) y `toNotionProperties`
   (escritura) del mismo archivo.
3. **Schema** — sumá `'MiCampo': 'tipo'` al mapa de `_ensureNotionSchema` en
   `main.dart`.
4. **Codegen** — corré `dart run build_runner build --delete-conflicting-outputs`
   (regenera `models.freezed.dart` y `models.g.dart`). Ver §4.
5. **Escritura** — si el usuario lo edita, agregá un setter en `session.dart` que
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
- Los puntos por período de **amigos** salen de la DB Notion **"Partidos"**
  (`NotionConfig.dbMatches`), una fila por partido resuelto (`Email`, `Points`,
  `EndedAt`, `CourtId`, `CourtName`, `Result`, `Seconds`). Se escribe con
  staging+flush offline-resiliente: `resolvePending()` encola en
  `pending_matches::$userKey` y `SyncCoordinator._flushPendingMatches()` sube en lote.
  Mis propios puntos del período salen del historial local (frescos), los de amigos de
  esa DB — así no hay doble conteo. "Total" sigue usando el acumulado `Profile.points`.

### Background / notificaciones (leer antes de tocar)

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
  faltante. Los mapeos `fromNotion`/`toNotionProperties` son **manuales** (no los
  genera json_serializable): actualizalos vos.

---

## 5. Rebranding (cambiar nombre / colores / identidad) sin romper nada

El branding está centralizado. Seguí este checklist en orden.

### 5.1 Colores y tipografía (bajo riesgo)

- **Todo el color y la tipografía** salen de [`lib/theme/app_theme.dart`](lib/theme/app_theme.dart):
  - `AppColors` (acento `accent`/`accentDark`, fondos `bg`/`bgElev`, estados
    `open`/`busy`/`closed`).
  - `AppText.archivo` / `AppText.grotesk` (fuentes de Google Fonts).
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

Hoy es `com.example.triplesapp` (histórico; el proyecto se llamaba TriplesApp).
Cambiarlo es opcional y **rompe la actualización in-place** (hay que desinstalar).
Si lo hacés, cambiá **de forma consistente**:

- `android/app/build.gradle` → `namespace` y `applicationId`.
- Carpeta del `MainActivity.kt`:
  `android/app/src/main/kotlin/com/example/triplesapp/MainActivity.kt` (mover a la
  ruta del package nuevo y actualizar el `package` del archivo).
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

- **`flutter analyze lib` debe quedar sin issues nuevos.** Hay un deprecado
  preexistente conocido (`setMapStyle`); no sumes otros.
- **google_maps_flutter_android está pineado a `2.19.7`** en `pubspec.yaml`: la
  2.19.8 migró a Pigeon/Kotlin y **rompe el build**. No lo actualices sin verificar.
- **Windows/adb:** `adb` no está en PATH; usá la ruta completa (§0).
- **Datos por usuario:** cualquier estado local nuevo debe ir namespaced por
  `userKey` (patrón `base::$userKey`) para no filtrarse entre cuentas. Al cerrar
  sesión, limpialo (`resetForLogout` / `clearForLogout`).
- **Batch, no spam:** las escrituras de stats van por `stageStats()` + `flush()`
  (cada ~2 min / al pausar / al cerrar), no una petición por evento. La presencia
  "Jugando" sí se escribe al instante (con reintento vía `_dirty`).
- **Fallback offline:** si Notion falla o no hay token, la app degrada a mock y no
  debe crashear. Mantené ese comportamiento (try/catch que preserva el fallback).
- **Isolates de background:** `Date.now()`/red/estado compartido se manejan distinto
  ahí. Si algo "no anda con la app cerrada pero sí abierta", el problema está en el
  isolate (§3).

---

## 7. Checklist antes de dar por terminado un cambio

1. `flutter analyze lib` → 0 issues nuevos.
2. Si tocaste `@freezed` → corriste `build_runner` y compila.
3. Si agregaste un campo de Notion → está en `fromNotion`, `toNotionProperties` y
   `_ensureNotionSchema`.
4. Si tocaste estado del partido → revisaste el **servicio principal y**
   `session_alarms.dart` (isolate), y las constantes gemelas.
5. Estado local nuevo → namespaced por usuario y limpiado en logout.
6. `flutter build apk --release --dart-define-from-file=dart_defines.json` compila.
7. Commit/push **solo si el usuario lo pidió**.
