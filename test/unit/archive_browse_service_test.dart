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

  group('archiveSearchQuery', () {
    test('builds a title-scoped movies query', () {
      expect(archiveSearchQuery('Night of the Living Dead'),
          'title:(Night of the Living Dead) AND mediatype:(movies)');
    });
    test('strips Lucene metacharacters', () {
      expect(archiveSearchQuery('Fear & Loathing: (1998)'),
          'title:(Fear Loathing 1998) AND mediatype:(movies)');
    });
    test('returns null for empty / whitespace-only text', () {
      expect(archiveSearchQuery('   '), isNull);
      expect(archiveSearchQuery('()'), isNull);
    });
  });

  group('search', () {
    test('queries advancedsearch and parses results', () async {
      late Uri requested;
      final c = MockClient((req) async {
        requested = req.url;
        return http.Response(
          jsonEncode({
            'response': {
              'docs': [
                {'identifier': 'notld', 'title': 'Night of the Living Dead'}
              ]
            }
          }),
          200,
        );
      });
      final results =
          await ArchiveBrowseService(c, ErrorLogService()).search('living dead');
      expect(results.single.identifier, 'notld');
      expect(requested.queryParameters['q'], contains('title:(living dead)'));
    });

    test('an empty query short-circuits to no results (no request)', () async {
      var called = false;
      final c = MockClient((_) async {
        called = true;
        return http.Response('[]', 200);
      });
      expect(await ArchiveBrowseService(c, ErrorLogService()).search('  '),
          isEmpty);
      expect(called, isFalse);
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

  group('ArchiveDetail.fromMetadata', () {
    final detail = ArchiveDetail.fromMetadata('notld', {
      'metadata': {
        'title': 'Night of the Living Dead',
        'date': '1968-10-01',
        'creator': 'George A. Romero',
        'description': '<p>A group is <b>trapped</b>.<br>Zombies &amp; more.</p>',
      },
      'files': [
        {'name': 'notld.mp4', 'format': 'h.264', 'size': '600000000'},
        {'name': 'notld.ogv', 'format': 'Ogg Video', 'size': '450000000'},
        {'name': 'notld_meta.xml', 'format': 'Metadata', 'size': '2000'},
        {'name': 'notld_archive.torrent', 'format': 'Archive BitTorrent'},
      ],
    });

    test('parses title, creator, and year (from a date field)', () {
      expect(detail.title, 'Night of the Living Dead');
      expect(detail.creator, 'George A. Romero');
      expect(detail.year, 1968);
    });

    test('strips HTML and entities from the description', () {
      expect(detail.description, 'A group is trapped.\nZombies & more.');
    });

    test('keeps only video files, largest first', () {
      expect(detail.videos.map((v) => v.name), ['notld.mp4', 'notld.ogv']);
      expect(detail.videos.first.sizeBytes, 600000000);
    });

    test('falls back to the identifier when title is missing', () {
      final d = ArchiveDetail.fromMetadata('some_id', {'metadata': {}});
      expect(d.title, 'some_id');
      expect(d.year, isNull);
      expect(d.videos, isEmpty);
    });

    test('reads year straight from a year field too', () {
      final d = ArchiveDetail.fromMetadata('x', {
        'metadata': {'year': '1925'}
      });
      expect(d.year, 1925);
    });
  });
}
