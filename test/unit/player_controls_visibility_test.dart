import 'package:couch_roach/src/features/player/player_controls_visibility.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ControlsVisibility', () {
    test('starts hidden and playing — the state the player opens in', () {
      final c = ControlsVisibility();
      expect(c.visible, isFalse);
      expect(c.playing, isTrue);
    });

    group('while playing', () {
      test('activity reveals the overlay and arms the idle countdown', () {
        final c = ControlsVisibility();
        expect(c.onActivity(), IdleHide.restart);
        expect(c.visible, isTrue);
      });

      test('repeated activity keeps restarting the countdown', () {
        final c = ControlsVisibility();
        c.onActivity();
        expect(c.onActivity(), IdleHide.restart);
        expect(c.onActivity(), IdleHide.restart);
        expect(c.visible, isTrue);
      });

      test('the countdown elapsing hides the overlay', () {
        final c = ControlsVisibility()..onActivity();
        expect(c.onIdleElapsed(), IdleHide.cancel);
        expect(c.visible, isFalse);
      });

      test('activity after an idle hide brings it back', () {
        final c = ControlsVisibility()
          ..onActivity()
          ..onIdleElapsed();
        expect(c.visible, isFalse);
        expect(c.onActivity(), IdleHide.restart);
        expect(c.visible, isTrue);
      });
    });

    group('while paused or ended', () {
      test('pausing pins the overlay up and stops the countdown', () {
        final c = ControlsVisibility();
        expect(c.onPlayingChanged(false), IdleHide.cancel);
        expect(c.visible, isTrue);
        expect(c.playing, isFalse);
      });

      test('pausing reveals the overlay even if it was hidden', () {
        final c = ControlsVisibility()
          ..onActivity()
          ..onIdleElapsed();
        expect(c.visible, isFalse);
        c.onPlayingChanged(false);
        expect(c.visible, isTrue);
      });

      test('activity never re-arms the countdown', () {
        final c = ControlsVisibility()..onPlayingChanged(false);
        expect(c.onActivity(), IdleHide.cancel);
        expect(c.visible, isTrue);
      });

      // The stranding failure mode: a remote emits key events, not pointer
      // motion. If the overlay could hide on a paused/ended video, the back and
      // Next Episode buttons would be gone with no way to summon them.
      test('no sequence of activity and idles can hide the overlay', () {
        final c = ControlsVisibility()..onPlayingChanged(false);
        for (var i = 0; i < 50; i++) {
          c.onActivity();
          c.onIdleElapsed();
          expect(c.visible, isTrue, reason: 'hidden on iteration $i');
        }
      });

      // A countdown armed microseconds before a pause can still fire after it.
      // Honouring that stale timer would hide the overlay on a paused video.
      test('a countdown armed before the pause cannot hide it afterwards', () {
        final c = ControlsVisibility();
        expect(c.onActivity(), IdleHide.restart); // timer armed, still playing
        c.onPlayingChanged(false); // ...then the pause lands
        c.onIdleElapsed(); // ...and the stale timer fires
        expect(c.visible, isTrue);
      });
    });

    group('resuming', () {
      test('behaves like fresh activity — visible, countdown re-armed', () {
        final c = ControlsVisibility()..onPlayingChanged(false);
        expect(c.onPlayingChanged(true), IdleHide.restart);
        expect(c.visible, isTrue);
        expect(c.playing, isTrue);
      });

      test('the overlay can idle away again once playing resumes', () {
        final c = ControlsVisibility()
          ..onPlayingChanged(false)
          ..onPlayingChanged(true);
        c.onIdleElapsed();
        expect(c.visible, isFalse);
      });

      test('a full pause/resume cycle returns to the pre-pause behaviour', () {
        final c = ControlsVisibility();
        c.onActivity();
        c.onIdleElapsed();
        expect(c.visible, isFalse);

        c.onPlayingChanged(false);
        c.onPlayingChanged(true);

        expect(c.onActivity(), IdleHide.restart);
        c.onIdleElapsed();
        expect(c.visible, isFalse);
      });
    });

    test('timings stay in lockstep with media_kit\'s own controls', () {
      expect(ControlsVisibility.hideDelay, const Duration(seconds: 3));
      expect(ControlsVisibility.fade, const Duration(milliseconds: 150));
    });
  });
}
