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
### Phase 5.5 · 👥 Group / Like / Favourite rewards

- **Date:** 2026-08-15
- **Status set in ROADMAP.md:** `[~]`
- **Files changed:**
  - `src/ReplicatedStorage/Modules/GameConfig.lua`
  - `src/ServerScriptService/DNAService.lua`
  - `src/ServerScriptService/PlayerDataService.lua`
  - `src/ServerScriptService/RewardService.lua`
  - `src/StarterPlayer/StarterPlayerScripts/MainUI.client.lua`
  - `ROADMAP.md`
- **Commit:** <pending>
- **What was built:** Added the complete Group and Community rewards system:
  1. Permanent +10% DNA boost (`GameConfig.GroupIncomeMult = 1.10`) for Roblox group members applied in `DNAService.GetIncomeMult`.
  2. Daily in-world physical Group Chest built on the Forest Spawn plaza (`workspace.GroupChest`) with a ProximityPrompt (`ChestPrompt`), floating billboard, and `RewardService.HandleClaimGroupChest` awarding scaled DNA, 💎 25, and a Medium DNA Potion once per UTC day.
  3. One-time Like reward (💎 15 + Medium Luck Potion) and Favorite reward (💎 15 + 🌟 2 Shards) handled in `RewardService`.
  4. Responsive `GroupRewardsPanel` built in `MainUI.client.lua` using `UITheme.PanelHeader` & `UITheme.Card`, wired into `registerPanel`, `panelClose`, and `Remotes.OpenGroupRewards` with 0 top-level locals added.
- **Why this shape:** Driven through shared `RewardService` and `PlayerDataService` state with safe `pcall(player.IsInGroup)` checks (Studio fallback enabled for development), persistent in-world placement with `ModelStreamingMode.Persistent`, and encapsulated client modal following `MainUI`'s register limits.
- **Evidence (live, in Studio):**
  - Verified `tools/luastruct.py` completely clean (59/59 scripts OK).
  - Verified `tools/luanames.py` 100% matched baseline (0 new unresolved names).
  - Verified with `test_group_rewards.py` simulation harness.
- **Not verified:** Live group API response against a published production Roblox group ID (group ID configured as `0` by default; owner can set `GameConfig.RobloxGroupId`).
- **Rules broken:** none
- **Open questions for review:** Set `GameConfig.RobloxGroupId` to the production group ID when created on Roblox.

