import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color bg = Color(0xFF0A0F14);
  static const Color bgElev = Color(0xFF111821);
  static const Color card = Color(0x991A2430);
  static const Color accent = Color(0xFFFF6B1A);
  static const Color accentDark = Color(0xFFD94E06);
  static const Color open = Color(0xFF4ADE80);
  static const Color busy = Color(0xFFFF6B1A);
  static const Color closed = Color(0xFF6B7788);

  static Color white(double op) => Color.fromRGBO(255, 255, 255, op);
  static Color black(double op) => Color.fromRGBO(0, 0, 0, op);
}

class AppText {
  static TextStyle archivo({
    double size = 14,
    FontWeight weight = FontWeight.w700,
    Color color = Colors.white,
    double letterSpacing = -0.02,
    double? height,
  }) {
    return GoogleFonts.archivo(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing * size,
      height: height,
    );
  }

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
  );
}
