# Briefing for OX — Evolution Lab, the map lane

You are a new agent on this project. You have never seen it. Read this file top to bottom **before
you open a single source file**. It is written so that you do not have to re-derive anything.

---

## 1. What we are building

**Evolution Lab** is a **Roblox** game — a "brainrot simulator" style progression game, written in
**Luau**. The player is a small creature, kills mobs, earns DNA and Diamonds, evolves into bigger
creatures (a 100-step chain, 206 skins), rebirths, buys pets, swords and game passes. It is not yet
published; it is being finished for launch.

The world is **21 zones**. Zone 1, **Forest**, is the one being finished — an authored village map
with a mountain range around it, twenty hunting camps around the village, roads between them, a boss
arena, and a portal gate at the map edge that leads to the next zone. **Everything you touch is
Forest only.** The other twenty zones keep the old generated valley until Forest is right. That rule
is not yours to change.

The judgement on this project is **visual**: does the zone read as a *designed place* when the owner
walks it. Not "does the code look clean".

### Who is who

- **Kristina** is the owner. She speaks Bosnian, gives instructions by screenshot and by walking the
  game. Her word closes any argument.
- **Claude** is the lead agent. It owns the roadmap, verifies work **live in Roblox Studio**, and is
  the only one who may mark a task done.
- **Gemini** is a second implementing agent, working in its own lane.
- **You (OX)** are a third implementing agent. Your work is verified by Claude. See §5.

---

## 2. The repository

```
C:\Users\Kristina\Documents\evolution-lab
```

Open your session **in that folder** (it is a git repo — if your client says "No Git / Default
Project" you are in the wrong directory and nothing below will be found).

| Path | What it is |
|---|---|
| `ROADMAP.md` | **The source of truth for what is done.** ~5400 lines, nine+ phases. We are in **Phase 32**. Every row carries its own *Check* and *Evidence* column. Read the rows you are assigned; do not read the whole file — it will eat your context. |
| `src/` | A **full mirror on disk of the Roblox place's scripts**: `src/ServerScriptService/…`, `src/ReplicatedStorage/…`. Read code off disk. This is where you make every edit. |
| `src/ServerScriptService/MapProps/` | The map lane — 25 small modules. This is where your work lives. |
| `agent-board/` | How agents talk to each other through files. See §5. |
| `tools/` | Lints and helpers, run with `C:/Python313/python.exe tools/<name>.py`. |
| `*.rbxl` | The Roblox place files. **Do not open, do not edit.** |

### The one thing to understand about Studio vs disk

**Roblox Studio is the source of truth for the code that actually runs.** `src/` is a mirror, and a
change on disk does nothing until it is pushed into Studio. You do **not** have Studio access —
Claude pushes and runs. So:

- Write your change to `src/`, completely, so it compiles.
- **Never fabricate output.** Do not write a "boot log" you did not see. An invented log has been
  shipped on this project once and it cost a whole task redo. If you cannot run it, write
  `Not verified: I have no Studio` — that is a correct answer and it costs you nothing.

---

## 3. The rules that get work rejected if you break them

1. **Small modules, never a god file.** The owner's standing rule (2026-08-22). New behaviour goes
   in a **new file under 200 lines** with a single purpose. Do not grow `MapHorizon.lua` (906 lines)
   or `JungleLayout.lua` (879) — a big file burns tokens on every read.
2. **Comment the WHY, in the house style.** Look at any file in `MapProps/` before writing one.
   Those headers explain *why a number is what it is* and *what was tried and failed*. Match that.
   A number with no argument next to it gets reverted.
3. **Never invent an asset id, product id or pass id.** If you need one, stop and ask.
4. **Determinism.** Every scatter/jitter draws from the **zone's own seeded `Random`**
   (`Random.new(<constant> + cx)`), never bare `math.random()`. Two servers of the same place must
   build the same map. This has shipped broken twice.
5. **Never raycast the live world to decide placement.** A raycast answers "what happened to be
   built at that instant". Decide against **authored footprints** — pure functions of the tables:
   `MapRidge.Footprints`, `MapHorizon.Footprints(zoneKey)`, `MapHorizon.Colliders(zoneKey)`,
   `JungleLayout.Camps`. Raycasting is allowed for *verification*, never for *placement*.
6. **Placement is order-dependent.** A pass only knows the world that existed when it ran. Read the
   ordering comments at `ForestMapService.lua:551-590` before inserting a new build step, and say in
   your own comment why your step goes where it goes.
7. **English** in every file, comment and log line. (Chat with the owner may be Bosnian; artifacts
   are English.)
8. **Line endings: the files on disk are LF, and `.gitattributes` pins them (`* -text`).** Preserve
   whatever a file already has — `src/` is a byte-exact mirror of the Roblox place, so a rewritten
   line ending shows as an all-lines diff and mismatches Studio's hash check. Measure with
   `git ls-files --eol <path>`; never assume. *(Corrected 2026-08-25: this rule said CRLF and it was
   wrong — OX measured it.)*
9. **Do not touch these** — they are another agent's lane right now:
   `JungleLayout.lua`, `PathSplines.lua`, `JungleTrails.lua`, `MapRoad.lua`, and everything under
   `agent-board/` except your own log file.
10. **Do not commit and do not push to git** unless Claude asks. Leave your changes in the working
    tree.

---

## 4. Orientation — the Forest map in coordinates

- The zone is built around a centre x, `cx`. Forest's `cx` is near 0. **Never hardcode a world x —
  express it as `cx + something`.** z is absolute.
- The **village** sits in the middle (around z 0). The **main lane** is a 56-stud trunk road down
  `x = 0`, running z −240 → −555. `CreatureService.insideKeepOut` keeps `|x| < 62` empty for it.
- **Twenty hunting camps** stand around the village, authored in `JungleLayout.CAMPS_FOREST`.
- **`MapHorizon`** raises the mountain range: an **inner row** at `|x| = 600 / |z| = 568`, and an
  **outer row** ~200 studs beyond it in the void. Inner-row hills got collider boxes in task 32.15;
  **outer-row hills do not collide** — they are skyline only, but they are enormous (≈480 × 620
  bounding boxes) and they *block sight*.
- **`LANE_PORTAL = 90`** is the notch left in the inner run at the portal gate. **It has been widened
  to 132 and to 240, and both were reverted, because widening bares the boundary wall.** Widening
  that lane is not on the table. Read the comment block at `MapHorizon.lua:226-249`.
- The **portal gate** (`PortalGate` / `ZoneGate`, built by `MapPortals`) stands at about
  `(0, 69, −575)` — the −Z edge, straight up the main lane from the village.

---

## 5. How you report — your own lane

Agents on this repo never edit each other's files. Yours is **one new file you create**:

```
agent-board/OX-LOG.md
```

Append-only, newest entry at the bottom, one entry per task attempt, exactly this shape:

````markdown
## T1 | CLAIMED | 2026-08-25T14:20

**Did:** one or two sentences — what changed and where.
**Files:** src/ServerScriptService/MapProps/MapPass.lua, src/ServerScriptService/ForestMapService.lua
**Evidence:**
```
<pasted verbatim from a terminal or lint — never retyped, never invented>
```
**Not verified:** what you could not run, and why. `none` if nothing.
**Open questions:** anything you had to assume. Say the assumption out loud.
````

Status word: `CLAIMED` (you believe it is done), `BLOCKED` (you cannot proceed — say exactly what
you need), or `ACK` (you have read a fix and started on it).

**Your ceiling is `[~]` — "claimed, unverified".** Only Claude writes `[x]`, and only after running
it in Studio. Never edit `ROADMAP.md` status boxes yourself.

### Before you claim anything, run the three lints and paste the output

```bash
C:/Python313/python.exe tools/luascope.py     # a name used out of its scope
C:/Python313/python.exe tools/luaremotes.py   # a remote fired on one side, unhandled on the other
C:/Python313/python.exe tools/codediff.py     # what your diff actually deleted
```

---

## 6. Your tasks

Three tasks, in order. **Finish T1 before starting T2.** All three serve one owner complaint, sent
with a screenshot in her words: *"otvori ovaj portal da se vidi"* — **open that portal so it can be
seen** — and *"ubacila sam bolje portale"* — she has inserted a better portal model. This is roadmap
row **32.28**; search `ROADMAP.md` for `| 32.28 |` and read it before you start.

---

### T1 — The portal is walled in, and the fix is DEPTH, not width

**What is wrong, measured on the live world (do not re-measure; you cannot):**

- A ray from the village to `PortalGate` at `(0, 69, −575)` is **blocked** by
  `Workspace.Folder.HorizonHill.Meshes/gora` at `(0, 69, −571)`.
- The offenders are **outer-row hills** — two of them ≈480 × 620 standing at `(−105, −785)` and
  `(118, −779)`, whose **front faces reach z = −472**, i.e. they stand **100 studs in front of the
  gate**, between the player and the door.
- The `LANE_PORTAL` notch only opens the wall to **z = −534**. The lane is therefore **not too
  narrow, it is 41 studs too shallow.** That is why every attempt to fix this by widening
  (90 → 132 → 240) was rejected: widening bares the boundary wall and never touches the hill that is
  actually in the way.
- A scratch cut proved the shape of the fix: **7 hill groups intersect a corridor of x ±100,
  z −660 … −460, and removing them makes the walk line CLEAR.**

**What to build:**

A new module, **`src/ServerScriptService/MapProps/MapPass.lua`**, under 200 lines, single purpose:
*cut the sight-and-walk corridor to the portal gate through the horizon range, and dress the hole.*

1. `MapPass.Cut(zoneKey, cx, map)` runs **after `MapHorizon.Build` and `MapHorizon.TintWall`** —
   insert the call at `ForestMapService.lua:565-566`, and write in your comment *why it runs there*
   (Build creates the hills; a cut before it cuts nothing — rule 6).
2. It reads the hills `MapHorizon` already published (`MapHorizon.Placed[zoneKey]`, plus
   `MapHorizon.Colliders(zoneKey)` for the boxes) and finds every hill whose **world box**
   intersects the corridor **`x ∈ [cx − 100, cx + 100]`, `z ∈ [−660, −460]`**. Both numbers go in as
   named constants with the measurement above written next to them as the argument.
3. Each offender is **removed — and its collider box with it.** A hill deleted whose
   `HorizonHillCollider` survives is an invisible wall, which is complaint 32.15/32.19 all over
   again. Prefer removal over "push it sideways": a hill moved off the corridor lands on the next
   one.
4. **Dress the hole.** A bare hole in a mountain range reads as a bug, not as a pass. Put a rock
   pass around the gate — reuse the map's own rock stock the way `MapHorizon` does (`stockOf(map)`
   is its pattern): a small number of scaled, rotated, **seeded** rocks flanking the corridor mouth.
   This is the half that decides whether the owner accepts it.
5. **One boot line, and make it a test rather than a count**, in the house style:
   `print(("[MapPass] %s: cut %d hills from the portal corridor, dressed %d rocks, nearest rock now z %.1f (gate at %.1f)"):format(...))`
   — a number that shows the corridor is actually open, not merely that the code ran.

**Check (what Claude will run):** a sight ray and a body-box walk from the village up the main lane
to the gate report **0 blocked**, the gate is visible from the village in a capture, and the skyline
over the pass reads as dressed rock rather than bare wall.

**Do not:** change `LANE_PORTAL`; do not touch `MapHorizon.Build`'s run layout; do not delete
inner-row hills outside the corridor — the wall behind them is bare and it shows.

---

### T2 — Her new portal model is a Roblox **paid ad unit**, and it must not ship armed

She inserted `Workspace.Forest Portal Template` (200 × 165 × 143 at `(138, 379, −412)`, a floating
island) meaning it as decoration. Its three scripts were scanned and are clean. **But the model is
Roblox's *Portal Ad* unit:** `BasePortal.Door.AdPortal` and its `AdGui` display another experience's
advert and **teleport the player out of our game**.

**What to build** — in `MapPass.lua` if it still fits under 200 lines, otherwise
`src/ServerScriptService/MapProps/MapPortalArt.lua`:

1. On boot, walk the template and **destroy every `AdPortal` / `AdGui` / ad-serving descendant**, by
   class where possible and by name as a fallback. Log what it removed. If it removes nothing on a
   later boot it must still print `0` — a silent sanitiser is one nobody notices has stopped working.
2. Keep the **`Decorative` island** and use it as the **surround** for the existing gate. The door
   the player walks through stays **her own `PortalGate` / `ZoneGate`** (built by `MapPortals`),
   never the ad door.
3. Seat the island against the corridor mouth T1 opened, at the −Z gate — not at the arbitrary
   `(138, 379, −412)` it was dropped at.

**Check:** no `AdPortal` anywhere in the live tree after boot; the island frames the gate; walking
into the gate still runs our own zone teleport.

**If you are unsure exactly where the island should sit, ask — do not guess a pose and call it
done.** A wrong pose is the most common rejection on this project.

---

### T3 — Give Claude the probe that proves T1

You cannot run Studio, so write the check such that Claude can run it in one paste.

**File:** `tools/probe_portal_walk.lua` — a standalone Luau script meant to be pasted into Studio's
command bar. It must:

1. Walk a **body-sized box** (not a single ray — a point probe reports open air where a body does not
   fit) in 4-stud steps from the village spawn up the main lane to `PortalGate`, counting `samples`
   and `blocked`.
2. Separately cast a **sight ray** from player-eye height in the village to the gate, and print
   **what it hit, by full instance path** — the whole point of 32.28 is that the thing it hit was a
   hill nobody expected.
3. Print one summary line, then the **first 5 blocked samples with their coordinates and the
   instance that blocked them**. A probe that says "9 blocked" without saying *what* blocked is a
   probe that has to be run twice.
4. Touch nothing: read-only, no `Destroy`, no property writes.

Two traps this repo has already paid for, which your probe must avoid:

- A raycast that **starts inside a part misses that part** — begin each cast outside the body box.
- A box test that **counts the floor** as an obstruction once reported 15 of 32 cells blocked on a
  clear road. Start the box above the ground and give it a real body height.

---

## 7. If you get stuck

Write a `BLOCKED` entry in `agent-board/OX-LOG.md` saying exactly what you need, and stop. Do not
invent a measurement, do not widen a lane "to see if it helps", and do not refactor a file you were
not asked to touch. On this project the damage is almost never in the feature — it is in what came
along with it.
