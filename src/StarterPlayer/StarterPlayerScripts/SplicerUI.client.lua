--[[
	SplicerUI -- the DNA Splicer's panel and its roll reveal (Phase 12.3).

	=========================================================================================
	WHY THIS IS ITS OWN LOCALSCRIPT AND NOT A BLOCK IN MainUI
	=========================================================================================
	MainUI is AT Luau's 200 top-level register cap. One more top-level local there deletes the
	whole HUD, silently, at load -- it has happened twice. Everything new that needs more than a
	couple of names gets its own script and its own ScreenGui; HatchReveal and EvolveReveal are
	the same decision made twice before this one.

	=========================================================================================
	THE PANEL QUOTES THE SERVER'S OWN FUNCTION
	=========================================================================================
	`GameConfig.GetSplicerRollCost` is pure over the save, so the price on this panel is not a
	client-side estimate of the price -- it is the same call the server bills with, against the
	same payload the server just pushed. The two cannot drift, which is the whole reason that
	function takes `data` instead of living in SplicerService.

	The pity meter is the one thing this file PREDICTS rather than quotes: `SplicerRolls` is
	incremented on the server, so between pressing and hearing back the client is one behind. It
	counts the same way (`rolls % pityEvery`) and a disagreement shows as a meter that is briefly
	stale, never as a wrong roll.

	=========================================================================================
	THE REVEAL ESCALATES, AND THE BLUR IS ALWAYS TAKEN BACK
	=========================================================================================
	Common and Rare get a card. Epic and Legendary add the ray fan. Mythic and above add the
	full-screen flash, the world burst and the long stinger -- that is the whole point of a rarity
	ladder nobody can see the odds of from inside a single roll.

	`finishReveal` is called from one place and runs whether the sequence completed or threw, for
	the reason HatchReveal's own timeout exists: a blur left on screen by a failed reveal is a
	player who has to rejoin to see their own game again.

	That only works if everything it must clean is REACHABLE from it. The card and the ray fan are
	upvalues rather than locals of the sequence for exactly that reason -- see the note beside them --
	and because they are shared, a reveal may only tear down the screen while it still owns it
	(`revealToken`).
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local SoundLibrary = require(ReplicatedStorage.Modules.SoundLibrary)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local currentData = nil
local rolling = false
-- Declared one per line rather than as `local panel, dim, ...`. That comma form is valid Luau and
-- reads better, but `tools/luanames.py` MIS-PARSES it: it registers only the first name, then
-- reports the last name of the list AND the next `local` in the file as undeclared. Measured on a
-- three-line fixture, not guessed. Nine free lines are cheaper than a permanently noisy tripwire --
-- see the note in src/SYNC.md.
local panel = nil
local dim = nil
local costLabel = nil
local currentLabel = nil
local pityLabel = nil
local pityBar = nil
local oddsRows = nil
local rollButton = nil

-- UITheme outlines every label in `Color.Outline` (a near-black) at 4px, which is right for the
-- white-on-colour text the HUD is made of and WRONG for dark text on this panel's white card: the
-- glyph and its own outline are then the same colour and the label renders as a solid blob. No
-- property probe can see that -- `.Text`, `.TextFits` and `.TextColor3` all read correct -- so it
-- survived until the panel was looked at. Dark text on white needs NO outline (the white already
-- separates it); a near-black swatch that must stay near-black (Secret) keeps its outline and turns
-- it light instead.
local function inkOnWhite(label)
	local s = label:FindFirstChildOfClass("UIStroke")
	if s then s.Thickness = 0 end
	return label
end

local function lightOutline(label)
	local s = label:FindFirstChildOfClass("UIStroke")
	if s then s.Color = UITheme.Color.PanelWhite end
	return label
end

-- Luminance of the authored colour, so the rule is "is this dark?" rather than a list of names --
-- a mutation added to the ladder later is handled without touching this file.
local function isDark(c)
	return (0.299 * c.R + 0.587 * c.G + 0.114 * c.B) < 0.25
end

local gui = Instance.new("ScreenGui")
gui.Name = "SplicerUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 8
gui.Parent = playerGui

-- ============================================================================
-- THE PANEL
-- ============================================================================
local function build()
	dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Size = UDim2.new(1, 0, 1, 0)
	dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	dim.BackgroundTransparency = 0.5
	dim.BorderSizePixel = 0
	dim.ZIndex = 19
	dim.Visible = false
	dim.Parent = gui

	panel = Instance.new("Frame")
	panel.Name = "SplicerPanel"
	-- 468 wide: the odds table is the widest thing on it at 7 rows of "name .... 61.3%", and the
	-- header's subtitle wants a line it does not have to wrap. 520 tall clears the odds table,
	-- the current-mutation card and the roll button with the panel's own 16 margins.
	panel.Size = UDim2.new(0, 468, 0, 520)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = UITheme.Color.PanelWhite
	panel.BorderSizePixel = 0
	panel.ZIndex = 20
	panel.Visible = false
	panel.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 22)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 5
	stroke.Color = UITheme.Color.Outline
	stroke.Parent = panel

	local _, contentY = UITheme.PanelHeader(panel, {
		title = "🧬 DNA Splicer",
		subtitle = "Splice a mutation into your DNA -- one is worn at a time",
		accent = UITheme.Color.Aqua,
		maxTextSize = 30,
	})

	local close = UITheme.Button(panel, {
		name = "Close",
		text = "X",
		color = UITheme.Color.Red,
		radius = 12,
		size = UDim2.new(0, 42, 0, 42),
		position = UDim2.new(1, -10, 0, 10),
		anchorPoint = Vector2.new(1, 0),
		zIndex = 26,
		maxTextSize = 26,
	})
	close.MouseButton1Click:Connect(function()
		panel.Visible = false
		dim.Visible = false
	end)

	-- ---- what you are wearing right now
	local worn = UITheme.Card(panel, {
		name = "WornCard",
		color = UITheme.Color.Lavender,
		size = UDim2.new(1, -32, 0, 62),
		position = UDim2.new(0, 16, 0, contentY),
		radius = 16,
		zIndex = 21,
	})
	currentLabel = UITheme.Label(worn, {
		name = "WornLabel",
		text = "No mutation yet",
		size = UDim2.new(1, -20, 1, -12),
		position = UDim2.new(0.5, 0, 0.5, 0),
		anchorPoint = Vector2.new(0.5, 0.5),
		maxTextSize = 22,
		minTextSize = 13,
		wrapped = true,
		zIndex = 24,
	})

	-- ---- the odds, at this player's own luck
	local oddsCard = UITheme.Card(panel, {
		name = "OddsCard",
		color = UITheme.Color.PanelBlue,
		size = UDim2.new(1, -32, 0, 214),
		position = UDim2.new(0, 16, 0, contentY + 72),
		radius = 16,
		zIndex = 21,
	})
	UITheme.Label(oddsCard, {
		name = "OddsTitle",
		text = "CHANCES",
		size = UDim2.new(1, -20, 0, 22),
		position = UDim2.new(0, 12, 0, 6),
		xAlign = "Left",
		maxTextSize = 17,
		color = UITheme.Color.Cream,
		zIndex = 24,
	})

	oddsRows = {}
	for i, m in ipairs(GameConfig.Mutations) do
		local row = UITheme.Label(oddsCard, {
			name = "Odds" .. m.name,
			text = m.name,
			size = UDim2.new(1, -24, 0, 24),
			position = UDim2.new(0, 12, 0, 28 + (i - 1) * 26),
			xAlign = "Left",
			maxTextSize = 18,
			minTextSize = 12,
			color = m.color,
			zIndex = 24,
		})
		-- Secret is authored near-black on purpose. On the odds card it would vanish into its own
		-- outline, so that one row gets a light outline and reads as black-with-a-halo instead.
		if isDark(m.color) then
			lightOutline(row)
		end
		local pct = UITheme.Label(oddsCard, {
			name = "Pct" .. m.name,
			text = "--",
			size = UDim2.new(0, 96, 0, 24),
			position = UDim2.new(1, -12, 0, 28 + (i - 1) * 26),
			anchorPoint = Vector2.new(1, 0),
			xAlign = "Right",
			maxTextSize = 18,
			minTextSize = 12,
			color = UITheme.Color.Cream,
			zIndex = 24,
		})
		oddsRows[m.name] = pct
	end

	-- ---- the pity meter
	pityLabel = UITheme.Label(panel, {
		name = "PityLabel",
		text = "",
		size = UDim2.new(1, -32, 0, 20),
		position = UDim2.new(0, 16, 0, contentY + 296),
		xAlign = "Left",
		maxTextSize = 16,
		minTextSize = 11,
		color = UITheme.Color.Outline,
		zIndex = 22,
	})
	inkOnWhite(pityLabel)
	pityBar = UITheme.ProgressBar(panel, {
		name = "PityBar",
		size = UDim2.new(1, -32, 0, 16),
		position = UDim2.new(0, 16, 0, contentY + 318),
		color = UITheme.Color.Sunny,
		radius = UITheme.Radius.Pill,
		thickness = 3,
		zIndex = 22,
	})

	-- ---- the button
	rollButton = UITheme.Button(panel, {
		name = "RollButton",
		text = "SPLICE",
		color = UITheme.Color.Green,
		size = UDim2.new(1, -32, 0, 50),
		position = UDim2.new(0, 16, 0, contentY + 346),
		radius = 16,
		zIndex = 22,
		maxTextSize = 28,
	})
	costLabel = UITheme.Label(panel, {
		name = "CostLabel",
		text = "",
		size = UDim2.new(1, -32, 0, 22),
		position = UDim2.new(0, 16, 0, contentY + 400),
		maxTextSize = 18,
		minTextSize = 12,
		color = UITheme.Color.Outline,
		zIndex = 22,
	})

	inkOnWhite(costLabel)

	rollButton.MouseButton1Click:Connect(function()
		if rolling then return end
		Remotes.SpliceRoll:FireServer()
	end)
end

-- ============================================================================
-- WHAT THE PANEL SAYS
-- ============================================================================
local function refresh()
	if not currentData or not panel then return end

	local cost = GameConfig.GetSplicerRollCost(currentData)
	local afford = (currentData.DNA or 0) >= cost
	costLabel.Text = ("🧬 %s"):format(UITheme.FormatNumber(cost))
	costLabel.TextColor3 = afford and UITheme.Color.Outline or UITheme.Color.Red
	UITheme.SetColor(rollButton, afford and UITheme.Color.Green or UITheme.Color.Locked)

	local worn = currentData.SplicerMutation and GameConfig.GetMutationByName(currentData.SplicerMutation)
	if worn then
		currentLabel.Text = ("Wearing %s -- x%.2f income, +%d%% speed")
			:format(worn.name, worn.incomeMult, worn.speedPct or 0)
		currentLabel.TextColor3 = worn.color
	else
		currentLabel.Text = "No mutation yet -- splice one to begin"
		currentLabel.TextColor3 = UITheme.Color.Cream
	end

	-- The odds, computed the way the roll computes them, at this player's own luck. A charged
	-- roll's odds are shown when the NEXT roll is the charged one, so the table on screen always
	-- describes the button underneath it.
	local S = GameConfig.Splicer
	local rolls = currentData.SplicerRolls or 0
	local nextIsCharged = ((rolls + 1) % S.pityEvery) == 0
	local luck = GameConfig.GetSplicerLuck(currentData, nextIsCharged)
	local total, weights = 0, {}
	for i, m in ipairs(GameConfig.Mutations) do
		local w = m.weight * (1 + (luck / 100) * (i - 1) * 0.5)
		weights[i] = w
		total += w
	end
	for i, m in ipairs(GameConfig.Mutations) do
		local pct = (weights[i] / total) * 100
		local row = oddsRows[m.name]
		if row then
			-- a 1-in-816 roll is 0.12%, and "0.1%" throws away the digit that makes it exciting
			row.Text = pct >= 1 and ("%.1f%%"):format(pct) or ("%.3f%%"):format(pct)
		end
	end

	local into = rolls % S.pityEvery
	local togo = S.pityEvery - into
	if nextIsCharged then
		pityLabel.Text = "⚡ NEXT ROLL IS CHARGED -- guaranteed Rare or better"
		pityLabel.TextColor3 = UITheme.Color.Orange
	else
		pityLabel.Text = ("Charged roll in %d"):format(togo)
		pityLabel.TextColor3 = UITheme.Color.Outline
	end
	-- recursive since 18.1: `UITheme.ProgressBar` parents the fill inside the bar's `InnerBody` so
	-- the pill's own clip trims it at both ends, and a flat lookup here would find nothing silently
	local fill = pityBar:FindFirstChild("Fill", true)
	if fill then
		fill.Size = UDim2.new(into / S.pityEvery, 0, 1, 0)
	end
end

-- ============================================================================
-- THE REVEAL
-- ============================================================================
local blur = nil
-- The card and the ray fan are UPVALUES, not locals inside the sequence, and that is the whole
-- point. They used to be declared inside the pcall and passed out on the success path only, so a
-- throw halfway through called `finishReveal(nil, nil)`: the blur came off (it was already an
-- upvalue) and the card and rays stayed parented to the ScreenGui FOREVER. Measured, not reasoned
-- about -- a forced failure left an empty 380x210 white card and its rays on screen for the rest of
-- the session, and the next roll simply built a second one on top. One cleanup path only works if
-- everything it must clean is reachable from it.
local revealCard = nil
local revealRays = nil
-- Which reveal owns the screen. Making the card an upvalue fixes the leak but creates a second
-- hazard in its place: a reveal runs about 4 s and the server's rate limit is far shorter than
-- that, so two results CAN overlap -- and then the first sequence's `finishReveal`, arriving late,
-- would destroy the second one's card and leave the player staring at a blurred world with nothing
-- on it. A tear-down is only allowed from the reveal that is still the current one.
local revealToken = 0

local function teardown(immediate)
	if blur then
		local dying = blur
		blur = nil
		if immediate then
			dying:Destroy()
		else
			TweenService:Create(dying, TweenInfo.new(0.35), { Size = 0 }):Play()
			task.delay(0.4, function() dying:Destroy() end)
		end
	end
	if revealRays then
		revealRays:Destroy()
		revealRays = nil
	end
	if revealCard then
		revealCard:Destroy()
		revealCard = nil
	end
end

local function finishReveal(token)
	-- ONE cleanup path, taken whether the sequence finished or threw. See the header.
	if token ~= revealToken then return end
	teardown(false)
	rolling = false
end

local function reveal(payload)
	-- A newer roll replaces whatever is on screen rather than stacking on top of it. Done before
	-- anything is built, and with the blur destroyed outright, so two BlurEffects never overlap.
	revealToken += 1
	local myToken = revealToken
	teardown(true)
	rolling = true
	local m = GameConfig.GetMutationByName(payload.name)
	local color = payload.color or (m and m.color) or UITheme.Color.Lavender
	local idx = payload.index or 1
	local big = idx >= 5      -- Mythic and above: the full treatment
	local mid = idx >= 3      -- Epic and above: rays

	local ok, err = pcall(function()
		blur = Instance.new("BlurEffect")
		-- Named, because Lighting already holds EvolveReveal's own BlurEffect parked at Size 0 and
		-- a `FindFirstChildOfClass("BlurEffect")` finds that one first -- which reads as "the blur
		-- never rose" when it is only the wrong object being measured.
		blur.Name = "SpliceRevealBlur"
		blur.Size = 0
		blur.Parent = Lighting
		TweenService:Create(blur, TweenInfo.new(0.3), { Size = big and 24 or 14 }):Play()

		local card = Instance.new("Frame")
		revealCard = card
		card.Name = "SpliceReveal"
		card.Size = UDim2.new(0, 380, 0, 210)
		card.Position = UDim2.new(0.5, 0, 0.5, 0)
		card.AnchorPoint = Vector2.new(0.5, 0.5)
		card.BackgroundColor3 = UITheme.Color.PanelWhite
		card.BorderSizePixel = 0
		card.ZIndex = 60
		card.Parent = gui
		local cc = Instance.new("UICorner")
		cc.CornerRadius = UDim.new(0, 20)
		cc.Parent = card
		local cs = Instance.new("UIStroke")
		cs.Thickness = 5
		cs.Color = UITheme.Color.Outline
		cs.Parent = card

		local rays
		if mid then
			rays = Instance.new("Frame")
			rays.Name = "Rays"
			rays.Size = UDim2.new(0, 620, 0, 620)
			rays.Position = UDim2.new(0.5, 0, 0.5, 0)
			rays.AnchorPoint = Vector2.new(0.5, 0.5)
			rays.BackgroundTransparency = 1
			rays.ZIndex = 58
			rays.Parent = gui
			revealRays = rays
			-- SIX bars of 600, each centred on the hub, NOT twelve spokes of 300 anchored at their
			-- top edge. `GuiObject.Rotation` turns an element about its own CENTRE and ignores
			-- AnchorPoint entirely, so the old form rotated each spoke about a point 150px below the
			-- card and the "starburst" came out as a fan hanging under it -- clearly visible in a
			-- screenshot and completely invisible to a probe, because AbsolutePosition is reported
			-- PRE-rotation (all twelve measured as the same rectangle pointing straight down).
			-- A bar centred on the hub is symmetric under rotation, so 6 of them at 30 degrees make
			-- the same 12 spokes with the hub where the card is.
			for i = 1, 6 do
				local ray = Instance.new("Frame")
				ray.Size = UDim2.new(0, 12, 0, 600)
				ray.Position = UDim2.new(0.5, 0, 0.5, 0)
				ray.AnchorPoint = Vector2.new(0.5, 0.5)
				ray.BackgroundColor3 = color
				ray.BackgroundTransparency = 0.55
				ray.BorderSizePixel = 0
				ray.Rotation = (i / 6) * 180
				ray.ZIndex = 58
				ray.Parent = rays
			end
			task.spawn(function()
				local t0 = os.clock()
				while rays.Parent and os.clock() - t0 < 2.6 do
					rays.Rotation = (os.clock() - t0) * 26
					task.wait()
				end
			end)
		end

		inkOnWhite(UITheme.Label(card, {
			name = "Kicker",
			text = payload.charged and "⚡ CHARGED SPLICE" or "SPLICE COMPLETE",
			size = UDim2.new(1, -24, 0, 24),
			position = UDim2.new(0, 12, 0, 14),
			maxTextSize = 18,
			color = UITheme.Color.Outline,
			zIndex = 62,
		}))

		-- the name, cycling through the ladder before it lands: the slot-machine beat that makes a
		-- roll feel rolled rather than announced
		local nameLabel = UITheme.Label(card, {
			name = "Name",
			text = payload.name,
			size = UDim2.new(1, -24, 0, 62),
			position = UDim2.new(0, 12, 0, 44),
			maxTextSize = 46,
			color = color,
			zIndex = 62,
		})
		-- The name is the ONE label on this card that keeps its dark outline, because it is drawn in
		-- the mutation's own colour and every rung of the ladder is light -- except Secret, which is
		-- authored near-black and would disappear into the outline it shares. The spin cycles through
		-- the whole ladder, so the choice has to travel with each pick, not be made once here.
		local function paintName(c)
			nameLabel.TextColor3 = c
			local s = nameLabel:FindFirstChildOfClass("UIStroke")
			if s then
				s.Color = isDark(c) and UITheme.Color.PanelWhite or UITheme.Color.Outline
			end
		end
		paintName(color)
		local statLabel = inkOnWhite(UITheme.Label(card, {
			name = "Stat",
			text = "",
			size = UDim2.new(1, -24, 0, 26),
			position = UDim2.new(0, 12, 0, 112),
			maxTextSize = 20,
			minTextSize = 13,
			color = UITheme.Color.Outline,
			zIndex = 62,
		}))
		local footLabel = inkOnWhite(UITheme.Label(card, {
			name = "Foot",
			text = "",
			size = UDim2.new(1, -24, 0, 24),
			position = UDim2.new(0, 12, 0, 146),
			maxTextSize = 17,
			minTextSize = 12,
			wrapped = true,
			color = UITheme.Color.Outline,
			zIndex = 62,
		}))

		card.Size = UDim2.new(0, 40, 0, 210)
		TweenService:Create(card, TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = UDim2.new(0, 380, 0, 210) }):Play()

		-- the cycle, decelerating into the result
		local spins = big and 16 or (mid and 11 or 7)
		local wait = 0.035
		for i = 1, spins do
			local pick = GameConfig.Mutations[math.random(1, #GameConfig.Mutations)]
			nameLabel.Text = pick.name
			paintName(pick.color)
			task.wait(wait)
			wait *= 1.16
		end
		nameLabel.Text = payload.name
		paintName(color)

		statLabel.Text = ("x%.2f income  ·  +%d%% speed"):format(payload.incomeMult or 1, payload.speedPct or 0)
		footLabel.Text = payload.equipped and "✅ Now worn" or "Kept -- your current mutation is stronger"

		-- Keyed through `PlayNotify` rather than naming a sound file, so the Splicer inherits the
		-- one mapping table (`SoundLibrary.NOTIFY_SOUND`) the rest of the game routes through:
		-- `evolve` is this game's big-moment sting and `fuse` its "something was made" chime.
		SoundLibrary.PlayNotify({ kind = big and "evolve" or "fuse" })

		if big then
			local flash = Instance.new("Frame")
			flash.Size = UDim2.new(1, 0, 1, 0)
			flash.BackgroundColor3 = color
			flash.BackgroundTransparency = 0.25
			flash.BorderSizePixel = 0
			flash.ZIndex = 59
			flash.Parent = gui
			TweenService:Create(flash, TweenInfo.new(0.55), { BackgroundTransparency = 1 }):Play()
			task.delay(0.6, function() flash:Destroy() end)
		end

		task.wait(big and 2.2 or 1.5)
		TweenService:Create(card, TweenInfo.new(0.25), { Size = UDim2.new(0, 40, 0, 210) }):Play()
		task.wait(0.26)
		finishReveal(myToken)
	end)

	if not ok then
		finishReveal(myToken)
		warn("[SplicerUI] reveal failed: " .. tostring(err))
	end
end

-- ============================================================================
-- WIRING
-- ============================================================================
build()

Remotes.DataUpdate.OnClientEvent:Connect(function(data)
	currentData = data
	refresh()
end)

Remotes.SpliceResult.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	if payload.ok then
		task.spawn(reveal, payload)
		return
	end
	-- A refusal. The WORDING of it is not this file's business: "not enough DNA" is a toast, and
	-- toasts belong to MainUI's stack so that they queue, rank and sound like every other message
	-- in the game. The server sends that through `Remotes.Notify` on its own; all this side does
	-- is re-read the panel, because the refusal means the quoted price and the wallet disagree and
	-- the player is looking straight at both.
	if payload.reason == "poor" then
		refresh()
	end
end)

-- Opened by the machine's own ProximityPrompt. MainUI's handler looks `ShopPanel` up in a table
-- that has no "splicer" row and falls through, so this is the only listener that answers.
local ProximityPromptService = game:GetService("ProximityPromptService")
ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	if who ~= player then return end
	if prompt:GetAttribute("ShopPanel") ~= "splicer" then return end
	panel.Visible = true
	dim.Visible = true
	refresh()
end)
