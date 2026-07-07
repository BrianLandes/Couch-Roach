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
