-- WelcomeBack -- the offline-earnings card shown once on join -- what the game made while you were gone.
--
-- MOVED OUT OF `MainUI` (18.9), byte for byte. It was already a closed
-- `;(function() ... end)()` block -- the shape this file's 200-register ceiling forces
-- every panel into -- so the extraction is a change of wrapper, not of code. See
-- `docs/SPLIT.md` for the `hud` contract and `docs/CODEMAP.md` for where the rest went.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))

local player = Players.LocalPlayer

local themeLabel, styleCard, styleButton, DISPLAY_FONT = UIKit.themeLabel, UIKit.styleCard, UIKit.styleButton, UIKit.DISPLAY_FONT
local PANEL_SHELL, PET_ROW_SHELL = UIKit.PANEL_SHELL, UIKit.PET_ROW_SHELL

return function(hud)
	local PANEL_ANCHOR, dayNumber, panelClose = hud.PANEL_ANCHOR, hud.dayNumber, hud.panelClose
	local refreshRewardPanel, registerPanel, rewardPanel = hud.refreshRewardPanel, hud.registerPanel, hud.rewardPanel
	local screenGui, toggleOnly, togglePanels = hud.screenGui, hud.toggleOnly, hud.togglePanels

	local shown = false

	local ROW_H, ROW_GAP = 88, 12
	local panel = Instance.new("Frame")
	panel.Name = "WelcomeBackPanel"
	-- 294 = the header's own 90 (top 14 + height 64 + gap 12) + two rows + the gap between them +
	-- 16 of bottom margin. It was authored at 276, which is 2px SHORT of the rows alone, so the
	-- second card hung over the shell's bottom rim. Two rows is the most this card can ever have
	-- and it is authored at that height on purpose: registerPanel computes its responsive fit from
	-- the authored size, so a panel that resized itself afterwards would be scaling off a stale one.
	panel.Size = UDim2.new(0, 580, 0, 294)
	panel.Position = PANEL_ANCHOR
	panel.ZIndex = 20
	panel.Visible = false
	panel.Parent = screenGui
	styleCard(panel, PANEL_SHELL, UDim.new(0, 24), 5)
	registerPanel(panel)
	panelClose(panel)

	-- THE SUBTITLE IS CAPTURED, and that is not a tidy-up. The hand-built `local sub` this header
	-- replaced was deleted while the line 200 lines down that writes to it ("Two things are waiting
	-- for you.") was left standing -- so `sub` resolved to a nil GLOBAL and `maybeWelcomeBack`
	-- threw on the first payload of every session, which is the one call that opens this card.
	-- `luanames.py` cannot see it: it is deliberately not scope-aware and two OTHER functions in
	-- this file declare a local called `sub`, so the name looked bound.
	local header, contentTop, _, sub = UITheme.PanelHeader(panel, {
		title = "\u{1F44B} Welcome Back!",
		subtitle = "You have unclaimed rewards waiting!",
		accent = UITheme.Color.Lavender,
		margin = 16,
		top = 14,
		height = 64,
	})

	local rowHost = Instance.new("Frame")
	rowHost.Name = "Rows"
	rowHost.Size = UDim2.new(1, -32, 0, ROW_H * 2 + ROW_GAP)
	rowHost.Position = UDim2.new(0, 16, 0, contentTop)
	rowHost.BackgroundTransparency = 1
	rowHost.ZIndex = panel.ZIndex + UITheme.Z.Content
	rowHost.Parent = panel

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.Padding = UDim.new(0, ROW_GAP)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = rowHost

	local function buildRow(order, color, defaultIcon, action)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, ROW_H)
		row.LayoutOrder = order
		row.ZIndex = rowHost.ZIndex + UITheme.Z.Content
		row.Visible = false
		row.Parent = rowHost
		styleCard(row, PET_ROW_SHELL, UDim.new(0, 16), 3.5)

		local iconBox = Instance.new("Frame")
		iconBox.Name = "IconBox"
		iconBox.Size = UDim2.new(0, 56, 0, 56)
		iconBox.Position = UDim2.new(0, 14, 0.5, 0)
		iconBox.AnchorPoint = Vector2.new(0, 0.5)
		iconBox.ZIndex = row.ZIndex + UITheme.Z.Content
		iconBox.Parent = row
		styleCard(iconBox, UITheme.Shade(color, 0.25), UDim.new(0, 12), 2.5)

		local iconLabel = Instance.new("TextLabel")
		iconLabel.Name = "IconLabel"
		iconLabel.Size = UDim2.new(1, 0, 1, 0)
		iconLabel.BackgroundTransparency = 1
		iconLabel.Text = defaultIcon or "\u{1F381}"
		iconLabel.Font = DISPLAY_FONT
		iconLabel.ZIndex = iconBox.ZIndex + UITheme.Z.Content
		themeLabel(iconLabel, 30)
		iconLabel.Parent = iconBox

		local head = Instance.new("TextLabel")
		head.Name = "Head"
		head.Size = UDim2.new(1, -250, 0, 28)
		head.Position = UDim2.new(0, 80, 0, 14)
		head.BackgroundTransparency = 1
		head.TextXAlignment = Enum.TextXAlignment.Left
		head.ZIndex = row.ZIndex + UITheme.Z.Content
		head.Parent = row
		themeLabel(head, 24)

		local note = Instance.new("TextLabel")
		note.Name = "Note"
		-- 24 -> 32 (15.16). Measured at the 14px floor, the Season Pass row's note -- "Finished
		-- quests and levels you have already passed" -- wraps to two lines needing **28px** in a
		-- 24px box, so its second line was cut on every join that opened this card. Wrapping is not
		-- turned off here the way the potion rows do it: at 14px the string is wider than the 298
		-- it has, so one line would truncate instead. The row is 88 tall and this ends at 78, so
		-- the 10px below it is the clearance the growth is taken out of.
		note.Size = UDim2.new(1, -250, 0, 32)
		note.Position = UDim2.new(0, 80, 0, 46)
		note.BackgroundTransparency = 1
		note.TextXAlignment = Enum.TextXAlignment.Left
		note.ZIndex = row.ZIndex + UITheme.Z.Content
		note.Parent = row
		themeLabel(note, 17, UITheme.Color.Gold)

		local btn = Instance.new("TextButton")
		btn.Name = "GoButton"
		btn.Size = UDim2.new(0, 130, 0, 52)
		btn.Position = UDim2.new(1, -14, 0.5, 0)
		btn.AnchorPoint = Vector2.new(1, 0.5)
		btn.Text = "CLAIM"
		btn.ZIndex = row.ZIndex + UITheme.Z.Content
		btn.Parent = row
		styleButton(btn, color, UDim.new(0, 14))
		btn.MouseButton1Click:Connect(action)

		return row, head, note, btn, iconLabel
	end

	local dailyRow, dailyHead, dailyNote, dailyBtn, dailyIcon = buildRow(1, UITheme.Color.Green, "\u{1F381}", function()
		refreshRewardPanel()
		toggleOnly(rewardPanel)
	end)
	local seasonRow, seasonHead, seasonNote, seasonBtn, seasonIcon = buildRow(2, UITheme.Color.Sunny, "\u{1F3C6}", function()
		hud.showSeasonPanel()
	end)

	function hud.maybeWelcomeBack(data, firstPayload)
		if shown or not firstPayload then return end
		shown = true
		if type(data) ~= "table" then return end
		if not data.TutorialDone then return end

		-- The same question refreshRewardPanel asks, off the same two fields, so the card and the
		-- tile badge can never disagree about whether today has been claimed.
		local dailyReady = dayNumber(os.time()) > dayNumber(data.LastRewardClaim)
		local seasonReady = hud.seasonClaimCount and hud.seasonClaimCount() or 0

		if not dailyReady and seasonReady <= 0 then return end

		if dailyReady then
			local streak = data.RewardStreak or 0
			local today = dayNumber(os.time())
			-- the streak the claim will PRODUCE, not the one on the save: a player who missed a day
			-- is starting again at 1, and telling them "Day 6 is ready" and then paying Day 1 is
			-- the kind of small lie that makes the whole board look broken
			local continuing = (today == dayNumber(data.LastRewardClaim) + 1)
			local upcoming = continuing and (streak + 1) or 1
			-- through the shared helper rather than the modulo written out a fifth time: 21.2 gave the
			-- board week tiers, and the day index is now one function's job (GameConfig.GetDailyReward)
			local index = GameConfig.GetDailyReward(math.max(upcoming, 1)).day
			dailyHead.Text = ("\u{1F381} Daily reward \u{2014} Day %d is ready"):format(index)
			-- AND THE NOTE HAS TO ASK THE SAME QUESTION THE HEAD DOES (11.28). It used to test only
			-- `streak > 0`, so a player who missed a day was told "Day 1 is ready" over "4 day streak
			-- -- claim to keep it going": the head had already worked out the streak was gone and the
			-- line under it still promised to keep it. Same lie the comment above was written against,
			-- one line lower down. A broken streak is worth saying out loud rather than hiding -- it is
			-- the only thing on this card that asks the player to come back tomorrow.
			dailyNote.Text = (continuing and streak > 0)
				and ("\u{1F525} %d day streak \u{2014} claim to keep it going"):format(streak)
				or (streak > 0 and "\u{1F494} Your streak ended \u{2014} this one starts a new run"
					or "Claim it to start a streak")
		end
		dailyRow.Visible = dailyReady

		if seasonReady > 0 then
			seasonHead.Text = ("\u{1F3C6} Season Pass \u{2014} %d to claim"):format(seasonReady)
			seasonNote.Text = "Finished quests and levels you have already passed"
		end
		seasonRow.Visible = seasonReady > 0

		sub.Text = (dailyReady and seasonReady > 0)
			and "Two things are waiting for you."
			or "You have something waiting."

		-- ===== AND THE CARD IS AS TALL AS WHAT IS ACTUALLY WAITING (16.5) =====
		--
		-- Authored at two rows, because two is the most it can ever hold and `registerPanel` reads
		-- its responsive fit off the AUTHORED size. But one row is the common case by a distance --
		-- the Season Pass has something to claim only after a level or a quest turns over -- and one
		-- row in a two-row card is 100 px of empty shell under the daily reward, which reads as a
		-- card that failed to finish loading rather than as a card with one thing on it.
		--
		-- SHRINKING IS THE SAFE DIRECTION and that is why this is allowed to run after
		-- `registerPanel`: the UIScale it fitted is computed for 580x294, so a panel that ends up
		-- SMALLER than that still fits every viewport it fitted before. Growing is what would be
		-- scaling off a stale number, and nothing here ever grows past the authored height.
		local liveRows = (dailyRow.Visible and 1 or 0) + (seasonRow.Visible and 1 or 0)
		if liveRows > 0 then
			local rowsH = liveRows * ROW_H + (liveRows - 1) * ROW_GAP
			rowHost.Size = UDim2.new(1, -32, 0, rowsH)
			-- 14 top + 64 header + 12 gap + rows + 16 bottom margin: the same arithmetic the
			-- authored 294 comes from, with the row count no longer assumed to be two.
			panel.Size = UDim2.new(0, 580, 0, 14 + 64 + 12 + rowsH + 16)
		end

		task.spawn(function()
			-- WAIT FOR THE LOADING SCREEN TO GO, and wait for the object rather than for a delay.
			-- LoadingScreen holds for MIN_SHOW 2.6 s and then fades for another 0.45 -- but it also
			-- waits on the HUD existing and on preloading, so the real number is a range, and a card
			-- animating open underneath it would be over by the time the wipe cleared.
			local lg = player:FindFirstChild("PlayerGui")
			local screen = lg and lg:FindFirstChild("LoadingScreen")
			local waited = 0
			while screen and screen.Parent and waited < 20 do
				waited += task.wait(0.1)
			end
			task.wait(0.35)
			-- ...and do not shove a card in front of something the player opened in the meantime.
			-- Twenty seconds is a long time to hold a greeting; if they are already busy, they have
			-- found their own way in and the badge on the tile is enough.
			for _, p in ipairs(togglePanels) do
				if p.Visible then return end
			end
			toggleOnly(panel)
		end)
	end
end
