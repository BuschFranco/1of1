import '../services/play_session_service.dart';

/// Métricas de juego del perfil, calculadas del historial local de sesiones.
///
/// Funciones puras (sin estado ni red): se recalculan al vuelo desde
/// `PlaySessionService.log`. Una sesión de juego puede tener varios partidos y
/// entrenamientos; los partidos se cuentan con `gamesPlayed`/`winsCount` y los
/// entrenamientos aparte (no suman partidos ni puntos).
class GameInsights {
  /// Récord: victorias, derrotas y empates (por partido).
  final int wins;
  final int losses;
  final int ties;
  final int bestStreak;

  /// Por formato (jugadores por equipo → stats). Solo formatos con datos.
  final Map<int, FormatStats> byFormat;

  /// Tiempo en la cancha (toda la sesión, esperas incluidas).
  final int totalSeconds;
  final int monthSeconds;
  final int avgSessionSeconds;

  /// Constancia.
  final double sessionsPerWeek; // promedio de las últimas 4 semanas
  final double gamesPerSession; // entre las sesiones con partidos

  /// Cuándo jugás: día de la semana (1 = lunes … 7 = domingo) y franja.
  final int? favoriteWeekday;
  final String? favoriteBand; // mañana / tarde / noche / madrugada

  /// Entrenamientos.
  final int trainings;
  final int games;

  /// Este mes contra el anterior.
  final MonthStats thisMonth;
  final MonthStats lastMonth;

  const GameInsights({
    required this.wins,
    required this.losses,
    required this.ties,
    required this.bestStreak,
    required this.byFormat,
    required this.totalSeconds,
    required this.monthSeconds,
    required this.avgSessionSeconds,
    required this.sessionsPerWeek,
    required this.gamesPerSession,
    required this.favoriteWeekday,
    required this.favoriteBand,
    required this.trainings,
    required this.games,
    required this.thisMonth,
    required this.lastMonth,
  });

  bool get hasData => games > 0 || trainings > 0 || totalSeconds > 0;

  /// Formato con más partidos, o null.
  int? get favoriteFormat {
    int? best;
    var max = 0;
    byFormat.forEach((f, s) {
      if (s.games > max) {
        max = s.games;
        best = f;
      }
    });
    return best;
  }

  /// Porcentaje de entrenamientos sobre el total de actividades (0–100).
  int get trainingShare {
    final total = games + trainings;
    return total == 0 ? 0 : (trainings * 100 / total).round();
  }

  static GameInsights from(List<PlaySession> log, {int bestStreak = 0, DateTime? now}) {
    final n = now ?? DateTime.now();
    final monthStart = DateTime(n.year, n.month);
    final lastMonthStart = DateTime(n.year, n.month - 1);
    final fourWeeksAgo = n.subtract(const Duration(days: 28));

    var wins = 0, losses = 0, ties = 0, trainings = 0, games = 0;
    var totalSec = 0, monthSec = 0, sessions = 0, sessionsWithGames = 0;
    var recentSessions = 0;
    final byFormat = <int, FormatStats>{};
    final weekdays = <int, int>{};
    final bands = <String, int>{};
    final thisM = MonthStats.builder();
    final lastM = MonthStats.builder();

    for (final s in log) {
      if (s.endedAtMillis <= 0) continue;
      final ended = DateTime.fromMillisecondsSinceEpoch(s.endedAtMillis);
      final started = ended.subtract(Duration(seconds: s.seconds));
      sessions++;
      totalSec += s.seconds;
      if (!ended.isBefore(monthStart)) monthSec += s.seconds;
      if (ended.isAfter(fourWeeksAgo)) recentSessions++;
      weekdays[started.weekday] = (weekdays[started.weekday] ?? 0) + 1;
      final band = _band(started.hour);
      bands[band] = (bands[band] ?? 0) + 1;

      trainings += s.trainingsDone;
      final g = s.ratedGames;
      if (g <= 0) continue;
      games += g;
      sessionsWithGames++;

      // Récord por partido. Sin desglose, el resultado suelto manda.
      final w = s.winsCount;
      var t = 0;
      if (!s.isMultiGame && s.result == PlayResult.tie) t = 1;
      wins += w;
      ties += t;
      losses += (g - w - t).clamp(0, g);

      // Por formato: partidos y victorias solo si la sesión fue de UN formato
      // (con varios no se sabe qué partido ganó); los puntos, partido a partido
      // cuando están cargados.
      final formats = s.formatList;
      if (formats.length == 1) {
        final fs = byFormat.putIfAbsent(formats.first, FormatStats.new);
        fs.games += g;
        fs.wins += w;
      }
      final gp = s.gamePoints;
      final gf = s.gameFormats;
      if (gp != null && gf != null) {
        for (var i = 0; i < gp.length && i < gf.length; i++) {
          final fs = byFormat.putIfAbsent(gf[i], FormatStats.new);
          fs.pointGames++;
          fs.points += gp[i];
        }
      }

      final m = !ended.isBefore(monthStart)
          ? thisM
          : (!ended.isBefore(lastMonthStart) ? lastM : null);
      if (m != null) {
        m.games += g;
        m.wins += w;
        if (s.userPoints != null) {
          m.points += s.userPoints!;
          m.pointGames += g;
        }
      }
    }

    int? topKey(Map<int, int> m) {
      int? best;
      var max = 0;
      m.forEach((k, v) {
        if (v > max) {
          max = v;
          best = k;
        }
      });
      return best;
    }

    String? topBand() {
      String? best;
      var max = 0;
      bands.forEach((k, v) {
        if (v > max) {
          max = v;
          best = k;
        }
      });
      return best;
    }

    return GameInsights(
      wins: wins,
      losses: losses,
      ties: ties,
      bestStreak: bestStreak,
      byFormat: byFormat,
      totalSeconds: totalSec,
      monthSeconds: monthSec,
      avgSessionSeconds: sessions == 0 ? 0 : totalSec ~/ sessions,
      sessionsPerWeek: recentSessions / 4,
      gamesPerSession: sessionsWithGames == 0 ? 0 : games / sessionsWithGames,
      favoriteWeekday: topKey(weekdays),
      favoriteBand: topBand(),
      trainings: trainings,
      games: games,
      thisMonth: thisM.build(),
      lastMonth: lastM.build(),
    );
  }

  static String _band(int hour) => switch (hour) {
        >= 6 && < 12 => 'mañana',
        >= 12 && < 19 => 'tarde',
        >= 19 => 'noche',
        _ => 'madrugada',
      };
}

class FormatStats {
  int games = 0;
  int wins = 0;
  int points = 0;
  int pointGames = 0;

  int? get winRate => games == 0 ? null : (wins * 100 / games).round();
  double? get avgPoints => pointGames == 0 ? null : points / pointGames;
}

class MonthStats {
  final int games;
  final int wins;
  final int points;
  final int pointGames;
  const MonthStats(this.games, this.wins, this.points, this.pointGames);

  int? get winRate => games == 0 ? null : (wins * 100 / games).round();
  double? get avgPoints => pointGames == 0 ? null : points / pointGames;

  static MonthBuilder builder() => MonthBuilder();
}

class MonthBuilder {
  int games = 0, wins = 0, points = 0, pointGames = 0;
  MonthStats build() => MonthStats(games, wins, points, pointGames);
}
