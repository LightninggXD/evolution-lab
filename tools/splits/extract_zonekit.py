"""Move ZoneBuilder's build vocabulary into ServerScriptService/ZoneKit.lua.

This is the FIRST step of the ZoneBuilder split and the only one that could go first:
`newPart` is called at 534 sites spread over the whole 9,281-line file, so no leaf can move
until the vocabulary it speaks exists somewhere both sides can see. See docs/SPLIT.md §6.

Seven blocks move, byte for byte:

    74-120   the platform's dimensions + the terrace band constants
    169-198  GROUND_MAX_LUM + groundColorOf
    243-249  ACTIVE_FRAME (the placement frame newPart applies)
    261-441  the shadow-by-size rule, the solidity-by-name list, its audit, and newPart
    495-510  the sign palette (SIGN_INK / SIGN_RIM / SIGN_FACE / SIGN_FONT)
    614-690  addPlankText
    717-741  vivid, spinForever, pulseForever

Done as a script rather than by hand so the ~370 moved lines are byte-identical -- every
comment in them is load-bearing (GEMINI.md rule 10) and this project has been burned by a
hand-edit that dropped one. The boundaries are asserted before anything is sliced, and it
refuses to run twice.

NINE COMMENT LINES ARE REPOINTED and nothing else: phrases like "104 call sites in this file"
meant ZoneBuilder, and a comment that lies about where something lives is worse than no comment.
Every one of them is an explicit (old, new) pair below, asserted unique before it is applied.
"""
import io
import sys
from pathlib import Path

ROOT = Path(r"C:\Users\Kristina\Documents\evolution-lab")
ZB = ROOT / "src/ServerScriptService/ZoneBuilder.lua"
KIT = ROOT / "src/ServerScriptService/ZoneKit.lua"

# 1-indexed, inclusive. Each block is followed by exactly one blank line, which goes with it
# (except the first, whose place the bridge takes).
BLOCKS = [
    (74, 120),
    (169, 198),
    (243, 249),
    (261, 441),
    (495, 510),
    (614, 690),
    (717, 741),
]

# (line, expected first 60 chars) -- the boundary is asserted, not assumed: if ZoneBuilder has
# moved under this script the line numbers are meaningless and a silent slice cuts the world in
# the wrong place.
BOUNDS = [
    (74, "-- Roughly 2.4x the old 450 x 550."),
    (120, "local TERRAIN_DEPTH = PLATFORM_DEPTH - WALL_THICK"),
    (169, "-- ---- THE GROUND IS NEVER THE BRIGHTEST THING IN ITS OWN ZONE"),
    (198, "end"),
    (243, "-- While this is set, every part newPart makes is placed"),
    (249, "local ACTIVE_FRAME = nil"),
    (261, "-- ===== SHADOWS ARE DECIDED BY SIZE, IN ONE PLACE ====="),
    (441, "end"),
    (495, "local SIGN_INK = Color3.fromRGB(26, 18, 36)"),
    (510, "end)()"),
    (614, "-- Text painted straight onto a prop's own face"),
    (690, "end"),
    (717, "-- Raw zone accents are muted (Forest's is a dark green)"),
    (741, "end"),
]

KIT_HEADER = '''-- ZoneKit -- the vocabulary the world is built in: the part factory, the two rules it applies
-- without being asked (shadow by size, solidity by name), the placement frame those rules read,
-- the platform's own dimensions, the sign palette, and the four small verbs the scenery is
-- painted and animated with.
--
-- WHY THIS IS ITS OWN FILE, AND WHY IT IS THE FIRST THING OUT (18.9)
-- -----------------------------------------------------------------
-- `ZoneBuilder` is 9,281 lines -- ~152k tokens to read whole, which is most of a context window
-- spent to move one prop. Splitting it is NOT the job `MainUI` was. MainUI's 23 blocks were
-- already `;(function() ... end)()` closures that escaped nothing, so each one was a module
-- already and the split was a change of wrapper. ZoneBuilder has **190 top-level locals, 48 of
-- them used across spans of 600+ lines**, and `newPart` alone is called at **534 sites** spread
-- over the whole file. There is no line at which a cut leaves the locals behind.
--
-- So the order is inverted: the shared vocabulary comes out FIRST, and the leaves (the village
-- prop library, the ground clutter, the idols and ruins, the mesh prop layer, the egg plaza, the
-- boss arena) move onto it afterwards, each one a section that only reads this. Nothing else
-- could move until this file existed. The measured order is `docs/SPLIT.md` §6.
--
-- WHAT IS AND IS NOT IN HERE. A rule every part in the world obeys is in here; a decision about
-- one zone is not. `GROUND_MATERIAL` -- which material each of the twenty floors is -- stays in
-- `ZoneBuilder`, and `groundColorOf` -- how bright ANY floor is allowed to be -- is here. That is
-- the same line 17.7 drew when it put the luminance ceiling in the builder instead of in the
-- zone's own table: a zone author says what colour the ground IS, the builder knows how bright a
-- floor may BE.
--
-- THE ONE PIECE OF MUTABLE STATE, AND WHY IT HAS ACCESSORS. `ACTIVE_FRAME` is an upvalue that
-- `newPart` reads on every one of those 534 calls and `spinForever` reads on every tween goal, so
-- it can be neither passed nor copied: a `local ACTIVE_FRAME = ZoneKit.ACTIVE_FRAME` in the
-- builder would be frozen at nil forever, silently, with no error anywhere -- exactly the trap
-- `docs/SPLIT.md` §3 rule 2 records from the MainUI split. It is reached through `setFrame` and
-- `getFrame` and nothing else, so the frame has exactly one owner.
--
-- Everything below is byte-for-byte what was at the top of `ZoneBuilder`, comments included. NINE
-- COMMENT LINES WERE REPOINTED and nothing else -- phrases like "104 call sites in this file"
-- meant ZoneBuilder and now say so, because a comment that lies about where a thing lives is the
-- most expensive line in the file to keep (GEMINI.md rule 10).
--
-- WHO MAY REQUIRE IT: any server script that builds world geometry. `HubPlaza`, `RebirthShrine`
-- and `LeaderboardService` all stand their own furniture and all re-derive some of this; they are
-- deliberately NOT changed by this move, because nobody asked for that and each of them is behind
-- its own version stamp.
--
-- Where the rest of ZoneBuilder lives: `docs/CODEMAP.md`.

local TweenService = game:GetService("TweenService")

'''

KIT_FOOTER = '''
-- ===== THE FRAME HAS EXACTLY ONE OWNER =====
-- These two are the whole interface to `ACTIVE_FRAME`. `ZoneBuilder` sets it around a builder that
-- was written for one spot and one orientation -- the portal in a Z wall, the Volcano cone, the
-- Celestial throne, the arena's return gate -- and puts back what was there before. It is never
-- read into a local on the other side of the require, for the reason in the header.
local function setFrame(cf)
	ACTIVE_FRAME = cf
end

local function getFrame()
	return ACTIVE_FRAME
end

-- Cleared at the top of Build(). The note over Build() is why it matters that this is a call and
-- not a `table.clear` from anywhere that fancies one: an audit is only worth reading for a pass
-- that actually made something, and a second pass that made nothing once printed 52 false names.
local function resetSolidSeen()
	table.clear(SOLID_SEEN)
end

return {
	newPart = newPart,
	groundColorOf = groundColorOf,
	addPlankText = addPlankText,
	vivid = vivid,
	spinForever = spinForever,
	pulseForever = pulseForever,

	setFrame = setFrame,
	getFrame = getFrame,
	auditSolidProps = auditSolidProps,
	resetSolidSeen = resetSolidSeen,

	PLATFORM_DEPTH = PLATFORM_DEPTH,
	PLATFORM_WIDTH = PLATFORM_WIDTH,
	WALL_HEIGHT = WALL_HEIGHT,
	WALL_THICK = WALL_THICK,
	PORTAL_GAP = PORTAL_GAP,
	TERRAIN_INNER = TERRAIN_INNER,
	TERRAIN_OUTER = TERRAIN_OUTER,
	TERRAIN_DEPTH = TERRAIN_DEPTH,

	SIGN_INK = SIGN_INK,
	SIGN_RIM = SIGN_RIM,
	SIGN_FACE = SIGN_FACE,
	SIGN_FONT = SIGN_FONT,
}
'''

BRIDGE = '''-- ================= the build vocabulary =================
-- THE KIT LEFT THIS FILE (18.9). `newPart` -- with the shadow-by-size rule and the
-- solidity-by-name list it applies to every part without being asked -- plus `groundColorOf`,
-- `addPlankText`, `vivid`, `spinForever`, `pulseForever`, the placement frame they all read, the
-- sign palette and the platform's own dimensions are `ServerScriptService.ZoneKit` now, byte for
-- byte, with every comment that explains why they behave the way they do. Nothing about what gets
-- built changed; only where the vocabulary lives.
--
-- WHY IT WENT FIRST, AND WHY THIS IS NOT THE JOB MainUI WAS: this file is 9,281 lines with 190
-- top-level locals, 48 of them used across spans of 600+ lines, and `newPart` is called at 534
-- sites spread over the whole of it. There is no line at which a cut leaves the locals behind --
-- which is what made MainUI's split a change of wrapper and makes this one a refactor. So the
-- vocabulary comes out first and the leaves (the village prop library, the ground clutter, the
-- idols and ruins, the mesh prop layer, the egg plaza, the boss arena) move onto it afterwards.
-- `docs/SPLIT.md` §6 is the measured order; `docs/CODEMAP.md` says where everything lives.
--
-- RE-LOCALISED RATHER THAN CALLED AS `ZoneKit.newPart(...)`, deliberately: there are 534 call
-- sites below and rewriting every one of them is 534 chances to break the world in exchange for
-- nothing visible, and a `local x = ZoneKit.x` costs exactly the register the `local function x`
-- it replaces cost. The move takes this file from 190 top-level locals to 181 -- 28 names left and
-- 19 came back -- which matters here for the same reason it matters in MainUI.
--
-- THE ONE THING THAT COULD NOT BE RE-LOCALISED IS THE FRAME. `ACTIVE_FRAME` is mutable and
-- `newPart` reads it on every call, so a copy taken here would be frozen at nil forever, silently
-- -- the trap `docs/SPLIT.md` §3 rule 2 records. It is reached through `ZoneKit.setFrame` and
-- `ZoneKit.getFrame` at the eight sites that used to assign or read it.
local ZoneKit = require(script.Parent.ZoneKit)

local newPart, groundColorOf, addPlankText = ZoneKit.newPart, ZoneKit.groundColorOf, ZoneKit.addPlankText
local vivid, spinForever, pulseForever = ZoneKit.vivid, ZoneKit.spinForever, ZoneKit.pulseForever
local PLATFORM_DEPTH, PLATFORM_WIDTH = ZoneKit.PLATFORM_DEPTH, ZoneKit.PLATFORM_WIDTH
local WALL_HEIGHT, WALL_THICK, PORTAL_GAP = ZoneKit.WALL_HEIGHT, ZoneKit.WALL_THICK, ZoneKit.PORTAL_GAP
local TERRAIN_INNER, TERRAIN_OUTER = ZoneKit.TERRAIN_INNER, ZoneKit.TERRAIN_OUTER
local TERRAIN_DEPTH = ZoneKit.TERRAIN_DEPTH
local SIGN_INK, SIGN_RIM = ZoneKit.SIGN_INK, ZoneKit.SIGN_RIM
local SIGN_FACE, SIGN_FONT = ZoneKit.SIGN_FACE, ZoneKit.SIGN_FONT
'''

# ---- the nine repointed comment lines, applied to the KIT copy only.
KIT_REPOINTS = [
    (
        "-- These two used to be declared down beside TERRAIN_PROFILE, ~3,300 lines below, which is where\n"
        "-- the long note explaining them still lives. They are up here now because the WALLS have to know\n"
        "-- them: `addRockRampart` runs 1,500 lines above the terrain section and it is the one thing in the\n"
        "-- file that stands in the same ground the terraces occupy, so it cannot be written without them.",

        "-- These two used to be declared down beside TERRAIN_PROFILE in `ZoneBuilder`, which is where the\n"
        "-- long note explaining them still lives. They came up out of it because the WALLS have to know\n"
        "-- them: `addRockRampart` runs 1,500 lines above the terrain section and it is the one thing in\n"
        "-- that file that stands in the same ground the terraces occupy, so it cannot be written without\n"
        "-- them.",
    ),
    (
        "-- The two white-floor workarounds already in this file (the patch tones below, and the cliffs) are",
        "-- The two white-floor workarounds already in `ZoneBuilder` (the patch tones, and the cliffs) are",
    ),
    (
        "-- `CastShadow = false` appears at **104 call sites** in this file and `CastShadow = true` at none:",
        "-- `CastShadow = false` appears at **104 call sites** in `ZoneBuilder` and `CastShadow = true` at\n"
        "-- none:",
    ),
    (
        "-- `CanCollide = false` appears at 418 sites in this file, and the obvious reading -- that the world",
        "-- `CanCollide = false` appears at 418 sites in `ZoneBuilder`, and the obvious reading -- that the\n"
        "-- world",
    ),
    (
        "-- The list above is a set of NAMES, and names are the one thing in this file that a per-biome",
        "-- The list above is a set of NAMES, and names are the one thing in the builder that a per-biome",
    ),
    (
        "\t-- LAST, and deliberately overriding the caller. The 104 `CastShadow = false` props in this file",
        "\t-- LAST, and deliberately overriding the caller. The 104 `CastShadow = false` props in `ZoneBuilder`",
    ),
]

# ---- what changes in ZoneBuilder besides the deletions: the eight frame/audit sites, and the two
# comments that pointed at a declaration which is no longer in this file.
ZB_PATCHES = [
    (
        "\tlocal previous = ACTIVE_FRAME\n"
        "\tACTIVE_FRAME = CFrame.new(cx, 0, wallZ) * CFrame.Angles(0, math.rad(wallZ > 0 and 90 or -90), 0)\n"
        "\tbuildPortal(model, 0, target, 1)\n"
        "\tACTIVE_FRAME = previous",

        "\tlocal previous = ZoneKit.getFrame()\n"
        "\tZoneKit.setFrame(CFrame.new(cx, 0, wallZ) * CFrame.Angles(0, math.rad(wallZ > 0 and 90 or -90), 0))\n"
        "\tbuildPortal(model, 0, target, 1)\n"
        "\tZoneKit.setFrame(previous)",
        1,
    ),
    (
        "\tlocal frame = ACTIVE_FRAME and (ACTIVE_FRAME * base) or base",
        "\tlocal active = ZoneKit.getFrame()\n"
        "\tlocal frame = active and (active * base) or base",
        1,
    ),
    (
        "\tACTIVE_FRAME = CFrame.new(-150, 0, 0)",
        "\tZoneKit.setFrame(CFrame.new(-150, 0, 0))",
        1,
    ),
    (
        "\tACTIVE_FRAME = CFrame.new(-130, 0, 0)",
        "\tZoneKit.setFrame(CFrame.new(-130, 0, 0))",
        1,
    ),
    (
        "\tlocal previous = ACTIVE_FRAME\n"
        "\tACTIVE_FRAME = CFrame.new(centre + Vector3.new(0, 0, -(R + 8))) * CFrame.Angles(0, math.rad(-90), 0)\n"
        "\tbuildPortal(model, 0, returnTarget, 1)\n"
        "\tACTIVE_FRAME = previous",

        "\tlocal previous = ZoneKit.getFrame()\n"
        "\tZoneKit.setFrame(CFrame.new(centre + Vector3.new(0, 0, -(R + 8))) * CFrame.Angles(0, math.rad(-90), 0))\n"
        "\tbuildPortal(model, 0, returnTarget, 1)\n"
        "\tZoneKit.setFrame(previous)",
        1,
    ),
    (
        "\tACTIVE_FRAME = nil",
        "\tZoneKit.setFrame(nil)",
        2,
    ),
    (
        "\ttable.clear(SOLID_SEEN)",
        "\tZoneKit.resetSolidSeen()",
        1,
    ),
    (
        "\tauditSolidProps()\n",
        "\tZoneKit.auditSolidProps()\n",
        1,
    ),
    (
        "-- TERRAIN_INNER / TERRAIN_OUTER / TERRAIN_DEPTH are declared at the top of the file, beside\n"
        "-- PLATFORM_WIDTH -- see the note there. They moved because `addRockRampart` needs them and it is\n"
        "-- written 2,400 lines above this point.",

        "-- TERRAIN_INNER / TERRAIN_OUTER / TERRAIN_DEPTH are declared in `ZoneKit`, beside PLATFORM_WIDTH\n"
        "-- -- see the note there. They left this section because `addRockRampart` needs them and it is\n"
        "-- written 2,400 lines above this point.",
        1,
    ),
    (
        "-- slightly emptier zone and never a broken one. (ACTIVE_ZONE_KEY is declared at the top of the\n"
        "-- file, beside ACTIVE_FRAME -- addLandmark needs it too and is written far above this point.)",

        "-- slightly emptier zone and never a broken one. (ACTIVE_ZONE_KEY is declared at the top of the\n"
        "-- file, where ACTIVE_FRAME stood before it became `ZoneKit`'s -- addLandmark needs it too and is\n"
        "-- written far above this point.)",
        1,
    ),
]


def main():
    if KIT.exists():
        sys.exit("ZoneKit.lua already exists -- refusing to run twice")

    text = io.open(ZB, encoding="utf-8", newline="").read()
    lines = text.split("\n")

    for n, prefix in BOUNDS:
        got = lines[n - 1]
        assert got.startswith(prefix), "line %d: expected %r, got %r" % (n, prefix, got)
    # every block is followed by one blank line, which is deleted with it
    for _first, last in BLOCKS:
        assert lines[last] == "", "line %d should be blank, got %r" % (last + 1, lines[last])

    body = "\n\n".join("\n".join(lines[f - 1:l]) for f, l in BLOCKS)
    for old, new in KIT_REPOINTS:
        assert body.count(old) == 1, "kit repoint not unique: %r" % old[:70]
        body = body.replace(old, new)
    KIT.write_text(KIT_HEADER + body + "\n" + KIT_FOOTER, encoding="utf-8", newline="")

    # rebuild ZoneBuilder: the first block's place is taken by the bridge, the rest just go.
    out, cut = [], 0
    keep = [True] * len(lines)
    for f, l in BLOCKS:
        for i in range(f - 1, l + 1):        # +1: the trailing blank line goes too
            keep[i] = False
            cut += 1
    for i, line in enumerate(lines):
        if i == BLOCKS[0][0] - 1:
            out.append(BRIDGE)
        if keep[i]:
            out.append(line)
    rest = "\n".join(out)

    for old, new, count in ZB_PATCHES:
        assert rest.count(old) == count, "ZoneBuilder patch %r: expected %d, found %d" % (
            old.strip()[:60], count, rest.count(old))
        rest = rest.replace(old, new)
    assert "ACTIVE_FRAME =" not in rest, "an ACTIVE_FRAME assignment survived in ZoneBuilder"
    ZB.write_text(rest, encoding="utf-8", newline="")

    print("ZoneKit.lua   %d lines" % (KIT.read_text(encoding="utf-8").count("\n") + 1))
    print("ZoneBuilder   %d lines (was %d), %d lines cut" % (
        ZB.read_text(encoding="utf-8").count("\n") + 1, len(lines), cut))


main()
