-- SwordPanel using ScrollingPanelBuilder
local RS = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("Remotes")
local GameConfig = require(RS.Modules.GameConfig)
local SwordPreview = require(RS.Modules:WaitForChild("HUD"):WaitForChild("SwordPreview"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local Builder = require(script.Parent:WaitForChild("ScrollingPanelBuilder"))
local UIKit = require(RS.Modules:WaitForChild("UIKit"))
local formatNumber = UIKit.formatNumber

local SwordPanel = {}
local panel = nil
local rows = {}

local WHITE = Color3.fromRGB(255, 255, 255)
local READY = { Color3.fromRGB(120, 255, 170), Color3.fromRGB(20, 200, 100) }
local DONE = { Color3.fromRGB(255, 214, 120), Color3.fromRGB(240, 165, 20) }
local LOCKED = { Color3.fromRGB(180, 180, 180), Color3.fromRGB(100, 100, 100) }

local function pastel(c, taken)
	local a = taken and 0.68 or 0.30
	local b = taken and 0.86 or 0.62
	return { c:Lerp(WHITE, a), c:Lerp(WHITE, b) }
end

local function refresh()
	local data = PlayerData.Get()
	if not data then return end

	local level = GameConfig.GetSwordLevel(data)
	local diamonds = data.Diamonds or 0
	local maxLevel = GameConfig.MaxSwordLevel
	local nextCost = GameConfig.GetSwordCost(level)
	local maxed = (nextCost == math.huge)

	panel.SetTitle(maxed and "WEAPON - FULLY FORGED" or "WEAPON")
	
	for i, tier in ipairs(GameConfig.Swords) do
		local refs = rows[i]
		if refs then
			if i < level then
				refs.card.SetSubtitle("Forged")
				refs.card.SetDescription(string.format("x%.2f damage", tier.damageMult))
				refs.card.Button.SetPrice("DONE")
				refs.card.Button.SetEnabled(false, DONE)
				refs.card.Button.SetColors(DONE)
				refs.card.SetColors(pastel(tier.color, true))
			elseif i == level then
				refs.card.SetSubtitle("EQUIPPED")
				refs.card.SetDescription(string.format("x%.2f damage", tier.damageMult))
				refs.card.Button.SetPrice("EQUIPPED")
				refs.card.Button.SetEnabled(false, DONE)
				refs.card.Button.SetColors(DONE)
				refs.card.SetColors(pastel(tier.color, false))
			elseif i == level + 1 then
				local affordable = diamonds >= tier.cost
				refs.card.SetSubtitle("Next Upgrade")
				refs.card.SetDescription(string.format("x%.2f damage", tier.damageMult))
				refs.card.Button.SetPrice("💎 " .. formatNumber(tier.cost))
				refs.card.Button.SetEnabled(affordable, affordable and READY or LOCKED)
				if affordable then
					refs.card.Button.SetColors(READY)
				else
					refs.card.Button.SetColors(LOCKED)
				end
				refs.card.SetColors(pastel(tier.color, false))
			else
				refs.card.SetSubtitle(string.format("After %d more", i - level - 1))
				refs.card.SetDescription(string.format("x%.2f damage", tier.damageMult))
				refs.card.Button.SetPrice("💎 " .. formatNumber(tier.cost))
				refs.card.Button.SetEnabled(false, LOCKED)
				refs.card.Button.SetColors(LOCKED)
				refs.card.SetColors(pastel(Color3.fromRGB(150, 150, 150), false))
			end
		end
	end
end

function SwordPanel.Init(screenGui)
	if panel then return panel end

	panel = Builder.CreatePanel({
		Parent = screenGui,
		Name = "Sword",
		Title = "WEAPON",
		HeaderIcon = "rbxassetid://115197317627143",
		HeaderColors = { Color3.fromRGB(255, 215, 0), Color3.fromRGB(200, 150, 0) },
	})

	for i, tier in ipairs(GameConfig.Swords) do
		local card = panel.AddCard({
			Name = "Blade" .. i,
			LayoutOrder = i,
			Title = i .. ". " .. tier.displayName,
			Subtitle = "",
			Description = "",
			Icon = "rbxassetid://115197317627143", -- reserves the 140px gutter for icon/preview
			IconPlate = true,
			BackgroundColors = pastel(tier.color, false),
			Buttons = {
				{
					Name = "Do",
					Price = "LOCKED",
					Icon = "",
					Colors = READY,
					Callback = function()
						Remotes.BuySword:FireServer()
					end,
				},
			},
		})
		
		-- Hide the default flat 2D image icon so the 3D viewport shows cleanly
		local iconImg = card.Instance:FindFirstChild("Icon")
		if iconImg then
			iconImg.ImageTransparency = 1
		end

		-- Attach the 3D blade preview inside the card's icon space
		SwordPreview.Attach(card.Instance, tier, {
			size = 110,
			position = UDim2.new(0, 15, 0.5, 0),
			anchorPoint = Vector2.new(0, 0.5),
			zIndex = card.Instance.ZIndex + 5,
		})

		rows[i] = { card = card }
	end

	panel.OnRefresh(refresh)
	PlayerData.OnChanged(function()
		if panel.IsOpen() then refresh() end
	end)
	refresh()
	return panel
end

function SwordPanel.Toggle()
	if panel then panel.Toggle() end
end

return SwordPanel
