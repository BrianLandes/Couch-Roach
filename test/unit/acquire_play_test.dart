import 'package:couch_roach/src/core/logging/error_log_service.dart';
import 'package:couch_roach/src/core/settings/settings_service.dart';
import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/data/repositories/library_repository.dart';
import 'package:couch_roach/src/data/repositories/season_pack_source_repository.dart';
import 'package:couch_roach/src/data/tmdb/season.dart';
import 'package:couch_roach/src/features/acquire/acquire_play.dart';
import 'package:couch_roach/src/injection.dart';
import 'package:couch_roach/src/services/acquisition/acquisition.dart';
import 'package:couch_roach/src/services/acquisition/acquisition_session.dart';
import 'package:couch_roach/src/services/discovery/tmdb_client.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// A torrent in the fake daemon. [drop] is what dropEpisode reports;
/// selectEpisode always finds the episode.
class _FakeTask implements TorrentTask {
  _FakeTask(this.hash, {this.drop});
  @override
  final String hash;
  final EpisodeDrop? drop;
  final List<(int, int)> dropped = [];
  final List<(int, int)> selected = [];

  @override
  Future<EpisodeDrop?> dropEpisode(
      {required int season, required int episode}) async {
    dropped.add((season, episode));
    return drop;
  }

  @override
  Future<String?> selectEpisode({
    required int season,
    required int episode,
    Duration wait = const Duration(minutes: 10),
  }) async {
    selected.add((season, episode));
    return '/lib/pack/S${season}E$episode.mkv';
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _FakeDaemon implements TorrentDaemon {
  final Map<String, _FakeTask> byKey = {};
  final Map<String, List<String>> files = {};
  final List<({String hash, bool deleteFiles})> removed = [];

  @override
  Future<TorrentTask?> taskForDedupeKey(String dedupeKey) async =>
      byKey[dedupeKey];

  @override
  Future<void> remove({required String hash, required bool deleteFiles}) async {
    removed.add((hash: hash, deleteFiles: deleteFiles));
    byKey.removeWhere((_, t) => t.hash == hash);
  }

  @override
  Future<List<TorrentStatus>> listTorrents() async => [
        for (final t in byKey.values)
          TorrentStatus(
            hash: t.hash,
            name: t.hash,
            progress: 0.5,
            state: 'downloading',
            downloadSpeed: 0,
            sizeBytes: 0,
            downloadedBytes: 0,
            savePath: '/lib',
          ),
      ];

  @override
  Future<List<Map<String, dynamic>>> torrentFiles(String hash) async =>
      [for (final n in files[hash] ?? const <String>[]) {'name': n}];

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _FakeSettings implements SettingsService {
  @override
  bool get requireVpn => false;
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

/// No TMDB data: every episode counts as aired.
class _FakeDiscovery implements DiscoveryClient {
  @override
  Future<SeasonDetails?> seasonDetails(int tmdbId, int seasonNumber) async =>
      null;
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

void main() {
  late AppDatabase db;
  late _FakeDaemon daemon;
  late LibraryRepository library;
  late SeasonPackSourceRepository packs;
  late AcquisitionSession session;

  const meta = ShowMeta(title: 'The Show', tmdbId: 7);
  final keys = acquireKeysFor(meta, 1, 2);

  setUp(() async {
    await getIt.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    daemon = _FakeDaemon();
    library = DriftLibraryRepository(db);
    packs = DriftSeasonPackSourceRepository(db);
    session = AcquisitionSession();
    getIt
      ..registerSingleton<ErrorLogService>(ErrorLogService())
      ..registerSingleton<TorrentDaemon>(daemon)
      ..registerSingleton<LibraryRepository>(library)
      ..registerSingleton<SeasonPackSourceRepository>(packs)
      ..registerSingleton<AcquisitionSession>(session)
      ..registerSingleton<SettingsService>(_FakeSettings())
      ..registerSingleton<DiscoveryClient>(_FakeDiscovery());
  });
  tearDown(() async {
    await getIt.reset();
    await db.close();
  });

  Future<LibraryItem?> row(String path) => library.findByPath(path);

  Future<void> addRow(String path) => library.upsert(ScannedFile(
      filePath: path,
      title: 'x',
      mediaType: 'tv',
      season: 1,
      episode: 2,
      tmdbId: 7));

  test('acquireKeysFor: an episode has its own key and a season key', () {
    expect(keys.episode,
        acquisitionDedupeKey(tmdbId: 7, title: 'The Show', season: 1, episode: 2));
    expect(keys.season,
        acquisitionDedupeKey(tmdbId: 7, title: 'The Show', season: 1));
    expect(acquireKeysFor(meta, null, null).season, isNull);
  });

  group('releaseCurrentSource', () {
    test("an episode's own torrent is removed with its files, rows flagged "
        'missing', () async {
      daemon.byKey[keys.episode] = _FakeTask('EP');
      daemon.files['EP'] = ['Show.S01E02.mkv'];
      await addRow('/lib/Show.S01E02.mkv');

      await cancelDownload(meta: meta, season: 1, episode: 2, title: 'x');

      expect(daemon.removed, [(hash: 'EP', deleteFiles: true)]);
      expect((await row('/lib/Show.S01E02.mkv'))!.missing, isTrue);
    });

    test('a pack-served episode drops only its file while others download',
        () async {
      final pack = _FakeTask('PACK',
          drop: const EpisodeDrop(
              path: '/lib/pack/S01E02.mkv', othersWanted: true));
      daemon.byKey[keys.season!] = pack;
      await addRow('/lib/pack/S01E02.mkv');

      await cancelDownload(meta: meta, season: 1, episode: 2, title: 'x');

      expect(pack.dropped, [(1, 2)]);
      expect(daemon.removed, isEmpty,
          reason: 'the pack still has other episodes downloading');
      expect((await row('/lib/pack/S01E02.mkv'))!.missing, isTrue);
    });

    test('a pack with nothing else wanted is removed — keeping its files',
        () async {
      daemon.byKey[keys.season!] = _FakeTask('PACK',
          drop: const EpisodeDrop(
              path: '/lib/pack/S01E02.mkv', othersWanted: false));

      await cancelDownload(meta: meta, season: 1, episode: 2, title: 'x');

      // Never deleteFiles on a pack: other episodes may already be on disk
      // (and in the library) from it.
      expect(daemon.removed, [(hash: 'PACK', deleteFiles: false)]);
    });

    test('a retry rejects the remembered pack for the whole season', () async {
      await packs.remember(tmdbId: 7, season: 1, downloadUrl: 'magnet:BAD');
      daemon.byKey[keys.season!] = _FakeTask('PACK',
          drop: const EpisodeDrop(path: '/x.mkv', othersWanted: false));

      await releaseCurrentSource(meta, 1, 2, title: 'x', reject: true);

      expect(await packs.find(7, 1), isNull);
      // Keyed by season, so every other episode of it excludes the pack too.
      expect(session.rejectedPacksFor(acquireKeysFor(meta, 1, 3).season!),
          {'magnet:BAD'});
    });

    test('a cancel keeps the remembered pack', () async {
      await packs.remember(tmdbId: 7, season: 1, downloadUrl: 'magnet:OK');

      await cancelDownload(meta: meta, season: 1, episode: 2, title: 'x');

      expect((await packs.find(7, 1))?.downloadUrl, 'magnet:OK');
      expect(session.rejectedPacksFor(keys.season!), isEmpty);
    });

    test('a movie releases its own torrent, no season fallback', () async {
      const movie = ShowMeta(title: 'Film', tmdbId: 9, mediaType: 'movie');
      final movieKey = acquireKeysFor(movie, null, null).episode;
      daemon.byKey[movieKey] = _FakeTask('MOV');

      await cancelDownload(meta: movie, title: 'x');

      expect(daemon.removed, [(hash: 'MOV', deleteFiles: true)]);
    });
  });

  group('prefetchEpisode', () {
    test('an episode already downloading on its own counts as started',
        () async {
      daemon.byKey[keys.episode] = _FakeTask('EP');
      expect(
          await prefetchEpisode(
              showName: 'The Show', tmdbId: 7, season: 1, episode: 2),
          isTrue);
    });

    test('a season pack in the client gets this episode selected in it',
        () async {
      final pack = _FakeTask('PACK');
      daemon.byKey[keys.season!] = pack;

      final started = await prefetchEpisode(
          showName: 'The Show', tmdbId: 7, season: 1, episode: 2);

      expect(started, isTrue);
      expect(pack.selected, [(1, 2)],
          reason: 'a pack fetched for another episode has this one skipped');
    });
  });
}
