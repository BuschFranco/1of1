import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../theme/app_theme.dart';

/// Marcador de cancha dibujado por la app (nada del pin clásico de Google):
/// disco oscuro con la pelota de básquet y una puntita hacia la ubicación.
/// Seleccionado = acento pleno y un poco más grande. Se rasteriza una sola
/// vez por variante y se reusa en todos los markers.
Future<BitmapDescriptor> buildCourtMarker({
  required bool selected,
  required double dpr,
}) async {
  final double d = (selected ? 44 : 34) * dpr; // diámetro del disco
  final double tail = (selected ? 9 : 7) * dpr; // alto de la puntita
  final double ring = 2.5 * dpr;
  final double w = d + ring * 2;
  final double h = d + tail + ring * 2;
  final center = Offset(w / 2, ring + d / 2);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  final Color fill = selected ? AppColors.accent : const Color(0xFF1C1C1E);
  final Color ringColor =
      selected ? AppColors.ink : AppColors.accent.withAlpha(220);
  final Color glyph = selected ? AppColors.ink : Colors.white;

  // Sombra suave para despegarlo del mapa oscuro.
  canvas.drawCircle(
    center.translate(0, 1.5 * dpr),
    d / 2,
    Paint()
      ..color = Colors.black.withAlpha(90)
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, 3 * dpr),
  );

  // Puntita (triángulo) hacia el punto exacto de la cancha.
  final tip = Path()
    ..moveTo(center.dx - 6 * dpr, center.dy + d / 2 - 2 * dpr)
    ..lineTo(center.dx, h)
    ..lineTo(center.dx + 6 * dpr, center.dy + d / 2 - 2 * dpr)
    ..close();
  canvas.drawPath(tip, Paint()..color = fill);

  // Disco con anillo.
  canvas.drawCircle(center, d / 2, Paint()..color = fill);
  canvas.drawCircle(
    center,
    d / 2 - ring / 2,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ring
      ..color = ringColor,
  );

  // Pelota de básquet (glyph de Material Icons, ya empaquetado en la app).
  final tp = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(Icons.sports_basketball.codePoint),
      style: TextStyle(
        fontSize: d * 0.58,
        fontFamily: Icons.sports_basketball.fontFamily,
        color: glyph,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));

  final image =
      await recorder.endRecording().toImage(w.ceil(), h.ceil());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  // Tamaño lógico explícito: sin esto Android trata el bitmap como dpr=1 y lo
  // re-escala (se veía grande y borroso). Así el PNG de alta resolución se
  // dibuja 1:1 con los píxeles físicos del device.
  return BitmapDescriptor.bytes(
    bytes!.buffer.asUint8List(),
    width: w / dpr,
    height: h / dpr,
  );
}
