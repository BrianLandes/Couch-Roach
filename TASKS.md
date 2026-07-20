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

### Restore app auto-updates via a private release channel (keyed builds off the public repo) · `p1`

- [ ] **Context:** the repo went public, but the Windows exe has `TMDB_API_KEY` / `OPENSUBTITLES_API_KEY` / `ALEXA_INBOX_TOKEN` baked in via `--dart-define` (recoverable from the binary). Public GitHub Releases are world-downloadable, so publishing is currently **disabled** (`windows-build.yml`: push trigger + Publish Release step off — the stopgap). This task restores auto-updates without exposing keyed builds.
- **Out-of-band first:** rotate all three keys (they're compromised); delete the old public releases (build-21…35) in the GitHub UI — the MCP server can't delete releases.
- **Option A — private "dist" repo (recommended, least work):** the launcher was *originally built for private releases* (`launcher/lib/updater.dart` already downloads via a read-only `githubToken`). Create a private `couch-roach-dist` repo; have `windows-build.yml` publish the build there (a PAT secret with write to the dist repo) instead of the public repo, and **remove the public `upload-artifact`** of the keyed zip so nothing keyed stays on the public repo. Point the launcher's `repo` at the dist repo. Keeps free public CI; minimal launcher change.
- **Option B — Cloudflare R2:** CI uploads the zip + `manifest.json` to a **private** R2 bucket (S3-compatible creds as GH secrets); the launcher fetches them from R2 via a credential or a Worker-signed URL (you already run a Worker). Decouples from GitHub; more launcher rework + access-control plumbing.
- **Option C — keyless (ideal, most work):** proxy TMDB/OpenSubtitles through the Worker so the exe ships with no third-party keys; then public releases are safe again. Doesn't protect the Alexa token unless that's also removed/rescoped.
- Whichever path: re-enable the build trigger + publish step once the target is private/keyless, and confirm the launcher updates end-to-end.

### Manually delete downloaded shows / seasons / episodes / movies · `p2`

- [ ] A way to remove downloaded content that isn't going to be auto-reaped (unwatched, kept, or otherwise not eligible). Needed at three granularities:
  - **Movie** — delete this movie's file. Button on `LibraryDetailScreen` (alongside Play/Keep).
  - **Show** — delete *all* the show's episodes, or just *one season's*. Button on `ShowDetailScreen` mirroring the existing `_DownloadAllButton` scope dialog ("This season" / "All seasons").
  - **Episode** — delete a single episode. Affordance on each local episode row (`_EpisodeRow`/`_Availability` where the Play button shows).

Design notes:
- Deletion must remove the **video file + its `.en.srt`/`.eng.srt`/`.english.srt` sidecars** on disk *and* the library row(s). The reaper already has this file-delete logic privately (`DriftWatchedReaper._deleteFileAndSidecars`) — **extract it into a shared helper** (a small `MediaFileDeleter`/`CleanupService`, or a method on `StorageManager`) so the reaper and manual delete share one path. Row removal: `LibraryRepository.removeByPath` already hard-deletes the row and cascades `watch_history` ("forget this title entirely") — that's the right call for an explicit user delete (vs. the reaper's `markMissing`, which keeps the row+history). Confirm the decision: an explicit delete probably *should* drop watch history too.
- **Confirm before deleting** (10-foot destructive action → a confirmation dialog; honor the "look at the target before deleting" rule). Show what's about to go (title + file count).
- Multi-file/multi-season deletes go through the same helper per file; report count deleted via snackbar. Skips/handles already-missing rows gracefully.
- A kept show/movie can be deleted (explicit user action overrides the keep pin); clear the `keptAt`/`keep` flag as part of removal so no stale pin lingers.

### Prefer whole season / show packs for the bulk "Download" button · `p3`

- [ ] The show detail "Download…" button (all seasons / one season) currently queues an **individual torrent per episode** (`downloadSeason` / `downloadAllSeasons` in `acquire_play.dart` → `prefetchEpisode` per episode). For a bulk download it's better to **first try a whole season-pack or show-pack torrent**, falling back to per-episode only when no acceptable pack is found. This flips our usual per-episode fetch paradigm — which must **stay unchanged** for the inline per-episode Download buttons and the next-episode prefetch.

Design notes:
- **Season-pack machinery already exists** and is used today only as the single-episode *fallback*: `jackett_resolver.dart` has `seasonPackResults(...)` + `FilenameMediaInfo.seasonPackNumber(...)`, and `_resolve` already queries a season-only pack when no single-episode source verifies (then extracts the one episode). Reuse this from the bulk button (grab the pack, keep *all* its episodes) rather than reinventing it. **Show pack** (all seasons — "complete" / "S01-S0N") is the genuinely new piece: add a `showPackResults` + a "complete series" query shape.
- Stays content-agnostic through `AcquisitionResolver` — just different **query shapes**, no new indexers: season pack → "Show Name S01" / "Season 1" (no episode marker); show pack → "Show Name complete" / "Season 1-N".
- After grabbing the pack (one torrent → a folder of episodes), the **existing scan + match + folder-fold** hydrates the episodes into library rows and the play flow — no per-episode acquisition needed. Verify the download lands under a managed root so the scanner picks it up.
- Skip episodes already local; if a pack only partially covers what's missing, decide: take the pack anyway (simplest) vs. top up the gaps per-episode. Note the choice.
- Fallback: no acceptable pack → current per-episode behavior. Keep the season/all scope dialog as-is.

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
