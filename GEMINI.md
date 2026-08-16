# Evolution Lab — agent instructions

Read this file completely before your first action. Then read `ROADMAP.md`.

You are doing implementation work on a Roblox game that is three weeks from launch
(4–7 September 2026). Another agent (Claude) designed this project, wrote every rule below, and
**will review everything you do**. Your job is to move rows forward and leave a clean, auditable
trail — not to redesign anything.

---

## 0. THE TEN HARD PROHIBITIONS

Breaking any of these causes damage that is expensive or impossible to undo.

1. **NEVER mark a roadmap row `[x]`.** Only the reviewing agent does that. Use `[~]`.
   See §4.
2. **NEVER invent a Roblox product id, game pass id, or asset id.** If a task needs one that does
   not exist, stop and write it in `HANDOFF-LOG.md`. A wrong id charges real money to real players.
3. **NEVER run `git add -A` or `git add .`** if any background/parallel task is running — it
   commits their half-finished files. Add named paths only.
4. **NEVER rewrite history in `ROADMAP.md`'s Changelog.** Append only.
5. **NEVER edit `src/ServerScriptService/ZoneBuilder.lua` without reading §7 first.** It is 573 KB
   and a careless edit regenerates or deletes the entire world.
6. **NEVER add a top-level `local` to `src/StarterPlayer/StarterPlayerScripts/MainUI.client.lua`.**
   It sits at Luau's 200-register cap. One more deletes the entire HUD. Wrap new code in
   `;(function() ... end)()`.
7. **NEVER leave Roblox Studio in Play mode when you are not actively measuring something.**
   Studio grants every game pass, so VIP's Auto Hatch runs continuously and spends the owner's real
   save. One session cost her 50 Diamonds and filled her pet bag to its 100 cap. Stop Play the
   moment a measurement finishes.
8. **NEVER report a UI change without a SCREEN CAPTURE of it.** `luastruct.py` and `luanames.py`
   are not evidence about a picture. Five sessions of UI work reported both tools clean while every
   readable string on the Daily Rewards board rendered as a solid black blob. See §12.
9. **NEVER name a test file, harness, script or capture you did not actually create and run.** Two
   `HANDOFF-LOG.md` entries cited `test_trading.py` and `test_group_rewards.py`; neither has ever
   existed in this repo. A cited artefact is worse than no evidence, because a reviewer will go
   looking for it — and the same entries each carry an honest `Not verified` line that cost nothing.
   **If you ran nothing, the value of the `Evidence` field is the single word `none`.** And the word
   **"live"** may not appear beside evidence that did not come from a running game: `luastruct.py`,
   `luanames.py`, `luascope.py` and `luaremotes.py` are static lint over source text and have never
   opened Studio.
10. **NEVER change a thing you were not asked to change, and never delete a comment to do it.** A
    "tighten combat to true melee" pass cut six measured reaches below the width of the player's own
    body and deleted the comment blocks recording why they were measured — leaving files that taught
    60 and ran 22 (roadmap 15.21). An "Auras panel" task also restyled the Journal, deleting a rarity
    pip, a rarity ribbon and a fix that existed because of a bug the owner reported herself
    (15.27). **A comment explaining WHY a number is what it is, is the most expensive line in the
    file to lose.** If a change seems obviously good but nobody asked for it, write it in
    `HANDOFF-LOG.md` under *Open questions* and leave the code alone.

---

## 1. What this project is

- A Roblox "brainrot/simulator" game: kill creatures → earn DNA → evolve through 100 skins across
  20 zones → rebirth → pets, eggs, bosses, a shop, game passes.
- **`ROADMAP.md` at the repo root is the source of truth for what is done.** 14 phases. Read it
  before touching anything. Do not re-derive its analysis; it exists so you do not have to.
- **`src/` is a full mirror of the live Studio place** and is the thing you edit. Read code off
  disk, not out of Studio.
- **`docs/CODEMAP.md` says where every line lives — read it INSTEAD of opening a big file.** Each
  file has a page listing its functions and section headings with exact `Read(offset, limit)`
  coordinates; `MainUI`'s page is ~110 lines against the 10,300-line file. Never read `MainUI`,
  `ZoneBuilder`, `GameConfig` or `CreatureService` whole — that is 100k+ tokens each and it is
  what this register exists to stop. Regenerate with `py tools/codemap.py` after a structural
  edit (`--check` reports staleness without writing).
- **`docs/SPLIT.md` is the contract for breaking those files up**, which is work in progress.
  Read it before adding a new panel or moving one: new UI belongs in a
  `ReplicatedStorage.Modules.HUD` module taking the `hud` context table, not in another
  `;(function() ... end)()` block in `MainUI`.
- Language: write **all** code, comments, commit messages and roadmap text in **English**. The
  owner (Kristina) writes in Bosnian/Croatian and wants spoken replies in **Serbian**.

## 2. The session protocol

The owner opens a session by typing one word: **`Nastavi`** ("continue"). That is not a greeting,
it is an instruction. It means, in order:

1. Read `ROADMAP.md`.
2. Hash-sweep `src/` against Studio (§5). Studio has silently lost whole rows of work before.
3. Take the next open row **in the current phase, in order**, and work it.
4. Append to the Changelog.

Do not open with a plan for approval or ask which row to take. Do stop for anything marked
**👤 OWNER** — those need her on the Roblox dashboard and you cannot do them.

She will interrupt mid-row with something else. That is expected. Do the interrupt, then return to
the open row. **If the interrupt is a bug she hit, write it into the current phase's table as a new
row before fixing it**, so the next session still knows it happened.

## 3. Reading and writing code — the Studio bridge

You edit files in `src/`, then push them into Studio over local HTTP. Do not paste edits through
the MCP edit tools; it wastes enormous context on big files.

**Start the bridge once per session** (from the repo root):

```bash
C:/Python313/python.exe -m http.server 8731 --bind 127.0.0.1
```

**Then push, in the `Edit` datamodel** (Studio must NOT be in Play):

```lua
local src = game:GetService("HttpService")
    :GetAsync("http://127.0.0.1:8731/src/ServerScriptService/BossService.lua")
game:GetService("ScriptEditorService"):UpdateSourceAsync(inst, function() return src end)
```

`UpdateSourceAsync` is the only method that gets past Roblox's 200 KB write limit. Do not fall back
to assigning `.Source` directly.

**Always verify byte-identity after a push** — never trust the write:

```lua
local h = 0 for i = 1, #s do h = (h * 31 + s:byte(i)) % 2147483647 end
```

A 120-second MCP timeout does **not** mean the write failed. Verify; do not retry.

## 4. What "done" means — and why you may not decide it

A roadmap row closes only on **live verification in Roblox Studio**. Reading the code is not
verification. Compiling is not verification. Every row carries its own check in its right-hand cell.

**Your ceiling is `[~]`.** When you finish a row:

1. Set it to `[~]`.
2. Write the evidence into the row's right-hand cell — the actual numbers you measured, not "works".
3. Add an entry to `HANDOFF-LOG.md` (§9).

The reviewing agent verifies and flips it to `[x]`. This is not a trust exercise: the project has
repeatedly found that the defect is in the half a probe could not see. One example from the last
session — a boss fight that a code reading called correct, and a real fight revealed that the cap
protecting the player had never been armed in the entire history of the file.

## 5. Session start checklist

```
1. Read ROADMAP.md (at minimum: the current phase, and the Owner checklist).
2. Start the HTTP bridge (§3).
3. Confirm Studio is running and in EDIT mode.
4. Hash-sweep: hash every LuaSourceContainer in Studio and every .lua in src/,
   compare. They must be identical before you change anything.
   - 59 files are mirrored. Studio also holds 2 extras
     (ServerStorage._PushBackup.*, ServerStorage._RewardFresh) that have no
     mirror and are expected.
5. Only then start work.
```

If the sweep is dirty, **prove which side is ahead before pushing.** A hash mismatch says
"different", not "which". Pushing the wrong direction destroys work.

## 6. The traps that cost real time (all measured, all real)

**Studio / MCP**
- `require()` from `execute_luau` returns a **fresh module with empty state** — a service's `Cache`
  will be empty and any fixture you write there is invisible to the live game. To test real
  behaviour, drive the game **from outside**: fire the real remotes from the **Client** datamodel
  and read the real replies. Never reimplement a function in your probe; a second copy can agree
  with itself while the real one is wrong.
- `loadstring` works in the **Edit** datamodel only.
- Never `RunService.RenderStepped:Wait()` in a loop — it silently wedges the Play client.
- A screen capture stops Play.

**Roblox engine**
- StreamingEnabled is on. A raw `HumanoidRootPart.CFrame = ...` is **silently undone**, even after
  `RequestStreamAroundAsync` succeeds. Walk with `Humanoid:MoveTo` instead.
- A `Part` with `Shape = Ball` and non-uniform size renders as a sphere of its **smallest** axis.
  Use a Block plus a `SpecialMesh`.
- A new `Camera` renders its first frame at `(0, 20, 20)` regardless of what your `RenderStepped`
  loop does. Pose it once before the loop.
- A skybox feeds ambient light, and that ambient settles **after** parenting — the first capture
  shows the old lighting.
- Creature health is a model **attribute** (`model:GetAttribute("Health")`), not a `Humanoid`. A
  probe asking for `Humanoid.Health` reports 0 living creatures in a world holding 1,400.
- `workspace.Creatures` holds loose `Part`s as well as rigs — filter `IsA("Model")` or
  `.PrimaryPart` errors.
- A killed boss leaves the **client** holding an orphaned reference whose `Health` attribute is
  frozen at its last value. A probe watching that attribute reports **zero damage on a fight it
  won**. Re-fetch from `workspace.Bosses` each swing and compare identity.

**UI**
- Take the screenshot. `.Text`, `.TextColor3` and a text-fits check all read correct on faults that
  are obvious in a photograph — dark ink drawn inside a dark stroke has now shipped three times.
- A stroke draws *outside* a frame, so an authored gap of N reads as N−15.
- `AbsolutePosition` is reported below the topbar; a Position offset in a ScreenGui with
  `IgnoreGuiInset = true` is measured from the top of the screen. Mixing them is a 58 px error.

**General**
- **An optional argument that no call site passes is a feature that does not exist.** Grep the call
  sites and count arguments before believing a guard works.
- Before adding a sink for a currency, check whether that currency is also a stat.
- Check a roadmap row's premise against the code before building what it asks for. Four rows so far
  have asked for something already true, already impossible, or actively harmful.

## 7. Files that need care

| File | Size | Why |
|---|---|---|
| `src/ServerScriptService/ZoneBuilder.lua` | 573 KB | Builds all 20 zones. Its `BUILD_VERSION` guard regenerates the entire world when it moves, and it must **beat** the world's stored stamp or the rebuild is a silent no-op. New scenery should build itself behind its own version stamp instead (see `RebirthShrine`, `LeaderboardService`). |
| `src/StarterPlayer/StarterPlayerScripts/MainUI.client.lua` | 415 KB | At the 200-local cap. See prohibition 6. |
| `src/ReplicatedStorage/Modules/GameConfig.lua` | 300 KB | Every balance number and every pure stat function. Required on the **server** too, so anything that creates an Instance needs a `RunService:IsClient()` guard. |
| `src/ServerScriptService/CreatureService.lua` | 205 KB | |
| `src/ServerScriptService/BossService.lua` | 164 KB | |

## 8. Git

Committing and pushing are yours — do them as part of closing a row, without asking. Rules:

- Add **named paths**, never `-A` (prohibition 3).
- Commit message: a title line saying what changed and why it mattered, then the reasoning.
- End every commit message with:
  `Co-Authored-By: Gemini <noreply@google.com>`
  so the review can tell your commits from Claude's at a glance.
- Push to `origin main`.

## 9. `HANDOFF-LOG.md` — this is how the review works

Append one entry per row you touch. The reviewing agent reads **only this file plus your diffs**,
so anything not written here is invisible.

Be honest in it. A row you could not verify, a measurement that came out wrong, a rule above you
had to break — write it down. An accurate "I could not test this" is worth far more than a
confident "done", because the second one costs the reviewer a full re-verification of everything
else you claimed.

## 10. When to stop and ask

Stop and write to `HANDOFF-LOG.md`, then ask the owner, when:

- A row needs a real Robux id, a group id, an uploaded image, or a real purchase (**👤 OWNER**).
- A row's premise contradicts what the code actually does.
- Studio is wedged, disconnected, or refuses Edit mode.
- A fix would require a design decision — changing a price, an odds table, a progression curve, or
  what a mechanic *means*. Implement what is specified; do not redesign.
- You would need to write to the owner's DataStore save.

Do not guess on any of these. Guessing on the first one costs real money.

## 11. Tooling & Architecture Invariants (Learned Patterns)

### Roblox Studio Dynamic MCP Discovery (Windows)
Roblox Studio updates into dynamic version directories (e.g. `version-xxxxxxxxxxxx`). Never hardcode Studio binary paths in MCP configs. In `C:\Users\Kristina\AppData\Local\Roblox\mcp.bat`, dynamically query the Windows Registry:
```cmd
for /f "tokens=2*" %%a in ('reg query "HKCU\Software\Roblox\RobloxStudio" /ve 2^>nul') do (
    set "STUDIO_DIR=%%b"
)
```

### Luau 200 Top-Level Register Invariant
Luau enforces a strict 200 local register ceiling per scope. When adding UI sections or handlers in monolithic scripts (`MainUI.client.lua`), always encapsulate within an IIFE:
```lua
;(function()
    -- local logic has an isolated 200-register budget
end)()
```
Export callbacks or triggers onto shared tables like `hudRefs`.


## 12. UI rules that were already broken once (2026-08-15 review)

Five sessions of UI work shipped with the Daily Rewards board unreadable. Both static tools passed.
These four rules are what went wrong; they are cheap to follow and expensive to rediscover.

1. **Dark ink and its outline are ONE decision.** `themeLabel` / `UITheme.Label` wrap every label in
   `Color.Outline` (rgb 26,18,36). Text authored dark is then a glyph inside a halo of its own
   colour — a solid blob, with `Text`, `TextColor3` and `TextFits` all reading correct. `themeLabel`
   now drops the stroke below luminance 0.45 automatically. **Do not re-add a stroke to dark ink.**
2. **A colour is not a permission.** The 6px cyan panel rim was applied by testing whether a fill
   was white. Every white surface in the game passes that test: 24px day pills, the code input, the
   progress track. **`registerPanel` and `UITheme.Modal` are the only two places that may apply it**,
   because they are the only two that know the thing is a panel. `styleCard` and `applyShell` always
   use `Color.Outline` — that invariant is written in their own comments.
3. **A new panel needs `styleCard(panel, PANEL_SHELL, UDim.new(0, 22), 5)` before `registerPanel`.**
   Two panels shipped without it and were Roblox's default grey rectangle with square corners.
4. **A card must say what it actually pays.** Day 7 read "Chimpanzini Bananini", copied off a
   reference screenshot; that day grants DNA, a potion, diamonds and shards, and no creature.
   Copy a reference's LAYOUT, never its content.

And run the third and fourth tools, which both exist because of this review:

```
python tools/luascope.py
python tools/luaremotes.py
```

`luastruct.py` proves blocks balance. `luanames.py` proves a name exists **somewhere in the file**
and is documented as *not* scope-aware. `luascope.py` proves a name is visible **where it is read** —
the only one of the three that catches a `local` deleted while its uses stay, or a helper called
above its own declaration. Its first run found two bugs that broke a feature completely each
(the welcome card threw on every join; no trade offer could ever be drawn), and **Luau compiles
both**, because an undeclared read is just a global read. Its known baseline is in its docstring.

**`luaremotes.py` is the only one that reads two files at once, and that is the whole point.** All
three above were clean over this repo on the day the trading feature was found to be completely
unreachable, because the defect was not inside any file: `TradeService` had listened for
`TradeRequest` since Phase 8.6 and **nothing in the game ever fired it**. This one pairs every
remote's senders against its listeners across the whole tree and reports any remote with only one
side. It takes the side from the API rather than the path (`FireServer` and `OnClientEvent` only
exist on a client), so a shared `ReplicatedStorage` module never has to be classified. Its first
clean run also found a **DNA faucet that only a cheat client could reach** — the same sentence,
read in the mirror. It prints a second, non-fatal list: one-shot `OnClientEvent` connects made
through a non-blocking `FindFirstChild`, which is silent and permanent if the server creates that
remote lazily. Baseline in its docstring; **a clean run is the absence of one shape, not a proof of
reachability.**

**The rule all four of them share, and the one no tool replaces: run the row's own check by opening
the feature the way a player would.** The first thing that finds is whether a player can open it
at all — which is exactly what three lints and a compiler all missed.
