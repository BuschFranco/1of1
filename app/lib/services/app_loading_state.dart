import 'package:flutter/foundation.dart';

/// Estado de carga inicial de la app (mapa + GPS). Lo consume el loader del
/// [MainShell] para saber cuándo hacer el fade out. Las canchas se miran aparte
/// vía `CourtsProvider.loading`.
class AppLoadingState extends ChangeNotifier {
  bool _mapReady = false;
  bool _gpsReady = false;

  bool get mapReady => _mapReady;
  bool get gpsReady => _gpsReady;

  /// El mapa terminó de crearse (onMapCreated). Idempotente.
  void markMapReady() {
    if (_mapReady) return;
    _mapReady = true;
    notifyListeners();
  }

  /// Se obtuvo (o se descartó por permiso) el primer punto GPS. Idempotente.
  /// Se llama también cuando el permiso se deniega para no bloquear el loader.
  void markGpsReady() {
    if (_gpsReady) return;
    _gpsReady = true;
    notifyListeners();
  }
}
