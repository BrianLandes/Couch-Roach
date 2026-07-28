import 'package:couch_roach/src/features/discover/show_detail_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('seasonDownloadState', () {
    test('none when nothing is downloaded', () {
      expect(seasonDownloadState(downloaded: 0, total: 10),
          SeasonDownloadState.none);
      expect(seasonDownloadState(downloaded: 0, total: null),
          SeasonDownloadState.none);
    });

    test('some when partially downloaded', () {
      expect(seasonDownloadState(downloaded: 3, total: 10),
          SeasonDownloadState.some);
    });

    test('all when every episode is downloaded', () {
      expect(seasonDownloadState(downloaded: 10, total: 10),
          SeasonDownloadState.all);
    });

    test('all when there are extras beyond the reported count (specials)', () {
      expect(seasonDownloadState(downloaded: 11, total: 10),
          SeasonDownloadState.all);
    });

    test('unknown total never reads as "all" — any downloaded is "some"', () {
      expect(seasonDownloadState(downloaded: 8, total: null),
          SeasonDownloadState.some);
      expect(seasonDownloadState(downloaded: 8, total: 0),
          SeasonDownloadState.some);
    });
  });
}
