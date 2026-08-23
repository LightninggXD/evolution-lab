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
