import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/courts.dart';
import 'analytics_service.dart';
import 'api/api_client.dart';

/// Fuente de canchas para la app. Carga desde el backend y guarda una copia en
/// el celu (`courts_cache`): sin red (modo offline) el mapa, la lista y la
/// detección de sesiones siguen funcionando con el último catálogo conocido.
class CourtsProvider extends ChangeNotifier {
  CourtsProvider({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  /// Global, no por usuario: las canchas aprobadas son las mismas para todos.
  static const _kCache = 'courts_cache';
  // Versionada: subir el sufijo cuando el catálogo trae un campo nuevo, así la
  // copia vieja (sin ese campo) no se toma por fresca y se vuelve a pedir.
  // v2: `proposedByAdmin`.
  static const _kCacheAt = 'courts_cache_at_v2';

  /// Con una copia más nueva que esto no se vuelve a pedir `GET /courts` (el
  /// catálogo cambia solo cuando un admin aprueba una cancha). Reconectar,
  /// agregar o borrar una cancha fuerzan la recarga.
  static const _kTtl = Duration(hours: 6);

  List<Court> _courts = [];
  bool _loading = false;
  bool _fromNotion = false;

  List<Court> get courts => _courts;
  bool get loading => _loading;
  /// True si la lista viene de la BD real (no del caché ni del fallback vacío).
  bool get fromNotion => _fromNotion;

  Future<void> load({bool force = false}) async {
    // Primero el caché: el mapa aparece al instante (también en el arranque en
    // frío de Render) y sin red queda lo último conocido.
    if (_courts.isEmpty) {
      final cached = await _readCache();
      if (cached.isNotEmpty) {
        _courts = cached;
        notifyListeners();
      }
    }
    if (!_api.isConfigured || !_api.hasToken) return;
    if (!force && _courts.isNotEmpty && await _cacheIsFresh()) return;
    // Spinner solo si no hay nada que mostrar.
    _loading = _courts.isEmpty;
    notifyListeners();
    try {
      // GET /courts ya devuelve solo las aprobadas.
      final rows = await _api.courts();
      final fresh = rows.map(Court.fromApi).toList();
      _courts = fresh;
      _fromNotion = true;
      // Nunca pisar un caché bueno con una lista vacía.
      if (fresh.isNotEmpty) unawaited(_writeCache(fresh));
    } catch (_) {
      // Sin red: se conserva la lista que había (caché o carga anterior). Antes
      // se vaciaba, y eso desarmaba geofences y detección.
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<List<Court>> _readCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kCache);
      if (raw == null) return const [];
      return [
        for (final e in jsonDecode(raw) as List)
          Court.fromApi((e as Map).cast<String, dynamic>())
      ];
    } catch (_) {
      return const []; // caché corrupto: ignorar
    }
  }

  Future<void> _writeCache(List<Court> courts, {bool touch = true}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _kCache, jsonEncode([for (final c in courts) c.toCacheJson()]));
      if (touch) {
        await prefs.setInt(_kCacheAt, DateTime.now().millisecondsSinceEpoch);
      }
    } catch (_) {}
  }

  Future<bool> _cacheIsFresh() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final at = prefs.getInt(_kCacheAt);
      if (at == null) return false;
      return DateTime.now()
              .difference(DateTime.fromMillisecondsSinceEpoch(at)) <
          _kTtl;
    } catch (_) {
      return false;
    }
  }

  /// Corrige el rating de UNA cancha (tras dejar o borrar una reseña, con la
  /// lista que el detalle ya bajó) sin volver a pedir el catálogo entero.
  void applyRating(String courtId, double average, int count) {
    final i = _courts.indexWhere((c) => c.id == courtId);
    if (i < 0) return;
    final c = _courts[i];
    if (c.reviews == count && (c.rating - average).abs() < 0.001) return;
    final updated = Court.fromApi(
        {...c.toCacheJson(), 'rating': average, 'reviews': count});
    _courts = [..._courts]..[i] = updated;
    notifyListeners();
    // Sin tocar la hora del caché: el resto del catálogo sigue igual de viejo.
    unawaited(_writeCache(_courts, touch: false));
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
    AnalyticsService.event('court_propose', {
      'type': court.type,
      'surface': court.surface,
      'free': court.free,
      'has_hours': court.openTime.isNotEmpty || court.hours.isNotEmpty,
    });
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
    await load(force: true);
  }

  /// Elimina una cancha (y sus reseñas, server-side). Solo admin: el backend
  /// devuelve 403 si el token no lo es.
  Future<void> deleteCourt(String courtId) async {
    await _api.deleteCourt(courtId);
    await load(force: true);
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
    // Antes se consultaba en cada arranque. Ahora: cada 12 h si hay alguna
    // propuesta esperando moderación, y cada 7 días si no (por si se propuso
    // desde otro celular o antes de reinstalar).
    final states = await _readCourtStates(e);
    final hasPending = states.values.any((s) => s == CourtApproval.pending);
    final every = hasPending ? const Duration(hours: 12) : const Duration(days: 7);
    final prefs = await SharedPreferences.getInstance();
    final atKey = 'court_decisions_at::$e';
    final lastAt = prefs.getInt(atKey);
    if (lastAt != null &&
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastAt)) <
            every) {
      return const [];
    }
    List<Court> mine;
    try {
      // GET /courts/mine trae las propias en TODOS los estados.
      final rows = await _api.myCourts();
      mine = rows.map(Court.fromApi).toList();
      await prefs.setInt(atKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      return const [];
    }
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
