import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Helpers de "efectos" del lenguaje pop-futurista: degradados de acento y glows
/// neón, centralizados para no repetir los mismos `LinearGradient`/`BoxShadow`
/// inline por toda la app. Todo dentro de la paleta actual (naranja/ámbar/verde).
class AppFx {
  AppFx._();

  /// Degradado diagonal del acento: naranja → ámbar (más "pop"/neón) o, en modo
  /// [deep], naranja → naranja oscuro (para superficies más sobrias).
  static LinearGradient accentGradient({bool deep = false}) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: deep
            ? const [AppColors.accent, AppColors.accentDark]
            : const [AppColors.accentAmber, AppColors.accent],
      );

  /// Ring hairline: degradado del color (arriba-izq) a casi-transparente
  /// (abajo-der). Se usa como "borde" pintando un contenedor de 1px por detrás
  /// del contenido (Flutter no soporta bordes con degradado nativo).
  static LinearGradient hairline(Color color, {int topAlpha = 140}) =>
      LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          color.withAlpha(topAlpha),
          color.withAlpha(16),
        ],
      );

  /// Glow neón estándar (halo de color). [alpha] 0–255.
  static List<BoxShadow> neonGlow(
    Color color, {
    double blur = 22,
    double spread = 1,
    int alpha = 90,
    Offset offset = Offset.zero,
  }) =>
      [
        BoxShadow(
          color: color.withAlpha(alpha),
          blurRadius: blur,
          spreadRadius: spread,
          offset: offset,
        ),
      ];

  /// Glow neón + sombra de profundidad (para elementos elevados: banners, CTAs).
  static List<BoxShadow> glowElevated(
    Color color, {
    double glowBlur = 24,
    int glowAlpha = 90,
  }) =>
      [
        BoxShadow(
          color: color.withAlpha(glowAlpha),
          blurRadius: glowBlur,
          spreadRadius: 1,
        ),
        BoxShadow(
          color: AppColors.black(0.4),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ];
}

/// Envuelve [child] en un "ring" de 1px con degradado (borde hairline neón).
/// El interior se pinta con [fill]; opcionalmente agrega [glow].
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
    this.radius = 18,
    this.thickness = 1.2,
    this.ringColor = AppColors.accent,
    this.fill = AppColors.panel,
    this.padding,
    this.glow,
    this.ringTopAlpha = 140,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: AppFx.hairline(ringColor, topAlpha: ringTopAlpha),
        boxShadow: glow,
      ),
      padding: EdgeInsets.all(thickness),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(radius - thickness),
        ),
        child: child,
      ),
    );
  }
}
