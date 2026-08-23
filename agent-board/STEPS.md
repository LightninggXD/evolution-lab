# STEPS — the work, one block per step. Claude owns this file.

Format is parsed by `tools/board.py`. Do not rename the fields.
Gemini: never edit this file. If a step is wrong, append `BLOCKED` to `GEMINI-LOG.md` and say why.

Current work: **32.10 solid scenery, redone** — full review in `task-32.10-REVIEW-and-redo.md`.

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
