import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
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
  ///
  /// Además se guarda una copia en el celu: sin red (modo offline) se devuelve
  /// la última lista conocida en vez de "no tenés amigos".
  Future<List<Friend>> listFriends(String ownerEmail, {bool force = false}) async {
    const key = 'friends';
    if (!force) {
      final cached = ApiCache.peek<List<Friend>>(key);
      if (cached != null && ApiCache.isFresh(key, ApiCache.ttlFriends)) {
        return cached;
      }
    }
    try {
      final rows = await _api.friends();
      final list = rows.map(Friend.fromApi).toList();
      ApiCache.put(key, list);
      unawaited(_persist(ownerEmail, list));
      return list;
    } catch (_) {
      final stale = ApiCache.peek<List<Friend>>(key) ?? await _readPersisted(ownerEmail);
      if (stale != null) return stale;
      rethrow;
    }
  }

  static String _persistKey(String owner) =>
      'friends_cache::${owner.trim().toLowerCase()}';

  Future<void> _persist(String owner, List<Friend> list) async {
    if (owner.trim().isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _persistKey(owner), jsonEncode([for (final f in list) f.toJson()]));
    } catch (_) {}
  }

  Future<List<Friend>?> _readPersisted(String owner) async {
    if (owner.trim().isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_persistKey(owner));
      if (raw == null) return null;
      return [
        for (final e in jsonDecode(raw) as List)
          Friend.fromApi((e as Map).cast<String, dynamic>())
      ];
    } catch (_) {
      return null;
    }
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
