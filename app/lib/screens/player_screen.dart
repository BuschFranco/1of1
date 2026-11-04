import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../data/scores.dart';
import '../services/analytics_service.dart';
import '../services/cache/api_cache.dart';
import '../services/scores_service.dart';
import '../theme/app_theme.dart';
import 'games_screen.dart';
import 'team_screen.dart';

/// Perfil de un jugador de NBA / WNBA: datos, promedios de la temporada
/// (comparados con los de su carrera) y sus últimos partidos.
class PlayerScreen extends StatefulWidget {
  final String league;
  final String playerId;

  /// Para pintar algo mientras carga (vienen del box score).
  final String? name;
  final String? headshot;

  const PlayerScreen({
    super.key,
    required this.league,
    required this.playerId,
    this.name,
    this.headshot,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  bool _loading = false;

  String get _key => 'scores::player::${widget.league}::${widget.playerId}';

  @override
  void initState() {
    super.initState();
    AnalyticsService.event('player_open', {'league': widget.league});
    _load();
  }

  Future<void> _load({bool force = false}) async {
    if (!force && ApiCache.isFresh(_key, ApiCache.ttlScoreProfiles)) return;
    setState(() => _loading = true);
    final p = await ScoresService.player(widget.league, widget.playerId);
    if (p != null) ApiCache.put(_key, p);
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = ApiCache.peek<PlayerProfile>(_key);
    final color = readableTeamColor(p?.teamColor ?? '', AppColors.accent);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        onRefresh: () => _load(force: true),
        color: AppColors.accent,
        backgroundColor: AppColors.bgElev,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _hero(p, color),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              child: p == null
                  ? Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(
                        child: _loading
                            ? CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.white(0.4))
                            : Text('No pudimos cargar al jugador',
                                style: AppText.grotesk(
                                    size: 14,
                                    weight: FontWeight.w700,
                                    color: AppColors.white(0.6))),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (p.season != null) ...[
                          sectionLabel('PROMEDIOS DE LA TEMPORADA'),
                          const SizedBox(height: 8),
                          _averages(p.season!, p.career, color),
                          const SizedBox(height: 18),
                        ],
                        if (p.lastGames.isNotEmpty) ...[
                          sectionLabel('ÚLTIMOS PARTIDOS'),
                          const SizedBox(height: 8),
                          _lastGames(p.lastGames),
                          const SizedBox(height: 18),
                        ],
                        if (p.info.isNotEmpty) ...[
                          sectionLabel('FICHA'),
                          const SizedBox(height: 8),
                          _info(p.info),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero(PlayerProfile? p, Color color) {
    final headshot = p?.headshot ?? widget.headshot ?? '';
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.6), AppColors.bg],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back, color: AppColors.ink),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const SizedBox(width: 12),
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.white(0.06),
                      border: Border.all(color: color, width: 3),
                      boxShadow: [
                        BoxShadow(
                            color: color.withValues(alpha: 0.45),
                            blurRadius: 24),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: headshot.isEmpty
                        ? Icon(Icons.person,
                            size: 60, color: AppColors.white(0.3))
                        : CachedNetworkImage(
                            imageUrl: headshot,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            errorWidget: (_, _, _) => Icon(Icons.person,
                                size: 60, color: AppColors.white(0.3)),
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if ((p?.jersey ?? '').isNotEmpty)
                          Text('#${p!.jersey}',
                              style: AppText.display(
                                  size: 28,
                                  color: color.withValues(alpha: 0.9))),
                        Text(p?.name ?? widget.name ?? '',
                            style: AppText.display(
                                size: 26, color: AppColors.ink)),
                        const SizedBox(height: 4),
                        if (p != null)
                          GestureDetector(
                            onTap: p.teamId.isEmpty
                                ? null
                                : () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => TeamScreen(
                                            league: widget.league,
                                            teamId: p.teamId),
                                      ),
                                    ),
                            child: Row(
                              children: [
                                TeamLogo(url: p.teamLogo, size: 20),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    [p.teamName, p.position]
                                        .where((x) => x.isNotEmpty)
                                        .join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.grotesk(
                                        size: 12,
                                        weight: FontWeight.w700,
                                        color: AppColors.white(0.8)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// PTS/REB/AST grandes y el resto chico, cada uno con la diferencia contra
  /// su promedio de carrera (verde arriba, rojo abajo; en pérdidas al revés).
  Widget _averages(StatLine season, StatLine? career, Color color) {
    Widget big(String label, String key) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [color.withValues(alpha: 0.25), AppColors.card],
            ),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Text(season.of(key).isEmpty ? '—' : season.of(key),
                  style: AppText.display(size: 32, color: AppColors.ink)),
              Text(label,
                  style: AppText.grotesk(
                      size: 9.5,
                      weight: FontWeight.w800,
                      color: AppColors.white(0.55),
                      letterSpacing: 0.1)),
              const SizedBox(height: 4),
              _vsCareer(season.of(key), career?.of(key) ?? '', true),
            ],
          ),
        ),
      );
    }

    const small = [
      ('PJ', 'GP', true),
      ('MIN', 'MIN', true),
      ('TC%', 'FG%', true),
      ('3P%', '3P%', true),
      ('TL%', 'FT%', true),
      ('ROB', 'STL', true),
      ('TAP', 'BLK', true),
      ('PER', 'TO', false),
    ];
    return Column(
      children: [
        Row(
          children: [
            big('PUNTOS', 'PTS'),
            const SizedBox(width: 8),
            big('REBOTES', 'REB'),
            const SizedBox(width: 8),
            big('ASISTENCIAS', 'AST'),
          ],
        ),
        const SizedBox(height: 8),
        cardBox(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          child: Wrap(
            runSpacing: 12,
            children: [
              for (final (label, key, higher) in small)
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 44) / 4,
                  child: Column(
                    children: [
                      Text(season.of(key).isEmpty ? '—' : season.of(key),
                          style: AppText.archivo(
                              size: 17, weight: FontWeight.w900)),
                      Text(label,
                          style: AppText.grotesk(
                              size: 9.5,
                              weight: FontWeight.w700,
                              color: AppColors.white(0.45))),
                      if (key != 'GP')
                        _vsCareer(season.of(key), career?.of(key) ?? '', higher),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (career != null) ...[
          const SizedBox(height: 6),
          Text('Flechas: comparado con su promedio de carrera',
              style: AppText.grotesk(size: 10, color: AppColors.white(0.4))),
        ],
      ],
    );
  }

  Widget _vsCareer(String now, String career, bool higherIsBetter) {
    final a = double.tryParse(now);
    final b = double.tryParse(career);
    if (a == null || b == null) return const SizedBox(height: 14);
    final diff = a - b;
    if (diff.abs() < 0.05) {
      return Text('= carrera',
          style: AppText.grotesk(size: 9.5, color: AppColors.white(0.35)));
    }
    final good = higherIsBetter ? diff > 0 : diff < 0;
    final c = good ? AppColors.open : const Color(0xFFEF4444);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(diff > 0 ? Icons.arrow_drop_up : Icons.arrow_drop_down,
            size: 16, color: c),
        Text(diff.abs().toStringAsFixed(1),
            style: AppText.grotesk(
                size: 10, weight: FontWeight.w700, color: c)),
      ],
    );
  }

  Widget _lastGames(List<PlayerGame> games) {
    TextStyle head = AppText.grotesk(
        size: 9.5, weight: FontWeight.w700, color: AppColors.white(0.4));
    TextStyle cell = AppText.grotesk(size: 12, weight: FontWeight.w600);
    Widget c(String t, double w, TextStyle st) =>
        SizedBox(width: w, child: Text(t, textAlign: TextAlign.center, style: st));
    return cardBox(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 92),
              c('MIN', 38, head),
              c('PTS', 38, head),
              c('REB', 38, head),
              c('AST', 38, head),
              Expanded(child: c('TC%', 38, head)),
            ],
          ),
          for (final g in games)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  SizedBox(
                    width: 92,
                    child: Row(
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: g.result == 'W'
                                ? AppColors.open
                                : const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(g.result == 'W' ? 'G' : 'P',
                              style: AppText.archivo(
                                  size: 10,
                                  weight: FontWeight.w900,
                                  color: Colors.white)),
                        ),
                        const SizedBox(width: 6),
                        Text(g.atVs == '@' ? '@' : 'vs',
                            style: AppText.grotesk(
                                size: 10, color: AppColors.white(0.45))),
                        const SizedBox(width: 3),
                        TeamLogo(url: g.oppLogo, size: 16),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(g.opp,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.archivo(
                                  size: 11, weight: FontWeight.w800)),
                        ),
                      ],
                    ),
                  ),
                  c(g.stats.of('MIN'), 38, cell),
                  c(g.stats.of('PTS'), 38,
                      cell.copyWith(fontWeight: FontWeight.w900)),
                  c(g.stats.of('REB'), 38, cell),
                  c(g.stats.of('AST'), 38, cell),
                  Expanded(child: c(g.stats.of('FG%'), 38, cell)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _info(List<(String, String)> info) => cardBox(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          children: [
            for (final (label, value) in info)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Text(label,
                        style: AppText.grotesk(
                            size: 12, color: AppColors.white(0.5))),
                    const Spacer(),
                    Flexible(
                      child: Text(value,
                          textAlign: TextAlign.right,
                          style: AppText.grotesk(
                              size: 12, weight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}

/// Etiqueta de sección en acento (mismo estilo en partido, jugador y equipo).
Widget sectionLabel(String t) => Text(t,
    style: AppText.grotesk(
        size: 10,
        weight: FontWeight.w800,
        color: AppColors.accent,
        letterSpacing: 0.14));

/// Card base de la sección Partidos.
Widget cardBox({required Widget child, EdgeInsets? padding}) => Container(
      padding: padding ?? const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppShape.rCard),
        border: Border.all(color: AppColors.white(0.05)),
      ),
      child: child,
    );
