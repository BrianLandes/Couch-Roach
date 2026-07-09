import 'package:couch_roach/src/features/player/subtitle_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('truncateSubtitleTitle', () {
    test('leaves a short title untouched', () {
      expect(truncateSubtitleTitle('English SDH'), 'English SDH');
    });

    test('caps a long title to max chars with an ellipsis', () {
      const long = 'The.Show.S01E01.1080p.WEB-DL.DDP5.1.H264-GROUP';
      final out = truncateSubtitleTitle(long, 20);
      expect(out.length, 20); // 19 chars + the ellipsis
      expect(out.endsWith('…'), isTrue);
      expect(out, 'The.Show.S01E01.108…');
    });

    test('trims a trailing space before the ellipsis', () {
      // Cut lands right after a space → no "  …".
      expect(truncateSubtitleTitle('English forced signs', 9), 'English…');
    });

    test('a title exactly at the limit is not truncated', () {
      final exact = 'a' * 36;
      expect(truncateSubtitleTitle(exact), exact);
    });
  });

  group('subtitleTrackLabel', () {
    test('synthetic tracks map to Off / Auto', () {
      expect(subtitleTrackLabel(id: 'no'), 'Off');
      expect(subtitleTrackLabel(id: 'auto'), 'Auto');
    });

    test('title + language reads "title (lang)"', () {
      expect(
        subtitleTrackLabel(id: '1', title: 'English SDH', language: 'en'),
        'English SDH (en)',
      );
    });

    test('long title is truncated but the language suffix survives', () {
      final label = subtitleTrackLabel(
        id: '2',
        title: 'The.Show.S01E01.1080p.WEB-DL.DDP5.1.H264-GROUP',
        language: 'en',
        maxTitle: 20,
      );
      expect(label.endsWith('… (en)'), isTrue);
    });

    test('language only when there is no title', () {
      expect(subtitleTrackLabel(id: '3', language: 'fr'), 'fr');
    });

    test('falls back to the track id when nothing else is known', () {
      expect(subtitleTrackLabel(id: '5'), 'Track 5');
    });
  });
}
