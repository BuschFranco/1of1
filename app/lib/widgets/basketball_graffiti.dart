import 'dart:math';
import 'package:flutter/material.dart';

/// Composición de elementos basketball estilo tattoo/graffiti como capa de
/// fondo decorativa. Opacidad muy baja para que sea sutil.
class BasketballGraffiti extends StatelessWidget {
  final double size;
  final Color color;

  const BasketballGraffiti({
    super.key,
    this.size = 280,
    this.color = const Color(0xFF000000),
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.square(size),
        painter: _GraffitiPainter(color: color),
      ),
    );
  }
}

class _GraffitiPainter extends CustomPainter {
  final Color color;
  _GraffitiPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width * 0.5;

    // ── Balón grande al centro ──────────────────────────────────────────
    _drawBall(canvas, c, r * 0.52);

    // ── Aro / canasta (arriba a la derecha) ─────────────────────────────
    _drawHoop(canvas, Offset(c.dx + r * 0.45, c.dy - r * 0.55), r * 0.28);

    // ── Segundo balón pequeño (abajo a la izquierda) ────────────────────
    _drawBall(canvas, Offset(c.dx - r * 0.52, c.dy + r * 0.48), r * 0.2);

    // ── Estrellas decorativas ───────────────────────────────────────────
    _drawStar(canvas, Offset(c.dx - r * 0.65, c.dy - r * 0.35), r * 0.06);
    _drawStar(canvas, Offset(c.dx + r * 0.68, c.dy + r * 0.2), r * 0.045);
    _drawStar(canvas, Offset(c.dx + r * 0.1, c.dy - r * 0.72), r * 0.04);
    _drawStar(canvas, Offset(c.dx - r * 0.3, c.dy + r * 0.7), r * 0.05);

    // ── Líneas de velocidad / rayas ─────────────────────────────────────
    _drawSpeedLines(canvas, c, r);
  }

  void _drawBall(Canvas canvas, Offset center, double radius) {
    final fillPaint = Paint()
      ..color = color.withAlpha(14)
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = color.withAlpha(22)
      ..strokeWidth = radius * 0.09
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Relleno base
    canvas.drawCircle(center, radius, fillPaint);

    // Borde exterior
    canvas.drawCircle(center, radius, strokePaint);

    // Línea vertical
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      strokePaint,
    );

    // Curvas horizontales superior e inferior
    final topCurve = Path()
      ..moveTo(center.dx - radius, center.dy)
      ..quadraticBezierTo(
          center.dx, center.dy - radius * 0.6, center.dx + radius, center.dy);
    final bottomCurve = Path()
      ..moveTo(center.dx - radius, center.dy)
      ..quadraticBezierTo(
          center.dx, center.dy + radius * 0.6, center.dx + radius, center.dy);
    canvas.drawPath(topCurve, strokePaint);
    canvas.drawPath(bottomCurve, strokePaint);

    // Arcos laterales
    final leftArc = Path()
      ..moveTo(center.dx - radius * 0.7, center.dy - radius * 0.7)
      ..quadraticBezierTo(
          center.dx, center.dy, center.dx - radius * 0.7, center.dy + radius * 0.7);
    final rightArc = Path()
      ..moveTo(center.dx + radius * 0.7, center.dy - radius * 0.7)
      ..quadraticBezierTo(
          center.dx, center.dy, center.dx + radius * 0.7, center.dy + radius * 0.7);
    canvas.drawPath(leftArc, strokePaint);
    canvas.drawPath(rightArc, strokePaint);
  }

  void _drawHoop(Canvas canvas, Offset center, double size) {
    final strokePaint = Paint()
      ..color = color.withAlpha(20)
      ..strokeWidth = size * 0.07
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = color.withAlpha(10)
      ..style = PaintingStyle.fill;

    // Backboard (rectángulo)
    final board = RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: Offset(center.dx, center.dy - size * 0.15),
          width: size * 0.7,
          height: size * 0.5),
      Radius.circular(size * 0.04),
    );
    canvas.drawRRect(board, fillPaint);
    canvas.drawRRect(board, strokePaint);

    // Aro (línea horizontal + círculo)
    final hoopY = center.dy + size * 0.12;
    canvas.drawLine(
      Offset(center.dx - size * 0.28, hoopY),
      Offset(center.dx + size * 0.28, hoopY),
      strokePaint,
    );

    // Red (líneas verticales que cuelgan)
    final netPaint = Paint()
      ..color = color.withAlpha(16)
      ..strokeWidth = size * 0.03
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (var i = -2; i <= 2; i++) {
      final x = center.dx + i * size * 0.1;
      final netPath = Path()
        ..moveTo(x, hoopY)
        ..quadraticBezierTo(
            x + i * size * 0.02, hoopY + size * 0.2, x, hoopY + size * 0.32);
      canvas.drawPath(netPath, netPaint);
    }
  }

  void _drawStar(Canvas canvas, Offset center, double radius) {
    final paint = Paint()
      ..color = color.withAlpha(18)
      ..style = PaintingStyle.fill;

    final path = Path();
    for (var i = 0; i < 5; i++) {
      final outerAngle = (i * 72 - 90) * pi / 180;
      final innerAngle = ((i * 72 + 36) - 90) * pi / 180;
      final outer = Offset(
        center.dx + radius * cos(outerAngle),
        center.dy + radius * sin(outerAngle),
      );
      final inner = Offset(
        center.dx + radius * 0.4 * cos(innerAngle),
        center.dy + radius * 0.4 * sin(innerAngle),
      );
      if (i == 0) {
        path.moveTo(outer.dx, outer.dy);
      } else {
        path.lineTo(outer.dx, outer.dy);
      }
      path.lineTo(inner.dx, inner.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawSpeedLines(Canvas canvas, Offset center, double r) {
    final paint = Paint()
      ..color = color.withAlpha(14)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    // Líneas de movimiento (izquierda)
    final lines = [
      (Offset(center.dx - r * 0.85, center.dy - r * 0.1),
          Offset(center.dx - r * 0.65, center.dy - r * 0.1)),
      (Offset(center.dx - r * 0.9, center.dy + r * 0.05),
          Offset(center.dx - r * 0.72, center.dy + r * 0.05)),
      (Offset(center.dx - r * 0.82, center.dy + r * 0.2),
          Offset(center.dx - r * 0.68, center.dy + r * 0.2)),
    ];

    for (final (start, end) in lines) {
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GraffitiPainter old) => old.color != color;
}
