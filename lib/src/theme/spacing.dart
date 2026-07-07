/// Spacing scale. Tuned a little larger than a touch app — this is viewed from a
/// couch and driven by a remote, so targets and gaps are generous.
/// See docs/STYLE.md.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// Minimum interactive size for comfortable D-pad targeting at 10 feet.
  static const double minTouchTarget = 56;

  /// Standard page edge inset on a TV (accounts for overscan-ish framing).
  static const double screenPadding = 48;
}
