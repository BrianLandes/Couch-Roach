import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/error_log_service.dart';
import '../../core/platform/open_url.dart';
import '../../core/settings/settings_service.dart';
import '../../core/storage/storage_manager.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/watch_history_repository.dart';
import '../../injection.dart';
import '../../services/acquisition/jackett_process.dart';
import '../../theme/theme.dart';
import '../../widgets/app_back_button.dart';
import '../../widgets/status_pill.dart';
import '../../data/db/database.dart';
import '../../data/repositories/saved_titles_repository.dart';
import '../acquire/jackett_providers.dart';
import '../discover/taste_providers.dart';
import '../library/saved_titles_providers.dart';
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
                title: 'Auto-play next episode',
                subtitle:
                    'When an episode ends, start the next one automatically if '
                    "it's already downloaded.",
                value: _settings.autoPlayNextEpisode,
                onChanged: (v) => _set(_settings.setAutoPlayNextEpisode(v)),
              ),
              _ToggleRow(
                title: 'Prefer surround sound',
                subtitle: 'Pick the widest audio track (5.1/7.1) when available.',
                value: _settings.preferSurroundAudio,
                onChanged: (v) => _set(_settings.setPreferSurroundAudio(v)),
              ),
              _DropdownRow(
                title: 'Preferred audio language',
                subtitle:
                    'When downloading, favor releases that carry this dubbed '
                    'audio. English plays by default.',
                value: _settings.preferredAudioLanguage,
                options: _audioLanguageOptions,
                onChanged: (v) => _set(_settings.setPreferredAudioLanguage(v)),
              ),
              _ToggleRow(
                title: 'Skip sign-language versions',
                subtitle:
                    'Ignore ASL/BSL release and subtitle variants when matching '
                    'an episode.',
                value: _settings.excludeSignLanguage,
                onChanged: (v) => _set(_settings.setExcludeSignLanguage(v)),
              ),

              // ── Performance ───────────────────────────────────────────────
              const SizedBox(height: AppSpacing.xl),
              _SectionLabel('Video performance', text: text),
              _ToggleRow(
                title: 'Hardware video rendering',
                subtitle:
                    'Use the GPU to draw the video. If video shows blank or a '
                    'solid color, turn it off. (This is rendering, not '
                    'decoding — see below.)',
                value: _settings.hardwareVideoAcceleration,
                onChanged: (v) =>
                    _set(_settings.setHardwareVideoAcceleration(v)),
              ),
              _DropdownRow(
                title: 'Hardware decoder',
                subtitle:
                    'Which GPU decoder to use for video. Leave on Automatic '
                    'unless large files stutter — then try forcing one, or '
                    '"Software" to compare. (Applies on the next video.)',
                value: _settings.hwdecMode,
                options: _hwdecOptions,
                onChanged: (v) => _set(_settings.setHwdecMode(v)),
              ),
              _ToggleRow(
                title: 'Low-power mode',
                subtitle:
                    'Trade a little sharpness for much lower CPU use — helps on '
                    'a weak box that stutters. (Applies on the next video.)',
                value: _settings.lowPowerVideo,
                onChanged: (v) => _set(_settings.setLowPowerVideo(v)),
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

              // ── Home screen ───────────────────────────────────────────────
              const SizedBox(height: AppSpacing.xl),
              _SectionLabel('Home screen', text: text),
              _ToggleRow(
                title: 'Personalized categories',
                subtitle:
                    'Show "Because you watch …" genre rows on the landing '
                    'page, learned from your watch history and saved titles.',
                value: _settings.personalizedCategories,
                onChanged: (v) => _setPersonalizedCategories(v),
              ),
              if (_settings.personalizedCategories &&
                  _settings.hiddenGenres.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _clearHiddenGenres,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(
                        'Show ${_settings.hiddenGenres.length} hidden '
                        'row${_settings.hiddenGenres.length == 1 ? '' : 's'} '
                        'again',
                      ),
                    ),
                  ),
                ),
              const _NotInterestedList(),

              // ── Sources ───────────────────────────────────────────────────
              const SizedBox(height: AppSpacing.xl),
              _SectionLabel('Sources', text: text),
              _ToggleRow(
                title: 'Internet Archive',
                subtitle:
                    'Include public-domain results from archive.org in search, '
                    'the "Free to Watch" row, and as a download source. Off by '
                    'default — your Jackett indexers are the main source.',
                value: _settings.internetArchiveEnabled,
                onChanged: (v) => _set(_settings.setInternetArchiveEnabled(v)),
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
              if (_settings.cleanupEnabled) ...[
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
                _ReapQueue(gracePeriod: _settings.cleanupGracePeriod),
              ],

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

  /// Toggle personalized rows, then invalidate the landing-page provider so it
  /// recomputes (or drops the rows) on the next visit.
  Future<void> _setPersonalizedCategories(bool v) async {
    await _settings.setPersonalizedCategories(v);
    ref.invalidate(personalGenreRowsProvider);
    if (mounted) setState(() {});
  }

  /// Un-hide every dismissed genre row and refresh the landing page.
  Future<void> _clearHiddenGenres() async {
    await _settings.clearHiddenGenres();
    ref.invalidate(personalGenreRowsProvider);
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

/// The "not interested" titles the user has hidden from the landing rails, each
/// with an un-hide action. Renders nothing when the list is empty. Live — the
/// row drops the moment a title is restored.
class _NotInterestedList extends ConsumerWidget {
  const _NotInterestedList();

  Future<void> _unhide(BuildContext context, SavedTitle title) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await getIt<SavedTitlesRepository>().setNotInterested(
        tmdbId: title.tmdbId,
        mediaType: title.mediaType,
        name: title.name,
        posterPath: title.posterPath,
        value: false,
      );
    } catch (e, st) {
      getIt<ErrorLogService>().logError(e,
          stackTrace: st, source: 'Settings.unhideNotInterested');
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't restore that title")),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final titles = ref.watch(notInterestedTitlesProvider).asData?.value ??
        const <SavedTitle>[];
    if (titles.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: GlassSurface(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Not interested — hidden from every row',
              style: text.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final t in titles)
                  InputChip(
                    label: Text(t.name),
                    avatar: const Icon(Icons.not_interested_rounded, size: 18),
                    onDeleted: () => _unhide(context, t),
                    deleteIcon: const Icon(Icons.close_rounded, size: 18),
                    deleteButtonTooltipMessage: 'Show again',
                  ),
              ],
            ),
          ],
        ),
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

/// Audio-language choices for the resolver preference. The value is the
/// canonical key FilenameMediaInfo.audioLanguageScore understands; '' = none.
/// libmpv `hwdec` values. `auto` is first so it's the fallback when the stored
/// value is unknown — and it's what media_kit uses on desktop anyway, so the
/// default changes nothing. The `-copy` variants decode on the GPU then read
/// frames back to system memory: slower, but they work where the zero-copy
/// path can't hand its surface to the renderer.
const _hwdecOptions = <(String, String)>[
  ('auto', 'Automatic (default)'),
  ('auto-copy', 'Automatic (copy back)'),
  ('auto-safe', 'Automatic (safe only)'),
  ('d3d11va', 'Direct3D 11 — Windows'),
  ('d3d11va-copy', 'Direct3D 11, copy back — Windows'),
  ('vaapi', 'VA-API — Linux'),
  ('nvdec', 'NVDEC — NVIDIA'),
  ('no', 'Software (no hardware decoding)'),
];

const _audioLanguageOptions = <(String, String)>[
  ('', 'None (English)'),
  ('portuguese', 'Portuguese'),
  ('spanish', 'Spanish'),
  ('french', 'French'),
  ('german', 'German'),
  ('italian', 'Italian'),
  ('japanese', 'Japanese'),
];

class _DropdownRow extends StatelessWidget {
  const _DropdownRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Fall back to the first option if the stored value isn't a known key.
    final current =
        options.any((o) => o.$1 == value) ? value : options.first.$1;
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
            DropdownButton<String>(
              value: current,
              underline: const SizedBox.shrink(),
              borderRadius: AppRadii.rMd,
              items: [
                for (final o in options)
                  DropdownMenuItem(value: o.$1, child: Text(o.$2)),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ],
        ),
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

/// The pending auto-cleanup queue: watched, unpinned files still on disk, with
/// how long until (or that) each is past the grace period, and a **Keep** action
/// that pins a title so it's never auto-deleted. Live — pinning drops the row.
class _ReapQueue extends ConsumerWidget {
  const _ReapQueue({required this.gracePeriod});

  final Duration gracePeriod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final candidates = ref.watch(reapCandidatesProvider);

    return candidates.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Text('Could not load the cleanup queue: $e',
            style: text.bodySmall?.copyWith(color: AppColors.danger)),
      ),
      data: (items) {
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              'Nothing is queued for cleanup — watched titles show up here '
              'before they’re deleted.',
              style:
                  text.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          );
        }
        return GlassSurface(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final c in items)
                _ReapRow(
                  candidate: c,
                  gracePeriod: gracePeriod,
                  onKeep: () =>
                      getIt<LibraryRepository>().setKeep(c.item.id, true),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ReapRow extends StatelessWidget {
  const _ReapRow({
    required this.candidate,
    required this.gracePeriod,
    required this.onKeep,
  });

  final ReapCandidate candidate;
  final Duration gracePeriod;
  final VoidCallback onKeep;

  /// "Show — S01E03" for a matched episode, otherwise the plain title.
  String get _label {
    final item = candidate.item;
    final name = item.tmdbName ?? item.title;
    final s = item.season, e = item.episode;
    if (s != null && e != null) {
      final code = 'S${s.toString().padLeft(2, '0')}'
          'E${e.toString().padLeft(2, '0')}';
      return '$name · $code';
    }
    return name;
  }

  /// "Deletes in 3 days" / "Deletes today" / "Ready to delete now".
  String get _timing {
    final left = candidate.lastWatchedAt.add(gracePeriod).difference(
          DateTime.now(),
        );
    if (left.inSeconds <= 0) return 'Ready to delete now';
    final days = left.inDays;
    if (days >= 1) return 'Deletes in $days day${days == 1 ? '' : 's'}';
    if (left.inHours >= 1) {
      return 'Deletes in ${left.inHours} hour${left.inHours == 1 ? '' : 's'}';
    }
    return 'Deletes today';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final ready = candidate.lastWatchedAt.add(gracePeriod).isBefore(
          DateTime.now(),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(
            ready
                ? Icons.auto_delete_rounded
                : Icons.schedule_rounded,
            size: 20,
            color: ready ? AppColors.danger : AppColors.textTertiary,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_label,
                    style: text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: AppSpacing.xs),
                Text(_timing,
                    style: text.bodySmall?.copyWith(
                      color:
                          ready ? AppColors.danger : AppColors.textSecondary,
                    )),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: onKeep,
            icon: const Icon(Icons.push_pin_outlined, size: 18),
            label: const Text('Keep'),
          ),
        ],
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
