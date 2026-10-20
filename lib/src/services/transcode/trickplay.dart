import 'dart:convert';

/// Seek-bar preview thumbnails ("trickplay", as Plex/Jellyfin call it): one
/// small frame every [kTrickplayIntervalSeconds], packed into JPEG grids
/// ("sheets") of [kTrickplayColumns] × [kTrickplayRows] tiles. Generated once
/// per file in the background by [TrickplayService]; at hover time the player
/// only crops a tile out of an already-decoded image, so the preview costs
/// nothing during playback. Everything in this file is pure + tested.

/// Seconds of video each tile stands for.
const kTrickplayIntervalSeconds = 10;

/// Tile size in pixels — fixed (letterboxed) whatever the video's aspect, so
/// the grid geometry never needs probing back out of the image.
const kTrickplayTileWidth = 192;
const kTrickplayTileHeight = 108;

/// Tiles per sheet row / column. 100 tiles ≈ 17 minutes of video per sheet;
/// a 1920×1080 sheet decodes to ~8 MB, so a 2-hour film holds ~66 MB at most.
const kTrickplayColumns = 10;
const kTrickplayRows = 10;
const kTrickplayTilesPerSheet = kTrickplayColumns * kTrickplayRows;

/// The marker file whose presence means a cache directory is complete. Written
/// last, after ffmpeg succeeded and every expected sheet exists.
const kTrickplayManifestName = 'manifest.json';

/// The sheet file name for a 0-based [index] (what ffmpeg writes with
/// `-start_number 0` and the `sheet_%03d.jpg` pattern).
String trickplaySheetName(int index) =>
    'sheet_${index.toString().padLeft(3, '0')}.jpg';

/// The ffmpeg output pattern matching [trickplaySheetName].
const kTrickplaySheetPattern = 'sheet_%03d.jpg';

/// A cache key for one file *as it is now*: its path, size and modification
/// time. A downscale (new size/mtime) or a download that's still being written
/// (mtime moving) gets a different key, so stale or partial thumbnails are never
/// served for a changed file. FNV-1a 64-bit, hex — stable across runs.
String trickplayKey({
  required String path,
  required int sizeBytes,
  required int modifiedMs,
}) {
  var hash = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  for (final unit in utf8.encode('$path|$sizeBytes|$modifiedMs')) {
    hash ^= unit;
    hash *= prime; // native ints wrap mod 2^64, which is what FNV wants
  }
  // Hex each 32-bit half: a native int is signed, and `toUnsigned(64)` can't
  // make a value with the top bit set non-negative, so formatting the whole
  // thing gave a leading '-' for about half of all keys.
  String half(int v) => (v & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
  return half(hash >> 32) + half(hash);
}

/// How many tiles a video of [durationSeconds] needs (at least one).
int trickplayTileCount(double durationSeconds) {
  if (durationSeconds <= 0) return 1;
  final n = (durationSeconds / kTrickplayIntervalSeconds).ceil();
  return n < 1 ? 1 : n;
}

/// How many sheets [tileCount] tiles fill.
int trickplaySheetCount(int tileCount) =>
    (tileCount + kTrickplayTilesPerSheet - 1) ~/ kTrickplayTilesPerSheet;

/// ffmpeg arguments that write the sheets for [input] into [outputDir].
///
/// Cheap by construction: `-skip_frame nokey` decodes **keyframes only** (the
/// expensive part of a 4K decode is everything between them), `fps` picks one
/// frame per interval (repeating the last keyframe across a long GOP), and
/// two threads keep it a background job. Audio/subtitles are never touched.
List<String> trickplayArgs({required String input, required String outputDir}) {
  const w = kTrickplayTileWidth, h = kTrickplayTileHeight;
  return [
    '-hide_banner',
    '-nostdin',
    '-loglevel', 'error',
    '-threads', '2',
    '-skip_frame', 'nokey',
    '-i', input,
    '-map', '0:v:0',
    '-an', '-sn', '-dn',
    '-vf',
    'fps=1/$kTrickplayIntervalSeconds,'
        'scale=$w:$h:force_original_aspect_ratio=decrease,'
        'pad=$w:$h:(ow-iw)/2:(oh-ih)/2,'
        'tile=${kTrickplayColumns}x$kTrickplayRows',
    '-q:v', '6',
    '-start_number', '0',
    '-y',
    '$outputDir/$kTrickplaySheetPattern',
  ];
}

/// A finished set of sheets for one file, read from its manifest.
class TrickplayManifest {
  const TrickplayManifest({
    required this.tileCount,
    required this.sheetCount,
    this.intervalSeconds = kTrickplayIntervalSeconds,
    this.tileWidth = kTrickplayTileWidth,
    this.tileHeight = kTrickplayTileHeight,
    this.columns = kTrickplayColumns,
    this.rows = kTrickplayRows,
  });

  final int tileCount;
  final int sheetCount;
  final int intervalSeconds;
  final int tileWidth;
  final int tileHeight;
  final int columns;
  final int rows;

  Map<String, dynamic> toJson() => {
        'version': 1,
        'tileCount': tileCount,
        'sheetCount': sheetCount,
        'intervalSeconds': intervalSeconds,
        'tileWidth': tileWidth,
        'tileHeight': tileHeight,
        'columns': columns,
        'rows': rows,
      };

  /// Null for anything malformed — a bad manifest just means "no previews".
  static TrickplayManifest? tryParse(String text) {
    try {
      final j = jsonDecode(text);
      if (j is! Map<String, dynamic>) return null;
      int? n(String k) => (j[k] as num?)?.toInt();
      final tiles = n('tileCount'), sheets = n('sheetCount');
      final interval = n('intervalSeconds'), w = n('tileWidth');
      final h = n('tileHeight'), cols = n('columns'), rows = n('rows');
      if ([tiles, sheets, interval, w, h, cols, rows]
          .any((v) => v == null || v <= 0)) {
        return null;
      }
      return TrickplayManifest(
        tileCount: tiles!,
        sheetCount: sheets!,
        intervalSeconds: interval!,
        tileWidth: w!,
        tileHeight: h!,
        columns: cols!,
        rows: rows!,
      );
    } catch (_) {
      return null;
    }
  }

  /// Which sheet, and which tile within it, shows the moment [at]. Clamped to
  /// the last tile, so hovering the very end still shows something.
  ({int sheet, int column, int row}) tileAt(Duration at) {
    var index = at.inMilliseconds ~/ (intervalSeconds * 1000);
    if (index < 0) index = 0;
    if (index >= tileCount) index = tileCount - 1;
    final perSheet = columns * rows;
    final within = index % perSheet;
    return (
      sheet: index ~/ perSheet,
      column: within % columns,
      row: within ~/ columns,
    );
  }
}
