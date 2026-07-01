import 'package:health/health.dart';

/// Métricas de salud agregadas para un partido (leídas del wearable vía
/// Health Connect / HealthKit). [calories] son calorías activas quemadas;
/// [avgHr]/[maxHr] el pulso promedio/máximo; [steps] los pasos del rango.
class HealthMetrics {
  final double calories;
  final int? avgHr;
  final int? maxHr;
  final int steps;

  const HealthMetrics({
    this.calories = 0,
    this.avgHr,
    this.maxHr,
    this.steps = 0,
  });

  /// ¿Hay algo que valga la pena registrar? (sin wearable suele venir todo en 0)
  bool get hasData => calories > 0 || steps > 0 || avgHr != null;
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
  /// el resto es registro visual en el historial.
  static const List<HealthDataType> _types = [
    HealthDataType.HEART_RATE,
    HealthDataType.ACTIVE_ENERGY_BURNED,
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

  /// Agrega las métricas de salud en la ventana [start, end] del partido.
  /// Devuelve null si no hay permiso o falla la lectura (el llamador lo trata
  /// como "sin datos", sin romper el flujo).
  Future<HealthMetrics?> metricsFor(DateTime start, DateTime end) async {
    if (end.isBefore(start)) return null;
    try {
      await _ensureConfigured();
      // OJO: en Android, Health Connect NO deja consultar de forma confiable si
      // el permiso de LECTURA está concedido (lo oculta por privacidad) y
      // hasPermissions devuelve null. Por eso NO gateamos acá: intentamos leer
      // directo y, si no hay permiso, la lectura falla/viene vacía y lo tratamos
      // como "sin datos". El opt-in real ya lo controla el flag del servicio.
      final points = await _health.getHealthDataFromTypes(
        startTime: start,
        endTime: end,
        types: _types,
      );
      final clean = _health.removeDuplicates(points);

      double calories = 0;
      int steps = 0;
      final hrs = <double>[];
      for (final p in clean) {
        final v = p.value;
        final num n = v is NumericHealthValue ? v.numericValue : 0;
        switch (p.type) {
          case HealthDataType.ACTIVE_ENERGY_BURNED:
            calories += n.toDouble();
            break;
          case HealthDataType.STEPS:
            steps += n.toInt();
            break;
          case HealthDataType.HEART_RATE:
            if (n > 0) hrs.add(n.toDouble());
            break;
          default:
            break;
        }
      }

      int? avgHr;
      int? maxHr;
      if (hrs.isNotEmpty) {
        avgHr = (hrs.reduce((a, b) => a + b) / hrs.length).round();
        maxHr = hrs.reduce((a, b) => a > b ? a : b).round();
      }

      return HealthMetrics(
        calories: calories,
        avgHr: avgHr,
        maxHr: maxHr,
        steps: steps,
      );
    } catch (_) {
      return null;
    }
  }
}
