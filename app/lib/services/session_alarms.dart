import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../notion/notion_config.dart';
import 'notion_service.dart';
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
// Pregunta de partido largo: a las 2h de juego neto pausa el partido y
// pregunta "¿Seguís jugando?" aunque la app esté cerrada.
const int kAlarmConfirmId = 100016;
// Timeout de la pregunta: sin respuesta en [_kConfirmTimeout], descarta el
// partido por completo (sin pendiente, sin puntos, sin historial).
const int kAlarmConfirmTimeoutId = 100017;
// Tope duro de la hora extra tras el "SÍ": cierra y GUARDA el partido.
const int kAlarmHardEndId = 100018;

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

// Claves fijas (no namespaced) con el "objetivo" de cada alarma.
const String _kAlarmStart = 'play_alarm_start';
const String _kAlarmEnd = 'play_alarm_end';
const String _kAlarmWarn = 'play_alarm_warn';
const String _kAlarmHardEnd = 'play_alarm_hardend';

// Claves base de PlaySessionService (deben coincidir EXACTO).
const String _kActiveBase = 'play_active_session';
const String _kPendingBase = 'play_pending_result';
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
// GEMELAS de PlaySessionService.pointsTimeCap / confirmTimeout / dwellSnooze:
// umbral de la pregunta de partido largo, ventana de respuesta, y snooze del
// detector tras descartar (el celu probablemente sigue en el radio).
const Duration _kConfirmAfter = Duration(hours: 2);
const Duration _kConfirmTimeout = Duration(minutes: 20);
const Duration _kDwellSnooze = Duration(hours: 1);

String _nsKey(String base, String uk) => uk.isEmpty ? base : '$base::$uk';

bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

/// Programa una alarma exacta con fallback: si el SO rechaza la exacta (p. ej.
/// el usuario revocó "Alarmas y recordatorios" en Android 14+), reintenta como
/// inexacta — dispara con demora de minutos, pero dispara (mejor que nada).
Future<void> _oneShotAt(DateTime at, int id, Function callback) async {
  try {
    await AndroidAlarmManager.oneShotAt(
      at,
      id,
      callback,
      exact: true,
      wakeup: true,
      allowWhileIdle: true,
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
  final activeKey = _nsKey(_kActiveBase, uk);
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

/// Arranca el radar periódico de respaldo (con `rescheduleOnReboot` para que
/// sobreviva reinicios del equipo). Lo programa SyncCoordinator cuando hay
/// sesión + background habilitado + permiso "Siempre".
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

/// Programa la pregunta de partido largo para [at] (2h de juego NETO). La
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
    _nsKey(_kActiveBase, uk),
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
    '¡Arrancó tu partido!',
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

  final activeKey = _nsKey(_kActiveBase, uk);
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
  if (prefs.getString(_nsKey(_kActiveBase, uk)) == null) return;
  // ¿Seguís afuera? Con fix adentro no avisamos; sin fix avisamos igual (la
  // salida ya se detectó y el aviso de más no cierra nada).
  if (!await _leftArea(lat, lng, defaultWhenNoFix: true)) return;

  await NotificationsService.instance.init();
  await NotificationsService.instance.show(
    courtName.isEmpty ? 'Estás saliendo de la cancha' : 'Estás saliendo de $courtName',
    'Tu partido se cierra en 3 minutos. Volvé a la cancha para seguir jugando.',
  );
}

/// Vigilancia de batería (alarma periódica): si hay un partido en curso y la
/// carga quedó muy baja (y no está cargando), lo cierra para proteger la info.
@pragma('vm:entry-point')
Future<void> alarmBatteryCallback() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final uk = prefs.getString(kBgUserKey) ?? '';
  if (prefs.getString(_nsKey(_kActiveBase, uk)) == null) {
    // No hay partido en curso: la vigilancia ya no hace falta.
    await cancelBatteryWatch();
    return;
  }
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

/// Pregunta de partido largo (2h de juego): "pausa" el partido estampando
/// `confirmAskedAtMillis` en la sesión activa y muestra "¿Seguís jugando?".
/// Con la app viva el ticker suele adelantarse (_beginConfirm) y este callback
/// no hace nada (idempotente). Es la vía con el proceso muerto.
@pragma('vm:entry-point')
Future<void> alarmConfirmCallback() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final uk = prefs.getString(kBgUserKey) ?? '';
  final activeKey = _nsKey(_kActiveBase, uk);
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
  final uk = prefs.getString(kBgUserKey) ?? '';
  final raw = prefs.getString(_nsKey(_kActiveBase, uk));
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
  final uk = prefs.getString(kBgUserKey) ?? '';
  final activeRaw = prefs.getString(_nsKey(_kActiveBase, uk));
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
        _nsKey(_kDwellSnoozeBase, uk),
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
    notifBody: 'Guardamos tu partido de 3 horas. Abrí 1of1 para registrar '
        'el resultado.',
  );
  _pingMain();
}

/// Descarta el partido en curso POR COMPLETO desde background (timeout de la
/// pregunta): sin pendiente, sin puntos, sin historial. Silencia el detector
/// de esa cancha 1h (el celu probablemente sigue dentro del radio: sin snooze
/// el dwell re-arrancaría enseguida) y avisa por notificación.
Future<void> _discardActive(
    SharedPreferences prefs, String uk, Map<String, dynamic> a) async {
  await prefs.remove(_nsKey(_kActiveBase, uk));
  final courtId = (a['courtId'] ?? '') as String;
  if (courtId.isNotEmpty) {
    await prefs.setString(
      _nsKey(_kDwellSnoozeBase, uk),
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
    'Partido cancelado',
    'No respondiste si seguías jugando, así que no lo guardamos.',
  );
  await NotificationsService.instance.cancelSession();
}

/// RADAR de respaldo (alarma periódica): re-muestrea el GPS y avanza la
/// detección aunque el proceso y el foreground service estén muertos. Espejo
/// en background de lo que hace _evaluate con la app viva:
///  - sin partido ni permanencia → si estás dentro del radio de una cancha,
///    siembra la permanencia (alarma de arranque a +6 min + notificación);
///  - con partido en curso → si estás fuera del radio y no hay gracia en
///    curso, arranca la gracia de salida (alarma de cierre + aviso).
/// Las geofences siguen siendo la vía rápida; esto cubre cuando el OEM las
/// estrangula o mata el servicio (peor caso: [_kRadarEvery] de demora).
@pragma('vm:entry-point')
Future<void> alarmRadarCallback() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final uk = prefs.getString(kBgUserKey) ?? '';

  final pos = await _currentLatLng();
  if (pos == null) return; // sin fix: el próximo tick reintenta
  await prefs.setInt(
      kLastBgFixKey, DateTime.now().millisecondsSinceEpoch);

  final activeKey = _nsKey(_kActiveBase, uk);
  final activeRaw = prefs.getString(activeKey);

  if (activeRaw != null) {
    // Partido en curso: detectar la SALIDA si nadie más la detectó.
    if (prefs.getString(_kAlarmEnd) != null) return; // gracia ya programada
    Map<String, dynamic> a;
    try {
      a = jsonDecode(activeRaw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (a['endsAtMillis'] != null) return; // gracia ya en curso
    // Pausado esperando la respuesta de "¿Seguís jugando?": la pregunta (y su
    // timeout) gobiernan — no sembramos la gracia de salida (semántica de
    // pausa, igual que _evaluate con _pausedAt != null).
    if (a['confirmAskedAtMillis'] != null) return;
    final startMillis = (a['startMillis'] as num?)?.toInt();
    final courtId = (a['courtId'] ?? '') as String;
    final court = await _courtFromCache(prefs, courtId);
    if (startMillis == null || court == null) return;
    final d = Geolocator.distanceBetween(
        pos.$1, pos.$2, court.$2, court.$3);
    if (d <= _kRadiusMeters) return; // seguís adentro: todo normal

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
    return;
  }

  // Sin partido en curso: detectar la LLEGADA si no hay permanencia armada.
  if (prefs.getString(_kAlarmStart) != null) return; // dwell ya sembrado
  final near = await _nearestCourtInRadius(prefs, pos.$1, pos.$2);
  if (near == null) return;

  // "No juego" vigente en esta cancha: no sembramos (arranque manual desde la
  // app). Si el snooze ya venció, lo limpiamos de paso.
  final snoozeRaw = prefs.getString(_nsKey(_kDwellSnoozeBase, uk));
  if (snoozeRaw != null) {
    try {
      final s = jsonDecode(snoozeRaw) as Map<String, dynamic>;
      final until = (s['untilMillis'] as num?)?.toInt() ?? 0;
      if (until > DateTime.now().millisecondsSinceEpoch) {
        if (s['courtId'] == near.$1) return;
      } else {
        await prefs.remove(_nsKey(_kDwellSnoozeBase, uk));
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
  await NotificationsService.instance
      .showDwellCountdown(near.$2, _kDwellThreshold.inSeconds);
  _pingMain();
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
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).timeout(const Duration(seconds: 12));
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
  final activeKey = _nsKey(_kActiveBase, uk);
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
      _nsKey(_kPendingBase, uk),
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
              ? 'Partido terminado por batería baja'
              : 'Terminó tu partido'),
      notifBody ??
          (lowBattery
              ? 'Cerramos tu partido para proteger tu información. Abrí 1of1 '
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

Future<void> _setNotionPresence(
  SharedPreferences prefs, {
  required bool playing,
  required String courtId,
  required String sinceIso,
}) async {
  try {
    if (!NotionConfig.isConfigured) return;
    final profRaw = prefs.getString('session_profile');
    if (profRaw == null) return;
    final prof = jsonDecode(profRaw) as Map<String, dynamic>;
    final pageId = (prof['pageId'] ?? '') as String;
    if (pageId.isEmpty) return;
    await NotionService().updatePage(pageId, {
      'Playing': NotionService.checkbox(playing),
      'PlayingCourtId': NotionService.richText(playing ? courtId : ''),
      'PlayingSince': NotionService.date(sinceIso.isEmpty ? null : sinceIso),
    });
    // Reflejamos en el caché local para que quede consistente.
    prof['playing'] = playing;
    prof['playingCourtId'] = playing ? courtId : '';
    prof['playingSince'] = sinceIso;
    await prefs.setString('session_profile', jsonEncode(prof));
  } catch (_) {/* best-effort */}
}

void _pingMain() {
  try {
    IsolateNameServer.lookupPortByName(kPlayPortName)
        ?.send(<String, dynamic>{'action': 'reconcile'});
  } catch (_) {}
}
