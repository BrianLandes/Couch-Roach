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
tmp\                      the in-flight download
```

## One-time setup

1. **Create a fine-grained GitHub token.** GitHub → Settings → Developer
   settings → Fine-grained tokens: *Repository access* = only
   `brianlandes/couch-roach`; *Permissions* → **Contents: Read-only**. It's the
   only secret and it's read-only.

2. **Save it on the machine that runs Couch Roach** as
   `%LOCALAPPDATA%\CouchRoach\config\launcher.json`:

   ```json
   { "githubToken": "github_pat_..." }
   ```

   (Optionally add `"repo": "owner/name"` to point at a different source repo.)

3. **Publish a build.** Run the "Windows build" workflow in `release` mode so a
   GitHub Release exists for the launcher to fetch.

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
