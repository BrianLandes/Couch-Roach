import 'package:couch_roach/src/features/player/player_sources.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isNetworkUrl', () {
    test('http and https are network sources', () {
      expect(isNetworkUrl('http://example.com/v.mp4'), isTrue);
      expect(isNetworkUrl('https://www.youtube.com/watch?v=abc123'), isTrue);
      expect(isNetworkUrl('HTTPS://EXAMPLE.COM/v.mp4'), isTrue);
    });

    // The one that matters on the primary target: a drive letter parses as a
    // URI scheme, so "has a scheme" would misread every Windows file as a
    // network source and wire up ytdl_hook for a local video.
    test('a Windows path is a local file, not a network source', () {
      expect(isNetworkUrl(r'C:\Users\brian\Videos\show.mkv'), isFalse);
      expect(isNetworkUrl(r'D:\media\Movie (1968).mp4'), isFalse);
    });

    test('a POSIX path is a local file', () {
      expect(isNetworkUrl('/home/brian/Videos/show.mkv'), isFalse);
      expect(isNetworkUrl('show.mkv'), isFalse);
    });

    test('other schemes are not network sources', () {
      expect(isNetworkUrl('file:///home/brian/show.mkv'), isFalse);
      expect(isNetworkUrl('magnet:?xt=urn:btih:abc'), isFalse);
    });

    test('empty input is not a network source', () {
      expect(isNetworkUrl(''), isFalse);
    });
  });

  group('isSidecarSubtitleId', () {
    test('subtitle file extensions are sidecars', () {
      expect(isSidecarSubtitleId('/media/show.en.srt'), isTrue);
      expect(isSidecarSubtitleId('subs.vtt'), isTrue);
    });

    test('a path with a separator is a sidecar on either platform', () {
      expect(isSidecarSubtitleId('/media/tv/subs'), isTrue);
      expect(isSidecarSubtitleId(r'C:\media\tv\subs'), isTrue);
    });

    test('libmpv track indices and sentinels are embedded, not sidecars', () {
      expect(isSidecarSubtitleId('1'), isFalse);
      expect(isSidecarSubtitleId('2'), isFalse);
      expect(isSidecarSubtitleId('no'), isFalse);
      expect(isSidecarSubtitleId('auto'), isFalse);
    });
  });

  group('suppressesAutoSubtitles', () {
    test('nothing saved lets the auto-English fetch run', () {
      expect(suppressesAutoSubtitles(null), isFalse);
    });

    test('an explicit "off" suppresses it', () {
      // Otherwise the auto fetch would switch subtitles back on for someone who
      // deliberately turned them off.
      expect(suppressesAutoSubtitles('no'), isTrue);
    });

    test('a saved embedded track suppresses it', () {
      expect(suppressesAutoSubtitles('2'), isTrue);
    });

    test('a saved sidecar does not — the auto path reloads the same file', () {
      expect(suppressesAutoSubtitles('/media/show.en.srt'), isFalse);
      expect(suppressesAutoSubtitles(r'C:\media\show.en.srt'), isFalse);
    });
  });
}
