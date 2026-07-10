import 'package:couch_roach/src/features/player/audio_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AudioTrackInfo t({
    String? language,
    String? title,
    int channels = 0,
    bool isDefault = false,
  }) =>
      AudioTrackInfo(
          language: language,
          title: title,
          channels: channels,
          isDefault: isDefault);

  group('isEnglishAudio', () {
    test('matches en / eng / english tags and English-named titles', () {
      expect(isEnglishAudio(t(language: 'en')), isTrue);
      expect(isEnglishAudio(t(language: 'ENG')), isTrue);
      expect(isEnglishAudio(t(language: 'English')), isTrue);
      expect(isEnglishAudio(t(title: 'English 5.1')), isTrue);
      expect(isEnglishAudio(t(language: 'pt')), isFalse);
      expect(isEnglishAudio(t(language: null, title: 'Commentary')), isFalse);
    });
  });

  group('autoAudioTrackIndex', () {
    test('null for a single track (nothing to choose)', () {
      expect(autoAudioTrackIndex([t(language: 'pt')], preferSurround: true),
          isNull);
    });

    test('prefers English over a wider foreign track', () {
      final tracks = [
        t(language: 'pt', channels: 6), // 5.1 Portuguese
        t(language: 'en', channels: 2), // stereo English
      ];
      expect(autoAudioTrackIndex(tracks, preferSurround: true), 1);
    });

    test('among English tracks, widest wins when surround is on', () {
      final tracks = [
        t(language: 'en', channels: 2),
        t(language: 'en', channels: 6),
      ];
      expect(autoAudioTrackIndex(tracks, preferSurround: true), 1);
    });

    test('among English tracks with surround off, keeps the default', () {
      final tracks = [
        t(language: 'en', channels: 2),
        t(language: 'en', channels: 6, isDefault: true),
      ];
      expect(autoAudioTrackIndex(tracks, preferSurround: false), 1);
    });

    test('no English + surround on → widest overall', () {
      final tracks = [
        t(language: 'pt', channels: 2),
        t(language: 'fr', channels: 8),
      ];
      expect(autoAudioTrackIndex(tracks, preferSurround: true), 1);
    });

    test('no English + surround off → null (do not reorder for channels)', () {
      final tracks = [
        t(language: 'pt', channels: 2),
        t(language: 'fr', channels: 8),
      ];
      expect(autoAudioTrackIndex(tracks, preferSurround: false), isNull);
    });

    test('ties keep the earlier track (stable, no needless reorder)', () {
      final tracks = [
        t(language: 'en', channels: 2),
        t(language: 'en', channels: 2),
      ];
      expect(autoAudioTrackIndex(tracks, preferSurround: true), 0);
    });
  });

  group('channelLayoutLabel', () {
    test('names common layouts, null for unknown', () {
      expect(channelLayoutLabel(0), isNull);
      expect(channelLayoutLabel(1), 'Mono');
      expect(channelLayoutLabel(2), 'Stereo');
      expect(channelLayoutLabel(6), '5.1');
      expect(channelLayoutLabel(8), '7.1');
      expect(channelLayoutLabel(4), '4ch');
    });
  });
}
