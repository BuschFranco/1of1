import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notificaciones locales del sistema (logro/título/nivel). Las dispara la app
/// cuando detecta un desbloqueo; aparecen aunque esté minimizada (el proceso
/// sigue vivo durante el juego por el foreground service de ubicación).
class NotificationsService {
  NotificationsService._();
  static final NotificationsService instance = NotificationsService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _nextId = 0;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'rewards',
    'Recompensas',
    description: 'Logros, títulos y subidas de nivel',
    importance: Importance.high,
  );

  /// Inicializa el plugin y crea el canal Android. Idempotente. Best-effort:
  /// si algo falla, deja [_ready] en false y la app sigue sin push.
  Future<void> init() async {
    if (_ready) return;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      // En iOS pedimos permisos aparte (requestPermission), no en el init.
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
      _ready = true;
    } catch (_) {/* sin push: la app sigue con el banner in-app */}
  }

  /// Pide permiso de notificaciones (Android 13+ / iOS). Seguro de llamar varias
  /// veces: el SO solo pregunta una vez.
  Future<void> requestPermission() async {
    if (!_ready) await init();
    if (!_ready) return;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (_) {/* ignorar */}
  }

  /// Muestra una notificación inmediata. Best-effort.
  Future<void> show(String title, String body) async {
    if (!_ready) await init();
    if (!_ready) return;
    try {
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'rewards',
          'Recompensas',
          channelDescription: 'Logros, títulos y subidas de nivel',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      );
      await _plugin.show(_nextId++, title, body, details);
    } catch (_) {/* ignorar */}
  }
}
