import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color bg = Color(0xFF0A0F14);
  static const Color bgElev = Color(0xFF111821);
  // Neobrutalismo: superficies SÓLIDAS (nada semitransparente ni "glass").
  static const Color card = Color(0xFF1A2430);
  static const Color accent = Color(0xFFFF6B1A);
  static const Color accentDark = Color(0xFFD94E06);
  // Acento claro (se conserva para tintes puntuales; ya no hay degradados).
  static const Color accentAmber = Color(0xFFFFA23C);
  static const Color open = Color(0xFF4ADE80);
  static const Color busy = Color(0xFFFF6B1A);
  static const Color closed = Color(0xFF6B7788);

  // Superficies nombradas (sólidas).
  static const Color panel = Color(0xFF1A2430);
  static const Color glass = Color(0xFF11181F);

  // Bordes del lenguaje neobrutalista: claro sobre paneles oscuros, negro puro
  // sobre elementos de acento.
  static const Color line = Color(0xE6FFFFFF); // blanco 90%
  static const Color ink = Color(0xFF000000);

  static Color white(double op) => Color.fromRGBO(255, 255, 255, op);
  static Color black(double op) => Color.fromRGBO(0, 0, 0, op);
}

/// Radios del lenguaje neobrutalista: pocos y chicos (nada de píldoras).
class AppShape {
  AppShape._();
  static const double rCard = 8; // cards grandes / paneles
  static const double rBtn = 6; // botones / inputs
  static const double rChip = 4; // chips / badges
}

class AppText {
  /// Fuente display de la marca (títulos): Unbounded — display bold y
  /// redondeada, con onda pop. Es ancha por naturaleza, así que el default de
  /// letterSpacing es 0 (los headlines grandes pasan valores negativos para
  /// compactar). Pesa hasta 900.
  static TextStyle display({
    double size = 14,
    FontWeight weight = FontWeight.w700,
    Color color = Colors.white,
    double letterSpacing = 0,
    double? height,
  }) {
    return GoogleFonts.unbounded(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing * size,
      height: height,
    );
  }

  /// Alias histórico. Todo el código existente que usaba `AppText.archivo`
  /// ahora renderiza con la fuente display (Unbounded) sin tocar call-sites.
  static TextStyle archivo({
    double size = 14,
    FontWeight weight = FontWeight.w700,
    Color color = Colors.white,
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
    Color color = Colors.white,
    double letterSpacing = 0,
    double? height,
  }) {
    return GoogleFonts.spaceGrotesk(
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
    textTheme: GoogleFonts.spaceGroteskTextTheme(
      ThemeData.dark().textTheme,
    ),
    // Diálogos neobrutalistas GLOBALES: fondo sólido, borde franco, radio
    // chico. Cubre todos los AlertDialog (resultado, permisos, insignia…)
    // sin tocarlos uno por uno.
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.bgElev,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppShape.rCard),
        side: const BorderSide(color: AppColors.line, width: 2),
      ),
    ),
  );
}
