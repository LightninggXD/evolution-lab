#!/usr/bin/env python3
"""Split GameConfig into sixteen ordered parts, children of the module itself.

WHY THIS ONE IS SAFE, WHICH IS NOT OBVIOUS FOR A FILE EVERY SCRIPT REQUIRES
---------------------------------------------------------------------------
`GameConfig` is 5,205 lines and has exactly **21 top-level locals**, and every one of them is
used inside a span of a few dozen lines around its own definition -- `scaleRange` at 558 is read
at 596-598, `CHARACTER_BY_KEY` at 4287 at 4290-4927. Nothing crosses a section heading. That was
measured before a line was moved, and it is what makes the cut clean: the boundaries below are
chosen so no local ever has to leave the file it is declared in.

The one name that is genuinely global to the file is `GameConfig` itself, so each part is

    return function(GameConfig) ... end

and writes into the table it is handed. The public shape does not change at all: `GameConfig`
still returns one table with the same fields, so **no call site anywhere in the game changes**.

ORDER IS LOAD-BEARING. Several sections build tables at load time out of what earlier sections
put on the table (`CHARACTERS_BY_STAGE` reads `GameConfig.Stages`), so the parts are required in
exactly the order they appeared in the file, and the loader says so.

THE BODIES ARE NOT RE-INDENTED. They sit at column 0 inside the function, which looks odd for
about a minute and means every moved line is byte-identical to what it replaced -- so a diff of
this commit shows a pure move, and a comment that took three sessions to write cannot be lost to
a whitespace pass.
"""

import io
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
SRC = ROOT / "src/ReplicatedStorage/Modules/GameConfig.lua"
DEST = ROOT / "src/ReplicatedStorage/Modules/GameConfig"

# (first line, name, what it is). The last part runs to `return GameConfig`.
PARTS = [
    (3, "Evolution", "the 20-stage chain, the XP curve, the damage ladder, the raised layers "
                     "and the income curve -- the numbers everything else is priced against"),
    (337, "Upgrades", "the four DNA upgrades and the mutation table"),
    (412, "Zones", "the 20 zones, their bosses, where a boss stands, boss revive and the "
                   "zone lookup helpers"),
    (698, "Pets", "the whole pet system: rarities, the per-zone species, eggs and their odds, "
                  "enchants, bag size and what an equipped team is worth"),
    (1776, "Rebirth", "the rebirth curve, the four milestones and what a rebirth pays"),
    (1951, "Rewards", "the seven-day daily board and the group/community rewards"),
    (1989, "Potions", "the three potion kinds in three sizes, and the health bottle's two numbers"),
    (2133, "Shops", "the boss arena, which shop stands in which zone, the mystery potion kiosk "
                    "and the lucky spin"),
    (2457, "Diamonds", "the premium currency: what it costs, and every way playing earns it"),
    (2701, "Mastery", "stage mastery, how speed scales with the body, and the playtime gifts"),
    (2807, "RobuxShop", "the developer products and the nine game passes"),
    (3141, "Events", "limited-time events: the UTC windows, the effects they reuse and which "
                     "skin an occurrence hands over"),
    (3585, "Season", "the season pass track and how a season turns over on its own"),
    (3783, "Helpers", "the shared accessors, the upgrade caps and the DNA Splicer"),
    (3945, "Characters", "the 100 skins by stage, the VIP wardrobe, the event-exclusive skins "
                         "and everything that reads damage or health off a costume"),
    (5112, "Codes", "promo codes and the offline earnings window"),
]

HEAD = '''-- GameConfig -- every number in the game, in sixteen parts.
--
-- WHY IT IS SPLIT (18.9)
-- ----------------------
-- It was 5,205 lines and ~83k tokens to read whole, and it is required by every script in the
-- place, so any session that needed one constant paid for all of them. The parts below are its
-- own section headings, unchanged; `docs/codemap/GameConfig.md` maps them.
--
-- THE PUBLIC SHAPE DID NOT CHANGE. This still returns one table with the same fields, so no call
-- site anywhere in the game changed -- `require(RS.Modules.GameConfig).Zones` is what it always
-- was. Each part is `return function(GameConfig) ... end` and writes into the table it is handed.
--
-- THE CUT IS CLEAN BECAUSE OF A MEASUREMENT, not a hope: the file had 21 top-level locals and
-- every one was used within a few dozen lines of its own definition, none crossing a section
-- heading. The boundaries were chosen so no local has to leave the part it is declared in.
--
-- ORDER IS LOAD-BEARING AND THIS LIST IS THE ORDER. Several parts build tables at load time out
-- of what earlier parts put on the table -- `Characters` reads `GameConfig.Stages`, `Zones` reads
-- the damage ladder -- so they are required in exactly the order they were written in. Moving a
-- name up this list is a silent nil at load time, not an error.
local GameConfig = {}

for _, part in ipairs({
'''


def main():
    if DEST.exists():
        sys.exit("GameConfig/ already exists -- refusing to run twice")

    lines = io.open(SRC, encoding="utf-8", newline="").read().split("\n")
    assert lines[0] == "local GameConfig = {}", lines[0]
    tail = next(i for i, l in enumerate(lines) if l == "return GameConfig")

    bounds = [p[0] for p in PARTS] + [tail + 1]
    DEST.mkdir(parents=True)

    for idx, (start, name, what) in enumerate(PARTS):
        end = bounds[idx + 1] - 1                      # 1-indexed, inclusive
        body = lines[start - 1:end]
        while body and body[-1].strip() == "":
            body.pop()
        head = [
            "-- GameConfig.%s -- %s." % (name, what),
            "--",
            "-- ONE OF THE SIXTEEN PARTS OF `GameConfig` (18.9), moved byte for byte. It is handed the",
            "-- shared config table and writes into it; see the loader in `GameConfig` itself for why",
            "-- the order of the parts is load-bearing and why nothing here is re-indented.",
            "",
            "return function(GameConfig)",
            "",
        ]
        (DEST / (name + ".lua")).write_text(
            "\n".join(head + body) + "\n\nend\n", encoding="utf-8", newline="")
        print("%-12s %5d-%-5d %5d lines" % (name, start, end, len(body)))

    loader = [HEAD.rstrip("\n")]
    for _, name, _w in PARTS:
        loader.append('\t"%s",' % name)
    loader += [
        "}) do",
        "\trequire(script:WaitForChild(part))(GameConfig)",
        "end",
        "",
        "return GameConfig",
        "",
    ]
    SRC.write_text("\n".join(loader), encoding="utf-8", newline="")
    print("\nGameConfig.lua is now %d lines" % (len(loader)))


main()
