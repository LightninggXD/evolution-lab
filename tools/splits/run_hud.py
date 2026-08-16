#!/usr/bin/env python3
"""Drive `extract.py` over every remaining MainUI closure block, in order.

The reason this is a driver and not twenty shell lines: `--publish` INSERTS a line into MainUI
(`hudRefs.x = x`, under x's own definition), so every extraction shifts the line numbers of every
block below it. A hard-coded list of ranges is wrong after the first one.

So blocks are identified by (section heading, size in lines) -- both stable under shifting -- and
the range is re-derived from `splitplan.py` immediately before each extraction. Two pairs of
blocks share a heading ("WELCOME BACK", "ACTIVE POTION TIMERS"), which is why size is in the key.

    py tools/splits/run_hud.py --dry
    py tools/splits/run_hud.py
    py tools/splits/run_hud.py --only SeasonPass
"""

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
PY = sys.executable

# (size, heading fragment, module name, publish, one-line description)
JOBS = [
    (103, "SCROLL AFFORDANCE", "ScrollAffordance", "",
     "the generic pass that gives all 15 ScrollingFrames a visible bar and a fade at the cut."),
    (88, "two tile columns", "TileColumnFit", "RIGHT_COLS",
     "the responsive pass that tightens the two HUD tile columns to the viewport."),
    (414, "EGGS", "EggShop", "PANEL_ANCHOR,robuxPanel",
     "the egg stall panel: the three eggs, their odds table and the hatch buttons (10.19)."),
    (188, "AUDIO", "AudioPanel", "PANEL_ANCHOR,columnTile",
     "the audio settings panel and its HUD tile: music and SFX volume (Phase 4.6)."),
    (200, "WELCOME BACK", "Quests", "",
     "the daily quest board: three rotating goals, their progress and their claim."),
    (213, "WELCOME BACK", "WelcomeBack", "PANEL_ANCHOR,dayNumber,refreshRewardPanel,rewardPanel,togglePanels",
     "the offline-earnings card shown once on join -- what the game made while you were gone."),
    (927, "Season Pass", "SeasonPass", "PANEL_ANCHOR,columnTile",
     "the whole Season Pass: the track, the free and premium rows, the claim and the tile."),
    (790, "HOW MANY PLAYERS OWN THIS", "JournalGrid",
     "CHAR_CELL_H,CHAR_LINE_H,CHAR_PER_LINE,characterCells,characterPanel,characterRows,characterScroll,ownershipText",
     "the Journal's 100-skin grid: the discs, their rarity ribbons and the ownership readout."),
    (27, "CURRENCY CAPSULES", "CurrencyPlus", "diamondPill,dnaPill,robuxPanel",
     "the `+` buttons on the DNA and Diamond capsules, which open the Robux shop."),
    (170, "PASS SHOP", "PassShop", "robuxGrid,robuxPanel",
     "the game-pass tab of the Robux shop -- a second tab on the same panel, not a second panel."),
    (181, "PRODUCT TILES", "ProductTiles", "robuxGrid",
     "the developer-product tiles in the Robux shop: the DNA packs and the consumables."),
    (96, "INVENTORY TABS", "InventoryTabs", "inventoryPanel,petsPanel,refreshInventoryPanel",
     "the tab strip that swaps the Inventory panel between potions and pets."),
    (124, "TWO WAYS INTO THE WHEEL", "WheelEntry", "SECONDS_PER_DAY,dayNumber,rewardPanel",
     "the free daily spin and the paid spin -- the two doors into the prize wheel (5.6 + 9.4)."),
    (95, "CODES", "Codes", "rewardPanel",
     "the promo-code box on the rewards board and the remote behind it (Phase 5.1)."),
    (95, "FOUR RUNGS", "RebirthRungs", "rebirthReqCard,rebirthReqLabel",
     "the four rebirth milestones drawn as rungs, so 4/4 is not an empty amber box (18.4)."),
    (81, "REBIRTH BEACON", "RebirthBeacon", "rebirthButton",
     "the arrow that appears on the Rebirth tile only when a rebirth is actually affordable."),
    (392, "Pet Fusion", "PetFusion", "PANEL_ANCHOR,colorTag,petDisplayInfo",
     "the Pet Fusion panel: the slots, the odds and the fuse button."),
    (144, "Release confirmation", "PetRelease", "colorTag",
     "the confirm shade for releasing pets -- the one destructive action in the pet bag."),
    (187, "ACTIVE POTION TIMERS", "PetsActions", "petsPanel,shopFrame",
     "the Pets panel's bulk action row: equip best, release duplicates, and the way out to Fusion."),
    (644, "ACTIVE POTION TIMERS", "PotionTimers", "",
     "the bottom-left stack of active potion timers -- how long each boost has left."),
]


def ranges():
    out = subprocess.run([PY, str(ROOT / "tools/splitplan.py")],
                         capture_output=True, text=True, cwd=ROOT).stdout
    found = {}
    for line in out.splitlines():
        parts = line.split(None, 2)
        if len(parts) == 3 and "-" in parts[0] and parts[1].isdigit():
            found.setdefault((int(parts[1]), parts[2].strip()), parts[0])
    return found


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("--only", default=None)
    args = ap.parse_args()

    for size, frag, name, publish, what in JOBS:
        if args.only and args.only != name:
            continue
        rng = next((r for (sz, lab), r in ranges().items() if sz == size and frag in lab), None)
        if rng is None:
            print("SKIP %-18s no block of %d lines under a heading matching %r"
                  % (name, size, frag))
            continue
        cmd = [PY, str(ROOT / "tools/splits/extract.py"), rng, name, "--what", what]
        if publish:
            cmd += ["--publish", publish]
        if args.dry:
            cmd.append("--dry")
        r = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT)
        sys.stdout.write(r.stdout)
        if r.returncode:
            sys.stdout.write(r.stderr)
            print("STOPPED at %s" % name)
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
