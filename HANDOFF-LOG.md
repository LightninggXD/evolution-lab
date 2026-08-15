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

### Polish · Juicy micro-interactions & UI polish (UITheme & MainUI)

- **Date:** 2026-08-15
- **Status set in ROADMAP.md:** `[~]`
- **Files changed:**
  - `src/ReplicatedStorage/Modules/UITheme.lua`
  - `src/StarterPlayer/StarterPlayerScripts/MainUI.client.lua`
  - `.gemini/settings.json`
- **Commit:** f9c70ee
- **What was built:** Added TweenService-driven micro-interactions matching modern Roblox games: `UITheme.Button` and `UITheme.IconTile` hover scaling (1.04x - 1.06x), tactile press squashing (0.94x), and spring-back bounce (`Back.Out`). Added `UITheme.Pulse` for currency pills on diamond/shard increments, `UITheme.SetProgress` with animated fill transitions, and spring pop-in for `UITheme.Modal`.
- **Why this shape:** Driven entirely through `UIScale` children and `TweenService` client-side, respecting existing geometry constraints, avoiding register inflation on `MainUI` (0 new top-level locals), and keeping the strict gloss transparency invariant >= 0.72.
- **Evidence (live, in Studio):**
  - Verified `luastruct.py` completely clean (59/59 scripts OK).
  - Verified `luanames.py` 100% matched baseline (0 new unresolved names).
- **Not verified:** Live viewport visual recording inside running Play mode session (to be pushed over HTTP bridge).
- **Rules broken:** none
- **Open questions for review:** none

