import 'dart:convert';

import 'package:couch_roach/src/core/logging/error_log_service.dart';
import 'package:couch_roach/src/core/settings/settings_service.dart';
import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/services/acquisition/acquisition.dart';
import 'package:couch_roach/src/services/acquisition/composite_resolver.dart';
import 'package:couch_roach/src/services/acquisition/internet_archive_resolver.dart';
import 'package:couch_roach/src/services/acquisition/jackett_resolver.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _config = JackettConfig(baseUrl: 'http://127.0.0.1:9117', apiKey: 'K');

// A minimal Torznab feed with a single magnet result.
const _feed = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="1.0" xmlns:torznab="http://torznab.com/schemas/2015/feed">
  <channel>
    <item>
      <title>Some.Movie.2020</title>
      <link>magnet:?xt=urn:btih:ABC</link>
      <torznab:attr name="magneturl" value="magnet:?xt=urn:btih:ABC"/>
      <torznab:attr name="seeders" value="100"/>
      <size>800000000</size>
    </item>
  </channel>
</rss>''';

void main() {
  final log = ErrorLogService();
  const meta = ShowMeta(title: 'X', tmdbId: 42, mediaType: 'movie');

  final settings = SettingsService(AppDatabase.forTesting(NativeDatabase.memory()));

  InternetArchiveResolver ia(http.Client c) => InternetArchiveResolver(c, log);
  JackettResolver jackett(http.Client c, {JackettConfig? config}) {
    final r = JackettResolver(c, log, settings);
    if (config != null) r.configure(config);
    return r;
  }

  http.Client dead() => MockClient((_) async => http.Response('', 500));

  test('returns null when no sub-resolver finds anything', () async {
    // IA errors; Jackett is unconfigured (returns null immediately).
    final composite = CompositeAcquisitionResolver(ia(dead()), jackett(dead()), log);
    expect(await composite.resolve(meta, null, null), isNull);
  });

  test('falls through to Jackett when Internet Archive has nothing', () async {
    final jClient = MockClient((_) async => http.Response(_feed, 200));
    final composite = CompositeAcquisitionResolver(
      ia(dead()),
      jackett(jClient, config: _config),
      log,
    );
    final hit = await composite.resolve(meta, null, null);
    expect(hit, isNotNull);
    expect(hit!.magnetOrUrl, startsWith('magnet:'));
  });

  test('Internet Archive wins and short-circuits before Jackett', () async {
    final iaClient = MockClient((req) async {
      if (req.url.path.contains('advancedsearch')) {
        return http.Response(
          jsonEncode({
            'response': {
              'docs': [
                {'identifier': 'pd-film', 'title': 'PD Film'},
              ],
            },
          }),
          200,
        );
      }
      // metadata/{id} → an item with a video file
      return http.Response(
        jsonEncode({
          'files': [
            {'name': 'movie.mp4'},
          ],
        }),
        200,
      );
    });
    // If the composite ever consulted Jackett here, this would throw — proving
    // IA's hit short-circuits the chain.
    final jClient =
        MockClient((_) async => throw StateError('Jackett should not be called'));
    final composite = CompositeAcquisitionResolver(
      ia(iaClient),
      jackett(jClient, config: _config),
      log,
    );
    final hit = await composite.resolve(meta, null, null);
    expect(hit, isNotNull);
    expect(hit!.magnetOrUrl, contains('archive.org'));
  });
}
