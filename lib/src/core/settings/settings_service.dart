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
  static const _kRequireVpn = 'requireVpn';
  static const _kCleanupEnabled = 'cleanupEnabled';
  static const _kCleanupGraceDays = 'cleanupGraceDays';
  static const _kPreferSurround = 'preferSurroundAudio';

  Future<void> load() async {
    final rows = await _db.select(_db.settings).get();
    _cache
      ..clear()
      ..addEntries(rows.map((r) => MapEntry(r.key, r.value)));
  }

  // ── typed reads (with defaults) ─────────────────────────────────────────────

  /// Auto-fetch English subtitles when a title is scanned / played.
  bool get autoDownloadSubtitles => _boolOr(_kAutoSubs, true);

  /// Require the VPN tunnel to be up before streaming/acquiring.
  bool get requireVpn => _boolOr(_kRequireVpn, false);

  /// Auto-delete fully-watched titles after the grace period.
  bool get cleanupEnabled => _boolOr(_kCleanupEnabled, true);

  /// Days a watched file is kept before the reaper deletes it.
  int get cleanupGraceDays => _intOr(_kCleanupGraceDays, 7);
  Duration get cleanupGracePeriod => Duration(days: cleanupGraceDays);

  /// Prefer the widest audio track (5.1/7.1) over a stereo downmix.
  bool get preferSurroundAudio => _boolOr(_kPreferSurround, true);

  // ── setters ─────────────────────────────────────────────────────────────────

  Future<void> setAutoDownloadSubtitles(bool v) => _setBool(_kAutoSubs, v);
  Future<void> setRequireVpn(bool v) => _setBool(_kRequireVpn, v);
  Future<void> setCleanupEnabled(bool v) => _setBool(_kCleanupEnabled, v);
  Future<void> setCleanupGraceDays(int v) => _setString(_kCleanupGraceDays, '$v');
  Future<void> setPreferSurroundAudio(bool v) => _setBool(_kPreferSurround, v);

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
