import 'dart:io';

import '../../injection.dart';
import '../logging/error_log_service.dart';

/// Open [url] in the OS's default browser via the platform opener — no
/// `url_launcher` dependency; the app already spawns processes. Used to hand off
/// to a local web UI (e.g. the Jackett indexer dashboard) that isn't a 10-foot
/// surface. Best-effort: logs and returns false on failure so the caller can
/// surface it.
Future<bool> openUrl(String url) async {
  try {
    if (Platform.isWindows) {
      // `start` is a cmd builtin; the empty "" is its (ignored) window title.
      await Process.start('cmd', ['/c', 'start', '', url]);
    } else if (Platform.isMacOS) {
      await Process.start('open', [url]);
    } else {
      await Process.start('xdg-open', [url]);
    }
    return true;
  } catch (e, st) {
    getIt<ErrorLogService>().logError(e, stackTrace: st, source: 'openUrl');
    return false;
  }
}
