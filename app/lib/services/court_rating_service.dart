import 'dart:collection';
import '../data/models.dart';
import 'api/api_client.dart';
import 'cache/api_cache.dart';

/// Resultado del cálculo de rating para una cancha.
class CourtRating {
  final double? average;
  final int count;

  const CourtRating({this.average, this.count = 0});

  bool get hasRating => average != null && count > 0;
}

/// Servicio de reseñas de canchas: rating promedio (con cache en memoria) y
/// CRUD de reseñas vía backend. Concentra acá lo que antes hacían las pantallas
/// directo contra Notion.
class CourtRatingService {
  CourtRatingService({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;
  final HashMap<String, CourtRating> _cache = HashMap();

  /// Obtiene el rating computado de una cancha. Si ya está en cache, lo retorna
  /// instantáneamente. Si no, consulta el backend, promedia y cachea.
  Future<CourtRating> ratingFor(String courtId) async {
    if (_cache.containsKey(courtId)) return _cache[courtId]!;
    if (!_api.isConfigured || !_api.hasToken) {
      const r = CourtRating();
      _cache[courtId] = r;
      return r;
    }
    try {
      final reviews = await listReviews(courtId);
      if (reviews.isEmpty) {
        const r = CourtRating();
        _cache[courtId] = r;
        return r;
      }
      final sum = reviews.fold<double>(0, (s, r) => s + r.rating);
      final avg = sum / reviews.length;
      final r = CourtRating(average: avg, count: reviews.length);
      _cache[courtId] = r;
      return r;
    } catch (_) {
      const r = CourtRating();
      _cache[courtId] = r;
      return r;
    }
  }

  /// Clave de la lista de reseñas en [ApiCache]. La comparten [ratingFor] y la
  /// pantalla de detalle para no pedir dos veces lo mismo.
  static String reviewsKey(String courtId) => 'reviews::$courtId';

  /// Reseñas de una cancha. Cacheadas con TTL (stale-while-revalidate desde la
  /// UI): dentro del TTL se sirven sin pegar a la red. `force` salta el cache
  /// (pull-to-refresh / tras crear o borrar).
  Future<List<Review>> listReviews(String courtId, {bool force = false}) async {
    final key = reviewsKey(courtId);
    if (!force) {
      final cached = ApiCache.peek<List<Review>>(key);
      if (cached != null && ApiCache.isFresh(key, ApiCache.ttlReviews)) {
        return cached;
      }
    }
    final rows = await _api.courtReviews(courtId);
    final list = rows.map(Review.fromApi).toList();
    ApiCache.put(key, list);
    return list;
  }

  /// Crea una reseña (email y handle salen del token en el server).
  Future<Review> createReview(
    String courtId, {
    required int rating,
    required String comment,
  }) async {
    final json =
        await _api.createReview(courtId, rating: rating, comment: comment);
    invalidate(courtId);
    return Review.fromApi(json);
  }

  /// Borra una reseña (propia, o cualquiera si el token es admin).
  Future<void> deleteReview(String pageId, {String courtId = ''}) async {
    await _api.deleteReview(pageId);
    if (courtId.isNotEmpty) invalidate(courtId);
  }

  /// Limpia el cache del rating agregado y de la lista de reseñas.
  void invalidate(String courtId) {
    _cache.remove(courtId);
    ApiCache.invalidate(reviewsKey(courtId));
  }
}
