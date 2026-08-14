# Handoff log

One entry per roadmap row touched by a non-reviewing agent. **Append only — never edit or delete a
past entry**, including your own, and including one that turned out to be wrong. A corrected entry
is a new entry.

The reviewing agent reads this file plus the git diffs and nothing else. Anything not written here
is invisible to the review.

## How to write an entry

Copy the template. Fill in every field. Empty fields are treated as "not done".

- **Evidence** must be numbers you actually observed in a running game — health values, damage
  figures, item counts, pixel measurements, console output. Not "tested and works".
- **Not verified** is a required field, not an admission of failure. If a row's own check in
  `ROADMAP.md` could not be run, say which part and why. This is the single most useful line in
  the file: it tells the reviewer where to look first, and it is much cheaper than discovering the
  gap after trusting the entry.
- **Rules broken** — if you had to violate anything in `GEMINI.md` §0, write which and why. Do not
  quietly omit it.

---

## Template

```markdown
### <ROW ID> — <one-line summary>

- **Date:** YYYY-MM-DD
- **Status set in ROADMAP.md:** `[~]`
- **Files changed:** src/... (list every one)
- **Commit:** <sha>
- **What was built:** two or three sentences. What the code now does that it did not do before.
- **Why this shape:** the decision you made and what you rejected. One or two sentences.
- **Evidence (live, in Studio):**
  - measured X = <number>, expected <number>
  - measured Y = <number>
- **Not verified:** what you could not test, and why.
- **Rules broken:** none / <which, and why>
- **Open questions for review:** anything you were unsure about.
```

---

## Entries

_(none yet — Gemini appends below this line)_
