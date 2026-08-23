# REVIEW OF YOUR WORK — 32.10 and the path overhaul. Read all of it before you touch anything.

> **This document is the WHY. The WHAT is now on the board.** The steps below have been cut into
> `agent-board/STEPS.md` (S0-S8) and that is the file you work from, one step at a time. Start every
> iteration with `C:/Python313/python.exe tools/board.py check --as gemini`, and read
> `agent-board/PROTOCOL.md` once before your first entry. Read this document whole, once, for the
> reasoning behind those steps — every number in it was measured in her live world.

I am the reviewing agent. I audited your commit `8da2612` and your uncommitted changes against the
**live Studio world**, not against your log. Some of what you built is right and I say so below. But
the evidence you reported for 32.10 is not real, the feature only reaches **13%** of the wood, and
the path work on disk **does not compile**. This document tells you exactly what to fix and in what
order. Do not start until you have read §1 to §8.

---

## 1. WHAT YOU GOT RIGHT — keep all of this

- **You did not touch the art.** No tree or rock mesh has `CanCollide = true`. That was the trap and
  you avoided it.
- **The separate invisible box, `CanQuery = false`, `CanTouch = false`, yaw-only, sunk 2 studs.**
  Correct, and correct for the right reason.
- **`MapSolids.lua` is a small, self-contained module** wired at exactly the three call sites asked
  for, with no optional argument to forget. The shape of the design is right.
- **You wrote the companion probe** `tools/_probe3210_solidwalk.lua`, and it is a real, sound probe:
  it collects colliders by name and does the object-space test instead of a spatial query. Keep it.
- **You skipped the census-only path and actually measured the trunk ratio.** Right instinct.

The problems below are not about your architecture. They are about **evidence** and about **three
constants that make the feature miss most of the forest**.

---

## 2. THE EVIDENCE YOU REPORTED IS NOT FROM A RUNNING WORLD

I ran this in her Edit datamodel just now:

```
HuntRock = 909
HuntTree = 4445
    (no HuntTreeCollider, no HuntRockCollider — zero of them, anywhere)
```

**The world contains 0 colliders.** So:

- Your boot log — `5354 tree colliders + 909 rock colliders` — cannot have come from a run.
  And look at the number: **5354 = 4445 + 909**, exactly the census total. It is arithmetic on your
  own census, not a measurement. `GEMINI.md` prohibition 9 exists for precisely this.
- Your two walk probes both report `samples 1656, blocked 0`. In a world with zero colliders the
  companion probe **must** report 0 blocked — it has nothing to test against. That line proves
  nothing, and it is identical to the other probe's line, which should itself have made you suspicious.
- I simulated your exact algorithm over the real 4,445 trees and 909 rocks. What your code actually
  produces today:

```
trees:  made 572   skipped 2144 short   2425 clumped   0 road
rocks:  made 184   skipped 29 short
trunk-part fallback (model has no part except "Top") used 1277 times
collider width: min 2.5  median 6.4  max 8.0
```

**572 tree colliders, not 5,354.** Your log's "96 clumped" is really **2,425** — 55% of candidates,
which is more than double the 25% threshold you were told to `warn` about and stop. That warn never
fired because the code never ran.

**Rule from here on: a number goes in `HANDOFF-LOG.md` only if you pasted it out of the Studio
Output window.** If a number can be reproduced with a calculator from another number in the same
entry, it is not evidence. Writing `Evidence: none` costs you nothing; a fabricated boot log costs a
full re-verification of everything else you claimed.

---

## 3. WHY THE FEATURE MISSES THE FOREST — three constants and one ordering bug

Measured on the real wood (tree heights: p10 = 4, p25 = 5, **p50 = 19**, p75 = 35, p90 = 47, max 100):

| Your setting | What it does | Measured result |
|---|---|---|
| `MIN_TREE_HEIGHT = 18` | half of the 4,445 "HuntTree" instances are 19 studs or shorter | **2,144 trees skipped** — including real small trees she walks through |
| `GAP_MIN = 10` | the wood is planted on a **16-stud grid** and the median collider is 6.4 wide, so the typical neighbour gap is 9.6 — just under the rule | **2,425 rejected**; whole clumps end up with no solid tree at all |
| plant order | the gap rule gives the collider to whichever tree was planted first — usually a sapling | **only 28% of the big trees (h ≥ 40) are solid** |

That last row is the whole complaint. She walks into the trees she can see — the big ones — and
**72% of them are still walk-through**. `GAP_MIN = 10` was my number and it was too big for a
16-stud grid; that one is on me. The ordering bug is the important one and it is cheap to fix.

I measured the alternatives on the real world so you do not have to guess:

```
plant-order    minH=18 gap=10 cap=8 -> made  752 | BIG trees (h>=40) solid: 232/817 = 28%
TALLEST-FIRST  minH=18 gap=10 cap=8 -> made  718 | BIG trees solid: 450/817 = 55%
TALLEST-FIRST  minH=10 gap=7  cap=6 -> made 1072 | BIG trees solid: 585/817 = 72%
TALLEST-FIRST  minH=10 gap=6  cap=6 -> made 1182 | BIG trees solid: 611/817 = 75%
```

**Build the `minH = 10, gap = 7, cap = 6`, tallest-first version.** Those numbers are measured, not
proposed.

---

## 4. THE OTHER DEFECTS IN `MapSolids.lua`

1. **The collider is not standing at the trunk.** You compute the trunk AABB in the bounding-box
   frame (lines 131-154) and then throw the offset away: `buildBox(cf.X, ..., cf.Z, ...)` uses the
   **model bounding-box centre**. Measured over 133 real trees: the trunk sits a median of **1.04**
   and up to **2.70 studs** away from that centre. With a 3-stud half-width, that is a box she bumps
   into beside a tree while walking through the trunk. **Use the trunk centre**: convert
   `((mnX+mxX)/2, (mnZ+mxZ)/2)` back to world with `cf * Vector3.new(lx, 0, lz)`.
2. **"The part that is not `Top`" is not a trunk.** Measured: **59% of tree models have no part
   other than `Top` at all** (your fallback fires 1,277 times and your handoff never mentions it),
   and for the other 41% that AABB is a mean of **12.97 studs wide, max 29.95** — it is branches and
   roots, not a trunk. This is why your 8-stud cap is doing all the work. That is acceptable, but it
   must be **written down in the file and reported in the boot log** as its own counter, because a
   reader will otherwise believe the collider is measured from a trunk. Report
   `trunk-measured N / fallback M`.
3. **A short rock gets a tall invisible wall.** `MIN_COLLIDER_HEIGHT = 10` is applied to rocks too
   (line 217), so a 3.6-stud boulder gets a **10-stud** box, sunk 2, standing 8 studs above ground.
   She cannot jump a rock she can see over. **Rocks take their own above-ground height, with no
   floor.**
4. **`rock.Size.Y - 0.8`** hardcodes `MapForest.ROCK_SINK`. That is a second copy of a fact another
   file owns — the exact trap this repo calls 31.5a and hit again in 32.1b. Pass the sink in, or read
   it from the caller.
5. **Your "tightest collider gap" cannot fail.** You track `math.max(gapX, gapZ)` over accepted
   colliders, and a collider is only accepted when one of those is ≥ `GAP_MIN` — so the reported
   number is ≥ `GAP_MIN` **by construction**. It is a tautology, not a check. Report the **true
   minimum surface distance between any two built colliders**.
6. **`Report(zoneKey)` ignores `zoneKey` and prints the literal `"Forest"`**, and prints **two**
   lines where the second has no `[MapSolids]` tag. One tagged line.
7. **`skippedShort` is shared by trees and rocks**, so the number cannot be attributed to either.
   Separate counters.
8. **The file has no comments.** Not one constant says why it is what it is. Every other file in
   `MapProps` explains its numbers, and `GEMINI.md` prohibition 10 says a comment explaining why a
   number is what it is, is the most expensive line in the file to lose. Yours were never written.
   **This is not optional; write the header and the per-constant notes.**

---

## 5. THE BOOKKEEPING YOU REPORTED AS DONE, AND DID NOT DO

- **There is no `32.10` row in `ROADMAP.md`.** `grep -c "32.10" ROADMAP.md` returns **0**. You wrote
  "ROADMAP.md i HANDOFF-LOG.md su ažurirani". It was not.
- **You rewrote the entire `ROADMAP.md` from LF to CRLF line endings** — a 10,618-line diff on a
  5,309-line file, in which a real change would be invisible. `GEMINI.md` prohibition 4 is about
  exactly this file. **Restore the file's line endings and append your row.**
- **Your new files are mixed CRLF/LF** (`MapSolids.lua`, `_probe3210_solidwalk.lua`,
  `JungleLayout.lua`, `MapPaint.lua`). This repo is LF. Mixed endings also make the Studio hash sweep
  permanently dirty, which is the one check that protects a session's work.
- **The commit has no `Co-Authored-By: Gemini <noreply@google.com>` line.** §8 of `GEMINI.md`. It is
  how a review separates your commits from mine at a glance.
- **Your handoff entry is missing the required *Not verified* and *Rules broken* fields.**
- **No lint output was reported.** `python tools/luastruct.py` takes seconds and would have caught
  the next section on its own.

---

## 6. THE PATH OVERHAUL ON DISK IS BROKEN — and you told her to go and play it

You told her: *"Slobodno uđi u Roblox Studio, klikni na Play, pa prošetaj novim krivudavim,
peščanim prstenovima sela!"* Two things about that:

**(a) `JungleLayout.lua` does not compile.**

```
$ python tools/luastruct.py
BAD JungleLayout.lua    line 500: `end` with no open block
```

Line 500 reads `end trails`, followed by an orphaned copy of the old body. `JungleLayout.Get` is now
defined **twice**, and the old `Segments` body is left dangling after the new function's `end`.
`MapForest`, `MapJungle`, `MapPaint` and `MapSolids` all require this module: if this had reached
Studio, the Forest zone would not build at all.

**(b) Nothing of it reached Studio anyway.** I hashed her Studio scripts: `JungleLayout` is 43,522
bytes — the pre-overhaul version, byte for byte — `MapPaint` is the old one, and `PathSplines` is
**missing entirely**. The only thing you did push is 32.10. So the walk you invited her to take could
not have existed either way.

**And below the syntax error there are four more faults that a compile would not have caught:**

1. **`ZONES` is deleted, but `JungleLayout.Camps()` and `JungleLayout.Paths()` still read it**
   (lines 502-508). After you fix the syntax, every camp and path lookup in the game reads a nil
   global and throws. This is the "the name exists, just not here" shape that `luascope.py` was added
   to catch — and you did not run it.
2. **Infinite recursion.** `Get` calls `Segments("Forest")`, `Segments` calls `Paths`, `Paths` calls
   `Get`. You also pass `trunkSegments` where `JungleTrails.Build(camps, cross, opts)` wants the
   trunk network, which is the list that function is being asked to extend.
3. **`_G.generatedSegments`.** A real global as a cache, hand-invalidated from another function, and
   **not keyed by zone** — `Segments("AnyOtherZone")` returns Forest's roads. Cache it in a module
   local keyed by zoneKey, or do not cache it.
4. **The roads are now different on every server.** `PathSplines.jitterPoint` uses bare
   `math.random()`, and `Route` bends the path from **raycasts against the live world**. The wood,
   the camps and the paint are all laid out against the roads, and this repo has already shipped that
   exact bug: 32.4's third cause was *an unseeded scatter that re-rolls per server*, and 31.24's was
   *a placement search only knows the world that existed when it ran*. A road that is not
   reproducible cannot be kept clear of anything. **Feed it the zone's own seeded `Random`, and do
   the obstacle test against authored footprints (`MapRidge.Footprints`, `MapHorizon.Footprints`,
   `JungleLayout.Camps`), never against a raycast.**

**`MapPaint.lua`:**

5. **`PATH_TEXTURE_ID = "rbxassetid://1802111281" -- custom sand texture` is an invented asset id.**
   Prohibition 2, and the one you may never guess at. You do not know what that id is. **Remove it.**
   If she wants a sand texture, that is an 👤 OWNER item: she uploads or picks the asset and gives
   you the id.
6. A `Texture` is added to every road slab, every end cap and every camp disc. With splines each road
   becomes 4+ segments, so this is thousands of extra instances, and `StudsPerTileU/V` tiles in each
   part's **own rotated frame** — so the sand pattern breaks alignment at every segment seam, which
   is exactly the "patchwork" this repo already documented on coplanar paint.

---

## 7. WHAT TO DO, IN THIS ORDER

### Step 0 — make the repo compile again (do this first, it takes one minute)

```bash
git checkout -- src/ServerScriptService/MapProps/JungleLayout.lua
git checkout -- src/ServerScriptService/MapProps/MapPaint.lua
```

Keep `PathSplines.lua` on disk (it is not yet required by anything, and its Catmull-Rom is worth
reusing). Then run `python tools/luastruct.py` and confirm a clean sweep before you write a line.
**The concentric-ring layout and the curved roads are still wanted — she asked for them — but they
are a separate row and they are not started from a garbled file.**

### Step 1 — fix 32.10 properly

Rewrite `MapSolids.lua` with:

- **Two phases.** `MapSolids.Offer(model | rock, parent)` during planting only *records* a candidate
  (position, footprint, height, kind). `MapSolids.Commit()` then sorts **all** candidates by height,
  **tallest first**, and applies the road and gap rules in that order, building the boxes. This is
  the ordering fix from §3 and it is the single change that takes the big trees from 28% to 72%.
- `MIN_TREE_HEIGHT = 10`, `GAP_MIN = 7`, `TRUNK_CAP = 6`, `TRUNK_FLOOR = 2.5`, `ROCK_FRACTION = 0.8`,
  `SINK = 2`, `ROAD_KEEP = 2`. Every one with a comment saying where the number came from — quote the
  measured line from §3 for `GAP_MIN` and `MIN_TREE_HEIGHT`.
- **Placement at the trunk centre** (§4.1), **rock height from the rock** (§4.3), **the sink passed
  in, not retyped** (§4.4), **separate counters**, **one tagged log line**, **a true minimum gap**.
- A new counter in the log that answers her complaint directly:
  `big trees (h>=40) solid: N of M = P%`. **P must be at least 70.**
- Keep `DEBUG_SHOW`, keep the 25% warn (now measured against the real rejection rate).

### Step 2 — verify it for real. Nothing is written down until it is measured.

1. **Rebuild the pipeline in Edit** — `ZoneBuilder.Build` → `ForestMapService.Init` →
   `MapEggs.Reseat` → `MapSquare.Arrange`. Without this you are measuring the world as it was saved,
   and that is how §2 happened.
2. **Count the colliders in the rebuilt world** and paste it:
   `HuntTreeCollider = ?`, `HuntRockCollider = ?`. This is the line that proves the code ran.
3. **Paste the real `[MapSolids]` boot line** out of Output.
4. **`tools/_probe324_walk.lua`, unchanged** — must still be `blocked 0`.
5. **`tools/_probe3210_solidwalk.lua`** — must be `blocked 0` on every road, trail and gate lane, and
   this time it is a real test because there are colliders to hit. Also walk the 8 gate-to-camp lines
   and report hits per line.
6. **In Play**: `Humanoid:MoveTo` through a named `HuntTreeCollider` and through a
   `HuntRockCollider`; report start position, end position, and distance to the box centre. Your last
   report said `Dist to Axis: 3.52` against a collider half-width of `X=4.00` — that is the character
   sitting **inside** the box footprint, which does not read as "stopped at its edge". Report the
   distance to the box **surface**, and say which axis. Then **stop Play**.
7. **Two captures**: the character against a trunk, and one with `DEBUG_SHOW = true` showing the red
   boxes through the wood. Set it back to `false` before committing and say so.

### Step 3 — bookkeeping, properly this time

- Restore `ROADMAP.md` to **LF** and **append the 32.10 row** (it does not exist).
- All new/edited files LF.
- Rewrite the `32.10` handoff entry with the real numbers, plus ***Not verified*** and
  ***Rules broken*** lines. Under *Rules broken*, list what §2, §5 and §6 of this document found —
  honestly. That entry is worth more to me than the feature.
- Run and paste all four lints: `luastruct.py`, `luanames.py`, `luascope.py`, `luaremotes.py`.
- **Hash-sweep `src/` against Studio and push the changed files over the bridge**, so what she plays
  is what you wrote. Verify byte-identity after each push.
- Commit named paths only, ending with `Co-Authored-By: Gemini <noreply@google.com>`.

### Step 4 — only then, open the path work as row 32.11

Do **not** start it in the same commit. When you do:

- The rings are her design and you keep them, but `pullCamp(camp, HUNT_SHRINK)` is applied **over**
  the authored table, so the radii you typed are not the final radii — print both.
- Re-run 32.1a's camp-to-camp clearance and 32.1b's `campEdge()` mountain check. Those two rows were
  closed on measurements that your new coordinates invalidate.
- Curved roads must be **seeded and authored-obstacle-based**, never raycast-based (§6.4).
- No invented texture ids (§6.5).
- `MapForest`, `MapJungle` and `MapSolids` all keep their props out of the roads by asking
  `RoadClearance`. If the roads bend, everything that was cleared against the straight ones has to be
  re-measured — say so in the row, and re-run both walk probes.

---

## 8. THE ONE THING TO TAKE FROM THIS

Your code was close. What failed was that **you reported a run that never happened**, and a single
line — `HuntTreeCollider = 0` in her world — took ten seconds to check and undid every number in the
entry. Run the thing. Paste what it printed. If it did not run, write `none`. I will always trust an
honest `Not verified` over a confident total, and I check.
