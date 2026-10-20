import 'dart:ui' show Offset, Size;

/// Where media_kit's desktop seek bar sits, so a hover over it can be mapped to
/// a time without forking its controls. These mirror media_kit's
/// `MaterialDesktopVideoControlsThemeData` defaults, which the player doesn't
/// override (see `_controlsTheme`): a 56px bottom button bar, and above it a
/// 36px-tall seek bar nudged down 16px onto the button bar, inset 16px each
/// side. Change them together with the theme.
const kPlayerButtonBarHeight = 56.0;
const kPlayerSeekBarHeight = 36.0;
const kPlayerSeekBarShift = 16.0;
const kPlayerSeekBarInset = 16.0;

/// Distance from the player's bottom edge to the top of the seek bar.
const kPlayerSeekBarTopFromBottom =
    kPlayerButtonBarHeight + kPlayerSeekBarHeight - kPlayerSeekBarShift;

/// The fraction (0–1) along the seek bar under [pos] in a player of [size], or
/// null when [pos] isn't over the bar. [slop] widens the target a little so the
/// preview doesn't flicker at the bar's edges. While [dragging] (a press that
/// started on the bar) only the horizontal position matters — the pointer
/// drifting up or down mid-drag still scrubs. Pure + tested.
double? seekBarFraction(Offset pos, Size size,
    {bool dragging = false, double slop = 6}) {
  final width = size.width - 2 * kPlayerSeekBarInset;
  if (width <= 0) return null;
  final x = pos.dx - kPlayerSeekBarInset;
  if (!dragging) {
    final top = size.height - kPlayerSeekBarTopFromBottom;
    final bottom = top + kPlayerSeekBarHeight;
    if (pos.dy < top - slop || pos.dy > bottom + slop) return null;
    if (x < -slop || x > width + slop) return null;
  }
  return (x / width).clamp(0.0, 1.0);
}

/// Left edge for a preview [previewWidth] wide centred over [fraction] of the
/// bar, kept [edge] px inside the player. Pure + tested.
double seekPreviewLeft({
  required double fraction,
  required double playerWidth,
  required double previewWidth,
  double edge = 8,
}) {
  final barWidth = playerWidth - 2 * kPlayerSeekBarInset;
  final centre = kPlayerSeekBarInset + fraction * barWidth;
  final maxLeft = playerWidth - previewWidth - edge;
  if (maxLeft < edge) return edge;
  return (centre - previewWidth / 2).clamp(edge, maxLeft);
}

/// "1:02:03" / "4:05" — the preview's timestamp. Pure + tested.
String formatPreviewTime(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
}
