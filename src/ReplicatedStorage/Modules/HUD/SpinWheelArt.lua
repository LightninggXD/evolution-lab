--[[
	SpinWheelArt -- everything the lucky wheel is MADE of: the pie, the bezel and its 24 LEDs, the
	ratchet flapper, the sunburst, and the three animations that drive them (34.46).

	MOVED OUT OF `SpinReveal.client.lua`, byte for byte -- the drawing did not change, the number of
	files that need it did. 34.46 turned the wheel from a cutscene into a LOBBY: it opens showing the
	prizes and a spin balance and does not turn until the player presses SPIN. That means the wheel
	is now drawn in two situations rather than one -- idle behind the lobby's controls, and spinning
	for a result -- and a second copy of a construction this fiddly is a second thing to get wrong.
	See `SpinLobby` for the chrome around it and `SpinReveal.client.lua` for the shell that owns both.

	THE ONE RULE IN THIS FILE, and the reason the radial pieces look the way they do: `GuiObject.
	Rotation` pivots on the element's CENTRE and ignores `AnchorPoint`, so a piece may only carry
	`Rotation` if its own centre IS the hub. `radialBar` is the only constructor allowed to place
	one. The full history of what happens when that is broken is on `radialBar` itself.
--]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local RS = game:GetService("ReplicatedStorage")

local Modules = RS:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local UITheme = require(Modules:WaitForChild("UITheme"))
local CardKit = require(Modules:WaitForChild("HUD"):WaitForChild("CardKit"))
local IconLibrary = require(Modules:WaitForChild("IconLibrary"))
local SoundLibrary = require(Modules:WaitForChild("SoundLibrary"))

local STEP = RunService.Heartbeat

local INK = CardKit.INK
local WHITE = Color3.fromRGB(255, 255, 255)
local GOLD = Color3.fromRGB(255, 226, 120)

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

-- ============================================================================
-- THE PUBLIC SURFACE
-- ============================================================================
--
-- Named rather than exported wholesale: the callers only ever need to BUILD the four pieces and RUN
-- the three animations, and everything else in this file is the construction rule that makes those
-- come out in the right place.
local Art = {
	Icon = iconInto,
	Wheel = buildWheel,
	Furniture = buildFurniture,
	Burst = buildBurst,
	SpinTo = spinTo,
	RevealPod = revealPod,
	UpdateLEDs = updateLEDs,
	Wobble = wobblePointer,

	INK = INK,
	WHITE = WHITE,
	GOLD = GOLD,
	SPIN_TIME = SPIN_TIME,
}

return Art
