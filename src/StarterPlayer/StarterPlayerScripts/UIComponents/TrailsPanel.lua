-- TrailsPanel -- the speed ladder cosmetic shop and equip menu.
-- Built on ScrollingPanelBuilder (S23).

local RS = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("Remotes")
local GameConfig = require(RS.Modules.GameConfig)

local Builder = require(script.Parent:WaitForChild("ScrollingPanelBuilder"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local UIKit = require(RS.Modules:WaitForChild("UIKit"))
local formatNumber = UIKit.formatNumber

local TrailsPanel = {}
local panel = nil
local rows = {}

local WHITE = Color3.fromRGB(255, 255, 255)
local READY = { Color3.fromRGB(120, 255, 170), Color3.fromRGB(20, 200, 100) }
local LOCKED = { Color3.fromRGB(180, 180, 180), Color3.fromRGB(100, 100, 100) }
local WORN = { Color3.fromRGB(255, 214, 120), Color3.fromRGB(240, 165, 20) }

local function pastel(c)
	return { c:Lerp(WHITE, 0.30), c:Lerp(WHITE, 0.62) }
end

local function refresh()
	local data = PlayerData.Get()
	if not data then return end

	local owned = data.CosmeticsOwned or {}
	local worn = data.WornCosmetics or {}
	local shards = data.EvolutionShards or 0

	for _, c in ipairs(GameConfig.Cosmetics) do
		if c.type == "Trail" then
			local refs = rows[c.key]
			if refs then
				local isOwned = owned[c.key] == true
				local isWorn = worn.Trail == c.key
				local speed = c.speedPct or 0

				refs.card.SetSubtitle(("+%d%% walk speed"):format(speed))

				if isOwned then
					if isWorn then
						refs.card.SetDescription("Equipped on your character")
						refs.card.Button.SetPrice("UNEQUIP")
						refs.card.Button.SetEnabled(true, LOCKED)
						refs.card.Button.SetColors(LOCKED)
					else
						refs.card.SetDescription("Owned")
						refs.card.Button.SetPrice("EQUIP")
						refs.card.Button.SetEnabled(true, READY)
						refs.card.Button.SetColors(READY)
					end
				else
					local price, currency = GameConfig.GetCosmeticPrice(c)
					local affordable = shards >= price
					refs.card.SetDescription("Speed boost cosmetic")
					refs.card.Button.SetPrice(("\u{2728} %s Shards"):format(formatNumber(price)))
					refs.card.Button.SetEnabled(affordable, affordable and READY or LOCKED)
					refs.card.Button.SetColors(affordable and READY or LOCKED)
				end
			end
		end
	end
end

function TrailsPanel.Init(screenGui)
	if panel then return panel end

	panel = Builder.CreatePanel({
		Parent = screenGui,
		Name = "Trails",
		Title = "\u{2728} TRAILS",
		HeaderIcon = "rbxassetid://17009541315",
		HeaderColors = { Color3.fromRGB(175, 138, 250), Color3.fromRGB(120, 80, 200) },
	})

	local order = 0
	for _, c in ipairs(GameConfig.Cosmetics) do
		if c.type == "Trail" then
			order = order + 1
			local baseColor = (c.colors and c.colors[1]) or Color3.fromRGB(180, 180, 220)
			local card = panel.AddCard({
				Name = c.key,
				LayoutOrder = order,
				Title = c.name,
				Subtitle = ("+%d%% walk speed"):format(c.speedPct or 0),
				Description = "",
				Icon = "",
				BackgroundColors = pastel(baseColor),
				Buttons = {
					{
						Name = "Do",
						Price = "LOCKED",
						Icon = "",
						Colors = READY,
						Callback = function()
							local data = PlayerData.Get()
							if not data then return end
							local owned = data.CosmeticsOwned or {}
							local worn = data.WornCosmetics or {}
							if owned[c.key] then
								if worn.Trail == c.key then
									Remotes.CosmeticEquip:InvokeServer("Trail", "")
								else
									Remotes.CosmeticEquip:InvokeServer("Trail", c.key)
								end
							else
								Remotes.CosmeticPurchase:InvokeServer(c.key)
							end
						end,
					},
				},
			})
			rows[c.key] = { card = card, c = c }
		end
	end

	panel.OnRefresh(refresh)
	PlayerData.OnChanged(function()
		if panel.IsOpen() then refresh() end
	end)
	refresh()
	return panel
end

function TrailsPanel.Toggle()
	if panel then panel.Toggle() end
end

function TrailsPanel.SetOpen(open)
	if panel then panel.SetOpen(open) end
end

function TrailsPanel.IsOpen()
	return panel ~= nil and panel.IsOpen()
end

function TrailsPanel.Refresh()
	if panel then panel.Refresh() end
end

return TrailsPanel
