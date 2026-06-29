// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Profile {

 String get pageId; String get name; String get handle; String get phone; String get city; double get lat; double get lng; String get avatar; String get position; double get height; int get games; int get courts; int get streak;// Puntos acumulados (definen el nivel).
 int get points; double get rating; String get userEmail;// Insignia de clan (hasta 4 caracteres) y colores del avatar (hex de 6
// dígitos, sin '#'). avatarColor = fondo, clanTextColor = letras.
// Vacíos = avatar por defecto (inicial, fondo naranja, texto blanco).
 String get clan; String get avatarColor; String get clanTextColor;// Familia tipográfica del clan (nombre de Google Fonts). Vacío = default.
 String get clanFont;// Título equipado (se desbloquea con logros). Visible para los amigos.
 String get title;// Nivel del jugador (según puntos). Se guarda para que lo vean los amigos.
 String get level;// IDs de logros desbloqueados (insignias permanentes). De acá se derivan
// los títulos. Se persisten para que no se pierdan al reinstalar.
 List<String> get unlockedBadges;// Tiempo jugado total (segundos) y desglose por cancha serializado como
// JSON {courtId: {"n": nombre, "s": segundos}}.
 int get playSeconds; String get playTimeByCourt;// Privacidad: qué comparte el usuario con sus amigos / en las canchas.
 bool get shareStatus;// mostrar "Jugando" a los amigos
 bool get shareCourt;// mostrar en qué cancha está jugando
 bool get shareTime;// mostrar cuánto tiempo lleva jugando
// Presencia actual (se actualiza al empezar/terminar un partido).
 bool get playing; String get playingCourtId; String get playingSince;
/// Create a copy of Profile
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProfileCopyWith<Profile> get copyWith => _$ProfileCopyWithImpl<Profile>(this as Profile, _$identity);

  /// Serializes this Profile to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Profile&&(identical(other.pageId, pageId) || other.pageId == pageId)&&(identical(other.name, name) || other.name == name)&&(identical(other.handle, handle) || other.handle == handle)&&(identical(other.phone, phone) || other.phone == phone)&&(identical(other.city, city) || other.city == city)&&(identical(other.lat, lat) || other.lat == lat)&&(identical(other.lng, lng) || other.lng == lng)&&(identical(other.avatar, avatar) || other.avatar == avatar)&&(identical(other.position, position) || other.position == position)&&(identical(other.height, height) || other.height == height)&&(identical(other.games, games) || other.games == games)&&(identical(other.courts, courts) || other.courts == courts)&&(identical(other.streak, streak) || other.streak == streak)&&(identical(other.points, points) || other.points == points)&&(identical(other.rating, rating) || other.rating == rating)&&(identical(other.userEmail, userEmail) || other.userEmail == userEmail)&&(identical(other.clan, clan) || other.clan == clan)&&(identical(other.avatarColor, avatarColor) || other.avatarColor == avatarColor)&&(identical(other.clanTextColor, clanTextColor) || other.clanTextColor == clanTextColor)&&(identical(other.clanFont, clanFont) || other.clanFont == clanFont)&&(identical(other.title, title) || other.title == title)&&(identical(other.level, level) || other.level == level)&&const DeepCollectionEquality().equals(other.unlockedBadges, unlockedBadges)&&(identical(other.playSeconds, playSeconds) || other.playSeconds == playSeconds)&&(identical(other.playTimeByCourt, playTimeByCourt) || other.playTimeByCourt == playTimeByCourt)&&(identical(other.shareStatus, shareStatus) || other.shareStatus == shareStatus)&&(identical(other.shareCourt, shareCourt) || other.shareCourt == shareCourt)&&(identical(other.shareTime, shareTime) || other.shareTime == shareTime)&&(identical(other.playing, playing) || other.playing == playing)&&(identical(other.playingCourtId, playingCourtId) || other.playingCourtId == playingCourtId)&&(identical(other.playingSince, playingSince) || other.playingSince == playingSince));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,pageId,name,handle,phone,city,lat,lng,avatar,position,height,games,courts,streak,points,rating,userEmail,clan,avatarColor,clanTextColor,clanFont,title,level,const DeepCollectionEquality().hash(unlockedBadges),playSeconds,playTimeByCourt,shareStatus,shareCourt,shareTime,playing,playingCourtId,playingSince]);

@override
String toString() {
  return 'Profile(pageId: $pageId, name: $name, handle: $handle, phone: $phone, city: $city, lat: $lat, lng: $lng, avatar: $avatar, position: $position, height: $height, games: $games, courts: $courts, streak: $streak, points: $points, rating: $rating, userEmail: $userEmail, clan: $clan, avatarColor: $avatarColor, clanTextColor: $clanTextColor, clanFont: $clanFont, title: $title, level: $level, unlockedBadges: $unlockedBadges, playSeconds: $playSeconds, playTimeByCourt: $playTimeByCourt, shareStatus: $shareStatus, shareCourt: $shareCourt, shareTime: $shareTime, playing: $playing, playingCourtId: $playingCourtId, playingSince: $playingSince)';
}


}

/// @nodoc
abstract mixin class $ProfileCopyWith<$Res>  {
  factory $ProfileCopyWith(Profile value, $Res Function(Profile) _then) = _$ProfileCopyWithImpl;
@useResult
$Res call({
 String pageId, String name, String handle, String phone, String city, double lat, double lng, String avatar, String position, double height, int games, int courts, int streak, int points, double rating, String userEmail, String clan, String avatarColor, String clanTextColor, String clanFont, String title, String level, List<String> unlockedBadges, int playSeconds, String playTimeByCourt, bool shareStatus, bool shareCourt, bool shareTime, bool playing, String playingCourtId, String playingSince
});




}
/// @nodoc
class _$ProfileCopyWithImpl<$Res>
    implements $ProfileCopyWith<$Res> {
  _$ProfileCopyWithImpl(this._self, this._then);

  final Profile _self;
  final $Res Function(Profile) _then;

/// Create a copy of Profile
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? pageId = null,Object? name = null,Object? handle = null,Object? phone = null,Object? city = null,Object? lat = null,Object? lng = null,Object? avatar = null,Object? position = null,Object? height = null,Object? games = null,Object? courts = null,Object? streak = null,Object? points = null,Object? rating = null,Object? userEmail = null,Object? clan = null,Object? avatarColor = null,Object? clanTextColor = null,Object? clanFont = null,Object? title = null,Object? level = null,Object? unlockedBadges = null,Object? playSeconds = null,Object? playTimeByCourt = null,Object? shareStatus = null,Object? shareCourt = null,Object? shareTime = null,Object? playing = null,Object? playingCourtId = null,Object? playingSince = null,}) {
  return _then(_self.copyWith(
pageId: null == pageId ? _self.pageId : pageId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,handle: null == handle ? _self.handle : handle // ignore: cast_nullable_to_non_nullable
as String,phone: null == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String,city: null == city ? _self.city : city // ignore: cast_nullable_to_non_nullable
as String,lat: null == lat ? _self.lat : lat // ignore: cast_nullable_to_non_nullable
as double,lng: null == lng ? _self.lng : lng // ignore: cast_nullable_to_non_nullable
as double,avatar: null == avatar ? _self.avatar : avatar // ignore: cast_nullable_to_non_nullable
as String,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as String,height: null == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as double,games: null == games ? _self.games : games // ignore: cast_nullable_to_non_nullable
as int,courts: null == courts ? _self.courts : courts // ignore: cast_nullable_to_non_nullable
as int,streak: null == streak ? _self.streak : streak // ignore: cast_nullable_to_non_nullable
as int,points: null == points ? _self.points : points // ignore: cast_nullable_to_non_nullable
as int,rating: null == rating ? _self.rating : rating // ignore: cast_nullable_to_non_nullable
as double,userEmail: null == userEmail ? _self.userEmail : userEmail // ignore: cast_nullable_to_non_nullable
as String,clan: null == clan ? _self.clan : clan // ignore: cast_nullable_to_non_nullable
as String,avatarColor: null == avatarColor ? _self.avatarColor : avatarColor // ignore: cast_nullable_to_non_nullable
as String,clanTextColor: null == clanTextColor ? _self.clanTextColor : clanTextColor // ignore: cast_nullable_to_non_nullable
as String,clanFont: null == clanFont ? _self.clanFont : clanFont // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as String,unlockedBadges: null == unlockedBadges ? _self.unlockedBadges : unlockedBadges // ignore: cast_nullable_to_non_nullable
as List<String>,playSeconds: null == playSeconds ? _self.playSeconds : playSeconds // ignore: cast_nullable_to_non_nullable
as int,playTimeByCourt: null == playTimeByCourt ? _self.playTimeByCourt : playTimeByCourt // ignore: cast_nullable_to_non_nullable
as String,shareStatus: null == shareStatus ? _self.shareStatus : shareStatus // ignore: cast_nullable_to_non_nullable
as bool,shareCourt: null == shareCourt ? _self.shareCourt : shareCourt // ignore: cast_nullable_to_non_nullable
as bool,shareTime: null == shareTime ? _self.shareTime : shareTime // ignore: cast_nullable_to_non_nullable
as bool,playing: null == playing ? _self.playing : playing // ignore: cast_nullable_to_non_nullable
as bool,playingCourtId: null == playingCourtId ? _self.playingCourtId : playingCourtId // ignore: cast_nullable_to_non_nullable
as String,playingSince: null == playingSince ? _self.playingSince : playingSince // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [Profile].
extension ProfilePatterns on Profile {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Profile value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Profile() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Profile value)  $default,){
final _that = this;
switch (_that) {
case _Profile():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Profile value)?  $default,){
final _that = this;
switch (_that) {
case _Profile() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String pageId,  String name,  String handle,  String phone,  String city,  double lat,  double lng,  String avatar,  String position,  double height,  int games,  int courts,  int streak,  int points,  double rating,  String userEmail,  String clan,  String avatarColor,  String clanTextColor,  String clanFont,  String title,  String level,  List<String> unlockedBadges,  int playSeconds,  String playTimeByCourt,  bool shareStatus,  bool shareCourt,  bool shareTime,  bool playing,  String playingCourtId,  String playingSince)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Profile() when $default != null:
return $default(_that.pageId,_that.name,_that.handle,_that.phone,_that.city,_that.lat,_that.lng,_that.avatar,_that.position,_that.height,_that.games,_that.courts,_that.streak,_that.points,_that.rating,_that.userEmail,_that.clan,_that.avatarColor,_that.clanTextColor,_that.clanFont,_that.title,_that.level,_that.unlockedBadges,_that.playSeconds,_that.playTimeByCourt,_that.shareStatus,_that.shareCourt,_that.shareTime,_that.playing,_that.playingCourtId,_that.playingSince);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String pageId,  String name,  String handle,  String phone,  String city,  double lat,  double lng,  String avatar,  String position,  double height,  int games,  int courts,  int streak,  int points,  double rating,  String userEmail,  String clan,  String avatarColor,  String clanTextColor,  String clanFont,  String title,  String level,  List<String> unlockedBadges,  int playSeconds,  String playTimeByCourt,  bool shareStatus,  bool shareCourt,  bool shareTime,  bool playing,  String playingCourtId,  String playingSince)  $default,) {final _that = this;
switch (_that) {
case _Profile():
return $default(_that.pageId,_that.name,_that.handle,_that.phone,_that.city,_that.lat,_that.lng,_that.avatar,_that.position,_that.height,_that.games,_that.courts,_that.streak,_that.points,_that.rating,_that.userEmail,_that.clan,_that.avatarColor,_that.clanTextColor,_that.clanFont,_that.title,_that.level,_that.unlockedBadges,_that.playSeconds,_that.playTimeByCourt,_that.shareStatus,_that.shareCourt,_that.shareTime,_that.playing,_that.playingCourtId,_that.playingSince);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String pageId,  String name,  String handle,  String phone,  String city,  double lat,  double lng,  String avatar,  String position,  double height,  int games,  int courts,  int streak,  int points,  double rating,  String userEmail,  String clan,  String avatarColor,  String clanTextColor,  String clanFont,  String title,  String level,  List<String> unlockedBadges,  int playSeconds,  String playTimeByCourt,  bool shareStatus,  bool shareCourt,  bool shareTime,  bool playing,  String playingCourtId,  String playingSince)?  $default,) {final _that = this;
switch (_that) {
case _Profile() when $default != null:
return $default(_that.pageId,_that.name,_that.handle,_that.phone,_that.city,_that.lat,_that.lng,_that.avatar,_that.position,_that.height,_that.games,_that.courts,_that.streak,_that.points,_that.rating,_that.userEmail,_that.clan,_that.avatarColor,_that.clanTextColor,_that.clanFont,_that.title,_that.level,_that.unlockedBadges,_that.playSeconds,_that.playTimeByCourt,_that.shareStatus,_that.shareCourt,_that.shareTime,_that.playing,_that.playingCourtId,_that.playingSince);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Profile extends Profile {
  const _Profile({this.pageId = '', this.name = '', this.handle = '', this.phone = '', this.city = '', this.lat = 0.0, this.lng = 0.0, this.avatar = '', this.position = '', this.height = 0.0, this.games = 0, this.courts = 0, this.streak = 0, this.points = 0, this.rating = 0.0, this.userEmail = '', this.clan = '', this.avatarColor = '', this.clanTextColor = '', this.clanFont = '', this.title = '', this.level = '', final  List<String> unlockedBadges = const <String>[], this.playSeconds = 0, this.playTimeByCourt = '', this.shareStatus = false, this.shareCourt = false, this.shareTime = false, this.playing = false, this.playingCourtId = '', this.playingSince = ''}): _unlockedBadges = unlockedBadges,super._();
  factory _Profile.fromJson(Map<String, dynamic> json) => _$ProfileFromJson(json);

@override@JsonKey() final  String pageId;
@override@JsonKey() final  String name;
@override@JsonKey() final  String handle;
@override@JsonKey() final  String phone;
@override@JsonKey() final  String city;
@override@JsonKey() final  double lat;
@override@JsonKey() final  double lng;
@override@JsonKey() final  String avatar;
@override@JsonKey() final  String position;
@override@JsonKey() final  double height;
@override@JsonKey() final  int games;
@override@JsonKey() final  int courts;
@override@JsonKey() final  int streak;
// Puntos acumulados (definen el nivel).
@override@JsonKey() final  int points;
@override@JsonKey() final  double rating;
@override@JsonKey() final  String userEmail;
// Insignia de clan (hasta 4 caracteres) y colores del avatar (hex de 6
// dígitos, sin '#'). avatarColor = fondo, clanTextColor = letras.
// Vacíos = avatar por defecto (inicial, fondo naranja, texto blanco).
@override@JsonKey() final  String clan;
@override@JsonKey() final  String avatarColor;
@override@JsonKey() final  String clanTextColor;
// Familia tipográfica del clan (nombre de Google Fonts). Vacío = default.
@override@JsonKey() final  String clanFont;
// Título equipado (se desbloquea con logros). Visible para los amigos.
@override@JsonKey() final  String title;
// Nivel del jugador (según puntos). Se guarda para que lo vean los amigos.
@override@JsonKey() final  String level;
// IDs de logros desbloqueados (insignias permanentes). De acá se derivan
// los títulos. Se persisten para que no se pierdan al reinstalar.
 final  List<String> _unlockedBadges;
// IDs de logros desbloqueados (insignias permanentes). De acá se derivan
// los títulos. Se persisten para que no se pierdan al reinstalar.
@override@JsonKey() List<String> get unlockedBadges {
  if (_unlockedBadges is EqualUnmodifiableListView) return _unlockedBadges;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_unlockedBadges);
}

// Tiempo jugado total (segundos) y desglose por cancha serializado como
// JSON {courtId: {"n": nombre, "s": segundos}}.
@override@JsonKey() final  int playSeconds;
@override@JsonKey() final  String playTimeByCourt;
// Privacidad: qué comparte el usuario con sus amigos / en las canchas.
@override@JsonKey() final  bool shareStatus;
// mostrar "Jugando" a los amigos
@override@JsonKey() final  bool shareCourt;
// mostrar en qué cancha está jugando
@override@JsonKey() final  bool shareTime;
// mostrar cuánto tiempo lleva jugando
// Presencia actual (se actualiza al empezar/terminar un partido).
@override@JsonKey() final  bool playing;
@override@JsonKey() final  String playingCourtId;
@override@JsonKey() final  String playingSince;

/// Create a copy of Profile
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProfileCopyWith<_Profile> get copyWith => __$ProfileCopyWithImpl<_Profile>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProfileToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Profile&&(identical(other.pageId, pageId) || other.pageId == pageId)&&(identical(other.name, name) || other.name == name)&&(identical(other.handle, handle) || other.handle == handle)&&(identical(other.phone, phone) || other.phone == phone)&&(identical(other.city, city) || other.city == city)&&(identical(other.lat, lat) || other.lat == lat)&&(identical(other.lng, lng) || other.lng == lng)&&(identical(other.avatar, avatar) || other.avatar == avatar)&&(identical(other.position, position) || other.position == position)&&(identical(other.height, height) || other.height == height)&&(identical(other.games, games) || other.games == games)&&(identical(other.courts, courts) || other.courts == courts)&&(identical(other.streak, streak) || other.streak == streak)&&(identical(other.points, points) || other.points == points)&&(identical(other.rating, rating) || other.rating == rating)&&(identical(other.userEmail, userEmail) || other.userEmail == userEmail)&&(identical(other.clan, clan) || other.clan == clan)&&(identical(other.avatarColor, avatarColor) || other.avatarColor == avatarColor)&&(identical(other.clanTextColor, clanTextColor) || other.clanTextColor == clanTextColor)&&(identical(other.clanFont, clanFont) || other.clanFont == clanFont)&&(identical(other.title, title) || other.title == title)&&(identical(other.level, level) || other.level == level)&&const DeepCollectionEquality().equals(other._unlockedBadges, _unlockedBadges)&&(identical(other.playSeconds, playSeconds) || other.playSeconds == playSeconds)&&(identical(other.playTimeByCourt, playTimeByCourt) || other.playTimeByCourt == playTimeByCourt)&&(identical(other.shareStatus, shareStatus) || other.shareStatus == shareStatus)&&(identical(other.shareCourt, shareCourt) || other.shareCourt == shareCourt)&&(identical(other.shareTime, shareTime) || other.shareTime == shareTime)&&(identical(other.playing, playing) || other.playing == playing)&&(identical(other.playingCourtId, playingCourtId) || other.playingCourtId == playingCourtId)&&(identical(other.playingSince, playingSince) || other.playingSince == playingSince));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,pageId,name,handle,phone,city,lat,lng,avatar,position,height,games,courts,streak,points,rating,userEmail,clan,avatarColor,clanTextColor,clanFont,title,level,const DeepCollectionEquality().hash(_unlockedBadges),playSeconds,playTimeByCourt,shareStatus,shareCourt,shareTime,playing,playingCourtId,playingSince]);

@override
String toString() {
  return 'Profile(pageId: $pageId, name: $name, handle: $handle, phone: $phone, city: $city, lat: $lat, lng: $lng, avatar: $avatar, position: $position, height: $height, games: $games, courts: $courts, streak: $streak, points: $points, rating: $rating, userEmail: $userEmail, clan: $clan, avatarColor: $avatarColor, clanTextColor: $clanTextColor, clanFont: $clanFont, title: $title, level: $level, unlockedBadges: $unlockedBadges, playSeconds: $playSeconds, playTimeByCourt: $playTimeByCourt, shareStatus: $shareStatus, shareCourt: $shareCourt, shareTime: $shareTime, playing: $playing, playingCourtId: $playingCourtId, playingSince: $playingSince)';
}


}

/// @nodoc
abstract mixin class _$ProfileCopyWith<$Res> implements $ProfileCopyWith<$Res> {
  factory _$ProfileCopyWith(_Profile value, $Res Function(_Profile) _then) = __$ProfileCopyWithImpl;
@override @useResult
$Res call({
 String pageId, String name, String handle, String phone, String city, double lat, double lng, String avatar, String position, double height, int games, int courts, int streak, int points, double rating, String userEmail, String clan, String avatarColor, String clanTextColor, String clanFont, String title, String level, List<String> unlockedBadges, int playSeconds, String playTimeByCourt, bool shareStatus, bool shareCourt, bool shareTime, bool playing, String playingCourtId, String playingSince
});




}
/// @nodoc
class __$ProfileCopyWithImpl<$Res>
    implements _$ProfileCopyWith<$Res> {
  __$ProfileCopyWithImpl(this._self, this._then);

  final _Profile _self;
  final $Res Function(_Profile) _then;

/// Create a copy of Profile
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pageId = null,Object? name = null,Object? handle = null,Object? phone = null,Object? city = null,Object? lat = null,Object? lng = null,Object? avatar = null,Object? position = null,Object? height = null,Object? games = null,Object? courts = null,Object? streak = null,Object? points = null,Object? rating = null,Object? userEmail = null,Object? clan = null,Object? avatarColor = null,Object? clanTextColor = null,Object? clanFont = null,Object? title = null,Object? level = null,Object? unlockedBadges = null,Object? playSeconds = null,Object? playTimeByCourt = null,Object? shareStatus = null,Object? shareCourt = null,Object? shareTime = null,Object? playing = null,Object? playingCourtId = null,Object? playingSince = null,}) {
  return _then(_Profile(
pageId: null == pageId ? _self.pageId : pageId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,handle: null == handle ? _self.handle : handle // ignore: cast_nullable_to_non_nullable
as String,phone: null == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String,city: null == city ? _self.city : city // ignore: cast_nullable_to_non_nullable
as String,lat: null == lat ? _self.lat : lat // ignore: cast_nullable_to_non_nullable
as double,lng: null == lng ? _self.lng : lng // ignore: cast_nullable_to_non_nullable
as double,avatar: null == avatar ? _self.avatar : avatar // ignore: cast_nullable_to_non_nullable
as String,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as String,height: null == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as double,games: null == games ? _self.games : games // ignore: cast_nullable_to_non_nullable
as int,courts: null == courts ? _self.courts : courts // ignore: cast_nullable_to_non_nullable
as int,streak: null == streak ? _self.streak : streak // ignore: cast_nullable_to_non_nullable
as int,points: null == points ? _self.points : points // ignore: cast_nullable_to_non_nullable
as int,rating: null == rating ? _self.rating : rating // ignore: cast_nullable_to_non_nullable
as double,userEmail: null == userEmail ? _self.userEmail : userEmail // ignore: cast_nullable_to_non_nullable
as String,clan: null == clan ? _self.clan : clan // ignore: cast_nullable_to_non_nullable
as String,avatarColor: null == avatarColor ? _self.avatarColor : avatarColor // ignore: cast_nullable_to_non_nullable
as String,clanTextColor: null == clanTextColor ? _self.clanTextColor : clanTextColor // ignore: cast_nullable_to_non_nullable
as String,clanFont: null == clanFont ? _self.clanFont : clanFont // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as String,unlockedBadges: null == unlockedBadges ? _self._unlockedBadges : unlockedBadges // ignore: cast_nullable_to_non_nullable
as List<String>,playSeconds: null == playSeconds ? _self.playSeconds : playSeconds // ignore: cast_nullable_to_non_nullable
as int,playTimeByCourt: null == playTimeByCourt ? _self.playTimeByCourt : playTimeByCourt // ignore: cast_nullable_to_non_nullable
as String,shareStatus: null == shareStatus ? _self.shareStatus : shareStatus // ignore: cast_nullable_to_non_nullable
as bool,shareCourt: null == shareCourt ? _self.shareCourt : shareCourt // ignore: cast_nullable_to_non_nullable
as bool,shareTime: null == shareTime ? _self.shareTime : shareTime // ignore: cast_nullable_to_non_nullable
as bool,playing: null == playing ? _self.playing : playing // ignore: cast_nullable_to_non_nullable
as bool,playingCourtId: null == playingCourtId ? _self.playingCourtId : playingCourtId // ignore: cast_nullable_to_non_nullable
as String,playingSince: null == playingSince ? _self.playingSince : playingSince // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
