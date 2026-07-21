/// Caché en memoria (por sesión de app) con TTL y stale-while-revalidate.
///
/// Objetivo: dejar de recargar lo mismo cada vez que se vuelve a una pantalla.
/// No persiste a disco (se pierde al cerrar la app del todo) — es a propósito:
/// resuelve la re-navegación sin sumar complejidad ni riesgo de datos viejos en
/// arranque frío.
///
/// Política de uso por lectura (patrón SWR, ver `Session.restore` como molde):
/// ```dart
/// final cached = ApiCache.peek<List<Foo>>(key);
/// if (cached != null) setState(() => data = cached);   // pinta al instante
/// if (!ApiCache.isFresh(key, ttl)) {                    // viejo o ausente
///   final fresh = await fetch();                        // refresca en bg
///   ApiCache.put(key, fresh);
///   setState(() => data = fresh);
/// }
/// ```
///
/// Las claves se namespacean por dominio con `dominio::id`
/// (`reviews::<courtId>`, `posts::<courtId>`, etc.) para poder invalidar por
/// prefijo. NO incluye el userKey: el caché entero se limpia con [clear] en el
/// logout, así no se filtran datos entre cuentas.
class ApiCache {
  ApiCache._();

  static final Map<String, ({Object? value, DateTime at})> _store = {};

  /// TTLs por defecto (constantes tuneables). Lecturas que cambian seguido con
  /// TTL corto; agregados lentos (rey/clan/puntos) con TTL más largo.
  static const Duration ttlReviews = Duration(minutes: 2);
  static const Duration ttlPosts = Duration(minutes: 2);
  static const Duration ttlKing = Duration(minutes: 5);
  static const Duration ttlClanOwner = Duration(minutes: 5);
  static const Duration ttlMyPoints = Duration(minutes: 5);
  static const Duration ttlProfiles = Duration(seconds: 90);
  static const Duration ttlPickups = Duration(seconds: 60);
  static const Duration ttlFriends = Duration(seconds: 60);
  static const Duration ttlRanking = Duration(minutes: 2);

  /// Valor cacheado sin importar su edad (o null si nunca se guardó).
  static T? peek<T>(String key) => _store[key]?.value as T?;

  /// true si hay un valor guardado y no superó [ttl].
  static bool isFresh(String key, Duration ttl) {
    final e = _store[key];
    return e != null && DateTime.now().difference(e.at) < ttl;
  }

  /// true si hay algún valor guardado (fresco o viejo).
  static bool has(String key) => _store.containsKey(key);

  static void put(String key, Object? value) =>
      _store[key] = (value: value, at: DateTime.now());

  static void invalidate(String key) => _store.remove(key);

  /// Borra la clave exacta [prefix] y todas las `prefix::...`.
  static void invalidatePrefix(String prefix) =>
      _store.removeWhere((k, _) => k == prefix || k.startsWith('$prefix::'));

  /// Limpia todo el caché. Llamar en el logout.
  static void clear() => _store.clear();
}
