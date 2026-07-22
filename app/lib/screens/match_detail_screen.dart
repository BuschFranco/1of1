import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import '../data/achievements.dart';
import '../data/courts.dart';
import '../services/courts_provider.dart';
import '../services/play_session_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/court_image.dart';
import '../widgets/pressable_widget.dart';

class MatchDetailScreen extends StatefulWidget {
  final PlaySession session;
  final ValueChanged<String>? onSelectCourt;
  const MatchDetailScreen({super.key, required this.session, this.onSelectCourt});

  @override
  State<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends State<MatchDetailScreen> {
  ValueChanged<String>? get onSelectCourt => widget.onSelectCourt;

  /// Versión más fresca del partido: si la re-lectura de salud actualizó el
  /// historial (los datos del reloj llegan tarde a Health Connect), usamos esa
  /// entrada; si no, el snapshot recibido.
  PlaySession get session {
    for (final e in context.read<PlaySessionService>().log) {
      if (e.endedAtMillis == widget.session.endedAtMillis &&
          e.courtId == widget.session.courtId) {
        return e;
      }
    }
    return widget.session;
  }

  @override
  void initState() {
    super.initState();
    // Partido sin datos de salud: reintentar la lectura ahora (Health Connect
    // puede haber sincronizado el reloj después de resolverse el resultado).
    unawaited(
        context.read<PlaySessionService>().refreshHealthFor(widget.session));
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild cuando la re-lectura de salud actualiza el historial.
    context.watch<PlaySessionService>();
    final s = session;
    final courts = context.read<CourtsProvider>().courts;
    Court? court;
    for (final c in courts) {
      if (c.id == s.courtId) {
        court = c;
        break;
      }
    }
    final (color, label) = _resultStyle(s.result);
    final ended = DateTime.fromMillisecondsSinceEpoch(s.endedAtMillis);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Gradient sutil de fondo.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.bg, Color(0xFF0D0D0D), AppColors.bg],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // AppBar custom.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      PressableWidget(
                        onTap: () => Navigator.pop(context),
                        child: const SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(Icons.arrow_back_ios_new, size: 20),
                        ),
                      ),
                      const Spacer(),
                      Text('Resumen',
                          style: AppText.grotesk(
                              size: 14, weight: FontWeight.w600, color: AppColors.white(0.6))),
                      const Spacer(),
                      const SizedBox(width: 44),
                    ],
                  ),
                ),
                // Contenido scrollable.
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: Column(
                      children: [
                        const SizedBox(height: 4),
                        // Hero: imagen de la cancha con el resultado y el nombre.
                        _heroBanner(court, s, color, label),
                        const SizedBox(height: 22),
                        // Puntos protagonista.
                        _pointsHero(s),
                        const SizedBox(height: 22),
                        // Franja de stats (duración · fecha · hora).
                        _statStrip(s, ended),
                        // Lo que anotó el usuario (total + desglose 3PT/2PT/TL).
                        if (s.hasUserStats) ...[
                          const SizedBox(height: 22),
                          _userStatsSection(s),
                        ],
                        // Salud (todas las métricas disponibles).
                        if (s.hasHealth) ...[
                          const SizedBox(height: 22),
                          _healthStrip(s),
                        ],
                        const SizedBox(height: 24),
                        _brandFooter(),
                      ],
                    ),
                  ),
                ),
                // Botones inferiores.
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      24, 0, 24, 16 + MediaQuery.of(context).viewPadding.bottom),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _shareButton(context),
                      const SizedBox(height: 10),
                      if (court != null) _courtButton(context, court),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Hero: imagen de la cancha a ancho completo con degradado; el resultado como
  /// chip arriba-izquierda y el nombre/zona sobre la imagen abajo.
  Widget _heroBanner(Court? court, PlaySession s, Color color, String label) {
    final name = court?.name ?? (s.courtName.isEmpty ? 'Cancha' : s.courtName);
    final sub = court == null
        ? ''
        : (court.area.isEmpty ? court.type : '${court.area} · ${court.type}');
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppShape.rCard),
      child: Stack(
        children: [
          CourtImage(
            url: court?.img ?? '',
            width: double.infinity,
            height: 172,
            borderRadius: BorderRadius.zero,
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withAlpha(40),
                    Colors.black.withAlpha(200),
                  ],
                  stops: const [0.35, 1.0],
                ),
              ),
            ),
          ),
          // Resultado: plano y editorial (misma directiva que la story),
          // barrita de acento a la izquierda; el scrim ya da contraste.
          Positioned(
            top: 14,
            left: 16,
            child: Row(
              children: [
                Container(width: 4, height: 14, color: color),
                const SizedBox(width: 8),
                Text(label,
                    style: AppText.archivo(
                        size: 12,
                        weight: FontWeight.w900,
                        color: color,
                        letterSpacing: 0.2)),
              ],
            ),
          ),
          // Nombre + zona.
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.archivo(
                        size: 24, weight: FontWeight.w900, color: Colors.white)),
                if (sub.isNotEmpty)
                  Text(sub,
                      style: AppText.grotesk(
                          size: 12.5, color: Colors.white.withAlpha(200))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Puntos protagonista del partido.
  Widget _pointsHero(PlaySession s) {
    final has = s.points > 0;
    return Column(
      children: [
        Text(has ? '+${s.points}' : '—',
            style: AppText.archivo(
                size: 46,
                weight: FontWeight.w900,
                height: 1.0,
                color: has ? AppColors.accent : AppColors.white(0.4))),
        const SizedBox(height: 2),
        Text('EXP GANADA',
            style: AppText.grotesk(
                size: 10.5,
                weight: FontWeight.w700,
                color: AppColors.white(0.4),
                letterSpacing: 0.14)),
      ],
    );
  }

  /// Franja única con duración · fecha · hora, separadas por líneas finas.
  Widget _statStrip(PlaySession s, DateTime ended) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppShape.rCard),
        border: Border.all(color: AppColors.line, width: 1),
      ),
      child: Row(
        children: [
          Expanded(child: _inlineStat('DURACIÓN', PlaySessionService.fmt(s.seconds))),
          _vDivider(),
          Expanded(child: _inlineStat('FECHA', _fmtDate(ended))),
          _vDivider(),
          Expanded(
              child: _inlineStat('HORA',
                  '${ended.hour.toString().padLeft(2, '0')}:${ended.minute.toString().padLeft(2, '0')}')),
        ],
      ),
    );
  }

  Widget _vDivider() =>
      Container(width: 1, height: 30, color: AppColors.white(0.1));

  /// Lo que anotó el usuario en "¿Cómo te fue?": total de puntos + desglose
  /// 3PT/2PT/TL. Distinto de los "PUNTOS GANADOS" que otorga la app.
  Widget _userStatsSection(PlaySession s) {
    final pts = s.userPoints ?? 0;
    // Métricas desde la fuente única (compartida con la imagen, no se desincroniza).
    final items = _userStatItems(s);

    // Filas de "planilla": etiqueta a la izquierda, valor a la derecha, con una
    // línea fina entre cada una. Texto plano, sin cajas ni divisores verticales.
    final lines = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) {
        lines.add(Divider(height: 1, thickness: 1, color: AppColors.white(0.05)));
      }
      lines.add(_statLine(items[i].label, items[i].value));
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppShape.rCard),
        border: Border.all(color: AppColors.line, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sports_basketball, size: 13, color: AppColors.accent),
              const SizedBox(width: 6),
              Text('PUNTUACIÓN',
                  style: AppText.grotesk(
                      size: 10.5,
                      weight: FontWeight.w700,
                      color: AppColors.white(0.5),
                      letterSpacing: 0.12)),
              if (pts > 0) ...[
                const Spacer(),
                Text('$pts',
                    style: AppText.archivo(
                        size: 22,
                        weight: FontWeight.w900,
                        color: AppColors.accent)),
                const SizedBox(width: 5),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text('PTS',
                      style: AppText.grotesk(
                          size: 10,
                          weight: FontWeight.w700,
                          color: AppColors.white(0.4))),
                ),
              ],
            ],
          ),
          if (lines.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...lines,
          ],
        ],
      ),
    );
  }

  /// Fila de planilla: nombre de la métrica a la izquierda (tenue), valor a la
  /// derecha (blanco, destacado). Lectura tipo lista, no columnas apretadas.
  Widget _statLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: AppText.grotesk(
                    size: 13,
                    weight: FontWeight.w600,
                    color: AppColors.white(0.6))),
          ),
          Text(value,
              style: AppText.archivo(size: 17, weight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _inlineStat(String label, String value) {
    return Column(
      children: [
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.archivo(size: 16, weight: FontWeight.w900)),
        const SizedBox(height: 3),
        Text(label,
            style: AppText.grotesk(
                size: 9,
                weight: FontWeight.w700,
                color: AppColors.white(0.4),
                letterSpacing: 0.1)),
      ],
    );
  }

  /// "Tu estado": todas las métricas de salud disponibles, como chips.
  Widget _healthStrip(PlaySession s) {
    // Métricas planas con color por tipo (sin cajas grises). Solo las que tienen
    // dato: lo que esté en 0/null no aparece.
    final metrics = <Widget>[
      if (s.calories > 0)
        _healthMetric(Icons.local_fire_department, const Color(0xFFFF6B1A),
            '${s.calories.round()}', 'kcal'),
      if (s.steps > 0)
        _healthMetric(Icons.directions_walk, const Color(0xFF22C55E),
            '${s.steps}', 'pasos'),
      if (s.avgHr != null)
        _healthMetric(
            Icons.favorite, const Color(0xFFEF4444), '${s.avgHr}', 'bpm'),
      if (s.maxHr != null && s.maxHr! > 0)
        _healthMetric(
            Icons.monitor_heart, const Color(0xFFF43F5E), '${s.maxHr}', 'máx'),
      if (s.distance > 0)
        _healthMetric(
            Icons.straighten,
            const Color(0xFF3B82F6),
            s.distance >= 1000
                ? (s.distance / 1000).toStringAsFixed(2)
                : '${s.distance.round()}',
            s.distance >= 1000 ? 'km' : 'm'),
      if (s.calories > 0 && s.seconds > 0)
        _healthMetric(Icons.whatshot, const Color(0xFFF97316),
            (s.calories / (s.seconds / 60)).toStringAsFixed(1), 'kcal/min'),
      if (s.steps > 0 && s.seconds > 0)
        _healthMetric(Icons.speed, const Color(0xFF10B981),
            '${(s.steps / (s.seconds / 60)).round()}', 'pasos/min'),
    ];
    final hasZones = s.hrZones != null &&
        s.hrZones!.any((z) => z > 0);
    final calorieRecord = context.read<PlaySessionService>().calorieRecord;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.monitor_heart_outlined, size: 13, color: AppColors.accent),
            const SizedBox(width: 6),
            Text('ESTADO',
                style: AppText.grotesk(
                    size: 10.5,
                    weight: FontWeight.w700,
                    color: AppColors.white(0.5),
                    letterSpacing: 0.12)),
            if (s.calorieRecord) ...[
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: kGold.withAlpha(38),
                  borderRadius: BorderRadius.circular(AppShape.rChip),
                  border: Border.all(color: kGold),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt, size: 11, color: kGold),
                    const SizedBox(width: 3),
                    Text('RÉCORD',
                        style: AppText.grotesk(
                            size: 8.5, weight: FontWeight.w800, color: kGold)),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        // Donut de zonas cardíacas + gauge de calorías (si hay datos).
        if (hasZones || s.calories > 0) ...[
          Row(
            children: [
              if (hasZones) Expanded(child: _hrZoneDonut(s.hrZones!)),
              if (hasZones && s.calories > 0) const SizedBox(width: 16),
              if (s.calories > 0)
                Expanded(
                    child: _calorieGauge(s.calories, calorieRecord)),
            ],
          ),
          const SizedBox(height: 12),
        ],
        Wrap(spacing: 22, runSpacing: 14, children: metrics),
      ],
    );
  }

  /// Donut chart de zonas cardíacas: muestra distribución de intensidad.
  static const _zoneColors = [
    Color(0xFF22C55E), // Calentamiento (verde)
    Color(0xFFEAB308), // Quema de grasa (amarillo)
    Color(0xFFF97316), // Cardio (naranja)
    Color(0xFFEF4444), // Pico (rojo)
    Color(0xFF991B1B), // Máximo (rojo oscuro)
  ];
  static const _zoneLabels = ['Calentamiento', 'Quema', 'Cardio', 'Pico', 'Máximo'];

  Widget _hrZoneDonut(List<int> zones) {
    final total = zones.fold(0, (s, z) => s + z);
    if (total == 0) return const SizedBox.shrink();

    final sections = List.generate(5, (i) {
      final pct = zones[i] / total * 100;
      return PieChartSectionData(
        value: zones[i].toDouble(),
        color: _zoneColors[i],
        radius: 14,
        title: pct >= 8 ? '${pct.round()}%' : '',
        titleStyle: AppText.grotesk(
            size: 9, weight: FontWeight.w700, color: Colors.white),
        titlePositionPercentageOffset: 0.55,
      );
    });

    return Column(
      children: [
        SizedBox(
          height: 100,
          child: PieChart(
            PieChartData(
              sections: sections,
              centerSpaceRadius: 28,
              sectionsSpace: 1,
            ),
          ),
        ),
        const SizedBox(height: 6),
        // Leyenda compacta
        Wrap(
          spacing: 8,
          runSpacing: 2,
          children: List.generate(5, (i) {
            if (zones[i] == 0) return const SizedBox.shrink();
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                        color: _zoneColors[i], shape: BoxShape.circle)),
                const SizedBox(width: 3),
                Text(_zoneLabels[i],
                    style: AppText.grotesk(
                        size: 8, color: AppColors.white(0.5))),
              ],
            );
          }),
        ),
      ],
    );
  }

  /// Gauge de calorías: arco que muestra calorías vs récord personal.
  Widget _calorieGauge(double calories, double record) {
    final pct = record > 0 ? (calories / record).clamp(0.0, 1.0) : 0.0;
    final color = pct >= 1.0
        ? kGold
        : (pct >= 0.7
            ? AppColors.accent
            : AppColors.white(0.4));

    return Column(
      children: [
        SizedBox(
          height: 100,
          width: 100,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                height: 80,
                width: 80,
                child: CircularProgressIndicator(
                  value: pct > 0 ? pct : 0.001,
                  strokeWidth: 8,
                  backgroundColor: AppColors.white(0.08),
                  valueColor: AlwaysStoppedAnimation(color),
                  strokeCap: StrokeCap.round,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${calories.round()}',
                      style: AppText.archivo(
                          size: 22,
                          weight: FontWeight.w900,
                          color: color)),
                  Text('kcal',
                      style: AppText.grotesk(
                          size: 9, color: AppColors.white(0.4))),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(record > 0 ? 'Récord: ${record.round()}' : 'Sin récord',
            style: AppText.grotesk(size: 8, color: AppColors.white(0.4))),
      ],
    );
  }

  /// Métrica de salud plana (sin caja): ícono a color + valor + unidad chica.
  Widget _healthMetric(IconData icon, Color color, String value, String unit) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(value,
            style: AppText.archivo(
                size: 17, weight: FontWeight.w900, color: AppColors.ink)),
        const SizedBox(width: 3),
        Padding(
          padding: const EdgeInsets.only(bottom: 1),
          child: Text(unit,
              style: AppText.grotesk(size: 10, color: AppColors.white(0.4))),
        ),
      ],
    );
  }

  Widget _brandFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 24,
                height: 2,
                decoration: BoxDecoration(
                  color: AppColors.white(0.15),
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
              const SizedBox(width: 10),
              const AppLogo(height: 22),
              const SizedBox(width: 10),
              Container(
                width: 24,
                height: 2,
                decoration: BoxDecoration(
                  color: AppColors.white(0.15),
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Estadísticas provistas por 1of1',
              style: AppText.grotesk(
                  size: 9.5,
                  weight: FontWeight.w500,
                  color: AppColors.white(0.3),
                  letterSpacing: 0.06)),
        ],
      ),
    );
  }

  Widget _shareButton(BuildContext context) {
    return PressableWidget(
      onTap: () => _captureAndShare(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(AppShape.rBtn),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.camera_alt_outlined, size: 16, color: AppColors.ink),
            const SizedBox(width: 8),
            Text('COMPARTIR RESULTADO',
                style: AppText.archivo(
                    size: 12,
                    weight: FontWeight.w800,
                    letterSpacing: 0.04,
                    color: AppColors.ink)),
          ],
        ),
      ),
    );
  }

  Widget _courtButton(BuildContext context, Court court) {
    return PressableWidget(
      onTap: () {
        Navigator.pop(context);
        onSelectCourt?.call(court.id);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppShape.rBtn),
          border: Border.all(color: AppColors.line, width: 1),
        ),
        child: Text('Ver cancha',
            textAlign: TextAlign.center,
            style: AppText.grotesk(
                size: 12.5, weight: FontWeight.w600, color: AppColors.white(0.7))),
      ),
    );
  }

  Future<void> _captureAndShare(BuildContext context) async {
    // Crear un widget replicable para captura.
    final key = GlobalKey();
    final s = session;
    final courts = context.read<CourtsProvider>().courts;
    Court? court;
    for (final c in courts) {
      if (c.id == s.courtId) {
        court = c;
        break;
      }
    }
    final (color, label) = _resultStyle(s.result);
    final ended = DateTime.fromMillisecondsSinceEpoch(s.endedAtMillis);

    // Overlay temporal FUERA de pantalla (left: -3000) para renderizar la
    // tarjeta 1080×1920 sin que el usuario la vea. El RepaintBoundary con [key]
    // es lo que se captura (antes faltaba y el cast a RenderRepaintBoundary
    // tiraba, con lo que el compartir fallaba en silencio).
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        left: -3000,
        top: 0,
        child: Material(
          color: Colors.transparent,
          child: RepaintBoundary(
            key: key,
            child: _ShareCard(
              session: s,
              court: court,
              color: color,
              label: label,
              ended: ended,
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);

    // Esperar a que se renderice (dos frames para asegurar el layout).
    await Future.delayed(const Duration(milliseconds: 250));

    try {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      // La tarjeta ya es 1080×1920: pixelRatio 1 alcanza para una story nítida.
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final buffer = byteData!.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/match_result.png');
      await file.writeAsBytes(buffer);

      entry.remove();

      await Share.shareXFiles(
        [XFile(file.path)],
        text: '¡Resultado en 1of1! 🏀',
      );
    } catch (e) {
      entry.remove();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo generar la imagen para compartir.',
                style: AppText.grotesk(size: 13)),
            backgroundColor: AppColors.bgElev,
          ),
        );
      }
    }
  }

  static (Color, String) _resultStyle(PlayResult? r) {
    switch (r) {
      case PlayResult.win:
        return (AppColors.open, 'VICTORIA');
      case PlayResult.loss:
        return (AppColors.accentDark, 'DERROTA');
      case PlayResult.tie:
        return (AppColors.white(0.7), 'EMPATE');
      case PlayResult.training:
        return (AppColors.accent, 'ENTRENAMIENTO');
      case PlayResult.notCounted:
      case null:
        return (AppColors.white(0.4), 'SIN INFO');
    }
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

/// Métricas derivadas de lo que anotó el usuario (desglose 3PT/2PT/TL + canastas
/// de campo + puntos por minuto). FUENTE ÚNICA: la usan tanto el registro en
/// pantalla como la imagen de compartir, así las dos SIEMPRE muestran lo mismo.
List<({String label, String value})> _userStatItems(PlaySession s) {
  final pts = s.userPoints ?? 0;
  final t3 = s.userTriples ?? 0;
  final t2 = s.userDoubles ?? 0;
  final tl = s.userFreeThrows ?? 0;
  final fieldGoals = t3 + t2;
  final madeShots = t3 + t2 + tl;
  final ppm = (pts > 0 && s.seconds > 0) ? pts / (s.seconds / 60) : null;
  // Puntos por tiro anotado (eficiencia) y qué parte del puntaje vino de triples.
  final perShot = (pts > 0 && madeShots > 0) ? pts / madeShots : null;
  final threeShare = (pts > 0 && t3 > 0) ? (t3 * 3 / pts * 100).round() : null;
  return [
    if (t3 > 0) (label: 'Triples', value: '$t3'),
    if (t2 > 0) (label: 'Dobles', value: '$t2'),
    if (tl > 0) (label: 'Tiros libres', value: '$tl'),
    if (fieldGoals > 0) (label: 'Canastas', value: '$fieldGoals'),
    if (madeShots > 0) (label: 'Tiros anotados', value: '$madeShots'),
    if (ppm != null) (label: 'Puntos por minuto', value: ppm.toStringAsFixed(1)),
    if (perShot != null)
      (label: 'Puntos por tiro', value: perShot.toStringAsFixed(1)),
    if (threeShare != null) (label: 'Puntaje en triples', value: '$threeShare%'),
  ];
}

/// Widget optimizado para captura como imagen (9:16, Instagram Stories).
class _ShareCard extends StatelessWidget {
  final PlaySession session;
  final Court? court;
  final Color color;
  final String label;
  final DateTime ended;

  const _ShareCard({
    required this.session,
    required this.court,
    required this.color,
    required this.label,
    required this.ended,
  });

  @override
  Widget build(BuildContext context) {
    final s = session;
    return Container(
      width: 1080,
      height: 1920,
      padding: const EdgeInsets.all(80),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A0A0A), Color(0xFF111111), Color(0xFF0A0A0A)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 24),
          const AppLogo(height: 150),
          const Spacer(),
          // Resultado: plano y editorial (sin globo), barrita de acento arriba.
          Container(width: 56, height: 5, color: color),
          const SizedBox(height: 22),
          Text(label,
              style: AppText.archivo(
                  size: 36,
                  weight: FontWeight.w900,
                  color: color,
                  letterSpacing: 0.25)),
          const SizedBox(height: 40),
          // Cancha.
          Text(
            court?.name ?? (s.courtName.isEmpty ? 'Cancha' : s.courtName),
            textAlign: TextAlign.center,
            style: AppText.archivo(
                size: 64, weight: FontWeight.w900, height: 1.05),
          ),
          if (court != null && court!.area.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(court!.area,
                style: AppText.grotesk(size: 28, color: AppColors.white(0.5))),
          ],
          // Exterior/Interior: mismo dato que ya se muestra en el detalle de
          // cancha (court.type), acá como chip con ícono para la imagen.
          if (court != null && court!.type.isNotEmpty) ...[
            const SizedBox(height: 16),
            _shareTypeBadge(court!.type),
          ],
          const SizedBox(height: 24),
          Text(
            '${_fmtDate(ended)} · ${ended.hour.toString().padLeft(2, '0')}:${ended.minute.toString().padLeft(2, '0')}',
            style: AppText.grotesk(size: 26, color: AppColors.white(0.4)),
          ),
          const SizedBox(height: 80),
          // Stats principales.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _shareStat('DURACIÓN', PlaySessionService.fmt(s.seconds)),
              _shareDivider(),
              _shareStat('EXP', s.points > 0 ? '+${s.points}' : '—',
                  color: s.points > 0 ? AppColors.accent : null),
            ],
          ),
          // Stats del usuario: total anotado (número grande) + el desglose como
          // planilla de texto plano (mismas métricas y valores que el registro).
          if (s.hasUserStats) ...[
            const SizedBox(height: 56),
            if ((s.userPoints ?? 0) > 0) ...[
              Text('${s.userPoints}',
                  style: AppText.archivo(
                      size: 128,
                      weight: FontWeight.w900,
                      color: AppColors.accent,
                      height: 0.95)),
              Text('PUNTOS ANOTADOS',
                  style: AppText.grotesk(
                      size: 24,
                      weight: FontWeight.w700,
                      color: AppColors.white(0.4),
                      letterSpacing: 0.14)),
              const SizedBox(height: 40),
            ],
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                children: [
                  for (final it in _userStatItems(s))
                    _shareStatLine(it.label, it.value),
                ],
              ),
            ),
          ],
          // Salud: todas las métricas disponibles.
          if (s.hasHealth) ...[
            const SizedBox(height: 72),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 52,
              runSpacing: 36,
              children: [
                if (s.calories > 0)
                  _shareMiniStat(Icons.local_fire_department, '${s.calories.round()} kcal'),
                if (s.steps > 0)
                  _shareMiniStat(Icons.directions_walk, '${s.steps} pasos'),
                if (s.avgHr != null)
                  _shareMiniStat(Icons.favorite_border, '${s.avgHr} bpm'),
                if (s.maxHr != null && s.maxHr! > 0)
                  _shareMiniStat(Icons.monitor_heart, '${s.maxHr} máx'),
                if (s.distance > 0)
                  _shareMiniStat(
                    Icons.straighten,
                    s.distance >= 1000
                        ? '${(s.distance / 1000).toStringAsFixed(1)} km'
                        : '${s.distance.round()} m',
                  ),
                if (s.calories > 0 && s.seconds > 0)
                  _shareMiniStat(Icons.whatshot,
                      '${(s.calories / (s.seconds / 60)).toStringAsFixed(1)} kcal/min'),
                if (s.steps > 0 && s.seconds > 0)
                  _shareMiniStat(Icons.speed,
                      '${(s.steps / (s.seconds / 60)).round()} pasos/min'),
              ],
            ),
            // Mini barra de zonas cardíacas.
            if (s.hrZones != null && s.hrZones!.any((z) => z > 0)) ...[
              const SizedBox(height: 48),
              _shareZoneBar(s.hrZones!),
            ],
          ],
          const Spacer(),
          // Disclaimer de origen de datos.
          Text('Estadísticas del partido provistas por 1of1',
              textAlign: TextAlign.center,
              style: AppText.grotesk(
                  size: 20,
                  weight: FontWeight.w500,
                  color: AppColors.white(0.3),
                  letterSpacing: 0.06)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Chip con el tipo de cancha (Exterior/Interior/lo que sea que traiga el
  /// backend) para la imagen de compartir. Ícono de sol para exterior, techo
  /// para cualquier otro valor (interior u otros que se agreguen a futuro).
  Widget _shareTypeBadge(String type) {
    final isOutdoor = type.toLowerCase() == 'exterior';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.white(0.06),
        borderRadius: BorderRadius.circular(AppShape.rChip),
        border: Border.all(color: AppColors.white(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isOutdoor ? Icons.wb_sunny_outlined : Icons.home_outlined,
              size: 26, color: AppColors.white(0.7)),
          const SizedBox(width: 10),
          Text(type.toUpperCase(),
              style: AppText.grotesk(
                  size: 24,
                  weight: FontWeight.w700,
                  color: AppColors.white(0.7),
                  letterSpacing: 0.08)),
        ],
      ),
    );
  }

  Widget _shareDivider() => Container(
        width: 2,
        height: 90,
        margin: const EdgeInsets.symmetric(horizontal: 52),
        color: AppColors.white(0.15),
      );

  Widget _shareStat(String label, String value, {Color? color}) {
    return Column(
      children: [
        Text(value,
            style: AppText.archivo(
                size: 78, weight: FontWeight.w900, color: color ?? Colors.white)),
        const SizedBox(height: 10),
        Text(label,
            style: AppText.grotesk(
                size: 22,
                weight: FontWeight.w700,
                color: AppColors.white(0.4),
                letterSpacing: 0.1)),
      ],
    );
  }

  /// Fila de planilla para la imagen: métrica a la izquierda, valor a la
  /// derecha, con una línea fina debajo. Mismo estilo que el registro en app.
  Widget _shareStatLine(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.white(0.08))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: AppText.grotesk(
                    size: 30,
                    weight: FontWeight.w600,
                    color: AppColors.white(0.6))),
          ),
          Text(value,
              style: AppText.archivo(
                  size: 44, weight: FontWeight.w900, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _shareMiniStat(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 36, color: AppColors.accent),
        const SizedBox(width: 14),
        Text(text,
            style: AppText.archivo(
                size: 34, weight: FontWeight.w800, color: Colors.white)),
      ],
    );
  }

  /// Mini barra horizontal de zonas cardíacas para la share card.
  static const _zoneColors = [
    Color(0xFF22C55E),
    Color(0xFFEAB308),
    Color(0xFFF97316),
    Color(0xFFEF4444),
    Color(0xFF991B1B),
  ];

  Widget _shareZoneBar(List<int> zones) {
    final total = zones.fold(0, (s, z) => s + z);
    if (total == 0) return const SizedBox.shrink();
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 20,
            child: Row(
              children: List.generate(5, (i) {
                final pct = zones[i] / total;
                if (pct <= 0) return const SizedBox.shrink();
                return Expanded(
                  flex: (pct * 1000).round(),
                  child: Container(color: _zoneColors[i]),
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (i) {
            if (zones[i] == 0) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: _zoneColors[i], shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text(_zoneLabels[i],
                      style: AppText.grotesk(
                          size: 16, color: AppColors.white(0.5))),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }

  static const _zoneLabels = ['Calentamiento', 'Quema', 'Cardio', 'Pico', 'Máximo'];

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
