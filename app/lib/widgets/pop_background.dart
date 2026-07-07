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

  const PopBackground({super.key, this.glowStrength = 1});

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: ColoredBox(color: AppColors.bg, child: SizedBox.expand()),
    );
  }
}
