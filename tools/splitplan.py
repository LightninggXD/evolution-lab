#!/usr/bin/env python3
"""List the blocks of MainUI that are still waiting to become modules, biggest first.

WHAT IT LOOKS FOR, AND WHY THAT IS THE RIGHT THING TO LOOK FOR
--------------------------------------------------------------
`MainUI` sits on Luau's 200-register ceiling, and the standing rule in this project is that
anything substantial goes inside `;(function() ... end)()` so it gets a register file of its
own. Twenty-three blocks were written that way -- and a closure that escapes nothing is
exactly what a module is. So the split does not need designing: the register cap already did
it, and this script reads the answer back out.

For each block it reports the captured upvalues -- the names defined at MainUI's top level
that the block reads. That set is the module's `hud` contract, and a block with a small one is
a cheap extraction. Names the block declares itself are excluded; so are comments, because a
name only mentioned in prose is not a dependency.

    py tools/splitplan.py             # blocks not yet extracted, biggest first
    py tools/splitplan.py --deps      # with each block's captured set

IT OVER-REPORTS RATHER THAN UNDER-REPORTS. Matching is textual, so a table key that happens to
share a name with a top-level local (`size`, `color`, `text`) shows up as a dependency it is
not. Read the list as "no more than this", check the handful that matter, and let `luascope.py`
be the thing that proves the extraction afterwards.
"""

import argparse
import io
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAIN = ROOT / "src/StarterPlayer/StarterPlayerScripts/MainUI.client.lua"

OPEN = re.compile(r"^;?\(function\(\)\s*$")
CLOSE = re.compile(r"^end\)\(\)\s*$")

sys.path.insert(0, str(Path(__file__).resolve().parent))
from codemap import headings  # noqa: E402  -- one definition of "what is a heading" in the repo

# services and modules a module requires for itself -- not part of the hud contract
SELF_SERVED = {
    "Players", "RS", "RunService", "TweenService", "GameConfig", "PetModel", "SoundLibrary",
    "Remotes", "player", "playerGui", "UITheme", "UIKit",
    # the drawing kit, which now comes from ReplicatedStorage.Modules.UIKit
    "formatNumber", "stroke", "gradient", "corner", "shade", "gradientForColor", "themeLabel",
    "liftChildren", "styleCard", "styleButton", "setButtonColor", "OUTLINE_COLOR",
    "DISPLAY_FONT", "PANEL_SHELL", "PET_ROW_SHELL", "READY_RIM",
}


def top_level_names(lines):
    """Every name bound at column 0 -- `local a, b = ...`, `local function f`, `function f`."""
    names = set()
    for l in lines:
        m = re.match(r"^local\s+function\s+([A-Za-z_]\w*)", l) or \
            re.match(r"^function\s+([A-Za-z_]\w*)", l)
        if m:
            names.add(m.group(1))
            continue
        m = re.match(r"^local\s+([A-Za-z_][\w,\s]*?)\s*=", l)
        if m:
            for n in m.group(1).split(","):
                names.add(n.strip())
    return names


def blocks(lines, path):
    opens = [i for i, l in enumerate(lines) if OPEN.match(l)]
    closes = [i for i, l in enumerate(lines) if CLOSE.match(l)]
    # A block is named by the section heading it falls under -- the same headings the CODEMAP
    # navigates by, so the two registers agree about what a thing is called.
    heads = headings(path)
    out = []
    for s in opens:
        e = next((c for c in closes if c > s), len(lines) - 1)
        label = ""
        for idx, text in heads:
            if idx < s:
                label = text
            else:
                break
        out.append({"start": s + 1, "end": e + 1, "lines": e - s + 1, "label": label})
    return out


def captured(lines, blk, names):
    body = lines[blk["start"]:blk["end"] - 1]
    code = "\n".join(l.split("--")[0] for l in body)
    inner = set()
    for l in body:
        for m in re.finditer(r"\blocal\s+(?:function\s+)?([A-Za-z_][\w,\s]*?)\s*(?:=|\()", l):
            for n in m.group(1).split(","):
                inner.add(n.strip())
    return sorted(n for n in names
                  if n not in inner and n not in SELF_SERVED
                  and re.search(r"\b" + re.escape(n) + r"\b", code))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--deps", action="store_true", help="show each block's captured set")
    ap.add_argument("--path", default=str(MAIN))
    args = ap.parse_args()

    lines = io.open(args.path, encoding="utf-8", newline="").read().split("\n")
    names = top_level_names(lines)
    bs = sorted(blocks(lines, args.path), key=lambda b: -b["lines"])

    print("%s -- %d lines, %d closure blocks still inline, %d of them"
          % (Path(args.path).name, len(lines), len(bs), sum(b["lines"] for b in bs)))
    print()
    print("%-14s %6s  %s" % ("lines", "size", "block"))
    for b in bs:
        print("%-14s %6d  %s" % ("%d-%d" % (b["start"], b["end"]), b["lines"], b["label"][:72]))
        if args.deps:
            deps = captured(lines, b, names)
            print("%-14s %6s  hud: %s" % ("", "", ", ".join(deps) if deps else "(nothing)"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
