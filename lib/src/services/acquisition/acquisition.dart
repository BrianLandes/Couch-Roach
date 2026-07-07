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
  const TorrentHandle({required this.magnetOrUrl, this.displayName});

  final String magnetOrUrl;
  final String? displayName;
}

/// Maps a request to a downloadable handle, or null if nothing legal is found.
abstract class AcquisitionResolver {
  Future<TorrentHandle?> resolve(ShowMeta meta, int? season, int? episode);
}

/// Drives the torrent daemon (qBittorrent-nox) over its Web API. Streaming is
/// the target: sequential download + first/last-piece priority, then hand the
/// primary file to the player once enough buffer exists
/// (DECISIONS: stream-while-downloading).
abstract class TorrentDaemon {
  /// Add a torrent configured for streaming. Returns a task handle.
  Future<TorrentTask> add(
    TorrentHandle handle, {
    required String savePath,
    bool sequential = true,
    bool firstLastPiecePriority = true,
  });
}

abstract class TorrentTask {
  /// Absolute path to the largest/primary video file once known.
  Future<String> get primaryFile;

  /// Completes when enough of the file is buffered (incl. first/last pieces)
  /// to begin playback.
  Future<void> readyToStream();

  /// 0.0–1.0 download progress stream, for the show-detail availability badge.
  Stream<double> get progress;
}
