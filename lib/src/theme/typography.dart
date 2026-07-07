import 'package:flutter/material.dart';

/// Type ramp. Uses the platform default family (no runtime font download) with
/// sizes nudged up for legibility from a couch. Colors are applied by the theme
/// via `.apply(bodyColor:, displayColor:)`, so styles here stay color-agnostic.
/// See docs/STYLE.md.
abstract final class AppTypography {
  static const TextTheme textTheme = TextTheme(
    displaySmall: TextStyle(
      fontSize: 40,
      height: 1.1,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
    ),
    headlineMedium: TextStyle(
      fontSize: 30,
      height: 1.15,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.25,
    ),
    headlineSmall: TextStyle(
      fontSize: 24,
      height: 1.2,
      fontWeight: FontWeight.w600,
    ),
    titleLarge: TextStyle(
      fontSize: 22,
      height: 1.25,
      fontWeight: FontWeight.w600,
    ),
    titleMedium: TextStyle(
      fontSize: 18,
      height: 1.3,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: TextStyle(fontSize: 17, height: 1.4, fontWeight: FontWeight.w400),
    bodyMedium: TextStyle(fontSize: 15, height: 1.4, fontWeight: FontWeight.w400),
    labelLarge: TextStyle(
      fontSize: 15,
      height: 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    ),
    labelMedium: TextStyle(
      fontSize: 13,
      height: 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
    ),
  );
}
