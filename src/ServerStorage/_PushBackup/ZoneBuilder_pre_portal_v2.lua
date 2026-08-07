local RS = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local GameConfig = require(RS.Modules.GameConfig)
local PetModel = require(RS.Modules.PetModel)

local ZoneBuilder = {}

-- Bump this on every change to world geometry. Build() skips any zone that already exists, which
-- on a place that has been played once means *no* decoration change is ever visible again. The
-- stamp on the Zones folder is how Build() tells "already built by this code" from "built by an
-- older version" -- if it does not match, the whole folder is dropped and regenerated.
local BUILD_VERSION = 15

local PLATFORM_DEPTH = 550
local PLATFORM_WIDTH = 450
local WALL_HEIGHT = 140
local WALL_THICK = 4
local PORTAL_GAP = 78

-- Forest arrival clearing. The place ships with its SpawnLocation at (-32, 1, -25), which is
-- inside the Forest egg-plaza footprint -- players spawn wedged against the shop. See EnsureSpawn.
local SPAWN_POSITION = Vector3.new(0, 1, 170)

-- Real Roblox PBR materials per zone instead of flat SmoothPlastic -- free, built-in,
-- actual surface detail (bump/roughness) with no external assets needed.
local GROUND_MATERIAL = {
	Forest = Enum.Material.Grass,
	Desert = Enum.Material.Sand,
	Ocean = Enum.Material.Sand,
	Volcano = Enum.Material.Basalt,
	Moon = Enum.Material.Slate,
	Mars = Enum.Material.Rock,
	Galaxy = Enum.Material.Foil,
	BlackHole = Enum.Material.Slate,
	Multiverse = Enum.Material.Foil,
	Nebula = Enum.Material.Foil,
	Wormhole = Enum.Material.Slate,
	QuantumRealm = Enum.Material.Glass,
	TimeRift = Enum.Material.Neon,
	AntimatterZone = Enum.Material.Slate,
	DreamDimension = Enum.Material.Foil,
	MirrorUniverse = Enum.Material.Glass,
	VoidExpanse = Enum.Material.Slate,
	CelestialThrone = Enum.Material.Neon,
	Singularity = Enum.Material.Foil,
	AbsolutePlane = Enum.Material.Neon,
}

-- Optional AI-generated cliff/rock formation per zone, cloned repeatedly along a
-- boundary to hide the flat invisible collision wall behind natural-looking terrain
-- instead of a flat slab. Zones with no entry here just keep the plain wall look.
local CLIFF_MESH_NAME = {
	Desert = "DesertCliffMesh",
}

local function getCliffTemplate(zoneKey)
	local name = CLIFF_MESH_NAME[zoneKey]
	return name and ServerStorage:FindFirstChild("Models") and ServerStorage.Models:FindFirstChild(name)
end

-- Clones `template` repeatedly along a line (axis "x" or "z") in front of `wall`,
-- with jitter/rotation/scale variety, then hides the flat wall behind it.
local function addCliffLine(model, wall, template, axis, length)
	wall.Transparency = 1
	-- tight spacing + generous scale so rocks always overlap -- no gaps a player could
	-- see (or peek into the next zone) through, and every stretch reads equally detailed
	local spacing = 26
	local count = math.ceil(length / spacing) + 2
	local start = -length / 2 - spacing
	for i = 0, count - 1 do
		local t = start + spacing * i + math.random(-3, 3)
		local rock = template:Clone()
		local scale = 1.05 + math.random() * 0.5
		rock:ScaleTo(scale)
		local geom = rock:FindFirstChild("body") and rock.body:FindFirstChild("body_geom")
		local halfHeight = (geom and geom.Size.Y / 2 or 65) * scale
		local pos
		if axis == "x" then
			pos = Vector3.new(wall.Position.X + t, halfHeight - 3, wall.Position.Z + math.random(-4, 4))
		else
			pos = Vector3.new(wall.Position.X + math.random(-4, 4), halfHeight - 3, wall.Position.Z + t)
		end
		local rotY = axis == "x" and (math.random(-10, 10)) or (90 + math.random(-10, 10))
		rock:PivotTo(CFrame.new(pos) * CFrame.Angles(0, math.rad(rotY), 0))
		rock.Parent = model
	end
end

local function newPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	return p
end

local function makeSign(parentModel, text, cframe, size)
	local signPart = newPart({
		Name = "SignPart",
		Size = Vector3.new(1, 1, 1),
		CFrame = cframe,
		Transparency = 1,
		CanCollide = false,
		Parent = parentModel,
	})
	local billboard = Instance.new("BillboardGui")
	billboard.Size = size or UDim2.new(0, 260, 0, 70)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 140
	billboard.Parent = signPart
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 0.35
	label.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Text = text
	label.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = label
	return signPart
end

-- Scatters vertical support pillars + a thin neon light strip along a wall so it never
-- reads as one flat bare slab -- reused by both wall-building helpers below. Must be defined
-- before buildXWall/buildZWall since Lua resolves `local function` upvalues lexically.
local function addWallDecor(model, positions, wallColor, faceOffset)
	local bright = Color3.new(math.min(1, wallColor.R * 4.5), math.min(1, wallColor.G * 4.5), math.min(1, wallColor.B * 4.5))
	for _, pos in ipairs(positions) do
		newPart({ Name = "WallPillar", Size = Vector3.new(6, WALL_HEIGHT + 4, WALL_THICK + 2), Position = pos, Color = bright, Material = Enum.Material.Metal, Parent = model })
		newPart({ Name = "WallLight", Size = Vector3.new(1.6, WALL_HEIGHT - 30, 1), Position = pos + faceOffset, Color = bright, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	end
end

-- Builds a solid wall along the X axis for one zone. If `target` is given, leaves a big
-- glowing portal gap in the middle instead of a full wall -- this is the only way in or out,
-- so you never see the next zone until you actually walk through the gate.
local function buildXWall(model, wallX, wallColor, target, cliffTemplate)
	if target then
		local gapHalf = PORTAL_GAP / 2
		local segLen = (PLATFORM_DEPTH - PORTAL_GAP) / 2

		local gateWallA = newPart({ Name = "Wall", Size = Vector3.new(WALL_THICK, WALL_HEIGHT, segLen), Position = Vector3.new(wallX, WALL_HEIGHT/2, -(gapHalf + segLen/2)), Color = wallColor, Material = Enum.Material.Slate, Parent = model })
		local gateWallB = newPart({ Name = "Wall", Size = Vector3.new(WALL_THICK, WALL_HEIGHT, segLen), Position = Vector3.new(wallX, WALL_HEIGHT/2, (gapHalf + segLen/2)), Color = wallColor, Material = Enum.Material.Slate, Parent = model })
		if cliffTemplate then
			-- frame the gate in the same rock formation as the rest of the boundary, so the
			-- portal reads as a carved passage through natural terrain, not a different style
			addCliffLine(model, gateWallA, cliffTemplate, "z", segLen)
			addCliffLine(model, gateWallB, cliffTemplate, "z", segLen)
		end

		newPart({ Name = "PortalPillar", Size = Vector3.new(WALL_THICK + 10, WALL_HEIGHT + 16, 14), Position = Vector3.new(wallX, WALL_HEIGHT/2 + 2, -gapHalf - 4), Color = target.accentColor, Material = Enum.Material.Metal, Parent = model })
		newPart({ Name = "PortalPillar", Size = Vector3.new(WALL_THICK + 10, WALL_HEIGHT + 16, 14), Position = Vector3.new(wallX, WALL_HEIGHT/2 + 2, gapHalf + 4), Color = target.accentColor, Material = Enum.Material.Metal, Parent = model })
		newPart({ Name = "PortalLintel", Size = Vector3.new(WALL_THICK + 10, 12, PORTAL_GAP + 28), Position = Vector3.new(wallX, WALL_HEIGHT + 12, 0), Color = target.accentColor, Material = Enum.Material.Metal, Parent = model })
		newPart({ Name = "PortalCap", Size = Vector3.new(WALL_THICK + 14, 6, PORTAL_GAP + 40), Position = Vector3.new(wallX, WALL_HEIGHT + 19, 0), Color = Color3.new(math.min(1,target.accentColor.R*1.3), math.min(1,target.accentColor.G*1.3), math.min(1,target.accentColor.B*1.3)), Material = Enum.Material.Neon, Parent = model })

		-- the big glowing gate surface you walk through -- opaque neon, so you see a colored
		-- glow hinting at the destination, never the actual next zone behind it
		local gate = newPart({
			Name = "PortalGate",
			Size = Vector3.new(2, WALL_HEIGHT - 4, PORTAL_GAP - 4),
			Position = Vector3.new(wallX, WALL_HEIGHT/2, 0),
			Color = target.accentColor,
			Material = Enum.Material.Neon,
			Transparency = 0.2,
			CanCollide = false,
			CanTouch = true,
			Parent = model,
		})
		gate:SetAttribute("TargetZone", target.key)

		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Color = ColorSequence.new(target.accentColor)
		sparkle.Rate = 12
		sparkle.Lifetime = NumberRange.new(1, 2)
		sparkle.Speed = NumberRange.new(2, 5)
		sparkle.Size = NumberSequence.new(1.2)
		sparkle.Transparency = NumberSequence.new(0.3, 1)
		sparkle.Parent = gate

		-- extra swirling rings + rising motes so the gate reads as a living portal,
		-- not just a flat glowing slab
		for ringIndex = 1, 2 do
			local ring = newPart({
				Name = "PortalRing",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(1, PORTAL_GAP - 6 - ringIndex * 8, PORTAL_GAP - 6 - ringIndex * 8),
				Orientation = Vector3.new(0, 0, 0),
				Position = Vector3.new(wallX, WALL_HEIGHT/2, 0),
				Color = target.accentColor,
				Material = Enum.Material.Neon,
				Transparency = 0.45,
				CanCollide = false,
				Parent = model,
			})
			task.spawn(function()
				while ring.Parent do
					ring.CFrame = CFrame.new(wallX, WALL_HEIGHT/2, 0) * CFrame.Angles(math.rad(90), os.clock() * (ringIndex == 1 and 0.6 or -0.9), 0)
					task.wait(0.03)
				end
			end)
		end

		local rising = Instance.new("ParticleEmitter")
		rising.Color = ColorSequence.new(Color3.new(1,1,1), target.accentColor)
		rising.Rate = 6
		rising.Lifetime = NumberRange.new(1.5, 2.5)
		rising.Speed = NumberRange.new(4, 6)
		rising.SpreadAngle = Vector2.new(8, 8)
		rising.Size = NumberSequence.new(0.6)
		rising.Transparency = NumberSequence.new(0.2, 1)
		rising.Parent = gate

		local portalLight = Instance.new("PointLight")
		portalLight.Color = target.accentColor
		portalLight.Range = 24
		portalLight.Brightness = 2
		portalLight.Parent = gate

		makeSign(model, "🌀 " .. target.emoji .. " " .. target.name, CFrame.new(wallX, WALL_HEIGHT + 12, 0), UDim2.new(0, 220, 0, 60))
	else
		local wall = newPart({ Name = "Wall", Size = Vector3.new(WALL_THICK, WALL_HEIGHT, PLATFORM_DEPTH), Position = Vector3.new(wallX, WALL_HEIGHT/2, 0), Color = wallColor, Material = Enum.Material.Slate, Parent = model })
		if cliffTemplate then
			addCliffLine(model, wall, cliffTemplate, "z", PLATFORM_DEPTH)
		else
			local positions = {}
			for i = 0, 4 do
				local pz = -PLATFORM_DEPTH/2 + (PLATFORM_DEPTH/4) * i
				table.insert(positions, Vector3.new(wallX, WALL_HEIGHT/2, pz))
			end
			local faceSign = wallX > 0 and -1 or 1
			addWallDecor(model, positions, wallColor, Vector3.new(faceSign * (WALL_THICK/2 + 0.6), 0, 0))
		end
	end
end

local function buildZWall(model, cx, cz, wallColor, cliffTemplate)
	local wall = newPart({ Name = "Wall", Size = Vector3.new(PLATFORM_WIDTH, WALL_HEIGHT, WALL_THICK), Position = Vector3.new(cx, WALL_HEIGHT/2, cz), Color = wallColor, Material = Enum.Material.Slate, Parent = model })
	if cliffTemplate then
		addCliffLine(model, wall, cliffTemplate, "x", PLATFORM_WIDTH)
	else
		local positions = {}
		for i = 0, 4 do
			local px = cx - PLATFORM_WIDTH/2 + (PLATFORM_WIDTH/4) * i
			table.insert(positions, Vector3.new(px, WALL_HEIGHT/2, cz))
		end
		local faceSign = cz > 0 and -1 or 1
		addWallDecor(model, positions, wallColor, Vector3.new(0, 0, faceSign * (WALL_THICK/2 + 0.6)))
	end
end

-- ===== shared decoration helpers =====
-- Every zone is dressed in four layers -- a GROUND layer of scattered rocks/mounds, a MID
-- layer of signature biome props, one big LANDMARK silhouette at the back of the platform,
-- and an ATMOSPHERE emitter -- plus LIGHTING ACCENTS, so no platform ever reads as an empty
-- rectangle. The Desert builder was the quality bar; these helpers make it cheap to hit it
-- in all 20 biomes without copy-pasting the same scatter loops twenty times.

local DECO_SPREAD_X = 205 -- stay inside the platform: |x - cx| <= 210
local DECO_SPREAD_Z = 255 -- and |z| <= 260
local CLEAR_HALF = 60     -- centre stays clear: Pet Shop + creature spawns live there
local ARRIVAL_Z = 174     -- players teleport in near here (see GetZoneSpawnPosition)
local ARRIVAL_CLEAR = 54  -- ... so keep a clearing around it in every zone

local function lighten(c, t)
	return c:Lerp(Color3.new(1, 1, 1), t)
end

local function darken(c, t)
	return c:Lerp(Color3.new(0, 0, 0), t)
end

-- Random point on the platform that is never inside the reserved central square and never
-- inside the arrival clearing. Returns absolute world x (already offset by cx) and z.
local function scatterPoint(cx, spreadX, spreadZ)
	spreadX = spreadX or DECO_SPREAD_X
	spreadZ = spreadZ or DECO_SPREAD_Z
	for _ = 1, 24 do
		local x = math.random(-spreadX, spreadX)
		local z = math.random(-spreadZ, spreadZ)
		local outsideCentre = math.abs(x) >= CLEAR_HALF or math.abs(z) >= CLEAR_HALF
		local dz = z - ARRIVAL_Z
		local outsideArrival = (x * x + dz * dz) > (ARRIVAL_CLEAR * ARRIVAL_CLEAR)
		if outsideCentre and outsideArrival then
			return cx + x, z
		end
	end
	local sign = math.random(1, 2) == 1 and -1 or 1
	return cx + sign * math.random(CLEAR_HALF + 12, spreadX), math.random(-spreadZ, -CLEAR_HALF)
end

local function addLight(part, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range or 24
	l.Brightness = brightness or 2
	l.Parent = part
	return l
end

-- GROUND LAYER: low scattered rocks / shards / debris that break up the flat floor.
local function addGroundLitter(model, cx, cfg)
	local colors = cfg.colors
	local flat = cfg.flat or 0.6
	for _ = 1, (cfg.count or 16) do
		local x, z = scatterPoint(cx)
		local s = math.random(cfg.minSize or 3, cfg.maxSize or 11)
		newPart({
			Name = cfg.name or "GroundRock",
			Shape = cfg.shape or Enum.PartType.Ball,
			Size = Vector3.new(s, s * flat, s * (0.75 + math.random() * 0.5)),
			Orientation = Vector3.new(0, math.random(0, 360), 0),
			Position = Vector3.new(x, s * flat * 0.35, z),
			Color = colors[math.random(1, #colors)],
			Material = cfg.material or Enum.Material.Rock,
			Transparency = cfg.transparency or 0,
			CanCollide = false,
			Parent = model,
		})
	end
end

-- GROUND LAYER: wide, very low mounds so the floor has some relief instead of being a plane.
local function addMounds(model, cx, cfg)
	for _ = 1, (cfg.count or 5) do
		local x, z = scatterPoint(cx, 190, 240)
		local s = math.random(cfg.minSize or 32, cfg.maxSize or 62)
		newPart({
			Name = cfg.name or "Mound",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(s, s * (cfg.flat or 0.24), s * 0.9),
			Position = Vector3.new(x, s * 0.03, z),
			Color = cfg.color,
			Material = cfg.material or Enum.Material.Slate,
			Transparency = cfg.transparency or 0,
			CanCollide = false,
			Parent = model,
		})
	end
end

-- ATMOSPHERE LAYER: one biome-appropriate particle field drifting over the whole platform.
local function addAtmosphere(model, cx, cfg)
	local anchor = newPart({
		Name = "Atmosphere",
		Size = Vector3.new(PLATFORM_WIDTH - 60, 1, PLATFORM_DEPTH - 60),
		Position = Vector3.new(cx, cfg.height or 30, 0),
		Transparency = 1,
		CanCollide = false,
		Parent = model,
	})
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(cfg.color, cfg.color2 or cfg.color)
	e.Size = NumberSequence.new(cfg.sizeStart or 2, cfg.sizeEnd or 4)
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, cfg.transparency or 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(cfg.lifeMin or 5, cfg.lifeMax or 9)
	e.Rate = cfg.rate or 10
	e.Speed = NumberRange.new(cfg.speedMin or 2, cfg.speedMax or 6)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-25, 25)
	e.LightEmission = cfg.lightEmission or 0
	e.Acceleration = cfg.acceleration or Vector3.new(0, 0, 0)
	e.Parent = anchor
	return anchor
end

-- LIGHTING ACCENTS: scattered lamp posts, each carrying a real PointLight in the biome colour.
local function addGlowPosts(model, cx, cfg)
	local color = cfg.color
	for _ = 1, (cfg.count or 5) do
		local x, z = scatterPoint(cx, 195, 245)
		local h = cfg.height or math.random(10, 20)
		newPart({ Name = "GlowPost", Size = Vector3.new(1.8, h, 1.8), Position = Vector3.new(x, h / 2, z), Color = darken(color, 0.65), Material = Enum.Material.Metal, CanCollide = false, Parent = model })
		local bulb = newPart({ Name = "GlowBulb", Shape = Enum.PartType.Ball, Size = Vector3.new(4.5, 4.5, 4.5), Position = Vector3.new(x, h + 1.5, z), Color = color, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(bulb, color, cfg.range or 28, cfg.brightness or 2)
	end
end

-- LANDMARK: one big silhouette feature near the back of the platform (z ~ -210) so the zone
-- reads from a distance. Every landmark stands on a lit plinth and is framed by two braziers,
-- so it looks like a built site rather than a lone prop dropped on the floor.
local function addLandmark(model, cx, cfg)
	local z = cfg.z or -210
	local base = cfg.base
	local accent = cfg.accent
	local mat = cfg.material or Enum.Material.Rock
	local lit = {}

	newPart({ Name = "LandmarkPlinth", Size = Vector3.new(96, 5, 62), Position = Vector3.new(cx, 2.5, z), Color = darken(base, 0.45), Material = mat, Parent = model })
	newPart({ Name = "LandmarkPlinthTrim", Size = Vector3.new(104, 1.8, 70), Position = Vector3.new(cx, 5.4, z), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = model })

	local style = cfg.style
	if style == "greattree" then
		newPart({ Name = "GreatTrunk", Size = Vector3.new(20, 76, 20), Position = Vector3.new(cx, 43, z), Color = cfg.trunkColor or Color3.fromRGB(92, 64, 40), Material = Enum.Material.Wood, Parent = model })
		for i = 1, 3 do
			newPart({ Name = "GreatRoot", Size = Vector3.new(8, 13, 28), Orientation = Vector3.new(0, i * 57, 0), Position = Vector3.new(cx + math.random(-12, 12), 9, z + math.random(-10, 10)), Color = cfg.trunkColor or Color3.fromRGB(92, 64, 40), Material = Enum.Material.Wood, Parent = model })
		end
		for i = 1, 6 do
			local s = math.random(36, 58)
			newPart({ Name = "GreatCanopy", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 0.82, s), Position = Vector3.new(cx + math.random(-24, 24), 80 + math.random(-10, 16), z + math.random(-16, 16)), Color = i % 2 == 0 and base or darken(base, 0.22), Material = Enum.Material.Grass, CanCollide = false, Parent = model })
		end
		local fruit = newPart({ Name = "GreatGlow", Shape = Enum.PartType.Ball, Size = Vector3.new(11, 11, 11), Position = Vector3.new(cx, 110, z), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		table.insert(lit, fruit)
	elseif style == "spire" then
		local y = 5
		for i = 0, 5 do
			local w = 42 - i * 5.5
			local h = 17 - i * 1.2
			newPart({ Name = "SpireBlock", Size = Vector3.new(w, h, w * 0.78), Orientation = Vector3.new(0, i * 11, 0), Position = Vector3.new(cx, y + h / 2, z), Color = i % 2 == 0 and base or darken(base, 0.2), Material = mat, Parent = model })
			y = y + h
		end
		local tip = newPart({ Name = "SpireTip", Size = Vector3.new(12, 24, 12), Orientation = Vector3.new(0, 45, 0), Position = Vector3.new(cx, y + 12, z), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		table.insert(lit, tip)
	elseif style == "arch" then
		for _, side in ipairs({ -1, 1 }) do
			newPart({ Name = "ArchLeg", Size = Vector3.new(13, 72, 14), Position = Vector3.new(cx + side * 31, 41, z), Color = base, Material = mat, Parent = model })
			newPart({ Name = "ArchLegTrim", Size = Vector3.new(16, 4, 17), Position = Vector3.new(cx + side * 31, 75, z), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		end
		newPart({ Name = "ArchSpan", Size = Vector3.new(90, 13, 16), Position = Vector3.new(cx, 83, z), Color = base, Material = mat, Parent = model })
		local key = newPart({ Name = "ArchKeystone", Shape = Enum.PartType.Ball, Size = Vector3.new(22, 22, 22), Position = Vector3.new(cx, 96, z), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		table.insert(lit, key)
	elseif style == "ring" then
		newPart({ Name = "RingPylon", Size = Vector3.new(18, 38, 18), Position = Vector3.new(cx, 24, z), Color = base, Material = mat, Parent = model })
		for i = 1, 3 do
			local s = 52 + i * 24
			local r = newPart({ Name = "LandmarkRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, s, s), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(cx, 80, z), Color = i == 2 and lighten(accent, 0.3) or accent, Material = Enum.Material.Neon, Transparency = 0.1 + i * 0.15, CanCollide = false, Parent = model })
			if i == 1 then
				table.insert(lit, r)
			end
		end
		local core = newPart({ Name = "LandmarkCore", Shape = Enum.PartType.Ball, Size = Vector3.new(26, 26, 26), Position = Vector3.new(cx, 80, z), Color = cfg.coreColor or lighten(accent, 0.4), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		table.insert(lit, core)
	elseif style == "crystal" then
		for i = 1, 7 do
			local h = math.random(38, 92)
			local w = math.random(8, 17)
			local c = newPart({ Name = "LandmarkCrystal", Size = Vector3.new(w, h, w), Orientation = Vector3.new(math.random(-13, 13), math.random(0, 360), math.random(-13, 13)), Position = Vector3.new(cx + math.random(-40, 40), 5 + h / 2, z + math.random(-18, 18)), Color = i % 2 == 0 and accent or lighten(accent, 0.4), Material = Enum.Material.Neon, Transparency = 0.12, Parent = model })
			if i <= 2 then
				table.insert(lit, c)
			end
		end
	elseif style == "tower" then
		local y = 5
		for i = 1, 4 do
			local w = 46 - i * 7
			newPart({ Name = "TowerTier", Size = Vector3.new(w, 19, w * 0.8), Position = Vector3.new(cx, y + 9.5, z), Color = i % 2 == 0 and base or darken(base, 0.18), Material = mat, Parent = model })
			newPart({ Name = "TowerBand", Size = Vector3.new(w + 5, 2.6, w * 0.8 + 5), Position = Vector3.new(cx, y + 19, z), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
			y = y + 19
		end
		local beacon = newPart({ Name = "TowerBeacon", Shape = Enum.PartType.Ball, Size = Vector3.new(17, 17, 17), Position = Vector3.new(cx, y + 10, z), Color = lighten(accent, 0.25), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		table.insert(lit, beacon)
	elseif style == "orb" then
		newPart({ Name = "OrbPylon", Shape = Enum.PartType.Cylinder, Size = Vector3.new(54, 16, 16), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(cx, 32, z), Color = base, Material = mat, Parent = model })
		local orb = newPart({ Name = "LandmarkOrb", Shape = Enum.PartType.Ball, Size = Vector3.new(46, 46, 46), Position = Vector3.new(cx, 82, z), Color = cfg.coreColor or accent, Material = Enum.Material.Neon, Transparency = cfg.orbTransparency or 0, CanCollide = false, Parent = model })
		table.insert(lit, orb)
		for i = 1, 2 do
			local s = 62 + i * 22
			newPart({ Name = "OrbHalo", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, s, s), Orientation = Vector3.new(i * 22, 0, 90), Position = Vector3.new(cx, 82, z), Color = lighten(accent, 0.35), Material = Enum.Material.Neon, Transparency = 0.35 + i * 0.15, CanCollide = false, Parent = model })
		end
	end

	for _, p in ipairs(lit) do
		addLight(p, accent, 42, 3)
	end

	-- two braziers framing the landmark so it reads as a site, not a lone prop
	for _, side in ipairs({ -1, 1 }) do
		newPart({ Name = "LandmarkPost", Size = Vector3.new(3.5, 42, 3.5), Position = Vector3.new(cx + side * 60, 21, z + 12), Color = darken(base, 0.55), Material = Enum.Material.Metal, CanCollide = false, Parent = model })
		local flame = newPart({ Name = "LandmarkFlame", Shape = Enum.PartType.Ball, Size = Vector3.new(8, 8, 8), Position = Vector3.new(cx + side * 60, 45, z + 12), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(flame, accent, 28, 2)
	end
end

-- Runs the shared GROUND + LANDMARK + ATMOSPHERE + LIGHTING passes for one zone, so each
-- biome builder below only has to add its own signature MID-layer props.
local function buildBiomeBase(model, cx, cfg)
	if cfg.litter then
		addGroundLitter(model, cx, cfg.litter)
	end
	if cfg.mounds then
		addMounds(model, cx, cfg.mounds)
	end
	if cfg.landmark then
		addLandmark(model, cx, cfg.landmark)
	end
	if cfg.atmosphere then
		addAtmosphere(model, cx, cfg.atmosphere)
	end
	if cfg.glow then
		addGlowPosts(model, cx, cfg.glow)
	end
end

-- Per-biome decoration builders. Each receives the zone model, zone config, and center X offset.
local decorationBuilders = {}

local forestTreeTemplate = ServerStorage:FindFirstChild("Models") and ServerStorage.Models:FindFirstChild("ForestTree")

decorationBuilders.Forest = function(model, zone, cx)
	local leaf = Color3.fromRGB(52, 132, 58)
	local glow = Color3.fromRGB(150, 255, 160)

	buildBiomeBase(model, cx, {
		litter = { count = 16, colors = { Color3.fromRGB(96, 104, 92), Color3.fromRGB(74, 86, 70), Color3.fromRGB(122, 128, 112) }, minSize = 3, maxSize = 10, material = Enum.Material.Rock },
		mounds = { count = 5, color = Color3.fromRGB(88, 156, 84), material = Enum.Material.Grass, minSize = 34, maxSize = 62 },
		landmark = { style = "greattree", base = leaf, accent = glow, trunkColor = Color3.fromRGB(96, 66, 42), material = Enum.Material.Wood },
		atmosphere = { color = Color3.fromRGB(215, 255, 190), color2 = Color3.fromRGB(255, 240, 160), height = 22, rate = 10, sizeStart = 0.8, sizeEnd = 1.8, transparency = 0.3, lifeMin = 5, lifeMax = 10, speedMin = 1, speedMax = 3, lightEmission = 0.9 },
		glow = { count = 5, color = Color3.fromRGB(255, 218, 130), height = 15, range = 30 },
	})

	-- MID: the tree canopy itself, varied scale + rotation so it never reads as clones
	for _ = 1, 15 do
		local x, z = scatterPoint(cx, 195, 245)
		if forestTreeTemplate then
			local tree = forestTreeTemplate:Clone()
			local geom = tree:FindFirstChild("body") and tree.body:FindFirstChild("body_geom")
			local scale = 0.8 + math.random() * 0.8
			tree:ScaleTo(scale)
			local halfHeight = (geom and geom.Size.Y / 2 or 8) * scale
			tree:PivotTo(CFrame.new(x, halfHeight, z) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
			tree.Parent = model
		else
			local h = math.random(14, 26)
			newPart({ Name = "Trunk", Size = Vector3.new(4, h, 4), Position = Vector3.new(x, h / 2, z), Color = Color3.fromRGB(92, 64, 40), Material = Enum.Material.Wood, Parent = model })
			newPart({ Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.new(21, 18, 21), Position = Vector3.new(x, h + 6, z), Color = leaf, Material = Enum.Material.Grass, CanCollide = false, Parent = model })
		end
	end

	-- MID: undergrowth -- bushes, glowing mushrooms and fallen logs at eye level
	for i = 1, 10 do
		local x, z = scatterPoint(cx)
		local s = math.random(7, 16)
		newPart({ Name = "Bush", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 0.8, s * 0.9), Orientation = Vector3.new(0, math.random(0, 360), 0), Position = Vector3.new(x, s * 0.34, z), Color = i % 2 == 0 and leaf or darken(leaf, 0.2), Material = Enum.Material.Grass, CanCollide = false, Parent = model })
	end
	for i = 1, 6 do
		local x, z = scatterPoint(cx)
		newPart({ Name = "MushroomStem", Size = Vector3.new(1.6, 5, 1.6), Position = Vector3.new(x, 2.5, z), Color = Color3.fromRGB(235, 226, 202), Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
		local cap = newPart({ Name = "MushroomCap", Shape = Enum.PartType.Ball, Size = Vector3.new(7.5, 4.5, 7.5), Position = Vector3.new(x, 5.8, z), Color = Color3.fromRGB(120, 255, 175), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		if i <= 3 then
			addLight(cap, Color3.fromRGB(120, 255, 175), 16, 1.5)
		end
	end
	for _ = 1, 5 do
		local x, z = scatterPoint(cx)
		newPart({ Name = "FallenLog", Shape = Enum.PartType.Cylinder, Size = Vector3.new(math.random(14, 26), 5, 5), Orientation = Vector3.new(0, math.random(0, 360), 0), Position = Vector3.new(x, 2.5, z), Color = Color3.fromRGB(86, 60, 38), Material = Enum.Material.Wood, CanCollide = false, Parent = model })
	end
end

local desertCactusTemplate = ServerStorage:FindFirstChild("Models") and ServerStorage.Models:FindFirstChild("DesertCactusMesh")
local petShopTemplate = ServerStorage:FindFirstChild("Models") and ServerStorage.Models:FindFirstChild("PetShopKiosk")
local desertStatueTemplate = ServerStorage:FindFirstChild("Models") and ServerStorage.Models:FindFirstChild("DesertStatue")

-- ===== EGGS =====
-- Big, bright, speckled procedural eggs (built from parts, not the old re-tinted mesh whose
-- baked-in texture never actually showed the tier color) so every tier reads as a distinct,
-- colorful reward. Basic/Better get a matte speckled shell; Premium glows with a gem crown.
-- `band` is the stripe around the waist. It is the single strongest cue that this is a toy egg
-- and not a boulder, so every tier gets one, in a colour that fights its own shell rather than
-- blending into it -- Better's first speckle set was three pale blues on a violet shell and the
-- pattern simply vanished.
local EGG_TIER_STYLE = {
	Basic = {
		base = Color3.fromRGB(250, 245, 235),
		band = Color3.fromRGB(120, 205, 255),
		speckles = { Color3.fromRGB(255, 90, 90), Color3.fromRGB(90, 170, 255), Color3.fromRGB(255, 210, 60), Color3.fromRGB(120, 220, 120) },
		shellMaterial = Enum.Material.SmoothPlastic,
	},
	Better = {
		base = Color3.fromRGB(96, 74, 240),
		band = Color3.fromRGB(255, 214, 90),
		speckles = { Color3.fromRGB(120, 240, 255), Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 120, 210), Color3.fromRGB(255, 214, 90) },
		shellMaterial = Enum.Material.SmoothPlastic,
		gemColor = Color3.fromRGB(120, 220, 255),
	},
	Premium = {
		base = Color3.fromRGB(255, 175, 20),
		band = Color3.fromRGB(120, 60, 255),
		speckles = { Color3.fromRGB(255, 60, 140), Color3.fromRGB(120, 60, 255), Color3.fromRGB(60, 220, 255), Color3.fromRGB(255, 255, 255) },
		shellMaterial = Enum.Material.Neon,
		gemColor = Color3.fromRGB(255, 255, 255),
		glow = true,
	},
}

local EGG_SHELL_SIZE = Vector3.new(8, 10.5, 8)
local EGG_PIVOT_Y = 7

-- Two parts, and the second one barely shows. Roblox balls are true ellipsoids, so one stretched
-- ball is a perfectly smooth shell -- but an ellipsoid is symmetric top to bottom and an egg is
-- not. The cap fixes that: a sphere sitting high enough that its equator is *inside* the main
-- shell and only its dome pokes out, which is exactly the pointed end.
-- (Four stacked lobes were tried first. Each junction showed as a ridge and the thing read as a
-- beehive; two lobes read as a snowman. The eye catches any waist, so do not add one.)
local EGG_BODY = Vector3.new(8.2, 10.6, 8.2)
local EGG_CAP = Vector3.new(5.8, 5.8, 5.8)
local EGG_CAP_Y = 3.0

-- Builds one egg as a Model and returns the bottom lobe, which is what the caller hangs the
-- ProximityPrompt on. Speckles are few and big on purpose: fourteen small dots read as noise
-- from three studs away, eight chunky patches read as pattern.
--
-- No Highlight here, deliberately. Roblox only renders about 31 of them at once, and a place
-- with 60 eggs and 60 podium pets would blow that budget and silently kill the outline on the
-- player's own pets -- which is the one place it actually matters. See PetModel's `outline` opt.
--
-- Every piece carries its offset from the shell as a PetOffset attribute and the model is tagged
-- EggIdle, so PetFollowClient can float and rock it on each client without the server sending a
-- CFrame per frame. See the note at the top of PetFollowService.
local function buildEgg(shop, ex, tierSuffix, pivotY)
	local style = EGG_TIER_STYLE[tierSuffix] or EGG_TIER_STYLE.Basic
	local center = Vector3.new(ex, pivotY or EGG_PIVOT_Y, 0)

	local model = Instance.new("Model")
	model.Name = "Egg"

	local shell = newPart({
		Name = "EggShell",
		Shape = Enum.PartType.Ball,
		Size = EGG_BODY,
		Position = center,
		Color = style.base,
		Material = style.shellMaterial,
		CanCollide = true,
		Parent = model,
	})
	model.PrimaryPart = shell

	-- offsets are relative to the shell, because the shell is what the client moves and
	-- everything else hangs off it. `offset` may be a Vector3 or a full CFrame (the crack shards
	-- are rotated, and rotation has to survive into the attribute too).
	local function piece(props, offset)
		props.Parent = model
		props.CanCollide = false
		local p = newPart(props)
		p:SetAttribute("PetOffset", typeof(offset) == "CFrame" and offset or CFrame.new(offset))
		return p
	end

	piece({
		Name = "EggCap",
		Shape = Enum.PartType.Ball,
		Size = EGG_CAP,
		Position = center + Vector3.new(0, EGG_CAP_Y, 0),
		Color = style.base,
		Material = style.shellMaterial,
	}, Vector3.new(0, EGG_CAP_Y, 0))

	-- a squashed ball just wider than the shell: the sliver that pokes out is the stripe. Sizing
	-- it as a ring rather than drawing one on a texture keeps it correct from every angle.
	piece({
		Name = "EggBand",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(EGG_BODY.X + 0.9, 2.4, EGG_BODY.Z + 0.9),
		Position = center + Vector3.new(0, -0.6, 0),
		Color = style.band or lighten(style.base, 0.3),
		Material = Enum.Material.SmoothPlastic,
	}, Vector3.new(0, -0.6, 0))

	-- the underside, a shade darker. Without it the shell is one flat colour and the egg reads
	-- as a sticker; with it there is a bottom.
	piece({
		Name = "EggUnder",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(EGG_BODY.X - 0.15, 5.6, EGG_BODY.Z - 0.15),
		Position = center + Vector3.new(0, -2.6, 0),
		Color = darken(style.base, 0.16),
		Material = style.shellMaterial,
	}, Vector3.new(0, -2.6, 0))

	-- a zig-zag crack across the front upper third: the one shape that says "something hatches
	-- out of this". Each shard is projected onto the shell so it lies flat against the curve.
	for i = 1, 6 do
		local x = -2.4 + (i - 1) * 0.96
		local y = 1.4 + ((i % 2 == 0) and 0.42 or -0.42)
		local nx, ny = x / (EGG_BODY.X / 2), y / (EGG_BODY.Y / 2)
		local z = (EGG_BODY.Z / 2) * math.sqrt(math.max(0.04, 1 - nx * nx - ny * ny))
		local cf = CFrame.new(Vector3.new(x, y, z - 0.15)) * CFrame.Angles(0, 0, math.rad((i % 2 == 0) and 34 or -34))
		piece({
			Name = "EggCrack",
			Size = Vector3.new(1.15, 0.3, 0.5),
			CFrame = CFrame.new(center) * cf,
			Color = darken(style.base, 0.55),
			Material = Enum.Material.SmoothPlastic,
		}, cf)
	end

	-- patches sit ON the shell surface, half in and half out, biased toward +Z -- the plaza's
	-- stairs and price cards are on +Z, so that is the side a player ever looks at. (Two earlier
	-- passes lost every spot: one sank them to 0.85 of the radius, the next faced them at -Z.)
	for _ = 1, 8 do
		local dir = Vector3.new(math.random() - 0.5, (math.random() - 0.4) * 0.9, math.random() * 0.9 + 0.2)
		dir = dir.Magnitude > 0 and dir.Unit or Vector3.new(0, 0, 1)
		local offset = Vector3.new(
			dir.X * EGG_BODY.X / 2,
			dir.Y * EGG_BODY.Y / 2 * 0.94,
			dir.Z * EGG_BODY.Z / 2
		)
		local s = 1.9 + math.random() * 1.3
		piece({
			Name = "EggSpot",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(s, s * 0.78, s),
			Position = center + offset,
			Color = style.speckles[math.random(1, #style.speckles)],
			Material = Enum.Material.SmoothPlastic,
		}, offset)
	end

	-- one soft gloss blob on the shoulder does more for "shiny" than any material setting
	piece({
		Name = "EggGloss",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.3, 3.0, 1.9),
		Position = center + Vector3.new(-1.9, 2.2, 2.9),
		Color = Color3.fromRGB(255, 255, 255),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.55,
	}, Vector3.new(-1.9, 2.2, 2.9))

	if style.gemColor then
		local gem = piece({
			Name = "EggGem",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2.1, 2.1, 2.1),
			Position = center + Vector3.new(0, 6.6, 0),
			Color = style.gemColor,
			Material = Enum.Material.Neon,
		}, Vector3.new(0, 6.6, 0))
		if style.glow then
			local light = Instance.new("PointLight")
			light.Color = style.gemColor
			light.Range = 18
			light.Brightness = 2.2
			light.Parent = gem

			local sparkle = Instance.new("ParticleEmitter")
			sparkle.Color = ColorSequence.new(style.gemColor)
			sparkle.LightEmission = 1
			sparkle.Size = NumberSequence.new(0.6)
			sparkle.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.3, 0.15),
				NumberSequenceKeypoint.new(1, 1),
			})
			sparkle.Lifetime = NumberRange.new(0.8, 1.4)
			sparkle.Rate = 7
			sparkle.Speed = NumberRange.new(0.5, 1.6)
			sparkle.SpreadAngle = Vector2.new(180, 180)
			sparkle.Parent = gem
		end
	end

	-- the egg floats, and without a shadow it reads as pasted onto the sky rather than resting
	-- over its podium. Parented to the shop, not to the model, so it stays put while the egg rocks.
	newPart({
		Name = "EggShadow",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 8.6, 8.6),
		Orientation = Vector3.new(0, 0, 90),
		Position = Vector3.new(ex, (pivotY or EGG_PIVOT_Y) - EGG_SHELL_SIZE.Y / 2 + 0.12, 0),
		Color = Color3.fromRGB(12, 10, 20),
		Transparency = 0.62,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CastShadow = false,
		Parent = shop,
	})

	model:SetAttribute("IdleAnchor", shell.CFrame)
	model:SetAttribute("IdlePhase", (ex % 7) * 0.9)
	model:SetAttribute("BobHeight", 0.45)
	CollectionService:AddTag(model, "EggIdle")

	model.Parent = shop
	return shell
end

-- ===== WHAT IS INSIDE AN EGG =====
-- Every zone hatches its own five species, so the only thing that tells two eggs apart is that
-- list -- which means it belongs on the egg itself, not buried in a menu. The percentages come
-- from GameConfig.GetEggOdds, the same weights the roll uses, so the board can never advertise
-- odds the roll does not honour. Luck is passed as 0: this is the shop's baseline, and a player's
-- own luck only ever moves it in their favour.
local function buildEggOddsBoard(shop, egg, ex, y)
	local anchor = newPart({
		Name = "EggOddsAnchor",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(ex, y, 0),
		Transparency = 1,
		CanCollide = false,
		Parent = shop,
	})

	local gui = Instance.new("BillboardGui")
	gui.Name = "EggOdds"
	-- sized in studs, not pixels: a pixel-sized billboard keeps its screen size at any range, so
	-- from the far end of the plaza the three boards grew into each other and covered the eggs.
	-- In studs each board stays over its own podium. MaxDistance then does the rest of the job --
	-- you only get the odds when you walk up to the egg, and the plaza reads clean from outside.
	gui.Size = UDim2.new(9, 0, 7.2, 0)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = 34
	gui.Parent = anchor

	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 1, 0)
	card.BackgroundColor3 = Color3.fromRGB(24, 18, 34)
	card.BackgroundTransparency = 0.12
	card.BorderSizePixel = 0
	card.Parent = gui
	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0.06, 0)
	cardCorner.Parent = card
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Thickness = 3
	cardStroke.Color = Color3.fromRGB(12, 8, 18)
	cardStroke.Parent = card

	-- everything inside is in scale units too, or it would not shrink with the board
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(0.94, 0, 0.16, 0)
	title.Position = UDim2.new(0.03, 0, 0.03, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextStrokeColor3 = Color3.fromRGB(12, 8, 18)
	title.TextStrokeTransparency = 0
	title.Text = egg.emoji .. " " .. egg.tierSuffix .. " · contents"
	title.Parent = card

	local list = Instance.new("Frame")
	list.Size = UDim2.new(0.94, 0, 0.76, 0)
	list.Position = UDim2.new(0.03, 0, 0.22, 0)
	list.BackgroundTransparency = 1
	list.Parent = card
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0.02, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	for i, entry in ipairs(GameConfig.GetEggOdds(egg, 0)) do
		local rarity = GameConfig.GetRarity(entry.def.rarity)

		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0.18, 0)
		row.BackgroundColor3 = Color3.fromRGB(14, 10, 22)
		row.BackgroundTransparency = 0.25
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		row.Parent = list
		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0.25, 0)
		rowCorner.Parent = row

		-- the rarity stripe is what the eye picks up first; the percentage is the detail you
		-- came close to read
		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.new(0.022, 0, 0.7, 0)
		stripe.Position = UDim2.new(0.014, 0, 0.15, 0)
		stripe.BackgroundColor3 = rarity.color
		stripe.BorderSizePixel = 0
		stripe.Parent = row
		local stripeCorner = Instance.new("UICorner")
		stripeCorner.CornerRadius = UDim.new(0.5, 0)
		stripeCorner.Parent = stripe

		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(0.66, 0, 0.86, 0)
		name.Position = UDim2.new(0.06, 0, 0.07, 0)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.FredokaOne
		name.TextScaled = true
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextColor3 = Color3.fromRGB(255, 255, 255)
		name.TextStrokeColor3 = Color3.fromRGB(12, 8, 18)
		name.TextStrokeTransparency = 0
		name.Text = entry.def.emoji .. " " .. entry.def.name
		name.Parent = row

		local chance = Instance.new("TextLabel")
		chance.Size = UDim2.new(0.24, 0, 0.86, 0)
		chance.Position = UDim2.new(0.74, 0, 0.07, 0)
		chance.BackgroundTransparency = 1
		chance.Font = Enum.Font.FredokaOne
		chance.TextScaled = true
		chance.TextXAlignment = Enum.TextXAlignment.Right
		chance.TextColor3 = rarity.color
		chance.TextStrokeColor3 = Color3.fromRGB(12, 8, 18)
		chance.TextStrokeTransparency = 0
		chance.Text = string.format(entry.chance < 10 and "%.1f%%" or "%.0f%%", entry.chance)
		chance.Parent = row
	end

	return anchor
end

-- The rarest species of the five, floating over the podium: the pet people are actually buying
-- the egg for. Tagged rather than animated here -- a server that CFrames it every frame would
-- replicate the spin to every client at a throttled rate and stutter; PetFollowClient spins it
-- locally instead. See the note at the top of PetFollowService.
local function buildEggFeaturePet(shop, egg, ex, y)
	local pool = GameConfig.GetEggPool(egg)
	if not pool or #pool == 0 then return nil end

	local def = pool[#pool]
	local model, root, pieces = PetModel.Build(def, "Normal", { scale = 0.85, plateDistance = 110, outline = false })
	model.Name = "FeaturePet"
	PetModel.Place(root, pieces, CFrame.new(ex, y, 0))
	model:SetAttribute("SpinAnchor", CFrame.new(ex, y, 0))
	model:SetAttribute("SpinSpeed", 0.7)
	model:SetAttribute("BobHeight", 0.45)
	CollectionService:AddTag(model, "PetDisplay")
	model.Parent = shop
	return model
end

-- ===== EGG PLAZA =====
-- The shop is the first thing a player walks into in every zone, so it gets a built stage instead
-- of the old flat 54x26 slab: a two-step lit dais, a back wall carrying the EGGS banner and one
-- nameplate per tier, four pylons holding a canopy beam, and a spotlit podium under every egg.
-- Everything is laid out from the egg row on z = 0 outward, and stays inside the reserved centre
-- square (CLEAR_HALF), so no biome decoration can land on top of it.

local PLAZA_Z = -4          -- dais centre; the egg row sits 4 studs forward of it
local PLAZA_DECK_TOP = 3    -- walking surface players stand on
local PLAZA_PODIUM_TOP = 6  -- what each egg actually rests on
local EGG_SPACING = 21

local function buildEggPlaza(shop, zone, cx, eggs)
	local accent = zone.accentColor
	-- Was rgb(38,38,46). Under its own canopy that read as a black hole in the middle of a bright
	-- zone: every darken() below starts from this, so the deck, the wall and the pylons all went
	-- near-black together. A mid slate keeps the neon trim and the eggs popping without the shop
	-- swallowing the light.
	local stone = Color3.fromRGB(92, 88, 112)
	local deckW = EGG_SPACING * (#eggs - 1) + 56
	local halfW = deckW / 2
	local backZ = PLAZA_Z - 20
	local frontZ = PLAZA_Z + 20

	-- ---- dais: a wide lower step, then the deck, so it reads as raised ground, not a floating slab
	newPart({ Name = "PlazaStep", Size = Vector3.new(deckW + 18, 1.4, 48), Position = Vector3.new(cx, 0.7, PLAZA_Z), Color = darken(stone, 0.2), Material = Enum.Material.Slate, Parent = shop })
	newPart({ Name = "PlazaDeck", Size = Vector3.new(deckW, 1.6, 40), Position = Vector3.new(cx, 2.2, PLAZA_Z), Color = stone, Material = Enum.Material.Metal, Parent = shop })
	for _, dz in ipairs({ -20, 20 }) do
		newPart({ Name = "PlazaTrim", Size = Vector3.new(deckW, 0.5, 1.6), Position = Vector3.new(cx, PLAZA_DECK_TOP - 0.1, PLAZA_Z + dz), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = shop })
	end
	for _, side in ipairs({ -1, 1 }) do
		newPart({ Name = "PlazaTrim", Size = Vector3.new(1.6, 0.5, 40), Position = Vector3.new(cx + side * halfW, PLAZA_DECK_TOP - 0.1, PLAZA_Z), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = shop })
	end

	-- ---- walk-up steps at the front. Each is a solid block resting on the ground rather than a
	-- thin slab floated at height, and they get *shorter* with distance, so walking in from the
	-- arrival side is 0 -> 0.8 -> 1.6 -> 2.4 -> deck: four rises no larger than a normal step.
	for i = 1, 3 do
		local top = 2.4 - (i - 1) * 0.8
		newPart({ Name = "PlazaStair", Size = Vector3.new(34, top, 5), Position = Vector3.new(cx, top / 2, frontZ + 2.5 + (i - 1) * 5), Color = darken(stone, 0.1), Material = Enum.Material.Slate, Parent = shop })
	end

	-- ---- back wall: the banner surface. Everything readable hangs off this, which is why it is
	-- tall and flat rather than another pile of props.
	newPart({ Name = "PlazaWall", Size = Vector3.new(deckW, 30, 3.5), Position = Vector3.new(cx, 18, backZ), Color = stone, Material = Enum.Material.Metal, Parent = shop })
	newPart({ Name = "PlazaWallInlay", Size = Vector3.new(deckW - 16, 21, 1), Position = Vector3.new(cx, 17, backZ + 2), Color = darken(accent, 0.55), Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = shop })
	newPart({ Name = "PlazaWallCap", Size = Vector3.new(deckW + 8, 2.6, 6), Position = Vector3.new(cx, 34.3, backZ), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = shop })
	makeSign(shop, "🥚 EGGS", CFrame.new(cx, 24, backZ + 2.6), UDim2.new(0, 300, 0, 84))

	-- ---- four pylons + a canopy beam across the front: turns the dais into a shop frontage
	for _, side in ipairs({ -1, 1 }) do
		for _, pz in ipairs({ backZ + 2, frontZ - 2 }) do
			newPart({ Name = "PlazaPylon", Size = Vector3.new(5.5, 33, 5.5), Position = Vector3.new(cx + side * (halfW - 3), 19.5, pz), Color = darken(stone, 0.25), Material = Enum.Material.Metal, Parent = shop })
			local lamp = newPart({ Name = "PlazaLamp", Shape = Enum.PartType.Ball, Size = Vector3.new(7, 7, 7), Position = Vector3.new(cx + side * (halfW - 3), 38, pz), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = shop })
			addLight(lamp, accent, 40, 3)
		end
	end
	newPart({ Name = "PlazaBeam", Size = Vector3.new(deckW, 2.4, 5), Position = Vector3.new(cx, 37, frontZ - 2), Color = darken(stone, 0.25), Material = Enum.Material.Metal, CanCollide = false, Parent = shop })

	-- ---- bollards flanking the stairs, so the approach has a threshold. They stand on the ground
	-- beside the steps (x +/- 22 clears the 34-wide stair), not on the deck -- on the deck they
	-- would float, because the deck stops 4 studs short of where the stairs begin.
	for _, side in ipairs({ -1, 1 }) do
		newPart({ Name = "PlazaBollard", Size = Vector3.new(2.4, 9, 2.4), Position = Vector3.new(cx + side * 22, 4.5, frontZ + 4), Color = darken(stone, 0.25), Material = Enum.Material.Metal, Parent = shop })
		local knob = newPart({ Name = "PlazaBollardLamp", Shape = Enum.PartType.Ball, Size = Vector3.new(3.6, 3.6, 3.6), Position = Vector3.new(cx + side * 22, 10.5, frontZ + 4), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = shop })
		addLight(knob, accent, 20, 1.6)
	end

	-- ---- one podium per egg, each lit from above so the shell reads against the dark deck
	local startX = cx - EGG_SPACING * (#eggs - 1) / 2
	local built = {}
	for i, egg in ipairs(eggs) do
		local ex = startX + EGG_SPACING * (i - 1)

		newPart({ Name = "PodiumBase", Size = Vector3.new(13.5, 1.6, 13.5), Position = Vector3.new(ex, PLAZA_DECK_TOP + 0.8, 0), Color = darken(stone, 0.15), Material = Enum.Material.Metal, Parent = shop })
		newPart({ Name = "PodiumGlow", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 15, 15), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(ex, PLAZA_DECK_TOP + 1.7, 0), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = shop })
		newPart({ Name = "PodiumTop", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, 11, 11), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(ex, PLAZA_PODIUM_TOP - 0.7, 0), Color = lighten(stone, 0.12), Material = Enum.Material.Metal, Parent = shop })

		local eggY = PLAZA_PODIUM_TOP + EGG_SHELL_SIZE.Y / 2
		local shell = buildEgg(shop, ex, egg.tierSuffix, eggY)

		-- the rarest pet this egg can give, hovering between the shell and the halo, with the
		-- full five-species list above it. Together they are the whole answer to "what is in
		-- this egg", which is the question the three eggs on a podium exist to ask.
		buildEggFeaturePet(shop, egg, ex, eggY + 7)
		buildEggOddsBoard(shop, egg, ex, eggY + 12.5)

		-- halo above the egg doubles as the spotlight source: a bare PointLight with nothing
		-- visible making it reads as the shell glowing on its own. It sits above the featured
		-- pet so the pet reads as lit from over its head rather than clipping through the disc.
		local halo = newPart({ Name = "PodiumHalo", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.7, 13, 13), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(ex, eggY + 17, 0), Color = lighten(accent, 0.3), Material = Enum.Material.Neon, Transparency = 0.25, CanCollide = false, Parent = shop })
		addLight(halo, lighten(accent, 0.3), 26, 2.4)

		-- one price card per podium, tier and cost on two lines. Both were nearly put on the back
		-- wall, but a billboard 21 studs behind the egg renders *behind* it in screen space and
		-- the shell hides the tier name -- in front of the podium it reads like a real price tag.
		makeSign(shop, egg.emoji .. " " .. egg.tierSuffix .. "\n🧬 " .. egg.cost .. " DNA", CFrame.new(ex, PLAZA_DECK_TOP + 1.6, 9), UDim2.new(0, 170, 0, 58))

		built[i] = shell
	end

	-- The canopy, the pylons and the back wall were dropping the whole shop into shadow at every
	-- ClockTime -- and this is the one spot in a zone where players stand still and look at
	-- things. Nothing structural here casts a shadow any more, and two warm fills under the beam
	-- lift the eggs off the deck -- gently: at 1.9 they blew the shells out to flat white and the
	-- speckles disappeared, which is the opposite of the point.
	for _, d in ipairs(shop:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:sub(1, 5) == "Plaza" then
			d.CastShadow = false
		end
	end
	for _, side in ipairs({ -1, 1 }) do
		local fill = newPart({
			Name = "PlazaFill",
			Size = Vector3.new(1, 1, 1),
			Position = Vector3.new(cx + side * 14, 27, PLAZA_Z + 6),
			Transparency = 1,
			CanCollide = false,
			CastShadow = false,
			Parent = shop,
		})
		addLight(fill, Color3.fromRGB(255, 246, 220), 46, 0.8)
	end

	return built
end

decorationBuilders.Desert = function(model, zone, cx)
	-- dense field of AI-generated cacti, varied scale/rotation so it doesn't read as clones
	if desertCactusTemplate then
		for i = 1, 26 do
			local x = cx + math.random(-205, 205)
			local z = math.random(-255, 255)
			local cactus = desertCactusTemplate:Clone()
			local geom = cactus:FindFirstChild("body") and cactus.body:FindFirstChild("body_geom")
			local scale = 0.6 + math.random() * 1.1
			cactus:ScaleTo(scale)
			local halfHeight = (geom and geom.Size.Y / 2 or 7) * scale
			cactus:PivotTo(CFrame.new(x, halfHeight, z) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
			cactus.Parent = model
		end
	else
		for i = 1, 10 do
			local x = cx + math.random(-190, 190)
			local z = math.random(-230, 230)
			newPart({ Name = "Cactus", Size = Vector3.new(4, 14, 4), Position = Vector3.new(x, 7, z), Color = Color3.fromRGB(60, 120, 70), Material = Enum.Material.Grass, Parent = model })
			newPart({ Name = "CactusArm", Size = Vector3.new(3, 6, 3), Position = Vector3.new(x + 3, 10, z), Color = Color3.fromRGB(60, 120, 70), Material = Enum.Material.Grass, Parent = model })
		end
	end

	-- scattered sandstone boulders for ground-level variety
	for i = 1, 12 do
		local x = cx + math.random(-210, 210)
		local z = math.random(-260, 260)
		local s = math.random(6, 16)
		newPart({ Name = "DesertRock", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 0.7, s), Position = Vector3.new(x, s * 0.35, z), Color = Color3.fromRGB(200, 170, 120), Material = Enum.Material.Sandstone, Parent = model })
	end

	-- low dune mounds break up the flat floor
	for i = 1, 6 do
		local x = cx + math.random(-190, 190)
		local z = math.random(-240, 240)
		local s = math.random(30, 55)
		newPart({ Name = "Dune", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 0.28, s), Position = Vector3.new(x, s * 0.05, z), Color = Color3.fromRGB(225, 195, 140), Material = Enum.Material.Sand, CanCollide = false, Parent = model })
	end

	-- big statue landmark so the zone doesn't feel empty from a distance
	if desertStatueTemplate then
		local statue = desertStatueTemplate:Clone()
		local geom = statue:FindFirstChild("body") and statue.body:FindFirstChild("body_geom")
		local halfHeight = geom and geom.Size.Y / 2 or 27
		statue:PivotTo(CFrame.new(cx, halfHeight - 3, -210))
		statue.Parent = model
	end

	-- small clay pottery scattered around so there's always something nearby to look at
	for i = 1, 10 do
		local x = cx + math.random(-200, 200)
		local z = math.random(-250, 250)
		local s = math.random(3, 6)
		newPart({ Name = "Pottery", Shape = Enum.PartType.Cylinder, Size = Vector3.new(s, s * 0.8, s * 0.8), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, s * 0.4, z), Color = Color3.fromRGB(180, 110, 70), Material = Enum.Material.Brick, Parent = model })
	end

	-- drifting sand-dust for atmosphere
	local dustPart = newPart({ Name = "DustAmbience", Size = Vector3.new(PLATFORM_WIDTH - 40, 1, PLATFORM_DEPTH - 40), Position = Vector3.new(cx, 25, 0), Transparency = 1, CanCollide = false, Parent = model })
	local dust = Instance.new("ParticleEmitter")
	dust.Color = ColorSequence.new(Color3.fromRGB(220, 195, 150))
	dust.Size = NumberSequence.new(2, 4)
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(6, 10)
	dust.Rate = 8
	dust.Speed = NumberRange.new(3, 6)
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Parent = dustPart

	-- shared ground litter + lantern accents so Desert matches the layering of the other biomes
	-- (the statue above is already this zone's landmark, so no extra one is added here)
	buildBiomeBase(model, cx, {
		litter = { count = 14, colors = { Color3.fromRGB(205, 175, 125), Color3.fromRGB(178, 145, 100), Color3.fromRGB(158, 130, 96) }, minSize = 3, maxSize = 9, material = Enum.Material.Sandstone },
		glow = { count = 5, color = Color3.fromRGB(255, 200, 110), height = 16, range = 30 },
	})

	-- MID: weathered sandstone pillars, half toppled, for silhouette variety at eye level
	for _ = 1, 8 do
		local x, z = scatterPoint(cx)
		local h = math.random(9, 24)
		newPart({ Name = "BrokenPillar", Size = Vector3.new(6, h, 6), Orientation = Vector3.new(math.random(-9, 9), math.random(0, 360), math.random(-9, 9)), Position = Vector3.new(x, h / 2, z), Color = Color3.fromRGB(198, 168, 118), Material = Enum.Material.Sandstone, Parent = model })
	end
end

decorationBuilders.Ocean = function(model, zone, cx)
	local shallow = Color3.fromRGB(72, 176, 232)
	local kelpColor = Color3.fromRGB(46, 122, 86)
	local coralPalette = { Color3.fromRGB(255, 118, 138), Color3.fromRGB(255, 186, 92), Color3.fromRGB(168, 112, 255), Color3.fromRGB(110, 232, 208) }

	-- SIGNATURE: two stacked glass sheets instead of one. The low slab tints everything near the
	-- floor, the thin high one reads as the surface seen from below, so the zone looks submerged
	-- rather than merely blue. Both non-colliding -- players still walk the sand underneath.
	newPart({ Name = "Water", Size = Vector3.new(PLATFORM_WIDTH - 20, 3, PLATFORM_DEPTH - 20), Position = Vector3.new(cx, 3, 0), Color = shallow, Material = Enum.Material.Glass, Transparency = 0.42, CanCollide = false, Parent = model })
	newPart({ Name = "WaterSurface", Size = Vector3.new(PLATFORM_WIDTH - 20, 1, PLATFORM_DEPTH - 20), Position = Vector3.new(cx, 26, 0), Color = lighten(shallow, 0.3), Material = Enum.Material.Glass, Transparency = 0.68, CanCollide = false, Parent = model })

	buildBiomeBase(model, cx, {
		litter = { count = 22, name = "Shell", colors = { Color3.fromRGB(242, 228, 204), Color3.fromRGB(214, 192, 166), Color3.fromRGB(255, 206, 190) }, minSize = 2, maxSize = 6, flat = 0.42, material = Enum.Material.Sand },
		mounds = { count = 7, name = "Sandbar", color = Color3.fromRGB(236, 216, 172), material = Enum.Material.Sand, minSize = 38, maxSize = 70, flat = 0.18 },
		landmark = { style = "arch", base = Color3.fromRGB(214, 198, 172), accent = Color3.fromRGB(110, 232, 208), material = Enum.Material.Sandstone },
		atmosphere = { color = lighten(shallow, 0.55), color2 = Color3.fromRGB(255, 255, 255), height = 8, rate = 20, sizeStart = 0.6, sizeEnd = 2.4, transparency = 0.45, lifeMin = 5, lifeMax = 9, speedMin = 5, speedMax = 9, lightEmission = 0.7, acceleration = Vector3.new(0, 7, 0) },
		glow = { count = 6, color = Color3.fromRGB(94, 236, 255), height = 11, range = 26 },
	})

	-- MID: kelp forest. Segments that lean a little further with every step up are the one
	-- silhouette that sells "underwater" from across the platform.
	for _ = 1, 22 do
		local x, z = scatterPoint(cx, 200, 250)
		local segments = math.random(3, 6)
		local lean = math.random(-7, 7)
		local y = 0
		for s = 1, segments do
			local h = math.random(9, 15)
			newPart({ Name = "Kelp", Size = Vector3.new(2.4, h, 1.2), Orientation = Vector3.new(lean * s * 0.5, math.random(0, 360), lean * s), Position = Vector3.new(x + s * lean * 0.25, y + h / 2, z), Color = s % 2 == 0 and kelpColor or darken(kelpColor, 0.18), Material = Enum.Material.Grass, CanCollide = false, Parent = model })
			y = y + h - 1
		end
		local bulb = newPart({ Name = "KelpBulb", Shape = Enum.PartType.Ball, Size = Vector3.new(4, 4, 4), Position = Vector3.new(x + segments * lean * 0.25, y + 2, z), Color = Color3.fromRGB(190, 255, 150), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		if math.random(1, 4) == 1 then
			addLight(bulb, Color3.fromRGB(190, 255, 150), 14, 1.2)
		end
	end

	-- MID: coral heads and fans. The hot palette against the blue wash is what stops the seabed
	-- reading as one flat colour -- reefs are loud, not tasteful.
	for _ = 1, 16 do
		local x, z = scatterPoint(cx)
		local c = coralPalette[math.random(1, #coralPalette)]
		for i = 1, math.random(3, 5) do
			local s = math.random(5, 12)
			newPart({ Name = "Coral", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 1.3, s), Orientation = Vector3.new(math.random(-14, 14), math.random(0, 360), math.random(-14, 14)), Position = Vector3.new(x + math.random(-7, 7), s * 0.55, z + math.random(-7, 7)), Color = i % 2 == 0 and c or lighten(c, 0.25), Material = Enum.Material.Foil, CanCollide = false, Parent = model })
		end
	end
	for _ = 1, 12 do
		local x, z = scatterPoint(cx)
		local h = math.random(8, 16)
		newPart({ Name = "CoralFan", Size = Vector3.new(h * 1.2, h, 0.8), Orientation = Vector3.new(0, math.random(0, 360), math.random(-12, 12)), Position = Vector3.new(x, h / 2 + 1, z), Color = coralPalette[math.random(1, #coralPalette)], Material = Enum.Material.Neon, Transparency = 0.25, CanCollide = false, Parent = model })
	end

	-- MID: bubble vents. The drifting atmosphere above needs visible sources on the floor or the
	-- rising motion reads as unexplained fog.
	for _ = 1, 6 do
		local x, z = scatterPoint(cx)
		local vent = newPart({ Name = "BubbleVent", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 7, 7), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 1, z), Color = Color3.fromRGB(70, 70, 80), Material = Enum.Material.Rock, CanCollide = false, Parent = model })
		local bubbles = Instance.new("ParticleEmitter")
		bubbles.Color = ColorSequence.new(Color3.fromRGB(220, 245, 255))
		bubbles.Size = NumberSequence.new(0.6, 1.6)
		bubbles.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
		bubbles.Lifetime = NumberRange.new(3, 5)
		bubbles.Rate = 14
		bubbles.Speed = NumberRange.new(6, 10)
		bubbles.SpreadAngle = Vector2.new(12, 12)
		bubbles.Acceleration = Vector3.new(0, 8, 0)
		bubbles.LightEmission = 0.6
		bubbles.Parent = vent
	end

	-- MID: a half-buried wreck. One large man-made silhouette gives the open mid-field something
	-- to navigate by; parked off to the port side so it clears both the plaza and the arrival pad.
	local wx, wz = cx - 128, 96
	newPart({ Name = "WreckKeel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(74, 12, 12), Orientation = Vector3.new(0, 24, 82), Position = Vector3.new(wx, 5, wz), Color = Color3.fromRGB(84, 62, 46), Material = Enum.Material.Wood, Parent = model })
	for i = -3, 3 do
		newPart({ Name = "WreckRib", Size = Vector3.new(1.8, 22 - math.abs(i) * 3, 26), Orientation = Vector3.new(0, 24, i * 6), Position = Vector3.new(wx + i * 10, 10, wz + i * 4), Color = Color3.fromRGB(96, 72, 52), Material = Enum.Material.Wood, CanCollide = false, Parent = model })
	end
	newPart({ Name = "WreckMast", Size = Vector3.new(3, 46, 3), Orientation = Vector3.new(0, 24, 22), Position = Vector3.new(wx + 6, 24, wz + 2), Color = Color3.fromRGB(76, 56, 40), Material = Enum.Material.Wood, CanCollide = false, Parent = model })
	local lantern = newPart({ Name = "WreckLantern", Shape = Enum.PartType.Ball, Size = Vector3.new(5, 5, 5), Position = Vector3.new(wx + 14, 42, wz + 6), Color = Color3.fromRGB(120, 240, 255), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	addLight(lantern, Color3.fromRGB(120, 240, 255), 30, 2.4)
end

decorationBuilders.Volcano = function(model, zone, cx)
	local lavaColor = Color3.fromRGB(255, 108, 28)
	local hotColor = Color3.fromRGB(255, 196, 70)
	local basalt = Color3.fromRGB(44, 32, 32)
	local coneZ = -196

	-- SIGNATURE LANDMARK: the cone, hand-built instead of routed through addLandmark so it can be
	-- a real stacked mountain with a lit crater. It owns the back of the platform, which is why
	-- this builder never asks buildBiomeBase for a landmark of its own.
	local y = 0
	for i = 0, 6 do
		local w = 172 - i * 22
		local h = 15
		newPart({ Name = "VolcanoCone", Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, w, w), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(cx, y + h / 2, coneZ), Color = i % 2 == 0 and basalt or darken(basalt, 0.25), Material = Enum.Material.Basalt, Parent = model })
		y = y + h - 1
	end
	newPart({ Name = "CraterRim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(7, 46, 46), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(cx, y + 2, coneZ), Color = darken(basalt, 0.35), Material = Enum.Material.Basalt, Parent = model })
	local craterGlow = newPart({ Name = "CraterLava", Shape = Enum.PartType.Cylinder, Size = Vector3.new(5, 34, 34), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(cx, y + 5, coneZ), Color = lavaColor, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	addLight(craterGlow, lavaColor, 60, 4)

	-- smoke column plus a spray of embers arcing back down: the crater has to look like it is
	-- doing something, otherwise the mountain is just a grey cone
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(90, 78, 74), Color3.fromRGB(40, 34, 32))
	smoke.Size = NumberSequence.new(14, 42)
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(4, 7)
	smoke.Rate = 12
	smoke.Speed = NumberRange.new(14, 22)
	smoke.SpreadAngle = Vector2.new(18, 18)
	smoke.Acceleration = Vector3.new(0, 6, 0)
	smoke.Parent = craterGlow
	local embers = Instance.new("ParticleEmitter")
	embers.Color = ColorSequence.new(hotColor, lavaColor)
	embers.Size = NumberSequence.new(1.4, 0.3)
	embers.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	embers.Lifetime = NumberRange.new(2.5, 4.5)
	embers.Rate = 24
	embers.Speed = NumberRange.new(28, 46)
	embers.SpreadAngle = Vector2.new(45, 45)
	embers.Acceleration = Vector3.new(0, -22, 0)
	embers.LightEmission = 1
	embers.Parent = craterGlow

	-- SIGNATURE: lava, routed as two flows spilling off the cone toward the outer edges instead
	-- of one slab in the middle -- the plaza has to stay walkable and unlit by it.
	for _, side in ipairs({ -1, 1 }) do
		local px, pz = cx + side * 34, coneZ + 40
		for i = 1, 9 do
			local w = 16 + i * 2.5
			newPart({ Name = "LavaFlow", Size = Vector3.new(w, 1.2, 26), Orientation = Vector3.new(0, side * i * 3, 0), Position = Vector3.new(px + side * i * 12, 0.9, pz + i * 17), Color = i % 3 == 0 and hotColor or lavaColor, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
			newPart({ Name = "LavaBank", Size = Vector3.new(w + 10, 2.4, 26), Orientation = Vector3.new(0, side * i * 3, 0), Position = Vector3.new(px + side * i * 12, 0.6, pz + i * 17), Color = darken(basalt, 0.15), Material = Enum.Material.Basalt, CanCollide = false, Parent = model })
		end
	end

	-- outlying lava pools with a cooled crust ring, so the far corners glow too
	for _ = 1, 5 do
		local x, z = scatterPoint(cx, 195, 245)
		local s = math.random(22, 40)
		newPart({ Name = "PoolCrust", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, s + 9, s + 9), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 0.6, z), Color = darken(basalt, 0.1), Material = Enum.Material.Basalt, CanCollide = false, Parent = model })
		local pool = newPart({ Name = "LavaPool", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, s, s), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 1.1, z), Color = lavaColor, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(pool, lavaColor, 30, 2.2)
	end

	-- MID: basalt colonnades. Clustered hexagonal-ish pillars are the classic cooled-lava
	-- formation and give the mid-field a jagged skyline the loose boulders never produced.
	for _ = 1, 10 do
		local x, z = scatterPoint(cx)
		for i = 1, math.random(4, 7) do
			local h = math.random(12, 34)
			newPart({ Name = "BasaltColumn", Size = Vector3.new(6, h, 6), Orientation = Vector3.new(0, math.random(0, 360), 0), Position = Vector3.new(x + math.random(-9, 9), h / 2, z + math.random(-9, 9)), Color = i % 2 == 0 and basalt or lighten(basalt, 0.12), Material = Enum.Material.Basalt, Parent = model })
		end
	end

	-- MID: fissures. Cracks of light in the floor make the ground itself look like it is barely
	-- holding, which no amount of dark rock on top of dark rock can do.
	for _ = 1, 16 do
		local x, z = scatterPoint(cx, 200, 250)
		newPart({ Name = "Fissure", Size = Vector3.new(math.random(18, 46), 0.6, math.random(2, 5)), Orientation = Vector3.new(0, math.random(0, 360), 0), Position = Vector3.new(x, 0.4, z), Color = hotColor, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	end

	-- MID: obsidian spikes at eye level, glassy and near-black so they read as silhouette
	for _ = 1, 12 do
		local x, z = scatterPoint(cx)
		local h = math.random(10, 26)
		newPart({ Name = "ObsidianSpike", Size = Vector3.new(5, h, 5), Orientation = Vector3.new(math.random(-16, 16), math.random(0, 360), math.random(-16, 16)), Position = Vector3.new(x, h / 2, z), Color = Color3.fromRGB(22, 16, 22), Material = Enum.Material.Glass, Parent = model })
	end

	buildBiomeBase(model, cx, {
		litter = { count = 20, name = "LavaRock", colors = { Color3.fromRGB(46, 34, 34), Color3.fromRGB(30, 22, 22), Color3.fromRGB(70, 42, 34) }, minSize = 4, maxSize = 13, material = Enum.Material.Basalt },
		mounds = { count = 5, name = "AshMound", color = Color3.fromRGB(58, 48, 46), material = Enum.Material.Slate, minSize = 30, maxSize = 58 },
		atmosphere = { color = Color3.fromRGB(255, 150, 60), color2 = Color3.fromRGB(120, 40, 20), height = 34, rate = 16, sizeStart = 1.2, sizeEnd = 0.4, transparency = 0.3, lifeMin = 4, lifeMax = 8, speedMin = 3, speedMax = 7, lightEmission = 1, acceleration = Vector3.new(0, 5, 0) },
		glow = { count = 5, color = Color3.fromRGB(255, 130, 50), height = 14, range = 30, brightness = 2.5 },
	})
end

decorationBuilders.Moon = function(model, zone, cx)
	local regolith = Color3.fromRGB(178, 178, 184)
	local shadow = Color3.fromRGB(96, 96, 104)

	buildBiomeBase(model, cx, {
		litter = { count = 24, name = "MoonRock", colors = { regolith, shadow, Color3.fromRGB(146, 146, 152) }, minSize = 3, maxSize = 12, material = Enum.Material.Slate },
		mounds = { count = 6, name = "RegolithMound", color = Color3.fromRGB(158, 158, 166), material = Enum.Material.Slate, minSize = 34, maxSize = 64, flat = 0.2 },
		landmark = { style = "orb", base = Color3.fromRGB(120, 120, 130), accent = Color3.fromRGB(150, 200, 255), coreColor = Color3.fromRGB(58, 118, 210), material = Enum.Material.Slate },
		atmosphere = { color = Color3.fromRGB(220, 220, 235), height = 12, rate = 5, sizeStart = 0.5, sizeEnd = 1.6, transparency = 0.75, lifeMin = 7, lifeMax = 12, speedMin = 0.5, speedMax = 2, lightEmission = 0.3 },
		glow = { count = 6, color = Color3.fromRGB(210, 235, 255), height = 13, range = 26 },
	})

	-- the landmark orb is Earth hanging over the horizon; a few continent patches stop it reading
	-- as a plain blue ball, which is the whole reason it works as a "you are on the Moon" cue
	for i = 1, 5 do
		local a = (i / 5) * math.pi * 2
		local s = math.random(11, 19)
		newPart({ Name = "EarthContinent", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 0.5, s), Orientation = Vector3.new(math.random(-40, 40), math.random(0, 360), math.random(-40, 40)), Position = Vector3.new(cx + math.cos(a) * 19, 82 + math.sin(a) * 13, -210 + math.random(-6, 6)), Color = Color3.fromRGB(70, 160, 90), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	end

	-- SIGNATURE: craters, rebuilt as a sunken dark floor ringed by thrown-up rubble. The old flat
	-- disc vanished the moment you stood next to it; a rim you can see edge-on does not.
	for _ = 1, 9 do
		local x, z = scatterPoint(cx, 200, 250)
		local r = math.random(12, 30)
		newPart({ Name = "Crater", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.5, r * 2, r * 2), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 0.4, z), Color = Color3.fromRGB(78, 78, 86), Material = Enum.Material.Slate, CanCollide = false, Parent = model })
		local rimCount = 10 + math.floor(r / 4)
		for i = 1, rimCount do
			local a = (i / rimCount) * math.pi * 2
			local s = math.random(4, 8)
			newPart({ Name = "CraterRim", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 0.55, s), Orientation = Vector3.new(0, math.random(0, 360), 0), Position = Vector3.new(x + math.cos(a) * r, s * 0.2, z + math.sin(a) * r), Color = regolith, Material = Enum.Material.Slate, CanCollide = false, Parent = model })
		end
	end

	-- MID: a landed module and its flag. One built object is worth twenty more rocks here --
	-- it is the only thing that gives the grey plain a sense of scale.
	local lx, lz = cx + 118, 92
	newPart({ Name = "LanderBody", Size = Vector3.new(20, 12, 20), Orientation = Vector3.new(0, 22, 0), Position = Vector3.new(lx, 14, lz), Color = Color3.fromRGB(228, 210, 150), Material = Enum.Material.Foil, Parent = model })
	newPart({ Name = "LanderCabin", Size = Vector3.new(13, 11, 13), Orientation = Vector3.new(0, 22, 0), Position = Vector3.new(lx, 25, lz), Color = Color3.fromRGB(200, 200, 210), Material = Enum.Material.Metal, Parent = model })
	for i = 1, 4 do
		local a = math.rad(45 + i * 90)
		newPart({ Name = "LanderLeg", Size = Vector3.new(1.6, 18, 1.6), Orientation = Vector3.new(math.cos(a) * 22, 0, math.sin(a) * 22), Position = Vector3.new(lx + math.cos(a) * 13, 7, lz + math.sin(a) * 13), Color = Color3.fromRGB(150, 150, 160), Material = Enum.Material.Metal, CanCollide = false, Parent = model })
		newPart({ Name = "LanderFoot", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 7, 7), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(lx + math.cos(a) * 17, 0.8, lz + math.sin(a) * 17), Color = Color3.fromRGB(130, 130, 140), Material = Enum.Material.Metal, CanCollide = false, Parent = model })
	end
	local beacon = newPart({ Name = "LanderBeacon", Shape = Enum.PartType.Ball, Size = Vector3.new(4.5, 4.5, 4.5), Position = Vector3.new(lx, 32, lz), Color = Color3.fromRGB(255, 90, 90), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	addLight(beacon, Color3.fromRGB(255, 90, 90), 26, 2)
	newPart({ Name = "FlagPole", Size = Vector3.new(0.9, 26, 0.9), Position = Vector3.new(lx + 24, 13, lz + 8), Color = Color3.fromRGB(220, 220, 225), Material = Enum.Material.Metal, CanCollide = false, Parent = model })
	newPart({ Name = "Flag", Size = Vector3.new(0.4, 8, 13), Position = Vector3.new(lx + 24, 22, lz + 15), Color = Color3.fromRGB(224, 70, 70), Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })

	-- MID: a dish array pointed at the sky, so the mid-ground carries a second built read
	for i = 1, 3 do
		local dx = cx - 150 + i * 26
		newPart({ Name = "DishMast", Size = Vector3.new(2.2, 20, 2.2), Position = Vector3.new(dx, 10, -108), Color = Color3.fromRGB(140, 140, 150), Material = Enum.Material.Metal, CanCollide = false, Parent = model })
		newPart({ Name = "Dish", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 18, 18), Orientation = Vector3.new(38, 0, 90), Position = Vector3.new(dx, 22, -108), Color = Color3.fromRGB(226, 226, 232), Material = Enum.Material.Foil, CanCollide = false, Parent = model })
	end

	-- MID: pebbles hanging just off the ground. Low gravity costs nothing to imply and it is the
	-- one thing that makes the Moon feel unlike Mars two zones later.
	for _ = 1, 22 do
		local x, z = scatterPoint(cx, 200, 250)
		local s = math.random(2, 5)
		newPart({ Name = "FloatingPebble", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s, s), Orientation = Vector3.new(math.random(0, 360), math.random(0, 360), 0), Position = Vector3.new(x, math.random(4, 16), z), Color = shadow, Material = Enum.Material.Slate, CanCollide = false, Parent = model })
	end

	-- MID: boulder piles at eye level so the horizon is not a perfectly clean line
	for _ = 1, 10 do
		local x, z = scatterPoint(cx)
		for i = 1, math.random(3, 6) do
			local s = math.random(8, 18)
			newPart({ Name = "MoonBoulder", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 0.85, s * 0.95), Orientation = Vector3.new(math.random(-20, 20), math.random(0, 360), math.random(-20, 20)), Position = Vector3.new(x + math.random(-11, 11), s * 0.4, z + math.random(-11, 11)), Color = i % 2 == 0 and regolith or shadow, Material = Enum.Material.Slate, Parent = model })
		end
	end
end

decorationBuilders.Mars = function(model, zone, cx)
	local rust = Color3.fromRGB(178, 88, 56)
	local dark = Color3.fromRGB(112, 54, 38)
	local ember = Color3.fromRGB(255, 148, 84)

	buildBiomeBase(model, cx, {
		litter = { count = 24, name = "MarsRock", colors = { rust, dark, Color3.fromRGB(148, 74, 50) }, minSize = 3, maxSize = 12, material = Enum.Material.Rock },
		mounds = { count = 6, name = "DustRidge", color = Color3.fromRGB(196, 108, 72), material = Enum.Material.Sand, minSize = 36, maxSize = 68, flat = 0.22 },
		landmark = { style = "spire", base = dark, accent = ember, material = Enum.Material.Rock },
		atmosphere = { color = Color3.fromRGB(228, 152, 104), color2 = Color3.fromRGB(150, 82, 58), height = 30, rate = 14, sizeStart = 3, sizeEnd = 7, transparency = 0.55, lifeMin = 6, lifeMax = 11, speedMin = 4, speedMax = 9 },
		glow = { count = 5, color = ember, height = 15, range = 28 },
	})

	-- MID: mesas. Flat-topped stacks with visible strata are the one silhouette that separates
	-- Mars from the Moon two zones back -- rounded boulders alone read identically at distance.
	for _ = 1, 6 do
		local x, z = scatterPoint(cx, 190, 240)
		local y = 0
		local w = math.random(34, 58)
		for i = 1, math.random(3, 5) do
			local h = math.random(7, 13)
			newPart({ Name = "Mesa", Size = Vector3.new(w, h, w * (0.75 + math.random() * 0.4)), Orientation = Vector3.new(0, math.random(0, 360), 0), Position = Vector3.new(x, y + h / 2, z), Color = i % 2 == 0 and rust or dark, Material = Enum.Material.Rock, Parent = model })
			y = y + h
			w = w - math.random(5, 10)
			if w < 12 then break end
		end
	end

	-- MID: dry channels cut into the floor. Long, thin and darker than the ground, so the plain
	-- reads as eroded terrain rather than a poured slab with rocks on it.
	for _ = 1, 14 do
		local x, z = scatterPoint(cx, 200, 250)
		newPart({ Name = "DryChannel", Size = Vector3.new(math.random(30, 80), 0.5, math.random(5, 12)), Orientation = Vector3.new(0, math.random(0, 360), 0), Position = Vector3.new(x, 0.3, z), Color = darken(dark, 0.35), Material = Enum.Material.Rock, CanCollide = false, Parent = model })
	end

	-- MID: dust devils. Thin, tall and moving -- the only vertical motion on an otherwise static
	-- plain, and cheap: one anchored column carrying the emitter.
	for _ = 1, 5 do
		local x, z = scatterPoint(cx, 195, 245)
		local column = newPart({ Name = "DustDevil", Size = Vector3.new(6, 44, 6), Position = Vector3.new(x, 22, z), Transparency = 1, CanCollide = false, Parent = model })
		local swirl = Instance.new("ParticleEmitter")
		swirl.Color = ColorSequence.new(Color3.fromRGB(226, 158, 112), Color3.fromRGB(160, 92, 62))
		swirl.Size = NumberSequence.new(3, 9)
		swirl.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		swirl.Lifetime = NumberRange.new(2.5, 4)
		swirl.Rate = 22
		swirl.Speed = NumberRange.new(2, 5)
		swirl.SpreadAngle = Vector2.new(14, 14)
		swirl.Acceleration = Vector3.new(0, 9, 0)
		swirl.Parent = column
	end

	-- MID: a rover and its solar array. One built object gives the plain a sense of scale that
	-- no amount of extra rock can, and marks Mars as "visited" rather than merely red.
	local rx, rz = cx - 124, 88
	newPart({ Name = "RoverDeck", Size = Vector3.new(22, 5, 13), Orientation = Vector3.new(0, 18, 0), Position = Vector3.new(rx, 8, rz), Color = Color3.fromRGB(228, 222, 208), Material = Enum.Material.Foil, Parent = model })
	newPart({ Name = "RoverMast", Size = Vector3.new(1.8, 13, 1.8), Position = Vector3.new(rx + 6, 17, rz), Color = Color3.fromRGB(150, 150, 158), Material = Enum.Material.Metal, CanCollide = false, Parent = model })
	local cam = newPart({ Name = "RoverEye", Shape = Enum.PartType.Ball, Size = Vector3.new(3.4, 3.4, 3.4), Position = Vector3.new(rx + 6, 24, rz), Color = Color3.fromRGB(120, 220, 255), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	addLight(cam, Color3.fromRGB(120, 220, 255), 22, 2)
	for _, side in ipairs({ -1, 1 }) do
		newPart({ Name = "RoverPanel", Size = Vector3.new(18, 0.7, 11), Orientation = Vector3.new(0, 18, side * 9), Position = Vector3.new(rx, 12, rz + side * 12), Color = Color3.fromRGB(46, 62, 140), Material = Enum.Material.Glass, CanCollide = false, Parent = model })
		for i = -1, 1, 2 do
			newPart({ Name = "RoverWheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 8, 8), Orientation = Vector3.new(0, 108, 0), Position = Vector3.new(rx + i * 8, 4, rz + side * 7), Color = Color3.fromRGB(60, 60, 66), Material = Enum.Material.Metal, CanCollide = false, Parent = model })
		end
	end

	-- MID: frost patches. A cold colour scattered through the rust keeps the palette from going
	-- monochrome, which is what made the old red-ball version look flat.
	for _ = 1, 9 do
		local x, z = scatterPoint(cx, 200, 250)
		local s = math.random(10, 24)
		newPart({ Name = "FrostPatch", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, s, s), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 0.4, z), Color = Color3.fromRGB(214, 236, 255), Material = Enum.Material.Ice, Transparency = 0.2, CanCollide = false, Parent = model })
	end
end

decorationBuilders.Galaxy = function(model, zone, cx)
	local violet = Color3.fromRGB(140, 90, 220)
	local cyan = Color3.fromRGB(120, 200, 255)
	local starPalette = { Color3.fromRGB(255, 255, 225), Color3.fromRGB(190, 215, 255), Color3.fromRGB(255, 200, 170) }

	buildBiomeBase(model, cx, {
		litter = { count = 20, name = "Meteorite", colors = { Color3.fromRGB(52, 40, 78), Color3.fromRGB(78, 58, 118), Color3.fromRGB(34, 26, 54) }, minSize = 3, maxSize = 11, material = Enum.Material.Slate },
		mounds = { count = 5, name = "StardustDrift", color = Color3.fromRGB(84, 58, 130), material = Enum.Material.Foil, minSize = 34, maxSize = 64, flat = 0.2 },
		landmark = { style = "ring", base = Color3.fromRGB(58, 42, 92), accent = violet, coreColor = Color3.fromRGB(255, 240, 200), material = Enum.Material.Foil },
		atmosphere = { color = lighten(violet, 0.4), color2 = cyan, height = 40, rate = 16, sizeStart = 0.5, sizeEnd = 2.2, transparency = 0.35, lifeMin = 7, lifeMax = 13, speedMin = 1, speedMax = 4, lightEmission = 1 },
		glow = { count = 6, color = cyan, height = 16, range = 30 },
	})

	-- SIGNATURE: a dense star field overhead. Small, varied and high, so looking up actually
	-- reads as space -- the old 30 identical dots at head height read as floating litter.
	for _ = 1, 90 do
		local x, z = scatterPoint(cx, 205, 255)
		local s = 1 + math.random() * 2.6
		newPart({ Name = "Star", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s, s), Position = Vector3.new(x, math.random(40, 115), z), Color = starPalette[math.random(1, #starPalette)], Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	end

	-- MID: floating asteroid islands. Rock underside, lit crystal crown -- gives the empty air
	-- between floor and stars something to read, and the zone its "you are in orbit" cue.
	for _ = 1, 9 do
		local x, z = scatterPoint(cx, 190, 240)
		local y = math.random(26, 62)
		local w = math.random(16, 34)
		newPart({ Name = "AsteroidTop", Size = Vector3.new(w, 5, w * 0.85), Orientation = Vector3.new(math.random(-6, 6), math.random(0, 360), math.random(-6, 6)), Position = Vector3.new(x, y, z), Color = Color3.fromRGB(64, 48, 96), Material = Enum.Material.Foil, CanCollide = false, Parent = model })
		newPart({ Name = "AsteroidKeel", Shape = Enum.PartType.Ball, Size = Vector3.new(w * 0.8, w * 0.9, w * 0.7), Position = Vector3.new(x, y - w * 0.4, z), Color = Color3.fromRGB(42, 32, 66), Material = Enum.Material.Slate, CanCollide = false, Parent = model })
		for i = 1, math.random(2, 4) do
			local h = math.random(6, 14)
			local crystal = newPart({ Name = "AsteroidCrystal", Size = Vector3.new(2.6, h, 2.6), Orientation = Vector3.new(math.random(-14, 14), math.random(0, 360), math.random(-14, 14)), Position = Vector3.new(x + math.random(-7, 7), y + 2.5 + h / 2, z + math.random(-7, 7)), Color = i % 2 == 0 and cyan or violet, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
			if i == 1 then
				addLight(crystal, cyan, 24, 2)
			end
		end
	end

	-- MID: nebula ribbons. Long translucent sheets at shallow angles do what a particle field
	-- cannot -- give the sky structure you can navigate by.
	for _ = 1, 10 do
		local x, z = scatterPoint(cx, 195, 245)
		newPart({ Name = "NebulaRibbon", Size = Vector3.new(math.random(60, 130), 1.4, math.random(18, 40)), Orientation = Vector3.new(math.random(-18, 18), math.random(0, 360), math.random(-12, 12)), Position = Vector3.new(x, math.random(30, 80), z), Color = math.random(1, 2) == 1 and violet or Color3.fromRGB(220, 110, 220), Material = Enum.Material.Neon, Transparency = 0.72, CanCollide = false, Parent = model })
	end

	-- MID: a ringed gas giant low at the back. One enormous object fixes the sense of distance
	-- that scattered small props keep destroying.
	local px, pz = cx + 96, -224
	local planet = newPart({ Name = "GasGiant", Shape = Enum.PartType.Ball, Size = Vector3.new(88, 88, 88), Position = Vector3.new(px, 78, pz), Color = Color3.fromRGB(196, 140, 96), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	addLight(planet, Color3.fromRGB(255, 190, 130), 70, 2.4)
	for i = 1, 3 do
		newPart({ Name = "GiantRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 118 + i * 20, 118 + i * 20), Orientation = Vector3.new(16, 0, 90), Position = Vector3.new(px, 78, pz), Color = i == 2 and Color3.fromRGB(255, 226, 180) or Color3.fromRGB(206, 168, 128), Material = Enum.Material.Neon, Transparency = 0.4 + i * 0.12, CanCollide = false, Parent = model })
	end

	-- MID: launch pylons at eye level, so the floor is not just a dark plane under a busy sky
	for _ = 1, 10 do
		local x, z = scatterPoint(cx)
		local h = math.random(12, 28)
		newPart({ Name = "StarPylon", Size = Vector3.new(3.4, h, 3.4), Orientation = Vector3.new(0, math.random(0, 360), 0), Position = Vector3.new(x, h / 2, z), Color = Color3.fromRGB(52, 40, 82), Material = Enum.Material.Metal, Parent = model })
		local tip = newPart({ Name = "StarPylonTip", Shape = Enum.PartType.Ball, Size = Vector3.new(5, 5, 5), Position = Vector3.new(x, h + 2, z), Color = violet, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(tip, violet, 20, 1.6)
	end
end

decorationBuilders.BlackHole = function(model, zone, cx)
	local plasma = Color3.fromRGB(180, 80, 240)
	local hot = Color3.fromRGB(255, 170, 90)
	local shell = Color3.fromRGB(26, 20, 34)
	local coreZ = -196

	-- SIGNATURE LANDMARK: the hole itself, hand-built rather than routed through addLandmark so
	-- the accretion disc can be a real tilted stack of rings around a pure-black sphere. It owns
	-- the back of the platform, which is why buildBiomeBase below is asked for no landmark.
	local core = newPart({ Name = "EventHorizon", Shape = Enum.PartType.Ball, Size = Vector3.new(64, 64, 64), Position = Vector3.new(cx, 86, coreZ), Color = Color3.fromRGB(0, 0, 0), Material = Enum.Material.SmoothPlastic, Reflectance = 0, CanCollide = false, Parent = model })
	for i = 1, 5 do
		local d = 96 + i * 26
		local ring = newPart({ Name = "AccretionRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.4, d, d), Orientation = Vector3.new(22, 0, 90), Position = Vector3.new(cx, 86, coreZ), Color = i <= 2 and hot or plasma, Material = Enum.Material.Neon, Transparency = 0.15 + i * 0.11, CanCollide = false, Parent = model })
		if i == 1 then
			addLight(ring, hot, 80, 4)
		end
	end
	-- photon ring: one bright thin circle right at the horizon is what makes the black sphere
	-- read as a hole rather than as a dark ball
	newPart({ Name = "PhotonRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 74, 74), Orientation = Vector3.new(22, 0, 90), Position = Vector3.new(cx, 86, coreZ), Color = Color3.fromRGB(255, 240, 220), Material = Enum.Material.Neon, CanCollide = false, Parent = model })

	-- twin polar jets, the classic silhouette, plus infalling motes so the core looks like it is
	-- eating rather than just sitting there
	for _, dir in ipairs({ 1, -1 }) do
		newPart({ Name = "PolarJet", Shape = Enum.PartType.Cylinder, Size = Vector3.new(86, 11, 11), Orientation = Vector3.new(0, 0, 90 + dir * 22), Position = Vector3.new(cx - dir * 17, 86 + dir * 62, coreZ), Color = Color3.fromRGB(220, 200, 255), Material = Enum.Material.Neon, Transparency = 0.35, CanCollide = false, Parent = model })
	end
	local infall = Instance.new("ParticleEmitter")
	infall.Color = ColorSequence.new(hot, plasma)
	infall.Size = NumberSequence.new(3.4, 0.2)
	infall.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	infall.Lifetime = NumberRange.new(2, 3.4)
	infall.Rate = 40
	infall.Speed = NumberRange.new(-34, -22)
	infall.SpreadAngle = Vector2.new(180, 180)
	infall.LightEmission = 1
	infall.Parent = core

	buildBiomeBase(model, cx, {
		litter = { count = 22, name = "Debris", colors = { shell, Color3.fromRGB(44, 32, 58), Color3.fromRGB(14, 10, 18) }, minSize = 3, maxSize = 12, material = Enum.Material.Slate },
		mounds = { count = 4, name = "CollapsedRidge", color = Color3.fromRGB(30, 24, 40), material = Enum.Material.Slate, minSize = 32, maxSize = 60, flat = 0.2 },
		atmosphere = { color = plasma, color2 = Color3.fromRGB(60, 20, 90), height = 36, rate = 18, sizeStart = 2.4, sizeEnd = 0.4, transparency = 0.4, lifeMin = 4, lifeMax = 8, speedMin = 6, speedMax = 12, lightEmission = 1 },
		glow = { count = 5, color = plasma, height = 16, range = 30, brightness = 2.6 },
	})

	-- MID: debris streams. Long thin shards all aimed at the core turn the empty floor into
	-- something with a direction -- everything here is falling the same way.
	for _ = 1, 26 do
		local x, z = scatterPoint(cx, 200, 250)
		local dx, dz = cx - x, coreZ - z
		local yaw = math.deg(math.atan2(dx, dz))
		newPart({ Name = "DebrisStreak", Size = Vector3.new(2.2, 2.2, math.random(20, 52)), Orientation = Vector3.new(math.random(-8, 8), yaw, math.random(-30, 30)), Position = Vector3.new(x, math.random(6, 46), z), Color = math.random(1, 3) == 1 and hot or plasma, Material = Enum.Material.Neon, Transparency = 0.3, CanCollide = false, Parent = model })
	end

	-- MID: gravity wells punched into the floor, each a dark disc inside a lit rim
	for _ = 1, 8 do
		local x, z = scatterPoint(cx, 195, 245)
		local r = math.random(14, 30)
		newPart({ Name = "GravityWell", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, r * 2, r * 2), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 0.4, z), Color = Color3.fromRGB(6, 4, 10), Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
		local rim = newPart({ Name = "WellRim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.7, r * 2 + 7, r * 2 + 7), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 0.3, z), Color = plasma, Material = Enum.Material.Neon, Transparency = 0.25, CanCollide = false, Parent = model })
		addLight(rim, plasma, 26, 2)
	end

	-- MID: torn structures. Broken man-made frames make the destruction legible -- bare rock
	-- being pulled apart looks the same as bare rock sitting still.
	for _ = 1, 8 do
		local x, z = scatterPoint(cx)
		for i = 1, math.random(3, 5) do
			local h = math.random(14, 38)
			newPart({ Name = "TornGirder", Size = Vector3.new(2.6, h, 2.6), Orientation = Vector3.new(math.random(-38, 38), math.random(0, 360), math.random(-38, 38)), Position = Vector3.new(x + math.random(-12, 12), h / 2 + math.random(0, 8), z + math.random(-12, 12)), Color = Color3.fromRGB(58, 48, 70), Material = Enum.Material.Metal, Parent = model })
		end
	end

	-- MID: lensing arcs. Thin bright bands stretched around the core are the visual shorthand for
	-- bent light, and they fill the mid-air band the jets leave empty.
	for i = 1, 7 do
		local a = (i / 7) * math.pi * 2
		newPart({ Name = "LensArc", Size = Vector3.new(math.random(70, 130), 1.1, 1.1), Orientation = Vector3.new(0, math.deg(a), math.random(-40, 40)), Position = Vector3.new(cx + math.cos(a) * 84, 60 + math.sin(a) * 34, coreZ + 62), Color = Color3.fromRGB(230, 220, 255), Material = Enum.Material.Neon, Transparency = 0.5, CanCollide = false, Parent = model })
	end
end

decorationBuilders.Multiverse = function(model, zone, cx)
	local pink = Color3.fromRGB(255, 100, 220)
	local palette = { Color3.fromRGB(255, 90, 200), Color3.fromRGB(90, 200, 255), Color3.fromRGB(255, 220, 90), Color3.fromRGB(150, 90, 255), Color3.fromRGB(110, 255, 170) }
	-- fragments of the biomes the player already walked through: the one prop that says
	-- "every world at once" better than any amount of abstract neon
	local fragments = {
		{ color = Color3.fromRGB(88, 156, 84), material = Enum.Material.Grass },
		{ color = Color3.fromRGB(230, 200, 120), material = Enum.Material.Sand },
		{ color = Color3.fromRGB(72, 176, 232), material = Enum.Material.Glass },
		{ color = Color3.fromRGB(255, 108, 28), material = Enum.Material.Neon },
		{ color = Color3.fromRGB(178, 178, 184), material = Enum.Material.Slate },
		{ color = Color3.fromRGB(178, 88, 56), material = Enum.Material.Rock },
	}

	buildBiomeBase(model, cx, {
		litter = { count = 20, name = "RealityChip", colors = palette, minSize = 2, maxSize = 7, shape = Enum.PartType.Block, flat = 1, material = Enum.Material.Neon, transparency = 0.25 },
		mounds = { count = 5, name = "VoidMound", color = Color3.fromRGB(30, 28, 44), material = Enum.Material.Slate, minSize = 32, maxSize = 62, flat = 0.22 },
		landmark = { style = "arch", base = Color3.fromRGB(42, 38, 58), accent = pink, material = Enum.Material.Metal },
		atmosphere = { color = pink, color2 = Color3.fromRGB(110, 200, 255), height = 34, rate = 18, sizeStart = 1, sizeEnd = 3.4, transparency = 0.4, lifeMin = 5, lifeMax = 10, speedMin = 2, speedMax = 6, lightEmission = 1 },
		glow = { count = 6, color = pink, height = 16, range = 30 },
	})

	-- SIGNATURE: free-standing doorways, each opening onto a different colour. A framed door is
	-- read as a way through instantly; the old bare rings read as scenery.
	for _ = 1, 12 do
		local x, z = scatterPoint(cx, 195, 245)
		local c = palette[math.random(1, #palette)]
		local h = math.random(22, 34)
		local w = h * 0.62
		local yaw = math.random(0, 360)
		local rot = CFrame.Angles(0, math.rad(yaw), 0)
		local base = CFrame.new(x, 0, z)
		for _, side in ipairs({ -1, 1 }) do
			local leg = newPart({ Name = "DoorJamb", Size = Vector3.new(2.6, h, 3.4), Color = Color3.fromRGB(46, 40, 62), Material = Enum.Material.Metal, Parent = model })
			leg.CFrame = base * rot * CFrame.new(side * w / 2, h / 2, 0)
		end
		local lintel = newPart({ Name = "DoorLintel", Size = Vector3.new(w + 5, 3, 4), Color = c, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		lintel.CFrame = base * rot * CFrame.new(0, h + 1, 0)
		local fill = newPart({ Name = "DoorPortal", Size = Vector3.new(w - 1, h - 2, 0.6), Color = c, Material = Enum.Material.Neon, Transparency = 0.28, CanCollide = false, Parent = model })
		fill.CFrame = base * rot * CFrame.new(0, h / 2, 0)
		addLight(fill, c, 26, 2.2)
	end

	-- MID: floating fragments of other worlds, drifting at head height and above
	for _ = 1, 16 do
		local x, z = scatterPoint(cx, 195, 245)
		local f = fragments[math.random(1, #fragments)]
		local s = math.random(9, 22)
		newPart({ Name = "WorldFragment", Size = Vector3.new(s, s * (0.5 + math.random() * 0.5), s * 0.9), Orientation = Vector3.new(math.random(-25, 25), math.random(0, 360), math.random(-25, 25)), Position = Vector3.new(x, math.random(14, 58), z), Color = f.color, Material = f.material, CanCollide = false, Parent = model })
	end

	-- MID: reality tears. Jagged bright slits in the air, angled every which way, so the space
	-- itself looks damaged rather than merely decorated.
	for _ = 1, 18 do
		local x, z = scatterPoint(cx, 200, 250)
		newPart({ Name = "RealityTear", Size = Vector3.new(0.6, math.random(12, 34), math.random(2, 5)), Orientation = Vector3.new(math.random(-40, 40), math.random(0, 360), math.random(-40, 40)), Position = Vector3.new(x, math.random(8, 52), z), Color = palette[math.random(1, #palette)], Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	end

	-- MID: a checkerboard of mismatched ground tiles under it all -- the floor is stitched
	-- together from several realities too, not one clean slab
	for _ = 1, 22 do
		local x, z = scatterPoint(cx, 200, 250)
		local f = fragments[math.random(1, #fragments)]
		local s = math.random(14, 32)
		newPart({ Name = "StitchedTile", Size = Vector3.new(s, 0.6, s * (0.7 + math.random() * 0.6)), Orientation = Vector3.new(0, math.random(0, 360), 0), Position = Vector3.new(x, 0.4, z), Color = f.color, Material = f.material, CanCollide = false, Parent = model })
	end
end

decorationBuilders.Nebula = function(model, zone, cx)
	local magenta = Color3.fromRGB(224, 120, 236)
	local azure = Color3.fromRGB(120, 180, 255)
	local palette = { magenta, azure, Color3.fromRGB(200, 120, 255), Color3.fromRGB(255, 170, 210) }

	buildBiomeBase(model, cx, {
		litter = { count = 20, name = "Cinder", colors = { Color3.fromRGB(96, 50, 130), Color3.fromRGB(70, 38, 102), Color3.fromRGB(132, 72, 168) }, minSize = 3, maxSize = 11, material = Enum.Material.Foil },
		mounds = { count = 6, name = "DustBank", color = Color3.fromRGB(112, 58, 152), material = Enum.Material.Foil, minSize = 36, maxSize = 68, flat = 0.22 },
		landmark = { style = "crystal", base = Color3.fromRGB(88, 46, 124), accent = magenta, material = Enum.Material.Foil },
		atmosphere = { color = magenta, color2 = azure, height = 44, rate = 26, sizeStart = 6, sizeEnd = 16, transparency = 0.62, lifeMin = 8, lifeMax = 14, speedMin = 1, speedMax = 4, lightEmission = 0.9 },
		glow = { count = 6, color = azure, height = 16, range = 30 },
	})

	-- SIGNATURE: gas pillars. Stacked translucent columns rising past the wall height are the
	-- one silhouette that says "star nursery" -- loose spheres just read as scattered balloons.
	for _ = 1, 5 do
		local x, z = scatterPoint(cx, 175, 230)
		local y = 0
		local w = math.random(30, 46)
		local c = palette[math.random(1, #palette)]
		for i = 1, math.random(5, 8) do
			local h = math.random(16, 26)
			newPart({ Name = "GasPillar", Shape = Enum.PartType.Ball, Size = Vector3.new(w, h, w * 0.9), Orientation = Vector3.new(0, math.random(0, 360), 0), Position = Vector3.new(x + math.random(-5, 5), y + h / 2, z + math.random(-5, 5)), Color = i % 2 == 0 and c or lighten(c, 0.22), Material = Enum.Material.Neon, Transparency = 0.55, CanCollide = false, Parent = model })
			y = y + h * 0.78
			w = w - math.random(2, 5)
			if w < 10 then break end
		end
		local tip = newPart({ Name = "PillarTip", Shape = Enum.PartType.Ball, Size = Vector3.new(9, 9, 9), Position = Vector3.new(x, y + 5, z), Color = Color3.fromRGB(255, 250, 220), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(tip, c, 46, 3)
	end

	-- MID: protostars. Bright cores wrapped in a shell, hanging at mid height -- the thing the
	-- pillars are supposedly making, so the zone reads as a process rather than a mood.
	for _ = 1, 8 do
		local x, z = scatterPoint(cx, 195, 245)
		local y = math.random(28, 72)
		local c = palette[math.random(1, #palette)]
		local star = newPart({ Name = "Protostar", Shape = Enum.PartType.Ball, Size = Vector3.new(12, 12, 12), Position = Vector3.new(x, y, z), Color = Color3.fromRGB(255, 248, 224), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(star, c, 44, 3)
		for i = 1, 2 do
			newPart({ Name = "ProtostarShell", Shape = Enum.PartType.Ball, Size = Vector3.new(20 + i * 12, 20 + i * 12, 20 + i * 12), Position = Vector3.new(x, y, z), Color = c, Material = Enum.Material.Neon, Transparency = 0.68 + i * 0.1, CanCollide = false, Parent = model })
		end
		newPart({ Name = "ProtostarDisc", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, 54, 54), Orientation = Vector3.new(math.random(-24, 24), 0, 90), Position = Vector3.new(x, y, z), Color = lighten(c, 0.3), Material = Enum.Material.Neon, Transparency = 0.55, CanCollide = false, Parent = model })
	end

	-- MID: filaments. Thin lit strands strung between the clouds give the mid-air a structure
	-- that raw fog never has.
	for _ = 1, 20 do
		local x, z = scatterPoint(cx, 200, 250)
		newPart({ Name = "Filament", Size = Vector3.new(math.random(30, 90), 1, 1), Orientation = Vector3.new(math.random(-30, 30), math.random(0, 360), math.random(-30, 30)), Position = Vector3.new(x, math.random(16, 76), z), Color = palette[math.random(1, #palette)], Material = Enum.Material.Neon, Transparency = 0.35, CanCollide = false, Parent = model })
	end

	-- MID: glowing floor vents feeding the clouds above, so the drift has a visible source
	for _ = 1, 9 do
		local x, z = scatterPoint(cx)
		local vent = newPart({ Name = "GasVent", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.4, 14, 14), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 1.2, z), Color = darken(magenta, 0.45), Material = Enum.Material.Foil, CanCollide = false, Parent = model })
		local mouth = newPart({ Name = "GasVentMouth", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 10, 10), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 2.5, z), Color = magenta, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(mouth, magenta, 24, 2)
		local plume = Instance.new("ParticleEmitter")
		plume.Color = ColorSequence.new(magenta, azure)
		plume.Size = NumberSequence.new(4, 14)
		plume.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
		plume.Lifetime = NumberRange.new(5, 9)
		plume.Rate = 10
		plume.Speed = NumberRange.new(5, 10)
		plume.SpreadAngle = Vector2.new(22, 22)
		plume.Acceleration = Vector3.new(0, 4, 0)
		plume.LightEmission = 0.8
		plume.Parent = mouth
	end
end

decorationBuilders.Wormhole = function(model, zone, cx)
	local violet = Color3.fromRGB(150, 100, 245)
	local pale = Color3.fromRGB(215, 200, 255)

	buildBiomeBase(model, cx, {
		litter = { count = 18, name = "Fragment", colors = { Color3.fromRGB(44, 44, 72), Color3.fromRGB(62, 58, 96), Color3.fromRGB(30, 30, 52) }, minSize = 3, maxSize = 10, material = Enum.Material.Slate },
		mounds = { count = 4, name = "WarpSwell", color = Color3.fromRGB(40, 38, 66), material = Enum.Material.Slate, minSize = 34, maxSize = 62, flat = 0.2 },
		-- no landmark: the throat below already owns the back of the platform, and addLandmark
		-- would place its plinth at z = -210, straight through the far end of the tunnel
		atmosphere = { color = violet, color2 = pale, height = 34, rate = 18, sizeStart = 1, sizeEnd = 3, transparency = 0.42, lifeMin = 4, lifeMax = 8, speedMin = 8, speedMax = 16, lightEmission = 1 },
		glow = { count = 6, color = violet, height = 15, range = 28 },
	})

	-- SIGNATURE: the throat. A receding corridor of rings that shrink and tilt as they go back is
	-- what turns five concentric circles in one spot into an actual tunnel you can look down.
	local tunnelZ = -60
	for i = 1, 16 do
		local d = 84 - i * 3.4
		local zPos = tunnelZ - i * 9
		local ring = newPart({
			Name = "ThroatRing",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2.2, d, d),
			Orientation = Vector3.new(0, 0, 90),
			Position = Vector3.new(cx + math.sin(i * 0.42) * 9, 40 + math.sin(i * 0.3) * 5, zPos),
			Color = i % 3 == 0 and pale or violet,
			Material = Enum.Material.Neon,
			Transparency = 0.18 + i * 0.03,
			CanCollide = false,
			Parent = model,
		})
		if i % 4 == 1 then
			addLight(ring, violet, 40, 2.6)
		end
	end
	local mouth = newPart({ Name = "ThroatMouth", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 34, 34), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(cx + math.sin(17 * 0.42) * 9, 40, tunnelZ - 17 * 9), Color = Color3.fromRGB(255, 255, 255), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	addLight(mouth, pale, 60, 4)

	-- MID: light streaks pulled along the tunnel axis. Everything points the same way, which is
	-- what makes the zone feel like it is moving even though nothing is animated.
	for _ = 1, 30 do
		local x, z = scatterPoint(cx, 200, 250)
		newPart({ Name = "WarpStreak", Size = Vector3.new(1.2, 1.2, math.random(26, 70)), Orientation = Vector3.new(math.random(-6, 6), math.random(-12, 12), math.random(0, 360)), Position = Vector3.new(x, math.random(6, 62), z), Color = math.random(1, 3) == 1 and pale or violet, Material = Enum.Material.Neon, Transparency = 0.3, CanCollide = false, Parent = model })
	end

	-- MID: stabiliser gantries flanking the throat, so the tunnel looks built and maintained
	for _, side in ipairs({ -1, 1 }) do
		for i = 1, 5 do
			local gx = cx + side * (58 + i * 5)
			local gz = tunnelZ - i * 26
			newPart({ Name = "GantryLeg", Size = Vector3.new(4.5, 54, 4.5), Position = Vector3.new(gx, 27, gz), Color = Color3.fromRGB(52, 50, 78), Material = Enum.Material.Metal, Parent = model })
			newPart({ Name = "GantryArm", Size = Vector3.new(22, 3, 3), Orientation = Vector3.new(0, 0, side * -14), Position = Vector3.new(gx - side * 11, 52, gz), Color = Color3.fromRGB(52, 50, 78), Material = Enum.Material.Metal, CanCollide = false, Parent = model })
			local emitter = newPart({ Name = "GantryEmitter", Shape = Enum.PartType.Ball, Size = Vector3.new(6, 6, 6), Position = Vector3.new(gx - side * 21, 51, gz), Color = violet, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
			addLight(emitter, violet, 26, 2)
		end
	end

	-- MID: debris caught in the pull, tumbling at every angle just off the tunnel line
	for _ = 1, 20 do
		local x, z = scatterPoint(cx, 195, 245)
		local s = math.random(5, 15)
		newPart({ Name = "CaughtDebris", Size = Vector3.new(s, s * 0.7, s * 1.3), Orientation = Vector3.new(math.random(0, 360), math.random(0, 360), math.random(0, 360)), Position = Vector3.new(x, math.random(10, 56), z), Color = Color3.fromRGB(58, 54, 88), Material = Enum.Material.Slate, CanCollide = false, Parent = model })
	end

	-- MID: floor conduits running toward the throat, so the ground carries the same direction
	for _ = 1, 14 do
		local x, z = scatterPoint(cx, 200, 250)
		newPart({ Name = "Conduit", Size = Vector3.new(2.6, 0.5, math.random(30, 76)), Orientation = Vector3.new(0, math.random(-16, 16), 0), Position = Vector3.new(x, 0.35, z), Color = violet, Material = Enum.Material.Neon, Transparency = 0.25, CanCollide = false, Parent = model })
	end
end

decorationBuilders.QuantumRealm = function(model, zone, cx)
	local teal = Color3.fromRGB(80, 220, 220)
	local deep = Color3.fromRGB(28, 84, 100)

	buildBiomeBase(model, cx, {
		litter = { count = 22, name = "Quanta", colors = { teal, Color3.fromRGB(150, 255, 245), Color3.fromRGB(60, 170, 190) }, minSize = 2, maxSize = 6, shape = Enum.PartType.Block, flat = 1, material = Enum.Material.Neon, transparency = 0.35 },
		mounds = { count = 5, name = "FieldSwell", color = Color3.fromRGB(38, 104, 122), material = Enum.Material.Glass, minSize = 34, maxSize = 64, flat = 0.2, transparency = 0.35 },
		landmark = { style = "crystal", base = deep, accent = teal, material = Enum.Material.Glass },
		atmosphere = { color = teal, color2 = Color3.fromRGB(190, 255, 250), height = 30, rate = 24, sizeStart = 0.4, sizeEnd = 1.4, transparency = 0.35, lifeMin = 3, lifeMax = 6, speedMin = 6, speedMax = 14, lightEmission = 1 },
		glow = { count = 6, color = teal, height = 14, range = 28 },
	})

	-- SIGNATURE: superposition. Every prop is built twice -- solid, plus a translucent twin
	-- offset a few studs. Two copies of the same object is the only way to draw "it is in both
	-- places" without animation, and it is what makes this zone unmistakable.
	for _ = 1, 16 do
		local x, z = scatterPoint(cx, 195, 245)
		local s = math.random(6, 15)
		local y = math.random(6, 44)
		local orient = Vector3.new(math.random(0, 360), math.random(0, 360), math.random(0, 360))
		newPart({ Name = "QuantumCube", Size = Vector3.new(s, s, s), Orientation = orient, Position = Vector3.new(x, y, z), Color = teal, Material = Enum.Material.Neon, Transparency = 0.15, CanCollide = false, Parent = model })
		newPart({ Name = "QuantumGhost", Size = Vector3.new(s, s, s), Orientation = orient, Position = Vector3.new(x + math.random(-9, 9), y + math.random(-5, 5), z + math.random(-9, 9)), Color = lighten(teal, 0.4), Material = Enum.Material.Neon, Transparency = 0.72, CanCollide = false, Parent = model })
	end

	-- MID: probability platforms. Thin glass slabs at stepped heights, each ringed in neon --
	-- the built element that keeps the zone from being pure floating geometry.
	for _ = 1, 10 do
		local x, z = scatterPoint(cx, 190, 240)
		local y = math.random(8, 40)
		local w = math.random(16, 30)
		newPart({ Name = "PhasePlatform", Size = Vector3.new(w, 1.4, w * 0.85), Orientation = Vector3.new(0, math.random(0, 360), 0), Position = Vector3.new(x, y, z), Color = deep, Material = Enum.Material.Glass, Transparency = 0.4, CanCollide = false, Parent = model })
		newPart({ Name = "PlatformRim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, w + 5, w + 5), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, y - 0.9, z), Color = teal, Material = Enum.Material.Neon, Transparency = 0.3, CanCollide = false, Parent = model })
	end

	-- MID: wave rails. Long low arcs of light skimming the floor read as particles taking every
	-- path at once, and they stop the ground going flat and empty between the platforms.
	for _ = 1, 16 do
		local x, z = scatterPoint(cx, 200, 250)
		local yaw = math.random(0, 360)
		for i = -3, 3 do
			newPart({ Name = "WaveRail", Size = Vector3.new(11, 0.8, 0.8), Orientation = Vector3.new(0, yaw, 0), Position = Vector3.new(x + math.cos(math.rad(yaw)) * i * 10, 1.4 + math.abs(math.sin(i * 0.9)) * 5, z - math.sin(math.rad(yaw)) * i * 10), Color = teal, Material = Enum.Material.Neon, Transparency = 0.2, CanCollide = false, Parent = model })
		end
	end

	-- MID: containment lattices at eye level -- open glass frames with a lit particle suspended
	-- inside, so the mid-field has something built rather than only scattered light
	for _ = 1, 7 do
		local x, z = scatterPoint(cx)
		local h = math.random(16, 28)
		for _, side in ipairs({ -1, 1 }) do
			newPart({ Name = "LatticePost", Size = Vector3.new(1.8, h, 1.8), Position = Vector3.new(x + side * 8, h / 2, z), Color = deep, Material = Enum.Material.Metal, Parent = model })
			newPart({ Name = "LatticePost", Size = Vector3.new(1.8, h, 1.8), Position = Vector3.new(x, h / 2, z + side * 8), Color = deep, Material = Enum.Material.Metal, Parent = model })
		end
		newPart({ Name = "LatticeCap", Size = Vector3.new(19, 1.4, 19), Position = Vector3.new(x, h, z), Color = deep, Material = Enum.Material.Metal, CanCollide = false, Parent = model })
		local held = newPart({ Name = "HeldParticle", Shape = Enum.PartType.Ball, Size = Vector3.new(7, 7, 7), Position = Vector3.new(x, h * 0.6, z), Color = Color3.fromRGB(200, 255, 250), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(held, teal, 26, 2.4)
	end
end

decorationBuilders.TimeRift = function(model, zone, cx)
	local gold = Color3.fromRGB(238, 196, 92)
	local brass = Color3.fromRGB(126, 96, 48)
	local frozen = Color3.fromRGB(190, 214, 236)

	buildBiomeBase(model, cx, {
		litter = { count = 20, name = "Cog", colors = { brass, gold, Color3.fromRGB(96, 74, 40) }, minSize = 3, maxSize = 10, shape = Enum.PartType.Cylinder, flat = 0.3, material = Enum.Material.Metal },
		mounds = { count = 5, name = "SandDrift", color = Color3.fromRGB(176, 148, 96), material = Enum.Material.Sand, minSize = 34, maxSize = 66, flat = 0.22 },
		landmark = { style = "tower", base = brass, accent = gold, material = Enum.Material.Metal },
		atmosphere = { color = gold, color2 = Color3.fromRGB(255, 240, 200), height = 32, rate = 16, sizeStart = 0.6, sizeEnd = 2, transparency = 0.45, lifeMin = 6, lifeMax = 11, speedMin = 2, speedMax = 5, lightEmission = 0.8, acceleration = Vector3.new(0, -3, 0) },
		glow = { count = 5, color = gold, height = 15, range = 28 },
	})

	-- SIGNATURE: clock faces standing in the ground at every angle, each with hands frozen at a
	-- different hour. A ring alone is just a ring; hands are what make it read as time.
	for _ = 1, 12 do
		local x, z = scatterPoint(cx, 195, 245)
		local d = math.random(16, 34)
		local yaw = math.random(0, 360)
		local tilt = math.random(-22, 22)
		local base = CFrame.new(x, d * 0.55, z) * CFrame.Angles(0, math.rad(yaw), math.rad(tilt))

		local face = newPart({ Name = "ClockFace", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, d, d), Color = Color3.fromRGB(238, 230, 208), Material = Enum.Material.Marble, CanCollide = false, Parent = model })
		face.CFrame = base * CFrame.Angles(0, math.rad(90), 0)
		local rim = newPart({ Name = "ClockRim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.2, d + 4, d + 4), Color = brass, Material = Enum.Material.Metal, CanCollide = false, Parent = model })
		rim.CFrame = base * CFrame.Angles(0, math.rad(90), 0)
		for _, hand in ipairs({ { d * 0.4, 1.4, math.random(0, 360) }, { d * 0.28, 2, math.random(0, 360) } }) do
			local h = newPart({ Name = "ClockHand", Size = Vector3.new(hand[1], hand[2], 0.7), Color = Color3.fromRGB(48, 38, 26), Material = Enum.Material.Metal, CanCollide = false, Parent = model })
			h.CFrame = base * CFrame.new(0, 0, 1.2) * CFrame.Angles(0, 0, math.rad(hand[3])) * CFrame.new(hand[1] / 2, 0, 0)
		end
		local pip = newPart({ Name = "ClockPip", Shape = Enum.PartType.Ball, Size = Vector3.new(2.6, 2.6, 2.6), Color = gold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		pip.CFrame = base * CFrame.new(0, 0, 1.6)
		addLight(pip, gold, 18, 1.4)
	end

	-- MID: hourglasses. Two cones and a lit stream, standing taller than a player, so the zone
	-- has a repeating silhouette at eye level instead of only floor clutter.
	for _ = 1, 7 do
		local x, z = scatterPoint(cx)
		for _, side in ipairs({ -1, 1 }) do
			newPart({ Name = "GlassCap", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 15, 15), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 12 + side * 11, z), Color = brass, Material = Enum.Material.Metal, CanCollide = false, Parent = model })
			newPart({ Name = "GlassBulb", Shape = Enum.PartType.Ball, Size = Vector3.new(13, 11, 13), Position = Vector3.new(x, 12 + side * 5.5, z), Color = frozen, Material = Enum.Material.Glass, Transparency = 0.55, CanCollide = false, Parent = model })
		end
		local stream = newPart({ Name = "SandStream", Size = Vector3.new(1.6, 9, 1.6), Position = Vector3.new(x, 12, z), Color = gold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(stream, gold, 20, 1.8)
		for _, side in ipairs({ -1, 1 }) do
			newPart({ Name = "GlassPost", Size = Vector3.new(1.4, 24, 1.4), Position = Vector3.new(x + side * 7, 12, z), Color = brass, Material = Enum.Material.Metal, CanCollide = false, Parent = model })
		end
	end

	-- MID: debris frozen mid-fall. Objects hanging in the air with no support is the cheapest,
	-- clearest way to draw stopped time, and it fills the band above head height.
	for _ = 1, 24 do
		local x, z = scatterPoint(cx, 200, 250)
		local s = math.random(3, 11)
		newPart({ Name = "FrozenDebris", Size = Vector3.new(s, s * 0.8, s * 1.2), Orientation = Vector3.new(math.random(0, 360), math.random(0, 360), math.random(0, 360)), Position = Vector3.new(x, math.random(8, 50), z), Color = math.random(1, 3) == 1 and gold or Color3.fromRGB(104, 84, 54), Material = Enum.Material.Metal, CanCollide = false, Parent = model })
	end

	-- MID: rift seams in the floor -- thin bright cracks where the two eras meet
	for _ = 1, 16 do
		local x, z = scatterPoint(cx, 200, 250)
		newPart({ Name = "RiftSeam", Size = Vector3.new(math.random(20, 56), 0.6, math.random(2, 4)), Orientation = Vector3.new(0, math.random(0, 360), 0), Position = Vector3.new(x, 0.4, z), Color = frozen, Material = Enum.Material.Neon, Transparency = 0.25, CanCollide = false, Parent = model })
	end

	-- MID: gear pillars, half-sunk into the ground, giving the mid-field a mechanical read
	for _ = 1, 9 do
		local x, z = scatterPoint(cx)
		local y = 0
		for i = 1, math.random(2, 4) do
			local d = math.random(14, 26)
			newPart({ Name = "GearDisc", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.4, d, d), Orientation = Vector3.new(0, math.random(0, 360), 90), Position = Vector3.new(x, y + 1.7, z), Color = i % 2 == 0 and brass or Color3.fromRGB(150, 118, 62), Material = Enum.Material.Metal, Parent = model })
			y = y + 3.2
		end
	end
end

decorationBuilders.AntimatterZone = function(model, zone, cx)
	local danger = Color3.fromRGB(255, 62, 62)
	local hot = Color3.fromRGB(255, 176, 120)
	local hull = Color3.fromRGB(58, 42, 42)

	buildBiomeBase(model, cx, {
		litter = { count = 22, name = "SlagChunk", colors = { hull, Color3.fromRGB(34, 22, 22), Color3.fromRGB(84, 52, 46) }, minSize = 3, maxSize = 12, material = Enum.Material.Slate },
		mounds = { count = 5, name = "BlastBerm", color = Color3.fromRGB(72, 40, 38), material = Enum.Material.Slate, minSize = 34, maxSize = 64, flat = 0.22 },
		landmark = { style = "spire", base = hull, accent = danger, material = Enum.Material.Metal },
		atmosphere = { color = danger, color2 = Color3.fromRGB(120, 20, 20), height = 32, rate = 20, sizeStart = 1.4, sizeEnd = 0.3, transparency = 0.35, lifeMin = 3, lifeMax = 6, speedMin = 8, speedMax = 16, lightEmission = 1 },
		glow = { count = 6, color = danger, height = 15, range = 30, brightness = 2.8 },
	})

	-- SIGNATURE: magnetic containment cells. Antimatter cannot touch anything, so the read has to
	-- be "suspended and held" -- a caged core between two emitter plates, never a pool on the
	-- floor. The old 150x150 red slab said the opposite of what this zone is.
	for _ = 1, 8 do
		local x, z = scatterPoint(cx, 190, 240)
		newPart({ Name = "CellBase", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 26, 26), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 2, z), Color = hull, Material = Enum.Material.Metal, Parent = model })
		for _, side in ipairs({ -1, 1 }) do
			newPart({ Name = "CellColumn", Size = Vector3.new(3, 30, 3), Position = Vector3.new(x + side * 10, 19, z), Color = darken(hull, 0.2), Material = Enum.Material.Metal, Parent = model })
		end
		newPart({ Name = "CellCap", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.4, 24, 24), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 35, z), Color = hull, Material = Enum.Material.Metal, CanCollide = false, Parent = model })
		local caged = newPart({ Name = "CagedCore", Shape = Enum.PartType.Ball, Size = Vector3.new(11, 11, 11), Position = Vector3.new(x, 19, z), Color = Color3.fromRGB(255, 240, 230), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(caged, danger, 40, 3.4)
		for i = 1, 3 do
			newPart({ Name = "ContainmentRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, 15 + i * 4, 15 + i * 4), Orientation = Vector3.new(i * 30, 0, 90), Position = Vector3.new(x, 19, z), Color = danger, Material = Enum.Material.Neon, Transparency = 0.35 + i * 0.12, CanCollide = false, Parent = model })
		end
		local arc = Instance.new("ParticleEmitter")
		arc.Color = ColorSequence.new(hot, danger)
		arc.Size = NumberSequence.new(1.6, 0.2)
		arc.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		arc.Lifetime = NumberRange.new(0.5, 1.1)
		arc.Rate = 26
		arc.Speed = NumberRange.new(10, 18)
		arc.SpreadAngle = Vector2.new(180, 180)
		arc.LightEmission = 1
		arc.Parent = caged
	end

	-- MID: hazard pylons with striped bands -- signage is what turns scattered machinery into a
	-- facility, and the yellow/black break is the only warm break in an all-red palette
	for _ = 1, 12 do
		local x, z = scatterPoint(cx)
		local h = math.random(14, 24)
		newPart({ Name = "HazardPylon", Size = Vector3.new(3.2, h, 3.2), Position = Vector3.new(x, h / 2, z), Color = Color3.fromRGB(40, 34, 32), Material = Enum.Material.Metal, Parent = model })
		for i = 1, 3 do
			newPart({ Name = "HazardBand", Size = Vector3.new(4, 2.2, 4), Position = Vector3.new(x, h * 0.25 * i, z), Color = Color3.fromRGB(248, 208, 40), Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
		end
		local top = newPart({ Name = "HazardLamp", Shape = Enum.PartType.Ball, Size = Vector3.new(4.4, 4.4, 4.4), Position = Vector3.new(x, h + 2, z), Color = danger, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(top, danger, 22, 2)
	end

	-- MID: annihilation craters. Where containment already failed: a scorched bowl, a glass-slag
	-- floor and a thrown-up rim, so the zone carries evidence rather than only warnings.
	for _ = 1, 7 do
		local x, z = scatterPoint(cx, 195, 245)
		local r = math.random(16, 34)
		newPart({ Name = "ScorchFloor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, r * 2, r * 2), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 0.4, z), Color = Color3.fromRGB(18, 10, 10), Material = Enum.Material.Slate, CanCollide = false, Parent = model })
		local slag = newPart({ Name = "SlagPool", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, r * 1.2, r * 1.2), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 0.7, z), Color = danger, Material = Enum.Material.Neon, Transparency = 0.2, CanCollide = false, Parent = model })
		addLight(slag, danger, 28, 2.4)
		local rimCount = 9 + math.floor(r / 5)
		for i = 1, rimCount do
			local a = (i / rimCount) * math.pi * 2
			local s = math.random(5, 10)
			newPart({ Name = "CraterSlag", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 0.6, s), Orientation = Vector3.new(0, math.random(0, 360), 0), Position = Vector3.new(x + math.cos(a) * r, s * 0.25, z + math.sin(a) * r), Color = hull, Material = Enum.Material.Slate, CanCollide = false, Parent = model })
		end
	end

	-- MID: buckled pipework running between the cells, so the machinery looks connected
	for _ = 1, 14 do
		local x, z = scatterPoint(cx, 200, 250)
		local yaw = math.random(0, 360)
		newPart({ Name = "Pipe", Shape = Enum.PartType.Cylinder, Size = Vector3.new(math.random(24, 60), 4, 4), Orientation = Vector3.new(0, yaw, 90), Position = Vector3.new(x, 3, z), Color = Color3.fromRGB(74, 58, 56), Material = Enum.Material.Metal, Parent = model })
		newPart({ Name = "PipeGlow", Size = Vector3.new(1.2, 0.5, 1.2), Position = Vector3.new(x, 5.2, z), Color = danger, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	end
end

decorationBuilders.DreamDimension = function(model, zone, cx)
	local lilac = Color3.fromRGB(206, 152, 255)
	local blush = Color3.fromRGB(255, 198, 232)
	local mint = Color3.fromRGB(198, 255, 226)
	local palette = { lilac, blush, mint, Color3.fromRGB(190, 214, 255) }

	buildBiomeBase(model, cx, {
		litter = { count = 18, name = "Pebble", colors = { Color3.fromRGB(150, 112, 190), Color3.fromRGB(186, 148, 220), Color3.fromRGB(122, 88, 160) }, minSize = 3, maxSize = 9, material = Enum.Material.Foil },
		mounds = { count = 8, name = "CloudBank", color = Color3.fromRGB(232, 216, 255), material = Enum.Material.Foil, minSize = 40, maxSize = 76, flat = 0.26, transparency = 0.2 },
		landmark = { style = "greattree", base = blush, accent = Color3.fromRGB(255, 246, 200), trunkColor = Color3.fromRGB(128, 96, 158), material = Enum.Material.Foil },
		atmosphere = { color = blush, color2 = mint, height = 38, rate = 14, sizeStart = 2.4, sizeEnd = 6, transparency = 0.55, lifeMin = 9, lifeMax = 15, speedMin = 0.5, speedMax = 2.5, lightEmission = 0.8 },
		glow = { count = 7, color = lilac, height = 17, range = 30 },
	})

	-- SIGNATURE: staircases that stop in mid-air. Nothing sells "dream" faster than architecture
	-- that clearly cannot work, and stairs are the version of it a player reads instantly.
	for _ = 1, 7 do
		local x, z = scatterPoint(cx, 185, 235)
		local yaw = math.random(0, 360)
		local dir = CFrame.Angles(0, math.rad(yaw), 0)
		local y = 2
		local steps = math.random(8, 16)
		for i = 1, steps do
			-- collidable on purpose: a staircase you fall straight through is worse than one that
			-- goes nowhere, and 16 steps at 3.4 tops out at ~56, far below the 140-stud walls
			local step = newPart({ Name = "DreamStair", Size = Vector3.new(13, 1.4, 6), Color = i % 2 == 0 and blush or Color3.fromRGB(244, 232, 255), Material = Enum.Material.Foil, Parent = model })
			step.CFrame = CFrame.new(x, y, z) * dir * CFrame.new(0, 0, -i * 6)
			y = y + 3.4
		end
		local capstone = newPart({ Name = "StairEndOrb", Shape = Enum.PartType.Ball, Size = Vector3.new(9, 9, 9), Color = Color3.fromRGB(255, 250, 220), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		capstone.CFrame = CFrame.new(x, y + 4, z) * dir * CFrame.new(0, 0, -(steps + 1) * 6)
		addLight(capstone, lilac, 32, 2.4)
	end

	-- MID: soap bubbles at every scale, drifting from ankle height to overhead. Translucent
	-- spheres are the whole palette of this biome; the trick is the spread of sizes, not the count.
	for _ = 1, 26 do
		local x, z = scatterPoint(cx, 200, 250)
		local s = math.random(6, 30)
		local c = palette[math.random(1, #palette)]
		newPart({ Name = "DreamBubble", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s, s), Position = Vector3.new(x, math.random(6, 70), z), Color = c, Material = Enum.Material.Neon, Transparency = 0.68, CanCollide = false, Parent = model })
	end

	-- MID: floating doors standing on nothing. One familiar object out of place does more than
	-- twenty abstract shapes -- it gives the surreal something to be surreal against.
	for _ = 1, 8 do
		local x, z = scatterPoint(cx, 190, 240)
		local y = math.random(6, 40)
		local yaw = math.random(0, 360)
		local rot = CFrame.Angles(0, math.rad(yaw), math.rad(math.random(-14, 14)))
		local frame = newPart({ Name = "DreamDoorFrame", Size = Vector3.new(15, 24, 2.4), Color = Color3.fromRGB(150, 112, 190), Material = Enum.Material.Foil, CanCollide = false, Parent = model })
		frame.CFrame = CFrame.new(x, y, z) * rot
		local leaf = newPart({ Name = "DreamDoor", Size = Vector3.new(11.5, 20, 1), Color = palette[math.random(1, #palette)], Material = Enum.Material.Neon, Transparency = 0.3, CanCollide = false, Parent = model })
		leaf.CFrame = CFrame.new(x, y, z) * rot * CFrame.new(0, 0, 1.4)
		addLight(leaf, lilac, 22, 1.8)
	end

	-- MID: oversized moons low over the platform. Two of them, because one reads as a planet and
	-- two read as a place where the sky does not have to make sense.
	for i, spec in ipairs({ { -132, -206, 62, blush }, { 118, -188, 46, mint } }) do
		local moon = newPart({ Name = "DreamMoon", Shape = Enum.PartType.Ball, Size = Vector3.new(spec[3], spec[3], spec[3]), Position = Vector3.new(cx + spec[1], 70 + i * 12, spec[2]), Color = spec[4], Material = Enum.Material.Neon, Transparency = 0.15, CanCollide = false, Parent = model })
		addLight(moon, spec[4], 70, 2.6)
	end

	-- MID: pastel toadstools at ground level, so the walkable band is not just cloud and air
	for _ = 1, 16 do
		local x, z = scatterPoint(cx)
		local h = math.random(6, 16)
		local c = palette[math.random(1, #palette)]
		newPart({ Name = "DreamStem", Size = Vector3.new(2.6, h, 2.6), Position = Vector3.new(x, h / 2, z), Color = Color3.fromRGB(248, 240, 255), Material = Enum.Material.Foil, CanCollide = false, Parent = model })
		local cap = newPart({ Name = "DreamCap", Shape = Enum.PartType.Ball, Size = Vector3.new(h * 1.1, h * 0.62, h * 1.1), Position = Vector3.new(x, h + h * 0.2, z), Color = c, Material = Enum.Material.Neon, Transparency = 0.15, CanCollide = false, Parent = model })
		if math.random(1, 3) == 1 then
			addLight(cap, c, 18, 1.4)
		end
	end
end

decorationBuilders.MirrorUniverse = function(model, zone, cx)
	local silver = Color3.fromRGB(216, 220, 238)
	local frame = Color3.fromRGB(92, 96, 118)
	local cold = Color3.fromRGB(180, 200, 255)

	buildBiomeBase(model, cx, {
		litter = { count = 24, name = "GlassShard", colors = { silver, Color3.fromRGB(168, 176, 200), cold }, minSize = 2, maxSize = 8, shape = Enum.PartType.Block, flat = 0.9, material = Enum.Material.Glass, transparency = 0.15 },
		mounds = { count = 5, name = "PolishedSwell", color = Color3.fromRGB(168, 172, 194), material = Enum.Material.Foil, minSize = 34, maxSize = 64, flat = 0.2 },
		landmark = { style = "crystal", base = frame, accent = cold, material = Enum.Material.Glass },
		atmosphere = { color = silver, color2 = cold, height = 30, rate = 12, sizeStart = 0.6, sizeEnd = 2, transparency = 0.6, lifeMin = 6, lifeMax = 11, speedMin = 1, speedMax = 4, lightEmission = 0.6 },
		glow = { count = 6, color = cold, height = 15, range = 28 },
	})

	-- SIGNATURE: standing mirrors. Full-height framed panes at high Reflectance actually reflect
	-- the player and the rest of the zone at runtime, which no amount of painted "shiny" can fake.
	for _ = 1, 14 do
		local x, z = scatterPoint(cx, 190, 240)
		local h = math.random(24, 46)
		local w = h * 0.52
		local yaw = math.random(0, 360)
		local rot = CFrame.Angles(0, math.rad(yaw), math.rad(math.random(-5, 5)))
		local base = CFrame.new(x, h / 2, z)

		local border = newPart({ Name = "MirrorFrame", Size = Vector3.new(w + 4, h + 4, 2.4), Color = frame, Material = Enum.Material.Metal, Parent = model })
		border.CFrame = base * rot
		local pane = newPart({ Name = "MirrorPane", Size = Vector3.new(w, h, 1), Color = silver, Material = Enum.Material.Glass, Reflectance = 0.95, CanCollide = false, Parent = model })
		pane.CFrame = base * rot * CFrame.new(0, 0, 1.1)
		local backPane = newPart({ Name = "MirrorPane", Size = Vector3.new(w, h, 1), Color = silver, Material = Enum.Material.Glass, Reflectance = 0.95, CanCollide = false, Parent = model })
		backPane.CFrame = base * rot * CFrame.new(0, 0, -1.1)
		local crest = newPart({ Name = "MirrorCrest", Shape = Enum.PartType.Ball, Size = Vector3.new(5.5, 5.5, 5.5), Color = cold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		crest.CFrame = base * rot * CFrame.new(0, h / 2 + 3, 0)
		addLight(crest, cold, 24, 1.8)
	end

	-- SIGNATURE: the inverted world overhead. A single reflective ceiling plane high above turns
	-- the whole platform into its own reflection -- the cheapest possible "mirror universe".
	newPart({ Name = "MirrorCeiling", Size = Vector3.new(PLATFORM_WIDTH - 30, 2, PLATFORM_DEPTH - 30), Position = Vector3.new(cx, 118, 0), Color = Color3.fromRGB(196, 204, 228), Material = Enum.Material.Glass, Reflectance = 0.85, Transparency = 0.25, CanCollide = false, Parent = model })

	-- MID: shattered panes leaning on the floor, catching light at broken angles
	for _ = 1, 20 do
		local x, z = scatterPoint(cx, 200, 250)
		local h = math.random(8, 22)
		newPart({ Name = "BrokenPane", Size = Vector3.new(math.random(5, 13), h, 0.8), Orientation = Vector3.new(math.random(-40, 40), math.random(0, 360), math.random(-30, 30)), Position = Vector3.new(x, h / 2, z), Color = silver, Material = Enum.Material.Glass, Reflectance = 0.8, Transparency = 0.1, CanCollide = false, Parent = model })
	end

	-- MID: mirrored twins. Every pillar is built with an upside-down copy hanging beneath the
	-- floor line, so even the props obey the reflection rather than only the surfaces.
	for _ = 1, 10 do
		local x, z = scatterPoint(cx)
		local h = math.random(16, 34)
		local w = math.random(5, 9)
		local yaw = math.random(0, 360)
		newPart({ Name = "TwinPillar", Size = Vector3.new(w, h, w), Orientation = Vector3.new(0, yaw, 0), Position = Vector3.new(x, h / 2, z), Color = frame, Material = Enum.Material.Metal, Parent = model })
		newPart({ Name = "TwinPillarInverted", Size = Vector3.new(w, h, w), Orientation = Vector3.new(0, yaw, 0), Position = Vector3.new(x, 118 - h / 2, z), Color = frame, Material = Enum.Material.Metal, Transparency = 0.35, CanCollide = false, Parent = model })
		local cap = newPart({ Name = "TwinCap", Shape = Enum.PartType.Ball, Size = Vector3.new(w + 2, w + 2, w + 2), Position = Vector3.new(x, h + 1, z), Color = cold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(cap, cold, 22, 1.6)
	end

	-- MID: a still reflecting pool at floor level, so looking down works as well as looking up.
	-- Parked off to the left and forward of the plaza: it has to clear both the egg-shop footprint
	-- (x within cx +/- 58) and the arrival clearing at z ~ 174.
	newPart({ Name = "ReflectingPool", Size = Vector3.new(130, 0.8, 70), Position = Vector3.new(cx - 120, 0.6, 96), Color = Color3.fromRGB(206, 214, 240), Material = Enum.Material.Glass, Reflectance = 0.9, Transparency = 0.15, CanCollide = false, Parent = model })
	for _, side in ipairs({ -1, 1 }) do
		newPart({ Name = "PoolKerb", Size = Vector3.new(136, 1.6, 4), Position = Vector3.new(cx - 120, 0.8, 96 + side * 37), Color = frame, Material = Enum.Material.Metal, Parent = model })
	end
end

decorationBuilders.VoidExpanse = function(model, zone, cx)
	local violet = Color3.fromRGB(148, 62, 228)
	local ash = Color3.fromRGB(24, 20, 34)

	buildBiomeBase(model, cx, {
		litter = { count = 16, name = "VoidGrit", colors = { ash, Color3.fromRGB(12, 10, 18), Color3.fromRGB(44, 34, 60) }, minSize = 3, maxSize = 10, material = Enum.Material.Slate },
		mounds = { count = 4, name = "AshSwell", color = Color3.fromRGB(18, 15, 26), material = Enum.Material.Slate, minSize = 34, maxSize = 66, flat = 0.2 },
		landmark = { style = "orb", base = ash, accent = violet, coreColor = Color3.fromRGB(10, 6, 16), orbTransparency = 0.1, material = Enum.Material.Slate },
		atmosphere = { color = violet, color2 = Color3.fromRGB(40, 14, 64), height = 40, rate = 8, sizeStart = 5, sizeEnd = 14, transparency = 0.7, lifeMin = 10, lifeMax = 16, speedMin = 0.5, speedMax = 2, lightEmission = 0.5 },
		glow = { count = 5, color = violet, height = 18, range = 32, brightness = 1.6 },
	})

	-- SIGNATURE: holes with nothing under them. A pure-black disc inside a torn, lit rim reads as
	-- absence; a dark grey disc just reads as a stain, which is why the rim has to glow.
	for _ = 1, 11 do
		local x, z = scatterPoint(cx, 195, 245)
		local r = math.random(14, 36)
		newPart({ Name = "VoidHole", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, r * 2, r * 2), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 0.5, z), Color = Color3.fromRGB(0, 0, 0), Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
		local rimCount = 12 + math.floor(r / 4)
		for i = 1, rimCount do
			local a = (i / rimCount) * math.pi * 2
			local h = math.random(3, 9)
			newPart({ Name = "TornEdge", Size = Vector3.new(3.2, h, 3.2), Orientation = Vector3.new(math.random(-24, 24), math.deg(a), math.random(-24, 24)), Position = Vector3.new(x + math.cos(a) * r, h * 0.4, z + math.sin(a) * r), Color = ash, Material = Enum.Material.Slate, CanCollide = false, Parent = model })
		end
		local glowRim = newPart({ Name = "HoleRim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, r * 2 + 5, r * 2 + 5), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 0.3, z), Color = violet, Material = Enum.Material.Neon, Transparency = 0.35, CanCollide = false, Parent = model })
		addLight(glowRim, violet, 30, 2)
	end

	-- MID: the remains of somewhere else. Broken slabs of grass, sand and stone drifting overhead
	-- are the only way to show what the void ate -- an empty zone with nothing in it is just empty.
	local remains = {
		{ color = Color3.fromRGB(66, 112, 62), material = Enum.Material.Grass },
		{ color = Color3.fromRGB(168, 142, 92), material = Enum.Material.Sand },
		{ color = Color3.fromRGB(96, 96, 104), material = Enum.Material.Slate },
		{ color = Color3.fromRGB(120, 52, 30), material = Enum.Material.Rock },
	}
	for _ = 1, 14 do
		local x, z = scatterPoint(cx, 195, 245)
		local r = remains[math.random(1, #remains)]
		local w = math.random(14, 34)
		local y = math.random(18, 68)
		newPart({ Name = "WorldRemnant", Size = Vector3.new(w, math.random(3, 7), w * (0.6 + math.random() * 0.6)), Orientation = Vector3.new(math.random(-24, 24), math.random(0, 360), math.random(-24, 24)), Position = Vector3.new(x, y, z), Color = r.color, Material = r.material, CanCollide = false, Parent = model })
		newPart({ Name = "RemnantUnderside", Shape = Enum.PartType.Ball, Size = Vector3.new(w * 0.75, w * 0.6, w * 0.6), Position = Vector3.new(x, y - w * 0.28, z), Color = ash, Material = Enum.Material.Slate, CanCollide = false, Parent = model })
	end

	-- MID: unravelling threads. Thin violet strands hanging from the remnants down toward the
	-- holes give the two layers a relationship instead of leaving them as separate clutter.
	for _ = 1, 22 do
		local x, z = scatterPoint(cx, 200, 250)
		newPart({ Name = "UnravelThread", Size = Vector3.new(0.7, math.random(20, 54), 0.7), Orientation = Vector3.new(math.random(-14, 14), math.random(0, 360), math.random(-14, 14)), Position = Vector3.new(x, math.random(16, 50), z), Color = violet, Material = Enum.Material.Neon, Transparency = 0.4, CanCollide = false, Parent = model })
	end

	-- MID: obelisks, the last standing structures. Tall, narrow, unlit except at the tip, so the
	-- eye has something to measure the dark against.
	for _ = 1, 9 do
		local x, z = scatterPoint(cx)
		local h = math.random(26, 52)
		newPart({ Name = "VoidObelisk", Size = Vector3.new(5, h, 5), Orientation = Vector3.new(math.random(-4, 4), math.random(0, 360), math.random(-4, 4)), Position = Vector3.new(x, h / 2, z), Color = Color3.fromRGB(16, 13, 24), Material = Enum.Material.Slate, Parent = model })
		local tip = newPart({ Name = "ObeliskTip", Size = Vector3.new(3.4, 6, 3.4), Orientation = Vector3.new(0, 45, 0), Position = Vector3.new(x, h + 3, z), Color = violet, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(tip, violet, 26, 2)
	end
end

decorationBuilders.CelestialThrone = function(model, zone, cx)
	local gold = Color3.fromRGB(255, 218, 128)
	local deepGold = Color3.fromRGB(186, 148, 68)
	local marble = Color3.fromRGB(246, 240, 224)
	local throneZ = -190

	-- SIGNATURE LANDMARK: the throne itself, hand-built rather than routed through addLandmark --
	-- this is the zone's name, so it has to be a recognisable seat on a stepped dais, not another
	-- abstract tower. buildBiomeBase below is therefore asked for no landmark of its own.
	local y = 0
	for i = 1, 5 do
		local w = 130 - i * 16
		newPart({ Name = "ThroneStep", Size = Vector3.new(w, 5, w * 0.62), Position = Vector3.new(cx, y + 2.5, throneZ), Color = i % 2 == 0 and marble or lighten(deepGold, 0.45), Material = Enum.Material.Marble, Parent = model })
		newPart({ Name = "ThroneStepTrim", Size = Vector3.new(w + 3, 1, w * 0.62 + 3), Position = Vector3.new(cx, y + 5.2, throneZ), Color = gold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		y = y + 5
	end
	newPart({ Name = "ThroneSeat", Size = Vector3.new(30, 6, 24), Position = Vector3.new(cx, y + 3, throneZ), Color = deepGold, Material = Enum.Material.Metal, Parent = model })
	newPart({ Name = "ThroneBack", Size = Vector3.new(30, 52, 6), Position = Vector3.new(cx, y + 32, throneZ - 9), Color = deepGold, Material = Enum.Material.Metal, Parent = model })
	newPart({ Name = "ThroneBackInlay", Size = Vector3.new(20, 40, 1.4), Position = Vector3.new(cx, y + 30, throneZ - 5.6), Color = gold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	for _, side in ipairs({ -1, 1 }) do
		newPart({ Name = "ThroneArm", Size = Vector3.new(5, 12, 24), Position = Vector3.new(cx + side * 17, y + 10, throneZ), Color = deepGold, Material = Enum.Material.Metal, Parent = model })
		newPart({ Name = "ThroneFinial", Shape = Enum.PartType.Ball, Size = Vector3.new(8, 8, 8), Position = Vector3.new(cx + side * 17, y + 18, throneZ + 9), Color = gold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	end
	-- crown of haloes above the seat: the one element that makes the whole arrangement read as
	-- divine rather than merely expensive
	for i = 1, 3 do
		local halo = newPart({ Name = "ThroneHalo", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 34 + i * 16, 34 + i * 16), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(cx, y + 68 + i * 9, throneZ), Color = gold, Material = Enum.Material.Neon, Transparency = 0.12 + i * 0.16, CanCollide = false, Parent = model })
		if i == 1 then
			addLight(halo, gold, 70, 4)
		end
	end

	buildBiomeBase(model, cx, {
		litter = { count = 18, name = "GildedStone", colors = { marble, Color3.fromRGB(224, 206, 164), lighten(deepGold, 0.3) }, minSize = 3, maxSize = 10, material = Enum.Material.Marble },
		mounds = { count = 7, name = "CloudBank", color = Color3.fromRGB(252, 246, 230), material = Enum.Material.Foil, minSize = 40, maxSize = 78, flat = 0.24, transparency = 0.18 },
		atmosphere = { color = gold, color2 = Color3.fromRGB(255, 250, 226), height = 42, rate = 16, sizeStart = 1, sizeEnd = 3.4, transparency = 0.45, lifeMin = 7, lifeMax = 13, speedMin = 1, speedMax = 4, lightEmission = 1, acceleration = Vector3.new(0, 2, 0) },
		glow = { count = 6, color = gold, height = 18, range = 32, brightness = 2.6 },
	})

	-- SIGNATURE: the approach. Two colonnades running from the arrival side up to the dais turn
	-- the platform into a hall with a destination, which is what a throne needs to mean anything.
	for _, side in ipairs({ -1, 1 }) do
		for i = 1, 8 do
			local px = cx + side * 54
			local pz = 140 - i * 40
			newPart({ Name = "ColonnadeBase", Size = Vector3.new(16, 3, 16), Position = Vector3.new(px, 1.5, pz), Color = marble, Material = Enum.Material.Marble, Parent = model })
			newPart({ Name = "ColonnadePillar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(58, 11, 11), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(px, 32, pz), Color = marble, Material = Enum.Material.Marble, Parent = model })
			newPart({ Name = "ColonnadeCap", Size = Vector3.new(15, 4, 15), Position = Vector3.new(px, 63, pz), Color = deepGold, Material = Enum.Material.Metal, CanCollide = false, Parent = model })
			local flame = newPart({ Name = "ColonnadeFlame", Shape = Enum.PartType.Ball, Size = Vector3.new(7.5, 7.5, 7.5), Position = Vector3.new(px, 69, pz), Color = gold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
			addLight(flame, gold, 34, 2.6)
			-- banners hung between the pillars, so the gap between them is not dead air
			newPart({ Name = "Banner", Size = Vector3.new(0.6, 26, 13), Position = Vector3.new(px - side * 6, 48, pz), Color = Color3.fromRGB(196, 62, 74), Material = Enum.Material.Fabric, CanCollide = false, Parent = model })
			newPart({ Name = "BannerTrim", Size = Vector3.new(0.8, 2.2, 14), Position = Vector3.new(px - side * 6, 35, pz), Color = gold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		end
	end

	-- MID: a gold carpet down the centre of the hall, edged in neon
	newPart({ Name = "Carpet", Size = Vector3.new(34, 0.5, 300), Position = Vector3.new(cx, 0.4, 10), Color = Color3.fromRGB(176, 48, 62), Material = Enum.Material.Fabric, CanCollide = false, Parent = model })
	for _, side in ipairs({ -1, 1 }) do
		newPart({ Name = "CarpetEdge", Size = Vector3.new(1.6, 0.6, 300), Position = Vector3.new(cx + side * 17, 0.45, 10), Color = gold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	end

	-- MID: floating haloes drifting over the hall, small and many, so the air above the colonnade
	-- carries the same motif as the throne
	for _ = 1, 20 do
		local x, z = scatterPoint(cx, 200, 250)
		local d = math.random(8, 20)
		newPart({ Name = "FloatingHalo", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, d, d), Orientation = Vector3.new(math.random(-25, 25), math.random(0, 360), 90), Position = Vector3.new(x, math.random(20, 72), z), Color = gold, Material = Enum.Material.Neon, Transparency = 0.3, CanCollide = false, Parent = model })
	end

	-- MID: braziers and offering bowls at ground level between the colonnades
	for _ = 1, 10 do
		local x, z = scatterPoint(cx)
		newPart({ Name = "BrazierStem", Size = Vector3.new(3, 11, 3), Position = Vector3.new(x, 5.5, z), Color = deepGold, Material = Enum.Material.Metal, Parent = model })
		newPart({ Name = "BrazierBowl", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 13, 13), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 12.5, z), Color = deepGold, Material = Enum.Material.Metal, CanCollide = false, Parent = model })
		local fire = newPart({ Name = "BrazierFire", Shape = Enum.PartType.Ball, Size = Vector3.new(9, 7, 9), Position = Vector3.new(x, 15.5, z), Color = gold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(fire, gold, 28, 2.4)
	end
end

decorationBuilders.Singularity = function(model, zone, cx)
	local white = Color3.fromRGB(255, 255, 255)
	local pale = Color3.fromRGB(206, 214, 236)
	local shell = Color3.fromRGB(22, 22, 30)
	local coreY, coreZ = 92, -186

	-- SIGNATURE LANDMARK: the point everything is falling into. Hand-built so the shells can be
	-- real concentric rings on three axes around one blinding core; buildBiomeBase gets no
	-- landmark of its own because a second silhouette would break the convergence read.
	local core = newPart({ Name = "SingularityCore", Shape = Enum.PartType.Ball, Size = Vector3.new(30, 30, 30), Position = Vector3.new(cx, coreY, coreZ), Color = white, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	addLight(core, white, 120, 6)
	for i = 1, 5 do
		local d = 52 + i * 24
		for _, axis in ipairs({ Vector3.new(0, 0, 90), Vector3.new(90, 0, 0), Vector3.new(0, 90, 90) }) do
			newPart({ Name = "CollapseShell", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, d, d), Orientation = axis + Vector3.new(i * 7, i * 11, 0), Position = Vector3.new(cx, coreY, coreZ), Color = i <= 2 and white or pale, Material = Enum.Material.Neon, Transparency = 0.4 + i * 0.1, CanCollide = false, Parent = model })
		end
	end
	local suck = Instance.new("ParticleEmitter")
	suck.Color = ColorSequence.new(pale, white)
	suck.Size = NumberSequence.new(4, 0.1)
	suck.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	suck.Lifetime = NumberRange.new(2, 3.5)
	suck.Rate = 60
	suck.Speed = NumberRange.new(-46, -30)
	suck.SpreadAngle = Vector2.new(180, 180)
	suck.LightEmission = 1
	suck.Parent = core

	buildBiomeBase(model, cx, {
		litter = { count = 20, name = "CollapsedGrit", colors = { shell, Color3.fromRGB(12, 12, 18), Color3.fromRGB(46, 46, 60) }, minSize = 2, maxSize = 8, shape = Enum.PartType.Block, flat = 0.8, material = Enum.Material.Foil },
		mounds = { count = 4, name = "DrawnSwell", color = Color3.fromRGB(18, 18, 26), material = Enum.Material.Foil, minSize = 32, maxSize = 62, flat = 0.18 },
		atmosphere = { color = white, color2 = pale, height = 44, rate = 22, sizeStart = 2, sizeEnd = 0.3, transparency = 0.35, lifeMin = 3, lifeMax = 7, speedMin = 10, speedMax = 20, lightEmission = 1 },
		glow = { count = 5, color = pale, height = 17, range = 30, brightness = 2.4 },
	})

	-- SIGNATURE: a floor grid dragged toward the core. Straight lines that visibly bend are the
	-- clearest possible drawing of curved space, and they give the dark floor a readable surface.
	for i = -9, 9 do
		local x = cx + i * 22
		for seg = 0, 11 do
			local z = 250 - seg * 44
			local pull = (1 - math.abs(z - coreZ) / 520) * i * -7
			newPart({ Name = "GridLine", Size = Vector3.new(1.2, 0.4, 46), Orientation = Vector3.new(0, pull * 0.4, 0), Position = Vector3.new(x + pull, 0.3, z), Color = pale, Material = Enum.Material.Neon, Transparency = 0.45, CanCollide = false, Parent = model })
		end
	end

	-- MID: collapsing structures. Blocks stretched along the axis to the core, each leaning the
	-- same way, so the mid-field shows the pull instead of merely sitting under it.
	for _ = 1, 22 do
		local x, z = scatterPoint(cx, 200, 250)
		local dx, dz = cx - x, coreZ - z
		local yaw = math.deg(math.atan2(dx, dz))
		local len = math.random(14, 44)
		newPart({ Name = "StretchedMass", Size = Vector3.new(math.random(4, 10), math.random(4, 10), len), Orientation = Vector3.new(math.random(-14, 14), yaw, math.random(-20, 20)), Position = Vector3.new(x, math.random(4, 40), z), Color = shell, Material = Enum.Material.Foil, CanCollide = false, Parent = model })
	end

	-- MID: light lances running the same line, so the pull is drawn in light as well as in mass
	for _ = 1, 20 do
		local x, z = scatterPoint(cx, 200, 250)
		local dx, dz = cx - x, coreZ - z
		local yaw = math.deg(math.atan2(dx, dz))
		newPart({ Name = "LightLance", Size = Vector3.new(0.8, 0.8, math.random(30, 90)), Orientation = Vector3.new(math.random(-10, 10), yaw, 0), Position = Vector3.new(x, math.random(8, 66), z), Color = white, Material = Enum.Material.Neon, Transparency = 0.42, CanCollide = false, Parent = model })
	end

	-- MID: monoliths still standing, each tipped toward the core -- the last things with a
	-- silhouette, and the only vertical scale reference in an otherwise horizontal zone
	for _ = 1, 10 do
		local x, z = scatterPoint(cx)
		local dx, dz = cx - x, coreZ - z
		local yaw = math.deg(math.atan2(dx, dz))
		local h = math.random(22, 48)
		newPart({ Name = "LeaningMonolith", Size = Vector3.new(6, h, 4), Orientation = Vector3.new(math.random(10, 24), yaw, 0), Position = Vector3.new(x, h / 2, z), Color = Color3.fromRGB(30, 30, 40), Material = Enum.Material.Foil, Parent = model })
		local crown = newPart({ Name = "MonolithCrown", Shape = Enum.PartType.Ball, Size = Vector3.new(5, 5, 5), Position = Vector3.new(x, h + 2, z), Color = white, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(crown, pale, 22, 1.8)
	end
end

decorationBuilders.AbsolutePlane = function(model, zone, cx)
	local gold = Color3.fromRGB(255, 215, 0)
	local paleGold = Color3.fromRGB(255, 240, 178)
	local bone = Color3.fromRGB(248, 248, 244)

	buildBiomeBase(model, cx, {
		litter = { count = 14, name = "AbsoluteChip", colors = { bone, Color3.fromRGB(232, 232, 226), paleGold }, minSize = 2, maxSize = 7, shape = Enum.PartType.Block, flat = 0.9, material = Enum.Material.SmoothPlastic },
		mounds = { count = 4, name = "WhiteSwell", color = Color3.fromRGB(250, 250, 246), material = Enum.Material.SmoothPlastic, minSize = 36, maxSize = 68, flat = 0.18 },
		landmark = { style = "arch", base = bone, accent = gold, material = Enum.Material.Marble },
		atmosphere = { color = paleGold, color2 = bone, height = 46, rate = 12, sizeStart = 1, sizeEnd = 3, transparency = 0.55, lifeMin = 8, lifeMax = 14, speedMin = 0.5, speedMax = 2.5, lightEmission = 1 },
		glow = { count = 6, color = gold, height = 18, range = 32, brightness = 2.6 },
	})

	-- SIGNATURE: the grid. On a white floor a gold lattice is the only thing that establishes
	-- scale and direction at all -- without it the endgame zone reads as an unfinished baseplate.
	for i = -8, 8 do
		newPart({ Name = "GridX", Size = Vector3.new(0.9, 0.4, PLATFORM_DEPTH - 30), Position = Vector3.new(cx + i * 26, 0.3, 0), Color = gold, Material = Enum.Material.Neon, Transparency = 0.45, CanCollide = false, Parent = model })
	end
	for i = -10, 10 do
		newPart({ Name = "GridZ", Size = Vector3.new(PLATFORM_WIDTH - 30, 0.4, 0.9), Position = Vector3.new(cx, 0.3, i * 26), Color = gold, Material = Enum.Material.Neon, Transparency = 0.45, CanCollide = false, Parent = model })
	end

	-- SIGNATURE: a ring of gold monoliths around the plaza, tall enough to be the skyline. Twelve
	-- identical, evenly spaced -- the deliberate symmetry is the point, this is the one zone that
	-- should look designed rather than grown.
	for i = 1, 12 do
		local a = (i / 12) * math.pi * 2
		local x = cx + math.cos(a) * 168
		local z = math.sin(a) * 200
		local h = 96
		-- leave the doorway open: players teleport in around (cx, 174), so anything landing at
		-- the front-centre of the ring would drop a 96-stud slab right on the arrival pad
		if math.abs(x - cx) >= 80 or z <= 110 then
			newPart({ Name = "AbsoluteMonolith", Size = Vector3.new(11, h, 6), Orientation = Vector3.new(0, math.deg(a), 0), Position = Vector3.new(x, h / 2, z), Color = bone, Material = Enum.Material.Marble, Parent = model })
			newPart({ Name = "MonolithInlay", Size = Vector3.new(5, h - 20, 1.4), Orientation = Vector3.new(0, math.deg(a), 0), Position = Vector3.new(x + math.cos(a) * -3.4, h / 2, z + math.sin(a) * -3.4), Color = gold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
			local capstone = newPart({ Name = "MonolithCap", Size = Vector3.new(13, 7, 8), Orientation = Vector3.new(0, math.deg(a), 45), Position = Vector3.new(x, h + 4, z), Color = gold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
			addLight(capstone, gold, 40, 3)
		end
	end

	-- MID: platonic solids turning in the air. Perfect shapes rather than debris -- everything
	-- here is finished, which is what separates this zone from the Void two stops back.
	for _ = 1, 16 do
		local x, z = scatterPoint(cx, 195, 245)
		local s = math.random(9, 22)
		local y = math.random(18, 74)
		local orient = Vector3.new(math.random(0, 360), math.random(0, 360), math.random(0, 360))
		if math.random(1, 2) == 1 then
			newPart({ Name = "AbsoluteSolid", Size = Vector3.new(s, s, s), Orientation = orient, Position = Vector3.new(x, y, z), Color = bone, Material = Enum.Material.Marble, CanCollide = false, Parent = model })
			newPart({ Name = "SolidEdgeGlow", Size = Vector3.new(s + 1.2, s * 0.14, s + 1.2), Orientation = orient, Position = Vector3.new(x, y, z), Color = gold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		else
			local orb = newPart({ Name = "AbsoluteOrb", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s, s), Position = Vector3.new(x, y, z), Color = paleGold, Material = Enum.Material.Neon, Transparency = 0.25, CanCollide = false, Parent = model })
			addLight(orb, gold, 26, 2)
		end
	end

	-- MID: the shaft. One column of light from the floor to well past the wall height, at the
	-- centre of the monolith ring, so the zone has a single unambiguous focal point.
	newPart({ Name = "AbsoluteShaft", Shape = Enum.PartType.Cylinder, Size = Vector3.new(190, 26, 26), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(cx, 95, -150), Color = paleGold, Material = Enum.Material.Neon, Transparency = 0.62, CanCollide = false, Parent = model })
	for i = 1, 4 do
		local ring = newPart({ Name = "ShaftRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 44 + i * 14, 44 + i * 14), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(cx, 18 + i * 34, -150), Color = gold, Material = Enum.Material.Neon, Transparency = 0.25 + i * 0.1, CanCollide = false, Parent = model })
		if i == 1 then
			addLight(ring, gold, 60, 3.4)
		end
	end

	-- MID: low plinths tracing the grid intersections, so the walkable band has objects at eye
	-- level and the floor pattern is echoed in three dimensions
	for _ = 1, 14 do
		local x, z = scatterPoint(cx)
		local h = math.random(7, 18)
		newPart({ Name = "AbsolutePlinth", Size = Vector3.new(12, h, 12), Position = Vector3.new(x, h / 2, z), Color = bone, Material = Enum.Material.Marble, Parent = model })
		newPart({ Name = "PlinthTrim", Size = Vector3.new(13.4, 1.2, 13.4), Position = Vector3.new(x, h, z), Color = gold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		local votive = newPart({ Name = "PlinthVotive", Shape = Enum.PartType.Ball, Size = Vector3.new(6, 6, 6), Position = Vector3.new(x, h + 4, z), Color = paleGold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(votive, gold, 22, 1.8)
	end
end

-- Moves (or creates) the one canonical SpawnLocation onto the Forest arrival clearing. Called at
-- the end of Build(), so the Forest floor it stands on already exists. Any extra SpawnLocations
-- are removed -- Roblox picks between them at random, so a stray one left in the Forest monument
-- footprint would still strand a share of players inside the shop.
function ZoneBuilder.EnsureSpawn()
	local spawn
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("SpawnLocation") then
			if spawn then
				d:Destroy()
			else
				spawn = d
			end
		end
	end

	if not spawn then
		spawn = Instance.new("SpawnLocation")
	end
	spawn.Name = "ForestSpawn"
	spawn.Size = Vector3.new(16, 1, 16)
	spawn.CFrame = CFrame.new(SPAWN_POSITION)
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.Enabled = true -- a disabled spawn silently sends everyone back to (0, 100, 0)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(120, 255, 160)
	spawn.Material = Enum.Material.Neon
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	-- parented to workspace, never into Zones: the folder is destroyed wholesale on a version bump
	spawn.Parent = workspace

	if not spawn:FindFirstChild("SpawnRing") then
		local ring = newPart({
			Name = "SpawnRing",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.8, 26, 26),
			Orientation = Vector3.new(0, 0, 90),
			Position = SPAWN_POSITION - Vector3.new(0, 0.4, 0),
			Color = Color3.fromRGB(120, 255, 160),
			Material = Enum.Material.Neon,
			Transparency = 0.35,
			CanCollide = false,
			Parent = spawn,
		})
		addLight(ring, Color3.fromRGB(120, 255, 160), 34, 2)
	end

	return spawn
end

function ZoneBuilder.Build()
	local zonesFolder = workspace:FindFirstChild("Zones")

	-- version guard: geometry from an older build is dropped rather than kept, otherwise the
	-- per-zone skip below would preserve it forever and none of the biome work would ever show
	if zonesFolder and zonesFolder:GetAttribute("BuildVersion") ~= BUILD_VERSION then
		warn(("[ZoneBuilder] rebuilding world: stamp %s -> %d")
			:format(tostring(zonesFolder:GetAttribute("BuildVersion")), BUILD_VERSION))
		zonesFolder:Destroy()
		zonesFolder = nil
	end

	if not zonesFolder then
		zonesFolder = Instance.new("Folder")
		zonesFolder.Name = "Zones"
		zonesFolder.Parent = workspace
	end
	zonesFolder:SetAttribute("BuildVersion", BUILD_VERSION)

	for i, zone in ipairs(GameConfig.Zones) do
		if not zonesFolder:FindFirstChild(zone.key) then
			local model = Instance.new("Model")
			model.Name = zone.key
			model.Parent = zonesFolder

			local cx = zone.offset

			local floor = newPart({
				Name = "Floor",
				Size = Vector3.new(PLATFORM_WIDTH, 4, PLATFORM_DEPTH),
				Position = Vector3.new(cx, -2, 0),
				Color = zone.groundColor,
				Material = GROUND_MATERIAL[zone.key] or Enum.Material.SmoothPlastic,
				Parent = model,
			})
			model.PrimaryPart = floor

			local pad = newPart({
				Name = "ZonePad",
				Size = Vector3.new(14, 1, 14),
				Position = Vector3.new(cx, 0.5, 240),
				Color = zone.accentColor,
				Material = Enum.Material.Neon,
				Transparency = 1,
				CanCollide = false,
				Parent = model,
			})

			makeSign(model, zone.emoji .. " " .. zone.name, CFrame.new(cx, 10, 255))

			-- fully enclose the zone in opaque walls -- the only way in/out is through the
			-- big portal gates below, so you never see a neighboring zone from here
			local wallColor = Color3.new(zone.accentColor.R * 0.25, zone.accentColor.G * 0.25, zone.accentColor.B * 0.25)
			local prevZone = GameConfig.Zones[i - 1]
			local nextZone = GameConfig.Zones[i + 1]
			local cliffTemplate = getCliffTemplate(zone.key)
			buildXWall(model, cx - PLATFORM_WIDTH/2, wallColor, prevZone, cliffTemplate)
			buildXWall(model, cx + PLATFORM_WIDTH/2, wallColor, nextZone, cliffTemplate)
			buildZWall(model, cx, -PLATFORM_DEPTH/2, wallColor, cliffTemplate)
			buildZWall(model, cx, PLATFORM_DEPTH/2, wallColor, cliffTemplate)

			-- extra rock clusters scattered inward from the edges so the walkable area
			-- itself feels like an irregular clearing among rocks, not a clean rectangle
			if cliffTemplate then
				for i = 1, 16 do
					local edge = math.random(1, 4)
					local rx, rz
					if edge <= 2 then
						rx = cx + math.random(-200, 200)
						local zSign = edge == 1 and -1 or 1
						rz = zSign * (PLATFORM_DEPTH / 2 - math.random(15, 65))
					else
						local xSign = edge == 3 and -1 or 1
						rx = cx + xSign * (PLATFORM_WIDTH / 2 - math.random(15, 55))
						rz = (math.random(1, 2) == 1) and math.random(60, 240) or math.random(-240, -60)
					end
					local rock = cliffTemplate:Clone()
					local scale = 0.35 + math.random() * 0.35
					rock:ScaleTo(scale)
					local geom = rock:FindFirstChild("body") and rock.body:FindFirstChild("body_geom")
					local halfHeight = (geom and geom.Size.Y / 2 or 65) * scale
					rock:PivotTo(CFrame.new(rx, halfHeight - 3, rz) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
					rock.Parent = model
				end
			end

			local builder = decorationBuilders[zone.key]
			if builder then
				builder(model, zone, cx)
			end

			-- Pet Shop: 3 eggs (Basic/Better/Premium) on a lit podium plaza in the middle of the
			-- zone. Each egg has its own ProximityPrompt tagged with an EggKey attribute so
			-- PetService can wire purchases fresh on every server start.
			do
				local eggs = GameConfig.GetEggsForZone(zone.key)
				if #eggs > 0 then
					local shop = Instance.new("Model")
					shop.Name = "PetShop"
					shop.Parent = model

					local shells = buildEggPlaza(shop, zone, cx, eggs)
					for i, egg in ipairs(eggs) do
						local promptParent = shells[i]
						if promptParent then
							local prompt = Instance.new("ProximityPrompt")
							prompt.ActionText = "Buy Egg"
							prompt.ObjectText = egg.cost .. " DNA"
							prompt.HoldDuration = 0.4
							-- the podium lifts the shell well above head height, so the old 14
							-- would only trigger from directly underneath it
							prompt.MaxActivationDistance = 18
							prompt.RequiresLineOfSight = false
							prompt:SetAttribute("EggKey", egg.key)
							prompt.Parent = promptParent
						end
					end
				end
			end
		end
	end

	ZoneBuilder.EnsureSpawn()
end

function ZoneBuilder.GetZoneSpawnPosition(zoneKey)
	for _, zone in ipairs(GameConfig.Zones) do
		if zone.key == zoneKey then
			return Vector3.new(zone.offset, 5, 180)
		end
	end
	return Vector3.new(0, 5, 180)
end

return ZoneBuilder

