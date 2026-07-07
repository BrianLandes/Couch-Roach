import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Embedded libmpv playback surface. Opens a local (or streamed) file, seeks to
/// a resume position, and reports position/completion back via callbacks so the
/// caller can persist watch history (HANDOFF §4.4).
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.filePath,
    this.startAt = Duration.zero,
    this.onProgress,
    this.onCompleted,
  });

  final String filePath;
  final Duration startAt;

  /// Called periodically and on pause/exit with the latest position + duration.
  final void Function(Duration position, Duration duration)? onProgress;

  /// Called when playback reaches (near) the end.
  final VoidCallback? onCompleted;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    _player.stream.position.listen((pos) {
      widget.onProgress?.call(pos, _player.state.duration);
    });
    _player.stream.completed.listen((done) {
      if (done) widget.onCompleted?.call();
    });

    await _player.open(Media(widget.filePath));
    if (widget.startAt > Duration.zero) {
      await _player.seek(widget.startAt);
    }
  }

  @override
  void dispose() {
    // Report final position before tearing down so resume is accurate.
    widget.onProgress?.call(_player.state.position, _player.state.duration);
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Video(controller: _controller),
    );
  }
}
