-- PlaytimeGiftsPanel -- the session-timer rewards, in the new panel design.
--
-- WHAT IT REPLACED: a 790 x 294 frame holding five 142-wide cells in a hand-laid horizontal row,
-- each one a stack of five TextLabels at authored y offsets (8, 36, 92, 118, and 1,-34). It was the
-- widest fixed panel in the HUD and the only one that read as a row of trading cards rather than as
-- a list -- which is the whole reason it looked like a different game to the Teleport and Store
-- screens beside it.
--
-- Five milestones is a LIST, and the builder's card is the list row this HUD is standardising on:
-- art on the left, name and two lines of state in the middle, one action on the right.
--
-- ===== THIS MODULE IS REQUIRED EAGERLY, AND THAT IS NOT A STYLE CHOICE =====
--
-- The other three builder panels are required inside their tile's click handler, which is right for
-- them: they read the save through `PlayerData`, and the save is pushed every three seconds, so a
-- panel built on the first click has the numbers immediately.
--
-- `Remotes.PlaytimeStatus` is not like that. `PlaytimeGiftService` fires it exactly TWICE -- 0.5 s
-- after the player joins, and again after each claim -- and never on a timer. A module that
-- subscribed on first click would have missed the join payload, so it would not know
-- `sessionStart`, and every row would count down from the moment the panel was opened rather than
-- from the moment the session began. So `Init` runs at HUD build time and the subscription is live
-- from then on; only the one-second tick is gated on the panel being visible.
--
-- ===== WHY THE COUNTDOWN IS NOT A `while true` LOOP OVER THE CARDS =====
--
-- The old block ran `refreshPlaytimePanel()` every second for the whole session, rewriting five
-- labels, five stroke colours and five card fills whether or not anything was on screen. Here the
-- loop still ticks every second -- a countdown has to -- but it returns immediately unless the
-- panel is open, and the READY transition is what actually needs watching: a milestone that comes
-- due while the panel is shut is picked up the moment it is opened, because `OnRefresh` runs then.

local RS = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("Remotes")
local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local IconLibrary = require(RS.Modules.IconLibrary)

local Builder = require(script.Parent:WaitForChild("ScrollingPanelBuilder"))

local PlaytimeGiftsPanel = {}
local panel = nil
local rows = {}

-- The session clock and the claim set. Held here rather than passed in, because this module is the
-- only reader of that remote now -- `MainUI` kept both as top-level locals purely so its own
-- refresh function could see them, and its register budget is the scarcest thing in this codebase.
local sessionStart = os.time()
local claimed = {}

local WHITE = Color3.fromRGB(255, 255, 255)
local CLAIM = { Color3.fromRGB(120, 255, 170), Color3.fromRGB(20, 200, 100) }
-- DEEPER THAN THE CARD IT SITS ON, and that is the whole reason for the numbers. The first version
-- of this was (255,196,130) -> (240,150,40), which is the same amber the waiting card is pastelled
-- from -- photographed, it read as an orange lozenge on an orange sheet with only the ink outline
-- separating them. A disabled button still has to be legible as a button; it is the CAPTION that
-- says it cannot be pressed, not the fact that you can barely see it.
local WAIT_COLORS = { Color3.fromRGB(250, 160, 50), Color3.fromRGB(212, 104, 12) }

local function pastel(c)
	return { c:Lerp(WHITE, 0.42), c:Lerp(WHITE, 0.68) }
end

-- Three states, three fills, and they are the same three the old cells used so nothing about the
-- colour language changes: warm while you wait, green when it is yours, grey once it is spent.
local WAITING = pastel(Color3.fromRGB(255, 150, 60))
local READY   = pastel(Color3.fromRGB(90, 220, 130))
local DONE    = pastel(Color3.fromRGB(150, 156, 175))

--- What the milestone actually pays, as one line. Built from the grant fields rather than written
--- per row, so a milestone added to `GameConfig.PlaytimeGifts` cannot arrive here undescribed.
local function rewardLine(m)
	local bits = { UITheme.FormatNumber(m.dna) .. " DNA" }
	if m.potions then
		table.insert(bits, "\u{1F9EA} x" .. m.potions)
	end
	if m.diamonds then
		table.insert(bits, "\u{1F48E} x" .. m.diamonds)
	end
	return table.concat(bits, "  \u{2022}  ")
end

--- The biggest thing in the payout decides the picture: a diamond beats a potion beats raw DNA.
--- Routed through `Resolve` rather than `ID` so an unmapped glyph falls back the way the header
--- says it should, instead of drawing an empty square.
local function iconFor(m)
	if m.diamonds then return IconLibrary.Resolve("\u{1F48E}") end
	if m.potions then return IconLibrary.Resolve("\u{1F9EA}") end
	return IconLibrary.Resolve("\u{1F9EC}")
end

local function refresh()
	local elapsed = os.time() - sessionStart
	for i, m in ipairs(GameConfig.PlaytimeGifts) do
		local row = rows[i]
		if row then
			local remaining = m.minutes * 60 - elapsed
			if claimed[i] then
				row.card.SetDescription("Claimed today")
				row.card.SetColors(DONE)
				row.card.Button.SetPrice("DONE")
				row.card.Button.SetEnabled(false)
			elseif remaining <= 0 then
				row.card.SetDescription("Ready to claim")
				row.card.SetColors(READY)
				row.card.Button.SetPrice("CLAIM")
				row.card.Button.SetEnabled(true, CLAIM)
			else
				-- `%dm %02ds`, not `%dm %ds`: this line rewrites itself once a second, and a seconds
				-- field that changes width makes the whole row twitch on every tick.
				row.card.SetDescription(("Unlocks in %dm %02ds"):format(remaining // 60, remaining % 60))
				row.card.SetColors(WAITING)
				-- amber rather than the disabled grey, and the time ON the button: this button is
				-- not refusing, it is telling you when to come back
				row.card.Button.SetPrice(("%dm"):format(math.ceil(remaining / 60)))
				row.card.Button.SetEnabled(false, WAIT_COLORS)
				row.card.Button.SetColors(WAIT_COLORS)
			end
		end
	end
end

function PlaytimeGiftsPanel.Init(screenGui)
	if panel then return panel end

	panel = Builder.CreatePanel({
		Parent = screenGui,
		Name = "PlaytimeGifts",
		Title = "PLAYTIME GIFTS",
		HeaderIcon = IconLibrary.Id.clock,
		HeaderColors = { Color3.fromRGB(255, 190, 120), Color3.fromRGB(245, 140, 40) },
		EmptyText = "No gifts configured",
	})

	for i, m in ipairs(GameConfig.PlaytimeGifts) do
		local card = panel.AddCard({
			Name = "Gift" .. i,
			LayoutOrder = i,
			Title = m.minutes .. " minutes",
			Subtitle = rewardLine(m),
			Description = "",
			Icon = iconFor(m) or "",
			BackgroundColors = WAITING,
			Buttons = {
				{
					Name = "Claim",
					Price = "CLAIM",
					Icon = "",
					Colors = CLAIM,
					-- The index, and the server re-checks both the clock and the claim set --
					-- `HandleClaim` refuses a second claim and refuses one that is not due, so the
					-- worst a stale card can do is earn a Notify saying so.
					Callback = function()
						Remotes.ClaimPlaytimeGift:FireServer(i)
					end,
				},
			},
		})
		rows[i] = { card = card }
	end

	-- Live from HUD build time -- see the header for why this cannot wait for the first click.
	Remotes.PlaytimeStatus.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then return end
		if payload.sessionStart then
			sessionStart = payload.sessionStart
		end
		claimed = {}
		for _, idx in ipairs(payload.claimed or {}) do
			claimed[idx] = true
		end
		if panel.IsOpen() then refresh() end
	end)

	panel.OnRefresh(refresh)

	task.spawn(function()
		while true do
			task.wait(1)
			-- a countdown that is not being watched is arithmetic nobody reads; `OnRefresh` catches
			-- whatever came due while the panel was shut
			if panel.IsOpen() then refresh() end
		end
	end)

	refresh()
	return panel
end

function PlaytimeGiftsPanel.Toggle()
	if panel then panel.Toggle() end
end

return PlaytimeGiftsPanel
