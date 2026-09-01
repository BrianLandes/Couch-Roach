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

  group('audioChannelCount', () {
    test('takes the wider of the two fields libmpv reports', () {
      // They don't always agree, and either can be absent — a track reporting 6
      // in one and 0 in the other is 5.1, not unknown.
      expect(audioChannelCount(channelsCount: 6, audioChannels: 0), 6);
      expect(audioChannelCount(channelsCount: 0, audioChannels: 6), 6);
      expect(audioChannelCount(channelsCount: 2, audioChannels: 6), 6);
    });

    test('both absent reads as unknown', () {
      expect(audioChannelCount(), 0);
      expect(audioChannelCount(channelsCount: null, audioChannels: null), 0);
    });
  });

  group('audioTrackLabel', () {
    test('title plus layout', () {
      expect(
        audioTrackLabel(id: '1', title: 'Commentary', channels: 2),
        'Commentary · Stereo',
      );
    });

    test('appends the language when the title does not already say it', () {
      expect(
        audioTrackLabel(id: '1', title: 'Surround', language: 'eng', channels: 6),
        'Surround (ENG) · 5.1',
      );
    });

    test('does not repeat a language the title already carries', () {
      expect(
        audioTrackLabel(
            id: '1', title: 'English 5.1', language: 'eng', channels: 6),
        'English 5.1 · 5.1',
      );
    });

    test('falls back to the language when there is no title', () {
      expect(
        audioTrackLabel(id: '2', language: 'pt', channels: 2),
        'PT · Stereo',
      );
    });

    test('falls back to the track number when there is neither', () {
      expect(audioTrackLabel(id: '3'), 'Track 3');
      expect(audioTrackLabel(id: '3', channels: 2), 'Track 3 · Stereo');
    });

    test('blank title and language are treated as absent', () {
      expect(audioTrackLabel(id: '4', title: '  ', language: '  '), 'Track 4');
    });

    test('an unknown channel count is simply omitted', () {
      expect(audioTrackLabel(id: '1', title: 'English', channels: 0), 'English');
    });
  });

  group('isSelectableTrackId', () {
    test("libmpv's synthetic entries never reach the menu", () {
      expect(isSelectableTrackId('auto'), isFalse);
      expect(isSelectableTrackId('no'), isFalse);
    });

    test('real track indices are selectable', () {
      expect(isSelectableTrackId('1'), isTrue);
      expect(isSelectableTrackId('2'), isTrue);
    });
  });
}
