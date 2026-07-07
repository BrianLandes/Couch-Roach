# Couch Roach — Home Media Center

A single-machine, one-click desktop media shell for a TV PC. Flutter coordinates;
libmpv (via `media_kit`) plays; a torrent daemon acquires. See
[`docs/HANDOFF.md`](docs/HANDOFF.md) for the full design and
[`docs/DECISIONS.md`](docs/DECISIONS.md) for resolved decisions.

- **Platform:** Windows 11 primary, Linux later.
- **App id:** `com.couch.roach`

## Status

Scaffold / M1 in progress. The Dart code is committed, but the native runner
folders (`windows/`, `linux/`) are **not** — they must be generated with the
Flutter toolchain (not installed in the cloud dev container).

## Setup (on your Windows machine)

```powershell
# 1. Generate the native platform folders (adds windows/ & linux/; keeps the
#    existing pubspec.yaml and lib/). Run from the repo root.
flutter create --org com.couch --project-name couch_roach --platforms=windows,linux .

# 2. Resolve dependencies (bump any versions the resolver complains about).
flutter pub get

# 3. Generate drift's database code (creates lib/src/data/db/database.g.dart).
dart run build_runner build --delete-conflicting-outputs

# 4. Run.
flutter run -d windows \
  --dart-define=OPENSUBTITLES_API_KEY=your_key \
  --dart-define=TMDB_API_KEY=your_key
```

> `flutter create .` over this repo only adds missing files (the platform
> runners); it won't overwrite `pubspec.yaml` or anything under `lib/`.

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
