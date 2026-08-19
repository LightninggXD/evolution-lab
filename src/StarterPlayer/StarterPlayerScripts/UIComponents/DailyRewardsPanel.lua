local DailyRewardsPanel = {}

function DailyRewardsPanel.Init(deps)
    local screenGui = deps.screenGui
    local UITheme = deps.UITheme
    local GameConfig = deps.GameConfig
    local Remotes = deps.Remotes
    local PANEL_ANCHOR = deps.PANEL_ANCHOR
    local PANEL_SHELL = deps.PANEL_SHELL
    local OUTLINE_COLOR = deps.OUTLINE_COLOR
    local READY_RIM = deps.READY_RIM
    local styleCard = deps.styleCard
    local registerPanel = deps.registerPanel
    local panelClose = deps.panelClose
    local themeLabel = deps.themeLabel
    local formatNumber = deps.formatNumber
    local shade = deps.shade
    local setButtonColor = deps.setButtonColor
    local claimTick = deps.claimTick
    local claimOverlay = deps.claimOverlay
    local hudRefs = deps.hudRefs
    local toggleOnly = deps.toggleOnly
    local rewardButton = deps.rewardButton
    local rewardBadge = deps.rewardBadge
    local TweenService = deps.TweenService
    local RunService = deps.RunService
    local player = deps.player
    local playerGui = deps.playerGui

    local getCurrentData = deps.getCurrentData
    local currentData = nil
    
-- ===== Daily Reward panel (all 7 days at once + big Day 7 hero card) ===== -- MODIFIED
-- The one true modal in the HUD: a dimmed backdrop kills the rest of the screen so the
-- 7-day board is the only thing reading. The dim is a sibling one ZIndex under the shell.
local rewardDim = Instance.new("Frame")
rewardDim.Name = "RewardDim"
rewardDim.Size = UDim2.new(1, 0, 1, 0)
rewardDim.Position = UDim2.new(0, 0, 0, 0)
-- The kit's own shadow tint rather than pure black. Flat rgb(0,0,0) over a bright cartoon world
-- reads as a screenshot someone dimmed in an image editor; the violet-black that everything else
-- in the game is outlined and shadowed with reads as part of the same picture.
rewardDim.BackgroundColor3 = UITheme.Color.Shadow
rewardDim.BackgroundTransparency = 0.38
rewardDim.BorderSizePixel = 0
rewardDim.ZIndex = 19
rewardDim.Visible = false
rewardDim.Parent = screenGui

local rewardPanel = Instance.new("Frame")
rewardPanel.Name = "RewardPanel"
-- 536, up from 480. The day grid ends at y=412 and the banner already owns the bottom strip
-- (anchored at 1,-14, 44 tall), which left ten pixels between them -- so the code bar (5.1) is paid
-- for with panel height rather than by moving anything that was already here. Still smaller than
-- the Journal at 968x548, so the responsive fit in registerPanel has nothing new to solve.
--
-- 578 -> 638 (18.3), and 56 of those 60 pixels go into the reward glyphs. "vece ikone" was one of
-- three asks on this panel and the icon could not grow inside a 152 px tile: the day chip ends at
-- y = 30 and the two value lines own the bottom 50, which left the glyph 56 px in the middle of a
-- card 140 wide. The cell is 182 now (see CELL_H) and the glyph is 84 -- wider than the day chip
-- above it, which it was not before. The grid bottom moves 454 -> 514 against a code bar whose top
-- edge is 638 - 110 = 528.
--
-- The last 4 px are the pulse's clearance, and they are a measurement rather than a rounding: the
-- claimable tile now runs `UITheme.Attention` at peak 1.03 and a UIScale grows about the
-- AnchorPoint, which on these cells is (0,0) -- so all of the growth goes down and right. The hero
-- column is the worst case at 372 x 1.03 = +11.2 px, reaching y = 525.2 against a code bar at 528.
-- Still under the Journal's 968 width, so registerPanel's fit has nothing new to solve.
rewardPanel.Size = UDim2.new(0, 700, 0, 638)
rewardPanel.Position = PANEL_ANCHOR
rewardPanel.ZIndex = 20
rewardPanel.Visible = false
rewardPanel.Parent = screenGui
styleCard(rewardPanel, PANEL_SHELL, UDim.new(0, 22), 5)
registerPanel(rewardPanel)
panelClose(rewardPanel)

-- toggleOnly still owns visibility; the backdrop only mirrors it -- and now fades rather than
-- snapping, so the dim arrives with the panel's scale pop instead of a frame ahead of it.
--
-- The SHOW has to be ordered carefully: Visible goes true BEFORE the tween starts, or there is
-- nothing on screen to fade; and the transparency is reset to fully clear first, or a re-open
-- starts from wherever the last close left it. The HIDE is the mirror, and it leans on
-- animatePanel keeping the panel Visible for the length of its own close tween -- 0.12s, which is
-- what this is matched to. A backdrop that vanished instantly would leave the panel shrinking
-- against the full-brightness world for the last two frames.
rewardPanel:GetPropertyChangedSignal("Visible"):Connect(function()
	if rewardPanel.Visible then
		rewardDim.BackgroundTransparency = 1
		rewardDim.Visible = true
		TweenService:Create(rewardDim, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 0.38 }):Play()
	else
		local fade = TweenService:Create(rewardDim, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ BackgroundTransparency = 1 })
		fade.Completed:Connect(function()
			-- guarded: the player may have reopened the board inside those 0.12 seconds, and hiding
			-- the backdrop then would leave the panel floating over an undimmed world
			if not rewardPanel.Visible then
				rewardDim.Visible = false
			end
		end)
		fade:Play()
	end
end)

-- Converted to the shared accent band (17.x). The streak line was a card at y = 58 saying the same
-- kind of thing a subtitle says -- "what is true for you right now" -- so it IS the subtitle, and
-- the card goes. That is one register back and 36 px of panel that the grid did not have to pay
-- for. Sunny because Day 7 is the gold hero column this board streaks towards.
local rewardStreakLine = select(4, UITheme.PanelHeader(rewardPanel, {
	title = "📅 Daily Rewards!",
	subtitle = "Streak: 1 day",
	accent = UITheme.Color.Sunny,
}))

-- The streak card that used to live here at y = 58 is the header's subtitle now -- see the note on
-- the band above. It was a 240 x 34 orange capsule holding one sentence about the player's current
-- state, which is exactly what a subtitle is for, and at y = 58 it would now sit underneath the
-- band. Two top-level registers back (card + label) against the one handle the subtitle costs.

local GRID_X, GRID_Y = 25, 142
-- CELL_H 152 -> 182 (18.3). The 30 px buys the reward glyph: 56 -> 84 on a small tile and 130 -> 164
-- on the hero. Nothing else on the card moved except downward by the same amount, and the panel grew
-- by 56 (2 rows + no extra gutter) so the code bar below still clears the grid by ten.
local CELL_W, CELL_H, CELL_GAP = 140, 182, 8
local DAY7_W = 200

local rewardCells = {} -- [dayIndex] = { frame, dayLabel, headerPill, plinth, iconLabel, amountLabel, bonusLabel, checkmark, strokeInst, idleColor, isToday }

-- one day of the board. `big` is the Day 7 hero column on the right: same anatomy, gold
-- shell, everything scaled up so it reads as the prize you are streaking towards.
local function buildDayCell(dayIndex, size, position, big)
	local reward = GameConfig.DailyRewards[dayIndex]
	local frame = Instance.new("Frame")
	frame.Name = "Day" .. dayIndex
	frame.Size = size
	frame.Position = position
	frame.Parent = rewardPanel
	-- ===== SEVEN HUES, NOT ONE CREAM AND ONE LIME (18.3) =====
	--
	-- Every tile but the hero was rgb(255,250,195) -- a single cream at luminance 0.97 -- so the board
	-- had exactly one colour in it and a claimed day had no hue of its own to keep. "vise nijansi
	-- boja ubaci" is answered here, at the source, rather than by tinting states later.
	--
	-- The ramp is cool -> warm -> gold across the week, so the row itself reads as an escalation
	-- toward the Day 7 prize, and it is drawn entirely from `UITheme.Color`: Aqua, Lavender,
	-- Bubblegum, Coral, Peach, Sunny, Gold. Two rules decided the list. Nothing in it is GREEN,
	-- because Green is what a claimable tile turns and a day whose idle colour was already green
	-- would have no state left to show; and day 7 is Gold rather than the old lime, which is what the
	-- header band has said this board streaks toward since 17.x ("Sunny because Day 7 is the gold
	-- hero column"). `#dayHues` is indexed modulo its own length so a longer week cannot nil this.
	local dayHues = {
		UITheme.Color.Aqua, UITheme.Color.Lavender, UITheme.Color.Bubblegum,
		UITheme.Color.Coral, UITheme.Color.Peach, UITheme.Color.Sunny, UITheme.Color.Gold,
	}
	local idleColor = dayHues[((dayIndex - 1) % #dayHues) + 1]
	local strokeInst = styleCard(frame, idleColor, UDim.new(0, 16), big and 5 or 3.5)

	local headerPill = Instance.new("Frame")
	headerPill.Name = "HeaderPill"
	-- 88 on the hero card, not 110. The card is 200 wide, so a 110 pill centred on it runs from
	-- x=45 to x=155 and the OP badge in the top-left corner starts at x=6 -- they overlapped by 27px
	-- and the badge was drawn through the pill's border. 88 leaves a 6px gap against a 44 badge.
	headerPill.Size = UDim2.new(0, big and 88 or 80, 0, big and 30 or 24)
	headerPill.Position = UDim2.new(0.5, 0, 0, 6)
	headerPill.AnchorPoint = Vector2.new(0.5, 0)
	headerPill.ZIndex = frame.ZIndex + UITheme.Z.Badge
	headerPill.Parent = frame
	styleCard(headerPill, Color3.fromRGB(255, 255, 255), UDim.new(1, 0), 2)

	local dayLabel = Instance.new("TextLabel")
	dayLabel.Name = "DayLabel"
	dayLabel.Size = UDim2.new(1, 0, 1, 0)
	dayLabel.BackgroundTransparency = 1
	dayLabel.Text = "Day " .. dayIndex
	dayLabel.ZIndex = headerPill.ZIndex + UITheme.Z.Content
	dayLabel.Parent = headerPill
	themeLabel(dayLabel, big and 20 or 16, Color3.fromRGB(24, 18, 38))

	if big then
		local opBadge = Instance.new("Frame")
		opBadge.Name = "OpBadge"
		opBadge.Size = UDim2.new(0, 44, 0, 26)
		opBadge.Position = UDim2.new(0, 6, 0, 8)
		opBadge.ZIndex = frame.ZIndex + UITheme.Z.Badge + 1
		opBadge.Parent = frame
		styleCard(opBadge, UITheme.Color.Orange, UDim.new(1, 0), 2)

		local opLabel = Instance.new("TextLabel")
		opLabel.Name = "OpLabel"
		opLabel.Size = UDim2.new(1, 0, 1, 0)
		opLabel.BackgroundTransparency = 1
		opLabel.Text = "OP!"
		opLabel.ZIndex = opBadge.ZIndex + UITheme.Z.Content
		opLabel.Parent = opBadge
		themeLabel(opLabel, 16, Color3.fromRGB(255, 255, 255))
	end

	local icon = "\u{1F9EC}"
	if reward.potions and reward.shards then
		icon = "\u{1F31F}"
	elseif reward.potions then
		icon = "\u{1F9EA}"
	elseif reward.shards or reward.diamonds then
		icon = "\u{1F48E}"
	end

	-- ===== THE PLINTH THE REWARD SITS ON (18.3) =====
	--
	-- "da ima neku dimenziju da izgleda 3d". The tile is one flat rectangle with a glyph floating in
	-- the middle of it; a second plane behind the glyph is what turns the reward into an OBJECT
	-- mounted on the card rather than a sticker printed on it. It also carries the second half of
	-- "vise nijansi": at `shade(idle, -0.16)` every tile now shows two values of its own hue instead
	-- of one flat wash, which is fourteen fills across the board where there used to be two.
	--
	-- `NoShadow`, because this is a chip lying ON the tile and not a raised object of its own -- a
	-- soft sprite here would be a second shadow inside the one the tile already casts, which reads as
	-- fog rather than as layers. What gives it its edge is styleCard's own gradient and outline.
	local plinth = Instance.new("Frame")
	plinth.Name = "Plinth"
	plinth.Size = UDim2.new(0, big and 180 or 106, 0, big and 200 or 92)
	plinth.Position = UDim2.new(0.5, 0, 0, big and 44 or 34)
	plinth.AnchorPoint = Vector2.new(0.5, 0)
	plinth.ZIndex = frame.ZIndex + UITheme.Z.Content
	plinth:SetAttribute("NoShadow", true)
	plinth.Parent = frame
	styleCard(plinth, shade(idleColor, -0.16), UDim.new(0, big and 18 or 14), big and 4 or 3)

	-- ===== "VECE IKONE", MEASURED =====
	--
	-- Before: an 80 x 24 day chip above a glyph drawn at 56 px (the box was `(1,0,0,56)` and the art is
	-- `ScaleType.Fit`, so 56 is the whole of it) -- the reward, which is the only reason the panel
	-- exists, was drawn narrower than the label naming the day it falls on. After: 84 px on a small
	-- tile (+50%) and 164 on the hero (+26%), both square and both centred on the plinth, so the glyph
	-- is now the largest thing on its own card by a wide margin.
	--
	-- `maxTextSize` follows, because the slot is an ImageLabel only when `IconLibrary` has a drawing
	-- for that emoji and a TextLabel when it does not -- a 44 pt cap would have left the fallback
	-- glyph at its old size inside the new box, which is the failure mode where only SOME of the days
	-- got bigger. 0.86 x the box, the same ratio the currency pills use.
	--
	-- ZIndex is passed explicitly rather than defaulted, so the slot lands one above the plinth and
	-- its own `IconShadow` sibling (authored at zIndex - 1) lands ON the plinth instead of under the
	-- tile's opaque body, where liftChildren's by-name skip had been leaving it.
	local iconLabel = UITheme.IconSlot(frame, {
		name = "IconLabel", icon = icon, maxTextSize = big and 140 or 72,
		size = UDim2.new(0, big and 164 or 84, 0, big and 164 or 84),
		position = UDim2.new(0.5, 0, 0, big and 62 or 38),
		anchorPoint = Vector2.new(0.5, 0),
		zIndex = frame.ZIndex + UITheme.Z.Content + 1,
	})

	-- The two value lines are anchored to the BOTTOM edge, so growing the cell moved them with it and
	-- the only change here is the clearance they keep from the plinth: the plinth ends at y = 126 on a
	-- 182 px tile and the amount now starts at 128 (was 102 on a 152 px tile against a glyph ending at
	-- 90). Bonus sits 26 under it and closes 6 px short of the bottom rim.
	local amountLabel = Instance.new("TextLabel")
	amountLabel.Name = "AmountLabel"
	amountLabel.Size = UDim2.new(1, -12, 0, big and 34 or 24)
	amountLabel.Position = UDim2.new(0, 6, 1, big and -92 or -54)
	amountLabel.BackgroundTransparency = 1
	amountLabel.TextWrapped = true
	-- THE CARD SAYS WHAT THE DAY PAYS, on day 7 as much as on day 1. It briefly read
	-- "Chimpanzini Bananini" on the hero card, copied off a reference screenshot -- day 7 grants
	-- 23,000 DNA, a potion, 2 diamonds and 3 shards and no creature at all, so the one card players
	-- streak a whole week for was advertising a pet that does not come.
	amountLabel.Text = formatNumber(reward.dna) .. " DNA"
	amountLabel.Parent = frame
	themeLabel(amountLabel, big and 24 or 19, Color3.fromRGB(24, 18, 38))

	local bonusLabel = Instance.new("TextLabel")
	bonusLabel.Name = "BonusLabel"
	bonusLabel.Size = UDim2.new(1, -12, 0, big and 32 or 22)
	bonusLabel.Position = UDim2.new(0, 6, 1, big and -54 or -28)
	bonusLabel.BackgroundTransparency = 1
	local bonusParts = {}
	if reward.potions then table.insert(bonusParts, "\u{1F9EA} x" .. reward.potions) end
	if reward.shards then table.insert(bonusParts, "\u{1F48E} x" .. reward.shards) end
	if reward.diamonds then table.insert(bonusParts, "\u{1F48E} x" .. reward.diamonds) end
	bonusLabel.Text = table.concat(bonusParts, "  ")
	bonusLabel.Visible = #bonusParts > 0
	bonusLabel.Parent = frame
	-- DARK INK, THE SAME ONE THE LINE ABOVE USES, AND IT IS A FIX RATHER THAN A MATCH (18.3). This
	-- label was the one thing on the card still taking `themeLabel`'s white default, which meant a
	-- white glyph read entirely off its 4 px halo -- fine at 30pt, mush at 17. It has been sitting on
	-- a cream tile at luminance 0.97 since the board was written, and the collected state added below
	-- is a `DoneShade` at 0.90, so the surface under it is now light in every one of the three states
	-- and white was wrong in all of them. The darkest fill it can land on is Coral at 0.57, where
	-- this ink measures 4.8:1.
	themeLabel(bonusLabel, big and 22 or 17, Color3.fromRGB(24, 18, 38))

	local checkmark = claimTick(frame, big and 44 or 36, big and 26 or 22)

	local claimButton = claimOverlay(frame)
	claimButton.MouseButton1Click:Connect(function()
		local cell = rewardCells[dayIndex]
		if cell and cell.isToday then
			Remotes.ClaimDailyReward:FireServer()
		end
	end)

	rewardCells[dayIndex] = {
		frame = frame, dayLabel = dayLabel, iconLabel = iconLabel,
		amountLabel = amountLabel, bonusLabel = bonusLabel,
		checkmark = checkmark, strokeInst = strokeInst,
		-- three more handles, all so `refreshRewardPanel` can repaint a state rather than build one:
		-- the day chip changes colour with the state, the plinth has to follow the tile's fill or it
		-- stops being the same object, and `idleThickness` keeps the hero's 5 px rim off a literal.
		headerPill = headerPill, plinth = plinth,
		idleColor = idleColor, idleThickness = big and 5 or 4, isToday = false,
	}
end

for d = 1, 6 do
	local row = math.floor((d - 1) / 3)
	local col = (d - 1) % 3
	buildDayCell(
		d,
		UDim2.new(0, CELL_W, 0, CELL_H),
		UDim2.new(0, GRID_X + col * (CELL_W + CELL_GAP), 0, GRID_Y + row * (CELL_H + CELL_GAP)),
		false
	)
end
buildDayCell(
	7,
	UDim2.new(0, DAY7_W, 0, CELL_H * 2 + CELL_GAP),
	UDim2.new(0, GRID_X + 3 * (CELL_W + CELL_GAP) + 6, 0, GRID_Y),
	true
)

-- NO SECOND FOOTER LINE HERE. One was added at (0.5, 1, -16) reading "Join Tomorrow For A Special
-- Reward!", which is the exact rectangle `rewardBannerCard` occupies (anchored 1,-14, 44 tall) --
-- so it was a fixed sentence drawn underneath a card that already says the same thing and says it
-- with the real day number ("Come back tomorrow for Day 6!"). Invisible, duplicated, and a
-- top-level local on a file that lives against Luau's 200-register cap.

-- ================= CODES (Phase 5.1) =================
--
-- IN THE DAILY PANEL, not on a tile of its own. The right-hand cluster is a full 2x4 grid after the
-- Audio tile took order 8, and a ninth would make it five rows deep and shift every tile on screen.
-- This is also simply where it belongs: the Daily panel is the free-stuff screen, it already wears
-- the "NEW!" badge that pulls players into it, and a code is the same kind of thing as a login
-- reward -- something you are given rather than something you buy.
--
-- Inside an immediately-called function with one refresh on `hudRefs`, per the register-cap rule.
;(function()
	local bar = Instance.new("Frame")
	bar.Name = "CodeBar"
	bar.Size = UDim2.new(1, -50, 0, 44)
	-- directly above the banner: banner sits at 1,-14 and is 44 tall, so its top edge is 1,-58
	bar.Position = UDim2.new(0.5, 0, 1, -66)
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.BackgroundTransparency = 1
	bar.ZIndex = rewardPanel.ZIndex + 1
	bar.Parent = rewardPanel

	local shell = Instance.new("Frame")
	shell.Name = "InputShell"
	shell.Size = UDim2.new(0.60, -6, 1, 0)
	shell.ZIndex = bar.ZIndex
	shell.Parent = bar
	-- PanelWhite, and the text on it is Outline rather than white: this is the one input surface in
	-- the game and a typed code has to be readable while it is being typed
	styleCard(shell, UITheme.Color.PanelWhite, UDim.new(1, 0), 4)

	local box = Instance.new("TextBox")
	box.Name = "CodeInput"
	box.BackgroundTransparency = 1
	box.Size = UDim2.new(1, -28, 1, -12)
	box.Position = UDim2.new(0, 14, 0.5, 0)
	box.AnchorPoint = Vector2.new(0, 0.5)
	box.ClearTextOnFocus = false
	box.Text = ""
	box.PlaceholderText = "\u{1F39F}\u{FE0F}  Enter a code..."
	box.PlaceholderColor3 = Color3.fromRGB(140, 136, 158)
	box.TextColor3 = UITheme.Color.Outline
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Font = UITheme.Font.Display
	box.TextScaled = true
	box.ZIndex = bar.ZIndex + UITheme.Z.Content
	box.Parent = shell
	local boxClamp = Instance.new("UITextSizeConstraint")
	boxClamp.MinTextSize = 14
	boxClamp.MaxTextSize = 22
	boxClamp.Parent = box

	local redeemButton = UITheme.Button(bar, {
		name = "Redeem", text = "REDEEM", color = UITheme.Color.Green,
		size = UDim2.new(0.25, -6, 1, 0), position = UDim2.new(0.60, 6, 0, 0),
		radius = 12, zIndex = bar.ZIndex, maxTextSize = 22, shadow = false,
	})

	local leftLabel = Instance.new("TextLabel")
	leftLabel.Name = "CodesLeft"
	leftLabel.Size = UDim2.new(0.15, -6, 1, 0)
	leftLabel.Position = UDim2.new(0.85, 6, 0, 0)
	leftLabel.BackgroundTransparency = 1
	leftLabel.Text = ""
	leftLabel.ZIndex = bar.ZIndex + UITheme.Z.Content
	leftLabel.Parent = bar
	themeLabel(leftLabel, 20)

	local function submit()
		local typed = box.Text
		if typed:gsub("%s", "") == "" then return end
		-- looked up rather than held, like the audio remote: CodesService creates it in Init and a
		-- WaitForChild at build time would stall the HUD if that ever stopped happening
		local remote = Remotes:FindFirstChild("RedeemCode")
		if remote then
			remote:FireServer(typed)
		end
		-- cleared either way. The server answers with a toast, and leaving a refused code sitting in
		-- the box invites the player to press REDEEM again into the rate limiter.
		box.Text = ""
	end

	redeemButton.MouseButton1Click:Connect(submit)
	-- Enter submits: this is a box people paste into off a web page, and reaching for a button
	-- afterwards is the kind of small friction that makes a code feel broken
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then submit() end
	end)

	-- Counted CLIENT-SIDE off GameConfig and the save the client already holds -- the same arithmetic
	-- CodesService.CountUnused does server-side, but asking for it would be a remote round trip for a
	-- number both sides can already see.
	hudRefs.refreshCodes = function(data)
		local redeemed = (data and data.RedeemedCodes) or {}
		local left = 0
		for _, entry in ipairs(GameConfig.Codes) do
			if not GameConfig.IsCodeExpired(entry)
				and not redeemed[GameConfig.NormaliseCode(entry.code)] then
				left += 1
			end
		end
		-- says nothing at all when there is nothing left to say, rather than printing "0 left" as a
		-- small permanent disappointment on the free-stuff screen
		leftLabel.Text = left > 0 and (left .. " new") or ""
	end
end)()

local rewardBannerCard = Instance.new("Frame")
rewardBannerCard.Name = "BannerCard"
rewardBannerCard.Size = UDim2.new(1, -50, 0, 44)
rewardBannerCard.Position = UDim2.new(0.5, 0, 1, -14)
rewardBannerCard.AnchorPoint = Vector2.new(0.5, 1)
rewardBannerCard.Parent = rewardPanel
styleCard(rewardBannerCard, UITheme.Color.Purple, UDim.new(1, 0), 4)

local rewardBannerLabel = Instance.new("TextLabel")
rewardBannerLabel.Name = "BannerLabel"
rewardBannerLabel.Size = UDim2.new(1, -28, 1, -16)
rewardBannerLabel.Position = UDim2.new(0.5, 0, 0.5, -3)
rewardBannerLabel.AnchorPoint = Vector2.new(0.5, 0.5)
rewardBannerLabel.BackgroundTransparency = 1
rewardBannerLabel.Text = "Come back tomorrow for the next reward!"
rewardBannerLabel.Parent = rewardBannerCard
themeLabel(rewardBannerLabel, 24)

rewardButton.MouseButton1Click:Connect(function()
	toggleOnly(rewardPanel)
end)

local SECONDS_PER_DAY = 86400
local function dayNumber(timestamp)
	return math.floor((timestamp or 0) / SECONDS_PER_DAY)
end

-- ================= THE TWO WAYS INTO THE WHEEL (Phase 5.6 + 9.4) =================
--
-- Placed HERE rather than beside the rest of the Daily panel further up, and the reason is a Lua
-- one: `dayNumber` is declared a few lines above, so a closure written earlier in the file would
-- not have it in scope. The button is still parented to `rewardPanel`, which has existed since
-- line ~2351.
--
-- It reads the SAME day boundary the server does (RewardService.GetFreeSpinStatus) off the same
-- field, so the button can never offer a spin the server will refuse -- the property the evolve
-- button already has against GetEvolveStep.
;(function()
	local button = UITheme.Button(rewardPanel, {
		name = "FreeSpin", text = "\u{1F3A1} FREE SPIN", color = UITheme.Color.Gold,
		-- 54 -> 90: at 54 this pair sat INSIDE the accent band, printing over the streak subtitle.
		-- 90 puts them in their own row between the band (ends 82) and the day grid (starts 142).
		size = UDim2.new(0, 220, 0, 42), position = UDim2.new(1, -22, 0, 90),
		anchorPoint = Vector2.new(1, 0), radius = 14,
		zIndex = rewardPanel.ZIndex + 1, maxTextSize = 22,
	})

	-- THE SHARD SPIN SITS BESIDE THE FREE ONE, and that placement is the point (9.4). They are the
	-- same wheel reached by two triggers, so putting them together is what makes the relationship
	-- legible -- free once a day, or 25 Shards whenever you have climbed for them -- where a shard
	-- wheel hidden on some other screen would read as a second, different gamble. It fits in the
	-- band the streak card (ends x262) and the free spin button (starts x458) leave empty, so
	-- nothing already measured on this panel moves.
	local shardButton = UITheme.Button(rewardPanel, {
		name = "ShardSpin", text = "\u{1F3A1} SPIN 25\u{1F31F}", color = UITheme.Color.Locked,
		size = UDim2.new(0, 170, 0, 42), position = UDim2.new(1, -250, 0, 90),
		anchorPoint = Vector2.new(1, 0), radius = 14,
		zIndex = rewardPanel.ZIndex + 1, maxTextSize = 22,
	})

	-- "7h 12m", "12m", "45s" -- the same shape the offline card uses, for the same reason: the
	-- player is reading it for "roughly when", not for the exact second.
	local function countdown(seconds)
		seconds = math.max(math.floor(seconds), 0)
		local h = seconds // 3600
		local m = (seconds % 3600) // 60
		if h > 0 then return ("%dh %dm"):format(h, m) end
		if m > 0 then return ("%dm"):format(m) end
		return ("%ds"):format(seconds)
	end

	-- Held inside this closure rather than as a top-level local: MainUI is at Luau's 200-local
	-- register cap and one more up there deletes the whole HUD. It is also the only thing `refresh`
	-- below needs to know about the nag, so it does not want to be visible any wider.
	local nagUntil = 0

	local function refresh()
		if not currentData then return end
		-- a "not ready yet" message on a button gets one and a half seconds to be read before the
		-- one-second tick below paints the countdown back over it
		if os.clock() < nagUntil then return end
		local ready = dayNumber(os.time()) > dayNumber(currentData.LastFreeSpin)
		if ready then
			UITheme.SetColor(button, UITheme.Color.Gold)
			UITheme.SetText(button, "\u{1F3A1} FREE SPIN!")
		else
			-- colour AND wording, like the Auto tile and the mute button: a control that only changes
			-- hue leaves the player guessing whether it is off or just decorated
			UITheme.SetColor(button, UITheme.Color.Locked)
			UITheme.SetText(button, "\u{1F3A1} " .. countdown((dayNumber(os.time()) + 1) * SECONDS_PER_DAY - os.time()))
		end

		-- The shard button reads the same price the server charges (GameConfig.SpinCostShards), so it
		-- can never offer a spin SpendShardSpin will refuse -- the property the evolve button has
		-- against GetEvolveStep and the free spin has against GetFreeSpinStatus.
		--
		-- When it cannot be afforded it shows PROGRESS rather than the price again. "12 / 25" tells a
		-- player who has never seen a shard both what the thing costs and that they are getting
		-- there; a greyed-out "SPIN 25" tells them only that they cannot press it.
		local cost = GameConfig.SpinCostShards
		local held = math.floor(currentData.EvolutionShards or 0)
		if held >= cost then
			UITheme.SetColor(shardButton, UITheme.Color.Purple)
			UITheme.SetText(shardButton, ("\u{1F3A1} SPIN %d\u{1F31F}"):format(cost))
		else
			UITheme.SetColor(shardButton, UITheme.Color.Locked)
			UITheme.SetText(shardButton, ("\u{1F31F} %d / %d"):format(held, cost))
		end
	end

	-- A MISSING REMOTE MUST SAY SO. Both spin buttons look their remote up with FindFirstChild
	-- INSIDE the handler -- correct, because RewardService and RobuxShopService create them on
	-- demand and the order is not guaranteed -- but the `if remote then` was silent on the else,
	-- so a button whose service had not finished starting was indistinguishable from a broken one.
	-- That is half of the "claim/spin buttons do not work" report, and it is the half that leaves
	-- no evidence behind.
	--
	-- The message goes ON THE BUTTON rather than through showNotification, and that is a scope fact
	-- rather than a design one: showNotification is declared ~2400 lines below here, so a closure
	-- written at this point captures nil and the click would throw instead of explaining itself.
	local function nagNotReady(target)
		nagUntil = os.clock() + 1.5
		UITheme.SetColor(target, UITheme.Color.Locked)
		UITheme.SetText(target, "\u{23F3} not ready")
	end

	button.MouseButton1Click:Connect(function()
		local remote = Remotes:FindFirstChild("ClaimFreeSpin")
		if remote then
			remote:FireServer()
		else
			nagNotReady(button)
		end
	end)

	-- Fired unconditionally rather than gated on the local affordability check: the client's copy of
	-- the save is up to a push behind, and a button that silently does nothing is worse than the
	-- server's own "you need 25" toast. The server is the one that decides either way.
	shardButton.MouseButton1Click:Connect(function()
		local remote = Remotes:FindFirstChild("SpinWithShards")
		if remote then
			remote:FireServer()
		else
			nagNotReady(shardButton)
		end
	end)

	-- Ticked only while the panel is actually open. A countdown nobody is looking at is a string
	-- rebuild and two property writes a second, forever, on every client in the server.
	task.spawn(function()
		while true do
			task.wait(1)
			if rewardPanel.Visible then
				refresh()
			end
		end
	end)

	-- one handle for both buttons: they are two states of the same question ("can I spin, and how")
	hudRefs.refreshSpins = refresh
end)()

local function refreshRewardPanel()
	currentData = getCurrentData()
	if not currentData then return end
	local data = currentData
	local today = dayNumber(os.time())
	local lastDay = dayNumber(data.LastRewardClaim)
	local canClaim = today > lastDay
	local streak = data.RewardStreak or 0

	rewardStreakLine.Text = "🔥 Streak: " .. streak .. " day" .. (streak == 1 and "" or "s")

	local upcomingStreak = streak
	if canClaim then
		upcomingStreak = (today == lastDay + 1) and (streak + 1) or 1
	end
	if upcomingStreak < 1 then upcomingStreak = 1 end
	local rewardIndex = ((upcomingStreak - 1) % #GameConfig.DailyRewards) + 1

	local claimedUpTo = canClaim and (rewardIndex - 1) or rewardIndex
	local todayIndex = canClaim and rewardIndex or nil

	-- ===== THREE STATES ON THREE DIFFERENT AXES (18.3) =====
	--
	-- What she photographed: six claimed days painted `Color.Locked` -- flat rgb(163,161,180) with a
	-- small green tick -- and one bright Day 7. "izgleda kao da dobijam rewards sto radim u
	-- mrtvacnici". `Locked` is the kit's REFUSAL swatch and four different states were reaching for
	-- it; a collected day is not a refusal, it is the record of a thing the player did, and painting
	-- it in the refusal colour is what made a panel full of achievement look like a panel full of
	-- nothing.
	--
	-- So the three states now differ on three different properties rather than on one:
	--
	--   claimable   FULL chroma -- `Color.Green`, the one hue this kit reserves for "act now" --
	--               plus the bright rim at +1 thickness, a READY_RIM day chip reading CLAIM!, and the
	--               single idle pulse. Loud by RULE now: every branch of it is applied here, off
	--               `isToday`, so it no longer depends on the day happening to be the gold one.
	--   collected   the day's OWN hue at about a third of the chroma (`UITheme.DoneShade`). Same
	--               colour, quieter -- a claimed potion day is still purple and a claimed diamond day
	--               is still cyan, so a week of collecting reads as a week of collecting. The green
	--               tick coin stays and is what separates it from a day that is merely not due yet.
	--   not yet     the day's own hue at full strength, dark rim, no tick, no chip.
	--
	-- None of the seven idle hues is green (see `dayHues`), so the claimable tile can never be
	-- confused with the tile beside it, whichever day of the week it lands on.
	for d = 1, 7 do
		local cell = rewardCells[d]
		if cell then
			local isClaimed = d <= claimedUpTo
			local isToday = (d == todayIndex)
			cell.isToday = isToday
			cell.checkmark.Visible = isClaimed
			-- state reads off the shell colour, not transparency: fading the card would
			-- eat the outline and the gradient that make it look moulded.
			local fill = cell.idleColor
			if isToday then
				fill = UITheme.Color.Green
			elseif isClaimed then
				fill = UITheme.DoneShade(cell.idleColor)
			end
			cell.strokeInst.Color = isToday and READY_RIM or OUTLINE_COLOR
			cell.strokeInst.Thickness = cell.idleThickness + (isToday and 1 or 0)
			cell.dayLabel.Text = isToday and "CLAIM!" or ("Day " .. d)
			setButtonColor(cell.frame, fill)
			-- The chip and the plinth follow the face, or the tile stops reading as one object: a
			-- white chip on a pale collected tile has no edge left, and a plinth still cut from the
			-- old hue looks like a sticker somebody forgot to update.
			setButtonColor(cell.headerPill, isToday and READY_RIM or UITheme.Color.PanelWhite)
			setButtonColor(cell.plinth, shade(fill, -0.16))

			-- ===== "DA SLJASTI STA JE BITNO" -- THE KIT'S OWN IDLE PULSE, FINALLY WIRED =====
			--
			-- `UITheme.Attention` has existed since the motion research landed and had ZERO call sites
			-- in the game: a `repeatCount = -1, reverses = true` tween at peak 1.05 over a 0.35 s beat
			-- with a 3.2 s gap, and the kit holds ONE slot so two things can never pulse at once.
			-- Priority 2 is the number its own comment block names for this exact caller.
			--
			-- ONLY WHILE THE PANEL IS OPEN, which is the conservative half rather than the clever one:
			-- the slot is global, this refresh runs on every DataUpdate whether the board is on screen
			-- or not, and a pulse held by a hidden panel would lock every future caller out of it for
			-- the session. Turning it off is the half that matters (§2.5), so the else-branch is
			-- unconditional -- it is safe on a tile that was never pulsing, it covers the day that was
			-- just claimed, and it covers "there is nothing to claim today" without a second test.
			--
			-- PEAK 1.03 RATHER THAN THE KIT'S 1.05, and it is geometry, not taste. A `UIScale` grows a
			-- GuiObject about its AnchorPoint and these cells are anchored (0,0), so every pixel of the
			-- growth goes down and right into the 8 px grid gutter. The hero column is 372 tall: at
			-- 1.05 it would reach 18.6 px past its own bottom edge and climb into the code bar, at 1.03
			-- it reaches 11.2 and the panel is sized to clear that (see rewardPanel.Size).
			if isToday and rewardPanel.Visible then
				UITheme.Attention(cell.frame, true, { priority = 2, peak = 1.03 })
			else
				UITheme.Attention(cell.frame, false)
			end
		end
	end

	if rewardBadge then
		rewardBadge.Visible = canClaim
	end

	if canClaim then
		rewardBannerLabel.Text = "🎉 Day " .. rewardIndex .. " is ready — click it to claim!"
		setButtonColor(rewardBannerCard, UITheme.Color.Green)
	else
		local nextDay = (streak % #GameConfig.DailyRewards) + 1
		rewardBannerLabel.Text = "Come back tomorrow for Day " .. nextDay .. "!"
		setButtonColor(rewardBannerCard, UITheme.Color.Purple)
	end
end

-- THE PULSE IS GATED ON `rewardPanel.Visible` (see the block inside the loop above) and this refresh
-- only runs on a DataUpdate -- which may have been minutes before the player opened the board. So
-- opening it re-asks the question; there is no cheaper way to start a pulse on a panel that was
-- already correct when it was hidden. A second connection rather than a branch inside the backdrop
-- fade above, because that one is written 400 lines earlier than this function exists and a closure
-- there would resolve `refreshRewardPanel` to a nil global -- the same upvalue trap `corner` and the
-- ZoneBuilder forward-declarations are documented for at the top of this file.
rewardPanel:GetPropertyChangedSignal("Visible"):Connect(function()
	if rewardPanel.Visible then
		refreshRewardPanel()
	else
		for _, cell in pairs(rewardCells) do
			UITheme.Attention(cell.frame, false)
		end
	end
end)


    hudRefs.refreshRewardPanel = refreshRewardPanel
end

return DailyRewardsPanel
