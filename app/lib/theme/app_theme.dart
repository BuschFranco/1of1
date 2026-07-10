import 'package:flutter/material.dart';

/// Paleta DARK MODE — estilo Nike: fondos negros, superficies grises oscuras,
/// acento naranja balón, texto blanco. Bordes sutiles, sombras profundas.
/// Se conservan los NOMBRES de tokens para no tocar los cientos de call-sites.
class AppColors {
  // Fondos dark.
  static const Color bg = Color(0xFF0A0A0A);
  static const Color bgElev = Color(0xFF141414);
  static const Color card = Color(0xFF1A1A1A);
  static const Color panel = Color(0xFF1A1A1A);

  // Acento interactivo: naranja balón.
  static const Color accent = Color(0xFFFF6B1A);
  static const Color accentDark = Color(0xFFCC5515);
  static const Color accentAmber = Color(0xFFFF6B1A);

  // Estados (brillantes sobre dark).
  static const Color open = Color(0xFF22C55E);
  static const Color busy = Color(0xFFF59E0B);
  static const Color closed = Color(0xFF6B7280);

  // Superficies dark (cada pantalla tenía su color saturado → tonos oscuros).
  static const Color lilac = Color(0xFF1E1B4B);
  static const Color sun = Color(0xFF1A1A1A);
  static const Color red = Color(0xFF1A1A1A);
  static const Color cream = Color(0xFF0A0A0A);
  static const Color olive = Color(0xFF1A1A1A);
  static const Color charcoal = Color(0xFF141414);
  static const Color paper = Color(0xFF141414);
  static const Color blush = Color(0xFF1A1A1A);
  static const Color glass = Color(0xFF141414);

  /// Fondos de perfil elegibles por el usuario (clave persistida → color).
  static const Map<String, Color> profileBgs = {
    'charcoal': charcoal,
    'olive': Color(0xFF2D3A1E),
    'sun': Color(0xFF3D2E0A),
    'lilac': Color(0xFF2E1B4B),
    'red': Color(0xFF3A0A0A),
    'cream': Color(0xFF1A1A1A),
  };

  /// Resuelve la clave guardada al color de fondo del perfil (default charcoal).
  static Color profileBg(String key) => profileBgs[key] ?? charcoal;

  // Borde universal: gris sutil sobre dark.
  static const Color line = Color(0xFF2A2A2A);

  // Texto / íconos: blanco.
  static const Color ink = Color(0xFFFFFFFF);

  /// Texto/secundario blanco con opacidad (para dark mode).
  static Color white(double op) => Color.fromRGBO(255, 255, 255, op);

  /// Texto/secundario negro con opacidad (para superpuestos sobre acento).
  static Color black(double op) => Color.fromRGBO(0, 0, 0, op);
}

/// Radios del lenguaje: pills en botones/chips, esquinas grandes en cards.
class AppShape {
  AppShape._();
  static const double rCard = 20;
  static const double rBtn = 100;
  static const double rChip = 100;
}

class AppText {
  /// Fuente display de la marca (títulos): Jost — geometric sans-serif
  /// inspirada en Futura (estilo Nike). Bold por defecto.
  static TextStyle display({
    double size = 14,
    FontWeight weight = FontWeight.w700,
    Color color = AppColors.ink,
    double letterSpacing = 0,
    double? height,
  }) {
    return TextStyle(
      fontFamily: 'Jost',
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing * size,
      height: height,
    );
  }

  /// Alias histórico.
  static TextStyle archivo({
    double size = 14,
    FontWeight weight = FontWeight.w900,
    Color color = AppColors.ink,
    double letterSpacing = 0,
    double? height,
  }) =>
      display(
        size: size,
        weight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );

  static TextStyle grotesk({
    double size = 12,
    FontWeight weight = FontWeight.w500,
    Color color = AppColors.ink,
    double letterSpacing = 0,
    double? height,
  }) {
    return TextStyle(
      fontFamily: 'Jost',
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing * size,
      height: height,
    );
  }
}

ThemeData buildAppTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      secondary: AppColors.accent,
      surface: AppColors.bg,
    ),
    textTheme: ThemeData.dark().textTheme.copyWith(
      bodyLarge: const TextStyle(fontFamily: 'Jost'),
      bodyMedium: const TextStyle(fontFamily: 'Jost'),
      bodySmall: const TextStyle(fontFamily: 'Jost'),
      labelLarge: const TextStyle(fontFamily: 'Jost'),
      labelMedium: const TextStyle(fontFamily: 'Jost'),
      labelSmall: const TextStyle(fontFamily: 'Jost'),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.bgElev,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppShape.rCard),
        side: const BorderSide(color: AppColors.line, width: 1),
      ),
    ),
  );
}
