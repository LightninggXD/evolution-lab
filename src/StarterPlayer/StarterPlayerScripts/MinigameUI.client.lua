--[[
	MinigameUI -- the arcade panel and the five games inside it (Phase 28; the fifth is 29.8).

	=========================================================================================
	WHY THIS IS ITS OWN LOCALSCRIPT AND NOT A BLOCK IN MainUI
	=========================================================================================
	MainUI is AT Luau's 200 top-level register cap. One more top-level local there deletes the
	whole HUD, silently, at load -- it has happened twice. Everything new that needs more than a
	couple of names gets its own script and its own ScreenGui; SplicerUI, HatchReveal and
	EvolveReveal are the same decision made three times before this one.

	=========================================================================================
	THE PANEL QUOTES THE SERVER'S OWN FUNCTION
	=========================================================================================
	`GameConfig.GetMinigameStatus` is pure over the save, so the cooldown, the plays left and the
	best score on this panel are not client-side estimates -- they are the same call the server
	refuses a start with, against the same payload the server just pushed. The two cannot drift,
	which is the whole reason that function takes `data` rather than living in MinigameService.

	=========================================================================================
	ONE SHELL, FIVE GAMES, ONE CLEANUP PATH
	=========================================================================================
	Every game is a function that fills `board` and registers whatever it made through `ctx.bind`.
	The shell owns the clock, the score, the timer bar and the teardown, so a game is only its own
	rules -- and, more importantly, there is exactly ONE place that disconnects things. A minigame
	that leaks a Heartbeat is a client that gets slower every time it is played, and it would leak
	five different ways if each game tore itself down.

	`stopRun` runs whether the run ended, timed out, or the panel was closed under it, for the
	reason SplicerUI's `finishReveal` exists: state left behind by a game nobody finished is a
	player who has to rejoin to get their screen back. It is also the ONLY caller of the finish
	remote, so a closed panel still banks the points that were earned -- the play was already spent
	when the run started (see the header of MinigameService).
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local SoundLibrary = require(ReplicatedStorage.Modules.SoundLibrary)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Declared one per line rather than as `local a, b, c`. That comma form is valid Luau and reads
-- better, but `tools/luanames.py` MIS-PARSES it -- see the same note in SplicerUI.
local currentData = nil
local zoneKey = nil
local modal = nil
local content = nil
local briefing = nil
local playing = nil
local result = nil
local board = nil
local titleLabel = nil
local blurbLabel = nil
local statusLabel = nil
local bestLabel = nil
local playButton = nil
local timerFill = nil
local scoreLabel = nil
local extraLabel = nil
local resultLines = nil
local againButton = nil

-- The live run. `token` is the server's; `binds` is everything the run made that has to be undone.
local run = nil

local ZB = 0 -- z base for anything drawn on `content`, filled in by build()

-- ============================================================================
-- THE SHELL
-- ============================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "MinigameUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 9
gui.Parent = playerGui

local function label(parent, text, size, position, opts)
	opts = opts or {}
	return UITheme.Label(parent, {
		text = text,
		size = size,
		position = position,
		zIndex = opts.zIndex or (ZB + 2),
		xAlign = opts.xAlign,
		color = opts.color,
		maxTextSize = opts.maxTextSize or 24,
		minTextSize = opts.minTextSize,
		wrapped = opts.wrapped,
	})
end

local function build()
	local m, c, close = UITheme.Modal(gui, {
		name = "MinigamePanel",
		title = "\u{1F3AE} Arcade",
		size = UDim2.new(0, 640, 0, 540),
		-- A dark inner board rather than the shops' panel blue: four of the five games are bright
		-- objects moving on a field, and they read as objects only if the field is quiet.
		accent = Color3.fromRGB(32, 28, 48),
	})
	modal, content = m, c
	ZB = content.ZIndex + UITheme.Z.Content

	close.Activated:Connect(function()
		SoundLibrary.PlayLocal("close")
		modal.Visible = false
	end)

	-- ---- briefing -------------------------------------------------------
	briefing = Instance.new("Frame")
	briefing.Name = "Briefing"
	briefing.BackgroundTransparency = 1
	briefing.Size = UDim2.new(1, -32, 1, -32)
	briefing.Position = UDim2.new(0, 16, 0, 16)
	briefing.ZIndex = ZB
	briefing.Parent = content

	titleLabel = label(briefing, "", UDim2.new(1, 0, 0, 46), UDim2.new(0, 0, 0, 4),
		{ maxTextSize = 38 })
	blurbLabel = label(briefing, "", UDim2.new(1, 0, 0, 74), UDim2.new(0, 0, 0, 56),
		{ maxTextSize = 20, wrapped = true, color = Color3.fromRGB(226, 224, 244) })
	bestLabel = label(briefing, "", UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 0, 140),
		{ maxTextSize = 20, color = UITheme.Color.Gold })
	statusLabel = label(briefing, "", UDim2.new(1, 0, 0, 60), UDim2.new(0, 0, 0, 178),
		{ maxTextSize = 20, wrapped = true, color = Color3.fromRGB(206, 204, 232) })

	playButton = UITheme.Button(briefing, {
		name = "Play",
		text = "PLAY",
		color = UITheme.Color.Green,
		size = UDim2.new(0, 260, 0, 50),
		position = UDim2.new(0.5, 0, 1, -70),
		anchorPoint = Vector2.new(0.5, 0),
		zIndex = ZB + 2,
		maxTextSize = 30,
	})

	-- ---- playing --------------------------------------------------------
	playing = Instance.new("Frame")
	playing.Name = "Playing"
	playing.BackgroundTransparency = 1
	playing.Size = UDim2.new(1, -24, 1, -24)
	playing.Position = UDim2.new(0, 12, 0, 12)
	playing.ZIndex = ZB
	playing.Visible = false
	playing.Parent = content

	local timerTrack = Instance.new("Frame")
	timerTrack.Name = "TimerTrack"
	timerTrack.Size = UDim2.new(1, 0, 0, 12)
	timerTrack.Position = UDim2.new(0, 0, 0, 0)
	timerTrack.BackgroundColor3 = Color3.fromRGB(18, 16, 30)
	timerTrack.BorderSizePixel = 0
	timerTrack.ZIndex = ZB + 1
	timerTrack.Parent = playing
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = timerTrack

	timerFill = Instance.new("Frame")
	timerFill.Name = "TimerFill"
	timerFill.Size = UDim2.new(1, 0, 1, 0)
	timerFill.BackgroundColor3 = UITheme.Color.Mint
	timerFill.BorderSizePixel = 0
	timerFill.ZIndex = ZB + 2
	timerFill.Parent = timerTrack
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = timerFill

	scoreLabel = label(playing, "0", UDim2.new(0.5, 0, 0, 32), UDim2.new(0, 0, 0, 18),
		{ xAlign = "Left", maxTextSize = 26, color = UITheme.Color.White })
	extraLabel = label(playing, "", UDim2.new(0.5, 0, 0, 32), UDim2.new(0.5, 0, 0, 18),
		{ xAlign = "Right", maxTextSize = 26, color = UITheme.Color.Coral })

	board = Instance.new("Frame")
	board.Name = "Board"
	board.BackgroundTransparency = 1
	board.Size = UDim2.new(1, 0, 1, -58)
	board.Position = UDim2.new(0, 0, 0, 58)
	board.ClipsDescendants = true
	board.ZIndex = ZB + 1
	board.Parent = playing

	-- ---- result ---------------------------------------------------------
	result = Instance.new("Frame")
	result.Name = "Result"
	result.BackgroundTransparency = 1
	result.Size = UDim2.new(1, -32, 1, -32)
	result.Position = UDim2.new(0, 16, 0, 16)
	result.ZIndex = ZB
	result.Visible = false
	result.Parent = content

	resultLines = {}
	resultLines.title = label(result, "", UDim2.new(1, 0, 0, 48), UDim2.new(0, 0, 0, 10),
		{ maxTextSize = 38 })
	resultLines.score = label(result, "", UDim2.new(1, 0, 0, 40), UDim2.new(0, 0, 0, 70),
		{ maxTextSize = 30, color = UITheme.Color.White })
	resultLines.best = label(result, "", UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 0, 116),
		{ maxTextSize = 22, color = UITheme.Color.Gold })
	resultLines.dna = label(result, "", UDim2.new(1, 0, 0, 40), UDim2.new(0, 0, 0, 158),
		{ maxTextSize = 30, color = UITheme.Color.Aqua })
	resultLines.diamonds = label(result, "", UDim2.new(1, 0, 0, 32), UDim2.new(0, 0, 0, 204),
		{ maxTextSize = 24, color = UITheme.Color.SkyBlue })
	resultLines.status = label(result, "", UDim2.new(1, 0, 0, 56), UDim2.new(0, 0, 0, 250),
		{ maxTextSize = 20, wrapped = true, color = Color3.fromRGB(206, 204, 232) })

	againButton = UITheme.Button(result, {
		name = "Again",
		text = "BACK",
		color = UITheme.Color.Blue,
		size = UDim2.new(0, 260, 0, 50),
		position = UDim2.new(0.5, 0, 1, -70),
		anchorPoint = Vector2.new(0.5, 0),
		zIndex = ZB + 2,
		maxTextSize = 30,
	})
end

-- ============================================================================
-- THE BRIEFING
-- ============================================================================
local function showBriefing()
	briefing.Visible = true
	playing.Visible = false
	result.Visible = false

	local status = GameConfig.GetMinigameStatus(currentData, zoneKey)
	local kind = status.kind
	if not kind then return end

	UITheme.SetText(titleLabel, kind.emoji .. "  " .. kind.name)
	UITheme.SetText(blurbLabel, kind.blurb)
	UITheme.SetText(bestLabel, ("Your best: %d   \u{2022}   Par: %d")
		:format(status.best or 0, kind.par))

	if status.ready then
		UITheme.SetText(statusLabel, ("%s\n%d of %d runs left today")
			:format(kind.howTo, status.playsLeft, status.dailyPlays))
		playButton.Visible = true
	else
		playButton.Visible = false
		if status.reason == "capped" then
			UITheme.SetText(statusLabel, ("That is all %d arcade runs for today.\nThe board resets at midnight UTC.")
				:format(status.dailyPlays))
		else
			UITheme.SetText(statusLabel, ("This terminal is cooling down.\nReady in %s.")
				:format(GameConfig.FormatDuration(status.secondsLeft)))
		end
	end
end

-- ============================================================================
-- THE GAMES
--
-- Each one is `function(ctx)` and fills `ctx.board`. What a game may use:
--   ctx.kind    the GameConfig row it is being played from
--   ctx.rng     a Random seeded by the server, so a run is reproducible from its own log
--   ctx.add(n)  score, floored at zero -- a penalty can never put a player in debt
--   ctx.setExtra(text)  the right-hand HUD line (lives, misses, whatever the game counts)
--   ctx.finish()        end the run NOW rather than at the clock
--   ctx.bind(x)         a connection or an instance the shell must clean up
--   ctx.onTick          optional; called every frame with (dt, remaining)
-- ============================================================================
local games = {}

-- ---- DNA Match (Animal Jam Classic: "Double Up") -------------------------
--
-- Twelve cards, six pairs, flipped two at a time. The one rule worth stating: a third card cannot
-- be flipped while two wrong ones are being shown. Without that guard a fast player flips the whole
-- board in one pass and the game is a clicking speed test rather than a memory test.
games.Match = function(ctx)
	local FACES = { "\u{1F9EC}", "\u{1F9A0}", "\u{1F41F}", "\u{1F98E}", "\u{1F43A}", "\u{1F98D}" }

	local deck = {}
	for i = 1, ctx.kind.pairs do
		table.insert(deck, FACES[i])
		table.insert(deck, FACES[i])
	end
	for i = #deck, 2, -1 do
		local j = ctx.rng:NextInteger(1, i)
		deck[i], deck[j] = deck[j], deck[i]
	end

	local grid = Instance.new("Frame")
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.new(1, -40, 1, -20)
	grid.Position = UDim2.new(0, 20, 0, 10)
	grid.ZIndex = ctx.ZB + 2
	grid.Parent = ctx.board
	ctx.bind(grid)

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.24, 0, 0.30, 0)
	layout.CellPadding = UDim2.new(0.013, 0, 0.026, 0)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = grid

	local flipped = {}
	local locked = false
	local found = 0

	local function faceUp(card, up)
		card.BackgroundColor3 = up and Color3.fromRGB(250, 250, 255) or Color3.fromRGB(64, 58, 96)
		local face = card:FindFirstChild("Face")
		if face then
			face.Text = up and card:GetAttribute("Face") or "?"
			face.TextColor3 = up and Color3.fromRGB(30, 26, 44) or Color3.fromRGB(190, 186, 220)
		end
	end

	for index, face in ipairs(deck) do
		local card = Instance.new("TextButton")
		card.Name = "Card" .. index
		card.Text = ""
		card.AutoButtonColor = false
		card.BorderSizePixel = 0
		card.ZIndex = ctx.ZB + 3
		card:SetAttribute("Face", face)
		card.Parent = grid

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = card

		local text = Instance.new("TextLabel")
		text.Name = "Face"
		text.BackgroundTransparency = 1
		text.Size = UDim2.new(1, 0, 1, 0)
		text.Font = UITheme.Font.Display
		text.TextScaled = true
		text.ZIndex = ctx.ZB + 4
		text.Parent = card

		faceUp(card, false)

		ctx.bind(card.Activated:Connect(function()
			if locked or card:GetAttribute("Done") or card:GetAttribute("Up") then return end
			card:SetAttribute("Up", true)
			faceUp(card, true)
			SoundLibrary.PlayLocal("click")
			table.insert(flipped, card)

			if #flipped < 2 then return end

			local a, b = flipped[1], flipped[2]
			flipped = {}
			if a:GetAttribute("Face") == b:GetAttribute("Face") then
				a:SetAttribute("Done", true)
				b:SetAttribute("Done", true)
				a.BackgroundColor3 = Color3.fromRGB(150, 240, 190)
				b.BackgroundColor3 = Color3.fromRGB(150, 240, 190)
				found += 1
				ctx.add(ctx.kind.pairPoints)
				ctx.setExtra(("%d / %d pairs"):format(found, ctx.kind.pairs))
				SoundLibrary.PlayLocal("collect")
				if found >= ctx.kind.pairs then
					-- The time bonus is the whole reason to hurry, and it is added here rather
					-- than by the shell so a run that times out cannot collect it.
					ctx.add(math.floor(ctx.remaining() * ctx.kind.timeBonusPerSecond))
					ctx.finish()
				end
			else
				locked = true
				task.delay(0.62, function()
					if not a.Parent or not b.Parent then return end
					a:SetAttribute("Up", false)
					b:SetAttribute("Up", false)
					faceUp(a, false)
					faceUp(b, false)
					locked = false
				end)
			end
		end))
	end

	ctx.setExtra(("0 / %d pairs"):format(ctx.kind.pairs))
end

-- ---- Phantom Purge (Animal Jam Classic: "Spider Zapper") -----------------
--
-- One target at a time, in a random spot, for a window that shrinks as the run goes on. Missing
-- one costs points AND is what the fiction calls a cell dividing, so the penalty reads as a
-- consequence rather than as a scold.
games.Purge = function(ctx)
	local kind = ctx.kind
	local live = nil
	local dieAt = 0
	local nextAt = 0
	local hits = 0
	local misses = 0

	local function clear()
		if live then
			live:Destroy()
			live = nil
		end
	end

	local function spawn(now)
		local progress = 1 - math.clamp(ctx.remaining() / kind.seconds, 0, 1)
		local showFor = kind.showForStart + (kind.showForFloor - kind.showForStart) * progress
		local size = math.floor(96 - 26 * progress)

		local cell = Instance.new("TextButton")
		cell.Name = "Cell"
		cell.Text = "\u{1F9A0}"
		cell.Font = UITheme.Font.Display
		cell.TextScaled = true
		cell.AutoButtonColor = false
		cell.BackgroundColor3 = Color3.fromRGB(150, 90, 220)
		cell.BorderSizePixel = 0
		cell.Size = UDim2.new(0, size, 0, size)
		-- Scale position, pixel size: the panel is 640 wide on a desktop and rather less on a
		-- phone, and a target placed in pixels would sit off the board on the narrow one.
		cell.Position = UDim2.new(ctx.rng:NextNumber(0.06, 0.88), 0, ctx.rng:NextNumber(0.08, 0.82), 0)
		cell.ZIndex = ctx.ZB + 3
		cell.Parent = ctx.board

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = cell

		cell.Activated:Connect(function()
			if live ~= cell then return end
			hits += 1
			ctx.add(kind.hitPoints)
			ctx.setExtra(("%d zapped  \u{2022}  %d split"):format(hits, misses))
			SoundLibrary.PlayLocal("collect")
			clear()
			local gapProgress = 1 - math.clamp(ctx.remaining() / kind.seconds, 0, 1)
			nextAt = os.clock() + (kind.gapStart + (kind.gapFloor - kind.gapStart) * gapProgress)
		end)

		live = cell
		dieAt = now + showFor
	end

	nextAt = os.clock() + 0.4
	ctx.setExtra("0 zapped  \u{2022}  0 split")

	ctx.onTick = function()
		local now = os.clock()
		if live and now >= dieAt then
			misses += 1
			ctx.add(-kind.missPenalty)
			ctx.setExtra(("%d zapped  \u{2022}  %d split"):format(hits, misses))
			SoundLibrary.PlayLocal("error")
			clear()
			local progress = 1 - math.clamp(ctx.remaining() / kind.seconds, 0, 1)
			nextAt = now + (kind.gapStart + (kind.gapFloor - kind.gapStart) * progress)
		elseif not live and now >= nextAt then
			spawn(now)
		end
	end
end

-- ---- Sample Sort (Animal Jam Classic: "Super Sort") ----------------------
--
-- A sample falls from the centrifuge toward three beakers and has to be sent to the one of its own
-- colour before it lands. Colour rather than shape on purpose: it has to be readable in the corner
-- of the eye while the previous one is still being judged.
games.Sort = function(ctx)
	local kind = ctx.kind
	local TONES = {
		{ name = "Cyan", color = Color3.fromRGB(90, 210, 250) },
		{ name = "Rose", color = Color3.fromRGB(250, 110, 170) },
		{ name = "Lime", color = Color3.fromRGB(150, 235, 120) },
	}

	local sample = nil
	local sampleTone = 1
	local fallStart = 0
	local fallFor = kind.fallStart
	local right = 0
	local wrong = 0

	local beakers = {}
	for i = 1, kind.beakers do
		local beaker = Instance.new("TextButton")
		beaker.Name = "Beaker" .. i
		beaker.Text = TONES[i].name
		beaker.Font = UITheme.Font.Display
		beaker.TextSize = 20
		beaker.TextColor3 = Color3.fromRGB(24, 20, 36)
		beaker.AutoButtonColor = false
		beaker.BackgroundColor3 = TONES[i].color
		beaker.BorderSizePixel = 0
		beaker.Size = UDim2.new(0.28, 0, 0, 64)
		beaker.Position = UDim2.new(0.05 + (i - 1) * 0.32, 0, 1, -72)
		beaker.ZIndex = ctx.ZB + 4
		beaker.Parent = ctx.board
		ctx.bind(beaker)

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 14)
		corner.Parent = beaker
		beakers[i] = beaker
	end

	local function judge(index)
		if not sample then return end
		if index == sampleTone then
			right += 1
			ctx.add(kind.hitPoints)
			SoundLibrary.PlayLocal("collect")
		else
			wrong += 1
			ctx.add(-kind.missPenalty)
			SoundLibrary.PlayLocal("error")
		end
		ctx.setExtra(("%d sorted  \u{2022}  %d spilled"):format(right, wrong))
		sample:Destroy()
		sample = nil
	end

	for i, beaker in ipairs(beakers) do
		ctx.bind(beaker.Activated:Connect(function() judge(i) end))
	end

	-- Keys as well as taps. Three beakers and three keys under the left hand is how the AJ original
	-- is actually played once somebody is good at it, and a game whose ceiling is mouse travel time
	-- has a much lower ceiling than this one deserves.
	ctx.bind(UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.One then judge(1) end
		if input.KeyCode == Enum.KeyCode.Two then judge(2) end
		if input.KeyCode == Enum.KeyCode.Three then judge(3) end
	end))

	ctx.setExtra("0 sorted  \u{2022}  0 spilled")

	ctx.onTick = function()
		local now = os.clock()
		if not sample then
			local progress = 1 - math.clamp(ctx.remaining() / kind.seconds, 0, 1)
			fallFor = kind.fallStart + (kind.fallFloor - kind.fallStart) * progress
			sampleTone = ctx.rng:NextInteger(1, kind.beakers)

			sample = Instance.new("Frame")
			sample.Name = "Sample"
			sample.BackgroundColor3 = TONES[sampleTone].color
			sample.BorderSizePixel = 0
			sample.Size = UDim2.new(0, 54, 0, 54)
			sample.Position = UDim2.new(ctx.rng:NextNumber(0.12, 0.78), 0, 0, 0)
			sample.ZIndex = ctx.ZB + 3
			sample.Parent = ctx.board
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(1, 0)
			corner.Parent = sample

			fallStart = now
			return
		end

		local t = (now - fallStart) / fallFor
		sample.Position = UDim2.new(sample.Position.X.Scale, 0, math.min(t, 1), -54)
		if t >= 1 then
			wrong += 1
			ctx.add(-kind.missPenalty)
			ctx.setExtra(("%d sorted  \u{2022}  %d spilled"):format(right, wrong))
			SoundLibrary.PlayLocal("error")
			sample:Destroy()
			sample = nil
		end
	end
end

-- ---- Containment (Animal Jam Classic: "Falling Phantoms") ----------------
--
-- The dish follows the pointer, phantoms fall, green DNA is worth catching. The dish is moved by
-- POINTER X ONLY -- no keys, no character movement -- which is what makes it play identically on a
-- phone and on a desktop, and is why this game needed no decision about the 45-stud body at all.
games.Containment = function(ctx)
	local kind = ctx.kind
	local lives = kind.lives
	local caught = 0
	local falling = {}
	local nextAt = 0
	local dishX = 0.5

	local dish = Instance.new("Frame")
	dish.Name = "Dish"
	dish.BackgroundColor3 = Color3.fromRGB(120, 230, 255)
	dish.BorderSizePixel = 0
	dish.Size = UDim2.new(0, 120, 0, 22)
	dish.AnchorPoint = Vector2.new(0.5, 0)
	dish.Position = UDim2.new(0.5, 0, 1, -34)
	dish.ZIndex = ctx.ZB + 4
	dish.Parent = ctx.board
	ctx.bind(dish)
	local dishCorner = Instance.new("UICorner")
	dishCorner.CornerRadius = UDim.new(1, 0)
	dishCorner.Parent = dish

	local function setLives()
		ctx.setExtra(("%s   %d caught"):format(string.rep("\u{2665}", math.max(lives, 0)), caught))
	end
	setLives()

	local function pointerX(position)
		local absPos = ctx.board.AbsolutePosition.X
		local absSize = math.max(ctx.board.AbsoluteSize.X, 1)
		dishX = math.clamp((position.X - absPos) / absSize, 0.06, 0.94)
		dish.Position = UDim2.new(dishX, 0, 1, -34)
	end

	ctx.bind(UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			pointerX(input.Position)
		end
	end))
	ctx.bind(UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			pointerX(input.Position)
		end
	end))

	ctx.onTick = function(dt)
		local now = os.clock()
		local progress = 1 - math.clamp(ctx.remaining() / kind.seconds, 0, 1)

		-- Points for staying alive, paid per frame rather than per second so the score moves while
		-- the player is watching it. Floored into the score by `ctx.add`, so the fractions do not
		-- accumulate into a free point.
		ctx.add(kind.survivePointsPerSecond * dt)

		if now >= nextAt then
			local gap = kind.spawnStart + (kind.spawnFloor - kind.spawnStart) * progress
			nextAt = now + gap

			-- One in four is DNA. Any more and dodging stops being the game.
			local good = ctx.rng:NextNumber() < 0.25
			local drop = Instance.new("TextLabel")
			drop.Name = good and "DNA" or "Phantom"
			drop.BackgroundTransparency = 1
			drop.Text = good and "\u{1F9EC}" or "\u{1F47E}"
			drop.Font = UITheme.Font.Display
			drop.TextScaled = true
			drop.Size = UDim2.new(0, 46, 0, 46)
			drop.AnchorPoint = Vector2.new(0.5, 0)
			drop.Position = UDim2.new(ctx.rng:NextNumber(0.08, 0.92), 0, 0, -46)
			drop.ZIndex = ctx.ZB + 3
			drop.Parent = ctx.board
			table.insert(falling, {
				gui = drop,
				good = good,
				speed = 0.55 + 0.5 * progress + ctx.rng:NextNumber() * 0.2,
				y = -0.08,
			})
		end

		for i = #falling, 1, -1 do
			local item = falling[i]
			item.y += item.speed * dt
			item.gui.Position = UDim2.new(item.gui.Position.X.Scale, 0, item.y, 0)

			-- The catch band is the dish's own row. Compared in the board's scale space, which is
			-- the only space both the dish and the drops are expressed in.
			if item.y >= 0.86 and item.y <= 1.0 then
				if math.abs(item.gui.Position.X.Scale - dishX) < 0.10 then
					if item.good then
						caught += 1
						ctx.add(kind.catchPoints)
						SoundLibrary.PlayLocal("collect")
					else
						lives -= 1
						SoundLibrary.PlayLocal("hurt")
						dish.BackgroundColor3 = Color3.fromRGB(255, 110, 110)
						task.delay(0.2, function()
							if dish.Parent then dish.BackgroundColor3 = Color3.fromRGB(120, 230, 255) end
						end)
					end
					setLives()
					item.gui:Destroy()
					table.remove(falling, i)
					if lives <= 0 then
						ctx.finish()
						return
					end
					continue
				end
			end

			if item.y > 1.1 then
				item.gui:Destroy()
				table.remove(falling, i)
			end
		end
	end
end

-- ---- Strand Splice (Animal Jam Classic: "Overflow") ----------------------
--
-- The only PUZZLE of the five: a cut strand lies across a grid as couplers, each tap turns one a
-- quarter turn, and the strand is spliced when a run of joined ends reaches the receptor. Solving
-- one board immediately deals a bigger one, so the game is scored per strand -- see the long note
-- on `gridSteps` in `GameConfig.Minigames` for why the difficulty is in the board and not the
-- clock. It is also the only game here with no `ctx.onTick`: nothing moves on its own.
--
-- THREE THINGS ARE WORTH KNOWING BEFORE EDITING IT.
--
-- 1. A TILE IS ITS OPENINGS ROTATED, NEVER A NAMED SHAPE. There is no "elbow" or "tee" branch
--    below the generator: a tile carries a four-slot `base` array of open sides plus a `turns`
--    count, and `openAt` reads the base back through the turns. That is what makes cutting the
--    solution one line -- the path says which two sides a tile must have open and that set IS the
--    base -- where a shape vocabulary would need a name, a rotation table and a match function for
--    every shape, all of which can disagree with the drawing.
-- 2. THE PIPE IS ROTATED AND THE BUTTON IS NOT. `Rotation` on a GUI pivots on the CENTRE, which is
--    exactly right for a square tile, but `AbsolutePosition` is reported PRE-rotation and a
--    rotated button is a hit box nobody can reason about. So the TextButton stays axis-aligned and
--    an inert Frame inside it carries the arms and the quarter turn.
-- 3. THE BOARD IS SOLVABLE BY CONSTRUCTION, AND ITS LENGTH IS BOUNDED ON PURPOSE. The path is laid
--    first as a staircase that only ever steps east, or vertically inside one column, and the
--    couplers on it are cut to fit; everything else on the grid is decoration. A random walk would
--    also be solvable, but its length is unbounded -- a sixteen-cell snake through a 6x4 is not a
--    six-second board -- and a puzzle whose difficulty cannot be bounded cannot be scored per
--    solve, which is the whole payout design.
games.Splice = function(ctx)
	local kind = ctx.kind

	-- 1 = north, 2 = east, 3 = south, 4 = west, clockwise -- so one quarter turn is +1 and the
	-- whole rotation problem is arithmetic modulo 4.
	local STEP = { { -1, 0 }, { 0, 1 }, { 1, 0 }, { 0, -1 } }
	local OPPOSITE = { 3, 4, 1, 2 }

	local DEAD_PIPE = Color3.fromRGB(98, 94, 136)
	local LIVE_PIPE = Color3.fromRGB(130, 250, 200)
	local FLASH_PIPE = Color3.fromRGB(255, 255, 255)
	local DEAD_TILE = Color3.fromRGB(46, 42, 72)
	local LIVE_TILE = Color3.fromRGB(32, 68, 76)
	local NODE_TILE = Color3.fromRGB(58, 46, 92)
	-- THE TWO NODES ARE PAINTED GOLD AND ARE NOT PART OF THE FLOW COLOURING, AND A CAPTURE IS WHY.
	-- Photographed at the authored colours the receptor read as a plain plate with no coupling on
	-- it at all: its stub is 66 px of a 132 px tile and the glyph, centred at 0.66 of the tile,
	-- covered 44 of them -- so 22 px of DEAD_PIPE (98,94,136) was left showing against a node plate
	-- of (64,52,98), which is nothing a player can see. The source got away with it only because it
	-- is live by definition and was therefore drawn in mint. Two changes, and the glyph shrank to
	-- 0.54 as well: a node now says which side it accepts from, at rest, before anything is joined.
	local NODE_PIPE = Color3.fromRGB(255, 206, 110)
	local TURN_TWEEN = TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	-- Everything a board makes hangs under one holder, so dealing the next board is one
	-- `ClearAllChildren` rather than a second teardown path competing with the shell's.
	local holder = Instance.new("Frame")
	holder.Name = "SpliceHolder"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.new(0.5, 0, 0.5, 0)
	holder.Size = UDim2.new(1, -20, 1, -10)
	holder.ZIndex = ctx.ZB + 2
	holder.Parent = ctx.board
	ctx.bind(holder)

	local solved = 0
	local frozen = false
	local buildBoard = nil

	local function openAt(tile, dir)
		return tile.base[((dir - 1 - tile.turns) % 4) + 1] and true or false
	end

	-- A coupler that is not on the path. Two thirds of them are pieces that could plausibly be on
	-- it; the tees are what stop a player solving the board by looking for the only shape that fits.
	local function decoyShape()
		local roll = ctx.rng:NextNumber()
		local a = ctx.rng:NextInteger(1, 4)
		local set = { false, false, false, false }
		set[a] = true
		if roll < 0.30 then
			set[OPPOSITE[a]] = true                 -- straight
		elseif roll < 0.75 then
			set[(a % 4) + 1] = true                 -- elbow
		else
			set[(a % 4) + 1] = true                 -- tee
			set[((a + 1) % 4) + 1] = true
		end
		return set
	end

	buildBoard = function(attempt)
		holder:ClearAllChildren()
		frozen = false

		local step = kind.gridSteps[math.min(solved + 1, #kind.gridSteps)]
		local cols, rows = step[1], step[2]
		ctx.setExtra(("%d spliced  \u{2022}  %d x %d"):format(solved, cols - 2, rows))

		-- The grid is sized by an ASPECT CONSTRAINT rather than off `AbsoluteSize`. The board frame
		-- is not square and its measured size is not trustworthy on the first frame anyway -- this
		-- panel is opened AFTER `startRun` on the expedition path, so a layout read here can be one
		-- frame stale. The constraint is the engine's own answer and it makes every cell square.
		local grid = Instance.new("Frame")
		grid.Name = "Grid"
		grid.BackgroundTransparency = 1
		grid.AnchorPoint = Vector2.new(0.5, 0.5)
		grid.Position = UDim2.new(0.5, 0, 0.5, 0)
		grid.Size = UDim2.new(1, 0, 1, 0)
		grid.ZIndex = ctx.ZB + 2
		local ratio = Instance.new("UIAspectRatioConstraint")
		ratio.AspectRatio = cols / rows
		ratio.AspectType = Enum.AspectType.FitWithinMaxSize
		ratio.Parent = grid
		grid.Parent = holder

		-- ===== THE SOLUTION IS LAID BEFORE ANYTHING IS DRAWN =====
		-- Column 1 holds the source and column `cols` the receptor, so the staircase runs through
		-- the interior columns only and both nodes are reached along the one axis they open on.
		local srcRow = ctx.rng:NextInteger(1, rows)
		local dstRow = ctx.rng:NextInteger(1, rows)
		local path = { { r = srcRow, c = 1 } }
		local row = srcRow
		for c = 2, cols - 1 do
			table.insert(path, { r = row, c = c })
			local target = (c == cols - 1) and dstRow or ctx.rng:NextInteger(1, rows)
			local towards = (target > row) and 1 or -1
			while row ~= target do
				row += towards
				table.insert(path, { r = row, c = c })
			end
		end
		table.insert(path, { r = dstRow, c = cols })

		local function cellKey(r, c) return r .. "," .. c end
		local function dirBetween(a, b)
			if b.r < a.r then return 1 end
			if b.c > a.c then return 2 end
			if b.r > a.r then return 3 end
			return 4
		end

		local wanted = {}
		for i, cell in ipairs(path) do
			local set = { false, false, false, false }
			if path[i - 1] then set[dirBetween(cell, path[i - 1])] = true end
			if path[i + 1] then set[dirBetween(cell, path[i + 1])] = true end
			wanted[cellKey(cell.r, cell.c)] = set
		end

		-- ===== THE TILES =====
		local tiles = {}
		local refresh = nil
		local onSpliced = nil
		local cw = 1 / cols
		local ch = 1 / rows

		for r = 1, rows do
			tiles[r] = {}
			for c = 1, cols do
				local isSource = (r == srcRow and c == 1)
				local isReceptor = (r == dstRow and c == cols)
				local fixed = isSource or isReceptor
				local solution = wanted[cellKey(r, c)]

				-- Nothing stands in the source or the receptor column except the node itself. The
				-- board then reads the way the fiction does -- strand on the left, receptor on the
				-- right, couplers in between -- and it is a dozen fewer instances a board.
				local skip = (c == 1 or c == cols) and not fixed
				if not skip then
					local base = nil
					local turns = nil
					if fixed then
						base = { false, false, false, false }
						base[isSource and 2 or 4] = true
						turns = 0
					elseif solution then
						-- The solution set IS the base, so the tile is correct at every turn count
						-- that is a multiple of four. It starts at 1, 2 or 3 so no coupler on the
						-- path is handed to the player already right.
						base = solution
						turns = ctx.rng:NextInteger(1, 3)
					else
						base = decoyShape()
						turns = ctx.rng:NextInteger(0, 3)
					end

					local tile = { r = r, c = c, base = base, turns = turns, fixed = fixed,
						live = false, arms = {} }
					tiles[r][c] = tile

					local button = Instance.new("TextButton")
					button.Name = ("Tile%d_%d"):format(r, c)
					button.Text = ""
					button.AutoButtonColor = false
					button.BorderSizePixel = 0
					button.BackgroundColor3 = fixed and NODE_TILE or DEAD_TILE
					button.Size = UDim2.new(cw, -8, ch, -8)
					button.Position = UDim2.new((c - 1) * cw, 4, (r - 1) * ch, 4)
					button.ZIndex = ctx.ZB + 3
					button.Active = not fixed
					button.Parent = grid
					tile.button = button

					local corner = Instance.new("UICorner")
					corner.CornerRadius = UDim.new(0, 12)
					corner.Parent = button

					local pipe = Instance.new("Frame")
					pipe.Name = "Pipe"
					pipe.BackgroundTransparency = 1
					pipe.Size = UDim2.new(1, 0, 1, 0)
					pipe.Rotation = turns * 90
					pipe.ZIndex = ctx.ZB + 4
					pipe.Parent = button
					tile.pipe = pipe

					for dir = 1, 4 do
						if base[dir] then
							local a = Instance.new("Frame")
							a.Name = "Arm" .. dir
							a.BorderSizePixel = 0
							a.BackgroundColor3 = fixed and NODE_PIPE or DEAD_PIPE
							a.ZIndex = ctx.ZB + 5
							if dir == 1 then
								a.AnchorPoint = Vector2.new(0.5, 0)
								a.Position = UDim2.new(0.5, 0, 0, 0)
								a.Size = UDim2.new(0.26, 0, 0.5, 0)
							elseif dir == 3 then
								a.AnchorPoint = Vector2.new(0.5, 1)
								a.Position = UDim2.new(0.5, 0, 1, 0)
								a.Size = UDim2.new(0.26, 0, 0.5, 0)
							elseif dir == 2 then
								a.AnchorPoint = Vector2.new(1, 0.5)
								a.Position = UDim2.new(1, 0, 0.5, 0)
								a.Size = UDim2.new(0.5, 0, 0.26, 0)
							else
								a.AnchorPoint = Vector2.new(0, 0.5)
								a.Position = UDim2.new(0, 0, 0.5, 0)
								a.Size = UDim2.new(0.5, 0, 0.26, 0)
							end
							a.Parent = pipe
							table.insert(tile.arms, a)
						end
					end

					local hub = Instance.new("Frame")
					hub.Name = "Hub"
					hub.BorderSizePixel = 0
					hub.BackgroundColor3 = fixed and NODE_PIPE or DEAD_PIPE
					hub.AnchorPoint = Vector2.new(0.5, 0.5)
					hub.Position = UDim2.new(0.5, 0, 0.5, 0)
					hub.Size = UDim2.new(0.34, 0, 0.34, 0)
					hub.ZIndex = ctx.ZB + 6
					hub.Parent = pipe
					local hubCorner = Instance.new("UICorner")
					hubCorner.CornerRadius = UDim.new(1, 0)
					hubCorner.Parent = hub
					table.insert(tile.arms, hub)

					if fixed then
						-- Parented to the BUTTON, not to the pipe, so it can never inherit a turn.
						-- Both glyphs are U+1F300 and above, the range 27.7 and 29.10 established
						-- as the safe one -- a miss below it draws nothing and reports nothing.
						local mark = Instance.new("TextLabel")
						mark.Name = "Mark"
						mark.BackgroundTransparency = 1
						mark.AnchorPoint = Vector2.new(0.5, 0.5)
						mark.Position = UDim2.new(0.5, 0, 0.5, 0)
						mark.Size = UDim2.new(0.54, 0, 0.54, 0)
						mark.Font = UITheme.Font.Display
						mark.Text = isSource and "\u{1F9EC}" or "\u{1F9EA}"
						mark.TextScaled = true
						mark.ZIndex = ctx.ZB + 7
						mark.Parent = button
					else
						-- Bound even though `Destroy` disconnects an instance's own events: this
						-- game destroys and rebuilds its board several times inside one run, and
						-- the rule the shell is built on is that the game registers what it makes.
						-- A guard that depends on the engine's cleanup order is a guard nobody can
						-- check by reading this file.
						ctx.bind(button.Activated:Connect(function()
							if frozen or not holder.Parent then return end
							tile.turns += 1
							TweenService:Create(pipe, TURN_TWEEN,
								{ Rotation = tile.turns * 90 }):Play()
							SoundLibrary.PlayLocal("click")
							if refresh() then
								onSpliced()
							end
						end))
					end
				end
			end
		end

		-- Floods from the source and repaints in one pass, and RETURNS whether the receptor was
		-- reached -- so "is it solved" and "what colour is everything" can never disagree.
		refresh = function()
			for r = 1, rows do
				for c = 1, cols do
					local tile = tiles[r][c]
					if tile then tile.live = false end
				end
			end

			local source = tiles[srcRow][1]
			source.live = true
			local queue = { source }
			local head = 1
			while head <= #queue do
				local tile = queue[head]
				head += 1
				for dir = 1, 4 do
					if openAt(tile, dir) then
						local nr = tile.r + STEP[dir][1]
						local nc = tile.c + STEP[dir][2]
						local other = tiles[nr] and tiles[nr][nc]
						if other and not other.live and openAt(other, OPPOSITE[dir]) then
							other.live = true
							table.insert(queue, other)
						end
					end
				end
			end

			for r = 1, rows do
				for c = 1, cols do
					local tile = tiles[r][c]
					if tile then
						local colour = tile.fixed and NODE_PIPE
							or (tile.live and LIVE_PIPE or DEAD_PIPE)
						for _, piece in ipairs(tile.arms) do
							piece.BackgroundColor3 = colour
						end
						if not tile.fixed then
							tile.button.BackgroundColor3 = tile.live and LIVE_TILE or DEAD_TILE
						end
					end
				end
			end
			return tiles[dstRow][cols].live
		end

		onSpliced = function()
			if frozen then return end
			frozen = true
			solved += 1
			ctx.add(kind.splicePoints)
			ctx.setExtra("\u{1F9EC}  SPLICED!")
			SoundLibrary.PlayLocal("collect")

			for r = 1, rows do
				for c = 1, cols do
					local tile = tiles[r][c]
					if tile and tile.live then
						for _, piece in ipairs(tile.arms) do
							piece.BackgroundColor3 = FLASH_PIPE
						end
					end
				end
			end

			task.delay(0.55, function()
				-- The run can end inside this delay three ways -- the clock, the panel closing, a
				-- zone transition -- and all three destroy the holder. That is the check.
				if not holder.Parent then return end
				buildBoard(1)
			end)
		end

		-- A board can come out already spliced: a path with no vertical steps is all straights, and
		-- a straight is symmetric, so a starting turn of 2 leaves it correct. Rare (~1%), harmless
		-- if it ever survives four deals -- the first tap breaks the line and putting it back pays
		-- the splice -- but a board the player did not solve should not be on screen.
		if refresh() and attempt < 4 then
			return buildBoard(attempt + 1)
		end
	end

	buildBoard(1)
end

-- ============================================================================
-- THE RUN
-- ============================================================================
local function stopRun(submit)
	if not run then return end
	local finished = run
	run = nil

	for _, bound in ipairs(finished.binds) do
		if typeof(bound) == "RBXScriptConnection" then
			bound:Disconnect()
		elseif typeof(bound) == "Instance" then
			bound:Destroy()
		end
	end
	if finished.heartbeat then
		finished.heartbeat:Disconnect()
	end
	board:ClearAllChildren()

	if submit then
		-- ===== THE ONE LINE THAT MAKES A STATION A STATION (29.4) =====
		-- The four games, the shell, the clock, the score and this teardown are shared whole between
		-- the zone arcade and an Expedition station. The ONLY difference between the two is which
		-- server owns the result, and that is carried on the session as a word rather than by a
		-- second copy of any of the above.
		--
		-- It has to be decided HERE and not at the call sites, because this is the single
		-- cleanup-and-submit path: a run also ends by the clock running out, by the panel being
		-- closed and by a zone transition, and every one of those has to bank to the right server.
		local finishRemote = finished.channel == "expedition"
			and Remotes.StationFinish
			or Remotes.MinigameFinish
		finishRemote:FireServer({ token = finished.token, score = math.floor(finished.score) })
	end
end

-- The modal's own header, which is the one piece of this panel that is NOT shared: the arcade is
-- called the arcade, and a station is called by the seal it is played for. Restored to the arcade's
-- wording by the terminal prompt, so neither entry point can inherit the other's title.
local function panelTitle(session)
	local header = modal:FindFirstChild("Title")
	if not header then return end
	if session and session.channel == "expedition" then
		UITheme.SetText(header, ("%s  %s"):format(session.symbol or "\u{1F5FA}",
			session.symbolName or "Station"))
	else
		UITheme.SetText(header, "\u{1F3AE} Arcade")
	end
end

local function startRun(session)
	stopRun(false)

	local kind = GameConfig.MinigameKindsByKey[session.kindKey]
	local game = kind and games[session.kindKey]
	if not game then
		warn("[MinigameUI] no game for kind " .. tostring(session.kindKey))
		return
	end

	briefing.Visible = false
	result.Visible = false
	playing.Visible = true
	board:ClearAllChildren()
	SoundLibrary.PlayLocal("open")

	run = {
		token = session.token,
		-- "arcade" unless the server said otherwise. Defaulted rather than required so the Phase 28
		-- payload, which knows nothing about expeditions, keeps working untouched.
		channel = session.channel or "arcade",
		kind = kind,
		score = 0,
		startedAt = os.clock(),
		binds = {},
		onTick = nil,
		heartbeat = nil,
	}

	UITheme.SetText(scoreLabel, "0")
	UITheme.SetText(extraLabel, "")
	timerFill.Size = UDim2.new(1, 0, 1, 0)
	timerFill.BackgroundColor3 = UITheme.Color.Mint

	local ctx
	ctx = {
		kind = kind,
		board = board,
		ZB = ZB,
		rng = Random.new(session.seed or os.clock()),
		bind = function(item)
			if run then table.insert(run.binds, item) end
		end,
		add = function(points)
			if not run then return end
			run.score = math.max(run.score + points, 0)
			UITheme.SetText(scoreLabel, tostring(math.floor(run.score)))
		end,
		setExtra = function(text)
			UITheme.SetText(extraLabel, text)
		end,
		remaining = function()
			if not run then return 0 end
			return math.max(kind.seconds - (os.clock() - run.startedAt), 0)
		end,
		finish = function()
			stopRun(true)
		end,
	}
	ctx.onTick = nil
	run.ctx = ctx

	game(ctx)

	run.heartbeat = RunService.Heartbeat:Connect(function(dt)
		if not run then return end
		local remaining = ctx.remaining()
		local fraction = remaining / kind.seconds
		timerFill.Size = UDim2.new(fraction, 0, 1, 0)
		if fraction < 0.25 then
			timerFill.BackgroundColor3 = UITheme.Color.Coral
		end
		if ctx.onTick then
			ctx.onTick(dt, remaining)
		end
		if remaining <= 0 then
			stopRun(true)
		end
	end)
end

-- ============================================================================
-- WIRING
-- ============================================================================
build()

playButton.Activated:Connect(function()
	if run then return end
	SoundLibrary.PlayLocal("click")
	Remotes.MinigameStart:FireServer(zoneKey)
end)

againButton.Activated:Connect(function()
	SoundLibrary.PlayLocal("click")
	showBriefing()
end)

Remotes.DataUpdate.OnClientEvent:Connect(function(data)
	currentData = data
	-- Only while the briefing is the thing on screen. A push landing mid-run must not redraw the
	-- panel under a game that is using it.
	if modal.Visible and briefing.Visible then
		showBriefing()
	end
end)

-- ===== THE SECOND WAY A RUN STARTS =====
-- An Expedition station hands over the same `{token, kindKey, seed}` shape the arcade does, plus
-- `channel = "expedition"`. Everything below this line is the arcade's own code path.
--
-- The station's RESULT is not drawn here. This panel's result card talks about cooldowns and runs
-- left, which is the arcade's vocabulary; a station's outcome is a seal on the expedition HUD, so
-- `ExpeditionUI` owns that screen and this one simply closes.
Remotes.ExpeditionStation.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	if payload.ok and not payload.finished then
		-- THE PANEL IS OPENED HERE, AND IT HAS TO BE. The arcade's panel is shown by the terminal's
		-- own ProximityPrompt handler at the bottom of this file; a station's prompt carries
		-- `ShopPanel = "expedition_station"` and belongs to `ExpeditionUI`, which fires
		-- `StationStart` instead -- so nothing on this path ever made the modal visible. Measured
		-- 2026-08-21: the station game ran, scored, timed out and banked a score of 0 while
		-- completely invisible, and every property probe called it healthy (`run` was live, the
		-- board had children, the labels held their text). Only a capture showed the empty screen.
		panelTitle(payload)
		startRun(payload)
		modal.Visible = true
		return
	end
	-- Either the station finished or it was refused; either way the game is over and the wording
	-- belongs to the expedition HUD.
	if run then
		stopRun(false)
	end
	modal.Visible = false
end)

-- WAITED FOR, NOT INDEXED. `MinigameSession` is created inside `MinigameService.Init`, which runs late in
-- ServerMain -- after the whole world is laid. A client that finished loading first indexes a
-- remote that is not there yet and this line THROWS, taking the rest of this script with it.
-- Measured on a cold Play 2026-08-27: `MinigameSession is not a valid member of Folder
-- "ReplicatedStorage.Remotes"`. It wins the race on a warm server and loses it on a cold one,
-- which is the worst shape a bug can have.
Remotes:WaitForChild("MinigameSession").OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	if payload.ok then
		startRun(payload)
	else
		-- The refusal's WORDING came through Notify from the server, which owns how a refusal is
		-- queued, ranked and sounded. All this side does is re-read the panel, because the reason
		-- it was refused is exactly what the briefing prints.
		showBriefing()
	end
end)

Remotes.MinigameResult.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	briefing.Visible = false
	playing.Visible = false
	result.Visible = true

	if not payload.ok then
		UITheme.SetText(resultLines.title, "\u{26A0} Run not counted")
		UITheme.SetText(resultLines.score, "")
		UITheme.SetText(resultLines.best, "")
		UITheme.SetText(resultLines.dna, "")
		UITheme.SetText(resultLines.diamonds, "")
		UITheme.SetText(resultLines.status, payload.reason == "tooFast"
			and "That run came back faster than the game can be played."
			or "That run took too long to come back.")
		return
	end

	UITheme.SetText(resultLines.title, payload.beatPar and "\u{2B50} Par beaten!" or "Run complete")
	UITheme.SetText(resultLines.score, ("Score  %d"):format(payload.score))
	-- The old wording here read "New personal best! (was beaten at 620)" -- it was printing PAR into
	-- a sentence about the previous best, which is nonsense, and it was caught by reading the live
	-- panel rather than the code. Both numbers are worth showing and neither is worth a clause: the
	-- badge says what happened, the pair says what it was measured against.
	UITheme.SetText(resultLines.best, payload.newBest
		and ("\u{1F3C6} New personal best!  \u{2022}  Par %d"):format(payload.par)
		or ("Best %d  \u{2022}  Par %d"):format(payload.best or 0, payload.par))
	UITheme.SetText(resultLines.dna, ("+%s DNA"):format(UITheme.FormatNumber(payload.dna)))
	UITheme.SetText(resultLines.diamonds, payload.diamonds > 0
		and ("+%d Diamond"):format(payload.diamonds)
		or "")
	UITheme.SetText(resultLines.status, payload.status and payload.status.playsLeft > 0
		and ("%d runs left today \u{2022} this terminal is ready again in %s")
			:format(payload.status.playsLeft, GameConfig.FormatDuration(payload.status.secondsLeft))
		or "That is all the arcade runs for today.")

	SoundLibrary.PlayLocal(payload.newBest and "levelUp" or "collect")
	if payload.diamonds > 0 then
		task.delay(0.3, function() SoundLibrary.PlayLocal("diamond") end)
	end
end)

-- Opened by the terminal's own ProximityPrompt, on the attribute contract SplicerUI established.
ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	if who ~= player then return end
	if prompt:GetAttribute("ShopPanel") ~= "minigame" then return end
	zoneKey = prompt:GetAttribute("ZoneKey")
	if not zoneKey then return end
	SoundLibrary.PlayLocal("open")
	panelTitle(nil)
	showBriefing()
	modal.Visible = true
end)

-- THE THREE WAYS A RUN CAN BE INTERRUPTED, and all three bank the score rather than dropping it.
-- The play was spent when the run started, so a lost run would be a play taken for nothing.
modal:GetPropertyChangedSignal("Visible"):Connect(function()
	if not modal.Visible and run then
		stopRun(true)
	end
end)

Remotes.ZoneTransition.OnClientEvent:Connect(function()
	if run then
		stopRun(true)
	end
	modal.Visible = false
end)

player.CharacterRemoving:Connect(function()
	if run then
		stopRun(true)
	end
	modal.Visible = false
end)
