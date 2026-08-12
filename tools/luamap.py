"""Structural map of a Lua file: what is in it, where, and how big.

Written for the Evolution Lab problem: `ZoneBuilder.lua` is 560 KB (~147k tokens) and
`MainUI.client.lua` is 379 KB (~100k), so reading either one whole costs most of a
context window for the sake of one function. This prints a table of contents instead --
a few kilobytes -- so a reader can jump straight to `Read(file, offset=N, limit=M)`.

It is deliberately dumb: it tracks nesting depth by counting block openers and `end`s
outside strings and comments, and reports every construct that starts at depth 0. That
is enough to find a function in a file nothing else can open, and it does not pretend to
be a parser.

    python tools/luamap.py src/ServerScriptService/ZoneBuilder.lua
    python tools/luamap.py --top 30 --by-size <file>
    python tools/luamap.py --grep decoration <file>
"""

import argparse
import io
import re
import sys

# ===== COUNTING BLOCKS IS THE WHOLE TRICK, AND THE OBVIOUS WAY IS WRONG =====
#
# The first version counted `function|if|for|while|do` as openers against `end`. That
# double-counts every loop: `for _, v in ipairs(t) do` opens on BOTH `for` and `do` and is
# closed by ONE `end`, so depth never returns to zero and the map reported a single
# 8,737-line "function" covering 99% of ZoneBuilder.
#
# So `for` and `while` are NOT openers -- their `do` is. The only complication is that a
# loop header may wrap, putting `do` on a later line, which is why `pending_do` exists: a
# `for`/`while` seen without its `do` claims the next one, so a bare `do ... end` block on
# the following line cannot be miscounted as the loop's.
KW_FUNCTION = re.compile(r"\bfunction\b")
KW_IF = re.compile(r"\bif\b")
KW_DO = re.compile(r"\bdo\b")
KW_FORWHILE = re.compile(r"\b(for|while)\b")
KW_REPEAT = re.compile(r"\brepeat\b")
KW_END = re.compile(r"\bend\b")
KW_UNTIL = re.compile(r"\buntil\b")

NAMED = [
    ("function", re.compile(r"^\s*(?:local\s+)?function\s+([\w.:\[\]\"']+)")),
    ("local-fn", re.compile(r"^\s*local\s+([\w]+)\s*=\s*function")),
    ("table", re.compile(r"^\s*(?:local\s+)?([\w.]+)\s*=\s*\{\s*$")),
    ("local", re.compile(r"^\s*local\s+([\w]+)\s*=")),
    ("assign", re.compile(r"^\s*([\w][\w.]*)\s*=")),
]


def strip_code(line):
    """Remove string literals and comments so the block counters do not see keywords in them."""
    out = []
    i, n = 0, len(line)
    quote = None
    while i < n:
        c = line[i]
        if quote:
            if c == "\\":
                i += 2
                continue
            if c == quote:
                quote = None
            i += 1
            continue
        if c in "\"'":
            quote = c
            i += 1
            continue
        if line.startswith("--", i):
            break
        out.append(c)
        i += 1
    return "".join(out)


def classify(line):
    for kind, rx in NAMED:
        m = rx.match(line)
        if m:
            return kind, m.group(1)
    return None, None


def build_map(path):
    raw = io.open(path, encoding="utf-8", newline="").read()
    lines = raw.split("\n")
    # byte offset of each line start, so a section's real weight can be reported
    offsets, acc = [], 0
    for ln in lines:
        offsets.append(acc)
        acc += len(ln.encode("utf-8")) + 1
    total_bytes = acc

    depth = 0
    long_block = 0          # inside a --[[ ]] comment or a [[ ]] long string
    pending_do = 0          # `for`/`while` headers still waiting for their `do`
    entries = []
    open_entry = None

    for idx, raw_line in enumerate(lines):
        line = raw_line
        if long_block:
            if "]]" in line:
                long_block = 0
                line = line.split("]]", 1)[1]
            else:
                continue
        # both `--[[ ... ]]` and a bare `[[ ... ]]` long string swallow keywords, and both
        # end the same way; treating them identically is enough for a table of contents
        if re.search(r"(--)?\[\[", line) and "]]" not in line:
            long_block = 1
            line = re.split(r"(?:--)?\[\[", line, maxsplit=1)[0]

        code = strip_code(line)

        if depth == 0 and open_entry is None:
            kind, name = classify(line)
            if kind:
                open_entry = {"kind": kind, "name": name, "start": idx}

        forwhile = len(KW_FORWHILE.findall(code))
        dos = len(KW_DO.findall(code))
        # each `for`/`while` consumes one `do`, this line's or a later one's
        pending_do += forwhile
        consumed = min(pending_do, dos)
        pending_do -= consumed

        opens = len(KW_FUNCTION.findall(code)) + len(KW_IF.findall(code)) \
            + len(KW_REPEAT.findall(code)) + dos
        closes = len(KW_END.findall(code)) + len(KW_UNTIL.findall(code))
        # `for`/`while` opened a block too -- via the `do` already counted above -- so the
        # loop's own keyword must NOT add a second one. A one-line `function() ... end` or
        # `if x then y end` nets to zero and is fine.
        depth += opens - closes
        if depth < 0:
            depth = 0

        if open_entry is not None and depth == 0:
            # closed on this line -- also covers single-line entries and bare locals
            open_entry["end"] = idx
            entries.append(open_entry)
            open_entry = None

    if open_entry is not None:
        open_entry["end"] = len(lines) - 1
        entries.append(open_entry)

    for e in entries:
        e["lines"] = e["end"] - e["start"] + 1
        s = offsets[e["start"]]
        t = offsets[e["end"]] + len(lines[e["end"]].encode("utf-8")) + 1
        e["bytes"] = t - s

    return entries, len(lines), total_bytes


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("--top", type=int, default=40)
    ap.add_argument("--by-size", action="store_true", help="heaviest first instead of in file order")
    ap.add_argument("--grep", default=None, help="only entries whose name matches this substring")
    ap.add_argument("--min-lines", type=int, default=1)
    args = ap.parse_args()

    entries, nlines, nbytes = build_map(args.path)
    entries = [e for e in entries if e["lines"] >= args.min_lines]
    if args.grep:
        entries = [e for e in entries if args.grep.lower() in (e["name"] or "").lower()]

    shown = sorted(entries, key=lambda e: -e["bytes"]) if args.by_size else entries
    shown = shown[: args.top]

    print("%s -- %d lines, %d bytes, ~%dk tokens whole" % (args.path, nlines, nbytes, nbytes / 3800))
    print("%-10s %-42s %7s %7s %9s  %s" % ("kind", "name", "start", "lines", "bytes", "Read(offset,limit)"))
    for e in shown:
        print("%-10s %-42s %7d %7d %9d  offset=%d limit=%d" % (
            e["kind"], (e["name"] or "")[:42], e["start"] + 1, e["lines"], e["bytes"],
            e["start"] + 1, e["lines"]))

    covered = sum(e["bytes"] for e in entries)
    print("\n%d top-level entries, %d bytes accounted for (%.0f%% of the file)"
          % (len(entries), covered, 100.0 * covered / max(nbytes, 1)))


if __name__ == "__main__":
    main()
