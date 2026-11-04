import 'dart:ui' show Color;

// Partidos de NBA / WNBA: resultados, box score y posiciones. Clases planas con
// `fromApi` manual (como NewsArticle): el backend (`ScoresModule`) ya mapea
// ESPN a esta forma, así que acá no hay lógica de la fuente.

/// Color de equipo de ESPN ("fdb927", sin '#'), o null si no vino o es inválido.
Color? teamColor(String hex) {
  final h = hex.replaceAll('#', '');
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

class ScoreTeam {
  final String id;
  final String name;
  final String abbr;
  final String logo;
  final String score;
  final bool winner;
  final String record;
  final String color;

  const ScoreTeam({
    this.id = '',
    required this.name,
    required this.abbr,
    required this.logo,
    required this.score,
    required this.winner,
    required this.record,
    this.color = '',
  });

  factory ScoreTeam.fromApi(Map<String, dynamic> j) => ScoreTeam(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        abbr: (j['abbr'] ?? '') as String,
        logo: (j['logo'] ?? '') as String,
        score: (j['score'] ?? '') as String,
        winner: j['winner'] == true,
        record: (j['record'] ?? '') as String,
        color: (j['color'] ?? '') as String,
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
  final String id;
  final String name;
  final String shortName;
  final String headshot;
  final String position;
  final bool starter;

  /// No jugó (DNP): se muestra al final, sin números.
  final bool dnp;

  /// Alineado con [BoxScore.columns].
  final List<String> stats;

  const BoxPlayer({
    required this.id,
    required this.name,
    required this.shortName,
    required this.headshot,
    required this.position,
    required this.starter,
    required this.dnp,
    required this.stats,
  });

  factory BoxPlayer.fromApi(Map<String, dynamic> j) => BoxPlayer(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        shortName: (j['shortName'] ?? j['name'] ?? '') as String,
        headshot: (j['headshot'] ?? '') as String,
        position: (j['position'] ?? '') as String,
        starter: j['starter'] == true,
        dnp: j['dnp'] == true,
        stats: [for (final s in (j['stats'] as List? ?? const [])) '$s'],
      );
}

class BoxTeam {
  final String id;
  final bool isHome;
  final String name;
  final String abbr;
  final String logo;
  final String score;
  final String color;
  final String altColor;

  /// Puntos por período (Q1, Q2, …, suplementarios).
  final List<int> linescores;
  final List<BoxPlayer> players;

  const BoxTeam({
    this.id = '',
    required this.isHome,
    required this.name,
    required this.abbr,
    required this.logo,
    required this.score,
    required this.color,
    required this.altColor,
    required this.linescores,
    required this.players,
  });

  factory BoxTeam.fromApi(Map<String, dynamic> j) => BoxTeam(
        id: (j['id'] ?? '') as String,
        isHome: j['side'] == 'home',
        name: (j['name'] ?? '') as String,
        abbr: (j['abbr'] ?? '') as String,
        logo: (j['logo'] ?? '') as String,
        score: (j['score'] ?? '') as String,
        color: (j['color'] ?? '') as String,
        altColor: (j['altColor'] ?? '') as String,
        linescores: [
          for (final v in (j['linescores'] as List? ?? const []))
            (v as num).toInt(),
        ],
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

  /// Jugada a jugada (null si ESPN no la publica o el partido no empezó).
  final GameTimeline? timeline;

  /// Previa / contexto (pronóstico, forma, cara a cara, comparativa…).
  final GamePreview? preview;

  const BoxScore({
    required this.game,
    required this.columns,
    required this.teams,
    this.timeline,
    this.preview,
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
        timeline: j['timeline'] is Map
            ? GameTimeline.fromApi(
                (j['timeline'] as Map).cast<String, dynamic>())
            : null,
        preview: j['preview'] is Map
            ? GamePreview.fromApi((j['preview'] as Map).cast<String, dynamic>())
            : null,
      );

  BoxTeam? get home => teams.where((t) => t.isHome).firstOrNull;
  BoxTeam? get away => teams.where((t) => !t.isHome).firstOrNull;
}

/// Una jugada: el marcador después de ella y los cambios de estadística que
/// produce (`d`: idJugador, stat, n). Ver `ScoresModule.timeline` en el backend.
class GamePlay {
  final int t; // segundos de juego transcurridos
  final int period;
  final String clock;
  final int home;
  final int away;

  /// 'h' local, 'a' visitante, '' sin equipo (fin de período, etc.).
  final String side;

  /// made · miss · ft · reb · to · foul · sub · timeout · end · jump · other
  final String kind;
  final int value;
  final String text;
  final List<(String, String, int)> deltas;
  final String? subIn;
  final String? subOut;

  /// Probabilidad de ganar del local (0..1), si ESPN la publica.
  final double? homeWinProb;

  const GamePlay({
    required this.t,
    required this.period,
    required this.clock,
    required this.home,
    required this.away,
    required this.side,
    required this.kind,
    required this.value,
    required this.text,
    required this.deltas,
    this.subIn,
    this.subOut,
    this.homeWinProb,
  });

  factory GamePlay.fromApi(Map<String, dynamic> j) => GamePlay(
        t: (j['t'] as num?)?.toInt() ?? 0,
        period: (j['per'] as num?)?.toInt() ?? 1,
        clock: (j['clock'] ?? '') as String,
        home: (j['h'] as num?)?.toInt() ?? 0,
        away: (j['a'] as num?)?.toInt() ?? 0,
        side: (j['side'] ?? '') as String,
        kind: (j['kind'] ?? 'other') as String,
        value: (j['v'] as num?)?.toInt() ?? 0,
        text: (j['text'] ?? '') as String,
        deltas: [
          for (final d in (j['d'] as List? ?? const []))
            if (d is List && d.length == 3)
              ('${d[0]}', '${d[1]}', (d[2] as num).toInt()),
        ],
        subIn: j['in'] as String?,
        subOut: j['out'] as String?,
        homeWinProb: (j['wp'] as num?)?.toDouble(),
      );
}

class GameTimeline {
  final int periods;
  final int periodLen;
  final int otLen;
  final List<GamePlay> plays;

  const GameTimeline({
    required this.periods,
    required this.periodLen,
    required this.otLen,
    required this.plays,
  });

  factory GameTimeline.fromApi(Map<String, dynamic> j) => GameTimeline(
        periods: (j['periods'] as num?)?.toInt() ?? 4,
        periodLen: (j['periodLen'] as num?)?.toInt() ?? 720,
        otLen: (j['otLen'] as num?)?.toInt() ?? 300,
        plays: [
          for (final p in (j['plays'] as List? ?? const []))
            GamePlay.fromApi((p as Map).cast<String, dynamic>()),
        ],
      );

  /// Duración total del partido según las jugadas (incluye suplementarios).
  int get totalSeconds {
    final last = plays.isEmpty ? 1 : plays.last.period;
    return periods * periodLen + (last > periods ? (last - periods) * otLen : 0);
  }

  /// Etiqueta del período: "1C", "2C", … o "TS1" (tiempo suplementario).
  String periodLabel(int p) => p > periods ? 'TS${p - periods}' : '${p}C';
}

/// Estadística de un jugador en un momento del partido.
class LiveLine {
  int seconds = 0;
  int pts = 0, reb = 0, ast = 0, stl = 0, blk = 0, to = 0, pf = 0;
  int fgm = 0, fga = 0, tpm = 0, tpa = 0, ftm = 0, fta = 0, plusMinus = 0;
  bool played = false;

  /// Mismo orden que las columnas del box (MIN, PTS, REB, AST, TC, 3P, TL,
  /// ROB, TAP, PER, +/-).
  List<String> cells() => [
        '${(seconds / 60).round()}',
        '$pts',
        '$reb',
        '$ast',
        '$fgm-$fga',
        '$tpm-$tpa',
        '$ftm-$fta',
        '$stl',
        '$blk',
        '$to',
        plusMinus > 0 ? '+$plusMinus' : '$plusMinus',
      ];
}

/// Columnas que muestra la planilla: las del backend con el porcentaje
/// intercalado después de cada "convertidos-intentados" (TC, 3P, TL).
List<String> columnsWithPct(List<String> base) => [
      for (final c in base) ...[
        c,
        if (c == 'TC' || c == '3P' || c == 'TL') '$c%',
      ],
    ];

/// "8-18" → "44"; sin intentos, "—".
String pctOf(String madeAttempted) {
  final parts = madeAttempted.split('-');
  if (parts.length != 2) return '—';
  final m = int.tryParse(parts[0]) ?? 0;
  final a = int.tryParse(parts[1]) ?? 0;
  return a == 0 ? '—' : '${(m * 100 / a).round()}';
}

/// Inserta los porcentajes en una fila alineada con [base] (ver
/// [columnsWithPct]).
List<String> cellsWithPct(List<String> base, List<String> cells) => [
      for (var i = 0; i < base.length; i++) ...[
        i < cells.length ? cells[i] : '',
        if (base[i] == 'TC' || base[i] == '3P' || base[i] == 'TL')
          pctOf(i < cells.length ? cells[i] : ''),
      ],
    ];

/// Fila de totales del equipo: suma columna por columna ("m-a" suma ambos
/// lados; el +/- no se suma porque no tiene sentido por equipo).
List<String> teamTotals(List<String> base, List<List<String>> rows) {
  final out = <String>[];
  for (var i = 0; i < base.length; i++) {
    if (base[i] == '+/-') {
      out.add('');
      continue;
    }
    var a = 0, b = 0;
    var pair = false;
    for (final r in rows) {
      if (i >= r.length) continue;
      final v = r[i];
      if (v.contains('-') && !v.startsWith('-')) {
        pair = true;
        final ps = v.split('-');
        a += int.tryParse(ps[0]) ?? 0;
        b += int.tryParse(ps.length > 1 ? ps[1] : '') ?? 0;
      } else {
        a += int.tryParse(v.replaceAll('+', '')) ?? 0;
      }
    }
    out.add(pair ? '$a-$b' : '$a');
  }
  return out;
}

/// Reconstruye el box score hasta la jugada [upTo] (inclusive), sumando los
/// cambios de cada jugada. Minutos y +/- salen de quién estaba en cancha:
/// arrancan los titulares y cada sustitución cambia el quinteto (se validó
/// contra el box final de ESPN: 0 diferencias en minutos y estadísticas).
Map<String, LiveLine> boxAt(BoxScore box, int upTo) {
  final tl = box.timeline;
  final out = <String, LiveLine>{};
  final homeIds = <String>{};
  final onCourt = <String, int>{}; // id → segundo en que entró
  for (final t in box.teams) {
    for (final p in t.players) {
      out[p.id] = LiveLine();
      if (t.isHome) homeIds.add(p.id);
      if (p.starter) {
        onCourt[p.id] = 0;
        out[p.id]!.played = true;
      }
    }
  }
  if (tl == null || tl.plays.isEmpty) return out;
  final last = upTo.clamp(0, tl.plays.length - 1);
  var prevHome = 0, prevAway = 0;
  for (var i = 0; i <= last; i++) {
    final p = tl.plays[i];
    // +/-: lo que cambió el marcador, para los que estaban en cancha.
    final dh = p.home - prevHome, da = p.away - prevAway;
    if (dh != 0 || da != 0) {
      for (final id in onCourt.keys) {
        final l = out[id];
        if (l == null) continue;
        l.plusMinus += homeIds.contains(id) ? dh - da : da - dh;
      }
      prevHome = p.home;
      prevAway = p.away;
    }
    for (final (id, stat, n) in p.deltas) {
      final l = out.putIfAbsent(id, LiveLine.new);
      l.played = true;
      switch (stat) {
        case 'pts':
          l.pts += n;
        case 'reb':
          l.reb += n;
        case 'ast':
          l.ast += n;
        case 'stl':
          l.stl += n;
        case 'blk':
          l.blk += n;
        case 'to':
          l.to += n;
        case 'pf':
          l.pf += n;
        case 'fgm':
          l.fgm += n;
        case 'fga':
          l.fga += n;
        case 'tpm':
          l.tpm += n;
        case 'tpa':
          l.tpa += n;
        case 'ftm':
          l.ftm += n;
        case 'fta':
          l.fta += n;
      }
    }
    if (p.kind == 'sub' && p.subIn != null && p.subOut != null) {
      final since = onCourt.remove(p.subOut);
      if (since != null) out[p.subOut]?.seconds += p.t - since;
      onCourt[p.subIn!] = p.t;
      out.putIfAbsent(p.subIn!, LiveLine.new).played = true;
    }
  }
  final now = tl.plays[last].t;
  for (final e in onCourt.entries) {
    out[e.key]?.seconds += now - e.value;
  }
  return out;
}

class StandingRow {
  final String id;
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
    this.id = '',
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
        id: (j['id'] ?? '') as String,
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


// ── Previa / pronósticos / perfiles ─────────────────────────────────────────

List<Map<String, dynamic>> _maps(Object? v) => [
      for (final e in (v as List? ?? const []))
        if (e is Map) e.cast<String, dynamic>(),
    ];
String _s(Object? v) => v == null ? '' : '$v';
double _d(Object? v) => (v as num?)?.toDouble() ?? 0;

class FormGame {
  final String result; // 'W' | 'L'
  final String opp;
  final String score;
  final String atVs;
  const FormGame(this.result, this.opp, this.score, this.atVs);
  factory FormGame.fromApi(Map<String, dynamic> j) =>
      FormGame(_s(j['result']), _s(j['opp']), _s(j['score']), _s(j['atVs']));
}

class H2hGame {
  final DateTime? date;
  final String home, away, homeScore, awayScore;
  final bool done;
  const H2hGame(
      this.date, this.home, this.away, this.homeScore, this.awayScore, this.done);
  factory H2hGame.fromApi(Map<String, dynamic> j) => H2hGame(
      DateTime.tryParse(_s(j['date']))?.toLocal(),
      _s(j['home']),
      _s(j['away']),
      _s(j['homeScore']),
      _s(j['awayScore']),
      j['done'] == true);
}

class CompareRow {
  final String label, home, away;
  final bool higherIsBetter;
  const CompareRow(this.label, this.home, this.away, this.higherIsBetter);
  factory CompareRow.fromApi(Map<String, dynamic> j) => CompareRow(
      _s(j['label']), _s(j['home']), _s(j['away']), j['higherIsBetter'] != false);
}

class LeaderItem {
  final String cat, id, name, headshot, value;
  const LeaderItem(this.cat, this.id, this.name, this.headshot, this.value);
  factory LeaderItem.fromApi(Map<String, dynamic> j) => LeaderItem(_s(j['cat']),
      _s(j['id']), _s(j['name']), _s(j['headshot']), _s(j['value']));
}

class InjuryItem {
  final String name, status, detail;
  const InjuryItem(this.name, this.status, this.detail);
  factory InjuryItem.fromApi(Map<String, dynamic> j) =>
      InjuryItem(_s(j['name']), _s(j['status']), _s(j['detail']));
}

/// Par local / visitante de cualquier lista.
class Sides<T> {
  final List<T> home;
  final List<T> away;
  const Sides(this.home, this.away);
  factory Sides.fromApi(
          Object? j, T Function(Map<String, dynamic>) f) =>
      j is Map
          ? Sides(_maps(j['home']).map(f).toList(),
              _maps(j['away']).map(f).toList())
          : Sides(const [], const []);
  bool get isEmpty => home.isEmpty && away.isEmpty;
}

class GamePreview {
  /// Pronóstico de ESPN antes del partido (0..1).
  final double? homeWinProb;
  final double? awayWinProb;
  final String h2hSummary;
  final List<H2hGame> h2hGames;
  final Sides<FormGame> form;

  /// true = promedios de la temporada; false = números del partido.
  final bool compareSeason;
  final List<CompareRow> compare;
  final Sides<LeaderItem> leaders;
  final Sides<InjuryItem> injuries;

  const GamePreview({
    required this.homeWinProb,
    required this.awayWinProb,
    required this.h2hSummary,
    required this.h2hGames,
    required this.form,
    required this.compareSeason,
    required this.compare,
    required this.leaders,
    required this.injuries,
  });

  factory GamePreview.fromApi(Map<String, dynamic> j) {
    final wp = j['winProb'] is Map ? (j['winProb'] as Map) : null;
    final h2h = j['h2h'] is Map ? (j['h2h'] as Map) : null;
    final cmp = j['compare'] is Map ? (j['compare'] as Map) : null;
    return GamePreview(
      homeWinProb: (wp?['home'] as num?)?.toDouble(),
      awayWinProb: (wp?['away'] as num?)?.toDouble(),
      h2hSummary: _s(h2h?['summary']),
      h2hGames: _maps(h2h?['games']).map(H2hGame.fromApi).toList(),
      form: Sides.fromApi(j['form'], FormGame.fromApi),
      compareSeason: cmp?['season'] == true,
      compare: _maps(cmp?['rows']).map(CompareRow.fromApi).toList(),
      leaders: Sides.fromApi(j['leaders'], LeaderItem.fromApi),
      injuries: Sides.fromApi(j['injuries'], InjuryItem.fromApi),
    );
  }
}

/// Fila del power ranking (ESPN BPI). Porcentajes 0..100.
class PowerRow {
  final String id, name, abbr, logo;
  final int rank;
  final double bpi, projW, projL, playoffs, playIn, finals, title;

  const PowerRow({
    required this.id,
    required this.name,
    required this.abbr,
    required this.logo,
    required this.rank,
    required this.bpi,
    required this.projW,
    required this.projL,
    required this.playoffs,
    required this.playIn,
    required this.finals,
    required this.title,
  });

  factory PowerRow.fromApi(Map<String, dynamic> j) => PowerRow(
        id: _s(j['id']),
        name: _s(j['name']),
        abbr: _s(j['abbr']),
        logo: _s(j['logo']),
        rank: (j['rank'] as num?)?.toInt() ?? 0,
        bpi: _d(j['bpi']),
        projW: _d(j['projW']),
        projL: _d(j['projL']),
        playoffs: _d(j['playoffs']),
        playIn: _d(j['playIn']),
        finals: _d(j['finals']),
        title: _d(j['title']),
      );
}

/// Promedios (labels de ESPN: GP, MIN, FG%, 3P%, FT%, REB, AST, BLK, STL, PF,
/// TO, PTS).
class StatLine {
  final List<String> labels;
  final List<String> values;
  const StatLine(this.labels, this.values);

  static StatLine? fromApi(Object? j) => j is Map
      ? StatLine([for (final l in (j['labels'] as List? ?? const [])) '$l'],
          [for (final v in (j['values'] as List? ?? const [])) '$v'])
      : null;

  String of(String label) {
    final i = labels.indexOf(label);
    return i >= 0 && i < values.length ? values[i] : '';
  }
}

class PlayerGame {
  final DateTime? date;
  final String opp, oppLogo, atVs, result, score;
  final StatLine stats;
  const PlayerGame(this.date, this.opp, this.oppLogo, this.atVs, this.result,
      this.score, this.stats);
  factory PlayerGame.fromApi(Map<String, dynamic> j) => PlayerGame(
        DateTime.tryParse(_s(j['date']))?.toLocal(),
        _s(j['opp']),
        _s(j['oppLogo']),
        _s(j['atVs']),
        _s(j['result']),
        _s(j['score']),
        StatLine([for (final l in (j['labels'] as List? ?? const [])) '$l'],
            [for (final v in (j['stats'] as List? ?? const [])) '$v']),
      );
}

class PlayerProfile {
  final String id, name, headshot, position, jersey;
  final String teamId, teamName, teamAbbr, teamLogo, teamColor;
  final List<(String, String)> info;
  final StatLine? season;
  final StatLine? career;
  final List<PlayerGame> lastGames;

  const PlayerProfile({
    required this.id,
    required this.name,
    required this.headshot,
    required this.position,
    required this.jersey,
    required this.teamId,
    required this.teamName,
    required this.teamAbbr,
    required this.teamLogo,
    required this.teamColor,
    required this.info,
    required this.season,
    required this.career,
    required this.lastGames,
  });

  factory PlayerProfile.fromApi(Map<String, dynamic> j) {
    final t = j['team'] is Map ? (j['team'] as Map) : const {};
    return PlayerProfile(
      id: _s(j['id']),
      name: _s(j['name']),
      headshot: _s(j['headshot']),
      position: _s(j['position']),
      jersey: _s(j['jersey']),
      teamId: _s(t['id']),
      teamName: _s(t['name']),
      teamAbbr: _s(t['abbr']),
      teamLogo: _s(t['logo']),
      teamColor: _s(t['color']),
      info: [for (final m in _maps(j['info'])) (_s(m['label']), _s(m['value']))],
      season: StatLine.fromApi(j['season']),
      career: StatLine.fromApi(j['career']),
      lastGames: _maps(j['lastGames']).map(PlayerGame.fromApi).toList(),
    );
  }
}

class RosterPlayer {
  final String id, name, headshot, position, jersey, pts, reb, ast, min;
  const RosterPlayer(this.id, this.name, this.headshot, this.position,
      this.jersey, this.pts, this.reb, this.ast, this.min);
  factory RosterPlayer.fromApi(Map<String, dynamic> j) => RosterPlayer(
      _s(j['id']),
      _s(j['name']),
      _s(j['headshot']),
      _s(j['position']),
      _s(j['jersey']),
      _s(j['pts']),
      _s(j['reb']),
      _s(j['ast']),
      _s(j['min']));
}

class TeamProfile {
  final String id, name, abbr, logo, color, record, standing;
  final PowerRow? power;
  final List<(String, String)> averages;
  final List<RosterPlayer> roster;

  const TeamProfile({
    required this.id,
    required this.name,
    required this.abbr,
    required this.logo,
    required this.color,
    required this.record,
    required this.standing,
    required this.power,
    required this.averages,
    required this.roster,
  });

  factory TeamProfile.fromApi(Map<String, dynamic> j) => TeamProfile(
        id: _s(j['id']),
        name: _s(j['name']),
        abbr: _s(j['abbr']),
        logo: _s(j['logo']),
        color: _s(j['color']),
        record: _s(j['record']),
        standing: _s(j['standing']),
        power: j['power'] is Map
            ? PowerRow.fromApi((j['power'] as Map).cast<String, dynamic>())
            : null,
        averages: [
          for (final m in _maps(j['averages'])) (_s(m['label']), _s(m['value']))
        ],
        roster: _maps(j['roster']).map(RosterPlayer.fromApi).toList(),
      );
}
