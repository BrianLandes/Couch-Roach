import 'package:flutter/widgets.dart';

/// Couch Roach palette — a dark "liquid glass" system: near-black cool base,
/// ambient accent glows behind translucent frosted surfaces, iridescent brand
/// accents. See docs/STYLE.md.
///
/// Alpha is baked into the glass tokens as hex (0xAARRGGBB) so surfaces stay
/// `const` and we avoid deprecated runtime opacity calls.
abstract final class AppColors {
  // ── Base surfaces ─────────────────────────────────────────────────────────
  /// App background — the darkest layer everything floats on.
  static const bg = Color(0xFF05060A);
  static const bgElevated = Color(0xFF0B0D15);

  // ── Ambient glows (blurred blobs painted behind glass) ────────────────────
  static const glowIndigo = Color(0xFF3B2E7E);
  static const glowViolet = Color(0xFF5B2E8C);
  static const glowCyan = Color(0xFF1E6E8C);

  // ── Brand accents (iridescent) ────────────────────────────────────────────
  static const primary = Color(0xFF6C7DFF); // periwinkle/indigo — the anchor
  static const primaryBright = Color(0xFF8FA0FF);
  static const secondary = Color(0xFF38E1FF); // cyan — highlights, focus
  static const tertiary = Color(0xFFFF6AD5); // magenta — sparing pops

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, secondary],
  );

  // ── Semantic ──────────────────────────────────────────────────────────────
  static const success = Color(0xFF3DE0A0);
  static const warning = Color(0xFFFFC24B);
  static const danger = Color(0xFFFF5C7A);

  // ── Text ──────────────────────────────────────────────────────────────────
  static const textPrimary = Color(0xFFF3F5FF);
  static const textSecondary = Color(0xFFAAB1CC);
  static const textTertiary = Color(0xFF6E7591);

  // ── Glass (translucent fills, hairline strokes, edge highlight) ───────────
  static const glassFill = Color(0x14FFFFFF); // ~8% white
  static const glassFillStrong = Color(0x22FFFFFF); // ~13%
  static const glassStroke = Color(0x2EFFFFFF); // ~18% hairline border
  static const glassHighlight = Color(0x59FFFFFF); // top-edge sheen
  static const scrim = Color(0x9905060A); // darken behind foreground

  // ── Focus (10-foot / remote) ──────────────────────────────────────────────
  /// Bright ring drawn around the focused element; pair with [focusGlow].
  static const focus = secondary;
  static const focusGlow = Color(0x5538E1FF);
}
