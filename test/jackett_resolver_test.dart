import 'package:couch_roach/src/core/logging/error_log_service.dart';
import 'package:couch_roach/src/services/acquisition/acquisition.dart';
import 'package:couch_roach/src/services/acquisition/jackett_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _config = JackettConfig(baseUrl: 'http://127.0.0.1:9117', apiKey: 'KEY');

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
    JackettResolver resolver(http.Client client) =>
        JackettResolver(client, ErrorLogService());

    test('returns null when not configured (sidecar not up)', () async {
      var called = false;
      final r = resolver(MockClient((_) async {
        called = true;
        return http.Response(_feed, 200);
      }));
      expect(await r.resolve(const ShowMeta(title: 'x'), null, null), isNull);
      expect(called, isFalse, reason: 'no HTTP when unconfigured');
    });

    test('returns the best hit as a TorrentHandle when configured', () async {
      final r = resolver(MockClient((req) async {
        expect(req.url.queryParameters['apikey'], 'KEY');
        return http.Response(_feed, 200);
      }))
        ..configure(_config);

      final handle = await r.resolve(const ShowMeta(title: 'Some Movie'), null, null);
      expect(handle, isNotNull);
      expect(handle!.magnetOrUrl, 'magnet:?xt=urn:btih:ABC');
      expect(handle.displayName, 'Some.Movie.2020.720p');
    });

    test('null on a non-200 response', () async {
      final r = resolver(MockClient((_) async => http.Response('nope', 500)))
        ..configure(_config);
      expect(await r.resolve(const ShowMeta(title: 'x'), null, null), isNull);
    });

    test('null when the feed has no items', () async {
      const empty = '<rss><channel></channel></rss>';
      final r = resolver(MockClient((_) async => http.Response(empty, 200)))
        ..configure(_config);
      expect(await r.resolve(const ShowMeta(title: 'x'), null, null), isNull);
    });
  });
}
