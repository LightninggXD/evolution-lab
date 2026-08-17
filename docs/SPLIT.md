# SPLIT — how this codebase is being taken apart, and the rules for doing it

Four files held two thirds of the game: `MainUI` (11,743 lines when this started), `ZoneBuilder`
(9,281), `GameConfig` (5,205) and `CreatureService` (3,869). Reading `MainUI` whole cost ~149k
tokens, which is most of a context window spent to change one label — and a file nobody can hold
in their head is a file where a change breaks something three thousand lines away.

This document is the contract for pulling them apart. It exists so the next session does not
re-derive it.

**Three of the four are done** (`MainUI`, `GameConfig`, `ZoneBuilder` — §5), and `CreatureService`
with `BossService` are what is left (§6). The largest file in the repo is now `BiomeDecor` at
2,519 lines; nothing is above Luau's register cliff any more.

---

## 0. Two registers, and neither is written by hand

| what | where | regenerate with |
|:--|:--|:--|
| where every function and section lives, per file | `docs/CODEMAP.md` + `docs/codemap/*.md` | `py tools/codemap.py` |
| which blocks of `MainUI` are still waiting to move | *(printed on demand)* | `py tools/splitplan.py --deps` |
| how close a file is to Luau's 200-register cliff | *(printed on demand)* | `py tools/luaregs.py <file>…` |

**`luaregs.py` is the one to run before AND after any cut to a server file.** It counts what the
compiler counts — declared *names* at column 0, so `local a, b, c` is three — which is not what
`splitplan.py` counts, and that difference is how `ZoneBuilder` sat two declarations from not
compiling while every scan reported it comfortable. It exits 1 if anything is at or over the cap.

**Read `docs/CODEMAP.md` before searching for code.** A per-file page is ~110 lines and gives
exact `Read(offset, limit)` coordinates for every function and every section heading. `MainUI`'s
page costs about two thousand tokens against the hundred and fifty thousand the file costs.

Re-run `py tools/codemap.py` after any structural edit. `--check` exits 1 when the register is
stale and touches nothing, which is what a hook or a pre-commit step should call.

---

## 1. The seam the register cap already cut for us — on the CLIENT

*(This section is about `MainUI`. The server files had no such seam, and §6 is the record of what
they needed instead: a contract measured over line ranges, and a shared vocabulary extracted before
any leaf could move.)*

`MainUI` sits on **Luau's 200-register ceiling** (see `evolution-lab-mainui-register-limit`), and
the standing rule for years has been that anything substantial goes inside
`;(function() ... end)()` so it gets a register file of its own.

Twenty-three blocks were written that way. **A closure that escapes nothing is already a module.**
So the split does not have to be designed — the constraint designed it, and `tools/splitplan.py`
reads the answer back out of the file. Each block's captured upvalues are its contract, and most
of them capture five or six names.

That is why extraction is a change of *wrapper*, not a rewrite:

```lua
;(function()                     -- becomes:   return function(hud)
    ...                          --                ...
end)()                           --            end
```

with the body moved **byte for byte**, indentation and comments included.

---

## 2. Where things go

```
ReplicatedStorage/Modules/
    UIKit.lua            the drawing kit: styleCard, styleButton, themeLabel, corner, stroke,
                         formatNumber, liftChildren, setButtonColor + the shell constants
    UITheme.lua          (unchanged) the design TOKENS — colours, radii, fonts, shared widgets
    HUD/
        TradePanel.lua   one panel, or one self-contained feature, per file
        ...
```

**UIKit vs UITheme, since both are "the UI module":** a *value* goes in `UITheme`, a *verb* goes
in `UIKit`. UITheme owns what colour a panel is; UIKit owns the act of painting an instance that
colour. UIKit requires UITheme; never the other way round.

A HUD module is a **function**, not a table:

```lua
return function(hud)
    ...
end
```

and MainUI calls it where the block used to be:

```lua
require(RS.Modules:WaitForChild("HUD"):WaitForChild("TradePanel"))(hudRefs)
```

Zero new top-level locals in MainUI — which matters, because the whole file is still one function
against those 200 registers.

### On the server, a module is a TABLE and the surface is the design

```
ServerScriptService/
    ZoneKit.lua       a KIT: shared vocabulary, no state (bar the placement frame)
    ScatterKit.lua    a KIT with state: the reservation table lives here, behind a verb
    BiomeDecor.lua    a LEAF: one job, one entry point
    ...
```

```lua
local ZoneKit = require(script.Parent.ZoneKit)   -- siblings, by name
...
return { newPart = newPart, setFrame = setFrame }
```

Three rules, each of which one of these cuts paid for:

1. **`Kit` means shared vocabulary, plain name means a leaf.** A kit is required by several files
   and exports many small names; a leaf is required by one and exports one or two. If a leaf grows
   a second caller, that is the signal it was a kit (`ZoneGate` is exactly that — the arena's way
   home is the same door as a zone boundary, so it could not stay inside `ZoneBuilder`).
2. **A kit holds a rule every part obeys; a per-zone decision stays with the builder.**
   `groundColorOf` (how bright ANY floor may be) is in `ZoneKit`; `GROUND_MATERIAL` (which of the
   twenty floors is Marble) is not, and `ZoneTerrain` takes it as an argument instead. Handing one
   value to one call site is not the `ZoneDecor` mistake — that was 29 helpers and a second list to
   keep in step.
3. **Anything reassigned is reached through an accessor, never exported as a value.** `setFrame` /
   `getFrame`, `setZoneKey`, `clearReservations`. A copy taken at require time is frozen forever,
   silently, and no lint in this repo can see it.

---

## 3. `hud` — the context table, and the two rules that make it work

`hud` **is** MainUI's existing `hudRefs`. It already carried handles *out* of the closures
(`hudRefs.refreshPetsPanel`); now it carries helpers *in* as well. Same table, no new register,
and a module can both read from it and publish to it.

### Rule 1 — it is filled at the point of definition, not in one block at the end

The first attempt put every `hudRefs.x = x` in one block above the first module call. That works
for a module called at line 10,000 and for nothing else: `showNotification` is not written until
line ~7,900, so a module extracted from above it would be handed **nil**.

So each assignment sits one line under the helper it exports:

```lua
local function panelClose(panel)
    ...
end
hudRefs.panelClose = panelClose
```

A module may use whatever is filled **above its own call site**, and nothing below — exactly the
rule the IIFE it replaces already lived by.

### Rule 2 — destructure only what is already filled; otherwise read at use time

```lua
return function(hud)
    local screenGui = hud.screenGui              -- fine: filled at line 78
    ...
    button.Activated:Connect(function()
        hud.showNotification("done")             -- read AT USE, if it is filled later
    end)
end
```

The table is shared by reference, so a field set afterwards is visible to a callback — but a local
copied at build time is frozen at `nil` forever, silently, with no error anywhere. This is the one
that will bite.

### What is on it today

| field | kind | filled at |
|:--|:--|:--|
| `getData()` | **getter** | top of file |
| `screenGui` | value | after the ScreenGui is made |
| `registerPanel` | function | after its definition |
| `closeAllPanels`, `toggleOnly` | function | ” |
| `panelClose` | function | ” |
| `flatText` | function | ” |
| `showNotification` | function | ” |
| `refreshPetsPanel`, `refreshCharacterPanel` | function | (pre-existing, outbound) |

**`getData` is a function where the rest are values**, and that asymmetry is load-bearing:
`currentData` is *rebound* (`currentData = data`) every time the server pushes a DataUpdate, about
every three seconds. A module that captured the value would hold whatever was there when the
client started — `nil` for the first seconds of a session, which is exactly when a new player is
looking at the screen. Anything else that becomes reassignable must join it as a getter.

---

## 4. The recipe

0. **Measure the candidate's CONTRACT before choosing it**, over a line range: what it *defines*,
   which of those names are read *outside* the range (its export surface), and which names declared
   outside are read *inside* (its imports). A client-side block's contract is its captured upvalues
   and `splitplan.py --deps` prints those; a server file has no closures, so the same question has
   to be asked over line numbers. **The imports are what decide the order** — that is the whole
   lesson of §6's first correction, and skipping this step is how a plan ends up cutting the
   biggest leaf first when the 253-line enabler had to go first.
1. `py tools/splitplan.py --deps` — pick a block; prefer a small captured set.
2. **Write the move as a Python script**, not by hand. Every comment in this codebase is
   load-bearing (GEMINI.md rule 10) and a hand-copy of 900 lines drops one. The script asserts its
   boundary lines before it slices, and refuses to run if the destination already exists. The nine
   that have run live in `tools/splits/` — `extract_trade.py` for a client block,
   `extract_scatterkit.py` for a server one.
   **Assert what must NOT be there afterwards, not just what was moved.** Every server cut here
   ends with a loop over the names that left, checking none is still spelled in the host: a
   survivor is a nil global, and a nil global in a builder is a silent hole in the world rather
   than an error. `extract_village.py` found one that way.
   **And assert what the moved text may not still reach for** — a name that stayed behind resolves
   to nil in the new file with the same silence.
3. Services and UIKit helpers are required by the module for itself; only true MainUI state goes
   through `hud`. On the server: re-localise (`local newPart = ZoneKit.newPart`) when the call
   sites number in the hundreds and nothing should change; spell out `VillageKit.addKnob(...)` when
   there are fifteen, because the qualified name tells the next reader where the thing lives.
   **Anything reassigned gets accessors, never a copy** — §3 rule 2 is the trap that has now cost
   this codebase four times (`ACTIVE_FRAME`, the village palette, `ACTIVE_ZONE_KEY`, and it is why
   `scatterBlocks` is exported as `clearReservations()` rather than as a table).
4. `py tools/luastruct.py`, `luanames.py`, **`luascope.py`**, `luaregs.py` on both files. `luascope`
   is the one
   that matters here: it is the only check that catches a name used where it is *not in scope*,
   which is precisely what a bad extraction produces, and Luau compiles those.
   `luanames` has a **baseline of 13 names across 11 files**, all false positives, listed in
   `src/SYNC.md`. They are not yours; check the count did not grow. A split moves those rows
   between files without changing the total — that already happened once and `src/SYNC.md` records
   which rows moved where.
5. `py tools/manifest_build.py && py tools/codemap.py`.
6. Push to Studio (Edit mode) and **create the instance first** — a new module is not just a file:

   ```lua
   local hud = Modules:FindFirstChild("HUD") or Instance.new("Folder")
   hud.Name, hud.Parent = "HUD", Modules
   local m = Instance.new("ModuleScript"); m.Name, m.Parent = "TradePanel", hud
   ```

   then `ScriptEditorService:UpdateSourceAsync` from `http://127.0.0.1:8731/…`
   (see `evolution-lab-studio-http-bridge`), then `loadstring` both files.
7. **Sweep all files, not the two you touched** — Studio drifts per file and a stale `UITheme`
   has made a fresh `MainUI` throw before. The manifest pass reports identical/different/missing
   for every mirrored script in one call.
8. **Play, and take a screen capture.** `luastruct` is not evidence about a picture (GEMINI.md
   rule 8). Count the children of `EvolutionLabUI` — it was **42** after the trading split — and
   look at the panel that moved. Then **stop Play** (rule 7).
   For a world cut this is a full rebuild in Edit plus a **census against numbers earlier rows
   already recorded** — §6 step 4 lists them and why each one is the thing a broken cut would
   break. Note that a fresh clone of the host does **not** give you a fresh clone of a kit it
   requires; destroy and re-parent the kit first or you are judging the old one.

---

## 5. Done

**`MainUI` 11,743 → 5,015 lines.** Every closure block is out; 22 modules under
`ReplicatedStorage/Modules/HUD/`, plus `Modules/UIKit` for the drawing kit.

```
UIKit 589        TradePanel 1012   JournalGrid 810     SeasonPass 947
PotionTimers 664 EggShop 434       PetFusion 412       GroupRewards 218
WelcomeBack 233  Quests 220        ProductTiles 201    AudioPanel 208
PassShop 190     PetsActions 207   PetRelease 164      WheelEntry 144
ScrollAffordance 123  InventoryTabs 116  RebirthRungs 115  Codes 115
TileColumnFit 108     RebirthBeacon 101  CurrencyPlus 47
```

**`ZoneBuilder` 9,281 → 2,472 lines + eight sibling modules.** Finished 2026-08-17; §6 below is the
plan it was made against and is kept for the measurements, not as a to-do list.

| module | lines | what it owns | names out → back |
|:--|--:|:--|:--|
| `ZoneKit` | 733 | the build vocabulary: `newPart` + the shadow/solidity rules it applies unasked, the placement frame, `groundColorOf`, `addPlankText`, `vivid`, `spinForever`, `pulseForever`, `lighten`, `darken`, the sign palette, the platform's dimensions | — |
| `ScatterKit` | 253 | where a prop may stand: the reservation table, `scatterPoint`, `scaled`, and the clearance geography (street, centre, both gate mouths, the boss's dais) | 16 → 6 |
| `VillageKit` | 608 | what a village is **made of**: the per-zone palette, the soft-prop vocabulary, the prop library | 22 → 1 |
| `ZoneGate` | 313 | the doorway between two zones, and the arena's way home | 9 → 3 |
| `ZoneTerrain` | 1,426 | the ground itself — the valley floor, the terraces, the cliffs, the pools; holds `buildValleySide`, ~1,270 lines, the largest function in the game | 4 → 1 |
| `BiomeDecor` | 2,519 | what a zone is **dressed in**: the four layers, the mesh prop layer, `buildBiomeBase`, and all twenty per-zone builders | 26 → 1 |
| `EggPlaza` | 1,012 | the three eggs a zone sells and the stall they stand on | 34 → 1 |
| `EventArena` | 645 | the Colosseum, which is not part of a zone | 4 → 1 |

**198 → 87 of Luau's 200 top-level registers**, measured with `tools/luaregs.py` (new, and the
first tool here that counts *names* rather than `local` *lines* — see §6, that distinction is the
whole reason the file was found to be two declarations from not compiling). No call site outside
the moved text changed; nothing was hand-copied; every cut is a script under `tools/splits/` that
asserts its boundaries before it slices and refuses to run twice.

**The order was not the one §6 planned, and the reason is worth keeping.** §6 listed the leaves
biggest-first. What actually had to happen first was `ScatterKit` — not a leaf at all, and only
200 lines — because `scatterPoint` is read 82 times inside the biome layer and `darken`/`lighten`
another 32, so *no* leaf could be cut until they lived somewhere both sides could require. Then the
four leaves §6 listed separately turned out to be **one**: measured, every layer verb had exactly
one caller, which had exactly one set of callers, which was read by exactly one line in `Build()`.
Cutting them apart would have meant inventing three surfaces nothing had asked for.

**`GameConfig` 5,205 → a 23-line loader + 16 parts** under `Modules/GameConfig/`: Evolution,
Upgrades, Zones, Pets, Rebirth, Rewards, Potions, Shops, Diamonds, Mastery, RobuxShop, Events,
Season, Helpers, Characters, Codes. No call site changed — it still returns one table.

Verified for both: `luastruct` and `luascope` clean on all 92 files, no module writes to a former
MainUI local, every file byte-identical to Studio, everything compiles, HUD photographed with the
same 42 children and no losses, every extracted panel populated (SeasonPanel 2,204 descendants,
CharacterPanel 2,730), Season Pass photographed open, and GameConfig compared field by field
against the pre-split version in a live Studio session — 266 fields both sides, nothing missing,
nothing extra, no type or length differences.

---

## 6. What is left, and why the next two are not the same job

These were **measured**, not guessed — the numbers below are from the same scan `splitplan.py`
does. Do not assume MainUI's recipe transfers; it does not, and here is the evidence.

### `ZoneBuilder` (9,281 lines) — DONE 2026-08-17; this section is the plan, kept for the numbers

**The result is in §5. Read the table there for what exists; read this for why.** The two places
the plan was wrong are recorded above the parts that were right, because both mistakes are the kind
another split will make:

- **the enabler was invisible to a leaf-shaped plan.** Step 2 below says "then the leaves, in this
  order", biggest first. No leaf could be cut at all until `ScatterKit` existed, and `ScatterKit`
  is not a leaf and is 253 lines. What made it necessary is a number this plan never took:
  `scatterPoint` is read **82 times inside the biome layer alone**, `darken` 17 and `lighten` 15.
  Before cutting anything, measure what the candidate *imports*, not just what it exports.
- **four of the leaves were one leaf.** Step 2 lists ground clutter, idols and ruins, the mesh prop
  layer and (via the egg plaza's line range) the twenty zone builders as separate cuts. Measured,
  every layer verb had exactly **one** caller (`buildBiomeBase`), which had exactly one set of
  callers (the twenty builders), which were read by exactly one line in `Build()`. Cutting them
  apart would have exported three surfaces nothing had asked for. `tools/splits/leafscan`-style
  contract scans — defines / escapes / imports over a line range — are what showed this, and doing
  that scan first is cheaper than any of the cuts.

190 top-level `local` lines, **48 of them used across spans of 600+ lines**, and `newPart` alone has
**534 call sites** spread over the whole file. There is no line at which a cut leaves the locals
behind, so §1's recipe does not apply.

**AND THAT 190 WAS THE WRONG NUMBER TO WATCH. The real one was 198, and the ceiling is 200.** The
scan above counts *lines*; Luau counts *names*, and `local addKnob, addScallops, addBunting,
addPlanter, candy` is one line and five registers. Measured by asking the compiler itself — prepend
N dummy top-level locals and find where `loadstring` starts refusing — `ZoneBuilder` at commit
`d7dd54b` compiled with **2** to spare and failed at 3 with *"Out of local registers … exceeded
limit 200"*. So the second file in this project was living on the same cliff as `MainUI`, and in
the file where crossing it does not break a panel but stops the world from building at all. The
`ZoneKit` cut took it to **189**, i.e. 11 of headroom. Re-measure the same way after any move here:
that is the number that decides whether the next edit is safe, not the line count.

**`tools/luaregs.py` is the version of that measurement you can run without Studio open.** It
counts declarations at column 0, comma-form included, and reproduces the compiler's answer on every
file it has been checked against — 169 at `1c9ec1e`, 87 today. The compiler is still the authority;
if the two disagree, fix the tool. Every file in `ServerScriptService` is now under 100 except
`CreatureService` (115).

1. ~~**First build `ZoneKit`**~~ — **DONE 2026-08-17.** `ServerScriptService/ZoneKit.lua`, 495
   lines: `newPart`, the shadow-by-size rule, `SOLID_PROPS` + its audit, `ACTIVE_FRAME`,
   `groundColorOf`, `addPlankText`, `vivid`, `spinForever`, `pulseForever`, the `SIGN_*` palette
   and the platform / terrace-band constants. Moved by `tools/splits/extract_zonekit.py`, byte for
   byte except nine comment lines that said "in this file" about ZoneBuilder and now name it.
   `ZoneBuilder` requires it as a sibling and **re-localises** every name (`local newPart =
   ZoneKit.newPart`), so none of the 534 call sites changed.
   **The one thing that could not be re-localised is `ACTIVE_FRAME`**, because it is reassigned:
   a copy taken at require time would be frozen at nil forever — §3 rule 2, in the server's
   dialect. It has `ZoneKit.setFrame` / `getFrame` and the eight sites that used to assign it now
   call those.
2. ~~Then the leaves, in this order, because each is a section that only reads the kit: the village
   prop library (2,108), ground clutter (3,147), idols and ruins (3,463), the mesh prop layer
   (5,172), the egg plaza (6,136 — 1,759 lines, the single biggest), the boss arena (7,895).~~
   **DONE, in a different order and one fewer cut — see the two corrections above.** The order that
   worked: `VillageKit`, then `ScatterKit` (the enabler), then `BiomeDecor` (which absorbed three
   of the leaves above), `ZoneTerrain`, `EggPlaza`, and `ZoneGate` + `EventArena` together, because
   the arena's way home is the same gateway as every zone boundary.
3. **Read GEMINI.md §7 first.** A careless edit here regenerates or deletes the world, and
   `BUILD_VERSION` must still beat the world's stamp or a rebuild is a silent no-op.
4. **A leaf is not proven by lint, and the eight cuts above are NOT yet proven.** What proved
   `ZoneKit` was a full rebuild in Edit and a census against numbers earlier rows had already
   recorded: `TerraceTop` **784/784** solid (11.23), `ValleyRock` 410/410 and `ValleyRockBase`
   0/410 (11.22), AbsolutePlane's floor back at rgb(204,204,204) Marble (17.7), and the two
   frame-built structures landing at exactly their frame's offset — the Celestial throne at
   **cx − 130.00** and the Volcano cone at cx − 150. A broken frame is invisible to every lint in
   this repo and puts a mountain in the middle of a village.

   **The same census is what the seven later cuts owe**, and it has not been taken: the work landed
   with Studio closed. Everything that *can* be checked off disk has been (`luastruct`, `luascope`
   and `luaregs` on all 100 files, `luaremotes` 53/53, `luanames` unchanged at 13, and every cut
   made by a script that asserts its boundaries) — and none of that is evidence about a picture.
   Run it as one rebuild: the four numbers above, plus a plaza with three shells on their podiums
   (`EggPlaza`), a walkable gate (`ZoneGate`), the arena standing with its way home
   (`EventArena`), and one zone's props photographed (`BiomeDecor`). `AbsolutePlane`'s Marble floor
   is the single most load-bearing of them now: `GROUND_MATERIAL` is handed to `ZoneTerrain` as an
   argument, so an empty one would show there first.

### `CreatureService` (3,868) and `BossService` (3,052) — split the rig factory out

**These are next, and they are now the two largest files in `ServerScriptService`.**

Same shape, smaller: 115 and 82 top-level locals, 42 and 39 of them spanning 400+ lines. The
coupling is concentrated in the rig-building vocabulary — `att` (171 and 210 sites), `mk` (197),
`IDENTITY` (67 and 88), `pairUp`, `INK`, `lighten`.

The seam that exists: in **BossService** those names are all defined between lines 234 and 545 and
almost all their use is above 1,775, so `BOSS RIG FACTORY` + `GENERATED MESH RIGS` (223–1,775,
~1,550 lines) comes out nearly whole. Check `att` and `INK` first — both are read again in the VFX
section around 2,585–2,715, so either the kit goes in its own module both sides require, or those
two uses move with it. **CreatureService** is the same story around its rig factory (533–2,300).

### `UITheme` (2,889) and `StageCostume` (1,626)

Untouched and not yet measured.
