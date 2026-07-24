import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
// Hide media_kit's own `toggleFullscreen` — we drive fullscreen through
// window_manager (window_service.toggleFullscreen), the app's single source of
// truth, to avoid two competing fullscreen systems.
import 'package:media_kit_video/media_kit_video.dart' hide toggleFullscreen;

import '../../core/config/app_config.dart';
import '../../core/logging/error_log_service.dart';
import '../../core/media/ytdlp.dart';
import '../../core/platform/open_url.dart';
import '../../core/media/ytdlp_resolver.dart';
import '../../core/settings/settings_service.dart';
import '../../core/window/window_service.dart';
import '../../data/db/database.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/watch_history_repository.dart';
import '../../injection.dart';
import '../../router/app_router.dart';
import '../../services/acquisition/acquisition.dart';
import '../../services/discovery/tmdb_client.dart';
import '../../services/subtitles/subtitle_service.dart';
import '../../services/subtitles/subtitle_skip_check.dart';
import '../../theme/theme.dart';
import '../../widgets/fullscreen_toggle_button.dart';
import '../acquire/acquire_play.dart';
import '../cast/cast_dialog.dart';
import 'audio_selection.dart';
import 'next_episode.dart';
import 'next_episode_button.dart';
import 'player_title.dart';
import 'subtitle_label.dart';

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

  // Hardware video decoding (libmpv `hwdec`) is user-controlled: it offloads a
  // weak CPU when the box has a working iGPU, but on some setups it decodes fine
  // yet renders a solid-color (e.g. blue) frame — so it defaults OFF and is a
  // Settings toggle the user can flip on to try it on their hardware.
  late final VideoController _controller = VideoController(
    _player,
    configuration: VideoControllerConfiguration(
      enableHardwareAcceleration:
          getIt<SettingsService>().hardwareVideoAcceleration,
    ),
  );

  WatchHistoryRepository get _history => getIt<WatchHistoryRepository>();
  LibraryRepository get _library => getIt<LibraryRepository>();

  final List<StreamSubscription<dynamic>> _subs = [];
  int _lastSavedSec = 0;
  // We auto-select an audio track once, on the first tracks update (prefer
  // English, then the widest layout). After that the user is free to change it
  // from the right-click "Audio" menu and we won't override their choice.
  bool _audioAutoSelected = false;
  // Audio tracks libmpv exposes and the active one, mirrored from the player
  // streams so the right-click "Audio" menu lists the real, current options.
  List<AudioTrack> _audioTracks = const [];
  AudioTrack _selectedAudio = AudioTrack.auto();
  // Resume target applied on the first position tick — seeking right after
  // open() is dropped because libmpv isn't ready to seek yet.
  Duration? _pendingSeek;
  String? _error;

  // The library row for the playing file (show/season/episode) — drives
  // prefetching and auto-playing the next episode. Loaded in _open().
  LibraryItem? _currentItem;
  // The title shown in the player's top bar. Composed from _currentItem once it
  // loads (clean show name + SxxExx, then + the episode name when TMDB answers;
  // a movie is just its clean name) so it's consistent regardless of what the
  // call site passed. Falls back to widget.title until then.
  String? _displayTitle;
  String? _episodeName;
  // Prefetch of the next episode fires once, partway through.
  bool _prefetchedNext = false;
  // The persistent bottom-right "Next Episode" button, resolved once after open.
  // `_nextEpisode` is the (season, episode) that follows this one — null when
  // this isn't a TV episode or nothing comes after. `_nextLocalItem` is that
  // episode's library row when it's already downloaded (→ "Play Next Episode");
  // null means it's still to fetch. `_nextDownloadRequested` gives the button
  // immediate feedback after a tap, until the daemon reports the new download.
  (int, int)? _nextEpisode;
  String? _nextShowName;
  int? _nextTmdbId;
  LibraryItem? _nextLocalItem;
  bool _nextDownloadRequested = false;
  // Guards the on-completion auto-advance so it fires at most once per player.
  bool _autoAdvanced = false;

  // Mirror the media_kit controls' auto-hide so the "Next Episode" button fades
  // in and out together with them: any pointer activity reveals it, and 3s of
  // stillness hides it — matching the controls' default `controlsHoverDuration`
  // (3s) and `controlsTransitionDuration` (150ms) so the two move in lockstep.
  bool _controlsVisible = false;
  Timer? _controlsHideTimer;
  static const _controlsHideDelay = Duration(seconds: 3);
  static const _controlsFade = Duration(milliseconds: 150);
  // Mirrors mpv's play state. While paused/ended we keep the overlay up (as
  // media_kit does with its own controls) instead of idle-hiding it — otherwise
  // the back/next buttons vanish at the end of a show and a remote (which emits
  // key events, not pointer moves) has no way to bring them back.
  bool _isPlaying = true;

  bool get _isTvEpisode =>
      _currentItem?.mediaType == 'tv' &&
      _currentItem?.tmdbId != null &&
      _currentItem?.season != null &&
      _currentItem?.episode != null;

  // Subtitle tracks libmpv currently exposes (embedded streams + anything we've
  // loaded) and the active one, mirrored from the player streams so the
  // right-click "Subtitles" menu always lists the real, current options.
  List<SubtitleTrack> _subtitleTracks = const [];
  SubtitleTrack _selectedSubtitle = const SubtitleTrack('auto', null, null);
  final MenuController _subtitleMenuController = MenuController();

  // True while a manual (right-click) subtitle download is in flight — guards
  // against double-runs and drives the menu item's "Downloading…" label.
  bool _subtitlesDownloading = false;

  // Temp dir holding a trailer's downloaded caption sidecar (YouTube captions,
  // fetched via yt-dlp since the resolved direct stream carries none). Cleaned
  // up on dispose.
  Directory? _trailerSubDir;

  // Per-title subtitle timing offset (ms), applied as mpv `sub-delay` and
  // persisted on the library row so a re-watch stays corrected. Range is
  // clamped to ±10s in the editor.
  int _subtitleOffsetMs = 0;
  static const _subtitleOffsetLimit = 10000;

  @override
  void initState() {
    super.initState();
    // Observe keys globally (not via a focus node) so a remote/keyboard reveals
    // the overlay without stealing focus or key handling from the media_kit
    // controls (Space / media-key play-pause, arrow-seek).
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    _open();
  }

  /// Any physical key press counts as activity and reveals the overlay. Returns
  /// false so the event is never consumed — it still reaches the player controls
  /// (this is an observer, not a handler).
  bool _onHardwareKey(KeyEvent event) {
    if (mounted && (event is KeyDownEvent || event is KeyRepeatEvent)) {
      _revealControls();
    }
    return false;
  }

  Future<void> _open() async {
    try {
      var start = widget.startAt;
      final id = widget.libraryItemId;
      if (id != null) {
        final item = await _library.findById(id);
        _currentItem = item;
        _subtitleOffsetMs = item?.subtitleOffsetMs ?? 0;
        // Compose the fullest title from the row now (show + SxxExx, or a clean
        // movie name); the episode name is added later by _loadCreditsMeta.
        _refreshDisplayTitle();
        if (start == Duration.zero) {
          final history = await _history.forItem(id);
          if (history != null && history.resumePositionSec > 0) {
            start = Duration(seconds: history.resumePositionSec);
            getIt<ErrorLogService>().info(
              'Resuming "${widget.title}" at ${start.inSeconds}s',
              source: 'PlayerScreen',
            );
          }
        }
      }
      _lastSavedSec = start.inSeconds;
      _pendingSeek = start > Duration.zero ? start : null;

      _subs.add(_player.stream.position.listen(_onPosition));
      _subs.add(_player.stream.tracks.listen(_onTracks));
      _subs.add(_player.stream.track.listen((t) {
        if (mounted) {
          setState(() {
            _selectedSubtitle = t.subtitle;
            _selectedAudio = t.audio;
          });
        }
      }));
      _subs.add(_player.stream.completed.listen((done) {
        if (done) {
          _markCompleted();
          _maybeAutoAdvance();
        }
      }));
      // Track play state so the overlay stays up while paused/ended.
      _subs.add(_player.stream.playing.listen(_onPlayingChanged));

      // Enrich the top-bar title with the episode's TMDB name for a local TV
      // episode ("Show — S01E03 · Episode Name"). Best-effort.
      if (_isTvEpisode && !_isNetworkSource) {
        unawaited(_loadEpisodeName());
      }
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

      // Configure the fallback ytdl_hook path (see _configureYtdlp) in case
      // self-resolution below fails but a Lua-enabled libmpv is present.
      await _configureYtdlp();
      await _configureLowPower();

      // For a network URL (a YouTube trailer), resolve the direct stream URL
      // ourselves with the bundled yt-dlp — media_kit's Windows libmpv has no
      // ytdl_hook (built without Lua), so the raw watch URL never gets rewritten
      // and mpv fails to demux it. Falls back to the raw URL when resolution
      // isn't possible (relying on ytdl_hook where it does exist, e.g. Linux).
      final mediaUrl = await _resolveMediaUrl(widget.filePath);

      // Seek is applied on the first ready position tick (see _onPosition).
      await _player.open(Media(mediaUrl));

      // Re-apply the saved subtitle timing offset for this title (no-op at 0).
      if (_subtitleOffsetMs != 0) unawaited(_applySubtitleDelay(_subtitleOffsetMs));

      // Playback has started — fetch English subtitles in the background and
      // load them into the running player if they arrive. Never blocks play.
      // Library titles pull from OpenSubtitles; a trailer pulls YouTube captions
      // via yt-dlp (the resolved direct stream has none of its own).
      unawaited(_isNetworkSource ? _ensureTrailerSubtitles() : _ensureSubtitles());

      // Resolve the following episode (and whether it's already local) so the
      // bottom-right "Next Episode" button can appear. Best-effort, off the UI.
      if (_isTvEpisode) unawaited(_resolveNextEpisode());
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

  /// Low-power decode tuning for underpowered boxes (Settings → Playback):
  /// skip the deblocking loop filter on non-keyframes and use cheap bilinear
  /// scaling. Cuts CPU noticeably for a small quality hit; best-effort and never
  /// blocks playback. No-op when the setting is off.
  Future<void> _configureLowPower() async {
    if (!getIt<SettingsService>().lowPowerVideo) return;
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    try {
      await platform.setProperty('vd-lavc-fast', 'yes');
      await platform.setProperty('vd-lavc-skiploopfilter', 'nonkey');
      await platform.setProperty('scale', 'bilinear');
      await platform.setProperty('dscale', 'bilinear');
      await platform.setProperty('cscale', 'bilinear');
      await platform.setProperty('dither', 'no');
    } catch (e, st) {
      getIt<ErrorLogService>()
          .logError(e, stackTrace: st, source: 'PlayerScreen.lowPower');
    }
  }

  /// Configure libmpv's builtin `ytdl_hook` as the **fallback** resolver for a
  /// network URL — used only when our own yt-dlp resolution ([_resolveMediaUrl])
  /// fails but a Lua-enabled libmpv is present (e.g. a system libmpv on Linux).
  /// Only runs for network sources; failures are logged and swallowed. No-op for
  /// local files.
  Future<void> _configureYtdlp() async {
    if (!_isNetworkSource) return;
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    try {
      // libmpv defaults `ytdl` to *no* (only the mpv CLI defaults it to yes), so
      // the hook never runs unless we ask for it.
      await platform.setProperty('ytdl', 'yes');
      // Point the hook at the bundled yt-dlp (it only searches PATH, not the app
      // dir). Null when yt-dlp isn't bundled — leave mpv's default PATH lookup in
      // place for dev machines that have it installed.
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

  /// The URL to actually hand mpv. Local files pass through untouched. For a
  /// network URL (a trailer), resolve the direct stream with the bundled yt-dlp
  /// and apply the headers it reports — because media_kit's Windows libmpv can't
  /// resolve it itself. On any resolution failure, fall back to the raw URL
  /// (which plays where `ytdl_hook` exists; else surfaces mpv's own error state).
  Future<String> _resolveMediaUrl(String path) async {
    if (!_isNetworkSource) return path;
    final log = getIt<ErrorLogService>();
    final resolved = await resolveNetworkStream(path);
    if (resolved == null) {
      log.info('yt-dlp could not resolve "$path" — opening it raw (needs a '
          'ytdl_hook-capable libmpv)', source: 'PlayerScreen.resolveMedia');
      return path;
    }
    await _applyStreamHeaders(resolved.headers);
    log.info('resolved trailer stream via yt-dlp', source: 'PlayerScreen.resolveMedia');
    return resolved.url;
  }

  /// Match yt-dlp's User-Agent for a resolved stream, via mpv's `user-agent`.
  /// A googlevideo URL is signed and self-contained (it fetches without any
  /// special header), but some clients' URLs are UA-sensitive, so setting the
  /// exact UA yt-dlp used is a cheap safeguard. We deliberately skip the other
  /// reported headers: mpv's `http-header-fields` is a comma-separated list and
  /// values like `Accept` contain commas, which would corrupt the list.
  /// Best-effort — a failure is logged, never fatal.
  Future<void> _applyStreamHeaders(Map<String, String> headers) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    final ua = headers['User-Agent'] ?? headers['user-agent'];
    if (ua == null || ua.isEmpty) return;
    try {
      await platform.setProperty('user-agent', ua);
    } catch (e, st) {
      getIt<ErrorLogService>()
          .logError(e, stackTrace: st, source: 'PlayerScreen.streamHeaders');
    }
  }

  /// Auto-fetch on open: fetch + select English subtitles, but only when a real
  /// library title, an OpenSubtitles key, and the auto-download setting all
  /// allow it. When auto-download is off the user can still trigger it by hand
  /// from the right-click menu ([_manualDownloadSubtitles]).
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
    log.info('ensuring English subtitles for ${widget.filePath}',
        source: 'PlayerScreen.ensureSubtitles');
    await _downloadAndSelectEnglish();
  }

  /// Fetch a trailer's English captions from YouTube (via the bundled yt-dlp)
  /// and load them into the player. The resolved direct stream carries no
  /// captions of its own, so this is the only way a trailer gets subtitles.
  /// Honors the same auto-download setting as library titles; best-effort and
  /// off the play path. The sidecar lands in a temp dir cleaned up on dispose.
  Future<void> _ensureTrailerSubtitles() async {
    if (!_isNetworkSource) return;
    if (!getIt<SettingsService>().autoDownloadSubtitles) return;
    final log = getIt<ErrorLogService>();
    try {
      final dir = await Directory.systemTemp.createTemp('cr_trailer_sub');
      _trailerSubDir = dir;
      final sub = await fetchNetworkSubtitle(widget.filePath, destDir: dir.path);
      if (sub == null) {
        log.info('no captions available for trailer ${widget.filePath}',
            source: 'PlayerScreen.trailerSubs');
        return;
      }
      if (!mounted) return;
      await _player.setSubtitleTrack(
        SubtitleTrack.uri(sub, title: 'English', language: 'en'),
      );
      log.info('loaded trailer captions: $sub',
          source: 'PlayerScreen.trailerSubs');
    } catch (e, st) {
      log.logError(e, stackTrace: st, source: 'PlayerScreen.trailerSubs');
    }
  }

  /// Manual trigger from the right-click menu — the escape hatch when
  /// auto-download is off (or found nothing). Same fetch as [_ensureSubtitles]
  /// but bypasses the auto-download setting, guards against double-runs, and
  /// reports the outcome to the user via a snackbar.
  Future<void> _manualDownloadSubtitles() async {
    _subtitleMenuController.close();
    final messenger = ScaffoldMessenger.of(context);
    if (widget.libraryItemId == null) {
      messenger.showSnackBar(const SnackBar(
          content: Text("Subtitles aren't available for this stream.")));
      return;
    }
    if (!const AppConfig().hasOpenSubtitlesKey) {
      messenger.showSnackBar(const SnackBar(
          content: Text('No OpenSubtitles API key is configured.')));
      return;
    }
    if (_subtitlesDownloading) return;
    setState(() => _subtitlesDownloading = true);
    messenger.showSnackBar(const SnackBar(
        content: Text('Searching for English subtitles…')));

    final result = await _downloadAndSelectEnglish();
    if (!mounted) return;
    setState(() => _subtitlesDownloading = false);

    final message = switch (result) {
      _SubtitleFetchResult.downloaded =>
        'English subtitles downloaded and turned on.',
      _SubtitleFetchResult.selectedExisting =>
        'Turned on the English subtitles.',
      _SubtitleFetchResult.none => 'No English subtitles found for this title.',
      _SubtitleFetchResult.error =>
        "Couldn't download subtitles — see the error log.",
    };
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  /// Ask the subtitle service for an English track (skip-check → search →
  /// download → `<name>.en.srt`), then make sure an English subtitle is actually
  /// *selected* for display: an already-present track (embedded, or a sidecar
  /// libmpv auto-loaded) is switched on if it isn't already, otherwise the
  /// freshly-downloaded sidecar is loaded + selected. Returns what happened so a
  /// caller can report it. Best-effort; a failure here never disrupts playback.
  Future<_SubtitleFetchResult> _downloadAndSelectEnglish() async {
    final log = getIt<ErrorLogService>();
    try {
      final srtPath =
          await getIt<SubtitleService>().ensureEnglish(widget.filePath);
      if (!mounted) return _SubtitleFetchResult.none;

      // If libmpv already exposes an English track — an embedded stream, or a
      // sidecar it auto-loaded — select it if it isn't the active one. mpv
      // won't necessarily display it on its own, so we turn it on explicitly.
      final english = _player.state.tracks.subtitle
          .where((s) => SubtitleSkipCheck.isEnglish(s.language, s.title))
          .toList();
      if (english.isNotEmpty) {
        // Prefer a full transcript over a forced/signs-only track (which shows
        // almost nothing). Title is the only signal libmpv exposes here — the
        // disposition.forced flag isn't in its track model — so a forced track
        // with no telltale title can still slip through; the right-click menu
        // is the manual override for that case.
        final track = english.firstWhere(
          (s) => !SubtitleSkipCheck.looksLikeForced(s.title),
          orElse: () => english.first,
        );
        if (_player.state.track.subtitle.id != track.id) {
          await _player.setSubtitleTrack(track);
          log.info('Enabled existing English subtitle track ${track.id}',
              source: 'PlayerScreen.ensureSubtitles');
        } else {
          log.info('English subtitle track ${track.id} already selected',
              source: 'PlayerScreen.ensureSubtitles');
        }
        return _SubtitleFetchResult.selectedExisting;
      }

      if (srtPath == null) {
        log.info('no English subtitles available (none found or downloaded)',
            source: 'PlayerScreen.ensureSubtitles');
        return _SubtitleFetchResult.none;
      }

      await _player.setSubtitleTrack(
        SubtitleTrack.uri(srtPath, title: 'English', language: 'en'),
      );
      log.info('Loaded + selected English subtitles: $srtPath',
          source: 'PlayerScreen.ensureSubtitles');
      return _SubtitleFetchResult.downloaded;
    } catch (e, st) {
      log.logError(e, stackTrace: st, source: 'PlayerScreen.ensureSubtitles');
      return _SubtitleFetchResult.error;
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

    // Once past the halfway mark, start downloading the next episode (if any)
    // in the background so it's ready by the time this one ends.
    _maybePrefetchNext(pos);

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

  /// Fire the next-episode prefetch once, after the halfway point.
  void _maybePrefetchNext(Duration pos) {
    if (_prefetchedNext) return;
    final item = _currentItem;
    final dur = _player.state.duration;
    if (item == null || dur <= Duration.zero) return;
    if (pos.inSeconds < dur.inSeconds * 0.5) return;
    _prefetchedNext = true;
    unawaited(_prefetchNext(item));
  }

  /// Fetch the current episode's TMDB name and fold it into the top-bar title.
  /// Best-effort; a miss just leaves the "Show — S01E03" title as-is.
  Future<void> _loadEpisodeName() async {
    final item = _currentItem;
    if (item?.tmdbId == null || item?.season == null || item?.episode == null) {
      return;
    }
    final details =
        await getIt<DiscoveryClient>().seasonDetails(item!.tmdbId!, item.season!);
    for (final e in details?.episodes ?? const []) {
      if (e.episodeNumber == item.episode) {
        if (e.name.trim().isNotEmpty) {
          _episodeName = e.name.trim();
          _refreshDisplayTitle();
        }
        break;
      }
    }
  }

  /// The title shown in the top bar: [_displayTitle] once composed from the
  /// loaded library row, else whatever the caller passed.
  String? get _effectiveTitle => _displayTitle ?? widget.title;

  /// Recompose the playback title from the loaded [_currentItem] so it's the
  /// fullest, most consistent form regardless of what the call site passed:
  ///  • a TV episode → "Show — S01E03 · Episode Name" (the episode name filled in
  ///    once [_loadCreditsMeta] fetches it; "Show — S01E03" until then, or when
  ///    the row isn't matched to TMDB). The show name is the clean TMDB name when
  ///    matched, else the scanner's clean title.
  ///  • a movie → its clean name.
  ///  • a trailer / ad-hoc stream (no row) → the caller's title.
  void _refreshDisplayTitle() {
    final item = _currentItem;
    if (item == null) return;
    final season = item.season;
    final episode = item.episode;
    final String? title;

    if (item.mediaType == 'tv' && season != null && episode != null) {
      final passed = widget.title;
      final passedHasCode =
          passed != null && RegExp(r'[Ss]\d{1,2}[Ee]\d{1,2}').hasMatch(passed);
      if (item.tmdbName == null && passedHasCode) {
        // Not matched yet, but the caller (the acquire flow) already baked the
        // code + episode name into the title — that's the fullest we have.
        title = passed;
      } else {
        // The clean show name: the TMDB name when matched, else the scanner's
        // title (already just the show name; strip any "— S01E01 …" the acquire
        // flow may have added so we don't double the code).
        final show = item.tmdbName ?? item.title.split(' — ').first.trim();
        title = composePlayerTitle(
          name: show,
          season: season,
          episode: episode,
          episodeName: _episodeName,
        );
      }
    } else if (item.tmdbName != null) {
      title = item.tmdbName; // matched movie → clean title
    } else {
      title = widget.title ?? item.title;
    }

    if (mounted && title != _displayTitle) {
      setState(() => _displayTitle = title);
    }
  }

  /// Download the episode after [item] (S{n}E{e+1}) if it isn't already in the
  /// library. Fire-and-forget through the acquisition seam; never blocks play.
  Future<void> _prefetchNext(LibraryItem item) async {
    final tmdbId = item.tmdbId;
    final season = item.season;
    final episode = item.episode;
    if (item.mediaType != 'tv' ||
        tmdbId == null ||
        season == null ||
        episode == null) {
      return;
    }
    final next = await _nextEpisodeNumber(tmdbId, season, episode);
    if (next == null) return;
    final (nextSeason, nextEp) = next;

    final local = await _library.localEpisodes(tmdbId);
    if (local.any((e) => e.season == nextSeason && e.episode == nextEp)) return;
    try {
      await prefetchEpisode(
        showName: item.tmdbName ?? item.title,
        tmdbId: tmdbId,
        season: nextSeason,
        episode: nextEp,
      );
    } catch (e, st) {
      getIt<ErrorLogService>()
          .logError(e, stackTrace: st, source: 'PlayerScreen.prefetchNext');
    }
  }

  /// The next episode's (season, episode) — the next in the same season, or the
  /// first of the next season once this one is finished — from TMDB season
  /// episode counts. Null when there's no next. Without TMDB (offline / no key)
  /// it degrades to the next episode in the same season.
  Future<(int, int)?> _nextEpisodeNumber(
      int tmdbId, int season, int episode) async {
    final details = await getIt<DiscoveryClient>().tvDetails(tmdbId);
    final counts = <int, int>{
      for (final s in details?.seasons ?? const [])
        if (s.seasonNumber >= 1 && s.episodeCount != null)
          s.seasonNumber: s.episodeCount!,
    };
    return nextEpisodeNumber(season, episode, episodeCounts: counts);
  }

  /// Open a local episode in place, replacing this player so Back doesn't return
  /// to the episode we just moved on from. Used by the "Play Next Episode"
  /// button.
  void _openEpisode(LibraryItem next) {
    if (!mounted) return;
    context.pushReplacement(
      Routes.player,
      extra: PlayerArgs(
        filePath: next.filePath,
        title: next.tmdbName ?? next.title,
        libraryItemId: next.id,
      ),
    );
  }

  /// When an episode finishes, roll straight into the next one if it's already
  /// downloaded (binge) — the auto counterpart to the "Play Next Episode" button.
  /// Fires at most once, only for a local TV episode, and only when the setting
  /// is on and the next episode is actually on disk (else the button stands in,
  /// offering to download it).
  void _maybeAutoAdvance() {
    if (_autoAdvanced || _isNetworkSource || !_isTvEpisode) return;
    if (!getIt<SettingsService>().autoPlayNextEpisode) return;
    final next = _nextLocalItem;
    if (next == null) return;
    _autoAdvanced = true;
    _openEpisode(next);
  }

  /// Resolve the episode that follows the current one — and whether it's already
  /// downloaded — to drive the bottom-right "Next Episode" button. Best-effort:
  /// on any failure (or when there's no next) the button simply doesn't appear.
  Future<void> _resolveNextEpisode() async {
    final item = _currentItem;
    final tmdbId = item?.tmdbId;
    final season = item?.season;
    final episode = item?.episode;
    if (item == null || tmdbId == null || season == null || episode == null) {
      return;
    }
    try {
      final next = await _nextEpisodeNumber(tmdbId, season, episode);
      if (next == null || !mounted) return;
      final (nextSeason, nextEp) = next;
      LibraryItem? localNext;
      for (final e in await _library.localEpisodes(tmdbId)) {
        if (e.season == nextSeason && e.episode == nextEp) {
          localNext = e;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _nextEpisode = next;
        _nextShowName = item.tmdbName ?? item.title;
        _nextTmdbId = tmdbId;
        _nextLocalItem = localNext;
      });
    } catch (e, st) {
      getIt<ErrorLogService>()
          .logError(e, stackTrace: st, source: 'PlayerScreen.resolveNext');
    }
  }

  /// "Download Next Episode" — kick off the background download and give the
  /// button immediate feedback until the daemon reports it (the button then
  /// flips to the downloading state via [downloadForTagProvider]). If nothing
  /// actually started (no source, or a VPN is required but down) clear the
  /// pending flag and tell the user.
  Future<void> _downloadNextEpisode() async {
    final next = _nextEpisode;
    final show = _nextShowName;
    final tmdbId = _nextTmdbId;
    if (next == null || show == null || tmdbId == null) return;
    final (nextSeason, nextEp) = next;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _nextDownloadRequested = true);

    await prefetchEpisode(
      showName: show,
      tmdbId: tmdbId,
      season: nextSeason,
      episode: nextEp,
    );
    if (!mounted) return;

    final daemon = getIt<TorrentDaemon>();
    final started = await daemon.taskForDedupeKey(acquisitionDedupeKey(
                tmdbId: tmdbId,
                title: show,
                season: nextSeason,
                episode: nextEp)) !=
            null ||
        await daemon.taskForDedupeKey(acquisitionDedupeKey(
                tmdbId: tmdbId, title: show, season: nextSeason)) !=
            null;
    if (!started && mounted) {
      setState(() => _nextDownloadRequested = false);
      messenger.showSnackBar(const SnackBar(
        content: Text("Couldn't start the download — see the error log."),
      ));
    }
  }

  /// "Play Next Episode when Ready" — jump into the preparing dialog for the next
  /// episode (reattaches to the in-flight download, buffers, then plays it in
  /// place of this one).
  Future<void> _playNextWhenReady() async {
    final next = _nextEpisode;
    final show = _nextShowName;
    final tmdbId = _nextTmdbId;
    if (next == null || show == null || tmdbId == null) return;
    final (nextSeason, nextEp) = next;
    final s = nextSeason.toString().padLeft(2, '0');
    final e = nextEp.toString().padLeft(2, '0');
    await playWhenReady(
      context,
      replace: true,
      title: '$show — S${s}E$e',
      meta: ShowMeta(title: show, tmdbId: tmdbId, mediaType: 'tv'),
      season: nextSeason,
      episode: nextEp,
    );
  }

  /// "This torrent's no good" — abandon the current source and stream the
  /// next-best one for this title. Only for real library titles sourced through
  /// acquisition (needs the show/episode to re-resolve); no-op for trailers.
  /// Stops playback first so the daemon can delete the current file, then hands
  /// off to the preparing dialog (retry-first) and replaces this player with the
  /// new source so Back doesn't return to the dead one.
  Future<void> _tryAnotherSource() async {
    final item = _currentItem;
    if (item == null) return;
    _subtitleMenuController.close();
    final meta = ShowMeta(
      title: item.tmdbName ?? item.title,
      tmdbId: item.tmdbId,
      mediaType: item.mediaType,
    );
    await _player.stop();
    if (!mounted) return;
    await playWhenReady(
      context,
      title: _effectiveTitle ?? item.tmdbName ?? item.title,
      meta: meta,
      season: item.season,
      episode: item.episode,
      retryFirst: true,
      replace: true,
    );
  }

  // Prefer English audio (then the widest layout), auto-selected once per open;
  // afterwards the user's manual choice from the "Audio" menu is respected.
  void _onTracks(Tracks tracks) {
    // Keep the right-click menus in sync with what libmpv exposes (embedded
    // tracks appear once the container is probed; a loaded subtitle sidecar
    // appears after sub-add).
    if (mounted && !listEquals(_subtitleTracks, tracks.subtitle)) {
      setState(() => _subtitleTracks = tracks.subtitle);
    }
    final audio = _selectableAudio(tracks.audio);
    if (mounted && !listEquals(_audioTracks, audio)) {
      setState(() => _audioTracks = audio);
    }

    if (_audioAutoSelected) return;
    if (audio.length < 2) return;

    final preferSurround = getIt<SettingsService>().preferSurroundAudio;
    final infos = audio.map(_audioInfo).toList(growable: false);
    final hasEnglish = infos.any(isEnglishAudio);

    // With no English track, we only reorder for channel width, which needs the
    // counts libmpv hasn't probed yet — wait for a later update. (English
    // selection is language-only, so it doesn't need to wait.)
    if (!hasEnglish) {
      if (!preferSurround) {
        _audioAutoSelected = true; // nothing we're allowed to change
        return;
      }
      if (!infos.any((t) => t.channels > 0)) return;
    }

    _audioAutoSelected = true;
    final idx = autoAudioTrackIndex(infos, preferSurround: preferSurround);
    if (idx == null) return;
    final best = audio[idx];
    // Nothing to do if it's already what mpv picked by default.
    if (best.id == _player.state.track.audio.id) return;

    _player.setAudioTrack(best);
    getIt<ErrorLogService>().info(
      'Auto-selected audio track ${best.id} (${_audioLabel(best)})',
      source: 'PlayerScreen',
    );
  }

  // Only real, selectable tracks — skip the synthetic "auto"/"no" entries.
  List<AudioTrack> _selectableAudio(List<AudioTrack> audio) => audio
      .where((t) => t.id != 'auto' && t.id != 'no')
      .toList(growable: false);

  AudioTrackInfo _audioInfo(AudioTrack t) => AudioTrackInfo(
        language: t.language,
        title: t.title,
        channels: _channelCount(t),
        isDefault: t.isDefault ?? false,
      );

  /// A readable label for an audio track in the picker — its title or language,
  /// plus the channel layout ("English · 5.1", "Português · Stereo", "Track 2").
  String _audioLabel(AudioTrack t) {
    final title = t.title?.trim();
    final lang = t.language?.trim();
    final bits = <String>[];
    if (title != null && title.isNotEmpty) {
      bits.add(title);
      if (lang != null &&
          lang.isNotEmpty &&
          !title.toLowerCase().contains(lang.toLowerCase())) {
        bits.add('(${lang.toUpperCase()})');
      }
    } else if (lang != null && lang.isNotEmpty) {
      bits.add(lang.toUpperCase());
    } else {
      bits.add('Track ${t.id}');
    }
    final ch = channelLayoutLabel(_channelCount(t));
    if (ch != null) bits.add('· $ch');
    return bits.join(' ');
  }

  /// Entries for the right-click "Audio" submenu: every selectable track, the
  /// active one check-marked.
  List<Widget> _audioMenuItems() {
    if (_audioTracks.isEmpty) {
      return const [MenuItemButton(child: Text('No audio tracks'))];
    }
    return [
      for (final t in _audioTracks)
        MenuItemButton(
          leadingIcon: Icon(
            t.id == _selectedAudio.id ? Icons.check_rounded : null,
            size: 18,
          ),
          onPressed: () => _selectAudio(t),
          child: Text(_audioLabel(t)),
        ),
    ];
  }

  /// Switch to [track] and log it. Marks auto-select done so our English
  /// preference doesn't fight the user's manual choice.
  Future<void> _selectAudio(AudioTrack track) async {
    _subtitleMenuController.close();
    _audioAutoSelected = true;
    try {
      await _player.setAudioTrack(track);
      if (mounted) setState(() => _selectedAudio = track);
      getIt<ErrorLogService>().info(
        'User selected audio: ${_audioLabel(track)} (id=${track.id})',
        source: 'PlayerScreen',
      );
    } catch (e, st) {
      getIt<ErrorLogService>()
          .logError(e, stackTrace: st, source: 'PlayerScreen.selectAudio');
    }
  }

  /// "Who's in this?" — open the cast panel for the current title (pulled from
  /// TMDB), or fall back to a typed web search when there's no TMDB match.
  Future<void> _showCast() async {
    _subtitleMenuController.close();
    final item = _currentItem;
    final tmdbId = item?.tmdbId;
    if (item == null || tmdbId == null) {
      await _lookupActorByTyping();
      return;
    }
    final title = _effectiveTitle ?? item.tmdbName ?? item.title;
    final query = (item.mediaType == 'tv' &&
            item.season != null &&
            item.episode != null)
        ? CastQuery.episode(
            tmdbId: tmdbId,
            season: item.season!,
            episode: item.episode!,
            title: title)
        : CastQuery.movie(tmdbId: tmdbId, title: title);
    if (mounted) await showCastDialog(context, query);
  }

  /// Fallback for an unmatched title: type a character name and hand off to a
  /// web search for who plays them.
  Future<void> _lookupActorByTyping() async {
    final controller = TextEditingController();
    final title = _effectiveTitle ?? widget.title ?? '';
    final q = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Look up an actor'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                "Type the character's name and we'll search the web for who "
                'plays them.'),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Character name'),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Search')),
        ],
      ),
    );
    if (q == null || q.trim().isEmpty) return;
    final search = '${q.trim()} $title actor'.trim();
    await openUrl(
        'https://www.google.com/search?q=${Uri.encodeQueryComponent(search)}');
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
    _advanceContinueWatching();
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
    // Finishing an episode (played to the end, or backed out during the
    // credits) drops it from Continue Watching — so point the rail at the next
    // episode instead, keeping the show resumable where you actually are.
    if (nearEnd) _advanceContinueWatching();
  }

  /// Keep this show on the Continue Watching rail after finishing an episode:
  /// seed the next episode (when it's downloaded) so the show stays resumable
  /// and an older, half-watched episode doesn't resurface in its place.
  void _advanceContinueWatching() {
    final next = _nextLocalItem;
    if (next != null) unawaited(_history.advanceToNextEpisode(next.id));
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _persistFinal();
    _controlsHideTimer?.cancel();
    // Best-effort: remove the trailer's downloaded caption sidecar.
    _trailerSubDir?.delete(recursive: true).ignore();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  void _back() {
    if (context.canPop()) context.pop();
  }

  /// Any user activity — pointer *or* keyboard/remote — reveals the overlay
  /// (back button + Next Episode) and restarts the idle countdown that hides it,
  /// mirroring the media_kit controls. The idle-hide only arms while playing;
  /// paused/ended keeps it up so it can't get stranded off-screen.
  void _revealControls() {
    _controlsHideTimer?.cancel();
    if (_isPlaying) {
      _controlsHideTimer = Timer(_controlsHideDelay, _hideControls);
    }
    if (!_controlsVisible) setState(() => _controlsVisible = true);
  }

  void _hideControls() {
    if (mounted && _controlsVisible) setState(() => _controlsVisible = false);
  }

  /// React to play/pause: while paused or ended keep the overlay up (and cancel
  /// any pending hide) so the back/next buttons stay reachable; on resume, fall
  /// back to the normal reveal-then-idle-hide behavior.
  void _onPlayingChanged(bool playing) {
    _isPlaying = playing;
    if (!playing) {
      _controlsHideTimer?.cancel();
      if (mounted && !_controlsVisible) setState(() => _controlsVisible = true);
    } else {
      _revealControls();
    }
  }

  /// Toggle OS-window fullscreen via window_manager — the same path as the F11
  /// key and the in-controls fullscreen button, so double-click, key, and button
  /// all drive one fullscreen state. Best-effort; a failure is logged, not fatal.
  void _toggleFullscreen() {
    unawaited(toggleFullscreen().catchError((Object e, StackTrace st) {
      getIt<ErrorLogService>()
          .logError(e, stackTrace: st, source: 'PlayerScreen.toggleFullscreen');
    }));
  }

  /// Human-readable label for a subtitle track in the picker. Embedded tracks
  /// often carry a title (e.g. "English SDH", "Forced") and/or a language code;
  /// surface whatever's there so the user can tell a full track from a
  /// forced/signs-only one — with a verbose title truncated so it doesn't blow
  /// out the menu (see [subtitleTrackLabel]).
  String _subtitleLabel(SubtitleTrack t) =>
      subtitleTrackLabel(id: t.id, title: t.title, language: t.language);

  /// Switch to [track] and log the choice. Optimistically updates the checkmark;
  /// the `stream.track` listener confirms it.
  Future<void> _selectSubtitle(SubtitleTrack track) async {
    try {
      await _player.setSubtitleTrack(track);
      if (mounted) setState(() => _selectedSubtitle = track);
      getIt<ErrorLogService>().info(
        'User selected subtitle: ${_subtitleLabel(track)} (id=${track.id})',
        source: 'PlayerScreen',
      );
    } catch (e, st) {
      getIt<ErrorLogService>()
          .logError(e, stackTrace: st, source: 'PlayerScreen.selectSubtitle');
    }
  }

  /// The entries for the "Subtitles" submenu: every track libmpv reports (the
  /// synthetic "Off" included, "Auto" dropped as redundant for a manual
  /// chooser), the active one check-marked, plus the timing-offset control.
  List<Widget> _subtitleMenuItems() {
    final tracks =
        _subtitleTracks.where((t) => t.id != 'auto').toList(growable: false);
    final sign = _subtitleOffsetMs > 0 ? '+' : '';
    return [
      if (tracks.isEmpty)
        const MenuItemButton(child: Text('No subtitle tracks'))
      else
        for (final t in tracks)
          MenuItemButton(
            leadingIcon: Icon(
              t.id == _selectedSubtitle.id ? Icons.check_rounded : null,
              size: 18,
            ),
            onPressed: () => _selectSubtitle(t),
            child: Text(_subtitleLabel(t)),
          ),
      const Divider(height: 1),
      MenuItemButton(
        leadingIcon: const Icon(Icons.av_timer_rounded, size: 18),
        onPressed: _openSubtitleOffsetDialog,
        child: Text('Timing offset…  ($sign$_subtitleOffsetMs ms)'),
      ),
    ];
  }

  /// Push the timing offset to libmpv as `sub-delay` (seconds; positive delays
  /// the subtitles). Best-effort — a failure is logged, never fatal.
  Future<void> _applySubtitleDelay(int ms) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    try {
      await platform.setProperty('sub-delay', '${ms / 1000}');
    } catch (e, st) {
      getIt<ErrorLogService>()
          .logError(e, stackTrace: st, source: 'PlayerScreen.subDelay');
    }
  }

  /// Set the offset live (state + mpv) without persisting — used while the user
  /// is dragging the value in the dialog so they see the effect immediately.
  void _setSubtitleOffsetLive(int ms) {
    final clamped = ms.clamp(-_subtitleOffsetLimit, _subtitleOffsetLimit);
    if (mounted) setState(() => _subtitleOffsetMs = clamped);
    unawaited(_applySubtitleDelay(clamped));
  }

  /// Persist the current offset on the library row (per title). No-op for
  /// ad-hoc streams that have no library item.
  Future<void> _persistSubtitleOffset() async {
    final id = widget.libraryItemId;
    if (id == null) return;
    try {
      await _library.setSubtitleOffset(id, _subtitleOffsetMs);
      getIt<ErrorLogService>().info(
          'Saved subtitle timing offset ${_subtitleOffsetMs}ms',
          source: 'PlayerScreen');
    } catch (e, st) {
      getIt<ErrorLogService>()
          .logError(e, stackTrace: st, source: 'PlayerScreen.persistOffset');
    }
  }

  /// Dialog to nudge the subtitle timing offset (±10s, in ms). Applies live as
  /// the value changes; persists once when dismissed.
  Future<void> _openSubtitleOffsetDialog() async {
    _subtitleMenuController.close();
    final controller = TextEditingController(text: '$_subtitleOffsetMs');
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            void apply(int v) {
              _setSubtitleOffsetLive(v);
              controller.text = '$_subtitleOffsetMs';
              controller.selection =
                  TextSelection.collapsed(offset: controller.text.length);
              setLocal(() {});
            }

            Widget step(int delta) => OutlinedButton(
                  onPressed: () => apply(_subtitleOffsetMs + delta),
                  child: Text('${delta > 0 ? '+' : ''}$delta'),
                );

            return AlertDialog(
              title: const Text('Subtitle timing offset'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Milliseconds to delay (+) or advance (−) the subtitles '
                    'for this title.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [step(-1000), step(-100), step(-10)],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: 150,
                    child: TextField(
                      controller: controller,
                      textAlign: TextAlign.center,
                      keyboardType:
                          const TextInputType.numberWithOptions(signed: true),
                      onChanged: (s) {
                        final v = int.tryParse(s);
                        if (v != null) _setSubtitleOffsetLive(v);
                      },
                      onSubmitted: (s) => apply(int.tryParse(s) ?? _subtitleOffsetMs),
                      decoration: const InputDecoration(
                        suffixText: 'ms',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [step(10), step(100), step(1000)],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => apply(0),
                  child: const Text('Reset'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    await _persistSubtitleOffset();
  }

  /// Controls theme: back button in the top bar (fades with the UI), and a
  /// fullscreen button that drives the OS window fullscreen (window_manager) so
  /// it's in sync with how the app launches. media_kit's own double-press
  /// fullscreen is disabled — double-click is routed to our window_manager
  /// toggle instead (see the outer GestureDetector in [build]) — so there's no
  /// competing fullscreen system.
  MaterialDesktopVideoControlsThemeData _controlsTheme() {
    return MaterialDesktopVideoControlsThemeData(
      // Single click on the video toggles play/pause (media_kit guards the
      // bottom seek-bar region so clicking the scrubber doesn't pause).
      playAndPauseOnTap: true,
      toggleFullscreenOnDoublePress: false,
      // Hide the mouse pointer together with the controls when they fade out, so
      // a fullscreen TV appliance shows nothing over the video while playing.
      hideMouseOnControlsRemoval: true,
      // The back button + title are rendered by us as a top-bar overlay (see
      // build) rather than here: media_kit's controls theme has an inverted
      // `updateShouldNotify` (it notifies only when the theme is *identical*), so
      // a title set after the first frame — once the library row and episode name
      // load — would never repaint through its topButtonBar.
      topButtonBar: const [],
      bottomButtonBar: [
        // Jump back 10s — the common "what did they just say?" rewind.
        MaterialDesktopCustomButton(
          icon: const Icon(Icons.replay_10_rounded),
          onPressed: _skipBack10,
        ),
        const MaterialDesktopPlayOrPauseButton(),
        // Jump forward 10s — the counterpart to the rewind, sat right after Play.
        MaterialDesktopCustomButton(
          icon: const Icon(Icons.forward_10_rounded),
          onPressed: _skipForward10,
        ),
        const MaterialDesktopVolumeButton(),
        const MaterialDesktopPositionIndicator(),
        const Spacer(),
        const FullscreenToggleButton(color: Colors.white, iconSize: 28),
      ],
    );
  }

  /// Seek 10 seconds earlier (clamped at the start), for the bottom-bar rewind
  /// button. Best-effort — a failure is logged, never fatal to playback.
  void _skipBack10() {
    final target = _player.state.position - const Duration(seconds: 10);
    final clamped = target < Duration.zero ? Duration.zero : target;
    unawaited(_player.seek(clamped).catchError((Object e, StackTrace st) {
      getIt<ErrorLogService>()
          .logError(e, stackTrace: st, source: 'PlayerScreen.skipBack10');
    }));
  }

  /// Seek 10 seconds later (clamped at the duration), for the bottom-bar
  /// fast-forward button. Best-effort — a failure is logged, never fatal.
  void _skipForward10() {
    final duration = _player.state.duration;
    var target = _player.state.position + const Duration(seconds: 10);
    if (duration > Duration.zero && target > duration) target = duration;
    unawaited(_player.seek(target).catchError((Object e, StackTrace st) {
      getIt<ErrorLogService>()
          .logError(e, stackTrace: st, source: 'PlayerScreen.skipForward10');
    }));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: _error != null
                ? _PlaybackError(
                    title: _effectiveTitle,
                    message: _error!,
                    onRetry: _currentItem != null ? _tryAnotherSource : null,
                  )
                : Stack(
                    children: [
                      // Right-click anywhere on the video opens the context menu
                      // at the pointer. Secondary tap isn't used by the media_kit
                      // controls (which own primary tap / hover), so they coexist.
                      // Double-click toggles OS-window fullscreen (window_manager,
                      // the app's single source of truth). On a genuine double
                      // tap the DoubleTapGestureRecognizer wins the arena, so the
                      // inner play/pause tap is rejected and doesn't flicker; a
                      // single tap times out and falls through to media_kit's
                      // playAndPauseOnTap handler.
                      Positioned.fill(
                        child: GestureDetector(
                          onSecondaryTapDown: (d) => _subtitleMenuController
                              .open(position: d.localPosition),
                          onDoubleTap: _toggleFullscreen,
                          child: MaterialDesktopVideoControlsTheme(
                            normal: _controlsTheme(),
                            fullscreen: _controlsTheme(),
                            child: Video(
                              controller: _controller,
                              controls: MaterialDesktopVideoControls,
                            ),
                          ),
                        ),
                      ),
                      // A zero-size anchor pinned top-left; the menu opens at the
                      // pointer offset (measured from here). Keeping the video
                      // OUT of the anchor's child is what makes a click anywhere
                      // on the video count as "outside" and dismiss the menu —
                      // consumeOutsideTap also swallows that click so it doesn't
                      // toggle play/pause.
                      Align(
                        alignment: Alignment.topLeft,
                        child: MenuAnchor(
                          controller: _subtitleMenuController,
                          consumeOutsideTap: true,
                          menuChildren: [
                            // Only worth showing when there's a real choice.
                            if (_audioTracks.length >= 2)
                              SubmenuButton(
                                leadingIcon: const Icon(
                                    Icons.multitrack_audio_rounded,
                                    size: 18),
                                menuChildren: _audioMenuItems(),
                                child: const Text('Audio'),
                              ),
                            SubmenuButton(
                              leadingIcon: const Icon(Icons.subtitles_outlined,
                                  size: 18),
                              menuChildren: _subtitleMenuItems(),
                              child: const Text('Subtitles'),
                            ),
                            // "Who's in this?" — pull the episode/movie cast from
                            // TMDB (a typed web search when there's no match).
                            if (!_isNetworkSource)
                              MenuItemButton(
                                leadingIcon: const Icon(
                                    Icons.people_alt_outlined,
                                    size: 18),
                                onPressed: _showCast,
                                child: const Text('Who’s in this?'),
                              ),
                            // Manual subtitle fetch — surfaced when auto-download
                            // is off, so subtitles can still be pulled on demand.
                            if (widget.libraryItemId != null &&
                                !getIt<SettingsService>().autoDownloadSubtitles)
                              MenuItemButton(
                                leadingIcon: _subtitlesDownloading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(Icons.download_rounded,
                                        size: 18),
                                onPressed: _subtitlesDownloading
                                    ? null
                                    : _manualDownloadSubtitles,
                                child: Text(_subtitlesDownloading
                                    ? 'Downloading subtitles…'
                                    : 'Download English subtitles'),
                              ),
                            if (_currentItem != null)
                              MenuItemButton(
                                leadingIcon: const Icon(Icons.refresh_rounded,
                                    size: 18),
                                onPressed: _tryAnotherSource,
                                child: const Text('Try a different source'),
                              ),
                          ],
                          child: const SizedBox.shrink(),
                        ),
                      ),
                    ],
                  ),
          ),
          // Activity catcher over the whole player: any pointer activity reveals
          // the overlay (and resets its idle-hide timer), so the back/Next
          // Episode buttons come up whenever the media_kit controls would.
          // A MouseRegion (canonical hover, fires even when the raw Listener's
          // hover is shadowed by media_kit's own regions) is layered with the
          // Listener for move/scroll. Both are non-opaque / translucent with no
          // gesture recognizers, so taps, double-taps and the right-click menu
          // still pass straight through to the video below — and taps reveal the
          // overlay anyway via the play/pause state change. Key presses (a
          // remote) reveal it through the global HardwareKeyboard handler.
          if (_error == null)
            Positioned.fill(
              child: MouseRegion(
                opaque: false,
                onEnter: (_) => _revealControls(),
                onHover: (_) => _revealControls(),
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerHover: (_) => _revealControls(),
                  onPointerMove: (_) => _revealControls(),
                  onPointerSignal: (_) => _revealControls(),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          // Our own top bar (back + title), fading with the controls. Rendered
          // here — not via media_kit's topButtonBar — so a title composed after
          // the first frame actually repaints (see _controlsTheme).
          if (_error == null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1.0 : 0.0,
                  duration: _controlsFade,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xB3000000), Color(0x00000000)],
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: _back,
                              icon: const Icon(Icons.arrow_back_rounded,
                                  color: Colors.white),
                              tooltip: 'Back',
                            ),
                            if (_effectiveTitle != null)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                      left: AppSpacing.sm),
                                  child: Text(
                                    _effectiveTitle!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 18),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
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
          // The single "Next Episode" affordance, bottom-right. It fades in and
          // out with the player controls (and goes untappable while hidden), so
          // it's there whenever the UI is up and gone when the UI is. Hidden on
          // the error screen.
          if (_error == null && _nextEpisode != null)
            Positioned(
              right: AppSpacing.xl,
              bottom: AppSpacing.xxl + AppSpacing.xl,
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1.0 : 0.0,
                  duration: _controlsFade,
                  child: NextEpisodeButton(
                    showName: _nextShowName!,
                    tmdbId: _nextTmdbId!,
                    season: _nextEpisode!.$1,
                    episode: _nextEpisode!.$2,
                    localItem: _nextLocalItem,
                    downloadRequested: _nextDownloadRequested,
                    onPlayLocal: _openEpisode,
                    onPlayWhenReady: _playNextWhenReady,
                    onDownload: _downloadNextEpisode,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Outcome of an English-subtitle fetch, so the manual trigger can report it.
enum _SubtitleFetchResult {
  /// A newly-downloaded sidecar was loaded and selected.
  downloaded,

  /// An already-present English track (embedded / auto-loaded) was turned on.
  selectedExisting,

  /// Nothing available — none found and none downloaded.
  none,

  /// The fetch threw (logged).
  error,
}

class _PlaybackError extends StatelessWidget {
  const _PlaybackError({required this.message, this.title, this.onRetry});
  final String? title;
  final String message;

  /// Offered for acquisition-sourced titles: abandon this (bad) source and
  /// stream the next-best one. Null for local files / trailers.
  final VoidCallback? onRetry;

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
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try a different source'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
