import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Distancia en metros desde una posición hasta un punto (null si no hay fix).
double? metersTo(Position? p, double lat, double lng) {
  if (p == null) return null;
  return Geolocator.distanceBetween(p.latitude, p.longitude, lat, lng);
}

/// Formatea metros para mostrar: "350 m", "1.2 km", "12 km".
String formatDist(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  final km = meters / 1000;
  if (km >= 10) return '${km.round()} km';
  return '${km.toStringAsFixed(1)} km';
}

/// Última posición conocida del usuario, compartida entre pantallas.
/// La alimenta el stream de ubicación del mapa (home); las demás pantallas
/// (canchas, detalle) solo la leen para calcular distancias reales.
class LocationService extends ChangeNotifier {
  Position? _last;
  Position? get last => _last;

  /// Actualiza la posición; notifica solo si se movió lo suficiente como para
  /// que cambien las distancias mostradas (evita rebuilds por cada fix).
  void update(Position p) {
    final prev = _last;
    _last = p;
    if (prev == null ||
        Geolocator.distanceBetween(
                prev.latitude, prev.longitude, p.latitude, p.longitude) >
            20) {
      notifyListeners();
    }
  }

  /// Precarga la última posición que conozca el sistema, sin pedir permisos.
  Future<void> warmUp() async {
    if (_last != null) return;
    final perm = await Geolocator.checkPermission();
    if (perm != LocationPermission.always &&
        perm != LocationPermission.whileInUse) {
      return;
    }
    final p = await Geolocator.getLastKnownPosition();
    if (p != null && _last == null) {
      _last = p;
      notifyListeners();
    }
  }
}
