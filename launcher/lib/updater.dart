import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// The default source repo — the **private** distribution repo that holds the
/// keyed app builds and the sidecars bundle (the public `couch-roach` repo holds
/// the source only). Overridable via the config file's `repo` key.
const _defaultRepo = 'brianlandes/couch-roach-dist';

// ── Pure helpers (unit-tested) ──────────────────────────────────────────────

/// The monotonic build number encoded in a release tag like `build-123`, or
/// null for any other tag shape.
int? buildNumberFromTag(String tag) {
  final m = RegExp(r'^build-(\d+)$').firstMatch(tag.trim());
  return m == null ? null : int.tryParse(m.group(1)!);
}

final _sidecarsAsset = RegExp(r'^sidecars-([0-9a-fA-F]+)\.zip$');

/// Parse GitHub's `releases/latest` JSON into the build number + the app .zip
/// asset. Null when the tag isn't a `build-N`. A `sidecars-*.zip` asset (present
/// on older releases) is skipped so it's never mistaken for the app zip — the
/// sidecars now live in their own release (see [parseSidecarsRelease]).
ReleaseInfo? parseLatestRelease(Map<String, dynamic> json) {
  final tag = json['tag_name'];
  if (tag is! String) return null;
  final build = buildNumberFromTag(tag);
  if (build == null) return null;

  ReleaseAsset? appZip;
  for (final a in (json['assets'] as List?) ?? const []) {
    if (a is! Map) continue;
    final name = a['name'];
    final url = a['url'];
    if (name is! String || url is! String) continue;
    if (_sidecarsAsset.hasMatch(name)) continue; // not the app build
    if (name.toLowerCase().endsWith('.zip')) {
      appZip ??= ReleaseAsset(url: url, name: name);
    }
  }
  return ReleaseInfo(build: build, appZip: appZip);
}

/// Find the `sidecars-<contenttag>.zip` asset in the dedicated `sidecars`
/// prerelease JSON. The tag is a content hash, stable while the sidecars don't
/// change. Null when the release has no sidecars asset.
SidecarsInfo? parseSidecarsRelease(Map<String, dynamic> json) {
  for (final a in (json['assets'] as List?) ?? const []) {
    if (a is! Map) continue;
    final name = a['name'];
    final url = a['url'];
    if (name is! String || url is! String) continue;
    final m = _sidecarsAsset.firstMatch(name);
    if (m != null) {
      return SidecarsInfo(asset: ReleaseAsset(url: url, name: name), tag: m.group(1)!);
    }
  }
  return null;
}

/// The installed build recorded in `current.json`, or null when nothing is
/// installed / the file is unreadable.
int? installedBuildFrom(String? currentJson) {
  if (currentJson == null) return null;
  try {
    final b = (jsonDecode(currentJson) as Map<String, dynamic>)['build'];
    if (b is int) return b;
    if (b is String) return int.tryParse(b);
  } catch (_) {}
  return null;
}

/// The sidecars tag recorded in `bin/sidecars.json`, or null.
String? installedSidecarsTag(String? sidecarsJson) {
  if (sidecarsJson == null) return null;
  try {
    final t = (jsonDecode(sidecarsJson) as Map<String, dynamic>)['tag'];
    return t is String ? t : null;
  } catch (_) {}
  return null;
}

/// The launcher's config (from `launcher.json`), defaulting sensibly.
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

class ReleaseAsset {
  const ReleaseAsset({required this.url, required this.name});

  /// The GitHub *API* URL of the asset — downloaded with
  /// `Accept: application/octet-stream`, which works for a private repo.
  final String url;
  final String name;
}

class ReleaseInfo {
  const ReleaseInfo({required this.build, this.appZip});
  final int build;
  final ReleaseAsset? appZip;
}

class SidecarsInfo {
  const SidecarsInfo({required this.asset, required this.tag});
  final ReleaseAsset asset;
  final String tag;
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
  String get binDir => p.join(base, 'bin');
  String get sidecarsFile => p.join(binDir, 'sidecars.json');
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
/// provisions the sidecars (qBittorrent/yt-dlp/ffprobe/Jackett) into the shared
/// bin dir, and launches the app. Degrades gracefully: with no token or no
/// network but an app already installed, it just launches the installed build.
class Updater {
  Updater({http.Client? client, LauncherPaths? paths})
      : _client = client ?? http.Client(),
        paths = paths ?? LauncherPaths.fromEnv();

  final http.Client _client;
  final LauncherPaths paths;

  /// Runs the flow, reporting each phase through [onStatus]. Returns the build
  /// it launched, or null when it stopped at an error state.
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

    // Install a newer app build if there is one; otherwise keep what's on disk.
    var buildToLaunch = installed;
    if (installed == null || latest.build > installed) {
      try {
        await _installApp(config, latest, onStatus);
        buildToLaunch = latest.build;
      } catch (e) {
        if (installed == null) {
          onStatus(UpdateStatus(UpdatePhase.error, message: 'Update failed.\n$e'));
          return null;
        }
        // A failed update shouldn't strand the user on a working install.
      }
    }
    if (buildToLaunch == null) return null;

    // Provision sidecars into the shared bin dir (best-effort — the app degrades
    // per-feature if one is missing, and the next launch retries).
    try {
      await _provisionSidecars(config, onStatus);
    } catch (_) {}

    return _launch(buildToLaunch, onStatus);
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

  Future<void> _installApp(
    LauncherConfig config,
    ReleaseInfo latest,
    void Function(UpdateStatus) onStatus,
  ) async {
    final appZip = latest.appZip;
    if (appZip == null) throw const HttpException('release has no app build');
    final zip = await _downloadAsset(
        config, appZip, onStatus, 'Downloading update…');
    onStatus(const UpdateStatus(UpdatePhase.extracting, message: 'Installing…'));
    final dir = Directory(paths.installDir(latest.build));
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    extractFileToDisk(zip, dir.path);
    _tryDelete(zip);
    await _writeJson(paths.currentFile,
        {'build': latest.build, 'dir': 'build-${latest.build}'});
    _reapOldBuilds(latest.build);
  }

  Future<void> _provisionSidecars(
    LauncherConfig config,
    void Function(UpdateStatus) onStatus,
  ) async {
    final sc = await _fetchSidecars(config);
    if (sc == null) return; // no sidecars release yet — leave bin as-is
    final installedTag =
        installedSidecarsTag(await _readFile(paths.sidecarsFile));
    if (installedTag == sc.tag && _sidecarsPresent()) return; // already current

    final zip = await _downloadAsset(
        config, sc.asset, onStatus, 'Preparing components…');
    onStatus(const UpdateStatus(UpdatePhase.extracting,
        message: 'Preparing components…'));
    await Directory(paths.binDir).create(recursive: true);
    // Extract over the existing files (no wipe — a running sidecar's file may be
    // locked; overwriting the rest is fine and self-heals next launch).
    extractFileToDisk(zip, paths.binDir);
    _tryDelete(zip);
    await _writeJson(paths.sidecarsFile, {'tag': sc.tag});
  }

  /// Fetch the dedicated `sidecars` prerelease and find its bundle asset. Null
  /// (not an error) when that release doesn't exist yet.
  Future<SidecarsInfo?> _fetchSidecars(LauncherConfig config) async {
    final res = await _client.get(
      Uri.parse(
          'https://api.github.com/repos/${config.repo}/releases/tags/sidecars'),
      headers: {
        'Authorization': 'Bearer ${config.githubToken}',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'couch-roach-launcher',
      },
    );
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw HttpException('GitHub API responded ${res.statusCode}');
    }
    return parseSidecarsRelease(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Whether the key sidecars are present in the bin dir.
  bool _sidecarsPresent() =>
      File(p.join(paths.binDir, 'qbittorrent.exe')).existsSync() &&
      File(p.join(paths.binDir, 'yt-dlp.exe')).existsSync() &&
      File(p.join(paths.binDir, 'ffprobe.exe')).existsSync() &&
      File(p.join(paths.binDir, 'jackett', 'JackettConsole.exe')).existsSync();

  Future<String> _downloadAsset(
    LauncherConfig config,
    ReleaseAsset asset,
    void Function(UpdateStatus) onStatus,
    String message,
  ) async {
    onStatus(UpdateStatus(UpdatePhase.downloading, message: message, fraction: 0));

    // The asset endpoint 302s to a signed storage URL. Follow that redirect
    // WITHOUT the auth header — the storage host rejects it.
    final req = http.Request('GET', Uri.parse(asset.url))
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
      streamed = await _client.send(http.Request('GET', Uri.parse(loc))
        ..headers['User-Agent'] = 'couch-roach-launcher');
    }
    if (streamed.statusCode != 200) {
      throw HttpException('download responded ${streamed.statusCode}');
    }

    final total = streamed.contentLength ?? 0;
    await Directory(paths.tmpDir).create(recursive: true);
    final file = File(p.join(paths.tmpDir, asset.name));
    final sink = file.openWrite();
    var received = 0;
    await for (final chunk in streamed.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) {
        onStatus(UpdateStatus(UpdatePhase.downloading,
            message: message, fraction: received / total));
      }
    }
    await sink.close();
    return file.path;
  }

  /// Delete every installed build except [keep] — best-effort.
  void _reapOldBuilds(int keep) {
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

  Future<void> _writeJson(String path, Map<String, Object?> data) async {
    final f = File(path);
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(data));
  }

  void _tryDelete(String path) {
    try {
      File(path).deleteSync();
    } catch (_) {}
  }

  Future<String?> _readFile(String path) async {
    final f = File(path);
    return await f.exists() ? f.readAsString() : null;
  }

  String _noTokenMessage() =>
      'Set up your GitHub access token to enable updates.\n\n'
      'Create a fine-grained token (Repository access: couch-roach-dist, '
      'Permissions → Contents: Read-only) and save it as:\n\n'
      '${paths.configFile}\n\n'
      'containing:  { "githubToken": "github_pat_..." }';
}
