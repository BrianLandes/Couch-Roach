import 'package:json_annotation/json_annotation.dart';

import 'season.dart';

part 'tv_show_details.g.dart';

@JsonSerializable()
class Genre {
  Genre({required this.id, required this.name});
  final int id;
  final String name;

  factory Genre.fromJson(Map<String, dynamic> json) => _$GenreFromJson(json);
  Map<String, dynamic> toJson() => _$GenreToJson(this);
}

/// Full TV show details (`tv/{id}`), including its season list.
@JsonSerializable()
class TvShowDetails {
  TvShowDetails({
    required this.tmdbId,
    required this.name,
    this.overview = '',
    this.posterPath,
    this.backdropPath,
    this.firstAirDate,
    this.voteAverage,
    this.numberOfSeasons,
    this.genres = const [],
    this.seasons = const [],
  });

  @JsonKey(name: 'id')
  final int tmdbId;
  final String name;

  @JsonKey(defaultValue: '')
  final String overview;

  @JsonKey(name: 'poster_path')
  final String? posterPath;

  @JsonKey(name: 'backdrop_path')
  final String? backdropPath;

  @JsonKey(name: 'first_air_date')
  final String? firstAirDate;

  @JsonKey(name: 'vote_average')
  final double? voteAverage;

  @JsonKey(name: 'number_of_seasons')
  final int? numberOfSeasons;

  final List<Genre> genres;
  final List<SeasonSummary> seasons;

  factory TvShowDetails.fromJson(Map<String, dynamic> json) =>
      _$TvShowDetailsFromJson(json);
  Map<String, dynamic> toJson() => _$TvShowDetailsToJson(this);
}
