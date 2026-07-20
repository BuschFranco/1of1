import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';

/// Cliente único del backend 1of1 (NestJS). Reemplaza a NotionService: la app
/// ya no habla con Notion — el backend es el dueño de la BD y de la auth.
///
/// - JWT: en memoria + persistido en prefs (`ApiConfig.jwtPrefsKey`, global)
///   para que el isolate de background pueda leerlo sin estado compartido.
/// - Errores: `ApiException(statusCode, message)` con el `message` de Nest.
/// - Los métodos devuelven JSON crudo (Map/List); los modelos parsean con
///   `fromApi`/`fromJson`, igual que antes hacían con `fromNotion`.
class ApiClient {
  ApiClient({String? token}) {
    if (token != null) _token = token;
  }

  /// Compartido por TODAS las instancias del proceso: así los servicios que
  /// se instancian sueltos (FriendsService(), etc.) ven la sesión sin
  /// inyección. Cada isolate tiene su copia (memoria no compartida): ahí se
  /// carga con [loadToken] desde prefs.
  static String? _token;
  static const Duration _timeout = Duration(seconds: 12);

  bool get isConfigured => ApiConfig.isConfigured;
  bool get hasToken => _token != null && _token!.isNotEmpty;

  // ── Token ──────────────────────────────────────────────────────────────

  /// Carga el JWT persistido (llamar una vez al arrancar, antes de restore()).
  Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString(ApiConfig.jwtPrefsKey);
    if (t != null && t.isNotEmpty) _token = t;
  }

  Future<void> setToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(ApiConfig.jwtPrefsKey, token);
  }

  Future<void> clearToken() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(ApiConfig.jwtPrefsKey);
  }

  /// Payload del JWT decodificado localmente (sin verificar firma — eso es
  /// del server). `{sub, email, profileId, isAdmin, exp}`.
  Map<String, dynamic> get tokenPayload => decodePayload(_token);

  String get tokenEmail => (tokenPayload['email'] ?? '').toString();
  String get tokenProfileId => (tokenPayload['profileId'] ?? '').toString();

  /// `isAdmin` NO viaja en el Profile del backend: sale del token.
  bool get isAdmin => tokenPayload['isAdmin'] == true;

  /// true si no hay token o su `exp` ya pasó (con 1 min de margen).
  bool get isTokenExpired {
    final exp = tokenPayload['exp'];
    if (exp is! num) return !hasToken;
    final expiry = DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
    return DateTime.now().isAfter(expiry.subtract(const Duration(minutes: 1)));
  }

  /// Decodifica el segmento payload de un JWT (estático para poder usarlo
  /// desde el isolate de background sin instanciar el cliente).
  static Map<String, dynamic> decodePayload(String? jwt) {
    if (jwt == null || jwt.isEmpty) return const {};
    final parts = jwt.split('.');
    if (parts.length != 3) return const {};
    try {
      final raw = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final map = jsonDecode(raw);
      return map is Map<String, dynamic> ? map : const {};
    } catch (_) {
      return const {};
    }
  }

  // ── HTTP genérico ──────────────────────────────────────────────────────

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (hasToken) 'Authorization': 'Bearer $_token',
      };

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${ApiConfig.baseUrl}$path').replace(
        queryParameters: query == null || query.isEmpty ? null : query,
      );

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final uri = _uri(path, query);
    final encoded = body == null ? null : jsonEncode(body);
    late http.Response res;
    switch (method) {
      case 'GET':
        res = await http.get(uri, headers: _headers).timeout(_timeout);
      case 'POST':
        res = await http
            .post(uri, headers: _headers, body: encoded)
            .timeout(_timeout);
      case 'PATCH':
        res = await http
            .patch(uri, headers: _headers, body: encoded)
            .timeout(_timeout);
      case 'DELETE':
        res = await http.delete(uri, headers: _headers).timeout(_timeout);
      default:
        throw ArgumentError('método $method');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.statusCode, _errorMessage(res.body), path);
    }
    if (res.body.isEmpty) return null;
    return jsonDecode(res.body);
  }

  /// Extrae el `message` de un error de Nest (string o lista de validación).
  static String _errorMessage(String body) {
    try {
      final data = jsonDecode(body);
      final msg = data is Map ? data['message'] : null;
      if (msg is List) return msg.join(' · ');
      if (msg is String && msg.isNotEmpty) return msg;
    } catch (_) {}
    return body;
  }

  Future<Map<String, dynamic>> _map(Future<dynamic> f) async =>
      (await f as Map).cast<String, dynamic>();

  Future<List<Map<String, dynamic>>> _list(Future<dynamic> f) async =>
      (await f as List).cast<Map<String, dynamic>>();

  // ── Auth (públicos) ────────────────────────────────────────────────────
  // Devuelven {token, profile}; el caller decide guardar el token (setToken).

  Future<Map<String, dynamic>> login(String email, String password) =>
      _map(_send('POST', '/auth/login', body: {
        'email': email,
        'password': password,
      }));

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String name,
    String? city,
    String? phone,
    String? birthdate,
  }) =>
      _map(_send('POST', '/auth/register', body: {
        'email': email,
        'password': password,
        'name': name,
        if (city != null && city.isNotEmpty) 'city': city,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (birthdate != null && birthdate.isNotEmpty) 'birthdate': birthdate,
      }));

  Future<Map<String, dynamic>> googleLogin(String idToken) =>
      _map(_send('POST', '/auth/google', body: {'idToken': idToken}));

  // ── Perfil propio ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> me() => _map(_send('GET', '/me'));

  Future<Map<String, dynamic>> updateMe(Map<String, dynamic> fields) =>
      _map(_send('PATCH', '/me', body: fields));

  Future<Map<String, dynamic>> setHandle(String handle) =>
      _map(_send('POST', '/me/handle', body: {'handle': handle}));

  Future<Map<String, dynamic>> setPresence({
    required bool playing,
    String? courtId,
    String? since,
  }) =>
      _map(_send('PATCH', '/me/presence', body: {
        'playing': playing,
        'courtId': ?courtId,
        'since': ?since,
      }));

  Future<Map<String, dynamic>> deleteMe() => _map(_send('DELETE', '/me'));

  // ── Perfiles públicos ──────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> profiles({String? fields}) =>
      _list(_send('GET', '/profiles', query: fields != null ? {'fields': fields} : null));

  /// 404 si no existe (ApiException.statusCode == 404).
  Future<Map<String, dynamic>> profileByHandle(String handle) =>
      _map(_send('GET', '/profiles/by-handle', query: {'handle': handle}));

  // ── Canchas y reseñas ──────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> courts() =>
      _list(_send('GET', '/courts'));

  /// Mis canchas propuestas, en TODOS los estados de aprobación.
  Future<List<Map<String, dynamic>>> myCourts() =>
      _list(_send('GET', '/courts/mine'));

  Future<Map<String, dynamic>> proposeCourt(Map<String, dynamic> court) =>
      _map(_send('POST', '/courts', body: court));

  /// Solo admin (403 si no).
  Future<void> deleteCourt(String courtId) =>
      _send('DELETE', '/courts/$courtId');

  Future<List<Map<String, dynamic>>> courtReviews(String courtId) =>
      _list(_send('GET', '/courts/$courtId/reviews'));

  Future<Map<String, dynamic>> createReview(
    String courtId, {
    required int rating,
    required String comment,
  }) =>
      _map(_send('POST', '/courts/$courtId/reviews', body: {
        'rating': rating,
        'comment': comment,
      }));

  /// Dueño de la reseña o admin (403 si no).
  Future<void> deleteReview(String pageId) =>
      _send('DELETE', '/reviews/$pageId');

  // ── Publicaciones de cancha ─────────────────────────────────────────────

  Future<Map<String, dynamic>> courtPosts(
    String courtId, {
    int limit = 20,
    String? cursor,
  }) =>
      _map(_send('GET', '/courts/$courtId/posts', query: {
        'limit': limit.toString(),
        if (cursor != null) 'cursor': cursor,
      }));

  Future<Map<String, dynamic>> createPost(
    String courtId, {
    required String content,
  }) =>
      _map(_send('POST', '/courts/$courtId/posts', body: {
        'content': content,
      }));

  Future<void> deletePost(String postId) =>
      _send('DELETE', '/posts/$postId');

  Future<Map<String, dynamic>> togglePostLike(String postId) =>
      _map(_send('POST', '/posts/$postId/like'));

  Future<Map<String, dynamic>> addPostComment(
    String postId, {
    required String content,
  }) =>
      _map(_send('POST', '/posts/$postId/comments', body: {
        'content': content,
      }));

  Future<void> deletePostComment(String commentId) =>
      _send('DELETE', '/comments/$commentId');

  Future<Map<String, dynamic>> toggleCommentLike(String commentId) =>
      _map(_send('POST', '/comments/$commentId/like'));

  // ── Amistades ──────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> friends() =>
      _list(_send('GET', '/friends'));

  Future<Map<String, dynamic>> addFriend({
    required String friendHandle,
    required String friendName,
    required String friendEmail,
  }) =>
      _map(_send('POST', '/friends', body: {
        'friendHandle': friendHandle,
        'friendName': friendName,
        'friendEmail': friendEmail,
      }));

  Future<void> removeFriend(String pageId) =>
      _send('DELETE', '/friends/$pageId');

  // ── Pickups y chats ────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> pickups() =>
      _list(_send('GET', '/pickups'));

  Future<Map<String, dynamic>> createPickup(Map<String, dynamic> pickup) =>
      _map(_send('POST', '/pickups', body: pickup));

  /// 404 código inválido; 403 propio/lleno/expirado/ya unido.
  Future<Map<String, dynamic>> joinPickup(String code) =>
      _map(_send('POST', '/pickups/join', body: {'code': code}));

  Future<Map<String, dynamic>> updatePickup(
    String pageId,
    Map<String, dynamic> fields,
  ) =>
      _map(_send('PATCH', '/pickups/$pageId', body: fields));

  /// Solo el creador. El server archiva también el chat asociado.
  Future<void> deletePickup(String pageId) =>
      _send('DELETE', '/pickups/$pageId');

  Future<Map<String, dynamic>> createChat(Map<String, dynamic> chat) =>
      _map(_send('POST', '/chats', body: chat));

  /// Mensajes del chat de un pickup. Con [sinceIso] trae solo los posteriores
  /// (polling incremental). Devuelve {messages: [...]}.
  Future<List<Map<String, dynamic>>> pickupMessages(
    String pickupId, {
    String? sinceIso,
  }) async {
    final res = await _map(_send('GET', '/pickups/$pickupId/messages',
        query: {if (sinceIso != null && sinceIso.isNotEmpty) 'after': sinceIso}));
    return ((res['messages'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
  }

  /// Envía un mensaje al chat del pickup (solo creador/miembros). 403 si no.
  Future<Map<String, dynamic>> sendPickupMessage(String pickupId, String text) =>
      _map(_send('POST', '/pickups/$pickupId/messages', body: {'text': text}));

  /// Sube una imagen de cancha (ya comprimida) a Storage vía multipart.
  /// Devuelve la URL pública. Timeout propio más largo que el de JSON.
  Future<String> uploadCourtImage(String filePath) async {
    final req = http.MultipartRequest(
      'POST',
      _uri('/uploads/court-image'),
    );
    if (hasToken) req.headers['Authorization'] = 'Bearer $_token';
    req.files.add(await http.MultipartFile.fromPath('file', filePath));
    final streamed = await req.send().timeout(const Duration(seconds: 60));
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(
          res.statusCode, _errorMessage(res.body), '/uploads/court-image');
    }
    final data = jsonDecode(res.body) as Map;
    return (data['url'] ?? '').toString();
  }

  // ── Historial de partidos / ranking ────────────────────────────────────

  /// Sube un lote; devuelve {results: [{ok}]} en el mismo orden.
  Future<Map<String, dynamic>> postMatches(
    List<Map<String, dynamic>> matches,
  ) =>
      _map(_send('POST', '/matches', body: {'matches': matches}));

  /// Fechas de fin (ISO) de mis partidos ya registrados en la DB Partidos:
  /// {endedAt: [...]}. Para dedupear el backfill del log local.
  Future<Map<String, dynamic>> myMatches() => _map(_send('GET', '/matches/mine'));

  /// Mis puntos acumulados en una cancha, sumados server-side desde la DB
  /// Partidos: {points, matches}. El email sale del token.
  Future<Map<String, dynamic>> courtPoints(String courtId) =>
      _map(_send('GET', '/matches/court-points', query: {'courtId': courtId}));

  /// Puntos agrupados por email desde `since` (ISO). `emails` máx 100.
  Future<List<Map<String, dynamic>>> ranking({
    required String since,
    required List<String> emails,
  }) =>
      _list(_send('GET', '/matches/ranking', query: {
        'since': since,
        'emails': emails.join(','),
      }));

  // ── Clanes (agrupación por insignia del perfil, server-side) ────────────

  /// Ranking global de clanes. Sin [since] = modo Total (Points del perfil);
  /// con [since] (ISO) suma los partidos del período. [{clan, points, members}]
  Future<List<Map<String, dynamic>>> clanRanking({String? since}) =>
      _list(_send('GET', '/clans/ranking', query: {
        if (since != null && since.isNotEmpty) 'since': since,
      }));

  /// Ranking global del período: {players: top50, clans: top50, me: {...}}.
  /// [since] ISO obligatorio (semana/mes/temporada).
  Future<Map<String, dynamic>> globalRanking(String since) =>
      _map(_send('GET', '/rankings/global', query: {'since': since}));

  /// Clan con más puntos en la cancha esta temporada: {owner: {...} | null}.
  Future<Map<String, dynamic>> clanCourtOwner(String courtId) =>
      _map(_send('GET', '/clans/court-owner', query: {'courtId': courtId}));

  /// Jugador con más puntos en la cancha esta temporada ("rey de la cancha"):
  /// {king: {name, handle, points} | null}.
  Future<Map<String, dynamic>> courtKing(String courtId) =>
      _map(_send('GET', '/matches/court-king', query: {'courtId': courtId}));
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.message, [this.path = '']);
  final int statusCode;
  final String message;
  final String path;

  @override
  String toString() => 'ApiException($path): HTTP $statusCode — $message';
}
