# VPN gating (ExpressVPN) — research & implementation plan

_Status: **scoped, not built.** Orthogonal to M1–M4; slot in around/after M4._
_Last updated: 2026-07-07_

## Goal

Ensure ExpressVPN is **on** (tunnel connected) before/while the app acquires or
streams content. The app should:

1. Detect whether ExpressVPN is running and connected.
2. If not running → start it.
3. If running but disconnected → **"activate"** it = connect the tunnel.
4. Periodically re-check that it stays running + connected.

**Assume the app is already configured and signed in.** We do **not** automate
activation-code entry / login. If ExpressVPN is not installed, too old, or not
signed in, the app must **surface that in the UI as a manual-fix state** — never
try to repair it silently.

## Key finding: ExpressVPN ships an official Windows CLI

As of the Nov-2025 Qt-app generation, ExpressVPN provides **`expressvpnctl`** on
Windows — a supported, scriptable CLI. This removes any need for GUI automation or
a reverse-engineered localhost API. The Linux CLI is equivalent, so the design is
symmetric across our current (Windows) and future (Linux) targets.

- **Binary:** `expressvpnctl`, installed at
  `C:\Program Files (x86)\ExpressVPN\services\` (also seen under
  `C:\Program Files\ExpressVPN\`). Path is version-dependent — **discover it, don't
  hardcode** (probe both known dirs; optionally read the install path from the
  registry).
- **Minimum app version: 12.69.0.** Older installs won't have `expressvpnctl` →
  treat as a `notInstalled`/`tooOld` manual-fix state.
- **Requires Administrator.** `connect` via CLI needs an elevated context. This is
  the one real design wrinkle — see "The admin problem" below.

### Commands

| Command                    | Use                                             |
| -------------------------- | ----------------------------------------------- |
| `expressvpnctl status`     | running + connected + signed-in signal (parse)  |
| `expressvpnctl connect`    | turn tunnel on (Smart Location or last server)  |
| `expressvpnctl disconnect` | turn tunnel off                                 |
| `expressvpnctl logout`     | sign out (we won't use this)                    |
| `expressvpnctl -h`         | list all commands                               |

### ⚠️ Undocumented: exact `status` output strings

ExpressVPN's docs do **not** publish the literal text `status` prints for each
state (connected / disconnected / not signed in / etc.). **First implementation
step is a spike on the real TV PC:** run `expressvpnctl status` in each state and
capture the exact output, then build the parser off those strings — not a guess.
Until we have them, the `VpnState` mapping is a stub.

## The admin problem (the design decision)

The media-center app should run as a **normal user**, but `expressvpnctl connect`
needs elevation. Options, best→worst for a couch/10-foot UX:

1. **Elevated helper via a Windows Scheduled Task (recommended).** Register a task
   once (first-run/install) that runs `expressvpnctl` with highest privileges; the
   app triggers it with `schtasks /run`. **No repeated UAC prompts**, app stays
   unelevated. Right answer for a set-and-forget TV box.
2. **Run the whole app elevated.** Simplest to code, but a UAC prompt every launch
   and it elevates the entire app (incl. the qBittorrent-nox child) for one
   feature. Heavy.
3. **Per-call elevation** (`ShellExecute` `runas`). A UAC prompt on *every connect*
   — unusable from a remote. **Rejected.**

`status` may not need elevation; `connect`/`disconnect` do. Confirm during the
spike whether `status` works unelevated (lets the poll run cheap, elevate only for
actions).

## Architecture (fits existing patterns)

Mirror the `AcquisitionResolver` swappable-seam pattern
(`lib/src/services/acquisition/`). Errors go through `ErrorLogService` with a
`source: 'VpnService.<op>'` per the repo's error-handling rule.

```
VpnController            (interface / seam — lib/src/services/vpn/)
 ├─ WindowsExpressVpnController   wraps expressvpnctl (build now)
 └─ LinuxExpressVpnController     wraps expressvpn CLI (later)

VpnService (@LazySingleton)
 ├─ Timer.periodic → poll status()
 ├─ exposes Stream<VpnState>
 └─ ensureConnected(): if disconnected → connect; if notInstalled/notSignedIn → error state

Riverpod StreamProvider<VpnState>  → UI status chip + "VPN needs setup" state
```

### `VpnState`

Distinguish at least:
- `connected` — tunnel up
- `disconnected` — running but tunnel off (auto-connect target)
- `connecting` — transient
- `notInstalled` / `tooOld` — no `expressvpnctl` or < 12.69.0 → **manual-fix UI**
- `notSignedIn` — installed but not activated → **manual-fix UI**
- `error` — CLI call failed / unparseable output → logged + surfaced

`notInstalled` / `tooOld` / `notSignedIn` are the "raise in the UI for the user to
fix manually" states from the requirement.

### Build order (per CLAUDE.md layering)

1. **Spike:** capture `expressvpnctl status` output strings + confirm whether
   `status` needs admin (do this on the real machine before coding the parser).
2. `VpnController` interface + `WindowsExpressVpnController` (path discovery,
   `Process.run` wrappers, status parser).
3. `VpnService` — periodic poll, `Stream<VpnState>`, `ensureConnected()`.
4. Elevation: Scheduled-Task registration + `schtasks /run` trigger for
   connect/disconnect.
5. Riverpod `StreamProvider` + UI status indicator + manual-fix state.
6. Tests: parser unit tests over the captured status strings; service tests with a
   fake `VpnController`.

## Open questions

- **Admin approach** — confirm Scheduled-Task helper (recommended) vs. run-elevated.
- **Exact `status` output strings** (the spike) — blocks the parser.
- **Does `status` need admin?** — affects whether the poll must go through the
  elevated helper too.
- **Gating policy** — is VPN a *hard gate* on acquisition/streaming (block play if
  disconnected) or *best-effort* (warn but allow)? Decide before wiring it into the
  play/acquire flow.
- **Where in the flow** — poll always-on from app start, or only when
  acquiring/streaming?

## Sources

- ExpressVPN — How to Use the CLI Control (Windows):
  https://www.expressvpn.com/support/vpn-setup/how-to-use-expressvpn-cli-windows/
- ExpressVPN — new Qt-based desktop apps (CLI rollout):
  https://www.expressvpn.com/blog/qt-linux-macos-apps/
