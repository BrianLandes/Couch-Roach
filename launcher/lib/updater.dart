import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// The default source repo. Overridable via the config file's `repo` key.
const _defaultRepo = 'brianlandes/couch-roach';

// ── Pure helpers (unit-tested) ──────────────────────────────────────────────

/// The monotonic build number encoded in a release tag like `build-123`, or
/// null for any other tag shape.
int? buildNumberFromTag(String tag) {
  final m = RegExp(r'^build-(\d+)$').firstMatch(tag.trim());
  return m == null ? null : int.tryParse(m.group(1)!);
}

/// The .zip build asset from GitHub's `releases/latest` JSON, plus the build
/// number from the tag. Null when the release isn't a recognizable Couch Roach
/// build (no `build-N` tag, or no .zip asset).
ReleaseInfo? parseLatestRelease(Map<String, dynamic> json) {
  final tag = json['tag_name'];
  if (tag is! String) return null;
  final build = buildNumberFromTag(tag);
  if (build == null) return null;
  final assets = (json['assets'] as List?) ?? const [];
  for (final a in assets) {
    if (a is! Map) continue;
    final name = a['name'];
    final url = a['url'];
    if (name is String &&
        url is String &&
        name.toLowerCase().endsWith('.zip')) {
      return ReleaseInfo(build: build, zipAssetUrl: url, zipAssetName: name);
    }
  }
  return null;
}

/// The installed build recorded in `current.json`, or null when nothing is
/// installed / the file is unreadable.
int? installedBuildFrom(String? currentJson) {
  if (currentJson == null) return null;
  try {
    final m = jsonDecode(currentJson) as Map<String, dynamic>;
    final b = m['build'];
    if (b is int) return b;
    if (b is String) return int.tryParse(b);
  } catch (_) {}
  return null;
}

/// The launcher's config (from `launcher.json`), with sensible defaults so a
/// missing/garbled file just means "no token yet".
LauncherConfig parseConfig(String? json) {
  if (json == null) return const LauncherConfig();
  try {
    final m = jsonDecode(json) as Map<String, dynamic>;
    final token = m['githubToken'];
    final repo = m['repo'];
    return LauncherConfig(
      githubToken: token is String && token.isNotEmpty ? token : null,
      repo: repo is String && repo.isNotEmpty ? repo : _defaultRepo,
    );
  } catch (_) {
    return const LauncherConfig();
  }
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.build,
    required this.zipAssetUrl,
    required this.zipAssetName,
  });
  final int build;

  /// The GitHub *API* URL of the asset (not the browser URL) — downloaded with
  /// `Accept: application/octet-stream`, which works for a private repo.
  final String zipAssetUrl;
  final String zipAssetName;
}

class LauncherConfig {
  const LauncherConfig({this.githubToken, this.repo = _defaultRepo});
  final String? githubToken;
  final String repo;
}

/// Per-user install layout under `%LOCALAPPDATA%\CouchRoach`.
class LauncherPaths {
  const LauncherPaths(this.base);

  factory LauncherPaths.fromEnv() {
    final root = Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    return LauncherPaths(p.join(root, 'CouchRoach'));
  }

  final String base;

  String get configFile => p.join(base, 'config', 'launcher.json');
  String get appDir => p.join(base, 'app');
  String get currentFile => p.join(appDir, 'current.json');
  String get tmpDir => p.join(base, 'tmp');
  String installDir(int build) => p.join(appDir, 'build-$build');
  String exePath(int build) => p.join(installDir(build), 'couch_roach.exe');
}

enum UpdatePhase { checking, downloading, extracting, launching, error }

class UpdateStatus {
  const UpdateStatus(this.phase, {this.message = '', this.fraction});
  final UpdatePhase phase;
  final String message;

  /// 0..1 download progress, when known.
  final double? fraction;
}

// ── The updater ─────────────────────────────────────────────────────────────

/// Checks the newest published build, installs it if it beats what's on disk,
/// and launches it. Degrades gracefully: with no token (or no network) but an
/// app already installed, it just launches the installed build.
class Updater {
  Updater({http.Client? client, LauncherPaths? paths})
      : _client = client ?? http.Client(),
        paths = paths ?? LauncherPaths.fromEnv();

  final http.Client _client;
  final LauncherPaths paths;

  /// Runs the whole flow, reporting each phase through [onStatus]. Returns the
  /// build it launched, or null when it stopped at an error state.
  Future<int?> run(void Function(UpdateStatus) onStatus) async {
    onStatus(const UpdateStatus(UpdatePhase.checking,
        message: 'Checking for updates…'));

    final config = parseConfig(await _readFile(paths.configFile));
    final installed = installedBuildFrom(await _readFile(paths.currentFile));

    if (config.githubToken == null) {
      if (installed != null) return _launch(installed, onStatus);
      onStatus(UpdateStatus(UpdatePhase.error, message: _noTokenMessage()));
      return null;
    }

    ReleaseInfo? latest;
    try {
      latest = await _fetchLatest(config);
    } catch (e) {
      if (installed != null) return _launch(installed, onStatus);
      onStatus(UpdateStatus(UpdatePhase.error,
          message: "Couldn't reach GitHub and nothing is installed yet.\n$e"));
      return null;
    }

    if (latest == null) {
      if (installed != null) return _launch(installed, onStatus);
      onStatus(const UpdateStatus(UpdatePhase.error,
          message: 'No installable build was found in the latest release.'));
      return null;
    }

    if (installed != null && latest.build <= installed) {
      return _launch(installed, onStatus);
    }

    try {
      final zip = await _download(config, latest, onStatus);
      onStatus(const UpdateStatus(UpdatePhase.extracting, message: 'Installing…'));
      await _install(zip, latest.build);
      await _writeCurrent(latest.build);
      _reapOld(latest.build);
    } catch (e) {
      // A failed update shouldn't strand the user on a working install.
      if (installed != null) return _launch(installed, onStatus);
      onStatus(UpdateStatus(UpdatePhase.error, message: 'Update failed.\n$e'));
      return null;
    }
    return _launch(latest.build, onStatus);
  }

  Future<ReleaseInfo?> _fetchLatest(LauncherConfig config) async {
    final res = await _client.get(
      Uri.parse('https://api.github.com/repos/${config.repo}/releases/latest'),
      headers: {
        'Authorization': 'Bearer ${config.githubToken}',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'couch-roach-launcher',
      },
    );
    if (res.statusCode != 200) {
      throw HttpException('GitHub API responded ${res.statusCode}');
    }
    return parseLatestRelease(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<String> _download(
    LauncherConfig config,
    ReleaseInfo latest,
    void Function(UpdateStatus) onStatus,
  ) async {
    onStatus(const UpdateStatus(UpdatePhase.downloading,
        message: 'Downloading update…', fraction: 0));

    // Ask the asset endpoint for the binary; it 302s to a signed URL. Follow
    // that redirect WITHOUT the auth header — the storage host rejects it.
    final req = http.Request('GET', Uri.parse(latest.zipAssetUrl))
      ..followRedirects = false
      ..headers.addAll({
        'Authorization': 'Bearer ${config.githubToken}',
        'Accept': 'application/octet-stream',
        'User-Agent': 'couch-roach-launcher',
      });
    var streamed = await _client.send(req);
    if (streamed.statusCode >= 300 && streamed.statusCode < 400) {
      final loc = streamed.headers['location'];
      if (loc == null) throw const HttpException('redirect without a location');
      final redirect = http.Request('GET', Uri.parse(loc))
        ..headers['User-Agent'] = 'couch-roach-launcher';
      streamed = await _client.send(redirect);
    }
    if (streamed.statusCode != 200) {
      throw HttpException('download responded ${streamed.statusCode}');
    }

    final total = streamed.contentLength ?? 0;
    await Directory(paths.tmpDir).create(recursive: true);
    final file = File(p.join(paths.tmpDir, latest.zipAssetName));
    final sink = file.openWrite();
    var received = 0;
    await for (final chunk in streamed.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) {
        onStatus(UpdateStatus(UpdatePhase.downloading,
            message: 'Downloading update…', fraction: received / total));
      }
    }
    await sink.close();
    return file.path;
  }

  Future<void> _install(String zipPath, int build) async {
    final dir = Directory(paths.installDir(build));
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    extractFileToDisk(zipPath, dir.path);
    try {
      await File(zipPath).delete();
    } catch (_) {}
  }

  Future<void> _writeCurrent(int build) async {
    final f = File(paths.currentFile);
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode({'build': build, 'dir': 'build-$build'}));
  }

  /// Delete every installed build except [keep] — best-effort (a build whose
  /// files are locked, e.g. a still-running one, is simply skipped).
  void _reapOld(int keep) {
    final dir = Directory(paths.appDir);
    if (!dir.existsSync()) return;
    for (final e in dir.listSync()) {
      if (e is! Directory) continue;
      final m = RegExp(r'^build-(\d+)$').firstMatch(p.basename(e.path));
      if (m != null && int.parse(m.group(1)!) != keep) {
        try {
          e.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
  }

  Future<int?> _launch(int build, void Function(UpdateStatus) onStatus) async {
    onStatus(const UpdateStatus(UpdatePhase.launching,
        message: 'Launching Couch Roach…'));
    await Process.start(
      paths.exePath(build),
      const [],
      workingDirectory: paths.installDir(build),
      mode: ProcessStartMode.detached,
    );
    return build;
  }

  Future<String?> _readFile(String path) async {
    final f = File(path);
    return await f.exists() ? f.readAsString() : null;
  }

  String _noTokenMessage() =>
      'Set up your GitHub access token to enable updates.\n\n'
      'Create a fine-grained token (Repository access: this repo, '
      'Permissions → Contents: Read-only) and save it as:\n\n'
      '${paths.configFile}\n\n'
      'containing:  { "githubToken": "github_pat_..." }';
}
