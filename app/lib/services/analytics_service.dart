import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase Analytics. Por ahora solo Android: iOS todavía no tiene su
/// `GoogleService-Info.plist` y el bundle id sigue siendo el de plantilla.
///
/// Nunca rompe la app: si Firebase no inicializa (sin config, sin Play
/// Services), todos los métodos son no-op.
class AnalyticsService {
  AnalyticsService._();

  static FirebaseAnalytics? _fa;

  /// Se llama una vez en `main()`, sin bloquear el arranque.
  static Future<void> init() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await Firebase.initializeApp();
      _fa = FirebaseAnalytics.instance;
    } catch (_) {
      _fa = null;
    }
  }

  /// Pantalla vista. Las pestañas no son rutas de Navigator, así que el
  /// registro automático de pantallas de Firebase no las ve: se loguean a mano.
  static void screen(String name) {
    final fa = _fa;
    if (fa == null) return;
    fa.logScreenView(screenName: name).catchError((_) {});
  }

  /// Evento de una acción completada. Lista y criterios en docs/analytics.md.
  ///
  /// NUNCA mandar datos personales en [params] (email, handle, textos que
  /// escribió el usuario, insignia de clan): solo ids, tipos, cantidades y
  /// booleanos. Los bool se mandan como 0/1 porque GA4 no acepta bool.
  static void event(String name, [Map<String, Object?> params = const {}]) {
    final fa = _fa;
    if (fa == null) return;
    fa
        .logEvent(name: name, parameters: _clean(params))
        .catchError((_) {});
  }

  /// Eventos recomendados de GA4 (salen en sus informes estándar).
  static void login(String method) =>
      _fa?.logLogin(loginMethod: method).catchError((_) {});
  static void signUp(String method) =>
      _fa?.logSignUp(signUpMethod: method).catchError((_) {});
  static void joinGroup(String groupId, Map<String, Object?> params) =>
      event('join_group', {'group_id': groupId, ...params});
  static void share(String contentType, Map<String, Object?> params) =>
      event('share', {'content_type': contentType, ...params});

  static Map<String, Object> _clean(Map<String, Object?> p) => {
        for (final e in p.entries)
          if (e.value case final Object v)
            e.key: switch (v) {
              final bool b => b ? 1 : 0,
              final String s => s.length > 100 ? s.substring(0, 100) : s,
              _ => v,
            },
      };
}
