import 'package:flutter/material.dart';

class BBallGlyph extends StatelessWidget {
  final double size;
  final Color color;

  const BBallGlyph({super.key, this.size = 20, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _BBallPainter(color: color),
    );
  }
}

class _BBallPainter extends CustomPainter {
  final Color color;
  _BBallPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);

    final fill = Paint()
      ..color = color.withAlpha(242)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, r, fill);

    final stroke = Paint()
      ..color = const Color(0xFF0A0F14)
      ..strokeWidth = size.width * 0.05
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

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
