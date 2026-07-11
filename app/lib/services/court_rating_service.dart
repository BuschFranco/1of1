import 'dart:collection';
import '../data/models.dart';
import '../notion/notion_config.dart';
import 'notion_service.dart';

/// Resultado del cálculo de rating para una cancha.
class CourtRating {
  final double? average;
  final int count;

  const CourtRating({this.average, this.count = 0});

  bool get hasRating => average != null && count > 0;
}

/// Servicio que calcula el rating promedio de una cancha a partir de sus
/// reseñas en Notion. Mantiene un cache en memoria para no repetir queries.
class CourtRatingService {
  final NotionService _notion = NotionService();
  final HashMap<String, CourtRating> _cache = HashMap();

  /// Obtiene el rating computado de una cancha. Si ya está en cache, lo retorna
  /// instantáneamente. Si no, consulta Notion, calcula el promedio y lo cachea.
  Future<CourtRating> ratingFor(String courtId) async {
    if (_cache.containsKey(courtId)) return _cache[courtId]!;
    if (!_notion.isConfigured) {
      const r = CourtRating();
      _cache[courtId] = r;
      return r;
    }
    try {
      final rows = await _notion.queryDatabase(
        NotionConfig.dbReviews,
        filter: NotionService.filterText('CourtId', courtId),
      );
      final reviews = rows.map(Review.fromNotion).toList();
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

  /// Limpia el cache (útil si se reescribe una reseña).
  void invalidate(String courtId) => _cache.remove(courtId);
}
