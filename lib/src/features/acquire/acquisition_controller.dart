import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/acquisition/acquisition.dart';
import 'acquire_play.dart';

/// Where an inline Download control is in its lifecycle.
enum AcquirePhase { idle, preparing, ready, failed }

/// Immutable state of one title's inline acquisition. Drives the Download →
/// progress bar → Play control on the detail screens.
class AcquireState {
  const AcquireState._(
    this.phase, {
    this.progress,
    this.filePath,
    this.libraryItemId,
    this.error,
  });

  const AcquireState.idle() : this._(AcquirePhase.idle);
  const AcquireState.preparing({double? progress})
      : this._(AcquirePhase.preparing, progress: progress);
  const AcquireState.ready({required String filePath, int? libraryItemId})
      : this._(AcquirePhase.ready,
            filePath: filePath, libraryItemId: libraryItemId);
  const AcquireState.failed(String error)
      : this._(AcquirePhase.failed, error: error);

  final AcquirePhase phase;

  /// 0..1 while [AcquirePhase.preparing]; null before the torrent exists
  /// (resolving/adding) → show an indeterminate bar.
  final double? progress;

  /// The streamable file, set on [AcquirePhase.ready].
  final String? filePath;
  final int? libraryItemId;
  final String? error;
}

/// Owns one title's non-blocking acquisition: on [start] it prepares the title
/// for playback in the background (reattaching to a running download if there is
/// one) and streams progress into [state], ending at [AcquirePhase.ready] with
/// the file to play — or [AcquirePhase.failed]. Kept alive for the session so a
/// download keeps progressing while the user navigates away and back.
class AcquisitionController extends StateNotifier<AcquireState> {
  AcquisitionController() : super(const AcquireState.idle());

  StreamSubscription<double>? _sub;

  Future<void> start({
    required String title,
    required ShowMeta meta,
    int? season,
    int? episode,
  }) async {
    // Already working or done — don't kick a second run (start() is also called
    // by auto-adopt when a running download is detected).
    if (state.phase == AcquirePhase.preparing ||
        state.phase == AcquirePhase.ready) {
      return;
    }
    state = const AcquireState.preparing();
    try {
      final prepared = await prepareForPlayback(
        title: title,
        meta: meta,
        season: season,
        episode: episode,
        bindProgress: (progress) {
          _sub?.cancel();
          _sub = progress.listen((p) {
            if (mounted) state = AcquireState.preparing(progress: p);
          });
        },
      );
      await _sub?.cancel();
      if (mounted) {
        state = AcquireState.ready(
          filePath: prepared.filePath,
          libraryItemId: prepared.libraryItemId,
        );
      }
    } on TorrentDaemonException catch (e) {
      if (mounted) state = AcquireState.failed(e.userMessage);
    } catch (_) {
      if (mounted) {
        state = const AcquireState.failed(
            'Something went wrong starting this video. Please try again.');
      }
    }
  }

  /// "This torrent didn't work" — abandon the current source and prepare the
  /// next-best one, rolling the control back through preparing → ready. Unlike
  /// [start], allowed from any phase (the user hits it while preparing or once
  /// it's ready but bad).
  Future<void> retry({
    required String title,
    required ShowMeta meta,
    int? season,
    int? episode,
  }) async {
    await _sub?.cancel();
    state = const AcquireState.preparing();
    try {
      final prepared = await retryWithNextSource(
        title: title,
        meta: meta,
        season: season,
        episode: episode,
        bindProgress: (progress) {
          _sub?.cancel();
          _sub = progress.listen((p) {
            if (mounted) state = AcquireState.preparing(progress: p);
          });
        },
      );
      await _sub?.cancel();
      if (mounted) {
        state = AcquireState.ready(
          filePath: prepared.filePath,
          libraryItemId: prepared.libraryItemId,
        );
      }
    } on TorrentDaemonException catch (e) {
      if (mounted) state = AcquireState.failed(e.userMessage);
    } catch (_) {
      if (mounted) {
        state = const AcquireState.failed(
            'Something went wrong starting this video. Please try again.');
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// One controller per title/episode, keyed by its [acquisitionDedupeKey]. Not
/// autoDispose: a download keeps preparing (and the Play state survives) while
/// the user navigates around during the session.
final acquisitionControllerProvider = StateNotifierProvider.family<
    AcquisitionController, AcquireState, String>((ref, dedupeKey) {
  return AcquisitionController();
});
