import 'package:freezed_annotation/freezed_annotation.dart';

part 'models.freezed.dart';
part 'models.g.dart';

// Las credenciales (email/hash) viven SOLO en el backend: la app se autentica
// con JWT y nunca ve la base Usuarios.

/// Info pública del jugador (base Perfiles).
///
/// Inmutable, con `copyWith`/`==`/`toJson`/`fromJson` generados por freezed +
/// json_serializable. Las claves del JSON coinciden con la entidad Profile que
/// serializa el backend, así que el mismo `fromJson` sirve para el cache local
/// y para las respuestas de la API.
@freezed
abstract class Profile with _$Profile {
  const Profile._();

  const factory Profile({
    @Default('') String pageId,
    @Default('') String name,
    @Default('') String handle,
    @Default('') String phone,
    @Default('') String city,
    @Default(0.0) double lat,
    @Default(0.0) double lng,
    @Default('') String avatar,
    @Default('') String position,
    @Default(0.0) double height,
    @Default(0) int games,
    @Default(0) int courts,
    @Default(0) int streak,
    // Puntos acumulados (definen el nivel).
    @Default(0) int points,
    @Default(0.0) double rating,
    @Default('') String userEmail,
    // Fecha de nacimiento (ISO 'yyyy-MM-dd'). Se pide en el registro para
    // verificar la edad (age gate). Vacío en cuentas viejas o de Google.
    @Default('') String birthdate,
    // Insignia de clan (hasta 4 caracteres) y colores del avatar (hex de 6
    // dígitos, sin '#'). avatarColor = fondo, clanTextColor = letras.
    // Vacíos = avatar por defecto (inicial, fondo naranja, texto blanco).
    @Default('') String clan,
    @Default('') String avatarColor,
    @Default('') String clanTextColor,
    // Familia tipográfica del clan (nombre de Google Fonts). Vacío = default.
    @Default('') String clanFont,
    // Marco del avatar (id de cosmetics.kFrames). Vacío = sin marco.
    @Default('') String avatarFrame,
    // Título equipado (se desbloquea con logros). Visible para los amigos.
    @Default('') String title,
    // Nivel del jugador (según puntos). Se guarda para que lo vean los amigos.
    @Default('') String level,
    // IDs de logros desbloqueados (insignias permanentes). De acá se derivan
    // los títulos. Se persisten para que no se pierdan al reinstalar.
    @Default(<String>[]) List<String> unlockedBadges,
    // Tiempo jugado total (segundos) y desglose por cancha serializado como
    // JSON {courtId: {"n": nombre, "s": segundos}}.
    @Default(0) int playSeconds,
    @Default('') String playTimeByCourt,
    // Privacidad: qué comparte el usuario con sus amigos / en las canchas.
    @Default(false) bool shareStatus, // mostrar "Jugando" a los amigos
    @Default(false) bool shareCourt, // mostrar en qué cancha está jugando
    @Default(false) bool shareTime, // mostrar cuánto tiempo lleva jugando
    // Presencia actual (se actualiza al empezar/terminar un partido).
    @Default(false) bool playing,
    @Default('') String playingCourtId,
    @Default('') String playingSince, // ISO8601, '' si no está jugando
    // Último partido jugado (para mostrar a los amigos cuando no está jugando).
    @Default('') String lastPlayedCourtId,
    @Default('') String lastPlayedAt, // ISO8601, '' si nunca jugó
    @Default(false) bool showLastPlayed, // privacidad: mostrarlo a los amigos
    @Default(false) bool isAdmin,
  }) = _Profile;

  /// Para cachear la sesión en SharedPreferences (restauración offline).
  factory Profile.fromJson(Map<String, dynamic> json) =>
      _$ProfileFromJson(json);

  /// Texto compuesto "Base · 1.82m" para mostrar en el perfil.
  String get pos {
    final parts = <String>[];
    if (position.isNotEmpty) parts.add(position);
    if (height > 0) parts.add('${height.toStringAsFixed(2)}m');
    return parts.join(' · ');
  }

}

/// Reseña de una cancha (base Reseñas).
class Review {
  final String pageId;
  final String courtId;
  final String userEmail;
  final String userHandle;
  final double rating;
  final String comment;
  final String? createdAt;

  const Review({
    this.pageId = '',
    required this.courtId,
    required this.userEmail,
    this.userHandle = '',
    required this.rating,
    required this.comment,
    this.createdAt,
  });

  /// Desde el JSON plano del backend (shape de entities.ts).
  factory Review.fromApi(Map<String, dynamic> json) {
    return Review(
      pageId: json['pageId'] as String? ?? '',
      courtId: json['courtId'] as String? ?? '',
      userEmail: json['userEmail'] as String? ?? '',
      userHandle: json['userHandle'] as String? ?? '',
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      comment: json['comment'] as String? ?? '',
      createdAt: json['createdAt'] as String?,
    );
  }

}

/// Publicación en el feed de una cancha.
class CourtPost {
  final String pageId;
  final String courtId;
  final String userEmail;
  final String userHandle;
  final String content;
  final String? createdAt;
  final int likeCount;
  final bool likedByMe;
  final List<PostComment> comments;

  const CourtPost({
    this.pageId = '',
    required this.courtId,
    required this.userEmail,
    this.userHandle = '',
    required this.content,
    this.createdAt,
    this.likeCount = 0,
    this.likedByMe = false,
    this.comments = const [],
  });

  factory CourtPost.fromApi(Map<String, dynamic> json) {
    return CourtPost(
      pageId: json['pageId'] as String? ?? '',
      courtId: json['courtId'] as String? ?? '',
      userEmail: json['userEmail'] as String? ?? '',
      userHandle: json['userHandle'] as String? ?? '',
      content: json['content'] as String? ?? '',
      createdAt: json['createdAt'] as String?,
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      likedByMe: json['likedByMe'] as bool? ?? false,
      comments: (json['comments'] as List<dynamic>?)
              ?.map((c) => PostComment.fromApi(c as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}

/// Comentario en una publicación de cancha.
class PostComment {
  final String pageId;
  final String postId;
  final String userEmail;
  final String userHandle;
  final String content;
  final String? createdAt;
  final int likeCount;
  final bool likedByMe;

  const PostComment({
    this.pageId = '',
    required this.postId,
    required this.userEmail,
    this.userHandle = '',
    required this.content,
    this.createdAt,
    this.likeCount = 0,
    this.likedByMe = false,
  });

  factory PostComment.fromApi(Map<String, dynamic> json) {
    return PostComment(
      pageId: json['pageId'] as String? ?? '',
      postId: json['postId'] as String? ?? '',
      userEmail: json['userEmail'] as String? ?? '',
      userHandle: json['userHandle'] as String? ?? '',
      content: json['content'] as String? ?? '',
      createdAt: json['createdAt'] as String?,
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      likedByMe: json['likedByMe'] as bool? ?? false,
    );
  }
}

/// Amistad (base Amistades). Relación unidireccional: el dueño (owner) agregó
/// a un amigo. No requiere aceptación del otro usuario.
class Friend {
  final String pageId;
  final String ownerEmail;
  final String friendHandle;
  final String friendName;
  final String friendEmail;

  const Friend({
    this.pageId = '',
    required this.ownerEmail,
    required this.friendHandle,
    required this.friendName,
    required this.friendEmail,
  });

  /// Desde el JSON plano del backend.
  factory Friend.fromApi(Map<String, dynamic> json) {
    return Friend(
      pageId: json['pageId'] as String? ?? '',
      ownerEmail: json['ownerEmail'] as String? ?? '',
      friendHandle: json['friendHandle'] as String? ?? '',
      friendName: json['friendName'] as String? ?? '',
      friendEmail: json['friendEmail'] as String? ?? '',
    );
  }

}

/// Partido / pickup (base Partidos).
class Pickup {
  final String pageId;
  final String title;
  final String courtId;
  final String createdBy;
  final String? dateTime;
  final int maxPlayers;
  final String vibe;
  final String notes;
  final int teamSize;
  final String teamAName;
  final String teamBName;
  final String teamAColor;
  final String teamBColor;
  final List<String> teamAMembers;
  final List<String> teamBMembers;
  final int targetScore;

  /// Emails que ACEPTARON la invitación (subconjunto de los miembros asignados).
  final List<String> acceptedMembers;

  /// Emails que RECHAZARON la invitación.
  final List<String> declinedMembers;

  /// Código de 5 dígitos para unirse al pickup. Solo lo ve el creador (en el
  /// chat del pickup) y se valida server-side al unirse.
  final String inviteCode;

  const Pickup({
    this.pageId = '',
    required this.title,
    required this.courtId,
    required this.createdBy,
    this.dateTime,
    this.maxPlayers = 10,
    this.vibe = 'Casual',
    this.notes = '',
    this.teamSize = 3,
    this.teamAName = 'Equipo A',
    this.teamBName = 'Equipo B',
    this.teamAColor = '#FF6B1A',
    this.teamBColor = '#3B82F6',
    this.teamAMembers = const [],
    this.teamBMembers = const [],
    this.targetScore = 21,
    this.acceptedMembers = const [],
    this.declinedMembers = const [],
    this.inviteCode = '',
  });

  /// Todos los invitados (miembros asignados a cualquier equipo).
  List<String> get invitedMembers => [...teamAMembers, ...teamBMembers];

  /// Equipo asignado a un email: 'A', 'B' o null si no está invitado.
  String? teamOf(String email) {
    final e = email.trim().toLowerCase();
    if (teamAMembers.any((m) => m.trim().toLowerCase() == e)) return 'A';
    if (teamBMembers.any((m) => m.trim().toLowerCase() == e)) return 'B';
    return null;
  }

  bool hasAccepted(String email) {
    final e = email.trim().toLowerCase();
    return acceptedMembers.any((m) => m.trim().toLowerCase() == e);
  }

  bool hasDeclined(String email) {
    final e = email.trim().toLowerCase();
    return declinedMembers.any((m) => m.trim().toLowerCase() == e);
  }

  bool isCreator(String email) =>
      createdBy.trim().toLowerCase() == email.trim().toLowerCase();

  /// True si ya pasaron 24h desde la fecha/hora del pickup (regla de retención:
  /// el pickup y su chat se eliminan de la BDD un día después del partido).
  /// Sin fecha parseable no expira (mejor mostrar de más que borrar de más).
  bool get isExpired {
    final d = DateTime.tryParse(dateTime ?? '');
    if (d == null) return false;
    return DateTime.now().isAfter(d.add(const Duration(hours: 24)));
  }

  Pickup copyWith({
    List<String>? teamAMembers,
    List<String>? teamBMembers,
    List<String>? acceptedMembers,
    List<String>? declinedMembers,
  }) {
    return Pickup(
      pageId: pageId,
      title: title,
      courtId: courtId,
      createdBy: createdBy,
      dateTime: dateTime,
      maxPlayers: maxPlayers,
      vibe: vibe,
      notes: notes,
      teamSize: teamSize,
      teamAName: teamAName,
      teamBName: teamBName,
      teamAColor: teamAColor,
      teamBColor: teamBColor,
      teamAMembers: teamAMembers ?? this.teamAMembers,
      teamBMembers: teamBMembers ?? this.teamBMembers,
      targetScore: targetScore,
      acceptedMembers: acceptedMembers ?? this.acceptedMembers,
      declinedMembers: declinedMembers ?? this.declinedMembers,
      inviteCode: inviteCode,
    );
  }

  /// Desde el JSON plano del backend (los members ya vienen como listas).
  factory Pickup.fromApi(Map<String, dynamic> json) {
    List<String> strs(dynamic v) =>
        v is List ? v.map((e) => e.toString()).toList() : const [];
    String str(dynamic v, String fallback) {
      final s = (v ?? '').toString();
      return s.isEmpty ? fallback : s;
    }

    return Pickup(
      pageId: json['pageId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      courtId: json['courtId'] as String? ?? '',
      createdBy: json['createdBy'] as String? ?? '',
      dateTime: json['dateTime'] as String?,
      maxPlayers: (json['maxPlayers'] as num?)?.toInt() ?? 10,
      vibe: str(json['vibe'], 'Casual'),
      notes: json['notes'] as String? ?? '',
      teamSize: (json['teamSize'] as num?)?.toInt() ?? 3,
      teamAName: str(json['teamAName'], 'Equipo A'),
      teamBName: str(json['teamBName'], 'Equipo B'),
      teamAColor: str(json['teamAColor'], '#FF6B1A'),
      teamBColor: str(json['teamBColor'], '#3B82F6'),
      teamAMembers: strs(json['teamAMembers']),
      teamBMembers: strs(json['teamBMembers']),
      targetScore: (json['targetScore'] as num?)?.toInt() ?? 21,
      acceptedMembers: strs(json['acceptedMembers']),
      declinedMembers: strs(json['declinedMembers']),
      inviteCode: json['inviteCode'] as String? ?? '',
    );
  }

  /// Payload para crear/actualizar en el backend. `createdBy` e `inviteCode`
  /// los maneja el server (salen del token / se generan); `courtId` solo
  /// aplica al crear (en updates el server lo ignora).
  Map<String, dynamic> toApiJson() {
    return {
      'title': title,
      'courtId': courtId,
      if (dateTime != null && dateTime!.isNotEmpty) 'dateTime': dateTime,
      'maxPlayers': maxPlayers,
      'vibe': vibe,
      'notes': notes,
      'teamSize': teamSize,
      'teamAName': teamAName,
      'teamBName': teamBName,
      'teamAColor': teamAColor,
      'teamBColor': teamBColor,
      'teamAMembers': teamAMembers,
      'teamBMembers': teamBMembers,
      'targetScore': targetScore,
      'acceptedMembers': acceptedMembers,
      'declinedMembers': declinedMembers,
    };
  }

}

/// Un mensaje del chat de un pickup (server-backed). El autor se identifica por
/// email; la UI resuelve nombre/insignia contra los perfiles que ya tiene.
class ChatMessage {
  final String id;
  final String email;
  final String text;
  final String createdAt; // ISO del server
  final int createdAtMillis;

  const ChatMessage({
    required this.id,
    required this.email,
    required this.text,
    required this.createdAt,
    required this.createdAtMillis,
  });

  factory ChatMessage.fromApi(Map<String, dynamic> json) {
    final iso = (json['createdAt'] ?? '').toString();
    return ChatMessage(
      id: (json['id'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
      createdAt: iso,
      createdAtMillis: DateTime.tryParse(iso)?.millisecondsSinceEpoch ?? 0,
    );
  }
}

/// Chat de crew generado al crear un pickup game.
class CrewChat {
  final String pageId;
  final String name;
  final String pickupId;
  final String createdBy;
  final String date;
  final String teamAName;
  final String teamBName;
  final String teamAColor;
  final String teamBColor;
  final String lastMessage;
  final int createdAtMillis;

  const CrewChat({
    this.pageId = '',
    required this.name,
    this.pickupId = '',
    required this.createdBy,
    this.date = '',
    this.teamAName = 'Equipo A',
    this.teamBName = 'Equipo B',
    this.teamAColor = '#FF6B1A',
    this.teamBColor = '#3B82F6',
    this.lastMessage = '',
    this.createdAtMillis = 0,
  });

  /// Desde el JSON plano del backend (`date` puede venir null).
  factory CrewChat.fromApi(Map<String, dynamic> json) {
    String str(dynamic v, String fallback) {
      final s = (v ?? '').toString();
      return s.isEmpty ? fallback : s;
    }

    return CrewChat(
      pageId: json['pageId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      pickupId: json['pickupId'] as String? ?? '',
      createdBy: json['createdBy'] as String? ?? '',
      date: json['date'] as String? ?? '',
      teamAName: str(json['teamAName'], 'Equipo A'),
      teamBName: str(json['teamBName'], 'Equipo B'),
      teamAColor: str(json['teamAColor'], '#FF6B1A'),
      teamBColor: str(json['teamBColor'], '#3B82F6'),
      lastMessage: json['lastMessage'] as String? ?? '',
    );
  }

  /// Payload para POST /chats (`createdBy` sale del token en el server).
  Map<String, dynamic> toApiJson() {
    return {
      'name': name,
      'pickupId': pickupId,
      if (date.isNotEmpty) 'date': date,
      'teamAName': teamAName,
      'teamBName': teamBName,
      'teamAColor': teamAColor,
      'teamBColor': teamBColor,
      'lastMessage': lastMessage,
    };
  }

  factory CrewChat.fromJson(Map<String, dynamic> json) {
    return CrewChat(
      pageId: json['pageId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      pickupId: json['pickupId'] as String? ?? '',
      createdBy: json['createdBy'] as String? ?? '',
      date: json['date'] as String? ?? '',
      teamAName: json['teamAName'] as String? ?? 'Equipo A',
      teamBName: json['teamBName'] as String? ?? 'Equipo B',
      teamAColor: json['teamAColor'] as String? ?? '#FF6B1A',
      teamBColor: json['teamBColor'] as String? ?? '#3B82F6',
      lastMessage: json['lastMessage'] as String? ?? '',
      createdAtMillis: json['createdAtMillis'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pageId': pageId,
      'name': name,
      'pickupId': pickupId,
      'createdBy': createdBy,
      'date': date,
      'teamAName': teamAName,
      'teamBName': teamBName,
      'teamAColor': teamAColor,
      'teamBColor': teamBColor,
      'lastMessage': lastMessage,
      'createdAtMillis': createdAtMillis,
    };
  }
}
