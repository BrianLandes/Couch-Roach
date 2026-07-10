import '../../data/db/database.dart';
import 'library_path_parse.dart';

/// One cell in the library grid: a standalone [ItemEntry] (a movie or a loose
/// file), a [ShowEntry] collapsing all downloaded episodes of one TMDB-matched
/// show, or an [UnmatchedShowEntry] collapsing episodes that clearly belong to
/// one show (same folder) but haven't matched TMDB yet.
sealed class LibraryEntry {
  const LibraryEntry();
}

class ItemEntry extends LibraryEntry {
  const ItemEntry(this.item);
  final LibraryItem item;
}

class ShowEntry extends LibraryEntry {
  const ShowEntry({
    required this.tmdbId,
    required this.name,
    required this.posterPath,
    required this.episodeCount,
  });
  final int tmdbId;
  final String name;
  final String? posterPath;
  final int episodeCount;
}

/// A group of episodes that share a show folder but have no TMDB match — so the
/// grid shows one tile instead of a pile of loose episodes. It has no poster or
/// detail page (nothing to link to); tapping it lists its files to play.
class UnmatchedShowEntry extends LibraryEntry {
  const UnmatchedShowEntry({required this.name, required this.items});
  final String name;
  final List<LibraryItem> items;
  int get episodeCount => items.length;
}

bool _isUnmatchedTv(LibraryItem i) => i.mediaType == 'tv' && i.tmdbId == null;

/// Collapse a flat library list. A TMDB-matched show (`tv` + `tmdbId`) becomes a
/// [ShowEntry]; two-or-more unmatched episodes sharing a show folder become an
/// [UnmatchedShowEntry]; everything else (movies, lone files) stays an
/// [ItemEntry]. Order follows each group's first-seen position so the grid is
/// stable as episodes come and go. Pure + tested.
List<LibraryEntry> groupLibraryItems(List<LibraryItem> items) {
  final byShow = <int, List<LibraryItem>>{};
  final byFolder = <String, List<LibraryItem>>{};
  for (final item in items) {
    if (item.mediaType == 'tv' && item.tmdbId != null) {
      byShow.putIfAbsent(item.tmdbId!, () => []).add(item);
    } else if (_isUnmatchedTv(item)) {
      byFolder
          .putIfAbsent(unmatchedShowKey(item.filePath, item.title), () => [])
          .add(item);
    }
  }
  // Only fold unmatched episodes together when there are 2+ of them — a single
  // loose file stays its own tile.
  final foldedKeys = {
    for (final e in byFolder.entries)
      if (e.value.length >= 2) e.key,
  };

  final emittedShows = <int>{};
  final emittedFolders = <String>{};
  final entries = <LibraryEntry>[];
  for (final item in items) {
    final id = item.tmdbId;
    if (item.mediaType == 'tv' && id != null) {
      if (emittedShows.add(id)) {
        final eps = byShow[id]!;
        final poster = eps
            .map((e) => e.tmdbPosterPath)
            .firstWhere((p) => p != null, orElse: () => null);
        final name = eps
                .map((e) => e.tmdbName)
                .firstWhere((n) => n != null, orElse: () => null) ??
            item.title;
        entries.add(ShowEntry(
          tmdbId: id,
          name: name,
          posterPath: poster,
          episodeCount: eps.length,
        ));
      }
      continue;
    }

    if (_isUnmatchedTv(item)) {
      final key = unmatchedShowKey(item.filePath, item.title);
      if (foldedKeys.contains(key)) {
        if (emittedFolders.add(key)) {
          final eps = byFolder[key]!;
          final folder = showFolderName(item.filePath);
          entries.add(UnmatchedShowEntry(
            name: folder.isNotEmpty ? folder : item.title,
            items: eps,
          ));
        }
        continue;
      }
    }

    entries.add(ItemEntry(item));
  }
  return entries;
}
