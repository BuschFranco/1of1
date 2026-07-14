import 'dart:convert';

import 'package:http/http.dart' as http;

const _kApiKey = String.fromEnvironment('MAPS_API_KEY');

/// Reverse geocoding con la Google Geocoding API (misma MAPS_API_KEY que el
/// mapa; requiere habilitar "Geocoding API" en la consola). Nunca lanza:
/// devuelve null si la API falla o no está habilitada — quien llama degrada a
/// no autocompletar.
class GeocodingService {
  /// Ciudad/localidad de un punto ("Buenos Aires"). Para autocompletar el
  /// campo Ciudad del registro.
  static Future<String?> cityFromLatLng(double lat, double lng) async {
    final comps = await _components(lat, lng);
    if (comps == null) return null;
    return _first(comps, ['locality', 'administrative_area_level_2']) ??
        _first(comps, ['administrative_area_level_1']);
  }

  /// Zona/barrio de un punto ("Palermo, Buenos Aires"). Para el área textual
  /// de una cancha nueva.
  static Future<String?> areaFromLatLng(double lat, double lng) async {
    final comps = await _components(lat, lng);
    if (comps == null) return null;
    final hood = _first(
        comps, ['neighborhood', 'sublocality', 'sublocality_level_1']);
    final city = _first(comps, ['locality', 'administrative_area_level_2']);
    if (hood != null && city != null && hood != city) return '$hood, $city';
    return hood ?? city;
  }

  /// address_components del primer resultado del reverse geocode, o null.
  static Future<List<Map<String, dynamic>>?> _components(
      double lat, double lng) async {
    if (_kApiKey.isEmpty) return null;
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'latlng': '$lat,$lng',
        'language': 'es',
        'key': _kApiKey,
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final results = data['results'] as List? ?? [];
      if (data['status'] != 'OK' || results.isEmpty) return null;
      final comps =
          (results.first as Map<String, dynamic>)['address_components'];
      return (comps as List?)?.cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }

  /// Primer componente cuyo `types` incluya alguno de [types].
  static String? _first(
      List<Map<String, dynamic>> comps, List<String> types) {
    for (final t in types) {
      for (final c in comps) {
        final ct = (c['types'] as List?)?.cast<String>() ?? const [];
        if (ct.contains(t)) {
          final name = (c['long_name'] ?? '') as String;
          if (name.isNotEmpty) return name;
        }
      }
    }
    return null;
  }
}
