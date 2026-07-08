import 'package:couch_roach/src/services/acquisition/qbittorrent_process.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QbittorrentProcess.defaultConfig', () {
    final conf = QbittorrentProcess.defaultConfig();

    test('binds the Web API to localhost on the fixed port', () {
      expect(conf, contains('WebUI\\Address=${QbittorrentProcess.webUiHost}'));
      expect(conf, contains('WebUI\\Port=${QbittorrentProcess.webUiPort}'));
      expect(QbittorrentProcess.webUiHost, '127.0.0.1');
    });

    test('disables localhost auth so the client connects credential-free', () {
      expect(conf, contains('WebUI\\LocalHostAuth=false'));
    });

    test('pre-accepts the legal notice so the headless daemon never blocks', () {
      expect(conf, contains('[LegalNotice]'));
      expect(conf, contains('Accepted=true'));
    });

    test('starts minimized to tray so the Windows GUI exe stays out of sight', () {
      expect(conf, contains('General\\StartMinimized=true'));
      expect(conf, contains('General\\MinimizeToTray=true'));
    });

    test('disables the update check so the GUI exe never prompts on launch', () {
      expect(conf, contains('General\\CheckForUpdates=false'));
    });

    test('seeds WebUI credentials so qBittorrent 5.x will start the Web API', () {
      // Without a password set, qBittorrent 5.x logs "Credentials are not set"
      // and never binds the Web API.
      expect(conf, contains('WebUI\\Username=admin'));
      expect(conf, contains('WebUI\\Password_PBKDF2=@ByteArray('));
    });
  });

  test('baseUrl points at the fixed localhost endpoint', () {
    expect(
      QbittorrentProcess.baseUrl,
      'http://127.0.0.1:${QbittorrentProcess.webUiPort}',
    );
  });

  group('enforceConfig', () {
    test('re-enables WebUI when an existing config turned it off', () {
      const stale = '[Preferences]\n'
          'WebUI\\Enabled=false\n'
          'WebUI\\Port=8080\n';
      final merged = QbittorrentProcess.enforceConfig(stale);
      expect(merged, contains('WebUI\\Enabled=true'));
      expect(merged, contains('WebUI\\Port=${QbittorrentProcess.webUiPort}'));
      expect(merged, isNot(contains('WebUI\\Enabled=false')));
      expect(merged, isNot(contains('WebUI\\Port=8080')));
    });

    test('preserves unrelated sections and keys', () {
      const existing = '[Preferences]\n'
          'WebUI\\Enabled=false\n'
          'Downloads\\SavePath=D:/Media\n'
          '\n'
          '[BitTorrent]\n'
          'Session\\Port=54321\n';
      final merged = QbittorrentProcess.enforceConfig(existing);
      expect(merged, contains('Downloads\\SavePath=D:/Media'));
      expect(merged, contains('[BitTorrent]'));
      expect(merged, contains('Session\\Port=54321'));
      expect(merged, contains('WebUI\\Enabled=true')); // still enforced
    });

    test('handles values containing = signs', () {
      const existing = '[Preferences]\n'
          'General\\SomeToken=a=b=c\n';
      final merged = QbittorrentProcess.enforceConfig(existing);
      expect(merged, contains('General\\SomeToken=a=b=c'));
    });

    test('a null (fresh) config comes out fully seeded', () {
      final merged = QbittorrentProcess.enforceConfig(null);
      expect(merged, contains('[LegalNotice]'));
      expect(merged, contains('Accepted=true'));
      expect(merged, contains('WebUI\\Enabled=true'));
      expect(merged, contains('WebUI\\LocalHostAuth=false'));
    });

    test('is idempotent — enforcing twice changes nothing further', () {
      final once = QbittorrentProcess.enforceConfig(null);
      final twice = QbittorrentProcess.enforceConfig(once);
      expect(twice, once);
    });

    test('preserves a user-set WebUI password instead of overwriting it', () {
      const existing = '[Preferences]\n'
          'WebUI\\Username=me\n'
          'WebUI\\Password_PBKDF2=@ByteArray(custom==:hash==)\n';
      final merged = QbittorrentProcess.enforceConfig(existing);
      expect(merged, contains('WebUI\\Username=me'));
      expect(merged, contains('WebUI\\Password_PBKDF2=@ByteArray(custom==:hash==)'));
      // The seeded default must not be added on top.
      expect(merged, isNot(contains('WebUI\\Username=admin')));
    });

    test('the @ByteArray password entry is written unquoted', () {
      final conf = QbittorrentProcess.enforceConfig(null);
      // QSettings only treats @ByteArray(...) as a byte-array type when unquoted.
      expect(conf, isNot(contains('"@ByteArray(')));
    });
  });
}
