import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/scores.dart';
import '../services/analytics_service.dart';
import '../services/cache/api_cache.dart';
import '../services/scores_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_chip.dart';
import '../widgets/pressable_widget.dart';
import 'game_detail_screen.dart';
import 'team_screen.dart';

/// Segmento "Partidos" de Social: resultados recientes y posiciones de NBA y
/// WNBA (ESPN vía el backend), filtrables por liga con los mismos chips que
/// Noticias. Liga Nacional no tiene fuente libre de datos: muestra el link al
/// fixture oficial.
///
/// [topPadding]: mismo mecanismo que `NewsScreen` (el selector de segmentos de
/// `SocialScreen` ya ocupa el espacio de arriba).
class GamesScreen extends StatefulWidget {
  final double topPadding;

  const GamesScreen({super.key, this.topPadding = 8});

  @override
  State<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends State<GamesScreen> {
  String _league = ScoresService.nba;

  /// 0 = resultados, 1 = posiciones, 2 = pronósticos (ESPN BPI).
  int _view = 0;
  bool _loading = false;

  String get _gamesKey => 'scores::games::$_league';
  String get _standingsKey => 'scores::standings::$_league';
  String get _powerKey => 'scores::power::$_league';
  bool get _hasData => _league != ScoresService.lnb;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Patrón (a) de docs/cache.md: peek síncrono + fetch si no está fresco.
  Future<void> _load({bool force = false}) async {
    if (!_hasData) return;
    final view = _view;
    final league = _league;
    final (key, ttl) = switch (view) {
      1 => (_standingsKey, ApiCache.ttlStandings),
      2 => (_powerKey, ApiCache.ttlPower),
      _ => (_gamesKey, ApiCache.ttlScores),
    };
    if (!force && ApiCache.isFresh(key, ttl)) return;
    setState(() => _loading = true);
    switch (view) {
      case 1:
        ApiCache.put(key, await ScoresService.standings(league));
      case 2:
        ApiCache.put(key, await ScoresService.power(league));
      default:
        ApiCache.put(key, await ScoresService.games(league));
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _selectLeague(String league) {
    if (league == _league) return;
    setState(() => _league = league);
    _load();
  }

  void _selectView(int view) {
    if (view == _view) return;
    setState(() => _view = view);
    AnalyticsService.event('games_view',
        {'view': const ['resultados', 'posiciones', 'pronosticos'][view]});
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      color: AppColors.accent,
      backgroundColor: AppColors.bgElev,
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, widget.topPadding, 20, 160),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppChip(
                label: 'NBA',
                active: _league == ScoresService.nba,
                onTap: () => _selectLeague(ScoresService.nba),
              ),
              AppChip(
                label: 'WNBA',
                active: _league == ScoresService.wnba,
                onTap: () => _selectLeague(ScoresService.wnba),
              ),
              AppChip(
                label: 'Liga Nacional',
                active: _league == ScoresService.lnb,
                onTap: () => _selectLeague(ScoresService.lnb),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!_hasData)
            _lnbCard()
          else ...[
            _viewToggle(),
            const SizedBox(height: 14),
            ...switch (_view) {
              1 => _standingsBody(),
              2 => _powerBody(),
              _ => _gamesBody(),
            },
          ],
        ],
      ),
    );
  }

  // ── Selector Resultados / Posiciones / Pronósticos ──────────────────────

  Widget _viewToggle() => ScoreTabs(
        items: const [
          (Icons.scoreboard_outlined, 'Resultados'),
          (Icons.format_list_numbered, 'Posiciones'),
          (Icons.insights, 'Pronósticos'),
        ],
        active: _view,
        onChange: _selectView,
      );

  Widget _spinner() => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppColors.white(0.4)),
        ),
      );

  Widget _empty(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Column(
          children: [
            Icon(icon, size: 44, color: AppColors.white(0.25)),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: AppText.grotesk(
                    size: 14,
                    weight: FontWeight.w700,
                    color: AppColors.white(0.6))),
          ],
        ),
      );

  // ── Resultados ──────────────────────────────────────────────────────────

  List<Widget> _gamesBody() {
    final games = ApiCache.peek<List<ScoreGame>>(_gamesKey) ?? const [];
    if (_loading && games.isEmpty) return [_spinner()];
    if (games.isEmpty) {
      return [
        _empty(Icons.sports_basketball_outlined,
            'No hubo partidos en el último mes.\nLa temporada está en receso.'),
      ];
    }
    final out = <Widget>[];
    String? lastDay;
    for (final g in games) {
      final day = _dayLabel(g.date);
      if (day != lastDay) {
        out.add(Padding(
          padding: EdgeInsets.only(bottom: 8, top: lastDay == null ? 0 : 10),
          child: Text(day.toUpperCase(),
              style: AppText.grotesk(
                  size: 10,
                  weight: FontWeight.w700,
                  color: AppColors.white(0.45),
                  letterSpacing: 0.1)),
        ));
        lastDay = day;
      }
      out.add(_gameCard(g));
    }
    return out;
  }

  /// "Hoy", "Ayer" o "Dom 02/11" (fecha local del usuario).
  String _dayLabel(DateTime? d) {
    if (d == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Hoy';
    if (diff == 1) return 'Ayer';
    if (diff == -1) return 'Mañana';
    const days = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    return '${days[d.weekday - 1]} ${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}';
  }

  String _time(DateTime? d) => d == null
      ? ''
      : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// Color del equipo, aclarado si es tan oscuro que no se ve sobre el fondo.
  Color _tc(ScoreTeam t, Color fallback) => readableTeamColor(t.color, fallback);

  Widget _gameCard(ScoreGame g) {
    final played = g.state != GameState.pre;
    final live = g.state == GameState.live;
    final ac = _tc(g.away, const Color(0xFF3B82F6));
    final hc = _tc(g.home, AppColors.accent);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PressableWidget(
        onTap: () => _openGame(g),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppShape.rCard),
            // Los colores de los dos equipos, apenas, de punta a punta.
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                ac.withValues(alpha: 0.22),
                AppColors.card,
                AppColors.card,
                hc.withValues(alpha: 0.22),
              ],
              stops: const [0, 0.35, 0.65, 1],
            ),
            border: Border.all(
                color: live
                    ? const Color(0xFFEF4444).withValues(alpha: 0.6)
                    : AppColors.white(0.05)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              Expanded(child: _teamSide(g.away, g, ac, alignEnd: false)),
              SizedBox(
                width: 92,
                child: Column(
                  children: [
                    if (played)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _score(g.away, g),
                          Text('  –  ',
                              style: AppText.grotesk(
                                  size: 14, color: AppColors.white(0.3))),
                          _score(g.home, g),
                        ],
                      )
                    else
                      Text(_time(g.date),
                          style: AppText.display(
                              size: 24, color: AppColors.ink)),
                    const SizedBox(height: 4),
                    if (live)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const LiveDot(size: 6),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(g.status,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.grotesk(
                                    size: 10,
                                    weight: FontWeight.w800,
                                    color: const Color(0xFFEF4444))),
                          ),
                        ],
                      )
                    else
                      Text(
                          g.state == GameState.post ? 'FINAL' : 'PRÓXIMO',
                          style: AppText.grotesk(
                              size: 9.5,
                              weight: FontWeight.w800,
                              color: AppColors.white(0.45),
                              letterSpacing: 0.12)),
                  ],
                ),
              ),
              Expanded(child: _teamSide(g.home, g, hc, alignEnd: true)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _score(ScoreTeam t, ScoreGame g) {
    final dim = g.state == GameState.post && !t.winner;
    return Text(t.score,
        style: AppText.display(
            size: 26, color: dim ? AppColors.white(0.4) : AppColors.ink));
  }

  /// Escudo con halo del color del equipo + sigla y récord.
  Widget _teamSide(ScoreTeam t, ScoreGame g, Color c, {required bool alignEnd}) {
    final dim = g.state == GameState.post && !t.winner;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.05),
            boxShadow: [
              BoxShadow(
                  color: c.withValues(alpha: dim ? 0.1 : 0.35),
                  blurRadius: 14),
            ],
          ),
          child: Opacity(
              opacity: dim ? 0.6 : 1, child: TeamLogo(url: t.logo, size: 34)),
        ),
        const SizedBox(height: 6),
        Text(t.abbr,
            style: AppText.archivo(
                size: 13,
                weight: FontWeight.w900,
                color: dim ? AppColors.white(0.5) : AppColors.ink)),
        if (t.record.isNotEmpty)
          Text(t.record,
              style: AppText.grotesk(size: 10, color: AppColors.white(0.4))),
      ],
    );
  }

  void _openGame(ScoreGame g) {
    AnalyticsService.event('game_open', {'league': _league});
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GameDetailScreen(league: _league, game: g),
    ));
  }

  // ── Posiciones ──────────────────────────────────────────────────────────

  List<Widget> _standingsBody() {
    final groups = ApiCache.peek<List<StandingGroup>>(_standingsKey) ?? const [];
    if (_loading && groups.isEmpty) return [_spinner()];
    if (groups.isEmpty) {
      return [_empty(Icons.leaderboard_outlined, 'Sin posiciones por ahora')];
    }
    final out = <Widget>[];
    for (final grp in groups) {
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(_groupName(grp.name).toUpperCase(),
            style: AppText.grotesk(
                size: 10,
                weight: FontWeight.w700,
                color: AppColors.accent,
                letterSpacing: 0.12)),
      ));
      out.add(Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppShape.rCard),
        ),
        child: Column(
          children: [
            _standingRow(null),
            for (final r in grp.rows) _standingRow(r),
          ],
        ),
      ));
    }
    out.add(_standingsLegend());
    return out;
  }

  String _groupName(String n) => switch (n) {
        'Eastern Conference' => 'Conferencia Este',
        'Western Conference' => 'Conferencia Oeste',
        _ => n,
      };

  /// Fila de la tabla; [r] null = encabezado. En NBA los 6 primeros van
  /// directo a playoffs y del 7 al 10 al play-in: se marcan con un filete.
  Widget _standingRow(StandingRow? r) {
    final head = r == null;
    final style = AppText.grotesk(
        size: head ? 9.5 : 12,
        weight: head ? FontWeight.w700 : FontWeight.w600,
        color: head ? AppColors.white(0.4) : AppColors.ink);
    Widget cell(String t, double w, {Color? color}) => SizedBox(
        width: w,
        child: Text(t,
            textAlign: TextAlign.right,
            style: color == null ? style : style.copyWith(color: color)));
    final nba = _league == ScoresService.nba;
    final zone = head
        ? null
        : nba
            ? (r.seed <= 6
                ? AppColors.open
                : r.seed <= 10
                    ? AppColors.busy
                    : null)
            : (r.seed <= 4 ? AppColors.open : null);
    final streakColor = head || r.streak.isEmpty
        ? null
        : r.streak.startsWith('W')
            ? AppColors.open
            : const Color(0xFFEF4444);
    final cutLine = !head && nba && (r.seed == 6 || r.seed == 10);
    final row = Container(
      padding: const EdgeInsets.fromLTRB(0, 9, 12, 9),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: cutLine
                  ? AppColors.white(0.22)
                  : AppColors.white(head ? 0.08 : 0.04),
              width: cutLine ? 1.2 : 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 20,
            margin: const EdgeInsets.only(right: 9),
            decoration: BoxDecoration(
              color: zone ?? Colors.transparent,
              borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(3)),
            ),
          ),
          SizedBox(
              width: 22,
              child: Text(head ? '#' : '${r.seed}',
                  style: style.copyWith(
                      color: zone ?? AppColors.white(0.45),
                      fontWeight: FontWeight.w800))),
          if (!head) ...[
            TeamLogo(url: r.logo, size: 22),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(head ? 'EQUIPO' : r.name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
          ),
          cell(head ? 'G-P' : '${r.wins}-${r.losses}', 46),
          cell(head ? '%' : r.pct, 40),
          cell(head ? 'DIF' : r.gamesBehind, 36),
          cell(head ? 'RACHA' : r.streak.replaceAll('W', 'G').replaceAll('L', 'P'),
              46,
              color: streakColor),
        ],
      ),
    );
    if (head || r.id.isEmpty) return row;
    return InkWell(onTap: () => _openTeam(r.id), child: row);
  }


  /// Referencias de color de la tabla (solo NBA tiene play-in).
  Widget _standingsLegend() {
    Widget item(Color c, String t) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text(t,
                style: AppText.grotesk(size: 10, color: AppColors.white(0.5))),
          ],
        );
    return Wrap(
      spacing: 14,
      children: [
        item(AppColors.open, 'Playoffs'),
        if (_league == ScoresService.nba) item(AppColors.busy, 'Play-in'),
      ],
    );
  }

  void _openTeam(String id) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TeamScreen(league: _league, teamId: id),
    ));
  }

  // ── Pronósticos (ESPN BPI) ──────────────────────────────────────────────

  List<Widget> _powerBody() {
    final rows = ApiCache.peek<List<PowerRow>>(_powerKey) ?? const [];
    if (_loading && rows.isEmpty) return [_spinner()];
    if (rows.isEmpty) {
      return [_empty(Icons.insights_outlined, 'Sin pronósticos por ahora')];
    }
    final head = AppText.grotesk(
        size: 9.5, weight: FontWeight.w700, color: AppColors.white(0.4));
    Widget pctCell(double v, Color c) => SizedBox(
          width: 54,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(fmtPct(v),
                  style: AppText.grotesk(size: 12, weight: FontWeight.w800)),
              const SizedBox(height: 3),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: SizedBox(
                  width: 44,
                  child: LinearProgressIndicator(
                    value: (v / 100).clamp(0, 1),
                    minHeight: 4,
                    backgroundColor: AppColors.white(0.08),
                    color: c,
                  ),
                ),
              ),
            ],
          ),
        );
    return [
      Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppShape.rCard),
        ),
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(width: 26, child: Text('#', style: head)),
                  Expanded(child: Text('EQUIPO', style: head)),
                  SizedBox(
                      width: 48,
                      child: Text('PROY.',
                          textAlign: TextAlign.right, style: head)),
                  SizedBox(
                      width: 54,
                      child: Text('PLAYOFFS',
                          textAlign: TextAlign.right, style: head)),
                  SizedBox(
                      width: 54,
                      child: Text('FINAL',
                          textAlign: TextAlign.right, style: head)),
                  SizedBox(
                      width: 54,
                      child: Text('CAMPEÓN',
                          textAlign: TextAlign.right, style: head)),
                ],
              ),
            ),
            for (final r in rows)
              InkWell(
                onTap: r.id.isEmpty ? null : () => _openTeam(r.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    border: Border(
                        top: BorderSide(color: AppColors.white(0.04))),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 26,
                        child: Text('${r.rank}',
                            style: AppText.archivo(
                                size: 12,
                                weight: FontWeight.w900,
                                color: r.rank <= 3
                                    ? AppColors.accent
                                    : AppColors.white(0.5))),
                      ),
                      TeamLogo(url: r.logo, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(r.abbr,
                            style: AppText.archivo(
                                size: 13, weight: FontWeight.w900)),
                      ),
                      SizedBox(
                        width: 48,
                        child: Text('${r.projW.round()}-${r.projL.round()}',
                            textAlign: TextAlign.right,
                            style: AppText.grotesk(
                                size: 12, color: AppColors.white(0.7))),
                      ),
                      pctCell(r.playoffs, AppColors.open),
                      pctCell(r.finals, AppColors.busy),
                      pctCell(r.title, AppColors.accent),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Proyección ESPN BPI: simula el resto de la temporada. "Proy." es el '
        'récord final esperado. Tocá un equipo para ver su detalle.',
        style: AppText.grotesk(size: 10, color: AppColors.white(0.4)),
      ),
    ];
  }

  // ── Liga Nacional ───────────────────────────────────────────────────────

  Widget _lnbCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppShape.rCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Liga Nacional',
              style: AppText.archivo(size: 16, weight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(
            'Todavía no tenemos los resultados de la Liga Nacional en la app. '
            'Podés ver el fixture, la tabla y las estadísticas en el sitio oficial.',
            style: AppText.grotesk(size: 13, color: AppColors.white(0.65)),
          ),
          const SizedBox(height: 14),
          PressableWidget(
            onTap: _openLnb,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(AppShape.rBtn),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Ver fixture oficial',
                      style: AppText.archivo(
                          size: 13,
                          weight: FontWeight.w800,
                          color: Colors.white)),
                  const SizedBox(width: 6),
                  const Icon(Icons.open_in_new, size: 15, color: Colors.white),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openLnb() async {
    try {
      await launchUrl(Uri.parse(ScoresService.lnbFixtureUrl),
          mode: LaunchMode.externalApplication);
      AnalyticsService.event('lnb_fixture_open');
    } catch (_) {/* sin browser disponible */}
  }
}

/// Color del equipo legible sobre el fondo oscuro de la app: si es muy
/// oscuro (p. ej. el azul marino de muchos equipos) se aclara.
Color readableTeamColor(String hex, Color fallback) {
  final c = teamColor(hex) ?? fallback;
  final hsl = HSLColor.fromColor(c);
  return hsl.lightness < 0.32 ? hsl.withLightness(0.45).toColor() : c;
}

/// Escudo del equipo (PNG de ESPN, cacheado en disco). Sin logo o si falla,
/// un círculo neutro del mismo tamaño para que las filas no salten.
class TeamLogo extends StatelessWidget {
  final String url;
  final double size;

  const TeamLogo({super.key, required this.url, this.size = 24});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      decoration:
          BoxDecoration(color: AppColors.white(0.08), shape: BoxShape.circle),
    );
    if (url.isEmpty) return placeholder;
    return CachedNetworkImage(
      imageUrl: url,
      width: size,
      height: size,
      fit: BoxFit.contain,
      placeholder: (_, _) => placeholder,
      errorWidget: (_, _, _) => placeholder,
    );
  }
}

/// Punto rojo que late: indicador de partido EN VIVO.
class LiveDot extends StatefulWidget {
  final double size;
  const LiveDot({super.key, this.size = 7});

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: const BoxDecoration(
              color: Color(0xFFEF4444), shape: BoxShape.circle),
        ),
      );
}

/// Selector de solapas de la sección Partidos (Resultados / Posiciones /
/// Pronósticos, Partido / Previa). Pill con ícono en cada opción y la activa
/// rellena en acento con halo: el subrayado anterior pasaba desapercibido.
class ScoreTabs extends StatelessWidget {
  final List<(IconData, String)> items;
  final int active;
  final ValueChanged<int> onChange;

  const ScoreTabs({
    super.key,
    required this.items,
    required this.active,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.bgElev,
        borderRadius: BorderRadius.circular(AppShape.rBtn),
        border: Border.all(color: AppColors.white(0.12)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChange(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: i == active ? AppColors.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppShape.rChip),
                    boxShadow: i == active
                        ? [
                            BoxShadow(
                              color: AppColors.accent.withValues(alpha: 0.45),
                              blurRadius: 14,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(items[i].$1,
                          size: 16,
                          color: i == active
                              ? Colors.white
                              : AppColors.white(0.55)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          items[i].$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.archivo(
                              size: 12.5,
                              weight: FontWeight.w800,
                              color: i == active
                                  ? Colors.white
                                  : AppColors.white(0.7)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
