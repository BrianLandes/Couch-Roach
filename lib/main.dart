import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'src/app.dart';
import 'src/core/logging/error_log_service.dart';
import 'src/core/storage/storage_manager.dart';
import 'src/core/window/window_service.dart';
import 'src/features/library/library_match_service.dart';
import 'src/features/library/library_service.dart';
import 'src/injection.dart';

void main() {
  // Run everything inside a guarded zone so uncaught async errors are captured.
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Initialize libmpv (media_kit) before any player is created.
      MediaKit.ensureInitialized();

      // Wire the DI container (services/singletons — see lib/src/injection.dart).
      configureDependencies();

      // Bring up error logging first, then route framework/platform errors to it.
      final log = getIt<ErrorLogService>();
      await log.init();
      FlutterError.onError = log.onFlutterError;
      PlatformDispatcher.instance.onError = log.onPlatformError;

      // Launch the TV window fullscreen (F11 toggles).
      await initFullscreenWindow();

      // Hydrate the configured storage roots so scanning/placement see every disk.
      await getIt<StorageManager>().load();

      runApp(const ProviderScope(child: CouchRoachApp()));

      // Kick off an initial library scan in the background, then match against
      // TMDB — neither blocks the UI (posters pop in as they resolve).
      unawaited(getIt<LibraryService>()
          .rescan()
          .then((_) => getIt<LibraryMatchService>().matchUnmatched()));
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
