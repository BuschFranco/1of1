import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Helpers de "efectos" del lenguaje NEOBRUTALISTA (dark): colores planos,
/// bordes francos y sombras duras desplazadas sin blur. Mantiene las firmas de
/// la era pop-futurista (gradientes/glows) para no tocar los call-sites: los
/// gradientes ahora son planos y los "glows" son sombras duras.
class AppFx {
  AppFx._();

  /// Sombra dura neobrutalista: negra, desplazada, SIN blur. Es el reemplazo
  /// universal de los glows neón.
  static List<BoxShadow> hardShadow({
    Offset offset = const Offset(4, 4),
    Color? color,
  }) =>
      [
        BoxShadow(
          color: color ?? AppColors.black(0.85),
          offset: offset,
          blurRadius: 0,
          spreadRadius: 0,
        ),
      ];

  /// Antes: degradado naranja→ámbar. Ahora PLANO (acento sólido): un gradiente
  /// con ambos extremos iguales pinta color liso sin tocar los call-sites.
  static LinearGradient accentGradient({bool deep = false}) => LinearGradient(
        colors: deep
            ? const [AppColors.accentDark, AppColors.accentDark]
            : const [AppColors.accent, AppColors.accent],
      );

  /// Antes: ring hairline con degradado. Ahora un "borde" plano del color dado
  /// (sin fade), acorde a los bordes francos del neobrutalismo.
  static LinearGradient hairline(Color color, {int topAlpha = 255}) =>
      LinearGradient(colors: [color, color]);

  /// Antes: glow neón. Ahora sombra dura negra (los parámetros de blur/alpha se
  /// ignoran a propósito para no tocar los call-sites). [offset] se respeta si
  /// alguien pasa uno distinto de cero.
  static List<BoxShadow> neonGlow(
    Color color, {
    double blur = 22,
    double spread = 1,
    int alpha = 90,
    Offset offset = Offset.zero,
  }) =>
      hardShadow(
        offset: offset == Offset.zero ? const Offset(3, 3) : offset,
      );

  /// Antes: glow + profundidad. Ahora una sombra dura más protagonista (para
  /// banners y CTAs elevados).
  static List<BoxShadow> glowElevated(
    Color color, {
    double glowBlur = 24,
    int glowAlpha = 90,
  }) =>
      hardShadow(offset: const Offset(5, 5));
}

/// Antes: ring con degradado. Ahora una caja con borde SÓLIDO del color dado
/// (2px por defecto) y relleno plano — mismo contrato, look neobrutalista.
class GradientRing extends StatelessWidget {
  final Widget child;
  final double radius;
  final double thickness;
  final Color ringColor;
  final Color fill;
  final EdgeInsetsGeometry? padding;
  final List<BoxShadow>? glow;
  final int ringTopAlpha;

  const GradientRing({
    super.key,
    required this.child,
    this.radius = 8,
    this.thickness = 2,
    this.ringColor = AppColors.accent,
    this.fill = AppColors.panel,
    this.padding,
    this.glow,
    this.ringTopAlpha = 255,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: ringColor, width: thickness),
        boxShadow: glow,
      ),
      child: child,
    );
  }
}
