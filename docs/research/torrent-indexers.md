# Torrent indexer search — reference notes

> ⚠️ **REFERENCE ONLY — OUT OF SCOPE FOR THIS REPO.**
> This documents *how* general torrent-indexer search works, for understanding.
> **Do not implement any of it here.** Per HANDOFF §8 and the CLAUDE.md invariants,
> only **legal-source** resolvers (Internet Archive, Academic Torrents, distro
> feeds) belong in `AcquisitionResolver`. **No** piracy-tracker /
> Prowlarr / Jackett-style indexer searching for commercial content. The
> transferable lesson here is the *adapter pattern*, not the sources.
>
> _Captured: 2026-07-07_

## Terminology (two different "trackers")

- **Indexers / torrent sites** — the **search** layer (where you *find* torrents).
  This doc is about these.
- **BitTorrent trackers** — the announce servers (`udp://…/announce`) in a magnet's
  `&tr=` params that coordinate peers. Different thing. Public tracker lists (e.g.
  `ngosang/trackerslist`) get appended to magnets to improve peer discovery — the
  only sense in which "obtaining trackers" means these.

## The reference architecture: normalization proxy (Jackett / Prowlarr)

Canonical OSS: **Jackett** (`github.com/Jackett/Jackett`) and **Prowlarr**
(`github.com/Prowlarr/Prowlarr`). Both solve the same problem — clients (Sonarr/
Radarr/etc.) can't speak to 100+ heterogeneous sites, so a proxy normalizes them:

1. Client sends one **standardized query** — **Torznab** (a torrent extension of the
   Newznab/RSS API): `?t=search&q=…&cat=…`.
2. Proxy translates it into a **site-specific HTTP request** (search URL, params,
   login/cookies).
3. Proxy **scrapes the results page** (or calls the site's own JSON API), extracting
   per row: title, magnet or `.torrent` URL, size, seeders, leechers, category, date.
4. Proxy **normalizes** back into a Torznab XML/RSS response.

Net effect: the client stays dumb; all per-site mess is isolated behind one uniform
API boundary.

## The scaling trick: definition-driven indexers (Cardigann)

The interesting part is how they avoid hand-coding hundreds of scrapers. Jackett and
Prowlarr both use **Cardigann-style YAML definitions** — one declarative file per
site describing:

- login method (form post / cookie / none),
- the search request (URL template, query params, category mappings),
- **selectors** (CSS/XPath + JSON/XML parsing) for the result-row and each field
  (title, magnet/download link, seeders, …).

A single site adapter reduces to: **request template + parse selectors + field
mapping**. The clearest illustration of "how do you programmatically search a torrent
site" is one of those `.yml` files — no code needed. See the Jackett
**Definition format** wiki and its `Cardigann/Definitions/*.yml`.

## How the magnet is actually obtained

Two paths (scrapers do one or both):

1. **Direct magnet scrape** — the page has a
   `magnet:?xt=urn:btih:<infohash>&dn=…&tr=…` anchor; select and extract it.
2. **`.torrent` → magnet** — only a `.torrent` file is linked; download it, parse the
   bencoded metadata, compute the **infohash** (SHA-1 of the bencoded `info` dict),
   and build the magnet from it. (Python `torf` does this parse/build step.)

Often there's a detail-page hop: search row → per-result page → magnet. That's why
definitions separate the "search row" selector from the "download" selector.

Easy case: some sites expose a **structured JSON API** (YTS/YIFY; The Pirate Bay via
`apibay.org`) so there's no HTML scraping — you get infohash/magnet + metadata
directly and rebuild the magnet with a known tracker list.

## Smaller code to read (than the .NET proxies)

- **MagnetMagnet** (Python) — scrapes magnet/name/size/seeders across several sites; compact.
- **pyYify** (Python) — wraps the YTS **official JSON API**; the "site gives you data" case.
- **TPB `apibay.org`** scripts — JSON API → rebuild magnet from infohash + tracker list.
- **1337x API** wrappers (BeautifulSoup4) — classic "parse the HTML table" pattern.
- **torf** (Python) — parse/create/edit `.torrent` files and magnet links.

## Why this is in our notes at all: the transferable pattern

The **definition-driven adapter pattern** is exactly the shape our legal-source
`AcquisitionResolver` should take: a resolver is *query template → fetch →
parse-to-magnet*, each source behind one uniform interface (this is why the seam is a
single swappable boundary — same idea as Torznab normalizing many sites to one API).

**Internet Archive** and **Academic Torrents** both expose real JSON/metadata APIs
(the "easy path" — no scraping), so our *legal* resolvers are the clean version of
this same pattern. Take the architecture lesson; leave the sources.

## Cross-language integration (the reference code is C# / Python)

**You almost never "port" C#/Python into Dart.** These tools are either small enough
to reimplement, or self-contained servers you consume as-is. Two realistic options
for a Flutter desktop app; **FFI and platform channels don't apply** (Dart FFI is the
C ABI — C#/Python aren't that; the Windows runner is C++, not .NET).

### Option A — Reimplement in pure Dart (recommended for in-scope resolvers)

A scraper's whole job is **HTTP request → parse → extract fields**, which is tiny in
Dart:
- `dio` / `http` — requests (cookies/headers for login flows)
- `html` (package:html) — parse HTML, query with **CSS selectors** (the exact
  primitive Cardigann definitions use)
- `xml` — Torznab/RSS or XML APIs
- `json_serializable` — the easy JSON-API case (our legal path)

One site adapter ≈ 30–60 lines, mapped onto an `AcquisitionResolver` impl. (If you
ever needed dozens of sources you *could* write a Dart interpreter that executes
Cardigann YAML definitions generically — only worth it at scale; for a handful,
hand-written Dart resolvers are simpler.) Usually the magnet is already in the HTML,
so you rarely need `.torrent`→infohash computation.

**This is the in-scope answer.** Internet Archive / Academic Torrents return JSON, so
a legal resolver is `dio.get(...)` + a `json_serializable` DTO + pull the magnet URL
— ~40 lines, pure Dart, single binary.

### Option B — Sidecar the existing tool (reuse it wholesale, out-of-repo hypothetical)

Architecturally native to this app already: it spawns **qBittorrent-nox as an
invisible localhost child** ("the daemon is invisible" invariant). Jackett/Prowlarr
are the same shape — **self-contained servers exposing an HTTP Torznab API**:

1. Bundle the binary,
2. `Process.start` it bound to `127.0.0.1:<port>` (like the daemon),
3. Call its Torznab endpoint from Dart (`dio` + parse XML),
4. Shut it down on exit.

**No porting** — you inherit hundreds of maintained site definitions. Cost: you ship
a second runtime (.NET for Jackett/Prowlarr; a PyInstaller-frozen `.exe` + bundled
Python for the Python scrapers, talking JSON over stdout or a tiny local HTTP
server), plus an extra process to babysit.

### Trade-off

| | Option A (pure Dart) | Option B (sidecar) |
|---|---|---|
| Effort | maintain each adapter | zero reimplementation |
| Breadth | what you write | hundreds of definitions |
| Bundle | single binary | +runtime, +process |
| Fit | matches `AcquisitionResolver` directly | matches "invisible daemon" pattern |

App-side code is identical either way: an `AcquisitionResolver` returning a magnet —
the only difference is whether it hits a bundled sidecar's localhost API or a remote
JSON API. The seam is exactly what lets you swap between them without the play flow
caring. **In-repo stays legal-source (Option A over JSON APIs); Option B is the
mechanical answer to the hypothetical, not a suggestion to bundle an indexer here.**

## Provider shapes compared (against the real seam)

All of these implement the **identical** seam —
`AcquisitionResolver.resolve(ShowMeta, season, episode) → Future<TorrentHandle?>`
(`lib/src/services/acquisition/acquisition.dart`). Same input, same `TorrentHandle`
(a magnet) out, `null` when nothing's found. Everything downstream — the daemon
handoff, `readyToStream()`, the play flow — is byte-for-byte identical and cannot
tell which produced the handle. The differences live **entirely inside `resolve()`**.

Three shapes are worth contrasting. Note that **the legal provider and a pure-Dart
scraper are the *same* Option A shape** (stateless Dart HTTP client, single binary) —
they differ only in *what they parse* and *how much brittleness you own*. The legal
one is simply Option A pointed at a stable JSON API instead of a scraped HTML page.

**1. Legal JSON resolver — Option A over a documented API (IN SCOPE).**
Internet Archive / Academic Torrents. A thin **stateless** `dio` client hits a
**remote JSON API** directly, maps a `json_serializable` DTO, picks a match, builds
the handle (IA's `.torrent` URL is even *derivable* from the item id). A **handful of
candidates or none** — `null` is normal for mainstream content. Season/episode mostly
N/A (films/lectures). No process, ~no config, tiny failure surface (network /
not-found). Legal exposure: none — the source *is* the license.

**2. Pure-Dart scraping resolver — Option A pointed at an indexer (HYPOTHETICAL).**
Same stateless single-binary shape as #1, but it fetches an indexer's **HTML** and
parses it with **CSS selectors** (`package:html`) instead of JSON. Now you get
**many candidates**, so you own **ranking/selection** (seeders/quality/size) *and*
you own **every selector** — the adapter breaks when the site changes its markup, and
you handle blocking/captcha yourself. You implement season/episode query mapping by
hand. Breadth scales only by writing more adapters (or a Dart Cardigann interpreter).
**Legal exposure is worst here** — the scraping logic lives in *your* repo/binary,
not offloaded anywhere.

**3. Jackett / Prowlarr sidecar — Option B (HYPOTHETICAL).**
Does **not** scrape itself. A **stateful** provider that spawns and babysits a bundled
**localhost sidecar** (the qBittorrent-nox "invisible daemon" pattern), which fans out
to N indexers and returns one normalized **Torznab XML** feed. Your Dart just queries
(`title + season + ep + category`), parses XML, and **ranks** the pile. Per-site
brittleness is **offloaded to the sidecar's maintained community definitions** — you
inherit hundreds for free. Cost: a bundled runtime + a managed process, a bigger
failure surface (process down, indexer down, rate-limit, captcha), and legal exposure
that lives in the sidecar + its indexer list.

| Dimension | 1. Legal JSON (in scope) | 2. Pure-Dart scrape | 3. Jackett/Prowlarr sidecar |
|---|---|---|---|
| Interface | `resolve() → TorrentHandle?` | identical | identical |
| Option | A (JSON) | A (HTML) | B |
| Data source | remote JSON API, direct | remote HTML page(s), direct | localhost sidecar over many sites |
| State / process | stateless | stateless | **stateful** — spawn/manage a child |
| Parse | JSON → DTO | **HTML → CSS selectors** | Torznab **XML** |
| Candidates | few, or none | many (per site) | dozens across many sites |
| Core logic | search + pick | scrape + parse + **rank** | query + **rank** (parsing done by sidecar) |
| Per-site upkeep | none (stable API) | **you own every selector** | offloaded to maintained definitions |
| Season/episode | mostly N/A | you map it by hand | first-class (Torznab) |
| Bundle | single binary | single binary | + runtime + process |
| Config | base URL / key | adapters in code | binary + endpoint/key + indexer list |
| Failure modes | network / not-found | network + selector-break + captcha | process/indexer down, rate-limit |
| Legal exposure | none (clean) | **worst — in your code** | in the sidecar |
| Breadth vs effort | narrow but trivial | scales by writing adapters | hundreds, ~free |

**Takeaway:** moving from #1 → #2 you keep the lean stateless shape but take on
parsing fragility, ranking, and the legal exposure directly in your binary. Moving
#2 → #3 you shed the per-site brittleness (someone else maintains the definitions)
but take on a process lifecycle and a fatter bundle. #1 is the only one in scope
precisely because it has the lean shape of #2 *without* the brittleness or exposure —
a stable JSON catalog you're licensed to read.

## Jackett as a bundled sidecar (packaging & runtime)

Decision (2026-07-07, DECISIONS §D): the indexer path ships as a **bundled Jackett
sidecar** — an invisible localhost child process, same model as qBittorrent-nox —
constrained to the user's own **legal / public-domain** indexer configuration.

**Runtime.** Jackett is **C# on .NET 9** (`net9.0`), cross-platform. It ships
**self-contained** builds (`dotnet publish --self-contained -r <rid>`) that bundle the
.NET runtime, so the TV PC needs **no .NET installed** — you ship Jackett's own copy
per platform alongside the app.

**What you spawn (sidecar mode — NOT the service installers).** Ignore the Windows
Service installer, systemd units, and tray app; those are standalone-deployment paths.
As a sidecar you launch the console host in the foreground, bound to localhost:
- **Windows:** `JackettConsole.exe` (not `JackettService.exe` / `JackettTray.exe`).
- **Linux:** the bundled self-contained `jackett` launcher (runs natively — no `dotnet`
  prefix, no `install_service_systemd.sh`).

Both start the web server + Torznab API on port **9117** and stop when the process is
killed.

**From Dart it's one control flow** (per-OS difference is just the exe path, like
qBittorrent-nox):
`Process.start(<jackett exe>, ['--Port', '9117', '--DataFolder',
<app-support>/jackett, '--NoRestart', '--NoUpdates'])` → poll `http://127.0.0.1:9117`
until Torznab answers → query → `process.kill()` on exit.

**Account / API key.** No Jackett account or external signup exists — it's fully local.
The Torznab **API key is auto-generated by Jackett on first run** and stored in
`ServerConfig.json` under `--DataFolder`; the app reads it there to auth its own calls.
(Only a *private* indexer configured inside Jackett would need credentials —
public/legal indexers need none.)

**Gotchas.**
1. **Bundle size** — self-contained .NET is ~**50–100 MB per platform** added to the
   installer (ships a separate win-x64 and linux-x64 copy). Works against the
   lightweight/one-click feel; qBittorrent-nox is also heavy, so there's precedent.
2. **`--DataFolder`** — point it at the app-support dir so indexer config + the
   generated API key persist per-user.
3. **`--NoUpdates`** — otherwise Jackett self-updates your bundled copy out from under
   you; pin to the version you shipped and update on your own release cadence.

## Links

- Jackett: https://github.com/Jackett/Jackett — Definition format:
  https://github.com/Jackett/Jackett/wiki/Definition-format
- Prowlarr: https://github.com/Prowlarr/Prowlarr — Servarr indexer wiki:
  https://wiki.servarr.com/prowlarr/indexers
- MagnetMagnet: https://github.com/eliasbenb/MagnetMagnet
- pyYify: https://github.com/nateshmbhat/pyYify
- torf: https://github.com/rndusr/torf
- Public tracker lists (the *other* "trackers"): https://github.com/ngosang/trackerslist
