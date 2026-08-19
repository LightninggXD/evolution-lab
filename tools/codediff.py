"""Diff two Lua revisions on EXECUTABLE CODE ALONE, with comments and blank lines stripped out.

WHY THIS EXISTS (19.6, 2026-08-20). A "compaction" pass over `FirstJoin.client.lua` cut it from
915 lines to 674 and was filed as documentation debt -- "almost all of them the design comments this
project keeps on purpose". It was not only that. It had also deleted two guards from
`runClimbBeat`, one of which is a live defect: without `if not ramp then return end` the fourth
tutorial beat shows "Climb to the next terrace" for seven seconds wherever the player is standing,
with no marker and no trail, because there is no terrace within range of the arena.

Four hundred changed lines is far too many to eyeball, and that is exactly the cover a deleted line
of code hides under. Stripped of comments the same diff was FIVE lines and the guards were obvious.

    python tools/codediff.py OLD.lua NEW.lua        compare two files
    python tools/codediff.py --quarantine           sweep tools/_studio_pull/ against src/

Use it on any revision pair where the summary is "mostly comments" -- that claim is the thing this
tool is for checking. It is not a linter: it makes no judgement, it only removes the noise that
makes a real change invisible. Note that a rename or a reflow still shows up here, so a non-empty
result is a prompt to read, not a verdict.
"""

import difflib
import os
import re
import sys

SRC_GUESS = [
    "src/StarterPlayer/StarterPlayerScripts/{stem}.client.lua",
    "src/StarterPlayer/StarterPlayerScripts/{stem}.lua",
    "src/StarterPlayer/StarterPlayerScripts/UIComponents/{stem}.lua",
    "src/ServerScriptService/{stem}.lua",
    "src/ServerScriptService/Systems/{stem}.lua",
    "src/ReplicatedStorage/Modules/{stem}.lua",
    "src/ReplicatedStorage/Modules/HUD/{stem}.lua",
    "src/ReplicatedStorage/Modules/GameConfig/{stem}.lua",
    "src/ReplicatedFirst/{stem}.client.lua",
]


def strip(path):
    """Every line that carries executable code, with trailing comments removed."""
    s = open(path, encoding="utf-8", errors="replace").read()
    # block comments first, so a `--[[ ... ]]` spanning code-looking lines cannot survive
    s = re.sub(r"--\[\[.*?\]\](--)?", "", s, flags=re.S)
    out = []
    for ln in s.split("\n"):
        # a trailing `-- note`, but never `--[` which would be the block form handled above
        ln = re.sub(r"\s+--(?!\[).*$", "", ln)
        if re.match(r"^\s*--", ln):
            continue
        if not ln.strip():
            continue
        out.append(ln.rstrip())
    return out


def compare(old, new, label=None, verbose=True):
    a, b = strip(old), strip(new)
    d = [
        l for l in difflib.unified_diff(a, b, lineterm="", n=0)
        if l[:1] in "+-" and l[:3] not in ("---", "+++")
    ]
    removed = sum(1 for l in d if l.startswith("-"))
    added = sum(1 for l in d if l.startswith("+"))
    print(f"{label or old} -> {new}")
    print(f"    code lines {len(a)} -> {len(b)}   removed {removed}  added {added}")
    if verbose and d:
        if len(d) <= 60:
            for l in d:
                print("      " + l)
        else:
            print(f"      ({len(d)} changed code lines -- rerun on this pair alone to see them)")
    return len(d)


def quarantine():
    """Sweep the 19.0 rescue folder against what src/ holds now.

    Measured 2026-08-20: eleven of the twelve are code-identical and only `FirstJoin` diverges,
    which is what makes the guard loss an isolated incident rather than a systemic one.
    """
    q = "tools/_studio_pull"
    total = 0
    for f in sorted(os.listdir(q)):
        if not f.endswith(".lua"):
            continue
        stem = f.replace(".client.lua", "").replace(".lua", "")
        target = next((p.format(stem=stem) for p in SRC_GUESS if os.path.exists(p.format(stem=stem))), None)
        if not target:
            print(f"{f:<32} no counterpart in src/  (skipped)")
            continue
        total += compare(os.path.join(q, f), target, label=f)
    return total


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--quarantine":
        sys.exit(0 if quarantine() == 0 else 0)  # never fails the shell; it reports
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    compare(sys.argv[1], sys.argv[2])
