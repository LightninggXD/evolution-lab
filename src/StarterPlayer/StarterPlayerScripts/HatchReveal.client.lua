--[[
	HatchReveal -- the egg shakes, cracks, flashes and hands you the pet (Phase 6.1).

	Hatching was the most repeated purchase in the game and its entire presentation was a small card
	over the player's head. The egg the player had walked to, paid at and was looking straight at did
	not react at all.

	Its own LocalScript rather than more MainUI, for the same reason `EvolveReveal` is one: this is a
	self-contained piece of theatre that needs no HUD state, and MainUI sits near Luau's 200-register
	ceiling. It also means the whole hatch presentation lives in one file -- MainUI's `pet` branch is
	now deliberately silent, the way `creature` and `playerHurt` already are.

	=========================================================================================
	THE THREE THINGS THAT WOULD LEAVE THE WORLD BROKEN
	=========================================================================================
	1. THE EGG IS A REPLICATED OBJECT AND THIS MOVES IT LOCALLY. A client-side CFrame change to a
	   server-owned part is never corrected by the server -- it simply stays wrong on this one
	   screen, forever. So the whole animation is `Model:PivotTo` against a SINGLE saved pivot,
	   restored in a `finally` path that runs even if the sequence errors. One value to put back
	   instead of one per part, which is the difference between a reliable restore and a hopeful one.
	2. TWO HATCHES CAN OVERLAP. Auto Hatch buys twice a second. A second sequence starting while the
	   first is mid-shake would save the ALREADY-SHAKEN pivot as its "original" and restore the egg
	   to a tilt. `busy` keeps one sequence per egg and drops the overlap -- the card still shows, so
	   nothing is lost except a second wobble nobody could have followed anyway.
	3. THE PET RIG IS SCENERY, NOT AN OBJECT. Everything built here goes in a local folder with
	   `CanQuery` and `CanTouch` off, so a rising pet can never become the answer to a combat ray or
	   block the player who is standing right on top of it.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS:WaitForChild("Modules"):WaitForChild("GameConfig"))
local PetModel = require(RS.Modules:WaitForChild("PetModel"))
local UITheme = require(RS.Modules:WaitForChild("UITheme"))
local SoundLibrary = require(RS.Modules:WaitForChild("SoundLibrary"))

local player = Players.LocalPlayer
local Remotes = RS:WaitForChild("Remotes")

-- Local-only scenery, exactly like CombatClient's fxFolder: nothing in here is game state and
-- nothing in here replicates.
local fxFolder = Instance.new("Folder")
fxFolder.Name = "HatchFxLocal"
fxFolder.Parent = workspace

-- HEARTBEAT, NOT RENDERSTEPPED, and this is a bug rather than a preference.
--
-- The three animation loops below originally waited on `RunService.RenderStepped`. On a client that
-- is not rendering -- a Studio session whose viewport has no size, and anything else that stops the
-- render loop -- RenderStepped never fires, so `:Wait()` never returns. The whole sequence then
-- hangs inside its own pcall: no error, no warning, no output, and the egg silently never hatches.
-- It took a print at each step to find, because every outward sign was of a script that had simply
-- decided not to run.
--
-- Heartbeat runs on the simulation step and is independent of rendering. At 60 Hz it is exactly as
-- smooth for this, and it cannot wedge.
local STEP = RunService.Heartbeat

local SHAKE_TIME = 0.75
local CRACK_TIME = 0.18
local RISE_TIME = 0.9
local HOLD_TIME = 1.3
local FIND_RADIUS = 70

local busy = {}

-- ============================================================================
-- FINDING THE EGG
-- ============================================================================
-- The payload does not say which podium was used, and it does not need to: the player is standing
-- at the one they just paid at. Nearest wins, which is the same rule the server's Auto Hatch uses
-- to pick between the three eggs that sit within a few studs of each other on every stall.
local function nearestEgg()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end

	local best, bestDist
	for _, model in ipairs(workspace:GetDescendants()) do
		if model:IsA("Model") and model.Name == "Egg" then
			local ok, pivot = pcall(function()
				return model:GetPivot()
			end)
			if ok then
				local d = (pivot.Position - root.Position).Magnitude
				if d < FIND_RADIUS and (not bestDist or d < bestDist) then
					best, bestDist = model, d
				end
			end
		end
	end
	return best
end

-- ============================================================================
-- THE PIECES
-- ============================================================================
local function burst(position, color, count)
	local att = Instance.new("Attachment")
	att.WorldPosition = position
	att.Parent = workspace.Terrain

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.8
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(14, 26)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = att
	emitter:Emit(count)

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 26
	light.Brightness = 4
	light.Parent = att
	TweenService:Create(light, TweenInfo.new(0.6), { Brightness = 0 }):Play()

	Debris:AddItem(att, 1.6)
end

-- The card, built here rather than borrowed from MainUI: this file owns the whole hatch, and a
-- BillboardGui on a local part is four lines cheaper than reaching across scripts for one.
local function revealCard(position, def, rarity)
	local host = Instance.new("Part")
	host.Size = Vector3.new(1, 1, 1)
	host.Transparency = 1
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.CastShadow = false
	host.CFrame = CFrame.new(position)
	host.Parent = fxFolder

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 230, 0, 74)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = host

	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 1, 0)
	card.BackgroundColor3 = rarity.color
	card.BorderSizePixel = 0
	card.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = UITheme.Color.Outline
	stroke.Parent = card

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -12, 0.56, 0)
	title.Position = UDim2.new(0.5, 0, 0, 4)
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.BackgroundTransparency = 1
	title.Font = UITheme.Font.Display
	title.TextScaled = true
	title.TextColor3 = UITheme.Color.White
	title.TextStrokeColor3 = UITheme.Color.Outline
	title.TextStrokeTransparency = 0
	title.Text = ("%s %s"):format(def.emoji or "", def.name or "")
	title.Parent = card

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, -12, 0.38, 0)
	sub.Position = UDim2.new(0.5, 0, 1, -4)
	sub.AnchorPoint = Vector2.new(0.5, 1)
	sub.BackgroundTransparency = 1
	sub.Font = UITheme.Font.Display
	sub.TextScaled = true
	sub.TextColor3 = UITheme.Color.White
	sub.TextStrokeColor3 = UITheme.Color.Outline
	sub.TextStrokeTransparency = 0
	sub.Text = rarity.name
	sub.Parent = card

	-- rises and fades on its own, so nothing has to remember to take it away
	TweenService:Create(host, TweenInfo.new(HOLD_TIME + 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = host.CFrame + Vector3.new(0, 4, 0),
	}):Play()
	task.delay(HOLD_TIME, function()
		for _, inst in ipairs({ card, title, sub }) do
			if inst:IsA("Frame") then
				TweenService:Create(inst, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
			else
				TweenService:Create(inst, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		end
		TweenService:Create(stroke, TweenInfo.new(0.5), { Transparency = 1 }):Play()
	end)
	Debris:AddItem(host, HOLD_TIME + 0.8)
end

-- ============================================================================
-- THE SEQUENCE
-- ============================================================================
local function play(payload)
	local egg = nearestEgg()
	local def = payload.key and GameConfig.GetPetDef(payload.key)
	local rarity = GameConfig.GetRarity(payload.rarity)
	-- no egg in sight (a hatch from a menu, a player who walked off mid-purchase): the card still
	-- has to appear, so it falls back to the player's own head rather than being skipped
	if not egg then
		local head = player.Character and player.Character:FindFirstChild("Head")
		if head and def then
			revealCard(head.Position + Vector3.new(0, head.Size.Y * 1.8 + 2, 0), def, rarity)
		end
		return
	end
	if busy[egg] then return end
	busy[egg] = true

	local home = egg:GetPivot()
	local shell = egg:FindFirstChild("EggShell")
	local shellColor = shell and shell.Color
	local top = home.Position + Vector3.new(0, 4, 0)

	-- Everything below is wrapped so that a failure anywhere still puts the egg back. An egg left
	-- tilted on one client's screen is invisible to every test and permanent for that player.
	local ok, err = pcall(function()
		-- 1. SHAKE, with the amplitude climbing so it reads as building up rather than as a rattle
		local t0 = os.clock()
		while os.clock() - t0 < SHAKE_TIME do
			local a = (os.clock() - t0) / SHAKE_TIME
			local amp = math.rad(3 + a * 12)
			local wobble = math.sin((os.clock() - t0) * 34)
			egg:PivotTo(home * CFrame.Angles(wobble * amp, 0, wobble * amp * 0.6))
			STEP:Wait()
		end
		egg:PivotTo(home)

		-- 2. CRACK -- a white flash on the shell and a quick shrink, which reads as the shell giving
		if shell then
			shell.Color = Color3.new(1, 1, 1)
		end
		SoundLibrary.Play("hit", nil, { speed = 1.5, volume = 0.35 })
		local t1 = os.clock()
		while os.clock() - t1 < CRACK_TIME do
			local a = (os.clock() - t1) / CRACK_TIME
			egg:PivotTo(home * CFrame.new(0, -a * 0.6, 0))
			STEP:Wait()
		end
		egg:PivotTo(home)
		if shell and shellColor then
			shell.Color = shellColor
		end

		-- 3. RARITY FLASH, in the colour of what was actually rolled -- a Legendary must not slide
		-- past looking like every other hatch
		burst(top, rarity.color, rarity.name == "Legendary" and 90 or 45)
		SoundLibrary.PlayHatch(payload.rarity)

		-- 4. THE PET RISES. Built from the key the server sent, at the tier it sent, so what comes
		-- out of the egg is the actual thing that was added to the inventory.
		if def then
			local model, body, pieces = PetModel.Build(def, payload.tier or "Normal", { scale = 1.5 })
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
					d.Anchored = true
					d.CastShadow = false
				end
			end
			model.Parent = fxFolder

			local t2 = os.clock()
			while os.clock() - t2 < RISE_TIME do
				local a = (os.clock() - t2) / RISE_TIME
				-- eased out, so it leaps clear of the egg and settles rather than drifting up at a
				-- constant speed like a balloon
				local eased = 1 - (1 - a) * (1 - a)
				PetModel.Place(body, pieces,
					CFrame.new(top + Vector3.new(0, eased * 3.2, 0)) * CFrame.Angles(0, a * math.pi * 2, 0))
				STEP:Wait()
			end

			revealCard(top + Vector3.new(0, 5.6, 0), def, rarity)

			-- gentle spin while the card is up, then away
			task.spawn(function()
				local t3 = os.clock()
				while os.clock() - t3 < HOLD_TIME and model.Parent do
					PetModel.Place(body, pieces,
						CFrame.new(top + Vector3.new(0, 3.2 + math.sin((os.clock() - t3) * 3) * 0.25, 0))
							* CFrame.Angles(0, (os.clock() - t3) * 1.6, 0))
					STEP:Wait()
				end
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") then
						TweenService:Create(d, TweenInfo.new(0.4), { Transparency = 1 }):Play()
					end
				end
				Debris:AddItem(model, 0.6)
			end)
		else
			revealCard(top + Vector3.new(0, 3, 0), { emoji = payload.emoji, name = payload.name }, rarity)
		end
	end)

	-- the restore, on every path
	if egg.Parent then
		egg:PivotTo(home)
		if shell and shellColor then
			shell.Color = shellColor
		end
	end
	busy[egg] = nil
	if not ok then
		warn("[HatchReveal] sequence failed: " .. tostring(err))
	end
end

-- ============================================================================
-- x10 IN THE WORLD (Phase 10.4) -- NOW THE FALLBACK ONLY
-- ============================================================================
--
-- 11.19 moved the x10 to the screen (`screenRevealBulk`, at the bottom of this file). Everything
-- below runs only when the screen cannot be had: a reveal is already up, or there is no PlayerGui
-- yet. That is the same relationship `play` has with `screenReveal`. Do not add to the grid here --
-- it is the degraded path, and its cards are unreadable from more than a few studs away by design
-- of BillboardGui itself.
--
-- TEN OF THE SEQUENCE ABOVE IS NOT THE ANSWER. Back to back it is ~35 seconds of theatre for one
-- button press, and run at once they fight over the same egg: `busy` would drop nine of them and the
-- player would watch a single hatch after paying for ten.
--
-- So the batch borrows the parts that read as "something big happened" -- one shake, one burst in
-- the best rarity's colour -- and then replaces the ten reveals with ten small cards that arrive
-- staggered and are readable as a group. One shake, one burst, one row of cards, about four seconds.
--
-- The cards are drawn in a GRID ON ONE BILLBOARD rather than as ten separate ones: ten billboards at
-- a podium overlap into an unreadable pile, and their relative positions would depend on where the
-- player happened to be standing. One host, laid out in GUI space, is stable from every angle.
local BULK_CARD_W, BULK_CARD_H = 74, 46
local BULK_COLS = 5
local BULK_HOLD = 2.6

local function bulkCards(position, pets, best)
	local host = Instance.new("Part")
	host.Size = Vector3.new(1, 1, 1)
	host.Transparency = 1
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.CastShadow = false
	host.CFrame = CFrame.new(position)
	host.Parent = fxFolder

	local rows = math.ceil(#pets / BULK_COLS)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, BULK_CARD_W * BULK_COLS + 16, 0, BULK_CARD_H * rows + 34)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = host

	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, 0, 0, 28)
	header.BackgroundTransparency = 1
	header.Font = UITheme.Font.Display
	header.TextScaled = true
	header.TextColor3 = UITheme.Color.White
	header.TextStrokeColor3 = UITheme.Color.Outline
	header.TextStrokeTransparency = 0
	-- names the best thing in the batch, because that is what the player is actually looking for
	header.Text = best and ("%s  %s!"):format(best.emoji or "", best.name or "") or ("x%d"):format(#pets)
	header.Parent = gui

	local grid = Instance.new("Frame")
	grid.Size = UDim2.new(1, 0, 1, -30)
	grid.Position = UDim2.new(0, 0, 0, 30)
	grid.BackgroundTransparency = 1
	grid.Parent = gui

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0, BULK_CARD_W - 6, 0, BULK_CARD_H - 6)
	layout.CellPadding = UDim2.new(0, 4, 0, 4)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	local frames = {}
	for i, entry in ipairs(pets) do
		local rarity = GameConfig.GetRarity(entry.rarity)
		local cell = Instance.new("Frame")
		cell.LayoutOrder = i
		cell.BackgroundColor3 = rarity.color
		cell.BorderSizePixel = 0
		-- starts invisible; the stagger below is what makes ten cards read as an unfolding result
		-- rather than as a table that was always there
		cell.BackgroundTransparency = 1
		cell.Parent = grid
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 8)
		c.Parent = cell
		local s = Instance.new("UIStroke")
		s.Thickness = 2
		s.Color = UITheme.Color.Outline
		s.Transparency = 1
		s.Parent = cell

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -6, 1, -6)
		label.Position = UDim2.new(0.5, 0, 0.5, 0)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.BackgroundTransparency = 1
		label.Font = UITheme.Font.Display
		label.TextScaled = true
		label.TextColor3 = UITheme.Color.White
		label.TextStrokeColor3 = UITheme.Color.Outline
		label.TextStrokeTransparency = 0
		label.TextTransparency = 1
		label.Text = entry.emoji or "?"
		label.Parent = cell

		frames[i] = { cell = cell, stroke = s, label = label, rarity = rarity }
	end

	task.spawn(function()
		for _, f in ipairs(frames) do
			TweenService:Create(f.cell, TweenInfo.new(0.18), { BackgroundTransparency = 0 }):Play()
			TweenService:Create(f.stroke, TweenInfo.new(0.18), { Transparency = 0 }):Play()
			TweenService:Create(f.label, TweenInfo.new(0.18), { TextTransparency = 0 }):Play()
			-- a Legendary in the batch gets its own small burst as its card lands, so a good pull is
			-- still an event inside a batch rather than one square among ten
			if GameConfig.IsBeaconRarity(f.rarity.name) then
				burst(position, f.rarity.color, 40)
				SoundLibrary.PlayHatch(f.rarity.name)
			end
			task.wait(0.09)
		end
	end)

	TweenService:Create(host, TweenInfo.new(BULK_HOLD + 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = host.CFrame + Vector3.new(0, 3.5, 0),
	}):Play()
	task.delay(BULK_HOLD, function()
		for _, f in ipairs(frames) do
			TweenService:Create(f.cell, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(f.stroke, TweenInfo.new(0.45), { Transparency = 1 }):Play()
			TweenService:Create(f.label, TweenInfo.new(0.45), { TextTransparency = 1 }):Play()
		end
		TweenService:Create(header, TweenInfo.new(0.45), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	Debris:AddItem(host, BULK_HOLD + 0.9)
end

local function playBulk(payload)
	local pets = payload.pets
	if type(pets) ~= "table" or #pets == 0 then return end
	local best = payload.best or pets[1]
	local bestRarity = GameConfig.GetRarity(best.rarity)

	local egg = nearestEgg()
	if not egg then
		local head = player.Character and player.Character:FindFirstChild("Head")
		if head then
			bulkCards(head.Position + Vector3.new(0, head.Size.Y * 1.8 + 3, 0), pets, best)
		end
		return
	end
	if busy[egg] then return end
	busy[egg] = true

	local home = egg:GetPivot()
	local shell = egg:FindFirstChild("EggShell")
	local shellColor = shell and shell.Color
	local top = home.Position + Vector3.new(0, 4, 0)

	local ok, err = pcall(function()
		-- ONE shake for the batch, faster and harder than a single hatch's: ten eggs' worth of
		-- anticipation compressed rather than repeated
		local t0 = os.clock()
		local shakeTime = SHAKE_TIME * 0.8
		while os.clock() - t0 < shakeTime do
			local a = (os.clock() - t0) / shakeTime
			local amp = math.rad(4 + a * 16)
			local wobble = math.sin((os.clock() - t0) * 42)
			egg:PivotTo(home * CFrame.Angles(wobble * amp, 0, wobble * amp * 0.6))
			STEP:Wait()
		end
		egg:PivotTo(home)

		if shell then shell.Color = Color3.new(1, 1, 1) end
		SoundLibrary.Play("hit", nil, { speed = 1.35, volume = 0.4 })
		local t1 = os.clock()
		while os.clock() - t1 < CRACK_TIME do
			local a = (os.clock() - t1) / CRACK_TIME
			egg:PivotTo(home * CFrame.new(0, -a * 0.6, 0))
			STEP:Wait()
		end
		egg:PivotTo(home)
		if shell and shellColor then shell.Color = shellColor end

		-- the burst takes the colour of the BEST pull, so the batch announces its own headline
		burst(top, bestRarity.color, bestRarity.name == "Legendary" and 110 or 60)
		bulkCards(top + Vector3.new(0, 4.2, 0), pets, best)
	end)

	if egg.Parent then
		egg:PivotTo(home)
		if shell and shellColor then shell.Color = shellColor end
	end
	busy[egg] = nil
	if not ok then
		warn("[HatchReveal] bulk sequence failed: " .. tostring(err))
	end
end

-- ============================================================================
-- THE FULL-SCREEN REVEAL (2026-08-11 feedback: "there is no animation at all")
-- ============================================================================
--
-- The world sequence above is still the right thing for a pass buying two eggs a second, but for a
-- hatch the player deliberately paid for it was too small and too far away to register: a 230x74
-- billboard on a podium the camera is not necessarily even pointing at. The owner asked for what
-- the evolve card does -- the egg large on screen, a click, three wiggles, then the pet.
--
-- BORROWED WHOLESALE FROM EvolveReveal, and deliberately so: the dim, the 20-unit blur, the
-- 0.52 x 0.72 stage on SizeConstraint.RelativeYY, the Back-eased pop from 0.2, the ray fan and the
-- long-lens ViewportFrame framed off the model's own bounding box. That file is the house style for
-- "something big happened" and a second, different-looking full-screen reward would read as another
-- game's UI. The numbers that matter are copied, not re-derived -- see the notes there for why each
-- one is what it is (ambient 210, FOV 30, headroom, the RelativeYY constraint).
--
-- THREE THINGS THIS HAS TO GET RIGHT
--   1. ONE AT A TIME. `screenBusy` -- a second reveal opening over the first would leave the first
--      one's cleanup to run against a live second card, which is how the blur gets stranded on.
--   2. THE BLUR AND THE GUI MUST DIE ON EVERY PATH, including an error inside the sequence and a
--      player respawning mid-reveal. Everything is behind one `finish` that is safe to call twice.
--   3. IT MUST NOT WAIT FOR A CLICK FOREVER. A player who opens a menu, walks away, or simply does
--      not realise the egg is clickable would otherwise be left with a blurred screen. There is a
--      hard auto-open timeout, so the click is an invitation and never a requirement.
local screenBusy = false

-- ============================================================================
-- THE SHELL, BUILT ONCE AND SHARED BY BOTH REVEALS
-- ============================================================================
-- A single hatch and a x10 are the same event at two scales, so they are the same shell: the dim,
-- the 20-unit blur, the 0.52 x 0.72 RelativeYY stage, the Back-eased pop from 0.2, the ray fan, the
-- ambient-210 / FOV-30 viewport, the caption pair and the full-screen tap target. This is one
-- function rather than two copies for a reason that is not tidiness: the moment they are two copies,
-- one of them gets a tweak and the game has two different-looking "something big happened" cards.
--
-- IT ALSO OWNS `screenBusy`, AND THAT IS THE FIX 11.19 ASKED FOR. Taking the lock at construction
-- means there is exactly one place that can raise it and exactly one place (`finish`) that can drop
-- it, so a caller cannot forget -- which is precisely how the x10 used to come up over a live single
-- hatch and let the first card's cleanup run against the second card's blur.
--
-- Returns nil when the lock is held or there is no PlayerGui yet, and a caller that gets nil is
-- expected to fall back to the world sequence rather than to skip the hatch.
local SHELL_MAX_LIFE = 16

local function buildScreenShell(color)
	if screenBusy then return nil end
	screenBusy = true

	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		screenBusy = false
		return nil
	end

	local Lighting = game:GetService("Lighting")

	local gui = Instance.new("ScreenGui")
	gui.Name = "HatchReveal"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 90
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	local blur = Instance.new("BlurEffect")
	blur.Size = 0
	blur.Parent = Lighting

	local dim = Instance.new("Frame")
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromRGB(14, 12, 26)
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.ZIndex = 1
	dim.Parent = gui

	local stage = Instance.new("Frame")
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.46)
	stage.Size = UDim2.fromScale(0.52, 0.72)
	stage.SizeConstraint = Enum.SizeConstraint.RelativeYY
	stage.BackgroundTransparency = 1
	stage.ZIndex = 2
	stage.Parent = gui

	local uiScale = Instance.new("UIScale")
	uiScale.Scale = 0.2
	uiScale.Parent = stage

	-- the ray fan, hidden until the shell actually gives -- it is the payoff, not the packaging
	local burstFrame = Instance.new("Frame")
	burstFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	burstFrame.Position = UDim2.fromScale(0.5, 0.46)
	burstFrame.Size = UDim2.fromScale(1, 1)
	burstFrame.BackgroundTransparency = 1
	burstFrame.Visible = false
	burstFrame.ZIndex = 2
	burstFrame.Parent = stage

	for i = 1, 12 do
		local ray = Instance.new("Frame")
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.fromScale(i % 2 == 0 and 1.25 or 0.9, 0.045)
		ray.Rotation = (i - 1) * 30
		ray.BackgroundColor3 = i % 3 == 0 and UITheme.Color.White or color
		ray.BackgroundTransparency = 0.35
		ray.BorderSizePixel = 0
		ray.ZIndex = 2
		ray.Parent = burstFrame
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = ray
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = ray
	end

	local vp = Instance.new("ViewportFrame")
	vp.AnchorPoint = Vector2.new(0.5, 0.5)
	vp.Position = UDim2.fromScale(0.5, 0.44)
	vp.Size = UDim2.fromScale(1, 1)
	vp.BackgroundTransparency = 1
	vp.ZIndex = 3
	-- a ViewportFrame sees none of the place's Lighting; left at the defaults everything in it is
	-- near-black. Same values EvolveReveal settled on -- see the long note there.
	vp.Ambient = Color3.fromRGB(210, 212, 222)
	vp.LightColor = Color3.fromRGB(255, 252, 244)
	vp.LightDirection = Vector3.new(-0.4, -0.7, -1)
	vp.Parent = stage

	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vp
	vp.CurrentCamera = cam

	local caption = Instance.new("TextLabel")
	caption.AnchorPoint = Vector2.new(0.5, 0)
	caption.Position = UDim2.fromScale(0.5, 0.78)
	caption.Size = UDim2.fromScale(1.6, 0.13)
	caption.BackgroundTransparency = 1
	caption.Font = UITheme.Font.Display
	caption.TextScaled = true
	caption.TextColor3 = UITheme.Color.White
	caption.Text = ""
	caption.ZIndex = 4
	caption.Parent = stage
	local capStroke = Instance.new("UIStroke")
	capStroke.Thickness = 4
	capStroke.Color = UITheme.Color.Outline
	capStroke.Parent = caption

	local sub = Instance.new("TextLabel")
	sub.AnchorPoint = Vector2.new(0.5, 0)
	sub.Position = UDim2.fromScale(0.5, 0.91)
	sub.Size = UDim2.fromScale(1.6, 0.1)
	sub.BackgroundTransparency = 1
	sub.Font = UITheme.Font.Display
	sub.TextScaled = true
	sub.TextColor3 = UITheme.Color.Cream
	sub.Text = ""
	sub.ZIndex = 4
	sub.Parent = stage
	local subStroke = Instance.new("UIStroke")
	subStroke.Thickness = 4
	subStroke.Color = UITheme.Color.Outline
	subStroke.Parent = sub

	-- a full-screen invisible button rather than a click on the egg: the egg is drawn inside a
	-- ViewportFrame, which is not an input surface, and asking a player to hit a 3D object through
	-- one is a worse experience than letting them press anywhere
	local hit = Instance.new("TextButton")
	hit.Size = UDim2.fromScale(1, 1)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.ZIndex = 5
	hit.Parent = gui

	local conns = {}

	local shell = {
		gui = gui,
		blur = blur,
		stage = stage,
		burstFrame = burstFrame,
		vp = vp,
		cam = cam,
		caption = caption,
		sub = sub,
		hit = hit,
		done = false,
	}

	-- Every per-frame loop a caller opens is handed back here, so `finish` is the ONE place that has
	-- to remember to disconnect. A RenderStepped handler that outlives its ViewportFrame is a leak
	-- that keeps running for the rest of the session.
	function shell.track(conn)
		table.insert(conns, conn)
		return conn
	end

	-- Safe to call twice, from a click, from a timer, from an error path. `done` is per-shell rather
	-- than a shared flag on purpose: a late timer belonging to a reveal that already closed must not
	-- be able to tear down the reveal that replaced it.
	function shell.finish()
		if shell.done then return end
		shell.done = true
		for _, c in ipairs(conns) do
			if c.Connected then c:Disconnect() end
		end
		TweenService:Create(blur, TweenInfo.new(0.25), { Size = 0 }):Play()
		TweenService:Create(dim, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(uiScale, TweenInfo.new(0.2), { Scale = 0.2 }):Play()
		task.delay(0.3, function()
			gui:Destroy()
			blur:Destroy()
			screenBusy = false
		end)
	end

	function shell.open()
		blur.Enabled = true
		TweenService:Create(blur, TweenInfo.new(0.3), { Size = 20 }):Play()
		TweenService:Create(dim, TweenInfo.new(0.28), { BackgroundTransparency = 0.4 }):Play()
		TweenService:Create(uiScale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }):Play()
		SoundLibrary.Play("click", nil, { volume = 0.4 })
	end

	-- THE LAST LINE OF DEFENCE FOR THE BLUR. Every sequence below already ends on a timer, and the
	-- auto-open below that guarantees the sequence starts -- but both of those live inside code that
	-- can be edited. This one does not depend on any of it: whatever happens, the blur and the lock
	-- are gone by SHELL_MAX_LIFE. A stranded blur is a game the player cannot un-blur without
	-- rejoining, which makes an unconditional deadline worth one line.
	task.delay(SHELL_MAX_LIFE, shell.finish)

	return shell
end

-- An egg is a sphere that is taller than it is wide, and Shape = Ball would silently draw it as a
-- sphere of its SMALLEST axis -- so this is a Block carrying a SpecialMesh, which is the one way to
-- get a non-uniform ellipsoid in Roblox. Same rule the world eggs are built under.
--
-- `scale` exists for the x10, where ten of these share one stage and the hero slot is built larger
-- than the nine around it. It defaults to 1, so the single reveal gets the egg it always had.
local function buildEggFigure(color, scale)
	scale = scale or 1
	local model = Instance.new("Model")
	model.Name = "RevealEgg"

	local body = Instance.new("Part")
	body.Name = "Shell"
	body.Size = Vector3.new(3.1, 4.0, 3.1) * scale
	body.Color = color
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.CFrame = CFrame.new(0, 0, 0)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = body
	body.Parent = model
	model.PrimaryPart = body

	-- two pale bands, so the egg reads as an egg and not as a coloured pill, and so the wiggle has
	-- something on it the eye can track
	for i, y in ipairs({ -0.75, 0.35 }) do
		local band = Instance.new("Part")
		band.Name = "Band" .. i
		band.Size = Vector3.new(3.16, 0.62, 3.16) * scale
		band.Color = color:Lerp(Color3.new(1, 1, 1), 0.55)
		band.Material = Enum.Material.SmoothPlastic
		band.Anchored = true
		band.CanCollide = false
		band.CanQuery = false
		band.CanTouch = false
		band.CFrame = CFrame.new(0, y * scale, 0)
		local bm = Instance.new("SpecialMesh")
		bm.MeshType = Enum.MeshType.Sphere
		bm.Scale = Vector3.new(1, 0.34, 1)
		bm.Parent = band
		band.Parent = model
	end

	return model, body
end

local function screenReveal(payload, def, rarity)
	local color = rarity and rarity.color or UITheme.Color.Gold
	local shell = buildScreenShell(color)
	if not shell then return false end

	local vp, cam = shell.vp, shell.cam
	local burstFrame, caption, sub = shell.burstFrame, shell.caption, shell.sub
	caption.Text = "Tap the egg!"

	local eggModel, eggBody = buildEggFigure(color)
	eggModel.Parent = vp

	local function frameOn(model)
		local cf, size = model:GetBoundingBox()
		local reach = math.max(size.X, size.Y, size.Z)
		local dist = reach / (2 * math.tan(math.rad(cam.FieldOfView / 2))) * 1.95
		return cf.Position, dist, reach
	end

	local focus, dist, reach = frameOn(eggModel)

	local spin = 0
	local wobble = 0
	local conn
	conn = shell.track(RunService.RenderStepped:Connect(function(dt)
		if not vp.Parent then
			conn:Disconnect()
			return
		end
		spin += dt * 0.55
		cam.CFrame = CFrame.lookAt(
			(CFrame.new(focus) * CFrame.Angles(0, spin, 0) * CFrame.new(0, reach * 0.06, dist)).Position,
			focus)
		if burstFrame.Visible then
			burstFrame.Rotation = -spin * 12
		end
		if wobble > 0 and eggBody and eggBody.Parent then
			eggBody.CFrame = CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.sin(os.clock() * 26) * wobble)
		end
	end))

	local finish = shell.finish

	shell.open()

	local opened = false
	local function openEgg()
		if opened or shell.done then return end
		opened = true
		shell.hit.Active = false

		local ok, err = pcall(function()
			-- 1. THREE WIGGLES, counted rather than timed, because "three" is what was asked for and
			-- a duration would drift with frame rate.
			caption.Text = "..."
			for i = 1, 3 do
				wobble = math.rad(9 + i * 3)
				SoundLibrary.Play("hit", nil, { speed = 1.4 + i * 0.15, volume = 0.25 })
				task.wait(0.26)
			end
			wobble = 0
			if eggBody and eggBody.Parent then eggBody.CFrame = CFrame.new(0, 0, 0) end

			-- 2. THE SHELL GIVES: a white flash, then it is gone
			if eggBody then eggBody.Color = Color3.new(1, 1, 1) end
			task.wait(0.12)
			eggModel:Destroy()
			burstFrame.Visible = true
			SoundLibrary.PlayHatch(payload.rarity)

			-- 3. THE PET, framed the same way the egg was
			if def then
				local model, body, pieces = PetModel.Build(def, payload.tier or "Normal", { scale = 1 })
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") then
						d.Anchored = true
						d.CanCollide = false
						d.CanQuery = false
						d.CanTouch = false
						d.CastShadow = false
					elseif d:IsA("BillboardGui") then
						-- PetModel hangs a name/rank plate on every rig it builds. A ViewportFrame does
						-- not render GUIs at all, so this is dead weight either way -- but it also
						-- duplicates the caption below it, which is what showed up as the pet's name
						-- and rarity appearing twice in the reveal's descendants.
						d:Destroy()
					end
				end
				PetModel.Place(body, pieces, CFrame.new(0, 0, 0))
				model.Parent = vp
				focus, dist, reach = frameOn(model)
			end

			caption.Text = (def and def.emoji or payload.emoji or "\u{1F423}") .. " " .. (payload.name or "?")
			caption.TextColor3 = color
			sub.Text = (rarity and rarity.name or "") .. "!"
		end)
		if not ok then
			warn("[HatchReveal] screen reveal failed: " .. tostring(err))
		end

		task.delay(2.4, finish)
	end

	shell.hit.MouseButton1Click:Connect(function()
		if opened then
			finish()   -- a second press dismisses; nobody should have to wait out theatre twice
		else
			openEgg()
		end
	end)

	-- THE CLICK IS AN INVITATION, NEVER A REQUIREMENT. A player who tabs away, opens a menu or
	-- simply does not realise the egg is tappable must not be left staring at a blurred screen.
	task.delay(3.5, function()
		if not shell.done then openEgg() end
	end)

	return true
end

-- ============================================================================
-- THE FULL-SCREEN x10 (Phase 11.19)
-- ============================================================================
--
-- What this replaces: a 74x46 grid of emoji squares on a BillboardGui by the podium. A billboard
-- shrinks with distance no matter how its size is authored -- offset units are not screen pixels and
-- there is no constant-size mode -- so ten cards that measure 74 pixels at point blank are unreadable
-- from anywhere a player actually stands. Ten pets is a screen event, so it moves to the screen, in
-- the SAME shell the single hatch uses. The grid survives below as the fallback only.
--
-- THE LAYOUT IS A WREATH, NOT A GRID, AND THAT IS THE WHOLE DESIGN DECISION.
--   * ONE ViewportFrame, ten egg models in it -- not ten small ViewportFrames. Ten viewports is ten
--     scenes with ten cameras, and worse, it is ten framed thumbnails: the eye reads that as a
--     receipt of what you were given. One scene means one camera move carries all ten together, and
--     the eggs can occlude and part like objects, which is what makes it an event.
--   * NINE ON AN ELLIPSE AROUND ONE IN THE MIDDLE. A 5x2 grid is 1.9 times wider than tall and the
--     stage is 0.72 as wide as it is tall, so a grid frames to a strip across the middle with the
--     eggs at a quarter of the size the ellipse gives them. The ellipse (rx 6.4, ry 8.2) is 0.78
--     wide-to-tall, which is the stage's own shape, so it fills the frame.
--   * THE HERO SLOT IS THE EMPHASIS, and it is structural rather than a second card: the best pull
--     sits dead centre, in front, built 1.25x while the ring is 0.82x, inside the ray fan (which is
--     centred on the same point), and it is the LAST to open. It gets the caption. There is no
--     second full-screen reveal to sit through.
--
-- A ROCK, NOT AN ORBIT. The single hatch spins its camera all the way round because one egg looks
-- the same from every angle. A ring does not: a quarter turn puts it edge-on and stacks ten eggs
-- into a line. So the camera sways +-15 degrees instead -- enough parallax to say "these are
-- objects", never enough to hide one behind another.
local BULK_RX, BULK_RY = 6.4, 8.2
local BULK_HERO_SCALE = 1.25
local BULK_RING_SCALE = 0.82
local BULK_RIPPLE = 0.07
local BULK_SCREEN_HOLD = 3.0
-- ONE sway angle, read by the framing solve AND by the camera loop. It used to be a literal in the
-- loop only, which is what let the two disagree: the frame was fitted to a pose the camera leaves.
local BULK_SWAY = math.rad(15)
-- How much of the half-frame the cluster may fill at its worst moment. 0.9 is a tenth of the frame
-- of daylight on every side, and it replaces the old blind x1.12 fudge on the distance.
local BULK_FILL = 0.9
-- The stage is 0.52 x 0.72 of the viewport HEIGHT -- both axes, because of the RelativeYY
-- constraint -- so the ViewportFrame inside it has this aspect on every screen there is. This is
-- now only the FALLBACK for the frame before layout has run: the solve reads `AbsoluteSize`, the
-- engine's own answer, rather than trusting a second copy of a number the layout owns.
local VP_ASPECT = 0.52 / 0.72

-- Slot 1 is the hero. `f` shrinks the ring when the server delivered fewer than ten (it can: the
-- batch stops when the DNA runs out) so four eggs do not sit on a ten-egg circle.
local function bulkSlots(n)
	local slots = { { cf = CFrame.new(0, 0, 3.4), scale = BULK_HERO_SCALE } }
	local ring = n - 1
	if ring > 0 then
		local f = math.clamp(ring / 9, 0.7, 1)
		for i = 1, ring do
			local a = math.pi / 2 + (i - 1) * (math.pi * 2 / ring)
			slots[i + 1] = {
				cf = CFrame.new(math.cos(a) * BULK_RX * f, math.sin(a) * BULK_RY * f, -1.6),
				scale = BULK_RING_SCALE,
			}
		end
	end
	return slots
end

-- `GetBoundingBox` is a Model method and a BasePart does not have one; a loose part in the cluster
-- carries its own box already.
local function boxOf(inst)
	if inst:IsA("Model") then return inst:GetBoundingBox() end
	if inst:IsA("BasePart") then return inst.CFrame, inst.Size end
	return nil
end

-- SOLVED AGAINST THE ROCKED EXTREMES, not the rest pose -- which is the whole bug this replaces.
-- The camera does not sit still: it yaws +-BULK_SWAY about the focus, and a yaw does two things to
-- a ring 15.2 studs wide and 8.3 deep at once. It WIDENS the silhouette (16.8 studs at 15 degrees),
-- and it swings the near side of that silhouette toward the lens, so the outermost eggs are both
-- bigger on screen and closer to it than they are at rest. Fitting the bounding box at rest and
-- adding half the depth -- what this did -- fits a pose the camera is in twice per cycle, and the
-- ring swings out of the frame it was fitted to for the rest of it.
--
-- It is a PROJECTION, not a formula. Every corner of every figure, at nine yaw samples across the
-- sway, answers "how far back must the camera be for ME to land inside BULK_FILL of the half
-- frame", and the distance is the largest of those answers. Nothing has to be re-derived when the
-- ellipse, the sway, the egg size or the slot count moves -- which a closed form does, silently.
-- Per FIGURE rather than per cluster, because the corners of the cluster's box are empty air (the
-- layout is an ellipse) and fitting them costs 9% of the size of every egg for nothing.
--
-- FieldOfView is the VERTICAL angle, so the horizontal half-angle is scaled by the viewport's own
-- width/height -- read off `AbsoluteSize`, not off VP_ASPECT, so the frame the eggs are fitted to
-- cannot drift from the frame they are drawn in. AbsoluteSize is 0 until layout has run, which is
-- what the fallback and the one re-solve below it are for.
local function frameCluster(model, cam, vp)
	local cf, csize0 = model:GetBoundingBox()
	local focus = cf.Position
	local aspect = VP_ASPECT
	if vp then
		local abs = vp.AbsoluteSize
		if abs.X > 0 and abs.Y > 0 then aspect = abs.X / abs.Y end
	end
	local halfTan = math.tan(math.rad(cam.FieldOfView / 2))
	local limitX = halfTan * aspect * BULK_FILL
	local limitY = halfTan * BULK_FILL

	local corners = {}
	for _, child in ipairs(model:GetChildren()) do
		local ccf, csize = boxOf(child)
		if ccf then
			for _, sx in ipairs({ -0.5, 0.5 }) do
				for _, sy in ipairs({ -0.5, 0.5 }) do
					for _, sz in ipairs({ -0.5, 0.5 }) do
						local p = ccf * Vector3.new(csize.X * sx, csize.Y * sy, csize.Z * sz)
						table.insert(corners, p - focus)
					end
				end
			end
		end
	end
	-- nothing enumerable in there: fall back to the cluster's own box, which is the looser fit this
	-- replaced rather than an invented number
	if #corners == 0 then
		for _, sx in ipairs({ -0.5, 0.5 }) do
			for _, sy in ipairs({ -0.5, 0.5 }) do
				for _, sz in ipairs({ -0.5, 0.5 }) do
					table.insert(corners,
						Vector3.new(csize0.X * sx, csize0.Y * sy, csize0.Z * sz))
				end
			end
		end
	end

	local dist = 0
	for step = 0, 8 do
		local yaw = -BULK_SWAY + (BULK_SWAY * 2) * (step / 8)
		local s, c = math.sin(yaw), math.cos(yaw)
		for _, v in ipairs(corners) do
			-- the corner in the camera's own axes at this yaw. `depth` is how much NEARER the lens
			-- than the focus it sits, so it is added to the distance the corner's spread demands.
			local across = v.X * c - v.Z * s
			local depth = v.X * s + v.Z * c
			local need = math.max(math.abs(across) / limitX, math.abs(v.Y) / limitY) + depth
			if need > dist then dist = need end
		end
	end
	-- a zero distance would put the camera on its own focus point and hand CFrame.lookAt two
	-- identical vectors, which is a NaN CFrame and a blank stage
	return focus, math.max(dist, 1)
end

local function screenRevealBulk(payload)
	local pets = payload.pets
	if type(pets) ~= "table" or #pets == 0 then return false end

	-- `payload.best` ARRIVES AS A COPY, not as one of the entries in `pets`. The server sets
	-- `best = rolled[k]` -- the same table twice -- but a RemoteEvent does not preserve a shared
	-- reference across a payload, it serialises it twice. So the hero is found by value; matching by
	-- identity would silently never match and hand the wreath eleven pets for ten eggs.
	local best = payload.best
	local heroIndex = 1
	if type(best) == "table" then
		for i, e in ipairs(pets) do
			if e.key == best.key and e.rarity == best.rarity then
				heroIndex = i
				break
			end
		end
	end
	best = pets[heroIndex]
	local bestRarity = GameConfig.GetRarity(best.rarity)

	local shell = buildScreenShell(bestRarity.color)
	if not shell then return false end

	-- hero first, then the rest in the order they were rolled
	local order = { best }
	for i, e in ipairs(pets) do
		if i ~= heroIndex then table.insert(order, e) end
	end

	local vp, cam = shell.vp, shell.cam
	local slots = bulkSlots(#order)

	-- One Model holding all ten, so the framing below can be taken from a real bounding box rather
	-- than from the radii it was written against -- move the ellipse and the camera follows.
	local cluster = Instance.new("Model")
	cluster.Name = "BulkEggs"

	local eggs = {}
	for i, entry in ipairs(order) do
		local slot = slots[i]
		local rarity = GameConfig.GetRarity(entry.rarity)
		local model = buildEggFigure(rarity.color, slot.scale)
		-- the probe hook: ten of these is the row's "10 figures drawn", and an attribute is
		-- countable from outside without depending on what anything was named
		model:SetAttribute("BulkSlot", i)
		model:PivotTo(slot.cf)
		model.Parent = cluster
		eggs[i] = { model = model, slot = slot, entry = entry, rarity = rarity }
	end
	cluster.Parent = vp

	-- Solved twice, and only twice: once now off the fallback aspect, and once on the first frame
	-- the ViewportFrame has an AbsoluteSize to report. It is NOT re-solved after that -- the eggs
	-- are destroyed one at a time during the ripple, so a later solve would reframe on whatever is
	-- left standing and walk the camera in as the ring empties.
	local focus, dist = frameCluster(cluster, cam, vp)
	local measured = vp.AbsoluteSize.Y > 0

	shell.caption.Text = ("Tap to open all %d!"):format(#order)

	local t0 = os.clock()
	local wobble = 0
	local conn
	conn = shell.track(RunService.RenderStepped:Connect(function()
		if not vp.Parent then
			conn:Disconnect()
			return
		end
		local t = os.clock() - t0
		if not measured and vp.AbsoluteSize.Y > 0 then
			measured = true
			focus, dist = frameCluster(cluster, cam, vp)
		end
		cam.CFrame = CFrame.lookAt(
			(CFrame.new(focus) * CFrame.Angles(0, math.sin(t * 0.55) * BULK_SWAY, 0)
				* CFrame.new(0, 0, dist)).Position,
			focus)
		if shell.burstFrame.Visible then
			shell.burstFrame.Rotation = -t * 9
		end
		if wobble > 0 then
			-- PivotTo, not a write to the shell part: the two bands are separate anchored parts, so
			-- rotating only the body would tilt the egg inside its own stripes. A small per-egg phase
			-- offset keeps ten identical wobbles from reading as one mechanical object.
			for i, egg in ipairs(eggs) do
				if egg.model.Parent then
					egg.model:PivotTo(egg.slot.cf * CFrame.Angles(0, 0, math.sin(t * 26 + i * 0.35) * wobble))
				end
			end
		end
	end))

	shell.open()

	local opened = false
	local function openAll()
		if opened or shell.done then return end
		opened = true
		shell.hit.Active = false

		local ok, err = pcall(function()
			-- 1. ALL TEN SHAKE AT ONCE -- three builds, the same count and rhythm as one egg, because
			-- this is the same event and not a different one.
			shell.caption.Text = "..."
			for i = 1, 3 do
				if shell.done then return end
				wobble = math.rad(7 + i * 3)
				SoundLibrary.Play("hit", nil, { speed = 1.3 + i * 0.15, volume = 0.3 })
				task.wait(0.26)
			end
			wobble = 0
			for _, egg in ipairs(eggs) do
				if egg.model.Parent then egg.model:PivotTo(egg.slot.cf) end
			end
			task.wait(0.1)

			-- 2. THE RIPPLE. Ten shells giving in one frame is a single flash nobody can read; 70ms
			-- apart is still "at once" to the eye but it sweeps the ring, and the HERO IS LAST so the
			-- batch lands on its headline instead of opening with it and then listing nine also-rans.
			shell.burstFrame.Visible = true
			local openOrder = {}
			for i = 2, #eggs do table.insert(openOrder, i) end
			table.insert(openOrder, 1)

			for step, i in ipairs(openOrder) do
				-- A SECOND TAP CAN LAND MID-RIPPLE and `finish` destroys the ScreenGui 0.3s later.
				-- Destroy() locks the Parent property of everything under it, so the next
				-- `model.Parent = vp` would throw -- caught by the pcall, but as a warning per pet.
				if shell.done then return end
				local egg = eggs[i]
				egg.model:Destroy()

				-- Built one per ripple step rather than ten up front, and that is not a nicety: ten
				-- PetModel.Build calls in one frame is ~200 parts created between two renders, which
				-- is a visible hitch at exactly the moment the player is looking. Spread over the
				-- ripple it costs nothing.
				local def = egg.entry.key and GameConfig.GetPetDef(egg.entry.key)
				if def then
					local model, body, pieces = PetModel.Build(def, egg.entry.tier or "Normal",
						{ scale = egg.slot.scale })
					for _, d in ipairs(model:GetDescendants()) do
						if d:IsA("BasePart") then
							d.Anchored = true
							d.CanCollide = false
							d.CanQuery = false
							d.CanTouch = false
							d.CastShadow = false
						elseif d:IsA("BillboardGui") then
							-- a ViewportFrame renders no GUIs at all; the nameplate is dead weight here
							d:Destroy()
						end
					end
					model:SetAttribute("BulkSlot", i)
					-- TURNED AROUND AND DROPPED. A rig's root is its BODY and its face is on -Z, while
					-- the camera sits on +Z looking back -- placed at the slot unrotated, every pet
					-- would show the player its tail. The drop is because the root is not the rig's
					-- centre either: the head is a stud and a half above it, so a pet placed at the
					-- egg's middle stands with its feet where the egg's middle was.
					PetModel.Place(body, pieces,
						egg.slot.cf * CFrame.new(0, -0.65 * egg.slot.scale, 0) * CFrame.Angles(0, math.pi, 0))
					model.Parent = vp
				end

				SoundLibrary.Play("hit", nil, { speed = 1.15 + step * 0.06, volume = 0.14 })
				-- the hero and any beacon-rarity pull get the real hatch sting on top of the tick, so
				-- a good roll is still an event inside a batch rather than one square among ten
				if i == 1 or GameConfig.IsBeaconRarity(egg.rarity.name) then
					SoundLibrary.PlayHatch(egg.rarity.name)
				end
				task.wait(BULK_RIPPLE)
			end

			shell.caption.Text = (best.emoji or "\u{1F423}") .. " " .. (best.name or "?")
			shell.caption.TextColor3 = bestRarity.color
			shell.sub.Text = ("%s  -  %d hatched"):format(bestRarity.name, #order)
		end)
		if not ok then
			warn("[HatchReveal] bulk screen reveal failed: " .. tostring(err))
		end

		-- handed back only now, so a double tap on the way in cannot dismiss the ripple it started
		shell.hit.Active = true
		task.delay(BULK_SCREEN_HOLD, shell.finish)
	end

	shell.hit.MouseButton1Click:Connect(function()
		if opened then
			shell.finish()
		else
			openAll()
		end
	end)

	-- the same invitation, never a requirement -- see the note on the single reveal's timeout
	task.delay(3.5, function()
		if not shell.done then openAll() end
	end)

	return true
end

Remotes:WaitForChild("Notify").OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	if payload.kind == "pet" then
		-- A HATCH THE PLAYER ASKED FOR GETS THE SCREEN; one Auto Hatch bought for them does not.
		-- `payload.auto` is stamped by PetService.HandleBuyEgg -- see the note on its signature.
		-- The world sequence is the fallback on both counts: if a reveal is already up (screenBusy)
		-- or this was automatic, the egg still shakes on its podium the way it always did.
		if not payload.auto and screenReveal(payload, payload.key and GameConfig.GetPetDef(payload.key),
			GameConfig.GetRarity(payload.rarity)) then
			return
		end
		task.spawn(play, payload)
	elseif payload.kind == "petBulk" then
		-- THE SAME RULE, AND THIS IS THE 11.19 FIX. `playBulk` never consulted `screenBusy`: a batch
		-- landing while a single reveal was up ran its own theatre alongside it, and whichever
		-- finished first tore down a blur the other one was still using. It now goes through the same
		-- lock as the single hatch, and when it cannot get the lock the world sequence -- one shake,
		-- one burst, the billboard grid -- is the fallback, exactly as `play` is for a single.
		-- (`payload.auto` is never set on a batch today: a x10 is always a button somebody pressed.
		-- It is checked anyway so that an automated batch would degrade the same way an Auto Hatch
		-- does rather than seizing the screen.)
		if not payload.auto and screenRevealBulk(payload) then
			return
		end
		task.spawn(playBulk, payload)
	end
end)
