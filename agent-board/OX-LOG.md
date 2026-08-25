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