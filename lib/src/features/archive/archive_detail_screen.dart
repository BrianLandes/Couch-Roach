import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/acquisition/archive_browse_service.dart';
import '../../theme/theme.dart';
import '../../widgets/app_back_button.dart';
import '../../widgets/poster_art.dart';
import '../downloads/download_format.dart' show formatBytes;
import 'archive_play.dart';
import 'archive_providers.dart';

/// Profile/detail page for an Internet Archive title (per the "tiles open a
/// profile page, not the player" rule). Shows the item's poster, year, credits,
/// description and its video files; playback is started from the Play button
/// here (downloads-and-watches via [playArchiveItem]).
class ArchiveDetailScreen extends ConsumerWidget {
  const ArchiveDetailScreen({super.key, required this.item});
  final ArchiveItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(archiveDetailProvider(item.identifier));

    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.md,
              AppSpacing.screenPadding,
              AppSpacing.screenPadding,
            ),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppBackButton(),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _Hero(
                      item: item,
                      detail: detailAsync.asData?.value,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                autofocus: true,
                onPressed: () => playArchiveItem(context, item),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Play'),
              ),
              ...switch (detailAsync) {
                AsyncData(:final value) => _body(context, value),
                AsyncError() => const [
                    SizedBox(height: AppSpacing.xl),
                    Text('Could not load details — see the error log.',
                        style: TextStyle(color: AppColors.danger)),
                  ],
                _ => const [
                    SizedBox(height: AppSpacing.xxl),
                    Center(child: CircularProgressIndicator()),
                  ],
              },
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, ArchiveDetail? detail) {
    final text = Theme.of(context).textTheme;
    if (detail == null) return const [];
    return [
      if (detail.description != null) ...[
        const SizedBox(height: AppSpacing.lg),
        Text(detail.description!,
            style: text.bodyMedium?.copyWith(color: AppColors.textSecondary)),
      ],
      if (detail.videos.length > 1) ...[
        const SizedBox(height: AppSpacing.xl),
        Text('In this item · ${detail.videos.length} videos',
            style: text.labelMedium?.copyWith(
                color: AppColors.textTertiary, letterSpacing: 1.2)),
        const SizedBox(height: AppSpacing.sm),
        for (final v in detail.videos)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: GlassSurface(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: Row(
                children: [
                  const Icon(Icons.movie_outlined,
                      size: 18, color: AppColors.textTertiary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(v.displayName,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  if (v.sizeBytes > 0) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Text(formatBytes(v.sizeBytes),
                        style: text.labelSmall
                            ?.copyWith(color: AppColors.textTertiary)),
                  ],
                ],
              ),
            ),
          ),
      ],
    ];
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.item, this.detail});
  final ArchiveItem item;
  final ArchiveDetail? detail;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final year = detail?.year ?? item.year;
    final meta = [
      if (year != null) '$year',
      if (detail?.creator != null) detail!.creator!,
    ].join('  ·  ');

    return GlassSurface(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: ClipRRect(
              borderRadius: AppRadii.rMd,
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: PosterArt(
                    imageUrl: item.thumbnailUrl, seed: item.identifier),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(detail?.title ?? item.title, style: text.headlineSmall),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(meta,
                      style: text.labelLarge
                          ?.copyWith(color: AppColors.textSecondary)),
                ],
                const SizedBox(height: AppSpacing.sm),
                Text('Internet Archive · Public Domain',
                    style: text.labelSmall
                        ?.copyWith(color: AppColors.textTertiary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
