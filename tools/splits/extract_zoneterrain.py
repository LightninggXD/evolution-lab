"""Move the valley walls out of ZoneBuilder into ServerScriptService/ZoneTerrain.lua.

STEP 5 of `docs/SPLIT.md` §6. 1,371 lines, and it takes out the single largest function in the
game: `buildValleySide` is 1,267 lines on its own, which `src/SYNC.md` has named "the actual
monolith" since the split was first argued about.

THE CLEANEST LEAF IN THE FILE, and it is clean because terrain is a different job from decoration.
Nothing it builds is a prop: it makes the ground the props stand on. So it consults no reservation
table, needs no zone key, and reads nothing from `ZoneBuilder` at all --

    ESCAPES: buildTerrain, terrainCrestY.
    IMPORTS: nine names, all of them already in `ZoneKit` (`newPart`, `groundColorOf`, `vivid`,
             `lighten`, `darken`, `addLight`, `TERRAIN_INNER`, `TERRAIN_OUTER`, `TERRAIN_DEPTH`),
             plus `ServerStorage` and ONE value, which is the only interesting decision here.

THAT ONE VALUE IS `GROUND_MATERIAL`, AND IT IS HANDED IN RATHER THAN MOVED. The obvious move is to
put it in `ZoneKit` beside `groundColorOf` -- the same question about the same floor -- and
`ZoneKit`'s own header refuses it in as many words:

  > WHAT IS AND IS NOT IN HERE. A rule every part in the world obeys is in here; a decision about
  > one zone is not. `GROUND_MATERIAL` -- which material each of the twenty floors is -- stays in
  > `ZoneBuilder`, and `groundColorOf` -- how bright ANY floor is allowed to be -- is here.

That line was drawn deliberately (17.7) and this commit is not the place to reverse it. The terrace
treads read the table at exactly ONE site, so the material arrives as a parameter:
`buildTerrain(model, zone, cx, groundMaterial)`, threaded on to `buildValleySide`. One value at one
call site is not the `ZoneDecor` shape `src/SYNC.md` warns about -- that was 29 helpers passed by
hand with a second list to keep in step -- and it leaves the table where the design says it lives.

`terrainCrestY` STOPS BEING A FORWARD DECLARATION. It was `local terrainCrestY` at the top of
`ZoneBuilder` with a note explaining that it had to be, because `addRockRampart` is written eight
hundred lines above the table it reads. The wall asks the terrain how high the terrace band stands
where the two meet, and that is a question across a boundary now: `ZoneTerrain.crestY(zone.key)`.
Both of its call sites are spelled out rather than re-localised -- there are two, and `VillageKit`'s
rule applies (at fifteen call sites, spelling out the module name is worth its four characters and
tells the next reader where the thing lives).

NO GEOMETRY CHANGES, SO `BUILD_VERSION` IS NOT BUMPED. The evidence this owes is the same census
the `ZoneKit` cut owed and for the same reason -- a terrace that has moved is invisible to every
lint in this repo: `TerraceTop` 784/784 solid, `ValleyRock` 410/410 with `ValleyRockBase` 0/410,
and the Absolute Plane's floor back at rgb(204,204,204) Marble, which is the one this commit could
break on its own if `GROUND_MATERIAL` arrived empty.
"""
import io
import re
import sys
from pathlib import Path

ROOT = Path(r"C:\Users\Kristina\Documents\evolution-lab")
ZB = ROOT / "src/ServerScriptService/ZoneBuilder.lua"
ZT = ROOT / "src/ServerScriptService/ZoneTerrain.lua"

# 1-indexed, inclusive.
CREST_DECL = (238, 243)   # the `local terrainCrestY` forward declaration and its note
TERRAIN = (1902, 3272)    # the whole TERRAIN section

BOUNDS = [
    (172, "local GROUND_MATERIAL = {"),
    (238, "-- Forward-declared for the same reason, and needed by the WALLS."),
    (242, "local terrainCrestY"),
    (243, ""),
    (1902, "-- ====="),
    (1903, "-- TERRAIN: the valley walls"),
    (3272, "end"),
    (3273, ""),
    (3274, "-- ===== EGGS ====="),
]

# ---------------------------------------------------------------- the new module

ZT_HEADER = '''-- ZoneTerrain -- the valley walls. The ground a zone is built ON, as opposed to everything that
-- is later stood on top of it.
--
-- Every zone was a flat slab with props on it. What is built here is a VALLEY: flat floor down the
-- middle where you actually play, rising through stacked terraces to cliffs at both edges, with
-- the boundary wall behind them. `buildValleySide` does one side and is called twice.
--
-- WHERE THE LINE IS: this file makes ground. `BiomeDecor` dresses it, `ZoneBuilder` walls it and
-- puts the buildings on it. Nothing here is a prop, which is why this is the one section of the
-- world builder that needed nothing from the rest of it: no reservation table, no zone key, no
-- village palette. Its whole vocabulary is `ZoneKit`.
--
-- IT HOLDS THE BIGGEST FUNCTION IN THE GAME. `buildValleySide` is ~1,270 lines and
-- `docs/CODEMAP.md` is how to read it without opening the file; the tier arithmetic is documented
-- in the block above it, which is worth reading before changing any number in this file. Two rules
-- from it that are load-bearing and easy to undo:
--
--   * NO TIER MAY BE LOWER THAN A MAXED JUMP -- a fully upgraded player's apex is 21.6 studs, so a
--     shelf below that is a shelf players stand on and see the seams of;
--   * a tier's usable tread ends at the NEXT tier's edge, which is the line that stops props being
--     buried in the cliffs.
--
-- WHO MAY REQUIRE IT: `ZoneBuilder`, which calls `buildTerrain` once per zone -- and `crestY`,
-- which is the wall asking the terrain how high the terrace band stands where the two meet. That
-- second one used to be a forward declaration at the top of `ZoneBuilder`, because
-- `addRockRampart` is written far above the table it reads; across a require there is no such
-- line, and the note the declaration carried is not needed any more.
--
-- Where the rest of the world is built: `docs/CODEMAP.md`, `docs/SPLIT.md` §6.

local ServerStorage = game:GetService("ServerStorage")

local ZoneKit = require(script.Parent.ZoneKit)

local newPart, groundColorOf, vivid = ZoneKit.newPart, ZoneKit.groundColorOf, ZoneKit.vivid
local lighten, darken, addLight = ZoneKit.lighten, ZoneKit.darken, ZoneKit.addLight
local TERRAIN_INNER, TERRAIN_OUTER = ZoneKit.TERRAIN_INNER, ZoneKit.TERRAIN_OUTER
local TERRAIN_DEPTH = ZoneKit.TERRAIN_DEPTH

-- NOTHING ELSE IS REQUIRED, AND ONE THING THAT COULD HAVE BEEN IS HANDED IN INSTEAD. The terrace
-- treads want to be made of the same material as the zone floor, which is `GROUND_MATERIAL` in
-- `ZoneBuilder` -- a per-zone table that `ZoneKit`'s header explicitly declines to hold, because a
-- decision about one zone is not a rule every part obeys. It arrives as the fourth argument to
-- `buildTerrain` rather than moving house to suit this file.

'''

ZT_FOOTER = '''
-- `buildValleySide` and `TERRAIN_PROFILE` are deliberately NOT exported: one side of one zone is
-- not a thing anybody outside this file has ever wanted, and the profile is only meaningful
-- alongside the arithmetic that reads it.
return {
	buildTerrain = buildTerrain,
	crestY = terrainCrestY,
}
'''

# ---------------------------------------------------------------- what ZoneBuilder gets instead

ZB_POINTER = '''-- ===== THE GROUND ITSELF LEFT THIS FILE (18.13) =====
--
-- `ServerScriptService.ZoneTerrain` -- `TERRAIN_PROFILE`, `terrainCrestY`, `buildValleySide` (the
-- largest function in the game at ~1,270 lines) and `buildTerrain`. 1,371 lines, and the cleanest
-- cut this file has taken: terrain is not decoration, so it consults no reservation table, needs no
-- zone key and imported nothing from here that was not already `ZoneKit`'s.
--
-- SPELLED OUT RATHER THAN RE-LOCALISED, unlike `ZoneKit` and `ScatterKit`: there are exactly two
-- call sites. `ZoneTerrain.buildTerrain(...)` in the zone loop, and `ZoneTerrain.crestY(...)` in
-- `addRockRampart` above -- which is the wall asking the ground how high the terrace band stands
-- where the two meet, and is why `terrainCrestY` needed a forward declaration here for so long.
local ZoneTerrain = require(script.Parent.ZoneTerrain)'''

ZB_TERRAIN_POINTER = '''-- ============================================================================
-- TERRAIN: the valley walls -- IN `ZoneTerrain` SINCE 18.13
-- ============================================================================
-- The terraces, the cliffs, the waterfalls and the pools are all built by
-- `ServerScriptService.ZoneTerrain` now; see the require above `addWallDecor`. `buildTerrain` is
-- still called once per zone from the loop at the bottom of this file, in the same place, and
-- `addRockRampart` still asks it for the crest height. Its one new argument is the zone's floor
-- material: `GROUND_MATERIAL` is a per-zone decision and stays here, so the terrace treads are
-- handed the one value they wanted rather than the table moving house. What is below this line is
-- what STANDS on that ground.'''


def cut(lines, lo, hi):
    return "\n".join(lines[lo - 1:hi])


def main():
    if ZT.exists():
        sys.exit("ZoneTerrain.lua already exists -- refusing to run twice")

    text = io.open(ZB, encoding="utf-8", newline="").read()
    lines = text.split("\n")

    for n, prefix in BOUNDS:
        got = lines[n - 1]
        assert got.startswith(prefix), "line %d: expected %r, got %r" % (n, prefix, got)

    body = cut(lines, *TERRAIN)

    # `function terrainCrestY(...)` filled ZoneBuilder's forward declaration; here it owns itself
    assert body.count("\nfunction terrainCrestY(zoneKey)\n") == 1
    body = body.replace("\nfunction terrainCrestY(zoneKey)\n",
                        "\nlocal function terrainCrestY(zoneKey)\n", 1)

    # the zone's floor material is threaded in rather than moved -- see the docstring
    for old, new, count in (
        ("local function buildValleySide(model, zone, cx, side, p)\n",
         "-- `groundMaterial` is `GROUND_MATERIAL[zone.key]`, handed in by `ZoneBuilder` because that\n"
         "-- table is a per-zone decision and stays there. See the note at the top of this file.\n"
         "local function buildValleySide(model, zone, cx, side, p, groundMaterial)\n", 1),
        ("\tlocal ground = GROUND_MATERIAL[zone.key] or Enum.Material.Grass\n",
         "\tlocal ground = groundMaterial or Enum.Material.Grass\n", 1),
        ("local function buildTerrain(model, zone, cx)\n",
         "local function buildTerrain(model, zone, cx, groundMaterial)\n", 1),
        ("\t\tbuildValleySide(model, zone, cx, side, p)\n",
         "\t\tbuildValleySide(model, zone, cx, side, p, groundMaterial)\n", 1),
    ):
        assert body.count(old) == count, "%r: expected %d, found %d" % (old.strip()[:60], count, body.count(old))
        body = body.replace(old, new)

    for stayed in ("scatterPoint", "reserveScatter", "scaled", "VillageKit", "BiomeDecor",
                   "decorationBuilders", "GameConfig", "PetModel", "CollectionService",
                   "TweenService", "buildPortal", "SHOP_Z", "GROUND_MATERIAL"):
        hits = [(i, l.strip()[:100]) for i, l in enumerate(body.split("\n"), 1)
                if re.search(r"(?<![\w.:])%s\b" % stayed, l) and not l.strip().startswith("--")]
        assert not hits, "%s is used in the moved text but stays in ZoneBuilder: %r" % (stayed, hits)

    ZT.write_text(re.sub(r"\n\n\n+", "\n\n", ZT_HEADER + body + "\n" + ZT_FOOTER),
                  encoding="utf-8", newline="")

    # ---- what is left of ZoneBuilder
    drop = set()
    for f, l in (CREST_DECL, TERRAIN):
        drop.update(range(f, l + 1))

    out = []
    for i, line in enumerate(lines, 1):
        if i == CREST_DECL[0]:
            out.append(ZB_POINTER)
            out.append("")
        if i == TERRAIN[0]:
            out.append(ZB_TERRAIN_POINTER)
        if i not in drop:
            out.append(line)
    rest = "\n".join(out)

    for old, new, count in (
        ("\tlocal crest = terrainCrestY(zone.key)\n", "\tlocal crest = ZoneTerrain.crestY(zone.key)\n", 1),
        ("\t\t\tbuildTerrain(model, zone, cx)\n",
         "\t\t\tZoneTerrain.buildTerrain(model, zone, cx, GROUND_MATERIAL[zone.key])\n", 1),
    ):
        assert rest.count(old) == count, "%r: expected %d, found %d" % (old.strip(), count, rest.count(old))
        rest = rest.replace(old, new)
    # the table stays; the two reads that stayed with it are the zone floor and the arena floor
    hits = re.findall(r"(?<![\w.:])GROUND_MATERIAL\[", rest)
    assert len(hits) == 3, "expected three GROUND_MATERIAL reads left, found %d" % len(hits)

    for gone in ("local terrainCrestY", "function terrainCrestY(",
                 "local TERRAIN_PROFILE", "local function buildValleySide",
                 "local function buildTerrain"):
        assert gone not in rest, "%r still in ZoneBuilder" % gone

    ZB.write_text(rest, encoding="utf-8", newline="")

    print("ZoneTerrain.lua %d lines" % (ZT.read_text(encoding="utf-8").count("\n") + 1))
    print("ZoneBuilder     %d lines (was %d)" % (rest.count("\n") + 1, len(lines)))


main()
