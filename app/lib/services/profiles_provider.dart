import 'package:flutter/foundation.dart';
import '../data/courts.dart';
import '../data/models.dart';
import '../notion/notion_config.dart';
import 'notion_service.dart';

/// Cache de perfiles indexado por email (inmutable). Permite resolver en vivo
/// el handle y la insignia de clan de quien propuso una cancha, de modo que si
/// el usuario cambia su handle o su clan, las miniaturas reflejen el cambio.
///
/// Se recarga al abrir la app; el dataset es chico (un perfil por usuario).
class ProfilesProvider extends ChangeNotifier {
  ProfilesProvider({NotionService? notion}) : _notion = notion ?? NotionService();

  final NotionService _notion;

  Map<String, Profile> _byEmail = {};
  bool _loading = false;

  bool get loading => _loading;

  /// Todos los perfiles cacheados (para buscar quién está jugando en una cancha).
  List<Profile> get all => _byEmail.values.toList();

  /// Perfil actual de un usuario por su email, o null si no está cacheado.
  Profile? byEmail(String email) {
    if (email.isEmpty) return null;
    return _byEmail[email.toLowerCase()];
  }

  /// Resuelve el handle y el clan vigentes de quien propuso una cancha.
  /// Prioridad: perfil de la sesión actual (refleja cambios al instante) >
  /// cache de perfiles por email > snapshot guardado en la cancha.
  ({String handle, String clan}) resolveProposer(
    Court court, {
    Profile? sessionProfile,
    String? sessionEmail,
  }) {
    final email = court.proposedByEmail.toLowerCase();
    Profile? p;
    if (email.isNotEmpty &&
        sessionEmail != null &&
        sessionEmail.toLowerCase() == email) {
      p = sessionProfile;
    } else {
      p = byEmail(email);
    }
    final handle =
        (p != null && p.handle.isNotEmpty) ? p.handle : court.proposedBy;
    final clan = p != null ? p.clan : court.proposedByClan;
    return (handle: handle, clan: clan);
  }

  Future<void> load() async {
    if (!_notion.isConfigured) return;
    _loading = true;
    notifyListeners();
    try {
      final rows = await _notion.queryDatabase(NotionConfig.dbProfiles);
      final map = <String, Profile>{};
      for (final row in rows) {
        final p = Profile.fromNotion(row);
        if (p.userEmail.isNotEmpty) map[p.userEmail.toLowerCase()] = p;
      }
      _byEmail = map;
    } catch (_) {
      // mantener el cache previo si falla la red
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
