import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models.dart';
import '../notion/notion_config.dart';
import 'friends_service.dart';
import 'notion_service.dart';

/// Estado de sesión del usuario. Maneja signup/login/logout contra Notion
/// (auth prototipo: email + contraseña hasheada SHA-256) y persiste la
/// sesión en SharedPreferences para restaurarla al reabrir la app.
class Session extends ChangeNotifier {
  Session({NotionService? notion}) : _notion = notion ?? NotionService();

  final NotionService _notion;

  static const _kEmail = 'session_email';
  static const _kProfile = 'session_profile';
  // Si el usuario eligió mantener la sesión abierta. Si es false, al reabrir la
  // app la sesión cacheada se descarta y hay que loguearse de nuevo.
  static const _kPersist = 'session_persist';
  // Posición de juego elegida por el usuario. Es puramente local (cosmética):
  // NO se sube a Notion ni se comparte con los amigos.
  static const _kLocalPosition = 'local_position';

  Profile? _profile;
  String? _email;
  String _localPosition = '';
  bool _restoring = true;
  // Hay cambios de perfil (stats, nivel, título, clan, privacidad, tiempo,
  // logros) staged localmente sin subir. El batch los sube juntos en flush().
  bool _dirty = false;
  // Evita flushes concurrentes (timer + lifecycle pueden disparar a la vez).
  bool _flushing = false;

  Profile? get profile => _profile;
  String? get email => _email;
  /// Posición de juego elegida (local, cosmética). '' si no eligió ninguna.
  String get localPosition => _localPosition;
  bool get restoring => _restoring;
  bool get isLoggedIn => _profile != null;
  bool get notionReady => _notion.isConfigured;

  /// True si el usuario está logueado pero todavía no definió su handle
  /// (recién registrado). Fuerza la pantalla de elección de handle.
  bool get needsHandle =>
      _profile != null && (_profile?.handle ?? '').trim().isEmpty;

  /// Hash prototipo (con el email como sal liviana). No es auth de producción.
  static String _hash(String email, String password) =>
      sha256.convert(utf8.encode('${email.toLowerCase()}:$password')).toString();

  /// Restaura la sesión desde el cache local (sin red). Si el usuario no eligió
  /// mantener la sesión abierta, descarta el cache y arranca deslogueado.
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    _localPosition = prefs.getString(_kLocalPosition) ?? '';
    final persist = prefs.getBool(_kPersist) ?? true;
    if (!persist) {
      await prefs.remove(_kEmail);
      await prefs.remove(_kProfile);
      _restoring = false;
      notifyListeners();
      return;
    }
    final em = prefs.getString(_kEmail);
    final cached = prefs.getString(_kProfile);
    if (em != null && cached != null) {
      try {
        _profile = Profile.fromJson(jsonDecode(cached) as Map<String, dynamic>);
        _email = em;
      } catch (_) {/* cache corrupto: ignorar */}
    }
    _restoring = false;
    notifyListeners();
  }

  /// Devuelve null si OK, o un mensaje de error. [persist] indica si la sesión
  /// debe sobrevivir al cierre de la app (checkbox "Mantener sesión abierta").
  Future<String?> login(String emailRaw, String password,
      {bool persist = true}) async {
    if (!_notion.isConfigured) {
      return 'Notion no está configurado (falta el token).';
    }
    final email = emailRaw.trim().toLowerCase();
    if (email.isEmpty || password.isEmpty) return 'Completá email y contraseña.';
    try {
      final rows = await _notion.queryDatabase(
        NotionConfig.dbUsers,
        filter: NotionService.filterTitle('Email', email),
      );
      if (rows.isEmpty) return 'No existe una cuenta con ese email.';
      final user = AppUser.fromNotion(rows.first);
      if (user.passwordHash != _hash(email, password)) {
        return 'Contraseña incorrecta.';
      }
      final profilePage = await _notion.retrievePage(user.profileId);
      await _persist(email, Profile.fromNotion(profilePage));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kPersist, persist);
      return null;
    } on NotionException catch (e) {
      return 'Error conectando con Notion (${e.statusCode}).';
    } catch (e) {
      return 'Error inesperado: $e';
    }
  }

  Future<String?> signup({
    required String emailRaw,
    required String password,
    required String name,
    String city = '',
    String phone = '',
  }) async {
    if (!_notion.isConfigured) {
      return 'Notion no está configurado (falta el token).';
    }
    final email = emailRaw.trim().toLowerCase();
    if (email.isEmpty || password.isEmpty || name.trim().isEmpty) {
      return 'Completá nombre, email y contraseña.';
    }
    if (password.length < 6) return 'La contraseña debe tener al menos 6 caracteres.';
    try {
      final existing = await _notion.queryDatabase(
        NotionConfig.dbUsers,
        filter: NotionService.filterTitle('Email', email),
      );
      if (existing.isNotEmpty) return 'Ya existe una cuenta con ese email.';

      // El handle NO se autogenera: se define después del registro en la
      // pantalla de handle (así evitamos colisiones con uno ya tomado).
      final newProfile = Profile(
        name: name.trim(),
        handle: '',
        city: city.trim(),
        phone: phone.trim(),
        userEmail: email,
      );
      final profilePage = await _notion.createPage(
        NotionConfig.dbProfiles,
        newProfile.toNotionProperties(),
      );
      final profileId = profilePage['id']?.toString() ?? '';

      await _notion.createPage(NotionConfig.dbUsers, {
        'Email': NotionService.title(email),
        'PasswordHash': NotionService.richText(_hash(email, password)),
        'ProfileId': NotionService.richText(profileId),
        'CreatedAt': NotionService.date(DateTime.now().toIso8601String()),
      });

      await _persist(email, Profile.fromNotion(profilePage));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kPersist, true);
      return null;
    } on NotionException catch (e) {
      return 'Error conectando con Notion (${e.statusCode}).';
    } catch (e) {
      return 'Error inesperado: $e';
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
    final rows = await _notion.queryDatabase(
      NotionConfig.dbProfiles,
      filter: NotionService.filterText('Handle', handle),
    );
    return rows.any((r) => (r['id']?.toString() ?? '') != excludePageId);
  }

  /// Define o cambia el handle del usuario actual. Devuelve null si OK, o un
  /// mensaje de error (formato inválido, ya tomado, o error de red).
  Future<String?> setHandle(String rawHandle) async {
    if (!_notion.isConfigured) {
      return 'Notion no está configurado (falta el token).';
    }
    final prof = _profile;
    final email = _email;
    if (prof == null || email == null) return 'No hay sesión activa.';

    final fmtErr = validateHandleFormat(rawHandle);
    if (fmtErr != null) return fmtErr;
    final handle = FriendsService.normalizeHandle(rawHandle);

    if (handle == prof.handle) return null; // sin cambios

    try {
      if (await isHandleTaken(handle, excludePageId: prof.pageId)) {
        return 'Ese handle ya está en uso. Probá con otro.';
      }
      await _notion.updatePage(prof.pageId, {
        'Handle': NotionService.richText(handle),
      });
      await _persist(email, prof.copyWith(handle: handle));
      return null;
    } on NotionException catch (e) {
      return 'Error conectando con Notion (${e.statusCode}).';
    } catch (e) {
      return 'Error inesperado: $e';
    }
  }

  /// Guarda la insignia de clan (hasta 4 caracteres) y el color del avatar
  /// (hex de 6 dígitos, sin '#') en la base Perfiles. Devuelve null si OK o un
  /// mensaje de error.
  Future<String?> setClanBadge({
    required String clan,
    required String color,
    required String textColor,
    required String font,
  }) async {
    final prof = _profile;
    final email = _email;
    if (prof == null || email == null) return 'No hay sesión activa.';

    final c = clan.trim().toUpperCase();
    if (c.length > 4) return 'La insignia no puede superar los 4 caracteres.';

    // Se guarda localmente y se sube en el próximo batch.
    _dirty = true;
    await _persist(
      email,
      prof.copyWith(
        clan: c,
        avatarColor: color,
        clanTextColor: textColor,
        clanFont: font,
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
    _dirty = true;
    await _persist(email, prof.copyWith(title: title));
    return null;
  }

  /// Actualiza las preferencias de privacidad. Se guardan localmente y se suben
  /// en el próximo batch.
  Future<String?> setSharePrefs({
    bool? shareStatus,
    bool? shareCourt,
    bool? shareTime,
  }) async {
    final prof = _profile;
    final email = _email;
    if (prof == null || email == null) return 'No hay sesión activa.';
    _dirty = true;
    await _persist(
      email,
      prof.copyWith(
        shareStatus: shareStatus ?? prof.shareStatus,
        shareCourt: shareCourt ?? prof.shareCourt,
        shareTime: shareTime ?? prof.shareTime,
      ),
    );
    return null;
  }

  /// Actualiza la presencia "jugando" en Notion. Best-effort (no bloquea ni
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
    if (!_notion.isConfigured) return;
    try {
      await _notion.updatePage(_profile!.pageId, {
        'Playing': NotionService.checkbox(playing),
        'PlayingCourtId': NotionService.richText(playing ? courtId : ''),
        'PlayingSince': NotionService.date(sinceIso.isEmpty ? null : sinceIso),
      });
    } catch (_) {
      // Falló la subida inmediata → marcamos dirty para que flush() la reintente
      // cada 2 min (con todo el perfil) hasta que entre.
      _dirty = true;
    }
  }

  /// Define (o limpia, con '') la posición de juego. Es local y cosmética: se
  /// guarda solo en SharedPreferences, no toca Notion ni el batch.
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
    _dirty = true;
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

  /// Sube TODO el perfil a Notion en UNA sola petición, si hay cambios staged.
  /// Lo dispara el batch (cada ~2 min / al pausar / cerrar la app). Junta en una
  /// llamada las stats, el tiempo jugado, los logros, el nivel, el título, el
  /// clan y la privacidad acumulados desde la última subida.
  Future<void> flush() async {
    if (_flushing || !_dirty) return;
    final prof = _profile;
    if (prof == null || !_notion.isConfigured) return;
    _flushing = true;
    try {
      await _notion.updatePage(prof.pageId, prof.toNotionProperties());
      _dirty = false;
    } catch (_) {
      /* sin red: dirty queda en true → se reintenta en el próximo flush */
    } finally {
      _flushing = false;
    }
  }

  Future<void> logout() async {
    await flush(); // subir lo que haya quedado pendiente antes de cerrar
    _dirty = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kEmail);
    await prefs.remove(_kProfile);
    await prefs.remove(_kLocalPosition);
    _profile = null;
    _email = null;
    _localPosition = '';
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
