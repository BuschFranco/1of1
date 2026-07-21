import 'package:flutter/foundation.dart';
import '../data/courts.dart';
import '../data/models.dart';
import 'api/api_client.dart';
import 'cache/api_cache.dart';

/// Cache de perfiles indexado por email (inmutable). Permite resolver en vivo
/// el handle y la insignia de clan de quien propuso una cancha, de modo que si
/// el usuario cambia su handle o su clan, las miniaturas reflejen el cambio.
///
/// Se recarga al abrir la app; el dataset es chico (un perfil por usuario).
class ProfilesProvider extends ChangeNotifier {
  ProfilesProvider({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

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

  /// Recarga los perfiles. Con guarda TTL: si ya se cargaron hace poco no vuelve
  /// a pegar a la red (evita un `GET /profiles` en cada apertura de detalle).
  /// `force: true` para el pull-to-refresh. La marca se limpia en el logout con
  /// `ApiCache.clear()`.
  Future<void> load({bool force = false}) async {
    if (!_api.isConfigured || !_api.hasToken) return;
    if (!force &&
        _byEmail.isNotEmpty &&
        ApiCache.isFresh('profiles', ApiCache.ttlProfiles)) {
      return;
    }
    _loading = true;
    notifyListeners();
    try {
      final rows = await _api.profiles(
        fields: 'userEmail,handle,clan,name,avatarColor,clanTextColor,clanFont,avatarFrame,playing,playingCourtId,playingSince,lastPlayedAt,lastPlayedCourtId,showLastPlayed,title',
      );
      final map = <String, Profile>{};
      for (final row in rows) {
        final p = Profile.fromJson(row);
        if (p.userEmail.isNotEmpty) map[p.userEmail.toLowerCase()] = p;
      }
      _byEmail = map;
      ApiCache.put('profiles', true); // marca de tiempo para la guarda TTL
    } catch (_) {
      // mantener el cache previo si falla la red
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
