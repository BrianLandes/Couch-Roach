import 'dart:io';

import 'package:path/path.dart' as p;

/// Locates sidecar executables that the packaging step drops next to the app
/// executable (see `tool/fetch_*`). These can't be found by name alone at
/// runtime — a clean release doesn't put them on PATH, and neither Linux
/// `Process.start` nor libmpv searches the executable's own directory — so we
/// resolve them by absolute path.

/// The absolute path of the first name in [candidateNames] that [exists] inside
/// [executableDir], or `null` if none are bundled there. Pure, with injectable
/// deps so it's unit-testable without touching the real filesystem.
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

/// [bundledExecutablePath] against the real bundle directory (next to
/// `Platform.resolvedExecutable`) and filesystem. Returns `null` when no
/// candidate is bundled — callers decide whether to fall back to a bare name
/// (resolved off PATH, so a dev machine with the tool installed still works) or
/// to skip the feature entirely.
String? bundledExecutable(List<String> candidateNames) => bundledExecutablePath(
      candidateNames,
      executableDir: p.dirname(Platform.resolvedExecutable),
      exists: (path) => File(path).existsSync(),
    );
