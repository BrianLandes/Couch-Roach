import 'package:json_annotation/json_annotation.dart';

part 'tv_show_summary.g.dart';

/// Reference DTO showing the json_serializable pattern used for all API
/// responses (TMDB / OpenSubtitles). Local DB rows use drift, not this — this
/// is for data crossing the network boundary. See CLAUDE.md → Data Models.
@JsonSerializable()
class TvShowSummary {
  TvShowSummary({
    required this.tmdbId,
    required this.name,
    required this.overview,
    this.posterPath,
    this.firstAirDate,
  });

  @JsonKey(name: 'id')
  final int tmdbId;
  final String name;
  final String overview;

  @JsonKey(name: 'poster_path')
  final String? posterPath;

  @JsonKey(name: 'first_air_date')
  final String? firstAirDate;

  factory TvShowSummary.fromJson(Map<String, dynamic> json) =>
      _$TvShowSummaryFromJson(json);
  Map<String, dynamic> toJson() => _$TvShowSummaryToJson(this);
}
