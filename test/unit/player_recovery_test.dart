import 'package:couch_roach/src/features/player/player_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  late PlaybackRecovery recovery;

  setUp(() {
    now = DateTime(2026, 10, 20, 21);
    recovery = PlaybackRecovery(clock: () => now);
  });

  /// Run one full recover cycle: error → reopen issued.
  PlaybackFailureAction failAndReopen() {
    final action = recovery.onError(isNetworkSource: false);
    if (action == PlaybackFailureAction.recover) recovery.onReopened();
    return action;
  }

  test('an error before playback ever started is a real failure', () {
    expect(recovery.onError(isNetworkSource: false),
        PlaybackFailureAction.showError);
  });

  test('a network stream is never reopened', () {
    recovery.onPlaybackConfirmed();
    expect(recovery.onError(isNetworkSource: true),
        PlaybackFailureAction.showError);
  });

  test('an error after playback was running is recovered', () {
    recovery.onPlaybackConfirmed();
    expect(recovery.onError(isNetworkSource: false),
        PlaybackFailureAction.recover);
    expect(recovery.isRecovering, isTrue);
    expect(recovery.delayFor, const Duration(seconds: 1));
  });

  test('errors while the reopen is pending are ignored', () {
    recovery.onPlaybackConfirmed();
    recovery.onError(isNetworkSource: false);
    expect(recovery.onError(isNetworkSource: false),
        PlaybackFailureAction.ignore);
  });

  test('a reopen that fails again is retried with growing delays, then gives up',
      () {
    recovery.onPlaybackConfirmed();
    expect(failAndReopen(), PlaybackFailureAction.recover);
    // Reopen failed before playing — still within budget.
    expect(recovery.onError(isNetworkSource: false),
        PlaybackFailureAction.recover);
    expect(recovery.delayFor, const Duration(seconds: 3));
    recovery.onReopened();
    expect(failAndReopen(), PlaybackFailureAction.recover);
    expect(recovery.delayFor, const Duration(seconds: 6));
    // Budget spent inside the window → the file really won't play.
    expect(recovery.onError(isNetworkSource: false),
        PlaybackFailureAction.showError);
  });

  test('a successful recovery ends the recovering state', () {
    recovery.onPlaybackConfirmed();
    failAndReopen();
    recovery.onPlaybackConfirmed();
    expect(recovery.isRecovering, isFalse);
    expect(recovery.hasStarted, isTrue);
  });

  test('the attempt budget refreshes after the window passes', () {
    recovery.onPlaybackConfirmed();
    for (var i = 0; i < PlaybackRecovery.maxAttempts; i++) {
      expect(failAndReopen(), PlaybackFailureAction.recover);
      recovery.onPlaybackConfirmed();
    }
    expect(recovery.onError(isNetworkSource: false),
        PlaybackFailureAction.showError);

    // Next night's sleep: a fresh budget.
    now = now.add(PlaybackRecovery.window + const Duration(seconds: 1));
    recovery.onPlaybackConfirmed();
    expect(recovery.onError(isNetworkSource: false),
        PlaybackFailureAction.recover);
  });

  group('isAudioOutputError', () {
    test('recognises a vanished audio device', () {
      // The exact message seen after sleep / HDMI unplug.
      expect(
          isAudioOutputError(
              'Could not open/initialize audio device -> no sound.'),
          isTrue);
      expect(isAudioOutputError('Failed to initialize audio output'), isTrue);
    });

    test('leaves real playback failures alone', () {
      expect(isAudioOutputError('Failed to recognize file format.'), isFalse);
      expect(isAudioOutputError('Loading failed'), isFalse);
      expect(isAudioOutputError('No video or audio streams selected.'),
          isFalse);
    });
  });
}
