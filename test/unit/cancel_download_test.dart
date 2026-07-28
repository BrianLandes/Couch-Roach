import 'package:couch_roach/src/core/logging/error_log_service.dart';
import 'package:couch_roach/src/features/acquire/acquire_play.dart';
import 'package:couch_roach/src/injection.dart';
import 'package:couch_roach/src/services/acquisition/acquisition.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTask implements TorrentTask {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

/// Records removeByDedupeKey calls; taskForDedupeKey reports a live task for the
/// keys in [presentKeys]. Everything else is unused.
class _FakeDaemon implements TorrentDaemon {
  _FakeDaemon(this.presentKeys);
  final Set<String> presentKeys;
  final List<({String key, bool deleteFiles})> removed = [];

  @override
  Future<TorrentTask?> taskForDedupeKey(String dedupeKey) async =>
      presentKeys.contains(dedupeKey) ? _FakeTask() : null;

  @override
  Future<void> removeByDedupeKey(String dedupeKey,
      {required bool deleteFiles}) async {
    removed.add((key: dedupeKey, deleteFiles: deleteFiles));
    presentKeys.remove(dedupeKey);
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

void main() {
  late _FakeDaemon daemon;

  setUp(() async {
    await getIt.reset();
    daemon = _FakeDaemon({});
    getIt
      ..registerSingleton<ErrorLogService>(ErrorLogService())
      ..registerSingleton<TorrentDaemon>(daemon);
  });
  tearDown(() async => getIt.reset());

  const meta = ShowMeta(title: 'The Show', tmdbId: 7);

  test('removes a single-episode download by its own key only', () async {
    final epKey = acquisitionDedupeKey(
        tmdbId: 7, title: 'The Show', season: 1, episode: 2);
    daemon.presentKeys.add(epKey); // the episode has its own torrent

    await cancelDownload(meta: meta, season: 1, episode: 2, title: 'x');

    expect(daemon.removed.map((r) => r.key), [epKey]);
    expect(daemon.removed.every((r) => r.deleteFiles), isTrue);
  });

  test('a pack-served episode removes the season pack too', () async {
    // No episode-specific torrent → the episode was streaming from the pack.
    await cancelDownload(meta: meta, season: 1, episode: 2, title: 'x');

    final epKey = acquisitionDedupeKey(
        tmdbId: 7, title: 'The Show', season: 1, episode: 2);
    final seasonKey =
        acquisitionDedupeKey(tmdbId: 7, title: 'The Show', season: 1);
    expect(daemon.removed.map((r) => r.key), [epKey, seasonKey]);
  });

  test('a movie removes its own key, no season fallback', () async {
    final movieKey = acquisitionDedupeKey(tmdbId: 7, title: 'The Show');
    daemon.presentKeys.add(movieKey);

    await cancelDownload(meta: meta, title: 'x');

    expect(daemon.removed.map((r) => r.key), [movieKey]);
  });
}
