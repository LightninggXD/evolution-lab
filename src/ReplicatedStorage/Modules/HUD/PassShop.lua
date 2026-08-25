-- PassShop -- the game-pass tab of the Robux shop -- a second tab on the same panel, not a second panel.
--
-- Redesigned (Task 17.15) with a storefront layout: Hero VIP card and a grid for the rest.
local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))

local Remotes = RS.Remotes

local themeLabel, styleCard, styleButton = UIKit.themeLabel, UIKit.styleCard, UIKit.styleButton

return function(hud)
	local robuxGrid, robuxPanel = hud.robuxGrid, hud.robuxPanel

	local promptPass = Remotes:WaitForChild("PromptGamePassPurchase", 10)

	local TAB_H = 40
	local TOP = 94 + TAB_H + 12

	robuxGrid.Position = UDim2.new(0, 16, 0, TOP)
	robuxGrid.Size = UDim2.new(1, -32, 1, -(TOP + 16))

	local tabRow = Instance.new("Frame")
	tabRow.Name = "TabRow"
	tabRow.Size = UDim2.new(1, -32, 0, TAB_H)
	tabRow.Position = UDim2.new(0, 16, 0, 94)
	tabRow.BackgroundTransparency = 1
	tabRow.ZIndex = robuxPanel.ZIndex + UITheme.Z.Content
	tabRow.Parent = robuxPanel

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
		b.Size = UDim2.new(0.5, -12, 1, 0)
		b.LayoutOrder = order
		b.Text = text
		b.Parent = tabRow
		styleButton(b, UITheme.Color.Blue, UDim.new(0, 14))
		return b
	end

	local productsTab = makeTab("Packs", 1)
	local passesTab = makeTab("Passes", 2)

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
	listLayout.Padding = UDim.new(0, 12)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = passScroll
	
	local gridContainer = Instance.new("Frame")
	gridContainer.Name = "GridContainer"
	gridContainer.Size = UDim2.new(1, -12, 0, 0)
	gridContainer.BackgroundTransparency = 1
	gridContainer.LayoutOrder = 2
	gridContainer.AutomaticSize = Enum.AutomaticSize.Y
	gridContainer.Parent = passScroll
	
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0.5, -6, 0, 120)
	gridLayout.CellPadding = UDim2.new(0, 12, 0, 12)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = gridContainer

	local rows = {}

	for i, pass in ipairs(GameConfig.GamePasses) do
		local isVip = pass.vip or pass.key == "VIP"
		
		local row = Instance.new("Frame")
		row.Name = pass.key
		row.LayoutOrder = i
		
		if isVip then
			row.Size = UDim2.new(1, -12, 0, 140)
			row.Parent = passScroll
			row.LayoutOrder = 1
			styleCard(row, UITheme.Color.Gold, UDim.new(0, 16), 4)
			
			local banner = Instance.new("TextLabel")
			banner.Name = "BannerLabel"
			banner.Size = UDim2.new(1, -140, 0, 36)
			banner.Position = UDim2.new(0, 130, 0, 10)
			banner.BackgroundTransparency = 1
			banner.TextXAlignment = Enum.TextXAlignment.Left
			banner.Text = "HERO BUNDLE: " .. pass.name
			banner.Parent = row
			themeLabel(banner, 28)
			
			local descLabel = Instance.new("TextLabel")
			descLabel.Name = "DescLabel"
			descLabel.Size = UDim2.new(1, -140, 0, 80)
			descLabel.Position = UDim2.new(0, 130, 0, 50)
			descLabel.BackgroundTransparency = 1
			descLabel.TextXAlignment = Enum.TextXAlignment.Left
			descLabel.TextYAlignment = Enum.TextYAlignment.Top
			descLabel.TextWrapped = true
			descLabel.Text = pass.desc
			descLabel.Parent = row
			themeLabel(descLabel, 16, UITheme.Color.Cream)
			
			local icon = UITheme.IconSlot(row, {
				name = "Icon", icon = pass.emoji, maxTextSize = 60,
				size = UDim2.new(0, 100, 0, 100), position = UDim2.new(0, 16, 0.5, 0), anchor = Vector2.new(0, 0.5)
			})
			
			local buyButton = Instance.new("TextButton")
			buyButton.Name = "BuyButton"
			buyButton.Size = UDim2.new(0, 140, 0, 50)
			buyButton.Position = UDim2.new(1, -16, 0.5, 0)
			buyButton.AnchorPoint = Vector2.new(1, 0.5)
			buyButton.Text = "R$ " .. pass.price
			buyButton.Parent = row
			styleButton(buyButton, UITheme.Color.Green, UDim.new(1, 0))
			
			buyButton.MouseButton1Click:Connect(function()
				if promptPass then promptPass:FireServer(pass.key) end
			end)
			rows[pass.key] = buyButton
		else
			row.Parent = gridContainer
			local accent = (pass.luckAdd or pass.petSlots) and UITheme.Color.Green or UITheme.Color.Blue
			styleCard(row, accent, UDim.new(0, 12), 4)
			
			local nameLabel = Instance.new("TextLabel")
			nameLabel.Name = "NameLabel"
			nameLabel.Size = UDim2.new(1, -20, 0, 24)
			nameLabel.Position = UDim2.new(0, 10, 0, 10)
			nameLabel.BackgroundTransparency = 1
			nameLabel.TextXAlignment = Enum.TextXAlignment.Center
			nameLabel.Text = pass.name
			nameLabel.Parent = row
			themeLabel(nameLabel, 20)
			
			local icon = UITheme.IconSlot(row, {
				name = "Icon", icon = pass.emoji, maxTextSize = 36,
				size = UDim2.new(0, 44, 0, 44), position = UDim2.new(0.5, 0, 0.5, -4), anchor = Vector2.new(0.5, 0.5)
			})
			
			local buyButton = Instance.new("TextButton")
			buyButton.Name = "BuyButton"
			buyButton.Size = UDim2.new(1, -20, 0, 32)
			buyButton.Position = UDim2.new(0.5, 0, 1, -10)
			buyButton.AnchorPoint = Vector2.new(0.5, 1)
			buyButton.Text = "R$ " .. pass.price
			buyButton.Parent = row
			styleButton(buyButton, UITheme.Color.Green, UDim.new(1, 0))
			
			buyButton.MouseButton1Click:Connect(function()
				if promptPass then promptPass:FireServer(pass.key) end
			end)
			rows[pass.key] = buyButton
		end
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
	hud.selectRobuxTab = selectTab

	hud.refreshPassShop = function()
		local owned = (hud.getData() and hud.getData().Passes) or {}
		for _, pass in ipairs(GameConfig.GamePasses) do
			local button = rows[pass.key]
			if button then
				if owned[pass.key] then
					button.Text = "OWNED"
					button.AutoButtonColor = false
					UITheme.SetColor(button, UITheme.DoneShade(UITheme.Color.Green))
				else
					button.Text = "R$ " .. pass.price
					button.AutoButtonColor = true
					UITheme.SetColor(button, UITheme.Color.Green)
				end
			end
		end
	end

	return {}
end
