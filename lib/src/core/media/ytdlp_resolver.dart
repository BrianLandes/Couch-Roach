import 'dart:convert';
import 'dart:io';

import 'ytdlp.dart';

/// A directly-playable stream resolved from a page URL (a YouTube trailer): the
/// media URL mpv can demux on its own, plus any HTTP headers yt-dlp says are
/// needed to fetch it (a matching User-Agent, etc.).
class ResolvedStream {
  const ResolvedStream({required this.url, this.headers = const {}});

  final String url;
  final Map<String, String> headers;
}

/// Parse `yt-dlp -j` (dump-json) output into a [ResolvedStream]. With a single
/// format selected (`-f best`), the top-level `url` is that format's direct
/// stream and `http_headers` are the headers to send with it. Returns null when
/// there's no usable `url` (e.g. yt-dlp emitted a playlist or an error). Pure +
/// tested.
ResolvedStream? parseYtDlpJson(String jsonStr) {
  try {
    final json = jsonDecode(jsonStr.trim()) as Map<String, dynamic>;
    final url = json['url'] as String?;
    if (url == null || url.isEmpty) return null;
    final headers = <String, String>{};
    final raw = json['http_headers'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (k is String && k.isNotEmpty && v != null) headers[k] = '$v';
      });
    }
    return ResolvedStream(url: url, headers: headers);
  } catch (_) {
    return null;
  }
}

/// Resolve a page URL to a direct stream with the bundled yt-dlp — the
/// cross-platform replacement for libmpv's builtin `ytdl_hook`, which media_kit's
/// Windows libmpv is built without (no Lua), so a YouTube watch URL handed
/// straight to mpv there fails to demux. `-f best` selects a single pre-muxed
/// progressive stream (one URL, no separate audio/video to merge). Returns null
/// on any failure — yt-dlp missing, a network error, or a non-video URL — so the
/// caller can fall back to handing mpv the raw URL (which works where the hook
/// does exist, e.g. a system libmpv on Linux).
Future<ResolvedStream?> resolveNetworkStream(String url) async {
  final ytDlp =
      bundledYtDlpPath() ?? (Platform.isWindows ? 'yt-dlp.exe' : 'yt-dlp');
  try {
    final res = await Process.run(ytDlp, [
      '-f', 'best',
      '--no-playlist',
      '--no-warnings',
      // Force IPv4. YouTube binds the returned stream URL to the IP yt-dlp
      // extracted it from (the `ip=` query param). On a dual-stack box yt-dlp
      // may resolve over IPv6 while mpv/ffmpeg then fetches over IPv4, so the
      // source IP no longer matches the signed URL → HTTP 400. Pinning yt-dlp to
      // IPv4 keeps it aligned with mpv's fetch (observed: Windows failed on an
      // IPv6-bound URL where Linux, IPv4 end-to-end, worked).
      '--force-ipv4',
      '-j',
      url,
    ]);
    if (res.exitCode != 0) return null;
    return parseYtDlpJson(res.stdout as String);
  } on ProcessException {
    return null; // yt-dlp not bundled and not on PATH
  } catch (_) {
    return null;
  }
}
