/// Whether an mpv log line is worth keeping when we're diagnosing the **video
/// pipeline** rather than a specific failure.
///
/// mpv at `v` level is a firehose, most of it irrelevant. What matters for the
/// 4K-stutter question is the decode/render handshake: which hwdec was tried,
/// whether a GPU-surface interop loaded, and what the GL/D3D/ANGLE context
/// reported. Those lines say directly whether libmpv even *has* the D3D11
/// interop compiled in — the thing that decides whether zero-copy is reachable
/// at all, or whether the copy-back is structural.
///
/// Warnings and errors are always kept regardless of subject. Pure + tested.
bool isRenderPipelineLogLine({
  required String level,
  required String prefix,
  required String text,
}) {
  final l = level.toLowerCase();
  if (l == 'error' || l == 'fatal' || l == 'warn' || l == 'w') return true;

  final haystack = '$prefix $text'.toLowerCase();
  for (final k in _renderKeywords) {
    if (haystack.contains(k)) return true;
  }
  return false;
}

// Substrings that mark a line as part of the decode/render handshake. Chosen to
// be distinctive enough not to sweep in unrelated chatter — deliberately no
// bare 'gl', which appears in far too many unrelated words.
const _renderKeywords = <String>[
  'hwdec',
  'interop',
  'd3d',
  'dxva',
  'angle',
  'egl',
  'opengl',
  'gpu',
  'vaapi',
  'nvdec',
  'vulkan',
  'vo/',
  'libmpv',
];
