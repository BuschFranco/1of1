import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// Catálogo de cosméticos del avatar que se desbloquean al subir de nivel:
/// marcos (anillos decorativos), colores de fondo, colores de letra y
/// tipografías. Cada ítem expone un [unlockLevel]; el nivel del jugador decide
/// cuáles puede equipar. La verificación de desbloqueo vive en la UI del editor.

/// Marco decorativo del avatar: un anillo con degradado y un resplandor (glow)
/// que rodea la insignia. El marco 'none' no dibuja nada extra.
class AvatarFrame {
  final String id;
  final String name;
  final int unlockLevel;

  /// Colores del degradado del anillo (>= 2). Vacío = sin anillo (marco 'none').
  final List<Color> ring;

  /// Color del resplandor exterior. transparent = sin glow.
  final Color glow;

  const AvatarFrame({
    required this.id,
    required this.name,
    required this.unlockLevel,
    this.ring = const [],
    this.glow = Colors.transparent,
  });

  bool get isNone => ring.isEmpty;
  bool unlockedAt(int level) => level >= unlockLevel;
}

/// Marcos disponibles, de menor a mayor nivel. El primero ('none') es el default.
const List<AvatarFrame> kFrames = [
  AvatarFrame(id: 'none', name: 'Sin marco', unlockLevel: 1),
  AvatarFrame(
    id: 'bronce',
    name: 'Bronce',
    unlockLevel: 3,
    ring: [Color(0xFFCD7F32), Color(0xFF8C5A2B)],
    glow: Color(0xFFCD7F32),
  ),
  AvatarFrame(
    id: 'plata',
    name: 'Plata',
    unlockLevel: 5,
    ring: [Color(0xFFE6E8EC), Color(0xFF9AA3AD)],
    glow: Color(0xFFC0C6CE),
  ),
  AvatarFrame(
    id: 'oro',
    name: 'Oro',
    unlockLevel: 8,
    ring: [Color(0xFFF9D976), Color(0xFFE9B949)],
    glow: Color(0xFFE9B949),
  ),
  AvatarFrame(
    id: 'rubi',
    name: 'Rubí',
    unlockLevel: 12,
    ring: [Color(0xFFFF8A8A), Color(0xFFC81E3A)],
    glow: Color(0xFFEF4444),
  ),
  AvatarFrame(
    id: 'esmeralda',
    name: 'Esmeralda',
    unlockLevel: 16,
    ring: [Color(0xFF6EE7B7), Color(0xFF10B981)],
    glow: Color(0xFF22C55E),
  ),
  AvatarFrame(
    id: 'zafiro',
    name: 'Zafiro',
    unlockLevel: 20,
    ring: [Color(0xFF60A5FA), Color(0xFF2563EB)],
    glow: Color(0xFF3B82F6),
  ),
  AvatarFrame(
    id: 'amatista',
    name: 'Amatista',
    unlockLevel: 26,
    ring: [Color(0xFFD8B4FE), Color(0xFF9333EA)],
    glow: Color(0xFFA855F7),
  ),
  AvatarFrame(
    id: 'fenix',
    name: 'Fénix',
    unlockLevel: 32,
    ring: [Color(0xFFFFD166), Color(0xFFFF6B1A), Color(0xFFEF4444)],
    glow: Color(0xFFFF6B1A),
  ),
  AvatarFrame(
    id: 'legendario',
    name: 'Legendario',
    unlockLevel: 40,
    ring: [Color(0xFFF9D976), Color(0xFFA855F7), Color(0xFF3B82F6), Color(0xFF22C55E)],
    glow: Color(0xFFF9D976),
  ),
];

/// Marco por id. Si no existe (o vacío), devuelve 'none'.
AvatarFrame frameById(String id) {
  for (final f in kFrames) {
    if (f.id == id) return f;
  }
  return kFrames.first;
}

/// Estilo tipográfico de la insignia de clan (fuente de Google Fonts). Familia
/// vacía o inválida => Archivo.
TextStyle clanFontStyle(
  String family, {
  required double size,
  Color color = Colors.white,
  FontWeight weight = FontWeight.w900,
}) {
  final fam = family.trim().isEmpty ? 'Archivo' : family.trim();
  try {
    return GoogleFonts.getFont(fam, fontSize: size, fontWeight: weight, color: color);
  } catch (_) {
    return GoogleFonts.archivo(fontSize: size, fontWeight: weight, color: color);
  }
}

/// Convierte un hex de 6 dígitos (sin '#') en Color. Vacío o inválido =>
/// color de acento por defecto (usado para el fondo del avatar).
Color clanColor(String hex) {
  final h = hex.replaceAll('#', '').trim();
  if (h.isEmpty) return AppColors.accent;
  final v = int.tryParse(h, radix: 16);
  if (v == null) return AppColors.accent;
  return Color(0xFF000000 | v);
}

/// Igual que [clanColor] pero el default (vacío/inválido) es blanco; se usa
/// para el color de las letras del clan.
Color clanTextColor(String hex) {
  final h = hex.replaceAll('#', '').trim();
  if (h.isEmpty) return Colors.white;
  final v = int.tryParse(h, radix: 16);
  if (v == null) return Colors.white;
  return Color(0xFF000000 | v);
}

/// Envuelve el avatar [child] con el marco equipado: un anillo con degradado y
/// un resplandor exterior. Si el marco es 'none' devuelve el avatar tal cual.
Widget framedAvatar(AvatarFrame frame, double radius, Widget child) {
  if (frame.isNone) return child;
  return Padding(
    padding: const EdgeInsets.all(4),
    child: Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius + 5),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: frame.ring,
        ),
        boxShadow: [
          BoxShadow(color: frame.glow.withAlpha(140), blurRadius: 16, spreadRadius: 0),
        ],
      ),
      child: child,
    ),
  );
}

/// Color cosmético: hex de 6 dígitos (sin '#') + nivel de desbloqueo.
class CosmeticColor {
  final String hex;
  final int unlockLevel;
  const CosmeticColor(this.hex, [this.unlockLevel = 1]);
  bool unlockedAt(int level) => level >= unlockLevel;
}

/// Colores de fondo del avatar. Los primeros (nivel 1) son la base de siempre;
/// el resto se desbloquea subiendo de nivel.
const List<CosmeticColor> kBgColors = [
  CosmeticColor('FF6B1A'), // naranja (default)
  CosmeticColor('3B82F6'), // azul
  CosmeticColor('22C55E'), // verde
  CosmeticColor('A855F7'), // violeta
  CosmeticColor('EF4444'), // rojo
  CosmeticColor('14B8A6'), // teal
  CosmeticColor('EC4899'), // rosa
  CosmeticColor('EAB308'), // amarillo
  // Desbloqueables.
  CosmeticColor('F97316', 4),
  CosmeticColor('06B6D4', 7),
  CosmeticColor('8B5CF6', 10),
  CosmeticColor('F43F5E', 14),
  CosmeticColor('10B981', 18),
  CosmeticColor('0EA5E9', 24),
  CosmeticColor('FACC15', 30),
];

/// Colores de las letras del clan. Base (blanco/negro + acentos) + extras.
const List<CosmeticColor> kTextColors = [
  CosmeticColor('FFFFFF'), // blanco (default)
  CosmeticColor('000000'), // negro
  CosmeticColor('FF6B1A'),
  CosmeticColor('EAB308'),
  CosmeticColor('22C55E'),
  CosmeticColor('3B82F6'),
  CosmeticColor('EF4444'),
  CosmeticColor('A855F7'),
  // Desbloqueables.
  CosmeticColor('06B6D4', 6),
  CosmeticColor('EC4899', 12),
  CosmeticColor('F9D976', 22),
];

/// Tipografía cosmética: familia de Google Fonts + nivel de desbloqueo.
class CosmeticFont {
  final String family;
  final int unlockLevel;
  const CosmeticFont(this.family, [this.unlockLevel = 1]);
  bool unlockedAt(int level) => level >= unlockLevel;
}

/// Tipografías del clan. Las primeras vienen de base; el resto por nivel.
const List<CosmeticFont> kFonts = [
  CosmeticFont('Archivo'),
  CosmeticFont('Bebas Neue'),
  CosmeticFont('Anton'),
  CosmeticFont('Russo One'),
  CosmeticFont('Orbitron'),
  CosmeticFont('Black Ops One'),
  // Desbloqueables.
  CosmeticFont('Teko', 5),
  CosmeticFont('Bungee', 9),
  CosmeticFont('Press Start 2P', 14),
  CosmeticFont('Faster One', 20),
  CosmeticFont('Monoton', 28),
];
