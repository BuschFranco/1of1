import '../services/notion_service.dart';

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
class Profile {
  final String pageId;
  final String name;
  final String handle;
  final String phone;
  final String city;
  final double lat;
  final double lng;
  final String avatar;
  final String position;
  final double height;
  final int games;
  final int courts;
  final int streak;
  final double rating;
  final String userEmail;
  // Insignia de clan (hasta 4 caracteres) y colores del avatar (hex de 6
  // dígitos, sin '#'). avatarColor = fondo, clanTextColor = letras.
  // Vacíos = avatar por defecto (inicial, fondo naranja, texto blanco).
  final String clan;
  final String avatarColor;
  final String clanTextColor;
  // Familia tipográfica del clan (nombre de Google Fonts). Vacío = default.
  final String clanFont;
  // Título equipado (se desbloquea con logros). Visible para los amigos.
  final String title;
  // Nivel del jugador (según puntos). Se guarda para que lo vean los amigos.
  final String level;

  // Privacidad: qué comparte el usuario con sus amigos / en las canchas.
  final bool shareStatus; // mostrar "Jugando" a los amigos
  final bool shareCourt; // mostrar en qué cancha está jugando
  final bool shareTime; // mostrar cuánto tiempo lleva jugando
  // Presencia actual (se actualiza al empezar/terminar un partido).
  final bool playing;
  final String playingCourtId;
  final String playingSince; // ISO8601, '' si no está jugando

  const Profile({
    this.pageId = '',
    required this.name,
    this.handle = '',
    this.phone = '',
    this.city = '',
    this.lat = 0,
    this.lng = 0,
    this.avatar = '',
    this.position = '',
    this.height = 0,
    this.games = 0,
    this.courts = 0,
    this.streak = 0,
    this.rating = 0,
    this.userEmail = '',
    this.clan = '',
    this.avatarColor = '',
    this.clanTextColor = '',
    this.clanFont = '',
    this.title = '',
    this.level = '',
    this.shareStatus = false,
    this.shareCourt = false,
    this.shareTime = false,
    this.playing = false,
    this.playingCourtId = '',
    this.playingSince = '',
  });

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
      rating: NotionService.readNumber(p, 'Rating'),
      userEmail: NotionService.readText(p, 'UserEmail'),
      clan: NotionService.readText(p, 'Clan'),
      avatarColor: NotionService.readText(p, 'AvatarColor'),
      clanTextColor: NotionService.readText(p, 'ClanTextColor'),
      clanFont: NotionService.readText(p, 'ClanFont'),
      title: NotionService.readText(p, 'EquippedTitle'),
      level: NotionService.readText(p, 'Level'),
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
      'Rating': NotionService.number(rating),
      'UserEmail': NotionService.richText(userEmail),
      'Clan': NotionService.richText(clan),
      'AvatarColor': NotionService.richText(avatarColor),
      'ClanTextColor': NotionService.richText(clanTextColor),
      'ClanFont': NotionService.richText(clanFont),
      'EquippedTitle': NotionService.richText(title),
      'Level': NotionService.richText(level),
      'ShareStatus': NotionService.checkbox(shareStatus),
      'ShareCourt': NotionService.checkbox(shareCourt),
      'ShareTime': NotionService.checkbox(shareTime),
      'Playing': NotionService.checkbox(playing),
      'PlayingCourtId': NotionService.richText(playingCourtId),
      'PlayingSince':
          NotionService.date(playingSince.isEmpty ? null : playingSince),
    };
  }

  Profile copyWith({
    String? name,
    String? handle,
    String? phone,
    String? city,
    String? position,
    double? height,
    String? avatar,
    String? clan,
    String? avatarColor,
    String? clanTextColor,
    String? clanFont,
    String? title,
    String? level,
    bool? shareStatus,
    bool? shareCourt,
    bool? shareTime,
    bool? playing,
    String? playingCourtId,
    String? playingSince,
  }) {
    return Profile(
      pageId: pageId,
      name: name ?? this.name,
      handle: handle ?? this.handle,
      phone: phone ?? this.phone,
      city: city ?? this.city,
      lat: lat,
      lng: lng,
      avatar: avatar ?? this.avatar,
      position: position ?? this.position,
      height: height ?? this.height,
      games: games,
      courts: courts,
      streak: streak,
      rating: rating,
      userEmail: userEmail,
      clan: clan ?? this.clan,
      avatarColor: avatarColor ?? this.avatarColor,
      clanTextColor: clanTextColor ?? this.clanTextColor,
      clanFont: clanFont ?? this.clanFont,
      title: title ?? this.title,
      level: level ?? this.level,
      shareStatus: shareStatus ?? this.shareStatus,
      shareCourt: shareCourt ?? this.shareCourt,
      shareTime: shareTime ?? this.shareTime,
      playing: playing ?? this.playing,
      playingCourtId: playingCourtId ?? this.playingCourtId,
      playingSince: playingSince ?? this.playingSince,
    );
  }

  /// Para cachear la sesión en SharedPreferences (restauración offline).
  Map<String, dynamic> toJson() => {
        'pageId': pageId,
        'name': name,
        'handle': handle,
        'phone': phone,
        'city': city,
        'lat': lat,
        'lng': lng,
        'avatar': avatar,
        'position': position,
        'height': height,
        'games': games,
        'courts': courts,
        'streak': streak,
        'rating': rating,
        'userEmail': userEmail,
        'clan': clan,
        'avatarColor': avatarColor,
        'clanTextColor': clanTextColor,
        'clanFont': clanFont,
        'title': title,
        'level': level,
        'shareStatus': shareStatus,
        'shareCourt': shareCourt,
        'shareTime': shareTime,
        'playing': playing,
        'playingCourtId': playingCourtId,
        'playingSince': playingSince,
      };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        pageId: j['pageId'] ?? '',
        name: j['name'] ?? '',
        handle: j['handle'] ?? '',
        phone: j['phone'] ?? '',
        city: j['city'] ?? '',
        lat: (j['lat'] ?? 0).toDouble(),
        lng: (j['lng'] ?? 0).toDouble(),
        avatar: j['avatar'] ?? '',
        position: j['position'] ?? '',
        height: (j['height'] ?? 0).toDouble(),
        games: (j['games'] ?? 0).toInt(),
        courts: (j['courts'] ?? 0).toInt(),
        streak: (j['streak'] ?? 0).toInt(),
        rating: (j['rating'] ?? 0).toDouble(),
        userEmail: j['userEmail'] ?? '',
        clan: j['clan'] ?? '',
        avatarColor: j['avatarColor'] ?? '',
        clanTextColor: j['clanTextColor'] ?? '',
        clanFont: j['clanFont'] ?? '',
        title: j['title'] ?? '',
        level: j['level'] ?? '',
        shareStatus: j['shareStatus'] ?? false,
        shareCourt: j['shareCourt'] ?? false,
        shareTime: j['shareTime'] ?? false,
        playing: j['playing'] ?? false,
        playingCourtId: j['playingCourtId'] ?? '',
        playingSince: j['playingSince'] ?? '',
      );
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
