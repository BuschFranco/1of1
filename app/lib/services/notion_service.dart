import 'dart:convert';
import 'package:http/http.dart' as http;
import '../notion/notion_config.dart';

/// Cliente mínimo de la API REST de Notion.
///
/// Provee query/create/update sobre databases + helpers para construir y
/// parsear propiedades Notion (title, rich_text, number, checkbox, select,
/// multi_select, url, phone_number, date).
class NotionService {
  NotionService({String? token}) : _token = token ?? NotionConfig.token;

  final String _token;
  static const String _base = 'https://api.notion.com/v1';

  bool get isConfigured => _token.isNotEmpty;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $_token',
        'Notion-Version': NotionConfig.apiVersion,
        'Content-Type': 'application/json',
      };

  /// Consulta una database. Devuelve la lista de páginas (results).
  Future<List<Map<String, dynamic>>> queryDatabase(
    String databaseId, {
    Map<String, dynamic>? filter,
    List<Map<String, dynamic>>? sorts,
    int pageSize = 100,
  }) async {
    final body = <String, dynamic>{'page_size': pageSize};
    if (filter != null) body['filter'] = filter;
    if (sorts != null) body['sorts'] = sorts;

    final res = await http.post(
      Uri.parse('$_base/databases/$databaseId/query'),
      headers: _headers,
      body: jsonEncode(body),
    );
    _ensureOk(res, 'queryDatabase');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['results'] as List).cast<Map<String, dynamic>>();
  }

  /// Crea una página dentro de una database. Devuelve la página creada.
  Future<Map<String, dynamic>> createPage(
    String databaseId,
    Map<String, dynamic> properties,
  ) async {
    final res = await http.post(
      Uri.parse('$_base/pages'),
      headers: _headers,
      body: jsonEncode({
        'parent': {'database_id': databaseId},
        'properties': properties,
      }),
    );
    _ensureOk(res, 'createPage');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Actualiza propiedades de una página existente.
  Future<Map<String, dynamic>> updatePage(
    String pageId,
    Map<String, dynamic> properties,
  ) async {
    final res = await http.patch(
      Uri.parse('$_base/pages/$pageId'),
      headers: _headers,
      body: jsonEncode({'properties': properties}),
    );
    _ensureOk(res, 'updatePage');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Asegura que una database tenga ciertas propiedades (mapa nombre -> tipo,
  /// ej. 'rich_text' | 'checkbox' | 'date' | 'number'). Es idempotente: Notion
  /// fusiona el schema, así que reenviar una propiedad existente del mismo tipo
  /// no la altera. Requiere capacidad de "actualizar contenido" en la
  /// integración. Si falla (p.ej. permisos), lanza.
  Future<void> ensureProperties(
    String databaseId,
    Map<String, String> nameToType,
  ) async {
    if (nameToType.isEmpty) return;
    final res = await http.patch(
      Uri.parse('$_base/databases/$databaseId'),
      headers: _headers,
      body: jsonEncode({
        'properties': {
          for (final e in nameToType.entries) e.key: {e.value: {}},
        }
      }),
    );
    _ensureOk(res, 'ensureProperties');
  }

  /// Archiva (borra) una página.
  Future<void> archivePage(String pageId) async {
    final res = await http.patch(
      Uri.parse('$_base/pages/$pageId'),
      headers: _headers,
      body: jsonEncode({'archived': true}),
    );
    _ensureOk(res, 'archivePage');
  }

  Future<Map<String, dynamic>> retrievePage(String pageId) async {
    final res = await http.get(
      Uri.parse('$_base/pages/$pageId'),
      headers: _headers,
    );
    _ensureOk(res, 'retrievePage');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  void _ensureOk(http.Response res, String op) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw NotionException(op, res.statusCode, res.body);
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Builders: Dart value -> Notion property payload
  // ─────────────────────────────────────────────────────────────────────

  static Map<String, dynamic> title(String value) => {
        'title': [
          {
            'text': {'content': value}
          }
        ]
      };

  static Map<String, dynamic> richText(String value) => {
        'rich_text': [
          {
            'text': {'content': value}
          }
        ]
      };

  static Map<String, dynamic> number(num? value) => {'number': value};

  static Map<String, dynamic> checkbox(bool value) => {'checkbox': value};

  static Map<String, dynamic> select(String? value) =>
      {'select': value == null || value.isEmpty ? null : {'name': value}};

  static Map<String, dynamic> multiSelect(List<String> values) => {
        'multi_select': [
          for (final v in values) {'name': v}
        ]
      };

  static Map<String, dynamic> url(String? value) =>
      {'url': value == null || value.isEmpty ? null : value};

  static Map<String, dynamic> phone(String? value) =>
      {'phone_number': value == null || value.isEmpty ? null : value};

  static Map<String, dynamic> date(String? isoStart) =>
      {'date': isoStart == null ? null : {'start': isoStart}};

  // ─────────────────────────────────────────────────────────────────────
  // Parsers: Notion page -> Dart value
  // (reciben el mapa `properties` de una página)
  // ─────────────────────────────────────────────────────────────────────

  static String readTitle(Map<String, dynamic> props, String name) {
    final list = props[name]?['title'] as List?;
    if (list == null || list.isEmpty) return '';
    return list.map((e) => e['plain_text'] ?? '').join();
  }

  static String readText(Map<String, dynamic> props, String name) {
    final list = props[name]?['rich_text'] as List?;
    if (list == null || list.isEmpty) return '';
    return list.map((e) => e['plain_text'] ?? '').join();
  }

  static double readNumber(Map<String, dynamic> props, String name,
      {double fallback = 0}) {
    final v = props[name]?['number'];
    return v is num ? v.toDouble() : fallback;
  }

  static int readInt(Map<String, dynamic> props, String name,
      {int fallback = 0}) {
    final v = props[name]?['number'];
    return v is num ? v.toInt() : fallback;
  }

  static bool readCheckbox(Map<String, dynamic> props, String name) {
    return props[name]?['checkbox'] == true;
  }

  static String readSelect(Map<String, dynamic> props, String name,
      {String fallback = ''}) {
    return props[name]?['select']?['name'] ?? fallback;
  }

  static List<String> readMultiSelect(Map<String, dynamic> props, String name) {
    final list = props[name]?['multi_select'] as List?;
    if (list == null) return const [];
    return list.map((e) => (e['name'] ?? '').toString()).toList();
  }

  static String readUrl(Map<String, dynamic> props, String name,
      {String fallback = ''}) {
    return props[name]?['url'] ?? fallback;
  }

  static String readPhone(Map<String, dynamic> props, String name,
      {String fallback = ''}) {
    return props[name]?['phone_number'] ?? fallback;
  }

  static String? readDate(Map<String, dynamic> props, String name) {
    return props[name]?['date']?['start'];
  }

  /// Filtro de igualdad para una propiedad rich_text.
  static Map<String, dynamic> filterText(String property, String value) => {
        'property': property,
        'rich_text': {'equals': value}
      };

  /// Filtro de igualdad para la propiedad title.
  static Map<String, dynamic> filterTitle(String property, String value) => {
        'property': property,
        'title': {'equals': value}
      };

  /// Filtro para checkbox.
  static Map<String, dynamic> filterCheckbox(String property, bool value) => {
        'property': property,
        'checkbox': {'equals': value}
      };

  /// Filtro de igualdad para una propiedad select.
  static Map<String, dynamic> filterSelect(String property, String value) => {
        'property': property,
        'select': {'equals': value}
      };
}

class NotionException implements Exception {
  NotionException(this.op, this.statusCode, this.body);
  final String op;
  final int statusCode;
  final String body;

  @override
  String toString() => 'NotionException($op): HTTP $statusCode — $body';
}
