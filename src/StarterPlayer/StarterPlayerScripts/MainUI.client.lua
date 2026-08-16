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
local diamondPill = UITheme.Pill(currencyStack, {
	name = "DiamondPill", icon = "💎", text = "0", layoutOrder = 2,
	size = UDim2.new(1, 0, 0, 40), maxTextSize = 30,
	shellColor = UITheme.Color.Frost:Lerp(UITheme.Color.Aqua, 0.16), color = UITheme.Color.Ink,
})
local shardPill = UITheme.Pill(currencyStack, {
	name = "ShardPill", icon = "🌟", text = "0", layoutOrder = 3,
	size = UDim2.new(1, 0, 0, 40), maxTextSize = 30,
	shellColor = UITheme.Color.Frost:Lerp(UITheme.Color.Lavender, 0.16), color = UITheme.Color.Ink,
})
-- (the three pills' .Value labels used to be cached here and were never read again -- see the note
-- on the Season XP bar: this chunk is at Luau's 200-register limit and every unused local counts)

-- ===== Upgrades panel (centre screen, opened by the Shop tile) =====
local shopFrame = Instance.new("Frame")
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
local RIGHT_BOTTOM_Y = 46
local PANEL_ANCHOR = UDim2.new(0.5, 0, 0.5, 0)

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
;(function()
	local stack = Instance.new("Frame")
	stack.Name = "PotionTimers"
	-- BOTH OF THESE ARE RECOMPUTED EVERY TICK NOW (10.17); these are only the first-frame values.
	-- The height was a fixed 250 that up to 297 px of content overflowed upward into the left tile
	-- column, and the x was that column's own 20 -- see the fit pass at the bottom of the refresh
	-- loop for both. The layout aligns to the BOTTOM of this frame, which is what makes a height
	-- change headroom rather than movement: the strip stays 170 px off the bottom (clearing the
	-- currency stack, 140 tall and 22 up) whether it is holding one boost or twelve.
	stack.Size = UDim2.new(0, 224, 0, 196)
	stack.Position = UDim2.new(0, 20, 1, -170)
	stack.AnchorPoint = Vector2.new(0, 1)
	stack.BackgroundTransparency = 1
	stack.Visible = false
	stack.ZIndex = UITheme.Z.Content
	stack.Parent = screenGui

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Padding = UDim.new(0, 6)
	layout.Parent = stack

	-- ===== DRIVEN BY GameConfig, NOT BY A LIST TYPED HERE (11.8) =====
	--
	-- This was `{ "dna", "xp", "luck" }`, and the fourth kind landed in the config, in the shop, in
	-- the inventory panel and in the save -- and had no timer on the HUD, because this one list did
	-- not know about it. A boost with no countdown is a boost the player cannot tell is running or
	-- about to end. The potion tables were deliberately built as kind x size for exactly this class
	-- of mistake; the strip is now built the same way, so a fifth kind gets a card by existing.
	local KINDS = {}
	for _, k in ipairs(GameConfig.PotionKinds) do table.insert(KINDS, k.key) end
	-- ...and the word on the card comes from the same table, so "health" cannot print lowercase
	-- while "DNA" prints in caps. `LABEL[kind] or kind` was the fallback and it was already the
	-- wrong answer the moment a kind existed that nobody had typed a label for.
	local LABEL = {}
	for _, k in ipairs(GameConfig.PotionKinds) do LABEL[k.key] = k.name end
	local rows = {}

	for order, kind in ipairs(KINDS) do
		-- colour and emoji are properties of the KIND, so any bottle of that kind carries the
		-- right ones -- no separate table to keep in step with GameConfig.Potions
		local sample
		for _, p in ipairs(GameConfig.Potions) do
			if p.kind == kind then
				sample = p
				break
			end
		end

		-- 216 x 38 AND A CAPSULE, NOT 244 x 48 AND A BOX (16.1). Every row on this strip is now the
		-- same 38 px single line: an icon disc, one short phrase, a clock, and -- only here, because
		-- only a potion is running out -- a 5 px bar along the bottom. `UDim.new(1, 0)` is a real
		-- radius for `styleCard`, not a hack: it has a documented pill path that drops the gloss to
		-- 0.40 height. The disc is 28 px on a 38 px row, so it shares the capsule's own left centre
		-- (19, 19) and cannot clip against the rounding.
		local card = Instance.new("Frame")
		card.Name = kind .. "Timer"
		card.Size = UDim2.new(0, 216, 0, 38)
		card.LayoutOrder = order
		card.BackgroundColor3 = Color3.fromRGB(30, 34, 48)
		card.Visible = false
		card.ZIndex = UITheme.Z.Content + 1
		card.Parent = stack
		styleCard(card, sample.color, UDim.new(1, 0), 3)

		local bottle = Instance.new("TextLabel")
		bottle.Name = "Bottle"
		bottle.Size = UDim2.new(0, 28, 0, 28)
		bottle.Position = UDim2.new(0, 5, 0, 5)
		bottle.BackgroundColor3 = sample.color
		bottle.Text = sample.emoji
		bottle.ZIndex = card.ZIndex + 1
		bottle.Parent = card
		corner(bottle, UDim.new(0.5, 0))
		themeLabel(bottle, 16)

		local effect = Instance.new("TextLabel")
		effect.Name = "Effect"
		effect.Size = UDim2.new(1, -110, 0, 17)
		effect.Position = UDim2.new(0, 40, 0, 4)
		effect.BackgroundTransparency = 1
		effect.TextXAlignment = Enum.TextXAlignment.Left
		effect.ZIndex = card.ZIndex + 1
		effect.Parent = card
		themeLabel(effect, 14)

		local clock = Instance.new("TextLabel")
		clock.Name = "Clock"
		clock.Size = UDim2.new(0, 58, 0, 17)
		clock.Position = UDim2.new(1, -64, 0, 4)
		clock.BackgroundTransparency = 1
		clock.TextXAlignment = Enum.TextXAlignment.Right
		clock.ZIndex = card.ZIndex + 1
		clock.Parent = card
		themeLabel(clock, 14)

		local track = Instance.new("Frame")
		track.Name = "Track"
		track.Size = UDim2.new(1, -52, 0, 5)
		track.Position = UDim2.new(0, 40, 1, -11)
		track.BackgroundColor3 = UITheme.Color.Cloud
		track.BorderSizePixel = 0
		track.ZIndex = card.ZIndex + 1
		track.Parent = card
		corner(track, UDim.new(0.5, 0))

		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.new(1, 0, 1, 0)
		fill.BackgroundColor3 = sample.color
		fill.BorderSizePixel = 0
		fill.ZIndex = track.ZIndex + 1
		fill.Parent = track
		corner(fill, UDim.new(0.5, 0))

		rows[kind] = { card = card, effect = effect, clock = clock, fill = fill }
	end

	-- ============================================================================
	-- THE PASS CHIP TRAY IS GONE FROM THE HUD (16.1)
	-- ============================================================================
	-- It was a gold card carrying up to nine 34 px emoji discs, wrapped two rows deep, parked
	-- permanently in the middle of the left edge. 6.4's own argument is what condemns it: a pass is
	-- PERMANENT, so the chip never changes, never counts down and never asks for anything. It was
	-- the single densest thing on the screen and the least actionable -- ten glyphs with no labels,
	-- competing for the eye with the two clocks that actually move. Worse, it is the row that made
	-- the strip TALL: 81 px of the 297 px that grew up the screen into the tile column.
	--
	-- Ownership is already answered properly, with names, art and prices, in the Robux panel's
	-- Passes tab -- one tap from the same screen. Nothing else in the file referenced `passCard`
	-- or `passChips`. If a permanent-boost readout is ever wanted back, it belongs inside a panel
	-- next to what it costs, not on the strip reserved for things that expire.

	-- ============================================================================
	-- THE EVENT HALF OF THE STRIP (7.1)
	-- ============================================================================
	-- A server-wide event is a boost that is running out, so by 6.4's own rule it is a CARD with a
	-- clock and not a chip. It sits above the pass chips because it is the only thing here that is
	-- true of everybody in the server at once, and it is the only one with a deadline.
	--
	-- WHY THIS EXISTS AT ALL when there is already a board in Forest: the board is read by a player
	-- who walks past it. Somebody who joins in the middle of a weekend, spawns, and goes straight to
	-- a zone would otherwise never learn that their DNA is doubled -- which is most of the value of
	-- running an event in the first place.
	--
	-- THE CLOCK COMES FROM THE SERVER, and this is the one place that matters on the client. Every
	-- window in GameConfig is measured against GameConfig.EventNow(), which is os.time() plus an
	-- offset -- and the offset is learned here, from the payload EventService publishes. A player
	-- whose machine is a day fast would otherwise be shown a weekend that is not running and a
	-- countdown to the wrong minute, and would then watch their DNA arrive at the ordinary rate.
	--
	-- Synced on `Changed` rather than on a poll of the value: the payload carries the moment it was
	-- WRITTEN, so reading it late means adopting a clock as stale as the read. Changed fires at the
	-- write, and the initial read below is corrected by the first refresh 30 seconds later.
	do
		local liveEvents = RS:FindFirstChild("LiveEvents")
		local HttpService = game:GetService("HttpService")
		local function adopt(value)
			if type(value) ~= "string" or value == "" then return end
			local ok, payload = pcall(function() return HttpService:JSONDecode(value) end)
			if ok and type(payload) == "table" and tonumber(payload.now) then
				GameConfig.SetEventClock(payload.now)
			end
		end
		if liveEvents then
			adopt(liveEvents.Value)
			liveEvents.Changed:Connect(adopt)
		else
			-- the server creates it in EventService.Init; a client that got here first waits rather
			-- than deciding for itself what time it is
			task.spawn(function()
				local sv = RS:WaitForChild("LiveEvents", 30)
				if sv then
					adopt(sv.Value)
					sv.Changed:Connect(adopt)
				end
			end)
		end
	end

	-- ============================================================================
	-- THE ARENA BOSS CLOCK (11.20)
	-- ============================================================================
	-- Same argument the event card above makes, and it applies harder here: the countdown already
	-- existed, on a board hanging over the arena entrance, where the only player who can read it is
	-- one who has already decided to go. A timer whose job is to MAKE somebody go has to be where
	-- they are.
	--
	-- It joins this strip rather than becoming a new HUD element, and that is the whole reason it is
	-- cheap: the strip is already a budgeted, bottom-aligned, drop-lowest-first stack (see 10.17
	-- below), so a fifth card inherits the phone-viewport behaviour, the tile-column clearance and
	-- the ordering without a line of new layout.
	--
	-- Fed by ReplicatedStorage attributes BossService republishes every second -- no remote, nothing
	-- to request, and a client that joins mid-interval reads the current value on its first tick.
	-- ONE LINE, NOT A CARD (16.1). The two-line card carried a subtitle -- "The Devourer returns",
	-- or the boss's health while it was alive -- under the clock. That is a sentence the player
	-- reads once and never needs again, printed permanently, and it is what forced 48 px. A boss
	-- clock only has to answer WHO and WHEN, so the name and the countdown share one 38 px capsule
	-- and the subtitle is gone. The health it used to show is on the boss's own bar the moment the
	-- fight starts, which is the only time it means anything.
	-- ========================================================================
	-- ...AND THEY ARE NOT ON THIS STRIP ANY MORE (16.2)
	-- ========================================================================
	-- The boss clock and the live-event clock came off the bottom-left strip and onto their own bar
	-- pinned to the very bottom edge of the screen, centred, at well under half the area they had.
	--
	-- WHY THEY DO NOT BELONG ON THE POTION STRIP: everything else on that strip is something the
	-- PLAYER is carrying -- a boost they drank, that is draining, that only they can see. These two
	-- are facts about the SERVER: the same words are on every screen in the game at the same moment.
	-- Mixing the two meant a boss timer nobody asked for could push a potion that is about to expire
	-- off the bottom of the budget, and it put a permanent red banner in the corner the player's eye
	-- goes to for their own numbers.
	--
	-- WHY THE BOTTOM EDGE: it is the only band of a Roblox screen that is genuinely idle -- the
	-- currencies are top-left, the tiles are down both sides, and the evolve card sits above this bar
	-- (moved up 14px to clear it). A world clock is ambient: findable without ever being in the way,
	-- and never the brightest thing on screen.
	--
	-- The bar auto-sizes on X around whichever pills are visible and stays centre-anchored, so one
	-- clock is centred and two are centred as a pair -- nothing slides sideways when an event starts.
	local eventBar = Instance.new("Frame")
	eventBar.Name = "WorldEventBar"
	-- 32, not 24 (17.x). The floor of this bar is not taste, it is the tile cluster: the responsive
	-- pass reserves BOTTOM_CLEAR = 46 for the right-hand column, so `clearance + height` has to stay
	-- at or under 46 or the bar slides under the tiles on a phone viewport. 12 + 32 = 44. The width
	-- stays 168 for the same reason in X: two chips plus their gap is 344, and on an 848-wide phone
	-- that leaves 16 px before the cluster starts. BOTTOM_CLEAR lives inside the responsive block
	-- at the bottom of this file and cannot be shared without a top-level register, so if it ever
	-- moves, THIS BAR HAS TO BE RE-CHECKED BY HAND -- the relationship is a comment, not code.
	eventBar.Size = UDim2.new(0, 0, 0, 32)
	eventBar.AutomaticSize = Enum.AutomaticSize.X
	eventBar.Position = UDim2.new(0.5, 0, 1, -12)
	eventBar.AnchorPoint = Vector2.new(0.5, 1)
	eventBar.BackgroundTransparency = 1
	eventBar.ZIndex = UITheme.Z.Content
	eventBar.Parent = screenGui

	local eventBarLayout = Instance.new("UIListLayout")
	eventBarLayout.FillDirection = Enum.FillDirection.Horizontal
	eventBarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	eventBarLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	eventBarLayout.SortOrder = Enum.SortOrder.LayoutOrder
	eventBarLayout.Padding = UDim.new(0, 8)
	eventBarLayout.Parent = eventBar

	local arenaCard = Instance.new("Frame")
	arenaCard.Name = "ArenaBoss"
	-- 168 x 24, down from 216 x 38. At this size the pill is a glance, not a card: an 18px emoji
	-- disc, the name at 12, the clock at 12, and nothing else fits -- which is the point.
	arenaCard.Size = UDim2.new(0, 168, 0, 32)
	arenaCard.LayoutOrder = 1                 -- boss first, event second, reading left to right
	arenaCard.BackgroundColor3 = Color3.fromRGB(30, 34, 48)
	arenaCard.Visible = false
	arenaCard.ZIndex = UITheme.Z.Content + 1
	arenaCard.Parent = eventBar
	styleCard(arenaCard, UITheme.Color.Red, UDim.new(1, 0), 3)

	local arenaBadge = Instance.new("TextLabel")
	arenaBadge.Name = "Badge"
	-- 18 on a 24px row, so the disc shares the capsule's own left centre (12, 12) and cannot clip
	-- against the rounding -- the same rule the 28-on-38 discs on the potion strip follow.
	arenaBadge.Size = UDim2.new(0, 22, 0, 22)
	arenaBadge.Position = UDim2.new(0, 5, 0, 5)
	arenaBadge.BackgroundColor3 = UITheme.Color.Red
	arenaBadge.Text = GameConfig.EventBoss.emoji
	arenaBadge.ZIndex = arenaCard.ZIndex + 1
	arenaBadge.Parent = arenaCard
	corner(arenaBadge, UDim.new(0.5, 0))
	themeLabel(arenaBadge, 14)

	-- Both labels are centred on the row (`0.5, -10` against a height of 20) rather than pinned to
	-- a top margin: on a single-line pill there is no second line to leave room for, and a
	-- top-pinned label on a 38 px capsule reads as if it has slipped.
	local arenaName = Instance.new("TextLabel")
	arenaName.Name = "ArenaName"
	-- -80 = 25 of left inset past the disc + 47 of clock and its right margin. Truncated rather than
	-- shrunk: themeLabel floors text at 14 and this label is authored at 12, so a long boss name has
	-- no shrink left to give and would wrap onto a second line the 24px pill has no room for.
	arenaName.Size = UDim2.new(1, -78, 0, 20)
	arenaName.Position = UDim2.new(0, 28, 0.5, -10)
	arenaName.BackgroundTransparency = 1
	arenaName.TextXAlignment = Enum.TextXAlignment.Left
	arenaName.TextTruncate = Enum.TextTruncate.AtEnd
	arenaName.ZIndex = arenaCard.ZIndex + 1
	arenaName.Parent = arenaCard
	-- 12, NOT the 14 the rest of this chip uses, and this is the binding constraint of the whole
	-- bar. Measured with GetTextBoundsAsync in FredokaOne: "Colosseum Clash" needs 100 px at 14,
	-- 97 at 13 and 87 at 12, and the widest band this 168 px card can give a name is 90. The
	-- original 12 px was not laziness -- it was tuned to exactly this string, and raising it to 14
	-- silently truncated the longest event in the game to "Colosseum...".
	--
	-- THE CAPTURE IS WHAT SETTLED IT. TextBounds read 76 x 14 in an 86 x 20 box -- fits by every
	-- number -- because TextBounds reports what was RENDERED, i.e. the already-truncated string,
	-- not what the text needed. TextFits was the only property telling the truth and it was the
	-- one that looked wrong. Measure the STRING, never the label, when asking if it will fit.
	themeLabel(arenaName, 12)
	-- AFTER themeLabel, NEVER BEFORE: `TextScaled = true` silently turns `TextWrapped` ON, so a
	-- "do not wrap" written above the helper that scales is reversed by it and reads correct in
	-- the source forever. Measured live: the band is 86 px and the string needs 76, so it fits on
	-- one line -- but wrapped, it broke into two lines that do not fit 20 px of height, and the
	-- engine reported TextFits = false while every other property looked right. These are one-line
	-- chips by construction; a second line is clipped by the card either way.
	arenaName.TextWrapped = false

	local arenaClock = Instance.new("TextLabel")
	arenaClock.Name = "Clock"
	arenaClock.Size = UDim2.new(0, 46, 0, 20)
	arenaClock.Position = UDim2.new(1, -50, 0.5, -10)
	arenaClock.BackgroundTransparency = 1
	arenaClock.TextXAlignment = Enum.TextXAlignment.Right
	arenaClock.ZIndex = arenaCard.ZIndex + 1
	arenaClock.Parent = arenaCard
	themeLabel(arenaClock, 14)
	arenaClock.TextWrapped = false

	-- ONE LINE, NOT A CARD (16.1). The effects line -- "x2 DNA   x2 Giant Loot   x2 XP" -- was the
	-- widest string anywhere on the HUD and it said the same three things for a whole weekend
	-- without moving. 12.13 above is the record of how much layout that one static line cost: two
	-- passes of pixel-fitting against a name that would not fit beside it. The name and the clock
	-- are the reason to look; what the event PAYS is on its own board in the world and in the
	-- Season panel, where a player deciding whether to go can actually act on it.
	--
	-- The "+1" for a second concurrent event goes with it: "Colosseum Clash  +1" is 118 px at this
	-- label's 14 px floor and the slot is 108. The headliner is drawn; the co-runner is not named.
	local eventCard = Instance.new("Frame")
	eventCard.Name = "EventBoost"
	eventCard.Size = UDim2.new(0, 168, 0, 32)
	eventCard.LayoutOrder = 2                 -- to the right of the arena pill (1)
	eventCard.BackgroundColor3 = Color3.fromRGB(30, 34, 48)
	eventCard.Visible = false
	eventCard.ZIndex = UITheme.Z.Content + 1
	eventCard.Parent = eventBar
	styleCard(eventCard, UITheme.Color.Coral, UDim.new(1, 0), 3)

	local eventBadge = Instance.new("TextLabel")
	eventBadge.Name = "Badge"
	eventBadge.Size = UDim2.new(0, 22, 0, 22)
	eventBadge.Position = UDim2.new(0, 5, 0, 5)
	eventBadge.BackgroundColor3 = UITheme.Color.Coral
	eventBadge.Text = "\u{1F525}"
	eventBadge.ZIndex = eventCard.ZIndex + 1
	eventBadge.Parent = eventCard
	corner(eventBadge, UDim.new(0.5, 0))
	themeLabel(eventBadge, 14)

	local eventName = Instance.new("TextLabel")
	eventName.Name = "EventName"
	eventName.Size = UDim2.new(1, -78, 0, 20)
	eventName.Position = UDim2.new(0, 28, 0.5, -10)
	eventName.BackgroundTransparency = 1
	eventName.TextXAlignment = Enum.TextXAlignment.Left
	eventName.TextTruncate = Enum.TextTruncate.AtEnd
	eventName.ZIndex = eventCard.ZIndex + 1
	eventName.Parent = eventCard
	themeLabel(eventName, 12)
	eventName.TextWrapped = false

	local eventClock = Instance.new("TextLabel")
	eventClock.Name = "Clock"
	eventClock.Size = UDim2.new(0, 46, 0, 20)
	eventClock.Position = UDim2.new(1, -50, 0.5, -10)
	eventClock.BackgroundTransparency = 1
	eventClock.TextXAlignment = Enum.TextXAlignment.Right
	eventClock.ZIndex = eventCard.ZIndex + 1
	eventClock.Parent = eventCard
	themeLabel(eventClock, 14)
	eventClock.TextWrapped = false

	-- ============================================================================
	-- THE MUTATION YOU ARE WEARING IS A DOT ON THE AURAS TILE (16.1)
	-- ============================================================================
	-- 15.24's argument below is kept because it is still right about the PROBLEM -- there was
	-- nowhere to see the worn aura -- and wrong only about the size of the answer. A card was the
	-- answer when the strip had room. It does not: counting the pass tray, four of the eight rows
	-- were facts that never change, and they pushed the two clocks that DO change up the screen
	-- behind them. A permanent one-of-seven fact earns a GLYPH, not a sentence.
	--
	-- So it becomes a coloured dot in the corner of the Auras TILE -- the button that opens the
	-- panel which already prints "wearing X" and the full "x1.80 DNA, +6 speed" line for every
	-- tier. The dot says "you have one, and it is this rarity"; one tap says the rest. It costs no
	-- screen space at all, and it puts the readout on the thing you would click anyway.
	--
	-- Parented to the tile rather than the strip, so the responsive pass that resizes the column
	-- carries it for free. `FindFirstChild`, not `WaitForChild`: the tiles are built ~500 lines
	-- above this block so it is already there, and yielding here would stall the rest of the HUD.
	-- If it were ever missing, `Parent = nil` leaves the dot alive but unrendered -- the refresh
	-- below stays valid and simply draws nothing.
	--
	-- ---- 15.24's original note, on why this readout has to exist at all: ----
	-- The report was *"I need somewhere to see which aura is equipped, or whatever this DNA machine
	-- gives"*, and it was exactly right: the Splicer sells a permanent income-and-speed multiplier
	-- that is WORN one at a time (`data.SplicerMutation`), and the only place in the entire game
	-- that named it was a line inside the Splicer's own roll panel -- i.e. you had to walk back to
	-- the machine to find out what you had bought from it. The particle aura on the body is the only
	-- other trace, and a particle does not say "x1.50".
	--
	-- IT BELONGS ON THIS STRIP AND NOWHERE ELSE. The strip is already the answer to "what is
	-- currently affecting me": potions that are running out, passes that are permanent, the live
	-- event, the arena clock. A worn mutation is the same class of fact as a pass -- permanent,
	-- bought, invisible without a readout -- so it is a card here rather than a new HUD element,
	-- and it inherits the budget, the fit pass and the tile-column clearance for free.
	--
	-- Dropped FIRST when the viewport is short (see the fit order below), beside the pass card and
	-- for the same reason: nothing about it is about to expire.
	local mutationDot = Instance.new("Frame")
	mutationDot.Name = "AuraDot"
	mutationDot.Size = UDim2.new(0, 22, 0, 22)
	mutationDot.Position = UDim2.new(1, -3, 0, 3)
	mutationDot.AnchorPoint = Vector2.new(1, 0)
	mutationDot.BackgroundColor3 = UITheme.Color.Purple
	mutationDot.Visible = false
	mutationDot.ZIndex = UITheme.Z.Badge
	mutationDot.Parent = screenGui:FindFirstChild("AurasButton")
	corner(mutationDot, UDim.new(0.5, 0))
	stroke(mutationDot, 2, UITheme.Color.Outline)

	-- x2 stays "x2"; x1.5 becomes "x1.5" rather than taking the thread down. See the note below.
	-- TWO decimals, not one (15.29). `%.1f` was written for the potion and event cards, whose
	-- multipliers are all x1.5 / x2 / x3 and exact at one decimal -- but a mutation is not: three of
	-- the seven are two-decimal, and Common 1.05 drew as `x1.1`, Epic 1.18 as `x1.2`, Godly 2.25 as
	-- `x2.2` (rounded DOWN, so the best aura in the game under-sold itself) anywhere this helper met
	-- one. Trailing zero trimmed, so `1.50 -> "1.5"` and nothing that was already correct changes.
	local function formatMult(m)
		m = tonumber(m) or 1
		if math.abs(m - math.floor(m + 0.5)) < 0.001 then
			return tostring(math.floor(m + 0.5))
		end
		local s = ("%.2f"):format(m)
		s = s:gsub("0$", "") -- 1.50 -> 1.5; 1.05 and 2.25 keep both digits
		return s
	end

	-- Its OWN loop, not a hook on DataUpdate: the number has to fall every second, and data only
	-- arrives when something in the game happens -- a player standing still would watch a frozen
	-- clock. Four times a second keeps the seconds honest without redrawing every frame.
	task.spawn(function()
		while true do
			local boosts = currentData and currentData.PotionBoosts
			local now = os.time()
			local any = false
			for _, kind in ipairs(KINDS) do
				local row = rows[kind]
				local b = boosts and boosts[kind]
				local left = b and ((b.untilTs or 0) - now) or 0
				if left > 0 then
					any = true
					row.card.Visible = true
					row.clock.Text = ("%d:%02d"):format(math.floor(left / 60), left % 60)
					-- `totalSecs` is what the boost was worth when it was last topped up, which is
					-- not the bottle's own duration -- a second bottle adds to the remainder. Fall
					-- back to `left` so an old save written before that field existed draws a full
					-- bar rather than dividing by nil.
					local total = math.max(b.totalSecs or left, 1)
					row.fill.Size = UDim2.new(math.clamp(left / total, 0, 1), 0, 1, 0)
					-- %d, NOT ON A VALUE THAT MIGHT NOT BE A WHOLE NUMBER.
					--
					-- In Luau `("%d"):format(2.5)` does not round -- it raises "number has no integer
					-- representation". This is the body of a `while true` inside a task.spawn with no
					-- pcall around it, so one such multiplier would kill this thread permanently: every
					-- potion timer in the session freezes at whatever it last showed, no error reaches
					-- the player, and the bug looks like "my potion never ran out". A potion multiplier
					-- is authored as 2 today and nothing stops the next one being 1.5.
					row.effect.Text = b.mult and ("x%s %s"):format(formatMult(b.mult), LABEL[kind] or kind)
						or (b.luckAdd and ("+%d%% Luck"):format(math.floor(b.luckAdd)) or "Boost")
				else
					row.card.Visible = false
				end
			end

			-- (No pass half any more -- see 16.1 where the chip tray was built.)

			-- The event half (7.1). Driven off the shared config against the SERVER's clock, not off
			-- the payload's own text, so the seconds fall between publishes instead of jumping every
			-- thirty. Only the first live event is drawn: two at once is possible (a festival can
			-- overlap a weekend) and a second card would push the strip up over the potion rows for
			-- the one player in a hundred who sees it. The clock is the reason to look; the effects
			-- line says what it is worth.
			--
			-- THE EFFECTS LINE SUMS EVERY LIVE EVENT, THE HEADER NAMES ONE (12.13). Overlap stopped
			-- being the rare case the paragraph above describes the moment the Colosseum took the same
			-- Saturday window as the weekend -- both are on every weekend now. The card still cannot
			-- become two cards for the reason given above, but drawing only the headliner's effects
			-- would tell a player their DNA is not doubled while it is, which is worse than a name
			-- that omits a co-runner. So: one card, the headliner's name, colour and clock (the sort
			-- in GetActiveEvents decides which that is), and the combined effects of everything
			-- running -- multiplied for mults and added for luck, exactly as GetEventMult and
			-- GetEventAdd do it on the server, so the line cannot disagree with the payout.
			local activeNow = GameConfig.GetActiveEvents()
			local live = activeNow[1]
			if live then
				local left = live.window.endTs - GameConfig.EventNow()
				eventCard.Visible = true
				eventBadge.Text = live.event.emoji
				eventBadge.BackgroundColor3 = live.event.color
				eventName.Text = live.event.name
				eventClock.Text = GameConfig.FormatDuration(left)
			else
				eventCard.Visible = false
			end

			-- The arena half (11.20). Read off the attributes rather than computed here: the interval,
			-- the spawn and the boss's health all live on the server, and a client that did its own
			-- arithmetic would drift from the board in the arena within one interval.
			--
			-- `nil` is a real state and is NOT zero -- it means BossService has not published yet
			-- (the first second of a server, or a client that got here first). Drawing "0:00" for that
			-- would announce a boss that is not coming, so the card simply stays hidden.
			-- The worn mutation (16.1). Tinted from the same `GameConfig.Mutations` row the server pays
			-- from, so the colour on the tile cannot disagree with the income stack. Nothing worn: no
			-- dot at all, rather than a grey one -- the Splicer is optional and a permanent grey mark
			-- on the tile would read as something broken rather than something not yet bought.
			local worn = currentData and currentData.SplicerMutation
			local wornDef = nil
			if worn then
				for _, m in ipairs(GameConfig.Mutations) do
					if m.name == worn then wornDef = m break end
				end
			end
			mutationDot.Visible = wornDef ~= nil
			if wornDef then
				mutationDot.BackgroundColor3 = wornDef.color
			end

			local arenaSecs = RS:GetAttribute("ArenaBossSeconds")
			if arenaSecs == nil then
				arenaCard.Visible = false
			elseif RS:GetAttribute("ArenaBossLive") then
				arenaCard.Visible = true
				arenaName.Text = GameConfig.EventBoss.name
				arenaClock.Text = "LIVE"
			else
				arenaCard.Visible = true
				arenaName.Text = "Arena Boss"
				arenaClock.Text = ("%d:%02d"):format(arenaSecs // 60, arenaSecs % 60)
			end

			-- ================================================================================
			-- BOUNDED, AND OUT FROM UNDER THE BUTTONS (10.17)
			-- ================================================================================
			-- Measured before this existed: the strip is a 250 px frame with `ClipsDescendants`
			-- false holding up to 297 px of content -- an event card (48), the pass card (81 when
			-- nine chips wrap to two rows) and three potion cards (48 each) with 6 px between them.
			-- It is bottom-aligned, so the excess grows UPWARD into the left tile column, which
			-- starts at the same x = 20. Live at 1546x793 with every boost running, the gold pass
			-- card covered the Rebirth tile whole: the tile occupies y 289..371 and the strip's
			-- content began at 322. Not a near miss and not only on small screens -- the third
			-- button in the column was simply gone, and it is the one that opens Rebirth.
			--
			-- TWO SEPARATE FIXES, because the overlap and the overflow are two different faults.
			--
			-- 1. THE STRIP MOVES OUT OF THE COLUMN'S LANE. It is beside the buttons now rather than
			--    on top of them, so nothing it does can ever cover one again. The x is read from the
			--    tile's own live `AbsoluteSize` instead of being computed a second time -- the
			--    responsive pass at the bottom of this file shrinks the tiles from 82 to as little
			--    as 40 on a short viewport, and a hard-coded 82 here would put the strip back over
			--    the column on exactly the screens that are already tightest.
			--
			-- 2. THE HEIGHT IS A BUDGET, NOT A GUESS. The frame may reach from its own bottom edge
			--    (170 off the bottom of the screen) up to TOP_CLEAR, the same 121 the tile columns
			--    respect for the topbar and stage card. Computed in AUTHORED OFFSETS off
			--    ViewportSize, never from AbsolutePosition -- this ScreenGui reports absolutes 58 px
			--    up from where offsets are measured (the topbar inset), and mixing the two is how
			--    an element lands exactly one inset out of place.
			--
			-- WHEN IT STILL DOES NOT FIT, WHOLE CARDS GO, LOWEST URGENCY FIRST -- clipping was the
			-- other option and it is worse: a card sliced in half reads as a broken HUD, and the
			-- slice would land on the stroke `styleCard` draws OUTSIDE the frame. The order is the
			-- honest one: the pass card first, because a pass is permanent and has nothing to miss;
			-- then the event, which is server-wide and announced elsewhere; then potions longest
			-- remaining first, so what survives to the last row is always the boost about to expire.
			-- At 793 the budget is 492 against 297 of content, so nothing is ever dropped on a
			-- desktop; a 420 px phone viewport gets 119 and keeps the two most urgent potions.
			-- BACK AGAINST THE LEFT EDGE (16.2). The sideways offset that used to be computed here
			-- existed because the left column was five tiles tall and reached down into this strip's
			-- lane. As a 2x2 block it ends around y = 311 on any viewport -- hundreds of pixels above
			-- where this strip starts -- so the strip owns the bottom-left corner outright and no longer
			-- has to be pushed out from under buttons that are not there any more.
			stack.Position = UDim2.new(0, 20, 1, -170)
			-- Read fresh every tick rather than captured once: `CurrentCamera` is nil for the first
			-- frames of a join, and the viewport changes when the window is resized.
			local viewportY = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.Y or 720
			-- CAPPED AT FOUR ROWS (16.1). The old budget was "every pixel between the tile column and
			-- the currency stack", which on a desktop is 492 -- ten rows of headroom, and the strip was
			-- happy to fill it. A HUD element free to grow to two thirds of the screen height is not a
			-- HUD element. Four 38 px rows, each measured with the 6 px `styleCard` draws outside it,
			-- plus three 6 px gaps, is 194; 196 is the ceiling and the drop pass below decides what
			-- survives it. The floor stays 96 for the same phone-viewport reason as before.
			local budget = math.clamp(viewportY - 170 - 121 - 10, 96, 196)
			stack.Size = UDim2.new(0, 224, 0, budget)

			-- Each card is measured with its stroke: `styleCard` draws 3 px outside the frame on
			-- every side, so two stacked cards cost 6 px more than their own heights claim.
			local function fits()
				local total, n = 0, 0
				for _, c in ipairs(stack:GetChildren()) do
					if c:IsA("GuiObject") and c.Visible then
						n += 1
						total += c.AbsoluteSize.Y + 6
					end
				end
				return total + math.max(n - 1, 0) * 6 <= budget
			end
			if not fits() then
				-- longest remaining last, so the first potion dropped is the one with most time left.
				-- NOTHING BUT POTIONS IS LEFT TO DROP (16.2). The arena and event pills used to lead this
				-- list; they are on their own bar along the bottom edge now and are not this strip's
				-- problem -- which also means a short viewport can no longer answer "the screen is tight"
				-- by hiding a world clock, and a boss timer can no longer crowd out an expiring potion.
				local order = {}
				local byTime = {}
				for _, kind in ipairs(KINDS) do
					local b = boosts and boosts[kind]
					if rows[kind].card.Visible then
						table.insert(byTime, { card = rows[kind].card, left = b and ((b.untilTs or 0) - now) or 0 })
					end
				end
				table.sort(byTime, function(a, b) return a.left > b.left end)
				for _, e in ipairs(byTime) do
					table.insert(order, e.card)
				end
				for _, card in ipairs(order) do
					if fits() then break end
					card.Visible = false
				end
			end

			-- `any OR owned OR an event`: a player with passes and no potion still has a strip worth
			-- showing, and one with none of the three still gets nothing rather than an empty box.
			-- Read off what SURVIVED the fit pass, not off the three flags above -- on a viewport
			-- short enough to drop everything, an empty box is exactly what those flags would draw.
			local shown = false
			for _, c in ipairs(stack:GetChildren()) do
				if c:IsA("GuiObject") and c.Visible then shown = true break end
			end
			stack.Visible = shown
			task.wait(0.25)
		end
	end)

	hudRefs.potionTimers = rows
end)()

-- An IMMEDIATELY-CALLED FUNCTION, not a `do` block. The note above is half right: a block does
-- release its registers at `end`, but Luau measures the PEAK, and the peak inside a block is every
-- top-level local still in scope plus everything the block declares. A function body gets its own
-- 200 and is the only thing that actually buys headroom -- see the Season Pass block, which had
-- the same comment on it and still broke the script.
;(function()
	-- THE BAR SITS ON THE BOTTOM EDGE OF THE BOARD, half in and half out, the way the reference
	-- does it: two wide buttons, then the two counters.
	local actionRow = Instance.new("Frame")
	actionRow.Name = "PetsActionRow"
	actionRow.Size = UDim2.new(1, -28, 0, 52)
	actionRow.Position = UDim2.new(0.5, 0, 1, -26)
	actionRow.AnchorPoint = Vector2.new(0.5, 0.5)
	actionRow.BackgroundTransparency = 1
	actionRow.ZIndex = petsPanel.ZIndex + UITheme.Z.Badge
	actionRow.Parent = petsPanel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = actionRow

	local function actionButton(order, text, color, width)
		local btn = Instance.new("TextButton")
		btn.Name = "Action" .. order
		btn.Size = UDim2.new(0, width or 178, 0, 46)
		btn.LayoutOrder = order
		btn.Text = text
		btn.ZIndex = actionRow.ZIndex
		btn.Parent = actionRow
		styleButton(btn, color, UDim.new(1, 0))
		return btn
	end

	-- 178 -> 146 each, which is what buys the select toggle its place in this row without pushing the
	-- two counter capsules off the end: 146 + 146 + 46 + 150 + 150 + 4 gaps of 10 = 678, inside the
	-- row's 744. Both labels still fit -- checked, not assumed.
	local equipBestButton = actionButton(1, "Equip Best Pets", UITheme.Color.Green, 146)
	local unequipAllButton = actionButton(2, "Unequip All Pets", UITheme.Color.Red, 146)

	-- ===== SELECT MODE (11.17) =====
	--
	-- The server has taken a LIST since 10.3; this is the client half that was never built, and
	-- releasing a hundred pets one confirm at a time is the reason the cap reads as a chore.
	--
	-- THE ROW SWAPS, IT DOES NOT GROW. While selecting, the two action buttons are hidden and one
	-- wide red button stands in their place at exactly their combined width (146 + 10 + 146 = 302),
	-- so nothing in the row moves by a pixel when the mode changes -- a bar that reflows on a toggle
	-- makes the player re-find every control. The counters stay visible throughout: "how many do I
	-- own" is the question that got them here.
	--
	-- The selection lives on `hudRefs`, not in a local, because `refreshPetsPanel` DESTROYS AND
	-- REBUILDS EVERY CELL ON EVERY DataUpdate -- roughly every three seconds, and on every kill.
	-- State held on the cards would be wiped mid-selection by an unrelated creature dying. The set is
	-- keyed by pet id and the rebuild reads it, so the ticks come back exactly where they were.
	local selectToggle = actionButton(3, "\u{2611}", UITheme.Color.Blue, 46)
	local releaseButton = actionButton(0, "RELEASE", UITheme.Color.Red, 302)
	releaseButton.Visible = false

	hudRefs.petSelect = { on = false, ids = {}, n = 0 }
	-- `sel.n` is also decremented by refreshPetsPanel when a selected pet stops existing, and that
	-- function is 200 lines below and cannot name anything in here -- so the repaint is handed over.

	-- One place that redraws the bar, called by every path that can change either the mode or the
	-- count -- so "the button says 3 and the grid shows 4 ticks" cannot happen.
	local function paintSelectBar()
		local sel = hudRefs.petSelect
		equipBestButton.Visible = not sel.on
		unequipAllButton.Visible = not sel.on
		releaseButton.Visible = sel.on
		-- plain `.Text`, the way every other call site in this file writes a button: styleButton
		-- subscribes a proxy label to it, so the visible text follows
		releaseButton.Text = sel.n > 0 and ("RELEASE %d"):format(sel.n) or "SELECT PETS TO RELEASE"
		setButtonColor(releaseButton, sel.n > 0 and UITheme.Color.Red or UITheme.Color.Locked)
		setButtonColor(selectToggle, sel.on and UITheme.Color.Green or UITheme.Color.Blue)
	end
	hudRefs.petSelectRepaint = paintSelectBar

	-- Leaving select mode always clears the set. A selection that survived the toggle would be
	-- invisible -- no ticks are drawn outside the mode -- and the next RELEASE press would act on
	-- pets the player picked minutes ago and cannot see.
	hudRefs.petSelectExit = function()
		local sel = hudRefs.petSelect
		sel.on, sel.ids, sel.n = false, {}, 0
		paintSelectBar()
		if hudRefs.refreshPetsPanel then hudRefs.refreshPetsPanel() end
	end

	hudRefs.petSelectToggleId = function(petId)
		local sel = hudRefs.petSelect
		if sel.ids[petId] then
			sel.ids[petId] = nil
			sel.n -= 1
		else
			sel.ids[petId] = true
			sel.n += 1
		end
		paintSelectBar()
	end

	selectToggle.MouseButton1Click:Connect(function()
		local sel = hudRefs.petSelect
		if sel.on then
			hudRefs.petSelectExit()
		else
			sel.on, sel.ids, sel.n = true, {}, 0
			paintSelectBar()
			if hudRefs.refreshPetsPanel then hudRefs.refreshPetsPanel() end
		end
	end)

	releaseButton.MouseButton1Click:Connect(function()
		local sel = hudRefs.petSelect
		if sel.n <= 0 then return end
		local list = {}
		for id in pairs(sel.ids) do table.insert(list, id) end
		if hudRefs.confirmReleaseMany then hudRefs.confirmReleaseMany(list) end
	end)

	paintSelectBar()

	-- The two blue counter capsules. The reference puts a green [+] on each of them -- an upsell for
	-- more slots -- and ours is not decoration: the equipped cap really is buyable, it is the PetSlot
	-- Diamond upgrade in the Shop, so the [+] opens that. See GameConfig.GetMaxEquippedPets.
	local function counterCapsule(order, emoji, onPlus)
		local capsule = Instance.new("Frame")
		capsule.Name = "Counter" .. order
		capsule.Size = UDim2.new(0, 150, 0, 46)
		capsule.LayoutOrder = order
		capsule.ZIndex = actionRow.ZIndex
		capsule.Parent = actionRow
		styleCard(capsule, UITheme.Color.Blue, UDim.new(1, 0), 4)

		local plus = Instance.new("TextButton")
		plus.Name = "Plus"
		plus.Size = UDim2.new(0, 34, 0, 34)
		plus.Position = UDim2.new(0, 7, 0.5, 0)
		plus.AnchorPoint = Vector2.new(0, 0.5)
		plus.Text = "+"
		plus.ZIndex = capsule.ZIndex + UITheme.Z.Content
		plus.Parent = capsule
		styleButton(plus, UITheme.Color.Green, UDim.new(0, 10), 3)
		plus.MouseButton1Click:Connect(onPlus)

		local count = Instance.new("TextLabel")
		count.Name = "Count"
		count.Size = UDim2.new(0, 62, 0, 34)
		count.Position = UDim2.new(0, 46, 0.5, 0)
		count.AnchorPoint = Vector2.new(0, 0.5)
		count.BackgroundTransparency = 1
		count.ZIndex = capsule.ZIndex + UITheme.Z.Content
		count.Text = "0"
		count.Parent = capsule
		themeLabel(count, 24)

		UITheme.IconSlot(capsule, {
			name = "Icon", icon = emoji, maxTextSize = 26,
			size = UDim2.new(0, 34, 0, 34), position = UDim2.new(1, -8, 0.5, 0),
			anchorPoint = Vector2.new(1, 0.5), zIndex = capsule.ZIndex + UITheme.Z.Content,
		})

		return count
	end

	-- read back by refreshPetsPanel, which is the only thing that knows the numbers
	hudRefs.petSlotCount = counterCapsule(3, "\u{1F43E}", function()
		toggleOnly(shopFrame)
	end)
	hudRefs.petOwnedCount = counterCapsule(4, "\u{1F392}", function()
		toggleOnly(shopFrame)
	end)

	-- These two remotes are newer than the authored Remotes folder, so they are fetched by name
	-- rather than indexed -- PetService creates whichever is missing when the server starts.
	task.spawn(function()
		local equipBest = Remotes:WaitForChild("EquipBestPets", 30)
		local unequipAll = Remotes:WaitForChild("UnequipAllPets", 30)
		if equipBest then
			equipBestButton.MouseButton1Click:Connect(function()
				equipBest:FireServer()
			end)
		end
		if unequipAll then
			unequipAllButton.MouseButton1Click:Connect(function()
				unequipAll:FireServer()
			end)
		end
	end)
end)()

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

-- Rarity and tier are two different axes and a pet row has to show both. RichText is the only
-- way to give one label two colours, so the rarity word carries its own colour inline while
-- themeLabel colours the rest of the line by tier.
local function colorTag(text, c)
	return string.format('<font color="#%02X%02X%02X">%s</font>',
		math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255), text)
end

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
;(function()
	-- A LIST SINCE 11.17, never a single id. `HandleDeletePets` has taken a list since 10.3 and the
	-- one-pet confirm already sent `{ id }`, so making the dialog itself list-shaped removes the last
	-- place the two paths could drift -- the multi-select confirm is the same frames, the same
	-- handler and the same remote call, differing only in how many ids went in.
	local pendingIds = nil

	-- Newer than the authored Remotes folder, so it is waited for by name rather than indexed --
	-- PetService creates it on server start. Resolved once here instead of on every confirm: a
	-- WaitForChild inside a click handler would yield the handler on the one frame it matters.
	local deleteRemote = nil
	task.spawn(function()
		deleteRemote = Remotes:WaitForChild("DeletePets", 30)
		if not deleteRemote then
			warn("[MainUI] Remotes.DeletePets never appeared -- pet release is disabled")
		end
	end)

	local shade4 = Instance.new("TextButton")
	shade4.Name = "ReleaseShade"
	shade4.Size = UDim2.new(1, 0, 1, 0)
	shade4.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	shade4.BackgroundTransparency = 0.45
	shade4.Text = ""
	shade4.AutoButtonColor = false
	shade4.Visible = false
	-- above every panel: this is a question, and anything drawn over it is a way to answer it by
	-- accident. The panels sit at ZIndex 20, so 60 clears them and their badges.
	shade4.ZIndex = 60
	shade4.Parent = screenGui

	local box = Instance.new("Frame")
	box.Name = "ReleaseDialog"
	box.Size = UDim2.new(0, 420, 0, 240)
	box.Position = UDim2.new(0.5, 0, 0.5, 0)
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.ZIndex = shade4.ZIndex + 1
	box.Parent = shade4
	styleCard(box, Color3.fromRGB(252, 252, 255), UDim.new(0, 18), 5)

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -32, 0, 40)
	title.Position = UDim2.new(0, 16, 0, 14)
	title.BackgroundTransparency = 1
	title.ZIndex = box.ZIndex + UITheme.Z.Content
	title.Text = "Release Pet?"
	title.Parent = box
	themeLabel(title, 30)

	local petLine = Instance.new("TextLabel")
	petLine.Name = "PetLine"
	petLine.Size = UDim2.new(1, -32, 0, 34)
	petLine.Position = UDim2.new(0, 16, 0, 60)
	petLine.BackgroundTransparency = 1
	petLine.RichText = true
	petLine.ZIndex = box.ZIndex + UITheme.Z.Content
	petLine.Text = ""
	petLine.Parent = box
	themeLabel(petLine, 24)

	local warn4 = Instance.new("TextLabel")
	warn4.Name = "Warning"
	-- two lines of room for one line of text: themeLabel floors at 14 px, so a box too short for
	-- its wrapped text clips the overflow rather than shrinking it, and reports nothing wrong
	warn4.Size = UDim2.new(1, -40, 0, 52)
	warn4.Position = UDim2.new(0, 20, 0, 98)
	warn4.BackgroundTransparency = 1
	warn4.TextWrapped = true
	warn4.ZIndex = box.ZIndex + UITheme.Z.Content
	warn4.Text = "This pet will be permanently deleted."
	warn4.Parent = box
	themeLabel(warn4, 18, Color3.fromRGB(120, 124, 138))

	local cancel = Instance.new("TextButton")
	cancel.Name = "Cancel"
	cancel.Size = UDim2.new(0, 210, 0, 56)
	cancel.Position = UDim2.new(0, 20, 1, -72)
	cancel.Text = "CANCEL"
	cancel.ZIndex = box.ZIndex + UITheme.Z.Content
	cancel.Parent = box
	styleButton(cancel, UITheme.Color.Blue, UDim.new(0, 12), 4)
	themeLabel(cancel, 24)

	local confirm = Instance.new("TextButton")
	confirm.Name = "Confirm"
	confirm.Size = UDim2.new(0, 152, 0, 56)
	confirm.Position = UDim2.new(1, -172, 1, -72)
	confirm.Text = "RELEASE"
	confirm.ZIndex = box.ZIndex + UITheme.Z.Content
	confirm.Parent = box
	styleButton(confirm, UITheme.Color.Red, UDim.new(0, 12), 4)
	themeLabel(confirm, 24)

	local function close()
		pendingIds = nil
		shade4.Visible = false
	end

	cancel.MouseButton1Click:Connect(close)
	-- clicking the darkened backdrop cancels, which is what every modal in every game does and what
	-- a player will try first
	shade4.MouseButton1Click:Connect(close)
	confirm.MouseButton1Click:Connect(function()
		local ids = pendingIds
		close()
		if ids and #ids > 0 and deleteRemote then
			deleteRemote:FireServer(ids)
			-- leave select mode on the way out, so the panel does not come back still armed with a
			-- selection whose pets no longer exist
			if hudRefs.petSelectExit then hudRefs.petSelectExit() end
		end
	end)

	hudRefs.confirmRelease = function(petId, displayName, rarityName, rarityColor)
		pendingIds = { petId }
		title.Text = "Release Pet?"
		petLine.Text = ("%s  %s"):format(displayName or "Pet",
			colorTag(rarityName or "", rarityColor or UITheme.Color.White))
		warn4.Text = "This pet will be permanently deleted."
		shade4.Visible = true
	end

	-- ===== THE SAME DIALOG, MANY PETS (11.17) =====
	--
	-- It names the COUNT rather than listing them: a release of thirty cannot show thirty names in a
	-- 420 px box, and a truncated list ("Wolf, Wolf, Wolf and 27 more") is worse than a number
	-- because it invites the reader to believe they have checked it. The place to check WHICH pets
	-- is the grid behind this dialog, where every one of them is drawn with a lit checkbox.
	--
	-- Copied rather than referenced: the caller's table is the live selection set and it keeps
	-- changing while this box is open, so holding a reference would let a click behind the dim
	-- change what CONFIRM is about to do.
	hudRefs.confirmReleaseMany = function(ids)
		if type(ids) ~= "table" or #ids == 0 then return end
		local copy = table.create(#ids)
		table.move(ids, 1, #ids, 1, copy)
		pendingIds = copy
		title.Text = ("Release %d Pets?"):format(#copy)
		petLine.Text = ("%d selected"):format(#copy)
		warn4.Text = ("All %d will be permanently deleted. Equipped pets are never included."):format(#copy)
		shade4.Visible = true
	end
end)()

-- ===== Pet Fusion panel =====
-- Fusing is a decision about a GROUP -- four identical pets go in, one of the next tier comes out
-- -- so this panel lists GROUPS, not pets. Each row is one species at one tier, and it states the
-- whole trade before you commit: how many you own, how many it takes, and what the result is
-- worth against what you are giving up.
--
-- Built inside an immediately-called function so its locals get a register file of their own --
-- see the note on the Season Pass panel for why a `do` block is not enough. Handles via `hudRefs`.
;(function()
	local panel = Instance.new("Frame")
	panel.Name = "FusionPanel"
	panel.Size = UDim2.new(0, 500, 0, 520)
	panel.Position = PANEL_ANCHOR
	panel.ZIndex = 20
	panel.Visible = false
	panel.Parent = screenGui
	styleCard(panel, PANEL_SHELL, UDim.new(0, 22), 5)
	registerPanel(panel)
	panelClose(panel)

	-- This panel already had the closest thing to what 11.13 asks for -- a purple hint card under the
	-- title -- and that card is exactly what the header band generalises. The card STAYS, because it
	-- carries a number (`FuseRequirement`) that has already changed once; the subtitle carries the
	-- part that never does.
	UITheme.PanelHeader(panel, {
		title = "\u{1F9EC} Pet Fusion",
		subtitle = "Trade duplicates upward -- Rainbow, then Celestial",
		accent = UITheme.Color.Purple,
		maxTextSize = 28,
	})

	local hint = Instance.new("Frame")
	hint.Size = UDim2.new(1, -32, 0, 44)
	hint.Position = UDim2.new(0, 16, 0, 94)
	hint.Parent = panel
	styleCard(hint, UITheme.Color.Purple, UDim.new(0, 14), 4)

	local hintLabel = Instance.new("TextLabel")
	hintLabel.Size = UDim2.new(1, -20, 1, -8)
	hintLabel.Position = UDim2.new(0, 10, 0, 2)
	hintLabel.BackgroundTransparency = 1
	hintLabel.TextWrapped = true
	hintLabel.Text = ("Fuse %d of the same pet at the same tier into one of the next tier.")
		:format(GameConfig.FuseRequirement)
	hintLabel.Parent = hint
	themeLabel(hintLabel, 18)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "FusionScroll"
	-- header 14+68, gap 12, hint 44, gap 12 => 150; bottom margin 16, so 166 short.
	scroll.Size = UDim2.new(1, -32, 1, -166)
	scroll.Position = UDim2.new(0, 16, 0, 150)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.Parent = panel

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = scroll

	-- ===== THE CATALYST CARDS LIVE HERE NOW (11.7) =====
	--
	-- They used to be two tiles in the Robux grid, between a DNA pack and a potion crate. A catalyst
	-- answers exactly one question -- "I have two of these and I need three" -- and that question is
	-- asked here, looking at a row that says (2/3), not while scrolling a wall of currency packs.
	--
	-- Built ONCE, outside `refresh`, with negative LayoutOrder so they sit above the fusion rows and
	-- survive every rebuild of the list below. Driven off `GameConfig.RobuxProducts` rather than
	-- hand-written, so the price on the button is the price in the table and the two cannot drift --
	-- which is the same reason the grid prints its own price rather than a typed string.
	local catalystRows = 0
	for _, product in ipairs(GameConfig.RobuxProducts) do
		if product.panelCard and not product.delisted then
			catalystRows += 1
			local row = Instance.new("Frame")
			row.Name = product.key
			row.Size = UDim2.new(1, -10, 0, 66)
			row.LayoutOrder = -100 + catalystRows
			row.Parent = scroll
			styleCard(row, UITheme.Color.Pink, UDim.new(0, 12), 3)

			UITheme.IconSlot(row, {
				name = "Icon", icon = product.emoji, maxTextSize = 30,
				size = UDim2.new(0, 48, 0, 48), position = UDim2.new(0, 10, 0, 9),
			})

			local title = Instance.new("TextLabel")
			title.Name = "NameLabel"
			title.Size = UDim2.new(1, -210, 0, 26)
			title.Position = UDim2.new(0, 66, 0, 10)
			title.BackgroundTransparency = 1
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.Text = product.name
			title.ZIndex = row.ZIndex + UITheme.Z.Content
			title.Parent = row
			themeLabel(title, 20)

			local sub = Instance.new("TextLabel")
			sub.Name = "SubLabel"
			sub.Size = UDim2.new(1, -210, 0, 22)
			sub.Position = UDim2.new(0, 66, 0, 34)
			sub.BackgroundTransparency = 1
			sub.TextXAlignment = Enum.TextXAlignment.Left
			-- says what it SKIPS, in the unit this panel is already counting in -- and SHORT, because
			-- the label is 226 px wide next to the price button and the first version of this
			-- sentence clipped at the minimum text size (found by 11.13's sweep, not by reading it)
			sub.Text = ("%d pets up a tier, no copies"):format(product.grantTierUps or 1)
			sub.ZIndex = row.ZIndex + UITheme.Z.Content
			sub.Parent = row
			themeLabel(sub, 16, UITheme.Color.Cream)

			local buy = Instance.new("TextButton")
			buy.Name = "BuyButton"
			buy.Size = UDim2.new(0, 118, 0, 44)
			buy.Position = UDim2.new(1, -12, 0.5, -22)
			buy.AnchorPoint = Vector2.new(1, 0)
			buy.Text = "R$ " .. product.price
			buy.ZIndex = row.ZIndex + UITheme.Z.Content
			buy.Parent = row
			styleButton(buy, UITheme.Color.Green, UDim.new(1, 0))
			buy.MouseButton1Click:Connect(function()
				Remotes.PromptRobuxPurchase:FireServer(product.key)
			end)
		end
	end

	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.Name = "EmptyLabel"
	emptyLabel.Size = UDim2.new(1, 0, 0, 66)
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.TextWrapped = true
	emptyLabel.LayoutOrder = 0
	emptyLabel.Text = ("Nothing to fuse yet \u{2014} you need %d copies of one pet at the same tier.")
		:format(GameConfig.FuseRequirement)
	emptyLabel.Parent = scroll
	themeLabel(emptyLabel, 20, UITheme.Color.Cream)

	-- GetPetPower is a SHARE OF THE PLAYER'S DAMAGE now, not the old 1..64 tier x rarity product, so
	-- it runs about 0.03 to 3.4 -- and "x0.1" as a power chip says nothing to anybody. Rendered as
	-- the percentage of damage the pet adds, which is the same unit the pet rows and the catalyst
	-- rows already print, so one pet reads the same number everywhere in the UI.
	local function powerText(p)
		return ("+%d%%"):format(math.floor(p * 100 + 0.5))
	end

	local function refresh()
		if not currentData then return end
		local data = currentData

		for _, child in ipairs(scroll:GetChildren()) do
			if child:IsA("Frame") and (child.Name == "FuseRow" or child.Name == "CatalystRow") then
				child:Destroy()
			end
		end

		-- one entry per species+tier, because that pairing is exactly what HandleFuse consumes
		local groups, order = {}, {}
		for _, pet in ipairs(data.Pets) do
			local groupKey = pet.key .. "|" .. pet.tier
			local g = groups[groupKey]
			if not g then
				-- firstId is what a Catalyst is spent on: a catalyst raises ONE pet, so the row needs a
				-- specific id, where a fuse only needs the species and tier
				g = { key = pet.key, tier = pet.tier, count = 0, firstId = pet.id, firstEnchant = pet.enchant }
				groups[groupKey] = g
				table.insert(order, g)
			end
			g.count += 1
			-- ===== THE GROUP'S BEST ENCHANT, AND WHY IT IS THE HONEST ONE TO QUOTE (13.1) =====
			--
			-- A group is many pets and they can carry different enchants, so there is no single
			-- "the" enchant for a fuse row -- but there is one the player can count on: HandleFuse
			-- consumes the STRONGEST-enchanted copies and carries the best of them onto the
			-- result, so the best in the group is exactly what comes out the other side. Client and
			-- server therefore agree by construction rather than by keeping two rules in step.
			if GameConfig.IsEnchantBetter(pet.enchant, g.bestEnchant) then
				g.bestEnchant = pet.enchant
			end
		end

		-- Groups that CANNOT fuse are dropped, not greyed out. A maxed-tier pet or a lone copy is
		-- not a choice the player has, and a hundred dead rows hide the four live ones.
		local ready = {}
		for _, g in ipairs(order) do
			g.nextTier = GameConfig.GetNextTier(g.tier)
			if g.nextTier and g.count >= GameConfig.FuseRequirement then
				-- `data` carries the zone axis into the ranking, so the fusion list is ordered by what
				-- these pets are worth to this player now rather than by what they were worth in the
				-- zone they hatched in
				-- the enchant rides BOTH sides, so the ratio the row prints is untouched by it and the
				-- two absolute figures are the ones the surviving pet actually carries
				g.power = GameConfig.GetPetPower({ key = g.key, tier = g.tier, enchant = g.bestEnchant }, data)
				g.nextPower = GameConfig.GetPetPower({ key = g.key, tier = g.nextTier, enchant = g.bestEnchant }, data)
				table.insert(ready, g)
			end
		end
		table.sort(ready, function(a, b)
			if a.nextPower ~= b.nextPower then return a.nextPower > b.nextPower end
			return a.key < b.key
		end)

		-- ===== THE CATALYST ROWS =====
		--
		-- They sit at the top of the same scroll rather than in a panel of their own, because they are
		-- the same decision as the rows below -- "make this pet stronger" -- reached by paying instead
		-- of by grinding. A player comparing the two should not have to hold one in their head while
		-- they go and look at the other. (It is also the only option: this file is at Luau's 200-local
		-- register cap and everything here lives inside one immediately-called function.)
		--
		-- Unlike the fuse rows, a group with ONE copy is a perfectly good catalyst target -- not needing
		-- four copies is the entire product -- so these are filtered only by the tier cap.
		local catalysts = {}
		for _, g in ipairs(order) do
			local step = GameConfig.GetCatalystNextTier(g.tier)
			if step then
				g.catalystTier = step
				table.insert(catalysts, g)
			end
		end
		table.sort(catalysts, function(a, b)
			-- `firstEnchant`, not `bestEnchant`: a catalyst is spent on `firstId`, one specific pet,
			-- and it mutates that pet's tier in place -- so the enchant that survives is that pet's
			local pa = GameConfig.GetPetPower({ key = a.key, tier = a.catalystTier, enchant = a.firstEnchant }, data)
			local pb = GameConfig.GetPetPower({ key = b.key, tier = b.catalystTier, enchant = b.firstEnchant }, data)
			if pa ~= pb then return pa > pb end
			return a.key < b.key
		end)

		local tokens = (currentData and currentData.TierUpTokens) or 0
		local shown = 0
		for _, g in ipairs(catalysts) do
			if shown >= 6 then break end
			shown += 1
			local info = petDisplayInfo(g.key)

			local row = Instance.new("Frame")
			row.Name = "CatalystRow"
			row.LayoutOrder = -1000 + shown
			row.Size = UDim2.new(1, 0, 0, 72)
			row.Parent = scroll
			styleCard(row, UITheme.Color.Pink or PET_ROW_SHELL, UDim.new(0, 14), 4)

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(0, 250, 0, 28)
			nameLabel.Position = UDim2.new(0, 16, 0, 8)
			nameLabel.BackgroundTransparency = 1
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.Text = ("\u{1F308} %s %s"):format(info.emoji, info.name)
			nameLabel.Parent = row
			themeLabel(nameLabel, 23)

			-- THE GAIN IS QUOTED IN DAMAGE, BECAUSE DAMAGE IS NOW THE ONLY THING A PET PAYS.
			--
			-- This read `incomeMult` until the pet rebalance, and that field is a hard 1 today -- so
			-- left alone this row would have advertised "income x1.00 -> x1.00 (+0%)" on a card the
			-- player is about to spend Robux against. A stat that no longer exists cannot be the
			-- headline of a purchase.
			--
			-- Still read off GetPetBonus rather than GetPetPower for the original reason: the tier
			-- ladder divides out to a constant ratio, but what the player actually gains is the
			-- share ON TOP of 1, so only the bonus itself can quote the real step. Both calls pass
			-- `pet key` and `data`, so the quote is what this player gets at their current rung.
			local fromBonus = GameConfig.GetPetBonus(g.tier, info.rarity, g.key, data, g.firstEnchant).damageMult
			local toBonus = GameConfig.GetPetBonus(g.catalystTier, info.rarity, g.key, data, g.firstEnchant).damageMult
			local gainLabel = Instance.new("TextLabel")
			gainLabel.Size = UDim2.new(0, 290, 0, 24)
			gainLabel.Position = UDim2.new(0, 16, 1, -32)
			gainLabel.BackgroundTransparency = 1
			gainLabel.TextXAlignment = Enum.TextXAlignment.Left
			gainLabel.RichText = true
			gainLabel.Text = ("%s \u{2192} %s   damage x%.2f \u{2192} %s"):format(
				g.tier,
				colorTag(g.catalystTier, GameConfig.PetTierColor[g.catalystTier] or UITheme.Color.White),
				fromBonus,
				colorTag(("x%.2f (+%.0f%%)"):format(toBonus, (toBonus / fromBonus - 1) * 100), READY_RIM))
			gainLabel.Parent = row
			themeLabel(gainLabel, 17, UITheme.Color.Cream)

			local btn = Instance.new("TextButton")
			btn.Name = "CatalystButton"
			btn.Size = UDim2.new(0, 118, 0, 46)
			btn.Position = UDim2.new(1, -12, 0.5, -23)
			btn.AnchorPoint = Vector2.new(1, 0)
			-- With no token in hand the row is not hidden, it becomes the offer. Hiding it would make a
			-- product nobody has heard of, and the moment a player is looking at their pets is the one
			-- moment they care what a tier is worth.
			-- THE PRICE IS READ, NOT TYPED (11.7). This said "R$ 99" as a literal, and 11.7 moved the
			-- product to 49 -- so the row would have advertised one number and charged another. The
			-- grid has always read `product.price` for exactly this reason; this row had been missed.
			btn.Text = tokens > 0 and ("USE (%d)"):format(tokens)
				or ("R$ " .. tostring(GameConfig.GetRobuxProduct("TierUp_1").price))
			btn.Parent = row
			styleButton(btn, tokens > 0 and UITheme.Color.Green or UITheme.Color.Gold, UDim.new(1, 0))
			btn.MouseButton1Click:Connect(function()
				if tokens > 0 then
					Remotes.UseTierUp:FireServer(g.firstId)
				else
					Remotes.PromptRobuxPurchase:FireServer("TierUp_1")
				end
			end)
		end

		emptyLabel.Visible = (#ready == 0 and shown == 0)

		for i, g in ipairs(ready) do
			local info = petDisplayInfo(g.key)
			local rarity = GameConfig.GetRarity(info.rarity)

			local row = Instance.new("Frame")
			row.Name = "FuseRow"
			row.LayoutOrder = i
			row.Size = UDim2.new(1, 0, 0, 72)
			row.Parent = scroll
			styleCard(row, PET_ROW_SHELL, UDim.new(0, 14), 4)

			local stripe = Instance.new("Frame")
			stripe.Size = UDim2.new(0, 7, 1, -20)
			stripe.Position = UDim2.new(0, 8, 0.5, 0)
			stripe.AnchorPoint = Vector2.new(0, 0.5)
			stripe.BackgroundColor3 = rarity.color
			stripe.BorderSizePixel = 0
			stripe.ZIndex = row.ZIndex + UITheme.Z.Content
			stripe.Parent = row
			corner(stripe, UDim.new(1, 0))

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(0, 250, 0, 28)
			nameLabel.Position = UDim2.new(0, 26, 0, 8)
			nameLabel.BackgroundTransparency = 1
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.RichText = true
			nameLabel.Text = ("%s %s  %s"):format(info.emoji, info.name,
				colorTag(("(%d/%d)"):format(g.count, GameConfig.FuseRequirement), READY_RIM))
			nameLabel.Parent = row
			themeLabel(nameLabel, 23)

			-- THE ANSWER TO "how much stronger": both sides of the trade and the ratio between them,
			-- on one line. Printing only the result would leave the player doing the division.
			local gainLabel = Instance.new("TextLabel")
			gainLabel.Size = UDim2.new(0, 260, 0, 24)
			gainLabel.Position = UDim2.new(0, 26, 1, -32)
			gainLabel.BackgroundTransparency = 1
			gainLabel.TextXAlignment = Enum.TextXAlignment.Left
			gainLabel.RichText = true
			gainLabel.Text = ("%s %s  \u{2192}  %s %s"):format(
				g.tier, powerText(g.power),
				colorTag(g.nextTier, GameConfig.PetTierColor[g.nextTier] or UITheme.Color.White),
				colorTag(powerText(g.nextPower) .. ((" (+%.0f%%)"):format((g.nextPower / g.power - 1) * 100)), READY_RIM))
			gainLabel.Parent = row
			themeLabel(gainLabel, 17, UITheme.Color.Cream)

			-- THE WARNING THE RATIO ABOVE DOES NOT COVER.
			--
			-- "+92%" is true of the PET and can be false of the PLAYER. Equipped bonuses multiply
			-- across three slots, so a player who owns four pets and fuses all four goes from three
			-- equipped to one -- their actual damage falls even though every number on this row went
			-- up. The server now re-equips the result, which recovers most of it, but a shallow
			-- collection still ends the trade with emptier slots and the player deserves to know
			-- before pressing rather than after.
			if currentData and #currentData.Pets - GameConfig.FuseRequirement + 1
				< #currentData.EquippedPetIds then
				local warn_ = Instance.new("TextLabel")
				warn_.Size = UDim2.new(0, 300, 0, 20)
				warn_.Position = UDim2.new(0, 26, 1, -12)
				warn_.BackgroundTransparency = 1
				warn_.TextXAlignment = Enum.TextXAlignment.Left
				warn_.Text = "\u{26A0}\u{FE0F} You'll have fewer pets equipped after this"
				warn_.ZIndex = row.ZIndex + UITheme.Z.Content
				warn_.Parent = row
				themeLabel(warn_, 15, Color3.fromRGB(255, 186, 120))
			end

			local fuseBtn = Instance.new("TextButton")
			fuseBtn.Name = "FuseButton"
			fuseBtn.Size = UDim2.new(0, 108, 0, 46)
			fuseBtn.Position = UDim2.new(1, -12, 0.5, -23)
			fuseBtn.AnchorPoint = Vector2.new(1, 0)
			fuseBtn.Text = ("FUSE %d"):format(GameConfig.FuseRequirement)
			fuseBtn.Parent = row
			styleButton(fuseBtn, UITheme.Color.Purple, UDim.new(1, 0))
			fuseBtn.MouseButton1Click:Connect(function()
				Remotes.FusePet:FireServer(g.key, g.tier)
			end)
		end

		-- + the catalyst cards, which are not in `ready` or `shown` because they are built once above
		-- and never rebuilt. Leaving them out of this sum is how the last two fusion rows become
		-- unreachable behind the bottom of the scroll.
		scroll.CanvasSize = UDim2.new(0, 0, 0, (#ready + shown) * 78 + catalystRows * 72 + 40)
	end

	hudRefs.refreshFusionPanel = refresh
	hudRefs.showFusionPanel = function()
		toggleOnly(panel)
		refresh()
	end
end)()

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
rebirthReqCard.Name = "ReqCard"
rebirthReqCard.Size = UDim2.new(1, -32, 0, 176)
-- 132 -> 154, clearing the ladder bar above it. The panel grew by the same 24 (see its Size), so
-- nothing below this moved relative to the bottom edge.
rebirthReqCard.Position = UDim2.new(0, 16, 0, 192)
rebirthReqCard.Parent = rebirthPanel
styleCard(rebirthReqCard, UITheme.Color.Gold, UDim.new(0, 14), 4)

local rebirthReqLabel = Instance.new("TextLabel")
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
;(function()
	-- Full chroma, one per rung; wrapped rather than indexed directly so a ladder longer than the
	-- palette (17.14 is open on exactly that) repeats colours instead of handing `DoneShade` a nil.
	local hues = { UITheme.Color.Aqua, UITheme.Color.Mint, UITheme.Color.Lavender, UITheme.Color.Gold }
	local count = math.max(GameConfig.MaxRebirths, 1)

	-- MEASURED OFF THE CARD, NOT TYPED. The card is 176 tall; 7 px of margin top and bottom and a
	-- 6 px gutter leaves 36 px a row at four rungs and 27 at five, so the block always fills the box
	-- it was added to fill and a fifth rebirth cannot push a row out of the bottom of it.
	local gap = 6
	local inset = 7
	local rowH = math.floor(((rebirthReqCard.Size.Y.Offset - inset * 2) - gap * (count - 1)) / count)
	local rungs = {}

	for tier = 1, count do
		local hue = hues[((tier - 1) % #hues) + 1]

		local row = Instance.new("Frame")
		row.Name = "Rung" .. tier
		row.Size = UDim2.new(1, -24, 0, rowH)
		row.Position = UDim2.new(0, 12, 0, inset + (tier - 1) * (rowH + gap))
		row.Visible = false
		-- A CHIP LYING ON A CARD, NOT A RAISED OBJECT (18.5). Without this the soft sprite would
		-- draw a second shadow inside the one the gold card already casts, which is what makes a
		-- stack of nested surfaces look like fog rather than like layers.
		row:SetAttribute("NoShadow", true)
		row.Parent = rebirthReqCard
		styleCard(row, UITheme.DoneShade(hue), UDim.new(0, 10), 3)

		-- The rank disc is the one thing on the row at full chroma: the row says "spent", the disc
		-- says "and this is which one". Radius Pill, so `DropShadow` declines it on shape alone.
		local disc = Instance.new("Frame")
		disc.Name = "Rank"
		disc.Size = UDim2.new(0, rowH - 10, 0, rowH - 10)
		disc.Position = UDim2.new(0, 7, 0.5, 0)
		disc.AnchorPoint = Vector2.new(0, 0.5)
		disc.ZIndex = row.ZIndex + UITheme.Z.Badge
		disc.Parent = row
		styleCard(disc, hue, UDim.new(1, 0), 2)

		local rank = Instance.new("TextLabel")
		rank.Name = "RankLabel"
		rank.Size = UDim2.new(1, 0, 1, 0)
		rank.BackgroundTransparency = 1
		rank.Text = tostring(tier)
		rank.ZIndex = disc.ZIndex + UITheme.Z.Content
		rank.Parent = disc
		-- white on a 0.64-0.78 pastel (Lavender through Gold), all of it under UITheme's 0.86
		-- light-surface cut, so the chunky halo is the right answer and `themeLabel` keeps it
		themeLabel(rank, math.max(rowH - 18, 14))

		local where = Instance.new("TextLabel")
		where.Name = "StageLabel"
		where.Size = UDim2.new(0, 96, 1, -8)
		where.Position = UDim2.new(0, rowH + 4, 0, 4)
		where.BackgroundTransparency = 1
		where.TextXAlignment = Enum.TextXAlignment.Left
		where.Text = ("Stage %d"):format(GameConfig.GetRebirthTierStageIndex(tier))
		where.ZIndex = row.ZIndex + UITheme.Z.Content
		where.Parent = row
		-- Ink, not white: a DoneShade is a light surface BY CONSTRUCTION (luminance 0.90), so this is
		-- the `inkOn` answer rather than a taste call, and themeLabel drops the halo with it.
		themeLabel(where, 16, UITheme.Color.Ink)

		-- WHAT THIS RUNG PAID, as the running totals it left behind rather than as its own increment.
		-- "+1.5x income" is a number nobody can act on; "you permanently earn x4.00 from here" is the
		-- shape the info card above already uses and the only one in which a spent milestone reads as
		-- a gain.
		local paid = Instance.new("TextLabel")
		paid.Name = "PaidLabel"
		paid.Size = UDim2.new(1, -(rowH + 106), 1, -8)
		paid.Position = UDim2.new(1, -10, 0, 4)
		paid.AnchorPoint = Vector2.new(1, 0)
		paid.BackgroundTransparency = 1
		paid.TextXAlignment = Enum.TextXAlignment.Right
		paid.Text = ("\u{2694}\u{FE0F} x%.2f    \u{1F9EC} x%.2f"):format(
			GameConfig.GetRebirthDamageMult({ Rebirths = tier }),
			GameConfig.GetRebirthIncomeMult({ Rebirths = tier }))
		paid.ZIndex = row.ZIndex + UITheme.Z.Content
		paid.Parent = row
		themeLabel(paid, 16, UITheme.Color.Ink)

		rungs[tier] = row
	end

	-- One handle out, called from `refreshRebirthPanel` below. The sentence and the rungs are the two
	-- halves of one switch and are never both on: the card is 176 px and either fills with prose or
	-- fills with rows.
	hudRefs.setRebirthRungs = function(show)
		rebirthReqLabel.Visible = not show
		for _, row in ipairs(rungs) do
			row.Visible = show
		end
	end
end)()

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
;(function()
	local beaconGui = Instance.new("ScreenGui")
	beaconGui.Name = "RebirthBeacon"
	beaconGui.ResetOnSpawn = false
	beaconGui.IgnoreGuiInset = false
	beaconGui.DisplayOrder = 90
	beaconGui.Enabled = false
	beaconGui.Parent = playerGui

	-- A ring that pulses AROUND the tile rather than a badge on top of it: the tile already carries
	-- an icon and a caption, and covering either to say "press me" hides what is being pressed.
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.BackgroundTransparency = 1
	ring.Parent = beaconGui
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(0, 22)
	ringCorner.Parent = ring
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Thickness = 4
	ringStroke.Color = UITheme.Color.Gold
	ringStroke.Transparency = 0.15
	ringStroke.Parent = ring

	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.Size = UDim2.new(0, 62, 0, 62)
	arrow.AnchorPoint = Vector2.new(0, 0.5)
	arrow.BackgroundTransparency = 1
	arrow.Text = "\u{27A1}\u{FE0F}"
	arrow.TextScaled = true
	arrow.Parent = beaconGui

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(0, 186, 0, 34)
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Text = "REBIRTH READY"
	label.Parent = beaconGui
	styleCard(label, UITheme.Color.Gold, UDim.new(0, 12), 3)
	themeLabel(label, 19)

	local conn
	local function stop()
		if conn then conn:Disconnect() conn = nil end
		beaconGui.Enabled = false
	end

	hudRefs.setRebirthReady = function(ready)
		if not ready then stop() return end
		if conn then return end -- already running; never stack a second Heartbeat
		beaconGui.Enabled = true
		local t0 = os.clock()
		conn = RunService.Heartbeat:Connect(function()
			-- the tile can be gone for a frame during a respawn or a layout pass
			if not rebirthButton.Parent then return end
			local pos, size = rebirthButton.AbsolutePosition, rebirthButton.AbsoluteSize
			if size.X < 1 then return end
			local t = os.clock() - t0
			local pulse = 0.5 + 0.5 * math.sin(t * 3.2)

			-- the ring breathes OUTWARD from the tile, so it never covers the icon
			local grow = 10 + pulse * 8
			ring.Position = UDim2.fromOffset(pos.X + size.X * 0.5, pos.Y + size.Y * 0.5)
			ring.Size = UDim2.fromOffset(size.X + grow * 2, size.Y + grow * 2)
			ringStroke.Transparency = 0.1 + pulse * 0.45

			-- and the arrow nudges toward the tile from its right, the one side the tile column
			-- never occupies (the left column is pinned at x = 20)
			local nudge = math.abs(math.sin(t * 3.2)) * 10
			local ax = pos.X + size.X + 16 + nudge
			arrow.Position = UDim2.fromOffset(ax, pos.Y + size.Y * 0.5)
			label.Position = UDim2.fromOffset(ax + 66, pos.Y + size.Y * 0.5)
		end)
	end

	-- the panel is what decides; this is only ever told. Start hidden so a save that arrives locked
	-- never flashes it.
	stop()
end)()

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
;(function()
	local bar = Instance.new("Frame")
	bar.Name = "CodeBar"
	bar.Size = UDim2.new(1, -50, 0, 44)
	-- directly above the banner: banner sits at 1,-14 and is 44 tall, so its top edge is 1,-58
	bar.Position = UDim2.new(0.5, 0, 1, -66)
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.BackgroundTransparency = 1
	bar.ZIndex = rewardPanel.ZIndex + 1
	bar.Parent = rewardPanel

	local shell = Instance.new("Frame")
	shell.Name = "InputShell"
	shell.Size = UDim2.new(0.60, -6, 1, 0)
	shell.ZIndex = bar.ZIndex
	shell.Parent = bar
	-- PanelWhite, and the text on it is Outline rather than white: this is the one input surface in
	-- the game and a typed code has to be readable while it is being typed
	styleCard(shell, UITheme.Color.PanelWhite, UDim.new(1, 0), 4)

	local box = Instance.new("TextBox")
	box.Name = "CodeInput"
	box.BackgroundTransparency = 1
	box.Size = UDim2.new(1, -28, 1, -12)
	box.Position = UDim2.new(0, 14, 0.5, 0)
	box.AnchorPoint = Vector2.new(0, 0.5)
	box.ClearTextOnFocus = false
	box.Text = ""
	box.PlaceholderText = "\u{1F39F}\u{FE0F}  Enter a code..."
	box.PlaceholderColor3 = Color3.fromRGB(140, 136, 158)
	box.TextColor3 = UITheme.Color.Outline
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Font = UITheme.Font.Display
	box.TextScaled = true
	box.ZIndex = bar.ZIndex + UITheme.Z.Content
	box.Parent = shell
	local boxClamp = Instance.new("UITextSizeConstraint")
	boxClamp.MinTextSize = 14
	boxClamp.MaxTextSize = 22
	boxClamp.Parent = box

	local redeemButton = UITheme.Button(bar, {
		name = "Redeem", text = "REDEEM", color = UITheme.Color.Green,
		size = UDim2.new(0.25, -6, 1, 0), position = UDim2.new(0.60, 6, 0, 0),
		radius = 12, zIndex = bar.ZIndex, maxTextSize = 22, shadow = false,
	})

	local leftLabel = Instance.new("TextLabel")
	leftLabel.Name = "CodesLeft"
	leftLabel.Size = UDim2.new(0.15, -6, 1, 0)
	leftLabel.Position = UDim2.new(0.85, 6, 0, 0)
	leftLabel.BackgroundTransparency = 1
	leftLabel.Text = ""
	leftLabel.ZIndex = bar.ZIndex + UITheme.Z.Content
	leftLabel.Parent = bar
	themeLabel(leftLabel, 20)

	local function submit()
		local typed = box.Text
		if typed:gsub("%s", "") == "" then return end
		-- looked up rather than held, like the audio remote: CodesService creates it in Init and a
		-- WaitForChild at build time would stall the HUD if that ever stopped happening
		local remote = Remotes:FindFirstChild("RedeemCode")
		if remote then
			remote:FireServer(typed)
		end
		-- cleared either way. The server answers with a toast, and leaving a refused code sitting in
		-- the box invites the player to press REDEEM again into the rate limiter.
		box.Text = ""
	end

	redeemButton.MouseButton1Click:Connect(submit)
	-- Enter submits: this is a box people paste into off a web page, and reaching for a button
	-- afterwards is the kind of small friction that makes a code feel broken
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then submit() end
	end)

	-- Counted CLIENT-SIDE off GameConfig and the save the client already holds -- the same arithmetic
	-- CodesService.CountUnused does server-side, but asking for it would be a remote round trip for a
	-- number both sides can already see.
	hudRefs.refreshCodes = function(data)
		local redeemed = (data and data.RedeemedCodes) or {}
		local left = 0
		for _, entry in ipairs(GameConfig.Codes) do
			if not GameConfig.IsCodeExpired(entry)
				and not redeemed[GameConfig.NormaliseCode(entry.code)] then
				left += 1
			end
		end
		-- says nothing at all when there is nothing left to say, rather than printing "0 left" as a
		-- small permanent disappointment on the free-stuff screen
		leftLabel.Text = left > 0 and (left .. " new") or ""
	end
end)()

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
local function dayNumber(timestamp)
	return math.floor((timestamp or 0) / SECONDS_PER_DAY)
end

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
;(function()
	local button = UITheme.Button(rewardPanel, {
		name = "FreeSpin", text = "\u{1F3A1} FREE SPIN", color = UITheme.Color.Gold,
		-- 54 -> 90: at 54 this pair sat INSIDE the accent band, printing over the streak subtitle.
		-- 90 puts them in their own row between the band (ends 82) and the day grid (starts 142).
		size = UDim2.new(0, 220, 0, 42), position = UDim2.new(1, -22, 0, 90),
		anchorPoint = Vector2.new(1, 0), radius = 14,
		zIndex = rewardPanel.ZIndex + 1, maxTextSize = 22,
	})

	-- THE SHARD SPIN SITS BESIDE THE FREE ONE, and that placement is the point (9.4). They are the
	-- same wheel reached by two triggers, so putting them together is what makes the relationship
	-- legible -- free once a day, or 25 Shards whenever you have climbed for them -- where a shard
	-- wheel hidden on some other screen would read as a second, different gamble. It fits in the
	-- band the streak card (ends x262) and the free spin button (starts x458) leave empty, so
	-- nothing already measured on this panel moves.
	local shardButton = UITheme.Button(rewardPanel, {
		name = "ShardSpin", text = "\u{1F3A1} SPIN 25\u{1F31F}", color = UITheme.Color.Locked,
		size = UDim2.new(0, 170, 0, 42), position = UDim2.new(1, -250, 0, 90),
		anchorPoint = Vector2.new(1, 0), radius = 14,
		zIndex = rewardPanel.ZIndex + 1, maxTextSize = 22,
	})

	-- "7h 12m", "12m", "45s" -- the same shape the offline card uses, for the same reason: the
	-- player is reading it for "roughly when", not for the exact second.
	local function countdown(seconds)
		seconds = math.max(math.floor(seconds), 0)
		local h = seconds // 3600
		local m = (seconds % 3600) // 60
		if h > 0 then return ("%dh %dm"):format(h, m) end
		if m > 0 then return ("%dm"):format(m) end
		return ("%ds"):format(seconds)
	end

	-- Held inside this closure rather than as a top-level local: MainUI is at Luau's 200-local
	-- register cap and one more up there deletes the whole HUD. It is also the only thing `refresh`
	-- below needs to know about the nag, so it does not want to be visible any wider.
	local nagUntil = 0

	local function refresh()
		if not currentData then return end
		-- a "not ready yet" message on a button gets one and a half seconds to be read before the
		-- one-second tick below paints the countdown back over it
		if os.clock() < nagUntil then return end
		local ready = dayNumber(os.time()) > dayNumber(currentData.LastFreeSpin)
		if ready then
			UITheme.SetColor(button, UITheme.Color.Gold)
			UITheme.SetText(button, "\u{1F3A1} FREE SPIN!")
		else
			-- colour AND wording, like the Auto tile and the mute button: a control that only changes
			-- hue leaves the player guessing whether it is off or just decorated
			UITheme.SetColor(button, UITheme.Color.Locked)
			UITheme.SetText(button, "\u{1F3A1} " .. countdown((dayNumber(os.time()) + 1) * SECONDS_PER_DAY - os.time()))
		end

		-- The shard button reads the same price the server charges (GameConfig.SpinCostShards), so it
		-- can never offer a spin SpendShardSpin will refuse -- the property the evolve button has
		-- against GetEvolveStep and the free spin has against GetFreeSpinStatus.
		--
		-- When it cannot be afforded it shows PROGRESS rather than the price again. "12 / 25" tells a
		-- player who has never seen a shard both what the thing costs and that they are getting
		-- there; a greyed-out "SPIN 25" tells them only that they cannot press it.
		local cost = GameConfig.SpinCostShards
		local held = math.floor(currentData.EvolutionShards or 0)
		if held >= cost then
			UITheme.SetColor(shardButton, UITheme.Color.Purple)
			UITheme.SetText(shardButton, ("\u{1F3A1} SPIN %d\u{1F31F}"):format(cost))
		else
			UITheme.SetColor(shardButton, UITheme.Color.Locked)
			UITheme.SetText(shardButton, ("\u{1F31F} %d / %d"):format(held, cost))
		end
	end

	-- A MISSING REMOTE MUST SAY SO. Both spin buttons look their remote up with FindFirstChild
	-- INSIDE the handler -- correct, because RewardService and RobuxShopService create them on
	-- demand and the order is not guaranteed -- but the `if remote then` was silent on the else,
	-- so a button whose service had not finished starting was indistinguishable from a broken one.
	-- That is half of the "claim/spin buttons do not work" report, and it is the half that leaves
	-- no evidence behind.
	--
	-- The message goes ON THE BUTTON rather than through showNotification, and that is a scope fact
	-- rather than a design one: showNotification is declared ~2400 lines below here, so a closure
	-- written at this point captures nil and the click would throw instead of explaining itself.
	local function nagNotReady(target)
		nagUntil = os.clock() + 1.5
		UITheme.SetColor(target, UITheme.Color.Locked)
		UITheme.SetText(target, "\u{23F3} not ready")
	end

	button.MouseButton1Click:Connect(function()
		local remote = Remotes:FindFirstChild("ClaimFreeSpin")
		if remote then
			remote:FireServer()
		else
			nagNotReady(button)
		end
	end)

	-- Fired unconditionally rather than gated on the local affordability check: the client's copy of
	-- the save is up to a push behind, and a button that silently does nothing is worse than the
	-- server's own "you need 25" toast. The server is the one that decides either way.
	shardButton.MouseButton1Click:Connect(function()
		local remote = Remotes:FindFirstChild("SpinWithShards")
		if remote then
			remote:FireServer()
		else
			nagNotReady(shardButton)
		end
	end)

	-- Ticked only while the panel is actually open. A countdown nobody is looking at is a string
	-- rebuild and two property writes a second, forever, on every client in the server.
	task.spawn(function()
		while true do
			task.wait(1)
			if rewardPanel.Visible then
				refresh()
			end
		end
	end)

	-- one handle for both buttons: they are two states of the same question ("can I spin, and how")
	hudRefs.refreshSpins = refresh
end)()

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
;(function()
	-- `topY` is where the strip's own top edge goes. Absent means the old behaviour -- ABOVE the card,
	-- at -34 -- which is still right for the Pets panel: its title is up there too (y = -30), so the
	-- pair reads as one label group sitting on the corner of the board. The Potions panel converted to
	-- a PanelHeader band, so its strip belongs INSIDE, under the band.
	local function buildTabs(panel, activeIndex, topY)
		local row = Instance.new("Frame")
		row.Name = "InventoryTabs"
		row.Size = UDim2.new(0, 262, 0, 38)
		-- above the card, not inside it: both panels fill their own interior with content that was
		-- laid out before this existed, and squeezing a row in at the top would have meant moving
		-- every scroll frame in both of them
		-- -18 stays -18 while the strip is outside: the Pets panel is untouched by this and its
		-- margin is not the converted panels' 16.
		row.Position = UDim2.new(1, topY and -16 or -18, 0, topY or -34)
		row.AnchorPoint = Vector2.new(1, 0)
		row.BackgroundTransparency = 1
		row.ZIndex = panel.ZIndex + UITheme.Z.Badge
		row.Parent = panel

		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 8)
		layout.Parent = row

		local defs = {
			{ text = "\u{1F43E} Pets", target = petsPanel, color = UITheme.Color.Bubblegum },
			{ text = "\u{1F9EA} Potions", target = inventoryPanel, color = UITheme.Color.Aqua },
		}
		for i, def in ipairs(defs) do
			local tab = Instance.new("TextButton")
			tab.Name = "Tab" .. i
			tab.Size = UDim2.new(0, 124, 0, 34)
			tab.LayoutOrder = i
			tab.AutoButtonColor = false
			tab.Text = def.text
			tab.Font = UITheme.Font.Display
			tab.TextSize = 19
			-- the inactive tab is dimmed rather than hidden, so the pair always reads as a pair
			tab.TextColor3 = i == activeIndex and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(236, 238, 248)
			tab.TextTransparency = i == activeIndex and 0 or 0.25
			tab.ZIndex = row.ZIndex + 1
			tab.Parent = row
			styleCard(tab, i == activeIndex and def.color or UITheme.Color.Locked, UDim.new(0, 14), 4)
			-- ===== BOTH TABS WERE BLANK PILLS, AND THE OUTLINE WAS NOT THE REASON (16.6) =====
			--
			-- A TextButton draws its own text at its OWN ZIndex, and `styleCard` puts the fill in an
			-- `InnerBody` child one rung ABOVE it (`Z.Body`) -- so since 15.28 the shell has been
			-- painted straight over the caption. Photographed: a grey pill and a blue pill with no
			-- words on either.
			--
			-- The first reading of this row was wrong in an instructive way. A contrast sweep said
			-- the text was 1.13:1 against its own fill and the conclusion was "it needs the missing
			-- outline" -- true (these were the only 4 of 942 visible runs with no `UIStroke`) and
			-- not the fault. A colour probe cannot see occlusion; the capture can. Adding the halo
			-- to a glyph nothing draws changed nothing, which is what the second capture showed.
			--
			-- So the caption moves onto its own label at `Z.Content`, the way `styleButton` mirrors
			-- every other button in this file into a proxy. `themeLabel` gives it the chunky halo
			-- for free, and the stroke is then matched to the glyph's own transparency: an outline
			-- left opaque under a dimmed label draws the word in outline only, the trap the `+1`
			-- popup and the notification fade both already carry notes about.
			local cap = Instance.new("TextLabel")
			cap.Name = "Label"
			cap.Size = UDim2.new(1, -10, 1, 0)
			cap.Position = UDim2.new(0.5, 0, 0.5, 0)
			cap.AnchorPoint = Vector2.new(0.5, 0.5)
			cap.BackgroundTransparency = 1
			cap.Text = def.text
			cap.TextColor3 = tab.TextColor3
			cap.TextTransparency = tab.TextTransparency
			cap.ZIndex = tab.ZIndex + UITheme.Z.Content
			cap.Parent = tab
			themeLabel(cap, 19)
			local capStroke = cap:FindFirstChildOfClass("UIStroke")
			if capStroke then capStroke.Transparency = cap.TextTransparency end
			tab.Text = ""
			tab.MouseButton1Click:Connect(function()
				if def.target == panel then return end
				toggleOnly(def.target)
				if def.target == inventoryPanel then
					refreshInventoryPanel()
				end
			end)
		end
	end

	buildTabs(petsPanel, 1, 94)
	-- 94 is the band's own bottom edge: top 14 + height 68 + gap 12, written out rather than read
	-- off PanelHeader's second return value, which would cost a top-level register this file has not
	-- got. The row is 38 tall carrying 34 px tabs, so it ends at 132 and the rule below clears it.
	buildTabs(inventoryPanel, 2, 94)
end)()


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
;(function()
	-- [key] = the label under the name, the one thing on a tile whose text depends on the player
	local amountLabels = {}

	-- ===== TODAY'S PICK =====
	--
	-- Derived from the calendar day, so it is the same product for every player on every server
	-- without a byte of server state, and it genuinely changes at midnight UTC. That honesty is the
	-- reason it is a PICK and not a "limited offer": nothing here is discounted and nothing expires,
	-- so a countdown to a price going up would be a lie told to hurry someone. What the timer counts
	-- down to is exactly what it says -- when the highlight moves to something else.
	-- ===== WHAT THIS GRID IS ALLOWED TO SHOW (11.7) =====
	--
	-- Two products are in `RobuxProducts` and not on this wall: Boss Revive is `delisted` (withdrawn,
	-- but its row has to survive so a retried receipt still resolves -- see the note there), and the
	-- two Catalysts carry `panel = "fusion"` because they answer a question the player only has while
	-- looking at a pet they cannot fuse yet.
	--
	-- ONE PREDICATE, USED TWICE -- the grid and the refresh loop -- because a product hidden from
	-- the cards but still walked by the refresh would write into a label that was never built.
	-- (It had a third caller until 15.23: the daily "pick", which is gone.)
	local function inGrid(product)
		return not product.delisted and product.panel == nil
	end

	local gridProducts = {}
	for _, product in ipairs(GameConfig.RobuxProducts) do
		if inGrid(product) then table.insert(gridProducts, product) end
	end

	for i, product in ipairs(gridProducts) do
		local card = Instance.new("Frame")
		card.Name = product.key
		card.LayoutOrder = i
		card.Parent = robuxGrid
		-- shell colour follows what the tile actually pays out, so the groups read apart at a glance
		local accent = UITheme.Color.Blue
		if product.grantPotions then
			accent = UITheme.Color.Green
		elseif product.grantDiamonds then
			accent = UITheme.Color.SkyBlue
		elseif product.grantShards then
			-- Sunny, not the SkyBlue the Diamond tiles use: shards and diamonds are both "premium
			-- currency" to a developer and are completely different things to a player -- one buys
			-- twenty-three permanent upgrades, the other buys spins -- so they must not read as one
			-- group with two amounts.
			accent = UITheme.Color.Sunny
		elseif product.grantBossRevives then
			accent = UITheme.Color.Red
		elseif product.grantTierUps then
			accent = UITheme.Color.Pink
		elseif product.grantSpin then
			accent = UITheme.Color.Purple
		elseif product.grantSeasonPremium then
			accent = UITheme.Color.Gold
		end
		styleCard(card, accent, UDim.new(0, 16), 4)

		-- THE ICON IS THE TILE. At 24 px the emoji was punctuation in front of a name; the fastest
		-- thing to recognise in a shop is what kind of thing you are looking at, and that is the icon.
		--
		-- Through UITheme.IconSlot since 9.9, so a product whose emoji has drawn art gets the
		-- drawing and one whose emoji does not keeps the glyph. The 60 px box is unchanged and the
		-- note below is still why it is 60: TextScaled fits the font to the LINE BOX and an emoji's
		-- line box is mostly padding, so a 40 px box drew an icon barely larger than the name under
		-- it. An ImageLabel has no such padding and fills what it is given, which is a small free
		-- improvement on exactly the tiles this was measured against.
		local icon = UITheme.IconSlot(card, {
			name = "Icon", icon = product.emoji, maxTextSize = 40,
			size = UDim2.new(1, -16, 0, 60), position = UDim2.new(0, 8, 0, 8),
		})

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "NameLabel"
		-- TWO LINES OF ROOM, and it is not cosmetic. themeLabel floors text at 14 px
		-- (UITextSizeConstraint.MinTextSize), so TextScaled cannot rescue a wrapped name from a box
		-- shorter than two lines -- it clips instead. "Small DNA Pack" wraps, and at 24 px tall the
		-- second line was cut in half on every DNA tile.
		nameLabel.Size = UDim2.new(1, -12, 0, 32)
		nameLabel.Position = UDim2.new(0, 6, 0, 68)
		nameLabel.BackgroundTransparency = 1
		nameLabel.TextWrapped = true
		nameLabel.Text = product.name
		nameLabel.Parent = card
		themeLabel(nameLabel, 17)

		-- The second line: what you actually receive. Blank for the products whose name already says
		-- it (a diamond count is a diamond count), filled in per player for the DNA packs, whose
		-- payout is scaled to the buyer's stage and is therefore unknowable at build time.
		local amount = Instance.new("TextLabel")
		amount.Name = "AmountLabel"
		amount.Size = UDim2.new(1, -12, 0, 18)
		amount.Position = UDim2.new(0, 6, 0, 100)
		amount.BackgroundTransparency = 1
		amount.Text = ""
		amount.Parent = card
		themeLabel(amount, 16, UITheme.Color.Cream)
		amountLabels[product.key] = amount

		-- THE PRICE IS ON THE BUTTON. Every tile used to read "Buy with R$", which made a 49 and a 999
		-- look like the same decision and forced the player through a Roblox modal to find out which
		-- was which.
		local buyButton = Instance.new("TextButton")
		buyButton.Name = "BuyButton"
		buyButton.Size = UDim2.new(1, -20, 0, 40)
		buyButton.Position = UDim2.new(0.5, 0, 1, -8)
		buyButton.AnchorPoint = Vector2.new(0.5, 1)
		buyButton.Text = product.price and ("R$ " .. product.price) or "Buy with R$"
		buyButton.Parent = card
		styleButton(buyButton, UITheme.Color.Green, UDim.new(1, 0))

		buyButton.MouseButton1Click:Connect(function()
			Remotes.PromptRobuxPurchase:FireServer(product.key)
		end)

		-- THE RIBBON, AND WHY NO TILE CLAIMS TO BE POPULAR.
		--
		-- "MOST POPULAR" is the standard ribbon in this genre and it is a claim about other players
		-- that nothing in this game measures. What is measurable is value: GetTierBonusPct divides
		-- this tier's payout per Robux by the cheapest tier's, so "+48% BONUS" is arithmetic done on
		-- the table three hundred lines up rather than a sentence somebody typed.
		local ribbonText = product.ribbon
		if not ribbonText then
			local bonus = GameConfig.GetTierBonusPct(product)
			if bonus > 0 then ribbonText = ("+%d%% BONUS"):format(bonus) end
		end
		if ribbonText then
			local ribbon = Instance.new("TextLabel")
			ribbon.Name = "Ribbon"
			ribbon.Size = UDim2.new(1, -20, 0, 20)
			ribbon.Position = UDim2.new(0.5, 0, 0, -6)
			ribbon.AnchorPoint = Vector2.new(0.5, 0)
			ribbon.BackgroundColor3 = product.ribbon and UITheme.Color.Gold or UITheme.Color.Purple
			ribbon.BorderSizePixel = 0
			ribbon.Text = ribbonText
			ribbon.ZIndex = card.ZIndex + UITheme.Z.Badge
			ribbon.Parent = card
			corner(ribbon, UDim.new(0, 8))
			themeLabel(ribbon, 14)
			ribbon.ZIndex = card.ZIndex + UITheme.Z.Badge
		end

	end

	-- Re-run on every data push, which is also what makes the countdown in the title tick without a
	-- loop of its own -- the server pushes about every three seconds.
	hudRefs.refreshRobuxShop = function()
		for _, product in ipairs(gridProducts) do
			local label = amountLabels[product.key]
			if label then
				if product.grantDNA and currentData then
					-- WHAT THIS PACK IS WORTH TO YOU, not what it was authored as. The table stores
					-- "1,000" meaning a thousand stage-one clicks; at stage 14 the same pack pays out
					-- billions, and a tile that said "1,000 DNA" there would read as an insult.
					label.Text = "+" .. formatNumber(GameConfig.ScaleReward(product.grantDNA, currentData)) .. " DNA"
				elseif product.grantPotions then
					label.Text = ("%d potions"):format(product.grantPotions)
				elseif product.grantTierUps then
					label.Text = ("%d catalyst%s"):format(product.grantTierUps, product.grantTierUps > 1 and "s" or "")
				elseif product.grantSpin then
					label.Text = "1 spin of the wheel"
				elseif product.grantBossRevives then
					label.Text = "keep your boss damage"
				end
			end
		end
		-- 15.23 DELETED THE COUNTDOWN THAT USED TO BE WRITTEN HERE, and the reason is that it counted
		-- down to nothing. "⭐ Today's pick resets in 10h 51m" sat under the title of a shop whose
		-- every tile is on sale permanently, at a fixed Robux price, with the same grant tomorrow as
		-- today -- so the clock promised an expiry that does not exist. A countdown is a claim that
		-- something is about to be lost; putting one over a Robux shop that loses nothing is a lie
		-- the player can check in twelve hours. The daily "pick" it timed was a star drawn on one
		-- rotating tile that carried no discount and no bonus, so it went with it.
		--
		-- What stays is the part that is genuinely per-player and genuinely changes: the DNA amounts
		-- above, which are scaled to the reader's own stage and would otherwise print stage-one
		-- numbers. The ribbons stay too -- +24% BONUS / BEST VALUE are derived from real value per
		-- Robux, i.e. a fact about the tile rather than a clock.
	end
	hudRefs.refreshRobuxShop()
end)()

-- ===== THE PASS SHOP: A SECOND TAB, NOT A SECOND PANEL =====
--
-- Two reasons it is a tab. From the player's side a pass and a product are the same decision --
-- "spend Robux" -- and splitting them across two entry points halves the chance either is seen.
-- And this file is at Luau's 200-LOCAL REGISTER CAP: a new panel needs several more top-level
-- locals and there are none to give. Everything below is inside an immediately-called function and
-- escapes only as a function on `hudRefs`, which costs one register no matter how much it holds.
-- A plain `do ... end` block is NOT enough -- that has deleted this whole HUD twice.
;(function()
	-- Created on demand by PassService.Init, so it may not have replicated yet when this runs.
	local promptPass = Remotes:WaitForChild("PromptGamePassPurchase", 10)

	local TAB_H = 40
	-- header 14 + 68 + gap 12 = 94 for the tab row, then the tabs and a 12 gap under them.
	local TOP = 94 + TAB_H + 12

	-- the product grid moves down to make room for the tab row above it
	robuxGrid.Position = UDim2.new(0, 16, 0, TOP)
	robuxGrid.Size = UDim2.new(1, -32, 1, -(TOP + 16))

	local tabRow = Instance.new("Frame")
	tabRow.Name = "TabRow"
	tabRow.Size = UDim2.new(1, -32, 0, TAB_H)
	tabRow.Position = UDim2.new(0, 16, 0, 94)
	tabRow.BackgroundTransparency = 1
	tabRow.ZIndex = robuxPanel.ZIndex + UITheme.Z.Content
	tabRow.Parent = robuxPanel

	-- ===== THE SAME 2 PX GAP 11.3 HAD TO FIX, IN A SECOND PLACE =====
	--
	-- These two tabs were hand-positioned at `0.5, -6` each, i.e. a 12 px frame gap -- and each
	-- carries a 5 px `UIStroke`, which draws OUTSIDE its frame. A gap of N between two stroked
	-- siblings shows as N - 2 x thickness, so 12 read as **2**, and the pair looked like one merged
	-- bar with a seam. Same arithmetic, same wrong answer, same fix as the Hatch row: a UIListLayout
	-- with 24 of padding, which lands as 14 px of daylight and takes the width arithmetic away from
	-- whoever edits this next.
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	tabLayout.Padding = UDim.new(0, 24)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabRow

	local function makeTab(text, order)
		local b = Instance.new("TextButton")
		b.Name = text .. "Tab"
		-- half the row minus half the padding each, so the two fill it exactly
		b.Size = UDim2.new(0.5, -12, 1, 0)
		b.LayoutOrder = order
		b.Text = text
		b.Parent = tabRow
		styleButton(b, UITheme.Color.Blue, UDim.new(0, 14))
		return b
	end

	local productsTab = makeTab("Packs", 1)
	local passesTab = makeTab("Passes", 2)

	-- A SCROLL, not a grid. Nine passes at the product tile's size is 710 px inside a 500 px panel,
	-- and the two things a buyer compares -- what it does and what it costs -- read better on a wide
	-- row than stacked in a square.
	local passScroll = Instance.new("ScrollingFrame")
	passScroll.Name = "PassScroll"
	passScroll.Size = UDim2.new(1, -32, 1, -(TOP + 16))
	passScroll.Position = UDim2.new(0, 16, 0, TOP)
	passScroll.BackgroundTransparency = 1
	passScroll.BorderSizePixel = 0
	passScroll.ScrollBarThickness = 6
	passScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	passScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	passScroll.Visible = false
	passScroll.ZIndex = robuxPanel.ZIndex + UITheme.Z.Content
	passScroll.Parent = robuxPanel

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 8)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = passScroll

	local rows = {}

	for i, pass in ipairs(GameConfig.GamePasses) do
		local row = Instance.new("Frame")
		row.Name = pass.key
		row.LayoutOrder = i
		row.Size = UDim2.new(1, -12, 0, 92)
		row.Parent = passScroll
		-- colour follows what the pass DOES, the same rule the packs above use
		local accent = UITheme.Color.Blue
		if pass.vip then
			accent = UITheme.Color.Gold
		elseif pass.luckAdd or pass.petSlots then
			accent = UITheme.Color.Green
		end
		styleCard(row, accent, UDim.new(0, 16), 4)

		local icon = UITheme.IconSlot(row, {
			name = "Icon", icon = pass.emoji, maxTextSize = 40,
			size = UDim2.new(0, 56, 0, 56), position = UDim2.new(0, 10, 0, 8),
		})

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "NameLabel"
		nameLabel.Size = UDim2.new(1, -200, 0, 30)
		nameLabel.Position = UDim2.new(0, 70, 0, 10)
		nameLabel.BackgroundTransparency = 1
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Text = pass.name
		nameLabel.Parent = row
		themeLabel(nameLabel, 24)

		local descLabel = Instance.new("TextLabel")
		descLabel.Name = "DescLabel"
		descLabel.Size = UDim2.new(1, -200, 0, 44)
		descLabel.Position = UDim2.new(0, 70, 0, 40)
		descLabel.BackgroundTransparency = 1
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.TextYAlignment = Enum.TextYAlignment.Top
		descLabel.TextWrapped = true
		descLabel.Text = pass.desc
		descLabel.Parent = row
		themeLabel(descLabel, 17, UITheme.Color.Cream)

		local buyButton = Instance.new("TextButton")
		buyButton.Name = "BuyButton"
		buyButton.Size = UDim2.new(0, 116, 0, 46)
		buyButton.Position = UDim2.new(1, -14, 0.5, 0)
		buyButton.AnchorPoint = Vector2.new(1, 0.5)
		buyButton.Text = "R$ " .. pass.price
		buyButton.Parent = row
		styleButton(buyButton, UITheme.Color.Green, UDim.new(1, 0))

		buyButton.MouseButton1Click:Connect(function()
			-- the server refuses on passId 0 and on already-owned, and says so; nothing is decided here
			if promptPass then
				promptPass:FireServer(pass.key)
			end
		end)

		rows[pass.key] = buyButton
	end

	local function selectTab(showPasses)
		passScroll.Visible = showPasses
		robuxGrid.Visible = not showPasses
		UITheme.SetColor(passesTab, showPasses and UITheme.Color.Green or UITheme.Color.Blue)
		UITheme.SetColor(productsTab, showPasses and UITheme.Color.Blue or UITheme.Color.Green)
	end

	productsTab.MouseButton1Click:Connect(function() selectTab(false) end)
	passesTab.MouseButton1Click:Connect(function() selectTab(true) end)
	selectTab(false)
	-- escapes so the HUD's currency `+` buttons can open the panel on the right tab; a player who
	-- taps `+` on Diamonds and lands on the pass list has been answered with a different question
	hudRefs.selectRobuxTab = selectTab

	-- OWNED IS A STATE, NOT A MESSAGE. A pass the player already holds must stop looking like
	-- something to buy -- leaving a live price on it is how a second purchase gets attempted and how
	-- the shop stops being trustworthy.
	hudRefs.refreshPassShop = function()
		local owned = (currentData and currentData.Passes) or {}
		for _, pass in ipairs(GameConfig.GamePasses) do
			local button = rows[pass.key]
			if button then
				if owned[pass.key] then
					button.Text = "OWNED"
					button.AutoButtonColor = false
					UITheme.SetColor(button, UITheme.Color.Locked)
				else
					button.Text = "R$ " .. pass.price
					button.AutoButtonColor = true
					UITheme.SetColor(button, UITheme.Color.Green)
				end
			end
		end
	end
end)()

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
;(function()
	local function addPlus(pill, tone)
		-- the pill is a horizontal UIListLayout of Icon (40 wide) + Value; the value gives up the room
		local value = pill:FindFirstChild("Value")
		if not value then return end
		value.Size = UDim2.new(1, -84, 1, 0)

		local plus = Instance.new("TextButton")
		plus.Name = "PlusButton"
		plus.Size = UDim2.new(0, 32, 0, 32)
		plus.LayoutOrder = 3
		plus.Text = "+"
		plus.Parent = pill
		styleButton(plus, tone, UDim.new(1, 0))
		plus.MouseButton1Click:Connect(function()
			toggleOnly(robuxPanel)
			-- always the Packs tab: `+` on a currency is a request for that currency, never for a pass
			if hudRefs.selectRobuxTab then hudRefs.selectRobuxTab(false) end
		end)
	end

	addPlus(dnaPill, UITheme.Color.Green)
	addPlus(diamondPill, UITheme.Color.SkyBlue)
	-- deliberately NOT on the Shard pill: Evolution Shards are not sold for Robux anywhere, so a `+`
	-- there would open a shop that has nothing to answer it with. They are earned off the raised
	-- creatures on the terraces (9.4), and the place to spend them is the Daily panel's wheel.
end)()

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
local characterRows = {}   -- [stageIndex] = { row, headerLabel }

-- How many cells stand side by side. The rest wrap onto another line of the same stage's row --
-- five across is what fits this panel legibly, and a stage now carries ten.
local CHAR_PER_LINE = 5
-- ROUND cells, and the diameter is the whole cell. A rounded rectangle carrying an icon and a name
-- is a list row; a disc carrying an icon is a COLLECTION SLOT, and the difference is most of why
-- the reference reads as a scrapbook and this read as a settings screen. The name moved into the
-- hover card -- it was never legible at 15px inside a 68px box anyway.
-- Grown from 84 once the discs started carrying a rig instead of a glyph: a character in an 84px
-- circle inset for its own rim is drawn about 60px tall, which is a smudge.
local CHAR_CELL_H = 96
local CHAR_LINE_H = 132

-- Built inside an immediately-called function, NOT at the top level: MainUI is at Luau's 200-local
-- ceiling and one more top-level local silently deletes the whole HUD. The hover card has to be an
-- upvalue every cell handler can see, and this is the only way to have one without spending a
-- register. `characterCells` and `characterRows` are declared above and filled from in here.
;(function()
	-- Required IN HERE, not at the top of the file: MainUI is at Luau's 200-local ceiling and a
	-- top-level require would cost one of the last registers. This function has its own 200.
	local CharacterPreview = require(RS.Modules.CharacterPreview)

	-- THE HOVER CARD IS GONE. It said a name and a damage figure, which the detail card on the
	-- right now states permanently and at a readable size -- and it was actively broken: it was
	-- shown on MouseEnter and hidden ONLY on MouseLeave, so closing the panel, scrolling the cell
	-- out from under the cursor, or a refresh hiding that cell all left it welded open at its build
	-- position (top-left, over the "Discovered 15 / 200" header) with stale text in it. Its stat
	-- line was also Cream on PanelWhite -- the exact white-on-white trap this file warns about
	-- twenty lines above.

	-- The twenty stage rows, PLUS TWO MORE at the end: the VIP skin and the event skins.
	--
	-- Both are built by exactly the same code as every other disc, which is the point: they lock,
	-- unlock, preview, select and wear with no special case anywhere, and a later change to how
	-- a cell looks reaches them for free. What they are NOT is part of a stage -- neither enters
	-- CHARACTERS_BY_STAGE, so the collection count, the evolve chain and the rank ladder cannot see
	-- them. See GameConfig.VipCharacter for why that separation is load-bearing.
	--
	-- ===== THE EVENT ROW (12.7) =====
	--
	-- It is the last row rather than the first, and it is DELIBERATELY not sorted by rarity. The
	-- optional "rare first" toggle this row carried does not survive contact with the panel: a
	-- stage's five entries are already in rarity order (Common, Uncommon, Rare, Epic, Legendary --
	-- that IS the authored list), and that order is simultaneously the UNLOCK QUEUE, which is what
	-- the header subtitle, the "next up" callout and the whole left-to-right reading of a row are
	-- built on. Reversing it would put the disc you are actually working towards at the far right of
	-- its row. There is also nothing for a LayoutOrder to sort: the cells are positioned by index
	-- inside their row, not laid out, so only the twenty ROWS have a LayoutOrder at all.
	--
	-- Guarded on the table being non-empty so removing the last event skin removes the row rather
	-- than leaving an empty header on the end of the list.
	local sections = {}
	for stageIndex, stage in ipairs(GameConfig.Stages) do
		table.insert(sections, {
			index = stageIndex,
			stage = stage,
			entries = GameConfig.GetCharactersForStage(stageIndex),
		})
	end
	-- THE WHOLE VIP WARDROBE, NOT ONE SKIN (16.2). Nine of them, so this row wraps onto a second
	-- line by the same `lineCount` arithmetic every stage row already uses -- no special case here
	-- either. See the wardrobe block over GameConfig.VipCharacters.
	table.insert(sections, {
		index = #GameConfig.Stages + 1,
		stage = { emoji = GameConfig.VipCharacter.emoji, name = "VIP Exclusive" },
		entries = GameConfig.VipCharacters,
	})
	if #GameConfig.EventCharacters > 0 then
		table.insert(sections, {
			index = #GameConfig.Stages + 2,
			stage = { emoji = "\u{1F386}", name = "Event Exclusive" },
			entries = GameConfig.EventCharacters,
		})
	end

	for _, section in ipairs(sections) do
		local stageIndex, stage, entries = section.index, section.stage, section.entries
		local lineCount = math.max(1, math.ceil(#entries / CHAR_PER_LINE))

		-- The number under each disc is WHAT IT DOES. It used to be the chance of rolling it, and
		-- that stopped being a fact the moment unlocks went sequential: there is no roll any more,
		-- so there is no chance to print. Position in the stage's list is the power ladder now --
		-- see GameConfig.GetCharacterDamagePct -- and the damage it grants is the one number that
		-- tells a player whether walking to the next disc is worth anything.

		local row = Instance.new("Frame")
		row.Name = "Stage" .. stageIndex
		row.LayoutOrder = stageIndex
		row.Size = UDim2.new(1, 0, 0, 26 + lineCount * CHAR_LINE_H + 4)
		row.BackgroundTransparency = 1
		row.Parent = characterScroll

		local header = Instance.new("TextLabel")
		header.Name = "Header"
		header.Size = UDim2.new(1, -8, 0, 22)
		header.Position = UDim2.new(0, 6, 0, 0)
		header.BackgroundTransparency = 1
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.Text = stage.emoji .. " " .. stage.name
		header.Parent = row
		themeLabel(header, 20, Color3.fromRGB(46, 54, 74))

		for i, entry in ipairs(entries) do
			-- THE DISC IS THE CHARACTER'S OWN COLOUR, NOT ITS RARITY'S. Rarity is no longer a thing
			-- the player experiences -- unlocks run left to right and the only difference between
			-- two discs is damage -- so colouring five of them gold and five grey was showing a
			-- ladder that no longer exists. Its own colour is the useful fact: the disc is now a
			-- swatch of what you actually turn into when you press it.
			local tint = entry.color or GameConfig.GetRarity(entry.rarity).color
			-- THE DAMAGE THIS RUNG PUTS ON THE BODY, and it is now literally the number the creature
			-- takes: GameConfig.GetRankDamage is the base of DNAService.GetCombatDamage, and nothing
			-- clamps it any more. The Journal promising one figure while combat drew another is the
			-- bug this replaces -- see the DAMAGE LADDER block in GameConfig.
			local damagePct = math.floor(GameConfig.GetRankDamage(GameConfig.GetCharacterRank(entry)))

			local col = (i - 1) % CHAR_PER_LINE
			local line = math.floor((i - 1) / CHAR_PER_LINE)

			local cell = Instance.new("TextButton")
			cell.Name = entry.key
			cell.AutoButtonColor = false
			cell.Text = ""
			-- square, and centred in its fifth of the row: a disc needs equal width and height, so
			-- the size is in offset and only the POSITION is in scale
			cell.Size = UDim2.new(0, CHAR_CELL_H, 0, CHAR_CELL_H)
			cell.Position = UDim2.new((col + 0.5) / CHAR_PER_LINE, -CHAR_CELL_H / 2, 0, 26 + line * CHAR_LINE_H)
			cell.Parent = row
			local cellStroke = styleCard(cell, tint, UDim.new(0.5, 0), 3)

			-- ===== THE DISC IS A RING NOW, NOT A FILLED PUCK =====
			--
			-- "Remove the circles around the characters, you cannot see them" (2026-08-11). The
			-- figure was never hidden -- it is a ViewportFrame lifted above the gloss by
			-- liftChildren -- it was being drawn on top of an OPAQUE disc in the character's own
			-- colour, and a green creature on a green puck is a silhouette-shaped hole. The tint is
			-- also the single worst case for it: the disc is deliberately painted the colour of the
			-- thing standing on it.
			--
			-- So the colour moves from the fill to the RIM, where it still identifies the character
			-- and still reads at a glance, and the figure gets the panel behind it instead of its
			-- own colour. The gradient goes with the fill -- a gradient over nothing is a wash of
			-- grey over the model's legs.
			--
			-- The stroke stays `tint` rather than the shared outline colour precisely because the
			-- fill no longer carries it; drop this and every disc in the Journal becomes identical.
			--
			-- RESTORED 2026-08-15 (15.27) after a Gemini pass reinstated the filled squircle. That
			-- pass is the same shape as 15.21: it undid a fix that exists because of a report she
			-- made herself, and wrote a comment describing the new look rather than the reason.
			--
			-- ...AND THE FILLED DISC CAME BACK A THIRD TIME, ON ITS OWN (2026-08-16). Not by anyone
			-- reinstating it: 15.28 rewrote `styleCard` to keep the colour in an `InnerBody` child
			-- instead of on the host, so `cell.BackgroundTransparency = 1` below now clears a surface
			-- that is no longer the one being seen, and the same three lines that used to strip a disc
			-- to a ring strip nothing. Photographed with the fill cleared on two rows and left on the
			-- third: hue-on-hue is real -- a green creature on a green puck flattens, and the damage
			-- number under the disc goes from legible to a smudge.
			--
			-- The owner's call between the three ways out (2026-08-16) was NOT the ring: keep the
			-- filled disc, which is the chunky look the rest of the HUD has, and take the collision
			-- out of it by paling the FILL while the rim keeps the character's colour at full
			-- strength. Hue and saturation come from the character and the value is set outright --
			-- the same HSV idiom as the locked disc below, pointed the other way.
			--
			-- `pale` is carried on the refs table because `setButtonColor` repaints this surface on
			-- every DataUpdate (15.28 made that call real; it used to paint nothing), so the pale is
			-- what refreshCharacterPanel has to hand it or the disc goes back to full strength one
			-- income tick later.
			local paleH, paleS = Color3.toHSV(tint)
			local pale = Color3.fromHSV(paleH, math.clamp(paleS * 0.34, 0, 1), 0.97)
			cell.BackgroundColor3 = pale
			local cellInner = cell:FindFirstChild("InnerBody")
			if cellInner then cellInner.BackgroundColor3 = pale end
			-- The gradient is authored off the full-strength colour, so over a pale fill it reads as
			-- a grey wash rather than as moulding. It lives on the host in one lineage of this file
			-- and under InnerBody in the other; both are cleared.
			local cellGrad = cell:FindFirstChild("Gradient")
				or (cellInner and cellInner:FindFirstChild("Gradient"))
			if cellGrad then cellGrad:Destroy() end
			-- and the sheen goes with it: a white highlight on a nearly-white disc is not a
			-- highlight, it is a bright band across the model's head
			local cellGloss = cell:FindFirstChild("Gloss")
				or (cellInner and cellInner:FindFirstChild("Gloss"))
			if cellGloss then cellGloss:Destroy() end
			cellStroke.Color = tint
			cellStroke.Thickness = UITheme.SnapStroke(4)

			-- THE CHARACTER ITSELF, not a glyph standing in for it. Half the roster shares an emoji,
			-- so a hundred discs carrying emoji showed a player perhaps eight distinct pictures for a
			-- hundred things they had collected -- which is the whole complaint about this panel.
			--
			-- Left EMPTY here and filled by syncPreviews below. A rig is 30 parts; building all
			-- hundred up front is three thousand parts created on join for a panel that is shut.
			local art = Instance.new("ViewportFrame")
			art.Name = "Art"
			-- inset off the rim so a shoulder cannot poke out through the side of the circle
			art.Size = UDim2.new(1, -12, 1, -12)
			art.Position = UDim2.new(0, 6, 0, 6)
			art.Visible = false
			art.ZIndex = cell.ZIndex + 1
			art.Parent = cell
			CharacterPreview.Light(art)

			-- the emoji stays as the stand-in until the rig for this cell exists -- which is what a
			-- cell shows while it is off screen, and what it falls back to if the build ever fails
			local icon = Instance.new("TextLabel")
			icon.Name = "Icon"
			icon.Size = UDim2.new(1, -12, 1, -12)
			icon.Position = UDim2.new(0, 6, 0, 6)
			icon.BackgroundTransparency = 1
			icon.Text = entry.emoji
			icon.Parent = cell
			themeLabel(icon, 40)

			-- what it grants, just under the disc and slightly overlapping it
			local damageLabel = Instance.new("TextLabel")
			damageLabel.Name = "Damage"
			damageLabel.Size = UDim2.new(1, 24, 0, 24)
			damageLabel.Position = UDim2.new(0, -12, 1, -6)
			damageLabel.BackgroundTransparency = 1
			-- An OFF-LADDER skin has no rung -- it scores as whatever the wearer's best earned skin
			-- scores (GameConfig.GetEffectiveRank), so any fixed percentage printed here would be
			-- a lie in one direction or the other depending on how far the collection has got. It says
			-- what it actually is instead.
			--
			-- `offLadder`, not `vip` (12.7): the event skins are the second kind of skin that is not
			-- on the ladder, and they score by the identical rule. Testing `vip` printed the ladder
			-- figure for a rank of 0 under the Prism Herald, i.e. the weakest number in the game.
			--
			-- A VIP SKIN IS THE ONE OFF-LADDER SKIN THAT CARRIES A FIGURE OF ITS OWN (16.2). It still
			-- has no rung -- it MULTIPLIES whatever rung the wearer scores -- so what belongs under the
			-- disc is the multiplier. A damage number here would be right for exactly one save.
			-- Trailing zeros are trimmed, so 5.00 reads x5 while 2.75 keeps both digits.
			damageLabel.Text = entry.vipDamageMult
					and ("\u{2694}\u{FE0F} x" .. (("%.2f"):format(entry.vipDamageMult):gsub("%.?0+$", "")))
				or (entry.offLadder and "\u{2694}\u{FE0F} = best"
					or ("\u{2694}\u{FE0F} %s"):format(formatNumber(damagePct)))
			damageLabel.ZIndex = cell.ZIndex + UITheme.Z.Badge
			damageLabel.Parent = cell
			themeLabel(damageLabel, 17, Color3.fromRGB(58, 66, 88))

			-- The locked state: a "?" over a DARKENED VERSION OF ITS OWN RARITY COLOUR, not a flat
			-- grey. The shape of the collection -- how many slots, which rarities -- is the
			-- information, and a row of identical grey discs throws it away. A padlock said only
			-- "locked"; a dim gold disc says "there is a Legendary here you have not found".
			local lock = Instance.new("TextLabel")
			lock.Name = "Lock"
			lock.Size = UDim2.new(1, 0, 1, 0)
			-- ...and it is mixed the way this project learned to mix a dark variant (11.14). The old
			-- line was `tint:Lerp(Color3.fromRGB(18, 16, 26), 0.72)`, which is "blend toward black,
			-- then take the result" -- and a lerp toward one fixed point does not just darken, it
			-- pulls every hue toward THAT point's hue as well. At 0.72 only 28% of the character's
			-- own colour survives and all hundred discs converge on the same brown-grey, which is
			-- precisely the outcome the comment above says it exists to avoid.
			--
			-- Hue and saturation come from the character, the VALUE is set outright. That is the
			-- world-look pass's rule ("blend then darken cancels; take hue/saturation from the blend
			-- and set the value") applied to a disc instead of a rock. Saturation is pushed UP, not
			-- down: a colour loses apparent chroma as it gets darker, so holding S constant would
			-- still read as a row of near-blacks.
			local lockH, lockS = Color3.toHSV(tint)
			lock.BackgroundColor3 = Color3.fromHSV(lockH, math.clamp(lockS * 1.15 + 0.22, 0, 1), 0.27)
			lock.BackgroundTransparency = 0
			lock.Text = "?"
			lock.ZIndex = cell.ZIndex + UITheme.Z.Badge + 1
			lock.Parent = cell
			corner(lock, UDim.new(0.5, 0))
			themeLabel(lock, 38)

			-- worn marker, on top of everything
			local check = Instance.new("TextLabel")
			check.Name = "Check"
			check.Size = UDim2.new(0, 30, 0, 30)
			check.Position = UDim2.new(1, -26, 0, -4)
			check.BackgroundColor3 = UITheme.Color.Green
			check.Text = "\u{2713}"
			check.Visible = false
			check.ZIndex = cell.ZIndex + UITheme.Z.Badge + 2
			check.Parent = cell
			corner(check, UDim.new(0.5, 0))
			themeLabel(check, 22)

			-- ===== NO RARITY BADGE HERE (15.28), AND THE REASON RETIRES 12.6 =====
			--
			-- 12.6 put a rarity pip on this disc and a rarity ribbon on the detail card, on the
			-- argument that a collection screen should say "there is a Legendary here you have not
			-- found". That argument was true of a game where characters DROPPED. It has not been
			-- true since 9.5 made every skin its own evolve: the 200 are unlocked in **strict rank
			-- order** (see the collection-order note in GameConfig), so the next one you get is the
			-- next one on the ladder no matter what rarity says, and there is nothing a player can
			-- do differently on learning it. The owner put it in one line -- *"I do not need the
			-- rarity option in the journal, every character has to be collected anyway"*.
			--
			-- `entry.rarity` is NOT dead and must not be deleted: `StageCostume.skinMarks` reads it
			-- to decide how much flourish a character wears, which is the form the fact takes now --
			-- you see a Legendary's ornament ON the Legendary rather than a letter in its corner.
			--
			-- A CLICK SELECTS, IT NO LONGER EQUIPS. It used to put the character straight on the body,
			-- which meant the only way to find out what one looked like was to wear it, and the only
			-- way to compare two was to wear both. The detail card on the right is where a character
			-- is looked at, and the Equip button on it is where the decision is made.
			cell.MouseButton1Click:Connect(function()
				if hudRefs.journalSelect then
					hudRefs.journalSelect(entry.key)
				end
			end)

			characterCells[entry.key] = {
				cell = cell, icon = icon, art = art, lock = lock, check = check, chance = damageLabel,
				strokeInst = cellStroke, entry = entry, rarity = { color = tint, pale = pale },
			}
		end

		characterRows[stageIndex] = { row = row, header = header }
	end

	-- ===== THE DETAIL CARD =====
	-- One character, big, on the right. Everything the hover card used to whisper is stated here at
	-- a size you can read, and the Equip button lives here rather than on the cell -- so looking at
	-- a character and deciding to become it are two different actions again.
	local detail = Instance.new("Frame")
	detail.Name = "Detail"
	-- lines up with characterScroll: same top (the header band's bottom edge), same bottom, and a
	-- right margin of 16 to match the scroll's left. 16 + 598 + 16 + 322 + 16 = 968 exactly.
	detail.Size = UDim2.new(0, 322, 1, -124)
	detail.Position = UDim2.new(1, -16, 0, 110)
	detail.AnchorPoint = Vector2.new(1, 0)
	detail.ZIndex = characterPanel.ZIndex + UITheme.Z.Content
	detail.Parent = characterPanel
	styleCard(detail, Color3.fromRGB(240, 243, 250), UDim.new(0, 18), 3)

	-- A WELL FOR THE FIGURE TO STAND IN. On the panel's own white sheet a pale character had no
	-- edge at all -- the same problem the loading screen's tip card was made to solve.
	--
	-- 244 -> 212 (12.6). The card gained a second stat row and every element under the well had to
	-- move up by the difference; the height came out of the well rather than out of the panel
	-- because the panel is the widest in the game and registerPanel fits it to a phone viewport by
	-- SCALE -- thirty-two more pixels of card is thirty-two fewer everywhere else on a small screen.
	-- The figure is still drawn 298 x 212, which is three times the size of a disc.
	local stageBox = Instance.new("Frame")
	stageBox.Name = "StageBox"
	stageBox.Size = UDim2.new(1, -24, 0, 212)
	stageBox.Position = UDim2.new(0, 12, 0, 12)
	stageBox.ZIndex = detail.ZIndex + 1
	stageBox.Parent = detail
	local stageStroke = styleCard(stageBox, Color3.fromRGB(224, 230, 244), UDim.new(0, 14), 3)

	local bigArt = Instance.new("ViewportFrame")
	bigArt.Name = "Art"
	bigArt.Size = UDim2.new(1, -10, 1, -10)
	bigArt.Position = UDim2.new(0, 5, 0, 5)
	bigArt.ZIndex = stageBox.ZIndex + 1
	bigArt.Parent = stageBox
	CharacterPreview.Light(bigArt)

	-- what stands in the well when nothing is selected, and when what IS selected has never been
	-- found: a locked character is a silhouette on purpose, so the panel keeps something to find
	local bigMark = Instance.new("TextLabel")
	bigMark.Name = "Mark"
	bigMark.Size = UDim2.new(1, 0, 1, 0)
	bigMark.BackgroundTransparency = 1
	bigMark.Text = "?"
	bigMark.ZIndex = stageBox.ZIndex + 2
	bigMark.Parent = stageBox
	themeLabel(bigMark, 96, Color3.fromRGB(186, 194, 214))

	-- (12.6's rarity ribbon stood in the corner of this well. It went with the pip on the disc --
	-- see the note over the cells for why rarity stopped being a fact a Journal reader can act on.)

	local dName = Instance.new("TextLabel")
	dName.Name = "DetailName"
	dName.Size = UDim2.new(1, -24, 0, 36)
	dName.Position = UDim2.new(0, 12, 0, 232)
	dName.BackgroundTransparency = 1
	dName.ZIndex = detail.ZIndex + 1
	dName.Parent = detail
	themeLabel(dName, 30, Color3.fromRGB(46, 54, 74))

	local dSub = Instance.new("TextLabel")
	dSub.Name = "DetailSub"
	dSub.Size = UDim2.new(1, -24, 0, 24)
	dSub.Position = UDim2.new(0, 12, 0, 268)
	dSub.BackgroundTransparency = 1
	dSub.ZIndex = detail.ZIndex + 1
	dSub.Parent = detail
	themeLabel(dSub, 20, Color3.fromRGB(126, 134, 156))

	-- WHAT THE RUNG IS WORTH, in the shape every other stat in this game is drawn in.
	--
	-- Two lines since 12.6, and the second one is not decoration: a skin has paid health as well as
	-- damage since GameConfig.CharacterHealthPerRank went in, and this panel -- the only screen in
	-- the game that says anything at all about what a character is worth -- was still quoting only
	-- half of it. 40 -> 62 to carry the pair; see the well above for where the pixels came from.
	local dStat = Instance.new("Frame")
	dStat.Name = "DetailStat"
	dStat.Size = UDim2.new(1, -24, 0, 62)
	dStat.Position = UDim2.new(0, 12, 0, 294)
	dStat.ZIndex = detail.ZIndex + 1
	dStat.Parent = detail
	styleCard(dStat, Color3.fromRGB(230, 235, 246), UDim.new(0, 12), 3)

	local dStatLabel = Instance.new("TextLabel")
	dStatLabel.Size = UDim2.new(1, -16, 0, 26)
	dStatLabel.Position = UDim2.new(0.5, 0, 0, 5)
	dStatLabel.AnchorPoint = Vector2.new(0.5, 0)
	dStatLabel.BackgroundTransparency = 1
	dStatLabel.ZIndex = dStat.ZIndex + 1
	dStatLabel.Parent = dStat
	themeLabel(dStatLabel, 21, Color3.fromRGB(70, 78, 98))

	-- The health half. Quoted from GameConfig.GetCharacterHealthPct -- the function the applied
	-- multiplier is built out of -- and never re-derived here: a second copy of "1% a rung" in the
	-- UI is a promise that goes stale the day the rate changes, which is exactly the class of bug
	-- the damage figure was rescued from (see the note over the disc's own label).
	local dStatHp = Instance.new("TextLabel")
	dStatHp.Name = "DetailHealth"
	dStatHp.Size = UDim2.new(1, -16, 0, 26)
	dStatHp.Position = UDim2.new(0.5, 0, 0, 31)
	dStatHp.AnchorPoint = Vector2.new(0.5, 0)
	dStatHp.BackgroundTransparency = 1
	dStatHp.ZIndex = dStat.ZIndex + 1
	dStatHp.Parent = dStat
	themeLabel(dStatHp, 21, Color3.fromRGB(70, 78, 98))

	local dHint = Instance.new("TextLabel")
	dHint.Name = "DetailHint"
	-- clear of the button below it: the hint wraps to two lines for every owned character, and at
	-- -78 the second line was entirely behind the green button -- which is the one sentence in this
	-- panel that explains why pressing it might appear to do nothing
	dHint.Size = UDim2.new(1, -24, 0, 44)
	dHint.Position = UDim2.new(0, 12, 1, -112)
	dHint.BackgroundTransparency = 1
	dHint.TextWrapped = true
	dHint.ZIndex = detail.ZIndex + 1
	dHint.Parent = detail
	themeLabel(dHint, 17, Color3.fromRGB(146, 154, 174))

	local equipButton = Instance.new("TextButton")
	equipButton.Name = "EquipButton"
	equipButton.Size = UDim2.new(1, -24, 0, 52)
	equipButton.Position = UDim2.new(0.5, 0, 1, -12)
	equipButton.AnchorPoint = Vector2.new(0.5, 1)
	equipButton.Text = "Wear this one"
	equipButton.Parent = detail
	styleButton(equipButton, UITheme.Color.Green, UDim.new(0, 16))
	-- AFTER styleButton, which writes its own ZIndex over anything set before it -- set first, the
	-- button ended up level with the hint and the stacking fell back to tree order
	equipButton.ZIndex = detail.ZIndex + 4

	local selectedKey = nil
	local bigRig, bigPivot = nil, nil

	-- ===== DARK INK ON A PALE CARD DOES NOT WANT AN OUTLINE (12.6) =====
	--
	-- Every label in this kit is white with a 4px near-black stroke, and that stroke is what carries
	-- white text over a bright cartoon world. The detail card is the other case entirely: it is a
	-- pale sheet (240,243,250) and its labels are DARK -- so glyph and outline are the same ink, and
	-- twenty-one pixels of it inside four more render as a fat dark blob with a slightly lighter
	-- core. Every property reads correct while it happens: TextFits true, .Text right,
	-- .TextColor3 right. It is only visible in a screenshot, which is how it was found -- the same
	-- defect 12.3 found on the Splicer's white reveal card, one panel over.
	--
	-- Fixed the same way, and deliberately by a LUMINANCE TEST rather than a list of label names:
	-- dName wears the CHARACTER'S own colour and a good half of the roster is pale gold or cream,
	-- which needs the dark outline exactly as much as the dark ones need it gone. 0.62 is the line
	-- between the two on this sheet -- the locked grey (150,158,178) sits a hair above it and keeps
	-- its stroke, the mid-grey subtitle sits below and loses it.
	-- THICKNESS, NOT ONLY TRANSPARENCY -- and this line is the whole reason the fix above needed a
	-- capture to check. Phase 15 taught `themeLabel` to call `OutlineText(label, 0)` for dark ink,
	-- and these five labels are AUTHORED dark (46,54,74) and REPAINTED bright at runtime with the
	-- character's own colour. So they arrive here with a stroke whose Thickness is already 0, and a
	-- helper that moves only Transparency has nothing left to switch on: "The Final" rendered at
	-- luminance 0.900 on a 0.953 card with no outline at all -- a difference of 0.052, which is a
	-- ghost rather than a blob but is just as unreadable. Restore both, or a zeroed stroke is
	-- permanent for any label that is dark at build time and bright afterwards.
	local function inkOnLight(label)
		local st = label:FindFirstChildOfClass("UIStroke")
		if not st then return end
		local c = label.TextColor3
		local bright = (0.299 * c.R + 0.587 * c.G + 0.114 * c.B) >= 0.62
		st.Transparency = bright and 0 or 1
		st.Thickness = bright and 4 or 0 -- 4 is themeLabel's own non-dark default
	end

	-- TEXT AND BUTTON ONLY. Called from refreshCharacterPanel, which runs on every DataUpdate --
	-- which is to say on every creature anyone kills -- so it must never rebuild the figure.
	local function paintDetail()
		local refs = selectedKey and characterCells[selectedKey]
		local entry = refs and refs.entry
		if not entry then
			dName.Text = "Nothing picked"
			dName.TextColor3 = Color3.fromRGB(46, 54, 74)
			dSub.Text = "Choose one from the list"
			dStatLabel.Text = ""
			dStatHp.Text = ""
			dHint.Text = ""
			bigMark.Visible = true
			bigMark.Text = "\u{1F4D2}"
			equipButton.Visible = false
			-- the empty card is a real state of this panel (it is what it opens as before anything is
			-- picked), so it gets the same ink treatment as the filled one
			inkOnLight(dName)
			inkOnLight(dSub)
			return
		end

		local owned = currentData and currentData.Characters and currentData.Characters[entry.key] == true
		local stage = GameConfig.Stages[entry.stage]
		local rarityLine = ownershipText(entry.key)
		-- ONE worn character, wherever the player is standing -- see GameConfig.GetWornCharacter
		local equipped = currentData and currentData.WornCharacter == entry.key
		-- The rung the player actually FIGHTS at. It is the best one owned, not the one on the body:
		-- a costume is free now, see GameConfig.GetProgressRank.
		-- ...times the VIP wardrobe, which is the one costume that DOES change it (16.2). Without that
		-- term this card told a player standing in an x8 skin they hit for an eighth of what they do.
		local progressDamage = currentData and math.floor(
			GameConfig.GetBaseDamage(currentData) * GameConfig.GetVipDamageMult(currentData)) or 0

		dName.Text = owned and entry.name or "???"
		dName.TextColor3 = owned and (entry.color or Color3.fromRGB(46, 54, 74)) or Color3.fromRGB(150, 158, 178)
		-- AN OFF-LADDER SKIN BELONGS TO NO STAGE, and this line used to say so by printing
		-- "  \u{2022}  #1 of 0" beside the VIP one: `entry.stage` is nil for it, so
		-- GetCharactersForStage hands back an empty list and GetCharacterIndex falls through to its
		-- 1. Nothing was broken underneath -- the ladder deliberately does not contain these -- it
		-- was the panel reporting a position in a list the entry is not in.
		if entry.offLadder then
			dSub.Text = ("%s  \u{2022}  outside the collection%s")
				:format(entry.vip and "\u{1F451} VIP Exclusive" or "\u{1F386} Event Exclusive", rarityLine)
		else
			dSub.Text = ("%s %s  \u{2022}  #%d of %d%s"):format(stage and stage.emoji or "", stage and stage.name or "",
				GameConfig.GetCharacterIndex(entry), #GameConfig.GetCharactersForStage(entry.stage), rarityLine)
		end

		-- ===== THE TWO NUMBERS A RUNG IS WORTH (12.6) =====
		--
		-- Both read off GetEffectiveRank, which is the only honest rung for an off-ladder skin: the
		-- VIP one scores as the best thing the save has earned, so a fixed figure would be a lie in
		-- one direction or the other depending on how far the collection has got. The disc's own
		-- label already says "= best" for exactly this reason; the card used to quote
		-- GetCharacterRank straight and therefore printed the WEAKEST rung in the game beside the
		-- strongest skin in it (GetRankDamage clamps a 0 up to rank 1).
		local shownRank = GameConfig.GetEffectiveRank(currentData, entry)
		-- A VIP skin's figure is that same rung MULTIPLIED, so the card answers "what would I hit for
		-- in this?" rather than quoting a rung the skin then changes underneath the player.
		dStatLabel.Text = ("\u{2694}\u{FE0F}  %s Damage"):format(
			formatNumber(math.floor(GameConfig.GetRankDamage(shownRank) * (entry.vipDamageMult or 1))))
		dStatHp.Text = ("\u{2764}\u{FE0F}  +%d%% Max Health"):format(
			math.floor(GameConfig.GetCharacterHealthPct(entry, currentData)))

		equipButton.Visible = owned
		if equipped then
			equipButton.Text = "\u{2713} Wearing it"
			setButtonColor(equipButton, UITheme.Color.Locked)
			-- dimmed AND dead. A greyed-out button that still fires a remote and still answers with a
			-- toast is worse than one that does nothing: it says the press failed rather than that
			-- there was nothing to press.
			equipButton.Active = false
			equipButton.AutoButtonColor = false
		else
			equipButton.Text = "Wear this one"
			setButtonColor(equipButton, UITheme.Color.Green)
			equipButton.Active = true
		end

		-- THERE IS NO TRADE LEFT TO WARN ABOUT. This used to compare the rung against the one on the
		-- body and print what wearing it would cost, because damage came from the costume. It comes
		-- from the best rung OWNED now, so picking an old skin changes nothing but the mirror --
		-- and the useful fact is instead what the player is hitting for right now.
		-- THE COLOUR IS RESET BEFORE THE CHAIN, not only inside the branches that change it. Three of
		-- the branches below paint this label green and none of the others painted it back, so the
		-- colour was whatever the LAST card looked at had said -- an unowned skin's "evolve to this
		-- stage" line inherited the green of a previously-inspected owned one and read as good news.
		-- Harmless-looking until 12.13 added a fourth green branch; a default set once, here, cannot
		-- go stale however many branches are added later.
		dHint.TextColor3 = Color3.fromRGB(146, 154, 174)
		if not owned then
			-- HOW TO GET IT, and for an off-ladder skin that is not "evolve" (12.7). Every unowned
			-- entry used to be told to evolve into its stage, and an off-ladder skin has no stage --
			-- so the Prism Herald's own card read "Evolve to this stage to discover it", which is
			-- both untrue and unactionable. Each kind now names its actual route.
			if entry.vip then
				-- BOTH LADDERS, because as of the wardrobe rebuild a VIP skin pays DNA as well as
				-- damage and quoting only the half that was here first would undersell the row by
				-- exactly the amount that was added to it.
				dHint.Text = ("Comes with the VIP pass \u{2014} x%s damage and x%s DNA while it is on, and it goes away again if the pass does.")
					:format((("%.2f"):format(entry.vipDamageMult or 1):gsub("%.?0+$", "")),
						(("%.2f"):format(entry.vipIncomeMult or 1):gsub("%.?0+$", "")))
			elseif entry.event then
				local eventDef = GameConfig.GetEvent(entry.event)
				local label = ("%s%s"):format(eventDef and (eventDef.emoji .. " ") or "",
					eventDef and eventDef.name or "the event")
				-- A ROTATION SKIN IS NOT AVAILABLE WHENEVER ITS EVENT IS (12.13). The generic line
				-- below is true of the festival, which hands out its one skin for the whole window --
				-- and false of a champion, which is one of four and is handed out on one weekend in
				-- four. Telling a collector to "turn up while it is running" on a weekend that is
				-- running somebody else's skin is the panel lying about the only thing this card
				-- exists to answer.
				local rot = GameConfig.GetRotationInfo(entry.key)
				if rot and rot.live then
					dHint.Text = ("Week %d of %d \u{2014} being handed out in %s RIGHT NOW. Turn up and it is yours for good.")
						:format(rot.slot, rot.count, label)
					dHint.TextColor3 = Color3.fromRGB(72, 168, 96)
				elseif rot and rot.nextStart then
					dHint.Text = ("Week %d of %d in the %s rotation \u{2014} its turn comes round in %s.")
						:format(rot.slot, rot.count, label,
							GameConfig.FormatDuration(rot.nextStart - GameConfig.EventNow()))
				else
					dHint.Text = ("Handed out during %s. Turn up while it is running and it is yours for good.")
						:format(label)
				end
			else
				dHint.Text = "Evolve to " .. (stage and stage.name or "this stage") .. " to discover it."
			end
		elseif equipped then
			dHint.Text = ("This is what you look like right now.  You hit for %s."):format(formatNumber(progressDamage))
		elseif entry.vipDamageMult then
			-- THE ONE CARD IN THIS PANEL WHERE "a skin is looks only" IS FALSE (16.2), so it says the
			-- trade instead of denying there is one: what this skin would put on the body, against what
			-- is on it right now.
			dHint.Text = ("Wear it for x%s damage and x%s DNA \u{2014} %s instead of %s."):format(
				(("%.2f"):format(entry.vipDamageMult):gsub("%.?0+$", "")),
				(("%.2f"):format(entry.vipIncomeMult or 1):gsub("%.?0+$", "")),
				formatNumber(currentData and math.floor(GameConfig.GetBaseDamage(currentData) * entry.vipDamageMult) or 0),
				formatNumber(progressDamage))
			dHint.TextColor3 = Color3.fromRGB(72, 168, 96)
		else
			local delta = math.floor(GameConfig.GetRankDamage(GameConfig.GetCharacterRank(entry))) - progressDamage
			if delta > 0 then
				dHint.Text = "Wear it freely \u{2014} a skin is looks only, your damage stays where you climbed to."
				dHint.TextColor3 = Color3.fromRGB(72, 168, 96)
			elseif delta < 0 then
				dHint.Text = ("Costs you nothing \u{2014} you still hit for %s."):format(formatNumber(progressDamage))
				dHint.TextColor3 = Color3.fromRGB(72, 168, 96)
			else
				dHint.Text = ("You hit for %s."):format(formatNumber(progressDamage))
				dHint.TextColor3 = Color3.fromRGB(146, 154, 174)
			end
		end

		-- LAST, because every branch above can still be writing a colour and the test is on the
		-- colour. (`dRarity` used to be excluded from this list by name -- its UIStroke was
		-- styleCard's BORDER rather than an outline around the glyphs. The ribbon is gone; the
		-- exclusion note is kept because the distinction still applies to anything styleCard'd
		-- that acquires a label.)
		inkOnLight(dName)
		inkOnLight(dSub)
		inkOnLight(dStatLabel)
		inkOnLight(dStatHp)
		inkOnLight(dHint)
	end

	-- REBUILDS THE FIGURE. Only from a click, never from a data push.
	local function selectCharacter(key)
		selectedKey = key
		if bigRig then
			bigRig:Destroy()
			bigRig, bigPivot = nil, nil
		end
		local refs = key and characterCells[key]
		local entry = refs and refs.entry
		local owned = entry and currentData and currentData.Characters
			and currentData.Characters[entry.key] == true
		if owned then
			-- no part cap here: this is the one place a player is actually looking at the build, so
			-- it gets every rivet the body in the world has
			-- An off-ladder skin belongs to no stage: it is a recoloured version of whatever the
			-- player currently IS, so it previews at their stage rather than at a fixed one. (Build
			-- returns nil for a nil stage rather than erroring, so this is a correctness fix, not a
			-- crash fix.)
			--
			-- `offLadder` since 12.7, for the same reason as the damage label above: an event skin
			-- has `stage = nil` too, so testing `vip` left the detail well EMPTY for an owned event
			-- skin -- the one entry in the panel a player would most want to look at.
			local previewStage = (entry.offLadder and currentData and currentData.StageIndex) or entry.stage
			bigRig = CharacterPreview.Build(bigArt, previewStage, entry)
			if bigRig then
				CharacterPreview.Frame(bigArt, bigRig, { zoom = 1.06, pitch = 0.12 })
				bigPivot = bigRig:GetPivot()
			end
		end
		bigMark.Visible = bigRig == nil
		bigMark.Text = entry and "?" or "\u{1F4D2}"
		if entry then
			stageStroke.Color = (owned and entry.color) or OUTLINE_COLOR
		end
		-- the rim on the selected cell, so the grid and the card agree about what is being shown
		for otherKey, other in pairs(characterCells) do
			other.selected = otherKey == key
		end
		paintDetail()
		-- refreshCharacterPanel is declared BELOW this function, so naming it here would read a
		-- global, not the upvalue -- it hands itself over on hudRefs once it exists instead
		if hudRefs.refreshCharacterPanel then hudRefs.refreshCharacterPanel() end
	end

	equipButton.MouseButton1Click:Connect(function()
		if selectedKey and equipButton.Active then
			Remotes.EquipCharacter:FireServer(selectedKey)
		end
	end)

	-- ===== THE RIGS, BUILT AS THEY COME INTO VIEW =====
	-- A hundred cells is a hundred rigs if they are all built, and the panel shows about eighteen
	-- at a time. So a cell builds its rig when it scrolls into the window and gives it back when it
	-- leaves, and only a few are built per pass -- a scroll that stops on a fresh row builds them
	-- over the next few frames instead of hitching on one.
	--
	-- ONE PASS IS NOT THE SAME AS ONE FRAME, AND THAT IS THE BUG THIS RETURN VALUE FIXES. A pass
	-- ran on three signals only: opening the panel, a scroll, and a DataUpdate. Opening it is ONE
	-- pass, so the panel used to open with two discs drawn and sixteen still showing the emoji
	-- stand-in, and the rest arrived one income tick at a time -- seconds of a half-built page, on
	-- the panel whose whole job is showing off a collection. Nothing was broken; the fill simply had
	-- no engine of its own. `fillPreviews` below is that engine.
	--
	-- Measured 2026-08-16 on the live client: a rig costs 3.15 ms to build and frame, so a window
	-- of eighteen is ~57 ms if it is done in one go -- three or four dropped frames, which is why
	-- this is still a budget and not a loop. Three per pass is ~9.5 ms, inside a 60 Hz frame, and
	-- fills a fresh window in six frames.
	local function syncPreviews(budget)
		if not (characterPanel.Visible and currentData) then return 0 end
		local owned = currentData.Characters or {}
		local top = characterScroll.AbsolutePosition.Y
		local height = characterScroll.AbsoluteSize.Y
		if height <= 0 then return 0 end
		budget = budget or 3
		local built = 0

		for key, refs in pairs(characterCells) do
			local y = refs.cell.AbsolutePosition.Y - top
			-- a row of slack either side, so a slow scroll never shows an empty disc arriving
			local inView = y > -CHAR_LINE_H and y < height + CHAR_LINE_H
			if owned[key] and inView then
				if not refs.rig and budget > 0 then
					budget -= 1
					-- same rule as the detail card: an off-ladder skin previews at the player's own stage
					local previewStage = (refs.entry.offLadder and currentData.StageIndex) or refs.entry.stage
					refs.rig = CharacterPreview.Build(refs.art, previewStage, refs.entry, { maxParts = 26 })
					if refs.rig then
						CharacterPreview.Frame(refs.art, refs.rig, { zoom = 1.16 })
						refs.art.Visible = true
						refs.icon.Visible = false
						built += 1
					end
				end
			elseif refs.rig then
				refs.rig:Destroy()
				refs.rig = nil
				refs.art.Visible = false
				refs.icon.Visible = owned[key] == true
			end
		end
		return built
	end

	-- Keeps passing until the window has nothing left to build. It stops on its own -- a pass that
	-- builds nothing is the signal that the window is complete, and a cell whose rig fails to build
	-- returns 0 as well, so a missing PreviewRig ends the loop instead of spinning on it.
	--
	-- `filling` is the guard that matters: this is reached from three places (open, scroll,
	-- DataUpdate) and a scroll fires CanvasPosition on every frame of the drag. Without it a
	-- one-second drag would leave sixty of these loops running against each other.
	local filling = false
	local function fillPreviews()
		if filling then return end
		filling = true
		task.spawn(function()
			while characterPanel.Visible do
				if syncPreviews(3) == 0 then break end
				task.wait()
			end
			filling = false
		end)
	end

	-- Scrolling is the only thing that changes what is in view, and CanvasPosition is the only
	-- honest signal for it -- the cells live inside the scrolling frame and their own positions
	-- move with it.
	characterScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(fillPreviews)

	-- ONE turntable, for the big figure only. Turning eighteen cell rigs as well would be six
	-- hundred part CFrames written every frame behind a panel, and a 96px disc reads no better
	-- moving than still.
	RunService.RenderStepped:Connect(function()
		if not (characterPanel.Visible and bigRig and bigPivot) then return end
		bigRig:PivotTo(CFrame.Angles(0, os.clock() * 0.6, 0) * bigPivot)
	end)

	hudRefs.journalSelect = selectCharacter
	hudRefs.journalPaintDetail = paintDetail
	-- The FILL, not one pass: `refreshCharacterPanel` calls this on every DataUpdate, and a
	-- discovery that lands while the panel is open should finish drawing the window rather than
	-- adding three discs to it and waiting for the next income tick.
	hudRefs.journalSync = fillPreviews
	-- Opening the panel lands on the character you are wearing. An empty card next to a full grid
	-- reads as something that failed to load.
	hudRefs.journalOnOpen = function()
		if not selectedKey and currentData then
			local worn = currentData.WornCharacter
			if worn then
				selectCharacter(worn)
			end
		end
		fillPreviews()
	end

	paintDetail()
end)()

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
;(function()
	local SEASON = GameConfig.Season
	local CELL = 92          -- one reward cell, square
	local PITCH = 104        -- ...plus the gap to the next column
	local PAGE_TOP = 148
	-- ===== THE BOARD'S VERTICAL ARITHMETIC, WRITTEN DOWN INSTEAD OF TYPED FOUR TIMES (18.6) =====
	--
	-- The tray height, the scroll height, the column height and the two rotated row tags were five
	-- independent literals that all encoded the same stack, with the derivation living only in a
	-- comment ("the scroll (254) centres in the tray (286) at y=16..."). Changing the rail -- which
	-- this row does -- moved four of the five and there was nothing to recompute them from. They are
	-- one expression now, so the next person to touch the rail changes RAIL_H and nothing else.
	local RAIL_H = 16        -- was 26; see the rail comment below for why it got thinner
	local COL_GAP = 5        -- the column layout's padding, twice over
	local TRAY_H = 286
	local SCROLL_H = 254
	local COL_H = CELL * 2 + RAIL_H + COL_GAP * 2                 -- 92+92+16+10 = 210
	local SCROLL_TOP = (TRAY_H - SCROLL_H) / 2                    -- 16, the scroll's inset in the tray
	local COL_TOP = SCROLL_TOP + (SCROLL_H - COL_H) / 2           -- 16 + 22 = 38, the free cell's top
	local FREE_TAG_Y = COL_TOP + CELL / 2                         -- 84  (was 79 at RAIL_H = 26)
	local PREMIUM_TAG_Y = COL_TOP + CELL + COL_GAP * 2 + RAIL_H + CELL / 2  -- 202 (was 207)

	local panel = Instance.new("Frame")
	panel.Name = "SeasonPanel"
	panel.Size = UDim2.new(0, 880, 0, 522)
	panel.Position = PANEL_ANCHOR
	panel.ZIndex = 20
	panel.Visible = false
	panel.Parent = screenGui
	styleCard(panel, PANEL_SHELL, UDim.new(0, 22), 5)
	registerPanel(panel)
	panelClose(panel)

	-- Converted to the shared accent band (17.x), the last of the nine. The band spans the full
	-- width, so the two tabs could no longer share the title's row -- they drop to their own row
	-- under it (y = 94) and start at the panel margin instead of at x = 360, where they used to sit
	-- beside the title. PAGE_TOP follows them down: 94 + the 42 px tab + 12 = 148.
	--
	-- The TITLE handle is kept because `refresh` rewrites it -- 7.3 made the season id and name
	-- functions of the DATE, so a title written once at build time names last month's season for the
	-- whole of this one, and a session can span the turnover. That is what PanelHeader's third
	-- return value is for.
	local title = select(3, UITheme.PanelHeader(panel, {
		title = GameConfig.GetCurrentSeason().emoji .. " " .. GameConfig.GetCurrentSeason().name,
		subtitle = "Earn season XP to unlock every reward",
		accent = UITheme.Color.Coral,
	}))

	-- ---- the two remotes this panel talks over. Newer than the authored Remotes folder, so they
	-- are waited for by name rather than indexed -- SeasonPassService creates whichever is missing.
	local claimQuestRemote, claimRewardRemote
	task.spawn(function()
		claimQuestRemote = Remotes:WaitForChild("ClaimQuest", 30)
		claimRewardRemote = Remotes:WaitForChild("ClaimSeasonReward", 30)
	end)

	-- ---- pages
	local function newPage(name)
		local page = Instance.new("Frame")
		page.Name = name
		page.Size = UDim2.new(1, -28, 1, -(PAGE_TOP + 14))
		page.Position = UDim2.new(0, 14, 0, PAGE_TOP)
		page.BackgroundTransparency = 1
		page.ZIndex = panel.ZIndex + UITheme.Z.Content
		page.Visible = false
		page.Parent = panel
		return page
	end
	local trackPage = newPage("TrackPage")
	local questPage = newPage("QuestPage")

	-- ---- tabs
	local tabs = {}
	local currentTab = "track"
	local function setTab(name)
		currentTab = name
		trackPage.Visible = (name == "track")
		questPage.Visible = (name == "quests")
		for key, btn in pairs(tabs) do
			-- ===== AN UNSELECTED TAB IS NOT A REFUSED ONE (18.6) =====
			--
			-- `Color.Locked` here said "you cannot press this" about the one control on the panel that
			-- always can be pressed -- and it is half of what made the top of this screen read grey.
			-- Lavender is a live surface (lum 0.635, white ink with its halo, same as every other
			-- chromatic button in the kit) and Sunny at 0.82 is plainly the brighter of the two, so
			-- "which one am I on" is answered by warmth and not by whether the control looks dead.
			setButtonColor(btn, key == name and UITheme.Color.Sunny or UITheme.Color.Lavender)
		end
	end

	-- ===== THE TABS NOW SPAN THE PANEL (18.6) =====
	--
	-- Two 190 px tabs at x=16 and x=216 end at 406 on an 880 px panel: **458 px of bare white** to
	-- their right, which is the widest empty rectangle in the game. Widened to 260 on a 270 pitch
	-- (16..276 and 286..546) and the remaining band is filled by the collected-rewards chip below,
	-- which lands at 566..864 against the panel's own 16 px right margin.
	for i, spec in ipairs({
		{ key = "track",  text = SEASON.emoji .. " Season Pass" },
		{ key = "quests", text = "\u{1F4CB} Quests" },
	}) do
		local btn = Instance.new("TextButton")
		btn.Name = "Tab_" .. spec.key
		btn.Size = UDim2.new(0, 260, 0, 42)
		btn.Position = UDim2.new(0, 16 + (i - 1) * 270, 0, 94)
		btn.Text = spec.text
		btn.ZIndex = panel.ZIndex + UITheme.Z.Content
		btn.Parent = panel
		styleButton(btn, UITheme.Color.Locked, UDim.new(0, 14))
		btn.MouseButton1Click:Connect(function()
			setTab(spec.key)
		end)
		tabs[spec.key] = btn
	end

	-- ===== WHAT GOES IN THE BAND: THE ONE NUMBER THIS PANEL NEVER SHOWED (18.6) =====
	--
	-- Everything else on the screen is a reading of XP -- the level badge, the XP bar, the node the
	-- board is lit up to. None of them says *how much of the pass you actually own*, which is the
	-- question a child opens a season pass to answer, and it is a different number from the level
	-- (premium rows you have passed but not bought are levels earned and rewards not held).
	--
	-- Deliberately NOT a third bar. This row is about there being two readings of one number
	-- already; the fix cannot be a fourth surface animating along a track. It is a count.
	local tally = Instance.new("TextLabel")
	tally.Name = "CollectedChip"
	tally.Size = UDim2.new(0, 298, 0, 42)
	tally.Position = UDim2.new(1, -16, 0, 94)
	tally.AnchorPoint = Vector2.new(1, 0)
	tally.Text = ("\u{1F381} 0 / %d collected"):format(SEASON.maxLevel * 2)
	tally.ZIndex = panel.ZIndex + UITheme.Z.Content
	tally.Parent = panel
	-- Aqua rather than a green: Green is the one "press me" colour on the board below and a bright
	-- green chip in the header would be read as a button. A TextLabel handed to `styleCard` is
	-- mirrored above `InnerBody` now (see styleCard), which is the only reason this can be a shell at
	-- all -- before this session it would have shipped as a blank blue pill.
	styleCard(tally, UITheme.Color.Aqua, UDim.new(0, 14), 4)
	themeLabel(tally, 22)

	-- ================= TRACK PAGE =================

	-- left: the level badge and the XP bar, the two numbers the whole page is about
	local sideCard = Instance.new("Frame")
	sideCard.Size = UDim2.new(0, 210, 1, 0)
	sideCard.Parent = trackPage
	styleCard(sideCard, UITheme.Color.Lavender, UDim.new(0, 18), 4)

	local levelLabel = Instance.new("TextLabel")
	levelLabel.Size = UDim2.new(1, -20, 0, 64)
	levelLabel.Position = UDim2.new(0, 10, 0, 14)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text = "Level 1"
	levelLabel.Parent = sideCard
	themeLabel(levelLabel, 42)

	-- THIS FILE IS AT LUAU'S 200-REGISTER CEILING. ProgressBar returns (background, fill, label) and
	-- the background was being bound to a local that nothing ever reads -- one wasted register out of
	-- two hundred, and it was the one that tipped the count over: adding any local anywhere above
	-- this point made the WHOLE script fail to compile, reported here rather than at the new line.
	-- Dropped via select() so the slot is never allocated. Keep an eye on this when adding UI.
	local xpBarFill, xpBarLabel = select(2, UITheme.ProgressBar(sideCard, {
		name = "SeasonXP",
		size = UDim2.new(1, -24, 0, 30),
		position = UDim2.new(0.5, 0, 0, 84),
		anchorPoint = Vector2.new(0.5, 0),
		color = UITheme.Color.Green,
		text = "0 / " .. SEASON.xpPerLevel,
		maxTextSize = 18,
		zIndex = sideCard.ZIndex + UITheme.Z.Content,
	}))

	local premiumStatus = Instance.new("TextLabel")
	premiumStatus.Size = UDim2.new(1, -20, 0, 92)
	premiumStatus.Position = UDim2.new(0, 10, 0, 128)
	premiumStatus.BackgroundTransparency = 1
	premiumStatus.TextWrapped = true
	premiumStatus.Text = ""
	premiumStatus.Parent = sideCard
	themeLabel(premiumStatus, 17, UITheme.Color.Cream)

	local premiumButton = Instance.new("TextButton")
	premiumButton.Size = UDim2.new(1, -24, 0, 52)
	premiumButton.Position = UDim2.new(0.5, 0, 1, -16)
	premiumButton.AnchorPoint = Vector2.new(0.5, 1)
	premiumButton.Text = "Get Premium"
	premiumButton.Parent = sideCard
	styleButton(premiumButton, UITheme.Color.Gold, UDim.new(0, 14))
	premiumButton.MouseButton1Click:Connect(function()
		Remotes.PromptRobuxPurchase:FireServer("SeasonPremium")
	end)

	-- ===== THE TRACK SITS IN A TRAY (15.28) =====
	--
	-- Thirty columns floating on the shell's bare grey read as a spreadsheet: nothing said where the
	-- board began or ended, and the two rows were told apart only by a padlock glyph on the lower
	-- one. The tray draws the board, and its left gutter names the rows ONCE instead of thirty
	-- times -- the columns are 92px wide and a "PREMIUM" caption does not fit in one, which is why
	-- the row had no label at all before.
	--
	-- ZIndex 8 is deliberate and low. Inside `trackPage` the only siblings are `sideCard` (styleCard
	-- leaves it in the 1..5 band, since nothing sets its ZIndex) and `trackScroll` at 24, so the
	-- tray's own shadow at 8+Z.Content clears the card and stays under every column. It does not
	-- need to clear the PANEL's shadow: under ZIndexBehavior.Sibling a child always draws above its
	-- parent, and this is a child of trackPage.
	local tray = Instance.new("Frame")
	tray.Name = "TrackTray"
	tray.Size = UDim2.new(1, -214, 0, TRAY_H)
	tray.Position = UDim2.new(0, 214, 0.5, 0)
	tray.AnchorPoint = Vector2.new(0, 0.5)
	tray.ZIndex = 8
	tray.Parent = trackPage
	-- ===== THE DARKEST SURFACE IN THE GAME, AND IT WAS 182,000 PX OF IT (18.6) =====
	--
	-- It was an explicit violet, rgb(104,98,138) -- luminance **0.41**, measured against every other
	-- panel in this file sitting between 0.89 and 1.00. 666 x 286 px of it, filling the whole right
	-- three quarters of the panel Kristina photographed when she said "puno je sivo i monotono". The
	-- reasoning for picking a violet was right (a *shade* of PANEL_SHELL comes out a hueless grey,
	-- because GradientFor drops white's foot to rgb(163,160,176)) and the VALUE was the mistake: the
	-- fix for "grey" was a dark colour rather than a light one.
	--
	-- `Color.Cloud` is the kit's own token for exactly this object -- "an inset rather than a raised
	-- chip: progress-bar tracks, wells, list backings" -- rgb(222,228,244), **luminance 0.89**, still
	-- comfortably a light surface, and it is what every groove in the game is already made of. It
	-- keeps the violet hue that made the tray read as a board rather than as more panel (hue 227deg,
	-- the same family as the old fill) at a value that lets the sixty reward cells carry the colour
	-- instead of fighting a dark ground for it. Luminance 0.41 -> 0.89.
	styleCard(tray, UITheme.Color.Cloud, UDim.new(0, 18), 4)

	-- Rotated -90 ABOUT ITS OWN CENTRE, so the box is authored landscape and lands portrait. A
	-- 44-wide box carrying the same Rotation would still be measured 44 wide before the turn and
	-- the 92px of text would spill sideways over the first column.
	-- The y values are the two card rows and they are DERIVED now (see the constants at the top of
	-- this block) rather than measured once by hand: FREE_TAG_Y = 84, PREMIUM_TAG_Y = 202, which is
	-- the 79/207 pair moved by the rail losing 10 px of height.
	--
	-- The two colours are a hierarchy, not decoration, and they had to change with the tray. Cream on
	-- a 0.41 violet was a white word on a dark board; on `Cloud` (0.89) it would be white on
	-- near-white. `Color.Ink` (lum 0.17) is dark ink and therefore drops its halo by the same rule
	-- every other dark label in this file uses -- it reads as the ordinary row. Gold keeps its 4 px
	-- near-black halo and is the only loud thing in the gutter, which is the point: PREMIUM is the
	-- row you are being sold.
	for _, tag in ipairs({
		{ text = "FREE", y = FREE_TAG_Y, color = UITheme.Color.Ink },
		{ text = "PREMIUM", y = PREMIUM_TAG_Y, color = UITheme.Color.Gold },
	}) do
		local tagLabel = Instance.new("TextLabel")
		tagLabel.Name = tag.text .. "Tag"
		tagLabel.Size = UDim2.new(0, 92, 0, 44)
		tagLabel.Position = UDim2.new(0, 27, 0, tag.y)
		tagLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		tagLabel.BackgroundTransparency = 1
		tagLabel.Rotation = -90
		tagLabel.Text = tag.text
		tagLabel.Parent = tray
		themeLabel(tagLabel, 20, tag.color)
	end

	-- right: the thirty columns, scrolling sideways. x=268 rather than 224 -- the 44px it gives up
	-- is the tray's gutter, and the canvas scrolls anyway so no reward cell is lost for it.
	local trackScroll = Instance.new("ScrollingFrame")
	trackScroll.Name = "TrackScroll"
	trackScroll.Size = UDim2.new(1, -268, 0, SCROLL_H)
	trackScroll.Position = UDim2.new(0, 268, 0.5, 0)
	trackScroll.AnchorPoint = Vector2.new(0, 0.5)
	trackScroll.BackgroundTransparency = 1
	trackScroll.BorderSizePixel = 0
	trackScroll.ScrollBarThickness = 8
	trackScroll.ScrollingDirection = Enum.ScrollingDirection.X
	trackScroll.CanvasSize = UDim2.new(0, SEASON.maxLevel * PITCH + 8, 0, 0)
	trackScroll.ZIndex = trackPage.ZIndex
	trackScroll.Parent = trackPage

	local trackLayout = Instance.new("UIListLayout")
	trackLayout.FillDirection = Enum.FillDirection.Horizontal
	trackLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	trackLayout.SortOrder = Enum.SortOrder.LayoutOrder
	trackLayout.Padding = UDim.new(0, 12)
	trackLayout.Parent = trackScroll

	-- What a cell shows: the best thing in the reward as one big icon, and its count under it.
	-- A cell is 92px square -- it cannot list four payouts, and the point of the icon is to be
	-- recognisable at a glance while scrolling past thirty of them.
	--
	-- THE THIRD RETURN IS THE REWARD'S OWN HUE (18.6), and it is what stops a claimed cell going
	-- grey. Four payout kinds, four kit tokens, chosen so that **none of them is Green**: Green is
	-- the one "press me" colour on this board, and an idle cell wearing it would compete with the
	-- sixty cells that genuinely can be claimed -- the same collision the Daily ramp was designed
	-- around in 18.3. Shards take Sunny because the shard glyph is already yellow, diamonds Aqua,
	-- potions Bubblegum, DNA Lavender.
	local function rewardFace(reward)
		if reward.shards then return "\u{2728}", "x" .. reward.shards, UITheme.Color.Sunny end
		if reward.diamonds then return "\u{1F48E}", "x" .. reward.diamonds, UITheme.Color.Aqua end
		if reward.potions then
			local potion = reward.potionId and GameConfig.GetPotion(reward.potionId)
			return potion and potion.emoji or "\u{1F9EA}", "x" .. reward.potions, UITheme.Color.Bubblegum
		end
		return "\u{1F9EC}", formatNumber(reward.dna or 0), UITheme.Color.Lavender
	end

	-- ===== INK FOLLOWS THE FILL, ON EVERY REPAINT (18.6) =====
	--
	-- `themeLabel` decides ink once and latches it behind a `Themed` attribute, which is correct for
	-- a label whose surface never changes colour. Every caption on this board sits on a surface that
	-- is repainted four different ways by `refresh`, and one of those ways is now `DoneShade` -- a
	-- fill at luminance 0.90, i.e. above the kit's 0.86 `LIGHT_SURFACE` cut, where white text with a
	-- 4 px near-black halo reads as a black smudge. Ink and halo move together (rule 7) or the dark
	-- glyph ends up inside a dark outline, which is the blob this file has already paid for twice.
	--
	-- Takes the HOST, never the proxy: both `styleButton` (TextButton -> `Label`) and `styleCard`'s
	-- new mirror (TextLabel -> `Label`) forward `TextColor3` to their child, so writing it here is
	-- what keeps every call site's `x.Text = ...` working. Neither of them forwards stroke WIDTH --
	-- the kit's hook moves transparency only -- so the halo is corrected on whichever instance
	-- actually draws the glyph.
	local function inkOnCell(host, fill)
		local light = UITheme.IsLightSurface(fill)
		host.TextColor3 = light and UITheme.Color.Ink or UITheme.Color.White
		local drawn = host:FindFirstChild("Label")
		if not (drawn and drawn:IsA("TextLabel")) then
			drawn = host
		end
		local st = drawn:FindFirstChildOfClass("UIStroke")
		if st then
			st.Thickness = light and 0 or 4
			st.Transparency = light and 1 or 0
		end
	end

	local cells = {} -- [level] = { free = refs, premium = refs }

	local function buildCell(parent, level, track, order)
		local btn = Instance.new("TextButton")
		btn.Name = track
		btn.Size = UDim2.new(0, CELL, 0, CELL)
		btn.LayoutOrder = order
		btn.Text = ""
		btn.ZIndex = parent.ZIndex
		btn.Parent = parent
		local strokeInst = styleCard(btn, UITheme.Color.Locked, UDim.new(0, 14), 4)

		local reward = GameConfig.GetSeasonReward(level)[track]
		local faceEmoji, faceAmount, faceHue = rewardFace(reward)

		-- ===== BIGGER ICONS, ASKED FOR IN AS MANY WORDS ("vece ikone") =====
		--
		-- 36 px of slot at 30 pt of glyph inside a 92 px cell: the reward -- the only thing on the
		-- cell anybody scrolls the board to see -- was smaller than the padlock under it, and the
		-- three bands (icon 5..41, amount 40..60, status 65..89) already overlapped by a pixel. The
		-- band is re-cut so the icon takes the slack: **icon 2..44, amount 44..64, status 66..90**,
		-- glyph 30 -> 36 pt in a 36 -> 42 px slot, and no two bands touch. Same move 18.3 made on the
		-- Daily tiles ("vece ikone"), where the glyph went 56 -> 84 px.
		UITheme.IconSlot(btn, {
			name = "Icon", icon = faceEmoji, maxTextSize = 36,
			size = UDim2.new(1, -8, 0, 42), position = UDim2.new(0, 4, 0, 2),
		})

		local amount = Instance.new("TextLabel")
		amount.Size = UDim2.new(1, -8, 0, 20)
		amount.Position = UDim2.new(0, 4, 0, 44)
		amount.BackgroundTransparency = 1
		amount.Text = faceAmount
		amount.Parent = btn
		themeLabel(amount, 17)

		local status = Instance.new("TextLabel")
		status.Size = UDim2.new(1, -8, 0, 24)
		status.Position = UDim2.new(0, 4, 1, -26)
		status.BackgroundTransparency = 1
		status.Text = "\u{1F512}"
		status.Parent = btn
		themeLabel(status, 16)

		btn.MouseButton1Click:Connect(function()
			if claimRewardRemote then
				claimRewardRemote:FireServer(level, track)
			end
		end)

		-- `amount` and `hue` ride along so `refresh` can repaint the cell in the reward's own colour
		-- and re-ink both captions against whatever fill it just chose.
		return { btn = btn, status = status, amount = amount, hue = faceHue, strokeInst = strokeInst }
	end

	for level = 1, SEASON.maxLevel do
		local row = GameConfig.GetSeasonReward(level)

		local column = Instance.new("Frame")
		column.Name = "Level" .. level
		-- Derived (COL_H, top of this block) instead of the old hand-summed 36. It was CELL*2 + rail
		-- + the list layout's two 5 px gaps and it had to be re-added by hand every time the rail
		-- moved; the tray's two rotated row tags are computed off the same expression.
		column.Size = UDim2.new(0, CELL, 0, COL_H)
		column.LayoutOrder = level
		column.BackgroundTransparency = 1
		column.ZIndex = trackScroll.ZIndex + UITheme.Z.Content
		column.Parent = trackScroll

		local columnLayout = Instance.new("UIListLayout")
		columnLayout.SortOrder = Enum.SortOrder.LayoutOrder
		columnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		columnLayout.Padding = UDim.new(0, COL_GAP)
		columnLayout.Parent = column

		local freeRefs = buildCell(column, level, "free", 1)

		-- ===== ONE RAIL THROUGH THE BOARD, NOT THIRTY LOOSE NUMBER CHIPS (15.28) =====
		--
		-- The strip between the two tracks used to be thirty separate pills, each saying only the
		-- number it was already sitting under. It is one continuous bar instead, running BETWEEN the
		-- free and premium rows -- the one line on the page that belongs to both of them.
		--
		-- It is still built PER COLUMN: the columns are placed by a UIListLayout, and a one-piece rail
		-- parented to the scrolling frame would be laid out as a thirty-first column. The segment is
		-- CELL + the layout's 12px padding wide and the column's vertical layout centres it, so each
		-- segment overhangs 6px either side and the seams close into one unbroken bar.
		--
		-- ===== AND IT IS NO LONGER A SECOND PROGRESS BAR (18.6) =====
		--
		-- Her words, on a capture of this exact panel: *"ovde imaju 2 progres bara sta ce mi"*. She is
		-- right and they were the SAME number twice -- the 186x30 `SeasonXP` bar in the level card and
		-- this rail, whose fill was `clamp(pos - lvl + 0.5, 0, 1)` per segment, i.e. the same
		-- `level + into/need` drawn a second time and 666 px wide. The XP bar stays, because it is the
		-- headline number and it is the only one of the two that carries the text ("1170 / 1500 XP").
		--
		-- The rail becomes what it looks like: **track**. Each segment is filled or it is not -- a
		-- binary on the level being reached, no partial fill anywhere on the board -- so the eye reads
		-- it as the line joining thirty stations rather than as a bar creeping along. The node discs
		-- already carry per-level state (reached / next / locked) at three colours, so nothing is lost
		-- by taking the analogue reading off the line under them.
		--
		-- Thinner with it: **26 -> 16 px**. A 26 px bar with a 34 px disc sitting on it is a bar with
		-- a bump; a 16 px line under the same disc is a rail with a station on it, which is the whole
		-- difference between "progress" and "track". The 10 px it gives back go to the column, the
		-- tray's two row tags and the free/premium band split -- all derived from RAIL_H at the top of
		-- this block, so none of them had to be re-measured by hand.
		local rail = Instance.new("Frame")
		rail.Name = "Rail"
		rail.Size = UDim2.new(0, CELL + 12, 0, RAIL_H)
		rail.LayoutOrder = 2
		-- The empty half of the track. It was `shade(Locked, -0.35)` = rgb(106,105,117), luminance
		-- 0.42 -- a near-black strip drawn thirty times across a panel whose complaint is that it is
		-- grey. On the light tray it is `Cloud` shaded a touch (rgb(191,196,210), lum 0.76): still
		-- plainly a groove, no longer the second darkest thing on the screen.
		rail.BackgroundColor3 = shade(UITheme.Color.Cloud, -0.14)
		rail.BorderSizePixel = 0
		rail.ZIndex = column.ZIndex
		rail.Parent = column

		-- No UICorner and no UIStroke on either piece, on purpose: rounded ends or an outline on every
		-- segment would draw thirty pill shapes again, which is the thing this replaced.
		local railFill = Instance.new("Frame")
		railFill.Name = "Fill"
		railFill.Size = UDim2.new(0, 0, 1, 0)
		railFill.BackgroundColor3 = UITheme.Color.Green
		railFill.BorderSizePixel = 0
		railFill.ZIndex = rail.ZIndex + 1
		railFill.Parent = rail
		gradient(railFill, ColorSequence.new(UITheme.Color.Mint, UITheme.Color.Green), 90)

		-- The level number rides the rail as a node, so the bar passes THROUGH each milestone rather
		-- than running alongside it. Milestone nodes are simply bigger -- the colour is state (see
		-- refresh) and cannot also be used to mean "this one matters".
		local node = Instance.new("Frame")
		node.Name = "Node"
		node.Size = UDim2.new(0, row.milestone and 40 or 34, 0, row.milestone and 40 or 34)
		node.Position = UDim2.new(0.5, 0, 0.5, 0)
		node.AnchorPoint = Vector2.new(0.5, 0.5)
		node.ZIndex = rail.ZIndex + 2
		node.Parent = rail
		local nodeStroke = styleCard(node, UITheme.Color.Locked, UDim.new(1, 0), 3)

		local nodeLabel = Instance.new("TextLabel")
		nodeLabel.Name = "NodeLabel"
		nodeLabel.Size = UDim2.new(1, -8, 1, -8)
		nodeLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
		nodeLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		nodeLabel.BackgroundTransparency = 1
		nodeLabel.Text = tostring(level)
		nodeLabel.ZIndex = node.ZIndex + UITheme.Z.Content
		nodeLabel.Parent = node
		themeLabel(nodeLabel, row.milestone and 21 or 18)

		local premiumRefs = buildCell(column, level, "premium", 3)

		cells[level] = {
			free = freeRefs, premium = premiumRefs,
			railFill = railFill, node = node, nodeStroke = nodeStroke,
			milestone = row.milestone == true,
		}
	end

	-- ================= QUEST PAGE =================

	local questScroll = Instance.new("ScrollingFrame")
	questScroll.Name = "QuestScroll"
	questScroll.Size = UDim2.new(1, 0, 1, 0)
	questScroll.BackgroundTransparency = 1
	questScroll.BorderSizePixel = 0
	questScroll.ScrollBarThickness = 8
	questScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	questScroll.ZIndex = questPage.ZIndex
	questScroll.Parent = questPage

	local questLayout = Instance.new("UIListLayout")
	questLayout.SortOrder = Enum.SortOrder.LayoutOrder
	questLayout.Padding = UDim.new(0, 7)
	questLayout.Parent = questScroll

	local questRows = {}   -- [period .. "|" .. key] = refs
	local periodHeaders = {} -- [period] = label, for the countdown
	-- [period] = the LayoutOrder of that period's header. The rows below it are re-ordered on every
	-- refresh (claimable first -- see the sort in `refresh`), so their order is a function of state
	-- rather than of the order they were built in, and it has to be measured from something fixed.
	local periodBase = {}
	local questOrder = 0

	for _, period in ipairs({ "daily", "weekly" }) do
		local periodDef = GameConfig.QuestPeriods[period]

		questOrder += 1
		periodBase[period] = questOrder
		local header = Instance.new("Frame")
		header.Name = period .. "Header"
		header.Size = UDim2.new(1, -10, 0, 40)
		header.LayoutOrder = questOrder
		header.ZIndex = questScroll.ZIndex + UITheme.Z.Content
		header.Parent = questScroll
		styleCard(header, period == "daily" and UITheme.Color.Aqua or UITheme.Color.Peach, UDim.new(0, 12), 3)

		local headerLabel = Instance.new("TextLabel")
		headerLabel.Size = UDim2.new(1, -20, 1, -6)
		headerLabel.Position = UDim2.new(0, 12, 0, 2)
		headerLabel.BackgroundTransparency = 1
		headerLabel.TextXAlignment = Enum.TextXAlignment.Left
		headerLabel.Text = periodDef.emoji .. " " .. periodDef.label
		headerLabel.Parent = header
		themeLabel(headerLabel, 22)
		periodHeaders[period] = headerLabel

		for _, quest in ipairs(GameConfig.GetQuests(period)) do
			questOrder += 1
			local row = Instance.new("Frame")
			row.Name = quest.key
			row.Size = UDim2.new(1, -10, 0, 74)
			row.LayoutOrder = questOrder
			row.ZIndex = questScroll.ZIndex + UITheme.Z.Content
			row.Parent = questScroll
			local rowStroke = styleCard(row, PET_ROW_SHELL, UDim.new(0, 14), 4)

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(0, 330, 0, 28)
			nameLabel.Position = UDim2.new(0, 16, 0, 8)
			nameLabel.BackgroundTransparency = 1
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.Text = quest.emoji .. " " .. quest.name
			nameLabel.Parent = row
			themeLabel(nameLabel, 23)

			local barBg, barFill, barLabel = UITheme.ProgressBar(row, {
				name = "Progress",
				size = UDim2.new(0, 330, 0, 26),
				position = UDim2.new(0, 16, 1, -34),
				color = UITheme.Color.Green,
				text = "0 / " .. quest.target,
				maxTextSize = 17,
				zIndex = row.ZIndex + UITheme.Z.Content,
			})

			-- ===== WHAT THE CLAIM BUTTON ACTUALLY PAYS, WHICH IS NOT THE SEASON XP =====
			--
			-- This row used to read "+1200 Season XP" beside a Claim button, and that is the whole
			-- "the Season Pass bar does not go up when I claim" report -- the bar is right and the
			-- label was wrong. `SeasonPassService.Track` pays the XP **pro rata as the quest
			-- advances** (deliberately: it used to arrive in one lump at the button, so the level bar
			-- was frozen for the entire time the player was doing the work). By the time a quest is
			-- claimable the player has already been paid every point of its XP, so the claim adds
			-- nothing to the bar and cannot be made to without paying twice.
			--
			-- So the label says where each half really comes from: the XP is earned as you go, and
			-- the button hands over the diamonds. A quest with no diamonds says so plainly rather
			-- than promising a number that has already landed.
			local payLabel = Instance.new("TextLabel")
			payLabel.Size = UDim2.new(0, 220, 1, -16)
			payLabel.Position = UDim2.new(0, 360, 0, 8)
			payLabel.BackgroundTransparency = 1
			payLabel.TextXAlignment = Enum.TextXAlignment.Left
			payLabel.TextWrapped = true
			payLabel.Text = quest.diamonds
				and ("Claim: +%d \u{1F48E}\n%d Season XP as you go"):format(quest.diamonds, quest.xp)
				or ("%d Season XP as you go"):format(quest.xp)
			payLabel.Parent = row
			-- `Cream` (rgb 255,248,235, lum 0.97) on a row shell at lum 0.885 is a near-white word on
			-- a near-white card, held up entirely by its 4 px near-black halo -- legible, and drawn as
			-- an outline rather than as text. `InkSoft` is the kit's own token for "secondary text on
			-- a light surface" and, being dark ink, drops the halo by the same rule.
			themeLabel(payLabel, 18, UITheme.Color.InkSoft)

			local claimBtn = Instance.new("TextButton")
			claimBtn.Name = "ClaimButton"
			claimBtn.Size = UDim2.new(0, 120, 0, 46)
			claimBtn.Position = UDim2.new(1, -14, 0.5, -23)
			claimBtn.AnchorPoint = Vector2.new(1, 0)
			claimBtn.Text = "Claim"
			claimBtn.Parent = row
			styleButton(claimBtn, UITheme.Color.Locked, UDim.new(1, 0))
			claimBtn.MouseButton1Click:Connect(function()
				if claimQuestRemote then
					claimQuestRemote:FireServer(period, quest.key)
				end
			end)

			questRows[period .. "|" .. quest.key] = {
				quest = quest, period = period, rowStroke = rowStroke,
				barFill = barFill, barLabel = barLabel, claimBtn = claimBtn,
				-- `row` so refresh can re-order it; `bornOrder` so rows inside one band keep the
				-- order they were authored in instead of coming out of `pairs` differently each time
				row = row, bornOrder = questOrder,
			}
		end
	end

	questScroll.CanvasSize = UDim2.new(0, 0, 0, questOrder * 78 + 30)

	-- Forward-declared because the HUD tile is built at the BOTTOM of this block (it wants the
	-- panel and `refresh` to exist first) while `refresh` is what owns the badge. A closure that
	-- referenced a local declared later would compile to a global read and silently do nothing.
	local tileBadge, tileBadgeLabel
	local lastClaimable = 0

	-- ================= REFRESH =================

	local function refresh()
		if not currentData then return end
		-- the season can turn over mid-session (7.3), so the header is re-read rather than assumed
		do
			-- NO LEADING EMOJI HERE ANY MORE (17.x). The title is PanelHeader's now, and PanelHeader
			-- runs IconifyLabel on it -- the leading glyph is stripped and drawn as a `TitleIcon`
			-- picture beside the words. This line re-added the glyph on the very first refresh, so
			-- the band rendered a drawn ticket AND the ticket emoji next to it. Photographed; it is
			-- the exact trap the Pets panel's refresh already carries a warning about.
			--
			-- The drawn icon is fixed at build time, which is very slightly wrong only for a session
			-- that spans a season turnover: the NAME updates and the picture would not. Accepted
			-- rather than solved, because UITheme.SetIcon looks for a child called `Icon`/`Label` and
			-- the band's is `TitleIcon`, so pointing it here would need a kit change for a case that
			-- lasts until the next rejoin.
			title.Text = GameConfig.GetCurrentSeason().name
		end
		local season = currentData.Season or {}
		local xp = season.xp or 0
		local level = GameConfig.GetSeasonLevel(xp)
		local into, need = GameConfig.GetSeasonLevelProgress(xp)
		local hasPremium = season.premium == true
		-- string keys: a table keyed by scattered integers does not survive the RemoteEvent that
		-- brought this data over -- see SeasonPassService
		local claimedFree = season.claimedFree or {}
		local claimedPremium = season.claimedPremium or {}
		-- Counted by the two loops below rather than by a second pass that re-derives the same
		-- question: each of them already has an exact "this one is pressable" branch, and a
		-- separate counter written against the same rules is the thing that drifts from them.
		local claimable = 0
		-- counted in the same pass, for the same reason: the header chip and the board must agree
		local collected = 0

		levelLabel.Text = "Level " .. level
		xpBarFill.Size = UDim2.new(need > 0 and (into / need) or 1, 0, 1, 0)
		xpBarLabel.Text = (level >= SEASON.maxLevel)
			and "MAX LEVEL"
			or ("%d / %d XP"):format(into, need)

		if hasPremium then
			premiumStatus.Text = "\u{2705} Premium unlocked \u{2014} both rows are yours."
			premiumButton.Visible = false
		else
			premiumStatus.Text = "Premium unlocks the bottom row, including every level you have already passed."
			premiumButton.Visible = true
		end

		-- There used to be a `pos = level + into/need` here -- the season expressed as one continuous
		-- number, 9.47 -- and the rail's per-segment partial fill was its only reader. That reading is
		-- the SeasonXP bar's job and always was (18.6), so the fractional position is gone with it
		-- rather than left behind as a value nothing draws.
		for lvl = 1, SEASON.maxLevel do
			local refs = cells[lvl]
			local slot = tostring(lvl)
			local reached = (lvl <= level)

			for _, track in ipairs({ "free", "premium" }) do
				local cellRefs = refs[track]
				local claimed = (track == "premium" and claimedPremium or claimedFree)[slot] == true
				local owned = (track == "free") or hasPremium

				-- ===== 88 SURFACES ON THIS PANEL WERE PAINTED `Color.Locked` (18.6) =====
				--
				-- Four states went through one swatch: claimed, claimable-behind-the-pass, not yet
				-- reached, and (on the nodes) not yet reached again. Three of those are refusals and
				-- grey is right for them. The fourth is a **receipt** -- a reward the player earned and
				-- collected -- and painting it in the refusal colour is the whole of "izgleda kao da
				-- dobijam rewards sto radim u mrtvacnici". Three states, three axes, exactly as 18.3
				-- did it on the Daily board: full chroma to claim, `DoneShade` of the reward's OWN hue
				-- when it is collected, no hue at all when it genuinely cannot be had.
				local fill
				if claimed then
					collected += 1
					cellRefs.status.Text = "\u{2705} Claimed"
					-- same hue, a third of the chroma, lifted to luminance 0.90 so the ink can never
					-- flip: Sunny rgb(255,212,75) -> rgb(250,240,213), Aqua rgb(105,205,250) ->
					-- rgb(216,240,250), Bubblegum -> rgb(250,222,240), Lavender -> rgb(235,226,251).
					-- Four pale pastels against the one flat rgb(163,161,180) they all used to be.
					fill = UITheme.DoneShade(cellRefs.hue)
					cellRefs.strokeInst.Color = OUTLINE_COLOR
					cellRefs.strokeInst.Thickness = 4
				elseif reached and owned then
					-- the one "press me" state on the board, same bright rim as everywhere else
					claimable += 1
					cellRefs.status.Text = "CLAIM!"
					fill = UITheme.Color.Green
					cellRefs.strokeInst.Color = READY_RIM
					cellRefs.strokeInst.Thickness = 5
				elseif reached and not owned then
					-- earned but behind the pass: gold rim, so it reads as "buy this" and not "grind
					-- more". This one KEEPS the locked fill -- the reward genuinely cannot be had --
					-- and it is the gold rim, not the fill, that does the selling.
					cellRefs.status.Text = "\u{1F512} Premium"
					fill = UITheme.Color.Locked
					cellRefs.strokeInst.Color = UITheme.Color.Gold
					cellRefs.strokeInst.Thickness = 4
				else
					cellRefs.status.Text = "\u{1F512} Lv." .. lvl
					fill = UITheme.Color.Locked
					cellRefs.strokeInst.Color = OUTLINE_COLOR
					cellRefs.strokeInst.Thickness = 4
				end
				setButtonColor(cellRefs.btn, fill)
				inkOnCell(cellRefs.status, fill)
				inkOnCell(cellRefs.amount, fill)
			end

			-- THE RAIL IS A CONNECTOR, NOT A BAR (18.6). It was
			-- `clamp(pos - lvl + 0.5, 0, 1)` -- a partial fill sliding through the segment the player
			-- is standing in, which is the second progress bar she photographed. Binary now: a segment
			-- behind a level already reached is full, everything ahead of it is empty, and there is no
			-- moving edge anywhere on the board. `pos` is still computed above because the node loop
			-- moving edge anywhere on the board.
			refs.railFill.Size = UDim2.new(reached and 1 or 0, 0, 1, 0)

			-- and the node lights as the level lands. The one level AHEAD wears the ready rim, so the
			-- board always points at the next thing rather than only marking the last -- the same
			-- signal the Daily board and the Mastery list use for "this is the live one".
			if reached then
				setButtonColor(refs.node, refs.milestone and UITheme.Color.Gold or UITheme.Color.Green)
				refs.nodeStroke.Color = OUTLINE_COLOR
				refs.nodeStroke.Thickness = 3
			elseif lvl == level + 1 then
				setButtonColor(refs.node, UITheme.Color.Sunny)
				refs.nodeStroke.Color = READY_RIM
				refs.nodeStroke.Thickness = 4
			else
				setButtonColor(refs.node, UITheme.Color.Locked)
				refs.nodeStroke.Color = OUTLINE_COLOR
				refs.nodeStroke.Thickness = 3
			end
		end

		-- the header chip. Gold and a trophy when the whole pass is in the bag, because "60 / 60" is
		-- the proudest line this panel can print and 18.4 already settled that a finished ladder gets
		-- to say so rather than going quiet.
		local total = SEASON.maxLevel * 2
		if collected >= total then
			tally.Text = ("\u{1F3C6} ALL %d COLLECTED!"):format(total)
			setButtonColor(tally, UITheme.Color.Gold)
		else
			tally.Text = ("\u{1F381} %d / %d collected"):format(collected, total)
			setButtonColor(tally, UITheme.Color.Aqua)
		end

		local held = currentData.Quests or {}
		-- ===== A CLAIMABLE QUEST GOES TO THE TOP OF ITS OWN CATEGORY =====
		--
		-- Collected here so the sort below has every row's state before any of them are placed. Rows
		-- keep their authored order inside each band, so nothing shuffles under the cursor while the
		-- player is reaching for a button -- only crossing a band moves a row, and that only happens
		-- on a completion or a claim, which the player just caused.
		local banded = { daily = {}, weekly = {} }
		for _, refs in pairs(questRows) do
			local quest = refs.quest
			local periodData = held[refs.period] or {}
			-- A period the server has not reset yet still carries the PREVIOUS period's numbers, so
			-- the stamp is checked here too rather than trusted -- otherwise a player who leaves the
			-- panel open across midnight watches yesterday's finished board.
			local stale = periodData.periodId ~= GameConfig.GetQuestPeriodId(refs.period)
			local done = stale and 0 or ((periodData.progress or {})[quest.key] or 0)
			local claimed = (not stale) and ((periodData.claimed or {})[quest.key] == true)

			refs.barFill.Size = UDim2.new(math.clamp(done / quest.target, 0, 1), 0, 1, 0)
			refs.barLabel.Text = ("%d / %d"):format(math.min(done, quest.target), quest.target)

			-- band 1 claimable, 2 still running, 3 finished with. A claimed quest sinks to the
			-- bottom rather than staying where it was: it is the one row on the board with nothing
			-- left to do, and it is exactly what the player has just stopped caring about.
			local band
			if claimed then
				band = 3
				refs.claimBtn.Text = "\u{2705} Done"
				-- A finished quest is a receipt, not a refused control (18.6). It was the SAME
				-- rgb(163,161,180) as the "🔒 2 left" button two rows down -- one swatch for "you did
				-- it" and "you did not". `DoneShade(Green)` is rgb(219,247,232) at luminance 0.90:
				-- unmistakably the green family, unmistakably spent, and light enough that the caption
				-- has to flip to dark ink -- which is what `inkOnCell` is doing on all three branches.
				setButtonColor(refs.claimBtn, UITheme.DoneShade(UITheme.Color.Green))
				inkOnCell(refs.claimBtn, UITheme.DoneShade(UITheme.Color.Green))
				refs.rowStroke.Color = OUTLINE_COLOR
				refs.rowStroke.Thickness = 4
			elseif done >= quest.target then
				band = 1
				claimable += 1
				refs.claimBtn.Text = "CLAIM!"
				setButtonColor(refs.claimBtn, UITheme.Color.Green)
				inkOnCell(refs.claimBtn, UITheme.Color.Green)
				refs.rowStroke.Color = READY_RIM
				refs.rowStroke.Thickness = 5
			else
				band = 2
				-- ===== AN UNFINISHED QUEST DOES NOT OFFER A CLAIM BUTTON =====
				--
				-- This said "Claim" in the Locked colour, which is the SAME grey the finished
				-- "Done" state uses -- so a quest at 0/3 and a quest already claimed looked
				-- identical, and the only one of the three states that was actually pressable
				-- (CLAIM!) was the odd one out. Players pressed the grey one, the server answered
				-- "That quest isn't finished yet!", and it read as "the claim buttons do not work".
				-- It is the exact thing in the 2026-08-11 screenshot: 0/3 offering Claim while
				-- 50/50 shows Done.
				--
				-- The button now states the requirement instead of inviting a press. The bar under
				-- it already shows progress, so the button says what is missing, not where you are.
				refs.claimBtn.Text = ("\u{1F512} %d left"):format(math.max(quest.target - done, 0))
				setButtonColor(refs.claimBtn, UITheme.Color.Locked)
				inkOnCell(refs.claimBtn, UITheme.Color.Locked)
				refs.rowStroke.Color = OUTLINE_COLOR
				refs.rowStroke.Thickness = 4
			end
			local bucket = banded[refs.period]
			if bucket then
				table.insert(bucket, { refs = refs, band = band, born = refs.bornOrder })
			end
		end

		-- ...and place them. LayoutOrder is measured from each period's own header, so the two
		-- categories can never interleave however their rows are re-ordered inside themselves.
		for period, rows in pairs(banded) do
			table.sort(rows, function(a, b)
				if a.band ~= b.band then return a.band < b.band end
				return a.born < b.born
			end)
			local base = periodBase[period] or 0
			for i, entry in ipairs(rows) do
				entry.refs.row.LayoutOrder = base + i
			end
		end

		-- ===== THE TILE HAS TO SAY THERE IS SOMETHING TO PRESS =====
		--
		-- Every other route into this panel was the player deciding to look. The Daily tile has
		-- carried a claimable-today flag since it was built; the Season tile was authored without
		-- one, so a finished quest and an unclaimed level sat behind a tile that looked exactly
		-- like a tile with nothing in it.
		--
		-- IT IS A COUNT, NOT A DOT. "3" is a reason to open the panel; a bare mark is a decoration
		-- the eye learns to skip after the second session -- which is also why it goes dark the
		-- moment the last thing is claimed rather than staying lit as an advert for the feature.
		lastClaimable = claimable
		if tileBadge then
			tileBadge.Visible = claimable > 0
			if tileBadgeLabel then
				tileBadgeLabel.Text = (claimable > 9) and "9+" or tostring(claimable)
			end
		end
	end

	-- the countdown to the next reset, ticking only while somebody is looking at it
	local function updateTimers()
		for period, label in pairs(periodHeaders) do
			local def = GameConfig.QuestPeriods[period]
			local remaining = math.max(0, GameConfig.GetQuestPeriodEnd(period) - os.time())
			label.Text = ("%s %s  \u{2022}  resets in %dh %02dm")
				:format(def.emoji, def.label, remaining // 3600, (remaining % 3600) // 60)
		end
	end

	task.spawn(function()
		while true do
			task.wait(1)
			if panel.Visible then
				updateTimers()
			end
		end
	end)

	-- ---- HUD tile, bottom of the right column (see RIGHT_COUNT)
	-- The badge is authored WITH the tile and hidden immediately, because UITheme.Badge is only
	-- reachable through the IconTile options table -- there is no "add a badge later" call. Hidden
	-- rather than left showing its placeholder: the first DataUpdate is a few hundred milliseconds
	-- out, and a red "1" that flashes on every join and is usually wrong is worse than no badge.
	local tile = columnTile("R", 5, SEASON.emoji, "Season", UITheme.Color.Sunny, "1", UITheme.Color.Coral)
	tileBadge = tile:FindFirstChild("Badge")
	tileBadgeLabel = tileBadge and tileBadge:FindFirstChild("Label")
	if tileBadge then tileBadge.Visible = false end
	tile.MouseButton1Click:Connect(function()
		toggleOnly(panel)
		setTab(currentTab)
		updateTimers()
		refresh()
	end)

	setTab("track")
	updateTimers()

	hudRefs.refreshSeasonPanel = refresh
	-- read by the welcome-back card, which has to know whether this feature has anything waiting
	-- before it offers a row pointing at it. It is the number `refresh` last drew on the badge, so
	-- the card and the tile can never disagree about what is claimable.
	hudRefs.seasonClaimCount = function() return lastClaimable end
	hudRefs.showSeasonPanel = function()
		toggleOnly(panel)
		setTab(currentTab)
		updateTimers()
		refresh()
	end
end)()

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
;(function()
	local shown = false

	local ROW_H, ROW_GAP = 88, 12
	local panel = Instance.new("Frame")
	panel.Name = "WelcomeBackPanel"
	-- 294 = the header's own 90 (top 14 + height 64 + gap 12) + two rows + the gap between them +
	-- 16 of bottom margin. It was authored at 276, which is 2px SHORT of the rows alone, so the
	-- second card hung over the shell's bottom rim. Two rows is the most this card can ever have
	-- and it is authored at that height on purpose: registerPanel computes its responsive fit from
	-- the authored size, so a panel that resized itself afterwards would be scaling off a stale one.
	panel.Size = UDim2.new(0, 580, 0, 294)
	panel.Position = PANEL_ANCHOR
	panel.ZIndex = 20
	panel.Visible = false
	panel.Parent = screenGui
	styleCard(panel, PANEL_SHELL, UDim.new(0, 24), 5)
	registerPanel(panel)
	panelClose(panel)

	-- THE SUBTITLE IS CAPTURED, and that is not a tidy-up. The hand-built `local sub` this header
	-- replaced was deleted while the line 200 lines down that writes to it ("Two things are waiting
	-- for you.") was left standing -- so `sub` resolved to a nil GLOBAL and `maybeWelcomeBack`
	-- threw on the first payload of every session, which is the one call that opens this card.
	-- `luanames.py` cannot see it: it is deliberately not scope-aware and two OTHER functions in
	-- this file declare a local called `sub`, so the name looked bound.
	local header, contentTop, _, sub = UITheme.PanelHeader(panel, {
		title = "\u{1F44B} Welcome Back!",
		subtitle = "You have unclaimed rewards waiting!",
		accent = UITheme.Color.Lavender,
		margin = 16,
		top = 14,
		height = 64,
	})

	local rowHost = Instance.new("Frame")
	rowHost.Name = "Rows"
	rowHost.Size = UDim2.new(1, -32, 0, ROW_H * 2 + ROW_GAP)
	rowHost.Position = UDim2.new(0, 16, 0, contentTop)
	rowHost.BackgroundTransparency = 1
	rowHost.ZIndex = panel.ZIndex + UITheme.Z.Content
	rowHost.Parent = panel

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.Padding = UDim.new(0, ROW_GAP)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = rowHost

	local function buildRow(order, color, defaultIcon, action)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, ROW_H)
		row.LayoutOrder = order
		row.ZIndex = rowHost.ZIndex + UITheme.Z.Content
		row.Visible = false
		row.Parent = rowHost
		styleCard(row, PET_ROW_SHELL, UDim.new(0, 16), 3.5)

		local iconBox = Instance.new("Frame")
		iconBox.Name = "IconBox"
		iconBox.Size = UDim2.new(0, 56, 0, 56)
		iconBox.Position = UDim2.new(0, 14, 0.5, 0)
		iconBox.AnchorPoint = Vector2.new(0, 0.5)
		iconBox.ZIndex = row.ZIndex + UITheme.Z.Content
		iconBox.Parent = row
		styleCard(iconBox, UITheme.Shade(color, 0.25), UDim.new(0, 12), 2.5)

		local iconLabel = Instance.new("TextLabel")
		iconLabel.Name = "IconLabel"
		iconLabel.Size = UDim2.new(1, 0, 1, 0)
		iconLabel.BackgroundTransparency = 1
		iconLabel.Text = defaultIcon or "\u{1F381}"
		iconLabel.Font = DISPLAY_FONT
		iconLabel.ZIndex = iconBox.ZIndex + UITheme.Z.Content
		themeLabel(iconLabel, 30)
		iconLabel.Parent = iconBox

		local head = Instance.new("TextLabel")
		head.Name = "Head"
		head.Size = UDim2.new(1, -250, 0, 28)
		head.Position = UDim2.new(0, 80, 0, 14)
		head.BackgroundTransparency = 1
		head.TextXAlignment = Enum.TextXAlignment.Left
		head.ZIndex = row.ZIndex + UITheme.Z.Content
		head.Parent = row
		themeLabel(head, 24)

		local note = Instance.new("TextLabel")
		note.Name = "Note"
		-- 24 -> 32 (15.16). Measured at the 14px floor, the Season Pass row's note -- "Finished
		-- quests and levels you have already passed" -- wraps to two lines needing **28px** in a
		-- 24px box, so its second line was cut on every join that opened this card. Wrapping is not
		-- turned off here the way the potion rows do it: at 14px the string is wider than the 298
		-- it has, so one line would truncate instead. The row is 88 tall and this ends at 78, so
		-- the 10px below it is the clearance the growth is taken out of.
		note.Size = UDim2.new(1, -250, 0, 32)
		note.Position = UDim2.new(0, 80, 0, 46)
		note.BackgroundTransparency = 1
		note.TextXAlignment = Enum.TextXAlignment.Left
		note.ZIndex = row.ZIndex + UITheme.Z.Content
		note.Parent = row
		themeLabel(note, 17, UITheme.Color.Gold)

		local btn = Instance.new("TextButton")
		btn.Name = "GoButton"
		btn.Size = UDim2.new(0, 130, 0, 52)
		btn.Position = UDim2.new(1, -14, 0.5, 0)
		btn.AnchorPoint = Vector2.new(1, 0.5)
		btn.Text = "CLAIM"
		btn.ZIndex = row.ZIndex + UITheme.Z.Content
		btn.Parent = row
		styleButton(btn, color, UDim.new(0, 14))
		btn.MouseButton1Click:Connect(action)

		return row, head, note, btn, iconLabel
	end

	local dailyRow, dailyHead, dailyNote, dailyBtn, dailyIcon = buildRow(1, UITheme.Color.Green, "\u{1F381}", function()
		refreshRewardPanel()
		toggleOnly(rewardPanel)
	end)
	local seasonRow, seasonHead, seasonNote, seasonBtn, seasonIcon = buildRow(2, UITheme.Color.Sunny, "\u{1F3C6}", function()
		hudRefs.showSeasonPanel()
	end)

	function hudRefs.maybeWelcomeBack(data, firstPayload)
		if shown or not firstPayload then return end
		shown = true
		if type(data) ~= "table" then return end
		if not data.TutorialDone then return end

		-- The same question refreshRewardPanel asks, off the same two fields, so the card and the
		-- tile badge can never disagree about whether today has been claimed.
		local dailyReady = dayNumber(os.time()) > dayNumber(data.LastRewardClaim)
		local seasonReady = hudRefs.seasonClaimCount and hudRefs.seasonClaimCount() or 0

		if not dailyReady and seasonReady <= 0 then return end

		if dailyReady then
			local streak = data.RewardStreak or 0
			local today = dayNumber(os.time())
			-- the streak the claim will PRODUCE, not the one on the save: a player who missed a day
			-- is starting again at 1, and telling them "Day 6 is ready" and then paying Day 1 is
			-- the kind of small lie that makes the whole board look broken
			local continuing = (today == dayNumber(data.LastRewardClaim) + 1)
			local upcoming = continuing and (streak + 1) or 1
			local index = ((math.max(upcoming, 1) - 1) % #GameConfig.DailyRewards) + 1
			dailyHead.Text = ("\u{1F381} Daily reward \u{2014} Day %d is ready"):format(index)
			-- AND THE NOTE HAS TO ASK THE SAME QUESTION THE HEAD DOES (11.28). It used to test only
			-- `streak > 0`, so a player who missed a day was told "Day 1 is ready" over "4 day streak
			-- -- claim to keep it going": the head had already worked out the streak was gone and the
			-- line under it still promised to keep it. Same lie the comment above was written against,
			-- one line lower down. A broken streak is worth saying out loud rather than hiding -- it is
			-- the only thing on this card that asks the player to come back tomorrow.
			dailyNote.Text = (continuing and streak > 0)
				and ("\u{1F525} %d day streak \u{2014} claim to keep it going"):format(streak)
				or (streak > 0 and "\u{1F494} Your streak ended \u{2014} this one starts a new run"
					or "Claim it to start a streak")
		end
		dailyRow.Visible = dailyReady

		if seasonReady > 0 then
			seasonHead.Text = ("\u{1F3C6} Season Pass \u{2014} %d to claim"):format(seasonReady)
			seasonNote.Text = "Finished quests and levels you have already passed"
		end
		seasonRow.Visible = seasonReady > 0

		sub.Text = (dailyReady and seasonReady > 0)
			and "Two things are waiting for you."
			or "You have something waiting."

		-- ===== AND THE CARD IS AS TALL AS WHAT IS ACTUALLY WAITING (16.5) =====
		--
		-- Authored at two rows, because two is the most it can ever hold and `registerPanel` reads
		-- its responsive fit off the AUTHORED size. But one row is the common case by a distance --
		-- the Season Pass has something to claim only after a level or a quest turns over -- and one
		-- row in a two-row card is 100 px of empty shell under the daily reward, which reads as a
		-- card that failed to finish loading rather than as a card with one thing on it.
		--
		-- SHRINKING IS THE SAFE DIRECTION and that is why this is allowed to run after
		-- `registerPanel`: the UIScale it fitted is computed for 580x294, so a panel that ends up
		-- SMALLER than that still fits every viewport it fitted before. Growing is what would be
		-- scaling off a stale number, and nothing here ever grows past the authored height.
		local liveRows = (dailyRow.Visible and 1 or 0) + (seasonRow.Visible and 1 or 0)
		if liveRows > 0 then
			local rowsH = liveRows * ROW_H + (liveRows - 1) * ROW_GAP
			rowHost.Size = UDim2.new(1, -32, 0, rowsH)
			-- 14 top + 64 header + 12 gap + rows + 16 bottom margin: the same arithmetic the
			-- authored 294 comes from, with the row count no longer assumed to be two.
			panel.Size = UDim2.new(0, 580, 0, 14 + 64 + 12 + rowsH + 16)
		end

		task.spawn(function()
			-- WAIT FOR THE LOADING SCREEN TO GO, and wait for the object rather than for a delay.
			-- LoadingScreen holds for MIN_SHOW 2.6 s and then fades for another 0.45 -- but it also
			-- waits on the HUD existing and on preloading, so the real number is a range, and a card
			-- animating open underneath it would be over by the time the wipe cleared.
			local lg = player:FindFirstChild("PlayerGui")
			local screen = lg and lg:FindFirstChild("LoadingScreen")
			local waited = 0
			while screen and screen.Parent and waited < 20 do
				waited += task.wait(0.1)
			end
			task.wait(0.35)
			-- ...and do not shove a card in front of something the player opened in the meantime.
			-- Twenty seconds is a long time to hold a greeting; if they are already busy, they have
			-- found their own way in and the badge on the tile is enough.
			for _, p in ipairs(togglePanels) do
				if p.Visible then return end
			end
			toggleOnly(panel)
		end)
	end
end)()

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
;(function()
	local ROW_H, ROW_GAP = 56, 8
	local PANEL_W = 620

	local aurasPanel = Instance.new("Frame")
	aurasPanel.Name = "AurasPanel"
	aurasPanel.Size = UDim2.new(0, PANEL_W, 0, 550)
	aurasPanel.Visible = false
	aurasPanel.ZIndex = 40
	aurasPanel.Parent = screenGui
	-- SHELL BEFORE registerPanel, and that order is the whole of 15.1: the cyan panel rim is chosen
	-- inside registerPanel off a UIStroke that has to already exist. Styling afterwards leaves the
	-- panel with the plain dark outline every card in the game wears and nothing marks it as a panel.
	styleCard(aurasPanel, PANEL_SHELL, UDim.new(0, 22), 5)
	registerPanel(aurasPanel)
	panelClose(aurasPanel)

	local _, topY, _, headerSub = UITheme.PanelHeader(aurasPanel, {
		title = "\u{1F9EC} Auras",
		subtitle = "Rolled at the DNA Splicer -- one is worn at a time",
		accent = UITheme.Color.Purple,
		maxTextSize = 28,
		margin = 16,
		top = 14,
	})

	local list = Instance.new("ScrollingFrame")
	list.Name = "AuraList"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.new(0, 16, 0, topY)
	list.Size = UDim2.new(1, -32, 1, -topY - 16)
	list.ZIndex = aurasPanel.ZIndex + UITheme.Z.Content
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = Color3.fromRGB(60, 70, 90)
	-- Seven rows fit without scrolling today; the canvas is computed rather than authored so an
	-- eighth mutation added to GameConfig.Mutations arrives as a scroll instead of as a row nobody
	-- can reach. (`Mutations` is rank-ordered, so a new one goes in rank position -- see the note
	-- over that table -- and this panel inherits the order for free.)
	list.CanvasSize = UDim2.new(0, 0, 0,
		#GameConfig.Mutations * ROW_H + (#GameConfig.Mutations - 1) * ROW_GAP)
	list.Parent = aurasPanel

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, ROW_GAP)
	listLayout.Parent = list

	local rows = {}
	local equipRemote
	-- The remote is created by SplicerService.Init at server boot, so it is there long before a
	-- player can open this -- but it is waited for rather than looked up, which is the 15.5 lesson:
	-- a FindFirstChild at build time on a remote created anywhere else is a permanently dead button.
	task.spawn(function()
		equipRemote = Remotes:WaitForChild("EquipMutation", 30)
	end)

	for i, mut in ipairs(GameConfig.Mutations) do
		local row = Instance.new("Frame")
		row.Name = "Aura_" .. mut.name
		row.Size = UDim2.new(1, 0, 0, ROW_H)
		row.LayoutOrder = i
		row.ZIndex = list.ZIndex
		styleCard(row, UITheme.Color.PanelWhite, UDim.new(0, 14), 3)
		row.Parent = list

		-- THE COLOUR IS THE AURA. This chip is painted the exact Color3 the particles on the body
		-- take, so the panel and the player are the same object seen twice.
		local chip = Instance.new("Frame")
		chip.Name = "Chip"
		chip.Size = UDim2.new(0, 44, 0, 44)
		chip.Position = UDim2.new(0, 10, 0.5, 0)
		chip.AnchorPoint = Vector2.new(0, 0.5)
		chip.ZIndex = row.ZIndex + UITheme.Z.Content
		styleCard(chip, mut.color, UDim.new(0, 12), 3)
		chip.Parent = row

		-- Inked by luminance, not by rarity name: Godly is near-white and Secret is near-black, and
		-- the two sit four rows apart in the same column.
		local bright = (0.299 * mut.color.R + 0.587 * mut.color.G + 0.114 * mut.color.B) > 0.55
		local count = UITheme.Label(chip, {
			name = "Count",
			text = "",
			size = UDim2.new(1, -4, 1, -4),
			position = UDim2.new(0, 2, 0, 2),
			maxTextSize = 20,
			minTextSize = 12,
			color = bright and Color3.fromRGB(46, 40, 30) or UITheme.Color.White,
			zIndex = chip.ZIndex + UITheme.Z.Content,
		})

		local name = UITheme.Label(row, {
			name = "Name",
			text = mut.name,
			size = UDim2.new(1, -240, 0, 24),
			position = UDim2.new(0, 66, 0, 7),
			xAlign = "Left",
			maxTextSize = 22,
			minTextSize = 15,
			color = Color3.fromRGB(30, 35, 45),
			zIndex = row.ZIndex + UITheme.Z.Content,
		})

		local effect = UITheme.Label(row, {
			name = "Effect",
			text = "",
			size = UDim2.new(1, -240, 0, 20),
			position = UDim2.new(0, 66, 0, 30),
			xAlign = "Left",
			maxTextSize = 15,
			minTextSize = 11,
			color = Color3.fromRGB(80, 95, 115),
			zIndex = row.ZIndex + UITheme.Z.Content,
		})

		local wear = UITheme.Button(row, {
			name = "Wear",
			text = "Wear",
			size = UDim2.new(0, 140, 0, 40),
			position = UDim2.new(1, -12, 0.5, 0),
			anchorPoint = Vector2.new(1, 0.5),
			color = UITheme.Color.Green,
			radius = 12,
			maxTextSize = 18,
			zIndex = row.ZIndex + UITheme.Z.Content,
		})
		wear.MouseButton1Click:Connect(function()
			-- Dimmed AND dead, the Journal's rule for its own Equip button: a greyed button that
			-- still fires a remote and gets a refusal back says the press failed rather than that
			-- there was nothing to press.
			if not wear.Active or not equipRemote then return end
			equipRemote:FireServer(mut.name)
		end)

		rows[mut.name] = { row = row, count = count, name = name, effect = effect, wear = wear }
	end

	local function refreshAurasPanel()
		local found = (currentData and currentData.SplicerFound) or {}
		local worn = currentData and currentData.SplicerMutation
		local ownedCount = 0

		for _, mut in ipairs(GameConfig.Mutations) do
			local r = rows[mut.name]
			local n = tonumber(found[mut.name]) or 0
			local isOwned = n > 0
			local isWorn = isOwned and worn == mut.name
			if isOwned then ownedCount += 1 end

			r.count.Text = isOwned and ("x" .. n) or "?"
			r.name.TextTransparency = isOwned and 0 or 0.35
			if isOwned then
				r.effect.Text = ("\u{1F48E} x%.2f DNA   \u{26A1} +%d%% speed"):format(mut.incomeMult, mut.speedPct)
				r.effect.TextTransparency = 0
			else
				-- The locked row is the only line in the game that says where a mutation comes from.
				r.effect.Text = ("\u{1F512} Roll at the DNA Splicer \u{2022} x%.2f DNA, +%d%% speed"):format(
					mut.incomeMult, mut.speedPct)
				r.effect.TextTransparency = 0.15
			end

			-- `UITheme.SetText` / `UITheme.SetColor`, never `.Text` and `setButtonColor`: a
			-- UITheme.Button draws its caption into a child called "Label" and its fill into a
			-- child "Body", so writing the button's own properties changes a surface nobody sees.
			r.wear.Visible = isOwned
			if isWorn then
				UITheme.SetText(r.wear, "\u{2713} Wearing")
				UITheme.SetColor(r.wear, UITheme.Color.Locked)
				r.wear.Active = false
				r.wear.AutoButtonColor = false
			else
				UITheme.SetText(r.wear, "Wear")
				UITheme.SetColor(r.wear, UITheme.Color.Green)
				r.wear.Active = true
				r.wear.AutoButtonColor = true
			end
		end

		if headerSub then
			local m = worn and GameConfig.GetMutationByName(worn)
			headerSub.Text = m
				and ("%d of %d found \u{2022} wearing %s (x%.2f DNA, +%d%% speed)")
					:format(ownedCount, #GameConfig.Mutations, m.name, m.incomeMult, m.speedPct)
				or ("%d of %d found \u{2022} nothing worn -- roll one at the DNA Splicer")
					:format(ownedCount, #GameConfig.Mutations)
		end
	end

	hudRefs.refreshAurasPanel = refreshAurasPanel

	local aurasButton = screenGui:FindFirstChild("AurasButton")
	if aurasButton then
		aurasButton.MouseButton1Click:Connect(function()
			toggleOnly(aurasPanel)
			refreshAurasPanel()
		end)
	end

	refreshAurasPanel()
end)()

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
;(function()
	local UIS = game:GetService("UserInputService")

	-- Order 8, the bottom-right corner, which was the one genuinely empty slot in the cluster. NOT 5:
	-- that is the Season Pass tile, built inside its own block further up, and the two overlapped
	-- exactly until a live read of the column caught it.
	local audioButton = columnTile("R", 8, "\u{1F50A}", "Audio", UITheme.Color.Aqua)

	local panel = Instance.new("Frame")
	panel.Name = "AudioPanel"
	panel.Size = UDim2.new(0, 430, 0, 408)
	panel.Position = PANEL_ANCHOR
	panel.ZIndex = 20
	panel.Visible = false
	panel.Parent = screenGui
	styleCard(panel, PANEL_SHELL, UDim.new(0, 22), 5)
	registerPanel(panel)
	panelClose(panel)

	-- Converted to the shared accent band (17.x). Rows moved 64 -> 100 and the panel grew by the same
	-- 36, so the bottom-anchored mute button keeps its gap. Aqua matches the Audio tile that opens it.
	UITheme.PanelHeader(panel, {
		title = "\u{1F50A} Audio",
		subtitle = "Master fades the other three",
		accent = UITheme.Color.Aqua,
	})

	-- `Master` is a fader over the other three rather than a fourth channel, which is why it leads and
	-- why the mute button below drives it and nothing else: muting is one decision, not four.
	local ROWS = {
		{ key = "Master",   label = "Master",    color = UITheme.Color.Gold },
		{ key = "SFX",      label = "Effects",   color = UITheme.Color.Coral },
		{ key = "UI",       label = "Interface", color = UITheme.Color.Aqua },
		{ key = "Ambience", label = "Ambience",  color = UITheme.Color.Mint },
	}

	local values = { Master = 1, SFX = 1, UI = 1, Ambience = 1 }
	local tracks, apply = {}, {}
	local dragging = nil
	local preMute = 1
	local refreshMute -- assigned below; declared here so `apply` can call it

	-- Applied LOCALLY on every frame of a drag, so the fader is audible while it moves, but only SENT
	-- when the drag ends. A remote per mouse-move frame is sixty round trips a second for a preference,
	-- and the server's copy only has to be right by the time the player lets go.
	local function commit()
		-- looked up rather than held: the remote is created by PlayerDataService.Init, and a
		-- WaitForChild at build time would stall the whole HUD if that ever stopped happening
		local remote = Remotes:FindFirstChild("SetAudioVolumes")
		if remote then
			remote:FireServer(values)
		end
	end

	for i, row in ipairs(ROWS) do
		local y = 100 + (i - 1) * 58

		UITheme.Label(panel, {
			name = row.key .. "Name", text = row.label,
			size = UDim2.new(0, 96, 0, 28), position = UDim2.new(0, 20, 0, y),
			xAlign = "Left", maxTextSize = 20, zIndex = 22,
		})

		local track = Instance.new("Frame")
		track.Name = row.key .. "Track"
		-- -216, not -196. The readout is right-anchored at (1, -18) and 60 wide, so it starts at x=352;
		-- at -196 the track ran to 356 and the two boxes overlapped by 4px -- more like 8 once the
		-- track's 4px stroke is counted, since UIStroke draws OUTSIDE the frame. Measured, not guessed.
		track.Size = UDim2.new(1, -216, 0, 26)
		track.Position = UDim2.new(0, 122, 0, y + 1)
		track.ZIndex = 22
		track.Parent = panel
		styleCard(track, UITheme.Color.PanelWhite, UDim.new(1, 0), 4)

		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.new(1, 0, 1, 0)
		fill.BackgroundColor3 = row.color
		fill.BorderSizePixel = 0
		fill.ZIndex = 23
		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(1, 0)
		fillCorner.Parent = fill
		local fillGrad = Instance.new("UIGradient")
		fillGrad.Rotation = 90
		fillGrad.Color = UITheme.GradientFor(row.color)
		fillGrad.Parent = fill
		fill.Parent = track

		local readout = UITheme.Label(panel, {
			name = row.key .. "Value", text = "100%",
			size = UDim2.new(0, 60, 0, 28), position = UDim2.new(1, -18, 0, y),
			anchorPoint = Vector2.new(1, 0), xAlign = "Right", maxTextSize = 20, zIndex = 22,
		})

		tracks[row.key] = track
		apply[row.key] = function(a)
			a = math.clamp(a, 0, 1)
			values[row.key] = a
			fill.Size = UDim2.new(a, 0, 1, 0)
			readout.Text = math.floor(a * 100 + 0.5) .. "%"
			SoundLibrary.SetVolumes(values)
			if refreshMute then refreshMute() end
		end

		-- A transparent TextButton over the track, taller than it, rather than input on the Frame: the
		-- extra 12px of height is what makes a 26px bar catchable with a finger.
		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.AutoButtonColor = false
		hit.Size = UDim2.new(1, 0, 1, 14)
		hit.Position = UDim2.new(0, 0, 0, -7)
		hit.ZIndex = 26
		hit.Parent = track
		hit.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging = row.key
				local t = tracks[row.key]
				apply[row.key]((input.Position.X - t.AbsolutePosition.X) / math.max(t.AbsoluteSize.X, 1))
			end
		end)
	end

	-- Tracked on UserInputService, not on the track: a drag that leaves the bar -- which is exactly
	-- what happens when you pull a fader to 0% or 100% -- would otherwise stop updating at the edge
	-- and strand the value wherever the pointer crossed it.
	UIS.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			local t = tracks[dragging]
			apply[dragging]((input.Position.X - t.AbsolutePosition.X) / math.max(t.AbsoluteSize.X, 1))
		end
	end)
	UIS.InputEnded:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = nil
			if values.Master > 0 then preMute = values.Master end
			commit()
		end
	end)

	local muteButton = UITheme.Button(panel, {
		name = "MuteAll", text = "MUTE ALL", color = UITheme.Color.Red,
		size = UDim2.new(0, 190, 0, 46), position = UDim2.new(0.5, 0, 1, -20),
		anchorPoint = Vector2.new(0.5, 1), radius = 14, zIndex = 22, maxTextSize = 22,
	})

	refreshMute = function()
		local muted = values.Master <= 0
		-- colour AND wording, like the Auto tile: a control that only changes hue is a guess
		UITheme.SetColor(muteButton, muted and UITheme.Color.Green or UITheme.Color.Red)
		UITheme.SetText(muteButton, muted and "UNMUTE" or "MUTE ALL")
	end

	-- Restores what the fader was BEFORE the mute rather than snapping to 100%: a player who set the
	-- game to a quarter volume and then muted it did not ask to be shouted at when they come back.
	muteButton.MouseButton1Click:Connect(function()
		if values.Master > 0 then
			preMute = values.Master
			apply.Master(0)
		else
			apply.Master(preMute > 0 and preMute or 1)
		end
		commit()
	end)

	audioButton.MouseButton1Click:Connect(function()
		toggleOnly(panel)
	end)

	hudRefs.refreshAudioPanel = function(data)
		local saved = (data and data.AudioVolumes) or {}
		for _, row in ipairs(ROWS) do
			local v = tonumber(saved[row.key])
			-- `v == v` rejects NaN, which would otherwise clamp through and paint a "nan%" readout
			apply[row.key]((v ~= nil and v == v) and v or 1)
		end
		if values.Master > 0 then preMute = values.Master end
		refreshMute()
	end
	refreshMute()
end)()


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
;(function()
	-- ===== NO HUD TILE OF ITS OWN (11.18), BUT A DOOR AGAIN (12.8) =====
	--
	-- 12.8 did not put the ninth tile back. `hudRefs.showEggPanel` is reachable from the Market
	-- flyout now (one tile, two buttons, built near the layout pass at the bottom of this file), and
	-- it is called with NO egg key from there -- so the panel opens on Basic in the player's own
	-- zone, prices and odds live, and the hatch buttons stay locked until they are standing at a
	-- podium. The paragraph below is why the dedicated tile is not coming back, and it still holds:
	-- a HUD button that cannot say which egg you are looking at should not be the one people use.
	--
	--
	-- "The egg screen belongs on the egg." This panel used to be reachable only from a tile in the
	-- corner of the screen -- the ninth in the right column -- while the podium the player had
	-- actually walked to carried two prompts that bought eggs and showed nothing. The two halves of
	-- the feature were in the two places the other one was not.
	--
	-- The prompt on the egg opens it now (PetService stamps `ShopPanel = "eggs"` on it, so it
	-- arrives through the one ProximityPromptService handler at the bottom of this file, beside the
	-- fusion lab and the upgrade counters). The tile is deleted rather than kept as a second route,
	-- for the reason the fusion lab already documents: two ways in means the one that cannot show
	-- you which egg you are standing at is the one people use. RIGHT_COUNT went 9 -> 8 with it.
	--
	-- The panel itself is unchanged, and `hudRefs.refreshEggPanel` is still called from refreshUI.

	local panel = Instance.new("Frame")
	panel.Name = "EggPanel"
	panel.Size = UDim2.new(0, 470, 0, 556)
	panel.Position = PANEL_ANCHOR
	panel.ZIndex = 20
	panel.Visible = false
	panel.Parent = screenGui
	styleCard(panel, PANEL_SHELL, UDim.new(0, 22), 5)
	registerPanel(panel)
	panelClose(panel)

	-- Converted to the shared accent band (17.x). Every child below moved down 36 and the panel grew
	-- by the same 36. The TITLE handle is kept because `refreshEggPanel` rewrites it per stall
	-- ("Forest Eggs"), which is exactly the case PanelHeader's third return value exists for --
	-- anything that TICKS belongs in the subtitle, but a name that changes with the place you are
	-- standing is still a name. Sunny because an egg stall is the gold-rush corner of the game.
	local title = select(3, UITheme.PanelHeader(panel, {
		title = "\u{1F95A} Eggs",
		subtitle = "Odds are per hatch",
		accent = UITheme.Color.Sunny,
	}))

	-- WHICH STALL THE PLAYER IS STANDING AT, or nil. Read off the same ProximityPrompts PetService
	-- wired -- their `EggKey` attribute is already the authority on which egg a podium sells, so
	-- this needs no new attribute, no new remote and no second source of truth. Distance is measured
	-- against the prompt's OWN MaxActivationDistance for the reason PetService gives for Auto Hatch:
	-- it is the range the player can SEE they are in, so anything else reads as arbitrary.
	local function nearestEggZone()
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local zones = workspace:FindFirstChild("Zones")
		if not (hrp and zones) then return nil end
		local bestZone, bestDist = nil, nil
		for _, zoneModel in ipairs(zones:GetChildren()) do
			local shop = zoneModel:FindFirstChild("PetShop")
			if shop then
				for _, prompt in ipairs(shop:GetDescendants()) do
					if prompt:IsA("ProximityPrompt") and prompt:GetAttribute("EggKey") then
						local anchor = prompt.Parent
						if anchor and anchor:IsA("BasePart") then
							local d = (anchor.Position - hrp.Position).Magnitude
							if d <= prompt.MaxActivationDistance and (not bestDist or d < bestDist) then
								bestZone, bestDist = zoneModel.Name, d
							end
						end
					end
				end
			end
		end
		return bestZone
	end

	-- Which zone's three eggs are on show. Falls back to the zone the save says the player is in, so
	-- the panel is a useful price/odds list from anywhere -- only the BUY is gated on standing there.
	local shownZone = nil
	local selectedTier = "Basic"

	local tierRow = Instance.new("Frame")
	tierRow.Name = "TierRow"
	tierRow.Size = UDim2.new(1, -36, 0, 54)
	tierRow.Position = UDim2.new(0, 18, 0, 94)
	tierRow.BackgroundTransparency = 1
	tierRow.ZIndex = panel.ZIndex + UITheme.Z.Content
	tierRow.Parent = panel

	local tierButtons = {}
	for i, suffix in ipairs({ "Basic", "Better", "Premium" }) do
		local btn = Instance.new("TextButton")
		btn.Name = suffix
		btn.Size = UDim2.new(0.32, 0, 1, 0)
		btn.Position = UDim2.new((i - 1) * 0.34, 0, 0, 0)
		btn.Text = suffix
		btn.ZIndex = tierRow.ZIndex
		btn.Parent = tierRow
		styleButton(btn, UITheme.Color.Locked, UDim.new(0, 14))
		tierButtons[suffix] = btn
	end

	local costLabel = Instance.new("TextLabel")
	costLabel.Name = "Cost"
	costLabel.Size = UDim2.new(1, -36, 0, 26)
	costLabel.Position = UDim2.new(0, 18, 0, 154)
	costLabel.BackgroundTransparency = 1
	costLabel.TextXAlignment = Enum.TextXAlignment.Left
	costLabel.Text = ""
	costLabel.ZIndex = panel.ZIndex + UITheme.Z.Content
	costLabel.Parent = panel
	themeLabel(costLabel, 22, Color3.fromRGB(46, 34, 66))

	local oddsScroll = Instance.new("ScrollingFrame")
	oddsScroll.Name = "OddsScroll"
	oddsScroll.Size = UDim2.new(1, -36, 0, 232)
	oddsScroll.Position = UDim2.new(0, 18, 0, 186)
	oddsScroll.BackgroundTransparency = 1
	oddsScroll.BorderSizePixel = 0
	oddsScroll.ScrollBarThickness = 6
	oddsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	oddsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	oddsScroll.ZIndex = panel.ZIndex + UITheme.Z.Content
	oddsScroll.Parent = panel

	local oddsLayout = Instance.new("UIListLayout")
	oddsLayout.Padding = UDim.new(0, 6)
	oddsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	oddsLayout.Parent = oddsScroll

	-- ===== TWO BUTTONS, ONE ROW, AND NO HAND ARITHMETIC (11.3) =====
	--
	-- THE OVERLAPPING PAIR IS HATCH AND HATCH x10, not Hatch and Auto Hatch as the report reads it.
	-- Auto Hatch is on its own full-width line 60 px below and never touched anything. Measured, on
	-- a 470-wide panel: both of these were `0.48` (225.6 px each), one placed from x=18 and the
	-- other anchored to the right edge at 452 -- so they ran into each other by 17.2 px, and looked
	-- like more because styleCard's UIStroke draws OUTSIDE the frame, adding 5 px to each side of
	-- both. 225.6 + 225.6 + 36 of margin is 487 in a panel 470 wide; the two fractions were the bug.
	--
	-- A horizontal UIListLayout divides the row it is given instead of each button being told a
	-- fraction of the PANEL, so the gap is stated once as padding and neither one can be sized into
	-- its neighbour again -- including after the height shrink in `styleButton`, which is the sort
	-- of global change that turns hand arithmetic like this into a defect somewhere else.
	local actionRow = Instance.new("Frame")
	actionRow.Name = "ActionRow"
	-- 44, the shrunk primary height, written here rather than left at 50: both children fill the
	-- row (`1, 0` on Y), so the row owns their height and `styleButton`'s shrink -- which only ever
	-- rewrites an OFFSET height -- correctly does not touch them.
	actionRow.Size = UDim2.new(1, -36, 0, 44)
	actionRow.Position = UDim2.new(0, 18, 0, 432)
	actionRow.BackgroundTransparency = 1
	actionRow.ZIndex = panel.ZIndex + UITheme.Z.Content
	actionRow.Parent = panel

	local actionLayout = Instance.new("UIListLayout")
	actionLayout.FillDirection = Enum.FillDirection.Horizontal
	-- 24, NOT the 12 this was first written with, and the difference is the outline. `styleCard`'s
	-- UIStroke is 5 px and draws OUTSIDE the frame it belongs to, so the two buttons each spend 5
	-- of the gap before any daylight appears between them: a 12 px frame gap measured 2 px of
	-- actual space and the pair read as one merged bar, which is the crowding this row exists to
	-- remove rather than the overlap arithmetic it was reported as. 24 leaves 14 visible.
	--
	-- GENERAL RULE FOR THIS UI: a gap of N between two stroked siblings shows as N - 10.
	actionLayout.Padding = UDim.new(0, 24)
	actionLayout.SortOrder = Enum.SortOrder.LayoutOrder
	actionLayout.Parent = actionRow

	local hatchButton = Instance.new("TextButton")
	hatchButton.Name = "Hatch"
	-- half the row minus half the padding, which is the one arithmetic left and it cannot drift:
	-- 24 of padding split between two children is 12 each
	hatchButton.Size = UDim2.new(0.5, -12, 1, 0)
	hatchButton.LayoutOrder = 1
	hatchButton.Text = "HATCH"
	hatchButton.ZIndex = actionRow.ZIndex + UITheme.Z.Content
	hatchButton.Parent = actionRow
	styleButton(hatchButton, UITheme.Color.Green, UDim.new(0, 14))

	local bulkButton = Instance.new("TextButton")
	bulkButton.Name = "HatchBulk"
	bulkButton.Size = UDim2.new(0.5, -12, 1, 0)
	bulkButton.LayoutOrder = 2
	bulkButton.Text = "HATCH x10"
	bulkButton.ZIndex = actionRow.ZIndex + UITheme.Z.Content
	bulkButton.Parent = actionRow
	styleButton(bulkButton, UITheme.Color.Blue, UDim.new(0, 14))

	local autoButton = Instance.new("TextButton")
	autoButton.Name = "AutoHatch"
	autoButton.Size = UDim2.new(1, -36, 0, 46)
	autoButton.Position = UDim2.new(0, 18, 0, 492)
	autoButton.Text = "AUTO HATCH"
	autoButton.ZIndex = panel.ZIndex + UITheme.Z.Content
	autoButton.Parent = panel
	styleButton(autoButton, UITheme.Color.Locked, UDim.new(0, 14))

	-- ===== REFRESH =====
	local rows = {}
	local function refresh()
		local data = currentData
		if not data then return end

		local nearZone = nearestEggZone()
		shownZone = nearZone or data.CurrentZone or "Forest"
		title.Text = ("\u{1F95A} %s Eggs"):format(shownZone)

		-- the egg being described, and the honest luck it would actually be rolled at
		local egg = nil
		for _, e in ipairs(GameConfig.Eggs) do
			if e.zone == shownZone and e.tierSuffix == selectedTier then egg = e end
		end
		for suffix, btn in pairs(tierButtons) do
			setButtonColor(btn, suffix == selectedTier and UITheme.Color.Purple or UITheme.Color.Locked)
		end
		if not egg then return end

		-- `GetPetLuckPercent` is the egg-side total (shared luck + the shop's Luck upgrade at +5 a
		-- level, 11.5). It is what `rollAndInsert` rolls against, which is the whole point of this
		-- panel quoting a number at all.
		local luck = GameConfig.GetPetLuckPercent(data) + (egg.luckBonus or 0)
		local affordable = (data.DNA or 0) >= egg.cost
		costLabel.Text = ("%s  \u{2022}  \u{1F340} %d%% luck"):format(formatNumber(egg.cost), math.floor(luck))

		-- ONE ROW PER SPECIES, REBUILT ONLY WHEN THE POOL CHANGES. The odds themselves are rewritten
		-- every refresh (luck moves with potions and pets), but the rows are reused -- rebuilding a
		-- dozen cards on every DataUpdate is what made the pet list flicker.
		local odds = GameConfig.GetEggOdds(egg, luck)
		local key = egg.key
		if rows.key ~= key then
			for _, r in ipairs(rows) do r:Destroy() end
			table.clear(rows)
			rows.key = key
			for i, entry in ipairs(odds) do
				local rarity = GameConfig.GetRarity(entry.def.rarity)
				local row = Instance.new("Frame")
				row.Name = entry.def.key
				row.Size = UDim2.new(1, -10, 0, 52)
				row.LayoutOrder = i
				row.ZIndex = oddsScroll.ZIndex
				row.Parent = oddsScroll
				styleCard(row, rarity.color, UDim.new(0, 12), 3)

				UITheme.IconSlot(row, {
					name = "Icon", icon = entry.def.emoji, maxTextSize = 28,
					size = UDim2.new(0, 42, 1, -10), position = UDim2.new(0, 8, 0, 5),
				})

				local nameLabel = Instance.new("TextLabel")
				nameLabel.Name = "NameLabel"
				nameLabel.Size = UDim2.new(1, -160, 0, 24)
				nameLabel.Position = UDim2.new(0, 58, 0, 5)
				nameLabel.BackgroundTransparency = 1
				nameLabel.TextXAlignment = Enum.TextXAlignment.Left
				nameLabel.Text = entry.def.name
				nameLabel.Parent = row
				themeLabel(nameLabel, 20)

				local rarityLabel = Instance.new("TextLabel")
				rarityLabel.Name = "Rarity"
				rarityLabel.Size = UDim2.new(1, -160, 0, 20)
				rarityLabel.Position = UDim2.new(0, 58, 0, 27)
				rarityLabel.BackgroundTransparency = 1
				rarityLabel.TextXAlignment = Enum.TextXAlignment.Left
				rarityLabel.Text = rarity.name
				rarityLabel.Parent = row
				themeLabel(rarityLabel, 16, UITheme.Color.Cream)

				local pct = Instance.new("TextLabel")
				pct.Name = "Chance"
				pct.Size = UDim2.new(0, 96, 1, -10)
				pct.Position = UDim2.new(1, -10, 0, 5)
				pct.AnchorPoint = Vector2.new(1, 0)
				pct.BackgroundTransparency = 1
				pct.TextXAlignment = Enum.TextXAlignment.Right
				pct.Text = ""
				pct.Parent = row
				themeLabel(pct, 24)

				table.insert(rows, row)
			end
		end
		for i, entry in ipairs(odds) do
			local row = rows[i]
			local pct = row and row:FindFirstChild("Chance")
			if pct then
				-- `entry.text` when the entry brought its own (the 12.12 Secret row, quoted as
				-- "1 in 50,000"): two decimals cannot express a 0.002% chance and would print
				-- "0.00%", which is the same lie one order of magnitude further down.
				-- Otherwise two decimals under 1%, because "0%" on a Legendary is a lie the player
				-- can disprove.
				pct.Text = entry.text or (entry.chance < 1
					and ("%.2f%%"):format(entry.chance)
					or ("%.1f%%"):format(entry.chance))
			end
		end

		-- ===== THE BUY IS GATED ON STANDING AT THE STALL, AND SAYS SO =====
		--
		-- Not because the server enforces it -- it does NOT, see the note in STATUS.md about the
		-- unused IsNearPetShop -- but because the podium is where the hatch animation plays and
		-- where the prompts are. A button that silently works from across the map would make the
		-- stall pointless; one that greys out with no reason given is the "claim buttons do nothing"
		-- complaint all over again. So it states the requirement.
		if not nearZone then
			setButtonColor(hatchButton, UITheme.Color.Locked)
			setButtonColor(bulkButton, UITheme.Color.Locked)
			hatchButton.Text = "GO TO A PET SHOP"
			bulkButton.Text = "\u{1F512}"
		else
			setButtonColor(hatchButton, affordable and UITheme.Color.Green or UITheme.Color.Locked)
			setButtonColor(bulkButton, ((data.DNA or 0) >= egg.cost * 10) and UITheme.Color.Blue or UITheme.Color.Locked)
			hatchButton.Text = affordable and "HATCH" or "NEED DNA"
			bulkButton.Text = "HATCH x10"
		end

		-- Auto Hatch: owned or not, on or off. `nil` counts as ON, exactly as DriveAutoHatch reads it
		-- (only an explicit `false` stops it) -- so a pass owner who has never touched this sees the
		-- true state rather than an OFF that does not match what the server is doing.
		if GameConfig.OwnsPass(data, "AutoHatch") then
			local on = player:GetAttribute("AutoHatch") ~= false
			setButtonColor(autoButton, on and UITheme.Color.Green or UITheme.Color.Locked)
			autoButton.Text = on and "\u{1F504} AUTO HATCH: ON" or "\u{1F504} AUTO HATCH: OFF"
		else
			setButtonColor(autoButton, UITheme.Color.Gold)
			autoButton.Text = "\u{1F512} AUTO HATCH \u{2014} GAME PASS"
		end
	end

	for suffix, btn in pairs(tierButtons) do
		btn.MouseButton1Click:Connect(function()
			selectedTier = suffix
			refresh()
		end)
	end

	hatchButton.MouseButton1Click:Connect(function()
		local egg = nil
		for _, e in ipairs(GameConfig.Eggs) do
			if e.zone == shownZone and e.tierSuffix == selectedTier then egg = e end
		end
		-- Fired unconditionally when in range rather than gated on the local affordability check:
		-- the client's copy of the save is up to a push behind, and the server's own "Not enough
		-- DNA" toast is better than a button that silently does nothing. Same rule as the spins.
		if egg and nearestEggZone() then
			Remotes.BuyEgg:FireServer(egg.key)
		end
	end)

	bulkButton.MouseButton1Click:Connect(function()
		local egg = nil
		for _, e in ipairs(GameConfig.Eggs) do
			if e.zone == shownZone and e.tierSuffix == selectedTier then egg = e end
		end
		local bulk = Remotes:FindFirstChild("BuyEggBulk")
		if egg and bulk and nearestEggZone() then
			bulk:FireServer(egg.key)
		end
	end)

	autoButton.MouseButton1Click:Connect(function()
		if not (currentData and GameConfig.OwnsPass(currentData, "AutoHatch")) then
			-- Sends them to the shop rather than doing nothing at all: this is the one control in
			-- the panel a player can press without owning what it needs.
			if hudRefs.selectRobuxTab then hudRefs.selectRobuxTab(true) end
			toggleOnly(robuxPanel)
			return
		end
		local remote = Remotes:FindFirstChild("SetAutoHatch")
		if remote then
			remote:FireServer(player:GetAttribute("AutoHatch") == false)
		end
	end)

	player:GetAttributeChangedSignal("AutoHatch"):Connect(refresh)

	-- ===== OPENED BY THE EGG IN FRONT OF YOU (11.18) =====
	--
	-- `eggKey` is the attribute PetService already keeps on every podium prompt for Auto Hatch, so
	-- the panel can open ON THE EGG THE PLAYER PRESSED rather than always on Basic. That is the
	-- difference between "the egg screen" and "a shop that happens to be near an egg": press the
	-- Premium podium and the odds table you get is Premium's.
	--
	-- Falls back to Basic when the key does not resolve, which is also what happens for any future
	-- caller with nothing to say -- the same "selected fresh on every open" rule the HUD tile had,
	-- and for the same reason: the player has almost certainly walked to a different stall since
	-- last time, and reopening on a zone they have left is the same class of bug as a panel
	-- reopening at yesterday's scroll position.
	hudRefs.showEggPanel = function(eggKey)
		selectedTier = "Basic"
		if eggKey then
			for _, e in ipairs(GameConfig.Eggs) do
				if e.key == eggKey and e.tierSuffix then
					selectedTier = e.tierSuffix
					break
				end
			end
		end
		refresh()
		toggleOnly(panel)
	end

	-- Ticked while the panel is open so walking up to a stall unlocks the buttons without the
	-- player having to close and reopen it. One second is plenty for "am I standing there".
	task.spawn(function()
		while true do
			task.wait(1)
			if panel.Visible then
				refresh()
			end
		end
	end)

	hudRefs.refreshEggPanel = refresh
end)()

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
;(function()
	local cam = workspace.CurrentCamera
	if not cam then return end

	local columns = { L = {}, R = {} }
	for _, child in ipairs(screenGui:GetChildren()) do
		local side = child:GetAttribute("ColumnSide")
		if side and columns[side] then
			table.insert(columns[side], child)
		end
	end
	for _, list in pairs(columns) do
		table.sort(list, function(a, b)
			return (a:GetAttribute("ColumnOrder") or 0) < (b:GetAttribute("ColumnOrder") or 0)
		end)
	end

	-- what the columns may not grow into: the topbar and the stage card above, and the evolve card
	-- and XP bar below. BOTTOM_CLEAR came down 122 -> 46 when the quick-action row it was reserving
	-- space for became rows 3 and 4 of this cluster -- that dead strip is now cluster.
	-- 121, up from 96: the TopBar carrying the stage card ends at y = 32 and the first tile started
	-- at 38, which after both strokes is no gap at all -- the card and the Shop tile were touching.
	local TOP_CLEAR, BOTTOM_CLEAR = 121, 46

	-- THE GAP IS NOT THE GAP YOU SEE, and this is why raising it to 18 did not visibly separate
	-- anything. Every tile carries a UIStroke of 5 drawn in Border mode -- OUTSIDE the frame's own
	-- bounds -- so between two tiles a nominal gap loses 5 to the upper tile's stroke and 5 to the
	-- lower tile's.
	--
	-- THE ARITHMETIC CHANGED ON 2026-08-11: it used to lose a third 5 to the sibling drop shadow
	-- addShadow parked below every tile, i.e. `visible = GAP - 15`. That shadow is gone (see
	-- UITheme.addShadow for why), so it is **`visible = GAP - 10`** now -- and GAP came 31 -> 26 to
	-- hold the same 16px of actual daylight. Leaving it at 31 would have quietly opened the column
	-- to 21px and pushed the bottom row into BOTTOM_CLEAR on a short viewport.
	--
	-- 26 for 16px of daylight. The number to change is this one.
	local GAP_MAX, GAP_MIN = 26, 8
	-- ...and the gap closes BEFORE the tiles shrink, which is what the note at the top of this block
	-- promises and what the old fixed gap never actually did. At 31 a four-row cluster needs 93px of
	-- pure spacing, and on a short viewport that pushed the tiles under their 40px floor and
	-- overflowed the screen. Spacing is the first thing a cramped screen can afford to lose.
	-- how many tiles wide each side is. BOTH sides are two wide as of 16.2: the left column lost its
	-- Trade tile and the four that remain read as a 2x2 block rather than a four-tall ladder down the
	-- edge. Half the height means the tiles keep their authored 82px on viewports where the ladder was
	-- being shrunk to fit, and it hands the whole bottom-left quarter of the screen back.
	local WIDTH = { L = 2, R = RIGHT_COLS }

	local function layout()
		local avail = math.max(cam.ViewportSize.Y - TOP_CLEAR - BOTTOM_CLEAR, 140)
		for side, list in pairs(columns) do
			local n = #list
			if n > 0 then
				-- SIZE IS DRIVEN BY THE ROW COUNT, NOT THE TILE COUNT. That is the whole benefit of
				-- the grid: seven tiles in two columns is four rows, so each tile gets the height
				-- budget of a quarter of the screen instead of a seventh, and stays at its authored
				-- 82px on any ordinary viewport instead of shrinking toward the 40px floor and
				-- dragging every caption down to its minimum size with it.
				local cols = WIDTH[side] or 1
				local rows = math.ceil(n / cols)
				local gap = GAP_MAX
				local size = math.clamp(math.floor((avail - (rows - 1) * gap) / rows), 40, 82)
				if rows * size + (rows - 1) * gap > avail and rows > 1 then
					gap = math.clamp(math.floor((avail - rows * size) / (rows - 1)), GAP_MIN, GAP_MAX)
					size = math.clamp(math.floor((avail - (rows - 1) * gap) / rows), 40, 82)
				end
				local pitch = size + gap
				for i, tile in ipairs(list) do
					tile.Size = UDim2.new(0, size, 0, size)
					local col = (i - 1) % cols
					local row = math.floor((i - 1) / cols)
					if side == "L" then
						tile.Position = UDim2.new(0, 20 + col * pitch, 0, TOP_CLEAR + row * pitch)
					else
						-- anchored (1, 1), i.e. positioned by its bottom-RIGHT corner: the cluster
						-- fills upward from the bottom edge and leftward from the right one, so the
						-- last row and the last column are the ones pinned to the corner.
						tile.Position = UDim2.new(
							1, -20 - (cols - 1 - col) * pitch,
							1, -(BOTTOM_CLEAR + (rows - 1 - row) * pitch))
					end
				end
			end
		end
	end

	cam:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	layout()
end)()

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
;(function()
	local FADE_H = 30      -- tall enough to swallow a sliced row, short enough not to dim a full one
	local TAIL = 14        -- trailing space under the last row, so it never touches the clip line

	-- The fade has to sit ABOVE the scroll's own children. ZIndexBehavior is Sibling here (checked
	-- live), so a sibling one rung up covers the whole subtree and the children's own ZIndex does
	-- not enter into it.
	local function attachFade(scroll)
		local panel = scroll.Parent
		if not panel or not panel:IsA("GuiObject") then return end
		if panel:FindFirstChild(scroll.Name .. "Fade") then return end

		-- The panel does not paint its own background any more -- applyShell moved the fill into an
		-- InnerBody child and left only the BaseColor attribute behind. Reading BackgroundColor3
		-- here would return Roblox's default frame grey and paint a grey smear over a white panel.
		local base = panel:GetAttribute("BaseColor")
		if typeof(base) ~= "Color3" then base = PANEL_SHELL end

		local fade = Instance.new("Frame")
		fade.Name = scroll.Name .. "Fade"
		fade.BackgroundColor3 = base
		fade.BorderSizePixel = 0
		fade.ZIndex = scroll.ZIndex + 1
		-- A Frame that is not Active does not eat the wheel or a touch drag, so the bottom strip of
		-- the list stays scrollable through it.
		fade.Active = false
		fade.Visible = false

		-- Pin to the scroll's bottom edge in the scroll's own units, so this survives every resize
		-- and the panel-open UIScale without any absolute-pixel maths. Written to respect a
		-- non-zero AnchorPoint because TrackScroll has one (0, 0.5).
		fade.AnchorPoint = Vector2.new(scroll.AnchorPoint.X, 1)
		fade.Size = UDim2.new(scroll.Size.X.Scale, scroll.Size.X.Offset, 0, FADE_H)
		fade.Position = UDim2.new(
			scroll.Position.X.Scale,
			scroll.Position.X.Offset,
			scroll.Position.Y.Scale + scroll.Size.Y.Scale * (1 - scroll.AnchorPoint.Y),
			scroll.Position.Y.Offset + scroll.Size.Y.Offset * (1 - scroll.AnchorPoint.Y)
		)

		local grad = Instance.new("UIGradient")
		grad.Rotation = 90   -- default 0 runs left-to-right; the cut is horizontal
		grad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.45, 0.55),
			NumberSequenceKeypoint.new(1, 0.05),
		})
		grad.Parent = fade
		fade.Parent = panel

		-- Show it only when something is actually below the fold, or a short list wears a permanent
		-- smudge along its bottom edge for no reason.
		local function refresh()
			local below = scroll.AbsoluteCanvasSize.Y - (scroll.CanvasPosition.Y + scroll.AbsoluteWindowSize.Y)
			fade.Visible = below > 4
		end
		scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(refresh)
		scroll:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(refresh)
		scroll:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(refresh)
		panel:GetPropertyChangedSignal("Visible"):Connect(function()
			if panel.Visible then task.defer(refresh) end
		end)
		task.defer(refresh)
	end

	local function polish(scroll)
		-- A visible bar on a white shell. Outline is the kit's near-black; at 0.35 it reads as a
		-- grip rather than a black stripe.
		scroll.ScrollBarImageColor3 = UITheme.Color.Outline
		scroll.ScrollBarImageTransparency = 0.35
		if scroll.ScrollBarThickness < 10 then scroll.ScrollBarThickness = 10 end

		-- Trailing space has to be bought differently depending on who owns the canvas. Padding on
		-- an AutomaticCanvasSize scroll grows the canvas with it; on a fixed canvas it would only
		-- push the content up and clip the last row harder, so that case buys the space on the
		-- canvas directly.
		if scroll.AutomaticCanvasSize == Enum.AutomaticSize.Y then
			local pad = scroll:FindFirstChildOfClass("UIPadding")
			if not pad then
				pad = Instance.new("UIPadding")
				pad.Parent = scroll
			end
			if pad.PaddingBottom.Offset < TAIL then
				pad.PaddingBottom = UDim.new(0, TAIL)
			end
		elseif scroll.CanvasSize.Y.Offset > 0 then
			scroll.CanvasSize = UDim2.new(
				scroll.CanvasSize.X.Scale, scroll.CanvasSize.X.Offset,
				scroll.CanvasSize.Y.Scale, scroll.CanvasSize.Y.Offset + TAIL
			)
		end

		attachFade(scroll)
	end

	for _, d in ipairs(screenGui:GetDescendants()) do
		if d:IsA("ScrollingFrame") then polish(d) end
	end
	-- Panels whose scroll is built lazily on first open would otherwise never be reached.
	screenGui.DescendantAdded:Connect(function(d)
		if d:IsA("ScrollingFrame") then task.defer(polish, d) end
	end)
end)()
