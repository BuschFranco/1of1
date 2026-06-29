// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Profile _$ProfileFromJson(Map<String, dynamic> json) => _Profile(
  pageId: json['pageId'] as String? ?? '',
  name: json['name'] as String? ?? '',
  handle: json['handle'] as String? ?? '',
  phone: json['phone'] as String? ?? '',
  city: json['city'] as String? ?? '',
  lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
  lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
  avatar: json['avatar'] as String? ?? '',
  position: json['position'] as String? ?? '',
  height: (json['height'] as num?)?.toDouble() ?? 0.0,
  games: (json['games'] as num?)?.toInt() ?? 0,
  courts: (json['courts'] as num?)?.toInt() ?? 0,
  streak: (json['streak'] as num?)?.toInt() ?? 0,
  points: (json['points'] as num?)?.toInt() ?? 0,
  rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
  userEmail: json['userEmail'] as String? ?? '',
  clan: json['clan'] as String? ?? '',
  avatarColor: json['avatarColor'] as String? ?? '',
  clanTextColor: json['clanTextColor'] as String? ?? '',
  clanFont: json['clanFont'] as String? ?? '',
  title: json['title'] as String? ?? '',
  level: json['level'] as String? ?? '',
  unlockedBadges:
      (json['unlockedBadges'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const <String>[],
  playSeconds: (json['playSeconds'] as num?)?.toInt() ?? 0,
  playTimeByCourt: json['playTimeByCourt'] as String? ?? '',
  shareStatus: json['shareStatus'] as bool? ?? false,
  shareCourt: json['shareCourt'] as bool? ?? false,
  shareTime: json['shareTime'] as bool? ?? false,
  playing: json['playing'] as bool? ?? false,
  playingCourtId: json['playingCourtId'] as String? ?? '',
  playingSince: json['playingSince'] as String? ?? '',
);

Map<String, dynamic> _$ProfileToJson(_Profile instance) => <String, dynamic>{
  'pageId': instance.pageId,
  'name': instance.name,
  'handle': instance.handle,
  'phone': instance.phone,
  'city': instance.city,
  'lat': instance.lat,
  'lng': instance.lng,
  'avatar': instance.avatar,
  'position': instance.position,
  'height': instance.height,
  'games': instance.games,
  'courts': instance.courts,
  'streak': instance.streak,
  'points': instance.points,
  'rating': instance.rating,
  'userEmail': instance.userEmail,
  'clan': instance.clan,
  'avatarColor': instance.avatarColor,
  'clanTextColor': instance.clanTextColor,
  'clanFont': instance.clanFont,
  'title': instance.title,
  'level': instance.level,
  'unlockedBadges': instance.unlockedBadges,
  'playSeconds': instance.playSeconds,
  'playTimeByCourt': instance.playTimeByCourt,
  'shareStatus': instance.shareStatus,
  'shareCourt': instance.shareCourt,
  'shareTime': instance.shareTime,
  'playing': instance.playing,
  'playingCourtId': instance.playingCourtId,
  'playingSince': instance.playingSince,
};
