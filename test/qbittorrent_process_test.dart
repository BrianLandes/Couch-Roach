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
  });

  test('baseUrl points at the fixed localhost endpoint', () {
    expect(
      QbittorrentProcess.baseUrl,
      'http://127.0.0.1:${QbittorrentProcess.webUiPort}',
    );
  });
}
