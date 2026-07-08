import 'dart:io';

import 'package:couch_roach/src/core/logging/error_log_service.dart';
import 'package:couch_roach/src/services/subtitles/subtitle_skip_check.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('cr_skip'));
  tearDown(() async => tmp.deleteSync(recursive: true));

  String touch(String name) {
    final f = File('${tmp.path}/$name')..writeAsStringSync('x');
    return f.path;
  }

  group('hasEnglishSidecar', () {
    test('false when nothing but the video is present', () {
      final video = touch('Movie.mkv');
      expect(SubtitleSkipCheck.hasEnglishSidecar(video), isFalse);
    });

    test('true for a .en.srt sidecar', () {
      final video = touch('Movie.mkv');
      touch('Movie.en.srt');
      expect(SubtitleSkipCheck.hasEnglishSidecar(video), isTrue);
    });

    test('true for a .eng.srt sidecar', () {
      final video = touch('Movie.mkv');
      touch('Movie.eng.srt');
      expect(SubtitleSkipCheck.hasEnglishSidecar(video), isTrue);
    });

    test('true for a .english.srt sidecar', () {
      final video = touch('Movie.mkv');
      touch('Movie.english.srt');
      expect(SubtitleSkipCheck.hasEnglishSidecar(video), isTrue);
    });

    test('true for a bare .srt sidecar', () {
      final video = touch('Movie.mkv');
      touch('Movie.srt');
      expect(SubtitleSkipCheck.hasEnglishSidecar(video), isTrue);
    });

    test('a sidecar for a different base name does not match', () {
      final video = touch('Movie.mkv');
      touch('Other.en.srt');
      expect(SubtitleSkipCheck.hasEnglishSidecar(video), isFalse);
    });
  });

  group('hasEnglish (public entry)', () {
    test('returns true immediately when a sidecar exists', () async {
      final check = SubtitleSkipCheck(ErrorLogService());
      final video = touch('Movie.mkv');
      touch('Movie.en.srt');
      expect(await check.hasEnglish(video), isTrue);
    });
  });

  group('isEnglish', () {
    test('matches en / eng / english language codes', () {
      expect(SubtitleSkipCheck.isEnglish('en', null), isTrue);
      expect(SubtitleSkipCheck.isEnglish('ENG', null), isTrue);
      expect(SubtitleSkipCheck.isEnglish('English', null), isTrue);
    });

    test('matches a title naming English when the language is absent', () {
      expect(SubtitleSkipCheck.isEnglish(null, 'English (SDH)'), isTrue);
    });

    test('is false for other languages and empty input', () {
      expect(SubtitleSkipCheck.isEnglish('spa', 'Español'), isFalse);
      expect(SubtitleSkipCheck.isEnglish(null, null), isFalse);
    });
  });

  group('ffprobeJsonHasEnglish', () {
    test('true for a subtitle stream tagged language=eng', () {
      const json = '''
      {"streams":[
        {"codec_type":"video"},
        {"codec_type":"subtitle","tags":{"language":"eng"}}
      ]}''';
      expect(SubtitleSkipCheck.ffprobeJsonHasEnglish(json), isTrue);
    });

    test('true for the uppercase LANGUAGE tag variant', () {
      const json =
          '{"streams":[{"codec_type":"subtitle","tags":{"LANGUAGE":"en"}}]}';
      expect(SubtitleSkipCheck.ffprobeJsonHasEnglish(json), isTrue);
    });

    test('true when only the title names English', () {
      const json =
          '{"streams":[{"codec_type":"subtitle","tags":{"title":"English (SDH)"}}]}';
      expect(SubtitleSkipCheck.ffprobeJsonHasEnglish(json), isTrue);
    });

    test('false for a non-English subtitle stream', () {
      const json =
          '{"streams":[{"codec_type":"subtitle","tags":{"language":"spa"}}]}';
      expect(SubtitleSkipCheck.ffprobeJsonHasEnglish(json), isFalse);
    });

    test('false when the only English track is not a subtitle', () {
      const json =
          '{"streams":[{"codec_type":"audio","tags":{"language":"eng"}}]}';
      expect(SubtitleSkipCheck.ffprobeJsonHasEnglish(json), isFalse);
    });

    test('false for no streams', () {
      expect(SubtitleSkipCheck.ffprobeJsonHasEnglish('{"streams":[]}'), isFalse);
    });

    test('false (not a throw) for malformed json', () {
      expect(SubtitleSkipCheck.ffprobeJsonHasEnglish('not json'), isFalse);
    });
  });
}
