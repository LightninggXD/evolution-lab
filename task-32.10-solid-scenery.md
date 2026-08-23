# TASK 32.10 — SOLID SCENERY: the player must not walk through trees and rocks

Owner's report (2026-08-23, live Forest): *"trebam napraviti da se kroz odredjene objekte ne moze
prolaziti, kao sto su stene, drveca i tako to"* — she walks straight through the trees and the
boulders in the Forest wood. She must be able to press Play and feel the difference.

Scope: **Forest zone only** (the Phase 31/32 rule). Read `GEMINI.md` first; every rule there still
applies. This document adds task-specific rules on top of it and overrides nothing in it.

---

## 0. THE ONE SENTENCE

You will NOT make the tree and rock **meshes** collide. You will write **one small new module** that
stands an **invisible convex box** at the foot of each big tree and beside each big rock — the exact
pattern this repo already ships in `MapJungle` — and wire it into the planter behind measured
clearance rules, so it can never seal a road or a corridor.

---

## 1. HARD RULES FOR THIS TASK (breaking any of these is a rollback)

1. **NEVER set `CanCollide = true` on a `MeshPart` of the art** — not a tree clone, not `HuntRock`,
   not `JungleRock`, not a mountain, not a village prop. A `MeshPart` at
   `CollisionFidelity.Default` is a handful of convex hulls that, for chunky low-poly art, is very
   nearly its **bounding box**. That is the 30.19 mountain trap, and it is literally the bug the
   owner reported herself in 32.1b (*"prolazim kroz planine"* — she was stuck inside one). A
   thousand colliding canopies would be a thousand of those traps. **Colliders are separate,
   invisible `Part`s. Always.**
2. **NEVER set `CanQuery = true` on the new colliders, and never change `CanQuery` on the art.**
   `MapForest.lua:33-40` documents why: eight services run AFTER the planter and find their spot
   with a box query or a downward ray (`Splicer`, `HubPlaza`, `MinigameService`, `MapArcade`,
   `MapAdventureBoard`). A queryable wood is boot log 30.17 — services that can no longer find any
   clear ground. `CanQuery = false` does **not** affect physics; collision still works. Read §6.3,
   because it means the existing walk probe is blind to your colliders and you must write the
   companion probe.
3. **NEVER make the undergrowth, the shrubs, the flowers or the small stones solid.** Only objects
   above the measured size thresholds in §4.2. A player who catches on a bush reports a worse bug
   than the one you are fixing.
4. **NEVER edit** `src/ServerScriptService/ZoneBuilder.lua`, `MainUI.client.lua`, `GameConfig.lua`,
   the `SOLID_PROPS` table in `ZoneKit.lua`, `MapHorizon.lua`, `MapRidge.lua`, or the existing
   `standRock` collider code in `MapJungle.lua`. The mountains were solved in 32.1b by moving them
   out of the play area — do not revisit that. `ZoneKit.SOLID_PROPS` is the other nineteen zones'
   policy and is out of scope.
5. **NEVER invent a collision group.** Measured: creatures are `Anchored = true` and moved with
   `workspace:BulkMoveTo` (`CreatureService.lua:2866`), so scenery colliders cannot wedge a
   creature. There is no `PhysicsService` collision group anywhere in this repo and this task does
   not add the first one.
6. **NEVER delete or rewrite an existing comment** to make room for your code (prohibition 10).
   Every constant you add gets its own comment saying **why that number**, in the style of the file
   it lands in.
7. **NEVER mark the roadmap row `[x]`.** Your ceiling is `[~]`.
8. **Do not leave Studio in Play mode** after a measurement (prohibition 7 — Play spends her real
   save through VIP Auto Hatch).

---

## 2. FACTS ALREADY MEASURED — DO NOT RE-DERIVE THEM

| Fact | Where |
|---|---|
| The Forest wood is planted by `MapForest.Plant` — trees via `plantOne`, rocks via `dropRock` | `src/ServerScriptService/MapProps/MapForest.lua:148`, `:274` |
| Everything it plants is `CanCollide = false` **and** `CanQuery = false`, deliberately | `MapForest.lua:28-40`, `:155-163`, `:286-289` |
| All three tree layers are named `HuntTree`; the rocks are `HuntRock`; both live in the `HuntForest` folder under `VillageMap` | `MapForest.lua:165`, `:292`, `:244-246` |
| Layer scales: emergent `1.35..1.7`, canopy `0.80..1.20`, undergrowth `0.38..0.62`, shrubs `0.7..1.4`; the tree stock itself is 30..110 studs tall | `MapForest.lua:65-91`, `:98-110` |
| Grid spacing is **16 studs**; the wood runs x ±610, z ±560 | `ForestMapService.lua:195` |
| A tree model's foliage mesh is named **`Top`** — that is how `treeStock` recognises a tree | `MapForest.lua:98-110` |
| The correct collider pattern already exists: invisible `Part`, **80% of the rock's footprint**, full height, yaw only, `Transparency = 1`, `CastShadow = false` — with the comment explaining why 80%: the art overlaps so the ring reads as one wall, while the thing the shoulder meets stays a clean convex box with gaps between the boxes, which is what stops a body wedging in a corner it cannot see | `MapJungle.lua:142-177` |
| The player body box is **9 x 8.4 x 7** studs | `MapJungle.lua:190`, `tools/_probe324_walk.lua:29` |
| Roads: `JungleLayout.RoadClearance(zoneKey, x, z, segments)` returns studs from the road SURFACE (the half-width is already subtracted). `MapJungle` demands `ROCK_KEEP = 13` for a 22-wide box | `JungleLayout.lua:567`, `MapJungle.lua:88-95` |
| The wood is already held 14 studs off the paint (`ROAD_VERGE`) and out of the village, plaza, funnel, boss ground, camps and mountains | `MapForest.lua` `isOpenGround` |
| The map is rebuilt from scratch on **every server boot** — `ForestMapService.Init` destroys `VillageMap` and re-clones it. There is **no** `BUILD_VERSION` stamp on this path, so your change is visible on her next Play with no rebuild ritual | `ForestMapService.lua:432-520` |
| The wood is seeded (`Random.new(20260822 + cx)`) so two servers grow the same forest — anything you add must be deterministic too | `MapForest.lua:249-250` |

---

## 3. STEP 1 — MEASURE BEFORE YOU CHANGE ANYTHING (mandatory; produces numbers you must report)

Run in the **Edit** datamodel after rebuilding the pipeline (`ZoneBuilder.Build` ->
`ForestMapService.Init` -> `MapEggs.Reseat` -> `MapSquare.Arrange`), otherwise you are measuring a
stale world (`evolution-lab-edit-world-stamp-lag`).

**3a. Census.** Walk `workspace.Zones.Forest.VillageMap` and print, per distinct instance name:
count, how many are `CanCollide = true`, and the median bounding-box size. This answers *which
objects she actually walks through*. The village's own authored props may already be solid, and
rule 6 says you do not touch what is not broken. Put the table in `HANDOFF-LOG.md`.

**3b. The trunk measurement.** For **five** tree prototypes out of `treeStock(map)`, print:
- the model bounding box (X, Y, Z);
- the names of every `BasePart` inside it;
- the combined world-space AABB of every part **NOT** named `Top` — that is the trunk;
- the ratio `trunkFootprintMin / modelBoxMin`.

**The collider is sized from the trunk's own footprint, never from a guessed fraction of the
canopy.** If a model has no part other than `Top`, fall back to `0.18 * min(boxX, boxZ)` and count
how often the fallback fires — print that counter. An invisible wall wider than the visible trunk is
exactly the fault this step exists to prevent.

**3c. Rock heights.** Print min / median / max above-ground height of `HuntRock`
(`Size.Y - ROCK_SINK`, with `ROCK_SINK = 0.8`) over a real build.

Do not write a line of the feature until these three are printed.

---

## 4. STEP 2 — THE MODULE YOU WILL WRITE

New file: **`src/ServerScriptService/MapProps/MapSolids.lua`**. A small module with one job, per her
standing rule that a big file burns tokens on every read. It owns *"what a scenery prop's collision
proxy is"* and nothing else. It must **not** require `MapForest` (that is a cycle); `MapForest`
requires it.

### 4.1 Public API — exactly these four functions

```lua
-- Begin a run: clears the spatial hash and the counters. Called once per zone build.
function MapSolids.Begin(zoneKey, segments)

-- Stand a trunk collider at a planted tree. `model` is the seated clone, already scaled and pivoted.
-- Returns true if a collider was made, false if it was skipped (and why, into the counters).
function MapSolids.TreeCollider(model, parent)

-- Stand a box beside a planted rock. `rock` is the seated BasePart.
function MapSolids.RockCollider(rock, parent)

-- Print the one boot line and return the counters table.
function MapSolids.Report(zoneKey)
```

### 4.2 The rules it enforces — every one a named constant with a comment saying why

| Constant | Value | Why |
|---|---|---|
| `MIN_TREE_HEIGHT` | `18` | Twice the 8.4-stud body. Below that the thing is a sapling, and catching on it is worse than walking through it. This skips most of the `0.38..0.62` undergrowth **without naming a layer** — the object's own measured height decides. |
| `MIN_ROCK_HEIGHT` | `3.5` | Above-ground height. Under it the body steps over anyway (`RISE = 3.0` in the walk probe) and a collider would only trip her. |
| `TRUNK_FRACTION` | `1.0` of the measured trunk AABB, capped at `8` studs, floored at `2.5` | The collider **is** the trunk and is never wider than the art. The cap exists because a scaled emergent's trunk can pass 12 studs, and a 12-stud invisible box between two 16-stud grid cells is a fence. |
| `ROCK_FRACTION` | `0.8` | The same 80% `MapJungle` already uses, for the reason written in its own comment. Do not invent a different number — cite that comment. |
| `COLLIDER_HEIGHT` | `0.6 * modelHeight`, min `10` | The canopy must never be solid: you may not be able to stand on a tree. |
| `SINK` | `2` | The box starts 2 studs below ground, so uneven terrain never leaves a gap underneath it. |
| `GAP_MIN` | `10` | Surface-to-surface between two colliders. The body's collision hull is far narrower than its 9-stud extent box, so 10 studs walks through comfortably; below that a clump becomes a wall. **A candidate that fails this is SKIPPED, not shrunk** — that tree stays walk-through and the art is untouched. |
| `ROAD_KEEP` | `2` studs beyond the collider's own half-diagonal | Measured from the road SURFACE with `JungleLayout.RoadClearance`, the same way `MapJungle.ROCK_KEEP` derives its 13. A collider in a road is a wall you cannot see — that is roadmap 32.4; do not repeat it. |
| `DEBUG_SHOW` | `false` | When `true`, colliders render at `Transparency 0.55`, bright red, `Material = Neon`. This is how the owner and the reviewer *see* invisible geometry in a capture. **Ship it `false`.** |

### 4.3 Collider properties — all of them, no exceptions

```lua
local box = Instance.new("Part")
box.Name         = "HuntTreeCollider"   -- or "HuntRockCollider"
box.Size         = Vector3.new(w, h, d)
box.CFrame       = CFrame.new(x, groundY - SINK + h / 2, z) * CFrame.Angles(0, yaw, 0) -- YAW ONLY
box.Anchored     = true
box.CanCollide   = true
box.CanQuery     = false  -- rule 2: the placement services must keep seeing open ground
box.CanTouch     = false  -- nothing uses Touched on scenery; one less event source
box.Transparency = DEBUG_SHOW and 0.55 or 1
box.CastShadow   = false
box.Parent       = parent -- the same HuntForest folder, so one Destroy still removes the whole wood
```

**Yaw only.** The rocks tilt up to 0.16 rad; a tilted box makes an overhang a body can wedge under.
The art tilts, the box does not.

### 4.4 The gap rule, concretely

Keep a spatial hash `cells[cx][cz]` with `cx = math.floor(x / 32)`. For each candidate, test its box
against every collider already registered in the 3x3 neighbouring cells, **surface-to-surface in
XZ**: reject when
`math.max(0, math.abs(dx) - (halfA.X + halfB.X)) < GAP_MIN` **and**
`math.max(0, math.abs(dz) - (halfA.Z + halfB.Z)) < GAP_MIN`.
Yaw is ignored in this test on purpose — it errs in the safe direction.

Count every rejection. If **more than 25%** of candidate trees are skipped by the gap rule, do not
silently ship: `warn` it, and write the number into the handoff. That means the wood is denser than
this rule assumes, and the reviewer decides what to do about it, not you.

### 4.5 The boot log line — this is how the owner sees that it worked

Exactly one line, in the `[MapForest]` house style:

```
[MapSolids] Forest: 1842 tree colliders + 611 rock colliders (skipped 214 short, 96 clumped, 7 road)
-- tightest collider gap 10.4 studs, tightest road clearance 15.2 studs
```

Those two "tightest" numbers are the point: they are what a reviewer checks instead of trusting the
code.

---

## 5. STEP 3 — WIRING (exact call sites; nothing else changes)

1. `MapForest.lua`: `local MapSolids = require(script.Parent.MapSolids)` beside the existing
   requires.
2. In `MapForest.Plant`, right after `segments` is resolved: `MapSolids.Begin(zoneKey, segments)`.
3. `plantOne` already returns the clone `t`. **Do not add an optional `solid` argument** to it.
   `MapSolids.TreeCollider` decides from the model's own measured height, so there is nothing to
   pass and nothing for a call site to forget — this repo has already shipped "an optional argument
   no call site passes", which is a safety net that does not exist. The correct wiring is **one
   line inside `plantOne` just before `return t`**, and **one line inside `dropRock` just before
   `return 1`**.
   Note that shrubs go through `scatter` with the shrub stock and therefore also reach
   `TreeCollider` — that is fine and correct: they are 2..20 studs tall and `MIN_TREE_HEIGHT = 18`
   rejects effectively all of them on their measured height. **Verify that in the census; do not
   assume it.**
4. Immediately before the existing `print` at the end of `MapForest.Plant`, call
   `MapSolids.Report(zoneKey)`.
5. Nothing else. Do not touch `isOpenGround`, the layer constants, the density curve, the seeding,
   `MapJungle`, or `ForestMapService`.

---

## 6. STEP 4 — VERIFICATION. FOUR TESTS, ALL FOUR REQUIRED, ALL WITH NUMBERS

A row closes on live verification. Reading the code is not verification; compiling is not
verification.

**6.1 The boot log.** Rebuild the pipeline in Edit and paste the real `[MapSolids]` and
`[MapForest]` lines. Both counts must be non-zero and both "tightest" numbers must clear their
constants.

**6.2 The road walk — regression.** Run `tools/_probe324_walk.lua` **unchanged**. It walks the
9 x 8.4 x 7 body box down the centre and both edges of every road, trail and gate lane (~1,656
cells). Required: **0 obstructed cells**, the same as it reports today. Paste the exact counts.

**6.3 The companion probe — which you must write, because 6.2 is blind to you.**
`_probe324_walk.lua` uses spatial queries and your colliders are `CanQuery = false`, so it **cannot
see them, by design**. Write `tools/_probe3210_solidwalk.lua`: the same lines, the same box, but
tested explicitly against every part named `HuntTreeCollider` / `HuntRockCollider`, collected **by
name** out of the `HuntForest` folder:

- transform the body-box centre into each collider's frame with
  `collider.CFrame:PointToObjectSpace(p)`;
- treat the body as a circle of radius `math.sqrt(4.5^2 + 3.5^2) = 5.70` studs in XZ (conservative);
- report a hit when `math.abs(local.X) < halfX + 5.70` **and** `math.abs(local.Z) < halfZ + 5.70`
  **and** the vertical spans overlap.

Required: **0 hits on every road, trail and gate lane.** Then also walk **8 straight lines from the
village gates to 8 different camps** and report hits per line. A handful of hits on a cross-country
line is expected and correct — it is a wood. A line with more than 30% of its cells blocked is a
wall: report it, do not ship it.

**6.4 The real proof — walk into a tree in Play.** Nothing above proves physics. In Play: pick one
`HuntTreeCollider`, record the character's start position, `Humanoid:MoveTo` a target **40 studs on
the far side of the trunk**, wait 6 seconds, print the final distance to the trunk's centre axis.
Required: the character **stops at roughly the collider's half-width** and never reaches the far
side. Repeat once for a `HuntRockCollider`. Print both start/end positions and both distances. Then
**stop Play**.

**6.5 One capture** (she asked to see it): a screenshot of the character standing against a tree
trunk, plus one with `DEBUG_SHOW = true` showing the red boxes through the wood. Set `DEBUG_SHOW`
back to `false` before committing, and say in the handoff that you did.

---

## 7. STEP 5 — BOOKKEEPING

1. **Add the row to `ROADMAP.md` Phase 32 BEFORE you fix it** (`GEMINI.md` §2: an owner-reported bug
   becomes a row first). Number it `32.10`, `[~]` when done, never `[x]`. Task cell: *"You walk
   through the trees and the rocks."* Check cell: *"0 obstructed cells on both walk probes; a Play
   walk stops at the trunk."* Evidence cell: your measured numbers.
2. **Append one `HANDOFF-LOG.md` entry** with the required fields: the §3 census table, every number
   from §6, an explicit ***Not verified*** line for anything you could not run, and a ***Rules
   broken*** line (write `none` if none).
3. **Run all four lints** and paste the output: `python tools/luastruct.py`,
   `python tools/luanames.py`, `python tools/luascope.py`, `python tools/luaremotes.py`. They prove
   syntax and scope only — they say nothing whatsoever about a collider. Do not present them as
   evidence that the feature works, and do not put the word "live" beside them.
4. **Commit named paths only** (never `git add -A`): the new module, `MapForest.lua`, the new probe,
   `ROADMAP.md`, `HANDOFF-LOG.md`. Message: what changed and why it mattered, ending with
   `Co-Authored-By: Gemini <noreply@google.com>`. Push to `origin main`.
5. **Last line of the handoff entry, addressed to the owner:** press Play and walk into any big tree
   in the wood — you now stop at the trunk; set `MapSolids.DEBUG_SHOW = true` to see the boxes.

---

## 8. WHAT "DONE" IS NOT

- Not "it compiles" — Luau compiles an undeclared read as a global read.
- Not "the lints are clean" — all four were clean on the day the trading feature was found to be
  completely unreachable.
- Not "I set CanCollide on the trees" — that is the mountain trap at scale, and it gets reverted.
- Not "the walk probe passed" — `_probe324_walk.lua` cannot see your colliders (§6.3).
- Not a redesign. If you find something else wrong in the wood, write it under *Open questions* in
  `HANDOFF-LOG.md` and leave the code alone.

## 9. STOP AND ASK IF

- The §3a census shows that what she walks through is **not** `HuntTree` / `HuntRock` (for example,
  the village's authored props are the walk-through ones). Report what you measured and stop — the
  fix then lives in a different file and is a different row.
- More than 25% of the trees are skipped by the gap rule (§4.4).
- Studio refuses Edit mode, or the hash sweep is dirty — prove which side is ahead before pushing.
