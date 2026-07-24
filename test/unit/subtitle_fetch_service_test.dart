import 'dart:io';

import 'package:couch_roach/src/core/logging/error_log_service.dart';
import 'package:couch_roach/src/core/settings/settings_service.dart';
import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/data/opensubtitles/download_response.dart';
import 'package:couch_roach/src/data/opensubtitles/subtitle_result.dart';
import 'package:couch_roach/src/data/repositories/library_repository.dart';
import 'package:couch_roach/src/data/repositories/subtitle_attempts_repository.dart';
import 'package:couch_roach/src/services/subtitles/movie_hasher.dart';
import 'package:couch_roach/src/services/subtitles/opensubtitles_client.dart';
import 'package:couch_roach/src/services/subtitles/subtitle_fetch_service.dart';
import 'package:couch_roach/src/services/subtitles/subtitle_searcher.dart';
import 'package:couch_roach/src/services/subtitles/subtitle_skip_check.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// ── fakes for the external collaborators (the DB-backed ones are real) ─────────

class _FakeSkip extends SubtitleSkipCheck {
  _FakeSkip(this._has) : super(ErrorLogService());
  final bool _has;
  @override
  Future<bool> hasEnglish(String videoPath) async => _has;
}

class _NoHasher implements MovieHasher {
  @override
  Future<String> hash(String path) async => '';
}

class _FakeClient implements SubtitleClient {
  _FakeClient({this.download});
  final DownloadResponse? download;
  int requestCount = 0;

  @override
  Future<List<SubtitleResult>> search({
    String? moviehash,
    String? query,
    int? tmdbId,
    int? parentTmdbId,
    int? season,
    int? episode,
    String language = 'en',
  }) async =>
      const [];

  @override
  Future<DownloadResponse?> requestDownload(int fileId) async {
    requestCount++;
    return download;
  }
}

class _FakeSearcher extends SubtitleSearcher {
  _FakeSearcher(this._result, SettingsService settings)
      : super(_NoHasher(), _FakeClient(), ErrorLogService(), settings);
  final SubtitleResult? _result;
  @override
  Future<SubtitleResult?> findBest(
    String videoPath, {
    int? tmdbId,
    int? season,
    int? episode,
    String? title,
    bool preferHearingImpaired = false,
  }) async =>
      _result;
}

SubtitleResult _result(int fileId) => SubtitleResult(
      id: '$fileId',
      attributes: SubtitleAttributes(files: [SubtitleFile(fileId: fileId)]),
    );

void main() {
  late AppDatabase db;
  late DriftLibraryRepository library;
  late DriftSubtitleAttemptsRepository attempts;
  late Directory tmp;
  final log = ErrorLogService();

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = DriftLibraryRepository(db);
    attempts = DriftSubtitleAttemptsRepository(db);
    tmp = await Directory.systemTemp.createTemp('cr_subdl');
  });
  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<int> addItem(String path) async {
    await library.upsert(
        ScannedFile(filePath: path, title: 'x', mediaType: 'movie'));
    return (await library.findByPath(path))!.id;
  }

  OpenSubtitlesSubtitleService build({
    required bool hasEnglish,
    SubtitleResult? searchResult,
    DownloadResponse? download,
    http.Client? httpClient,
  }) {
    return OpenSubtitlesSubtitleService(
      _FakeSkip(hasEnglish),
      _FakeSearcher(searchResult, SettingsService(db)),
      _FakeClient(download: download),
      attempts,
      library,
      httpClient ?? MockClient((_) async => http.Response('SRT', 200)),
      log,
    );
  }

  test('already-present English records present and skips download', () async {
    final path = '${tmp.path}/Movie.mkv';
    final id = await addItem(path);
    final service = build(hasEnglish: true);

    final result = await service.ensureEnglish(path);

    expect(result, isNull); // embedded English → no sidecar path
    expect(File('${tmp.path}/Movie.en.srt').existsSync(), isFalse);
    expect(await attempts.downloadsToday(), 0); // present isn't a download
    // Item is now terminal → out of the queue.
    final need = await attempts.itemsNeedingSubtitles();
    expect(need.where((e) => e.id == id), isEmpty);
  });

  test('force bypasses the skip-check and downloads even with English present',
      () async {
    // The empty-embedded-English case: skip-check says "has English", but the
    // manual (force) path must still fetch a real transcript.
    final path = '${tmp.path}/Empty.mkv';
    final id = await addItem(path);
    final service = build(
      hasEnglish: true, // skip-check would normally short-circuit
      searchResult: _result(99),
      download: DownloadResponse(link: 'https://dl.example/real.srt'),
      httpClient: MockClient((_) async =>
          http.Response('1\n00:00:01,000 --> 00:00:02,000\nReal\n', 200)),
    );

    final result = await service.ensureEnglish(path, force: true);

    final expected = '${tmp.path}/Empty.en.srt';
    expect(result, expected);
    expect(File(expected).readAsStringSync(), contains('Real'));
    expect(await attempts.downloadsToday(), 1);
    // The item is no longer stuck as "present".
    final need = await attempts.itemsNeedingSubtitles();
    expect(need.where((e) => e.id == id), isEmpty);
  });

  test('a found subtitle is downloaded and saved as <name>.en.srt', () async {
    final path = '${tmp.path}/Film.mkv';
    await addItem(path);
    var served = false;
    final service = build(
      hasEnglish: false,
      searchResult: _result(42),
      download: DownloadResponse(link: 'https://dl.example/sub.srt'),
      httpClient: MockClient((req) async {
        served = req.url.toString() == 'https://dl.example/sub.srt';
        return http.Response('1\n00:00:01,000 --> 00:00:02,000\nHi\n', 200);
      }),
    );

    final result = await service.ensureEnglish(path);

    final expected = '${tmp.path}/Film.en.srt';
    expect(result, expected);
    expect(File(expected).existsSync(), isTrue);
    expect(File(expected).readAsStringSync(), contains('Hi'));
    expect(served, isTrue);
    expect(await attempts.downloadsToday(), 1);
  });

  test('no search match records not_found and returns null', () async {
    final path = '${tmp.path}/Nope.mkv';
    await addItem(path);
    final service = build(hasEnglish: false, searchResult: null);

    expect(await service.ensureEnglish(path), isNull);
    expect(File('${tmp.path}/Nope.en.srt').existsSync(), isFalse);
    expect(await attempts.downloadsToday(), 0);
  });

  test('a refused download (quota) records quota and leaves the item eligible',
      () async {
    final path = '${tmp.path}/Later.mkv';
    final id = await addItem(path);
    final service = build(
      hasEnglish: false,
      searchResult: _result(7),
      download: null, // requestDownload refused
    );

    expect(await service.ensureEnglish(path), isNull);
    // quota is transient → still a candidate.
    final need = await attempts.itemsNeedingSubtitles();
    expect(need.map((e) => e.id), contains(id));
  });

  group('processQueue', () {
    test('downloads up to the budget then stops', () async {
      await addItem('${tmp.path}/A.mkv');
      await addItem('${tmp.path}/B.mkv');
      final service = build(
        hasEnglish: false,
        searchResult: _result(1),
        download: DownloadResponse(link: 'https://dl.example/s.srt'),
      );

      final saved = await service.processQueue(max: 1);

      expect(saved, 1);
      expect(await attempts.downloadsToday(), 1);
      // One item still needs subtitles (budget stopped us).
      expect(await attempts.itemsNeedingSubtitles(), hasLength(1));
    });

    test('stops early and returns 0 when the quota is hit', () async {
      await addItem('${tmp.path}/A.mkv');
      await addItem('${tmp.path}/B.mkv');
      final service = build(
        hasEnglish: false,
        searchResult: _result(1),
        download: null, // every download refused
      );

      expect(await service.processQueue(max: 5), 0);
    });

    test('does nothing once the daily budget is spent', () async {
      final id = await addItem('${tmp.path}/A.mkv');
      await attempts.record(id, SubtitleAttemptStatus.found); // "spent" today
      final service = build(hasEnglish: false, searchResult: _result(1));

      // Only 1 download allowed/day and it's already used.
      expect(await service.processQueue(max: 1), 0);
    });
  });
}
