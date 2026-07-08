import 'dart:io';

import 'package:couch_roach/src/core/logging/error_log_service.dart';
import 'package:couch_roach/src/core/settings/settings_service.dart';
import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/data/opensubtitles/download_response.dart';
import 'package:couch_roach/src/data/opensubtitles/subtitle_result.dart';
import 'package:couch_roach/src/services/subtitles/movie_hasher.dart';
import 'package:couch_roach/src/services/subtitles/opensubtitles_client.dart';
import 'package:couch_roach/src/services/subtitles/subtitle_searcher.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

SubtitleResult _res(
  String id, {
  int downloads = 0,
  bool trusted = false,
  bool hi = false,
  bool withFile = true,
  String? release,
}) {
  return SubtitleResult(
    id: id,
    attributes: SubtitleAttributes(
      downloadCount: downloads,
      fromTrusted: trusted,
      hearingImpaired: hi,
      release: release,
      files: withFile ? [SubtitleFile(fileId: int.parse(id))] : const [],
    ),
  );
}

/// Records each search call and replays canned responses in order.
class _FakeClient implements SubtitleClient {
  _FakeClient(this._responses);
  final List<List<SubtitleResult>> _responses;
  final List<Map<String, Object?>> calls = [];
  var _i = 0;

  @override
  Future<List<SubtitleResult>> search({
    String? moviehash,
    String? query,
    int? tmdbId,
    int? parentTmdbId,
    int? season,
    int? episode,
    String language = 'en',
  }) async {
    calls.add({
      'moviehash': moviehash,
      'query': query,
      'tmdbId': tmdbId,
      'parentTmdbId': parentTmdbId,
      'season': season,
      'episode': episode,
    });
    return _i < _responses.length ? _responses[_i++] : const [];
  }

  @override
  Future<DownloadResponse?> requestDownload(int fileId) async => null;
}

class _FakeHasher implements MovieHasher {
  @override
  Future<String> hash(String path) async => 'deadbeefdeadbeef';
}

class _ThrowingHasher implements MovieHasher {
  @override
  Future<String> hash(String path) async => throw const FileSystemException('nope');
}

void main() {
  final log = ErrorLogService();
  late SettingsService settings;

  setUp(() async {
    settings = SettingsService(AppDatabase.forTesting(NativeDatabase.memory()));
    await settings.load();
  });

  group('pickBest', () {
    test('returns null on empty', () {
      expect(SubtitleSearcher.pickBest(const []), isNull);
    });

    test('skips results with no downloadable file', () {
      final only = _res('1', downloads: 999, withFile: false);
      expect(SubtitleSearcher.pickBest([only]), isNull);
    });

    test('ranks by download count', () {
      final best = SubtitleSearcher.pickBest([
        _res('1', downloads: 10),
        _res('2', downloads: 5000),
        _res('3', downloads: 300),
      ]);
      expect(best!.id, '2');
    });

    test('a trusted uploader beats a modestly-more-downloaded stranger', () {
      final best = SubtitleSearcher.pickBest([
        _res('1', downloads: 300),
        _res('2', downloads: 100, trusted: true),
      ]);
      expect(best!.id, '2'); // 100 + 500 boost > 300
    });

    test('an overwhelmingly popular sub still beats a trusted one', () {
      final best = SubtitleSearcher.pickBest([
        _res('1', downloads: 50000),
        _res('2', downloads: 100, trusted: true),
      ]);
      expect(best!.id, '1');
    });

    test('prefers non-hearing-impaired by default as a tiebreaker', () {
      final best = SubtitleSearcher.pickBest([
        _res('1', downloads: 100, hi: true),
        _res('2', downloads: 100, hi: false),
      ]);
      expect(best!.id, '2');
    });

    test('honors preferHearingImpaired', () {
      final best = SubtitleSearcher.pickBest(
        [
          _res('1', downloads: 100, hi: true),
          _res('2', downloads: 100, hi: false),
        ],
        preferHearingImpaired: true,
      );
      expect(best!.id, '1');
    });

    test('drops a sub whose release names a different episode', () {
      final best = SubtitleSearcher.pickBest(
        [
          _res('1', downloads: 5000, release: 'Show.S01E09.1080p'), // wrong ep
          _res('2', downloads: 10, release: 'Show.S01E01.1080p'),
        ],
        season: 1,
        episode: 1,
      );
      expect(best!.id, '2');
    });

    test('drops a sign-language release when excluded', () {
      final best = SubtitleSearcher.pickBest([
        _res('1', downloads: 5000, release: 'Show.S01E01.ASL'),
        _res('2', downloads: 10, release: 'Show.S01E01.1080p'),
      ]);
      expect(best!.id, '2');
    });

    test('a null release is never filtered out', () {
      final best = SubtitleSearcher.pickBest(
        [_res('1', downloads: 100)],
        season: 1,
        episode: 1,
      );
      expect(best!.id, '1');
    });
  });

  group('findBest orchestration', () {
    test('uses the hash search when it returns hits', () async {
      final client = _FakeClient([
        [_res('1', downloads: 10)],
      ]);
      final searcher = SubtitleSearcher(_FakeHasher(), client, log, settings);
      final best = await searcher.findBest('/movies/Film.mkv');
      expect(best!.id, '1');
      expect(client.calls, hasLength(1));
      expect(client.calls.single['moviehash'], 'deadbeefdeadbeef');
    });

    test('an episode uses parent_tmdb_id + season/episode when hash is empty',
        () async {
      final client = _FakeClient([
        const [], // hash miss
        [_res('7', downloads: 20)], // id-based hit
      ]);
      final searcher = SubtitleSearcher(_FakeHasher(), client, log, settings);
      final best = await searcher.findBest(
        '/tv/Show.S02E05.mkv',
        tmdbId: 1234,
        season: 2,
        episode: 5,
      );
      expect(best!.id, '7');
      final idCall = client.calls[1];
      expect(idCall['moviehash'], isNull);
      // The show id must go in parent_tmdb_id (with season/episode) — NOT
      // tmdb_id, which OpenSubtitles reads as the episode's own feature id.
      expect(idCall['parentTmdbId'], 1234);
      expect(idCall['tmdbId'], isNull);
      expect(idCall['season'], 2);
      expect(idCall['episode'], 5);
      // Only one unique hit so far, so the query search also runs to widen.
      expect(client.calls, hasLength(3));
      expect(client.calls[2]['query'], 'Show');
    });

    test('a movie uses a plain tmdb_id (no parent, no season/episode)',
        () async {
      final client = _FakeClient([
        const [], // hash miss
        [_res('3', downloads: 40)], // id-based hit
      ]);
      final searcher = SubtitleSearcher(_FakeHasher(), client, log, settings);
      final best = await searcher.findBest('/movies/Film.mkv', tmdbId: 555);
      expect(best!.id, '3');
      final idCall = client.calls[1];
      expect(idCall['tmdbId'], 555);
      expect(idCall['parentTmdbId'], isNull);
      expect(idCall['season'], isNull);
      expect(idCall['episode'], isNull);
    });

    test('id and query hits are merged and de-duplicated by file id', () async {
      // Same file id (7) from the id search and the query widen collapses to one
      // candidate; the distinct one (8) survives alongside it.
      final client = _FakeClient([
        const [], // hash miss
        [_res('7', downloads: 20)], // id-based
        [_res('7', downloads: 20), _res('8', downloads: 99)], // query widen
      ]);
      final searcher = SubtitleSearcher(_FakeHasher(), client, log, settings);
      final best = await searcher.findBest(
        '/tv/Show.S02E05.mkv',
        tmdbId: 1234,
        season: 2,
        episode: 5,
      );
      // 8 is the most-downloaded of the two unique survivors.
      expect(best!.id, '8');
    });

    test('parses filename for the query when there is no tmdb id', () async {
      final client = _FakeClient([
        const [], // hash miss
        [_res('9', downloads: 5)],
      ]);
      final searcher = SubtitleSearcher(_FakeHasher(), client, log, settings);
      final best = await searcher.findBest('/tv/Cool.Show.S01E02.720p.mkv');
      expect(best!.id, '9');
      final fallback = client.calls[1];
      expect(fallback['query'], 'Cool Show');
      expect(fallback['season'], 1);
      expect(fallback['episode'], 2);
      expect(fallback['tmdbId'], isNull);
    });

    test('a hasher failure degrades to the fallback search', () async {
      final client = _FakeClient([
        [_res('4', downloads: 1)], // this would be the fallback response
      ]);
      final searcher = SubtitleSearcher(_ThrowingHasher(), client, log, settings);
      final best = await searcher.findBest('/tv/Show.S01E01.mkv');
      expect(best!.id, '4');
      // Hash threw before a request, so the first (and only) call is the
      // filename fallback.
      expect(client.calls.single['moviehash'], isNull);
      expect(client.calls.single['query'], 'Show');
    });

    test('returns null when everything comes up empty', () async {
      final client = _FakeClient([const [], const []]);
      final searcher = SubtitleSearcher(_FakeHasher(), client, log, settings);
      expect(await searcher.findBest('/tv/Unknown.S01E01.mkv'), isNull);
    });
  });
}
