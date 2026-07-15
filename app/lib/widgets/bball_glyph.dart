import 'package:flutter/material.dart';

class BBallGlyph extends StatelessWidget {
  final double size;
  final Color color;

  /// Modo contorno: sin relleno, el círculo y las costuras se trazan en [color]
  /// sólido (para íconos sobre fondos de color, como el botón "+").
  final bool outline;

  const BBallGlyph(
      {super.key, this.size = 20, this.color = Colors.white, this.outline = false});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _BBallPainter(color: color, outline: outline),
    );
  }
}

class _BBallPainter extends CustomPainter {
  final Color color;
  final bool outline;
  _BBallPainter({required this.color, this.outline = false});

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);

    final stroke = Paint()
      ..color = outline ? color : Colors.white.withAlpha(80)
      ..strokeWidth = size.width * (outline ? 0.09 : 0.06)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (outline) {
      // Contorno del balón (el trazo se dibuja centrado en el radio, así que
      // achicamos medio grosor para que no se recorte en el borde).
      canvas.drawCircle(center, r - stroke.strokeWidth / 2, stroke);
    } else {
      final fill = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, r, fill);
    }

    // Vertical
    canvas.drawLine(Offset(r, 0), Offset(r, size.height), stroke);
    // Horizontal curve top/bottom
    final path1 = Path()
      ..moveTo(0, r)
      ..quadraticBezierTo(r, r - size.height * 0.35, size.width, r);
    final path2 = Path()
      ..moveTo(0, r)
      ..quadraticBezierTo(r, r + size.height * 0.35, size.width, r);
    canvas.drawPath(path1, stroke);
    canvas.drawPath(path2, stroke);
    // Side arcs
    final arc1 = Path()
      ..moveTo(size.width * 0.2, size.height * 0.2)
      ..quadraticBezierTo(
          r, r, size.width * 0.2, size.height * 0.8);
    final arc2 = Path()
      ..moveTo(size.width * 0.8, size.height * 0.2)
      ..quadraticBezierTo(
          r, r, size.width * 0.8, size.height * 0.8);
    canvas.drawPath(arc1, stroke);
    canvas.drawPath(arc2, stroke);
  }

  @override
  bool shouldRepaint(covariant _BBallPainter oldDelegate) =>
      oldDelegate.color != color;
}
