-- ZonePanel -- the teleport list, in the new panel design.
--
-- WHAT IT REPLACED, and why the difference matters: the first version of this file drew three
-- hard-coded cards reading "Stage 1", "Stage 2", "Stage 3" whose buttons called
-- `print("Teleport to Stage 1")`. There are TWENTY-ONE zones and the button has to reach
-- `Remotes.TeleportToZone`, which is the only thing that actually moves a player.
--
-- WHAT DECIDES A ROW: `GameConfig.Zones` for the membership and the copy, and the live save for
-- the state. A zone is reachable when it is in `UnlockedZones`; when it is not, there are two
-- possible reasons and the row names the one actually in the way -- the stage requirement, or the
-- previous zone's boss. That distinction is not cosmetic: a player at the right stage who reads
-- "Requires: Bacteria" while the top bar says "Bacteria" concludes the panel is broken.
--
-- THE CARDS ARE BUILT ONCE AND UPDATED, never rebuilt. Membership is fixed at twenty-one, and a
-- rebuild on every `DataUpdate` would throw the scroll position away every three seconds.
--
-- THE ZONE'S COLOUR IS PASTELLED BEFORE IT IS USED. `zone.accentColor` is the zone's WORLD colour
-- and terrain is allowed to be near-black -- Forest is a deep pine, Ocean a midnight navy. Handed
-- straight to a card it makes a list of twenty near-black bars. Blended toward white the hue
-- survives and the rows still tell apart. This is the rule the old panel already followed
-- (`evolution-lab-village-contrast-rule` is the same idea in the world).

local RS = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("Remotes")
local GameConfig = require(RS.Modules.GameConfig)

local Builder = require(script.Parent:WaitForChild("ScrollingPanelBuilder"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local ZonePanel = {}
local panel = nil
local rows = {}

local WHITE = Color3.fromRGB(255, 255, 255)
local GO = { Color3.fromRGB(120, 255, 170), Color3.fromRGB(20, 200, 100) }
local HERE = { Color3.fromRGB(255, 214, 120), Color3.fromRGB(240, 165, 20) }

local function pastel(c)
	return { c:Lerp(WHITE, 0.52), c:Lerp(WHITE, 0.74) }
end

--- Why this zone is not reachable yet, as a sentence, naming the blocker actually in the way.
local function lockReason(zone, data)
	local reqStage = GameConfig.Stages[zone.unlockStageIndex]
	local stageName = reqStage and reqStage.name or "?"
	if (data.StageIndex or 1) < zone.unlockStageIndex then
		return "Requires: " .. stageName
	end
	if zone.requiresBossKey then
		local beaten = false
		for _, k in ipairs(data.DefeatedBosses or {}) do
			if k == zone.requiresBossKey then beaten = true break end
		end
		if not beaten then
			local prev = GameConfig.GetZoneByKey(zone.requiresBossKey)
			return "Beat the " .. ((prev and prev.name) or zone.requiresBossKey) .. " boss"
		end
	end
	return "Requires: " .. stageName
end

local function refresh()
	local data = PlayerData.Get()
	if not data then return end

	local unlocked = {}
	for _, k in ipairs(data.UnlockedZones or {}) do unlocked[k] = true end
	local here = data.CurrentZone

	for _, zone in ipairs(GameConfig.Zones) do
		local row = rows[zone.key]
		if row then
			local isHere = (zone.key == here)
			if isHere then
				row.card.SetSubtitle("You are here")
				row.card.Button.SetPrice("HERE")
				row.card.Button.SetEnabled(false, HERE)
				-- amber rather than the disabled grey: this button is not refusing, it has
				-- nothing left to do
				row.card.Button.SetColors(HERE)
			elseif unlocked[zone.key] then
				row.card.SetSubtitle(zone.incomeBonusPct > 0
					and ("Unlocked  ·  +" .. zone.incomeBonusPct .. "% income")
					or "Unlocked")
				row.card.Button.SetPrice("GO")
				row.card.Button.SetEnabled(true, GO)
			else
				row.card.SetSubtitle(lockReason(zone, data))
				row.card.Button.SetPrice("LOCKED")
				row.card.Button.SetEnabled(false)
			end
		end
	end
end

function ZonePanel.Init(screenGui)
	if panel then return panel end

	panel = Builder.CreatePanel({
		Parent = screenGui,
		Name = "Teleport",
		Title = "TELEPORT",
		HeaderIcon = "rbxassetid://12600727274", -- her bag art; a map/portal icon would be better
		HeaderColors = { Color3.fromRGB(255, 150, 255), Color3.fromRGB(255, 50, 200) },
	})

	for i, zone in ipairs(GameConfig.Zones) do
		local card = panel.AddCard({
			Name = zone.key,
			LayoutOrder = i,
			Title = zone.name,
			Subtitle = "",
			-- the zone's own income line, which is the reason to go there at all
			Description = zone.incomeBonusPct > 0 and (zone.emoji .. "  Zone " .. i) or (zone.emoji .. "  Starting zone"),
			Icon = "",  -- per-zone art is not uploaded yet; the emoji carries it in Description
			BackgroundColors = pastel(zone.accentColor),
			Buttons = {
				{
					Name = "Go",
					Price = "GO",
					Icon = "",
					Colors = GO,
					-- The server decides. `HandleTeleportRequest` re-checks the unlock and answers
					-- a refused press with its own reason, so the worst a stale card can do is
					-- send a request that is politely declined -- never a free teleport.
					Callback = function()
						Remotes.TeleportToZone:FireServer(zone.key)
						panel.SetOpen(false)
					end,
				},
			},
		})
		rows[zone.key] = { card = card, zone = zone }
	end

	panel.OnRefresh(refresh)
	PlayerData.OnChanged(function()
		-- only while somebody is looking: twenty-one cards restyled every three seconds for a
		-- hidden panel is the cost this game already has twenty of
		if panel.IsOpen() then refresh() end
	end)
	refresh()
	return panel
end

function ZonePanel.Toggle()
	if panel then panel.Toggle() end
end

return ZonePanel
