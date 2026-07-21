import '../data/models.dart';
import 'api/api_client.dart';
import 'cache/api_cache.dart';

/// Maneja amistades y búsqueda de perfiles por handle (vía backend).
class FriendsService {
  FriendsService({ApiClient? api}) : _api = api ?? ApiClient();
  final ApiClient _api;

  bool get isConfigured => _api.isConfigured && _api.hasToken;

  /// Normaliza un handle: minúsculas y con '@' adelante.
  static String normalizeHandle(String raw) {
    var h = raw.trim().toLowerCase();
    if (h.isEmpty) return h;
    if (!h.startsWith('@')) h = '@$h';
    return h;
  }

  /// Busca un perfil por handle exacto. Devuelve null si no existe.
  Future<Profile?> searchByHandle(String handleRaw) async {
    final handle = normalizeHandle(handleRaw);
    if (handle.isEmpty) return null;
    try {
      final json = await _api.profileByHandle(handle);
      return Profile.fromJson(json);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Lista los amigos del usuario. El owner sale del token en el server:
  /// [ownerEmail] se conserva en la firma por compatibilidad con los callers.
  /// Cacheado con TTL en [ApiCache] (como el servicio es stateless y cada caller
  /// crea su instancia, el cache vive en ApiCache, no acá). `force` para el
  /// pull-to-refresh; las mutaciones invalidan.
  Future<List<Friend>> listFriends(String ownerEmail, {bool force = false}) async {
    const key = 'friends';
    if (!force) {
      final cached = ApiCache.peek<List<Friend>>(key);
      if (cached != null && ApiCache.isFresh(key, ApiCache.ttlFriends)) {
        return cached;
      }
    }
    final rows = await _api.friends();
    final list = rows.map(Friend.fromApi).toList();
    ApiCache.put(key, list);
    return list;
  }

  /// Agrega un amigo (sin requerir aceptación). Devuelve el Friend creado.
  Future<Friend> addFriend(String ownerEmail, Profile friend) async {
    final json = await _api.addFriend(
      friendHandle: friend.handle,
      friendName: friend.name,
      friendEmail: friend.userEmail,
    );
    ApiCache.invalidate('friends'); // la lista cambió
    ApiCache.invalidatePrefix('ranking'); // el ranking incluye a los amigos
    return Friend.fromApi(json);
  }

  /// Elimina una amistad por su page id.
  Future<void> removeFriend(String pageId) async {
    await _api.removeFriend(pageId);
    ApiCache.invalidate('friends');
    ApiCache.invalidatePrefix('ranking');
  }
}
