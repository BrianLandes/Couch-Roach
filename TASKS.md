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

### Disable "Download next" when the next episode hasn't aired · `p4`

- [x] The player's Next Episode button now reports when an unaired episode is due instead of
  offering a Download that can only fail — and the automatic prefetch stops trying too.

**The task's half.** `NextEpisodeButton` takes an `airDate`; in its not-yet-fetched state an
unaired episode renders a disabled pill reading "Airs Mar 4, 2026" (or "Not yet released"
when TMDB has no date). Only the *download* action is replaced — an episode already on disk
or mid-download still plays, whatever TMDB claims about its date. `player_screen` resolves
the date in `_resolveNextEpisode`, and skips the lookup when the episode is already local.

**The half that wasn't in the task.** `prefetchEpisode` had no aired guard either, so the
halfway-mark auto-prefetch would try to fetch an unaired episode — a wasted resolver
round-trip at best, latching onto a mislabelled fake at worst. Both the button and the
prefetch funnel through that one function, so the guard went there: one place, impossible to
bypass.

**Fails open, deliberately.** `episodeHasAired` treats an episode TMDB doesn't list, a season
it has no details for, a throwing lookup, and an unparseable date as *aired*. The guard exists
to avoid pointless fetches, not to become a new way for downloads to fail on a poorly-dated
show or an offline TMDB. Only a date TMDB actually gives us, in the future, blocks anything.
Same reasoning in the button: a null `airDate` leaves Download enabled and lets
`prefetchEpisode` make the authoritative call.

Also extracted `airDateLabel` into `new_episodes.dart` next to `isAired` and pointed the show
detail page's `_UnreleasedBadge` at it, so an unreleased episode reads identically in both
places instead of via a second copy of the month table.

**No schema change.** Tests: 5 button states (unaired disabled, aired enabled, unknown-date
enabled, and downloaded / downloading both beating a future date), 7 on `episodeHasAired`
covering every fail-open route, `episodeAirDate`, and `airDateLabel`. 743 green.

### `_splitYear` in LibraryMatchService is dead for the common path · `p4`

- [x] Took the "better" option: candidates now carry the year, so it actually sharpens the
  search instead of being silently dropped.

`_splitYear` tried to pull a trailing year off a candidate to send TMDB a `year=` filter,
but `tmdbSearchCandidates` ran `cleanShowName` first, which had already stripped it — so
`"Dune 2021"` arrived as `"Dune"` and the filter was never sent. Dead code with a real cost:
a bare "Dune" is ambiguous across three films, and remakes couldn't be told from originals.

- `tmdbSearchCandidates` now returns `List<SearchCandidate>` — a
  `({String query, int? year})` record — instead of `List<String>`.
- New `splitShowNameYear(raw)` returns `cleanShowName`'s output **unchanged** plus the year
  it removed, recovered from the trimmed tail rather than re-parsed. That's deliberate: the
  search text is byte-for-byte what it was, so this change can only *add* a filter, never
  alter a query. Keeps the two permanently in step.
- The folder candidate reads its year off the raw basename, since `showFolderName` had
  already stripped it.
- `_splitYear` deleted.
- Dedupe is on the query alone (the same title from filename and folder is one search,
  keeping the first year seen).

Only one lib caller, so the blast radius was the tests. **No schema change.**

Tests: the year-carrying cases (bare and parenthesised, folder-sourced, none-named) plus
guards that a title merely *ending* in digits keeps them — `Apollo 13`, `Se7en`, and `2012`
(a year-shaped title is the title, not a suffix). The old match-service test that pinned the
broken behaviour now asserts `year=2021` **is** sent. 728 green.

### Title matching: a very short query false-matches anything · `p3`

- [x] Fixed in two places — the length floor the task described, plus the root-name
  candidate that turned out to be the more common trigger.

**1. Containment floor.** `pickBestMatchIndex` fell back to substring containment with no
length rule, so a stray short query swept up whatever TMDB returned (`'m'` matched
`'Something Entirely Different'`; `'It'` matched `'Titanic'`, which really does contain
"it"). Containment now requires the **contained** side to be ≥ `kMinContainmentChars` (4) —
guarded on whichever string is the contained one, since a short *result* inside a long query
is exactly as weak. Genuinely short films (*M*, *Up*, *It*) are unaffected: they're caught by
the exact-match pass, which has no length rule.

**2. The bigger one the task understated.** The floor fixes `/m/…` and `/tv/…`, but the
canonical layout is `/movies/Inception.mkv` — `movies` normalizes to 6 chars, sails past any
floor, and contain-matches a result named "Movie". Root cause: `tmdbSearchCandidates` added
the containing folder unconditionally, so a file sitting **loose in a library root** got
searched for by the root's own name. It now takes `rootPaths` and skips the folder candidate
via the existing `isLooseInRoot` — the same structural helper `library_grouping` already
uses, so no denylist of folder names. `LibraryMatchService` takes `StorageManager` to supply
them; `main()` awaits `StorageManager.load()` before `matchUnmatched()`, so the roots are
populated when it runs. Omitting `rootPaths` keeps the old behaviour for callers that know
the file is foldered.

Note this is a **different path** from the earlier "Stop matching a longer title that merely
contains the target" task — that one hardened *torrent release* matching
(`titleMatches`/`titleMatchesStrict` in `filename_media_info.dart`). This is the TMDB
search-result validation in `library_path_parse.dart`; the two don't share code.

**No schema change.** Tests: 11 on `pickBestMatchIndex`/`tmdbSearchCandidates` (both floor
directions, the boundary at 3 vs 4, short-titles-still-match, loose-in-root vs foldered,
season folders, dedupe) + 3 end-to-end through the match service, including the `/movies`
case the floor alone wouldn't catch. 721 green; `library_path_parse.dart` 95.7%.

Not verified on-device: whether the real library has titles that *depended* on the loose
containment. The exact-match pass covers short titles, and nothing in the suite regressed,
but a title that only ever matched by a ≤3-char containment would now stay unmatched (and
retry on the next pass, so it fails soft).

### Show detail: reflect a just-ready episode's Play button live (season download) · `p3`

**Device test FAILED — reopened.** Episodes still don't flip to Play during a season
download, even after navigating away and back. The provider fix below was correct but
insufficient: it made the *query* live, while nothing ever **creates the rows**.

**Actual root cause (two, both from a season pack being invisible to per-episode UI):**
1. `_tryPack` queues the pack fire-and-forget, and the acquire flow only writes a library
   row for the **one** episode it was asked to prepare (`_finishPrepared`). Every other
   episode in the pack stays unknown to the library — and so to the live query — until
   someone plays it or the next launch's disk scan picks it up.
2. Each episode's `AcquireButton` adopts a running download via `downloadForTagProvider(tag)`
   keyed on the **episode** dedupe key, but a pack is tagged with the **season** key. So the
   button can't see the pack either — which is why there's no progress meter.

**Fix for (1) — shipped:** new `DownloadedEpisodeRegistrar` reads finished files straight off
the daemon and registers a library row for each. Sweeps every 10s from `main()`. Only our
tagged torrents, only numeric-tmdb-id keys, only fully-downloaded playable video whose name
parses to a season+episode (the filename is authoritative — a pack's key names one season but
its files are what actually landed). A path already in the library is skipped entirely, so
sweeps are idempotent and can never clobber an existing row. Supporting changes:
`TorrentStatus.savePath` (parsed from `/torrents/info`, needed to build absolute paths),
`torrentFiles` promoted onto the `TorrentDaemon` interface, and a pure `parseAcquisitionKey`
that recovers tmdbId/season/episode from a tag — refusing to guess on title-keyed fallbacks,
since a title can contain the key's own separators. 11 registrar tests + 5 parser tests.

Not an `@LazySingleton`: constructed in `main()` instead, because this container has no
Flutter SDK to re-run `build_runner` with and `injection.config.dart` must never be
hand-edited. **Follow-up:** convert it to an annotated service next time codegen runs.

**Fix for (2) — shipped:** each episode covered by an in-flight pack now shows its own
progress meter instead of a Download button. New pure `episodeFileProgress(files)` maps a
torrent's file list to `(season, episode) → progress` (filename authoritative, non-video and
marker-less files ignored, furthest-along file wins so a sample can't drag progress
backwards), and `packEpisodeProgressProvider` polls it on the existing 1.5s cadence,
autoDispose so the extra per-file polling stops with the page. It considers **pack torrents
only** (key with `episode == null`): episode-tagged downloads stay with `AcquireButton`, which
already drives them with retry/cancel — so the two can never double-render the same download.
`_EpisodeDownloading` mirrors the acquire button's own progress styling. 6 helper tests.

- [x] (superseded detail) While a season downloads, an episode that finishes now flips its row to Play with no
  manual refresh.

Root cause was one word: `localEpisodesProvider` was a `FutureProvider`, so "what's on disk"
was read **once** when the page opened and never again. The drift query behind it was already
the right shape — it just called `.get()` instead of `.watch()`.

- `LibraryRepository.watchLocalEpisodes(tmdbId)` added alongside the existing one-shot
  `localEpisodes`. Both go through one private `_localEpisodesQuery`, so the live and
  one-shot views can't drift apart on what counts as "on disk". The one-shot stays for the
  imperative callers (the player's next-episode lookup, prefetch) — those aren't UI state.
- `localEpisodesProvider`, `localShowItemsProvider` and `localTitleProvider` are now
  `StreamProvider`s over it. **Scope note:** `localTitleProvider` wasn't in the task but had
  the identical bug — acquire a movie with its detail page open and Play never appeared —
  and was the same one-line change.
- Deleted the two hand-rolled `ref.invalidate(localEpisodesProvider(tmdbId))` calls in
  show_detail_screen; they only existed because the provider wasn't live, and the liveness
  now covers deletes in both directions.

**No schema change** — pure read-side, no `schemaVersion` bump.

Tests: 6 repository tests against real drift (emits on arrival, on delete, on a file going
missing, scoped per show, empty-not-silent, and agreement with the one-shot) + 3 widget tests
driving a controllable fake stream to prove a row flips Download → Play mid-download, that
episodes flip independently, and that a delete flips it back. 703 green;
`library_repository.dart` 94.5%.

Two testing gotchas worth remembering, both now handled in
`test/widget/show_detail_screen_test.dart`: a fake stream repo must **replay its current
value to each new listener** (as drift's `.watch()` does) or late-subscribing providers sit
in `loading` forever; and `DetailScaffold` lays out in a lazy `ListView`, so on the default
800x600 test surface the episode rows never build — the test sets a taller viewport.

Not verified on-device: the end-to-end season download. The liveness is proven at the
repository and widget layers, but the real path also depends on the scanner registering the
finished file promptly.

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

### Large videos (7–8 GB) play at a poor frame rate · `p2`

- [ ] Big files stutter / drop frames in Couch Roach, but the *same file* plays smoothly in PotPlayer on the same machine — so it's not raw hardware capacity. NOT transcoding — PotPlayer isn't transcoding either; it's hardware decode.

**Correction on what the existing setting does** (read the media_kit 1.2.6 / media_kit_video 1.3.1 source to confirm): the "Hardware video acceleration" toggle is **not** hwdec. It's media_kit's `enableHardwareAcceleration`, which is passed to the native `VideoOutputManager.Create` and selects the hardware vs software **rendering / video-output texture** path. Hardware **decoding** is a separate knob: `NativeVideoController.create` sets `hwdec: configuration.hwdec ?? 'auto'` **unconditionally on desktop**, regardless of that toggle. So hwdec has been `auto` all along, and the toggle the user flipped only ever changed rendering.

**First cut shipped (diagnostic, not yet a fix):**
- New `SettingsService.hwdecMode` (default `'auto'` — exactly what media_kit already applied, so no behaviour change) passed through as `VideoControllerConfiguration.hwdec`. Settings → Video performance gets a "Hardware decoder" dropdown (`auto`, `auto-copy`, `auto-safe`, `d3d11va`, `d3d11va-copy`, `vaapi`, `nvdec`, `no`). The old toggle is relabelled "Hardware video **rendering**" so the two stop being confused.
- The player now logs what libmpv *actually* chose: `_logDecodeDiagnostics` samples mpv properties 3s in (`hwdec`, `hwdec-current`, `hwdec-interop`, `video-codec`, `video-params/pixelformat`, `width`/`height`, `container-fps`) and again at 63s (`frame-drop-count`, `decoder-frame-drop-count`, `estimated-vf-fps`). Logged at info level under `PlayerScreen.decode`.

**DIAGNOSED (2026-09-01) — it's the render path, not decode.** Decode log from a stuttering
4K file:

```
selected  hwdec=auto hwdec-current=d3d11va-copy hwdec-interop=- video-codec=hevc
          video-params/pixelformat=p010 width=3840 height=1920 container-fps=23.976
after 60s hwdec-current=d3d11va-copy frame-drop-count=791 decoder-frame-drop-count=0
```

`decoder-frame-drop-count=0` with `frame-drop-count=791` (≈55% of ~1440 frames in 60s) means
the **decoder keeps up and the video output drops the frames**. `hwdec-interop` is empty, so
libmpv can't hand GPU surfaces to media_kit's renderer and falls back to `d3d11va-**copy**`:
every frame is read back to system memory and re-uploaded. At 4K 10-bit (p010) that's ~12 MB
per frame, ~290 MB/s each way — the wall. Explains why swapping decoders barely moved it:
decode was never the problem.

Ruled out on-device: "Hardware video rendering" was already ON (turning it OFF was somewhat
smoother but introduced artifacts), so zero-copy isn't reachable through that toggle on this
GPU. Nothing else was running/downloading, so contention is out too.

**Mitigation shipped: output-size cap.** New `maxVideoHeight` setting (0 = uncapped default;
1080p / 720p) → pure `videoOutputCap()` → `VideoControllerConfiguration.width/height`. mpv
letterboxes into the box preserving aspect, so a 16:9 box bounds any ratio: the 2:1 4K film
renders 1920x960 instead of 3840x1920 — a quarter of the pixels for the output stage. Opt-in
because it also upscales a source *smaller* than the cap.

**Honest limitation:** this cuts the upload-and-draw half only. The GPU→CPU readback still
happens at the decoded resolution, so it reduces the bottleneck rather than removing it.
**If 1080p/720p isn't enough, the decisive fix is to stop fetching 4K for this box** —
a max-download-resolution preference (prefer 1080p releases over 2160p) in the resolver, which
sidesteps the readback entirely. Queue that if the cap underdelivers.

**Earlier device test (superseded):** User tried several Hardware decoder values;
Direct3D 11 seemed *slightly* better but nowhere near watchable, the rest made no difference.
Confirmed nothing else was running or downloading, so daemon/CPU contention is ruled out —
which also rules out the "pause torrents while watching" lever for this. **Still need the
`PlayerScreen.decode` log lines** (verbose logging is now on) — without `hwdec-current` and the
drop counters this is guesswork. If `hwdec-current` is a real decoder and drops are still
climbing, decode isn't the bottleneck and the next suspect is the **render path**: media_kit's
`vo=libmpv` texture hand-off, and the "Hardware video rendering" toggle in both positions.

**Next step — read the log while a big file stutters.** `hwdec-current` is the tell:
- `hwdec-current=no` → silent software fallback; force `d3d11va` (or `d3d11va-copy`) from the new dropdown and re-check.
- `hwdec-current` set but drop counts climbing → decode is fine, so the bottleneck is elsewhere: the **copy-back vs zero-copy** render path (media_kit hands frames through its own texture; `-copy` variants add a GPU→CPU readback that's expensive at 4K), demuxer/cache sizing for large files, or disk/CPU contention from the torrent daemon seeding while playing (see the "pause torrents while watching" backlog item). Also worth trying the "Hardware video rendering" toggle in both positions now that it's understood to be the *rendering* path. [windows]

### Paused video + PC sleep → "cannot play the file" on wake · `p2`

- [ ] Pause a video, let the PC sleep, come back → the player says it can't play the file that was playing; have to back out and replay it to recover.
- Likely the mpv/media_kit pipeline (or the file handle / GPU context / the localhost stream if it was an archive_play) doesn't survive suspend/resume. Investigate: does the OS `WM_POWERBROADCAST` resume event reach us? On resume, re-open the current media at the saved position instead of leaving the dead handle. Consider listening for the player's error state and auto-recovering (reload at last position) rather than requiring a manual back+replay. Repro with both a local file and an archive/stream source. [windows]

### Trailer / YouTube playback stopped working (regression) · `p2`

- [ ] Playing trailers / YouTube videos fails now — was working before, unclear when it broke; no error captured yet, but nearly everything tried recently fails.
- First step: reproduce and **capture the actual error** (ErrorLogService log + the player/network error). Likely causes to check: the YouTube extraction path (an `explode`/yt-dlp-style resolver whose API/endpoints drifted — YouTube changes break these often), a changed trailer URL/key from TMDB (`videos` endpoint → YouTube key), or the embed/stream handoff to mpv. Confirm where in the chain it dies (no trailer key? extraction fails? mpv can't open the resolved URL?) before fixing. [windows]

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

### Structure + coverage pass · `p2`

- [x] Fresh audit of file/code structure and test coverage; fix what it turned up.

569 → 690 tests, 47.1% → 50.2% line coverage (excl. generated). Analyze clean throughout.
Layering already held and there were no route-string leaks, so the findings were narrower
than the file sizes suggested — the real gap was **testability**, not structure.

- **player_screen** 1,978 → 1,954 lines, decisions extracted into four pure siblings, all
  100%: `player_controls_visibility` (overlay auto-hide), `player_progress` (resume, the 5s
  save throttle, the 95% watched / 50% prefetch thresholds), `player_sources`,
  `player_input`. `audio_selection` absorbed the label/channel helpers → 100%. The widget
  stays at 0% — libmpv can't be driven in a test; that's now the documented pattern.
- ⚠️ **One deliberate behaviour change**, not a pure extraction:
  `ControlsVisibility.onIdleElapsed` re-checks `playing` before hiding, so a timer armed
  just before a pause can no longer fire after it and hide the overlay on a paused video.
  Narrow race, but it's the stranding mode — **still wants on-device confirmation** before
  the overlay task counts as closed.
- **PosterScrim** — `AppColors.posterScrim{Clear,,Strong}` + a widget in `poster_art.dart`,
  replacing 4 raw-hex copies whose stops had drifted (0.5/0.5/0.45). In the style showcase.
- **resume_button** → `features/discover/`, fixing the one shared-layer-imports-features
  inversion.
- **test/ layout** — `test/unit/` vs `test/widget/` split on widget mounting, plus
  `test/support/` for shared fakes; nothing loose in `test/`. Convention in CLAUDE.md.
- **The root cause worth remembering:** `AppConfig` was constructed inline in services, and
  its `--dart-define` values are compile-time constants that are *always empty* under
  `flutter test` — so every key-gated path was unreachable and the old tests said so in
  their comments. Injecting it (+ `test/support/FakeAppConfig`) took `AlexaInboxService`
  45.9% → 96.9% and `LibraryMatchService` 8.1% → 79.0%. New key-gated services must follow
  this pattern. Also `library_detail_screen` 0% → 83.2%.
- Two bugs the new tests surfaced are queued separately (short-query false match;
  `_splitYear` dead for the common path) — both change matching behaviour.

### Hydrate Alexa-queued titles with their TMDB id for the details page · `p3`

- [x] Titles from the Alexa voice queue carry their TMDB id + media type, and the details
  page fills in the full TMDB profile from it.

**(1) The id already persisted** — `addFromAlexa()` writes `tmdbId`/`mediaType` onto the
SavedTitles row; now asserted end to end by the drain tests (movie path, TV fallback,
re-delivery). No change needed.

**(2) The details page did not hydrate — the real bug, and wider than Alexa.** `_savedTile`
builds a `DiscoverTile` from a saved row with only `{tmdbId, title, mediaType, posterPath}`,
and `MovieDetailScreen` rendered `overview`/`year`/`voteAverage` straight off that tile
without ever fetching by id. So **every** movie opened from Want-to-watch, Favorites or
Recently Downloaded showed a bare page — Alexa titles were just the most visible case. TV
was already fine (`ShowDetailScreen` takes only `(tmdbId, name)` and fetches details itself).

Fix: pure `hydrateTile(base, fetched)` in `discover_tile.dart` — base wins on identity
(`tmdbId`/`mediaType`), fetched wins field-by-field on everything it has.
`MovieDetailScreen` watches `movieTileProvider(tmdbId)` and renders the merged tile, so the
page paints instantly off what it was pushed with and a miss or partial response degrades
rather than blanking. The hydrated title/poster also feed `SaveTitleButtons`,
`AcquireButton` and the trailer picker, so re-saving stores canonical name/art and
acquisition searches the canonical title.

Tests: `hydrate_tile_test.dart` (9 pure) + `movie_detail_screen_test.dart` (5 widget,
including the sparse-Alexa-tile regression).

TV path closed too: `show_detail_screen_test.dart` (4 widget) pins that the screen hydrates
its whole profile from just `(tmdbId, name)` — there's no sparse tile to merge on this side,
it's hydration by construction — plus the header staying usable during the fetch and both
degraded states (TMDB error → local-only fallback, TMDB miss → "Not found"). Guards against a
refactor quietly starting to render off the sparse route args.

Coverage landed: `discover_tile` 100%, `movie_detail_screen` 0% → 84.4%,
`show_detail_screen` 67.4% → 69.6%. Suite 694 green, 51.2% overall.

### Logging overhaul: verbose gate, split error log, per-launch rotation · `p3`

- [x] Two tasks done together, since they touch the same file.
- **Verbose gate.** `ErrorLogService` gained a `verbose` flag; `info` entries are now dropped unless it's on, while `warn`/`logError` always write. New `SettingsService.verboseLogging` (default off) with a "Verbose logging" toggle in Settings; `main()` syncs `log.verbose` from it and re-syncs on every settings change (`SettingsService` is a `ChangeNotifier`), so flipping the toggle takes effect immediately.
- **Deliberately did NOT mass-delete the ~106 `info`/`warn` call sites.** Each is a `source`-tagged debug trace; with the gate they cost nothing by default, and deleting them would gut diagnostics for the bugs still on the board (trailers, downloads, sleep/resume). The poll-loop ones are already throttled to one line / 4s. Gating was the actual fix; revisit deletion only if verbose output proves unreadable.
- **Split + rotation.** Each launch now writes a **pair** under `<app-support>/logs/`: `couch_roach-<stamp>.log` (everything) and `couch_roach-<stamp>.errors.log` (warnings/errors only — same entries, filtered copy, so the combined stream stays complete). Replaces the single ever-growing file and its 5 MB rename-to-`.1` rotation. Stamp is `YYYY-MM-DD_HH-mm-ss` so lexicographic order is chronological; startup prunes all files of the oldest sessions beyond the newest 10, matched by filename prefix (unrelated files in the dir are untouched). Pruning runs before the new pair is opened and is fully best-effort — it can never break a launch.
- **Bonus signal.** mpv's own `error`/`fatal` log lines (mirrored for network/trailer playback) now go through `logError` instead of `info`, so real libmpv failures always land in the log and the errors file even with verbose off — directly useful for the trailer regression.
- Settings screen shows both paths and notes the retention. Docs updated (CLAUDE.md, DECISIONS.md).
- Tests: verbose gating (info dropped/kept, warn+error always), errors-only file contents, pre-init buffering routed to both files, pruning (deletes oldest beyond 10, both files per session, leaves foreign files and under-limit dirs alone), plus settings persistence. (Validated via CI — no Flutter SDK in this container.)
- Caveat: `init()` runs before settings load, so the few `info` entries emitted during early startup are dropped even with verbose on. Documented on the field.

### Input-mode based focus: mouse drift no longer hijacks arrow-key selection · `p2`

- [x] While arrow-navigating, any mouse movement (the remote is an air-mouse, so a resting hand jitters the cursor) would hover-hijack the selection. Now selection is **mode-based**. New `lib/src/core/input/input_mode.dart`: an app-wide `InputModeController extends ValueNotifier<InputMode>` (`keyboard`|`pointer`, defaults pointer) + a global `inputMode` instance. A global `HardwareKeyboard` handler (`inputModeKeyHandler`, registered in `main()`, never consumes) flips to **keyboard** mode on a nav key (arrows/Tab); an app-level `Listener` in `app.dart` (`MaterialApp.router` `builder`) flips to **pointer** mode on a deliberate `onPointerDown`/scroll (`PointerScrollEvent`) — never on movement. `FocusableCard._onHoverHighlight` now requests focus only when `inputMode.isPointer`, so cursor drift in keyboard mode is inert; a click (`_onTap`) requests focus + activates (pointer mode already set by the ancestor Listener). `_onFocusHighlight` skips the scroll-into-view only for pointer-mode hover, so keyboard nav always centers. `FocusableCard` is the single shared seam (the only hand-rolled hover-focus; `ContinueWatchingCard`'s MouseRegion only reveals overlay buttons, doesn't move selection). Tests: `input_mode_test.dart` (controller transitions + notify-on-change; handler switches on nav-key-down only, never consumes) and `focusable_card_input_mode_test.dart` (hover selects in pointer mode, not in keyboard mode). (Validated via CI — no Flutter SDK in this container.) On-device: confirm arrow nav ignores cursor jitter and a click still selects.

### Fix episode/pack search mixing up numbered-sequel series (Planet Earth I/II/III) · `p2`

- [x] Searching "Planet Earth" pulled down "Planet Earth II"/"III" releases (and vice-versa). Root cause: TV episode + season/show-pack verification in `jackett_resolver.dart` used `FilenameMediaInfo.titleMatches`, loose containment on the fully-stripped normalized title — `normalizeTitle("Planet Earth II")` = `"planetearthii"`, which *contains* `"planetearth"`, so the base-series query matched the sequels; `SxxExx` can't disambiguate since all three are S01 on TMDB. New `FilenameMediaInfo.titleMatchesSeriesAware` — the TV counterpart of `titleMatchesStrict`: the query's parsed title tokens must be a **prefix** of the release's (so region/edition qualifiers like "The Office US" still match), but a **bare number immediately after** the matched tokens is treated as a sequel marker the query lacks and rejected, so "Planet Earth" ≠ "Planet Earth II"/"III" (and a sequel query needs the matching number). Roman-numeral sequels fold to digits ("Planet Earth II" ↔ "Planet Earth 2"). Swapped into all three TV filters (verified episodes, season packs, show packs); the movie path keeps `titleMatchesStrict`. Tests: new `titleMatchesSeriesAware` group (base-vs-sequel both directions, roman/digit folding, region qualifier still allowed, shorter/unrelated rejected, empty-query fallback). (Validated via CI — no Flutter SDK in this container.)

### Auto-play next when the next episode downloaded mid-playback · `p2`

- [x] Auto-play-next didn't fire if the next episode finished downloading *during* the current one: `_maybeAutoAdvance` read `_nextLocalItem`, resolved once at open by `_resolveNextEpisode` — null if the next episode wasn't on disk then, and never refreshed. Now `_maybeAutoAdvance` is async and, when the cached item is null, re-queries the library (`_resolveNextLocalNow` → `localEpisodes(tmdbId)` for the already-resolved next `(season, ep)`) so a just-arrived episode still auto-plays. Guarded on `_autoAdvanced` after the await. (Verified via CI — no Flutter SDK in this container instance.)

### Show detail opens on the season you were last watching · `p3`

- [x] The show detail always opened on season 1 (`_season` defaulted to `seasons.first`). New `WatchHistoryRepository.lastWatchedSeason(tmdbId)` (newest watch-history row for the show — in-progress or finished — its season) + `lastWatchedSeasonProvider`; `_contentChildren` defaults the selected season to it when it's a real season of the show, else the first. A chip tap still sets `_season`, which wins. Repo tests: newest-wins, null-when-none, show-scoped. (Verified via CI.)

### Four new recommendation rails on the landing page · `p2`

- [x] Added four single-signal (no-ensemble) discovery rails, each reusing `_DiscoverRail` (so they honor the owned filter + "Not interested"):
  - **More like \<favorite\>** (`moreLikeFavoriteProvider`) — TMDB recommendations seeded from your newest favorite alone, as a named/legible rail (vs. the blended "Recommended For You").
  - **Because you watch \<Actor\>** (`favoriteActorProvider`) — the actor recurring across the most of your watched+favorited titles (pure `topRecurringPerson` over `tvCast`/`movieCast`), then their `personCredits` ranked by popularity.
  - **Acclaimed in \<genre\>** (`acclaimedInGenreProvider`) — top-rated in your #1 inferred genre via `discover` (`sort_by=vote_average.desc`, `vote_count.gte=300`), a quality axis next to the popularity genre rows. `discoverMovies/discoverTv` gained `sortBy`/`minVotes`.
  - **Finish the Franchise** (`finishFranchiseProvider`) — for owned/favorited movies in a TMDB collection, the other released films of that collection you don't own. New client calls `movieCollectionId` + `movieCollection`.
- All filter out owned titles (`ownedTmdbIdsProvider`) and the seeds themselves; each returns null/empty until there's enough signal, so no empty rows. Tests: `topRecurringPerson` (recurrence/cutoff/ties), the acclaimed discover params, and collection parsing. 544 green, analyze clean. Device-verify the rails populate as expected.

### Rework "New Episodes" — only truly-new episodes for caught-up shows · `p2`

- [x] The rail used to surface any show with a later aired episode than the one you watched — so a half-watched season showed your *backlog* as "new." Now a show qualifies only when **(1)** your furthest *finished* episode was the latest aired when you finished it (you were caught up) **and (2)** a new episode has aired since. **No new persisted metadata** — computed from data we already had: `LibraryItems.season/episode` + `WatchHistory.lastWatchedAt`/`completed` + TMDB air dates (live). `latestWatchedEpisodePerShow` now filters to `completed = true` (so in-progress and `advanceToNextEpisode`-seeded rows don't inflate "furthest") and carries `lastWatchedAt` on `WatchedShow`. New pure helper `hasNewEpisodeSinceCaughtUp({higherRankedAirDates, lastWatchedAt, now})` replaces `hasNewerAiredSeason`/`hasLaterAiredEpisode`: caught-up = nothing ranked above aired by `lastWatchedAt`; new-since = something ranked above aired after. `newEpisodesProvider` feeds it the air dates of later episodes of the watched season (season details) + later seasons (season-level dates). Caveat: judged from *current* TMDB air dates (assumes they're historically stable — bulletproofing would need a `wasCaughtUp` snapshot on completion; deemed not worth it). Tests: helper (caught-up/backlog/new-since/undated/empty/equal-instant), completed-filter + lastWatchedAt on the query. 536 green, analyze clean.

### Watched indicator on episodes (show detail) · `p3`

- [x] Each episode row on the show detail page now shows a green `check_circle` (and dims the title) when the episode has been watched. New `WatchHistoryRepository.watchCompletedEpisodes(tmdbId)` — a live left/inner join returning the show's `completed` `(season, episode)` pairs, **including episodes whose file was since reaped** (the row is flagged missing but history is kept), so the mark survives auto-cleanup. `completedEpisodesProvider` (family, live) feeds `_EpisodeList`, which passes `watched` to each `_EpisodeRow`. Watched = watch history `completed` (an in-progress episode isn't marked — it's on Continue Watching). Repo tests: completed-only, show-scoping, reaped-survival. Widget test omitted (drift stream doesn't emit reliably under the widget tester's fake clock; logic is unit-tested). 535 green, analyze clean.

### "Recently Downloaded" rail: newest N, drop only when watched · `p3`

- [x] The rail shows the **newest N (20) app-acquired titles and keeps them until watched** — no time window (an earlier `maxAge`/60-day cutoff was removed per feedback: things should stay for a while). Left join on `watchHistory` so it's reactive to both new downloads and titles getting watched; a title drops when watched **since it was downloaded** (`lastWatchedAt >= its addedAt`) — "since *this* download" (not "ever watched") so a since-reaped, freshly re-downloaded title reappears. Collapsed one entry per show; a watched episode drops the whole show (Continue Watching covers it). Tests: no-window/old-download-stays, watched-since exclusion, old-history re-download reappears, whole-show exclusion, limit. (Validated via CI — no Flutter SDK in this container.)

### Media Play/Pause key leaks to background apps (Spotify/YouTube) · `p2`

- [x] The hardware media Play/Pause key paused Couch Roach *and* propagated to background media apps (Spotify/YouTube would start). Root cause: Couch Roach never owned the OS media session, so Windows delivered the key both to the focused window (media_kit) and, via the System Media Transport Controls (SMTC), to whatever app owns the current session (Spotify). Fix: own the SMTC session while a video plays, so the key routes to Couch Roach only.
- **Native (windows/runner):** new `MediaSession` (C++/WinRT) gets `SystemMediaTransportControls` for the window (interop `GetForWindow`), enables Play/Pause, marshals `ButtonPressed` to the UI thread via `PostMessage` → a `couch_roach/media_session` method channel (`onButton`). Methods: `enable`(title)/`setPlaybackStatus`(playing)/`disable`. Wired in `flutter_window`; CMake adds the source, links `windowsapp.lib`, and disables `/WX` (+ explicit `/EHsc`) for that TU since the WinRT headers aren't warning-clean.
- **Dart:** `MediaSessionController` (Windows-only; no-op elsewhere) — the player `enable`s on open, `setPlaying` on every play-state change, `disable` on dispose, and routes `onButton` → play/pause. `_onHardwareKey` now swallows the raw media Play/Pause key **on Windows** so media_kit doesn't *also* toggle (double-toggle) — SMTC's `onButton` is the single driver (verified media_kit uses `CallbackShortcuts`, which a `HardwareKeyboard` handler returning true preempts).
- **Windows CI build: green** (after a follow-up fix — the C++/WinRT headers pull in `<experimental/coroutine>` under C++17, so the runner needed `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS`). Compiles clean; release published. Dart analyze + 528 tests green.
- ✅ **Device-verified (mostly):** the remote's Play/Pause now drives Couch Roach and Spotify/YouTube no longer react. **Residual:** occasionally the button does nothing, or still reaches a background app. User is gathering instances to characterise when/why — likely a window-focus or SMTC-session-ownership gap (we claim the session on play and release it on dispose, so a paused/backgrounded player may be handing it back). Revisit with concrete repro steps.

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
