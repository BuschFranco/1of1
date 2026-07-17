import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/courts.dart';
import 'api/api_client.dart';

/// Fuente de canchas para la app. Carga desde el backend.
/// Si no hay API configurada o falla, la lista queda vacía.
class CourtsProvider extends ChangeNotifier {
  CourtsProvider({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  List<Court> _courts = [];
  bool _loading = false;
  bool _fromNotion = false;

  List<Court> get courts => _courts;
  bool get loading => _loading;
  /// True si la lista viene de la BD real (no del fallback vacío).
  bool get fromNotion => _fromNotion;

  Future<void> load() async {
    if (!_api.isConfigured || !_api.hasToken) {
      _courts = [];
      _fromNotion = false;
      notifyListeners();
      return;
    }
    _loading = true;
    notifyListeners();
    try {
      // GET /courts ya devuelve solo las aprobadas.
      final rows = await _api.courts();
      _courts = rows.map(Court.fromApi).toList();
      _fromNotion = true;
    } catch (_) {
      _courts = [];
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Propone una cancha nueva (entra "Sin definir", pendiente de moderación).
  /// No aparece en la app hasta que un admin la apruebe. El autor sale del
  /// token en el server; [createdByEmail] se usa solo para sembrar el estado
  /// local de notificaciones.
  Future<void> addCourt(
    Court court, {
    String? createdBy,
    String? createdByClan,
    String? createdByEmail,
  }) async {
    final created = await _api.proposeCourt(court.toApiJson());
    // Sembramos el estado "pendiente" en el mapa persistido para no perder la
    // PRIMERA aprobación: si no registráramos el pendiente, al detectarla luego
    // se tomaría como "primera observación" y no dispararía la notificación.
    final id = created['id']?.toString() ?? '';
    final email = (createdByEmail ?? '').trim().toLowerCase();
    if (id.isNotEmpty && email.isNotEmpty) {
      final states = await _readCourtStates(email);
      states[id] = CourtApproval.pending;
      await _writeCourtStates(email, states);
    }
    await load();
  }

  /// Elimina una cancha (y sus reseñas, server-side). Solo admin: el backend
  /// devuelve 403 si el token no lo es.
  Future<void> deleteCourt(String courtId) async {
    await _api.deleteCourt(courtId);
    await load();
  }

  // ── Notificación de decisión (aprobada/rechazada) sobre canchas propias ──
  //
  // No hay canal push entre usuarios: al abrir la app comparamos el estado
  // actual de las canchas creadas por el usuario contra el último conocido
  // (persistido, namespaced por usuario) y avisamos los cambios nuevos.

  String _statesKey(String email) => 'notified_court_states::$email';

  Future<Map<String, String>> _readCourtStates(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_statesKey(email));
      if (raw == null) return {};
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeCourtStates(String email, Map<String, String> s) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_statesKey(email), jsonEncode(s));
    } catch (_) {}
  }

  /// Revisa las canchas creadas por [email] y devuelve las que cambiaron a
  /// aprobada/rechazada desde la última vez. Solo avisa cuando había un estado
  /// previo distinto: la primera observación se registra en silencio (evita
  /// spam de canchas viejas ya resueltas, p. ej. tras reinstalar).
  Future<List<({String name, bool approved})>> pollMyCourtDecisions(
      String email) async {
    final e = email.trim().toLowerCase();
    if (e.isEmpty || !_api.isConfigured || !_api.hasToken) return const [];
    List<Court> mine;
    try {
      // GET /courts/mine trae las propias en TODOS los estados.
      final rows = await _api.myCourts();
      mine = rows.map(Court.fromApi).toList();
    } catch (_) {
      return const [];
    }
    final states = await _readCourtStates(e);
    final decisions = <({String name, bool approved})>[];
    var changed = false;
    for (final c in mine) {
      if (c.id.isEmpty) continue;
      final cur = c.approval;
      final prev = states[c.id];
      if (prev != null &&
          prev != cur &&
          (cur == CourtApproval.approved || cur == CourtApproval.rejected)) {
        decisions.add((name: c.name, approved: cur == CourtApproval.approved));
      }
      if (prev != cur) {
        states[c.id] = cur;
        changed = true;
      }
    }
    if (changed) await _writeCourtStates(e, states);
    return decisions;
  }
}
