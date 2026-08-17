local RS = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("Remotes")
local GameConfig = require(RS.Modules:WaitForChild("GameConfig"))
local UITheme = require(RS.Modules:WaitForChild("UITheme"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local InventoryPotionsTab = {}

local WHITE = Color3.fromRGB(255, 255, 255)
local USE = { Color3.fromRGB(120, 255, 170), Color3.fromRGB(20, 200, 100) }
local FALLBACK_ICON = "rbxassetid://138146402871393"

local function pastel(c)
	return { c:Lerp(WHITE, 0.30), c:Lerp(WHITE, 0.62) }
end

local function activeSeconds(data, kind)
	local boost = GameConfig.GetPotionBoost(data, kind)
	if not boost then return 0 end
	return math.max(0, (boost.untilTs or 0) - os.time())
end

local function createStandardRow(parent, layoutOrder, options)
	local card = Instance.new("Frame")
	card.Name = "Row_" .. (options.Name or tostring(layoutOrder))
	card.Size = UDim2.new(1, 0, 0, 80)
	card.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	card.LayoutOrder = layoutOrder
	card.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Color = UITheme.Color.Outline
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = card
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = card

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(
		options.BackgroundColors and options.BackgroundColors[1] or Color3.fromRGB(220, 230, 255),
		options.BackgroundColors and options.BackgroundColors[2] or Color3.fromRGB(180, 200, 255)
	)
	gradient.Parent = card
	
	local grid = Instance.new("ImageLabel")
	grid.Name = "Grid"
	grid.Size = UDim2.new(1, 0, 1, 0)
	grid.BackgroundTransparency = 1
	grid.Image = "rbxassetid://17601461662"
	grid.ImageColor3 = Color3.fromRGB(255, 255, 255)
	grid.ImageTransparency = 0.95
	grid.ScaleType = Enum.ScaleType.Tile
	grid.TileSize = UDim2.new(0, 16, 0, 16)
	grid.ZIndex = 0
	grid.Parent = card

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.new(0, 64, 0, 64)
	icon.Position = UDim2.new(0, 8, 0.5, -32)
	icon.BackgroundTransparency = 1
	icon.Image = options.Icon or ""
	icon.Parent = card

	local iconStroke = Instance.new("UIStroke")
	iconStroke.Color = UITheme.Color.Outline
	iconStroke.Thickness = 3
	iconStroke.Parent = icon

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -200, 0, 30)
	title.Position = UDim2.new(0, 80, 0, 10)
	title.BackgroundTransparency = 1
	title.Text = options.Title or ""
	title.Font = UITheme.Font.Display
	title.TextSize = 24
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = card

	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = UITheme.Color.Outline
	titleStroke.Thickness = 2
	titleStroke.Parent = title

	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.new(1, -200, 0, 20)
	subtitle.Position = UDim2.new(0, 80, 0, 40)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = options.Subtitle or ""
	subtitle.Font = UITheme.Font.Body
	subtitle.TextSize = 16
	subtitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Parent = card
	
	local subStroke = Instance.new("UIStroke")
	subStroke.Color = UITheme.Color.Outline
	subStroke.Thickness = 2
	subStroke.Parent = subtitle

	local buttonSet = {}
	if options.Buttons then
		local rx = -12
		for _, bOpt in ipairs(options.Buttons) do
			local btn = Instance.new("TextButton")
			btn.Size = UDim2.new(0, 100, 0, 40)
			btn.Position = UDim2.new(1, rx - 100, 0.5, -20)
			btn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			btn.Text = bOpt.Price or ""
			btn.Font = UITheme.Font.Display
			btn.TextSize = 20
			btn.TextColor3 = Color3.fromRGB(255, 255, 255)
			btn.Parent = card

			local btnCorner = Instance.new("UICorner")
			btnCorner.CornerRadius = UDim.new(0, 6)
			btnCorner.Parent = btn

			local btnStroke = Instance.new("UIStroke")
			btnStroke.Color = UITheme.Color.Outline
			btnStroke.Thickness = 2
			btnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			btnStroke.Parent = btn

			local btnGrad = Instance.new("UIGradient")
			btnGrad.Rotation = 90
			btnGrad.Color = ColorSequence.new(bOpt.Colors[1], bOpt.Colors[2])
			btnGrad.Parent = btn

			if bOpt.Callback then
				btn.MouseButton1Click:Connect(bOpt.Callback)
			end
			
			buttonSet[bOpt.Name] = btn
			rx = rx - 108
		end
	end

	return { Frame = card, Buttons = buttonSet }
end

function InventoryPotionsTab.Refresh(scrollFrame, currentData)
	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:IsA("Frame") and string.sub(child.Name, 1, 4) == "Row_" then
			child:Destroy()
		end
	end

	local held = currentData.Potions or {}
	local order = 1
	local empty = true

	for _, potion in ipairs(GameConfig.Potions) do
		local count = held[potion.id] or 0
		if count > 0 then
			empty = false
			local left = activeSeconds(currentData, potion.kind)
			
			local card = createStandardRow(scrollFrame, order, {
				Name = potion.id,
				Title = potion.shortName,
				Subtitle = ("%d min \u{2022} x%d held\n%s"):format(potion.minutes, count, potion.blurb),
				Icon = potion.imageId or FALLBACK_ICON,
				BackgroundColors = pastel(potion.color),
				Buttons = {
					{
						Name = "Use",
						Price = left > 0 and "+TIME" or "USE",
						Colors = USE,
						Callback = function() Remotes.UsePotion:FireServer(potion.id) end,
					},
				},
			})
			order = order + 1
		end
	end

	local emptyLabel = scrollFrame:FindFirstChild("EmptyLabel")
	if not emptyLabel then
		emptyLabel = Instance.new("TextLabel")
		emptyLabel.Name = "EmptyLabel"
		emptyLabel.Size = UDim2.new(1, 0, 0, 50)
		emptyLabel.Position = UDim2.new(0, 0, 0.5, -25)
		emptyLabel.BackgroundTransparency = 1
		emptyLabel.Font = UITheme.Font.Display
		emptyLabel.TextSize = 20
		emptyLabel.TextColor3 = Color3.fromRGB(150, 160, 180)
		emptyLabel.Text = "No potions yet \u{2014} buy them at a zone shop"
		emptyLabel.Parent = scrollFrame
	end
	emptyLabel.Visible = empty
	
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, (order - 1) * 85)
end

return InventoryPotionsTab
