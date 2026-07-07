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

## Setup (on a Linux machine)

The Linux desktop build compiles native plugin code (media_kit/libmpv, the ALSA
`volume_controller`, and sqlite3), so a handful of system `-dev` packages and a
linker must be present before the first build. On a fresh Debian/Ubuntu/Zorin
machine, install the toolchain and libraries up front:

```bash
# Base Flutter Linux desktop toolchain (GTK, CMake, ninja, pkg-config).
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev

# App-specific native deps discovered by the build:
#   libasound2-dev  -> ALSA headers (volume_controller plugin)
#   libmpv-dev, mpv -> libmpv, the actual player behind media_kit
#   lld-18, clang-18, build-essential -> LLVM linker (ld.lld) + C/C++ toolchain
#     for the native-assets build step. Match the llvm version the error names
#     (e.g. lld-18 for `/usr/lib/llvm-18/bin`).
sudo apt-get install -y libasound2-dev libmpv-dev mpv lld-18 clang-18 build-essential
```

Then the usual flow. After installing system libs, do a clean build so CMake
re-detects them:

```bash
flutter clean && flutter pub get
flutter run -d linux --dart-define-from-file=dart_define.json
```

In VS Code, the committed `.vscode/launch.json` provides Linux debug/profile/
release configs — pick the Linux device in the status bar and press **F5**.

**Symptom → fix** for the errors seen on first build:

| CMake / build error | Missing package |
| ------------------- | --------------- |
| `Could NOT find ALSA (missing: ALSA_LIBRARY ALSA_INCLUDE_DIR)` | `libasound2-dev` |
| `Failed to find any of [ld.lld, ld] in ... /usr/lib/llvm-18/bin` | `lld-18` (match the llvm version in the path) |
| libmpv / mpv not found at link time | `libmpv-dev`, `mpv` |

> Secrets work the same as on Windows — unlock `dart_define.json` with git-crypt
> (`sudo apt install git-crypt`, then `git-crypt unlock /path/to/key`; see
> [Secrets](#secrets)), or drop your own keys into a local `dart_define.json`.

## Bundled binaries (torrent daemon)

The app spawns qBittorrent as an invisible localhost child (see
[`docs/DECISIONS.md`](docs/DECISIONS.md) §E). The binary is **vendored on demand**,
not committed — `third_party/qbittorrent/` is gitignored and populated by a fetch
script (pinned version + SHA-256, idempotent):

```powershell
# Windows: extracts the self-contained qbittorrent.exe from the official signed
# installer (needs 7-Zip on PATH or at its default install location).
./tool/fetch_qbittorrent_windows.ps1
```

```bash
# Linux: downloads a fully static qbittorrent-nox (no Qt/shared-lib deps).
./tool/fetch_qbittorrent_linux.sh
```

Run the script for your platform **once** before building; the runner CMake copies
the binary next to the app executable, from where the app resolves it at runtime.
The Windows CI build (`.github/workflows/windows-build.yml`) runs the fetch step
automatically before `flutter build windows`.

> **Dev note:** the app launches fine without this — the daemon just fails to start
> (logged, non-fatal) and local playback still works. For acquisition to actually
> function on a dev machine, either run the fetch script once (then `flutter run`
> bundles it) or have `qbittorrent-nox` on your `PATH`. Windows has no official
> headless nox, so the GUI `qbittorrent.exe` is bundled and run hidden (minimized
> to tray) — a user-supplied real `qbittorrent-nox.exe` in the bundle dir is
> preferred if present.

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
