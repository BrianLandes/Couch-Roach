import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'video_extensions.dart';
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

    // Prefer the *selected format's* own headers over the top-level ones.
    //
    // This matters: YouTube ties a playback URL to the client that extracted it
    // (the `c=` query param — e.g. `c=ANDROID_VR`), and rejects a fetch whose
    // User-Agent doesn't match with **HTTP 403**. yt-dlp's top-level
    // `http_headers` is the generic set and can carry a desktop-Chrome UA while
    // the chosen format came from a different client, which is exactly the
    // mismatch that broke trailer playback. The per-format headers are the ones
    // that actually go with this URL.
    var headers = _headersFrom(json['http_headers']);
    final formats = json['formats'];
    if (formats is List) {
      for (final f in formats) {
        if (f is Map && f['url'] == url) {
          final perFormat = _headersFrom(f['http_headers']);
          if (perFormat.isNotEmpty) headers = perFormat;
          break;
        }
      }
    }
    return ResolvedStream(url: url, headers: headers);
  } catch (_) {
    return null;
  }
}

Map<String, String> _headersFrom(Object? raw) {
  final headers = <String, String>{};
  if (raw is Map) {
    raw.forEach((k, v) {
      if (k is String && k.isNotEmpty && v != null) headers[k] = '$v';
    });
  }
  return headers;
}

/// Headers to forward to mpv as `http-header-fields` entries, formatted
/// `Name: value`.
///
/// [skipped] names are left out deliberately:
/// * **User-Agent** is set through mpv's dedicated `user-agent` property, and
///   sending it twice risks a duplicate header.
/// * **Accept-Encoding** — ffmpeg negotiates and decodes compression itself;
///   forcing yt-dlp's value can yield a body mpv won't decode.
/// * **Host / Connection / Content-Length / Range** are per-connection and
///   mpv's own, so overriding them corrupts the request.
///
/// Pure + tested.
List<String> mpvHeaderFields(Map<String, String> headers) {
  const skipped = {
    'user-agent',
    'accept-encoding',
    'host',
    'connection',
    'content-length',
    'range',
  };
  final out = <String>[];
  headers.forEach((k, v) {
    if (skipped.contains(k.toLowerCase())) return;
    if (v.isEmpty) return;
    out.add('$k: $v');
  });
  return out;
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

/// Pick the best subtitle sidecar from [paths] (what yt-dlp wrote): a `.vtt`
/// (mpv reads WebVTT natively) or `.srt`, preferring the shortest filename so a
/// plain `…​.en.vtt` wins over a regional `…​.en-US.vtt`. Null when none match.
/// Pure + tested.
String? pickSubtitleFile(Iterable<String> paths) {
  final subs = paths.where((path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.vtt') || lower.endsWith('.srt');
  }).toList()
    ..sort((a, b) => a.length.compareTo(b.length));
  return subs.isEmpty ? null : subs.first;
}

/// Download a page URL's English caption track with the bundled yt-dlp and
/// return the sidecar path, or null when there are no captions (or yt-dlp is
/// unavailable). Used to give trailers subtitles — mpv plays the direct stream
/// we resolved, which carries none. Written as `.vtt` (no ffmpeg needed to
/// convert, and mpv reads WebVTT); manual captions are preferred over
/// auto-generated. Files land in [destDir] (a caller-owned temp dir it cleans
/// up). Best-effort: never throws.
Future<String?> fetchNetworkSubtitle(
  String url, {
  required String destDir,
  String lang = 'en',
}) async {
  final ytDlp =
      bundledYtDlpPath() ?? (Platform.isWindows ? 'yt-dlp.exe' : 'yt-dlp');
  try {
    final res = await Process.run(ytDlp, [
      '--skip-download',
      '--write-subs',
      '--write-auto-subs',
      '--sub-langs', '$lang.*,$lang',
      '--sub-format', 'vtt',
      '--no-playlist',
      '--no-warnings',
      // Same IPv4 pin as the stream resolve — keep the caption fetch aligned.
      '--force-ipv4',
      '-o', p.join(destDir, 'trailer'),
      url,
    ]);
    if (res.exitCode != 0) return null;
    final dir = Directory(destDir);
    if (!dir.existsSync()) return null;
    return pickSubtitleFile(dir.listSync().whereType<File>().map((f) => f.path));
  } on ProcessException {
    return null; // yt-dlp not bundled and not on PATH
  } catch (_) {
    return null;
  }
}


/// The downloaded video among [paths] — the largest file with a playable video
/// extension, or null when yt-dlp wrote none.
///
/// Largest wins because the same directory also holds the caption sidecar and
/// can hold a leftover fragment; the media file is comfortably the biggest.
/// Pure + tested.
String? pickDownloadedVideo(Iterable<({String path, int sizeBytes})> files) {
  ({String path, int sizeBytes})? best;
  for (final f in files) {
    final ext = p.extension(f.path).toLowerCase();
    if (!kVideoExtensions.contains(ext)) continue;
    if (best == null || f.sizeBytes > best.sizeBytes) best = f;
  }
  return best?.path;
}

/// Download a page URL's video with the bundled yt-dlp and return the file path.
///
/// This is how trailers play. Handing mpv the *signed* googlevideo URL kept
/// failing: YouTube binds that URL to the client that extracted it (the `c=`
/// query param), to the source IP, and to an expiry, and answers **403** when
/// the fetch doesn't match on every axis. Matching yt-dlp's headers fixed some
/// cases and not others, and YouTube keeps rotating which client yt-dlp has to
/// use — so the fetch is handed to yt-dlp, which already holds whatever that
/// format needs. Trailers are small (a couple of minutes of muxed ≤720p), so
/// the wait is short and the file is temporary.
///
/// Returns null on any failure so the caller can fall back to streaming.
Future<String?> downloadNetworkVideo(
  String url, {
  required String destDir,
  void Function(String detail)? onFailure,
}) async {
  final ytDlp =
      bundledYtDlpPath() ?? (Platform.isWindows ? 'yt-dlp.exe' : 'yt-dlp');
  try {
    final res = await Process.run(ytDlp, [
      // One pre-muxed progressive stream — no separate audio/video to merge,
      // which would need ffmpeg and produce a much larger file.
      '-f', 'best',
      '--no-playlist',
      '--no-warnings',
      // Same IPv4 pin as the rest of the yt-dlp calls.
      '--force-ipv4',
      // Write straight to the final name; a leftover .part would otherwise sit
      // in the directory we scan.
      '--no-part',
      '-o', p.join(destDir, 'trailer.%(ext)s'),
      url,
    ]);
    if (res.exitCode != 0) {
      // yt-dlp's stderr is the only thing that says *why* — a broken extractor,
      // an HTTP 403, a geo block. Without it a failure here is undiagnosable.
      onFailure?.call('yt-dlp exit ${res.exitCode}: ${_tail('${res.stderr}')}');
      return null;
    }
    final dir = Directory(destDir);
    if (!dir.existsSync()) {
      onFailure?.call('yt-dlp reported success but wrote no directory');
      return null;
    }
    final picked = pickDownloadedVideo(dir
        .listSync()
        .whereType<File>()
        .map((f) => (path: f.path, sizeBytes: f.lengthSync())));
    if (picked == null) {
      onFailure?.call('yt-dlp wrote no playable file into $destDir');
    }
    return picked;
  } on ProcessException catch (e) {
    onFailure?.call('yt-dlp not runnable: $e');
    return null; // not bundled and not on PATH
  } catch (e) {
    onFailure?.call('$e');
    return null;
  }
}

/// The last few lines of a process's output — enough to name the failure
/// without pasting a screenful of progress bars into the log.
String _tail(String output, {int lines = 6}) {
  final kept = output
      .trim()
      .split('\n')
      .where((l) => l.trim().isNotEmpty)
      .toList();
  if (kept.length <= lines) return kept.join(' | ');
  return kept.sublist(kept.length - lines).join(' | ');
}
