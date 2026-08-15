#!/usr/bin/env python3
"""Scope-aware undefined-global lint for the Lua sources in src/.

`luastruct.py` proves the blocks balance and `luanames.py` proves the names exist SOMEWHERE in
the file. This one proves a name is visible AT THE POINT IT IS USED, which is the hole the other
two share and cannot close:

    local sub = Instance.new("TextLabel")   -- deleted in a redesign
    ...
    sub.Text = "Two things are waiting"     -- 200 lines down, left standing

`luanames.py` calls that clean, because two other functions in the same file happen to declare a
local called `sub` and it is deliberately not scope-aware. Luau compiles it (a read of an
undeclared name is a global read), so a compile check passes too. It fails at RUNTIME, once, in
the one handler that opens the card -- which is how it shipped.

    python tools/luascope.py            # check every .lua under src/
    python tools/luascope.py FILE ...

Exit code 0 when every name resolves, 1 otherwise.

HOW IT SCOPES. A stack of scopes, pushed by the tokens that open a Lua block (`function`, `do`,
`then`, `else`, `repeat`) and popped by the ones that close it (`end`, `elseif`, `else`, `until`).
`local x` binds into the current scope; function parameters and `for` loop variables bind into the
scope the body opens. That is the whole model -- it is not a parser, and it does not need to be:
every construct it does not understand can only make a scope LARGER than it really is, which loses
findings rather than inventing them.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from luastruct import tokens, Problem  # noqa: E402  (shared comment/string-aware tokenizer)
from luanames import GLOBALS, KEYWORDS, NAME  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent

OPEN = {"function", "do", "then", "else", "repeat"}
CLOSE = {"end", "until"}

# `Game` is Roblox's deprecated alias for `game`; two vendored files in ServerStorage still use it.
EXTRA_GLOBALS = {"Game", "_"}

# THE BASELINE, so a run can be read at a glance (2026-08-15). Two findings are known and left:
#   ZoneBuilder.lua:1622  VILLAGE_CREAM   -- real: three props read it 169 lines above its `local`,
#                                            so they are painted nil (default grey). Fixing it means
#                                            moving BUILD_VERSION, which regenerates all 21 zones.
#   Type.lua:183          value           -- real, and not ours: a vendored free-asset library whose
#                                            `isPositiveInt` tests an argument it never took.
# Anything else this prints is new.


def check(path):
    src = path.read_text(encoding="utf-8")
    toks = [t for t in tokens(src) if t[0] != "comment"]

    scopes = [set()]          # [0] is the file's own chunk
    pending = []              # names to bind into the NEXT scope opened (params, loop vars)
    unknown = {}
    i = 0
    n = len(toks)

    def bind(name):
        if NAME.match(name) and name not in KEYWORDS:
            scopes[-1].add(name)

    def visible(name):
        for s in reversed(scopes):
            if name in s:
                return True
        return False

    while i < n:
        kind, text, line = toks[i]

        if kind == "name" and text == "local":
            # local function f  -- f is visible inside its own body (recursion), so bind it here
            j = i + 1
            if j < n and toks[j][1] == "function":
                if j + 1 < n and toks[j + 1][0] == "name":
                    bind(toks[j + 1][1])
                i += 1
                continue
            # local a, b, c = ...
            while j < n and toks[j][0] == "name":
                bind(toks[j][1])
                j += 1
                if j < n and toks[j][1] == ",":
                    j += 1
                    continue
                break
            i = j
            continue

        if kind == "name" and text == "for":
            # the control variables belong to the body, which opens at the `do`
            j = i + 1
            while j < n and (toks[j][0] == "name" or toks[j][1] == ","):
                if toks[j][0] == "name":
                    if toks[j][1] in ("in",):
                        break
                    pending.append(toks[j][1])
                j += 1
            i = j          # past the control variables, not just past `for`
            continue

        if kind == "name" and text == "function":
            # parameters belong to the body; the name being defined is a read of its host
            # (`function M.f()` reads M) or a global definition (`function f()`)
            j = i + 1
            if j < n and toks[j][0] == "name":
                host = toks[j][1]
                k = j + 1
                if k < n and toks[k][1] in ".:":
                    if not visible(host) and host not in GLOBALS and host not in EXTRA_GLOBALS and host not in unknown:
                        unknown[host] = toks[j][2]
                else:
                    bind(host)          # `function f()` at any depth defines f
                j = k
                while j < n and toks[j][1] in ".:":
                    j += 2
            if j < n and toks[j][1] == "(":
                j += 1
                while j < n and toks[j][1] != ")":
                    if toks[j][0] == "name":
                        pending.append(toks[j][1])
                    j += 1
            scopes.append(set())
            for p in pending:
                bind(p)
            pending = []
            i = j + 1
            continue

        if kind == "name" and text in OPEN:
            if text == "else":
                if len(scopes) > 1:
                    scopes.pop()
            scopes.append(set())
            for p in pending:
                bind(p)
            pending = []
            i += 1
            continue

        if kind == "name" and (text in CLOSE or text == "elseif"):
            if len(scopes) > 1:
                scopes.pop()
            i += 1
            continue

        if kind == "name" and text not in KEYWORDS:
            prev = toks[i - 1] if i else None
            nxt = toks[i + 1] if i + 1 < n else None
            nxt2 = toks[i + 2] if i + 2 < n else None
            field = prev and prev[0] == "punct" and prev[1] in ".:"
            # `name =` is an assignment target or a table key, never a read -- but a bare
            # `name = ...` at statement level DEFINES a global, so bind it and move on
            assign = (nxt and nxt[0] == "punct" and nxt[1] == "="
                      and not (nxt2 and nxt2[0] == "punct" and nxt2[1] == "="))
            if field:
                pass
            elif assign:
                if not (prev and prev[0] == "punct" and prev[1] in ",{("):
                    bind(text)          # over-approximates table keys; loses findings, never invents
            elif not visible(text) and text not in GLOBALS and text not in EXTRA_GLOBALS and text not in unknown:
                unknown[text] = line
        i += 1

    return len(src.splitlines()), unknown


def main(argv):
    files = [Path(a) for a in argv] if argv else sorted((ROOT / "src").rglob("*.lua"))
    if not files:
        print("no .lua files found")
        return 1

    failed = 0
    width = max(len(f.name) for f in files)
    for f in files:
        try:
            lines, unknown = check(f)
        except Problem as e:
            failed += 1
            print(f"BAD {f.name:<{width}}  tokenizer: {e}")
            continue
        if unknown:
            failed += 1
            print(f"BAD {f.name:<{width}}  {len(unknown)} out-of-scope name(s):")
            for name, line in sorted(unknown.items(), key=lambda kv: kv[1]):
                print(f"      line {line}: {name}")
        else:
            print(f"OK  {f.name:<{width}}  {lines:>5}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
