import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

import '../../data/db/database.dart';

/// Typed, cached access to the user's app preferences (drift `settings` table).
///
/// Call [load] once at startup (like `StorageManager.load`); after that the
/// getters read a synchronous cache so services (reaper, player, subtitle queue)
/// can consult them without an await. Setters persist and update the cache, then
/// notify listeners so the settings screen re-renders. Every setting has a
/// default, so a fresh install with no rows behaves sensibly.
@LazySingleton()
class SettingsService extends ChangeNotifier {
  SettingsService(this._db);

  final AppDatabase _db;
  final Map<String, String> _cache = {};

  // Keys.
  static const _kAutoSubs = 'autoDownloadSubtitles';
  static const _kAutoPlayNext = 'autoPlayNextEpisode';
  static const _kRequireVpn = 'requireVpn';
  static const _kCleanupEnabled = 'cleanupEnabled';
  static const _kCleanupGraceDays = 'cleanupGraceDays';
  static const _kPreferSurround = 'preferSurroundAudio';
  static const _kExcludeSignLanguage = 'excludeSignLanguage';
  static const _kPreferredAudioLanguage = 'preferredAudioLanguage';
  static const _kHardwareVideo = 'hardwareVideoAcceleration';
  static const _kLowPowerVideo = 'lowPowerVideo';
  static const _kInternetArchive = 'internetArchiveEnabled';
  static const _kPersonalizedCategories = 'personalizedCategories';
  static const _kHiddenGenres = 'hiddenGenres';

  Future<void> load() async {
    final rows = await _db.select(_db.settings).get();
    _cache
      ..clear()
      ..addEntries(rows.map((r) => MapEntry(r.key, r.value)));
  }

  // ── typed reads (with defaults) ─────────────────────────────────────────────

  /// Auto-fetch English subtitles when a title is scanned / played.
  bool get autoDownloadSubtitles => _boolOr(_kAutoSubs, true);

  /// When a TV episode finishes, automatically play the next one if it's already
  /// downloaded (binge behaviour). On by default.
  bool get autoPlayNextEpisode => _boolOr(_kAutoPlayNext, true);

  /// Require the VPN tunnel to be up before streaming/acquiring.
  bool get requireVpn => _boolOr(_kRequireVpn, false);

  /// Auto-delete fully-watched titles after the grace period.
  bool get cleanupEnabled => _boolOr(_kCleanupEnabled, true);

  /// Days a watched file is kept before the reaper deletes it.
  int get cleanupGraceDays => _intOr(_kCleanupGraceDays, 7);
  Duration get cleanupGracePeriod => Duration(days: cleanupGraceDays);

  /// Prefer the widest audio track (5.1/7.1) over a stereo downmix.
  bool get preferSurroundAudio => _boolOr(_kPreferSurround, true);

  /// Skip sign-language (ASL/BSL) release variants and subtitles — a different
  /// cut than the standard release. Applied to both download ranking and
  /// subtitle picking.
  bool get excludeSignLanguage => _boolOr(_kExcludeSignLanguage, true);

  /// Canonical language name the user wants *dubbed audio* in (e.g.
  /// 'portuguese'); empty = no preference (English-first, today's behaviour).
  /// When set, the resolver ranks releases whose title tags this language above
  /// the rest.
  String get preferredAudioLanguage => _cache[_kPreferredAudioLanguage] ?? '';

  /// Use GPU hardware video decoding (libmpv `hwdec`). Off by default: some
  /// setups decode fine but render a solid-color frame. A box with a working
  /// iGPU should turn this ON — it offloads decoding from a weak CPU.
  bool get hardwareVideoAcceleration => _boolOr(_kHardwareVideo, false);

  /// Trade a little video quality for much lower CPU use (skip the deblocking
  /// loop filter, cheap scaling). For underpowered boxes that stutter.
  bool get lowPowerVideo => _boolOr(_kLowPowerVideo, false);

  /// Include the Internet Archive as a source: its public-domain results in
  /// search, the "Free to Watch" landing rail, and as a resolver in the
  /// acquisition chain. Off by default — deprecated in favour of the user's own
  /// Jackett indexers; kept as an opt-in for public-domain browsing.
  bool get internetArchiveEnabled => _boolOr(_kInternetArchive, false);

  /// Show personalized "Because you watch …" genre rows on the landing page,
  /// inferred from watch history + saved titles. On by default.
  bool get personalizedCategories => _boolOr(_kPersonalizedCategories, true);

  /// Genre-row keys ("tv:10765") the user has hidden from the landing page.
  Set<String> get hiddenGenres {
    final raw = _cache[_kHiddenGenres] ?? '';
    return raw.split(',').where((s) => s.isNotEmpty).toSet();
  }

  // ── setters ─────────────────────────────────────────────────────────────────

  Future<void> setAutoDownloadSubtitles(bool v) => _setBool(_kAutoSubs, v);
  Future<void> setAutoPlayNextEpisode(bool v) => _setBool(_kAutoPlayNext, v);
  Future<void> setRequireVpn(bool v) => _setBool(_kRequireVpn, v);
  Future<void> setCleanupEnabled(bool v) => _setBool(_kCleanupEnabled, v);
  Future<void> setCleanupGraceDays(int v) => _setString(_kCleanupGraceDays, '$v');
  Future<void> setPreferSurroundAudio(bool v) => _setBool(_kPreferSurround, v);
  Future<void> setExcludeSignLanguage(bool v) =>
      _setBool(_kExcludeSignLanguage, v);
  Future<void> setPreferredAudioLanguage(String v) =>
      _setString(_kPreferredAudioLanguage, v);
  Future<void> setHardwareVideoAcceleration(bool v) =>
      _setBool(_kHardwareVideo, v);
  Future<void> setLowPowerVideo(bool v) => _setBool(_kLowPowerVideo, v);
  Future<void> setInternetArchiveEnabled(bool v) =>
      _setBool(_kInternetArchive, v);
  Future<void> setPersonalizedCategories(bool v) =>
      _setBool(_kPersonalizedCategories, v);

  /// Hide a genre row (persist its key); the landing page drops it.
  Future<void> hideGenre(String key) {
    final next = {...hiddenGenres, key};
    return _setString(_kHiddenGenres, next.join(','));
  }

  /// Un-hide every genre row (a "reset" for the personalized rows).
  Future<void> clearHiddenGenres() => _setString(_kHiddenGenres, '');

  // ── internals ───────────────────────────────────────────────────────────────

  bool _boolOr(String key, bool fallback) {
    final v = _cache[key];
    return v == null ? fallback : v == 'true';
  }

  int _intOr(String key, int fallback) => int.tryParse(_cache[key] ?? '') ?? fallback;

  Future<void> _setBool(String key, bool value) => _setString(key, '$value');

  Future<void> _setString(String key, String value) async {
    _cache[key] = value;
    await _db.into(_db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(key: key, value: value),
        );
    notifyListeners();
  }
}
