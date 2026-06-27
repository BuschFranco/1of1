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

  Profile? _profile;
  String? _email;
  bool _restoring = true;

  Profile? get profile => _profile;
  String? get email => _email;
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

  /// Restaura la sesión desde el cache local (sin red).
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
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

  /// Devuelve null si OK, o un mensaje de error.
  Future<String?> login(String emailRaw, String password) async {
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
    if (!_notion.isConfigured) {
      return 'Notion no está configurado (falta el token).';
    }
    final prof = _profile;
    final email = _email;
    if (prof == null || email == null) return 'No hay sesión activa.';

    final c = clan.trim().toUpperCase();
    if (c.length > 4) return 'La insignia no puede superar los 4 caracteres.';

    try {
      await _notion.updatePage(prof.pageId, {
        'Clan': NotionService.richText(c),
        'AvatarColor': NotionService.richText(color),
        'ClanTextColor': NotionService.richText(textColor),
        'ClanFont': NotionService.richText(font),
      });
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
    } on NotionException catch (e) {
      return 'Error conectando con Notion (${e.statusCode}).';
    } catch (e) {
      return 'Error inesperado: $e';
    }
  }

  /// Actualiza el nivel del jugador en Notion (best-effort) para que lo vean
  /// los amigos. Lo dispara el sistema de puntos al subir de nivel.
  Future<void> setLevel(String level) async {
    final prof = _profile;
    final email = _email;
    if (prof == null || email == null || !_notion.isConfigured) return;
    if (prof.level == level) return;
    try {
      await _notion.updatePage(prof.pageId, {
        'Level': NotionService.richText(level),
      });
      await _persist(email, prof.copyWith(level: level));
    } catch (_) {/* se reintenta al próximo cambio de nivel */}
  }

  /// Equipa (o saca, si es vacío) el título visible bajo el nombre. Se guarda
  /// en Notion para que los amigos lo vean.
  Future<String?> setTitle(String title) async {
    final prof = _profile;
    final email = _email;
    if (prof == null || email == null) return 'No hay sesión activa.';
    if (!_notion.isConfigured) return 'Notion no está configurado.';
    try {
      await _notion.updatePage(prof.pageId, {
        'EquippedTitle': NotionService.richText(title),
      });
      await _persist(email, prof.copyWith(title: title));
      return null;
    } on NotionException catch (e) {
      return 'Error conectando con Notion (${e.statusCode}).';
    } catch (e) {
      return 'Error inesperado: $e';
    }
  }

  /// Actualiza las preferencias de privacidad (qué comparte con sus amigos).
  Future<String?> setSharePrefs({
    bool? shareStatus,
    bool? shareCourt,
    bool? shareTime,
  }) async {
    final prof = _profile;
    final email = _email;
    if (prof == null || email == null) return 'No hay sesión activa.';
    if (!_notion.isConfigured) return 'Notion no está configurado.';
    try {
      await _notion.updatePage(prof.pageId, {
        if (shareStatus != null) 'ShareStatus': NotionService.checkbox(shareStatus),
        if (shareCourt != null) 'ShareCourt': NotionService.checkbox(shareCourt),
        if (shareTime != null) 'ShareTime': NotionService.checkbox(shareTime),
      });
      await _persist(
        email,
        prof.copyWith(
          shareStatus: shareStatus,
          shareCourt: shareCourt,
          shareTime: shareTime,
        ),
      );
      return null;
    } on NotionException catch (e) {
      return 'Error conectando con Notion (${e.statusCode}).';
    } catch (e) {
      return 'Error inesperado: $e';
    }
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
    if (prof == null || email == null || !_notion.isConfigured) return;
    final sinceIso = playing && since != null ? since.toIso8601String() : '';
    try {
      await _notion.updatePage(prof.pageId, {
        'Playing': NotionService.checkbox(playing),
        'PlayingCourtId': NotionService.richText(playing ? courtId : ''),
        'PlayingSince': NotionService.date(sinceIso.isEmpty ? null : sinceIso),
      });
      await _persist(
        email,
        prof.copyWith(
          playing: playing,
          playingCourtId: playing ? courtId : '',
          playingSince: sinceIso,
        ),
      );
    } catch (_) {/* sin red: se reintenta en el próximo cambio de estado */}
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kEmail);
    await prefs.remove(_kProfile);
    _profile = null;
    _email = null;
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
