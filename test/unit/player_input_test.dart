import 'package:couch_roach/src/features/player/player_input.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isMediaPlayPauseKey', () {
    test('recognizes all three media transport keys', () {
      // Keyboards and remotes disagree about which one they emit.
      expect(isMediaPlayPauseKey(LogicalKeyboardKey.mediaPlayPause), isTrue);
      expect(isMediaPlayPauseKey(LogicalKeyboardKey.mediaPlay), isTrue);
      expect(isMediaPlayPauseKey(LogicalKeyboardKey.mediaPause), isTrue);
    });

    test('other keys — including the ones media_kit binds — are not', () {
      expect(isMediaPlayPauseKey(LogicalKeyboardKey.space), isFalse);
      expect(isMediaPlayPauseKey(LogicalKeyboardKey.arrowLeft), isFalse);
      expect(isMediaPlayPauseKey(LogicalKeyboardKey.arrowRight), isFalse);
      expect(isMediaPlayPauseKey(LogicalKeyboardKey.escape), isFalse);
      expect(isMediaPlayPauseKey(LogicalKeyboardKey.mediaStop), isFalse);
    });
  });

  group('shouldSwallowKey', () {
    test('with a media session, the media key is swallowed', () {
      // SMTC already delivers the press as a session button and acts on it;
      // letting the raw key through as well makes media_kit toggle a second
      // time and the two cancel out.
      expect(
        shouldSwallowKey(LogicalKeyboardKey.mediaPlayPause,
            hasMediaSession: true),
        isTrue,
      );
    });

    test('without a media session, the media key must pass through', () {
      // There's no duplicate to cancel, so swallowing it would break
      // play/pause outright on Linux.
      expect(
        shouldSwallowKey(LogicalKeyboardKey.mediaPlayPause,
            hasMediaSession: false),
        isFalse,
      );
    });

    test('every other key passes through regardless of platform', () {
      // The player observes keys globally; it must not steal Space or
      // arrow-seek from media_kit's own controls.
      for (final key in [
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.escape,
        LogicalKeyboardKey.enter,
      ]) {
        expect(shouldSwallowKey(key, hasMediaSession: true), isFalse,
            reason: '$key with a media session');
        expect(shouldSwallowKey(key, hasMediaSession: false), isFalse,
            reason: '$key without a media session');
      }
    });
  });
}
