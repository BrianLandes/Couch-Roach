import 'package:injectable/injectable.dart';

import 'acquisition.dart';

/// The context of one acquire-and-watch request, kept so "try another source"
/// can re-run the exact same resolve for a title — including from the Downloads
/// screen, which otherwise only knows the torrent, not what was searched for.
class AcquireRequest {
  const AcquireRequest({
    required this.title,
    required this.meta,
    this.season,
    this.episode,
  });

  /// Display/player title (e.g. "The Show — S01E01 · Pilot").
  final String title;

  /// What the resolver searches for (show/movie name + tmdb id + type).
  final ShowMeta meta;
  final int? season;
  final int? episode;
}

/// Session-scoped memory for acquisition, keyed by [acquisitionDedupeKey]:
///
/// - **tried source URLs** per title/episode — fed to
///   [AcquisitionResolver.resolve]'s `exclude` so "try another source" skips
///   what's already been handed out and returns the next-best instead;
/// - **the originating [AcquireRequest]** — so a retry triggered from a surface
///   that only has the torrent (the Downloads screen) can reconstruct the search.
///
/// Deliberately in-memory only (DECISIONS: single-machine, one viewing session):
/// it resets on restart. Worst case after a restart is one wasted retry before
/// the current source is re-recorded as tried.
@LazySingleton()
class AcquisitionSession {
  final Map<String, Set<String>> _tried = {};
  final Map<String, AcquireRequest> _requests = {};

  /// URLs already handed out for [dedupeKey] (empty if none). Pass to `resolve`.
  Set<String> triedFor(String dedupeKey) =>
      _tried[dedupeKey] ?? const <String>{};

  /// Record that [url] was handed out for [dedupeKey] (so it's excluded next).
  void markTried(String dedupeKey, String url) =>
      (_tried[dedupeKey] ??= <String>{}).add(url);

  /// Remember how [dedupeKey] was requested, so it can be retried later.
  void recordRequest(String dedupeKey, AcquireRequest request) =>
      _requests[dedupeKey] = request;

  /// The request that started [dedupeKey] this session, or null if unknown
  /// (never requested this session — e.g. a download from a previous run).
  AcquireRequest? requestFor(String dedupeKey) => _requests[dedupeKey];
}
