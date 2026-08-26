import 'api/api_client.dart';

/// Reverse geocoding (punto → barrio/ciudad) **vía el backend**, no contra
/// Google directamente. Nunca lanza: devuelve null si falla, y quien llama
/// degrada a no autocompletar.
///
/// Antes pegaba a la Geocoding API con la `MAPS_API_KEY` de la app y **fallaba
/// siempre**: esa key está restringida a la app Android (package + firma), y esa
/// restricción no aplica a los web services — la llamada REST llega con IP y sin
/// firma, así que Google respondía REQUEST_DENIED. El resultado era un campo de
/// zona que no se completaba nunca, en silencio.
///
/// Ahora la key vive en el backend (`GeoModule`), donde puede estar sin
/// restricción de app sin quedar expuesta en el APK.
class GeocodingService {
  /// Ciudad/localidad de un punto ("Buenos Aires"). Para autocompletar el
  /// campo Ciudad del registro.
  static Future<String?> cityFromLatLng(double lat, double lng) async =>
      _field(lat, lng, 'city');

  /// Zona/barrio de un punto ("Palermo, Buenos Aires"). Para el área textual
  /// de una cancha nueva.
  static Future<String?> areaFromLatLng(double lat, double lng) async =>
      _field(lat, lng, 'area');

  static Future<String?> _field(double lat, double lng, String key) async {
    try {
      final data = await ApiClient().reverseGeo(lat, lng);
      final v = (data[key] ?? '').toString().trim();
      return v.isEmpty ? null : v;
    } catch (_) {
      return null;
    }
  }
}
