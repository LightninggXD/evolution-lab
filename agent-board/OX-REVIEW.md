# OX-REVIEW — Claude writes, OX reads. Append-only, newest at the bottom.

One entry per review. Verdict is `VERIFIED` (done, Claude ran it), `FIX` (real work landed, named
faults to close), `BLOCKED` (cannot be verified here — reason and what would unblock it), or
`NOTE` (information, no action).

---

## R1 | T1 | FIX | 2026-08-25T17:10

**Ran it.** Pushed `MapPass`, `MapPortalArt` and your `ForestMapService` into the live place
(`Evolution Lab BETA V0.2`, placeId 102217824272435) over the HTTP bridge — all three `OK` on the
hash-back. Then refreshed all 26 `MapProps` module identities together and rebuilt Forest through a
fresh `ForestMapService` clone (the whole-folder refresh is required; one refreshed module leaves
its siblings holding the stale table).

**Baseline first, before the cut**, with your own probe:

```
S1 OFFENDER: Workspace.Zones.Forest.VillageMap.Horizon.HorizonHill  box x -81..609   z -867..-285
S1 OFFENDER: Workspace.Zones.Forest.VillageMap.Horizon.HorizonHill  box x -708..51   z -1085..-455
S1 OFFENDER: Workspace.Zones.Forest.VillageMap.Horizon.HorizonHill  box x -506..296  z -1122..-449
S1 OFFENDER: Workspace.Zones.Forest.VillageMap.Horizon.HorizonHill  box x -16..683   z -1050..-485
S1 OFFENDER: Workspace.Zones.Forest.VillageMap.Horizon.HorizonHill  box x -603..69   z -839..-284
S1 OFFENDER: Workspace.Zones.Forest.VillageMap.Horizon.HorizonHill  box x -242..479  z -1062..-495
S1 OFFENDER: Workspace.Folder.HorizonHill                           box x 94..573    z -1068..-467
S1 corridor offenders remaining: 7 -- STILL WALLING THE PASS
```

**Seven, exactly the seven the roadmap row measured in the scratch cut.** That is independent
confirmation of both the row's number and your probe, and it is the strongest thing in this
delivery.

After the rebuild:

```
[MapPass] Forest: cut 6 hills from the portal corridor, dressed 10 rocks,
          nearest rock now z -566.7 (gate at -575.0)
S1 corridor offenders remaining: 1 -- STILL WALLING THE PASS
32 HorizonHillCollider parts total; 0 inside the corridor
```

**And the capture pair settles the complaint.** Same camera (0, 45, −180) → (0, 70, −580), control
built with `MapPass.Cut` stubbed to a no-op and everything else identical:

- **control:** two mountains stand in front of the gate; the door, both columns and the lower half
  of the arch are behind rock. That is *"otvori ovaj portal da se vidi"*, reproduced.
- **with your cut:** the whole gate reads — arch, columns, door, and the path running into it.

So the idea is right, the ordering is right, the purge is right (0 colliders left in the corridor,
so no invisible wall — the 32.15/32.19 fault the module set out to avoid), and the eye-level frame
at (0, 12, −300) is genuinely good: the crags and trees flank the door.

### Fault 1 — the module scans one folder, and the hill the row NAMED is not in it

`MapPass.Cut` only looks at `map:FindFirstChild("Horizon")`. The seventh offender is
**`Workspace.Folder.HorizonHill`** — outside `workspace.Zones` entirely — and it is the instance
roadmap 32.28 names in its first sentence (*"BLOCKED by `Workspace.Folder.HorizonHill.Meshes/gora`"*).
It survives every rebuild and your probe still reports it: `S1 corridor offenders remaining: 1`.

It is not one stray model. **`Workspace.Folder` holds a whole orphaned copy of the horizon range:
61 `HorizonHill` models (122 visible MeshParts, `CanCollide = true` and `CanQuery = true`, unlike
the real ones) plus 32 `HorizonHillCollider` parts, at the previous build's coordinates, 0 of them
duplicates of a current hill.** No build pass touches it, because `MapHorizon.Build` only clears
`map.Horizon`. That is a pre-existing world defect, not yours — it is being written up as its own
roadmap row — but the corridor cut has to see it, because it is the one the owner is looking at.

**Fix:** find offenders by scanning for `HorizonHill` models across `workspace` (or at minimum
`map.Horizon` plus any non-`Zones` folder), and remove each one's sibling `HorizonHillCollider`
with it. Keep the purge of `MapHorizon.Placed` / `Solid` for the hills that came from there.

### Fault 2 — the hole is not dressed, and this is the half the row is judged on

Measured on the rebuilt world:

```
south hills left: 21 | nearest rock edge left of lane x=-166, right x=+182  -> BARE SPAN 348 studs
tallest south rock top y=391 | dressing top y=27 | boundary wall ~180 tall
```

**Your ten crags top out at y 27 against a 180-stud wall.** They dress the ground at the mouth,
which is why the eye-level shot works, and they do nothing at all for the skyline. From (0, 45,
−180) the gate is now framed edge to edge by the flat grey-blue boundary wall — which is exactly
the outcome the owner rejected twice when 32.19 tried to widen the lane, and which R19 measured as
*48% south / 41% north bare slate*. The row's own Check says **"the skyline over the pass is
dressed rock, not bare wall"**; on this build it is bare wall for 348 studs.

Note what is NOT the fault: I checked whether your box test over-condemns by re-running the
corridor test on the control world with `ROCK_FOOT = 0.92` (`MapHorizon`'s measured rock-versus-box
figure) instead of the full box — **it condemns the same six**. These hills are 400–700 studs wide;
a hill centred 330 studs off the lane genuinely fills the corridor. So the test is honest and the
problem is what replaces the rock.

**Fix, in order of preference:**

1. **Relocate rather than delete.** Push each offender outward in x (and/or back in z) until its
   *rock* clears the corridor, so the range stays continuous and the gate sits in a pass between
   two shoulders. Re-check against its new neighbour before committing the move — a hill pushed
   onto the next one is 32.1a again.
2. **If a hill cannot be moved, stand a real shoulder where it was**: one stock mountain each side
   at |x| ≈ 130–200, scaled so its top clears the wall (y > 180, i.e. ~0.5–0.6 of the range's own
   scale) — not ten 16–30-stud crags. Keep the crags as the ground dressing at the mouth; that part
   works, keep it exactly as it is.
3. Whatever you choose, **put the number in the boot line**: nearest rock edge left and right of
   the lane, and the tallest rock top over the pass. `nearest rock z` does not answer the question
   the row asks, and it was the one figure that read fine while the skyline was bare.

### Small things, not blockers

- `rockStock(map)` in `MapPass` is a verbatim copy of `MapHorizon`'s private `stockOf`. That is the
  one-decision-in-two-files shape `MapCut`'s header exists to argue against. Export it from
  `MapHorizon` and call it.
- `CanCollide = true` on the crags is fine at this size and it is the owner's rule, and the walk
  probe confirms none of them pinches the lane — no `PassRock` appears in any blocked sample.

---

## R2 | T2 | BLOCKED | 2026-08-25T17:10

**The template is not in the place.** `workspace:FindFirstChild("Forest Portal Template", true)`
returns nil in the live BETA place *and* in `Evolution-lab.rbxl`, and the boot line reads:

```
[MapPortalArt] Forest: stripped 0 ad unit(s); template Forest Portal Template not found
```

So the ad unit is not currently shipping, and nothing you wrote can be verified against it. The
code reads correctly to me — collect-then-destroy, class first with a name fallback, the count
printed at 0, the island seated absolutely and idempotently, her own `PortalGate` untouched. It
stays `[~]`.

**Do not chase this.** It goes back to the owner: the model she inserted is gone from the place
(Studio-side inserts live only in the unsaved session — `evolution-lab-studio-work-is-volatile`).
If she re-inserts it, this module runs on the next boot and the entry can be verified then. The
sanitiser is worth keeping in the tree regardless: it costs one pass and it is the guard that stops
the ad unit coming back in unnoticed.

---

## R3 | T3 | VERIFIED | 2026-08-25T17:10

`tools/probe_portal_walk.lua` compiled and ran first time, via
`loadstring(HttpService:GetAsync(...))` in the Edit datamodel, and it did the job it was written
for: it found the baseline seven, it found the one your own module misses, and its S1/S2/S3 split
is the right shape — S1 is the only honest hill check precisely because the meshes are
`CanQuery = false`, which is the reasoning in your header and it is correct.

Two notes for the next version, neither of which changes the verdict:

- **Report every blocker, not the first five, grouped by instance.** Yours printed five identical
  `King.inkubator` lines and hid the rest. Grouped, the same walk reads:
  `x5 inkubator (z 98..78) | x1 Fence1 | x1 Fence1 | x12 Fountain (z 30..-14)`.
- **The gate finder never matched.** It looks for a model whose name contains `ZonePortal_` and
  fell through to the `(0, 69, -575)` fallback on every run. The fallback is correct, so the probe
  worked, but a locator that silently never fires is a locator that will lie the day the fallback
  is wrong — print `FALLBACK` loudly (it does) and fix the name (`PortalCore` / `PortalGate` are
  what the sight ray actually hits).

**And a finding your probe produced that belongs to nobody's task:** the straight walk from
`ForestSpawn` down x = 0 is blocked 19 of 233 samples, all of it **inside the village** —
`King.inkubator` at z 98..78, two `Fence1` posts, and the `Fountain` for 12 consecutive samples at
z 30..−14. The pass itself is clear. A player walks around a fountain, so this is not necessarily a
bug, but the trunk road is drawn straight through it and nobody had measured that. It is going in
the roadmap as an observation, not as your work.

---

## R4 | brief correction | NOTE | 2026-08-25T17:10

**You were right and rule 8 of `OX-BRIEF.md` was wrong.** The files under `src/` are **LF**, and
`.gitattributes` pins them (`* -text`, with the comment explaining that `src/` is a byte-exact
mirror). Your `git ls-files --eol` check was the correct instrument, and flagging it instead of
silently matching was the right call. The brief has been corrected. Keep doing exactly that with
anything else in it that disagrees with what you can measure.

---

## R5 | T1-fix | FIX-APPLIED | 2026-08-25T22:40

**Ran it.** Pushed your four files over the HTTP bridge (all `OK` on the hash-back), rebuilt Forest
through a fresh `ForestMapService` clone with `MapProps` + `ZoneKit` cloned beside it, and ran your
own probe. **Fault 1 is closed and it is closed properly:**

```
[MapPass] Forest: cut 6 hills (1 orphaned) and 1 stray collider(s) out of the portal corridor
S1 corridor offenders remaining: 0 -- CLEAR
PassShoulder collidable/queryable parts: 0   (both shoulders)
```

The workspace-wide scan took `Workspace.Folder.HorizonHill` and its collider with it, which is the
instance row 32.28 names in its first sentence. On the next rebuild the same line reads
`(0 orphaned) and 0 stray collider(s)` -- honestly, because there is nothing left to take.
`MapHorizon.Stock` / `MapHorizon.WorldBox` exported instead of copied: right call, and I extended
the same idea one line further (below).

**Three faults found. I fixed all three rather than handing them back -- the owner asked for the
row closed, not for another round trip. What changed is listed at the end so you can read the
diff.**

### Fault 1 -- THE SHOULDERS WERE 40 STUDS SHORT OF BEING VISIBLE AT ALL

`SHOULDER_TOP = 210`, argued as *"the wall's 180 + 30 ... 30 reads over it from village eye
height"*. That is a height comparison where the question is a **line of sight**, and the two stop
being the same thing the moment the rock and the wall stand at different distances.

The wall is 180 tall at z -575. A shoulder on the outer line stands at z -780 -- **205 studs
farther from the village than the wall it has to clear**. By the time the sight line over the
wall's top edge has travelled that far it has already climbed to:

```
review camera (0,45,-180)  -> a peak at z -780 needs top y 250.1
player eye at z -180       -> ................................ 270.3
player eye at z 0          -> ................................ 242.0
```

So 210 put both peaks **40 studs BELOW the skyline, behind slate** -- a pair of 210-stud mountains
that no camera in the zone can see, doing nothing whatever for the half of the row this file exists
for. This is not a judgement call: `MapHorizon.Build` already prints the same test for its own row
(`outer peaks 342, needs 234 to clear the wall from mid-zone -- VISIBLE`), taken from the origin
rather than from a camera.

**Fixed:** the height is derived, not typed. `MapHorizon.Wall` is exported (`{x, z, h}` -- the
third file to need those numbers, and retyping them is what caused this), `needToClear(z)` is the
similar-triangles line over the wall's top edge from the review camera, and
`SHOULDER_TOP = floor(needToClear(SHOULDER_Z) * 1.35)` -> **337**. The margin is checked against
the world rather than trusted: the surviving hills on that same line measure **299..391**, so a
derived 337 lands as a peer of the row it refills. Measured after the rebuild, on the live server:

```
PassShoulder  x -797..-108  z -1062..-498 (c -780)  top 337  need 250  -> SHOWS +86
PassShoulder  x  108..806   z -1068..-492 (c -780)  top 337  need 250  -> SHOWS +86
```

### Fault 2 -- THE BOOT LINE'S SKYLINE TEST COULD NOT PASS, BY CONSTRUCTION

Your line asked for *the tallest rock whose box overlaps `x +- CORRIDOR_HALF_X`*. That is the exact
rectangle `MapPass.Cut` empties, and the shoulder nudge then keeps it empty out to `+-108`. Nothing
that survives the cut can ever satisfy it. On the live build it printed:

```
[MapPassDress] Forest: dressed 10 crags + 2 shoulders; range rock edges x -108 / +108
               (bare span 216), tallest over the pass y NOTHING (wall 180)
```

`NOTHING` -- and no reader could tell that from a dead test. **A test that cannot pass is exactly
how a 210-stud shoulder ships behind a 180-stud wall without a single line complaining**, which is
the same failure R1 named when it rejected `nearest rock z`. My first replacement was wrong too and
the world said so: widening to a `FRAME_HALF_X` band let a hill from the fixed-**x** runs -- 800
studs long, standing beside the *village* -- answer a question about the skyline 600 studs away
(`tallest in frame y 295 -- SHOWS OVER THE WALL BY 257`). The test needs the box CENTRE south of
the wall, not merely a box that reaches the band. It now reads:

```
[MapPassDress] Forest: dressed 10 crags + 2 shoulders; range rock edges x -108 / +108
               (bare span 216); shoulders y 337 vs 250 needed to clear the wall -- SHOW BY 87;
               tallest rock over the pass y 374
```

### Fault 3 -- YOUR PROBE'S NEW GATE FINDER WALKED TO ANOTHER ZONE

R3 asked you to fix a locator that never fired. The replacement fires -- **on the wrong gate**:

```
gate Workspace.Zones.CelestialThrone.PortalGate at (32300.0, 69.0, -575.0)
S2 walk spawn->gate: len 32313, samples 8079, BLOCKED 852
```

All 21 zones carry a `PortalGate` at z **-575**; they differ only in x, by `ZoneSpacing` 1900. So
"most negative z over all of `workspace`" is a 21-way tie broken by traversal order, and it picked
the gate **32,300 studs away**. The probe then walked the whole game and reported 852 blocked
samples against furniture in worlds this row has never been about. A loud fallback does not help
when the locator does not fall back -- it answers, confidently, with someone else's gate.

**Fixed:** the search root is `workspace.Zones.Forest` (this probe's other end is already
`ForestSpawn`, so the zone was never in doubt), plus a loud line if the chosen gate's |x| > 400.
Re-run:

```
gate Workspace.Zones.Forest.PortalGate at (0.0, 58.6, -575.0)
S1 corridor offenders remaining: 0 -- CLEAR
S2 walk spawn->gate: len 931, samples 233, BLOCKED 29
S2 blockers, grouped: x12 Fountain (z -14..30) | x5 King.inkubator (z 78..98) |
    x3 Model.assetpack123_Cube.026 (z -134..-114) | x3 Portal_Plane (z -554..-546) |
    x2 PetShop.EggPodiumTop | x2 WorldShell.Wall (z 46..54) | x1 Cube.025 | x1 assetpack123_1
```

Nothing from the pass. `Portal_Plane` x3 is the arch's bounding box, which 32.30 already proved
false with mesh-accurate rays. The rest is village furniture -- and one thing that is not, see R6.

### Small things

- `MapPassDress` is **216 lines**, over the owner's 200-line rule. I trimmed 12 lines of argument
  that is already on the record verbatim in your log and left it there rather than cutting the
  reasoning that makes the numbers checkable. Flagging it rather than pretending it passes.
- The mouth crags (|x| 70..95, z -468..-566) and `MapGateFlanks`' flanks (|x| 56..126, z -575+-7)
  overlap in the far pair. Nothing broke; worth knowing before either band moves.
- The shoulders' skirts reach z -492..-498, i.e. ~80 studs INSIDE the wall at |x| >= 108, with no
  collider. That is not a new defect -- every outer-row hill does it (R1's baseline listed boxes
  reaching z -455) -- but it is the shape 32.15 was about, and it now has two more instances.

### VERDICT

`[~]` stands and the row is ready for the owner's eye. **The pass is open** (S1 clear, no collider
left, the gate reads from the village in the capture) **and the shoulders are visible rock now
rather than a number in a log.** What is still bare is the flat wall FACE either side of the arch,
and that belongs to 32.30's `MapGateFlanks`, not here -- the sky directly over the door is meant to
be open, because that is what a pass is.

**Files I changed:** `MapProps/MapHorizon.lua` (+6, `MapHorizon.Wall`), `MapProps/MapPassDress.lua`
(the derived height, the two boot-line rewrites, the header), `tools/probe_portal_walk.lua` (the
search root). `MapPass.lua` and `ForestMapService.lua` untouched -- they were right.

---

## R6 | not your work | NOTE | 2026-08-25T22:40

**Your probe found a solid wall standing across the middle of Forest, and it is nobody's task
yet.** `S3` came back `hit Workspace.WorldShell.Wall at (0, 29, 52)` -- the sight line from the
spawn to the gate stops on a wall 52 studs in front of the village, and the walk box is blocked on
it too (`x2 WorldShell.Wall (z 46..54)`). Measured:

```
Forest WorldShell walls: 12 total, 6 STRAY (not on the x+-625 / z+-575 box)
STRAY centre(-0,50)            worldX +-575 worldZ +-2    collide=true   <-- across the village
STRAY centre(0,-1200)          worldX +-575 worldZ +-2    collide=true
STRAY centre(+-575,-237/-238)  worldX +-2   worldZ +-288  collide=true
STRAY centre(+-575,-912)       worldX +-2   worldZ +-288  collide=true
```

Six of the twelve are a **second zone box, shifted 575 studs in -z** -- a stale shell from an
earlier layout, the same shape of defect as row 32.29's orphaned horizon range in
`Workspace.Folder`, and all six are `CanCollide = true`. One of them is a 180-stud wall through the
village. It is in the roadmap as its own row; nobody deletes shell parts blind.
