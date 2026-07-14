import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/achievements.dart';
import '../data/courts.dart';
import '../notion/notion_config.dart';
import '../theme/app_theme.dart';
import 'health_service.dart';
import 'session_alarms.dart';

/// Detecta automáticamente cuándo el usuario está "jugando" en una cancha:
/// si permanece dentro de [radiusMeters] de una cancha durante [dwellThreshold],
/// arranca un contador; cuando sale del radio, el contador termina.
///
/// Fase 1 (foreground): muestrea la ubicación cada [_sampleEvery] mientras la
/// app está abierta. El tiempo activo se persiste cada 60s para no perderlo.
class PlaySessionService extends ChangeNotifier with WidgetsBindingObserver {
  static const double radiusMeters = 110;
  static const Duration dwellThreshold = Duration(minutes: 6);
  // "No juego": al declinar la cuenta regresiva, el detector de ESA cancha
  // queda silenciado por este tiempo (mientras sigas dentro del radio).
  static const Duration dwellSnooze = Duration(hours: 1);
  // El snooze se limpia solo si venís leyendo FUERA del radio de la cancha
  // silenciada de forma continua por este tiempo (más tolerante que
  // gpsJitterGrace: un salto de GPS no debe revivir el banner, que es justo lo
  // que "No juego" quiere evitar).
  static const Duration snoozeExitClear = Duration(minutes: 2);
  // Tolerancia a saltos de GPS: al salir del radio (durante la cuenta de inicio)
  // o al re-entrar (durante la cuenta de cierre), esperamos este tiempo continuo
  // antes de resetear/cancelar, para que un salto accidental no reinicie nada.
  // 15s cubre una lectura de GPS perdida (el muestreo en background es ~10s).
  static const Duration gpsJitterGrace = Duration(seconds: 15);
  // Si al reabrir la app el "latido" del partido es más viejo que esto, asumimos
  // que el proceso estuvo caído (apagado / kill) y guardamos el partido con el
  // tiempo jugado hasta ese latido, en vez de resumirlo con tiempo inflado.
  static const Duration resumeGapMax = Duration(minutes: 3);
  // Período de gracia de salida: con una sesión activa, el partido NO se corta
  // apenas el GPS te ubica fuera del radio. Recién se cierra si seguís fuera de
  // forma continua durante este tiempo (tolera saltos de señal y pausas cortas).
  static const Duration exitGrace = Duration(minutes: 6);
  // La notificación de "saliste de la cancha / termina en…" recién se muestra
  // cuando quedan estos minutos o menos de la gracia de salida. Antes de eso, la
  // notif sigue mostrando el partido en curso (no molesta apenas te movés).
  // GEMELA: session_alarms._kEndNotifLead (la alarma de aviso en background usa
  // el mismo lead; si cambiás una, cambiá la otra).
  static const Duration endNotifLeadTime = Duration(minutes: 3);
  // Duración mínima para que un partido cuente. Por debajo de esto asumimos que
  // se canceló (no suma puntos, ni tiempo, ni jugadas, ni entra al historial).
  static const Duration minMatch = Duration(minutes: 13);
  // Multiplicador de puntos por duración: incentiva partidos largos. Crece
  // lineal desde x1.0 al empezar hasta [maxMultiplier] al llegar a [multiplierCap].
  static const Duration multiplierCap = Duration(minutes: 90);
  static const double maxMultiplier = 1.8;
  // El tiempo deja de sumar puntos a partir de acá (~2h, un partido
  // profesional). Cap silencioso: no se muestra en la UI. Es TAMBIÉN el
  // umbral de la pregunta de partido largo ("¿Seguís jugando?"): mismo
  // trigger, un solo número.
  static const Duration pointsTimeCap = Duration(hours: 2);
  // Pregunta de partido largo: al llegar a [pointsTimeCap] de juego neto se
  // pausa el cronómetro y se pregunta si el partido sigue. Sin respuesta en
  // [confirmTimeout] se cancela POR COMPLETO (sin puntos ni historial); con
  // "SÍ" hay [overtimeMax] extra y a las 3h netas se cierra y guarda solo.
  // GEMELAS: session_alarms._kConfirmAfter / _kConfirmTimeout.
  static const Duration confirmTimeout = Duration(minutes: 20);
  static const Duration overtimeMax = Duration(hours: 1);
  // Con la batería en este nivel (o menos) y sin cargar, cerramos el partido en
  // curso para proteger la información antes de que el SO mate la app.
  static const int batteryEndPercent = 5;
  static const Duration _sampleEvery = Duration(seconds: 10);
  // Cada cuánto se suben los agregados a Notion (batch). El historial y los
  // favoritos NO se suben: quedan locales.
  static const Duration _syncEvery = Duration(minutes: 2);
  // Identidad del usuario actual para "namespacing" de las claves locales.
  // Vacío = sin sesión. Garantiza que los datos (puntos, logros, historial…) de
  // una cuenta no se mezclen con los de otra en el mismo dispositivo, ni se
  // suban al perfil equivocado en el batch.
  String _userKey = '';
  String _k(String base) => _userKey.isEmpty ? base : '$base::$_userKey';

  String get _kActive => _k('play_active_session');
  String get _kDwellSnooze => _k('play_dwell_snooze');
  String get _kTotals => _k('play_totals_by_court');
  String get _kBackground => _k('play_background_enabled');
  String get _kPlays => _k('play_total_count');
  String get _kLog => _k('play_log');
  String get _kPending => _k('play_pending_result');
  String get _kStreak => _k('play_streak');
  String get _kStreakHist => _k('play_streak_history');
  String get _kPoints => _k('play_points');
  String get _kBadges => _k('play_unlocked_badges');
  String get _kNotifs => _k('reward_notifications');
  String get _kCalRecord => _k('play_calorie_record');
  String get _kHealthEnabled => _k('play_health_enabled');
  // Buffer de partidos pendientes de subir a la DB "Partidos" de Notion. Se
  // sube en lote en el flush (mala señal en la cancha = reintento, sin perder
  // el registro). Ver SyncCoordinator._flushPendingMatches.
  String get _kPendingMatches => _k('pending_matches');

  List<Court> _courts = const [];
  Timer? _ticker;
  StreamSubscription<Position>? _posSub;
  // Puerto para que el isolate de las alarmas (arranque/cierre en background)
  // le avise a este isolate que reconcilie el estado desde prefs.
  ReceivePort? _playPort;
  // Batería: para cerrar el partido si el equipo queda con muy poca carga.
  final Battery _battery = Battery();
  bool _batteryChecking = false;
  bool _background = false;

  /// Si el usuario habilitó la detección en segundo plano.
  bool get backgroundEnabled => _background;

  /// Notifica cuando empieza/termina un partido, para propagar la presencia
  /// (ej. actualizar el estado "Jugando" en Notion vía Session).
  void Function(bool playing, String courtId, DateTime? since)? onPresenceChanged;

  /// Terminó un partido válido (>= [minMatch]) que queda pendiente de resultado.
  /// Incluye la cancha, el momento de fin (para el "último partido") y si se
  /// cerró por batería baja (para avisar distinto).
  void Function(String courtId, DateTime endedAt, bool lowBattery)? onMatchEnded;

  /// Se descartó un partido por durar menos de [minMatch]: no se registró nada.
  void Function(String courtName, int seconds)? onMatchDiscarded;

  /// Mostrar la pregunta "¿Seguís jugando?" del partido largo (2h). La cablea
  /// SyncCoordinator a NotificationsService.showContinueCheck.
  void Function(String courtName)? onConfirmNotif;

  /// Quitar la pregunta (respondida, vencida o reconciliada).
  VoidCallback? onCancelConfirmNotif;

  /// Aviso visible genérico (título + cuerpo) para los desenlaces del partido
  /// largo: "llegaste al tiempo límite" y "cancelado por no responder".
  void Function(String title, String body)? onNoticeNotif;

  // ── Notificación de sesión (cronómetro persistente con la app minimizada) ──
  // La capa de notificaciones implementa el "cómo"; acá solo decidimos el qué y
  // el cuándo. Solo se muestra con la app en segundo plano: en foreground manda
  // el banner in-app.
  /// Mostrar la cuenta regresiva (cancha, momento en que arranca el partido).
  void Function(String courtName, int remainingSeconds)? onDwellNotif;

  /// Mostrar el partido en curso (cancha, momento de inicio).
  void Function(String courtName, DateTime startedAt)? onPlayingNotif;

  /// Mostrar la cuenta regresiva de cierre (saliste del radio): cancha y momento
  /// en que el partido se cierra solo.
  void Function(String courtName, DateTime endsAt)? onEndingNotif;

  /// Mostrar el partido pausado (cancha + segundos congelados).
  void Function(String courtName, int elapsedSeconds)? onPausedNotif;

  /// Quitar la notificación de sesión.
  VoidCallback? onClearSessionNotif;

  // Si la app está en primer plano (no mostramos la notif de sesión en ese caso).
  bool _foreground = true;

  /// Vuelve a dibujar (o limpia) la notificación de sesión según el estado
  /// actual. En primer plano siempre la limpia.
  void _renderSessionNotif() {
    if (_foreground) {
      onClearSessionNotif?.call();
      return;
    }
    if (isPlaying && _startedAt != null) {
      if (_pausedAt != null) {
        onPausedNotif?.call(_courtName ?? '', _elapsed);
      } else if (_outsideSince != null &&
          _outsideSince!.add(exitGrace).difference(DateTime.now()) <=
              endNotifLeadTime) {
        // Saliste del radio Y quedan <= 3 min: recién ahí avisamos "termina en…".
        onEndingNotif?.call(_courtName ?? '', _outsideSince!.add(exitGrace));
      } else {
        // Jugando (o saliste hace poco pero todavía hay margen): mostramos el
        // partido en curso. Inicio "efectivo" = ahora - elapsed, para que el
        // cronómetro nativo muestre el tiempo correcto descontando la pausa.
        onPlayingNotif?.call(
            _courtName ?? '', DateTime.now().subtract(Duration(seconds: _elapsed)));
      }
    } else if (isDwelling) {
      onDwellNotif?.call(dwellCourtName ?? '', dwellRemainingSeconds);
    } else {
      onClearSessionNotif?.call();
    }
  }

  /// Se dispara cuando toca subir al batch (cada [_syncEvery], al pausar/cerrar
  /// la app y en dispose). El listener "stagea" las stats actuales en la Session
  /// y llama a `Session.flush()` (que sube todo el perfil en una petición si hay
  /// cambios pendientes). El nivel ya viaja dentro de las stats.
  VoidCallback? onFlush;

  Timer? _syncTimer;

  int _tickCount = 0;
  bool _sampling = false;

  // Permanencia: cancha candidata y desde cuándo estamos cerca.
  String? _dwellCourtId;
  DateTime? _dwellSince;
  // Durante la permanencia, desde cuándo venimos leyendo FUERA de la cancha del
  // dwell. Toleramos [gpsJitterGrace] antes de resetear la cuenta de inicio.
  DateTime? _dwellOutsideSince;

  // "No juego": cancha cuyo detector está silenciado y hasta cuándo. Mientras
  // esté vigente y sigas adentro del radio, no se siembra dwell ahí y la UI
  // ofrece el arranque manual ([manualStartCourt] / [startManualNow]).
  String? _snoozeCourtId;
  DateTime? _snoozeUntil;
  // Desde cuándo venimos leyendo fuera del radio de la cancha silenciada (el
  // snooze se limpia tras [snoozeExitClear] continuos afuera: te fuiste real).
  DateTime? _snoozeOutsideSince;
  // Si la última lectura de GPS cayó dentro del radio de la cancha silenciada.
  bool _atSnoozedCourt = false;

  // Gracia de salida: desde cuándo estamos fuera del radio teniendo una sesión
  // activa. null = estamos dentro. Al superar [exitGrace] se corta el partido.
  DateTime? _outsideSince;
  // Durante la gracia de salida, desde cuándo venimos leyendo DE VUELTA adentro.
  // Toleramos [gpsJitterGrace] antes de cancelar el cierre (evita que un salto
  // de GPS cancele la cuenta de fin).
  DateTime? _insideSince;
  // Si ya mostramos la notif de "termina en…" para la gracia de salida actual
  // (para pasarla una sola vez al cruzar [endNotifLeadTime] y no re-emitirla).
  bool _endNotifShown = false;

  // Sesión activa.
  String? _courtId;
  String? _courtName;
  DateTime? _startedAt;
  int _elapsed = 0; // segundos
  int _lastSavedAt = 0; // segundos transcurridos en el último guardado
  int _accrued = 0; // reservado; los totales se computan al resolver el partido
  // Pausa del cronómetro (como play/pause de YouTube/Spotify).
  DateTime? _pausedAt; // != null mientras está pausado
  int _pausedSeconds = 0; // total de segundos pausados (se excluyen del elapsed)
  // Pregunta de partido largo (2h): desde cuándo esperamos la respuesta de
  // "¿Seguís jugando?" (mientras esté seteado, _pausedAt apunta al mismo
  // momento: congela cronómetro y detección) y si el usuario ya confirmó su
  // hora extra (no se re-pregunta; el próximo tope es el cierre duro a 3h).
  DateTime? _confirmAskedAt;
  bool _confirmedOnce = false;

  // Tiempo jugado acumulado por cancha (persistido local).
  final Map<String, _CourtPlay> _totals = {};

  // Cantidad total de veces que el usuario pasó al estado "Jugando".
  int _totalPlays = 0;

  /// Jugadas totales (todas las veces que jugó, sin discriminar cancha).
  int get totalPlays => _totalPlays;

  // Puntos acumulados (más tiempo + bonus por resultado/racha/cancha nueva).
  int _points = 0;
  int get points => _points;
  int get level => levelForPoints(_points);

  // ── Salud (Health Connect / HealthKit) ───────────────────────────────────
  final HealthService _health = HealthService();
  // Si el usuario conectó Salud (opt-in). Mientras esté en false no se consulta
  // nada de salud al resolver partidos.
  bool _healthEnabled = false;
  bool get healthEnabled => _healthEnabled;
  // Récord personal de calorías activas en un partido. Solo se suma bonus
  // cuando un partido lo supera (y ahí se actualiza). Sobrevive a reinstalar
  // porque también se siembra desde Notion.
  double _calorieRecord = 0;
  double get calorieRecord => _calorieRecord;
  // Bonus fijo de puntos al batir el récord de calorías.
  static const int calorieRecordBonus = 25;

  // IDs de logros desbloqueados (insignias permanentes). Una vez logrado, queda
  // logrado aunque las stats que lo originaron ya no estén (p.ej. tras reinstalar
  // se pierde el historial pero el set se siembra desde Notion).
  final Set<String> _unlockedBadges = {};
  Set<String> get unlockedBadges => Set.unmodifiable(_unlockedBadges);

  // ── Notificaciones de recompensa (logro / título / nivel) ────────────────
  // Cola de eventos a mostrar como banner in-app. La UI (MainShell) muestra el
  // primero, lo descarta con [acknowledgeReward] y sigue con el próximo.
  final List<RewardEvent> _rewards = [];
  List<RewardEvent> get rewards => List.unmodifiable(_rewards);

  /// Se dispara con cada recompensa nueva, además de encolar el banner in-app.
  /// Lo usa la capa de notificaciones del sistema (push local).
  void Function(RewardEvent reward)? onReward;

  // Historial persistido de notificaciones (más reciente primero), para el
  // listado del botón de campana.
  List<AppNotification> _notifs = [];
  List<AppNotification> get notifications => List.unmodifiable(_notifs);

  /// Cantidad de notificaciones sin leer (para el badge de la campana).
  int get unreadCount => _notifs.where((n) => !n.read).length;

  // Mientras es false NO se generan notificaciones. Se mantiene apagado durante
  // el sembrado inicial (restore + seed desde Notion) para no notificar el
  // progreso que el usuario ya tenía al abrir la app.
  bool _notify = false;
  // Nivel y títulos ya conocidos: base para detectar lo "nuevo".
  int _lastLevel = 1;
  final Set<String> _knownTitles = {};

  /// Descarta el primer evento de recompensa (lo llama la UI tras mostrarlo).
  void acknowledgeReward() {
    if (_rewards.isEmpty) return;
    _rewards.removeAt(0);
    notifyListeners();
  }

  /// Marca todas las notificaciones como leídas (al abrir el listado).
  void markNotificationsRead() {
    if (_notifs.every((n) => n.read)) return;
    for (final n in _notifs) {
      n.read = true;
    }
    _persistNotifs();
    notifyListeners();
  }

  /// Borra el historial de notificaciones.
  void clearNotifications() {
    if (_notifs.isEmpty) return;
    _notifs = [];
    _persistNotifs();
    notifyListeners();
  }

  /// Encola un evento (banner in-app) y lo guarda en el historial.
  void _emit(RewardEvent e) {
    _rewards.add(e);
    _notifs.insert(
      0,
      AppNotification(
        kind: e.kind,
        refId: e.refId,
        atMillis: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (_notifs.length > 50) _notifs = _notifs.sublist(0, 50);
    _persistNotifs();
    onReward?.call(e);
  }

  /// Agrega una notificación de chat creado (pickup).
  void addChatNotification(String chatName) {
    _emit(RewardEvent.chatCreated(chatName));
  }

  Future<void> _persistNotifs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kNotifs, jsonEncode(_notifs.map((n) => n.toJson()).toList()));
  }

  /// Detecta si subió de nivel y encola el evento. Siempre actualiza la
  /// referencia [_lastLevel] (incluso con [_notify] apagado, para no disparar
  /// notificaciones retroactivas al activar).
  void _checkLevelUp() {
    final lvl = level;
    if (_notify && lvl > _lastLevel) {
      _emit(RewardEvent.levelUp(lvl));
    }
    _lastLevel = lvl;
  }

  /// Snapshot actual de stats para evaluar logros.
  PlayStats get _currentStats => PlayStats(
        partidos: _totalPlays,
        canchas: uniqueCourtsCount,
        victorias: wins,
        maxRacha: bestStreak,
        segundos: totalSeconds,
        entrenamientos: trainings,
        victoriasAnio: winsLastYear,
        nivel: level,
      );

  // Historial de partidos terminados (más reciente primero), racha actual de
  // victorias consecutivas, e historial de rachas cerradas.
  List<PlaySession> _log = [];
  int _streak = 0;
  List<StreakEntry> _streakHistory = [];
  // Partido terminado esperando que el usuario elija el resultado.
  PlaySession? _pendingSession;

  List<PlaySession> get log => List.unmodifiable(_log);
  int get streak => _streak;
  List<StreakEntry> get streakHistory => List.unmodifiable(_streakHistory);
  PlaySession? get pending => _pendingSession;

  /// Cantidad de partidos ganados (resultado "Ganó").
  int get wins => _log.where((e) => e.result == PlayResult.win).length;

  /// Cantidad de entrenamientos completados.
  int get trainings =>
      _log.where((e) => e.result == PlayResult.training).length;

  /// Partidos ganados en los últimos 365 días.
  int get winsLastYear {
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 365))
        .millisecondsSinceEpoch;
    return _log
        .where((e) =>
            e.result == PlayResult.win && e.endedAtMillis >= cutoff)
        .length;
  }

  /// Puntos de la semana actual (lunes a hoy).
  int get pointsThisWeek {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final startMs = DateTime(monday.year, monday.month, monday.day)
        .millisecondsSinceEpoch;
    return _log
        .where((e) => e.endedAtMillis >= startMs)
        .fold(0, (sum, e) => sum + e.points);
  }

  /// Puntos del mes actual.
  int get pointsThisMonth {
    final now = DateTime.now();
    final startMs = DateTime(now.year, now.month, 1)
        .millisecondsSinceEpoch;
    return _log
        .where((e) => e.endedAtMillis >= startMs)
        .fold(0, (sum, e) => sum + e.points);
  }

  /// Inicio de la temporada actual. Las temporadas son SEMESTRES de calendario:
  /// 1 ene–30 jun y 1 jul–31 dic (dos por año). Devuelve el 1 de enero o el 1
  /// de julio del año en curso según [now] (por defecto, ahora). Fuente única
  /// del corte de temporada (la usa la UI del ranking también).
  static DateTime seasonStart([DateTime? now]) {
    final n = now ?? DateTime.now();
    return DateTime(n.year, n.month <= 6 ? 1 : 7, 1);
  }

  /// Puntos de la temporada actual (semestre de calendario, ver [seasonStart]).
  int get pointsSeason {
    final startMs = seasonStart().millisecondsSinceEpoch;
    return _log
        .where((e) => e.endedAtMillis >= startMs)
        .fold(0, (sum, e) => sum + e.points);
  }

  /// Mejor racha alcanzada (la actual o la más alta del historial).
  int get bestStreak {
    var best = _streak;
    for (final s in _streakHistory) {
      if (s.wins > best) best = s.wins;
    }
    return best;
  }

  bool get isPlaying => _startedAt != null;
  String? get courtName => _courtName;

  /// Id de la cancha del partido en curso (null si no estás jugando). Lo usa
  /// el detalle de cancha para mostrarte "jugando acá" con el estado LOCAL,
  /// sin esperar el round-trip de presencia a Notion.
  String? get courtId => isPlaying ? _courtId : null;
  int get elapsedSeconds => _elapsed;

  /// Multiplicador de puntos por duración para [seconds] de partido: x1.0 al
  /// empezar, sube lineal hasta [maxMultiplier] a [multiplierCap] (1:30h) y se
  /// mantiene ahí. Solo afecta los puntos por tiempo.
  static double multiplierFor(int seconds) {
    final cap = multiplierCap.inSeconds;
    final t = seconds.clamp(0, cap) / cap;
    return 1.0 + (maxMultiplier - 1.0) * t;
  }

  /// Multiplicador actual del partido en curso (en vivo).
  double get currentMultiplier => multiplierFor(_elapsed);

  /// Puntos por tiempo acumulados hasta ahora en el partido en curso (misma
  /// fórmula que al resolver: minutos topados a [pointsTimeCap] × multiplicador).
  /// No incluye los bonus de resultado/racha/cancha nueva (esos van al cerrar).
  int get currentTimePoints {
    final secs =
        _elapsed > pointsTimeCap.inSeconds ? pointsTimeCap.inSeconds : _elapsed;
    return ((secs ~/ 60) * multiplierFor(secs)).round();
  }

  /// True si el cronómetro del partido está pausado.
  bool get isPaused => _pausedAt != null;

  /// Pausa o reanuda el cronómetro del partido (un solo botón, como YouTube /
  /// Spotify). Pausado: el tiempo deja de correr y la detección de salida del
  /// radio se congela (no se cierra solo). Al reanudar, sigue desde donde quedó.
  void togglePause() {
    if (!isPlaying) return;
    // Con la pregunta de partido largo pendiente manda la pregunta: se
    // responde con SÍ/NO (notif o banner), no con el botón de pausa.
    if (awaitingConfirm) return;
    if (_pausedAt == null) {
      _pausedAt = DateTime.now();
    } else {
      // Reanudar: el tramo pausado se descuenta del tiempo jugado.
      _pausedSeconds += DateTime.now().difference(_pausedAt!).inSeconds;
      _pausedAt = null;
      // Volvemos a evaluar la salida del radio desde cero.
      _outsideSince = null;
      // La pausa corre el umbral de la pregunta/tope (son de juego NETO):
      // re-programamos la alarma para el nuevo momento en tiempo de reloj.
      _rescheduleConfirmAlarm();
    }
    _persistActive();
    _renderSessionNotif();
    notifyListeners();
  }

  // ── Pregunta de partido largo ("¿Seguís jugando?") ────────────────────────

  /// True mientras esperamos que el usuario responda la pregunta de las 2h.
  bool get awaitingConfirm => isPlaying && _confirmAskedAt != null;

  /// (Re)programa la alarma del próximo hito del partido largo en tiempo de
  /// reloj: la pregunta a [pointsTimeCap] de juego neto, o el cierre duro a
  /// [pointsTimeCap]+[overtimeMax] si ya confirmó. Con la marca ya pasada no
  /// programa nada (el ticker la dispara al toque con la app viva).
  void _rescheduleConfirmAlarm() {
    if (!isPlaying || _startedAt == null) return;
    final paused = Duration(seconds: _pausedSeconds);
    if (_confirmedOnce) {
      final at = _startedAt!.add(pointsTimeCap + overtimeMax + paused);
      if (at.isAfter(DateTime.now())) unawaited(scheduleHardEndAlarm(at: at));
      return;
    }
    final at = _startedAt!.add(pointsTimeCap + paused);
    if (at.isAfter(DateTime.now())) unawaited(scheduleConfirmAlarm(at: at));
  }

  /// Corre en cada tick con partido en curso: dispara la pregunta a las 2h,
  /// vigila su timeout y aplica el tope duro de la hora extra.
  void _checkLongMatch() {
    if (awaitingConfirm) {
      // Esperando respuesta: solo vigilamos el timeout (la alarma de
      // background es el respaldo con el proceso muerto).
      if (DateTime.now().difference(_confirmAskedAt!) >= confirmTimeout) {
        discardOnTimeout();
      }
      return;
    }
    if (_pausedAt != null) return; // pausa manual: el umbral es juego neto
    if (_outsideSince != null) return; // gracia en curso: ya se está cerrando
    if (!_confirmedOnce && _elapsed >= pointsTimeCap.inSeconds) {
      _beginConfirm();
    } else if (_confirmedOnce &&
        _elapsed >= (pointsTimeCap + overtimeMax).inSeconds) {
      // Tope duro de la hora extra: cerrar y GUARDAR, avisando el límite.
      // Snooze de la cancha (mismo flujo que "No juego"): seguís parado ahí y
      // sin esto arrancaría otra cuenta regresiva al instante; queda el botón
      // "Iniciar partido" manual en el mapa.
      unawaited(cancelHardEndAlarm());
      final id = _courtId;
      if (id != null) unawaited(_setSnooze(id));
      onNoticeNotif?.call('Llegaste al tiempo límite',
          'Guardamos tu partido de 3 horas. Registrá el resultado.');
      _endSession();
    }
  }

  /// Pausa el partido y muestra la pregunta. Idempotente (la alarma de
  /// background pudo haberse adelantado vía reconcileFromPrefs).
  void _beginConfirm() {
    if (!isPlaying || _confirmAskedAt != null) return;
    _confirmAskedAt = DateTime.now();
    _pausedAt = _confirmAskedAt; // congela cronómetro y detección (pausa)
    unawaited(cancelConfirmAlarm()); // la vía por alarma ya no hace falta
    unawaited(
        scheduleConfirmTimeoutAlarm(at: _confirmAskedAt!.add(confirmTimeout)));
    onConfirmNotif?.call(_courtName ?? '');
    unawaited(_persistActive());
    _renderSessionNotif();
    notifyListeners();
  }

  /// "SÍ, SIGO": reanuda el partido con [overtimeMax] de tope. El tiempo de
  /// espera no cuenta como jugado (misma aritmética que el resume de pausa).
  Future<void> confirmContinue() async {
    if (!awaitingConfirm) {
      // El botón de la notif pudo llegar antes que la reconciliación (la
      // pregunta la hizo la alarma con la app minimizada/cerrada): adoptamos
      // el estado persistido y reintentamos.
      await reconcileFromPrefs();
      if (!awaitingConfirm) return;
    }
    _pausedSeconds += DateTime.now().difference(_pausedAt!).inSeconds;
    _pausedAt = null;
    _confirmAskedAt = null;
    _confirmedOnce = true;
    // Igual que el resume de togglePause: la salida del radio se re-evalúa
    // desde cero.
    _outsideSince = null;
    unawaited(cancelConfirmTimeoutAlarm());
    onCancelConfirmNotif?.call();
    _rescheduleConfirmAlarm(); // programa el cierre duro (3h netas)
    unawaited(_persistActive());
    _renderSessionNotif();
    notifyListeners();
  }

  /// "NO, TERMINÉ": cierra normal con el tiempo congelado en la pregunta —
  /// queda pendiente de "¿Cómo te fue?" y suma como cualquier partido. Snooze
  /// de la cancha: seguís parado ahí y sin esto arrancaría otra cuenta
  /// regresiva al instante.
  Future<void> confirmStop() async {
    if (!awaitingConfirm) {
      await reconcileFromPrefs();
      if (!awaitingConfirm) return;
    }
    onCancelConfirmNotif?.call();
    unawaited(cancelConfirmTimeoutAlarm());
    final id = _courtId;
    if (id != null) unawaited(_setSnooze(id));
    _endSession();
  }

  /// Venció el timeout sin respuesta: cancela el partido POR COMPLETO — no
  /// queda pendiente, no suma puntos, ni tiempo, ni jugadas, ni historial.
  void discardOnTimeout() {
    if (!awaitingConfirm) return;
    onCancelConfirmNotif?.call();
    final id = _courtId;
    if (id != null) unawaited(_setSnooze(id));
    onNoticeNotif?.call('Partido cancelado',
        'No respondiste si seguías jugando, así que no lo guardamos.');
    _resetLiveSession();
  }

  /// True cuando estamos acumulando permanencia en una cancha cercana pero el
  /// partido todavía no arrancó (cuenta regresiva de [dwellThreshold] en curso).
  bool get isDwelling =>
      !isPlaying && _dwellCourtId != null && _dwellSince != null;

  /// Nombre de la cancha candidata durante la cuenta regresiva de permanencia.
  String? get dwellCourtName => _dwellCourt?.name;

  /// Cancha candidata (objeto) durante la cuenta regresiva de permanencia.
  Court? get _dwellCourt => _courtById(_dwellCourtId);

  /// Cancha del partido en curso (objeto).
  Court? get _playingCourt => _courtById(_courtId);

  Court? _courtById(String? id) {
    if (id == null) return null;
    for (final c in _courts) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Registra el puerto por el que el isolate de las alarmas nos pide reconciliar.
  void _registerPlayPort() {
    if (_playPort != null) return;
    IsolateNameServer.removePortNameMapping(kPlayPortName);
    _playPort = ReceivePort();
    IsolateNameServer.registerPortWithName(_playPort!.sendPort, kPlayPortName);
    _playPort!.listen((_) => reconcileFromPrefs());
  }

  /// Adopta el estado que una alarma de background pudo haber escrito (arranque
  /// o cierre automático del partido) mientras la app estaba dormida/cerrada.
  Future<void> reconcileFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final activeRaw = prefs.getString(_kActive);
    final pendingRaw = prefs.getString(_kPending);

    // 1) Arranque automático: la alarma dejó una sesión activa y no estábamos
    // jugando → adoptarla.
    if (!isPlaying && activeRaw != null) {
      try {
        final j = jsonDecode(activeRaw) as Map<String, dynamic>;
        final start = DateTime.fromMillisecondsSinceEpoch(
            (j['startMillis'] as num).toInt());
        if (DateTime.now().difference(start) <= const Duration(hours: 6)) {
          final endsAtMillis = (j['endsAtMillis'] as num?)?.toInt();
          _courtId = j['courtId'] as String?;
          _courtName = j['courtName'] as String?;
          _startedAt = start;
          _elapsed = DateTime.now().difference(start).inSeconds;
          _lastSavedAt = _elapsed;
          _accrued = 0;
          _dwellCourtId = null;
          _dwellSince = null;
          // Si había gracia de salida en curso, la restauramos para que el
          // cierre siga corriendo con el tiempo correcto (no la perdemos).
          _outsideSince = endsAtMillis != null
              ? DateTime.fromMillisecondsSinceEpoch(endsAtMillis)
                  .subtract(exitGrace)
              : null;
          _pausedAt = null;
          _pausedSeconds = 0;
          unawaited(cancelStartAlarm());
          // Re-armamos el foreground service para que el partido adoptado siga
          // detectándose aunque la app se vuelva a minimizar.
          if (_background) unawaited(_startStream());
          _renderSessionNotif();
          notifyListeners();
        }
      } catch (_) {}
    }

    // 1.b) Pregunta de partido largo hecha por la alarma en background:
    // adoptar la espera (o descartar si venció y su timeout no llegó a correr),
    // para que SÍ/NO de la notificación operen sobre el estado real. Cubre
    // tanto la sesión recién adoptada arriba como una que ya teníamos.
    if (isPlaying && activeRaw != null) {
      try {
        final j = jsonDecode(activeRaw) as Map<String, dynamic>;
        _confirmedOnce = _confirmedOnce || j['confirmedOnce'] == true;
        final askedMillis = (j['confirmAskedAtMillis'] as num?)?.toInt();
        if (askedMillis != null && _confirmAskedAt == null) {
          _confirmAskedAt = DateTime.fromMillisecondsSinceEpoch(askedMillis);
          _pausedAt ??= _confirmAskedAt;
          if (DateTime.now().difference(_confirmAskedAt!) >= confirmTimeout) {
            discardOnTimeout();
          } else {
            _renderSessionNotif();
            notifyListeners();
          }
        }
      } catch (_) {}
    }

    // 2) Cierre automático: creíamos estar jugando pero la alarma ya borró la
    // sesión activa → cerrar en memoria.
    if (isPlaying && activeRaw == null) {
      _resetLiveSession();
    }

    // 3) Pendiente de resultado dejado por la alarma → adoptarlo (dispara el
    // diálogo "¿Cómo te fue?").
    if (!isPlaying && _pendingSession == null && pendingRaw != null) {
      try {
        _pendingSession = PlaySession.fromJson(
            jsonDecode(pendingRaw) as Map<String, dynamic>);
        notifyListeners();
      } catch (_) {}
    }

    // 4) Permanencia sembrada en background (radar) → adoptarla, para que la
    // cuenta regresiva siga donde iba en vez de reiniciarse al abrir la app.
    if (!isPlaying && _dwellCourtId == null) {
      final t = await readPendingStartTarget();
      final atMillis = (t?['atMillis'] as num?)?.toInt();
      if (t != null &&
          atMillis != null &&
          (t['userKey'] ?? '') == _userKey &&
          DateTime.fromMillisecondsSinceEpoch(atMillis)
              .isAfter(DateTime.now())) {
        _dwellCourtId = t['courtId'] as String?;
        _dwellSince = DateTime.fromMillisecondsSinceEpoch(atMillis)
            .subtract(dwellThreshold);
        _dwellOutsideSince = null;
        unawaited(_startStream());
        _renderSessionNotif();
        notifyListeners();
      }
    }
  }

  /// Segundos que faltan para que el partido arranque solo. Si no hay
  /// permanencia en curso devuelve el umbral completo.
  int get dwellRemainingSeconds {
    if (_dwellSince == null) return dwellThreshold.inSeconds;
    final rem =
        dwellThreshold.inSeconds - DateTime.now().difference(_dwellSince!).inSeconds;
    return rem < 0 ? 0 : rem;
  }

  /// True cuando hay un partido en curso pero el usuario salió del radio: corre
  /// la cuenta regresiva de [exitGrace] para cerrarlo solo.
  bool get isEndingSoon => isPlaying && _outsideSince != null;

  /// Segundos que faltan para que el partido se cierre solo por estar fuera del
  /// radio. 0 si no estamos en período de gracia.
  int get endRemainingSeconds {
    if (_outsideSince == null) return 0;
    final rem =
        exitGrace.inSeconds - DateTime.now().difference(_outsideSince!).inSeconds;
    return rem < 0 ? 0 : rem;
  }

  /// Momento en que el partido se cerrará solo si seguís fuera del radio (para
  /// el cronómetro de la notificación). null si no hay gracia en curso.
  DateTime? get endsAt =>
      _outsideSince?.add(exitGrace);

  /// Detiene el partido en curso manualmente (botón "Detener"). Lo deja como
  /// "pendiente de resultado", igual que si hubiera terminado por salir del
  /// radio. Como seguís parado en la cancha, silenciamos su detector 1 h
  /// (igual que "No juego"): sin esto arrancaría OTRA cuenta regresiva al
  /// instante. Queda el banner "Iniciar partido" por si querés jugar de nuevo;
  /// si te vas, el snooze se limpia solo.
  void stopNow() {
    if (!isPlaying) return;
    final id = _courtId;
    if (id != null) unawaited(_setSnooze(id));
    _endSession();
  }

  /// Arranca el partido manualmente, sin esperar los [dwellThreshold] de
  /// permanencia. Solo aplica si hay una cancha candidata cerca y no hay ya un
  /// partido en curso (lo dispara el botón "Empezar" del cronómetro).
  void startNow() {
    if (isPlaying) return;
    final id = _dwellCourtId;
    if (id == null) return;
    for (final c in _courts) {
      if (c.id == id) {
        _startSession(c);
        return;
      }
    }
  }

  // ── "No juego": declinar la cuenta regresiva + arranque manual ────────────

  /// Cancha silenciada en la que TODAVÍA estás parado: la UI muestra el banner
  /// de arranque manual ("Iniciar partido") mientras esto no sea null.
  Court? get manualStartCourt {
    if (isPlaying || _snoozeCourtId == null || !_atSnoozedCourt) return null;
    if (_snoozeUntil == null || DateTime.now().isAfter(_snoozeUntil!)) {
      return null;
    }
    return _courtById(_snoozeCourtId);
  }

  /// Silencia el detector de [courtId] por [dwellSnooze] (memoria + prefs,
  /// para que el radar de background tampoco siembre la permanencia ahí).
  /// Asume que estás parado en esa cancha; si no, _maintainSnooze lo corrige.
  Future<void> _setSnooze(String courtId) async {
    _snoozeCourtId = courtId;
    _snoozeUntil = DateTime.now().add(dwellSnooze);
    _snoozeOutsideSince = null;
    _atSnoozedCourt = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kDwellSnooze,
      jsonEncode({
        'courtId': courtId,
        'untilMillis': _snoozeUntil!.millisecondsSinceEpoch,
      }),
    );
  }

  /// "No juego": cancela la cuenta regresiva y silencia el detector de esa
  /// cancha por [dwellSnooze] mientras sigas dentro del radio.
  Future<void> declineDwell() async {
    if (!isDwelling) return;
    final id = _dwellCourtId!;
    _dwellCourtId = null;
    _dwellSince = null;
    _dwellOutsideSince = null;
    // Sin esto, reconcileFromPrefs resucitaría la cuenta desde _kAlarmStart (y
    // la alarma arrancaría el partido igual a los 6 min).
    unawaited(cancelStartAlarm());
    await _setSnooze(id);
    _renderSessionNotif(); // la notif de cuenta regresiva desaparece
    notifyListeners();
  }

  /// Arranca el partido manualmente en la cancha silenciada (el usuario cambió
  /// de opinión después de "No juego"). Limpia el snooze.
  void startManualNow() {
    final c = manualStartCourt;
    if (c == null || isPlaying) return;
    _clearSnooze();
    _startSession(c);
  }

  /// Limpia el snooze (memoria + prefs) y avisa a la UI si el banner de
  /// arranque manual estaba visible.
  void _clearSnooze() {
    if (_snoozeCourtId == null) return;
    final wasVisible = manualStartCourt != null;
    _snoozeCourtId = null;
    _snoozeUntil = null;
    _snoozeOutsideSince = null;
    _atSnoozedCourt = false;
    unawaited(
        SharedPreferences.getInstance().then((p) => p.remove(_kDwellSnooze)));
    if (wasVisible) notifyListeners();
  }

  /// Mantenimiento del snooze en cada lectura de GPS: lo vence a la hora, lo
  /// limpia si te fuiste del radio de verdad ([snoozeExitClear] continuos
  /// afuera) y mantiene [_atSnoozedCourt] al día para el banner manual.
  void _maintainSnooze(Position pos) {
    final id = _snoozeCourtId;
    if (id == null) return;
    if (_snoozeUntil == null || DateTime.now().isAfter(_snoozeUntil!)) {
      _clearSnooze();
      return;
    }
    final c = _courtById(id);
    if (c == null) {
      _clearSnooze();
      return;
    }
    final inside = Geolocator.distanceBetween(
            pos.latitude, pos.longitude, c.lat, c.lng) <=
        radiusMeters;
    if (inside) {
      _snoozeOutsideSince = null;
    } else {
      _snoozeOutsideSince ??= DateTime.now();
      if (DateTime.now().difference(_snoozeOutsideSince!) >= snoozeExitClear) {
        _clearSnooze();
        return;
      }
    }
    if (inside != _atSnoozedCourt) {
      _atSnoozedCourt = inside;
      notifyListeners();
    }
  }

  /// Segundos del tramo de la sesión activa todavía no volcados a los totales.
  int get _pending => isPlaying ? (_elapsed - _accrued) : 0;

  /// Tiempo total jugado (todas las canchas), incluyendo la sesión en curso.
  /// Para mostrar en vivo en la UI.
  int get totalSeconds =>
      _totals.values.fold(0, (a, b) => a + b.seconds) + _pending;

  /// Tiempo total ya REGISTRADO (sin la sesión en curso). Es lo que se sube al
  /// backend: el partido en curso recién se contabiliza al resolverlo.
  int get committedSeconds =>
      _totals.values.fold(0, (a, b) => a + b.seconds);

  /// Desglose por cancha serializado (mismo formato que la persistencia local)
  /// para subirlo a Notion: {courtId: {"n": nombre, "s": segundos}}.
  String get totalsJson => jsonEncode({
        for (final e in _totals.entries)
          e.key: {'n': e.value.name, 's': e.value.seconds},
      });

  /// Tiempo jugado en una cancha puntual, incluyendo la sesión en curso.
  int secondsForCourt(String courtId) {
    final base = _totals[courtId]?.seconds ?? 0;
    return base + (_courtId == courtId ? _pending : 0);
  }

  /// Cantidad de canchas únicas donde el usuario llegó al estado "Jugando".
  int get uniqueCourtsCount => _totals.length;

  /// Desglose por cancha (mayor a menor), incluyendo la sesión en curso.
  List<({String courtId, String name, int seconds})> get breakdown {
    final out = <({String courtId, String name, int seconds})>[];
    for (final e in _totals.entries) {
      out.add((
        courtId: e.key,
        name: e.value.name,
        seconds: e.value.seconds + (_courtId == e.key ? _pending : 0),
      ));
    }
    // Si hay una cancha activa todavía sin total guardado, incluirla.
    if (isPlaying && !_totals.containsKey(_courtId)) {
      out.add((courtId: _courtId!, name: _courtName ?? '', seconds: _pending));
    }
    out.sort((a, b) => b.seconds.compareTo(a.seconds));
    return out;
  }

  void setCourts(List<Court> courts) => _courts = courts;

  /// Formatea segundos como reloj: "1:23:45" / "23:45" / "00:09".
  static String fmt(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) return '$h:$mm:$ss';
    return '$mm:$ss';
  }

  /// Arranca el muestreo de ubicación (pide permiso si hace falta).
  ///
  /// [seedPoints]/[seedPlays]/[seedStreak] vienen del perfil de Notion: si la
  /// nube tiene valores más altos que los locales (p.ej. tras reinstalar), se
  /// adoptan para no perder progreso ni bajar de nivel.
  Future<void> startTracking({
    required String userKey,
    int seedPoints = 0,
    int seedPlays = 0,
    int seedStreak = 0,
    List<String> seedBadges = const [],
    String seedTotalsJson = '',
  }) async {
    if (_ticker != null) return;
    // Notificaciones apagadas durante todo el sembrado: el progreso preexistente
    // (local + el sembrado desde Notion) no debe disparar banners al arrancar.
    _notify = false;
    // Fijamos el usuario y limpiamos cualquier estado en memoria del anterior:
    // el restore lee solo las claves de ESTE usuario.
    _userKey = userKey;
    // Persistimos el userKey para que el isolate de las alarmas arme las mismas
    // claves namespaced, y registramos el puerto de reconciliación.
    _registerPlayPort();
    unawaited(SharedPreferences.getInstance()
        .then((p) => p.setString(kBgUserKey, userKey)));
    _resetState();
    // DEV: si el proceso murió con el modo prueba activo, restauramos la
    // ubicación simulada ANTES del restore. Sin esto, un reinicio del SO
    // "teletransporta" al jugador al GPS real (lejos de la cancha simulada) y
    // el partido en prueba se cierra o descarta solo. El mock se limpia
    // únicamente al salir del modo prueba (clearMock).
    try {
      final prefs = await SharedPreferences.getInstance();
      final mockRaw = prefs.getString(kMockPosKey);
      if (mockRaw != null) {
        final parts = mockRaw.split(',');
        final mlat = double.tryParse(parts[0]);
        final mlng = double.tryParse(parts.length > 1 ? parts[1] : '');
        if (mlat != null && mlng != null) {
          _mock = Position(
            latitude: mlat,
            longitude: mlng,
            timestamp: DateTime.now(),
            accuracy: 5,
            altitude: 0,
            altitudeAccuracy: 0,
            heading: 0,
            headingAccuracy: 0,
            speed: 0,
            speedAccuracy: 0,
          );
        }
      }
    } catch (_) {/* sin prefs: seguimos con GPS real */}
    await _restore();
    // Por si una alarma arrancó/cerró un partido mientras la app estaba cerrada.
    await reconcileFromPrefs();

    // Sembrado desde Notion: nunca por debajo de lo que ya hay en la nube.
    var seeded = false;
    if (seedPoints > _points) {
      _points = seedPoints;
      await _persistPoints();
      seeded = true;
    }
    if (seedPlays > _totalPlays) {
      _totalPlays = seedPlays;
      await _persistPlays();
      seeded = true;
    }
    if (seedStreak > _streak) {
      _streak = seedStreak;
      await _persistStreak();
      seeded = true;
    }
    // Insignias: unión con las de Notion (las ganadas nunca se pierden).
    if (seedBadges.isNotEmpty) {
      _unlockedBadges.addAll(seedBadges);
      await _persistBadges();
      seeded = true;
    }
    // Tiempo por cancha: merge con Notion, quedándonos con el mayor por cancha
    // (no perdemos lo acumulado en otro dispositivo).
    if (seedTotalsJson.isNotEmpty) {
      try {
        final m = jsonDecode(seedTotalsJson) as Map<String, dynamic>;
        var merged = false;
        m.forEach((k, v) {
          final o = v as Map<String, dynamic>;
          final secs = (o['s'] as num?)?.toInt() ?? 0;
          final name = (o['n'] ?? '') as String;
          final cur = _totals[k];
          if (cur == null || secs > cur.seconds) {
            _totals[k] = _CourtPlay(
                cur != null && cur.name.isNotEmpty ? cur.name : name, secs);
            merged = true;
          }
        });
        if (merged) {
          await _persistTotals();
          seeded = true;
        }
      } catch (_) {/* JSON corrupto: ignorar */}
    }
    // Por si las stats (sembradas o locales) desbloquean logros nuevos. Con
    // _notify apagado esto solo siembra los sets conocidos, sin notificar.
    _recomputeBadges();
    // A partir de acá, lo que se desbloquee SÍ se notifica.
    _lastLevel = level;
    _notify = true;
    if (seeded) notifyListeners();

    // Observador de ciclo de vida + timer de sync por lotes (una sola vez).
    WidgetsBinding.instance.addObserver(this);
    _syncTimer ??= Timer.periodic(_syncEvery, (_) => _flush());

    // NO pedimos permiso de ubicación acá: lo pide el modal de permisos cuando
    // el usuario activa el switch. Arrancamos el ticker igual: si todavía no hay
    // permiso, las muestras fallan (silenciosas) y empiezan a funcionar en
    // cuanto se conceda, sin reiniciar la app.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _sample(); // primera muestra inmediata (si hay permiso)
    // El foreground service (con su notificación) ya NO arranca acá: ahora lo
    // gobierna el geofencing (enter de una cancha → enterCourtArea). Con la app
    // abierta, el ticker de arriba ya detecta sin servicio en primer plano.
  }

  /// Llamado al ENTRAR a la zona de una cancha (geofence). Arranca el foreground
  /// service para mantener viva la detección aunque se minimice la app; su
  /// notificación queda justificada porque estás en una cancha.
  void enterCourtArea() {
    // Los geofences usan el GPS REAL: en modo prueba manda el mock y un cruce
    // real (p. ej. una cancha cerca de tu casa) no debe interferir la prueba.
    if (_mock != null) return;
    if (_background) _startStream();
  }

  /// Llamado al SALIR de la zona de una cancha (geofence EXIT).
  ///
  /// Si hay un partido en curso NO cortamos el foreground service: lo dejamos
  /// vivo durante la gracia de salida para que el isolate principal cierre el
  /// partido de forma confiable con la app minimizada (antes lo matábamos acá y,
  /// sin proceso vivo, la gracia nunca cerraba hasta reabrir la app). Además
  /// arrancamos la gracia + alarma desde acá porque el evento de geofence es
  /// confiable aunque el muestreo GPS no llegue a correr.
  void leaveCourtArea() {
    // Ídem enterCourtArea: los geofences (GPS real) no deben re-armar la gracia
    // de salida mientras el mock está adentro de la cancha simulada.
    if (_mock != null) return;
    if (isPlaying) {
      _beginExitGrace();
      return;
    }
    _stopStream();
  }

  /// Arranca la gracia de salida del partido en curso: marca desde cuándo
  /// estamos fuera, programa la alarma de cierre (para que cierre aunque la app
  /// esté minimizada/cerrada) y pasa la notif a "termina en…". Idempotente: si
  /// ya hay gracia en curso (o está pausado / no hay partido) no hace nada. La
  /// disparan tanto el muestreo GPS ([_evaluate]) como el evento de geofence
  /// EXIT ([leaveCourtArea]).
  void _beginExitGrace() {
    if (!isPlaying || _pausedAt != null || _outsideSince != null) return;
    _outsideSince = DateTime.now();
    _insideSince = null;
    _endNotifShown = false; // gracia nueva: la notif sigue "jugando" por ahora
    final pc = _playingCourt;
    if (pc != null && _startedAt != null) {
      unawaited(scheduleEndAlarm(
        userKey: _userKey,
        courtId: pc.id,
        courtName: pc.name,
        lat: pc.lat,
        lng: pc.lng,
        startMillis: _startedAt!.millisecondsSinceEpoch,
        at: _outsideSince!.add(exitGrace),
      ));
    }
    unawaited(_persistActive()); // persiste endsAtMillis para el cierre correcto
    _renderSessionNotif(); // la notif pasa a "termina en…"
  }

  void stopTracking() {
    _ticker?.cancel();
    _ticker = null;
    _stopStream();
  }

  /// Limpia TODO el estado en memoria (stats, logros, historial, sesión y
  /// permanencia en curso). No toca SharedPreferences: lo persistido queda en
  /// la "namespace" de cada usuario y se vuelve a cargar en su próximo login.
  void _resetState() {
    _totals.clear();
    _totalPlays = 0;
    _points = 0;
    _calorieRecord = 0;
    _healthEnabled = false;
    _streak = 0;
    _streakHistory = [];
    _log = [];
    _unlockedBadges.clear();
    _notifs = [];
    _rewards.clear();
    _pendingSession = null;
    _knownTitles.clear();
    _lastLevel = 1;
    _tickCount = 0;
    _courtId = null;
    _courtName = null;
    _startedAt = null;
    _elapsed = 0;
    _lastSavedAt = 0;
    _accrued = 0;
    _pausedAt = null;
    _pausedSeconds = 0;
    _outsideSince = null;
    _insideSince = null;
    _endNotifShown = false;
    _dwellCourtId = null;
    _dwellSince = null;
    _dwellOutsideSince = null;
    _snoozeCourtId = null;
    _snoozeUntil = null;
    _snoozeOutsideSince = null;
    _atSnoozedCourt = false;
    _mock = null;
  }

  /// Al cerrar sesión: corta el tracking, limpia el estado del usuario que se
  /// va y olvida su "namespace". Así el próximo login arranca limpio y NUNCA se
  /// sube en el batch el progreso de otra cuenta.
  void resetForLogout() {
    stopTracking();
    _resetState();
    _userKey = '';
    _notify = false;
    onClearSessionNotif?.call();
    notifyListeners();
  }

  // ── Sync por lotes (batch) ───────────────────────────────────────────────

  /// Pide subir lo pendiente. El listener (`onFlush`) stagea las stats y llama a
  /// `Session.flush()`, que decide si hay algo para subir según su flag dirty.
  void _flush() => onFlush?.call();

  /// Fuerza la subida (p. ej. al cerrar sesión). Útil para no esperar al timer.
  void flush() => _flush();

  /// Recalcula qué logros están desbloqueados según las stats actuales y los
  /// agrega al set permanente. Si hubo nuevos, los marca para subir y (si las
  /// notificaciones ya están activas) encola los banners de logro y de los
  /// títulos que esos logros recién destrabaron.
  void _recomputeBadges() {
    final stats = _currentStats;
    var changed = false;
    for (final a in kAchievements) {
      if (a.unlocked(stats) && _unlockedBadges.add(a.id)) {
        changed = true;
        if (_notify) _emit(RewardEvent.achievement(a));
      }
    }
    // Títulos recién desbloqueados (derivan de los logros). Con _notify apagado
    // solo sembramos el set conocido, sin generar notificaciones.
    for (final t in kTitles) {
      if (t.unlocked(stats) && _knownTitles.add(t.name) && _notify) {
        _emit(RewardEvent.title(t));
      }
    }
    if (changed) _persistBadges();
    notifyListeners();
  }

  Future<void> _persistBadges() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kBadges, _unlockedBadges.toList());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Volvimos a la app: limpiamos la notif de sesión (manda el banner in-app).
      _foreground = true;
      // Adoptamos lo que una alarma pudo haber arrancado/cerrado en background.
      unawaited(reconcileFromPrefs());
      _renderSessionNotif();
      // Re-evaluamos ya: si la permanencia venció mientras estábamos en segundo
      // plano, arranca el partido al instante en vez de esperar la próxima muestra.
      if (isDwelling) _sample();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      // Al minimizar/cerrar subimos lo pendiente (el timer solo corre con la app
      // abierta) y mostramos la notif de sesión del estado actual.
      _foreground = false;
      _flush();
      _renderSessionNotif();
    }
  }

  /// Habilita/deshabilita la detección en segundo plano (lo elige el usuario).
  /// Con background, un servicio en primer plano mantiene viva la app aunque
  /// esté minimizada, así el muestreo sigue corriendo.
  /// Se dispara al cambiar la preferencia de detección en background, para que
  /// el coordinador registre o quite las geofences de las canchas.
  void Function(bool enabled)? onBackgroundChanged;

  Future<void> setBackground(bool enabled) async {
    _background = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBackground, enabled);
    // Si se apaga, cortamos cualquier servicio en curso. El registro/quita de
    // geofences lo maneja el coordinador vía onBackgroundChanged.
    if (!enabled) _stopStream();
    onBackgroundChanged?.call(enabled);
    notifyListeners();
  }

  /// Stream de ubicación con servicio en primer plano (mantiene la app viva en
  /// background). Su rol principal es ese; la detección la sigue haciendo el
  /// ticker con getCurrentPosition (funciona aunque estés quieto).
  Future<void> _startStream() async {
    if (_posSub != null) return;
    // NO pedimos permiso acá (lo pide el modal). Solo arrancamos el servicio en
    // primer plano si el permiso ya está concedido.
    final perm = await Geolocator.checkPermission();
    if (perm != LocationPermission.always &&
        perm != LocationPermission.whileInUse) {
      return;
    }
    final LocationSettings settings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        // distanceFilter 0 + intervalo de tiempo: en segundo plano el ticker de
        // 1s está suspendido, así que la detección depende SOLO de este stream.
        // Con un filtro por distancia, parado y quieto (justo el caso del dwell)
        // no llegan updates y la cuenta regresiva de inicio nunca se resuelve.
        // Pidiendo updates por tiempo, _evaluate corre periódicamente y el
        // partido arranca a los 6 min aunque estés inmóvil.
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 10),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: '1of1',
          notificationText: 'Detección de cancha activa',
          enableWakeLock: true,
        ),
      );
    } else {
      settings = AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 8,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
        pauseLocationUpdatesAutomatically: false,
      );
    }
    _posSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen((pos) {
      // En modo prueba manda el mock: si dejáramos pasar el GPS real (lejos de
      // la cancha simulada), dispararía la gracia de salida a cada rato,
      // resetearía la permanencia y cancelaría las alarmas en plena prueba.
      if (_mock != null) return;
      _noteBgFix();
      _evaluate(pos);
    }, onError: (_) {});
  }

  // Diagnóstico: deja registrado el último fix recibido en background (visible
  // en los controles DEV del mapa). Throttled para no escribir a disco cada 10s.
  DateTime? _lastBgFixWrite;
  void _noteBgFix() {
    if (_foreground) return;
    final now = DateTime.now();
    if (_lastBgFixWrite != null &&
        now.difference(_lastBgFixWrite!) < const Duration(minutes: 1)) {
      return;
    }
    _lastBgFixWrite = now;
    unawaited(SharedPreferences.getInstance()
        .then((p) => p.setInt(kLastBgFixKey, now.millisecondsSinceEpoch)));
  }

  void _stopStream() {
    _posSub?.cancel();
    _posSub = null;
  }

  void _tick() {
    if (isPlaying && _startedAt != null) {
      // Partido largo: pregunta a las 2h, timeout de respuesta y tope de 3h.
      _checkLongMatch();
      if (!isPlaying) return; // _checkLongMatch pudo cerrar/cancelar el partido
      // Pausado: el tiempo queda congelado (no avanza el elapsed).
      if (_pausedAt == null) {
        _elapsed =
            DateTime.now().difference(_startedAt!).inSeconds - _pausedSeconds;
        // Guardado periódico cada 30s: persistimos la sesión activa (para
        // retomar el cronómetro si se cierra la app). El tiempo NO se vuelca a
        // los totales todavía: eso pasa al resolver el partido.
        if (_elapsed - _lastSavedAt >= 30) {
          _lastSavedAt = _elapsed;
          _persistActive();
        }
        // Gracia de salida: al cruzar el umbral de [endNotifLeadTime] restantes,
        // pasamos la notif a "termina en…" (una sola vez por período de salida).
        if (_outsideSince != null && !_endNotifShown) {
          final rem = _outsideSince!.add(exitGrace).difference(DateTime.now());
          if (rem <= endNotifLeadTime) {
            _endNotifShown = true;
            _renderSessionNotif();
          }
        }
      }
      notifyListeners();
      // Cada ~20s revisamos la batería: si quedó muy baja, cerramos el partido.
      if (_tickCount % 20 == 0) unawaited(_maybeEndForLowBattery());
    } else if (isDwelling) {
      // Sin partido todavía, pero acumulando permanencia. Si ya se cumplió el
      // umbral, arrancamos el partido sin esperar una muestra nueva de GPS (así
      // la notif pasa de la cuenta regresiva a "partido en curso" en el momento
      // justo, sin contar números negativos). Si no, refrescamos la cuenta.
      final ready = dwellRemainingSeconds <= 0 ? _dwellCourt : null;
      if (ready != null) {
        _startSession(ready);
      } else {
        notifyListeners();
      }
    }
    _tickCount++;
    if (_tickCount % _sampleEvery.inSeconds == 0) _sample();
  }

  // ── DEV: ubicación simulada ───────────────────────────────────────────────
  // Mientras [_mock] no sea null, el muestreo usa este punto en vez del GPS
  // real. Sirve para probar la detección de radio/canchas moviendo un pin en el
  // mapa. Es una herramienta temporal de prueba.
  Position? _mock;
  bool get mockActive => _mock != null;

  /// Fija una ubicación simulada y la evalúa al instante (arranca la detección
  /// de cercanía como si estuvieras parado ahí). También la persiste para que
  /// los callbacks de alarma en background la respeten (isolate aparte).
  void setMock(double lat, double lng) {
    _mock = Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
    unawaited(SharedPreferences.getInstance()
        .then((p) => p.setString(kMockPosKey, '$lat,$lng')));
    _evaluate(_mock!);
  }

  /// Quita la ubicación simulada y vuelve al GPS real en el próximo muestreo.
  void clearMock() {
    _mock = null;
    unawaited(
        SharedPreferences.getInstance().then((p) => p.remove(kMockPosKey)));
  }

  Future<void> _sample() async {
    if (_sampling) return;
    // DEV: con ubicación simulada activa, no tocamos el GPS real.
    if (_mock != null) {
      _evaluate(_mock!);
      return;
    }
    _sampling = true;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      _evaluate(pos);
    } catch (_) {
      // sin fix: no hacemos nada hasta la próxima muestra
    } finally {
      _sampling = false;
    }
  }

  void _evaluate(Position pos) {
    // Descartamos lecturas demasiado imprecisas para un radio de 110m.
    if (pos.accuracy > radiusMeters * 1.5) return;

    // "No juego": vencimiento / salida real / flag de "sigo parado ahí".
    _maintainSnooze(pos);

    // En segundo plano (con el foreground-service vivo) esta es la vía para
    // revisar la batería: si estás jugando y quedó muy baja, cerramos el partido.
    if (isPlaying) unawaited(_maybeEndForLowBattery());

    // Cancha más cercana dentro del radio.
    Court? near;
    double best = radiusMeters + 1;
    for (final c in _courts) {
      if (c.lat == 0 && c.lng == 0) continue;
      final d = Geolocator.distanceBetween(
          pos.latitude, pos.longitude, c.lat, c.lng);
      if (d <= radiusMeters && d < best) {
        best = d;
        near = c;
      }
    }

    if (isPlaying) {
      // Pausado: congelamos la detección (no arranca la gracia ni se cierra).
      if (_pausedAt != null) return;
      // Latido: dejamos registrado que el partido sigue vivo (también en
      // background mientras el foreground-service entregue ubicaciones).
      unawaited(_persistActive());
      final atCourt = near != null && near.id == _courtId;

      if (_outsideSince == null) {
        // No hay gracia de salida en curso.
        if (atCourt) return; // todo normal, seguimos jugando
        // Salimos del radio: única fuente de verdad para arrancar la gracia
        // (también la usa el geofence EXIT vía leaveCourtArea).
        _beginExitGrace();
        return;
      }

      // Ya hay una gracia de salida en curso.
      if (atCourt) {
        // Lectura de "volviste". Toleramos [gpsJitterGrace] continuos adentro
        // antes de cancelar el cierre, para que un salto de GPS no lo cancele.
        _insideSince ??= DateTime.now();
        if (DateTime.now().difference(_insideSince!) >= gpsJitterGrace) {
          _outsideSince = null;
          _insideSince = null;
          _endNotifShown = false;
          unawaited(cancelEndAlarm());
          _renderSessionNotif(); // la notif vuelve a "jugando"
        }
        return;
      }

      // Seguís afuera: descartamos la re-entrada tentativa y evaluamos el cierre.
      _insideSince = null;
      if (DateTime.now().difference(_outsideSince!) >= exitGrace) {
        _endSession();
        if (near != null) _beginDwell(near);
      }
      return;
    }

    // No estamos jugando.
    // Caso 1: estamos en la cancha del dwell en curso → acumular permanencia.
    if (_dwellCourtId != null && near != null && near.id == _dwellCourtId) {
      _dwellOutsideSince = null; // seguimos adentro: no hay salida pendiente
      if (_dwellSince != null &&
          DateTime.now().difference(_dwellSince!) >= dwellThreshold) {
        _startSession(near);
      } else {
        // Todavía por debajo del umbral: refrescamos la cuenta regresiva.
        _renderSessionNotif();
      }
      return;
    }

    // Caso 2: había un dwell en curso pero esta lectura NO es su cancha (salimos
    // del radio o saltó a otra cancha). Toleramos [gpsJitterGrace] continuos
    // antes de resetear, para que un salto de GPS no reinicie la cuenta.
    if (_dwellCourtId != null && _dwellSince != null) {
      _dwellOutsideSince ??= DateTime.now();
      if (DateTime.now().difference(_dwellOutsideSince!) < gpsJitterGrace) {
        // Dentro de la tolerancia: asumimos que es un salto de GPS y seguís en
        // la cancha. Si el umbral YA se cumplió mientras "salías", arrancamos
        // igual (no perdemos la cuenta por un salto justo sobre el final). Si
        // realmente te fuiste, la gracia de salida cerrará el partido enseguida.
        final c = _dwellCourt;
        if (c != null &&
            DateTime.now().difference(_dwellSince!) >= dwellThreshold) {
          _startSession(c);
        }
        return; // seguimos esperando (mantenemos el dwell)
      }
      // Superó la tolerancia: reseteamos la permanencia.
      _dwellCourtId = null;
      _dwellSince = null;
      _dwellOutsideSince = null;
      unawaited(cancelStartAlarm());
      _renderSessionNotif();
      // Sigue abajo: si esta lectura cae en otra cancha, arranca dwell nuevo.
    }

    // Caso 3: sin dwell en curso.
    if (near != null) {
      // "No juego" vigente en esta cancha: no sembramos la permanencia (el
      // arranque queda manual vía startManualNow hasta que el snooze caiga).
      if (near.id == _snoozeCourtId && manualStartCourt != null) return;
      _beginDwell(near); // arranca la permanencia en esta cancha
    } else if (!_background) {
      // Fuera de toda cancha y sin background: cortamos el foreground-service.
      _stopStream();
    }
  }

  void _beginDwell(Court c) {
    _dwellCourtId = c.id;
    _dwellSince = DateTime.now();
    _dwellOutsideSince = null;
    // Programamos el arranque automático a los [dwellThreshold] min con una
    // alarma exacta del sistema: dispara aunque la app esté cerrada/dormida.
    unawaited(scheduleStartAlarm(
      userKey: _userKey,
      courtId: c.id,
      courtName: c.name,
      lat: c.lat,
      lng: c.lng,
      at: _dwellSince!.add(dwellThreshold),
    ));
    // Arrancamos el foreground-service de ubicación apenas empieza la
    // permanencia. Así, aunque se minimice la app, el isolate sigue vivo y
    // _evaluate corre periódicamente: el partido arranca solo a los 6 min y la
    // notificación pasa de la cuenta regresiva a "partido en curso" sin que el
    // usuario tenga que abrir la app. (Antes solo se prendía con la geofence y
    // la preferencia de background; si el dwell empezaba con la app abierta, al
    // minimizar quedaba congelado y el cronómetro contaba en negativo.)
    _startStream();
    _renderSessionNotif();
  }

  void _startSession(Court c) {
    // Idempotente: si ya estamos jugando en esta cancha, no reiniciamos (evita
    // doble arranque entre el stream y la alarma de background).
    if (isPlaying && _courtId == c.id) return;
    _courtId = c.id;
    _courtName = c.name;
    _startedAt = DateTime.now();
    _elapsed = 0;
    _lastSavedAt = 0;
    _accrued = 0;
    _pausedAt = null;
    _pausedSeconds = 0;
    _outsideSince = null;
    _endNotifShown = false;
    _confirmAskedAt = null;
    _confirmedOnce = false;
    // Ya arrancó: cancelamos la alarma de arranque (si estaba pendiente) y
    // arrancamos la vigilancia periódica de batería (red de seguridad en
    // background por si el SO mata el proceso). También programamos la
    // pregunta de partido largo (la alarma cubre el proceso muerto; con la
    // app viva el ticker se adelanta).
    unawaited(cancelStartAlarm());
    unawaited(scheduleBatteryWatch());
    unawaited(scheduleConfirmAlarm(at: _startedAt!.add(pointsTimeCap)));
    // No registramos nada todavía: jugada, cancha, tiempo, puntos, racha e
    // historial se computan recién al resolver el resultado (resolvePending),
    // con el partido ya terminado y validado por duración. Acá solo persistimos
    // la sesión activa para poder retomar el cronómetro si se cierra la app.
    _persistActive();
    onPresenceChanged?.call(true, c.id, _startedAt);
    _renderSessionNotif();
    notifyListeners();
  }

  void _endSession({bool lowBattery = false}) {
    onPresenceChanged?.call(false, '', null);

    final endedSeconds = _elapsed;
    final endedCourtId = _courtId ?? '';
    final endedCourtName = _courtName ?? '';

    if (endedSeconds < minMatch.inSeconds) {
      // Partido demasiado corto: probablemente se canceló. Como nada se
      // registró durante el partido, no hay que revertir nada: simplemente no
      // dejamos partido pendiente y avisamos que no se registró.
      onMatchDiscarded?.call(endedCourtName, endedSeconds);
      _resetLiveSession();
      return;
    }

    // Dejamos el partido "pendiente de resultado": la UI le preguntará al
    // usuario cómo le fue (Ganó/Perdió/Empató/...). El registro local (jugada,
    // tiempo, puntos, racha, historial) se hace al resolver, en resolvePending.
    final endedAt = DateTime.now();
    _pendingSession = PlaySession(
      courtId: endedCourtId,
      courtName: endedCourtName,
      seconds: endedSeconds,
      endedAtMillis: endedAt.millisecondsSinceEpoch,
    );
    _persistPending();
    onMatchEnded?.call(endedCourtId, endedAt, lowBattery);
    _resetLiveSession();
  }

  /// Si estás jugando y el equipo quedó con muy poca batería (y sin cargar),
  /// cerramos el partido para proteger tu información antes de que el SO mate la
  /// app. Best-effort: si no se puede leer la batería, no hace nada.
  Future<void> _maybeEndForLowBattery() async {
    if (!isPlaying || _batteryChecking) return;
    _batteryChecking = true;
    try {
      final state = await _battery.batteryState;
      if (state == BatteryState.charging || state == BatteryState.full) return;
      final level = await _battery.batteryLevel;
      if (isPlaying && level <= batteryEndPercent) {
        _endSession(lowBattery: true);
      }
    } catch (_) {/* sin lectura de batería: ignoramos */} finally {
      _batteryChecking = false;
    }
  }

  /// Limpia el estado de la sesión en vivo (cancha, cronómetro, pausa) y
  /// refresca la notificación. No toca totales ni partido pendiente.
  void _resetLiveSession() {
    _courtId = null;
    _courtName = null;
    _startedAt = null;
    _elapsed = 0;
    _lastSavedAt = 0;
    _accrued = 0;
    _pausedAt = null;
    _pausedSeconds = 0;
    _outsideSince = null;
    _insideSince = null;
    _endNotifShown = false;
    _confirmAskedAt = null;
    _confirmedOnce = false;
    // Reseteamos también la permanencia: al terminar un partido (manual o por
    // salir del radio) NO queremos arrancar otro al instante con el dwell viejo
    // ya vencido. Así, si seguís dentro de la cancha, empieza de nuevo la cuenta
    // regresiva de 6 min para el próximo partido.
    _dwellCourtId = null;
    _dwellSince = null;
    _dwellOutsideSince = null;
    // Cancelamos cualquier alarma pendiente (arranque/cierre/batería/partido
    // largo): el estado quedó resuelto acá.
    unawaited(cancelStartAlarm());
    unawaited(cancelEndAlarm());
    unawaited(cancelBatteryWatch());
    unawaited(cancelConfirmAlarm());
    unawaited(cancelConfirmTimeoutAlarm());
    unawaited(cancelHardEndAlarm());
    // El partido cerró: soltamos el foreground service para no drenar batería.
    // Si seguís dentro de otra cancha, el _beginDwell posterior lo reactiva.
    _stopStream();
    _clearActive();
    _renderSessionNotif();
    notifyListeners();
  }

  /// Registra el resultado elegido por el usuario para el partido pendiente.
  /// Win extiende la racha; loss la corta (y la guarda en el historial de
  /// rachas); el resto (empate / no contó / entrenamiento) no afecta la racha.
  Future<void> resolvePending(PlayResult result) async {
    final p = _pendingSession;
    if (p == null) return;

    // ¿Primera vez en esta cancha? (antes de registrar el tiempo de la cancha)
    final isNewCourt =
        p.courtId.isEmpty ? false : !_totals.containsKey(p.courtId);

    // Registro local del partido (recién ahora, con el resultado confirmado):
    // sumamos la jugada y volcamos el tiempo al total de la cancha.
    _totalPlays++;
    if (p.courtId.isNotEmpty) {
      final cur = _totals[p.courtId];
      _totals[p.courtId] = _CourtPlay(
        cur?.name.isNotEmpty == true ? cur!.name : p.courtName,
        (cur?.seconds ?? 0) + p.seconds,
      );
    }

    // Racha: al ganar sube; al perder se corta (y se archiva).
    if (result == PlayResult.win) {
      _streak++;
    } else if (result == PlayResult.loss) {
      if (_streak > 0) {
        _streakHistory.insert(
            0, StreakEntry(DateTime.now().millisecondsSinceEpoch, _streak));
      }
      _streak = 0;
    }

    // Base por tiempo: única parte que usa el multiplicador por duración
    // (incentivo a jugar partidos largos). El tiempo deja de sumar puntos a
    // partir de [pointsTimeCap] (~2h, un partido profesional).
    final scoredSecs = p.seconds > pointsTimeCap.inSeconds
        ? pointsTimeCap.inSeconds
        : p.seconds;
    final timePoints = ((scoredSecs ~/ 60) * multiplierFor(scoredSecs)).round();

    // Bonus por resultado: PORCENTAJE de los puntos por tiempo (no un valor
    // fijo), así el peso del resultado escala con lo que jugaste.
    final resultPct = switch (result) {
      PlayResult.win => 0.30,
      PlayResult.tie => 0.20,
      PlayResult.training => 0.15,
      PlayResult.loss => 0.10,
      PlayResult.notCounted => 0.0,
    };
    final resultBonus = (timePoints * resultPct).round();

    // Bonus de racha: +5% de los puntos por tiempo por cada victoria seguida,
    // con tope de 25% (racha de 5). La racha puede seguir creciendo, pero el
    // porcentaje se mantiene en 25%.
    final streakPct =
        result == PlayResult.win ? _streak.clamp(0, 5) * 0.05 : 0.0;
    final streakBonus = (timePoints * streakPct).round();

    // ── Salud: enriquecer con datos del wearable (si el usuario conectó Salud).
    // Se lee la ventana [inicio, fin] del partido del store del OS (retiene el
    // histórico, así que sirve aunque respondas más tarde). Puntos SOLO si las
    // calorías superan tu récord personal; ahí se suma el bonus y se sube el
    // récord. El primer dato válido fija la base sin bonus. Sin datos (sin
    // wearable) no pasa nada.
    HealthMetrics? hm;
    int healthBonus = 0;
    bool newCalorieRecord = false;
    if (_healthEnabled && p.seconds > 0) {
      final end = DateTime.fromMillisecondsSinceEpoch(p.endedAtMillis);
      final start = end.subtract(Duration(seconds: p.seconds));
      hm = await _health.metricsFor(start, end);
      if (hm != null && hm.calories > 0) {
        if (_calorieRecord > 0 && hm.calories > _calorieRecord) {
          healthBonus = calorieRecordBonus;
          newCalorieRecord = true;
        }
        if (hm.calories > _calorieRecord) _calorieRecord = hm.calories;
      }
    }

    // Total: tiempo + bonus por resultado (%) + racha (%) + cancha nueva +
    // récord de salud.
    final gained = timePoints +
        resultBonus +
        streakBonus +
        (isNewCourt ? 30 : 0) +
        healthBonus;
    _points += gained;

    // Guardamos el partido con los puntos que sumó y los datos de salud, para
    // mostrarlos en el historial.
    _log.insert(
      0,
      p.withResult(
        result,
        points: gained,
        calories: hm?.calories ?? 0,
        avgHr: hm?.avgHr,
        maxHr: hm?.maxHr,
        steps: hm?.steps ?? 0,
        distance: hm?.distance ?? 0,
        calorieRecord: newCalorieRecord,
      ),
    );
    if (_log.length > 100) _log = _log.sublist(0, 100);

    // Encolar para el ranking por período (semana/mes/temporada) de amigos.
    // Solo partidos que suman puntos (los "sin información" no aportan al
    // ranking). Se sube en lote en el flush; acá solo persiste local.
    if (gained > 0 && NotionConfig.dbMatches.isNotEmpty && _userKey.isNotEmpty) {
      await _enqueuePendingMatch(
        points: gained,
        endedAtMillis: p.endedAtMillis,
        courtId: p.courtId,
        courtName: p.courtName,
        result: result.name,
        seconds: p.seconds,
      );
    }

    _pendingSession = null;
    await _persistPlays();
    await _persistTotals();
    await _persistLog();
    await _persistStreak();
    await _persistPoints();
    await _persistCalorieRecord();
    await _clearPending();
    _recomputeBadges();
    _checkLevelUp(); // los puntos ganados pueden haber subido el nivel
    notifyListeners();
  }

  // ── Partidos pendientes de subir (ranking por período) ──────────────────

  /// Agrega un partido al buffer local de subida. `email` = userKey (email
  /// normalizado), la misma clave con la que se resuelven los amigos.
  Future<void> _enqueuePendingMatch({
    required int points,
    required int endedAtMillis,
    required String courtId,
    required String courtName,
    required String result,
    required int seconds,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kPendingMatches) ?? <String>[];
    list.add(jsonEncode({
      'email': _userKey,
      'points': points,
      'endedAt':
          DateTime.fromMillisecondsSinceEpoch(endedAtMillis).toIso8601String(),
      'courtId': courtId,
      'courtName': courtName,
      'result': result,
      'seconds': seconds,
    }));
    await prefs.setStringList(_kPendingMatches, list);
  }

  /// Lee los partidos pendientes de subir (cada uno es un mapa JSON).
  Future<List<Map<String, dynamic>>> readPendingMatches() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kPendingMatches) ?? <String>[];
    final out = <Map<String, dynamic>>[];
    for (final s in list) {
      try {
        out.add(jsonDecode(s) as Map<String, dynamic>);
      } catch (_) {
        // Entrada corrupta: se descarta.
      }
    }
    return out;
  }

  /// Reescribe el buffer con lo que quedó sin subir (los que fallaron).
  Future<void> writePendingMatches(List<Map<String, dynamic>> pending) async {
    final prefs = await SharedPreferences.getInstance();
    if (pending.isEmpty) {
      await prefs.remove(_kPendingMatches);
      return;
    }
    await prefs.setStringList(
        _kPendingMatches, pending.map(jsonEncode).toList());
  }

  // ── Persistencia local ─────────────────────────────────────────────────

  Future<void> _persistActive() async {
    if (_startedAt == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kActive,
      jsonEncode({
        'courtId': _courtId,
        'courtName': _courtName,
        'startMillis': _startedAt!.millisecondsSinceEpoch,
        // "Latido": última vez que el partido estuvo efectivamente en curso. Si
        // el proceso se corta (apagado / kill), al reabrir sabemos hasta cuándo
        // se jugó realmente y guardamos el partido con ese tiempo (no inflado).
        'lastSeenMillis': DateTime.now().millisecondsSinceEpoch,
        // Si hay gracia de salida en curso, cuándo DEBE cerrarse el partido (fin
        // de gracia). Sirve para reconstruir la duración correcta (tope = fin de
        // gracia, no el momento en que reabrís la app). null = sin salida.
        'endsAtMillis': _outsideSince?.add(exitGrace).millisecondsSinceEpoch,
        // Pregunta de partido largo: pendiente desde (null = sin pregunta) y si
        // ya confirmó su hora extra. Los leen los isolates de background (radar
        // no siembra gracia mientras espera; el timeout descarta) y la
        // reconciliación al reabrir.
        'confirmAskedAtMillis': _confirmAskedAt?.millisecondsSinceEpoch,
        'confirmedOnce': _confirmedOnce,
      }),
    );
  }

  Future<void> _clearActive() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kActive);
  }

  Future<void> _persistPlays() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPlays, _totalPlays);
  }

  Future<void> _persistPoints() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPoints, _points);
  }

  Future<void> _persistCalorieRecord() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kCalRecord, _calorieRecord);
  }

  // ── Salud: conectar / desconectar ────────────────────────────────────────

  /// El usuario activó "Conectar Salud": dispara el pedido de permisos y deja
  /// habilitada la lectura para los próximos partidos. No se llama solo: siempre
  /// desde un gesto explícito del usuario. Devuelve false solo si Health Connect
  /// no está disponible (para poder explicarle al usuario).
  ///
  /// OJO: en Android, Health Connect NO deja verificar el permiso de LECTURA
  /// (lo oculta por privacidad), así que requestAuthorization puede devolver
  /// false aun estando concedido. Por eso NO gateamos el flag en ese valor:
  /// habilitamos mientras Health Connect esté disponible. Si al final no hay
  /// permiso, simplemente no vendrán datos (no rompe nada ni suma puntos).
  Future<bool> enableHealth() async {
    bool available = false;
    try {
      available = await _health.isAvailable();
    } catch (_) {/* sin Health Connect */}
    final prefs = await SharedPreferences.getInstance();
    if (!available) {
      _healthEnabled = false;
      await prefs.setBool(_kHealthEnabled, false);
      notifyListeners();
      return false;
    }
    // Dispara el flujo de permisos (si ya estaban dados, no re-pregunta).
    try {
      await _health.requestPermissions();
    } catch (_) {/* el usuario resolverá en el diálogo del sistema */}
    _healthEnabled = true;
    await prefs.setBool(_kHealthEnabled, true);
    notifyListeners();
    return true;
  }

  Future<void> disableHealth() async {
    _healthEnabled = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHealthEnabled, false);
    notifyListeners();
  }

  /// ¿Está Health Connect disponible en el dispositivo? (para decidir si vale
  /// la pena ofrecer la conexión).
  Future<bool> healthAvailable() => _health.isAvailable();

  /// Prueba de lectura de salud (para diagnosticar por qué un partido no trae
  /// datos): devuelve un resumen legible de las últimas horas.
  Future<String> diagnoseHealth() => _health.diagnose();

  /// Re-lee las métricas de salud de un partido del historial que quedó SIN
  /// datos: el reloj suele sincronizar Health Connect DESPUÉS de resolverse el
  /// resultado, y ese 0 quedaba persistido para siempre. Se llama al abrir el
  /// detalle de un partido; si ahora hay datos, actualiza el historial (los
  /// puntos y el récord no cambian: es registro visual retroactivo).
  Future<void> refreshHealthFor(PlaySession s) async {
    if (!_healthEnabled || s.hasHealth || s.seconds <= 0) return;
    final end = DateTime.fromMillisecondsSinceEpoch(s.endedAtMillis);
    final start = end.subtract(Duration(seconds: s.seconds));
    HealthMetrics? hm;
    try {
      hm = await _health.metricsFor(start, end);
    } catch (_) {
      return;
    }
    if (hm == null || !hm.hasData) return;
    final idx = _log.indexWhere(
        (e) => e.endedAtMillis == s.endedAtMillis && e.courtId == s.courtId);
    if (idx < 0) return;
    _log[idx] = _log[idx].withHealth(hm);
    await _persistLog();
    notifyListeners();
  }

  /// Siembra el récord de calorías desde el perfil (Notion) al iniciar sesión,
  /// para que sobreviva a reinstalar sin poder re-farmearse. Solo sube: nunca
  /// baja el récord local con un valor menor del servidor.
  Future<void> seedCalorieRecord(double fromProfile) async {
    if (fromProfile > _calorieRecord) {
      _calorieRecord = fromProfile;
      await _persistCalorieRecord();
      notifyListeners();
    }
  }

  Future<void> _persistLog() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kLog, jsonEncode(_log.map((e) => e.toJson()).toList()));
  }

  Future<void> _persistStreak() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kStreak, _streak);
    await prefs.setString(_kStreakHist,
        jsonEncode(_streakHistory.map((e) => e.toJson()).toList()));
  }

  Future<void> _persistPending() async {
    final prefs = await SharedPreferences.getInstance();
    if (_pendingSession == null) {
      await prefs.remove(_kPending);
    } else {
      await prefs.setString(_kPending, jsonEncode(_pendingSession!.toJson()));
    }
  }

  Future<void> _clearPending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPending);
  }

  Future<void> _persistTotals() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kTotals,
      jsonEncode({
        for (final e in _totals.entries)
          e.key: {'n': e.value.name, 's': e.value.seconds},
      }),
    );
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();

    // Activo por defecto; el usuario puede desactivarlo desde la tuerquita.
    _background = prefs.getBool(_kBackground) ?? true;
    _totalPlays = prefs.getInt(_kPlays) ?? 0;
    _streak = prefs.getInt(_kStreak) ?? 0;
    _points = prefs.getInt(_kPoints) ?? 0;
    _calorieRecord = prefs.getDouble(_kCalRecord) ?? 0;
    _healthEnabled = prefs.getBool(_kHealthEnabled) ?? false;
    _unlockedBadges
      ..clear()
      ..addAll(prefs.getStringList(_kBadges) ?? const []);

    // Historial de notificaciones.
    final rawNotifs = prefs.getString(_kNotifs);
    if (rawNotifs != null) {
      try {
        final list = jsonDecode(rawNotifs) as List;
        _notifs = list
            .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {/* ignorar cache corrupto */}
    }

    // Historial de partidos.
    final rawLog = prefs.getString(_kLog);
    if (rawLog != null) {
      try {
        final list = jsonDecode(rawLog) as List;
        _log = list
            .map((e) => PlaySession.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {/* ignorar cache corrupto */}
    }

    // Historial de rachas.
    final rawStreaks = prefs.getString(_kStreakHist);
    if (rawStreaks != null) {
      try {
        final list = jsonDecode(rawStreaks) as List;
        _streakHistory = list
            .map((e) => StreakEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {/* ignorar */}
    }

    // Partido pendiente de resultado (p.ej. terminó con la app cerrada).
    final rawPending = prefs.getString(_kPending);
    if (rawPending != null) {
      try {
        _pendingSession = PlaySession.fromJson(
            jsonDecode(rawPending) as Map<String, dynamic>);
      } catch (_) {/* ignorar */}
    }

    // Snooze de "No juego" (si sigue vigente; _atSnoozedCourt se resuelve con
    // la próxima lectura de GPS).
    final rawSnooze = prefs.getString(_kDwellSnooze);
    if (rawSnooze != null) {
      try {
        final j = jsonDecode(rawSnooze) as Map<String, dynamic>;
        final until = DateTime.fromMillisecondsSinceEpoch(
            (j['untilMillis'] as num).toInt());
        if (until.isAfter(DateTime.now())) {
          _snoozeCourtId = j['courtId'] as String?;
          _snoozeUntil = until;
        } else {
          unawaited(prefs.remove(_kDwellSnooze));
        }
      } catch (_) {/* ignorar */}
    }

    // Totales por cancha.
    final rawTotals = prefs.getString(_kTotals);
    if (rawTotals != null) {
      try {
        final m = jsonDecode(rawTotals) as Map<String, dynamic>;
        _totals.clear();
        m.forEach((k, v) {
          final o = v as Map<String, dynamic>;
          _totals[k] = _CourtPlay(
              (o['n'] ?? '') as String, (o['s'] as num?)?.toInt() ?? 0);
        });
      } catch (_) {/* ignorar cache corrupto */}
    }

    // Sesión activa (si la app se cerró durante un partido).
    final raw = prefs.getString(_kActive);
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        final start = DateTime.fromMillisecondsSinceEpoch(
            (j['startMillis'] as num).toInt());
        // Sin lastSeenMillis = la sesión la escribió la ALARMA de background
        // (arranque automático con el proceso muerto): no hubo latidos, pero el
        // partido SIGUE en curso. No aplica la regla del "gap" (cerraría con 0s
        // y el partido desaparecería de la app, que era el bug reportado).
        final hasHeartbeat = j['lastSeenMillis'] != null;
        final lastSeen = hasHeartbeat
            ? DateTime.fromMillisecondsSinceEpoch(
                (j['lastSeenMillis'] as num).toInt())
            : start;
        final courtId = j['courtId'] as String?;
        final courtName = j['courtName'] as String?;
        final endsAtMillis = (j['endsAtMillis'] as num?)?.toInt();
        final endsAt = endsAtMillis != null
            ? DateTime.fromMillisecondsSinceEpoch(endsAtMillis)
            : null;
        // Pregunta de partido largo pendiente al morir el proceso. Va ANTES de
        // la regla del gap de latidos: durante la espera el partido está
        // pausado y los latidos se frenan — sin este orden, el gap lo cerraría
        // con el tiempo del último latido en vez de aplicar la pregunta.
        final askedMillis = (j['confirmAskedAtMillis'] as num?)?.toInt();
        final askedAt = askedMillis != null
            ? DateTime.fromMillisecondsSinceEpoch(askedMillis)
            : null;
        final now = DateTime.now();

        if (now.difference(start) > const Duration(hours: 6)) {
          // Demasiado vieja: la descartamos.
          await _clearActive();
        } else if (endsAt != null && !now.isBefore(endsAt)) {
          // Habías salido de la cancha y la gracia venció con la app cerrada: el
          // partido debía cerrarse a [endsAt]. Lo guardamos con esa duración (la
          // gracia cuenta como jugado); el tope es fin-de-gracia, no el app-open.
          final seconds = endsAt.difference(start).inSeconds;
          if (seconds >= minMatch.inSeconds) {
            _pendingSession = PlaySession(
              courtId: courtId ?? '',
              courtName: courtName ?? '',
              seconds: seconds,
              endedAtMillis: endsAt.millisecondsSinceEpoch,
            );
            await _persistPending();
          }
          await _clearActive();
          unawaited(cancelStartAlarm());
          unawaited(cancelEndAlarm());
          unawaited(cancelBatteryWatch());
        } else if (askedAt != null &&
            now.difference(askedAt) >= confirmTimeout) {
          // La pregunta venció sin respuesta y su alarma de timeout no llegó a
          // correr: descartamos POR COMPLETO (sin pendiente, sin puntos) —
          // misma regla que el timeout en background.
          if (courtId != null && courtId.isNotEmpty) {
            unawaited(_setSnooze(courtId));
          }
          await _clearActive();
          unawaited(cancelStartAlarm());
          unawaited(cancelEndAlarm());
          unawaited(cancelBatteryWatch());
          unawaited(cancelConfirmAlarm());
          unawaited(cancelConfirmTimeoutAlarm());
          unawaited(cancelHardEndAlarm());
          onCancelConfirmNotif?.call();
        } else if (askedAt != null) {
          // Pregunta todavía vigente: adoptamos el partido PAUSADO esperando
          // la respuesta (el cronómetro quedó congelado en el momento de la
          // pregunta). El timeout sigue corriendo (alarma + ticker).
          _courtId = courtId;
          _courtName = courtName;
          _startedAt = start;
          _elapsed = askedAt.difference(start).inSeconds;
          _lastSavedAt = _elapsed;
          _accrued = 0;
          _confirmAskedAt = askedAt;
          _pausedAt = askedAt;
          _confirmedOnce = j['confirmedOnce'] == true;
        } else if (hasHeartbeat && now.difference(lastSeen) > resumeGapMax) {
          // El proceso estuvo caído (apagado / kill) mientras jugabas: el
          // partido se jugó hasta [lastSeen]. Lo GUARDAMOS con ese tiempo (no
          // resumimos con tiempo inflado). Si fue muy corto (< minMatch) se
          // descarta según la regla habitual.
          final seconds = lastSeen.difference(start).inSeconds;
          if (seconds >= minMatch.inSeconds) {
            _pendingSession = PlaySession(
              courtId: courtId ?? '',
              courtName: courtName ?? '',
              seconds: seconds,
              endedAtMillis: lastSeen.millisecondsSinceEpoch,
            );
            await _persistPending();
          }
          await _clearActive();
          unawaited(cancelStartAlarm());
          unawaited(cancelEndAlarm());
          unawaited(cancelBatteryWatch());
        } else {
          // Partido en curso: hueco chico (seguíamos jugando) o arranque
          // automático por alarma con el proceso muerto. Resume.
          _courtId = courtId;
          _courtName = courtName;
          _startedAt = start;
          _elapsed = now.difference(start).inSeconds;
          _lastSavedAt = _elapsed;
          // El tiempo de la sesión en curso todavía NO está en los totales (se
          // vuelca al resolver). Lo dejamos como pendiente para que el
          // cronómetro y el tiempo en vivo lo muestren completo.
          _accrued = 0;
          // Si ya había confirmado su hora extra, no se re-pregunta: el
          // próximo hito es el cierre duro de las 3h.
          _confirmedOnce = j['confirmedOnce'] == true;
          // Si había una gracia de salida en curso (no vencida), la restauramos
          // para que la cuenta regresiva de cierre siga desde donde iba.
          if (endsAt != null) _outsideSince = endsAt.subtract(exitGrace);
          // Arrancamos el latido ya (las sesiones escritas por la alarma no lo
          // traen, y sin latido el próximo restore la cerraría mal).
          await _persistActive();
          // Re-armamos el foreground service: el partido resumido tiene que
          // seguir detectándose aunque la app se vuelva a minimizar.
          if (_background) unawaited(_startStream());
        }
      } catch (_) {
        await _clearActive();
      }
      // Refrescamos la notificación de sesión en TODOS los caminos: en
      // foreground limpia la "Jugando en…" vieja que pudo dejar el isolate de
      // background; si seguimos jugando en background, la re-dibuja correcta.
      _renderSessionNotif();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _flush();
    _syncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _posSub?.cancel();
    if (_playPort != null) {
      IsolateNameServer.removePortNameMapping(kPlayPortName);
      _playPort!.close();
      _playPort = null;
    }
    super.dispose();
  }
}

/// Tiempo acumulado en una cancha (nombre cacheado + segundos).
class _CourtPlay {
  final String name;
  final int seconds;
  const _CourtPlay(this.name, this.seconds);
}

/// Resultado de un partido (lo elige el usuario al terminar).
enum PlayResult { win, loss, tie, notCounted, training }

extension PlayResultX on PlayResult {
  String get label => switch (this) {
        PlayResult.win => 'Victoria',
        PlayResult.loss => 'Derrota',
        PlayResult.tie => 'Empate',
        PlayResult.notCounted => 'Sin información',
        PlayResult.training => 'Entrenamiento',
      };

  static PlayResult? fromName(String? n) {
    for (final r in PlayResult.values) {
      if (r.name == n) return r;
    }
    return null;
  }
}

/// Un partido terminado: cancha, duración, cuándo terminó y resultado.
class PlaySession {
  final String courtId;
  final String courtName;
  final int seconds;
  final int endedAtMillis;
  final PlayResult? result;

  /// Puntos sumados por este partido (tiempo + bonus). 0 si aún no se resolvió.
  final int points;

  // ── Datos de salud del wearable (Health Connect / HealthKit) ──────────────
  // Se llenan al resolver el partido si el usuario conectó Salud y tenía un
  // reloj/anillo puesto. 0/null = sin datos (no penaliza ni afecta el récord).
  /// Calorías activas quemadas durante el partido.
  final double calories;
  /// Pulso promedio y máximo (bpm) durante el partido.
  final int? avgHr;
  final int? maxHr;
  /// Pasos registrados durante el partido.
  final int steps;
  /// Distancia recorrida durante el partido, en metros.
  final double distance;

  /// ¿Este partido marcó un récord personal de calorías? (para destacarlo).
  final bool calorieRecord;

  const PlaySession({
    required this.courtId,
    required this.courtName,
    required this.seconds,
    required this.endedAtMillis,
    this.result,
    this.points = 0,
    this.calories = 0,
    this.avgHr,
    this.maxHr,
    this.steps = 0,
    this.distance = 0,
    this.calorieRecord = false,
  });

  bool get hasHealth =>
      calories > 0 || steps > 0 || avgHr != null || distance > 0;

  PlaySession withResult(
    PlayResult r, {
    int points = 0,
    double calories = 0,
    int? avgHr,
    int? maxHr,
    int steps = 0,
    double distance = 0,
    bool calorieRecord = false,
  }) =>
      PlaySession(
        courtId: courtId,
        courtName: courtName,
        seconds: seconds,
        endedAtMillis: endedAtMillis,
        result: r,
        points: points,
        calories: calories,
        avgHr: avgHr,
        maxHr: maxHr,
        steps: steps,
        distance: distance,
        calorieRecord: calorieRecord,
      );

  /// Copia con datos de salud llegados tarde (el wearable sincroniza Health
  /// Connect después de resolver el partido). No toca puntos ni récord: es
  /// solo registro visual retroactivo.
  PlaySession withHealth(HealthMetrics hm) => PlaySession(
        courtId: courtId,
        courtName: courtName,
        seconds: seconds,
        endedAtMillis: endedAtMillis,
        result: result,
        points: points,
        calories: hm.calories,
        avgHr: hm.avgHr,
        maxHr: hm.maxHr,
        steps: hm.steps,
        distance: hm.distance,
        calorieRecord: calorieRecord,
      );

  Map<String, dynamic> toJson() => {
        'courtId': courtId,
        'courtName': courtName,
        'seconds': seconds,
        'endedAt': endedAtMillis,
        'result': result?.name,
        'points': points,
        'calories': calories,
        'avgHr': avgHr,
        'maxHr': maxHr,
        'steps': steps,
        'distance': distance,
        'calorieRecord': calorieRecord,
      };

  factory PlaySession.fromJson(Map<String, dynamic> j) => PlaySession(
        courtId: (j['courtId'] ?? '') as String,
        courtName: (j['courtName'] ?? '') as String,
        seconds: (j['seconds'] as num?)?.toInt() ?? 0,
        endedAtMillis: (j['endedAt'] as num?)?.toInt() ?? 0,
        result: PlayResultX.fromName(j['result'] as String?),
        points: (j['points'] as num?)?.toInt() ?? 0,
        calories: (j['calories'] as num?)?.toDouble() ?? 0,
        avgHr: (j['avgHr'] as num?)?.toInt(),
        maxHr: (j['maxHr'] as num?)?.toInt(),
        steps: (j['steps'] as num?)?.toInt() ?? 0,
        distance: (j['distance'] as num?)?.toDouble() ?? 0,
        calorieRecord: (j['calorieRecord'] as bool?) ?? false,
      );
}

/// Tipo de recompensa que dispara una notificación in-app.
enum RewardKind { achievement, title, levelUp, chatCreated }

/// Un evento de recompensa a mostrar como banner: logro o título desbloqueado,
/// o subida de nivel. Lleva ya resuelto el texto, el ícono y el color a mostrar.
///
/// [refId] identifica de forma estable la recompensa (id del logro, nombre del
/// título o número de nivel) para poder persistirla y reconstruirla luego sin
/// guardar ícono/color (que se re-resuelven desde el catálogo).
class RewardEvent {
  final RewardKind kind;
  final String refId;
  final String headline; // ej. "¡Logro desbloqueado!"
  final String name; // ej. "Trotamundos" / "Nivel 5"
  final IconData icon;
  final Color color;

  const RewardEvent({
    required this.kind,
    required this.refId,
    required this.headline,
    required this.name,
    required this.icon,
    required this.color,
  });

  factory RewardEvent.achievement(Achievement a) => RewardEvent(
        kind: RewardKind.achievement,
        refId: a.id,
        headline: '¡Logro desbloqueado!',
        name: a.name,
        icon: a.icon,
        color: kGold,
      );

  factory RewardEvent.title(GameTitle t) => RewardEvent(
        kind: RewardKind.title,
        refId: t.name,
        headline: '¡Nuevo título!',
        name: t.name,
        icon: Icons.workspace_premium,
        color: t.color,
      );

  factory RewardEvent.levelUp(int level) => RewardEvent(
        kind: RewardKind.levelUp,
        refId: '$level',
        headline: '¡Subiste de nivel!',
        name: 'Nivel $level',
        icon: Icons.trending_up,
        color: AppColors.accent,
      );

  factory RewardEvent.chatCreated(String chatName) => RewardEvent(
        kind: RewardKind.chatCreated,
        refId: chatName,
        headline: 'Chat creado',
        name: chatName,
        icon: Icons.chat_bubble_outline,
        color: AppColors.accent,
      );

  /// Reconstruye el evento a partir de su tipo y [refId] (al cargar el historial
  /// persistido), re-resolviendo ícono/color/textos desde el catálogo.
  factory RewardEvent.restore(RewardKind kind, String refId) {
    switch (kind) {
      case RewardKind.achievement:
        final a = achievementById(refId);
        if (a != null) return RewardEvent.achievement(a);
      case RewardKind.title:
        final t = titleByName(refId);
        if (t != null) return RewardEvent.title(t);
      case RewardKind.levelUp:
        return RewardEvent.levelUp(int.tryParse(refId) ?? 1);
      case RewardKind.chatCreated:
        return RewardEvent.chatCreated(refId);
    }
    // Catálogo cambió y ya no existe: fallback neutro.
    return RewardEvent(
      kind: kind,
      refId: refId,
      headline: 'Notificación',
      name: refId,
      icon: Icons.notifications_outlined,
      color: AppColors.accent,
    );
  }
}

/// Una notificación persistida en el historial: tipo + [refId] (para reconstruir
/// el evento), cuándo ocurrió y si ya fue leída.
class AppNotification {
  final RewardKind kind;
  final String refId;
  final int atMillis;
  bool read;

  AppNotification({
    required this.kind,
    required this.refId,
    required this.atMillis,
    this.read = false,
  });

  RewardEvent get event => RewardEvent.restore(kind, refId);

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'refId': refId,
        'at': atMillis,
        'read': read,
      };

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        kind: RewardKind.values.firstWhere(
          (k) => k.name == j['kind'],
          orElse: () => RewardKind.achievement,
        ),
        refId: (j['refId'] ?? '') as String,
        atMillis: (j['at'] as num?)?.toInt() ?? 0,
        read: (j['read'] as bool?) ?? false,
      );
}

/// Una racha terminada: cuándo terminó y cuántos partidos seguidos ganó.
class StreakEntry {
  final int endedAtMillis;
  final int wins;
  const StreakEntry(this.endedAtMillis, this.wins);

  Map<String, dynamic> toJson() => {'endedAt': endedAtMillis, 'wins': wins};
  factory StreakEntry.fromJson(Map<String, dynamic> j) => StreakEntry(
        (j['endedAt'] as num?)?.toInt() ?? 0,
        (j['wins'] as num?)?.toInt() ?? 0,
      );
}
