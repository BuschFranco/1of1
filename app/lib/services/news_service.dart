import '../data/models.dart';
import 'api/api_client.dart';

/// Feed de noticias (NBA / WNBA / Liga Nacional) **vía el backend**, no
/// contra ESPN/NewsData.io directamente. Nunca lanza: degrada a lista vacía,
/// y quien llama muestra "sin noticias" en vez de un error.
///
/// Mismo motivo que `GeocodingService`: la llamada externa la hace el
/// backend (`NewsModule`), que además cachea 30 min para no fundir el cupo
/// diario de NewsData.io entre todos los usuarios de la app.
class NewsService {
  static const nba = 'nba';
  static const wnba = 'wnba';
  static const lnb = 'lnb';

  static Future<List<NewsArticle>> forLeague(String league) async {
    try {
      final raw = await ApiClient().getNews(league);
      return raw.map(NewsArticle.fromApi).toList();
    } catch (_) {
      return const [];
    }
  }
}
