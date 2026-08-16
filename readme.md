# Evolution Lab Design System

A design system for **Evolution Lab**, a Roblox creature-collecting/incremental "simulator" game (evolve creatures, collect DNA, unlock zones, fight for loot). Built from screenshots the user supplied directly from the game and from a second reference set showing the "brainrot simulator" comic-outline visual style (Bobritto Pack / Chimpanzini Bananini imagery) that the user wants Evolution Lab's UI redesigned toward.

## Sources
- GitHub repo given as the primary source: **LightninggXD/evolution-lab** (https://github.com/LightninggXD/evolution-lab) — at time of import the repo returned no readable files (empty or inaccessible at `main`/`master`). Nothing was copied from it. If you get repo access working, re-run a sync — this system should be rebuilt against the real code once available.
- 10 screenshots of Evolution Lab's current UI (HUD, zones list, daily rewards, Robux shop, playtime gifts, combat).
- 5 screenshots of a different, more polished "brainrot simulator" style Roblox game (daily rewards, season pass, world/HUD), used as the target visual direction (thick black outlines, comic font, hard drop shadows) since the user shared these as "design examples."

  **Only 4 of those 15 actually landed on disk** (`daily-modal`, `playtime-modal`, `robux-shop`,
  `zones-modal`) — the other 11, including every `ref2-*` style target, exceeded a 256 KB transfer
  cap during the original import and were written out truncated. Recovery from the session cache
  was attempted and produced only the top 5-27% of each image, so nothing was restored. **Please
  re-send the reference screenshots**, especially the `ref2-*` brainrot-style ones — they are the
  target the rebuild is judged against, and right now no copy of them exists.
- No Figma file was provided.

**Caveat:** because the GitHub source was empty, this system is built entirely from screenshots, which is lossier than source code (icons are recreated as emoji/placeholders, not the original sprites; exact hex values and font are estimated). Re-attach the repo with real content, or provide Figma/exported icon assets, for a more accurate rebuild.

## Products
Single product: **Evolution Lab** (Roblox game client UI — HUD, shop, zone/world select, daily rewards, combat).

## Components
Core: `Button`, `StatCard`, `CurrencyPill`, `IconBadge`.
Feedback: `Modal`, `ProgressBar`, `DamageText`, `RewardTile`, `Tag`.
Navigation: `NavRail`, `ZoneRow`.

### Intentional additions
None of these were pulled from a component-library source (no accessible codebase/Figma) — they're a standard inventory sized to what's visible across both screenshot sets: buttons, currency/stat readouts, circular icon shortcuts, dialogs, reward tiles, tags/ribbons, progress bars, damage callouts, nav rail and zone rows.

## Content fundamentals
- **Tone:** hype-y, casual, exclamation-heavy. "Use the DNA Machine or fight creatures to collect DNA!", "Come back tomorrow for Day 2!", "OP!", "Join Tomorrow For A Special Reward!"
- **Casing:** Title Case for labels and card names ("Mutation Chance", "Auto Attack"); ALL CAPS reserved for hype tags ("NEW!", "OP!", "FREE!", "LIMITED TIME").
- **Person:** implicit second person via imperative commands ("Use the DNA Machine…"), never "I" or narrator voice.
- **Numbers:** always abbreviated with suffixes as they grow — K → M → B → T → Qa → Qi → Sx… ("459.33K", "36.76Qi", "7Sx / 840Sx"). Never show a raw 6+ digit number.
- **Emoji/icon-as-word:** icons prefix almost every label instead of being purely decorative (🚀 Use the DNA Machine, 🧬 12 DNA, 🎁 Daily Rewards!) — the icon carries meaning, not just flavor.
- **Exclamation marks are the default**, not the exception — nearly every headline and CTA ends in "!".
- **Urgency/reward framing:** timers ("in 8m 16s", "13:15:37"), streak counters ("Streak: 1 day"), locked-vs-unlocked framing ("Requires: Bacteria").

## Visual foundations
- **Direction:** thick-outline "comic sticker" style — every panel, button, and icon gets a heavy dark outline plus a flat (non-blurred) drop shadow offset straight down. No soft glows, no blur, no gradAients-as-depth.
- **State colour — a finished thing is not a disabled thing (added 2026-08-16, ROADMAP 18.5).** The kit has one grey and four states reached for it. Three of them are refusals and grey is right; the fourth is *done*, and painting an achievement in the refusal colour is what made a week of collected rewards read as a morgue. Three states, three axes: **claimable** = full chroma and the loudest thing on the panel; **done** = the same hue at a third of the chroma (`UITheme.DoneShade`, which also lifts every result to luminance 0.90 so the ink can never flip); **locked** = no hue at all (`Color.Locked`).
- **Color:** warm cream/white panel surfaces (`--cream-panel`) on a muted desaturated backdrop; saturated flat accents carry meaning — green = go/claim/success, gold = currency/premium, blue = info/portals, red = danger/new, purple = rare/evolve. Max one background color per screen; accents do the work.
- **Type:** one bold rounded display face throughout (Baloo 2, substituted — see Fonts note). Two treatments: (1) big headlines get white fill + thick dark stroke + hard drop shadow (Daily Rewards!, Season Pass!); (2) card labels/values are solid-fill, no stroke, for readability at small sizes.
- **Spacing:** 4/8/12/16/20/24/32/40px scale; HUD elements sit in a consistent gap rhythm, never touching edges directly (always padding).
- **Corner radii:** 10px small badges, 16px cards, 20-24px modals, fully pill buttons — always paired with the outline.
- **Backgrounds:** the game world itself (3D voxel/low-poly biome renders) is the "background image" behind all HUD chrome — never a flat color behind gameplay. HUD panels float on top, opaque, never blurred/glassy.
- **Animation:** not visible in static screenshots, but the genre convention (and safe default) is snappy scale/translate feedback — buttons press down ~2px on click, no easing bounce, no fades. Keep transitions fast (~120-200ms).
- **Hover/press states:** press = translate down 2px (shadow "compresses"); no visible hover state distinct from idle in a touch/console-first game — treat hover as the press-preview on desktop.
- **Borders:** every surface has a 3-5px solid dark border (`--outline`), always solid, never dashed.
- **Shadows — TWO TIERS, and they do different jobs (amended 2026-08-16, ROADMAP 18.5).** The rule used to read "hard-edged offset shadows only, never blurred", and that is right about the *sticker* and wrong as a blanket ban, in the same way the transparency rule was (see `guidelines/ui-research-2026.md`, contradiction #2).
  - **The lip** — `0 6px 0` in the shell's own darkened fill, drawn by `applyShell`/`styleCard` as a `ShadowBody`. It is what makes a surface look *thick*, it is part of the cutout, and it never blurs. **Dropped on round shells**: a stadium shifted down pokes its flanks out at both ends, which is what put dark crescents on every capsule in the game (17.8).
  - **The cast shadow** — one soft nine-sliced sprite (`UITheme.DropShadow`, `tools/make_shadow.py`), tinted `Color.Shadow` at 0.62, sized to the shell plus 24 px and dropped 6. It is what makes a surface look *raised off the world*, which a thick sticker on a bright 3D map does not do on its own. Also skipped on round shells, and on the server.
  A Frame cannot be soft — alpha falling off over a distance is the whole of what a cast shadow is, and `UICorner` + `BackgroundTransparency` express exactly one hard edge. Both previous attempts at a Frame-based cast shadow were removed on play-test feedback for the same geometric reason.
- **Transparency/blur:** essentially none — panels are fully opaque so they read clearly over busy 3D game backgrounds.
- **Imagery color vibe:** the 3D world renders are warm and saturated (sandy desert tan, forest green, neon-lit cave blues/purples) — bright and toyetic, not photoreal, no grain/filmic treatment.
- **Cards:** flat cream fill, thick dark outline, hard drop shadow, no inner shadow, no left-border accent stripe.
- **Layering (hard rule):** every surface stacks `Shadow(-1) < Shell(0) < Body(+1) < Gloss(+2) < Content(+4) < Badge(+6) < Overlay(+8)` — corrected 2026-08-16 to the `Z` table `UITheme` actually defines; the old five-rung version in this line predated the `InnerBody` split and has been wrong since. And the gloss sheen never drops below 72% transparent. Text and icons always render *above* the sheen. An opaque sheen painted over labels is what made the original HUD unreadable across ~30 components at once — see the "Layering & the gloss rule" specimen card. Don't hand-roll a sheen; build surfaces through the theme layer that owns this contract.

## Iconography
- **Primary system: emoji.** Every icon across both reference sets is a native emoji (🗺️ 🐾 ♻️ 🎁 🧪 🛒 🛍️ ⏰ 🧬 💎 🏆 🔒), not an SVG/icon-font. This is the real system in production — keep using emoji for new UI in this style, don't substitute a stroke icon set.
- Reward/pet/pack art (Bobritto Pack, Chimpanzini Bananini, potion bottles) are bespoke illustrated icons in the source game — not reproduced here; use `image-slot`-style placeholders for that bespoke art in new designs and flag it as needing the real exported PNGs.
- No icon font or SVG sprite was found or provided — nothing was copied into `assets/icons/`.

## Fonts
**Fredoka One** — resolved, no longer a guess. The in-engine `UITheme` module probes
`Enum.Font.FredokaOne` at runtime and uses it for all display text (falling back to `GothamBlack`
on Studio builds that lack it); body text is `GothamBold`. `tokens/typography.css` now loads
Fredoka One from Google Fonts, keeping the earlier Baloo 2 placeholder only as the next fallback.

One caveat: Fredoka One ships a single weight (400). The weight tokens (`--weight-bold`,
`--weight-black`) therefore synthesize rather than load a real cut — which matches the engine,
where the chunky look comes from the `UIStroke` outline, not from a heavier weight.

## Index
- `styles.css` — root stylesheet, imports everything below.
- `tokens/` — `colors.css`, `typography.css`, `spacing.css`, `effects.css`.
- `guidelines/` — 9 foundation specimen cards (Colors, Type, Spacing groups) shown in the Design System tab.
- `src/` — recovered Luau mirror of the game itself (see `src/SYNC.md`, `src/APPLY.md`); the source of truth for the `--engine-*` tokens and the layering rule.
- `components/core/` — `Button`, `StatCard`, `CurrencyPill`, `IconBadge` (+ card `core.card.html`).
- `components/feedback/` — `Modal`, `ProgressBar`, `DamageText`, `RewardTile`, `Tag` (+ card `feedback.card.html`).
- `components/navigation/` — `NavRail`, `ZoneRow` (+ card `navigation.card.html`).
- `ui_kits/evolution-lab/` — interactive HUD recreation (`index.html` + screen components).
- `assets/reference/` — the 15 source screenshots this system was built from.
- `thumbnail.html` — project tile.
- `SKILL.md` — portable skill file for Claude Code.

## Caveats / help wanted
- ~~The GitHub repo had no readable content at import time~~ — **partly resolved.** The game's
  Luau source is now mirrored in `src/` (recovered from a Studio session; see `src/SYNC.md`), so
  colors, font and the layering rules below come from real code rather than from screenshots. The
  mirror is partial — `ZoneService`, `PetService`, `PlayerDataService` and `DNAService` are still
  only in the place file.
- ~~Font is a Google Fonts substitute~~ — **resolved**, see Fonts above.
- Color tokens: `tokens/colors.css` now carries an authoritative `--engine-*` block read straight
  out of `UITheme`, and the semantic aliases point at it. The older `--*-500` / `--*-600` scales
  are the original screenshot estimates and are kept for the existing component CSS — they do not
  match the shipping game exactly.
- No logo was provided — the brand mark is rendered as plain text ("Evolution Lab") everywhere a mark would go.
- Icons are emoji (matching the source), but bespoke illustrated art (pet/pack icons) is only placeholder-flagged, not recreated.

**Please iterate with me** — tell me which screens matter most, whether the comic-outline direction should fully replace the darker original HUD look (I leaned fully into the outline style since that's what you sent as "design examples"), and send the real repo/fonts/icons when you can so I can tighten this up.
