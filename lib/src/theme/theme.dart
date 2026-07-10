import 'package:flutter/material.dart';

import 'colors.dart';
import 'radii.dart';
import 'spacing.dart';
import 'typography.dart';

// Barrel — `import 'package:couch_roach/src/theme/theme.dart';` gets the whole system.
export 'colors.dart';
export 'glass.dart';
export 'radii.dart';
export 'spacing.dart';
export 'typography.dart';

/// The app's Material theme, wired to the liquid-glass tokens. Screens paint an
/// [AmbientBackground] and float [GlassSurface]s on top; this theme handles the
/// text, buttons, inputs, and focus styling. See docs/STYLE.md.
abstract final class AppTheme {
  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: Color(0xFF0A0B14),
      secondary: AppColors.secondary,
      onSecondary: Color(0xFF04121A),
      tertiary: AppColors.tertiary,
      surface: AppColors.bgElevated,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
      onError: Color(0xFF1A0308),
      outline: AppColors.glassStroke,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      canvasColor: Colors.transparent,
      focusColor: AppColors.focusGlow,
      splashColor: AppColors.focusGlow,
      textTheme: AppTypography.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      iconTheme: const IconThemeData(color: AppColors.textPrimary),
    );

    return base.copyWith(
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(0, AppSpacing.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.rPill),
          textStyle: AppTypography.textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size(0, AppSpacing.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          side: const BorderSide(color: AppColors.glassStroke),
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.rPill),
          textStyle: AppTypography.textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.secondary,
          minimumSize: const Size(0, AppSpacing.minTouchTarget),
          textStyle: AppTypography.textTheme.labelLarge,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.glassFill,
        side: const BorderSide(color: AppColors.glassStroke),
        labelStyle: AppTypography.textTheme.labelMedium
            ?.copyWith(color: AppColors.textSecondary),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: AppColors.glassFill,
        hintStyle: TextStyle(color: AppColors.textTertiary),
        border: OutlineInputBorder(
          borderRadius: AppRadii.rMd,
          borderSide: BorderSide(color: AppColors.glassStroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.rMd,
          borderSide: BorderSide(color: AppColors.glassStroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.rMd,
          borderSide: BorderSide(color: AppColors.focus, width: 2),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.glassStroke,
        thickness: 1,
        space: 1,
      ),
      // Chunky, grabbable scrollbars for the 10-foot / mouse-driven UI. Always
      // visibility is forced per-axis in AppScrollBehavior (vertical only, so
      // the horizontal tile rails stay clean); this sets the look.
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(12),
        radius: const Radius.circular(6),
        minThumbLength: 48,
        interactive: true,
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged) ||
              states.contains(WidgetState.hovered)) {
            return AppColors.textSecondary;
          }
          return AppColors.textTertiary;
        }),
      ),
    );
  }
}
