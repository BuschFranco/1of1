import 'package:health/health.dart';

/// Métricas de salud agregadas para un partido (leídas del wearable vía
/// Health Connect / HealthKit). [calories] son calorías activas quemadas;
/// [avgHr]/[maxHr] el pulso promedio/máximo; [steps] los pasos del rango.
class HealthMetrics {
  final double calories;
  final int? avgHr;
  final int? maxHr;
  final int steps;
  /// Distancia recorrida durante el partido, en metros.
  final double distance;

  /// True si las calorías/distancia vinieron de una SESIÓN de entrenamiento
  /// registrada en el reloj (más precisa que sumar muestras sueltas).
  final bool fromWorkout;

  /// Actividad de la sesión de entrenamiento (p.ej. "BASKETBALL"), si la hubo.
  final String? workoutActivity;

  /// Distribución de tiempo en zonas cardíacas: [calentamiento, quemaGrasa,
  /// cardio, pico, maximo] — cada valor son segundos acumulados en esa zona.
  /// Null si no hay datos de pulso.
  final List<int>? hrZones;

  // ── Métricas de muestreo esporádico ──────────────────────────────────────
  // Null = el reloj no registró ninguna muestra en la ventana del partido, que
  // es lo NORMAL para varias de ellas (SpO2 y HRV suelen medirse en reposo).
  /// Saturación de oxígeno en sangre, en % (promedio de las muestras).
  final int? spo2;
  /// Frecuencia cardíaca en reposo (bpm). Es un valor diario del reloj, no del
  /// partido: sirve como indicador de estado de forma.
  final int? restingHr;
  /// Variabilidad cardíaca RMSSD, en ms. Indicador de recuperación/fatiga.
  final int? hrv;
  /// Ritmo respiratorio, en respiraciones por minuto.
  final int? respiratoryRate;
  /// Velocidad promedio, en m/s.
  final double? speed;

  const HealthMetrics({
    this.calories = 0,
    this.avgHr,
    this.maxHr,
    this.steps = 0,
    this.distance = 0,
    this.fromWorkout = false,
    this.workoutActivity,
    this.hrZones,
    this.spo2,
    this.restingHr,
    this.hrv,
    this.respiratoryRate,
    this.speed,
  });

  /// ¿Hay algo que valga la pena registrar? (sin wearable suele venir todo en 0)
  bool get hasData =>
      calories > 0 || steps > 0 || avgHr != null || distance > 0;
}

/// Wrapper del paquete `health`: lee del store unificado del OS (Health Connect
/// en Android, HealthKit en iOS), así que es agnóstico del wearable (reloj o
/// anillo) mientras éste sincronice al sistema.
///
/// No se pide ningún permiso al construirlo: [requestPermissions] se llama solo
/// cuando el usuario activa "Conectar Salud" (regla: nada de auto-requests).
class HealthService {
  final Health _health = Health();
  bool _configured = false;

  /// Tipos que leemos. Calorías activas es la métrica que da puntos (récord);
  /// pulso y pasos son registro visual en el historial. OJO: si se pidieran
  /// varios tipos en UNA sola llamada y uno fallara (permiso/soporte), Health
  /// Connect tira excepción y se cae toda la lectura; por eso leemos por tipo.
  /// TOTAL_CALORIES es el fallback de calorías: muchos orígenes (Samsung
  /// Health, sobre todo) solo escriben totales, no activas — sin él, calorías
  /// daba 0 para siempre en esos equipos.
  /// WORKOUT es la sesión de ejercicio del reloj (básquet, etc.): sus totales
  /// (calorías, distancia) son los que muestra Samsung y cubren la duración
  /// real de la sesión, así que enriquecen el partido cuando existe.
  /// Métricas "de esfuerzo": las que un reloj mide DURANTE el partido.
  static const List<HealthDataType> _types = [
    HealthDataType.HEART_RATE,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.TOTAL_CALORIES_BURNED,
    HealthDataType.STEPS,
    HealthDataType.DISTANCE_DELTA,
    HealthDataType.WORKOUT,
    // Añadidas después: los relojes las muestrean de forma ESPORÁDICA (SpO2 y
    // HRV suelen medirse en reposo o de noche), así que es normal que un partido
    // no tenga ninguna muestra. La UI las omite cuando faltan en vez de
    // mostrarlas en cero, que se leería como "tu oxígeno fue 0".
    HealthDataType.BLOOD_OXYGEN,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
    HealthDataType.RESPIRATORY_RATE,
    HealthDataType.SPEED,
  ];

  static final List<HealthDataAccess> _perms =
      List.filled(_types.length, HealthDataAccess.READ);

  /// Promedio de las muestras, o null si no hubo ninguna. Null y 0 significan
  /// cosas distintas acá: "el reloj no midió" vs "midió cero".
  static double? _promedio(List<double> v) =>
      v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// ¿Está Health Connect disponible en el dispositivo? (Android). En iOS
  /// HealthKit está siempre presente, así que devolvemos true best-effort.
  Future<bool> isAvailable() async {
    try {
      await _ensureConfigured();
      final status = await _health.getHealthConnectSdkStatus();
      return status == HealthConnectSdkStatus.sdkAvailable;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasPermissions() async {
    try {
      await _ensureConfigured();
      return (await _health.hasPermissions(_types, permissions: _perms)) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Dispara el flujo de permisos del sistema. Devuelve si quedaron concedidos.
  Future<bool> requestPermissions() async {
    try {
      await _ensureConfigured();
      return await _health.requestAuthorization(_types, permissions: _perms);
    } catch (_) {
      return false;
    }
  }

  /// Nombre legible de un origen de datos. En Android `sourceName` trae el
  /// **packageName** de la app que escribió el dato (`sourceId` viene siempre
  /// vacío y `deviceModel` siempre null), así que es la ÚNICA señal de origen
  /// disponible — y la que distingue "lo escribió el reloj" de "lo escribió el
  /// celular".
  static String _sourceLabel(String raw) {
    const conocidos = {
      'com.sec.android.app.shealth': 'Samsung Health',
      'com.google.android.apps.fitness': 'Google Fit',
      'com.google.android.gms': 'Google Play Services',
      'com.huawei.health': 'Huawei Health',
      'com.xiaomi.wearable': 'Xiaomi Wearable',
      'com.huami.watch.hmwatchmanager': 'Zepp',
      'com.garmin.android.apps.connectmobile': 'Garmin Connect',
      'com.fitbit.FitbitMobile': 'Fitbit',
      'com.buschfranco.oneofone': '1of1 (esta app)',
    };
    if (raw.isEmpty) return 'origen desconocido';
    return conocidos[raw] ?? raw;
  }

  /// Desglose por origen de una lista de puntos: "Samsung Health: 4820 (12 reg.)".
  /// Es el corazón del diagnóstico: si acá solo figura el proveedor del teléfono,
  /// el problema no está en la app sino en el puente del reloj.
  /// Tipos que se PROMEDIAN en vez de sumarse: sumar pulsos o saturaciones de
  /// oxígeno no significa nada (31 muestras de ~78 bpm dan "2404", que confunde).
  static const _promediables = {
    HealthDataType.HEART_RATE,
    HealthDataType.BLOOD_OXYGEN,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
    HealthDataType.RESPIRATORY_RATE,
    HealthDataType.SPEED,
  };

  static String _porOrigen(List<HealthDataPoint> puntos, HealthDataType t) {
    final sumas = <String, double>{};
    final conteos = <String, int>{};
    for (final p in puntos) {
      final k = _sourceLabel(p.sourceName);
      final v = p.value;
      sumas[k] = (sumas[k] ?? 0) + (v is NumericHealthValue ? v.numericValue.toDouble() : 0);
      conteos[k] = (conteos[k] ?? 0) + 1;
    }
    if (sumas.isEmpty) return '';
    final promediar = _promediables.contains(t);
    final partes = sumas.entries.map((e) {
      final n = conteos[e.key] ?? 1;
      final valor = promediar ? (e.value / n) : e.value;
      return '${e.key}: ${valor.round()}${promediar ? ' prom' : ''} ($n reg.)';
    }).toList();
    return '\n    ↳ ${partes.join('\n    ↳ ')}';
  }

  /// Rango temporal cubierto por los puntos, para ver si están repartidos en el
  /// partido o concentrados en dos minutos.
  static String _rango(List<HealthDataPoint> puntos) {
    if (puntos.isEmpty) return '';
    var min = puntos.first.dateFrom;
    var max = puntos.first.dateTo;
    for (final p in puntos) {
      if (p.dateFrom.isBefore(min)) min = p.dateFrom;
      if (p.dateTo.isAfter(max)) max = p.dateTo;
    }
    String hhmm(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '\n    ↳ de ${hhmm(min)} a ${hhmm(max)}';
  }

  /// Diagnóstico legible de por qué un partido no trae datos de salud.
  ///
  /// Con [from]/[to] analiza la ventana EXACTA de un partido; sin ellos, las
  /// últimas [back] horas. Lo importante es el desglose **por origen**: sirve
  /// para distinguir "el reloj no sincronizó" de "solo escribió el celular",
  /// que es la diferencia entre un bug de la app y un problema del puente del
  /// fabricante.
  Future<String> diagnose({
    Duration back = const Duration(hours: 6),
    DateTime? from,
    DateTime? to,
  }) async {
    final sb = StringBuffer();
    try {
      await _ensureConfigured();
    } catch (e) {
      return 'No se pudo inicializar salud:\n$e';
    }
    HealthConnectSdkStatus? status;
    try {
      status = await _health.getHealthConnectSdkStatus();
    } catch (_) {}
    sb.writeln('Health Connect: ${status ?? 'desconocido'}');
    // En Android este chequeo es poco confiable para permisos de LECTURA (los
    // oculta): true = concedido; false = denegado; null = no se puede saber.
    Object? perm;
    try {
      perm = await _health.hasPermissions(_types, permissions: _perms);
    } catch (e) {
      perm = 'error: $e';
    }
    sb.writeln('Permiso lectura: $perm');

    // Ventana del partido si nos la dan; si no, las últimas `back` horas.
    final end = to ?? DateTime.now();
    final start = from ?? end.subtract(back);
    String hhmm(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    sb.writeln(from != null
        ? 'Ventana: el partido (${hhmm(start)} a ${hhmm(end)})'
        : 'Ventana: últimas ${back.inHours}h');
    sb.writeln('');
    // Un renglón por tipo: permiso individual, muestras y agregado, o el error.
    // El permiso por tipo es lo que más importa: Health Connect concede de a
    // uno, así que Calorías/Distancia pueden estar denegadas aunque HR ande.
    // Todos los orígenes vistos, para el veredicto del final.
    final origenes = <String>{};
    for (final t in _types) {
      // Estado del permiso de ESTE tipo (en Android puede venir null = oculto).
      String permLabel;
      try {
        final p = await _health.hasPermissions([t], permissions: [
          HealthDataAccess.READ,
        ]);
        permLabel = p == true ? 'permiso: sí' : (p == false ? 'permiso: NO' : 'permiso: ?');
      } catch (_) {
        permLabel = 'permiso: ?';
      }
      try {
        final points = await _health.getHealthDataFromTypes(
          startTime: start,
          endTime: end,
          types: [t],
        );
        final clean = _health.removeDuplicates(points);
        for (final p in clean) {
          if (p.sourceName.isNotEmpty) origenes.add(p.sourceName);
        }
        // WORKOUT: cada punto es una sesión de ejercicio (no un número). Se
        // reporta actividad + totales para poder verificar el enriquecimiento.
        if (t == HealthDataType.WORKOUT) {
          final sesiones = clean
              .where((p) => p.value is WorkoutHealthValue)
              .map((p) {
            final w = p.value as WorkoutHealthValue;
            final kcal = w.totalEnergyBurned;
            final m = w.totalDistance;
            // El horario de la sesión importa: si no solapa con el partido, no
            // lo enriquece por más que exista.
            return '${w.workoutActivityType.name} '
                '(${hhmm(p.dateFrom)}-${hhmm(p.dateTo)}, '
                '${_sourceLabel(p.sourceName)})'
                '${kcal != null ? ' · $kcal kcal' : ''}'
                '${m != null ? ' · $m m' : ''}';
          }).toList();
          final detalle =
              sesiones.isEmpty ? '' : '\n    ↳ ${sesiones.join('\n    ↳ ')}';
          sb.writeln('${t.name} ($permLabel): ${clean.length} sesiones$detalle');
          continue;
        }
        double sum = 0;
        for (final p in clean) {
          final v = p.value;
          if (v is NumericHealthValue) sum += v.numericValue.toDouble();
        }
        final agg = switch (t) {
          HealthDataType.ACTIVE_ENERGY_BURNED => ' · ${sum.round()} kcal',
          HealthDataType.TOTAL_CALORIES_BURNED => ' · ${sum.round()} kcal',
          HealthDataType.STEPS => ' · ${sum.round()} pasos',
          HealthDataType.DISTANCE_DELTA => ' · ${sum.round()} m',
          HealthDataType.HEART_RATE => ' · prom ${clean.isEmpty ? 0 : (sum / clean.length).round()} bpm',
          _ => '',
        };
        // El desglose por origen es LO importante de todo el diagnóstico.
        sb.writeln('${t.name} ($permLabel): ${clean.length} muestras$agg'
            '${_porOrigen(clean, t)}${_rango(clean)}');
      } catch (e) {
        sb.writeln('${t.name} ($permLabel): ERROR → $e');
      }
    }
    // Veredicto: lo primero que hay que mirar es QUIÉN escribió los datos. Si
    // solo figura el proveedor del propio teléfono, ningún cambio en la app va a
    // traer los datos del reloj — hay que arreglar el puente del fabricante.
    sb.writeln('');
    sb.writeln('── Orígenes de datos ──');
    if (origenes.isEmpty) {
      sb.writeln('NINGUNO escribió datos en esta ventana.');
      sb.writeln('Ni el reloj ni el teléfono. Revisá que Health Connect tenga '
          'permisos y que la app de tu reloj esté sincronizando.');
    } else {
      for (final o in origenes) {
        sb.writeln('· ${_sourceLabel(o)}');
      }
      const puente = {
        'com.sec.android.app.shealth',
        'com.huawei.health',
        'com.xiaomi.wearable',
        'com.huami.watch.hmwatchmanager',
        'com.garmin.android.apps.connectmobile',
        'com.fitbit.FitbitMobile',
      };
      if (!origenes.any(puente.contains)) {
        sb.writeln('');
        sb.writeln('⚠ No aparece ninguna app de reloj/pulsera. Los datos que ves '
            'son del TELÉFONO, por eso los números son bajos.');
        sb.writeln('En Samsung: abrí Samsung Health → Ajustes → Health Connect y '
            'activá el compartido de Pasos, Frecuencia cardíaca, Actividad '
            '(calorías y distancia) y Ejercicio.');
      }
    }
    return sb.toString();
  }

  /// Agrega las métricas de salud en la ventana [start, end] del partido.
  /// Devuelve null si no hay permiso o falla la lectura (el llamador lo trata
  /// como "sin datos", sin romper el flujo).
  Future<HealthMetrics?> metricsFor(DateTime start, DateTime end) async {
    if (end.isBefore(start)) return null;
    try {
      await _ensureConfigured();
    } catch (_) {
      return null;
    }

    // 1) Buscar una SESIÓN de entrenamiento que se solape con el partido. El
    //    reloj pudo arrancar la sesión antes de que el GPS detectara el partido,
    //    así que buscamos con holgura (±30 min) y elegimos la de mayor solape.
    WorkoutHealthValue? workout;
    DateTime winStart = start;
    DateTime winEnd = end;
    /// Qué porción de la sesión del reloj cae dentro del partido (1.0 = toda).
    double workoutShare = 1.0;
    try {
      final wpoints = await _health.getHealthDataFromTypes(
        startTime: start.subtract(const Duration(minutes: 30)),
        endTime: end.add(const Duration(minutes: 30)),
        types: [HealthDataType.WORKOUT],
      );
      HealthDataPoint? best;
      double bestOverlap = 0;
      for (final p in wpoints) {
        if (p.value is! WorkoutHealthValue) continue;
        // Solape (en ms) entre la sesión y la ventana del partido.
        final os = p.dateFrom.isAfter(start) ? p.dateFrom : start;
        final oe = p.dateTo.isBefore(end) ? p.dateTo : end;
        final overlap = oe.difference(os).inMilliseconds.toDouble();
        if (overlap <= 0) continue;
        final act = (p.value as WorkoutHealthValue).workoutActivityType;
        // Preferimos BÁSQUET y OTRO (las dos opciones que el usuario elegiría
        // en el reloj para un partido): a igualdad de solape, ganan sobre un
        // deporte no relacionado que pudiera solapar por casualidad.
        final relevante = act == HealthWorkoutActivityType.BASKETBALL ||
            act == HealthWorkoutActivityType.OTHER;
        // El bonus tiene que ser PROPORCIONAL, no +1: el solape está en
        // milisegundos, así que sumarle 1 no desempata nunca (1 ms de más ya lo
        // supera). Con +25 % un deporte relevante gana ante solapes parecidos,
        // pero uno claramente más largo sigue ganando.
        final score = overlap * (relevante ? 1.25 : 1.0);
        if (best == null || score > bestOverlap) {
          best = p;
          bestOverlap = score;
        }
      }
      if (best != null) {
        workout = best.value as WorkoutHealthValue;
        // Fracción de la sesión que cae DENTRO del partido, para prorratear sus
        // totales. Sin esto, dejar el entrenamiento del reloj corriendo mientras
        // volvías a casa inflaba las calorías del partido (y podía regalar el
        // bonus de récord).
        final so = best.dateFrom.isAfter(start) ? best.dateFrom : start;
        final eo = best.dateTo.isBefore(end) ? best.dateTo : end;
        final durSesion = best.dateTo.difference(best.dateFrom).inMilliseconds;
        final durSolape = eo.difference(so).inMilliseconds;
        workoutShare = (durSesion > 0 && durSolape > 0)
            ? (durSolape / durSesion).clamp(0.0, 1.0)
            : 1.0;
        // Ampliamos la ventana de lectura a la unión con la sesión: así el
        // pulso/pasos cubren todo lo que el reloj grabó.
        if (best.dateFrom.isBefore(winStart)) winStart = best.dateFrom;
        if (best.dateTo.isAfter(winEnd)) winEnd = best.dateTo;
      }
    } catch (_) {/* sin sesión: seguimos con la agregación por tipo */}

    // 2) Agregación por tipo sobre la ventana (ampliada si hubo sesión).
    //    Leemos CADA tipo por separado: si uno falla (permiso/soporte), no
    //    anula la lectura de los demás. En Android no se puede verificar el
    //    permiso de LECTURA (Health Connect lo oculta): intentamos leer directo.
    double activeCal = 0;
    double totalCal = 0;
    int steps = 0;
    double distance = 0;
    final hrs = <double>[];
    // Muestras crudas de HR con timestamps para calcular zonas.
    final hrTimestamps = <DateTime>[];
    // Métricas esporádicas: se juntan las muestras y se promedian al final.
    final spo2s = <double>[];
    final restingHrs = <double>[];
    final hrvs = <double>[];
    final resps = <double>[];
    final speeds = <double>[];
    for (final t in _types) {
      if (t == HealthDataType.WORKOUT) continue; // se maneja aparte (arriba)
      try {
        final points = await _health.getHealthDataFromTypes(
          startTime: winStart,
          endTime: winEnd,
          types: [t],
        );
        final clean = _health.removeDuplicates(points);
        for (final p in clean) {
          final v = p.value;
          final num n = v is NumericHealthValue ? v.numericValue : 0;
          switch (p.type) {
            case HealthDataType.ACTIVE_ENERGY_BURNED:
              activeCal += n.toDouble();
              break;
            case HealthDataType.TOTAL_CALORIES_BURNED:
              totalCal += n.toDouble();
              break;
            case HealthDataType.STEPS:
              steps += n.toInt();
              break;
            case HealthDataType.DISTANCE_DELTA:
              distance += n.toDouble();
              break;
            case HealthDataType.HEART_RATE:
              if (n > 0) {
                hrs.add(n.toDouble());
                hrTimestamps.add(p.dateFrom);
              }
              break;
            // Las esporádicas se promedian: no tiene sentido sumarlas (sumar
            // saturaciones de oxígeno no significa nada). Se descartan los 0,
            // que en estas métricas siempre son lectura fallida.
            case HealthDataType.BLOOD_OXYGEN:
              if (n > 0) spo2s.add(n.toDouble());
              break;
            case HealthDataType.RESTING_HEART_RATE:
              if (n > 0) restingHrs.add(n.toDouble());
              break;
            case HealthDataType.HEART_RATE_VARIABILITY_RMSSD:
              if (n > 0) hrvs.add(n.toDouble());
              break;
            case HealthDataType.RESPIRATORY_RATE:
              if (n > 0) resps.add(n.toDouble());
              break;
            case HealthDataType.SPEED:
              if (n > 0) speeds.add(n.toDouble());
              break;
            default:
              break;
          }
        }
      } catch (_) {/* seguimos con los demás tipos */}
    }

    // Pasos por la API de AGREGACIÓN de Health Connect, que deduplica del lado
    // del sistema. Sumar los registros crudos (arriba) sobrecuenta cuando el
    // reloj y el teléfono cubren el mismo rato: `removeDuplicates` compara los
    // puntos por todos sus campos —uuid y origen incluidos— así que dos fuentes
    // distintas nunca se deduplican entre sí. La suma cruda queda de fallback.
    try {
      final agg = await _health.getTotalStepsInInterval(winStart, winEnd);
      if (agg != null && agg > 0) steps = agg;
    } catch (_) {/* nos quedamos con la suma cruda */}

    int? avgHr;
    int? maxHr;
    List<int>? hrZones;
    if (hrs.isNotEmpty) {
      // Ordenar por fecha ANTES de calcular zonas: Health Connect no garantiza
      // el orden y, mezclando dos orígenes, los deltas entre muestras salían
      // negativos y caían todos en el sanity check de 5 s.
      final idx = List<int>.generate(hrs.length, (i) => i)
        ..sort((a, b) => hrTimestamps[a].compareTo(hrTimestamps[b]));
      final hrsOrd = [for (final i in idx) hrs[i]];
      final tsOrd = [for (final i in idx) hrTimestamps[i]];
      avgHr = (hrsOrd.reduce((a, b) => a + b) / hrsOrd.length).round();
      maxHr = hrsOrd.reduce((a, b) => a > b ? a : b).round();
      hrZones = _computeHrZones(hrsOrd, tsOrd, maxHr);
    }

    // 3) La sesión manda para calorías/distancia (coincide con lo que muestra
    //    el reloj). Si no la trae, caemos a la agregación por tipo: calorías
    //    ACTIVAS y, si el origen no las escribe, TOTALES (nunca se suman).
    //    Los totales de la sesión se PRORRATEAN por la porción que solapa con el
    //    partido (ver workoutShare): una sesión de 3 h que cubre 2 h de partido
    //    aporta 2/3 de sus calorías, no las 3 h enteras.
    final workoutCal =
        (workout?.totalEnergyBurned ?? 0).toDouble() * workoutShare;
    final workoutDist =
        (workout?.totalDistance ?? 0).toDouble() * workoutShare;
    return HealthMetrics(
      calories: workoutCal > 0
          ? workoutCal
          : (activeCal > 0 ? activeCal : totalCal),
      avgHr: avgHr,
      maxHr: maxHr,
      steps: steps,
      distance: workoutDist > 0 ? workoutDist : distance,
      fromWorkout: workout != null,
      workoutActivity: workout?.workoutActivityType.name,
      hrZones: hrZones,
      spo2: _promedio(spo2s)?.round(),
      restingHr: _promedio(restingHrs)?.round(),
      hrv: _promedio(hrvs)?.round(),
      respiratoryRate: _promedio(resps)?.round(),
      speed: _promedio(speeds),
    );
  }

  /// Calcula la distribución de tiempo en zonas cardíacas a partir de las
  /// muestras crutas y sus timestamps. Zonas basadas en % del HR máximo
  /// observado: Calentamiento (<60%), Quema de grasa (60-70%), Cardio (70-80%),
  /// Pico (80-90%), Máximo (>90%). Devuelve lista de 5 enteros (segundos).
  static List<int> _computeHrZones(
      List<double> hrs, List<DateTime> timestamps, int maxHr) {
    final zones = List.filled(5, 0);
    if (hrs.length < 2) return zones;
    // Estimar duración entre muestras consecutivas.
    for (var i = 0; i < hrs.length; i++) {
      int sec;
      if (i < hrs.length - 1) {
        sec = timestamps[i + 1].difference(timestamps[i]).inSeconds;
      } else {
        // Última muestra: usar el promedio de intervalos anteriores.
        sec = timestamps.isNotEmpty && timestamps.length >= 2
            ? (timestamps.last.difference(timestamps.first).inSeconds ~/
                (timestamps.length - 1))
            : 5;
      }
      // Antes, TODO hueco > 60 s se colapsaba a 5 s. Con el reloj fuera de modo
      // ejercicio las muestras vienen cada varios minutos, así que un partido de
      // 2 h daba ~2 min de zonas: el gráfico quedaba vacío. Ahora el hueco se
      // respeta y solo se TOPEA, para que un reloj apagado una hora no invente
      // tiempo que no se jugó.
      const maxHueco = 300; // 5 min
      if (sec <= 0) {
        sec = 5;
      } else if (sec > maxHueco) {
        sec = maxHueco;
      }
      final pct = hrs[i] / maxHr;
      final zi = pct < 0.6
          ? 0
          : (pct < 0.7
              ? 1
              : (pct < 0.8 ? 2 : (pct < 0.9 ? 3 : 4)));
      zones[zi] += sec;
    }
    return zones;
  }
}
