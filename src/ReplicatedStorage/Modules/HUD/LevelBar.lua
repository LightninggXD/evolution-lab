-- LevelBar -- the level ladder as one bar, sitting above the evolve card (32.7).
--
-- A HUD MODULE, i.e. a FUNCTION and not a table (`docs/SPLIT.md` §2). It builds its own bar and
-- its own listeners, so **MainUI gains exactly one line and zero top-level locals** -- the whole
-- constraint that file lives under ([[evolution-lab-mainui-register-limit]]).
--
-- ===== TWO BARS, ONE ABOVE THE OTHER, AND THEY MEAN DIFFERENT THINGS =====
--
-- The green one below this is the EVOLVE bar: `data.XP`, filled by kills and SPENT on every evolve.
-- This one is `data.Level` / `data.LevelXp`, filled by damage dealt and reset only by a rebirth. It
-- is deliberately a different colour and it is stacked directly above the thing it is not, because
-- the one way a player misreads this screen is by thinking the top bar is the bottom bar earlier.
-- The caption says LV and a number; the evolve caption says XP and a cost. Neither ever says the
-- other's word.
--
-- ===== IT READS PLAYER ATTRIBUTES, NOT `DataUpdate` =====
--
-- The bar has to move on every blow, and `DataUpdate` carries the whole save table -- firing it
-- three times a second per player would be the most expensive thing on the wire in the game.
-- `LevelService` publishes `Level` and `LevelXp` as PLAYER ATTRIBUTES on a 0.4 s sweep instead
-- (the channel `AutoSpeedMult` and `IsVIP` already use), which replicates one number each and
-- costs nothing while a player is idle.
--
-- `DataUpdate` is still listened to, and it is not redundant: a save that arrives before the first
-- sweep has run -- the join payload -- is what draws the bar for the first time, and a rebirth's
-- push is what snaps it back to zero without waiting.

local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))

local Remotes = RS.Remotes
local formatNumber = UIKit.formatNumber

-- MEASURED OFF THE CARD BELOW IT, NOT TYPED. `EvolveFrame` is 470 x 136 anchored to the bottom at
-- -84, so its top edge is 220 px up; this sits at 226, which is six pixels of daylight and the same
-- gap that card keeps from the QuickBuyRow under it. Same width, because two stacked bars of
-- different widths read as two unrelated things.
local BAR_W, BAR_H = 470, 32
local BAR_BOTTOM = 226

return function(hud)
	local player = Players.LocalPlayer

	local _, fill, label = UITheme.ProgressBar(hud.screenGui, {
		name = "LevelBar",
		size = UDim2.new(0, BAR_W, 0, BAR_H),
		position = UDim2.new(0.5, 0, 1, -BAR_BOTTOM),
		anchorPoint = Vector2.new(0.5, 1),
		-- SkyBlue, and the choice is a negative one: the evolve bar under it is Green and the boss
		-- bar that takes over this band mid-fight is Red, so this is the nearest bright pastel that
		-- neither of them can be mistaken for.
		color = UITheme.Color.SkyBlue,
		text = "LV 1",
		maxTextSize = 19,
		zIndex = 4,
	})

	-- ONE STRING, BUILT IN ONE PLACE, so the bar and its caption can never disagree about which
	-- level is being drawn.
	local function refresh()
		local data = hud.getData()

		-- THE ATTRIBUTE WINS AND THE SAVE IS THE FALLBACK, in that order. The attribute is the live
		-- channel and is up to 0.4 s fresher than the last `DataUpdate`; the save table is what is
		-- there before the first sweep lands. Reading them the other way round would make the bar
		-- jump backwards every time a push arrived mid-fight.
		local level = tonumber(player:GetAttribute("Level")) or GameConfig.GetLevel(data)
		local xp = tonumber(player:GetAttribute("LevelXp")) or GameConfig.GetLevelXp(data)
		level = math.clamp(math.floor(level), 1, GameConfig.MaxLevel)
		xp = math.max(xp, 0)

		local cost = GameConfig.GetLevelXpCost(level)
		-- `{ Level = level }` rather than `data`: the multiplier drawn must be the multiplier for
		-- the level drawn, and `data` can be one push behind the attribute.
		local mult = GameConfig.GetLevelDamageMult({ Level = level })

		if cost == math.huge then
			fill.Size = UDim2.new(1, 0, 1, 0)
			label.Text = ("LV %d  \u{2022}  MAX  \u{2022}  \u{2694}\u{FE0F} x%.2f"):format(level, mult)
			return
		end

		fill.Size = UDim2.new(math.clamp(xp / cost, 0, 1), 0, 1, 0)

		-- THE REBIRTH DOOR IS NAMED ON THIS BAR AND NOWHERE ELSE ON THE MAIN SCREEN. The gate is a
		-- level now (32.7), so the bar the level lives on is the only honest place to say what it is
		-- counting toward -- otherwise a player has to open a panel to find out that the number
		-- climbing in front of them is the requirement for anything at all.
		local tail = ""
		if data then
			local nextTier = GameConfig.GetNextRebirthTier(data)
			local nextLevel = nextTier and GameConfig.RebirthLevelFor(nextTier) or nil
			if nextLevel then
				tail = level >= nextLevel
					and ("  \u{2022}  \u{267B}\u{FE0F} REBIRTH %d READY"):format(nextTier)
					or ("  \u{2022}  \u{267B}\u{FE0F} %d at LV %d"):format(nextTier, nextLevel)
			end
		end

		label.Text = ("LV %d  \u{2022}  %s / %s%s"):format(
			level, formatNumber(math.floor(xp)), formatNumber(cost), tail)
	end

	-- The live channel. Two attributes, so two signals -- `Level` alone would leave the fill frozen
	-- between level-ups, which is every frame but one.
	player:GetAttributeChangedSignal("LevelXp"):Connect(refresh)
	player:GetAttributeChangedSignal("Level"):Connect(refresh)
	-- ...and the save channel, for the join payload and for the rebirth that zeroes it.
	Remotes.DataUpdate.OnClientEvent:Connect(refresh)

	-- ===== THE LEVEL-UP TOAST LIVES HERE RATHER THAN IN MainUI'S HANDLER =====
	--
	-- `hud.showNotification` is written far below the line that requires this module, so it is nil
	-- at build time and filled in by the time any of this runs -- which is why it is reached through
	-- `hud` on every call instead of being cached. Doing it this way is what keeps MainUI's own edit
	-- for this feature to a single `require` line: a `payload.kind == "level"` branch in that file's
	-- twenty-branch handler would have been the second one.
	Remotes.Notify.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" or payload.kind ~= "level" then return end
		if not hud.showNotification then return end
		local text = ("\u{2B50} LEVEL %d!  \u{2694}\u{FE0F} x%.2f damage")
			:format(payload.level or 1, payload.mult or 1)
		if payload.nextRebirthLevel then
			text = text .. ("  \u{2022}  Rebirth at LV %d"):format(payload.nextRebirthLevel)
		end
		hud.showNotification(text, UITheme.Color.SkyBlue, UITheme.NotifyRank("level"))
		refresh()
	end)

	refresh()
end
