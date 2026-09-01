import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum LogLevel { info, warning, error }

/// Central error/diagnostics sink. Every system opts in by sending failures here
/// — `getIt<ErrorLogService>().logError(e, stackTrace: st, source: 'X.op')` — and
/// the app's global handlers route uncaught framework/async errors through it too
/// (wired in main()). Entries are appended to human-readable text logs the user
/// can find locally (there's no remote backend — this is the single-machine
/// equivalent of the Supabase error table in the sibling projects).
///
/// **Two files per launch**, under `<app-support>/logs/`:
///
/// * `couch_roach-<stamp>.log` — the combined stream.
/// * `couch_roach-<stamp>.errors.log` — warnings and errors only, so a real
///   problem isn't buried under routine chatter.
///
/// A fresh pair is started on every launch (rather than one ever-growing file)
/// and the oldest sessions past [_keepSessions] are pruned on startup.
///
/// **[verbose] gates the chatter.** `info` entries — the routine tracing that
/// most systems emit — are dropped unless verbose logging is switched on in
/// Settings. `warning` and `error` always log. main() syncs [verbose] from
/// `SettingsService`.
///
/// Call [init] once at startup; writes before then are buffered and flushed
/// when the files are ready.
@LazySingleton()
class ErrorLogService {
  ErrorLogService();

  /// `couch_roach-<stamp>.log` / `couch_roach-<stamp>.errors.log`.
  static const _prefix = 'couch_roach-';
  static const _mainSuffix = '.log';
  static const _errorSuffix = '.errors.log';

  /// How many *past* launches to keep on disk. Older sessions are deleted when
  /// a new one starts, so the logs folder can't grow without bound.
  static const _keepSessions = 10;

  /// When false (the default), [LogLevel.info] entries are dropped before they
  /// reach either file. Set from the "Verbose logging" setting; warnings and
  /// errors ignore it.
  ///
  /// Note: [init] runs before settings are loaded, so the handful of `info`
  /// entries emitted during early startup are dropped even with the setting on.
  bool verbose = false;

  File? _file;
  File? _errorFile;
  final List<({String text, LogLevel level})> _pending = [];
  Future<void> _writes = Future<void>.value();

  /// Absolute path to this launch's combined log, or null before [init].
  String? get logFilePath => _file?.path;

  /// Absolute path to this launch's warnings/errors-only log, or null before
  /// [init].
  String? get errorLogFilePath => _errorFile?.path;

  /// Open this launch's pair of log files and prune old sessions. [directory]
  /// overrides the default app-support location — used by tests.
  Future<void> init({Directory? directory}) async {
    final base = directory ?? await getApplicationSupportDirectory();
    final logDir = Directory(p.join(base.path, 'logs'));
    if (!logDir.existsSync()) logDir.createSync(recursive: true);

    // Prune before opening this session's files so the new pair is never a
    // deletion candidate.
    _pruneOldSessions(logDir);

    final stamp = _fileStamp(DateTime.now());
    _file = File(p.join(logDir.path, '$_prefix$stamp$_mainSuffix'));
    _errorFile = File(p.join(logDir.path, '$_prefix$stamp$_errorSuffix'));

    _append(_file!, '──────── session started ${_timestamp()} ────────');

    final buffered = List.of(_pending);
    _pending.clear();
    for (final e in buffered) {
      _dispatch(e.text, e.level);
    }
  }

  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? source,
  }) {
    // Routine tracing is opt-in — it's the bulk of the volume and nobody reads
    // it unless they're chasing something. Warnings and errors always log.
    if (level == LogLevel.info && !verbose) return;

    final line = StringBuffer()
      ..write(_timestamp())
      ..write('  ')
      ..write(level.name.toUpperCase().padRight(7))
      ..write(source == null ? '' : '[$source] ')
      ..write(message);
    if (error != null) line.write('  :: $error');
    var entry = line.toString();
    if (stackTrace != null) entry = '$entry\n$stackTrace';
    _emit(entry, level);
  }

  /// Opt-in entry point for other systems.
  void logError(
    Object error, {
    StackTrace? stackTrace,
    String? source,
    String? message,
  }) {
    log(
      LogLevel.error,
      message ?? error.toString(),
      error: message == null ? null : error,
      stackTrace: stackTrace,
      source: source,
    );
  }

  void warn(String message, {String? source}) =>
      log(LogLevel.warning, message, source: source);

  /// Routine tracing — only reaches the log when [verbose] is on.
  void info(String message, {String? source}) =>
      log(LogLevel.info, message, source: source);

  /// Handler for `FlutterError.onError`.
  void onFlutterError(FlutterErrorDetails details) {
    log(
      LogLevel.error,
      details.exceptionAsString(),
      stackTrace: details.stack,
      source: 'flutter',
    );
    FlutterError.presentError(details); // keep default console reporting
  }

  /// Handler for `PlatformDispatcher.instance.onError`.
  bool onPlatformError(Object error, StackTrace stack) {
    logError(error, stackTrace: stack, source: 'platform');
    return true;
  }

  /// Awaits all queued writes — call before shutdown or in tests.
  Future<void> flush() => _writes;

  void _emit(String entry, LogLevel level) {
    if (kDebugMode) debugPrint(entry);
    if (_file == null) {
      _pending.add((text: entry, level: level));
      return;
    }
    _dispatch(entry, level);
  }

  /// Every entry goes to the combined log; warnings and errors get a second
  /// copy in the errors-only log.
  void _dispatch(String entry, LogLevel level) {
    final main = _file;
    if (main != null) _append(main, entry);
    final errors = _errorFile;
    if (level != LogLevel.info && errors != null) _append(errors, entry);
  }

  void _append(File file, String entry) {
    // Serialize appends so lines never interleave; logging must never throw
    // back into the app.
    _writes = _writes.then((_) async {
      try {
        await file.writeAsString('$entry\n', mode: FileMode.append);
      } catch (_) {
        // swallow — a failed log write can't be allowed to break the app
      }
    });
  }

  /// Delete all files belonging to the oldest sessions, keeping the newest
  /// [_keepSessions]. Best-effort: pruning must never break startup.
  void _pruneOldSessions(Directory logDir) {
    try {
      final files = logDir.listSync().whereType<File>().toList();
      final stamps = <String>{};
      for (final f in files) {
        final s = _sessionStampOf(p.basename(f.path));
        if (s != null) stamps.add(s);
      }
      if (stamps.length <= _keepSessions) return;
      // The stamp is `YYYY-MM-DD_HH-mm-ss`, so lexicographic order is
      // chronological order.
      final ordered = stamps.toList()..sort();
      final doomed = ordered.take(stamps.length - _keepSessions).toSet();
      for (final f in files) {
        final s = _sessionStampOf(p.basename(f.path));
        if (s != null && doomed.contains(s)) f.deleteSync();
      }
    } catch (_) {
      // ignore — a log dir we can't tidy is not worth failing a launch over
    }
  }

  /// The session stamp encoded in [basename], or null when the file isn't one
  /// of ours. Checks the errors suffix first — it also ends in `.log`.
  static String? _sessionStampOf(String basename) {
    if (!basename.startsWith(_prefix)) return null;
    final rest = basename.substring(_prefix.length);
    for (final suffix in const [_errorSuffix, _mainSuffix]) {
      if (rest.endsWith(suffix)) {
        return rest.substring(0, rest.length - suffix.length);
      }
    }
    return null;
  }

  /// Filename-safe, sortable launch stamp: `YYYY-MM-DD_HH-mm-ss`.
  static String _fileStamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)}_'
        '${two(t.hour)}-${two(t.minute)}-${two(t.second)}';
  }

  String _timestamp() => DateTime.now().toIso8601String();
}
