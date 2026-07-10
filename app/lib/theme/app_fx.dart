import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Helpers de efectos — dark mode Nike: sombras profundas sobre fondos oscuros.
class AppFx {
  AppFx._();

  /// Sombra dura: negra con opacidad media, sin blur.
  static List<BoxShadow> hardShadow({
    Offset offset = const Offset(1, 2),
    double blur = 0,
    Color? color,
  }) =>
      [
        BoxShadow(
          color: (color ?? Colors.black).withValues(alpha: 0.5),
          offset: offset,
          blurRadius: blur,
          spreadRadius: 0,
        ),
      ];

  /// Sombra sutil para cards secundarias / elementos pasivos.
  static List<BoxShadow> softShadow({
    Offset offset = const Offset(0, 1),
    double blur = 1,
    Color? color,
  }) =>
      [
        BoxShadow(
          color: (color ?? Colors.black).withValues(alpha: 0.3),
          offset: offset,
          blurRadius: blur,
          spreadRadius: 0,
        ),
      ];

  /// Sombra para elementos elevados (banners, CTAs).
  static List<BoxShadow> elevatedShadow({
    Offset offset = const Offset(0, 2),
    double blur = 2,
    Color? color,
  }) =>
      [
        BoxShadow(
          color: (color ?? Colors.black).withValues(alpha: 0.6),
          offset: offset,
          blurRadius: blur,
          spreadRadius: 0,
        ),
      ];

  /// Gradiente de acento (plano — ambos extremos iguales).
  static LinearGradient accentGradient({bool deep = false}) => LinearGradient(
        colors: deep
            ? const [AppColors.accentDark, AppColors.accentDark]
            : const [AppColors.accent, AppColors.accent],
      );

  /// Borde plano del color dado.
  static LinearGradient hairline(Color color, {int topAlpha = 255}) =>
      LinearGradient(colors: [color, color]);

  /// Sombra glow neon.
  static List<BoxShadow> neonGlow(
    Color color, {
    double blur = 22,
    double spread = 1,
    int alpha = 90,
    Offset offset = Offset.zero,
  }) =>
      [
        BoxShadow(
          color: color.withValues(alpha: alpha / 255),
          offset: offset == Offset.zero ? const Offset(0, 2) : offset,
          blurRadius: blur,
          spreadRadius: spread,
        ),
      ];

  /// Sombra elevada para banners y CTAs protagonistas.
  static List<BoxShadow> glowElevated(
    Color color, {
    double glowBlur = 24,
    int glowAlpha = 90,
  }) =>
      elevatedShadow();
}

/// Caja con borde SÓLIDO del color dado y relleno plano.
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
    this.thickness = 1,
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
