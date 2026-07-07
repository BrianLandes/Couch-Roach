import 'dart:convert';

import 'package:couch_roach/src/core/logging/error_log_service.dart';
import 'package:couch_roach/src/services/acquisition/archive_browse_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('curatedPicksQuery restricts to movies in the vetted collections', () {
    expect(curatedPicksQuery,
        'mediatype:(movies) AND collection:(silent_films OR classic_cartoons)');
    // Guardrail: the open, unvetted movie feed must never be a source.
    expect(curatedPicksQuery, isNot(contains('feature_films')));
  });

  group('ArchiveItem.fromDoc', () {
    test('parses identifier, title, year, and item_size', () {
      final item = ArchiveItem.fromDoc({
        'identifier': 'popeye_patriotic_popeye',
        'title': 'Patriotic Popeye',
        'year': 1957,
        'item_size': 215152653,
      })!;
      expect(item.title, 'Patriotic Popeye');
      expect(item.year, 1957);
      expect(item.sizeBytes, 215152653);
      expect(item.thumbnailUrl,
          'https://archive.org/services/img/popeye_patriotic_popeye');
    });

    test('coerces list/string fields and tolerates missing ones', () {
      final item = ArchiveItem.fromDoc({
        'identifier': 'x',
        'title': ['First Title', 'alt'],
        'year': '1925',
      })!;
      expect(item.title, 'First Title');
      expect(item.year, 1925);
      expect(item.sizeBytes, 0);
    });

    test('returns null without a usable identifier', () {
      expect(ArchiveItem.fromDoc({'title': 'no id'}), isNull);
      expect(ArchiveItem.fromDoc({'identifier': ''}), isNull);
    });
  });

  group('popularPicks', () {
    ArchiveBrowseService service(MockClient c) =>
        ArchiveBrowseService(c, ErrorLogService());

    test('parses the search response and skips malformed docs', () async {
      final c = MockClient((req) async {
        expect(req.url.path, '/advancedsearch.php');
        expect(req.url.queryParameters['sort[]'], 'downloads desc');
        return http.Response(
          jsonEncode({
            'response': {
              'docs': [
                {'identifier': 'a', 'title': 'A', 'item_size': 10},
                {'title': 'no identifier'}, // dropped
                {'identifier': 'b', 'title': 'B'},
              ]
            }
          }),
          200,
        );
      });
      final picks = await service(c).popularPicks();
      expect(picks.map((p) => p.identifier), ['a', 'b']);
    });

    test('returns [] on a non-200 response', () async {
      final c = MockClient((_) async => http.Response('nope', 503));
      expect(await service(c).popularPicks(), isEmpty);
    });
  });
}
