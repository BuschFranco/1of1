import 'api/api_client.dart';
import 'api/api_config.dart';

/// Cache en memoria del clan que conquistó cada cancha (insignia con más
/// puntos históricos ahí, resuelta server-side). Lo comparten las miniaturas
/// del carrusel del mapa: una sola consulta por cancha por sesión de app, sin
/// re-pegar al backend en cada swipe/rebuild. `null` = sin dueño o sin red
/// (ante error se olvida la entrada para reintentar en el próximo build).
class CourtOwnerCache {
  CourtOwnerCache._();

  static final Map<String, Future<String?>> _futures = {};

  static Future<String?> ownerFor(String courtId) =>
      _futures.putIfAbsent(courtId, () async {
        if (!ApiConfig.isConfigured || courtId.isEmpty) return null;
        try {
          final r = await ApiClient().clanCourtOwner(courtId);
          final owner = r['owner'];
          if (owner is! Map) return null;
          final clan = (owner['clan'] ?? '').toString();
          return clan.isEmpty ? null : clan;
        } catch (_) {
          _futures.remove(courtId);
          return null;
        }
      });

  // Rey de la cancha (jugador con más puntos esta temporada): nombre o handle
  // para la miniatura. Misma política de cache que [ownerFor].
  static final Map<String, Future<String?>> _kings = {};

  static Future<String?> kingFor(String courtId) =>
      _kings.putIfAbsent(courtId, () async {
        if (!ApiConfig.isConfigured || courtId.isEmpty) return null;
        try {
          final r = await ApiClient().courtKing(courtId);
          final king = r['king'];
          if (king is! Map) return null;
          final name = (king['name'] ?? '').toString();
          final handle = (king['handle'] ?? '').toString();
          final label = name.isNotEmpty ? name : handle;
          return label.isEmpty ? null : label;
        } catch (_) {
          _kings.remove(courtId);
          return null;
        }
      });
}
