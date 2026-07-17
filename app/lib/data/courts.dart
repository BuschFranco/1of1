import 'package:flutter/material.dart';

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

  /// Construye una Court desde el JSON plano del backend.
  factory Court.fromApi(Map<String, dynamic> json) {
    String str(dynamic v, String fallback) {
      final s = (v ?? '').toString();
      return s.isEmpty ? fallback : s;
    }

    return Court(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      area: json['area'] as String? ?? '',
      dist: json['dist'] as String? ?? '',
      img: json['img'] as String? ?? '',
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      reviews: (json['reviews'] as num?)?.toInt() ?? 0,
      type: str(json['type'], 'Exterior'),
      free: json['free'] == true,
      lit: json['lit'] == true,
      hoops: (json['hoops'] as num?)?.toInt() ?? 1,
      surface: str(json['surface'], 'Asfalto'),
      rawStatus: _statusFromString(str(json['status'], 'open')),
      players: (json['players'] as num?)?.toInt() ?? 0,
      vibe: str(json['vibe'], 'Casual'),
      hours: json['hours'] as String? ?? '',
      openTime: json['openTime'] as String? ?? '',
      closeTime: json['closeTime'] as String? ?? '',
      badges: (json['badges'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      desc: json['desc'] as String? ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0,
      proposedBy: json['proposedBy'] as String? ?? '',
      proposedByClan: json['proposedByClan'] as String? ?? '',
      proposedByEmail: json['proposedByEmail'] as String? ?? '',
      approval: json['approval'] as String? ?? '',
    );
  }

  /// Payload para POST /courts. El autor (handle/clan/email) y la moderación
  /// los pone el server a partir del token; acá van solo los datos de la cancha.
  Map<String, dynamic> toApiJson() {
    return {
      'name': name,
      'area': area,
      'dist': dist,
      'img': img,
      'type': type,
      'free': free,
      'lit': lit,
      'hoops': hoops,
      'surface': surface,
      'vibe': vibe,
      // Hours legible autogenerado; OpenTime/CloseTime son la fuente
      // estructurada (mismo criterio que toNotionProperties).
      'hours': hoursLabel,
      'openTime': openTime,
      'closeTime': closeTime,
      'badges': badges.where(kAllowedBadges.contains).toList(),
      'desc': desc,
      'lat': lat,
      'lng': lng,
    };
  }

}
