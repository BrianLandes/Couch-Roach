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

    try {
      await _awaitReady();
    } on TimeoutException {
      // WebUI never bound. Log every config file under the profile so a
      // path/format mismatch (qBittorrent wrote its config somewhere other than
      // where we seeded) is obvious from the log.
      _logDiscoveredConfigs(profileDir);
      rethrow;
    }
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

  /// Ensure the daemon comes up headless with its Web API bound to
  /// `127.0.0.1:8181`, the first-run legal notice pre-accepted, and localhost
  /// auth bypassed (the client connects credential-free — the daemon is only
  /// reachable on 127.0.0.1).
  ///
  /// This runs on **every** launch and *merges* the required keys into any
  /// existing config rather than skipping when the file exists. qBittorrent
  /// rewrites its whole config on exit, so an earlier build (or a manual tweak)
  /// can leave WebUI disabled or on the wrong port — and a skip-if-exists seed
  /// would never repair it, leaving the daemon up with no Web API to talk to.
  /// The user's unrelated settings (download paths, limits, …) are preserved.
  Future<void> _seedConfig(Directory profileDir) async {
    // qBittorrent reads <profile>/qBittorrent/config/qBittorrent.{ini,conf}.
    // The Windows GUI build (portable/profile mode) uses .ini; nox uses .conf.
    final configDir = Directory(p.join(profileDir.path, 'qBittorrent', 'config'));
    if (!configDir.existsSync()) configDir.createSync(recursive: true);

    final fileName = Platform.isWindows ? 'qBittorrent.ini' : 'qBittorrent.conf';
    final conf = File(p.join(configDir.path, fileName));
    final existing = conf.existsSync() ? conf.readAsStringSync() : null;
    final merged = enforceConfig(existing);
    if (merged != existing) conf.writeAsStringSync(merged);
    _log.info(
      'qBittorrent config ${existing == null ? 'seeded' : 'reconciled'} at ${conf.path}',
      source: 'QbittorrentProcess',
    );
  }

  /// The keys we force on every launch (section → key → value). `WebUI\Enabled`
  /// is the load-bearing one — without it the Web API never binds.
  /// `LocalHostAuth=false` bypasses auth for localhost clients; the legal-notice
  /// acceptance stops the daemon blocking on a first-run prompt; the
  /// StartMinimized/tray keys keep the Windows GUI exe (used in lieu of a
  /// headless nox build) out of sight (nox ignores them).
  static Map<String, Map<String, String>> get _requiredConfig => {
        'LegalNotice': {'Accepted': 'true'},
        'Preferences': {
          'WebUI\\Enabled': 'true',
          'WebUI\\Address': webUiHost,
          'WebUI\\Port': '$webUiPort',
          'WebUI\\LocalHostAuth': 'false',
          'WebUI\\CSRFProtection': 'false',
          'General\\Locale': 'en',
          'General\\StartMinimized': 'true',
          'General\\MinimizeToTray': 'true',
          'General\\CloseToTray': 'true',
        },
      };

  static const _webUiUsername = 'admin';

  /// PBKDF2-HMAC-SHA512 (100k iterations) of a fixed password with a fixed salt,
  /// in qBittorrent's `@ByteArray(base64(salt):base64(hash))` form. qBittorrent
  /// 5.x refuses to start the Web API when no credentials are set ("WebUI:
  /// Credentials are not set"), so this exists purely to satisfy that gate — it
  /// is **not a secret**: the Web API binds to 127.0.0.1 with `LocalHostAuth`
  /// bypass, so the password is never used to authenticate a client. Written
  /// unquoted so QSettings parses it as a byte-array type. Only seeded when no
  /// password is already set, so a user's own WebUI password is preserved.
  static const _webUiPasswordPbkdf2 =
      '@ByteArray(Y291Y2hyb2FjaHNhbHQxNg==:AtmWvuanDiGbcUBPGIC40uHAwLPtzqr/'
      'zNAXglK9Ytp+dVFfvQrdvO5SXxdKuv1yAYF5k+YO9kaa1/Z9ZPrM+A==)';

  /// Merge [_requiredConfig] into [existing] qBittorrent INI text (or produce a
  /// fresh config when null), preserving every other section/key in order. Pure
  /// and static so the merge is unit-testable.
  static String enforceConfig(String? existing) {
    final sectionOrder = <String>[];
    final data = <String, Map<String, String>>{};

    String? current;
    for (final raw in (existing ?? '').split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        current = line.substring(1, line.length - 1);
        if (!data.containsKey(current)) {
          sectionOrder.add(current);
          data[current] = <String, String>{};
        }
        continue;
      }
      final eq = line.indexOf('=');
      if (eq <= 0 || current == null) continue; // skip malformed / preamble
      data[current]![line.substring(0, eq).trim()] = line.substring(eq + 1).trim();
    }

    _requiredConfig.forEach((section, kv) {
      if (!data.containsKey(section)) {
        sectionOrder.add(section);
        data[section] = <String, String>{};
      }
      data[section]!.addAll(kv);
    });

    // Seed WebUI credentials only when none exist yet — qBittorrent 5.x won't
    // start the Web API without them, but a user who set their own password
    // keeps it. Treat an empty value as "not set" too (that's exactly the state
    // that logs "Credentials are not set").
    final prefs = data['Preferences']!;
    final existingPw = prefs['WebUI\\Password_PBKDF2'];
    if (existingPw == null || existingPw.isEmpty) {
      prefs['WebUI\\Username'] = _webUiUsername;
      prefs['WebUI\\Password_PBKDF2'] = _webUiPasswordPbkdf2;
    }

    final buf = StringBuffer();
    for (final section in sectionOrder) {
      buf.writeln('[$section]');
      data[section]!.forEach((k, v) => buf.writeln('$k=$v'));
      buf.writeln();
    }
    return buf.toString();
  }

  /// The fresh-install config (exposed for testing).
  static String defaultConfig() => enforceConfig(null);

  /// On a readiness timeout, dump what the daemon itself is telling us: the
  /// config files it wrote (to catch a path mismatch) and the tail of its own
  /// log (which says *why* the Web UI didn't bind — bad port, blocking prompt,
  /// etc.). Diagnostic only; never masks the original timeout.
  void _logDiscoveredConfigs(Directory profileDir) {
    try {
      final files = profileDir
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .toList();

      final configs = files
          .where((f) {
            final n = p.basename(f.path).toLowerCase();
            return n.endsWith('.ini') || n.endsWith('.conf');
          })
          .map((f) => f.path)
          .toList();
      _log.warn(
        'qBittorrent WebUI never came up. Config files under the profile: '
        '${configs.isEmpty ? '(none found)' : configs.join(', ')}',
        source: 'QbittorrentProcess',
      );

      // qBittorrent writes <profile>/qBittorrent/data/logs/qbittorrent.log —
      // its own log explains a WebUI that won't start.
      for (final logFile in files.where(
          (f) => p.basename(f.path).toLowerCase() == 'qbittorrent.log')) {
        final lines = logFile.readAsLinesSync();
        final tail = lines.length <= 40 ? lines : lines.sublist(lines.length - 40);
        _log.warn(
          'qBittorrent log (${logFile.path}), last ${tail.length} lines:\n'
          '${tail.join('\n')}',
          source: 'QbittorrentProcess',
        );
      }
    } catch (_) {
      // Diagnostic only — never let it mask the original timeout.
    }
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
