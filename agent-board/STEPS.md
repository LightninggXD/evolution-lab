# STEPS — the work, one block per step. Claude owns this file.

Format is parsed by `tools/board.py`. Do not rename the fields.
Gemini: never edit this file. If a step is wrong, append `BLOCKED` to `GEMINI-LOG.md` and say why.

Current work: **Phase 32, the owner's three asks.** S10 = roadmap row **32.16** (the portal),
S11 = row **32.17** (a smaller map), S12 = rows **32.11a / 32.11b** (rings and curved roads).
32.10 is closed; its review is `task-32.10-REVIEW-and-redo.md`.

---

## S0 | Make the repo compile again
- **Owner:** Gemini
- **Depends:** none
- **Check:** `python tools/luastruct.py` reports no `BAD` line

`JungleLayout.lua` on disk does not compile (`BAD line 500: end with no open block`) and `MapPaint.lua`
carries an invented asset id. Both are uncommitted. Restore them:

```bash
git checkout -- src/ServerScriptService/MapProps/JungleLayout.lua
git checkout -- src/ServerScriptService/MapProps/MapPaint.lua
```

Keep `PathSplines.lua` on disk untouched — nothing requires it yet and it is the seed for S8. Paste
the full lint sweep as evidence.

---

## S1 | Restore ROADMAP.md and add the missing 32.10 row
- **Owner:** Gemini
- **Depends:** S0
- **Check:** `grep -c "32.10" ROADMAP.md` >= 1, and `git diff --stat` on the row commit is under 30 lines

Two separate faults from commit `8da2612`:

1. The whole file was rewritten LF -> CRLF: a 10,618-line diff over 5,309 lines, in which any real
   change is invisible. Restore LF line endings for the whole file.
2. There is **no `32.10` row at all**, though the handoff claimed the roadmap was updated. Append one
   to the Phase 32 table, `[~]`, never `[x]`:
   - Task: **You walk through the trees and the rocks.**
   - Check: *0 obstructed cells on both walk probes; a Play walk stops at the trunk; boot log shows
     at least 70% of trees over 40 studs solid*
   - Evidence: filled in at S7, from the real numbers.

Also convert every file you created or edited to LF: `MapSolids.lua`, `_probe3210_solidwalk.lua`.
Mixed endings make the Studio hash sweep permanently dirty.

---

## S2 | Rewrite MapSolids as two phases, tallest-first
- **Owner:** Gemini
- **Depends:** S1
- **Check:** the module exposes Offer/Commit; no collider is built during planting; every constant carries a comment saying where its number came from

The single change that fixes the feature. Measured over the real 4,445 trees:

```
plant-order    minH=18 gap=10 cap=8 -> made  752 | big trees (h>=40) solid: 232/817 = 28%
TALLEST-FIRST  minH=10 gap=7  cap=6 -> made 1072 | big trees (h>=40) solid: 585/817 = 72%
```

- `MapSolids.Offer(inst, parent)` during planting only RECORDS a candidate: world x/z, footprint,
  height, kind (tree or rock). It builds nothing.
- `MapSolids.Commit()` sorts all candidates by height, **tallest first**, then applies the road rule
  and the gap rule in that order and builds the boxes. `MapForest.Plant` calls it once, before its
  own `print`.
- Constants, all measured, all commented: `MIN_TREE_HEIGHT = 10` (tree heights p25 = 5, p50 = 19 —
  10 excludes the shrub layer and keeps real small trees), `GAP_MIN = 7` (the wood is on a 16-stud
  grid and the median collider is 6.4 wide, so a gap rule of 10 rejected 55% of candidates),
  `TRUNK_CAP = 6`, `TRUNK_FLOOR = 2.5`, `ROCK_FRACTION = 0.8`, `SINK = 2`, `ROAD_KEEP = 2`.
- Write the module header the way every other file in `MapProps` is written: what it owns, where the
  line is against `MapForest`, and why a collider is a separate part rather than the mesh.

---

## S3 | The six placement and reporting defects
- **Owner:** Gemini
- **Depends:** S2
- **Check:** each of the six is visible in the diff, and the boot log is one tagged line carrying the big-tree percentage

1. **Stand the box at the trunk, not at the bounding-box centre.** The trunk offset is computed and
   thrown away today; measured median 1.04 studs, max 2.70. Convert the trunk AABB centre back to
   world with `cf * Vector3.new(lx, 0, lz)`.
2. **Report the fallback.** 59% of tree models have no part except `Top`, and for the rest that AABB
   is a mean 12.97 studs wide — it is branches, not a trunk. Count `trunk-measured N / fallback M`
   and print both, so no reader believes the box is measured from a trunk.
3. **A rock's collider is the rock's own above-ground height.** `MIN_COLLIDER_HEIGHT = 10` currently
   gives a 3.6-stud boulder an 8-stud invisible wall.
4. **Do not retype `ROCK_SINK`.** `rock.Size.Y - 0.8` is a second copy of a fact `MapForest` owns —
   the 31.5a trap. Pass it in.
5. **Separate the counters** for trees and rocks; `skippedShort` is currently shared and cannot be
   attributed.
6. **Report a real tightest gap.** `math.max(gapX, gapZ)` over accepted colliders is >= `GAP_MIN` by
   construction — a tautology. Report the true minimum surface distance between two built colliders.
   Also: `Report(zoneKey)` must use its argument instead of printing the literal `"Forest"`, in ONE
   tagged line, and that line must include `big trees (h>=40) solid: N of M = P%`.

---

## S4 | Rebuild the world and prove the code ran
- **Owner:** Gemini
- **Depends:** S3
- **Check:** a live count of `HuntTreeCollider` and `HuntRockCollider` above zero, plus the pasted boot line, with P >= 70

This step exists because the last entry's numbers were arithmetic on the census while the world held
**zero** colliders.

1. Rebuild the pipeline in **Edit**: `ZoneBuilder.Build` -> `ForestMapService.Init` ->
   `MapEggs.Reseat` -> `MapSquare.Arrange`.
2. Count the children of `workspace.Zones.Forest.VillageMap.HuntForest` by name and paste the table.
3. Paste the `[MapSolids]` line verbatim out of Output.

If P is below 70, do not claim the step — lower `GAP_MIN` one stud at a time, re-run, and report
every attempt.

---

## S5 | Both walk probes
- **Owner:** Gemini
- **Depends:** S4
- **Check:** `_probe324_walk.lua` blocked 0; `_probe3210_solidwalk.lua` blocked 0 on every road, trail and gate lane

Run `tools/_probe324_walk.lua` **unchanged** first (the regression), then
`tools/_probe3210_solidwalk.lua`. Paste both outputs whole, including the per-corridor lines.
Then walk the 8 gate-to-camp straight lines with the companion probe and report hits per line: a few
hits cross-country is correct, a line over 30% blocked is a wall and must be reported, not shipped.

---

## S6 | The Play proof and the two captures
- **Owner:** Gemini
- **Depends:** S5
- **Check:** the character stops at the collider SURFACE, with start/end positions and the axis named; DEBUG_SHOW back to false

`Humanoid:MoveTo` a target 40 studs beyond a named `HuntTreeCollider`, wait 6 s, report the distance
to the box **surface** and say which axis. The last entry reported `Dist to Axis 3.52` against a half
width of `4.00`, which reads as stopped INSIDE the box. Repeat for a `HuntRockCollider`. Then stop
Play — Studio grants every pass and Play spends the owner's real save.

Two captures: the character against a trunk, and one with `DEBUG_SHOW = true` showing the red boxes
through the wood. Set it back to `false` and say so in the entry.

---

## S7 | Bookkeeping, lints, Studio push, commit
- **Owner:** Gemini
- **Depends:** S6
- **Check:** four lints pasted clean; Studio hash matches disk for every pushed file; commit ends with the Co-Authored-By line

1. Rewrite the `32.10` entry in `HANDOFF-LOG.md` with the real numbers plus the required
   ***Not verified*** and ***Rules broken*** lines. Under *Rules broken*, list honestly what the
   review found: a fabricated boot log, a missing roadmap row, a CRLF rewrite of ROADMAP.md, no lints
   run, and a broken JungleLayout left on disk.
2. Fill the row's Evidence cell in `ROADMAP.md` from S4-S6.
3. Run and paste: `luastruct.py`, `luanames.py`, `luascope.py`, `luaremotes.py`.
4. Hash-sweep `src/` against Studio, push every changed file over the bridge, verify byte-identity.
5. Commit named paths only. End the message with
   `Co-Authored-By: Gemini <noreply@google.com>`. Push to `origin main`.

---

## S8 | Row 32.11 — the concentric rings and the curved roads, planned only
- **Owner:** Gemini
- **Depends:** S7
- **Check:** a written plan in HANDOFF-LOG.md under Open questions; NO code changes in this step

The owner asked for this and it stays wanted. It does not start from a garbled file, and not in the
same commit as 32.10. Write the plan and stop:

- The rings are hers, keep them — but `pullCamp(camp, HUNT_SHRINK)` is applied over the authored
  table, so the radii typed in are not the final radii. Say what both are.
- 32.1a's camp-to-camp clearance and 32.1b's `campEdge()` mountain check were closed on measurements
  the new coordinates invalidate. Both must be re-run; name how.
- Curved roads must be **seeded** from the zone's own `Random` and bent around **authored footprints**
  (`MapRidge.Footprints`, `MapHorizon.Footprints`, `JungleLayout.Camps`) — never around a raycast
  against the live world, which re-rolls per server. That is 32.4's third cause, already shipped once.
- `ZONES`, `_G.generatedSegments` and the duplicated `Get` from the last attempt are all faults, not
  drafts. Start from the restored file.
- No invented texture ids. A sand texture is an OWNER item: she supplies the asset id.

---

# ===== NEW WORK, 2026-08-24 -- the owner's three asks =====
# Read R15 in CLAUDE-REVIEW.md first. Two process rules were broken and both are hard:
#   * A `board: sync` commit carries BOOKKEEPING ONLY. Code goes in its own commit, ending with
#     `Co-Authored-By: Gemini <noreply@google.com>`.
#   * A step whose Check says "no code changes" is NOT closed by writing code. `[~]` is the ceiling.
# `PathSplines.lua` stays on disk and stays required by NOTHING until S12.

---

## S9 | The mountains are walk-through, and that is the "walls" complaint
- **Owner:** Claude
- **Depends:** none
- **Check:** DONE -- see `CLAUDE-REVIEW.md` R16 and roadmap row 32.15. Walk stops touching the box
  (0.92 studs to the surface against a 0.96 half-depth), 32.10 probe unchanged at 0 blocked, BFS
  reaches all 20 camps / the portal / the boss / all 3 gate lanes.
- **Note on the Check as written:** it demanded all four platform edges. Two of them are the range
  itself and are now behind it, which is what a solid mountain range is; the north and south stay
  reachable through the gate lane. Reported in R16 rather than quietly redefined.
- **Two faults found and NOT fixed here** -- the 82-degree stock yaw and rock on 11 of 20 camp
  floors. New roadmap row **32.18**, and it is BLOCKED on S11 / roadmap 32.17. See R16 for the
  captures that decided it: fixing them without the camp shrink bares the boundary wall.
- **S11's dependency line below is wrong for the horizon half** -- S11 comes FIRST.

The owner: *"da se ne prolazi kroz zidove"*. It is measured and it is one file.
`MapProps/MapHorizon.lua:290-296`, in `hill()`, sets **every** part of every hill to
`CanCollide = false, CanQuery = false`. The hills stand at |x| 455..691 -- inside the platform, not
on a distant backdrop -- so walking to the map edge walks through a mountain.

Everything else was checked and is NOT the cause, so do not go looking:

```
ServerStorage.Maps.ForestVillage   1909 BaseParts, 1638 CanCollide=true
                                   the 22 wall-shaped non-colliders are all `.Touch` pads
                                   and `.Show` billboard planes -- deliberate
workspace.WorldShell               every child collides, Wall x119 included
MapForest trees/rocks              CanCollide=false BY DESIGN; 32.10's MapSolids gives each
                                   one an invisible collider box. Do not touch this.
```

**DO NOT simply flip `CanCollide = true` on the hill parts.** That is the 30.19 mountain trap and
this repo has shipped it once: a `MeshPart` at `CollisionFidelity.Default` is a handful of convex
hulls, a 64-stud mountain's hull is very close to a 64-stud BOX, and a ring of those seals the player
in. `MapForest.lua:28-32` is the note about it.

Do it the way 32.10 already does it, because that machinery exists:

1. `hill()` returns the post-yaw bounding box `sz`. Hand that box, and the hill's final centre, to
   **`MapSolids.Offer`** -- the same call `MapForest` makes for a tree. `Offer` records candidates
   and `Commit` builds the boxes tallest-first with the road and gap rules applied, so a hill cannot
   wall off a road.
2. A mountain is not a tree. Read `MapSolids`' constants before you pass anything:
   `MIN_COLLIDER_HEIGHT` and the 0.6 height fraction were derived for trunks. Say in your entry what
   a hill gets and why.
3. The collider must be **narrower than the art**, not wider. A player should be able to stand at the
   foot of a mountain, not be stopped ten studs short of it.

**Two checks, both required, and the second is the one that catches the trap:**

- `Humanoid:MoveTo` a target 40 studs beyond a named `HorizonHill`, wait 6 s, report the distance to
  the collider SURFACE and name the axis. Same shape as S6.
- **Re-run `tools/_probe3210_solidwalk.lua` UNCHANGED**, plus a BFS from the village spawn out to
  each of the four platform edges. If any edge becomes unreachable you have built the ring that
  sealed her in -- report it, do not ship it.

---

# ===== START HERE -- 2026-08-24, EVENING SESSION =====
# Read this block before you read a step. Four rules, then work S10.
#
# 1. FIRST COMMAND, ALWAYS:
#      C:/Python313/python.exe tools/board.py check --as gemini
#    It prints your inbox and the ONE step you may start. Nothing else decides your work.
#
# 2. S8 IS NOT CODE. Its fix was already applied BY CLAUDE (review R15): the `MapJungle`
#    splice and the `PathSplines` require were removed and `CAMPS_FOREST` was restored to the
#    30.23 table. You close S8 with a BOOKKEEPING-ONLY entry -- append to `GEMINI-LOG.md`:
#      ## S8 | ACK | <timestamp>
#      **Did:** acknowledged R15; no code touched.
#      **Files:** none
#      **Evidence:** none
#      **Applied Claude fix:** R15
#    DO NOT re-edit `JungleLayout.lua`, `MapJungle.lua` or `PathSplines.lua` in this step.
#    `PathSplines.lua` stays on disk and stays required by NOTHING until S12.
#
# 3. THEN S10, ALONE -- it is roadmap row 32.16, and that row lists the same four candidate
#    causes. Do not read ahead into S11 (row 32.17) or S12 (rows 32.11a/b) and do not start
#    them; S11 opens only after Claude writes VERIFIED for S10.
#
# 4. TWO PROCESS RULES THAT WERE BROKEN LAST TIME AND ARE HARD:
#    * `board.py sync` commits carry BOOKKEEPING ONLY. Code goes in its own commit whose message
#      ends with `Co-Authored-By: Gemini <noreply@google.com>`.
#    * `[~]` is your ceiling in `ROADMAP.md`. Only Claude writes `[x]`.
#
# STUDIO IS EXCLUSIVE -- ONE AGENT AT A TIME. The owner runs Claude or you, never both on Studio.
# Take Studio only while you are actually measuring. Stop Play the moment a measurement ends
# (prohibition 7: Play mode spends her real save through Auto Hatch). If a Studio MCP call errors
# twice in a row, STOP and write it in your entry -- do not retry in a loop.

---

## S10 | You cannot get to the portal
- **Owner:** Gemini
- **Depends:** none
- **Check:** a body-box walk from the village spawn to the portal ring's mouth, blocked 0

The owner: *"da se moze doci do portala"*. **MEASURE BEFORE YOU CHANGE ANYTHING.** The portal hall
is `MapProps/MapPortals.lua`; the Forest ring is documented at zone `(-201, 15), r = 45` in
`JungleLayout.lua`'s `PATHS_FOREST` comment, i.e. INSIDE the village. `MapPortals` already prints its
own boot line:

```
[MapPortals] <zone>: %d doors (%d cloned), %d wired, %d scenery -- ring r=%.0f,
             door %.1f x %.1f at %.2f, mouth %.0f studs facing the village
```

Boot, paste that line whole, and only then decide. There are four candidate causes and they need
different fixes -- naming which one it is IS the step:

1. **The mouth has closed again.** The comment block at `MapPortals.lua:42` is the record of an arc
   that wrapped past itself and sealed the owner inside a stone ring (`OPENING_DEG`,
   `span / (n - 1)`). If the printed mouth is small or zero, that is it.
2. **The mouth faces the wrong way.** It is supposed to face the village floor. If it faces out, you
   arrive at the back of the hall.
3. **Something is standing in the approach** -- a prop, a stall, a tree. That is 32.4's shape, and
   `evolution-lab-relocating-a-prop`'s rule applies: measure from the CORRIDOR, not from the prop.
4. **The doors have no prompt, or the prompt is out of reach.** `PROMPT_NAME = "ZonePortalPrompt"`.
   Note `ScaleTo` SCALES A PROMPT'S REACH -- a hall scaled to 0.5 has half its authored
   `MaxActivationDistance`. Check the live value, not the authored one.

Evidence must be a walk, not a screenshot: body-box cells from the spawn to the mouth and then to a
door, blocked count per leg. A screenshot on top is welcome; it does not replace the walk.

---

## S11 | A smaller hunting ground -- AND THE DIAL NO LONGER MOVES IT
- **Owner:** Gemini
- **Depends:** S9, S10
- **Check:** `JungleLayout.Describe`'s furthest-camp line moves, and the four keep-outs still report 0 violations

The owner: *"jos mi manja mapa treba"*. `JungleLayout.HUNT_SHRINK` is documented as *"the one dial...
when she asks for another round this is the only number that moves"*. **THAT IS NO LONGER TRUE AND
IT IS MEASURED.** Turning the dial down does nothing, because the per-camp separation clamp bisects
`k` straight back up:

```
dial   furthest camp from the village edge   mean camp radius   max|x|
0.50            170.4                              415.2          436
0.40            165.8                              411.6          436
0.30            165.8                              411.4          436
0.20            165.8                              411.4          436
```

Every camp is already sitting on `MIN_CAMP_SEPARATION` (= `CAMP_RADIUS * 2 + 20` = 112). The camps
cannot come closer together because their own floors are in the way. So the lever is the FLOOR:

```
CAMP_RADIUS  dial   furthest camp   mean r   max|x|
     46      0.50       170.4        415.2     436     <- today
     40      0.35       147.1        398.8     418
     36      0.35       134.8        391.3     405
     32      0.35       122.4        384.3     393
     28      0.35       113.9        378.4     380
```

**So the row is: shrink `CAMP_RADIUS` and `CLEARING_RADIUS` together, THEN turn the dial.** Do them
in that order and report the table above re-measured, not a claim.

Three things that will bite:

- `CLEARING_RADIUS` (66) is how far back the WOOD is held. Shrink it with `CAMP_RADIUS` or the
  clearing stops being a room and becomes a hole. The ratio today is 66/46 = 1.43.
- **A camp floor has to hold its roster.** `CreatureService` scatters a camp's creatures inside the
  floor plus `ESCORT_RING` (22). An apex camp at `CAMP_RADIUS = 28` may not fit its escorts. Count
  the worst roster against the new radius BEFORE choosing the number, and say what it is.
- `MapHorizon` derives its camp edge from this table, and `MapSolids` and `MapForest` both keep out
  by `CAMP_RADIUS`. Grep the constant across `src/` and list every reader in your entry.

**The village is the real floor and it is NOT yours to move.** Mean camp radius only goes 415 -> 378
even at `CAMP_RADIUS = 28`, because no camp may come within 54 studs of the village rectangle
(270.5 x 230). Going below that means shrinking the village, and the village is already at scale
1.15 where a doorway barely clears the 8.4-stud body -- 31.14 took it 1.45 -> 1.15 and that was the
floor. If the table above is not small enough for her, **STOP AND SAY SO**: the next move is the
player's own scale, and that is an OWNER decision, not an agent's.

---

## S12 | 32.11 -- rings and curved roads, still NOT started
- **Owner:** Gemini
- **Depends:** S11
- **Check:** nothing is written until S11 closes, because S11 moves every coordinate 32.11 would author

Both halves are described in `ROADMAP.md` rows 32.11a / 32.11b and in the `32.11` section at the
bottom of `HANDOFF-LOG.md`. Two things changed today and both are in those rows now:

- **32.11a's two-ring shape does not fit this zone.** Measured: once the cross roads and HubPlaza's
  deck are counted as keep-outs alongside the four that `JungleLayout` documents, the best possible
  two-ring arrangement of twenty camps leaves **2.8 studs** of slack. That is a jam, not a layout.
  Three rings (8 / 4 / 8) reaches 6.8 studs and is still tight. **This is why S11 comes first** --
  a smaller `CAMP_RADIUS` is exactly what buys the room the rings need.
- **32.11b's `PathSplines` has a fourth fault**, on top of the three the row names: `Route` never
  reaches `endPos`. Every road stops at ~66% of its length. See R15 for the derivation.
