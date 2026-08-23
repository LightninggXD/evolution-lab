-- RebirthPanel -- the milestone ladder, in the new panel design.
--
-- A rebirth resets the run and pays a permanent multiplier. There are `GameConfig.MaxRebirths` of
-- them -- TWENTY since 32.7, up from four -- each gated behind a LEVEL rather than a stage (see
-- `GameConfig.Levels`), each spent once, and then the ladder ends -- so this panel is a LADDER of
-- rows rather than a repeating button, and every row can say which of the three states it is in:
-- taken, next, or still out of reach.
--
-- EVERYTHING DERIVES FROM `CanRebirthNow` AND `GetNextRebirthTier`, the two functions the server
-- and the shrine also use. That is deliberate and it is the rule that keeps this panel honest: the
-- button can never offer something `HandleRebirth` will refuse, because it is asking the same
-- question with the same code.
--
-- A TAKEN RUNG IS NOT A DISABLED ONE. It keeps its own colour at reduced chroma and says what it
-- paid; only a rung that genuinely cannot be pressed yet takes the refusal grey. Painting an
-- achievement the colour of a refusal is the fault 18.3 and 18.4 were both about, and a fresh panel
-- is exactly where it comes back.
--
-- WHAT IT COSTS IS NAMED, NOT IMPLIED. The old rebirth screen listed a price and never once named
-- the thing being bought, which is why a rebirth read as a punishment. Each row carries both: the
-- multiplier it grants, and the reset it charges.

local RS = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("Remotes")
local GameConfig = require(RS.Modules.GameConfig)

local Builder = require(script.Parent:WaitForChild("ScrollingPanelBuilder"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local RebirthPanel = {}
local panel = nil
local rungs = {}

local WHITE = Color3.fromRGB(255, 255, 255)
local READY = { Color3.fromRGB(120, 255, 170), Color3.fromRGB(20, 200, 100) }
local DONE = { Color3.fromRGB(255, 214, 120), Color3.fromRGB(240, 165, 20) }

-- One hue per rung, so the ladder reads as distinct steps rather than a column of copies.
-- WRAPPED, NOT INDEXED (32.7): the ladder is twenty rungs and this palette is four, and an
-- unwrapped `RUNG_HUE[tier]` would hand `pastel` a nil on rung five -- a hard error inside the
-- build loop, which takes the whole panel down with it.
local RUNG_HUE = {
	Color3.fromRGB(105, 205, 250),
	Color3.fromRGB(120, 235, 165),
	Color3.fromRGB(175, 138, 250),
	Color3.fromRGB(255, 200, 90),
}

local function hueFor(tier)
	return RUNG_HUE[((tier - 1) % #RUNG_HUE) + 1]
end

local function pastel(c, taken)
	-- a taken rung keeps its hue and loses most of its chroma -- the `DoneShade` idea from 18.3,
	-- which is "a finished thing is not a disabled thing"
	local a = taken and 0.68 or 0.30
	local b = taken and 0.86 or 0.62
	return { c:Lerp(WHITE, a), c:Lerp(WHITE, b) }
end

local function refresh()
	local data = PlayerData.Get()
	if not data then return end

	local done = data.Rebirths or 0
	local ready = GameConfig.CanRebirthNow(data)
	local nextTier = GameConfig.GetNextRebirthTier(data)

	-- THE GATE IS A LEVEL SINCE 32.7. It is read from `RebirthLevelFor`, the same function the
	-- server's `CanRebirthNow` asks -- which is this panel's own rule (see the header): the button
	-- can never offer something `HandleRebirth` will refuse, because it is asking the same
	-- question with the same code.
	local level = GameConfig.GetLevel(data)

	for tier, row in ipairs(rungs) do
		local gateLevel = GameConfig.RebirthLevelFor(tier)

		if tier <= done then
			-- TAKEN. Saves from before the ladder existed hold more rebirths than there are rungs
			-- (the owner's test save has eight), which is why this is `<=` and not `==`: every rung
			-- up to the count reads as taken rather than the panel showing "8 / 4".
			row.card.SetSubtitle("Taken")
			row.card.SetDescription(("Permanent  ·  x%.2f damage  ·  x%.2f income")
				:format(GameConfig.GetRebirthDamageMult({ Rebirths = tier }),
					GameConfig.GetRebirthIncomeMult({ Rebirths = tier })))
			row.card.SetColors(pastel(hueFor(tier), true))
			row.card.Button.SetPrice("DONE")
			row.card.Button.SetEnabled(false, DONE)
			row.card.Button.SetColors(DONE)
		elseif tier == nextTier and ready then
			row.card.SetSubtitle("Ready now")
			row.card.SetDescription("Resets your stage, zones and collection")
			row.card.SetColors(pastel(hueFor(tier), false))
			row.card.Button.SetPrice("REBIRTH")
			row.card.Button.SetEnabled(true, READY)
		else
			row.card.SetSubtitle(("Reach Level %d"):format(gateLevel))
			-- THE DISTANCE, NOT JUST THE POSITION. "You are Level 12" leaves the player to do the
			-- subtraction on every row of a twenty-row ladder; the levels still to go is the one
			-- number any of those rows is actually asking for.
			row.card.SetDescription(("Level %d  \u{00B7}  %d to go"):format(level, math.max(gateLevel - level, 0)))
			row.card.SetColors(pastel(hueFor(tier), false))
			row.card.Button.SetPrice("LOCKED")
			row.card.Button.SetEnabled(false)
		end
	end

	panel.SetTitle(done >= GameConfig.MaxRebirths and "REBIRTH — COMPLETE" or "REBIRTH")
end

function RebirthPanel.Init(screenGui)
	if panel then return panel end

	panel = Builder.CreatePanel({
		Parent = screenGui,
		Name = "Rebirth",
		Title = "REBIRTH",
		HeaderIcon = "rbxassetid://17009541315", -- her rebirth arrows
		HeaderColors = { Color3.fromRGB(255, 160, 120), Color3.fromRGB(230, 70, 90) },
	})

	for tier = 1, GameConfig.MaxRebirths do
		local card = panel.AddCard({
			Name = "Rebirth" .. tier,
			LayoutOrder = tier,
			Title = "Rebirth " .. tier,
			Subtitle = "",
			Description = "",
			Icon = "rbxassetid://17009541315",
			BackgroundColors = pastel(hueFor(tier), false),
			Buttons = {
				{
					Name = "Do",
					Price = "LOCKED",
					Icon = "",
					Colors = READY,
					-- the tier is sent, and `HandleRebirth` re-asks `CanRebirthNow` before it
					-- touches the save -- so a stale card cannot buy a rung twice
					Callback = function()
						Remotes.Rebirth:FireServer(tier)
						panel.SetOpen(false)
					end,
				},
			},
		})
		rungs[tier] = { card = card }
	end

	panel.OnRefresh(refresh)
	PlayerData.OnChanged(function()
		if panel.IsOpen() then refresh() end
	end)
	refresh()
	return panel
end

function RebirthPanel.Toggle()
	if panel then panel.Toggle() end
end

return RebirthPanel
