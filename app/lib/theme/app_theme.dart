import 'package:flutter/material.dart';

/// Paleta RETRO-POP CARTOON (clara). Fondos planos saturados por pantalla,
/// superficies claras (crema/blanco), tinta negra, bordes negros y sombras
/// duras. Se conservan los NOMBRES de tokens de la era neobrutalista (accent,
/// glass, line, white(op)…) reimplementando sus VALORES, para no tocar los
/// cientos de call-sites.
class AppColors {
  // Fondo base (crema) y superficies.
  static const Color bg = Color(0xFFF4EBDD); // crema base / default
  static const Color bgElev = Color(0xFFFFFFFF); // elevado (diálogos) = blanco
  static const Color card = Color(0xFFFFF9EF); // card crema casi blanca
  static const Color panel = Color(0xFFFFF9EF); // = card

  // Acento interactivo: rojo (kickers, links, tab activa, selección).
  static const Color accent = Color(0xFFC94040);
  static const Color accentDark = Color(0xFF9E2F2F);
  static const Color accentAmber = Color(0xFFF5A94B); // = sun (tinte cálido)

  // Estados (oscurecidos para leer sobre superficies claras).
  static const Color open = Color(0xFF2E9E5B); // verde
  static const Color busy = Color(0xFFD97706); // ámbar quemado
  static const Color closed = Color(0xFF7A7267); // gris cálido

  // Fondos de sección (un color distinto por pantalla) + superficies claras.
  static const Color lilac = Color(0xFF9F92E8);
  static const Color sun = Color(0xFFF5A94B);
  static const Color red = Color(0xFFC94040);
  static const Color cream = Color(0xFFF4EBDD);
  static const Color olive = Color(0xFF8FA05A); // verde oliva de la paleta
  static const Color paper = Color(0xFFFFFFFF); // pills/nav/cards sobre saturado
  static const Color blush = Color(0xFFF7CFC4); // relleno de botones / headlines

  /// Fondos de perfil elegibles por el usuario (clave persistida → color).
  /// El default es el crema (el mismo de la sección "+").
  static const Map<String, Color> profileBgs = {
    'cream': cream,
    'olive': olive,
    'sun': sun,
    'lilac': lilac,
    'red': red,
  };

  /// Resuelve la clave guardada al color de fondo del perfil (default crema).
  static Color profileBg(String key) => profileBgs[key] ?? cream;

  // "glass" (histórico): overlays sobre el mapa y la tab bar → pills BLANCAS.
  static const Color glass = Color(0xFFFFFFFF);

  // Borde universal del lenguaje: NEGRO (antes blanco 90%). Al redefinir el
  // valor, todos los `AppColors.line` pasan a negro sin tocar call-sites.
  static const Color line = Color(0xFF000000);
  static const Color ink = Color(0xFF000000);

  /// "Tinta tenue": OJO — histórico `white(op)`, ahora devuelve NEGRO con
  /// opacidad. Así todos los textos/íconos/bordes secundarios que eran "blanco
  /// apagado sobre oscuro" pasan a "negro apagado sobre claro" de una sola vez.
  /// Para blanco real usar `Colors.white` explícito (sobre acento/rojo).
  static Color white(double op) => Color.fromRGBO(0, 0, 0, op);
  static Color black(double op) => Color.fromRGBO(0, 0, 0, op);
}

/// Radios del lenguaje retro-pop: pills en botones/chips, esquinas grandes en
/// cards.
class AppShape {
  AppShape._();
  static const double rCard = 20; // cards / paneles redondeados grandes
  static const double rBtn = 100; // botones / inputs → pill
  static const double rChip = 100; // chips / badges → pill
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

  /// Alias histórico. Todo el código existente que usaba `AppText.archivo`
  /// ahora renderiza con la fuente display (Jost) sin tocar call-sites.
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
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.light(
      primary: AppColors.accent,
      secondary: AppColors.accent,
      surface: AppColors.bg,
    ),
    textTheme: ThemeData.light().textTheme.copyWith(
      bodyLarge: const TextStyle(fontFamily: 'Jost'),
      bodyMedium: const TextStyle(fontFamily: 'Jost'),
      bodySmall: const TextStyle(fontFamily: 'Jost'),
      labelLarge: const TextStyle(fontFamily: 'Jost'),
      labelMedium: const TextStyle(fontFamily: 'Jost'),
      labelSmall: const TextStyle(fontFamily: 'Jost'),
    ),
    // Diálogos retro-pop GLOBALES: fondo claro, borde negro franco, esquinas
    // redondeadas. Cubre todos los AlertDialog sin tocarlos uno por uno.
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppShape.rCard),
        side: const BorderSide(color: AppColors.ink, width: 2),
      ),
    ),
  );
}
