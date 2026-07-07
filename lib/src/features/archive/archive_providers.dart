import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../injection.dart';
import '../../services/acquisition/archive_browse_service.dart';

/// Curated public-domain picks from the Internet Archive for the landing
/// "Free to Watch" rail. Empty (rail hidden) if IA is unreachable.
final archivePicksProvider = FutureProvider<List<ArchiveItem>>(
  (ref) => getIt<ArchiveBrowseService>().popularPicks(),
);
