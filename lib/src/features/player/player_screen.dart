import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
// Hide media_kit's own `toggleFullscreen` — we drive fullscreen through
// window_manager (window_service.toggleFullscreen), the app's single source of
// truth, to avoid two competing fullscreen systems.
import 'package:media_kit_video/media_kit_video.dart' hide toggleFullscreen;

import '../../core/config/app_config.dart';
import '../../core/logging/error_log_service.dart';
import '../../core/media/ytdlp.dart';
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
import 'credits.dart';
import 'next_episode.dart';

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
  // We auto-select the best (most-channels) audio track once, on the first
  // tracks update. After that the user is free to change it from the mpv menu
  // and we won't override their choice.
  bool _audioAutoSelected = false;
  // Resume target applied on the first position tick — seeking right after
  // open() is dropped because libmpv isn't ready to seek yet.
  Duration? _pendingSeek;
  String? _error;

  // The library row for the playing file (show/season/episode) — drives
  // prefetching and auto-playing the next episode. Loaded in _open().
  LibraryItem? _currentItem;
  // Prefetch of the next episode fires once, partway through.
  bool _prefetchedNext = false;
  // "Up Next" auto-advance: the next local episode + its countdown.
  LibraryItem? _upNext;
  Timer? _upNextTimer;
  int _upNextSeconds = 0;
  // Credits detection: chapters read via ffprobe, and the position at which to
  // roll "Up Next" (a credits chapter, else a runtime-tail heuristic). Computed
  // once the duration is known. `_creditsChecked` fires the roll at most once
  // from the position ticks; `_advanced` guards against doing it twice (credits
  // trigger vs the natural end).
  List<VideoChapter> _chapters = const [];
  Duration? _contentRuntime; // the episode's TMDB runtime, if known
  bool _creditsMetaReady = false;
  int? _creditsTriggerSec;
  bool _creditsChecked = false;
  bool _advanced = false;

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

  // Per-title subtitle timing offset (ms), applied as mpv `sub-delay` and
  // persisted on the library row so a re-watch stays corrected. Range is
  // clamped to ±10s in the editor.
  int _subtitleOffsetMs = 0;
  static const _subtitleOffsetLimit = 10000;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      var start = widget.startAt;
      final id = widget.libraryItemId;
      if (id != null) {
        final item = await _library.findById(id);
        _currentItem = item;
        _subtitleOffsetMs = item?.subtitleOffsetMs ?? 0;
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
        if (mounted) setState(() => _selectedSubtitle = t.subtitle);
      }));
      _subs.add(_player.stream.completed.listen((done) {
        if (done) {
          _markCompleted();
          unawaited(_onCreditsOrEnd(atEnd: true));
        }
      }));

      // Credits-detection metadata for a local TV episode: chapters (ffprobe) +
      // the episode's TMDB runtime (content length). Used by _onPosition to roll
      // "Up Next" when the credits start rather than at the very end. Best-effort.
      if (_isTvEpisode && !_isNetworkSource) {
        unawaited(_loadCreditsMeta());
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

      // For a network URL (a YouTube trailer), point libmpv's ytdl_hook at the
      // bundled yt-dlp so it can resolve the stream — it only searches PATH, not
      // the app directory. No-op for local files and when yt-dlp isn't bundled
      // (libmpv then falls back to a PATH lookup / its graceful error state).
      await _configureYtdlp();
      await _configureLowPower();

      // Seek is applied on the first ready position tick (see _onPosition).
      await _player.open(Media(widget.filePath));

      // Re-apply the saved subtitle timing offset for this title (no-op at 0).
      if (_subtitleOffsetMs != 0) unawaited(_applySubtitleDelay(_subtitleOffsetMs));

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

    // Roll "Up Next" when the credits start (a credits chapter, else a
    // runtime-tail heuristic) rather than waiting for the very end.
    _maybeRollCredits(pos);

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

  /// When playback reaches the detected credits point, roll "Up Next" once (the
  /// natural end also triggers it, guarded so it only happens once).
  void _maybeRollCredits(Duration pos) {
    if (_creditsChecked || !_isTvEpisode) return;
    final dur = _player.state.duration;
    if (dur <= Duration.zero || !_creditsMetaReady) return;

    _creditsTriggerSec ??= creditsStart(
          duration: dur,
          chapters: _chapters,
          contentRuntime: _contentRuntime,
        )?.inSeconds ??
        -1;
    final trigger = _creditsTriggerSec!;
    if (trigger >= 0 && pos.inSeconds >= trigger) {
      _creditsChecked = true;
      unawaited(_onCreditsOrEnd(atEnd: false));
    }
  }

  /// Load credits-detection metadata for the current episode: chapters (via the
  /// bundled ffprobe) and the episode's TMDB runtime (content length). Both are
  /// best-effort; missing data just falls back to the runtime heuristic.
  Future<void> _loadCreditsMeta() async {
    final item = _currentItem;
    if (item?.tmdbId == null || item?.season == null || item?.episode == null) {
      return;
    }
    _chapters = await readVideoChapters(widget.filePath);
    _contentRuntime =
        await _episodeRuntime(item!.tmdbId!, item.season!, item.episode!);
    _creditsMetaReady = true;
  }

  /// The episode's aired runtime from TMDB, or null if unknown.
  Future<Duration?> _episodeRuntime(int tmdbId, int season, int episode) async {
    final details = await getIt<DiscoveryClient>().seasonDetails(tmdbId, season);
    for (final e in details?.episodes ?? const []) {
      if (e.episodeNumber == episode && e.runtime != null && e.runtime! > 0) {
        return Duration(minutes: e.runtime!);
      }
    }
    return null;
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

  /// Advance to the next episode — including rolling from the last episode of a
  /// season into the first of the next. Called both when the credits start
  /// ([atEnd] false) and at the natural end ([atEnd] true), but acts at most once
  /// (guarded by [_advanced]).
  ///
  /// If the next episode is already downloaded → an "Up Next" countdown auto-plays
  /// it (so it rolls as the credits play). If it's only downloading, we don't
  /// interrupt the credits with a blocking dialog — that waits for the natural
  /// end, then opens the "Preparing to play" dialog, which reattaches to the
  /// download, shows progress, and plays when buffered. No-op for movies/trailers
  /// or when there's no next.
  Future<void> _onCreditsOrEnd({required bool atEnd}) async {
    if (_advanced) return;
    final item = _currentItem;
    final tmdbId = item?.tmdbId;
    final season = item?.season;
    final episode = item?.episode;
    if (item == null ||
        item.mediaType != 'tv' ||
        tmdbId == null ||
        season == null ||
        episode == null) {
      return;
    }

    final next = await _nextEpisodeNumber(tmdbId, season, episode);
    if (next == null || !mounted || _advanced) return;
    final (nextSeason, nextEp) = next;
    final showName = item.tmdbName ?? item.title;

    // 1) The next episode is already in the library → Up Next countdown.
    LibraryItem? localNext;
    for (final e in await _library.localEpisodes(tmdbId)) {
      if (e.season == nextSeason && e.episode == nextEp) {
        localNext = e;
        break;
      }
    }
    if (localNext != null) {
      if (!mounted || _advanced) return;
      _advanced = true;
      setState(() {
        _upNext = localNext;
        _upNextSeconds = 10;
      });
      _upNextTimer?.cancel();
      _upNextTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() => _upNextSeconds--);
        if (_upNextSeconds <= 0) {
          t.cancel();
          _playNext();
        }
      });
      return;
    }

    // 2) Not local — if it's downloading (the prefetch started it), open the
    // preparing dialog. Don't do this mid-credits, only at the natural end, so a
    // blocking dialog never covers the credits.
    if (!atEnd) return;
    final daemon = getIt<TorrentDaemon>();
    final downloading = await daemon.taskForDedupeKey(acquisitionDedupeKey(
                tmdbId: tmdbId,
                title: showName,
                season: nextSeason,
                episode: nextEp)) !=
            null ||
        await daemon.taskForDedupeKey(acquisitionDedupeKey(
                tmdbId: tmdbId, title: showName, season: nextSeason)) !=
            null;
    if (!downloading || !mounted || _advanced) return;
    _advanced = true;

    final s = nextSeason.toString().padLeft(2, '0');
    final e = nextEp.toString().padLeft(2, '0');
    await playWhenReady(
      context,
      replace: true,
      title: '$showName — S${s}E$e',
      meta: ShowMeta(title: showName, tmdbId: tmdbId, mediaType: 'tv'),
      season: nextSeason,
      episode: nextEp,
    );
  }

  void _playNext() {
    _upNextTimer?.cancel();
    final next = _upNext;
    if (next == null || !mounted) return;
    // Replace this (finished) episode so Back doesn't return to it.
    context.pushReplacement(
      Routes.player,
      extra: PlayerArgs(
        filePath: next.filePath,
        title: next.tmdbName ?? next.title,
        libraryItemId: next.id,
      ),
    );
  }

  void _cancelUpNext() {
    _upNextTimer?.cancel();
    if (mounted) setState(() => _upNext = null);
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
      title: widget.title ?? item.tmdbName ?? item.title,
      meta: meta,
      season: item.season,
      episode: item.episode,
      retryFirst: true,
      replace: true,
    );
  }

  // When multiple audio tracks exist, prefer the one with the most channels so
  // a surround mix (5.1/7.1) wins over a stereo downmix. Runs once per open;
  // afterwards the user's manual track choice is respected.
  void _onTracks(Tracks tracks) {
    // Keep the right-click subtitle menu in sync with what libmpv exposes
    // (embedded tracks appear once the container is probed; a loaded sidecar
    // appears after sub-add).
    if (mounted && !listEquals(_subtitleTracks, tracks.subtitle)) {
      setState(() => _subtitleTracks = tracks.subtitle);
    }

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
    _upNextTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  void _back() {
    if (context.canPop()) context.pop();
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
  /// forced/signs-only one.
  String _subtitleLabel(SubtitleTrack t) {
    if (t.id == 'no') return 'Off';
    if (t.id == 'auto') return 'Auto';
    final title = t.title?.trim();
    final lang = t.language?.trim();
    if (title != null && title.isNotEmpty) {
      return (lang != null && lang.isNotEmpty) ? '$title ($lang)' : title;
    }
    if (lang != null && lang.isNotEmpty) return lang;
    return 'Track ${t.id}';
  }

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
                ? _PlaybackError(
                    title: widget.title,
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
                            SubmenuButton(
                              leadingIcon: const Icon(Icons.subtitles_outlined,
                                  size: 18),
                              menuChildren: _subtitleMenuItems(),
                              child: const Text('Subtitles'),
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
          if (_upNext != null)
            Positioned(
              right: AppSpacing.xl,
              bottom: AppSpacing.xl,
              child: _UpNextCard(
                title: _upNext!.tmdbName ?? _upNext!.title,
                subtitle: _upNext!.season != null && _upNext!.episode != null
                    ? 'S${_upNext!.season} · E${_upNext!.episode}'
                    : null,
                seconds: _upNextSeconds,
                onPlay: _playNext,
                onCancel: _cancelUpNext,
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

/// The "Up Next" auto-advance card shown at the end of an episode.
class _UpNextCard extends StatelessWidget {
  const _UpNextCard({
    required this.title,
    required this.seconds,
    required this.onPlay,
    required this.onCancel,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final int seconds;
  final VoidCallback onPlay;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: GlassSurface(
        strong: true,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Up next · playing in ${seconds}s',
                style: text.labelMedium
                    ?.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.xs),
            Text(title,
                style: text.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            if (subtitle != null)
              Text(subtitle!,
                  style: text.labelMedium
                      ?.copyWith(color: AppColors.secondary)),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                FilledButton.icon(
                  autofocus: true,
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play now'),
                ),
                const SizedBox(width: AppSpacing.sm),
                TextButton(onPressed: onCancel, child: const Text('Cancel')),
              ],
            ),
          ],
        ),
      ),
    );
  }
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
