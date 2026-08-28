# STEPS — the work, one block per step. Claude owns this file.

Format is parsed by `tools/board.py`. Do not rename the fields.
Gemini: never edit this file. If a step is wrong, append `BLOCKED` to `GEMINI-LOG.md` and say why.

Current work: **Phase 34's four in-flight features, none of which can run.** S16 = row **33.9**'s
botched double patch, S17 = row **34.1** (achievements + titles), S18 = row **34.2** (the vanity
layer), S19 = row **34.4** (the community goal), S20 = the unreviewed **34.5-34.8** code on disk.
All five are DISK-ONLY: Studio, the push and every capture stay with Claude.

Earlier: **Phase 32, the owner's three asks.** S10 = roadmap row **32.16** (the portal),
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
# 3. THEN **S13** -- it is the owner's own picture ("zakopan je ne vidi se kako treba") and it is
#    the priority. Roadmap row 32.19. S10 was reviewed and REJECTED (R17): its evidence was never
#    measured, and the village door ring turns out to be reachable -- read R17 before you re-open
#    it. Do not read ahead into S11 (row 32.17) or S12 (rows 32.11a/b) and do not start them.
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
- **Depends:** S9
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

---

## S13 | PARKED until S11 -- the arrival gate is buried in the mountains
- **Owner:** Gemini
- **Depends:** S11
- **Check:** a 12-stud raycast grid over the gate footprint (x -120..108, z 308..657, 600 cells)
  reports **0 cells standing on a `HorizonHillCollider`** -- it is 252 today -- AND a screen capture
  from the player's own eye at the gate shows the portal standing clear

> ### 👤 PARKED BY THE OWNER, 2026-08-24 -- DO NOT WORK THIS STEP.
> Fork (a) was built here twice and measured (review **R19**). Both builds pass the Check --
> 0 of 600 cells -- and both fail the capture: moving the inner row off the gate bares the flat
> boundary wall behind it, which is the 48%/41% finding `MapHorizon`'s own `LANE_PORTAL`
> comment already records. Shown that, the owner chose to **wait for the camps to shrink**
> (**S11 / roadmap 32.17**) rather than take either fork against today's coordinates. See R21.
> Everything below this banner is the ORIGINAL brief, kept for when the step re-opens; its
> line *"THE OWNER PICKED FORK (a)"* was written before anyone had built (a) and no longer
> holds. The patch is parked outside the repo.

**Order: the S8 `ACK` comes first because a pending fix outranks new work -- and then THIS, not S10.**

**THIS IS THE OWNER'S OWN COMPLAINT AND SHE HAS ALREADY PICKED THE FIX.** She sent a capture of her
character at the north gate: *"zakopan je ne vidi se kako treba"*. Roadmap row **32.19** carries the
whole finding; read it before you touch anything. Do not re-derive it -- it is measured.

**What is wrong, measured on the live server 2026-08-24:**

```
north gate parts                       57, spanning x -120..108, y 0..222, z 308..657
  ... inside a hill's own bounding box 48 of 57
  ... inside a hill COLLIDER box       18 of 57
gate footprint, 12-stud raycast grid   600 cells; 252 of them (42%) land on a
                                       HorizonHillCollider whose top is y = 236.4
the two hills responsible (inner row)  centre (-242, 111, 568), reaches x -418..-65
                                       centre ( 261, 112, 556), reaches x   83..440
their collider boxes                   (-242, 117, 611), x -448..-35, 238 studs tall
                                       ( 261, 119, 601), x   71..451, 241 studs tall
the walkway itself                     still open: a body-box walk to ZonePad (0, 0.5, 490)
                                       is 20 samples, 0 blocked -- the lane holds at x ~ 0
```

**THE ARITHMETIC IS THE WHOLE TASK, and it is one line.** `MapHorizon.buildRun` reserves the gate
lane by holding a hill's CENTRE at

```lua
local lo = spec.lane > 0 and (spec.lane + spec.alongLen * FILL / 2) or 0
```

`FILL` is **0.55**, a silhouette fraction averaged over the hill's whole height. But 32.15's collider
is built from **`ROCK_FOOT` 0.92** of the same box, because at the player's feet a mountain fills
nearly all of it. The two disagree by `(0.92 - 0.55) / 2 = 0.185` of a ~460-stud hill, so **every
collider overhangs its own lane by about 85 studs** -- with `LANE_PORTAL = 90` the reserved gap is
+-90 and the collider edges land at x = -35 and x = +71. That is the 42%.

The file already makes this argument against itself: `MapHorizon.Colliders` refuses to box the OUTER
row because *"a box on an outer hill is a box across the gate"*. Nobody carried it to the inner
row's lane. And the comment above `LANE_PORTAL` argues for 90 over the older 132 on a premise that
**died with 32.15**: *"these hills do not collide, do not query and are sunk 15 studs -- nothing
walks into them"*. They collide now.

**THE OWNER PICKED FORK (a): widen the lane until the gate's own footprint is clear.** Fork (b) --
clip only the collider boxes off the gate -- was offered and REJECTED, because it leaves the portal
looking buried, which is what she complained about. Do not implement (b).

**Three things the patch must do, and a fourth it must not:**

1. **Reserve what the COLLIDER occupies, not the silhouette.** The offset in `buildRun` comes from
   the same fraction the collider is built from (`ROCK_FOOT`), not from `FILL`. Today the run that
   carries colliders is exactly the run that has a lane -- write that in the comment, do not leave
   it implied.
2. **The lane must be at least the gate's own stonework.** The gate spans x -120..108, so 90 was
   never enough even before the colliders. The walkway reservation this codebase already owns is
   **`ZoneGate.PORTAL_CLEAR_HALF = 132`** -- *"how far boulders stay off the centre line"*. Restate
   it with a comment naming `ZoneGate`, the way `WALL_X` is restated at the top of the file. **Do
   NOT add a require**: this file's header says why it restates instead.
3. **Rewrite the comment block above `LANE_PORTAL` so it tells the truth**, keeping the history --
   32.15 gave the inner row colliders, 32.19 is this change. A comment explaining WHY a number is
   what it is, is the most expensive line in this file to lose (prohibition 10).
4. **Change nothing else.** No new requires, no renamed functions, no tidying. Do not touch
   `Colliders`, `trimOffRoads`, `hill`, `worldBox`, or any constant not named above. `MapSolids` is
   not part of this row.

**What you must report, and every line of it is pasted output:**

- the new `[MapHorizon]` boot line beside today's, which reads
  `66 hills over 8 runs ... 34 collider box(es) offered, 29 clipped, 0 dropped`
- the gate-footprint grid: 600 cells, how many on a `HorizonHillCollider` (must be 0)
- `tools/_probe3210_solidwalk.lua` re-run **UNCHANGED**: it must stay `1656 samples, 0 blocked`
- the camp check: `0 of 20 camp floors overlapped by a box`
- **a capture from the player's own eye at the gate** -- prohibition 8, and this row is a LOOK

**THE RISK IS REAL AND IT IS YOURS TO REPORT, NOT TO ENGINEER AWAY.** Widening the lane thins the
inner wall above the gate. An older cut at 132 measured the boundary wall **48% bare on the south
and 41% on the north**. Since then the OUTER row was deliberately made to run WHOLE across the gate
to fill exactly that hole -- read the note in `Build` that says so. If your capture shows bare slate
above the gate, **report it and stop**; do not add a second mechanism to compensate. That is an
owner call and she has already had one fork today.

---

## S15 | 33.12 -- 41 pet glyphs that may never be drawn, and the tripwire that would have caught them

- **Owner:** Gemini
- **Depends:** none
- **Note:** DISK-ONLY row. You do not need Studio, and you must not use it.
- **Check:** `src/ReplicatedStorage/Modules/GameConfig/Pets.lua` -- every `emoji =` field decodes to
  a codepoint **>= 0x1F300**, the file carries a load-time tripwire in the shape of the one in
  `Adventures.lua`, and `tools/luastruct.py` + a UTF-8 byte-for-byte re-read both pass.

**THE FAULT, and it is photographed.** The away card for `Pebble` rendered as
`Pebble  •  tier 1  •  luck x1.00` with **no rock in front of it**. `\u{1FAA8}` was laid out and
drawn as nothing. It is invisible to every property probe -- `.Text`, `.TextColor3` and `.TextFits`
all read correct -- which is why it took a screenshot to find and why a tripwire is half the row.

**Two bands are exposed in `Pets.lua`, 41 pets in total:**

* **10 pets at U+1FA70 or above** -- `Pebble`, `Cinder`, `Rustling` (U+1FAA8), `Scarab` (U+1FAB2),
  `Orbiton` (U+1FA90), `Echo` / `Reflekt` / `Inversal` (U+1FA9E), `Gasbub` / `Fluffle` (U+1FAE7).
  These are a LATER Unicode addition than U+1F300..1F9FF and the system emoji font here does not
  have them.
* **31 pets BELOW U+1F300** -- U+26A1, U+2728, U+2B50, U+2604, U+269B and friends. These are
  **text-presentation by default**: the renderer falls back to the display font, which is 27.7's
  exact fault. `Adventures.lua`'s own tripwire already warns about this band; `Pets.lua` asserts
  nothing.

**WHAT TO DO -- four things, and nothing else.**

1. **Replace every out-of-band `emoji` with an in-band one that still reads as the same creature.**
   The safe band is **U+1F300 .. U+1F9FF**. Keep the pet's identity: `Pebble` is a rock, so a rock
   from the safe band (U+1F5FB is a mountain, U+1F30B a volcano -- pick what reads, not what is
   nearest in code); `Sparky` at U+26A1 is lightning, U+1F329 is a cloud with lightning; `Scarab`
   is a beetle, U+1F41E is a lady beetle. **Do not reuse a glyph another pet already has** -- the
   icon layer is keyed BY EMOJI, so two pets on one glyph collapse to one icon.
2. **Write the tripwire.** Copy the SHAPE of `Adventures.lua` lines 496-506: a loop at the bottom of
   the file, `pcall(utf8.codepoint, pet.emoji, 1)`, `warn` naming the pet key and the codepoint when
   it is missing, non-numeric, or `< 0x1F300`. Add the **upper** bound too -- `> 0x1F9FF` is the
   band that caused half of this row and Adventures' check would not have caught it. One warn line,
   the pet key in it, the codepoint printed as `U+%X`.
3. **Add a comment block above the pet list** saying why the band is what it is. One paragraph. It
   is the most expensive line in a config file to lose.
4. **Change nothing else.** No renamed keys, no re-ordered tables, no colour edits, no reindenting
   (this file is one of the sixteen `GameConfig` parts, moved byte for byte -- its header says so).

**THE ENCODING RULE, AND IT IS THE ONE THAT CAN COST A DAY.** This file is UTF-8 and the icon layer
is keyed by the literal emoji bytes. Something run against this repo once rewrote 52 files as
mojibake (UTF-8 read as cp1252, written back) and **24 were not byte-reversible**. So:

* Read and write this file as **UTF-8 explicitly**. Never let a tool guess the codepage.
* After you write it, **re-read it and print the codepoint of all 149 `emoji` fields**. Paste that
  list. If any line shows a capital A-tilde or an a-circumflex followed by the euro sign -- the
  two tells of UTF-8 read as cp1252 -- you have already destroyed it:  and
  start again.
* `board.py sync` refuses a commit that carries mojibake markers. Do not work around the guard.

**WHAT YOU MUST REPORT, and every line of it is pasted output:**

* the before/after table: pet key, old codepoint, new codepoint, for **every** pet you touched
* the count of `emoji` fields in the file before and after (must both be **149**)
* `C:/Python313/python.exe tools/luastruct.py` clean
* the tripwire's output on a deliberately broken copy (set one pet to `"\u{26A1}"` in a scratch
  copy, show the warn line, then throw the scratch copy away) -- a guard nobody has seen fire is
  not a guard
* **Not verified:** the capture. You cannot take it -- Studio is mine, exclusively. Say so in that
  field and leave it to me; the row does not close without it.

**Your ceiling on this row is `[~]`.** Do not write `[x]` in `ROADMAP.md`. Do not touch
`ZoneBuilder`, `MainUI`, or anything in `ServerScriptService`.

---

## S16 | 33.9 was applied TWICE, and it left a duplicate top-level local in the one file with no registers to spare

- **Owner:** Gemini
- **Depends:** none
- **Note:** DISK-ONLY. Two line deletions and nothing else. Do not open Studio.
- **Check:** `ZoneBuilder.lua` contains exactly ONE `local WORLD_DENSITY` and exactly ONE
  `atmosphere.Density = WORLD_DENSITY`, `tools/luastruct.py` is clean, and `tools/luaregs.py`
  reports the same or a LOWER top-level local count for that file than before your edit.

**THE FAULT.** Roadmap row 33.9 (Atmosphere Density -> 0.18) has already been applied to
`src/ServerScriptService/ZoneBuilder.lua` -- and applied a second time on top of itself, so the file
now carries both lines twice:

```
2050  local WORLD_DENSITY = 0.18
2051  local WORLD_DENSITY = 0.18          <-- delete this one
...
2120      atmosphere.Density = WORLD_DENSITY
2121          atmosphere.Density = WORLD_DENSITY   <-- delete this one (note the wrong indent)
```

**WHY IT IS NOT COSMETIC.** `ZoneBuilder.lua` is 573 KB and is documented as sitting a couple of
registers away from not compiling at all (`GEMINI.md` section 7, prohibition 5). A duplicate
top-level `local` spends one of those registers to say a thing that was already said. The second
`atmosphere.Density` write is harmless at runtime and is the fingerprint of the botched patch: it is
how you know the edit ran twice, which is the thing worth recording.

**WHAT TO DO -- exactly this and nothing else.**

1. Delete line 2051 (the second `local WORLD_DENSITY = 0.18`).
2. Delete line 2121 (the mis-indented duplicate `atmosphere.Density = WORLD_DENSITY`).
3. **Do not change the value.** 0.18 is the number row 33.9 asked for; the row is not open on the
   value, it is open on the capture, which is mine to take.
4. Do not touch any other line of `ZoneBuilder.lua`. This step is the ONLY ZoneBuilder edit you are
   authorised to make in this batch.

**WHAT TO REPORT:** the two deleted lines quoted, `luastruct.py` clean, and `luaregs.py` for
`ZoneBuilder.lua` before and after. **Not verified:** the side-by-side fog capture at 620 studs --
Studio is mine, say so and leave it.

---

## S17 | 34.1 -- the Achievements panel is dead code written against a contract that does not exist, and a claimed title vanishes on rejoin

- **Owner:** Gemini
- **Depends:** none
- **Note:** DISK-ONLY. `MainUI` is at the 200-local cap -- prohibition 6 applies to every line you
  write in it.
- **Check:** `grep -rn "AchievementsPanel" src/` shows a `require` from `MainUI`; the panel reads
  `hud.getData()` and never `hud.currentData`; `hud.hudRefs` appears nowhere in it; it listens to
  `DataUpdate`; `AchievementService` re-applies the `WornTitle` attribute on join; `luastruct.py`,
  `luascope.py` and `luaremotes.py` all clean.

**THE STATE OF THE ROW.** 34.1 is `[ ]` in `ROADMAP.md` and the feature is ~90% written on disk and
committed: `GameConfig/Achievements.lua` (47 rows), `ServerScriptService/AchievementService.lua`,
`ReplicatedStorage/Modules/HUD/AchievementsPanel.lua`, `ServerMain:272` wires the service, and
`CombatClient:960-995` already draws a title over the head off the `WornTitle` attribute. **None of
it can run.** Six faults, every one verified on disk, in the order that matters.

**1. NOTHING REQUIRES THE PANEL.** Every HUD panel is built by a line in `MainUI` of the shape
`require(RS.Modules:WaitForChild("HUD"):WaitForChild("X"))(hudRefs)` -- there are ~20 of them
(`SwordPanel` 1463, `PetsGrid` 1639, `RelicsPanel` 2813, `SeasonPass` 3278, `EggShop` 4571 ...).
There is no such line for `AchievementsPanel`. And `MainUI:1123` says

```lua
local achievementsButton = columnTile("R", 5, "\u{1F3C6}", "Goals", UITheme.Color.Gold)
```

-- a tile that is declared and **never read again**. That is character-for-character the fault row
33.30 found on the Vanity tile: a button in the HUD that opens nothing.

**THE FIX, and copy it rather than inventing one.** `MainUI:1128-1140` is the cosmetics wiring that
33.26/33.30 wrote for exactly this problem: a lazy build inside an immediately-called function, the
built-panel handle doubling as the built-flag, then `toggleOnly`. Use the same shape for
`achievementsButton`, requiring `RS.Modules:WaitForChild("HUD"):WaitForChild("AchievementsPanel")`.
**Zero new top-level locals in MainUI** -- everything inside the IIFE, handles on `hudRefs`.

**2. IT READS A FIELD THAT DOES NOT EXIST.** `AchievementsPanel.lua:114` and `:147` read
`hud.currentData`. There is no such field. `MainUI:14` keeps the save in a **file-local**
`currentData` that is REBOUND on every push, and publishes the accessor `hud.getData` at `MainUI:41`
precisely because a value copy goes stale. `hud.currentData` is nil forever, so `refresh` returns on
its first line and every row would sit on its first-frame paint. Use `local data = hud.getData and
hud.getData()`, which is what `RelicsPanel:579` and every other live panel does.

**3. IT WRITES THROUGH A NIL.** `AchievementsPanel.lua:191-192` write
`hud.hudRefs.achievementsPanel` and `hud.hudRefs.refreshAchievementsPanel`. **`hud` IS `hudRefs`**;
`hud.hudRefs` is nil, so those two lines are a hard error *at build time* -- the panel would not
finish being built even once something required it. Write `hud.achievementsPanel` and
`hud.refreshAchievementsPanel`. The header comment of
`StarterPlayer/StarterPlayerScripts/UIComponents/CosmeticsPanel.lua` documents faults 2 and 3 as the
same pair found in that file; read it before you start, it will save you the reasoning.

**4. NO `DataUpdate` LISTENER.** The panel registers `refresh` and nothing ever calls it after the
first open, so a claim's own push cannot repaint the row that made it. Every other panel in this HUD
refreshes on that remote -- add the listener the same way `CosmeticsPanel` does.

**5. A CLAIMED TITLE DISAPPEARS ON REJOIN.** `AchievementService:74` sets the `WornTitle` attribute
inside `HandleEquipTitle` and **nowhere else**. `CombatClient:984` draws the plate off that
attribute. So the save keeps `data.WornTitle` correctly and the head is blank until the player
re-equips -- which is the row's own live check ("survives rejoin") failing before anyone tests it.
`CosmeticService:78-93` already has the restore shape (a `PlayerAdded` handler that waits for the
save, then re-applies the attributes). Copy the shape, **and do not copy its two bugs**: it also
misses any player who is already in the game when the handler connects (iterate
`Players:GetPlayers()` as well), and it hardcodes three attribute names where a loop belongs.

**6. THE PANEL DOES NOT SAY WHAT IT PAYS.** `AchievementsPanel:100-104` reduces every reward to the
word `"DNA"`, `"Gems"` or `"Title"`. A card must say what it actually pays (`GEMINI.md` UI rule 4,
and the Daily-board row it was written for): print `+1,000 DNA`, `+50 Diamonds`, or the title in
quotes -- `Title: "Slayer"` -- because the title's NAME is the entire reward and the panel currently
never shows it anywhere.

**THREE SMALLER ONES, in the same pass:**

* **Time rows are unreadable.** `TimePlayed` is lifetime **seconds** (`PlayerDataService:95` says
  so), so the four `Time_*` rows render `0 / 3.6K` and `0 / 360K`. Format a time counter as
  `1h` / `10h` / `50h` / `100h` and the progress as hours; leave every other counter on
  `formatNumber`.
* **The scrollbar is white on white.** `scroll.ScrollBarThickness = 6` with no
  `ScrollBarImageColor3` on a `PanelWhite` shell is an invisible bar. `Modules/HUD/ScrollAffordance`
  exists for this and was written by the sweep that found nine of these; use it.
* **The claim pays currency with no telemetry.** `AchievementService.HandleClaim` adds DNA and
  Diamonds and tells `Telemetry` nothing, while `CommunityGoalService:159-161` shows the exact call
  shape (`Telemetry.Economy(player, "Source", Telemetry.Currency.X, amount, newBalance,
  Telemetry.Tx.Y, tag)`). Phase 20's rule is that ONE wrapper is the only caller of AnalyticsService
  -- so route it through `Telemetry`, never through `AnalyticsService` directly, and pick an
  existing `Telemetry.Tx.*` key rather than inventing one; if none fits, say so and leave the call
  out rather than making a key up.

**WHAT YOU MUST NOT DO.** Do not add a top-level `local` to `MainUI`. Do not re-order or re-word the
47 rows in `Achievements.lua` -- the counters they name (`Kills`, `Rebirths`, `EggsOpened`,
`SecretsHatched`, `Fuses`, `MinigamesPlayed`, `ZoneFloorsCleared`, `TotalClicks`, `TimePlayed`) were
each checked against a live writer and all nine are real. Do not touch `ZoneBuilder`.

**WHAT TO REPORT:** the grep proving the panel is now required; the before/after of each of the six
faults as a two-line quote; `luastruct.py`, `luascope.py`, `luaremotes.py` clean; the top-level
local count of `MainUI` before and after (`tools/luaregs.py`) -- it must be **identical**.
**Not verified:** the capture, the live claim, and the second-client title. All three are mine.

---

## S18 | 34.2 -- the vanity layer sells three trails that nothing draws, and its equip lets a client name the attribute

- **Owner:** Gemini
- **Depends:** S17 (same HUD contract; do not fight yourself over `MainUI`)
- **Note:** DISK-ONLY. One of these is a security fault, so it is first.
- **Check:** `CosmeticService.HandleEquip` derives the type from the catalogue and never from its
  own argument; no `priceRobux` button is drawn while `productId == 0`; every `emoji` in
  `Cosmetics.lua` decodes inside U+1F300..U+1F9FF; `luastruct.py` + `luascope.py` clean.

**1. AN EQUIP CAN WRITE ANY ATTRIBUTE, INCLUDING ONE FROM ANOTHER FEATURE.**
`CosmeticService.HandleEquip(player, cosmeticType, cosmeticKey)` takes `cosmeticType` **from the
client** and concatenates it: `player:SetAttribute("Worn" .. cosmeticType, cosmeticKey)` (line 52).
Nothing checks it against the catalogue's own `type` field. So
`Remotes.CosmeticEquip:InvokeServer("Title", "Trail_Rainbow")` sets the attribute **`WornTitle`** --
which `CombatClient:984` draws over the head as a title -- from a 100-Diamond trail, and an arbitrary
string reaches `SetAttribute`'s name rules. **Fix:** look `cosmeticKey` up in
`GameConfig.Cosmetics`, use `config.type`, and never the argument. For the unequip branch (empty
key) accept only a type from a fixed allow-list built from the catalogue itself. The rule this
breaks is the one every service here already follows: the client names *what*, the server decides
*what that means*.

**2. THE HEADLINE ITEM IS INVISIBLE.** Grep for `WornTrail` across `src/`: the only hits are
`CosmeticService` writing it. `CombatClient` reads `WornNamePlate`, `EmoteClient` reads `WornEmote`
-- **nothing reads `WornTrail`**, and `Cosmetics.lua`'s `path = "Trails/Rainbow-01"` names an asset
that exists nowhere in the repo. So the 1,000-Diamond Galaxy Trail is a purchase that changes
nothing on screen. Two honest options, and you must pick one and say why in your log:

* **(a)** write the renderer: two `Attachment`s on the character plus a `Trail`, driven off the
  attribute the same way the name plate is, colours read from the catalogue row (add a
  `color`/`gradient` field -- a `path` string that points at no asset must not survive this step);
  or
* **(b)** delete the three Trail rows and say the vanity layer ships with plates and emotes only.

**(a) is the recommendation** -- trails are the cheapest visible cosmetic in the genre -- but **do
not invent an asset id for a trail texture** (prohibition 2). A `Trail` with a colour sequence and
no texture is a real trail.

**3. A GLYPH OUTSIDE THE SAFE BAND, in a file written after the row that established the band.**
`NamePlate_Dark` uses `\u{26AB}` -- U+26AB, **below U+1F300**, which is the exact class of glyph
that S15 / row 33.12 replaced across `Pets.lua` because the system font here renders it as
text-presentation instead of an emoji. Replace it from the U+1F300..U+1F9FF band with something that
still reads as a dark plate, and **add the same load-time tripwire** `Pets.lua` now carries (warn on
missing / non-numeric / below 0x1F300 / above 0x1F9FF, naming the key and printing `U+%X`). Read and
write this file as **UTF-8 explicitly** -- the mojibake rule from S15 is unchanged, and `board.py
sync` refuses a commit that carries the markers.

**4. A ROBUX BUTTON THAT CANNOT EVER TAKE A PAYMENT.** Every catalogue row carries `priceRobux`
with `productId = 0`. `CosmeticsPanel:127` draws `"R$ " .. c.priceRobux` and `:142` then refuses to
act unless `productId > 0` -- so the button is drawn and does nothing, on every row, forever. Worse:
even with a real id there is **no branch in `RobuxShopService.ProcessReceipt` that knows about the
cosmetics table**, so a paid purchase would charge and grant nothing. Until the owner creates the
products (that is a 👤 OWNER item, it is not yours -- prohibition 2):

* do not draw the Robux button at all when `productId == 0`; the Diamond button stays;
* write the `ProcessReceipt` branch behind the same `productId > 0` check so the wiring is ready,
  and grant by **key** with the already-owned test that `HandlePurchase` uses -- a receipt is
  retried and can land on another server (that is why every consumable in this game is a counted
  charge, not a moment);
* add a row to the 👤 Owner action checklist in `ROADMAP.md` naming the products that need
  creating. Append, never rewrite.

**5. TWO SMALLER ONES.** `HandlePurchase` spends Diamonds with no `Telemetry.Economy` call (same
shape as S17's telemetry item, `Sink` this time, not `Source`). And `CosmeticService.Init`'s restore
misses players already in the game and hardcodes three types -- fix it with the same loop S17 fault 5
asks for, in the same pass, since it is the same six lines.

**6. THE THREE EMOTE ANIMATION IDS ARE NOT VERIFIED AND YOU CANNOT VERIFY THEM.**
`507770239` / `507771019` / `507770677` are commented in the file as "placeholder catalog animation
ids". An animation only loads in this place if **Roblox** owns it, and that is a live test, in
Studio, which is mine. **Do not change them, do not add more.** List all three under *Not verified*
in your log and I will load-test them.

**WHAT TO REPORT:** the exploit fix quoted before/after; which option you took for the trails and
why; the before/after codepoint table for `Cosmetics.lua`'s nine emoji; the tripwire firing once on
a deliberately broken scratch copy; the lints. **Not verified:** the capture, the second-client
visibility, the three animation ids.

---

## S19 | 34.4 -- the community counter is a complete cross-server system that nothing has ever incremented

- **Owner:** Gemini
- **Depends:** none
- **Note:** DISK-ONLY, server-side. `CreatureService` and `BossService` are large; make the smallest
  possible edit in each.
- **Check:** `grep -rn "AddProgress" src/` shows at least two call sites outside the service; the
  service ignores its own `MessagingService` echo; `PlayerAdded` is armed inside `Init()`;
  `luastruct.py` + `luascope.py` clean.

**THE HEADLINE.** `CommunityGoalService.AddProgress(amount)` (line 140) has **zero callers**.
`CreatureService:27` and `BossService:27` both `require` the module and neither ever calls it. So the
counter is permanently 0, `PayoutAll` can never fire, and every other part of the feature --
`UpdateAsync`, the `MessagingService` topic, the window handling, the `GlobalKillsProgress`
NumberValue that `EventService:556` already reads -- is correct code wired to a dead input. This is
the shape to remember: **a counter nobody increments looks exactly like a feature that works.**

**WHAT TO DO.**

1. **Call it where the kill is already counted**, so the two numbers can never disagree:
   `CreatureService:3815` (`data.Kills = (data.Kills or 0) + 1`), `BossService:2493` and
   `BossService:2817`. One line each, immediately after the existing bump.
2. **Decide the boss weight and write the reason in a comment.** A boss already counts as one in
   `data.Kills`; if you weight it higher in the community counter the two boards stop agreeing.
   Default to **1** unless you can state why not.
3. **The publisher hears its own echo.** `MessagingService:SubscribeAsync` delivers a topic to the
   server that published it. The sync loop already folds the authoritative `UpdateAsync` return into
   `globalTotal` (line ~120) and then `onGlobalUpdate` adds the same delta *again* when the message
   comes back -- the total inflates by exactly this server's own contribution, which is worst on a
   single-server test, i.e. exactly how it will first be measured. Stamp the payload with
   `game.JobId` and drop your own; keep the `window` check as it is. Also type-check `data.delta`
   before adding it.
4. **`Players.PlayerAdded:Connect` is at module scope** (line ~170), outside `Init()`. It arms on the
   first `require`, which is `BossService:27` -- before `ServerMain:274` wires anything. Move it
   inside `Init()`, where every other service in this game arms its handlers.
5. **The join payout loses a slow save.** It does `task.wait(5)`, calls `PlayerDataService.Get` once
   and returns if nil -- so a player whose DataStore load is slower than five seconds silently never
   gets paid. Use the bounded `repeat ... until data` shape (`CosmeticService:80-87`), with a cap on
   the tries and a `warn` if it gives up.
6. **`GlobalGoalsClaimed` grows for the life of the save** -- one key per weekly window, never
   pruned, and it is not in `PlayerDataService`'s default table either. Add the default (`{}`, next
   to `AchievementsClaimed` at line 106) and prune to the newest 8 windows.
   `PlayerDataService.TrimCollection` (line 381) is the house shape for this: **read it before you
   use it**, it takes a label and it logs.
7. **Do not change `target = 5000000`.** Print the arithmetic instead: kills per player per hour
   times a plausible concurrent population times the 48-hour window, from numbers already in
   `GameConfig`. If it says the goal is unreachable, that is a finding for the owner, not a constant
   for you to move.

**WHAT TO REPORT:** the grep proving `AddProgress` now has callers, quoted with their line numbers;
the echo fix; the arithmetic from item 7 as actual numbers; the lints. **Not verified:** the
cross-server tick and the payout -- `MessagingService` cannot be exercised from Studio at all, which
is why the published test place exists, and that is mine to run.

---

## S20 | 34.5-34.8: four features were written to disk and NOBODY has ever read them back

- **Owner:** Gemini
- **Depends:** S17, S18, S19 (do those first -- they are the same defect shapes, and you will
  recognise them faster afterwards)
- **Note:** REPORT-FIRST. Fix only the mechanical class listed below; anything that changes
  behaviour is written up and left for me.
- **Check:** one table in `GEMINI-LOG.md` with a row per defect: file, line, defect, the one-line
  proof, and `FIXED` or `LEFT`. Every `FIXED` row must also show the lint that covers it.

**WHY THIS STEP EXISTS.** `ROADMAP.md` has 34.5, 34.6, 34.7 and 34.8 all at `[ ]` -- not started --
and all four already have code on disk:

| Row | What is on disk |
|---|---|
| 34.5 enchant transfer | `StarterPlayer/StarterPlayerScripts/UIComponents/EnchantTransferPicker.lua` + a transfer path in `PetService.lua` |
| 34.6 mobile gestures | `StarterPlayer/StarterPlayerScripts/MobileGestures.client.lua` |
| 34.7 weather | `ZoneBuilder.lua:1865 buildWeather(model, zone, cx)` + the `WeatherEmitter` part at `:1922`, called at `:2397` |
| 34.8 kill streak | `CombatClient.client.lua:1777 updateStreak()` |

Unreviewed code that a roadmap calls "not started" is the most expensive kind in this repo: nothing
will ever look at it again, because the row says there is nothing to look at.

**THE NINE SHAPES TO CHECK EACH FILE AGAINST.** These are the defects this project has actually
shipped, in the order they are cheapest to detect:

1. **Nothing requires it.** Grep the module name across `src/`. `HUD/PassShop` was unrequired for
   fifteen phases and 191 lines were rewritten inside it.
2. **The wrong HUD contract.** `hud.currentData` (does not exist -- it is `hud.getData()`) and
   `hud.hudRefs.x` (does not exist -- `hud` IS `hudRefs`). Both are silent.
3. **A remote created on one side only.** Run `tools/luaremotes.py`; it is the only lint that reads
   two files at once.
4. **A local used outside its scope, or above its own declaration.** Run `tools/luascope.py`. Two of
   the worst runtime bugs in this repo's history were exactly this and both compiled.
5. **A name that exists, just not here** -- `UITheme.Font.Sub` printed on every character spawn for
   a week and `UITheme.Font` has only `Body` and `Display`. Check every dotted field you did not
   write against the module that owns it.
6. **An invented id** -- asset, product, pass, animation. If you cannot show where it came from, it
   is invented; report it, never "fix" it by picking another.
7. **A counter nothing increments** (S19's headline) and its mirror, **a save field written but
   missing from `PlayerDataService`'s default table** (lines 79-107).
8. **A client string used as authority** (S18's headline).
9. **A guard nobody has seen fire.** If a file has a cap, a cooldown or a rate limit, show it firing
   once on a scratch copy, or say plainly that it is unproven.

**THE ONLY THINGS YOU MAY FIX IN THIS STEP:** shapes 2, 3, 4, 5 and 7 -- they are mechanical, they
have a lint or a grep behind them, and each fix is a line or two. **Shapes 1, 6, 8, 9 you REPORT**:
whether a dead file should be wired or deleted is a design call, an invented id is the owner's, and
an authority hole may need a remote's shape changed.

**AND `ZoneBuilder` IS OFF LIMITS IN THIS STEP** -- 34.7's `buildWeather` is read, measured and
written up, and **not edited**. S16 is the only ZoneBuilder change you are authorised to make, and
it is two deletions. Prohibition 5 stands.

**WHAT TO REPORT:** the table, and nothing rewritten to look tidier than it is. A row that says
`LEFT -- design call, here is the question` is worth more to me than a plausible fix I have to
re-derive. **Not verified:** every capture, every live measurement, both clients. Mine.

## S21 | 34.11 (Missing Forest PortalGate)
- **Owner:** Gemini
- **Depends:** none
- **Check:** 

Find where `PortalGate` went missing in Forest (door to zone 2) and restore it so `MapGateFlanks` can find it.

## S22 | 34.12 (ForestMapService Floating Props)
- **Owner:** Gemini
- **Depends:** none
- **Check:** 

Fix the discrepancy where `ForestMapService` orphans 39 props from the mountain cut but settles 0 back to the floor.

---

## S23 | The cosmetics screen splits into three places the owner asked for
- **Owner:** Gemini
- **Depends:** none
- **Check:** `tools/luastruct.py`, `luascope.py`, `luaremotes.py`, `luaregs.py` all clean; `MainUI` register count does NOT rise (it is at 149 of 200 and one more top-level local deletes the HUD); and every claim below answered with the grep that proves it

**DISK ONLY. No Studio, no captures, no Play.** Those are mine and I will run them against what you
write. Do not touch `ZoneBuilder`, `PetService`, `EnchantTransferPicker`, `Cosmetics.lua`,
`CosmeticService.lua` or `EvolutionVisuals` -- all six are mine this session and are being edited
right now. If you need a change in one of them, write the request into `GEMINI-LOG.md` and I will
make it.

### Where this comes from

Kristina's message, with a capture of the Vanity panel: *"ove trails trebaju biti negde odvojeno ...
a trails moze u shopu samo drugi panel za to, kao inventory sto ima potion pets i relics, e tako
trails ubaci i maceve spoji kao trecu opciju pa nek bude sve tu, emotes nek bude kao mala ikona pa
kad je kliknes otvori par vrsta emota ... a ovaj tag u boji nek bude negde sa titlom, posto se titl
moze dobiti to ima smisla da bude zajedno negde"*. She then chose the layout explicitly: **the
existing Inventory tab strip grows to five tabs.** That is decided; do not re-open it.

The one panel becomes three homes:

| What | Where it goes |
|---|---|
| **Trails** (5 of them, and they are the SPEED ladder now) | a new **Trails** tab on the Inventory strip |
| **Sword** ladder (today a HUD tile, `UIComponents/SwordPanel`) | a **Sword** tab on the same strip; the L5 HUD tile goes away |
| **Name Plates** | beside the **Titles** list in `HUD/AchievementsPanel` -- her reason: a title is earned, a plate is worn, they belong together |
| **Emotes** | their own small HUD icon that opens a short list. All three are FREE now |
| `UIComponents/CosmeticsPanel` + the Vanity HUD tile | **nothing is left in it** -- report whether to delete it or leave it unreachable. Do NOT delete it yourself |

### What you are building

1. **`InventoryTabs.lua` grows from three tabs to five.** Read its own header first: the strip is
   `3 * 112 + 2 * 8 = 352` inside a frame authored at 358, and the note at `:31` records that going
   from two tabs to three cost a width change *and* a per-tab shrink. Five tabs need that
   arithmetic done again, once, with the new numbers written into the comment the way the old ones
   are. The two new entries follow the existing `{ text = ..., target = ..., color = ... }` shape.
   **`target` must be a panel that already exists** -- the strip does not build panels, it swaps
   between them, and its `:19` note says the require order decides whether a tab silently loses its
   target.

2. **A Trails panel.** Build it on `UIComponents/ScrollingPanelBuilder` like every other list panel
   written this month -- `AdventurePetPicker` is the closest model. One card per row of
   `GameConfig.Cosmetics` whose `type == "Trail"`. Each card shows the trail's name, **its speed
   bonus (`speedPct`, "+N% walk speed")**, and one button that is:
   - `EQUIP` / `UNEQUIP` when `data.CosmeticsOwned[key]` -- fires `Remotes.CosmeticEquip`
   - the price otherwise -- `GameConfig.GetCosmeticPrice(c)` returns `amount, currency` and the
     currency for a trail is `"Shards"`, held in `data.EvolutionShards`. Fire
     `Remotes.CosmeticPurchase`.
   - greyed with the reason when it cannot be pressed. **Do not put the caption in
     `UIKit.styleButton`'s third argument -- that is a RADIUS** and it ate every price in the vanity
     shop four days ago (roadmap 34.22). Set `.Text` on its own line.

3. **The Sword tab points at `UIComponents/SwordPanel`**, which already exists and already builds
   itself on the same builder. Remove the L5 `swordButton` tile from `MainUI` and its click handler.
   **Removing lines from `MainUI` is safe; adding a top-level local is not.**

4. **Name Plates move into `HUD/AchievementsPanel`** as a second section under the titles, same card
   shape, priced in Diamonds (`GetCosmeticPrice` says so).

5. **Emotes get their own HUD icon** -- one small button, its own panel, three rows, all free
   (`GetCosmeticPrice` returns `0, nil`, and a nil currency means CLAIM-then-equip, not "refuse").
   `StarterPlayerScripts/EmoteClient` already exists and already walks the catalogue: read it before
   writing anything, and wire to it rather than around it.

### The traps that have caught this exact work before

- **`hud` IS `hudRefs`.** `hud.currentData` and `hud.hudRefs.x` do not exist; it is `hud.getData()`.
  Three panels shipped dead this month on that alone.
- **A panel that nothing requires is dead code**, and it looks identical to working code. Grep the
  module name across `src/` and paste the hit.
- **The builder's card labels are `CardTitle` / `CardSubtitle` / `CardDescription` inside a frame
  named `Text`.** Guessing those names is what drew the sword preview over its own card (34.17).
- **Check every dotted field you did not write against the module that owns it.** Fifth time.

### What to report in `GEMINI-LOG.md`

The five files you touched, the new tab arithmetic with the numbers, `MainUI`'s register count
before and after, and the grep that proves each new panel is required from somewhere. **Anything
you could not do, say so plainly and leave it undone** -- a row reading `LEFT: the emote icon has
nowhere on the HUD that does not collide with TileColumnFit, here is what I measured` is worth more
than a guess I have to unpick.
## S24 | DONE | 34.8 -- the kill streak is a local nothing assigns, and only ONE toast in the game groups
- **Owner:** Gemini
- **Depends:** none
- **Check:** `grep -n "updateStreak" src/StarterPlayer/StarterPlayerScripts/CombatClient.client.lua` shows an ASSIGNMENT and not only the declaration and the call; `tools/luastruct.py`, `luascope.py`, `luaregs.py`, `luaremotes.py` clean on every file you touch; `MainUI`'s register count unchanged at 148 of 200 (read it with `luaregs.py`, do not estimate); and every claim below answered with the grep that proves it

**DISK ONLY. No Studio, no captures, no Play.** Those are mine and I will run them against what you
write. Do not touch `TrailsPanel`, `EmotesPanel` or `InventoryTabs` -- I pushed all three into
Studio an hour ago and a disk edit under them puts the two copies out of step. Do not touch
`ZoneBuilder`. If you need a change in one of those, write the request into `GEMINI-LOG.md` and I
will make it.

### What is actually there, measured on disk today

Roadmap **34.8** reads *"a streak counter that decays, and the notify stack collapsing a burst into
one line"*. Half of it was written during S20, and neither half is finished:

| Piece | State |
|---|---|
| `CombatClient:26` `local updateStreak` | **declared and never assigned.** So `CombatClient:1778` `if kill and updateStreak then` is `if kill and nil then` -- dead on every kill since the day it was written, and it compiles, lints and reads as working code |
| `MainUI:3439` `showNotification(text, color, rank, groupId)` | the grouping IS built and it works -- it finds a live toast carrying the same `GroupId`, bumps a `Multiplier` attribute, rewrites `Body` to `"Nx <text>"` and pops it |
| callers passing a `groupId` | **exactly one in the whole game**, `kind == "diamond"`. Every other burst still stacks N separate toasts |

So this row is not "build a feature". It is **arm the one that exists and give the other one a
value**, and the interesting half is deciding *which* toasts group.

### What you are building

1. **Assign `updateStreak`.** It is called at `CombatClient:1778`, inside the kill branch of the FX
   handler. Read that whole block first: the note above it explains why the kill FX is deduped, and
   your counter must count KILLS, not FX frames. The streak is `+1` per kill and **decays to 0 after
   4 s with no kill** -- one `task.delay` guarded by a generation counter, never a per-kill timer. A
   burst of six kills must not leave six timers racing. Nothing here is server-authoritative: it is
   a number on one player's own screen and the server already pays the kill. **Do not add a remote.**

2. **Draw it where this game already draws combat feedback**, which is the world and not the screen
   centre -- that is the standing rule, and `CombatClient` already obeys it (the DNA pop is drawn
   over the corpse). A streak of 1 or 2 draws NOTHING. From 3 up it rides the existing kill pop as a
   second line (`3x STREAK`), climbing in weight, and it lives and dies inside `CombatClient`: **no
   new ScreenGui, and nothing in `MainUI`.**

3. **Give the burst toasts a `groupId`.** Walk the branch list under `Remotes.Notify.OnClientEvent`
   at `MainUI:4255` and pass a 4th argument on the kinds that ARRIVE IN BURSTS and say the same
   thing each time. `petDrop` is the obvious second one after `diamond`. **A kind carrying a name or
   a figure that differs per event must NOT group** -- `"5x NEW CHARACTER!"` would be a lie about
   five different characters. Write the list you chose into the log with one line of reason per
   kind, including the ones you deliberately left alone. Getting that list wrong is the whole risk
   in this step, and it is a judgement, not an arithmetic.

### The traps that have caught this exact work before

- **A `local x` with no assignment is invisible to every lint we own.** That is precisely what this
  row is. When you finish, grep your own new locals the same way: a declaration, an assignment, a
  use -- all three, by name.
- **`MainUI` is at 148 registers of 200 and one more TOP-LEVEL local deletes the entire HUD.** The
  helpers inside `showNotification` are nested for exactly that reason and the comment at :3425 says
  so. Anything you add in there stays nested.
- **A `task.delay` per event is how a decaying counter becomes six racing timers.** Guard it with a
  generation number, not with `if streak > 0`.
- **Check every dotted field you did not write against the module that owns it.** Sixth time.

### What to report in `GEMINI-LOG.md`

The files you touched; `MainUI`'s register count before and after, read with `luaregs.py`; the grep
showing `updateStreak` assigned; the list of kinds you gave a `groupId`, with the reason for each
and for each one you left ungrouped; and anything you could not do, said plainly and left undone.

## S25 | 33.11 (1.5) -- the currency readouts SNAP, and the count-up half was never built
- **Owner:** Gemini
- **Depends:** none
- **Check:** `grep -rn "CountUp" src/` returns the new helper plus its three call sites and NOTHING else; `tools/luastruct.py`, `luascope.py`, `luaregs.py`, `luaremotes.py` clean on every file you touch; `luaregs.py` says `MainUI.client.lua 148 registers` and `UITheme.lua` no more than 66 -- read them, do not estimate

**DISK ONLY. No Studio, no captures, no Play.** I own those and I will run them against what you
write. Do not touch `ZoneBuilder`. If you need a change in a file I have pushed, write the request
into `GEMINI-LOG.md` instead of making it.

### What is actually there, measured on disk today

Roadmap **33.11** lists eight polish items and names `guidelines/ui-research-2026.md` as the spec.
**Read section 1.5 of that file before you write a line** -- it carries the real defaults and the
two guards, and they are not guesses, they are lifted from a published module.

| Piece | State on disk |
|---|---|
| the pulse half | **built and correct.** `UITheme.Pulse` (UITheme:3066) jumps the shell, not the inner frame, via the `PulseHost` ObjectValue. `MainUI:3918/3921` already calls it for Diamonds and Shards |
| the count-up half | **does not exist.** `grep -rn "CountUp|countUp" src/` is **0 hits** |
| the three wallet pills | `MainUI:3913-3915` writes `dnaPill.Value.Text = formatNumber(data.DNA)` and the same for Diamonds and Shards -- a straight assignment, so 41.2K becomes 58.9K between two frames with nothing in between |

So this is not "build a feature". It is **the missing half of a pair whose other half already
works**, and the interesting part is the two guards, because this is a clicker: the DNA counter
moves several times a second and a naive count-up runs permanently behind the truth.

### What you are building

1. **`UITheme.CountUp(label, target, opts)`**, in `UITheme.lua`, near `UITheme.Pulse` so the pair
   reads as a pair. Not in `MainUI` -- that file is at 148 registers of 200 and a top-level local
   there is the most expensive thing in this repo. Signature and behaviour:
   - it animates the **text of one label** from the value it is showing to `target`, formatted with
     `UITheme.FormatNumber` unless `opts.format` gives another function;
   - **duration 0.5 s TOTAL, whatever the delta.** Not 0.5 s per 1000. Section 1.5 says so and the
     reason is in the same paragraph;
   - **re-target, never queue.** A second call while a spin is running cancels the first and starts
     from wherever the number stands. Two tweens writing one property is a bug this codebase has
     already paid for -- the comment at `UITheme:1589` is about exactly that collision;
   - **skip the spin when the delta is under 2% of the current value** and just write the text. A
     60-clicks-per-minute drip otherwise makes the number vibrate forever;
   - **`UITheme.ReducedMotion()` (UITheme:113) skips the spin entirely.** It is a player setting and
     it already exists; do not read `GuiService` yourself.
   - Easing **Quad/Out**, matching everything else in the kit.
   - **A tween cannot drive a string.** The idiom that fits this kit is a hidden `NumberValue` child
     tweened by `TweenService` with `GetPropertyChangedSignal("Value")` writing the text -- no
     `RunService` loop, and cancelling is one `:Cancel()`. If you pick something else, say in the log
     what and why.

2. **Route the three pills through it** at `MainUI:3913-3915`. Nothing else. The DNA card in the
   top-right and the damage readout are OUT of scope for this step -- they have their own owners and
   I do not want a fourth thing moving in the same capture.

3. **Leave `UITheme.Pulse` exactly where it is.** The pulse fires on a real increase; the count-up
   fires on any change. They are meant to run together (section 1.5: "count-up *and* pulse, not
   either/or"). Do not fold one into the other and do not make Pulse conditional.

### The traps that have caught this exact work before

- **`UITheme.FormatNumber` and `MainUI`'s `formatNumber` are two functions.** MainUI's is
  `UIKit.formatNumber` (`MainUI:65`). If your helper formats with one and the caller compares
  against the other, the label flickers between two spellings of the same number. Format in ONE
  place -- inside the helper.
- **The pill you pass is not the pill you see.** `UITheme.Pill` returns the inner content frame and
  hangs the capsule around it; that is what `PulseHost` at `UITheme:3082` is for. You are writing to
  `pill.Value`, a TextLabel, so this does not bite you here -- but do not "fix" it by walking up to
  `.Parent`.
- **A cancelled tween lands wherever the swing was.** Write the final value by hand after a cancel,
  the way `attentionStop` (UITheme:1611) does. A count-up that is interrupted must still end on the
  true number, always, or the wallet lies.
- **Check every dotted field you did not write against the module that owns it.** Seventh time.

### What to report in `GEMINI-LOG.md`

The files you touched; `luaregs.py` output for `MainUI` and `UITheme` before and after; the grep for
`CountUp` showing the helper and exactly three call sites; and the two guard numbers as you
implemented them (total duration, and the delta threshold) with the line each sits on. Anything you
could not do, say plainly and leave undone.

## S26 | DONE | 33.11 (2.5) -- there are TWO idle-pulse implementations fighting over one UIScale, and one of them is a global
- **Owner:** Gemini
- **Depends:** none
- **Check:** `grep -rn "_G\." src/` returns **0 hits**; `grep -rn "UITheme.Attention" src/` shows every claimable surface going through the kit; the four lints clean; `luaregs.py` says `MainUI.client.lua 148 registers`

**DISK ONLY**, same seam as S25.

### What is actually there, measured on disk today

The kit already owns this. `UITheme.Attention` (UITheme:1585 onward) is a **single global slot** with
a priority, a `pressMotion` suspend/resume pair, and a stop that writes `Scale` back to 1 by hand --
each of those three exists because of a specific bug, and the comment block above it names them. The
Daily Rewards **cells** use it correctly: `MainUI:2397` `UITheme.Attention(cell.frame, true,
{ priority = 2, peak = 1.03 })`, with the 1.03 justified by measured geometry at `MainUI:2391`.

**And then `MainUI:2432-2460` does the whole thing again by hand on the reward BUTTON.** Read that
block. It has five faults and every one of them is a rule the kit block above it already states:

| Fault | Why it matters |
|---|---|
| `_G.RewardPulseTween` | the **only** `_G` in all of `src/` (four references, all in this block). A client-wide global holding one tween handle |
| `if not _G.RewardPulseTween then _G.RewardPulseTween = t end` | if a handle is already stored, the NEW tween is played and never stored -- so it can never be cancelled. An infinite tween orphaned for the session |
| it bypasses the kit's one slot | so the HUD tile and a Daily cell can pulse **at the same time**. Section 2.5 says at most one pulsing tile on screen, and the kit enforces it -- this block opts out |
| it bypasses `attentionSuspend` | every HUD tile is a `pressMotion` surface, so hovering this button puts the hover tween and an infinite reversing tween on the same `UIScale` in the same frame. That is the exact collision `UITheme:1589` describes |
| `game:GetService("TweenService")` and `("GuiService")` inside the refresh body | this function runs on every `DataUpdate`. Services are cached at the top of the file everywhere else in this codebase |

### What you are building

1. **Delete the hand-rolled block and call the kit**: `UITheme.Attention(rewardButton, canClaim,
   { priority = <n>, peak = <p> })` in the true branch and `UITheme.Attention(rewardButton, false)`
   unconditionally in the else, matching the shape at `MainUI:2396-2400` and for the reason its
   comment gives (turning it OFF is the half that matters).
2. **Pick the priority deliberately and say why in the log.** The Daily cell is priority 2. A HUD
   tile and the cell inside the panel it opens are the same news told twice -- decide which one wins
   when both are claimable, and write the reason down. This is the judgement in this step; the code
   is ten lines.
3. **Pick the peak deliberately too.** The kit's default is 1.05, the Daily cell uses 1.03 because
   its cells are anchored (0,0) and all growth goes down-right into an 8 px gutter. **Measure the
   reward tile's own anchor and its neighbours' gap before you choose** -- if it is a column tile in
   the HUD grid, the same arithmetic applies and the answer is probably not 1.06 (what the deleted
   block used). Show the arithmetic.
4. **Then sweep for the others.** `screenGui.GiftsButton.Badge` and the mastery badge
   (`MainUI:1221`, `masteryBadge`, deliberately nil -- read the comment at :1219 before touching it)
   are the other claimable markers. For each one, either wire `Attention` or write one line saying
   why not. Do not add a pulse to a tile that is claimable most of the time -- an attention-getter
   that is always on is decoration, not attention.

### The traps

- **`masteryBadge` is nil on purpose.** :1219 explains it. If you assign it you have changed a
  behaviour nobody asked for.
- **Cancelling an infinite reversing tween does not return the scale to 1.** `attentionStop` writes
  it back by hand and says why. Whatever you delete, do not delete that.
- **One `UIScale` per GuiObject** and Roblox does not promise which one it honours. Use the kit's
  `scaleOf` path (it names the child `Scale`), never `Instance.new("UIScale")` beside an existing one.

### What to report in `GEMINI-LOG.md`

The `grep -rn "_G\." src/` output proving 0; the priority and peak you chose with the arithmetic
behind the peak; the list of claimable surfaces you swept, each with wired-or-why-not; and
`luaregs.py` for MainUI before and after.

## S27 | DONE | 33.11 (5.3) -- MEASURE FIRST: does a shrunk panel actually swamp itself with its own outline
- **Owner:** Gemini
- **Depends:** none
- **Check:** the measurement table below exists in `GEMINI-LOG.md` with real numbers before any file changed; if the measurement says nothing qualifies, **that is a complete step and you change nothing**

**DISK ONLY.** This one is deliberately shaped as a measurement with an optional edit, because the
edit is a visual change across 74 stroke sites and I do not want it made on a hunch.

### The claim to test

`guidelines/ui-research-2026.md` section 5.3: `UIStroke.StrokeSizingMode` is new since 4 Dec 2025.
`FixedSize` (the default, and what every stroke in this game uses -- `grep -rn "StrokeSizingMode"
src/` is **0 hits**) keeps pixel thickness, so a 5 px outline on a panel that `registerPanel` has
`UIScale`-fitted down to 0.35 on a phone stays 5 px on a panel that is now a third the size.
`ScaledSize` makes Thickness a **percentage of the parent's shortest axis** instead.

`MainUI:807` builds one `UIScale` per panel and `MainUI:881` reads it back. **That fit is real and it
is the whole premise of this step.**

### Step one -- the measurement, and it may be the whole step

For the **five widest panels** (find them; the Journal at 968 is one), report a row per panel:

| Panel | authored W x H | UIScale at a 1280x720 viewport | UIScale at a phone viewport (say 640x360) | shell stroke thickness px | effective px after the fit | that as a % of the shortest axis |

The fit factor comes from reading `registerPanel`'s own arithmetic, not from guessing -- and say
which lines you read it off. **If the effective thickness never rises above about 4% of the shortest
axis, the outline is not swamping anything and the right answer is to change nothing.** Write that
conclusion in the log and stop; a measured "no" closes this step exactly like a "yes" does.

### Step two -- ONLY if the measurement says yes

Change `StrokeSizingMode` **only on the panel shell strokes**, converting each thickness with
`thickness_px / shortest_axis_px` at the AUTHORED size, so the desktop rendering is unchanged to the
pixel and only the shrunk case moves. Report the before/after number for every site you touch. Do
not sweep the 74 sites; do not touch badge, pill, tile or card strokes; do not touch anything in
`ZoneBuilder`, `ZoneKit` or any server file -- world-space strokes have no `UIScale` over them and
nothing in this section applies to them.

### Two facts from the same source, so nobody spends an afternoon on them

- **`BorderOffset` cannot give you a drop shadow.** Custom border positioning does not produce an
  offset shadow; the duplicate offset frame stays.
- **`LineJoinMode` is inert here.** With `UICorner` present -- and every panel has one -- the corner
  overrides it. Do not set it.
- Keep the whole screen under **300** UIStrokes; if your change adds any, it is the wrong change.

### What to report in `GEMINI-LOG.md`

The table, in full, with the lines you read the fit off. Then either the sentence "measured no, no
files changed" or the before/after list. **A guess in this table is worse than an empty table** --
if you cannot get a number, name the number you cannot get.

## S28 | DONE | 22.1 -- the friends-in-server bonus, and the one income multiplier it has to join
- **Owner:** Gemini
- **Depends:** none
- **Check:** `grep -rn "IsFriendsWith" src/` shows the new service beside the two existing call sites and nowhere else; the four lints clean on every file touched; `luaregs.py` says `MainUI.client.lua 148 registers`; and the ordering decision, the cap and the offline decision each answered with the line they sit on

**DISK ONLY. No Studio, no captures, no Play.** Those are mine. Do not touch `ZoneBuilder`,
`MainUI`'s top-level scope, `TrailsPanel`, `EmotesPanel`, `InventoryTabs`, or `AchievementService`
(that last one is under review in S17 and a second writer in it will collide).

### The row

Roadmap **22.1**: *"Friends-in-server bonus -- +X% DNA per friend present, capped, drawn as a live
HUD pill that says how many and how much"*. Phase 22 is co-play and this is its cheapest rung: it
costs no art, no product id and no owner action, and it pays a player for the thing the whole phase
is trying to cause.

### What is already on disk, measured today

| Piece | Where |
|---|---|
| the friend count, already written once | `Telemetry.lua:530-548`. **Read this whole block before you write a line.** It is the pattern: `IsFriendsWith` is a web call **per pair**, so it runs off the join thread in a `task.spawn`, every call is `pcall`ed, and it is done ONCE per join with a count rather than once per friend |
| a client-side count, unused for anything but a caption | `UIComponents/FriendInviteButton.lua:10-19` `getFriendCount()` |
| the single income multiplier | `DNAService.GetIncomeMult` (`DNAService:13`). **Every** DNA the game pays -- clicks, kills, idle auto-collect, offline -- goes through this one function |
| the way a server-computed figure reaches the HUD with no new remote | `DNAService:696` stamps `data.__autoPerSec = amt` and `PushToClient` carries it in the payload it already sends. The comment above it explains why the client must not recompose the number itself |
| a bonus term with the same shape, already in the chain | `DNAService:54-56`, the group bonus: `if data.InGroup then mult = mult * (GameConfig.GroupIncomeMult or 1.10) end` |

**Nothing anywhere pays a friend bonus.** `grep -rn "FriendBonus" src/` is 0 hits.

### What you are building

1. **A new server module** -- `FriendBonusService` or a name you can defend; **not** `SocialService`,
   which is a Roblox service name and shadowing it in a require would be a bug that only shows up
   the day somebody uses the real one. It owns a map from UserId to a friend count and keeps it
   current. Init it from `ServerMain` beside the other services (see the block at `ServerMain:153`
   onward for the order and the style).

2. **The term in `DNAService.GetIncomeMult`.** Three decisions, and each one has a right answer that
   is already argued somewhere in that function's own comments -- read them, then write yours:
   - **Where in the chain.** The stated convention is earned-before-bought: passes sit late so a
     bought multiplier applies to everything above it, the wardrobe after the pass, events last.
     A friend bonus is earned and free. Place it and say why in one line of comment.
   - **The cap.** The row says capped. Pick the per-friend percent and the ceiling, and justify them
     against a number already in the file -- the group bonus is +10% flat, the zone bonuses are a
     percent sum, `MegaIncome` is a percent per level. A bonus that beats a Robux pass for free is
     the wrong answer and so is one nobody notices.
   - **The offline payout.** `excludeEvents` has exactly ONE caller, `OfflineService`, and the
     comment at `DNAService:213` says exactly why: the offline payout multiplies this rate by up to
     eight hours of ABSENCE. **A friend who is in the server right now was not there while the
     player slept.** Decide what the offline path does with this term and make the code say it.

3. **The live count, and the trap that will get you.** The map must update when a friend **joins**
   and when one **leaves**. `PlayerRemoving` **does not unparent the player** -- measured, it is in
   the notes -- so `Players:GetPlayers()` inside that handler **still contains the person who is
   leaving**. Recount after they are gone, or subtract them explicitly. Getting this wrong leaves
   every remaining player paid for a friend who is not there, forever, until they rejoin.
   Also: never call `IsFriendsWith` in a loop on a hot path. It is a web call.

4. **The readout.** Do **not** add a fourth pill to the currency stack (`MainUI:391-405`) -- that
   stack's geometry is measured and `MainUI` is at 148 registers of 200. The surface that is already
   about friends is `FriendInviteButton`, and it already counts them. Put the live number and the
   live percent there, fed by the server's stamped figure (the `__autoPerSec` pattern above), not by
   the client's own `getFriendCount` -- two counts that can disagree is the bug, not the feature.

5. **While you are in that file, it never got a shell.** `FriendInviteButton.lua:24-38` builds a raw
   `ImageButton` with `btn.Image = ""` and a comment reading `-- REPLACE WITH UPLOADED ICON`, plus a
   hand-rolled `UICorner` and `UIStroke` instead of going through the kit. Every other surface in
   this game is `UITheme`. Give it the same treatment the rest of the HUD gets, and either give it a
   real icon through `IconLibrary` or a glyph -- an empty `Image` renders as nothing at all.

### The traps

- **`IsFriendsWith` yields and can throw.** Every call in `pcall`, off the join thread, exactly as
  `Telemetry:538` does it.
- **Do not put the friend count in the save.** It is a live fact about right now. A save field would
  pay a player forever for a friend who logged off in June.
- **Two players, one pair.** If you count from both sides on every join you will double-count or
  race. `Telemetry:533` explains the choice it made and why; make yours and say it.
- **Check every dotted field you did not write against the module that owns it.** Eighth time.

### What to report in `GEMINI-LOG.md`

The files; the three decisions (position in the chain, the cap arithmetic, offline) each with the
line number; the leave-path handling with the line that proves the leaver is excluded; `luaregs.py`
for `MainUI` before and after; and the four lints. Anything you could not do, plainly, left undone.

## S29 | 22.2 -- the invite button opens a prompt and nothing has ever been paid for it
- **Owner:** Gemini
- **Depends:** S28
- **Check:** a joiner arriving with launch data pays BOTH sides exactly once, proven by a table in the log of what the save held before and after; a second join on the same pair pays nothing; the four lints clean

**DISK ONLY.** Same seam.

### The row

Roadmap **22.2**: *"Invite reward -- `FriendInviteButton` already opens the prompt. **Pay for the
join, not the click**, and pay both sides"*. The emphasis is the whole row. A reward for pressing a
button is a reward for pressing a button; the thing worth paying for is a person who actually
arrived.

### What is on disk

`FriendInviteButton.lua:74` is the entire feature: `SocialService:PromptGameInvite(Players.LocalPlayer)`.
`grep -rn "LaunchData\|GetJoinData" src/` is **0 hits** -- nothing anywhere reads who invited whom.

### What you are building

1. **Carry the inviter through the invite.** `SocialService:PromptGameInvite` takes an optional
   `ExperienceInviteOptions` whose `LaunchData` is a string that arrives with the joiner. Put the
   inviter's UserId in it. **Look the API up before you write it** -- if the shape is not what this
   paragraph says, follow the API and say so in the log; do not bend the code to match my sentence.
2. **Read it on the join.** The joiner's `player:GetJoinData().LaunchData`. Validate it: it is a
   string a client can put anything into, so parse it as a number, refuse anything else, and refuse
   an inviter who is the joiner.
3. **Pay both sides, once per pair, ever.** A save field on the inviter listing the UserIds they
   have been paid for, and a flag on the joiner saying they have been paid as a joiner. Two separate
   facts -- one of them is per-pair and one is per-account.
4. **The anti-abuse half, which is the real work.** Alt accounts are the failure mode of every
   referral system ever shipped. At minimum: a cap on how many invites one account is ever paid for,
   and a reason to believe the joiner is a person -- account age is the usual lever and it is
   readable (`Player.AccountAge`, in days). Pick the numbers, write them as named constants in
   `GameConfig`, and put the reasoning in the log. **If you cannot defend a number, say so and leave
   the constant at a deliberately conservative value.**
5. **What the reward IS.** Not DNA -- DNA is stage-scaled and means nothing across two players at
   different stages. The roadmap's own note under 34.4 says the exclusive-pet shape is the reward to
   use here. Diamonds and Evolution Shards are the two currencies with a fixed meaning; a pet is a
   better story. Choose, price it against something already in the game, and say what you compared
   it to.
6. **Tell the player.** Both sides get a `Notify` with the group rules S24 is already changing -- if
   S24 is not merged yet, use the existing call shape and do not invent a new one.

### The traps

- **A save field that only ever grows is a save-size bug.** The inviter's paid list is bounded by
  the cap in point 4; make the cap enforce the bound, do not let the list grow first and check after.
- **`GetJoinData` is empty for a normal join.** Every path through this code must be a no-op for the
  player who simply pressed Play on the game page, which is almost everybody.
- **Never trust a client-supplied number as an identity.** The LaunchData is client-influenced.
  It names a *candidate* inviter; the server decides whether that candidate gets paid.
- **Do not write to another player's save through a stale table.** `PlayerDataService.Get` is the
  only door, and the inviter may be offline -- decide what happens then and say it. "Pays on their
  next login" is a legitimate answer if you implement it; silently dropping it is not.

### What to report in `GEMINI-LOG.md`

The API shape you actually used with the doc line you read it off; the two save fields and where
they are initialised for an existing save; the anti-abuse constants with the reasoning; a
before/after table of both saves across one paid pair and one refused repeat; and the four lints.

## S30 | The remotes lint reports BAD on a healthy game, and that is how a lint stops being read
- **Owner:** Gemini
- **Depends:** none
- **Check:** `C:/Python313/python.exe tools/luaremotes.py` reports **0 unreachable remotes** with no rule loosened -- proven by a deliberately broken test case that it still catches

**TOOLS ONLY. Do not touch anything under `src/` in this step.** That is what makes it safe to run
beside the others.

### What is wrong

```
BAD 2 unreachable remote(s) of 83 resolved:

  MinigameFinish -- the server listens for it and NO CLIENT EVER FIRES IT
      src/ServerScriptService/MinigameService.lua:495
  StationFinish -- the server listens for it and NO CLIENT EVER FIRES IT
      src/ServerScriptService/ExpeditionService.lua:1020
```

**Both are false.** `MinigameUI.client.lua:1117-1120` fires both of them:

```lua
local finishRemote = finished.channel == "expedition"
    and Remotes.StationFinish
    or Remotes.MinigameFinish
finishRemote:FireServer({ token = finished.token, score = math.floor(finished.score) })
```

The lint looks for `Remotes.<Name>:FireServer(`. Here the remote is put in a **local** first and
fired through that local one line later, and the comment above it explains that this is deliberate
design -- it is the single cleanup-and-submit path and the channel decides which server owns the
result. So the code is right and the tool is wrong.

**Why this is worth a step and not a shrug:** `luaremotes.py` is one of the four lints every claim
in this repo is checked with, and roadmap **34.41** and **34.42** were both found by it -- a remote
nothing could fire, and an expedition with no exit. A tool that prints BAD on a healthy tree is a
tool people learn to skip, and the next real dead remote goes out with the noise.

### What you are building

Teach the resolver to follow a remote through a **local assignment in the same file**: when a local
is assigned an expression containing `Remotes.<Name>` -- including the `cond and A or B` form above,
which yields TWO names from one assignment -- then a `:FireServer(` on that local counts as a fire
of every name in it.

Keep it a text scan; do not write a Lua parser. Scope it deliberately and write the scope into the
tool's own docstring: same file, local assigned once, name used as `<local>:FireServer(`. Anything
you cannot resolve stays reported -- **a lint that resolves too much is worse than one that resolves
too little**, and the tool's own header already says the compiler wins whenever the two disagree.

### Prove it still bites

A fix to a detector is only worth what its false-negative test says. Before you claim this:

1. run it on the tree and paste the `0 unreachable` line;
2. **temporarily** comment out the `finishRemote:FireServer(...)` line in a scratch COPY of the file
   (not in `src/`), point the tool at it, and show that it reports `MinigameFinish` and
   `StationFinish` again;
3. paste both outputs in the log.

If you cannot build the negative test without editing `src/`, say so and stop -- do not edit `src/`
for it. Reverting a temporary edit is exactly how an unrelated change ships.

### What to report in `GEMINI-LOG.md`

Both tool outputs verbatim, the negative test and how you built it without touching `src/`, and the
scope sentence you added to the docstring.
