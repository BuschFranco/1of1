import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Id de la acción "EMPEZAR YA" del cronómetro en la notificación de sesión.
const String kStartNowAction = 'start_now';

/// Id de la acción "DETENER" (cierra el partido en curso manualmente).
const String kStopAction = 'stop_now';

/// Id de la acción "PAUSAR/REANUDAR" (alterna la pausa del cronómetro).
const String kPauseAction = 'toggle_pause';

/// Id de la acción "NO JUEGO" (declina la cuenta regresiva y silencia el
/// detector de esa cancha por una hora).
const String kDeclineAction = 'decline_dwell';

/// Id de la acción "SÍ, SIGO" de la pregunta de partido largo (2h): reanuda
/// el partido con una hora extra como máximo.
const String kConfirmYesAction = 'confirm_yes';

/// Id de la acción "NO, TERMINÉ" de la pregunta de partido largo: cierra el
/// partido con el tiempo congelado en el momento de la pregunta.
const String kConfirmNoAction = 'confirm_no';

/// Id de la acción "Ir al chat" de las notificaciones de pickup (crear/unirse).
const String kOpenPickupChatAction = 'open_pickup_chat';

/// Prefijo del payload que lleva el id del pickup para enrutar al chat.
const String kPickupChatPayload = 'pickup_chat:';

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

  /// Id fijo de la pregunta "¿Seguís jugando?" (partido largo). Fijo para
  /// poder cancelarla al responder / al vencer el timeout.
  static const int _confirmId = 100001;

  /// Lo invoca el handler de la acción "EMPEZAR YA" (con el proceso vivo). Lo
  /// cablea SyncCoordinator para llamar a `PlaySessionService.startNow()`.
  VoidCallback? onStartNowAction;

  /// Lo invoca el handler de la acción "DETENER". Lo cablea SyncCoordinator
  /// para llamar a `PlaySessionService.stopNow()`.
  VoidCallback? onStopAction;

  /// Lo invoca el handler de la acción "PAUSAR/REANUDAR". Lo cablea
  /// SyncCoordinator para llamar a `PlaySessionService.togglePause()`.
  VoidCallback? onPauseAction;

  /// Lo invoca el handler de la acción "NO JUEGO". Lo cablea SyncCoordinator
  /// para llamar a `PlaySessionService.declineDwell()`.
  VoidCallback? onDeclineAction;

  /// Lo invoca el handler de "SÍ, SIGO" (pregunta de partido largo). Lo cablea
  /// SyncCoordinator para llamar a `PlaySessionService.confirmContinue()`.
  VoidCallback? onConfirmYesAction;

  /// Lo invoca el handler de "NO, TERMINÉ". Lo cablea SyncCoordinator para
  /// llamar a `PlaySessionService.confirmStop()`.
  VoidCallback? onConfirmNoAction;

  /// Se invoca al tocar una notificación de pickup (o su botón "Ir al chat").
  /// Lo cablea main.dart para navegar al chat del pickup por su id. Al asignarlo
  /// se drena cualquier pickup pendiente (app abierta desde la notificación).
  void Function(String pickupId)? get onOpenPickupChat => _onOpenPickupChat;
  void Function(String pickupId)? _onOpenPickupChat;
  set onOpenPickupChat(void Function(String pickupId)? cb) {
    _onOpenPickupChat = cb;
    final pending = _pendingChatPickupId;
    if (cb != null && pending != null) {
      _pendingChatPickupId = null;
      cb(pending);
    }
  }

  /// Id de pickup capturado del lanzamiento de la app desde una notificación
  /// (app cerrada). Se drena cuando se cablea [onOpenPickupChat].
  String? _pendingChatPickupId;

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
    if (response.actionId == kDeclineAction) onDeclineAction?.call();
    if (response.actionId == kConfirmYesAction) onConfirmYesAction?.call();
    if (response.actionId == kConfirmNoAction) onConfirmNoAction?.call();
    // Pickup: tap del cuerpo (actionId null) o botón "Ir al chat".
    final payload = response.payload;
    if (payload != null &&
        payload.startsWith(kPickupChatPayload) &&
        (response.actionId == null ||
            response.actionId == kOpenPickupChatAction)) {
      final id = payload.substring(kPickupChatPayload.length);
      if (id.isNotEmpty) {
        final cb = _onOpenPickupChat;
        // Sin listener aún (app recién abierta): lo dejamos pendiente.
        if (cb != null) {
          cb(id);
        } else {
          _pendingChatPickupId = id;
        }
      }
    }
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
      // App abierta desde una notificación de pickup (proceso estaba muerto):
      // capturamos el id para enrutar al chat en cuanto se cablee el listener.
      try {
        final launch = await _plugin.getNotificationAppLaunchDetails();
        final payload = launch?.notificationResponse?.payload;
        if (launch?.didNotificationLaunchApp == true &&
            payload != null &&
            payload.startsWith(kPickupChatPayload)) {
          final id = payload.substring(kPickupChatPayload.length);
          if (id.isNotEmpty) _pendingChatPickupId = id;
        }
      } catch (_) {/* ignorar */}
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

  /// Notificación de pickup (crear/unirse) con botón "Ir al chat" que abre el
  /// chat del pickup [pickupId]. El payload permite enrutar tanto desde el botón
  /// como al tocar el cuerpo de la notificación.
  Future<void> showPickupChat(
      String title, String body, String pickupId) async {
    if (!_ready) await init();
    if (!_ready || pickupId.isEmpty) return;
    try {
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'rewards',
          'Recompensas',
          channelDescription: 'Logros, títulos y subidas de nivel',
          importance: Importance.high,
          priority: Priority.high,
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction(kOpenPickupChatAction, 'Ir al chat',
                showsUserInterface: true, cancelNotification: true),
          ],
        ),
        iOS: DarwinNotificationDetails(),
      );
      await _plugin.show(
        _nextId++,
        title,
        body,
        details,
        payload: '$kPickupChatPayload$pickupId',
      );
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
            AndroidNotificationAction(kDeclineAction, 'NO JUEGO',
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

  /// Pregunta "¿Seguís jugando?" del partido largo (2h). Va por el canal de
  /// recompensas (importancia alta: DEBE sonar — la de sesión es silenciosa y
  /// pasarla por alto termina en una cancelación injusta a los 20 min). Botones
  /// SÍ/NO que abren la app y responden en el isolate principal.
  Future<void> showContinueCheck(String court) async {
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
          autoCancel: false,
          // Igual que la notif de sesión: la cancha revela dónde estás.
          visibility: NotificationVisibility.private,
          actions: <AndroidNotificationAction>[
            // Ambas abren la app (el handler de background es no-op) y la
            // notif se descarta sola al responder.
            AndroidNotificationAction(kConfirmYesAction, 'SÍ, SIGO',
                showsUserInterface: true, cancelNotification: true),
            AndroidNotificationAction(kConfirmNoAction, 'NO, TERMINÉ',
                showsUserInterface: true, cancelNotification: true),
          ],
        ),
        iOS: DarwinNotificationDetails(),
      );
      await _plugin.show(
        _confirmId,
        court.isEmpty ? '¿Seguís jugando?' : '¿Seguís jugando en $court?',
        'Pausamos tu partido a las 2 horas. Si no respondés en 20 minutos, '
            'lo cancelamos.',
        details,
      );
    } catch (_) {/* ignorar */}
  }

  /// Quita la pregunta de partido largo (respondida, vencida o reconciliada).
  Future<void> cancelContinueCheck() async {
    if (!_ready) await init();
    if (!_ready) return;
    try {
      await _plugin.cancel(_confirmId);
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
