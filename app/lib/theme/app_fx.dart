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

  /// Sombra AMBIENTAL para elementos que flotan sobre contenido con textura
  /// (las tarjetas sobre el mapa). Dos capas: una cercana que define el borde y
  /// una amplia y difusa que despega la caja del fondo.
  ///
  /// Es lo contrario de [hardShadow]: sin ella, el corte entre la tarjeta y el
  /// mapa queda a filo y la tarjeta parece pegada, no flotando.
  static List<BoxShadow> ambientShadow({double strength = 1}) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.35 * strength),
          offset: const Offset(0, 3),
          blurRadius: 10,
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.22 * strength),
          offset: const Offset(0, 10),
          blurRadius: 28,
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

  // ── Halos de TEXTO ──────────────────────────────────────────────────────
  //
  // El sitio usa `text-shadow: 0 0 20px rgba(255,107,26,.4)` en su titular de
  // acento: sin offset, blur amplio, alpha bajo. Devuelven `Shadow` (no
  // `BoxShadow`: son tipos distintos) pero viven acá porque es el mismo
  // lenguaje visual que el resto de los efectos.
  //
  // La ausencia de offset es justamente lo que distingue el halo de la sombra
  // dura del estilo viejo.

  static List<Shadow> textGlow(
    Color color, {
    double blur = 16,
    double alpha = 0.3,
  }) =>
      [
        Shadow(
          color: color.withValues(alpha: alpha),
          blurRadius: blur,
        ),
      ];

  /// Halo naranja para titulares que YA son de acento. Prácticamente los
  /// valores del sitio (20px / .40), apenas bajados: los títulos de la app son
  /// de 28-46px contra los 120px del hero web, y el blur no escala con la
  /// fuente.
  static List<Shadow> accentGlow({double blur = 18, double alpha = 0.38}) =>
      textGlow(AppColors.accent, blur: blur, alpha: alpha);

  /// Halo blanco para titulares en tinta. Alpha MUCHO más bajo a propósito: el
  /// sitio no le pone halo a su línea blanca, y sobre un fondo casi negro el
  /// blanco a .40 engorda el trazo de Anton (ya condensada y pesada) en vez de
  /// verse como aura.
  static List<Shadow> inkGlow({double blur = 14, double alpha = 0.15}) =>
      textGlow(AppColors.ink, blur: blur, alpha: alpha);

  /// Halo NEGRO de legibilidad para texto sobre foto (el del marquee del
  /// sitio: 0 0 40px rgba(0,0,0,.7) + 0 0 80px rgba(0,0,0,.4)).
  static List<Shadow> readableGlow({double scale = 1}) => [
        Shadow(color: Colors.black.withValues(alpha: 0.7), blurRadius: 40 * scale),
        Shadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 80 * scale),
      ];

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
