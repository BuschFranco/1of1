import 'package:native_geofence/native_geofence.dart';
import 'courts_provider.dart';
import 'geofence_service.dart';
import 'notifications_service.dart';
import 'play_session_service.dart';
import 'session.dart';

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
  })  : _session = session,
        _play = play,
        _courts = courts {
    _wire();
  }

  final Session _session;
  final PlaySessionService _play;
  final CourtsProvider _courts;

  // Evita arrancar el tracking más de una vez por sesión (Session notifica en
  // cada cambio de perfil, no solo al loguear).
  bool _trackingStarted = false;
  // Cantidad de canchas con la que se registraron geofences por última vez
  // (para no re-registrar en cada notify del catálogo).
  int _geofencedCount = -1;

  void _wire() {
    // Presencia "Jugando" → Notion (best-effort, con reintento vía batch).
    _play.onPresenceChanged = (playing, courtId, since) {
      _session.setPresence(playing: playing, courtId: courtId, since: since);
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
    _play.onBackgroundChanged = (_) => _syncGeofences();

    // Cada recompensa (logro/título/nivel) también dispara un push del sistema.
    _play.onReward = (r) {
      NotificationsService.instance.show(r.headline, r.name);
    };

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
        playSeconds: _play.totalSeconds,
        playTimeByCourt: _play.totalsJson,
      );
      await _session.flush();
    };

    // El catálogo de canchas alimenta la detección de cercanía.
    _courts.addListener(_pushCourts);
    _pushCourts();

    // Arranca/detiene el tracking según haya o no sesión activa.
    _session.addListener(_onSessionChanged);
    _onSessionChanged();
  }

  void _pushCourts() {
    _play.setCourts(_courts.courts);
    _syncGeofences();
  }

  /// Registra (o quita) las geofences de las canchas según haya sesión, esté
  /// habilitada la detección en background y haya canchas cargadas. Evita
  /// re-registrar si la cantidad de canchas no cambió.
  void _syncGeofences() {
    final loggedIn = _session.profile != null;
    final courts = _courts.courts;
    if (!loggedIn || !_play.backgroundEnabled || courts.isEmpty) {
      if (_geofencedCount != 0) {
        _geofencedCount = 0;
        GeofenceService.instance.clear();
      }
      return;
    }
    if (_geofencedCount == courts.length) return; // sin cambios relevantes
    _geofencedCount = courts.length;
    GeofenceService.instance.syncCourts(courts);
  }

  void _onSessionChanged() {
    final p = _session.profile;
    if (p == null) {
      // Cierre de sesión: frenamos el tracking y reseteamos para el próximo login.
      if (_trackingStarted) {
        _play.stopTracking();
        _trackingStarted = false;
        _geofencedCount = -1;
        GeofenceService.instance.clear();
      }
      return;
    }
    if (_trackingStarted) return;
    _trackingStarted = true;
    // Sembrar desde Notion para no perder progreso tras reinstalar.
    _play.startTracking(
      seedPoints: p.points,
      seedPlays: p.games,
      seedStreak: p.streak,
      seedBadges: p.unlockedBadges,
      seedTotalsJson: p.playTimeByCourt,
    );
    _syncGeofences();
  }

  void dispose() {
    _courts.removeListener(_pushCourts);
    _session.removeListener(_onSessionChanged);
  }
}
