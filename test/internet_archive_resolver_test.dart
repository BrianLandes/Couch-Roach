import 'dart:convert';

import 'package:couch_roach/src/core/logging/error_log_service.dart';
import 'package:couch_roach/src/services/acquisition/acquisition.dart';
import 'package:couch_roach/src/services/acquisition/internet_archive_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('buildInternetArchiveQuery', () {
    test('scopes to title + movies mediatype', () {
      final q = buildInternetArchiveQuery(
          const ShowMeta(title: 'Night of the Living Dead'), null, null);
      expect(q, 'title:(Night of the Living Dead) AND mediatype:(movies)');
    });

    test('strips Lucene metacharacters from the title', () {
      final q = buildInternetArchiveQuery(
          const ShowMeta(title: 'Fear & Loathing: (1998)!'), null, null);
      expect(q, 'title:(Fear Loathing 1998) AND mediatype:(movies)');
    });

    test('appends a zero-padded SxxExx when season/episode are given', () {
      final q =
          buildInternetArchiveQuery(const ShowMeta(title: 'Show'), 1, 3);
      expect(q, 'title:(Show S01E03) AND mediatype:(movies)');
    });
  });

  test('internetArchiveTorrentUrl builds the item torrent URL', () {
    expect(
      internetArchiveTorrentUrl('night_of_the_living_dead_dvd'),
      'https://archive.org/download/night_of_the_living_dead_dvd/'
      'night_of_the_living_dead_dvd_archive.torrent',
    );
  });

  group('fileLooksLikeVideo', () {
    test('detects by extension', () {
      expect(fileLooksLikeVideo({'name': 'Movie.mp4'}), isTrue);
    });
    test('detects by IA format when the extension is unknown', () {
      expect(fileLooksLikeVideo({'name': 'Night.ogv', 'format': 'Ogg Video'}),
          isTrue);
      expect(fileLooksLikeVideo({'name': 'clip.mpg', 'format': 'MPEG2'}), isTrue);
    });
    test('rejects the torrent and metadata entries', () {
      expect(
          fileLooksLikeVideo(
              {'name': 'x_archive.torrent', 'format': 'Archive BitTorrent'}),
          isFalse);
      expect(fileLooksLikeVideo({'name': 'x_meta.xml', 'format': 'Metadata'}),
          isFalse);
    });
  });

  group('resolve', () {
    // Canned IA responses routed by URL path.
    MockClient client(Map<String, Object> metadataById, {List<String>? ids}) {
      final docs = (ids ?? metadataById.keys.toList())
          .map((id) => {'identifier': id, 'title': 'Title $id'})
          .toList();
      return MockClient((req) async {
        if (req.url.path == '/advancedsearch.php') {
          return http.Response(
              jsonEncode({
                'response': {'docs': docs}
              }),
              200);
        }
        if (req.url.path.startsWith('/metadata/')) {
          final id = req.url.path.substring('/metadata/'.length);
          return http.Response(jsonEncode(metadataById[id] ?? {}), 200);
        }
        return http.Response('not found', 404);
      });
    }

    InternetArchiveResolver resolver(MockClient c) =>
        InternetArchiveResolver(c, ErrorLogService());

    test('returns the torrent URL for the first item that has video', () async {
      final c = client({
        'good_film': {
          'files': [
            {'name': 'movie.mp4', 'format': 'h.264'}
          ]
        }
      });
      final handle = await resolver(c)
          .resolve(const ShowMeta(title: 'Good Film'), null, null);
      expect(handle, isNotNull);
      expect(handle!.magnetOrUrl, internetArchiveTorrentUrl('good_film'));
      expect(handle.displayName, 'Title good_film');
    });

    test('skips a candidate with no video and takes the next', () async {
      final c = client(
        {
          'audio_only': {
            'files': [
              {'name': 'song.mp3', 'format': 'VBR MP3'}
            ]
          },
          'real_film': {
            'files': [
              {'name': 'film.ogv', 'format': 'Ogg Video'}
            ]
          },
        },
        ids: ['audio_only', 'real_film'],
      );
      final handle =
          await resolver(c).resolve(const ShowMeta(title: 'x'), null, null);
      expect(handle!.magnetOrUrl, internetArchiveTorrentUrl('real_film'));
    });

    test('returns null when nothing matches', () async {
      final c = client({}, ids: const []);
      final handle =
          await resolver(c).resolve(const ShowMeta(title: 'nope'), null, null);
      expect(handle, isNull);
    });
  });
}
