import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/error_log_service.dart';
import '../../core/platform/open_url.dart';
import '../../core/settings/settings_service.dart';
import '../../core/storage/storage_manager.dart';
import '../../injection.dart';
import '../../services/acquisition/jackett_process.dart';
import '../../theme/theme.dart';
import '../../widgets/app_back_button.dart';
import '../../widgets/status_pill.dart';
import '../acquire/jackett_providers.dart';
import 'storage_providers.dart';

/// The one place to manage the app: library folders (add with an OS folder
/// picker, enable/remove), plus the feature toggles — auto-download subtitles,
/// require VPN, and auto-cleanup with its grace period.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _controller = TextEditingController();
  String? _folderError;

  SettingsService get _settings => getIt<SettingsService>();
  StorageManager get _storage => getIt<StorageManager>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    try {
      final path = await getDirectoryPath(confirmButtonText: 'Add folder');
      if (path != null) await _addRoot(path);
    } catch (e, st) {
      getIt<ErrorLogService>()
          .logError(e, stackTrace: st, source: 'Settings.pickFolder');
      setState(() => _folderError = "Couldn't open the folder picker.");
    }
  }

  Future<void> _addManual() async {
    final path = _controller.text.trim();
    if (path.isEmpty) return;
    await _addRoot(path);
  }

  Future<void> _addRoot(String path) async {
    if (!Directory(path).existsSync()) {
      setState(() => _folderError = "That folder doesn't exist on this machine.");
      return;
    }
    try {
      await _storage.addRoot(path: path);
      _controller.clear();
      setState(() => _folderError = null);
    } catch (e, st) {
      getIt<ErrorLogService>()
          .logError(e, stackTrace: st, source: 'Settings.addRoot');
      setState(() => _folderError = "Couldn't add that folder — see the error log.");
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
                  Text('Settings', style: text.headlineMedium),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),

              // ── Playback ──────────────────────────────────────────────────
              _SectionLabel('Playback', text: text),
              _ToggleRow(
                title: 'Auto-download English subtitles',
                subtitle:
                    'Fetch subtitles from OpenSubtitles when a title has none.',
                value: _settings.autoDownloadSubtitles,
                onChanged: (v) => _set(_settings.setAutoDownloadSubtitles(v)),
              ),
              _ToggleRow(
                title: 'Prefer surround sound',
                subtitle: 'Pick the widest audio track (5.1/7.1) when available.',
                value: _settings.preferSurroundAudio,
                onChanged: (v) => _set(_settings.setPreferSurroundAudio(v)),
              ),
              _ToggleRow(
                title: 'Skip sign-language versions',
                subtitle:
                    'Ignore ASL/BSL release and subtitle variants when matching '
                    'an episode.',
                value: _settings.excludeSignLanguage,
                onChanged: (v) => _set(_settings.setExcludeSignLanguage(v)),
              ),

              // ── Streaming / VPN ───────────────────────────────────────────
              const SizedBox(height: AppSpacing.xl),
              _SectionLabel('Streaming', text: text),
              _ToggleRow(
                title: 'Require VPN before streaming',
                subtitle:
                    'Block downloads/streaming until ExpressVPN is connected.',
                value: _settings.requireVpn,
                onChanged: (v) => _set(_settings.setRequireVpn(v)),
              ),

              // ── Indexers ──────────────────────────────────────────────────
              const SizedBox(height: AppSpacing.xl),
              _SectionLabel('Indexers', text: text),
              Text(
                'Downloads come from the indexers you configure in Jackett. Add '
                'your own legal / public-domain indexers in its web interface — '
                'nothing is enabled by default.',
                style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              const _IndexerService(),

              // ── Cleanup ───────────────────────────────────────────────────
              const SizedBox(height: AppSpacing.xl),
              _SectionLabel('Cleanup', text: text),
              _ToggleRow(
                title: 'Auto-delete watched titles',
                subtitle:
                    'After a full watch, free the disk (watch history is kept).',
                value: _settings.cleanupEnabled,
                onChanged: (v) => _set(_settings.setCleanupEnabled(v)),
              ),
              if (_settings.cleanupEnabled)
                _StepperRow(
                  title: 'Grace period',
                  valueLabel: '${_settings.cleanupGraceDays} '
                      'day${_settings.cleanupGraceDays == 1 ? '' : 's'}',
                  onDecrement: _settings.cleanupGraceDays > 1
                      ? () => _set(_settings
                          .setCleanupGraceDays(_settings.cleanupGraceDays - 1))
                      : null,
                  onIncrement: _settings.cleanupGraceDays < 90
                      ? () => _set(_settings
                          .setCleanupGraceDays(_settings.cleanupGraceDays + 1))
                      : null,
                ),

              // ── Library folders ───────────────────────────────────────────
              const SizedBox(height: AppSpacing.xl),
              _SectionLabel('Library folders', text: text),
              Text(
                'Folders the app manages. Content spreads across these by free '
                'space, and every enabled folder is scanned.',
                style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              GlassSurface(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FilledButton.icon(
                      onPressed: _pickFolder,
                      icon: const Icon(Icons.create_new_folder_rounded),
                      label: const Text('Add folder…'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            onSubmitted: (_) => _addManual(),
                            decoration: const InputDecoration(
                              hintText: r'…or type a path, e.g. D:\Media',
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        OutlinedButton(
                          onPressed: _addManual,
                          child: const Text('Add'),
                        ),
                      ],
                    ),
                    if (_folderError != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(_folderError!,
                          style: text.bodyMedium
                              ?.copyWith(color: AppColors.danger)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              rootsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Could not load folders: $e',
                    style: text.bodyMedium?.copyWith(color: AppColors.danger)),
                data: (roots) => roots.isEmpty
                    ? Text('No library folders yet — add one above.',
                        style: text.bodyMedium
                            ?.copyWith(color: AppColors.textSecondary))
                    : Column(
                        children: [
                          for (final root in roots)
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: AppSpacing.md),
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

              // ── Diagnostics ───────────────────────────────────────────────
              const SizedBox(height: AppSpacing.xxl),
              const Divider(),
              const SizedBox(height: AppSpacing.md),
              _SectionLabel('Error log', text: text),
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

  /// Await a setter, then rebuild so the toggle/value reflects the new state.
  Future<void> _set(Future<void> op) async {
    await op;
    if (mounted) setState(() {});
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, {required this.text});
  final String label;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        label.toUpperCase(),
        style: text.labelMedium
            ?.copyWith(color: AppColors.textTertiary, letterSpacing: 1.5),
      ),
    );
  }
}

/// The indexer-service card: Jackett's online/offline status + a button to open
/// its local web UI (where the user adds their own legal/public-domain indexers).
class _IndexerService extends ConsumerWidget {
  const _IndexerService();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final alive = ref.watch(jackettAliveProvider).asData?.value;
    return GlassSurface(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Jackett indexer service', style: text.titleMedium),
              ),
              StatusPill.health(
                alive: alive,
                onlineLabel: 'Online',
                offlineLabel: 'Offline',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Runs locally at ${JackettProcess.baseUrl}. Open its web interface to '
            'add and manage your indexers.',
            style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: alive == false
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.of(context);
                    if (!await openUrl(JackettProcess.baseUrl)) {
                      messenger.showSnackBar(const SnackBar(
                        content: Text('Could not open the browser — '
                            'see the error log.'),
                      ));
                    }
                  },
            icon: const Icon(Icons.open_in_browser_rounded),
            label: const Text('Open Jackett'),
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: GlassSurface(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(subtitle,
                      style: text.bodySmall
                          ?.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.title,
    required this.valueLabel,
    this.onDecrement,
    this.onIncrement,
  });

  final String title;
  final String valueLabel;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: GlassSurface(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        child: Row(
          children: [
            Expanded(child: Text(title, style: text.titleMedium)),
            IconButton(
              onPressed: onDecrement,
              icon: const Icon(Icons.remove_circle_outline_rounded),
              tooltip: 'Fewer days',
            ),
            SizedBox(
              width: 72,
              child: Text(valueLabel,
                  textAlign: TextAlign.center, style: text.titleMedium),
            ),
            IconButton(
              onPressed: onIncrement,
              icon: const Icon(Icons.add_circle_outline_rounded),
              tooltip: 'More days',
            ),
          ],
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
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      child: Row(
        children: [
          Icon(Icons.folder_rounded,
              color: enabled ? AppColors.primaryBright : AppColors.textTertiary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(path,
                style: text.titleMedium?.copyWith(
                  color: enabled ? AppColors.textPrimary : AppColors.textTertiary,
                ),
                overflow: TextOverflow.ellipsis),
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
