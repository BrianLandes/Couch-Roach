import 'package:couch_roach/src/features/player/player_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveStartPosition', () {
    test('an explicit start wins over a saved resume position', () {
      // Auto-advancing into the next episode passes an explicit start; the
      // previous episode's saved position must not hijack it.
      expect(
        resolveStartPosition(
          requested: const Duration(minutes: 2),
          savedResumeSec: 900,
        ),
        const Duration(minutes: 2),
      );
    });

    test('falls back to the saved resume position', () {
      expect(
        resolveStartPosition(requested: Duration.zero, savedResumeSec: 754),
        const Duration(seconds: 754),
      );
    });

    test('no history starts at the beginning', () {
      expect(
        resolveStartPosition(requested: Duration.zero, savedResumeSec: null),
        Duration.zero,
      );
    });

    test('a saved zero means never-watched, not resume-at-zero', () {
      expect(
        resolveStartPosition(requested: Duration.zero, savedResumeSec: 0),
        Duration.zero,
      );
    });
  });

  group('shouldSaveProgress', () {
    test('holds off until playback has moved far enough', () {
      expect(shouldSaveProgress(positionSec: 3, lastSavedSec: 0), isFalse);
      expect(shouldSaveProgress(positionSec: 4, lastSavedSec: 0), isFalse);
    });

    test('saves once the threshold is reached', () {
      expect(shouldSaveProgress(positionSec: 5, lastSavedSec: 0), isTrue);
      expect(shouldSaveProgress(positionSec: 120, lastSavedSec: 100), isTrue);
    });

    // Absolute movement, so scrubbing backwards persists as promptly as
    // playing forwards — otherwise a rewind wouldn't stick until you'd played
    // back past where you started.
    test('a backwards seek counts as movement too', () {
      expect(shouldSaveProgress(positionSec: 100, lastSavedSec: 600), isTrue);
      expect(shouldSaveProgress(positionSec: 598, lastSavedSec: 600), isFalse);
    });

    test('no movement never saves', () {
      expect(shouldSaveProgress(positionSec: 42, lastSavedSec: 42), isFalse);
    });
  });

  group('isWatched', () {
    const hour = Duration(hours: 1);

    test('short of the threshold is not watched', () {
      expect(
        isWatched(position: const Duration(minutes: 56), duration: hour),
        isFalse,
      );
    });

    test('at or past the threshold is watched', () {
      // 95% of an hour is 57 minutes — backing out during the credits still
      // counts, so the reaper and Continue Watching treat it as finished.
      expect(
        isWatched(position: const Duration(minutes: 57), duration: hour),
        isTrue,
      );
      expect(isWatched(position: hour, duration: hour), isTrue);
    });

    // A file whose duration libmpv hasn't reported yet must never be marked
    // watched — the reaper deletes watched files.
    test('an unknown duration is never watched', () {
      expect(
        isWatched(position: const Duration(hours: 3), duration: Duration.zero),
        isFalse,
      );
    });
  });

  group('shouldPrefetchNext', () {
    const hour = Duration(hours: 1);

    test('not before the halfway point', () {
      expect(
        shouldPrefetchNext(
            position: const Duration(minutes: 29), duration: hour),
        isFalse,
      );
    });

    test('from the halfway point on', () {
      expect(
        shouldPrefetchNext(
            position: const Duration(minutes: 30), duration: hour),
        isTrue,
      );
      expect(
        shouldPrefetchNext(
            position: const Duration(minutes: 59), duration: hour),
        isTrue,
      );
    });

    test('an unknown duration never triggers a prefetch', () {
      expect(
        shouldPrefetchNext(
            position: const Duration(minutes: 30), duration: Duration.zero),
        isFalse,
      );
    });
  });

  test('the prefetch point comes before the watched point', () {
    // Otherwise the next episode would only start downloading once this one was
    // effectively over, defeating the point of prefetching.
    expect(kPrefetchFraction, lessThan(kWatchedFraction));
  });
}
