import 'package:json_annotation/json_annotation.dart';

part 'credits.g.dart';

/// One person in a cast list (episode/movie credits, guest stars). The same
/// shape covers `cast` and `guest_stars` across TMDB credits endpoints.
@JsonSerializable()
class CastMember {
  CastMember({
    required this.personId,
    required this.name,
    this.character = '',
    this.profilePath,
    this.order,
  });

  @JsonKey(name: 'id')
  final int personId;
  final String name;

  @JsonKey(defaultValue: '')
  final String character;

  @JsonKey(name: 'profile_path')
  final String? profilePath;

  /// Billing order within its list (lower = more prominent); null for guests.
  final int? order;

  factory CastMember.fromJson(Map<String, dynamic> json) =>
      _$CastMemberFromJson(json);
  Map<String, dynamic> toJson() => _$CastMemberToJson(this);
}

/// One title from a person's combined credits — the "known for" feed. Carries
/// both `title` (movies) and `name` (TV); [displayTitle] picks the right one.
@JsonSerializable()
class PersonCredit {
  PersonCredit({
    required this.tmdbId,
    required this.mediaType,
    this.title,
    this.name,
    this.character = '',
    this.posterPath,
    this.popularity = 0,
    this.releaseDate,
    this.firstAirDate,
  });

  @JsonKey(name: 'id')
  final int tmdbId;

  /// 'movie' or 'tv'.
  @JsonKey(name: 'media_type')
  final String mediaType;

  final String? title;
  final String? name;

  @JsonKey(defaultValue: '')
  final String character;

  @JsonKey(name: 'poster_path')
  final String? posterPath;

  @JsonKey(defaultValue: 0)
  final double popularity;

  @JsonKey(name: 'release_date')
  final String? releaseDate;

  @JsonKey(name: 'first_air_date')
  final String? firstAirDate;

  String get displayTitle => (title ?? name ?? '').trim();

  /// Four-digit release/air year, when TMDB has a date.
  String? get year {
    final d = releaseDate ?? firstAirDate;
    return (d != null && d.length >= 4) ? d.substring(0, 4) : null;
  }

  factory PersonCredit.fromJson(Map<String, dynamic> json) =>
      _$PersonCreditFromJson(json);
  Map<String, dynamic> toJson() => _$PersonCreditToJson(this);
}
