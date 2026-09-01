import 'package:couch_roach/src/core/settings/settings_service.dart';
import 'package:couch_roach/src/data/db/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SettingsService settings;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsService(db);
    await settings.load();
  });
  tearDown(() => db.close());

  test('defaults apply when nothing is stored', () {
    expect(settings.autoDownloadSubtitles, isTrue);
    expect(settings.requireVpn, isFalse);
    expect(settings.cleanupEnabled, isTrue);
    expect(settings.cleanupGraceDays, 7);
    expect(settings.cleanupGracePeriod, const Duration(days: 7));
    expect(settings.preferSurroundAudio, isTrue);
    expect(settings.excludeSignLanguage, isTrue);
    expect(settings.internetArchiveEnabled, isFalse); // deprecated → off
    // 'auto' is what media_kit already applies on desktop, so the default
    // leaves decoding exactly as it was.
    expect(settings.hwdecMode, 'auto');
    // Hardware *rendering* is a separate knob and stays off by default.
    expect(settings.hardwareVideoAcceleration, isFalse);
    // Routine log chatter is opt-in.
    expect(settings.verboseLogging, isFalse);
    // Video output is uncapped unless the user opts in.
    expect(settings.maxVideoHeight, 0);
    // Downloads aren't resolution-capped by default either.
    expect(settings.maxDownloadHeight, 0);
  });

  test('max download height persists', () async {
    await settings.setMaxDownloadHeight(1080);
    expect(settings.maxDownloadHeight, 1080);

    final reloaded = SettingsService(db);
    await reloaded.load();
    expect(reloaded.maxDownloadHeight, 1080);
  });

  test('max video height persists', () async {
    await settings.setMaxVideoHeight(1080);
    expect(settings.maxVideoHeight, 1080);

    final reloaded = SettingsService(db);
    await reloaded.load();
    expect(reloaded.maxVideoHeight, 1080);
  });

  test('verbose logging persists', () async {
    await settings.setVerboseLogging(true);
    expect(settings.verboseLogging, isTrue);

    final reloaded = SettingsService(db);
    await reloaded.load();
    expect(reloaded.verboseLogging, isTrue);
  });

  test('hwdec mode persists and is independent of hardware rendering',
      () async {
    await settings.setHwdecMode('d3d11va');
    expect(settings.hwdecMode, 'd3d11va');
    expect(settings.hardwareVideoAcceleration, isFalse); // untouched

    final reloaded = SettingsService(db);
    await reloaded.load();
    expect(reloaded.hwdecMode, 'd3d11va');
  });

  test('Internet Archive toggle flips and persists', () async {
    expect(settings.internetArchiveEnabled, isFalse);
    await settings.setInternetArchiveEnabled(true);
    expect(settings.internetArchiveEnabled, isTrue);

    final reloaded = SettingsService(db);
    await reloaded.load();
    expect(reloaded.internetArchiveEnabled, isTrue);
  });

  test('setters update the live cache', () async {
    await settings.setAutoDownloadSubtitles(false);
    await settings.setRequireVpn(true);
    await settings.setCleanupGraceDays(14);

    expect(settings.autoDownloadSubtitles, isFalse);
    expect(settings.requireVpn, isTrue);
    expect(settings.cleanupGraceDays, 14);
    expect(settings.cleanupGracePeriod, const Duration(days: 14));
  });

  test('values persist across a reload (survive a restart)', () async {
    await settings.setRequireVpn(true);
    await settings.setCleanupGraceDays(30);

    final reloaded = SettingsService(db);
    await reloaded.load();

    expect(reloaded.requireVpn, isTrue);
    expect(reloaded.cleanupGraceDays, 30);
    expect(reloaded.autoDownloadSubtitles, isTrue); // untouched → default
  });

  test('notifies listeners on change', () async {
    var notified = 0;
    settings.addListener(() => notified++);
    await settings.setPreferSurroundAudio(false);
    expect(notified, 1);
  });
}
