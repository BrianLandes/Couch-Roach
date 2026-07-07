import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_router.dart';
import '../../theme/theme.dart';

/// M1 placeholder landing screen. Will become the two-rail landing
/// (Continue Watching + For You) in M2. For now it's the app shell entry point
/// and shows the liquid-glass baseline.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: AmbientBackground(
        child: Center(
          child: GlassSurface(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Couch Roach', style: text.displaySmall),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Home Media Center',
                  style: text.titleMedium?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'M1 scaffold — library scan + player next.',
                  style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xl),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.icon(
                      onPressed: () => context.push(Routes.storageSettings),
                      icon: const Icon(Icons.folder_rounded),
                      label: const Text('Manage storage'),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    OutlinedButton(
                      onPressed: () => context.push(Routes.styleShowcase),
                      child: const Text('Style gallery'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
