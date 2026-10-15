import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api/api_client.dart';
import 'api/api_config.dart';
import 'cache/api_cache.dart';

/// Clan que conquistó cada cancha y rey de la cancha (temporada actual).
///
/// Se baja UNA vez para todas las canchas (`GET /clans/court-leaders`), se
/// guarda en el celu (`court_leaders_cache`) y se sirve stale-while-revalidate:
/// pasados [_ttl] se refresca en segundo plano. Antes eran dos llamadas por
/// cada tarjeta del carrusel, y la del clan era la consulta más pesada de la
/// base. Al resolver un partido se invalida ([invalidate]).
///
/// Mismas formas que antes: `{clan, points, members}` / `{name, handle, points}`.
/// Si el backend todavía no tiene el endpoint (404), cae a las consultas por
/// cancha de siempre.
class CourtOwnerCache {
  CourtOwnerCache._();

  static const _kPrefs = 'court_leaders_cache';
  static const _ttl = Duration(minutes: 30);

  /// courtId → `{king, clan}`.
  static Map<String, dynamic>? _leaders;
  static DateTime? _at;
  static bool _restored = false;
  static Future<void>? _inflight;

  /// El backend no tiene `court-leaders` (versión vieja): consultas por cancha.
  static bool _perCourt = false;

  /// Un partido nuevo puede cambiar rey/clan: la próxima lectura refresca.
  static void invalidate() => _at = null;

  static Future<void> _ensure() async {
    if (!_restored) await _restore();
    final fresh = _at != null && DateTime.now().difference(_at!) < _ttl;
    if (fresh || !ApiConfig.isConfigured) return;
    final f = _inflight ??= _fetch().whenComplete(() => _inflight = null);
    // Con algo guardado se responde ya y se refresca en segundo plano.
    if (_leaders == null) await f;
  }

  static Future<void> _fetch() async {
    try {
      final r = await ApiClient().courtLeaders();
      final m = r['leaders'];
      _leaders = m is Map ? Map<String, dynamic>.from(m) : <String, dynamic>{};
      _at = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefs,
          jsonEncode({'at': _at!.millisecondsSinceEpoch, 'leaders': _leaders}));
    } on ApiException catch (e) {
      if (e.statusCode == 404) _perCourt = true;
    } catch (_) {/* sin red: queda lo guardado */}
  }

  static Future<void> _restore() async {
    _restored = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPrefs);
      if (raw == null) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _leaders = Map<String, dynamic>.from(m['leaders'] as Map);
      _at = DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt());
    } catch (_) {/* caché corrupto: ignorar */}
  }

  static Map<String, dynamic>? _entry(String courtId, String field) {
    final e = _leaders?[courtId];
    if (e is! Map) return null;
    final v = e[field];
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }

  /// Lo que haya en memoria, sin esperar a la red (para pintar al instante).
  static Map<String, dynamic>? peekOwner(String courtId) => _perCourt
      ? ApiCache.peek<Map<String, dynamic>?>(_ownerKey(courtId))
      : _entry(courtId, 'clan');

  static Map<String, dynamic>? peekKing(String courtId) => _perCourt
      ? ApiCache.peek<Map<String, dynamic>?>(_kingKey(courtId))
      : _entry(courtId, 'king');

  /// Registro completo del clan dueño `{clan, points, members}` (o null).
  static Future<Map<String, dynamic>?> ownerDataFor(String courtId) async {
    if (courtId.isEmpty) return null;
    await _ensure();
    if (_perCourt) return _legacyOwner(courtId);
    final d = _entry(courtId, 'clan');
    return (d != null && (d['clan'] ?? '').toString().isNotEmpty) ? d : null;
  }

  /// Registro completo del rey `{name, handle, points}` (o null).
  static Future<Map<String, dynamic>?> kingDataFor(String courtId) async {
    if (courtId.isEmpty) return null;
    await _ensure();
    if (_perCourt) return _legacyKing(courtId);
    final d = _entry(courtId, 'king');
    if (d == null) return null;
    final label = (d['name'] ?? '').toString().isNotEmpty
        ? d['name'].toString()
        : (d['handle'] ?? '').toString();
    return label.isEmpty ? null : d;
  }

  /// Etiqueta del clan dueño (para las miniaturas del mapa).
  static Future<String?> ownerFor(String courtId) async {
    final d = await ownerDataFor(courtId);
    final clan = (d?['clan'] ?? '').toString();
    return clan.isEmpty ? null : clan;
  }

  /// Etiqueta del rey: nombre o, si no hay, handle (para las miniaturas).
  static Future<String?> kingFor(String courtId) async {
    final d = await kingDataFor(courtId);
    if (d == null) return null;
    final name = (d['name'] ?? '').toString();
    final handle = (d['handle'] ?? '').toString();
    final label = name.isNotEmpty ? name : handle;
    return label.isEmpty ? null : label;
  }

  // ── Respaldo: backend sin `court-leaders` (una consulta por cancha) ──────

  static String _ownerKey(String courtId) => 'clanowner::$courtId';
  static String _kingKey(String courtId) => 'king::$courtId';

  static Future<Map<String, dynamic>?> _legacyOwner(String courtId) async {
    final key = _ownerKey(courtId);
    if (ApiCache.isFresh(key, ApiCache.ttlClanOwner)) {
      return ApiCache.peek<Map<String, dynamic>?>(key);
    }
    try {
      final r = await ApiClient().clanCourtOwner(courtId);
      final owner = r['owner'];
      final data = owner is Map ? Map<String, dynamic>.from(owner) : null;
      final clean =
          (data != null && (data['clan'] ?? '').toString().isNotEmpty) ? data : null;
      ApiCache.put(key, clean);
      return clean;
    } catch (_) {
      return ApiCache.peek<Map<String, dynamic>?>(key);
    }
  }

  static Future<Map<String, dynamic>?> _legacyKing(String courtId) async {
    final key = _kingKey(courtId);
    if (ApiCache.isFresh(key, ApiCache.ttlKing)) {
      return ApiCache.peek<Map<String, dynamic>?>(key);
    }
    try {
      final r = await ApiClient().courtKing(courtId);
      final king = r['king'];
      final data = king is Map ? Map<String, dynamic>.from(king) : null;
      final label = data == null
          ? ''
          : ((data['name'] ?? '').toString().isNotEmpty
              ? data['name'].toString()
              : (data['handle'] ?? '').toString());
      final clean = label.isEmpty ? null : data;
      ApiCache.put(key, clean);
      return clean;
    } catch (_) {
      return ApiCache.peek<Map<String, dynamic>?>(key);
    }
  }
}
