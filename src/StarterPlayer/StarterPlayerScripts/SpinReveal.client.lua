--[[
	SpinReveal -- modern animated Lucky Wheel reveal theatre (Phase 5.6 + Phase 18.23).

	Inspired by high-production Roblox hits (Blade Ball, Pet Simulator 99, Sol's RNG):
	  - Dynamic physical ratchet flapper/pointer that deflects and springs on every tick
	  - 24-bulb animated LED carnival chaser rim with high-speed strobe and victory pulses
	  - Dual counter-rotating sunburst celebration rays
	  - Smooth anticipation windup, cubic deceleration with rising pitch clicks, and spring settle
	  - Bouncy victory pod scaling with golden halo and tiered fanfare sounds
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local RS = game:GetService("ReplicatedStorage")

local Modules = RS:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local UITheme = require(Modules:WaitForChild("UITheme"))
local UIKit = require(Modules:WaitForChild("UIKit"))
local CardKit = require(Modules:WaitForChild("HUD"):WaitForChild("CardKit"))
local IconLibrary = require(Modules:WaitForChild("IconLibrary"))
local SoundLibrary = require(Modules:WaitForChild("SoundLibrary"))

local player = Players.LocalPlayer
local Remotes = RS:WaitForChild("Remotes")

local STEP = RunService.Heartbeat

-- ============================================================================
-- THE NUMBERS
-- ============================================================================
local SPIN_TIME = 4.6
local WINDUP_TIME = 0.35
local WINDUP_DEG = 16
local SETTLE_TIME = 0.32
local SETTLE_DEG = 3.8
local TURNS = 5
local SPIN_POWER = 3.0
local JITTER_ARC = 0.32

local BIG_WINS = {
	jackpot = true, vault = true, relic = true, pet = true, dna_flood = true,
}

local SHELL_MAX_LIFE = math.max(24, (GameConfig.SpinMaxChain or 12) * 5.6)
local MAX_QUEUE = 3

local INK = CardKit.INK
local WHITE = Color3.fromRGB(255, 255, 255)
local GOLD = Color3.fromRGB(255, 226, 120)
local formatNumber = UIKit.formatNumber

-- ============================================================================
-- HELPERS
-- ============================================================================
local function iconInto(parent, emoji, size, position, zIndex)
	local id = IconLibrary.Resolve(emoji)
	if id then
		local img = Instance.new("ImageLabel")
		img.Name = "Icon"
		img.BackgroundTransparency = 1
		img.Image = id
		img.ScaleType = Enum.ScaleType.Fit
		img.Size = size
		img.Position = position
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.ZIndex = zIndex
		img.Parent = parent
		return img
	end
	local lbl = Instance.new("TextLabel")
	lbl.Name = "Glyph"
	lbl.BackgroundTransparency = 1
	lbl.Text = emoji or ""
	lbl.Font = UITheme.Font.Display
	lbl.TextScaled = true
	lbl.TextColor3 = WHITE
	lbl.Size = size
	lbl.Position = position
	lbl.AnchorPoint = Vector2.new(0.5, 0.5)
	lbl.ZIndex = zIndex
	lbl.Parent = parent
	return lbl
end

local function detailText(spin)
	local d = spin.detail
	if type(d) ~= "table" then return "" end
	local bits = {}
	if d.dna then table.insert(bits, ("+%s DNA"):format(formatNumber(d.dna))) end
	if d.diamonds then table.insert(bits, ("+%d 💎"):format(d.diamonds)) end
	if d.shards then table.insert(bits, ("+%d 🌟"):format(d.shards)) end
	if d.potion then table.insert(bits, ("%dx %s"):format(d.potions or 1, d.potion)) end
	if d.relicChests then
		table.insert(bits, ("%d Relic Chest -- open it in the Forge"):format(d.relicChests))
	end
	if d.petName then
		table.insert(bits, ("%s %s%s"):format(d.petEmoji or "🐾", d.petName,
			d.petRarity and (" (" .. d.petRarity .. ")") or ""))
	end
	if d.substituted then table.insert(bits, "(" .. d.substituted .. ")") end
	return table.concat(bits, "   ")
end

-- ============================================================================
-- THE SHELL
-- ============================================================================
local busy = false

local function buildShell()
	if busy then return nil end
	busy = true

	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		busy = false
		return nil
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "SpinReveal"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 95
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	local blur = Instance.new("BlurEffect")
	blur.Size = 0
	blur.Parent = Lighting

	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromRGB(10, 8, 22)
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.ZIndex = 1
	dim.Parent = gui

	local root = Instance.new("Frame")
	root.Name = "Stage"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.47)
	root.Size = UDim2.fromScale(0.70, 0.70)
	root.SizeConstraint = Enum.SizeConstraint.RelativeYY
	root.BackgroundTransparency = 1
	root.ZIndex = 2
	root.Parent = gui

	local uiScale = Instance.new("UIScale")
	uiScale.Scale = 0.2
	uiScale.Parent = root

	local conns = {}
	local shell = {
		gui = gui, blur = blur, dim = dim, root = root, uiScale = uiScale, done = false,
	}

	function shell.track(conn)
		table.insert(conns, conn)
		return conn
	end

	function shell.finish()
		if shell.done then return end
		shell.done = true
		for _, c in ipairs(conns) do
			if c.Connected then c:Disconnect() end
		end
		TweenService:Create(blur, TweenInfo.new(0.25), { Size = 0 }):Play()
		TweenService:Create(dim, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(uiScale, TweenInfo.new(0.22), { Scale = 0.2 }):Play()
		task.delay(0.3, function()
			gui:Destroy()
			blur:Destroy()
			busy = false
		end)
	end

	function shell.open()
		blur.Enabled = true
		TweenService:Create(blur, TweenInfo.new(0.3), { Size = 20 }):Play()
		TweenService:Create(dim, TweenInfo.new(0.28), { BackgroundTransparency = 0.30 }):Play()
		TweenService:Create(uiScale, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }):Play()
		SoundLibrary.PlayLocal("open", { volume = 0.45 })
	end

	task.delay(SHELL_MAX_LIFE, shell.finish)
	return shell
end

-- ============================================================================
-- DRAWING THE WHEEL WITH LED CHASER RIM
-- ============================================================================
local function buildWheel(root)
	-- Outer decorative golden bezel with LED bulbs
	local outerBezel = Instance.new("Frame")
	outerBezel.Name = "OuterBezel"
	outerBezel.AnchorPoint = Vector2.new(0.5, 0.5)
	outerBezel.Position = UDim2.fromScale(0.5, 0.5)
	outerBezel.Size = UDim2.fromScale(0.96, 0.96)
	outerBezel.BackgroundColor3 = Color3.fromRGB(245, 180, 50)
	outerBezel.BorderSizePixel = 0
	outerBezel.ZIndex = 2
	outerBezel.Parent = root
	CardKit.Corner(outerBezel, 9999)
	CardKit.Gradient(outerBezel, { Color3.fromRGB(255, 235, 120), Color3.fromRGB(200, 130, 20) }, 90)
	CardKit.Stroke(outerBezel, INK, 6)

	-- 24 LED Light bulbs around the rim for dynamic chasing effects
	local bulbs = {}
	local NUM_BULBS = 24
	for b = 1, NUM_BULBS do
		local bulbPeg = Instance.new("Frame")
		bulbPeg.Name = "BulbPeg" .. b
		bulbPeg.AnchorPoint = Vector2.new(0.5, 1)
		bulbPeg.Position = UDim2.fromScale(0.5, 0.5)
		bulbPeg.Size = UDim2.fromScale(0.032, 0.492)
		bulbPeg.Rotation = (b - 1) * (360 / NUM_BULBS)
		bulbPeg.BackgroundTransparency = 1
		bulbPeg.ZIndex = 3
		bulbPeg.Parent = outerBezel

		local bulb = Instance.new("Frame")
		bulb.Name = "Bulb"
		bulb.AnchorPoint = Vector2.new(0.5, 0)
		bulb.Position = UDim2.fromScale(0.5, 0.008)
		bulb.Size = UDim2.fromScale(1, 0.065)
		bulb.BackgroundColor3 = Color3.fromRGB(255, 240, 160)
		bulb.BorderSizePixel = 0
		bulb.ZIndex = 4
		bulb.Parent = bulbPeg
		CardKit.Corner(bulb, 9999)
		local bulbStroke = Instance.new("UIStroke")
		bulbStroke.Color = Color3.fromRGB(120, 80, 10)
		bulbStroke.Thickness = 1.5
		bulbStroke.Parent = bulb

		bulbs[b] = bulb
	end

	-- The rotating wheel disc inside
	local wheel = Instance.new("Frame")
	wheel.Name = "Wheel"
	wheel.AnchorPoint = Vector2.new(0.5, 0.5)
	wheel.Position = UDim2.fromScale(0.5, 0.5)
	wheel.Size = UDim2.fromScale(0.88, 0.88)
	wheel.BackgroundColor3 = Color3.fromRGB(38, 34, 66)
	wheel.BorderSizePixel = 0
	wheel.ZIndex = 4
	wheel.Parent = root
	CardKit.Corner(wheel, 9999)
	CardKit.Gradient(wheel, { Color3.fromRGB(58, 52, 92), Color3.fromRGB(26, 22, 48) }, 90)
	CardKit.Stroke(wheel, INK, 5)

	local segments = GameConfig.SpinWheel
	local n = #segments
	local arc = 360 / n
	local pods = {}

	for i, seg in ipairs(segments) do
		local theta = (i - 1) * arc

		local pod = Instance.new("Frame")
		pod.Name = "Pod" .. i
		pod.AnchorPoint = Vector2.new(0.5, 1)
		pod.Position = UDim2.fromScale(0.5, 0.5)
		pod.Size = UDim2.fromScale(0.165, 0.425)
		pod.Rotation = theta
		pod.BackgroundColor3 = WHITE
		pod.BorderSizePixel = 0
		pod.ZIndex = 5
		pod.Parent = wheel

		local colors = seg.colors or { Color3.fromRGB(170, 170, 190), Color3.fromRGB(120, 120, 140) }
		CardKit.Corner(pod, 16)
		CardKit.Gradient(pod, colors, 90)
		CardKit.Stroke(pod, INK, 4)
		CardKit.Studs(pod, 18, 0.88, 16, 5)

		iconInto(pod, seg.emoji, UDim2.fromScale(0.80, 0.32), UDim2.fromScale(0.5, 0.22), 6)

		local label = CardKit.Text(pod, {
			name = "Short",
			text = seg.short or seg.name or "",
			size = UDim2.fromScale(1.05, 0.14),
			position = UDim2.fromScale(0.5, 0.42),
			textSize = 15,
			xAlign = "Center",
			zIndex = 6,
			strokeThickness = 2.5,
			truncate = false,
		})
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.TextWrapped = true

		pods[i] = pod
	end

	-- Boundary pegs between pods
	for i = 1, n do
		local peg = Instance.new("Frame")
		peg.Name = "Peg" .. i
		peg.AnchorPoint = Vector2.new(0.5, 1)
		peg.Position = UDim2.fromScale(0.5, 0.5)
		peg.Size = UDim2.fromScale(0.028, 0.485)
		peg.Rotation = (i - 0.5) * arc
		peg.BackgroundTransparency = 1
		peg.ZIndex = 7
		peg.Parent = wheel

		local dot = Instance.new("Frame")
		dot.Name = "Dot"
		dot.AnchorPoint = Vector2.new(0.5, 0)
		dot.Position = UDim2.fromScale(0.5, 0)
		dot.Size = UDim2.fromScale(1, 0.055)
		dot.BackgroundColor3 = Color3.fromRGB(255, 235, 130)
		dot.BorderSizePixel = 0
		dot.ZIndex = 7
		dot.Parent = peg
		CardKit.Corner(dot, 9999)
		CardKit.Stroke(dot, INK, 2)
	end

	return wheel, pods, arc, bulbs
end

-- ============================================================================
-- THE FURNITURE & BOUNCING RATCHET POINTER
-- ============================================================================
local function buildFurniture(root)
	-- Center shiny hub
	local hub = Instance.new("Frame")
	hub.Name = "Hub"
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.Position = UDim2.fromScale(0.5, 0.5)
	hub.Size = UDim2.fromScale(0.245, 0.245)
	hub.BackgroundColor3 = WHITE
	hub.BorderSizePixel = 0
	hub.ZIndex = 9
	hub.Parent = root
	CardKit.Corner(hub, 9999)
	CardKit.Gradient(hub, { Color3.fromRGB(255, 240, 160), Color3.fromRGB(240, 150, 30) }, 90)
	CardKit.Stroke(hub, INK, 5)
	CardKit.Studs(hub, 16, 0.82, 9999, 9)
	iconInto(hub, "\u{1F3A1}", UDim2.fromScale(0.68, 0.68), UDim2.fromScale(0.5, 0.5), 10)

	-- Physical Animated Pointer (Ratchet Flapper)
	local pointer = Instance.new("Frame")
	pointer.Name = "Pointer"
	pointer.AnchorPoint = Vector2.new(0.5, 0.15)
	pointer.Position = UDim2.fromScale(0.5, 0.045)
	pointer.Size = UDim2.fromScale(0.11, 0.125)
	pointer.BackgroundTransparency = 1
	pointer.ZIndex = 11
	pointer.Parent = root

	local stem = Instance.new("Frame")
	stem.Name = "Stem"
	stem.AnchorPoint = Vector2.new(0.5, 0)
	stem.Position = UDim2.fromScale(0.5, 0)
	stem.Size = UDim2.fromScale(0.65, 0.65)
	stem.BackgroundColor3 = Color3.fromRGB(255, 80, 95)
	stem.BorderSizePixel = 0
	stem.ZIndex = 11
	stem.Parent = pointer
	CardKit.Corner(stem, 8)
	CardKit.Gradient(stem, { Color3.fromRGB(255, 120, 130), Color3.fromRGB(230, 40, 60) }, 90)
	CardKit.Stroke(stem, INK, 4)

	local tip = Instance.new("Frame")
	tip.Name = "Tip"
	tip.AnchorPoint = Vector2.new(0.5, 0.5)
	tip.Position = UDim2.fromScale(0.5, 0.74)
	tip.Size = UDim2.fromScale(0.58, 0.58)
	tip.Rotation = 45
	tip.BackgroundColor3 = Color3.fromRGB(255, 80, 95)
	tip.BorderSizePixel = 0
	tip.ZIndex = 11
	tip.Parent = pointer
	CardKit.Corner(tip, 4)
	CardKit.Gradient(tip, { Color3.fromRGB(255, 120, 130), Color3.fromRGB(230, 40, 60) }, 90)
	CardKit.Stroke(tip, INK, 4)

	-- Pointer pivot pin
	local pin = Instance.new("Frame")
	pin.AnchorPoint = Vector2.new(0.5, 0.5)
	pin.Position = UDim2.fromScale(0.5, 0.18)
	pin.Size = UDim2.fromScale(0.24, 0.24)
	pin.BackgroundColor3 = Color3.fromRGB(255, 230, 120)
	pin.BorderSizePixel = 0
	pin.ZIndex = 12
	pin.Parent = pointer
	CardKit.Corner(pin, 9999)
	CardKit.Stroke(pin, INK, 2)

	return hub, pointer
end

-- ============================================================================
-- DUAL ROTATING SUNBURST CELEBRATION RAYS
-- ============================================================================
local function buildBurst(root)
	local burst = Instance.new("Frame")
	burst.Name = "Burst"
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Position = UDim2.fromScale(0.5, 0.5)
	burst.Size = UDim2.fromScale(1.60, 1.60)
	burst.BackgroundTransparency = 1
	burst.Visible = false
	burst.ZIndex = 1
	burst.Parent = root

	-- Inner golden starburst
	local inner = Instance.new("Frame")
	inner.Name = "InnerRays"
	inner.Size = UDim2.fromScale(1, 1)
	inner.BackgroundTransparency = 1
	inner.ZIndex = 1
	inner.Parent = burst

	for i = 1, 16 do
		local ray = Instance.new("Frame")
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.fromScale(i % 2 == 0 and 1.35 or 1.05, 0.045)
		ray.Rotation = (i - 1) * (360 / 16)
		ray.BackgroundColor3 = GOLD
		ray.BackgroundTransparency = 0.35
		ray.BorderSizePixel = 0
		ray.ZIndex = 1
		ray.Parent = inner
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = ray
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = ray
	end

	-- Outer pastel aura rays
	local outer = Instance.new("Frame")
	outer.Name = "OuterRays"
	outer.Size = UDim2.fromScale(1.15, 1.15)
	outer.AnchorPoint = Vector2.new(0.5, 0.5)
	outer.Position = UDim2.fromScale(0.5, 0.5)
	outer.BackgroundTransparency = 1
	outer.ZIndex = 1
	outer.Parent = burst

	for i = 1, 12 do
		local ray = Instance.new("Frame")
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.fromScale(1.20, 0.06)
		ray.Rotation = (i - 1) * 30 + 15
		ray.BackgroundColor3 = Color3.fromRGB(150, 230, 255)
		ray.BackgroundTransparency = 0.55
		ray.BorderSizePixel = 0
		ray.ZIndex = 1
		ray.Parent = outer
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = ray
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = ray
	end

	return burst
end

local function buildCaption(gui)
	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.AnchorPoint = Vector2.new(0.5, 0.5)
	caption.Position = UDim2.fromScale(0.5, 0.890)
	caption.Size = UDim2.fromScale(0.75, 0.088)
	caption.BackgroundTransparency = 1
	caption.Font = UITheme.Font.Display
	caption.TextScaled = true
	caption.TextColor3 = WHITE
	caption.Text = ""
	caption.ZIndex = 12
	caption.Parent = gui
	local capStroke = Instance.new("UIStroke")
	capStroke.Thickness = 4.5
	capStroke.Color = UITheme.Color.Outline
	capStroke.Parent = caption

	local sub = Instance.new("TextLabel")
	sub.Name = "Detail"
	sub.AnchorPoint = Vector2.new(0.5, 0.5)
	sub.Position = UDim2.fromScale(0.5, 0.960)
	sub.Size = UDim2.fromScale(0.75, 0.048)
	sub.BackgroundTransparency = 1
	sub.Font = UITheme.Font.Display
	sub.TextScaled = true
	sub.TextColor3 = UITheme.Color.Cream
	sub.Text = ""
	sub.ZIndex = 12
	sub.Parent = gui
	local subStroke = Instance.new("UIStroke")
	subStroke.Thickness = 3.5
	subStroke.Color = UITheme.Color.Outline
	subStroke.Parent = sub

	return caption, sub
end

-- ============================================================================
-- THE ANIMATED SPIN SEQUENCE WITH SPRING POINTER & LED CHASE
-- ============================================================================
local function wobblePointer(pointer, intensity)
	intensity = intensity or 1
	pointer.Rotation = -18 * intensity
	TweenService:Create(pointer,
		TweenInfo.new(0.12, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
		{ Rotation = 0 }):Play()
end

local function updateLEDs(bulbs, rot, isPulsing)
	local n = #bulbs
	if isPulsing then
		local pulseColor = (math.floor(os.clock() * 10) % 2 == 0) and WHITE or GOLD
		for _, b in ipairs(bulbs) do
			b.BackgroundColor3 = pulseColor
		end
		return
	end

	local lead = math.floor(math.abs(rot) / (360 / n)) % n + 1
	for i, b in ipairs(bulbs) do
		local dist = (i - lead) % n
		if dist == 0 then
			b.BackgroundColor3 = WHITE
		elseif dist == 1 or dist == 2 then
			b.BackgroundColor3 = GOLD
		elseif dist == 3 or dist == 4 then
			b.BackgroundColor3 = Color3.fromRGB(255, 180, 60)
		else
			b.BackgroundColor3 = Color3.fromRGB(140, 90, 25)
		end
	end
end

local function spinTo(shell, wheel, pointer, bulbs, targetIndex, arc, rot)
	local jitter = (math.random() * 2 - 1) * arc * JITTER_ARC
	local want = -((targetIndex - 1) * arc) + jitter
	local base = rot + TURNS * 360
	local final = base + ((want - base) % 360)

	-- 1. ANTICIPATION WINDUP
	local from = rot
	local windTo = rot - WINDUP_DEG
	local t0 = os.clock()
	while true do
		local a = (os.clock() - t0) / WINDUP_TIME
		if a >= 1 or shell.done then break end
		local eased = 1 - (1 - a) * (1 - a)
		local currentR = from + (windTo - from) * eased
		wheel.Rotation = currentR
		pointer.Rotation = (1 - eased) * 6
		updateLEDs(bulbs, currentR, false)
		STEP:Wait()
	end
	if shell.done then return final end
	wheel.Rotation = windTo

	SoundLibrary.PlayLocal("swing", { speed = 0.65, volume = 0.50 })

	-- 2. MAIN ACCELERATION & DECELERATION SPIN
	local span = final - windTo
	local ticksAt = math.floor((windTo + arc * 0.5) / arc)
	t0 = os.clock()
	while true do
		local a = (os.clock() - t0) / SPIN_TIME
		if a >= 1 or shell.done then break end
		local eased = 1 - (1 - a) ^ SPIN_POWER
		local r = windTo + span * eased
		wheel.Rotation = r
		updateLEDs(bulbs, r, false)

		-- Tick & Ratchet pointer deflect
		local now = math.floor((r + arc * 0.5) / arc)
		if now ~= ticksAt then
			ticksAt = now
			local intensity = math.clamp(1 - a * 0.4, 0.5, 1.2)
			wobblePointer(pointer, intensity)
			SoundLibrary.PlayLocal("click", { speed = 0.92 + a * 0.55, volume = 0.32 })
		end

		STEP:Wait()
	end
	if shell.done then return final end
	wheel.Rotation = final

	-- 3. THE SETTLE & BOUNCE
	SoundLibrary.PlayLocal("hit", { speed = 1.35, volume = 0.32 })
	wobblePointer(pointer, 1.4)
	t0 = os.clock()
	while true do
		local a = (os.clock() - t0) / SETTLE_TIME
		if a >= 1 or shell.done then break end
		local bounce = math.sin(a * math.pi) * SETTLE_DEG * (1 - a)
		wheel.Rotation = final + bounce
		updateLEDs(bulbs, final + bounce, false)
		STEP:Wait()
	end
	if not shell.done then
		wheel.Rotation = final
		pointer.Rotation = 0
	end

	return final
end

-- ============================================================================
-- THE REVEAL THEATRE
-- ============================================================================
local function revealPod(pod, big)
	local scale = pod:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = pod

	TweenService:Create(scale,
		TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = big and 1.25 or 1.15 }):Play()

	local stroke = pod:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, TweenInfo.new(0.45), {
			Thickness = big and 10 or 6,
			Color = big and Color3.fromRGB(255, 235, 100) or WHITE,
		}):Play()
	end
end

local function playChain(payload)
	local spins = payload.spins
	if type(spins) ~= "table" or #spins == 0 then return false end

	local shell = buildShell()
	if not shell then return false end

	local wheel, pods, arc, bulbs = buildWheel(shell.root)
	local hub, pointer = buildFurniture(shell.root)
	local burst = buildBurst(shell.root)
	local caption, sub = buildCaption(shell.gui)

	-- Dual counter-rotating sunburst rays
	local innerRays = burst:FindFirstChild("InnerRays")
	local outerRays = burst:FindFirstChild("OuterRays")
	shell.track(STEP:Connect(function(dt)
		if burst.Visible then
			if innerRays then innerRays.Rotation = (innerRays.Rotation + dt * 24) % 360 end
			if outerRays then outerRays.Rotation = (outerRays.Rotation - dt * 16) % 360 end
			updateLEDs(bulbs, 0, true)
		end
	end))

	local hit = Instance.new("TextButton")
	hit.Name = "Dismiss"
	hit.Size = UDim2.fromScale(1, 1)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.ZIndex = 25
	hit.Parent = shell.gui

	local revealed = false
	hit.MouseButton1Click:Connect(function()
		if revealed then shell.finish() end
	end)

	shell.open()
	caption.Text = "\u{1F3A1} LUCKY SPIN"
	sub.Text = "Good luck!"

	task.spawn(function()
		local ok, err = pcall(function()
			local rot = 0
			for i, spin in ipairs(spins) do
				local index = tonumber(spin.index)

				if index and pods[index] then
					rot = spinTo(shell, wheel, pointer, bulbs, index, arc, rot)
				else
					task.wait(0.25)
				end
				if shell.done then return end

				local isRespin = spin.key == "respin"
				local big = BIG_WINS[spin.key] == true

				if isRespin then
					if pods[index] then revealPod(pods[index], false) end
					caption.Text = "\u{1F3A1} SPIN AGAIN!"
					caption.TextColor3 = Color3.fromRGB(255, 220, 100)
					sub.Text = ("free re-spin (%d)"):format(i)
					SoundLibrary.PlayLocal("levelUp", { volume = 0.55 })
					task.wait(1.1)
					if shell.done then return end
					local scale = pods[index] and pods[index]:FindFirstChildOfClass("UIScale")
					if scale then
						TweenService:Create(scale, TweenInfo.new(0.25), { Scale = 1 }):Play()
					end
					caption.Text = "\u{1F3A1} LUCKY SPIN"
					caption.TextColor3 = WHITE
					sub.Text = "Good luck!"
				else
					caption.Text = ("%s %s"):format(spin.emoji or "", spin.name or "?")
					caption.TextColor3 = big and GOLD or WHITE
					sub.Text = detailText(spin)
					revealed = true

					burst.Visible = true
					if pods[index] then revealPod(pods[index], big) end
					SoundLibrary.PlayLocal(big and "evolve" or "purchase", { volume = big and 0.70 or 0.55 })

					-- Stage pop & celebration pulse
					TweenService:Create(shell.uiScale,
						TweenInfo.new(0.40, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
						{ Scale = big and 1.08 or 1.04 }):Play()
				end
			end
		end)
		if not ok then
			warn("[SpinReveal] sequence failed: " .. tostring(err))
			local last = spins[#spins]
			if last then
				caption.Text = ("%s %s"):format(last.emoji or "", last.name or "?")
				sub.Text = detailText(last)
			end
			revealed = true
		end

		task.delay(3.0, shell.finish)
	end)

	return true
end

-- ============================================================================
-- QUEUE MANAGEMENT
-- ============================================================================
local queue = {}
local draining = false

local function drain()
	if draining then return end
	draining = true
	task.spawn(function()
		while #queue > 0 do
			local payload = table.remove(queue, 1)
			if not playChain(payload) then
				table.insert(queue, 1, payload)
				task.wait(0.35)
			else
				repeat task.wait(0.2) until not busy
			end
		end
		draining = false
	end)
end

Remotes:WaitForChild("SpinResult").OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	if type(payload.spins) ~= "table" or #payload.spins == 0 then return end
	if #queue >= MAX_QUEUE then return end
	table.insert(queue, payload)
	drain()
end)
