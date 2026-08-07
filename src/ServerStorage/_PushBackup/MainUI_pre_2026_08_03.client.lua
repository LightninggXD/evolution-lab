local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(RS.Modules.GameConfig)
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
	return string.format("%.2f%s", n, suffixes[mag])
end

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(0, 12)
	c.Parent = parent
	return c
end

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

local OUTLINE_COLOR = UITheme.Color.Outline
local DISPLAY_FONT = UITheme.Font.Display
local PANEL_SHELL = Color3.fromRGB(48, 42, 72)

local function shade(c, amt)
	return UITheme.Shade(c, amt)
end

local function gradientForColor(baseColor)
	return UITheme.GradientFor(baseColor)
end

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
	end
	if not label:FindFirstChildOfClass("UIStroke") then
		UITheme.OutlineText(label, 3)
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

	local strokeInst = Instance.new("UIStroke")
	strokeInst.Thickness = thickness or 4
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

	local lip = Instance.new("Frame")
	lip.Name = "Shadow"
	lip.BackgroundColor3 = UITheme.Shade(baseColor, -0.55)
	lip.BorderSizePixel = 0
	lip.AnchorPoint = Vector2.new(0.5, 1)
	lip.Position = UDim2.new(0.5, 0, 1, 0)
	lip.Size = UDim2.new(1, 0, 0, 6)
	lip.ZIndex = inst.ZIndex
	lip:SetAttribute("IsLip", true)
	corner(lip, cornerRadius)
	lip.Parent = inst

	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.BackgroundColor3 = UITheme.Color.White
	gloss.BackgroundTransparency = 0.76 -- invariant: >= 0.72
	gloss.BorderSizePixel = 0
	gloss.Size = UDim2.new(0.84, 0, 0.32, 0)
	gloss.Position = UDim2.new(0.08, 0, 0.07, 0)
	gloss.ZIndex = inst.ZIndex + UITheme.Z.Gloss
	corner(gloss, UDim.new(1, 0))
	local glossGrad = gradient(gloss, ColorSequence.new(UITheme.Color.White), 90)
	glossGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.7, 0.92),
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

		-- press feedback: shell sinks 3px, lip shrinks
		local lip = btn:FindFirstChild("Shadow")
		local resting = btn.Position
		local pressed = false
		btn.MouseButton1Down:Connect(function()
			if pressed then return end
			pressed = true
			resting = btn.Position
			btn.Position = resting + UDim2.new(0, 0, 0, 3)
			if lip then lip.Size = UDim2.new(1, 0, 0, 3) end
		end)
		local function release()
			if not pressed then return end
			pressed = false
			btn.Position = resting
			if lip then lip.Size = UDim2.new(1, 0, 0, 6) end
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
	size = UDim2.new(0, 272, 0, 64),
	position = UDim2.new(0, 20, 0, 14),
	radius = 16,
	maxTextSize = 30,
})
local stageLabel = stageCard.Label

local dnaCard = UITheme.Card(topBar, {
	name = "DNACard",
	text = "🧬 0 DNA",
	color = UITheme.Color.Blue,
	size = UDim2.new(0, 300, 0, 74),
	position = UDim2.new(1, -20, 0, 12),
	anchorPoint = Vector2.new(1, 0),
	radius = 18,
	maxTextSize = 36,
})
local dnaLabel = dnaCard.Label

-- ===== Center hint: how to get DNA now =====
local clickHintLabel = UITheme.Label(screenGui, {
	name = "ClickHint",
	text = "🧬 Use the DNA Machine or fight creatures to collect DNA!",
	size = UDim2.new(0, 560, 0, 32),
	position = UDim2.new(0.5, 0, 0, 22),
	anchorPoint = Vector2.new(0.5, 0),
	maxTextSize = 22,
	zIndex = UITheme.Z.Content,
})

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
local dnaPillValue = dnaPill.Value
local diamondPillValue = diamondPill.Value
local shardPillValue = shardPill.Value

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

local shopTitle = UITheme.Label(shopFrame, {
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

local upgradeOrder = { "Speed", "Income", "Luck", "Mutation", "AutoCollect" }
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

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, -12, 0, 46)
	titleLabel.Position = UDim2.new(0, 6, 0, 8)
	titleLabel.BackgroundTransparency = 1
	titleLabel.TextWrapped = true
	titleLabel.Text = def.emoji .. " " .. def.displayName
	titleLabel.Parent = btn
	themeLabel(titleLabel, 22, Color3.fromRGB(255, 255, 255))

	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "LevelLabel"
	levelLabel.Size = UDim2.new(1, -12, 0, 26)
	levelLabel.Position = UDim2.new(0, 6, 0, 58)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text = "Level 0"
	levelLabel.Parent = btn
	themeLabel(levelLabel, 20, Color3.fromRGB(255, 255, 255))

	local costLabel = Instance.new("TextLabel")
	costLabel.Name = "CostLabel"
	costLabel.Size = UDim2.new(1, -12, 0, 30)
	costLabel.Position = UDim2.new(0, 6, 1, -40)
	costLabel.BackgroundTransparency = 1
	costLabel.Text = "Cost: " .. def.baseCost
	costLabel.Parent = btn
	themeLabel(costLabel, 24, UITheme.Color.Cream)

	btn.MouseButton1Click:Connect(function()
		Remotes.BuyUpgrade:FireServer(key)
	end)

	upgradeButtons[key] = { button = btn, levelLabel = levelLabel, costLabel = costLabel }
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
-- Two columns of chunky IconTiles (caption BELOW the tile) plus a bottom-right quick row.
-- Only one floating panel is shown at a time -- opening one closes the others.
local togglePanels = {}
local function registerPanel(panel)
	-- Floating panels live at screen centre now; the tile columns own the screen edges.
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	table.insert(togglePanels, panel)
end
local function toggleOnly(panel)
	local wasVisible = panel.Visible
	for _, p in ipairs(togglePanels) do
		p.Visible = false
	end
	panel.Visible = not wasVisible
end

local TILE_SIZE = UDim2.new(0, 78, 0, 78)
local TILE_PITCH = 92
local TILE_START_Y = 96 -- clears the Roblox topbar inset
local PANEL_ANCHOR = UDim2.new(0.5, 0, 0.5, 0)

local function columnTile(side, order, emoji, caption, color, badge, badgeColor)
	local opts = {
		name = caption .. "Button",
		icon = emoji,
		caption = caption,
		color = color,
		size = TILE_SIZE,
		radius = 16,
		badge = badge,
		badgeColor = badgeColor,
	}
	if side == "L" then
		opts.position = UDim2.new(0, 20, 0, TILE_START_Y + (order - 1) * TILE_PITCH)
		opts.anchorPoint = Vector2.new(0, 0)
	else
		opts.position = UDim2.new(1, -20, 0, TILE_START_Y + (order - 1) * TILE_PITCH)
		opts.anchorPoint = Vector2.new(1, 0)
	end
	return UITheme.IconTile(screenGui, opts)
end

-- LEFT column
local inventoryButton  = columnTile("L", 1, "🧪", "Inventory", UITheme.Color.Green)
local shopToggleButton = columnTile("L", 2, "🛒", "Shop", UITheme.Color.Gold, "FREE!", UITheme.Color.Green)
local petsButton       = columnTile("L", 3, "🐾", "Pets", UITheme.Color.Pink)
local rebirthButton    = columnTile("L", 4, "♻️", "Rebirth", UITheme.Color.Purple)

-- RIGHT column (right-aligned)
local zonesButton  = columnTile("R", 1, "🗺️", "Zones", UITheme.Color.Blue)
local rewardButton = columnTile("R", 2, "🎁", "Daily", UITheme.Color.Orange, "NEW!", UITheme.Color.Red)
local robuxButton  = columnTile("R", 3, "🛍️", "Robux", UITheme.Color.Green)

-- BOTTOM-RIGHT quick actions
local quickRow = Instance.new("Frame")
quickRow.Name = "QuickRow"
quickRow.Size = UDim2.new(0, 260, 0, 60)
quickRow.Position = UDim2.new(1, -20, 1, -42)
quickRow.AnchorPoint = Vector2.new(1, 1)
quickRow.BackgroundTransparency = 1
quickRow.ZIndex = UITheme.Z.Content
quickRow.Parent = screenGui

local quickLayout = Instance.new("UIListLayout")
quickLayout.FillDirection = Enum.FillDirection.Horizontal
quickLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
quickLayout.VerticalAlignment = Enum.VerticalAlignment.Center
quickLayout.SortOrder = Enum.SortOrder.LayoutOrder
quickLayout.Padding = UDim.new(0, 10)
quickLayout.Parent = quickRow

local function quickTile(order, emoji, caption, color)
	return UITheme.IconTile(quickRow, {
		name = caption .. "Button",
		icon = emoji,
		caption = caption,
		color = color,
		size = UDim2.new(0, 60, 0, 60),
		radius = 14,
		layoutOrder = order,
		zIndex = UITheme.Z.Content,
	})
end

local playtimeButton = quickTile(1, "⏰", "Gifts", UITheme.Color.Orange)
local potionQuickButton = quickTile(2, "🧪", "Potion", UITheme.Color.SkyBlue)
potionQuickButton.MouseButton1Click:Connect(function()
	Remotes.UsePotion:FireServer()
end)

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
		panel.Visible = false
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
	goButton.Text = "🔒"
	goButton.Parent = row
	styleButton(goButton, UITheme.Color.Locked, UDim.new(1, 0))

	goButton.MouseButton1Click:Connect(function()
		Remotes.TeleportToZone:FireServer(zone.key)
	end)

	zoneRows[zone.key] = { statusLabel = statusLabel, goButton = goButton }
	zonesScroll.CanvasSize = UDim2.new(0, 0, 0, i * 74)
end

zonesButton.MouseButton1Click:Connect(function()
	toggleOnly(zonesPanel)
end)

-- ===== Pets panel =====
local petsPanel = Instance.new("Frame")
petsPanel.Name = "PetsPanel"
petsPanel.Size = UDim2.new(0, 460, 0, 500)
petsPanel.Position = PANEL_ANCHOR
petsPanel.ZIndex = 20
petsPanel.Visible = false
petsPanel.Parent = screenGui
styleCard(petsPanel, PANEL_SHELL, UDim.new(0, 22), 5)
registerPanel(petsPanel)
panelClose(petsPanel)

local petsPanelTitle = Instance.new("TextLabel")
petsPanelTitle.Name = "TitleLabel"
petsPanelTitle.Size = UDim2.new(1, -80, 0, 38)
petsPanelTitle.Position = UDim2.new(0, 18, 0, 10)
petsPanelTitle.BackgroundTransparency = 1
petsPanelTitle.TextXAlignment = Enum.TextXAlignment.Left
petsPanelTitle.Text = "🐾 Pets (0/" .. GameConfig.MaxEquippedPets .. " equipped)"
petsPanelTitle.Parent = petsPanel
themeLabel(petsPanelTitle, 28)

-- Info row: eggs are no longer buyable from this tab -- each zone has its own physical
-- Pet Shop kiosk that sells that zone's egg, walk up to it and use the prompt there.
local eggShopFrame = Instance.new("Frame")
eggShopFrame.Name = "EggShopFrame"
eggShopFrame.Size = UDim2.new(1, -28, 0, 54)
eggShopFrame.Position = UDim2.new(0, 14, 0, 54)
eggShopFrame.Parent = petsPanel
styleCard(eggShopFrame, UITheme.Color.Pink, UDim.new(0, 14), 4)

local eggInfoLabel = Instance.new("TextLabel")
eggInfoLabel.Size = UDim2.new(1, -20, 1, -10)
eggInfoLabel.Position = UDim2.new(0, 10, 0, 4)
eggInfoLabel.BackgroundTransparency = 1
eggInfoLabel.TextWrapped = true
eggInfoLabel.Text = "🐾 Visit the Pet Shop in each zone to buy that zone's egg!"
eggInfoLabel.Parent = eggShopFrame
themeLabel(eggInfoLabel, 19)

-- Owned pets scroll list
local petsScroll = Instance.new("ScrollingFrame")
petsScroll.Name = "PetsScroll"
petsScroll.Size = UDim2.new(1, -28, 1, -128)
petsScroll.Position = UDim2.new(0, 14, 0, 116)
petsScroll.BackgroundTransparency = 1
petsScroll.BorderSizePixel = 0
petsScroll.ScrollBarThickness = 6
petsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
petsScroll.Parent = petsPanel

local petsListLayout = Instance.new("UIListLayout")
petsListLayout.Padding = UDim.new(0, 6)
petsListLayout.SortOrder = Enum.SortOrder.LayoutOrder
petsListLayout.Parent = petsScroll

local petsEmptyLabel = Instance.new("TextLabel")
petsEmptyLabel.Name = "EmptyLabel"
petsEmptyLabel.Size = UDim2.new(1, 0, 0, 44)
petsEmptyLabel.BackgroundTransparency = 1
petsEmptyLabel.TextWrapped = true
petsEmptyLabel.Text = "No pets yet — visit a Pet Shop in any zone!"
petsEmptyLabel.LayoutOrder = 0
petsEmptyLabel.Parent = petsScroll
themeLabel(petsEmptyLabel, 20, UITheme.Color.Cream)

petsButton.MouseButton1Click:Connect(function()
	toggleOnly(petsPanel)
end)

local function petDisplayInfo(petKey)
	for _, p in ipairs(GameConfig.Pets) do
		if p.key == petKey then return p end
	end
	return { name = petKey, emoji = "❓" }
end

local function refreshPetsPanel()
	if not currentData then return end
	local data = currentData

	petsPanelTitle.Text = string.format("🐾 Pets (%d/%d equipped)", #data.EquippedPetIds, GameConfig.MaxEquippedPets)

	-- clear old rows (keep the empty label instance to reuse)
	for _, child in ipairs(petsScroll:GetChildren()) do
		if child:IsA("Frame") and child.Name == "PetRow" then
			child:Destroy()
		end
	end

	petsEmptyLabel.Visible = (#data.Pets == 0)

	local equippedLookup = {}
	for _, id in ipairs(data.EquippedPetIds) do equippedLookup[id] = true end

	-- count duplicates per key+tier to know when Fuse is available
	local dupCounts = {}
	for _, pet in ipairs(data.Pets) do
		local groupKey = pet.key .. "|" .. pet.tier
		dupCounts[groupKey] = (dupCounts[groupKey] or 0) + 1
	end

	for i, pet in ipairs(data.Pets) do
		local info = petDisplayInfo(pet.key)
		local tierColor = GameConfig.PetTierColor[pet.tier] or Color3.fromRGB(255,255,255)
		local isEquipped = equippedLookup[pet.id] == true

		local row = Instance.new("Frame")
		row.Name = "PetRow"
		row.LayoutOrder = i
		row.Size = UDim2.new(1, 0, 0, 60)
		row.BackgroundColor3 = Color3.fromRGB(35, 32, 45)
		row.BackgroundTransparency = 0.2
		row.Parent = petsScroll
		corner(row, UDim.new(0, 10))
		stroke(row, 2, tierColor)

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(0.5, 0, 0, 22)
		nameLabel.Position = UDim2.new(0, 10, 0, 5)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 15
		nameLabel.TextColor3 = Color3.fromRGB(255,255,255)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Text = info.emoji .. " " .. info.name
		nameLabel.Parent = row

		local tierLabel = Instance.new("TextLabel")
		tierLabel.Size = UDim2.new(0.5, 0, 0, 16)
		tierLabel.Position = UDim2.new(0, 10, 0, 27)
		tierLabel.BackgroundTransparency = 1
		tierLabel.Font = Enum.Font.Gotham
		tierLabel.TextSize = 12
		tierLabel.TextColor3 = tierColor
		tierLabel.TextXAlignment = Enum.TextXAlignment.Left
		tierLabel.Text = pet.tier .. (isEquipped and " · Equipped" or "")
		tierLabel.Parent = row

		local equipBtn = Instance.new("TextButton")
		equipBtn.Size = UDim2.new(0, 80, 0, 26)
		equipBtn.Position = UDim2.new(1, -180, 0.5, -13)
		equipBtn.Font = Enum.Font.GothamBold
		equipBtn.TextSize = 12
		local equipBtnColor
		if isEquipped then
			equipBtn.Text = "Unequip"
			equipBtnColor = Color3.fromRGB(200, 90, 90)
		else
			equipBtn.Text = "Equip"
			equipBtnColor = Color3.fromRGB(90, 190, 120)
		end
		equipBtn.Parent = row
		styleButton(equipBtn, equipBtnColor, UDim.new(1, 0))
		equipBtn.MouseButton1Click:Connect(function()
			if isEquipped then
				Remotes.UnequipPet:FireServer(pet.id)
			else
				Remotes.EquipPet:FireServer(pet.id)
			end
		end)

		local groupKey = pet.key .. "|" .. pet.tier
		local nextTier = GameConfig.GetNextTier(pet.tier)
		if nextTier and (dupCounts[groupKey] or 0) >= GameConfig.FuseRequirement then
			local fuseBtn = Instance.new("TextButton")
			fuseBtn.Size = UDim2.new(0, 90, 0, 26)
			fuseBtn.Position = UDim2.new(1, -90, 0.5, -13)
			fuseBtn.Font = Enum.Font.GothamBold
			fuseBtn.TextSize = 12
			fuseBtn.Text = "Fuse → " .. nextTier
			fuseBtn.Parent = row
			styleButton(fuseBtn, Color3.fromRGB(160, 100, 220), UDim.new(1, 0))
			fuseBtn.MouseButton1Click:Connect(function()
				Remotes.FusePet:FireServer(pet.key, pet.tier)
			end)
		end
	end

	petsScroll.CanvasSize = UDim2.new(0, 0, 0, #data.Pets * 66 + 40)
end

local function refreshZonesPanel()
	if not currentData then return end
	local unlockedLookup = {}
	for _, k in ipairs(currentData.UnlockedZones) do unlockedLookup[k] = true end
	for _, zone in ipairs(GameConfig.Zones) do
		local refs = zoneRows[zone.key]
		if refs then
			if unlockedLookup[zone.key] then
				refs.statusLabel.Text = "Unlocked" .. (zone.incomeBonusPct > 0 and (" · +" .. zone.incomeBonusPct .. "% income") or "")
				refs.goButton.Text = "Go"
				setButtonColor(refs.goButton, Color3.fromRGB(60, 190, 100))
			else
				local reqStage = GameConfig.Stages[zone.unlockStageIndex]
				refs.statusLabel.Text = "Requires: " .. (reqStage and reqStage.name or "?")
				refs.goButton.Text = "🔒"
				setButtonColor(refs.goButton, Color3.fromRGB(80, 80, 90))
			end
		end
	end
end

-- ===== Rebirth panel =====
local rebirthPanel = Instance.new("Frame")
rebirthPanel.Name = "RebirthPanel"
rebirthPanel.Size = UDim2.new(0, 340, 0, 270)
rebirthPanel.Position = PANEL_ANCHOR
rebirthPanel.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
rebirthPanel.BackgroundTransparency = 0.05
rebirthPanel.Visible = false
rebirthPanel.Parent = screenGui
corner(rebirthPanel)
stroke(rebirthPanel, 2, Color3.fromRGB(190, 120, 255))
registerPanel(rebirthPanel)

local rebirthTitle = Instance.new("TextLabel")
rebirthTitle.Size = UDim2.new(1, -20, 0, 30)
rebirthTitle.Position = UDim2.new(0, 10, 0, 8)
rebirthTitle.BackgroundTransparency = 1
rebirthTitle.Font = Enum.Font.GothamBlack
rebirthTitle.TextSize = 20
rebirthTitle.TextColor3 = Color3.fromRGB(255,255,255)
rebirthTitle.TextXAlignment = Enum.TextXAlignment.Left
rebirthTitle.Text = "♻️ Rebirth"
rebirthTitle.Parent = rebirthPanel

local rebirthInfoLabel = Instance.new("TextLabel")
rebirthInfoLabel.Name = "InfoLabel"
rebirthInfoLabel.Size = UDim2.new(1, -20, 0, 58)
rebirthInfoLabel.Position = UDim2.new(0, 10, 0, 40)
rebirthInfoLabel.BackgroundTransparency = 1
rebirthInfoLabel.Font = Enum.Font.Gotham
rebirthInfoLabel.TextSize = 14
rebirthInfoLabel.TextColor3 = Color3.fromRGB(220,220,230)
rebirthInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
rebirthInfoLabel.TextYAlignment = Enum.TextYAlignment.Top
rebirthInfoLabel.TextWrapped = true
rebirthInfoLabel.Text = "Rebirths: 0\nEvolution Shards: 0 (+0% income)"
rebirthInfoLabel.Parent = rebirthPanel

local rebirthReqLabel = Instance.new("TextLabel")
rebirthReqLabel.Name = "ReqLabel"
rebirthReqLabel.Size = UDim2.new(1, -20, 0, 84)
rebirthReqLabel.Position = UDim2.new(0, 10, 0, 100)
rebirthReqLabel.BackgroundTransparency = 1
rebirthReqLabel.Font = Enum.Font.GothamBold
rebirthReqLabel.TextSize = 13
rebirthReqLabel.TextColor3 = Color3.fromRGB(255, 210, 90)
rebirthReqLabel.TextXAlignment = Enum.TextXAlignment.Left
rebirthReqLabel.TextWrapped = true
rebirthReqLabel.Text = "Reach Universe God to rebirth."
rebirthReqLabel.Parent = rebirthPanel

local rebirthActionButton = Instance.new("TextButton")
rebirthActionButton.Name = "ActionButton"
rebirthActionButton.Size = UDim2.new(1, -20, 0, 46)
rebirthActionButton.Position = UDim2.new(0, 10, 1, -56)
rebirthActionButton.Font = Enum.Font.GothamBlack
rebirthActionButton.TextSize = 16
rebirthActionButton.Text = "REBIRTH"
rebirthActionButton.Parent = rebirthPanel
styleButton(rebirthActionButton, Color3.fromRGB(80, 80, 90), UDim.new(1, 0))

rebirthButton.MouseButton1Click:Connect(function()
	toggleOnly(rebirthPanel)
end)

rebirthActionButton.MouseButton1Click:Connect(function()
	Remotes.Rebirth:FireServer()
end)

local function refreshRebirthPanel()
	if not currentData then return end
	local data = currentData
	local shardBonus = GameConfig.GetShardIncomeBonusPct(data.EvolutionShards)
	local tierNow = GameConfig.GetRebirthTier(data.StageIndex)
	rebirthInfoLabel.Text = string.format(
		"Rebirths: %d\nEvolution Shards: %d (+%d%% income)\nRebirth Tier: %d / %d",
		data.Rebirths, data.EvolutionShards, shardBonus, tierNow, GameConfig.MaxRebirthTier
	)

	local canRebirth = data.StageIndex >= GameConfig.RebirthRequirementStageIndex
	local nextShards = GameConfig.GetRebirthShardReward(data.StageIndex, data.Rebirths)
	if canRebirth then
		local nextTierStage = math.min((tierNow + 1) * GameConfig.RebirthTierSize, #GameConfig.Stages)
		local pushHint = ""
		if tierNow < GameConfig.MaxRebirthTier then
			local nextTierStageDef = GameConfig.Stages[nextTierStage]
			local nextTierShards = GameConfig.GetRebirthShardReward(nextTierStage, data.Rebirths)
			pushHint = string.format(" Push to %s %s (Stage %d) for +%d Shards instead!", nextTierStageDef.emoji, nextTierStageDef.name, nextTierStage, nextTierShards)
		end
		rebirthReqLabel.Text = string.format("Ready! Rebirth now for +%d Shards.%s", nextShards, pushHint)
		rebirthActionButton.Text = string.format("REBIRTH (+%d Shards)", nextShards)
		setButtonColor(rebirthActionButton, Color3.fromRGB(190, 120, 255))
	else
		local reqStage = GameConfig.Stages[GameConfig.RebirthRequirementStageIndex]
		rebirthReqLabel.Text = "Reach " .. reqStage.emoji .. " " .. reqStage.name .. " (Stage " .. GameConfig.RebirthRequirementStageIndex .. ") to unlock your first Rebirth. A Rebirth checkpoint exists every 5 stages."
		rebirthActionButton.Text = "REBIRTH (LOCKED)"
		setButtonColor(rebirthActionButton, Color3.fromRGB(80, 80, 90))
	end
end

-- ===== Daily Reward panel (all 7 days at once + big Day 7 card) =====
local rewardPanel = Instance.new("Frame")
rewardPanel.Name = "RewardPanel"
rewardPanel.Size = UDim2.new(0, 630, 0, 430)
rewardPanel.Position = UDim2.new(0.5, -315, 0.5, -215)
rewardPanel.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
rewardPanel.BackgroundTransparency = 0.02
rewardPanel.Visible = false
rewardPanel.Parent = screenGui
corner(rewardPanel, UDim.new(0, 16))
stroke(rewardPanel, 3, Color3.fromRGB(255, 180, 60))
registerPanel(rewardPanel)

local rewardTitle = Instance.new("TextLabel")
rewardTitle.Size = UDim2.new(1, -80, 0, 40)
rewardTitle.Position = UDim2.new(0, 20, 0, 14)
rewardTitle.BackgroundTransparency = 1
rewardTitle.Font = Enum.Font.GothamBlack
rewardTitle.TextSize = 26
rewardTitle.TextColor3 = Color3.fromRGB(255,255,255)
rewardTitle.TextXAlignment = Enum.TextXAlignment.Left
rewardTitle.Text = "📅 Daily Rewards!"
rewardTitle.Parent = rewardPanel

local rewardCloseButton = Instance.new("TextButton")
rewardCloseButton.Size = UDim2.new(0, 36, 0, 36)
rewardCloseButton.Position = UDim2.new(1, -50, 0, 14)
rewardCloseButton.Font = Enum.Font.GothamBlack
rewardCloseButton.TextSize = 18
rewardCloseButton.Text = "X"
rewardCloseButton.Parent = rewardPanel
styleButton(rewardCloseButton, Color3.fromRGB(200, 60, 60), UDim.new(0, 10))

rewardCloseButton.MouseButton1Click:Connect(function()
	rewardPanel.Visible = false
end)

local rewardStreakLabel = Instance.new("TextLabel")
rewardStreakLabel.Name = "StreakLabel"
rewardStreakLabel.Size = UDim2.new(1, -40, 0, 20)
rewardStreakLabel.Position = UDim2.new(0, 20, 0, 52)
rewardStreakLabel.BackgroundTransparency = 1
rewardStreakLabel.Font = Enum.Font.Gotham
rewardStreakLabel.TextSize = 14
rewardStreakLabel.TextColor3 = Color3.fromRGB(200,200,210)
rewardStreakLabel.TextXAlignment = Enum.TextXAlignment.Left
rewardStreakLabel.Text = "Streak: 0 days"
rewardStreakLabel.Parent = rewardPanel

local GRID_X, GRID_Y = 20, 78
local CELL_W, CELL_H, CELL_GAP = 134, 147, 6
local DAY7_W = 170

local rewardCells = {} -- [dayIndex] = { frame, dayLabel, iconLabel, amountLabel, bonusLabel, checkmark, strokeInst, isToday }

local function buildDayCell(dayIndex, size, position, big)
	local reward = GameConfig.DailyRewards[dayIndex]
	local frame = Instance.new("Frame")
	frame.Name = "Day" .. dayIndex
	frame.Size = size
	frame.Position = position
	frame.BackgroundTransparency = 0.05
	frame.Parent = rewardPanel
	local strokeInst = styleCard(frame, Color3.fromRGB(255, 210, 90), UDim.new(0, 16), big and 5 or 4)

	local dayLabel = Instance.new("TextLabel")
	dayLabel.Name = "DayLabel"
	dayLabel.Size = UDim2.new(1, 0, 0, big and 34 or 22)
	dayLabel.Position = UDim2.new(0, 0, 0, 6)
	dayLabel.BackgroundTransparency = 1
	dayLabel.Font = Enum.Font.GothamBlack
	dayLabel.TextSize = big and 24 or 15
	dayLabel.TextColor3 = Color3.fromRGB(255,255,255)
	dayLabel.Text = "Day " .. dayIndex
	dayLabel.Parent = frame

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "IconLabel"
	iconLabel.Size = UDim2.new(1, 0, 0, big and 90 or 50)
	iconLabel.Position = UDim2.new(0, 0, 0, big and 44 or 30)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Font = Enum.Font.GothamBlack
	iconLabel.TextSize = big and 64 or 34
	local icon = "🧬"
	if reward.potions and reward.shards then
		icon = "🌟"
	elseif reward.potions then
		icon = "🧪"
	elseif reward.shards or reward.diamonds then
		icon = "💎"
	end
	iconLabel.Text = icon
	iconLabel.Parent = frame

	local amountLabel = Instance.new("TextLabel")
	amountLabel.Name = "AmountLabel"
	amountLabel.Size = UDim2.new(1, -8, 0, big and 24 or 18)
	amountLabel.Position = UDim2.new(0, 4, 1, big and -70 or -46)
	amountLabel.BackgroundTransparency = 1
	amountLabel.Font = Enum.Font.GothamBold
	amountLabel.TextSize = big and 17 or 13
	amountLabel.TextColor3 = Color3.fromRGB(150, 220, 255)
	amountLabel.TextWrapped = true
	amountLabel.Text = formatNumber(reward.dna) .. " DNA"
	amountLabel.Parent = frame

	local bonusLabel = Instance.new("TextLabel")
	bonusLabel.Name = "BonusLabel"
	bonusLabel.Size = UDim2.new(1, -8, 0, big and 24 or 16)
	bonusLabel.Position = UDim2.new(0, 4, 1, big and -44 or -26)
	bonusLabel.BackgroundTransparency = 1
	bonusLabel.Font = Enum.Font.GothamBold
	bonusLabel.TextSize = big and 16 or 12
	bonusLabel.TextColor3 = Color3.fromRGB(255, 210, 90)
	local bonusParts = {}
	if reward.potions then table.insert(bonusParts, "🧪 x" .. reward.potions) end
	if reward.shards then table.insert(bonusParts, "💎 x" .. reward.shards) end
	if reward.diamonds then table.insert(bonusParts, "💎 x" .. reward.diamonds) end
	bonusLabel.Text = table.concat(bonusParts, "  ")
	bonusLabel.Visible = #bonusParts > 0
	bonusLabel.Parent = frame

	local checkmark = Instance.new("TextLabel")
	checkmark.Name = "Checkmark"
	checkmark.Size = UDim2.new(0, 30, 0, 30)
	checkmark.Position = UDim2.new(1, -34, 0, 4)
	checkmark.BackgroundColor3 = Color3.fromRGB(70, 200, 110)
	checkmark.Font = Enum.Font.GothamBlack
	checkmark.TextSize = 18
	checkmark.TextColor3 = Color3.fromRGB(255,255,255)
	checkmark.Text = "✓"
	checkmark.Visible = false
	checkmark.ZIndex = 6
	checkmark.Parent = frame
	corner(checkmark, UDim.new(1, 0))

	local claimButton = Instance.new("TextButton")
	claimButton.Name = "ClaimButton"
	claimButton.Size = UDim2.new(1, 0, 1, 0)
	claimButton.BackgroundTransparency = 1
	claimButton.Text = ""
	claimButton.ZIndex = 5
	claimButton.Parent = frame
	claimButton.MouseButton1Click:Connect(function()
		local cell = rewardCells[dayIndex]
		if cell and cell.isToday then
			Remotes.ClaimDailyReward:FireServer()
		end
	end)

	rewardCells[dayIndex] = {
		frame = frame, dayLabel = dayLabel, iconLabel = iconLabel,
		amountLabel = amountLabel, bonusLabel = bonusLabel,
		checkmark = checkmark, strokeInst = strokeInst, isToday = false,
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
	UDim2.new(0, GRID_X + 3 * (CELL_W + CELL_GAP) + 10, 0, GRID_Y),
	true
)

local rewardBannerLabel = Instance.new("TextLabel")
rewardBannerLabel.Size = UDim2.new(1, -40, 0, 26)
rewardBannerLabel.Position = UDim2.new(0, 20, 1, -40)
rewardBannerLabel.BackgroundTransparency = 1
rewardBannerLabel.Font = Enum.Font.GothamBold
rewardBannerLabel.TextSize = 15
rewardBannerLabel.TextColor3 = Color3.fromRGB(255,255,255)
rewardBannerLabel.Text = "Come back tomorrow for the next reward!"
rewardBannerLabel.Parent = rewardPanel

rewardButton.MouseButton1Click:Connect(function()
	toggleOnly(rewardPanel)
end)

local SECONDS_PER_DAY = 86400
local function dayNumber(timestamp)
	return math.floor((timestamp or 0) / SECONDS_PER_DAY)
end

local function refreshRewardPanel()
	if not currentData then return end
	local data = currentData
	local today = dayNumber(os.time())
	local lastDay = dayNumber(data.LastRewardClaim)
	local canClaim = today > lastDay
	local streak = data.RewardStreak or 0

	rewardStreakLabel.Text = "Streak: " .. streak .. " day" .. (streak == 1 and "" or "s")

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
			cell.isToday = isToday
			cell.checkmark.Visible = isClaimed
			cell.frame.BackgroundTransparency = isClaimed and 0.45 or 0.05
			if isToday then
				cell.strokeInst.Color = Color3.fromRGB(90, 230, 130)
				cell.strokeInst.Thickness = 5
				cell.dayLabel.Text = "CLAIM!"
				cell.dayLabel.TextColor3 = Color3.fromRGB(255,255,255)
				setButtonColor(cell.frame, Color3.fromRGB(90, 230, 130))
			else
				cell.strokeInst.Color = OUTLINE_COLOR
				cell.strokeInst.Thickness = (d == 7) and 5 or 4
				cell.dayLabel.Text = "Day " .. d
				cell.dayLabel.TextColor3 = Color3.fromRGB(255,255,255)
				setButtonColor(cell.frame, Color3.fromRGB(255, 210, 90))
			end
		end
	end

	if canClaim then
		rewardBannerLabel.Text = "🎉 Day " .. rewardIndex .. " is ready — click it to claim!"
	else
		local nextDay = (streak % #GameConfig.DailyRewards) + 1
		rewardBannerLabel.Text = "Come back tomorrow for Day " .. nextDay .. "!"
	end
end

-- ===== Inventory panel (Potions) =====
local inventoryPanel = Instance.new("Frame")
inventoryPanel.Name = "InventoryPanel"
inventoryPanel.Size = UDim2.new(0, 320, 0, 250)
inventoryPanel.Position = PANEL_ANCHOR
inventoryPanel.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
inventoryPanel.BackgroundTransparency = 0.05
inventoryPanel.Visible = false
inventoryPanel.Parent = screenGui
corner(inventoryPanel)
stroke(inventoryPanel, 2, Color3.fromRGB(120, 220, 160))
registerPanel(inventoryPanel)

local inventoryTitle = Instance.new("TextLabel")
inventoryTitle.Size = UDim2.new(1, -20, 0, 30)
inventoryTitle.Position = UDim2.new(0, 10, 0, 8)
inventoryTitle.BackgroundTransparency = 1
inventoryTitle.Font = Enum.Font.GothamBlack
inventoryTitle.TextSize = 20
inventoryTitle.TextColor3 = Color3.fromRGB(255,255,255)
inventoryTitle.TextXAlignment = Enum.TextXAlignment.Left
inventoryTitle.Text = "🧪 Inventory"
inventoryTitle.Parent = inventoryPanel

local diamondCountLabel = Instance.new("TextLabel")
diamondCountLabel.Size = UDim2.new(1, -20, 0, 24)
diamondCountLabel.Position = UDim2.new(0, 10, 0, 40)
diamondCountLabel.BackgroundTransparency = 1
diamondCountLabel.Font = Enum.Font.GothamBold
diamondCountLabel.TextSize = 16
diamondCountLabel.TextColor3 = Color3.fromRGB(120, 200, 255)
diamondCountLabel.TextXAlignment = Enum.TextXAlignment.Left
diamondCountLabel.Text = "💎 Diamonds: 0"
diamondCountLabel.Parent = inventoryPanel

local potionCountLabel = Instance.new("TextLabel")
potionCountLabel.Size = UDim2.new(1, -20, 0, 26)
potionCountLabel.Position = UDim2.new(0, 10, 0, 66)
potionCountLabel.BackgroundTransparency = 1
potionCountLabel.Font = Enum.Font.GothamBold
potionCountLabel.TextSize = 17
potionCountLabel.TextColor3 = Color3.fromRGB(150, 255, 180)
potionCountLabel.TextXAlignment = Enum.TextXAlignment.Left
potionCountLabel.Text = "🧪 Potions: 0"
potionCountLabel.Parent = inventoryPanel

local potionDescLabel = Instance.new("TextLabel")
potionDescLabel.Size = UDim2.new(1, -20, 0, 40)
potionDescLabel.Position = UDim2.new(0, 10, 0, 94)
potionDescLabel.BackgroundTransparency = 1
potionDescLabel.Font = Enum.Font.Gotham
potionDescLabel.TextSize = 13
potionDescLabel.TextColor3 = Color3.fromRGB(200,200,210)
potionDescLabel.TextWrapped = true
potionDescLabel.Text = string.format("Each Potion gives %dx DNA income for %d minutes.", GameConfig.PotionIncomeMult, GameConfig.PotionDurationSeconds // 60)
potionDescLabel.Parent = inventoryPanel

local potionBoostLabel = Instance.new("TextLabel")
potionBoostLabel.Size = UDim2.new(1, -20, 0, 20)
potionBoostLabel.Position = UDim2.new(0, 10, 0, 136)
potionBoostLabel.BackgroundTransparency = 1
potionBoostLabel.Font = Enum.Font.GothamBold
potionBoostLabel.TextSize = 13
potionBoostLabel.TextColor3 = Color3.fromRGB(255, 210, 90)
potionBoostLabel.Text = ""
potionBoostLabel.Parent = inventoryPanel

local potionUseButton = Instance.new("TextButton")
potionUseButton.Size = UDim2.new(1, -20, 0, 44)
potionUseButton.Position = UDim2.new(0, 10, 1, -54)
potionUseButton.Font = Enum.Font.GothamBlack
potionUseButton.TextSize = 16
potionUseButton.Text = "USE POTION"
potionUseButton.Parent = inventoryPanel
styleButton(potionUseButton, Color3.fromRGB(90, 200, 130), UDim.new(1, 0))

potionUseButton.MouseButton1Click:Connect(function()
	Remotes.UsePotion:FireServer()
end)

inventoryButton.MouseButton1Click:Connect(function()
	toggleOnly(inventoryPanel)
end)

local function refreshInventoryPanel()
	if not currentData then return end
	diamondCountLabel.Text = "💎 Diamonds: " .. (currentData.Diamonds or 0)
	potionCountLabel.Text = "🧪 Potions: " .. (currentData.Potions or 0)
	local remaining = (currentData.PotionBoostUntil or 0) - os.time()
	if remaining > 0 then
		potionBoostLabel.Text = string.format("⚡ Boost active: %dm %ds remaining (%dx income)", remaining // 60, remaining % 60, GameConfig.PotionIncomeMult)
	else
		potionBoostLabel.Text = ""
	end
end

-- keep the boost countdown ticking live while the panel is open
task.spawn(function()
	while true do
		task.wait(1)
		if inventoryPanel.Visible then
			refreshInventoryPanel()
		end
	end
end)

-- ===== Robux Shop panel =====
local robuxPanel = Instance.new("Frame")
robuxPanel.Name = "RobuxPanel"
robuxPanel.Size = UDim2.new(0, 390, 0, 310)
robuxPanel.Position = PANEL_ANCHOR
robuxPanel.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
robuxPanel.BackgroundTransparency = 0.05
robuxPanel.Visible = false
robuxPanel.Parent = screenGui
corner(robuxPanel)
stroke(robuxPanel, 2, Color3.fromRGB(90, 220, 130))
registerPanel(robuxPanel)

local robuxTitle = Instance.new("TextLabel")
robuxTitle.Size = UDim2.new(1, -20, 0, 30)
robuxTitle.Position = UDim2.new(0, 10, 0, 8)
robuxTitle.BackgroundTransparency = 1
robuxTitle.Font = Enum.Font.GothamBlack
robuxTitle.TextSize = 20
robuxTitle.TextColor3 = Color3.fromRGB(255,255,255)
robuxTitle.TextXAlignment = Enum.TextXAlignment.Left
robuxTitle.Text = "🛍️ Robux Shop"
robuxTitle.Parent = robuxPanel

local robuxGrid = Instance.new("Frame")
robuxGrid.Size = UDim2.new(1, -20, 1, -50)
robuxGrid.Position = UDim2.new(0, 10, 0, 44)
robuxGrid.BackgroundTransparency = 1
robuxGrid.Parent = robuxPanel

local robuxLayout = Instance.new("UIGridLayout")
robuxLayout.CellSize = UDim2.new(0, 175, 0, 118)
robuxLayout.CellPadding = UDim2.new(0, 8, 0, 8)
robuxLayout.SortOrder = Enum.SortOrder.LayoutOrder
robuxLayout.Parent = robuxGrid

for i, product in ipairs(GameConfig.RobuxProducts) do
	local card = Instance.new("Frame")
	card.Name = product.key
	card.LayoutOrder = i
	card.BackgroundColor3 = Color3.fromRGB(35, 32, 45)
	card.Parent = robuxGrid
	corner(card, UDim.new(0, 10))
	stroke(card, 2, Color3.fromRGB(90, 220, 130))

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -10, 0, 46)
	nameLabel.Position = UDim2.new(0, 5, 0, 8)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextSize = 15
	nameLabel.TextColor3 = Color3.fromRGB(255,255,255)
	nameLabel.TextWrapped = true
	nameLabel.Text = product.emoji .. " " .. product.name
	nameLabel.Parent = card

	local buyButton = Instance.new("TextButton")
	buyButton.Size = UDim2.new(1, -12, 0, 32)
	buyButton.Position = UDim2.new(0, 6, 1, -40)
	buyButton.Font = Enum.Font.GothamBlack
	buyButton.TextSize = 13
	buyButton.Text = "Buy with R$"
	buyButton.Parent = card
	styleButton(buyButton, Color3.fromRGB(90, 220, 130), UDim.new(1, 0))

	buyButton.MouseButton1Click:Connect(function()
		Remotes.PromptRobuxPurchase:FireServer(product.key)
	end)
end

robuxButton.MouseButton1Click:Connect(function()
	toggleOnly(robuxPanel)
end)

-- ===== Playtime Gifts panel =====
local playtimePanel = Instance.new("Frame")
playtimePanel.Name = "PlaytimePanel"
playtimePanel.Size = UDim2.new(0, 720, 0, 210)
playtimePanel.Position = UDim2.new(0.5, -360, 0.5, -105)
playtimePanel.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
playtimePanel.BackgroundTransparency = 0.03
playtimePanel.Visible = false
playtimePanel.Parent = screenGui
corner(playtimePanel, UDim.new(0, 16))
stroke(playtimePanel, 3, Color3.fromRGB(255, 150, 90))
registerPanel(playtimePanel)

local playtimeTitle = Instance.new("TextLabel")
playtimeTitle.Size = UDim2.new(1, -80, 0, 34)
playtimeTitle.Position = UDim2.new(0, 20, 0, 12)
playtimeTitle.BackgroundTransparency = 1
playtimeTitle.Font = Enum.Font.GothamBlack
playtimeTitle.TextSize = 22
playtimeTitle.TextColor3 = Color3.fromRGB(255,255,255)
playtimeTitle.TextXAlignment = Enum.TextXAlignment.Left
playtimeTitle.Text = "⏰ Playtime Gifts"
playtimeTitle.Parent = playtimePanel

local playtimeCloseButton = Instance.new("TextButton")
playtimeCloseButton.Size = UDim2.new(0, 32, 0, 32)
playtimeCloseButton.Position = UDim2.new(1, -46, 0, 12)
playtimeCloseButton.Font = Enum.Font.GothamBlack
playtimeCloseButton.TextSize = 16
playtimeCloseButton.Text = "X"
playtimeCloseButton.Parent = playtimePanel
styleButton(playtimeCloseButton, Color3.fromRGB(200, 60, 60), UDim.new(0, 10))
playtimeCloseButton.MouseButton1Click:Connect(function()
	playtimePanel.Visible = false
end)

local playtimeSubLabel = Instance.new("TextLabel")
playtimeSubLabel.Size = UDim2.new(1, -40, 0, 20)
playtimeSubLabel.Position = UDim2.new(0, 20, 0, 46)
playtimeSubLabel.BackgroundTransparency = 1
playtimeSubLabel.Font = Enum.Font.Gotham
playtimeSubLabel.TextSize = 13
playtimeSubLabel.TextColor3 = Color3.fromRGB(200,200,210)
playtimeSubLabel.Text = "The longer you stay in this session, the better the gift!"
playtimeSubLabel.Parent = playtimePanel

local PLAYTIME_CELL_W = 128
local playtimeCells = {} -- [index] = { frame, statusLabel, checkmark, strokeInst }

for i, milestone in ipairs(GameConfig.PlaytimeGifts) do
	local frame = Instance.new("Frame")
	frame.Name = "Gift" .. i
	frame.Size = UDim2.new(0, PLAYTIME_CELL_W, 0, 130)
	frame.Position = UDim2.new(0, 20 + (i - 1) * (PLAYTIME_CELL_W + 10), 0, 72)
	frame.Parent = playtimePanel
	local strokeInst = styleCard(frame, Color3.fromRGB(255, 150, 90), UDim.new(0, 16), 4)

	local timeLabel = Instance.new("TextLabel")
	timeLabel.Size = UDim2.new(1, 0, 0, 20)
	timeLabel.Position = UDim2.new(0, 0, 0, 6)
	timeLabel.BackgroundTransparency = 1
	timeLabel.Font = Enum.Font.GothamBlack
	timeLabel.TextSize = 14
	timeLabel.TextColor3 = Color3.fromRGB(255,255,255)
	timeLabel.Text = milestone.minutes .. " min"
	timeLabel.Parent = frame

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Size = UDim2.new(1, 0, 0, 36)
	iconLabel.Position = UDim2.new(0, 0, 0, 28)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Font = Enum.Font.GothamBlack
	iconLabel.TextSize = 28
	iconLabel.Text = milestone.diamonds and "💎" or (milestone.potions and "🧪" or "🧬")
	iconLabel.Parent = frame

	local amountLabel = Instance.new("TextLabel")
	amountLabel.Size = UDim2.new(1, -8, 0, 16)
	amountLabel.Position = UDim2.new(0, 4, 0, 66)
	amountLabel.BackgroundTransparency = 1
	amountLabel.Font = Enum.Font.GothamBold
	amountLabel.TextSize = 12
	amountLabel.TextColor3 = Color3.fromRGB(150, 220, 255)
	amountLabel.Text = formatNumber(milestone.dna) .. " DNA"
	amountLabel.Parent = frame

	local bonusLabel = Instance.new("TextLabel")
	bonusLabel.Size = UDim2.new(1, -8, 0, 16)
	bonusLabel.Position = UDim2.new(0, 4, 0, 84)
	bonusLabel.BackgroundTransparency = 1
	bonusLabel.Font = Enum.Font.GothamBold
	bonusLabel.TextSize = 11
	bonusLabel.TextColor3 = Color3.fromRGB(255, 210, 90)
	local parts = {}
	if milestone.potions then table.insert(parts, "🧪 x" .. milestone.potions) end
	if milestone.diamonds then table.insert(parts, "💎 x" .. milestone.diamonds) end
	bonusLabel.Text = table.concat(parts, " ")
	bonusLabel.Visible = #parts > 0
	bonusLabel.Parent = frame

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Size = UDim2.new(1, -8, 0, 20)
	statusLabel.Position = UDim2.new(0, 4, 1, -26)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.TextSize = 12
	statusLabel.TextColor3 = Color3.fromRGB(200,200,210)
	statusLabel.Text = "Locked"
	statusLabel.Parent = frame

	local checkmark = Instance.new("TextLabel")
	checkmark.Size = UDim2.new(0, 26, 0, 26)
	checkmark.Position = UDim2.new(1, -30, 0, 4)
	checkmark.BackgroundColor3 = Color3.fromRGB(70, 200, 110)
	checkmark.Font = Enum.Font.GothamBlack
	checkmark.TextSize = 15
	checkmark.TextColor3 = Color3.fromRGB(255,255,255)
	checkmark.Text = "✓"
	checkmark.Visible = false
	checkmark.ZIndex = 6
	checkmark.Parent = frame
	corner(checkmark, UDim.new(1, 0))

	local claimButton = Instance.new("TextButton")
	claimButton.Size = UDim2.new(1, 0, 1, 0)
	claimButton.BackgroundTransparency = 1
	claimButton.Text = ""
	claimButton.ZIndex = 5
	claimButton.Parent = frame
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
				cell.statusLabel.TextColor3 = Color3.fromRGB(150, 220, 150)
				cell.strokeInst.Color = OUTLINE_COLOR
				cell.strokeInst.Thickness = 4
				setButtonColor(cell.frame, Color3.fromRGB(255, 150, 90))
			else
				local remaining = milestone.minutes * 60 - elapsedSeconds
				if remaining <= 0 then
					cell.statusLabel.Text = "CLAIM!"
					cell.statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
					cell.strokeInst.Color = Color3.fromRGB(90, 230, 130)
					cell.strokeInst.Thickness = 5
					setButtonColor(cell.frame, Color3.fromRGB(90, 230, 130))
				else
					cell.statusLabel.Text = string.format("in %dm %ds", remaining // 60, remaining % 60)
					cell.statusLabel.TextColor3 = Color3.fromRGB(200,200,210)
					cell.strokeInst.Color = OUTLINE_COLOR
					cell.strokeInst.Thickness = 4
					setButtonColor(cell.frame, Color3.fromRGB(255, 150, 90))
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

-- ===== Notification popup (top-center, stacks) =====
local notifFrame = Instance.new("Frame")
notifFrame.Name = "NotifFrame"
notifFrame.Size = UDim2.new(0, 340, 0, 300)
notifFrame.Position = UDim2.new(0.5, -170, 0, 100)
notifFrame.BackgroundTransparency = 1
notifFrame.Parent = screenGui

local notifLayout = Instance.new("UIListLayout")
notifLayout.Padding = UDim.new(0, 6)
notifLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
notifLayout.SortOrder = Enum.SortOrder.LayoutOrder
notifLayout.Parent = notifFrame

local function showNotification(text, color)
	local notif = Instance.new("TextLabel")
	notif.Size = UDim2.new(0, 320, 0, 34)
	notif.BackgroundColor3 = color or Color3.fromRGB(40,40,50)
	notif.BackgroundTransparency = 0.15
	notif.Font = Enum.Font.GothamBold
	notif.TextSize = 16
	notif.TextColor3 = Color3.fromRGB(255,255,255)
	notif.Text = text
	notif.Parent = notifFrame
	corner(notif)
	task.delay(2.5, function()
		if notif and notif.Parent then
			local tween = TweenService:Create(notif, TweenInfo.new(0.4), { BackgroundTransparency = 1, TextTransparency = 1 })
			tween:Play()
			tween.Completed:Wait()
			notif:Destroy()
		end
	end)
end

-- ================= state updates =================
local function refreshUI()
	if not currentData then return end
	local data = currentData
	local stage = GameConfig.Stages[data.StageIndex]

	stageLabel.Text = stage.emoji .. " " .. stage.name
	dnaLabel.Text = "🧬 " .. formatNumber(data.DNA) .. " DNA"

	if stage.cost == math.huge then
		evolveButton.Text = "MAX EVOLUTION REACHED"
		progressBarFill.Size = UDim2.new(1, 0, 1, 0)
	else
		local dnaPct = math.clamp(data.DNA / stage.cost, 0, 1)
		local xpPct = stage.xpCost > 0 and math.clamp((data.XP or 0) / stage.xpCost, 0, 1) or 1
		progressBarFill.Size = UDim2.new(math.min(dnaPct, xpPct), 0, 1, 0)
		local nextStage = GameConfig.Stages[data.StageIndex + 1]
		evolveButton.Text = string.format("EVOLVE to %s %s (%s/%s DNA, %s/%s XP)", nextStage.emoji, nextStage.name, formatNumber(data.DNA), formatNumber(stage.cost), formatNumber(data.XP or 0), formatNumber(stage.xpCost))
	end

	for key, refs in pairs(upgradeButtons) do
		local level = data.Upgrades[key]
		local cost = GameConfig.GetUpgradeCost(key, level)
		refs.levelLabel.Text = "Level " .. level
		refs.costLabel.Text = "Cost: " .. formatNumber(cost)
	end

	for key, refs in pairs(diamondUpgradeButtons) do
		local def = GameConfig.DiamondUpgrades[key]
		local level = (data.DiamondUpgrades and data.DiamondUpgrades[key]) or 0
		local cost = GameConfig.GetDiamondUpgradeCost(key, level)
		refs.levelLabel.Text = "Level " .. level .. (def.maxLevel and (" / " .. def.maxLevel) or "")
		refs.costLabel.Text = (cost == math.huge) and "MAXED" or ("💎 " .. formatNumber(cost))
	end
end

Remotes.DataUpdate.OnClientEvent:Connect(function(data)
	currentData = data
	refreshUI()
	refreshZonesPanel()
	refreshPetsPanel()
	refreshRebirthPanel()
	refreshRewardPanel()
	refreshInventoryPanel()
end)

Remotes.Notify.OnClientEvent:Connect(function(payload)
	if payload.kind == "crit" then
		showNotification("💥 CRITICAL! +" .. formatNumber(payload.amount) .. " DNA", Color3.fromRGB(255, 200, 60))
	elseif payload.kind == "upgrade" then
		local def = GameConfig.Upgrades[payload.upgrade]
		showNotification("⬆️ " .. def.displayName .. " upgraded to Lv." .. payload.level, Color3.fromRGB(90, 200, 255))
	elseif payload.kind == "evolve" then
		showNotification("🌟 EVOLVED into " .. payload.emoji .. " " .. payload.stage .. "!", Color3.fromRGB(190, 120, 255))
	elseif payload.kind == "mutation" then
		showNotification("🧬 MUTATION: " .. payload.name .. "!", Color3.fromRGB(255, 90, 90))
	elseif payload.kind == "zone" then
		showNotification("🗺️ NEW ZONE UNLOCKED: " .. payload.emoji .. " " .. payload.name .. "!", Color3.fromRGB(60, 160, 220))
	elseif payload.kind == "pet" then
		showNotification("🥚 Hatched a pet: " .. payload.emoji .. " " .. payload.name .. "!", Color3.fromRGB(220, 150, 230))
	elseif payload.kind == "fuse" then
		showNotification("✨ FUSED into " .. payload.tier .. " " .. payload.emoji .. " " .. payload.name .. "!", Color3.fromRGB(160, 100, 220))
	elseif payload.kind == "creature" then
		showNotification("👾 Defeated a creature! +" .. formatNumber(payload.amount) .. " DNA", Color3.fromRGB(90, 220, 130))
	elseif payload.kind == "machine" then
		showNotification("🧬 Machine gave +" .. formatNumber(payload.amount) .. " DNA", Color3.fromRGB(120, 220, 255))
	elseif payload.kind == "playerHurt" then
		showNotification("💢 Ouch! -" .. formatNumber(payload.amount) .. " HP", Color3.fromRGB(220, 80, 80))
	elseif payload.kind == "rebirth" then
		showNotification("♻️ REBIRTH #" .. payload.rebirths .. " (Tier " .. payload.tier .. ")! +" .. payload.shards .. " Evolution Shards", Color3.fromRGB(190, 120, 255))
	elseif payload.kind == "dailyReward" then
		local text = "🎁 Day " .. payload.day .. " reward: +" .. formatNumber(payload.dna) .. " DNA"
		if payload.potions and payload.potions > 0 then
			text = text .. " +" .. payload.potions .. " 🧪"
		end
		if payload.shards and payload.shards > 0 then
			text = text .. " +" .. payload.shards .. " 💎 Shards"
		end
		if payload.diamonds and payload.diamonds > 0 then
			text = text .. " +" .. payload.diamonds .. " 💎 Diamonds"
		end
		showNotification(text, Color3.fromRGB(255, 180, 60))
	elseif payload.kind == "diamondUpgrade" then
		local def = GameConfig.DiamondUpgrades[payload.upgrade]
		showNotification("💎 " .. (def and def.displayName or payload.upgrade) .. " upgraded to Lv." .. payload.level .. "!", Color3.fromRGB(120, 200, 255))
	elseif payload.kind == "potion" then
		local remaining = math.max(0, payload.untilTs - os.time())
		showNotification(string.format("🧪 Potion used! %dx DNA for %dm %ds", GameConfig.PotionIncomeMult, remaining // 60, remaining % 60), Color3.fromRGB(120, 255, 180))
	elseif payload.kind == "playtimeGift" then
		showNotification("⏰ Playtime Gift (" .. payload.minutes .. " min)! Reward claimed!", Color3.fromRGB(255, 150, 90))
	elseif payload.kind == "robuxPurchase" then
		showNotification("🛍️ Purchased: " .. payload.name .. "!", Color3.fromRGB(90, 220, 130))
	elseif payload.kind == "error" then
		showNotification("❌ " .. payload.message, Color3.fromRGB(200, 60, 60))
	end
end)

-- ================= input =================
evolveButton.MouseButton1Click:Connect(function()
	Remotes.Evolve:FireServer()
end)
