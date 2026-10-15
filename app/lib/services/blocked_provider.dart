import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lista de usuarios bloqueados por el usuario actual. Se guarda en el
/// dispositivo (SharedPreferences namespaced por usuario, patrón
/// `base::$userKey`) Y se respalda en el servidor (`/sync/data/blocked`), así que
/// sobrevive a reinstalar o cambiar de celular: antes el usuario bloqueado
/// reaparecía. El bloqueo sigue aplicándose SOLO en la UI de este dispositivo —
/// el servidor guarda la lista pero no filtra nada con ella.
///
/// Guardamos emails normalizados (minúsculas, sin espacios).
class BlockedProvider extends ChangeNotifier {
  static const _kBase = 'blocked_users';

  String _userKey = '';
  Set<String> _blocked = {};

  Set<String> get blocked => _blocked;

  String get _key => _userKey.isEmpty ? _kBase : '$_kBase::$_userKey';

  String _norm(String email) => email.trim().toLowerCase();

  bool isBlocked(String email) => _blocked.contains(_norm(email));

  /// Carga la lista del usuario activo (llamar en login / cambio de sesión).
  Future<void> loadForUser(String email) async {
    _userKey = _norm(email);
    final sp = await SharedPreferences.getInstance();
    _blocked = (sp.getStringList(_key) ?? const <String>[]).toSet();
    notifyListeners();
  }

  Future<void> block(String email) async {
    final e = _norm(email);
    if (e.isEmpty || _blocked.contains(e)) return;
    _blocked = {..._blocked, e};
    await _persist();
    notifyListeners();
  }

  /// Une bloqueados traídos del servidor con los locales. Unión: restaurar
  /// nunca desbloquea a nadie. Devuelve true si cambió algo.
  Future<bool> mergeFrom(Iterable<String> remote) async {
    final merged = {..._blocked, ...remote.map(_norm).where((e) => e.isNotEmpty)};
    if (merged.length == _blocked.length) return false;
    _blocked = merged;
    await _persist(local: false);
    notifyListeners();
    return true;
  }

  Future<void> unblock(String email) async {
    final e = _norm(email);
    if (!_blocked.contains(e)) return;
    _blocked = {..._blocked}..remove(e);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist({bool local = true}) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_key, _blocked.toList());
    if (local) await sp.setBool(_dirtyKey, true);
  }

  // Cambiada en el celu y todavía sin subir. Mientras lo esté, el restore NO
  // une con la lista del servidor: un desbloqueo hecho sin conexión se perdería.
  String get _dirtyKey => '${_key}_dirty';

  Future<bool> hasLocalChanges() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_dirtyKey) ?? false;
  }

  /// El servidor ya tiene la lista local.
  Future<void> markSynced() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_dirtyKey);
  }

  void clearForLogout() {
    _userKey = '';
    _blocked = {};
    notifyListeners();
  }
}
