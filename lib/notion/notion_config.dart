/// Configuración de la integración con Notion.
///
/// El TOKEN se inyecta en build-time vía --dart-define (igual que MAPS_API_KEY),
/// nunca se commitea. Los IDs de las bases no son secretos, así que van con
/// default embebido y se pueden sobreescribir por dart-define si hiciera falta.
class NotionConfig {
  /// Internal Integration Secret de Notion (ntn_... o secret_...).
  static const String token = String.fromEnvironment('NOTION_TOKEN');

  static const String dbUsers = String.fromEnvironment(
    'NOTION_DB_USERS',
    defaultValue: '42c859d28f854f2cb004a8a68fd7b374',
  );
  static const String dbProfiles = String.fromEnvironment(
    'NOTION_DB_PROFILES',
    defaultValue: '38505f6959d44e968b537afe66459657',
  );
  static const String dbCourts = String.fromEnvironment(
    'NOTION_DB_COURTS',
    defaultValue: 'bda471e99e2f420887a0ca441ae68488',
  );
  static const String dbReviews = String.fromEnvironment(
    'NOTION_DB_REVIEWS',
    defaultValue: 'a878279779174b7baecb13a8c1fbf9dc',
  );
  static const String dbPickups = String.fromEnvironment(
    'NOTION_DB_PICKUPS',
    defaultValue: 'e4e76d276ec34012be0b36ba1f5ed133',
  );
  static const String dbFriends = String.fromEnvironment(
    'NOTION_DB_FRIENDS',
    defaultValue: 'a83f5d37fae54973ae106698c83545fa',
  );

  /// Versión de la API REST de Notion (estable, query por database_id).
  static const String apiVersion = '2022-06-28';

  /// La app puede hablar con Notion solo si hay token. Si no, degrada a
  /// los datos mock locales (kCourts).
  static bool get isConfigured => token.isNotEmpty;
}
