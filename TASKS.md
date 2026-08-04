# TASKS

The task board for **Couch Roach**. This file is the source of truth for dev
work — read it first when resuming, and keep it current as work progresses.

**Status** is tracked by which section a task sits in. Move a task down the list
as it advances: `Backlog` → `To Do` → `In Progress` → `Done`. When a task is
finished and the change is committed, delete it from here (git history is the
archive) or move it under `Done` if it's worth a short-lived record.

**Priority** — `p1` (highest) … `p4` (default), shown as a tag on each task.

_Format: each task is a `###` heading with a checkbox line and optional detail
underneath. Keep the detail that matters (decisions, design notes, follow-ups);
drop the rest._

---

## In Progress

_Aim for one task here at a time._

### Alexa inbox consumer (poll-and-drain voice-added titles) · `p2`

- [ ] App-side consumer for the Alexa voice inbox (Cloudflare Worker + KV queue; upstream already built/deployed). Poll-and-drain on demand: startup + landing-page re-entry, throttled 30s.

Implemented:
- SavedTitles gets nullable `source` column (schemaVersion 6→7 + migration). Voice titles land on the Want-to-watch list tagged `source='alexa'` (decision: fileless watchlist, not the file-backed LibraryItems).
- `AppConfig.alexaInboxBaseUrl` (defaulted to public Worker URL) + `alexaInboxToken` (secret via `--dart-define`; `hasAlexaInbox` guard).
- `AlexaInboxService` (`@LazySingleton`): `drain()` (GET /pending → resolve each → POST /ack successes; `_busy` + 30s throttle; silent on network blips) and `addFromAlexa()` (top TMDB hit, movies-first then TV fallback; no-match logged+swallowed+acked; dedupe inherent via `{tmdbId,mediaType}` PK upsert).
- `setWantToWatch` gains optional source; origin is first-write-wins (never relabels an already-saved title).
- Startup drain in `main()`; landing-page re-entry via RouteObserver + RouteAware on LibraryScreen.

Tests: `alexa_inbox_service_test.dart` (resolve/fallback/no-match/dedupe/source-preservation/guard) + extended saved_titles. Full suite 468 green, analyze clean.

Caveat: TmdbClient swallows network errors → a TMDB outage reads as no-match (acked/dropped); drain gates on `hasTmdbKey` to reduce that window. End-to-end drain vs live Worker is the handoff's manual curl plan.

Follow-up (not done): requires `ALEXA_INBOX_TOKEN` in `dart_define.json` before the feature activates.

---

## To Do

_Queued and ready to pick up._

### Player overlay still strands sometimes after a while · `p2`

- [ ] The title / back / Next Episode overlay still **sometimes** fails to come up after long playback — a recurrence of the bug the paused-persistence + global-key reveal fix (commit 32ef09d) was meant to close.
- **Stab taken** (unverified — device-only, intermittent): broadened the reveal to a canonical `MouseRegion` (`onEnter`/`onHover`, fires even when the raw Listener's hover is shadowed by media_kit's own regions) layered over the existing `Listener` (hover/move + now pointer-signal/scroll), plus the existing `HardwareKeyboard` key reveal and play-state persistence. **Needs on-device confirmation it actually fixes it.**
- If it recurs, go deeper: (1) does `_controlsVisible` get stuck `false` while `_isPlaying` stays true (neither idle-reveal nor paused-persistence kicks in)? (2) does media_kit's own controls visibility diverge from ours (theirs shows, ours doesn't)? Consider driving our overlay off media_kit's own controls-visible signal instead of a parallel timer, or a periodic re-assert. Repro on both mouse and remote.

- [ ] Add the app icon to the Windows launcher.

### Disable "Download next" when the next episode hasn't aired · `p4`

- [ ] The Download-next button should know whether the next episode has aired, and be disabled with a message if it hasn't aired yet.

### Hydrate Alexa-queued titles with their TMDB id for the details page · `p3`

- [ ] Ensure titles acquired from the Alexa voice queue carry their TMDB id (and media type — movie vs TV show) so that pulling one up on the details page can fill in the richer TMDB profile (overview, cast, seasons, artwork, etc.).

Follow-up to the [[alexa-inbox-consumer]] work. `addFromAlexa()` already resolves the top TMDB hit and upserts on a `{tmdbId, mediaType}` PK, so the id should be present on the SavedTitles row — verify that end to end: (1) the id actually persists for Alexa-sourced titles, and (2) the details page reads it and hydrates the full profile rather than showing only the sparse queued fields. Cover both movie and TV-show paths (the resolver is movies-first with a TV fallback).

---

## Backlog

_Captured but not yet queued for current work._

### perf: pause torrent activity during playback (weak box) · `p3`

- [ ] Biggest remaining perf lever for the low-end TV box (follow-up to commit 9919819). While a video plays, the qBittorrent daemon seeding/downloading in the background contends for CPU + disk + network and causes stutter. Pause non-essential torrents during playback, resume on exit.

Design (the tricky part is not pausing the torrent that feeds a LIVE stream):
- On player open: snapshot active torrents, pause all EXCEPT the one downloading the currently-playing file; on player dispose: resume exactly those.
- Mapping the current file → its torrent needs the torrent save path. `TorrentStatus` doesn't carry `save_path` today; either add it (from `/torrents/info`) and match by prefix, OR thread an explicit `isLiveStream` flag through `PlayerArgs` (archive_play sets it true; local library playback false → safe to pause everything). The PlayerArgs flag is simpler + reliable.
- Gate behind a setting "Pause downloads while watching" (default ON is reasonable for this box). SettingsService pattern already established.
- Daemon already has `setPaused({hash, paused})` + `listTorrents()`; may want a `pauseAll`/`resumeAll` convenience.

Secondary perf ideas (lower impact, note only): stagger the landing page's concurrent TMDB provider loads + poster decodes on startup; reduce/throttle background polling (VPN 5s, downloads ~1.5s) while a video plays; consider capping qBittorrent global connection/rate limits on a weak box.

### Discovery: learn which TMDB categories to show · `p4`

- [ ] Follow-up to the category-rows feature (commit 2e62a08). Landing rows are a FIXED starter set today: TV Shows (trending), Movies (trending), Documentaries (genre 99). Make categories smarter / personalized:
- Derive from watch history (favor genres the user watches; TMDB `genre_ids` are on each result).
- Or let the user pick which rows to show (ties into the Settings screen).
- Possibly rotate/seasonal ("Top rated", "New this month" via discover date filters).

Wiring extends easily: add a provider (`discoverMovies(genreId:)` / trending / popular) → map to `DiscoverTile` → add a `_DiscoverRail` on the landing. The hard part is the selection logic. Overlaps the deferred personalization fork (HANDOFF §9) and the "For You" rail.

### Windows: first-run "unknown developer" SmartScreen alert · `p4` · due 2026-08-01

- [ ] Running the exe for the first time comes up with a red Windows alert saying "unknown developer" and I have to hit "Run anyways". [windows]

### Jackett opens a command prompt on top of the window (Windows) · `p4`

- [ ] Jackett on Windows opens a command prompt on top of my window when I open it. Should run hidden (the qBittorrent-nox pattern).

### qBittorrent still prompts for its update (Windows) · `p4`

- [ ] qBittorrent on Windows still asks if I want to download the update. Should be suppressed for the invisible daemon.

---

## Done

_Finished work worth a short record; prune freely — git history is the archive._

### Rework "New Episodes" — only truly-new episodes for caught-up shows · `p2`

- [x] The rail used to surface any show with a later aired episode than the one you watched — so a half-watched season showed your *backlog* as "new." Now a show qualifies only when **(1)** your furthest *finished* episode was the latest aired when you finished it (you were caught up) **and (2)** a new episode has aired since. **No new persisted metadata** — computed from data we already had: `LibraryItems.season/episode` + `WatchHistory.lastWatchedAt`/`completed` + TMDB air dates (live). `latestWatchedEpisodePerShow` now filters to `completed = true` (so in-progress and `advanceToNextEpisode`-seeded rows don't inflate "furthest") and carries `lastWatchedAt` on `WatchedShow`. New pure helper `hasNewEpisodeSinceCaughtUp({higherRankedAirDates, lastWatchedAt, now})` replaces `hasNewerAiredSeason`/`hasLaterAiredEpisode`: caught-up = nothing ranked above aired by `lastWatchedAt`; new-since = something ranked above aired after. `newEpisodesProvider` feeds it the air dates of later episodes of the watched season (season details) + later seasons (season-level dates). Caveat: judged from *current* TMDB air dates (assumes they're historically stable — bulletproofing would need a `wasCaughtUp` snapshot on completion; deemed not worth it). Tests: helper (caught-up/backlog/new-since/undated/empty/equal-instant), completed-filter + lastWatchedAt on the query. 536 green, analyze clean.

### Watched indicator on episodes (show detail) · `p3`

- [x] Each episode row on the show detail page now shows a green `check_circle` (and dims the title) when the episode has been watched. New `WatchHistoryRepository.watchCompletedEpisodes(tmdbId)` — a live left/inner join returning the show's `completed` `(season, episode)` pairs, **including episodes whose file was since reaped** (the row is flagged missing but history is kept), so the mark survives auto-cleanup. `completedEpisodesProvider` (family, live) feeds `_EpisodeList`, which passes `watched` to each `_EpisodeRow`. Watched = watch history `completed` (an in-progress episode isn't marked — it's on Continue Watching). Repo tests: completed-only, show-scoping, reaped-survival. Widget test omitted (drift stream doesn't emit reliably under the widget tester's fake clock; logic is unit-tested). 535 green, analyze clean.

### "Recently Downloaded" rail: recency window + drop watched titles · `p3`

- [x] Tightened the rail from "all managed downloads" to "recent, still-unwatched new arrivals." `watchRecentlyDownloaded` gains a `maxAge` (default **60 days**) so only downloads from the last ~month or two show, and now **excludes any title watched since it was downloaded** — those live on Continue Watching / are done. Implemented as a left join on `watchHistory` (so the rail is reactive to *both* new downloads and titles getting watched); a title drops when any of its within-window downloads has `lastWatchedAt >= its addedAt`. Using "since *this* download" (not "ever watched") means a since-reaped title that's freshly re-downloaded correctly reappears — its old history predates the new file. A watched episode drops the whole show (it's on Continue Watching). Tests: window cutoff, watched-since exclusion, old-history re-download reappears, whole-show exclusion. 532 green, analyze clean.

### Media Play/Pause key leaks to background apps (Spotify/YouTube) · `p2`

- [x] The hardware media Play/Pause key paused Couch Roach *and* propagated to background media apps (Spotify/YouTube would start). Root cause: Couch Roach never owned the OS media session, so Windows delivered the key both to the focused window (media_kit) and, via the System Media Transport Controls (SMTC), to whatever app owns the current session (Spotify). Fix: own the SMTC session while a video plays, so the key routes to Couch Roach only.
- **Native (windows/runner):** new `MediaSession` (C++/WinRT) gets `SystemMediaTransportControls` for the window (interop `GetForWindow`), enables Play/Pause, marshals `ButtonPressed` to the UI thread via `PostMessage` → a `couch_roach/media_session` method channel (`onButton`). Methods: `enable`(title)/`setPlaybackStatus`(playing)/`disable`. Wired in `flutter_window`; CMake adds the source, links `windowsapp.lib`, and disables `/WX` (+ explicit `/EHsc`) for that TU since the WinRT headers aren't warning-clean.
- **Dart:** `MediaSessionController` (Windows-only; no-op elsewhere) — the player `enable`s on open, `setPlaying` on every play-state change, `disable` on dispose, and routes `onButton` → play/pause. `_onHardwareKey` now swallows the raw media Play/Pause key **on Windows** so media_kit doesn't *also* toggle (double-toggle) — SMTC's `onButton` is the single driver (verified media_kit uses `CallbackShortcuts`, which a `HardwareKeyboard` handler returning true preempts).
- **Windows CI build: green** (after a follow-up fix — the C++/WinRT headers pull in `<experimental/coroutine>` under C++17, so the runner needed `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS`). Compiles clean; release published. Dart analyze + 528 tests green.
- ⏳ **On-device test still pending:** confirm the remote's Play/Pause pauses Couch Roach only (Spotify/YouTube no longer start), with no double-toggle. If a double-toggle shows up, the follow-up is tightening how media_kit's own key handling is suppressed.

### "Cancel download" in the inline acquire menu · `p3`

- [x] The inline acquire control's ⋮ menu (next to "Try a different source" / "Choose source…") now has a red **"Cancel download"** while a title is still downloading (`preparing` phase only — not `ready`, where cancelling would delete an already-registered, playable library file). New `cancelDownload(...)` removes the episode's own torrent (deleting partial files) or, if it's streaming from a season pack, the pack; `AcquisitionController.cancel` calls it and drops the control back to idle (a Download button). The remembered season pack is left intact (cancel ≠ "bad source"). Auto-adopt is race-safe: it only re-starts on `phase == idle` with a *live* torrent, and cancel removes it. Snackbar "Download cancelled." Test: `cancelDownload` key handling (single episode / pack-served / movie). 528 green, analyze clean.

### Season chips: download-coverage indicator · `p3`

- [x] Each season chip on the show detail page now carries a small leading icon showing how much of the season is on disk: nothing when none is downloaded, a muted download arrow (`Icons.download_rounded`) when *some* episodes are, and a green `download_done` when *all* are. A tooltip reads "N of M downloaded" / "All episodes downloaded". Pure classifier `seasonDownloadState({downloaded, total})` (total from `SeasonSummary.episodeCount`; unknown total never reads as "all"); `_SeasonChips` takes the live `localEpisodes` map so it updates as episodes land, counts per season, and drops the default selected-checkmark so the indicator is the only leading icon. Tests: classifier (none/some/all/extras/unknown-total) + a widget test asserting the chip indicator. 525 green, analyze clean.

### Prefer season packs for single episodes, and remember the pack per season · `p2`

- [x] Two changes so single-episode acquisition rides a whole-season pack (better-seeded, one consistent A/V source) and other episodes reuse it.
- **(1) Pack-first for episodes.** Flipped `JackettResolver.resolve`'s episode tiers: Tier 1 now prefers a verified **season pack** (the daemon extracts just the requested episode's file from it), Tier 2 falls back to a single-episode release, Tier 3 null. Bulk downloads already went pack-first; the source picker still lists everything.
- **(2) Remember the pack per season (persistent).** New `SeasonPackSources` table keyed `{tmdbId, season}` (schemaVersion 10→11 + migration) + `SeasonPackSourceRepository` (find/remember/forget). `acquire_play._resolveEpisodeSource` is now cache- and pack-first: a remembered pack for the show+season is reused directly — skipping the re-search and surviving a restart / the pack leaving the client — else it resolves (pack-first) and **remembers** a freshly-found pack. Also remembered when a season pack is queued by the bulk "Download" (`_tryPack`) or picked from the source list (`prepareChosenSource`); **forgotten** when the user "tries another source" off a pack-served episode (so the whole season moves off a bad pack; session-exclude also blocks re-picking it). Daemon-level Tier-0 reattach still handles the case where the pack is still live.
- **(3) Skip the pack path for a still-airing season.** A complete season pack can't exist while episodes are still to air, so `_resolveEpisodeSource` now fetches the season's TMDB episodes and, if any hasn't aired (`seasonPackWorthTrying` — false when any episode is unaired/date-less, true for an unknown/empty list so behavior is unchanged), skips the pack search and grabs the single episode (`AcquisitionResolver.resolve` gained `allowSeasonPack`, threaded through composite/IA/Jackett). Ordered cache-first so later episodes of a *complete* season reuse the remembered pack without the air-date fetch (only cache-miss pays it). Bulk season download self-corrects (a fruitless pack query falls back to per-episode), left as-is.
- Tests: resolver tier reorder + `allowSeasonPack:false`, `seasonPackWorthTrying` (complete / airing / date-less / empty), `SeasonPackSourceRepository` (remember/replace/independent keys/forget). 519 green, analyze clean. Device-verify: an episode of a *finished* season grabs the pack and a second episode reuses it; an episode of a *currently-airing* season skips the pack and grabs the single episode.

### Show detail: play local files when TMDB details won't load · `p2`

- [x] A matched show tile (correct name + poster on the landing page, from the cached row) opened a detail page that fetches `tvDetails` live; when that returned null (offline, rate-limited, no key, or a stale/wrong match) the page showed a dead-end "Not found on TMDB" and dropped the playable local files entirely. Now the null- and error-branches render `_LocalOnlyFallback`: a minimal poster/name header (from the library rows' cached `tmdbName`/`tmdbPosterPath`) plus a playable list of every local file for that tmdbId (new `localShowItemsProvider` → `LibraryRepository.localEpisodes`, season/episode-sorted, keeps loose matched files), each with a Play button. Falls back to the bare notice only when there's genuinely nothing local, so an unmatched show still reads as such. Widget test: a 404 tvDetails + a matched episode on disk renders the note + `S01E03` + Play (not the dead notice). 510 green, analyze clean.

### Remember manual audio / subtitle track per video · `p2`

- [x] Only the subtitle *offset* persisted per file; a manual audio-track or subtitle-track choice was runtime-only and reverted to the auto-pick every re-watch. Now both persist per library file and, once set, win over the auto-pick (auto still governs untouched videos). Two nullable columns on `LibraryItems` (`preferredAudioTrackId`, `preferredSubtitleTrackId`; schemaVersion 9→10 + migration); `LibraryRepository.setPreferredAudioTrack/setPreferredSubtitleTrack`. The player persists on manual `_selectAudio`/`_selectSubtitle` (skipping the synthetic "auto") and restores in `_onTracks` via `_restorePreferredTracks`: audio + embedded-subtitle tracks match by libmpv id; **"off"** (`'no'`) and embedded choices suppress the auto-English fetch (`_suppressAutoSubtitleSelect`, decided at open so there's no race); a **sidecar** subtitle (id is the `.en.srt` path — stable across sessions, detected by `_isSidecarSubId`) is left to the auto path, which reloads the same file and selects it. Manual "Download English subtitles" is unaffected (it's the explicit override). Repo test for persist/clear. 509 green, analyze clean. Device-verify the three cases: pick an alternate audio track, pick an alternate embedded subtitle, and turn subtitles off — each should stick on re-open.

### Favorite / Want-to-watch for owned movies · `p2`

- [x] An owned movie's detail page (`LibraryDetailScreen`, where `_openDetail` sends any owned movie) only had Play / Keep / Trailers / Delete — no way to Favorite or Want-to-watch it, even though the *discovery* movie page and the Favorites/Want rails already supported movies. Added `SaveTitleButtons` (Favorite + Want-to-watch, per the decision to show both) to that page's action row for a matched movie (`item.tmdbId != null`), folding the existing buttons into its `leading` slot so it's one wrapping row. Extracted `_buildActions`; matched-TV items are unchanged (they link out to the show page, which carries its own toggles). No schema/repo change — `setFavorite/setWantToWatch` already handle `mediaType: 'movie'`.

### "Recently Downloaded" landing rail · `p2`

- [x] New rail just under Continue Watching listing app-acquired titles, one tile per show, most-recently-downloaded first. `LibraryRepository.watchRecentlyDownloaded` (live drift watch): `managed = true` + present rows, ordered by `addedAt` desc, collapsed in Dart to one entry per `'<mediaType>:<tmdbId>'` (else title) keeping each show's newest file; mapped to a `DiscoverTile` off the show's canonical `tmdbName`/`tmdbPosterPath`. **Made `managed` meaningful:** it was a designed-but-never-written column, so added a `managed` field to `ScannedFile`, stamped it in `_insert`, and set `managed: true` from both acquire paths (`acquire_play`, `archive_play`); `_onConflict` now stamps `managed` one-way (an acquire sets it true even if a plain scan inserted the row first; a scan never clears it), mirroring the tmdbId rule. Only matched rows become tiles (the poster routing keys off a TMDB id) and the rail reuses `_DiscoverRail`, so it also honors the "Not interested" filter. Repo tests: managed/present filter, show-collapse + ordering, movie/tv id-namespace split, limit, scan-then-acquire race. 508 green, analyze clean.

### "Not interested" — hide a show/movie from the landing page · `p2`

- [x] Flag a show/movie **Not interested** to drop it from *every* landing-page discovery row while keeping it in search. Backed by `SavedTitles.notInterestedAt` (nullable timestamp, schemaVersion 8→9 + migration), mirroring the `keptAt` pattern; `SavedTitlesRepository.setNotInterested` + `watchNotInterested` (live `{'<mediaType>:<tmdbId>'}` set) + `watchNotInterestedTitles` (rows for the un-hide surface). Filtering is a **single point**: `_DiscoverRail` (now a `ConsumerWidget`) subtracts the not-interested set from its tiles, so all rails — trending, personalized genre rows, etc. — honor it and a rail that empties out doesn't render. `tmdbSearchProvider` unchanged (still searchable). Marking UI: a "Not interested" toggle in `SaveTitleButtons` (detail pages) **and** a long-press / right-click context menu on `DiscoverPosterCard` (new `onContextAction` on `FocusableCard` → `onLongPress`/`onSecondaryTap`). Un-hide path: a live chip list in Settings → Home screen, each chip restoring one title. Repo tests (flag/coexist/cleanup/key-set/title-list); 471+ green, analyze clean.

### Manual "find subtitles" from the player, even when auto is on · `p3`

- [x] The player's right-click "Download English subtitles" item was gated on auto-download being *off*. But auto can be on and still leave a bad/empty English track, with no way to force a re-search. Now shown whenever there's a library item + an OpenSubtitles key (dropped the `!autoDownloadSubtitles` gate). `_manualDownloadSubtitles` already re-runs the OpenSubtitles search and reports the outcome.

### Auto-play the next episode when one finishes · `p2`

- [x] There was no auto-advance — the next episode was a manual button. Now, when a TV episode finishes (`stream.completed`), the player rolls straight into the next one if it's **already downloaded** (`_maybeAutoAdvance` → `_openEpisode(_nextLocalItem)`), guarded to fire once and only for a local TV episode. Off-switch: a "Auto-play next episode" toggle in Settings → Playback (`SettingsService.autoPlayNextEpisode`, default on). When the next isn't on disk yet, the "Play Next Episode" button still stands in. Device-verify.

### "Choose source" picker + dedupe torrent candidates · `p3`

- [x] For a hard-to-find episode, blind "Try another source" felt like flip-flopping between two bad sources. Added **"Choose source…"** to the acquire button's ⋮ menu: a 10-foot picker listing every verified, ranked, deduped candidate — episode releases *and* the season packs that contain it — with size / seeders and a "Season pack" badge; picking one downloads exactly that (`AcquisitionResolver.candidates` → `sourceCandidates` → `controller.chooseSource` → `prepareChosenSource`, sharing the prepare tail via `_finishPrepared`). **Dedupe**: `dedupeTorznabResults` collapses the same torrent re-listed by several indexers (magnet infohash via `torrentInfohash`, else normalized title+size), so both the picker and blind retry offer genuinely distinct content. Extracted `rankedTorznabResults` from `pickBestTorznabResult`. Tests for infohash/dedupe/ranking/candidates. 500 green, analyze clean.

### Continue Watching: advance to the next episode when one finishes · `p2`

- [x] Finishing an episode (played to the end, or backed out during the credits past the 95% "completed" threshold) dropped the show off Continue Watching — and an *older* half-watched episode would resurface in its place, tricking a rewatch. Now the player seeds a near-zero resume on the **next** episode (when it's downloaded — usually so, since we prefetch it) via `WatchHistoryRepository.advanceToNextEpisode`, so the show stays on the rail pointing at the next episode; being most-recent, it also supersedes the older episode in the by-show dedupe. No-op if the next episode already has progress (never clobbers). Repo tests cover both. Residual edge (next episode not downloaded) unchanged — noted, not fixed.

### Manually delete downloaded shows / seasons / episodes / movies · `p2`

- [x] Delete controls at three granularities: **movie** (Delete in the LibraryDetail action row; also a "Remove from library" when the file is missing), **show** (a "Delete…" in the show detail action row → scope dialog "Season N" / "All episodes"), and **episode** (in the local Play button's overflow "more" menu, mirroring the acquire button's ellipsis). Shared: extracted the reaper's file-delete into `deleteMediaFileAndSidecars` (both the reaper and manual delete use it); new `MediaDeleter` service (`deleteItem`/`deleteItems`) hard-removes via `removeByPath` (cascades watch history — an explicit delete forgets the title, vs. the reaper's markMissing); `confirmAndDelete` UI helper (destructive dialog + count snackbar). An explicit delete ignores the keep pin; a whole-show delete also clears the show-level `keptAt`. `MediaDeleter` tests (delete + sidecar + row, missing-file, batch, isolation); reaper still green on the shared helper. 494 tests, analyze clean.

### Prefer whole season / show packs for the bulk "Download" button · `p3`

- [x] The show detail "Download…" button is now **pack-first**: one season → tries a whole-season pack before per-episode; all seasons → tries a whole-**series** pack, else each season (pack-first, else per-episode). Per-episode paradigm unchanged for inline episode Downloads + next-episode prefetch. New: `FilenameMediaInfo.isShowPack` + `showPackResults` + a `showPack` tvsearch query shape; `AcquisitionResolver.resolveSeasonPack`/`resolveShowPack` (null defaults; Jackett implements; composite fans out; IA switched to `extends` for the defaults). `acquire_play` gained `_tryPack` + `_acquireSeason` and returns a `BulkDownloadResult` (packs vs episodes) the snackbar reports. Skips already-local/already-downloading; a pack keyed per-season (or per-show) so its episodes dedupe. Downloaded pack → existing scan + folder-fold hydrates episodes. Content-agnostic (just new query shapes). Tests: isShowPack, showPackResults, buildTorznabUri showPack, resolveSeasonPack/resolveShowPack. 490 green, analyze clean.

### Move keyed Windows builds to a private dist repo (Option A) · `p1`

- [x] Publishing was moved off the public repo so the keyed exe is never world-downloadable. `windows-build.yml` re-enabled (push→main) but now publishes the app release to **`BrianLandes/couch-roach-dist`** via a `DIST_REPO_TOKEN` PAT (removed the public keyed `upload-artifact`; dropped the job to `contents: read`). `launcher-build.yml`'s sidecars prerelease also publishes to the dist repo (same repo the launcher reads both from). The launcher already supported a private repo — just repointed `_defaultRepo` → `couch-roach-dist` and updated the token help + README. Launcher tests + analyze green; workflow YAML validated.
- **Remaining (user):** add the `DIST_REPO_TOKEN` secret (fine-grained PAT, Contents:read+write on couch-roach-dist) to the public repo's Actions secrets; put a read-only PAT for couch-roach-dist in the machine's `launcher.json`; then verify end-to-end — a release build lands in couch-roach-dist and the launcher installs it. Longer-term, Option C (keyless Worker proxy) would remove the baked keys entirely.

### Stop matching a longer title that merely contains the target · `p2`

- [x] The movie resolver path did **no** title verification (ranked by seeds only), so a search for "Descendants" could grab "Descendants Wicked Wonderland"; the TV path's `titleMatches` was containment-based. Added `FilenameMediaInfo.titleMatchesStrict` — parses both sides (year/quality stripped by the existing `parse`), requires the title *tokens* to be equal (rejecting a longer title with extra words), requires matching years when both name one (remake guard), and reconciles roman-numeral sequels (Frozen II ↔ 2) and `&`↔"and"; a year-only title (e.g. "2012") falls back to the loose match. Applied via a new `verifiedMovieResults` filter in the resolver's movie branch (mirrors `verifiedEpisodeResults`). Left the **TV** path on loose `titleMatches` on purpose — release naming legitimately appends region/qualifier words ("The Office" → "The Office US") that strict would wrongly reject; SxxExx already disambiguates episodes. Tests cover Descendants/The Descendants, Blade Runner 2049 vs 1982, Frozen II/2, Fast & Furious, year-only fallback, plus the movie filter.

### Add a CI workflow that runs the test suite · `p2`

- [x] `.github/workflows/test.yml` runs `flutter test` on push-to-main, PRs, and manual dispatch, on `ubuntu-latest` (suite is pure-Dart/drift — no Windows toolchain or dart_define.json needed). Mirrors the build workflows' Flutter setup (subosito/flutter-action @ 3.44.5, cache); concurrency cancel-in-progress. Free now that the repo is public. Green gate the build workflows assume.

### Keep a TV show (like keeping a movie) · `p3`

- [x] Show-level "Keep" toggle on the show detail page (shown once you own any episode), pinning the whole show against auto-cleanup — the TV counterpart to a movie's per-file Keep. The pin is a per-show fact on `SavedTitles.keptAt` (schemaVersion 7→8 + migration), set via `SavedTitlesRepository.setKeep`; the reaper queries (`reapable` / `watchReapCandidates`) left-join SavedTitles and exempt any episode whose show has `keptAt` set — so **episodes downloaded after pinning are spared too**, not just the ones present when you pinned. Live off the `savedTitleProvider` stream; push-pin icon (as in the Settings cleanup queue). A keep-only row (no favorite/watchlist) is created/removed cleanly. Tests: SavedTitles keep coexistence/cleanup, and a reaper test proving a kept show spares a *later-added* episode. Per-file `LibraryItems.keep` still pins individual movies / loose files.

### Player overlay stranded after a show ends · `p2`

- [x] The back button + Next Episode overlay only revealed on mouse hover/move and idle-hid after 3s regardless of play state, so on a remote-driven TV they became unrecoverable at the end of a show (media_kit's own controls still showed). Now reveals on any activity (pointer down + a top-level `Focus` treating any key as activity, returning `ignored`) and stays up while paused/ended.

### Dedupe Continue Watching by show · `p4`

- [x] `watchContinueWatching` now collapses multiple in-progress episodes of the same show to the most-recently-watched one. Show identity is the matched TMDB id (else the clean show title); movies never collapse. The SQL limit moved into Dart (dedupe-then-take) so a binge-heavy show can't starve other titles off the rail. Covered by two repo tests.

### "Go back 10 seconds" button on the player · `p4`

- [x] Added a `replay_10` button to the player's bottom control bar (`MaterialDesktopCustomButton` → `_skipBack10`), seeking −10s clamped at the start. Fades with the rest of the controls.
