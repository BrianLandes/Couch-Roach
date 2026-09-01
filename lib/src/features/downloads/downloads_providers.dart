import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../injection.dart';
import '../../services/acquisition/acquisition.dart';
import '../../services/acquisition/episode_file_progress.dart';

/// How often the Downloads screen re-polls the daemon. The qBittorrent Web API
/// has no push channel, so we poll; ~1.5s is live enough for a progress bar
/// without hammering the localhost daemon.
const _pollInterval = Duration(milliseconds: 1500);

/// Live snapshot of everything the torrent daemon is doing, for the Downloads
/// activity screen. autoDispose so polling stops when the screen is closed.
/// Emits [] when the daemon isn't reachable (listTorrents degrades gracefully),
/// so the screen shows its empty state rather than an error.
final downloadsProvider =
    StreamProvider.autoDispose<List<TorrentStatus>>((ref) async* {
  final daemon = getIt<TorrentDaemon>();
  while (true) {
    yield await daemon.listTorrents();
    await Future<void>.delayed(_pollInterval);
  }
});

/// The live download bearing [tag] (the [acquisitionTag] stamped at add time),
/// or null if none is active. Watches [downloadsProvider] so it ticks with the
/// poll — the show/movie detail buttons use it to show "Downloading nn%".
final downloadForTagProvider =
    Provider.autoDispose.family<TorrentStatus?, String>((ref, tag) {
  final torrents = ref.watch(downloadsProvider).asData?.value ?? const [];
  for (final t in torrents) {
    if (t.tags.contains(tag)) return t;
  }
  return null;
});

/// Whether the torrent daemon's Web API is reachable — drives the online/offline
/// indicator on the Downloads screen. Polls a lightweight health ping.
final daemonAliveProvider = StreamProvider.autoDispose<bool>((ref) async* {
  final daemon = getIt<TorrentDaemon>();
  while (true) {
    yield await daemon.isAlive();
    await Future<void>.delayed(_pollInterval);
  }
});


/// Per-episode progress for a show's in-flight **season/show packs**, keyed by
/// `(season, episode)`.
///
/// Episode-tagged downloads are deliberately excluded: `AcquireButton` already
/// drives those through its own state machine (with retry/cancel), and showing
/// a second meter for the same download would double-render it. Packs are the
/// gap — they're tagged with the *season* key, so no episode's button can see
/// them, and every episode inside one otherwise shows a Download control that
/// would start a redundant fetch.
///
/// autoDispose, so the extra per-file polling stops when the detail page closes.
final packEpisodeProgressProvider =
    StreamProvider.autoDispose.family<Map<(int, int), double>, int>(
        (ref, tmdbId) async* {
  final daemon = getIt<TorrentDaemon>();
  while (true) {
    yield await _packEpisodeProgress(daemon, tmdbId);
    await Future<void>.delayed(_pollInterval);
  }
});

/// One poll: find this show's pack torrents and merge their per-file progress.
Future<Map<(int, int), double>> _packEpisodeProgress(
    TorrentDaemon daemon, int tmdbId) async {
  final out = <(int, int), double>{};
  for (final t in await daemon.listTorrents()) {
    final isOurPack = t.tags.any((tag) {
      final key = parseAcquisitionKey(tag);
      // episode == null → a season or whole-show pack, not a single episode.
      return key.tmdbId == tmdbId && key.episode == null;
    });
    if (!isOurPack) continue;
    for (final e in episodeFileProgress(await daemon.torrentFiles(t.hash)).entries) {
      final existing = out[e.key];
      if (existing == null || e.value > existing) out[e.key] = e.value;
    }
  }
  return out;
}
