import 'package:flutter/material.dart';
import '../data/scores.dart';
import '../services/cache/api_cache.dart';
import '../services/scores_service.dart';
import '../theme/app_theme.dart';
import 'games_screen.dart';

/// Box score de un partido de NBA / WNBA: marcador arriba y, por equipo, la
/// planilla de cada jugador (titulares, suplentes y los que no jugaron). La
/// tabla scrollea en horizontal con el nombre fijo a la izquierda.
class GameDetailScreen extends StatefulWidget {
  final String league;
  final ScoreGame game;

  const GameDetailScreen({super.key, required this.league, required this.game});

  @override
  State<GameDetailScreen> createState() => _GameDetailScreenState();
}

class _GameDetailScreenState extends State<GameDetailScreen> {
  bool _loading = false;

  /// 0 = visitante, 1 = local (mismo orden que la card del listado).
  int _team = 0;

  String get _key => 'scores::box::${widget.league}::${widget.game.id}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    if (!force && ApiCache.isFresh(_key, ApiCache.ttlScores)) return;
    setState(() => _loading = true);
    final box = await ScoresService.boxScore(widget.league, widget.game.id);
    if (box != null) ApiCache.put(_key, box);
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final box = ApiCache.peek<BoxScore>(_key);
    final g = box?.game ?? widget.game;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _load(force: true),
          color: AppColors.accent,
          backgroundColor: AppColors.bgElev,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.arrow_back, color: AppColors.ink),
                  ),
                  const SizedBox(width: 4),
                  Text(widget.league.toUpperCase(),
                      style: AppText.archivo(size: 18, weight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 8),
              _scoreHeader(g),
              const SizedBox(height: 18),
              if (box == null && _loading)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.white(0.4)),
                  ),
                )
              else if (box == null || box.teams.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 30),
                  child: Text('Sin estadísticas de este partido por ahora',
                      textAlign: TextAlign.center,
                      style: AppText.grotesk(
                          size: 14,
                          weight: FontWeight.w700,
                          color: AppColors.white(0.6))),
                )
              else ...[
                _teamPicker(box, g),
                const SizedBox(height: 12),
                _table(box, _teamFor(box, g)),
                const SizedBox(height: 10),
                Text(
                  'TC: tiros de campo · 3P: triples · TL: tiros libres · '
                  'ROB: robos · TAP: tapas · PER: pérdidas',
                  style: AppText.grotesk(size: 10, color: AppColors.white(0.4)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Equipo del box score que corresponde al selector (por sigla; si no
  /// coincide, por posición).
  BoxTeam _teamFor(BoxScore box, ScoreGame g) {
    final abbr = _team == 0 ? g.away.abbr : g.home.abbr;
    for (final t in box.teams) {
      if (t.abbr == abbr) return t;
    }
    return box.teams[_team.clamp(0, box.teams.length - 1)];
  }

  Widget _scoreHeader(ScoreGame g) {
    Widget side(ScoreTeam t) {
      final dim = g.state == GameState.post && !t.winner;
      return Expanded(
        child: Column(
          children: [
            TeamLogo(url: t.logo, size: 48),
            const SizedBox(height: 6),
            Text(t.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: AppText.grotesk(
                    size: 12,
                    weight: FontWeight.w700,
                    color: dim ? AppColors.white(0.5) : AppColors.ink)),
            const SizedBox(height: 4),
            Text(t.score,
                style: AppText.display(
                    size: 34,
                    color: dim ? AppColors.white(0.5) : AppColors.ink)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppShape.rCard),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          side(g.away),
          Padding(
            padding: const EdgeInsets.only(top: 60),
            child: Text(g.state == GameState.post ? 'Final' : g.status,
                style: AppText.grotesk(
                    size: 11,
                    weight: FontWeight.w700,
                    color: g.state == GameState.live
                        ? const Color(0xFFEF4444)
                        : AppColors.white(0.5))),
          ),
          side(g.home),
        ],
      ),
    );
  }

  Widget _teamPicker(BoxScore box, ScoreGame g) {
    Widget opt(int i, ScoreTeam t) {
      final active = _team == i;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _team = i),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: active ? AppColors.accent : AppColors.card,
              borderRadius: BorderRadius.circular(AppShape.rChip),
            ),
            child: Text(t.abbr.isEmpty ? t.name : t.abbr,
                textAlign: TextAlign.center,
                style: AppText.archivo(
                    size: 13,
                    weight: FontWeight.w800,
                    color: active ? Colors.white : AppColors.white(0.7))),
          ),
        ),
      );
    }

    return Row(children: [
      opt(0, g.away),
      const SizedBox(width: 8),
      opt(1, g.home),
    ]);
  }

  Widget _table(BoxScore box, BoxTeam team) {
    const nameW = 132.0;
    const colW = 44.0;
    final starters = team.players.where((p) => p.starter && !p.dnp).toList();
    final bench = team.players.where((p) => !p.starter && !p.dnp).toList();
    final dnp = team.players.where((p) => p.dnp).toList();

    TextStyle st({bool head = false, bool bold = false}) => AppText.grotesk(
        size: head ? 9.5 : 12,
        weight: head || bold ? FontWeight.w700 : FontWeight.w500,
        color: head ? AppColors.white(0.4) : AppColors.ink);

    Widget nameCell(BoxPlayer? p, {String? label}) => SizedBox(
          width: nameW,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: label != null
                ? Text(label, style: st(head: true))
                : Row(
                    children: [
                      Flexible(
                        child: Text(p!.name,
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
        );

    Widget statsRow(List<String> values, {bool head = false}) => Row(
          children: [
            for (var i = 0; i < box.columns.length; i++)
              SizedBox(
                width: colW,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(i < values.length ? values[i] : '',
                      textAlign: TextAlign.center,
                      // PTS (columna 1) resaltada: es lo primero que se busca.
                      style: head
                          ? st(head: true)
                          : (i == 1 ? st(bold: true) : st())),
                ),
              ),
          ],
        );

    // Filas: encabezado, titulares, "Suplentes", suplentes, "No jugaron".
    final names = <Widget>[nameCell(null, label: 'TITULARES')];
    final stats = <Widget>[statsRow(box.columns, head: true)];
    void divider(String label) {
      names.add(nameCell(null, label: label));
      stats.add(statsRow(const [], head: true));
    }

    for (final p in starters) {
      names.add(nameCell(p));
      stats.add(statsRow(p.stats));
    }
    if (bench.isNotEmpty) {
      divider('SUPLENTES');
      for (final p in bench) {
        names.add(nameCell(p));
        stats.add(statsRow(p.stats));
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppShape.rCard),
      ),
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
          if (dnp.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
              child: Text(
                'No jugaron: ${dnp.map((p) => p.name).join(', ')}',
                style: AppText.grotesk(size: 11, color: AppColors.white(0.45)),
              ),
            ),
        ],
      ),
    );
  }
}
