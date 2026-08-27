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
  list. If any line shows `Ã` or `â€` you have already destroyed it -- `git checkout -- src/` and
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
