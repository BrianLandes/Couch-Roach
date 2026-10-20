import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/acquisition/acquisition.dart';
import 'acquire_play.dart';
import 'preparing_dialog.dart' show Prepared;

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

  /// Bumped by every run. A run only touches [state] while it's still the
  /// latest, so a slow run that's been superseded (start → "Choose source…"
  /// while the first source is still buffering) can't overwrite the new run's
  /// progress with its own — or rebind progress to a torrent that was just
  /// removed, which read as a "Downloading nn%" that never moved again.
  int _generation = 0;

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
    await _run((bind) => prepareForPlayback(
          title: title,
          meta: meta,
          season: season,
          episode: episode,
          bindProgress: bind,
        ));
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
  }) =>
      _run((bind) => retryWithNextSource(
            title: title,
            meta: meta,
            season: season,
            episode: episode,
            bindProgress: bind,
          ));

  /// "Use this source" — the user picked a specific candidate from the source
  /// picker. Discards whatever's downloading and prepares the chosen one,
  /// rolling the control through preparing → ready. Allowed from any phase.
  Future<void> chooseSource({
    required TorrentHandle handle,
    required String title,
    required ShowMeta meta,
    int? season,
    int? episode,
  }) =>
      _run((bind) => prepareChosenSource(
            title: title,
            meta: meta,
            season: season,
            episode: episode,
            handle: handle,
            bindProgress: bind,
          ));

  /// Drive one prepare through preparing → ready / failed, binding its live
  /// progress — and ignoring it entirely once a newer run has started.
  Future<void> _run(
      Future<Prepared> Function(void Function(Stream<double>) bind)
          prepare) async {
    final generation = ++_generation;
    bool current() => mounted && generation == _generation;
    await _sub?.cancel();
    _sub = null;
    state = const AcquireState.preparing();
    try {
      final prepared = await prepare((progress) {
        if (!current()) return;
        _sub?.cancel();
        _sub = progress.listen((p) {
          if (current()) state = AcquireState.preparing(progress: p);
        });
      });
      if (!current()) return;
      await _sub?.cancel();
      _sub = null;
      state = AcquireState.ready(
        filePath: prepared.filePath,
        libraryItemId: prepared.libraryItemId,
      );
    } on TorrentDaemonException catch (e) {
      if (current()) state = AcquireState.failed(e.userMessage);
    } catch (_) {
      if (current()) {
        state = const AcquireState.failed(
            'Something went wrong starting this video. Please try again.');
      }
    }
  }

  /// "Stop this" — cancel the in-progress download, remove the torrent + its
  /// partial files, and reset the control to idle (a Download button). Best-
  /// effort: even if the removal fails, the control still returns to idle. Also
  /// retires any run still in flight, so it can't flip the control back.
  Future<void> cancel({
    required String title,
    required ShowMeta meta,
    int? season,
    int? episode,
  }) async {
    final generation = ++_generation;
    await _sub?.cancel();
    _sub = null;
    try {
      await cancelDownload(
          title: title, meta: meta, season: season, episode: episode);
    } catch (_) {
      // Best-effort — still drop the control back to idle below.
    }
    if (mounted && generation == _generation) {
      state = const AcquireState.idle();
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
