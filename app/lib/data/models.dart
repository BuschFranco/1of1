import 'package:freezed_annotation/freezed_annotation.dart';
import '../services/notion_service.dart';

part 'models.freezed.dart';
part 'models.g.dart';

/// Credenciales (base Usuarios). La contraseña se guarda hasheada.
class AppUser {
  final String pageId;
  final String email;
  final String passwordHash;
  final String profileId;
  final bool isAdmin;

  const AppUser({
    required this.pageId,
    required this.email,
    required this.passwordHash,
    required this.profileId,
    this.isAdmin = false,
  });

  factory AppUser.fromNotion(Map<String, dynamic> page) {
    final p = page['properties'] as Map<String, dynamic>;
    return AppUser(
      pageId: page['id']?.toString() ?? '',
      email: NotionService.readTitle(p, 'Email'),
      passwordHash: NotionService.readText(p, 'PasswordHash'),
      profileId: NotionService.readText(p, 'ProfileId'),
      isAdmin: NotionService.readCheckbox(p, 'Adm'),
    );
  }
}

/// Info pública del jugador (base Perfiles).
///
/// Inmutable, con `copyWith`/`==`/`toJson`/`fromJson` generados por freezed +
/// json_serializable. El mapeo desde/hacia Notion (`fromNotion`/
/// `toNotionProperties`) se mantiene manual porque usa nombres de propiedad y
/// lectores propios de Notion que no calzan con la serialización por defecto.
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

  factory Profile.fromNotion(Map<String, dynamic> page) {
    final p = page['properties'] as Map<String, dynamic>;
    return Profile(
      pageId: page['id']?.toString() ?? '',
      name: NotionService.readTitle(p, 'Name'),
      handle: NotionService.readText(p, 'Handle'),
      phone: NotionService.readPhone(p, 'Phone'),
      city: NotionService.readText(p, 'City'),
      lat: NotionService.readNumber(p, 'Lat'),
      lng: NotionService.readNumber(p, 'Lng'),
      avatar: NotionService.readUrl(p, 'Avatar'),
      position: NotionService.readSelect(p, 'Position'),
      height: NotionService.readNumber(p, 'Height'),
      games: NotionService.readInt(p, 'Games'),
      courts: NotionService.readInt(p, 'Courts'),
      streak: NotionService.readInt(p, 'Streak'),
      points: NotionService.readInt(p, 'Points'),
      rating: NotionService.readNumber(p, 'Rating'),
      userEmail: NotionService.readText(p, 'UserEmail'),
      clan: NotionService.readText(p, 'Clan'),
      avatarColor: NotionService.readText(p, 'AvatarColor'),
      clanTextColor: NotionService.readText(p, 'ClanTextColor'),
      clanFont: NotionService.readText(p, 'ClanFont'),
      avatarFrame: NotionService.readText(p, 'AvatarFrame'),
      title: NotionService.readText(p, 'EquippedTitle'),
      level: NotionService.readText(p, 'Level'),
      unlockedBadges: NotionService.readMultiSelect(p, 'UnlockedBadges'),
      playSeconds: NotionService.readInt(p, 'PlaySeconds'),
      playTimeByCourt: NotionService.readText(p, 'PlayTimeByCourt'),
      shareStatus: NotionService.readCheckbox(p, 'ShareStatus'),
      shareCourt: NotionService.readCheckbox(p, 'ShareCourt'),
      shareTime: NotionService.readCheckbox(p, 'ShareTime'),
      playing: NotionService.readCheckbox(p, 'Playing'),
      playingCourtId: NotionService.readText(p, 'PlayingCourtId'),
      playingSince: NotionService.readDate(p, 'PlayingSince') ?? '',
      lastPlayedCourtId: NotionService.readText(p, 'LastPlayedCourtId'),
      lastPlayedAt: NotionService.readDate(p, 'LastPlayedAt') ?? '',
      showLastPlayed: NotionService.readCheckbox(p, 'ShowLastPlayed'),
      isAdmin: NotionService.readCheckbox(p, 'Adm'),
    );
  }

  Map<String, dynamic> toNotionProperties() {
    return {
      'Name': NotionService.title(name),
      'Handle': NotionService.richText(handle),
      'Phone': NotionService.phone(phone),
      'City': NotionService.richText(city),
      'Lat': NotionService.number(lat),
      'Lng': NotionService.number(lng),
      'Avatar': NotionService.url(avatar),
      'Position': NotionService.select(position),
      'Height': NotionService.number(height),
      'Games': NotionService.number(games),
      'Courts': NotionService.number(courts),
      'Streak': NotionService.number(streak),
      'Points': NotionService.number(points),
      'Rating': NotionService.number(rating),
      'UserEmail': NotionService.richText(userEmail),
      'Clan': NotionService.richText(clan),
      'AvatarColor': NotionService.richText(avatarColor),
      'ClanTextColor': NotionService.richText(clanTextColor),
      'ClanFont': NotionService.richText(clanFont),
      'AvatarFrame': NotionService.richText(avatarFrame),
      'EquippedTitle': NotionService.richText(title),
      'Level': NotionService.richText(level),
      'UnlockedBadges': NotionService.multiSelect(unlockedBadges),
      'PlaySeconds': NotionService.number(playSeconds),
      'PlayTimeByCourt': NotionService.richText(playTimeByCourt),
      'ShareStatus': NotionService.checkbox(shareStatus),
      'ShareCourt': NotionService.checkbox(shareCourt),
      'ShareTime': NotionService.checkbox(shareTime),
      'Playing': NotionService.checkbox(playing),
      'PlayingCourtId': NotionService.richText(playingCourtId),
      'PlayingSince':
          NotionService.date(playingSince.isEmpty ? null : playingSince),
      'LastPlayedCourtId': NotionService.richText(lastPlayedCourtId),
      'LastPlayedAt':
          NotionService.date(lastPlayedAt.isEmpty ? null : lastPlayedAt),
      'ShowLastPlayed': NotionService.checkbox(showLastPlayed),
      'Adm': NotionService.checkbox(isAdmin),
    };
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

  factory Review.fromNotion(Map<String, dynamic> page) {
    final p = page['properties'] as Map<String, dynamic>;
    return Review(
      pageId: page['id']?.toString() ?? '',
      courtId: NotionService.readText(p, 'CourtId'),
      userEmail: NotionService.readText(p, 'UserEmail'),
      userHandle: NotionService.readText(p, 'UserHandle'),
      rating: NotionService.readNumber(p, 'Rating'),
      comment: NotionService.readText(p, 'Comment'),
      createdAt: NotionService.readDate(p, 'CreatedAt'),
    );
  }

  Map<String, dynamic> toNotionProperties() {
    return {
      'Title': NotionService.title('$userEmail → $courtId'),
      'CourtId': NotionService.richText(courtId),
      'UserEmail': NotionService.richText(userEmail),
      'UserHandle': NotionService.richText(userHandle),
      'Rating': NotionService.number(rating),
      'Comment': NotionService.richText(comment),
      'CreatedAt': NotionService.date(createdAt),
    };
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

  factory Friend.fromNotion(Map<String, dynamic> page) {
    final p = page['properties'] as Map<String, dynamic>;
    return Friend(
      pageId: page['id']?.toString() ?? '',
      ownerEmail: NotionService.readText(p, 'OwnerEmail'),
      friendHandle: NotionService.readText(p, 'FriendHandle'),
      friendName: NotionService.readText(p, 'FriendName'),
      friendEmail: NotionService.readText(p, 'FriendEmail'),
    );
  }

  Map<String, dynamic> toNotionProperties() {
    return {
      'Title': NotionService.title('$ownerEmail → $friendHandle'),
      'OwnerEmail': NotionService.richText(ownerEmail),
      'FriendHandle': NotionService.richText(friendHandle),
      'FriendName': NotionService.richText(friendName),
      'FriendEmail': NotionService.richText(friendEmail),
      'CreatedAt': NotionService.date(DateTime.now().toIso8601String()),
    };
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
    );
  }

  factory Pickup.fromNotion(Map<String, dynamic> page) {
    final p = page['properties'] as Map<String, dynamic>;
    final rawA = NotionService.readText(p, 'TeamAMembers');
    final rawB = NotionService.readText(p, 'TeamBMembers');
    final rawAcc = NotionService.readText(p, 'AcceptedMembers');
    final rawDec = NotionService.readText(p, 'DeclinedMembers');
    return Pickup(
      pageId: page['id']?.toString() ?? '',
      title: NotionService.readTitle(p, 'Title'),
      courtId: NotionService.readText(p, 'CourtId'),
      createdBy: NotionService.readText(p, 'CreatedBy'),
      dateTime: NotionService.readDate(p, 'DateTime'),
      maxPlayers: NotionService.readInt(p, 'MaxPlayers', fallback: 10),
      vibe: NotionService.readSelect(p, 'Vibe', fallback: 'Casual'),
      notes: NotionService.readText(p, 'Notes'),
      teamSize: NotionService.readInt(p, 'TeamSize', fallback: 3),
      teamAName: NotionService.readText(p, 'TeamAName').isEmpty ? 'Equipo A' : NotionService.readText(p, 'TeamAName'),
      teamBName: NotionService.readText(p, 'TeamBName').isEmpty ? 'Equipo B' : NotionService.readText(p, 'TeamBName'),
      teamAColor: NotionService.readText(p, 'TeamAColor').isEmpty ? '#FF6B1A' : NotionService.readText(p, 'TeamAColor'),
      teamBColor: NotionService.readText(p, 'TeamBColor').isEmpty ? '#3B82F6' : NotionService.readText(p, 'TeamBColor'),
      teamAMembers: rawA.isEmpty ? [] : rawA.split(',').where((e) => e.isNotEmpty).toList(),
      teamBMembers: rawB.isEmpty ? [] : rawB.split(',').where((e) => e.isNotEmpty).toList(),
      targetScore: NotionService.readInt(p, 'TargetScore', fallback: 21),
      acceptedMembers: rawAcc.isEmpty ? [] : rawAcc.split(',').where((e) => e.isNotEmpty).toList(),
      declinedMembers: rawDec.isEmpty ? [] : rawDec.split(',').where((e) => e.isNotEmpty).toList(),
    );
  }

  Map<String, dynamic> toNotionProperties() {
    return {
      'Title': NotionService.title(title),
      'CourtId': NotionService.richText(courtId),
      'CreatedBy': NotionService.richText(createdBy),
      'DateTime': NotionService.date(dateTime),
      'MaxPlayers': NotionService.number(maxPlayers),
      'Vibe': NotionService.select(vibe),
      'Notes': NotionService.richText(notes),
      'TeamSize': NotionService.number(teamSize),
      'TeamAName': NotionService.richText(teamAName),
      'TeamBName': NotionService.richText(teamBName),
      'TeamAColor': NotionService.richText(teamAColor),
      'TeamBColor': NotionService.richText(teamBColor),
      'TeamAMembers': NotionService.richText(teamAMembers.join(',')),
      'TeamBMembers': NotionService.richText(teamBMembers.join(',')),
      'TargetScore': NotionService.number(targetScore),
      'AcceptedMembers': NotionService.richText(acceptedMembers.join(',')),
      'DeclinedMembers': NotionService.richText(declinedMembers.join(',')),
    };
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

  factory CrewChat.fromNotion(Map<String, dynamic> page) {
    final p = page['properties'] as Map<String, dynamic>;
    return CrewChat(
      pageId: page['id']?.toString() ?? '',
      name: NotionService.readTitle(p, 'Name'),
      pickupId: NotionService.readText(p, 'PickupId'),
      createdBy: NotionService.readText(p, 'CreatedBy'),
      date: NotionService.readDate(p, 'Date') ?? '',
      teamAName: NotionService.readText(p, 'TeamAName').isEmpty
          ? 'Equipo A'
          : NotionService.readText(p, 'TeamAName'),
      teamBName: NotionService.readText(p, 'TeamBName').isEmpty
          ? 'Equipo B'
          : NotionService.readText(p, 'TeamBName'),
      teamAColor: NotionService.readText(p, 'TeamAColor').isEmpty
          ? '#FF6B1A'
          : NotionService.readText(p, 'TeamAColor'),
      teamBColor: NotionService.readText(p, 'TeamBColor').isEmpty
          ? '#3B82F6'
          : NotionService.readText(p, 'TeamBColor'),
      lastMessage: NotionService.readText(p, 'LastMessage'),
    );
  }

  Map<String, dynamic> toNotionProperties() {
    return {
      'Name': NotionService.title(name),
      'PickupId': NotionService.richText(pickupId),
      'CreatedBy': NotionService.richText(createdBy),
      'Date': NotionService.date(date.isEmpty ? null : date),
      'TeamAName': NotionService.richText(teamAName),
      'TeamBName': NotionService.richText(teamBName),
      'TeamAColor': NotionService.richText(teamAColor),
      'TeamBColor': NotionService.richText(teamBColor),
      'LastMessage': NotionService.richText(lastMessage),
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
