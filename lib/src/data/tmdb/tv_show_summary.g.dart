// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tv_show_summary.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TvShowSummary _$TvShowSummaryFromJson(Map<String, dynamic> json) =>
    TvShowSummary(
      tmdbId: (json['id'] as num).toInt(),
      name: json['name'] as String,
      overview: json['overview'] as String,
      posterPath: json['poster_path'] as String?,
      firstAirDate: json['first_air_date'] as String?,
    );

Map<String, dynamic> _$TvShowSummaryToJson(TvShowSummary instance) =>
    <String, dynamic>{
      'id': instance.tmdbId,
      'name': instance.name,
      'overview': instance.overview,
      'poster_path': instance.posterPath,
      'first_air_date': instance.firstAirDate,
    };
