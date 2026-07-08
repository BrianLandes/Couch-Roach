import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/config/app_config.dart';
import '../../core/logging/error_log_service.dart';
import '../../core/media/ytdlp.dart';
import '../../core/settings/settings_service.dart';
import '../../data/repositories/watch_history_repository.dart';
import '../../injection.dart';
import '../../services/subtitles/subtitle_service.dart';
import '../../services/subtitles/subtitle_skip_check.dart';
import '../../theme/theme.dart';
import '../../widgets/fullscreen_toggle_button.dart';

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
  // True when the source is a network URL (a YouTube trailer resolved through
  // yt-dlp), as opposed to a local library file. Gates the ytdl_hook wiring and
  // verbose mpv logging below.
  late final bool _isNetworkSource = _isNetworkUrl(widget.filePath);

  late final Player _player = Player(
    configuration: PlayerConfiguration(
      // On the trailer path, raise mpv's own logging and (below) mirror it into
      // our file log. A crash in libmpv's yt-dlp/ytdl_hook resolve pipeline is
      // native — it never surfaces as a Dart exception — so the file log (which
      // survives the crash) is the only trail we get. `v` over `debug` on
      // purpose: our log writer appends asynchronously, and debug's flood would
      // leave the crash-adjacent lines queued (unwritten) when the process dies.
      logLevel: _isNetworkSource ? MPVLogLevel.v : MPVLogLevel.error,
    ),
  );

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
  // We auto-select the best (most-channels) audio track once, on the first
  // tracks update. After that the user is free to change it from the mpv menu
  // and we won't override their choice.
  bool _audioAutoSelected = false;
  // Resume target applied on the first position tick — seeking right after
  // open() is dropped because libmpv isn't ready to seek yet.
  Duration? _pendingSeek;
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
        if (history != null && history.resumePositionSec > 0) {
          start = Duration(seconds: history.resumePositionSec);
          getIt<ErrorLogService>().info(
            'Resuming "${widget.title}" at ${start.inSeconds}s',
            source: 'PlayerScreen',
          );
        }
      }
      _lastSavedSec = start.inSeconds;
      _pendingSeek = start > Duration.zero ? start : null;

      _subs.add(_player.stream.position.listen(_onPosition));
      _subs.add(_player.stream.tracks.listen(_onTracks));
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

      // Mirror libmpv's own log into our file log for network/trailer playback.
      // A crash in the yt-dlp/ytdl_hook resolve pipeline is native and leaves
      // nothing in the Dart error stream, so these lines are the trail up to it.
      if (_isNetworkSource) {
        _subs.add(_player.stream.log.listen((l) {
          getIt<ErrorLogService>().info(
            '[mpv ${l.level}] ${l.prefix}: ${l.text.trim()}',
            source: 'PlayerScreen.mpv',
          );
        }));
      }

      // For a network URL (a YouTube trailer), point libmpv's ytdl_hook at the
      // bundled yt-dlp so it can resolve the stream — it only searches PATH, not
      // the app directory. No-op for local files and when yt-dlp isn't bundled
      // (libmpv then falls back to a PATH lookup / its graceful error state).
      await _configureYtdlp();

      // Seek is applied on the first ready position tick (see _onPosition).
      await _player.open(Media(widget.filePath));

      // Playback has started — fetch English subtitles in the background and
      // load them into the running player if they arrive. Never blocks play.
      unawaited(_ensureSubtitles());
    } catch (e, st) {
      getIt<ErrorLogService>()
          .logError(e, stackTrace: st, source: 'PlayerScreen.open');
      if (mounted) setState(() => _error = '$e');
    }
  }

  static bool _isNetworkUrl(String path) {
    final uri = Uri.tryParse(path);
    return uri != null && (uri.isScheme('http') || uri.isScheme('https'));
  }

  /// Prepare libmpv to resolve a network URL (a trailer) through yt-dlp. Only
  /// runs for network sources; any failure is logged and swallowed so it never
  /// blocks playback (a missing/failed resolve surfaces as the player's own
  /// error state). No-op for local files.
  Future<void> _configureYtdlp() async {
    if (!_isNetworkSource) return;
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    try {
      // Point mpv's builtin ytdl_hook at the bundled yt-dlp (it only searches
      // PATH, not the app dir). Null when yt-dlp isn't bundled — leave mpv's
      // default PATH lookup in place for dev machines that have it installed.
      final scriptOpt = ytdlHookScriptOpt();
      if (scriptOpt != null) {
        await platform.setProperty('script-opts', scriptOpt);
      }
      // Force a single pre-muxed stream. mpv's default for YouTube pulls
      // *separate* best-video + best-audio and stitches them with an internal
      // `edl://` — a fragile path in libmpv that can hard-crash the process. A
      // muxed 'best' avoids the merge entirely (YouTube muxed formats cap around
      // 720p, which is plenty for an inline trailer).
      await platform.setProperty('ytdl-format', 'best');
    } catch (e, st) {
      getIt<ErrorLogService>()
          .logError(e, stackTrace: st, source: 'PlayerScreen.configureYtdlp');
    }
  }

  /// Ask the subtitle service for an English track (skip-check → search →
  /// download → `<name>.en.srt`), then make sure an English subtitle is
  /// actually *selected* for display: an already-present track (embedded, or a
  /// sidecar libmpv auto-loaded) is switched on if it isn't already, otherwise
  /// the freshly-downloaded sidecar is loaded + selected. Best-effort; a failure
  /// here never disrupts playback.
  Future<void> _ensureSubtitles() async {
    final log = getIt<ErrorLogService>();
    // Only real library titles get subtitle fetching — trailers and other
    // ad-hoc streams have no library item (and no local file to hash/search).
    if (widget.libraryItemId == null) {
      log.info('subtitles skipped: no library item (trailer/ad-hoc stream)',
          source: 'PlayerScreen.ensureSubtitles');
      return;
    }
    if (!const AppConfig().hasOpenSubtitlesKey) {
      log.info('subtitles skipped: no OpenSubtitles API key configured',
          source: 'PlayerScreen.ensureSubtitles');
      return;
    }
    if (!getIt<SettingsService>().autoDownloadSubtitles) {
      log.info('subtitles skipped: auto-download disabled in settings',
          source: 'PlayerScreen.ensureSubtitles');
      return;
    }
    try {
      log.info('ensuring English subtitles for ${widget.filePath}',
          source: 'PlayerScreen.ensureSubtitles');
      final srtPath =
          await getIt<SubtitleService>().ensureEnglish(widget.filePath);
      if (!mounted) return;

      // If libmpv already exposes an English track — an embedded stream, or a
      // sidecar it auto-loaded — select it if it isn't the active one. mpv
      // won't necessarily display it on its own, so we turn it on explicitly.
      final existing = _player.state.tracks.subtitle
          .where((s) => SubtitleSkipCheck.isEnglish(s.language, s.title))
          .toList();
      if (existing.isNotEmpty) {
        final track = existing.first;
        if (_player.state.track.subtitle.id != track.id) {
          await _player.setSubtitleTrack(track);
          log.info('Enabled existing English subtitle track ${track.id}',
              source: 'PlayerScreen.ensureSubtitles');
        } else {
          log.info('English subtitle track ${track.id} already selected',
              source: 'PlayerScreen.ensureSubtitles');
        }
        return;
      }

      if (srtPath == null) {
        log.info('no English subtitles available (none found or downloaded)',
            source: 'PlayerScreen.ensureSubtitles');
        return;
      }

      await _player.setSubtitleTrack(
        SubtitleTrack.uri(srtPath, title: 'English', language: 'en'),
      );
      log.info('Loaded + selected English subtitles: $srtPath',
          source: 'PlayerScreen.ensureSubtitles');
    } catch (e, st) {
      log.logError(e, stackTrace: st, source: 'PlayerScreen.ensureSubtitles');
    }
  }

  void _onPosition(Duration pos) {
    // Apply the resume seek once the player is actually running and knows the
    // duration — doing it earlier (right after open) is silently dropped.
    final seek = _pendingSeek;
    if (seek != null && _player.state.duration > Duration.zero) {
      _pendingSeek = null;
      _lastSavedSec = seek.inSeconds;
      _player.seek(seek);
      return;
    }

    // Throttle saves to roughly every 5s of progress so we don't hammer the DB.
    final id = widget.libraryItemId;
    if (id == null || _pendingSeek != null) return;
    if ((pos.inSeconds - _lastSavedSec).abs() < 5) return;
    _lastSavedSec = pos.inSeconds;
    _history.record(
      libraryItemId: id,
      position: pos,
      duration: _player.state.duration,
    );
  }

  // When multiple audio tracks exist, prefer the one with the most channels so
  // a surround mix (5.1/7.1) wins over a stereo downmix. Runs once per open;
  // afterwards the user's manual track choice is respected.
  void _onTracks(Tracks tracks) {
    if (_audioAutoSelected) return;
    // Respect the user's preference — leave mpv's default audio track as-is.
    if (!getIt<SettingsService>().preferSurroundAudio) return;

    // Only real, selectable tracks — skip the synthetic "auto"/"no" entries.
    final selectable = tracks.audio
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    if (selectable.length < 2) return;

    // Channel counts aren't populated until libmpv has probed the streams; wait
    // for a later update if none of them report a count yet.
    final anyKnown = selectable.any((t) => _channelCount(t) > 0);
    if (!anyKnown) return;

    _audioAutoSelected = true;

    final best = selectable.reduce((a, b) {
      final ca = _channelCount(a);
      final cb = _channelCount(b);
      if (ca != cb) return ca > cb ? a : b;
      // Equal channels: keep libmpv's default so we don't reorder needlessly.
      if (a.isDefault == true && b.isDefault != true) return a;
      return b.isDefault == true ? b : a;
    });

    // Nothing to do if the widest track is already what mpv picked by default.
    if (best.id == _player.state.track.audio.id) return;

    _player.setAudioTrack(best);
    getIt<ErrorLogService>().info(
      'Selected surround audio track ${best.id} '
      '(${_channelCount(best)}ch, ${best.channels ?? best.language ?? '?'})',
      source: 'PlayerScreen',
    );
  }

  // libmpv exposes the channel count on either field depending on the container;
  // take whichever is larger, defaulting to 0 (unknown) so it never wins a tie.
  int _channelCount(AudioTrack t) {
    final a = t.channelscount ?? 0;
    final b = t.audiochannels ?? 0;
    return a > b ? a : b;
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

  /// Controls theme: back button in the top bar (fades with the UI), and a
  /// fullscreen button that drives the OS window fullscreen (window_manager) so
  /// it's in sync with how the app launches. media_kit's own fullscreen
  /// (double-press + its button) is disabled to avoid a competing system.
  MaterialDesktopVideoControlsThemeData _controlsTheme() {
    return MaterialDesktopVideoControlsThemeData(
      toggleFullscreenOnDoublePress: false,
      // Hide the mouse pointer together with the controls when they fade out, so
      // a fullscreen TV appliance shows nothing over the video while playing.
      hideMouseOnControlsRemoval: true,
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
      bottomButtonBar: const [
        MaterialDesktopPlayOrPauseButton(),
        MaterialDesktopVolumeButton(),
        MaterialDesktopPositionIndicator(),
        Spacer(),
        FullscreenToggleButton(color: Colors.white, iconSize: 28),
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
