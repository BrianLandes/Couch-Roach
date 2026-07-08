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

/// A YouTube thumbnail URL for a video key — `hqdefault` (480×360) is always
/// present, unlike `maxresdefault`. Used for the picker's row art.
String youtubeThumbnailUrl(String key) =>
    'https://i.ytimg.com/vi/$key/hqdefault.jpg';

T? _firstWhere<T>(List<T> items, bool Function(T) test) {
  for (final item in items) {
    if (test(item)) return item;
  }
  return null;
}

/// A single selectable preview in the trailer picker: the [video] plus, for a TV
/// season-specific video, which [seasonNumber] it belongs to (null = show-level
/// or a movie).
class TrailerOption {
  const TrailerOption(this.video, {this.seasonNumber});
  final TmdbVideo video;
  final int? seasonNumber;
}

/// A titled section of the picker (e.g. "Trailers", "Teasers").
class TrailerGroup {
  const TrailerGroup(this.title, this.options);
  final String title;
  final List<TrailerOption> options;
}

/// Group previews for the picker into Trailers → Teasers → Clips & More,
/// dropping non-YouTube / keyless videos and de-duping by video key. Within a
/// group: official first, then show-level before season-specific, then season
/// ascending, then by name. Empty groups are omitted. Pure + tested.
List<TrailerGroup> groupTrailerOptions(List<TrailerOption> options) {
  String bucketOf(TrailerOption o) {
    switch (o.video.type.toLowerCase()) {
      case 'trailer':
        return 'Trailers';
      case 'teaser':
        return 'Teasers';
      default:
        return 'Clips & More';
    }
  }

  final seenKeys = <String>{};
  final byBucket = <String, List<TrailerOption>>{};
  for (final o in options) {
    if (o.video.site.toLowerCase() != 'youtube' || o.video.key.isEmpty) continue;
    if (!seenKeys.add(o.video.key)) continue;
    byBucket.putIfAbsent(bucketOf(o), () => []).add(o);
  }

  int compare(TrailerOption a, TrailerOption b) {
    if (a.video.official != b.video.official) return a.video.official ? -1 : 1;
    final as = a.seasonNumber;
    final bs = b.seasonNumber;
    if ((as == null) != (bs == null)) return as == null ? -1 : 1;
    if (as != null && bs != null && as != bs) return as.compareTo(bs);
    return a.video.name.toLowerCase().compareTo(b.video.name.toLowerCase());
  }

  const order = ['Trailers', 'Teasers', 'Clips & More'];
  final out = <TrailerGroup>[];
  for (final title in order) {
    final list = byBucket[title];
    if (list == null || list.isEmpty) continue;
    list.sort(compare);
    out.add(TrailerGroup(title, List.unmodifiable(list)));
  }
  return out;
}
