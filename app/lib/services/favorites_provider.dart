import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'analytics_service.dart';

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
    final adding = !_ids.contains(courtId);
    if (adding) {
      _ids.add(courtId);
    } else {
      _ids.remove(courtId);
    }
    AnalyticsService.event('favorite_toggle', {
      'court_id': courtId,
      'action': adding ? 'add' : 'remove',
    });
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _ids.toList());
    await prefs.setBool(_dirtyKey, true);
  }

  // Cambiada en el celu y todavía sin subir. Mientras lo esté, el restore NO
  // une con la lista del servidor: un favorito quitado sin conexión volvería.
  String get _dirtyKey => '${_key}_dirty';

  Future<bool> hasLocalChanges() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_dirtyKey) ?? false;
  }

  /// El servidor ya tiene la lista local.
  Future<void> markSynced() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dirtyKey);
  }
}
