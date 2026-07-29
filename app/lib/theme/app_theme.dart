import 'package:flutter/material.dart';

/// Paleta DARK MODE, alineada con el sitio web (`web/src/styles/tokens.css`):
/// azules muy oscuros en vez de negro puro, acento naranja balón, texto blanco.
/// Se conservan los NOMBRES de tokens para no tocar los cientos de call-sites.
///
/// La rampa de superficies va de más oscuro a más claro:
/// `lilac` (#080e18) → `bg` (#0d141e) → `bgElev` (#141b26) → `card` (#1a202a).
class AppColors {
  // Fondos dark (--bg / --bg-card del sitio). bgElev es un paso INTERMEDIO
  // entre bg y card: los modales se pintan con bgElev y sus secciones con card,
  // así que igualarlos aplanaría los sheets y los diálogos.
  static const Color bg = Color(0xFF0D141E);
  static const Color bgElev = Color(0xFF141B26);
  static const Color card = Color(0xFF1A202A);
  static const Color panel = Color(0xFF1A202A);

  // Acento interactivo: naranja balón (idéntico al --accent del sitio).
  static const Color accent = Color(0xFFFF6B1A);
  static const Color accentDark = Color(0xFFCC5515);
  static const Color accentAmber = Color(0xFFFF6B1A);

  // Estados (brillantes sobre dark).
  static const Color open = Color(0xFF22C55E);
  static const Color busy = Color(0xFFF59E0B);
  static const Color closed = Color(0xFF6B7280);

  /// Fondo de Canchas y Crew: el `--bg-lowest` del sitio, MÁS oscuro que `bg`
  /// a propósito (esas dos pantallas son listas a pantalla completa y el
  /// contraste con las cards las hace respirar).
  static const Color lilac = Color(0xFF080E18);

  // Aliases históricos de fondo de PANTALLA (no de card): se conservan para no
  // romper call-sites, pero no tienen color propio.
  static const Color sun = bg;
  static const Color red = bg;
  static const Color cream = bg;
  static const Color olive = bg;
  static const Color blush = bg;
  // Aliases de superficie elevada (paneles sobre el mapa, chips, fills).
  static const Color charcoal = bgElev;
  static const Color paper = bgElev;
  static const Color glass = bgElev;

  /// Fondos de perfil elegibles por el usuario (clave persistida → color).
  /// Las CLAVES no se tocan (están guardadas en prefs); los valores se
  /// re-tintaron a la familia del sitio. Todos de luminancia baja y parecida,
  /// así el texto blanco funciona en los seis sin condicionales.
  static const Map<String, Color> profileBgs = {
    'charcoal': bg,
    'olive': Color(0xFF16241C),
    'sun': Color(0xFF2A1E0D),
    'lilac': Color(0xFF151B3A),
    'red': Color(0xFF2A1014),
    'cream': card,
  };

  /// Resuelve la clave guardada al color de fondo del perfil (default charcoal).
  static Color profileBg(String key) => profileBgs[key] ?? bg;

  // Borde universal: gris azulado. Mantiene el mismo salto de luminancia que
  // tenía sobre el negro, solo cambia la temperatura.
  static const Color line = Color(0xFF2B3444);

  /// Borde CÁLIDO del sitio (`--border`). Reservado para bordes editoriales
  /// puntuales: `line` tiene decenas de usos estructurales (cards, inputs,
  /// chips, avatares) y pintarlos todos de marrón delinearía la app entera.
  static const Color lineWarm = Color(0xFF5A4137);

  // Texto / íconos: blanco (el --ink-strong del sitio).
  static const Color ink = Color(0xFFFFFFFF);

  /// Textos cálidos del sitio (`--ink-variant` / `--ink-muted`). Todavía sin
  /// usar: la jerarquía secundaria de la app se expresa con `white(op)`, así
  /// que migrar a estos exige una pasada propia para no invertirla.
  static const Color inkVariant = Color(0xFFE2BFB2);
  static const Color inkMuted = Color(0xFFA98A7E);

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
  static const double rField = 16; // inputs de texto (rectángulo redondeado, no píldora)
}

/// Tipografía de la marca: las mismas tres familias que la web
/// (`web/src/styles/tokens.css`), con un helper por rol.
///
/// | Helper      | Familia        | Rol en la web  |
/// | ----------- | -------------- | -------------- |
/// | `display()` | Anton          | titulares      |
/// | `archivo()` | Anybody        | etiquetas      |
/// | `grotesk()` | Archivo Narrow | texto corrido  |
///
/// Archivo Narrow y Anybody son **fuentes variables**: declarar `fontWeight` no
/// alcanza para moverles el peso, hay que empujar el eje `wght` con
/// `fontVariations`. Por eso los helpers mandan las dos cosas — `fontWeight`
/// para que Flutter elija bien la familia y calcule el fallback, y la variación
/// para que el trazo sea realmente el pedido.
class AppText {
  /// Eje `wght` a partir del `FontWeight` pedido.
  static List<FontVariation> _wght(FontWeight w) =>
      [FontVariation('wght', w.value.toDouble())];

  /// Titulares de la marca: Anton, condensada y pesada. Viene en un solo peso
  /// (400), así que acá `weight` no cambia el trazo — no le pases pesos
  /// esperando variación.
  static TextStyle display({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.ink,
    double letterSpacing = 0,
    double? height,
    List<Shadow>? shadows,
  }) {
    return TextStyle(
      fontFamily: 'Anton',
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing * size,
      height: height,
      shadows: shadows,
    );
  }

  /// Etiquetas y títulos de sección: Anybody. Es la que la web usa para
  /// botones y rótulos en mayúscula. Conserva el nombre histórico porque lo
  /// usan ~150 call-sites.
  static TextStyle archivo({
    double size = 14,
    FontWeight weight = FontWeight.w900,
    Color color = AppColors.ink,
    double letterSpacing = 0,
    double? height,
    List<Shadow>? shadows,
  }) {
    return TextStyle(
      fontFamily: 'Anybody',
      fontSize: size,
      fontWeight: weight,
      fontVariations: _wght(weight),
      color: color,
      letterSpacing: letterSpacing * size,
      height: height,
      shadows: shadows,
    );
  }

  /// Texto corrido: Archivo Narrow.
  static TextStyle grotesk({
    double size = 12,
    FontWeight weight = FontWeight.w500,
    Color color = AppColors.ink,
    double letterSpacing = 0,
    double? height,
    List<Shadow>? shadows,
  }) {
    return TextStyle(
      fontFamily: 'ArchivoNarrow',
      fontSize: size,
      fontWeight: weight,
      fontVariations: _wght(weight),
      color: color,
      letterSpacing: letterSpacing * size,
      height: height,
      shadows: shadows,
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
    // Texto corrido en Archivo Narrow y etiquetas en Anybody, igual que la web.
    textTheme: ThemeData.dark().textTheme.copyWith(
      bodyLarge: const TextStyle(fontFamily: 'ArchivoNarrow'),
      bodyMedium: const TextStyle(fontFamily: 'ArchivoNarrow'),
      bodySmall: const TextStyle(fontFamily: 'ArchivoNarrow'),
      labelLarge: const TextStyle(fontFamily: 'Anybody'),
      labelMedium: const TextStyle(fontFamily: 'Anybody'),
      labelSmall: const TextStyle(fontFamily: 'Anybody'),
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
