import 'package:couch_roach/src/core/logging/error_log_service.dart';
import 'package:couch_roach/src/core/settings/settings_service.dart';
import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/services/acquisition/acquisition.dart';
import 'package:couch_roach/src/services/acquisition/jackett_resolver.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _config = JackettConfig(baseUrl: 'http://127.0.0.1:9117', apiKey: 'KEY');

/// A settings service backed by an in-memory DB (defaults apply). [exclude]
/// seeds the sign-language toggle for tests that care.
Future<SettingsService> _settings({bool exclude = true}) async {
  final s = SettingsService(AppDatabase.forTesting(NativeDatabase.memory()));
  await s.load();
  if (!exclude) await s.setExcludeSignLanguage(false);
  return s;
}

// A Torznab (RSS) feed with the torznab namespace, mixing an enclosure-only row
// and a magneturl row.
const _feed = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="1.0" xmlns:torznab="http://torznab.com/schemas/2015/feed">
  <channel>
    <item>
      <title>Some.Movie.2020.1080p.BluRay</title>
      <enclosure url="http://127.0.0.1:9117/dl/x.torrent" length="1500000000"
                 type="application/x-bittorrent"/>
      <size>1500000000</size>
      <torznab:attr name="seeders" value="42"/>
      <torznab:attr name="peers" value="50"/>
    </item>
    <item>
      <title>Some.Movie.2020.720p</title>
      <link>magnet:?xt=urn:btih:ABC</link>
      <torznab:attr name="magneturl" value="magnet:?xt=urn:btih:ABC"/>
      <torznab:attr name="seeders" value="100"/>
      <size>800000000</size>
    </item>
  </channel>
</rss>''';

void main() {
  group('buildTorznabUri', () {
    test('tvsearch with season/episode + TV category', () {
      final uri = buildTorznabUri(
          _config, const ShowMeta(title: 'The Show'), 1, 2);
      expect(uri.path, '/api/v2.0/indexers/all/results/torznab/api');
      final q = uri.queryParameters;
      expect(q['apikey'], 'KEY');
      expect(q['t'], 'tvsearch');
      expect(q['q'], 'The Show');
      expect(q['cat'], '5000');
      expect(q['season'], '1');
      expect(q['ep'], '2');
    });

    test('movie search when there is no season/episode', () {
      final uri =
          buildTorznabUri(_config, const ShowMeta(title: 'A Film'), null, null);
      final q = uri.queryParameters;
      expect(q['t'], 'search');
      expect(q['cat'], '2000');
      expect(q.containsKey('season'), isFalse);
      expect(q.containsKey('ep'), isFalse);
    });

    test('a trailing slash on the base URL is not doubled', () {
      const cfg = JackettConfig(baseUrl: 'http://127.0.0.1:9117/', apiKey: 'K');
      final uri = buildTorznabUri(cfg, const ShowMeta(title: 'x'), null, null);
      expect(uri.toString(), contains('9117/api/v2.0/indexers/all'));
      expect(uri.toString(), isNot(contains('9117//api')));
    });
  });

  group('parseTorznabResults', () {
    final results = parseTorznabResults(_feed);

    test('parses each item with its download link + stats', () {
      expect(results, hasLength(2));

      final enclosureRow = results[0];
      expect(enclosureRow.title, 'Some.Movie.2020.1080p.BluRay');
      expect(enclosureRow.downloadUrl, 'http://127.0.0.1:9117/dl/x.torrent');
      expect(enclosureRow.seeders, 42);
      expect(enclosureRow.peers, 50);
      expect(enclosureRow.sizeBytes, 1500000000);

      final magnetRow = results[1];
      expect(magnetRow.downloadUrl, 'magnet:?xt=urn:btih:ABC');
      expect(magnetRow.seeders, 100);
    });

    test('drops an item with no usable download link', () {
      const noLink = '''<rss xmlns:torznab="http://torznab.com/schemas/2015/feed">
        <channel><item><title>No link</title>
        <torznab:attr name="seeders" value="9"/></item></channel></rss>''';
      expect(parseTorznabResults(noLink), isEmpty);
    });

    test('malformed XML yields an empty list (never throws)', () {
      expect(parseTorznabResults('not xml at all'), isEmpty);
      expect(parseTorznabResults(''), isEmpty);
    });
  });

  group('pickBestTorznabResult', () {
    test('returns null for an empty list', () {
      expect(pickBestTorznabResult(const []), isNull);
    });

    test('prefers the most seeders', () {
      final best = pickBestTorznabResult(parseTorznabResults(_feed));
      expect(best!.title, 'Some.Movie.2020.720p'); // 100 seeders > 42
    });

    test('breaks a seeder tie by larger size', () {
      final best = pickBestTorznabResult(const [
        TorznabResult(title: 'small', downloadUrl: 'magnet:a', seeders: 10, sizeBytes: 100),
        TorznabResult(title: 'big', downloadUrl: 'magnet:b', seeders: 10, sizeBytes: 900),
      ]);
      expect(best!.title, 'big');
    });

    test('a preferred audio language outranks pure seed health', () {
      final best = pickBestTorznabResult(
        const [
          TorznabResult(
              title: 'Some.Movie.2020.1080p', downloadUrl: 'magnet:en', seeders: 500),
          TorznabResult(
              title: 'Some.Movie.2020.1080p.Dublado.PT',
              downloadUrl: 'magnet:pt',
              seeders: 20),
        ],
        preferAudioLanguage: 'portuguese',
      );
      expect(best!.downloadUrl, 'magnet:pt');
    });

    test('within the preferred language, seed health still decides', () {
      final best = pickBestTorznabResult(
        const [
          TorznabResult(
              title: 'Some.Movie.Dublado', downloadUrl: 'magnet:pt-low', seeders: 5),
          TorznabResult(
              title: 'Some.Movie.Portugues', downloadUrl: 'magnet:pt-hi', seeders: 90),
        ],
        preferAudioLanguage: 'portuguese',
      );
      expect(best!.downloadUrl, 'magnet:pt-hi');
    });

    test('no preference leaves seed-health ranking unchanged', () {
      final best = pickBestTorznabResult(const [
        TorznabResult(title: 'Movie.Dublado', downloadUrl: 'magnet:pt', seeders: 20),
        TorznabResult(title: 'Movie.1080p', downloadUrl: 'magnet:en', seeders: 500),
      ]);
      expect(best!.downloadUrl, 'magnet:en');
    });
  });

  group('verifiedEpisodeResults', () {
    const meta = ShowMeta(title: 'Game of Thrones');
    TorznabResult r(String title, {int seeders = 10, int size = 900000000}) =>
        TorznabResult(
            title: title, downloadUrl: 'magnet:$title', seeders: seeders, sizeBytes: size);

    test('keeps only the exact requested episode of the right show', () {
      final kept = verifiedEpisodeResults([
        r('Game.of.Thrones.S01E01.1080p'),
        r('Game.of.Thrones.S01E09.1080p'), // wrong episode
        r('House.of.the.Dragon.S01E01.1080p'), // wrong show
        r('Game.of.Thrones.S01.1080p'), // season pack (no episode)
      ], meta, 1, 1);
      expect(kept.map((e) => e.title), ['Game.of.Thrones.S01E01.1080p']);
    });

    test('drops sign-language cuts by default but keeps them when allowed', () {
      final input = [
        r('Game.of.Thrones.S01E01.ASL.1080p'),
        r('Game.of.Thrones.S01E01.1080p'),
      ];
      expect(verifiedEpisodeResults(input, meta, 1, 1).map((e) => e.title),
          ['Game.of.Thrones.S01E01.1080p']);
      expect(
          verifiedEpisodeResults(input, meta, 1, 1, excludeSignLanguage: false)
              .length,
          2);
    });

    test('drops implausibly tiny files', () {
      final kept = verifiedEpisodeResults(
          [r('Game.of.Thrones.S01E01.1080p', size: 1024)], meta, 1, 1);
      expect(kept, isEmpty);
    });
  });

  group('seasonPackResults', () {
    const meta = ShowMeta(title: 'Game of Thrones');
    TorznabResult r(String title) =>
        TorznabResult(title: title, downloadUrl: 'magnet:$title', seeders: 10);

    test('keeps whole-season packs for the requested season only', () {
      final kept = seasonPackResults([
        r('Game.of.Thrones.S01.1080p'),
        r('Game.of.Thrones.Season.2.1080p'), // wrong season
        r('Game.of.Thrones.S01E05.1080p'), // single episode, not a pack
        r('House.of.the.Dragon.S01.1080p'), // wrong show
      ], meta, 1);
      expect(kept.map((e) => e.title), ['Game.of.Thrones.S01.1080p']);
    });
  });

  group('resolve — episode tiers', () {
    const meta = ShowMeta(title: 'Game of Thrones');

    String feed(List<String> titles) => '''<?xml version="1.0"?>
<rss xmlns:torznab="http://torznab.com/schemas/2015/feed"><channel>
${titles.map((t) => '<item><title>$t</title>'
            '<torznab:attr name="magneturl" value="magnet:$t"/>'
            '<torznab:attr name="seeders" value="50"/>'
            '<size>900000000</size></item>').join('\n')}
</channel></rss>''';

    test('Tier 1: returns a verified single episode, ignoring wrong ones',
        () async {
      final r = JackettResolver(
        MockClient((_) async => http.Response(
            feed(['Game.of.Thrones.S01E09.1080p', 'Game.of.Thrones.S01E01.1080p']),
            200)),
        ErrorLogService(),
        await _settings(),
      )..configure(_config);

      final handle = await r.resolve(meta, 1, 1);
      expect(handle, isNotNull);
      expect(handle!.displayName, 'Game.of.Thrones.S01E01.1080p');
      expect(handle.seasonPack, isFalse);
    });

    test('Tier 2: falls back to a season pack when no single episode verifies',
        () async {
      var call = 0;
      final r = JackettResolver(
        MockClient((req) async {
          call++;
          // First query (season+ep) → only a wrong episode; second (season-only)
          // → the pack.
          return http.Response(
              req.url.queryParameters.containsKey('ep')
                  ? feed(['Game.of.Thrones.S01E09.1080p'])
                  : feed(['Game.of.Thrones.S01.1080p']),
              200);
        }),
        ErrorLogService(),
        await _settings(),
      )..configure(_config);

      final handle = await r.resolve(meta, 1, 1);
      expect(handle, isNotNull);
      expect(handle!.displayName, 'Game.of.Thrones.S01.1080p');
      expect(handle.seasonPack, isTrue);
      expect(call, 2, reason: 'episode query, then a season-only pack query');
    });

    test('Tier 3: no verified source → null (fail loudly, no wrong guess)',
        () async {
      final r = JackettResolver(
        MockClient((_) async =>
            http.Response(feed(['Game.of.Thrones.S01E09.1080p']), 200)),
        ErrorLogService(),
        await _settings(),
      )..configure(_config);

      expect(await r.resolve(meta, 1, 1), isNull);
    });
  });

  group('parseJackettApiKey', () {
    test('reads the APIKey field', () {
      expect(parseJackettApiKey('{"APIKey":"abc123","Port":9117}'), 'abc123');
    });
    test('null when absent, empty, or malformed', () {
      expect(parseJackettApiKey('{"Port":9117}'), isNull);
      expect(parseJackettApiKey('{"APIKey":""}'), isNull);
      expect(parseJackettApiKey('nonsense'), isNull);
    });
  });

  group('resolve', () {
    Future<JackettResolver> resolver(http.Client client) async =>
        JackettResolver(client, ErrorLogService(), await _settings());

    test('returns null when not configured (sidecar not up)', () async {
      var called = false;
      final r = await resolver(MockClient((_) async {
        called = true;
        return http.Response(_feed, 200);
      }));
      expect(await r.resolve(const ShowMeta(title: 'x'), null, null), isNull);
      expect(called, isFalse, reason: 'no HTTP when unconfigured');
    });

    test('returns the best hit as a TorrentHandle when configured', () async {
      final r = (await resolver(MockClient((req) async {
        expect(req.url.queryParameters['apikey'], 'KEY');
        return http.Response(_feed, 200);
      })))
        ..configure(_config);

      final handle = await r.resolve(const ShowMeta(title: 'Some Movie'), null, null);
      expect(handle, isNotNull);
      expect(handle!.magnetOrUrl, 'magnet:?xt=urn:btih:ABC');
      expect(handle.displayName, 'Some.Movie.2020.720p');
    });

    test('null on a non-200 response', () async {
      final r = (await resolver(MockClient((_) async => http.Response('nope', 500))))
        ..configure(_config);
      expect(await r.resolve(const ShowMeta(title: 'x'), null, null), isNull);
    });

    test('null when the feed has no items', () async {
      const empty = '<rss><channel></channel></rss>';
      final r = (await resolver(MockClient((_) async => http.Response(empty, 200))))
        ..configure(_config);
      expect(await r.resolve(const ShowMeta(title: 'x'), null, null), isNull);
    });
  });
}
