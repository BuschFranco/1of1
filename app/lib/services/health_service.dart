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

  const HealthMetrics({
    this.calories = 0,
    this.avgHr,
    this.maxHr,
    this.steps = 0,
    this.distance = 0,
    this.fromWorkout = false,
    this.workoutActivity,
    this.hrZones,
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
  static const List<HealthDataType> _types = [
    HealthDataType.HEART_RATE,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.TOTAL_CALORIES_BURNED,
    HealthDataType.STEPS,
    HealthDataType.DISTANCE_DELTA,
    HealthDataType.WORKOUT,
  ];

  static final List<HealthDataAccess> _perms =
      List.filled(_types.length, HealthDataAccess.READ);

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

  /// Diagnóstico: lee las últimas [back] horas y devuelve un resumen legible
  /// (estado de Health Connect, muestras por tipo, agregados y error si falla).
  /// Sirve para entender por qué un partido no trae datos de salud.
  Future<String> diagnose({Duration back = const Duration(hours: 6)}) async {
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
    sb.writeln('Ventana: últimas ${back.inHours}h');
    sb.writeln('');

    final end = DateTime.now();
    final start = end.subtract(back);
    // Un renglón por tipo: permiso individual, muestras y agregado, o el error.
    // El permiso por tipo es lo que más importa: Health Connect concede de a
    // uno, así que Calorías/Distancia pueden estar denegadas aunque HR ande.
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
        // WORKOUT: cada punto es una sesión de ejercicio (no un número). Se
        // reporta actividad + totales para poder verificar el enriquecimiento.
        if (t == HealthDataType.WORKOUT) {
          final sesiones = clean
              .where((p) => p.value is WorkoutHealthValue)
              .map((p) {
            final w = p.value as WorkoutHealthValue;
            final kcal = w.totalEnergyBurned;
            final m = w.totalDistance;
            return '${w.workoutActivityType.name}'
                '${kcal != null ? ' · $kcal kcal' : ''}'
                '${m != null ? ' · $m m' : ''}';
          }).toList();
          final detalle = sesiones.isEmpty ? '' : ' · ${sesiones.join(' | ')}';
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
          _ => '',
        };
        sb.writeln('${t.name} ($permLabel): ${clean.length} muestras$agg');
      } catch (e) {
        sb.writeln('${t.name} ($permLabel): ERROR → $e');
      }
    }
    sb.writeln('');
    sb.writeln('Si calorías o distancia dan 0 con permiso OK: en Samsung '
        'Health → Ajustes → Health Connect, confirmá que "Actividad" '
        '(calorías, distancia) esté compartida.');
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
        final score = overlap + (relevante ? 1 : 0);
        if (best == null || score > bestOverlap) {
          best = p;
          bestOverlap = score;
        }
      }
      if (best != null) {
        workout = best.value as WorkoutHealthValue;
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
            default:
              break;
          }
        }
      } catch (_) {/* seguimos con los demás tipos */}
    }

    int? avgHr;
    int? maxHr;
    List<int>? hrZones;
    if (hrs.isNotEmpty) {
      avgHr = (hrs.reduce((a, b) => a + b) / hrs.length).round();
      maxHr = hrs.reduce((a, b) => a > b ? a : b).round();
      // Calcular distribución de zonas cardíacas (segundos por zona).
      hrZones = _computeHrZones(hrs, hrTimestamps, maxHr);
    }

    // 3) La sesión manda para calorías/distancia (coincide con lo que muestra
    //    el reloj). Si no la trae, caemos a la agregación por tipo: calorías
    //    ACTIVAS y, si el origen no las escribe, TOTALES (nunca se suman).
    final workoutCal = (workout?.totalEnergyBurned ?? 0).toDouble();
    final workoutDist = (workout?.totalDistance ?? 0).toDouble();
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
      if (sec <= 0 || sec > 60) sec = 5; // Sanity check.
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
