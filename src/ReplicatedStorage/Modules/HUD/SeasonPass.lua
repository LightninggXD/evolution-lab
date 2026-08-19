-- SeasonPass -- the whole Season Pass: the track, the free and premium rows, the claim and the tile.
--
-- MOVED OUT OF `MainUI` (18.9), byte for byte. It was already a closed
-- `;(function() ... end)()` block -- the shape this file's 200-register ceiling forces
-- every panel into -- so the extraction is a change of wrapper, not of code. See
-- `docs/SPLIT.md` for the `hud` contract and `docs/CODEMAP.md` for where the rest went.

local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))

local Remotes = RS.Remotes

local formatNumber, gradient, shade, themeLabel = UIKit.formatNumber, UIKit.gradient, UIKit.shade, UIKit.themeLabel
local styleCard, styleButton, setButtonColor, OUTLINE_COLOR = UIKit.styleCard, UIKit.styleButton, UIKit.setButtonColor, UIKit.OUTLINE_COLOR
local PANEL_SHELL, PET_ROW_SHELL, READY_RIM = UIKit.PANEL_SHELL, UIKit.PET_ROW_SHELL, UIKit.READY_RIM

return function(hud)
	local PANEL_ANCHOR, columnTile, panelClose = hud.PANEL_ANCHOR, hud.columnTile, hud.panelClose
	local registerPanel, screenGui, toggleOnly = hud.registerPanel, hud.screenGui, hud.toggleOnly

	local SEASON = GameConfig.Season
	local CELL = 92          -- one reward cell, square
	local PITCH = 104        -- ...plus the gap to the next column
	local PAGE_TOP = 148
	-- ===== THE BOARD'S VERTICAL ARITHMETIC, WRITTEN DOWN INSTEAD OF TYPED FOUR TIMES (18.6) =====
	--
	-- The tray height, the scroll height, the column height and the two rotated row tags were five
	-- independent literals that all encoded the same stack, with the derivation living only in a
	-- comment ("the scroll (254) centres in the tray (286) at y=16..."). Changing the rail -- which
	-- this row does -- moved four of the five and there was nothing to recompute them from. They are
	-- one expression now, so the next person to touch the rail changes RAIL_H and nothing else.
	local RAIL_H = 16        -- was 26; see the rail comment below for why it got thinner
	local COL_GAP = 5        -- the column layout's padding, twice over
	local TRAY_H = 286
	local SCROLL_H = 254
	local COL_H = CELL * 2 + RAIL_H + COL_GAP * 2                 -- 92+92+16+10 = 210
	local SCROLL_TOP = (TRAY_H - SCROLL_H) / 2                    -- 16, the scroll's inset in the tray
	local COL_TOP = SCROLL_TOP + (SCROLL_H - COL_H) / 2           -- 16 + 22 = 38, the free cell's top
	local FREE_TAG_Y = COL_TOP + CELL / 2                         -- 84  (was 79 at RAIL_H = 26)
	local PREMIUM_TAG_Y = COL_TOP + CELL + COL_GAP * 2 + RAIL_H + CELL / 2  -- 202 (was 207)

	local panel = Instance.new("Frame")
	panel.Name = "SeasonPanel"
	panel.Size = UDim2.new(0, 880, 0, 522)
	panel.Position = PANEL_ANCHOR
	panel.ZIndex = 20
	panel.Visible = false
	panel.Parent = screenGui
	styleCard(panel, PANEL_SHELL, UDim.new(0, 22), 5)
	registerPanel(panel)
	panelClose(panel)

	-- Converted to the shared accent band (17.x), the last of the nine. The band spans the full
	-- width, so the two tabs could no longer share the title's row -- they drop to their own row
	-- under it (y = 94) and start at the panel margin instead of at x = 360, where they used to sit
	-- beside the title. PAGE_TOP follows them down: 94 + the 42 px tab + 12 = 148.
	--
	-- The TITLE handle is kept because `refresh` rewrites it -- 7.3 made the season id and name
	-- functions of the DATE, so a title written once at build time names last month's season for the
	-- whole of this one, and a session can span the turnover. That is what PanelHeader's third
	-- return value is for.
	local title = select(3, UITheme.PanelHeader(panel, {
		title = GameConfig.GetCurrentSeason().emoji .. " " .. GameConfig.GetCurrentSeason().name,
		subtitle = "Earn season XP to unlock every reward",
		accent = UITheme.Color.Coral,
	}))

	-- ---- the two remotes this panel talks over. Newer than the authored Remotes folder, so they
	-- are waited for by name rather than indexed -- SeasonPassService creates whichever is missing.
	local claimQuestRemote, claimRewardRemote
	task.spawn(function()
		claimQuestRemote = Remotes:WaitForChild("ClaimQuest", 30)
		claimRewardRemote = Remotes:WaitForChild("ClaimSeasonReward", 30)
	end)

	-- ---- pages
	local function newPage(name)
		local page = Instance.new("Frame")
		page.Name = name
		page.Size = UDim2.new(1, -28, 1, -(PAGE_TOP + 14))
		page.Position = UDim2.new(0, 14, 0, PAGE_TOP)
		page.BackgroundTransparency = 1
		page.ZIndex = panel.ZIndex + UITheme.Z.Content
		page.Visible = false
		page.Parent = panel
		return page
	end
	local trackPage = newPage("TrackPage")
	local questPage = newPage("QuestPage")

	-- ---- tabs
	local tabs = {}
	local currentTab = "track"
	local function setTab(name)
		currentTab = name
		trackPage.Visible = (name == "track")
		questPage.Visible = (name == "quests")
		for key, btn in pairs(tabs) do
			-- ===== AN UNSELECTED TAB IS NOT A REFUSED ONE (18.6) =====
			--
			-- `Color.Locked` here said "you cannot press this" about the one control on the panel that
			-- always can be pressed -- and it is half of what made the top of this screen read grey.
			-- Lavender is a live surface (lum 0.635, white ink with its halo, same as every other
			-- chromatic button in the kit) and Sunny at 0.82 is plainly the brighter of the two, so
			-- "which one am I on" is answered by warmth and not by whether the control looks dead.
			setButtonColor(btn, key == name and UITheme.Color.Sunny or UITheme.Color.Lavender)
		end
	end

	-- ===== THE TABS NOW SPAN THE PANEL (18.6) =====
	--
	-- Two 190 px tabs at x=16 and x=216 end at 406 on an 880 px panel: **458 px of bare white** to
	-- their right, which is the widest empty rectangle in the game. Widened to 260 on a 270 pitch
	-- (16..276 and 286..546) and the remaining band is filled by the collected-rewards chip below,
	-- which lands at 566..864 against the panel's own 16 px right margin.
	for i, spec in ipairs({
		{ key = "track",  text = SEASON.emoji .. " Season Pass" },
		{ key = "quests", text = "\u{1F4CB} Quests" },
	}) do
		local btn = Instance.new("TextButton")
		btn.Name = "Tab_" .. spec.key
		btn.Size = UDim2.new(0, 260, 0, 42)
		btn.Position = UDim2.new(0, 16 + (i - 1) * 270, 0, 94)
		btn.Text = spec.text
		btn.ZIndex = panel.ZIndex + UITheme.Z.Content
		btn.Parent = panel
		styleButton(btn, UITheme.Color.Locked, UDim.new(0, 14))
		btn.MouseButton1Click:Connect(function()
			setTab(spec.key)
		end)
		tabs[spec.key] = btn
	end

	-- ===== WHAT GOES IN THE BAND: THE ONE NUMBER THIS PANEL NEVER SHOWED (18.6) =====
	--
	-- Everything else on the screen is a reading of XP -- the level badge, the XP bar, the node the
	-- board is lit up to. None of them says *how much of the pass you actually own*, which is the
	-- question a child opens a season pass to answer, and it is a different number from the level
	-- (premium rows you have passed but not bought are levels earned and rewards not held).
	--
	-- Deliberately NOT a third bar. This row is about there being two readings of one number
	-- already; the fix cannot be a fourth surface animating along a track. It is a count.
	local tally = Instance.new("TextLabel")
	tally.Name = "CollectedChip"
	tally.Size = UDim2.new(0, 298, 0, 42)
	tally.Position = UDim2.new(1, -16, 0, 94)
	tally.AnchorPoint = Vector2.new(1, 0)
	tally.Text = ("\u{1F381} 0 / %d collected"):format(SEASON.maxLevel * 2)
	tally.ZIndex = panel.ZIndex + UITheme.Z.Content
	tally.Parent = panel
	-- Aqua rather than a green: Green is the one "press me" colour on the board below and a bright
	-- green chip in the header would be read as a button. A TextLabel handed to `styleCard` is
	-- mirrored above `InnerBody` now (see styleCard), which is the only reason this can be a shell at
	-- all -- before this session it would have shipped as a blank blue pill.
	styleCard(tally, UITheme.Color.Aqua, UDim.new(0, 14), 4)
	themeLabel(tally, 22)

	-- ================= TRACK PAGE =================

	-- left: the level badge and the XP bar, the two numbers the whole page is about
	local sideCard = Instance.new("Frame")
	sideCard.Size = UDim2.new(0, 210, 1, 0)
	sideCard.Parent = trackPage
	styleCard(sideCard, UITheme.Color.Lavender, UDim.new(0, 18), 4)

	-- ===== THE SECOND BAR IS GONE, AND THE ONE THAT WENT IS THIS ONE (19.13) =====
	--
	-- 18.6 already answered "ovde imaju 2 progres bara sta ce mi" by taking the analogue reading off
	-- the RAIL and keeping the bar here, on the argument that the bar is the only one of the two
	-- carrying text. She looked at the result and said the opposite -- *"ovaj levo ne treba"* -- and
	-- she is right for a reason the first pass missed: the rail is the surface a player actually
	-- reads the season on, because it runs under the sixty rewards and tells you which of them you
	-- have passed. A 186 x 30 green bar in the corner competes with it and reports the same journey
	-- at a tenth of the resolution.
	--
	-- So the level card stops being a second instrument and becomes a READOUT: a caption, the level
	-- as one large numeral, and the XP as text in a `Cloud` well. Nothing animates along a track
	-- here any more -- the board does that. Note this also gives a register back rather than costing
	-- one, which matters (see the ProgressBar note this replaced: the file is at Luau's 200-local
	-- ceiling and the two bar handles were two of them).
	local levelCaption = Instance.new("TextLabel")
	levelCaption.Name = "LevelCaption"
	levelCaption.Size = UDim2.new(1, -20, 0, 22)
	levelCaption.Position = UDim2.new(0, 10, 0, 16)
	levelCaption.BackgroundTransparency = 1
	levelCaption.Text = "SEASON LEVEL"
	levelCaption.Parent = sideCard
	themeLabel(levelCaption, 15, UITheme.Color.Cream)

	local levelLabel = Instance.new("TextLabel")
	levelLabel.Size = UDim2.new(1, -20, 0, 74)
	levelLabel.Position = UDim2.new(0, 10, 0, 38)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text = "1"
	levelLabel.Parent = sideCard
	themeLabel(levelLabel, 58)

	-- `Cloud` is the kit's inset token and the well is what makes this read as a readout rather than
	-- as a fourth chip: it is the only sunken surface on the page. Dark ink on it, which drops its
	-- halo automatically -- the luminance branch in `themeLabel` owns that decision, so a colour
	-- change here can never reintroduce the black-blob bug.
	local xpReadout = Instance.new("TextLabel")
	xpReadout.Name = "SeasonXP"
	xpReadout.Size = UDim2.new(1, -24, 0, 36)
	xpReadout.Position = UDim2.new(0.5, 0, 0, 118)
	xpReadout.AnchorPoint = Vector2.new(0.5, 0)
	xpReadout.Text = "0 / " .. SEASON.xpPerLevel .. " XP"
	xpReadout.ZIndex = sideCard.ZIndex + UITheme.Z.Content
	xpReadout.Parent = sideCard
	styleCard(xpReadout, UITheme.Color.Cloud, UDim.new(0, 12), 3)
	themeLabel(xpReadout, 17, UITheme.Color.Ink)

	local premiumStatus = Instance.new("TextLabel")
	premiumStatus.Size = UDim2.new(1, -20, 0, 100)
	premiumStatus.Position = UDim2.new(0, 10, 0, 168)
	premiumStatus.BackgroundTransparency = 1
	premiumStatus.TextWrapped = true
	premiumStatus.Text = ""
	premiumStatus.Parent = sideCard
	themeLabel(premiumStatus, 17, UITheme.Color.Cream)

	local premiumButton = Instance.new("TextButton")
	premiumButton.Size = UDim2.new(1, -24, 0, 52)
	premiumButton.Position = UDim2.new(0.5, 0, 1, -16)
	premiumButton.AnchorPoint = Vector2.new(0.5, 1)
	premiumButton.Text = "Get Premium"
	premiumButton.Parent = sideCard
	styleButton(premiumButton, UITheme.Color.Gold, UDim.new(0, 14))
	premiumButton.MouseButton1Click:Connect(function()
		Remotes.PromptRobuxPurchase:FireServer("SeasonPremium")
	end)

	-- ===== THE TRACK SITS IN A TRAY (15.28) =====
	--
	-- Thirty columns floating on the shell's bare grey read as a spreadsheet: nothing said where the
	-- board began or ended, and the two rows were told apart only by a padlock glyph on the lower
	-- one. The tray draws the board, and its left gutter names the rows ONCE instead of thirty
	-- times -- the columns are 92px wide and a "PREMIUM" caption does not fit in one, which is why
	-- the row had no label at all before.
	--
	-- ZIndex 8 is deliberate and low. Inside `trackPage` the only siblings are `sideCard` (styleCard
	-- leaves it in the 1..5 band, since nothing sets its ZIndex) and `trackScroll` at 24, so the
	-- tray's own shadow at 8+Z.Content clears the card and stays under every column. It does not
	-- need to clear the PANEL's shadow: under ZIndexBehavior.Sibling a child always draws above its
	-- parent, and this is a child of trackPage.
	local tray = Instance.new("Frame")
	tray.Name = "TrackTray"
	tray.Size = UDim2.new(1, -214, 0, TRAY_H)
	tray.Position = UDim2.new(0, 214, 0.5, 0)
	tray.AnchorPoint = Vector2.new(0, 0.5)
	tray.ZIndex = 8
	tray.Parent = trackPage
	-- ===== THE DARKEST SURFACE IN THE GAME, AND IT WAS 182,000 PX OF IT (18.6) =====
	--
	-- It was an explicit violet, rgb(104,98,138) -- luminance **0.41**, measured against every other
	-- panel in this file sitting between 0.89 and 1.00. 666 x 286 px of it, filling the whole right
	-- three quarters of the panel Kristina photographed when she said "puno je sivo i monotono". The
	-- reasoning for picking a violet was right (a *shade* of PANEL_SHELL comes out a hueless grey,
	-- because GradientFor drops white's foot to rgb(163,160,176)) and the VALUE was the mistake: the
	-- fix for "grey" was a dark colour rather than a light one.
	--
	-- `Color.Cloud` is the kit's own token for exactly this object -- "an inset rather than a raised
	-- chip: progress-bar tracks, wells, list backings" -- rgb(222,228,244), **luminance 0.89**, still
	-- comfortably a light surface, and it is what every groove in the game is already made of. It
	-- keeps the violet hue that made the tray read as a board rather than as more panel (hue 227deg,
	-- the same family as the old fill) at a value that lets the sixty reward cells carry the colour
	-- instead of fighting a dark ground for it. Luminance 0.41 -> 0.89.
	styleCard(tray, UITheme.Color.Cloud, UDim.new(0, 18), 4)

	-- Rotated -90 ABOUT ITS OWN CENTRE, so the box is authored landscape and lands portrait. A
	-- 44-wide box carrying the same Rotation would still be measured 44 wide before the turn and
	-- the 92px of text would spill sideways over the first column.
	-- The y values are the two card rows and they are DERIVED now (see the constants at the top of
	-- this block) rather than measured once by hand: FREE_TAG_Y = 84, PREMIUM_TAG_Y = 202, which is
	-- the 79/207 pair moved by the rail losing 10 px of height.
	--
	-- The two colours are a hierarchy, not decoration, and they had to change with the tray. Cream on
	-- a 0.41 violet was a white word on a dark board; on `Cloud` (0.89) it would be white on
	-- near-white. `Color.Ink` (lum 0.17) is dark ink and therefore drops its halo by the same rule
	-- every other dark label in this file uses -- it reads as the ordinary row. Gold keeps its 4 px
	-- near-black halo and is the only loud thing in the gutter, which is the point: PREMIUM is the
	-- row you are being sold.
	for _, tag in ipairs({
		{ text = "FREE", y = FREE_TAG_Y, color = UITheme.Color.Ink },
		{ text = "PREMIUM", y = PREMIUM_TAG_Y, color = UITheme.Color.Gold },
	}) do
		local tagLabel = Instance.new("TextLabel")
		tagLabel.Name = tag.text .. "Tag"
		tagLabel.Size = UDim2.new(0, 92, 0, 44)
		tagLabel.Position = UDim2.new(0, 27, 0, tag.y)
		tagLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		tagLabel.BackgroundTransparency = 1
		tagLabel.Rotation = -90
		tagLabel.Text = tag.text
		tagLabel.Parent = tray
		themeLabel(tagLabel, 20, tag.color)
	end

	-- right: the thirty columns, scrolling sideways. x=268 rather than 224 -- the 44px it gives up
	-- is the tray's gutter, and the canvas scrolls anyway so no reward cell is lost for it.
	local trackScroll = Instance.new("ScrollingFrame")
	trackScroll.Name = "TrackScroll"
	trackScroll.Size = UDim2.new(1, -268, 0, SCROLL_H)
	trackScroll.Position = UDim2.new(0, 268, 0.5, 0)
	trackScroll.AnchorPoint = Vector2.new(0, 0.5)
	trackScroll.BackgroundTransparency = 1
	trackScroll.BorderSizePixel = 0
	trackScroll.ScrollBarThickness = 8
	trackScroll.ScrollingDirection = Enum.ScrollingDirection.X
	trackScroll.CanvasSize = UDim2.new(0, SEASON.maxLevel * PITCH + 8, 0, 0)
	trackScroll.ZIndex = trackPage.ZIndex
	trackScroll.Parent = trackPage

	local trackLayout = Instance.new("UIListLayout")
	trackLayout.FillDirection = Enum.FillDirection.Horizontal
	trackLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	trackLayout.SortOrder = Enum.SortOrder.LayoutOrder
	trackLayout.Padding = UDim.new(0, 12)
	trackLayout.Parent = trackScroll

	-- What a cell shows: the best thing in the reward as one big icon, and its count under it.
	-- A cell is 92px square -- it cannot list four payouts, and the point of the icon is to be
	-- recognisable at a glance while scrolling past thirty of them.
	--
	-- THE THIRD RETURN IS THE REWARD'S OWN HUE (18.6), and it is what stops a claimed cell going
	-- grey. Four payout kinds, four kit tokens, chosen so that **none of them is Green**: Green is
	-- the one "press me" colour on this board, and an idle cell wearing it would compete with the
	-- sixty cells that genuinely can be claimed -- the same collision the Daily ramp was designed
	-- around in 18.3. Shards take Sunny because the shard glyph is already yellow, diamonds Aqua,
	-- potions Bubblegum, DNA Lavender.
	local function rewardFace(reward)
		if reward.shards then return "\u{2728}", "x" .. reward.shards, UITheme.Color.Sunny end
		if reward.diamonds then return "\u{1F48E}", "x" .. reward.diamonds, UITheme.Color.Aqua end
		if reward.potions then
			local potion = reward.potionId and GameConfig.GetPotion(reward.potionId)
			return potion and potion.emoji or "\u{1F9EA}", "x" .. reward.potions, UITheme.Color.Bubblegum
		end
		return "\u{1F9EC}", formatNumber(reward.dna or 0), UITheme.Color.Lavender
	end

	-- ===== INK FOLLOWS THE FILL, ON EVERY REPAINT (18.6) =====
	--
	-- `themeLabel` decides ink once and latches it behind a `Themed` attribute, which is correct for
	-- a label whose surface never changes colour. Every caption on this board sits on a surface that
	-- is repainted four different ways by `refresh`, and one of those ways is now `DoneShade` -- a
	-- fill at luminance 0.90, i.e. above the kit's 0.86 `LIGHT_SURFACE` cut, where white text with a
	-- 4 px near-black halo reads as a black smudge. Ink and halo move together (rule 7) or the dark
	-- glyph ends up inside a dark outline, which is the blob this file has already paid for twice.
	--
	-- Takes the HOST, never the proxy: both `styleButton` (TextButton -> `Label`) and `styleCard`'s
	-- new mirror (TextLabel -> `Label`) forward `TextColor3` to their child, so writing it here is
	-- what keeps every call site's `x.Text = ...` working. Neither of them forwards stroke WIDTH --
	-- the kit's hook moves transparency only -- so the halo is corrected on whichever instance
	-- actually draws the glyph.
	local function inkOnCell(host, fill)
		local light = UITheme.IsLightSurface(fill)
		host.TextColor3 = light and UITheme.Color.Ink or UITheme.Color.White
		local drawn = host:FindFirstChild("Label")
		if not (drawn and drawn:IsA("TextLabel")) then
			drawn = host
		end
		local st = drawn:FindFirstChildOfClass("UIStroke")
		if st then
			st.Thickness = light and 0 or 4
			st.Transparency = light and 1 or 0
		end
	end

	local cells = {} -- [level] = { free = refs, premium = refs }

	local function buildCell(parent, level, track, order)
		local btn = Instance.new("TextButton")
		btn.Name = track
		btn.Size = UDim2.new(0, CELL, 0, CELL)
		btn.LayoutOrder = order
		btn.Text = ""
		btn.ZIndex = parent.ZIndex
		btn.Parent = parent
		local strokeInst = styleCard(btn, UITheme.Color.Locked, UDim.new(0, 14), 4)

		local reward = GameConfig.GetSeasonReward(level)[track]
		local faceEmoji, faceAmount, faceHue = rewardFace(reward)

		-- ===== BIGGER ICONS, ASKED FOR IN AS MANY WORDS ("vece ikone") =====
		--
		-- 36 px of slot at 30 pt of glyph inside a 92 px cell: the reward -- the only thing on the
		-- cell anybody scrolls the board to see -- was smaller than the padlock under it, and the
		-- three bands (icon 5..41, amount 40..60, status 65..89) already overlapped by a pixel. The
		-- band is re-cut so the icon takes the slack: **icon 2..44, amount 44..64, status 66..90**,
		-- glyph 30 -> 36 pt in a 36 -> 42 px slot, and no two bands touch. Same move 18.3 made on the
		-- Daily tiles ("vece ikone"), where the glyph went 56 -> 84 px.
		UITheme.IconSlot(btn, {
			name = "Icon", icon = faceEmoji, maxTextSize = 36,
			size = UDim2.new(1, -8, 0, 42), position = UDim2.new(0, 4, 0, 2),
		})

		local amount = Instance.new("TextLabel")
		amount.Size = UDim2.new(1, -8, 0, 20)
		amount.Position = UDim2.new(0, 4, 0, 44)
		amount.BackgroundTransparency = 1
		amount.Text = faceAmount
		amount.Parent = btn
		themeLabel(amount, 17)

		local status = Instance.new("TextLabel")
		status.Size = UDim2.new(1, -8, 0, 24)
		status.Position = UDim2.new(0, 4, 1, -26)
		status.BackgroundTransparency = 1
		status.Text = "\u{1F512}"
		status.Parent = btn
		themeLabel(status, 16)

		btn.MouseButton1Click:Connect(function()
			if claimRewardRemote then
				claimRewardRemote:FireServer(level, track)
			end
		end)

		-- `amount` and `hue` ride along so `refresh` can repaint the cell in the reward's own colour
		-- and re-ink both captions against whatever fill it just chose.
		return { btn = btn, status = status, amount = amount, hue = faceHue, strokeInst = strokeInst }
	end

	for level = 1, SEASON.maxLevel do
		local row = GameConfig.GetSeasonReward(level)

		local column = Instance.new("Frame")
		column.Name = "Level" .. level
		-- Derived (COL_H, top of this block) instead of the old hand-summed 36. It was CELL*2 + rail
		-- + the list layout's two 5 px gaps and it had to be re-added by hand every time the rail
		-- moved; the tray's two rotated row tags are computed off the same expression.
		column.Size = UDim2.new(0, CELL, 0, COL_H)
		column.LayoutOrder = level
		column.BackgroundTransparency = 1
		column.ZIndex = trackScroll.ZIndex + UITheme.Z.Content
		column.Parent = trackScroll

		local columnLayout = Instance.new("UIListLayout")
		columnLayout.SortOrder = Enum.SortOrder.LayoutOrder
		columnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		columnLayout.Padding = UDim.new(0, COL_GAP)
		columnLayout.Parent = column

		local freeRefs = buildCell(column, level, "free", 1)

		-- ===== ONE RAIL THROUGH THE BOARD, NOT THIRTY LOOSE NUMBER CHIPS (15.28) =====
		--
		-- The strip between the two tracks used to be thirty separate pills, each saying only the
		-- number it was already sitting under. It is one continuous bar instead, running BETWEEN the
		-- free and premium rows -- the one line on the page that belongs to both of them.
		--
		-- It is still built PER COLUMN: the columns are placed by a UIListLayout, and a one-piece rail
		-- parented to the scrolling frame would be laid out as a thirty-first column. The segment is
		-- CELL + the layout's 12px padding wide and the column's vertical layout centres it, so each
		-- segment overhangs 6px either side and the seams close into one unbroken bar.
		--
		-- ===== AND IT IS NO LONGER A SECOND PROGRESS BAR (18.6) =====
		--
		-- Her words, on a capture of this exact panel: *"ovde imaju 2 progres bara sta ce mi"*. She is
		-- right and they were the SAME number twice -- the 186x30 `SeasonXP` bar in the level card and
		-- this rail, whose fill was `clamp(pos - lvl + 0.5, 0, 1)` per segment, i.e. the same
		-- `level + into/need` drawn a second time and 666 px wide. The XP bar stays, because it is the
		-- headline number and it is the only one of the two that carries the text ("1170 / 1500 XP").
		--
		-- The rail becomes what it looks like: **track**. Each segment is filled or it is not -- a
		-- binary on the level being reached, no partial fill anywhere on the board -- so the eye reads
		-- it as the line joining thirty stations rather than as a bar creeping along. The node discs
		-- already carry per-level state (reached / next / locked) at three colours, so nothing is lost
		-- by taking the analogue reading off the line under them.
		--
		-- Thinner with it: **26 -> 16 px**. A 26 px bar with a 34 px disc sitting on it is a bar with
		-- a bump; a 16 px line under the same disc is a rail with a station on it, which is the whole
		-- difference between "progress" and "track". The 10 px it gives back go to the column, the
		-- tray's two row tags and the free/premium band split -- all derived from RAIL_H at the top of
		-- this block, so none of them had to be re-measured by hand.
		local rail = Instance.new("Frame")
		rail.Name = "Rail"
		rail.Size = UDim2.new(0, CELL + 12, 0, RAIL_H)
		rail.LayoutOrder = 2
		-- The empty half of the track. It was `shade(Locked, -0.35)` = rgb(106,105,117), luminance
		-- 0.42 -- a near-black strip drawn thirty times across a panel whose complaint is that it is
		-- grey. On the light tray it is `Cloud` shaded a touch (rgb(191,196,210), lum 0.76): still
		-- plainly a groove, no longer the second darkest thing on the screen.
		rail.BackgroundColor3 = shade(UITheme.Color.Cloud, -0.14)
		rail.BorderSizePixel = 0
		rail.ZIndex = column.ZIndex
		rail.Parent = column

		-- No UICorner and no UIStroke on either piece, on purpose: rounded ends or an outline on every
		-- segment would draw thirty pill shapes again, which is the thing this replaced.
		local railFill = Instance.new("Frame")
		railFill.Name = "Fill"
		railFill.Size = UDim2.new(0, 0, 1, 0)
		railFill.BackgroundColor3 = UITheme.Color.Green
		railFill.BorderSizePixel = 0
		railFill.ZIndex = rail.ZIndex + 1
		railFill.Parent = rail
		gradient(railFill, ColorSequence.new(UITheme.Color.Mint, UITheme.Color.Green), 90)

		-- The level number rides the rail as a node, so the bar passes THROUGH each milestone rather
		-- than running alongside it. Milestone nodes are simply bigger -- the colour is state (see
		-- refresh) and cannot also be used to mean "this one matters".
		local node = Instance.new("Frame")
		node.Name = "Node"
		node.Size = UDim2.new(0, row.milestone and 40 or 34, 0, row.milestone and 40 or 34)
		node.Position = UDim2.new(0.5, 0, 0.5, 0)
		node.AnchorPoint = Vector2.new(0.5, 0.5)
		node.ZIndex = rail.ZIndex + 2
		node.Parent = rail
		local nodeStroke = styleCard(node, UITheme.Color.Locked, UDim.new(1, 0), 3)

		local nodeLabel = Instance.new("TextLabel")
		nodeLabel.Name = "NodeLabel"
		nodeLabel.Size = UDim2.new(1, -8, 1, -8)
		nodeLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
		nodeLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		nodeLabel.BackgroundTransparency = 1
		nodeLabel.Text = tostring(level)
		nodeLabel.ZIndex = node.ZIndex + UITheme.Z.Content
		nodeLabel.Parent = node
		themeLabel(nodeLabel, row.milestone and 21 or 18)

		local premiumRefs = buildCell(column, level, "premium", 3)

		cells[level] = {
			free = freeRefs, premium = premiumRefs,
			railFill = railFill, node = node, nodeStroke = nodeStroke,
			milestone = row.milestone == true,
		}
	end

	-- ================= QUEST PAGE =================

	local questScroll = Instance.new("ScrollingFrame")
	questScroll.Name = "QuestScroll"
	questScroll.Size = UDim2.new(1, 0, 1, 0)
	questScroll.BackgroundTransparency = 1
	questScroll.BorderSizePixel = 0
	questScroll.ScrollBarThickness = 8
	questScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	questScroll.ZIndex = questPage.ZIndex
	questScroll.Parent = questPage

	local questLayout = Instance.new("UIListLayout")
	questLayout.SortOrder = Enum.SortOrder.LayoutOrder
	questLayout.Padding = UDim.new(0, 7)
	questLayout.Parent = questScroll

	local questRows = {}   -- [period .. "|" .. key] = refs
	local periodHeaders = {} -- [period] = label, for the countdown
	-- [period] = the LayoutOrder of that period's header. The rows below it are re-ordered on every
	-- refresh (claimable first -- see the sort in `refresh`), so their order is a function of state
	-- rather than of the order they were built in, and it has to be measured from something fixed.
	local periodBase = {}
	local questOrder = 0

	for _, period in ipairs({ "daily", "weekly" }) do
		local periodDef = GameConfig.QuestPeriods[period]

		questOrder += 1
		periodBase[period] = questOrder
		local header = Instance.new("Frame")
		header.Name = period .. "Header"
		header.Size = UDim2.new(1, -10, 0, 40)
		header.LayoutOrder = questOrder
		header.ZIndex = questScroll.ZIndex + UITheme.Z.Content
		header.Parent = questScroll
		styleCard(header, period == "daily" and UITheme.Color.Aqua or UITheme.Color.Peach, UDim.new(0, 12), 3)

		local headerLabel = Instance.new("TextLabel")
		headerLabel.Size = UDim2.new(1, -20, 1, -6)
		headerLabel.Position = UDim2.new(0, 12, 0, 2)
		headerLabel.BackgroundTransparency = 1
		headerLabel.TextXAlignment = Enum.TextXAlignment.Left
		headerLabel.Text = periodDef.emoji .. " " .. periodDef.label
		headerLabel.Parent = header
		themeLabel(headerLabel, 22)
		periodHeaders[period] = headerLabel

		for _, quest in ipairs(GameConfig.GetQuests(period)) do
			questOrder += 1
			local row = Instance.new("Frame")
			row.Name = quest.key
			row.Size = UDim2.new(1, -10, 0, 74)
			row.LayoutOrder = questOrder
			row.ZIndex = questScroll.ZIndex + UITheme.Z.Content
			row.Parent = questScroll
			local rowStroke = styleCard(row, PET_ROW_SHELL, UDim.new(0, 14), 4)

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(0, 330, 0, 28)
			nameLabel.Position = UDim2.new(0, 16, 0, 8)
			nameLabel.BackgroundTransparency = 1
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.Text = quest.emoji .. " " .. quest.name
			nameLabel.Parent = row
			themeLabel(nameLabel, 23)

			local barBg, barFill, barLabel = UITheme.ProgressBar(row, {
				name = "Progress",
				size = UDim2.new(0, 330, 0, 26),
				position = UDim2.new(0, 16, 1, -34),
				color = UITheme.Color.Green,
				text = "0 / " .. quest.target,
				maxTextSize = 17,
				zIndex = row.ZIndex + UITheme.Z.Content,
			})

			-- ===== WHAT THE CLAIM BUTTON ACTUALLY PAYS, WHICH IS NOT THE SEASON XP =====
			--
			-- This row used to read "+1200 Season XP" beside a Claim button, and that is the whole
			-- "the Season Pass bar does not go up when I claim" report -- the bar is right and the
			-- label was wrong. `SeasonPassService.Track` pays the XP **pro rata as the quest
			-- advances** (deliberately: it used to arrive in one lump at the button, so the level bar
			-- was frozen for the entire time the player was doing the work). By the time a quest is
			-- claimable the player has already been paid every point of its XP, so the claim adds
			-- nothing to the bar and cannot be made to without paying twice.
			--
			-- So the label says where each half really comes from: the XP is earned as you go, and
			-- the button hands over the diamonds. A quest with no diamonds says so plainly rather
			-- than promising a number that has already landed.
			local payLabel = Instance.new("TextLabel")
			payLabel.Size = UDim2.new(0, 220, 1, -16)
			payLabel.Position = UDim2.new(0, 360, 0, 8)
			payLabel.BackgroundTransparency = 1
			payLabel.TextXAlignment = Enum.TextXAlignment.Left
			payLabel.TextWrapped = true
			payLabel.Text = quest.diamonds
				and ("Claim: +%d \u{1F48E}\n%d Season XP as you go"):format(quest.diamonds, quest.xp)
				or ("%d Season XP as you go"):format(quest.xp)
			payLabel.Parent = row
			-- `Cream` (rgb 255,248,235, lum 0.97) on a row shell at lum 0.885 is a near-white word on
			-- a near-white card, held up entirely by its 4 px near-black halo -- legible, and drawn as
			-- an outline rather than as text. `InkSoft` is the kit's own token for "secondary text on
			-- a light surface" and, being dark ink, drops the halo by the same rule.
			themeLabel(payLabel, 18, UITheme.Color.InkSoft)

			local claimBtn = Instance.new("TextButton")
			claimBtn.Name = "ClaimButton"
			claimBtn.Size = UDim2.new(0, 120, 0, 46)
			claimBtn.Position = UDim2.new(1, -14, 0.5, -23)
			claimBtn.AnchorPoint = Vector2.new(1, 0)
			claimBtn.Text = "Claim"
			claimBtn.Parent = row
			styleButton(claimBtn, UITheme.Color.Locked, UDim.new(1, 0))
			claimBtn.MouseButton1Click:Connect(function()
				if claimQuestRemote then
					claimQuestRemote:FireServer(period, quest.key)
				end
			end)

			questRows[period .. "|" .. quest.key] = {
				quest = quest, period = period, rowStroke = rowStroke,
				barFill = barFill, barLabel = barLabel, claimBtn = claimBtn,
				-- `row` so refresh can re-order it; `bornOrder` so rows inside one band keep the
				-- order they were authored in instead of coming out of `pairs` differently each time
				row = row, bornOrder = questOrder,
			}
		end
	end

	questScroll.CanvasSize = UDim2.new(0, 0, 0, questOrder * 78 + 30)

	-- Forward-declared because the HUD tile is built at the BOTTOM of this block (it wants the
	-- panel and `refresh` to exist first) while `refresh` is what owns the badge. A closure that
	-- referenced a local declared later would compile to a global read and silently do nothing.
	local tileBadge, tileBadgeLabel
	local lastClaimable = 0

	-- ================= REFRESH =================

	local function refresh()
		if not hud.getData() then return end
		-- the season can turn over mid-session (7.3), so the header is re-read rather than assumed
		do
			-- NO LEADING EMOJI HERE ANY MORE (17.x). The title is PanelHeader's now, and PanelHeader
			-- runs IconifyLabel on it -- the leading glyph is stripped and drawn as a `TitleIcon`
			-- picture beside the words. This line re-added the glyph on the very first refresh, so
			-- the band rendered a drawn ticket AND the ticket emoji next to it. Photographed; it is
			-- the exact trap the Pets panel's refresh already carries a warning about.
			--
			-- The drawn icon is fixed at build time, which is very slightly wrong only for a session
			-- that spans a season turnover: the NAME updates and the picture would not. Accepted
			-- rather than solved, because UITheme.SetIcon looks for a child called `Icon`/`Label` and
			-- the band's is `TitleIcon`, so pointing it here would need a kit change for a case that
			-- lasts until the next rejoin.
			title.Text = GameConfig.GetCurrentSeason().name
		end
		local season = hud.getData().Season or {}
		local xp = season.xp or 0
		local level = GameConfig.GetSeasonLevel(xp)
		local into, need = GameConfig.GetSeasonLevelProgress(xp)
		local hasPremium = season.premium == true
		-- string keys: a table keyed by scattered integers does not survive the RemoteEvent that
		-- brought this data over -- see SeasonPassService
		local claimedFree = season.claimedFree or {}
		local claimedPremium = season.claimedPremium or {}
		-- Counted by the two loops below rather than by a second pass that re-derives the same
		-- question: each of them already has an exact "this one is pressable" branch, and a
		-- separate counter written against the same rules is the thing that drifts from them.
		local claimable = 0
		-- counted in the same pass, for the same reason: the header chip and the board must agree
		local collected = 0

		levelLabel.Text = tostring(level)
		xpReadout.Text = (level >= SEASON.maxLevel)
			and "MAX LEVEL"
			or ("%d / %d XP"):format(into, need)

		if hasPremium then
			premiumStatus.Text = "\u{2705} Premium unlocked \u{2014} both rows are yours."
			premiumButton.Visible = false
		else
			premiumStatus.Text = "Premium unlocks the bottom row, including every level you have already passed."
			premiumButton.Visible = true
		end

		-- There used to be a `pos = level + into/need` here -- the season expressed as one continuous
		-- number, 9.47 -- and the rail's per-segment partial fill was its only reader. That reading is
		-- the SeasonXP bar's job and always was (18.6), so the fractional position is gone with it
		-- rather than left behind as a value nothing draws.
		for lvl = 1, SEASON.maxLevel do
			local refs = cells[lvl]
			local slot = tostring(lvl)
			local reached = (lvl <= level)

			for _, track in ipairs({ "free", "premium" }) do
				local cellRefs = refs[track]
				local claimed = (track == "premium" and claimedPremium or claimedFree)[slot] == true
				local owned = (track == "free") or hasPremium

				-- ===== 88 SURFACES ON THIS PANEL WERE PAINTED `Color.Locked` (18.6) =====
				--
				-- Four states went through one swatch: claimed, claimable-behind-the-pass, not yet
				-- reached, and (on the nodes) not yet reached again. Three of those are refusals and
				-- grey is right for them. The fourth is a **receipt** -- a reward the player earned and
				-- collected -- and painting it in the refusal colour is the whole of "izgleda kao da
				-- dobijam rewards sto radim u mrtvacnici". Three states, three axes, exactly as 18.3
				-- did it on the Daily board: full chroma to claim, `DoneShade` of the reward's OWN hue
				-- when it is collected, no hue at all when it genuinely cannot be had.
				local fill
				if claimed then
					collected += 1
					cellRefs.status.Text = "\u{2705} Claimed"
					-- same hue, a third of the chroma, lifted to luminance 0.90 so the ink can never
					-- flip: Sunny rgb(255,212,75) -> rgb(250,240,213), Aqua rgb(105,205,250) ->
					-- rgb(216,240,250), Bubblegum -> rgb(250,222,240), Lavender -> rgb(235,226,251).
					-- Four pale pastels against the one flat rgb(163,161,180) they all used to be.
					fill = UITheme.DoneShade(cellRefs.hue)
					cellRefs.strokeInst.Color = OUTLINE_COLOR
					cellRefs.strokeInst.Thickness = 4
				elseif reached and owned then
					-- the one "press me" state on the board, same bright rim as everywhere else
					claimable += 1
					cellRefs.status.Text = "CLAIM!"
					fill = UITheme.Color.Green
					cellRefs.strokeInst.Color = READY_RIM
					cellRefs.strokeInst.Thickness = 5
				elseif reached and not owned then
					-- earned but behind the pass: gold rim, so it reads as "buy this" and not "grind
					-- more". This one KEEPS the locked fill -- the reward genuinely cannot be had --
					-- and it is the gold rim, not the fill, that does the selling.
					cellRefs.status.Text = "\u{1F512} Premium"
					fill = UITheme.Color.Locked
					cellRefs.strokeInst.Color = UITheme.Color.Gold
					cellRefs.strokeInst.Thickness = 4
				else
					cellRefs.status.Text = "\u{1F512} Lv." .. lvl
					fill = UITheme.Color.Locked
					cellRefs.strokeInst.Color = OUTLINE_COLOR
					cellRefs.strokeInst.Thickness = 4
				end
				setButtonColor(cellRefs.btn, fill)
				inkOnCell(cellRefs.status, fill)
				inkOnCell(cellRefs.amount, fill)
			end

			-- THE RAIL IS A CONNECTOR, NOT A BAR (18.6). It was
			-- `clamp(pos - lvl + 0.5, 0, 1)` -- a partial fill sliding through the segment the player
			-- is standing in, which is the second progress bar she photographed. Binary now: a segment
			-- behind a level already reached is full, everything ahead of it is empty, and there is no
			-- moving edge anywhere on the board. `pos` is still computed above because the node loop
			-- moving edge anywhere on the board.
			refs.railFill.Size = UDim2.new(reached and 1 or 0, 0, 1, 0)

			-- and the node lights as the level lands. The one level AHEAD wears the ready rim, so the
			-- board always points at the next thing rather than only marking the last -- the same
			-- signal the Daily board and the Mastery list use for "this is the live one".
			if reached then
				setButtonColor(refs.node, refs.milestone and UITheme.Color.Gold or UITheme.Color.Green)
				refs.nodeStroke.Color = OUTLINE_COLOR
				refs.nodeStroke.Thickness = 3
			elseif lvl == level + 1 then
				setButtonColor(refs.node, UITheme.Color.Sunny)
				refs.nodeStroke.Color = READY_RIM
				refs.nodeStroke.Thickness = 4
			else
				setButtonColor(refs.node, UITheme.Color.Locked)
				refs.nodeStroke.Color = OUTLINE_COLOR
				refs.nodeStroke.Thickness = 3
			end
		end

		-- the header chip. Gold and a trophy when the whole pass is in the bag, because "60 / 60" is
		-- the proudest line this panel can print and 18.4 already settled that a finished ladder gets
		-- to say so rather than going quiet.
		local total = SEASON.maxLevel * 2
		if collected >= total then
			tally.Text = ("\u{1F3C6} ALL %d COLLECTED!"):format(total)
			setButtonColor(tally, UITheme.Color.Gold)
		else
			tally.Text = ("\u{1F381} %d / %d collected"):format(collected, total)
			setButtonColor(tally, UITheme.Color.Aqua)
		end

		local held = hud.getData().Quests or {}
		-- ===== A CLAIMABLE QUEST GOES TO THE TOP OF ITS OWN CATEGORY =====
		--
		-- Collected here so the sort below has every row's state before any of them are placed. Rows
		-- keep their authored order inside each band, so nothing shuffles under the cursor while the
		-- player is reaching for a button -- only crossing a band moves a row, and that only happens
		-- on a completion or a claim, which the player just caused.
		local banded = { daily = {}, weekly = {} }
		for _, refs in pairs(questRows) do
			local quest = refs.quest
			local periodData = held[refs.period] or {}
			-- A period the server has not reset yet still carries the PREVIOUS period's numbers, so
			-- the stamp is checked here too rather than trusted -- otherwise a player who leaves the
			-- panel open across midnight watches yesterday's finished board.
			local stale = periodData.periodId ~= GameConfig.GetQuestPeriodId(refs.period)
			local done = stale and 0 or ((periodData.progress or {})[quest.key] or 0)
			local claimed = (not stale) and ((periodData.claimed or {})[quest.key] == true)

			refs.barFill.Size = UDim2.new(math.clamp(done / quest.target, 0, 1), 0, 1, 0)
			refs.barLabel.Text = ("%d / %d"):format(math.min(done, quest.target), quest.target)

			-- band 1 claimable, 2 still running, 3 finished with. A claimed quest sinks to the
			-- bottom rather than staying where it was: it is the one row on the board with nothing
			-- left to do, and it is exactly what the player has just stopped caring about.
			local band
			if claimed then
				band = 3
				refs.claimBtn.Text = "\u{2705} Done"
				-- A finished quest is a receipt, not a refused control (18.6). It was the SAME
				-- rgb(163,161,180) as the "🔒 2 left" button two rows down -- one swatch for "you did
				-- it" and "you did not". `DoneShade(Green)` is rgb(219,247,232) at luminance 0.90:
				-- unmistakably the green family, unmistakably spent, and light enough that the caption
				-- has to flip to dark ink -- which is what `inkOnCell` is doing on all three branches.
				setButtonColor(refs.claimBtn, UITheme.DoneShade(UITheme.Color.Green))
				inkOnCell(refs.claimBtn, UITheme.DoneShade(UITheme.Color.Green))
				refs.rowStroke.Color = OUTLINE_COLOR
				refs.rowStroke.Thickness = 4
			elseif done >= quest.target then
				band = 1
				claimable += 1
				refs.claimBtn.Text = "CLAIM!"
				setButtonColor(refs.claimBtn, UITheme.Color.Green)
				inkOnCell(refs.claimBtn, UITheme.Color.Green)
				refs.rowStroke.Color = READY_RIM
				refs.rowStroke.Thickness = 5
			else
				band = 2
				-- ===== AN UNFINISHED QUEST DOES NOT OFFER A CLAIM BUTTON =====
				--
				-- This said "Claim" in the Locked colour, which is the SAME grey the finished
				-- "Done" state uses -- so a quest at 0/3 and a quest already claimed looked
				-- identical, and the only one of the three states that was actually pressable
				-- (CLAIM!) was the odd one out. Players pressed the grey one, the server answered
				-- "That quest isn't finished yet!", and it read as "the claim buttons do not work".
				-- It is the exact thing in the 2026-08-11 screenshot: 0/3 offering Claim while
				-- 50/50 shows Done.
				--
				-- The button now states the requirement instead of inviting a press. The bar under
				-- it already shows progress, so the button says what is missing, not where you are.
				refs.claimBtn.Text = ("\u{1F512} %d left"):format(math.max(quest.target - done, 0))
				setButtonColor(refs.claimBtn, UITheme.Color.Locked)
				inkOnCell(refs.claimBtn, UITheme.Color.Locked)
				refs.rowStroke.Color = OUTLINE_COLOR
				refs.rowStroke.Thickness = 4
			end
			local bucket = banded[refs.period]
			if bucket then
				table.insert(bucket, { refs = refs, band = band, born = refs.bornOrder })
			end
		end

		-- ...and place them. LayoutOrder is measured from each period's own header, so the two
		-- categories can never interleave however their rows are re-ordered inside themselves.
		for period, rows in pairs(banded) do
			table.sort(rows, function(a, b)
				if a.band ~= b.band then return a.band < b.band end
				return a.born < b.born
			end)
			local base = periodBase[period] or 0
			for i, entry in ipairs(rows) do
				entry.refs.row.LayoutOrder = base + i
			end
		end

		-- ===== THE TILE HAS TO SAY THERE IS SOMETHING TO PRESS =====
		--
		-- Every other route into this panel was the player deciding to look. The Daily tile has
		-- carried a claimable-today flag since it was built; the Season tile was authored without
		-- one, so a finished quest and an unclaimed level sat behind a tile that looked exactly
		-- like a tile with nothing in it.
		--
		-- IT IS A COUNT, NOT A DOT. "3" is a reason to open the panel; a bare mark is a decoration
		-- the eye learns to skip after the second session -- which is also why it goes dark the
		-- moment the last thing is claimed rather than staying lit as an advert for the feature.
		lastClaimable = claimable
		if tileBadge then
			tileBadge.Visible = claimable > 0
			if tileBadgeLabel then
				tileBadgeLabel.Text = (claimable > 9) and "9+" or tostring(claimable)
			end
		end
	end

	-- the countdown to the next reset, ticking only while somebody is looking at it
	local function updateTimers()
		for period, label in pairs(periodHeaders) do
			local def = GameConfig.QuestPeriods[period]
			local remaining = math.max(0, GameConfig.GetQuestPeriodEnd(period) - os.time())
			label.Text = ("%s %s  \u{2022}  resets in %dh %02dm")
				:format(def.emoji, def.label, remaining // 3600, (remaining % 3600) // 60)
		end
	end

	task.spawn(function()
		while true do
			task.wait(1)
			if panel.Visible then
				updateTimers()
			end
		end
	end)

	-- ---- HUD tile, bottom of the right column (see RIGHT_COUNT)
	-- The badge is authored WITH the tile and hidden immediately, because UITheme.Badge is only
	-- reachable through the IconTile options table -- there is no "add a badge later" call. Hidden
	-- rather than left showing its placeholder: the first DataUpdate is a few hundred milliseconds
	-- out, and a red "1" that flashes on every join and is usually wrong is worse than no badge.
	local tile = columnTile("R", 5, SEASON.emoji, "Season", UITheme.Color.Sunny, "1", UITheme.Color.Coral)
	tileBadge = tile:FindFirstChild("Badge")
	tileBadgeLabel = tileBadge and tileBadge:FindFirstChild("Label")
	if tileBadge then tileBadge.Visible = false end
	tile.MouseButton1Click:Connect(function()
		toggleOnly(panel)
		setTab(currentTab)
		updateTimers()
		refresh()
	end)

	setTab("track")
	updateTimers()

	hud.refreshSeasonPanel = refresh
	-- read by the welcome-back card, which has to know whether this feature has anything waiting
	-- before it offers a row pointing at it. It is the number `refresh` last drew on the badge, so
	-- the card and the tile can never disagree about what is claimable.
	hud.seasonClaimCount = function() return lastClaimable end
	hud.showSeasonPanel = function()
		toggleOnly(panel)
		setTab(currentTab)
		updateTimers()
		refresh()
	end
end
