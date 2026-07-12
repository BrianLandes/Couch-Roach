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

### Dedupe Continue Watching by show · `p4`

- [ ] If there is more than one video for Continue Watching from the same show, only show the most recent one.

### Disable "Download next" when the next episode hasn't aired · `p4`

- [ ] The Download-next button should know whether the next episode has aired, and be disabled with a message if it hasn't aired yet.

### "Go back 10 seconds" button on the player · `p4`

- [ ] Add a skip-back-10s button to the player controls.

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
