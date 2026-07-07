import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:injectable/injectable.dart';

/// Computes the OpenSubtitles moviehash — the preferred subtitle search key
/// (HANDOFF §4.6 step 2). It's `filesize` plus the sum of the first and last
/// 64 KB read as little-endian unsigned 64-bit ints (mod 2^64), rendered as a
/// 16-char lowercase hex string.
abstract class MovieHasher {
  Future<String> hash(String path);
}

@LazySingleton(as: MovieHasher)
class OpenSubtitlesMovieHasher implements MovieHasher {
  static const _chunk = 64 * 1024; // 64 KB

  @override
  Future<String> hash(String path) async {
    final file = File(path);
    final length = await file.length();
    final raf = await file.open();
    try {
      var acc = length; // native 64-bit int addition wraps mod 2^64
      acc = _addChunk(acc, await _readAt(raf, 0, min(_chunk, length)));
      final tail = length > _chunk ? length - _chunk : 0;
      acc = _addChunk(acc, await _readAt(raf, tail, min(_chunk, length)));
      return _toHex(acc);
    } finally {
      await raf.close();
    }
  }

  Future<Uint8List> _readAt(RandomAccessFile raf, int offset, int count) async {
    await raf.setPosition(offset);
    return raf.read(count);
  }

  int _addChunk(int acc, Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final words = bytes.length ~/ 8; // ignore a trailing partial word
    for (var i = 0; i < words; i++) {
      acc += data.getUint64(i * 8, Endian.little);
    }
    return acc;
  }

  String _toHex(int value) {
    final bytes = (ByteData(8)..setInt64(0, value, Endian.big)).buffer.asUint8List();
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
