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
  // Hay cambios de perfil (stats, nivel, título, clan, privacidad, tiempo,
  // logros) staged localmente sin subir. El batch los sube juntos en flush().
  bool _dirty = false;
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
  /// Pestaña de inicio elegida ('home' = default). Ver AppTab.
  String get defaultTab => _defaultTab;
  bool get restoring => _restoring;
  bool get isLoggedIn => _profile != null;
  bool get notionReady => _notion.isConfigured;
  bool get isAdmin => _profile?.isAdmin ?? false;

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
    _profileBg = prefs.getString(_kProfileBg) ?? '';
    _defaultTab = prefs.getString(_kDefaultTab) ?? 'home';
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
    // Refrescar perfil desde Notion en background para capturar cambios
    // (como el campo isAdmin) sin bloquear el arranque.
    if (_profile != null && _notion.isConfigured) {
      _refreshProfileFromNotion(em!);
    }
  }

  /// Refresca el perfil desde Notion (background, sin bloquear).
  Future<void> _refreshProfileFromNotion(String email) async {
    try {
      final rows = await _notion.queryDatabase(
        NotionConfig.dbUsers,
        filter: NotionService.filterTitle('Email', email),
      );
      if (rows.isEmpty) return;
      final user = AppUser.fromNotion(rows.first);
      final profilePage = await _notion.retrievePage(user.profileId);
      final fresh = Profile.fromNotion(profilePage).copyWith(isAdmin: user.isAdmin);
      if (_email == email) {
        _profile = fresh;
        await _persist(email, fresh);
        notifyListeners();
      }
    } catch (_) {}
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
      await _persist(email, Profile.fromNotion(profilePage).copyWith(isAdmin: user.isAdmin));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kPersist, persist);
      _justAuthenticated = true;
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
    String birthdate = '',
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
        birthdate: birthdate,
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
      _justAuthenticated = true;
      return null;
    } on NotionException catch (e) {
      return 'Error conectando con Notion (${e.statusCode}).';
    } catch (e) {
      return 'Error inesperado: $e';
    }
  }

  /// Login o registro con Google. Recibe los datos del usuario de Google
  /// (email, nombre, foto). Si el email ya existe en dbUsers, hace login.
  /// Si no, crea User + Profile y loguea. PasswordHash se marca como
  /// "google:" para diferenciar de contraseñas manuales.
  Future<String?> googleSignIn({
    required String email,
    required String name,
    String avatarUrl = '',
  }) async {
    if (!_notion.isConfigured) {
      return 'Notion no está configurado (falta el token).';
    }
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty) return 'No se pudo obtener el email de Google.';
    try {
      // 1) Buscar si ya existe el usuario en dbUsers.
      final existing = await _notion.queryDatabase(
        NotionConfig.dbUsers,
        filter: NotionService.filterTitle('Email', cleanEmail),
      );

      if (existing.isNotEmpty) {
        // Ya tiene cuenta: login directo.
        final user = AppUser.fromNotion(existing.first);
        final profilePage = await _notion.retrievePage(user.profileId);
        await _persist(cleanEmail, Profile.fromNotion(profilePage).copyWith(isAdmin: user.isAdmin));
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_kPersist, true);
        _justAuthenticated = true;
        return null;
      }

      // 2) Usuario nuevo: crear Profile.
      final newProfile = Profile(
        name: name.trim(),
        handle: '',
        avatar: avatarUrl,
        userEmail: cleanEmail,
      );
      final profilePage = await _notion.createPage(
        NotionConfig.dbProfiles,
        newProfile.toNotionProperties(),
      );
      final profileId = profilePage['id']?.toString() ?? '';

      // 3) Crear User en dbUsers con passwordHash = "google:".
      await _notion.createPage(NotionConfig.dbUsers, {
        'Email': NotionService.title(cleanEmail),
        'PasswordHash': NotionService.richText('google:'),
        'ProfileId': NotionService.richText(profileId),
        'CreatedAt': NotionService.date(DateTime.now().toIso8601String()),
      });

      // 4) Persistir y notificar.
      await _persist(cleanEmail, Profile.fromNotion(profilePage));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kPersist, true);
      _justAuthenticated = true;
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
    String? frame,
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
    bool? showLastPlayed,
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
    _dirty = true;
    await _persist(
      email,
      prof.copyWith(
        lastPlayedCourtId: courtId,
        lastPlayedAt: at.toIso8601String(),
      ),
    );
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

  /// Define (o limpia, con '') el fondo del perfil. Local y cosmético: se
  /// guarda solo en SharedPreferences, no toca Notion ni el batch.
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

  /// Elimina la cuenta y todos los datos personales del usuario en Notion
  /// (derecho de supresión — Ley 25.326 art. 16 / CCPA; requisito de tiendas).
  /// Archiva: la fila de Usuarios, el Perfil, y sus filas en Partidos, Reseñas,
  /// Amistades (como owner) y Pickups creados. Luego limpia la sesión local.
  /// Best-effort por colección: si una falla, sigue con las demás y devuelve el
  /// error para informarlo, pero igual cierra la sesión local.
  Future<String?> deleteAccount() async {
    final prof = _profile;
    final email = _email;
    if (prof == null || email == null) return 'No hay sesión activa.';
    if (!_notion.isConfigured) return 'No se puede eliminar sin conexión.';

    String? firstError;
    Future<void> archiveWhere(String db, Map<String, dynamic> filter) async {
      if (db.isEmpty) return;
      try {
        final rows = await _notion.queryDatabaseAll(db, filter: filter);
        for (final r in rows) {
          final id = r['id']?.toString();
          if (id != null) await _notion.archivePage(id);
        }
      } catch (e) {
        firstError ??= e.toString();
      }
    }

    // Cortamos el batch para que no re-suba el perfil que vamos a borrar.
    _dirty = false;

    // Historial de partidos (title = Email), reseñas y amistades (rich_text),
    // pickups creados por el usuario.
    await archiveWhere(NotionConfig.dbMatches,
        NotionService.filterTitle('Email', email));
    await archiveWhere(NotionConfig.dbReviews,
        NotionService.filterText('UserEmail', email));
    await archiveWhere(NotionConfig.dbFriends,
        NotionService.filterText('OwnerEmail', email));
    await archiveWhere(NotionConfig.dbPickups,
        NotionService.filterText('CreatedBy', email));

    // Perfil y credenciales.
    try {
      if (prof.pageId.isNotEmpty) await _notion.archivePage(prof.pageId);
    } catch (e) {
      firstError ??= e.toString();
    }
    await archiveWhere(NotionConfig.dbUsers,
        NotionService.filterTitle('Email', email));

    // Limpiar la sesión local (sin flush: la cuenta ya no existe).
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

  Future<void> logout() async {
    await flush(); // subir lo que haya quedado pendiente antes de cerrar
    _dirty = false;
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
