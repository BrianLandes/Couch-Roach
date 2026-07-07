import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/logging/error_log_service.dart';
import '../../injection.dart';
import '../../theme/theme.dart';

/// Everything the player needs to open a title. Passed via go_router `extra`
/// (file paths don't belong in a URL).
class PlayerArgs {
  const PlayerArgs({
    required this.filePath,
    this.title,
    this.startAt = Duration.zero,
  });

  final String filePath;
  final String? title;
  final Duration startAt;
}

/// Embedded libmpv playback surface. Opens a local (or later streamed) file,
/// seeks to a resume position, and reports position/completion via callbacks so
/// the caller can persist watch history (wired in the resume-tracking task).
/// Codecs/containers/subtitles/controls are libmpv's job — we don't build them.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.filePath,
    this.title,
    this.startAt = Duration.zero,
    this.onProgress,
    this.onCompleted,
  });

  final String filePath;
  final String? title;
  final Duration startAt;

  /// Called with the latest position + duration (on tick and on exit).
  final void Function(Duration position, Duration duration)? onProgress;

  /// Called when playback reaches (near) the end.
  final VoidCallback? onCompleted;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player = Player();

  // Hardware acceleration is disabled: with GPU rendering, some Windows setups
  // decode fine but render a solid-color (e.g. blue) frame. CPU rendering is the
  // reliable path. TODO(perf): expose this as a setting and re-try HW accel for
  // high-res content once we can detect the failure.
  late final VideoController _controller = VideoController(
    _player,
    configuration:
        const VideoControllerConfiguration(enableHardwareAcceleration: false),
  );

  final List<StreamSubscription<dynamic>> _subs = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      _subs.add(_player.stream.position.listen(
        (pos) => widget.onProgress?.call(pos, _player.state.duration),
      ));
      _subs.add(_player.stream.completed.listen((done) {
        if (done) widget.onCompleted?.call();
      }));
      _subs.add(_player.stream.error.listen((message) {
        getIt<ErrorLogService>().logError(
          message,
          source: 'PlayerScreen.mpv(${widget.filePath})',
        );
        if (mounted) setState(() => _error = message);
      }));

      await _player.open(Media(widget.filePath));
      if (widget.startAt > Duration.zero) {
        await _player.seek(widget.startAt);
      }
    } catch (e, st) {
      getIt<ErrorLogService>()
          .logError(e, stackTrace: st, source: 'PlayerScreen.open');
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    // Report final position before tearing down so resume is accurate.
    widget.onProgress?.call(_player.state.position, _player.state.duration);
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
