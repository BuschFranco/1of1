import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Favoritos guardados localmente (no en Notion), por court id. Las claves se
/// separan por usuario para que las cuentas no compartan favoritos en el mismo
/// dispositivo.
class FavoritesProvider extends ChangeNotifier {
  // Vacío = sin sesión (clave global). Con sesión, se sufija con el email.
  String _userKey = '';
  String get _key =>
      _userKey.isEmpty ? 'favorite_courts' : 'favorite_courts::$_userKey';
  Set<String> _ids = {};

  Set<String> get ids => _ids;
  bool isFavorite(String courtId) => _ids.contains(courtId);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _ids = (prefs.getStringList(_key) ?? const []).toSet();
    notifyListeners();
  }

  /// Cambia el usuario activo y recarga SUS favoritos.
  Future<void> setUser(String userKey) async {
    if (_userKey == userKey) return;
    _userKey = userKey;
    await load();
  }

  /// Al cerrar sesión: olvida los favoritos en memoria y la namespace.
  void clearForLogout() {
    _userKey = '';
    _ids = {};
    notifyListeners();
  }

  /// Une favoritos traídos del servidor con los locales. Unión: restaurar nunca
  /// quita un favorito. Devuelve true si cambió algo.
  Future<bool> mergeFrom(Iterable<String> remote) async {
    final merged = {..._ids, ...remote.where((e) => e.isNotEmpty)};
    if (merged.length == _ids.length) return false;
    _ids = merged;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _ids.toList());
    return true;
  }

  Future<void> toggle(String courtId) async {
    if (_ids.contains(courtId)) {
      _ids.remove(courtId);
    } else {
      _ids.add(courtId);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _ids.toList());
  }
}
