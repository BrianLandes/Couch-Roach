import 'package:couch_roach/src/services/acquisition/archive_browse_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArchiveDetail.fromMetadata', () {
    final detail = ArchiveDetail.fromMetadata('notld', {
      'metadata': {
        'title': 'Night of the Living Dead',
        'date': '1968-10-01',
        'creator': 'George A. Romero',
        'description': '<p>A group is <b>trapped</b>.<br>Zombies &amp; more.</p>',
      },
      'files': [
        {'name': 'notld.mp4', 'format': 'h.264', 'size': '600000000'},
        {'name': 'notld.ogv', 'format': 'Ogg Video', 'size': '450000000'},
        {'name': 'notld_meta.xml', 'format': 'Metadata', 'size': '2000'},
        {'name': 'notld_archive.torrent', 'format': 'Archive BitTorrent'},
      ],
    });

    test('parses title, creator, and year (from a date field)', () {
      expect(detail.title, 'Night of the Living Dead');
      expect(detail.creator, 'George A. Romero');
      expect(detail.year, 1968);
    });

    test('strips HTML and entities from the description', () {
      expect(detail.description, 'A group is trapped.\nZombies & more.');
    });

    test('keeps only video files, largest first', () {
      expect(detail.videos.map((v) => v.name), ['notld.mp4', 'notld.ogv']);
      expect(detail.videos.first.sizeBytes, 600000000);
    });

    test('falls back to the identifier when title is missing', () {
      final d = ArchiveDetail.fromMetadata('some_id', {'metadata': {}});
      expect(d.title, 'some_id');
      expect(d.year, isNull);
      expect(d.videos, isEmpty);
    });

    test('reads year straight from a year field too', () {
      final d = ArchiveDetail.fromMetadata('x', {
        'metadata': {'year': '1925'}
      });
      expect(d.year, 1925);
    });
  });
}
