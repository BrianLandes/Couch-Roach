import 'dart:io';
import 'dart:typed_data';

import 'package:couch_roach/src/services/subtitles/movie_hasher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  final hasher = OpenSubtitlesMovieHasher();

  setUp(() async => tmp = await Directory.systemTemp.createTemp('cr_hash'));
  tearDown(() async => tmp.deleteSync(recursive: true));

  Future<String> writeFile(String name, Uint8List bytes) async {
    final f = File('${tmp.path}/$name');
    await f.writeAsBytes(bytes);
    return f.path;
  }

  test('zero-filled file: hash equals the filesize (chunks sum to 0)', () async {
    // 200000 bytes of zeros → hash = 200000 = 0x30D40.
    final path = await writeFile('zeros.bin', Uint8List(200000));
    expect(await hasher.hash(path), '0000000000030d40');
  });

  test('adds little-endian 64-bit words from the head chunk', () async {
    // First 8 bytes little-endian = 1, rest zeros → hash = filesize + 1.
    final bytes = Uint8List(200000);
    bytes[0] = 1; // LE uint64 value 1 in the first word
    final path = await writeFile('one.bin', bytes);
    expect(await hasher.hash(path), '0000000000030d41');
  });

  test('always returns 16 lowercase hex chars', () async {
    final path = await writeFile('small.bin', Uint8List(1000));
    final h = await hasher.hash(path);
    expect(h, matches(RegExp(r'^[0-9a-f]{16}$')));
  });
}
