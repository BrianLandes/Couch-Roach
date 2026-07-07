import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../injection.dart';
import '../../router/app_router.dart';
import '../../theme/theme.dart';
import 'library_providers.dart';
import 'library_service.dart';

/// M1 landing screen. Becomes the two-rail landing (Continue Watching + For You)
/// in M2; for now it shows the library state plus the scan/storage controls.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final itemsAsync = ref.watch(libraryItemsProvider);
    final library = getIt<LibraryService>();

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
                itemsAsync.when(
                  loading: () => Text(
                    'Loading library…',
                    style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
                  ),
                  error: (e, _) => Text(
                    'Library error — see the error log.',
                    style: text.bodyLarge?.copyWith(color: AppColors.danger),
                  ),
                  data: (items) => Text(
                    items.isEmpty
                        ? 'No titles yet — add a library folder, then rescan.'
                        : '${items.length} ${items.length == 1 ? 'title' : 'titles'} in your library',
                    style: text.bodyLarge,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: library.scanning,
                      builder: (context, scanning, _) => FilledButton.icon(
                        onPressed: scanning ? null : () => library.rescan(),
                        icon: scanning
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh_rounded),
                        label: Text(scanning ? 'Scanning…' : 'Rescan'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    OutlinedButton.icon(
                      onPressed: () => context.push(Routes.storageSettings),
                      icon: const Icon(Icons.folder_rounded),
                      label: const Text('Manage storage'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: () => context.push(Routes.styleShowcase),
                  child: const Text('Style gallery'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
