"""Move MainUI's TRADING UI block (an already-closed IIFE) into Modules/HUD/TradePanel.lua.

This is the TEMPLATE extraction: 23 of MainUI's blocks are `;(function() ... end)()` closures
written that way to dodge Luau's 200-register cap, which means each one already has a small,
knowable set of captured upvalues. Turning one into `require(...)(hudRefs)` is therefore a
rename of the wrapper, not a rewrite of the code. Everything inside moves byte-for-byte.

Trading's captured set, measured: screenGui, registerPanel, panelClose, toggleOnly,
showNotification, flatText, currentData -- plus services and the UIKit helpers, which the
module requires for itself. Only `currentData` needs a change, because it is REASSIGNED in
MainUI (`currentData = data` on every DataUpdate) and a module cannot see another script's
local being rebound; it becomes `hud.getData()`.
"""
import io
import sys
from pathlib import Path

ROOT = Path(r"C:\Users\Kristina\Documents\evolution-lab")
MAIN = ROOT / "src/StarterPlayer/StarterPlayerScripts/MainUI.client.lua"
DEST = ROOT / "src/ReplicatedStorage/Modules/HUD/TradePanel.lua"

BANNER, OPEN, CLOSE = 10136, 10139, 11106     # 1-indexed

HEADER = '''-- TradePanel -- the whole of player-to-player trading on the client: the invite pop-in, the
-- partner picker, the two-sided offer board, the confirm countdown and the four remotes behind
-- them (Phase 8.6).
--
-- WHY THIS IS ITS OWN FILE (18.9)
-- ------------------------------
-- It was 968 lines at the bottom of `MainUI`, and it was ALREADY a closed
-- `;(function() ... end)()` block -- written that way because that file sits on Luau's 200-local
-- ceiling and one more top-level local deletes the entire HUD. That wrapper is what makes this
-- extraction safe: a closure that escapes nothing has a knowable set of captured upvalues, and
-- for this block that set is seven names. So the move is a change of wrapper, not of code --
-- everything below the `return function(hud)` line is byte-for-byte what was in MainUI.
--
-- THE ONE THING THAT COULD NOT MOVE VERBATIM is `currentData`. MainUI REBINDS it
-- (`currentData = data`) every time the server pushes a DataUpdate, roughly every three seconds,
-- and a module cannot see another script's local being reassigned -- it would have captured the
-- value that happened to be there when this file first ran, which for a player who opens a trade
-- in their first seconds is `nil`. It reads `hud.getData()` instead, which is MainUI's own
-- closure over the live local.
--
-- WHAT `hud` IS: the HUD context table -- MainUI's `hudRefs`, the table it was already using to
-- get handles out of these closures. See the block that fills it in MainUI, and `docs/SPLIT.md`
-- for the contract every module in this folder is held to.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))

local Remotes = RS.Remotes
local player = Players.LocalPlayer

local corner, stroke = UIKit.corner, UIKit.stroke
local styleCard, themeLabel = UIKit.styleCard, UIKit.themeLabel
local PANEL_SHELL, PET_ROW_SHELL = UIKit.PANEL_SHELL, UIKit.PET_ROW_SHELL

return function(hud)
\tlocal screenGui = hud.screenGui
\tlocal registerPanel, panelClose, toggleOnly = hud.registerPanel, hud.panelClose, hud.toggleOnly
\tlocal showNotification, flatText = hud.showNotification, hud.flatText

'''

FOOTER = "end\n"

CALL = '''-- ============================================================================
-- TRADING UI & REMOTES (Phase 8.6)
-- ============================================================================
-- MOVED OUT (18.9) to `ReplicatedStorage.Modules.HUD.TradePanel` -- 968 lines of it, unchanged.
-- It was already a `;(function() ... end)()` closure capturing seven names from this file, so the
-- module takes those seven as `hudRefs` and nothing else had to be threaded through. The block
-- returned nothing and escaped nothing, which is why this is a plain call and not an assignment.
require(RS.Modules:WaitForChild("HUD"):WaitForChild("TradePanel"))(hudRefs)
'''

CTX = '''-- ================= THE HUD CONTEXT =================
-- WHAT AN EXTRACTED PANEL MODULE IS ALLOWED TO SEE, AND WHY IT IS A TABLE AND NOT A REQUIRE.
--
-- `hudRefs` already existed: it is the one table this file uses to get handles OUT of the
-- `;(function() ... end)()` blocks the register cap forces every panel into. Splitting panels
-- into modules needs the traffic to run the other way as well, and it is the same table -- so a
-- module gets `hudRefs`, not a bespoke context object, and adding a field costs no register.
--
-- ORDERING IS THE WHOLE OF THE CONTRACT. Every name below is a local defined ABOVE this line, and
-- every module call must come BELOW it. A module extracted from somewhere earlier in the file
-- moves this block up to just before its call site -- and can then only be handed the fields that
-- are already filled at that point. Nothing here is a forward declaration; a nil in this table is
-- a panel that silently does nothing.
--
-- `getData` IS A FUNCTION AND THE OTHERS ARE NOT, for one reason: `currentData` is REBOUND on
-- every DataUpdate (about every three seconds), and a module that captured the value would hold
-- whatever was there when the client started -- `nil` for the first few seconds of a session.
-- The closure reads this file's live local. Anything else that becomes reassignable later must
-- join it as a getter rather than be copied in here.
hudRefs.screenGui = screenGui
hudRefs.registerPanel = registerPanel
hudRefs.panelClose = panelClose
hudRefs.toggleOnly = toggleOnly
hudRefs.closeAllPanels = closeAllPanels
hudRefs.showNotification = showNotification
hudRefs.flatText = flatText
hudRefs.getData = function() return currentData end

'''


def main():
    if DEST.exists():
        sys.exit("TradePanel.lua already exists -- refusing to run twice")

    lines = io.open(MAIN, encoding="utf-8", newline="").read().split("\n")

    assert lines[BANNER] == "-- TRADING UI & REMOTES (Phase 8.6)", lines[BANNER]
    assert lines[OPEN - 1] == ";(function()", repr(lines[OPEN - 1])
    assert lines[CLOSE - 1] == "end)()", repr(lines[CLOSE - 1])

    body = lines[OPEN:CLOSE - 1]                       # inside the IIFE, indentation intact

    hits = [i for i, l in enumerate(body) if "currentData" in l]
    assert len(hits) == 1, hits
    assert body[hits[0]] == "\t\tlocal data = currentData", repr(body[hits[0]])
    body[hits[0]] = "\t\tlocal data = hud.getData()"

    DEST.parent.mkdir(parents=True, exist_ok=True)
    DEST.write_text(HEADER + "\n".join(body) + "\n" + FOOTER, encoding="utf-8", newline="")

    rest = lines[:BANNER - 1] + CTX.split("\n")[:-1] + CALL.split("\n")[:-1] + lines[CLOSE:]
    MAIN.write_text("\n".join(rest), encoding="utf-8", newline="")

    print("TradePanel.lua  %d lines" % (DEST.read_text(encoding="utf-8").count("\n") + 1))
    print("MainUI          %d lines (was %d)"
          % (MAIN.read_text(encoding="utf-8").count("\n") + 1, len(lines)))


main()
