import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'src/app.dart';
import 'src/core/logging/error_log_service.dart';
import 'src/core/settings/settings_service.dart';
import 'src/core/storage/storage_manager.dart';
import 'src/core/window/window_service.dart';
import 'src/features/library/library_match_service.dart';
import 'src/features/library/library_service.dart';
import 'src/injection.dart';
import 'src/services/acquisition/jackett_process.dart';
import 'src/services/acquisition/qbittorrent_process.dart';
import 'src/services/cleanup/completed_torrent_reaper.dart';
import 'src/services/cleanup/watched_reaper.dart';

void main() {
  // Run everything inside a guarded zone so uncaught async errors are captured.
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Bound the decoded-image (poster/still) cache. The TV box is low on RAM,
      // and the landing page shows many rows of artwork at once — without a cap
      // the live-bitmap cache grows until the app GC-stutters or is OOM-killed.
      PaintingBinding.instance.imageCache
        ..maximumSize = 150
        ..maximumSizeBytes = 48 << 20; // ~48 MB of decoded bitmaps

      // Initialize libmpv (media_kit) before any player is created.
      MediaKit.ensureInitialized();

      // Wire the DI container (services/singletons — see lib/src/injection.dart).
      configureDependencies();

      // Bring up error logging first, then route framework/platform errors to it.
      final log = getIt<ErrorLogService>();
      await log.init();
      FlutterError.onError = log.onFlutterError;
      PlatformDispatcher.instance.onError = log.onPlatformError;

      // Spawn the invisible sidecars (qBittorrent-nox daemon + Jackett indexer)
      // and shut them down when the window closes. Non-fatal: if they can't
      // start, the app still runs (local playback works; acquisition is just
      // unavailable) — the failures are logged.
      final daemon = getIt<QbittorrentProcess>();
      final jackett = getIt<JackettProcess>();

      // Launch the TV window (windowed; F11 or the in-app button toggles
      // fullscreen). The close hook kills the sidecar children before the app
      // exits so nothing is orphaned.
      Future<void> shutdownSidecars() async {
        await daemon.stop();
        await jackett.stop();
      }

      await initFullscreenWindow(onClose: shutdownSidecars);

      // Safety net for the paths that never fire the window-close hook: an IDE
      // stop, `q` in `flutter run`, or a plain `kill` signals the process
      // directly. Without this the sidecars orphan and libmpv's GL teardown can
      // abort the process (the same crash the window-close exit(0) avoids). Catch
      // the signals, stop the children, then hard-exit before that teardown runs.
      // Linux only — Windows closes through the window hook, and watching these
      // signals there is unreliable.
      if (Platform.isLinux) {
        for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
          signal.watch().listen((_) async {
            try {
              await shutdownSidecars();
            } finally {
              exit(0);
            }
          });
        }
      }

      unawaited(daemon.start().catchError((Object e, StackTrace st) {
        getIt<ErrorLogService>()
            .logError(e, stackTrace: st, source: 'main.startDaemon');
      }));
      // Jackett's own start() swallows/logs its failures, but guard the future
      // too so a throw can't escape into the zone.
      unawaited(jackett.start().catchError((Object e, StackTrace st) {
        getIt<ErrorLogService>()
            .logError(e, stackTrace: st, source: 'main.startJackett');
      }));

      // Hydrate the configured storage roots so scanning/placement see every disk.
      await getIt<StorageManager>().load();

      // Load user preferences into the cache so services read them synchronously.
      await getIt<SettingsService>().load();

      runApp(const ProviderScope(child: CouchRoachApp()));

      // Kick off an initial library scan in the background, then match against
      // TMDB — neither blocks the UI (posters pop in as they resolve). After the
      // scan reconciles disk, reap fully-watched files past the grace period
      // (the row is flagged missing, so watch history survives).
      unawaited(getIt<LibraryService>()
          .rescan()
          .then((_) => getIt<LibraryMatchService>().matchUnmatched())
          .then((_) => getIt<WatchedReaper>().sweep()));

      // Re-sweep periodically so a long-running session still reclaims space.
      Timer.periodic(
        const Duration(hours: 6),
        (_) => getIt<WatchedReaper>().sweep(),
      );

      // Clear finished torrents from the client (keeping their files) so it
      // doesn't accumulate completed torrents seeding forever. isAlive() guards
      // the startup run before the daemon has finished coming up.
      unawaited(getIt<CompletedTorrentReaper>().sweep());
      Timer.periodic(
        const Duration(minutes: 15),
        (_) => getIt<CompletedTorrentReaper>().sweep(),
      );
    },
    (error, stack) {
      // Last-resort sink for anything the handlers above didn't catch.
      try {
        getIt<ErrorLogService>().logError(error, stackTrace: stack, source: 'uncaught');
      } catch (_) {
        // ignore: avoid_print
        print('Fatal before logger ready: $error\n$stack');
      }
    },
  );
}
