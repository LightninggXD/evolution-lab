-- PotionTimers -- the bottom-left stack of active potion timers -- how long each boost has left.
--
-- MOVED OUT OF `MainUI` (18.9), byte for byte. It was already a closed
-- `;(function() ... end)()` block -- the shape this file's 200-register ceiling forces
-- every panel into -- so the extraction is a change of wrapper, not of code. See
-- `docs/SPLIT.md` for the `hud` contract and `docs/CODEMAP.md` for where the rest went.

local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))

local stroke, corner, themeLabel, styleCard = UIKit.stroke, UIKit.corner, UIKit.themeLabel, UIKit.styleCard

return function(hud)
	local screenGui = hud.screenGui

	local stack = Instance.new("Frame")
	stack.Name = "PotionTimers"
	-- BOTH OF THESE ARE RECOMPUTED EVERY TICK NOW (10.17); these are only the first-frame values.
	-- The height was a fixed 250 that up to 297 px of content overflowed upward into the left tile
	-- column, and the x was that column's own 20 -- see the fit pass at the bottom of the refresh
	-- loop for both. The layout aligns to the BOTTOM of this frame, which is what makes a height
	-- change headroom rather than movement: the strip stays 170 px off the bottom (clearing the
	-- currency stack, 140 tall and 22 up) whether it is holding one boost or twelve.
	stack.Size = UDim2.new(0, 224, 0, 196)
	stack.Position = UDim2.new(0, 20, 1, -170)
	stack.AnchorPoint = Vector2.new(0, 1)
	stack.BackgroundTransparency = 1
	stack.Visible = false
	stack.ZIndex = UITheme.Z.Content
	stack.Parent = screenGui

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Padding = UDim.new(0, 6)
	layout.Parent = stack

	-- ===== DRIVEN BY GameConfig, NOT BY A LIST TYPED HERE (11.8) =====
	--
	-- This was `{ "dna", "xp", "luck" }`, and the fourth kind landed in the config, in the shop, in
	-- the inventory panel and in the save -- and had no timer on the HUD, because this one list did
	-- not know about it. A boost with no countdown is a boost the player cannot tell is running or
	-- about to end. The potion tables were deliberately built as kind x size for exactly this class
	-- of mistake; the strip is now built the same way, so a fifth kind gets a card by existing.
	local KINDS = {}
	for _, k in ipairs(GameConfig.PotionKinds) do table.insert(KINDS, k.key) end
	-- ...and the word on the card comes from the same table, so "health" cannot print lowercase
	-- while "DNA" prints in caps. `LABEL[kind] or kind` was the fallback and it was already the
	-- wrong answer the moment a kind existed that nobody had typed a label for.
	local LABEL = {}
	for _, k in ipairs(GameConfig.PotionKinds) do LABEL[k.key] = k.name end
	local rows = {}

	for order, kind in ipairs(KINDS) do
		-- colour and emoji are properties of the KIND, so any bottle of that kind carries the
		-- right ones -- no separate table to keep in step with GameConfig.Potions
		local sample
		for _, p in ipairs(GameConfig.Potions) do
			if p.kind == kind then
				sample = p
				break
			end
		end

		-- 216 x 38 AND A CAPSULE, NOT 244 x 48 AND A BOX (16.1). Every row on this strip is now the
		-- same 38 px single line: an icon disc, one short phrase, a clock, and -- only here, because
		-- only a potion is running out -- a 5 px bar along the bottom. `UDim.new(1, 0)` is a real
		-- radius for `styleCard`, not a hack: it has a documented pill path that drops the gloss to
		-- 0.40 height. The disc is 28 px on a 38 px row, so it shares the capsule's own left centre
		-- (19, 19) and cannot clip against the rounding.
		local card = Instance.new("Frame")
		card.Name = kind .. "Timer"
		card.Size = UDim2.new(0, 216, 0, 38)
		card.LayoutOrder = order
		card.BackgroundColor3 = Color3.fromRGB(30, 34, 48)
		card.Visible = false
		card.ZIndex = UITheme.Z.Content + 1
		card.Parent = stack
		styleCard(card, sample.color, UDim.new(1, 0), 3)

		local bottle = Instance.new("TextLabel")
		bottle.Name = "Bottle"
		bottle.Size = UDim2.new(0, 28, 0, 28)
		bottle.Position = UDim2.new(0, 5, 0, 5)
		bottle.BackgroundColor3 = sample.color
		bottle.Text = sample.emoji
		bottle.ZIndex = card.ZIndex + 1
		bottle.Parent = card
		corner(bottle, UDim.new(0.5, 0))
		themeLabel(bottle, 16)

		local effect = Instance.new("TextLabel")
		effect.Name = "Effect"
		effect.Size = UDim2.new(1, -110, 0, 17)
		effect.Position = UDim2.new(0, 40, 0, 4)
		effect.BackgroundTransparency = 1
		effect.TextXAlignment = Enum.TextXAlignment.Left
		effect.ZIndex = card.ZIndex + 1
		effect.Parent = card
		themeLabel(effect, 14)

		local clock = Instance.new("TextLabel")
		clock.Name = "Clock"
		clock.Size = UDim2.new(0, 58, 0, 17)
		clock.Position = UDim2.new(1, -64, 0, 4)
		clock.BackgroundTransparency = 1
		clock.TextXAlignment = Enum.TextXAlignment.Right
		clock.ZIndex = card.ZIndex + 1
		clock.Parent = card
		themeLabel(clock, 14)

		local track = Instance.new("Frame")
		track.Name = "Track"
		track.Size = UDim2.new(1, -52, 0, 5)
		track.Position = UDim2.new(0, 40, 1, -11)
		track.BackgroundColor3 = UITheme.Color.Cloud
		track.BorderSizePixel = 0
		track.ZIndex = card.ZIndex + 1
		track.Parent = card
		corner(track, UDim.new(0.5, 0))

		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.new(1, 0, 1, 0)
		fill.BackgroundColor3 = sample.color
		fill.BorderSizePixel = 0
		fill.ZIndex = track.ZIndex + 1
		fill.Parent = track
		corner(fill, UDim.new(0.5, 0))

		rows[kind] = { card = card, effect = effect, clock = clock, fill = fill }
	end

	-- ============================================================================
	-- THE PASS CHIP TRAY IS GONE FROM THE HUD (16.1)
	-- ============================================================================
	-- It was a gold card carrying up to nine 34 px emoji discs, wrapped two rows deep, parked
	-- permanently in the middle of the left edge. 6.4's own argument is what condemns it: a pass is
	-- PERMANENT, so the chip never changes, never counts down and never asks for anything. It was
	-- the single densest thing on the screen and the least actionable -- ten glyphs with no labels,
	-- competing for the eye with the two clocks that actually move. Worse, it is the row that made
	-- the strip TALL: 81 px of the 297 px that grew up the screen into the tile column.
	--
	-- Ownership is already answered properly, with names, art and prices, in the Robux panel's
	-- Passes tab -- one tap from the same screen. Nothing else in the file referenced `passCard`
	-- or `passChips`. If a permanent-boost readout is ever wanted back, it belongs inside a panel
	-- next to what it costs, not on the strip reserved for things that expire.

	-- ============================================================================
	-- THE EVENT HALF OF THE STRIP (7.1)
	-- ============================================================================
	-- A server-wide event is a boost that is running out, so by 6.4's own rule it is a CARD with a
	-- clock and not a chip. It sits above the pass chips because it is the only thing here that is
	-- true of everybody in the server at once, and it is the only one with a deadline.
	--
	-- WHY THIS EXISTS AT ALL when there is already a board in Forest: the board is read by a player
	-- who walks past it. Somebody who joins in the middle of a weekend, spawns, and goes straight to
	-- a zone would otherwise never learn that their DNA is doubled -- which is most of the value of
	-- running an event in the first place.
	--
	-- THE CLOCK COMES FROM THE SERVER, and this is the one place that matters on the client. Every
	-- window in GameConfig is measured against GameConfig.EventNow(), which is os.time() plus an
	-- offset -- and the offset is learned here, from the payload EventService publishes. A player
	-- whose machine is a day fast would otherwise be shown a weekend that is not running and a
	-- countdown to the wrong minute, and would then watch their DNA arrive at the ordinary rate.
	--
	-- Synced on `Changed` rather than on a poll of the value: the payload carries the moment it was
	-- WRITTEN, so reading it late means adopting a clock as stale as the read. Changed fires at the
	-- write, and the initial read below is corrected by the first refresh 30 seconds later.
	do
		local liveEvents = RS:FindFirstChild("LiveEvents")
		local HttpService = game:GetService("HttpService")
		local function adopt(value)
			if type(value) ~= "string" or value == "" then return end
			local ok, payload = pcall(function() return HttpService:JSONDecode(value) end)
			if ok and type(payload) == "table" and tonumber(payload.now) then
				GameConfig.SetEventClock(payload.now)
			end
		end
		if liveEvents then
			adopt(liveEvents.Value)
			liveEvents.Changed:Connect(adopt)
		else
			-- the server creates it in EventService.Init; a client that got here first waits rather
			-- than deciding for itself what time it is
			task.spawn(function()
				local sv = RS:WaitForChild("LiveEvents", 30)
				if sv then
					adopt(sv.Value)
					sv.Changed:Connect(adopt)
				end
			end)
		end
	end

	-- ============================================================================
	-- THE ARENA BOSS CLOCK (11.20)
	-- ============================================================================
	-- Same argument the event card above makes, and it applies harder here: the countdown already
	-- existed, on a board hanging over the arena entrance, where the only player who can read it is
	-- one who has already decided to go. A timer whose job is to MAKE somebody go has to be where
	-- they are.
	--
	-- It joins this strip rather than becoming a new HUD element, and that is the whole reason it is
	-- cheap: the strip is already a budgeted, bottom-aligned, drop-lowest-first stack (see 10.17
	-- below), so a fifth card inherits the phone-viewport behaviour, the tile-column clearance and
	-- the ordering without a line of new layout.
	--
	-- Fed by ReplicatedStorage attributes BossService republishes every second -- no remote, nothing
	-- to request, and a client that joins mid-interval reads the current value on its first tick.
	-- ONE LINE, NOT A CARD (16.1). The two-line card carried a subtitle -- "The Devourer returns",
	-- or the boss's health while it was alive -- under the clock. That is a sentence the player
	-- reads once and never needs again, printed permanently, and it is what forced 48 px. A boss
	-- clock only has to answer WHO and WHEN, so the name and the countdown share one 38 px capsule
	-- and the subtitle is gone. The health it used to show is on the boss's own bar the moment the
	-- fight starts, which is the only time it means anything.
	-- ========================================================================
	-- ...AND THEY ARE NOT ON THIS STRIP ANY MORE (16.2)
	-- ========================================================================
	-- The boss clock and the live-event clock came off the bottom-left strip and onto their own bar
	-- pinned to the very bottom edge of the screen, centred, at well under half the area they had.
	--
	-- WHY THEY DO NOT BELONG ON THE POTION STRIP: everything else on that strip is something the
	-- PLAYER is carrying -- a boost they drank, that is draining, that only they can see. These two
	-- are facts about the SERVER: the same words are on every screen in the game at the same moment.
	-- Mixing the two meant a boss timer nobody asked for could push a potion that is about to expire
	-- off the bottom of the budget, and it put a permanent red banner in the corner the player's eye
	-- goes to for their own numbers.
	--
	-- WHY THE BOTTOM EDGE: it is the only band of a Roblox screen that is genuinely idle -- the
	-- currencies are top-left, the tiles are down both sides, and the evolve card sits above this bar
	-- (moved up 14px to clear it). A world clock is ambient: findable without ever being in the way,
	-- and never the brightest thing on screen.
	--
	-- The bar auto-sizes on X around whichever pills are visible and stays centre-anchored, so one
	-- clock is centred and two are centred as a pair -- nothing slides sideways when an event starts.
	local eventBar = Instance.new("Frame")
	eventBar.Name = "WorldEventBar"
	-- 32, not 24 (17.x). The floor of this bar is not taste, it is the tile cluster: the responsive
	-- pass reserves BOTTOM_CLEAR = 46 for the right-hand column, so `clearance + height` has to stay
	-- at or under 46 or the bar slides under the tiles on a phone viewport. 12 + 32 = 44. The width
	-- stays 168 for the same reason in X: two chips plus their gap is 344, and on an 848-wide phone
	-- that leaves 16 px before the cluster starts. BOTTOM_CLEAR lives inside the responsive block
	-- at the bottom of this file and cannot be shared without a top-level register, so if it ever
	-- moves, THIS BAR HAS TO BE RE-CHECKED BY HAND -- the relationship is a comment, not code.
	eventBar.Size = UDim2.new(0, 0, 0, 32)
	eventBar.AutomaticSize = Enum.AutomaticSize.X
	eventBar.Position = UDim2.new(0.5, 0, 1, -12)
	eventBar.AnchorPoint = Vector2.new(0.5, 1)
	eventBar.BackgroundTransparency = 1
	eventBar.ZIndex = UITheme.Z.Content
	eventBar.Parent = screenGui

	local eventBarLayout = Instance.new("UIListLayout")
	eventBarLayout.FillDirection = Enum.FillDirection.Horizontal
	eventBarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	eventBarLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	eventBarLayout.SortOrder = Enum.SortOrder.LayoutOrder
	eventBarLayout.Padding = UDim.new(0, 8)
	eventBarLayout.Parent = eventBar

	local arenaCard = Instance.new("Frame")
	arenaCard.Name = "ArenaBoss"
	-- 168 x 24, down from 216 x 38. At this size the pill is a glance, not a card: an 18px emoji
	-- disc, the name at 12, the clock at 12, and nothing else fits -- which is the point.
	arenaCard.Size = UDim2.new(0, 168, 0, 32)
	arenaCard.LayoutOrder = 1                 -- boss first, event second, reading left to right
	arenaCard.BackgroundColor3 = Color3.fromRGB(30, 34, 48)
	arenaCard.Visible = false
	arenaCard.ZIndex = UITheme.Z.Content + 1
	arenaCard.Parent = eventBar
	styleCard(arenaCard, UITheme.Color.Red, UDim.new(1, 0), 3)

	local arenaBadge = Instance.new("TextLabel")
	arenaBadge.Name = "Badge"
	-- 18 on a 24px row, so the disc shares the capsule's own left centre (12, 12) and cannot clip
	-- against the rounding -- the same rule the 28-on-38 discs on the potion strip follow.
	arenaBadge.Size = UDim2.new(0, 22, 0, 22)
	arenaBadge.Position = UDim2.new(0, 5, 0, 5)
	arenaBadge.BackgroundColor3 = UITheme.Color.Red
	arenaBadge.Text = GameConfig.EventBoss.emoji
	arenaBadge.ZIndex = arenaCard.ZIndex + 1
	arenaBadge.Parent = arenaCard
	corner(arenaBadge, UDim.new(0.5, 0))
	themeLabel(arenaBadge, 14)

	-- Both labels are centred on the row (`0.5, -10` against a height of 20) rather than pinned to
	-- a top margin: on a single-line pill there is no second line to leave room for, and a
	-- top-pinned label on a 38 px capsule reads as if it has slipped.
	local arenaName = Instance.new("TextLabel")
	arenaName.Name = "ArenaName"
	-- -80 = 25 of left inset past the disc + 47 of clock and its right margin. Truncated rather than
	-- shrunk: themeLabel floors text at 14 and this label is authored at 12, so a long boss name has
	-- no shrink left to give and would wrap onto a second line the 24px pill has no room for.
	arenaName.Size = UDim2.new(1, -78, 0, 20)
	arenaName.Position = UDim2.new(0, 28, 0.5, -10)
	arenaName.BackgroundTransparency = 1
	arenaName.TextXAlignment = Enum.TextXAlignment.Left
	arenaName.TextTruncate = Enum.TextTruncate.AtEnd
	arenaName.ZIndex = arenaCard.ZIndex + 1
	arenaName.Parent = arenaCard
	-- 12, NOT the 14 the rest of this chip uses, and this is the binding constraint of the whole
	-- bar. Measured with GetTextBoundsAsync in FredokaOne: "Colosseum Clash" needs 100 px at 14,
	-- 97 at 13 and 87 at 12, and the widest band this 168 px card can give a name is 90. The
	-- original 12 px was not laziness -- it was tuned to exactly this string, and raising it to 14
	-- silently truncated the longest event in the game to "Colosseum...".
	--
	-- THE CAPTURE IS WHAT SETTLED IT. TextBounds read 76 x 14 in an 86 x 20 box -- fits by every
	-- number -- because TextBounds reports what was RENDERED, i.e. the already-truncated string,
	-- not what the text needed. TextFits was the only property telling the truth and it was the
	-- one that looked wrong. Measure the STRING, never the label, when asking if it will fit.
	themeLabel(arenaName, 12)
	-- AFTER themeLabel, NEVER BEFORE: `TextScaled = true` silently turns `TextWrapped` ON, so a
	-- "do not wrap" written above the helper that scales is reversed by it and reads correct in
	-- the source forever. Measured live: the band is 86 px and the string needs 76, so it fits on
	-- one line -- but wrapped, it broke into two lines that do not fit 20 px of height, and the
	-- engine reported TextFits = false while every other property looked right. These are one-line
	-- chips by construction; a second line is clipped by the card either way.
	arenaName.TextWrapped = false

	local arenaClock = Instance.new("TextLabel")
	arenaClock.Name = "Clock"
	arenaClock.Size = UDim2.new(0, 46, 0, 20)
	arenaClock.Position = UDim2.new(1, -50, 0.5, -10)
	arenaClock.BackgroundTransparency = 1
	arenaClock.TextXAlignment = Enum.TextXAlignment.Right
	arenaClock.ZIndex = arenaCard.ZIndex + 1
	arenaClock.Parent = arenaCard
	themeLabel(arenaClock, 14)
	arenaClock.TextWrapped = false

	-- ONE LINE, NOT A CARD (16.1). The effects line -- "x2 DNA   x2 Giant Loot   x2 XP" -- was the
	-- widest string anywhere on the HUD and it said the same three things for a whole weekend
	-- without moving. 12.13 above is the record of how much layout that one static line cost: two
	-- passes of pixel-fitting against a name that would not fit beside it. The name and the clock
	-- are the reason to look; what the event PAYS is on its own board in the world and in the
	-- Season panel, where a player deciding whether to go can actually act on it.
	--
	-- The "+1" for a second concurrent event goes with it: "Colosseum Clash  +1" is 118 px at this
	-- label's 14 px floor and the slot is 108. The headliner is drawn; the co-runner is not named.
	local eventCard = Instance.new("Frame")
	eventCard.Name = "EventBoost"
	eventCard.Size = UDim2.new(0, 168, 0, 32)
	eventCard.LayoutOrder = 2                 -- to the right of the arena pill (1)
	eventCard.BackgroundColor3 = Color3.fromRGB(30, 34, 48)
	eventCard.Visible = false
	eventCard.ZIndex = UITheme.Z.Content + 1
	eventCard.Parent = eventBar
	styleCard(eventCard, UITheme.Color.Coral, UDim.new(1, 0), 3)

	local eventBadge = Instance.new("TextLabel")
	eventBadge.Name = "Badge"
	eventBadge.Size = UDim2.new(0, 22, 0, 22)
	eventBadge.Position = UDim2.new(0, 5, 0, 5)
	eventBadge.BackgroundColor3 = UITheme.Color.Coral
	eventBadge.Text = "\u{1F525}"
	eventBadge.ZIndex = eventCard.ZIndex + 1
	eventBadge.Parent = eventCard
	corner(eventBadge, UDim.new(0.5, 0))
	themeLabel(eventBadge, 14)

	local eventName = Instance.new("TextLabel")
	eventName.Name = "EventName"
	eventName.Size = UDim2.new(1, -78, 0, 20)
	eventName.Position = UDim2.new(0, 28, 0.5, -10)
	eventName.BackgroundTransparency = 1
	eventName.TextXAlignment = Enum.TextXAlignment.Left
	eventName.TextTruncate = Enum.TextTruncate.AtEnd
	eventName.ZIndex = eventCard.ZIndex + 1
	eventName.Parent = eventCard
	themeLabel(eventName, 12)
	eventName.TextWrapped = false

	local eventClock = Instance.new("TextLabel")
	eventClock.Name = "Clock"
	eventClock.Size = UDim2.new(0, 46, 0, 20)
	eventClock.Position = UDim2.new(1, -50, 0.5, -10)
	eventClock.BackgroundTransparency = 1
	eventClock.TextXAlignment = Enum.TextXAlignment.Right
	eventClock.ZIndex = eventCard.ZIndex + 1
	eventClock.Parent = eventCard
	themeLabel(eventClock, 14)
	eventClock.TextWrapped = false

	-- ============================================================================
	-- THE MUTATION YOU ARE WEARING IS A DOT ON THE AURAS TILE (16.1)
	-- ============================================================================
	-- 15.24's argument below is kept because it is still right about the PROBLEM -- there was
	-- nowhere to see the worn aura -- and wrong only about the size of the answer. A card was the
	-- answer when the strip had room. It does not: counting the pass tray, four of the eight rows
	-- were facts that never change, and they pushed the two clocks that DO change up the screen
	-- behind them. A permanent one-of-seven fact earns a GLYPH, not a sentence.
	--
	-- So it becomes a coloured dot in the corner of the Auras TILE -- the button that opens the
	-- panel which already prints "wearing X" and the full "x1.80 DNA, +6 speed" line for every
	-- tier. The dot says "you have one, and it is this rarity"; one tap says the rest. It costs no
	-- screen space at all, and it puts the readout on the thing you would click anyway.
	--
	-- Parented to the tile rather than the strip, so the responsive pass that resizes the column
	-- carries it for free. `FindFirstChild`, not `WaitForChild`: the tiles are built ~500 lines
	-- above this block so it is already there, and yielding here would stall the rest of the HUD.
	-- If it were ever missing, `Parent = nil` leaves the dot alive but unrendered -- the refresh
	-- below stays valid and simply draws nothing.
	--
	-- ---- 15.24's original note, on why this readout has to exist at all: ----
	-- The report was *"I need somewhere to see which aura is equipped, or whatever this DNA machine
	-- gives"*, and it was exactly right: the Splicer sells a permanent income-and-speed multiplier
	-- that is WORN one at a time (`data.SplicerMutation`), and the only place in the entire game
	-- that named it was a line inside the Splicer's own roll panel -- i.e. you had to walk back to
	-- the machine to find out what you had bought from it. The particle aura on the body is the only
	-- other trace, and a particle does not say "x1.50".
	--
	-- IT BELONGS ON THIS STRIP AND NOWHERE ELSE. The strip is already the answer to "what is
	-- currently affecting me": potions that are running out, passes that are permanent, the live
	-- event, the arena clock. A worn mutation is the same class of fact as a pass -- permanent,
	-- bought, invisible without a readout -- so it is a card here rather than a new HUD element,
	-- and it inherits the budget, the fit pass and the tile-column clearance for free.
	--
	-- Dropped FIRST when the viewport is short (see the fit order below), beside the pass card and
	-- for the same reason: nothing about it is about to expire.
	local mutationDot = Instance.new("Frame")
	mutationDot.Name = "AuraDot"
	mutationDot.Size = UDim2.new(0, 22, 0, 22)
	mutationDot.Position = UDim2.new(1, -3, 0, 3)
	mutationDot.AnchorPoint = Vector2.new(1, 0)
	mutationDot.BackgroundColor3 = UITheme.Color.Purple
	mutationDot.Visible = false
	mutationDot.ZIndex = UITheme.Z.Badge
	mutationDot.Parent = screenGui:FindFirstChild("AurasButton")
	corner(mutationDot, UDim.new(0.5, 0))
	stroke(mutationDot, 2, UITheme.Color.Outline)

	-- x2 stays "x2"; x1.5 becomes "x1.5" rather than taking the thread down. See the note below.
	-- TWO decimals, not one (15.29). `%.1f` was written for the potion and event cards, whose
	-- multipliers are all x1.5 / x2 / x3 and exact at one decimal -- but a mutation is not: three of
	-- the seven are two-decimal, and Common 1.05 drew as `x1.1`, Epic 1.18 as `x1.2`, Godly 2.25 as
	-- `x2.2` (rounded DOWN, so the best aura in the game under-sold itself) anywhere this helper met
	-- one. Trailing zero trimmed, so `1.50 -> "1.5"` and nothing that was already correct changes.
	local function formatMult(m)
		m = tonumber(m) or 1
		if math.abs(m - math.floor(m + 0.5)) < 0.001 then
			return tostring(math.floor(m + 0.5))
		end
		local s = ("%.2f"):format(m)
		s = s:gsub("0$", "") -- 1.50 -> 1.5; 1.05 and 2.25 keep both digits
		return s
	end

	-- Its OWN loop, not a hook on DataUpdate: the number has to fall every second, and data only
	-- arrives when something in the game happens -- a player standing still would watch a frozen
	-- clock. Four times a second keeps the seconds honest without redrawing every frame.
	task.spawn(function()
		while true do
			local boosts = hud.getData() and hud.getData().PotionBoosts
			local now = os.time()
			local any = false
			for _, kind in ipairs(KINDS) do
				local row = rows[kind]
				local b = boosts and boosts[kind]
				local left = b and ((b.untilTs or 0) - now) or 0
				if left > 0 then
					any = true
					row.card.Visible = true
					row.clock.Text = ("%d:%02d"):format(math.floor(left / 60), left % 60)
					-- `totalSecs` is what the boost was worth when it was last topped up, which is
					-- not the bottle's own duration -- a second bottle adds to the remainder. Fall
					-- back to `left` so an old save written before that field existed draws a full
					-- bar rather than dividing by nil.
					local total = math.max(b.totalSecs or left, 1)
					row.fill.Size = UDim2.new(math.clamp(left / total, 0, 1), 0, 1, 0)
					-- %d, NOT ON A VALUE THAT MIGHT NOT BE A WHOLE NUMBER.
					--
					-- In Luau `("%d"):format(2.5)` does not round -- it raises "number has no integer
					-- representation". This is the body of a `while true` inside a task.spawn with no
					-- pcall around it, so one such multiplier would kill this thread permanently: every
					-- potion timer in the session freezes at whatever it last showed, no error reaches
					-- the player, and the bug looks like "my potion never ran out". A potion multiplier
					-- is authored as 2 today and nothing stops the next one being 1.5.
					row.effect.Text = b.mult and ("x%s %s"):format(formatMult(b.mult), LABEL[kind] or kind)
						or (b.luckAdd and ("+%d%% Luck"):format(math.floor(b.luckAdd)) or "Boost")
				else
					row.card.Visible = false
				end
			end

			-- (No pass half any more -- see 16.1 where the chip tray was built.)

			-- The event half (7.1). Driven off the shared config against the SERVER's clock, not off
			-- the payload's own text, so the seconds fall between publishes instead of jumping every
			-- thirty. Only the first live event is drawn: two at once is possible (a festival can
			-- overlap a weekend) and a second card would push the strip up over the potion rows for
			-- the one player in a hundred who sees it. The clock is the reason to look; the effects
			-- line says what it is worth.
			--
			-- THE EFFECTS LINE SUMS EVERY LIVE EVENT, THE HEADER NAMES ONE (12.13). Overlap stopped
			-- being the rare case the paragraph above describes the moment the Colosseum took the same
			-- Saturday window as the weekend -- both are on every weekend now. The card still cannot
			-- become two cards for the reason given above, but drawing only the headliner's effects
			-- would tell a player their DNA is not doubled while it is, which is worse than a name
			-- that omits a co-runner. So: one card, the headliner's name, colour and clock (the sort
			-- in GetActiveEvents decides which that is), and the combined effects of everything
			-- running -- multiplied for mults and added for luck, exactly as GetEventMult and
			-- GetEventAdd do it on the server, so the line cannot disagree with the payout.
			local activeNow = GameConfig.GetActiveEvents()
			local live = activeNow[1]
			if live then
				local left = live.window.endTs - GameConfig.EventNow()
				eventCard.Visible = true
				eventBadge.Text = live.event.emoji
				eventBadge.BackgroundColor3 = live.event.color
				eventName.Text = live.event.name
				eventClock.Text = GameConfig.FormatDuration(left)
			else
				eventCard.Visible = false
			end

			-- The arena half (11.20). Read off the attributes rather than computed here: the interval,
			-- the spawn and the boss's health all live on the server, and a client that did its own
			-- arithmetic would drift from the board in the arena within one interval.
			--
			-- `nil` is a real state and is NOT zero -- it means BossService has not published yet
			-- (the first second of a server, or a client that got here first). Drawing "0:00" for that
			-- would announce a boss that is not coming, so the card simply stays hidden.
			-- The worn mutation (16.1). Tinted from the same `GameConfig.Mutations` row the server pays
			-- from, so the colour on the tile cannot disagree with the income stack. Nothing worn: no
			-- dot at all, rather than a grey one -- the Splicer is optional and a permanent grey mark
			-- on the tile would read as something broken rather than something not yet bought.
			local worn = hud.getData() and hud.getData().SplicerMutation
			local wornDef = nil
			if worn then
				for _, m in ipairs(GameConfig.Mutations) do
					if m.name == worn then wornDef = m break end
				end
			end
			mutationDot.Visible = wornDef ~= nil
			if wornDef then
				mutationDot.BackgroundColor3 = wornDef.color
			end

			local arenaSecs = RS:GetAttribute("ArenaBossSeconds")
			if arenaSecs == nil then
				arenaCard.Visible = false
			elseif RS:GetAttribute("ArenaBossLive") then
				arenaCard.Visible = true
				arenaName.Text = GameConfig.EventBoss.name
				arenaClock.Text = "LIVE"
			else
				arenaCard.Visible = true
				arenaName.Text = "Arena Boss"
				arenaClock.Text = ("%d:%02d"):format(arenaSecs // 60, arenaSecs % 60)
			end

			-- ================================================================================
			-- BOUNDED, AND OUT FROM UNDER THE BUTTONS (10.17)
			-- ================================================================================
			-- Measured before this existed: the strip is a 250 px frame with `ClipsDescendants`
			-- false holding up to 297 px of content -- an event card (48), the pass card (81 when
			-- nine chips wrap to two rows) and three potion cards (48 each) with 6 px between them.
			-- It is bottom-aligned, so the excess grows UPWARD into the left tile column, which
			-- starts at the same x = 20. Live at 1546x793 with every boost running, the gold pass
			-- card covered the Rebirth tile whole: the tile occupies y 289..371 and the strip's
			-- content began at 322. Not a near miss and not only on small screens -- the third
			-- button in the column was simply gone, and it is the one that opens Rebirth.
			--
			-- TWO SEPARATE FIXES, because the overlap and the overflow are two different faults.
			--
			-- 1. THE STRIP MOVES OUT OF THE COLUMN'S LANE. It is beside the buttons now rather than
			--    on top of them, so nothing it does can ever cover one again. The x is read from the
			--    tile's own live `AbsoluteSize` instead of being computed a second time -- the
			--    responsive pass at the bottom of this file shrinks the tiles from 82 to as little
			--    as 40 on a short viewport, and a hard-coded 82 here would put the strip back over
			--    the column on exactly the screens that are already tightest.
			--
			-- 2. THE HEIGHT IS A BUDGET, NOT A GUESS. The frame may reach from its own bottom edge
			--    (170 off the bottom of the screen) up to TOP_CLEAR, the same 121 the tile columns
			--    respect for the topbar and stage card. Computed in AUTHORED OFFSETS off
			--    ViewportSize, never from AbsolutePosition -- this ScreenGui reports absolutes 58 px
			--    up from where offsets are measured (the topbar inset), and mixing the two is how
			--    an element lands exactly one inset out of place.
			--
			-- WHEN IT STILL DOES NOT FIT, WHOLE CARDS GO, LOWEST URGENCY FIRST -- clipping was the
			-- other option and it is worse: a card sliced in half reads as a broken HUD, and the
			-- slice would land on the stroke `styleCard` draws OUTSIDE the frame. The order is the
			-- honest one: the pass card first, because a pass is permanent and has nothing to miss;
			-- then the event, which is server-wide and announced elsewhere; then potions longest
			-- remaining first, so what survives to the last row is always the boost about to expire.
			-- At 793 the budget is 492 against 297 of content, so nothing is ever dropped on a
			-- desktop; a 420 px phone viewport gets 119 and keeps the two most urgent potions.
			-- BACK AGAINST THE LEFT EDGE (16.2). The sideways offset that used to be computed here
			-- existed because the left column was five tiles tall and reached down into this strip's
			-- lane. As a 2x2 block it ends around y = 311 on any viewport -- hundreds of pixels above
			-- where this strip starts -- so the strip owns the bottom-left corner outright and no longer
			-- has to be pushed out from under buttons that are not there any more.
			stack.Position = UDim2.new(0, 20, 1, -170)
			-- Read fresh every tick rather than captured once: `CurrentCamera` is nil for the first
			-- frames of a join, and the viewport changes when the window is resized.
			local viewportY = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.Y or 720
			-- CAPPED AT FOUR ROWS (16.1). The old budget was "every pixel between the tile column and
			-- the currency stack", which on a desktop is 492 -- ten rows of headroom, and the strip was
			-- happy to fill it. A HUD element free to grow to two thirds of the screen height is not a
			-- HUD element. Four 38 px rows, each measured with the 6 px `styleCard` draws outside it,
			-- plus three 6 px gaps, is 194; 196 is the ceiling and the drop pass below decides what
			-- survives it. The floor stays 96 for the same phone-viewport reason as before.
			local budget = math.clamp(viewportY - 170 - 121 - 10, 96, 196)
			stack.Size = UDim2.new(0, 224, 0, budget)

			-- Each card is measured with its stroke: `styleCard` draws 3 px outside the frame on
			-- every side, so two stacked cards cost 6 px more than their own heights claim.
			local function fits()
				local total, n = 0, 0
				for _, c in ipairs(stack:GetChildren()) do
					if c:IsA("GuiObject") and c.Visible then
						n += 1
						total += c.AbsoluteSize.Y + 6
					end
				end
				return total + math.max(n - 1, 0) * 6 <= budget
			end
			if not fits() then
				-- longest remaining last, so the first potion dropped is the one with most time left.
				-- NOTHING BUT POTIONS IS LEFT TO DROP (16.2). The arena and event pills used to lead this
				-- list; they are on their own bar along the bottom edge now and are not this strip's
				-- problem -- which also means a short viewport can no longer answer "the screen is tight"
				-- by hiding a world clock, and a boss timer can no longer crowd out an expiring potion.
				local order = {}
				local byTime = {}
				for _, kind in ipairs(KINDS) do
					local b = boosts and boosts[kind]
					if rows[kind].card.Visible then
						table.insert(byTime, { card = rows[kind].card, left = b and ((b.untilTs or 0) - now) or 0 })
					end
				end
				table.sort(byTime, function(a, b) return a.left > b.left end)
				for _, e in ipairs(byTime) do
					table.insert(order, e.card)
				end
				for _, card in ipairs(order) do
					if fits() then break end
					card.Visible = false
				end
			end

			-- `any OR owned OR an event`: a player with passes and no potion still has a strip worth
			-- showing, and one with none of the three still gets nothing rather than an empty box.
			-- Read off what SURVIVED the fit pass, not off the three flags above -- on a viewport
			-- short enough to drop everything, an empty box is exactly what those flags would draw.
			local shown = false
			for _, c in ipairs(stack:GetChildren()) do
				if c:IsA("GuiObject") and c.Visible then shown = true break end
			end
			stack.Visible = shown
			task.wait(0.25)
		end
	end)

	hud.potionTimers = rows
end
