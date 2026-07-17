import 'dart:async';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:native_geofence/native_geofence.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/courts.dart';
import 'api/api_client.dart';
import 'courts_provider.dart';
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
class SyncCoordinator {
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
  // Cantidad de canchas con la que se registraron geofences por última vez
  // (para no re-registrar en cada notify del catálogo).
  int _geofencedCount = -1;
  // Si el radar periódico de background está programado (evita re-programarlo
  // en cada sync, lo que reiniciaría su fase).
  bool _radarOn = false;

  void _wire() {
    // Presencia "Jugando" → Notion (best-effort, con reintento vía batch).
    // Además dispara una notificación del sistema en cada arranque/cierre de
    // partido: son eventos siempre visibles (a diferencia de las recompensas,
    // que dependen de desbloquear algo), así que sirven de feedback y de prueba
    // de que el canal de notificaciones funciona.
    _play.onPresenceChanged = (playing, courtId, since) {
      _session.setPresence(playing: playing, courtId: courtId, since: since);
      if (playing) {
        final name = _courtNameById(courtId);
        NotificationsService.instance.show(
          '¡Arrancó tu partido!',
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
          'Partido terminado por batería baja',
          'Cerramos tu partido para proteger tu información. Abrí 1of1 para '
              'registrar el resultado.',
        );
      } else {
        NotificationsService.instance.show(
          'Terminó tu partido',
          'Abrí 1of1 para registrar el resultado.',
        );
      }
      _session.setLastPlayed(courtId: courtId, at: endedAt);
    };

    // Partido demasiado corto (< 13 min): no se registró.
    _play.onMatchDiscarded = (court, seconds) {
      final mins = seconds ~/ 60;
      final dur = mins > 0 ? '$mins min' : '$seconds s';
      NotificationsService.instance.show(
        'Partido no registrado',
        'Duró solo $dur, muy poco para contar como partido. '
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

    // Cada recompensa (logro/título/nivel) también dispara un push del sistema.
    // chatCreated se salta: solo se muestra el banner in-app.
    _play.onReward = (r) {
      if (r.kind == RewardKind.chatCreated) return;
      NotificationsService.instance.show(r.headline, r.name);
    };

    // Notificación de sesión (cronómetro persistente con la app minimizada).
    _play.onDwellNotif = (court, remainingSeconds) =>
        NotificationsService.instance.showDwellCountdown(court, remainingSeconds);
    _play.onPlayingNotif = (court, startedAt) =>
        NotificationsService.instance.showPlaying(court, startedAt);
    _play.onEndingNotif = (court, endsAt) =>
        NotificationsService.instance.showEndingCountdown(court, endsAt);
    _play.onPausedNotif = (court, elapsed) =>
        NotificationsService.instance.showPaused(court, elapsed);
    _play.onClearSessionNotif = () =>
        NotificationsService.instance.cancelSession();
    // Pregunta de partido largo (2h): mostrar/quitar la notif y avisos de sus
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
    _play.onFlush = () async {
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
    };

    // El catálogo de canchas alimenta la detección de cercanía.
    _courts.addListener(_pushCourts);
    _pushCourts();

    // Arranca/detiene el tracking según haya o no sesión activa.
    _session.addListener(_onSessionChanged);
    _onSessionChanged();
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
  Future<void> _syncGeofences() async {
    final loggedIn = _session.profile != null;
    final courts = _courts.courts;
    var always = false;
    try {
      always = await Geolocator.checkPermission() == LocationPermission.always;
    } catch (_) {}
    if (!loggedIn || !_play.backgroundEnabled || courts.isEmpty || !always) {
      if (_geofencedCount != 0) {
        _geofencedCount = 0;
        GeofenceService.instance.clear();
      }
      if (_radarOn) {
        _radarOn = false;
        unawaited(cancelRadarWatch());
      }
      return;
    }
    if (!_radarOn) {
      _radarOn = true;
      unawaited(scheduleRadarWatch());
    }
    if (_geofencedCount == courts.length) return; // sin cambios relevantes
    _geofencedCount = courts.length;
    // Cache global de canchas para que el radar (isolate sin memoria
    // compartida) pueda medir cercanía.
    unawaited(_writeCourtsGeoCache(courts));
    GeofenceService.instance.syncCourts(courts);
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
    final p = _session.profile;
    if (p == null) {
      // Cierre de sesión: frenamos el tracking y limpiamos el estado en memoria
      // (puntos, logros, historial) para que NO se filtren a la próxima cuenta.
      if (_trackingStarted) {
        _play.resetForLogout();
        _favorites.clearForLogout();
        _pickups.clearForLogout();
        _blocked.clearForLogout();
        _trackingStarted = false;
        _geofencedCount = -1;
        GeofenceService.instance.clear();
        _radarOn = false;
        unawaited(cancelRadarWatch());
      }
      return;
    }
    if (_trackingStarted) return;
    _trackingStarted = true;
    // Clave por usuario: aísla los datos locales de cada cuenta en el dispositivo.
    final userKey = (_session.email ?? p.userEmail).trim().toLowerCase();
    _favorites.setUser(userKey);
    // Con sesión (JWT) recién disponible: (re)cargar el catálogo. El load()
    // del arranque pudo haber corrido sin token (401/lista vacía).
    if (_courts.courts.isEmpty) unawaited(_courts.load());
    // Cargar los pickups/invitaciones del usuario (para el badge de la campana y
    // las notificaciones del perfil, sin depender de abrir la pestaña Crew).
    unawaited(_pickups.loadForUser(userKey));
    // Lista local de usuarios bloqueados de esta cuenta.
    unawaited(_blocked.loadForUser(userKey));
    // Sembrar desde Notion para no perder progreso tras reinstalar.
    _play.startTracking(
      userKey: userKey,
      seedPoints: p.points,
      seedPlays: p.games,
      seedStreak: p.streak,
      seedBadges: p.unlockedBadges,
      seedTotalsJson: p.playTimeByCourt,
    );
    unawaited(_syncGeofences());
    // Avisar decisiones de moderación sobre las canchas que propuso el usuario
    // (se aprobaron/rechazaron desde la última vez que abrió la app).
    unawaited(_checkCourtDecisions(userKey));
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

  void dispose() {
    _courts.removeListener(_pushCourts);
    _session.removeListener(_onSessionChanged);
  }
}
