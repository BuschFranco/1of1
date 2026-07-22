import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../services/play_session_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_chip.dart';
import '../widgets/pressable_widget.dart';

/// Pantalla desarrollada de estadísticas de juego (las que el usuario carga en
/// la encuesta post-partido). Se abre al tocar la card "Estadísticas de juego"
/// del perfil. Filtros de tiempo + gráficos de evolución para dar seguimiento y
/// persuadir a cargar la puntuación de cada partido.
enum _StatPeriod { week, month, season, total, custom }

// Colores del desglose (consistentes con el perfil).
const _c3 = Color(0xFF3B82F6); // 3PT azul
const _c2 = Color(0xFFA855F7); // 2PT violeta
const _cTl = Color(0xFFEAB308); // TL dorado

class GameStatsScreen extends StatefulWidget {
  const GameStatsScreen({super.key});

  @override
  State<GameStatsScreen> createState() => _GameStatsScreenState();
}

class _GameStatsScreenState extends State<GameStatsScreen> {
  // Orden de páginas swipeables (mismo criterio que el ranking del perfil).
  static const _order = <_StatPeriod>[
    _StatPeriod.week,
    _StatPeriod.month,
    _StatPeriod.season,
    _StatPeriod.total,
    _StatPeriod.custom,
  ];

  late final PageController _pageCtrl;
  int _page = 3; // arranca en "Total"
  DateTime? _customFrom;
  DateTime? _customTo;

  _StatPeriod get _period => _order[_page];

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(initialPage: _page);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _select(_StatPeriod p) {
    final target = _order.indexOf(p);
    if (target < 0) return;
    _pageCtrl.animateToPage(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  // ── Filtro por período ──────────────────────────────────────────────────

  DateTime _cutoff(_StatPeriod period) {
    final now = DateTime.now();
    switch (period) {
      case _StatPeriod.week:
        final monday = now.subtract(Duration(days: now.weekday - 1));
        return DateTime(monday.year, monday.month, monday.day);
      case _StatPeriod.month:
        return DateTime(now.year, now.month, 1);
      case _StatPeriod.season:
        // Temporada = semestre de calendario (fuente única en el service).
        return PlaySessionService.seasonStart(now);
      case _StatPeriod.total:
        return DateTime.fromMillisecondsSinceEpoch(0);
      case _StatPeriod.custom:
        return _customFrom ?? DateTime(now.year, now.month, 1);
    }
  }

  DateTime? _end(_StatPeriod period) =>
      period == _StatPeriod.custom ? _customTo : null;

  /// Partidos con puntuación cargada dentro del período, en orden cronológico
  /// (viejo → nuevo). `ps.log` viene más reciente primero, así que se invierte.
  List<PlaySession> _matches(PlaySessionService ps, _StatPeriod period) {
    final startMs = _cutoff(period).millisecondsSinceEpoch;
    final endMs = _end(period)?.millisecondsSinceEpoch;
    return ps.log
        .where((s) =>
            s.userPoints != null &&
            s.endedAtMillis >= startMs &&
            (endMs == null || s.endedAtMillis < endMs))
        .toList()
        .reversed
        .toList();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: now,
      initialDateRange: _customFrom != null && _customTo != null
          ? DateTimeRange(start: _customFrom!, end: _customTo!)
          : DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
      locale: const Locale('es', 'AR'),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.dark(
            primary: AppColors.accent,
            onPrimary: Colors.white,
            surface: AppColors.bgElev,
            onSurface: AppColors.ink,
          ),
          dialogTheme: DialogThemeData(backgroundColor: AppColors.bgElev),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _customFrom = picked.start;
        // Fin inclusivo: sumamos un día para que el rango sea [from, to+1día).
        _customTo = DateTime(
            picked.end.year, picked.end.month, picked.end.day + 1);
      });
      _select(_StatPeriod.custom);
    }
  }

  String get _customLabel {
    if (_customFrom == null || _customTo == null) return 'Rango';
    String d(DateTime x) => '${x.day}/${x.month}';
    // _customTo es exclusivo (+1 día); mostramos el último día real.
    final last = _customTo!.subtract(const Duration(days: 1));
    return '${d(_customFrom!)} - ${d(last)}';
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ps = context.watch<PlaySessionService>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header con back.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  _iconBtn(Icons.arrow_back, () => Navigator.pop(context)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Estadísticas de juego',
                        style: AppText.archivo(
                            size: 20, weight: FontWeight.w900)),
                  ),
                ],
              ),
            ),
            _filters(),
            const SizedBox(height: 8),
            // Páginas swipeables: una por período, sincronizadas con los chips.
            Expanded(
              child: PageView.builder(
                controller: _pageCtrl,
                itemCount: _order.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _periodPage(ps, _order[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _periodPage(PlaySessionService ps, _StatPeriod period) {
    if (period == _StatPeriod.custom && (_customFrom == null || _customTo == null)) {
      return _pickPrompt();
    }
    final matches = _matches(ps, period);
    if (matches.isEmpty) return _empty(period);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _summaryCard(matches),
        const SizedBox(height: 16),
        _evolutionCard(matches),
        const SizedBox(height: 16),
        _breakdownCard(matches),
        const SizedBox(height: 16),
        _shotsCard(matches),
      ],
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return PressableWidget(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.bgElev,
          borderRadius: BorderRadius.circular(AppShape.rBtn),
          border: Border.all(color: AppColors.white(0.25), width: 1.5),
        ),
        child: Icon(icon, color: AppColors.ink, size: 18),
      ),
    );
  }

  Widget _filters() {
    Widget chip(String label, _StatPeriod p) => AppChip(
          label: label,
          active: _period == p,
          onTap: () => _select(p),
        );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        chip('Semana', _StatPeriod.week),
        chip('Mes', _StatPeriod.month),
        chip('Temporada', _StatPeriod.season),
        chip('Total', _StatPeriod.total),
        AppChip(
          label: _customLabel,
          active: _period == _StatPeriod.custom,
          onTap: _pickCustomRange,
        ),
      ],
    );
  }

  // ── Tarjetas resumen ───────────────────────────────────────────────────

  Widget _summaryCard(List<PlaySession> matches) {
    final total = matches.fold(0, (s, m) => s + (m.userPoints ?? 0));
    final count = matches.length;
    final avg = count > 0 ? total / count : 0.0;
    final best = matches.fold(0, (m, s) =>
        (s.userPoints ?? 0) > m ? (s.userPoints ?? 0) : m);
    final withTime = matches.where((m) => m.seconds > 0);
    final ppm = withTime.isEmpty
        ? 0.0
        : withTime.fold<double>(
                0, (a, m) => a + (m.userPoints! / (m.seconds / 60))) /
            withTime.length;
    final madeShots = matches.fold(
        0,
        (s, m) =>
            s +
            (m.userTriples ?? 0) +
            (m.userDoubles ?? 0) +
            (m.userFreeThrows ?? 0));
    final perShot = madeShots > 0 ? total / madeShots : 0.0;

    final cells = <Widget>[
      _statCell('Puntos totales', '$total', Icons.score,
          const Color(0xFFFF6B1A)),
      _statCell('Prom. por partido', avg.toStringAsFixed(1), Icons.trending_up,
          const Color(0xFF22C55E)),
      _statCell('Mejor partido', '$best', Icons.emoji_events,
          const Color(0xFFEAB308)),
      _statCell('Partidos', '$count', Icons.event_available,
          const Color(0xFF64748B)),
      if (ppm > 0)
        _statCell('Puntos por min', ppm.toStringAsFixed(1), Icons.bolt,
            const Color(0xFFF97316)),
      if (perShot > 0)
        _statCell('Puntos por tiro', perShot.toStringAsFixed(1),
            Icons.my_location, const Color(0xFF14B8A6)),
    ];

    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 2) {
      if (rows.isNotEmpty) {
        rows.add(Container(height: 1, color: AppColors.white(0.06)));
      }
      if (i + 1 < cells.length) {
        rows.add(IntrinsicHeight(
          child: Row(children: [
            Expanded(child: cells[i]),
            Container(width: 1, color: AppColors.white(0.06)),
            Expanded(child: cells[i + 1]),
          ]),
        ));
      } else {
        rows.add(Row(children: [
          Expanded(child: cells[i]),
          const Expanded(child: SizedBox()),
        ]));
      }
    }

    return _card(child: Column(children: rows));
  }

  Widget _statCell(String label, String value, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.grotesk(
                        size: 9.5,
                        weight: FontWeight.w700,
                        color: AppColors.white(0.45),
                        letterSpacing: 0.1)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(value,
              style: AppText.archivo(
                  size: 20,
                  weight: FontWeight.w900,
                  height: 1.0,
                  color: AppColors.ink)),
        ],
      ),
    );
  }

  // ── Evolución de puntos ──────────────────────────────────────────────────

  Widget _evolutionCard(List<PlaySession> matches) {
    final spots = <FlSpot>[];
    for (var i = 0; i < matches.length; i++) {
      spots.add(FlSpot(i.toDouble(), (matches[i].userPoints ?? 0).toDouble()));
    }
    final maxY = spots.fold<double>(
        0, (m, s) => s.y > m ? s.y : m);
    final topY = (maxY <= 0 ? 10 : maxY * 1.2).ceilToDouble();

    return _card(
      header: 'EVOLUCIÓN DE TUS PUNTOS',
      subtitle: 'Puntos anotados en cada partido',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 18, 14, 10),
        child: SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: topY,
              minX: 0,
              maxX: (matches.length - 1).clamp(0, double.infinity).toDouble(),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: (topY / 4).clamp(1, double.infinity),
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: AppColors.white(0.06), strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                bottomTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: (topY / 4).clamp(1, double.infinity),
                    getTitlesWidget: (v, meta) => Text(
                      v.toInt().toString(),
                      style: AppText.grotesk(
                          size: 9, color: AppColors.white(0.35)),
                    ),
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.25,
                  color: AppColors.accent,
                  barWidth: 3,
                  dotData: FlDotData(
                    show: matches.length <= 20,
                    getDotPainter: (spot, percent, bar, index) =>
                        FlDotCirclePainter(
                            radius: 3,
                            color: AppColors.accent,
                            strokeWidth: 0),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: AppColors.accent.withAlpha(28),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── De dónde vienen los puntos (barra apilada) ────────────────────────────

  Widget _breakdownCard(List<PlaySession> matches) {
    final t3 = matches.fold(0, (s, m) => s + (m.userTriples ?? 0));
    final t2 = matches.fold(0, (s, m) => s + (m.userDoubles ?? 0));
    final tl = matches.fold(0, (s, m) => s + (m.userFreeThrows ?? 0));
    final pts3 = t3 * 3;
    final pts2 = t2 * 2;
    final ptsTl = tl;
    final total = pts3 + pts2 + ptsTl;
    if (total <= 0) return const SizedBox.shrink();
    int pct(int v) => (v / total * 100).round();

    Widget seg(int v, Color c) =>
        v > 0 ? Expanded(flex: v, child: Container(color: c)) : const SizedBox();
    Widget legend(Color c, String label, int v) {
      if (v <= 0) return const SizedBox.shrink();
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text('$label ${pct(v)}%',
              style: AppText.grotesk(
                  size: 11,
                  weight: FontWeight.w600,
                  color: AppColors.white(0.6))),
        ],
      );
    }

    return _card(
      header: 'DE DÓNDE VIENEN TUS PUNTOS',
      subtitle: 'Reparto de tu puntaje en el período',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                height: 14,
                child: Row(
                    children: [seg(pts3, _c3), seg(pts2, _c2), seg(ptsTl, _cTl)]),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                legend(_c3, '3PT', pts3),
                legend(_c2, '2PT', pts2),
                legend(_cTl, 'TL', ptsTl),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Triples / Dobles / TL por partido ─────────────────────────────────────

  Widget _shotsCard(List<PlaySession> matches) {
    // Últimos partidos (hasta 10) para que las barras se lean bien.
    final shown = matches.length > 10
        ? matches.sublist(matches.length - 10)
        : matches;
    final anyBreakdown = shown.any((m) =>
        (m.userTriples ?? 0) > 0 ||
        (m.userDoubles ?? 0) > 0 ||
        (m.userFreeThrows ?? 0) > 0);
    if (!anyBreakdown) return const SizedBox.shrink();

    double maxV = 0;
    for (final m in shown) {
      for (final v in [
        (m.userTriples ?? 0),
        (m.userDoubles ?? 0),
        (m.userFreeThrows ?? 0)
      ]) {
        if (v > maxV) maxV = v.toDouble();
      }
    }
    final topY = (maxV <= 0 ? 4 : maxV + 1).ceilToDouble();

    BarChartRodData rod(int v, Color c) => BarChartRodData(
          toY: v.toDouble(),
          color: c,
          width: 5,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
        );

    final groups = <BarChartGroupData>[];
    for (var i = 0; i < shown.length; i++) {
      final m = shown[i];
      groups.add(BarChartGroupData(
        x: i,
        barsSpace: 2,
        barRods: [
          rod(m.userTriples ?? 0, _c3),
          rod(m.userDoubles ?? 0, _c2),
          rod(m.userFreeThrows ?? 0, _cTl),
        ],
      ));
    }

    Widget legend(Color c, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text(label,
                style: AppText.grotesk(
                    size: 11,
                    weight: FontWeight.w600,
                    color: AppColors.white(0.6))),
          ],
        );

    return _card(
      header: 'TRIPLES, DOBLES Y TIROS LIBRES',
      subtitle: matches.length > 10
          ? 'Tus últimos 10 partidos'
          : 'Por partido en el período',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 16, 14, 12),
        child: Column(
          children: [
            SizedBox(
              height: 160,
              child: BarChart(
                BarChartData(
                  maxY: topY,
                  barGroups: groups,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: (topY / 4).clamp(1, double.infinity),
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: AppColors.white(0.06), strokeWidth: 1),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: (topY / 4).clamp(1, double.infinity),
                        getTitlesWidget: (v, meta) => Text(
                          v.toInt().toString(),
                          style: AppText.grotesk(
                              size: 9, color: AppColors.white(0.35)),
                        ),
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(enabled: false),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                legend(_c3, 'Triples'),
                legend(_c2, 'Dobles'),
                legend(_cTl, 'Tiros libres'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers de layout ──────────────────────────────────────────────────

  /// Card con estilo del perfil. [header]/[subtitle] opcionales arriba.
  Widget _card({Widget? child, String? header, String? subtitle}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppShape.rCard),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(header,
                      style: AppText.grotesk(
                          size: 11,
                          weight: FontWeight.w700,
                          color: AppColors.white(0.5),
                          letterSpacing: 0.1)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: AppText.grotesk(
                            size: 9, color: AppColors.white(0.3))),
                  ],
                ],
              ),
            ),
          ?child,
        ],
      ),
    );
  }

  Widget _empty(_StatPeriod period) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.query_stats,
                size: 46, color: AppColors.white(0.25)),
            const SizedBox(height: 16),
            Text('Todavía no hay datos',
                textAlign: TextAlign.center,
                style: AppText.archivo(size: 17, weight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              period == _StatPeriod.total
                  ? 'Cargá tu puntuación al terminar un partido y acá vas a ver tu evolución, de dónde vienen tus puntos y mucho más.'
                  : 'No cargaste puntuaciones en este período. Probá con otro filtro o cargá la puntuación en tu próximo partido.',
              textAlign: TextAlign.center,
              style: AppText.grotesk(
                  size: 12.5, color: AppColors.white(0.5), height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  /// Página del filtro "Rango" cuando todavía no se eligió un rango.
  Widget _pickPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.date_range,
                size: 46, color: AppColors.white(0.25)),
            const SizedBox(height: 16),
            Text('Elegí un rango de fechas',
                textAlign: TextAlign.center,
                style: AppText.archivo(size: 17, weight: FontWeight.w800)),
            const SizedBox(height: 14),
            AppChip(
              label: 'Elegir fechas',
              active: true,
              onTap: _pickCustomRange,
            ),
          ],
        ),
      ),
    );
  }
}
