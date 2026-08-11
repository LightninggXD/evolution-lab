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

-- ================= helpers =================
local function formatNumber(n)
	n = math.floor(n)
	if n < 1000 then return tostring(n) end
	local suffixes = {"K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp"}
	local mag = 0
	while n >= 1000 and mag < #suffixes do
		n = n / 1000
		mag += 1
	end
	-- THE ROUNDING CARRIES, and the loop above has already stopped looking. 999,999 divides once to
	-- 999.999, which is under the loop's threshold and so is accepted -- and "%.2f" then prints it
	-- as "1000.00", i.e. "1000.00K" for a number one short of a million. The threshold is 999.995
	-- and not 999.95 because this one prints TWO decimals; the carry happens wherever the format
	-- rounds up to 1000, so the constant has to match the precision beside it.
	if n >= 999.995 and mag < #suffixes then
		n = n / 1000
		mag += 1
	end
	return string.format("%.2f%s", n, suffixes[mag])
end

-- `corner` is defined AFTER the UITheme require further down, not here, and that is not tidiness:
-- Lua binds an upvalue where a function is WRITTEN, so a version written above the require would
-- resolve `UITheme` to a nil global and blow up on the first corner the HUD draws. Same trap the
-- ZoneBuilder forward-declarations exist for.

local function stroke(parent, thickness, color)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 2
	s.Color = color or Color3.fromRGB(255,255,255)
	s.Transparency = 0.4
	s.Parent = parent
	return s
end

local function gradient(parent, colorSequence, rotation)
	local g = Instance.new("UIGradient")
	g.Color = colorSequence
	g.Rotation = rotation or 90
	g.Parent = parent
	return g
end

-- ================= shared design system (ReplicatedStorage.Modules.UITheme) =================
local UITheme = require(RS.Modules.UITheme)

-- THROUGH THE SHAPE SCALE (10.18). This helper draws most of the HUD's corners and it used to take
-- whatever number the call site typed, which is how the interface came to speak in ten different
-- radii that differ by two pixels each. `SnapRadius` rounds to the nearest named step and leaves
-- pills and deliberately-large panel corners alone, so no call site had to change.
local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UITheme.SnapRadius(radius or UITheme.Radius.Card)
	c.Parent = parent
	return c
end

local OUTLINE_COLOR = UITheme.Color.Outline
local DISPLAY_FONT = UITheme.Font.Display
-- LIGHT, AND THE ONE PLACE IT HAS TO CHANGE. Every panel in the game reads this one value --
-- Daily, Zones, Journal, Rebirth, Pets, Fusion, Inventory, Character, Shop, Season -- so the whole
-- UI moves together or not at all. It started at rgb(48,42,72), which was near enough to black
-- that the panels read as a debug overlay dropped on a bright cartoon world; rgb(92,86,128) was a
-- step and still read dark.
--
-- THE WHITE TEXT SURVIVES ON A LIGHT SHELL BECAUSE OF THE OUTLINE, not because of the fill. Every
-- display label in the kit is white with a 4px near-black stroke (Color.Outline, rgb(26,18,36)),
-- and that stroke is what carries it -- which is exactly how the reference games put white text on
-- cream panels. The gradient helps too: GradientFor lifts the top stop to rgb(244,243,251) and
-- drops the bottom to rgb(163,160,176), so the panel has a lit top and a shaded foot rather than
-- one flat wash.
local PANEL_SHELL = Color3.fromRGB(226, 222, 245)

-- Roblox's own TextLabel default. A label still carrying it never picked a colour -- see themeLabel.

-- Pet rows sit one step lighter than the panel shell. The tier colour goes on a stripe rather
-- than the whole card because every PetTierColor is pale (luminance 0.61-0.86 -- Normal is
-- rgb(220,220,220)), and a pale card cannot carry the white outlined display text.
-- Moves WITH the shell above -- and now moves the OTHER WAY. It was "one step lighter" while the
-- panel was dark; on a light panel a lighter row is invisible against it, so the relationship
-- inverts and the row becomes one step darker. Still well above the outline, so the white row text
-- keeps its contrast.
local PET_ROW_SHELL = Color3.fromRGB(178, 172, 208)

local function shade(c, amt)
	return UITheme.Shade(c, amt)
end

local function gradientForColor(baseColor)
	return UITheme.GradientFor(baseColor)
end

-- Bright rim painted on whatever is actionable right now -- the one "come here" signal, shared
-- by the Daily board and the Stage Mastery list. Declared up here with the other constants
-- because both readers are functions defined further down, and a `local` introduced after them
-- would resolve to a nil global inside those closures rather than to this value.
local READY_RIM = shade(UITheme.Color.Green, 0.5)

-- Every readable label: display font + thick dark outline + autosized (never a fixed 11-13px).
local function themeLabel(label, maxSize, color)
	if not (label:IsA("TextLabel") or label:IsA("TextButton") or label:IsA("TextBox")) then
		return label
	end
	if label:GetAttribute("Themed") then
		return label
	end
	label:SetAttribute("Themed", true)
	label.Font = DISPLAY_FONT
	label.TextStrokeTransparency = 1
	if color then
		label.TextColor3 = color
	else
		-- A label that never picked a colour still carries Roblox's near-black default, and
		-- OutlineText below wraps it in a dark stroke -- dark on dark, which is how every panel
		-- title, the pet/zone row names and the toast message ended up unreadable.
		--
		-- This used to test `label.TextColor3 == ROBLOX_DEFAULT_TEXT` and that comparison is
		-- ALWAYS false: the engine's default is a different float from the one Color3.fromRGB
		-- computes for the same 27,42,53, so the branch never ran and the bug was never actually
		-- fixed. Luminance is the honest test, and every colour this UI sets on purpose is bright.
		local c = label.TextColor3
		if 0.299 * c.R + 0.587 * c.G + 0.114 * c.B < 0.35 then
			label.TextColor3 = UITheme.Color.White
		end
	end
	if not label:FindFirstChildOfClass("UIStroke") then
		UITheme.OutlineText(label, 4) -- matches UITheme's own default; see the note there
	end
	if not label:FindFirstChildOfClass("UITextSizeConstraint") then
		local maxT = maxSize
		if not maxT then
			local h = label.Size.Y.Offset
			if h <= 0 then h = 26 end
			maxT = math.clamp(math.floor(h * 0.85), 14, 30)
		end
		UITheme.AutoSize(label, math.min(14, maxT), maxT)
	end
	return label
end

--[[
	HARD INVARIANT (this is the bug that started the redesign): the gloss sheen must never
	paint over content. Content children of a themed surface are pushed to Shell+3, strictly
	above the gloss at Shell+1. Nested surfaces keep their own relative stacking via `delta`.
]]
local function liftChildren(inst)
	local baseZ = inst.ZIndex
	local function lift(child)
		if not child:IsA("GuiObject") then return end
		if child.Name == "Gloss" or child.Name == "Shadow" then return end
		local target = baseZ + UITheme.Z.Content
		if child.ZIndex >= target then return end
		local delta = target - child.ZIndex
		child.ZIndex = target
		for _, d in ipairs(child:GetDescendants()) do
			if d:IsA("GuiObject") then
				d.ZIndex = d.ZIndex + delta
			end
		end
	end
	for _, child in ipairs(inst:GetChildren()) do
		lift(child)
	end
	inst.ChildAdded:Connect(lift)
end

--[[
	Chunky glossy surface applied to an EXISTING instance (the ~30 legacy call sites).
	Thick dark outline + moulded vertical gradient + hard bottom lip (drop shadow that is
	safe inside UIListLayout/UIGridLayout parents) + a FAINT sheen that can never cover text.
	Returns the UIStroke, same as the old helper.
]]
local function styleCard(inst, baseColor, radius, thickness)
	baseColor = baseColor or UITheme.Color.Blue
	local cornerRadius = (typeof(radius) == "UDim") and radius or UDim.new(0, radius or 16)

	inst.BackgroundColor3 = baseColor
	inst.BackgroundTransparency = 0
	inst.BorderSizePixel = 0
	inst:SetAttribute("BaseColor", baseColor)
	corner(inst, cornerRadius)

	-- 5 to match UITheme.applyShell. These two functions build the SAME object by two routes --
	-- anything constructed here has to look identical to anything constructed there, or the HUD ends
	-- up with two button styles on one screen.
	-- ...and through the same stroke scale as `applyShell` (10.18), for the reason the comment above
	-- already gives: these two routes must produce the same object. Snapping in one and not the other
	-- would have been a new way for them to diverge.
	local strokeInst = Instance.new("UIStroke")
	strokeInst.Thickness = UITheme.SnapStroke(thickness or UITheme.Stroke.Heavy)
	strokeInst.Color = OUTLINE_COLOR
	strokeInst.Transparency = 0
	strokeInst.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	strokeInst.LineJoinMode = Enum.LineJoinMode.Round
	strokeInst.Parent = inst

	local grad = Instance.new("UIGradient")
	grad.Name = "Gradient"
	grad.Rotation = 90
	grad.Color = UITheme.GradientFor(baseColor)
	grad.Parent = inst

	-- NO BOTTOM LIP. It was a full-width 6px bar carrying the shell's full corner radius, which is
	-- wider than the shell is at the height it sat at -- so it stuck out of both bottom corners, and
	-- out of a circular shell (the Journal discs) badly. It is the "ugly line at the bottom of the
	-- button" in the 2026-08-11 report. Removed in UITheme.addShadow at the same time; these two
	-- functions build the SAME object by two routes and must not diverge.

	-- The sheen, with UITheme.addGloss's geometry -- see the long note there for why it is inset by
	-- the shell's own corner radius rather than clipped. Same two cases, same numbers.
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.BackgroundColor3 = UITheme.Color.White
	gloss.BackgroundTransparency = 0.78 -- invariant: >= 0.72 (mirrors UITheme.addGloss)
	gloss.BorderSizePixel = 0
	gloss.AnchorPoint = Vector2.new(0.5, 0)
	gloss.ZIndex = inst.ZIndex + UITheme.Z.Gloss
	if cornerRadius.Scale >= 0.5 then
		gloss.Size = UDim2.new(0.56, 0, 0.26, 0)
		gloss.Position = UDim2.new(0.5, 0, 0.10, 0)
		corner(gloss, UDim.new(1, 0))
	else
		local pad = cornerRadius.Offset + 4
		gloss.Size = UDim2.new(1, -pad * 2, 0.34, 0)
		gloss.Position = UDim2.new(0.5, 0, 0, 5)
		corner(gloss, UDim.new(0, math.max(cornerRadius.Offset - 3, 4)))
	end
	local glossGrad = gradient(gloss, ColorSequence.new(UITheme.Color.White), 90)
	glossGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.62),
		NumberSequenceKeypoint.new(0.7, 0.94),
		NumberSequenceKeypoint.new(1, 1),
	})
	gloss.Parent = inst

	liftChildren(inst)
	return strokeInst
end

local function styleButton(btn, baseColor, radius, thickness)
	btn.AutoButtonColor = false
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextStrokeTransparency = 1

	-- ===== EVERY ACTION BUTTON IN THE GAME LOST SIX PIXELS, IN ONE PLACE =====
	--
	-- Asked for as "the buttons are too big". Done here rather than at the ~25 sites that author
	-- one, because a height typed in 25 places drifts the moment somebody writes the 26th -- which
	-- is the same reasoning that put the egg panel's two action buttons into a list layout below.
	--
	-- KEYED ON THE EXACT AUTHORED HEIGHT, NOT A SCALE FACTOR. 50 is the primary action on a panel
	-- and 46 is everything else; they become 44 and 40, and the gap between the two tiers survives
	-- so the hierarchy still reads. Everything else in this file is sized against something other
	-- than "an action button" -- the close X is 42, a tier chip is 34, the Robux hero cards are 60+
	-- -- and a blanket multiplier would drag every one of them off its own grid. Anything not one
	-- of those two numbers comes out exactly as it was authored.
	--
	-- A Y.Scale term means the parent owns the height, so those are left alone too.
	-- Mirrored in UITheme.Button, which is the other way a button in this game gets built.
	do
		local h = btn.Size.Y.Offset
		if btn.Size.Y.Scale == 0 and (h == 50 or h == 46) then
			btn.Size = UDim2.new(btn.Size.X.Scale, btn.Size.X.Offset, 0, h == 50 and 44 or 40)
		end
	end

	local strokeInst = styleCard(btn, baseColor, radius, thickness)

	if btn:IsA("TextButton") then
		-- A TextButton's own text draws at the button's ZIndex, i.e. UNDER the gloss. Mirror it
		-- into a child label above the gloss so `btn.Text = ...` keeps working at every call site.
		local proxy = Instance.new("TextLabel")
		proxy.Name = "Label"
		proxy.BackgroundTransparency = 1
		proxy.Size = UDim2.new(1, -14, 1, -10)
		proxy.Position = UDim2.new(0.5, 0, 0.5, 0)
		proxy.AnchorPoint = Vector2.new(0.5, 0.5)
		proxy.TextColor3 = btn.TextColor3
		proxy.TextWrapped = true
		proxy.Text = btn.Text
		proxy.ZIndex = btn.ZIndex + UITheme.Z.Content
		proxy.Parent = btn
		themeLabel(proxy, 24)
		btn.TextTransparency = 1
		btn:GetPropertyChangedSignal("Text"):Connect(function()
			proxy.Text = btn.Text
		end)
		btn:GetPropertyChangedSignal("TextColor3"):Connect(function()
			proxy.TextColor3 = btn.TextColor3
		end)

		-- PRESS FEEDBACK THAT SURVIVES A LAYOUT.
		--
		-- The sink was `btn.Position = resting + 3px`, and a UIListLayout or UIGridLayout parent
		-- rewrites Position on every layout pass -- so it was reverted before it could be seen. Every
		-- button inside a list was silently dead on click: the bottom-right quick row, the Pets
		-- action row, the Pets/Potions tabs, the Season track. AutoButtonColor is off too, so there
		-- was no fallback tint either -- half the game's buttons simply did not respond.
		--
		-- A UIScale is not a layout property, so nothing overwrites it. Squashing to 0.96 reads as
		-- the same push as a 3px sink and works identically in a list, in a grid and free-positioned.
		-- The lip that used to shrink from 6px to 3px alongside the squash is gone (see styleCard),
		-- so the UIScale is the whole of the press now. It was always the part that actually read
		-- as a press -- and unlike the old sibling shadow it scales WITH the button, which is why
		-- pressing no longer makes a dark edge pop out around the shell.
		local squash = btn:FindFirstChildOfClass("UIScale")
		if not squash then
			squash = Instance.new("UIScale")
			squash.Parent = btn
		end
		local pressed = false
		btn.MouseButton1Down:Connect(function()
			if pressed then return end
			pressed = true
			squash.Scale = 0.96
		end)
		local function release()
			if not pressed then return end
			pressed = false
			squash.Scale = 1
		end
		btn.MouseButton1Up:Connect(release)
		btn.MouseLeave:Connect(release)
	end

	return strokeInst
end

-- Re-tint an already-styled button/card at runtime (keeps the gradient in sync with color swaps).
local function setButtonColor(btn, baseColor)
	UITheme.SetColor(btn, baseColor)
end

-- ================= root gui =================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "EvolutionLabUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

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
evolveFrame.Position = UDim2.new(0.5, 0, 1, -22)
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

-- ===== Bottom-left: currency stack (no panel, just big outlined numbers) =====
local currencyStack = Instance.new("Frame")
currencyStack.Name = "CurrencyStack"
currencyStack.Size = UDim2.new(0, 250, 0, 140)
currencyStack.Position = UDim2.new(0, 20, 1, -22)
currencyStack.AnchorPoint = Vector2.new(0, 1)
currencyStack.BackgroundTransparency = 1
currencyStack.ZIndex = UITheme.Z.Content
currencyStack.Parent = screenGui

local currencyLayout = Instance.new("UIListLayout")
currencyLayout.SortOrder = Enum.SortOrder.LayoutOrder
currencyLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
currencyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
currencyLayout.Padding = UDim.new(0, 2)
currencyLayout.Parent = currencyStack

local dnaPill = UITheme.Pill(currencyStack, {
	name = "DNAPill", icon = "🧬", text = "0", layoutOrder = 1,
	size = UDim2.new(1, 0, 0, 46), maxTextSize = 34,
})
local diamondPill = UITheme.Pill(currencyStack, {
	name = "DiamondPill", icon = "💎", text = "0", layoutOrder = 2,
	size = UDim2.new(1, 0, 0, 40), maxTextSize = 30,
})
local shardPill = UITheme.Pill(currencyStack, {
	name = "ShardPill", icon = "🌟", text = "0", layoutOrder = 3,
	size = UDim2.new(1, 0, 0, 40), maxTextSize = 30,
})
-- (the three pills' .Value labels used to be cached here and were never read again -- see the note
-- on the Season XP bar: this chunk is at Luau's 200-register limit and every unused local counts)

-- ===== Upgrades panel (centre screen, opened by the Shop tile) =====
local shopFrame = Instance.new("Frame")
shopFrame.Name = "ShopFrame"
shopFrame.Size = UDim2.new(0, 900, 0, 352)
shopFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
shopFrame.AnchorPoint = Vector2.new(0.5, 0.5)
shopFrame.ZIndex = 20
shopFrame.Visible = false
shopFrame.Parent = screenGui
styleCard(shopFrame, PANEL_SHELL, UDim.new(0, 22), 5)

UITheme.Label(shopFrame, {
	name = "ShopTitle",
	text = "🛒 Upgrades",
	size = UDim2.new(0, 420, 0, 42),
	position = UDim2.new(0, 24, 0, 10),
	xAlign = "Left",
	maxTextSize = 34,
	zIndex = shopFrame.ZIndex + UITheme.Z.Content,
})

local shopCloseButton = UITheme.Button(shopFrame, {
	name = "ShopClose",
	text = "X",
	color = UITheme.Color.Red,
	size = UDim2.new(0, 44, 0, 44),
	position = UDim2.new(1, -16, 0, 10),
	anchorPoint = Vector2.new(1, 0),
	radius = 12,
	maxTextSize = 30,
	zIndex = shopFrame.ZIndex + UITheme.Z.Badge,
})
shopCloseButton.MouseButton1Click:Connect(function()
	shopFrame.Visible = false
end)

local upgradeRow = Instance.new("Frame")
upgradeRow.Name = "UpgradeRow"
upgradeRow.Size = UDim2.new(1, -32, 0, 140)
upgradeRow.Position = UDim2.new(0, 16, 0, 58)
upgradeRow.BackgroundTransparency = 1
upgradeRow.Parent = shopFrame

local shopLayout = Instance.new("UIListLayout")
shopLayout.FillDirection = Enum.FillDirection.Horizontal
shopLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
shopLayout.Padding = UDim.new(0, 12)
shopLayout.SortOrder = Enum.SortOrder.LayoutOrder
shopLayout.Parent = upgradeRow

-- Mutation Chance came off the shop row. Only this list changed: `GameConfig.Upgrades.Mutation`
-- and `DNAService.GetMutationChancePerRoll` are both left alone on purpose. Anyone who already
-- bought levels keeps them, and the base rate does not depend on the upgrade -- the formula is
-- `clamp(2 + level * 1.5, 0, 60)` percent on a roll every ten seconds, so mutations carry on at 2%
-- with nothing bought. Deleting the config entry instead would have zeroed a stat that is still
-- read on the server and silently changed the income of every existing save.
-- Auto Collect came off too, and for the reason the owner gave: there is nothing on the ground to
-- collect, so the tile was selling a mechanic the game does not have. Same treatment as Mutation --
-- only this list changed. `DNAService.GetAutoCollectAmount` returns 0 at level 0, so a save that
-- never bought it is unaffected, and one that did keeps its passive income.
local upgradeOrder = { "Speed", "Income", "Luck" }
local upgradeButtons = {}

for i, key in ipairs(upgradeOrder) do
	local def = GameConfig.Upgrades[key]
	local btn = Instance.new("TextButton")
	btn.Name = key .. "Button"
	btn.LayoutOrder = i
	btn.Size = UDim2.new(0, 164, 1, 0)
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
	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "Icon"
	iconLabel.Size = UDim2.new(1, -12, 0, 44)
	iconLabel.Position = UDim2.new(0.5, 0, 0, 8)
	iconLabel.AnchorPoint = Vector2.new(0.5, 0)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Text = def.emoji
	iconLabel.ZIndex = btn.ZIndex + UITheme.Z.Content
	iconLabel.Parent = btn
	themeLabel(iconLabel, 40, Color3.fromRGB(255, 255, 255))

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, -12, 0, 30)
	titleLabel.Position = UDim2.new(0.5, 0, 0, 54)
	titleLabel.AnchorPoint = Vector2.new(0.5, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.TextWrapped = true
	titleLabel.Text = def.displayName
	titleLabel.ZIndex = btn.ZIndex + UITheme.Z.Content
	titleLabel.Parent = btn
	themeLabel(titleLabel, 22, Color3.fromRGB(255, 255, 255))

	local levelBadge = Instance.new("Frame")
	levelBadge.Name = "LevelBadge"
	levelBadge.Size = UDim2.new(0, 58, 0, 26)
	levelBadge.Position = UDim2.new(1, -6, 0, 6)
	levelBadge.AnchorPoint = Vector2.new(1, 0)
	-- Z.Badge, so it clears the gloss the shell draws over its own children
	levelBadge.ZIndex = btn.ZIndex + UITheme.Z.Badge
	levelBadge.Parent = btn
	styleCard(levelBadge, UITheme.Shade(UITheme.Color.Outline, 0.22), UDim.new(1, 0), 2.5)

	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "LevelLabel"
	levelLabel.Size = UDim2.new(1, -8, 1, -6)
	levelLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	levelLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text = "Lv 0"
	levelLabel.ZIndex = levelBadge.ZIndex + UITheme.Z.Content
	levelLabel.Parent = levelBadge
	themeLabel(levelLabel, 18, Color3.fromRGB(255, 255, 255))

	local costPill = Instance.new("Frame")
	costPill.Name = "CostPill"
	costPill.Size = UDim2.new(1, -20, 0, 32)
	costPill.Position = UDim2.new(0.5, 0, 1, -8)
	costPill.AnchorPoint = Vector2.new(0.5, 1)
	costPill.ZIndex = btn.ZIndex + UITheme.Z.Badge
	costPill.Parent = btn
	styleCard(costPill, UITheme.Shade(UITheme.Color.Outline, 0.22), UDim.new(1, 0), 2.5)

	local costLabel = Instance.new("TextLabel")
	costLabel.Name = "CostLabel"
	costLabel.Size = UDim2.new(1, -10, 1, -6)
	costLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	costLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	costLabel.BackgroundTransparency = 1
	costLabel.Text = "\u{1F9EC} " .. def.baseCost
	costLabel.ZIndex = costPill.ZIndex + UITheme.Z.Content
	costLabel.Parent = costPill
	themeLabel(costLabel, 22, UITheme.Color.Cream)

	btn.MouseButton1Click:Connect(function()
		Remotes.BuyUpgrade:FireServer(key)
	end)

	upgradeButtons[key] = { button = btn, levelLabel = levelLabel, costLabel = costLabel, badge = levelBadge }
end

-- ===== Diamond Upgrades row (bought with premium Diamonds, not DNA) =====
local diamondRow = Instance.new("Frame")
diamondRow.Name = "DiamondRow"
diamondRow.Size = UDim2.new(1, -32, 0, 130)
diamondRow.Position = UDim2.new(0, 16, 0, 206)
diamondRow.BackgroundTransparency = 1
diamondRow.Parent = shopFrame

local diamondLayout = Instance.new("UIListLayout")
diamondLayout.FillDirection = Enum.FillDirection.Horizontal
diamondLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
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
	levelLabel.Size = UDim2.new(1, -12, 0, 24)
	levelLabel.Position = UDim2.new(0, 6, 1, -56)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text = "Level 0"
	levelLabel.Parent = btn
	themeLabel(levelLabel, 19, Color3.fromRGB(255, 255, 255))

	local costLabel = Instance.new("TextLabel")
	costLabel.Name = "CostLabel"
	costLabel.Size = UDim2.new(1, -12, 0, 30)
	costLabel.Position = UDim2.new(0, 6, 1, -38)
	costLabel.BackgroundTransparency = 1
	costLabel.Text = "💎 " .. def.baseCost
	costLabel.Parent = btn
	themeLabel(costLabel, 24, UITheme.Color.Cream)

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
local RIGHT_COUNT = 9
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
		opts.position = UDim2.new(0, 20, 0, TILE_START_Y + (order - 1) * TILE_PITCH)
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
	local btn = UITheme.Button(panel, {
		name = "Close",
		text = "X",
		color = UITheme.Color.Red,
		size = UDim2.new(0, 42, 0, 42),
		position = UDim2.new(1, -14, 0, 10),
		anchorPoint = Vector2.new(1, 0),
		radius = 12,
		maxTextSize = 28,
		zIndex = panel.ZIndex + UITheme.Z.Badge,
	})
	btn.MouseButton1Click:Connect(function()
		animatePanel(panel, false)
	end)
	return btn
end

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

local zonesPanelTitle = Instance.new("TextLabel")
zonesPanelTitle.Size = UDim2.new(1, -80, 0, 40)
zonesPanelTitle.Position = UDim2.new(0, 18, 0, 10)
zonesPanelTitle.BackgroundTransparency = 1
zonesPanelTitle.TextXAlignment = Enum.TextXAlignment.Left
zonesPanelTitle.Text = "🗺️ Zones"
zonesPanelTitle.Parent = zonesPanel
themeLabel(zonesPanelTitle, 32)

local zonesScroll = Instance.new("ScrollingFrame")
zonesScroll.Name = "ZonesScroll"
zonesScroll.Size = UDim2.new(1, -28, 1, -70)
zonesScroll.Position = UDim2.new(0, 14, 0, 58)
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
	styleCard(row, zone.accentColor, UDim.new(0, 14), 4)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(0.62, 0, 0, 30)
	nameLabel.Position = UDim2.new(0, 12, 0, 6)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = zone.emoji .. " " .. zone.name
	nameLabel.Parent = row
	themeLabel(nameLabel, 24)
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
	themeLabel(statusLabel, 17, UITheme.Color.Cream)

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

local masteryTitle = Instance.new("TextLabel")
masteryTitle.Name = "TitleLabel"
masteryTitle.Size = UDim2.new(1, -80, 0, 40)
masteryTitle.Position = UDim2.new(0, 18, 0, 10)
masteryTitle.BackgroundTransparency = 1
masteryTitle.TextXAlignment = Enum.TextXAlignment.Left
masteryTitle.Text = "⭐ Stage Mastery"
masteryTitle.Parent = masteryPanel
themeLabel(masteryTitle, 32)
-- 9.9: the leading glyph becomes a drawing at the title's left edge, or stays a glyph if
-- there is no art for it. One line, and it moves nothing else on the panel.
UITheme.IconifyLabel(masteryTitle)

-- running total, so the player can see what the whole collection is currently worth without
-- adding up twenty rows themselves
local masterySummaryCard = Instance.new("Frame")
masterySummaryCard.Name = "SummaryCard"
masterySummaryCard.Size = UDim2.new(1, -36, 0, 40)
masterySummaryCard.Position = UDim2.new(0, 18, 0, 54)
masterySummaryCard.Parent = masteryPanel
styleCard(masterySummaryCard, UITheme.Color.Gold, UDim.new(0, 12), 3)

local masterySummaryLabel = Instance.new("TextLabel")
masterySummaryLabel.Name = "SummaryLabel"
masterySummaryLabel.Size = UDim2.new(1, -24, 1, -8)
masterySummaryLabel.Position = UDim2.new(0, 12, 0, 2)
masterySummaryLabel.BackgroundTransparency = 1
masterySummaryLabel.TextXAlignment = Enum.TextXAlignment.Left
masterySummaryLabel.Text = "0 / " .. #GameConfig.Stages .. " mastered"
masterySummaryLabel.Parent = masterySummaryCard
themeLabel(masterySummaryLabel, 20)

local masteryScroll = Instance.new("ScrollingFrame")
masteryScroll.Name = "MasteryScroll"
masteryScroll.Size = UDim2.new(1, -28, 1, -114)
masteryScroll.Position = UDim2.new(0, 14, 0, 102)
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

	masteryRows[i] = { row = row, statusLabel = statusLabel, buyButton = buyButton, stroke = rowStroke }
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
petsPanel.Size = UDim2.new(0, 772, 0, 524)
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

-- The title sits ON the top-left corner, half outside the board, the way the reference does it.
-- Nothing clips here, so a negative Y simply draws over the world behind the panel.
local petsPanelTitle = Instance.new("TextLabel")
petsPanelTitle.Name = "TitleLabel"
petsPanelTitle.Size = UDim2.new(0, 420, 0, 54)
petsPanelTitle.Position = UDim2.new(0, 16, 0, -30)
petsPanelTitle.BackgroundTransparency = 1
petsPanelTitle.TextXAlignment = Enum.TextXAlignment.Left
petsPanelTitle.ZIndex = petsPanel.ZIndex + UITheme.Z.Badge
petsPanelTitle.Text = "🐾 Pets!"
petsPanelTitle.Parent = petsPanel
themeLabel(petsPanelTitle, 44)
-- 9.9: the leading glyph becomes a drawing at the title's left edge, or stays a glyph if
-- there is no art for it. One line, and it moves nothing else on the panel.
UITheme.IconifyLabel(petsPanelTitle)

-- Bulk actions. A collection this size is not managed one row at a time: by the time a player is
-- three zones in they own dozens of pets, and "which three are my best" is a question the game
-- should answer, not something to solve by scrolling and comparing numbers by eye.
-- Fusion is NOT one of them: it has exactly one door, the Pet Fusion Lab counter in the world (see
-- the ShopPanel handler at the bottom of this script). A shortcut here made the lab pointless.
--
-- WHY THIS BLOCK IS WRAPPED IN `do ... end`, AND WHY WHAT ESCAPES IT GOES IN ONE TABLE:
-- this file's top level is a single Luau function, and Luau gives a function 200 registers. It
-- sits at ~190 named top-level locals. Seven more -- a frame, a layout, a builder fn, three
-- buttons and a forward declaration -- pushed it over, and the WHOLE SCRIPT stopped compiling:
-- not a broken panel, no HUD at all, every side button gone at once. Locals declared inside a
-- `do` block release their registers at `end`, so a block costs nothing lasting. Anything that
-- must outlive it goes in `hudRefs` -- one register no matter how many entries it holds. New UI
-- follows this shape, or lives in its own module.
local hudRefs = {}

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
	stack.Size = UDim2.new(0, 250, 0, 250)
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

	local KINDS = { "dna", "xp", "luck" }
	local LABEL = { dna = "DNA", xp = "XP" }
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

		local card = Instance.new("Frame")
		card.Name = kind .. "Timer"
		card.Size = UDim2.new(0, 244, 0, 48)
		card.LayoutOrder = order
		card.BackgroundColor3 = Color3.fromRGB(30, 34, 48)
		card.Visible = false
		card.ZIndex = UITheme.Z.Content + 1
		card.Parent = stack
		styleCard(card, sample.color, UDim.new(0, 12), 3)

		local bottle = Instance.new("TextLabel")
		bottle.Name = "Bottle"
		bottle.Size = UDim2.new(0, 36, 0, 36)
		bottle.Position = UDim2.new(0, 6, 0, 6)
		bottle.BackgroundColor3 = sample.color
		bottle.Text = sample.emoji
		bottle.ZIndex = card.ZIndex + 1
		bottle.Parent = card
		corner(bottle, UDim.new(0.5, 0))
		themeLabel(bottle, 20)

		local effect = Instance.new("TextLabel")
		effect.Name = "Effect"
		effect.Size = UDim2.new(1, -122, 0, 20)
		effect.Position = UDim2.new(0, 50, 0, 4)
		effect.BackgroundTransparency = 1
		effect.TextXAlignment = Enum.TextXAlignment.Left
		effect.ZIndex = card.ZIndex + 1
		effect.Parent = card
		themeLabel(effect, 17)

		local clock = Instance.new("TextLabel")
		clock.Name = "Clock"
		clock.Size = UDim2.new(0, 66, 0, 20)
		clock.Position = UDim2.new(1, -72, 0, 4)
		clock.BackgroundTransparency = 1
		clock.TextXAlignment = Enum.TextXAlignment.Right
		clock.ZIndex = card.ZIndex + 1
		clock.Parent = card
		themeLabel(clock, 17)

		local track = Instance.new("Frame")
		track.Name = "Track"
		track.Size = UDim2.new(1, -62, 0, 8)
		track.Position = UDim2.new(0, 50, 1, -15)
		track.BackgroundColor3 = Color3.fromRGB(16, 18, 26)
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
	-- THE PERMANENT HALF OF THE STRIP (6.4)
	-- ============================================================================
	-- Roadmap 6.4 asks for "pass icons and countdowns". THERE IS NO COUNTDOWN TO GIVE THEM: all nine
	-- passes are permanent, and a clock on a number that never falls is worse than no clock at all --
	-- it invites the player to wonder when the thing they bought forever runs out. So the strip is
	-- split the way the boosts themselves are. A potion is a CARD with a bar and a clock because it is
	-- running out; a pass is a CHIP because it is not, and the chip's whole message is "this is on".
	--
	-- Built once and shown or hidden, exactly like the three potion rows above and for the same
	-- reason: ownership changes at most a handful of times in a session, and rebuilding nine frames
	-- four times a second to say the same thing would be the most expensive idle loop in the HUD.
	--
	-- A GRID rather than a row, because nine 34 px chips do not fit across 244 px and a grid wraps by
	-- itself -- a tenth pass costs nothing here. Invisible children are skipped by the layout, so the
	-- rows close up on their own as passes are hidden.
	local PASS_CELL, PASS_PAD, PASS_COLS = 34, 5, 6
	local passChips = {}

	local passCard = Instance.new("Frame")
	passCard.Name = "PassBoosts"
	passCard.Size = UDim2.new(0, 244, 0, PASS_CELL + 8)
	passCard.LayoutOrder = 0                  -- above the potion cards; the stack aligns to the bottom
	passCard.BackgroundColor3 = Color3.fromRGB(30, 34, 48)
	passCard.Visible = false
	passCard.ZIndex = UITheme.Z.Content + 1
	passCard.Parent = stack
	styleCard(passCard, UITheme.Color.Gold, UDim.new(0, 12), 3)

	local passGrid = Instance.new("Frame")
	passGrid.Name = "Chips"
	passGrid.Size = UDim2.new(1, -12, 1, -8)
	passGrid.Position = UDim2.new(0, 6, 0, 4)
	passGrid.BackgroundTransparency = 1
	passGrid.ZIndex = passCard.ZIndex + 1
	passGrid.Parent = passCard

	local passLayout = Instance.new("UIGridLayout")
	passLayout.CellSize = UDim2.new(0, PASS_CELL, 0, PASS_CELL)
	passLayout.CellPadding = UDim2.new(0, PASS_PAD, 0, PASS_PAD)
	passLayout.SortOrder = Enum.SortOrder.LayoutOrder
	passLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	passLayout.Parent = passGrid

	for order, pass in ipairs(GameConfig.GamePasses) do
		local chip = Instance.new("TextLabel")
		chip.Name = pass.key
		chip.LayoutOrder = order
		-- DARK DISC ON A GOLD CARD, and the first build got this backwards. `styleCard` paints the
		-- whole card in the colour it is handed, so gold chips on a gold card came out as pale marks
		-- that had to be hunted for. This is the potion row inverted -- there a coloured disc sits on a
		-- dark card -- and the inversion is the point: one glance says these two rows are different
		-- kinds of thing, a permanent one and a running-out one.
		chip.BackgroundColor3 = UITheme.Color.Outline
		chip.Text = pass.emoji
		chip.Visible = false
		chip.ZIndex = passGrid.ZIndex + 1
		chip.Parent = passGrid
		corner(chip, UDim.new(0.5, 0))
		themeLabel(chip, 19)
		-- THE CHIP IS THE DISC AND THE ICON AT ONCE, so 9.9 goes INSIDE it rather than replacing it:
		-- the dark disc is what makes these read as permanent against the potion row's coloured
		-- cards (see the note above), and an ImageLabel in its place would lose that. The glyph is
		-- blanked and a drawing inset into the same box; a pass with no art keeps its emoji.
		if UITheme.HasIcon(pass.emoji) then
			chip.Text = ""
			UITheme.IconSlot(chip, {
				name = "Art", icon = pass.emoji,
				size = UDim2.new(0.72, 0, 0.72, 0), position = UDim2.new(0.5, 0, 0.5, 0),
				anchorPoint = Vector2.new(0.5, 0.5), zIndex = chip.ZIndex + 1,
			})
		end
		passChips[#passChips + 1] = { key = pass.key, frame = chip }
	end

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

	local eventCard = Instance.new("Frame")
	eventCard.Name = "EventBoost"
	eventCard.Size = UDim2.new(0, 244, 0, 48)
	eventCard.LayoutOrder = -1                -- above the pass chips, which are 0
	eventCard.BackgroundColor3 = Color3.fromRGB(30, 34, 48)
	eventCard.Visible = false
	eventCard.ZIndex = UITheme.Z.Content + 1
	eventCard.Parent = stack
	styleCard(eventCard, UITheme.Color.Coral, UDim.new(0, 12), 3)

	local eventBadge = Instance.new("TextLabel")
	eventBadge.Name = "Badge"
	eventBadge.Size = UDim2.new(0, 36, 0, 36)
	eventBadge.Position = UDim2.new(0, 6, 0, 6)
	eventBadge.BackgroundColor3 = UITheme.Color.Coral
	eventBadge.Text = "\u{1F525}"
	eventBadge.ZIndex = eventCard.ZIndex + 1
	eventBadge.Parent = eventCard
	corner(eventBadge, UDim.new(0.5, 0))
	themeLabel(eventBadge, 20)

	local eventName = Instance.new("TextLabel")
	eventName.Name = "EventName"
	eventName.Size = UDim2.new(1, -132, 0, 20)
	eventName.Position = UDim2.new(0, 50, 0, 4)
	eventName.BackgroundTransparency = 1
	eventName.TextXAlignment = Enum.TextXAlignment.Left
	eventName.ZIndex = eventCard.ZIndex + 1
	eventName.Parent = eventCard
	themeLabel(eventName, 17)

	local eventClock = Instance.new("TextLabel")
	eventClock.Name = "Clock"
	eventClock.Size = UDim2.new(0, 76, 0, 20)
	eventClock.Position = UDim2.new(1, -82, 0, 4)
	eventClock.BackgroundTransparency = 1
	eventClock.TextXAlignment = Enum.TextXAlignment.Right
	eventClock.ZIndex = eventCard.ZIndex + 1
	eventClock.Parent = eventCard

	local eventEffects = Instance.new("TextLabel")
	eventEffects.Name = "Effects"
	eventEffects.Size = UDim2.new(1, -62, 0, 18)
	eventEffects.Position = UDim2.new(0, 50, 1, -20)
	eventEffects.BackgroundTransparency = 1
	eventEffects.TextXAlignment = Enum.TextXAlignment.Left
	eventEffects.ZIndex = eventCard.ZIndex + 1
	eventEffects.Parent = eventCard
	themeLabel(eventEffects, 15)
	themeLabel(eventClock, 17)

	-- x2 stays "x2"; x1.5 becomes "x1.5" rather than taking the thread down. See the note below.
	local function formatMult(m)
		m = tonumber(m) or 1
		if math.abs(m - math.floor(m + 0.5)) < 0.001 then
			return tostring(math.floor(m + 0.5))
		end
		return ("%.1f"):format(m)
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

			-- The pass half. `data.Passes` is recomputed on every load and never trusted from the save
			-- (see PassService), so a chip here is a live ownership answer rather than a stale one.
			local passes = currentData and currentData.Passes
			local owned = 0
			for _, chip in ipairs(passChips) do
				local on = passes and passes[chip.key] == true
				chip.frame.Visible = on
				if on then owned += 1 end
			end
			local used = math.max(1, math.ceil(owned / PASS_COLS))
			passCard.Size = UDim2.new(0, 244, 0, 8 + used * PASS_CELL + (used - 1) * PASS_PAD)
			passCard.Visible = owned > 0

			-- The event half (7.1). Driven off the shared config against the SERVER's clock, not off
			-- the payload's own text, so the seconds fall between publishes instead of jumping every
			-- thirty. Only the first live event is drawn: two at once is possible (a festival can
			-- overlap a weekend) and a second card would push the strip up over the potion rows for
			-- the one player in a hundred who sees it. The clock is the reason to look; the effects
			-- line says what it is worth.
			local live = GameConfig.GetActiveEvents()[1]
			if live then
				local left = live.window.endTs - GameConfig.EventNow()
				eventCard.Visible = true
				eventBadge.Text = live.event.emoji
				eventBadge.BackgroundColor3 = live.event.color
				eventName.Text = live.event.name
				eventClock.Text = GameConfig.FormatDuration(left)
				local bits = {}
				for field, label in pairs({ incomeMult = "DNA", xpMult = "XP", damageMult = "Damage" }) do
					local v = live.event.effects and live.event.effects[field]
					if v then table.insert(bits, ("x%s %s"):format(formatMult(v), label)) end
				end
				local luck = live.event.effects and live.event.effects.luckAdd
				if luck then table.insert(bits, ("+%d%% Luck"):format(math.floor(luck))) end
				table.sort(bits)
				eventEffects.Text = table.concat(bits, "   ")
			else
				eventCard.Visible = false
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
			local tileW = rebirthButton.AbsoluteSize.X
			if tileW > 0 then
				stack.Position = UDim2.new(0, 20 + tileW + 14, 1, -170)
			end
			-- Read fresh every tick rather than captured once: `CurrentCamera` is nil for the first
			-- frames of a join, and the viewport changes when the window is resized.
			local viewportY = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.Y or 720
			local budget = math.max(viewportY - 170 - 121 - 10, 96)
			stack.Size = UDim2.new(0, 250, 0, budget)

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
				-- longest remaining last, so the first potion dropped is the one with most time left
				local order = { passCard, eventCard }
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

	local equipBestButton = actionButton(1, "Equip Best Pets", UITheme.Color.Green)
	local unequipAllButton = actionButton(2, "Unequip All Pets", UITheme.Color.Red)

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

local petsScroll = Instance.new("ScrollingFrame")
petsScroll.Name = "PetsScroll"
-- clear of the title above and the action bar sitting on the bottom edge
petsScroll.Size = UDim2.new(1, -44, 1, -128)
petsScroll.Position = UDim2.new(0, 22, 0, 54)
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
	grid.CellSize = UDim2.new(0, 232, 0, 126)
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

-- Live rigs shown in the pet rows. A row shows the actual creature in a ViewportFrame rather
-- than its emoji: the emoji is the same 🐾 shape for half the roster, and the whole point of 100
-- species is that you can tell them apart. Kept in a list so one RenderStepped can turn them all.
local petPreviewRigs = {}

local function refreshPetsPanel()
	if not currentData then return end
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
	petsPanelTitle.Text = "Pets"

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
		local bonus = GameConfig.GetPetBonus(pet.tier, info.rarity, pet.key, data)
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
		cell.Size = UDim2.new(0, 232, 0, 126)
		cell.ZIndex = petsScroll.ZIndex + UITheme.Z.Content
		cell.Parent = petsScroll
		cell.MouseButton1Click:Connect(function()
			if isEquipped then
				Remotes.UnequipPet:FireServer(pet.id)
			else
				Remotes.EquipPet:FireServer(pet.id)
			end
		end)

		-- the grey card, offset right and down to leave the art its corner
		local card = Instance.new("Frame")
		card.Name = "Card"
		card.Size = UDim2.new(0, 180, 0, 92)
		card.Position = UDim2.new(0, 52, 0, 32)
		card.ZIndex = cell.ZIndex
		card.Parent = cell
		-- rarity rides the rim: it is the one thing the reference has no equivalent for, and a
		-- coloured edge says it without spending a line of the card on the word
		styleCard(card, Color3.fromRGB(226, 228, 236), UDim.new(0, 14), 3).Color =
			isEquipped and Color3.fromRGB(62, 196, 86) or rarity.color

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "PetName"
		nameLabel.Size = UDim2.new(1, -20, 0, 26)
		nameLabel.Position = UDim2.new(0, 10, 0, 5)
		nameLabel.BackgroundTransparency = 1
		nameLabel.ZIndex = card.ZIndex + UITheme.Z.Content
		nameLabel.Text = info.name
		nameLabel.Parent = card
		flatText(themeLabel(nameLabel, 24, Color3.fromRGB(122, 126, 140)))

		local subLabel = Instance.new("TextLabel")
		subLabel.Name = "SubLabel"
		subLabel.Size = UDim2.new(1, -20, 0, 18)
		subLabel.Position = UDim2.new(0, 10, 0, 31)
		subLabel.BackgroundTransparency = 1
		subLabel.RichText = true
		subLabel.ZIndex = card.ZIndex + UITheme.Z.Content
		subLabel.Text = colorTag(rarity.name, shade(rarity.color, -0.35)) .. " · " .. pet.tier
		subLabel.Parent = card
		flatText(themeLabel(subLabel, 16, Color3.fromRGB(150, 154, 168)))

		-- the inset stat bar, the one line the reference's card actually carries
		local statBar = Instance.new("Frame")
		statBar.Name = "StatBar"
		statBar.Size = UDim2.new(1, -20, 0, 34)
		statBar.Position = UDim2.new(0, 10, 0, 51)
		statBar.BackgroundColor3 = Color3.fromRGB(240, 242, 248)
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
		flatText(themeLabel(statLabel, 18, Color3.fromRGB(88, 92, 104)))

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
		if not isEquipped then
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

		-- No per-row Fuse button any more. Fusing is a decision about a GROUP of four identical
		-- pets, not about the one row under the cursor, and a button that silently consumed three
		-- other pets from elsewhere in the list was the least readable thing in this panel. It
		-- lives in the Fusion panel now, which shows what goes in and what comes out.
	end

	-- three to a row, cell 126 tall on 12 of padding
	petsScroll.CanvasSize = UDim2.new(0, 0, 0, math.ceil(#data.Pets / 3) * 138 + 12)
end

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
	local pendingId = nil

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
		pendingId = nil
		shade4.Visible = false
	end

	cancel.MouseButton1Click:Connect(close)
	-- clicking the darkened backdrop cancels, which is what every modal in every game does and what
	-- a player will try first
	shade4.MouseButton1Click:Connect(close)
	confirm.MouseButton1Click:Connect(function()
		local id = pendingId
		close()
		if id and deleteRemote then
			-- a list of one: the server has a single handler for one pet and for many, so there is
			-- no second path here that could drift from the multi-select one
			deleteRemote:FireServer({ id })
		end
	end)

	hudRefs.confirmRelease = function(petId, displayName, rarityName, rarityColor)
		pendingId = petId
		petLine.Text = ("%s  %s"):format(displayName or "Pet",
			colorTag(rarityName or "", rarityColor or UITheme.Color.White))
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

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -80, 0, 38)
	title.Position = UDim2.new(0, 18, 0, 10)
	title.BackgroundTransparency = 1
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "\u{1F9EC} Pet Fusion"
	title.Parent = panel
	themeLabel(title, 28)

	local hint = Instance.new("Frame")
	hint.Size = UDim2.new(1, -28, 0, 44)
	hint.Position = UDim2.new(0, 14, 0, 52)
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
	scroll.Size = UDim2.new(1, -28, 1, -122)
	scroll.Position = UDim2.new(0, 14, 0, 106)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.Parent = panel

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = scroll

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
				g = { key = pet.key, tier = pet.tier, count = 0, firstId = pet.id }
				groups[groupKey] = g
				table.insert(order, g)
			end
			g.count += 1
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
				g.power = GameConfig.GetPetPower({ key = g.key, tier = g.tier }, data)
				g.nextPower = GameConfig.GetPetPower({ key = g.key, tier = g.nextTier }, data)
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
			local pa = GameConfig.GetPetPower({ key = a.key, tier = a.catalystTier }, data)
			local pb = GameConfig.GetPetPower({ key = b.key, tier = b.catalystTier }, data)
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
			local fromBonus = GameConfig.GetPetBonus(g.tier, info.rarity, g.key, data).damageMult
			local toBonus = GameConfig.GetPetBonus(g.catalystTier, info.rarity, g.key, data).damageMult
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
			btn.Text = tokens > 0 and ("USE (%d)"):format(tokens) or "R$ 99"
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

		scroll.CanvasSize = UDim2.new(0, 0, 0, (#ready + shown) * 78 + 40)
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
				setButtonColor(refs.goButton, Color3.fromRGB(80, 80, 90))
			end
		end
	end
end

-- ===== Rebirth panel =====
local rebirthPanel = Instance.new("Frame")
rebirthPanel.Name = "RebirthPanel"
rebirthPanel.Size = UDim2.new(0, 430, 0, 392)
rebirthPanel.Position = PANEL_ANCHOR
rebirthPanel.ZIndex = 20
rebirthPanel.Visible = false
rebirthPanel.Parent = screenGui
styleCard(rebirthPanel, PANEL_SHELL, UDim.new(0, 22), 5)
registerPanel(rebirthPanel)
panelClose(rebirthPanel)

local rebirthTitle = Instance.new("TextLabel")
rebirthTitle.Name = "TitleLabel"
rebirthTitle.Size = UDim2.new(1, -80, 0, 38)
rebirthTitle.Position = UDim2.new(0, 18, 0, 10)
rebirthTitle.BackgroundTransparency = 1
rebirthTitle.TextXAlignment = Enum.TextXAlignment.Left
rebirthTitle.Text = "♻️ Rebirth"
rebirthTitle.Parent = rebirthPanel
themeLabel(rebirthTitle, 28)
-- 9.9: the leading glyph becomes a drawing at the title's left edge, or stays a glyph if
-- there is no art for it. One line, and it moves nothing else on the panel.
UITheme.IconifyLabel(rebirthTitle)

-- the two readouts get real cards rather than bare text on the shell, so the panel has the
-- same stacked-card rhythm as Zones/Pets instead of reading as a dialog box
local rebirthInfoCard = Instance.new("Frame")
rebirthInfoCard.Name = "InfoCard"
rebirthInfoCard.Size = UDim2.new(1, -28, 0, 64)
rebirthInfoCard.Position = UDim2.new(0, 14, 0, 56)
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

local rebirthReqCard = Instance.new("Frame")
rebirthReqCard.Name = "ReqCard"
rebirthReqCard.Size = UDim2.new(1, -28, 0, 176)
rebirthReqCard.Position = UDim2.new(0, 14, 0, 132)
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

local rebirthActionButton = Instance.new("TextButton")
rebirthActionButton.Name = "ActionButton"
rebirthActionButton.Size = UDim2.new(1, -28, 0, 58)
rebirthActionButton.Position = UDim2.new(0, 14, 1, -72)
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
		rebirthReqLabel.Text = string.format(
			"All %d Rebirths complete.\nEverything they paid for is permanent and stays with you.",
			GameConfig.MaxRebirths)
		rebirthActionButton.Text = "ALL REBIRTHS COMPLETE"
		setButtonColor(rebirthActionButton, UITheme.Color.Locked)
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
rewardPanel.Size = UDim2.new(0, 700, 0, 536)
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

local rewardTitle = Instance.new("TextLabel")
rewardTitle.Name = "TitleLabel"
rewardTitle.Size = UDim2.new(1, -90, 0, 44)
rewardTitle.Position = UDim2.new(0, 22, 0, 12)
rewardTitle.BackgroundTransparency = 1
rewardTitle.TextXAlignment = Enum.TextXAlignment.Left
rewardTitle.Text = "📅 Daily Rewards!"
rewardTitle.Parent = rewardPanel
themeLabel(rewardTitle, 36)
-- 9.9: the leading glyph becomes a drawing at the title's left edge, or stays a glyph if
-- there is no art for it. One line, and it moves nothing else on the panel.
UITheme.IconifyLabel(rewardTitle)

local rewardStreakCard = Instance.new("Frame")
rewardStreakCard.Name = "StreakCard"
rewardStreakCard.Size = UDim2.new(0, 240, 0, 34)
rewardStreakCard.Position = UDim2.new(0, 22, 0, 58)
rewardStreakCard.Parent = rewardPanel
styleCard(rewardStreakCard, UITheme.Color.Orange, UDim.new(1, 0), 3)

local rewardStreakLabel = Instance.new("TextLabel")
rewardStreakLabel.Name = "StreakLabel"
rewardStreakLabel.Size = UDim2.new(1, -28, 0, 24)
rewardStreakLabel.Position = UDim2.new(0, 14, 0, 3)
rewardStreakLabel.BackgroundTransparency = 1
rewardStreakLabel.TextXAlignment = Enum.TextXAlignment.Left
rewardStreakLabel.Text = "🔥 Streak: 0 days"
rewardStreakLabel.Parent = rewardStreakCard
themeLabel(rewardStreakLabel, 22)

local GRID_X, GRID_Y = 25, 100
local CELL_W, CELL_H, CELL_GAP = 140, 152, 8
local DAY7_W = 200

local rewardCells = {} -- [dayIndex] = { frame, dayLabel, iconLabel, amountLabel, bonusLabel, checkmark, strokeInst, idleColor, isToday }

-- one day of the board. `big` is the Day 7 hero column on the right: same anatomy, gold
-- shell, everything scaled up so it reads as the prize you are streaking towards.
local function buildDayCell(dayIndex, size, position, big)
	local reward = GameConfig.DailyRewards[dayIndex]
	local frame = Instance.new("Frame")
	frame.Name = "Day" .. dayIndex
	frame.Size = size
	frame.Position = position
	frame.Parent = rewardPanel
	local idleColor = big and UITheme.Color.Gold or UITheme.Color.Blue
	local strokeInst = styleCard(frame, idleColor, UDim.new(0, 16), big and 5 or 4)

	local dayLabel = Instance.new("TextLabel")
	dayLabel.Name = "DayLabel"
	dayLabel.Size = UDim2.new(1, -14, 0, big and 40 or 28)
	dayLabel.Position = UDim2.new(0, 7, 0, big and 12 or 8)
	dayLabel.BackgroundTransparency = 1
	dayLabel.Text = "Day " .. dayIndex
	dayLabel.Parent = frame
	themeLabel(dayLabel, big and 34 or 24)

	local icon = "🧬"
	if reward.potions and reward.shards then
		icon = "🌟"
	elseif reward.potions then
		icon = "🧪"
	elseif reward.shards or reward.diamonds then
		icon = "💎"
	end
	-- THE ICON IS THE FACE OF THE CARD, so this is the one slot on this panel where the drawing
	-- matters most. The box is unchanged; what changed is that an emoji's glyph fills about half
	-- its line box while a drawing fills what it is given, so these come out visibly larger at the
	-- same authored size. Day 7's 🌟 is gold on a gold card -- the case that pushed the icon drop
	-- shadow into UITheme rather than being special-cased here (see iconSlot).
	local iconLabel = UITheme.IconSlot(frame, {
		name = "IconLabel", icon = icon, maxTextSize = big and 84 or 46,
		size = UDim2.new(1, 0, 0, big and 138 or 58),
		position = UDim2.new(0, 0, 0, big and 62 or 38),
	})

	local amountLabel = Instance.new("TextLabel")
	amountLabel.Name = "AmountLabel"
	amountLabel.Size = UDim2.new(1, -12, 0, big and 34 or 24)
	amountLabel.Position = UDim2.new(0, 6, 1, big and -84 or -56)
	amountLabel.BackgroundTransparency = 1
	amountLabel.TextWrapped = true
	amountLabel.Text = formatNumber(reward.dna) .. " DNA"
	amountLabel.Parent = frame
	themeLabel(amountLabel, big and 28 or 21, UITheme.Color.Cream)

	local bonusLabel = Instance.new("TextLabel")
	bonusLabel.Name = "BonusLabel"
	bonusLabel.Size = UDim2.new(1, -12, 0, big and 36 or 24)
	bonusLabel.Position = UDim2.new(0, 6, 1, big and -46 or -30)
	bonusLabel.BackgroundTransparency = 1
	local bonusParts = {}
	if reward.potions then table.insert(bonusParts, "🧪 x" .. reward.potions) end
	if reward.shards then table.insert(bonusParts, "💎 x" .. reward.shards) end
	if reward.diamonds then table.insert(bonusParts, "💎 x" .. reward.diamonds) end
	bonusLabel.Text = table.concat(bonusParts, "  ")
	bonusLabel.Visible = #bonusParts > 0
	bonusLabel.Parent = frame
	themeLabel(bonusLabel, big and 26 or 19)

	local checkmark = claimTick(frame, big and 42 or 34, big and 26 or 22)

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
		idleColor = idleColor, isToday = false,
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
		size = UDim2.new(0, 220, 0, 42), position = UDim2.new(1, -22, 0, 54),
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
		size = UDim2.new(0, 170, 0, 42), position = UDim2.new(1, -250, 0, 54),
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

	rewardStreakLabel.Text = "🔥 Streak: " .. streak .. " day" .. (streak == 1 and "" or "s")

	local upcomingStreak = streak
	if canClaim then
		upcomingStreak = (today == lastDay + 1) and (streak + 1) or 1
	end
	if upcomingStreak < 1 then upcomingStreak = 1 end
	local rewardIndex = ((upcomingStreak - 1) % #GameConfig.DailyRewards) + 1

	local claimedUpTo = canClaim and (rewardIndex - 1) or rewardIndex
	local todayIndex = canClaim and rewardIndex or nil

	for d = 1, 7 do
		local cell = rewardCells[d]
		if cell then
			local isClaimed = d <= claimedUpTo
			local isToday = (d == todayIndex)
			local idleThickness = (d == 7) and 5 or 4
			cell.isToday = isToday
			cell.checkmark.Visible = isClaimed
			-- state reads off the shell colour, not transparency: fading the card would
			-- eat the outline and the gradient that make it look moulded.
			if isToday then
				cell.strokeInst.Color = READY_RIM
				cell.strokeInst.Thickness = idleThickness + 1
				cell.dayLabel.Text = "CLAIM!"
				setButtonColor(cell.frame, UITheme.Color.Green)
			elseif isClaimed then
				cell.strokeInst.Color = OUTLINE_COLOR
				cell.strokeInst.Thickness = idleThickness
				cell.dayLabel.Text = "Day " .. d
				setButtonColor(cell.frame, UITheme.Color.Locked)
			else
				cell.strokeInst.Color = OUTLINE_COLOR
				cell.strokeInst.Thickness = idleThickness
				cell.dayLabel.Text = "Day " .. d
				setButtonColor(cell.frame, cell.idleColor)
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
do
	local shell = styleCard(inventoryPanel, UITheme.Color.PanelWhite, UDim.new(0, 22), 5)
	if shell then shell.Color = UITheme.Color.SkyBlue end
	-- and FLAT. styleCard hangs a top-to-bottom gradient on everything it builds, which is what
	-- gives the coloured tiles their gloss -- but the same ramp over a white sheet just greys the
	-- bottom half of it, so the panel read as dirty rather than as paper.
	local grad = inventoryPanel:FindFirstChild("Gradient")
	if grad then grad:Destroy() end
end
registerPanel(inventoryPanel)
panelClose(inventoryPanel)

-- The title sits ABOVE the card, not inside it. Inside, it costs 48px of the panel's own height
-- and competes with the first section heading; above, it is a label on a box, which is what it is.
local inventoryTitle = Instance.new("TextLabel")
inventoryTitle.Name = "TitleLabel"
inventoryTitle.Size = UDim2.new(0, 420, 0, 48)
inventoryTitle.Position = UDim2.new(0, 6, 0, -54)
inventoryTitle.BackgroundTransparency = 1
inventoryTitle.TextXAlignment = Enum.TextXAlignment.Left
inventoryTitle.Text = "\u{1F392} Items!"
inventoryTitle.Parent = inventoryPanel
themeLabel(inventoryTitle, 40)
-- 9.9: the leading glyph becomes a drawing at the title's left edge, or stays a glyph if
-- there is no art for it. One line, and it moves nothing else on the panel.
UITheme.IconifyLabel(inventoryTitle)

-- ===== SECTION HEADINGS =====
-- Centred grey word with a rule running out of both sides. Two of them, written out rather than
-- put behind a helper: a helper for two call sites is a function you have to go and read.
-- INK on white, and passed EXPLICITLY -- themeLabel only rescues a dark colour to white when no
-- colour was given at all, so an explicit dark one survives, which is the whole point here.
local INK_ON_WHITE = Color3.fromRGB(108, 116, 140)
-- One heading now, not two: "Resources" titled a section that no longer exists (10.16).
for _, sec in ipairs({ { "Potions", 112 } }) do
	local head = Instance.new("TextLabel")
	head.Name = "Section_" .. sec[1]
	head.Size = UDim2.new(1, -36, 0, 30)
	head.Position = UDim2.new(0, 18, 0, sec[2])
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
local BOOST_STRIP_H = 30

local boostStrip = Instance.new("Frame")
boostStrip.Name = "BoostStrip"
-- the live-boost readout sits ABOVE the first heading, because it is status rather than content:
-- what is running right now belongs at the top of the screen it belongs to
boostStrip.Size = UDim2.new(1, -96, 0, BOOST_STRIP_H * 3)
boostStrip.Position = UDim2.new(0, 18, 0, 16)
boostStrip.BackgroundTransparency = 1
boostStrip.Parent = inventoryPanel

local boostRows = {}
for i, kind in ipairs(GameConfig.PotionKinds) do
	local row = Instance.new("TextLabel")
	row.Name = "Boost_" .. kind.key
	row.Size = UDim2.new(1, 0, 0, BOOST_STRIP_H)
	row.Position = UDim2.new(0, 0, 0, (i - 1) * BOOST_STRIP_H)
	row.BackgroundTransparency = 1
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.Visible = false
	row.Text = ""
	row.Parent = boostStrip
	themeLabel(row, 20, kind.color)
	boostRows[kind.key] = row
end

-- shown in place of the strip when nothing at all is running, so the space is never just blank
local noBoostLabel = Instance.new("TextLabel")
noBoostLabel.Name = "NoBoost"
noBoostLabel.Size = UDim2.new(1, 0, 0, BOOST_STRIP_H)
noBoostLabel.BackgroundTransparency = 1
noBoostLabel.TextXAlignment = Enum.TextXAlignment.Left
noBoostLabel.Text = "No potion running"
noBoostLabel.Parent = boostStrip
themeLabel(noBoostLabel, 20, UITheme.Color.Cream)

local potionScroll = Instance.new("ScrollingFrame")
potionScroll.Name = "PotionScroll"
potionScroll.Size = UDim2.new(1, -36, 0, 204)
potionScroll.Position = UDim2.new(0, 18, 0, 146)
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
potionEmptyLabel.Size = UDim2.new(1, -36, 0, 204)
potionEmptyLabel.Position = UDim2.new(0, 18, 0, 146)
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
	nameLabel.Size = UDim2.new(1, -250, 0, 26)
	nameLabel.Position = UDim2.new(0, 56, 0, 6)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = potion.emoji .. " " .. potion.shortName
	nameLabel.Parent = row
	themeLabel(nameLabel, 22)

	local subLabel = Instance.new("TextLabel")
	subLabel.Name = "SubLabel"
	-- WIDER, AND ON ONE LINE. `effectText` for the Luck bottles is "+120% egg, pet, character and
	-- mutation luck" -- 52 characters. In a 224 x 22 box with TextScaled and TextWrapped that is
	-- two wrapped lines inside 14px of bounds, which renders at about 7px: the three rows whose
	-- text a player most needs to read were the only three in the whole GUI that did not fit.
	--
	-- The row has the width to give: the count sits at -168 and the button at -100, so reserving
	-- 250 for both left 68 studs of the row unused. TextWrapped off so it can never stack two lines
	-- into a 22px box again -- if a future bottle out-writes the space it truncates visibly rather
	-- than shrinking to nothing.
	subLabel.Size = UDim2.new(1, -186, 0, 22)
	subLabel.Position = UDim2.new(0, 56, 0, 32)
	subLabel.BackgroundTransparency = 1
	subLabel.TextXAlignment = Enum.TextXAlignment.Left
	subLabel.TextWrapped = false
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

	local anyRunning = false
	for _, kind in ipairs(GameConfig.PotionKinds) do
		local boost = GameConfig.GetPotionBoost(currentData, kind.key)
		local row = boostRows[kind.key]
		if boost then
			anyRunning = true
			local remaining = math.max((boost.untilTs or 0) - os.time(), 0)
			local effect = boost.mult and ("x" .. boost.mult) or ("+" .. (boost.luckAdd or 0) .. "%")
			row.Text = ("%s %s %s  \u{2022}  %dm %02ds left"):format(kind.emoji, effect, kind.name, remaining // 60, remaining % 60)
			row.Visible = true
		else
			row.Visible = false
		end
	end
	noBoostLabel.Visible = not anyRunning
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
	local function buildTabs(panel, activeIndex)
		local row = Instance.new("Frame")
		row.Name = "InventoryTabs"
		row.Size = UDim2.new(0, 262, 0, 38)
		-- above the card, not inside it: both panels fill their own interior with content that was
		-- laid out before this existed, and squeezing a row in at the top would have meant moving
		-- every scroll frame in both of them
		row.Position = UDim2.new(1, -18, 0, -34)
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
			tab.MouseButton1Click:Connect(function()
				if def.target == panel then return end
				toggleOnly(def.target)
				if def.target == inventoryPanel then
					refreshInventoryPanel()
				end
			end)
		end
	end

	buildTabs(petsPanel, 1)
	buildTabs(inventoryPanel, 2)
end)()


-- ===== Robux Shop panel =====
local robuxPanel = Instance.new("Frame")
robuxPanel.Name = "RobuxPanel"
robuxPanel.Size = UDim2.new(0, 448, 0, 500)
robuxPanel.Position = PANEL_ANCHOR
robuxPanel.ZIndex = 20
robuxPanel.Visible = false
robuxPanel.Parent = screenGui
styleCard(robuxPanel, PANEL_SHELL, UDim.new(0, 22), 5)
registerPanel(robuxPanel)
panelClose(robuxPanel)

local robuxTitle = Instance.new("TextLabel")
robuxTitle.Name = "TitleLabel"
robuxTitle.Size = UDim2.new(1, -80, 0, 38)
robuxTitle.Position = UDim2.new(0, 18, 0, 10)
robuxTitle.BackgroundTransparency = 1
robuxTitle.TextXAlignment = Enum.TextXAlignment.Left
robuxTitle.Text = "🛍️ Robux Shop"
robuxTitle.Parent = robuxPanel
themeLabel(robuxTitle, 30)
-- 9.9: the leading glyph becomes a drawing at the title's left edge, or stays a glyph if
-- there is no art for it. One line, and it moves nothing else on the panel.
UITheme.IconifyLabel(robuxTitle)

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
	local function pickIndex()
		return (math.floor(os.time() / 86400) % #GameConfig.RobuxProducts) + 1
	end

	for i, product in ipairs(GameConfig.RobuxProducts) do
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

		-- the pick's own marker, drawn over the tile rather than in place of the ribbon so a tile can
		-- be both the best value and today's pick without one of the two facts disappearing
		if i == pickIndex() then
			local star = Instance.new("TextLabel")
			star.Name = "PickStar"
			star.Size = UDim2.new(0, 30, 0, 30)
			star.Position = UDim2.new(0, 2, 0, 12)
			star.BackgroundTransparency = 1
			star.Text = "\u{2B50}"
			star.ZIndex = card.ZIndex + UITheme.Z.Badge
			star.Parent = card
			themeLabel(star, 24)
		end
	end

	-- Re-run on every data push, which is also what makes the countdown in the title tick without a
	-- loop of its own -- the server pushes about every three seconds.
	hudRefs.refreshRobuxShop = function()
		for _, product in ipairs(GameConfig.RobuxProducts) do
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
		local left = 86400 - (os.time() % 86400)
		-- leading 🛍️ dropped for the reason written on the Pets title; the ⭐ mid-string stays,
		-- because it belongs to the sentence about the pick and has no slot of its own
		robuxTitle.Text = ("Robux Shop   \u{2B50} pick resets in %dh %02dm"):format(left // 3600, (left % 3600) // 60)
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
	local TOP = 64 + TAB_H + 8

	-- the product grid moves down to make room for the tab row above it
	robuxGrid.Position = UDim2.new(0, 16, 0, TOP)
	robuxGrid.Size = UDim2.new(1, -32, 1, -(TOP + 16))

	local tabRow = Instance.new("Frame")
	tabRow.Name = "TabRow"
	tabRow.Size = UDim2.new(1, -32, 0, TAB_H)
	tabRow.Position = UDim2.new(0, 16, 0, 60)
	tabRow.BackgroundTransparency = 1
	tabRow.ZIndex = robuxPanel.ZIndex + UITheme.Z.Content
	tabRow.Parent = robuxPanel

	local function makeTab(text, order)
		local b = Instance.new("TextButton")
		b.Name = text .. "Tab"
		b.Size = UDim2.new(0.5, -6, 1, 0)
		b.Position = UDim2.new(0.5 * (order - 1), order == 1 and 0 or 6, 0, 0)
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
playtimePanel.Size = UDim2.new(0, 790, 0, 292)
playtimePanel.Position = PANEL_ANCHOR
playtimePanel.ZIndex = 20
playtimePanel.Visible = false
playtimePanel.Parent = screenGui
styleCard(playtimePanel, PANEL_SHELL, UDim.new(0, 22), 5)
registerPanel(playtimePanel)
panelClose(playtimePanel)

local playtimeTitle = Instance.new("TextLabel")
playtimeTitle.Name = "TitleLabel"
playtimeTitle.Size = UDim2.new(1, -90, 0, 40)
playtimeTitle.Position = UDim2.new(0, 20, 0, 10)
playtimeTitle.BackgroundTransparency = 1
playtimeTitle.TextXAlignment = Enum.TextXAlignment.Left
playtimeTitle.Text = "⏰ Playtime Gifts"
playtimeTitle.Parent = playtimePanel
themeLabel(playtimeTitle, 32)
-- 9.9: the leading glyph becomes a drawing at the title's left edge, or stays a glyph if
-- there is no art for it. One line, and it moves nothing else on the panel.
UITheme.IconifyLabel(playtimeTitle)

local playtimeSubLabel = Instance.new("TextLabel")
playtimeSubLabel.Name = "SubLabel"
playtimeSubLabel.Size = UDim2.new(1, -44, 0, 24)
playtimeSubLabel.Position = UDim2.new(0, 22, 0, 54)
playtimeSubLabel.BackgroundTransparency = 1
playtimeSubLabel.TextXAlignment = Enum.TextXAlignment.Left
playtimeSubLabel.Text = "The longer you stay in this session, the better the gift!"
playtimeSubLabel.Parent = playtimePanel
themeLabel(playtimeSubLabel, 20, UITheme.Color.Cream)

local PLAYTIME_CELL_W = 142
local playtimeCells = {} -- [index] = { frame, statusLabel, checkmark, strokeInst }

for i, milestone in ipairs(GameConfig.PlaytimeGifts) do
	local frame = Instance.new("Frame")
	frame.Name = "Gift" .. i
	frame.Size = UDim2.new(0, PLAYTIME_CELL_W, 0, 182)
	frame.Position = UDim2.new(0, 16 + (i - 1) * (PLAYTIME_CELL_W + 12), 0, 92)
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
characterPanel.Size = UDim2.new(0, 968, 0, 548)
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

-- ON A WHITE PANEL EVERY LABEL HAS TO NAME ITS COLOUR, and that is not automatic: themeLabel only
-- rescues a colour to white when none was given, so anything left to default -- or set to Cream --
-- ends up white on white and disappears.
local characterTitle = Instance.new("TextLabel")
characterTitle.Size = UDim2.new(0, 460, 0, 48)
characterTitle.Position = UDim2.new(0, 6, 0, -54)
characterTitle.BackgroundTransparency = 1
characterTitle.TextXAlignment = Enum.TextXAlignment.Left
characterTitle.Text = "\u{1F4D2} Journal!"
characterTitle.Parent = characterPanel
themeLabel(characterTitle, 40)

local characterCount = Instance.new("TextLabel")
characterCount.Name = "CountLabel"
characterCount.Size = UDim2.new(1, -44, 0, 26)
characterCount.Position = UDim2.new(0, 20, 0, 14)
characterCount.BackgroundTransparency = 1
characterCount.TextXAlignment = Enum.TextXAlignment.Left
characterCount.Text = "Discovered 0 / 100"
characterCount.Parent = characterPanel
themeLabel(characterCount, 22, Color3.fromRGB(124, 134, 156))

local characterScroll = Instance.new("ScrollingFrame")
characterScroll.Name = "CharacterScroll"
-- the left column only: the detail card owns the right 330 and is built further down
characterScroll.Size = UDim2.new(0, 604, 1, -62)
characterScroll.Position = UDim2.new(0, 14, 0, 48)
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

	-- The twenty stage rows, PLUS ONE MORE at the end for the VIP skin.
	--
	-- It is built by exactly the same code as every other disc, which is the point: it locks,
	-- unlocks, previews, selects and wears with no special case anywhere, and a later change to how
	-- a cell looks reaches it for free. What it is NOT is part of a stage -- it never enters
	-- CHARACTERS_BY_STAGE, so the collection count, the evolve chain and the rank ladder cannot see
	-- it. See GameConfig.VipCharacter for why that separation is load-bearing.
	local sections = {}
	for stageIndex, stage in ipairs(GameConfig.Stages) do
		table.insert(sections, {
			index = stageIndex,
			stage = stage,
			entries = GameConfig.GetCharactersForStage(stageIndex),
		})
	end
	table.insert(sections, {
		index = #GameConfig.Stages + 1,
		stage = { emoji = GameConfig.VipCharacter.emoji, name = "VIP Exclusive" },
		entries = { GameConfig.VipCharacter },
	})

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
			cell.BackgroundTransparency = 1
			local cellGrad = cell:FindFirstChild("Gradient")
			if cellGrad then cellGrad:Destroy() end
			-- and the sheen goes with it: a white highlight floating on nothing is not a highlight,
			-- it is a smear across the model's head
			local cellGloss = cell:FindFirstChild("Gloss")
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
			-- The VIP skin has NO rung on the ladder -- it scores as whatever the wearer's best earned
			-- skin scores (GameConfig.GetEffectiveRank), so any fixed percentage printed here would be
			-- a lie in one direction or the other depending on how far the collection has got. It says
			-- what it actually is instead.
			damageLabel.Text = entry.vip and "\u{2694}\u{FE0F} = best"
				or ("\u{2694}\u{FE0F} %s"):format(formatNumber(damagePct))
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
			lock.BackgroundColor3 = tint:Lerp(Color3.fromRGB(18, 16, 26), 0.72)
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
				strokeInst = cellStroke, entry = entry, rarity = { color = tint },
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
	detail.Size = UDim2.new(0, 322, 1, -62)
	detail.Position = UDim2.new(1, -14, 0, 48)
	detail.AnchorPoint = Vector2.new(1, 0)
	detail.ZIndex = characterPanel.ZIndex + UITheme.Z.Content
	detail.Parent = characterPanel
	styleCard(detail, Color3.fromRGB(240, 243, 250), UDim.new(0, 18), 3)

	-- A WELL FOR THE FIGURE TO STAND IN. On the panel's own white sheet a pale character had no
	-- edge at all -- the same problem the loading screen's tip card was made to solve.
	local stageBox = Instance.new("Frame")
	stageBox.Name = "StageBox"
	stageBox.Size = UDim2.new(1, -24, 0, 244)
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

	local dName = Instance.new("TextLabel")
	dName.Name = "DetailName"
	dName.Size = UDim2.new(1, -24, 0, 36)
	dName.Position = UDim2.new(0, 12, 0, 264)
	dName.BackgroundTransparency = 1
	dName.ZIndex = detail.ZIndex + 1
	dName.Parent = detail
	themeLabel(dName, 30, Color3.fromRGB(46, 54, 74))

	local dSub = Instance.new("TextLabel")
	dSub.Name = "DetailSub"
	dSub.Size = UDim2.new(1, -24, 0, 24)
	dSub.Position = UDim2.new(0, 12, 0, 300)
	dSub.BackgroundTransparency = 1
	dSub.ZIndex = detail.ZIndex + 1
	dSub.Parent = detail
	themeLabel(dSub, 20, Color3.fromRGB(126, 134, 156))

	-- the one number that matters, in the shape every other stat in this game is drawn in
	local dStat = Instance.new("Frame")
	dStat.Name = "DetailStat"
	dStat.Size = UDim2.new(1, -24, 0, 40)
	dStat.Position = UDim2.new(0, 12, 0, 332)
	dStat.ZIndex = detail.ZIndex + 1
	dStat.Parent = detail
	styleCard(dStat, Color3.fromRGB(230, 235, 246), UDim.new(0, 12), 3)

	local dStatLabel = Instance.new("TextLabel")
	dStatLabel.Size = UDim2.new(1, -16, 1, -6)
	dStatLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	dStatLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	dStatLabel.BackgroundTransparency = 1
	dStatLabel.ZIndex = dStat.ZIndex + 1
	dStatLabel.Parent = dStat
	themeLabel(dStatLabel, 21, Color3.fromRGB(70, 78, 98))

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

	-- TEXT AND BUTTON ONLY. Called from refreshCharacterPanel, which runs on every DataUpdate --
	-- which is to say on every creature anyone kills -- so it must never rebuild the figure.
	local function paintDetail()
		local refs = selectedKey and characterCells[selectedKey]
		local entry = refs and refs.entry
		if not entry then
			dName.Text = "Nothing picked"
			dSub.Text = "Choose one from the list"
			dStatLabel.Text = ""
			dHint.Text = ""
			bigMark.Visible = true
			bigMark.Text = "\u{1F4D2}"
			equipButton.Visible = false
			return
		end

		local owned = currentData and currentData.Characters and currentData.Characters[entry.key] == true
		local stage = GameConfig.Stages[entry.stage]
		local rarityLine = ownershipText(entry.key)
		-- ONE worn character, wherever the player is standing -- see GameConfig.GetWornCharacter
		local equipped = currentData and currentData.WornCharacter == entry.key
		-- The rung the player actually FIGHTS at. It is the best one owned, not the one on the body:
		-- a costume is free now, see GameConfig.GetProgressRank.
		local progressDamage = currentData and math.floor(GameConfig.GetBaseDamage(currentData)) or 0

		dName.Text = owned and entry.name or "???"
		dName.TextColor3 = owned and (entry.color or Color3.fromRGB(46, 54, 74)) or Color3.fromRGB(150, 158, 178)
		dSub.Text = ("%s %s  \u{2022}  #%d of %d%s"):format(stage and stage.emoji or "", stage and stage.name or "",
			GameConfig.GetCharacterIndex(entry), #GameConfig.GetCharactersForStage(entry.stage), rarityLine)
		dStatLabel.Text = ("\u{2694}\u{FE0F}  %s Damage"):format(
			formatNumber(math.floor(GameConfig.GetRankDamage(GameConfig.GetCharacterRank(entry)))))

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
		if not owned then
			dHint.Text = "Evolve to " .. (stage and stage.name or "this stage") .. " to discover it."
		elseif equipped then
			dHint.Text = ("This is what you look like right now.  You hit for %s."):format(formatNumber(progressDamage))
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
			-- The VIP skin belongs to no stage: it is a gold version of whatever the player currently
			-- IS, so it previews at their stage rather than at a fixed one. (Build returns nil for a
			-- nil stage rather than erroring, so this is a correctness fix, not a crash fix.)
			local previewStage = (entry.vip and currentData and currentData.StageIndex) or entry.stage
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
	-- A hundred cells is three thousand parts if they are all built, and the panel shows about
	-- eighteen of them at a time. So a cell builds its rig when it scrolls into the window and
	-- gives it back when it leaves, and at most two are built per pass -- a scroll that stops on a
	-- fresh row builds them over the next few frames instead of hitching on one.
	local function syncPreviews()
		if not (characterPanel.Visible and currentData) then return end
		local owned = currentData.Characters or {}
		local top = characterScroll.AbsolutePosition.Y
		local height = characterScroll.AbsoluteSize.Y
		if height <= 0 then return end
		local budget = 2

		for key, refs in pairs(characterCells) do
			local y = refs.cell.AbsolutePosition.Y - top
			-- a row of slack either side, so a slow scroll never shows an empty disc arriving
			local inView = y > -CHAR_LINE_H and y < height + CHAR_LINE_H
			if owned[key] and inView then
				if not refs.rig and budget > 0 then
					budget -= 1
					-- same rule as the detail card: the VIP skin previews at the player's own stage
					local previewStage = (refs.entry.vip and currentData.StageIndex) or refs.entry.stage
					refs.rig = CharacterPreview.Build(refs.art, previewStage, refs.entry, { maxParts = 26 })
					if refs.rig then
						CharacterPreview.Frame(refs.art, refs.rig, { zoom = 1.16 })
						refs.art.Visible = true
						refs.icon.Visible = false
					end
				end
			elseif refs.rig then
				refs.rig:Destroy()
				refs.rig = nil
				refs.art.Visible = false
				refs.icon.Visible = owned[key] == true
			end
		end
	end

	-- Scrolling is the only thing that changes what is in view, and CanvasPosition is the only
	-- honest signal for it -- the cells live inside the scrolling frame and their own positions
	-- move with it.
	characterScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(syncPreviews)

	-- ONE turntable, for the big figure only. Turning eighteen cell rigs as well would be six
	-- hundred part CFrames written every frame behind a panel, and a 96px disc reads no better
	-- moving than still.
	RunService.RenderStepped:Connect(function()
		if not (characterPanel.Visible and bigRig and bigPivot) then return end
		bigRig:PivotTo(CFrame.Angles(0, os.clock() * 0.6, 0) * bigPivot)
	end)

	hudRefs.journalSelect = selectCharacter
	hudRefs.journalPaintDetail = paintDetail
	hudRefs.journalSync = syncPreviews
	-- Opening the panel lands on the character you are wearing. An empty card next to a full grid
	-- reads as something that failed to load.
	hudRefs.journalOnOpen = function()
		if not selectedKey and currentData then
			local worn = currentData.WornCharacter
			if worn then
				selectCharacter(worn)
			end
		end
		syncPreviews()
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
	characterCount.Text = ("Discovered %d / %d"):format(have, total)

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
		if isOwned then
			setButtonColor(refs.cell, refs.rarity.color)
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
	local PAGE_TOP = 106

	local panel = Instance.new("Frame")
	panel.Name = "SeasonPanel"
	panel.Size = UDim2.new(0, 880, 0, 480)
	panel.Position = PANEL_ANCHOR
	panel.ZIndex = 20
	panel.Visible = false
	panel.Parent = screenGui
	styleCard(panel, PANEL_SHELL, UDim.new(0, 22), 5)
	registerPanel(panel)
	panelClose(panel)

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(0, 330, 0, 40)
	title.Position = UDim2.new(0, 18, 0, 10)
	title.BackgroundTransparency = 1
	title.TextXAlignment = Enum.TextXAlignment.Left
	-- The live season, not the authored one: 7.3 made the id and the name functions of the date, so
	-- a title written once at build time would name last month's season for the whole of this one.
	-- `refresh` re-reads it below, which also covers a session that spans the turnover.
	do
		local season = GameConfig.GetCurrentSeason()
		title.Text = season.emoji .. " " .. season.name
	end
	title.Parent = panel
	themeLabel(title, 30)

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
			setButtonColor(btn, key == name and UITheme.Color.Sunny or UITheme.Color.Locked)
		end
	end

	for i, spec in ipairs({
		{ key = "track",  text = SEASON.emoji .. " Season Pass" },
		{ key = "quests", text = "\u{1F4CB} Quests" },
	}) do
		local btn = Instance.new("TextButton")
		btn.Name = "Tab_" .. spec.key
		btn.Size = UDim2.new(0, 190, 0, 42)
		btn.Position = UDim2.new(0, 360 + (i - 1) * 200, 0, 12)
		btn.Text = spec.text
		btn.ZIndex = panel.ZIndex + UITheme.Z.Content
		btn.Parent = panel
		styleButton(btn, UITheme.Color.Locked, UDim.new(0, 14))
		btn.MouseButton1Click:Connect(function()
			setTab(spec.key)
		end)
		tabs[spec.key] = btn
	end

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

	-- right: the thirty columns, scrolling sideways
	local trackScroll = Instance.new("ScrollingFrame")
	trackScroll.Name = "TrackScroll"
	trackScroll.Size = UDim2.new(1, -224, 0, 254)
	trackScroll.Position = UDim2.new(0, 224, 0.5, 0)
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
	local function rewardFace(reward)
		if reward.shards then return "\u{2728}", "x" .. reward.shards end
		if reward.diamonds then return "\u{1F48E}", "x" .. reward.diamonds end
		if reward.potions then
			local potion = reward.potionId and GameConfig.GetPotion(reward.potionId)
			return potion and potion.emoji or "\u{1F9EA}", "x" .. reward.potions
		end
		return "\u{1F9EC}", formatNumber(reward.dna or 0)
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
		local faceEmoji, faceAmount = rewardFace(reward)

		UITheme.IconSlot(btn, {
			name = "Icon", icon = faceEmoji, maxTextSize = 30,
			size = UDim2.new(1, -8, 0, 36), position = UDim2.new(0, 4, 0, 5),
		})

		local amount = Instance.new("TextLabel")
		amount.Size = UDim2.new(1, -8, 0, 20)
		amount.Position = UDim2.new(0, 4, 0, 40)
		amount.BackgroundTransparency = 1
		amount.Text = faceAmount
		amount.Parent = btn
		themeLabel(amount, 17)

		local status = Instance.new("TextLabel")
		status.Size = UDim2.new(1, -8, 0, 24)
		status.Position = UDim2.new(0, 4, 1, -27)
		status.BackgroundTransparency = 1
		status.Text = "\u{1F512}"
		status.Parent = btn
		themeLabel(status, 16)

		btn.MouseButton1Click:Connect(function()
			if claimRewardRemote then
				claimRewardRemote:FireServer(level, track)
			end
		end)

		return { btn = btn, status = status, strokeInst = strokeInst }
	end

	for level = 1, SEASON.maxLevel do
		local row = GameConfig.GetSeasonReward(level)

		local column = Instance.new("Frame")
		column.Name = "Level" .. level
		column.Size = UDim2.new(0, CELL, 0, CELL * 2 + 42)
		column.LayoutOrder = level
		column.BackgroundTransparency = 1
		column.ZIndex = trackScroll.ZIndex + UITheme.Z.Content
		column.Parent = trackScroll

		local columnLayout = Instance.new("UIListLayout")
		columnLayout.SortOrder = Enum.SortOrder.LayoutOrder
		columnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		columnLayout.Padding = UDim.new(0, 5)
		columnLayout.Parent = column

		local freeRefs = buildCell(column, level, "free", 1)

		-- the level number between the two rows, brighter on every tenth
		local chip = Instance.new("Frame")
		chip.Name = "Chip"
		chip.Size = UDim2.new(0, CELL, 0, 32)
		chip.LayoutOrder = 2
		chip.ZIndex = column.ZIndex
		chip.Parent = column
		local chipStroke = styleCard(chip, row.milestone and UITheme.Color.Sunny or UITheme.Color.Locked, UDim.new(1, 0), 3)

		local chipLabel = Instance.new("TextLabel")
		chipLabel.Size = UDim2.new(1, -8, 1, -6)
		chipLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
		chipLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		chipLabel.BackgroundTransparency = 1
		chipLabel.Text = tostring(level)
		chipLabel.Parent = chip
		themeLabel(chipLabel, 22)

		local premiumRefs = buildCell(column, level, "premium", 3)

		cells[level] = { free = freeRefs, premium = premiumRefs, chip = chip, chipStroke = chipStroke }
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
			themeLabel(payLabel, 18, UITheme.Color.Cream)

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
			local current = GameConfig.GetCurrentSeason()
			title.Text = current.emoji .. " " .. current.name
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

		for lvl = 1, SEASON.maxLevel do
			local refs = cells[lvl]
			local slot = tostring(lvl)
			local reached = (lvl <= level)

			for _, track in ipairs({ "free", "premium" }) do
				local cellRefs = refs[track]
				local claimed = (track == "premium" and claimedPremium or claimedFree)[slot] == true
				local owned = (track == "free") or hasPremium

				if claimed then
					cellRefs.status.Text = "\u{2705} Claimed"
					setButtonColor(cellRefs.btn, UITheme.Color.Locked)
					cellRefs.strokeInst.Color = OUTLINE_COLOR
					cellRefs.strokeInst.Thickness = 4
				elseif reached and owned then
					-- the one "press me" state on the board, same bright rim as everywhere else
					claimable += 1
					cellRefs.status.Text = "CLAIM!"
					setButtonColor(cellRefs.btn, UITheme.Color.Green)
					cellRefs.strokeInst.Color = READY_RIM
					cellRefs.strokeInst.Thickness = 5
				elseif reached and not owned then
					-- earned but behind the pass: gold rim, so it reads as "buy this" and not "grind more"
					cellRefs.status.Text = "\u{1F512} Premium"
					setButtonColor(cellRefs.btn, UITheme.Color.Locked)
					cellRefs.strokeInst.Color = UITheme.Color.Gold
					cellRefs.strokeInst.Thickness = 4
				else
					cellRefs.status.Text = "\u{1F512} Lv." .. lvl
					setButtonColor(cellRefs.btn, UITheme.Color.Locked)
					cellRefs.strokeInst.Color = OUTLINE_COLOR
					cellRefs.strokeInst.Thickness = 4
				end
			end
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
				setButtonColor(refs.claimBtn, UITheme.Color.Locked)
				refs.rowStroke.Color = OUTLINE_COLOR
				refs.rowStroke.Thickness = 4
			elseif done >= quest.target then
				band = 1
				claimable += 1
				refs.claimBtn.Text = "CLAIM!"
				setButtonColor(refs.claimBtn, UITheme.Color.Green)
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
local function showNotification(text, color)
	local live = {}
	for _, c in ipairs(notifFrame:GetChildren()) do
		if c:IsA("Frame") then table.insert(live, c) end
	end
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
	notif.Name = "Notif"
	notif.Size = UDim2.new(1, 0, 0, 46)
	notif.ZIndex = notifFrame.ZIndex
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
		chip.Size = UDim2.new(0, 32, 0, 32)
		chip.Position = UDim2.new(0, 7, 0.5, -2)
		chip.AnchorPoint = Vector2.new(0, 0.5)
		chip.ZIndex = notif.ZIndex + UITheme.Z.Content
		chip.Parent = notif
		-- a shade DOWN from the card, not up: the badge has to separate from the fill it sits on,
		-- and the card is already at the top of its own range
		styleCard(chip, UITheme.Shade(vivid, -0.3), UDim.new(1, 0), 2)

		local glyph = Instance.new("TextLabel")
		glyph.Size = UDim2.new(1, 0, 1, 0)
		glyph.BackgroundTransparency = 1
		glyph.Text = icon
		glyph.ZIndex = chip.ZIndex + UITheme.Z.Content
		glyph.Parent = chip
		themeLabel(glyph, 20)
	end

	local message = Instance.new("TextLabel")
	message.Name = "Message"
	-- left-aligned and inset past the chip when there is one. Centred text that starts at a
	-- different x on every toast is what made a stack of them read as noise.
	message.Size = UDim2.new(1, icon and -54 or -20, 1, -12)
	message.Position = UDim2.new(0, icon and 46 or 10, 0.5, -2)
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
		-- no body to hang it on (mid-respawn): fall back to the toast rather than losing the message
		showNotification(text, color)
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
	dnaPill.Value.Text = formatNumber(data.DNA)
	diamondPill.Value.Text = formatNumber(data.Diamonds or 0)
	shardPill.Value.Text = formatNumber(data.EvolutionShards or 0)

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
		refs.levelLabel.Text = ("Lv %d / %d"):format(level, upgradeMax)
		refs.costLabel.Text = maxed and "ZONE LOCKED" or ("\u{1F9EC} " .. formatNumber(cost))
		if refs.button then
			setButtonColor(refs.button, (not maxed and data.DNA >= cost)
				and UITheme.Color.Green or UITheme.Color.Locked)
		end
	end

	for key, refs in pairs(diamondUpgradeButtons) do
		local def = GameConfig.DiamondUpgrades[key]
		local level = (data.DiamondUpgrades and data.DiamondUpgrades[key]) or 0
		local cost = GameConfig.GetDiamondUpgradeCost(key, level)
		refs.levelLabel.Text = "Level " .. level .. (def.maxLevel and (" / " .. def.maxLevel) or "")
		refs.costLabel.Text = (cost == math.huge) and "MAXED" or ("💎 " .. formatNumber(cost))
		if refs.button then
			setButtonColor(refs.button, (cost ~= math.huge and (data.Diamonds or 0) >= cost)
				and UITheme.Color.SkyBlue or UITheme.Color.Locked)
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
	-- 2 rows is the maximum this card can ever have, and it is authored at that height so
	-- registerPanel's responsive fit is computed once against the largest it can be. A card that
	-- re-sized itself after being fitted would be measuring against a scale derived from the old
	-- size -- the feedback loop registerPanel's own comment warns about.
	panel.Size = UDim2.new(0, 560, 0, 116 + ROW_H * 2 + ROW_GAP + 20)
	panel.Position = PANEL_ANCHOR
	panel.ZIndex = 20
	panel.Visible = false
	panel.Parent = screenGui
	styleCard(panel, PANEL_SHELL, UDim.new(0, 22), 5)
	registerPanel(panel)
	panelClose(panel)

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -110, 0, 44)
	title.Position = UDim2.new(0, 24, 0, 16)
	title.BackgroundTransparency = 1
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "\u{1F44B} Welcome back!"
	title.ZIndex = panel.ZIndex + UITheme.Z.Content
	title.Parent = panel
	themeLabel(title, 36)

	local sub = Instance.new("TextLabel")
	sub.Name = "Subtitle"
	sub.Size = UDim2.new(1, -48, 0, 26)
	sub.Position = UDim2.new(0, 24, 0, 62)
	sub.BackgroundTransparency = 1
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.Text = "You have something waiting."
	sub.ZIndex = panel.ZIndex + UITheme.Z.Content
	sub.Parent = panel
	themeLabel(sub, 20, UITheme.Color.Cream)

	-- A list layout rather than hand arithmetic, so hiding one row closes the gap it left instead
	-- of leaving a hole the size of a card in the middle of the panel (11.3's rule, applied before
	-- it can become a defect rather than after).
	local rowHost = Instance.new("Frame")
	rowHost.Name = "Rows"
	rowHost.Size = UDim2.new(1, -48, 0, ROW_H * 2 + ROW_GAP)
	rowHost.Position = UDim2.new(0, 24, 0, 104)
	rowHost.BackgroundTransparency = 1
	rowHost.ZIndex = panel.ZIndex + UITheme.Z.Content
	rowHost.Parent = panel

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.Padding = UDim.new(0, ROW_GAP)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = rowHost

	-- one line of the card: what is waiting, and the one button that goes there
	local function buildRow(order, color, action)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, ROW_H)
		row.LayoutOrder = order
		row.ZIndex = rowHost.ZIndex + UITheme.Z.Content
		row.Visible = false
		row.Parent = rowHost
		styleCard(row, PET_ROW_SHELL, UDim.new(0, 16), 4)

		local head = Instance.new("TextLabel")
		head.Name = "Head"
		head.Size = UDim2.new(1, -190, 0, 30)
		head.Position = UDim2.new(0, 18, 0, 12)
		head.BackgroundTransparency = 1
		head.TextXAlignment = Enum.TextXAlignment.Left
		head.ZIndex = row.ZIndex + UITheme.Z.Content
		head.Parent = row
		themeLabel(head, 26)

		local note = Instance.new("TextLabel")
		note.Name = "Note"
		note.Size = UDim2.new(1, -190, 0, 26)
		note.Position = UDim2.new(0, 18, 0, 46)
		note.BackgroundTransparency = 1
		note.TextXAlignment = Enum.TextXAlignment.Left
		note.ZIndex = row.ZIndex + UITheme.Z.Content
		note.Parent = row
		themeLabel(note, 19, UITheme.Color.Cream)

		local btn = Instance.new("TextButton")
		btn.Name = "GoButton"
		btn.Size = UDim2.new(0, 150, 0, 52)
		btn.Position = UDim2.new(1, -16, 0.5, 0)
		btn.AnchorPoint = Vector2.new(1, 0.5)
		btn.Text = "OPEN"
		btn.ZIndex = row.ZIndex + UITheme.Z.Content
		btn.Parent = row
		styleButton(btn, color, UDim.new(0, 14))
		-- No explicit close: every one of these opens a panel through `toggleOnly`, which runs
		-- `closeAllPanels` first, and this card is a registered panel -- so it closes itself on the
		-- way out, animated, through the same path as everything else.
		btn.MouseButton1Click:Connect(action)

		return row, head, note, btn
	end

	local dailyRow, dailyHead, dailyNote = buildRow(1, UITheme.Color.Green, function()
		refreshRewardPanel()
		toggleOnly(rewardPanel)
	end)
	local seasonRow, seasonHead, seasonNote = buildRow(2, UITheme.Color.Sunny, function()
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
			local upcoming = (today == dayNumber(data.LastRewardClaim) + 1) and (streak + 1) or 1
			local index = ((math.max(upcoming, 1) - 1) % #GameConfig.DailyRewards) + 1
			dailyHead.Text = ("\u{1F381} Daily reward \u{2014} Day %d is ready"):format(index)
			dailyNote.Text = (streak > 0)
				and ("\u{1F525} %d day streak \u{2014} claim to keep it going"):format(streak)
				or "Claim it to start a streak"
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
	local BADGE_REST = UITheme.Shade(UITheme.Color.Outline, 0.22)

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

	if payload.kind == "crit" then
		showNotification("💥 CRITICAL! +" .. formatNumber(payload.amount) .. " DNA", Color3.fromRGB(255, 200, 60))
	elseif payload.kind == "upgrade" then
		local def = GameConfig.Upgrades[payload.upgrade]
		showNotification("⬆️ " .. def.displayName .. " upgraded to Lv." .. payload.level, Color3.fromRGB(90, 200, 255))
		-- nil-guarded like every other hudRefs consumer: a panel that failed to build must not take
		-- the notification with it
		if hudRefs.punchUpgrade then hudRefs.punchUpgrade(payload.upgrade) end
	elseif payload.kind == "diamond" then
		showNotification("\u{1F48E} Diamond found!  +" .. (payload.amount or 1), Color3.fromRGB(130, 225, 255))
	elseif payload.kind == "evolve" then
		-- TWO DIFFERENT EVENTS SHARE THIS PAYLOAD. Four presses in five hand over the next skin and
		-- leave the stage where it is, so announcing "EVOLVED into Worm" on all of them would be
		-- wrong four times out of five -- and what changed is the thing the player is looking at.
		-- The reveal card draws the picture; this line is the words that go with it.
		if payload.advanced then
			showNotification("\u{1F31F} EVOLVED into " .. payload.emoji .. " " .. payload.stage .. "!",
				Color3.fromRGB(190, 120, 255))
		else
			showNotification(("\u{2728} NEW FORM: %s %s  (%d/%d)"):format(
				(GameConfig.GetCharacter(payload.character or "") or {}).emoji or "\u{2B50}",
				(GameConfig.GetCharacter(payload.character or "") or {}).name or payload.stage,
				payload.step or 1, payload.steps or 5), Color3.fromRGB(190, 120, 255))
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
			showNotification(("%s %s%s"):format(payload.emoji, payload.name, gain), tint)
		end
	elseif payload.kind == "questComplete" then
		-- finishing one is worth a toast; the reward itself is a separate, deliberate press, so the
		-- message says where to go rather than implying it has already been paid out
		showNotification(("%s %s \u{2014} ready to claim in %s!")
			:format(payload.emoji, payload.name, GameConfig.Season.emoji .. " Season"),
			UITheme.Color.Gold)
	-- The "mutation" toast is gone: DNAService stopped sending it. Mutations roll every ten
	-- seconds and the banner fired over and over during ordinary play.
	elseif payload.kind == "zone" then
		showNotification("🗺️ NEW ZONE UNLOCKED: " .. payload.emoji .. " " .. payload.name .. "!", Color3.fromRGB(60, 160, 220))
	elseif payload.kind == "pet" then
		-- Deliberately silent here now. The whole hatch -- the egg shaking, cracking, the rarity
		-- flash, the pet rising out of it and the card naming what it is -- belongs to HatchReveal
		-- (Phase 6.1), which is the only thing that knows when the reveal moment actually is. This
		-- branch used to draw the card immediately, which is a second before the egg had finished
		-- moving. Same reasoning as `creature` and `playerHurt` above.
	elseif payload.kind == "fuse" then
		local rarity = GameConfig.GetRarity(payload.rarity)
		worldPopup(payload.emoji .. " " .. payload.name, "FUSED → " .. payload.tier, rarity.color)
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
		showNotification(text, Color3.fromRGB(255, 180, 60))
	elseif payload.kind == "stageMastery" then
		showNotification("⭐ " .. payload.emoji .. " " .. payload.stage .. " MASTERED! (" .. payload.owned .. "/" .. #GameConfig.Stages .. ")", Color3.fromRGB(255, 215, 70))
	elseif payload.kind == "diamondUpgrade" then
		local def = GameConfig.DiamondUpgrades[payload.upgrade]
		showNotification("💎 " .. (def and def.displayName or payload.upgrade) .. " upgraded to Lv." .. payload.level .. "!", Color3.fromRGB(120, 200, 255))
	elseif payload.kind == "potion" then
		local remaining = math.max(0, (payload.untilTs or 0) - os.time())
		local potion = payload.potionId and GameConfig.GetPotion(payload.potionId)
		showNotification(string.format("%s %s  \u{2022}  %dm %02ds left",
			potion and potion.emoji or "\u{1F9EA}",
			potion and potion.effectText or "Potion used",
			remaining // 60, remaining % 60), (potion and potion.color) or Color3.fromRGB(120, 255, 180))
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
		showNotification("⏰ Playtime Gift (" .. payload.minutes .. " min)! Reward claimed!", Color3.fromRGB(255, 150, 90))
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
		showNotification("❌ " .. payload.message, Color3.fromRGB(200, 60, 60))
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
	panel.Size = UDim2.new(0, 430, 0, 372)
	panel.Position = PANEL_ANCHOR
	panel.ZIndex = 20
	panel.Visible = false
	panel.Parent = screenGui
	styleCard(panel, PANEL_SHELL, UDim.new(0, 22), 5)
	registerPanel(panel)
	panelClose(panel)

	UITheme.Label(panel, {
		name = "Title", text = "\u{1F50A} Audio",
		size = UDim2.new(1, -80, 0, 40), position = UDim2.new(0, 18, 0, 10),
		xAlign = "Left", maxTextSize = 34, zIndex = 22,
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
		local y = 64 + (i - 1) * 58

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
-- shown is the number `rollAndInsert` rolls against, because both call one function.
--
-- The whole block is an immediately-called function with only `hudRefs.refreshEggPanel` escaping,
-- because this file is at Luau's 200-local ceiling. A `do ... end` is NOT enough -- see the note
-- over the Season Pass panel for the two times that mistake deleted the entire HUD.
;(function()
	local eggButton = columnTile("R", 9, "\u{1F95A}", "Eggs", UITheme.Color.Bubblegum)

	local panel = Instance.new("Frame")
	panel.Name = "EggPanel"
	panel.Size = UDim2.new(0, 470, 0, 520)
	panel.Position = PANEL_ANCHOR
	panel.ZIndex = 20
	panel.Visible = false
	panel.Parent = screenGui
	styleCard(panel, PANEL_SHELL, UDim.new(0, 22), 5)
	registerPanel(panel)
	panelClose(panel)

	local title = UITheme.Label(panel, {
		name = "Title", text = "\u{1F95A} Eggs",
		size = UDim2.new(1, -80, 0, 40), position = UDim2.new(0, 18, 0, 10),
		xAlign = "Left", maxTextSize = 34, zIndex = 22,
	})

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
	tierRow.Position = UDim2.new(0, 18, 0, 58)
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
	costLabel.Position = UDim2.new(0, 18, 0, 118)
	costLabel.BackgroundTransparency = 1
	costLabel.TextXAlignment = Enum.TextXAlignment.Left
	costLabel.Text = ""
	costLabel.ZIndex = panel.ZIndex + UITheme.Z.Content
	costLabel.Parent = panel
	themeLabel(costLabel, 22, UITheme.Color.Cream)

	local oddsScroll = Instance.new("ScrollingFrame")
	oddsScroll.Name = "OddsScroll"
	oddsScroll.Size = UDim2.new(1, -36, 0, 232)
	oddsScroll.Position = UDim2.new(0, 18, 0, 150)
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
	actionRow.Position = UDim2.new(0, 18, 0, 396)
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
	autoButton.Position = UDim2.new(0, 18, 0, 456)
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

		local luck = GameConfig.GetLuckPercent(data) + (egg.luckBonus or 0)
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
				-- two decimals under 1%, because "0%" on a Legendary is a lie the player can disprove
				pct.Text = entry.chance < 1
					and ("%.2f%%"):format(entry.chance)
					or ("%.1f%%"):format(entry.chance)
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

	eggButton.MouseButton1Click:Connect(function()
		-- Selected fresh on every open: the player has almost certainly walked to a different stall
		-- since last time, and reopening on a zone they have left is the same class of bug as a
		-- panel reopening at yesterday's scroll position.
		selectedTier = "Basic"
		refresh()
		toggleOnly(panel)
	end)

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
	-- how many tiles wide each side is. The left column stays single-file: it has three tiles and
	-- sits against the edge the player's eye starts from.
	local WIDTH = { L = 1, R = RIGHT_COLS }

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
	-- This is the ONLY way into fusing -- there is deliberately no HUD button for it any more.
	if which == "fusion" then
		if hudRefs.showFusionPanel then hudRefs.showFusionPanel() end
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
