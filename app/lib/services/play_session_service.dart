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
  static const double radiusMeters = 80;
  static const Duration dwellThreshold = Duration(minutes: 7);
  static const Duration _sampleEvery = Duration(seconds: 10);
  // Cada cuánto se suben los agregados a Notion (batch). El historial y los
  // favoritos NO se suben: quedan locales.
  static const Duration _syncEvery = Duration(minutes: 2);
  static const String _kActive = 'play_active_session';
  static const String _kTotals = 'play_totals_by_court';
  static const String _kBackground = 'play_background_enabled';
  static const String _kPlays = 'play_total_count';
  static const String _kLog = 'play_log';
  static const String _kPending = 'play_pending_result';
  static const String _kStreak = 'play_streak';
  static const String _kStreakHist = 'play_streak_history';
  static const String _kPoints = 'play_points';
  static const String _kBadges = 'play_unlocked_badges';
  static const String _kNotifs = 'reward_notifications';

  List<Court> _courts = const [];
  Timer? _ticker;
  StreamSubscription<Position>? _posSub;
  bool _background = false;

  /// Si el usuario habilitó la detección en segundo plano.
  bool get backgroundEnabled => _background;

  /// Notifica cuando empieza/termina un partido, para propagar la presencia
  /// (ej. actualizar el estado "Jugando" en Notion vía Session).
  void Function(bool playing, String courtId, DateTime? since)? onPresenceChanged;

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

  // Sesión activa.
  String? _courtId;
  String? _courtName;
  DateTime? _startedAt;
  int _elapsed = 0; // segundos
  int _lastSavedAt = 0; // segundos transcurridos en el último guardado
  int _accrued = 0; // segundos de la sesión ya sumados a los totales

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

  /// Segundos del tramo de la sesión activa todavía no volcados a los totales.
  int get _pending => isPlaying ? (_elapsed - _accrued) : 0;

  /// Tiempo total jugado (todas las canchas), incluyendo la sesión en curso.
  int get totalSeconds =>
      _totals.values.fold(0, (a, b) => a + b.seconds) + _pending;

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

  /// Formatea segundos como "1h 23m" / "45m" / "30s".
  static String fmt(int seconds) {
    if (seconds >= 3600) {
      final h = seconds ~/ 3600;
      final m = (seconds % 3600) ~/ 60;
      return m > 0 ? '${h}h ${m}m' : '${h}h';
    }
    if (seconds >= 60) return '${seconds ~/ 60}m';
    return '${seconds}s';
  }

  /// Arranca el muestreo de ubicación (pide permiso si hace falta).
  ///
  /// [seedPoints]/[seedPlays]/[seedStreak] vienen del perfil de Notion: si la
  /// nube tiene valores más altos que los locales (p.ej. tras reinstalar), se
  /// adoptan para no perder progreso ni bajar de nivel.
  Future<void> startTracking({
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
    // Al minimizar/cerrar la app subimos lo pendiente: el timer solo corre con
    // la app abierta, así no perdemos lo acumulado en el último tramo.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _flush();
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
          notificationText: 'Estás en una cancha · registrando tu tiempo',
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
      _elapsed = DateTime.now().difference(_startedAt!).inSeconds;
      // Guardado periódico cada 30s: vuelca el tramo al total de la cancha.
      if (_elapsed - _lastSavedAt >= 30) {
        _lastSavedAt = _elapsed;
        _flushAccrual();
        _persistActive();
      }
      notifyListeners();
    }
    _tickCount++;
    if (_tickCount % _sampleEvery.inSeconds == 0) _sample();
  }

  /// Suma el tramo no contabilizado de la sesión al total de la cancha.
  void _flushAccrual() {
    if (_courtId == null) return;
    final delta = _elapsed - _accrued;
    if (delta <= 0) return;
    final cur = _totals[_courtId!];
    _totals[_courtId!] = _CourtPlay(
      cur?.name.isNotEmpty == true ? cur!.name : (_courtName ?? ''),
      (cur?.seconds ?? 0) + delta,
    );
    _accrued = _elapsed;
    _persistTotals();
  }

  Future<void> _sample() async {
    if (_sampling) return;
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
    // Descartamos lecturas demasiado imprecisas para un radio de 40m.
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

    if (near == null) {
      // Fuera de toda cancha: cortar sesión y resetear permanencia.
      _dwellCourtId = null;
      _dwellSince = null;
      if (isPlaying) _endSession();
      return;
    }

    if (isPlaying) {
      // Si nos movimos a otra cancha, cerramos la actual y empezamos a contar
      // permanencia en la nueva.
      if (near.id != _courtId) {
        _endSession();
        _beginDwell(near);
      }
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
  }

  void _startSession(Court c) {
    _courtId = c.id;
    _courtName = c.name;
    _startedAt = DateTime.now();
    _elapsed = 0;
    _lastSavedAt = 0;
    _accrued = 0;
    // Registramos la cancha en el historial al instante (cuenta como "única"
    // aunque todavía no haya acumulado segundos) y sumamos una jugada total.
    _totals.putIfAbsent(c.id, () => _CourtPlay(c.name, 0));
    _totalPlays++;
    _persistTotals();
    _persistPlays();
    _persistActive();
    _recomputeBadges();
    onPresenceChanged?.call(true, c.id, _startedAt);
    notifyListeners();
  }

  void _endSession() {
    _flushAccrual(); // vuelca el tramo final al total de la cancha
    onPresenceChanged?.call(false, '', null);
    // Dejamos el partido "pendiente de resultado": la UI le preguntará al
    // usuario cómo le fue (Ganó/Perdió/Empató/...).
    _pendingSession = PlaySession(
      courtId: _courtId ?? '',
      courtName: _courtName ?? '',
      seconds: _elapsed,
      endedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
    _persistPending();
    _courtId = null;
    _courtName = null;
    _startedAt = null;
    _elapsed = 0;
    _lastSavedAt = 0;
    _accrued = 0;
    _clearActive();
    notifyListeners();
  }

  /// Registra el resultado elegido por el usuario para el partido pendiente.
  /// Win extiende la racha; loss la corta (y la guarda en el historial de
  /// rachas); el resto (empate / no contó / entrenamiento) no afecta la racha.
  Future<void> resolvePending(PlayResult result) async {
    final p = _pendingSession;
    if (p == null) return;

    // ¿Primera vez en esta cancha? (antes de insertar el partido al log)
    final isNewCourt = !_log.any((e) => e.courtId == p.courtId);

    _log.insert(0, p.withResult(result));
    if (_log.length > 100) _log = _log.sublist(0, 100);

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
    final gained =
        (p.seconds ~/ 60) + resultBonus + streakBonus + (isNewCourt ? 30 : 0);
    _points += gained;

    _pendingSession = null;
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
          // No recontamos lo previo al cierre: el total ya lo tenía (hasta el
          // último flush). Marcamos lo transcurrido como ya volcado.
          _accrued = _elapsed;
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

  const PlaySession({
    required this.courtId,
    required this.courtName,
    required this.seconds,
    required this.endedAtMillis,
    this.result,
  });

  PlaySession withResult(PlayResult r) => PlaySession(
        courtId: courtId,
        courtName: courtName,
        seconds: seconds,
        endedAtMillis: endedAtMillis,
        result: r,
      );

  Map<String, dynamic> toJson() => {
        'courtId': courtId,
        'courtName': courtName,
        'seconds': seconds,
        'endedAt': endedAtMillis,
        'result': result?.name,
      };

  factory PlaySession.fromJson(Map<String, dynamic> j) => PlaySession(
        courtId: (j['courtId'] ?? '') as String,
        courtName: (j['courtName'] ?? '') as String,
        seconds: (j['seconds'] as num?)?.toInt() ?? 0,
        endedAtMillis: (j['endedAt'] as num?)?.toInt() ?? 0,
        result: PlayResultX.fromName(j['result'] as String?),
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
