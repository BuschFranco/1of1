import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/models.dart';
import '../notion/notion_config.dart';
import 'notion_service.dart';

/// Provee los pickups en los que el usuario está involucrado (como creador o
/// invitado) y las operaciones de invitación/gestión: aceptar, rechazar, mover
/// miembros de equipo, quitar miembros y eliminar el pickup.
class PickupsProvider extends ChangeNotifier {
  PickupsProvider({NotionService? notion}) : _notion = notion ?? NotionService();
  final NotionService _notion;

  List<Pickup> _pickups = [];
  List<Pickup> get pickups => List.unmodifiable(_pickups);

  bool _loading = false;
  bool get loading => _loading;

  String _email = '';

  /// Carga los pickups donde el usuario es creador o está invitado (aparece en
  /// TeamAMembers/TeamBMembers). Best-effort: ante error deja la lista actual.
  Future<void> loadForUser(String email) async {
    _email = email.trim().toLowerCase();
    if (_email.isEmpty ||
        !NotionConfig.isConfigured ||
        NotionConfig.dbPickups.isEmpty) {
      _pickups = [];
      notifyListeners();
      return;
    }
    _loading = true;
    notifyListeners();
    try {
      final rows = await _notion.queryDatabaseAll(
        NotionConfig.dbPickups,
        filter: NotionService.filterOr([
          NotionService.filterText('CreatedBy', _email),
          NotionService.filterTextContains('TeamAMembers', _email),
          NotionService.filterTextContains('TeamBMembers', _email),
        ]),
      );
      final list = rows.map(Pickup.fromNotion).toList();
      final seen = <String>{};
      final deduped = [for (final p in list) if (seen.add(p.pageId)) p];
      // Regla de retención: 24h después del pickup deja de mostrarse y se
      // limpia de la BDD (pickup + chat) para ahorrar espacio.
      final expired = deduped.where((p) => p.isExpired).toList();
      _pickups = deduped.where((p) => !p.isExpired).toList();
      // Más recientes primero (los sin fecha, al final).
      _pickups.sort((a, b) => (b.dateTime ?? '').compareTo(a.dateTime ?? ''));
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

  Future<Pickup> _update(Pickup updated) async {
    await _notion.updatePage(updated.pageId, updated.toNotionProperties());
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

  /// Mueve un miembro al equipo destino ('A' o 'B'), reconstruyendo los CSV.
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

  /// Unirse a un pickup por código de invitación (5 dígitos). Busca el pickup
  /// server-side, valida estado y capacidad, y mete al usuario en el equipo con
  /// espacio (el de menos miembros primero) como miembro ya ACEPTADO.
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
    if (e.isEmpty || !NotionConfig.isConfigured) {
      return (error: 'No se pudo conectar. Probá de nuevo.', pickupId: null);
    }
    try {
      final rows = await _notion.queryDatabase(
        NotionConfig.dbPickups,
        filter: NotionService.filterText('InviteCode', c),
      );
      if (rows.isEmpty) {
        return (
          error: 'Código inválido. Revisá los 5 dígitos.',
          pickupId: null
        );
      }
      final p = Pickup.fromNotion(rows.first);
      if (p.isExpired) {
        return (error: 'Ese pickup ya terminó.', pickupId: null);
      }
      if (p.isCreator(e)) {
        return (error: 'Este pickup es tuyo 🙂', pickupId: null);
      }
      if (p.teamOf(e) != null) {
        // Ya estaba invitado: si tenía la invitación pendiente, aceptarla.
        if (!p.hasAccepted(e)) {
          await accept(p, e);
          await loadForUser(e);
          return (error: null, pickupId: p.pageId);
        }
        return (error: 'Ya estás en este pickup.', pickupId: null);
      }
      // Elegir el equipo con espacio (menos miembros primero) según teamSize.
      final aFree = p.teamAMembers.length < p.teamSize;
      final bFree = p.teamBMembers.length < p.teamSize;
      if (!aFree && !bFree) {
        return (error: 'El pickup ya está completo.', pickupId: null);
      }
      final toA = aFree &&
          (!bFree || p.teamAMembers.length <= p.teamBMembers.length);
      final updated = p.copyWith(
        teamAMembers: toA ? [...p.teamAMembers, e] : null,
        teamBMembers: toA ? null : [...p.teamBMembers, e],
        acceptedMembers: [
          ...p.acceptedMembers.where((x) => !_eq(x, e)),
          e,
        ],
      );
      await _notion.updatePage(updated.pageId, updated.toNotionProperties());
      // El pickup no estaba en la lista local del que se une: recargar.
      await loadForUser(e);
      return (error: null, pickupId: p.pageId);
    } catch (_) {
      return (error: 'No se pudo conectar. Probá de nuevo.', pickupId: null);
    }
  }

  /// El usuario abandona el pickup: se quita de equipos y respuestas en Notion y
  /// se remueve de la lista local (ya no participa).
  Future<void> leave(Pickup p, String email) async {
    final updated = p.copyWith(
      teamAMembers: p.teamAMembers.where((x) => !_eq(x, email)).toList(),
      teamBMembers: p.teamBMembers.where((x) => !_eq(x, email)).toList(),
      acceptedMembers: p.acceptedMembers.where((x) => !_eq(x, email)).toList(),
      declinedMembers: p.declinedMembers.where((x) => !_eq(x, email)).toList(),
    );
    await _notion.updatePage(updated.pageId, updated.toNotionProperties());
    _pickups.removeWhere((x) => x.pageId == p.pageId);
    notifyListeners();
  }

  /// Archiva en Notion la página del pickup y, best-effort, las filas de su
  /// chat. Compartido entre la eliminación manual y la limpieza por expiración.
  Future<void> _archiveInNotion(Pickup p) async {
    await _notion.archivePage(p.pageId);
    // Chat asociado en Notion (si dbChats está configurado).
    if (NotionConfig.dbChats.isNotEmpty) {
      try {
        final chats = await _notion.queryDatabase(
          NotionConfig.dbChats,
          filter: NotionService.filterText('PickupId', p.pageId),
        );
        for (final c in chats) {
          final id = c['id']?.toString();
          if (id != null) await _notion.archivePage(id);
        }
      } catch (_) {}
    }
  }

  /// Limpia de la BDD los pickups vencidos (24h después del partido). Cualquier
  /// cliente que los vea los archiva: los datos ya están muertos y archivar es
  /// idempotente, así que no importa si dos usuarios lo intentan a la vez.
  Future<void> _cleanupExpired(List<Pickup> expired) async {
    for (final p in expired) {
      try {
        await _archiveInNotion(p);
      } catch (_) {
        // Best-effort: se reintenta en la próxima carga.
      }
    }
  }

  /// Elimina (archiva) el pickup y, best-effort, su chat en Notion.
  Future<void> deletePickup(Pickup p) async {
    await _archiveInNotion(p);
    _pickups.removeWhere((x) => x.pageId == p.pageId);
    notifyListeners();
  }

  void clearForLogout() {
    _pickups = [];
    _email = '';
    notifyListeners();
  }
}
