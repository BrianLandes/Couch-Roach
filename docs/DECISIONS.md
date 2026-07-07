# Resolved Decisions & Deltas

Live record of decisions made against `HANDOFF.md`. Read this first when
resuming — the container is ephemeral, so this file is the source of truth for
"what did we decide."

_Last updated: 2026-07-07_

## Project identity
- App id / org: **`com.couch.roach`**
- Repo: `brianlandes/couch-roach`, dev branch `claude/home-media-center-handoff-68osi0`
- Dart package name: `couch_roach`

## Adopted stack conventions (from sibling project)
For consistency with Brian's other Flutter app, Couch Roach uses the same
patterns (see `CLAUDE.md`):
- **injectable + get_it** — DI for services/singletons (`lib/src/injection.dart`).
- **json_serializable** — DTOs for API JSON (drift handles local rows).
- **flutter_riverpod** — UI state (`ProviderScope` at root).
- **go_router** — navigation (`lib/src/router/app_router.dart`).
- **drift** — local SQLite (no Supabase/Postgres/RLS; single-machine).
- Codegen toolchain pinned to the analyzer-10 world: **drift < 2.32.0**
  (2.32.1–2.34.0 have a codegen bug; the 2.34.2 fix needs analyzer 13 which
  injectable_generator can't use yet). Resolved: drift 2.31.0, injectable_generator
  2.12.1, json_serializable 6.14.0. Built on Flutter 3.44.5 / Dart 3.12.2.

## Todoist
Dev tasks live in the **Couch Roach** Todoist project (board view), id
`6h3xW6q4HRmCPC3p`, sections Backlog/To Do/In Progress/Done. Full workflow +
section ids in `CLAUDE.md`.

## Resolved §9 forks
| Fork | Decision |
|---|---|
| Local store | **SQLite via drift** (not flat JSON) |
| Play flow | **Stream-while-downloading** (sequential + first/last-piece), not download-then-play |
| Recommendation depth | Start simple (concatenate + dedupe) — default |
| Subtitle filename parsing | Dart regex — default |
| Torrent daemon | qBittorrent-nox — default |
| TMDB matching in M1 | Scan + play with filename-derived titles in M1; **M2 back-fills `tmdb_id`** |

## New requirements (beyond the handoff)

### A. Multi-disk storage
The TV PC has **3 physical disks**; content must spread across them by free space.
- The library **scanner reads all configured roots** (across all disks), not one.
- New downloads pick a **target disk by available free space** (above a floor).
- Modeled by `StorageManager` + a `storage_locations` table (root path, label,
  enabled, priority). See `lib/src/core/storage/`.
- Open impl detail: cross-platform free-space query. Dart has no built-in; likely
  a tiny platform channel (Win32 `GetDiskFreeSpaceEx`) or a maintained package.
  Marked TODO in `StorageManager`.

### B. Auto-cleanup after watch
The **library folders are the app's to manage.** Anything that lands in them is
hydrated (TMDB metadata + subtitles) and then reaped after watching. This is the
managed zone — there is no separate "app-downloaded only" gate.
- **Lifecycle:** file appears in a library folder → hydrate (metadata + subs) →
  watchable → auto-delete after a full play-through + grace period.
- Trigger: `watch_history.completed == true` AND `last_watched_at` older than the
  grace period. Deletes the video + its `.en.srt` sidecar, removes the row.
- **Exception:** a file pinned `keep = true` (a movie to rewatch) is never
  auto-deleted. `keep` is a column on the `library` table; the UI needs a
  "keep around" toggle.
- The `managed` column stays as provenance (downloaded vs pre-existing) but no
  longer gates cleanup.
- Runs on startup and periodically. See `lib/src/services/cleanup/`.
- **Still open:** grace-period length (default proposed: **7 days**).

## TV / kiosk UX
- Must go **fullscreen**.
- Input: a **remote that emits arrow keys** → D-pad / focus-traversal navigation
  is a first-class concern, built in from the start (Flutter `FocusableActionDetector`
  / focus traversal, large 10-foot targets).

## Visual style — "Liquid Glass"
Slick/simple/modern, iOS-Liquid-Glass-inspired: translucent frosted surfaces over
a dark ambient glow, iridescent periwinkle→cyan accents, bright cyan focus rings.
Baseline is built: tokens in `lib/src/theme/`, `GlassSurface` + `AmbientBackground`
helpers, `AppTheme.dark`, and a component gallery at `Routes.styleShowcase`
(`/style`). Full guide: `docs/STYLE.md`. Rule: use tokens, never hardcode.

## Error logging
No remote backend (unlike the sibling projects' Supabase error table), so errors
go to a **local text log**: `<app-support>/logs/couch_roach.log` (rotates at
~5 MB). `ErrorLogService` (`lib/src/core/logging/`) is the single sink every
system opts into via `getIt<ErrorLogService>().logError(e, stackTrace:, source:)`;
`main()` also routes uncaught framework/async errors to it (FlutterError.onError,
PlatformDispatcher.onError, guarded zone). The path is shown in the Storage
settings screen. On Windows the file lands under `%APPDATA%\com.couch\couch_roach\logs\`.

## Secrets
- Injected via `--dart-define` (or a gitignored `config` file); nothing secret in git.
- **OpenSubtitles.com** Api-Key: Brian has one.
- **TMDB** key: Brian will obtain (needed at M2).

## Environment note
- Flutter SDK is **not** installed in the Claude Code cloud container, so
  `flutter create` (which generates the native `windows/` & `linux/` runner
  folders) must be run on Brian's Windows machine. See `README.md` → Setup.
