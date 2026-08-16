# SPLIT — how this codebase is being taken apart, and the rules for doing it

Four files hold two thirds of the game: `MainUI` (11,743 lines when this started), `ZoneBuilder`
(9,281), `GameConfig` (5,205) and `CreatureService` (3,869). Reading `MainUI` whole costs ~149k
tokens, which is most of a context window spent to change one label — and a file nobody can hold
in their head is a file where a change breaks something three thousand lines away.

This document is the contract for pulling them apart. It exists so the next session does not
re-derive it.

---

## 0. Two registers, and neither is written by hand

| what | where | regenerate with |
|:--|:--|:--|
| where every function and section lives, per file | `docs/CODEMAP.md` + `docs/codemap/*.md` | `py tools/codemap.py` |
| which blocks of `MainUI` are still waiting to move | *(printed on demand)* | `py tools/splitplan.py --deps` |

**Read `docs/CODEMAP.md` before searching for code.** A per-file page is ~110 lines and gives
exact `Read(offset, limit)` coordinates for every function and every section heading. `MainUI`'s
page costs about two thousand tokens against the hundred and fifty thousand the file costs.

Re-run `py tools/codemap.py` after any structural edit. `--check` exits 1 when the register is
stale and touches nothing, which is what a hook or a pre-commit step should call.

---

## 1. The seam the register cap already cut for us

`MainUI` sits on **Luau's 200-register ceiling** (see `evolution-lab-mainui-register-limit`), and
the standing rule for years has been that anything substantial goes inside
`;(function() ... end)()` so it gets a register file of its own.

Twenty-three blocks were written that way. **A closure that escapes nothing is already a module.**
So the split does not have to be designed — the constraint designed it, and `tools/splitplan.py`
reads the answer back out of the file. Each block's captured upvalues are its contract, and most
of them capture five or six names.

That is why extraction is a change of *wrapper*, not a rewrite:

```lua
;(function()                     -- becomes:   return function(hud)
    ...                          --                ...
end)()                           --            end
```

with the body moved **byte for byte**, indentation and comments included.

---

## 2. Where things go

```
ReplicatedStorage/Modules/
    UIKit.lua            the drawing kit: styleCard, styleButton, themeLabel, corner, stroke,
                         formatNumber, liftChildren, setButtonColor + the shell constants
    UITheme.lua          (unchanged) the design TOKENS — colours, radii, fonts, shared widgets
    HUD/
        TradePanel.lua   one panel, or one self-contained feature, per file
        ...
```

**UIKit vs UITheme, since both are "the UI module":** a *value* goes in `UITheme`, a *verb* goes
in `UIKit`. UITheme owns what colour a panel is; UIKit owns the act of painting an instance that
colour. UIKit requires UITheme; never the other way round.

A HUD module is a **function**, not a table:

```lua
return function(hud)
    ...
end
```

and MainUI calls it where the block used to be:

```lua
require(RS.Modules:WaitForChild("HUD"):WaitForChild("TradePanel"))(hudRefs)
```

Zero new top-level locals in MainUI — which matters, because the whole file is still one function
against those 200 registers.

---

## 3. `hud` — the context table, and the two rules that make it work

`hud` **is** MainUI's existing `hudRefs`. It already carried handles *out* of the closures
(`hudRefs.refreshPetsPanel`); now it carries helpers *in* as well. Same table, no new register,
and a module can both read from it and publish to it.

### Rule 1 — it is filled at the point of definition, not in one block at the end

The first attempt put every `hudRefs.x = x` in one block above the first module call. That works
for a module called at line 10,000 and for nothing else: `showNotification` is not written until
line ~7,900, so a module extracted from above it would be handed **nil**.

So each assignment sits one line under the helper it exports:

```lua
local function panelClose(panel)
    ...
end
hudRefs.panelClose = panelClose
```

A module may use whatever is filled **above its own call site**, and nothing below — exactly the
rule the IIFE it replaces already lived by.

### Rule 2 — destructure only what is already filled; otherwise read at use time

```lua
return function(hud)
    local screenGui = hud.screenGui              -- fine: filled at line 78
    ...
    button.Activated:Connect(function()
        hud.showNotification("done")             -- read AT USE, if it is filled later
    end)
end
```

The table is shared by reference, so a field set afterwards is visible to a callback — but a local
copied at build time is frozen at `nil` forever, silently, with no error anywhere. This is the one
that will bite.

### What is on it today

| field | kind | filled at |
|:--|:--|:--|
| `getData()` | **getter** | top of file |
| `screenGui` | value | after the ScreenGui is made |
| `registerPanel` | function | after its definition |
| `closeAllPanels`, `toggleOnly` | function | ” |
| `panelClose` | function | ” |
| `flatText` | function | ” |
| `showNotification` | function | ” |
| `refreshPetsPanel`, `refreshCharacterPanel` | function | (pre-existing, outbound) |

**`getData` is a function where the rest are values**, and that asymmetry is load-bearing:
`currentData` is *rebound* (`currentData = data`) every time the server pushes a DataUpdate, about
every three seconds. A module that captured the value would hold whatever was there when the
client started — `nil` for the first seconds of a session, which is exactly when a new player is
looking at the screen. Anything else that becomes reassignable must join it as a getter.

---

## 4. The recipe

1. `py tools/splitplan.py --deps` — pick a block; prefer a small captured set.
2. **Write the move as a Python script**, not by hand. Every comment in this codebase is
   load-bearing (GEMINI.md rule 10) and a hand-copy of 900 lines drops one. The script asserts its
   boundary lines before it slices, and refuses to run if the destination already exists. The
   three that have run live in `tools/splits/` — `extract_trade.py` is the one to copy.
3. Services and UIKit helpers are required by the module for itself; only true MainUI state goes
   through `hud`.
4. `py tools/luastruct.py`, `luanames.py`, **`luascope.py`** on both files. `luascope` is the one
   that matters here: it is the only check that catches a name used where it is *not in scope*,
   which is precisely what a bad extraction produces, and Luau compiles those.
   `luanames` reports three pre-existing unknowns in MainUI — `animatePanel`, `stop`,
   `nextStageDef`. They are not yours; check the count did not grow.
5. `py tools/manifest_build.py && py tools/codemap.py`.
6. Push to Studio (Edit mode) and **create the instance first** — a new module is not just a file:

   ```lua
   local hud = Modules:FindFirstChild("HUD") or Instance.new("Folder")
   hud.Name, hud.Parent = "HUD", Modules
   local m = Instance.new("ModuleScript"); m.Name, m.Parent = "TradePanel", hud
   ```

   then `ScriptEditorService:UpdateSourceAsync` from `http://127.0.0.1:8731/…`
   (see `evolution-lab-studio-http-bridge`), then `loadstring` both files.
7. **Sweep all files, not the two you touched** — Studio drifts per file and a stale `UITheme`
   has made a fresh `MainUI` throw before. The manifest pass reports identical/different/missing
   for every mirrored script in one call.
8. **Play, and take a screen capture.** `luastruct` is not evidence about a picture (GEMINI.md
   rule 8). Count the children of `EvolutionLabUI` — it was **42** after the trading split — and
   look at the panel that moved. Then **stop Play** (rule 7).

---

## 5. Done so far

| module | lines | out of |
|:--|--:|:--|
| `ReplicatedStorage/Modules/UIKit.lua` | 589 | MainUI 16–555 |
| `ReplicatedStorage/Modules/HUD/TradePanel.lua` | 1012 | MainUI's trading IIFE |

`MainUI` 11,743 → 10,302 lines. Verified: all lint clean, 55/55 files byte-identical to Studio,
HUD renders with all 42 children, trade picker drawn, console clean.

**22 blocks and ~5,360 lines remain** in MainUI — run `splitplan.py` for the current list. The
next three by size are the Season Pass panel (927), the Journal's ownership block (790) and the
potion timers (644).

---

## 6. After MainUI

Not started; the seams are known but unmeasured.

- **`GameConfig` (5,205)** — pure data, so the safest of the four. Split into siblings
  (`GameConfigZones`, `GameConfigSkins`, `GameConfigPets`, `GameConfigProducts`…) with `GameConfig`
  requiring them and re-exporting, so **no call site anywhere changes**. Check first what the
  accessor functions close over.
- **`ZoneBuilder` (9,281)** — read GEMINI.md §7 before touching it; a careless edit regenerates or
  deletes the world. The decoration/prop builders are leaves and go first. `BUILD_VERSION` must
  still beat the world's stamp or a rebuild is a silent no-op.
- **`CreatureService` (3,869)** and **`BossService` (3,053)** — server-side, no register cap
  pressure, so lower priority than the two above.
