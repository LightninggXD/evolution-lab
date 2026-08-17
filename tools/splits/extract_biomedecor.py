"""Move what a zone is DECORATED WITH out of ZoneBuilder into ServerScriptService/BiomeDecor.lua.

STEP 4 of `docs/SPLIT.md` §6, and the largest single cut this file will take: **2,443 lines**, 30%
of what is left of it, moved byte for byte.

WHAT THE PLAN SAID, AND WHY THE PIECES COME OUT TOGETHER
--------------------------------------------------------
§6 lists four separate leaves here -- "ground clutter (3,147), idols and ruins (3,463), the mesh
prop layer (5,172)" and, buried inside what the codemap calls the egg plaza, the twenty per-zone
decoration builders. Measured, they are not four leaves. They are one, and the measurement is the
argument:

  * `addGroundLitter`, `addGroundClutter`, `addMounds`, `addLandmark`, `addAtmosphere`,
    `addGlowPosts`, `addIdols` and `addRuins` are read by exactly one caller between them, and it
    is `buildBiomeBase` in the mesh-prop section. Cutting the clutter alone exports eight names to
    serve one call site;
  * `buildBiomeBase` in turn is read by exactly one thing: the twenty `decorationBuilders`;
  * and `decorationBuilders` is read by exactly one line in `Build()`.

So the whole layer has **one** name escaping it -- `decorationBuilders` -- and cutting it anywhere
other than at that line means inventing a surface that nothing asked for. Twenty-six top-level
names leave; one comes back.

THE TWENTY BUILDERS WERE NEVER IN ONE PLACE, which is the other thing this fixes. `Forest` is
written at 4,180 and `Desert` at 5,224, with **the entire egg section and the egg plaza in between**
-- 968 lines of unrelated code wedged into the middle of a list. Nothing chose that; it is where the
eggs happened to be pasted. Here the twenty are consecutive.

ACTIVE_ZONE_KEY IS THE ONE THING THAT COULD NOT BE RE-LOCALISED
---------------------------------------------------------------
It is reassigned per zone -- `ACTIVE_ZONE_KEY = zone.key` at the top of the zone's decoration pass
and `= nil` after it -- so a copy taken at require time would be frozen at nil forever, silently.
That is `docs/SPLIT.md` §3 rule 2, and it is the third time this codebase has paid for it
(`ACTIVE_FRAME` in `ZoneKit`, the village palette in `VillageKit`). It moves INTO this module,
where all nine of its readers live, and `ZoneBuilder`'s zone loop reaches it through
`BiomeDecor.setZoneKey(...)` -- the same shape as `ZoneKit.setFrame`.

Its old declaration also stops apologising. It sat at the top of `ZoneBuilder`, 3,700 lines above
`addMeshProps`, with a comment explaining that it had to be there because Lua binds an upvalue
where a function is WRITTEN. Behind a require there is no such line.

TWO STRANDED COMMENTS ARE PUT BACK, and neither is reworded:
  * the note introducing `EnsureSpawn` was sitting between the last decoration builder and the boss
    arena header, **732 lines** from the function it describes, which had none of its own;
  * the `ScatterKit` pointer written into this section an hour ago says "left this file", which
    stops being true for the file it is now in. It is rewritten for its new home; `ZoneBuilder`
    gets its own pointer where the section used to start.

NO GEOMETRY CHANGES, SO `BUILD_VERSION` IS NOT BUMPED. Same builders, same call order, same
`scatterBlocks`. The claim this move owes evidence for is a rebuild and a census, not a lint -- and
the two `ZoneKit.setFrame` sites that moved with it (the Volcano cone at cx - 150, the Celestial
throne at cx - 130) are the cheapest thing in the world to measure.
"""
import io
import re
import sys
from pathlib import Path

ROOT = Path(r"C:\Users\Kristina\Documents\evolution-lab")
ZB = ROOT / "src/ServerScriptService/ZoneBuilder.lua"
BD = ROOT / "src/ServerScriptService/BiomeDecor.lua"

# 1-indexed, inclusive.
ZONE_KEY = (238, 248)     # ACTIVE_ZONE_KEY, its note, and the blank after it
HELPERS = (1891, 2576)    # shared decoration helpers + ground clutter + idols and ruins
MESH = (3950, 4255)       # the mesh prop layer, buildBiomeBase, decorationBuilders, Forest
BUILDERS = (5224, 6669)   # the other nineteen
SPAWN_NOTE = (6670, 6673) # EnsureSpawn's comment, stranded 732 lines from EnsureSpawn

BOUNDS = [
    (238, "-- WHICH ZONE IS BEING BUILT RIGHT NOW, for the two builders that need a mesh keyed by zone and are"),
    (247, "local ACTIVE_ZONE_KEY = nil"),
    (248, ""),
    (1891, "-- ===== shared decoration helpers ====="),
    (2576, "end"),
    (2577, ""),
    (2578, "-- ====="),
    (3949, ""),
    (3950, "-- ===== THE MESH PROP LAYER ====="),
    (4254, "local desertStatueTemplate = ServerStorage:FindFirstChild(\"Models\")"),
    (4255, ""),
    (4256, "-- ===== EGGS ====="),
    (5223, ""),
    (5224, "decorationBuilders.Desert = function(model, zone, cx)"),
    (6669, ""),
    (6670, "-- Moves (or creates) the one canonical SpawnLocation onto the Forest arrival clearing. Called at"),
    (6673, "-- footprint would still strand a share of players inside the shop."),
    (6674, "-- ===== BOSS EVENT ARENA ====="),
]

# ---------------------------------------------------------------- the new module

BD_HEADER = '''-- BiomeDecor -- what each of the twenty zones is DRESSED IN, once its ground and its terraces
-- exist. Four shared layers and twenty signature builders that arrange them.
--
-- THE FOUR LAYERS, which is the whole design and is worth stating once: a GROUND layer of
-- scattered rocks and mounds, a MID layer of the zone's own props, one big LANDMARK silhouette at
-- the back of the platform, and an ATMOSPHERE emitter -- plus lighting accents, so no platform
-- ever reads as an empty coloured rectangle. `buildBiomeBase` takes one table describing all four
-- and builds them; a zone's builder is mostly that call plus whatever makes the zone itself.
--
-- WHERE THE LINE IS: this file owns what a zone is decorated WITH. `ZoneBuilder` owns the ground
-- it stands on, the terraces around it, the walls, the gates, the village, the eggs and the boss
-- arena -- and it owns the zone loop that calls in here, once per zone, through
-- `decorationBuilders[zone.key]`.
--
-- WHY IT IS ONE FILE AND NOT THE FOUR `docs/SPLIT.md` §6 ASKED FOR
-- ----------------------------------------------------------------
-- §6 names the ground clutter, the idols and the mesh prop layer as three separate leaves and the
-- decoration builders as a fourth. Measured, they are one thing wearing four section headers:
-- the eight `add*` layer verbs have exactly one caller between them (`buildBiomeBase`),
-- `buildBiomeBase` has exactly one set of callers (the twenty builders), and the twenty are read
-- by exactly one line in `Build()`. **One name escapes this file.** Cutting anywhere else would
-- mean inventing a surface nothing had asked for.
--
-- THE TWENTY WERE NOT IN ONE PLACE BEFORE THIS. `Forest` was written 1,000 lines above `Desert`
-- with the whole egg section and the egg plaza wedged between them -- not a decision, just where
-- the eggs got pasted. They are consecutive here, in zone order.
--
-- `ACTIVE_ZONE_KEY` LIVES HERE NOW AND IS REACHED THROUGH `setZoneKey`. It is reassigned per zone,
-- so a copy taken at require time would be frozen at nil forever and silently -- `docs/SPLIT.md`
-- §3 rule 2, the trap `ACTIVE_FRAME` and the village palette have each already paid for. All nine
-- of its readers are in this file; both of its writers are in `ZoneBuilder`'s zone loop.
--
-- WHO MAY REQUIRE IT: any server script decorating a zone platform. `ZoneBuilder` today. A caller
-- that runs `decorationBuilders[key]` without calling `setZoneKey(key)` first gets a zone with no
-- mesh props and no mesh landmark, and no error -- see `setZoneKey`.
--
-- Where the rest of the world is built: `docs/CODEMAP.md`, `docs/SPLIT.md` §6.

local ServerStorage = game:GetService("ServerStorage")

-- The vocabulary this file is written in. `ZoneKit` is what a part is made of; `ScatterKit` is
-- where a prop may stand and the ground it takes when it does. Both are re-localised for the
-- reason both of them give: `scatterPoint` alone is read 82 times below.
local ZoneKit = require(script.Parent.ZoneKit)
local ScatterKit = require(script.Parent.ScatterKit)

local newPart, addLight, seatModel = ZoneKit.newPart, ZoneKit.addLight, ZoneKit.seatModel
local lighten, darken = ZoneKit.lighten, ZoneKit.darken
local PLATFORM_DEPTH, PLATFORM_WIDTH = ZoneKit.PLATFORM_DEPTH, ZoneKit.PLATFORM_WIDTH
local scatterPoint, reserveScatter = ScatterKit.scatterPoint, ScatterKit.reserveScatter
local scaled, STREET_HALF = ScatterKit.scaled, ScatterKit.STREET_HALF

'''

BD_ZONE_KEY = '''-- ===== WHICH ZONE IS BEING BUILT RIGHT NOW =====
--
-- Two builders below need a mesh keyed by zone and are handed everything except the zone:
-- `addMeshProps` looks for `Prop_<key>_<slot>` and `addLandmark` for `Landmark_<key>`. Rather than
-- thread a zone through nine layers of table-driven config, the zone loop sets this around the
-- decoration pass and clears it after.
--
-- IT IS REACHED THROUGH `setZoneKey` AND NOT EXPORTED AS A VALUE, and that is not decoration: it
-- is reassigned per zone, so a copy taken at require time on the other side of the boundary would
-- be frozen at nil forever with nothing in the log -- `docs/SPLIT.md` §3 rule 2. `ZoneKit`'s
-- placement frame is the same shape for the same reason.
--
-- WHAT A MISSING CALL COSTS, so it is written down somewhere: nil is a legal value here and both
-- readers treat it as "no mesh available" and fall back to block-built geometry. A zone decorated
-- without `setZoneKey` therefore comes out looking slightly plain and entirely unbroken, which is
-- the failure mode you do not notice for a month.
local ACTIVE_ZONE_KEY = nil

local function setZoneKey(key)
	ACTIVE_ZONE_KEY = key
end

'''

BD_FOOTER = '''
-- One name and one verb. Everything above is reached through `decorationBuilders[zone.key]`, which
-- is the single line in `ZoneBuilder.Build()` that reads this file at all -- see the header for why
-- the surface is this small and not eight `add*` verbs wide.
return {
	decorationBuilders = decorationBuilders,
	setZoneKey = setZoneKey,
}
'''

# the ScatterKit pointer written into this section in 18.11, which now describes the wrong file
OLD_POINTER = """-- THE PLACEMENT RULES ARE IN `ScatterKit` (18.11). `scatterPoint`, `reserveScatter`, `scaled` and
-- the clearance geography they read all left this file; they arrive re-localised at the top, so
-- every call site below reads exactly as it did. `lighten` and `darken` went to `ZoneKit`, beside
-- `vivid`. What is left in this section is the layers those verbs are used to build."""

NEW_POINTER = """-- THE PLACEMENT RULES ARE IN `ScatterKit` and the colour verbs in `ZoneKit`; both arrive
-- re-localised at the top of this file. What follows is the four layers themselves, in the order
-- `buildBiomeBase` builds them."""

# ---------------------------------------------------------------- what ZoneBuilder gets instead

ZB_POINTER = '''-- ===== WHAT A ZONE IS DECORATED WITH LEFT THIS FILE (18.12) =====
--
-- `ServerScriptService.BiomeDecor` -- the four shared layers (`addGroundLitter`,
-- `addGroundClutter`, `addMounds`, `addLandmark`, `addAtmosphere`, `addGlowPosts`, plus the idols
-- and the ruins), the mesh prop layer and `buildBiomeBase` that arranges them, and all twenty
-- per-zone `decorationBuilders`. 2,443 lines and twenty-six top-level names, which took this file
-- from **159 of Luau's 200 registers to 134**.
--
-- ONE NAME COMES BACK, and that is the reason the cut is here and not in four places: every layer
-- verb has exactly one caller (`buildBiomeBase`), which has exactly one set of callers (the twenty
-- builders), which are read by exactly one line in `Build()` below.
--
-- WHAT DID NOT MOVE: the ground itself, the terraces, the walls and gates, the village, the eggs,
-- the egg plaza and the boss arena. This file still builds the zone; it no longer dresses it.
--
-- `ACTIVE_ZONE_KEY` WENT WITH IT AND IS SET THROUGH `BiomeDecor.setZoneKey`. It is reassigned per
-- zone, so it could not be re-localised in either direction -- `docs/SPLIT.md` §3 rule 2, the same
-- trap as `ZoneKit`'s placement frame. Both writers are in the zone loop at the bottom of this
-- file; all nine readers went with the builders.
local BiomeDecor = require(script.Parent.BiomeDecor)
local decorationBuilders = BiomeDecor.decorationBuilders'''


def cut(lines, lo, hi):
    return "\n".join(lines[lo - 1:hi])


def main():
    if BD.exists():
        sys.exit("BiomeDecor.lua already exists -- refusing to run twice")

    text = io.open(ZB, encoding="utf-8", newline="").read()
    lines = text.split("\n")

    for n, prefix in BOUNDS:
        got = lines[n - 1]
        assert got.startswith(prefix), "line %d: expected %r, got %r" % (n, prefix, got)

    helpers = cut(lines, *HELPERS)
    assert helpers.count(OLD_POINTER) == 1, "the 18.11 ScatterKit pointer is not where it was"
    helpers = helpers.replace(OLD_POINTER, NEW_POINTER, 1)

    body = helpers + "\n\n" + cut(lines, *MESH) + "\n\n" + cut(lines, *BUILDERS)

    # Nothing in the moved text may still reach for a name that stayed behind. `ZoneKit.setFrame`
    # is the only qualified call in 2,443 lines and it is required above.
    for stayed in ("GROUND_MATERIAL", "terrainCrestY", "buildPortal", "VillageKit",
                   "GameConfig", "PetModel", "CollectionService", "TweenService", "HttpService"):
        hits = [(i, l.strip()[:100]) for i, l in enumerate(body.split("\n"), 1)
                if re.search(r"(?<![\w.:])%s\b" % stayed, l) and not l.strip().startswith("--")]
        assert not hits, "%s is used in the moved text but stays in ZoneBuilder: %r" % (stayed, hits)

    # the three blocks each end on a blank line, so joining them doubles up at the two seams
    out = re.sub(r"\n\n\n+", "\n\n", BD_HEADER + BD_ZONE_KEY + body + "\n" + BD_FOOTER)
    BD.write_text(out, encoding="utf-8", newline="")

    # ---- what is left of ZoneBuilder
    drop = set()
    for f, l in (ZONE_KEY, HELPERS, MESH, BUILDERS, SPAWN_NOTE):
        drop.update(range(f, l + 1))

    out = []
    for i, line in enumerate(lines, 1):
        if i == HELPERS[0]:
            out.append(ZB_POINTER)
        if i not in drop:
            out.append(line)
    rest = "\n".join(out)

    # EnsureSpawn's own comment, put back on EnsureSpawn. Not reworded.
    note = cut(lines, *SPAWN_NOTE) + "\n"
    assert rest.count("\nfunction ZoneBuilder.EnsureSpawn()\n") == 1
    assert note not in rest
    rest = rest.replace("\nfunction ZoneBuilder.EnsureSpawn()\n",
                        "\n" + note + "function ZoneBuilder.EnsureSpawn()\n", 1)

    # the zone loop's two writes go through the accessor
    for old, new, count in (
        ("\t\t\tACTIVE_ZONE_KEY = zone.key\n", "\t\t\tBiomeDecor.setZoneKey(zone.key)\n", 1),
        ("\t\t\tACTIVE_ZONE_KEY = nil\n", "\t\t\tBiomeDecor.setZoneKey(nil)\n", 1),
    ):
        assert rest.count(old) == count, "%r: expected %d, found %d" % (old.strip(), count, rest.count(old))
        rest = rest.replace(old, new)

    for gone in ("local ACTIVE_ZONE_KEY", "local function addGroundLitter", "local ZONE_CLUTTER",
                 "local function addGroundClutter", "local function addMounds",
                 "local function addAtmosphere", "local function addGlowPosts",
                 "local function landmarkFigure", "local function addLandmark",
                 "local function buildIdol", "local function addIdols", "local function addRuins",
                 "local PROP_SLOTS", "local function addMeshProps", "local function buildBiomeBase",
                 "local decorationBuilders = {}", "decorationBuilders.", "local forestTreeTemplate",
                 "local desertCactusTemplate", "local petShopTemplate", "local desertStatueTemplate",
                 "local function reserveScatter"):
        assert gone not in rest, "%r still in ZoneBuilder" % gone
    survivors = [(i, l.strip()[:110]) for i, l in enumerate(rest.split("\n"), 1)
                 if "ACTIVE_ZONE_KEY" in l and not l.strip().startswith("--")]
    assert not survivors, "ACTIVE_ZONE_KEY survived in ZoneBuilder: %r" % survivors

    ZB.write_text(rest, encoding="utf-8", newline="")

    print("BiomeDecor.lua  %d lines" % (BD.read_text(encoding="utf-8").count("\n") + 1))
    print("ZoneBuilder     %d lines (was %d)" % (rest.count("\n") + 1, len(lines)))
    print()
    print("--- the twenty builders, in the order they now sit ---")
    for i, line in enumerate(BD.read_text(encoding="utf-8").split("\n"), 1):
        if line.startswith("decorationBuilders."):
            print("%5d  %s" % (i, line.split(" =")[0]))


main()
