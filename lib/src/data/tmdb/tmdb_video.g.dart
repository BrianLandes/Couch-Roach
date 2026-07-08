// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tmdb_video.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TmdbVideo _$TmdbVideoFromJson(Map<String, dynamic> json) => TmdbVideo(
      key: json['key'] as String,
      site: json['site'] as String? ?? '',
      type: json['type'] as String? ?? '',
      name: json['name'] as String? ?? '',
      official: json['official'] as bool? ?? false,
    );

Map<String, dynamic> _$TmdbVideoToJson(TmdbVideo instance) => <String, dynamic>{
      'key': instance.key,
      'site': instance.site,
      'type': instance.type,
      'name': instance.name,
      'official': instance.official,
    };
