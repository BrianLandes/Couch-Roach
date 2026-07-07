import 'package:json_annotation/json_annotation.dart';

part 'tv_show_summary.g.dart';

/// A TV show as it appears in list responses (search, trending, recommendations,
/// similar). Crosses the network boundary, so json_serializable — local rows use
/// drift. See CLAUDE.md → Data Models.
@JsonSerializable()
class TvShowSummary {
  TvShowSummary({
    required this.tmdbId,
    required this.name,
    this.overview = '',
    this.posterPath,
    this.backdropPath,
    this.firstAirDate,
    this.voteAverage,
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

  factory TvShowSummary.fromJson(Map<String, dynamic> json) =>
      _$TvShowSummaryFromJson(json);
  Map<String, dynamic> toJson() => _$TvShowSummaryToJson(this);
}
