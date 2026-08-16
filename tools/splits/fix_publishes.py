#!/usr/bin/env python3
"""Repair `hudRefs.x = x` lines that `extract.py --publish` put in the wrong place.

TWO FAULTS, ONE CAUSE. `extract.py` asked `luamap` where a top-level name's definition ENDS and
inserted the publish line under it. `luamap` counts Lua BLOCKS (`function`/`if`/`do`/`end`) and
does not count brackets -- so for

    local dnaPill = UITheme.Pill(currencyStack, {
        name = "DNAPill", ...
    })

it reports the statement as one line long, and the publish landed on line two, inside the table
constructor. That is a hard syntax error: `Expected '}' ... got '='`. The second fault is
cosmetic -- a name published by four different extractions got four identical lines.

This finds every `hudRefs.x = x` written at column 0, drops the duplicates, and moves any that
sits at non-zero BRACKET depth down to the first line where the brackets close again.

    py tools/splits/fix_publishes.py --dry
    py tools/splits/fix_publishes.py
"""

import argparse
import io
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from luastruct import tokens  # noqa: E402  (comment- and string-aware)

MAIN = ROOT / "src/StarterPlayer/StarterPlayerScripts/MainUI.client.lua"
PUBLISH = re.compile(r"^hudRefs\.([A-Za-z_]\w*) = \1$")
OPENERS, CLOSERS = "([{", ")]}"


def bracket_depth_by_line(text, nlines):
    """Bracket depth at the START of each 1-indexed line."""
    depth_at = [0] * (nlines + 2)
    depth = 0
    seen = 1
    for kind, tok, line in tokens(text):
        while seen < line:
            seen += 1
            depth_at[seen] = depth
        if kind == "punct":
            if tok in OPENERS:
                depth += 1
            elif tok in CLOSERS:
                depth -= 1
    while seen < nlines + 1:
        seen += 1
        depth_at[seen] = depth
    return depth_at


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry", action="store_true")
    args = ap.parse_args()

    text = io.open(MAIN, encoding="utf-8", newline="").read()
    lines = text.split("\n")
    depth_at = bracket_depth_by_line(text, len(lines))

    seen, drop, move = set(), [], []
    for i, l in enumerate(lines):
        m = PUBLISH.match(l)
        if not m:
            continue
        name = m.group(1)
        if name in seen:
            drop.append(i)
            continue
        seen.add(name)
        if depth_at[i + 1] > 0:
            # walk forward to the first line that starts with the brackets closed again
            j = i + 1
            while j < len(lines) and depth_at[j + 1] > 0:
                j += 1
            move.append((i, j))

    print("%d publish lines, %d duplicates to drop, %d inside brackets to move"
          % (len(seen) + len(drop), len(drop), len(move)))
    for i, j in move:
        print("  line %d  %s  ->  line %d, under `%s`"
              % (i + 1, lines[i], j, lines[j - 1].strip()))
    if args.dry:
        return 0

    # Apply from the bottom so earlier indices stay valid: a move is a delete plus an insert.
    # `j` is the 0-indexed first line PAST the constructor; removing the publish line from above
    # it shifts it down one, so the insert goes at j-1 to land immediately after the `})`.
    for i, j in sorted(move, reverse=True):
        text_line = lines.pop(i)
        lines.insert(j - 1, text_line)
    for i in sorted(drop, reverse=True):
        del lines[i]

    MAIN.write_text("\n".join(lines), encoding="utf-8", newline="")
    print("MainUI now %d lines" % len(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
