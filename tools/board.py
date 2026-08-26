"""board.py -- the shared Claude/Gemini work board.

Two agents work this repo and they must never edit the same file, so the board is three lanes plus
one generated page:

    agent-board/STEPS.md          Claude writes    the work, one block per step
    agent-board/GEMINI-LOG.md     Gemini writes    append-only claims, with evidence
    agent-board/CLAUDE-REVIEW.md  Claude writes    append-only verdicts and fixes
    agent-board/STATUS.md         NOBODY writes    rendered from the three above

A step's state is decided by comparing the newest claim against the newest review, which is why the
timestamps are mandatory and why both logs are append-only. `PROTOCOL.md` is the contract.

Commands
    check [--as gemini|claude]   what is waiting for that agent right now (default: both)
    render                       rewrite STATUS.md from the lanes
    sync [--auto] [--no-push]    render, GUARD, stage, commit and push -- the "never think about it"
                                 command. `--auto` is hook mode: it refuses a suspiciously large
                                 change set instead of committing it.

WHY `sync` GUARDS INSTEAD OF JUST COMMITTING. It was written the day a bulk rewrite turned 52 files
of the mirror into mojibake -- every section sign grew a stray capital A, and every literal emoji in `GameConfig` became four
bytes of garbage, which matters because the icon layer is keyed BY EMOJI. Nothing in git noticed;
the diff looked like ordinary work. An auto-commit without the guard would have made that damage
permanent and pushed it. So the guard runs first, every time, and a failed guard is a refusal to
commit rather than a warning nobody reads.

Everything here is ASCII on purpose. A print of a non-ASCII glyph dies on a Windows console with a
cp1252 codepage, and this script is run by two agents that both read the console rather than the
file. Writes go through a .tmp + os.replace so a failed encode cannot leave a 0-byte STATUS.md
(python-write-truncates-before-encode).
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOARD = os.path.join(ROOT, "agent-board")
STEPS_MD = os.path.join(BOARD, "STEPS.md")
GEMINI_MD = os.path.join(BOARD, "GEMINI-LOG.md")
REVIEW_MD = os.path.join(BOARD, "CLAUDE-REVIEW.md")
STATUS_MD = os.path.join(BOARD, "STATUS.md")

# `## S3 | Rewrite MapSolids ...` in STEPS.md. The separator is a pipe rather than a dash so a step
# title may contain dashes, which every real title does.
STEP_RE = re.compile(r"^##\s+(S\d+)\s*\|\s*(.+?)\s*$")
FIELD_RE = re.compile(r"^-\s+\*\*(Owner|Depends|Check):\*\*\s*(.*?)\s*$")
# `## S3 | CLAIMED | 2026-08-24T14:20` and the review form with a trailing `| R7`
ENTRY_RE = re.compile(
    r"^##\s+(S\d+)\s*\|\s*([A-Z][A-Z-]*)\s*\|\s*(\d{4}-\d{2}-\d{2}T\d{2}:\d{2})\s*(?:\|\s*(R\d+))?\s*$"
)

CLAIM_WORDS = ("CLAIMED", "BLOCKED", "ACK")
REVIEW_WORDS = ("VERIFIED", "FIX", "NOTE")


def read(path):
    if not os.path.exists(path):
        return ""
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def write(path, text):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    os.replace(tmp, path)


def _outside_fences(text):
    """Yield only the lines that are NOT inside a ``` fence.

    Not defensive tidiness: an evidence block is pasted console output, and both logs carry a
    template written inside a fence. Without this the parser reads those as real entries -- the
    first render of this board did exactly that and reported a step claimed that nobody had touched.
    """
    fenced = False
    for line in text.splitlines():
        if line.lstrip().startswith("```"):
            fenced = not fenced
            continue
        if not fenced:
            yield line


def parse_steps(text):
    """[{id, title, owner, depends[], check, body}] in file order."""
    steps = []
    cur = None
    for line in _outside_fences(text):
        m = STEP_RE.match(line)
        if m:
            cur = {"id": m.group(1), "title": m.group(2), "owner": "", "depends": [],
                   "check": "", "body": []}
            steps.append(cur)
            continue
        if cur is None:
            continue
        f = FIELD_RE.match(line)
        if f:
            key, val = f.group(1).lower(), f.group(2)
            if key == "depends":
                cur["depends"] = [] if val.lower() in ("none", "-", "") else \
                    [p.strip() for p in val.split(",") if p.strip()]
            else:
                cur[key] = val
            continue
        cur["body"].append(line)
    return steps


def parse_entries(text, allowed):
    """Newest entry per step id: {sid: {status, when, rid, body}}. Later lines win."""
    out = {}
    cur = None
    for line in _outside_fences(text):
        m = ENTRY_RE.match(line)
        if m:
            sid, status, when, rid = m.group(1), m.group(2), m.group(3), m.group(4)
            if status not in allowed:
                cur = None
                continue
            cur = {"status": status, "when": when, "rid": rid or "", "body": []}
            prev = out.get(sid)
            # ISO timestamps sort correctly as strings; ties go to the newer line in the file
            if prev is None or when >= prev["when"]:
                out[sid] = cur
            continue
        if cur is not None:
            cur["body"].append(line)
    return out


def resolve(steps, claims, reviews):
    """State per step. A review dated at or after the newest claim decides the step."""
    state = {}
    for st in steps:
        sid = st["id"]
        c = claims.get(sid)
        r = reviews.get(sid)
        if r and r["status"] == "VERIFIED" and (not c or r["when"] >= c["when"]):
            state[sid] = "VERIFIED"
            continue
        if r and r["status"] == "FIX" and (not c or r["when"] >= c["when"]):
            state[sid] = "FIX-PENDING"
            continue
        if c and c["status"] == "BLOCKED":
            state[sid] = "BLOCKED"
            continue
        if c and c["status"] in ("CLAIMED", "ACK"):
            state[sid] = "AWAITING-REVIEW" if c["status"] == "CLAIMED" else "IN-PROGRESS"
            continue
        blocked_by = [d for d in st["depends"] if state.get(d) != "VERIFIED"]
        state[sid] = "WAIT" if blocked_by else "TODO"
    return state


def bar(done, total, width=28):
    if total <= 0:
        return "[" + "-" * width + "] 0%"
    filled = int(round(width * done / float(total)))
    pct = int(round(100.0 * done / total))
    return "[" + "#" * filled + "-" * (width - filled) + "] " + str(pct) + "%"


GLYPH = {
    "VERIFIED": "[x]",
    "AWAITING-REVIEW": "[?]",
    "FIX-PENDING": "[!]",
    "IN-PROGRESS": "[~]",
    "BLOCKED": "[B]",
    "TODO": "[ ]",
    "WAIT": "[.]",
}


def load():
    steps = parse_steps(read(STEPS_MD))
    claims = parse_entries(read(GEMINI_MD), CLAIM_WORDS)
    reviews = parse_entries(read(REVIEW_MD), REVIEW_WORDS)
    return steps, claims, reviews, resolve(steps, claims, reviews)


def cmd_render_quiet():
    """Render without the console output. `check` calls this, so the board it reports on is never the
    stale one somebody forgot to re-render."""
    _render(quiet=True)


def cmd_render():
    _render(quiet=False)


def _render(quiet=False):
    steps, claims, reviews, state = load()
    done = sum(1 for s in steps if state[s["id"]] == "VERIFIED")
    total = len(steps)

    out = []
    out.append("# STATUS -- GENERATED FILE, DO NOT EDIT")
    out.append("")
    out.append("Rendered by `python tools/board.py render` from `STEPS.md`, `GEMINI-LOG.md` and")
    out.append("`CLAUDE-REVIEW.md`. Any hand edit here is overwritten on the next render.")
    out.append("")
    out.append("```")
    out.append(bar(done, total) + "   " + str(done) + " of " + str(total) + " steps verified")
    out.append("```")
    out.append("")
    out.append("| | Step | State | Owner | Last claim | Last review |")
    out.append("|---|---|---|---|---|---|")
    for s in steps:
        sid = s["id"]
        c, r = claims.get(sid), reviews.get(sid)
        out.append("| %s | **%s** %s | `%s` | %s | %s | %s |" % (
            GLYPH[state[sid]], sid, s["title"], state[sid], s["owner"] or "-",
            (c["status"] + " " + c["when"]) if c else "-",
            ((r["rid"] + " " if r["rid"] else "") + r["status"] + " " + r["when"]) if r else "-",
        ))
    out.append("")

    fixes = [s for s in steps if state[s["id"]] == "FIX-PENDING"]
    if fixes:
        out.append("## Waiting on GEMINI -- apply these fixes first")
        out.append("")
        for s in fixes:
            r = reviews[s["id"]]
            out.append("- **%s** %s -- %s %s" % (s["id"], s["title"], r["rid"], r["when"]))
        out.append("")

    todo = [s for s in steps if state[s["id"]] == "TODO"]
    if todo:
        out.append("Next step Gemini may start: **" + todo[0]["id"] + "** " + todo[0]["title"])
        out.append("")

    awaiting = [s for s in steps if state[s["id"]] == "AWAITING-REVIEW"]
    if awaiting:
        out.append("## Waiting on CLAUDE -- claimed, unreviewed")
        out.append("")
        for s in awaiting:
            out.append("- **%s** %s -- claimed %s" % (s["id"], s["title"], claims[s["id"]]["when"]))
        out.append("")

    blocked = [s for s in steps if state[s["id"]] == "BLOCKED"]
    if blocked:
        out.append("## BLOCKED -- Gemini stopped and asked")
        out.append("")
        for s in blocked:
            out.append("- **%s** %s -- %s" % (s["id"], s["title"], claims[s["id"]]["when"]))
        out.append("")

    write(STATUS_MD, "\n".join(out) + "\n")
    if not quiet:
        print("wrote " + os.path.relpath(STATUS_MD, ROOT))
        print(bar(done, total) + "   " + str(done) + " of " + str(total) + " steps verified")


def show(title, rows):
    print("")
    print(title)
    print("-" * len(title))
    if not rows:
        print("  (nothing)")
    for line in rows:
        print("  " + line)


def cmd_check(who):
    cmd_render_quiet()
    steps, claims, reviews, state = load()
    done = sum(1 for s in steps if state[s["id"]] == "VERIFIED")
    print(bar(done, len(steps)) + "   " + str(done) + " of " + str(len(steps)) + " verified")

    # The board is only true if the tree is committed. Printed at the TOP of every check, on both
    # sides, because "I forgot to commit" is how a session's work goes missing and how two agents
    # start disagreeing about what the code says.
    rows = dirty_files()
    if rows:
        print("UNCOMMITTED: " + str(len(rows)) + " file(s) -- run "
              "`C:/Python313/python.exe tools/board.py sync` before you stop.")
        for st, p in rows[:8]:
            print("      " + (st or "??") + "  " + p)
        if len(rows) > 8:
            print("      ... and " + str(len(rows) - 8) + " more")
    else:
        print("working tree clean.")

    if who in ("gemini", "both"):
        rows = []
        for s in steps:
            if state[s["id"]] == "FIX-PENDING":
                r = reviews[s["id"]]
                rows.append("%s %s  (%s %s)" % (s["id"], s["title"], r["rid"], r["when"]))
                for line in r["body"]:
                    if line.strip():
                        rows.append("      " + line.rstrip())
        show("INBOX FOR GEMINI -- fixes to apply before any new work", rows)

        nxt = [s for s in steps if state[s["id"]] == "TODO"]
        show("NEXT STEP GEMINI MAY START", [
            "%s %s\n      check: %s" % (nxt[0]["id"], nxt[0]["title"], nxt[0]["check"])
        ] if nxt else [])

    if who in ("claude", "both"):
        rows = []
        for s in steps:
            if state[s["id"]] in ("AWAITING-REVIEW", "BLOCKED"):
                c = claims[s["id"]]
                rows.append("%s [%s] %s  (claimed %s)" % (s["id"], state[s["id"]], s["title"], c["when"]))
                rows.append("      check: " + s["check"])
        show("INBOX FOR CLAUDE -- claimed or blocked, unreviewed", rows)
    print("")


# ===== THE GUARD, AND WHAT EACH CHECK IS FOR =====
#
# Every one of these exists because the repo has already been damaged that exact way. They are cheap
# -- the whole guard is under a second over 60 files -- and they run before staging, so a failure
# leaves the tree exactly as it was for a human to look at.

# The tells of UTF-8 text that has been read as cp1252/latin-1 and written back as UTF-8. `Â` before
# a section sign, and the `ð`/`â` prefixes every mangled emoji starts with.
def _mojibake_markers():
    """The tells of UTF-8 text read as cp1252/latin-1 and written back as UTF-8 -- DERIVED, never
    typed. A literal mojibake string in this file would itself be mangled by the next tool that gets
    the encoding wrong, and would then match nothing. So the markers are computed from characters
    this repo really uses: a section sign, an em dash, a right quote and an emoji, each put through
    the exact damage. Two bytes is enough to identify each family and short markers cannot
    false-positive on ordinary prose.
    """
    seeds = ("§", "—", "’", "💎")
    out = set()
    for ch in seeds:
        b = ch.encode("utf-8")
        for enc in ("cp1252", "latin-1"):
            try:
                out.add(b[:2].decode(enc))
            except Exception:
                pass
    return tuple(sorted(out))


MOJIBAKE = _mojibake_markers()

# A UTF-8 BOM and a CRLF pair, as numbers. See the block in `guard` for why they are not
# written as escape sequences.
BOM_BYTES = bytes((0xEF, 0xBB, 0xBF))
CRLF_BYTES = bytes((13, 10))
# Nothing outside these roots is auto-committed. `src/` is the mirror and is the point; the board and
# the docs are the paperwork. A .rbxl, a key, or an agent's scratch file is not any agent's to
# commit, and .gitignore already knows which is which.
SYNC_PATHS = ("src", "tools", "docs", "agent-board", "guidelines", "components")
# ...plus everything at the top level that is documentation or repo policy. `.gitignore` already
# drops the agents' scratch (`/task.md`, `/implementation_plan.md`, `/push*`), so whatever .md is
# left at the root is a document somebody wrote to be read -- a review, a handoff, the roadmap.
SYNC_ROOT_FILES = (".gitignore", ".gitattributes", ".mcp.json")
# ...and the project config for the agents themselves. `.claude/settings.local.json` is personal
# and gitignored; `settings.json` carries the Stop hook that runs this very command, so it belongs
# in the repo with everything else it automates.
SYNC_EXACT = (".claude/settings.json",)


def in_sync_paths(p):
    if any(p == root or p.startswith(root + "/") for root in SYNC_PATHS):
        return True
    if "/" not in p and (p.endswith(".md") or p in SYNC_ROOT_FILES):
        return True
    if p in SYNC_EXACT:
        return True
    return False
# In hook mode a change set bigger than this is not work, it is an accident: a bulk rewrite, an
# encoding pass, or a second agent writing while this one commits. 52 files is what the mojibake
# incident looked like in `git status`, and it would have sailed through any size limit above that.
AUTO_MAX_FILES = 30


def git(*a):
    import subprocess
    r = subprocess.run(["git"] + list(a), capture_output=True, text=True, cwd=ROOT)
    return r.returncode, r.stdout.strip(), r.stderr.strip()


def dirty_files():
    """[(status, path)] for everything git would consider a change, ignored files excluded."""
    _, out, _ = git("status", "--porcelain", "--untracked-files=all")
    rows = []
    for line in out.splitlines():
        # `XY PATH`, and the path is taken by splitting rather than by a fixed offset: git trims the
        # leading space of the status pair in some shells, and an off-by-one here silently turns
        # `GEMINI.md` into `EMINI.md` -- a path that then fails to stage with no useful error.
        m = re.match(r"^\s*(\S{1,2})\s+(.+?)\s*$", line)
        if m:
            rows.append((m.group(1), m.group(2).strip('"')))
    return rows


def guard(paths):
    """[] when it is safe to commit, else a list of reasons. Reasons are printed, not raised."""
    import subprocess
    problems = []

    for p in paths:
        full = os.path.join(ROOT, p)
        if not os.path.isfile(full) or os.path.splitext(p)[1] not in (".lua", ".md", ".py", ".json"):
            continue
        with open(full, "rb") as fh:
            raw = fh.read()
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            problems.append(p + ": not valid UTF-8 -- something wrote it with a byte encoding")
            continue
        for m in MOJIBAKE:
            if m in text:
                problems.append(p + ": MOJIBAKE (" + repr(m) + ") -- this file was read as cp1252 "
                                "and written back as UTF-8; restore it with `git checkout -- " + p + "`")
                break

        # ===== THE TWO TELLS THAT ARRIVE BEFORE THE MOJIBAKE DOES =====
        # A BOM and a wholesale CRLF rewrite are the SAME accident as the mojibake above -- a tool
        # that read the file with the Windows ANSI codepage and wrote it back "helpfully" -- but
        # they land on files that had no non-ASCII to mangle, so the marker test above sees nothing
        # and waves them through. Both have already cost this repo real work:
        #
        #   * A BOM makes the file a permanent MISMATCH against Studio, which stores Source as LF
        #     and without one. Roadmap 33.15 is that bug, and 2026-08-26 produced five more.
        #   * A CRLF rewrite buries the real change. On 2026-08-26 four files came back carrying
        #     4,808 CRLF endings and a 4,675-line diff, inside which the actual edit was 47 lines --
        #     in PlayerDataService, BossService and DNAService. Board step S1 is the same fault on
        #     ROADMAP.md: "a 10,618-line diff over 5,309 lines, in which any real change is
        #     invisible".
        #
        # Both are LOSSLESS to repair, so these say how to repair rather than saying
        # `git checkout`: the content is fine, only the bytes around it are wrong. The byte
        # constants are built from numbers rather than written as escapes -- a typed escape in this
        # file is exactly what the last tool to get encoding wrong would rewrite.
        if raw[:3] == BOM_BYTES:
            problems.append(p + ": BOM -- Studio stores Source as LF with no BOM, so this file can "
                            "never hash-match. Strip the first three bytes; the content is fine.")
        crlf = raw.count(CRLF_BYTES)
        if crlf:
            problems.append(p + ": " + str(crlf) + " CRLF line ending(s) -- this repo is LF and so "
                            "is Studio, so this is a permanent hash MISMATCH and it buries the real "
                            "change in the diff. Replace CRLF with LF; the content is fine.")

    # A Lua file that does not parse must never reach Studio, and `git checkout` is the whole cure
    # while it is still uncommitted.
    if any(p.startswith("src") and p.endswith(".lua") for p in paths):
        lint = os.path.join(ROOT, "tools", "luastruct.py")
        if os.path.exists(lint):
            r = subprocess.run([sys.executable, lint], capture_output=True, text=True, cwd=ROOT)
            for line in (r.stdout or "").splitlines():
                if line.startswith("BAD"):
                    problems.append("luastruct: " + line.strip())
    return problems


def cmd_sync(auto, push):
    cmd_render()
    rows = [r for r in dirty_files() if in_sync_paths(r[1])]
    skipped = [r for r in dirty_files() if not in_sync_paths(r[1])]

    if not rows:
        print("nothing to commit inside the sync paths")
        if skipped:
            print("left alone (outside the sync paths): " + ", ".join(p for _, p in skipped))
        return 0

    print("changed: " + str(len(rows)) + " file(s)")
    for st, p in rows[:40]:
        print("   " + (st or "??") + "  " + p)
    if len(rows) > 40:
        print("   ... and " + str(len(rows) - 40) + " more")

    if auto and len(rows) > AUTO_MAX_FILES:
        print("")
        print("REFUSED: " + str(len(rows)) + " changed files is over the auto limit of "
              + str(AUTO_MAX_FILES) + ".")
        print("That size is usually a bulk rewrite or a second agent mid-write, not one step's work.")
        print("Look at `git status`, then commit deliberately or run `board.py sync` without --auto.")
        return 2

    problems = guard([p for _, p in rows])
    if problems:
        print("")
        print("REFUSED -- the guard found " + str(len(problems)) + " problem(s). Nothing was staged:")
        for pr in problems:
            print("   " + pr)
        return 2

    steps, claims, reviews, state = load()
    done = sum(1 for s in steps if state[s["id"]] == "VERIFIED")
    msg = "board: sync %d file(s) -- %d of %d steps verified" % (len(rows), done, len(steps))

    for _, p in rows:
        code, _, err = git("add", "--", p)
        if code != 0:
            print("git add failed for " + p + ": " + err)
            return 1
    code, out, err = git("commit", "-m", msg)
    if code != 0:
        print("commit: " + (out or err))
        return 1
    print("committed: " + msg)

    if push:
        code, out, err = git("push", "origin", "HEAD")
        print("push: " + ("ok" if code == 0 else "FAILED -- " + (err or out).splitlines()[-1]))
    if skipped:
        print("left alone (outside the sync paths): " + ", ".join(p for _, p in skipped))
    return 0


def main():
    args = sys.argv[1:]
    cmd = args[0] if args else "check"
    who = "both"
    if "--as" in args:
        i = args.index("--as")
        if i + 1 < len(args):
            who = args[i + 1].lower()
    if cmd == "render":
        cmd_render()
    elif cmd == "check":
        cmd_check(who)
    elif cmd == "sync":
        return cmd_sync("--auto" in args, "--no-push" not in args)
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
