import '../data/models.dart';
import 'api/api_client.dart';

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
  Future<List<Friend>> listFriends(String ownerEmail) async {
    final rows = await _api.friends();
    return rows.map(Friend.fromApi).toList();
  }

  /// Agrega un amigo (sin requerir aceptación). Devuelve el Friend creado.
  Future<Friend> addFriend(String ownerEmail, Profile friend) async {
    final json = await _api.addFriend(
      friendHandle: friend.handle,
      friendName: friend.name,
      friendEmail: friend.userEmail,
    );
    return Friend.fromApi(json);
  }

  /// Elimina una amistad por su page id.
  Future<void> removeFriend(String pageId) async {
    await _api.removeFriend(pageId);
  }
}
