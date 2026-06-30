import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/achievements.dart';
import '../data/courts.dart';
import '../theme/app_theme.dart';

/// Detecta automáticamente cuándo el usuario está "jugando" en una cancha:
/// si permanece dentro de [radiusMeters] de una cancha durante [dwellThreshold],
/// arranca un contador; cuando sale del radio, el contador termina.
///
/// Fase 1 (foreground): muestrea la ubicación cada [_sampleEvery] mientras la
/// app está abierta. El tiempo activo se persiste cada 60s para no perderlo.
class PlaySessionService extends ChangeNotifier with WidgetsBindingObserver {
  static const double radiusMeters = 110;
  static const Duration dwellThreshold = Duration(minutes: 6);
  // Período de gracia de salida: con una sesión activa, el partido NO se corta
  // apenas el GPS te ubica fuera del radio. Recién se cierra si seguís fuera de
  // forma continua durante este tiempo (tolera saltos de señal y pausas cortas).
  static const Duration exitGrace = Duration(minutes: 6);
  // Duración mínima para que un partido cuente. Por debajo de esto asumimos que
  // se canceló (no suma puntos, ni tiempo, ni jugadas, ni entra al historial).
  static const Duration minMatch = Duration(minutes: 13);
  // Multiplicador de puntos por duración: incentiva partidos largos. Crece
  // lineal desde x1.0 al empezar hasta [maxMultiplier] al llegar a [multiplierCap].
  static const Duration multiplierCap = Duration(minutes: 90);
  static const double maxMultiplier = 1.8;
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

  List<Court> _courts = const [];
  Timer? _ticker;
  StreamSubscription<Position>? _posSub;
  bool _background = false;

  /// Si el usuario habilitó la detección en segundo plano.
  bool get backgroundEnabled => _background;

  /// Notifica cuando empieza/termina un partido, para propagar la presencia
  /// (ej. actualizar el estado "Jugando" en Notion vía Session).
  void Function(bool playing, String courtId, DateTime? since)? onPresenceChanged;

  /// Terminó un partido válido (>= [minMatch]) que queda pendiente de resultado.
  /// Incluye la cancha y el momento de fin (para registrar el "último partido").
  void Function(String courtId, DateTime endedAt)? onMatchEnded;

  /// Se descartó un partido por durar menos de [minMatch]: no se registró nada.
  void Function(String courtName, int seconds)? onMatchDiscarded;

  // ── Notificación de sesión (cronómetro persistente con la app minimizada) ──
  // La capa de notificaciones implementa el "cómo"; acá solo decidimos el qué y
  // el cuándo. Solo se muestra con la app en segundo plano: en foreground manda
  // el banner in-app.
  /// Mostrar la cuenta regresiva (cancha, momento en que arranca el partido).
  void Function(String courtName, DateTime endsAt)? onDwellNotif;

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
      } else if (_outsideSince != null) {
        onEndingNotif?.call(_courtName ?? '', _outsideSince!.add(exitGrace));
      } else {
        // Inicio "efectivo" = ahora - elapsed, para que el cronómetro nativo
        // muestre el tiempo correcto descontando lo que estuvo pausado.
        onPlayingNotif?.call(
            _courtName ?? '', DateTime.now().subtract(Duration(seconds: _elapsed)));
      }
    } else if (isDwelling) {
      onDwellNotif?.call(dwellCourtName ?? '', _dwellSince!.add(dwellThreshold));
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

  // Gracia de salida: desde cuándo estamos fuera del radio teniendo una sesión
  // activa. null = estamos dentro. Al superar [exitGrace] se corta el partido.
  DateTime? _outsideSince;

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

  /// True si el cronómetro del partido está pausado.
  bool get isPaused => _pausedAt != null;

  /// Pausa o reanuda el cronómetro del partido (un solo botón, como YouTube /
  /// Spotify). Pausado: el tiempo deja de correr y la detección de salida del
  /// radio se congela (no se cierra solo). Al reanudar, sigue desde donde quedó.
  void togglePause() {
    if (!isPlaying) return;
    if (_pausedAt == null) {
      _pausedAt = DateTime.now();
    } else {
      // Reanudar: el tramo pausado se descuenta del tiempo jugado.
      _pausedSeconds += DateTime.now().difference(_pausedAt!).inSeconds;
      _pausedAt = null;
      // Volvemos a evaluar la salida del radio desde cero.
      _outsideSince = null;
    }
    _persistActive();
    _renderSessionNotif();
    notifyListeners();
  }

  /// True cuando estamos acumulando permanencia en una cancha cercana pero el
  /// partido todavía no arrancó (cuenta regresiva de [dwellThreshold] en curso).
  bool get isDwelling =>
      !isPlaying && _dwellCourtId != null && _dwellSince != null;

  /// Nombre de la cancha candidata durante la cuenta regresiva de permanencia.
  String? get dwellCourtName {
    if (_dwellCourtId == null) return null;
    for (final c in _courts) {
      if (c.id == _dwellCourtId) return c.name;
    }
    return null;
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
  /// "pendiente de resultado", igual que si hubiera terminado por salir del radio.
  void stopNow() {
    if (!isPlaying) return;
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
    _resetState();
    await _restore();

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

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _sample(); // primera muestra inmediata
    // El foreground service (con su notificación) ya NO arranca acá: ahora lo
    // gobierna el geofencing (enter de una cancha → enterCourtArea). Con la app
    // abierta, el ticker de arriba ya detecta sin servicio en primer plano.
  }

  /// Llamado al ENTRAR a la zona de una cancha (geofence). Arranca el foreground
  /// service para mantener viva la detección aunque se minimice la app; su
  /// notificación queda justificada porque estás en una cancha.
  void enterCourtArea() {
    if (_background) _startStream();
  }

  /// Llamado al SALIR de la zona de una cancha. Corta el foreground service (y
  /// su notificación). La sesión, si la había, se cierra sola al salir del radio.
  void leaveCourtArea() {
    _stopStream();
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
    _dwellCourtId = null;
    _dwellSince = null;
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
      _renderSessionNotif();
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
    // Un solo pedido de permiso: si ya está concedido (aunque sea "mientras se
    // usa"), arrancamos el servicio en primer plano sin volver a preguntar.
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }
    final LocationSettings settings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 8,
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
        .listen(_evaluate, onError: (_) {});
  }

  void _stopStream() {
    _posSub?.cancel();
    _posSub = null;
  }

  void _tick() {
    if (isPlaying && _startedAt != null) {
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
      }
      notifyListeners();
    } else if (isDwelling) {
      // Sin partido todavía, pero acumulando permanencia: refrescamos cada
      // segundo para que la cuenta regresiva del cronómetro baje en vivo.
      notifyListeners();
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
  /// de cercanía como si estuvieras parado ahí).
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
    _evaluate(_mock!);
  }

  /// Quita la ubicación simulada y vuelve al GPS real en el próximo muestreo.
  void clearMock() => _mock = null;

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
      // ¿Seguimos dentro del radio de la cancha en juego?
      if (near != null && near.id == _courtId) {
        // Volvimos (o nunca salimos): se cancela cualquier gracia de salida.
        if (_outsideSince != null) {
          _outsideSince = null;
          _renderSessionNotif(); // la notif vuelve a "jugando"
        }
        return;
      }
      // Fuera del radio de la cancha actual (o cerca de otra). Arrancamos la
      // gracia de salida: el partido se corta recién si seguimos fuera de forma
      // continua durante [exitGrace]. Un salto de GPS o una pausa corta no lo
      // cierran.
      if (_outsideSince == null) {
        _outsideSince = DateTime.now();
        _renderSessionNotif(); // la notif pasa a "termina en…"
      }
      if (DateTime.now().difference(_outsideSince!) >= exitGrace) {
        _endSession();
        // Si al cerrar ya estábamos dentro de otra cancha, arrancamos su
        // permanencia para detectar el próximo partido.
        if (near != null) _beginDwell(near);
      }
      return;
    }

    if (near == null) {
      // Fuera de toda cancha y sin sesión: resetear permanencia.
      final wasDwelling = _dwellSince != null;
      _dwellCourtId = null;
      _dwellSince = null;
      if (wasDwelling) _renderSessionNotif();
      return;
    }

    // No estamos jugando: acumular permanencia hasta el umbral.
    if (_dwellCourtId != near.id) {
      _beginDwell(near);
    } else if (_dwellSince != null &&
        DateTime.now().difference(_dwellSince!) >= dwellThreshold) {
      _startSession(near);
    }
  }

  void _beginDwell(Court c) {
    _dwellCourtId = c.id;
    _dwellSince = DateTime.now();
    _renderSessionNotif();
  }

  void _startSession(Court c) {
    _courtId = c.id;
    _courtName = c.name;
    _startedAt = DateTime.now();
    _elapsed = 0;
    _lastSavedAt = 0;
    _accrued = 0;
    _pausedAt = null;
    _pausedSeconds = 0;
    _outsideSince = null;
    // No registramos nada todavía: jugada, cancha, tiempo, puntos, racha e
    // historial se computan recién al resolver el resultado (resolvePending),
    // con el partido ya terminado y validado por duración. Acá solo persistimos
    // la sesión activa para poder retomar el cronómetro si se cierra la app.
    _persistActive();
    onPresenceChanged?.call(true, c.id, _startedAt);
    _renderSessionNotif();
    notifyListeners();
  }

  void _endSession() {
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
    onMatchEnded?.call(endedCourtId, endedAt);
    _resetLiveSession();
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

    // Bonus de racha: usa la racha ya incluyendo esta victoria.
    var streakBonus = 0;
    if (result == PlayResult.win) {
      streakBonus = 10 * (_streak + 1);
      _streak++;
    } else if (result == PlayResult.loss) {
      if (_streak > 0) {
        _streakHistory.insert(
            0, StreakEntry(DateTime.now().millisecondsSinceEpoch, _streak));
      }
      _streak = 0;
    }

    // Puntos: base por tiempo + bonus por resultado, racha y cancha nueva.
    final resultBonus = switch (result) {
      PlayResult.win => 50,
      PlayResult.tie => 20,
      PlayResult.training => 15,
      PlayResult.loss => 10,
      PlayResult.notCounted => 0,
    };
    // Los puntos por tiempo se multiplican por la duración (incentivo a jugar
    // partidos largos); los bonus no se multiplican.
    final timePoints = ((p.seconds ~/ 60) * multiplierFor(p.seconds)).round();
    final gained =
        timePoints + resultBonus + streakBonus + (isNewCourt ? 30 : 0);
    _points += gained;

    // Guardamos el partido con los puntos que sumó, para mostrarlos en el
    // historial.
    _log.insert(0, p.withResult(result, points: gained));
    if (_log.length > 100) _log = _log.sublist(0, 100);

    _pendingSession = null;
    await _persistPlays();
    await _persistTotals();
    await _persistLog();
    await _persistStreak();
    await _persistPoints();
    await _clearPending();
    _recomputeBadges();
    _checkLevelUp(); // los puntos ganados pueden haber subido el nivel
    notifyListeners();
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
        // Solo retomamos sesiones recientes (< 6h); la próxima muestra la
        // valida (si ya no estás cerca, se cierra sola).
        if (DateTime.now().difference(start) > const Duration(hours: 6)) {
          await _clearActive();
        } else {
          _courtId = j['courtId'] as String?;
          _courtName = j['courtName'] as String?;
          _startedAt = start;
          _elapsed = DateTime.now().difference(start).inSeconds;
          _lastSavedAt = _elapsed;
          // El tiempo de la sesión en curso todavía NO está en los totales (se
          // vuelca al resolver). Lo dejamos como pendiente para que el
          // cronómetro y el tiempo en vivo lo muestren completo.
          _accrued = 0;
        }
      } catch (_) {
        await _clearActive();
      }
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
        PlayResult.win => 'Ganó',
        PlayResult.loss => 'Perdió',
        PlayResult.tie => 'Empató',
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

  const PlaySession({
    required this.courtId,
    required this.courtName,
    required this.seconds,
    required this.endedAtMillis,
    this.result,
    this.points = 0,
  });

  PlaySession withResult(PlayResult r, {int points = 0}) => PlaySession(
        courtId: courtId,
        courtName: courtName,
        seconds: seconds,
        endedAtMillis: endedAtMillis,
        result: r,
        points: points,
      );

  Map<String, dynamic> toJson() => {
        'courtId': courtId,
        'courtName': courtName,
        'seconds': seconds,
        'endedAt': endedAtMillis,
        'result': result?.name,
        'points': points,
      };

  factory PlaySession.fromJson(Map<String, dynamic> j) => PlaySession(
        courtId: (j['courtId'] ?? '') as String,
        courtName: (j['courtName'] ?? '') as String,
        seconds: (j['seconds'] as num?)?.toInt() ?? 0,
        endedAtMillis: (j['endedAt'] as num?)?.toInt() ?? 0,
        result: PlayResultX.fromName(j['result'] as String?),
        points: (j['points'] as num?)?.toInt() ?? 0,
      );
}

/// Tipo de recompensa que dispara una notificación in-app.
enum RewardKind { achievement, title, levelUp }

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
