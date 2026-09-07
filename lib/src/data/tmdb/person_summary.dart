import 'package:json_annotation/json_annotation.dart';

part 'person_summary.g.dart';

/// One person from TMDB's `/search/person` results.
///
/// Search matches a query against people as well as titles, so typing an
/// actor's or director's name surfaces their filmography rather than only the
/// titles whose *name* happens to contain the query.
@JsonSerializable()
class PersonSummary {
  PersonSummary({
    required this.personId,
    required this.name,
    this.knownForDepartment = '',
    this.profilePath,
    this.popularity = 0,
  });

  @JsonKey(name: 'id')
  final int personId;

  @JsonKey(defaultValue: '')
  final String name;

  /// TMDB's primary role for this person — 'Acting', 'Directing', 'Writing', …
  /// Used to decide which of their credit lists leads.
  @JsonKey(name: 'known_for_department', defaultValue: '')
  final String knownForDepartment;

  @JsonKey(name: 'profile_path')
  final String? profilePath;

  @JsonKey(defaultValue: 0)
  final double popularity;

  factory PersonSummary.fromJson(Map<String, dynamic> json) =>
      _$PersonSummaryFromJson(json);
  Map<String, dynamic> toJson() => _$PersonSummaryToJson(this);
}
