import '../services/notion_service.dart';

enum CourtStatus { open, busy, closed }

CourtStatus _statusFromString(String s) => switch (s) {
      'busy' => CourtStatus.busy,
      'closed' => CourtStatus.closed,
      _ => CourtStatus.open,
    };

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
  final CourtStatus status;
  final int players;
  final String vibe;
  final String hours;
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
    required this.status,
    required this.players,
    required this.vibe,
    required this.hours,
    required this.badges,
    required this.desc,
    required this.lat,
    required this.lng,
    this.proposedBy = '',
    this.proposedByClan = '',
    this.proposedByEmail = '',
  });

  String get statusName => switch (status) {
        CourtStatus.busy => 'busy',
        CourtStatus.closed => 'closed',
        CourtStatus.open => 'open',
      };

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
      status: _statusFromString(NotionService.readSelect(p, 'Status', fallback: 'open')),
      players: NotionService.readInt(p, 'Players'),
      vibe: NotionService.readSelect(p, 'Vibe', fallback: 'Casual'),
      hours: NotionService.readText(p, 'Hours'),
      badges: NotionService.readMultiSelect(p, 'Badges'),
      desc: NotionService.readText(p, 'Desc'),
      lat: NotionService.readNumber(p, 'Lat'),
      lng: NotionService.readNumber(p, 'Lng'),
      proposedBy: NotionService.readText(p, 'CreatedBy'),
      proposedByClan: NotionService.readText(p, 'CreatedByClan'),
      proposedByEmail: NotionService.readText(p, 'CreatedByEmail'),
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
      'Status': NotionService.select(statusName),
      'Players': NotionService.number(players),
      'Vibe': NotionService.select(vibe),
      'Hours': NotionService.richText(hours),
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

const List<Court> kCourts = [
  Court(
    id: 'parq-lez',
    name: 'Parque Lezama',
    area: 'San Telmo',
    dist: '0.4 km',
    img: 'https://images.unsplash.com/photo-1546519638-68e109498ffc?w=800&q=80',
    rating: 4.8,
    reviews: 142,
    type: 'Exterior',
    free: true,
    lit: true,
    hoops: 4,
    surface: 'Asfalto',
    status: CourtStatus.open,
    players: 8,
    vibe: 'Competitivo',
    hours: '06:00 — 23:00',
    badges: ['Iluminada', 'Gratis', 'Popular'],
    desc: 'Cancha clásica del barrio con buena iluminación nocturna. Se arman pickups todos los martes y jueves.',
    lat: -34.6260,
    lng: -58.3699,
  ),
  Court(
    id: 'poly-nort',
    name: 'Polideportivo Norte',
    area: 'Belgrano',
    dist: '1.2 km',
    img: 'https://images.unsplash.com/photo-1504450758481-7338eba7524a?w=800&q=80',
    rating: 4.9,
    reviews: 389,
    type: 'Interior',
    free: false,
    lit: true,
    hoops: 2,
    surface: 'Parquet',
    status: CourtStatus.open,
    players: 12,
    vibe: 'Entrenamiento',
    hours: '07:00 — 22:00',
    badges: ['Parquet', 'Reserva', 'Vestuarios'],
    desc: 'Cancha reglamentaria FIBA con parquet profesional. Se alquila por hora con reserva previa.',
    lat: -34.5573,
    lng: -58.4495,
  ),
  Court(
    id: 'plaza-arm',
    name: 'Plaza Armenia',
    area: 'Palermo',
    dist: '2.1 km',
    img: 'https://images.unsplash.com/photo-1577416412292-747c6607f055?w=800&q=80',
    rating: 4.5,
    reviews: 87,
    type: 'Exterior',
    free: true,
    lit: false,
    hoops: 2,
    surface: 'Cemento',
    status: CourtStatus.open,
    players: 5,
    vibe: 'Casual',
    hours: 'Abierto 24h',
    badges: ['Gratis', 'Casual'],
    desc: 'Ambiente relajado, ideal para tirar un rato. Sin luces, se juega hasta el atardecer.',
    lat: -34.5886,
    lng: -58.4226,
  ),
  Court(
    id: 'club-river',
    name: 'Club Atletico River',
    area: 'Núñez',
    dist: '3.8 km',
    img: 'https://images.unsplash.com/photo-1608245449230-4ac19066d2d0?w=800&q=80',
    rating: 4.7,
    reviews: 231,
    type: 'Interior',
    free: false,
    lit: true,
    hoops: 6,
    surface: 'Parquet',
    status: CourtStatus.busy,
    players: 24,
    vibe: 'Profesional',
    hours: '08:00 — 23:00',
    badges: ['Profesional', 'Parquet', 'Torneos'],
    desc: 'Complejo con 3 canchas. Liga interna los fines de semana.',
    lat: -34.5452,
    lng: -58.4500,
  ),
  Court(
    id: 'patio-bom',
    name: 'Patio Bombonera',
    area: 'La Boca',
    dist: '4.5 km',
    img: 'https://images.unsplash.com/photo-1520975916090-3105956dac38?w=800&q=80',
    rating: 4.3,
    reviews: 54,
    type: 'Exterior',
    free: true,
    lit: true,
    hoops: 2,
    surface: 'Asfalto',
    status: CourtStatus.open,
    players: 3,
    vibe: 'Callejero',
    hours: '06:00 — 00:00',
    badges: ['Street', 'Gratis', 'Iluminada'],
    desc: 'Streetball puro. Asfalto gastado con historia.',
    lat: -34.6358,
    lng: -58.3624,
  ),
];
