import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/logging/error_log_service.dart';

/// Owns the **qBittorrent-nox child process** lifecycle (HANDOFF §4.1/§4.7).
///
/// The daemon is invisible: on [start] the app spawns qBittorrent-nox headless,
/// bound to `127.0.0.1` on a fixed port with an isolated profile, and waits for
/// its Web API to answer before returning. On [stop] (wired to window close in
/// `main()`) the child is killed. The user launches one thing.
///
/// This service owns only the *process* — talking to the Web API (adding
/// torrents, progress) is the separate `TorrentDaemon` implementation.
/// [baseUrl] is exposed so that client can find the daemon.
@LazySingleton()
class QbittorrentProcess {
  QbittorrentProcess(this._log);

  final ErrorLogService _log;

  /// Fixed localhost port for the Web API. Deliberately not qBittorrent's
  /// default 8080 to avoid colliding with an unrelated qBittorrent the user may
  /// already run.
  static const int webUiPort = 8181;
  static const String webUiHost = '127.0.0.1';

  /// Base URL of the Web API, e.g. `http://127.0.0.1:8181`.
  static String get baseUrl => 'http://$webUiHost:$webUiPort';

  Process? _process;

  /// True once [start] has spawned a process (whether or not it's ready).
  bool get isRunning => _process != null;

  /// Spawn the daemon and wait until its Web API responds. Idempotent — a second
  /// call while running is a no-op. Failures are logged and rethrown so the
  /// caller can decide whether to degrade (acquisition unavailable) or surface.
  Future<void> start() async {
    if (_process != null) return;

    final profileDir = await _profileDirectory();
    await _seedConfig(profileDir);

    final executable = _resolveExecutable();
    try {
      // Only pass --profile; the WebUI host/port live in the seeded config so
      // this works for both nox and the Windows GUI exe (which doesn't take the
      // nox-only --webui-port flag).
      _process = await Process.start(
        executable,
        ['--profile=${profileDir.path}'],
        // inheritStdio — NOT a detached mode. A detached mode (detached /
        // detachedWithStdio) makes `.exitCode` throw "Process is detached",
        // which we rely on to detect an unexpected exit and to await shutdown in
        // stop(). inheritStdio keeps exitCode + kill() while staying invisible:
        // on Windows we run the GUI exe minimized to tray (seeded config), on
        // Linux nox is headless, and inherited stdio just goes to the app's own
        // (absent) console rather than needing to be drained.
        mode: ProcessStartMode.inheritStdio,
      );
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'QbittorrentProcess.start');
      rethrow;
    }

    // Kill the child if it dies unexpectedly so isRunning reflects reality.
    unawaited(_process!.exitCode.then((code) {
      if (_process != null) {
        _log.log(
          LogLevel.warning,
          'qBittorrent daemon exited unexpectedly (code $code)',
        );
        _process = null;
      }
    }));

    await _awaitReady();
  }

  /// Kill the child process. Safe to call when nothing is running. Never
  /// throws — this runs on window close, and a shutdown hiccup must not trap the
  /// user in a window that won't close.
  Future<void> stop() async {
    final proc = _process;
    _process = null;
    if (proc == null) return;
    try {
      proc.kill();
      // Give it a moment to exit; escalate to SIGKILL if it lingers.
      final exited = await proc.exitCode
          .then((_) => true)
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (!exited) proc.kill(ProcessSignal.sigkill);
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'QbittorrentProcess.stop');
    }
  }

  // ── internals ──────────────────────────────────────────────────────────────

  /// Prefer a bundled binary next to the app executable (dropped there by the
  /// packaging step, same model as ffprobe); fall back to a bare name resolved
  /// off PATH so a dev machine with qBittorrent installed just works.
  ///
  /// On Windows there is no official headless `qbittorrent-nox.exe`, so the
  /// packaging step bundles the GUI `qbittorrent.exe` (run hidden via the seeded
  /// config) — but a user-supplied nox build is preferred if present. On Linux
  /// `Process.start` does not search the executable's own directory, so the
  /// bundled binary must be invoked by absolute path.
  String _resolveExecutable() {
    final candidates = Platform.isWindows
        ? const ['qbittorrent-nox.exe', 'qbittorrent.exe']
        : const ['qbittorrent-nox'];
    final exeDir = p.dirname(Platform.resolvedExecutable);
    for (final name in candidates) {
      final bundled = File(p.join(exeDir, name));
      if (bundled.existsSync()) return bundled.path;
    }
    return candidates.first; // bare name → resolved off PATH (dev machines)
  }

  Future<Directory> _profileDirectory() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'qbittorrent'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Seed `qBittorrent.conf` so the daemon comes up headless, bound to
  /// localhost, with the first-run legal notice pre-accepted and localhost auth
  /// disabled (the API client connects with no credentials — the daemon is only
  /// ever reachable on 127.0.0.1). Written only if absent so the user's later
  /// tweaks via the Web UI survive restarts.
  Future<void> _seedConfig(Directory profileDir) async {
    // qBittorrent reads <profile>/qBittorrent/config/qBittorrent.{ini,conf}.
    // The Windows GUI build (portable/profile mode) uses .ini; nox uses .conf.
    final configDir = Directory(p.join(profileDir.path, 'qBittorrent', 'config'));
    if (!configDir.existsSync()) configDir.createSync(recursive: true);

    final fileName = Platform.isWindows ? 'qBittorrent.ini' : 'qBittorrent.conf';
    final conf = File(p.join(configDir.path, fileName));
    if (conf.existsSync()) return;

    conf.writeAsStringSync(defaultConfig());
  }

  /// The seed config (exposed for testing). `LocalHostAuth=false` lets the
  /// localhost-only Web API client connect without credentials; the legal-notice
  /// acceptance keeps the daemon from blocking on a first-run prompt. The
  /// StartMinimized/tray keys keep the Windows GUI exe (used in lieu of a
  /// headless nox build) out of sight — nox ignores them.
  static String defaultConfig() {
    return '[LegalNotice]\n'
        'Accepted=true\n'
        '\n'
        '[Preferences]\n'
        'WebUI\\Enabled=true\n'
        'WebUI\\Address=$webUiHost\n'
        'WebUI\\Port=$webUiPort\n'
        'WebUI\\LocalHostAuth=false\n'
        'WebUI\\CSRFProtection=false\n'
        'General\\Locale=en\n'
        'General\\StartMinimized=true\n'
        'General\\MinimizeToTray=true\n'
        'General\\CloseToTray=true\n';
  }

  /// Poll the Web API until it answers or we give up.
  Future<void> _awaitReady() async {
    final client = http.Client();
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    try {
      while (DateTime.now().isBefore(deadline)) {
        if (_process == null) {
          throw StateError('qBittorrent exited before its Web API came up');
        }
        try {
          final res = await client
              .get(Uri.parse('$baseUrl/api/v2/app/version'))
              .timeout(const Duration(seconds: 2));
          if (res.statusCode == 200) return;
        } catch (_) {
          // Not up yet — keep polling.
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      final e = TimeoutException(
        'qBittorrent-nox Web API did not respond at $baseUrl within 20s',
      );
      _log.logError(e, source: 'QbittorrentProcess._awaitReady');
      throw e;
    } finally {
      client.close();
    }
  }
}
