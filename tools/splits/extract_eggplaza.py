"""Move the eggs and the stall they stand on out of ZoneBuilder into
ServerScriptService/EggPlaza.lua.

STEP 6 of `docs/SPLIT.md` §6. 968 lines, and the biggest REGISTER win of the whole split:
**thirty-four top-level names leave and one comes back**, because an egg is built out of a dozen
small pieces (`eggBall`, `eggSurface`, `buildCrystalNest`, `buildEggMesh`, `buildEgg`,
`buildEggOddsBoard`, `buildEggFeaturePet`, `orbitForever`, `addEggShowcase`, `makePriceCard`,
`addStallDressing`) plus the tier style table, the shell dimensions and the plaza's own palette --
and every one of those is read only by the next one along.

  ESCAPES: buildEggPlaza.
  IMPORTS: five names from `ZoneKit`, and five requires it does for itself -- `RS`, `GameConfig`,
           `PetModel`, `CollectionService`, `TweenService`. Nothing at all from `ZoneBuilder`.

`built` LOOKED LIKE A SIXTH IMPORT AND IS NOT. `local built = {}` inside `buildEggPlaza` is the
list of shells it returns, and `local built = false` at the bottom of `ZoneBuilder` is the
"has Build() run" flag. Same name, different scopes, no relationship -- and a name-based scan
reports the inner one as a read of the outer. Worth writing down because the next scan will say it
again.

WHY THE EGGS AND THE PLAZA GO TOGETHER: the plaza is what the eggs stand on and is the only caller
of `buildEgg`, `addEggShowcase`, `buildEggOddsBoard` and `makePriceCard`. Splitting them would put
a boundary through the middle of one screen.

WHAT DOES NOT MOVE: where the plaza goes. `Build()` still decides that each zone's shop stands at
`cx - 150` and calls in once per zone with the eggs that zone sells, read from `GameConfig`.

NO GEOMETRY CHANGES, SO `BUILD_VERSION` IS NOT BUMPED. What this owes evidence for is a rebuild and
a look at a plaza -- three shells on their podiums, the odds board readable, the price cards
present. `docs/CODEMAP.md` says a lint is not evidence about a picture.
"""
import io
import re
import sys
from pathlib import Path

ROOT = Path(r"C:\Users\Kristina\Documents\evolution-lab")
ZB = ROOT / "src/ServerScriptService/ZoneBuilder.lua"
EP = ROOT / "src/ServerScriptService/EggPlaza.lua"

EGGS = (1920, 2887)   # -- ===== EGGS ===== through the end of buildEggPlaza

BOUNDS = [
    (1919, ""),
    (1920, "-- ===== EGGS ====="),
    (2886, "end"),
    (2887, ""),
    (2888, "-- ===== BOSS EVENT ARENA ====="),
]

EP_HEADER = '''-- EggPlaza -- the three eggs a zone sells and the stall they stand on.
--
-- One per zone, in the middle of the street where the shop is: a planked deck, three stone podiums,
-- a shell on each, an odds board behind them and a price card in front. It is the first thing a
-- player walks into in every zone and the reason they are in the zone at all, so it gets a built
-- stage rather than three props on the floor.
--
-- WHERE THE LINE IS: this file builds the plaza. `ZoneBuilder` decides WHERE it goes -- `Build()`
-- stands each zone's shop at cx - 150 and calls in once per zone with the eggs that zone sells,
-- read from `GameConfig`. Nothing about the layout of a zone is in here.
--
-- WHY IT IS ONE FILE AND NOT TWO. The eggs and the plaza are one screen: the plaza is what the
-- eggs stand on and is the only caller of `buildEgg`, `addEggShowcase`, `buildEggOddsBoard` and
-- `makePriceCard`. A boundary between them would run through the middle of the thing a player
-- looks at.
--
-- IT WAS ALSO THIRTY-FOUR TOP-LEVEL NAMES IN A FILE THAT LIVES UNDER LUAU'S 200-REGISTER CEILING,
-- and one of them escaped. An egg is built out of a dozen small pieces and each is read only by the
-- next one along, which is exactly the shape that should be behind a require.
--
-- WHO MAY REQUIRE IT: any server script standing an egg stall. `ZoneBuilder` today. `HubPlaza`
-- builds its own and is deliberately untouched.
--
-- Where the rest of the world is built: `docs/CODEMAP.md`, `docs/SPLIT.md` §6.

local RS = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local GameConfig = require(RS.Modules.GameConfig)
local PetModel = require(RS.Modules.PetModel)

local ZoneKit = require(script.Parent.ZoneKit)

local newPart, addLight, lighten = ZoneKit.newPart, ZoneKit.addLight, ZoneKit.lighten
local pulseForever, SIGN_FONT = ZoneKit.pulseForever, ZoneKit.SIGN_FONT

'''

EP_FOOTER = '''
-- One name. The dozen builders above are all reached through this, which is the single line in
-- `ZoneBuilder.Build()` that reads this file -- see the header for why the surface is not twelve
-- verbs wide.
return {
	buildEggPlaza = buildEggPlaza,
}
'''

ZB_POINTER = '''-- ===== THE EGGS AND THEIR STALL LEFT THIS FILE (18.14) =====
--
-- `ServerScriptService.EggPlaza` -- the tier style table and the shell dimensions, `eggBall`,
-- `eggSurface`, `buildCrystalNest`, `buildEggMesh`, `buildEgg`, `buildEggOddsBoard`,
-- `buildEggFeaturePet`, `orbitForever`, `addEggShowcase`, `makePriceCard`, `addStallDressing` and
-- `buildEggPlaza` itself. 968 lines and **thirty-four top-level names**, the biggest register win
-- of the split: this file goes from 130 of Luau's 200 to **97**, its first time under a hundred.
--
-- ONE NAME COMES BACK. An egg is built out of a dozen small pieces and each is read only by the
-- next one along, so the whole stall has a single entry point.
--
-- WHAT DID NOT MOVE: where the plaza goes. `Build()` below still stands each zone's shop at
-- cx - 150 and calls in with the eggs that zone sells, read from `GameConfig`.
local EggPlaza = require(script.Parent.EggPlaza)'''


def main():
    if EP.exists():
        sys.exit("EggPlaza.lua already exists -- refusing to run twice")

    text = io.open(ZB, encoding="utf-8", newline="").read()
    lines = text.split("\n")
    for n, prefix in BOUNDS:
        got = lines[n - 1]
        assert got.startswith(prefix), "line %d: expected %r, got %r" % (n, prefix, got)

    body = "\n".join(lines[EGGS[0] - 1:EGGS[1]])

    for stayed in ("scatterPoint", "reserveScatter", "scaled", "VillageKit", "BiomeDecor",
                   "decorationBuilders", "ZoneTerrain", "buildPortal", "GROUND_MATERIAL",
                   "SHOP_Z", "PROMPT_REACH", "ARENA_VERSION", "STREET_HALF", "ARRIVAL_Z"):
        hits = [(i, l.strip()[:100]) for i, l in enumerate(body.split("\n"), 1)
                if re.search(r"(?<![\w.:])%s\b" % stayed, l) and not l.strip().startswith("--")]
        assert not hits, "%s is used in the moved text but stays in ZoneBuilder: %r" % (stayed, hits)

    EP.write_text(re.sub(r"\n\n\n+", "\n\n", EP_HEADER + body + "\n" + EP_FOOTER),
                  encoding="utf-8", newline="")

    out = []
    for i, line in enumerate(lines, 1):
        if i == EGGS[0]:
            out.append(ZB_POINTER)
            out.append("")
        if not (EGGS[0] <= i <= EGGS[1]):
            out.append(line)
    rest = "\n".join(out)

    hits = re.findall(r"(?<![\w.:])buildEggPlaza\(", rest)
    assert len(hits) == 1, "expected one buildEggPlaza call site, found %d" % len(hits)
    rest = re.sub(r"(?<![\w.:])buildEggPlaza\(", "EggPlaza.buildEggPlaza(", rest)

    for gone in ("local EGG_TIER_STYLE", "local EGG_SHELL_SIZE", "local function eggBall",
                 "local function eggSurface", "local function buildCrystalNest",
                 "local function buildEggMesh", "local function buildEgg(",
                 "local function buildEggOddsBoard", "local function buildEggFeaturePet",
                 "local function orbitForever", "local function addEggShowcase",
                 "local function makePriceCard", "local function addStallDressing",
                 "local function buildEggPlaza", "local PLAZA_Z"):
        assert gone not in rest, "%r still in ZoneBuilder" % gone

    ZB.write_text(rest, encoding="utf-8", newline="")

    print("EggPlaza.lua    %d lines" % (EP.read_text(encoding="utf-8").count("\n") + 1))
    print("ZoneBuilder     %d lines (was %d)" % (rest.count("\n") + 1, len(lines)))


main()
