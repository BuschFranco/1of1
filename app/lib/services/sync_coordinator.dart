import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:native_geofence/native_geofence.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/courts.dart';
import 'analytics_service.dart';
import 'api/api_client.dart';
import 'cache/api_cache.dart';
import 'courts_provider.dart';
import 'app_permissions.dart';
import 'blocked_provider.dart';
import 'favorites_provider.dart';
import 'geofence_service.dart';
import 'notifications_service.dart';
import 'pickups_provider.dart';
import 'play_session_service.dart';
import 'session.dart';
import 'session_alarms.dart';

/// Conecta la sesión del usuario con el detector de partidos
/// ([PlaySessionService]) y el catálogo de canchas ([CourtsProvider]).
///
/// Centraliza el "pegamento" de sincronización que antes vivía en HomeScreen:
///  - propaga la presencia "Jugando" a Notion ([Session.setPresence]),
///  - cablea el batch ([PlaySessionService.onFlush] → stagear stats + flush),
///  - alimenta la detección de cercanía con las canchas vigentes,
///  - al iniciar sesión arranca el tracking sembrando el progreso desde Notion,
///  - al cerrar sesión detiene el tracking.
///
/// No es un widget: no depende del árbol de UI. Se crea una sola vez al arrancar
/// la app (main.dart) y vive mientras la app esté abierta.
class SyncCoordinator with WidgetsBindingObserver {
  SyncCoordinator({
    required Session session,
    required PlaySessionService play,
    required CourtsProvider courts,
    required FavoritesProvider favorites,
    required PickupsProvider pickups,
    required BlockedProvider blocked,
  })  : _session = session,
        _play = play,
        _courts = courts,
        _favorites = favorites,
        _pickups = pickups,
        _blocked = blocked {
    _wire();
  }

  final Session _session;
  final PlaySessionService _play;
  final CourtsProvider _courts;
  final FavoritesProvider _favorites;
  final PickupsProvider _pickups;
  final BlockedProvider _blocked;

  // Evita arrancar el tracking más de una vez por sesión (Session notifica en
  // cada cambio de perfil, no solo al loguear).
  bool _trackingStarted = false;
  // Si ya apagamos el background por falta de sesión (mismo motivo de
  // idempotencia que _trackingStarted).
  bool _alarmsCleared = false;
  // Cantidad de canchas con la que se registraron geofences por última vez
  // (para no re-registrar en cada notify del catálogo).
  int _geofencedCount = -1;
  // Si el radar periódico de background está programado (evita re-programarlo
  // en cada sync, lo que reiniciaría su fase).
  bool _radarOn = false;
  // Si el watchdog del radar está programado. Va de la mano con `_radarOn`:
  // vive/muere con las mismas condiciones (sesión + background + permiso
  // "Siempre"), pero es su propia alarma.
  bool _watchdogOn = false;

  // ── Respaldo del historial en el servidor ───────────────────────────────
  /// Verdadero recién cuando el restore terminó BIEN. Hasta entonces NO se suben
  /// las listas (favoritos, bloqueados, rachas): el PUT REEMPLAZA el contenido, y
  /// en una instalación nueva subiría listas vacías encima de las del servidor,
  /// borrando justo lo que se quería proteger.
  bool _historyReady = false;
  bool _syncingHistory = false;
  String _historyUserKey = '';

  /// Último contenido de cada lista que el servidor ya tiene (kind → JSON), para
  /// no volver a subir lo que no cambió.
  final Map<String, String> _lastPushedData = {};

  /// Si el aviso de reenganche está programado. Igual que `_radarOn`, el flag
  /// se enciende DESPUÉS de que la programación haya terminado bien.
  bool _nudgeOn = false;

  /// Último valor visto de `Session.offline`, para detectar la reconexión.
  bool _wasOffline = false;

  /// Bloqueos hechos sin conexión cuyo `DELETE /friends/:id` falló: se
  /// reintentan en cada flush hasta que entren.
  static String _unfriendKey(String uk) => 'pending_unfriend::$uk';

  void _wire() {
    // Presencia "Jugando" → Notion (best-effort, con reintento vía batch).
    // Además dispara una notificación del sistema en cada arranque/cierre de
    // partido: son eventos siempre visibles (a diferencia de las recompensas,
    // que dependen de desbloquear algo), así que sirven de feedback y de prueba
    // de que el canal de notificaciones funciona.
    _play.onPresenceChanged = (playing, courtId, since) {
      _session.setPresence(playing: playing, courtId: courtId, since: since);
      if (playing) {
        AnalyticsService.event(
            'play_session_start', {'court_id': courtId, 'trigger': 'app'});
      }
      if (playing) {
        final name = _courtNameById(courtId);
        NotificationsService.instance.show(
          '¡Arrancó tu sesión de juego!',
          name == null
              ? 'Estamos contando tu tiempo en la cancha.'
              : 'Contando tu tiempo en $name.',
        );
      }
    };

    // Terminó un partido válido: avisamos para que registre el resultado y
    // guardamos el "último partido" (cancha + momento) para mostrar a los amigos.
    _play.onMatchEnded = (courtId, endedAt, lowBattery) {
      if (lowBattery) {
        NotificationsService.instance.show(
          'Sesión terminada por batería baja',
          'Cerramos tu sesión para proteger tu información. Abrí 1of1 para '
              'registrar el resultado.',
        );
      } else {
        NotificationsService.instance.show(
          'Terminó tu sesión de juego',
          'Abrí 1of1 para registrar el resultado.',
        );
      }
      _session.setLastPlayed(courtId: courtId, at: endedAt);
    };

    // Partido demasiado corto (< 13 min): no se registró.
    _play.onMatchDiscarded = (court, seconds) {
      AnalyticsService.event('play_session_discard',
          {'minutes': seconds ~/ 60, 'reason': 'too_short'});
      final mins = seconds ~/ 60;
      final dur = mins > 0 ? '$mins min' : '$seconds s';
      NotificationsService.instance.show(
        'Sesión no registrada',
        'Duró solo $dur, muy poco para contar como sesión. '
            'No suma puntos ni queda en el historial.',
      );
    };

    // Geofencing del SO: enter/exit de la zona de una cancha arranca/corta el
    // foreground service (así la notificación persistente solo aparece estando
    // en una cancha, no todo el tiempo).
    GeofenceService.instance.onEvent = (event, courtIds) {
      if (event == GeofenceEvent.enter) {
        _play.enterCourtArea();
      } else if (event == GeofenceEvent.exit) {
        _play.leaveCourtArea();
      }
    };
    // Al cambiar la preferencia de background, registramos o quitamos geofences.
    _play.onBackgroundChanged = (_) => unawaited(_syncGeofences());
    // Al cambiar la preferencia del aviso de reenganche, programamos o
    // cancelamos su alarma. Es independiente de las geofences: el aviso no
    // necesita ubicación ni permiso "Siempre", solo leer prefs.
    _play.onNudgeChanged = (_) => unawaited(_syncNudge());

    // Cada recompensa (logro/título/nivel) también dispara un push del sistema.
    // chatCreated se salta: solo se muestra el banner in-app.
    _play.onReward = (r) {
      if (r.kind == RewardKind.chatCreated) return;
      NotificationsService.instance.show(r.headline, r.name);
    };

    // Notificación de sesión (cronómetro persistente con la app minimizada).
    _play.onDwellNotif = (court, remainingSeconds) =>
        NotificationsService.instance.showDwellCountdown(court, remainingSeconds);
    _play.onArrivalNotif = (court, minutes) =>
        NotificationsService.instance.showArrivalAlert(court, minutes);
    _play.onPlayingNotif = (court, startedAt) =>
        NotificationsService.instance.showPlaying(court, startedAt);
    _play.onEndingNotif = (court, endsAt) =>
        NotificationsService.instance.showEndingCountdown(court, endsAt);
    _play.onPausedNotif = (court, elapsed) =>
        NotificationsService.instance.showPaused(court, elapsed);
    _play.onClearSessionNotif = () =>
        NotificationsService.instance.cancelSession();
    // Pregunta de partido largo (3h): mostrar/quitar la notif y avisos de sus
    // desenlaces (tiempo límite / cancelado por no responder).
    _play.onConfirmNotif = (court) =>
        NotificationsService.instance.showContinueCheck(court);
    _play.onCancelConfirmNotif = () =>
        NotificationsService.instance.cancelContinueCheck();
    _play.onNoticeNotif = (title, body) =>
        NotificationsService.instance.show(title, body);
    // Botones de la notificación → arrancan/detienen/pausan el partido (vivo).
    NotificationsService.instance.onStartNowAction = () => _play.startNow();
    NotificationsService.instance.onStopAction = () => _play.stopNow();
    NotificationsService.instance.onPauseAction = () => _play.togglePause();
    NotificationsService.instance.onDeclineAction =
        () => unawaited(_play.declineDwell());
    NotificationsService.instance.onConfirmYesAction =
        () => unawaited(_play.confirmContinue());
    NotificationsService.instance.onConfirmNoAction =
        () => unawaited(_play.confirmStop());

    // Batch: cuando el service lo pide (cada 2 min / al pausar / cerrar),
    // stageamos las stats actuales y subimos TODO el perfil en una sola
    // petición (incluye nivel, logros, tiempo y ediciones de perfil pendientes).
    _play.onFlush = _flushAll;

    // El catálogo de canchas alimenta la detección de cercanía.
    _courts.addListener(_pushCourts);
    _pushCourts();

    // Arranca/detiene el tracking según haya o no sesión activa.
    _session.addListener(_onSessionChanged);
    _onSessionChanged();

    // Modo offline: al volver a primer plano se reintenta la conexión.
    WidgetsBinding.instance.addObserver(this);

    // Modo offline EN VIVO (antes solo se decidía al arrancar). Dos señales:
    // el SO (se apagó wifi/datos, modo avión) y las propias requests (wifi
    // conectado pero sin salida a internet, que el SO no ve).
    ApiClient.onNetworkError = _session.goOffline;
    ApiClient.onNetworkOk = () {
      if (_session.offline) unawaited(_session.reconnect());
    };
    _connSub = Connectivity().onConnectivityChanged.listen(_onConnectivity);
  }

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _noNetTimer;
  Timer? _retryTimer;
  bool _foreground = true;

  /// Cada cuánto se reintenta mientras está offline y en primer plano: cubre
  /// el wifi sin internet que vuelve y el server que se despierta.
  static const _kRetryEvery = Duration(seconds: 30);

  void _onConnectivity(List<ConnectivityResult> r) {
    final none = r.isEmpty || r.every((c) => c == ConnectivityResult.none);
    _noNetTimer?.cancel();
    if (none) {
      // Margen corto: al pasar de wifi a datos el SO avisa "sin red" un
      // instante y no queremos parpadear el modo offline.
      _noNetTimer = Timer(const Duration(seconds: 2), () async {
        final now = await Connectivity().checkConnectivity();
        if (now.isEmpty || now.every((c) => c == ConnectivityResult.none)) {
          _session.goOffline();
        }
      });
    } else if (_session.offline) {
      unawaited(_session.reconnect());
    }
  }

  /// Reintento periódico mientras dure el modo offline (solo en primer plano).
  void _syncRetryTimer() {
    final want = _session.offline && _foreground;
    if (want && _retryTimer == null) {
      _retryTimer = Timer.periodic(_kRetryEvery, (_) {
        if (_session.offline) unawaited(_session.reconnect());
      });
    } else if (!want) {
      _retryTimer?.cancel();
      _retryTimer = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncRetryTimer();
    if (state == AppLifecycleState.resumed && _session.offline) {
      unawaited(_session.reconnect());
    }
  }

  /// Volvió la conexión: subir YA todo lo pendiente (sin esperar el timer de
  /// 2 min) y retomar lo que el arranque offline salteó.
  void _onReconnected(String userKey) {
    unawaited(_courts.load(force: true));
    unawaited(_flushAll());
    unawaited(_backfillMatchLog(userKey));
    unawaited(_pickups
        .loadForUser(userKey)
        .then((_) => _checkRescheduledPickups(userKey)));
    unawaited(_checkCourtDecisions(userKey));
  }

  Future<void> _flushAll() async {
    await _session.stageStats(
      games: _play.totalPlays,
      courts: _play.uniqueCourtsCount,
      streak: _play.streak,
      points: _play.points,
      level: _play.level.toString(),
      unlockedBadges: _play.unlockedBadges.toList(),
      playSeconds: _play.committedSeconds,
      playTimeByCourt: _play.totalsJson,
    );
    await _session.flush();
    await _flushPendingMatches();
    await _flushPendingSessions();
    await _flushPendingUnfriends();
    // Si el restore no pudo correr al arrancar (sin red), reintenta acá.
    if (!_historyReady && !_syncingHistory && _historyUserKey.isNotEmpty) {
      unawaited(_syncHistory(_historyUserKey));
    }
    await _pushLists();
  }

  /// Encola el `DELETE /friends/:id` de un bloqueo hecho sin conexión.
  Future<void> queueUnfriend(String friendshipId) async {
    final uk = _historyUserKey;
    if (uk.isEmpty || friendshipId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_unfriendKey(uk)) ?? <String>[];
    if (!list.contains(friendshipId)) list.add(friendshipId);
    await prefs.setStringList(_unfriendKey(uk), list);
  }

  Future<void> _flushPendingUnfriends() async {
    final uk = _historyUserKey;
    final api = ApiClient();
    if (uk.isEmpty || !api.isConfigured || !api.hasToken) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_unfriendKey(uk)) ?? const <String>[];
    if (list.isEmpty) return;
    final left = <String>[];
    for (final id in list) {
      try {
        await api.removeFriend(id);
      } on ApiException catch (e) {
        // 404: la amistad ya no existe, no hay nada que reintentar.
        if (e.statusCode != 404) left.add(id);
      } catch (_) {
        left.add(id);
      }
    }
    if (left.isEmpty) {
      await prefs.remove(_unfriendKey(uk));
    } else {
      await prefs.setStringList(_unfriendKey(uk), left);
    }
  }

  /// Sube EN UN LOTE los partidos pendientes al backend (POST /matches, para
  /// el ranking por período; el email sale del token). Best-effort: si la
  /// request entera falla, todo queda en el buffer; si el server responde,
  /// solo se conservan los ítems con ok:false. Reintento en el próximo flush.
  Future<void> _flushPendingMatches() async {
    final api = ApiClient();
    if (!api.isConfigured || !api.hasToken) return;
    final pending = await _play.readPendingMatches();
    if (pending.isEmpty) return;
    final failed = <Map<String, dynamic>>[];
    try {
      final res = await api.postMatches([
        for (final m in pending)
          {
            'points': (m['points'] as num?)?.toInt() ?? 0,
            'endedAt': (m['endedAt'] ?? '') as String,
            'courtId': (m['courtId'] ?? '') as String,
            'courtName': (m['courtName'] ?? '') as String,
            if ((m['result'] ?? '') != '') 'result': m['result'] as String,
            'seconds': (m['seconds'] as num?)?.toInt() ?? 0,
          }
      ]);
      final results = (res['results'] as List?) ?? const [];
      for (var i = 0; i < pending.length; i++) {
        final ok = i < results.length && (results[i] as Map)['ok'] == true;
        if (!ok) failed.add(pending[i]);
      }
    } catch (_) {
      failed.addAll(pending); // sin red: reintento completo en el próximo flush
    }
    await _play.writePendingMatches(failed);
  }

  /// Nombre de una cancha por id (para el texto de la notificación). null si no
  /// está en el catálogo cargado o el id viene vacío (p. ej. al cerrar).
  String? _courtNameById(String id) {
    if (id.isEmpty) return null;
    for (final c in _courts.courts) {
      if (c.id == id) return c.name;
    }
    return null;
  }

  void _pushCourts() {
    _play.setCourts(_courts.courts);
    unawaited(_syncGeofences());
  }

  /// Registra (o quita) las geofences de las canchas y el radar periódico de
  /// respaldo según haya sesión, esté habilitada la detección en background,
  /// haya canchas cargadas Y el permiso de ubicación sea "Siempre" — sin ese
  /// permiso Android no entrega geofences ni GPS en background: registrarlas
  /// solo daría una falsa sensación de que funciona. Evita re-registrar si la
  /// cantidad de canchas no cambió.
  /// Programa o cancela el aviso de "hace días que no jugás".
  ///
  /// Aparte de `_syncGeofences` a propósito: aquel exige permiso de ubicación
  /// "Siempre" y canchas cargadas, y el aviso no necesita ninguna de las dos
  /// cosas — su callback solo lee prefs. Metido ahí adentro, el usuario que no
  /// dio background nunca recibiría el aviso, que es justo el que más lejos
  /// está de volver a la cancha.
  Future<void> _syncNudge() async {
    final on = _session.profile != null && _play.nudgeEnabled;
    if (!on) {
      if (_nudgeOn) {
        _nudgeOn = false;
        unawaited(cancelNudge());
      }
      return;
    }
    if (!_nudgeOn) {
      _nudgeOn = true;
      unawaited(scheduleNudge().onError((_, _) => _nudgeOn = false));
    }
  }

  Future<void> _syncGeofences() async {
    final loggedIn = _session.profile != null;
    final courts = _courts.courts;
    var always = false;
    try {
      always = await Geolocator.checkPermission() == LocationPermission.always;
    } catch (_) {}
    // Refrescar el permiso de alarmas exactas persistido para los isolates de
    // background (`can_schedule_exact`). Lo escribe checkPermissions(), que
    // hasta acá SOLO se llamaba al abrir el modal de permisos: quien nunca lo
    // abría —o lo revocaba después— dejaba la clave ausente o vieja, y
    // `_oneShotAt` programaba alarmas exactas que el SO descarta en silencio.
    unawaited(checkPermissions());
    if (!loggedIn || !_play.backgroundEnabled || courts.isEmpty || !always) {
      if (_geofencedCount != 0) {
        _geofencedCount = 0;
        GeofenceService.instance.clear();
      }
      if (_radarOn) {
        _radarOn = false;
        unawaited(cancelRadarWatch());
      }
      if (_watchdogOn) {
        _watchdogOn = false;
        unawaited(cancelWatchdog());
      }
      return;
    }
    // El flag se marca DESPUÉS de que la programación haya terminado, no antes:
    // si falla, tiene que quedar en false para que el próximo sync reintente.
    // Marcarlo antes (como estaba) dejaba el radar apagado para toda la vida
    // del proceso ante un solo fallo, sin ninguna señal.
    if (!_radarOn) {
      _radarOn = true;
      unawaited(scheduleRadarWatch().onError((_, _) => _radarOn = false));
    }
    if (!_watchdogOn) {
      _watchdogOn = true;
      unawaited(scheduleWatchdog().onError((_, _) => _watchdogOn = false));
    }
    if (_geofencedCount == courts.length) return; // sin cambios relevantes
    // Cache global de canchas para que el radar (isolate sin memoria
    // compartida) pueda medir cercanía.
    unawaited(_writeCourtsGeoCache(courts));
    // El contador se marca DESPUÉS de que el registro haya terminado bien —
    // mismo criterio que `_radarOn` acá arriba. Marcarlo antes (como estaba)
    // daba las geofences por puestas aunque el registro fallara, y como
    // `syncCourts` se tragaba toda excepción, el equipo se quedaba sin
    // detección instantánea para toda la vida del proceso, sin ninguna señal.
    final ok = await GeofenceService.instance
        .syncCourts(courts, origin: await _lastKnownLatLng());
    _geofencedCount = ok ? courts.length : 0;
  }

  /// Última posición conocida, para priorizar qué canchas vigilar cuando hay
  /// más de las que Android permite. Best-effort: si no hay fix reciente
  /// devuelve null y el recorte cae al orden del catálogo.
  Future<(double, double)?> _lastKnownLatLng() async {
    try {
      final p = await Geolocator.getLastKnownPosition();
      if (p != null) return (p.latitude, p.longitude);
    } catch (_) {/* sin permiso o sin fix: no es crítico */}
    return null;
  }

  Future<void> _writeCourtsGeoCache(List<Court> courts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        kCourtsGeoCacheKey,
        jsonEncode([
          for (final c in courts)
            if (!(c.lat == 0 && c.lng == 0))
              {'id': c.id, 'name': c.name, 'lat': c.lat, 'lng': c.lng},
        ]),
      );
    } catch (_) {}
  }

  void _onSessionChanged() {
    _syncRetryTimer();
    final p = _session.profile;
    if (p == null) {
      // Ventana de arranque: todavía no sabemos si hay sesión (restore/verify en
      // curso). NO tocar las alarmas acá o cancelaríamos el cierre de un partido
      // legítimo en curso en CADA arranque de la app.
      if (_session.restoring || _session.verifying) return;

      // Cierre de sesión: frenamos el tracking y limpiamos el estado en memoria
      // (puntos, logros, historial) para que NO se filtren a la próxima cuenta.
      if (_trackingStarted) {
        _play.resetForLogout();
        _favorites.clearForLogout();
        _pickups.clearForLogout();
        _blocked.clearForLogout();
        ApiCache.clear(); // no filtrar datos cacheados a la próxima cuenta
        _trackingStarted = false;
        _historyReady = false;
        _historyUserKey = '';
        _lastPushedData.clear();
      }

      // Sin sesión: apagar TODO el background una sola vez. Va FUERA del if de
      // arriba a propósito: el caso más común es que la app arranque ya
      // deslogueada (_trackingStarted == false), y si no limpiamos, una
      // permanencia sembrada en la corrida anterior arranca un partido y
      // notifica sin sesión. La sesión activa persistida NO se borra: es
      // namespaced por usuario y se readopta al volver a loguearse (si tiene
      // menos de 6 h).
      if (!_alarmsCleared) {
        _alarmsCleared = true;
        _geofencedCount = -1;
        _radarOn = false;
        _watchdogOn = false;
        _nudgeOn = false;
        GeofenceService.instance.clear();
        unawaited(cancelAllPlayAlarms());
        // Notificaciones ya posteadas que sobrevivirían al logout.
        unawaited(NotificationsService.instance.cancelSession());
        unawaited(NotificationsService.instance.cancelContinueCheck());
      }
      return;
    }
    _alarmsCleared = false; // hay sesión: al cerrarla hay que volver a limpiar
    // Pulso máximo de referencia para las zonas cardíacas (220 − edad).
    _play.setUserBirthdate(p.birthdate);
    // Se arranca con el perfil cacheado aunque `GET /me` siga en vuelo: el
    // tracking es local (historial, sesión en curso, alarmas) y lo de red es
    // best-effort con reintento. Antes se esperaba la verificación, y eso
    // atrasaba el banner de una sesión en curso hasta 4 s al abrir la app. Si
    // `/me` da 401, el logout pasa por la rama de arriba y limpia todo.
    final offline = _session.offline;
    final reconnected = _wasOffline && !offline;
    _wasOffline = offline;
    if (_trackingStarted) {
      if (reconnected && _historyUserKey.isNotEmpty) {
        _onReconnected(_historyUserKey);
      }
      return;
    }
    _trackingStarted = true;
    // Clave por usuario: aísla los datos locales de cada cuenta en el dispositivo.
    final userKey = (_session.email ?? p.userEmail).trim().toLowerCase();
    _favorites.setUser(userKey);
    // Con sesión (JWT) recién disponible: (re)cargar el catálogo. El load()
    // del arranque pudo haber corrido sin token (401/lista vacía).
    if (_courts.courts.isEmpty) unawaited(_courts.load());
    // Cargar los pickups/invitaciones del usuario (para el badge de la campana y
    // las notificaciones del perfil, sin depender de abrir la pestaña Crew).
    // Con la lista ya cargada, avisamos los que el creador reprogramó.
    unawaited(_pickups
        .loadForUser(userKey)
        .then((_) => _checkRescheduledPickups(userKey)));
    // Lista local de usuarios bloqueados de esta cuenta.
    unawaited(_blocked.loadForUser(userKey));
    // Sembrar desde Notion para no perder progreso tras reinstalar.
    final tracking = _play.startTracking(
      userKey: userKey,
      seedPoints: p.points,
      seedPlays: p.games,
      seedStreak: p.streak,
      seedBadges: p.unlockedBadges,
      seedTotalsJson: p.playTimeByCourt,
    );
    unawaited(_syncGeofences());
    // Subir una única vez el historial local que quedó sin registrar en la DB
    // Partidos (partidos anteriores a la migración al backend). Recién cuando
    // el tracking terminó de restaurar (el log local ya está cargado).
    unawaited(tracking.then((_) => _backfillMatchLog(userKey)));
    // Respaldo del historial: restaurar lo que el servidor tenga (reinstalación o
    // celular nuevo) y subir lo que todavía no está. Después de `startTracking`
    // porque necesita el log local ya cargado.
    _historyUserKey = userKey;
    unawaited(tracking.then((_) => _syncHistory(userKey)));
    // Después del restore: recién ahí `startTracking` dejó el userKey para los
    // isolates y se sembró la fecha de la última sesión.
    unawaited(tracking.then((_) => _syncNudge()));
    // Avisar decisiones de moderación sobre las canchas que propuso el usuario
    // (se aprobaron/rechazaron desde la última vez que abrió la app).
    unawaited(_checkCourtDecisions(userKey));
  }

  /// Backfill one-time del log local a la DB Partidos: los rankings por
  /// período leen esa DB, que existe recién desde la migración al backend —
  /// sin esto, lo jugado antes no aparece en semana/mes/temporada ni cuenta
  /// para el clan. Dedup contra lo ya registrado comparando endedAt al minuto
  /// (Notion puede normalizar el ISO). El flag se marca solo si todo subió OK.
  Future<void> _backfillMatchLog(String userKey) async {
    final api = ApiClient();
    if (!api.isConfigured || !api.hasToken || userKey.isEmpty) return;
    final flag = 'log_backfill_done::$userKey';
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(flag) ?? false) return;

      // Dedup por RELOJ DE PARED al minuto ("yyyy-MM-ddTHH:mm"): la app sube
      // hora local sin offset y Notion la devuelve con "+00:00" — comparar por
      // epoch correría 3 h y duplicaría. Los componentes de fecha/hora, en
      // cambio, se conservan tal cual.
      String wallMinute(String iso) =>
          iso.length >= 16 ? iso.substring(0, 16) : iso;
      final mine = await api.myMatches();
      final known = <String>{
        for (final s in (mine['endedAt'] as List? ?? const []))
          wallMinute(s.toString()),
      };
      // También evitar duplicar lo que espera en el buffer pendiente.
      for (final m in await _play.readPendingMatches()) {
        known.add(wallMinute((m['endedAt'] ?? '').toString()));
      }

      final missing = [
        for (final s in _play.log)
          if (s.points > 0 &&
              !known.contains(wallMinute(
                  DateTime.fromMillisecondsSinceEpoch(s.endedAtMillis)
                      .toIso8601String())))
            {
              'points': s.points,
              'endedAt': DateTime.fromMillisecondsSinceEpoch(s.endedAtMillis)
                  .toIso8601String(),
              'courtId': s.courtId,
              'courtName': s.courtName,
              if (s.result != null) 'result': s.result!.name,
              'seconds': s.seconds,
            },
      ];

      if (missing.isNotEmpty) {
        final res = await api.postMatches(missing);
        final results = (res['results'] as List?) ?? const [];
        final allOk = results.length == missing.length &&
            results.every((r) => (r as Map)['ok'] == true);
        if (!allOk) return; // reintento en el próximo arranque
      }
      await prefs.setBool(flag, true);
    } catch (_) {
      // Sin red / error: se reintenta en el próximo inicio de sesión.
    }
  }

  // ── Respaldo del historial ──────────────────────────────────────────────

  static const _kSyncBatch = 50; // el servidor rechaza lotes mayores

  /// Cada cuánto se vuelven a bajar las listas de respaldo (`GET /sync/data`)
  /// una vez restaurado el equipo.
  static const _kSyncDataEvery = Duration(hours: 12);
  static String _syncAtKey(String uk) => 'sync_data_at::$uk';
  static String _pushedKey(String uk) => 'sync_pushed::$uk';

  /// Guarda qué tiene el servidor de cada lista (ver `_lastPushedData`).
  Future<void> _savePushed() async {
    final uk = _historyUserKey;
    if (uk.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pushedKey(uk), jsonEncode(_lastPushedData));
    } catch (_) {}
  }

  /// Sube lo pendiente: sesiones que se cerraron (o cambiaron) desde la última
  /// vez. Es un upsert por (email, endedAtMs) del lado del servidor, así que
  /// reintentar NUNCA duplica, incluso si la respuesta se perdió.
  Future<void> _flushPendingSessions() async {
    final api = ApiClient();
    if (!api.isConfigured || !api.hasToken) return;
    final pending = await _play.readPendingSessions();
    if (pending.isEmpty) return;

    final sent = <String>{}; // entradas (JSON) que el servidor confirmó
    for (var i = 0; i < pending.length; i += _kSyncBatch) {
      final end = i + _kSyncBatch > pending.length ? pending.length : i + _kSyncBatch;
      final chunk = pending.sublist(i, end);
      try {
        final res = await api.syncSessions(chunk);
        final results = (res['results'] as List?) ?? const [];
        for (var j = 0; j < chunk.length; j++) {
          final ok = j < results.length && (results[j] as Map)['ok'] == true;
          if (ok) sent.add(jsonEncode(chunk[j]));
        }
      } catch (_) {/* sin red: queda todo en la cola */}
    }
    if (sent.isEmpty) return;

    // Se vuelve a leer la cola y se quita SOLO lo confirmado, comparando el
    // contenido: mientras la request volaba pudo entrar una sesión nueva, o
    // cambiar la visibilidad de una ya encolada, y escribir `failed` a secas
    // pisaría esa versión más nueva.
    final current = await _play.readPendingSessions();
    await _play.writePendingSessions(
        [for (final m in current) if (!sent.contains(jsonEncode(m))) m]);
  }

  /// Restaura del servidor lo que falte y sube lo que el servidor todavía no
  /// tiene. Corre en cada inicio de sesión; es idempotente.
  ///
  /// - Sesiones: se bajan SOLO la primera vez en este dispositivo (flag
  ///   `history_restored::uk`); después lo local ya es la fuente.
  /// - Listas (rachas, favoritos, bloqueados): se bajan siempre (es chico) para
  ///   saber qué tiene el servidor y no volver a subirlo.
  /// - Todo es unión: restaurar nunca quita nada, y nunca desbloquea a nadie.
  Future<void> _syncHistory(String userKey) async {
    final api = ApiClient();
    if (_syncingHistory ||
        !api.isConfigured ||
        !api.hasToken ||
        userKey.isEmpty) {
      return;
    }
    _syncingHistory = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final restoredFlag = 'history_restored::$userKey';

      // Los providers cargan sus prefs de forma asíncrona al loguear: se
      // vuelven a leer acá para que la unión parta de lo local de verdad y no de
      // una lista todavía vacía.
      await _favorites.load();
      await _blocked.loadForUser(userKey);

      // Ya restaurado en este equipo y sincronizado hace poco: no hace falta
      // volver a bajar las listas del servidor en cada arranque. Lo que el
      // servidor tiene sale de la copia guardada de `_lastPushedData`, y lo
      // cambiado acá se sube igual por `_pushLists`. Solo se pierde ver antes
      // los cambios hechos desde OTRO celular (llegan en el próximo ciclo).
      final restored = prefs.getBool(restoredFlag) ?? false;
      final lastAt = prefs.getInt(_syncAtKey(userKey));
      final pushedRaw = prefs.getString(_pushedKey(userKey));
      if (restored &&
          lastAt != null &&
          pushedRaw != null &&
          DateTime.now()
                  .difference(DateTime.fromMillisecondsSinceEpoch(lastAt)) <
              _kSyncDataEvery) {
        _lastPushedData
          ..clear()
          ..addAll((jsonDecode(pushedRaw) as Map).cast<String, String>());
        _historyReady = true;
        await _pushLists();
        return;
      }

      // 1) Sesiones.
      var remoteSessions = <PlaySession>[];
      if (!restored) {
        final res = await api.mySyncedSessions(limit: kMaxLocalSessions);
        for (final e in (res['sessions'] as List? ?? const [])) {
          final m = (e as Map).cast<String, dynamic>();
          final ms = (m['endedAtMs'] as num?)?.toInt() ?? 0;
          final data = (m['data'] as Map?)?.cast<String, dynamic>() ?? const {};
          if (ms > 0) remoteSessions.add(PlaySession.fromSyncJson(ms, data));
        }
      }

      // 2) Listas.
      final data = await api.mySyncData();
      List<dynamic> list(String kind) => (data[kind] as List?) ?? const [];
      final remoteStreaks = [
        for (final e in list('streak_history'))
          StreakEntry.fromJson((e as Map).cast<String, dynamic>())
      ];
      // Una lista cambiada en el celu y sin subir NO se une: lo quitado sin
      // conexión volvería. Gana la local y `_pushLists` la sube entera.
      if (!await _favorites.hasLocalChanges()) {
        await _favorites.mergeFrom(list('favorites').map((e) => '$e'));
      }
      if (!await _blocked.hasLocalChanges()) {
        await _blocked.mergeFrom(list('blocked').map((e) => '$e'));
      }
      await _play.restoreHistoryFromBackup(remoteSessions, remoteStreaks);

      // Lo que el servidor YA tiene, para no re-subirlo. Un kind ausente queda
      // sin marcar: significa "nunca se sincronizó" y se sube lo local.
      _lastPushedData.clear();
      for (final kind in const ['streak_history', 'favorites', 'blocked']) {
        if (data.containsKey(kind)) _lastPushedData[kind] = jsonEncode(list(kind));
      }

      // 3) Subir el historial local que el servidor aún no tiene (una sola vez):
      // protege a quien ya venía jugando antes de existir el respaldo.
      await _backfillSessions(userKey, prefs);

      await prefs.setBool(restoredFlag, true);
      await prefs.setInt(
          _syncAtKey(userKey), DateTime.now().millisecondsSinceEpoch);
      _historyReady = true;
      await _savePushed();
      await _pushLists();
    } catch (_) {
      // Sin red / servidor dormido: queda `_historyReady = false` y se reintenta
      // en el próximo flush o en el próximo inicio. Mientras tanto NO se suben
      // listas, para no pisar las del servidor con vacías.
    } finally {
      _syncingHistory = false;
    }
  }

  /// Sube de una vez el historial local. La flag se marca solo si TODO volvió ok.
  Future<void> _backfillSessions(String userKey, SharedPreferences prefs) async {
    final flag = 'sessions_backfill_done::$userKey';
    if (prefs.getBool(flag) ?? false) return;
    final api = ApiClient();
    final all = [
      for (final s in _play.historyForBackup)
        if (s.endedAtMillis > 0)
          {'endedAtMs': s.endedAtMillis, 'data': s.toSyncJson()}
    ];
    for (var i = 0; i < all.length; i += _kSyncBatch) {
      final end = i + _kSyncBatch > all.length ? all.length : i + _kSyncBatch;
      final chunk = all.sublist(i, end);
      final res = await api.syncSessions(chunk);
      final results = (res['results'] as List?) ?? const [];
      final allOk = results.length == chunk.length &&
          results.every((r) => (r as Map)['ok'] == true);
      if (!allOk) return; // reintento en el próximo inicio
    }
    await prefs.setBool(flag, true);
  }

  /// Sube las listas que cambiaron desde la última vez. Solo después del
  /// restore (ver `_historyReady`).
  Future<void> _pushLists() async {
    if (!_historyReady) return;
    final api = ApiClient();
    if (!api.isConfigured || !api.hasToken) return;
    final lists = <String, List<dynamic>>{
      'streak_history': [for (final e in _play.streakHistory) e.toJson()],
      'favorites': _favorites.ids.toList()..sort(),
      'blocked': _blocked.blocked.toList()..sort(),
    };
    Future<void> markSynced(String kind) async {
      if (kind == 'favorites') await _favorites.markSynced();
      if (kind == 'blocked') await _blocked.markSynced();
    }

    for (final entry in lists.entries) {
      final json = jsonEncode(entry.value);
      if (_lastPushedData[entry.key] == json) {
        await markSynced(entry.key);
        continue;
      }
      // Una lista que el servidor nunca tuvo y que acá está vacía no hace falta
      // crearla: "ausente" y "vacía" significan lo mismo hasta que haya algo.
      if (!_lastPushedData.containsKey(entry.key) && entry.value.isEmpty) continue;
      try {
        await api.putSyncData(entry.key, entry.value);
        _lastPushedData[entry.key] = json;
        await markSynced(entry.key);
        await _savePushed();
      } catch (_) {/* se reintenta en el próximo flush */}
    }
  }

  /// Compara el estado de las canchas propias contra el último conocido y, por
  /// cada aprobación/rechazo nuevo, emite la notificación (in-app + push).
  Future<void> _checkCourtDecisions(String email) async {
    try {
      final decisions = await _courts.pollMyCourtDecisions(email);
      for (final d in decisions) {
        _play.addCourtDecision(d.name, d.approved);
      }
    } catch (_) {/* best-effort: no rompe el arranque */}
  }

  /// Avisa los pickups que el creador reprogramó desde la última vez que el
  /// usuario abrió la app (no hay push entre usuarios; ver PickupsProvider).
  /// Corre DESPUÉS de que los pickups estén cargados, si no no hay con qué
  /// comparar.
  Future<void> _checkRescheduledPickups(String email) async {
    try {
      final moved = await _pickups.pollRescheduled(email);
      for (final m in moved) {
        _play.addPickupReschedule(m.title, _pickupDateLabel(m.dateIso));
      }
    } catch (_) {/* best-effort: no rompe el arranque */}
  }

  /// Fecha legible para el aviso ("12/8/2026 · 20:30"). Mismo formato que el
  /// panel del chat del pickup.
  String _pickupDateLabel(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '${dt.day}/${dt.month}/${dt.year} · $h:$m';
    } catch (_) {
      return '';
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connSub?.cancel();
    _noNetTimer?.cancel();
    _retryTimer?.cancel();
    ApiClient.onNetworkError = null;
    ApiClient.onNetworkOk = null;
    _courts.removeListener(_pushCourts);
    _session.removeListener(_onSessionChanged);
  }
}
