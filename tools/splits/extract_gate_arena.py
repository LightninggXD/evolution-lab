"""Move the boundary gateway and the boss arena out of ZoneBuilder into
ServerScriptService/ZoneGate.lua and ServerScriptService/EventArena.lua.

STEP 7 of `docs/SPLIT.md` §6, and the last one. Two files in one commit because the second needs
the first: the arena's way home is built through the same `buildPortal` as every zone boundary,
which is the only thing it ever wanted from `ZoneBuilder`.

  ZoneGate    280 lines, 9 top-level names out, 3 back (`buildPortal`, `buildPortalInZWall`,
              `PORTAL_CLEAR_HALF`). Imports nothing but `ZoneKit`.
  EventArena  596 lines, 3 names out plus `ARENA_VERSION`, 1 back. Imports `ZoneKit`,
              `VillageKit` (for `candy`, on the bunting), `ZoneGate`, and three services.

THE ARENA IS NOT PART OF A ZONE AND NEVER WAS. It sits straight through the gate at the Forest
spawn, is reached by teleport and no other way, and carries its own version stamp precisely so it
can be rebuilt without dropping all twenty-one zones -- 900 parts against 60,000. It has been the
most obviously separate thing in this file since it was written; it just had nowhere to go.

`ARENA_VERSION` GOES WITH IT AND IS EXPORTED, because `Build()` reads it to decide whether the
arena standing in the world is stale. That is the arena's own version of the `BUILD_VERSION`
question and it belongs beside the thing it stamps -- the comment explaining why it is separate
from `BUILD_VERSION` at all travels unchanged.

`PORTAL_CLEAR_HALF` IS EXPORTED FOR THE CLIFFS, not for the gate. It is how far boulders stay off
the centre line, read twice by `addRockRampart` in `ZoneBuilder` and never inside `ZoneGate`. A
number that only its neighbours read is still the gate's decision: it is the gate's width that sets
it.

NO GEOMETRY CHANGES, SO `BUILD_VERSION` IS NOT BUMPED, and `ARENA_VERSION` is not either -- an
arena already standing in a world is still current, which is the whole point of a stamp that means
"what this code builds", not "when this code was edited". Evidence owed: walk a gate, and look at
the arena. Both are pictures, so both need a capture.
"""
import io
import re
import sys
from pathlib import Path

ROOT = Path(r"C:\Users\Kristina\Documents\evolution-lab")
ZB = ROOT / "src/ServerScriptService/ZoneBuilder.lua"
ZG = ROOT / "src/ServerScriptService/ZoneGate.lua"
EA = ROOT / "src/ServerScriptService/EventArena.lua"

ARENA_STAMP = (68, 73)    # ARENA_VERSION, its note, and the blank after it
GATE = (262, 541)         # -- ===== portal gateway ===== through buildPortalInZWall
ARENA = (1935, 2530)      # -- ===== BOSS EVENT ARENA ===== through the end of buildEventArena

BOUNDS = [
    (68, "-- The Colosseum carries its own stamp."),
    (72, "local ARENA_VERSION = 2"),
    (73, ""),
    (74, "-- ================= the build vocabulary ================="),
    (261, ""),
    (262, "-- ===== portal gateway ====="),
    (540, "end"),
    (541, ""),
    (542, "-- ===== BOUNDARY CLIFFS"),
    (1934, ""),
    (1935, "-- ===== BOSS EVENT ARENA ====="),
    (2529, "end"),
    (2530, ""),
    (2531, "-- ===== WHAT MUST NEVER STREAM OUT"),
]

ZG_HEADER = '''-- ZoneGate -- the doorway between two zones.
--
-- Twenty-one platforms in a line, and the only way from one to the next is through the gap in the
-- wall between them. That gap is the most-looked-at object in the game after the egg stall: every
-- player walks through forty of them on the way to the end, so it is built as real stonework --
-- jambs, a lintel, a keystone, a lit arch and a name board -- instead of a hole.
--
-- WHERE THE LINE IS: this file builds a gateway. `ZoneBuilder` decides which walls have one and
-- what is on the other side. `buildPortal` is written in the plane x = wallX with local +X pointing
-- at the interior; `buildPortalInZWall` is the same gateway turned a quarter and stood in a Z wall,
-- and it is a separate function only because that rotation is easy to get backwards.
--
-- WHO REQUIRES IT: `ZoneBuilder`, for the walls -- and `EventArena`, whose way home is the same
-- gateway. That second caller is why this is a file of its own rather than more of `ZoneBuilder`:
-- the arena is not part of a zone and should not have to reach into the zone builder for a door.
--
-- `PORTAL_CLEAR_HALF` IS EXPORTED AND IS NOT USED IN HERE. It is how far the boundary boulders stay
-- off the centre line, read by `addRockRampart` in `ZoneBuilder`. It lives here because it is the
-- GATE's width that decides it.
--
-- Where the rest of the world is built: `docs/CODEMAP.md`, `docs/SPLIT.md` §6.

local ZoneKit = require(script.Parent.ZoneKit)

local newPart, addPlankText, vivid = ZoneKit.newPart, ZoneKit.addPlankText, ZoneKit.vivid
local spinForever, pulseForever = ZoneKit.spinForever, ZoneKit.pulseForever
local addLight, PORTAL_GAP = ZoneKit.addLight, ZoneKit.PORTAL_GAP

'''

ZG_FOOTER = '''
return {
	buildPortal = buildPortal,
	buildPortalInZWall = buildPortalInZWall,
	PORTAL_CLEAR_HALF = PORTAL_CLEAR_HALF,
}
'''

EA_HEADER = '''-- EventArena -- the Colosseum, which is not in a zone and never was.
--
-- A round sand pit with a raised dais in the middle, ringed by a stepped stand, torch pylons and
-- banners. It sits straight through the gate at the Forest spawn (`GameConfig.EventArena.centre`)
-- and is reached by teleport and no other way, which is why it can be that far off the zone strip
-- and cost nothing.
--
-- WHY IT IS ITS OWN FILE: it is the one thing `ZoneBuilder` builds that is not part of a zone. It
-- has its own version stamp for the same reason -- bumping `BUILD_VERSION` drops all twenty-one
-- zones and rebuilds ~60,000 parts, and the arena is ~900. It has been separate in every sense but
-- the physical one since it was written.
--
-- EVERYTHING IS LAID OUT FROM THE CENTRE OUTWARD BY ANGLE, so the whole thing is four loops rather
-- than a hand-placed floor plan, and it stays perfectly circular at any radius. The dressing
-- helpers below are stated in the arena's own polar terms (an angle and a radius out from one
-- centre), which is why they are here and not in `ZoneKit`: nothing else in the world is a circular
-- amphitheatre.
--
-- THE WAY HOME IS A `ZoneGate`, the same gateway every zone boundary is built from. That shared
-- door is why `ZoneGate` came out as a file of its own in the same commit as this one.
--
-- Where the rest of the world is built: `docs/CODEMAP.md`, `docs/SPLIT.md` §6.

local RS = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local GameConfig = require(RS.Modules.GameConfig)

local ZoneKit = require(script.Parent.ZoneKit)
local VillageKit = require(script.Parent.VillageKit)
local ZoneGate = require(script.Parent.ZoneGate)

local newPart, addLight = ZoneKit.newPart, ZoneKit.addLight
local pulseForever, vivid = ZoneKit.pulseForever, ZoneKit.vivid

'''

EA_FOOTER = '''
-- `ARENA_VERSION` is exported because `ZoneBuilder.Build()` reads it to decide whether the arena
-- standing in the world was built by this code. It is the arena's own answer to the question
-- `BUILD_VERSION` answers for the zones, and it belongs beside the thing it stamps.
return {
	buildEventArena = buildEventArena,
	ARENA_VERSION = ARENA_VERSION,
}
'''

ZB_GATE_POINTER = '''-- ===== THE GATEWAY LEFT THIS FILE (18.15) =====
--
-- `ServerScriptService.ZoneGate` -- `buildPortal`, `buildPortalInZWall` and the seven names behind
-- them, plus `PORTAL_CLEAR_HALF`, which is how far the boundary boulders stay off the centre line
-- and is exported back because `addRockRampart` below reads it. 280 lines.
--
-- IT WENT BECAUSE IT HAS TWO CALLERS, and the second one is not a zone: the boss arena's way home
-- is the same gateway, and an arena in its own file should not have to reach into the zone builder
-- for a door.
local ZoneGate = require(script.Parent.ZoneGate)
local PORTAL_CLEAR_HALF = ZoneGate.PORTAL_CLEAR_HALF'''

ZB_ARENA_POINTER = '''-- ===== THE COLOSSEUM LEFT THIS FILE (18.15) =====
--
-- `ServerScriptService.EventArena` -- `buildEventArena`, the two polar dressing helpers, and
-- `ARENA_VERSION` with the note explaining why it is a separate stamp from `BUILD_VERSION`.
-- 596 lines.
--
-- IT IS THE ONE THING THIS FILE BUILT THAT IS NOT PART OF A ZONE. It sits off the strip, is reached
-- by teleport only, and is rebuilt on its own stamp because dropping it costs 900 parts where
-- dropping the zones costs 60,000. `Build()` below still owns the decision of when to rebuild it,
-- and reads `EventArena.ARENA_VERSION` to make it.
local EventArena = require(script.Parent.EventArena)'''


def cut(lines, lo, hi):
    return "\n".join(lines[lo - 1:hi])


def main():
    for p in (ZG, EA):
        if p.exists():
            sys.exit("%s already exists -- refusing to run twice" % p.name)

    text = io.open(ZB, encoding="utf-8", newline="").read()
    lines = text.split("\n")
    for n, prefix in BOUNDS:
        got = lines[n - 1]
        assert got.startswith(prefix), "line %d: expected %r, got %r" % (n, prefix, got)

    gate = cut(lines, *GATE)
    arena = cut(lines, ARENA_STAMP[0], ARENA_STAMP[1] - 1) + "\n\n" + cut(lines, *ARENA)

    # the arena's one call into the gateway is now a call across a boundary
    assert arena.count("\tbuildPortal(model, 0, returnTarget, 1)\n") == 1
    arena = arena.replace("\tbuildPortal(model, 0, returnTarget, 1)\n",
                          "\tZoneGate.buildPortal(model, 0, returnTarget, 1)\n", 1)

    for body, name, stayed in (
        (gate, "ZoneGate", ("ServerStorage", "GameConfig", "CollectionService", "TweenService",
                            "PetModel", "VillageKit", "ScatterKit", "scatterPoint", "EggPlaza",
                            "ZoneTerrain", "BiomeDecor", "GROUND_MATERIAL", "ARENA_VERSION")),
        (arena, "EventArena", ("TweenService", "PetModel", "ScatterKit", "scatterPoint", "EggPlaza",
                               "ZoneTerrain", "BiomeDecor", "GROUND_MATERIAL", "SHOP_Z",
                               "PORTAL_CLEAR_HALF", "buildPortalInZWall")),
    ):
        for gone in stayed:
            hits = [(i, l.strip()[:100]) for i, l in enumerate(body.split("\n"), 1)
                    if re.search(r"(?<![\w.:])%s\b" % gone, l) and not l.strip().startswith("--")]
            assert not hits, "%s uses %s, which stays in ZoneBuilder: %r" % (name, gone, hits)

    ZG.write_text(re.sub(r"\n\n\n+", "\n\n", ZG_HEADER + gate + "\n" + ZG_FOOTER),
                  encoding="utf-8", newline="")
    EA.write_text(re.sub(r"\n\n\n+", "\n\n", EA_HEADER + arena + "\n" + EA_FOOTER),
                  encoding="utf-8", newline="")

    drop = set()
    for f, l in (ARENA_STAMP, GATE, ARENA):
        drop.update(range(f, l + 1))

    out = []
    for i, line in enumerate(lines, 1):
        if i == GATE[0]:
            out.append(ZB_GATE_POINTER)
            out.append("")
        if i == ARENA[0]:
            out.append(ZB_ARENA_POINTER)
            out.append("")
        if i not in drop:
            out.append(line)
    rest = "\n".join(out)

    for pat, new, count in (
        (r"(?<![\w.:])buildPortalInZWall\(", "ZoneGate.buildPortalInZWall(", 1),
        (r"(?<![\w.:])buildPortal\(", "ZoneGate.buildPortal(", 1),
        (r"(?<![\w.:])buildEventArena\(", "EventArena.buildEventArena(", 1),
        (r"(?<![\w.:])ARENA_VERSION\b", "EventArena.ARENA_VERSION", 3),
    ):
        found = len(re.findall(pat, rest))
        assert found == count, "%s: expected %d, found %d" % (pat, count, found)
        rest = re.sub(pat, new, rest)

    for gone in ("local ARENA_VERSION",
                 "local function buildPortal", "local function buildPortalInZWall",
                 "local function buildEventArena", "local function coloMesh",
                 "local function coloDisc"):
        assert gone not in rest, "%r still in ZoneBuilder" % gone

    ZB.write_text(rest, encoding="utf-8", newline="")

    print("ZoneGate.lua    %d lines" % (ZG.read_text(encoding="utf-8").count("\n") + 1))
    print("EventArena.lua  %d lines" % (EA.read_text(encoding="utf-8").count("\n") + 1))
    print("ZoneBuilder     %d lines (was %d)" % (rest.count("\n") + 1, len(lines)))


main()
