#!/usr/bin/env python3
"""Undefined-global lint for the Lua sources in src/.

`luastruct.py` proves the blocks balance; this proves the names resolve. It is the check that
catches the class of typo a bracket counter cannot see -- `lighen(c, 0.2)` instead of
`lighten`, a helper called above its `local function`, a colour local renamed in one place.

Deliberately NOT scope-aware: it collects every name bound anywhere in the file (locals,
function parameters, loop variables, `Name = ` table fields are ignored) and flags any bare
identifier that is neither bound nor a known Roblox/Lua global. That over-approximates
bindings, so it can miss a use-before-declaration -- it will never invent a false alarm for a
name that genuinely exists somewhere. Use it as a typo net, not as a compiler.

    python tools/luanames.py            # check every .lua under src/
    python tools/luanames.py FILE ...

Exit code 0 when nothing unknown is referenced, 1 otherwise.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from luastruct import tokens, Problem  # noqa: E402  (shared comment/string-aware tokenizer)

ROOT = Path(__file__).resolve().parent.parent

KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in",
    "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while",
    "continue", "export", "type",
}

# Lua standard library + the Roblox datamodel globals and constructors this project uses.
GLOBALS = {
    # lua
    "assert", "error", "getmetatable", "ipairs", "next", "pairs", "pcall", "print", "rawequal",
    "rawget", "rawlen", "rawset", "require", "select", "setmetatable", "tonumber", "tostring",
    "type", "unpack", "xpcall", "math", "os", "string", "table", "coroutine", "utf8", "debug",
    "bit32", "_G", "self",
    # roblox
    "game", "workspace", "script", "shared", "plugin", "Instance", "Enum", "task", "typeof",
    "warn", "spawn", "delay", "wait", "tick", "time", "elapsedTime", "settings", "DebuggerManager",
    "UserSettings", "version", "PluginManager", "gcinfo", "newproxy",
    # roblox datatypes
    "Axes", "BrickColor", "CFrame", "CatalogSearchParams", "Color3", "ColorSequence",
    "ColorSequenceKeypoint", "DateTime", "DockWidgetPluginGuiInfo", "Faces", "FloatCurveKey",
    "Font", "NumberRange", "NumberSequence", "NumberSequenceKeypoint", "OverlapParams",
    "PathWaypoint", "PhysicalProperties", "RaycastParams", "Random", "Ray", "Rect", "Region3",
    "Region3int16", "RotationCurveKey", "TweenInfo", "UDim", "UDim2", "Vector2", "Vector2int16",
    "Vector3", "Vector3int16",
}

NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def bound_names(src):
    """Every identifier bound anywhere in the file: locals, params, loop vars, globals assigned."""
    bound = set()

    # local a, b, c   /   local function f
    for m in re.finditer(r"\blocal\s+(function\s+)?([A-Za-z_][A-Za-z0-9_,\s]*)", src):
        for part in m.group(2).split(","):
            part = part.strip()
            if NAME.match(part) and part not in KEYWORDS:
                bound.add(part)

    # function f(a, b)  /  function M.f(a, b)  /  f = function(a, b)
    for m in re.finditer(r"\bfunction\s*[A-Za-z0-9_.:]*\s*\(([^)]*)\)", src):
        for part in m.group(1).split(","):
            part = part.strip().lstrip(".")
            if NAME.match(part):
                bound.add(part)

    # for i = 1, n   /  for k, v in pairs(t)
    for m in re.finditer(r"\bfor\s+([A-Za-z_][A-Za-z0-9_,\s]*?)\s*(?:=|\bin\b)", src):
        for part in m.group(1).split(","):
            part = part.strip()
            if NAME.match(part) and part not in KEYWORDS:
                bound.add(part)

    # bare global assignment:  Foo = ...  (not Foo.bar = ..., not == )
    for m in re.finditer(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=[^=]", src, re.M):
        bound.add(m.group(1))

    return bound


def check(path):
    src = path.read_text(encoding="utf-8")
    bound = bound_names(src) | GLOBALS | KEYWORDS

    toks = list(tokens(src))
    unknown = {}
    for i, (kind, text, line) in enumerate(toks):
        if kind != "name":
            continue
        prev = toks[i - 1] if i else None
        # field access: a.b / a:b -- `b` is a member, not a global
        if prev and prev[0] == "punct" and prev[1] in ".:":
            continue
        # `name =` is either an assignment target or a table-constructor key (`{ minSize = 3 }`),
        # never a read. `==` is a comparison, so only a single `=` counts.
        nxt = toks[i + 1] if i + 1 < len(toks) else None
        nxt2 = toks[i + 2] if i + 2 < len(toks) else None
        if nxt and nxt[0] == "punct" and nxt[1] == "=" and not (nxt2 and nxt2[0] == "punct" and nxt2[1] == "="):
            continue
        if text not in bound and text not in unknown:
            unknown[text] = line

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
            print(f"BAD {f.name:<{width}}  {len(unknown)} unknown name(s):")
            for name, line in sorted(unknown.items(), key=lambda kv: kv[1]):
                print(f"      line {line}: {name}")
        else:
            print(f"OK  {f.name:<{width}}  {lines:>5}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
