#!/usr/bin/env python3
"""Structural checker for the Lua sources in src/.

Not a parser and not a substitute for running the code -- it only answers the one question
that has actually bitten this project: after a large hand-edit, do the blocks and brackets
still balance? It is comment- and string-aware, so `--[[ ... ]]`, `[==[ ... ]==]`, quoted
strings and `-- end` in a comment cannot fool it.

    python tools/luastruct.py            # check every .lua under src/
    python tools/luastruct.py FILE ...   # check specific files

Exit code 0 when everything balances, 1 otherwise.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# `for`/`while` own the `do` that follows them, so that `do` must not count as its own block.
OPENERS = {"function", "if", "do", "repeat"}
LOOPS = {"for", "while"}
NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")

BRACKET_PAIRS = {")": "(", "]": "[", "}": "{"}


class Problem(Exception):
    pass


def strip_long_bracket(src, i, line):
    """If src[i:] opens a long bracket ([[ or [==[), return (end_index, new_line). Else None."""
    if src[i] != "[":
        return None
    j = i + 1
    while j < len(src) and src[j] == "=":
        j += 1
    if j >= len(src) or src[j] != "[":
        return None
    level = j - i - 1
    close = "]" + "=" * level + "]"
    end = src.find(close, j + 1)
    if end == -1:
        raise Problem(f"line {line}: unterminated long bracket")
    return end + len(close), line + src.count("\n", i, end)


def tokens(src):
    """Yield (kind, text, line) for kind in {'name', 'punct'}, skipping comments and strings."""
    i, line, n = 0, 1, len(src)
    while i < n:
        c = src[i]

        if c == "\n":
            line += 1
            i += 1
            continue

        if c.isspace():
            i += 1
            continue

        # comments -- long form first, so `--[[` is not read as a line comment
        if src.startswith("--", i):
            lb = strip_long_bracket(src, i + 2, line)
            if lb:
                i, line = lb
                continue
            nl = src.find("\n", i)
            i = n if nl == -1 else nl
            continue

        # long strings
        lb = strip_long_bracket(src, i, line)
        if lb:
            i, line = lb
            continue

        # quoted strings
        if c in "\"'":
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == "\n":
                    raise Problem(f"line {line}: unterminated string")
                if src[j] == c:
                    break
                j += 1
            else:
                raise Problem(f"line {line}: unterminated string")
            i = j + 1
            continue

        m = NAME.match(src, i)
        if m:
            yield "name", m.group(0), line
            i = m.end()
            continue

        if c.isdigit():
            j = i
            while j < n and (src[j].isalnum() or src[j] in "._"):
                j += 1
            i = j
            continue

        yield "punct", c, line
        i += 1


def check(path):
    src = path.read_text(encoding="utf-8")
    blocks = []      # (keyword, line)
    brackets = []    # (char, line)
    pending_do = 0

    for kind, text, line in tokens(src):
        if kind == "name":
            if text in LOOPS:
                # the loop is its own block (closed by `end`) *and* it owns the `do` that
                # follows its header, which must therefore not open a second block
                blocks.append((text, line))
                pending_do += 1
            elif text == "do":
                if pending_do:
                    pending_do -= 1   # belongs to the for/while already on the stack
                else:
                    blocks.append(("do", line))
            elif text in OPENERS:
                blocks.append((text, line))
            elif text == "end":
                if not blocks:
                    raise Problem(f"line {line}: `end` with no open block")
                kw, opened = blocks.pop()
                if kw == "repeat":
                    raise Problem(f"line {line}: `end` closes `repeat` from line {opened} (wants `until`)")
            elif text == "until":
                if not blocks or blocks[-1][0] != "repeat":
                    raise Problem(f"line {line}: `until` with no matching `repeat`")
                blocks.pop()
        else:
            if text in "([{":
                brackets.append((text, line))
            elif text in BRACKET_PAIRS:
                if not brackets:
                    raise Problem(f"line {line}: `{text}` with no opener")
                ch, opened = brackets.pop()
                if ch != BRACKET_PAIRS[text]:
                    raise Problem(f"line {line}: `{text}` closes `{ch}` opened on line {opened}")

    # `for`/`while` on the stack are pushed as themselves, so an unconsumed pending_do means a
    # loop header never reached its `do`
    if pending_do:
        raise Problem(f"{pending_do} `for`/`while` header(s) never reached a `do`")
    if brackets:
        ch, opened = brackets[-1]
        raise Problem(f"unclosed `{ch}` opened on line {opened}")
    if blocks:
        kw, opened = blocks[-1]
        raise Problem(f"unclosed `{kw}` opened on line {opened}")

    return len(src.splitlines())


def main(argv):
    if argv:
        files = [Path(a) for a in argv]
    else:
        files = sorted((ROOT / "src").rglob("*.lua"))
    if not files:
        print("no .lua files found")
        return 1

    failed = 0
    width = max(len(f.name) for f in files)
    for f in files:
        try:
            lines = check(f)
            print(f"OK  {f.name:<{width}}  {lines:>5}")
        except Problem as e:
            failed += 1
            print(f"BAD {f.name:<{width}}  {e}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
