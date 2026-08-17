"""Move the village palette, the soft-prop vocabulary and the village prop library out of
ZoneBuilder and into ServerScriptService/VillageKit.lua.

STEP 2, and the first leaf of `docs/SPLIT.md` §6.

WHAT THE PLAN SAID, AND WHY THE PIECE IS BIGGER THAN THE PLAN SAID
------------------------------------------------------------------
§6 names "the village prop library (2,108)" as the first leaf -- the section header at what is now
line 1572, `villMesh` / `addLamp` / `SHOP_SCALE` / `addStall` / `addWell`, 231 lines. That block
CANNOT MOVE ON ITS OWN, and measuring it is what shows why:

  * `addLamp`, `addWell` and `addPlanter` paint themselves out of `VILLAGE_WOOD`,
    `VILLAGE_WOOD_DARK` and `VILLAGE_CREAM`, which are **reassigned per zone** by
    `applyVillageStyle`. A module that took a copy of those at require time would be frozen on the
    Forest set forever, silently -- `docs/SPLIT.md` §3 rule 2, the same trap `ACTIVE_FRAME` hit.
    So the palette moves with the props or nothing moves.
  * Once the palette moves, the soft-prop vocabulary (`candy`, `addKnob`, `addScallops`,
    `addBunting`, `addPlanter`) has to move too -- three of the five read it.
  * And moving the 231 lines alone would have been **register-negative**: five names out, five
    re-localised back in, plus one for the require. The point of splitting this file is the
    200-register ceiling it is sitting under.

So the leaf is drawn where a leaf can actually be cut, and the line is a statable one:

    VillageKit owns what the village is MADE OF.  ZoneBuilder keeps where each piece GOES.

`addZoneProps`, `addZoneVillage`, `buildZoneShop` and `buildMysteryOddsBoard` -- the layout, the
coordinates, the ProximityPrompts and everything that reads `GameConfig` -- do not move. They call
the library through the require.

THE PALETTE BECOMES A TABLE, AND THAT IS THE ONE DESIGN DECISION HERE
---------------------------------------------------------------------
Six mutable top-level `local`s become six fields of one `VILLAGE` table that both files hold by
reference. A table has no line number, so the "read ~170 lines above its own `local`" bug that cost
BUILD_VERSION 133 cannot recur, and a reference cannot go stale the way a copied value can. The
cost is that ~59 read sites change spelling (`VILLAGE_CREAM` -> `VILLAGE.cream`), which is done here
by counted, asserted substitution rather than by hand -- and the table carries an `__index` that
ERRORS on an unknown field, because the failure being guarded against is silent: a nil Color3 paints
Roblox's default grey and nothing is logged.

NO GEOMETRY CHANGES, SO `BUILD_VERSION` IS NOT BUMPED. Same values, same writer, same call order.
That is a claim this move owes evidence for -- a rebuild and a census, not a lint.

WHAT ELSE CHANGES IN THE MOVED TEXT (everything else is byte for byte):
  * the five soft-prop verbs gain `local`. They were written `function candy(i)` to fill
    ZoneBuilder's `local addKnob, addScallops, addBunting, addPlanter, candy` forward declaration,
    which is a shape that only means something inside the file that wrote the declaration. That
    declaration is deleted here.
  * two comment paragraphs that describe the six values as `local`s declared above `addZoneProps`
    are repointed, because after this they are neither.
  * the two-line comment introducing `addLamp` is moved back to sit on `addLamp`. It had drifted
    ABOVE the section header, 45 lines from the function it describes, which is how it reads today.
  * `-- Live values the builders read...` and its two `local`s fold into the table, sentence kept.

Written as a script for the reason `extract_zonekit.py` gives: every comment in this codebase is
load-bearing (GEMINI.md rule 10). Boundaries asserted before slicing; refuses to run twice.
"""
import io
import re
import sys
from pathlib import Path

ROOT = Path(r"C:\Users\Kristina\Documents\evolution-lab")
ZB = ROOT / "src/ServerScriptService/ZoneBuilder.lua"
VK = ROOT / "src/ServerScriptService/VillageKit.lua"

# 1-indexed, inclusive; each takes the blank line that follows it.
FWD_DECL = (241, 244)      # the soft-prop forward declaration, comment and all
PALETTE = (1076, 1087)     # the four colours + the note about why they are declared up here
VILLAGE = (1294, 1801)     # the style tables, the outline tier, the vocabulary, the prop library

BOUNDS = [
    (241, "-- Same reason, for the soft-prop vocabulary (knobs, scallops, bunting, planters)."),
    (244, "local addKnob, addScallops, addBunting, addPlanter, candy"),
    (1076, "-- ===== THE VILLAGE PALETTE, DECLARED HERE BECAUSE addZoneProps READS IT ====="),
    (1087, "local VILLAGE_CREAM = Color3.fromRGB(252, 244, 226)"),
    (1294, "-- ===== THE VILLAGE IS BUILT OF DIFFERENT STUFF IN EVERY ZONE ====="),
    (1801, "end"),
]

# ---------------------------------------------------------------- the new module

VK_HEADER = '''-- VillageKit -- what the village is MADE OF: the per-zone palette every hand-placed structure is
-- dressed in, the four soft shapes that turn a box into a toy, and the prop library itself -- the
-- lamp, the shop kiosk, the well and the mesh loader they are all built through.
--
-- WHERE THE LINE IS: this file owns what a village is made of; `ZoneBuilder` owns where each piece
-- goes. `addZoneVillage` still decides that the lamps run every 30 studs from z = 420 and that the
-- shop stands at cx - 150; `buildZoneShop` still hangs the ProximityPrompts and reads `GameConfig`.
-- None of that moved. What moved is the vocabulary those three functions speak.
--
-- WHY IT IS BIGGER THAN "THE VILLAGE PROP LIBRARY" (18.10)
-- --------------------------------------------------------
-- `docs/SPLIT.md` §6 names the prop library as the first leaf out of `ZoneBuilder` and describes
-- each leaf as "a section that only reads the kit". The prop library nearly is, and the gap is the
-- whole reason this file has a palette in it: `addLamp`, `addWell` and `addPlanter` paint
-- themselves out of colours that are **reassigned per zone**. A module that copied those at require
-- time would be frozen on the Forest set forever, with no error anywhere -- `docs/SPLIT.md` §3
-- rule 2, which `ACTIVE_FRAME` already paid for once in `ZoneKit`. So the palette comes with the
-- props, and the soft-prop vocabulary comes with the palette because three of its five read it.
--
-- Cutting only the 231 lines §6 named would also have been register-NEGATIVE -- five names out,
-- five re-localised back, plus one for the require -- and the 200-register ceiling is the reason
-- this file is being split at all. This cut takes `ZoneBuilder` from 189 registers to 169.
--
-- NOTHING IS RE-LOCALISED ON THE BUILDER'S SIDE, and that is the opposite of what `ZoneKit` did.
-- `ZoneKit` kept its names local there because `newPart` has 534 call sites and rewriting them
-- would have been 534 chances to break the world for nothing visible. The village verbs have
-- **fifteen** call sites between them. At fifteen, spelling out `VillageKit.addKnob(...)` costs one
-- afternoon of nothing and buys back the registers, and it tells the next reader where the thing
-- lives -- which is the entire point of the split.
--
-- WHO MAY REQUIRE IT: any server script standing village furniture. Nothing but `ZoneBuilder` does
-- today. `HubPlaza` and `RebirthShrine` build their own and are deliberately untouched.
--
-- Where the rest of the world is built: `docs/CODEMAP.md`, `docs/SPLIT.md` §6.

local ServerStorage = game:GetService("ServerStorage")

-- The kit is required here and not handed in, so this file stands on its own: `newPart` and the
-- placement frame, plus the four verbs that came down to `ZoneKit` in 18.10 precisely because the
-- village needed them -- `seatModel` for the mesh props, `stoneTones` for the well's cobbles,
-- `makeSign` for the shop's board and `addLight` for everything that glows out here.
local ZoneKit = require(script.Parent.ZoneKit)

local newPart = ZoneKit.newPart
local seatModel, makeSign = ZoneKit.seatModel, ZoneKit.makeSign
local stoneTones, addLight = ZoneKit.stoneTones, ZoneKit.addLight

'''

VK_PALETTE = '''-- ===== THE PALETTE IS ONE TABLE, AND THE TABLE IS THE POINT =====
--
-- Six live values dress every hand-placed structure in a zone. They were six top-level `local`s in
-- `ZoneBuilder`, reassigned per zone, and that shape cost BUILD_VERSION 133. The note written at
-- the time, kept because it is the reason this is not six re-localised names:
--
--   > These four were authored ~170 lines below, beside the VILLAGE_STYLE table that reassigns them
--   > per zone, which reads well and compiled fine -- and meant the three uses in addZoneProps below
--   > (the crate lid, a knob and the banner emblem) resolved to a nil GLOBAL, so those parts took
--   > Roblox's default grey instead of cream. A `local` is only visible BELOW its own line no matter
--   > where the function is called from. If you move this block, it has to stay above addZoneProps.
--
-- A TABLE HAS NO LINE. Both files hold this one by reference, so all six fields are readable
-- wherever either file is written, and "read above its own declaration" stops being a thing that
-- can happen. It is also the only shape that survives the require at all: the values are
-- reassigned per zone, so a copy taken on the other side would be frozen on Forest forever
-- (`docs/SPLIT.md` §3 rule 2).
--
-- THE FIELDS ARE GUARDED, because the failure they replace is silent. `VILLAGE.crem` is nil, a nil
-- `Color3` paints Roblox's default grey, and nothing errors or logs -- which is exactly how 133
-- survived long enough to ship. `__index` only fires on a field that is not there, so it costs
-- nothing on the six that always are, and it turns a typo into a build-time error instead of a grey
-- part in twenty villages that nobody photographs.
--
-- Live values the builders read. The values here are the Forest set and are the documented
-- fallback; `applyVillageStyle` overwrites all six per zone and is still the only writer.
local VILLAGE = setmetatable({
	wood  = Color3.fromRGB(154, 108, 62),
	dark  = Color3.fromRGB(101, 69, 40),
	cloth = Color3.fromRGB(240, 235, 222),
	cream = Color3.fromRGB(252, 244, 226),
	post  = Enum.Material.Wood,
	board = Enum.Material.WoodPlanks,
}, {
	__index = function(_, key)
		error(("VILLAGE has no field %q -- a nil colour paints default grey and never errors"):format(tostring(key)), 2)
	end,
})

'''

VK_FOOTER = '''
-- `villMesh` and `trimFor` are deliberately NOT exported. Nothing outside this file has ever called
-- either, and a library's surface should be the things somebody asks it for.
return {
	palette = VILLAGE,
	applyVillageStyle = applyVillageStyle,

	candy = candy,
	addKnob = addKnob,
	addScallops = addScallops,
	addBunting = addBunting,
	addPlanter = addPlanter,

	addLamp = addLamp,
	addStall = addStall,
	addWell = addWell,
	SHOP_SCALE = SHOP_SCALE,
}
'''

# ---------------------------------------------------------------- what ZoneBuilder gets instead

ZB_BRIDGE = '''-- ===== THE VILLAGE'S MATERIALS LEFT THIS FILE (18.10) =====
--
-- `ServerScriptService.VillageKit` -- the per-zone palette, `applyVillageStyle` and the tables it
-- reads, the soft-prop vocabulary (`candy`, `addKnob`, `addScallops`, `addBunting`, `addPlanter`)
-- and the prop library itself (`addLamp`, `addStall`, `addWell`, `SHOP_SCALE`, and the `villMesh`
-- loader behind them). Twenty-two top-level names, which took this file from **189 of Luau's 200
-- registers to 169**. Read its header for where the line between the two files is drawn.
--
-- WHAT DID NOT MOVE: the layout. `addZoneProps` below, and `addZoneVillage`, `buildZoneShop` and
-- `buildMysteryOddsBoard` further down, still decide where every piece stands, still hang the
-- prompts and still read `GameConfig`. They call the library through this require.
--
-- NOT RE-LOCALISED, unlike `ZoneKit` above -- there are fifteen call sites, not five hundred, and
-- `VillageKit.addKnob(...)` is worth its four extra characters for saying where the thing lives.
--
-- `VILLAGE` IS A REFERENCE, NOT A COPY, and it has to be: `applyVillageStyle` reassigns all six of
-- its fields once per zone, so a value copied here would be frozen on Forest forever and silently
-- (`docs/SPLIT.md` §3 rule 2). The table is shared, so the field reads below always see the zone
-- currently being built.
local VillageKit = require(script.Parent.VillageKit)
local VILLAGE = VillageKit.palette'''

ZB_VILLAGE_POINTER = '''--
-- THE MATERIALS ARE IN `VillageKit`; WHAT IS LEFT HERE IS THE PLAN. The nineteen per-zone palettes
-- and the rule behind them (contrast with the GROUND, not agreement with the theme), the outline
-- tier, the candy set, the four soft shapes and the prop library are all in
-- `ServerScriptService.VillageKit` as of 18.10 -- see the require above `addZoneProps`. What
-- follows is the placement: the odds board, the shop counters and `addZoneVillage`, which is the
-- function that says where a village's pieces actually stand.'''

# ---------------------------------------------------------------- patches inside the moved text

VK_BODY_PATCHES = [
    # the five soft-prop verbs owned a forward declaration in ZoneBuilder; here they own themselves
    ("\nfunction candy(i)\n", "\nlocal function candy(i)\n", 1),
    ("\nfunction addKnob(model, pos, size, color, material)\n",
     "\nlocal function addKnob(model, pos, size, color, material)\n", 1),
    ("\nfunction addScallops(model, base, width, count, y, z, colorA, colorB, size)\n",
     "\nlocal function addScallops(model, base, width, count, y, z, colorA, colorB, size)\n", 1),
    ("\nfunction addBunting(model, fromPos, toPos, count, droop, seed)\n",
     "\nlocal function addBunting(model, fromPos, toPos, count, droop, seed)\n", 1),
    ("\nfunction addPlanter(model, base, seed, scale)\n",
     "\nlocal function addPlanter(model, base, seed, scale)\n", 1),

    # the six values are fields of one table now, not locals reassigned in place
    (
        "-- These four values dress EVERY hand-placed structure in a zone: the street fence, the welcome\n"
        "-- arch, the name board, the benches, the planters, the well, the stalls and the shop. They were\n"
        "-- four constants, so all twenty zones were furnished in the same brown pine and the same cream\n"
        "-- paint",

        "-- These six values dress EVERY hand-placed structure in a zone: the street fence, the welcome\n"
        "-- arch, the name board, the benches, the planters, the well, the stalls and the shop. They began\n"
        "-- as four colour constants, so all twenty zones were furnished in the same brown pine and the\n"
        "-- same cream paint",
        1,
    ),
    (
        "-- They are `local` and REASSIGNED per zone rather than threaded through as parameters: fifty-nine\n"
        "-- lines across a dozen builders read them, and none of those builders is handed the zone. The\n"
        "-- write happens in one place -- `applyVillageStyle`, called from the zone loop right where\n"
        "-- ACTIVE_ZONE_KEY is set -- so the mutation has exactly one owner and one lifetime.",

        "-- They are REASSIGNED per zone rather than threaded through as parameters: fifty-nine lines\n"
        "-- across a dozen builders read them, and none of those builders is handed the zone. The write\n"
        "-- happens in one place -- `applyVillageStyle`, called from `ZoneBuilder`'s zone loop right where\n"
        "-- ACTIVE_ZONE_KEY is set -- so the mutation has exactly one owner and one lifetime.",
        1,
    ),
    (
        "-- The four locals themselves are declared ABOVE addZoneProps, not here, because that function\n"
        "-- reads three of them -- see the note there. This is where they are documented and where they are\n"
        "-- reassigned; it is not where they are introduced.",

        "-- The six values themselves are the `VILLAGE` table at the top of this file -- see the note there\n"
        "-- for why a table and not six locals. This is where they are documented and where they are\n"
        "-- reassigned; it is not where they are introduced.",
        1,
    ),

    # VILLAGE_POST_MAT / VILLAGE_BOARD_MAT fold into the table; their sentence went with them
    (
        "\n\n-- Live values the builders read. Reassigned by applyVillageStyle, never written anywhere else.\n"
        "local VILLAGE_POST_MAT = Enum.Material.Wood\n"
        "local VILLAGE_BOARD_MAT = Enum.Material.WoodPlanks\n",
        "\n",
        1,
    ),
]

# The two lines that introduce addLamp had drifted ABOVE the section header, 45 lines from the
# function they describe. Put back where they belong; not deleted, not reworded.
LAMP_NOTE = (
    "-- A lantern on a post, hung off the +Z side of `base`. Used along the street and beside every\n"
    "-- structure below: a settlement reads as a settlement mostly by being lit.\n"
)

# ---------------------------------------------------------------- the palette rename, both sides

PALETTE_RENAMES = [
    ("VILLAGE_WOOD_DARK", "VILLAGE.dark"),   # before VILLAGE_WOOD: it is a prefix of this one
    ("VILLAGE_WOOD", "VILLAGE.wood"),
    ("VILLAGE_CLOTH", "VILLAGE.cloth"),
    ("VILLAGE_CREAM", "VILLAGE.cream"),
    ("VILLAGE_POST_MAT", "VILLAGE.post"),
    ("VILLAGE_BOARD_MAT", "VILLAGE.board"),
]

# ---------------------------------------------------------------- ZoneBuilder call sites

CALL_RENAMES = [
    ("candy", 6),
    ("addKnob", 7),
    ("addScallops", 1),
    ("addBunting", 2),
    ("addPlanter", 1),
    ("addLamp", 1),
    ("addStall", 1),
    ("addWell", 1),
]

ZB_PATCHES = [
    ("\tlocal S = SHOP_SCALE\n", "\tlocal S = VillageKit.SHOP_SCALE\n", 1),
    ("\t\t\tapplyVillageStyle(zone.key)\n", "\t\t\tVillageKit.applyVillageStyle(zone.key)\n", 1),
    (
        "-- SHOP_SCALE is declared much further down, next to addStall, and cannot be used up here.",
        "-- SHOP_SCALE is `VillageKit.SHOP_SCALE` and could be read here, but this number is not derived\n"
        "-- from it: 175 was measured against the Ocean shipwreck, not against the kiosk's own size.",
        1,
    ),
    (
        "-- nineteen zones out of twenty. See the block above VILLAGE_STYLE.",
        "-- nineteen zones out of twenty. See the palette note at the top of `VillageKit`.",
        1,
    ),
]


def main():
    if VK.exists():
        sys.exit("VillageKit.lua already exists -- refusing to run twice")

    text = io.open(ZB, encoding="utf-8", newline="").read()
    lines = text.split("\n")

    for n, prefix in BOUNDS:
        got = lines[n - 1]
        assert got.startswith(prefix), "line %d: expected %r, got %r" % (n, prefix, got)
    for _f, l in (FWD_DECL, PALETTE, VILLAGE):
        assert lines[l] == "", "line %d should be blank, got %r" % (l + 1, lines[l])

    # ---- the module body
    body = "\n".join(lines[VILLAGE[0] - 1:VILLAGE[1]])
    for old, new, count in VK_BODY_PATCHES:
        assert body.count(old) == count, "body patch %r: expected %d, found %d" % (
            old.strip()[:60], count, body.count(old))
        body = body.replace(old, new)

    assert body.count(LAMP_NOTE) == 1
    body = body.replace(LAMP_NOTE, "", 1)
    assert body.count("local function addLamp(model, base, color, h)\n") == 1
    body = body.replace("local function addLamp(model, base, color, h)\n",
                        LAMP_NOTE + "local function addLamp(model, base, color, h)\n")

    for old, new in PALETTE_RENAMES:
        body = re.sub(r"\b%s\b" % old, new, body)
    assert "VILLAGE_" not in body.replace("VILLAGE_STYLE", "").replace(
        "VILLAGE_DEFAULT", "").replace("VILLAGE_MATERIAL", ""), "a VILLAGE_* colour survived"

    VK.write_text(VK_HEADER + VK_PALETTE + body + "\n" + VK_FOOTER, encoding="utf-8", newline="")

    # ---- what is left of ZoneBuilder
    keep = [True] * len(lines)
    for f, l in (FWD_DECL, PALETTE, VILLAGE):
        for i in range(f - 1, l + 1):        # +1: the trailing blank goes too
            keep[i] = False
    out = []
    for i, line in enumerate(lines):
        if i == PALETTE[0] - 1:
            out.append(ZB_BRIDGE)
        if i == VILLAGE[0] - 1:
            out.append(ZB_VILLAGE_POINTER)
        if keep[i]:
            out.append(line)
    rest = "\n".join(out)

    # The BUILD_VERSION changelog is a dated record of what each bump DID. 133's entry names
    # VILLAGE_CREAM and the `local` it was read above; renaming inside it would make a true
    # historical sentence false. Nothing above BUILD_VERSION is touched.
    split = re.search(r"\nlocal BUILD_VERSION = \d+\n", rest)
    assert split, "BUILD_VERSION declaration not found"
    head, tail = rest[:split.start()], rest[split.start():]
    assert "VILLAGE_CREAM" in head, "133's changelog entry is not where it was"

    for old, new in PALETTE_RENAMES:
        tail = re.sub(r"\b%s\b" % old, new, tail)
    for name, count in CALL_RENAMES:
        pat = r"(?<![\w.:])%s\(" % name
        found = len(re.findall(pat, tail))
        assert found == count, "%s(: expected %d call sites, found %d" % (name, count, found)
        tail = re.sub(pat, "VillageKit.%s(" % name, tail)
    for old, new, count in ZB_PATCHES:
        assert tail.count(old) == count, "ZoneBuilder patch %r: expected %d, found %d" % (
            old.strip()[:60], count, tail.count(old))
        tail = tail.replace(old, new)

    # Nothing below BUILD_VERSION may still spell a name that now lives in the other file. This is
    # the check that matters most: a missed `VILLAGE_CREAM` is a nil global, a nil global is
    # Roblox's default grey, and no lint and no error will ever mention it.
    survivors = [l.strip()[:110] for l in tail.split("\n") if "VILLAGE_" in l]
    assert not survivors, "VILLAGE_* survived in ZoneBuilder:\n" + "\n".join(survivors)

    rest = head + tail
    # `addStallDressing` in the egg plaza starts with `addStall`, so these are matched to the end of
    # the name rather than as substrings -- the loose version reported a definition that is not one.
    for gone in ("local VILLAGE_WOOD =", "local VILLAGE_STYLE =", "local VILLAGE_DEFAULT =",
                 "local VILLAGE_MATERIAL =", "local CANDY =", "local SHOP_SCALE =",
                 "local function trimFor(", "local function villMesh(", "local function addLamp(",
                 "local function addStall(", "local function addWell(",
                 "local function applyVillageStyle("):
        assert gone not in rest, "%r still in ZoneBuilder" % gone

    ZB.write_text(rest, encoding="utf-8", newline="")

    print("VillageKit.lua  %d lines" % (VK.read_text(encoding="utf-8").count("\n") + 1))
    print("ZoneBuilder     %d lines (was %d)" % (
        rest.count("\n") + 1, len(lines)))
    print()
    print("--- every rewritten line in ZoneBuilder ---")
    for i, line in enumerate(rest.split("\n"), 1):
        if "VillageKit." in line or "VILLAGE." in line:
            print("%5d  %s" % (i, line.strip()[:150]))


main()
