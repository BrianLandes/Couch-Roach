import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/logging/error_log_service.dart';
import '../../core/process/bundled_executable.dart';
import 'jackett_resolver.dart';

/// Owns the **Jackett indexer sidecar** lifecycle (DECISIONS §D) — the same
/// invisible-localhost-child model as [QbittorrentProcess].
///
/// On [start] the app spawns Jackett's console host headless, bound to
/// `127.0.0.1:9117` with an isolated `--DataFolder`, waits for its web/Torznab
/// API to answer, reads the auto-generated API key from `ServerConfig.json`, and
/// hands a [JackettConfig] to [JackettResolver] so the acquisition seam can start
/// querying. On [stop] (wired to window close in `main()`) the child is killed.
///
/// Jackett is content-agnostic infrastructure: this manages only the *process* —
/// which indexers exist (and the legal responsibility for them) live in the
/// user's own Jackett configuration, never in this repo (CLAUDE.md invariant).
@LazySingleton()
class JackettProcess {
  JackettProcess(this._http, this._log, this._resolver);

  final http.Client _http;
  final ErrorLogService _log;
  final JackettResolver _resolver;

  /// Jackett's default port. Kept as-is (per DECISIONS §D) — it flows through
  /// [JackettConfig] to the resolver, so changing it here is enough if it ever
  /// needs to move to avoid colliding with a user's own Jackett instance.
  static const int port = 9117;
  static const String host = '127.0.0.1';
  static String get baseUrl => 'http://$host:$port';

  Process? _process;

  /// True once [start] has spawned a process (whether or not it's ready).
  bool get isRunning => _process != null;

  /// Spawn the sidecar and wire the resolver once its API answers. Idempotent —
  /// a second call while running is a no-op. A missing bundle or a failed start
  /// degrades quietly (indexer search stays unavailable); the failure is logged.
  Future<void> start() async {
    if (_process != null) return;

    // Adopt an already-running Jackett on the port rather than spawning a second
    // one that can't bind. This is common in dev (a hot-restart or IDE-stop
    // kills the app without firing the window-close shutdown, orphaning the
    // child) and possible in prod after a crash. The live instance shares this
    // DataFolder, so its ServerConfig.json holds the API key we need — point the
    // resolver at it and skip spawning. Without this, the doomed spawn's exit
    // would tear the resolver's config back down and disable indexer search.
    if (await isAlive()) {
      final config = await _readConfig(await _dataFolder());
      if (config != null) {
        _resolver.configure(config);
        _log.info('Adopted an already-running Jackett at $baseUrl',
            source: 'JackettSidecar');
      } else {
        _log.warn(
          'Something is already serving $baseUrl but no API key was found in '
          'our DataFolder — indexer search disabled (a foreign Jackett?)',
          source: 'JackettSidecar',
        );
      }
      return;
    }

    final executable = _resolveExecutable();
    if (executable == null) {
      _log.warn(
        'Jackett not bundled next to the app — indexer search unavailable',
        source: 'JackettSidecar.start',
      );
      return;
    }

    final dataFolder = await _dataFolder();
    try {
      // Console host in sidecar mode (NOT the service/systemd/tray installers).
      // inheritStdio keeps exitCode + kill() working while staying invisible —
      // see QbittorrentProcess for why detached modes are avoided.
      _process = await Process.start(
        executable,
        [
          '--Port', '$port',
          '--DataFolder', dataFolder.path,
          '--NoRestart',
          '--NoUpdates',
          // Bind 127.0.0.1 only. Without this Jackett defaults to AllowExternal
          // (listens on all interfaces), exposing the unauthenticated dashboard +
          // Torznab API to the LAN — this keeps it an invisible localhost child.
          '--ListenPrivate',
        ],
        mode: ProcessStartMode.inheritStdio,
      );
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'JackettSidecar.start');
      return; // non-fatal: acquisition degrades without the indexer path
    }

    // Reflect an unexpected exit and stop the resolver querying a dead endpoint.
    unawaited(_process!.exitCode.then((code) {
      if (_process != null) {
        _log.warn('Jackett sidecar exited unexpectedly (code $code)',
            source: 'JackettSidecar');
        _process = null;
        _resolver.configure(null);
      }
    }));

    try {
      await _awaitReady();
    } on TimeoutException catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'JackettSidecar.awaitReady');
      return;
    }

    final config = await _readConfig(dataFolder);
    if (config == null) {
      _log.warn(
        'Jackett is up but no API key was found in ServerConfig.json — '
        'indexer search stays disabled',
        source: 'JackettSidecar',
      );
      return;
    }
    _resolver.configure(config);
    _log.info('Jackett sidecar ready at $baseUrl', source: 'JackettSidecar');
  }

  /// Kill the child process and detach the resolver. Safe to call when nothing is
  /// running; never throws (runs on window close).
  Future<void> stop() async {
    final proc = _process;
    _process = null;
    _resolver.configure(null);
    if (proc == null) return;
    try {
      proc.kill();
      final exited = await proc.exitCode
          .then((_) => true)
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (!exited) proc.kill(ProcessSignal.sigkill);
    } catch (e, st) {
      _log.logError(e, stackTrace: st, source: 'JackettSidecar.stop');
    }
  }

  // ── internals ──────────────────────────────────────────────────────────────

  /// The bundled console host next to the app executable, or null if not present
  /// (dev builds without the vendored tree). Resolved by absolute path — Linux
  /// `Process.start` doesn't search the executable's own directory.
  String? _resolveExecutable() {
    final name = Platform.isWindows ? 'JackettConsole.exe' : 'jackett';
    return bundledExecutable([p.join('jackett', name)]);
  }

  Future<Directory> _dataFolder() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'jackett'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Whether the sidecar's web/Torznab API is answering (any HTTP response means
  /// it's listening) — drives the settings status indicator and the adopt check.
  Future<bool> isAlive() async {
    try {
      await _http.get(Uri.parse(baseUrl)).timeout(const Duration(seconds: 2));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Poll the web endpoint until it binds (any HTTP response means the server is
  /// listening) or we give up.
  Future<void> _awaitReady() async {
    final deadline = DateTime.now().add(const Duration(seconds: 40));
    while (DateTime.now().isBefore(deadline)) {
      if (_process == null) {
        throw StateError('Jackett exited before its API came up');
      }
      try {
        await _http
            .get(Uri.parse(baseUrl))
            .timeout(const Duration(seconds: 2));
        return; // got a response → the port is bound
      } catch (_) {
        // Not up yet — keep polling.
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    throw TimeoutException(
      'Jackett Torznab API did not respond at $baseUrl within 40s',
    );
  }

  /// Read the auto-generated Torznab API key from `<DataFolder>/ServerConfig.json`
  /// into a [JackettConfig]. Retries briefly: the file can lag the web server
  /// binding on first run. Null if it never appears.
  Future<JackettConfig?> _readConfig(Directory dataFolder) async {
    final file = File(p.join(dataFolder.path, 'ServerConfig.json'));
    for (var i = 0; i < 10; i++) {
      if (file.existsSync()) {
        final key = parseJackettApiKey(file.readAsStringSync());
        if (key != null) return JackettConfig(baseUrl: baseUrl, apiKey: key);
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return null;
  }
}
