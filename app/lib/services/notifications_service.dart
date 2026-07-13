import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Id de la acción "EMPEZAR YA" del cronómetro en la notificación de sesión.
const String kStartNowAction = 'start_now';

/// Id de la acción "DETENER" (cierra el partido en curso manualmente).
const String kStopAction = 'stop_now';

/// Id de la acción "PAUSAR/REANUDAR" (alterna la pausa del cronómetro).
const String kPauseAction = 'toggle_pause';

/// Handler de respuestas que corre en un ISOLATE DE BACKGROUND (app cerrada).
/// No puede tocar el estado vivo del partido, así que es un no-op: la acción
/// "EMPEZAR YA" solo arranca el partido con el proceso vivo (app minimizada).
@pragma('vm:entry-point')
void notificationBackgroundHandler(NotificationResponse response) {}

/// Notificaciones locales del sistema. Dos usos:
///  - Recompensas (logro/título/nivel) y eventos puntuales de partido.
///  - Notificación de SESIÓN persistente: con la app minimizada muestra la
///    cuenta regresiva de los 7 min (con botón "EMPEZAR YA") y, ya jugando, el
///    tiempo del partido en curso. Usa el cronómetro nativo de Android, que
///    corre solo sin que la app actualice cada segundo.
class NotificationsService {
  NotificationsService._();
  static final NotificationsService instance = NotificationsService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _nextId = 0;

  /// Id fijo de la notificación de sesión (se reemplaza en cada cambio de
  /// estado: dwell → jugando → limpia).
  static const int _sessionId = 100000;

  /// Lo invoca el handler de la acción "EMPEZAR YA" (con el proceso vivo). Lo
  /// cablea SyncCoordinator para llamar a `PlaySessionService.startNow()`.
  VoidCallback? onStartNowAction;

  /// Lo invoca el handler de la acción "DETENER". Lo cablea SyncCoordinator
  /// para llamar a `PlaySessionService.stopNow()`.
  VoidCallback? onStopAction;

  /// Lo invoca el handler de la acción "PAUSAR/REANUDAR". Lo cablea
  /// SyncCoordinator para llamar a `PlaySessionService.togglePause()`.
  VoidCallback? onPauseAction;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'rewards',
    'Recompensas',
    description: 'Logros, títulos y subidas de nivel',
    importance: Importance.high,
  );

  // Canal de la notificación de sesión: importancia baja para que no suene ni
  // vibre en cada actualización (es persistente, no un aviso puntual).
  static const AndroidNotificationChannel _sessionChannel =
      AndroidNotificationChannel(
    'session',
    'Partido en curso',
    description: 'Cronómetro de la cancha y del partido',
    importance: Importance.low,
  );

  void _onResponse(NotificationResponse response) {
    if (response.actionId == kStartNowAction) onStartNowAction?.call();
    if (response.actionId == kStopAction) onStopAction?.call();
    if (response.actionId == kPauseAction) onPauseAction?.call();
  }

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
        onDidReceiveNotificationResponse: _onResponse,
        onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
      );
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_channel);
      await android?.createNotificationChannel(_sessionChannel);
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

  /// True si la app tiene las notificaciones habilitadas por el SO. Sirve para
  /// decidir si hace falta volver a pedir el permiso (y para diagnóstico).
  Future<bool> isEnabled() async {
    if (!_ready) await init();
    if (!_ready) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        return (await android.areNotificationsEnabled()) ?? false;
      }
    } catch (_) {/* ignorar */}
    return true; // iOS u otra plataforma: asumimos habilitado.
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

  /// Notificación de sesión en estado "cuenta regresiva": muestra cuánto falta
  /// para que arranque el partido (cronómetro nativo que baja solo hasta
  /// [endsAt]) y un botón "EMPEZAR YA". Persistente (ongoing).
  Future<void> showDwellCountdown(String court, int remainingSeconds) async {
    if (!_ready) await init();
    if (!_ready) return;
    // Solo un mensaje, sin contador.
    const body = 'Tu partido va a arrancar solo';
    try {
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          'session',
          'Partido en curso',
          channelDescription: 'Cronómetro de la cancha y del partido',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          // Ocultamos el contenido (nombre de cancha = ubicación del usuario) en
          // la pantalla bloqueada; visible al desbloquear.
          visibility: NotificationVisibility.private,
          actions: const <AndroidNotificationAction>[
            // showsUserInterface: true → abre la app y ejecuta la acción en el
            // isolate principal (el handler de background es no-op y no puede
            // tocar el partido en curso).
            AndroidNotificationAction(kStartNowAction, 'EMPEZAR YA',
                showsUserInterface: true, cancelNotification: false),
          ],
        ),
      );
      await _plugin.show(
        _sessionId,
        court.isEmpty ? 'Estás en una cancha' : 'Estás en $court',
        body,
        details,
      );
    } catch (_) {/* ignorar */}
  }

  /// Notificación de sesión en estado "jugando": cronómetro nativo contando
  /// hacia arriba desde [startedAt]. Persistente.
  Future<void> showPlaying(String court, DateTime startedAt) async {
    if (!_ready) await init();
    if (!_ready) return;
    try {
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          'session',
          'Partido en curso',
          channelDescription: 'Cronómetro de la cancha y del partido',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          // Ocultamos el contenido (nombre de cancha = ubicación del usuario) en
          // la pantalla bloqueada; visible al desbloquear.
          visibility: NotificationVisibility.private,
          actions: const <AndroidNotificationAction>[
            // Todas abren la app: la acción en background es un no-op (corre en
            // un isolate aparte, sin acceso al partido vivo).
            AndroidNotificationAction(kPauseAction, 'PAUSAR',
                showsUserInterface: true, cancelNotification: false),
            AndroidNotificationAction(kStopAction, 'DETENER',
                showsUserInterface: true, cancelNotification: false),
          ],
        ),
      );
      await _plugin.show(
        _sessionId,
        court.isEmpty ? 'Jugando' : 'Jugando en $court',
        'Partido en curso',
        details,
      );
    } catch (_) {/* ignorar */}
  }

  /// Notificación de sesión en estado "pausado": tiempo congelado (sin
  /// cronómetro) y botón "REANUDAR" (+ "DETENER").
  Future<void> showPaused(String court, int elapsedSeconds) async {
    if (!_ready) await init();
    if (!_ready) return;
    try {
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          'session',
          'Partido en curso',
          channelDescription: 'Cronómetro de la cancha y del partido',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          // Ocultamos el contenido (nombre de cancha = ubicación del usuario) en
          // la pantalla bloqueada; visible al desbloquear.
          visibility: NotificationVisibility.private,
          actions: const <AndroidNotificationAction>[
            // Todas abren la app (ver nota en showPlaying).
            AndroidNotificationAction(kPauseAction, 'REANUDAR',
                showsUserInterface: true, cancelNotification: false),
            AndroidNotificationAction(kStopAction, 'DETENER',
                showsUserInterface: true, cancelNotification: false),
          ],
        ),
      );
      await _plugin.show(
        _sessionId,
        court.isEmpty ? 'Partido pausado' : 'Pausado · $court',
        'Partido en pausa',
        details,
      );
    } catch (_) {/* ignorar */}
  }

  /// Notificación de sesión en estado "saliste del radio": cronómetro nativo
  /// que baja hasta [endsAt] (cuando se cierra solo) y botón "DETENER".
  Future<void> showEndingCountdown(String court, DateTime endsAt) async {
    if (!_ready) await init();
    if (!_ready) return;
    try {
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          'session',
          'Partido en curso',
          channelDescription: 'Cronómetro de la cancha y del partido',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          // Ocultamos el contenido (nombre de cancha = ubicación del usuario) en
          // la pantalla bloqueada; visible al desbloquear.
          visibility: NotificationVisibility.private,
          actions: const <AndroidNotificationAction>[
            AndroidNotificationAction(
              kStopAction,
              'DETENER',
              showsUserInterface: true,
              cancelNotification: false,
            ),
          ],
        ),
      );
      await _plugin.show(
        _sessionId,
        court.isEmpty ? 'Saliste de la cancha' : 'Saliste de $court',
        'Si no volvés, el partido se cierra solo',
        details,
      );
    } catch (_) {/* ignorar */}
  }

  /// Quita la notificación de sesión (al volver a la app o terminar el partido).
  Future<void> cancelSession() async {
    if (!_ready) return;
    try {
      await _plugin.cancel(_sessionId);
    } catch (_) {/* ignorar */}
  }
}
