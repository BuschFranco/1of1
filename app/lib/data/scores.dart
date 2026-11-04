// Partidos de NBA / WNBA: resultados, box score y posiciones. Clases planas con
// `fromApi` manual (como NewsArticle): el backend (`ScoresModule`) ya mapea
// ESPN a esta forma, así que acá no hay lógica de la fuente.

class ScoreTeam {
  final String name;
  final String abbr;
  final String logo;
  final String score;
  final bool winner;
  final String record;

  const ScoreTeam({
    required this.name,
    required this.abbr,
    required this.logo,
    required this.score,
    required this.winner,
    required this.record,
  });

  factory ScoreTeam.fromApi(Map<String, dynamic> j) => ScoreTeam(
        name: (j['name'] ?? '') as String,
        abbr: (j['abbr'] ?? '') as String,
        logo: (j['logo'] ?? '') as String,
        score: (j['score'] ?? '') as String,
        winner: j['winner'] == true,
        record: (j['record'] ?? '') as String,
      );
}

/// Estado del partido: por jugar, en juego o terminado.
enum GameState { pre, live, post }

class ScoreGame {
  final String id;
  final DateTime? date;
  final GameState state;

  /// Texto de ESPN para el estado ("Final", "Q3 5:12", "7:30 PM ET").
  final String status;
  final ScoreTeam home;
  final ScoreTeam away;

  const ScoreGame({
    required this.id,
    required this.date,
    required this.state,
    required this.status,
    required this.home,
    required this.away,
  });

  factory ScoreGame.fromApi(Map<String, dynamic> j) => ScoreGame(
        id: (j['id'] ?? '') as String,
        date: DateTime.tryParse((j['date'] ?? '') as String)?.toLocal(),
        state: switch (j['state']) {
          'in' => GameState.live,
          'post' => GameState.post,
          _ => GameState.pre,
        },
        status: (j['status'] ?? '') as String,
        home: ScoreTeam.fromApi(
            ((j['home'] ?? const {}) as Map).cast<String, dynamic>()),
        away: ScoreTeam.fromApi(
            ((j['away'] ?? const {}) as Map).cast<String, dynamic>()),
      );
}

class BoxPlayer {
  final String name;
  final String position;
  final bool starter;

  /// No jugó (DNP): se muestra al final, sin números.
  final bool dnp;

  /// Alineado con [BoxScore.columns].
  final List<String> stats;

  const BoxPlayer({
    required this.name,
    required this.position,
    required this.starter,
    required this.dnp,
    required this.stats,
  });

  factory BoxPlayer.fromApi(Map<String, dynamic> j) => BoxPlayer(
        name: (j['name'] ?? '') as String,
        position: (j['position'] ?? '') as String,
        starter: j['starter'] == true,
        dnp: j['dnp'] == true,
        stats: [for (final s in (j['stats'] as List? ?? const [])) '$s'],
      );
}

class BoxTeam {
  final String name;
  final String abbr;
  final String logo;
  final String score;
  final List<BoxPlayer> players;

  const BoxTeam({
    required this.name,
    required this.abbr,
    required this.logo,
    required this.score,
    required this.players,
  });

  factory BoxTeam.fromApi(Map<String, dynamic> j) => BoxTeam(
        name: (j['name'] ?? '') as String,
        abbr: (j['abbr'] ?? '') as String,
        logo: (j['logo'] ?? '') as String,
        score: (j['score'] ?? '') as String,
        players: [
          for (final p in (j['players'] as List? ?? const []))
            BoxPlayer.fromApi((p as Map).cast<String, dynamic>()),
        ],
      );
}

class BoxScore {
  final ScoreGame? game;

  /// Encabezados de las columnas (MIN, PTS, REB, AST, TC, 3P, TL, …).
  final List<String> columns;
  final List<BoxTeam> teams;

  const BoxScore({
    required this.game,
    required this.columns,
    required this.teams,
  });

  factory BoxScore.fromApi(Map<String, dynamic> j) => BoxScore(
        game: j['game'] is Map
            ? ScoreGame.fromApi((j['game'] as Map).cast<String, dynamic>())
            : null,
        columns: [for (final c in (j['columns'] as List? ?? const [])) '$c'],
        teams: [
          for (final t in (j['teams'] as List? ?? const []))
            BoxTeam.fromApi((t as Map).cast<String, dynamic>()),
        ],
      );
}

class StandingRow {
  final int seed;
  final String name;
  final String abbr;
  final String logo;
  final int wins;
  final int losses;
  final String pct;
  final String gamesBehind;
  final String streak;

  const StandingRow({
    required this.seed,
    required this.name,
    required this.abbr,
    required this.logo,
    required this.wins,
    required this.losses,
    required this.pct,
    required this.gamesBehind,
    required this.streak,
  });

  factory StandingRow.fromApi(Map<String, dynamic> j) => StandingRow(
        seed: (j['seed'] as num?)?.toInt() ?? 0,
        name: (j['name'] ?? '') as String,
        abbr: (j['abbr'] ?? '') as String,
        logo: (j['logo'] ?? '') as String,
        wins: (j['wins'] as num?)?.toInt() ?? 0,
        losses: (j['losses'] as num?)?.toInt() ?? 0,
        pct: (j['pct'] ?? '') as String,
        gamesBehind: (j['gamesBehind'] ?? '') as String,
        streak: (j['streak'] ?? '') as String,
      );
}

class StandingGroup {
  final String name;
  final List<StandingRow> rows;

  const StandingGroup({required this.name, required this.rows});

  factory StandingGroup.fromApi(Map<String, dynamic> j) => StandingGroup(
        name: (j['name'] ?? '') as String,
        rows: [
          for (final r in (j['rows'] as List? ?? const []))
            StandingRow.fromApi((r as Map).cast<String, dynamic>()),
        ],
      );
}
