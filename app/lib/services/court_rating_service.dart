import 'dart:collection';
import '../data/models.dart';
import 'api/api_client.dart';

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

  /// Reseñas de una cancha (sin cache: la pantalla de detalle quiere frescas).
  Future<List<Review>> listReviews(String courtId) async {
    final rows = await _api.courtReviews(courtId);
    return rows.map(Review.fromApi).toList();
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

  /// Limpia el cache (útil si se reescribe una reseña).
  void invalidate(String courtId) => _cache.remove(courtId);
}
