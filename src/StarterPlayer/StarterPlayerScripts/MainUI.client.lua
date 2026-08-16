local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GameConfig = require(RS.Modules.GameConfig)
local PetModel = require(RS.Modules.PetModel)
local SoundLibrary = require(RS.Modules:WaitForChild("SoundLibrary"))
local Remotes = RS.Remotes

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local currentData = nil
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

-- ================= the drawing kit =================
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

-- ================= root gui =================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "EvolutionLabUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui
hudRefs.screenGui = screenGui

-- ===== Top bar: Stage + DNA =====
local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.Size = UDim2.new(1, 0, 0, 90)
topBar.Position = UDim2.new(0, 0, 0, 0)
topBar.BackgroundTransparency = 1
topBar.Parent = screenGui

local stageCard = UITheme.Card(topBar, {
	name = "StageCard",
	text = "🧬 Cell",
	color = UITheme.Color.Purple,
	size = UDim2.new(0, 240, 0, 52),
	-- y=42 clears the Roblox topbar (menu/chat icons own the top ~36px on the left).
	position = UDim2.new(0, 20, 0, 42),
	radius = 16,
	maxTextSize = 28,
})
local stageLabel = stageCard.Label

-- ===== THE SECOND DNA READOUT IS GONE (10.16) =====
--
-- DNA was drawn twice: a 300x74 card here in the top-right, and a pill in the bottom-left currency
-- stack. Keeping the pill and dropping the card is not a coin toss -- the stack is where this HUD
-- decided currencies live. It holds all three of them (DNA, Diamonds, Shards) in one consistent
-- column, and 3.7 put the `+` shop buttons on two of those pills, so the stack is both the readout
-- AND the way to act on it. The card was a leftover from when DNA was the only currency in the
-- game: it said the same number, in a different shape, in the opposite corner, with nothing to
-- press. Two places to look for one figure is one place too many, and the top bar keeps the Stage
-- card, which is the thing that corner is actually for.
--
-- Two more top-level locals paid back to a file at 181 of Luau's 200.

-- ===== Center hint: how to get DNA now =====
-- It teaches the one thing a player who has just landed does not know, and then it goes. It used
-- to be permanent: nothing in the file ever hid it, so a Star Weaver sitting on 59 billion DNA was
-- still being told where DNA comes from -- and at y=22 under an IgnoreGuiInset ScreenGui it was
-- half-tucked behind the Roblox topbar while it said so. Hidden on the first DNA the player earns
-- (see refreshUI), or after ninety seconds if they somehow have not earned any.
UITheme.Label(screenGui, {
	name = "ClickHint",
	text = "🧬 Fight creatures to collect DNA!",
	size = UDim2.new(0, 560, 0, 32),
	position = UDim2.new(0.5, 0, 0, 52),
	anchorPoint = Vector2.new(0.5, 0),
	maxTextSize = 22,
	zIndex = UITheme.Z.Content,
})
task.delay(90, function()
	local hint = screenGui:FindFirstChild("ClickHint")
	if hint then hint.Visible = false end
end)

-- ===== Bottom-centre: star + stage name, evolve progress bar, evolve button =====
local evolveFrame = Instance.new("Frame")
evolveFrame.Name = "EvolveFrame"
evolveFrame.Size = UDim2.new(0, 470, 0, 136)
-- -36, up from -22 (16.2): the world-event bar is pinned to the bottom edge at -5 and is 26 tall,
-- so its top edge sits at -31. Leaving this at -22 would have put the evolve card's own stroke
-- through the boss pill. Five pixels of daylight between the two.
evolveFrame.Position = UDim2.new(0.5, 0, 1, -36)
evolveFrame.AnchorPoint = Vector2.new(0.5, 1)
evolveFrame.BackgroundTransparency = 1
evolveFrame.Parent = screenGui

local evolveStageLabel = UITheme.Label(evolveFrame, {
	name = "StageProgressLabel",
	text = "⭐ Cell",
	size = UDim2.new(1, 0, 0, 30),
	position = UDim2.new(0.5, 0, 0, 0),
	anchorPoint = Vector2.new(0.5, 0),
	maxTextSize = 26,
	zIndex = 10,
})

local progressBarBg, progressBarFill, evolveProgressLabel = UITheme.ProgressBar(evolveFrame, {
	name = "EvolveBar",
	size = UDim2.new(1, 0, 0, 34),
	position = UDim2.new(0.5, 0, 0, 34),
	anchorPoint = Vector2.new(0.5, 0),
	color = UITheme.Color.Green,
	text = "0 / 50 DNA",
	maxTextSize = 22,
	zIndex = 4,
})

local evolveButton = UITheme.Button(evolveFrame, {
	name = "EvolveButton",
	text = "EVOLVE",
	color = UITheme.Color.Purple,
	size = UDim2.new(1, -70, 0, 50),
	position = UDim2.new(0.5, 0, 0, 82),
	anchorPoint = Vector2.new(0.5, 0),
	radius = UDim.new(1, 0),
	maxTextSize = 26,
})

-- refreshUI writes `evolveButton.Text`; mirror it onto the themed child label (which lives
-- above the gloss) so the existing call sites keep working unchanged.
local evolveButtonLabel = evolveButton.Label
evolveButton:GetPropertyChangedSignal("Text"):Connect(function()
	evolveButtonLabel.Text = evolveButton.Text
end)
evolveButton.Text = "EVOLVE (0 / 50 DNA)"

-- ===== Bottom-left: currency stack =====
-- THE THREE NUMBERS THE PLAYER LOOKS AT MOST WERE THE ONLY UNSTYLED THING ON THE SCREEN (16.x).
-- Photographed in Play on 2026-08-16: `UITheme.Pill` built a frame at BackgroundTransparency = 1
-- with no InnerBody and no UIStroke, so DNA / Diamonds / Shards rendered as bare outlined text
-- lying directly on the 3D world, while every other HUD element is a chunky outlined capsule. It
-- read as debug text somebody forgot to remove.
--
-- ONE DARK CAPSULE FOR ALL THREE, not one per currency hue. Two reasons, and the second is the
-- one that decides it: a wallet is a single readout and three different bright fills would split
-- it into three unrelated widgets; and the HUD's tiles already own every saturated colour on the
-- screen, so a dark shell is what separates a thing you READ from a thing you PRESS. The emoji
-- carries the per-currency identity, which is what it is there for.
--
-- 52,44,82 rather than Color.Outline (26,18,36): the outline is drawn ON this fill at 5px, and a
-- fill equal to its own stroke is a solid black lozenge with no rim. Dark enough for white ink,
-- light enough that the rim still draws the shape.
local currencyStack = Instance.new("Frame")
currencyStack.Name = "CurrencyStack"
-- 160, not 140: the gap below went 2 -> 10 (a 5px stroke is drawn OUTSIDE each capsule, so at 2
-- the three would have overlapped rims and read as one welded bar) and 46+40+40+2*10 = 146 plus
-- the strokes needs the room, or the top capsule lays out above its own frame.
currencyStack.Size = UDim2.new(0, 250, 0, 160)
currencyStack.Position = UDim2.new(0, 20, 1, -22)
currencyStack.AnchorPoint = Vector2.new(0, 1)
currencyStack.BackgroundTransparency = 1
currencyStack.ZIndex = UITheme.Z.Content
currencyStack.Parent = screenGui

local currencyLayout = Instance.new("UIListLayout")
currencyLayout.SortOrder = Enum.SortOrder.LayoutOrder
currencyLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
currencyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
currencyLayout.Padding = UDim.new(0, 10)
currencyLayout.Parent = currencyStack

-- ===== NEAR-WHITE CHROME, NOT CANDY (18.2) =====
--
-- Three passes got here. Bare outlined text on the 3D world -> one near-black indigo capsule for all
-- three -> Mint / Aqua / Lavender, painted on her own note ("nemoj te crne vec bright pastel i beli
-- theme"). She looked at the third and asked for the next step down, not for the dark bar back:
-- "ovo je lose ne vidi se nista od ovog okolo il napravi belje il lepse ne znam".
--
-- She is describing a measurement. In the kit's own luminance scale (0.299R + 0.587G + 0.114B, the
-- one `isLightSurface` reads) the three pastels are rgb(68,225,145) = 0.66, rgb(105,205,250) = 0.71
-- and rgb(175,138,250) = 0.64 -- fully saturated candy, and stacked three deep at 250 px wide they
-- were the loudest object on a screen whose only job is to show a bright village.
--
-- WHAT REPLACES THEM IS `Frost` LERPED 16% TOWARD EACH CURRENCY'S HUE -- not three pastels, and not
-- three identical Frosts either. Frost on its own (rgb 240,243,252, luminance 0.95) buys the quiet
-- and gives back three capsules nobody can tell apart at a glance, which is the exact fault the
-- single dark shell had and the one thing the pastels got right. 16% is the smallest tint that
-- survives a screenshot: the fills come out rgb(213,240,235), rgb(218,237,252) and rgb(230,226,252)
-- -- a mint-white, a sky-white and a lilac-white at luminance 0.91 / 0.91 / 0.90, i.e. within 0.05
-- of Frost itself and 0.25 lighter than what they replace. Both ends of every lerp are existing kit
-- tokens, so this puts no new colour on the screen (same move as the Journal's worn-skin rim).
--
-- INK: `Color.Ink` (rgb 48,38,66, luminance 0.17), and it is FORCED rather than chosen -- white on a
-- 0.90 fill is about 1.1:1. Measured against these three the ratio is 11.8 / 11.8 / 11.2 : 1 (WCAG,
-- linearised sRGB), up from 8.4:1 on the Mint capsule -- so the wallet got quieter and MORE legible
-- in the same edit. `Color.Ink` rather than the hand-typed rgb(46,34,66) that stood here: it is the
-- kit's named ink for a light surface and it is three points off what was already being drawn.
--
-- All three are still one wallet -- same capsule, same 5 px rim, same ink, same treatment -- and
-- because `isDarkInk` cuts at 0.45, `UITheme.Pill`'s own branch sees dark ink on a light shell and
-- drops the halo. Do not hand any of these a stroke back: a dark glyph inside a `Color.Outline`
-- halo is a blob that reads correct in every property and only fails in a capture.
--
-- THE IDENTITY MOVES ONTO THE TWO THINGS THAT SHOULD BE LOUD, which is what the row asked for: the
-- emoji (already coloured art) and the `+` disc hung on these pills ~4,900 lines down, which is
-- Green on DNA and SkyBlue on Diamonds. The capsule is chrome; the thing you press is not.
local dnaPill = UITheme.Pill(currencyStack, {
	name = "DNAPill", icon = "🧬", text = "0", layoutOrder = 1,
	size = UDim2.new(1, 0, 0, 46), maxTextSize = 34,
	shellColor = UITheme.Color.Frost:Lerp(UITheme.Color.Mint, 0.16), color = UITheme.Color.Ink,
})
hudRefs.dnaPill = dnaPill
local diamondPill = UITheme.Pill(currencyStack, {
	name = "DiamondPill", icon = "💎", text = "0", layoutOrder = 2,
	size = UDim2.new(1, 0, 0, 40), maxTextSize = 30,
	shellColor = UITheme.Color.Frost:Lerp(UITheme.Color.Aqua, 0.16), color = UITheme.Color.Ink,
})
hudRefs.diamondPill = diamondPill
local shardPill = UITheme.Pill(currencyStack, {
	name = "ShardPill", icon = "🌟", text = "0", layoutOrder = 3,
	size = UDim2.new(1, 0, 0, 40), maxTextSize = 30,
	shellColor = UITheme.Color.Frost:Lerp(UITheme.Color.Lavender, 0.16), color = UITheme.Color.Ink,
})
-- (the three pills' .Value labels used to be cached here and were never read again -- see the note
-- on the Season XP bar: this chunk is at Luau's 200-register limit and every unused local counts)

-- ===== Upgrades panel (centre screen, opened by the Shop tile) =====
local shopFrame = Instance.new("Frame")
hudRefs.shopFrame = shopFrame
shopFrame.Name = "ShopFrame"
-- 900 x 352 -> 656 x 392 (11.13).
--
-- HEIGHT: the header band is 68 tall where the bare title label was 42, and the two upgrade rows
-- keep every pixel they had rather than being squeezed to pay for it.
--
-- WIDTH: 900 was never a measurement of anything. Both rows are tiles centred by a UIListLayout,
-- so the content was 3 x 200 + 2 x 12 = 624 wide and the panel carried ~130 px of dead shell on
-- each side of it -- which is what "even margins" actually looks like when it is wrong: not a
-- crooked edge, but a board with nothing on a third of it. 624 + 16 a side = 656.
--
-- 656 -> 868 (Phase 12), because the DNA row is FOUR tiles now that Auto Collect is back on it:
-- 4 x 200 + 3 x 12 = 836, + 16 a side = 868. The tile width stays 200 on both rows, which is the
-- thing 11.13 actually bought -- one tile size the eye can learn, so three centred beneath four
-- still reads as a grid. Both rows are `1, -32` children with centred layouts, so this one number
-- moves them together and neither needed touching.
shopFrame.Size = UDim2.new(0, 868, 0, 392)
shopFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
shopFrame.AnchorPoint = Vector2.new(0.5, 0.5)
shopFrame.ZIndex = 20
shopFrame.Visible = false
shopFrame.Parent = screenGui
styleCard(shopFrame, PANEL_SHELL, UDim.new(0, 22), 5)

-- The subtitle is doing real work here, not decoration: this one panel spends TWO currencies -- the
-- top row is DNA and the bottom row is Diamonds -- and nothing on it said so. A player who had not
-- already worked that out read six tiles priced in two different marks with one word above them.
--
-- Not assigned to anything. This file is at Luau's 200-local register cap and the header needs no
-- handle: nothing on this panel rewrites its title. See the header block in UITheme.
UITheme.PanelHeader(shopFrame, {
	title = "🛒 Upgrades",
	subtitle = "Top row costs DNA, bottom row costs Diamonds -- every level is permanent",
	accent = UITheme.Color.Green,
	maxTextSize = 32,
})

-- ...and the close button is NOT built here any more. It used to be the one panel in the game that
-- shut by assigning `Visible = false`, so it vanished on a jump cut while all thirteen others
-- animated out -- and it could not simply be pointed at `animatePanel`, because that is a local
-- declared two hundred lines further down and a closure written here cannot see it. It goes through
-- `panelClose` beside `registerPanel(shopFrame)` instead, which is where every other panel gets its
-- X and is below both. That also gives this file back one top-level register.

local upgradeRow = Instance.new("Frame")
upgradeRow.Name = "UpgradeRow"
upgradeRow.Size = UDim2.new(1, -32, 0, 140)
-- 58 -> 94: the header band is top 14 + height 68 + gap 12. Written out rather than read back off
-- PanelHeader's second return value, which would cost a top-level register this file does not have.
upgradeRow.Position = UDim2.new(0, 16, 0, 94)
upgradeRow.BackgroundTransparency = 1
upgradeRow.Parent = shopFrame

local shopLayout = Instance.new("UIListLayout")
shopLayout.FillDirection = Enum.FillDirection.Horizontal
shopLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
shopLayout.Padding = UDim.new(0, 12)
shopLayout.SortOrder = Enum.SortOrder.LayoutOrder
shopLayout.Parent = upgradeRow

-- BOTH DELISTED UPGRADES ARE RESOLVED (Phase 12), in opposite directions.
--
-- Mutation Chance is GONE from `GameConfig.Upgrades` outright, not merely off this list. It was
-- left in place before because the server still read it -- deleting it would have silently
-- changed the income of every save that had bought levels. That reasoning expired when the
-- ambient ten-second mutation roll it fed was deleted: an upgrade that speeds up nothing is
-- worse than an absent one. Levels already bought are refunded at their exact geometric sum by
-- the load migration in PlayerDataService.
--
-- Auto Collect comes BACK, because the reason it was pulled was a wrong card rather than a
-- missing mechanic. The owner's objection was "there is nothing on the ground to collect" --
-- true, and the tile said so ("Passively collects DNA every second" reads as picking things up).
-- `DNAService.GetAutoCollectAmount` has always paid a real per-second share of a click, so the
-- description was rewritten to describe that instead and the tile is honest now.
local upgradeOrder = { "Speed", "Income", "Luck", "AutoCollect" }
local upgradeButtons = {}

for i, key in ipairs(upgradeOrder) do
	local def = GameConfig.Upgrades[key]
	local btn = Instance.new("TextButton")
	btn.Name = key .. "Button"
	btn.LayoutOrder = i
	-- 164 -> 200, the width the Diamond tiles below already use. Two rows of three tiles at two
	-- different widths, both centred, read as two unrelated rows that happen to share a board; at
	-- one width they line up into a grid and the panel stops needing to be 900 wide to hide it.
	btn.Size = UDim2.new(0, 200, 1, 0)
	btn.Text = ""
	btn.Parent = upgradeRow
	styleButton(btn, UITheme.Color.Gold, UDim.new(0, 16))

	-- ICON, NAME, LEVEL BADGE, COST PILL -- four pieces of furniture instead of three stacked
	-- sentences. The tile used to read "\u{1F680} Speed" / "Level 1" / "Cost: 28": three centred lines of
	-- roughly the same weight, which is a spreadsheet row rather than a button. The level is a state
	-- you glance at, so it becomes a badge in the corner; the cost is the thing you actually decide
	-- on, so it becomes a pill carrying its own currency mark; and the icon gets the room the two
	-- freed sentences leave behind.
	--
	-- The chip colour is Shade(Outline, 0.22) inline rather than a named constant, because this file
	-- is at Luau's 200-local ceiling and one more top-level name is not worth a readability win.
	-- 15.22 TOOK 8 px OFF THE ICON AND 8 OFF THE GAP UNDER THE NAME, to open a 22 px band for the
	-- effect line below. The tile is 200 x 140 and every band in it is now spoken for: icon 8..44,
	-- name 46..76, effect 78..100, cost pill 100..132. Nothing was moved that a measurement in an
	-- earlier row depended on -- the level badge is still top-right at 6 and the cost pill still
	-- sits 8 px off the bottom.
	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "Icon"
	iconLabel.Size = UDim2.new(1, -12, 0, 36)
	iconLabel.Position = UDim2.new(0.5, 0, 0, 8)
	iconLabel.AnchorPoint = Vector2.new(0.5, 0)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Text = def.emoji
	iconLabel.ZIndex = btn.ZIndex + UITheme.Z.Content
	iconLabel.Parent = btn
	themeLabel(iconLabel, 40, Color3.fromRGB(255, 255, 255))

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, -12, 0, 30)
	titleLabel.Position = UDim2.new(0.5, 0, 0, 46)
	titleLabel.AnchorPoint = Vector2.new(0.5, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.TextWrapped = true
	titleLabel.Text = def.displayName
	titleLabel.ZIndex = btn.ZIndex + UITheme.Z.Content
	titleLabel.Parent = btn
	themeLabel(titleLabel, 22, Color3.fromRGB(255, 255, 255))

	-- ===== WHAT THE LEVEL YOU OWN IS ACTUALLY DOING (15.22) =====
	--
	-- None of these four tiles has ever printed an effect. The report was about Auto Collect --
	-- *"I do not know what it collects"* -- and it was the fairest possible reading of a tile that
	-- showed an icon, a name, a level and a price and nothing else: the only way to learn what a
	-- level bought was to buy one and watch the DNA counter, which for a per-second trickle inside
	-- an income stack is not observable at all. The same is true of the other three, so all four
	-- get the line rather than singling out the one that was complained about.
	--
	-- Each tile prints ITS OWN contribution, not the whole stack, because the stack is shared -- a
	-- pet multiplier belongs to the pet, not to this upgrade -- and a tile that claimed the lot
	-- would double-count against the next tile that did the same. Auto Collect is the exception,
	-- and it is the honest one: what a player wants from it is the DNA it actually pays them per
	-- second, so it prints the server's own figure (`__autoPerSec`, stamped by the loop that pays
	-- it) rather than a fraction nobody can price.
	local effectLabel = Instance.new("TextLabel")
	effectLabel.Name = "EffectLabel"
	effectLabel.Size = UDim2.new(1, -12, 0, 22)
	effectLabel.Position = UDim2.new(0.5, 0, 0, 78)
	effectLabel.AnchorPoint = Vector2.new(0.5, 0)
	effectLabel.BackgroundTransparency = 1
	-- ONE LINE, NEVER TWO. A 22 px box floors at 14 px text (themeLabel), so a wrapped string is
	-- clipped rather than shrunk -- 15.16 in one sentence. Every string this label can hold is
	-- short by construction; TextWrapped stays off so a long one truncates visibly instead.
	effectLabel.TextWrapped = false
	effectLabel.Text = ""
	effectLabel.ZIndex = btn.ZIndex + UITheme.Z.Content
	effectLabel.Parent = btn
	themeLabel(effectLabel, 16, UITheme.Color.Cream)

	local levelBadge = Instance.new("Frame")
	levelBadge.Name = "LevelBadge"
	-- 58 -> 84 (11.13). The badge was sized for the "Lv 0" it is built with, but the refresh writes
	-- "Lv %d/%d" against `GetUpgradeMaxLevel`, which is 5 per unlocked zone and therefore 100 at the
	-- end of the strip -- "Lv 100/100" in a 50 px label clipped at the minimum text size on all three
	-- tiles. Sized against the widest string the refresh can produce, not against the placeholder.
	levelBadge.Size = UDim2.new(0, 84, 0, 26)
	levelBadge.Position = UDim2.new(1, -6, 0, 6)
	levelBadge.AnchorPoint = Vector2.new(1, 0)
	-- Z.Badge, so it clears the gloss the shell draws over its own children
	levelBadge.ZIndex = btn.ZIndex + UITheme.Z.Badge
	levelBadge.Parent = btn
	-- ===== THE CHIPS ARE WHITE NOW, NOT NEAR-BLACK (17.x) =====
	--
	-- `Shade(Color.Outline, 0.22)` is a 22%-of-near-black fill -- the darkest surface the kit can
	-- produce -- and it was the idiom for every price chip and level badge on the board. On a
	-- Gold or SkyBlue tile in a game made of candy, that reads as a hole punched through the
	-- button. Cream at luminance 0.97 with dark ink is the same chip doing the same job: it still
	-- separates the price from the tile it sits on, by being LIGHTER than its host instead of
	-- darker.
	--
	-- THE INK HAS TO FLIP IN THE SAME EDIT. These labels were Cream/White on near-black; left
	-- alone on a cream chip they would be invisible, and `themeLabel`'s luminance branch drops
	-- the near-black halo for dark ink -- which is what keeps a dark glyph from sitting inside a
	-- dark outline and rendering as a blob. Ink and stroke are one decision; never move one.
	styleCard(levelBadge, UITheme.Color.Cream, UDim.new(1, 0), 2.5)

	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "LevelLabel"
	levelLabel.Size = UDim2.new(1, -8, 1, -6)
	levelLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	levelLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text = "Lv 0"
	levelLabel.ZIndex = levelBadge.ZIndex + UITheme.Z.Content
	levelLabel.Parent = levelBadge
	themeLabel(levelLabel, 18, Color3.fromRGB(46, 34, 66))

	local costPill = Instance.new("Frame")
	costPill.Name = "CostPill"
	costPill.Size = UDim2.new(1, -20, 0, 32)
	costPill.Position = UDim2.new(0.5, 0, 1, -8)
	costPill.AnchorPoint = Vector2.new(0.5, 1)
	costPill.ZIndex = btn.ZIndex + UITheme.Z.Badge
	costPill.Parent = btn
	styleCard(costPill, UITheme.Color.Cream, UDim.new(1, 0), 2.5)

	local costLabel = Instance.new("TextLabel")
	costLabel.Name = "CostLabel"
	costLabel.Size = UDim2.new(1, -10, 1, -6)
	costLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	costLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	costLabel.BackgroundTransparency = 1
	costLabel.Text = "\u{1F9EC} " .. def.baseCost
	costLabel.ZIndex = costPill.ZIndex + UITheme.Z.Content
	costLabel.Parent = costPill
	themeLabel(costLabel, 22, Color3.fromRGB(46, 34, 66))

	btn.MouseButton1Click:Connect(function()
		Remotes.BuyUpgrade:FireServer(key)
	end)

	upgradeButtons[key] = { button = btn, levelLabel = levelLabel, costLabel = costLabel, badge = levelBadge, effectLabel = effectLabel }
end

-- ===== Diamond Upgrades row (bought with premium Diamonds, not DNA) =====
local diamondRow = Instance.new("Frame")
diamondRow.Name = "DiamondRow"
diamondRow.Size = UDim2.new(1, -32, 0, 130)
-- 94 + 140 + 12 of gap. Bottom margin is then 392 - (246 + 130) = 16, the same as the sides.
diamondRow.Position = UDim2.new(0, 16, 0, 246)
diamondRow.BackgroundTransparency = 1
diamondRow.Parent = shopFrame

local diamondLayout = Instance.new("UIListLayout")
diamondLayout.FillDirection = Enum.FillDirection.Horizontal
-- LEFT, NOT CENTRE -- this is the whole of "the two rows do not line up". The DNA row is four 200 px
-- tiles and fills its 836 exactly, so Center and Left are the same thing for it; this row is three
-- and centring insets it 106 px on each side. Three tiles under four, sharing column 1, is a grid
-- with an empty fourth cell. Three tiles floating between four is two unrelated rows.
diamondLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
diamondLayout.Padding = UDim.new(0, 12)
diamondLayout.SortOrder = Enum.SortOrder.LayoutOrder
diamondLayout.Parent = diamondRow

local diamondUpgradeOrder = { "MegaIncome", "MegaLuck", "PetSlot" }
local diamondUpgradeButtons = {}

for i, key in ipairs(diamondUpgradeOrder) do
	local def = GameConfig.DiamondUpgrades[key]
	local btn = Instance.new("TextButton")
	btn.Name = key .. "DiamondButton"
	btn.LayoutOrder = i
	btn.Size = UDim2.new(0, 200, 1, 0)
	btn.Text = ""
	btn.Parent = diamondRow
	styleButton(btn, UITheme.Color.SkyBlue, UDim.new(0, 16))

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, -12, 0, 28)
	titleLabel.Position = UDim2.new(0, 6, 0, 6)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = def.emoji .. " " .. def.displayName
	titleLabel.Parent = btn
	themeLabel(titleLabel, 22, Color3.fromRGB(255, 255, 255))

	local descLabel = Instance.new("TextLabel")
	descLabel.Size = UDim2.new(1, -12, 0, 34)
	descLabel.Position = UDim2.new(0, 6, 0, 34)
	descLabel.BackgroundTransparency = 1
	descLabel.TextWrapped = true
	descLabel.Text = def.description
	descLabel.Parent = btn
	themeLabel(descLabel, 15, UITheme.Color.Cream)

	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "LevelLabel"
	-- ===== THREE THINGS SHARE 130 PX AND THE MIDDLE ONE IS TWO LINES =====
	--
	-- Measured on the running tile: the description box is y = 34..68 (it WRAPS -- "+10% permanent
	-- income per level" is two lines and genuinely needs all 34), and the cost capsule owns 90..122.
	-- That leaves exactly 68..90 for the level, and nothing else.
	--
	-- This line has now been wrong twice in one session in opposite directions. At -56 it sat at
	-- 74..98 and ran through the new cost capsule; the fix moved it to -70, i.e. 60..84, which ran
	-- through the DESCRIPTION instead -- photographed, "Level 2" printed on top of the second line of
	-- its own explanation. -62 with a 22 px box is the only placement the three of them fit in, and
	-- there is no slack left: anything that makes the description three lines needs a taller tile.
	levelLabel.Size = UDim2.new(1, -12, 0, 22)
	levelLabel.Position = UDim2.new(0, 6, 1, -62)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text = "Level 0"
	levelLabel.Parent = btn
	themeLabel(levelLabel, 19, Color3.fromRGB(255, 255, 255))

	-- THE SAME CHIP THE DNA ROW ABOVE DRAWS, and for the reason given there: the cost is the thing
	-- the player actually decides on, so it gets its own dark capsule instead of being a fourth line
	-- of centred text. Two rows on one board that price themselves two different ways is most of why
	-- the bottom row reads as a different, lesser kind of tile. Same Shade(Outline, 0.22), same 2.5
	-- stroke, same Z.Badge so it clears the shell's gloss -- and the same 8 px off the bottom edge.
	local costPill = Instance.new("Frame")
	costPill.Name = "CostPill"
	costPill.Size = UDim2.new(1, -20, 0, 32)
	costPill.Position = UDim2.new(0.5, 0, 1, -8)
	costPill.AnchorPoint = Vector2.new(0.5, 1)
	costPill.ZIndex = btn.ZIndex + UITheme.Z.Badge
	costPill.Parent = btn
	styleCard(costPill, UITheme.Color.Cream, UDim.new(1, 0), 2.5)

	local costLabel = Instance.new("TextLabel")
	costLabel.Name = "CostLabel"
	costLabel.Size = UDim2.new(1, -10, 1, -6)
	costLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	costLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	costLabel.BackgroundTransparency = 1
	costLabel.Text = "💎 " .. def.baseCost
	costLabel.ZIndex = costPill.ZIndex + UITheme.Z.Content
	costLabel.Parent = costPill
	themeLabel(costLabel, 22, Color3.fromRGB(46, 34, 66))

	btn.MouseButton1Click:Connect(function()
		Remotes.BuyDiamondUpgrade:FireServer(key)
	end)

	diamondUpgradeButtons[key] = { button = btn, levelLabel = levelLabel, costLabel = costLabel }
end

-- ================= HUD tile columns =================
-- Two columns of chunky IconTiles (caption INSIDE the tile) plus a bottom-right quick row.
-- Only one floating panel is shown at a time -- opening one closes the others.
local togglePanels = {}
hudRefs.togglePanels = togglePanels
local function registerPanel(panel)
	-- Floating panels live at screen centre now; the tile columns own the screen edges.
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	table.insert(togglePanels, panel)

	-- STAMPED SO ANOTHER SCRIPT CAN ASK "IS A PANEL OPEN?" (15.20). `togglePanels` is a local in
	-- this file and this file cannot afford to export one, so the answer travels on the object --
	-- the same trick `columnTile` uses for `ColumnSide`/`ColumnOrder`, and for the same reason.
	-- `FirstJoin` reads it to get its tutorial banner out from over a modal; anything else that
	-- needs to yield to a panel can read it too, without this file gaining a register or a remote.
	panel:SetAttribute("HudPanel", true)

	-- THE CYAN RIM IS A PANEL'S, AND THIS IS THE ONLY PLACE THAT KNOWS WHAT A PANEL IS.
	-- Every floating panel passes through here exactly once, and nothing else does -- so the rim is
	-- decided here rather than inside styleCard, where the only thing available to decide on is the
	-- fill colour and "is it white" is true of a progress track and a 24px day pill as well.
	-- Near-white rather than an equality test, because the panels are painted from three different
	-- whites (PANEL_SHELL, PanelWhite, and the Pets panel's own 252,252,255) and a rim they share is
	-- the whole point. Anything coloured keeps the dark outline styleCard gave it.
	--
	-- AND NEITHER THE STROKE NOR THE COLOUR IS ON `panel` ANY MORE (16.4). 15.28 moved the fill,
	-- its gradient and the outline into an `InnerBody` child and left the host transparent, so both
	-- halves of this test broke at once and in silence: `panel:FindFirstChildOfClass("UIStroke")`
	-- returned **nil** for every panel in the game, and `panel.BackgroundColor3` read back Roblox's
	-- default frame grey (0.639, 0.635, 0.647) -- which is not near-white, so even a found stroke
	-- would have been left alone. Measured on the running HUD before the fix: **19 of 19 panels,
	-- zero cyan rims**, every one of them wearing the ordinary dark 5px card outline instead.
	--
	-- Asked of the surface now, not of the host: `UITheme.FaceOf` answers `InnerBody` for a modern
	-- shell and the object itself for anything older, and `BaseColor` is the attribute `applyShell`
	-- stamps on the HOST with the colour it was actually asked for -- which is the one reading that
	-- survives wherever the fill happens to live next.
	--
	-- The lip keeps its dark outline on purpose. The cyan belongs to the face of the panel; a
	-- ShadowBody recoloured to match would stop reading as a shadow and start reading as a second,
	-- misaligned rim.
	local face = UITheme.FaceOf(panel)
	local shellStroke = face and face:FindFirstChildOfClass("UIStroke")
	if shellStroke then
		local c = panel:GetAttribute("BaseColor") or face.BackgroundColor3
		if math.min(c.R, c.G, c.B) > 0.95 then
			shellStroke.Thickness = 6
			shellStroke.Color = UITheme.Color.PanelBorder
		end
	end

	-- EVERY PANEL IN THIS FILE IS SIZED IN PIXELS, AND SEVERAL ARE BIGGER THAN A PHONE.
	--
	-- The Journal is 968 x 548; a Roblox phone viewport is roughly 848 x 420. Centre-anchored, a
	-- panel that does not fit clips on all four sides at once -- including the close button in its
	-- corner and, for the panels that draw their title or tab strip ABOVE themselves, the only
	-- route to the other tab. There was no UIScale anywhere in the game and no branch on viewport
	-- size, so on a phone the game's menus were simply not reachable.
	--
	-- One UIScale per panel rather than one over the whole HUD: a UIScale scales about its object's
	-- AnchorPoint, and these are all centre-anchored, so each one shrinks about the middle of the
	-- screen and stays centred. Scaling the whole HUD instead would drag the corner tiles inward
	-- and leave a wide dead margin round the edge of the screen.
	--
	-- Measured off the AUTHORED size (Size.*.Offset), never off AbsoluteSize -- AbsoluteSize is the
	-- result of this scale, so reading it here is a feedback loop that walks the panel to nothing.
	local w, h = panel.Size.X.Offset, panel.Size.Y.Offset
	if w <= 0 or h <= 0 then return end

	local scale = Instance.new("UIScale")
	scale.Parent = panel

	local cam = workspace.CurrentCamera
	local function fit()
		if not cam then return end
		local v = cam.ViewportSize
		-- 32 of side margin, and 108 vertically: the titles and tab strips several panels hang
		-- above themselves live in that band, and a panel scaled to the exact viewport height puts
		-- them off the top.
		local fitted = math.clamp(math.min((v.X - 32) / w, (v.Y - 108) / h), 0.35, 1)
		-- PUBLISHED, because the open/close animation below has to know what "fully open" means for
		-- THIS panel. It is not 1: an 968-wide Journal on a phone is fitted to well under half size,
		-- and a pop that animated to 1.0 would quietly undo the fit and clip the panel off both
		-- edges. Every tween down there is a fraction of this number.
		panel:SetAttribute("FitScale", fitted)
		scale.Scale = fitted
	end
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	fit()
end
hudRefs.registerPanel = registerPanel

-- ===== HOW A PANEL OPENS, IN THE ONE PLACE EVERY PANEL ALREADY PASSES THROUGH =====
--
-- Panels appeared by having `.Visible` set to true. That is a jump cut, and it was the same jump
-- cut in all fourteen of them because there was no shared open path -- TweenService is required at
-- the top of this file and used for a notification fade and a purchase celebration, and nothing
-- else. So rather than animate one board on its own, this goes into `closeAllPanels`, `toggleOnly`
-- and `panelClose`: the three chokepoints every panel in the file is already routed through. All
-- of them get the motion at once and a panel added later gets it without knowing this exists.
--
-- IT TWEENS THE UISCALE registerPanel ALREADY ATTACHED, and it multiplies the fitted value rather
-- than replacing it -- see the note on FitScale above for what replacing it would cost on a phone.
--
-- ONE LIVE TWEEN PER PANEL. Opening a panel while its own close tween is still running otherwise
-- leaves two tweens writing Scale in the same frame and the panel settles wherever the loser
-- stopped. `live` is keyed by panel and lives inside the block so it costs no top-level register;
-- only the function escapes, which is the shape the Season Pass and Fusion panels already use.
local animatePanel
do
	local live = {}
	local OPEN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local SHUT = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	-- ===== A PANEL OPENS AT THE TOP, NOT WHERE IT WAS LEFT =====
	--
	-- `CanvasPosition` was written NOWHERE in this file -- the only mention of it was a
	-- GetPropertyChangedSignal subscription on the Journal -- so all ten ScrollingFrames reopened
	-- exactly where the player had last scrolled them. Open the Passes tab, scroll to the bottom,
	-- close, reopen: still at the bottom, with the header off screen and no clue anything is above.
	--
	-- Fixed HERE rather than at the ten build sites because `animatePanel` is the single chokepoint
	-- every panel opens through (toggleOnly -> closeAllPanels/animatePanel), so one call covers the
	-- panels that exist now and every one added later. Descendants rather than children: several
	-- panels put their scroll inside a tab container.
	--
	-- Declared inside this `do` block on purpose -- MainUI is at Luau's 200-local register cap and a
	-- new TOP-LEVEL local takes the whole HUD with it.
	local function rewindScrolls(panel)
		for _, d in ipairs(panel:GetDescendants()) do
			if d:IsA("ScrollingFrame") then
				d.CanvasPosition = Vector2.zero
			end
		end
	end

	function animatePanel(panel, open)
		local running = live[panel]
		if running then
			running:Cancel()
			live[panel] = nil
		end

		local scale = panel:FindFirstChildOfClass("UIScale")
		-- a panel that never went through registerPanel has no UIScale and no fitted size; it still
		-- has to open, just without the motion
		if not scale then
			if open then rewindScrolls(panel) end
			panel.Visible = open
			return
		end
		local fit = panel:GetAttribute("FitScale") or 1

		if open then
			rewindScrolls(panel)
			panel.Visible = true
			scale.Scale = fit * 0.86
			local tween = TweenService:Create(scale, OPEN, { Scale = fit })
			live[panel] = tween
			tween.Completed:Connect(function()
				live[panel] = nil
			end)
			tween:Play()
		else
			if not panel.Visible then return end
			local tween = TweenService:Create(scale, SHUT, { Scale = fit * 0.9 })
			live[panel] = tween
			tween.Completed:Connect(function(state)
				live[panel] = nil
				-- Cancelled means something reopened this panel mid-close and is now driving the
				-- scale itself. Hiding it here would blank a panel the player just asked for.
				if state == Enum.PlaybackState.Completed then
					panel.Visible = false
					scale.Scale = fit
				end
			end)
			tween:Play()
		end
	end
end

local function closeAllPanels()
	for _, p in ipairs(togglePanels) do
		animatePanel(p, false)
	end
end
local function toggleOnly(panel)
	local wasVisible = panel.Visible
	-- closeAllPanels has already played this panel's close tween if it was the open one, so the
	-- reopen is guarded rather than unconditional -- without the guard a second click would cancel
	-- its own close half-way and leave the panel sitting at 0.9 scale, visible and slightly small.
	closeAllPanels()
	if not wasVisible then
		animatePanel(panel, true)
	end
end
hudRefs.closeAllPanels = closeAllPanels
hudRefs.toggleOnly = toggleOnly

-- A teleport is not a good time to still have a menu open. Pressing Go in the Zones list starts a
-- transition that covers the screen for a second and a bit, and the list was still sitting there
-- when the cover wiped -- open over a zone the player had already left, its Go buttons still live.
--
-- The signal is the transition remote rather than the Go button, so walking into a portal gate,
-- taking the Colosseum gate or being sent home from the arena all clear the screen the same way.
-- Spawned, because ZoneService creates that remote at run time and this must not block the HUD
-- being built if it is slow to arrive.
task.spawn(function()
	local transition = Remotes:WaitForChild("ZoneTransition", 30)
	if not transition then
		return
	end
	transition.OnClientEvent:Connect(function(payload)
		if typeof(payload) == "table" and payload.phase == "start" then
			closeAllPanels()
		end
	end)
end)

local TILE_SIZE = UDim2.new(0, 82, 0, 82)
local TILE_PITCH = 96 -- 14px of clean air between tiles; captions live inside them now
local TILE_START_Y = 100 -- clears the topbar inset and the stage card above it

-- The RIGHT cluster hangs off the BOTTOM of the screen instead of the top: the Roblox
-- player list owns the top-right corner and grows with the player count, so a tile parked
-- under it there gets drawn over (that is what buried "Zones").
-- Four, not five: the Mastery tile came off this column. Stage Mastery is bought at the Upgrade
-- Emporium's diamond counter in zone 8 now, which is also where the Robux shop is sold from --
-- a permanent upgrade you walk to is a destination, where a button that is always on screen is
-- chrome. The PANEL is untouched; only its entry point moved.
-- Five since the Season Pass tile joined the column.
--
-- SEVEN, AND TWO WIDE. Gifts and Auto folded in from the old QuickRow, and at that point a single
-- stack of seven 82px tiles was 686px of screen edge -- taller than a 720p viewport can give it,
-- so the responsive pass was shrinking every tile toward its 40px floor to make them fit and the
-- captions were pinning at their minimum size. Two columns halve the height it needs, which is
-- what lets the tiles stay full size and the words stay readable. Order runs left-to-right then
-- upward, so 7 sits alone in the bottom-left.
-- EIGHT. The Audio tile (Phase 4.6) took the one empty slot in the grid -- order 8, bottom-right,
-- beside the lone order 7 that this comment used to describe. `rows` is ceil(COUNT / COLS), which is
-- 4 either way, so nothing that was already on screen moved by a pixel.
-- ...and back to EIGHT (11.18). The ninth was Eggs, and it is gone: the egg panel is opened by the
-- prompt on the podium now, which is the only place that knows WHICH egg you are looking at.
-- (That note used to claim `rows` is 4 at both 8 and 9. It is not -- ceil(9 / 2) is 5 -- which is
-- exactly why the lone ninth tile had a row of its own to sit on.)
--
-- NINE AGAIN (12.8), and the ninth is not the old Eggs tile coming back. It is one MARKET tile that
-- opens a two-button flyout, and the two buttons are the two panels that had no HUD door at all:
-- Eggs and Fusion. The reason the doors were removed still holds -- a stall you walked to should be
-- what sells you the thing -- and it cost more than it bought: fusion was reported missing outright
-- ("am I missing pet fusion, I am already on stage 4") and the egg screen is where the odds live, so
-- a player who wanted to COMPARE two eggs had to walk back to one. Both panels self-gate: the egg
-- panel already prices and prints odds from anywhere and locks only the BUY behind standing at the
-- podium, and fusion is validated on the server. So the flyout buys the browsing and gives away
-- none of the walking. `rows` is 5 now; the responsive pass at the bottom of the file works that out
-- from the tiles it finds, so nothing here has to be told about it.
-- EIGHT AGAIN (15.25 deleted the Market tile, this constant was left behind at 9). It only decides
-- the AUTHORED position -- the layout pass at the end of the file recounts the tiles it actually
-- finds -- so the cost of the stale 9 was one frame of the whole right cluster sitting a pitch high
-- before the first layout ran. That is exactly the flash the comment above says the authored
-- position exists to prevent.
local RIGHT_COUNT = 8
local RIGHT_COLS = 2
hudRefs.RIGHT_COLS = RIGHT_COLS
local RIGHT_BOTTOM_Y = 46
local PANEL_ANCHOR = UDim2.new(0.5, 0, 0.5, 0)
hudRefs.PANEL_ANCHOR = PANEL_ANCHOR

local function columnTile(side, order, emoji, caption, color, badge, badgeColor)
	local opts = {
		name = caption .. "Button",
		icon = emoji,
		caption = caption,
		color = color,
		size = TILE_SIZE,
		radius = 20,
		badge = badge,
		badgeColor = badgeColor,
	}
	if side == "L" then
		-- TWO WIDE (16.2). This column was a single file of five tiles; it is a 2x2 grid of four now.
		-- Trade came off it entirely (see the note under this function), and four buttons in a block
		-- are half the height of four in a ladder -- which is what lets them hold their authored 82px
		-- on a short viewport instead of being shrunk toward the 40px floor by the layout pass.
		--
		-- The 2 is written literally rather than hoisted into a constant beside RIGHT_COLS on purpose:
		-- this file's top level is at Luau's 200-register ceiling and one more top-level local silently
		-- deletes the entire HUD. The layout pass at the bottom of the file carries the same 2 in WIDTH.
		local lcol = (order - 1) % 2
		local lrow = math.floor((order - 1) / 2)
		opts.position = UDim2.new(0, 20 + lcol * TILE_PITCH, 0, TILE_START_Y + lrow * TILE_PITCH)
		opts.anchorPoint = Vector2.new(0, 0)
	else
		-- The authored position, for the one frame before the layout pass at the bottom of the file
		-- runs. Same grid arithmetic it uses, kept here so the cluster never flashes as a stack.
		-- AnchorPoint is (1,1), i.e. the tile's bottom-RIGHT corner, so column 0 of the pair steps
		-- LEFT by one pitch and the last row sits hard against RIGHT_BOTTOM_Y.
		local col = (order - 1) % RIGHT_COLS
		local row = math.floor((order - 1) / RIGHT_COLS)
		local rows = math.ceil(RIGHT_COUNT / RIGHT_COLS)
		opts.position = UDim2.new(
			1, -20 - (RIGHT_COLS - 1 - col) * TILE_PITCH,
			1, -(RIGHT_BOTTOM_Y + (rows - 1 - row) * TILE_PITCH))
		opts.anchorPoint = Vector2.new(1, 1)
	end
	local tile = UITheme.IconTile(screenGui, opts)
	-- Stamped rather than collected into a table, because this file is at Luau's 200-local ceiling
	-- and a registry would cost one of the last registers. The responsive pass at the bottom of
	-- the file finds the columns by these two attributes.
	tile:SetAttribute("ColumnSide", side)
	tile:SetAttribute("ColumnOrder", order)
	return tile
end
hudRefs.columnTile = columnTile

-- LEFT column
-- THE INVENTORY TILE IS GONE, and so is the Potion quick tile in the bottom row. The panel itself
-- is left standing and still refreshes -- every call site is unchanged -- it simply has nothing
-- opening it any more. Removing the tile rather than the panel is deliberate: the potion counters
-- it draws are read by the shop and the reward flow, and unpicking those to delete a screen nobody
-- can reach any more would be a much larger change than the one that was asked for.
-- The three tiles below it moved up a slot; leaving Shop at order 2 would have left a hole at the
-- top of the column, which reads as a missing button rather than as a removed one.
-- No badge on Shop: every upgrade in it costs DNA or Diamonds, so "FREE!" was a lie.
local shopToggleButton = columnTile("L", 1, "🛒", "Shop", UITheme.Color.Sunny)
-- ONE BUTTON, TWO SCREENS. Removing the Inventory and Potion tiles left the potions with nothing
-- opening them at all -- and potions are a consumable the player pays for, so that was a regression
-- rather than a simplification. Instead of putting a fourth tile back, the two panels that already
-- existed became the two TABS of this one: it opens Pets, and Potions is one click away.
local inventoryButton  = columnTile("L", 2, "\u{1F392}", "Inventory", UITheme.Color.Bubblegum)
local rebirthButton    = columnTile("L", 3, "♻️", "Rebirth", UITheme.Color.Lavender)
hudRefs.rebirthButton = rebirthButton
-- THE TRADE TILE IS GONE (16.2), and the feature is not.
--
-- Trading is never something you browse INTO -- it is something you do TO one specific person -- so
-- the door moved onto the person: click any other player in the world and a small card opens over
-- them with their headshot, their name, how far away they are and a Trade button (see the trade
-- block at the bottom of this file). A permanent tile spent a fifth of the left edge on a feature
-- that means nothing at all until somebody else is standing next to you, and it asked the player to
-- pick a name off a list when they were already looking straight at the person they meant.
--
-- Four tiles left, and they are a 2x2 block now rather than a ladder -- see the L branch of
-- columnTile above and WIDTH in the layout pass at the bottom of this file.
--
-- The Auras tile (15.27) IS BUILT HERE AND HELD BY NOBODY, and both halves of that are deliberate.
-- Here, because the responsive column pass at the bottom of this file collects its tiles ONCE, by
-- walking screenGui's children when it runs -- a tile created after it is never laid out at all and
-- keeps its authored pixel position on every viewport. Held by nobody, because this file is at
-- Luau's 200-local ceiling and one more top-level local silently deletes the whole HUD; the code
-- that needs it finds it back as `screenGui.AurasButton`, the name columnTile stamps on it.
columnTile("L", 4, "\u{1F9EC}", "Auras", UITheme.Color.Purple)

-- RIGHT CLUSTER (right-aligned), two tiles wide and filling upward from the bottom-right corner --
-- see RIGHT_COUNT and the layout pass at the end of the file. Order runs left-to-right then up:
-- 1,2 are the top row, 7,8 the bottom. Order 5 is the Season Pass tile, which is built inside its
-- own immediately-called block further down -- it does not appear in this list, and assuming a gap
-- here because a slot is missing from THIS run of columnTile calls is how the Audio tile initially
-- landed on top of it. Check the live column, not this list.
local journalButton = columnTile("R", 1, "\u{1F4D2}", "Journal", UITheme.Color.Lavender)
local zonesButton  = columnTile("R", 2, "\u{1F5FA}\u{FE0F}", "Zones", UITheme.Color.Aqua)
local rewardButton = columnTile("R", 3, "\u{1F381}", "Daily", UITheme.Color.Peach, "NEW!", UITheme.Color.Coral)
-- The "NEW!" flag is a claimable-today signal, not decoration: updateRewardPanel hides it
-- the moment the day is claimed and shows it again when the next day unlocks.
local rewardBadge = rewardButton:FindFirstChild("Badge")
local robuxButton  = columnTile("R", 4, "\u{1F6CD}\u{FE0F}", "Robux", UITheme.Color.Mint)

-- The Mastery tile used to sit at order 2 here. Its badge -- shown while at least one Mastery was
-- both reached and affordable -- went with it; `masteryBadge` stays declared and nil so the
-- refresh that sets it (which is already nil-guarded) needs no change.
local masteryBadge = nil

-- GIFTS AND AUTO ARE PART OF THE CLUSTER NOW, not a separate strip.
--
-- They used to be their own 260x68 Frame with its own UIListLayout pinned at (1, -20, 1, -42), and
-- being outside the column registry had three consequences that all showed: they never took part
-- in the responsive pass, so they stayed 68px while the tiles above them shrank to fit the screen;
-- they used a 10px list padding against the column's 14, so nothing lined up; and the column above
-- had to reserve 122px of dead space at the bottom to clear them.
--
-- As ordinary columnTiles at orders 6 and 7 they inherit the grid, the gap, the sizing and the
-- ColumnSide/ColumnOrder registry the layout pass reads -- one system instead of two. The whole
-- QuickRow frame, its layout and its builder are gone, which also gives three top-level registers
-- back to a file that has about sixteen to spare.
local playtimeButton = columnTile("R", 6, "⏰", "Gifts", UITheme.Color.Peach)

-- AUTO-ATTACK toggle. The state itself lives on the player as an attribute, not in either script:
-- CombatClient does the fighting and also toggles it off the T key, this tile draws it, and the
-- attribute is the single place both of them read. Either side can flip it and the other follows.
-- Caption starts as "Auto" and refreshAutoTile immediately rewrites it to Auto ON / Auto OFF.
local autoAttackButton = columnTile("R", 7, "\u{2694}\u{FE0F}", "Auto", UITheme.Color.Locked)

local function refreshAutoTile()
	local on = player:GetAttribute("AutoAttack") == true
	-- colour AND caption, not just one: a tile that only changes hue is a guess, and this is a
	-- setting a player has to be able to check at a glance mid-fight
	UITheme.SetColor(autoAttackButton, on and UITheme.Color.Green or UITheme.Color.Locked)
	local body = autoAttackButton:FindFirstChild("Body")
	local caption = body and body:FindFirstChild("Caption")
	if caption then
		caption.Text = on and "Auto ON" or "Auto OFF"
	end
end

autoAttackButton.MouseButton1Click:Connect(function()
	player:SetAttribute("AutoAttack", player:GetAttribute("AutoAttack") ~= true)
end)
player:GetAttributeChangedSignal("AutoAttack"):Connect(refreshAutoTile)
refreshAutoTile()

registerPanel(shopFrame)
shopToggleButton.MouseButton1Click:Connect(function()
	toggleOnly(shopFrame)
end)

-- shared: red X close button in the top-right of a floating panel
local function panelClose(panel)
	-- (declared below its first caller's panel on purpose -- see the Upgrades panel, whose X is
	-- attached at the bottom of this block because `animatePanel` does not exist further up)
	local btn = UITheme.Button(panel, {
		name = "Close",
		text = "\u{2715}",
		color = UITheme.Color.Red,
		size = UDim2.new(0, 44, 0, 44),
		position = UDim2.new(1, -12, 0, 8),
		anchorPoint = Vector2.new(1, 0),
		radius = UDim.new(1, 0),
		maxTextSize = 26,
		zIndex = panel.ZIndex + UITheme.Z.Badge + 2,
	})
	btn.MouseButton1Click:Connect(function()
		animatePanel(panel, false)
	end)
	return btn
end
hudRefs.panelClose = panelClose

-- The Upgrades panel is built ~500 lines above this, before `animatePanel` and `panelClose` exist,
-- so its X is attached here -- the first thing that could give it one. It is the whole of 11.13's
-- "the main shop is the only panel that closes by setting Visible = false".
panelClose(shopFrame)

-- ===== Zones panel =====
local zonesPanel = Instance.new("Frame")
zonesPanel.Name = "ZonesPanel"
zonesPanel.Size = UDim2.new(0, 430, 0, 480)
zonesPanel.Position = PANEL_ANCHOR
zonesPanel.ZIndex = 20
zonesPanel.Visible = false
zonesPanel.Parent = screenGui
styleCard(zonesPanel, PANEL_SHELL, UDim.new(0, 22), 5)
registerPanel(zonesPanel)
panelClose(zonesPanel)

-- Converted to the shared accent band (17.x). It was a bare 32 px label at (18, 10) with the list
-- starting at 58 and a 14 px margin -- one of nine panels still doing that, each with its own
-- content top (56 to 106) and its own margin (14 / 18 / 20 / 22). The band is what makes them read
-- as one application; see the geometry note in UITheme.PanelHeader. Aqua matches the Zones tile in
-- the HUD, which is the button that opens this -- a panel whose accent disagrees with the tile that
-- opened it reads as a different screen.
UITheme.PanelHeader(zonesPanel, {
	title = "🗺️ Zones",
	subtitle = "Later zones pay more income",
	accent = UITheme.Color.Aqua,
})

local zonesScroll = Instance.new("ScrollingFrame")
zonesScroll.Name = "ZonesScroll"
-- 94 is the band's bottom edge (top 14 + height 68 + gap 12), written out rather than captured --
-- this file is at Luau's 200-local cap. -110 is that 94 plus a matching 16 px bottom margin.
zonesScroll.Size = UDim2.new(1, -32, 1, -110)
zonesScroll.Position = UDim2.new(0, 16, 0, 94)
zonesScroll.BackgroundTransparency = 1
zonesScroll.BorderSizePixel = 0
zonesScroll.ScrollBarThickness = 6
zonesScroll.CanvasSize = UDim2.new(0, 0, 0, #GameConfig.Zones * 74)
zonesScroll.Parent = zonesPanel

local zonesListLayout = Instance.new("UIListLayout")
zonesListLayout.Padding = UDim.new(0, 6)
zonesListLayout.SortOrder = Enum.SortOrder.LayoutOrder
zonesListLayout.Parent = zonesScroll

local zoneRows = {}

for i, zone in ipairs(GameConfig.Zones) do
	local row = Instance.new("Frame")
	row.Name = zone.key
	row.LayoutOrder = i
	row.Size = UDim2.new(1, 0, 0, 68)
	row.Parent = zonesScroll
	-- ===== PASTEL THE ZONE, DO NOT PAINT IT RAW (17.x) =====
	--
	-- `zone.accentColor` is the zone's WORLD colour -- it paints terrain, and terrain is allowed to
	-- be near-black (Forest is a deep pine, Ocean a midnight navy, Moon a dead grey). Handed
	-- straight to a UI row it made a list of twenty near-black bars on a white panel, which is the
	-- thing this pass exists to remove.
	--
	-- Blended 62% toward white, the hue survives -- Forest still reads green, Volcano still reads
	-- red, and the twenty are still tellable apart -- while every row lands in the same light band
	-- as the panel it sits on. This is a UI decision made in the UI; GameConfig keeps the true
	-- colour for the world, which is the only place it is correct.
	styleCard(row, zone.accentColor:Lerp(UITheme.Color.White, 0.62), UDim.new(0, 14), 4)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(0.62, 0, 0, 30)
	nameLabel.Position = UDim2.new(0, 12, 0, 6)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = zone.emoji .. " " .. zone.name
	nameLabel.Parent = row
	themeLabel(nameLabel, 24, Color3.fromRGB(46, 34, 66))
	-- DRAW THE ZONE, DO NOT SPELL IT (10.20). All twenty zones have art now, and this row was the
	-- single biggest place still rendering a platform emoji -- twenty of them, stacked, in one
	-- scrolling list, which is exactly where four different emoji fonts are most obvious.
	-- `IconifyLabel` strips the leading glyph and puts the drawing where it was; it returns false
	-- and leaves the label alone for anything unmapped, so this is safe on a zone added later.
	UITheme.IconifyLabel(nameLabel)

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Size = UDim2.new(0.62, 0, 0, 22)
	statusLabel.Position = UDim2.new(0, 12, 1, -30)
	statusLabel.BackgroundTransparency = 1
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.Text = "Locked"
	statusLabel.Parent = row
	-- dark ink, because the row under it is pastel now -- and themeLabel drops the near-black halo
	-- on that branch, which is the half that must never be left behind
	themeLabel(statusLabel, 17, Color3.fromRGB(88, 78, 112))

	local goButton = Instance.new("TextButton")
	goButton.Name = "GoButton"
	goButton.Size = UDim2.new(0, 96, 0, 46)
	goButton.Position = UDim2.new(1, -108, 0.5, -23)
	goButton.Text = "\u{1F512}"
	goButton.Parent = row
	styleButton(goButton, UITheme.Color.Locked, UDim.new(1, 0))
	-- THE PADLOCK IS DRAWN, THE WORD "Go" IS NOT (10.20). A locked row shows an icon and an
	-- unlocked one shows a word, so this button carries both an ImageLabel and its own text and
	-- shows exactly one of them at a time -- see `UITheme.ShowIconOrText`. Built here so
	-- the slot exists before the first refresh; a slot created lazily would leave the very first
	-- draw of a fresh save showing the glyph.
	do
		local slot = UITheme.IconSlot(goButton, {
			name = "LockIcon", icon = "\u{1F512}",
			size = UDim2.new(0, 26, 0, 26), position = UDim2.new(0.5, 0, 0.5, 0),
			anchorPoint = Vector2.new(0.5, 0.5), zIndex = goButton.ZIndex + UITheme.Z.Content,
		})
		if slot then goButton.Text = "" end
	end

	goButton.MouseButton1Click:Connect(function()
		Remotes.TeleportToZone:FireServer(zone.key)
	end)

	zoneRows[zone.key] = { statusLabel = statusLabel, goButton = goButton }
	zonesScroll.CanvasSize = UDim2.new(0, 0, 0, i * 74)
end

zonesButton.MouseButton1Click:Connect(function()
	toggleOnly(zonesPanel)
end)

-- ===== Stage Mastery panel =====
-- One permanent Diamond purchase per evolution stage. Laid out as a checklist rather than a
-- shelf of upgrades: every row is worth the same, only the price differs, so what the player is
-- reading is "which ones do I still owe" -- see the STAGE MASTERY block in GameConfig.
local masteryPanel = Instance.new("Frame")
masteryPanel.Name = "MasteryPanel"
masteryPanel.Size = UDim2.new(0, 460, 0, 510)
masteryPanel.Position = PANEL_ANCHOR
masteryPanel.ZIndex = 20
masteryPanel.Visible = false
masteryPanel.Parent = screenGui
styleCard(masteryPanel, PANEL_SHELL, UDim.new(0, 22), 5)
registerPanel(masteryPanel)
panelClose(masteryPanel)

-- The subtitle says what the panel is FOR, which the twenty rows below never do: they are priced in
-- Diamonds and gated on a stage, and both facts used to have to be inferred from a locked row.
UITheme.PanelHeader(masteryPanel, {
	title = "⭐ Stage Mastery",
	-- Kept short deliberately: this is the narrowest of the four headers (460 wide against the
	-- Upgrades panel's 900), and the first draft clipped at the minimum text size.
	subtitle = "One permanent buy per stage -- rebirth never takes it",
	accent = UITheme.Color.Gold,
	maxTextSize = 30,
})

-- Running total, so the player can see what the whole collection is currently worth without
-- adding up twenty rows themselves -- AND HOW FAR ALONG IT IS (11.16).
--
-- It was a flat gold card carrying "7/20 mastered — +21% Power, ...". The words were already
-- right; what a card cannot do is answer "how much of this is left" without the reader doing the
-- division. This is the one place in the panel where twenty rows collapse into a single ratio, so
-- it is the one place a bar belongs -- a bar per ROW would be a two-state bar, which is a tick box
-- drawn the long way.
--
-- Same size, same position, same colour, same text: the card became the bar's background rather
-- than being replaced by one, so nothing below it moved. 18/36 -> 16/32 on the margins was 11.13's
-- "even margins" half and still holds.
local masterySummaryFill, masterySummaryLabel = select(2, UITheme.ProgressBar(masteryPanel, {
	name = "SummaryCard",
	size = UDim2.new(1, -32, 0, 40),
	position = UDim2.new(0, 16, 0, 94),
	color = UITheme.Color.Gold,
	radius = UITheme.Radius.Pill,
	thickness = 3,
	text = "0 / " .. #GameConfig.Stages .. " mastered",
	maxTextSize = 20,
	zIndex = masteryPanel.ZIndex + UITheme.Z.Content,
}))

local masteryScroll = Instance.new("ScrollingFrame")
masteryScroll.Name = "MasteryScroll"
-- header 14+68, gap 12, summary 40, gap 12 => 146; bottom margin 16, so the scroll is 162 short.
masteryScroll.Size = UDim2.new(1, -32, 1, -162)
masteryScroll.Position = UDim2.new(0, 16, 0, 146)
masteryScroll.BackgroundTransparency = 1
masteryScroll.BorderSizePixel = 0
masteryScroll.ScrollBarThickness = 6
masteryScroll.CanvasSize = UDim2.new(0, 0, 0, #GameConfig.Stages * 74)
masteryScroll.Parent = masteryPanel

local masteryListLayout = Instance.new("UIListLayout")
masteryListLayout.Padding = UDim.new(0, 6)
masteryListLayout.SortOrder = Enum.SortOrder.LayoutOrder
masteryListLayout.Parent = masteryScroll

local masteryRows = {}

for i, stage in ipairs(GameConfig.Stages) do
	local row = Instance.new("Frame")
	row.Name = "Stage" .. i
	row.LayoutOrder = i
	row.Size = UDim2.new(1, 0, 0, 68)
	row.Parent = masteryScroll
	local rowStroke = styleCard(row, stage.color, UDim.new(0, 14), 4)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(0.66, 0, 0, 28)
	nameLabel.Position = UDim2.new(0, 12, 0, 6)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = stage.emoji .. " " .. stage.name
	nameLabel.Parent = row
	themeLabel(nameLabel, 23)

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Size = UDim2.new(0.66, 0, 0, 24)
	statusLabel.Position = UDim2.new(0, 12, 1, -30)
	statusLabel.BackgroundTransparency = 1
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.Text = "Locked"
	statusLabel.Parent = row
	themeLabel(statusLabel, 17, UITheme.Color.Cream)

	local buyButton = Instance.new("TextButton")
	buyButton.Name = "BuyButton"
	buyButton.Size = UDim2.new(0, 108, 0, 46)
	buyButton.Position = UDim2.new(1, -120, 0.5, -23)
	buyButton.Text = "🔒"
	buyButton.Parent = row
	styleButton(buyButton, UITheme.Color.Locked, UDim.new(1, 0))

	buyButton.MouseButton1Click:Connect(function()
		Remotes.BuyStageMastery:FireServer(i)
	end)

	-- `nameLabel` rides along since 18.6: the row fill is repainted three different ways by the
	-- refresh below and one of them is now a light surface, so the caption's ink is state, not a
	-- build-time decision.
	masteryRows[i] = { row = row, nameLabel = nameLabel, statusLabel = statusLabel, buyButton = buyButton, stroke = rowStroke }
	masteryScroll.CanvasSize = UDim2.new(0, 0, 0, i * 74)
end

-- The Mastery panel is opened from the Upgrade Emporium's diamond counter -- see the
-- ProximityPrompt handler at the bottom of this script. Nothing on the HUD opens it any more.

local function refreshMasteryPanel()
	if not currentData then return end
	local data = currentData
	local cfg = GameConfig.StageMastery
	local bonus = GameConfig.GetStageMasteryBonus(data)
	local diamonds = data.Diamonds or 0
	local reached = data.StageIndex or 1
	local effect = string.format("+%d%% Power · +%.1f Speed · +%d%% HP", cfg.damagePct, cfg.walkSpeed, cfg.healthPct)

	masterySummaryLabel.Text = string.format("%d/%d mastered — +%d%% Power, +%.1f Speed, +%d%% HP",
		bonus.owned, #GameConfig.Stages,
		math.floor((bonus.damageMult - 1) * 100 + 0.5), bonus.walkSpeed,
		math.floor((bonus.healthMult - 1) * 100 + 0.5))
	-- the same ratio the words state, drawn (11.16). Written as a Scale so it stays correct when the
	-- responsive UIScale shrinks the panel -- an offset width here would be right on one screen only.
	masterySummaryFill.Size = UDim2.new(bonus.owned / math.max(1, #GameConfig.Stages), 0, 1, 0)

	local anyAffordable = false

	for i, stage in ipairs(GameConfig.Stages) do
		local refs = masteryRows[i]
		if refs then
			local owned = GameConfig.HasStageMastery(data, i)
			local cost = GameConfig.GetStageMasteryCost(i)

			if owned then
				refs.statusLabel.Text = "✓ Mastered"
				refs.buyButton.Text = "✓"
				setButtonColor(refs.buyButton, UITheme.Color.Green)
				refs.stroke.Color = OUTLINE_COLOR
				setButtonColor(refs.row, UITheme.Color.Locked)
			elseif i > reached then
				refs.statusLabel.Text = "Reach " .. stage.name .. " to unlock"
				refs.buyButton.Text = "🔒"
				setButtonColor(refs.buyButton, UITheme.Color.Locked)
				refs.stroke.Color = OUTLINE_COLOR
				setButtonColor(refs.row, UITheme.Color.Locked)
			else
				local affordable = diamonds >= cost
				anyAffordable = anyAffordable or affordable
				refs.statusLabel.Text = effect
				refs.buyButton.Text = "💎 " .. cost
				-- grey, not red: an unaffordable row is "not yet", and a wall of red buttons on a
				-- fresh save reads as twenty things being broken
				setButtonColor(refs.buyButton, affordable and UITheme.Color.Green or UITheme.Color.Locked)
				-- the bright rim is the same "you can act on this now" cue the Daily board uses
				refs.stroke.Color = affordable and READY_RIM or OUTLINE_COLOR
				setButtonColor(refs.row, stage.color)
			end
		end
	end

	if masteryBadge then
		masteryBadge.Visible = anyAffordable
	end
end

-- ===== Pets panel =====
--
-- BUILT AGAINST A REFERENCE SCREENSHOT, not against the rest of this HUD. The player asked for the
-- pet inventory to look like the one in Duck Evolution, and that panel is a WHITE board with a
-- cyan rim, a grid of grey cards, and each pet's art hanging off the top-left corner of its own
-- card with a green tick on it when equipped. Every other panel in this file is dark; this one is
-- deliberately not, so its labels pass explicit dark colours to themeLabel (which otherwise
-- force-brightens anything dark, on the assumption of a dark shell -- see the luminance test there).
--
-- The palette is written out at each use rather than hoisted into constants: this chunk is at
-- Luau's 200-register ceiling and five more top-level locals is exactly the kind of thing that has
-- already broken the whole script once.
--   white board 252,252,255 | cyan rim 64,196,255 | card 226,228,236 | inset 240,242,248
--   name text 122,126,140   | stat text 88,92,104 | tick/number green 62,196,86
local petsPanel = Instance.new("Frame")
hudRefs.petsPanel = petsPanel
petsPanel.Name = "PetsPanel"
-- landscape, like the reference -- a grid of cards needs width, and the old 490 fitted two
petsPanel.Size = UDim2.new(0, 772, 0, 588)
petsPanel.Position = PANEL_ANCHOR
petsPanel.ZIndex = 20
petsPanel.Visible = false
petsPanel.Parent = screenGui
styleCard(petsPanel, Color3.fromRGB(252, 252, 255), UDim.new(0, 20), 6)
registerPanel(petsPanel)
panelClose(petsPanel)
-- styleCard paints the standard dark outline on everything; the reference rim is a bright cyan.
-- Reached through the children rather than through a local for the register reason above.
for _, s in ipairs(petsPanel:GetChildren()) do
	if s:IsA("UIStroke") then s.Color = Color3.fromRGB(64, 196, 255) end
end

-- ===== THE TITLE IS INSIDE THE BOARD NOW (17.x) =====
--
-- It sat at y = -30 -- half outside, ON the world -- and that was a real decision copied from the
-- reference art, defended in the comment that used to be here. Its pair, the Pets/Potions tab strip,
-- sat outside with it at -34. The Potions half of that pair converted to the shared accent band this
-- session, and a tab strip whose two halves disagree about which side of the card they live on is
-- worse than either choice made consistently. So Pets follows.
--
-- The action row at the BOTTOM edge stays half in and half out: that one is anchored to the bottom
-- (scale 1) and reads as a bar clipped to the board, not as a label floating on scenery.
--
-- Bubblegum, matching the Pets tile. Scroll moved 80 -> 144 (band 94 + the 38 px tab row + 12) and
-- the board grew by the same 64, so the bottom bar keeps its gap.
UITheme.PanelHeader(petsPanel, {
	title = "🐾 Pets!",
	subtitle = "Your equipped pets boost every drop",
	accent = UITheme.Color.Bubblegum,
})

-- Bulk actions. A collection this size is not managed one row at a time: by the time a player is
-- three zones in they own dozens of pets, and "which three are my best" is a question the game
-- should answer, not something to solve by scrolling and comparing numbers by eye.
-- Fusion is NOT one of them, and that is still true after 12.8: the button that opens it lives in
-- the Market flyout in the tile cluster, not on this panel. Two doors, both deliberate -- the Pet
-- Fusion Lab counter in the world (see the ShopPanel handler at the bottom of this script) and the
-- flyout. What is NOT wanted is a third one buried inside the pets screen, where it reads as a bulk
-- action on the collection rather than as a machine you visit.
--
-- WHY THIS BLOCK IS WRAPPED IN `do ... end`, AND WHY WHAT ESCAPES IT GOES IN ONE TABLE:
-- this file's top level is a single Luau function, and Luau gives a function 200 registers. It
-- sits at ~190 named top-level locals. Seven more -- a frame, a layout, a builder fn, three
-- buttons and a forward declaration -- pushed it over, and the WHOLE SCRIPT stopped compiling:
-- not a broken panel, no HUD at all, every side button gone at once. Locals declared inside a
-- `do` block release their registers at `end`, so a block costs nothing lasting. Anything that
-- must outlive it goes in `hudRefs` -- one register no matter how many entries it holds. New UI
-- follows this shape, or lives in its own module.

-- ===== Bottom-left: ACTIVE POTION TIMERS =====================================================
-- Nothing in the game said how long a boost had left. You drank a bottle, it disappeared into the
-- save, and some minutes later the multiplier quietly stopped -- so the counter is the only place
-- the effect is visible at all once the toast has gone.
--
-- One row per potion KIND, not per bottle. A kind is the unit a boost is tracked in: drinking a
-- second bottle of the same kind EXTENDS the timer instead of stacking a second effect (see
-- PotionService.applyBoost), so three rows is the true maximum and they can all be built once and
-- shown or hidden rather than created per potion.
--
-- BUILT INSIDE AN IMMEDIATELY-CALLED FUNCTION, for the register reason set out above.
-- MOVED OUT (18.9) to `ReplicatedStorage.Modules.HUD.PotionTimers` -- 644 lines, unchanged.
require(RS.Modules:WaitForChild("HUD"):WaitForChild("PotionTimers"))(hudRefs)

-- An IMMEDIATELY-CALLED FUNCTION, not a `do` block. The note above is half right: a block does
-- release its registers at `end`, but Luau measures the PEAK, and the peak inside a block is every
-- top-level local still in scope plus everything the block declares. A function body gets its own
-- 200 and is the only thing that actually buys headroom -- see the Season Pass block, which had
-- the same comment on it and still broke the script.
-- MOVED OUT (18.9) to `ReplicatedStorage.Modules.HUD.PetsActions` -- 187 lines, unchanged.
require(RS.Modules:WaitForChild("HUD"):WaitForChild("PetsActions"))(hudRefs)

-- Owned pets scroll list
-- themeLabel wraps every label in a thick dark outline, which is right on a dark panel and wrong
-- on this white one -- the reference's card text is plain grey. Kills the outline after theming.
local function flatText(label)
	for _, s in ipairs(label:GetChildren()) do
		if s:IsA("UIStroke") then s.Transparency = 1 end
	end
	return label
end
hudRefs.flatText = flatText

local petsScroll = Instance.new("ScrollingFrame")
petsScroll.Name = "PetsScroll"
-- clear of the title above and the action bar sitting on the bottom edge
-- 26 px lower than it was, and 26 shorter: 13.4's odds strip sits in the gap. The action bar on the
-- bottom edge is unmoved, so only the top of the scroll changed.
petsScroll.Size = UDim2.new(1, -44, 1, -218)
petsScroll.Position = UDim2.new(0, 22, 0, 144)
petsScroll.BackgroundTransparency = 1
petsScroll.BorderSizePixel = 0
petsScroll.ScrollBarThickness = 6
petsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
petsScroll.Parent = petsPanel

-- A GRID, NOT A LIST. The reference lays pets out as cards left-to-right and this is the single
-- biggest difference from the old panel: a full-width row per pet fits six on a screen, and a
-- player three zones in owns dozens. The cell is taller and wider than the card inside it because
-- the pet's art hangs off the card's top-left corner and has to have somewhere to hang.
-- 3 columns: 3 * 232 + 2 * 10 = 716, inside the 728 the scroll has.
do
	local grid = Instance.new("UIGridLayout")
	-- 156 tall since 13.3 (was 126). THREE numbers move together for one decision: this, the
	-- `cell.Size` in refreshPetsPanel, and the row height in the CanvasSize line at the end of it.
	-- A grid cell shorter than the frame inside it silently overlaps the row below.
	grid.CellSize = UDim2.new(0, 232, 0, 156)
	grid.CellPadding = UDim2.new(0, 10, 0, 12)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = petsScroll
end

-- Parented to the PANEL, not the scroll: inside a UIGridLayout it would be laid out as a cell and
-- push the first pet out of place.
local petsEmptyLabel = Instance.new("TextLabel")
petsEmptyLabel.Name = "EmptyLabel"
petsEmptyLabel.Size = UDim2.new(1, -60, 0, 60)
petsEmptyLabel.Position = UDim2.new(0, 30, 0, 120)
petsEmptyLabel.BackgroundTransparency = 1
petsEmptyLabel.TextWrapped = true
petsEmptyLabel.ZIndex = petsPanel.ZIndex + UITheme.Z.Content
petsEmptyLabel.Text = "No pets yet — visit a Pet Shop in any zone to buy an egg!"
petsEmptyLabel.Parent = petsPanel
flatText(themeLabel(petsEmptyLabel, 24, Color3.fromRGB(150, 154, 168)))

inventoryButton.MouseButton1Click:Connect(function()
	toggleOnly(petsPanel)
end)

local function petDisplayInfo(petKey)
	for _, p in ipairs(GameConfig.Pets) do
		if p.key == petKey then return p end
	end
	return { name = petKey, emoji = "❓", rarity = "Common" }
end
hudRefs.petDisplayInfo = petDisplayInfo

-- Rarity and tier are two different axes and a pet row has to show both. RichText is the only
-- way to give one label two colours, so the rarity word carries its own colour inline while
-- themeLabel colours the rest of the line by tier.
local function colorTag(text, c)
	return string.format('<font color="#%02X%02X%02X">%s</font>',
		math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255), text)
end
hudRefs.colorTag = colorTag

-- ===== THE ODDS, WHERE THE MONEY IS SPENT (13.4) =====
--
-- Built from `GameConfig.Enchants` itself, never typed out: the weights sum to 100 by contract
-- (`AssertEnchantWeights` warns if they stop), so a weight IS a percentage and this line cannot
-- drift from what `RollEnchant` actually does. Every rung is printed in its own colour, the same
-- colour its chip wears on the card, so the strip doubles as the legend for the grid under it.
--
-- ONE STRIP FOR THE WHOLE PANEL rather than a line per card: the odds are a property of the ladder,
-- not of the pet, and thirty copies of the same sentence is how a grid becomes unreadable.
do
	local odds = Instance.new("TextLabel")
	odds.Name = "EnchantOdds"
	-- ===== IT SHARES THE TAB ROW NOW (17.x) =====
	--
	-- y = 54 put it INSIDE the accent band the moment this panel got one -- photographed printing
	-- straight through the subtitle, two sentences in the same 22 px. The tab strip is right-aligned
	-- in the 94..132 row and only 262 px of the panel's 772, so the whole left half of that row was
	-- empty and this is exactly the kind of quiet, always-true line that belongs in it.
	--
	-- 102 rather than 94 centres the 22 px line on the 38 px tabs beside it (94 + (38-22)/2 = 102).
	-- The width stops 300 px short of the right edge: 262 of tab plus a 16 gap plus the margin, so a
	-- long odds string truncates against the tabs instead of running under them.
	odds.Size = UDim2.new(1, -300, 0, 22)
	odds.Position = UDim2.new(0, 22, 0, 102)
	odds.BackgroundTransparency = 1
	odds.RichText = true
	odds.TextXAlignment = Enum.TextXAlignment.Left
	odds.ZIndex = petsPanel.ZIndex + UITheme.Z.Content
	local parts = {}
	for _, e in ipairs(GameConfig.Enchants) do
		-- shade(-0.35) for the same reason the rarity word on each card takes it: these sit on a
		-- white sheet, and the chip colours are chosen to be readable as FILLS, not as ink
		table.insert(parts, colorTag(("%s %g%%"):format(e.name, e.weight), shade(e.color, -0.35)))
	end
	odds.Text = "\u{2728} Enchant odds:  " .. table.concat(parts, "  \u{00B7}  ")
	odds.Parent = petsPanel
	flatText(themeLabel(odds, 16, Color3.fromRGB(150, 154, 168)))
end

-- Live rigs shown in the pet rows. A row shows the actual creature in a ViewportFrame rather
-- than its emoji: the emoji is the same 🐾 shape for half the roster, and the whole point of 100
-- species is that you can tell them apart. Kept in a list so one RenderStepped can turn them all.
local petPreviewRigs = {}

local function refreshPetsPanel()
	if not currentData then return end
	-- SHUT MEANS SKIPPED (11.32). This function destroys every cell and rebuilds each one with a real
	-- `PetModel.Build` -- ~30 parts a pet, so a full 100-pet bag is ~3,000 parts -- and it used to run
	-- on every `DataUpdate`, which the server sends about every three seconds AND on every kill. Most
	-- of that work was drawn into a panel nobody was looking at. Raising `MaxOwnedPets` 30 -> 100 in
	-- 11.10 tripled the bill without anything flagging it; the turntable beside this already checked
	-- `petsPanel.Visible`, which is what made the omission look deliberate.
	--
	-- A bare guard would leave the panel opening stale, so the pair to this is the `Visible` listener
	-- below `hudRefs.refreshPetsPanel` -- and it is hung on the PROPERTY, not on the open handlers,
	-- because there are three ways in (the HUD button, the tab strip, `toggleOnly` from elsewhere)
	-- and a fourth would silently open stale. Everything this function writes -- the title, both
	-- counter capsules, the empty label, the grid -- is parented inside `petsPanel`, so there is
	-- nothing here that a closed panel still owes the rest of the HUD.
	if not petsPanel.Visible then return end
	local data = currentData

	-- NO LEADING 🐾 HERE ANY MORE: the paw is drawn beside this label as a TitleIcon (9.9), and a
	-- refresh that put the glyph back would show the emoji next to the picture of itself. The
	-- icon is built once and never changes, so this line only carries the words.
	--
	-- NO COUNT IN THE TITLE EITHER. It used to read "Pets (%d/%d equipped)" against the raw
	-- `GameConfig.MaxEquippedPets` constant — the base 3, which ignores the diamond PetSlot upgrade
	-- and the +3 Pet Slots pass. A player who had bought slots saw "5/3", a fraction that says their
	-- save is broken. The slot capsule directly below already prints the same pair through
	-- `GetMaxEquippedPets(data)`, which counts both, so the title had nothing left to add.
	--
	-- AND SINCE 17.x IT REWRITES NOTHING AT ALL. The title is the accent band's, built once with the
	-- words it will always have; `petsPanelTitle` no longer exists and this line referenced a name
	-- that was out of scope -- which Luau compiles happily and `luascope.py` is the only check that
	-- catches. Left as a comment rather than deleted, because the two paragraphs above are the record
	-- of why the title says exactly "Pets!" and nothing about counts.

	-- Clear old cells. Matched on NAME alone: a cell is a TextButton now (the whole card is the
	-- equip button), and the old `IsA("Frame")` test silently stopped clearing anything -- every
	-- refresh would have stacked another full copy of the collection into the grid.
	for _, child in ipairs(petsScroll:GetChildren()) do
		if child.Name == "PetRow" then
			child:Destroy()
		end
	end
	-- the rigs went with the rows they were parented to
	table.clear(petPreviewRigs)

	petsEmptyLabel.Visible = (#data.Pets == 0)

	local equippedLookup = {}
	for _, id in ipairs(data.EquippedPetIds) do equippedLookup[id] = true end

	-- Strongest first. The old order was insertion order -- literally the order the pets happened
	-- to hatch in -- so in a collection of two hundred the best one could be anywhere and the three
	-- that were actually equipped were scattered down the scroll.
	--
	-- `data` IS THE SECOND ARGUMENT AND IT WAS MISSING HERE. Without it `GetPetPower` drops the zone
	-- axis and quotes every pet at its own home zone's strength, so the drawn order stopped matching
	-- the real one: a zone-matched Epic that beats a Forest Legendary four times over was drawn under
	-- it. The two server callers (`PetService`, `PlayerDataService`) always passed it, so the list the
	-- player read and the list Equip Best acted on were sorted differently.
	local ranked = GameConfig.SortedPetsByPower(data.Pets, data)

	-- ===== PRUNE THE SELECTION AGAINST WHAT STILL EXISTS (11.17) =====
	--
	-- The set is keyed by pet id and outlives the cards, which is what makes it survive the rebuild
	-- this function does on every DataUpdate -- but it also means a pet that left the save by some
	-- OTHER route while select mode was open (a fusion consuming it, a release from the single-pet
	-- x, a trade) would stay ticked forever in a set nobody can see. The count on the RELEASE button
	-- would then be larger than the number of ticks on screen, which is the one thing a confirm
	-- dialog must never be.
	local sel = hudRefs.petSelect
	if sel and sel.n > 0 then
		local alive, dropped = {}, false
		for _, p in ipairs(data.Pets) do alive[p.id] = true end
		for id in pairs(sel.ids) do
			if not alive[id] then
				sel.ids[id] = nil
				sel.n -= 1
				dropped = true
			end
		end
		-- the button carries the count, so it has to hear about this
		if dropped and hudRefs.petSelectRepaint then hudRefs.petSelectRepaint() end
	end

	hudRefs.petSlotCount.Text = ("%d/%d"):format(#data.EquippedPetIds, GameConfig.GetMaxEquippedPets(data))
	-- "17 / 30" rather than "17": a bare number cannot tell the player they are one hatch from being
	-- refused, and being refused at the podium with no warning is how the 600-cap read as a bug.
	-- The capsule turns red AT the cap and amber approaching it, so the state is legible without
	-- reading the digits -- and `>=` rather than `==` because a grandfathered save can sit above it.
	local owned, cap = #data.Pets, GameConfig.MaxOwnedPets
	hudRefs.petOwnedCount.Text = ("%d/%d"):format(owned, cap)
	local capsule = hudRefs.petOwnedCount.Parent
	if capsule then
		capsule.BackgroundColor3 = (owned >= cap) and UITheme.Color.Red
			or (owned >= cap - 3) and UITheme.Color.Orange
			or UITheme.Color.Blue
	end

	for i, pet in ipairs(ranked) do
		local info = petDisplayInfo(pet.key)
		local rarity = GameConfig.GetRarity(info.rarity)
		local isEquipped = equippedLookup[pet.id] == true
		-- `pet.key` and `data` are what make this row honest about the zone axis: the same Legendary
		-- reads +80% while its own zone is current and +20% once the player has climbed well past it,
		-- which is the whole point of the progression rebalance. Quoting it without them would print
		-- a number the damage chain does not use.
		-- `pet.enchant` is the fifth axis (13.1). It is passed here and nowhere reimplemented: the
		-- card quotes exactly the share the damage chain sums, enchant included.
		local bonus = GameConfig.GetPetBonus(pet.tier, info.rarity, pet.key, data, pet.enchant)
		-- The reference prints a flat "+75". A pet's contribution is a share of the player's own
		-- damage, summed across the equipped slots, so the percentage it adds IS the number -- and
		-- unlike the old multiplicative reading it is now literally true: three pets at +80% each
		-- really do come to +240% damage.
		local damageText = ("+%d%%"):format(math.floor((bonus.damageMult - 1) * 100 + 0.5))

		-- THE CELL IS THE BUTTON. In the reference you equip by clicking the pet, not by hunting for
		-- an Equip button on its row -- and the pet's art hangs off the top-left of its card, outside
		-- it, which only works if the clickable thing is the whole cell rather than the card.
		-- ViewportFrames and Frames are inactive by default, so clicks on the art land here too.
		local cell = Instance.new("TextButton")
		cell.Name = "PetRow"
		cell.LayoutOrder = i
		cell.Text = ""
		cell.AutoButtonColor = false
		cell.BackgroundTransparency = 1
		cell.Size = UDim2.new(0, 232, 0, 156)
		cell.ZIndex = petsScroll.ZIndex + UITheme.Z.Content
		cell.Parent = petsScroll
		-- assigned further down, once the card exists to hang it on; the handler below closes over
		-- the LOCAL, so it sees the box whenever it is clicked rather than whatever was built first
		local selectBox = nil
		cell.MouseButton1Click:Connect(function()
			-- ===== IN SELECT MODE THE CELL PICKS, IT DOES NOT EQUIP (11.17) =====
			-- Read at CLICK time rather than captured when the row was built: the mode can be
			-- toggled between a refresh and a click, and a captured flag would leave a grid of cards
			-- still equipping while the bar says RELEASE.
			local sel = hudRefs.petSelect
			if sel and sel.on then
				-- An equipped pet is not offered: the server refuses to delete one, so letting it be
				-- ticked would build a selection whose count and whose outcome disagree. Same rule
				-- the single-pet x already follows -- absent, never drawn-then-refused.
				if isEquipped then return end
				if hudRefs.petSelectToggleId then hudRefs.petSelectToggleId(pet.id) end
				-- ONE CELL REPAINTED, NOT THE WHOLE GRID. refreshPetsPanel destroys and rebuilds
				-- every card, and each card builds a real PetModel rig -- a hundred pets is roughly
				-- three thousand parts. Rebuilding that on every tick of a checkbox would make
				-- selecting ten pets the most expensive thing in the HUD. The bar's own count is
				-- redrawn by petSelectToggleId; this is the other half of the same state.
				if selectBox then
					local ticked = sel.ids[pet.id] == true
					selectBox.Text = ticked and "\u{2714}" or ""
					setButtonColor(selectBox, ticked and UITheme.Color.Green or Color3.fromRGB(236, 238, 246))
				end
				return
			end
			if isEquipped then
				Remotes.UnequipPet:FireServer(pet.id)
			else
				Remotes.EquipPet:FireServer(pet.id)
			end
		end)

		-- the grey card, offset right and down to leave the art its corner
		local card = Instance.new("Frame")
		card.Name = "Card"
		-- 122, not 92, since 13.3: the enchant row sits at y=89 and needs 28 of height plus a 5px
		-- foot. The CELL grew with it -- see the grid's CellSize and the CanvasSize arithmetic at the
		-- bottom of this function, which are two numbers expressing one decision.
		card.Size = UDim2.new(0, 180, 0, 122)
		card.Position = UDim2.new(0, 52, 0, 32)
		card.ZIndex = cell.ZIndex
		card.Parent = cell
		-- rarity rides the rim: it is the one thing the reference has no equivalent for, and a
		-- coloured edge says it without spending a line of the card on the word
		--
		-- ===== ...AND THE FACE CARRIES IT TOO NOW (18.6) =====
		--
		-- rgb(226,228,236) is a hueless near-white, so a wall of pet cards was white on white on a
		-- white panel with one thin coloured line round each: the rarity was already known to the card
		-- (`SubLabel` prints its name) and the card refused to look like it. Same 18.2 technique as the
		-- currency capsules -- `Frost` lerped a fixed fraction toward the identity colour, both ends of
		-- the lerp an existing token, so no new colour enters the palette.
		--
		-- **0.18 is set by the darkest rarity, not by taste.** The lerp has to land above the kit's
		-- 0.86 `LIGHT_SURFACE` cut or the card flips to white ink and the three dark captions below
		-- become invisible. Secret rgb(255,64,160) is the lowest-luminance rarity at 0.518, and
		-- 0.95 - 0.18*(0.95-0.518) = **0.872**; Epic lands 0.871, Rare 0.875, Legendary and Common
		-- higher still. At 0.22 Secret would have come out 0.855 and been the one card in the game
		-- with the wrong ink.
		local cardFill = UITheme.Color.Frost:Lerp(rarity.color, 0.18)
		styleCard(card, cardFill, UDim.new(0, 14), 3).Color =
			isEquipped and Color3.fromRGB(62, 196, 86) or rarity.color

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "PetName"
		nameLabel.Size = UDim2.new(1, -20, 0, 26)
		nameLabel.Position = UDim2.new(0, 10, 0, 5)
		nameLabel.BackgroundTransparency = 1
		nameLabel.ZIndex = card.ZIndex + UITheme.Z.Content
		nameLabel.Text = info.name
		nameLabel.Parent = card
		-- ===== THE PET'S OWN NAME WAS THE FAINTEST THING ON ITS CARD (18.6) =====
		--
		-- rgb(122,126,140) is a mid grey at luminance 0.49 on a card at 0.87, and `flatText` then
		-- switches its halo off -- so the headline of the card was carried by 0.38 of luminance
		-- difference and nothing else. `Color.Ink` (rgb 48,38,66, lum 0.17) is the kit's token for
		-- exactly this: the dark glyph for a light surface. It is dark ink by `IsDarkInk`, so
		-- `themeLabel` drops the halo on its own and `flatText` becomes a no-op rather than a fix.
		flatText(themeLabel(nameLabel, 24, UITheme.Color.Ink))

		local subLabel = Instance.new("TextLabel")
		subLabel.Name = "SubLabel"
		subLabel.Size = UDim2.new(1, -20, 0, 18)
		subLabel.Position = UDim2.new(0, 10, 0, 31)
		subLabel.BackgroundTransparency = 1
		subLabel.RichText = true
		subLabel.ZIndex = card.ZIndex + UITheme.Z.Content
		subLabel.Text = colorTag(rarity.name, shade(rarity.color, -0.35)) .. " · " .. pet.tier
		subLabel.Parent = card
		-- rgb(150,154,168), lum 0.60 -- the palest ink in the file, on a light card. `InkSoft` is the
		-- kit's "secondary text on a light surface" token (lum 0.37) and is the SAME family as the Ink
		-- above it, so name and sub-line read as one block with a hierarchy instead of as two greys.
		-- The rarity word inside keeps its own inline colour: `colorTag` sets it per-run and RichText
		-- overrides `TextColor3` for that span only.
		flatText(themeLabel(subLabel, 16, UITheme.Color.InkSoft))

		-- the inset stat bar, the one line the reference's card actually carries
		local statBar = Instance.new("Frame")
		statBar.Name = "StatBar"
		statBar.Size = UDim2.new(1, -20, 0, 34)
		statBar.Position = UDim2.new(0, 10, 0, 51)
		-- The groove keeps the card's own tint rather than reverting to a hueless rgb(240,242,248):
		-- a neutral inset on a tinted card is the one place the old grey would still show through.
		-- shade(-0.06) is a 6% darkening, so an Epic card's bar is a deeper violet-white and a
		-- Legendary's a deeper cream. Six per cent and not more because this bar carries dark ink by
		-- hand rather than by the `InkOn` cut: the worst case (Secret) goes 0.872 -> 0.820, which is
		-- still a wide margin under `Color.Ink` at 0.17, and a deeper groove would start eating it.
		statBar.BackgroundColor3 = shade(cardFill, -0.06)
		statBar.BorderSizePixel = 0
		statBar.ZIndex = card.ZIndex + UITheme.Z.Content
		statBar.Parent = card
		corner(statBar, UDim.new(0, 10))

		local statLabel = Instance.new("TextLabel")
		statLabel.Name = "StatLabel"
		statLabel.Size = UDim2.new(1, -12, 1, -6)
		statLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
		statLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		statLabel.BackgroundTransparency = 1
		statLabel.ZIndex = statBar.ZIndex + UITheme.Z.Content
		statLabel.Text = ("\u{1F5E1}\u{FE0F} Damage: %s"):format(damageText)
		statLabel.Parent = statBar
		-- rgb(88,92,104) is lum 0.36 -- already close to `InkSoft` -- but this line is the card's one
		-- NUMBER, the thing a player compares between two pets, so it takes the full `Color.Ink`
		-- rather than the secondary tone. Ink for the value, InkSoft for the label above it.
		flatText(themeLabel(statLabel, 18, UITheme.Color.Ink))

		-- ===== THE ENCHANT ROW (13.3) =====
		--
		-- One row, and it says a different thing depending on whether this pet has ever been
		-- enchanted. Unenchanted, the whole width is the offer -- an action nobody has taken yet has
		-- to be the loud thing on the card. Once it wears one, the enchant's NAME takes the left of
		-- the row in its own colour and the roll shrinks to a price button on the right: the state
		-- is what the player wants to read at a glance across a grid of thirty pets, and the re-roll
		-- is a thing they go looking for.
		--
		-- The price comes from `GetEnchantCost`, the same pure function the server charges with, so
		-- the card cannot quote a number the transaction disagrees with -- the rule 12.3's cost
		-- label follows for the Splicer.
		do
			local enchantDef = GameConfig.GetEnchantDef(pet.enchant)
			local cost = GameConfig.GetEnchantCost(pet)
			local canAfford = (data.Diamonds or 0) >= cost

			local rollBtn = Instance.new("TextButton")
			rollBtn.Name = "EnchantButton"
			rollBtn.Size = UDim2.new(0, enchantDef and 68 or 160, 0, 28)
			rollBtn.Position = UDim2.new(0, enchantDef and 102 or 10, 0, 89)
			rollBtn.Text = enchantDef and ("%d \u{1F48E}"):format(cost)
				or ("\u{2728} ENCHANT  %d \u{1F48E}"):format(cost)
			rollBtn.ZIndex = card.ZIndex + UITheme.Z.Content
			rollBtn.Parent = card
			-- grey when it cannot be paid for, rather than hidden or silently refused: the price is
			-- the information, and a player two diamonds short should be able to see that
			styleButton(rollBtn, canAfford and UITheme.Color.Purple or Color3.fromRGB(176, 180, 192),
				UDim.new(0, 9), 2)
			themeLabel(rollBtn, enchantDef and 16 or 17)
			rollBtn.MouseButton1Click:Connect(function()
				-- resolved at CLICK time: this remote is created by PetService.Init through
				-- `ensureRemote`, so a client that built its HUD first would have captured a nil
				local r = Remotes:FindFirstChild("EnchantPet")
				if r then
					r:FireServer(pet.id)
				else
					warn("[MainUI] Remotes.EnchantPet never appeared -- enchanting is disabled")
				end
			end)

			if enchantDef then
				local worn = Instance.new("TextLabel")
				worn.Name = "EnchantChip"
				worn.Size = UDim2.new(0, 84, 0, 28)
				worn.Position = UDim2.new(0, 10, 0, 89)
				worn.Text = ("\u{2728} %s"):format(enchantDef.name)
				worn.ZIndex = card.ZIndex + UITheme.Z.Content
				worn.Parent = card
				styleCard(worn, enchantDef.color, UDim.new(0, 9), 2)
				-- INK CHOSEN BY LUMINANCE, NOT BY RUNG -- the same test 12.3 and 12.6 both had to
				-- reach for, so a future rung is handled for free.
				--
				-- THE THRESHOLD IS 0.40, AND THE FIRST CUT'S 0.62 WAS WRONG FOR THIS PALETTE. Every
				-- rung on this ladder is a SATURATED, LIGHT fill by design (they have to read as
				-- chips on a white card), so the two mid rungs landed at 0.611 and 0.612 and took
				-- white ink on a fill bright enough to swallow it -- about 2.8:1, under any
				-- readability floor, while dark ink on the same fill is 4.5:1. At 0.40 all six take
				-- dark ink today and the white branch is kept for the dark rung a later phase adds.
				local c = enchantDef.color
				local lum = 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
				local dark = lum > 0.40
				themeLabel(worn, 15, dark and Color3.fromRGB(58, 46, 24) or Color3.fromRGB(255, 255, 255))
				-- ...AND THE STROKE HAS TO GO WITH THE INK, which the first cut got wrong and the
				-- screenshot caught: themeLabel outlines every label in near-black at 3 px, so the
				-- dark half of this branch was drawing (58,46,24) glyphs inside a (26,18,36) outline
				-- -- the same colour, i.e. a fat dark blob with a slightly lighter core. The white
				-- half NEEDS that outline (white on a mid violet is thin without it) and the dark
				-- half does not: a light fill already separates dark ink. Third time this exact
				-- fault has been found by looking rather than by probing (12.3, 12.6, here), and
				-- `TextFits`, `.Text` and `.TextColor3` all read correct in every one of them.
				if dark then flatText(worn) end
			end
		end

		-- ===== RELEASE =====
		--
		-- A small x in the card's top-right rather than a button on the row. The whole cell is the
		-- equip toggle (see the note above), so a full-width Release button would sit inside the
		-- thing it must not be confused with -- and the destructive action must be the one you aim
		-- at, not the one you hit by missing.
		--
		-- ABSENT ON AN EQUIPPED PET, not disabled. The server refuses to release an equipped pet, so
		-- a button that is drawn and then refused would teach the player the UI is lying to them;
		-- unequipping is one click on the same cell and puts the x back.
		--
		-- IN SELECT MODE THE x IS REPLACED BY A CHECKBOX, in the same corner (11.17). Not shown
		-- alongside it: two small controls in one corner, one of which deletes immediately and one of
		-- which does not, is the worst possible pairing. The two modes are exclusive, so the corner
		-- says exactly one thing at a time.
		local selecting = hudRefs.petSelect and hudRefs.petSelect.on
		if not isEquipped and not selecting then
			local release = Instance.new("TextButton")
			release.Name = "Release"
			release.Size = UDim2.new(0, 26, 0, 26)
			-- hangs off the card's own corner, clear of the art in the opposite one
			release.Position = UDim2.new(1, -8, 0, -8)
			release.AnchorPoint = Vector2.new(1, 0)
			release.Text = "\u{2715}"
			release.ZIndex = card.ZIndex + UITheme.Z.Badge
			release.Parent = card
			styleButton(release, UITheme.Color.Red, UDim.new(1, 0), 2)
			themeLabel(release, 16)
			release.MouseButton1Click:Connect(function()
				if hudRefs.confirmRelease then
					hudRefs.confirmRelease(pet.id, info.name, rarity.name, rarity.color)
				end
			end)
		elseif selecting and not isEquipped then
			-- A LABEL, NOT A BUTTON. The whole cell is already the hit area in select mode, so a
			-- clickable box inside it would swallow clicks aimed at the card and leave the pet's
			-- picture -- the biggest part of the target -- doing nothing.
			local box = Instance.new("TextLabel")
			box.Name = "SelectBox"
			box.Size = UDim2.new(0, 28, 0, 28)
			box.Position = UDim2.new(1, -8, 0, -8)
			box.AnchorPoint = Vector2.new(1, 0)
			box.Text = hudRefs.petSelect.ids[pet.id] and "\u{2714}" or ""
			box.ZIndex = card.ZIndex + UITheme.Z.Badge
			box.Parent = card
			styleCard(box, hudRefs.petSelect.ids[pet.id] and UITheme.Color.Green
				or Color3.fromRGB(236, 238, 246), UDim.new(0, 8), 3)
			themeLabel(box, 20)
			selectBox = box
		end

		-- the pet itself, hanging off the card's top-left corner with nothing behind it. The rig is
		-- the same PetModel build that walks around the world, so what you see here is what you get.
		local preview = Instance.new("ViewportFrame")
		preview.Name = "Preview"
		preview.Size = UDim2.new(0, 96, 0, 96)
		preview.Position = UDim2.new(0, 0, 0, 0)
		preview.BackgroundTransparency = 1
		preview.BorderSizePixel = 0
		preview.Ambient = Color3.fromRGB(196, 196, 212)
		preview.LightColor = Color3.fromRGB(255, 255, 255)
		preview.LightDirection = Vector3.new(-0.4, -1, -0.55)
		preview.ZIndex = card.ZIndex + UITheme.Z.Badge
		preview.Parent = cell

		local def = GameConfig.GetPetDef(pet.key)
		if def then
			local rig, rigRoot, rigPieces = PetModel.Build(def, pet.tier, {
				scale = 1,
				nameplate = false,
				outline = false,
				sparkle = false,
			})
			PetModel.Place(rigRoot, rigPieces, CFrame.new())
			rig.Parent = preview

			local cam = Instance.new("Camera")
			-- a touch off-axis, so the rig reads as three-dimensional instead of as a mugshot
			cam.FieldOfView = 45
			cam.CFrame = CFrame.new(Vector3.new(3.2, 2.8, -7.4), Vector3.new(0, 1.0, 0))
			cam.Parent = preview
			preview.CurrentCamera = cam

			table.insert(petPreviewRigs, { root = rigRoot, pieces = rigPieces, phase = i * 0.7 })
		end

		-- the green tick, ON the pet, exactly where the reference puts it
		if isEquipped then
			local tick = Instance.new("TextLabel")
			tick.Name = "EquippedTick"
			tick.Size = UDim2.new(0, 46, 0, 46)
			tick.Position = UDim2.new(0, 26, 0, 22)
			tick.BackgroundTransparency = 1
			tick.ZIndex = preview.ZIndex + 2
			tick.Text = "\u{2714}"
			tick.Parent = cell
			themeLabel(tick, 44, Color3.fromRGB(62, 196, 86))
		end

		-- and the big green number under it: the same figure the stat bar spells out, at a glance
		local valueLabel = Instance.new("TextLabel")
		valueLabel.Name = "ValueLabel"
		valueLabel.Size = UDim2.new(0, 88, 0, 28)
		valueLabel.Position = UDim2.new(0, 4, 0, 72)
		valueLabel.BackgroundTransparency = 1
		valueLabel.ZIndex = preview.ZIndex + 2
		valueLabel.Text = damageText
		valueLabel.Parent = cell
		themeLabel(valueLabel, 26, Color3.fromRGB(62, 196, 86))

		-- ===== THE SECRET BADGE (12.12) =====
		--
		-- The rarity is already on the card twice -- the rim colour and the word in the sub-line --
		-- and for the other five that is exactly right. A Secret is a 1-in-50,000 hatch, and the
		-- first thing a player does with one is show it to somebody; a word in 16px grey text three
		-- lines down is not a thing you can point at. So it gets the one loud element in this panel.
		--
		-- ON THE CELL, IN THE ART'S TOP-LEFT CORNER, which is the only free corner: the card's
		-- top-right is the release x (or the select checkbox), the equipped tick sits at (26,22) on
		-- the rig itself, and the damage figure owns the bottom-left at y=72. Nothing else can be
		-- drawn here, so nothing else has to move.
		if info.secret then
			local badge = Instance.new("TextLabel")
			badge.Name = "SecretBadge"
			badge.Size = UDim2.new(0, 60, 0, 20)
			badge.Position = UDim2.new(0, 0, 0, 0)
			-- above the ViewportFrame, which is itself lifted to Badge -- the rig would otherwise
			-- render over a label parented to the same cell
			badge.ZIndex = preview.ZIndex + 3
			badge.Text = "SECRET"
			badge.Parent = cell
			styleCard(badge, rarity.color, UDim.new(0, 7), 2)
			themeLabel(badge, 14, Color3.fromRGB(255, 255, 255))
		end

		-- No per-row Fuse button any more. Fusing is a decision about a GROUP of four identical
		-- pets, not about the one row under the cursor, and a button that silently consumed three
		-- other pets from elsewhere in the list was the least readable thing in this panel. It
		-- lives in the Fusion panel now, which shows what goes in and what comes out.
	end

	-- three to a row, cell 156 tall on 12 of padding (13.3 grew the cell for the enchant row)
	petsScroll.CanvasSize = UDim2.new(0, 0, 0, math.ceil(#data.Pets / 3) * 168 + 12)
end

-- Handed over so the select-mode block above -- which is built ~200 lines earlier and cannot name a
-- local declared below it -- can force a redraw when the mode changes (11.17).
hudRefs.refreshPetsPanel = refreshPetsPanel

-- The other half of the skip-while-shut guard (11.32): the grid is rebuilt the moment the panel
-- becomes visible, off whatever `currentData` holds by then, so skipping the pushes that arrived
-- while it was closed costs nothing a player can see. It is one connection on the property rather
-- than a call in each open path, and it cannot fire on a close.
petsPanel:GetPropertyChangedSignal("Visible"):Connect(function()
	if petsPanel.Visible then refreshPetsPanel() end
end)

-- One turntable for every row, and only while the panel is actually open: a ViewportFrame costs
-- nothing when nobody is looking at it, and a pet standing dead still in a box looks like a
-- screenshot of a pet.
RunService.RenderStepped:Connect(function()
	if not petsPanel.Visible then return end
	local t = os.clock()
	for _, rig in ipairs(petPreviewRigs) do
		if rig.root.Parent then
			PetModel.Place(rig.root, rig.pieces,
				CFrame.new(0, math.sin(t * 1.7 + rig.phase) * 0.07, 0)
				* CFrame.Angles(0, math.sin(t * 0.55 + rig.phase) * 0.55, 0))
		end
	end
end)

-- ===== Release confirmation =====
--
-- The one destructive action a player can take on their own save, so it is the one thing in this
-- HUD that asks twice. It exists because the inventory ceiling came down from 600 (GameConfig
-- .MaxOwnedPets, 100 today): at 600 there was never a reason to remove a pet and so there was never
-- a way to, and a cap without a release is just a wall.
--
-- THE DIALOG IS BUILT ONCE AND RE-TARGETED, not built per pet. A confirm built inside the row
-- handler would allocate a full modal on every click, and the row list is rebuilt from scratch on
-- every data push -- so the frames would pile up behind a panel nobody has closed.
--
-- Deliberately NOT symmetrical: Cancel is the wide neutral button and sits first, Release is
-- narrower, red, and second. The safe path is the easy one to hit, and the destructive one has to
-- be aimed at. `pendingId` is cleared on every exit path, so a stale id cannot be released by a
-- later confirm that was opened for a different pet and dismissed with Escape.
--
-- Built inside an immediately-called function so its locals get a register file of their own --
-- see the note on the Season Pass panel for why a `do` block is not enough. Handles via `hudRefs`.
-- MOVED OUT (18.9) to `ReplicatedStorage.Modules.HUD.PetRelease` -- 144 lines, unchanged.
require(RS.Modules:WaitForChild("HUD"):WaitForChild("PetRelease"))(hudRefs)

-- ===== Pet Fusion panel =====
-- Fusing is a decision about a GROUP -- four identical pets go in, one of the next tier comes out
-- -- so this panel lists GROUPS, not pets. Each row is one species at one tier, and it states the
-- whole trade before you commit: how many you own, how many it takes, and what the result is
-- worth against what you are giving up.
--
-- Built inside an immediately-called function so its locals get a register file of their own --
-- see the note on the Season Pass panel for why a `do` block is not enough. Handles via `hudRefs`.
-- MOVED OUT (18.9) to `ReplicatedStorage.Modules.HUD.PetFusion` -- 392 lines, unchanged.
require(RS.Modules:WaitForChild("HUD"):WaitForChild("PetFusion"))(hudRefs)

local function refreshZonesPanel()
	if not currentData then return end
	local unlockedLookup = {}
	for _, k in ipairs(currentData.UnlockedZones) do unlockedLookup[k] = true end
	for _, zone in ipairs(GameConfig.Zones) do
		local refs = zoneRows[zone.key]
		if refs then
			if unlockedLookup[zone.key] then
				refs.statusLabel.Text = "Unlocked" .. (zone.incomeBonusPct > 0 and (" · +" .. zone.incomeBonusPct .. "% income") or "")
				UITheme.ShowIconOrText(refs.goButton, false, "Go")
				setButtonColor(refs.goButton, Color3.fromRGB(60, 190, 100))
			else
				-- BOTH REASONS, and the one actually in the way first.
			--
			-- This row used to print the stage requirement alone. A zone also needs the PREVIOUS
			-- zone's boss defeated (GameConfig.IsZoneUnlocked), so a Bacteria player would read
			-- "Desert -- Requires: Bacteria" with "🧬 Bacteria" in the top bar and conclude the
			-- panel was broken. ZoneService already answers the press with the right reason; the
			-- list was the only thing lying about it.
				local reqStage = GameConfig.Stages[zone.unlockStageIndex]
				local stageOk = (currentData.StageIndex or 1) >= zone.unlockStageIndex
				local bossKey = zone.requiresBossKey
				local bossDone = true
				if bossKey then
					bossDone = false
					for _, k in ipairs(currentData.DefeatedBosses or {}) do
						if k == bossKey then
							bossDone = true
							break
						end
					end
				end
				if not stageOk then
					refs.statusLabel.Text = "Requires: " .. (reqStage and reqStage.name or "?")
				elseif not bossDone then
					local prev = GameConfig.GetZoneByKey(bossKey)
					refs.statusLabel.Text = "Beat the " .. ((prev and prev.name) or bossKey) .. " boss"
				else
					refs.statusLabel.Text = "Requires: " .. (reqStage and reqStage.name or "?")
				end
				UITheme.ShowIconOrText(refs.goButton, true, "\u{1F512}")
				setButtonColor(refs.goButton, UITheme.Color.Locked)
			end
		end
	end
end

-- ===== Rebirth panel =====
local rebirthPanel = Instance.new("Frame")
rebirthPanel.Name = "RebirthPanel"
-- 392 -> 416: the 20 px ladder bar plus its gaps, added below the info card (11.16)
rebirthPanel.Size = UDim2.new(0, 430, 0, 454)
rebirthPanel.Position = PANEL_ANCHOR
rebirthPanel.ZIndex = 20
rebirthPanel.Visible = false
rebirthPanel.Parent = screenGui
styleCard(rebirthPanel, PANEL_SHELL, UDim.new(0, 22), 5)
registerPanel(rebirthPanel)
panelClose(rebirthPanel)

-- Converted to the shared accent band (17.x). Every child below moved down 38 -- the band's 94 less
-- the 56 the info card used to start at -- and the panel grew by the same 38 so the bottom-anchored
-- action button keeps its gap. Lavender is the pastel of the Rebirth tile's purple; the panel and
-- the button that opens it have to agree.
UITheme.PanelHeader(rebirthPanel, {
	title = "♻️ Rebirth",
	subtitle = "Reset progress for a permanent multiplier",
	accent = UITheme.Color.Lavender,
})

-- the two readouts get real cards rather than bare text on the shell, so the panel has the
-- same stacked-card rhythm as Zones/Pets instead of reading as a dialog box
local rebirthInfoCard = Instance.new("Frame")
rebirthInfoCard.Name = "InfoCard"
rebirthInfoCard.Size = UDim2.new(1, -32, 0, 64)
rebirthInfoCard.Position = UDim2.new(0, 16, 0, 94)
rebirthInfoCard.Parent = rebirthPanel
styleCard(rebirthInfoCard, UITheme.Color.Purple, UDim.new(0, 14), 4)

local rebirthInfoLabel = Instance.new("TextLabel")
rebirthInfoLabel.Name = "InfoLabel"
rebirthInfoLabel.Size = UDim2.new(1, -24, 1, -16)
rebirthInfoLabel.Position = UDim2.new(0, 12, 0, 8)
rebirthInfoLabel.BackgroundTransparency = 1
rebirthInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
rebirthInfoLabel.TextYAlignment = Enum.TextYAlignment.Top
rebirthInfoLabel.TextWrapped = true
rebirthInfoLabel.Text = "Rebirths  0 / 4"
rebirthInfoLabel.Parent = rebirthInfoCard
themeLabel(rebirthInfoLabel, 19, UITheme.Color.Cream)

-- ===== THE CLIMB TO THE NEXT RUNG, DRAWN (11.16) =====
--
-- The card below states it in words -- "You are Stage 12 -- 3 stages to go" -- and words are the
-- wrong shape for a distance. This is the one thing on the panel a player checks repeatedly during
-- a run, and until now checking it meant reading a sentence.
--
-- IT MEASURES THE RUN, NOT THE LADDER. The obvious other candidate was `Rebirths / MaxRebirths`,
-- and that is the same mistake as a bar per Journal stage: four rungs is four, and a four-step bar
-- says less than the "0 / 4" already printed above it. The stage climb is 1..20, it resets to 1 on
-- every rebirth, and it is what the player actually moves along -- so the bar is
-- (stage - 1) / (required stage - 1), which is 0 the moment a rebirth drops you back to Stage 1 and
-- exactly 1 when the button lights up.
--
-- One local, not three: the fill and the label are reached by name in the refresh. This file is at
-- Luau's 200-register cap.
local rebirthLadderBar = UITheme.ProgressBar(rebirthPanel, {
	name = "LadderBar",
	size = UDim2.new(1, -32, 0, 20),
	position = UDim2.new(0, 16, 0, 164),
	color = UITheme.Color.Purple,
	radius = UDim.new(1, 0),
	thickness = 3,
	text = "",
	maxTextSize = 16,
	zIndex = rebirthPanel.ZIndex + UITheme.Z.Content,
})

local rebirthReqCard = Instance.new("Frame")
hudRefs.rebirthReqCard = rebirthReqCard
rebirthReqCard.Name = "ReqCard"
rebirthReqCard.Size = UDim2.new(1, -32, 0, 176)
-- 132 -> 154, clearing the ladder bar above it. The panel grew by the same 24 (see its Size), so
-- nothing below this moved relative to the bottom edge.
rebirthReqCard.Position = UDim2.new(0, 16, 0, 192)
rebirthReqCard.Parent = rebirthPanel
styleCard(rebirthReqCard, UITheme.Color.Gold, UDim.new(0, 14), 4)

local rebirthReqLabel = Instance.new("TextLabel")
hudRefs.rebirthReqLabel = rebirthReqLabel
rebirthReqLabel.Name = "ReqLabel"
rebirthReqLabel.Size = UDim2.new(1, -24, 1, -16)
rebirthReqLabel.Position = UDim2.new(0, 12, 0, 8)
rebirthReqLabel.BackgroundTransparency = 1
rebirthReqLabel.TextXAlignment = Enum.TextXAlignment.Left
rebirthReqLabel.TextYAlignment = Enum.TextYAlignment.Top
rebirthReqLabel.TextWrapped = true
rebirthReqLabel.Text = "Reach Universe God to rebirth."
rebirthReqLabel.Parent = rebirthReqCard
themeLabel(rebirthReqLabel, 18)

-- ===== THE FOUR RUNGS, DRAWN, BECAUSE AT 4/4 THIS CARD WAS AN EMPTY AMBER BOX (18.4) =====
--
-- Her capture of the finished panel: a purple header, a purple stat card, then a 398 x 176 amber
-- slab carrying two sentences and about 100 px of nothing, over a grey "ALL REBIRTHS COMPLETE"
-- button. The endgame's own screen was telling the player there was nothing left -- which is exactly
-- backwards, because a finished ladder is the largest thing anybody in this game ever does.
--
-- The card keeps its job in the two live states (what the next milestone costs and what it pays).
-- What changes is the third: when the ladder is spent, the sentence is hidden and these rows take
-- the whole card, one per rebirth, each naming the stage it was gated behind and the two permanent
-- multipliers it left behind. Nothing here reads or writes the ladder -- the numbers come out of
-- `GameConfig.GetRebirthDamageMult` / `GetRebirthIncomeMult` with a synthetic `{ Rebirths = n }`,
-- the same two functions the live branches already call, so a fifth rung (17.14) needs no edit here.
--
-- COLOUR, WHICH IS THE OTHER HALF OF THE ROW. The panel was one hue plus a grey. Each rung takes a
-- kit pastel of its own -- Aqua, Mint, Lavender, Gold, an escalation ending on the trophy colour --
-- at FULL chroma on the rank disc and at `UITheme.DoneShade` on the row behind it. That is the kit's
-- own three-state separation and this is the "spent" case of it: same hue, a third of the chroma,
-- never the refusal grey. Four bright rows on the gold card is where the extra "nijanse" come from,
-- and none of them is a new colour.
--
-- INSIDE AN IIFE with one handle on `hudRefs`, per the register-cap rule at the top of the file.
-- MOVED OUT (18.9) to `ReplicatedStorage.Modules.HUD.RebirthRungs` -- 95 lines, unchanged.
require(RS.Modules:WaitForChild("HUD"):WaitForChild("RebirthRungs"))(hudRefs)

local rebirthActionButton = Instance.new("TextButton")
rebirthActionButton.Name = "ActionButton"
rebirthActionButton.Size = UDim2.new(1, -32, 0, 58)
rebirthActionButton.Position = UDim2.new(0, 16, 1, -74)
rebirthActionButton.Text = "REBIRTH"
rebirthActionButton.Parent = rebirthPanel
styleButton(rebirthActionButton, UITheme.Color.Locked, UDim.new(1, 0))

rebirthButton.MouseButton1Click:Connect(function()
	toggleOnly(rebirthPanel)
end)

rebirthActionButton.MouseButton1Click:Connect(function()
	Remotes.Rebirth:FireServer()
end)

-- ===== THE REBIRTH BEACON: AN ARROW THAT ONLY EXISTS WHEN THERE IS SOMETHING TO PRESS =====
--
-- A milestone that is reachable and unmentioned is a milestone nobody uses. This is the one moment
-- in the game worth interrupting for, so it gets a pointer -- and it gets exactly nothing the rest
-- of the time, which is what stops it becoming another permanently-lit badge the eye learns to skip.
--
-- Three deliberate cheapnesses, because this can be on screen for a long stretch:
--
--   * ONE `RunService.Heartbeat` for the whole beacon, connected only while it is showing and
--     disconnected the instant it is not. Not one per element, and nothing at all while locked.
--   * It reads `rebirthButton.AbsolutePosition` every frame rather than caching it, because the
--     responsive pass at the bottom of this file MOVES that tile on any viewport change -- a cached
--     position leaves the arrow pointing at empty screen after a window resize.
--   * `IgnoreGuiInset` is left FALSE on this ScreenGui. That is not an oversight: an offset Position
--     inside an inset-ignoring GUI is measured from the top of the SCREEN while `AbsolutePosition`
--     is reported below the topbar, and mixing the two puts everything exactly one inset (58 px
--     measured here) out of place. Copying the other GUI's flag looks like the fix and is not.
--
-- Everything lives in this immediately-called function so the file gains no top-level locals -- see
-- the register-cap note further down. The one handle out is `hudRefs.setRebirthReady`.
-- MOVED OUT (18.9) to `ReplicatedStorage.Modules.HUD.RebirthBeacon` -- 81 lines, unchanged.
require(RS.Modules:WaitForChild("HUD"):WaitForChild("RebirthBeacon"))(hudRefs)

-- ===== THE REBIRTH PANEL ANSWERS SIX QUESTIONS, IN ORDER =====
--
-- how many have I done, which is next, where am I now, what do I get, what do I lose, how far off
-- am I. It used to answer one and a half of those -- a Shard count and "a checkpoint exists every
-- 5 stages" -- which is why a rebirth read as a punishment: the panel listed a price and never once
-- named the thing being bought.
--
-- Everything here derives from GameConfig.CanRebirthNow / GetNextRebirthTier, the same two
-- functions the server and the shrine use, so the button can never offer something HandleRebirth
-- will refuse.
local function refreshRebirthPanel()
	if not currentData then return end
	local data = currentData
	local done = data.Rebirths or 0
	local nextTier = GameConfig.GetNextRebirthTier(data)
	local ready, why = GameConfig.CanRebirthNow(data)

	-- WHAT IS PERMANENT. Stated as the totals carried right now, not as a per-run rate: after a
	-- reset that takes the stage, the zones and the collection, "you permanently hit for x3.5" is
	-- the only framing in which the trade reads as a gain.
	-- "8 / 4" IS NOT A COUNTER, IT IS A BUG REPORT. Saves from before the ladder existed hold more
	-- rebirths than the ladder has rungs (the owner's test save has eight) and they keep every point
	-- of it -- so past the cap the denominator is dropped rather than printing a fraction that reads
	-- as broken arithmetic.
	local counter = (done > GameConfig.MaxRebirths)
		and ("Rebirths  %d"):format(done)
		or ("Rebirths  %d / %d"):format(done, GameConfig.MaxRebirths)
	rebirthInfoLabel.Text = string.format(
		"%s\n\u{2694}\u{FE0F}  x%.2f Damage  \u{2022}  \u{1F9EC}  x%.2f Income   (permanent)",
		counter, GameConfig.GetRebirthDamageMult(data), GameConfig.GetRebirthIncomeMult(data))

	if ready then
		local reqStageIndex = GameConfig.GetRebirthTierStageIndex(nextTier)
		local afterData = { Rebirths = done + 1 }
		rebirthReqLabel.Text = string.format(
			"REBIRTH %d IS READY.\nTakes you to  \u{2694}\u{FE0F} x%.2f Damage  \u{2022}  \u{1F9EC} x%.2f Income, forever.\n\nResets: stage, zones, upgrades, DNA, XP and your skins.\nKeeps: pets, diamonds, shards, mastery and everything above.",
			nextTier, GameConfig.GetRebirthDamageMult(afterData), GameConfig.GetRebirthIncomeMult(afterData))
		rebirthActionButton.Text = string.format("REBIRTH %d  \u{2022}  STAGE %d", nextTier, reqStageIndex)
		setButtonColor(rebirthActionButton, UITheme.Color.Purple)
		rebirthActionButton.Active = true
	elseif why == "done" then
		-- The ladder is four rungs and it ENDS. A save from before this rule can hold more than four
		-- and keeps every point of it -- there is simply nothing left to spend.
		--
		-- The sentence is kept but goes UNSEEN in this state (`setRebirthRungs` hides it): the four
		-- rung rows say the same thing with the numbers in it, and a sentence over four rows is what
		-- put 100 px of nothing on this card in the first place. It stays authored so the card is
		-- never blank if the rung block ever fails to build.
		rebirthReqLabel.Text = string.format(
			"All %d Rebirths complete.\nEverything they paid for is permanent and stays with you.",
			GameConfig.MaxRebirths)
		-- ===== GOLD, NOT `Locked` (18.4) =====
		--
		-- "puno je sivo i monotono", and this button is the sentence it was aimed at: the proudest
		-- line in the game was grey text on a grey slab. Grey is the kit's REFUSAL swatch -- locked,
		-- unaffordable, cannot press -- and it is genuinely right for the `stage` branch below, where
		-- the button is a control the player is not allowed to use yet. It is wrong here, because
		-- nothing is being refused: there is no fifth rung to want. `Color.Gold` is the kit's trophy
		-- colour and is used nowhere as an action, so it cannot be misread as "press me"; `Active`
		-- stays false and the button still does nothing when clicked, which is the behaviour that
		-- actually matters. White ink over the 4 px halo, same as the gold card above it -- Gold is
		-- luminance 0.78, under UITheme's 0.86 light-surface cut, so the ink does not want to flip.
		rebirthActionButton.Text = string.format("\u{1F3C6}  ALL %d REBIRTHS COMPLETE", GameConfig.MaxRebirths)
		setButtonColor(rebirthActionButton, UITheme.Color.Gold)
		rebirthActionButton.Active = false
	else
		-- HOW FAR OFF, in stages, because that is the unit the player moves in. Naming the creature
		-- as well as the number is what makes it a destination rather than a threshold.
		local reqStageIndex = GameConfig.GetRebirthTierStageIndex(nextTier)
		local reqStage = GameConfig.Stages[reqStageIndex]
		local togo = reqStageIndex - (data.StageIndex or 1)
		rebirthReqLabel.Text = string.format(
			"Rebirth %d unlocks at  %s %s  (Stage %d).\nYou are Stage %d \u{2014} %d %s to go.\n\nEach of the %d Rebirths is used ONCE, in order: stages 5, 10, 15 and 20.",
			nextTier, reqStage.emoji, reqStage.name, reqStageIndex,
			data.StageIndex or 1, togo, togo == 1 and "stage" or "stages", GameConfig.MaxRebirths)
		rebirthActionButton.Text = string.format("LOCKED  \u{2022}  %d MORE %s",
			togo, togo == 1 and "STAGE" or "STAGES")
		setButtonColor(rebirthActionButton, UITheme.Color.Locked)
		rebirthActionButton.Active = false
	end

	-- The req card holds prose in the two live states and the spent-rung block in the third; one call
	-- owns both halves so they can never both be on. See the block over the rungs.
	if hudRefs.setRebirthRungs then hudRefs.setRebirthRungs(why == "done") end

	-- ===== THE LADDER BAR (11.16) =====
	-- Computed here rather than in each of the three branches above, because all three want the same
	-- number and only the wording differs. `ready` and `done` both read FULL: at `ready` the climb is
	-- literally finished and the button below is lit, and at `done` there is no further rung -- a bar
	-- that sat at 90% in either state would be describing a distance that does not exist.
	do
		local stage = data.StageIndex or 1
		local frac, text
		if ready or why == "done" then
			frac = 1
			text = (why == "done") and "Ladder complete" or ("Stage %d \u{2014} ready"):format(stage)
		else
			local reqStageIndex = GameConfig.GetRebirthTierStageIndex(nextTier)
			-- from Stage 1, which is where every run starts and where a rebirth puts you back
			frac = math.clamp((stage - 1) / math.max(1, reqStageIndex - 1), 0, 1)
			text = ("Stage %d / %d"):format(stage, reqStageIndex)
		end
		-- THROUGH `SetProgress`, NOT `bar.Fill` (18.1). The fill is a child of the bar's `InnerBody`
		-- now, so that the pill's own clip trims it at the curved ends instead of the bar clipping a
		-- square hole and leaving two dark crescents. A direct index would throw here -- "Fill is not
		-- a valid member of Frame" -- inside the one refresh this panel has. `SetProgress` does the
		-- recursive lookup; `false` keeps this instant, which is what the direct write was.
		UITheme.SetProgress(rebirthLadderBar, frac, false)
		rebirthLadderBar.Label.Text = text
	end

	-- and tell the HUD tile whether to shine -- see the Rebirth beacon block
	if hudRefs.setRebirthReady then hudRefs.setRebirthReady(ready) end
end

-- ===== shared bits for the two "claim a reward" boards (Daily + Playtime) =====
-- Both boards are grids of chunky cards whose whole face is the hit area, with a green
-- coin dropped on the corner once the reward is banked.

-- claimed marker: sits on the Badge layer so it always clears the card's own gloss.
local function claimTick(card, diameter, maxText)
	local coin = Instance.new("Frame")
	coin.Name = "Checkmark"
	coin.Size = UDim2.new(0, diameter, 0, diameter)
	coin.Position = UDim2.new(1, -8, 0, 8)
	coin.AnchorPoint = Vector2.new(1, 0)
	coin.ZIndex = card.ZIndex + UITheme.Z.Badge
	coin.Visible = false
	coin.Parent = card
	styleCard(coin, UITheme.Color.Green, UDim.new(1, 0), 3)

	local tick = Instance.new("TextLabel")
	tick.Name = "Tick"
	tick.Size = UDim2.new(1, -10, 1, -14)
	tick.Position = UDim2.new(0.5, 0, 0.5, -3)
	tick.AnchorPoint = Vector2.new(0.5, 0.5)
	tick.BackgroundTransparency = 1
	tick.Text = "✓"
	tick.Parent = coin
	themeLabel(tick, maxText or 22)

	return coin
end

-- the card face is a Frame, so the click target is a transparent button laid over it.
local function claimOverlay(card)
	local btn = Instance.new("TextButton")
	btn.Name = "ClaimButton"
	btn.Size = UDim2.new(1, 0, 1, 0)
	btn.BackgroundTransparency = 1
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.ZIndex = card.ZIndex + UITheme.Z.Overlay
	btn.Parent = card
	return btn
end

-- ===== Daily Reward panel (all 7 days at once + big Day 7 hero card) =====
-- The one true modal in the HUD: a dimmed backdrop kills the rest of the screen so the
-- 7-day board is the only thing reading. The dim is a sibling one ZIndex under the shell.
local rewardDim = Instance.new("Frame")
rewardDim.Name = "RewardDim"
rewardDim.Size = UDim2.new(1, 0, 1, 0)
rewardDim.Position = UDim2.new(0, 0, 0, 0)
-- The kit's own shadow tint rather than pure black. Flat rgb(0,0,0) over a bright cartoon world
-- reads as a screenshot someone dimmed in an image editor; the violet-black that everything else
-- in the game is outlined and shadowed with reads as part of the same picture.
rewardDim.BackgroundColor3 = UITheme.Color.Shadow
rewardDim.BackgroundTransparency = 0.38
rewardDim.BorderSizePixel = 0
rewardDim.ZIndex = 19
rewardDim.Visible = false
rewardDim.Parent = screenGui

local rewardPanel = Instance.new("Frame")
hudRefs.rewardPanel = rewardPanel
rewardPanel.Name = "RewardPanel"
-- 536, up from 480. The day grid ends at y=412 and the banner already owns the bottom strip
-- (anchored at 1,-14, 44 tall), which left ten pixels between them -- so the code bar (5.1) is paid
-- for with panel height rather than by moving anything that was already here. Still smaller than
-- the Journal at 968x548, so the responsive fit in registerPanel has nothing new to solve.
--
-- 578 -> 638 (18.3), and 56 of those 60 pixels go into the reward glyphs. "vece ikone" was one of
-- three asks on this panel and the icon could not grow inside a 152 px tile: the day chip ends at
-- y = 30 and the two value lines own the bottom 50, which left the glyph 56 px in the middle of a
-- card 140 wide. The cell is 182 now (see CELL_H) and the glyph is 84 -- wider than the day chip
-- above it, which it was not before. The grid bottom moves 454 -> 514 against a code bar whose top
-- edge is 638 - 110 = 528.
--
-- The last 4 px are the pulse's clearance, and they are a measurement rather than a rounding: the
-- claimable tile now runs `UITheme.Attention` at peak 1.03 and a UIScale grows about the
-- AnchorPoint, which on these cells is (0,0) -- so all of the growth goes down and right. The hero
-- column is the worst case at 372 x 1.03 = +11.2 px, reaching y = 525.2 against a code bar at 528.
-- Still under the Journal's 968 width, so registerPanel's fit has nothing new to solve.
rewardPanel.Size = UDim2.new(0, 700, 0, 638)
rewardPanel.Position = PANEL_ANCHOR
rewardPanel.ZIndex = 20
rewardPanel.Visible = false
rewardPanel.Parent = screenGui
styleCard(rewardPanel, PANEL_SHELL, UDim.new(0, 22), 5)
registerPanel(rewardPanel)
panelClose(rewardPanel)

-- toggleOnly still owns visibility; the backdrop only mirrors it -- and now fades rather than
-- snapping, so the dim arrives with the panel's scale pop instead of a frame ahead of it.
--
-- The SHOW has to be ordered carefully: Visible goes true BEFORE the tween starts, or there is
-- nothing on screen to fade; and the transparency is reset to fully clear first, or a re-open
-- starts from wherever the last close left it. The HIDE is the mirror, and it leans on
-- animatePanel keeping the panel Visible for the length of its own close tween -- 0.12s, which is
-- what this is matched to. A backdrop that vanished instantly would leave the panel shrinking
-- against the full-brightness world for the last two frames.
rewardPanel:GetPropertyChangedSignal("Visible"):Connect(function()
	if rewardPanel.Visible then
		rewardDim.BackgroundTransparency = 1
		rewardDim.Visible = true
		TweenService:Create(rewardDim, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 0.38 }):Play()
	else
		local fade = TweenService:Create(rewardDim, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ BackgroundTransparency = 1 })
		fade.Completed:Connect(function()
			-- guarded: the player may have reopened the board inside those 0.12 seconds, and hiding
			-- the backdrop then would leave the panel floating over an undimmed world
			if not rewardPanel.Visible then
				rewardDim.Visible = false
			end
		end)
		fade:Play()
	end
end)

-- Converted to the shared accent band (17.x). The streak line was a card at y = 58 saying the same
-- kind of thing a subtitle says -- "what is true for you right now" -- so it IS the subtitle, and
-- the card goes. That is one register back and 36 px of panel that the grid did not have to pay
-- for. Sunny because Day 7 is the gold hero column this board streaks towards.
local rewardStreakLine = select(4, UITheme.PanelHeader(rewardPanel, {
	title = "📅 Daily Rewards!",
	subtitle = "Streak: 1 day",
	accent = UITheme.Color.Sunny,
}))

-- The streak card that used to live here at y = 58 is the header's subtitle now -- see the note on
-- the band above. It was a 240 x 34 orange capsule holding one sentence about the player's current
-- state, which is exactly what a subtitle is for, and at y = 58 it would now sit underneath the
-- band. Two top-level registers back (card + label) against the one handle the subtitle costs.

local GRID_X, GRID_Y = 25, 142
-- CELL_H 152 -> 182 (18.3). The 30 px buys the reward glyph: 56 -> 84 on a small tile and 130 -> 164
-- on the hero. Nothing else on the card moved except downward by the same amount, and the panel grew
-- by 56 (2 rows + no extra gutter) so the code bar below still clears the grid by ten.
local CELL_W, CELL_H, CELL_GAP = 140, 182, 8
local DAY7_W = 200

local rewardCells = {} -- [dayIndex] = { frame, dayLabel, headerPill, plinth, iconLabel, amountLabel, bonusLabel, checkmark, strokeInst, idleColor, isToday }

-- one day of the board. `big` is the Day 7 hero column on the right: same anatomy, gold
-- shell, everything scaled up so it reads as the prize you are streaking towards.
local function buildDayCell(dayIndex, size, position, big)
	local reward = GameConfig.DailyRewards[dayIndex]
	local frame = Instance.new("Frame")
	frame.Name = "Day" .. dayIndex
	frame.Size = size
	frame.Position = position
	frame.Parent = rewardPanel
	-- ===== SEVEN HUES, NOT ONE CREAM AND ONE LIME (18.3) =====
	--
	-- Every tile but the hero was rgb(255,250,195) -- a single cream at luminance 0.97 -- so the board
	-- had exactly one colour in it and a claimed day had no hue of its own to keep. "vise nijansi
	-- boja ubaci" is answered here, at the source, rather than by tinting states later.
	--
	-- The ramp is cool -> warm -> gold across the week, so the row itself reads as an escalation
	-- toward the Day 7 prize, and it is drawn entirely from `UITheme.Color`: Aqua, Lavender,
	-- Bubblegum, Coral, Peach, Sunny, Gold. Two rules decided the list. Nothing in it is GREEN,
	-- because Green is what a claimable tile turns and a day whose idle colour was already green
	-- would have no state left to show; and day 7 is Gold rather than the old lime, which is what the
	-- header band has said this board streaks toward since 17.x ("Sunny because Day 7 is the gold
	-- hero column"). `#dayHues` is indexed modulo its own length so a longer week cannot nil this.
	local dayHues = {
		UITheme.Color.Aqua, UITheme.Color.Lavender, UITheme.Color.Bubblegum,
		UITheme.Color.Coral, UITheme.Color.Peach, UITheme.Color.Sunny, UITheme.Color.Gold,
	}
	local idleColor = dayHues[((dayIndex - 1) % #dayHues) + 1]
	local strokeInst = styleCard(frame, idleColor, UDim.new(0, 16), big and 5 or 3.5)

	local headerPill = Instance.new("Frame")
	headerPill.Name = "HeaderPill"
	-- 88 on the hero card, not 110. The card is 200 wide, so a 110 pill centred on it runs from
	-- x=45 to x=155 and the OP badge in the top-left corner starts at x=6 -- they overlapped by 27px
	-- and the badge was drawn through the pill's border. 88 leaves a 6px gap against a 44 badge.
	headerPill.Size = UDim2.new(0, big and 88 or 80, 0, big and 30 or 24)
	headerPill.Position = UDim2.new(0.5, 0, 0, 6)
	headerPill.AnchorPoint = Vector2.new(0.5, 0)
	headerPill.ZIndex = frame.ZIndex + UITheme.Z.Badge
	headerPill.Parent = frame
	styleCard(headerPill, Color3.fromRGB(255, 255, 255), UDim.new(1, 0), 2)

	local dayLabel = Instance.new("TextLabel")
	dayLabel.Name = "DayLabel"
	dayLabel.Size = UDim2.new(1, 0, 1, 0)
	dayLabel.BackgroundTransparency = 1
	dayLabel.Text = "Day " .. dayIndex
	dayLabel.ZIndex = headerPill.ZIndex + UITheme.Z.Content
	dayLabel.Parent = headerPill
	themeLabel(dayLabel, big and 20 or 16, Color3.fromRGB(24, 18, 38))

	if big then
		local opBadge = Instance.new("Frame")
		opBadge.Name = "OpBadge"
		opBadge.Size = UDim2.new(0, 44, 0, 26)
		opBadge.Position = UDim2.new(0, 6, 0, 8)
		opBadge.ZIndex = frame.ZIndex + UITheme.Z.Badge + 1
		opBadge.Parent = frame
		styleCard(opBadge, UITheme.Color.Orange, UDim.new(1, 0), 2)

		local opLabel = Instance.new("TextLabel")
		opLabel.Name = "OpLabel"
		opLabel.Size = UDim2.new(1, 0, 1, 0)
		opLabel.BackgroundTransparency = 1
		opLabel.Text = "OP!"
		opLabel.ZIndex = opBadge.ZIndex + UITheme.Z.Content
		opLabel.Parent = opBadge
		themeLabel(opLabel, 16, Color3.fromRGB(255, 255, 255))
	end

	local icon = "\u{1F9EC}"
	if reward.potions and reward.shards then
		icon = "\u{1F31F}"
	elseif reward.potions then
		icon = "\u{1F9EA}"
	elseif reward.shards or reward.diamonds then
		icon = "\u{1F48E}"
	end

	-- ===== THE PLINTH THE REWARD SITS ON (18.3) =====
	--
	-- "da ima neku dimenziju da izgleda 3d". The tile is one flat rectangle with a glyph floating in
	-- the middle of it; a second plane behind the glyph is what turns the reward into an OBJECT
	-- mounted on the card rather than a sticker printed on it. It also carries the second half of
	-- "vise nijansi": at `shade(idle, -0.16)` every tile now shows two values of its own hue instead
	-- of one flat wash, which is fourteen fills across the board where there used to be two.
	--
	-- `NoShadow`, because this is a chip lying ON the tile and not a raised object of its own -- a
	-- soft sprite here would be a second shadow inside the one the tile already casts, which reads as
	-- fog rather than as layers. What gives it its edge is styleCard's own gradient and outline.
	local plinth = Instance.new("Frame")
	plinth.Name = "Plinth"
	plinth.Size = UDim2.new(0, big and 180 or 106, 0, big and 200 or 92)
	plinth.Position = UDim2.new(0.5, 0, 0, big and 44 or 34)
	plinth.AnchorPoint = Vector2.new(0.5, 0)
	plinth.ZIndex = frame.ZIndex + UITheme.Z.Content
	plinth:SetAttribute("NoShadow", true)
	plinth.Parent = frame
	styleCard(plinth, shade(idleColor, -0.16), UDim.new(0, big and 18 or 14), big and 4 or 3)

	-- ===== "VECE IKONE", MEASURED =====
	--
	-- Before: an 80 x 24 day chip above a glyph drawn at 56 px (the box was `(1,0,0,56)` and the art is
	-- `ScaleType.Fit`, so 56 is the whole of it) -- the reward, which is the only reason the panel
	-- exists, was drawn narrower than the label naming the day it falls on. After: 84 px on a small
	-- tile (+50%) and 164 on the hero (+26%), both square and both centred on the plinth, so the glyph
	-- is now the largest thing on its own card by a wide margin.
	--
	-- `maxTextSize` follows, because the slot is an ImageLabel only when `IconLibrary` has a drawing
	-- for that emoji and a TextLabel when it does not -- a 44 pt cap would have left the fallback
	-- glyph at its old size inside the new box, which is the failure mode where only SOME of the days
	-- got bigger. 0.86 x the box, the same ratio the currency pills use.
	--
	-- ZIndex is passed explicitly rather than defaulted, so the slot lands one above the plinth and
	-- its own `IconShadow` sibling (authored at zIndex - 1) lands ON the plinth instead of under the
	-- tile's opaque body, where liftChildren's by-name skip had been leaving it.
	local iconLabel = UITheme.IconSlot(frame, {
		name = "IconLabel", icon = icon, maxTextSize = big and 140 or 72,
		size = UDim2.new(0, big and 164 or 84, 0, big and 164 or 84),
		position = UDim2.new(0.5, 0, 0, big and 62 or 38),
		anchorPoint = Vector2.new(0.5, 0),
		zIndex = frame.ZIndex + UITheme.Z.Content + 1,
	})

	-- The two value lines are anchored to the BOTTOM edge, so growing the cell moved them with it and
	-- the only change here is the clearance they keep from the plinth: the plinth ends at y = 126 on a
	-- 182 px tile and the amount now starts at 128 (was 102 on a 152 px tile against a glyph ending at
	-- 90). Bonus sits 26 under it and closes 6 px short of the bottom rim.
	local amountLabel = Instance.new("TextLabel")
	amountLabel.Name = "AmountLabel"
	amountLabel.Size = UDim2.new(1, -12, 0, big and 34 or 24)
	amountLabel.Position = UDim2.new(0, 6, 1, big and -92 or -54)
	amountLabel.BackgroundTransparency = 1
	amountLabel.TextWrapped = true
	-- THE CARD SAYS WHAT THE DAY PAYS, on day 7 as much as on day 1. It briefly read
	-- "Chimpanzini Bananini" on the hero card, copied off a reference screenshot -- day 7 grants
	-- 23,000 DNA, a potion, 2 diamonds and 3 shards and no creature at all, so the one card players
	-- streak a whole week for was advertising a pet that does not come.
	amountLabel.Text = formatNumber(reward.dna) .. " DNA"
	amountLabel.Parent = frame
	themeLabel(amountLabel, big and 24 or 19, Color3.fromRGB(24, 18, 38))

	local bonusLabel = Instance.new("TextLabel")
	bonusLabel.Name = "BonusLabel"
	bonusLabel.Size = UDim2.new(1, -12, 0, big and 32 or 22)
	bonusLabel.Position = UDim2.new(0, 6, 1, big and -54 or -28)
	bonusLabel.BackgroundTransparency = 1
	local bonusParts = {}
	if reward.potions then table.insert(bonusParts, "\u{1F9EA} x" .. reward.potions) end
	if reward.shards then table.insert(bonusParts, "\u{1F48E} x" .. reward.shards) end
	if reward.diamonds then table.insert(bonusParts, "\u{1F48E} x" .. reward.diamonds) end
	bonusLabel.Text = table.concat(bonusParts, "  ")
	bonusLabel.Visible = #bonusParts > 0
	bonusLabel.Parent = frame
	-- DARK INK, THE SAME ONE THE LINE ABOVE USES, AND IT IS A FIX RATHER THAN A MATCH (18.3). This
	-- label was the one thing on the card still taking `themeLabel`'s white default, which meant a
	-- white glyph read entirely off its 4 px halo -- fine at 30pt, mush at 17. It has been sitting on
	-- a cream tile at luminance 0.97 since the board was written, and the collected state added below
	-- is a `DoneShade` at 0.90, so the surface under it is now light in every one of the three states
	-- and white was wrong in all of them. The darkest fill it can land on is Coral at 0.57, where
	-- this ink measures 4.8:1.
	themeLabel(bonusLabel, big and 22 or 17, Color3.fromRGB(24, 18, 38))

	local checkmark = claimTick(frame, big and 44 or 36, big and 26 or 22)

	local claimButton = claimOverlay(frame)
	claimButton.MouseButton1Click:Connect(function()
		local cell = rewardCells[dayIndex]
		if cell and cell.isToday then
			Remotes.ClaimDailyReward:FireServer()
		end
	end)

	rewardCells[dayIndex] = {
		frame = frame, dayLabel = dayLabel, iconLabel = iconLabel,
		amountLabel = amountLabel, bonusLabel = bonusLabel,
		checkmark = checkmark, strokeInst = strokeInst,
		-- three more handles, all so `refreshRewardPanel` can repaint a state rather than build one:
		-- the day chip changes colour with the state, the plinth has to follow the tile's fill or it
		-- stops being the same object, and `idleThickness` keeps the hero's 5 px rim off a literal.
		headerPill = headerPill, plinth = plinth,
		idleColor = idleColor, idleThickness = big and 5 or 4, isToday = false,
	}
end

for d = 1, 6 do
	local row = math.floor((d - 1) / 3)
	local col = (d - 1) % 3
	buildDayCell(
		d,
		UDim2.new(0, CELL_W, 0, CELL_H),
		UDim2.new(0, GRID_X + col * (CELL_W + CELL_GAP), 0, GRID_Y + row * (CELL_H + CELL_GAP)),
		false
	)
end
buildDayCell(
	7,
	UDim2.new(0, DAY7_W, 0, CELL_H * 2 + CELL_GAP),
	UDim2.new(0, GRID_X + 3 * (CELL_W + CELL_GAP) + 6, 0, GRID_Y),
	true
)

-- NO SECOND FOOTER LINE HERE. One was added at (0.5, 1, -16) reading "Join Tomorrow For A Special
-- Reward!", which is the exact rectangle `rewardBannerCard` occupies (anchored 1,-14, 44 tall) --
-- so it was a fixed sentence drawn underneath a card that already says the same thing and says it
-- with the real day number ("Come back tomorrow for Day 6!"). Invisible, duplicated, and a
-- top-level local on a file that lives against Luau's 200-register cap.

-- ================= CODES (Phase 5.1) =================
--
-- IN THE DAILY PANEL, not on a tile of its own. The right-hand cluster is a full 2x4 grid after the
-- Audio tile took order 8, and a ninth would make it five rows deep and shift every tile on screen.
-- This is also simply where it belongs: the Daily panel is the free-stuff screen, it already wears
-- the "NEW!" badge that pulls players into it, and a code is the same kind of thing as a login
-- reward -- something you are given rather than something you buy.
--
-- Inside an immediately-called function with one refresh on `hudRefs`, per the register-cap rule.
-- MOVED OUT (18.9) to `ReplicatedStorage.Modules.HUD.Codes` -- 95 lines, unchanged.
require(RS.Modules:WaitForChild("HUD"):WaitForChild("Codes"))(hudRefs)

local rewardBannerCard = Instance.new("Frame")
rewardBannerCard.Name = "BannerCard"
rewardBannerCard.Size = UDim2.new(1, -50, 0, 44)
rewardBannerCard.Position = UDim2.new(0.5, 0, 1, -14)
rewardBannerCard.AnchorPoint = Vector2.new(0.5, 1)
rewardBannerCard.Parent = rewardPanel
styleCard(rewardBannerCard, UITheme.Color.Purple, UDim.new(1, 0), 4)

local rewardBannerLabel = Instance.new("TextLabel")
rewardBannerLabel.Name = "BannerLabel"
rewardBannerLabel.Size = UDim2.new(1, -28, 1, -16)
rewardBannerLabel.Position = UDim2.new(0.5, 0, 0.5, -3)
rewardBannerLabel.AnchorPoint = Vector2.new(0.5, 0.5)
rewardBannerLabel.BackgroundTransparency = 1
rewardBannerLabel.Text = "Come back tomorrow for the next reward!"
rewardBannerLabel.Parent = rewardBannerCard
themeLabel(rewardBannerLabel, 24)

rewardButton.MouseButton1Click:Connect(function()
	toggleOnly(rewardPanel)
end)

local SECONDS_PER_DAY = 86400
hudRefs.SECONDS_PER_DAY = SECONDS_PER_DAY
local function dayNumber(timestamp)
	return math.floor((timestamp or 0) / SECONDS_PER_DAY)
end
hudRefs.dayNumber = dayNumber

-- ================= THE TWO WAYS INTO THE WHEEL (Phase 5.6 + 9.4) =================
--
-- Placed HERE rather than beside the rest of the Daily panel further up, and the reason is a Lua
-- one: `dayNumber` is declared a few lines above, so a closure written earlier in the file would
-- not have it in scope. The button is still parented to `rewardPanel`, which has existed since
-- line ~2351.
--
-- It reads the SAME day boundary the server does (RewardService.GetFreeSpinStatus) off the same
-- field, so the button can never offer a spin the server will refuse -- the property the evolve
-- button already has against GetEvolveStep.
-- MOVED OUT (18.9) to `ReplicatedStorage.Modules.HUD.WheelEntry` -- 124 lines, unchanged.
require(RS.Modules:WaitForChild("HUD"):WaitForChild("WheelEntry"))(hudRefs)

local function refreshRewardPanel()
	if not currentData then return end
	local data = currentData
	local today = dayNumber(os.time())
	local lastDay = dayNumber(data.LastRewardClaim)
	local canClaim = today > lastDay
	local streak = data.RewardStreak or 0

	rewardStreakLine.Text = "🔥 Streak: " .. streak .. " day" .. (streak == 1 and "" or "s")

	local upcomingStreak = streak
	if canClaim then
		upcomingStreak = (today == lastDay + 1) and (streak + 1) or 1
	end
	if upcomingStreak < 1 then upcomingStreak = 1 end
	local rewardIndex = ((upcomingStreak - 1) % #GameConfig.DailyRewards) + 1

	local claimedUpTo = canClaim and (rewardIndex - 1) or rewardIndex
	local todayIndex = canClaim and rewardIndex or nil

	-- ===== THREE STATES ON THREE DIFFERENT AXES (18.3) =====
	--
	-- What she photographed: six claimed days painted `Color.Locked` -- flat rgb(163,161,180) with a
	-- small green tick -- and one bright Day 7. "izgleda kao da dobijam rewards sto radim u
	-- mrtvacnici". `Locked` is the kit's REFUSAL swatch and four different states were reaching for
	-- it; a collected day is not a refusal, it is the record of a thing the player did, and painting
	-- it in the refusal colour is what made a panel full of achievement look like a panel full of
	-- nothing.
	--
	-- So the three states now differ on three different properties rather than on one:
	--
	--   claimable   FULL chroma -- `Color.Green`, the one hue this kit reserves for "act now" --
	--               plus the bright rim at +1 thickness, a READY_RIM day chip reading CLAIM!, and the
	--               single idle pulse. Loud by RULE now: every branch of it is applied here, off
	--               `isToday`, so it no longer depends on the day happening to be the gold one.
	--   collected   the day's OWN hue at about a third of the chroma (`UITheme.DoneShade`). Same
	--               colour, quieter -- a claimed potion day is still purple and a claimed diamond day
	--               is still cyan, so a week of collecting reads as a week of collecting. The green
	--               tick coin stays and is what separates it from a day that is merely not due yet.
	--   not yet     the day's own hue at full strength, dark rim, no tick, no chip.
	--
	-- None of the seven idle hues is green (see `dayHues`), so the claimable tile can never be
	-- confused with the tile beside it, whichever day of the week it lands on.
	for d = 1, 7 do
		local cell = rewardCells[d]
		if cell then
			local isClaimed = d <= claimedUpTo
			local isToday = (d == todayIndex)
			cell.isToday = isToday
			cell.checkmark.Visible = isClaimed
			-- state reads off the shell colour, not transparency: fading the card would
			-- eat the outline and the gradient that make it look moulded.
			local fill = cell.idleColor
			if isToday then
				fill = UITheme.Color.Green
			elseif isClaimed then
				fill = UITheme.DoneShade(cell.idleColor)
			end
			cell.strokeInst.Color = isToday and READY_RIM or OUTLINE_COLOR
			cell.strokeInst.Thickness = cell.idleThickness + (isToday and 1 or 0)
			cell.dayLabel.Text = isToday and "CLAIM!" or ("Day " .. d)
			setButtonColor(cell.frame, fill)
			-- The chip and the plinth follow the face, or the tile stops reading as one object: a
			-- white chip on a pale collected tile has no edge left, and a plinth still cut from the
			-- old hue looks like a sticker somebody forgot to update.
			setButtonColor(cell.headerPill, isToday and READY_RIM or UITheme.Color.PanelWhite)
			setButtonColor(cell.plinth, shade(fill, -0.16))

			-- ===== "DA SLJASTI STA JE BITNO" -- THE KIT'S OWN IDLE PULSE, FINALLY WIRED =====
			--
			-- `UITheme.Attention` has existed since the motion research landed and had ZERO call sites
			-- in the game: a `repeatCount = -1, reverses = true` tween at peak 1.05 over a 0.35 s beat
			-- with a 3.2 s gap, and the kit holds ONE slot so two things can never pulse at once.
			-- Priority 2 is the number its own comment block names for this exact caller.
			--
			-- ONLY WHILE THE PANEL IS OPEN, which is the conservative half rather than the clever one:
			-- the slot is global, this refresh runs on every DataUpdate whether the board is on screen
			-- or not, and a pulse held by a hidden panel would lock every future caller out of it for
			-- the session. Turning it off is the half that matters (§2.5), so the else-branch is
			-- unconditional -- it is safe on a tile that was never pulsing, it covers the day that was
			-- just claimed, and it covers "there is nothing to claim today" without a second test.
			--
			-- PEAK 1.03 RATHER THAN THE KIT'S 1.05, and it is geometry, not taste. A `UIScale` grows a
			-- GuiObject about its AnchorPoint and these cells are anchored (0,0), so every pixel of the
			-- growth goes down and right into the 8 px grid gutter. The hero column is 372 tall: at
			-- 1.05 it would reach 18.6 px past its own bottom edge and climb into the code bar, at 1.03
			-- it reaches 11.2 and the panel is sized to clear that (see rewardPanel.Size).
			if isToday and rewardPanel.Visible then
				UITheme.Attention(cell.frame, true, { priority = 2, peak = 1.03 })
			else
				UITheme.Attention(cell.frame, false)
			end
		end
	end

	if rewardBadge then
		rewardBadge.Visible = canClaim
	end

	if canClaim then
		rewardBannerLabel.Text = "🎉 Day " .. rewardIndex .. " is ready — click it to claim!"
		setButtonColor(rewardBannerCard, UITheme.Color.Green)
	else
		local nextDay = (streak % #GameConfig.DailyRewards) + 1
		rewardBannerLabel.Text = "Come back tomorrow for Day " .. nextDay .. "!"
		setButtonColor(rewardBannerCard, UITheme.Color.Purple)
	end
end
hudRefs.refreshRewardPanel = refreshRewardPanel

-- THE PULSE IS GATED ON `rewardPanel.Visible` (see the block inside the loop above) and this refresh
-- only runs on a DataUpdate -- which may have been minutes before the player opened the board. So
-- opening it re-asks the question; there is no cheaper way to start a pulse on a panel that was
-- already correct when it was hidden. A second connection rather than a branch inside the backdrop
-- fade above, because that one is written 400 lines earlier than this function exists and a closure
-- there would resolve `refreshRewardPanel` to a nil global -- the same upvalue trap `corner` and the
-- ZoneBuilder forward-declarations are documented for at the top of this file.
rewardPanel:GetPropertyChangedSignal("Visible"):Connect(function()
	if rewardPanel.Visible then
		refreshRewardPanel()
	else
		for _, cell in pairs(rewardCells) do
			UITheme.Attention(cell.frame, false)
		end
	end
end)

-- ===== Inventory panel (Potions) =====
local inventoryPanel = Instance.new("Frame")
hudRefs.inventoryPanel = inventoryPanel
inventoryPanel.Name = "InventoryPanel"
-- tall enough for the two counter cards, the three live-boost lines and a scroll deep enough to
-- show four of the nine bottles at once
inventoryPanel.Size = UDim2.new(0, 520, 0, 528)
inventoryPanel.Position = PANEL_ANCHOR
inventoryPanel.ZIndex = 20
inventoryPanel.Visible = false
inventoryPanel.Parent = screenGui
-- WHITE, WITH A BLUE RIM. Every panel in this HUD was PANEL_SHELL navy on the theory that it
-- matches the tiles, and against a bright zone that reads as a hole cut in the screen. The rim is
-- recoloured after styleCard rather than through it, because styleCard always uses OUTLINE_COLOR --
-- deliberately, so nothing built through it can drift from UITheme's own shell.
-- (The rim itself is `registerPanel`'s now -- every panel wears the same one, which is what this
-- comment wanted in the first place. What stays here is the gradient removal below, which is this
-- panel's own.)
do
	styleCard(inventoryPanel, UITheme.Color.PanelWhite, UDim.new(0, 22), 5)
	-- and FLAT. styleCard hangs a top-to-bottom gradient on everything it builds, which is what
	-- gives the coloured tiles their gloss -- but the same ramp over a white sheet just greys the
	-- bottom half of it, so the panel read as dirty rather than as paper.
	local grad = inventoryPanel:FindFirstChild("Gradient")
	if grad then grad:Destroy() end
end
registerPanel(inventoryPanel)
panelClose(inventoryPanel)

-- ===== THE TITLE IS INSIDE THE CARD NOW (17.x) =====
--
-- It used to sit at y = -54, i.e. ON THE 3D WORLD above the panel, with the tab strip at -34 beside
-- it. That was a real decision and it is written up below at `buildTabs` -- the panel's interior was
-- already full, so the title went where there was room. 11.13 spent that argument: every shop-side
-- panel opens with the same accent band, and one panel whose title floats over the scenery reads as
-- a rendering fault rather than as a style. Photographed 2026-08-16 and that is exactly how it read.
--
-- What paid for the 114 px this costs is the BoostStrip that used to own y = 16..106 -- ninety
-- pixels reserved for three timers that are almost never running. That readout is this header's
-- SUBTITLE now, which is where a "what is happening right now" line belongs anyway, and it is the
-- only handle kept: `refreshInventoryPanel` writes it once a second.
--
-- Aqua because that is the Potions tab's own colour in the strip below -- the same rule the Journal
-- follows with Lavender: a panel whose accent disagrees with the button that opened it reads as a
-- different screen. `IconifyLabel` is called by PanelHeader itself, so the 🎒 still becomes a drawing.
local inventoryBoostLine = select(4, UITheme.PanelHeader(inventoryPanel, {
	title = "\u{1F392} Items!",
	subtitle = "No potion running",
	accent = UITheme.Color.Aqua,
	maxTextSize = 34,
}))

-- ===== SECTION HEADINGS =====
-- Centred grey word with a rule running out of both sides. Two of them, written out rather than
-- put behind a helper: a helper for two call sites is a function you have to go and read.
-- INK on white, and passed EXPLICITLY -- themeLabel only rescues a dark colour to white when no
-- colour was given at all, so an explicit dark one survives, which is the whole point here.
local INK_ON_WHITE = Color3.fromRGB(108, 116, 140)
-- One heading now, not two: "Resources" titled a section that no longer exists (10.16).
-- 112 -> 144: header band 14 + 68 + 12 = 94, then the 34 px tab row and a 16 gap. Margin 18 -> 16,
-- which is the one every converted panel uses.
for _, sec in ipairs({ { "Potions", 144 } }) do
	local head = Instance.new("TextLabel")
	head.Name = "Section_" .. sec[1]
	head.Size = UDim2.new(1, -32, 0, 30)
	head.Position = UDim2.new(0, 16, 0, sec[2])
	head.BackgroundTransparency = 1
	head.Text = sec[1]
	head.Parent = inventoryPanel
	themeLabel(head, 26, INK_ON_WHITE)
	for _, side in ipairs({ -1, 1 }) do
		local rule = Instance.new("Frame")
		rule.Name = "Rule"
		rule.Size = UDim2.new(0.32, 0, 0, 3)
		rule.Position = UDim2.new(side < 0 and 0 or 0.68, 0, 0.5, -1)
		rule.BackgroundColor3 = Color3.fromRGB(224, 228, 238)
		rule.BorderSizePixel = 0
		rule.ZIndex = head.ZIndex
		rule.Parent = head
	end
end

-- ===== THE RESOURCES SECTION IS GONE (10.16) =====
--
-- It held two square cards under a "Resources" heading: a diamond reading `x0` and a green bottle
-- reading `x0`. Both were duplicates, and both cost the player something to read.
--
-- The DIAMOND is drawn permanently on the HUD's own capsule, bottom-left, with a `+` that opens the
-- shop -- so this was a second, worse copy of a number that is always on screen anyway, sitting
-- inside a modal that is not about diamonds. Diamonds are not a potion ingredient; nothing in this
-- panel spends one.
--
-- The BOTTLE COUNT was a total of the nine bottles listed on the shelf DIRECTLY ABOVE IT, each with
-- its own count, its effect and its duration. A sum of the rows you are already looking at is not a
-- resource, it is arithmetic -- and "🧪 x0" beside a shelf that says "you have no potions" is the
-- same sentence twice.
--
-- Six top-level locals went with them, which this file feels: it sits at 181 of Luau's 200-register
-- ceiling, and a panel that has now paid six back is a panel that stopped costing the HUD anything.
--
-- THE POTION SHELF.
--
-- There used to be one potion, held as a single integer, and this panel was a card reading
-- "POTIONS 3" with one USE button under it. There are nine bottles now -- DNA / XP / Luck, each in
-- Small / Medium / Large -- so the panel is the shelf: one row per bottle, how many are held, what
-- it does and how long it lasts, and a USE that drinks that exact one.
--
-- All nine rows are built ONCE here and only their text, colour and button state are written on
-- refresh. Rebuilding rows on every DataUpdate is what made the pet list flicker.
-- ===== THE BOOST STRIP IS GONE, AND ITS READOUT IS THE HEADER'S SUBTITLE (17.x) =====
--
-- It reserved BOOST_STRIP_H * 3 = 90 px at the top of the card for three timers, and the rows were
-- positioned by INDEX and merely toggled Visible -- so one running boost of the third kind drew
-- itself sixty pixels down an otherwise empty white band. Measured on the capture: one 30 px line
-- of dark text ("No potion running") in ninety pixels of nothing, directly under a title that was
-- floating outside the panel.
--
-- One line in the accent band says the same thing in the place a status line belongs, and the 90 px
-- pays for the band and the tab row that moved inside with it. Four top-level registers went with
-- the strip (BOOST_STRIP_H, boostStrip, boostRows, noBoostLabel) against the one the subtitle
-- handle costs -- this file is at Luau's 200-local ceiling and that is a net three back.
--
-- WHAT IT COSTS: the per-kind colour. Each row used to be tinted `kind.color`; one shared label
-- cannot be three colours, so the kind's EMOJI carries the identity instead. That is the same
-- trade the world-event bar made when its two cards became two pills.

-- ===== THE SHELF ENDS WHERE THE PANEL DOES, NOT 178 PX SHORT OF IT (16.7) =====
--
-- Authored at a fixed 204 in a 528-tall panel whose content starts at 146, so the list stopped at
-- y = 350 and the bottom third of the card was empty white. Measured: canvas 810 against 204 of
-- window -- **three of twelve rows visible**, in a panel with room for six, and the space that
-- would have shown the other three sitting blank underneath.
--
-- Relative height rather than a second magic number: 164 is the 146 this starts at plus the 18 of
-- bottom margin the panel is built with everywhere else, so the shelf follows the panel if the
-- panel is ever resized again. `PotionEmpty` covers the same rectangle and moves with it.
local potionScroll = Instance.new("ScrollingFrame")
potionScroll.Name = "PotionScroll"
-- 146 -> 186 and 18 -> 16: header 94 + tab row 34 + gap 16 = 144 for the "Potions" rule, + 30 + 12.
-- 202 is that 186 plus the 16 of bottom margin, so all four margins agree (16.7's rule, new numbers).
potionScroll.Size = UDim2.new(1, -32, 1, -202)
potionScroll.Position = UDim2.new(0, 16, 0, 186)
potionScroll.BackgroundTransparency = 1
potionScroll.BorderSizePixel = 0
potionScroll.ScrollBarThickness = 6
potionScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
potionScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
potionScroll.Parent = inventoryPanel

local potionListLayout = Instance.new("UIListLayout")
potionListLayout.Padding = UDim.new(0, 6)
potionListLayout.SortOrder = Enum.SortOrder.LayoutOrder
potionListLayout.Parent = potionScroll

-- WHAT AN EMPTY SHELF SAYS. Nine greyed rows reading x0 is a price list, not an inventory: it
-- tells a player who owns nothing that the screen is broken rather than that they have not bought
-- anything. One grey line over the whole shelf is the honest answer, and the rows go with it.
local potionEmptyLabel = Instance.new("TextLabel")
potionEmptyLabel.Name = "PotionEmpty"
potionEmptyLabel.Size = UDim2.new(1, -32, 1, -202) -- the shelf's rectangle exactly; see 16.7 above
potionEmptyLabel.Position = UDim2.new(0, 16, 0, 186)
potionEmptyLabel.BackgroundTransparency = 1
potionEmptyLabel.Visible = false
potionEmptyLabel.Text = "You don't have any Potions!"
potionEmptyLabel.ZIndex = inventoryPanel.ZIndex + UITheme.Z.Content
potionEmptyLabel.Parent = inventoryPanel
themeLabel(potionEmptyLabel, 26, Color3.fromRGB(168, 176, 194))

local potionRows = {}
for i, potion in ipairs(GameConfig.Potions) do
	local row = Instance.new("Frame")
	row.Name = "Potion_" .. potion.id
	row.Size = UDim2.new(1, -10, 0, 62)
	row.LayoutOrder = i
	row.Parent = potionScroll
	styleCard(row, potion.color, UDim.new(0, 14), 3)

	local icon = UITheme.IconSlot(row, {
		name = "Icon", icon = potion.sizeEmoji, maxTextSize = 30,
		size = UDim2.new(0, 46, 1, -10), position = UDim2.new(0, 8, 0, 5),
	})

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	-- 26 -> 24 and y 6 -> 4, to hand four pixels down to the sub-label below (15.16). This label is
	-- capped at 22px of text, so 24 is still more box than it can use.
	nameLabel.Size = UDim2.new(1, -250, 0, 24)
	nameLabel.Position = UDim2.new(0, 56, 0, 4)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = potion.emoji .. " " .. potion.shortName
	nameLabel.Parent = row
	themeLabel(nameLabel, 22)

	local subLabel = Instance.new("TextLabel")
	subLabel.Name = "SubLabel"
	-- TWO LINES, AND THE BOX IS SIZED FOR TWO (15.16). This started as "wider, and on ONE line":
	-- the box was widened from -224 to -186 and `TextWrapped` was set false. **Neither half of that
	-- worked.** The wrapping flag was set BEFORE `themeLabel`, and `themeLabel` sets `TextScaled`,
	-- which turns wrapping back on -- measured live, a fresh label goes false -> true the instant
	-- `TextScaled` is assigned, and only an assignment placed after it sticks. And the width was
	-- never enough anyway: measured at the 14px floor, the four longest strings need **300, 305,
	-- 310 and 320px** on one line against the **288** this box actually gets, so switching wrapping
	-- off would have truncated the "  •  20 min" tail rather than fixing anything.
	--
	-- It cannot get wider -- the count sits at -168 and the button at -100 -- so it gets taller.
	-- Wrapped at 288 those strings need 28px; the box is 30, sitting between the name label (which
	-- gave up 4px above) and the row's own 62, so there is clearance at both ends. This is the DNA
	-- bottles' row too, and they still take one line and sit at the top of it.
	subLabel.Size = UDim2.new(1, -186, 0, 30)
	subLabel.Position = UDim2.new(0, 56, 0, 28)
	subLabel.BackgroundTransparency = 1
	subLabel.TextXAlignment = Enum.TextXAlignment.Left
	subLabel.Text = ("%s  \u{2022}  %d min"):format(potion.effectText, potion.minutes)
	subLabel.Parent = row
	themeLabel(subLabel, 17, UITheme.Color.Cream)

	local countLabel = Instance.new("TextLabel")
	countLabel.Name = "CountLabel"
	countLabel.Size = UDim2.new(0, 62, 1, -10)
	countLabel.Position = UDim2.new(1, -168, 0, 5)
	countLabel.BackgroundTransparency = 1
	countLabel.Text = "x0"
	countLabel.Parent = row
	themeLabel(countLabel, 26)

	local useBtn = Instance.new("TextButton")
	useBtn.Name = "UseButton"
	useBtn.Size = UDim2.new(0, 92, 0, 42)
	useBtn.Position = UDim2.new(1, -100, 0.5, -21)
	useBtn.Text = "USE"
	useBtn.Parent = row
	styleButton(useBtn, UITheme.Color.Green, UDim.new(1, 0))
	useBtn.MouseButton1Click:Connect(function()
		Remotes.UsePotion:FireServer(potion.id)
	end)

	potionRows[potion.id] = { row = row, countLabel = countLabel, useBtn = useBtn }
end

-- No opener: the Inventory tile was removed from the left column. `inventoryPanel` stays built and
-- registered so registerPanel/toggleOnly bookkeeping and refreshInventoryPanel() are untouched.

local function refreshInventoryPanel()
	if not currentData then return end
	-- The two resource counts that used to be written here are gone with the cards -- see the
	-- RESOURCES note above. `totalPotions` stays because the shelf below still needs it to decide
	-- between the nine rows and the single "you have none" line.
	local totalPotions = GameConfig.CountPotions(currentData)

	local held = currentData.Potions
	if type(held) ~= "table" then held = {} end
	-- Owning nothing at all swaps the whole shelf for one line. Owning SOME still lists every
	-- bottle, greyed -- that list doubles as the reference for what the mystery shop can hand over,
	-- and hiding the ones you lack would remove the only place a player can see what exists.
	potionEmptyLabel.Visible = totalPotions <= 0
	potionScroll.Visible = totalPotions > 0
	for _, potion in ipairs(GameConfig.Potions) do
		local refs = potionRows[potion.id]
		local count = held[potion.id] or 0
		refs.countLabel.Text = "x" .. count
		refs.useBtn.Visible = count > 0
		UITheme.SetColor(refs.row, count > 0 and potion.color or UITheme.Color.Locked)
	end

	-- ONE LINE IN THE HEADER BAND, not three rows in ninety pixels of white -- see the note where the
	-- BoostStrip used to be. Two strings are composed because the subtitle is 22 px tall with a 12 px
	-- floor and TextScaled WRAPS rather than truncates: a second line is clipped by the band and
	-- simply disappears. One boost gets its full name; two or three drop the name and keep the emoji,
	-- which is the difference between ~52 characters and ~36 in a 412 px label.
	local running, brief = {}, {}
	for _, kind in ipairs(GameConfig.PotionKinds) do
		local boost = GameConfig.GetPotionBoost(currentData, kind.key)
		if boost then
			local remaining = math.max((boost.untilTs or 0) - os.time(), 0)
			local effect = boost.mult and ("x" .. boost.mult) or ("+" .. (boost.luckAdd or 0) .. "%")
			table.insert(running, ("%s %s %s  \u{2022}  %dm %02ds left"):format(kind.emoji, effect, kind.name, remaining // 60, remaining % 60))
			table.insert(brief, ("%s %s %dm%02ds"):format(kind.emoji, effect, remaining // 60, remaining % 60))
		end
	end
	inventoryBoostLine.Text = (#running == 0) and "No potion running"
		or (#running == 1) and running[1]
		or table.concat(brief, "   \u{2022}   ")
end
hudRefs.refreshInventoryPanel = refreshInventoryPanel

-- keep the boost countdowns ticking live while the panel is open
task.spawn(function()
	while true do
		task.wait(1)
		if inventoryPanel.Visible then
			refreshInventoryPanel()
		end
	end
end)

-- ===== THE INVENTORY TABS =====
-- The Pets panel and the Potions panel are two separate frames that were built pages apart, and
-- neither had to be rebuilt to join them: a tab is just `toggleOnly` pointed at the other one.
-- The strip is drawn on BOTH panels so whichever is open shows the same pair, with its own tab
-- held lit -- a tab row that disappears when you switch is a dead end.
--
-- Built inside an immediately-called function, NOT at the top level: MainUI is at Luau's 200-local
-- ceiling and one more top-level local silently deletes the entire HUD. See the Fusion and Season
-- Pass panels, which are wrapped for the same reason.
-- MOVED OUT (18.9) to `ReplicatedStorage.Modules.HUD.InventoryTabs` -- 96 lines, unchanged.
require(RS.Modules:WaitForChild("HUD"):WaitForChild("InventoryTabs"))(hudRefs)


-- ===== Robux Shop panel =====
-- ===== THREE COLUMNS, BECAUSE THIS IS THE SCREEN THAT TAKES THE MONEY (16.8) =====
--
-- 448 x 500 gave the grid 416 of width, which is two 192 cells and no room for a third, and 338 of
-- height, which is 1.9 rows of 180. Measured live: canvas 1,726 against a 338 window -- **the shop
-- showed a fifth of itself**, and the twenty products below the fold were reached by scrolling a
-- list whose first screen looks complete. Every other panel in this file is sized to its content;
-- this one was sized to the smallest thing it could get away with.
--
-- 640 x 640 is arithmetic, not taste: the grid then has 608 of width and three cells plus their two
-- 10 px gaps is 596, so a column fits with 12 px of slack rather than the 0 an exact 628 would have
-- left (a grid that wraps on a rounding drops to two columns and nothing reports it). Height 640
-- puts 478 in the window, 2.5 rows, and turns 9 rows of 2 into 6 rows of 3.
--
-- Nothing inside had to move. Both scrolls and the tab row are sized `(1, -32)` off the panel, so
-- they follow it, and `registerPanel` fits the whole thing to the viewport from the AUTHORED size --
-- on a 848 x 420 phone that is a scale of 0.59, which is exactly what that machinery is for.
local robuxPanel = Instance.new("Frame")
hudRefs.robuxPanel = robuxPanel
robuxPanel.Name = "RobuxPanel"
robuxPanel.Size = UDim2.new(0, 640, 0, 640)
robuxPanel.Position = PANEL_ANCHOR
robuxPanel.ZIndex = 20
robuxPanel.Visible = false
robuxPanel.Parent = screenGui
styleCard(robuxPanel, PANEL_SHELL, UDim.new(0, 22), 5)
registerPanel(robuxPanel)
panelClose(robuxPanel)

-- THE COUNTDOWN MOVES OUT OF THE TITLE. It used to be appended to it -- the refresh loop wrote
-- "Robux Shop   ⭐ pick resets in 3h 04m" into the title label every second, which meant the panel's
-- name changed length continuously and the leading 🛍️ had to be dropped to make room for a clause
-- that is not the panel's name. A subtitle is where a sentence about the contents belongs, so the
-- title is now a constant and `refreshRobuxShop` writes to `Header.Subtitle`.
--
-- Reached by path rather than by a handle for the usual reason: this file is at the 200-local cap.
UITheme.PanelHeader(robuxPanel, {
	title = "🛍️ Robux Shop",
	-- 15.23: a constant, and it stays a constant. The subtitle used to be overwritten every push
	-- with a countdown to the daily "pick" -- see refreshRobuxShop for why that clock is gone.
	subtitle = "Packs, potions and passes",
	accent = UITheme.Color.Green,
	maxTextSize = 30,
})

-- A SCROLLING FRAME, NOT A FRAME. Seventeen products in a 448 x 500 panel is nine rows of two,
-- about 1,400 px of cards in roughly 350 px of space: as a plain Frame everything below the third
-- row simply did not exist as far as the player was concerned. The class is the only thing that
-- changed here -- Visible still toggles the same way the tab code expects.
local robuxGrid = Instance.new("ScrollingFrame")
hudRefs.robuxGrid = robuxGrid
robuxGrid.Name = "RobuxGrid"
robuxGrid.Size = UDim2.new(1, -32, 1, -80)
robuxGrid.Position = UDim2.new(0, 16, 0, 64)
robuxGrid.BackgroundTransparency = 1
robuxGrid.BorderSizePixel = 0
robuxGrid.ScrollBarThickness = 6
robuxGrid.AutomaticCanvasSize = Enum.AutomaticSize.Y
robuxGrid.CanvasSize = UDim2.new(0, 0, 0, 0)
robuxGrid.Parent = robuxPanel

-- THE FIRST ROW'S RIBBON WAS BEING CUT IN HALF (11.13). Every value ribbon hangs 6 px ABOVE its own
-- card (`Position = 0.5, 0, 0, -6`), which is what makes it read as a ribbon rather than a caption --
-- and a ScrollingFrame clips at canvas y = 0, so on the top row those 6 px were simply gone. Nine
-- rows of tiles were fine and the two the player sees first were not. A top pad on the canvas gives
-- the overhang somewhere to be; the grid layout is untouched.
-- In an IIFE, not a top-level local and not a `do` block: registers are function-scoped in Luau, so
-- a `do ... end` would still take one of the twenty this file has left.
;(function()
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.Parent = robuxGrid
end)()

local robuxLayout = Instance.new("UIGridLayout")
robuxLayout.CellSize = UDim2.new(0, 192, 0, 180)
robuxLayout.CellPadding = UDim2.new(0, 10, 0, 12)
robuxLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
robuxLayout.SortOrder = Enum.SortOrder.LayoutOrder
robuxLayout.Parent = robuxGrid

-- ===== THE PRODUCT TILES =====
--
-- Inside an immediately-called function for the reason stated at the pass shop below: this file is
-- at Luau's 200-local register cap, and the tiles need per-card handles to update later. Everything
-- kept alive escapes as one function on hudRefs.
-- MOVED OUT (18.9) to `ReplicatedStorage.Modules.HUD.ProductTiles` -- 181 lines, unchanged.
require(RS.Modules:WaitForChild("HUD"):WaitForChild("ProductTiles"))(hudRefs)

-- ===== THE PASS SHOP: A SECOND TAB, NOT A SECOND PANEL =====
--
-- Two reasons it is a tab. From the player's side a pass and a product are the same decision --
-- "spend Robux" -- and splitting them across two entry points halves the chance either is seen.
-- And this file is at Luau's 200-LOCAL REGISTER CAP: a new panel needs several more top-level
-- locals and there are none to give. Everything below is inside an immediately-called function and
-- escapes only as a function on `hudRefs`, which costs one register no matter how much it holds.
-- A plain `do ... end` block is NOT enough -- that has deleted this whole HUD twice.
-- MOVED OUT (18.9) to `ReplicatedStorage.Modules.HUD.PassShop` -- 170 lines, unchanged.
require(RS.Modules:WaitForChild("HUD"):WaitForChild("PassShop"))(hudRefs)

-- ===== THE `+` ON THE CURRENCY CAPSULES =====
--
-- Twenty lines, and the highest-leverage conversion change in this file: the shop was reachable
-- only from a tile in the right-hand column, i.e. never at the moment a player discovers they are
-- short. The `+` sits on the number that just came up short.
--
-- It has to be built HERE, after robuxPanel exists, rather than beside the pills 2,500 lines up:
-- `robuxPanel` is a local declared later in the file, so a closure written up there could not see
-- it. Inside an immediately-called function, like everything else added to this file -- the register
-- cap does not care that these are only two small buttons.
-- MOVED OUT (18.9) to `ReplicatedStorage.Modules.HUD.CurrencyPlus` -- 27 lines, unchanged.
require(RS.Modules:WaitForChild("HUD"):WaitForChild("CurrencyPlus"))(hudRefs)

robuxButton.MouseButton1Click:Connect(function()
	toggleOnly(robuxPanel)
end)

-- ===== Playtime Gifts panel =====
local playtimePanel = Instance.new("Frame")
playtimePanel.Name = "PlaytimePanel"
playtimePanel.Size = UDim2.new(0, 790, 0, 294)
playtimePanel.Position = PANEL_ANCHOR
playtimePanel.ZIndex = 20
playtimePanel.Visible = false
playtimePanel.Parent = screenGui
styleCard(playtimePanel, PANEL_SHELL, UDim.new(0, 22), 5)
registerPanel(playtimePanel)
panelClose(playtimePanel)

-- Converted to the shared accent band (17.x). This panel had ALREADY grown its own title-plus-
-- subtitle pair by hand -- a 32 px label at y = 10 and a sentence at y = 54 -- which is the shape
-- PanelHeader standardises, so the conversion is a straight swap and costs two registers less than
-- it saves. The cells were at y = 92 and the band ends at 94, so they move 2 px and nothing else on
-- this panel has to be touched. Peach, warm, for a timer that pays you for staying.
UITheme.PanelHeader(playtimePanel, {
	title = "⏰ Playtime Gifts",
	subtitle = "The longer this session runs, the better the gift",
	accent = UITheme.Color.Peach,
})

local PLAYTIME_CELL_W = 142
local playtimeCells = {} -- [index] = { frame, statusLabel, checkmark, strokeInst }

for i, milestone in ipairs(GameConfig.PlaytimeGifts) do
	local frame = Instance.new("Frame")
	frame.Name = "Gift" .. i
	frame.Size = UDim2.new(0, PLAYTIME_CELL_W, 0, 182)
	frame.Position = UDim2.new(0, 16 + (i - 1) * (PLAYTIME_CELL_W + 12), 0, 94)
	frame.Parent = playtimePanel
	local strokeInst = styleCard(frame, UITheme.Color.Orange, UDim.new(0, 16), 4)

	local timeLabel = Instance.new("TextLabel")
	timeLabel.Name = "TimeLabel"
	timeLabel.Size = UDim2.new(1, -14, 0, 26)
	timeLabel.Position = UDim2.new(0, 7, 0, 8)
	timeLabel.BackgroundTransparency = 1
	timeLabel.Text = milestone.minutes .. " min"
	timeLabel.Parent = frame
	themeLabel(timeLabel, 24)

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "IconLabel"
	iconLabel.Size = UDim2.new(1, 0, 0, 52)
	iconLabel.Position = UDim2.new(0, 0, 0, 36)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Text = milestone.diamonds and "💎" or (milestone.potions and "🧪" or "🧬")
	iconLabel.Parent = frame
	themeLabel(iconLabel, 44)

	local amountLabel = Instance.new("TextLabel")
	amountLabel.Name = "AmountLabel"
	amountLabel.Size = UDim2.new(1, -12, 0, 24)
	amountLabel.Position = UDim2.new(0, 6, 0, 92)
	amountLabel.BackgroundTransparency = 1
	amountLabel.Text = formatNumber(milestone.dna) .. " DNA"
	amountLabel.Parent = frame
	themeLabel(amountLabel, 21, UITheme.Color.Cream)

	local bonusLabel = Instance.new("TextLabel")
	bonusLabel.Name = "BonusLabel"
	bonusLabel.Size = UDim2.new(1, -12, 0, 22)
	bonusLabel.Position = UDim2.new(0, 6, 0, 118)
	bonusLabel.BackgroundTransparency = 1
	local parts = {}
	if milestone.potions then table.insert(parts, "🧪 x" .. milestone.potions) end
	if milestone.diamonds then table.insert(parts, "💎 x" .. milestone.diamonds) end
	bonusLabel.Text = table.concat(parts, "  ")
	bonusLabel.Visible = #parts > 0
	bonusLabel.Parent = frame
	themeLabel(bonusLabel, 19)

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Size = UDim2.new(1, -12, 0, 26)
	statusLabel.Position = UDim2.new(0, 6, 1, -34)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "Locked"
	statusLabel.Parent = frame
	themeLabel(statusLabel, 20, UITheme.Color.Cream)

	local checkmark = claimTick(frame, 32, 20)

	local claimButton = claimOverlay(frame)
	claimButton.MouseButton1Click:Connect(function()
		Remotes.ClaimPlaytimeGift:FireServer(i)
	end)

	playtimeCells[i] = { frame = frame, statusLabel = statusLabel, checkmark = checkmark, strokeInst = strokeInst }
end

playtimeButton.MouseButton1Click:Connect(function()
	toggleOnly(playtimePanel)
end)

local playtimeSessionStart = os.time()
local playtimeClaimed = {}

Remotes.PlaytimeStatus.OnClientEvent:Connect(function(payload)
	if payload.sessionStart then
		playtimeSessionStart = payload.sessionStart
	end
	playtimeClaimed = {}
	if payload.claimed then
		for _, idx in ipairs(payload.claimed) do
			playtimeClaimed[idx] = true
		end
	end
end)

local function refreshPlaytimePanel()
	local elapsedSeconds = os.time() - playtimeSessionStart
	for i, milestone in ipairs(GameConfig.PlaytimeGifts) do
		local cell = playtimeCells[i]
		if cell then
			local isClaimed = playtimeClaimed[i] == true
			cell.checkmark.Visible = isClaimed
			if isClaimed then
				cell.statusLabel.Text = "Claimed"
				cell.statusLabel.TextColor3 = UITheme.Color.Cream
				cell.strokeInst.Color = OUTLINE_COLOR
				cell.strokeInst.Thickness = 4
				setButtonColor(cell.frame, UITheme.Color.Locked)
			else
				local remaining = milestone.minutes * 60 - elapsedSeconds
				if remaining <= 0 then
					cell.statusLabel.Text = "CLAIM!"
					cell.statusLabel.TextColor3 = UITheme.Color.White
					cell.strokeInst.Color = READY_RIM
					cell.strokeInst.Thickness = 5
					setButtonColor(cell.frame, UITheme.Color.Green)
				else
					cell.statusLabel.Text = string.format("in %dm %ds", remaining // 60, remaining % 60)
					cell.statusLabel.TextColor3 = UITheme.Color.Cream
					cell.strokeInst.Color = OUTLINE_COLOR
					cell.strokeInst.Thickness = 4
					setButtonColor(cell.frame, UITheme.Color.Orange)
				end
			end
		end
	end
end

task.spawn(function()
	while true do
		task.wait(1)
		refreshPlaytimePanel()
	end
end)


-- ===== Character Journal =====
-- A hundred characters, five for every stage, unlocked by evolving into that stage. This is the
-- one place a player can see what they have and what they are still missing.
--
-- Built as twenty rows of five cells rather than a flat grid of a hundred: the collection IS
-- per stage -- five Wolves, five Aliens -- and a grid loses that grouping entirely. A locked cell
-- keeps its shape and shows a padlock over the rarity colour, so the row always tells you how
-- close to complete it is at a glance.
--
-- Nothing here is created per refresh. All 120 instances are built once and refreshCharacterPanel
-- only writes text, colour and visibility -- rebuilding a hundred cells on every DataUpdate would
-- hitch the client every time a creature died.
local characterPanel = Instance.new("Frame")
hudRefs.characterPanel = characterPanel
characterPanel.Name = "CharacterPanel"
-- Wide enough for a second column. The collection is on the left and the ONE character you are
-- looking at is on the right, at a size where you can actually see it -- a grid of thumbnails with
-- no detail view is a contact sheet, and it is the reason the old panel needed a hover tooltip to
-- say anything at all about what the cursor was over.
-- 548 -> 604 with 11.14's header and 11.16's collection bar. The title used to hang 54 px ABOVE the
-- panel, so the space it occupied on screen was never counted in this number; folding it inside as a
-- band would otherwise have cost the list its third visible row for no change in footprint. 604 is
-- still under the old 548 + 54, so the panel got slightly SHORTER on screen while the list kept its
-- height and gained a header and a bar.
characterPanel.Size = UDim2.new(0, 968, 0, 604)
characterPanel.Position = PANEL_ANCHOR
characterPanel.ZIndex = 20
characterPanel.Visible = false
characterPanel.Parent = screenGui
-- Same white shell as the Items panel: flat white sheet, sky-blue rim, gradient removed. See the
-- longer note over inventoryPanel for why the gradient has to go on a white card.
do
	local shell = styleCard(characterPanel, UITheme.Color.PanelWhite, UDim.new(0, 22), 5)
	if shell then shell.Color = UITheme.Color.SkyBlue end
	local grad = characterPanel:FindFirstChild("Gradient")
	if grad then grad:Destroy() end
end
registerPanel(characterPanel)
panelClose(characterPanel)

-- ===== THE HEADER (11.14) =====
--
-- This panel's title used to be a bare 40px TextLabel at y = -54 -- i.e. FIFTY-FOUR PIXELS ABOVE THE
-- PANEL'S OWN TOP EDGE, floating on the dim with nothing behind it -- and the count sat separately
-- inside at y=14 in grey. That is the exact shape 11.13 replaced on the four shop-side panels, and
-- it is the plainest of the lot because the Journal is the widest panel in the game: 968 px of white
-- sheet opening with an unbacked line of text.
--
-- The count becomes the SUBTITLE rather than a second floating label, which is what the band is for.
-- It is the only line on the panel that answers "how far in am I", and 11.13's rule is that the
-- subtitle carries the thing a player would otherwise have to work out -- here, that the hundred
-- discs are not a lottery: they unlock strictly in order, so the next dim disc is always the one
-- being worked towards. See GameConfig.GetEvolveStep.
--
-- Lavender because that is the Journal tile's own colour in the right-hand column -- a panel whose
-- accent disagrees with the button that opened it reads as a different screen.
--
-- Only the subtitle is kept: refreshCharacterPanel rewrites the count and nothing rewrites the
-- title. That trades two top-level registers for one, which this file cares about more than most --
-- see the register note over the Journal's build block.
local characterCount = select(4, UITheme.PanelHeader(characterPanel, {
	title = "\u{1F4D2} Journal",
	subtitle = "Discovered 0 / 100",
	accent = UITheme.Color.Lavender,
	maxTextSize = 34,
	-- 68 -> 84 to carry the collection bar below the subtitle; see the bar itself
	height = 84,
}))

-- ===== HOW FULL THE COLLECTION IS, DRAWN (11.16) =====
--
-- It rides INSIDE the header band rather than above the list, which is the only reason it costs the
-- grid no height at all: the band already exists and had 20 px of dead space under its subtitle.
-- The alternative -- a bar between the header and the scroll -- would have taken a row of discs off
-- the visible list to say something the subtitle directly above it already says in words.
--
-- This is the one bar in the Journal. A bar per STAGE ROW was the obvious other candidate and is
-- wrong: a stage is five discs, and five discs already show three lit and two dark. A progress bar
-- over five steps is a tick box drawn the long way.
--
-- Parented through `characterCount.Parent` rather than through a second local for the header --
-- this file is at Luau's 200-register cap, and the subtitle's parent IS the band.
local characterFill = select(2, UITheme.ProgressBar(characterCount.Parent, {
	name = "CollectionBar",
	size = UDim2.new(1, -28, 0, 14),
	position = UDim2.new(0, 14, 0, 62),
	color = UITheme.Color.Gold,
	radius = UDim.new(1, 0),
	thickness = 3,
	shadow = false, -- it sits on a coloured band, not on the panel sheet; a drop shadow reads as a smear
	text = "",
	zIndex = characterCount.Parent.ZIndex + UITheme.Z.Content,
}))

local characterScroll = Instance.new("ScrollingFrame")
hudRefs.characterScroll = characterScroll
characterScroll.Name = "CharacterScroll"
-- the left column only: the detail card owns the right 322 and is built further down.
-- y = 94 is the header band's own bottom edge (top 14 + height 68 + gap 12), written out rather than
-- read off PanelHeader's second return value, which would cost a top-level register this file does
-- not have. -108 is that 94 plus the 14 of bottom margin, so the panel's four margins agree.
characterScroll.Size = UDim2.new(0, 598, 1, -124)
characterScroll.Position = UDim2.new(0, 16, 0, 110)
characterScroll.BackgroundTransparency = 1
characterScroll.BorderSizePixel = 0
-- The Journal is twenty rows deep and only three and a bit fit on screen, so the scrollbar is the
-- only thing telling a player there is anything below the fold. At 6px and default colouring it was
-- a pale hairline on a white panel -- the list looked like it simply ended, and the report was
-- "there is no scroll in the Journal". Thick, dark and fully opaque, against the panel's own ink.
characterScroll.ScrollBarThickness = 12
characterScroll.ScrollBarImageColor3 = Color3.fromRGB(58, 66, 88)
characterScroll.ScrollBarImageTransparency = 0
characterScroll.ScrollingDirection = Enum.ScrollingDirection.Y
characterScroll.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
-- measured off the rows rather than counted: a stage's row is as tall as the number of characters
-- it has needs, and that number is data (it went from five to ten once already)
characterScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
characterScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
characterScroll.Parent = characterPanel

local characterLayout = Instance.new("UIListLayout")
characterLayout.Padding = UDim.new(0, 8)
characterLayout.SortOrder = Enum.SortOrder.LayoutOrder
characterLayout.Parent = characterScroll

local characterCells = {}  -- [key] = { cell, icon, nameLabel, lock, strokeInst }
hudRefs.characterCells = characterCells

-- ===== HOW MANY PLAYERS OWN THIS ONE (Phase 5.7) =====
--
-- Read from `ReplicatedStorage.GlobalStats`, a StringValue the server republishes -- no remote, no
-- request handler, and a client that joins late gets the current value for free. `JSONDecode` is
-- local parsing, not a web call, so this works with HTTP requests switched off.
--
-- Decoded on demand and CACHED AGAINST THE RAW STRING, so clicking through a hundred discs costs
-- one decode rather than a hundred -- the payload is a ~200-key table.
--
-- Returns "" when the server has published nothing, which is what it does until MIN_SAMPLE players
-- exist. With four players on the board every owned character reads "100% own it", which is true
-- and worthless, so on a young game the Journal simply says nothing about rarity.
local statsRaw, statsTable = nil, nil
local function ownershipText(key)
	local holder = RS:FindFirstChild("GlobalStats")
	local raw = holder and holder.Value or ""
	if raw == "" then return "" end
	if raw ~= statsRaw then
		statsRaw = raw
		local ok, decoded = pcall(function()
			return game:GetService("HttpService"):JSONDecode(raw)
		end)
		statsTable = ok and decoded or nil
	end
	local players = statsTable and tonumber(statsTable.players) or 0
	if players <= 0 then return "" end
	local owners = tonumber((statsTable.chars or {})[key]) or 0
	-- NOBODY owning it is not "<0.1%", it is nothing to say. Running it through the brackets below
	-- printed "<0.1% own it" for a character with zero owners, which claims somebody has one --
	-- caught by running this function against a zero.
	if owners <= 0 then return "" end
	local pct = math.clamp(owners / players * 100, 0, 100)
	local shown
	if pct >= 10 then
		shown = ("%d%%"):format(math.floor(pct + 0.5))
	elseif pct >= 0.1 then
		shown = ("%.1f%%"):format(pct)
	else
		-- never "0.0%": somebody owns it, and rounding that to zero is the one thing a rarity line
		-- must not do
		shown = "<0.1%"
	end
	return ("  \u{2022}  %s own it"):format(shown)
end
hudRefs.ownershipText = ownershipText
local characterRows = {}   -- [stageIndex] = { row, headerLabel }
hudRefs.characterRows = characterRows

-- How many cells stand side by side. The rest wrap onto another line of the same stage's row --
-- five across is what fits this panel legibly, and a stage now carries ten.
local CHAR_PER_LINE = 5
hudRefs.CHAR_PER_LINE = CHAR_PER_LINE
-- ROUND cells, and the diameter is the whole cell. A rounded rectangle carrying an icon and a name
-- is a list row; a disc carrying an icon is a COLLECTION SLOT, and the difference is most of why
-- the reference reads as a scrapbook and this read as a settings screen. The name moved into the
-- hover card -- it was never legible at 15px inside a 68px box anyway.
-- Grown from 84 once the discs started carrying a rig instead of a glyph: a character in an 84px
-- circle inset for its own rim is drawn about 60px tall, which is a smudge.
local CHAR_CELL_H = 96
hudRefs.CHAR_CELL_H = CHAR_CELL_H
local CHAR_LINE_H = 132
hudRefs.CHAR_LINE_H = CHAR_LINE_H

-- Built inside an immediately-called function, NOT at the top level: MainUI is at Luau's 200-local
-- ceiling and one more top-level local silently deletes the whole HUD. The hover card has to be an
-- upvalue every cell handler can see, and this is the only way to have one without spending a
-- register. `characterCells` and `characterRows` are declared above and filled from in here.
-- MOVED OUT (18.9) to `ReplicatedStorage.Modules.HUD.JournalGrid` -- 790 lines, unchanged.
require(RS.Modules:WaitForChild("HUD"):WaitForChild("JournalGrid"))(hudRefs)

journalButton.MouseButton1Click:Connect(function()
	toggleOnly(characterPanel)
	if characterPanel.Visible and hudRefs.journalOnOpen then
		-- one frame, so the scrolling frame has been laid out and AbsolutePosition means something
		task.defer(hudRefs.journalOnOpen)
	end
end)

local function refreshCharacterPanel()
	if not currentData then return end
	local owned = currentData.Characters or {}
	-- one key, not a per-stage map: any character can be worn at any time now
	local wornKey = currentData.WornCharacter

	local have, total = GameConfig.CountCharacters(owned)
	-- The header's subtitle since 11.14. It says the RULE as well as the count, because the count on
	-- its own reads as a lottery scorecard -- and the discs are not a lottery, they are a queue.
	--
	-- ===== ...AND SINCE 12.6 IT NAMES THE FRONT OF THE QUEUE (12.6) =====
	--
	-- "They unlock in order, so the next one is always the cheapest" states the rule and then leaves
	-- the player to go and find the first dim disc themselves, in a list twenty rows deep that opens
	-- three and a bit rows from the top. The rule is worth saying once, in a comment and in the
	-- design; the ANSWER is worth saying every time the panel is open.
	--
	-- Both functions are the server's own: GetCollectionStage returns the lowest stage still missing
	-- an entry (capped at the stage reached) and NextCharacterForStage returns that stage's first
	-- unowned one -- the same pair DNAService hands a character over with. So this callout cannot
	-- drift from what an evolve will actually give, which a second "first dim disc" scan written
	-- here certainly would.
	--
	-- The nil case is NOT "collection complete": the cap means a player who has finished every stage
	-- they have reached also gets nil, with ninety discs still dark above them. That is the common
	-- case, not the edge one, and it is the one moment the panel can say plainly what the next
	-- evolve is for.
	local nextStage = GameConfig.GetCollectionStage(owned, currentData.StageIndex or 1)
	local nextEntry = GameConfig.NextCharacterForStage(owned, nextStage)
	local nextLine
	if nextEntry then
		local nextStageDef = GameConfig.Stages[nextStage]
		nextLine = ("  \u{2022}  Next up: %s %s"):format(nextStageDef and nextStageDef.emoji or "", nextEntry.name)
	elseif have < total then
		nextLine = "  \u{2022}  Evolve to open the next stage"
	else
		nextLine = "  \u{2022}  every one of them found"
	end
	characterCount.Text = ("Discovered %d / %d%s"):format(have, total, nextLine)
	-- and the same fraction as a bar in the band below it (11.16)
	characterFill.Size = UDim2.new(have / math.max(1, total), 0, 1, 0)

	for stageIndex in ipairs(GameConfig.Stages) do
		local entries = GameConfig.GetCharactersForStage(stageIndex)
		local n = 0
		for _, entry in ipairs(entries) do
			if owned[entry.key] then n += 1 end
		end
		local refs = characterRows[stageIndex]
		if refs then
			local stage = GameConfig.Stages[stageIndex]
			refs.header.Text = ("%s %s   %d/%d"):format(stage.emoji, stage.name, n, #entries)
			-- the stage you are standing at is the only one you can change right now, so it is
			-- the only one drawn in white
			-- dark ink on the white sheet; the stage you are standing at is the only one you can
			-- change right now, so it is the only one at full contrast
			refs.header.TextColor3 = (stageIndex == currentData.StageIndex)
				and Color3.fromRGB(46, 54, 74) or Color3.fromRGB(150, 158, 178)
		end
	end

	-- rigs come and go with the scroll and with what has just been discovered
	if hudRefs.journalSync then hudRefs.journalSync() end

	for key, refs in pairs(characterCells) do
		local isOwned = owned[key] == true
		-- exactly one tick in the whole panel: there is one character on the body
		local isWorn = wornKey == key
		local chosen = isWorn
		refs.lock.Visible = not isOwned
		-- a locked disc hides its chance too: the "?" is the whole message, and a percentage under
		-- something you have never seen is just noise
		refs.chance.Visible = isOwned
		-- the rig if this cell has one, the emoji until it does. Never both, or the glyph sits on
		-- top of the character it was standing in for.
		refs.art.Visible = isOwned and refs.rig ~= nil
		refs.icon.Visible = isOwned and refs.rig == nil
		refs.check.Visible = isOwned and isWorn
		-- NOTE (11.14): the two setButtonColor calls below paint NOTHING and are kept only because
		-- they cost nothing. The disc became a ring (see the cell build) -- BackgroundTransparency 1,
		-- Gradient and Gloss both destroyed -- so SetColor writes a BackgroundColor3 nobody can see
		-- and a BaseColor attribute nothing in the repo reads. The visible colour of a disc is
		-- entirely `strokeInst.Color` below. Anyone chasing "why does changing the disc colour do
		-- nothing" should start there and not here.
		-- THAT NOTE IS NO LONGER TRUE AND THE ARGUMENT IS PASSED ACCORDINGLY (2026-08-16). 15.28
		-- gave `setButtonColor` a body -- it paints `InnerBody`, its gradient and `ShadowBody` -- and
		-- 15.28 also moved the disc's fill INTO InnerBody, so this call is now the thing that decides
		-- what colour a disc is on every DataUpdate. It is handed the PALE fill the cell was built
		-- with, not the character's full-strength colour: the rim carries full strength, the fill is
		-- paled so the figure standing on it is not the same hue as its own background.
		if isOwned then
			setButtonColor(refs.cell, refs.rarity.pale or refs.rarity.color)
			-- the one being worn gets a bright rim, the same "this is active" signal the Daily
			-- board and the Mastery list already use
			-- Worn gets the full bright rim. A pick saved for ANOTHER stage gets the same colour at
			-- 40% strength and one step of thickness -- enough to find it again when you scroll to
			-- that stage, not enough to compete with the one you have on. No badge either way but
			-- the tick, so there is exactly one tick in the panel.
			-- The resting rim is the CHARACTER'S OWN COLOUR, not the shared outline. That colour used
			-- to be the disc's fill, and the fill is transparent now so the figure can be seen at all
			-- (see the cell build) -- if the rim did not pick it up, every unlocked disc in the
			-- Journal would be the same dark grey ring and the panel would lose its only at-a-glance
			-- difference between a hundred entries.
			refs.strokeInst.Color = isWorn and READY_RIM
				or (chosen and READY_RIM:Lerp(refs.rarity.color, 0.6) or refs.rarity.color)
			refs.strokeInst.Thickness = isWorn and 5 or (chosen and 5 or 4)
		else
			setButtonColor(refs.cell, UITheme.Color.Locked)
			refs.strokeInst.Color = OUTLINE_COLOR
			refs.strokeInst.Thickness = 3
		end
		-- WHAT THE DETAIL CARD IS SHOWING, on top of all of it. Worn is a state of the character;
		-- selected is a state of the cursor, and the panel needs to say both at once -- otherwise
		-- clicking a second character while wearing a first leaves nothing pointing at the card.
		if refs.selected then
			refs.strokeInst.Color = Color3.fromRGB(58, 66, 88)
			refs.strokeInst.Thickness = 5
		end
	end

	if hudRefs.journalPaintDetail then hudRefs.journalPaintDetail() end
end

-- Handed over rather than named directly by the Journal's own build, which runs above this line.
hudRefs.refreshCharacterPanel = refreshCharacterPanel

-- ===== Season Pass panel =====
-- Two pages behind one pair of tabs: the thirty-level TRACK, and the QUEST BOARD that is the only
-- thing which fills it. They belong together -- a track with no visible way to earn XP reads as
-- decoration, and a quest list with nothing to spend the XP on reads as busywork.
--
-- Nothing in here is created per refresh. The thirty columns (sixty reward cells) and the seven
-- quest rows are built once and `refresh` only writes text, colour and visibility -- the same rule
-- the Character Journal follows, and for the same reason: rebuilding ~500 instances on every
-- DataUpdate would stutter the screen on every creature kill.
--
-- BUILT INSIDE A FUNCTION, and a `do` block would NOT have done. Luau's 200-register limit is per
-- FUNCTION, and a do-block shares the enclosing function's budget: its locals are released at the
-- block's `end`, so blocks can run one after another, but the PEAK inside any one of them is this
-- file's ~191 top-level locals plus everything the block itself declares. A block buys about nine.
-- This panel declares forty, and it sits at the very bottom of the file where that peak is highest.
--
-- An immediately-called function has the same scoping and the same upvalues but its OWN 200 --
-- the only way to add anything substantial here short of moving it into a module. The leading `;`
-- stops Lua reading the `(` as a call on the preceding statement. Handles escape via `hudRefs`.
-- MOVED OUT (18.9) to `ReplicatedStorage.Modules.HUD.SeasonPass` -- 927 lines, unchanged.
require(RS.Modules:WaitForChild("HUD"):WaitForChild("SeasonPass"))(hudRefs)

-- ===== Notification popup (top-center, stacks) =====
-- Sits above every floating panel (ZIndex 20) and the Daily modal's dim (19), because a
-- claim confirmation usually fires while one of those is still open.
-- Parked at the TOP-CENTRE and narrow, not across the middle of the screen.
--
-- These were 420 px wide and anchored at screen centre, which put a stack of fat coloured bars
-- directly over the player's own character -- the one thing on screen the player is actually
-- looking at while fighting. A notification is a readout: it has to be legible and then get out of
-- the way. Half the width, above the action, and it never crosses the middle third of the screen.
local notifFrame = Instance.new("Frame")
notifFrame.Name = "NotifFrame"
notifFrame.Size = UDim2.new(0, 300, 0, 260)
notifFrame.Position = UDim2.new(0.5, 0, 0, 66)
notifFrame.AnchorPoint = Vector2.new(0.5, 0)
notifFrame.BackgroundTransparency = 1
notifFrame.ZIndex = 60
notifFrame.Parent = screenGui

local notifLayout = Instance.new("UIListLayout")
notifLayout.Padding = UDim.new(0, 6)
notifLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
notifLayout.SortOrder = Enum.SortOrder.LayoutOrder
notifLayout.Parent = notifFrame

-- At most this many on screen. A kill that pays DNA fires one, taking damage fires one, and a
-- fight produces both several times a second -- without a cap the stack grew down the screen
-- faster than the 2.5 s timer cleared it. The oldest goes when a new one arrives.
local NOTIF_MAX = 4

-- ===== THE TOAST, REBUILT =====
--
-- It was a flat rounded bar that appeared, sat there, and faded. Nothing about it moved, the
-- colour it was handed was used raw (so half of them came out muddy), and the message was one
-- 16 px wrapped line -- an emoji and its text run together at the same weight, which is why a
-- reward and an error read as the same grey event.
--
-- Four changes, in order of how much they do:
--
--   1. IT MOVES. Slides up and overshoots in on Back easing, drops and shrinks out. Motion is
--      what makes a notification register at the edge of vision while the player is fighting --
--      a static card in a corner is furniture, and the eye stops reporting furniture.
--   2. THE COLOUR IS PUSHED. `vividToast` lifts whatever it is handed to full saturation and a
--      high value before it reaches styleCard, so the gradient has somewhere bright to go. The
--      raw colours passed by the call sites are chosen to be readable as text, not as fills.
--   3. THE ICON IS ITS OWN CHIP. The leading emoji is split off into a round badge on the left,
--      lit in the toast's own colour. That is the whole difference between "a sentence" and "a
--      notification": you know what kind of event it is before reading a word.
--   4. A TIMER BAR drains along the bottom, so a toast that is about to go says so.
--
-- ALL OF IT LIVES INSIDE THIS FUNCTION. MainUI is at Luau's 200-register cap -- one more
-- top-level local deletes the entire HUD -- so the helpers below are nested, not hoisted.
--
-- 11.15 added the two the list above was missing. THE TIMER BAR IT ASKED FOR WAS ALREADY HERE --
-- point 4 above, shipped with the rebuild -- so the row is really two things:
--
--   5. THE CHIP CARRIES A DRAWING, not a glyph. 9.9 generated 44 icons keyed by emoji and every
--      other surface in the game routes through them; the toast was the last place still showing
--      the raw system emoji, which is a different art style at a different weight in the one
--      element whose whole job is to say what kind of event this is at a glance. Unmapped emoji
--      keep the glyph -- that is the icon layer's design, not a gap in it.
--   6. THE STACK IS RANKED. See UITheme.NotifyRank for why: the cap made the eviction victim the
--      OLDEST, and during a fight the four newest are all combat chatter, so the one-in-an-hour
--      message was the one reliably destroyed. Rank decides both who dies and who sits on top.
local function showNotification(text, color, rank)
	rank = rank or 1
	-- Monotonic, and parked on the frame rather than in a top-level local -- this file is at Luau's
	-- 200-register cap. It doubles as the tie-break inside a rank (older sits higher) and as the
	-- unique part of each toast's Name, which UIListLayout needs: with every child called "Notif"
	-- and every LayoutOrder equal, the sort order among them is not defined by anything.
	local seq = (notifFrame:GetAttribute("Seq") or 0) + 1
	notifFrame:SetAttribute("Seq", seq)

	-- EVICT THE LEAST IMPORTANT, OLDEST -- not simply the oldest.
	local live = {}
	for _, c in ipairs(notifFrame:GetChildren()) do
		if c:IsA("Frame") then table.insert(live, c) end
	end
	table.sort(live, function(a, b)
		local ra, rb = a:GetAttribute("Rank") or 1, b:GetAttribute("Rank") or 1
		if ra ~= rb then return ra < rb end
		return (a:GetAttribute("Seq") or 0) < (b:GetAttribute("Seq") or 0)
	end)
	for i = 1, #live - (NOTIF_MAX - 1) do
		live[i]:Destroy()
	end

	-- Full saturation, value floored at 0.92. A toast is a two-second flash on top of a busy
	-- world; anything less than the brightest version of its own hue loses to the scenery behind
	-- it. Hue is preserved exactly, so every call site keeps meaning what it meant.
	local base = color or UITheme.Color.Purple
	local h, s, v = Color3.toHSV(base)
	local vivid = Color3.fromHSV(h, math.max(s, 0.55), math.max(v, 0.92))

	-- Split a leading emoji off the message. Roblox emoji are multi-byte, so this takes
	-- everything up to the first space and only treats it as an icon if it is NOT plain ASCII --
	-- that keeps "Not enough DNA!" whole while lifting the 💎 off "💎 Diamond found!".
	local icon, body = nil, text
	local head, rest = text:match("^(%S+)%s+(.*)$")
	if head and #head <= 8 and not head:match("^[%w%p]+$") then
		icon, body = head, rest
	end

	local notif = Instance.new("Frame")
	-- unique, so the layout has a defined order to fall back on -- see `seq` above
	notif.Name = "Notif" .. seq
	-- 46 -> 52: a drawn icon needs more of the card than a glyph does. Four of these plus the 6 px
	-- padding is 232 against notifFrame's 260, so the stack still cannot reach its own bottom edge.
	notif.Size = UDim2.new(1, 0, 0, 52)
	notif.ZIndex = notifFrame.ZIndex
	-- HIGHER RANK SITS HIGHER, and within one rank the older one does. Negated because UIListLayout
	-- draws the SMALLEST LayoutOrder first and rank counts the other way; the 100000 spacing is wide
	-- enough that no sequence number can ever reach the next rank's band.
	notif.LayoutOrder = -rank * 100000 + seq
	notif:SetAttribute("Rank", rank)
	notif:SetAttribute("Seq", seq)
	notif.Parent = notifFrame
	styleCard(notif, vivid, UDim.new(1, 0), 3)

	-- THE POP. A UIScale on the card itself, so the outline, lip, gloss and text all scale as one
	-- object -- tweening Size instead would leave the stroke at its own thickness and the card
	-- would appear to grow a border. Back/Out overshoots and settles, which is the difference
	-- between something arriving and something being switched on.
	local pop = Instance.new("UIScale")
	pop.Scale = 0.55
	pop.Parent = notif
	TweenService:Create(pop, TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }):Play()

	if icon then
		local chip = Instance.new("Frame")
		chip.Name = "Chip"
		chip.Size = UDim2.new(0, 38, 0, 38)
		chip.Position = UDim2.new(0, 7, 0.5, -2)
		chip.AnchorPoint = Vector2.new(0, 0.5)
		chip.ZIndex = notif.ZIndex + UITheme.Z.Content
		chip.Parent = notif
		-- a shade DOWN from the card, not up: the badge has to separate from the fill it sits on,
		-- and the card is already at the top of its own range
		styleCard(chip, UITheme.Shade(vivid, -0.3), UDim.new(1, 0), 2)

		-- THE DRAWING IF THERE IS ONE, THE GLYPH IF THERE IS NOT (11.15). IconSlot decides which,
		-- so this call site never has to know the emoji table -- and an emoji with no art is a
		-- normal answer rather than a missing asset, which is why the fallback is the glyph and not
		-- a placeholder. Inset 6 px: the icons are drawn to fill their square and the chip is a
		-- circle, so a full-bleed icon clips its own corners on the rim.
		UITheme.IconSlot(chip, {
			icon = icon,
			size = UDim2.new(1, -6, 1, -6),
			position = UDim2.new(0.5, 0, 0.5, 0),
			anchorPoint = Vector2.new(0.5, 0.5),
			zIndex = chip.ZIndex + UITheme.Z.Content,
			maxTextSize = 22,
		})
	end

	local message = Instance.new("TextLabel")
	message.Name = "Message"
	-- left-aligned and inset past the chip when there is one. Centred text that starts at a
	-- different x on every toast is what made a stack of them read as noise.
	-- clears the chip: it starts at x=7 and is 38 wide, so its right edge is 45 and the words start
	-- at 53. The old 46 was written against a 32 px chip and would now sit one pixel off the rim.
	message.Size = UDim2.new(1, icon and -61 or -20, 1, -12)
	message.Position = UDim2.new(0, icon and 53 or 10, 0.5, -2)
	message.AnchorPoint = Vector2.new(0, 0.5)
	message.BackgroundTransparency = 1
	message.TextWrapped = true
	message.TextXAlignment = icon and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center
	message.Text = body
	message.Parent = notif
	themeLabel(message, 17)

	-- THE TIMER. Drains right to left along the bottom lip in the toast's own colour, lightened
	-- so it reads against the fill. Not styled as a card: it is a two-pixel readout, and an
	-- outline on it would be thicker than the bar.
	local timer = Instance.new("Frame")
	timer.Name = "Timer"
	timer.Size = UDim2.new(1, -22, 0, 3)
	timer.Position = UDim2.new(0.5, 0, 1, -8)
	timer.AnchorPoint = Vector2.new(0.5, 1)
	timer.BackgroundColor3 = UITheme.Shade(vivid, 0.55)
	timer.BorderSizePixel = 0
	timer.ZIndex = notif.ZIndex + UITheme.Z.Content
	timer.Parent = notif
	corner(timer, UDim.new(1, 0))
	TweenService:Create(timer, TweenInfo.new(2.5, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 3) }):Play()

	task.delay(2.5, function()
		if not (notif and notif.Parent) then return end
		-- OUT IS A MOVE AS WELL AS A FADE. Shrinking away on Back/In mirrors the entrance, so a
		-- toast leaving is as readable as one arriving -- a pure alpha fade on a busy background
		-- simply looks like the card was always half there.
		local info = TweenInfo.new(0.32)
		TweenService:Create(pop, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.In),
			{ Scale = 0.7 }):Play()
		-- a chunky toast is a whole stack of parts, so fade shell, lip, gloss, outline and
		-- the outlined text together instead of just the one label the flat version had.
		local shellTween = TweenService:Create(notif, info, { BackgroundTransparency = 1 })
		for _, d in ipairs(notif:GetDescendants()) do
			if d:IsA("TextLabel") then
				TweenService:Create(d, info, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
			elseif d:IsA("ImageLabel") then
				-- AN IMAGE DOES NOT FADE ON BackgroundTransparency, and 11.15 is what makes this
				-- branch necessary: before the icon chip carried a drawing there were no ImageLabels
				-- in a toast, so the generic GuiObject arm below covered everything. Without this the
				-- card, its outline and its words fade out and the icon stays at full opacity until
				-- Destroy blinks it away -- the one element left behind by its own exit animation.
				-- IconShadow is an ImageLabel too and is caught by the same line.
				TweenService:Create(d, info, { ImageTransparency = 1, BackgroundTransparency = 1 }):Play()
			elseif d:IsA("GuiObject") then
				TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
			elseif d:IsA("UIStroke") then
				TweenService:Create(d, info, { Transparency = 1 }):Play()
			end
		end
		shellTween:Play()
		shellTween.Completed:Wait()
		notif:Destroy()
	end)
end
hudRefs.showNotification = showNotification

-- ===== World popup =====
-- A small card that floats up off the player IN THE WORLD, not across the screen.
--
-- Everything that happens at a place -- a pet hatching out of the egg you are standing at, a
-- potion bought at the stall you are standing at -- is drawn here rather than as a screen banner.
-- A banner covers the thing the player walked over to look at, and it also reads as chrome: the
-- eye learns to ignore a bar that appears in the same place every time.
--
-- Sized in PIXELS and AlwaysOnTop for the same reason the damage numbers are: this is a readout,
-- so it stays legible at whatever distance the camera happens to be, and it must never end up
-- behind the scenery. It is small on purpose -- the point is that it does not take the screen.
local function worldPopup(text, subText, color)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		-- no body to hang it on (mid-respawn): fall back to the toast rather than losing the message.
		-- Rank 2, because everything routed through worldPopup is a one-off -- a fusion, an Apex pet
		-- drop -- and this branch is already the unlucky path. Losing it to a crit toast would be
		-- the second thing to go wrong for the same event.
		showNotification(text, color, 2)
		return
	end

	local host = Instance.new("Part")
	host.Name = "WorldPopup"
	host.Size = Vector3.new(1, 1, 1)
	host.Transparency = 1
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false -- must never become the answer to a combat ray
	host.CanTouch = false
	host.CastShadow = false
	-- measured off the head's own size: the body runs 1x to 9x across the twenty stages, and a
	-- constant offset is a hat at one end of the game and a kite at the other
	local startCF = head.CFrame * CFrame.new(0, head.Size.Y * 1.6 + 2, 0)
	host.CFrame = startCF
	host.Parent = workspace

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 210, 0, subText and 62 or 42)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = host

	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 1, 0)
	card.Parent = gui
	styleCard(card, color or UITheme.Color.Gold, UDim.new(0, 12), 3)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -14, subText and 0.56 or 1, -6)
	label.Position = UDim2.new(0.5, 0, 0, 3)
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.ZIndex = card.ZIndex + UITheme.Z.Content
	label.Parent = card
	themeLabel(label, 20)

	if subText then
		local sub = Instance.new("TextLabel")
		sub.Size = UDim2.new(1, -14, 0.36, 0)
		sub.Position = UDim2.new(0.5, 0, 1, -4)
		sub.AnchorPoint = Vector2.new(0.5, 1)
		sub.BackgroundTransparency = 1
		sub.Text = subText
		sub.ZIndex = label.ZIndex
		sub.Parent = card
		themeLabel(sub, 15, UITheme.Color.Cream)
	end

	-- rises and fades, held solid for the first half: a card that starts fading immediately is
	-- never read
	task.spawn(function()
		local t0 = os.clock()
		local LIFE = 1.9
		while host.Parent do
			local t = (os.clock() - t0) / LIFE
			if t >= 1 then break end
			local ease = 1 - (1 - t) * (1 - t)
			host.CFrame = startCF + Vector3.new(0, ease * 7, 0)
			local fade = math.clamp((t - 0.55) / 0.45, 0, 1)
			for _, d in ipairs(card:GetDescendants()) do
				if d:IsA("TextLabel") then
					d.TextTransparency = fade
					local s = d:FindFirstChildOfClass("UIStroke")
					if s then s.Transparency = fade end
				elseif d:IsA("GuiObject") then
					d.BackgroundTransparency = fade
				elseif d:IsA("UIStroke") then
					d.Transparency = fade
				end
			end
			card.BackgroundTransparency = fade
			RunService.RenderStepped:Wait()
		end
		host:Destroy()
	end)
end

-- ===== Purchase celebration =====
-- The complaint: "when I buy anything in the market I have no idea I bought it." That was literally
-- true -- PotionService fires { kind = "reward" } for both stalls and for the cauldron, and nothing
-- in this file had ever handled that kind, so the DNA came off the counter and the screen did not
-- change. Same for { kind = "bossDefeated" }.
--
-- Handling them as toasts would have been the minimum. This is deliberately louder: it lands in
-- the middle of the screen over everything, it punches in past its own size before settling, a
-- ring runs out past it, and a burst goes off on the player in the world -- because the purchase
-- happened at a stall you are standing at, and something that only happens on the HUD does not
-- read as having happened THERE.
local function celebratePurchase(text, color)
	color = color or UITheme.Color.Gold

	-- One at a time. An egg multi-hatch or a run of purchases would otherwise stack several of
	-- these on top of each other at the same screen position, which reads as one flickering card.
	for _, sg in ipairs(screenGui:GetChildren()) do
		if sg.Name == "PurchasePop" then sg:Destroy() end
	end

	local holder = Instance.new("Frame")
	holder.Name = "PurchasePop"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	-- high on the screen, clear of the character: this is a celebration, not a curtain
	holder.Position = UDim2.new(0.5, 0, 0.24, 0)
	holder.Size = UDim2.new(0, 330, 0, 74)
	holder.BackgroundTransparency = 1
	-- above the notification stack (60), which is itself above every floating panel
	holder.ZIndex = 80
	holder.Parent = screenGui

	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.new(0.5, 0, 0.5, 0)
	ring.Size = UDim2.new(0.6, 0, 0.6, 0)
	ring.BackgroundTransparency = 1
	ring.ZIndex = holder.ZIndex
	ring.Parent = holder
	corner(ring, UDim.new(1, 0))
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Thickness = 6
	ringStroke.Color = color
	ringStroke.Parent = ring

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.new(0.5, 0, 0.5, 0)
	card.Size = UDim2.new(0, 0, 0, 0)
	card.ZIndex = holder.ZIndex + 1
	card.Parent = holder
	styleCard(card, color, UDim.new(0, 20), 5)

	local label = Instance.new("TextLabel")
	label.Name = "Message"
	label.Size = UDim2.new(1, -30, 1, -18)
	label.Position = UDim2.new(0.5, 0, 0.5, 0)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.TextWrapped = true
	label.Text = text
	label.ZIndex = card.ZIndex + UITheme.Z.Content
	label.Parent = card
	themeLabel(label, 21)

	-- Back easing overshoots on purpose. An element that simply appears at its final size has no
	-- arrival, and the arrival IS the message.
	TweenService:Create(card, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(1, 0, 1, 0),
	}):Play()
	TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(1.6, 0, 2.6, 0),
	}):Play()
	TweenService:Create(ringStroke, TweenInfo.new(0.5), { Transparency = 1 }):Play()

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp then
		local scale = character:GetAttribute("BodyScale") or 1
		local host = Instance.new("Part")
		host.Name = "PurchaseBurst"
		host.Size = Vector3.new(1, 1, 1)
		host.CFrame = hrp.CFrame
		host.Transparency = 1
		host.Anchored = true
		host.CanCollide = false
		host.CanQuery = false -- it must never become the answer to a combat ray
		host.CanTouch = false
		host.CastShadow = false
		-- parented to workspace on the client only: confetti is not game state and no other machine
		-- has any business receiving it
		host.Parent = workspace

		local att = Instance.new("Attachment")
		att.Parent = host

		local bits = Instance.new("ParticleEmitter")
		bits.Color = ColorSequence.new(color, UITheme.Color.Cream)
		-- sized and thrown off the BODY, which runs 1x to 9x across the twenty stages: a fixed
		-- burst is a firework at stage one and a sprinkle of dust at stage twenty
		bits.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.4 * scale),
			NumberSequenceKeypoint.new(0.7, 1 * scale),
			NumberSequenceKeypoint.new(1, 0),
		})
		bits.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.7, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		bits.Lifetime = NumberRange.new(0.6, 1.1)
		bits.Speed = NumberRange.new(14 * scale, 30 * scale)
		bits.SpreadAngle = Vector2.new(180, 180)
		bits.Rate = 0
		bits.RotSpeed = NumberRange.new(-300, 300)
		bits.Acceleration = Vector3.new(0, -46 * scale, 0) -- it falls: confetti that drifts is smoke
		bits.LightEmission = 0.4
		bits.Parent = att
		bits:Emit(26)

		task.delay(2, function()
			host:Destroy()
		end)
	end

	task.delay(1.25, function()
		if not holder.Parent then return end
		local info = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(holder, info, { Position = UDim2.new(0.5, 0, 0.17, 0) }):Play()
		for _, d in ipairs(holder:GetDescendants()) do
			if d:IsA("TextLabel") then
				TweenService:Create(d, info, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
			elseif d:IsA("GuiObject") then
				TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
			elseif d:IsA("UIStroke") then
				TweenService:Create(d, info, { Transparency = 1 }):Play()
			end
		end
		task.delay(0.4, function()
			if holder.Parent then holder:Destroy() end
		end)
	end)
end

-- ================= state updates =================
local function refreshUI()
	if not currentData then return end
	local data = currentData
	local stage = GameConfig.Stages[data.StageIndex]

	stageLabel.Text = stage.emoji .. " " .. stage.name
	-- ONE SOURCE FOR WHAT THE EVOLVE BUTTON DOES. GetEvolveStep is the same function DNAService
	-- charges against, so the price printed here and the price taken there cannot drift apart --
	-- and a lit green button can never be answered by a red "not enough" toast.
	local step = GameConfig.GetEvolveStep(data)
	-- The stage name over the evolve bar and the number written on the bar are BOTH part of this
	-- refresh. They were built once with placeholder text ("\u{2B50} Cell", "0 / 50 DNA") and then
	-- never written to again, so a Star Weaver with 5.8T DNA still read "Cell / 0 / 50" all session.
	-- The (n/5) is where you stand INSIDE the stage: five skins is five evolves.
	evolveStageLabel.Text = ("\u{2B50} %s  (%d/%d)"):format(stage.name, step.have, step.stageTotal)
	-- (the top-right DNA card's write used to be here -- see the note at its former home. The pill
	-- in the currency stack below is the one readout now.)

	-- THE BOTTOM-LEFT CURRENCY STACK, WHICH NOTHING HAD EVER WRITTEN TO.
	--
	-- The three pills were built with a placeholder "0" and then never touched again, so DNA,
	-- Diamonds and Evolution Shards all read 0 for a whole session however much was earned. It was
	-- reported as "I get a diamond and it is not counted here", and the diamond is only where it
	-- shows: DNA has a second readout in the top-right card and the shard count has one in the
	-- Rebirth panel, so the dead pill was invisible for both of them.
	--
	-- The three `.Value` labels used to be cached in locals up beside the pills and were dropped to
	-- free registers -- MainUI is at Luau's 200 top-level local cap -- and the write that was
	-- supposed to replace them never landed. Reached through the frames instead, which costs no
	-- locals at all.
	local prevDiamonds = tonumber(diamondPill:GetAttribute("PrevVal") or 0)
	local prevShards = tonumber(shardPill:GetAttribute("PrevVal") or 0)

	dnaPill.Value.Text = formatNumber(data.DNA)
	diamondPill.Value.Text = formatNumber(data.Diamonds or 0)
	shardPill.Value.Text = formatNumber(data.EvolutionShards or 0)

	if (data.Diamonds or 0) > prevDiamonds and prevDiamonds > 0 then
		UITheme.Pulse(diamondPill)
	end
	if (data.EvolutionShards or 0) > prevShards and prevShards > 0 then
		UITheme.Pulse(shardPill)
	end

	dnaPill:SetAttribute("PrevVal", data.DNA or 0)
	diamondPill:SetAttribute("PrevVal", data.Diamonds or 0)
	shardPill:SetAttribute("PrevVal", data.EvolutionShards or 0)

	-- the starting hint has done its job the moment there is any DNA on the counter
	if data.DNA > 0 then
		local hint = screenGui:FindFirstChild("ClickHint")
		if hint and hint.Visible then hint.Visible = false end
	end

	if step.isMax then
		evolveButton.Text = "MAX EVOLUTION REACHED"
		progressBarFill.Size = UDim2.new(1, 0, 1, 0)
		evolveProgressLabel.Text = "MAX STAGE"
		setButtonColor(evolveButton, UITheme.Color.Locked)
	else
		-- ONE BAR, ONE CURRENCY. This used to draw `math.min(dnaPct, xpPct)` and then had to work out
		-- which of the two the number underneath should name, because an evolve cost both -- so the
		-- bar could jump backwards when the binding requirement swapped, and the label changed units
		-- underneath the player. XP is the only gate now (see DNAService.HandleEvolve), so the bar and
		-- the label can finally be the same fact.
		local xpPct = step.xpCost > 0 and math.clamp((data.XP or 0) / step.xpCost, 0, 1) or 1
		progressBarFill.Size = UDim2.new(xpPct, 0, 1, 0)
		evolveProgressLabel.Text = formatNumber(data.XP or 0) .. " / " .. formatNumber(step.xpCost) .. " XP"

		-- WHAT THE PRESS BUYS, WHICH IS NOT ALWAYS A STAGE. Four presses in five hand over the next
		-- skin and leave the body where it is; the fifth is the stage. Naming the stage on all five
		-- was the old text, and it would now be wrong four times out of five.
		--
		-- THE MOST IMPORTANT BUTTON IN THE GAME, AND IT WAS ILLEGIBLE: it used to print both
		-- requirements in full ("EVOLVE to \u{1F9A7} Gorilla (59.17B/60.00K DNA, 264/357 XP)"),
		-- 51 characters crushed by TextScaled into about 13px. The bar underneath already draws
		-- whichever requirement is furthest behind, so the button names one -- the one in the way.
		local goal
		if step.advancesStage and step.nextStage then
			goal = ("%s %s"):format(step.nextStage.emoji, step.nextStage.name)
		elseif step.entry then
			goal = ("%s %s (%d/%d)"):format(step.entry.emoji, step.entry.name, step.entryIndex, step.entryTotal)
		else
			goal = ("%s %s"):format(stage.emoji, stage.name)
		end

		-- The SAME condition the server checks, and now it is one term instead of two -- see
		-- DNAService.HandleEvolve. The button can never promise something the server refuses.
		local canEvolve = (data.XP or 0) >= step.xpCost
		if canEvolve then
			evolveButton.Text = "EVOLVE to " .. goal
		else
			evolveButton.Text = ("%s \u{2014} needs %s more XP"):format(goal,
				formatNumber(math.max(step.xpCost - (data.XP or 0), 0)))
		end
		-- LIT ONLY WHEN IT WILL WORK. A full-brightness green button that answers a press with a red
		-- error toast is the game telling the player they did something wrong for doing the one
		-- thing the screen was inviting them to do.
		setButtonColor(evolveButton, canEvolve and UITheme.Color.Green or UITheme.Color.Locked)
	end

	-- Same rule for both shop lists: a row you cannot afford is dimmed rather than left inviting.
	-- THE CAP IS SHOWN, NOT JUST OBEYED. Five levels per unlocked zone (GetUpgradeMaxLevel), so the
	-- row reads "Lv 5 / 5" and its price reads "ZONE LOCKED" rather than quoting a number the server
	-- will refuse -- an upgrade that silently stops being buyable is the same complaint as a claim
	-- button that does nothing. The diamond rows below have printed their own cap this way for ages.
	local upgradeMax = GameConfig.GetUpgradeMaxLevel(data)
	for key, refs in pairs(upgradeButtons) do
		local level = data.Upgrades[key]
		local cost = GameConfig.GetUpgradeCost(key, level, data)
		local maxed = (level >= upgradeMax)
		-- no spaces round the slash: this is a 84 px corner badge, not a sentence
		refs.levelLabel.Text = ("Lv %d/%d"):format(level, upgradeMax)
		refs.costLabel.Text = maxed and "ZONE LOCKED" or ("\u{1F9EC} " .. formatNumber(cost))
		-- 15.22: what this level is doing right now, in the unit the upgrade is bought for. Auto
		-- Collect prints the server's own per-second figure (see the stamp in DNAService's loop);
		-- the other three are arithmetic on the level alone, so they need nothing from the server
		-- and cannot drift from it. `__autoPerSec` is absent for one tick on a fresh join, which is
		-- what the `or 0` is for -- a tile that reads "+0/s" for a second is honest.
		if refs.effectLabel then
			if key == "AutoCollect" then
				refs.effectLabel.Text = ("\u{1F9EC} %s/sec"):format(formatNumber(data.__autoPerSec or 0))
			elseif key == "Income" then
				refs.effectLabel.Text = ("x%.2f DNA earned"):format(1 + level * 0.12)
			elseif key == "Luck" then
				refs.effectLabel.Text = ("+%d%% egg luck"):format(level * GameConfig.PetLuckPerUpgradeLevel)
			elseif key == "Speed" then
				refs.effectLabel.Text = ("+%.1f walk speed"):format(GameConfig.GetSpeedUpgradeBonus(data))
			end
		end
		if refs.button then
			-- Maxed is genuinely Locked -- there is nothing left to buy. Merely short of DNA is not,
			-- and it used to draw the same grey. See the token's own note in UITheme.
			setButtonColor(refs.button, maxed and UITheme.Color.Locked
				or (data.DNA >= cost) and UITheme.Color.Green or UITheme.Color.Unaffordable)
		end
	end

	for key, refs in pairs(diamondUpgradeButtons) do
		local def = GameConfig.DiamondUpgrades[key]
		local level = (data.DiamondUpgrades and data.DiamondUpgrades[key]) or 0
		local cost = GameConfig.GetDiamondUpgradeCost(key, level)
		refs.levelLabel.Text = "Level " .. level .. (def.maxLevel and (" / " .. def.maxLevel) or "")
		refs.costLabel.Text = (cost == math.huge) and "MAXED" or ("💎 " .. formatNumber(cost))
		if refs.button then
			setButtonColor(refs.button, (cost == math.huge) and UITheme.Color.Locked
				or ((data.Diamonds or 0) >= cost) and UITheme.Color.SkyBlue or UITheme.Color.Unaffordable)
		end
	end
end

-- ===== WELCOME BACK: THE ONE MOMENT THE GAME ASKS FOR ATTENTION INSTEAD OF WAITING FOR IT =====
--
-- Two finished features that never called out to anybody. The daily reward's only signal was a
-- 46 px badge on one tile in a cluster of nine -- and the `dailyReward` toast fires AFTER the
-- claim, so it is a receipt, not an invitation. The Season Pass was worse: `hudRefs.showSeasonPanel`
-- was defined and had no caller anywhere in the file, so nothing but the tile itself could ever
-- open that screen.
--
-- ONE CARD LISTING WHAT IS WAITING, each line with the button that goes there.
--
--   Not a toast. A toast is dismissed by a timer, and the seconds it would own are the seconds the
--   player is still walking out of the loading wipe.
--   Not an auto-open of the Daily panel either. Opening a screen the player did not ask for puts a
--   Claim button under a cursor that was not aimed at it, and it can only ever say one of the two
--   things -- the Season Pass would be exactly as silent afterwards as it is now.
--
-- GATED ON `TutorialDone`, which is what makes it "welcome BACK". A brand-new save has an unclaimed
-- daily too, and FirstJoin is driving its own four-beat guide over the same frames; two guides at
-- once is neither. Note this is the same field 6.3 chose and for the same reason -- `StageIndex == 1`
-- would have fired on every rebirth.
--
-- ONCE PER SESSION, ON THE FIRST PAYLOAD. Re-checking on later pushes would pop a card over the
-- middle of a fight the moment a quest ticked over, which is the opposite of what a join card is.
-- MOVED OUT (18.9) to `ReplicatedStorage.Modules.HUD.WelcomeBack` -- 213 lines, unchanged.
require(RS.Modules:WaitForChild("HUD"):WaitForChild("WelcomeBack"))(hudRefs)

-- ============================================================================
-- THE AURAS PANEL (15.27) -- every mutation the Splicer has ever given you, and
-- which one is on your body right now
-- ============================================================================
--
-- "I need somewhere to see which auras I have and which one is equipped" (2026-08-15). 15.24
-- answered half of that: the boost strip now names the ONE you are wearing, because that strip is
-- the answer to "what is affecting me right now". It cannot answer the other half -- a collection
-- is a screen, not a card -- and until this panel there was no screen: `data.SplicerFound` has
-- counted every roll since Phase 12 and NOTHING in the game read it.
--
-- Three decisions worth not re-deriving:
--
-- * The unfound entries are drawn, named and priced. That is the Journal's rule ("what is still
--   out there is the whole point of a collection screen"), and here it also does a second job --
--   the locked row is the only place in the game that says WHERE a mutation comes from.
-- * The chip carries the COUNT, not another glyph. All seven rows would otherwise show the same
--   emoji; the colour is what identifies an aura (it is literally the colour of the particles on
--   your body) and the number beside it is the one fact the save holds that nothing displayed.
-- * Wearing a WEAKER one is allowed. Both stats rise together with rarity, so this is never an
--   optimisation -- it is the look. The row prints the multiplier it costs you and 15.24's card
--   keeps printing the one you are on, so the trade is stated twice before it is made.
-- MOVED OUT (18.9) to `ReplicatedStorage.Modules.HUD.Quests` -- 200 lines, unchanged.
require(RS.Modules:WaitForChild("HUD"):WaitForChild("Quests"))(hudRefs)

Remotes.DataUpdate.OnClientEvent:Connect(function(data)
	local firstPayload = (currentData == nil)
	currentData = data

	-- AUDIO STARTS HERE, on the first payload, because this is the earliest point at which the client
	-- knows both that the server is alive and what this player's saved volumes are (4.6). Init resolves
	-- the three SoundGroups the server made, pushes the saved levels onto them and warms the asset
	-- cache off the main thread -- without that last part the first swing of a session is silent while
	-- the wav is still downloading.
	if firstPayload then
		SoundLibrary.Init(data.AudioVolumes)
	end

	-- The ambient bed follows the SAVE rather than the travel remote. ZoneTransition only fires when a
	-- player walks a gate, so driving it from there would leave the bed silent on join, wrong after a
	-- rebirth (which puts the save back to Forest without a transition) and stale after a respawn.
	-- SetAmbience is a no-op when the bed is already the right one, so calling it on every push -- the
	-- server sends one about every three seconds -- costs a table lookup and a string compare.
	SoundLibrary.SetAmbience(data.CurrentZone)

	refreshUI()
	refreshZonesPanel()
	refreshPetsPanel()
	if hudRefs.refreshFusionPanel then hudRefs.refreshFusionPanel() end
	if hudRefs.refreshSeasonPanel then hudRefs.refreshSeasonPanel() end
	if hudRefs.refreshPassShop then hudRefs.refreshPassShop() end
	if hudRefs.refreshAudioPanel then hudRefs.refreshAudioPanel(data) end
	if hudRefs.refreshCodes then hudRefs.refreshCodes(data) end
	if hudRefs.refreshSpins then hudRefs.refreshSpins() end
	-- the odds move with luck, and luck moves with a potion, a pet swap or a bought upgrade -- all
	-- of which arrive as a DataUpdate and none of which the panel could see on its own
	if hudRefs.refreshEggPanel then hudRefs.refreshEggPanel() end
	-- the DNA tiles are priced in the player's own stage, so they move when the player does
	if hudRefs.refreshRobuxShop then hudRefs.refreshRobuxShop() end
	refreshRebirthPanel()
	refreshRewardPanel()
	refreshMasteryPanel()
	refreshInventoryPanel()
	refreshCharacterPanel()
	if hudRefs.refreshAurasPanel then hudRefs.refreshAurasPanel() end

	-- LAST, and that is load-bearing: the card reads `hudRefs.seasonClaimCount()`, which is the
	-- number `refreshSeasonPanel` wrote a few lines up. Called before it, the count is 0 on the one
	-- payload that matters and the Season row would never be offered to anybody.
	if hudRefs.maybeWelcomeBack then hudRefs.maybeWelcomeBack(data, firstPayload) end
end)

-- ===== A BOUGHT UPGRADE HAS TO LOOK BOUGHT =====
--
-- The only feedback was a toast sliding in at the top of the screen, nowhere near the tile the
-- player just pressed, so the tile itself never acknowledged the click -- the number simply changed
-- on the next DataUpdate, which arrives a round trip later and reads as lag rather than as a
-- purchase.
--
-- IT REUSES THE UISCALE styleButton ALREADY PUT ON THE BUTTON. A GuiObject may hold only one
-- UIScale, so a second one added here would silently do nothing at all. That same scale is what
-- styleButton squashes to 0.96 on press and restores to 1 on release -- the two do not collide in
-- practice because the purchase confirmation comes back from the server well after mouse-up, and
-- if it ever did overlap the tween is the later writer and wins.
--
-- Inside a `do` block with only the function escaping onto hudRefs: this file is at Luau's 200-local
-- ceiling and the timing constants must not cost top-level registers.
do
	local PUNCH_UP = TweenInfo.new(0.11, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local PUNCH_DOWN = TweenInfo.new(0.17, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	-- Cream, not the old 22%-of-near-black: this is what a level badge settles BACK to after its
	-- purchase flash, and the badge it settles into is Cream now. The two must agree or every
	-- upgrade you buy turns its own badge black a second later.
	local BADGE_REST = UITheme.Color.Cream

	function hudRefs.punchUpgrade(key)
		local refs = upgradeButtons[key]
		if not refs or not refs.button or not refs.button.Parent then return end

		local scale = refs.button:FindFirstChildOfClass("UIScale")
		if scale then
			local up = TweenService:Create(scale, PUNCH_UP, { Scale = 1.12 })
			up.Completed:Connect(function()
				TweenService:Create(scale, PUNCH_DOWN, { Scale = 1 }):Play()
			end)
			up:Play()
		end

		local badge = refs.badge
		if not badge or not badge.Parent then return end
		-- the badge flashes green and settles back, so the eye is pulled to the number that changed
		setButtonColor(badge, UITheme.Color.Green)
		task.delay(0.45, function()
			if badge.Parent then setButtonColor(badge, BADGE_REST) end
		end)

		local pop = Instance.new("TextLabel")
		pop.Name = "Pop"
		pop.Size = UDim2.new(0, 48, 0, 26)
		pop.Position = UDim2.new(0.5, 0, 0, -2)
		pop.AnchorPoint = Vector2.new(0.5, 1)
		pop.BackgroundTransparency = 1
		pop.Text = "+1"
		pop.ZIndex = badge.ZIndex + UITheme.Z.Overlay
		pop.Parent = badge
		themeLabel(pop, 22, UITheme.Color.Green)

		local rise = TweenService:Create(pop, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, 0, 0, -32), TextTransparency = 1 })
		-- the outline has to fade WITH the glyph. themeLabel gives every label a UIStroke, and a stroke
		-- left at Transparency 0 while its text fades out leaves a "+1" written in outline hanging in
		-- the air -- the same trap the notification fade already documents.
		local popStroke = pop:FindFirstChildOfClass("UIStroke")
		if popStroke then
			TweenService:Create(popStroke, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Transparency = 1 }):Play()
		end
		rise.Completed:Connect(function() pop:Destroy() end)
		rise:Play()
	end
end

Remotes.Notify.OnClientEvent:Connect(function(payload)
	-- ONE line, not twenty. Which sound a notification makes is decided by SoundLibrary.NOTIFY_SOUND,
	-- a row per kind, so the branches below stay about wording and a new kind is a row rather than an
	-- edit in here. It runs BEFORE the branches on purpose: `showNotification` and `celebratePurchase`
	-- both tween, and the sound belongs to the moment the event arrived, not to the end of an animation.
	SoundLibrary.PlayNotify(payload)

	-- HOW MUCH THIS ONE IS WORTH KEEPING, computed once for the whole payload and handed to every
	-- toast below (11.15). It is one number per EVENT, not per wording, which is the same split
	-- PlayNotify is built on -- so a new kind is a row in UITheme.NotifyRank and nothing in here
	-- changes. Passed explicitly rather than left ambient: a toast raised from a button click a
	-- second later must not inherit the last server message's importance.
	local notifRank = UITheme.NotifyRank(payload.kind)

	-- THE `crit` BRANCH IS GONE, AND IT WAS NEVER REACHED (15.14). Its only sender was
	-- `DNAService.HandleClick` behind `Remotes.CollectClick`, which nothing in the game has fired
	-- for as long as combat has paid the DNA -- so this toast has been unreachable, not merely
	-- rare. A crit is now drawn at the kill by `CombatClient`, on the DNA pop that is already
	-- there: it is a fact about one creature, and this HUD's own rule is that those belong where
	-- they happen. `SoundLibrary.NOTIFY_SOUND.crit` and `UITheme.NotifyRank`'s row are left alone --
	-- both are inert for a kind that no longer arrives, and both are one row rather than a branch.
	if payload.kind == "upgrade" then
		local def = GameConfig.Upgrades[payload.upgrade]
		showNotification("⬆️ " .. def.displayName .. " upgraded to Lv." .. payload.level, Color3.fromRGB(90, 200, 255), notifRank)
		-- nil-guarded like every other hudRefs consumer: a panel that failed to build must not take
		-- the notification with it
		if hudRefs.punchUpgrade then hudRefs.punchUpgrade(payload.upgrade) end
	elseif payload.kind == "diamond" then
		showNotification("\u{1F48E} Diamond found!  +" .. (payload.amount or 1), Color3.fromRGB(130, 225, 255), notifRank)
	elseif payload.kind == "evolve" then
		-- TWO DIFFERENT EVENTS SHARE THIS PAYLOAD. Four presses in five hand over the next skin and
		-- leave the stage where it is, so announcing "EVOLVED into Worm" on all of them would be
		-- wrong four times out of five -- and what changed is the thing the player is looking at.
		-- The reveal card draws the picture; this line is the words that go with it.
		if payload.advanced then
			showNotification("\u{1F31F} EVOLVED into " .. payload.emoji .. " " .. payload.stage .. "!",
				Color3.fromRGB(190, 120, 255), notifRank)
		else
			showNotification(("\u{2728} NEW FORM: %s %s  (%d/%d)"):format(
				(GameConfig.GetCharacter(payload.character or "") or {}).emoji or "\u{2B50}",
				(GameConfig.GetCharacter(payload.character or "") or {}).name or payload.stage,
				payload.step or 1, payload.steps or 5), Color3.fromRGB(190, 120, 255), notifRank)
		end
	elseif payload.kind == "character" then
		-- THE CLIENT HALF OF A CHANGE THAT ONLY LANDED ON THE SERVER.
		--
		-- DNAService deliberately stopped sending `rarity` -- unlocks run in order now, so there is
		-- nothing rare about the next one along, and its comment says stamping "COMMON!" on
		-- something a player just earned reads as a disappointment. It sends `damagePct` instead.
		-- This branch never stopped reading `rarity`: GetRarity(nil) fell back to Common, so every
		-- character in the game was announced as "📒 NEW COMMON CHARACTER!" -- the exact words the
		-- server was rewritten to stop saying -- and the damage figure was never shown at all.
		local tint = (GameConfig.GetCharacter(payload.key or "") or {}).color or UITheme.Color.Lavender
		local gain = payload.damage and (("  \u{2694}\u{FE0F} %s Damage"):format(formatNumber(payload.damage))) or ""
		if payload.isNew then
			celebratePurchase(("📒 NEW CHARACTER!\n%s %s%s"):format(payload.emoji, payload.name, gain), tint)
		else
			showNotification(("%s %s%s"):format(payload.emoji, payload.name, gain), tint, notifRank)
		end
	elseif payload.kind == "questComplete" then
		-- finishing one is worth a toast; the reward itself is a separate, deliberate press, so the
		-- message says where to go rather than implying it has already been paid out
		showNotification(("%s %s \u{2014} ready to claim in %s!")
			:format(payload.emoji, payload.name, GameConfig.Season.emoji .. " Season"),
			UITheme.Color.Gold, notifRank)
	-- The "mutation" toast is gone: DNAService stopped sending it. Mutations roll every ten
	-- seconds and the banner fired over and over during ordinary play.
	elseif payload.kind == "zone" then
		showNotification("🗺️ NEW ZONE UNLOCKED: " .. payload.emoji .. " " .. payload.name .. "!", Color3.fromRGB(60, 160, 220), notifRank)
	elseif payload.kind == "pet" then
		-- Deliberately silent here now. The whole hatch -- the egg shaking, cracking, the rarity
		-- flash, the pet rising out of it and the card naming what it is -- belongs to HatchReveal
		-- (Phase 6.1), which is the only thing that knows when the reveal moment actually is. This
		-- branch used to draw the card immediately, which is a second before the egg had finished
		-- moving. Same reasoning as `creature` and `playerHurt` above.
	elseif payload.kind == "petDrop" then
		-- A PET OUT OF A CREATURE IS NOT A HATCH, AND MUST NOT BORROW ONE (11.6). The first version
		-- of the terrace drop sent `kind = "pet"` with `auto = true`, reasoning that the quiet
		-- presentation was the right one. It is not quiet -- it is the EGG sequence: HatchReveal's
		-- fallback shakes and cracks the egg on its podium, which for a kill up on a terrace is an
		-- animation several hundred studs away, on an egg nobody bought. Measured: the drop produced
		-- no visible feedback at all where the player was standing.
		--
		-- Drawn here instead, on the player, the way a fusion is -- see the note in
		-- `evolution-lab-feedback-placement`: a thing that happened in the world is shown in the
		-- world, at the place it happened.
		local rarity = GameConfig.GetRarity(payload.rarity)
		worldPopup(payload.emoji .. " " .. payload.name,
			payload.exclusive and "APEX DROP \u{2014} EGGS CANNOT HATCH THIS" or "DROPPED", rarity.color)
	elseif payload.kind == "fuse" then
		local rarity = GameConfig.GetRarity(payload.rarity)
		-- The enchant is named when one survived the fuse (13.2). A carried-forward enchant is a
		-- thing the player PAID for, so the one moment it could look like it was destroyed is the
		-- moment it has to be said out loud.
		worldPopup(payload.emoji .. " " .. payload.name,
			"FUSED → " .. payload.tier .. (payload.enchantName and ("  \u{2728} " .. payload.enchantName) or ""),
			rarity.color)
	elseif payload.kind == "enchant" then
		-- Drawn on the player like a fuse, and in the enchant's OWN colour -- the same rule the pet
		-- card follows, so the flash in the world and the label on the card are recognisably one
		-- thing. An upgrade and a kept roll say different words on purpose: "nothing changed" is a
		-- real outcome of this button and hiding it would make the panel read as broken.
		local def = GameConfig.GetEnchantDef(payload.rolled)
		if payload.upgraded then
			worldPopup(payload.emoji .. " " .. payload.name,
				"ENCHANTED → " .. (payload.rolledName or ""), def and def.color or UITheme.Color.White)
		else
			worldPopup((payload.rolledName or "?") .. " rolled",
				"KEPT " .. (payload.wornName or "NONE"), def and def.color or UITheme.Color.White)
		end
	elseif payload.kind == "creature" then
		-- Deliberately silent. A kill ALREADY writes its DNA in the world, floating up off the
		-- creature that died (CombatClient's popNumber) -- which is where a player fighting it is
		-- looking. Repeating it as a screen banner meant every kill printed the same fact twice, and
		-- at auto-attack speed the second copy was a wall of green bars over the character.
	elseif payload.kind == "playerHurt" then
		-- Same: this is drawn on the player's own head by CombatClient, in red, where the damage is
		-- actually happening. A banner for it was the single most frequent thing on screen.
	-- The `machine` branch is gone with the DNA Machine itself (10.19, owner's decision). Nothing
	-- sends that payload any more: MachineService was the only producer and it has been deleted.
	elseif payload.kind == "rebirth" then
		-- BOTH MULTIPLIERS, AS TOTALS, AND THEN WHERE THE LADDER POINTS NEXT. The player has just
		-- traded a whole climb for this; a delta ("+100%") describes the transaction, while the
		-- total describes what they now permanently are, which is the only framing under which a
		-- full reset reads as a gain. Naming the next milestone is what stops the screen going quiet
		-- at the exact moment the run restarts.
		local tail = ""
		if payload.nextTier and payload.nextStageIndex then
			local s = GameConfig.Stages[payload.nextStageIndex]
			tail = ("\nNext: Rebirth %d at %s %s"):format(payload.nextTier, s and s.emoji or "", s and s.name or ("Stage " .. payload.nextStageIndex))
		else
			tail = "\nThat was the last one — everything you earned is permanent."
		end
		celebratePurchase(("♻️ REBIRTH %d!\n\u{2694}\u{FE0F} x%.2f Damage  •  \u{1F9EC} x%.2f Income — forever%s"):format(
			payload.rebirths, payload.damageMult or 1, payload.incomeMult or 1, tail),
			Color3.fromRGB(190, 120, 255))
	elseif payload.kind == "dailyReward" then
		local text = "🎁 Day " .. payload.day .. " reward: +" .. formatNumber(payload.dna) .. " DNA"
		if payload.potions and payload.potions > 0 then
			text = text .. " +" .. payload.potions .. " 🧪"
		end
		if payload.shards and payload.shards > 0 then
			-- 🌟, not 💎: the shard pill on the HUD is a gold star, and the diamond line directly
			-- below this one is the gem -- with both reading 💎 the day-7 reward looked like two
			-- diamond payouts of different sizes
			text = text .. " +" .. payload.shards .. " 🌟 Shards"
		end
		if payload.diamonds and payload.diamonds > 0 then
			text = text .. " +" .. payload.diamonds .. " 💎 Diamonds"
		end
		showNotification(text, Color3.fromRGB(255, 180, 60), notifRank)
	elseif payload.kind == "stageMastery" then
		showNotification("⭐ " .. payload.emoji .. " " .. payload.stage .. " MASTERED! (" .. payload.owned .. "/" .. #GameConfig.Stages .. ")", Color3.fromRGB(255, 215, 70), notifRank)
	elseif payload.kind == "diamondUpgrade" then
		local def = GameConfig.DiamondUpgrades[payload.upgrade]
		showNotification("💎 " .. (def and def.displayName or payload.upgrade) .. " upgraded to Lv." .. payload.level .. "!", Color3.fromRGB(120, 200, 255), notifRank)
	elseif payload.kind == "potion" then
		local remaining = math.max(0, (payload.untilTs or 0) - os.time())
		local potion = payload.potionId and GameConfig.GetPotion(payload.potionId)
		showNotification(string.format("%s %s  \u{2022}  %dm %02ds left",
			potion and potion.emoji or "\u{1F9EA}",
			potion and potion.effectText or "Potion used",
			remaining // 60, remaining % 60), (potion and potion.color) or Color3.fromRGB(120, 255, 180), notifRank)
	elseif payload.kind == "offline" then
		-- A card, not a toast: this is the first thing a returning player sees and it is the entire
		-- argument for having come back. `away` and `capped` are computed server-side (see
		-- OfflineService) so the two sides cannot drift on how long "8h 20m" is, and the cap is stated
		-- rather than hidden -- crediting eight hours while implying it paid for three days is the
		-- kind of small lie players check.
		-- SHORT ON PURPOSE, and measured rather than guessed. `celebratePurchase` draws a 330x74 card
		-- whose label is 300x56, wrapped, and themeLabel floors text at 14px -- so a long second line
		-- does not shrink, it wraps to a third row and pins at that floor. "+1.48M DNA while you were
		-- away (8h) - max" is 41 characters and did exactly that; this is 29 at its longest, the same
		-- order as the rebirth and boss cards that already share this function.
		celebratePurchase(("\u{1F4A4} WELCOME BACK!\n+%s DNA earned in %s%s"):format(
			formatNumber(payload.amount or 0), payload.away or "?",
			payload.capped and " (max)" or ""), Color3.fromRGB(150, 190, 255))
	elseif payload.kind == "playtimeGift" then
		showNotification("⏰ Playtime Gift (" .. payload.minutes .. " min)! Reward claimed!", Color3.fromRGB(255, 150, 90), notifRank)
	elseif payload.kind == "bossRevive" then
		celebratePurchase(("\u{2694}\u{FE0F} REVIVED!\n%s is back to %d%%"):format(payload.name or "The boss", payload.pct or 0),
			UITheme.Color.Gold)
	elseif payload.kind == "spin" then
		-- The server has already rolled and already paid; this is the reveal, not the roll. The two
		-- rarest segments come up gold because landing one has to look different from landing the
		-- 34% one, or the wheel reads the same every time and stops being a wheel.
		local rare = (payload.segmentKey == "jackpot" or payload.segmentKey == "vault")
		celebratePurchase(("🎡 LUCKY SPIN!\n%s %s"):format(payload.emoji or "", payload.name or ""),
			rare and UITheme.Color.Gold or Color3.fromRGB(120, 200, 255))
	elseif payload.kind == "robuxPurchase" then
		celebratePurchase("🛍️ Purchased!\n" .. payload.name, Color3.fromRGB(90, 220, 130))
	elseif payload.kind == "reward" then
		-- Every shop purchase in the game lands here: both village stalls, the potion cauldron, and
		-- the Colosseum announcements. Until now this branch did not exist and all of it was silent.
		celebratePurchase(payload.message, payload.color or Color3.fromRGB(120, 226, 168))
	elseif payload.kind == "bossDefeated" then
		celebratePurchase("👑 " .. payload.name .. " defeated!\n+" .. formatNumber(payload.amount) .. " DNA", UITheme.Color.Gold)
	elseif payload.kind == "error" then
		showNotification("❌ " .. payload.message, Color3.fromRGB(200, 60, 60), notifRank)
	end
end)

-- ================= input =================
evolveButton.MouseButton1Click:Connect(function()
	Remotes.Evolve:FireServer()
end)

-- ================= AUDIO (Phase 4.6) =================
--
-- THE TILE FILLS THE ONE HOLE IN THE GRID. Right-column order 8 is the empty bottom-right corner
-- next to the lone order 7, so RIGHT_COUNT goes 7 -> 8 while `rows` stays ceil(COUNT/COLS) = 4 and
-- nothing already on screen moves.
--
-- The whole block is an immediately-called function with only its refresh escaping onto `hudRefs`,
-- because this file is at Luau's 200-local ceiling. A `do ... end` is NOT enough -- see the note
-- over the Season Pass panel for the two times that mistake deleted the entire HUD.
-- MOVED OUT (18.9) to `ReplicatedStorage.Modules.HUD.AudioPanel` -- 188 lines, unchanged.
require(RS.Modules:WaitForChild("HUD"):WaitForChild("AudioPanel"))(hudRefs)


-- ================= shop counters that open a panel =================
--
-- Two of the three shop kinds do not need the server at all: Pet Fusion and the two Upgrade
-- Emporium counters only have to OPEN a panel this HUD already builds. So the client listens for
-- its own prompt rather than firing a remote and waiting for the server to tell it what it already
-- knows -- there is no remote and no server handler for these, and the walk-up-and-press feels
-- instant because nothing round-trips.
--
-- The counter says which panel it is through a `ShopPanel` attribute that ZoneBuilder stamps on
-- the prompt, so a new shop is a new attribute value and one line here, not a new remote.
local ProximityPromptService = game:GetService("ProximityPromptService")

local shopPanels = {
	pets = petsPanel,
	mastery = masteryPanel,
	robux = robuxPanel,
}


-- ================= EGGS (10.19) =================
--
-- "Hatch and auto-hatch need their own panel; selecting an egg should first show what your chances
-- are of getting which creature, and then in that same tab give you hatch and auto-hatch."
--
-- Before this the ONLY egg UI in the whole game was two ProximityPrompts on a podium, and the odds
-- existed only as a SurfaceGui painted on the stall wall -- quoted at luck 0, which is nobody's
-- actual luck. Auto Hatch was worse: the remote, the pass and the whole `DriveAutoHatch` driver
-- were written and running, and **nothing in the game could turn it on**.
--
-- WHY THE ODDS ARE HONEST HERE AND WERE NOT ON THE WALL. `GameConfig.GetLuckPercent` moved out of
-- DNAService this session precisely so this panel could call it -- see the note there. The number
-- shown is the number `rollAndInsert` rolls against, because both call one function: since 11.5
-- that function is `GetPetLuckPercent`, the shared total plus the shop's Luck upgrade.
--
-- The whole block is an immediately-called function with only `hudRefs.refreshEggPanel` escaping,
-- because this file is at Luau's 200-local ceiling. A `do ... end` is NOT enough -- see the note
-- over the Season Pass panel for the two times that mistake deleted the entire HUD.
-- MOVED OUT (18.9) to `ReplicatedStorage.Modules.HUD.EggShop` -- 414 lines, unchanged.
require(RS.Modules:WaitForChild("HUD"):WaitForChild("EggShop"))(hudRefs)

-- ===== The two tile columns, fitted to the screen =====
-- Both columns are laid out in raw pixels: the left runs DOWN from y=100, the right runs UP from
-- the bottom, five tiles at a 96 pitch. That needs 596px of height, and a Roblox phone viewport is
-- about 420 -- so on a phone the top two tiles of the right column (Journal and Zones) were drawn
-- at y=-176 and y=-80. Entirely off the screen, and the Journal tile is the only way into the
-- character collection at all.
--
-- Rather than a scrollable menu or a hamburger, the columns just tighten: the gap closes first,
-- and only then do the tiles themselves shrink, down to a 40px floor. On a desktop viewport this
-- resolves to within a few pixels of the hand-authored layout, so nothing moves for the people
-- already playing it.
--
-- Inside a function, and finding its tiles by attribute rather than from a table, because this
-- file is at Luau's 200-local ceiling -- see the note over the Season Pass panel.
-- MOVED OUT (18.9) to `ReplicatedStorage.Modules.HUD.TileColumnFit` -- 88 lines, unchanged.
require(RS.Modules:WaitForChild("HUD"):WaitForChild("TileColumnFit"))(hudRefs)

ProximityPromptService.PromptTriggered:Connect(function(prompt, playerWhoTriggered)
	-- PromptTriggered fires on every client for every player, so a teammate walking up to the
	-- fusion lab must not open the panel on your screen
	if playerWhoTriggered ~= player then return end
	local which = prompt:GetAttribute("ShopPanel")
	if not which then return end
	-- Fusion is handled by name rather than through the table above: its panel is built inside a
	-- block and only escapes as a function on hudRefs, which already does the toggle and the refresh.
	-- ===== AND SINCE 15.25 IT IS THE ONLY WAY IN AGAIN =====
	--
	-- 12.8 added a Market tile whose flyout opened this panel and the egg panel from anywhere, and
	-- wrote here "do not delete that tile" -- because fusion had been reported as a missing feature
	-- by players who had not yet walked into Volcano. The owner removed the tile anyway on
	-- 2026-08-15 ("I do not need the Market button"), which is her call and is recorded as 15.25.
	--
	-- WHAT THAT COSTS, so the next reader does not have to rediscover it: fusing now requires
	-- standing at the Pet Fusion Lab counter in Volcano (zone 4 -- it was moved down from 5 for the
	-- same discoverability reason). The egg panel is unaffected in practice, since every zone has a
	-- podium. If the report ever comes back, the cheap fix is a Fusion door on the Pets panel's
	-- action row rather than a tenth tile: that row is at 678 px of 744 and both wide buttons would
	-- have to give up 30 px each, which is a measurement to take and not a guess.
	if which == "fusion" then
		if hudRefs.showFusionPanel then hudRefs.showFusionPanel() end
		return
	end
	-- Same shape as fusion, and same reason: the egg panel is built inside a block and only escapes
	-- as functions on hudRefs. It is handed the prompt's `EggKey` so it opens on the egg that was
	-- pressed rather than on Basic (11.18) -- which is the one thing the Market flyout added in 12.8
	-- cannot do, and why this path is still the one that matters.
	if which == "eggs" then
		if hudRefs.showEggPanel then hudRefs.showEggPanel(prompt:GetAttribute("EggKey")) end
		return
	end
	if which == "group" or prompt.Name == "ChestPrompt" then
		if hudRefs.showGroupRewards then hudRefs.showGroupRewards() end
		return
	end
	local panel = shopPanels[which]
	if panel then
		toggleOnly(panel)
		if which == "pets" then
			refreshPetsPanel()
		elseif which == "mastery" then
			refreshMasteryPanel()
		end
	end
end)

-- ============================================================================
-- GROUP & COMMUNITY REWARDS MODAL (Phase 5.5)
-- ============================================================================
-- MOVED OUT (18.9) to `ReplicatedStorage.Modules.HUD.GroupRewards` -- 199 lines, unchanged.
require(RS.Modules:WaitForChild("HUD"):WaitForChild("GroupRewards"))(hudRefs)


-- ============================================================================
-- TRADING UI & REMOTES (Phase 8.6)
-- ============================================================================
-- MOVED OUT (18.9) to `ReplicatedStorage.Modules.HUD.TradePanel` -- 968 lines of it, unchanged.
-- It was already a `;(function() ... end)()` closure capturing seven names from this file, so the
-- module takes those seven as `hudRefs` and nothing else had to be threaded through. The block
-- returned nothing and escaped nothing, which is why this is a plain call and not an assignment.
require(RS.Modules:WaitForChild("HUD"):WaitForChild("TradePanel"))(hudRefs)


-- ============================================================================
-- SCROLL AFFORDANCE PASS  (16.x)
-- ============================================================================
-- Photographed 2026-08-16 on the Zones, Inventory and Journal panels: a list scrolled anywhere but
-- the end has its last visible row sliced dead flat by the panel edge, with nothing to say more
-- exists below it. A structural probe over all 15 ScrollingFrames found why, and it is three
-- separate omissions rather than one:
--
--   * 13 of 15 have NO bottom padding, so the final row ends exactly on the clip line.
--   * 9 of 15 carry ScrollBarImageColor3 = white -- and every panel shell is white, so the only
--     affordance the engine gives for free is invisible. That is not a subtle defect; those
--     panels render with no scrollbar at all.
--   * Nothing fades the cut, so a half-row reads as a rendering fault rather than as content.
--
-- This runs once, generically, over whatever ScrollingFrames exist. It deliberately does NOT know
-- any panel by name -- a panel added later is covered by the same pass, which is the whole reason
-- it is written as a sweep instead of 15 edits.
--
-- Register cost: zero. Everything lives inside this block.
-- MOVED OUT (18.9) to `ReplicatedStorage.Modules.HUD.ScrollAffordance` -- 103 lines, unchanged.
require(RS.Modules:WaitForChild("HUD"):WaitForChild("ScrollAffordance"))(hudRefs)
