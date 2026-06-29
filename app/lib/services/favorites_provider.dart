import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Favoritos guardados localmente (no en Notion), por court id.
class FavoritesProvider extends ChangeNotifier {
  static const _key = 'favorite_courts';
  Set<String> _ids = {};

  Set<String> get ids => _ids;
  bool isFavorite(String courtId) => _ids.contains(courtId);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _ids = (prefs.getStringList(_key) ?? const []).toSet();
    notifyListeners();
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
