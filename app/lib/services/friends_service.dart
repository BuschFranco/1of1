import '../data/models.dart';
import '../notion/notion_config.dart';
import 'notion_service.dart';

/// Maneja amistades (base Amistades) y búsqueda de perfiles por handle.
class FriendsService {
  FriendsService({NotionService? notion}) : _notion = notion ?? NotionService();
  final NotionService _notion;

  bool get isConfigured => _notion.isConfigured;

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
    final rows = await _notion.queryDatabase(
      NotionConfig.dbProfiles,
      filter: NotionService.filterText('Handle', handle),
    );
    if (rows.isEmpty) return null;
    return Profile.fromNotion(rows.first);
  }

  /// Lista los amigos del usuario (owner).
  Future<List<Friend>> listFriends(String ownerEmail) async {
    final rows = await _notion.queryDatabase(
      NotionConfig.dbFriends,
      filter: NotionService.filterText('OwnerEmail', ownerEmail),
    );
    return rows.map(Friend.fromNotion).toList();
  }

  /// Agrega un amigo (sin requerir aceptación). Devuelve el Friend creado.
  Future<Friend> addFriend(String ownerEmail, Profile friend) async {
    final f = Friend(
      ownerEmail: ownerEmail,
      friendHandle: friend.handle,
      friendName: friend.name,
      friendEmail: friend.userEmail,
    );
    final page = await _notion.createPage(
      NotionConfig.dbFriends,
      f.toNotionProperties(),
    );
    return Friend.fromNotion(page);
  }

  /// Elimina (archiva) una amistad por su page id.
  Future<void> removeFriend(String pageId) async {
    await _notion.archivePage(pageId);
  }
}
