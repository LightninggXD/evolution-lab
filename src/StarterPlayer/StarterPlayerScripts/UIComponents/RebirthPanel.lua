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

		-- WHAT THE RUNG IS WORTH, ON EVERY ROW RATHER THAN ONLY THE TAKEN ONES (17.14). The two
		-- multipliers are the whole reason to press the button, and until this row they appeared
		-- exclusively on rungs already spent -- so the ladder told a player what a rebirth HAD
		-- been worth and never what the next one is worth. Same running totals in both cases:
		-- "x4.00 damage" is what the save reads AFTER that rung, not the increment it adds, which
		-- is the only form of the number anybody can act on.
		--
		-- MEASURED, NOT ESTIMATED: the card's text column is 282 px (592 wide, less a 140 px icon
		-- gutter and the 170 px button column) and CardDescription is 18 px FredokaOne with
		-- TextTruncate.AtEnd. The string this replaced -- "Permanent (dot) x1.25 damage (dot)
		-- x1.30 income" -- measures 317 px and was photographed cut off at "x1.30...", i.e. the
		-- panel truncated the one thing the row exists to show. This one is 223 px at the
		-- twentieth rung, 263 px with the "Pays" prefix. TextBounds reports the TRUNCATION and so
		-- cannot check this -- ask TextService:GetTextSize for the untruncated width.
		local pays = ("x%.2f damage  \u{00B7}  x%.2f income"):format(
			GameConfig.GetRebirthDamageMult({ Rebirths = tier }),
			GameConfig.GetRebirthIncomeMult({ Rebirths = tier }))

		if tier <= done then
			-- TAKEN. Saves from before the ladder existed hold more rebirths than there are rungs
			-- (the owner's test save has eight), which is why this is `<=` and not `==`: every rung
			-- up to the count reads as taken rather than the panel showing "8 / 4".
			row.card.SetSubtitle("Taken  \u{00B7}  kept forever")
			row.card.SetDescription(pays)
			row.card.SetColors(pastel(hueFor(tier), true))
			row.card.Button.SetPrice("DONE")
			row.card.Button.SetEnabled(false, DONE)
			row.card.Button.SetColors(DONE)
		elseif tier == nextTier and ready then
			-- THE CHARGE MOVED INTO THE SUBTITLE so the description can carry the payout. Both
			-- halves of the trade are still named on the row -- what it costs and what it pays,
			-- this file's own rule at the top; what changed is that the reset no longer takes the
			-- whole 282 px line to say it ("Resets your stage, zones and collection" measures
			-- 298 px and was truncated too).
			row.card.SetSubtitle("Ready now  \u{00B7}  resets your run")
			row.card.SetDescription("Pays " .. pays)
			row.card.SetColors(pastel(hueFor(tier), false))
			row.card.Button.SetPrice("REBIRTH")
			row.card.Button.SetEnabled(true, READY)
		else
			-- THE DISTANCE, NOT JUST THE POSITION. "You are Level 12" leaves the player to do the
			-- subtraction on every row of a twenty-row ladder; the levels still to go is the one
			-- number any of those rows is actually asking for. It sits beside the gate now rather
			-- than on its own line, because that line belongs to `pays`.
			row.card.SetSubtitle(("Reach Level %d  \u{00B7}  %d to go"):format(gateLevel, math.max(gateLevel - level, 0)))
			row.card.SetDescription("Pays " .. pays)
			row.card.SetColors(pastel(hueFor(tier), false))
			row.card.Button.SetPrice("LOCKED")
			row.card.Button.SetEnabled(false)
		end
	end

	-- THE HEADING CARRIES THE POSITION (17.14). Twenty rungs scroll, so the rung a player is
	-- actually on is often off the top or the bottom of the list -- "REBIRTH" alone left the panel
	-- silent about how far up it they were. The denominator is DROPPED once the ladder is finished
	-- rather than printed as "8 / 20": a legacy save holding more rebirths than there are rungs
	-- would read as broken arithmetic, which is the same reason the rungs above are `<=`, not `==`.
	panel.SetTitle(done >= GameConfig.MaxRebirths
		and "REBIRTH \u{2014} COMPLETE"
		or ("REBIRTH  \u{00B7}  %d / %d"):format(done, GameConfig.MaxRebirths))
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
