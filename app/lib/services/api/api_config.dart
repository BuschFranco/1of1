/// Configuración del backend propio (NestJS).
///
/// `baseUrl` es `const` de compile-time (igual que era el token de Notion)
/// porque los isolates de background NO comparten memoria con el isolate
/// principal: necesitan poder construir el cliente sin estado compartido.
///
/// Se inyecta por dart-define (ver dart_defines.json):
///   "API_BASE_URL": "http://192.168.0.62:3000"
class ApiConfig {
  ApiConfig._();

  static const String baseUrl = String.fromEnvironment('API_BASE_URL');

  /// Clave global (NO namespaced por usuario) donde se persiste el JWT.
  /// Global a propósito: el isolate de background no conoce el userKey.
  /// Mismo criterio que `session_profile`.
  static const String jwtPrefsKey = 'session_jwt';

  /// Sin baseUrl la app degrada a modo offline/mock (no intenta red).
  static bool get isConfigured => baseUrl.isNotEmpty;
}
