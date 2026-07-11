import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models.dart';

/// Servicio de chats locales para pickup games.
/// Los chats se guardan en SharedPreferences y se eliminan automáticamente
/// 24 horas después de la fecha del pickup.
///
/// La clave está namespaced por usuario (`local_pickup_chats::$userKey`) para
/// no filtrar chats entre cuentas logueadas en el mismo dispositivo (ver
/// CLAUDE.md §6). Se instancia con el email del usuario activo.
class LocalChatService {
  static const _kChats = 'local_pickup_chats';
  static const _expiryHours = 24;

  /// userKey = email en minúsculas y sin espacios (mismo criterio que el resto
  /// del estado local). Vacío = clave global (fallback sin sesión).
  final String _userKey;

  LocalChatService([String? userEmail])
      : _userKey = (userEmail ?? '').trim().toLowerCase();

  String get _key => _userKey.isEmpty ? _kChats : '$_kChats::$_userKey';

  /// Obtiene todos los chats locales no expirados.
  Future<List<CrewChat>> getChats() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getStringList(_key) ?? [];
    final now = DateTime.now();
    final valid = <CrewChat>[];
    final validJson = <String>[];

    for (final json in raw) {
      try {
        final map = jsonDecode(json) as Map<String, dynamic>;
        final chat = CrewChat.fromJson(map);
        // Verificar expiración: 24h después de la fecha del pickup.
        final pickupDate = DateTime.tryParse(chat.date);
        if (pickupDate != null &&
            now.isAfter(pickupDate.add(Duration(hours: _expiryHours)))) {
          continue; // Expirado, no incluir.
        }
        valid.add(chat);
        validJson.add(json);
      } catch (_) {
        // Corrupto, descartar.
      }
    }

    // Re-guardar sin los expirados.
    if (validJson.length != raw.length) {
      await sp.setStringList(_key, validJson);
    }

    return valid;
  }

  /// Guarda un nuevo chat local.
  Future<void> saveChat(CrewChat chat) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getStringList(_key) ?? [];
    raw.add(jsonEncode(chat.toJson()));
    await sp.setStringList(_key, raw);
  }

  /// Elimina un chat por pickupId.
  Future<void> deleteChat(String pickupId) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getStringList(_key) ?? [];
    final filtered = raw.where((json) {
      try {
        final map = jsonDecode(json) as Map<String, dynamic>;
        return map['pickupId'] != pickupId;
      } catch (_) {
        return true;
      }
    }).toList();
    await sp.setStringList(_key, filtered);
  }
}
