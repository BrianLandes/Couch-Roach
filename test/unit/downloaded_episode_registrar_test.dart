import 'package:couch_roach/src/core/logging/error_log_service.dart';
import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/data/repositories/library_repository.dart';
import 'package:couch_roach/src/services/acquisition/acquisition.dart';
import 'package:couch_roach/src/services/acquisition/downloaded_episode_registrar.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _FakeDaemon implements TorrentDaemon {
  _FakeDaemon(this.torrents, this.files);

  final List<TorrentStatus> torrents;
  final Map<String, List<Map<String, dynamic>>> files;

  @override
  Future<List<TorrentStatus>> listTorrents() async => torrents;

  @override
  Future<List<Map<String, dynamic>>> torrentFiles(String hash) async =>
      files[hash] ?? const [];

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

TorrentStatus status({
  required String hash,
  required String savePath,
  List<String> tags = const [],
}) =>
    TorrentStatus(
      hash: hash,
      name: hash,
      progress: 0.5,
      state: 'downloading',
      downloadSpeed: 0,
      sizeBytes: 0,
      downloadedBytes: 0,
      tags: tags,
      savePath: savePath,
    );

Map<String, dynamic> file(String name, double progress) =>
    {'name': name, 'progress': progress};

void main() {
  late AppDatabase db;
  late LibraryRepository repo;
  late ErrorLogService log;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DriftLibraryRepository(db);
    log = ErrorLogService();
  });
  tearDown(() async => db.close());

  // The season-pack tag the bulk download stamps: tmdb id 42, season 1.
  final packTag = acquisitionTag(
      acquisitionDedupeKey(tmdbId: 42, title: 'Show', season: 1));

  DownloadedEpisodeRegistrar registrarFor(_FakeDaemon d) =>
      DownloadedEpisodeRegistrar(d, repo, log);

  test('registers every finished episode file in a season pack', () async {
    final daemon = _FakeDaemon([
      status(hash: 'h1', savePath: '/disk1/tv', tags: [packTag]),
    ], {
      'h1': [
        file('Show.S01/Show.S01E01.mkv', 1.0),
        file('Show.S01/Show.S01E02.mkv', 1.0),
        file('Show.S01/Show.S01E03.mkv', 0.4), // still downloading
      ],
    });

    final n = await registrarFor(daemon).sweep();
    expect(n, 2);

    final rows = await repo.localEpisodes(42);
    expect(rows.map((r) => (r.season, r.episode)).toSet(), {(1, 1), (1, 2)});
    // Paths are the save path joined with the listed (relative) name.
    expect(rows.map((r) => r.filePath),
        contains(p.join('/disk1/tv', 'Show.S01/Show.S01E01.mkv')));
    // App-acquired, so they belong to the managed cleanup lifecycle.
    expect(rows.every((r) => r.managed), isTrue);
  });

  test('an unfinished file is registered on a later sweep, once done',
      () async {
    final files = [file('Show.S01E01.mkv', 0.2)];
    final daemon = _FakeDaemon(
      [status(hash: 'h1', savePath: '/d', tags: [packTag])],
      {'h1': files},
    );
    final registrar = registrarFor(daemon);

    expect(await registrar.sweep(), 0);
    expect(await repo.localEpisodes(42), isEmpty);

    files[0] = file('Show.S01E01.mkv', 1.0); // finishes
    expect(await registrar.sweep(), 1);
    expect(await repo.localEpisodes(42), hasLength(1));
  });

  test('is idempotent — a second sweep re-registers nothing', () async {
    final daemon = _FakeDaemon(
      [status(hash: 'h1', savePath: '/d', tags: [packTag])],
      {'h1': [file('Show.S01E01.mkv', 1.0)]},
    );
    final registrar = registrarFor(daemon);

    expect(await registrar.sweep(), 1);
    expect(await registrar.sweep(), 0);
    expect(await repo.localEpisodes(42), hasLength(1));
  });

  test('leaves an existing row completely alone', () async {
    // A row the acquire flow already wrote (it played this episode).
    await repo.upsert(const ScannedFile(
      filePath: '/d/Show.S01E01.mkv',
      title: 'Show — S01E01',
      mediaType: 'tv',
      season: 1,
      episode: 1,
      tmdbId: 42,
      tmdbName: 'Show',
    ));
    final daemon = _FakeDaemon(
      [status(hash: 'h1', savePath: '/d', tags: [packTag])],
      {'h1': [file('Show.S01E01.mkv', 1.0)]},
    );

    expect(await registrarFor(daemon).sweep(), 0);
    final row = (await repo.localEpisodes(42)).single;
    expect(row.title, 'Show — S01E01'); // not overwritten
  });

  test('reuses the show name an existing row already carries', () async {
    await repo.upsert(const ScannedFile(
      filePath: '/d/Show.S01E09.mkv',
      title: 'Show — S01E09',
      mediaType: 'tv',
      season: 1,
      episode: 9,
      tmdbId: 42,
      tmdbName: 'The Real Name',
    ));
    final daemon = _FakeDaemon(
      [status(hash: 'h1', savePath: '/d', tags: [packTag])],
      {'h1': [file('Show.S01E01.mkv', 1.0)]},
    );

    await registrarFor(daemon).sweep();
    final added = (await repo.localEpisodes(42))
        .firstWhere((r) => r.episode == 1);
    expect(added.tmdbName, 'The Real Name');
  });

  group('skips what it should', () {
    test('a torrent with no acquisition tag of ours', () async {
      final daemon = _FakeDaemon(
        [status(hash: 'h1', savePath: '/d', tags: ['someone-elses-tag'])],
        {'h1': [file('Show.S01E01.mkv', 1.0)]},
      );
      expect(await registrarFor(daemon).sweep(), 0);
    });

    test('a title-keyed tag (no numeric tmdb id to attribute files to)',
        () async {
      final tag = acquisitionTag(
          acquisitionDedupeKey(title: 'Some Show', season: 1));
      final daemon = _FakeDaemon(
        [status(hash: 'h1', savePath: '/d', tags: [tag])],
        {'h1': [file('Show.S01E01.mkv', 1.0)]},
      );
      expect(await registrarFor(daemon).sweep(), 0);
    });

    test('non-video files and files with no episode marker', () async {
      final daemon = _FakeDaemon(
        [status(hash: 'h1', savePath: '/d', tags: [packTag])],
        {
          'h1': [
            file('Show.S01E01.srt', 1.0), // subtitle
            file('readme.txt', 1.0),
            file('Show.Behind.The.Scenes.mkv', 1.0), // no SxxExx
          ]
        },
      );
      expect(await registrarFor(daemon).sweep(), 0);
    });

    test('a torrent the daemon reported no save path for', () async {
      final daemon = _FakeDaemon(
        [status(hash: 'h1', savePath: '', tags: [packTag])],
        {'h1': [file('Show.S01E01.mkv', 1.0)]},
      );
      expect(await registrarFor(daemon).sweep(), 0);
    });
  });

  test('a daemon failure is swallowed, not thrown at the caller', () async {
    // The daemon being down or mid-restart is routine; a sweep that throws
    // would escape into the periodic timer with nowhere to be caught.
    final registrar = DownloadedEpisodeRegistrar(_ThrowingDaemon(), repo, log);
    expect(await registrar.sweep(), 0);
    expect(await repo.getAll(), isEmpty);
  });

  test('the season in the filename wins over the one in the key', () async {
    // A "season 1" pack that actually contains a special/other season file:
    // what got downloaded is what we record.
    final daemon = _FakeDaemon(
      [status(hash: 'h1', savePath: '/d', tags: [packTag])],
      {'h1': [file('Show.S02E05.mkv', 1.0)]},
    );
    await registrarFor(daemon).sweep();
    final row = (await repo.localEpisodes(42)).single;
    expect((row.season, row.episode), (2, 5));
  });
}

class _ThrowingDaemon implements TorrentDaemon {
  @override
  Future<List<TorrentStatus>> listTorrents() async =>
      throw StateError('daemon down');

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}
