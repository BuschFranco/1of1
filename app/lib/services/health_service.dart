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

  const HealthMetrics({
    this.calories = 0,
    this.avgHr,
    this.maxHr,
    this.steps = 0,
    this.distance = 0,
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
  static const List<HealthDataType> _types = [
    HealthDataType.HEART_RATE,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.TOTAL_CALORIES_BURNED,
    HealthDataType.STEPS,
    HealthDataType.DISTANCE_DELTA,
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
    // Un renglón por tipo: cantidad de muestras y agregado, o el error puntual.
    for (final t in _types) {
      try {
        final points = await _health.getHealthDataFromTypes(
          startTime: start,
          endTime: end,
          types: [t],
        );
        final clean = _health.removeDuplicates(points);
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
        sb.writeln('${t.name}: ${clean.length} muestras$agg');
      } catch (e) {
        sb.writeln('${t.name}: ERROR → $e');
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
    // Leemos CADA tipo por separado: si uno falla (permiso/soporte), no anula
    // la lectura de los demás. En Android no se puede verificar el permiso de
    // LECTURA (Health Connect lo oculta), así que intentamos leer directo.
    double activeCal = 0;
    double totalCal = 0;
    int steps = 0;
    double distance = 0;
    final hrs = <double>[];
    for (final t in _types) {
      try {
        final points = await _health.getHealthDataFromTypes(
          startTime: start,
          endTime: end,
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
              if (n > 0) hrs.add(n.toDouble());
              break;
            default:
              break;
          }
        }
      } catch (_) {/* seguimos con los demás tipos */}
    }

    int? avgHr;
    int? maxHr;
    if (hrs.isNotEmpty) {
      avgHr = (hrs.reduce((a, b) => a + b) / hrs.length).round();
      maxHr = hrs.reduce((a, b) => a > b ? a : b).round();
    }

    return HealthMetrics(
      // Preferimos calorías ACTIVAS; si el origen no las escribe, caemos a las
      // totales. Nunca se suman (sería doble conteo: total incluye activas).
      calories: activeCal > 0 ? activeCal : totalCal,
      avgHr: avgHr,
      maxHr: maxHr,
      steps: steps,
      distance: distance,
    );
  }
}
