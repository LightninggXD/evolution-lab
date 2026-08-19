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

-- ===== THE WHEEL IS A PIE NOW, AND ROTATION IS WHY IT HAD TO BE (19.13) =====
--
-- `GuiObject.Rotation` pivots on the element's CENTRE and ignores `AnchorPoint`. Every radial piece
-- on this wheel -- the twelve prize pods, the twelve boundary pegs, the twenty-four rim bulbs --
-- was built as a bar anchored (0.5, 1) at the hub and given `Rotation = theta`, which is the
-- construction that reads correctly and renders wrong: each bar spun about its own midpoint, a
-- point 106 px above the hub, so all twelve landed in ONE place as a fan of overlapping rectangles
-- offset up-and-left of the disc. That is exactly what Kristina photographed -- "radi, vrti se, ali
-- su kartice spojene". The pegs give it away independently: they came out on a circle of radius
-- ~half their own length, centred half a length above the hub, which is only possible under a
-- centre pivot.
--
-- THE FIX IS STRUCTURAL, not a number: a piece may only carry `Rotation` if its own centre IS the
-- hub. So every radial element is now a full-diameter bar centred on the wheel, with the half that
-- points inward masked off by a `UIGradient` transparency step at t = 0.5. `radialBar` is the only
-- constructor allowed to place one, and nothing else in this file sets `Rotation` on an off-centre
-- frame.
--
-- Once the pieces sit where they are told, a rectangle per prize is the wrong shape anyway: a
-- 0.165-wide card spanning hub to rim overlaps its neighbours everywhere inside r = 0.30, because
-- near the hub a fixed width subtends an arc far wider than 360/12. A sector cannot be drawn in one
-- frame, so each prize is filled by a fan of STRIPS_PER_SEG same-coloured bars -- they overlap each
-- other, which is the point, and the seam where a fan overshoots its neighbour is covered by the
-- ink divider that every real carnival wheel has anyway.
local PIE_R = 0.462          -- outer radius of the pie, in fractions of the wheel's side
local STRIPS_PER_SEG = 9     -- fan density: 9 closes the gap at PIE_R with 30-degree sectors
local STRIP_W = 0.032        -- one fan bar's width; must exceed PIE_R * (arc / STRIPS_PER_SEG)
local DIV_W = 0.040          -- ink divider; must exceed STRIP_W so the fan's overshoot is buried
local ICON_R = 0.265         -- where the prize glyph sits, measured from the hub
local TEXT_R = 0.400         -- where its caption sits -- further out, because there is more room there

local BIG_WINS = {
	jackpot = true, vault = true, relic = true, pet = true, dna_flood = true,
}

local SHELL_MAX_LIFE = math.max(24, (GameConfig.SpinMaxChain or 12) * 5.6)
local MAX_QUEUE = 3
-- How many times one payload may fail to build before it is dropped. Dropping a spin is bad;
-- retrying one that can never build is worse, because it holds every later spin behind it.
local MAX_BUILD_ATTEMPTS = 8

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

-- The ONE way a rotating radial piece may be built. `holder` is the full square of the parent, so
-- its centre is the parent's centre and `Rotation` therefore turns about the hub; `bar` is a full
-- diameter of it, and the caller masks the inward half. `lengthScale` is the radius the visible
-- half reaches, in fractions of the parent's side.
local function radialBar(parent, angleDeg, widthScale, lengthScale, zIndex)
	local holder = Instance.new("Frame")
	holder.Name = "Spoke"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.Rotation = angleDeg
	holder.ZIndex = zIndex
	holder.Parent = parent

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.fromScale(0.5, 0.5)
	bar.Size = UDim2.fromScale(widthScale, lengthScale * 2)
	bar.BackgroundColor3 = WHITE
	bar.BorderSizePixel = 0
	bar.ZIndex = zIndex
	bar.Parent = holder

	return holder, bar
end

-- Colour along the OUTWARD half and a hard transparency step at the hub. t = 0 is the rim, t = 0.5
-- is the centre; everything past it is the same bar pointing into the opposite sector and must not
-- draw. The object's own `BackgroundTransparency` still multiplies through the visible half -- that
-- is what the win flash animates, since a `ColorSequence` cannot be tweened.
local function maskOutward(bar, colors)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, colors[1]),
		ColorSequenceKeypoint.new(0.5, colors[2]),
		ColorSequenceKeypoint.new(1, colors[2]),
	})
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.499, 0),
		NumberSequenceKeypoint.new(0.501, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = bar
	return g
end

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

	-- 24 LED bulbs around the rim. Same centre-pivot rule as everything else: the bulb rides a
	-- full-square holder, so it orbits the bezel's centre instead of spinning where it stands.
	local bulbs = {}
	local NUM_BULBS = 24
	for b = 1, NUM_BULBS do
		local bulbPeg = Instance.new("Frame")
		bulbPeg.Name = "BulbPeg" .. b
		bulbPeg.AnchorPoint = Vector2.new(0.5, 0.5)
		bulbPeg.Position = UDim2.fromScale(0.5, 0.5)
		bulbPeg.Size = UDim2.fromScale(1, 1)
		bulbPeg.Rotation = (b - 1) * (360 / NUM_BULBS)
		bulbPeg.BackgroundTransparency = 1
		bulbPeg.ZIndex = 3
		bulbPeg.Parent = outerBezel

		local bulb = Instance.new("Frame")
		bulb.Name = "Bulb"
		bulb.AnchorPoint = Vector2.new(0.5, 0.5)
		bulb.Position = UDim2.fromScale(0.5, 0.5 - 0.462)
		bulb.Size = UDim2.fromScale(0.034, 0.034)
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

		-- One sector = one transparent full-square container, so the win animation can scale the
		-- whole wedge about the hub with a single UIScale. `Theta`/`Arc` ride on it as attributes
		-- because the flash fan is built later, from `revealPod`, which has only the container.
		local pod = Instance.new("Frame")
		pod.Name = "Pod" .. i
		pod.AnchorPoint = Vector2.new(0.5, 0.5)
		pod.Position = UDim2.fromScale(0.5, 0.5)
		pod.Size = UDim2.fromScale(1, 1)
		pod.BackgroundTransparency = 1
		pod.ZIndex = 5
		pod.Parent = wheel
		pod:SetAttribute("Theta", theta)
		pod:SetAttribute("Arc", arc)

		local podScale = Instance.new("UIScale")
		podScale.Parent = pod

		local colors = seg.colors or { Color3.fromRGB(170, 170, 190), Color3.fromRGB(120, 120, 140) }
		for k = 1, STRIPS_PER_SEG do
			local phi = theta - arc * 0.5 + (k - 0.5) * (arc / STRIPS_PER_SEG)
			local _, bar = radialBar(pod, phi, STRIP_W, PIE_R, 5)
			maskOutward(bar, colors)
		end

		-- The caption and the glyph ride their own centred holder at the sector's mid-angle.
		local face = Instance.new("Frame")
		face.Name = "Face"
		face.AnchorPoint = Vector2.new(0.5, 0.5)
		face.Position = UDim2.fromScale(0.5, 0.5)
		face.Size = UDim2.fromScale(1, 1)
		face.BackgroundTransparency = 1
		face.Rotation = theta
		face.ZIndex = 8
		face.Parent = pod

		iconInto(face, seg.emoji, UDim2.fromScale(0.085, 0.085),
			UDim2.fromScale(0.5, 0.5 - ICON_R), 9)

		-- Outward of the glyph on purpose: tangential room grows with radius, and this is the piece
		-- that has to stay legible. At TEXT_R a sector is ~0.207 of the disc wide before the divider
		-- takes its share, so the box is 0.155 and two 15px lines are the worst case.
		local label = CardKit.Text(face, {
			name = "Short",
			text = seg.short or seg.name or "",
			size = UDim2.fromScale(0.155, 0.075),
			position = UDim2.fromScale(0.5, 0.5 - TEXT_R),
			textSize = 15,
			xAlign = "Center",
			zIndex = 9,
			strokeThickness = 2.5,
			truncate = false,
			wrapped = true,
		})
		label.AnchorPoint = Vector2.new(0.5, 0.5)

		pods[i] = pod
	end

	-- Ink dividers on the sector boundaries. Wider than a fan bar, which is the whole job: a fan
	-- overshoots its sector by half a bar and the divider is what buries the seam.
	for j = 1, n do
		local _, bar = radialBar(wheel, (j - 0.5) * arc, DIV_W, PIE_R, 6)
		maskOutward(bar, { INK, INK })
	end

	-- One ring closes the scalloped ends of the fan bars into a circle.
	local rim = Instance.new("Frame")
	rim.Name = "Rim"
	rim.AnchorPoint = Vector2.new(0.5, 0.5)
	rim.Position = UDim2.fromScale(0.5, 0.5)
	rim.Size = UDim2.fromScale(PIE_R * 2 + 0.012, PIE_R * 2 + 0.012)
	rim.BackgroundTransparency = 1
	rim.ZIndex = 7
	rim.Parent = wheel
	CardKit.Corner(rim, 9999)
	CardKit.Stroke(rim, INK, 5)

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

	-- ===== THE FLAPPER PIVOTS ON ITS PIN, AND THAT COSTS ONE EXTRA FRAME =====
	--
	-- `wobblePointer` writes `Rotation` on this, and rotation turns about an element's CENTRE. The
	-- old flapper was a 0.11 x 0.125 box anchored near its top, so every tick swung it about its own
	-- waist -- the tip and the pin travelled in opposite directions, which is not how a ratchet
	-- moves. `pointer` is now empty scaffolding whose centre IS the pivot, and `flap` hangs in its
	-- lower half carrying the geometry the old box had.
	local pointer = Instance.new("Frame")
	pointer.Name = "Pointer"
	pointer.AnchorPoint = Vector2.new(0.5, 0.5)
	pointer.Position = UDim2.fromScale(0.5, 0.045)
	pointer.Size = UDim2.fromScale(0.11, 0.25)
	pointer.BackgroundTransparency = 1
	pointer.ZIndex = 11
	pointer.Parent = root

	local flap = Instance.new("Frame")
	flap.Name = "Flap"
	flap.AnchorPoint = Vector2.new(0.5, 0)
	flap.Position = UDim2.fromScale(0.5, 0.5)
	flap.Size = UDim2.fromScale(1, 0.5)
	flap.BackgroundTransparency = 1
	flap.ZIndex = 11
	flap.Parent = pointer

	local stem = Instance.new("Frame")
	stem.Name = "Stem"
	stem.AnchorPoint = Vector2.new(0.5, 0)
	stem.Position = UDim2.fromScale(0.5, 0)
	stem.Size = UDim2.fromScale(0.65, 0.65)
	stem.BackgroundColor3 = Color3.fromRGB(255, 80, 95)
	stem.BorderSizePixel = 0
	stem.ZIndex = 11
	stem.Parent = flap
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
	tip.Parent = flap
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
	pin.Parent = flap
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

	-- Modest, because the sector now reaches PIE_R: 1.25 would push it out over the golden bezel.
	TweenService:Create(scale,
		TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = big and 1.06 or 1.04 }):Play()

	-- A won sector cannot be "brightened" in place: its colour lives in a UIGradient, gradients
	-- multiply the frame's own colour, and a ColorSequence is not tweenable. So the win is a second
	-- fan laid over the first in white or gold, faded in and out by BackgroundTransparency -- which
	-- the mask leaves free on the outward half. Built here rather than at wheel time so eleven
	-- losing sectors never pay for it, and destroyed after, so a re-spin needs no cleanup.
	local theta = pod:GetAttribute("Theta") or 0
	local arcDeg = pod:GetAttribute("Arc") or 30

	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.AnchorPoint = Vector2.new(0.5, 0.5)
	flash.Position = UDim2.fromScale(0.5, 0.5)
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundTransparency = 1
	flash.ZIndex = 7
	flash.Parent = pod

	local bars = {}
	for k = 1, STRIPS_PER_SEG do
		local phi = theta - arcDeg * 0.5 + (k - 0.5) * (arcDeg / STRIPS_PER_SEG)
		local _, bar = radialBar(flash, phi, STRIP_W, PIE_R, 7)
		bar.BackgroundColor3 = big and GOLD or WHITE
		bar.BackgroundTransparency = 1
		maskOutward(bar, { WHITE, WHITE })
		bars[k] = bar
	end

	task.spawn(function()
		for pulse = 1, big and 3 or 2 do
			for _, bar in ipairs(bars) do
				TweenService:Create(bar, TweenInfo.new(0.14), { BackgroundTransparency = 0.42 }):Play()
			end
			task.wait(0.16)
			if not flash.Parent then return end
			for _, bar in ipairs(bars) do
				TweenService:Create(bar, TweenInfo.new(0.20), { BackgroundTransparency = 1 }):Play()
			end
			task.wait(0.22)
			if not flash.Parent then return end
		end
		flash:Destroy()
	end)
end

-- Held from the moment a shell exists until the animation thread takes ownership of it, so the
-- protected wrapper below can tear down one that was abandoned half-built.
--
-- MEASURED, not theorised: with a builder made to throw on purpose, the first spin was caught and
-- dropped correctly and the next two still reported "still busy after 8 attempts". `buildShell`
-- sets `busy` before any of the builders run, and the only thing that clears it is `shell.finish`
-- -- which the throw skipped, leaving it to the `task.delay(SHELL_MAX_LIFE, ...)` safety net 67
-- seconds later. So a single builder fault still ate a minute of spins, and left a dimmed, blurred,
-- empty shell sitting over the game while it did. Same bug as the drain wedge, one order of
-- magnitude smaller, and invisible until the wedge above was fixed.
local pendingShell = nil

local function buildAndPlay(payload)
	local spins = payload.spins
	if type(spins) ~= "table" or #spins == 0 then return false end

	local shell = buildShell()
	if not shell then return false end
	pendingShell = shell

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

	-- The animation thread owns the shell from here; it has its own pcall and its own finish.
	pendingShell = nil
	return true
end

-- THE PROTECTED DOOR, and the half that never had one. Everything `buildAndPlay` does before its
-- `task.spawn` -- five builders, the dismiss button, `shell.open()` -- ran outside any `pcall`:
-- the one inside guards the ANIMATION only, and it lives in a different thread, so an error in a
-- builder escaped into the drain loop below and killed it. A missing icon, a `SpinWheel` row with
-- no emoji, a PlayerGui reparent mid-open: any of them and the wheel went silent for the rest of
-- the session while the server kept charging Robux, shards and the free daily for it.
--
-- Returns `played, unbuildable`. The second value is what stops the retry from becoming the same
-- wedge by a slower road: a payload that THREW will throw again, so it is dropped rather than
-- put back at the head of the queue forever.
local function playChain(payload)
	local ok, res = pcall(buildAndPlay, payload)
	if not ok then
		warn("[SpinReveal] could not build the wheel: " .. tostring(res))
		-- Give the half-built shell back rather than waiting out SHELL_MAX_LIFE: `busy` is what
		-- every later spin queues behind, and an empty dimmed overlay is what the player is
		-- looking through in the meantime.
		if pendingShell then
			pendingShell.finish()
			pendingShell = nil
		end
		return false, true
	end
	return res, false
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
		-- `draining` MUST be cleared on every exit, and it used to be cleared on exactly one: the
		-- line after a `while` that ran unprotected. Anything that threw inside took the thread
		-- with it and left the flag true forever, so every later `SpinResult` was queued and
		-- `drain()` returned at its first line. The player kept paying and saw nothing at all --
		-- there is no notify fallback any more, deliberately.
		local ok, err = pcall(function()
			local attempts = 0
			while #queue > 0 do
				-- Peek rather than pop: the payload only leaves the queue once it is spoken for,
				-- so a failure has nothing to put back and cannot lose one by forgetting to.
				local played, unbuildable = playChain(queue[1])
				if played then
					table.remove(queue, 1)
					attempts = 0
					repeat task.wait(0.2) until not busy
				elseif unbuildable or attempts >= MAX_BUILD_ATTEMPTS then
					table.remove(queue, 1)
					warn(("[SpinReveal] dropped a spin payload (%s)"):format(
						unbuildable and "it threw while building" or ("still busy after " .. attempts .. " attempts")))
					attempts = 0
				else
					-- The ordinary case: `buildShell` refused because one is already open.
					attempts += 1
					task.wait(0.35)
				end
			end
		end)
		draining = false
		if not ok then warn("[SpinReveal] drain loop failed: " .. tostring(err)) end
	end)
end

Remotes:WaitForChild("SpinResult").OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	if type(payload.spins) ~= "table" or #payload.spins == 0 then return end
	if #queue >= MAX_QUEUE then return end
	table.insert(queue, payload)
	drain()
end)
