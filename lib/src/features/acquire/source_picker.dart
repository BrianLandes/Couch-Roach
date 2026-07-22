import 'package:flutter/material.dart';

import '../../services/acquisition/acquisition.dart';
import '../../theme/theme.dart';
import '../../widgets/focusable_card.dart';
import '../downloads/download_format.dart';
import 'acquire_play.dart';

/// Show the "Choose source" picker for a title and return the source the user
/// picked, or null if they cancelled. Lists every verified, ranked, deduped
/// candidate (episode releases *and* the season packs that contain it) with its
/// size / seeders so the user can pick deliberately instead of trusting the
/// blind auto-rank — the fix for a hard-to-find episode with only a couple of
/// bad auto-picks. 10-foot: rows are focusable for the remote.
Future<SourceCandidate?> showSourcePicker(
  BuildContext context, {
  required String title,
  required ShowMeta meta,
  int? season,
  int? episode,
}) {
  return showDialog<SourceCandidate>(
    context: context,
    builder: (ctx) => _SourcePickerDialog(
      title: title,
      meta: meta,
      season: season,
      episode: episode,
    ),
  );
}

class _SourcePickerDialog extends StatefulWidget {
  const _SourcePickerDialog({
    required this.title,
    required this.meta,
    this.season,
    this.episode,
  });

  final String title;
  final ShowMeta meta;
  final int? season;
  final int? episode;

  @override
  State<_SourcePickerDialog> createState() => _SourcePickerDialogState();
}

class _SourcePickerDialogState extends State<_SourcePickerDialog> {
  late final Future<List<SourceCandidate>> _candidates = sourceCandidates(
    meta: widget.meta,
    season: widget.season,
    episode: widget.episode,
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('Choose a source'),
      content: SizedBox(
        width: 560,
        child: FutureBuilder<List<SourceCandidate>>(
          future: _candidates,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final sources = snap.data ?? const <SourceCandidate>[];
            if (sources.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  'No sources found. The indexers you have configured in Jackett '
                  'returned nothing for this — try again later, or add an indexer '
                  'that carries it.',
                  style: text.bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              itemCount: sources.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, i) => _SourceRow(
                source: sources[i],
                autofocus: i == 0,
                onPressed: () => Navigator.pop(context, sources[i]),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.source,
    required this.onPressed,
    this.autofocus = false,
  });

  final SourceCandidate source;
  final VoidCallback onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final meta = [
      if (source.sizeBytes > 0) formatBytes(source.sizeBytes),
      '${source.seeders} seeder${source.seeders == 1 ? '' : 's'}',
    ].join('  ·  ');

    return FocusableCard(
      autofocus: autofocus,
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(source.title,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: text.titleSmall),
                  const SizedBox(height: AppSpacing.xs),
                  Text(meta,
                      style: text.labelMedium
                          ?.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
            if (source.isSeasonPack) ...[
              const SizedBox(width: AppSpacing.sm),
              const _Badge('Season pack'),
            ],
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: const BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: AppRadii.rSm,
      ),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: AppColors.secondary)),
    );
  }
}
