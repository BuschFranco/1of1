import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Fondo neobrutalista reutilizable: base sólida y lisa (la grilla técnica no
/// convenció: el estilo lo llevan las cards con bordes y sombras duras, no el
/// fondo). Se monta DETRÁS del contenido y no captura toques.
///
/// Uso típico: envolver el body en un Stack con `Positioned.fill(child:
/// const PopBackground())` como primer hijo.
class PopBackground extends StatelessWidget {
  /// Se conserva por compatibilidad de call-sites; ya no hay nada que escalar.
  final double glowStrength;

  /// Color del fondo de la sección. Retro-pop: cada pantalla puede tener su
  /// propio color saturado (lila, sun, red, cream). Default: fondo base (crema).
  final Color? color;

  const PopBackground({super.key, this.glowStrength = 1, this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ColoredBox(
        color: color ?? AppColors.bg,
        child: const SizedBox.expand(),
      ),
    );
  }
}
