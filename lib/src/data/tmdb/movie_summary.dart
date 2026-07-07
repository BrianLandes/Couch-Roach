import 'package:json_annotation/json_annotation.dart';

part 'movie_summary.g.dart';

/// A movie as it appears in list responses (search, trending).
@JsonSerializable()
class MovieSummary {
  MovieSummary({
    required this.tmdbId,
    required this.title,
    this.overview = '',
    this.posterPath,
    this.backdropPath,
    this.releaseDate,
    this.voteAverage,
  });

  @JsonKey(name: 'id')
  final int tmdbId;
  final String title;

  @JsonKey(defaultValue: '')
  final String overview;

  @JsonKey(name: 'poster_path')
  final String? posterPath;

  @JsonKey(name: 'backdrop_path')
  final String? backdropPath;

  @JsonKey(name: 'release_date')
  final String? releaseDate;

  @JsonKey(name: 'vote_average')
  final double? voteAverage;

  factory MovieSummary.fromJson(Map<String, dynamic> json) =>
      _$MovieSummaryFromJson(json);
  Map<String, dynamic> toJson() => _$MovieSummaryToJson(this);
}
