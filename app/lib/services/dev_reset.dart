import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api/api_config.dart';
import 'cache/api_cache.dart';
import 'cache/court_image_cache.dart';
import 'geofence_service.dart';
import 'session_alarms.dart';

/// Herramienta de ADMIN (botón de debug del mapa): borra lo que la app guarda
/// en el celu y la reinicia, para probar de nuevo lo que sale "una sola vez"
/// (bienvenida, permisos, tours, onboarding, restore del historial).
///
/// Lo que NO toca: los permisos del sistema (ubicación, notificaciones, Health
/// Connect) — esos son del SO y se resetean desde los ajustes del teléfono —
/// ni nada del servidor.
Future<void> wipeLocalDataAndRestart({required bool keepSession}) async {
  final prefs = await SharedPreferences.getInstance();

  // Claves de la sesión de cuenta (mismas que Session y ApiConfig): si se
  // conservan, la app reabre logueada y solo se pierde lo local.
  const sessionKeys = [
    ApiConfig.jwtPrefsKey,
    'session_email',
    'session_profile',
    'session_persist',
  ];
  final kept = <String, Object>{};
  if (keepSession) {
    for (final k in sessionKeys) {
      final v = prefs.get(k);
      if (v != null) kept[k] = v;
    }
  }

  // El background sigue programado aunque se borren las prefs: apagarlo antes,
  // así ninguna alarma corre a mitad del borrado con estado a medias.
  await cancelAllPlayAlarms();
  GeofenceService.instance.clear();

  await prefs.clear();
  for (final e in kept.entries) {
    final v = e.value;
    if (v is String) await prefs.setString(e.key, v);
    if (v is bool) await prefs.setBool(e.key, v);
  }

  ApiCache.clear();
  try {
    await courtImageCache.emptyCache();
    await DefaultCacheManager().emptyCache();
  } catch (_) {/* sin caché que borrar */}

  // Reinicio real del proceso (lo hace la Activity): todo lo que vive en
  // memoria (providers, isolates) arranca de cero.
  await const MethodChannel('oneofone/alarm_perm').invokeMethod('restartApp');
}
