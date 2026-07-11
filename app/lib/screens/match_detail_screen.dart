import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../data/achievements.dart';
import '../data/courts.dart';
import '../services/court_rating_service.dart';
import '../services/courts_provider.dart';
import '../services/play_session_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/court_image.dart';
import '../widgets/pressable_widget.dart';
import '../widgets/rating_badge.dart';

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
                        const SizedBox(height: 12),
                        // Cancha.
                        _courtHeader(court, s),
                        const SizedBox(height: 28),
                        // Resultado grande.
                        _resultBadge(color, label),
                        const SizedBox(height: 28),
                        // Stats principales.
                        _mainStats(s),
                        const SizedBox(height: 16),
                        // Fecha y hora.
                        _dateStats(ended),
                        // Salud.
                        if (s.hasHealth) ...[
                          const SizedBox(height: 28),
                          _healthSection(s),
                        ],
                        const SizedBox(height: 32),
                        // Brand footer.
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

  Widget _courtHeader(Court? court, PlaySession s) {
    return Column(
      children: [
        CourtImage(
          url: court?.img ?? '',
          width: 80,
          height: 80,
          borderRadius: BorderRadius.circular(AppShape.rCard),
        ),
        const SizedBox(height: 14),
        Text(
          court?.name ?? (s.courtName.isEmpty ? 'Cancha' : s.courtName),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppText.archivo(size: 22, weight: FontWeight.w900),
        ),
        if (court != null && (court.area.isNotEmpty || court.type.isNotEmpty)) ...[
          const SizedBox(height: 4),
          Text(
            court.area.isEmpty ? court.type : '${court.area} · ${court.type}',
            style: AppText.grotesk(size: 13, color: AppColors.white(0.5)),
          ),
        ],
        if (court != null) ...[
          const SizedBox(height: 8),
          Builder(builder: (context) {
            final rs = context.read<CourtRatingService>();
            return FutureBuilder<CourtRating>(
              future: rs.ratingFor(court.id),
              builder: (context, snap) {
                final cr = snap.data;
                return RatingBadge(value: cr?.average, size: 12);
              },
            );
          }),
        ],
      ],
    );
  }

  Widget _resultBadge(Color color, String label) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(AppShape.rCard),
        border: Border.all(color: color.withAlpha(100), width: 2),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: AppText.archivo(size: 28, weight: FontWeight.w900, color: color),
      ),
    );
  }

  Widget _mainStats(PlaySession s) {
    return Row(
      children: [
        Expanded(child: _bigStat(Icons.schedule, 'Duración', PlaySessionService.fmt(s.seconds))),
        const SizedBox(width: 12),
        Expanded(
          child: _bigStat(
            Icons.stars_rounded,
            'Puntos',
            s.points > 0 ? '+${s.points}' : '—',
            valueColor: s.points > 0 ? AppColors.accent : null,
          ),
        ),
      ],
    );
  }

  Widget _dateStats(DateTime ended) {
    return Row(
      children: [
        Expanded(child: _bigStat(Icons.calendar_today, 'Fecha', _fmtDate(ended))),
        const SizedBox(width: 12),
        Expanded(
          child: _bigStat(
            Icons.access_time_filled,
            'Hora',
            '${ended.hour.toString().padLeft(2, '0')}:${ended.minute.toString().padLeft(2, '0')}',
          ),
        ),
      ],
    );
  }

  Widget _bigStat(IconData icon, String label, String value, {Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.all(16),
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
              Icon(icon, size: 14, color: AppColors.white(0.4)),
              const SizedBox(width: 6),
              Text(label.toUpperCase(),
                  style: AppText.grotesk(
                      size: 10,
                      weight: FontWeight.w700,
                      color: AppColors.white(0.4),
                      letterSpacing: 0.08)),
            ],
          ),
          const SizedBox(height: 10),
          Text(value,
              style: AppText.archivo(
                  size: 22,
                  weight: FontWeight.w900,
                  color: valueColor ?? AppColors.ink)),
        ],
      ),
    );
  }

  Widget _healthSection(PlaySession s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.monitor_heart_outlined, size: 14, color: AppColors.accent),
            const SizedBox(width: 6),
            Text('TU ESTADO',
                style: AppText.grotesk(
                    size: 11,
                    weight: FontWeight.w700,
                    color: AppColors.white(0.5),
                    letterSpacing: 0.1)),
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
                    Icon(Icons.bolt, size: 12, color: kGold),
                    const SizedBox(width: 3),
                    Text('RÉCORD',
                        style: AppText.grotesk(
                            size: 9, weight: FontWeight.w800, color: kGold)),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        if (s.calories > 0 || s.steps > 0)
          Row(
            children: [
              if (s.calories > 0)
                Expanded(child: _healthStat(Icons.local_fire_department, 'Calorías', '${s.calories.round()} kcal')),
              if (s.calories > 0 && s.steps > 0) const SizedBox(width: 10),
              if (s.steps > 0)
                Expanded(child: _healthStat(Icons.directions_walk, 'Pasos', '${s.steps}')),
            ],
          ),
        if (s.avgHr != null || s.distance > 0) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              if (s.avgHr != null)
                Expanded(child: _healthStat(Icons.monitor_heart_outlined, 'Pulso', '${s.avgHr} bpm')),
              if (s.avgHr != null && s.distance > 0) const SizedBox(width: 10),
              if (s.distance > 0)
                Expanded(
                  child: _healthStat(
                    Icons.straighten,
                    'Distancia',
                    s.distance >= 1000
                        ? '${(s.distance / 1000).toStringAsFixed(2)} km'
                        : '${s.distance.round()} m',
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _healthStat(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppShape.rBtn),
        border: Border.all(color: AppColors.line, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: AppColors.white(0.4)),
              const SizedBox(width: 4),
              Text(label.toUpperCase(),
                  style: AppText.grotesk(
                      size: 9, color: AppColors.white(0.4), letterSpacing: 0.06)),
            ],
          ),
          const SizedBox(height: 6),
          Text(value, style: AppText.archivo(size: 15, weight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _brandFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
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
    );
  }

  Widget _shareButton(BuildContext context) {
    return PressableWidget(
      onTap: () => _captureAndShare(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(AppShape.rBtn),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.camera_alt_outlined, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Text('COMPARTIR RESULTADO',
                style: AppText.archivo(
                    size: 13, weight: FontWeight.w800, letterSpacing: 0.04)),
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
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppShape.rBtn),
          border: Border.all(color: AppColors.line, width: 1),
        ),
        child: Text('Ver cancha',
            textAlign: TextAlign.center,
            style: AppText.grotesk(
                size: 13, weight: FontWeight.w600, color: AppColors.white(0.7))),
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

    // Crear un overlay temporal para capturar.
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        width: 1080,
        height: 1920,
        child: Material(
          color: Colors.transparent,
          child: _ShareCard(
            key: key,
            session: s,
            court: court,
            color: color,
            label: label,
            ended: ended,
          ),
        ),
      ),
    );
    overlay.insert(entry);

    // Esperar a que se renderice.
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final buffer = byteData!.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/match_result.png');
      await file.writeAsBytes(buffer);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: '¡Resultado en 1of1! 🏀',
      );
    } catch (_) {}

    entry.remove();
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
    super.key,
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
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Brand.
          Text('1of1',
              style: AppText.archivo(size: 48, weight: FontWeight.w900, color: AppColors.accent)),
          const SizedBox(height: 80),
          // Resultado.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
            decoration: BoxDecoration(
              color: color.withAlpha(25),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: color.withAlpha(100), width: 3),
            ),
            child: Text(label,
                style: AppText.archivo(
                    size: 52, weight: FontWeight.w900, color: color)),
          ),
          const SizedBox(height: 60),
          // Cancha.
          Text(
            court?.name ?? (s.courtName.isEmpty ? 'Cancha' : s.courtName),
            textAlign: TextAlign.center,
            style: AppText.archivo(size: 36, weight: FontWeight.w800),
          ),
          if (court != null && court!.area.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(court!.area,
                style: AppText.grotesk(size: 24, color: AppColors.white(0.5))),
          ],
          const SizedBox(height: 60),
          // Stats.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _shareStat('DURACIÓN', PlaySessionService.fmt(s.seconds)),
              Container(
                width: 2,
                height: 60,
                margin: const EdgeInsets.symmetric(horizontal: 40),
                color: AppColors.white(0.15),
              ),
              _shareStat('PUNTOS', s.points > 0 ? '+${s.points}' : '—'),
            ],
          ),
          const SizedBox(height: 40),
          // Fecha.
          Text(
            '${_fmtDate(ended)} · ${ended.hour.toString().padLeft(2, '0')}:${ended.minute.toString().padLeft(2, '0')}',
            style: AppText.grotesk(size: 22, color: AppColors.white(0.4)),
          ),
          // Salud.
          if (s.hasHealth) ...[
            const SizedBox(height: 50),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (s.calories > 0)
                  _shareMiniStat(Icons.local_fire_department, '${s.calories.round()} kcal'),
                if (s.calories > 0 && s.distance > 0) const SizedBox(width: 40),
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
          // CTA.
          Text('Jugá en 1of1',
              style: AppText.grotesk(
                  size: 22, color: AppColors.white(0.3), letterSpacing: 0.1)),
        ],
      ),
    );
  }

  Widget _shareStat(String label, String value) {
    return Column(
      children: [
        Text(value,
            style: AppText.archivo(size: 44, weight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text(label,
            style: AppText.grotesk(
                size: 16,
                color: AppColors.white(0.4),
                letterSpacing: 0.1)),
      ],
    );
  }

  Widget _shareMiniStat(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: AppColors.white(0.4)),
        const SizedBox(width: 8),
        Text(text,
            style: AppText.grotesk(size: 20, color: AppColors.white(0.5))),
      ],
    );
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
