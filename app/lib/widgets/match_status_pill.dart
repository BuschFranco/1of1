import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/play_session_service.dart';
import '../theme/app_fx.dart';
import '../theme/app_theme.dart';
import 'pressable_widget.dart';

/// Mini-píldora flotante con el estado del partido: sigue al usuario por toda
/// la app (fuera del mapa) mientras haya actividad (partido en curso o cuenta
/// regresiva). Reusa los mismos flags y colores que los banners del mapa —
/// única fuente de verdad: [PlaySessionService]. Tap → vuelve al mapa, donde
/// está el banner completo con sus controles.
class MatchStatusPill extends StatefulWidget {
  final VoidCallback onTap;
  const MatchStatusPill({super.key, required this.onTap});

  @override
  State<MatchStatusPill> createState() => _MatchStatusPillState();
}

class _MatchStatusPillState extends State<MatchStatusPill>
    with SingleTickerProviderStateMixin {
  // Pulso del puntito de estado (solo late mientras la píldora está visible).
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _syncPulse(bool active) {
    if (active && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!active && _pulse.isAnimating) {
      _pulse.stop();
    }
  }

  static String _mmss(int secs) =>
      '${(secs ~/ 60).toString().padLeft(2, '0')}:${(secs % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final ps = context.watch<PlaySessionService>();
    final active = ps.isPlaying || ps.isDwelling;
    _syncPulse(active);

    // Entrada/salida suave: baja desde arriba al activarse. Cuando no hay
    // actividad dejamos un hijo vacío para que la animación de salida corra.
    return AnimatedSlide(
      offset: active ? Offset.zero : const Offset(0, -0.6),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: active ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: !active ? const SizedBox(height: 0) : _pill(ps),
      ),
    );
  }

  Widget _pill(PlaySessionService ps) {
    // Mismos colores de estado que los banners del mapa (home_screen).
    final playing = ps.isPlaying;
    final paused = ps.isPaused;
    final Color accent = playing
        ? (paused ? AppColors.white(0.7) : AppColors.open)
        : AppColors.accent;

    final String time =
        _mmss(playing ? ps.elapsedSeconds : ps.dwellRemainingSeconds);
    final bool ending = playing && ps.isEndingSoon && !paused;
    final String label = !playing
        ? 'EMPIEZA EN'
        : paused
            ? 'PAUSADO'
            : ending
                ? 'SALE EN ${_mmss(ps.endRemainingSeconds)}'
                : 'EN JUEGO';
    final Color labelColor = ending ? AppColors.busy : AppColors.white(0.6);

    return PressableWidget(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 7, 14, 7),
        decoration: BoxDecoration(
          color: AppColors.glass,
          borderRadius: BorderRadius.circular(AppShape.rBtn),
          border: Border.all(color: accent, width: 1),
          boxShadow: AppFx.hardShadow(offset: const Offset(3, 3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (playing)
              // Puntito de estado pulsante (fijo si está pausado).
              FadeTransition(
                opacity: paused
                    ? const AlwaysStoppedAnimation(1.0)
                    : Tween(begin: 0.35, end: 1.0).animate(_pulse),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: accent, shape: BoxShape.circle),
                ),
              )
            else
              Icon(Icons.sports_basketball, size: 14, color: accent),
            const SizedBox(width: 8),
            Text(time,
                style: AppText.archivo(
                    size: 13, weight: FontWeight.w800, color: accent)),
            const SizedBox(width: 8),
            Text(label,
                style: AppText.grotesk(
                    size: 10,
                    weight: FontWeight.w700,
                    color: labelColor,
                    letterSpacing: 0.08)),
          ],
        ),
      ),
    );
  }
}
