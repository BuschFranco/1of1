import 'api/api_client.dart';
import 'api/api_config.dart';
import 'cache/api_cache.dart';

/// Cache del clan que conquistó cada cancha y del rey de la cancha. Respaldado
/// por [ApiCache] (TTL + stale-while-revalidate), así una sola consulta por
/// cancha sirve tanto a las miniaturas del carrusel del mapa como al detalle,
/// y se refresca sola pasado el TTL. Ante error se sirve lo último cacheado (si
/// hay) y se reintenta en la próxima lectura.
///
/// Guarda la respuesta COMPLETA (`{clan, points}` / `{name, handle, points}`)
/// porque el detalle muestra también los puntos; las miniaturas usan solo la
/// etiqueta vía [ownerFor] / [kingFor].
class CourtOwnerCache {
  CourtOwnerCache._();

  static String ownerKey(String courtId) => 'clanowner::$courtId';
  static String kingKey(String courtId) => 'king::$courtId';

  // Dedup de llamadas concurrentes (muchas miniaturas rebuildeando a la vez).
  static final Map<String, Future<Map<String, dynamic>?>> _ownerInflight = {};
  static final Map<String, Future<Map<String, dynamic>?>> _kingInflight = {};

  /// Registro completo del clan dueño `{clan, points}` (o null si no hay dueño
  /// / sin red). Sirve de cache si está fresco; si no, consulta y cachea.
  static Future<Map<String, dynamic>?> ownerDataFor(String courtId) {
    final key = ownerKey(courtId);
    if (ApiCache.isFresh(key, ApiCache.ttlClanOwner)) {
      return Future.value(ApiCache.peek<Map<String, dynamic>?>(key));
    }
    return _ownerInflight.putIfAbsent(courtId, () async {
      try {
        if (!ApiConfig.isConfigured || courtId.isEmpty) {
          ApiCache.put(key, null);
          return null;
        }
        final r = await ApiClient().clanCourtOwner(courtId);
        final owner = r['owner'];
        final data = owner is Map ? Map<String, dynamic>.from(owner) : null;
        // Sin dueño si el clan viene vacío.
        final clean =
            (data != null && (data['clan'] ?? '').toString().isNotEmpty)
                ? data
                : null;
        ApiCache.put(key, clean);
        return clean;
      } catch (_) {
        // Servir lo viejo si existe; no re-put para que siga "stale" y reintente.
        return ApiCache.peek<Map<String, dynamic>?>(key);
      } finally {
        _ownerInflight.remove(courtId);
      }
    });
  }

  /// Registro completo del rey `{name, handle, points}` (o null).
  static Future<Map<String, dynamic>?> kingDataFor(String courtId) {
    final key = kingKey(courtId);
    if (ApiCache.isFresh(key, ApiCache.ttlKing)) {
      return Future.value(ApiCache.peek<Map<String, dynamic>?>(key));
    }
    return _kingInflight.putIfAbsent(courtId, () async {
      try {
        if (!ApiConfig.isConfigured || courtId.isEmpty) {
          ApiCache.put(key, null);
          return null;
        }
        final r = await ApiClient().courtKing(courtId);
        final king = r['king'];
        final data = king is Map ? Map<String, dynamic>.from(king) : null;
        final label = data == null
            ? ''
            : ((data['name'] ?? '').toString().isNotEmpty
                ? (data['name']).toString()
                : (data['handle'] ?? '').toString());
        final clean = label.isEmpty ? null : data;
        ApiCache.put(key, clean);
        return clean;
      } catch (_) {
        return ApiCache.peek<Map<String, dynamic>?>(key);
      } finally {
        _kingInflight.remove(courtId);
      }
    });
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
}
