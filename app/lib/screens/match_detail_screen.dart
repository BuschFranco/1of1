import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../data/achievements.dart';
import '../data/courts.dart';
import '../services/courts_provider.dart';
import '../services/play_session_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/court_image.dart';
import '../widgets/pressable_widget.dart';

class MatchDetailScreen extends StatelessWidget {
  final PlaySession session;
  final ValueChanged<String>? onSelectCourt;
  const MatchDetailScreen({super.key, required this.session, this.onSelectCourt});

  @override
  Widget build(BuildContext context) {
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
        Text('PUNTOS GANADOS',
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
    final pills = <Widget>[
      if (s.calories > 0)
        _healthPill(Icons.local_fire_department, '${s.calories.round()} kcal'),
      if (s.steps > 0) _healthPill(Icons.directions_walk, '${s.steps} pasos'),
      if (s.avgHr != null) _healthPill(Icons.favorite_border, '${s.avgHr} bpm'),
      if (s.distance > 0)
        _healthPill(
            Icons.straighten,
            s.distance >= 1000
                ? '${(s.distance / 1000).toStringAsFixed(2)} km'
                : '${s.distance.round()} m'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.monitor_heart_outlined, size: 13, color: AppColors.accent),
            const SizedBox(width: 6),
            Text('TU ESTADO',
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
        Wrap(spacing: 8, runSpacing: 8, children: pills),
      ],
    );
  }

  Widget _healthPill(IconData icon, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppShape.rChip),
        border: Border.all(color: AppColors.line, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.accent),
          const SizedBox(width: 6),
          Text(value,
              style: AppText.archivo(size: 13, weight: FontWeight.w800)),
        ],
      ),
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
              _shareStat('PUNTOS', s.points > 0 ? '+${s.points}' : '—',
                  color: s.points > 0 ? AppColors.accent : null),
            ],
          ),
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
                if (s.distance > 0)
                  _shareMiniStat(
                    Icons.straighten,
                    s.distance >= 1000
                        ? '${(s.distance / 1000).toStringAsFixed(1)} km'
                        : '${s.distance.round()} m',
                  ),
              ],
            ),
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

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
