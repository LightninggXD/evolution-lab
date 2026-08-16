#!/usr/bin/env python3
"""Move one `;(function() ... end)()` block out of MainUI into a HUD module.

    py tools/splits/extract.py 6834-7760 SeasonPass
    py tools/splits/extract.py 8403-8615 Quests --publish rewardPanel,dayNumber
    py tools/splits/extract.py 5147-5327 ProductTiles --dry

WHY A TOOL AND NOT A HAND EDIT
------------------------------
There are twenty-odd of these to do and every one is the same five steps, three of which are
easy to get subtly wrong: which services the block needs, which of MainUI's locals it captured,
and whether a captured name is filled at the call site yet. Doing it by hand once produced a
correct module; doing it by hand twenty times would not. And every comment in this codebase is
load-bearing (GEMINI.md rule 10) -- a script moves 900 lines byte for byte, a copy-paste drops
one and nobody notices for a month.

WHAT IT WORKS OUT FOR ITSELF
----------------------------
* **The preamble.** It scans the body for each service and module MainUI requires at its top and
  emits only the ones that are actually used, so a module that never touches sound does not
  require SoundLibrary.
* **The kit.** `styleCard`, `themeLabel` and friends come from `Modules.UIKit` now; the same
  scan decides which of them to bind.
* **The `hud` contract.** Everything else the block reads that is a top-level local of MainUI
  becomes `local x = hud.x`. A name is only counted when it is READ -- `\bname\b` followed by a
  single `=` is a table key or an assignment target, not a dependency, and that filter is what
  keeps `size`, `color` and `text` out of the list.

WHAT IT REFUSES TO DO
---------------------
It will not run if a dependency is not published on `hudRefs` at the moment the block is
reached. That is the failure this whole design exists to prevent: a module handed a nil helper
does not error, it silently draws nothing. Pass `--publish name` and the tool inserts
`hudRefs.name = name` directly under that name's own definition (never at the end of the file --
see docs/SPLIT.md §3).
"""

import argparse
import io
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from luamap import build_map  # noqa: E402

MAIN = ROOT / "src/StarterPlayer/StarterPlayerScripts/MainUI.client.lua"
DESTDIR = ROOT / "src/ReplicatedStorage/Modules/HUD"

# name -> the line that reproduces it inside a module. Order is the order they are emitted in.
PREAMBLE = [
    ("Players", 'local Players = game:GetService("Players")'),
    ("RS", 'local RS = game:GetService("ReplicatedStorage")'),
    ("RunService", 'local RunService = game:GetService("RunService")'),
    ("TweenService", 'local TweenService = game:GetService("TweenService")'),
    ("UserInputService", 'local UserInputService = game:GetService("UserInputService")'),
    ("MarketplaceService", 'local MarketplaceService = game:GetService("MarketplaceService")'),
    ("ProximityPromptService",
     'local ProximityPromptService = game:GetService("ProximityPromptService")'),
    ("", ""),
    ("GameConfig", "local GameConfig = require(RS.Modules.GameConfig)"),
    ("PetModel", "local PetModel = require(RS.Modules.PetModel)"),
    ("SoundLibrary", 'local SoundLibrary = require(RS.Modules:WaitForChild("SoundLibrary"))'),
    ("UITheme", "local UITheme = require(RS.Modules.UITheme)"),
    ("__KIT__", 'local UIKit = require(RS.Modules:WaitForChild("UIKit"))'),
    ("", ""),
    ("Remotes", "local Remotes = RS.Remotes"),
    ("player", "local player = Players.LocalPlayer"),
    ("playerGui", 'local playerGui = player:WaitForChild("PlayerGui")'),
]

KIT = ["formatNumber", "stroke", "gradient", "corner", "shade", "gradientForColor", "themeLabel",
       "liftChildren", "styleCard", "styleButton", "setButtonColor",
       "OUTLINE_COLOR", "DISPLAY_FONT", "PANEL_SHELL", "PET_ROW_SHELL", "READY_RIM", "LIP_DEPTH"]

# `RS` is implied by any require; `player` by `playerGui`. Emitted even when the body never
# names them directly, because the preamble lines above depend on them.
IMPLIES = {"GameConfig": ["RS"], "PetModel": ["RS"], "SoundLibrary": ["RS"], "UITheme": ["RS"],
           "__KIT__": ["RS"], "Remotes": ["RS"], "player": ["Players"],
           "playerGui": ["player", "Players"]}

SELF_SERVED = {n for n, _ in PREAMBLE if n} | set(KIT) | {"UIKit"}


def top_level(lines):
    """{name: (start, end)} 1-indexed, for every name bound at MainUI's top level.

    COLUMN 0 IS THE TEST, and it has to be. `luamap` classifies with a leading `^\\s*`, so an
    indented `local color = ...` inside a block its depth counter got wrong is reported as a
    top-level name -- and then `color`, `name` and `text` show up as dependencies of half the
    panels in the file. Nothing in this file is declared at top level with indentation.
    """
    out = {}
    for e in build_map(str(MAIN))[0]:
        if e["name"] and re.match(r"^[A-Za-z_]\w*$", e["name"]) \
                and re.match(r"^(local\s|function\s)", lines[e["start"]]):
            out.setdefault(e["name"], (e["start"] + 1, e["end"] + 1))
    for i, l in enumerate(lines):                       # multi-name `local a, b = ...`
        m = re.match(r"^local\s+([A-Za-z_][\w,\s]*?)\s*=", l)
        if m and "," in m.group(1):
            for n in m.group(1).split(","):
                out.setdefault(n.strip(), (i + 1, i + 1))
    return out


def reads(body_code, name):
    """True when `name` is READ in the body as a bare identifier.

    Two things that look like a use and are not: `name = x` is a table key or a write, and
    `thing.name` is a field on somebody else's object. Both are extremely common in this file --
    every `UITheme.Card{ color = ..., text = ... }` call has several -- and counting them turns
    the dependency list into noise.
    """
    return re.search(r"(?<![.:\w])" + re.escape(name) + r"\b(?!\s*=(?!=))", body_code) is not None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("block", help="line range of the IIFE, e.g. 6834-7760")
    ap.add_argument("name", help="module name, e.g. SeasonPass")
    ap.add_argument("--publish", default="",
                    help="comma-separated MainUI locals to expose on hudRefs first")
    ap.add_argument("--what", default="", help="one line for the module header")
    ap.add_argument("--dry", action="store_true", help="report and write nothing")
    args = ap.parse_args()

    start, end = (int(x) for x in args.block.split("-"))
    dest = DESTDIR / (args.name + ".lua")
    if dest.exists() and not args.dry:
        sys.exit("%s already exists -- refusing to overwrite" % dest.name)

    lines = io.open(MAIN, encoding="utf-8", newline="").read().split("\n")
    assert lines[start - 1] in (";(function()", "(function()"), repr(lines[start - 1])
    assert lines[end - 1] == "end)()", repr(lines[end - 1])

    body = lines[start:end - 1]
    code = "\n".join(l.split("--")[0] for l in body)

    names = top_level(lines)
    inner = set()
    for l in body:
        for m in re.finditer(r"\blocal\s+(?:function\s+)?([A-Za-z_][\w,\s]*?)\s*(?:=|\()", l):
            for n in m.group(1).split(","):
                inner.add(n.strip())

    kit_used = [k for k in KIT if k not in inner and reads(code, k)]
    want = {n for n, _ in PREAMBLE if n and n not in inner and reads(code, n)}
    if kit_used:
        want.add("__KIT__")
    for n in list(want):
        want.update(IMPLIES.get(n, []))

    deps = sorted(n for n in names
                  if n not in inner and n not in SELF_SERVED and n != "hudRefs"
                  and reads(code, n))

    # `currentData` is never a dependency -- it is rebound on every DataUpdate, so it is read
    # through the getter or not at all.
    if "currentData" in deps:
        deps.remove("currentData")
    published = [p for p in args.publish.split(",") if p]

    # Which deps are already on hudRefs above this block? Anything else must be published.
    have = {m.group(1) for i, l in enumerate(lines) if i < start
            for m in [re.match(r"^hudRefs\.([A-Za-z_]\w*)\s*=", l)] if m}
    missing = [d for d in deps if d not in have and d not in published]

    print("%s  %d lines  ->  Modules/HUD/%s.lua" % (args.block, end - start + 1, args.name))
    print("  preamble : %s" % ", ".join(sorted(want)) or "(none)")
    print("  kit      : %s" % (", ".join(kit_used) or "(none)"))
    print("  hud      : %s" % (", ".join(deps) or "(nothing)"))
    if "currentData" in code:
        print("  note     : reads currentData -> rewritten to hud.getData()")
    if missing:
        print("  MISSING  : %s   (pass --publish %s)" % (", ".join(missing), ",".join(missing)))
        if not args.dry:
            sys.exit(1)
    if args.dry:
        return 0

    # ---- publish what the block needs, one line under each name's own definition ----
    for p in sorted(published, key=lambda n: -names[n][1]):
        if p not in names:
            sys.exit("cannot publish %s -- not a top-level name in MainUI" % p)
        lines.insert(names[p][1], "hudRefs.%s = %s" % (p, p))
        if names[p][1] < start:
            start, end = start + 1, end + 1
        body = lines[start:end - 1]

    # ---- the module ----
    head = ["-- %s -- %s" % (args.name, args.what or "extracted from MainUI, unchanged."),
            "--",
            "-- MOVED OUT OF `MainUI` (18.9), byte for byte. It was already a closed",
            "-- `;(function() ... end)()` block -- the shape this file's 200-register ceiling forces",
            "-- every panel into -- so the extraction is a change of wrapper, not of code. See",
            "-- `docs/SPLIT.md` for the `hud` contract and `docs/CODEMAP.md` for where the rest went.",
            ""]
    for n, line in PREAMBLE:
        if n == "" :
            if head[-1] != "":
                head.append("")
        elif n in want:
            head.append(line)
    while head and head[-1] == "":
        head.pop()
    head.append("")
    if kit_used:
        for i in range(0, len(kit_used), 4):
            chunk = kit_used[i:i + 4]
            head.append("local %s = %s" % (", ".join(chunk),
                                           ", ".join("UIKit." + c for c in chunk)))
        head.append("")
    head.append("return function(hud)")
    for i in range(0, len(deps), 3):
        chunk = deps[i:i + 3]
        head.append("\tlocal %s = %s" % (", ".join(chunk),
                                         ", ".join("hud." + c for c in chunk)))
    if deps:
        head.append("")

    out = []
    for l in body:
        # `hudRefs` IS `hud` inside a module -- the same table, reached by its parameter name
        l = re.sub(r"\bhudRefs\b", "hud", l)
        l = re.sub(r"\bcurrentData\b", "hud.getData()", l)
        out.append(l)

    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text("\n".join(head + out) + "\nend\n", encoding="utf-8", newline="")

    # ---- the call site ----
    call = [
        "-- MOVED OUT (18.9) to `ReplicatedStorage.Modules.HUD.%s` -- %d lines, unchanged."
        % (args.name, end - start + 1),
        'require(RS.Modules:WaitForChild("HUD"):WaitForChild("%s"))(hudRefs)' % args.name,
    ]
    lines[start - 1:end] = call
    MAIN.write_text("\n".join(lines), encoding="utf-8", newline="")
    print("  written. MainUI now %d lines" % len(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
