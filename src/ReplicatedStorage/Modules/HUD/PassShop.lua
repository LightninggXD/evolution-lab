-- PassShop -- the game-pass tab of the Robux shop -- a second tab on the same panel, not a second panel.
--
-- MOVED OUT OF `MainUI` (18.9), byte for byte. It was already a closed
-- `;(function() ... end)()` block -- the shape this file's 200-register ceiling forces
-- every panel into -- so the extraction is a change of wrapper, not of code. See
-- `docs/SPLIT.md` for the `hud` contract and `docs/CODEMAP.md` for where the rest went.

local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))

local Remotes = RS.Remotes

local themeLabel, styleCard, styleButton = UIKit.themeLabel, UIKit.styleCard, UIKit.styleButton

return function(hud)
	local robuxGrid, robuxPanel = hud.robuxGrid, hud.robuxPanel

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
	passScroll.VerticalScrollBarInset = Enum.ScrollBarInset.Always
	passScroll.ScrollBarThickness = 12
	passScroll.Name = "PassScroll"
	passScroll.Size = UDim2.new(1, -32, 1, -(TOP + 16))
	passScroll.Position = UDim2.new(0, 16, 0, TOP)
	passScroll.BackgroundTransparency = 1
	passScroll.BorderSizePixel = 0
	passScroll.ScrollBarThickness = 12
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
	hud.selectRobuxTab = selectTab

	-- OWNED IS A STATE, NOT A MESSAGE. A pass the player already holds must stop looking like
	-- something to buy -- leaving a live price on it is how a second purchase gets attempted and how
	-- the shop stops being trustworthy.
	hud.refreshPassShop = function()
		local owned = (hud.getData() and hud.getData().Passes) or {}
		for _, pass in ipairs(GameConfig.GamePasses) do
			local button = rows[pass.key]
			if button then
				if owned[pass.key] then
					button.Text = "OWNED"
					button.AutoButtonColor = false
					-- ...AND OWNED IS A RECEIPT, NOT A REFUSAL (18.6). `Color.Locked` is the swatch
					-- this kit uses for "you cannot press this", and it was doing double duty here
					-- for "you already bought this" -- so a shop where the player had spent the most
					-- was the greyest screen in the game. `DoneShade` keeps the hue exactly and
					-- lifts it pale, which is the same three-state split 18.3 made on the Daily
					-- board and 18.6 made on the Season track: full chroma to buy, pale of its own
					-- colour once held, grey only when it genuinely cannot be had.
					UITheme.SetColor(button, UITheme.DoneShade(UITheme.Color.Green))
				else
					button.Text = "R$ " .. pass.price
					button.AutoButtonColor = true
					UITheme.SetColor(button, UITheme.Color.Green)
				end
			end
		end
	end
end
