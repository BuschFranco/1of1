import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../data/scores.dart';
import '../services/analytics_service.dart';
import '../services/cache/api_cache.dart';
import '../services/scores_service.dart';
import '../theme/app_theme.dart';
import 'games_screen.dart';
import 'player_screen.dart';

/// Perfil de un equipo de NBA / WNBA: récord y posición, pronóstico de la
/// temporada (ESPN BPI), promedios y el plantel con los promedios de cada uno.
class TeamScreen extends StatefulWidget {
  final String league;
  final String teamId;

  const TeamScreen({super.key, required this.league, required this.teamId});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  bool _loading = false;

  String get _key => 'scores::team::${widget.league}::${widget.teamId}';

  @override
  void initState() {
    super.initState();
    AnalyticsService.event('team_open', {'league': widget.league});
    _load();
  }

  Future<void> _load({bool force = false}) async {
    if (!force && ApiCache.isFresh(_key, ApiCache.ttlScoreProfiles)) return;
    setState(() => _loading = true);
    final t = await ScoresService.team(widget.league, widget.teamId);
    if (t != null) ApiCache.put(_key, t);
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = ApiCache.peek<TeamProfile>(_key);
    final color = readableTeamColor(t?.color ?? '', AppColors.accent);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        onRefresh: () => _load(force: true),
        color: AppColors.accent,
        backgroundColor: AppColors.bgElev,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _hero(t, color),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              child: t == null
                  ? Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(
                        child: _loading
                            ? CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.white(0.4))
                            : Text('No pudimos cargar el equipo',
                                style: AppText.grotesk(
                                    size: 14,
                                    weight: FontWeight.w700,
                                    color: AppColors.white(0.6))),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (t.power != null) ...[
                          sectionLabel('PRONÓSTICO DE LA TEMPORADA'),
                          const SizedBox(height: 8),
                          _power(t.power!, color),
                          const SizedBox(height: 18),
                        ],
                        if (t.averages.isNotEmpty) ...[
                          sectionLabel('PROMEDIOS POR PARTIDO'),
                          const SizedBox(height: 8),
                          _averages(t.averages),
                          const SizedBox(height: 18),
                        ],
                        if (t.roster.isNotEmpty) ...[
                          sectionLabel('PLANTEL'),
                          const SizedBox(height: 8),
                          _roster(t.roster, color),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero(TeamProfile? t, Color color) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.65), AppColors.bg],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 22),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, color: AppColors.ink),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                  boxShadow: [
                    BoxShadow(
                        color: color.withValues(alpha: 0.45), blurRadius: 26),
                  ],
                ),
                child: TeamLogo(url: t?.logo ?? '', size: 84),
              ),
              const SizedBox(height: 10),
              Text(t?.name ?? '',
                  textAlign: TextAlign.center,
                  style: AppText.display(size: 28, color: AppColors.ink)),
              const SizedBox(height: 4),
              if (t != null)
                Text(
                  [t.record, t.standing].where((x) => x.isNotEmpty).join(' · '),
                  style: AppText.grotesk(
                      size: 12,
                      weight: FontWeight.w700,
                      color: AppColors.white(0.75)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _power(PowerRow p, Color color) {
    Widget meter(String label, double pct) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: 112,
                child: Text(label,
                    style: AppText.grotesk(
                        size: 12, color: AppColors.white(0.7))),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: (pct / 100).clamp(0, 1),
                    minHeight: 8,
                    backgroundColor: AppColors.white(0.08),
                    color: color,
                  ),
                ),
              ),
              SizedBox(
                width: 52,
                child: Text(fmtPct(pct),
                    textAlign: TextAlign.right,
                    style: AppText.archivo(size: 13, weight: FontWeight.w900)),
              ),
            ],
          ),
        );

    return cardBox(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _bigStat('#${p.rank}', 'POWER RANKING'),
              _bigStat('${p.projW.round()}-${p.projL.round()}', 'RÉCORD PROYECTADO'),
              _bigStat(p.bpi.toStringAsFixed(1), 'BPI'),
            ],
          ),
          const SizedBox(height: 10),
          meter('Playoffs', p.playoffs),
          if (widget.league == ScoresService.nba) meter('Play-in', p.playIn),
          meter('Llegar a la final', p.finals),
          meter('Campeón', p.title),
          const SizedBox(height: 4),
          Text('Proyección ESPN BPI (simula el resto de la temporada).',
              style: AppText.grotesk(size: 10, color: AppColors.white(0.4))),
        ],
      ),
    );
  }

  Widget _bigStat(String value, String label) => Expanded(
        child: Column(
          children: [
            Text(value, style: AppText.display(size: 24, color: AppColors.ink)),
            Text(label,
                textAlign: TextAlign.center,
                style: AppText.grotesk(
                    size: 9,
                    weight: FontWeight.w800,
                    color: AppColors.white(0.45),
                    letterSpacing: 0.08)),
          ],
        ),
      );

  Widget _averages(List<(String, String)> avgs) => cardBox(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        child: Wrap(
          runSpacing: 14,
          children: [
            for (final (label, value) in avgs)
              SizedBox(
                width: (MediaQuery.of(context).size.width - 44) / 3,
                child: Column(
                  children: [
                    Text(value,
                        style:
                            AppText.archivo(size: 18, weight: FontWeight.w900)),
                    Text(label,
                        textAlign: TextAlign.center,
                        style: AppText.grotesk(
                            size: 10, color: AppColors.white(0.5))),
                  ],
                ),
              ),
          ],
        ),
      );

  Widget _roster(List<RosterPlayer> roster, Color color) {
    final head = AppText.grotesk(
        size: 9.5, weight: FontWeight.w700, color: AppColors.white(0.4));
    Widget c(String t, TextStyle st) =>
        SizedBox(width: 40, child: Text(t, textAlign: TextAlign.center, style: st));
    return cardBox(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(child: SizedBox()),
              c('PTS', head),
              c('REB', head),
              c('AST', head),
              c('MIN', head),
            ],
          ),
          for (final p in roster)
            InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PlayerScreen(
                  league: widget.league,
                  playerId: p.id,
                  name: p.name,
                  headshot: p.headshot,
                ),
              )),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.white(0.06),
                        border:
                            Border.all(color: color.withValues(alpha: 0.6)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: p.headshot.isEmpty
                          ? Icon(Icons.person,
                              size: 20, color: AppColors.white(0.3))
                          : CachedNetworkImage(
                              imageUrl: p.headshot,
                              fit: BoxFit.cover,
                              alignment: Alignment.topCenter,
                              errorWidget: (_, _, _) => Icon(Icons.person,
                                  size: 20, color: AppColors.white(0.3)),
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.grotesk(
                                  size: 13, weight: FontWeight.w700)),
                          Text(
                            [if (p.jersey.isNotEmpty) '#${p.jersey}', p.position]
                                .where((x) => x.isNotEmpty)
                                .join(' · '),
                            style: AppText.grotesk(
                                size: 10, color: AppColors.white(0.45)),
                          ),
                        ],
                      ),
                    ),
                    c(p.pts.isEmpty ? '—' : p.pts,
                        AppText.archivo(size: 13, weight: FontWeight.w900)),
                    c(p.reb.isEmpty ? '—' : p.reb, AppText.grotesk(size: 12)),
                    c(p.ast.isEmpty ? '—' : p.ast, AppText.grotesk(size: 12)),
                    c(p.min.isEmpty ? '—' : p.min,
                        AppText.grotesk(size: 12, color: AppColors.white(0.6))),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 99.98 → "99,9%"; 0.04 → "<0,1%"; 4.8 → "4,8%".
String fmtPct(double v) {
  if (v <= 0) return '0%';
  if (v < 0.1) return '<0,1%';
  if (v >= 99.95) return '>99,9%';
  return '${v.toStringAsFixed(v >= 10 ? 0 : 1).replaceAll('.', ',')}%';
}
