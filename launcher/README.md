# Couch Roach launcher

A tiny, self-updating launcher for Couch Roach. It's the thing your desktop
shortcut points at: on each run it checks the newest published build, downloads
and installs it if it's newer than what's on disk, then launches it. The
launcher stays deliberately dumb so **it** never needs updating — only the app
it launches does.

This is a separate Flutter package (its own Windows runner →
`couch_roach_launcher.exe`) with minimal dependencies (`http`, `archive`,
`path`).

## Install layout (per-user, no admin)

Everything lives under `%LOCALAPPDATA%\CouchRoach`:

```
config\launcher.json     your GitHub token (see below)
app\current.json         which build is installed
app\build-<N>\           an installed build (couch_roach.exe + DLLs + data\)
bin\                     the sidecars (qbittorrent.exe, yt-dlp.exe, ffprobe.exe, jackett\)
bin\sidecars.json        which sidecars bundle is installed
tmp\                     the in-flight download
```

## Sidecars

The four sidecars (qBittorrent, yt-dlp, ffprobe, Jackett) are **not** bundled in
the app anymore — the app zip is small. The "Launcher & sidecars" workflow
publishes them as a `sidecars-<tag>.zip` asset on a dedicated `sidecars`
**prerelease** (prerelease so it never becomes `releases/latest` and disturbs the
app-build detection), and the launcher fetches that by tag and provisions them
into `bin\` before launching the app (which searches `bin\` first). The `<tag>`
is a hash of the sidecar binaries, so the launcher only re-downloads them when
they actually change — and the app build no longer rebuilds them at all.

## One-time setup

1. **Create a fine-grained GitHub token.** GitHub → Settings → Developer
   settings → Fine-grained tokens: *Repository access* = only
   `brianlandes/couch-roach-dist` (the **private** repo that holds the built app
   + sidecars — the public `couch-roach` repo has the source only); *Permissions*
   → **Contents: Read-only**. It's the only secret and it's read-only.

2. **Save it on the machine that runs Couch Roach** as
   `%LOCALAPPDATA%\CouchRoach\config\launcher.json`:

   ```json
   { "githubToken": "github_pat_..." }
   ```

   (Optionally add `"repo": "owner/name"` to point at a different source repo.)

3. **Publish a build.** The "Windows build" workflow (release mode) publishes the
   app build to the private `couch-roach-dist` repo, and "Launcher & sidecars"
   publishes the sidecars there too. Both need a `DIST_REPO_TOKEN` secret on the
   public `couch-roach` repo — a fine-grained PAT with **Contents: Read and
   write** on `couch-roach-dist` (this is separate from your machine's read-only
   token in step 1).

4. **Put the launcher on the machine** and point the desktop/Start shortcut at
   `couch_roach_launcher.exe`. Grab it from the `couch-roach-launcher` artifact
   of a workflow run, or build it yourself:

   ```
   cd launcher
   flutter build windows --release
   ```

That's it — from then on it self-updates.

## Behaviour when things go wrong

- **No token, app already installed** → launches the installed build.
- **No token, nothing installed** → shows where to put the token.
- **GitHub unreachable, app installed** → launches the installed build (offline).
- **Update download fails, app installed** → keeps the working install and
  launches it.
