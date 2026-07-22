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

### Add the Couch Roach icon to the launcher · `p4`

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
