import 'package:flutter/material.dart';
import '../services/notion_service.dart';

enum CourtStatus { open, closed }

// El estado "busy" (override manual) se eliminó: el estado efectivo sale del
// horario real (isOpenNow). Un 'busy' legacy en Notion se lee como 'open'.
CourtStatus _statusFromString(String s) => switch (s) {
      'closed' => CourtStatus.closed,
      _ => CourtStatus.open,
    };

/// Parsea un "HH:mm" a TimeOfDay. null si no matchea o está fuera de rango.
TimeOfDay? _todFromHHmm(String s) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s.trim());
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  if (h > 23 || min > 59) return null;
  return TimeOfDay(hour: h, minute: min);
}

String _fmtTod(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Estados de moderación de una cancha (select "Aprobacion" en Notion).
class CourtApproval {
  static const pending = 'Sin definir';
  static const approved = 'Aprobado';
  static const rejected = 'Desaprobado';
}

/// Badges que existen como opciones en la base Canchas de Notion.
/// Al escribir filtramos a este set para no romper el multi_select.
const Set<String> kAllowedBadges = {
  'Iluminada', 'Gratis', 'Popular', 'Techada', 'Reserva', 'Torneos',
  'Vestuarios', 'Estacionamiento', 'Bebedero',
};

class Court {
  final String id;
  final String name;
  final String area;
  final String dist;
  final String img;
  final double rating;
  final int reviews;
  final String type;
  final bool free;
  final bool lit;
  final int hoops;
  final String surface;

  /// Estado crudo que viene del select "Status" de Notion. Solo se usa para el
  /// override manual `busy` (ocupada) y como fallback si la cancha no tiene
  /// horario parseable. El estado real de abierto/cerrado se computa: ver
  /// [status] e [isOpenNow].
  final CourtStatus rawStatus;
  final int players;
  final String vibe;

  /// Horario en texto libre (legacy). Se conserva para canchas viejas que aún
  /// no tienen [openTime]/[closeTime]; sirve de fallback de parseo y display.
  final String hours;

  /// Horario estructurado "HH:mm" (vacío = desconocido). Apertura == cierre
  /// significa 24h (ver [is24h]).
  final String openTime;
  final String closeTime;

  final List<String> badges;
  final String desc;
  final double lat;
  final double lng;

  /// Handle del usuario que propuso la cancha (se lee de la columna
  /// "CreatedBy" de Notion). Vacío en las canchas mock.
  final String proposedBy;

  /// Snapshot de la insignia de clan al momento del envío (columna
  /// "CreatedByClan"). Solo se usa como fallback si no se puede resolver el
  /// perfil en vivo por email.
  final String proposedByClan;

  /// Email (inmutable) de quien propuso la cancha (columna "CreatedByEmail").
  /// Es la clave para resolver en vivo su handle y clan actuales desde la base
  /// Perfiles, así los cambios posteriores se reflejan en las miniaturas.
  final String proposedByEmail;

  /// Estado de moderación (select "Aprobacion": ver [CourtApproval]). Vacío si
  /// la columna no está seteada. Las canchas del mapa son siempre "Aprobado"
  /// (el provider filtra); se lee para detectar la decisión sobre las propias.
  final String approval;

  const Court({
    required this.id,
    required this.name,
    required this.area,
    required this.dist,
    required this.img,
    required this.rating,
    required this.reviews,
    required this.type,
    required this.free,
    required this.lit,
    required this.hoops,
    required this.surface,
    required this.rawStatus,
    required this.players,
    required this.vibe,
    required this.hours,
    this.openTime = '',
    this.closeTime = '',
    required this.badges,
    required this.desc,
    required this.lat,
    required this.lng,
    this.proposedBy = '',
    this.proposedByClan = '',
    this.proposedByEmail = '',
    this.approval = '',
  });

  String get _rawStatusName => switch (rawStatus) {
        CourtStatus.closed => 'closed',
        CourtStatus.open => 'open',
      };

  /// Horario de apertura efectivo: los campos estructurados y, si están vacíos,
  /// el parseo del texto libre legacy. null si no hay horario conocido.
  TimeOfDay? get openTod =>
      _todFromHHmm(openTime) ?? parseHours(hours)?.$1;

  /// Horario de cierre efectivo (ver [openTod]).
  TimeOfDay? get closeTod =>
      _todFromHHmm(closeTime) ?? parseHours(hours)?.$2;

  /// True si la cancha está 24h (apertura == cierre, ambos definidos).
  bool get is24h {
    final o = openTod, c = closeTod;
    return o != null && c != null && o.hour == c.hour && o.minute == c.minute;
  }

  /// Computa si está abierta AHORA contra la hora del dispositivo. Maneja rangos
  /// que cruzan medianoche (ej. 18:00–02:00). null si no hay horario parseable.
  bool? get isOpenNow {
    if (is24h) return true;
    final o = openTod, c = closeTod;
    if (o == null || c == null) return null;
    final now = TimeOfDay.now();
    final nowMin = now.hour * 60 + now.minute;
    final oMin = o.hour * 60 + o.minute;
    final cMin = c.hour * 60 + c.minute;
    if (cMin > oMin) return nowMin >= oMin && nowMin < cMin; // mismo día
    return nowMin >= oMin || nowMin < cMin; // cruza medianoche
  }

  /// Estado efectivo: se computa del horario real (abierta/cerrada); si no hay
  /// horario parseable, cae al estado crudo de Notion. Todos los consumidores
  /// usan `court.status`, así que ven el valor ya computado.
  CourtStatus get status {
    final open = isOpenNow;
    if (open == null) return rawStatus;
    return open ? CourtStatus.open : CourtStatus.closed;
  }

  /// Horario formateado para mostrar ("06:00 — 23:00" / "Abierto 24h" / legacy).
  String get hoursLabel {
    if (is24h) return 'Abierto 24h';
    final o = openTod, c = closeTod;
    if (o != null && c != null) return '${_fmtTod(o)} — ${_fmtTod(c)}';
    return hours;
  }

  /// Parsea un horario en texto libre a (apertura, cierre). Soporta
  /// "HH:MM — HH:MM", "HH:MM - HH:MM", "de 6:00 a 23:00", "24h"/"Abierto 24h"
  /// (→ 00:00/00:00). null si no se puede interpretar.
  static (TimeOfDay, TimeOfDay)? parseHours(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final lower = s.toLowerCase();
    if (lower.contains('24')) {
      const midnight = TimeOfDay(hour: 0, minute: 0);
      return (midnight, midnight);
    }
    final matches =
        RegExp(r'(\d{1,2}):(\d{2})').allMatches(s).toList();
    if (matches.length < 2) return null;
    final open = _todFromHHmm(matches[0].group(0)!);
    final close = _todFromHHmm(matches[1].group(0)!);
    if (open == null || close == null) return null;
    return (open, close);
  }

  /// Construye una Court a partir de una página de la base Canchas de Notion.
  /// El `id` es el page id de Notion (estable y único).
  factory Court.fromNotion(Map<String, dynamic> page) {
    final p = page['properties'] as Map<String, dynamic>;
    return Court(
      id: page['id']?.toString() ?? '',
      name: NotionService.readTitle(p, 'Name'),
      area: NotionService.readText(p, 'Area'),
      dist: NotionService.readText(p, 'Dist'),
      img: NotionService.readUrl(p, 'Img'),
      rating: NotionService.readNumber(p, 'Rating'),
      reviews: NotionService.readInt(p, 'Reviews'),
      type: NotionService.readSelect(p, 'Type', fallback: 'Exterior'),
      free: NotionService.readCheckbox(p, 'Free'),
      lit: NotionService.readCheckbox(p, 'Lit'),
      hoops: NotionService.readInt(p, 'Hoops', fallback: 1),
      surface: NotionService.readSelect(p, 'Surface', fallback: 'Asfalto'),
      rawStatus: _statusFromString(NotionService.readSelect(p, 'Status', fallback: 'open')),
      players: NotionService.readInt(p, 'Players'),
      vibe: NotionService.readSelect(p, 'Vibe', fallback: 'Casual'),
      hours: NotionService.readText(p, 'Hours'),
      openTime: NotionService.readText(p, 'OpenTime'),
      closeTime: NotionService.readText(p, 'CloseTime'),
      badges: NotionService.readMultiSelect(p, 'Badges'),
      desc: NotionService.readText(p, 'Desc'),
      lat: NotionService.readNumber(p, 'Lat'),
      lng: NotionService.readNumber(p, 'Lng'),
      proposedBy: NotionService.readText(p, 'CreatedBy'),
      proposedByClan: NotionService.readText(p, 'CreatedByClan'),
      proposedByEmail: NotionService.readText(p, 'CreatedByEmail'),
      approval: NotionService.readSelect(p, 'Aprobacion', fallback: ''),
    );
  }

  /// Serializa a propiedades de Notion para crear/actualizar la cancha.
  /// Por defecto entra como "Sin definir" (pendiente de moderación).
  Map<String, dynamic> toNotionProperties({
    String? createdBy,
    String? createdByClan,
    String? createdByEmail,
    String approval = CourtApproval.pending,
  }) {
    return {
      'Name': NotionService.title(name),
      'Area': NotionService.richText(area),
      'Dist': NotionService.richText(dist),
      'Img': NotionService.url(img),
      'Rating': NotionService.number(rating),
      'Reviews': NotionService.number(reviews),
      'Type': NotionService.select(type),
      'Free': NotionService.checkbox(free),
      'Lit': NotionService.checkbox(lit),
      'Hoops': NotionService.number(hoops),
      'Surface': NotionService.select(surface),
      'Status': NotionService.select(_rawStatusName),
      'Players': NotionService.number(players),
      'Vibe': NotionService.select(vibe),
      // Hours legible autogenerado (compat con canchas viejas y con quien lea
      // Notion a mano); OpenTime/CloseTime son la fuente estructurada.
      'Hours': NotionService.richText(hoursLabel),
      'OpenTime': NotionService.richText(openTime),
      'CloseTime': NotionService.richText(closeTime),
      'Badges': NotionService.multiSelect(
        badges.where(kAllowedBadges.contains).toList(),
      ),
      'Desc': NotionService.richText(desc),
      'Lat': NotionService.number(lat),
      'Lng': NotionService.number(lng),
      if (createdBy != null) 'CreatedBy': NotionService.richText(createdBy),
      if (createdByClan != null)
        'CreatedByClan': NotionService.richText(createdByClan),
      if (createdByEmail != null)
        'CreatedByEmail': NotionService.richText(createdByEmail),
      'Aprobacion': NotionService.select(approval),
    };
  }
}
