import 'package:json_annotation/json_annotation.dart';

part 'tmdb_video.g.dart';

/// A video attached to a TMDB title (`/tv|movie/{id}/videos`) — usually a
/// YouTube trailer or teaser.
@JsonSerializable()
class TmdbVideo {
  TmdbVideo({
    required this.key,
    this.site = '',
    this.type = '',
    this.name = '',
    this.official = false,
  });

  /// The site's video id — for YouTube, the `watch?v=` id.
  final String key;

  @JsonKey(defaultValue: '')
  final String site;

  /// `Trailer`, `Teaser`, `Clip`, `Featurette`, …
  @JsonKey(defaultValue: '')
  final String type;

  @JsonKey(defaultValue: '')
  final String name;

  @JsonKey(defaultValue: false)
  final bool official;

  factory TmdbVideo.fromJson(Map<String, dynamic> json) =>
      _$TmdbVideoFromJson(json);
  Map<String, dynamic> toJson() => _$TmdbVideoToJson(this);
}

/// Pick the best preview from a title's videos: a YouTube trailer wins, an
/// official one over an unofficial, with teasers as the fallback. Null if
/// there's no usable YouTube video. Pure + tested.
TmdbVideo? pickTrailer(List<TmdbVideo> videos) {
  final youtube = videos
      .where((v) => v.site.toLowerCase() == 'youtube' && v.key.isNotEmpty)
      .toList();
  if (youtube.isEmpty) return null;

  bool isType(TmdbVideo v, String t) => v.type.toLowerCase() == t;

  return _firstWhere(youtube, (v) => isType(v, 'trailer') && v.official) ??
      _firstWhere(youtube, (v) => isType(v, 'trailer')) ??
      _firstWhere(youtube, (v) => isType(v, 'teaser') && v.official) ??
      _firstWhere(youtube, (v) => isType(v, 'teaser')) ??
      youtube.first;
}

/// The YouTube watch URL for a video key — what libmpv (via yt-dlp) resolves.
String youtubeWatchUrl(String key) => 'https://www.youtube.com/watch?v=$key';

T? _firstWhere<T>(List<T> items, bool Function(T) test) {
  for (final item in items) {
    if (test(item)) return item;
  }
  return null;
}
