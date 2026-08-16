"""Move MainUI's drawing kit (lines 16-555) into ReplicatedStorage/Modules/UIKit.lua.

Done as a script rather than by hand so the 540 moved lines are byte-identical -- every
comment in them is load-bearing and this project has been burned by a hand-edit that
dropped one. Verifies the boundary before writing and refuses to run twice.
"""
import io
import sys
from pathlib import Path

ROOT = Path(r"C:\Users\Kristina\Documents\evolution-lab")
MAIN = ROOT / "src/StarterPlayer/StarterPlayerScripts/MainUI.client.lua"
KIT = ROOT / "src/ReplicatedStorage/Modules/UIKit.lua"

FIRST, LAST = 16, 555          # 1-indexed, inclusive

KIT_HEADER = '''-- UIKit -- the HUD's drawing kit: every helper that turns a bare Roblox instance into a
-- piece of this game's interface.
--
-- WHY THIS IS ITS OWN FILE (18.9)
-- ------------------------------
-- These 540 lines were the top of `StarterPlayerScripts.MainUI`, which had grown to 11,743 --
-- ~149k tokens to read whole, for the sake of changing one label. The kit is the part of that
-- file that depends on NOTHING in it: it references `UITheme` and its own constants and not
-- `screenGui`, `currentData`, `player` or any remote, which is what makes it the one seam that
-- could be cut without threading state through the cut. Everything below is byte-for-byte what
-- was there, comments included -- no drawing behaviour was changed by the move.
--
-- WHO MAY REQUIRE IT: any client script. It is in `ReplicatedStorage.Modules` rather than under
-- `MainUI` so the next HUD-adjacent LocalScript (HatchReveal, EvolveReveal, SplicerUI ...) can
-- stop re-deriving `themeLabel` and use this one.
--
-- THE CONTRACT WITH `UITheme`, WHICH IS NOT THE SAME THING: `UITheme` owns the design tokens --
-- colours, radii, fonts, the shared PanelHeader/IconSlot widgets. This owns the *application* of
-- them to an instance the HUD just made. When in doubt: a value goes in UITheme, a verb goes here.
--
-- Where the rest of MainUI went: `docs/CODEMAP.md`.

local RS = game:GetService("ReplicatedStorage")

'''

KIT_FOOTER = '''
-- `gradientForColor` and `LIP_DEPTH` are exported for completeness but had NO caller outside
-- these lines when the kit was cut out -- `gradientForColor` had none at all. They are kept
-- rather than deleted because a dead helper is cheap and rule 10 of GEMINI.md is that nothing
-- gets removed on the side of a job that was not about removing it.
return {
	formatNumber = formatNumber,
	stroke = stroke,
	gradient = gradient,
	corner = corner,
	shade = shade,
	gradientForColor = gradientForColor,
	themeLabel = themeLabel,
	liftChildren = liftChildren,
	styleCard = styleCard,
	styleButton = styleButton,
	setButtonColor = setButtonColor,

	OUTLINE_COLOR = OUTLINE_COLOR,
	DISPLAY_FONT = DISPLAY_FONT,
	PANEL_SHELL = PANEL_SHELL,
	PET_ROW_SHELL = PET_ROW_SHELL,
	READY_RIM = READY_RIM,
	LIP_DEPTH = LIP_DEPTH,
}
'''

BRIDGE = '''-- ================= the drawing kit =================
-- THE KIT LEFT THIS FILE (18.9). `formatNumber`, `stroke`, `gradient`, `corner`, `shade`,
-- `themeLabel`, `liftChildren`, `styleCard`, `styleButton` and `setButtonColor` -- 540 lines of
-- them -- are `ReplicatedStorage.Modules.UIKit` now, byte for byte, with every comment that
-- explained why they draw the way they do. Nothing about the drawing changed; only where it lives.
--
-- WHY: this file was 11,743 lines, so changing one label meant reading ~149k tokens of context to
-- find it. The kit is the one block here that depends on nothing else in the file -- it reads
-- `UITheme` and its own constants, never `screenGui`, `currentData` or a remote -- so it is the
-- seam that cuts without dragging state across. `docs/CODEMAP.md` is the register of where the
-- rest lives; read that instead of reading this file.
--
-- RE-LOCALISED RATHER THAN CALLED AS `UIKit.styleCard(...)`, deliberately, on both counts:
--   * there are 500+ call sites below and rewriting every one of them is 500 chances to break the
--     HUD in exchange for nothing visible;
--   * a `local x = UIKit.x` costs exactly the register the `local function x` it replaces cost, so
--     this file's standing against Luau's 200-local ceiling is unchanged (it is one BETTER --
--     `LIP_DEPTH` and `gradientForColor` stayed behind in the module). See the note over the
--     Season Pass panel for what that ceiling does when it is crossed.
local UIKit = require(RS.Modules:WaitForChild("UIKit"))
local UITheme = require(RS.Modules.UITheme)

local formatNumber, stroke, gradient, corner = UIKit.formatNumber, UIKit.stroke, UIKit.gradient, UIKit.corner
local shade, themeLabel, liftChildren = UIKit.shade, UIKit.themeLabel, UIKit.liftChildren
local styleCard, styleButton, setButtonColor = UIKit.styleCard, UIKit.styleButton, UIKit.setButtonColor
local OUTLINE_COLOR, DISPLAY_FONT = UIKit.OUTLINE_COLOR, UIKit.DISPLAY_FONT
local PANEL_SHELL, PET_ROW_SHELL, READY_RIM = UIKit.PANEL_SHELL, UIKit.PET_ROW_SHELL, UIKit.READY_RIM
'''


def main():
    if KIT.exists():
        sys.exit("UIKit.lua already exists -- refusing to run twice")

    text = io.open(MAIN, encoding="utf-8", newline="").read()
    lines = text.split("\n")

    # The boundary is asserted, not assumed: if MainUI has moved under this script the line
    # numbers are meaningless and a silent slice would cut the file in the wrong place.
    assert lines[FIRST - 1] == "-- ================= helpers =================", lines[FIRST - 1]
    assert lines[LAST - 1] == "", repr(lines[LAST - 1])
    assert lines[LAST] == "-- ================= root gui =================", lines[LAST]
    assert lines[60] == "local UITheme = require(RS.Modules.UITheme)", lines[60]

    body = "\n".join(lines[FIRST - 1:LAST])          # lines 16..555 inclusive
    KIT.write_text(KIT_HEADER + body + KIT_FOOTER, encoding="utf-8", newline="")

    rest = "\n".join(lines[:FIRST - 1]) + "\n" + BRIDGE + "\n" + "\n".join(lines[LAST:])
    MAIN.write_text(rest, encoding="utf-8", newline="")

    print("UIKit.lua  %d lines" % (KIT.read_text(encoding="utf-8").count("\n") + 1))
    print("MainUI     %d lines (was %d)"
          % (MAIN.read_text(encoding="utf-8").count("\n") + 1, len(lines)))


main()
