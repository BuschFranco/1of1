import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    // Sin red (modo offline) se ve lo último conocido: amigos, niveles, clanes.
    if (_byEmail.isEmpty) {
      final cached = await _readCache();
      if (cached.isNotEmpty) {
        _byEmail = cached;
        notifyListeners();
      }
    }
    if (!_api.isConfigured || !_api.hasToken) return;
    if (!force &&
        _byEmail.isNotEmpty &&
        ApiCache.isFresh('profiles', ApiCache.ttlProfiles)) {
      return;
    }
    // Al arrancar, una copia guardada de hace menos de [_kStartupTtl] alcanza
    // (antes se pedía siempre). La presencia "Jugando ahora" se refresca igual
    // al abrir una cancha, porque ahí ya rige la guarda corta de arriba.
    if (!force && !_loadedThisRun && _byEmail.isNotEmpty && await _cacheIsFresh()) {
      _loadedThisRun = true;
      ApiCache.put('profiles', true);
      return;
    }
    _loadedThisRun = true;
    _loading = true;
    notifyListeners();
    try {
      // `shareCourt` y `points` faltaban: sin ellos "Jugando ahora" nunca
      // mostraba a otros jugadores y el ranking Total de amigos daba 0.
      final rows = await _api.profiles(
        fields: 'userEmail,handle,clan,name,avatarColor,clanTextColor,clanFont,avatarFrame,playing,playingCourtId,playingSince,shareCourt,points,lastPlayedAt,lastPlayedCourtId,showLastPlayed,title',
      );
      final map = <String, Profile>{};
      for (final row in rows) {
        final p = Profile.fromJson(row);
        if (p.userEmail.isNotEmpty) map[p.userEmail.toLowerCase()] = p;
      }
      _byEmail = map;
      ApiCache.put('profiles', true); // marca de tiempo para la guarda TTL
      if (map.isNotEmpty) unawaited(_writeCache(map));
    } catch (_) {
      // mantener el cache previo si falla la red
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // Global: son los mismos datos públicos que ve cualquier usuario logueado.
  static const _kCache = 'profiles_cache';
  static const _kCacheAt = 'profiles_cache_at';
  static const _kStartupTtl = Duration(minutes: 10);
  bool _loadedThisRun = false;

  Future<bool> _cacheIsFresh() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final at = prefs.getInt(_kCacheAt);
      if (at == null) return false;
      return DateTime.now()
              .difference(DateTime.fromMillisecondsSinceEpoch(at)) <
          _kStartupTtl;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, Profile>> _readCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kCache);
      if (raw == null) return const {};
      final out = <String, Profile>{};
      for (final e in jsonDecode(raw) as List) {
        final p = Profile.fromJson((e as Map).cast<String, dynamic>());
        if (p.userEmail.isNotEmpty) out[p.userEmail.toLowerCase()] = p;
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  Future<void> _writeCache(Map<String, Profile> map) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _kCache, jsonEncode([for (final p in map.values) p.toJson()]));
      await prefs.setInt(_kCacheAt, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }
}
