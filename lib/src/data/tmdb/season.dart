import 'package:json_annotation/json_annotation.dart';

part 'season.g.dart';

/// A season as listed inside TV details.
@JsonSerializable()
class SeasonSummary {
  SeasonSummary({
    required this.seasonNumber,
    required this.name,
    this.overview,
    this.episodeCount,
    this.posterPath,
    this.airDate,
  });

  @JsonKey(name: 'season_number')
  final int seasonNumber;
  final String name;
  final String? overview;

  @JsonKey(name: 'episode_count')
  final int? episodeCount;

  @JsonKey(name: 'poster_path')
  final String? posterPath;

  @JsonKey(name: 'air_date')
  final String? airDate;

  factory SeasonSummary.fromJson(Map<String, dynamic> json) =>
      _$SeasonSummaryFromJson(json);
  Map<String, dynamic> toJson() => _$SeasonSummaryToJson(this);
}

/// One episode from a season details response.
@JsonSerializable()
class EpisodeSummary {
  EpisodeSummary({
    required this.episodeNumber,
    required this.name,
    this.seasonNumber,
    this.overview = '',
    this.stillPath,
    this.airDate,
    this.runtime,
    this.voteAverage,
  });

  @JsonKey(name: 'episode_number')
  final int episodeNumber;

  @JsonKey(name: 'season_number')
  final int? seasonNumber;

  final String name;

  @JsonKey(defaultValue: '')
  final String overview;

  @JsonKey(name: 'still_path')
  final String? stillPath;

  @JsonKey(name: 'air_date')
  final String? airDate;

  final int? runtime;

  @JsonKey(name: 'vote_average')
  final double? voteAverage;

  factory EpisodeSummary.fromJson(Map<String, dynamic> json) =>
      _$EpisodeSummaryFromJson(json);
  Map<String, dynamic> toJson() => _$EpisodeSummaryToJson(this);
}

/// A full season with its episode list (`tv/{id}/season/{n}`).
@JsonSerializable()
class SeasonDetails {
  SeasonDetails({
    required this.seasonNumber,
    required this.name,
    this.overview,
    this.episodes = const [],
  });

  @JsonKey(name: 'season_number')
  final int seasonNumber;
  final String name;
  final String? overview;
  final List<EpisodeSummary> episodes;

  factory SeasonDetails.fromJson(Map<String, dynamic> json) =>
      _$SeasonDetailsFromJson(json);
  Map<String, dynamic> toJson() => _$SeasonDetailsToJson(this);
}
