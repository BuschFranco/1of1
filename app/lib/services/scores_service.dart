import '../data/scores.dart';
import 'api/api_client.dart';

/// Partidos de NBA / WNBA (resultados, box score, posiciones) **vía el
/// backend** (`ScoresModule`), igual que `NewsService`: la app nunca le pega a
/// ESPN directo. Nunca lanza: degrada a vacío / null y quien llama muestra
/// "sin partidos" en vez de un error.
///
/// Liga Nacional no tiene fuente libre de datos (FeedConstruct tiene los
/// derechos exclusivos): la pantalla ofrece el fixture oficial en el navegador.
class ScoresService {
  static const nba = 'nba';
  static const wnba = 'wnba';
  static const lnb = 'lnb';

  /// Fixture oficial de la Liga Nacional (se abre en el navegador).
  static const lnbFixtureUrl = 'https://www.laliganacional.com.ar/laliga/fixture';

  static Future<List<ScoreGame>> games(String league) async {
    try {
      final raw = await ApiClient().getScoreGames(league);
      return raw.map(ScoreGame.fromApi).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<BoxScore?> boxScore(String league, String id) async {
    try {
      final raw = await ApiClient().getBoxScore(league, id);
      return raw == null ? null : BoxScore.fromApi(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<List<StandingGroup>> standings(String league) async {
    try {
      final raw = await ApiClient().getStandings(league);
      return raw.map(StandingGroup.fromApi).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<List<PowerRow>> power(String league) async {
    try {
      final raw = await ApiClient().getPower(league);
      return raw.map(PowerRow.fromApi).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<PlayerProfile?> player(String league, String id) async {
    try {
      final raw = await ApiClient().getPlayerProfile(league, id);
      return raw == null ? null : PlayerProfile.fromApi(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<TeamProfile?> team(String league, String id) async {
    try {
      final raw = await ApiClient().getTeamProfile(league, id);
      return raw == null ? null : TeamProfile.fromApi(raw);
    } catch (_) {
      return null;
    }
  }
}
