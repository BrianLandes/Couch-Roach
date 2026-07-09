import 'package:couch_roach/src/features/player/credits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('creditsStart', () {
    test('null for a clip shorter than the minimum', () {
      expect(creditsStart(duration: const Duration(minutes: 3)), isNull);
    });

    test('uses a credits chapter in the back third', () {
      final start = creditsStart(
        duration: const Duration(minutes: 45),
        chapters: const [
          VideoChapter(start: Duration(minutes: 2), title: 'Cold Open'),
          VideoChapter(start: Duration(minutes: 42), title: 'End Credits'),
        ],
      );
      expect(start, const Duration(minutes: 42));
    });

    test('ignores a credits-named chapter that is too early', () {
      // A "credits" chapter at the very start (e.g. an opening titles marker)
      // is not the end credits — fall through to the heuristic.
      final start = creditsStart(
        duration: const Duration(minutes: 45),
        chapters: const [
          VideoChapter(start: Duration(seconds: 30), title: 'Opening Credits'),
        ],
      );
      // 6% of 2700s = 162s, capped at 180s → trigger at 2700-162 = 2538s.
      expect(start, const Duration(seconds: 2700 - 162));
    });

    test('heuristic tail is clamped to the max for long runtimes', () {
      // 6% of 90min (5400s) = 324s → clamped to 180s.
      final start = creditsStart(duration: const Duration(minutes: 90));
      expect(start, const Duration(seconds: 5400 - 180));
    });

    test('heuristic tail is clamped to the min for short episodes', () {
      // 6% of 10min (600s) = 36s → clamped up to 45s.
      final start = creditsStart(duration: const Duration(minutes: 10));
      expect(start, const Duration(seconds: 600 - 45));
    });

    test('uses TMDB content runtime when the file runs meaningfully longer', () {
      // 25-min file, 22-min aired episode → the 3-min tail is credits/extras.
      final start = creditsStart(
        duration: const Duration(minutes: 25),
        contentRuntime: const Duration(minutes: 22),
      );
      expect(start, const Duration(minutes: 22));
    });

    test('ignores TMDB runtime when the gap is tiny (≈ the whole file)', () {
      // File ≈ runtime (30s gap): the runtime spans the credits too → heuristic.
      final start = creditsStart(
        duration: const Duration(seconds: 22 * 60 + 30),
        contentRuntime: const Duration(minutes: 22),
      );
      // 6% of 1350s = 81s → trigger at 1350-81.
      expect(start, const Duration(seconds: 1350 - 81));
    });

    test('ignores an implausible TMDB runtime (< half the file)', () {
      // 45-min file, 20-min "runtime" (wrong episode / season-pack) → ignored.
      final start = creditsStart(
        duration: const Duration(minutes: 45),
        contentRuntime: const Duration(minutes: 20),
      );
      expect(start, const Duration(seconds: 2700 - 162)); // heuristic
    });

    test('a credits chapter still wins over the TMDB runtime', () {
      final start = creditsStart(
        duration: const Duration(minutes: 25),
        contentRuntime: const Duration(minutes: 22),
        chapters: const [
          VideoChapter(start: Duration(minutes: 23), title: 'End Credits'),
        ],
      );
      expect(start, const Duration(minutes: 23));
    });
  });

  group('parseFfprobeChapters', () {
    test('parses start + title', () {
      const json = '''
      {"chapters":[
        {"start_time":"0.000000","tags":{"title":"Intro"}},
        {"start_time":"1325.400000","tags":{"title":"Credits"}}
      ]}''';
      final chapters = parseFfprobeChapters(json);
      expect(chapters, hasLength(2));
      expect(chapters[1].start, const Duration(milliseconds: 1325400));
      expect(chapters[1].title, 'Credits');
    });

    test('skips entries without a numeric start and tolerates missing tags', () {
      const json =
          '{"chapters":[{"start_time":"nope"},{"start_time":"5.0"}]}';
      final chapters = parseFfprobeChapters(json);
      expect(chapters, hasLength(1));
      expect(chapters.single.title, '');
    });

    test('empty / malformed json yields no chapters', () {
      expect(parseFfprobeChapters('{"chapters":[]}'), isEmpty);
      expect(parseFfprobeChapters('not json'), isEmpty);
    });
  });
}
