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

# 2. Unlock the secrets. dart_define.json is committed ENCRYPTED via git-crypt;
#    unlock it once per machine with your key file (see Secrets below):
git-crypt unlock /path/to/couch-roach-git-crypt.key

# 3. Run. (Codegen output is committed; only re-run build_runner after you
#    change the drift schema — see below.)
flutter run -d windows --dart-define-from-file=dart_define.json
```

Fresh machine without the key? The app still builds; TMDB/OpenSubtitles calls
just won't work until you unlock. Or copy `dart_define.example.json` →
`dart_define.json` and paste your own keys. You can also pass keys inline with
repeated `--dart-define=KEY=value` flags.

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

Two developer keys — one **TMDB API Key (v3 auth)**
(<https://www.themoviedb.org/settings/api>) and one **OpenSubtitles Api-Key** —
live in `dart_define.json` and are injected at run time via
`--dart-define-from-file`. `AppConfig` (`lib/src/core/config/app_config.dart`)
reads them. Your wife never sees them; the app ships with the keys baked into the
build, not entered by the user.

### git-crypt (how the keys travel between machines)

`dart_define.json` is **committed to the repo, encrypted at rest** by
[git-crypt](https://github.com/AGWA/git-crypt). Anyone (or any leak) without the
key sees ciphertext; your working copy is transparently decrypted once unlocked.

Key facts for future-you:

- **What's encrypted:** files matched in `.gitattributes` (`dart_define.json`).
  Add more secret files there with `filter=git-crypt diff=git-crypt`.
- **The key** is a single binary file exported with `git-crypt export-key`. It is
  **NOT in the repo** — it lives in the password manager (secure note). It is the
  *only* thing that can decrypt these blobs; lose it and the committed secrets are
  unrecoverable.
- **New machine:** install git-crypt (`sudo apt install git-crypt` on
  Debian/Ubuntu/Zorin), `git clone`, then `git-crypt unlock /path/to/key`.
  Decryption is then automatic on every checkout for that clone.
- **Check state:** `git-crypt status` (look for `encrypted: dart_define.json`).
  `git-crypt lock` re-encrypts the working tree; `git-crypt unlock <key>` restores
  it. If a clone was made without git-crypt installed, the secret files stay as
  ciphertext until you unlock.
- Windows dev isn't used here; if it ever is, git-crypt installs via Scoop/Choco
  and must be on `PATH`.
