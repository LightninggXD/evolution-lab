#!/usr/bin/env python3
"""Emit docs/CODEMAP.md and docs/codemap/<Name>.md -- the repo's file register.

WHY THIS EXISTS
---------------
`MainUI.client.lua` is 11,700 lines (~149k tokens) and `ZoneBuilder.lua` is 9,300. Reading
either one whole costs most of a context window for the sake of one function, so every
session that touched them paid the same tax twice: once to find the code, once to re-find
it after a /clear. `tools/luamap.py` already answers "what is in this file and where", but
it has to be RUN, per file, and its output is thrown away at the end of the session.

This writes that answer down. A checked-in map is read once, by any agent, and turns
"grep around until something matches" into a single `Read(file, offset=N, limit=M)`.

It is deliberately a GENERATED file. Nobody hand-maintains it, so it cannot go stale in the
way a hand-written architecture doc does -- re-run it after a structural edit:

    py tools/codemap.py            # rewrite the whole register
    py tools/codemap.py --check    # exit 1 if the register is out of date, touch nothing

WHAT GOES IN A ROW, AND WHY NOT EVERYTHING
------------------------------------------
`luamap` reports every top-level construct, which for MainUI is 529 rows -- most of them
single-line `assign` statements like `topBar.Size = ...`. That is noise: nobody navigates to
a property assignment. So the register keeps only what a reader would actually jump to:

  * every function (`function f`, `local f = function`),
  * every top-level table literal (the config data),
  * multi-line `local` blocks,
  * and -- this is the half luamap cannot see -- every SECTION HEADING comment.

The headings matter more than the functions in a file like MainUI, where 75% of the bytes
are straight-line construction inside `;(function() ... end)()` wrappers that own no name.
`-- ===== Zones panel =====` is the only marker that block has, and it is the marker the
comments in the file are already written against.
"""

import argparse
import io
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from luamap import build_map  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
DOCS = ROOT / "docs"
OUTDIR = DOCS / "codemap"
INDEX = DOCS / "CODEMAP.md"

# A heading is a comment that is mostly rule characters around a name. THREE dialects are in
# this repo and all three have to be matched, because a missed one is a blind span in the
# register -- the banner form below hid a 1,450-line block of MainUI containing the whole
# trading UI until it was added:
#
#   -- ===== Zones panel =====          inline, name between the rules
#   -- ================= helpers ====== inline, ragged rules
#   -- ==========================       banner: a bare rule line,
#   -- TRADING UI & REMOTES (Phase 8.6) the name on its own,
#   -- ==========================       and a closing rule
HEADING = re.compile(r"^--\s*=====+\s*(.*?)\s*=*\s*$")
RULE = re.compile(r"^--\s*=====+\s*$")
BANNER_NAME = re.compile(r"^--\s*(\S.*?)\s*$")

# Rows worth navigating to. `assign` and one-line `local` are dropped -- see the module docstring.
KEEP_KINDS = {"function", "local-fn", "table"}
MIN_LOCAL_LINES = 3

# A file below this many lines needs no per-file page; the index line is the whole story.
PAGE_THRESHOLD = 400


def headings(path):
    """Section-heading comments, as (line_index, text). Long-comment aware."""
    with io.open(path, encoding="utf-8", newline="") as fh:
        lines = [ln.rstrip("\r\n") for ln in fh]

    out = []
    long_block = False
    for idx, line in enumerate(lines):
        if long_block:
            if "]]" in line:
                long_block = False
            continue
        if re.search(r"(--)?\[\[", line) and "]]" not in line:
            long_block = True
            continue

        # Banner form first: a bare rule, a name, a bare rule. Checked before the inline form
        # because a bare rule also matches HEADING -- with an empty name, which is dropped.
        if RULE.match(line) and idx + 2 < len(lines) and RULE.match(lines[idx + 2]):
            m = BANNER_NAME.match(lines[idx + 1])
            if m and not RULE.match(lines[idx + 1]):
                out.append((idx, m.group(1)))
                continue

        m = HEADING.match(line)
        if m and m.group(1):
            out.append((idx, m.group(1)))
    return out


def rows_for(path):
    """Merged, line-ordered navigation rows for one file."""
    entries, nlines, nbytes = build_map(str(path))
    rows = []
    for e in entries:
        if e["kind"] in KEEP_KINDS or (e["kind"] == "local" and e["lines"] >= MIN_LOCAL_LINES):
            rows.append({
                "start": e["start"],
                "lines": e["lines"],
                "kind": e["kind"],
                "name": e["name"] or "",
            })
    for idx, text in headings(path):
        rows.append({"start": idx, "lines": None, "kind": "§", "name": text})
    rows.sort(key=lambda r: (r["start"], 0 if r["kind"] == "§" else 1))

    # A heading's span runs to the next heading -- that is the block a reader wants to Read,
    # and it is the only span available for the unnamed `;(function() ... end)()` chunks.
    heads = [i for i, r in enumerate(rows) if r["kind"] == "§"]
    for pos, i in enumerate(heads):
        nxt = heads[pos + 1] if pos + 1 < len(heads) else None
        end = rows[nxt]["start"] if nxt is not None else nlines
        rows[i]["lines"] = max(1, end - rows[i]["start"])
    return rows, nlines, nbytes


def page_for(rel, path):
    rows, nlines, nbytes = rows_for(path)
    name = Path(rel).name
    out = []
    out.append("# %s" % name)
    out.append("")
    out.append("`%s` — **%d lines, %d KB (~%dk tokens whole)**" % (rel, nlines, nbytes // 1024, nbytes / 3800))
    out.append("")
    out.append("Generated by `tools/codemap.py`. Jump straight to a row — do not read the file whole.")
    out.append("")
    out.append("| line | kind | name | Read |")
    out.append("|-----:|:-----|:-----|:-----|")
    for r in rows:
        kind = r["kind"]
        nm = r["name"].replace("|", "\\|")
        if kind == "§":
            nm = "**%s**" % nm
        out.append("| %d | %s | %s | `offset=%d limit=%d` |"
                   % (r["start"] + 1, kind, nm, r["start"] + 1, r["lines"]))
    out.append("")
    return "\n".join(out), nlines, nbytes, len(rows)


def collect():
    files = []
    for dirpath, _dirs, names in os.walk(SRC):
        for fn in sorted(names):
            if not fn.endswith(".lua"):
                continue
            full = Path(dirpath) / fn
            rel = str(full.relative_to(ROOT)).replace("\\", "/")
            if "_PushBackup" in rel:
                continue
            files.append((rel, full))
    return sorted(files, key=lambda t: t[0])


def build():
    """Return {path: text} of every file the register consists of."""
    written = {}
    index = []
    index.append("# CODEMAP — where every line of this game lives")
    index.append("")
    index.append("Generated by `tools/codemap.py`; re-run it after any structural edit "
                 "(`py tools/codemap.py`, or `--check` to test staleness).")
    index.append("")
    index.append("**Read this before searching for code.** Every file below has a per-file page "
                 "listing its functions and section headings with exact `Read(offset, limit)` "
                 "coordinates. Opening `MainUI.client.lua` whole costs ~149k tokens; its page "
                 "costs about two.")
    index.append("")

    rowsets = []
    for rel, full in collect():
        text, nlines, nbytes, nrows = page_for(rel, full)
        page = None
        if nlines >= PAGE_THRESHOLD:
            page = "codemap/%s.md" % Path(rel).name.replace(".lua", "")
            written[str(OUTDIR / (Path(rel).name.replace(".lua", "") + ".md"))] = text
        rowsets.append((rel, nlines, nbytes, nrows, page))

    for service in ("src/ReplicatedFirst", "src/ReplicatedStorage", "src/ServerScriptService",
                    "src/ServerStorage", "src/StarterPlayer"):
        group = [r for r in rowsets if r[0].startswith(service + "/")]
        if not group:
            continue
        index.append("## %s" % service.split("/", 1)[1])
        index.append("")
        index.append("| file | lines | KB | map |")
        index.append("|:-----|------:|---:|:----|")
        for rel, nlines, nbytes, _nrows, page in sorted(group, key=lambda t: -t[1]):
            short = rel[len(service) + 1:]
            link = "[map](%s)" % page if page else "—"
            index.append("| `%s` | %d | %d | %s |" % (short, nlines, nbytes // 1024, link))
        index.append("")

    total_lines = sum(r[1] for r in rowsets)
    index.append("---")
    index.append("")
    index.append("%d files, %d lines total." % (len(rowsets), total_lines))
    index.append("")
    written[str(INDEX)] = "\n".join(index)
    return written


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="report staleness, write nothing")
    args = ap.parse_args()

    written = build()
    if args.check:
        stale = []
        for path, text in written.items():
            p = Path(path)
            if not p.exists() or p.read_text(encoding="utf-8") != text:
                stale.append(path)
        if stale:
            print("CODEMAP is out of date (%d files):" % len(stale))
            for s in sorted(stale):
                print("   ", os.path.relpath(s, ROOT))
            print("\nrun: py tools/codemap.py")
            return 1
        print("CODEMAP is current (%d pages)." % len(written))
        return 0

    OUTDIR.mkdir(parents=True, exist_ok=True)
    # Pages for files that no longer exist must go, or the register lies by omission-in-reverse.
    keep = {Path(p).name for p in written}
    for old in OUTDIR.glob("*.md"):
        if old.name not in keep:
            old.unlink()
            print("removed stale page", old.name)
    for path, text in written.items():
        Path(path).write_text(text, encoding="utf-8")
    print("wrote %d files -> docs/" % len(written))
    return 0


if __name__ == "__main__":
    sys.exit(main())
