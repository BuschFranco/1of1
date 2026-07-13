import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lista de usuarios bloqueados por el usuario actual. Es LOCAL al dispositivo
/// (SharedPreferences namespaced por usuario, patrón `base::$userKey`): sin
/// backend propio no tenemos dónde guardarla de forma compartida, pero alcanza
/// para el requisito de tiendas de "poder bloquear a otros usuarios" —
/// el contenido de los bloqueados se oculta en la UI de este dispositivo.
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

  Future<void> unblock(String email) async {
    final e = _norm(email);
    if (!_blocked.contains(e)) return;
    _blocked = {..._blocked}..remove(e);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_key, _blocked.toList());
  }

  void clearForLogout() {
    _userKey = '';
    _blocked = {};
    notifyListeners();
  }
}
