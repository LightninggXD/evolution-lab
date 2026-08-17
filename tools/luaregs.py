"""Count a file's TOP-LEVEL LOCAL REGISTERS -- the number Luau's 200 limit is actually against.

WHY THIS EXISTS. Every scan in this repo before 2026-08-17 counted `local` *lines*, and quoted 190
for `ZoneBuilder`. Luau counts *names*: `local addKnob, addScallops, addBunting, addPlanter, candy`
is one line and five registers. The real figure was **198 of 200**, i.e. the world builder was two
declarations from not compiling -- and here crossing the cap does not break a panel the way it does
in `MainUI`, it stops the entire world from being built.

THE COMPILER IS STILL THE AUTHORITY, and asking it is three lines in a Studio console:

    loadstring(string.rep("local __z = 1\\n", N) .. src)
    -- raise N until: "Out of local registers when trying to allocate `x`: exceeded limit 200"

This tool is the version you can run without Studio open. It agrees with that measurement on every
file it has been checked against, but it is a text scan: if the two ever disagree, the compiler is
right and this is the thing to fix.

WHAT COUNTS AS TOP LEVEL: a `local` or `local function` at column 0 -- not indented, not inside a
`do ... end`, not inside any function body. A chunk is itself a function, so its locals are the
ones competing for the 200. Re-declaring a name costs another register; Luau does not reuse the
slot, and this counts declarations rather than distinct names for that reason.

    python tools/luaregs.py src/ServerScriptService/ZoneBuilder.lua [more.lua ...]
"""
import re
import sys
from pathlib import Path

DECL = re.compile(r"^local\s+(?:function\s+)?([A-Za-z_][\w]*(?:\s*,\s*[A-Za-z_][\w]*)*)")
LIMIT = 200


def strip_block_comments(text):
    # long comments only; a `--` line comment cannot start a declaration and is skipped below
    return re.sub(r"--\[(=*)\[.*?\]\1\]", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)


def count(path):
    text = strip_block_comments(Path(path).read_text(encoding="utf-8"))
    names, dupes = [], {}
    for line in text.split("\n"):
        m = DECL.match(line)
        if not m:
            continue
        for n in m.group(1).split(","):
            n = n.strip()
            names.append(n)
            dupes[n] = dupes.get(n, 0) + 1
    return names, {n: c for n, c in dupes.items() if c > 1}


def main(argv):
    if not argv:
        sys.exit(__doc__)
    worst = 0
    for path in argv:
        names, dupes = count(path)
        worst = max(worst, len(names))
        head = len(names) >= LIMIT and "OVER" or (len(names) >= LIMIT - 15 and "TIGHT" or "ok")
        print("%-5s %-34s %3d registers, %3d of headroom" % (
            head, Path(path).name, len(names), LIMIT - len(names)))
        if dupes:
            print("        re-declared (each costs another register): %s" % ", ".join(
                "%s x%d" % (n, c) for n, c in sorted(dupes.items())))
    return 1 if worst >= LIMIT else 0


sys.exit(main(sys.argv[1:]))
