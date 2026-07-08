import 'dart:io';

import '../process/bundled_executable.dart';

/// Locates the bundled yt-dlp binary (dropped next to the app executable by
/// `tool/fetch_ytdlp_*`) and turns it into the mpv script-opt that points
/// libmpv's builtin `ytdl_hook` at it — how the inline Trailer feature resolves
/// YouTube URLs. libmpv is in-process (media_kit), and `ytdl_hook` only searches
/// PATH, not the app directory, so a bundled binary must be handed over by
/// absolute path.

/// The absolute path of the bundled yt-dlp, or `null` when it isn't bundled (a
/// dev machine may still have it on PATH, which libmpv finds on its own).
String? bundledYtDlpPath() =>
    bundledExecutable([Platform.isWindows ? 'yt-dlp.exe' : 'yt-dlp']);

/// The `script-opts` value that points `ytdl_hook` at the bundled yt-dlp, or
/// `null` to leave libmpv's default PATH lookup in place. Set on the mpv
/// `script-opts` property before opening a network URL.
String? ytdlHookScriptOpt() {
  final path = bundledYtDlpPath();
  return path == null ? null : 'ytdl_hook-ytdl_path=$path';
}
