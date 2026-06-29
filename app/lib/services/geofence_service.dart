import 'dart:isolate';
import 'dart:ui';
import 'package:native_geofence/native_geofence.dart';
import '../data/courts.dart';
import 'notifications_service.dart';

/// Radio (m) de cada geofence de cancha. Igual al de la detección por dwell.
const double kCourtGeofenceRadius = 80;

/// Nombre del puerto con el que el isolate principal recibe los eventos de
/// geofence desde el isolate de background.
const String kGeofencePortName = 'oneofone_geofence_port';

/// Callback de geofence. Corre en un ISOLATE DE BACKGROUND, incluso con la app
/// cerrada. Si la app está viva, reenvía el evento al isolate principal (que
/// arranca/corta el tracking). Si está muerta, dispara una notificación local
/// para que el usuario abra la app y registre su partido.
@pragma('vm:entry-point')
Future<void> geofenceTriggered(GeofenceCallbackParams params) async {
  final ids = params.geofences.map((g) => g.id).toList();
  final send = IsolateNameServer.lookupPortByName(kGeofencePortName);
  if (send != null) {
    // App viva: que el isolate principal maneje enter/exit.
    send.send(<String, dynamic>{'event': params.event.name, 'ids': ids});
    return;
  }
  // App cerrada: avisar al usuario al ENTRAR a una cancha.
  if (params.event == GeofenceEvent.enter) {
    await NotificationsService.instance.show(
      'Estás en una cancha',
      'Abrí 1of1 para registrar tu partido.',
    );
  }
}

/// Registra/quita geofences de las canchas en el SO (Google Play Services /
/// CoreLocation). El SO vigila las zonas sin mantener la app viva ni una
/// notificación persistente; solo despierta la app al cruzar un borde.
class GeofenceService {
  GeofenceService._();
  static final GeofenceService instance = GeofenceService._();

  bool _ready = false;
  ReceivePort? _port;

  /// Se dispara en el isolate principal con cada enter/exit (cuando la app está
  /// viva). [courtIds] son los ids de las canchas involucradas.
  void Function(GeofenceEvent event, List<String> courtIds)? onEvent;

  Future<void> init() async {
    if (_ready) return;
    // Puerto para recibir eventos del isolate de background.
    IsolateNameServer.removePortNameMapping(kGeofencePortName);
    _port = ReceivePort();
    IsolateNameServer.registerPortWithName(_port!.sendPort, kGeofencePortName);
    _port!.listen((msg) {
      if (msg is! Map) return;
      final ev = GeofenceEvent.values.firstWhere(
        (e) => e.name == msg['event'],
        orElse: () => GeofenceEvent.enter,
      );
      final ids = (msg['ids'] as List).map((e) => e.toString()).toList();
      onEvent?.call(ev, ids);
    });
    try {
      await NativeGeofenceManager.instance.initialize();
      _ready = true;
    } catch (_) {/* sin geofencing: la app sigue con detección en foreground */}
  }

  /// Registra geofences para las canchas con coordenadas (máx 95, margen del
  /// límite de 100 de Android). Reemplaza las anteriores.
  Future<void> syncCourts(List<Court> courts) async {
    if (!_ready) await init();
    if (!_ready) return;
    final withCoords =
        courts.where((c) => !(c.lat == 0 && c.lng == 0)).take(95).toList();
    try {
      await NativeGeofenceManager.instance.removeAllGeofences();
      for (final c in withCoords) {
        await NativeGeofenceManager.instance.createGeofence(
          Geofence(
            id: c.id,
            location: Location(latitude: c.lat, longitude: c.lng),
            radiusMeters: kCourtGeofenceRadius,
            triggers: const {GeofenceEvent.enter, GeofenceEvent.exit},
            iosSettings: const IosGeofenceSettings(initialTrigger: true),
            androidSettings: const AndroidGeofenceSettings(
              initialTriggers: {GeofenceEvent.enter},
              expiration: Duration(days: 365),
              notificationResponsiveness: Duration(minutes: 1),
            ),
          ),
          geofenceTriggered,
        );
      }
    } catch (_) {/* ignorar: best-effort */}
  }

  /// Quita todas las geofences (al desactivar la detección en background).
  Future<void> clear() async {
    if (!_ready) return;
    try {
      await NativeGeofenceManager.instance.removeAllGeofences();
    } catch (_) {/* ignorar */}
  }
}
