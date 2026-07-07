// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'movie_summary.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MovieSummary _$MovieSummaryFromJson(Map<String, dynamic> json) => MovieSummary(
      tmdbId: (json['id'] as num).toInt(),
      title: json['title'] as String,
      overview: json['overview'] as String? ?? '',
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      releaseDate: json['release_date'] as String?,
      voteAverage: (json['vote_average'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$MovieSummaryToJson(MovieSummary instance) =>
    <String, dynamic>{
      'id': instance.tmdbId,
      'title': instance.title,
      'overview': instance.overview,
      'poster_path': instance.posterPath,
      'backdrop_path': instance.backdropPath,
      'release_date': instance.releaseDate,
      'vote_average': instance.voteAverage,
    };
