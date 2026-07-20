// The acquisition boundary (HANDOFF §8). The app does not care where a magnet
// comes from — legal-source resolvers are provided; anything else is a
// swappable implementation with its own legal exposure. Keeping this as one
// small interface is the whole point: the play flow never touches trackers.

/// Minimal metadata the resolver needs to find a title.
class ShowMeta {
  const ShowMeta({required this.title, this.tmdbId, this.mediaType = 'tv'});

  final String title;
  final int? tmdbId;
  final String mediaType;
}

/// A magnet/torrent reference handed off to the daemon.
class TorrentHandle {
  const TorrentHandle({
    required this.magnetOrUrl,
    this.displayName,
    this.seasonPack = false,
  });

  final String magnetOrUrl;
  final String? displayName;

  /// True when this handle is a **whole-season pack** the resolver fell back to
  /// (Tier 2): the daemon must extract the requested episode's file from it, and
  /// the caller keys it per-season (not per-episode) so a second episode reuses
  /// the same download instead of re-fetching (Tier 0).
  final bool seasonPack;
}

/// Maps a request to a downloadable handle, or null if nothing legal is found.
abstract class AcquisitionResolver {
  /// [exclude] lists source URLs (the value that would land in
  /// [TorrentHandle.magnetOrUrl]) already handed out for this title — skip them
  /// so "try another source" resolves the next-best instead of the same one.
  Future<TorrentHandle?> resolve(
    ShowMeta meta,
    int? season,
    int? episode, {
    Set<String> exclude = const {},
  });

  /// Resolve a **whole-season pack** for [season] of [meta]'s show, or null when
  /// none verifies. Used by the bulk "Download" flow to prefer one season
  /// torrent over per-episode ones. Default: no pack support (a resolver that
  /// only serves single titles, e.g. Internet Archive, inherits this null).
  Future<TorrentHandle?> resolveSeasonPack(
    ShowMeta meta,
    int season, {
    Set<String> exclude = const {},
  }) async =>
      null;

  /// Resolve a **whole-series pack** (all seasons in one torrent) for [meta]'s
  /// show, or null when none verifies. Default: no pack support.
  Future<TorrentHandle?> resolveShowPack(
    ShowMeta meta, {
    Set<String> exclude = const {},
  }) async =>
      null;
}

/// A stable per-title/episode key, used both as the daemon add's `dedupeKey`
/// (so re-selecting reattaches instead of re-downloading) and to find a title's
/// live download in [TorrentStatus.tags]. Keyed on the TMDB id when available so
/// it survives release-title differences. Pure so the play flow and the
/// download-badge lookup derive the same value.
String acquisitionDedupeKey({
  int? tmdbId,
  required String title,
  int? season,
  int? episode,
}) {
  final base = 'cr-tmdb-${tmdbId ?? title}';
  if (season != null && episode != null) return '$base-s${season}e$episode';
  // A season-only key (episode omitted) tags a whole-season pack, so every
  // episode played out of it reattaches to the same download (Tier 0 reuse).
  if (season != null) return '$base-s$season';
  return base;
}

/// The daemon tag applied to a torrent added with [dedupeKey]. Tags can't contain
/// commas. Pure + shared so [TorrentStatus.tags] can be matched back to a title.
String acquisitionTag(String dedupeKey) =>
    'cr-src-${dedupeKey.replaceAll(',', '_')}';

/// The dedupe key encoded in an [acquisitionTag], or null if [tag] isn't one of
/// ours — lets the Downloads screen map a torrent back to its acquisition
/// context. Dedupe keys never contain commas, so the reverse is exact. Pure.
String? dedupeKeyFromTag(String tag) {
  const prefix = 'cr-src-';
  return tag.startsWith(prefix) ? tag.substring(prefix.length) : null;
}

/// Why a torrent operation failed, so the UI can explain it in plain language
/// instead of "check the logs".
enum TorrentErrorKind {
  /// The source returned 404 — the title's torrent isn't there.
  sourceNotFound,

  /// The source refused or errored (403 / 5xx) — usually transient.
  sourceUnavailable,

  /// Couldn't reach the source at all (DNS/TLS/offline).
  network,

  /// Got a response, but it isn't a valid `.torrent` (e.g. an HTML error page).
  badTorrent,

  /// The daemon rejected the add.
  addFailed,

  /// Added, but the torrent never showed up in the client.
  notInClient,

  /// Downloading too slowly to start playing within the time budget.
  timeout,

  /// No playable video file could be resolved in the torrent.
  noVideo,

  generic,
}

/// Raised when a torrent daemon operation fails. [message] is the technical
/// detail (logged); [userMessage] is a friendly explanation for the 10-foot UI.
class TorrentDaemonException implements Exception {
  TorrentDaemonException(
    this.message, {
    this.kind = TorrentErrorKind.generic,
    this.statusCode,
  });

  final String message;
  final TorrentErrorKind kind;

  /// HTTP status, when the failure came from fetching the `.torrent`.
  final int? statusCode;

  /// A friendly, source-agnostic explanation to show the user.
  String get userMessage => switch (kind) {
        TorrentErrorKind.sourceNotFound =>
          "This title isn't available to download from its source anymore.",
        TorrentErrorKind.sourceUnavailable =>
          'The source is busy or unavailable right now. Please try again in a little while.',
        TorrentErrorKind.network =>
          "Couldn't reach the source — check your internet connection and try again.",
        TorrentErrorKind.badTorrent =>
          "This title's download couldn't be read — the file may be missing or broken on the source.",
        TorrentErrorKind.addFailed =>
          "The download couldn't be started by the torrent client.",
        TorrentErrorKind.notInClient =>
          "The download didn't start. Please try again.",
        TorrentErrorKind.timeout =>
          "This is downloading too slowly to start playing — no one may be sharing it right now. Try again later.",
        TorrentErrorKind.noVideo =>
          'No playable video was found in this title.',
        TorrentErrorKind.generic =>
          'Something went wrong starting this video. Please try again.',
      };

  @override
  String toString() => 'TorrentDaemonException: $message';
}

/// Drives the torrent daemon (qBittorrent-nox) over its Web API. Streaming is
/// the target: sequential download + first/last-piece priority, then hand the
/// primary file to the player once enough buffer exists
/// (DECISIONS: stream-while-downloading).
abstract class TorrentDaemon {
  /// Add a torrent configured for streaming. Returns a task handle.
  ///
  /// [dedupeKey], when given, makes the add idempotent: if a torrent for this key
  /// was already added it reattaches to it (same download) instead of adding a
  /// duplicate — so selecting the same title twice doesn't re-download or fail.
  Future<TorrentTask> add(
    TorrentHandle handle, {
    required String savePath,
    bool sequential = true,
    bool firstLastPiecePriority = true,
    String? dedupeKey,
  });

  /// The task for an already-added torrent bearing [dedupeKey]'s tag, or null if
  /// none exists — lets a caller reattach to a running download (reading its
  /// hash + save path) without re-resolving or re-adding it.
  Future<TorrentTask?> taskForDedupeKey(String dedupeKey);

  /// Snapshot of every torrent the daemon is managing — drives the Downloads
  /// activity screen. Returns [] if the daemon isn't reachable.
  Future<List<TorrentStatus>> listTorrents();

  /// Whether the daemon's Web API is reachable right now (a health ping) — drives
  /// the online/offline indicator. Never throws.
  Future<bool> isAlive();

  /// Remove a torrent from the daemon. When [deleteFiles] is true its downloaded
  /// data (incl. partial/stalled files) is deleted from disk too.
  Future<void> remove({required String hash, required bool deleteFiles});

  /// Remove the torrent bearing [dedupeKey]'s tag, if one exists (deleting its
  /// files when [deleteFiles]). No-op when nothing matches. Used by "try another
  /// source" to discard the current download before re-resolving.
  Future<void> removeByDedupeKey(String dedupeKey, {required bool deleteFiles});

  /// Pause ([paused] true) or resume ([paused] false) a torrent.
  Future<void> setPaused({required String hash, required bool paused});
}

/// A live status line for one torrent in the daemon (from the qBittorrent
/// `/torrents/info` shape). Progress is 0.0–1.0; [etaSeconds] is null when the
/// daemon can't estimate it (e.g. stalled or complete).
class TorrentStatus {
  const TorrentStatus({
    required this.hash,
    required this.name,
    required this.progress,
    required this.state,
    required this.downloadSpeed,
    required this.sizeBytes,
    required this.downloadedBytes,
    this.etaSeconds,
    this.tags = const [],
  });

  final String hash;
  final String name;

  /// The torrent's qBittorrent tags — includes the [acquisitionTag] we stamped
  /// at add time, which maps it back to the title/episode that requested it.
  final List<String> tags;

  /// 0.0–1.0.
  final double progress;

  /// Raw daemon state string (e.g. `downloading`, `stalledDL`, `pausedDL`,
  /// `uploading`, `checkingDL`, `error`). Mapped to a friendly label in the UI.
  final String state;

  /// Bytes/second, current.
  final int downloadSpeed;
  final int sizeBytes;
  final int downloadedBytes;

  /// Seconds remaining, or null if unknown/not applicable.
  final int? etaSeconds;

  bool get isComplete => progress >= 1.0;
}

abstract class TorrentTask {
  /// Prepare a single file for playback and return its absolute path: focus the
  /// download on it, then wait until enough is buffered (incl. first/last
  /// pieces) to begin playback.
  ///
  /// [name] selects the file by its basename (as listed in the item's file
  /// list) — for multi-file torrents (IA bundles / whole seasons) this plays
  /// exactly the chosen video. When [name] is null but [season]/[episode] are
  /// given, the file whose name parses to that `SxxExx` is selected (extracting
  /// one episode from a season pack); if no file matches but the torrent has a
  /// single video, that video is used. When all are null, the largest/primary
  /// video is used. Selecting files is additive: previously prepared files stay
  /// wanted, so a watched episode isn't dropped when the next is picked.
  Future<String> prepareFile({String? name, int? season, int? episode});

  /// 0.0–1.0 download progress stream, for the show-detail availability badge.
  Stream<double> get progress;
}
