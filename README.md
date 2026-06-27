# TriplesApp

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
| **Perfiles** | `Name`, `Handle`, `Phone`, `City`, `Lat`, `Lng`, `Avatar`, `Position`, `Height`, `UserEmail` · **Clan**: `Clan`, `AvatarColor`, `ClanTextColor`, `ClanFont` · **Progreso visible para amigos**: `EquippedTitle`, `Level` · **Presencia/privacidad**: `Playing`, `PlayingCourtId`, `PlayingSince`, `ShareStatus`, `ShareCourt`, `ShareTime` |
| **Canchas** | `Name`, `Area`, `Img`, `Type`, `Free`, `Lit`, `Hoops`, `Surface`, `Status`, `Hours`, `Badges`, `Desc`, `Lat`, `Lng`, `Aprobacion` · **Autor**: `CreatedBy` (handle), `CreatedByEmail` (clave para resolver en vivo), `CreatedByClan` (snapshot) |
| **Reseñas** | `CourtId`, `UserEmail`, `Rating`, `Comment`, `CreatedAt` |
| **Partidos** (pickups) | `CourtId`, `CreatedBy`, `DateTime`, `MaxPlayers`, `Vibe`, `Notes` |
| **Amistades** | `OwnerEmail`, `FriendHandle`, `FriendName`, `FriendEmail`, `CreatedAt` |

> El **estado "Jugando", el título equipado y el nivel** se guardan en el perfil
> justamente para que los amigos puedan verlos. La presencia de otros se
> refresca al abrir Amigos / un detalle.

### En el dispositivo (local, `shared_preferences`)

Lo personal del dispositivo o derivado del juego. **No** viaja con la cuenta:
si cambiás de teléfono, esto no se transfiere.

| Clave | Qué guarda |
|-------|------------|
| `session_email`, `session_profile` | Cache de sesión (para reabrir sin red) |
| `onboarding_seen` | Si ya viste el onboarding |
| `favorite_courts` | IDs de canchas favoritas |
| `play_points`, `play_total_count` | Puntos acumulados y partidos jugados |
| `play_totals_by_court` | Tiempo jugado por cancha |
| `play_log` | Historial de partidos (cancha, duración, resultado, fecha) |
| `play_streak`, `play_streak_history` | Racha actual e historial de rachas |
| `play_active_session`, `play_pending_result` | Partido en curso / pendiente de resultado |
| `play_background_enabled` | Preferencia de detección en segundo plano |

> Los **logros, títulos y nivel se calculan localmente** a partir de estas
> estadísticas. Solo el **nivel** y el **título equipado** se copian a Notion
> (denormalizados) para mostrarlos a los amigos.

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

> Importante: usar una ruta **sin acentos ni espacios** (ej. `F:\dev\TriplesApp`).
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

---

## En construcción

Secciones maquetadas pero todavía sin backend: **Check-in**, **Reservar cancha**,
el **chat de Crew** y el **Rating** del perfil (aparecen marcadas dentro de la
app).
