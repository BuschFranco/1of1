import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'notifications_service.dart';

/// Permisos que la app necesita para funcionar bien.
enum AppPerm { location, background, notifications, alarm, battery }

/// Canal nativo para consultar/abrir el permiso de alarmas exactas (Android 12+)
/// y la exención de optimización de batería.
const MethodChannel _alarmChannel = MethodChannel('oneofone/alarm_perm');

/// Estado de los permisos clave.
class PermState {
  final bool location; // permiso concedido Y servicio de ubicación encendido
  // Ubicación "Permitir siempre": sin esto Android no entrega geofences ni GPS
  // a los isolates de background — la detección solo funciona con la app
  // abierta. Es LA pieza que hace que los partidos arranquen/cierren solos.
  final bool background;
  final bool notifications;
  final bool alarm; // puede programar alarmas exactas
  // Exención de optimización de batería: sin ella, Samsung/One UI congela o
  // mata el proceso (y el foreground service) en pleno partido.
  final bool battery;

  const PermState({
    required this.location,
    required this.background,
    required this.notifications,
    required this.alarm,
    required this.battery,
  });

  // Ni la batería ni el background cuentan acá: son RECOMENDADOS (sin ellos la
  // detección funciona solo con la app abierta/foreground service) pero no
  // obligatorios. Así el modal no insiste si el usuario los ignora.
  bool get allGranted => location && notifications && alarm;

  List<AppPerm> get missing => [
        if (!location) AppPerm.location,
        if (!background) AppPerm.background,
        if (!notifications) AppPerm.notifications,
        if (!alarm) AppPerm.alarm,
        if (!battery) AppPerm.battery,
      ];
}

Future<bool> _canScheduleExact() async {
  try {
    return (await _alarmChannel.invokeMethod<bool>('canScheduleExact')) ?? true;
  } catch (_) {
    return true; // sin canal (iOS/otros): no bloqueamos por esto
  }
}

Future<bool> _ignoresBatteryOptimizations() async {
  try {
    return (await _alarmChannel
            .invokeMethod<bool>('isIgnoringBatteryOptimizations')) ??
        true;
  } catch (_) {
    return true; // sin canal (iOS/otros): no bloqueamos por esto
  }
}

/// Revisa el estado actual de los permisos.
Future<PermState> checkPermissions() async {
  var loc = false;
  var bg = false;
  try {
    final perm = await Geolocator.checkPermission();
    final service = await Geolocator.isLocationServiceEnabled();
    loc = service &&
        (perm == LocationPermission.always ||
            perm == LocationPermission.whileInUse);
    bg = perm == LocationPermission.always;
  } catch (_) {}
  final notif = await NotificationsService.instance.isEnabled();
  final alarm = await _canScheduleExact();
  final battery = await _ignoresBatteryOptimizations();
  return PermState(
      location: loc,
      background: bg,
      notifications: notif,
      alarm: alarm,
      battery: battery);
}

/// Pide (o guía a activar) la ubicación. Si el servicio está apagado abre sus
/// ajustes; si el permiso quedó denegado permanentemente, abre los ajustes de
/// la app.
Future<void> requestLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings();
      return;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
    }
  } catch (_) {}
}

/// Pide el permiso de ubicación en SEGUNDO PLANO ("Siempre"). En Android 11+ el
/// sistema no lo concede desde un prompt in-app: hay que enviar al usuario a los
/// ajustes de la app. IMPORTANTE: llamar SOLO después de mostrar la divulgación
/// destacada (prominent disclosure) que exige Google Play.
Future<void> requestBackgroundLocation() async {
  try {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    // Si todavía no es "Siempre", guiamos al usuario a los ajustes del sistema
    // (donde puede elegir "Permitir todo el tiempo").
    if (perm != LocationPermission.always) {
      await Geolocator.openAppSettings();
    }
  } catch (_) {}
}

/// Pide las notificaciones; si ya estaban denegadas, abre los ajustes de la app.
Future<void> requestNotifications() async {
  await NotificationsService.instance.requestPermission();
  if (!await NotificationsService.instance.isEnabled()) {
    try {
      await Geolocator.openAppSettings();
    } catch (_) {}
  }
}

/// Abre la pantalla del sistema para conceder alarmas exactas.
Future<void> requestAlarm() async {
  try {
    await _alarmChannel.invokeMethod('openExactSettings');
  } catch (_) {}
}

/// Pide la exención de optimización de batería (diálogo del sistema).
Future<void> requestBattery() async {
  try {
    await _alarmChannel.invokeMethod('requestIgnoreBatteryOptimizations');
  } catch (_) {}
}

/// Abre la pantalla de Health Connect (fallback manual para conceder los
/// permisos de salud si el diálogo in-app no aparece).
Future<void> openHealthConnect() async {
  try {
    await _alarmChannel.invokeMethod('openHealthConnect');
  } catch (_) {}
}

/// Dispara la acción de activación del permiso dado.
Future<void> requestPerm(AppPerm p) async {
  switch (p) {
    case AppPerm.location:
      await requestLocation();
      break;
    case AppPerm.background:
      await requestBackgroundLocation();
      break;
    case AppPerm.notifications:
      await requestNotifications();
      break;
    case AppPerm.alarm:
      await requestAlarm();
      break;
    case AppPerm.battery:
      await requestBattery();
      break;
  }
}
