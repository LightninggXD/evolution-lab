# UI research 2026 — currency, motion, density, panels, legibility

Research pass for the Evolution Lab polish work, August 2026. Written to sit beside `readme.md`,
not to replace it: everything here is either **absent** from the readme or **contradicts** it, and
the two lists at the bottom say which.

## 0. How to read this

Every numbered claim carries a source URL. Evidence is tagged:

- **[DOC]** — Roblox Creator Hub / W3C. Authoritative.
- **[MOD]** — a shipping community module's published defaults. Strong: these are numbers people
  actually run, not opinions.
- **[FORUM]** — DevForum practitioner post. **Weak on its own.** Flagged wherever it is all there is.
- **[GAME]** — an observation about a named shipping game, sourced from its wiki. Medium: the wikis
  describe what is on screen, not why.
- **[INFER]** — my recommendation derived from the above. Not sourced. Marked so you can discount it.

Repo state quoted below was read off `src/` on 2026-08-16 (`MainUI.client.lua`, `UITheme.lua`).
No `.lua` file was edited.

---

## 1. The currency readout

### 1.1 The corner: bottom-left is right. Do not move it.

This was the surprise. The genre does **not** put soft currency top-right the way console games do.

- **Grow a Garden:** "A player can see how many Sheckles they have in the **bottom left corner** of
  the screen, or by looking at the leaderboard in the top right." **[GAME]**
  https://growagarden.fandom.com/wiki/Sheckles
  (Same wording carried into the sequel: https://growagarden2.fandom.com/wiki/Sheckles)
- **Pet Simulator 99:** "The currency of the world the player is currently in will show on the
  **left side** of the screen, just below their Diamonds." **[GAME]**
  https://pet-simulator.fandom.com/wiki/Currencies_(Pet_Simulator_99)
  — note this also establishes the *stacking* convention: a permanent premium currency on top, the
  contextual/zone currency beneath it. Our stack is DNA → 💎 → 🌟, same shape.

**Both fandom pages 402'd on direct fetch; the quotes above are from search-result excerpts of those
URLs, so treat the wording as accurate and the page as unverified-by-me.**

Why the corner is forced, mechanically:

- The **top** is Roblox's. `ScreenGui.ScreenInsets` defaults to `CoreUISafeInsets`, which "keeps all
  descendant GuiObjects inside the core UI safe area, clear of the top bar buttons and other screen
  cutouts", and that mode "is recommended if the ScreenGui contains interactive UI elements". **[DOC]**
  https://create.roblox.com/docs/ui/on-screen-containers
- Roblox has since moved the **health bar to the right-hand end of the topbar**, and stated it does
  not want developer UI squeezed in there: "We did not want to squeeze UI between the new experience
  controls and the healthbar, now that the healthbar will continue to be placed on the right-side."
  `GuiService.TopbarInset` does **not** account for the health bar. **[DOC/staff reply]**
  https://devforum.roblox.com/t/robloxs-new-experience-controls-health-bar-does-not-update-guiservicetopbarinset/3170836

  → Our right-hand tile cluster is anchored to the **bottom** right (`RIGHT_BOTTOM_Y = 46`), not the
  top. That decision is validated by this; leave it.

### 1.2 The one thing bottom-left costs you: the thumbstick

Roblox's own docs: "On mobile devices, the default controls occupy a portion of the bottom-left and
bottom-right corners of the screen. When you design a game's UI, avoid placing important info or
virtual buttons in these zones." **[DOC]**
https://create.roblox.com/docs/ui/position-and-size

Concrete sizes of those controls, from a community tutorial that read them out of the PlayerModule:

- jump button / thumbstick: **70 px** on a small screen, **120 px** on a large one
- the switch happens "when any of the screen dimensions reach over **500 pixels**"
- `ControlsSheetV2` buttons are "**144 pixels** long and wide" **[FORUM]**
  https://devforum.roblox.com/t/the-correct-way-to-design-mobile-buttons/2494558

The docs' prescribed fix is **relative** placement, not a magic number: position custom buttons off
the live jump button, e.g. `UDim2.fromOffset(-20, jumpButton.Size.Y.Offset)` to sit 20 px to its
left. **[DOC]** https://create.roblox.com/docs/ui/position-and-size

**Our current numbers:** `CurrencyStack` is `250 × 140` at `Position (0, 20), (1, -22)` with
`AnchorPoint (0,1)` — so it occupies the bottom **162 px** of the left edge. On a phone the
thumbstick is 70–120 px tall in that exact corner. **The bottom pill is inside the thumbstick.**
The `event chip row` (24 px tall, 5 px off the bottom edge) is worse.

### 1.3 Anatomy of the capsule

There is no published spec for this; the numbers below are **[INFER]** anchored to things that are
sourced.

| Part | Value | Anchor |
| --- | --- | --- |
| Shape | `UICorner` at `UDim.new(1, 0)` — a true capsule | already `UITheme.Radius.Pill`; `UITheme.Pill` takes the round path in `applyShell` when given this, so no corner crescents |
| Height | keep 46 / 40 / 40 | already above the 44 px AAA touch floor for the top one (§3.1); the lower two are display-only so 40 is fine |
| Outline | 3–4 px, `LineJoinMode` default `Round` | `readme.md` 3–5 px; `UIStroke.LineJoinMode` "Defaults to Round" **[DOC]** https://create.roblox.com/docs/reference/engine/classes/UIStroke |
| Icon vs text | icon box ≈ pill height − 2×padding; value text `maxTextSize` ≈ 0.72 × pill height | our DNA pill is 46 tall at `maxTextSize = 34` → 0.74. Already right. Keep the ratio when you change the height. |
| Internal gap | 6 px | `UITheme.Pill` already sets `layout.Padding = UDim.new(0, 6)` |
| Stack gap | 2 px → **8 px** | 2 px is off the readme's 4/8/12/16/20/24/32/40 scale entirely (`readme.md` "Spacing") |

**Performance ceiling worth knowing before you add strokes everywhere:** Roblox's own guidance in
the UIStroke release notes is "less than **300** total UIStrokes on screen". **[DOC]**
https://devforum.roblox.com/t/studio-beta-uistroke-improvements-scaling-offsets-and-more/3958036

### 1.4 The "+" affordance

Genre-standard, but I could not find a hard citation for it — the closest is the Game UI Database's
"Currency Store (IAP)" collection, which is a screenshot corpus rather than a stated rule. **[weak]**
https://www.gameuidatabase.com/index.php?scrn=122

We already ship one: the code comment at `MainUI.client.lua:4641` says the diamond "is drawn
permanently on the HUD's own capsule, bottom-left, with a `+` that opens the shop", and
`MainUI.client.lua:5432` routes a currency `+` to the Packs tab. **[INFER]** Put a `+` on every
currency the Robux shop actually sells and on none that it doesn't — a `+` that opens a panel with
nothing for that currency is worse than no `+`.

### 1.5 Does the number animate? Both, and here are the real defaults

`NumberSpinnerV2` (published 20 July 2026, the current community standard for this) ships these
defaults **[MOD]**:
https://devforum.roblox.com/t/numberspinnerv2-a-modern-animated-number-and-text-spinner-module/4748302

```
Duration              = 0.5    -- the count-up / reel spin
SlotResizeDuration    = 0.08   -- when the number gets a digit wider
BounceDuration        = 0.12   -- the pulse on change
BounceReturnDuration  = 0.14
BounceScale           = 1.08
EasingStyle           = Enum.EasingStyle.Quad
EasingDirection       = Enum.EasingDirection.Out
BounceEasingStyle     = Enum.EasingStyle.Quad
BounceEasingDirection = Enum.EasingDirection.Out
```

So: **count-up *and* pulse, not either/or**, count-up 0.5 s, pulse 1.08× over 0.12 s out / 0.14 s
back, all Quad/Out. Note the width animation is a separate, much shorter 0.08 s — that is what stops
the pill visibly jerking when `9` becomes `10`.

**[INFER]** Two guards for a clicker economy: (a) cap the count-up at 0.5 s total regardless of
delta, and re-target a running spin rather than queueing a second one, or fast DNA income will run
the readout permanently behind the truth; (b) fire the 1.08 pulse on *every* change but the count-up
only when the delta is ≥ ~2 % of the current value — otherwise a 60-clicks/minute drip makes the
number vibrate forever.

The detection hook is `GetPropertyChangedSignal` rather than `.Changed`, because the former "only
detects the Property given" while the latter "detects any property change which is not necessary".
**[FORUM]** https://devforum.roblox.com/t/what-is-the-best-way-to-make-currency-change-ui/653454

---

## 2. Motion

### 2.1 The engine defaults you are overriding

`TweenInfo.new(time?, easingStyle?, easingDirection?, repeatCount?, reverses?, delayTime?)` **[DOC]**
https://create.roblox.com/docs/reference/engine/datatypes/TweenInfo

| Param | Default | Docs wording |
| --- | --- | --- |
| `time` | `1` | "Duration for the tween, in seconds." |
| `easingStyle` | `Enum.EasingStyle.Quad` | |
| `easingDirection` | `Enum.EasingDirection.Out` | |
| `repeatCount` | `0` | "`-1` repeats indefinitely." |
| `reverses` | `false` | "Whether the tween should reverse to the starting values once it reaches its targets." |
| `delayTime` | `0` | "Time of delay until the tween begins, in seconds." |

Easing descriptions, verbatim **[DOC]**
https://create.roblox.com/docs/reference/engine/enums/EasingStyle

- `Back` (2): "Slightly overshoots the target, then backs into place."
- `Bounce` (6): "Bounces backwards multiple times after reaching the target, before eventually settling."
- `Elastic` (7): "Moves as if attached to a rubber band, overshooting the target several times."
- `Quad` (3): "Similar to `Sine` but with a slightly sharper curve based on quadratic interpolation."

**Back's overshoot amount is not a parameter.** There is no property to tune it. If 0.22 s of Back
overshoots too far for a small panel, the only lever is a two-stage tween (scale → 1.04 → 1.00),
not a softer Back. **[INFER, from the absence of any such field in the TweenInfo signature]**

### 2.2 Panel open/close — and the readme's "no bounce" rule is wrong as written

**Roblox's own official use-case tutorial** animates a settings menu open with:

```lua
transition = TweenInfo.new(0.5, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)  -- open
transition = TweenInfo.new(0)                                                        -- closed
Position: open UDim2.fromScale(0.5, 0.5), closed UDim2.fromScale(0.5, 0.4)
```

and rotates the gear button 0 → 45° with `TweenInfo.new(0.5, Enum.EasingStyle.Exponential,
Enum.EasingDirection.Out)`. **[DOC]**
https://create.roblox.com/docs/tutorials/use-case-tutorials/ui/interactive-ui

So the platform holder ships overshoot easing in its teaching material. The genre uses it too;
`Back, Out` on a `UIScale` is the common recipe, e.g. `TweenInfo.new(1, Enum.EasingStyle.Back,
Enum.EasingDirection.Out, 0, false, 0)` driving `{Scale = 1}`. **[FORUM]**
https://devforum.roblox.com/t/stopping-a-tween/2709800

**Recommendation, and why:** keep what `MainUI` already does — `TweenInfo.new(0.22,
Enum.EasingStyle.Back, Enum.EasingDirection.Out)` open, `TweenInfo.new(0.12,
Enum.EasingStyle.Quad, Enum.EasingDirection.In)` close (`MainUI.client.lua:995-996`). That is the
right answer and the readme is the thing that's wrong. Reasons: `Back` overshoots **once**;
`Bounce` settles over several visible hops and Roblox's own sample needs 0.5 s to do it, which is
far too long for a panel a player opens fifty times a session. `Elastic` is worse still. Amend the
rule to **"one overshoot (`Back`), never `Bounce` or `Elastic`"** rather than "no bounce".

**Scale from 0.8, not from 0.** **[INFER]** In this style the outline is the silhouette; a panel
scaling up from 0 renders a 5 px stroke as a solid blob for the first three frames. `MainUI`
already multiplies the published `FitScale` attribute rather than tweening to a literal 1.0
(`MainUI.client.lua` ~985-1010) — that is correct and must not be "simplified" away, because a
968-wide Journal on a phone is fitted well under half size.

### 2.3 Button press

Reportedly the biggest single differentiator, and the *worst-sourced* part of this research: I found
no numeric teardown of Pet Simulator 99's button feel, only tutorials claiming to reproduce it.
Community-reported values are hover scale **1.1** at `TweenInfo.new(0.3, Enum.EasingStyle.Back,
Enum.EasingDirection.Out)`, sometimes `TweenInfo.new(0.15, Enum.EasingStyle.Sine, ...)`. **[FORUM,
weak — treat as folklore]**
https://devforum.roblox.com/t/need-help-tweening-ui-button/4090826

**[INFER]** For a hard-drop-shadow style, scale is the wrong channel and translate is the right one,
because the readable event is the shadow *compressing*. Concretely:

- press: 0.06 s `Quad/Out` — button `Position.Y += 2`, shadow height `-= 2`
- release: 0.12 s `Back/Out` — both back
- the readme's "~120-200 ms" is right for the release and too slow for the press; a press that takes
  120 ms to bottom out feels like lag on touch.

### 2.4 Reward / claim celebration

The genre answer is a UI particle burst. `UIEmitter` (v2-ab, 6 June 2025) is the current module;
its API is `UIEmitter:Emit(Amount_of_particles, {properties}, Parent)`, properties include
`LifeTime {Min,Max}`, `Velocity {{MinX,MaxX},{MinY,MaxY}}`, `Size` (example `{8, 24}`),
`Rotation`, `RotationSpeed`, `Drag`, `Gravity`, `ZIndex`; the author's own test emits **50**
particles per burst. **[MOD]**
https://devforum.roblox.com/t/uiemitter-module-ui-particles-confetti/2913477

A separate "Confetti Effect" module defaults to **250** particles per call. **[MOD]**
https://devforum.roblox.com/t/confetti-effect/3592913

**[INFER]** 40–60 for a daily-reward claim; 200+ only for a rebirth or a new-skin reveal. Anything
in between trains players to ignore the big one.

### 2.5 Idle attention-getters — the frequency knob is `delayTime`

Mechanism, entirely from the TweenInfo signature **[DOC]**: an infinite reversing pulse is
`TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1, true, delayTime)` —
`repeatCount = -1` "repeats indefinitely", `reverses = true` returns it to the start value, and
`delayTime` is the gap. **You do not need a `RunService` loop for this**, and using one is the
common mistake. https://create.roblox.com/docs/reference/engine/datatypes/TweenInfo

**[INFER]** for the numbers: `delayTime` 2.5–4 s, peak scale ≤ 1.06 (below the 1.08 the currency
readout uses for a *real* event, so an idle nudge never outranks a real one), and **at most one
pulsing tile on screen at a time**. Pulse only tiles carrying unclaimed state; kill the tween the
moment the state clears, don't just hide the badge.

### 2.6 The motion kill-switch you are currently ignoring

`GuiService.ReducedMotionEnabled` is a player accessibility setting. Roblox's own remedy is
literally to "set the `TweenInfo.Time` parameter of a `TweenInfo` to `0`". Sibling properties:
`GuiService.PreferredTransparency` and `GuiService.PreferredTextSize`. **[DOC]**
https://create.roblox.com/docs/production/publishing/accessibility

**[INFER]** One helper in `UITheme` that returns `TweenInfo.new(reduced and 0 or t, ...)` and every
tween in `MainUI` is covered at once.

---

## 3. HUD density and safe areas

### 3.1 Minimum touch target — three floors, use the highest

| Standard | Size | Level |
| --- | --- | --- |
| WCAG 2.2 SC 2.5.8 "Target Size (Minimum)" — "The size of the target for pointer inputs is at least **24 by 24 CSS pixels**" | 24 px | AA **[DOC]** https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html |
| WCAG 2.1 SC 2.5.5 "Target Size" — "at least **44 by 44 CSS pixels**" | 44 px | AAA **[DOC]** https://www.w3.org/WAI/WCAG21/Understanding/target-size.html |
| Roblox's *own* default jump button | **70 px** small screen / **120 px** large | de facto **[FORUM]** https://devforum.roblox.com/t/the-correct-way-to-design-mobile-buttons/2494558 |

**Verdict on our build:** 82 px HUD tiles are correct — above 44, above the platform's own 70 px
small-screen control, below its 120 px large-screen one. The 44 × 44 panel close button
(`panelClose`, `MainUI.client.lua:1314`) sits *exactly* on the AAA floor; it must not shrink. The
**24 px event chip row is below the AAA floor and only just over the AA one** — fine as a display
strip, not fine if any chip is tappable.

### 3.2 Top clearance — the number changed and a lot of code didn't

The docs give a worked mobile example. On that device **[DOC]**
https://create.roblox.com/docs/reference/engine/classes/GuiService

```
GetInsetArea(Enum.ScreenInsets.None)             -> -59, -58, 792, 334
GetInsetArea(Enum.ScreenInsets.DeviceSafeInsets) ->   0, -58, 733, 313
GetInsetArea(Enum.ScreenInsets.CoreUISafeInsets) ->   0,   0, 733, 313
GetInsetArea(Enum.ScreenInsets.TopbarSafeInsets) -> 164, -58, 733,   0
```

Read out: the topbar is **58 px** tall, the device notch eats **59 px** at each side, and
`TopbarSafeInsets` starting at **x = 164** means Roblox's own left-hand controls occupy the first
164 px of the bar. The legacy value everyone hardcoded was **36**; the new inset is **58**. **[FORUM,
corroborated by the doc numbers above]**
https://devforum.roblox.com/t/what-are-the-new-topbar-inset-dimensions/3237388

**Trap:** `GuiService:GetGuiInset()` returns `0,0,0,0` on the first frame with the new topbar.
Never cache it at startup. **[FORUM/Engine Bugs]**
https://devforum.roblox.com/t/guiservicegetguiinset-returns-0-0-0-0-for-the-first-frame-of-the-game-with-new-topbar-ui/2973508

The four `ScreenInsets` modes, verbatim **[DOC]** https://create.roblox.com/docs/ui/on-screen-containers:
`CoreUISafeInsets` (default, recommended for interactive UI), `DeviceSafeInsets` (notch only, no
topbar allowance), `TopbarSafeInsets` ("between the top bar controls and the right edge of the
device safe area"), `None` ("may result in UI that is obscured or completely hidden by device
notches and cutouts").

**Our `TILE_START_Y = 100` is a hardcoded guess at this.** It is fine under `CoreUISafeInsets`
(where the origin is already below the bar) and wrong under anything else.

### 3.3 Bottom clearance

Covered in §1.2. Reserve `jumpButtonSize + 20` at the bottom on touch, read off the live control,
not off a constant.

### 3.4 How many buttons is too many, and how to group

**There is no published number.** Roblox's own UI/UX page argues for contextual minimalism rather
than a cap: it praises *Super Striker League* for swapping the button set by game state (no ball →
"Sprint"/"Tackle"; with ball → "Deke"/"Pass"), and warns against showing players "clutter of
everything that they don't" need. **[DOC]**
https://create.roblox.com/docs/production/game-design/ui-ux-design

The grouping convention that *is* stated: "group UI elements from the same category together", with
a worked example placing objective info at the top, the focal readout centre, and player state at
the sides; and "Place interactive elements in easy-to-reach zones near the natural resting position
for thumbs." **[DOC]**
https://create.roblox.com/docs/tutorials/curriculums/user-interface-design/wireframe-your-layouts

**[INFER]** Our 12 always-on tiles (4 left + 8 right) plus the evolve widget plus the chip row is
above what any sourced guidance endorses, but nothing I found lets me name a number. The defensible
move is not "delete tiles" — it is to make the 8-tile right cluster state-driven so tiles with
nothing to claim collapse out, which is exactly the Super Striker pattern the docs endorse.

### 3.5 Stop measuring the viewport in pixels

`GuiService.ViewportDisplaySize` returns a `DisplaySize` enum, and **Roblox publishes no pixel
thresholds for it** — deliberately, because "attempting to predict screen size by pixels often leads
to misinterpretation". **[DOC]**
https://create.roblox.com/docs/reference/engine/enums/DisplaySize

```
Small  (0) -- "Applies to most tablet/mobile/handheld devices."
Medium (1) -- "Applies to most laptops and monitors."
Large  (2) -- "Applies to most TVs or larger."
```

The matching Style Editor query selectors are `@ViewportDisplaySizeSmall` / `Medium` / `Large`, plus
`@PreferredInputTouch`, which "allows your UI to automatically swap tokens for text sizes, container
dimensions, and other measurements". **[DOC]**
https://create.roblox.com/docs/projects/cross-platform · https://create.roblox.com/docs/ui/styling/editor

**Our `MainUI` reflow reads `cam.ViewportSize.Y` directly** (`MainUI.client.lua:9574`). That is the
pixel-prediction the docs warn about. Also relevant: consoles are viewed from "**8–10 feet** away".
**[DOC]** https://create.roblox.com/docs/production/publishing/console-guidelines

---

## 4. Panel / modal anatomy

Honest warning: **this is the thinnest section.** The DevForum's Art Design Support threads on
exactly these games (`grow-a-garden-ui-example/3764006`, `grow-a-garden-dialog-ui/3736124`,
`feedback-on-my-pet-simulator-99-inspired-ui/3814728`) contain **no numbers at all** — I read all
three and they discuss ImageLabel tiling and BillboardGui offsets, not design specs. Anything below
without a URL is inference.

### 4.1 Close button

Convention is a coloured X badge in the **top-right of the panel**, overhanging or flush. No source
states this; it is what our own build already does — `panelClose` builds a red 44 × 44 circle at
`Position (1, -12), (0, 8)`, `AnchorPoint (1, 0)`, `ZIndex = panel.ZIndex + Z.Badge + 2`
(`MainUI.client.lua:1314`). It meets §3.1's AAA floor. **Keep it; nothing found argues against it.**

### 4.2 Header band vs floating title

No source. Our `UITheme.PanelHeader` band (top 14, height 68, gap 12 → content starts at y = 94) is
already the more legible of the two options over a bright world, because the band gives the title
its own opaque ground rather than relying on a text stroke (§5.3).

### 4.3 Scroll affordance — the one hard, actionable finding here

**`UIGradient` does not work on a `ScrollingFrame`.** Straight from the current class docs: "You can
apply gradients to `Frame`, `TextLabel`, `TextButton`, `ImageLabel`, `ImageButton`, and
`ViewportFrame`. However, **`ScrollingFrame` and `TextBox` are not currently supported**." **[DOC]**
https://create.roblox.com/docs/reference/engine/classes/UIGradient

So the standard "fade the bottom edge so the player knows there is more" **cannot** be done by
parenting a `UIGradient` to the scroller. It has to be a **sibling** `Frame`/`ImageLabel` pinned to
the bottom of the scroller's *parent*, carrying its own `UIGradient` with a `Transparency`
`NumberSequence` — and note "the envelope values of the NumberSequenceKeypoints are ignored". **[DOC]**

Relevant `ScrollingFrame` defaults **[DOC]**
https://create.roblox.com/docs/reference/engine/classes/ScrollingFrame

- `ElasticBehavior` "Defaults to `WhenScrollable`" — the rubber-band at the end of travel is *itself*
  a free affordance and is on by default. Do not switch it off.
- `VerticalScrollBarInset` and `HorizontalScrollBarInset` "Default to `ScrollBarInset.None`" —
  meaning **the scrollbar is drawn on top of your content**. Set `VerticalScrollBarInset = Always`
  on any list whose right-hand column has anything in it.
- `VerticalScrollBarPosition` "Defaults to `VerticalScrollBarPosition.Right`".

The only practitioner advice I could find on making a scroller *legible as* a scroller is "make the
scrollbar bigger" — one reply, one thread. **[FORUM, very weak]**
https://devforum.roblox.com/t/how-to-make-it-easier-for-players-to-recognize-a-scrolling-frame/2565331
The thread is worth reading anyway for the framing: the OP reports that *almost all* of their
playtesters did not realise the menu scrolled.

**Our build:** 22 `ScrollingFrame`s in `MainUI`, 14 of them at `ScrollBarThickness = 6`, one at 12,
two at 8, and one runtime bump to 10. **[INFER]** Standardise: 8 on pointer, 12 on touch (the
`@PreferredInputTouch` style query from §3.5 exists for exactly this), plus the sibling fade
overlay. A 6 px bar over a cream panel is close to invisible.

### 4.4 Tabs and empty states

No source found for either in the Roblox/genre literature. Not going to invent numbers for them.

---

## 5. Readability over a bright 3D world

### 5.1 The genre's real answer: dim the WORLD, not the panel

This resolves the apparent conflict with `readme.md`'s "Transparency/blur: essentially none".

The widely-copied Roblox pattern for opening a full-screen menu is a **Lighting** effect, not a GUI
effect: tween a `BlurEffect` to `Size = 20` and a `ColorCorrectionEffect` to `Saturation = -1` over
`TweenInfo.new(0.5)`. **[FORUM, but the values are consistent across the copies of this script]**
https://devforum.roblox.com/t/localscript-blur-background-inside-esc-menu/2486466

That is blur on the **camera**, applied to the 3D render, with the panel still fully opaque above
it. The readme's rule is about *GUI surfaces* and stays intact. The two are not the same mechanism
and should stop being described by one rule.

**[INFER]** For our bright, saturated map, `Saturation = -0.6` and `Blur.Size = 14` is enough —
`-1` is greyscale and reads as "the game paused" rather than "a panel is open". Tween in over
0.18 s to match the panel's 0.22 s open, not 0.5 s.

### 5.2 The flat scrim, and the property that must scale it

A full-screen black `Frame` under the panel, `BackgroundTransparency` tweened 1 → ~0.45, is standard
practice — I found **no** Roblox source giving a number for it, so 0.45 is **[INFER]**.

What *is* sourced: `GuiService.PreferredTransparency` — "A value of `1` indicates the player prefers
the default background transparency, while a value of `0` indicates the player prefers fully
opaque." **[DOC]** https://create.roblox.com/docs/production/publishing/accessibility

**[INFER]** So the scrim's alpha should be `1 - (0.55 * GuiService.PreferredTransparency)`: a player
who has asked for opaque backgrounds gets a solid scrim, everyone else gets 0.45. This is three
lines and it is the only accessibility setting our HUD would be actively fighting.

### 5.3 Outline, not fill, is what separates a panel from the world

Our panels are luminance 0.89 over a saturated map — the near-white fill has almost no separation
from a sunlit sand or ice zone. The separation comes from the stroke.

- **New since 4 Dec 2025:** `UIStroke.StrokeSizingMode`. `FixedSize` (default) keeps pixel
  thickness; **`ScaledSize` makes "Thickness property act as a percentage of the parent GuiObject's
  shortest axis"**, suggested range 0 to 1. Also new: `BorderStrokePosition` (`Outer` default /
  `Center` / `Inner`) and `BorderOffset` (a `UDim`). **[DOC]**
  https://devforum.roblox.com/t/studio-beta-uistroke-improvements-scaling-offsets-and-more/3958036

  This is the fix for panels that are `UIScale`-fitted to 0.35 on a phone (§2.2): at `FixedSize` a
  5 px outline stays 5 px and swamps a shrunk panel; at `ScaledSize` it shrinks with it.

- **`BorderOffset` cannot give you a hard drop shadow.** The same announcement notes custom
  positioning is only supported for border strokes and does not produce an offset shadow. Keep the
  duplicate offset frame (`--shadow-panel: 0 4px 0 var(--outline)` in `tokens/effects.css`). Worth
  writing down so nobody spends an afternoon on it.

- **`LineJoinMode` trap:** "When using UIStroke with LineJoinMode set to Bevel or Miter with
  UICorner, the UICorner will override the LineJoinMode." **[DOC]**, same URL. Our corners are all
  `UICorner`, so `LineJoinMode` is inert on every panel — don't bother setting it.

- Keep the total under **300** UIStrokes on screen (§1.3), same source.

### 5.4 Text over the world

Where text has no opaque ground under it — floating damage numbers, the currency values today, zone
billboards — the only practitioner advice found is the obvious one: "making it bigger and/or adding
a black outline around it". **[FORUM, weak]**
https://devforum.roblox.com/t/feedback-on-hud-ui/3090275

`UIStroke.ApplyStrokeMode` has two modes: `Contextual` applies "the stroke to the object's border
instead of the text itself" where a border applies, and `Border`. **[DOC]**
https://create.roblox.com/docs/reference/engine/classes/UIStroke — be explicit about which you
want on a `TextLabel` that also has a `BackgroundTransparency` of 0; `Contextual` will not stroke
the glyphs there.

**[INFER]** The structural fix is §1.3: put the currency values on an opaque capsule and the
question of stroking loose text over a bright world stops being asked at all.

---

# Changes this implies for Evolution Lab

Ranked by visual impact per unit of work. This is a polish pass, so everything here is an edit to
something that already exists.

1. **Give the three currency pills a `shellColor`.** `UITheme.Pill` already builds the full capsule
   — shell, `Radius.Pill`, `applyShell` round path, gloss — the moment `opts.shellColor` is
   non-nil, and the currency stack is the one caller that omits it (`MainUI.client.lua:589-600`).
   Three arguments. This is the single largest look change in the document per line edited. §1.3
2. **Count-up + 1.08 bounce on currency change**, at NumberSpinnerV2's shipped numbers: 0.5 s Quad/Out
   spin, 0.12 s out / 0.14 s back bounce, 0.08 s width change. Re-target a running spin instead of
   queueing. §1.5
3. **Lift the currency stack and the event chip row off the mobile thumbstick.** Currently the stack
   occupies the bottom 162 px of the left edge and the chip row sits 5 px off the bottom; the
   thumbstick is 70–120 px in that exact corner. Position relative to the live jump button as the
   docs prescribe, not off a constant. §1.2, §3.3
4. **Dim the world when a panel opens** — `BlurEffect` + `ColorCorrection.Saturation`, tweened 0.18 s
   to match the existing 0.22 s panel open. Costs one shared function on the `closeAllPanels` /
   `toggleOnly` / `panelClose` chokepoints that `animatePanel` already uses. §5.1
5. **Bottom-fade overlay + fatter scrollbars on the 22 `ScrollingFrame`s.** The fade must be a
   *sibling* with a `UIGradient` — the gradient cannot go on the scroller itself. Bar 6 → 8/12, and
   `VerticalScrollBarInset = Always` on lists with content in the right column. This is the direct
   fix for "our last row is just cut off". §4.3
6. **`StrokeSizingMode = ScaledSize` on panel shells.** One property; makes the outline survive the
   `FitScale` shrink on phones instead of swamping the panel. Requires the Dec 2025 engine. §5.3
7. **Honour the three accessibility properties** — `ReducedMotionEnabled` (`TweenInfo.Time = 0`),
   `PreferredTransparency` (scale the scrim), `PreferredTextSize`. One helper in `UITheme` covers
   every tween in `MainUI`. §2.6, §5.2
8. **Idle pulse on unclaimed tiles**, driven by `repeatCount = -1, reverses = true` and a
   `delayTime` of 2.5–4 s — never a `RunService` loop, never more than one at a time, peak ≤ 1.06 so
   it stays quieter than a real currency change. §2.5
9. **Press timing split**: 0.06 s down, 0.12 s back. The readme's single "~120-200 ms" makes the
   press half of it feel laggy on touch. §2.3
10. **Replace `cam.ViewportSize.Y` reflow tests with `ViewportDisplaySize`.** Roblox deliberately
    publishes no pixel thresholds for it; a pixel test is the failure mode the docs name. Larger job
    than the rest — do it last, or only when the reflow next breaks. §3.5
11. **Make the 8-tile right cluster state-driven** so tiles with nothing to claim collapse out.
    Endorsed pattern, no sourced button-count cap — so this is a judgement call, not a rule. §3.4
12. **Event chip row: 24 px is under the 44 px AAA touch floor.** Fine if the chips are display-only;
    if any chip is tappable it needs 44. §3.1

---

# Where this research contradicts our own readme.md

1. **"no easing bounce" (readme, *Animation*) — wrong as written.** Roblox's own official tutorial
   opens a menu with `Enum.EasingStyle.Bounce, Out` over 0.5 s, and `Back, Out` on a `UIScale` is the
   genre's standard panel open. Our shipping code already uses `Back, Out` at 0.22 s and is right;
   the readme documents a rule the code doesn't follow. **Amend to: "one overshoot (`Back`), never
   `Bounce` or `Elastic`."** §2.2

2. **"Transparency/blur: essentially none" (readme, *Visual foundations*) — right rule, wrong
   scope.** It is correct for GUI surfaces and incorrect as a blanket ban: the genre dims the 3D
   world behind a modal with a Lighting `BlurEffect` + `ColorCorrection`, which is a camera effect,
   not a glassy panel. **Scope the rule to GuiObjects and add the world-dim as its own line.** §5.1

3. **"no fades" (readme, *Animation*) — contradicted by our own needs and by Roblox's accessibility
   docs**, which use a fade as the *reference* implementation of a motion-safe transition. A scrim
   has to fade; there is nothing else it can do. §2.6, §5.2

4. **"press = translate down 2px … ~120-200ms" — one number doing two jobs.** Down and up want
   different durations. §2.3

5. **`CurrencyPill` is listed as a core component (readme, *Components*) but the shipping HUD renders
   no pill** — `MainUI.client.lua:572` says so in a comment: "no panel, just big outlined numbers".
   Documentation/implementation drift, and it is the exact thing that started this work. §1.3

6. **Spacing scale drift.** The readme's scale is 4/8/12/16/20/24/32/40. The currency stack uses a
   2 px gap between pills and the event chip row sits 5 px off the bottom edge — neither is on the
   scale. §1.3

7. **"no visible hover state distinct from idle" (readme, *Hover/press states*) — genre practice
   disagrees**, using a ~1.1 hover scale on desktop. But the only evidence is DevForum folklore with
   no teardown behind it, so **I would keep the readme's rule** and note the disagreement rather than
   act on it. §2.3

8. **Not a contradiction, but wholly absent from the readme:** touch-target floors (24/44/70/120 px),
   `ScreenInsets` and the 36 → 58 px topbar change, the mobile thumbstick exclusion zone, the
   `UIGradient`-on-`ScrollingFrame` prohibition, the `< 300 UIStroke` budget, `StrokeSizingMode`
   (Dec 2025), and the three `GuiService` accessibility properties. All of these are platform facts
   a design system for a Roblox game should state. §3, §4.3, §5.3
