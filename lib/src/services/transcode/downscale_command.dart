import 'dart:convert';

/// Hardware HEVC encoders we'll use, best-first.
///
/// Software encoders are deliberately absent: the bundled FFmpeg is BtbN's
/// **LGPL** build, which ships no x264/x265 (both GPL). That's the right license
/// posture to keep, and it's the right technical call anyway — software-encoding
/// 4K on the kind of box that needs this would take hours, where a hardware
/// encoder runs faster than realtime.
const kPreferredEncoders = <String>[
  'hevc_qsv', // Intel Quick Sync — the iGPU case this exists for
  'hevc_nvenc', // NVIDIA
  'hevc_amf', // AMD
  'hevc_vaapi', // Linux
];

/// The first of [kPreferredEncoders] present in `ffmpeg -encoders` output, or
/// null when the build has none.
///
/// Null means the downscale feature stays off rather than falling back to a
/// software encoder that would never finish. Pure + tested.
String? pickHardwareEncoder(String ffmpegEncodersOutput) {
  final lines = ffmpegEncodersOutput.split('\n');
  final available = <String>{};
  for (final line in lines) {
    // Rows look like " V....D hevc_qsv   HEVC (Intel Quick Sync Video acceleration)".
    for (final field in line.trim().split(RegExp(r'\s+'))) {
      available.add(field);
    }
  }
  for (final e in kPreferredEncoders) {
    if (available.contains(e)) return e;
  }
  return null;
}

/// ffmpeg arguments to downscale [input] to at most [maxHeight], writing
/// [output].
///
/// Deliberate choices:
/// * **`-map 0` + `-c copy`, then `-c:v <encoder>`** — every stream is carried
///   over and only the *video* is re-encoded. A Dolby Atmos track and the
///   subtitle streams are copied bit-for-bit, never touched.
/// * **`scale=-2:<h>`** — height-driven, width computed to preserve aspect and
///   rounded to an even number (encoders reject odd dimensions). A 2:1 4K film
///   becomes 2160x1080, not a squashed 16:9.
/// * **`p010le`** — stays 10-bit. We are **not** tone-mapping HDR to SDR: that
///   needs filters the LGPL build may lack, is slow, and gets washed-out results
///   when wrong. The entire win here is the 4x drop in pixels, and that survives
///   keeping HDR intact.
/// * **`-nostdin`** — a background job must never sit waiting on a prompt.
///
/// Pure + tested.
List<String> downscaleArgs({
  required String input,
  required String output,
  required String encoder,
  required int maxHeight,
  int globalQuality = 24,
}) =>
    [
      '-y',
      '-hide_banner',
      '-nostdin',
      '-i', input,
      '-map', '0',
      '-c', 'copy',
      '-c:v', encoder,
      '-vf', 'scale=-2:$maxHeight',
      '-pix_fmt', 'p010le',
      '-global_quality', '$globalQuality',
      output,
    ];

/// ffprobe arguments that report the first video stream's dimensions as JSON.
List<String> probeVideoStreamArgs(String input) => [
      '-v', 'quiet',
      '-print_format', 'json',
      '-show_streams',
      '-select_streams', 'v:0',
      input,
    ];

/// The height of the first video stream in [probeVideoStreamArgs] output, or
/// null when the JSON is unusable (no video stream, malformed, empty).
///
/// Null is "don't know", and callers must treat it as "leave the file alone" —
/// re-encoding something we couldn't measure would be worse than skipping it.
/// Pure + tested.
int? parseFfprobeVideoHeight(String jsonText) {
  try {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) return null;
    final streams = decoded['streams'];
    if (streams is! List || streams.isEmpty) return null;
    final first = streams.first;
    if (first is! Map<String, dynamic>) return null;
    final h = first['height'];
    if (h is int) return h > 0 ? h : null;
    if (h is String) {
      final parsed = int.tryParse(h);
      return (parsed != null && parsed > 0) ? parsed : null;
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// Whether a file measuring [height] should be downscaled to [maxHeight].
///
/// A small margin stops a pointless re-encode of something already essentially
/// at the cap (a 1088-tall file against a 1080 cap is not worth an hour of GPU
/// time). [maxHeight] of 0 or less means the feature is off. Pure + tested.
bool needsDownscale({required int? height, required int maxHeight}) {
  if (maxHeight <= 0 || height == null) return false;
  return height > maxHeight + _capMargin;
}

const _capMargin = 64;
