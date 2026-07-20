# Couch Roach — Home Media Center

[![Tests](https://github.com/BrianLandes/Couch-Roach/actions/workflows/test.yml/badge.svg)](https://github.com/BrianLandes/Couch-Roach/actions/workflows/test.yml)

A single-machine, one-click desktop **home media center** for a TV PC. Point a
remote at it from the couch: browse what's out, pick something, and it plays —
no menus full of apps, no accounts, no subscriptions. Couch Roach is the shell
that ties it together: **Flutter coordinates, a torrent daemon acquires, and
libmpv plays.**

- **Platform:** Windows 11 (primary), Linux (buildable). Android/macOS not set up.
- **App id:** `com.couch.roach`
- **Built with:** Flutter 3.44.5 / Dart 3.12.2.

> Full design in [`docs/HANDOFF.md`](docs/HANDOFF.md); settled decisions in
> [`docs/DECISIONS.md`](docs/DECISIONS.md); the dev board is
> [`TASKS.md`](TASKS.md).

## What it is

Couch Roach is an **orchestration shell, not a media engine**. It doesn't
reimplement a video player, a downloader, or a metadata database — it
*coordinates* best-in-class pieces behind a single 10-foot UI:

- **Discovery** comes from [TMDB](https://www.themoviedb.org/) — trending,
  search, recommendations, cast, artwork, seasons/episodes.
- **Playback** is [libmpv](https://mpv.io/) (via
  [`media_kit`](https://pub.dev/packages/media_kit)) embedded in-process — it
  owns codecs, containers, subtitles, and resume position.
- **Acquisition** goes through a torrent daemon (qBittorrent) fed by *your own*
  indexer configuration (Jackett/Torznab). See **[Legal & scope](#legal--scope)**.
- **Everything local** lives in one SQLite file via
  [`drift`](https://pub.dev/packages/drift) — library, watch history, settings.
  There's no server, no login, no cloud: it's a single machine and a single
  trust boundary.

## Features

- **10-foot "liquid glass" TV UI** — dark, frosted surfaces; works with **both**
  a remote (D-pad/keys) **and** a pointer, with a bright focus ring for the couch.
- **A landing page that learns you** — Continue Watching, Favorites, Want to
  Watch, "New Episodes for You", recommendations, and personalized
  "Because you watch …" genre rows inferred from your history.
- **Rich playback** — resume where you left off, English-audio auto-select with a
  track picker, on-demand subtitle download + timing offset, next-episode button,
  "Who's in this?" cast lookup, skip ±10s.
- **A library that tidies itself** — scans your folders, matches titles to TMDB
  (with a folder-based fallback for the obscure ones), and auto-deletes fully
  watched files after a grace period — unless you pin them **Keep**.
- **Multi-disk aware** — content spreads across every configured drive by free
  space; no single hardcoded library root.
- **Self-updating Windows launcher** — one small exe that keeps the app current
  from GitHub Releases (see [`launcher/`](launcher/)).
- **Optional voice add** — queue titles by voice through an Alexa skill that
  drops them onto your Want-to-watch list.

## How it works

```
   Flutter app (this repo)  ── coordinates ──┐
        │  drift (SQLite): library, history, settings
        │  Riverpod (UI state) · go_router (nav) · injectable/get_it (DI)
        ▼
   ┌─────────────┐   ┌──────────────┐   ┌────────────────────────┐
   │  TMDB /     │   │  libmpv      │   │  qBittorrent + Jackett │
   │ OpenSubs    │   │ (media_kit)  │   │  (invisible localhost) │
   │  discovery  │   │  playback    │   │  acquisition           │
   └─────────────┘   └──────────────┘   └────────────────────────┘
```

The torrent daemon and the indexer service run as **invisible localhost child
processes** the app starts and stops — you launch one thing. Acquisition is a
single swappable seam (`AcquisitionResolver`); the play flow never knows or cares
where a file came from.

## Legal & scope

Couch Roach is a **personal, single-machine** tool, and acquisition is
deliberately **content-agnostic infrastructure**:

- **No indexers ship with it, and none are enabled by default.** The bundled
  Jackett is stock and bound to `127.0.0.1` only. *You* add indexers in the local
  Jackett UI, pointed at whatever legal / public-domain sources you choose — and
  that choice, and its legal responsibility, is **yours, not this project's**.
- The repo **hardcodes no trackers** and ships **no commercial-piracy sources**
  in code or default config. Only legal-source resolvers (e.g. Internet Archive,
  public-domain feeds) and the content-agnostic Torznab seam belong here. See
  [`docs/DECISIONS.md`](docs/DECISIONS.md) §D.

Use it with content you're legally entitled to. Don't use it to infringe.

## Getting started

Building the app yourself needs the Flutter toolchain and two free developer API
keys (TMDB + OpenSubtitles). The **[Secrets](#secrets)** section explains the
keys; the platform sections below cover the toolchain.

### 1. Bring your own API keys

Copy the example file and drop in your own keys — this is all you need to build:

```bash
cp dart_define.example.json dart_define.json
# then edit dart_define.json:
#   TMDB_API_KEY          -> https://www.themoviedb.org/settings/api  (v3 auth)
#   OPENSUBTITLES_API_KEY -> https://www.opensubtitles.com/en/consumers
```

`dart_define.json` is passed at run time with `--dart-define-from-file` and read
by `AppConfig` (`lib/src/core/config/app_config.dart`). It's **gitignored as
plaintext** — you won't commit your keys. (The committed, *encrypted*
`dart_define.json` is a maintainer convenience; see
[Secrets](#secrets-maintainer-key-sharing).) The app still builds and runs
without keys — TMDB/OpenSubtitles features just stay dark until you add them.

### 2. Windows

```powershell
flutter pub get
# Codegen output (database.g.dart, injection.config.dart) is committed; only
# re-run build_runner after you change the drift schema or an annotated class.
flutter run -d windows --dart-define-from-file=dart_define.json
```

Regenerate generated code after editing `lib/src/data/db/database.dart` (or an
`@injectable` / `@JsonSerializable` class):

```powershell
dart run build_runner build
```

### 3. Linux

The Linux desktop build compiles native plugin code (media_kit/libmpv, the ALSA
`volume_controller`, sqlite3), so a few system `-dev` packages and a linker must
be present first. On a fresh Debian/Ubuntu/Zorin machine:

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

Then, doing a clean build so CMake re-detects the new libs:

```bash
flutter clean && flutter pub get
flutter run -d linux --dart-define-from-file=dart_define.json
```

In VS Code, the committed `.vscode/launch.json` provides Linux debug/profile/
release configs — pick the Linux device in the status bar and press **F5**.

**Symptom → fix** for the errors seen on a first Linux build:

| CMake / build error | Missing package |
| ------------------- | --------------- |
| `Could NOT find ALSA (missing: ALSA_LIBRARY ALSA_INCLUDE_DIR)` | `libasound2-dev` |
| `Failed to find any of [ld.lld, ld] in ... /usr/lib/llvm-18/bin` | `lld-18` (match the llvm version in the path) |
| libmpv / mpv not found at link time | `libmpv-dev`, `mpv` |

## Bundled binaries (sidecars)

Four helpers ride **next to the app executable**, each vendored on demand (pinned
version + SHA-256, idempotent scripts) rather than committed —
`third_party/{qbittorrent,yt-dlp,ffprobe,jackett}/` are all gitignored:

| Binary       | Why                                                                    |
| ------------ | ---------------------------------------------------------------------- |
| qBittorrent  | invisible localhost torrent daemon (see [`DECISIONS.md`](docs/DECISIONS.md) §E) |
| `yt-dlp`     | lets libmpv's `ytdl_hook` resolve YouTube URLs (inline trailers)       |
| `ffprobe`    | fast subtitle-stream probe in the subtitle skip-check                  |
| Jackett      | invisible localhost Torznab indexer sidecar ([`DECISIONS.md`](docs/DECISIONS.md) §D) — a whole self-contained .NET tree bundled as `jackett/` |

Run the scripts for your platform **once** before building; the runner CMake copies
each binary (or, for Jackett, its directory) next to the app executable, from where
the app resolves it at runtime.

```powershell
# Windows (each extracts a self-contained payload; qBittorrent needs 7-Zip on PATH):
./tool/fetch_qbittorrent_windows.ps1   # GUI qbittorrent.exe from the signed installer
./tool/fetch_ytdlp_windows.ps1         # official yt-dlp.exe (bundles its own Python)
./tool/fetch_ffprobe_windows.ps1       # ffprobe.exe from BtbN's LGPL static FFmpeg build
./tool/fetch_jackett_windows.ps1       # self-contained Jackett tree (bundles .NET 9)
```

```bash
# Linux:
./tool/fetch_qbittorrent_linux.sh      # fully static qbittorrent-nox (no Qt deps)
./tool/fetch_ytdlp_linux.sh            # standalone yt-dlp (bundles its own Python)
./tool/fetch_ffprobe_linux.sh          # ffprobe from BtbN's LGPL static FFmpeg build
./tool/fetch_jackett_linux.sh          # self-contained Jackett tree (bundles .NET 9)
```

The Windows CI build (`.github/workflows/windows-build.yml`) runs all four fetch
steps automatically before `flutter build windows`.

> **The app launches fine without any of these** — each feature degrades
> gracefully (the daemon fails to start / logged and non-fatal; the Trailer button
> shows the player's error state; the subtitle check falls back to a slower libmpv
> probe). For a feature to work on a dev machine, either run its fetch script once
> (then `flutter run` bundles it) or have the tool on your `PATH`. Windows has no
> official headless qbittorrent-nox, so the GUI `qbittorrent.exe` is bundled and run
> hidden (minimized to tray) — a user-supplied `qbittorrent-nox.exe` in the bundle
> dir is preferred if present.
>
> **Updating yt-dlp:** YouTube periodically breaks extractors; bump the pinned
> `$Version`/`VERSION` in `tool/fetch_ytdlp_*` (and the SHA-256 from that release's
> `SHA2-256SUMS`) to refresh. The BtbN FFmpeg autobuild tag pinned for `ffprobe`
> is eventually pruned upstream — if that fetch 404s, bump it to a current
> autobuild release and refresh its SHA-256.

## Project layout

```
lib/src/
  app.dart                       # root MaterialApp (dark, 10-foot theme)
  core/
    config/app_config.dart       # secrets via --dart-define
    storage/storage_manager.dart # multi-disk spread + free-space target pick
  data/db/database.dart          # drift schema (library, watch_history, ...)
  features/
    library/                     # scanner, matching, landing screen
    discover/                    # TMDB discovery + taste/personalization
    player/                      # embedded media_kit playback
    settings/                    # library folders, cleanup, toggles
  services/
    acquisition/                 # the swappable seam: AcquisitionResolver + daemon
    discovery/                   # TMDB client
    subtitles/                   # OpenSubtitles
    cleanup/                     # auto-delete-after-watch reaper
launcher/                        # self-updating Windows launcher (separate package)
docs/                            # HANDOFF (design), DECISIONS, STYLE, VPN
```

## Development

```bash
flutter pub get
flutter analyze          # must be clean
flutter test             # the full suite (pure-Dart/drift, runs headless)
```

CI runs `flutter test` on every push and PR
([`.github/workflows/test.yml`](.github/workflows/test.yml)); the Windows build
and the launcher/sidecar packaging have their own workflows. Repository-specific
conventions (drift migrations, DI, the acquisition invariant, the design system)
live in [`CLAUDE.md`](CLAUDE.md), and queued work is tracked in
[`TASKS.md`](TASKS.md).

## Secrets (maintainer key-sharing)

The **normal path is [Bring your own API keys](#1-bring-your-own-api-keys)** — a
plaintext `dart_define.json` you never commit. The rest of this section is for the
maintainer, who shares one set of keys across their own machines by committing
`dart_define.json` **encrypted at rest** with
[git-crypt](https://github.com/AGWA/git-crypt). Contributors don't need this.

- **What's encrypted:** files matched in `.gitattributes` (`dart_define.json`).
  Add more secret files there with `filter=git-crypt diff=git-crypt`.
- **The key** is a single binary file exported with `git-crypt export-key`. It is
  **NOT in the repo** — it lives in a password manager. It is the *only* thing
  that can decrypt these blobs; lose it and the committed secrets are
  unrecoverable. (Public viewers see only ciphertext — safe.)
- **Unlock a clone:** install git-crypt (`sudo apt install git-crypt`), then
  `git-crypt unlock /path/to/key`. Decryption is automatic on every checkout after.
- **Check state:** `git-crypt status` (look for `encrypted: dart_define.json`).
  `git-crypt lock` re-encrypts the working tree; `git-crypt unlock <key>` restores
  it. A clone made without git-crypt installed keeps the secret files as
  ciphertext until you unlock.

## License

No license is set yet, so **default copyright applies (all rights reserved)** —
the code is public to read, but not yet granted for reuse. A license is planned;
until one lands, open an issue if you'd like to use the code.
