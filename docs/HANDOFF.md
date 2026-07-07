# Home Media Center — Implementation Handoff

> Original handoff document, preserved verbatim for context. Resolved decisions
> live in `docs/DECISIONS.md`.

**Target:** Single-machine desktop app for two users (you + wife) on a TV PC.
**Primary platform:** Windows 11. **Secondary (later):** Linux.
**Non-negotiables:** runs entirely on the one machine (no client/server split the user sees), and launches with essentially one click.

---

## 1. Design principles

Three of these drive every decision below:

1. **Don't build a video player.** Codecs, containers, subtitle rendering, and 10-foot playback are solved problems. The app is an *orchestration shell*, not a media engine. Playback is delegated to libmpv.
2. **Three clean responsibilities.** The Flutter app *coordinates*; a torrent daemon *acquires*; libmpv *plays*. Each does one thing. State flows through the app.
3. **Consolidation over accretion.** Prefer folding capability into existing components over adding new processes. Every new moving part is a new thing that can break in front of your wife.

---

## 2. Architecture overview

```
┌─────────────────────────────────────────────────────────┐
│  Flutter desktop app  (the shell — the only thing she sees)│
│                                                            │
│  ├─ UI: landing / show detail / player screens             │
│  ├─ Local store (SQLite via drift): library, watch history │
│  ├─ Discovery client  → TMDB API                           │
│  ├─ Subtitle client   → OpenSubtitles.com API              │
│  ├─ Playback: media_kit (libmpv, in-process/embedded)      │
│  └─ Acquisition: AcquisitionResolver (interface)           │
│         └─ drives torrent daemon over RPC                   │
└─────────────────────────────────────────────────────────┘
              │                         │
      ┌───────▼────────┐        ┌───────▼─────────┐
      │ Torrent daemon │        │ libmpv (bundled) │
      │ (qBittorrent-  │        │ via media_kit    │
      │  nox, RPC)     │        │                  │
      └────────────────┘        └──────────────────┘
```

Key point: with **media_kit**, libmpv runs *in-process* and renders into the Flutter widget tree. Playback is embedded in the app — not a separate window — so it's genuinely one seamless application. This is the main reason Flutter + media_kit wins over the NiceGUI + external-mpv route discussed earlier.

---

## 3. Tech stack (decisions + rationale)

| Concern | Choice | Why |
|---|---|---|
| App framework | **Flutter desktop** | One native `.exe` and one native Linux binary from one codebase; already in your wheelhouse. |
| Playback | **media_kit** (libmpv) | Plays essentially every codec/container (MKV, HEVC, embedded subs). Embedded, not a separate window. Exposes position/duration natively → free resume tracking. |
| Local state | **SQLite via `drift`** | Typed queries for library + history; Flutter-native. (Fork: a flat JSON store is viable for two users — see §9.) |
| Discovery / metadata | **TMDB API** | Free. Show/movie metadata, artwork, episode lists, trending, "similar," and watch-provider data. |
| Subtitles | **OpenSubtitles.com REST API** | Hash + filename matching; SRT/UTF-8 output. Pure HTTP → lives in Dart, no extra process. |
| Torrent engine | **qBittorrent-nox** (headless, Web API) | Mature, cross-platform, and critically supports **sequential download + prioritize first/last piece**, which is what enables stream-while-downloading. Launched as a child process by the app so she never manages it. |

---

## 4. Feature breakdown → implementation

### 4.1 One-click launch
- Ship as a compiled Flutter desktop binary. Windows: a desktop/Start shortcut. Linux (later): a `.desktop` entry.
- On startup the app **spawns the qBittorrent-nox daemon as a child process** (bound to localhost, fixed port, headless) and shuts it down on exit. She launches one thing; the daemon is invisible.
- Launch into a fullscreen / kiosk-style layout suitable for a TV and a remote/controller.

### 4.2 Landing page
Two rails:

**Continue Watching** — from local `watch_history`: show poster + "S2E4 · 12:30 left" + resume position. Sorted by `last_watched_at`. This is the highest-value rail; make it the top one.

**For You** — a blend, all derived from TMDB seeded by watch history:
- *New episodes* of shows already in history (TMDB episode air dates vs. what's been watched).
- *Trending / hot now* (TMDB trending endpoint).
- *Similar to what you've watched* (TMDB "recommendations"/"similar" for a few recent titles).

Keep the recommendation logic dumb at first (concatenate + dedupe + light ranking). Personalization depth is a fork (§9), not a v1 requirement.

### 4.3 Show detail
- Selecting a title opens metadata (synopsis, cast, artwork, rating) + a season/episode list from TMDB.
- Each episode row shows local availability state: **Downloaded** / **Not downloaded** / **Downloading (nn%)**.
- Play button per episode → triggers the play flow (§4.4).

### 4.4 Play flow (the core state machine)
```
play(showMeta, season, episode):
  local = library.resolve(showMeta.tmdbId, season, episode)
  if local exists:
      ensureSubtitles(local)        # §4.6
      mpv.play(local.path, startAt = resumePosition)
  else:
      handle = acquisition.resolve(showMeta, season, episode)   # §4.7 (interface)
      torrent = daemon.add(handle, sequential=true, firstLastPiecePriority=true)
      await torrent.readyToStream()   # enough buffer + first/last pieces
      ensureSubtitles(torrent.primaryFile)
      mpv.play(torrent.primaryFile, startAt = 0)
  on mpv exit: watch_history.upsert(position, duration, completed?)
```
- **Resume tracking is native**: media_kit exposes a position stream, so persist position on pause/exit and on completion mark the episode done.
- **Stream-while-download vs download-then-play** is a complexity fork (§9). Simplest v1: download-then-play with a progress screen. Streaming is the sequential-download + first/last-piece path once you want it.

### 4.5 Universal format support
- Delegated entirely to libmpv via media_kit — MKV, HEVC/H.265, AV1, VP9, multichannel audio, embedded subtitle tracks all handled.
- Edge cases to keep on the radar: HDR tone-mapping and some exotic audio passthrough, but these are libmpv-config concerns, not app code.

### 4.6 Auto English subtitles
FileBot-style: hash match first, filename fuzzy-match fallback. **Pure Dart, no daemon.**
1. **Skip check:** is there an embedded English subtitle track (ffprobe — ships with ffmpeg alongside mpv) or a sidecar `.srt`? If so, done.
2. **Compute OpenSubtitles moviehash:** `filesize` + sum of first 64 KB and last 64 KB read as 8-byte little-endian unsigned ints, mod 2⁶⁴, as 16-char lowercase hex. (`RandomAccessFile` in Dart.)
3. **Search** `GET /api/v1/subtitles?moviehash=…&languages=en`.
4. **Fallback** if empty: parse filename → title/season/episode, search by `query` + `season_number`/`episode_number` (or `tmdb_id`, which you already have). Dart regex handles common `Show.S01E02.1080p...` patterns; reach for GuessIt only if filenames are chaotic.
5. **Pick best:** sort by download count / trusted uploader; decide hearing-impaired preference.
6. **Download:** `POST /api/v1/download` with `file_id` → temp link → save as `<VideoName>.en.srt` next to the file. libmpv auto-loads correctly-named sidecars.

**API constraints (build around these):**
- Searching is unlimited; **downloading is quota-limited** (free account ~20/day; "Under Development" consumer flag allows ~100/day without user login). For a bulk first-scan of an existing library, use a **queue that processes a few/day and remembers what it already tried** — don't hammer on first launch.
- Register **one** Api-Key as the developer (you); your wife never sees it.
- A descriptive `User-Agent` header is mandatory or requests are rejected.

### 4.7 Torrent subsystem
Mechanically source-agnostic: it accepts a magnet/torrent, downloads it (sequential + first/last-piece priority for streaming), and hands a file path to the player. Driven over the daemon's RPC/Web API from Dart.

**Legal source APIs to build the resolver against:**
- **Internet Archive** — fully torrentable, real API. Public-domain film/TV, concerts, software.
- **Academic Torrents** — API-accessible datasets and some media.
- Linux distros / large open datasets publish feeds.

See §8 for the acquisition boundary.

---

## 5. Local data model

```
library
  id, tmdb_id, season, episode, file_path,
  container, video_codec, audio_codec, has_embedded_en_sub,
  added_at

watch_history
  tmdb_id, season, episode,
  resume_position_sec, duration_sec, completed,
  last_watched_at

subtitle_attempts        # so the quota-limited fetcher doesn't retry endlessly
  tmdb_id, season, episode, status, attempted_at
```
Recommendations are computed at read-time from `watch_history` + TMDB; nothing to persist there.

---

## 6. External APIs

- **TMDB** — API key (free tier). Endpoints: search, tv/{id}, tv/{id}/season/{n}, trending, tv/{id}/recommendations, tv/{id}/similar, watch/providers. Cache responses; artwork via TMDB image CDN.
- **OpenSubtitles.com** — `Api-Key` header (per-app), optional JWT via `/login` for higher quota. Endpoints: `/subtitles` (search, unlimited), `/download` (quota-limited). SRT/UTF-8 default.

---

## 7. Build order (milestones)

Front-loaded so a fully useful, self-contained media center exists before acquisition is touched.

- **M1 — Local media center.** Shell + library scan + libmpv playback of existing local files + resume tracking. *Useful and complete on its own.*
- **M2 — Discovery.** TMDB integration + landing page (Continue Watching + For You) + show-detail/episode screens.
- **M3 — Subtitles.** Auto English-subtitle fetch with the quota-aware queue.
- **M4 — Acquisition.** Torrent daemon integration + `AcquisitionResolver` with legal-source implementations; download-then-play first, streaming later.

---

## 8. Acquisition boundary (read this)

The torrent subsystem is defined behind a single interface:

```dart
abstract class AcquisitionResolver {
  /// Returns a magnet/torrent handle for the requested title, or null.
  Future<TorrentHandle?> resolve(ShowMeta meta, int season, int episode);
}
```

This doc specifies the **client mechanics** (sequential download, first/last-piece priority, RPC control, hand-off to mpv) and **legal-source implementations** of the resolver: `InternetArchiveResolver`, `AcademicTorrentsResolver`, etc. These map a request to torrents that are licensed for distribution.

What this doc **does not** specify is a resolver that searches piracy trackers (e.g. a Prowlarr/Jackett-style indexer pointed at those trackers) to obtain current commercial streaming shows. Downloading licensed commercial content without a license is infringement, and BitTorrent re-uploads while downloading, so it's distribution too — that integration is left out by design. The interface is the seam: legal resolvers are provided; anything else is yours to source and carries that legal exposure.

Keeping this as a swappable interface is also just better architecture — the app doesn't care where a magnet comes from, and the legal/illegal decision lives in one small, replaceable place rather than being smeared through the play flow.

> **Amendment (2026-07-07 — see DECISIONS §D):** a **Jackett/Prowlarr Torznab resolver run as a bundled sidecar is now in scope**, narrowly. It ships as *content-agnostic* infrastructure the user points at their **own legal / public-domain indexer configuration** (personal, single-machine). The resolver hardcodes no indexers and ships no commercial-piracy trackers in code or default config — the choice of indexers lives in the user's own Jackett instance, and the legal responsibility for that choice sits with the user, not this repo. Targeting piracy trackers for commercial content — in code or default config — remains out of scope, exactly as above. Mechanically: Jackett (.NET 9, self-contained) runs as an invisible localhost child process, same model as qBittorrent-nox. Packaging + runtime details in `docs/research/torrent-indexers.md`.

---

## 9. Open forks (decide before / during build)

- **Stream-while-downloading vs download-then-play.** Streaming needs sequential + buffer-ready logic and readiness detection; download-then-play is a progress bar. Recommend shipping the latter first.
- **SQLite (drift) vs flat JSON store.** Two users, modest data — JSON is defensible and simpler; SQLite pays off if the library grows or queries get richer.
- **Recommendation depth.** Concatenate-and-dedupe TMDB rails (simple) vs. weighted personalization from history. Start simple.
- **Subtitle filename parsing.** Dart regex (no dependency) vs. GuessIt (better on messy names, adds a Python call). Start with regex.
- **Daemon choice.** qBittorrent-nox (recommended) vs. a small libtorrent Python sidecar (more control, another process). qBittorrent keeps the process count down.
