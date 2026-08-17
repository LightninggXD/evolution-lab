"""Move the platform's placement rules out of ZoneBuilder into ServerScriptService/ScatterKit.lua,
and the two colour one-liners into ZoneKit beside `vivid`.

STEP 3 of `docs/SPLIT.md` §6, and it is the ENABLER rather than a leaf. Nothing about it is
worth 200 lines on its own; what it buys is that every leaf after it can be cut.

WHY THIS COMES BEFORE THE LEAVES
--------------------------------
Measured across the four remaining leaves, `scatterPoint` is read **81 times inside the biome
layer alone** and `darken` / `lighten` 17 and 15. Every candidate cut needs them, and there are
only two ways a leaf can get a name that lives in its host:

  * hand it over at require time -- which is the `ZoneDecor` shape, 29 helpers passed in by hand,
    and `src/SYNC.md` records what that cost;
  * or move it somewhere both sides can require.

`newPart` went the second way in 18.9 and the village palette in 18.10. This does the same for the
last shared vocabulary in the file, and it is the one that could NOT have gone into `ZoneKit`:

    ScatterKit HAS STATE.  `scatterBlocks` is a live table of ground already taken, cleared once
    per zone and appended to by every prop that is big enough to walk around.

`ZoneKit` is a vocabulary -- `newPart`, `vivid`, the sign palette -- and is stateless but for the
placement frame. A reservation table is a different kind of thing and gets a different file, so
that "who cleared this and when" has one answer and one home. The clear is `addGroundDetail`'s and
stays there; it just calls `ScatterKit.clearReservations()` now instead of reaching into a table.

WHAT MOVES, AND WHERE IT CAME FROM
----------------------------------
To `ScatterKit`:
  * the platform's clearance geography -- `DECO_SPREAD_X/Z`, `CLEAR_HALF`, `ARRIVAL_Z`,
    `ARRIVAL_CLEAR`, `STREET_HALF`, `BOSS_Z`, `BOSS_CLEAR` -- which is one set of numbers
    describing where a prop may NOT stand, and reads as one set for the first time here;
  * `scatterBlocks` + `reserveScatter`, which were declared 1,000 lines above the note that
    explains them, with a comment apologising for it. That comment's reason ("the props that
    register with it are built from this point onwards") stops being true the moment it is behind
    a require, and it is kept, quoted, at the top of the new file for the trap it records;
  * `scatterPoint` itself and its `LEGACY_SPREAD_*` / `DEFAULT_HALF` rescaling;
  * `DENSITY` + `scaled`.

To `ZoneKit`, beside `vivid`, because a colour verb belongs with the other colour verb:
  * `lighten` and `darken`. Four lines, 24 call sites in `ZoneBuilder` and more in every leaf.

SIXTEEN TOP-LEVEL NAMES LEAVE AND SIX COME BACK, so `ZoneBuilder` goes 169 -> 159 of Luau's 200
registers. Re-localised on the builder's side for the reason `ZoneKit` gives: `scatterPoint` has
109 call sites and rewriting them would be 109 chances to break the world for nothing visible.

NO GEOMETRY CHANGES, SO `BUILD_VERSION` IS NOT BUMPED. Same numbers, same function bodies, same
call order -- and the same single `scatterBlocks` table, which is the one thing this move could
plausibly break and the thing the verification has to look at.
"""
import io
import re
import sys
from pathlib import Path

ROOT = Path(r"C:\Users\Kristina\Documents\evolution-lab")
ZB = ROOT / "src/ServerScriptService/ZoneBuilder.lua"
ZK = ROOT / "src/ServerScriptService/ZoneKit.lua"
SK = ROOT / "src/ServerScriptService/ScatterKit.lua"

# 1-indexed, inclusive.
FWD_DECL = (226, 234)        # the `local scatterPoint` forward declaration, comment and all
BLOCKS_NOTE = (880, 882)     # scatterBlocks' comment, stranded above SHOP_Z's
BLOCKS = (893, 896)          # local scatterBlocks + reserveScatter
GEOGRAPHY = (1890, 1923)     # the clearance constants and everything explaining them
COLOURS = (1925, 1931)       # lighten + darken -> ZoneKit
SCATTER = (1933, 2081)       # the halfSize note, scatterPoint, DENSITY, scaled

BOUNDS = [
    (226, "-- Forward-declared. `scatterPoint` is defined in the shared-decoration section far below, but the"),
    (233, "local scatterPoint"),
    (234, ""),
    (880, "-- Ground already claimed by something big, in WORLD coordinates. See the longer note further down,"),
    (882, "-- register with it are built from this point in the file onwards."),
    (893, "local scatterBlocks = {}"),
    (896, "end"),
    (1890, "-- THE VALLEY FLOOR, not the whole platform."),
    (1923, "local BOSS_CLEAR = GameConfig.BossStationClear"),
    (1925, "local function lighten(c, t)"),
    (1931, "end"),
    (1933, "-- Random point on the platform that is never inside the reserved central square and never"),
    (2081, "end"),
    (2082, ""),
    (2083, "-- GROUND LAYER: low scattered rocks / shards / debris that break up the flat floor."),
]

# ---------------------------------------------------------------- the new module

SK_HEADER = '''-- ScatterKit -- where a prop may stand, and the ground it takes when it does.
--
-- One question, asked ninety-odd times per zone: give me a point on this platform that is not in
-- the walkway, not in either gate mouth, not on the boss's dais, not in the middle where the pet
-- shop is, and not inside anything that has already been put down. `scatterPoint` answers it and
-- `reserveScatter` is how the answer stays true for the next caller.
--
-- WHY THIS IS NOT IN `ZoneKit`: it has STATE. `ZoneKit` is a vocabulary -- what a part is made of,
-- what a sign looks like, how big the platform is -- and it is stateless but for the placement
-- frame. `scatterBlocks` is a live table of ground already claimed, cleared once per zone and
-- appended to by every prop big enough that you have to walk around it. "Who cleared this table,
-- and when" is a question worth being able to answer in one file.
--
-- THE OWNER OF THE CLEAR IS STILL `ZoneBuilder`. `addGroundDetail` is the first thing built on a
-- zone's ground and it calls `ScatterKit.clearReservations()` there, exactly where it used to call
-- `table.clear(scatterBlocks)`. The scope the table belongs to did not change; only the file did.
--
-- WHAT THE OLD DECLARATION SITE WAS APOLOGISING FOR, kept because it is the trap and not the fix:
--
--   > Ground already claimed by something big, in WORLD coordinates. See the longer note further
--   > down, beside scatterPoint, for what this is for. Declared here rather than there because the
--   > props that register with it are built from this point in the file onwards.
--
-- That is a `local`'s line number leaking into the design: the table sat a thousand lines above
-- the comment that explained it, in the middle of an unrelated section, because Lua binds an
-- upvalue where a function is WRITTEN. Behind a require there is no such line and no such
-- constraint -- the same thing the village palette's move bought in 18.10.
--
-- WHO MAY REQUIRE IT: any server script placing props on a zone platform. `ZoneBuilder` today.
-- Anything that starts calling `scatterPoint` also inherits `clearReservations`, and the zone loop
-- is the only place that may call it.
--
-- Where the rest of the world is built: `docs/CODEMAP.md`, `docs/SPLIT.md` §6.

local RS = game:GetService("ReplicatedStorage")
local GameConfig = require(RS.Modules.GameConfig)

'''

SK_RESERVATIONS = '''-- ===== THE RESERVATION TABLE =====
--
-- World coordinates, so an entry left over from the previous zone could never match anything in
-- this one anyway; the clear is for the table's size, not for correctness.
local scatterBlocks = {}

local function reserveScatter(x, z, radius)
	scatterBlocks[#scatterBlocks + 1] = { x = x, z = z, r = radius }
end

-- Called once per zone, by `addGroundDetail`, which is the first thing built on a zone's ground.
-- It is a verb rather than an exported table for one reason: an exported `scatterBlocks` could be
-- cleared by anybody, and the bug this system was built to fix (11.27) was precisely that the
-- clear happened at the wrong point in the build.
local function clearReservations()
	table.clear(scatterBlocks)
end

'''

SK_FOOTER = '''
-- `scatterBlocks` itself is deliberately NOT exported -- see `clearReservations` for why. Nor are
-- the geography constants that only `scatterPoint` reads (`DECO_SPREAD_*`, `CLEAR_HALF`,
-- `ARRIVAL_CLEAR`, `BOSS_CLEAR`, `LEGACY_SPREAD_*`, `DEFAULT_HALF`, `DENSITY`); the two below are
-- out because `ZoneBuilder` places hand-built things against them.
return {
	scatterPoint = scatterPoint,
	reserveScatter = reserveScatter,
	clearReservations = clearReservations,
	scaled = scaled,

	STREET_HALF = STREET_HALF,
	ARRIVAL_Z = ARRIVAL_Z,
}
'''

# ---------------------------------------------------------------- ZoneKit gets the colour verbs

ZK_ANCHOR = """-- Raw zone accents are muted (Forest's is a dark green) and read as dead paint on a Neon part,
-- so anything meant to actually glow gets the accent pushed up to full saturation first.
local function vivid(c)"""

ZK_COLOURS = """-- The two most-used verbs in the world builder: 24 call sites in `ZoneBuilder` before the leaves
-- were cut out of it, and every one of those leaves needs them too. They came down here in 18.11
-- for that reason and no other -- a colour verb belongs beside the other colour verb.
local function lighten(c, t)
	return c:Lerp(Color3.new(1, 1, 1), t)
end

local function darken(c, t)
	return c:Lerp(Color3.new(0, 0, 0), t)
end

"""

ZK_EXPORT_ANCHOR = "\tvivid = vivid,\n"
ZK_EXPORT = "\tvivid = vivid,\n\tlighten = lighten,\n\tdarken = darken,\n"

# ---------------------------------------------------------------- what ZoneBuilder gets instead

ZB_REQUIRE = '''
-- WHERE A PROP MAY STAND LEFT THIS FILE (18.11)
--
-- `ServerScriptService.ScatterKit` -- the reservation table and `reserveScatter`, `scatterPoint`
-- and the legacy-spread rescaling behind it, `DENSITY` / `scaled`, and the platform's whole
-- clearance geography (the street, the centre square, both gate mouths, the boss's dais). Sixteen
-- top-level names, which took this file from **169 of Luau's 200 registers to 159**.
--
-- IT HAS STATE AND `ZoneKit` DOES NOT, which is the whole reason it is a second file rather than
-- more of the first. Read its header.
--
-- RE-LOCALISED, unlike `VillageKit` and for `ZoneKit`'s reason: `scatterPoint` alone has 109 call
-- sites here. Rewriting them would be 109 chances to break the world in a way no lint can see.
local ScatterKit = require(script.Parent.ScatterKit)

local scatterPoint, reserveScatter = ScatterKit.scatterPoint, ScatterKit.reserveScatter
local scaled = ScatterKit.scaled
local STREET_HALF, ARRIVAL_Z = ScatterKit.STREET_HALF, ScatterKit.ARRIVAL_Z

-- ...and the two colour verbs, which went the other way -- to `ZoneKit`, beside `vivid`. Same
-- reason as everything else on this line: 24 call sites below, none of which should have to change.
local lighten, darken = ZoneKit.lighten, ZoneKit.darken
'''

ZB_HELPERS_POINTER = '''-- THE PLACEMENT RULES ARE IN `ScatterKit` (18.11). `scatterPoint`, `reserveScatter`, `scaled` and
-- the clearance geography they read all left this file; they arrive re-localised at the top, so
-- every call site below reads exactly as it did. `lighten` and `darken` went to `ZoneKit`, beside
-- `vivid`. What is left in this section is the layers those verbs are used to build.'''


def cut(lines, lo, hi):
    return "\n".join(lines[lo - 1:hi])


def main():
    if SK.exists():
        sys.exit("ScatterKit.lua already exists -- refusing to run twice")

    text = io.open(ZB, encoding="utf-8", newline="").read()
    lines = text.split("\n")

    for n, prefix in BOUNDS:
        got = lines[n - 1]
        assert got.startswith(prefix), "line %d: expected %r, got %r" % (n, prefix, got)

    # ---- the new module, byte for byte except the two blocks rewritten above
    geography = cut(lines, *GEOGRAPHY)
    scatter = cut(lines, *SCATTER)
    colours = cut(lines, *COLOURS)

    # `function scatterPoint(...)` filled ZoneBuilder's forward declaration; here it owns itself.
    assert scatter.count("\nfunction scatterPoint(cx, spreadX, spreadZ, halfSize)\n") == 1
    scatter = scatter.replace("\nfunction scatterPoint(cx, spreadX, spreadZ, halfSize)\n",
                              "\nlocal function scatterPoint(cx, spreadX, spreadZ, halfSize)\n", 1)

    # the paragraph that stranded scatterBlocks up beside SHOP_Z is quoted in the header instead
    stale = ("-- Cleared once per zone, at the top of addGroundDetail -- which is the first thing the zone loop\n"
             "-- builds on the ground. Entries are world-space, so a stale one from the previous zone could never\n"
             "-- match anyway; the clear is for the table's size, not for correctness.\n"
             "--\n"
             "-- DECLARED FAR ABOVE THIS COMMENT, next to addGroundDetail. It has to be: addGroundDetail and the\n"
             "-- crate/coin scatter both run several hundred lines earlier in the file, and a local declared here\n"
             "-- is simply not in scope up there -- it compiles as a nil global lookup and dies at run time.\n"
             "-- `scatterPoint` below gets away with being used early only because it is a GLOBAL function.\n")
    assert scatter.count(stale) == 1, "the stranded-declaration paragraph is not where it was"
    scatter = scatter.replace(
        stale,
        "-- Cleared once per zone, by `clearReservations` at the top of addGroundDetail -- which is the first\n"
        "-- thing the zone loop builds on the ground. Entries are world-space, so a stale one from the\n"
        "-- previous zone could never match anyway; the clear is for the table's size, not for correctness.\n"
        "--\n"
        "-- IT USED TO BE DECLARED A THOUSAND LINES ABOVE THIS COMMENT, next to addGroundDetail, because a\n"
        "-- `local` is only in scope below its own line and the crate and coin scatter run far earlier in\n"
        "-- that file. Behind a require there is no such line. The table is at the top of this one, where it\n"
        "-- belongs, and the note the old site carried is quoted in the header.\n", 1)

    SK.write_text(SK_HEADER + geography + "\n\n" + SK_RESERVATIONS + scatter + "\n" + SK_FOOTER,
                  encoding="utf-8", newline="")

    # ---- ZoneKit takes lighten/darken
    zk = io.open(ZK, encoding="utf-8", newline="").read()
    assert zk.count(ZK_ANCHOR) == 1, "ZoneKit's `vivid` is not where it was"
    assert zk.count(ZK_EXPORT_ANCHOR) == 1, "ZoneKit's `vivid` export is not where it was"
    assert "lighten" not in zk and "darken" not in zk, "ZoneKit already has a colour verb by that name"
    assert colours == ("local function lighten(c, t)\n"
                       "\treturn c:Lerp(Color3.new(1, 1, 1), t)\n"
                       "end\n\n"
                       "local function darken(c, t)\n"
                       "\treturn c:Lerp(Color3.new(0, 0, 0), t)\n"
                       "end"), "lighten/darken are not the two lines this expects:\n" + colours
    zk = zk.replace(ZK_ANCHOR, ZK_COLOURS + ZK_ANCHOR, 1)
    zk = zk.replace(ZK_EXPORT_ANCHOR, ZK_EXPORT, 1)
    ZK.write_text(zk, encoding="utf-8", newline="")

    # ---- what is left of ZoneBuilder
    drop = set()
    for f, l in (FWD_DECL, BLOCKS_NOTE, BLOCKS, GEOGRAPHY, COLOURS, SCATTER):
        drop.update(range(f, l + 1))
    # the blank lines between the moved blocks, and the one above the first of them
    drop.update({1889, 1924, 1932})

    out = []
    for i, line in enumerate(lines, 1):
        if i == 880:
            out.append("")           # the section header and SHOP_Z's note were jammed together
        if i == 1890:
            out.append("")
            out.append(ZB_HELPERS_POINTER)
        if i not in drop:
            out.append(line)
    rest = "\n".join(out)

    # the ACTIVE_ZONE_KEY note points at a forward declaration that is not below it any more
    stranded = "-- nothing in the log. Same trap, same fix, as the `scatterPoint` forward declaration below."
    assert rest.count(stranded) == 1
    rest = rest.replace(
        stranded,
        "-- nothing in the log. Same trap, same fix, as the `scatterPoint` forward declaration that stood\n"
        "-- below this one until `ScatterKit` took it in 18.11.", 1)

    # the require goes where the other two kits are required, above everything that calls into it
    anchor = "local stoneTones, addLight = ZoneKit.stoneTones, ZoneKit.addLight\n"
    assert rest.count(anchor) == 1, "the ZoneKit re-local block is not where it was"
    rest = rest.replace(anchor, anchor + ZB_REQUIRE, 1)

    # the one call site that reached into the table by hand
    assert rest.count("\ttable.clear(scatterBlocks)\n") == 1
    rest = rest.replace("\ttable.clear(scatterBlocks)\n", "\tScatterKit.clearReservations()\n", 1)

    # Nothing may still spell a name that now lives elsewhere. A survivor here is a nil global,
    # and a nil global in a builder is a silent hole in the world, not an error.
    for gone in ("local scatterBlocks", "local function reserveScatter", "local function lighten",
                 "local function darken", "local DECO_SPREAD_X", "local CLEAR_HALF",
                 "local ARRIVAL_CLEAR", "local BOSS_CLEAR", "local BOSS_Z", "local DEFAULT_HALF",
                 "local DENSITY", "local function scaled", "local LEGACY_SPREAD_X",
                 "function scatterPoint(", "local scatterPoint\n"):
        assert gone not in rest, "%r still declared in ZoneBuilder" % gone
    survivors = [(i, l.strip()[:110]) for i, l in enumerate(rest.split("\n"), 1)
                 if "scatterBlocks" in l and not l.strip().startswith("--")]
    assert not survivors, "scatterBlocks survived in ZoneBuilder: %r" % survivors

    ZB.write_text(rest, encoding="utf-8", newline="")

    print("ScatterKit.lua  %d lines" % (SK.read_text(encoding="utf-8").count("\n") + 1))
    print("ZoneKit.lua     %d lines" % (zk.count("\n") + 1))
    print("ZoneBuilder     %d lines (was %d)" % (rest.count("\n") + 1, len(lines)))


main()
