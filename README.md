# Couch Roach — Home Media Center

A single-machine, one-click desktop media shell for a TV PC. Flutter coordinates;
libmpv (via `media_kit`) plays; a torrent daemon acquires. See
[`docs/HANDOFF.md`](docs/HANDOFF.md) for the full design and
[`docs/DECISIONS.md`](docs/DECISIONS.md) for resolved decisions.

- **Platform:** Windows 11 primary, Linux later.
- **App id:** `com.couch.roach`

## Status

Scaffold complete. Native runner folders (`windows/`, `linux/`) are generated and
committed, dependencies resolve, drift codegen output (`database.g.dart`) is
committed, and `flutter analyze` is clean. Built with Flutter 3.44.5 / Dart 3.12.2.

## Setup (on your Windows machine)

```powershell
# 1. Resolve dependencies.
flutter pub get

# 2. Run. (Codegen output is committed; only re-run build_runner after you
#    change the drift schema — see below.)
flutter run -d windows ^
  --dart-define=OPENSUBTITLES_API_KEY=your_key ^
  --dart-define=TMDB_API_KEY=your_key
```

Regenerate drift code after editing `lib/src/data/db/database.dart`:

```powershell
dart run build_runner build
```

> Android/macOS aren't set up (Windows-first, Linux later). Add them later with
> `flutter create --platforms=android,macos .` if ever needed.

## Layout

```
lib/src/
  app.dart                     # root MaterialApp (dark, 10-foot theme)
  core/
    config/app_config.dart     # secrets via --dart-define
    storage/storage_manager.dart # multi-disk spread + free-space target pick
  data/db/database.dart        # drift schema (library, watch_history, ...)
  features/
    library/                   # scanner + landing screen
    player/                    # embedded media_kit playback
  services/
    acquisition/               # §8 boundary: AcquisitionResolver + daemon
    discovery/                 # TMDB (M2)
    subtitles/                 # OpenSubtitles (M3)
    cleanup/                   # auto-delete-after-watch reaper
```

## Secrets

Injected at run time via `--dart-define`; nothing secret is committed. You hold
one OpenSubtitles Api-Key and one TMDB key as the developer — your wife never
sees them.
