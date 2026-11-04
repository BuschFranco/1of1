import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../data/scores.dart';
import '../services/cache/api_cache.dart';
import '../services/scores_service.dart';
import '../theme/app_theme.dart';
import 'games_screen.dart';
import 'player_screen.dart';
import 'team_screen.dart';

/// Partido de NBA / WNBA con **línea de tiempo**: el usuario recorre el
/// partido jugada a jugada (deslizando el gráfico o la barra, o con "play") y
/// el marcador, los líderes y la planilla de cada jugador se recalculan para
/// ese momento (`boxAt`). Con el partido en vivo se refresca solo y, si estás
/// parado al final, seguís la última jugada.
class GameDetailScreen extends StatefulWidget {
  final String league;
  final ScoreGame game;

  const GameDetailScreen({super.key, required this.league, required this.game});

  @override
  State<GameDetailScreen> createState() => _GameDetailScreenState();
}

class _GameDetailScreenState extends State<GameDetailScreen> {
  bool _loading = false;

  /// 0 = visitante, 1 = local.
  int _team = 0;

  /// Solapa bajo el hero: 0 = Partido (línea de tiempo y planilla),
  /// 1 = Previa (pronóstico, forma, cara a cara, comparativa…).
  int _view = 0;

  /// Jugada seleccionada en la línea de tiempo; null = la última (en vivo o
  /// final). Mientras sea null, un refresco en vivo sigue la jugada nueva.
  int? _index;
  Timer? _player; // reproducción automática
  Timer? _liveRefresh;

  String get _key => 'scores::box::${widget.league}::${widget.game.id}';

  @override
  void initState() {
    super.initState();
    _load();
    // En vivo: refresco cada 30 s (el backend cachea 1 min con partidos en
    // juego, así que no castiga a ESPN aunque haya muchos mirando).
    _liveRefresh = Timer.periodic(const Duration(seconds: 30), (_) {
      final g = ApiCache.peek<BoxScore>(_key)?.game ?? widget.game;
      if (g.state == GameState.live) _load(force: true);
    });
  }

  @override
  void dispose() {
    _player?.cancel();
    _liveRefresh?.cancel();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    if (!force && ApiCache.isFresh(_key, ApiCache.ttlScores)) return;
    setState(() => _loading = true);
    final box = await ScoresService.boxScore(widget.league, widget.game.id);
    if (box != null) ApiCache.put(_key, box);
    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _togglePlay(int count) {
    if (_player != null) {
      _player!.cancel();
      setState(() => _player = null);
      return;
    }
    // Desde el principio si estabas al final.
    var i = _index ?? count - 1;
    if (i >= count - 1) i = 0;
    setState(() => _index = i);
    _player = Timer.periodic(const Duration(milliseconds: 110), (t) {
      final next = (_index ?? 0) + 1;
      if (next >= count) {
        t.cancel();
        setState(() {
          _player = null;
          _index = null;
        });
        return;
      }
      setState(() => _index = next);
    });
  }

  void _seek(int i, int count) {
    _player?.cancel();
    setState(() {
      _player = null;
      _index = i >= count - 1 ? null : i;
    });
  }

  @override
  Widget build(BuildContext context) {
    final box = ApiCache.peek<BoxScore>(_key);
    final g = box?.game ?? widget.game;
    final tl = box?.timeline;
    final count = tl?.plays.length ?? 0;
    final idx = count == 0 ? -1 : (_index ?? count - 1).clamp(0, count - 1);
    final play = idx >= 0 ? tl!.plays[idx] : null;
    final live = box == null ? null : boxAt(box, math.max(idx, 0));
    final atEnd = _index == null;

    final awayTeam = box?.away;
    final homeTeam = box?.home;
    final awayColor = _color(awayTeam?.color ?? g.away.color, const Color(0xFF3B82F6));
    final homeColor = _color(homeTeam?.color ?? g.home.color, AppColors.accent);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        onRefresh: () => _load(force: true),
        color: AppColors.accent,
        backgroundColor: AppColors.bgElev,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _hero(g, play, atEnd, awayColor, homeColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (box == null && _loading)
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.white(0.4)),
                      ),
                    )
                  else if (box == null)
                    _note('Sin estadísticas de este partido por ahora')
                  // Sin jugar: solo la previa.
                  else if (box.teams.isEmpty)
                    box.preview == null
                        ? _note('Todavía no hay datos de este partido')
                        : _previewView(box.preview!, g, awayColor, homeColor)
                  else ...[
                    if (box.preview != null) ...[
                      _viewTabs(),
                      const SizedBox(height: 14),
                    ],
                    if (_view == 1 && box.preview != null)
                      _previewView(box.preview!, g, awayColor, homeColor)
                    else ...[
                    if (awayTeam != null && homeTeam != null)
                      _linescore(awayTeam, homeTeam, play, tl, awayColor, homeColor),
                    if (tl != null && count > 1) ...[
                      const SizedBox(height: 14),
                      _timelineCard(tl, idx, play!, awayColor, homeColor,
                          awayTeam, homeTeam),
                    ],
                    const SizedBox(height: 18),
                    _sectionLabel(atEnd ? 'LÍDERES' : 'LÍDERES HASTA ACÁ'),
                    const SizedBox(height: 8),
                    _leaders(box, live!, awayColor, homeColor),
                    const SizedBox(height: 18),
                    _teamPicker(g, awayColor, homeColor),
                    const SizedBox(height: 12),
                    _table(box, _teamFor(box, g), live, atEnd || tl == null),
                    const SizedBox(height: 10),
                    Text(
                      'TC: tiros de campo · 3P: triples · TL: tiros libres · '
                      'ROB: robos · TAP: tapas · PER: pérdidas · '
                      'Tocá un jugador para ver sus promedios.',
                      style: AppText.grotesk(
                          size: 10, color: AppColors.white(0.4)),
                    ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  /// Color del equipo, aclarado si es tan oscuro que no se ve sobre el fondo.
  Color _color(String hex, Color fallback) => readableTeamColor(hex, fallback);

  Widget _note(String t) => Padding(
        padding: const EdgeInsets.only(top: 30),
        child: Text(t,
            textAlign: TextAlign.center,
            style: AppText.grotesk(
                size: 14,
                weight: FontWeight.w700,
                color: AppColors.white(0.6))),
      );

  Widget _sectionLabel(String t) => Text(t,
      style: AppText.grotesk(
          size: 10,
          weight: FontWeight.w800,
          color: AppColors.accent,
          letterSpacing: 0.14));

  BoxTeam _teamFor(BoxScore box, ScoreGame g) {
    final abbr = _team == 0 ? g.away.abbr : g.home.abbr;
    for (final t in box.teams) {
      if (t.abbr == abbr) return t;
    }
    return box.teams[_team.clamp(0, box.teams.length - 1)];
  }

  // ── Hero ────────────────────────────────────────────────────────────────

  Widget _hero(ScoreGame g, GamePlay? play, bool atEnd, Color awayColor,
      Color homeColor) {
    final awayScore = play != null && !atEnd ? '${play.away}' : g.away.score;
    final homeScore = play != null && !atEnd ? '${play.home}' : g.home.score;
    final finished = g.state == GameState.post && atEnd;
    final awayWins = (int.tryParse(awayScore) ?? 0) > (int.tryParse(homeScore) ?? 0);
    final homeWins = (int.tryParse(homeScore) ?? 0) > (int.tryParse(awayScore) ?? 0);

    String moment;
    if (play != null && !atEnd) {
      moment = '${_periodName(play.period)} · ${play.clock}';
    } else {
      moment = switch (g.state) {
        GameState.post => 'Final',
        GameState.live => g.status,
        // Sin jugar: fecha y hora locales (ESPN manda "7:30 PM EST").
        GameState.pre => g.date == null
            ? g.status
            : '${g.date!.day.toString().padLeft(2, '0')}/'
                '${g.date!.month.toString().padLeft(2, '0')} · '
                '${g.date!.hour.toString().padLeft(2, '0')}:'
                '${g.date!.minute.toString().padLeft(2, '0')} hs',
      };
    }

    Widget side(ScoreTeam t, String score, bool lead, Color c) {
      final dim = finished && !lead;
      return Expanded(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
                border: Border.all(color: c.withValues(alpha: 0.7), width: 2),
                boxShadow: [
                  BoxShadow(
                      color: c.withValues(alpha: 0.35),
                      blurRadius: 18,
                      spreadRadius: 1),
                ],
              ),
              child: GestureDetector(
                onTap: t.id.isEmpty ? null : () => _openTeam(t.id),
                child: TeamLogo(url: t.logo, size: 52),
              ),
            ),
            const SizedBox(height: 8),
            Text(t.abbr,
                style: AppText.archivo(
                    size: 14,
                    weight: FontWeight.w900,
                    color: dim ? AppColors.white(0.5) : AppColors.ink)),
            if (t.record.isNotEmpty)
              Text(t.record,
                  style:
                      AppText.grotesk(size: 10, color: AppColors.white(0.45))),
            const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, a) =>
                  ScaleTransition(scale: a, child: child),
              child: Text(score,
                  key: ValueKey(score),
                  style: AppText.display(
                      size: 46,
                      color: dim ? AppColors.white(0.45) : AppColors.ink)),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            awayColor.withValues(alpha: 0.55),
            AppColors.bg,
            homeColor.withValues(alpha: 0.55),
          ],
          stops: const [0, 0.5, 1],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 20),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, color: AppColors.ink),
                  ),
                  const Spacer(),
                  _statusPill(g, atEnd),
                  const SizedBox(width: 12),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  side(g.away, awayScore, awayWins, awayColor),
                  Padding(
                    padding: const EdgeInsets.only(top: 112),
                    child: Text('–',
                        style: AppText.display(
                            size: 30, color: AppColors.white(0.3))),
                  ),
                  side(g.home, homeScore, homeWins, homeColor),
                ],
              ),
              const SizedBox(height: 6),
              Text(moment.toUpperCase(),
                  style: AppText.grotesk(
                      size: 11,
                      weight: FontWeight.w800,
                      color: AppColors.white(0.75),
                      letterSpacing: 0.12)),
            ],
          ),
        ),
      ),
    );
  }

  String _periodName(int p) {
    final tl = ApiCache.peek<BoxScore>(_key)?.timeline;
    final regular = tl?.periods ?? 4;
    if (p > regular) return 'Suplementario ${p - regular}';
    return '$p° cuarto';
  }

  Widget _statusPill(ScoreGame g, bool atEnd) {
    final live = g.state == GameState.live && atEnd;
    final label = !atEnd
        ? 'REPETICIÓN'
        : live
            ? 'EN VIVO'
            : g.state == GameState.post
                ? 'FINAL'
                : 'PRÓXIMO';
    final color = live ? const Color(0xFFEF4444) : AppColors.white(0.85);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live) ...[
            const LiveDot(),
            const SizedBox(width: 6),
          ],
          Text(label,
              style: AppText.grotesk(
                  size: 10,
                  weight: FontWeight.w800,
                  color: color,
                  letterSpacing: 0.1)),
        ],
      ),
    );
  }

  // ── Marcador por período ────────────────────────────────────────────────

  Widget _linescore(BoxTeam away, BoxTeam home, GamePlay? play,
      GameTimeline? tl, Color awayColor, Color homeColor) {
    final n = math.max(away.linescores.length, home.linescores.length);
    if (n == 0) return const SizedBox.shrink();
    final regular = tl?.periods ?? 4;
    final current = _index == null ? null : play?.period;
    String head(int p) => p > regular ? 'TS${p - regular}' : '$p';

    Widget row(String label, Color c, List<int> ls, {bool header = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 16,
              decoration: BoxDecoration(
                color: header ? Colors.transparent : c,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              child: Text(label,
                  style: AppText.archivo(
                      size: header ? 10 : 13,
                      weight: FontWeight.w800,
                      color: header ? AppColors.white(0.4) : AppColors.ink)),
            ),
            for (var i = 0; i < n; i++)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  decoration: BoxDecoration(
                    color: current == i + 1
                        ? AppColors.accent.withValues(alpha: 0.18)
                        : null,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    header ? head(i + 1) : (i < ls.length ? '${ls[i]}' : '-'),
                    textAlign: TextAlign.center,
                    style: AppText.grotesk(
                        size: header ? 10 : 13,
                        weight: header ? FontWeight.w700 : FontWeight.w600,
                        color: header ? AppColors.white(0.4) : AppColors.ink),
                  ),
                ),
              ),
            SizedBox(
              width: 40,
              child: Text(
                header ? 'T' : '${ls.fold<int>(0, (a, b) => a + b)}',
                textAlign: TextAlign.right,
                style: AppText.archivo(
                    size: header ? 10 : 14,
                    weight: FontWeight.w900,
                    color: header ? AppColors.white(0.4) : AppColors.ink),
              ),
            ),
          ],
        ),
      );
    }

    return _card(
      child: Column(
        children: [
          row('', Colors.transparent, const [], header: true),
          row(away.abbr, awayColor, away.linescores),
          row(home.abbr, homeColor, home.linescores),
        ],
      ),
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
        padding: padding ?? const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppShape.rCard),
          border: Border.all(color: AppColors.white(0.05)),
        ),
        child: child,
      );

  // ── Línea de tiempo ─────────────────────────────────────────────────────

  Widget _timelineCard(GameTimeline tl, int idx, GamePlay play, Color awayColor,
      Color homeColor, BoxTeam? away, BoxTeam? home) {
    final count = tl.plays.length;
    final total = math.max(tl.totalSeconds, 1);
    final playing = _player != null;

    int nearest(double fraction) {
      final t = fraction.clamp(0.0, 1.0) * total;
      var best = 0;
      for (var i = 0; i < count; i++) {
        if (tl.plays[i].t <= t) best = i;
      }
      return best;
    }

    final sideColor = play.side == 'h'
        ? homeColor
        : play.side == 'a'
            ? awayColor
            : AppColors.white(0.4);
    final sideAbbr = play.side == 'h'
        ? home?.abbr ?? ''
        : play.side == 'a'
            ? away?.abbr ?? ''
            : '';

    return _card(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _sectionLabel('LÍNEA DE TIEMPO'),
              const Spacer(),
              _roundBtn(
                icon: playing ? Icons.pause : Icons.play_arrow,
                onTap: () => _togglePlay(count),
              ),
              const SizedBox(width: 8),
              _roundBtn(
                icon: Icons.skip_next,
                onTap: () => _seek(count - 1, count),
                active: _index == null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Gráfico de momentum: diferencia de puntos a lo largo del partido.
          // Se puede arrastrar para moverse en el tiempo.
          LayoutBuilder(
            builder: (context, c) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) =>
                  _seek(nearest(d.localPosition.dx / c.maxWidth), count),
              onHorizontalDragUpdate: (d) =>
                  _seek(nearest(d.localPosition.dx / c.maxWidth), count),
              child: SizedBox(
                height: 120,
                width: c.maxWidth,
                child: CustomPaint(
                  painter: _MomentumPainter(
                    tl: tl,
                    cursorT: play.t,
                    homeColor: homeColor,
                    awayColor: awayColor,
                    grid: AppColors.white(0.08),
                    labelColor: AppColors.white(0.35),
                  ),
                ),
              ),
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: AppColors.accent,
              inactiveTrackColor: AppColors.white(0.1),
              thumbColor: AppColors.accent,
              overlayColor: AppColors.accent.withValues(alpha: 0.15),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              min: 0,
              max: (count - 1).toDouble(),
              value: idx.toDouble(),
              onChanged: (v) => _seek(v.round(), count),
            ),
          ),
          // La jugada del momento elegido.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: Container(
              key: ValueKey(idx),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: sideColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border(left: BorderSide(color: sideColor, width: 3)),
              ),
              child: Row(
                children: [
                  Icon(_playIcon(play), size: 20, color: sideColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${tl.periodLabel(play.period)} · ${play.clock}'
                          '${sideAbbr.isEmpty ? '' : ' · $sideAbbr'}',
                          style: AppText.grotesk(
                              size: 10,
                              weight: FontWeight.w700,
                              color: AppColors.white(0.5)),
                        ),
                        const SizedBox(height: 2),
                        Text(play.text,
                            style: AppText.grotesk(
                                size: 13,
                                weight: FontWeight.w700,
                                color: AppColors.ink)),
                      ],
                    ),
                  ),
                  if (play.value > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: sideColor,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text('+${play.value}',
                          style: AppText.archivo(
                              size: 12,
                              weight: FontWeight.w900,
                              color: Colors.white)),
                    ),
                ],
              ),
            ),
          ),
          if (play.homeWinProb != null) ...[
            const SizedBox(height: 12),
            _winProb(play.homeWinProb!, awayColor, homeColor, away, home),
          ],
        ],
      ),
    );
  }

  Widget _roundBtn(
      {required IconData icon, required VoidCallback onTap, bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? AppColors.accent : AppColors.white(0.08),
        ),
        child: Icon(icon,
            size: 20, color: active ? Colors.white : AppColors.ink),
      ),
    );
  }

  IconData _playIcon(GamePlay p) => switch (p.kind) {
        'made' => Icons.sports_basketball,
        'miss' => Icons.close_rounded,
        'ft' => p.value > 0 ? Icons.adjust : Icons.close_rounded,
        'reb' => Icons.replay_rounded,
        'to' => Icons.swap_horiz_rounded,
        'foul' => Icons.front_hand_outlined,
        'sub' => Icons.sync_alt_rounded,
        'timeout' => Icons.pause_circle_outline,
        'end' => Icons.flag_outlined,
        'jump' => Icons.north_rounded,
        _ => Icons.circle_outlined,
      };

  Widget _winProb(double home, Color awayColor, Color homeColor, BoxTeam? away,
      BoxTeam? homeT) {
    final h = (home * 100).round().clamp(0, 100);
    final a = 100 - h;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('${away?.abbr ?? ''} $a%',
                style: AppText.grotesk(
                    size: 11, weight: FontWeight.w800, color: awayColor)),
            const Spacer(),
            Text('PROBABILIDAD DE GANAR',
                style: AppText.grotesk(
                    size: 9,
                    weight: FontWeight.w700,
                    color: AppColors.white(0.4),
                    letterSpacing: 0.1)),
            const Spacer(),
            Text('$h% ${homeT?.abbr ?? ''}',
                style: AppText.grotesk(
                    size: 11, weight: FontWeight.w800, color: homeColor)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                Expanded(flex: math.max(a, 1), child: Container(color: awayColor)),
                Expanded(flex: math.max(h, 1), child: Container(color: homeColor)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Líderes ─────────────────────────────────────────────────────────────

  Widget _leaders(BoxScore box, Map<String, LiveLine> live, Color awayColor,
      Color homeColor) {
    (BoxPlayer, BoxTeam, int)? best(int Function(LiveLine) f) {
      (BoxPlayer, BoxTeam, int)? b;
      for (final t in box.teams) {
        for (final p in t.players) {
          final v = f(live[p.id] ?? LiveLine());
          if (v > 0 && (b == null || v > b.$3)) b = (p, t, v);
        }
      }
      return b;
    }

    Widget card(String label, (BoxPlayer, BoxTeam, int)? l) {
      final c = l == null ? AppColors.white(0.2) : (l.$2.isHome ? homeColor : awayColor);
      return Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [c.withValues(alpha: 0.28), AppColors.card],
            ),
            border: Border.all(color: c.withValues(alpha: 0.35)),
          ),
          child: Column(
            children: [
              _headshot(l?.$1.headshot ?? '', c),
              const SizedBox(height: 6),
              Text(l == null ? '—' : '${l.$3}',
                  style: AppText.display(size: 26, color: AppColors.ink)),
              Text(label,
                  style: AppText.grotesk(
                      size: 9,
                      weight: FontWeight.w800,
                      color: AppColors.white(0.5),
                      letterSpacing: 0.1)),
              const SizedBox(height: 4),
              Text(l?.$1.shortName ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.grotesk(
                      size: 11,
                      weight: FontWeight.w700,
                      color: AppColors.white(0.8))),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        card('PUNTOS', best((l) => l.pts)),
        const SizedBox(width: 8),
        card('REBOTES', best((l) => l.reb)),
        const SizedBox(width: 8),
        card('ASISTENCIAS', best((l) => l.ast)),
      ],
    );
  }

  Widget _headshot(String url, Color ring) {
    final fallback = Icon(Icons.person, size: 28, color: AppColors.white(0.3));
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.white(0.06),
        border: Border.all(color: ring, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: url.isEmpty
          ? fallback
          : CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              placeholder: (_, _) => fallback,
              errorWidget: (_, _, _) => fallback,
            ),
    );
  }

  // ── Selector de equipo y planilla ───────────────────────────────────────

  Widget _teamPicker(ScoreGame g, Color awayColor, Color homeColor) {
    Widget opt(int i, ScoreTeam t, Color c) {
      final active = _team == i;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _team = i),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: active ? c : AppColors.card,
              borderRadius: BorderRadius.circular(AppShape.rChip),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TeamLogo(url: t.logo, size: 20),
                const SizedBox(width: 8),
                Text(t.abbr.isEmpty ? t.name : t.abbr,
                    style: AppText.archivo(
                        size: 13,
                        weight: FontWeight.w900,
                        color: active ? Colors.white : AppColors.white(0.7))),
              ],
            ),
          ),
        ),
      );
    }

    return Row(children: [
      opt(0, g.away, awayColor),
      const SizedBox(width: 8),
      opt(1, g.home, homeColor),
    ]);
  }

  Widget _table(BoxScore box, BoxTeam team, Map<String, LiveLine>? live,
      bool atEnd) {
    const nameW = 132.0;
    const colW = 44.0;
    // En un momento intermedio, "jugó" = entró a la cancha hasta ahí.
    bool inGame(BoxPlayer p) =>
        atEnd ? !p.dnp : (live?[p.id]?.played ?? false);
    List<String> raw(BoxPlayer p) =>
        atEnd || live == null ? p.stats : live[p.id]!.cells();
    List<String> cells(BoxPlayer p) => cellsWithPct(box.columns, raw(p));
    final columns = columnsWithPct(box.columns);
    final starters = team.players.where((p) => p.starter && inGame(p)).toList();
    final bench = team.players.where((p) => !p.starter && inGame(p)).toList();
    final out = team.players.where((p) => !inGame(p)).toList();

    TextStyle st({bool head = false, bool bold = false}) => AppText.grotesk(
        size: head ? 9.5 : 12,
        weight: head || bold ? FontWeight.w700 : FontWeight.w500,
        color: head ? AppColors.white(0.4) : AppColors.ink);

    Widget nameCell(BoxPlayer? p, {String? label}) => GestureDetector(
          onTap: p == null ? null : () => _openPlayer(p),
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
          width: nameW,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: label != null
                ? Text(label, style: st(head: true))
                : Row(
                    children: [
                      Flexible(
                        child: Text(p!.shortName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: st(bold: true)),
                      ),
                      if (p.position.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Text(p.position,
                            style: AppText.grotesk(
                                size: 9, color: AppColors.white(0.4))),
                      ],
                    ],
                  ),
          ),
        ),
        );

    Widget statsRow(List<String> values, {bool head = false}) => Row(
          children: [
            for (var i = 0; i < columns.length; i++)
              SizedBox(
                width: colW,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(i < values.length ? values[i] : '',
                      textAlign: TextAlign.center,
                      // PTS resaltada; los % un poco más tenues.
                      style: head
                          ? st(head: true)
                          : i == 1
                              ? st(bold: true)
                              : columns[i].endsWith('%')
                                  ? st().copyWith(color: AppColors.white(0.6))
                                  : st()),
                ),
              ),
          ],
        );

    final names = <Widget>[nameCell(null, label: 'TITULARES')];
    final stats = <Widget>[statsRow(columns, head: true)];
    for (final p in starters) {
      names.add(nameCell(p));
      stats.add(statsRow(cells(p)));
    }
    if (bench.isNotEmpty) {
      names.add(nameCell(null, label: 'SUPLENTES'));
      stats.add(statsRow(const [], head: true));
      for (final p in bench) {
        names.add(nameCell(p));
        stats.add(statsRow(cells(p)));
      }
    }
    // Totales del equipo (con sus porcentajes).
    final played = [...starters, ...bench];
    if (played.isNotEmpty) {
      names.add(nameCell(null, label: 'TOTAL'));
      stats.add(statsRow(cellsWithPct(
          box.columns, teamTotals(box.columns, played.map(raw).toList()))));
    }

    return _card(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: names),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: stats),
                ),
              ),
            ],
          ),
          if (out.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
              child: Text(
                '${atEnd ? 'No jugaron' : 'Todavía no entraron'}: '
                '${out.map((p) => p.shortName).join(', ')}',
                style: AppText.grotesk(size: 11, color: AppColors.white(0.45)),
              ),
            ),
        ],
      ),
    );
  }

  // ── Navegación ──────────────────────────────────────────────────────────

  void _openPlayer(BoxPlayer p) {
    if (p.id.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerScreen(
        league: widget.league,
        playerId: p.id,
        name: p.name,
        headshot: p.headshot,
      ),
    ));
  }

  void _openTeam(String id) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TeamScreen(league: widget.league, teamId: id),
    ));
  }

  // ── Solapas Partido / Previa ────────────────────────────────────────────

  Widget _viewTabs() => ScoreTabs(
        items: const [
          (Icons.timeline, 'Partido'),
          (Icons.query_stats, 'Previa'),
        ],
        active: _view,
        onChange: (i) => setState(() => _view = i),
      );

  // ── Previa ──────────────────────────────────────────────────────────────

  Widget _previewView(
      GamePreview pv, ScoreGame g, Color awayColor, Color homeColor) {
    final out = <Widget>[];
    void section(String label, Widget child) {
      if (out.isNotEmpty) out.add(const SizedBox(height: 18));
      out
        ..add(sectionLabel(label))
        ..add(const SizedBox(height: 8))
        ..add(child);
    }

    if (pv.homeWinProb != null && pv.awayWinProb != null) {
      section('PRONÓSTICO',
          _forecast(pv, g, awayColor, homeColor));
    }
    if (!pv.form.isEmpty) {
      section('ÚLTIMOS 5 PARTIDOS', _form(pv, g, awayColor, homeColor));
    }
    if (pv.h2hSummary.isNotEmpty || pv.h2hGames.isNotEmpty) {
      section('CARA A CARA ESTA TEMPORADA', _h2h(pv));
    }
    if (pv.compare.isNotEmpty) {
      section(
          pv.compareSeason
              ? 'COMPARATIVA · PROMEDIOS DE LA TEMPORADA'
              : 'COMPARATIVA DEL PARTIDO',
          _compare(pv, g, awayColor, homeColor));
    }
    if (!pv.leaders.isEmpty) {
      section(
          pv.compareSeason ? 'LÍDERES DE LA TEMPORADA' : 'LÍDERES DEL PARTIDO',
          _seasonLeaders(pv, g, awayColor, homeColor));
    }
    if (!pv.injuries.isEmpty) {
      section('LESIONADOS', _injuries(pv, g));
    }
    if (out.isEmpty) return _note('Sin previa para este partido');
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: out);
  }

  Widget _forecast(
      GamePreview pv, ScoreGame g, Color awayColor, Color homeColor) {
    final a = (pv.awayWinProb! * 100).round();
    final h = (pv.homeWinProb! * 100).round();
    Widget side(ScoreTeam t, int pct, Color c, bool alignEnd) => Column(
          crossAxisAlignment:
              alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!alignEnd) ...[
                  TeamLogo(url: t.logo, size: 26),
                  const SizedBox(width: 6),
                ],
                Text('$pct%',
                    style: AppText.display(size: 30, color: c)),
                if (alignEnd) ...[
                  const SizedBox(width: 6),
                  TeamLogo(url: t.logo, size: 26),
                ],
              ],
            ),
            Text(t.abbr,
                style: AppText.grotesk(
                    size: 11,
                    weight: FontWeight.w800,
                    color: AppColors.white(0.6))),
          ],
        );
    return _card(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              side(g.away, a, awayColor, false),
              const Spacer(),
              side(g.home, h, homeColor, true),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  Expanded(
                      flex: a.clamp(1, 99), child: Container(color: awayColor)),
                  Container(width: 2, color: AppColors.bg),
                  Expanded(
                      flex: h.clamp(1, 99), child: Container(color: homeColor)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('Probabilidad de ganar según ESPN, antes del partido.',
              style: AppText.grotesk(size: 10, color: AppColors.white(0.4))),
        ],
      ),
    );
  }

  Widget _form(GamePreview pv, ScoreGame g, Color awayColor, Color homeColor) {
    Widget row(ScoreTeam t, List<FormGame> games, Color c) {
      final wins = games.where((x) => x.result == 'W').length;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            TeamLogo(url: t.logo, size: 24),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              child: Text(t.abbr,
                  style: AppText.archivo(size: 13, weight: FontWeight.w900)),
            ),
            for (final f in games)
              Container(
                width: 26,
                height: 26,
                margin: const EdgeInsets.only(right: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: f.result == 'W'
                      ? AppColors.open.withValues(alpha: 0.9)
                      : const Color(0xFFEF4444).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(f.result == 'W' ? 'G' : 'P',
                    style: AppText.archivo(
                        size: 11,
                        weight: FontWeight.w900,
                        color: Colors.white)),
              ),
            const Spacer(),
            Text('$wins-${games.length - wins}',
                style: AppText.archivo(
                    size: 14, weight: FontWeight.w900, color: c)),
          ],
        ),
      );
    }

    return _card(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Column(
        children: [
          row(g.away, pv.form.away, awayColor),
          row(g.home, pv.form.home, homeColor),
        ],
      ),
    );
  }

  /// ESPN manda el resumen de la serie en inglés.
  String _seriesEs(String s) {
    final lead = RegExp(r'^(\w+) leads series (\d+-\d+)').firstMatch(s);
    if (lead != null) return '${lead[1]} gana la serie ${lead[2]}';
    final won = RegExp(r'^(\w+) wins? series (\d+-\d+)').firstMatch(s);
    if (won != null) return '${won[1]} ganó la serie ${won[2]}';
    final tied = RegExp(r'^Series tied (\d+-\d+)').firstMatch(s);
    if (tied != null) return 'Serie empatada ${tied[1]}';
    if (s.startsWith('Series starts')) return 'Primer cruce de la temporada';
    return s;
  }

  Widget _h2h(GamePreview pv) {
    final done = pv.h2hGames.where((x) => x.done).toList();
    String date(DateTime? d) => d == null
        ? ''
        : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    return _card(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_seriesEs(pv.h2hSummary),
              style: AppText.archivo(size: 14, weight: FontWeight.w900)),
          for (final x in done)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    child: Text(date(x.date),
                        style: AppText.grotesk(
                            size: 11, color: AppColors.white(0.45))),
                  ),
                  Expanded(
                    child: Text(
                      '${x.away} ${x.awayScore}  –  ${x.homeScore} ${x.home}',
                      style: AppText.grotesk(
                          size: 13, weight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _compare(
      GamePreview pv, ScoreGame g, Color awayColor, Color homeColor) {
    Widget row(CompareRow r) {
      final a = double.tryParse(r.away) ?? 0;
      final h = double.tryParse(r.home) ?? 0;
      final awayBetter = r.higherIsBetter ? a > h : a < h;
      final homeBetter = r.higherIsBetter ? h > a : h < a;
      final total = (a + h) == 0 ? 1 : (a + h);
      TextStyle v(bool better, Color c) => AppText.archivo(
          size: 14,
          weight: FontWeight.w900,
          color: better ? c : AppColors.white(0.55));
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            Row(
              children: [
                Text(r.away, style: v(awayBetter, awayColor)),
                Expanded(
                  child: Text(r.label,
                      textAlign: TextAlign.center,
                      style: AppText.grotesk(
                          size: 11, color: AppColors.white(0.6))),
                ),
                Text(r.home, style: v(homeBetter, homeColor)),
              ],
            ),
            const SizedBox(height: 4),
            // Barras enfrentadas: cada lado crece hacia el centro.
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FractionallySizedBox(
                      widthFactor: (a / total).clamp(0.02, 1.0),
                      child: Container(
                        height: 5,
                        decoration: BoxDecoration(
                          color: awayColor.withValues(
                              alpha: awayBetter ? 1 : 0.35),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: (h / total).clamp(0.02, 1.0),
                      child: Container(
                        height: 5,
                        decoration: BoxDecoration(
                          color: homeColor.withValues(
                              alpha: homeBetter ? 1 : 0.35),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return _card(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Column(
        children: [
          Row(
            children: [
              TeamLogo(url: g.away.logo, size: 20),
              const SizedBox(width: 6),
              Text(g.away.abbr,
                  style: AppText.archivo(size: 12, weight: FontWeight.w900)),
              const Spacer(),
              Text(g.home.abbr,
                  style: AppText.archivo(size: 12, weight: FontWeight.w900)),
              const SizedBox(width: 6),
              TeamLogo(url: g.home.logo, size: 20),
            ],
          ),
          const SizedBox(height: 4),
          for (final r in pv.compare) row(r),
        ],
      ),
    );
  }

  Widget _seasonLeaders(
      GamePreview pv, ScoreGame g, Color awayColor, Color homeColor) {
    Widget item(LeaderItem l, Color c) => GestureDetector(
          onTap: l.id.isEmpty
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PlayerScreen(
                        league: widget.league,
                        playerId: l.id,
                        name: l.name,
                        headshot: l.headshot),
                  )),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                _headshotSmall(l.headshot, c),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.grotesk(
                              size: 12, weight: FontWeight.w700)),
                      Text(l.cat,
                          style: AppText.grotesk(
                              size: 10, color: AppColors.white(0.45))),
                    ],
                  ),
                ),
                Text(l.value,
                    style: AppText.archivo(
                        size: 16, weight: FontWeight.w900, color: c)),
              ],
            ),
          ),
        );

    Widget col(ScoreTeam t, List<LeaderItem> ls, Color c) => Expanded(
          child: _card(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    TeamLogo(url: t.logo, size: 18),
                    const SizedBox(width: 6),
                    Text(t.abbr,
                        style: AppText.archivo(
                            size: 12, weight: FontWeight.w900)),
                  ],
                ),
                const SizedBox(height: 4),
                for (final l in ls) item(l, c),
              ],
            ),
          ),
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        col(g.away, pv.leaders.away, awayColor),
        const SizedBox(width: 8),
        col(g.home, pv.leaders.home, homeColor),
      ],
    );
  }

  Widget _headshotSmall(String url, Color ring) {
    final fallback = Icon(Icons.person, size: 18, color: AppColors.white(0.3));
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.white(0.06),
        border: Border.all(color: ring, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: url.isEmpty
          ? fallback
          : CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorWidget: (_, _, _) => fallback,
            ),
    );
  }

  Widget _injuries(GamePreview pv, ScoreGame g) {
    Widget team(ScoreTeam t, List<InjuryItem> list) {
      if (list.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                TeamLogo(url: t.logo, size: 18),
                const SizedBox(width: 6),
                Text(t.abbr,
                    style:
                        AppText.archivo(size: 12, weight: FontWeight.w900)),
              ],
            ),
            for (final i in list)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 24),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        i.detail.isEmpty ? i.name : '${i.name} · ${i.detail}',
                        style: AppText.grotesk(size: 12),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: (i.status == 'Afuera'
                                ? const Color(0xFFEF4444)
                                : AppColors.busy)
                            .withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(i.status,
                          style: AppText.grotesk(
                              size: 10,
                              weight: FontWeight.w800,
                              color: i.status == 'Afuera'
                                  ? const Color(0xFFEF4444)
                                  : AppColors.busy)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    return _card(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          team(g.away, pv.injuries.away),
          team(g.home, pv.injuries.home),
        ],
      ),
    );
  }
}

/// Gráfico de momentum: diferencia de puntos (local − visitante) en el
/// tiempo. Arriba de la línea de cero, color del local; abajo, del visitante.
/// Líneas verticales separan los cuartos; el cursor marca el momento elegido.
class _MomentumPainter extends CustomPainter {
  final GameTimeline tl;
  final int cursorT;
  final Color homeColor;
  final Color awayColor;
  final Color grid;
  final Color labelColor;

  _MomentumPainter({
    required this.tl,
    required this.cursorT,
    required this.homeColor,
    required this.awayColor,
    required this.grid,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = math.max(tl.totalSeconds, 1).toDouble();
    var maxDiff = 5;
    for (final p in tl.plays) {
      maxDiff = math.max(maxDiff, (p.home - p.away).abs());
    }
    final top = 14.0; // espacio para las etiquetas de los cuartos
    final h = size.height - top;
    final mid = top + h / 2;
    double x(num t) => t / total * size.width;
    double y(int diff) => mid - diff / maxDiff * (h / 2 - 4);

    // Cuartos.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final lastPeriod = tl.plays.isEmpty ? tl.periods : tl.plays.last.period;
    var start = 0;
    for (var p = 1; p <= math.max(lastPeriod, tl.periods); p++) {
      final len = p > tl.periods ? tl.otLen : tl.periodLen;
      if (p > 1) {
        canvas.drawLine(Offset(x(start), top), Offset(x(start), size.height), gridPaint);
      }
      final tp = TextPainter(
        text: TextSpan(
            text: tl.periodLabel(p),
            style: TextStyle(fontSize: 9, color: labelColor, fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x(start + len / 2) - tp.width / 2, 0));
      start += len;
    }
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), gridPaint);

    // Curva en escalón (el marcador cambia de a saltos).
    final path = Path()..moveTo(0, mid);
    var prevY = mid;
    for (final p in tl.plays) {
      final px = x(p.t);
      path.lineTo(px, prevY);
      prevY = y(p.home - p.away);
      path.lineTo(px, prevY);
    }
    path.lineTo(size.width * math.min(1, (tl.plays.isEmpty ? 0 : tl.plays.last.t) / total), prevY);
    final endX = x(tl.plays.isEmpty ? 0 : tl.plays.last.t);
    final area = Path.from(path)
      ..lineTo(endX, mid)
      ..close();

    // Relleno: arriba color local, abajo visitante (recortando por mitades).
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, size.width, mid));
    canvas.drawPath(area, Paint()..color = homeColor.withValues(alpha: 0.35));
    canvas.restore();
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, mid, size.width, size.height));
    canvas.drawPath(area, Paint()..color = awayColor.withValues(alpha: 0.35));
    canvas.restore();

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // Cursor.
    final cx = x(cursorT);
    canvas.drawLine(
      Offset(cx, top),
      Offset(cx, size.height),
      Paint()
        ..color = AppColors.accent
        ..strokeWidth = 2,
    );
    var diffAt = 0;
    for (final p in tl.plays) {
      if (p.t > cursorT) break;
      diffAt = p.home - p.away;
    }
    canvas.drawCircle(Offset(cx, y(diffAt)), 5, Paint()..color = AppColors.accent);
    canvas.drawCircle(
        Offset(cx, y(diffAt)),
        5,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_MomentumPainter old) =>
      old.cursorT != cursorT || old.tl != tl || old.homeColor != homeColor;
}
