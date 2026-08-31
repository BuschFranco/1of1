import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'api/api_client.dart';

/// Ruta calculada hacia una cancha: puntos para dibujar la polyline y los
/// textos de duración/distancia que devuelve Google ("12 min", "1,3 km").
/// Cuando la Directions API no está disponible cae a línea recta y los textos
/// quedan vacíos (la marca funciona igual, degradada).
class RouteResult {
  final List<LatLng> points;
  final String durationText;
  final String distText;
  final bool straightLine;
  const RouteResult({
    required this.points,
    this.durationText = '',
    this.distText = '',
    this.straightLine = false,
  });
}

class RouteService {
  /// Pide la ruta al backend ([mode] = 'walking' | 'driving'), que a su vez
  /// consulta la Directions API — la app no puede llamar a Google
  /// directamente (mismo motivo que GeocodingService: la MAPS_API_KEY de acá
  /// está restringida al Maps SDK, no sirve para web services). Nunca lanza:
  /// ante cualquier falla (red, backend abajo, Directions sin resultado)
  /// devuelve la línea recta origin→dest.
  static Future<RouteResult> fetchRoute({
    required LatLng origin,
    required LatLng dest,
    required String mode,
  }) async {
    final fallback = RouteResult(points: [origin, dest], straightLine: true);
    try {
      final data = await ApiClient().directions(
        originLat: origin.latitude,
        originLng: origin.longitude,
        destLat: dest.latitude,
        destLng: dest.longitude,
        mode: mode,
      );
      final encoded = (data['points'] ?? '').toString();
      if (encoded.isEmpty) return fallback;
      final points = _decodePolyline(encoded);
      if (points.length < 2) return fallback;
      return RouteResult(
        points: points,
        durationText: (data['durationText'] ?? '').toString(),
        distText: (data['distText'] ?? '').toString(),
      );
    } catch (_) {
      return fallback;
    }
  }

  /// Decodifica el formato "encoded polyline" de Google (deltas en base 5 bits
  /// con signo zig-zag, escala 1e5).
  static List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    int index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      for (var coord = 0; coord < 2; coord++) {
        int shift = 0, result = 0, b;
        do {
          b = encoded.codeUnitAt(index++) - 63;
          result |= (b & 0x1f) << shift;
          shift += 5;
        } while (b >= 0x20 && index < encoded.length);
        final delta = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
        if (coord == 0) {
          lat += delta;
        } else {
          lng += delta;
        }
      }
      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }
}
