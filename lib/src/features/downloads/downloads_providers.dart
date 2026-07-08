import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../injection.dart';
import '../../services/acquisition/acquisition.dart';

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
