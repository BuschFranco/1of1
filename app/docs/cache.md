# Caché en memoria (stale-while-revalidate)

Sistema de caché de la app para dejar de recargar lo mismo cada vez que se
vuelve a una pantalla. Objetivo: al reentrar a una cancha (o reabrir un chat, la
lista de crew, amigos, ranking) mostrar todo **al instante** y refrescar en
segundo plano, gastando menos peticiones.

> **Alcance:** caché **en memoria, por sesión de app**. NO persiste a disco — se
> pierde al cerrar la app del todo. Es a propósito: resuelve la re-navegación sin
> sumar complejidad ni riesgo de datos viejos en arranque frío.

## El primitivo: `ApiCache`

[`lib/services/cache/api_cache.dart`](../lib/services/cache/api_cache.dart). Un
store estático `Map<String, {value, at}>` con TTL. API:

| Método | Qué hace |
| --- | --- |
| `peek<T>(key)` | Valor cacheado sin importar su edad (o `null`). |
| `isFresh(key, ttl)` | `true` si hay valor y no superó `ttl`. |
| `put(key, value)` | Guarda con timestamp `DateTime.now()`. |
| `invalidate(key)` | Borra una clave exacta. |
| `invalidatePrefix(p)` | Borra `p` y todas las `p::...`. |
| `clear()` | Vacía todo. **Se llama en el logout.** |

Los TTLs viven como constantes en `ApiCache` (`ttlReviews`, `ttlPosts`,
`ttlKing`, `ttlClanOwner`, `ttlMyPoints`, `ttlProfiles`, `ttlPickups`,
`ttlFriends`, `ttlRanking`). Tunealos ahí.

### Claves por dominio

`reviews::<courtId>`, `posts::<courtId>`, `king::<courtId>`,
`clanowner::<courtId>`, `mypoints::<courtId>`, `profiles`, `pickups`, `friends`,
`ranking::<period>`, `globalranking::<period>`, `chat::<pickupId>`.

Las claves **no** incluyen el `userKey`: el caché entero se limpia con `clear()`
en el logout (ver más abajo), así no se filtran datos entre cuentas.

## El patrón de uso (SWR)

Política por lectura:

- **Fresco (`isFresh` < TTL):** se sirve de caché, **cero red**. Es el gran
  ahorro al reentrar.
- **Viejo (> TTL) pero presente:** se pinta lo cacheado al instante y se refetcha
  en segundo plano; al volver se actualiza sin spinner.
- **Ausente:** spinner + fetch (primera apertura).

Molde original en la app: `Session.restore` + `_refreshProfileFromApi`.

### Dos formas de aplicarlo

**a) Widget con estado propio** (`initState` + `setState`). Se aplica lo cacheado
ANTES del primer build (sin `setState`, porque estamos dentro de `initState`) y se
refresca tras el `await`:

```dart
Future<void> _load() async {
  final cached = ApiCache.peek<Foo>(key);
  if (cached != null) _apply(cached);          // pinta al instante
  if (cached != null && ApiCache.isFresh(key, ttl)) return; // fresco: no toca red
  final fresh = await fetch();
  ApiCache.put(key, fresh);
  if (mounted) setState(() => _apply(fresh));  // setState SOLO después del await
}
```

Ejemplos: `_CourtKingCard`, `_CourtOwnerCard`, `_MyCourtStats` en
[`detail_screen.dart`](../lib/screens/detail_screen.dart).

**b) `FutureBuilder` con `initialData`.** La semilla del caché evita el spinner
mientras revalida; el `builder` solo muestra spinner si NO hay datos:

```dart
FutureBuilder<List<Foo>>(
  future: _future,
  initialData: ApiCache.peek<List<Foo>>(key),
  builder: (context, snap) {
    if (!snap.hasData && snap.connectionState == ConnectionState.waiting) {
      return spinner;
    }
    ...
  },
)
```

Ejemplos: `_ReviewsSection`, `_PostsSection` en `detail_screen.dart`.

## Qué está cacheado y dónde

| Dato | Clave | TTL | Dónde |
| --- | --- | --- | --- |
| Lista de reseñas | `reviews::<courtId>` | 2 min | `CourtRatingService.listReviews` + `_ReviewsSection` |
| Publicaciones | `posts::<courtId>` | 2 min | `_PostsSection` |
| Rey de la cancha | `king::<courtId>` | 5 min | `CourtOwnerCache.kingDataFor` (mapa + detalle) |
| Clan conquistador | `clanowner::<courtId>` | 5 min | `CourtOwnerCache.ownerDataFor` (mapa + detalle) |
| Mis puntos en la cancha | `mypoints::<courtId>` | 5 min | `_MyCourtStats` |
| Perfiles (presencia) | `profiles` | 90 s | `ProfilesProvider.load` (guarda TTL) |
| Pickups (crew) | `pickups` | 60 s | `PickupsProvider.loadForUser` (guarda TTL) |
| Amigos | `friends` | 60 s | `FriendsService.listFriends` |
| Ranking de amigos | `ranking::<period>` | 2 min | `_RankingSheet` en `profile_screen.dart` |
| Ranking global | `globalranking::<period>` | 2 min | `ranking_screen.dart` |
| Mensajes de chat | `chat::<pickupId>` | (semilla) | `PickupChatScreen` (últimos ~50; el polling incremental sigue igual) |

Notas:

- **Rey/clan unificados:** `CourtOwnerCache`
  ([`court_owner_cache.dart`](../lib/services/court_owner_cache.dart)) está
  respaldado por `ApiCache`, así una sola consulta por cancha sirve a las
  miniaturas del carrusel del mapa **y** al detalle. Guarda la respuesta completa
  (con puntos) y dedupea llamadas concurrentes.
- **Reseñas sin doble fetch:** `CourtRatingService.ratingFor` computa el promedio
  desde la misma lista cacheada que usa el detalle (antes se pedía dos veces).
- **Chat:** el TTL no aplica; se siembra la lista desde `chat::<pickupId>` para
  pintar al instante y el **polling incremental de 4 s** (con `sinceIso`) sigue
  igual — no hay regresión de tiempo real. Se guardan los últimos ~50 mensajes en
  cada poll con novedades y en `dispose`.
- **Pull-to-refresh** fuerza la recarga (`force: true`) saltando la guarda TTL
  (crew, etc.).

## Invalidación

El caché se auto-refresca por TTL, pero además se invalida al instante ante
acciones del usuario para que el cambio se vea sin esperar:

| Acción | Invalida |
| --- | --- |
| Crear/borrar reseña | `reviews::<courtId>` (+ rating agregado) — en `CourtRatingService.invalidate` |
| Crear/borrar/comentar publicación | `posts::<courtId>` — en `_PostsSection._refresh` |
| Resolver un partido | `king::<courtId>`, `clanowner::<courtId>`, `mypoints::<courtId>`, `ranking`, `globalranking` — en `PlaySessionService.resolvePending` |
| Agregar/quitar amigo | `friends`, `ranking` — en `FriendsService` |
| Crear pickup / unirse por código | recarga forzada de `pickups` |
| **Logout** | `ApiCache.clear()` — en `SyncCoordinator._onSessionChanged`, junto a los `clearForLogout()` |

## Cómo agregar una lectura nueva al caché

1. Elegí una clave namespaced (`dominio::id`) y un TTL (constante en `ApiCache`).
2. Aplicá el patrón (a) o (b) de arriba según el widget.
3. Si la acción del usuario cambia ese dato, agregá el `invalidate`/
   `invalidatePrefix` correspondiente en el punto de la mutación.
4. Si el dato es sensible por cuenta, confiá en `ApiCache.clear()` del logout (no
   metas el `userKey` en la clave).
