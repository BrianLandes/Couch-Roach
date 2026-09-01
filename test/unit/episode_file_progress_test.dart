import 'package:couch_roach/src/services/acquisition/episode_file_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> f(String name, double progress) =>
      {'name': name, 'progress': progress};

  test('maps each episode file to its own progress', () {
    final out = episodeFileProgress([
      f('Show.S01/Show.S01E01.mkv', 1.0),
      f('Show.S01/Show.S01E02.mkv', 0.42),
      f('Show.S01/Show.S01E03.mkv', 0.0),
    ]);
    expect(out, {(1, 1): 1.0, (1, 2): 0.42, (1, 3): 0.0});
  });

  test('reads the season from the filename, not a caller assumption', () {
    final out = episodeFileProgress([f('Show.S02E05.mkv', 0.5)]);
    expect(out, {(2, 5): 0.5});
  });

  test('ignores non-video files and names with no episode marker', () {
    final out = episodeFileProgress([
      f('Show.S01E01.srt', 1.0),
      f('readme.txt', 1.0),
      f('Show.Behind.The.Scenes.mkv', 1.0),
      f('Show.S01E01.mkv', 0.3),
    ]);
    expect(out, {(1, 1): 0.3});
  });

  test('the furthest-along file wins when two claim the same episode', () {
    // A sample/duplicate must not drag the shown progress backwards.
    final out = episodeFileProgress([
      f('Sample/Show.S01E01.mkv', 0.05),
      f('Show.S01E01.mkv', 0.80),
    ]);
    expect(out, {(1, 1): 0.80});
  });

  test('clamps out-of-range progress and defaults a missing value to 0', () {
    final out = episodeFileProgress([
      f('Show.S01E01.mkv', 1.4),
      {'name': 'Show.S01E02.mkv'}, // no progress key
    ]);
    expect(out, {(1, 1): 1.0, (1, 2): 0.0});
  });

  test('empty and malformed entries yield an empty map', () {
    expect(episodeFileProgress(const []), isEmpty);
    expect(episodeFileProgress([{'progress': 1.0}]), isEmpty); // no name
    expect(episodeFileProgress([f('', 1.0)]), isEmpty);
  });
}
