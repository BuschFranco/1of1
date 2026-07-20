import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models.dart';
import 'api/api_client.dart';
import 'friends_service.dart';

/// Estado de sesión del usuario. Maneja signup/login/logout contra el backend
/// propio (JWT) y persiste la sesión en SharedPreferences para restaurarla al
/// reabrir la app. La contraseña viaja al server, que la hashea y compara —
/// la app ya no conoce el esquema de hash.
class Session extends ChangeNotifier {
  Session({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  static const _kEmail = 'session_email';
  static const _kProfile = 'session_profile';
  // Si el usuario eligió mantener la sesión abierta. Si es false, al reabrir la
  // app la sesión cacheada se descarta y hay que loguearse de nuevo.
  static const _kPersist = 'session_persist';
  // Posición de juego elegida por el usuario. Es puramente local (cosmética):
  // NO se sube a la BD ni se comparte con los amigos.
  static const _kLocalPosition = 'local_position';
  // Color de fondo del perfil elegido por el usuario (clave de
  // AppColors.profileBgs). Local y cosmético, como la posición.
  static const _kProfileBg = 'profile_bg_color';
  static const _kDefaultTab = 'default_start_tab';

  Profile? _profile;
  String? _email;
  String _localPosition = '';
  String _profileBg = '';
  String _defaultTab = 'home';
  bool _restoring = true;
  // Campos del perfil modificados localmente sin subir. El batch los sube
  // juntos en flush(). Usar un Set en vez de bool permite enviar solo los
  // campos que realmente cambiaron (PATCH parcial), reduciendo el payload.
  final Set<String> _dirtyFields = {};
  // Evita flushes concurrentes (timer + lifecycle pueden disparar a la vez).
  bool _flushing = false;

  // True una sola vez tras un login/registro EXPLÍCITO (no en el restore de
  // sesión). La UI lo consume para mostrar el mensaje de bienvenida una vez.
  bool _justAuthenticated = false;
  bool consumeJustAuthenticated() {
    if (!_justAuthenticated) return false;
    _justAuthenticated = false;
    return true;
  }

  Profile? get profile => _profile;
  String? get email => _email;
  /// Posición de juego elegida (local, cosmética). '' si no eligió ninguna.
  String get localPosition => _localPosition;

  /// Clave del fondo de perfil elegido ('' = default). Ver AppColors.profileBgs.
  String get profileBg => _profileBg;
  /// Pestaña de inicio por defecto al abrir la app ('home' = default).
  String get defaultTab => _defaultTab;
  bool get restoring => _restoring;
  bool get isLoggedIn => _profile != null;
  bool get notionReady => _api.isConfigured;
  bool get isAdmin => _profile?.isAdmin ?? false;

  /// True si el usuario está logueado pero todavía no definió su handle
  /// (recién registrado). Fuerza la pantalla de elección de handle.
  bool get needsHandle =>
      _profile != null && (_profile?.handle ?? '').trim().isEmpty;

  /// Mensaje de error legible para una excepción de la API.
  static String _apiError(Object e) {
    if (e is ApiException) {
      if (e.message.isNotEmpty) return e.message;
      return 'Error del servidor (${e.statusCode}).';
    }
    if (e is TimeoutException) return 'No se pudo conectar con el servidor.';
    return 'Error inesperado: $e';
  }

  /// Aplica el flag admin del token al perfil (no viaja en el Profile del
  /// backend: vive en el JWT).
  Profile _withAdmin(Profile p) => p.copyWith(isAdmin: _api.isAdmin);

  /// Procesa la respuesta {token, profile} de /auth/*: guarda el JWT y
  /// persiste la sesión. Devuelve null si OK.
  Future<String?> _acceptAuth(
    Map<String, dynamic> data,
    String email, {
    required bool persist,
  }) async {
    final token = (data['token'] ?? '').toString();
    final profJson = data['profile'];
    if (token.isEmpty || profJson is! Map) {
      return 'Respuesta inválida del servidor.';
    }
    await _api.setToken(token);
    final prof = _withAdmin(
      Profile.fromJson(profJson.cast<String, dynamic>()),
    );
    await _persist(email, prof);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPersist, persist);
    _justAuthenticated = true;
    return null;
  }

  /// Restaura la sesión desde el cache local (sin red). Si el usuario no eligió
  /// mantener la sesión abierta, descarta el cache y arranca deslogueado.
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    _localPosition = prefs.getString(_kLocalPosition) ?? '';
    _profileBg = prefs.getString(_kProfileBg) ?? '';
    _defaultTab = prefs.getString(_kDefaultTab) ?? 'home';
    await _api.loadToken();
    final persist = prefs.getBool(_kPersist) ?? true;
    if (!persist) {
      await prefs.remove(_kEmail);
      await prefs.remove(_kProfile);
      await _api.clearToken();
      _restoring = false;
      notifyListeners();
      return;
    }
    final em = prefs.getString(_kEmail);
    final cached = prefs.getString(_kProfile);
    // Sin JWT no hay sesión contra el backend (p. ej. venir de una versión
    // vieja de la app, o token borrado): forzar login.
    if (em != null && cached != null && _api.hasToken) {
      try {
        _profile = _withAdmin(
          Profile.fromJson(jsonDecode(cached) as Map<String, dynamic>),
        );
        _email = em;
      } catch (_) {/* cache corrupto: ignorar */}
    }
    _restoring = false;
    notifyListeners();
    // Refrescar perfil desde el backend en background para capturar cambios
    // sin bloquear el arranque. Si el token venció, el 401 cierra la sesión.
    if (_profile != null && _api.isConfigured) {
      _refreshProfileFromApi(em!);
    }
  }

  /// Refresca el perfil desde el backend (background, sin bloquear).
  Future<void> _refreshProfileFromApi(String email) async {
    try {
      final json = await _api.me();
      final fresh = _withAdmin(Profile.fromJson(json));
      // Nunca pisar el cache bueno con un perfil vacío/malformado.
      if (fresh.pageId.isEmpty) return;
      if (_email == email) {
        _profile = fresh;
        await _persist(email, fresh);
        notifyListeners();
      }
    } on ApiException catch (e) {
      // Token vencido o cuenta eliminada: la única salida es re-loguear.
      if (e.statusCode == 401 && _email == email) {
        await logout(flushFirst: false);
      }
    } catch (_) {/* sin red: seguir con el cache */}
  }

  /// Devuelve null si OK, o un mensaje de error. [persist] indica si la sesión
  /// debe sobrevivir al cierre de la app (checkbox "Mantener sesión abierta").
  Future<String?> login(String emailRaw, String password,
      {bool persist = true}) async {
    if (!_api.isConfigured) {
      return 'El servidor no está configurado (falta API_BASE_URL).';
    }
    final email = emailRaw.trim().toLowerCase();
    if (email.isEmpty || password.isEmpty) return 'Completá email y contraseña.';
    try {
      final data = await _api.login(email, password);
      return await _acceptAuth(data, email, persist: persist);
    } on ApiException catch (e) {
      if (e.statusCode == 401) return 'Email o contraseña incorrectos.';
      return _apiError(e);
    } catch (e) {
      return _apiError(e);
    }
  }

  Future<String?> signup({
    required String emailRaw,
    required String password,
    required String name,
    String city = '',
    String phone = '',
    String birthdate = '',
  }) async {
    if (!_api.isConfigured) {
      return 'El servidor no está configurado (falta API_BASE_URL).';
    }
    final email = emailRaw.trim().toLowerCase();
    if (email.isEmpty || password.isEmpty || name.trim().isEmpty) {
      return 'Completá nombre, email y contraseña.';
    }
    if (password.length < 6) return 'La contraseña debe tener al menos 6 caracteres.';
    try {
      final data = await _api.register(
        email: email,
        password: password,
        name: name.trim(),
        city: city.trim(),
        phone: phone.trim(),
        birthdate: birthdate,
      );
      return await _acceptAuth(data, email, persist: true);
    } on ApiException catch (e) {
      if (e.statusCode == 409) return 'Ya existe una cuenta con ese email.';
      return _apiError(e);
    } catch (e) {
      return _apiError(e);
    }
  }

  /// Login o registro con Google. Recibe el idToken de Google Sign-In; el
  /// backend lo verifica server-side y hace find-or-create (PasswordHash
  /// "google:"). La app ya no confía en el email del cliente.
  Future<String?> googleSignIn({required String idToken}) async {
    if (!_api.isConfigured) {
      return 'El servidor no está configurado (falta API_BASE_URL).';
    }
    if (idToken.isEmpty) return 'No se pudo autenticar con Google.';
    try {
      final data = await _api.googleLogin(idToken);
      final email =
          ((data['profile'] as Map?)?['userEmail'] ?? '').toString().trim().toLowerCase();
      if (email.isEmpty) return 'No se pudo obtener el email de Google.';
      return await _acceptAuth(data, email, persist: true);
    } on ApiException catch (e) {
      if (e.statusCode == 401) return 'No se pudo validar la cuenta de Google.';
      return _apiError(e);
    } catch (e) {
      return _apiError(e);
    }
  }

  /// Valida el formato del handle. Devuelve un mensaje de error o null si es OK.
  static String? validateHandleFormat(String rawHandle) {
    final h = FriendsService.normalizeHandle(rawHandle);
    final body = h.startsWith('@') ? h.substring(1) : h;
    if (body.isEmpty) return 'Ingresá un handle.';
    if (body.length < 3) return 'El handle debe tener al menos 3 caracteres.';
    if (body.length > 20) return 'El handle no puede superar los 20 caracteres.';
    if (!RegExp(r'^[a-z0-9._]+$').hasMatch(body)) {
      return 'Solo letras, números, punto (.) o guion bajo (_).';
    }
    return null;
  }

  /// Indica si un handle ya está tomado por OTRO perfil (excluye el propio).
  Future<bool> isHandleTaken(String rawHandle, {String? excludePageId}) async {
    final handle = FriendsService.normalizeHandle(rawHandle);
    try {
      final json = await _api.profileByHandle(handle);
      return (json['pageId']?.toString() ?? '') != excludePageId;
    } on ApiException catch (e) {
      if (e.statusCode == 404) return false; // libre
      rethrow;
    }
  }

  /// Define o cambia el handle del usuario actual. Devuelve null si OK, o un
  /// mensaje de error (formato inválido, ya tomado, o error de red).
  Future<String?> setHandle(String rawHandle) async {
    if (!_api.isConfigured) {
      return 'El servidor no está configurado (falta API_BASE_URL).';
    }
    final prof = _profile;
    final email = _email;
    if (prof == null || email == null) return 'No hay sesión activa.';

    final fmtErr = validateHandleFormat(rawHandle);
    if (fmtErr != null) return fmtErr;
    final handle = FriendsService.normalizeHandle(rawHandle);

    if (handle == prof.handle) return null; // sin cambios

    try {
      // El server valida formato y unicidad; el copyWith local evita esperar
      // el próximo refresh para ver el handle nuevo.
      await _api.setHandle(handle);
      await _persist(email, prof.copyWith(handle: handle));
      return null;
    } on ApiException catch (e) {
      if (e.statusCode == 409) return 'Ese handle ya está en uso. Probá con otro.';
      return _apiError(e);
    } catch (e) {
      return _apiError(e);
    }
  }

  /// Guarda la insignia de clan (hasta 4 caracteres) y el color del avatar
  /// (hex de 6 dígitos, sin '#'). Devuelve null si OK o un mensaje de error.
  Future<String?> setClanBadge({
    required String clan,
    required String color,
    required String textColor,
    required String font,
    String? frame,
  }) async {
    final prof = _profile;
    final email = _email;
    if (prof == null || email == null) return 'No hay sesión activa.';

    final c = clan.trim().toUpperCase();
    if (c.length > 4) return 'La insignia no puede superar los 4 caracteres.';

    // Se guarda localmente y se sube en el próximo batch.
    _dirtyFields.addAll(['clan', 'avatarColor', 'clanTextColor', 'clanFont', 'avatarFrame']);
    await _persist(
      email,
      prof.copyWith(
        clan: c,
        avatarColor: color,
        clanTextColor: textColor,
        clanFont: font,
        avatarFrame: frame ?? prof.avatarFrame,
      ),
    );
    return null;
  }

  /// Equipa (o saca, si es vacío) el título visible bajo el nombre. Se guarda
  /// localmente y se sube en el próximo batch.
  Future<String?> setTitle(String title) async {
    final prof = _profile;
    final email = _email;
    if (prof == null || email == null) return 'No hay sesión activa.';
    _dirtyFields.add('title');
    await _persist(email, prof.copyWith(title: title));
    return null;
  }

  /// Actualiza las preferencias de privacidad. Se guardan localmente y se suben
  /// en el próximo batch.
  Future<String?> setSharePrefs({
    bool? shareStatus,
    bool? shareCourt,
    bool? shareTime,
    bool? showLastPlayed,
  }) async {
    final prof = _profile;
    final email = _email;
    if (prof == null || email == null) return 'No hay sesión activa.';
    if (shareStatus != null) _dirtyFields.add('shareStatus');
    if (shareCourt != null) _dirtyFields.add('shareCourt');
    if (shareTime != null) _dirtyFields.add('shareTime');
    if (showLastPlayed != null) _dirtyFields.add('showLastPlayed');
    await _persist(
      email,
      prof.copyWith(
        shareStatus: shareStatus ?? prof.shareStatus,
        shareCourt: shareCourt ?? prof.shareCourt,
        shareTime: shareTime ?? prof.shareTime,
        showLastPlayed: showLastPlayed ?? prof.showLastPlayed,
      ),
    );
    return null;
  }

  /// Registra el último partido jugado (cancha + momento) para mostrarlo a los
  /// amigos cuando el usuario no está jugando. Se guarda local y se sube en el
  /// próximo batch (sin escritura inmediata extra).
  Future<void> setLastPlayed({
    required String courtId,
    required DateTime at,
  }) async {
    final prof = _profile;
    final email = _email;
    if (prof == null || email == null) return;
    _dirtyFields.addAll(['lastPlayedCourtId', 'lastPlayedAt']);
    await _persist(
      email,
      prof.copyWith(
        lastPlayedCourtId: courtId,
        lastPlayedAt: at.toIso8601String(),
      ),
    );
  }

  /// Actualiza la presencia "jugando" en el backend. Best-effort (no bloquea ni
  /// muestra error): lo dispara el detector automático de partido.
  Future<void> setPresence({
    required bool playing,
    String courtId = '',
    DateTime? since,
  }) async {
    final prof = _profile;
    final email = _email;
    if (prof == null || email == null) return;
    final sinceIso = playing && since != null ? since.toIso8601String() : '';
    // Actualizamos el caché primero (estado intencional) para que la UI ya lo
    // refleje y, si la subida falla, el batch tenga qué reintentar.
    await _persist(
      email,
      prof.copyWith(
        playing: playing,
        playingCourtId: playing ? courtId : '',
        playingSince: sinceIso,
      ),
    );
    if (!_api.isConfigured || !_api.hasToken) return;
    try {
      await _api.setPresence(
        playing: playing,
        courtId: playing ? courtId : '',
        since: sinceIso.isEmpty ? null : sinceIso,
      );
    } catch (_) {
      // Falló la subida inmediata → marcamos dirty para que flush() la reintente
      // cada 2 min (solo los campos de presencia) hasta que entre.
      _dirtyFields.addAll(['playing', 'playingCourtId', 'playingSince']);
    }
  }

  /// Define (o limpia, con '') la posición de juego. Es local y cosmética: se
  /// guarda solo en SharedPreferences, no toca la BD ni el batch.
  Future<void> setLocalPosition(String position) async {
    _localPosition = position;
    final prefs = await SharedPreferences.getInstance();
    if (position.isEmpty) {
      await prefs.remove(_kLocalPosition);
    } else {
      await prefs.setString(_kLocalPosition, position);
    }
    notifyListeners();
  }

  /// Define (o limpia, con '') el fondo del perfil. Local y cosmético: se
  /// guarda solo en SharedPreferences, no toca la BD ni el batch.
  Future<void> setProfileBg(String key) async {
    _profileBg = key;
    final prefs = await SharedPreferences.getInstance();
    if (key.isEmpty) {
      await prefs.remove(_kProfileBg);
    } else {
      await prefs.setString(_kProfileBg, key);
    }
    notifyListeners();
  }

  /// Define la pestaña de inicio por defecto al abrir la app.
  Future<void> setDefaultTab(String tab) async {
    _defaultTab = tab;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDefaultTab, tab);
    notifyListeners();
  }

  /// "Stagea" los agregados de juego en el perfil local y los marca para subir.
  /// NO pega a la red: el envío real lo hace [flush] en el próximo batch. Si los
  /// valores no cambiaron, no marca nada (evita peticiones inútiles).
  Future<void> stageStats({
    required int games,
    required int courts,
    required int streak,
    required int points,
    required String level,
    required List<String> unlockedBadges,
    required int playSeconds,
    required String playTimeByCourt,
  }) async {
    final prof = _profile;
    final email = _email;
    if (prof == null || email == null) return;
    final unchanged = prof.games == games &&
        prof.courts == courts &&
        prof.streak == streak &&
        prof.points == points &&
        prof.level == level &&
        prof.playSeconds == playSeconds &&
        prof.playTimeByCourt == playTimeByCourt &&
        listEquals(prof.unlockedBadges, unlockedBadges);
    if (unchanged) return;
    _dirtyFields.addAll([
      'games', 'courts', 'streak', 'points', 'level',
      'unlockedBadges', 'playSeconds', 'playTimeByCourt',
    ]);
    await _persist(
      email,
      prof.copyWith(
        games: games,
        courts: courts,
        streak: streak,
        points: points,
        level: level,
        unlockedBadges: unlockedBadges,
        playSeconds: playSeconds,
        playTimeByCourt: playTimeByCourt,
      ),
    );
  }

  /// Sube SOLO los campos modificados al backend en UNA sola petición, si hay
  /// cambios staged. Lo dispara el batch (cada ~2 min / al pausar / cerrar la
  /// app). Junta en una llamada las stats, el tiempo jugado, los logros, el
  /// nivel, el título, el clan y la privacidad acumulados desde la última subida.
  Future<void> flush() async {
    if (_flushing || _dirtyFields.isEmpty) return;
    final prof = _profile;
    if (prof == null || !_api.isConfigured || !_api.hasToken) return;
    _flushing = true;
    try {
      // Enviar solo los campos que cambiaron (PATCH parcial).
      final patch = <String, dynamic>{};
      final json = prof.toJson();
      for (final field in _dirtyFields) {
        if (json.containsKey(field)) patch[field] = json[field];
      }
      if (patch.isNotEmpty) {
        await _api.updateMe(patch);
      }
      _dirtyFields.clear();
    } catch (_) {
      /* sin red: dirtyFields queda intacto → se reintenta en el próximo flush */
    } finally {
      _flushing = false;
    }
  }

  /// Elimina la cuenta y todos los datos personales del usuario (derecho de
  /// supresión — Ley 25.326 art. 16 / CCPA; requisito de tiendas). El backend
  /// archiva usuario, perfil, partidos, reseñas, amistades y pickups creados.
  /// Luego limpia la sesión local (aunque el server haya devuelto error parcial).
  Future<String?> deleteAccount() async {
    final prof = _profile;
    final email = _email;
    if (prof == null || email == null) return 'No hay sesión activa.';
    if (!_api.isConfigured) return 'No se puede eliminar sin conexión.';

    String? firstError;
    // Cortamos el batch para que no re-suba el perfil que vamos a borrar.
    _dirtyFields.clear();
    try {
      await _api.deleteMe();
    } catch (e) {
      firstError = _apiError(e);
    }

    // Limpiar la sesión local (sin flush: la cuenta ya no existe).
    await _api.clearToken();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kEmail);
    await prefs.remove(_kProfile);
    await prefs.remove(_kLocalPosition);
    await prefs.remove(_kProfileBg);
    await prefs.remove(_kDefaultTab);
    _profile = null;
    _email = null;
    _localPosition = '';
    _profileBg = '';
    _defaultTab = 'home';
    notifyListeners();
    return firstError;
  }

  Future<void> logout({bool flushFirst = true}) async {
    if (flushFirst) {
      await flush(); // subir lo que haya quedado pendiente antes de cerrar
    }
    _dirtyFields.clear();
    await _api.clearToken();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kEmail);
    await prefs.remove(_kProfile);
    await prefs.remove(_kLocalPosition);
    await prefs.remove(_kProfileBg);
    await prefs.remove(_kDefaultTab);
    _profile = null;
    _email = null;
    _localPosition = '';
    _profileBg = '';
    _defaultTab = 'home';
    notifyListeners();
  }

  Future<void> _persist(String email, Profile prof) async {
    _email = email;
    _profile = prof;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kEmail, email);
    await prefs.setString(_kProfile, jsonEncode(prof.toJson()));
    notifyListeners();
  }
}
