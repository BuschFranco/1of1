import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

const _kApiKey = String.fromEnvironment('MAPS_API_KEY');

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
  /// Pide la ruta a la Directions API ([mode] = 'walking' | 'driving').
  /// Nunca lanza: ante cualquier falla devuelve la línea recta origin→dest.
  static Future<RouteResult> fetchRoute({
    required LatLng origin,
    required LatLng dest,
    required String mode,
  }) async {
    final fallback = RouteResult(points: [origin, dest], straightLine: true);
    if (_kApiKey.isEmpty) return fallback;
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
        'origin': '${origin.latitude},${origin.longitude}',
        'destination': '${dest.latitude},${dest.longitude}',
        'mode': mode,
        'language': 'es',
        'key': _kApiKey,
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return fallback;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = data['routes'] as List? ?? [];
      if (data['status'] != 'OK' || routes.isEmpty) return fallback;
      final route = routes.first as Map<String, dynamic>;
      final points =
          _decodePolyline(route['overview_polyline']?['points'] as String? ?? '');
      if (points.length < 2) return fallback;
      final legs = route['legs'] as List? ?? [];
      final leg = legs.isNotEmpty ? legs.first as Map<String, dynamic> : null;
      return RouteResult(
        points: points,
        durationText: leg?['duration']?['text'] as String? ?? '',
        distText: leg?['distance']?['text'] as String? ?? '',
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
