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

Remotes:WaitForChild("Notify").OnClientEvent:Connect(function(payload)
	if type(payload) == "table" and payload.kind == "pet" then
		task.spawn(play, payload)
	end
end)
