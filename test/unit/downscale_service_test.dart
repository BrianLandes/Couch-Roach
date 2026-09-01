import 'package:couch_roach/src/core/logging/error_log_service.dart';
import 'package:couch_roach/src/core/media/playback_activity.dart';
import 'package:couch_roach/src/core/settings/settings_service.dart';
import 'package:couch_roach/src/data/db/database.dart';
import 'package:couch_roach/src/data/repositories/library_repository.dart';
import 'package:couch_roach/src/services/transcode/downscale_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Counts `getAll` so a test can prove the sweep bailed out *before* touching
/// the library — which is the only observable difference between "returned null
/// because a guard fired" and "returned null after finding nothing to do".
class _CountingLibrary implements LibraryRepository {
  int getAllCalls = 0;

  @override
  Future<List<LibraryItem>> getAll() async {
    getAllCalls++;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) async => null;
}

class _FakeSettings implements SettingsService {
  _FakeSettings(this.maxDownloadHeight);

  @override
  final int maxDownloadHeight;

  @override
  dynamic noSuchMethod(Invocation invocation) async => null;
}

void main() {
  late _CountingLibrary library;

  setUp(() {
    library = _CountingLibrary();
    playbackActive.value = false;
  });

  // A plain global shared across tests — leaving it true would silently disable
  // every later sweep.
  tearDown(() => playbackActive.value = false);

  DownscaleService serviceWith({required int cap}) =>
      DownscaleService(library, _FakeSettings(cap), ErrorLogService());

  group('sweep guards', () {
    test('does nothing when the resolution cap is off', () async {
      // The downscaler is keyed off the download cap: no cap means the user
      // never opted in, so it must not re-encode anything.
      expect(await serviceWith(cap: 0).sweep(), isNull);
      expect(library.getAllCalls, 0);
    });

    test('a negative cap is treated as off, not as a tiny cap', () async {
      expect(await serviceWith(cap: -1).sweep(), isNull);
      expect(library.getAllCalls, 0);
    });

    // The whole point of the feature is smoother playback; encoding on the same
    // GPU while a video is open would make the problem worse, not better.
    test('does nothing while a video is playing', () async {
      playbackActive.value = true;

      expect(await serviceWith(cap: 1080).sweep(), isNull);
      expect(library.getAllCalls, 0);
    });

    test('the playback guard lifts once playback stops', () async {
      final service = serviceWith(cap: 1080);

      playbackActive.value = true;
      await service.sweep();
      expect(library.getAllCalls, 0);

      playbackActive.value = false;
      await service.sweep();
      // Now it gets as far as looking for work (and finds none — the fake
      // library is empty, and no encoder is resolved in a test environment).
      expect(await service.sweep(), isNull);
    });
  });

  group('current job', () {
    test('starts idle', () {
      expect(serviceWith(cap: 1080).current.value, isNull);
    });

    test('stays idle when every sweep is guarded away', () async {
      final service = serviceWith(cap: 0);
      await service.sweep();
      expect(service.current.value, isNull);
    });
  });
}
