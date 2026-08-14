--[[
	RarityBeam -- a pillar of light where somebody just pulled a Legendary (Phase 6.2).

	A Legendary is a 0.5% roll and until now it looked exactly like a Common to everyone except the
	person holding the egg: same podium, same small card, no reason for anybody else in the server to
	know it happened. The rarest thing in the game was also the least visible one.

	The beam is the fix, and it is deliberately built for the OTHER players. It is 420 studs tall so
	it clears every zone's skyline, its label is a fixed pixel size so it is as readable from the far
	end of the platform as from underneath, and it is fired by the server to EVERY client rather than
	drawn locally by the hatcher -- a celebration only the celebrant can see is a card, not an event.

	=========================================================================================
	WHAT THIS FILE IS CAREFUL ABOUT
	=========================================================================================
	1. HEARTBEAT, NEVER RENDERSTEPPED, AND NEVER TweenService FOR THE PART THAT MATTERS.
	   This is the same bug HatchReveal's header describes, met twice. `RenderStepped:Wait()` never
	   returns on a client that is not rendering, and `TweenService:Create(...):Play()` on such a
	   client has been observed to run and move nothing at all (see the ambience fade in Phase 4).
	   Every value here that has to arrive -- height, transparency, the ring radii -- is stepped by
	   hand on Heartbeat, which runs on the simulation step and cannot wedge.
	2. NOTHING HERE IS A `Highlight`. CreatureService rents 14 of the ~31 outline renders Roblox
	   will draw at once; a Highlight per beam in a busy server would silently strip the outlines off
	   creatures across the whole world. The chunky read comes from a wide translucent halo column
	   around a narrow neon core instead, which costs no render slot.
	3. EVERY PART IS LOCAL, ANCHORED, AND UNTOUCHABLE. `CanQuery` and `CanTouch` are off on all of
	   them, so a 420-stud column can never become the answer to a combat raycast, block a player, or
	   catch a ProximityPrompt. It lives in a local folder and replicates nowhere.
	4. THE SERVER SETS THE PACE, BUT THE CLIENT STILL CAPS ITSELF. Auto Hatch buys twice a second, so
	   a full server of buyers is a steady trickle of Legendaries. The server rate-limits per player;
	   `MAX_ACTIVE` here is the second half of that, so a burst can never leave a client drawing
	   twenty columns at once.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS:WaitForChild("Modules"):WaitForChild("GameConfig"))
local UITheme = require(RS.Modules:WaitForChild("UITheme"))
local SoundLibrary = require(RS.Modules:WaitForChild("SoundLibrary"))

local player = Players.LocalPlayer
local Remotes = RS:WaitForChild("Remotes")

local STEP = RunService.Heartbeat

local HEIGHT = 420        -- clears the tallest zone scenery and the camera's usual pitch
-- SIZED FROM A PICTURE, NOT FROM TASTE. At 6 studs the first build was a hairline from 170 studs
-- away and invisible at 440, which is the distance the whole feature exists for. A stud is a stud
-- at any height, so a column that has to read from across a 1250-stud platform has to be about as
-- wide as a market stall -- and the halo has to be wide enough to be seen when the core is not.
local CORE_W = 13
local HALO_W = 28
local RING_MAX = 64
local GROW = 0.28
local HOLD = 4.2
local FADE = 1.2
local MAX_ACTIVE = 6
-- the toast outlives the column on purpose: the beam is the "look over there", the words are the
-- thing you read once you have looked
local TOAST_IN = 0.18
local TOAST_HOLD = 5.4
local TOAST_OUT = 0.5

local fxFolder = Instance.new("Folder")
fxFolder.Name = "RarityBeamLocal"
fxFolder.Parent = workspace

local active = 0

-- ============================================================================
-- PIECES
-- ============================================================================
-- NOTHING IS PARENTED IN HERE, and that is the point. A Part is 4 x 1.2 x 2, opaque and at the
-- world origin the instant it exists; parenting it before it has been placed puts a grey slab in
-- the middle of Forest for one frame, on every beam, for every player. Each part below is finished
-- first and parented last, by its caller.
local function scenery(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Locked = true
	return part
end

local function column(width, color, transparency)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Block
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency
	p.Size = Vector3.new(width, 1, width)
	return scenery(p)
end

-- A Cylinder's axis is its X, so a flat disc lying on the ground is a cylinder turned on its side.
-- (A Ball would be worse than wrong here: a non-uniform Ball is drawn as a sphere of its SMALLEST
-- axis, so a 60x60x1 "disc" would render as a 1-stud marble.)
local function disc(color)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.35
	p.Size = Vector3.new(1.2, 4, 4)
	return scenery(p)
end

-- ============================================================================
-- THE TOAST
-- ============================================================================
-- THE NAMING IS ON THE SCREEN, NOT ON THE BEAM, and that was measured rather than preferred. A
-- BillboardGui shrinks with distance whether its size is authored in studs or in pixels: the first
-- build put a 320x96 card on the column, and at 177 studs it rendered about a hundred pixels wide --
-- at the 500-stud range this whole feature exists for it is a smudge. So the announcement is split
-- along the axis each half is good at. The COLUMN is a physical object 420 studs tall, which is
-- exactly as visible from the far end of the platform as it is meant to be; the WORDS are a HUD
-- toast, the same size for everybody in the server no matter where they are standing.
--
-- This is also the "one client toast" roadmap 5.4 asks for. A cross-server announcement has no
-- position in this server and therefore no beam to draw -- but it has words, and they land here
-- unchanged.
--
-- Its own ScreenGui rather than MainUI's: that file is at Luau's 200-register ceiling (see its
-- header) and a toast needs no HUD state at all.
local toastGui, toastList
local toastSeq = 0

local function ensureToastGui()
	if toastGui and toastGui.Parent then return end
	toastGui = Instance.new("ScreenGui")
	toastGui.Name = "RarityToast"
	-- a respawn in the middle of an announcement must not take the words with it
	toastGui.ResetOnSpawn = false
	-- above the HUD and above the boss bar (30), below the zone-transition wipe (500)
	toastGui.DisplayOrder = 120
	toastGui.IgnoreGuiInset = true
	toastGui.Parent = player:WaitForChild("PlayerGui")

	toastList = Instance.new("Frame")
	toastList.Name = "List"
	toastList.AnchorPoint = Vector2.new(0.5, 0)
	-- clear of the XP bar that sits along the very top of the HUD
	toastList.Position = UDim2.new(0.5, 0, 0, 54)
	toastList.Size = UDim2.new(0, 560, 0, 260)
	toastList.BackgroundTransparency = 1
	toastList.Parent = toastGui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = toastList
end

local function toast(color, headline, subline)
	ensureToastGui()

	-- oldest out first, so a burst of announcements cannot walk the stack down the screen
	local live = {}
	for _, c in ipairs(toastList:GetChildren()) do
		if c:IsA("Frame") then table.insert(live, c) end
	end
	table.sort(live, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
	while #live >= 3 do
		table.remove(live, 1):Destroy()
	end

	toastSeq += 1
	local card = Instance.new("Frame")
	card.Size = UDim2.new(0, 560, 0, 72)
	card.BackgroundColor3 = color
	card.BackgroundTransparency = 1
	card.BorderSizePixel = 0
	card.LayoutOrder = toastSeq
	card.Parent = toastList

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = UITheme.Color.Outline
	stroke.Transparency = 1
	stroke.Parent = card

	local top = Instance.new("TextLabel")
	top.Size = UDim2.new(1, -20, 0, 30)
	top.Position = UDim2.new(0.5, 0, 0, 5)
	top.AnchorPoint = Vector2.new(0.5, 0)
	top.BackgroundTransparency = 1
	top.Font = UITheme.Font.Display
	top.TextScaled = true
	top.TextColor3 = UITheme.Color.White
	top.TextStrokeColor3 = UITheme.Color.Outline
	top.TextStrokeTransparency = 1
	top.TextTransparency = 1
	top.Text = headline
	top.Parent = card

	local bottom = Instance.new("TextLabel")
	bottom.Size = UDim2.new(1, -20, 0, 32)
	bottom.Position = UDim2.new(0.5, 0, 1, -5)
	bottom.AnchorPoint = Vector2.new(0.5, 1)
	bottom.BackgroundTransparency = 1
	bottom.Font = UITheme.Font.Display
	bottom.TextScaled = true
	bottom.TextColor3 = UITheme.Color.White
	bottom.TextStrokeColor3 = UITheme.Color.Outline
	bottom.TextStrokeTransparency = 1
	bottom.TextTransparency = 1
	bottom.Text = subline
	bottom.Parent = card

	-- Stepped by hand for the same reason everything else here is: TweenService has been observed to
	-- run and move nothing on a client that is not rendering, and a toast that never becomes visible
	-- is indistinguishable from one that was never sent.
	task.spawn(function()
		local function setAlpha(a)   -- 0 = invisible, 1 = fully drawn
			card.BackgroundTransparency = 1 - a * 0.92
			stroke.Transparency = 1 - a
			top.TextTransparency = 1 - a
			top.TextStrokeTransparency = 1 - a
			bottom.TextTransparency = 1 - a
			bottom.TextStrokeTransparency = 1 - a
		end
		local t0 = os.clock()
		while card.Parent and os.clock() - t0 < TOAST_IN do
			setAlpha((os.clock() - t0) / TOAST_IN)
			STEP:Wait()
		end
		if card.Parent then setAlpha(1) end
		local t1 = os.clock()
		while card.Parent and os.clock() - t1 < TOAST_HOLD do
			STEP:Wait()
		end
		local t2 = os.clock()
		while card.Parent and os.clock() - t2 < TOAST_OUT do
			setAlpha(1 - (os.clock() - t2) / TOAST_OUT)
			STEP:Wait()
		end
		card:Destroy()
	end)
end

local function sparks(host, color)
	local att = Instance.new("Attachment")
	att.Position = Vector3.new(0, 1, 0)
	att.Parent = host

	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0.9
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2.4),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(1.1, 2.0)
	e.Speed = NumberRange.new(38, 70)
	e.Acceleration = Vector3.new(0, 26, 0)
	e.SpreadAngle = Vector2.new(11, 11)
	e.EmissionDirection = Enum.NormalId.Top
	e.Rate = 34
	e.Parent = att
	e:Emit(40)
	return e
end

-- ============================================================================
-- THE BEAM
-- ============================================================================
local function playBeam(payload)
	if active >= MAX_ACTIVE then return end

	-- An explicit `color` wins, exactly as it does on the positionless branch below. Without this
	-- the column could only ever be a PET rarity's colour, and the second publisher is not a pet:
	-- a Splicer mutation is named "Mythic" / "Secret" / "Godly", none of which is a pet rarity, so
	-- `GetRarity` would fall back to Common and beam a grey pillar for the rarest roll in the game.
	local color = payload.color
	if typeof(color) ~= "Color3" then
		color = GameConfig.GetRarity(payload.rarity).color
	end
	local base = payload.position - Vector3.new(0, 3, 0)   -- a root part stands about 3 studs up

	active += 1

	-- the still anchor everything that must not scale hangs off: label, particles, sound
	local host = scenery(Instance.new("Part"))
	host.Size = Vector3.new(1, 1, 1)
	host.Transparency = 1
	host.CFrame = CFrame.new(base)

	local core = column(CORE_W, color, 0.15)
	local halo = column(HALO_W, color, 0.78)
	local rings = { disc(color), disc(color), disc(color) }

	local function setHeight(h)
		core.Size = Vector3.new(CORE_W, h, CORE_W)
		core.CFrame = CFrame.new(base + Vector3.new(0, h * 0.5, 0))
		halo.Size = Vector3.new(HALO_W, h, HALO_W)
		halo.CFrame = core.CFrame
	end
	local function setRing(p, radius, thickness)
		p.Size = Vector3.new(thickness, radius * 2, radius * 2)
		p.CFrame = CFrame.new(base + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
	end

	-- placed, then shown -- see the note over `scenery`
	setHeight(0.2)
	for _, r in ipairs(rings) do
		setRing(r, 2, 1.2)
		r.Transparency = 1
	end
	host.Parent = fxFolder
	core.Parent = fxFolder
	halo.Parent = fxFolder
	for _, r in ipairs(rings) do
		r.Parent = fxFolder
	end

	toast(color, payload.headline or "LEGENDARY", payload.subline or "")
	local emitter = sparks(host, color)

	SoundLibrary.PlayAtPosition("beacon", base + Vector3.new(0, 6, 0))

	local ok, err = pcall(function()
		-- 1. SHOOT UP. Eased out so it leaves the ground fast and arrives softly, which reads as a
		-- beam rather than as a part that changed size.
		local t0 = os.clock()
		while os.clock() - t0 < GROW do
			local a = (os.clock() - t0) / GROW
			local eased = 1 - (1 - a) * (1 - a)
			setHeight(math.max(0.2, eased * HEIGHT))
			STEP:Wait()
		end
		setHeight(HEIGHT)

		-- 2. HOLD: the core breathes, the halo counter-breathes, and three rings ripple outward on a
		-- stagger so the base never looks static.
		local t1 = os.clock()
		while os.clock() - t1 < HOLD do
			local t = os.clock() - t1
			local pulse = 0.5 + 0.5 * math.sin(t * 7)
			core.Transparency = 0.10 + pulse * 0.16
			halo.Transparency = 0.72 + (1 - pulse) * 0.14
			core.Size = Vector3.new(CORE_W * (0.92 + pulse * 0.16), HEIGHT, CORE_W * (0.92 + pulse * 0.16))
			for i, r in ipairs(rings) do
				-- each ring runs the same 1.1s sweep, offset by a third of it
				local a = ((t / 1.1) + (i - 1) / #rings) % 1
				setRing(r, 2 + a * RING_MAX, 1.2)
				r.Transparency = 0.35 + a * 0.65
			end
			STEP:Wait()
		end

		-- 3. AWAY. The emitter stops FEEDING rather than being destroyed, so the sparks already in
		-- the air finish their own lifetimes instead of vanishing in a block.
		emitter.Rate = 0
		-- the rings stop mid-sweep, so each one fades from wherever it had got to rather than
		-- snapping to a shared value first
		local ringFrom = {}
		for i, r in ipairs(rings) do
			ringFrom[i] = r.Transparency
		end
		local t2 = os.clock()
		while os.clock() - t2 < FADE do
			local a = (os.clock() - t2) / FADE
			core.Transparency = 0.10 + a * 0.90
			halo.Transparency = 0.72 + a * 0.28
			for i, r in ipairs(rings) do
				r.Transparency = ringFrom[i] + (1 - ringFrom[i]) * a
			end
			STEP:Wait()
		end
	end)

	-- one cleanup path, taken whether the loop finished or threw
	core:Destroy()
	halo:Destroy()
	for _, r in ipairs(rings) do
		r:Destroy()
	end
	Debris:AddItem(host, 2.2)   -- long enough for the last sparks to die on their own
	active -= 1

	if not ok then
		warn("[RarityBeam] beam failed: " .. tostring(err))
	end
end

-- ============================================================================
-- WIRING
-- ============================================================================
-- FireAllClients, so this arrives at the hatcher and at everybody else identically. The payload is
-- checked anyway: a malformed one would otherwise leave `active` incremented forever and silently
-- cap the feature off after six bad sends.
--
-- A PAYLOAD WITH NO POSITION IS WORDS ONLY, and that is not a degraded case -- it is the second
-- kind of announcement. An event opening (7.1) happens everywhere at once and a cross-server hatch
-- (5.4) happens somewhere this server cannot point at; neither has anywhere to put a column, and
-- both have something to say. Until now this handler REQUIRED a Vector3 and silently dropped
-- anything without one, so the header's claim that a positionless message "lands here unchanged"
-- was not yet true. It is now.
local beam = Remotes:WaitForChild("RarityBeam")
beam.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end

	if typeof(payload.position) ~= "Vector3" then
		if type(payload.headline) ~= "string" then return end
		-- an explicit colour, or the rarity's if one was named, or the house lavender
		local color = payload.color
		if typeof(color) ~= "Color3" then
			color = payload.rarity and GameConfig.GetRarity(payload.rarity).color or UITheme.Color.Lavender
		end
		toast(color, payload.headline, payload.subline or "")
		return
	end

	task.spawn(playBeam, payload)
end)
