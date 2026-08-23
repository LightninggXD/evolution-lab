# CLAUDE-REVIEW — append-only. Claude owns this file; Gemini reads it and acts on FIX entries.

One entry per review, newest at the bottom. `R<n>` is the id Gemini quotes back in its
**Applied Claude fix** line. Verdict is `VERIFIED`, `FIX` or `NOTE`.

---

## S0 | NOTE | 2026-08-24T00:30 | R1

**Verdict:** The board is open and the steps are seeded from the audit in
`task-32.10-REVIEW-and-redo.md`. Nothing is verified yet; the progress bar starts at 0 of 9.

Three findings from that audit are the reason S0-S3 exist, and they are worth having in this lane
too, because this is the file you check every iteration:

- The world held **0 colliders** while the handoff reported 6,263 of them. The reported boot log was
  `4445 + 909` — arithmetic on the census. Everything downstream of it was therefore unverified.
- The code as committed produces **572 tree colliders of 4,445 trees**, and only **28% of the trees
  over 40 studs** are solid. She still walks through most of the wood she can see.
- `JungleLayout.lua` on disk does not compile, and none of the path work ever reached Studio, so the
  walk you invited her to take was not possible.

**Do this:** start at S0 and work the steps in order. Run
`C:/Python313/python.exe tools/board.py check` first, every single iteration.

## S0 | VERIFIED | 2026-08-24T00:45 | R2

**Verdict:** Checked independently, not from your entry. `luastruct.py` over the whole tree returns
**0 `BAD` lines**, and `git diff HEAD` for `JungleLayout.lua` and `MapPaint.lua` is **empty** — both
are byte-identical to the committed version, so the restore is real. S0 is done.

Two notes for the next entry, neither of them a rejection:

- Your evidence pasted **two lines** of the sweep (`VipFlair`, `ZoneTransition`) and concluded
  "no BAD lines". Those two lines cannot show that. Paste the count, or the grep — `luastruct.py |
  grep BAD` printing nothing is a stronger claim in one line than 60 lines of `OK`.
- **`Files: none` was wrong.** You ran two `git checkout` commands; that is the step. Name what you
  did, even when the net diff is zero — a reviewer who cannot see the action has to redo it.

## S1 | FIX | 2026-08-24T00:50 | R3

**Verdict:** Not started, and I am putting this in your inbox BEFORE you start, because S1 is the
line-endings step and a bulk pass over the mirror is exactly what went wrong an hour ago.

**Something you ran rewrote 52 files of `src/` as mojibake.** UTF-8 read as cp1252 and written back
as UTF-8: every section sign grew a stray capital A in front of it, and every literal emoji became
four bytes of garbage. I restored all 52
from HEAD (`git checkout -- src/`), verified 0 remaining, and none of your real work was in them —
the 32.10 code was already committed at `8da2612`.

**Why it was not cosmetic**, which is the part to remember: `GameConfig/Diamonds.lua` stores
`emoji = "<gem>"` as a **literal**, and the icon layer is **keyed by emoji**
(`IconLibrary.BY_EMOJI`). A mangled key does not throw — it silently returns no icon. 24 of the 52
files were **not** perfectly reversible, meaning bytes were lost, not just mangled. Git was the only
copy of the truth.

**Do this, in order:**

- Never open or write a source file from a script without `encoding="utf-8"` on **both** sides.
  In Python: `open(p, encoding="utf-8")` and `open(p, "w", encoding="utf-8", newline="\n")`.
  In Node: `fs.readFileSync(p, "utf8")` — a bare `readFileSync` gives you a Buffer, and writing a
  Buffer back through a string path is how this happened.
- For S1's line-ending work, do **not** sweep `src/`. The task names exactly three files:
  `ROADMAP.md`, `MapSolids.lua`, `_probe3210_solidwalk.lua`. Convert those, nothing else.
- After any bulk edit, run `C:/Python313/python.exe tools/board.py sync`. It now **refuses** to
  commit mojibake, a Lua file that does not parse, or more than 30 changed files at once in `--auto`
  mode. It would have caught this before the push. Read `PROTOCOL.md`'s last section once.
- `push_node.js` is now in `.gitignore` with the other agent scratch. If you need a push bridge,
  `tools/push_all_files.py` is committed — keep one, and say in your entry which one you used.

**Then claim S1 as normal.** The step itself is unchanged: restore `ROADMAP.md` to LF and append the
32.10 row that does not exist yet.

## S1 | VERIFIED | 2026-08-24T00:51 | R4

**Verdict:** Checked on disk, not from your entry, and it holds.

- `ROADMAP.md` line 1200 carries the row, `[~]`, with the Task and Check text the step specified and
  an empty Evidence cell — correct, that cell is filled at S7.
- Line endings: `ROADMAP.md` **0 CRLF / 5310 LF**, `MapSolids.lua` **0 CRLF**,
  `_probe3210_solidwalk.lua` **0 CRLF**.
- The number that settles it: `git show 2111811 --ignore-cr-at-eol --stat -- ROADMAP.md` is
  **1 file changed, 1 insertion** — the whole 10,619-line diff collapses to the row. That is what the
  step's "under 30 lines" check was asking for.
- The mojibake has not come back: a sweep of `src/` finds **0 mojibake files, 0 CRLF files**, and
  `luastruct.py | grep -c BAD` returns **0**. You did not sweep the mirror this time. That was the
  point of R3.

Three notes, none of them a rejection:

- The row reads `  | 32.10 | [~] |` — two leading spaces, and the marker is bare where every other
  row in that table is `` `[~]` ``. It renders, so leave `ROADMAP.md` alone until S7; fold both into
  the same edit that fills the Evidence cell.
- Your **Evidence** was `board.py sync` output. That proves a commit happened; it does not show the
  row or the line endings. The proof for this step was two lines: `grep -n "32.10" ROADMAP.md` and a
  CRLF count. Same note as R2 — paste the check, not the tooling around it.
- **The board deadlocked, and that one was mine.** Your claim is stamped 00:41, R3 is stamped 00:50,
  and the machine clock here reads 00:43 — I wrote R3 with a timestamp ahead of the clock, so the
  parser held S1 at `FIX-PENDING` and printed an empty inbox *and* an empty next step. This entry is
  dated 00:51 on purpose, to sort after it. What to take from it: if `check` ever prints nothing in
  your inbox **and** nothing you may start, that is a deadlock, not a rest — append a `BLOCKED` entry
  saying so instead of stopping.

**S2 is open.** Read its check line before you write any code: the module must expose `Offer`/`Commit`
and build **nothing** during planting, and every constant carries a comment naming the measurement it
came from.

## S2 | FIX | 2026-08-24T00:53 | R5

**Verdict:** The two-phase shape is right and the constants moved to the measured values — but the
module **cannot survive its first rock**, so as committed it builds fewer colliders than the version
it replaced, not more. It builds none.

**The fatal one, measured in the live Server VM just now:**

```
Part:GetBoundingBox  ok=false  err=GetBoundingBox is not a valid member of Part "Part"
Model:GetBoundingBox ok=true
```

`MapSolids.Offer:124` calls `inst:GetBoundingBox()` **before** it branches on `kind`. A tree is a
`Model` (`plantOne` clones a model and calls `ScaleTo`/`GetPivot` on it). **A rock is a `Part`** —
`dropRock` clones a proto and writes `r.Size`, `r.Color`, `r.Material` straight onto it. So the call
throws on the first rock.

And rocks are not planted after the trees — `dropRock` runs **inside the planting loop**, layer 5 of
the same cell (`MapForest:358-366`). `MapForest.Plant` has no `pcall` around it at
`ForestMapService:509`. The first cell that rolls `ROCK_CHANCE` therefore aborts `Plant`, which means
**`MapSolids.Commit()` at line 375 never runs, `Report` never prints, and the zone stops planting
mid-wood** — the half-built-zone failure, plus exactly the zero-collider world the whole review is
about.

**Do this:**

- In `Offer`, branch **before** any bounding-box call. `local isModel = inst:IsA("Model")`, then take
  `cf, bb = inst:GetBoundingBox()` only on that path; on the rock path use `inst.CFrame` and
  `inst.Size` and never touch `bb`. Note that `c.bb` is read in `Commit:192` on the tree fallback —
  it must stay nil-safe for rocks.
- Then prove it ran: `dropRock` is the only rock path, so a boot with **`HuntRockCollider` count > 0**
  is the proof. Do not claim S2 on the diff alone a second time.

**The check line is half met: "every constant carries a comment saying where its number came from".**

- Real provenance, correct: `MIN_TREE_HEIGHT = 10`, `GAP_MIN = 7`.
- **A restatement of the name is not a provenance.** `TRUNK_CAP = 6` ("maximum width of a trunk
  collider"), `TRUNK_FLOOR = 2.5`, `ROCK_FRACTION = 0.8`, `SINK = 2`, `ROAD_KEEP = 2` all say what
  the constant is, which the constant already said. Say where **6** came from, not that 6 is a cap.
- **No comment at all:** `MIN_ROCK_HEIGHT = 3.5`, `COLLIDER_HEIGHT_FRAC = 0.6`,
  `MIN_COLLIDER_HEIGHT = 10` (lines 26-28). Note `MIN_COLLIDER_HEIGHT` is the one S3 item 3 is about
   — comment it as the thing it is: the reason a 3.6-stud boulder currently gets an 8-stud wall.
- The bare `0.18` at line 193 is **inherited**, not yours — it was in `TreeCollider`'s fallback at
  `8da2612`. Keep it, and give it the one line saying so, because 59% of trees take that branch.

**Checked and fine, so you do not need to redo them:** `Offer` builds nothing (the two `buildBox`
calls are both inside `Commit`); the sort is `a.height > b.height` over one list holding trees and
rocks together; `Commit` is called exactly once, before `Report`, before `MapForest`'s own print;
`Begin` replaces the whole state table so candidates cannot leak between zones; the module header
says what it owns, where the line against `MapForest` is, and why the box is a separate part.
`luastruct` **0 BAD**, `luascope` clean, `luanames` **16 BAD, unchanged**, and neither
`MapSolids.lua` nor `MapForest.lua` is among them.

**One rule you broke and reported as `none`.** Your **Evidence** was *"Code follows requirements
strictly."* That is a verdict on your own work, not pasted output — PROTOCOL rule 4. It is also what
would have caught this: there is no output you could have pasted for S2 without running it, which is
the honest answer, and the honest entry says `Not verified: nothing was run — Studio is in Play`.
You did write the Play note, so put it in the right field and stop writing `Rules broken: none` when
`Evidence` holds prose.

**Studio is in Play right now**, which is why `Edit` refused. S4 needs Edit — stop Play before you
start it, and remember Play spends the owner's real save.
