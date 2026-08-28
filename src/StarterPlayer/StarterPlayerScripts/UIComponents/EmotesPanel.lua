-- EmotesPanel -- the emote selector panel (S23).
-- Built on ScrollingPanelBuilder.

local RS = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("Remotes")
local GameConfig = require(RS.Modules.GameConfig)

local Builder = require(script.Parent:WaitForChild("ScrollingPanelBuilder"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local EmotesPanel = {}
local panel = nil
local rows = {}

local WHITE = Color3.fromRGB(255, 255, 255)
local READY = { Color3.fromRGB(120, 255, 170), Color3.fromRGB(20, 200, 100) }
local LOCKED = { Color3.fromRGB(180, 180, 180), Color3.fromRGB(100, 100, 100) }
local ACTIVE = { Color3.fromRGB(255, 214, 120), Color3.fromRGB(240, 165, 20) }

local function pastel(c)
	return { c:Lerp(WHITE, 0.30), c:Lerp(WHITE, 0.62) }
end

local function refresh()
	local data = PlayerData.Get()
	if not data then return end

	local owned = data.CosmeticsOwned or {}
	local worn = data.WornCosmetics or {}

	for _, c in ipairs(GameConfig.Cosmetics) do
		if c.type == "Emote" then
			local refs = rows[c.key]
			if refs then
				local isWorn = worn.Emote == c.key
				if isWorn then
					refs.card.SetSubtitle("Playing now")
					refs.card.SetDescription("Move to cancel animation")
					refs.card.Button.SetPrice("STOP")
					refs.card.Button.SetEnabled(true, ACTIVE)
					refs.card.Button.SetColors(ACTIVE)
				else
					refs.card.SetSubtitle("Free emote")
					refs.card.SetDescription("Plays looped character animation")
					refs.card.Button.SetPrice("PLAY")
					refs.card.Button.SetEnabled(true, READY)
					refs.card.Button.SetColors(READY)
				end
			end
		end
	end
end

function EmotesPanel.Init(screenGui)
	if panel then return panel end

	panel = Builder.CreatePanel({
		Parent = screenGui,
		Name = "Emotes",
		Title = "\u{1F44B} EMOTES",
		HeaderIcon = "rbxassetid://17009541315",
		HeaderColors = { Color3.fromRGB(255, 180, 100), Color3.fromRGB(255, 120, 50) },
	})

	local order = 0
	for _, c in ipairs(GameConfig.Cosmetics) do
		if c.type == "Emote" then
			order = order + 1
			local card = panel.AddCard({
				Name = c.key,
				LayoutOrder = order,
				Title = c.emoji .. "  " .. c.name,
				Subtitle = "Free emote",
				Description = "Plays looped character animation",
				Icon = "",
				BackgroundColors = pastel(Color3.fromRGB(255, 210, 150)),
				Buttons = {
					{
						Name = "Do",
						Price = "PLAY",
						Icon = "",
						Colors = READY,
						Callback = function()
							local data = PlayerData.Get()
							if not data then return end
							local owned = data.CosmeticsOwned or {}
							local worn = data.WornCosmetics or {}
							if not owned[c.key] then
								Remotes.CosmeticPurchase:InvokeServer(c.key)
							end
							if worn.Emote == c.key then
								Remotes.CosmeticEquip:InvokeServer("Emote", "")
							else
								Remotes.CosmeticEquip:InvokeServer("Emote", c.key)
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

function EmotesPanel.Toggle()
	if panel then panel.Toggle() end
end

function EmotesPanel.SetOpen(open)
	if panel then panel.SetOpen(open) end
end

function EmotesPanel.IsOpen()
	return panel ~= nil and panel.IsOpen()
end

function EmotesPanel.Refresh()
	if panel then panel.Refresh() end
end

return EmotesPanel
