"""Move four more verbs out of ZoneBuilder and into ZoneKit: seatModel, makeSign, stoneTones,
addLight.

STEP 1 OF THE VILLAGE LEAF, and it exists because the leaf cannot move without it. `docs/SPLIT.md`
§6 says each leaf "only reads the kit", and the village prop library nearly does -- but not quite:

    villMesh -> seatModel        addWell -> stoneTones
    addStall -> makeSign         addLamp, addStall -> addLight

Four names that were still ZoneBuilder's. The alternatives were to hand the village module a
dependency table it reads at call time, or to pass four functions as arguments; both are
indirection invented to avoid admitting that these four are vocabulary. They are:

  * `seatModel` puts ANY cloned model on the ground whatever its author did with its pivot -- 18
    call sites, nothing zone-specific in it.
  * `makeSign` is every name board in the world (6 sites) and it reads `SIGN_INK` / `SIGN_RIM` /
    `SIGN_FACE` / `SIGN_FONT`, which are already in ZoneKit. Its palette was here and it was not.
  * `stoneTones` is what colour ANY rock is (5 sites), derived from `groundColorOf`, which is
    already in ZoneKit -- exactly the line the header draws between "a rule every part obeys" and
    "a decision about one zone".
  * `addLight` is eight lines with no dependency on anything at all, called at 81 sites, and it is
    the fifth of the "small verbs the scenery is painted and animated with" the header names.

REGISTER-NEUTRAL FOR ZoneBuilder, deliberately. All four are re-localised on the other side of the
require, so not one of those 110 call sites changes and the four registers come straight back --
the same trade `extract_zonekit.py` made for `newPart`'s 534. This step is not here to buy
registers; step 2 (`extract_village.py`) is.

ONE TOKEN CHANGES IN THE MOVED CODE: `function addLight(...)` becomes `local function addLight(...)`.
It was written without `local` because it filled a forward declaration 2,500 lines above it
(`local addLight, scatterPoint`) -- a shape that only makes sense inside the file that declared it.
That forward declaration and the two comments that name it are repointed here; nothing else in the
~200 moved lines differs by a byte.

Written as a script rather than by hand for the reason `extract_zonekit.py` gives: every comment in
this codebase is load-bearing (GEMINI.md rule 10) and a hand-copy drops one. Boundaries are
asserted before anything is sliced; it refuses to run twice.
"""
import io
import sys
from pathlib import Path

ROOT = Path(r"C:\Users\Kristina\Documents\evolution-lab")
ZB = ROOT / "src/ServerScriptService/ZoneBuilder.lua"
KIT = ROOT / "src/ServerScriptService/ZoneKit.lua"

# 1-indexed, inclusive. Each block is followed by exactly one blank line, which goes with it.
BLOCKS = [
    (218, 233),    # seatModel, with the note about the Forest trees hovering over the grass
    (252, 370),    # makeSign, with the whole "every layer is sized in SCALE" note
    (684, 746),    # stoneTones, with the dark-ground and pale-ground notes
    (2762, 2769),  # addLight
]

# (line, expected prefix) -- asserted, not assumed: if ZoneBuilder has moved under this script the
# numbers are meaningless and a silent slice cuts the world in the wrong place.
BOUNDS = [
    (218, "-- SEATS A CLONED MODEL ON THE GROUND, whatever its author did with its pivot."),
    (233, "end"),
    (252, "-- Every name board in the world -- the gate signs, the two direction signs on the walkway"),
    (370, "end"),
    (684, "-- Rock is the zone's own ground colour pulled toward white in three steps"),
    (746, "end"),
    (2762, "function addLight(part, color, range, brightness)"),
    (2769, "end"),
]

# Where the four blocks land in ZoneKit: immediately above the accessor footer, so everything they
# read (newPart, the SIGN_* palette, groundColorOf) is already in scope above them.
KIT_ANCHOR = "-- ===== THE FRAME HAS EXACTLY ONE OWNER ====="

KIT_LEAD = '''-- ===== FOUR MORE VERBS, MOVED DOWN FOR THE VILLAGE LEAF (18.10) =====
--
-- These four were still `ZoneBuilder`'s when the village prop library came to move, and every one
-- of them was already vocabulary rather than a decision about a zone -- `makeSign` even reads the
-- SIGN_* palette that had been sitting up in this file without it. They are byte-for-byte what was
-- in the builder, except that `addLight` gained the `local` it never needed there (it was filling
-- a forward declaration 2,500 lines above itself, which is a shape that only means anything inside
-- the file that wrote the declaration).
--
-- All four are re-localised on the builder's side, so their 110 call sites read exactly as before.

'''

KIT_RETURN_OLD = """	newPart = newPart,
	groundColorOf = groundColorOf,
	addPlankText = addPlankText,
	vivid = vivid,
	spinForever = spinForever,
	pulseForever = pulseForever,
"""

KIT_RETURN_NEW = """	newPart = newPart,
	groundColorOf = groundColorOf,
	addPlankText = addPlankText,
	vivid = vivid,
	spinForever = spinForever,
	pulseForever = pulseForever,

	seatModel = seatModel,
	makeSign = makeSign,
	stoneTones = stoneTones,
	addLight = addLight,
"""

KIT_HEADER_OLD = """-- ZoneKit -- the vocabulary the world is built in: the part factory, the two rules it applies
-- without being asked (shadow by size, solidity by name), the placement frame those rules read,
-- the platform's own dimensions, the sign palette, and the four small verbs the scenery is
-- painted and animated with.
"""

KIT_HEADER_NEW = """-- ZoneKit -- the vocabulary the world is built in: the part factory, the two rules it applies
-- without being asked (shadow by size, solidity by name), the placement frame those rules read,
-- the platform's own dimensions, the sign palette, and the small verbs the scenery is painted,
-- lit, seated, labelled and animated with.
"""

# ---- ZoneBuilder side.

# The four names come back on the same bridge the rest of the vocabulary arrives on, so the 110
# call sites below are untouched and the four registers are exactly the ones the `local function`s
# cost. Appended after the SIGN_* line at the end of the bridge.
ZB_RELOCALISE_AFTER = "local SIGN_FACE, SIGN_FONT = ZoneKit.SIGN_FACE, ZoneKit.SIGN_FONT"
ZB_RELOCALISE = (
    "local seatModel, makeSign = ZoneKit.seatModel, ZoneKit.makeSign\n"
    "local stoneTones, addLight = ZoneKit.stoneTones, ZoneKit.addLight"
)

ZB_PATCHES = [
    # the bridge's own inventory of what left
    (
        "-- THE KIT LEFT THIS FILE (18.9). `newPart` -- with the shadow-by-size rule and the\n"
        "-- solidity-by-name list it applies to every part without being asked -- plus `groundColorOf`,\n"
        "-- `addPlankText`, `vivid`, `spinForever`, `pulseForever`, the placement frame they all read, the\n"
        "-- sign palette and the platform's own dimensions are `ServerScriptService.ZoneKit` now, byte for\n"
        "-- byte, with every comment that explains why they behave the way they do. Nothing about what gets\n"
        "-- built changed; only where the vocabulary lives.",

        "-- THE KIT LEFT THIS FILE (18.9). `newPart` -- with the shadow-by-size rule and the\n"
        "-- solidity-by-name list it applies to every part without being asked -- plus `groundColorOf`,\n"
        "-- `addPlankText`, `vivid`, `spinForever`, `pulseForever`, the placement frame they all read, the\n"
        "-- sign palette and the platform's own dimensions are `ServerScriptService.ZoneKit` now, byte for\n"
        "-- byte, with every comment that explains why they behave the way they do. Nothing about what gets\n"
        "-- built changed; only where the vocabulary lives.\n"
        "--\n"
        "-- AND FOUR MORE FOLLOWED THEM (18.10): `seatModel`, `makeSign`, `stoneTones` and `addLight`.\n"
        "-- Those went because the VILLAGE leaf needs them -- `villMesh` seats a model, `addWell` tones a\n"
        "-- rock, `addStall` makes a sign and lights itself -- and because each was already vocabulary\n"
        "-- rather than a decision about a zone. `makeSign` in particular was reading a SIGN_* palette that\n"
        "-- had already moved to the kit without it.",
        1,
    ),
    # the forward declaration addLight no longer needs
    (
        "-- Forward-declared. Both are defined in the shared-decoration section far below, but the portal,\n"
        "-- cliff, titan and prop builders are all written above it, and Lua binds an upvalue where the\n"
        "-- function is *written* rather than where it runs -- without these names in scope up here every\n"
        "-- call would silently resolve to a nil global and blow up at world-build time.\n"
        "local addLight, scatterPoint",

        "-- Forward-declared. `scatterPoint` is defined in the shared-decoration section far below, but the\n"
        "-- portal, cliff, titan and prop builders are all written above it, and Lua binds an upvalue where\n"
        "-- the function is *written* rather than where it runs -- without the name in scope up here every\n"
        "-- call would silently resolve to a nil global and blow up at world-build time.\n"
        "--\n"
        "-- `addLight` stood on this line until 18.10 and is the kit's now. It needs no forward declaration\n"
        "-- at all any more: it arrives re-localised at the top of the file, which is above everything.\n"
        "local scatterPoint",
        1,
    ),
    # ACTIVE_ZONE_KEY's note points at that forward declaration by name
    (
        "-- there it resolved to a nil global and every landmark silently fell back to its block style with\n"
        "-- nothing in the log. Same trap, same fix, as the `addLight, scatterPoint` forward declarations.",

        "-- there it resolved to a nil global and every landmark silently fell back to its block style with\n"
        "-- nothing in the log. Same trap, same fix, as the `scatterPoint` forward declaration below.",
        1,
    ),
]


def main():
    src = io.open(KIT, encoding="utf-8", newline="").read()
    if "seatModel = seatModel," in src:
        sys.exit("ZoneKit already has the verbs -- refusing to run twice")

    text = io.open(ZB, encoding="utf-8", newline="").read()
    lines = text.split("\n")

    for n, prefix in BOUNDS:
        got = lines[n - 1]
        assert got.startswith(prefix), "line %d: expected %r, got %r" % (n, prefix, got)
    for _first, last in BLOCKS:
        assert lines[last] == "", "line %d should be blank, got %r" % (last + 1, lines[last])

    body = "\n\n".join("\n".join(lines[f - 1:l]) for f, l in BLOCKS)
    # the one token that changes: addLight filled a forward declaration in the builder and owns
    # itself here
    assert body.count("\nfunction addLight(part, color, range, brightness)\n") == 1
    body = body.replace("\nfunction addLight(part, color, range, brightness)\n",
                        "\nlocal function addLight(part, color, range, brightness)\n")

    assert src.count(KIT_ANCHOR) == 1
    assert src.count(KIT_HEADER_OLD) == 1
    assert src.count(KIT_RETURN_OLD) == 1
    src = src.replace(KIT_HEADER_OLD, KIT_HEADER_NEW)
    src = src.replace(KIT_ANCHOR, KIT_LEAD + body + "\n\n" + KIT_ANCHOR)
    src = src.replace(KIT_RETURN_OLD, KIT_RETURN_NEW)
    KIT.write_text(src, encoding="utf-8", newline="")

    keep = [True] * len(lines)
    for f, l in BLOCKS:
        for i in range(f - 1, l + 1):        # +1: the trailing blank line goes too
            keep[i] = False
    rest = "\n".join(line for i, line in enumerate(lines) if keep[i])

    assert rest.count(ZB_RELOCALISE_AFTER) == 1
    rest = rest.replace(ZB_RELOCALISE_AFTER, ZB_RELOCALISE_AFTER + "\n" + ZB_RELOCALISE)
    for old, new, count in ZB_PATCHES:
        assert rest.count(old) == count, "ZoneBuilder patch %r: expected %d, found %d" % (
            old.strip()[:60], count, rest.count(old))
        rest = rest.replace(old, new)

    # the four names must survive only as calls, never as definitions, on this side
    for name in ("seatModel", "makeSign", "stoneTones"):
        assert ("local function %s(" % name) not in rest, "%s still defined in ZoneBuilder" % name
    assert "\nfunction addLight(" not in rest, "addLight still defined in ZoneBuilder"

    ZB.write_text(rest, encoding="utf-8", newline="")

    print("ZoneKit.lua   %d lines" % (KIT.read_text(encoding="utf-8").count("\n") + 1))
    print("ZoneBuilder   %d lines (was %d)" % (
        ZB.read_text(encoding="utf-8").count("\n") + 1, len(lines)))


main()
