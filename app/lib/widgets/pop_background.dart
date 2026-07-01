import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Fondo pop-futurista reutilizable: grilla técnica sutil + halos radiales
/// naranjas + viñeta, todo dentro de la paleta. Se monta DETRÁS del contenido
/// (no captura toques). Pensado para pantallas que NO son el mapa.
///
/// Uso típico: envolver el body en un Stack con `Positioned.fill(child:
/// const PopBackground())` como primer hijo.
class PopBackground extends StatelessWidget {
  /// Intensidad del halo superior (0–1). Default suave.
  final double glowStrength;

  const PopBackground({super.key, this.glowStrength = 1});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _PopBackgroundPainter(glowStrength: glowStrength),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _PopBackgroundPainter extends CustomPainter {
  final double glowStrength;
  _PopBackgroundPainter({required this.glowStrength});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Base sólida (por si el fondo del Scaffold no está seteado).
    canvas.drawRect(rect, Paint()..color = AppColors.bg);

    // Halo radial naranja arriba-derecha (atmósfera neón).
    final halo1 = RadialGradient(
      colors: [
        AppColors.accent.withAlpha((46 * glowStrength).round().clamp(0, 255)),
        Colors.transparent,
      ],
    );
    final c1 = Offset(size.width * 0.92, size.height * 0.06);
    final r1 = size.shortestSide * 0.75;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = halo1.createShader(
            Rect.fromCircle(center: c1, radius: r1)),
    );

    // Halo secundario tenue abajo-izquierda.
    final halo2 = RadialGradient(
      colors: [
        AppColors.accent.withAlpha((22 * glowStrength).round().clamp(0, 255)),
        Colors.transparent,
      ],
    );
    final c2 = Offset(size.width * 0.05, size.height * 0.88);
    final r2 = size.shortestSide * 0.7;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = halo2.createShader(
            Rect.fromCircle(center: c2, radius: r2)),
    );

    // Grilla técnica: líneas finas equiespaciadas, muy sutiles.
    const step = 34.0;
    final gridPaint = Paint()
      ..color = AppColors.white(0.028)
      ..strokeWidth = 1;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Viñeta oscura en los bordes para enfocar el centro.
    final vignette = RadialGradient(
      colors: [Colors.transparent, AppColors.black(0.35)],
      stops: const [0.62, 1],
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = vignette.createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _PopBackgroundPainter old) =>
      old.glowStrength != glowStrength;
}
