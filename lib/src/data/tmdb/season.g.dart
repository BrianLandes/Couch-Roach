// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'season.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SeasonSummary _$SeasonSummaryFromJson(Map<String, dynamic> json) =>
    SeasonSummary(
      seasonNumber: (json['season_number'] as num).toInt(),
      name: json['name'] as String,
      overview: json['overview'] as String?,
      episodeCount: (json['episode_count'] as num?)?.toInt(),
      posterPath: json['poster_path'] as String?,
      airDate: json['air_date'] as String?,
    );

Map<String, dynamic> _$SeasonSummaryToJson(SeasonSummary instance) =>
    <String, dynamic>{
      'season_number': instance.seasonNumber,
      'name': instance.name,
      'overview': instance.overview,
      'episode_count': instance.episodeCount,
      'poster_path': instance.posterPath,
      'air_date': instance.airDate,
    };

EpisodeSummary _$EpisodeSummaryFromJson(Map<String, dynamic> json) =>
    EpisodeSummary(
      episodeNumber: (json['episode_number'] as num).toInt(),
      name: json['name'] as String,
      seasonNumber: (json['season_number'] as num?)?.toInt(),
      overview: json['overview'] as String? ?? '',
      stillPath: json['still_path'] as String?,
      airDate: json['air_date'] as String?,
      runtime: (json['runtime'] as num?)?.toInt(),
      voteAverage: (json['vote_average'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$EpisodeSummaryToJson(EpisodeSummary instance) =>
    <String, dynamic>{
      'episode_number': instance.episodeNumber,
      'season_number': instance.seasonNumber,
      'name': instance.name,
      'overview': instance.overview,
      'still_path': instance.stillPath,
      'air_date': instance.airDate,
      'runtime': instance.runtime,
      'vote_average': instance.voteAverage,
    };

SeasonDetails _$SeasonDetailsFromJson(Map<String, dynamic> json) =>
    SeasonDetails(
      seasonNumber: (json['season_number'] as num).toInt(),
      name: json['name'] as String,
      overview: json['overview'] as String?,
      episodes: (json['episodes'] as List<dynamic>?)
              ?.map((e) => EpisodeSummary.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$SeasonDetailsToJson(SeasonDetails instance) =>
    <String, dynamic>{
      'season_number': instance.seasonNumber,
      'name': instance.name,
      'overview': instance.overview,
      'episodes': instance.episodes,
    };
