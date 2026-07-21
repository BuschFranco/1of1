import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/models.dart';
import 'api/api_client.dart';
import 'cache/api_cache.dart';

/// Provee los pickups en los que el usuario está involucrado (como creador o
/// invitado) y las operaciones de invitación/gestión: aceptar, rechazar, mover
/// miembros de equipo, quitar miembros y eliminar el pickup. Todo vía backend.
class PickupsProvider extends ChangeNotifier {
  PickupsProvider({ApiClient? api}) : _api = api ?? ApiClient();
  final ApiClient _api;

  List<Pickup> _pickups = [];
  List<Pickup> get pickups => List.unmodifiable(_pickups);

  bool _loading = false;
  bool get loading => _loading;

  String _email = '';

  /// Carga los pickups donde el usuario es creador o está invitado. El filtro
  /// lo hace el server con el email del token; [email] se conserva para la
  /// lógica local (expiración/orden). Best-effort: ante error deja la lista.
  Future<void> loadForUser(String email, {bool force = false}) async {
    _email = email.trim().toLowerCase();
    if (_email.isEmpty || !_api.isConfigured || !_api.hasToken) {
      _pickups = [];
      notifyListeners();
      return;
    }
    // Guarda TTL: si se cargó hace poco y ya hay datos, no refetch (evita el
    // GET /pickups en cada apertura de Crew). `force` para el pull-to-refresh.
    if (!force &&
        _pickups.isNotEmpty &&
        ApiCache.isFresh('pickups', ApiCache.ttlPickups)) {
      return;
    }
    _loading = true;
    notifyListeners();
    try {
      final rows = await _api.pickups();
      final list = rows.map(Pickup.fromApi).toList();
      final seen = <String>{};
      final deduped = [for (final p in list) if (seen.add(p.pageId)) p];
      // Regla de retención: 24h después del pickup deja de mostrarse y se
      // limpia de la BDD (pickup + chat) para ahorrar espacio.
      final expired = deduped.where((p) => p.isExpired).toList();
      _pickups = deduped.where((p) => !p.isExpired).toList();
      // Más recientes primero (los sin fecha, al final).
      _pickups.sort((a, b) => (b.dateTime ?? '').compareTo(a.dateTime ?? ''));
      ApiCache.put('pickups', true); // marca de tiempo para la guarda TTL
      // Fire-and-forget: no bloquear la pantalla por la limpieza. Si falla,
      // igual quedan ocultos y se reintenta en la próxima carga.
      if (expired.isNotEmpty) unawaited(_cleanupExpired(expired));
    } catch (_) {
      // Silencioso: no romper la pantalla.
    }
    _loading = false;
    notifyListeners();
  }

  Pickup? byId(String pageId) {
    for (final p in _pickups) {
      if (p.pageId == pageId) return p;
    }
    return null;
  }

  /// Invitaciones pendientes para un usuario: está invitado (en algún equipo),
  /// no es el creador y todavía no aceptó ni rechazó.
  List<Pickup> pendingInvitesFor(String email) {
    return _pickups
        .where((p) =>
            !p.isCreator(email) &&
            p.teamOf(email) != null &&
            !p.hasAccepted(email) &&
            !p.hasDeclined(email))
        .toList();
  }

  /// Crea el pickup en el backend (el server genera el inviteCode de 5 dígitos
  /// y toma el creador del token). Devuelve el pickup creado.
  Future<Pickup> create(Pickup p) async {
    final json = await _api.createPickup(p.toApiJson());
    final created = Pickup.fromApi(json);
    _pickups.insert(0, created);
    notifyListeners();
    return created;
  }

  /// Crea la metadata del chat de crew. Devuelve null si la feature está
  /// apagada en el server (503) — el chat local funciona igual.
  Future<CrewChat?> createChat(CrewChat chat) async {
    try {
      final json = await _api.createChat(chat.toApiJson());
      return CrewChat.fromApi(json);
    } on ApiException catch (e) {
      if (e.statusCode == 503) return null;
      rethrow;
    }
  }

  Future<Pickup> _update(Pickup updated) async {
    await _api.updatePickup(updated.pageId, updated.toApiJson());
    final i = _pickups.indexWhere((p) => p.pageId == updated.pageId);
    if (i >= 0) _pickups[i] = updated;
    notifyListeners();
    return updated;
  }

  bool _eq(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  /// Acepta la invitación: agrega a aceptados y saca de rechazados.
  Future<Pickup> accept(Pickup p, String email) async {
    final acc = [
      ...p.acceptedMembers.where((x) => !_eq(x, email)),
      email,
    ];
    final dec = p.declinedMembers.where((x) => !_eq(x, email)).toList();
    return _update(p.copyWith(acceptedMembers: acc, declinedMembers: dec));
  }

  /// Rechaza la invitación: agrega a rechazados y saca de aceptados.
  Future<Pickup> decline(Pickup p, String email) async {
    final dec = [
      ...p.declinedMembers.where((x) => !_eq(x, email)),
      email,
    ];
    final acc = p.acceptedMembers.where((x) => !_eq(x, email)).toList();
    return _update(p.copyWith(acceptedMembers: acc, declinedMembers: dec));
  }

  /// Mueve un miembro al equipo destino ('A' o 'B').
  Future<Pickup> moveMember(Pickup p, String email, String toTeam) async {
    final a = p.teamAMembers.where((x) => !_eq(x, email)).toList();
    final b = p.teamBMembers.where((x) => !_eq(x, email)).toList();
    if (toTeam == 'A') {
      a.add(email);
    } else {
      b.add(email);
    }
    return _update(p.copyWith(teamAMembers: a, teamBMembers: b));
  }

  /// Quita a un miembro del pickup por completo (de equipos y de aceptados).
  Future<Pickup> removeMember(Pickup p, String email) async {
    return _update(p.copyWith(
      teamAMembers: p.teamAMembers.where((x) => !_eq(x, email)).toList(),
      teamBMembers: p.teamBMembers.where((x) => !_eq(x, email)).toList(),
      acceptedMembers: p.acceptedMembers.where((x) => !_eq(x, email)).toList(),
      declinedMembers: p.declinedMembers.where((x) => !_eq(x, email)).toList(),
    ));
  }

  /// Reenvía la invitación a un miembro que ya respondió: limpia su respuesta
  /// (accepted/declined) para que vuelva a quedar pendiente. Solo el creador.
  Future<Pickup> resendInvite(Pickup p, String email) async {
    return _update(p.copyWith(
      acceptedMembers: p.acceptedMembers.where((x) => !_eq(x, email)).toList(),
      declinedMembers: p.declinedMembers.where((x) => !_eq(x, email)).toList(),
    ));
  }

  /// Unirse a un pickup por código de invitación (5 dígitos). El server valida
  /// todo (código, expiración, capacidad, ya-miembro) y mete al usuario en el
  /// equipo con espacio como miembro ya ACEPTADO.
  ///
  /// Límite conocido: el creador no recibe aviso push cuando alguien se une (no
  /// existe canal push entre usuarios); ve al nuevo miembro al abrir el chat.
  Future<({String? error, String? pickupId})> joinByCode(
      String code, String email) async {
    final c = code.trim();
    final e = email.trim().toLowerCase();
    if (c.length != 5 || int.tryParse(c) == null) {
      return (error: 'Código inválido. Revisá los 5 dígitos.', pickupId: null);
    }
    if (e.isEmpty || !_api.isConfigured || !_api.hasToken) {
      return (error: 'No se pudo conectar. Probá de nuevo.', pickupId: null);
    }
    try {
      final json = await _api.joinPickup(c);
      final joined = Pickup.fromApi(json);
      // El pickup no estaba en la lista local del que se une: recargar sí o sí.
      await loadForUser(e, force: true);
      return (error: null, pickupId: joined.pageId);
    } on ApiException catch (ex) {
      if (ex.statusCode == 404) {
        return (
          error: 'Código inválido. Revisá los 5 dígitos.',
          pickupId: null
        );
      }
      // 403: propio / completo / expirado / ya unido — el server manda el
      // mensaje legible.
      if (ex.statusCode == 403 && ex.message.isNotEmpty) {
        return (error: ex.message, pickupId: null);
      }
      return (error: 'No se pudo conectar. Probá de nuevo.', pickupId: null);
    } catch (_) {
      return (error: 'No se pudo conectar. Probá de nuevo.', pickupId: null);
    }
  }

  /// El usuario abandona el pickup: se quita de equipos y respuestas y se
  /// remueve de la lista local (ya no participa).
  Future<void> leave(Pickup p, String email) async {
    final updated = p.copyWith(
      teamAMembers: p.teamAMembers.where((x) => !_eq(x, email)).toList(),
      teamBMembers: p.teamBMembers.where((x) => !_eq(x, email)).toList(),
      acceptedMembers: p.acceptedMembers.where((x) => !_eq(x, email)).toList(),
      declinedMembers: p.declinedMembers.where((x) => !_eq(x, email)).toList(),
    );
    await _api.updatePickup(updated.pageId, updated.toApiJson());
    _pickups.removeWhere((x) => x.pageId == p.pageId);
    notifyListeners();
  }

  /// Limpia de la BDD los pickups vencidos (24h después del partido). El
  /// DELETE del server es solo-creador: en los clientes de los invitados da
  /// 403 y se ignora (el creador lo limpia en su próxima carga). El server
  /// también archiva el chat asociado.
  Future<void> _cleanupExpired(List<Pickup> expired) async {
    for (final p in expired) {
      try {
        await _api.deletePickup(p.pageId);
      } catch (_) {
        // Best-effort: 403 de no-creador o sin red; se reintenta luego.
      }
    }
  }

  /// Elimina el pickup (y su chat, server-side). Solo el creador.
  Future<void> deletePickup(Pickup p) async {
    await _api.deletePickup(p.pageId);
    _pickups.removeWhere((x) => x.pageId == p.pageId);
    notifyListeners();
  }

  void clearForLogout() {
    _pickups = [];
    _email = '';
    notifyListeners();
  }
}
