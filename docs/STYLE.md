# Couch Roach — Style Guide

The look: **slick, simple, modern — "liquid glass."** Translucent frosted
surfaces floating over a dark, softly-glowing ambient background, with bright
focus rings for the remote. Think visionOS / iOS "Liquid Glass": everything is a
little translucent and fluid, content reads first, chrome gets out of the way.

Design tokens live in **[lib/src/theme/](../lib/src/theme/)** (`AppColors`,
`AppTypography`, `AppSpacing`, `AppRadii`, `AppGlass`, `AppTheme`) — import the
[theme barrel](../lib/src/theme/theme.dart). The Material theme is applied in
`app.dart` via `MaterialApp.router(theme: AppTheme.dark)`. **Always use these
constants and the theme's text/color styles — never hardcode a hex, size, or
radius in a widget.**

There's a **living component gallery** at
[lib/src/features/dev/style_showcase_page.dart](../lib/src/features/dev/style_showcase_page.dart),
route `Routes.styleShowcase` (`/style`) — palette, type ramp, glass panels,
buttons, status pills, the focus ring, and inputs. Use it as the palette when
building UI, and **add new shared widgets to it** as they land.

---

## The vibe

- **Glass over glow.** Nothing is a flat grey card. Foreground surfaces are
  frosted glass (`GlassSurface`) sitting on an [AmbientBackground] whose soft
  color blobs give the blur something to refract. No ambient color behind →
  glass looks dead.
- **Dark, cinematic, calm.** Near-black cool base so posters and video pop.
- **Iridescent accents, used sparingly.** Periwinkle → cyan is the signature
  pairing; magenta is a rare pop. Accents highlight, they don't fill the screen.
- **Content first, chrome quiet.** Big legible type, generous spacing, soft
  rounded corners. Playful materials, serious legibility.

## Palette (→ `AppColors`)

| Token | Hex | Role |
| --- | --- | --- |
| `bg` / `bgElevated` | `#05060A` / `#0B0D15` | base layers everything floats on |
| `primary` | `#6C7DFF` | periwinkle/indigo — the anchor, primary fills |
| `secondary` | `#38E1FF` | cyan — highlights and **focus rings** |
| `tertiary` | `#FF6AD5` | magenta — sparing pops |
| `success` / `warning` / `danger` | `#3DE0A0` / `#FFC24B` / `#FF5C7A` | status |
| `textPrimary` / `textSecondary` / `textTertiary` | `#F3F5FF` / `#AAB1CC` / `#6E7591` | body / muted / faint |
| `glowIndigo` / `glowViolet` / `glowCyan` | — | ambient background blobs |

**Glass tokens** (alpha baked in): `glassFill` (~8% white), `glassFillStrong`
(~13%, for foreground surfaces), `glassStroke` (~18% hairline border),
`glassHighlight` (top-edge sheen). Signature pairing: **cyan-on-dark for focus,
periwinkle for primary action.**

## Glass surfaces (→ `GlassSurface`, `AppGlass`)

Wrap content in `GlassSurface` instead of a plain `Card`/`Container` to get the
frosted look (a `ClipRRect` + `BackdropFilter` blur + translucent gradient fill +
hairline border + top sheen). Blur levels: `AppGlass.blur` (24, standard),
`blurStrong` (40, nav/modals), `blurThin` (12, chips). Use `strong: true` for
foreground surfaces (dialogs, the nav bar) that need more presence.

## Typography (→ `AppTypography`)

Platform default family (no runtime font download — keeps the app offline-ready),
sizes nudged up for 10-foot legibility. Ramp: `displaySmall` 40 / `headlineMedium`
30 / `titleLarge` 22 / `titleMedium` 18 / `bodyLarge` 17 / `bodyMedium` 15 /
`labelLarge` 15. Prefer `Theme.of(context).textTheme.…` over ad-hoc `TextStyle`.
(A bundled custom display font can be added later if we want more character.)

## Spacing & radii (→ `AppSpacing`, `AppRadii`)

Spacing `xs 4 … xxl 48`, `screenPadding 48` (TV edge inset), `minTouchTarget 56`
(comfortable D-pad targeting). Radii `sm 10 … xl 30`, `pill 999` — generous and
soft; buttons are pill-shaped, panels are `lg`.

## 10-foot / remote UX (load-bearing)

The remote is used **like a mouse** on Windows/Linux, so the app is driven both
ways — plan for both, always:

- **Dual input: focus *and* pointer.** Every interactive element must respond to
  **both** arrow-key/D-pad focus **and** the pointer — highlight on focus **or**
  hover, activate on Enter/Space **or** click. Reach for `FocusableCard`
  (`lib/src/widgets/focusable_card.dart`) instead of re-implementing it per widget.
- **Bright cyan focus ring + glow** (`AppColors.focus` / `focusGlow`) on the
  focused/hovered element. Test with arrow keys only *and* with the mouse.
- **Focus follows scroll.** Arrowing to an item that's partly or fully off-screen
  must scroll it **fully into view** (`Scrollable.ensureVisible` on focus — built
  into `FocusableCard`).
- **Back button on every screen except the landing page.** Use `AppBackButton`
  (`lib/src/widgets/app_back_button.dart`) — it pops the nav stack. The landing
  page is the root.
- **Big targets, high contrast, legible from a couch.** Honor `minTouchTarget`.
- **Continue Watching is the top rail** on the landing page.
- Motion is soft and quick (≈150–200ms) — fluid, never flashy.

## Do / Don't

- **Do** float glass on ambient glow; **don't** put glass on a flat black void.
- **Do** use accents to highlight; **don't** flood a surface with saturated color.
- **Do** pull every color/size/radius from the tokens; **don't** hardcode values.
- **Do** add each new shared widget to the gallery so the reference stays live.
