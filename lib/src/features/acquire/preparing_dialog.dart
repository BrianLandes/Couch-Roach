import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/acquisition/acquisition.dart';
import '../../theme/theme.dart';

/// A prepared playback: the streamable file plus the library item it was
/// registered as (so the player records watch history / resume).
typedef Prepared = ({String filePath, int? libraryItemId});

/// The shared "getting it ready to play" modal used by every acquire-and-watch
/// flow (Internet Archive browse, and the resolver-sourced not-local play). It
/// runs [prepare] — add the torrent, wait for enough buffer, register a library
/// item — behind a progress bar, then pops [Prepared]; on failure it shows a
/// plain-language reason. Cancelling leaves any download running in the
/// background (it shows up on the Downloads screen).
class PreparingDialog extends StatefulWidget {
  const PreparingDialog({
    super.key,
    required this.subtitle,
    required this.prepare,
    this.retry,
  });

  /// The title being prepared (shown under the heading).
  final String subtitle;

  /// Does the acquisition work. [bindProgress] hands the dialog a 0..1 progress
  /// stream to display — the dialog owns the subscription and cancels it on
  /// dispose, so callers don't have to.
  final Future<Prepared> Function({
    required void Function(Stream<double>) bindProgress,
  }) prepare;

  /// When given, the dialog offers a "Try another source" action (while
  /// preparing and on error) that abandons the current source and re-runs with
  /// this — the next-best torrent. Same shape as [prepare]. Null hides it (e.g.
  /// Internet Archive playback, which has a single source).
  final Future<Prepared> Function({
    required void Function(Stream<double>) bindProgress,
  })? retry;

  @override
  State<PreparingDialog> createState() => _PreparingDialogState();
}

class _PreparingDialogState extends State<PreparingDialog> {
  double _progress = 0;
  String? _error;
  StreamSubscription<double>? _progressSub;

  /// The work currently running — starts as [PreparingDialog.prepare], swaps to
  /// [PreparingDialog.retry] when the user asks for another source.
  late Future<Prepared> Function({
    required void Function(Stream<double>) bindProgress,
  }) _active = widget.prepare;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final prepared = await _active(bindProgress: _bindProgress);
      if (mounted) Navigator.of(context).pop(prepared);
    } on TorrentDaemonException catch (e) {
      // Plain-language reason; the technical detail is already logged upstream.
      _fail(e.userMessage);
    } catch (_) {
      _fail('Something went wrong starting this video. Please try again.');
    }
  }

  /// Discard the current source and re-run with the next-best. Resets the
  /// progress/error state so the dialog shows buffering again.
  void _tryAnother() {
    final retry = widget.retry;
    if (retry == null) return;
    _progressSub?.cancel();
    setState(() {
      _active = retry;
      _error = null;
      _progress = 0;
    });
    _run();
  }

  void _bindProgress(Stream<double> progress) {
    _progressSub?.cancel();
    _progressSub = progress.listen((p) {
      if (mounted) setState(() => _progress = p);
    });
  }

  void _fail(String message) {
    if (mounted) setState(() => _error = message);
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final error = _error;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: GlassSurface(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              error == null ? 'Preparing to play' : 'Playback error',
              style: text.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              widget.subtitle,
              style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (error != null)
              Text(error,
                  style: text.bodyMedium?.copyWith(color: AppColors.danger))
            else ...[
              ClipRRect(
                borderRadius: AppRadii.rSm,
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  minHeight: 8,
                  backgroundColor: AppColors.glassFill,
                  valueColor: const AlwaysStoppedAnimation(AppColors.secondary),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Getting it ready to play…',
                style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (widget.retry != null)
                  TextButton.icon(
                    onPressed: _tryAnother,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Try another source'),
                  ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  autofocus: true,
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(error == null ? 'Cancel' : 'Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
