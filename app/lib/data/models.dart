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

  const AppUser({
    required this.pageId,
    required this.email,
    required this.passwordHash,
    required this.profileId,
  });

  factory AppUser.fromNotion(Map<String, dynamic> page) {
    final p = page['properties'] as Map<String, dynamic>;
    return AppUser(
      pageId: page['id']?.toString() ?? '',
      email: NotionService.readTitle(p, 'Email'),
      passwordHash: NotionService.readText(p, 'PasswordHash'),
      profileId: NotionService.readText(p, 'ProfileId'),
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
    };
  }
}

/// Reseña de una cancha (base Reseñas).
class Review {
  final String pageId;
  final String courtId;
  final String userEmail;
  final double rating;
  final String comment;
  final String? createdAt;

  const Review({
    this.pageId = '',
    required this.courtId,
    required this.userEmail,
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

  const Pickup({
    this.pageId = '',
    required this.title,
    required this.courtId,
    required this.createdBy,
    this.dateTime,
    this.maxPlayers = 10,
    this.vibe = 'Casual',
    this.notes = '',
  });

  factory Pickup.fromNotion(Map<String, dynamic> page) {
    final p = page['properties'] as Map<String, dynamic>;
    return Pickup(
      pageId: page['id']?.toString() ?? '',
      title: NotionService.readTitle(p, 'Title'),
      courtId: NotionService.readText(p, 'CourtId'),
      createdBy: NotionService.readText(p, 'CreatedBy'),
      dateTime: NotionService.readDate(p, 'DateTime'),
      maxPlayers: NotionService.readInt(p, 'MaxPlayers', fallback: 10),
      vibe: NotionService.readSelect(p, 'Vibe', fallback: 'Casual'),
      notes: NotionService.readText(p, 'Notes'),
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
    };
  }
}
