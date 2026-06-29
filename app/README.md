# 1of1

App mobile (Flutter) para descubrir canchas de básquet en un mapa, ver
detalles, dejar reseñas, organizar pickups, registrar tus partidos y conectar
con otros jugadores.

> Estado: prototipo funcional con backend de datos sobre **Notion**.

---

## Funcionalidades

- **Mapa de canchas** con marcadores, búsqueda de barrios (Google Places),
  círculo del radio de detección y **carrusel** de tarjetas deslizable.
- **Listado** de canchas con orden por cercanía y filtros rápidos.
- **Detalle de cancha**: imagen (con placeholder si no hay), amenities,
  horarios, reseñas, tiempo que jugaste ahí y **"jugando ahora"**.
- **Agregar cancha** (ubicación en mapa + imagen por URL) → entra a
  **moderación** (Sin definir / Aprobado / Desaprobado). Solo las aprobadas se
  muestran. Guarda el email del proponente para resolver su handle/clan en vivo.
- **Reseñas** por cancha (rating + comentario).
- **Pickups**: organizar partidos (cancha, fecha, jugadores, notas).
- **Favoritos** (locales) — visibles en el perfil.
- **Perfil**:
  - **Insignia de clan**: hasta 4 caracteres, color de fondo y de letras (hex
    o paleta) y tipografía. Se usa como avatar.
  - **Detección automática de partidos** por GPS: si estás ≥7 min dentro de
    80 m de una cancha, pasás a estado **"Jugando"**; al salir, termina y te
    pregunta el resultado (Ganó / Perdió / Empató / Entrenamiento / Sin
    información). Opcional **en segundo plano**.
  - **Tiempo jugado** total y por cancha · **Partidos**, **Canchas únicas**.
  - **Historial** de partidos con resultado, fecha y duración.
  - **Racha** de victorias (con historial de rachas).
  - **Sistema de puntos** (tiempo + bonus por resultado / racha / cancha nueva)
    y **niveles numéricos infinitos**.
  - **Logros** y **Títulos** coleccionables (bloqueado gris / desbloqueado
    dorado); el título equipado y el nivel se ven en la lista de amigos.
  - **Privacidad** (⚙️): qué compartís mientras jugás (estado, cancha, tiempo)
    y si la detección corre en segundo plano.
- **Amigos**: buscar por handle y agregar (sin aceptación). Cada amigo muestra
  su avatar/clan, nivel, título y estado "Jugando".
- **Login / registro** con sesión persistente.

---

## Stack y arquitectura

- **Flutter** (Dart) — Android (mobile). iOS preparado (incluye modos de
  background) pero no compilado.
- **Estado** (`provider`): `Session`, `CourtsProvider`, `FavoritesProvider`,
  `ProfilesProvider`, `PlaySessionService`.
- **Base de datos**: **Notion** vía su API REST (`http`). Cada tabla es una
  database. La app degrada a datos mock locales si no hay token. Las columnas
  nuevas se crean solas al iniciar (`ensureProperties`) si la integración tiene
  permiso de *Update content*.
- **Mapas / ubicación**: `google_maps_flutter` + `geolocator` (incluye servicio
  en primer plano para la detección en background).
- **Persistencia local**: `shared_preferences`.
- **Hashing de contraseñas**: `crypto` (SHA-256). *Auth prototipo, no apta para
  producción.*

---

## Datos: qué se guarda y dónde

### En la base de datos (Notion)

Lo que tiene que ser compartido entre usuarios o sobrevivir a un cambio de
dispositivo.

| Base | Campos principales |
|------|--------------------|
| **Usuarios** | `Email`, `PasswordHash`, `ProfileId`, `CreatedAt` |
| **Perfiles** | `Name`, `Handle`, `Phone`, `City`, `Lat`, `Lng`, `Avatar`, `Position`, `Height`, `UserEmail` · **Clan**: `Clan`, `AvatarColor`, `ClanTextColor`, `ClanFont` · **Progreso (agregados + visible para amigos)**: `Games`, `Courts`, `Streak`, `Points`, `Level`, `EquippedTitle`, `UnlockedBadges` (IDs de logros desbloqueados), `PlaySeconds` (tiempo total), `PlayTimeByCourt` (tiempo por cancha, JSON) · **Presencia/privacidad**: `Playing`, `PlayingCourtId`, `PlayingSince`, `ShareStatus`, `ShareCourt`, `ShareTime` |
| **Canchas** | `Name`, `Area`, `Img`, `Type`, `Free`, `Lit`, `Hoops`, `Surface`, `Status`, `Hours`, `Badges`, `Desc`, `Lat`, `Lng`, `Aprobacion` · **Autor**: `CreatedBy` (handle), `CreatedByEmail` (clave para resolver en vivo), `CreatedByClan` (snapshot) |
| **Reseñas** | `CourtId`, `UserEmail`, `Rating`, `Comment`, `CreatedAt` |
| **Partidos** (pickups) | `CourtId`, `CreatedBy`, `DateTime`, `MaxPlayers`, `Vibe`, `Notes` |
| **Amistades** | `OwnerEmail`, `FriendHandle`, `FriendName`, `FriendEmail`, `CreatedAt` |

> El **estado "Jugando", el título equipado, el nivel y los logros/títulos
> desbloqueados** se guardan en el perfil justamente para que los amigos puedan
> verlos y para que no se pierdan al cambiar de dispositivo. La presencia de
> otros se refresca al abrir Amigos / un detalle.

### En el dispositivo (local, `shared_preferences`)

`shared_preferences` es la **fuente de verdad mientras usás la app**. Algunas
claves son **espejo de la BDD** (se suben por lotes — ver más abajo); otras son
**puramente locales** y **no** viajan con la cuenta: si cambiás de teléfono, esas
no se transfieren.

| Clave | Qué guarda | ¿Se sube? |
|-------|------------|-----------|
| `session_email`, `session_profile` | Cache de sesión (para reabrir sin red) | espejo |
| `onboarding_seen` | Si ya viste el onboarding | ❌ local |
| `favorite_courts` | IDs de canchas favoritas | ❌ local |
| `play_points`, `play_total_count` | Puntos acumulados y partidos jugados | ✅ batch |
| `play_totals_by_court` | Tiempo jugado por cancha | ✅ batch |
| `play_unlocked_badges` | Logros desbloqueados (IDs) | ✅ batch |
| `play_log` | Historial de partidos (cancha, duración, resultado, fecha) | ❌ local |
| `play_streak`, `play_streak_history` | Racha actual e historial de rachas | racha ✅ batch · historial ❌ local |
| `play_active_session`, `play_pending_result` | Partido en curso / pendiente de resultado | ❌ local |
| `play_background_enabled` | Preferencia de detección en segundo plano | ❌ local |

> Los **agregados** (`Games`, `Courts`, `Streak`, `Points`, `Level`), el
> **título equipado**, los **logros/títulos desbloqueados** (`UnlockedBadges`) y
> el **tiempo jugado** (total y por cancha) se copian a Notion (denormalizados)
> para mostrarlos a los amigos y no perderlos al cambiar de dispositivo. Los
> logros se **calculan** a partir de las stats, pero una vez desbloqueados quedan
> **registrados de forma permanente** (no se re-bloquean aunque se borre el
> historial). El **historial detallado de partidos** y los **favoritos** quedan
> siempre locales.

### Cómo se sincronizan los datos a Notion (por lotes / *batch*)

Para no pegarle a la API de Notion en cada cambio (tiene *rate limit* de
~3 req/s y sería un derroche), todos los datos del perfil se suben **por lotes**
en **una sola petición**, no dato por dato. La lógica vive en
[`PlaySessionService`](lib/services/play_session_service.dart) (dispara el batch)
y [`Session.flush`](lib/services/session.dart) (arma y envía la petición):

1. **Local es la fuente de verdad** mientras usás la app: todo cambio se
   escribe primero en `shared_preferences`.
2. Cada cambio del perfil (stats, tiempo, logros, **nivel**, **título**,
   **clan**, **privacidad**) actualiza el caché local y marca un flag *dirty* —
   **no** dispara una petición.
3. `flush()` sube **todo el perfil en una sola** petición
   (`updatePage` con `toNotionProperties()` — stats, tiempo, logros, nivel,
   título, clan y privacidad juntos) cuando:
   - pasan **2 minutos** (timer periódico), **o**
   - la app pasa a segundo plano / se cierra
     (`AppLifecycleState.paused/detached/hidden`, vía `WidgetsBindingObserver`),
     **o**
   - se cierra sesión (`logout`) o se destruye el service (`dispose`).
4. Si en el intervalo **no cambió nada** (`dirty == false`), no se hace ninguna
   petición.
5. **Reintento automático:** `flush()` solo limpia el flag `dirty` **si la
   petición tuvo éxito**. Si falla (sin red, error de Notion), `dirty` queda en
   `true` y el **próximo tick de 2 min lo reintenta** — así la info del usuario
   no queda desactualizada. (Login y signup quedan afuera de este reintento: son
   interactivos y el usuario ve el error en el momento.)
6. Al **iniciar sesión** los contadores locales se **siembran** desde Notion
   (`seedPoints/seedPlays/seedStreak/seedBadges/seedTotalsJson`): si la nube
   tiene valores más altos que el local (p. ej. tras reinstalar), se adoptan,
   para no perder progreso, bajar de nivel, re-bloquear logros ni perder tiempo
   jugado. El tiempo por cancha se *mergea* quedándose con el mayor por cancha.

> **Inmediato (fuera del batch):**
> - El **handle** se sube al instante porque requiere validación de unicidad en
>   el momento (no se puede diferir sin arriesgar duplicados).
> - La **presencia** ("Jugando") se sube al instante para que los amigos te vean
>   jugando *ahora*; pero si esa subida falla, se marca `dirty` y el batch la
>   **reintenta** cada 2 min con el resto del perfil.
>
> **Solo local (nunca se sube):** historial detallado de partidos, historial de
> rachas, sesión en curso / pendiente, favoritos y preferencias del dispositivo.

---

## Estructura del proyecto

```
lib/
├── main.dart                   # Arranque + bootstrap de schema de Notion
├── data/
│   ├── courts.dart             # Modelo Court + mock + mapeo Notion
│   ├── models.dart             # AppUser, Profile, Review, Pickup, Friend
│   └── achievements.dart       # Logros, títulos y niveles
├── notion/
│   └── notion_config.dart      # Token + IDs de las databases
├── services/
│   ├── notion_service.dart     # Cliente REST de Notion (+ ensureProperties)
│   ├── session.dart            # Auth + sesión + presencia/título/nivel
│   ├── courts_provider.dart    # Carga de canchas (Notion / fallback)
│   ├── profiles_provider.dart  # Cache de perfiles por email (presencia en vivo)
│   ├── favorites_provider.dart
│   ├── friends_service.dart
│   └── play_session_service.dart  # Detección de partidos, tiempo, puntos, racha
├── screens/                    # home, list, detail, auth, profile, …
├── widgets/                    # Componentes reutilizables (CourtImage, etc.)
└── theme/app_theme.dart        # Colores y tipografías
```

---

## Cómo correrlo

### Requisitos
- Flutter SDK
- Android SDK + un dispositivo Android (físico o emulador)
- Una API key de **Google Maps** y un **token de integración de Notion**

> Importante: usar una ruta **sin acentos ni espacios** (ej. `F:\dev\1of1`).
> Las herramientas nativas de Android en Windows fallan con caracteres no-ASCII.

### 1. Configurar secretos

Crear `dart_defines.json` en la raíz (está en `.gitignore`):

```json
{
  "MAPS_API_KEY": "tu_google_maps_key",
  "NOTION_TOKEN": "tu_notion_internal_integration_secret"
}
```

Los IDs de las databases de Notion tienen default en
[`lib/notion/notion_config.dart`](lib/notion/notion_config.dart) y se pueden
sobreescribir por `--dart-define` si hace falta.

> Para Notion: crear una *internal integration* en
> https://www.notion.so/my-integrations, darle capacidad de **Update content**
> (para que la app cree las columnas nuevas sola) y compartir la página con las
> databases con esa integración.

### 2. Instalar dependencias y correr

```bash
flutter pub get
flutter run --dart-define-from-file=dart_defines.json
```

> Tras cambios en permisos nativos (ubicación en background) conviene un rebuild
> completo, no hot reload.

---

## Notas de seguridad

- `dart_defines.json`, `.env` y `ios/Flutter/APIKeys.xcconfig` están en
  `.gitignore` — **nunca** se versionan.
- El login es prototipo (contraseñas hasheadas pero sin servidor). Para
  producción se migraría a un proveedor real (Firebase Auth / Supabase).
- La ubicación en segundo plano es **opcional** y la habilita el usuario; en
  Android requiere permiso "Permitir siempre".

### ⚠️ El token de Notion queda embebido en el cliente

`NOTION_TOKEN` se inyecta en *build-time* vía `--dart-define`
(`String.fromEnvironment` en
[`notion_config.dart`](lib/notion/notion_config.dart)) y termina **compilado
como texto plano dentro del APK** (`libapp.so`). **No está encriptado**: con el
`.apk` en la mano, cualquiera puede extraerlo (`strings`, `blutter`,
`reFlutter`) y obtener **acceso total a las 6 databases de Notion** desde la API,
sin pasar por la app.

> `--dart-define` / variables de entorno **solo** mantienen el secreto fuera del
> código fuente y de git — **no** fuera del binario distribuido. Es un
> malentendido común.

---

## Cambios necesarios para producción

Antes de publicar/distribuir, **estos cambios son obligatorios**:

1. **Mover Notion detrás de un backend propio.** El cliente no debe tener
   **ningún** secreto. Patrón:

   ```
   App (sin token)  →  Backend propio (guarda el token)  →  Notion API
   ```

   El backend (una Cloud Function / servidor mínimo) guarda el token, valida
   permisos, aplica *rate-limit* y nunca lo expone. La app le pega a *tu* API,
   no a Notion directamente.
2. **Regenerar el token de Notion** actual antes de cualquier release: se
   expuso durante el desarrollo (chats, builds locales).
3. **No distribuir** un APK *release* con el token adentro.
4. **Auth real:** migrar el login prototipo (SHA-256 sin servidor) a un
   proveedor (Firebase Auth / Supabase).
5. **(Opcional) Mover Google Maps / Places** detrás del backend o restringir la
   key por *package name* + SHA-1 y por API habilitada, para evitar abuso.

---

## En construcción

Secciones maquetadas pero todavía sin backend: **Check-in**, **Reservar cancha**,
el **chat de Crew** y el **Rating** del perfil (aparecen marcadas dentro de la
app).
