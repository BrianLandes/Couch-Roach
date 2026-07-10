// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'credits.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CastMember _$CastMemberFromJson(Map<String, dynamic> json) => CastMember(
      personId: (json['id'] as num).toInt(),
      name: json['name'] as String,
      character: json['character'] as String? ?? '',
      profilePath: json['profile_path'] as String?,
      order: (json['order'] as num?)?.toInt(),
    );

Map<String, dynamic> _$CastMemberToJson(CastMember instance) =>
    <String, dynamic>{
      'id': instance.personId,
      'name': instance.name,
      'character': instance.character,
      'profile_path': instance.profilePath,
      'order': instance.order,
    };

PersonCredit _$PersonCreditFromJson(Map<String, dynamic> json) => PersonCredit(
      tmdbId: (json['id'] as num).toInt(),
      mediaType: json['media_type'] as String,
      title: json['title'] as String?,
      name: json['name'] as String?,
      character: json['character'] as String? ?? '',
      posterPath: json['poster_path'] as String?,
      popularity: (json['popularity'] as num?)?.toDouble() ?? 0,
      releaseDate: json['release_date'] as String?,
      firstAirDate: json['first_air_date'] as String?,
    );

Map<String, dynamic> _$PersonCreditToJson(PersonCredit instance) =>
    <String, dynamic>{
      'id': instance.tmdbId,
      'media_type': instance.mediaType,
      'title': instance.title,
      'name': instance.name,
      'character': instance.character,
      'poster_path': instance.posterPath,
      'popularity': instance.popularity,
      'release_date': instance.releaseDate,
      'first_air_date': instance.firstAirDate,
    };
