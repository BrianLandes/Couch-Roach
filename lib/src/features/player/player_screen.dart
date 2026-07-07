import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/logging/error_log_service.dart';
import '../../data/repositories/watch_history_repository.dart';
import '../../injection.dart';
import '../../theme/theme.dart';

/// Everything the player needs to open a title. Passed via go_router `extra`
/// (file paths don't belong in a URL).
class PlayerArgs {
  const PlayerArgs({
    required this.filePath,
    this.title,
    this.libraryItemId,
    this.startAt = Duration.zero,
  });

  final String filePath;
  final String? title;

  /// When set, the player resumes from and records watch history for this item.
  final int? libraryItemId;

  /// Explicit start position; when zero and [libraryItemId] is set, the saved
  /// resume position is used instead.
  final Duration startAt;
}

/// Embedded libmpv playback surface. Resumes from saved position, persists
/// progress + completion to watch history, and reports errors. Codecs,
/// containers, subtitles, and controls are libmpv's job — we don't build them.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.filePath,
    this.title,
    this.libraryItemId,
    this.startAt = Duration.zero,
  });

  final String filePath;
  final String? title;
  final int? libraryItemId;
  final Duration startAt;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player = Player();

  // Hardware acceleration is disabled: with GPU rendering, some Windows setups
  // decode fine but render a solid-color (e.g. blue) frame. CPU rendering is the
  // reliable path. TODO(perf): expose as a setting and re-try HW accel for
  // high-res content once we can detect the failure.
  late final VideoController _controller = VideoController(
    _player,
    configuration:
        const VideoControllerConfiguration(enableHardwareAcceleration: false),
  );

  WatchHistoryRepository get _history => getIt<WatchHistoryRepository>();

  final List<StreamSubscription<dynamic>> _subs = [];
  int _lastSavedSec = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      var start = widget.startAt;
      final id = widget.libraryItemId;
      if (id != null && start == Duration.zero) {
        final history = await _history.forItem(id);
        if (history != null) {
          start = Duration(seconds: history.resumePositionSec);
        }
      }
      _lastSavedSec = start.inSeconds;

      _subs.add(_player.stream.position.listen(_onPosition));
      _subs.add(_player.stream.completed.listen((done) {
        if (done) _markCompleted();
      }));
      _subs.add(_player.stream.error.listen((message) {
        getIt<ErrorLogService>().logError(
          message,
          source: 'PlayerScreen.mpv(${widget.filePath})',
        );
        if (mounted) setState(() => _error = message);
      }));

      await _player.open(Media(widget.filePath));
      if (start > Duration.zero) {
        await _player.seek(start);
      }
    } catch (e, st) {
      getIt<ErrorLogService>()
          .logError(e, stackTrace: st, source: 'PlayerScreen.open');
      if (mounted) setState(() => _error = '$e');
    }
  }

  // Throttle saves to roughly every 5s of progress so we don't hammer the DB.
  void _onPosition(Duration pos) {
    final id = widget.libraryItemId;
    if (id == null) return;
    if ((pos.inSeconds - _lastSavedSec).abs() < 5) return;
    _lastSavedSec = pos.inSeconds;
    _history.record(
      libraryItemId: id,
      position: pos,
      duration: _player.state.duration,
    );
  }

  void _markCompleted() {
    final id = widget.libraryItemId;
    if (id == null) return;
    _history.record(
      libraryItemId: id,
      position: Duration.zero,
      duration: _player.state.duration,
      completed: true,
    );
  }

  // Save the final position on exit; count "watched to the end" (>= 95%) as
  // completed so the reaper and Continue Watching treat it right.
  void _persistFinal() {
    final id = widget.libraryItemId;
    if (id == null) return;
    final pos = _player.state.position;
    final dur = _player.state.duration;
    final nearEnd = dur.inSeconds > 0 && pos.inSeconds >= dur.inSeconds * 0.95;
    _history.record(
      libraryItemId: id,
      position: pos,
      duration: dur,
      completed: nearEnd,
    );
  }

  @override
  void dispose() {
    _persistFinal();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  void _back() {
    if (context.canPop()) context.pop();
  }

  /// Controls theme with a back button in the top bar so it fades in/out with
  /// the rest of the player UI.
  MaterialDesktopVideoControlsThemeData _controlsTheme() {
    return MaterialDesktopVideoControlsThemeData(
      topButtonBar: [
        IconButton(
          onPressed: _back,
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          tooltip: 'Back',
        ),
        if (widget.title != null)
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.sm),
            child: Text(
              widget.title!,
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: _error != null
                ? _PlaybackError(title: widget.title, message: _error!)
                : MaterialDesktopVideoControlsTheme(
                    normal: _controlsTheme(),
                    fullscreen: _controlsTheme(),
                    child: Video(
                      controller: _controller,
                      controls: MaterialDesktopVideoControls,
                    ),
                  ),
          ),
          // On the error screen there are no fading controls, so keep a back
          // button reachable.
          if (_error != null)
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: AppColors.scrim,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: _back,
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: 'Back',
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlaybackError extends StatelessWidget {
  const _PlaybackError({required this.message, this.title});
  final String? title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 44, color: AppColors.danger),
            const SizedBox(height: AppSpacing.md),
            Text(
              title == null ? "Couldn't play this file" : 'Couldn\'t play "$title"',
              style: text.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
