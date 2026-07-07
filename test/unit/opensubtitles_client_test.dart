import 'dart:convert';

import 'package:couch_roach/src/core/logging/error_log_service.dart';
import 'package:couch_roach/src/services/subtitles/opensubtitles_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  OpenSubtitlesClient clientFor(MockClient mock) =>
      OpenSubtitlesClient(mock, ErrorLogService());

  test('search parses results and exposes the primary file id', () async {
    final client = clientFor(MockClient((req) async {
      expect(req.headers['User-Agent'], isNotNull); // mandatory header sent
      return http.Response(
          jsonEncode({
            'data': [
              {
                'id': '7061050',
                'type': 'subtitle',
                'attributes': {
                  'language': 'en',
                  'download_count': 12345,
                  'hearing_impaired': false,
                  'from_trusted': true,
                  'files': [
                    {'file_id': 999, 'file_name': 'show.s01e01.en.srt'},
                  ],
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));

    final results = await client.search(query: 'The Show', season: 1, episode: 1);
    expect(results, hasLength(1));
    expect(results.first.attributes.language, 'en');
    expect(results.first.attributes.downloadCount, 12345);
    expect(results.first.attributes.fromTrusted, isTrue);
    expect(results.first.fileId, 999);
  });

  test('requestDownload parses the link and quota', () async {
    final client = clientFor(MockClient((req) async {
      expect(req.method, 'POST');
      expect(jsonDecode(req.body), {'file_id': 999});
      return http.Response(
          jsonEncode({
            'link': 'https://download.opensubtitles.com/tmp/abc.srt',
            'file_name': 'show.s01e01.en.srt',
            'remaining': 19,
            'requests': 1,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));

    final dl = await client.requestDownload(999);
    expect(dl, isNotNull);
    expect(dl!.link, contains('abc.srt'));
    expect(dl.remaining, 19);
  });

  test('non-200 degrades to empty/null (logged, not thrown)', () async {
    final client = clientFor(MockClient((_) async => http.Response('{}', 401)));
    expect(await client.search(query: 'x'), isEmpty);
    expect(await client.requestDownload(1), isNull);
  });
}
