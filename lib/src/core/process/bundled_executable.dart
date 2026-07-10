import 'dart:io';

import 'package:path/path.dart' as p;

/// Locates sidecar executables (see `tool/fetch_*`). These can't be found by
/// name alone at runtime — a clean release doesn't put them on PATH, and
/// neither Linux `Process.start` nor libmpv searches the executable's own
/// directory — so we resolve them by absolute path.
///
/// They're provisioned by the launcher into `%LOCALAPPDATA%\CouchRoach\bin`
/// (see [sidecarSearchDirs]); a build that still bundles them next to the app
/// exe also works, as a fallback.

/// The absolute path of the first name in [candidateNames] that [exists] inside
/// [executableDir], or `null` if none are there. Pure, with injectable deps so
/// it's unit-testable without touching the real filesystem.
String? bundledExecutablePath(
  List<String> candidateNames, {
  required String executableDir,
  required bool Function(String path) exists,
}) {
  for (final name in candidateNames) {
    final candidate = p.join(executableDir, name);
    if (exists(candidate)) return candidate;
  }
  return null;
}

/// The first of [candidateNames] found across [searchDirs] (dirs tried in
/// order), or null. Pure — the caller injects the dirs and existence check.
String? firstExecutableIn(
  List<String> candidateNames,
  List<String> searchDirs,
  bool Function(String path) exists,
) {
  for (final dir in searchDirs) {
    final hit = bundledExecutablePath(candidateNames,
        executableDir: dir, exists: exists);
    if (hit != null) return hit;
  }
  return null;
}

/// Where sidecars may live, most-preferred first: the launcher-managed bin dir
/// (`%LOCALAPPDATA%\CouchRoach\bin`), then next to the app exe (a dev or
/// self-contained build that bundled them). The launcher populates the bin dir
/// before it launches the app.
List<String> sidecarSearchDirs() {
  final dirs = <String>[];
  final localAppData = Platform.environment['LOCALAPPDATA'];
  if (localAppData != null && localAppData.isNotEmpty) {
    dirs.add(p.join(localAppData, 'CouchRoach', 'bin'));
  }
  dirs.add(p.dirname(Platform.resolvedExecutable));
  return dirs;
}

/// [firstExecutableIn] over the real [sidecarSearchDirs] and filesystem.
/// Returns `null` when no candidate is found — callers decide whether to fall
/// back to a bare name (resolved off PATH, so a dev machine with the tool
/// installed still works) or to skip the feature entirely.
String? bundledExecutable(List<String> candidateNames) => firstExecutableIn(
      candidateNames,
      sidecarSearchDirs(),
      (path) => File(path).existsSync(),
    );
