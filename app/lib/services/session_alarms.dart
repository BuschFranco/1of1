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

/// Puerto para avisarle al isolate principal que reconcilie desde prefs.
const String kPlayPortName = 'oneofone_play_port';

/// userKey activo, para que el callback arme las claves namespaced igual que
/// PlaySessionService (`base::$userKey`).
const String kBgUserKey = 'play_bg_userkey';

/// DEV: ubicación simulada ("lat,lng") del modo prueba. La escribe setMock para
/// que los callbacks de alarma (isolate aparte, sin memoria compartida) también
/// la respeten y el arranque/cierre automático sea testeable sin ir a la cancha.
const String kMockPosKey = 'play_mock_pos';

// Claves fijas (no namespaced) con el "objetivo" de cada alarma.
const String _kAlarmStart = 'play_alarm_start';
const String _kAlarmEnd = 'play_alarm_end';
const String _kAlarmWarn = 'play_alarm_warn';

// Claves base de PlaySessionService (deben coincidir EXACTO).
const String _kActiveBase = 'play_active_session';
const String _kPendingBase = 'play_pending_result';

// Constantes espejo de PlaySessionService (mantener en sync).
const double _kRadiusMeters = 110;
const int _kMinMatchSeconds = 13 * 60;
const int _kBatteryEndPercent = 5;
const Duration _kBatteryWatchEvery = Duration(minutes: 15);
// Gemela de PlaySessionService.endNotifLeadTime: cuánto antes del cierre avisamos.
const Duration _kEndNotifLead = Duration(minutes: 3);

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

  // Arrancó un partido en background → vigilamos la batería.
  await scheduleBatteryWatch();

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

/// Cierra el partido en curso (sesión activa → pendiente de resultado) desde el
/// isolate de background. Descarta si duró menos de [_kMinMatchSeconds].
Future<void> _closeActiveToPending(
  SharedPreferences prefs,
  String uk, {
  required bool lowBattery,
  int? endsAtMillis,
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
  final endMs = (endsAtMillis != null && endsAtMillis < nowMs) ? endsAtMillis : nowMs;
  final seconds = ((endMs - startMillis) / 1000).round();

  await prefs.remove(activeKey);
  await cancelBatteryWatch(); // el partido cerró: no seguimos vigilando
  await _setNotionPresence(prefs, playing: false, courtId: '', sinceIso: '');
  await NotificationsService.instance.init();

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
      lowBattery ? 'Partido terminado por batería baja' : 'Terminó tu partido',
      lowBattery
          ? 'Cerramos tu partido para proteger tu información. Abrí 1of1 para '
              'registrar el resultado.'
          : 'Abrí 1of1 para registrar el resultado.',
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
