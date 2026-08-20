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
--
-- ===== TWO LADDERS IN ONE LIST (21.3) =====
--
-- The panel now draws `GameConfig.PlaytimeGifts` and `GameConfig.DailyPlaytimeGifts` one after the
-- other, under a banner each. They are the same kind of thing measured against two different
-- clocks, and a player who has just been told the 30-minute rung is spent has to be able to see,
-- without leaving the screen, that the OTHER 30-minute rung is the one still open to them. Two
-- panels would have made that a comparison across a click.
--
-- The two ladders are driven by ONE `refresh` over a table of two rows, not by two copies of it:
-- the daily ladder differs from the session one in exactly three things -- which config list, which
-- claim set, and which clock -- and every one of those is data. The daily clock arrives from the
-- server as a virtual start time (`dailyStart = now - secondsPlayedToday`) precisely so that
-- `os.time() - start` is the right expression for both.

local RS = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("Remotes")
local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local IconLibrary = require(RS.Modules.IconLibrary)

local Builder = require(script.Parent:WaitForChild("ScrollingPanelBuilder"))

local PlaytimeGiftsPanel = {}
local panel = nil

-- THE TWO LADDERS, and everything that differs between them. `start` is a virtual one until the
-- first payload lands: the session clock is genuinely "now" for a panel built at HUD time, and the
-- daily clock defaults to the same thing, which shows a fresh ladder rather than a wrong one.
--
-- Held here rather than passed in, because this module is the only reader of that remote now --
-- `MainUI` kept the session pair as top-level locals purely so its own refresh function could see
-- them, and its register budget is the scarcest thing in this codebase.
local ladders = {
	{
		key = "session",
		list = nil, -- filled in at Init, once GameConfig is required
		banner = "THIS SESSION",
		blurb = "since you joined",
		start = os.time(),
		claimed = {},
		rows = {},
		order = 0,
	},
	{
		key = "daily",
		list = nil,
		banner = "TODAY IN TOTAL",
		blurb = "every session added up",
		start = os.time(),
		claimed = {},
		rows = {},
		order = 100,
	},
}
local sessionLadder, dailyLadder = ladders[1], ladders[2]

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

--- Whole minutes as the shortest true thing to call them. The daily ladder runs to four hours, and
--- `240m` on a card whose neighbour says `30m` makes the player do the division themselves.
local function durationText(minutes)
	if minutes < 60 then return minutes .. "m" end
	local h, m = minutes // 60, minutes % 60
	return m == 0 and (h .. "h") or ("%dh %dm"):format(h, m)
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
	local now = os.time()
	for _, ladder in ipairs(ladders) do
		local elapsed = now - ladder.start
		-- The banner carries the clock it is measured against, live. It is the only place the
		-- accumulated total is ever shown, and it is what turns "TODAY IN TOTAL" from a label into
		-- a number the player can watch move -- which is the whole point of a persistent ladder.
		if ladder.bannerLabel then
			ladder.bannerLabel.Text = ("%s  \u{2022}  %s played"):format(ladder.banner, durationText(elapsed // 60))
		end
		for i, m in ipairs(ladder.list) do
			local row = ladder.rows[i]
			if row then
				local remaining = m.minutes * 60 - elapsed
				if ladder.claimed[i] then
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
					-- `%dm %02ds`, not `%dm %ds`: this line rewrites itself once a second, and a
					-- seconds field that changes width makes the whole row twitch on every tick.
					-- Past an hour the seconds are dropped rather than left to run to `179m 04s`:
					-- a field that wide is a stopwatch, and nobody watches a three-hour one tick.
					if remaining >= 3600 then
						row.card.SetDescription("Unlocks in " .. durationText(math.ceil(remaining / 60)))
					else
						row.card.SetDescription(("Unlocks in %dm %02ds"):format(remaining // 60, remaining % 60))
					end
					row.card.SetColors(WAITING)
					-- amber rather than the disabled grey, and the time ON the button: this button
					-- is not refusing, it is telling you when to come back
					row.card.Button.SetPrice(durationText(math.ceil(remaining / 60)))
					row.card.Button.SetEnabled(false, WAIT_COLORS)
					row.card.Button.SetColors(WAIT_COLORS)
				end
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

	sessionLadder.list = GameConfig.PlaytimeGifts
	dailyLadder.list = GameConfig.DailyPlaytimeGifts

	for _, ladder in ipairs(ladders) do
		-- ===== THE BANNER =====
		-- A `CustomLayout` card, which is the builder's own escape hatch for a row that is not the
		-- art/name/action shape -- rather than a bare TextLabel dropped into the scroll. Going
		-- through AddCard is what keeps it inside the UIListLayout's ordering and inside the
		-- padding that stops a 4 px stroke being sliced off by the clip; a label parented straight
		-- to the scroll would be laid out beside the cards but styled like nothing else in the HUD.
		local head = panel.AddCard({
			Name = ladder.key .. "Banner",
			LayoutOrder = ladder.order,
			CustomLayout = true,
			BackgroundColors = { Color3.fromRGB(96, 104, 130), Color3.fromRGB(58, 64, 86) },
		})
		-- 140 is the card height the list is built around and a banner is not a card; 52 is the
		-- header rule's own height elsewhere in this kit, so the two read as the same furniture.
		head.Instance.Size = UDim2.new(1, -6, 0, 52)

		local bannerLabel = Instance.new("TextLabel")
		bannerLabel.Name = "Banner"
		-- NOT `1, -24`. The hint below is anchored to the same 52 px strip's right edge, so a
		-- full-width label sits UNDER it and truncates 200 px past where it is actually readable.
		-- 604 (card) - 12 - 376 - 12 - 200 - 12 = 4 px of slack, and both ends truncate at end.
		bannerLabel.Size = UDim2.new(1, -228, 1, 0)
		bannerLabel.Position = UDim2.new(0, 12, 0, 0)
		bannerLabel.BackgroundTransparency = 1
		bannerLabel.Font = Enum.Font.FredokaOne
		bannerLabel.TextSize = 22
		bannerLabel.TextColor3 = WHITE
		bannerLabel.TextXAlignment = Enum.TextXAlignment.Left
		bannerLabel.TextTruncate = Enum.TextTruncate.AtEnd
		-- one above the card it sits on, which is 53 -- see the ZIndex contract in UITheme
		bannerLabel.ZIndex = 54
		bannerLabel.Text = ladder.banner
		bannerLabel.Parent = head.Instance
		local bs = Instance.new("UIStroke")
		bs.Color = Color3.fromRGB(0, 0, 0)
		bs.Thickness = 3
		bs.Parent = bannerLabel
		ladder.bannerLabel = bannerLabel

		local hint = Instance.new("TextLabel")
		hint.Name = "Hint"
		hint.Size = UDim2.new(0, 200, 1, 0)
		hint.Position = UDim2.new(1, -12, 0, 0)
		hint.AnchorPoint = Vector2.new(1, 0)
		hint.BackgroundTransparency = 1
		hint.Font = Enum.Font.GothamBold
		hint.TextSize = 15
		hint.TextColor3 = Color3.fromRGB(212, 218, 235)
		hint.TextXAlignment = Enum.TextXAlignment.Right
		hint.TextTruncate = Enum.TextTruncate.AtEnd
		hint.ZIndex = 54
		hint.Text = ladder.blurb
		hint.Parent = head.Instance

		-- ===== THE RUNGS =====
		for i, m in ipairs(ladder.list) do
			local card = panel.AddCard({
				Name = ladder.key .. "Gift" .. i,
				LayoutOrder = ladder.order + i,
				Title = durationText(m.minutes),
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
						-- The index and which ladder it belongs to. The server re-checks both the
						-- clock and the claim set -- `HandleClaim` refuses a second claim and
						-- refuses one that is not due, so the worst a stale card can do is earn a
						-- Notify saying so.
						Callback = function()
							Remotes.ClaimPlaytimeGift:FireServer(i, ladder.key)
						end,
					},
				},
			})
			ladder.rows[i] = { card = card }
		end
	end

	-- Live from HUD build time -- see the header for why this cannot wait for the first click.
	Remotes.PlaytimeStatus.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then return end
		-- Guarded rather than assigned straight through: the join payload is fired 0.5 s in and
		-- reports whatever the save had at that moment, which is nothing at all if the save was
		-- still loading. A nil there must leave the clock where it is, not zero it to 1970.
		if payload.sessionStart then
			sessionLadder.start = payload.sessionStart
		end
		if payload.dailyStart then
			dailyLadder.start = payload.dailyStart
		end
		sessionLadder.claimed = {}
		for _, idx in ipairs(payload.claimed or {}) do
			sessionLadder.claimed[idx] = true
		end
		dailyLadder.claimed = {}
		for _, idx in ipairs(payload.dailyClaimed or {}) do
			dailyLadder.claimed[idx] = true
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
