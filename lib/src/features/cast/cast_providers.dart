import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/tmdb/credits.dart';
import '../../injection.dart';
import '../../services/discovery/tmdb_client.dart';
import 'cast_assembly.dart';

typedef EpisodeRef = ({int tmdbId, int season, int episode});

/// The assembled cast for a TV episode (guest stars → episode cast → main cast).
final episodeCastProvider =
    FutureProvider.family<List<CastMember>, EpisodeRef>((ref, a) async {
  final tmdb = getIt<DiscoveryClient>();
  final ep = await tmdb.episodeCredits(a.tmdbId, a.season, a.episode);
  final main = await tmdb.tvCast(a.tmdbId);
  return assembleEpisodeCast(
    guestStars: ep.guestStars,
    episodeCast: ep.cast,
    mainCast: main,
  );
});

/// A movie's cast.
final movieCastProvider =
    FutureProvider.family<List<CastMember>, int>((ref, tmdbId) async {
  return getIt<DiscoveryClient>().movieCast(tmdbId);
});

/// An actor's "known for" titles, ranked and trimmed for the grid.
final personKnownForProvider =
    FutureProvider.family<List<PersonCredit>, int>((ref, personId) async {
  final credits = await getIt<DiscoveryClient>().personCredits(personId);
  return knownForTitles(credits);
});
