# OX-LOG — append-only, newest at the bottom. Format per OX-BRIEF §5.

## T1 | CLAIMED | 2026-08-25T16:26

**Did:** New module `src/ServerScriptService/MapProps/MapPass.lua` (199 lines). `MapPass.Cut(zoneKey, cx, map)` finds every `HorizonHill` model in the map's `Horizon` folder whose world-axis AABB (part-sum maths, same as `MapHorizon.worldBox`) intersects the measured corridor x ∈ [cx−100, cx+100], z ∈ [−660, −460], destroys it, purges its entry from `MapHorizon.Solid[zoneKey]` (so `Colliders()` offers no box for it) and from `MapHorizon.Placed[zoneKey]` by exact wx/wz match (so the wood's keep-out has no ghost), then dresses the mouth: 10 seeded stock-mountain crags (heights 16–30, yaw +90° ± jitter, sunk 3, CanCollide true) flanking z −468…−566 at |x| 70–95. Wired at `ForestMapService` between `TintWall` and `Plant` with the ordering argument in the comment; boot line is the brief's test line (nearest-rock-z vs gate-z).
**Files:** src/ServerScriptService/MapProps/MapPass.lua (new), src/ServerScriptService/ForestMapService.lua (+13 lines, 0 deleted)
**Evidence:**
```
$ C:/Python313/python.exe tools/luascope.py   (full run: every file OK)
OK  ForestMapService.lua              617
OK  MapPass.lua                       199
OK  MapPortalArt.lua                   82

$ C:/Python313/python.exe tools/codediff.py <HEAD ForestMapService> src/.../ForestMapService.lua
    code lines 249 -> 253   removed 0  added 4
      +local MapPass = require(script.Parent.MapProps.MapPass)
      +local MapPortalArt = require(script.Parent.MapProps.MapPortalArt)
      +				MapPass.Cut(zoneKey, cx, map)
      +				MapPortalArt.Init(zoneKey, cx)

$ git diff --numstat
13	0	src/ServerScriptService/ForestMapService.lua

$ git ls-files --eol src/ServerScriptService/ForestMapService.lua
i/lf    w/lf    attr/-text            	src/ServerScriptService/ForestMapService.lua
```
**Not verified:** I have no Studio. The cut count on a live build (brief predicts ~7 hill groups) and the walk/sight result are Claude's to confirm via `tools/probe_portal_walk.lua`.
**Open questions:** (1) Brief rule 8 says disk files are CRLF; measured with `git ls-files --eol`, this repo's untouched files (`MapHorizon`, `MapWaterfall`) are **LF** on disk and in the index (`attr/-text`, byte-exact per `.gitattributes`). My first pass wrote CRLF and `git diff` showed all 617 lines changed; rewritten as LF the diff is exactly my 13 insertions. I matched LF. If Studio's copies really are CRLF, Claude's hash sweep will say so — flagging instead of hiding it. (2) The corridor intersection uses each hill's FULL world box; if that over-cuts an inner-row skirt hill whose box merely clips z −660, the boot line's `cut N` will read high against the predicted 7 and the dressing covers the face — Claude should compare the printed count to 7 before accepting.

## T2 | CLAIMED | 2026-08-25T16:26

**Did:** New module `src/ServerScriptService/MapProps/MapPortalArt.lua` (82 lines). Every boot it walks `Workspace.Forest Portal Template`, destroys every `AdPortal` / `AdGui` descendant by class plus a name fallback ("adportal"/"adgui" substring, case-insensitive), skipping nodes already inside a collected root, and prints the count even when 0. It then seats the surviving `Decorative` island with an absolute idempotent `PivotTo` at `(cx+0, 36, -676)` — centred on the lane, just behind her own gate, skirt buried so nothing floats. Called right after `MapPass.Cut` in `ForestMapService`. Her own `PortalGate` / zone teleport is untouched.
**Files:** src/ServerScriptService/MapProps/MapPortalArt.lua (new), src/ServerScriptService/ForestMapService.lua (shared with T1 wiring)
**Evidence:**
```
$ C:/Python313/python.exe tools/luascope.py
OK  MapPortalArt.lua                   82
```
**Not verified:** I have no Studio — no live proof that the template's ad descendants are gone after boot, and no capture of the island pose.
**Open questions:** 👤 THE ISLAND POSE IS A GUESS FLAGGED AS ONE, per the brief ("ask, do not guess"). (cx+0, 36, −676) puts a 200×165×143 island spanning y −35…108 behind the gate at (0, 69, −575): front face ≈ z −593, i.e. clear of the door stonework only if the gate's columns are shallower than ~18 studs. Kristina should pick: behind-the-gate (current default), flanking pair split left/right of the corridor mouth, or skyline-only (parked above the pass). It is two constants (`ISLAND_Z`, `ISLAND_Y`), not code.

## T3 | CLAIMED | 2026-08-25T16:26

**Did:** New probe `tools/probe_portal_walk.lua` for Studio's command bar, read-only, returns the report string. Three checks because none alone can prove the row: **S1 geometry** — enumerates every `HorizonHill` still meeting the corridor and lists offenders by full path (authoritative, because horizon meshes are `CanQuery=false` and NO ray or bounds query can see them — a ray/walk-only probe would report CLEAR over a standing mountain); **S2 walk** — body box 9×8.4×7 (her measured body, same constants as `_probe3216_portalwalk`) stepped 4 studs spawn→gate, ground cast per sample from y400, box held CLEAR above it, wall = hit taller than RISE 3 (kerb/steps distinction); **S3 sight** — one eye-height village→door ray printing what it hit by full instance path. First 5 blocked samples carry coordinates and the blocking instance; VERDICT line summarises all three.
**Files:** tools/probe_portal_walk.lua (new)
**Evidence:**
```
(file is a Studio paste-in; nothing on disk executes it. Syntax reviewed by eye against
tools/_probe3216_portalwalk.lua, the repo's proven probe. No lint in tools/ parses tools/*.lua.)
```
**Not verified:** I have no Studio. Claude runs it after pushing T1/T2; expected output is `S1 corridor offenders remaining: 0 -- CLEAR`, `BLOCKED 0`, and S3 either CLEAR or hitting only our own gate stonework.
**Open questions:** none beyond T1's — the probe reads the same corridor numbers as `MapPass`, so both must move together if the corridor is ever re-measured.

---

### Pre-existing findings noticed while working (NOT mine to fix, logged where they belong)

From `tools/luaremotes.py` (verbatim):
```
BAD 4 unreachable remote(s) of 79 resolved:

  ExpeditionLeave -- the server listens for it and NO CLIENT EVER FIRES IT
      src/ServerScriptService/ExpeditionService.lua:1006
  MinigameFinish -- the server listens for it and NO CLIENT EVER FIRES IT
      src/ServerScriptService/MinigameService.lua:490
  PromptGamePassPurchase -- the server sends it and NO CLIENT LISTENS
      src/ServerScriptService/MapProps/MapVIP.lua:84
  StationFinish -- the server listens for it and NO CLIENT EVER FIRES IT
      src/ServerScriptService/ExpeditionService.lua:1020
```
None of these four are touched by T1–T3; they pre-date this session.

## T2-pose | ANSWERED | 2026-08-25T16:40

**Did:** Asked the owner the island-pose question T2 flagged (behind-the-gate / above-the-pass / skyline-only / leave at drop point). **Her answer: behind the gate** -- exactly the default already coded (MapPortalArt.ISLAND_X_OFFSET 0, ISLAND_Z -676, ISLAND_Y 36). No code change; the open question in the T2 entry is closed by this answer.
**Files:** none
**Evidence:**
`
owner chat reply, 2026-08-25: "Iza kapije (Recommended)"
`
**Not verified:** still needs Claude's live capture after push -- pose numbers are reasoned, not measured.
**Open questions:** none.
## T1-fix | CLAIMED | 2026-08-25T21:05

**Did:** Both R1 faults closed, in three files plus one new one.
**Fault 1** -- `MapPass.Cut` now walks ALL of `workspace` for `HorizonHill` models and judges each by its own world box (`MapHorizon.WorldBox`, newly exported -- see below), so the orphaned copy in `Workspace.Folder` is inside the scan. Every orphan taken out also takes its sibling `HorizonHillCollider` parts with it: any collider whose centre falls inside the removed hill's box (+4 studs slack -- those colliders were sized at ROCK_FOOT of these very boxes at these very coordinates, so slack only absorbs float drift). In-map hills keep the existing purge of `Solid`/`Placed`; orphans are never in those tables. Boot line now reads `cut %d hills (%d orphaned) and %d stray collider(s)` -- on a clean place `orphaned` reads 0 honestly.
**Fault 2** -- new module `src/ServerScriptService/MapProps/MapPassDress.lua` (176 lines) owns the dressing. It keeps the ten mouth crags VERBATIM (same constants, same seed 20260825+cx; only the draw order height/yaw differs, which changes nothing downstream -- nothing keys off those positions) and adds TWO SHOULDERS: stock mountains a side, yaw pi/2 like their run, scaled to top y=210 (= wall 180 + 30 clearance; same visible-top formula as `MapHorizon.scaleFor`), seated at z=-780 on the OUTER row's own line (AT.outerZ 776; measured offender centres -779/-785) so they refill the torn line behind the wall instead of crowding `MapGateFlanks`'s work at the arch, CanCollide/CanQuery false like every skyline-only outer hill. After seating, the placed box is MEASURED and the model pushed straight out until it clears cx +- (100 + 8) -- measure-then-shift once, the `MapGateFlanks.keepClearOfLane` pattern, no raycast. Boot line prints the test R1 asked for: range-rock edges left/right of the lane (surviving hills + shoulders, low dressing excluded -- that was the figure called meaningless at y 27), bare span between them, tallest top over the corridor against wall 180. Expected after fix: edges pulled in past ~+-115 (was -166/+182, span 348), tallest ~210.
**Why delete-plus-shoulder lost to relocate (R1's option 1):** tried against the measured boxes first. Hill (x -81..609) clears the corridor at centre x~445; hill (x -16..683) at ~449 -- two ~500-stud mountains land within 5 studs of each other, exactly the stacked-lump outcome R1's "re-check against its new neighbour" forbids; west side collapses to a 65-stud slot the same way. Staggering them in z blind -- no mesh measurement outside Studio -- is the rule-7 gamble. Reasoning is in the module header, not just this log.
**Small note taken:** `stockOf` and `worldBox` are now exported from `MapHorizon` (+2 lines there); `MapPass`'s verbatim copy is gone; `MapPass.RockStock = MapHorizon.Stock` kept so `MapGateFlanks` (not my lane) still runs untouched.
**Probe (R3 notes, verdict was already VERIFIED):** gate finder matches `PortalGate` / `PortalCore` / `ZonePortal_` and prints a loud `!! GATE FALLBACK` line when nothing matched; S2 blockers are now ALL reported, grouped by instance with counts and z-ranges (`x5 King.inkubator (z 98..78) | ...` style), sorted by count.
**Files:** src/ServerScriptService/MapProps/MapPass.lua (rewritten, 124), src/ServerScriptService/MapProps/MapPassDress.lua (new, 176), src/ServerScriptService/MapProps/MapHorizon.lua (+8 incl comments), src/ServerScriptService/ForestMapService.lua (+9 incl comments: require + call right after `MapPass.Cut`, ordering argued in the comment), tools/probe_portal_walk.lua (grouped S2 + locator).
**Evidence:**
```
$ C:/Python313/python.exe tools/luascope.py   (full run: every file OK)
OK  ForestMapService.lua              639
OK  MapHorizon.lua                    914
OK  MapGateFlanks.lua                 178
OK  MapPass.lua                       124
OK  MapPassDress.lua                  176

$ C:/Python313/python.exe tools/codediff.py (comment-stripped, per file)
ForestMapService.lua: OLD 257 -> NEW 259; changed 2   (+require, +call -- nothing else)
MapHorizon.lua:       OLD 375 -> NEW 377; changed 2   (+2 export lines -- nothing else)
probe_portal_walk.lua: changed 37 (locator + grouping only)

$ git diff --numstat
9	0	src/ServerScriptService/ForestMapService.lua
8	0	src/ServerScriptService/MapProps/MapHorizon.lua
84	164	src/ServerScriptService/MapProps/MapPass.lua
40	7	tools/probe_portal_walk.lua

$ EOL check: all five files LF (matches .gitattributes byte-exact mirror rule)
```
(`tools/luaremotes.py`: same 4 pre-existing unreachable remotes as last session, none mine.)
**Not verified:** I have no Studio. Claude's checks after push: (1) boot line shows `orphaned` >= 1 and colliders swept on the live BETA place, then `S1 corridor offenders remaining: 0 -- CLEAR` including the Folder hill; (2) `[MapPassDress]` line shows edges ~+-115 or tighter, tallest ~210 > 180; (3) capture from (0, 45, -180): gate framed by rock, not bare slate; (4) walk probe still BLOCKED 0 up the lane.
**Open questions:** (1) SHOULDER_X seed is 305, outside R1's suggested "|x| ~130-200" band -- deliberate: turned with the run, a 210-top shoulder's long axis is ~400 studs, so a centre inside 200 puts its skirt across the lane; 305 keeps the box clear by construction and the nudge enforces it regardless. If the capture wants the shoulders tighter in, shrink SHOULDER_TOP first (smaller mountain, shorter axis) -- say so and I will re-solve. (2) Shoulder pose (behind the wall at z -780) is reasoned from the offender coordinates, not captured; if she wants the peaks closer to the door, SHOULDER_Z is one constant. (3) Crags reproduce at slightly different heights/yaws than build 1 because the seat routine draws height before yaw now; nothing depends on the old draw order.

## 33.1 + 33.2 + 33.6 | CLAIMED | 2026-08-26T18:40

**Did:** Verified 32.28/S13 live end to end and closed the two rows hanging on it. (1) Ran `tools/probe_portal_walk.lua` in Studio against the live world: S1 geometry 0 offenders, S3 sight ray lands on the `PortalGate` film, S2 walk decomposed every blocker by full path. The straight centre line crosses only authored village exhibits (Fountain, two inkubator rows, Spawn.Model structure) and climbable PortalSteps; a waypoint route of body-box Blockcast legs (slot x ~9.5 between the Basic inkubator and house123, east of Fountain, west of merchant/Spawn.Model) reaches the door. Captured the gate framed from (0, 45, -180). (2) **Fixed the probe's own false witness**: old S2 used `GetPartBoundsInBox`, which reads the stone arch's OBB and cannot see that its doorway is a hole in the mesh -- it reported the arch as 3 blocked samples no sidestep could clear (a greedy walk died at its flank). Rewrote S2 to `workspace:Blockcast` + `RaycastParams.RespectCanCollide` + STEP_UP 4.0 (32.10's measured walk-over limit). (3) 33.2 ad sweep: 0 AdPortal/AdGui/named-ad in all of workspace; `Forest Portal Template` absent from Workspace AND ServerStorage -- she removed it, nothing returns, the arch is the surround (her own answer "Iza kapije" already on record for the pose question). (4) 33.6: measured 0 HorizonHill outside workspace.Zones (60 inside), `Workspace.Folder` empty (0 children), deleted the husk (grep: nothing in src/ creates or parents into it), skyline captured unchanged.
**Files:** tools/probe_portal_walk.lua (S2 rewrite, +24/-23), ROADMAP.md (33.1/33.2/33.6 -> `[~]` with evidence), agent-board/OX-LOG.md
**Evidence:**
```
S1 corridor offenders remaining: 0 -- CLEAR
S2 walk spawn->gate: len 931, samples 233, BLOCKED 10   (all village exhibits + PortalSteps)
S3 sight ray village-eye -> door: hit Workspace.Zones.Forest.PortalGate at (0, 71, -575)
ROUTE VERDICT: the full body-box walk REACHES THE DOOR through the village   (10/10 legs ok)
33.2 AD SWEEP: 0 AdPortal/AdGui/named-ad descendant(s) in workspace -- CLEAR
33.2 template 'Forest Portal Template': Workspace=absent, ServerStorage=absent
HorizonHill models: inside Zones 60, OUTSIDE Zones 0 ; Workspace.Folder: present, 0 children
live boot: [MapPass] Forest: cut 6 hills (0 orphaned) and 0 stray collider(s)
           [MapPassDress] edges x -108 / +108 (bare span 216); shoulders y 337 -- SHOW BY 87
           [MapPortalArt] Forest: stripped 0 ad unit(s); template Forest Portal Template not found
hash sweep (5 map-lane files): disk == Studio byte-identical
   MapPass 5915/1879107592  MapPassDress 11248/389011106  MapPortalArt 3734/1433617866
   ForestMapService 37896/1177192303  MapHorizon 52676/778150623
git diff --numstat tools/probe_portal_walk.lua  ->  24 insertions, 23 deletions
```
**Not verified:** nothing on a real published server (Studio only); the Play session was stopped before the probe could re-run inside it -- every number above is Edit-mode world + one captured Play boot log, which is the same world ZoneBuilder rebuilds. The `[x]` on 33.1/33.2/33.6 stays Claude's to write.
**Open questions:** (1) The village plaza north exit is TIGHT for a max-size body: the only slot between the Basic inkubator exhibit and house123 is ~11 studs wide (body needs 9). It passed, but if she ever widens those exhibits the route closes -- flagging, not fixing. (2) `[MapGates] Forest: 10 prop(s) STILL IN THE ROAD with nowhere to go` printed on the live boot (Barrels/Fences/Shop in South road) -- pre-existing, no row found for it; left for triage.

## 32.32 | CLAIMED | 2026-08-26T04:15

**Did:** Measured row 32.32's world state live after the 33.17 frame-leak fix landed (`fc2c678`, committed by a concurrent writer DURING this session at 04:09 -- no code touched here, verification only). (1) Full `WorldShell` census: exactly **6** `Wall` parts per zone, every one on its own zone box -- Forest reads `x +-625` full-depth plus `z +-575` in two 575-wide segments a side with the gate gap between them; **72 unique Wall rows over 12 zones**, and the six strays the row names (`centre(0,50)`, `centre(0,-1200)`, `centre(+-575,-237)`, `centre(+-575,-912)`) exist **nowhere** in the folder. (2) `probe_portal_walk` re-run UNCHANGED against the rebuilt world: S1 `0 offenders -- CLEAR`; S2 **`BLOCKED 0 of 233 samples`** on the dead-centre line -- better than 33.1's waypoint route, and explained: the post-fix rebuild let `MapSquare` finally ring the village groups (`[MapSquare] Forest: 43 props moved in 3 of 3 groups ... shop narrow (46,55)->(79,52)`; the pre-fix boots printed `0 props moved ... LEFT WHERE THEY WERE`, because half-shifted exhibits filled their own clearings); S3 sight ray hits the `PortalGate` film at `(0, 71, -575)` -- the door, not a Wall. (3) Eggs healthy on the `stamp 137 -> 138` rebuild: three columns seated `ground/lift 0.0/+1.6`, **no split warnings**. The warning itself proved real on the pre-rebuild boot: `egg 1/2/3 is in 2 pieces standing up to 608/575/544 studs from its own shell`.
**Writer-pass answer the row demanded:** `ZoneBuilder.lua:1844-1854` is the pass that stamps the `Zone` attribute and collects `ALWAYS_LOADED` direct children into WorldShell. The strays were once Forest direct children built through the leaked frame, collected like any wall, and preserved by same-world handback (`ShellId` match -> parts handed back, never position-checked). A rebuild that regenerates the zones folder issues a NEW `ShellId`, so every old shell part is destroyed and only correctly-framed walls are laid again -- that is what removed them.
**Evidence:**
```
gate Workspace.Zones.Forest.PortalGate at (0.0, 59.3, -575.0)
S1 corridor offenders remaining: 0 -- CLEAR
S2 walk spawn->gate: len 931, samples 233, BLOCKED 0 -- CLEAR
S3 sight ray village-eye -> door: hit Workspace.Zones.Forest.PortalGate at (0, 71, -575)
VERDICT: geometry CLEAR, walk CLEAR, sight hit (see S3)
Forest walls: pos(-625,90,0) 4x180x1150 | pos(625,90,0) | pos(-+338,90,-575) 575x180x4
              pos(-+338,90,575) 575x180x4   == exactly the authored zone box, 6 of 6
live boot (pre-rebuild):  [MapEggs] egg 1..3 is in 2 pieces standing up to 608/575/544 studs ...
live boot (stamp 138):    [MapEggs] seated 3 egg columns in modern row (0.0/+1.6 x3)  <- no split lines
                          [MapSquare] 43 props moved in 3 of 3 groups ringed about (-19, 8)
hash sweep: disk == Studio byte-identical for all six files touched by 33.17
```
**Not verified:** whether a FUTURE fresh build could still re-create strays -- reasoned closed rather than re-measured: the leak path is closed in code (`ZoneKit.withFrame` restores on every exit path incl. throw; `ZoneBuilder` warns and clears a leaked frame at each zone start), and the observed full rebuild produced zero strays and zero split eggs. Console noise during the rebuild (`ZoneService:51 OnServerEvent can only be used on the server`, then `MapPortals:68` / `MapSigns:52` module-load failures) are **Edit-context artifacts**: `ReadyRemote.OnServerEvent` at module top level throws outside a running-server context, so any Edit-mode require of ZoneService trips it; Play boots in the same console print both modules clean.
**Open questions:** (1) `fc2c678` landed mid-session from another writer closing 33.17 `[x]`; this session overlapped it in Studio (Edit-mode measurements only, read-only probes). If Claude reviews both entries: the two sessions are complementary, not conflicting -- 33.17 wrote the fix, this entry measures its world effect under 32.32. (2) Row 32.32 stays `[~]` until Claude runs or accepts these numbers; the `[x]` ceiling rule stands.
## 33.3 | CLAIMED (measurement half) | 2026-08-26T04:40

**Did:** Measured what fork (a) actually has to solve, on the live module and against a verified Python replica of `pullCamp`, and delivered the rows measured authored/final comment column. (1) Built a faithful replica of `PullIn` / `campClear` / `pullCamp` / inner-first placement order over `CAMPS_FOREST` (constants: CAMP_RADIUS 20 -> MIN_VILLAGE_CLEAR 28, MIN_CAMP_SEPARATION 60, dial 0.20); it reproduces every boot line exactly -- `[village-clamped: SE5, NE5]`, `[separated: NW5]`, furthest NW4 at 84.0, closest NW3 at 28.0, tightest floor gap NW1/NW5 +20.0. Verified live: loading `JungleLayout.Source` through loadstring and reading `Camps()` gives identical vgaps to the decimal for all twenty camps. (2) **The finding: the inner ring is REAL, the outer band is a SMEAR, and eight of the twenty hand-written `final r=` comments were lies.** Inner ring: 10 camps at 28.0-29.3 (clean). Outer: SW5 56.1 alone, NE4 71.3, NW2 73.7, SW4 81.6, then NW4/NE2/SW2/SE4 at 84.0 -- nothing stands between 29.3 and 56.1. Worst comment errors: SE2 claimed 84, measures **29.3** (a raidBrute on the INNER ring, beside the village); NE5/SE5 claimed 56, measure **28.0** exactly (the clamp line); NW5 claimed 56, measures **80.8**; NE4 claimed 84, measures 71.3; SW4 81.6; NW2 73.7. (3) Replaced all twenty comments with measured values plus a header block naming the method, the worst errors and why the remaining re-author is an INVERSE problem against `pullCamp`, not a retype (R15s two reverted retypes: 16 and 8 keep-out violations). No coordinate changed; the world is untouched.
**Files:** src/ServerScriptService/MapProps/JungleLayout.lua (comments only, +32/-20)
**Evidence:**
```
replica vs boot: clamped [SE5,NE5] == [SE5,NE5]; separated [NW5]==[NW5]; far NW4 84.0==84.0;
                 near NW3 28.0==28.0; tightest NW1/NW5 +20.0==+20.0
live Camps() vgaps == replica to 0.1 for all 20 (NW2 -340.8,252.0 vgap 73.7 etc.)
village-gap bands after pullCamp(0.20): {28:[NW1,NW3,NE1,NE3,NE5,SW1,SW3,SE1,SE3,SE5],
  29:[SE2], 56:[SW5], 71:[NE4], 74:[NW2], 81:[NW5], 82:[SW4], 84:[NW4,NE2,SW2,SE4]}
pushed: Studio Source len=54461 hash=891141676 == disk len=54461 hash=891141676
luascope: OK JungleLayout.lua 891
```
**Not verified:** nothing new to verify in-world -- no coordinate moved, so `Describe` lines are unchanged by construction and were not re-booted. The inverse solve itself (which camp goes to which band) is NOT attempted: it is a design decision (an apex -- SE5 -- currently sits on the inner ring beside the village, and fixing that re-opens 32.18s east-camp-edge arithmetic that 33.4 depends on), so it is written up as the rows remaining work rather than guessed at.
**Open questions:** (1) CONCURRENT WRITER COLLISION, second of the session: commit `cc575ef` ("33.18: the secret passage behind the waterfall", 04:24) swept these exact JungleLayout comment lines into ITS commit alongside the MapWaterfall feature -- the mirror image of R28s "code riding in someone elses commit", this time bookkeeping absorbed by a feature. Attribution untangled here; no content lost. Their push also carried my edits to Studio byte-identically (hash above), which is why my own push attempt found the anchor already replaced. (2) For whoever solves the smear: moving NE5/SE5/SW5/SE2 in vgap while pinning their final |x| at ~298.5-299.8 keeps 32.18s east edge (319.8 ceiling) intact -- vgap on that line is `hypot(28, |fz|-230 or 0)`, so band 56 wants fz ~ +-278.5 and band 84 wants fz ~ +-309.2. That arithmetic is the cheap half; the DESIGN half (does an apex belong 28 studs from the square?) belongs to her.
