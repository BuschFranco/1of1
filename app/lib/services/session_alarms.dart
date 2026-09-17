import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api/api_client.dart';
import 'api/api_config.dart';
import 'notifications_service.dart';

/// Arranque/cierre AUTOMÁTICO del partido en segundo plano con alarmas exactas
/// del sistema (android_alarm_manager_plus). Android dispara los callbacks en un
/// ISOLATE DE BACKGROUND a la hora exacta aunque la app esté minimizada o
/// cerrada. El callback verifica ubicación, escribe el estado persistido (las
/// mismas claves que usa PlaySessionService), actualiza la notificación y la
/// presencia en Notion, y le avisa al isolate principal (si está vivo) para que
/// reconcilie. El isolate principal también reconcilia al volver al frente.

/// IDs de las alarmas (fijos: solo hay una permanencia / una salida a la vez).
const int kAlarmStartId = 100011;
const int kAlarmEndId = 100012;
// Alarma PERIÓDICA que vigila la batería mientras hay un partido en curso:
// despierta aunque la app esté cerrada y cierra el partido si la carga quedó
// muy baja (red de seguridad además del polling con la app viva).
const int kAlarmBatteryId = 100013;
// Aviso de "tu partido se cierra pronto": dispara cuando quedan
// [_kEndNotifLead] de la gracia de salida, aunque la app esté cerrada.
const int kAlarmWarnId = 100014;
// RADAR periódico de respaldo: cada [_kRadarEvery] re-muestrea el GPS en un
// isolate de background y avanza la detección (sembrar permanencia al llegar,
// arrancar la gracia de salida al irse) aunque Samsung haya matado el proceso
// y el foreground service. Es la red de seguridad de las geofences.
const int kAlarmRadarId = 100015;
// Pregunta de partido largo: a las 3h de juego neto pausa el partido y
// pregunta "¿Seguís jugando?" aunque la app esté cerrada.
const int kAlarmConfirmId = 100016;
// Timeout de la pregunta: sin respuesta en [_kConfirmTimeout], descarta el
// partido por completo (sin pendiente, sin puntos, sin historial).
const int kAlarmConfirmTimeoutId = 100017;
// Tope duro de la hora extra tras el "SÍ": cierra y GUARDA el partido.
const int kAlarmHardEndId = 100018;
// WATCHDOG del radar: alarma PERIÓDICA (a propósito, no cadena) que revive
// [scheduleRadarWatch] si dejó de tickear. Ver el comentario de
// [scheduleWatchdog] para el porqué.
const int kAlarmWatchdogId = 100019;
// Aviso de reenganche: alarma PERIÓDICA inexacta que chequea si pasaron varios
// días sin una sesión de juego. Ver [scheduleNudge].
const int kAlarmNudgeId = 100020;

/// Puerto para avisarle al isolate principal que reconcilie desde prefs.
const String kPlayPortName = 'oneofone_play_port';

/// userKey activo, para que el callback arme las claves namespaced igual que
/// PlaySessionService (`base::$userKey`).
const String kBgUserKey = 'play_bg_userkey';

/// DEV: ubicación simulada ("lat,lng") del modo prueba. La escribe setMock para
/// que los callbacks de alarma (isolate aparte, sin memoria compartida) también
/// la respeten y el arranque/cierre automático sea testeable sin ir a la cancha.
const String kMockPosKey = 'play_mock_pos';

/// Cache global de canchas (id/nombre/lat/lng en JSON) para que el radar pueda
/// medir cercanía sin memoria compartida. Lo escribe SyncCoordinator.
const String kCourtsGeoCacheKey = 'courts_geo_cache';

/// Diagnóstico: momento (epoch ms) del último fix de GPS obtenido en
/// background (radar o stream con la app minimizada). Visible en los controles
/// DEV del mapa para verificar en la calle que el background funciona.
const String kLastBgFixKey = 'last_bg_fix_millis';

/// Si el SO nos deja programar alarmas EXACTAS. Lo escribe el isolate principal
/// (`checkPermissions`, que sí tiene el canal con la Activity) para que los
/// isolates de background puedan decidir sin poder consultarlo ellos mismos.
/// Clave GLOBAL, mismo criterio que `session_jwt`. Ver [_oneShotAt].
const String kCanScheduleExactKey = 'can_schedule_exact';

/// Momento (epoch ms) en que [_radarTick] se EJECUTÓ por última vez, haya
/// conseguido fix o no. A diferencia de [kLastBgFixKey] (que solo se actualiza
/// con fix exitoso, y por eso queda viejo con solo estar en interiores sin
/// señal), esto mide si la CADENA sigue viva, que es lo único que le importa
/// al watchdog. Interno: no se muestra en ningún diagnóstico de usuario.
const String kLastRadarTickKey = 'last_radar_tick_millis';

// Claves fijas (no namespaced) con el "objetivo" de cada alarma.
const String _kAlarmStart = 'play_alarm_start';
const String _kAlarmEnd = 'play_alarm_end';
const String _kAlarmWarn = 'play_alarm_warn';
const String _kAlarmHardEnd = 'play_alarm_hardend';

// Claves base de PlaySessionService (deben coincidir EXACTO). Públicas porque
// Session también las lee al arrancar: para decidir si, sin red, entra con el
// perfil cacheado en vez de mandar al login (hay un partido sin terminar).
const String kActiveSessionBase = 'play_active_session';
const String kPendingResultBase = 'play_pending_result';
// Snooze de "No juego": {courtId, untilMillis}. El radar no debe volver a
// sembrar la permanencia en la cancha silenciada mientras siga vigente.
const String _kDwellSnoozeBase = 'play_dwell_snooze';

// Constantes espejo de PlaySessionService (mantener en sync).
const double _kRadiusMeters = 110;
const int _kMinMatchSeconds = 13 * 60;
const int _kBatteryEndPercent = 5;
const Duration _kBatteryWatchEvery = Duration(minutes: 15);
// Gemela de PlaySessionService.endNotifLeadTime: cuánto antes del cierre avisamos.
const Duration _kEndNotifLead = Duration(minutes: 3);
// Gemelas de PlaySessionService.dwellThreshold / exitGrace.
const Duration _kDwellThreshold = Duration(minutes: 6);
const Duration _kExitGrace = Duration(minutes: 6);
// Cadencia del radar de respaldo (peor caso de detección sin geofence/FGS).
const Duration _kRadarEvery = Duration(minutes: 15);
// Cada cuánto despierta el watchdog a chequear que el radar siga tickeando.
// Más espaciado que el radar a propósito: es una red de seguridad de la red de
// seguridad, no necesita la cadencia de [_kRadarEvery].
const Duration _kWatchdogEvery = Duration(minutes: 30);
// Si el radar no tickeó en más de esto, se lo considera muerto y se re-arma.
// 2x [_kRadarEvery] con margen: un tick tardío por Doze no debe disparar un
// re-arme innecesario.
const Duration _kRadarStaleAfter = Duration(minutes: 35);
// GEMELAS de PlaySessionService.pointsTimeCap / confirmTimeout / dwellSnooze:
// umbral de la pregunta de partido largo, ventana de respuesta, y snooze del
// detector tras descartar (el celu probablemente sigue en el radio).
const Duration _kConfirmAfter = Duration(hours: 3);
const Duration _kConfirmTimeout = Duration(minutes: 20);
const Duration _kDwellSnooze = Duration(hours: 2, minutes: 30);

String bgNsKey(String base, String uk) => uk.isEmpty ? base : '$base::$uk';

bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

// ── Gate de sesión en background ────────────────────────────────────────────
//
// Sin sesión iniciada NO se detecta ni se notifica nada: el usuario tocaría la
// notificación, la app lo mandaría al login y quedaría sin saber dónde se
// registró su partido. El isolate no comparte memoria con el principal, así que
// la única señal de sesión que puede ver son las claves que Session escribe en
// prefs (y borra en el logout).
//
// Ojo: el gate NO mira la red a propósito. Con sesión guardada pero sin
// internet la detección debe seguir funcionando — el registro es
// offline-resiliente (se encola en pending_matches y se sube al volver).

/// JWT usable desde background: presente y no vencido. null si falta o venció.
/// Única implementación de la decodificación/exp (la usan el gate de sesión y
/// [_setNotionPresence]): si cambia el criterio, cambia en un solo lugar.
String? validBgJwt(SharedPreferences prefs) {
  try {
    final jwt = prefs.getString(ApiConfig.jwtPrefsKey);
    if (jwt == null || jwt.isEmpty) return null;
    final exp = ApiClient.decodePayload(jwt)['exp'];
    final expired = exp is num &&
        DateTime.now().isAfter(
            DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000));
    return expired ? null : jwt;
  } catch (_) {
    return null;
  }
}

/// ¿Hay sesión iniciada, visto desde el isolate de background? Lee las tres
/// claves que borra `Session.logout()` (email + perfil cacheado + JWT).
///
/// [requireFreshToken] en false para los caminos que solo CIERRAN un partido ya
/// en curso: si el token vence a mitad de partido, igual hay que poder cerrarlo
/// (con el gate estricto quedaría abierto para siempre, con su notificación
/// pegada). Quien expulsa al usuario es el 401 del próximo GET /me, no esto.
Future<bool> hasBgSession(SharedPreferences prefs,
    {bool requireFreshToken = true}) async {
  try {
    // El isolate arranca con una copia vieja de prefs: sin reload podría ver
    // una sesión que ya se cerró (o no ver una que se acaba de abrir).
    await prefs.reload();
    final email = prefs.getString('session_email') ?? '';
    final profile = prefs.getString('session_profile') ?? '';
    if (email.isEmpty || profile.isEmpty) return false;
    // Build sin API_BASE_URL (modo degradado): nunca hay JWT y la app funciona
    // local, así que no lo exigimos.
    if (!ApiConfig.isConfigured) return true;
    if (!requireFreshToken) return true;
    return validBgJwt(prefs) != null;
  } catch (_) {
    // Ante la duda no detectamos: mejor perder una detección que notificar un
    // partido que no tiene dónde registrarse.
    return false;
  }
}

/// Programa una alarma exacta con fallback: si el SO rechaza la exacta (p. ej.
/// el usuario revocó "Alarmas y recordatorios" en Android 14+), cae a inexacta
/// — dispara con demora de minutos, pero dispara (mejor que nada).
///
/// **La decisión se toma ANTES de programar, leyendo [kCanScheduleExactKey].**
/// No alcanza con un try/catch: cuando `canScheduleExactAlarms()` es false el
/// plugin solo LOGUEA del lado Java y devuelve éxito por el method channel, así
/// que no hay excepción que atrapar y la alarma queda sin registrar en silencio.
/// Ese fue uno de los dos caminos por los que la detección en background se
/// moría sin dejar rastro.
Future<void> _oneShotAt(DateTime at, int id, Function callback) async {
  // El isolate de background no puede consultar el permiso: el canal
  // `oneofone/alarm_perm` se registra en la Activity. Por eso el isolate
  // principal deja el resultado acá (ver `AppPermissions.checkPermissions`).
  // Ausente ⇒ asumimos que sí, que es el caso de la enorme mayoría de devices.
  var exact = true;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    exact = prefs.getBool(kCanScheduleExactKey) ?? true;
  } catch (_) {/* ante la duda, exacta */}
  try {
    await AndroidAlarmManager.oneShotAt(
      at,
      id,
      callback,
      exact: exact,
      wakeup: true,
      // allowWhileIdle solo tiene sentido con exacta: en inexacta el SO ya
      // agrupa el disparo con las ventanas de mantenimiento de Doze.
      allowWhileIdle: exact,
      rescheduleOnReboot: true,
    );
  } catch (_) {
    try {
      await AndroidAlarmManager.oneShotAt(
        at,
        id,
        callback,
        wakeup: true,
        rescheduleOnReboot: true,
      );
    } catch (_) {/* sin alarma: quedan los caminos con la app viva */}
  }
}

// ── Programar / cancelar ────────────────────────────────────────────────────

/// Programa el arranque automático del partido para [at] en la cancha dada.
Future<void> scheduleStartAlarm({
  required String userKey,
  required String courtId,
  required String courtName,
  required double lat,
  required double lng,
  required DateTime at,
}) async {
  if (!_isAndroid) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    _kAlarmStart,
    jsonEncode({
      'userKey': userKey,
      'courtId': courtId,
      'courtName': courtName,
      'lat': lat,
      'lng': lng,
      'atMillis': at.millisecondsSinceEpoch,
    }),
  );
  await AndroidAlarmManager.cancel(kAlarmStartId);
  await _oneShotAt(at, kAlarmStartId, alarmStartCallback);
}

Future<void> cancelStartAlarm() async {
  if (!_isAndroid) return;
  await AndroidAlarmManager.cancel(kAlarmStartId);
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_kAlarmStart);
}

/// Programa el cierre automático del partido para [at] (gracia de salida).
Future<void> scheduleEndAlarm({
  required String userKey,
  required String courtId,
  required String courtName,
  required double lat,
  required double lng,
  required int startMillis,
  required DateTime at,
}) async {
  if (!_isAndroid) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    _kAlarmEnd,
    jsonEncode({
      'userKey': userKey,
      'courtId': courtId,
      'courtName': courtName,
      'lat': lat,
      'lng': lng,
      'startMillis': startMillis,
      'atMillis': at.millisecondsSinceEpoch,
    }),
  );
  await AndroidAlarmManager.cancel(kAlarmEndId);
  await _oneShotAt(at, kAlarmEndId, alarmEndCallback);

  // Aviso "se cierra pronto": alarma a [_kEndNotifLead] del cierre, para que la
  // notificación llegue aunque la app esté congelada/cerrada (el camino con la
  // app viva lo cubre el ticker, pero acá no dependemos de él).
  final warnAt = at.subtract(_kEndNotifLead);
  await AndroidAlarmManager.cancel(kAlarmWarnId);
  if (warnAt.isAfter(DateTime.now())) {
    await prefs.setString(
      _kAlarmWarn,
      jsonEncode({
        'userKey': userKey,
        'courtName': courtName,
        'lat': lat,
        'lng': lng,
      }),
    );
    await _oneShotAt(warnAt, kAlarmWarnId, alarmWarnCallback);
  }
}

Future<void> cancelEndAlarm() async {
  if (!_isAndroid) return;
  await AndroidAlarmManager.cancel(kAlarmEndId);
  await AndroidAlarmManager.cancel(kAlarmWarnId);
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_kAlarmEnd);
  await prefs.remove(_kAlarmWarn);
}

/// Cancela el cierre automático pendiente porque VOLVISTE a la cancha durante la
/// gracia. Se llama desde el callback de geofence ENTER cuando la app está
/// muerta: ahí el isolate principal no está vivo para cancelar la alarma, así
/// que lo hacemos acá y limpiamos el estado de salida persistido (endsAtMillis)
/// para que la sesión activa vuelva a "jugando".
Future<void> cancelEndAlarmOnReenter() async {
  if (!_isAndroid) return;
  await AndroidAlarmManager.cancel(kAlarmEndId);
  await AndroidAlarmManager.cancel(kAlarmWarnId);
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  await prefs.remove(_kAlarmEnd);
  await prefs.remove(_kAlarmWarn);
  final uk = prefs.getString(kBgUserKey) ?? '';
  await _clearExitStateInActive(prefs, uk);
}

/// Borra el `endsAtMillis` de la sesión activa persistida (la gracia de salida
/// quedó sin efecto). Sin esto, un _restore posterior vería un fin-de-gracia
/// "vencido" y cerraría un partido que en realidad sigue en curso.
Future<void> _clearExitStateInActive(SharedPreferences prefs, String uk) async {
  final activeKey = bgNsKey(kActiveSessionBase, uk);
  final raw = prefs.getString(activeKey);
  if (raw == null) return;
  try {
    final a = jsonDecode(raw) as Map<String, dynamic>;
    if (a['endsAtMillis'] != null) {
      a['endsAtMillis'] = null;
      await prefs.setString(activeKey, jsonEncode(a));
    }
  } catch (_) {/* estado corrupto: ignorar */}
}

/// Arranca la vigilancia periódica de batería mientras dure el partido.
Future<void> scheduleBatteryWatch() async {
  if (!_isAndroid) return;
  await AndroidAlarmManager.cancel(kAlarmBatteryId);
  await AndroidAlarmManager.periodic(
    _kBatteryWatchEvery,
    kAlarmBatteryId,
    alarmBatteryCallback,
    wakeup: true,
    allowWhileIdle: true,
    rescheduleOnReboot: false,
  );
}

Future<void> cancelBatteryWatch() async {
  if (!_isAndroid) return;
  await AndroidAlarmManager.cancel(kAlarmBatteryId);
}

/// Arranca el radar de respaldo. Lo programa SyncCoordinator cuando hay sesión +
/// background habilitado + permiso "Siempre".
///
/// **Es una alarma PERIÓDICA, y tiene que seguir siéndolo.** Entre ago-2026 y
/// este arreglo fue una cadena de one-shots exactas, buscando atravesar Doze con
/// `exact + allowWhileIdle`. Ganaba precisión y perdía lo único que importa acá:
/// que el radar siga existiendo. La cadena se cortaba de forma PERMANENTE por
/// dos caminos, y el usuario lo reportó como "con la app cerrada no detecta
/// nada":
///
///  1. El plugin invoca el callback SIN await (`closure()` a secas), así que el
///     `CountDownLatch` nativo se libera apenas el handler retorna y el
///     JobIntentService suelta su wakelock mientras el resto del `Future` sigue
///     pendiente. Todo lo caro del tick (prefs, `hasBgSession`, y sobre todo el
///     fix de GPS) corre ya sin wakelock: si el CPU se duerme o el OEM mata el
///     proceso antes del `finally`, el eslabón siguiente NUNCA se programa.
///  2. Cuando `canScheduleExactAlarms()` es false, el plugin solo LOGUEA y
///     sigue: el method channel devuelve éxito, así que el `catch` de
///     [_oneShotAt] jamás corre y la alarma simplemente no queda registrada.
///
/// Con `periodic` el schedule lo mantiene Android, no nuestro código Dart: un
/// tick truncado cuesta UN tick, no el radar entero. Y al ser inexacta no pasa
/// por el gate de alarmas exactas (`setInexactRepeating`), así que el punto 2
/// tampoco aplica. La precisión que se pierde no hace falta: esto es una red de
/// seguridad cada 15 min, no un evento con deadline (para esos siguen las
/// one-shots exactas: arranque, cierre, aviso previo, partido largo).
Future<void> scheduleRadarWatch() async {
  if (!_isAndroid) return;
  await AndroidAlarmManager.cancel(kAlarmRadarId);
  await AndroidAlarmManager.periodic(
    _kRadarEvery,
    kAlarmRadarId,
    alarmRadarCallback,
    wakeup: true,
    allowWhileIdle: true,
    rescheduleOnReboot: true,
  );
}

Future<void> cancelRadarWatch() async {
  if (!_isAndroid) return;
  await AndroidAlarmManager.cancel(kAlarmRadarId);
}

/// Arranca el watchdog del radar. Lo programa SyncCoordinator junto con
/// [scheduleRadarWatch] (mismas condiciones: sesión + background + permiso
/// "Siempre").
///
/// Chequea que el radar siga tickeando y lo re-programa si no. Es una alarma
/// PERIÓDICA de las inexactas: no necesita precisión, solo llegar eventualmente.
///
/// Segunda red, no la principal: desde que el radar volvió a ser `periodic`
/// (ver [scheduleRadarWatch]) Android mantiene ese schedule solo. Lo que este
/// watchdog cubre es que la alarma del radar **nunca haya quedado registrada**
/// — que es un fallo mudo, porque programarla no informa si funcionó.
Future<void> scheduleWatchdog() async {
  if (!_isAndroid) return;
  await AndroidAlarmManager.cancel(kAlarmWatchdogId);
  await AndroidAlarmManager.periodic(
    _kWatchdogEvery,
    kAlarmWatchdogId,
    alarmWatchdogCallback,
    wakeup: true,
    allowWhileIdle: true,
    rescheduleOnReboot: true,
  );
}

Future<void> cancelWatchdog() async {
  if (!_isAndroid) return;
  await AndroidAlarmManager.cancel(kAlarmWatchdogId);
}

// ── Ahorro de energía ──────────────────────────────────────────────────────
// Con el ahorro activo el SO estrangula ubicación, geofences y foreground
// service, así que la detección se degrada EN SILENCIO: el usuario cree que su
// partido se está midiendo y no pasa nada. Esto avisa.
//
// Se lee con `battery_plus` (→ PowerManager.isPowerSaveMode) y NO con el canal
// propio de la app: `oneofone/alarm_perm` se registra en la Activity, así que no
// existe en los isolates de background. battery_plus es plugin de pub y sí está.

/// Cada cuánto, como mucho, se repite el aviso mientras el ahorro siga activo.
/// Sin esto el radar avisaría cada 15 minutos.
const Duration kPowerSaveNotifyCooldown = Duration(hours: 6);

/// Cuándo se avisó por última vez. Clave GLOBAL: el isolate de background no
/// conoce el userKey (mismo criterio que `session_jwt` y `last_bg_fix_millis`).
const String kPowerSaveNotifiedKey = 'power_save_notified_at';

/// True si el ahorro de energía está activo. False ante cualquier error: nunca
/// alarmar por una lectura que falló.
Future<bool> isPowerSaveOn() async {
  try {
    return await Battery().isInBatterySaveMode;
  } catch (_) {
    return false;
  }
}

/// Avisa que el ahorro de energía puede estar frenando la detección, como mucho
/// una vez cada [kPowerSaveNotifyCooldown].
///
/// Si el ahorro está apagado **borra la marca**, para que un episodio nuevo
/// vuelva a avisar en vez de quedar silenciado por el aviso de hace 6 h.
///
/// [playing] cambia el texto: con un partido en curso hay algo concreto que
/// perder, y conviene decirlo.
Future<void> maybeNotifyPowerSave(
  SharedPreferences prefs, {
  required bool playing,
}) async {
  try {
    if (!await isPowerSaveOn()) {
      await prefs.remove(kPowerSaveNotifiedKey);
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = prefs.getInt(kPowerSaveNotifiedKey) ?? 0;
    if (now - last < kPowerSaveNotifyCooldown.inMilliseconds) return;
    await prefs.setInt(kPowerSaveNotifiedKey, now);
    // El texto dice qué hacer, no solo qué pasa: apagarlo y que funcione solo,
    // o registrar el partido a mano desde el mapa.
    await NotificationsService.instance.showPowerSave(
      playing ? 'Tu sesión puede no contarse' : 'Ahorro de energía activo',
      playing
          ? 'Puede frenar el cronómetro. Apagalo y sigue sola; si no, cortá la sesión a mano con DETENER.'
          : 'Puede impedir que detectemos tu sesión de juego. Apagalo y arranca sola; si no, tocá EMPEZAR YA en la cancha.',
    );
  } catch (_) {/* el aviso es best-effort: nunca romper la detección */}
}

/// Programa la pregunta de partido largo para [at] (3h de juego NETO). La
/// programa PlaySessionService al arrancar el partido y la REPROGRAMA al
/// reanudar una pausa manual (la pausa corre el umbral). También la programa
/// alarmStartCallback cuando el partido arranca en background.
Future<void> scheduleConfirmAlarm({required DateTime at}) async {
  if (!_isAndroid) return;
  await AndroidAlarmManager.cancel(kAlarmConfirmId);
  await _oneShotAt(at, kAlarmConfirmId, alarmConfirmCallback);
}

Future<void> cancelConfirmAlarm() async {
  if (!_isAndroid) return;
  await AndroidAlarmManager.cancel(kAlarmConfirmId);
}

/// Programa el descarte por falta de respuesta para [at] (+20 min de la
/// pregunta). La programan tanto _beginConfirm (foreground) como el callback
/// de la pregunta (background); el cancel previo la hace idempotente.
Future<void> scheduleConfirmTimeoutAlarm({required DateTime at}) async {
  if (!_isAndroid) return;
  await AndroidAlarmManager.cancel(kAlarmConfirmTimeoutId);
  await _oneShotAt(at, kAlarmConfirmTimeoutId, alarmConfirmTimeoutCallback);
}

Future<void> cancelConfirmTimeoutAlarm() async {
  if (!_isAndroid) return;
  await AndroidAlarmManager.cancel(kAlarmConfirmTimeoutId);
}

/// Programa el cierre duro para [at] (tope de la hora extra tras el "SÍ"):
/// cierra y GUARDA el partido aunque la app esté cerrada, con [at] como fin
/// para no inflar la duración si la alarma llega tarde.
Future<void> scheduleHardEndAlarm({required DateTime at}) async {
  if (!_isAndroid) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
      _kAlarmHardEnd, jsonEncode({'atMillis': at.millisecondsSinceEpoch}));
  await AndroidAlarmManager.cancel(kAlarmHardEndId);
  await _oneShotAt(at, kAlarmHardEndId, alarmHardEndCallback);
}

Future<void> cancelHardEndAlarm() async {
  if (!_isAndroid) return;
  await AndroidAlarmManager.cancel(kAlarmHardEndId);
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_kAlarmHardEnd);
}

/// Deja el background COMPLETAMENTE apagado. Se llama al cerrar sesión: sin
/// esto, una permanencia sembrada antes del logout hace que
/// [alarmStartCallback] arranque un partido y notifique "¡Arrancó tu partido!"
/// con la sesión ya cerrada (el gate de cada callback lo frena, pero igual
/// conviene no dejar alarmas colgadas despertando el equipo al vacío).
///
/// Vive acá porque las claves de target (`play_alarm_*`) son privadas de este
/// archivo: SyncCoordinator no puede limpiarlas por su cuenta.
Future<void> cancelAllPlayAlarms() async {
  if (!_isAndroid) return;
  // cancelEndAlarm ya cancela el aviso previo (warn) junto con el cierre.
  await cancelStartAlarm();
  await cancelEndAlarm();
  await cancelBatteryWatch();
  await cancelConfirmAlarm();
  await cancelConfirmTimeoutAlarm();
  await cancelHardEndAlarm();
  await cancelRadarWatch();
  await cancelWatchdog();
  await cancelNudge();
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kBgUserKey);
  } catch (_) {/* best-effort: el gate de sesión ya cubre el caso */}
}

/// Target de la alarma de arranque pendiente (permanencia sembrada por el radar
/// o por _beginDwell), para que el isolate principal la adopte al volver al
/// frente en vez de reiniciar la cuenta regresiva.
Future<Map<String, dynamic>?> readPendingStartTarget() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_kAlarmStart);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

// ── Callbacks (isolate de background) ────────────────────────────────────────

/// Arranca el partido si al cumplirse la permanencia seguís en la cancha.
@pragma('vm:entry-point')
Future<void> alarmStartCallback() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final raw = prefs.getString(_kAlarmStart);
  if (raw == null) return;
  await prefs.remove(_kAlarmStart);
  // Es el que notifica "¡Arrancó tu partido!": sin sesión no arrancamos nada
  // (el target ya quedó consumido arriba, así que no vuelve a dispararse).
  if (!await hasBgSession(prefs)) return;

  Map<String, dynamic> t;
  try {
    t = jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return;
  }
  final uk = (t['userKey'] ?? '') as String;
  final courtId = (t['courtId'] ?? '') as String;
  final courtName = (t['courtName'] ?? '') as String;
  final lat = (t['lat'] as num?)?.toDouble() ?? 0;
  final lng = (t['lng'] as num?)?.toDouble() ?? 0;
  final atMillis =
      (t['atMillis'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;

  // ¿Seguís en la cancha? Best-effort: si no hay fix, arrancamos igual.
  if (await _leftArea(lat, lng, defaultWhenNoFix: false)) return;

  final startIso = DateTime.fromMillisecondsSinceEpoch(atMillis).toIso8601String();
  // OJO: a propósito SIN 'lastSeenMillis'. Su ausencia le indica a _restore()
  // que el partido lo arrancó esta alarma con el proceso muerto (no hay
  // latidos) y que sigue EN CURSO: debe resumirlo, no cerrarlo por "gap".
  await prefs.setString(
    bgNsKey(kActiveSessionBase, uk),
    jsonEncode({
      'courtId': courtId,
      'courtName': courtName,
      'startMillis': atMillis,
    }),
  );

  await NotificationsService.instance.init();
  await NotificationsService.instance
      .showPlaying(courtName, DateTime.fromMillisecondsSinceEpoch(atMillis));
  // Aviso VISIBLE (la notif de sesión de arriba es silenciosa): paridad con el
  // camino en-proceso, donde onPresenceChanged postea este mismo mensaje.
  await NotificationsService.instance.show(
    '¡Arrancó tu sesión de juego!',
    courtName.isEmpty
        ? 'Estamos contando tu tiempo en la cancha.'
        : 'Contando tu tiempo en $courtName.',
  );

  await _setNotionPresence(prefs,
      playing: true, courtId: courtId, sinceIso: startIso);

  // Arrancó un partido en background → vigilamos la batería y programamos la
  // pregunta de partido largo (arranque por alarma = sin pausas previas, el
  // umbral de juego neto coincide con el de reloj).
  await scheduleBatteryWatch();
  await scheduleConfirmAlarm(
      at: DateTime.fromMillisecondsSinceEpoch(atMillis).add(_kConfirmAfter));

  _pingMain();
}

/// Cierra el partido si al cumplirse la gracia seguís fuera del radio.
@pragma('vm:entry-point')
Future<void> alarmEndCallback() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final raw = prefs.getString(_kAlarmEnd);
  if (raw == null) return;
  await prefs.remove(_kAlarmEnd);
  // Token laxo: este camino CIERRA un partido en curso. Si el JWT venció a
  // mitad de partido igual hay que poder cerrarlo (si no, queda abierto para
  // siempre con su notificación pegada).
  if (!await hasBgSession(prefs, requireFreshToken: false)) return;

  Map<String, dynamic> t;
  try {
    t = jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return;
  }
  final uk = (t['userKey'] ?? '') as String;
  // La cancha/duración las toma _closeActiveToPending desde la sesión activa.
  final lat = (t['lat'] as num?)?.toDouble() ?? 0;
  final lng = (t['lng'] as num?)?.toDouble() ?? 0;
  // Momento en que el partido DEBE cerrarse (fin de gracia): tope de la duración.
  final atMillis = (t['atMillis'] as num?)?.toInt();

  final activeKey = bgNsKey(kActiveSessionBase, uk);
  if (prefs.getString(activeKey) == null) return; // ya no hay partido en curso

  // ¿Volviste a la cancha? Si hay fix y estás dentro, NO cerramos. Sin fix,
  // CERRAMOS (defaultWhenNoFix: true): ya detectamos la salida hace [exitGrace].
  if (!await _leftArea(lat, lng, defaultWhenNoFix: true)) {
    // La gracia queda sin efecto: limpiamos su rastro persistido para que un
    // restore posterior no cierre con un fin-de-gracia vencido.
    await _clearExitStateInActive(prefs, uk);
    _pingMain();
    return;
  }

  await _closeActiveToPending(prefs, uk, lowBattery: false, endsAtMillis: atMillis);
  _pingMain();
}

/// Aviso "tu partido se cierra pronto": dispara a [_kEndNotifLead] del cierre.
/// Solo notifica si el partido sigue en curso, la gracia sigue vigente (no se
/// canceló) y seguís fuera del radio. Corre aunque la app esté cerrada.
@pragma('vm:entry-point')
Future<void> alarmWarnCallback() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final raw = prefs.getString(_kAlarmWarn);
  if (raw == null) return;
  await prefs.remove(_kAlarmWarn);
  // Token laxo: solo avisa sobre un partido ya en curso (ver alarmEndCallback).
  if (!await hasBgSession(prefs, requireFreshToken: false)) return;
  // Gracia cancelada (volviste y el isolate principal o el geofence limpiaron
  // la alarma de cierre): no hay nada que avisar.
  if (prefs.getString(_kAlarmEnd) == null) return;

  Map<String, dynamic> t;
  try {
    t = jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return;
  }
  final uk = (t['userKey'] ?? '') as String;
  final courtName = (t['courtName'] ?? '') as String;
  final lat = (t['lat'] as num?)?.toDouble() ?? 0;
  final lng = (t['lng'] as num?)?.toDouble() ?? 0;

  // ¿Sigue habiendo partido en curso?
  if (prefs.getString(bgNsKey(kActiveSessionBase, uk)) == null) return;
  // ¿Seguís afuera? Con fix adentro no avisamos; sin fix avisamos igual (la
  // salida ya se detectó y el aviso de más no cierra nada).
  if (!await _leftArea(lat, lng, defaultWhenNoFix: true)) return;

  await NotificationsService.instance.init();
  await NotificationsService.instance.show(
    courtName.isEmpty ? 'Estás saliendo de la cancha' : 'Estás saliendo de $courtName',
    'Tu sesión se cierra en 3 minutos. Volvé a la cancha para seguir jugando.',
  );
}

/// Vigilancia de batería (alarma periódica): si hay un partido en curso y la
/// carga quedó muy baja (y no está cargando), lo cierra para proteger la info.
@pragma('vm:entry-point')
Future<void> alarmBatteryCallback() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  // Token laxo: solo cierra un partido ya en curso (ver alarmEndCallback).
  if (!await hasBgSession(prefs, requireFreshToken: false)) {
    await cancelBatteryWatch();
    return;
  }
  final uk = prefs.getString(kBgUserKey) ?? '';
  if (prefs.getString(bgNsKey(kActiveSessionBase, uk)) == null) {
    // No hay partido en curso: la vigilancia ya no hace falta.
    await cancelBatteryWatch();
    return;
  }
  // Con partido en curso: aprovechamos el único despertar periódico que tenemos
  // para avisar si el ahorro de energía está frenando la detección. Va ANTES del
  // corte por batería baja, que hace return en la mayoría de los casos.
  await maybeNotifyPowerSave(prefs, playing: true);
  try {
    final battery = Battery();
    final state = await battery.batteryState;
    if (state == BatteryState.charging || state == BatteryState.full) return;
    if (await battery.batteryLevel > _kBatteryEndPercent) return;
  } catch (_) {
    return; // sin lectura de batería: no hacemos nada
  }
  await _closeActiveToPending(prefs, uk, lowBattery: true);
  _pingMain();
}

/// Pregunta de partido largo (3h de juego): "pausa" el partido estampando
/// `confirmAskedAtMillis` en la sesión activa y muestra "¿Seguís jugando?".
/// Con la app viva el ticker suele adelantarse (_beginConfirm) y este callback
/// no hace nada (idempotente). Es la vía con el proceso muerto.
@pragma('vm:entry-point')
Future<void> alarmConfirmCallback() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  // Token laxo: pregunta sobre un partido ya en curso (ver alarmEndCallback).
  if (!await hasBgSession(prefs, requireFreshToken: false)) return;
  final uk = prefs.getString(kBgUserKey) ?? '';
  final activeKey = bgNsKey(kActiveSessionBase, uk);
  final raw = prefs.getString(activeKey);
  if (raw == null) return; // no hay partido: nada que preguntar
  Map<String, dynamic> a;
  try {
    a = jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return;
  }
  // Gracia de salida en curso: el partido ya se está cerrando solo.
  if (a['endsAtMillis'] != null) return;
  // Ya preguntado (el ticker se adelantó) o ya confirmó su hora extra.
  if (a['confirmAskedAtMillis'] != null) return;
  if (a['confirmedOnce'] == true) return;

  final now = DateTime.now();
  a['confirmAskedAtMillis'] = now.millisecondsSinceEpoch;
  await prefs.setString(activeKey, jsonEncode(a));
  await scheduleConfirmTimeoutAlarm(at: now.add(_kConfirmTimeout));
  await NotificationsService.instance.init();
  await NotificationsService.instance
      .showContinueCheck((a['courtName'] ?? '') as String);
  _pingMain();
}

/// Timeout de la pregunta: si nadie respondió (el flag sigue en la sesión
/// activa), descarta el partido POR COMPLETO — sin pendiente, sin puntos, sin
/// historial.
@pragma('vm:entry-point')
Future<void> alarmConfirmTimeoutCallback() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  // Token laxo: descarta un partido ya en curso (ver alarmEndCallback).
  if (!await hasBgSession(prefs, requireFreshToken: false)) return;
  final uk = prefs.getString(kBgUserKey) ?? '';
  final raw = prefs.getString(bgNsKey(kActiveSessionBase, uk));
  if (raw == null) return;
  Map<String, dynamic> a;
  try {
    a = jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return;
  }
  // Respondida (el isolate principal limpió el flag): nada que hacer.
  if (a['confirmAskedAtMillis'] == null) return;
  await _discardActive(prefs, uk, a);
  _pingMain();
}

/// Tope duro de la hora extra tras el "SÍ": cierra y GUARDA el partido
/// (pendiente de resultado) usando el tope como fin, y avisa que llegó al
/// límite de tiempo.
@pragma('vm:entry-point')
Future<void> alarmHardEndCallback() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final raw = prefs.getString(_kAlarmHardEnd);
  await prefs.remove(_kAlarmHardEnd);
  // Token laxo: cierra y GUARDA un partido ya en curso (ver alarmEndCallback).
  if (!await hasBgSession(prefs, requireFreshToken: false)) return;
  final uk = prefs.getString(kBgUserKey) ?? '';
  final activeRaw = prefs.getString(bgNsKey(kActiveSessionBase, uk));
  if (activeRaw == null) return;
  int? atMillis;
  if (raw != null) {
    try {
      atMillis =
          ((jsonDecode(raw) as Map<String, dynamic>)['atMillis'] as num?)
              ?.toInt();
    } catch (_) {}
  }
  // Snooze de la cancha (mismo flujo que "No juego"): el celu sigue en el
  // radio y sin esto el radar re-sembraría la permanencia enseguida. Al
  // reabrir, el restore adopta el snooze y aparece el botón "Iniciar partido".
  // Se lee ANTES del cierre porque _closeActiveToPending borra la sesión.
  try {
    final a = jsonDecode(activeRaw) as Map<String, dynamic>;
    final courtId = (a['courtId'] ?? '') as String;
    if (courtId.isNotEmpty) {
      await prefs.setString(
        bgNsKey(_kDwellSnoozeBase, uk),
        jsonEncode({
          'courtId': courtId,
          'untilMillis':
              DateTime.now().add(_kDwellSnooze).millisecondsSinceEpoch,
        }),
      );
    }
  } catch (_) {}
  await _closeActiveToPending(
    prefs,
    uk,
    lowBattery: false,
    endsAtMillis: atMillis,
    notifTitle: 'Llegaste al tiempo límite',
    notifBody: 'Guardamos tu sesión de 4 horas. Abrí 1of1 para registrar '
        'el resultado.',
  );
  _pingMain();
}

/// Descarta el partido en curso POR COMPLETO desde background (timeout de la
/// pregunta): sin pendiente, sin puntos, sin historial. Silencia el detector
/// de esa cancha 2:30hs (el celu probablemente sigue dentro del radio: sin snooze
/// el dwell re-arrancaría enseguida) y avisa por notificación.
Future<void> _discardActive(
    SharedPreferences prefs, String uk, Map<String, dynamic> a) async {
  await prefs.remove(bgNsKey(kActiveSessionBase, uk));
  final courtId = (a['courtId'] ?? '') as String;
  if (courtId.isNotEmpty) {
    await prefs.setString(
      bgNsKey(_kDwellSnoozeBase, uk),
      jsonEncode({
        'courtId': courtId,
        'untilMillis':
            DateTime.now().add(_kDwellSnooze).millisecondsSinceEpoch,
      }),
    );
  }
  await cancelBatteryWatch();
  await cancelConfirmAlarm();
  await cancelConfirmTimeoutAlarm();
  await cancelHardEndAlarm();
  await AndroidAlarmManager.cancel(kAlarmEndId);
  await AndroidAlarmManager.cancel(kAlarmWarnId);
  await prefs.remove(_kAlarmEnd);
  await prefs.remove(_kAlarmWarn);
  await _setNotionPresence(prefs, playing: false, courtId: '', sinceIso: '');
  await NotificationsService.instance.init();
  await NotificationsService.instance.cancelContinueCheck();
  await NotificationsService.instance.show(
    'Sesión cancelada',
    'No respondiste si seguías jugando, así que no la guardamos.',
  );
  await NotificationsService.instance.cancelSession();
}

/// WATCHDOG del radar: si el radar dejó de tickear, lo vuelve a programar.
///
/// Con el radar de vuelta en `AndroidAlarmManager.periodic` esto es redundancia
/// (Android mantiene ese schedule solo), pero se conserva a propósito: cubre el
/// caso de que la alarma del radar no haya quedado registrada — p. ej. porque
/// falló al programarse durante el arranque de la app, escenario que no deja
/// ninguna señal (ver [_oneShotAt]).
@pragma('vm:entry-point')
Future<void> alarmWatchdogCallback() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  // Token laxo, mismo criterio que el propio radar: un JWT vencido no apaga
  // la vigilancia, solo el logout real.
  if (!await hasBgSession(prefs, requireFreshToken: false)) {
    await cancelWatchdog();
    return;
  }
  final lastTick = prefs.getInt(kLastRadarTickKey) ?? 0;
  final staleSince = DateTime.now().millisecondsSinceEpoch -
      _kRadarStaleAfter.inMilliseconds;
  if (lastTick < staleSince) {
    // El radar no da señales de vida: re-programarlo. scheduleRadarWatch
    // cancela cualquier resto antes de registrar, así que es seguro llamarlo
    // aunque en realidad siguiera vivo.
    await scheduleRadarWatch();
  }
}

/// RADAR de respaldo: re-muestrea el GPS y avanza la detección aunque el proceso
/// y el foreground service estén muertos. Espejo en background de lo que hace
/// _evaluate con la app viva:
///  - sin partido ni permanencia → si estás dentro del radio de una cancha,
///    siembra la permanencia (alarma de arranque a +6 min + notificación);
///  - con partido en curso → si estás fuera del radio y no hay gracia en
///    curso, arranca la gracia de salida (alarma de cierre + aviso).
/// Las geofences siguen siendo la vía rápida; esto cubre cuando el OEM las
/// estrangula o mata el servicio (peor caso: [_kRadarEvery] de demora).
///
/// El trabajo vive en [_radarTick], que sella [kLastRadarTickKey] (la señal que
/// lee [alarmWatchdogCallback]) y devuelve `false` solo cuando el radar debe
/// apagarse de verdad — hoy, únicamente al no haber sesión.
///
/// Ojo con el `await` acá adentro: el plugin invoca este callback SIN esperar el
/// `Future` (`closure()` a secas), así que el wakelock del JobIntentService se
/// suelta apenas retornamos y todo lo que quede pendiente corre con el CPU
/// pudiendo dormirse. Mantené el tick lo más corto posible.
@pragma('vm:entry-point')
Future<void> alarmRadarCallback() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (!await _radarTick()) await cancelRadarWatch();
  } catch (_) {
    // Un fallo puntual (GPS, prefs, JSON corrupto) no apaga el radar: la
    // periódica sigue programada y el próximo tick reintenta.
  }
}

/// Un tick del radar. Devuelve si el radar debe seguir programado.
Future<bool> _radarTick() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  // Es el ÚNICO camino que siembra detección nueva con la app cerrada: sin
  // sesión, además de frenarlo, apagamos el radar para no despertar el equipo
  // cada 15 min al vacío (se reprograma al volver a loguearse, vía
  // SyncCoordinator._syncGeofences). El gate va antes de leer el mock: si te
  // deslogueás con el modo prueba activo, el radar también se apaga.
  //
  // Token LAXO para decidir si el radar sigue encendido: un JWT vencido no es
  // un logout. Apagarlo por eso lo dejaría muerto hasta reiniciar el proceso,
  // porque el flag `_radarOn` que lo re-arma vive en el isolate principal y no
  // se entera de lo que hizo el de background.
  if (!await hasBgSession(prefs, requireFreshToken: false)) {
    return false; // única salida que APAGA el radar
  }
  // El tick va a ejecutarse de verdad: sellar ANTES de cualquier return que
  // siga, para que un fix que tarda o falla no se lea como radar muerto.
  await prefs.setInt(
      kLastRadarTickKey, DateTime.now().millisecondsSinceEpoch);
  // Con el token vencido no sembramos detección nueva (mismo criterio que
  // antes), pero el radar sigue latiendo hasta que el JWT se renueve.
  if (!await hasBgSession(prefs)) return true;
  final uk = prefs.getString(kBgUserKey) ?? '';

  final pos = await _currentLatLng();
  if (pos == null) return true; // sin fix: el próximo tick reintenta
  await prefs.setInt(
      kLastBgFixKey, DateTime.now().millisecondsSinceEpoch);

  final activeKey = bgNsKey(kActiveSessionBase, uk);
  final activeRaw = prefs.getString(activeKey);

  if (activeRaw != null) {
    // Partido en curso: detectar la SALIDA si nadie más la detectó.
    if (prefs.getString(_kAlarmEnd) != null) return true; // gracia ya programada
    Map<String, dynamic> a;
    try {
      a = jsonDecode(activeRaw) as Map<String, dynamic>;
    } catch (_) {
      return true;
    }
    if (a['endsAtMillis'] != null) return true; // gracia ya en curso
    // Pausado esperando la respuesta de "¿Seguís jugando?": la pregunta (y su
    // timeout) gobiernan — no sembramos la gracia de salida (semántica de
    // pausa, igual que _evaluate con _pausedAt != null).
    if (a['confirmAskedAtMillis'] != null) return true;
    final startMillis = (a['startMillis'] as num?)?.toInt();
    final courtId = (a['courtId'] ?? '') as String;
    final court = await _courtFromCache(prefs, courtId);
    if (startMillis == null || court == null) return true;
    final d = Geolocator.distanceBetween(
        pos.$1, pos.$2, court.$2, court.$3);
    if (d <= _kRadiusMeters) return true; // seguís adentro: todo normal

    // Estás afuera sin gracia en curso: la arrancamos igual que _beginExitGrace
    // (persistir endsAtMillis + alarma de cierre + notificación de cierre).
    final endsAt = DateTime.now().add(_kExitGrace);
    a['endsAtMillis'] = endsAt.millisecondsSinceEpoch;
    await prefs.setString(activeKey, jsonEncode(a));
    await scheduleEndAlarm(
      userKey: uk,
      courtId: courtId,
      courtName: court.$1,
      lat: court.$2,
      lng: court.$3,
      startMillis: startMillis,
      at: endsAt,
    );
    _pingMain();
    return true;
  }

  // Sin partido en curso: detectar la LLEGADA si no hay permanencia armada.
  if (prefs.getString(_kAlarmStart) != null) return true; // dwell ya sembrado
  final near = await _nearestCourtInRadius(prefs, pos.$1, pos.$2);
  if (near == null) return true;

  // "No juego" vigente en esta cancha: no sembramos (arranque manual desde la
  // app). Si el snooze ya venció, lo limpiamos de paso.
  final snoozeRaw = prefs.getString(bgNsKey(_kDwellSnoozeBase, uk));
  if (snoozeRaw != null) {
    try {
      final s = jsonDecode(snoozeRaw) as Map<String, dynamic>;
      final until = (s['untilMillis'] as num?)?.toInt() ?? 0;
      if (until > DateTime.now().millisecondsSinceEpoch) {
        if (s['courtId'] == near.$1) return true;
      } else {
        await prefs.remove(bgNsKey(_kDwellSnoozeBase, uk));
      }
    } catch (_) {}
  }

  final at = DateTime.now().add(_kDwellThreshold);
  await scheduleStartAlarm(
    userKey: uk,
    courtId: near.$1,
    courtName: near.$2,
    lat: near.$3,
    lng: near.$4,
    at: at,
  );
  // Cuenta regresiva visible: mismo formato que el camino con la app viva.
  await NotificationsService.instance.init();
  // Primero el aviso RUIDOSO (canal de importancia alta) y después el
  // cronómetro persistente, que es silencioso a propósito. Sin el primero la
  // detección funciona pero es invisible: el usuario se entera al abrir la app.
  await NotificationsService.instance
      .showArrivalAlert(near.$2, _kDwellThreshold.inMinutes);
  await NotificationsService.instance
      .showDwellCountdown(near.$2, _kDwellThreshold.inSeconds);
  _pingMain();
  // Llegaste a una cancha: si el ahorro está activo, avisar ANTES de que se
  // pierda el partido (todavía faltan los 6 min de permanencia).
  await maybeNotifyPowerSave(prefs, playing: false);
  return true;
}

/// Siembra la permanencia para [courtId] desde un evento de GEOFENCE con la app
/// cerrada. Es el espejo de lo que hace el radar al encontrarte dentro del
/// radio, pero disparado por el SO al instante en vez de esperar al próximo
/// tick (hasta [_kRadarEvery] de demora).
///
/// Sin esto la geofence solo mostraba un aviso de "abrí la app": la detección
/// automática con la app cerrada quedaba en manos del radar, y llegar a la
/// cancha no arrancaba nada hasta 15 minutos después.
///
/// Devuelve si sembró. Es idempotente y respeta los MISMOS gates que el radar:
/// no pisa un partido en curso, ni una permanencia ya sembrada, ni una cancha
/// silenciada con "No juego".
Future<bool> seedDwellForCourt(String courtId) async {
  if (!_isAndroid || courtId.isEmpty) return false;
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  if (!await hasBgSession(prefs)) return false;
  final uk = prefs.getString(kBgUserKey) ?? '';

  // Partido en curso: no hay nada que sembrar (y si volviste durante la gracia
  // de salida, de eso se encarga cancelEndAlarmOnReenter).
  if (prefs.getString(bgNsKey(kActiveSessionBase, uk)) != null) return false;
  // Permanencia ya sembrada (por el radar o por una geofence anterior).
  if (prefs.getString(_kAlarmStart) != null) return false;

  final court = await _courtFromCache(prefs, courtId);
  if (court == null) return false; // catálogo no cacheado todavía

  // "No juego" vigente en ESTA cancha: el usuario ya dijo que no. Si venció, se
  // limpia de paso (mismo criterio que el radar).
  final snoozeRaw = prefs.getString(bgNsKey(_kDwellSnoozeBase, uk));
  if (snoozeRaw != null) {
    try {
      final sn = jsonDecode(snoozeRaw) as Map<String, dynamic>;
      final until = (sn['untilMillis'] as num?)?.toInt() ?? 0;
      if (until > DateTime.now().millisecondsSinceEpoch) {
        if (sn['courtId'] == courtId) return false;
      } else {
        await prefs.remove(bgNsKey(_kDwellSnoozeBase, uk));
      }
    } catch (_) {}
  }

  final at = DateTime.now().add(_kDwellThreshold);
  await scheduleStartAlarm(
    userKey: uk,
    courtId: courtId,
    courtName: court.$1,
    lat: court.$2,
    lng: court.$3,
    at: at,
  );
  await NotificationsService.instance.init();
  // Mismo par que en el radar: aviso ruidoso + cronómetro silencioso.
  await NotificationsService.instance
      .showArrivalAlert(court.$1, _kDwellThreshold.inMinutes);
  await NotificationsService.instance
      .showDwellCountdown(court.$1, _kDwellThreshold.inSeconds);
  _pingMain();
  return true;
}

/// Posición actual (lat, lng) respetando la ubicación simulada del modo
/// prueba. null si no hay fix.
Future<(double, double)?> _currentLatLng() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final mock = prefs.getString(kMockPosKey);
    if (mock != null) {
      final parts = mock.split(',');
      final mlat = double.tryParse(parts[0]);
      final mlng = double.tryParse(parts.length > 1 ? parts[1] : '');
      if (mlat != null && mlng != null) return (mlat, mlng);
    }
  } catch (_) {}
  try {
    // Timeout corto A PROPÓSITO: esto corre en un callback de alarma, cuyo
    // wakelock ya se soltó (el plugin no espera nuestro Future). Cuanto más
    // tiempo pasemos acá, más chances de que el CPU se duerma a mitad del tick.
    // Sin fix, el próximo tick reintenta en [_kRadarEvery].
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).timeout(const Duration(seconds: 8));
    return (pos.latitude, pos.longitude);
  } catch (_) {
    return null;
  }
}

/// (nombre, lat, lng) de una cancha del cache por id. null si no está.
Future<(String, double, double)?> _courtFromCache(
    SharedPreferences prefs, String courtId) async {
  final raw = prefs.getString(kCourtsGeoCacheKey);
  if (raw == null || courtId.isEmpty) return null;
  try {
    for (final e in jsonDecode(raw) as List) {
      final m = e as Map<String, dynamic>;
      if (m['id'] == courtId) {
        return (
          (m['name'] ?? '') as String,
          (m['lat'] as num).toDouble(),
          (m['lng'] as num).toDouble(),
        );
      }
    }
  } catch (_) {}
  return null;
}

/// (id, nombre, lat, lng) de la cancha más cercana dentro del radio. null si
/// ninguna cae dentro.
Future<(String, String, double, double)?> _nearestCourtInRadius(
    SharedPreferences prefs, double lat, double lng) async {
  final raw = prefs.getString(kCourtsGeoCacheKey);
  if (raw == null) return null;
  (String, String, double, double)? best;
  var bestDist = _kRadiusMeters + 1;
  try {
    for (final e in jsonDecode(raw) as List) {
      final m = e as Map<String, dynamic>;
      final clat = (m['lat'] as num?)?.toDouble() ?? 0;
      final clng = (m['lng'] as num?)?.toDouble() ?? 0;
      if (clat == 0 && clng == 0) continue;
      final d = Geolocator.distanceBetween(lat, lng, clat, clng);
      if (d <= _kRadiusMeters && d < bestDist) {
        bestDist = d;
        best = ((m['id'] ?? '') as String, (m['name'] ?? '') as String, clat, clng);
      }
    }
  } catch (_) {}
  return best;
}

/// Cierra el partido en curso (sesión activa → pendiente de resultado) desde el
/// isolate de background. Descarta si duró menos de [_kMinMatchSeconds].
/// [notifTitle]/[notifBody] permiten personalizar el aviso (p. ej. el cierre
/// por tiempo límite); si no se pasan, va el texto estándar.
Future<void> _closeActiveToPending(
  SharedPreferences prefs,
  String uk, {
  required bool lowBattery,
  int? endsAtMillis,
  String? notifTitle,
  String? notifBody,
}) async {
  final activeKey = bgNsKey(kActiveSessionBase, uk);
  final activeRaw = prefs.getString(activeKey);
  if (activeRaw == null) return;
  Map<String, dynamic> a;
  try {
    a = jsonDecode(activeRaw) as Map<String, dynamic>;
  } catch (_) {
    return;
  }
  final startMillis = (a['startMillis'] as num?)?.toInt();
  if (startMillis == null) return;
  final courtId = (a['courtId'] ?? '') as String;
  final courtName = (a['courtName'] ?? '') as String;

  final now = DateTime.now();
  // Tope de la duración: el fin de gracia (si lo tenemos), no el momento en que
  // corre el callback (la alarma puede llegar tarde). Así la duración no se
  // infla. Fallback (batería): usamos "now".
  final nowMs = now.millisecondsSinceEpoch;
  var endMs = (endsAtMillis != null && endsAtMillis < nowMs) ? endsAtMillis : nowMs;
  // Defensivo: con la pregunta de partido largo pendiente, el cronómetro quedó
  // congelado en ese momento — cualquier cierre debe capear ahí, no en "now".
  final askedMs = (a['confirmAskedAtMillis'] as num?)?.toInt();
  if (askedMs != null && askedMs < endMs) endMs = askedMs;
  final seconds = ((endMs - startMillis) / 1000).round();

  await prefs.remove(activeKey);
  await cancelBatteryWatch(); // el partido cerró: no seguimos vigilando
  // El partido cerró: la pregunta de partido largo (y sus alarmas) ya no
  // tienen sentido, en cualquier estado en que hayan quedado.
  await cancelConfirmAlarm();
  await cancelConfirmTimeoutAlarm();
  await cancelHardEndAlarm();
  await _setNotionPresence(prefs, playing: false, courtId: '', sinceIso: '');
  await NotificationsService.instance.init();
  await NotificationsService.instance.cancelContinueCheck();

  if (seconds >= _kMinMatchSeconds) {
    // Partido válido → pendiente de resultado (mismo formato que PlaySession).
    await prefs.setString(
      bgNsKey(kPendingResultBase, uk),
      jsonEncode({
        'courtId': courtId,
        'courtName': courtName,
        'seconds': seconds,
        'endedAt': endMs,
        'result': null,
        'points': 0,
      }),
    );
    await NotificationsService.instance.show(
      notifTitle ??
          (lowBattery
              ? 'Sesión terminada por batería baja'
              : 'Terminó tu sesión de juego'),
      notifBody ??
          (lowBattery
              ? 'Cerramos tu sesión para proteger tu información. Abrí 1of1 '
                  'para registrar el resultado.'
              : 'Abrí 1of1 para registrar el resultado.'),
    );
  }
  await NotificationsService.instance.cancelSession();
}

// ── Helpers del callback ─────────────────────────────────────────────────────

/// True si hay fix GPS y estás a más de [_kRadiusMeters] del punto. Si no hay
/// fix (o no hay coords), devuelve [defaultWhenNoFix]. Este default es clave:
///  - ARRANQUE (`alarmStartCallback`): false → sin fix asumimos que seguís
///    dentro, así arrancamos igual (best-effort a favor de arrancar).
///  - CIERRE (`alarmEndCallback`): true → sin fix asumimos que seguís afuera y
///    CERRAMOS. La salida ya se detectó [exitGrace] antes; si no podemos
///    confirmar que volviste, el default correcto es cerrar (antes se quedaba
///    abierto para siempre hasta reabrir la app).
Future<bool> _leftArea(double lat, double lng,
    {required bool defaultWhenNoFix}) async {
  if (lat == 0 && lng == 0) return defaultWhenNoFix;
  // DEV: con una ubicación simulada activa (modo prueba), decidimos con ella en
  // vez del GPS real; si no, el GPS real (lejos de la cancha simulada) abortaría
  // el arranque o cerraría el partido en plena prueba.
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final mock = prefs.getString(kMockPosKey);
    if (mock != null) {
      final parts = mock.split(',');
      final mlat = double.tryParse(parts[0]);
      final mlng = double.tryParse(parts.length > 1 ? parts[1] : '');
      if (mlat != null && mlng != null) {
        return Geolocator.distanceBetween(mlat, mlng, lat, lng) >
            _kRadiusMeters;
      }
    }
  } catch (_) {/* sin prefs: seguimos con el GPS real */}
  try {
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).timeout(const Duration(seconds: 12));
    final d =
        Geolocator.distanceBetween(pos.latitude, pos.longitude, lat, lng);
    return d > _kRadiusMeters;
  } catch (_) {
    return defaultWhenNoFix;
  }
}

/// Escribe la presencia en el backend DESDE EL ISOLATE de background. No hay
/// memoria compartida con el isolate principal: el JWT se lee de prefs (clave
/// global `session_jwt`). Si falta o venció, se deja `presence_dirty` en prefs
/// y el ping al isolate principal dispara la reconciliación (que reintenta vía
/// el mecanismo `_dirty` de Session).
Future<void> _setNotionPresence(
  SharedPreferences prefs, {
  required bool playing,
  required String courtId,
  required String sinceIso,
}) async {
  try {
    if (!ApiConfig.isConfigured) return;
    final jwt = validBgJwt(prefs);
    if (jwt == null) {
      await prefs.setBool('presence_dirty', true);
      return;
    }
    await ApiClient(token: jwt).setPresence(
      playing: playing,
      courtId: playing ? courtId : '',
      since: sinceIso.isEmpty ? null : sinceIso,
    );
    // Reflejamos en el caché local para que quede consistente.
    final profRaw = prefs.getString('session_profile');
    if (profRaw != null) {
      final prof = jsonDecode(profRaw) as Map<String, dynamic>;
      prof['playing'] = playing;
      prof['playingCourtId'] = playing ? courtId : '';
      prof['playingSince'] = sinceIso;
      await prefs.setString('session_profile', jsonEncode(prof));
    }
  } catch (_) {
    // Best-effort: marcar para que el isolate principal reintente.
    try {
      await prefs.setBool('presence_dirty', true);
    } catch (_) {}
  }
}

void _pingMain() {
  try {
    IsolateNameServer.lookupPortByName(kPlayPortName)
        ?.send(<String, dynamic>{'action': 'reconcile'});
  } catch (_) {}
}

// ── Aviso de vuelta a la cancha (reenganche) ────────────────────────────────
// La ÚNICA notificación que sale sin que haya pasado nada en la cancha: si el
// usuario deja de jugar, a los 2 días le avisamos. No es detección — no toma
// GPS ni red, solo lee prefs — pero vive acá porque necesita una alarma del SO:
// `notifications_service.dart` solo sabe mostrar notificaciones inmediatas, no
// programarlas (no hay `zonedSchedule` ni el paquete `timezone`).

/// Cada cuántos días se avisa, una vez por etapa. Después de la última, SILENCIO
/// hasta que vuelva a jugar: seguir insistiendo cada 2 días es la forma más
/// rápida de que apague las notificaciones de la app entera.
const List<int> kNudgeDaysSteps = [2, 5, 10];

/// Ventana horaria en que puede mostrarse (hora local, fin exclusivo). Existe
/// para que el aviso no suene de madrugada cuando la última sesión terminó
/// tarde.
const int kNudgeHourFrom = 18;
const int kNudgeHourTo = 22;

/// Cadencia de la alarma. **Tiene que ser ≤ el largo de la ventana**: una
/// grilla de período `s` cae siempre dentro de una ventana de largo ≥ `s`, así
/// que con 4 h de período y 4 h de ventana hay garantía de un tick por día
/// caiga donde caiga la grilla. Con 6 h, una grilla 17/23/05/11 se saltearía el
/// día entero.
const Duration _kNudgeEvery = Duration(hours: 4);

/// Epoch ms de la última sesión REGISTRADA (no de la última vez que abrió la
/// app: quien entra todos los días sin ir a jugar es justo a quien hay que
/// avisarle). Namespaced; la escribe `PlaySessionService.resolvePending`.
const String kLastSessionBase = 'play_last_session';

/// Etapa de [kNudgeDaysSteps] ya avisada (0..3). Vuelve a 0 al jugar.
const String kNudgeStageBase = 'play_nudge_stage';

/// Cuándo se avisó por última vez: dos ticks caen dentro de la misma ventana de
/// 4 h, y sin esto el segundo mostraría el aviso de la etapa siguiente el mismo
/// día.
const String kNudgeLastBase = 'play_nudge_last';

/// `{"court": "...", "streak": n}` para personalizar el texto. Lo deja armado
/// el isolate principal: parsear `play_log` (hasta 100 sesiones de JSON) dentro
/// de un callback sin wakelock es justo lo que no hay que hacer acá.
const String kNudgeCtxBase = 'play_nudge_ctx';

/// Preferencia del usuario (default ON). Namespaced como el resto.
const String kNudgeEnabledBase = 'play_nudge_enabled';

/// Programa el aviso de reenganche. Lo llama SyncCoordinator al loguear y cada
/// vez que el usuario toca el switch.
///
/// **Periódica e INEXACTA, a propósito.** Un aviso de reenganche no tiene
/// deadline: `exact: true` se descarta en silencio si falta el permiso (ver
/// [_oneShotAt]) y encima gastaría el presupuesto de alarmas exactas que sí
/// necesitan las del ciclo de juego. Y periódica —no una cadena de one-shots—
/// porque el schedule lo mantiene Android; la cadena ya rompió la detección una
/// vez (ver [scheduleRadarWatch]).
Future<void> scheduleNudge() async {
  if (!_isAndroid) return;
  await AndroidAlarmManager.cancel(kAlarmNudgeId);
  await AndroidAlarmManager.periodic(
    _kNudgeEvery,
    kAlarmNudgeId,
    alarmNudgeCallback,
    // `allowWhileIdle` aunque no sea crítica: en Doze profundo una alarma sin
    // esto se difiere hasta la próxima ventana de mantenimiento, que puede caer
    // fuera de [kNudgeHourFrom, kNudgeHourTo) y hacer que el aviso no salga
    // nunca. A una cada 4 h el costo es nulo — Android igual las estrangula a
    // uno cada ~9 min.
    wakeup: true,
    allowWhileIdle: true,
    rescheduleOnReboot: true,
  );
}

Future<void> cancelNudge() async {
  if (!_isAndroid) return;
  await AndroidAlarmManager.cancel(kAlarmNudgeId);
}

/// Título y cuerpo del aviso según la etapa y lo que sepamos del usuario.
///
/// Dos familias por etapa: personalizada cuando hay cancha habitual o racha,
/// genérica cuando no (cuenta nueva, o historial sin nada que destacar). Dentro
/// de cada una rota con [seed] —el timestamp de la última sesión— así dos
/// rachas de inactividad seguidas no repiten el mismo texto.
///
/// El de la última etapa DICE que es el último. Es deliberado: es lo que hace
/// que la serie se lea como que la app se preocupa y no como que persigue.
({String title, String body}) buildNudgeText(
  int stage,
  int days,
  String court,
  int streak,
  int seed,
) {
  final hayCancha = court.isNotEmpty;
  final rot = seed.abs();
  switch (stage) {
    case 0:
      if (hayCancha) {
        return rot % 2 == 0
            ? (
                title: 'Hace $days días que $court no te ve',
                body: 'Una hora alcanza. Fijate quién anda por ahí.'
              )
            : (
                title: '$court te está esperando',
                body: '$days días afuera. Hoy puede ser el día.'
              );
      }
      return rot % 2 == 0
          ? (
              title: '$days días sin pisar una cancha',
              body: 'La pelota no se tira sola.'
            )
          : (
              title: 'Hace $days días que no jugás',
              body: 'Buscá una cancha cerca y armá algo.'
            );
    case 1:
      if (streak > 0) {
        return (
          title: 'Tu racha de $streak sigue viva. Por ahora.',
          body: '$days días sin jugar. Todavía estás a tiempo.'
        );
      }
      if (hayCancha) {
        return (
          title: '$days días afuera',
          body: '$court sigue en el mismo lugar.'
        );
      }
      return (
        title: '$days días afuera',
        body: 'El que vuelve primero es el que mejor juega.'
      );
    default:
      return hayCancha
          ? (
              title: '$days días sin $court',
              body: 'Último recordatorio, prometido. '
                  'Cuando quieras volver, te esperamos.'
            )
          : (
              title: '$days días sin jugar',
              body: 'Último recordatorio, prometido. Acá vamos a estar.'
            );
  }
}

/// Tick del aviso de reenganche. Corre en un isolate de background cada 4 h.
///
/// **Barato a propósito**: prefs adentro, notificación afuera y listo. El
/// plugin invoca los callbacks sin `await`, así que el wakelock se suelta al
/// primer `await` y todo lo que venga después puede truncarse — por eso acá no
/// hay ni GPS ni red (a diferencia del radar, que sí toma un fix).
@pragma('vm:entry-point')
Future<void> alarmNudgeCallback() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();

  // Gate ESTRICTO: esto es un aviso proactivo, no el cierre de algo ya en
  // curso. Mismo criterio que alarmStartCallback.
  if (!await hasBgSession(prefs)) {
    await cancelNudge();
    return;
  }
  // Sin userKey no se puede namespacear, y `bgNsKey` cae a la clave pelada:
  // leeríamos el estado de nadie.
  final uk = prefs.getString(kBgUserKey) ?? '';
  if (uk.isEmpty) return;

  if (!(prefs.getBool(bgNsKey(kNudgeEnabledBase, uk)) ?? true)) return;

  // Nunca jugó: "hace 2 días que no jugás" sería mentira. Ese caso es
  // onboarding, no reenganche.
  final last = prefs.getInt(bgNsKey(kLastSessionBase, uk)) ?? 0;
  if (last <= 0) return;

  final stage = prefs.getInt(bgNsKey(kNudgeStageBase, uk)) ?? 0;
  if (stage >= kNudgeDaysSteps.length) return;

  final now = DateTime.now();
  if (now.hour < kNudgeHourFrom || now.hour >= kNudgeHourTo) return;

  // Ya se avisó hoy: con período de 4 h entra más de un tick en la ventana.
  final lastNudge = prefs.getInt(bgNsKey(kNudgeLastBase, uk)) ?? 0;
  if (lastNudge > 0) {
    final prev = DateTime.fromMillisecondsSinceEpoch(lastNudge);
    if (prev.year == now.year &&
        prev.month == now.month &&
        prev.day == now.day) {
      return;
    }
  }

  final days =
      now.difference(DateTime.fromMillisecondsSinceEpoch(last)).inDays;

  // Saltar a la etapa MÁS ALTA ya alcanzada. Sin esto, alguien que estuvo 12
  // días afuera (o que reinstaló) recibiría las tres etapas en tres noches
  // seguidas: la de 2 días, la de 5 y la de 10, todas atrasadas. Se avisa una
  // sola vez, con el mensaje que corresponde a lo que realmente pasó.
  var etapa = stage;
  while (etapa + 1 < kNudgeDaysSteps.length &&
      days >= kNudgeDaysSteps[etapa + 1]) {
    etapa++;
  }
  if (days < kNudgeDaysSteps[etapa]) return;

  var court = '';
  var streak = 0;
  try {
    final raw = prefs.getString(bgNsKey(kNudgeCtxBase, uk));
    if (raw != null && raw.isNotEmpty) {
      final ctx = jsonDecode(raw) as Map<String, dynamic>;
      court = (ctx['court'] as String?) ?? '';
      streak = (ctx['streak'] as num?)?.toInt() ?? 0;
    }
  } catch (_) {/* sin contexto: mensaje genérico */}

  final txt = buildNudgeText(etapa, days, court, streak, last);
  // Se persiste ANTES de notificar: si el proceso muere entre las dos cosas,
  // preferimos perder un aviso a mandar el mismo dos veces.
  await prefs.setInt(bgNsKey(kNudgeStageBase, uk), etapa + 1);
  await prefs.setInt(bgNsKey(kNudgeLastBase, uk), now.millisecondsSinceEpoch);
  await NotificationsService.instance.showNudge(txt.title, txt.body);
}
