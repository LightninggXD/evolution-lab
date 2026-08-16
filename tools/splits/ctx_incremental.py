"""Fill the HUD context table INCREMENTALLY, right after each helper is defined.

The first cut of this put one `hudRefs.x = x` block just above the TradePanel call, which works
for TradePanel and for nothing else: `showNotification` is defined at line 7793, so a module
extracted from anywhere above that would be handed nil. Lua binds a name to the variable that is
in scope WHERE THE CODE IS WRITTEN, which is the same rule that makes the existing IIFE blocks
work at all -- so the table has to be filled at the same points, not once at the end.

Edits are applied bottom-up so earlier line numbers stay valid.
"""
import io
from pathlib import Path

MAIN = Path(r"C:\Users\Kristina\Documents\evolution-lab"
            r"\src\StarterPlayer\StarterPlayerScripts\MainUI.client.lua")

lines = io.open(MAIN, encoding="utf-8", newline="").read().split("\n")


def at(n):                      # 1-indexed read
    return lines[n - 1]


# ---- the anchors this script was written against. If any of these moved, stop. ----
assert at(14) == "local currentData = nil"
assert at(50) == "screenGui.Parent = playerGui"
assert at(659) == "end" and at(574).startswith("local function registerPanel")
assert at(754) == "end" and at(750).startswith("local function closeAllPanels")
assert at(764) == "end" and at(755).startswith("local function toggleOnly")
assert at(996) == "end" and at(978).startswith("local function panelClose")
assert at(1366) == "local hudRefs = {}"
assert at(2225) == "end" and at(2220).startswith("local function flatText")
assert at(7948) == "end" and at(7793).startswith("local function showNotification")

# The single-block version this replaces.
CTX_HEAD = "-- ================= THE HUD CONTEXT ================="
ctx_start = next(i for i, l in enumerate(lines) if l == CTX_HEAD)
ctx_end = next(i for i, l in enumerate(lines[ctx_start:], ctx_start)
               if l.startswith("hudRefs.getData ="))

# ---- insertions, as (after_line_1indexed, [lines]) ----
INSERTS = [
    (7948, ["hudRefs.showNotification = showNotification"]),
    (2225, ["hudRefs.flatText = flatText"]),
    (996, ["hudRefs.panelClose = panelClose"]),
    (764, ["hudRefs.closeAllPanels = closeAllPanels", "hudRefs.toggleOnly = toggleOnly"]),
    (659, ["hudRefs.registerPanel = registerPanel"]),
    (50, ["hudRefs.screenGui = screenGui"]),
]

HUDREFS_BLOCK = '''
-- ================= THE HUD CONTEXT =================
-- WHAT A PANEL MODULE IN `ReplicatedStorage.Modules.HUD` IS ALLOWED TO SEE.
--
-- `hudRefs` was already here for the opposite traffic: it is how the `;(function() ... end)()`
-- blocks this file's register cap forces every panel into get a handle back OUT (see
-- `hudRefs.refreshPetsPanel`). Splitting those blocks into real modules needs the same table to
-- carry things IN, so a module is handed `hudRefs` rather than a context object of its own, and
-- a new field costs no register.
--
-- IT IS FILLED INCREMENTALLY, one line under each helper as that helper is defined, and that is
-- not tidiness. `showNotification` is not written until line ~7900; a module extracted from above
-- it and handed a table filled at the bottom of the file would be handed **nil**. Filling it at
-- the point of definition means the rule for a module is exactly the rule for the IIFE it
-- replaces: it may use whatever exists ABOVE its own call site, and nothing below.
--
-- THE COROLLARY, AND IT IS THE ONE THAT BITES: a module may only DESTRUCTURE (`local f =
-- hud.showNotification`) what is already filled when it is called. Anything it needs that is
-- filled later must be read off the table at USE time (`hud.showNotification(...)`) -- the table
-- is shared by reference, so a field set afterwards is visible to a callback, but a local copied
-- at build time is frozen at nil forever. `docs/SPLIT.md` has the contract in full.
--
-- `getData` IS A FUNCTION WHERE THE REST ARE VALUES because `currentData` is REBOUND on every
-- DataUpdate, about every three seconds. A module that captured the value would hold whatever
-- was there when the client started -- nil for the first seconds of a session. This closure reads
-- the live local instead.
local hudRefs = {}
hudRefs.getData = function() return currentData end
'''

# ---- apply, bottom-up ----
del lines[ctx_start:ctx_end + 1]

for after, block in INSERTS:
    lines[after:after] = block

# move the declaration to the top, where `currentData` is, and drop the old one-liner
old = next(i for i, l in enumerate(lines) if l == "local hudRefs = {}")
del lines[old]
lines[14:14] = HUDREFS_BLOCK.split("\n")[1:-1]

MAIN.write_text("\n".join(lines), encoding="utf-8", newline="")
print("MainUI now %d lines" % len(lines))
