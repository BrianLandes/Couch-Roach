import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/error_log_service.dart';
import '../../core/storage/storage_manager.dart';
import '../../injection.dart';
import '../../theme/theme.dart';
import '../../widgets/app_back_button.dart';
import 'storage_providers.dart';

/// Manage the library folders content spreads across (one per disk, typically).
/// The scanner reads every enabled root; downloads pick a root by free space.
class StorageSettingsScreen extends ConsumerStatefulWidget {
  const StorageSettingsScreen({super.key});

  @override
  ConsumerState<StorageSettingsScreen> createState() =>
      _StorageSettingsScreenState();
}

class _StorageSettingsScreenState extends ConsumerState<StorageSettingsScreen> {
  final _controller = TextEditingController();
  String? _error;

  StorageManager get _storage => getIt<StorageManager>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final path = _controller.text.trim();
    if (path.isEmpty) return;
    if (!Directory(path).existsSync()) {
      setState(() => _error = "That folder doesn't exist on this machine.");
      return;
    }
    try {
      await _storage.addRoot(path: path);
      _controller.clear();
      setState(() => _error = null);
    } catch (e, st) {
      // Opt in to the central error log, and surface a message to the user.
      getIt<ErrorLogService>()
          .logError(e, stackTrace: st, source: 'StorageSettings.add');
      setState(() => _error = "Couldn't add that folder — see the error log.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rootsAsync = ref.watch(storageRootsProvider);

    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            children: [
              Row(
                children: [
                  const AppBackButton(),
                  const SizedBox(width: AppSpacing.sm),
                  Text('Storage locations', style: text.headlineMedium),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.only(left: 52),
                child: Text(
                  'Library folders the app manages. Content spreads across these '
                  'by free space, and every enabled folder is scanned.',
                  style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Add form.
              GlassSurface(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            onSubmitted: (_) => _add(),
                            decoration: const InputDecoration(
                              hintText: r'Add a library folder, e.g. D:\Media',
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        FilledButton.icon(
                          onPressed: _add,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Add'),
                        ),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _error!,
                        style: text.bodyMedium?.copyWith(color: AppColors.danger),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              rootsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text(
                  'Could not load storage locations: $e',
                  style: text.bodyMedium?.copyWith(color: AppColors.danger),
                ),
                data: (roots) => roots.isEmpty
                    ? _EmptyState(text: text)
                    : Column(
                        children: [
                          for (final root in roots)
                            Padding(
                              padding: const EdgeInsets.only(bottom: AppSpacing.md),
                              child: _RootRow(
                                path: root.path,
                                enabled: root.enabled,
                                onToggle: (v) => _storage.setEnabled(root.id!, v),
                                onRemove: () => _storage.removeRoot(root.id!),
                              ),
                            ),
                        ],
                      ),
              ),

              const SizedBox(height: AppSpacing.xxl),
              const Divider(),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Error log',
                style: text.labelMedium?.copyWith(
                  color: AppColors.textTertiary,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              SelectableText(
                getIt<ErrorLogService>().logFilePath ?? 'initializing…',
                style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RootRow extends StatelessWidget {
  const _RootRow({
    required this.path,
    required this.enabled,
    required this.onToggle,
    required this.onRemove,
  });

  final String path;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GlassSurface(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Icon(
            Icons.folder_rounded,
            color: enabled ? AppColors.primaryBright : AppColors.textTertiary,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              path,
              style: text.titleMedium?.copyWith(
                color: enabled ? AppColors.textPrimary : AppColors.textTertiary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Switch(value: enabled, onChanged: onToggle),
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        children: [
          const Icon(Icons.folder_off_rounded, size: 40, color: AppColors.textTertiary),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No library folders yet',
            style: text.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Add one above to start — one per disk works well.',
            style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
