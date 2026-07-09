import 'package:couch_roach/src/features/player/player_title.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('composePlayerTitle', () {
    test('episode with a name → "Show — S01E03 · Name"', () {
      expect(
        composePlayerTitle(
          name: 'Game of Thrones',
          season: 1,
          episode: 3,
          episodeName: 'Lord Snow',
        ),
        'Game of Thrones — S01E03 · Lord Snow',
      );
    });

    test('episode without a name → "Show — S01E03"', () {
      expect(
        composePlayerTitle(name: 'The Show', season: 1, episode: 3),
        'The Show — S01E03',
      );
    });

    test('a blank episode name is dropped', () {
      expect(
        composePlayerTitle(
            name: 'The Show', season: 2, episode: 5, episodeName: '   '),
        'The Show — S02E05',
      );
    });

    test('season and episode are zero-padded to two digits', () {
      expect(
        composePlayerTitle(name: 'X', season: 12, episode: 9),
        'X — S12E09',
      );
    });

    test('no season/episode (a movie) → just the name', () {
      expect(composePlayerTitle(name: 'Blade Runner'), 'Blade Runner');
    });

    test('a lone season or episode still degrades to the bare name', () {
      expect(composePlayerTitle(name: 'M', season: 1), 'M');
      expect(composePlayerTitle(name: 'M', episode: 4), 'M');
    });
  });
}
