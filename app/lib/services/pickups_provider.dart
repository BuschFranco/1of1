import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models.dart';
import 'api/api_client.dart';
import 'cache/api_cache.dart';

/// Ocupación de una cancha en un día, para pintar el picker de horarios.
///
/// La calcula el backend (`GET /pickups/availability`), que devuelve solo
/// tiempos y aros: un pickup privado no filtra más que "la cancha está ocupada
/// a tal hora".
class CourtAvailability {
  /// Aros de la cancha: cuántos partidos de media cancha entran a la vez.
  final int hoops;

  /// Cuánto ocupa un pickup desde su horario de inicio. Lo manda el server para
  /// no duplicar acá su constante (`PICKUP_SLOT_MS`).
  final Duration slot;

  /// Inicio de cada pickup ya agendado y cuántos aros se lleva. Los `startsAt`
  /// son DateTime **locales** con el reloj de pared original (ver [fromApi]).
  final List<({DateTime startsAt, int hoops})> busy;

  const CourtAvailability({
    required this.hoops,
    required this.slot,
    required this.busy,
  });

  /// Todo libre. Es el fallback cuando la consulta falla: nunca dejamos al
  /// usuario sin poder elegir horario por un problema de red — el backend
  /// revalida igual al crear.
  static const CourtAvailability unknown = CourtAvailability(
    hoops: 1,
    slot: Duration(minutes: 90),
    busy: [],
  );

  /// Ojo con las fechas: la app manda ISO local SIN offset y el backend lo trata
  /// como UTC (regla heredada, ver `parseUtc` en `backend/src/domain/wire.ts`).
  /// O sea que lo que vuelve en UTC es el **reloj de pared** original, no un
  /// instante real. Por eso se reconstruye componente a componente como
  /// DateTime local, en vez de usar `DateTime.parse().toLocal()`, que correría
  /// todo por el offset de la zona.
  factory CourtAvailability.fromApi(Map<String, dynamic> json) {
    final raw = (json['busy'] as List?) ?? const [];
    final busy = <({DateTime startsAt, int hoops})>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final parsed = DateTime.tryParse('${item['startsAt']}');
      if (parsed == null) continue;
      final u = parsed.toUtc();
      busy.add((
        startsAt: DateTime(u.year, u.month, u.day, u.hour, u.minute),
        hoops: (item['hoops'] as num?)?.toInt() ?? 1,
      ));
    }
    final minutes = (json['slotMinutes'] as num?)?.toInt() ?? 90;
    return CourtAvailability(
      hoops: (json['hoops'] as num?)?.toInt() ?? 1,
      slot: Duration(minutes: minutes),
      busy: busy,
    );
  }

  /// Aros que consume un pickup según su formato: un 5v5 es cancha completa
  /// (2 aros), un 4v4 o menos es media cancha (1). Gemela de `hoopCost` en el
  /// backend: si cambia una, cambiá la otra.
  int costOf(int teamSize) => (teamSize >= 5 ? 2 : 1).clamp(1, hoops);

  /// True si a las [start] todavía entra un pickup de [teamSize] por equipo.
  /// Todos los pickups ocupan el mismo bloque, así que dos se solapan cuando sus
  /// inicios distan menos de [slot].
  bool fits(DateTime start, int teamSize) {
    var used = 0;
    for (final b in busy) {
      if (b.startsAt.difference(start).abs() < slot) used += b.hoops;
    }
    return used + costOf(teamSize) <= hoops;
  }
}

/// Provee los pickups en los que el usuario está involucrado (como creador o
/// invitado) y las operaciones de invitación/gestión: aceptar, rechazar, mover
/// miembros de equipo, quitar miembros y eliminar el pickup. Todo vía backend.
class PickupsProvider extends ChangeNotifier {
  PickupsProvider({ApiClient? api}) : _api = api ?? ApiClient();
  final ApiClient _api;

  List<Pickup> _pickups = [];
  List<Pickup> get pickups => List.unmodifiable(_pickups);

  /// Pickups públicos de la ÚLTIMA cancha consultada (cache de la sección del
  /// detalle de cancha). No persiste; es solo para no refetchear al reentrar.
  final List<Pickup> _publicByCourt = [];
  List<Pickup> get publicByCourt => List.unmodifiable(_publicByCourt);

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

  /// Carga los pickups PÚBLICOS de una cancha (para la sección del detalle).
  /// Best-effort: ante error deja la lista anterior. Filtra los vencidos igual
  /// que la lista propia (regla de retención de 24h).
  Future<void> loadPublicForCourt(String courtId, {bool force = false}) async {
    if (courtId.isEmpty || !_api.isConfigured || !_api.hasToken) {
      _publicByCourt.clear();
      notifyListeners();
      return;
    }
    if (!force && _publicByCourt.isNotEmpty &&
        _publicByCourt.first.courtId == courtId &&
        ApiCache.isFresh('publicPickups:$courtId', ApiCache.ttlPickups)) {
      return;
    }
    try {
      final rows = await _api.publicPickups(courtId);
      final list = rows.map(Pickup.fromApi).toList();
      _publicByCourt
        ..clear()
        ..addAll(list.where((p) => !p.isExpired));
      ApiCache.put('publicPickups:$courtId', true);
    } catch (_) {
      // Silencioso: no romper el detalle si el backend duerme/falla.
    }
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

  /// Ocupación de [courtId] en el día [day] (se usa solo la fecha, no la hora).
  ///
  /// Ante cualquier error devuelve [CourtAvailability.unknown] (todo libre): es
  /// preferible mostrar de más y que el backend rechace al crear, antes que
  /// dejar al usuario sin poder elegir horario porque se cayó la red.
  Future<CourtAvailability> availability(
    String courtId,
    DateTime day, {
    String? excludePickupId,
  }) async {
    if (courtId.trim().isEmpty) return CourtAvailability.unknown;
    final date = '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    try {
      final json = await _api.courtAvailability(
        courtId,
        date,
        excludePickupId: excludePickupId,
      );
      return CourtAvailability.fromApi(json);
    } catch (_) {
      return CourtAvailability.unknown;
    }
  }

  /// Pickup activo que creó [email], o null si no tiene ninguno.
  ///
  /// Regla de producto: **un solo pickup activo por creador**. Hasta que el suyo
  /// no termine (24 h después del partido, ver [Pickup.isExpired]) o lo elimine,
  /// no puede crear otro. Sirve para avisar antes de abrir el formulario; quien
  /// decide de verdad es el backend, que revalida al crear.
  Pickup? activeCreatedBy(String email) {
    if (email.trim().isEmpty) return null;
    for (final p in _pickups) {
      if (p.isCreator(email) && !p.isExpired) return p;
    }
    return null;
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

  /// Reprograma el pickup (fecha y/o hora). Solo lo usa el creador desde el chat
  /// del pickup; el backend valida que quien llama sea miembro.
  ///
  /// [iso] va en hora LOCAL sin zona (`toIso8601String()` de un DateTime local),
  /// igual que al crear el pickup: el backend lo interpreta con parseUtc, así
  /// que mezclar formatos desfasaría el horario mostrado.
  Future<Pickup> reschedule(Pickup p, DateTime when) =>
      _update(p.copyWith(dateTime: when.toIso8601String()));

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

  /// Unirse a un pickup público por id, sin código de invitación. El server
  /// valida todo (público, expiración, capacidad, ya-miembro) y mete al
  /// usuario en el equipo con espacio como miembro ya ACEPTADO. Tras unirse se
  /// recarga la lista propia para que aparezca en Crew.
  ///
  /// Devuelve null en éxito o un mensaje de error legible (el del server cuando
  /// lo manda).
  Future<String?> joinPublic(Pickup p, String email) async {
    final e = email.trim().toLowerCase();
    if (e.isEmpty || !_api.isConfigured || !_api.hasToken) {
      return 'No se pudo conectar. Probá de nuevo.';
    }
    try {
      final json = await _api.joinPublicPickup(p.pageId);
      final joined = Pickup.fromApi(json);
      await loadForUser(e, force: true);
      // Actualizar en la lista pública cacheada si está, así la UI local
      // refleja el cupo nuevo sin refetch.
      for (var i = 0; i < _publicByCourt.length; i++) {
        if (_publicByCourt[i].pageId == joined.pageId) {
          _publicByCourt[i] = joined;
        }
      }
      notifyListeners();
      return null;
    } on ApiException catch (ex) {
      if (ex.statusCode == 403 && ex.message.isNotEmpty) return ex.message;
      return 'No se pudo conectar. Probá de nuevo.';
    } catch (_) {
      return 'No se pudo conectar. Probá de nuevo.';
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
    _publicByCourt.clear();
    _email = '';
    notifyListeners();
  }

  // ── Aviso de pickup reprogramado ────────────────────────────────────────────
  //
  // No hay canal push entre usuarios: cuando el creador cambia la fecha, los
  // demás se enteran (a) por el mensaje que queda en el chat, y (b) por esta
  // comparación, que corre al recargar los pickups y avisa los cambios nuevos.
  // Mismo patrón que las decisiones de moderación de canchas.

  String _datesKey(String email) => 'notified_pickup_dates::$email';

  Future<Map<String, String>> _readKnownDates(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_datesKey(email));
      if (raw == null) return {};
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeKnownDates(String email, Map<String, String> d) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_datesKey(email), jsonEncode(d));
    } catch (_) {}
  }

  /// Devuelve los pickups cuya fecha cambió desde la última vez que los vimos.
  /// La primera observación se registra en silencio (si no, al reinstalar
  /// avisaría de todos los pickups como si recién los hubieran movido).
  ///
  /// Excluye los que creé yo: si cambié la fecha, ya lo sé.
  Future<List<({String title, String dateIso})>> pollRescheduled(
      String email) async {
    final e = email.trim().toLowerCase();
    if (e.isEmpty || _pickups.isEmpty) return const [];
    final known = await _readKnownDates(e);
    final out = <({String title, String dateIso})>[];
    var changed = false;
    final seen = <String>{};

    for (final p in _pickups) {
      if (p.pageId.isEmpty) continue;
      seen.add(p.pageId);
      final cur = p.dateTime ?? '';
      final prev = known[p.pageId];
      // Solo avisamos si participo de verdad y no soy el creador.
      final involved = !p.isCreator(e) && (p.hasAccepted(e) || p.teamOf(e) != null);
      if (prev != null && prev != cur && cur.isNotEmpty && involved) {
        out.add((title: p.title, dateIso: cur));
      }
      if (prev != cur) {
        known[p.pageId] = cur;
        changed = true;
      }
    }

    // Los pickups que ya no están (borrados/expirados) salen del registro para
    // que no crezca sin límite.
    final stale = known.keys.where((k) => !seen.contains(k)).toList();
    if (stale.isNotEmpty) {
      for (final k in stale) {
        known.remove(k);
      }
      changed = true;
    }

    if (changed) await _writeKnownDates(e, known);
    return out;
  }
}
