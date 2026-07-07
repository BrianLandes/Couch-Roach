# CLAUDE.md

Guidance for Claude Code when working in this repo.

**Couch Roach** is a **Flutter desktop** app (Windows 11 first, Linux later) — a
single-machine, one-click **home media center** for a TV PC. It's an *orchestration
shell*, not a media engine: the Flutter app **coordinates**, a torrent daemon
**acquires**, and libmpv **plays**. Full design in [docs/HANDOFF.md](docs/HANDOFF.md);
resolved decisions and deltas in [docs/DECISIONS.md](docs/DECISIONS.md) — **read
DECISIONS.md first when resuming**, it's the source of truth for what's been settled.

The core stack is wired up and **must be used** for the concerns below:

- **drift** (`drift`) — local SQLite store (library, watch history, storage config);
  schema + `AppDatabase` in [lib/src/data/db/database.dart](lib/src/data/db/database.dart).
  This is the only persistence layer — there is **no** remote/Supabase backend; the app
  is single-machine and single-trust-boundary (no auth, no RLS).
- **injectable + get_it** — dependency injection; container in
  [lib/src/injection.dart](lib/src/injection.dart). All services and singletons register
  here (see Services).
- **json_serializable** — serialization for anything crossing the **network** boundary
  (TMDB / OpenSubtitles JSON). Local rows use drift, not this. Reference model:
  [lib/src/data/tmdb/tv_show_summary.dart](lib/src/data/tmdb/tv_show_summary.dart).
- **flutter_riverpod** — UI state; `ProviderScope` at the app root in
  [lib/main.dart](lib/main.dart) (see State management).
- **go_router** — navigation; all routes in
  [lib/src/router/app_router.dart](lib/src/router/app_router.dart) (see Navigation).
- **media_kit** (libmpv) — playback, embedded in-process; player in
  [lib/src/features/player/player_screen.dart](lib/src/features/player/player_screen.dart).
  **Don't build a video player** — codecs, containers, subtitles, and resume position are
  delegated to libmpv.

The app is built in milestones (M1 local player → M2 discovery → M3 subtitles →
M4 acquisition; see HANDOFF §7). Sections describing not-yet-built pieces say so inline.
The task-tracking and coding-style guidelines are adapted from a sibling Flutter project
so both codebases stay consistent.

---

## Todoist task tracking

Dev tasks for this repo are tracked in **Todoist** via the `todoist` MCP server. Keep the
task list current from the repo: push new work, pull active items, and flip status as work
progresses.

### Where tasks live

- **Project:** `Couch Roach` — project id `6h3xW6q4HRmCPC3p` (board view).
- Push repo tasks to this project, **not** the Inbox.
- Account: Brian Landes (userId `59594567`), timezone `America/Denver`, Todoist Free plan.

### Status model — board sections

Status is tracked by which **board section (column)** a task sits in — not by a label. The
project (board view) has four columns:

| Section     | Section id         | Meaning                                       |
| ----------- | ------------------ | --------------------------------------------- |
| Backlog     | `6h3xW7cG9m3H5gpp` | Captured but not yet queued for current work  |
| To Do       | `6h3xW7cfqWhC3RXp` | Queued and ready to pick up                   |
| In Progress | `6h3xW7XMw8hqX42p` | Actively being worked (aim for one at a time) |
| Done        | `6h3xW7XvRM3V29gp` | Finished work — move here, *then* complete    |

**Finishing a task is two steps, in this order:** move it to the **Done** section
(`update-tasks` with `sectionId: "6h3xW7XvRM3V29gp"`), *then* `complete-tasks` it. Section
membership survives completion, so completed tasks stay grouped under Done in the
completed-tasks view. **Order matters** — a task cannot be re-sectioned after it's completed
(you'd have to `uncomplete-tasks` → move → re-complete).

### Lifecycle → tools

- **Push a new task** → `add-tasks` with `projectId: "6h3xW6q4HRmCPC3p"` and a `sectionId`
  (usually To Do `6h3xW7cfqWhC3RXp`, or Backlog `6h3xW7cG9m3H5gpp` if not yet queued).
  Set `priority` (`p1` highest … `p4` default), `dueString`, and `description` as needed.
- **Move between columns** → `update-tasks` with the new `sectionId`.
- **Start work** → move the task to In Progress (`sectionId: "6h3xW7XMw8hqX42p"`); aim for
  one in-progress task at a time.
- **Pull "what I'm working on"** → `find-tasks` with `sectionId: "6h3xW7XMw8hqX42p"`.
- **List all open repo tasks** → `find-tasks` with `projectId: "6h3xW6q4HRmCPC3p"`.
- **List finished tasks** → `find-completed-tasks` (optionally `sectionId: "6h3xW7XvRM3V29gp"`).
- **Mark done** → first move to Done (`update-tasks` `sectionId: "6h3xW7XvRM3V29gp"`), *then*
  `complete-tasks`. Always in that order — section can't be changed after completion.

### Conventions & gotchas

- Priorities are **strings** (`p1`–`p4`); integers are rejected. `p1` is highest, `p4` default.
- To **reschedule** an existing task's due date, use `reschedule-tasks`, not `update-tasks`
  (update replaces the whole due string and destroys recurrence).
- `find-tasks` requires at least one filter (text, project, section, label, or filter string).
- The Todoist MCP tools are deferred — load their schemas with `ToolSearch`
  (`select:mcp__Todoist__<name>`) before calling them.

---

## Working Through a Todoist Task

Use the Todoist MCP tools to read and analyze a task before touching any code. Follow these
steps in order.

### 1. Read the task

Fetch the task (`find-tasks`, or `fetch-object` by id) and read its `content` and
`description`. Read any discussion with `find-comments`. Note requirements, explicit
decisions, and open questions.

### 2. Move it to In Progress

Move the task to the **In Progress** column via `update-tasks`
(`sectionId: "6h3xW7XMw8hqX42p"`) so the board reflects what you're actively working on.
Aim for only one task in In Progress at a time.

### 3. Audit existing code

Before planning any new code, search the codebase for anything that already addresses the task:
- Existing tables/columns in [lib/src/data/db/database.dart](lib/src/data/db/database.dart)
- Existing service, repository, or model code that overlaps the requirements
- Screens or widgets adjacent to the feature area (under `lib/src/features/`)

### 4. Assess data-model changes

For every proposed schema change (new table, new column):
- **New table:** Ask whether the data can live as column(s) on an existing table. Only add a
  new table if the entity is genuinely distinct and would otherwise violate normalization.
- **New column:** Prefer adding to an existing drift table when the data is a direct property
  of that entity.
- Every schema change means **bumping `schemaVersion`** and adding a step to the drift
  `MigrationStrategy` (see Local database below). Document the rationale for any decision that
  deviates from the task's proposal.

### 5. Gap analysis

Produce a concise list of what the task requires versus what already exists — already
implemented (no action), partially implemented (needs extension), missing (build from
scratch). Present it and get alignment before writing code.

### 6. Implement in dependency order

Work bottom-up so each layer compiles before the next depends on it:

1. **drift schema + migration** — add/extend tables, bump `schemaVersion`, add the migration
   step; run `build_runner`
2. **Models** — add or extend `json_serializable` DTOs for any new API shapes; run `build_runner`
3. **Repository interface** — add method signatures to the relevant repository
4. **Repository implementation** — implement against the drift `AppDatabase` / HTTP client
5. **Service** — add orchestration methods in the relevant `@LazySingleton` service
6. **State + widgets** — Riverpod providers and UI components
7. **Screens + routes** — wire widgets/services together; register a `GoRoute` for new screens
8. **Tests** — repository/service tests against an in-memory drift DB; widget tests for
   complex rendering

Mark each layer done before moving to the next.

### 7. Comment and complete

After implementation **and after the user has approved it**, post a brief summary comment on
the task with `add-comments` (what was implemented, deviations and why, follow-up gaps). Then
finish it: move the task to the **Done** section (`sectionId: "6h3xW7XvRM3V29gp"`) and
`complete-tasks` it, in that order.

---

## Coding Guidelines

### Local database (drift)

drift is the only store. **Prefer drift's typed query API / DAOs over raw SQL** — use the
generated table classes and `.select()` / `.into()` / `managers`. Reach for `customSelect`
only when a query genuinely can't be expressed in the builder.

Schema changes go through drift's migration mechanism, not ad-hoc mutation:
- Edit the table classes in [database.dart](lib/src/data/db/database.dart).
- **Bump `schemaVersion`** and add an `onUpgrade` step to a `MigrationStrategy`.
- **Never** change what an already-shipped migration step did — add a new step for the new
  version. (Pre-release, before any DB exists in the wild, editing v1 tables directly is fine.)
- Regenerate with `dart run build_runner build` after any table change.

There is **no RLS / row-level auth** — this is a single-machine app the app itself is the only
client of. Don't add multi-user access-control machinery.

### Services

All services register with the DI container using `injectable` annotations. Use
`@LazySingleton()` for services that hold state or are expensive to create, and `@Singleton()`
for services that must be eagerly initialized.

```dart
import 'package:injectable/injectable.dart';

@LazySingleton()
class ExampleService {
  ExampleService(this._db); // constructor deps are auto-wired by injectable
  final AppDatabase _db;
}
```

Retrieve services via `getIt<ServiceName>()` in widgets, or declare them as constructor
parameters in other services. App-wide services live under `lib/src/` in their feature or
`core/` area. The container is [lib/src/injection.dart](lib/src/injection.dart): `getIt` is the
locator and `configureDependencies()` (called in `main()` after `MediaKit.ensureInitialized`)
registers everything. `RegisterModule` there provides manually-constructed singletons
(`AppDatabase`, `StorageManager`) so a service can just take them as constructor parameters.
After adding or changing an annotated service, regenerate with `dart run build_runner build`.
`injection.config.dart` is generated — **never edit it by hand**.

### Data Models & Serialization

Use `json_serializable` for any class serialized to/from **JSON** (TMDB, OpenSubtitles). Local
persistence uses drift row classes, not this.

```dart
import 'package:json_annotation/json_annotation.dart';

part 'my_model.g.dart';

@JsonSerializable()
class MyModel {
  @JsonKey(name: 'db_column_name')
  final String fieldName;
  MyModel(this.fieldName);
  factory MyModel.fromJson(Map<String, dynamic> json) => _$MyModelFromJson(json);
  Map<String, dynamic> toJson() => _$MyModelToJson(this);
}
```

See [tv_show_summary.dart](lib/src/data/tmdb/tv_show_summary.dart) for a worked reference.
DTOs live under the client's directory (`lib/src/data/tmdb/`, etc.). Regenerate `*.g.dart`
with `dart run build_runner build` after adding/changing a model. When a field can arrive as an
unexpected type from the API, add a top-level converter and wire it via `@JsonKey(fromJson: …)`
rather than editing the generated file.

### State Management (Riverpod)

Use **Riverpod** for UI-facing reactive state. `ProviderScope` wraps the app in
[lib/main.dart](lib/main.dart). Define state as providers; `ref.watch` them in `build` (rebuilds
on change) and `ref.read` them in callbacks. Prefer a `StreamProvider` fed by a **drift watch
query** (`.watch()`) so screens update live as the library / watch history changes.

Keep the layers distinct: **services and singletons** live in get_it/injectable (the backend-y
work — scanning, storage, clients); **UI state** lives in Riverpod providers that read from
those services. Put providers in the relevant feature directory.

### Navigation (go_router)

All navigation goes through **go_router**. Routes are declared in one place —
[app_router.dart](lib/src/router/app_router.dart) — each with its path as a constant on
`Routes`. Navigate with `context.go(...)` / `context.push(...)` and the `Routes.*` constants;
**never** hardcode a path string at a call site, and don't use a bare
`Navigator.push(MaterialPageRoute(...))` in feature code. Register a new screen by adding a
`GoRoute` (and a `Routes` constant).

### Error Handling

Any operation that can fail (network calls, DB access, file I/O, spawning the daemon) must both
**surface the failure to the user** (an error state / snackbar in the 10-foot UI) and **log it**
through `ErrorLogService`
([lib/src/core/logging/error_log_service.dart](lib/src/core/logging/error_log_service.dart)) —
the single sink every system opts into:

```dart
try {
  await risky();
} catch (e, st) {
  getIt<ErrorLogService>().logError(e, stackTrace: st, source: 'PlayerScreen.play');
  // …then show the user an error state.
}
```

It appends human-readable entries to a local text log at `<app-support>/logs/couch_roach.log`
(shown in the Storage settings screen — there's no remote backend). Uncaught framework/async
errors are captured automatically: `main()` installs `FlutterError.onError`,
`PlatformDispatcher.onError`, and a guarded zone that all route here. Always pass a `source`
(`Class.operation`) so entries are traceable. Capture any `BuildContext`-derived objects
(`ScaffoldMessenger`, `GoRouter`) before an `await` when the widget may be unmounted by the time
the call returns.

---

## Project-specific invariants (read this)

These are load-bearing for this app specifically — don't violate them without discussion.

- **Acquisition is a single, swappable seam.** All torrent sourcing goes through
  `AcquisitionResolver` in
  [lib/src/services/acquisition/acquisition.dart](lib/src/services/acquisition/acquisition.dart).
  Only **legal-source** resolvers belong in this repo (Internet Archive, Academic Torrents,
  distro feeds). **Do not add** a resolver that searches piracy trackers or a Prowlarr/Jackett
  indexer for commercial content — that's deliberately out of scope (HANDOFF §8). The play flow
  must never reference where a magnet came from.
- **All file placement goes through `StorageManager`.** The machine has multiple disks; content
  spreads across them by free space. Never hardcode a single library root — scan every root the
  manager reports, and pick download targets via `chooseTarget`. See
  [lib/src/core/storage/storage_manager.dart](lib/src/core/storage/storage_manager.dart).
- **Cleanup lifecycle.** The configured library folders are the app's to manage: files that land
  there get hydrated (metadata + subtitles) and then reaped after a full watch + grace period,
  deleting the video and its `.en.srt` sidecar. A file pinned `keep = true` is never
  auto-deleted. Only touch files that are `completed` and past grace. See
  [lib/src/services/cleanup/watched_reaper.dart](lib/src/services/cleanup/watched_reaper.dart).
- **Secrets via `--dart-define`.** API keys are read through `AppConfig`
  ([lib/src/core/config/app_config.dart](lib/src/core/config/app_config.dart)); **never** commit
  a key or hardcode one in source.
- **The daemon is invisible.** The app spawns qBittorrent-nox as a child process bound to
  localhost on a fixed port and shuts it down on exit. The user launches one thing.
- **`MediaKit.ensureInitialized()`** must run in `main()` before any player is created.

---

## Design system — "Liquid Glass", 10-foot / TV UX

Full guide in **[docs/STYLE.md](docs/STYLE.md)**. The look is **liquid glass**:
translucent frosted surfaces floating over a dark, softly-glowing ambient background, with
bright focus rings for the remote.

- **Use the tokens — never hardcode.** All colors/spacing/radii/type live in
  [lib/src/theme/](lib/src/theme/) (`AppColors`, `AppSpacing`, `AppRadii`, `AppTypography`,
  `AppGlass`, `AppTheme`); import the [theme barrel](lib/src/theme/theme.dart). No raw hex,
  magic sizes, or font names in widgets. Prefer `Theme.of(context).textTheme.…`.
- **Glass over glow.** Wrap foreground content in `GlassSurface` (not a plain `Card`), and put
  an `AmbientBackground` behind each screen so the blur has color to refract. Glass on a flat
  black void reads dead.
- **Dual input — focus *and* pointer.** The remote acts like a mouse, so every interactive
  element must work with **both** arrow-key/D-pad focus **and** the pointer: highlight on focus
  **or** hover, and activate on Enter/Space **or** click. Use `FocusableCard`
  ([lib/src/widgets/focusable_card.dart](lib/src/widgets/focusable_card.dart)) rather than
  hand-rolling this. Bright cyan focus ring + glow (`AppColors.focus` / `focusGlow`); honor
  `AppSpacing.minTouchTarget`.
- **Focus follows scroll.** Moving the selection to an off-screen item must scroll it *fully*
  into view (`Scrollable.ensureVisible` on focus — `FocusableCard` does this).
- **Back button on every screen except the landing page.** Use `AppBackButton`
  ([lib/src/widgets/app_back_button.dart](lib/src/widgets/app_back_button.dart)); it pops the
  nav stack (`context.pop()`). The landing page is the root and has none.
- **Continue Watching is the top rail** on the landing page — the highest-value surface.

There's a **living component gallery** at
[lib/src/features/dev/style_showcase_page.dart](lib/src/features/dev/style_showcase_page.dart)
(route `Routes.styleShowcase`, `/style`). Use it as the palette when building UI, and **add each
new shared widget to it** so the reference stays current.

---

## Testing

New features and non-trivial widgets should be accompanied by tests. Run everything with
`flutter test`.

- **Repository / service logic** — test against an **in-memory drift database**:
  `AppDatabase.forTesting(NativeDatabase.memory())`. This exercises the real schema and query
  shapes — it catches migration and constraint issues that mocks can't.
- **Widgets** — widget tests for components with significant conditional rendering; there's a
  baseline shell test in [test/widget_test.dart](test/widget_test.dart).

> **Sandbox note:** `flutter test` runs in the Claude Code cloud container (drift's in-memory
> `NativeDatabase` works there). Occasionally the first run fails while fetching the native
> `libsqlite3` binary through the proxy (a checksum mismatch) — that's environmental, not a code
> problem; retry, and it runs normally on a real machine regardless.

---

## Key Conventions

- **Codegen.** `drift`, `injectable`, and `json_serializable` all generate code. After changing
  a drift table, an `@injectable` service, or a `@JsonSerializable` model, run
  `dart run build_runner build`. **Never hand-edit** `*.g.dart` or `injection.config.dart`.
  Generated files are committed so the repo builds without a codegen step; keep them in sync.
- **Dependency pinning.** `drift` / `drift_dev` are pinned **`<2.32.0`** on purpose: 2.32.1–2.34.0
  ship a codegen bug and the 2.34.2 fix requires analyzer 13, which `injectable_generator`
  (analyzer ≤10) can't use. Bump the drift toolchain and injectable together once injectable
  supports analyzer 13. Resolved set: drift 2.31.0, analyzer 10.2.0, injectable_generator 2.12.1,
  json_serializable 6.14.0.
- **Environment.** Built with **Flutter 3.44.5 / Dart 3.12.2**. Windows is the primary target;
  Linux runner exists; Android/macOS are not set up.
- **Build loop.** `flutter pub get` → (`dart run build_runner build` if codegen changed) →
  `flutter analyze` → `flutter run -d windows --dart-define=…`. See
  [README.md](README.md) for the full setup.
