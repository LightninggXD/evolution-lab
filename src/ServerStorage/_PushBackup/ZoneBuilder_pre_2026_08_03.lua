local RS = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local GameConfig = require(RS.Modules.GameConfig)

local ZoneBuilder = {}

local PLATFORM_DEPTH = 550
local PLATFORM_WIDTH = 450
local WALL_HEIGHT = 140
local WALL_THICK = 4
local PORTAL_GAP = 78

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

-- Per-biome decoration builders. Each receives the zone model, zone config, and center X offset.
local decorationBuilders = {}

local forestTreeTemplate = ServerStorage:FindFirstChild("Models") and ServerStorage.Models:FindFirstChild("ForestTree")

decorationBuilders.Forest = function(model, zone, cx)
	for i = 1, 14 do
		local x = cx + math.random(-190, 190)
		local z = math.random(-230, 230)
		if forestTreeTemplate then
			local tree = forestTreeTemplate:Clone()
			local geom = tree:FindFirstChild("body") and tree.body:FindFirstChild("body_geom")
			local scale = 0.85 + math.random() * 0.5
			tree:ScaleTo(scale)
			local halfHeight = (geom and geom.Size.Y / 2 or 8) * scale
			tree:PivotTo(CFrame.new(x, halfHeight, z) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
			tree.Parent = model
		else
			local trunk = newPart({ Name = "Trunk", Size = Vector3.new(4, 16, 4), Position = Vector3.new(x, 8, z), Color = Color3.fromRGB(92, 64, 40), Material = Enum.Material.Wood, Parent = model })
			local leaves = newPart({ Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.new(18, 18, 18), Position = Vector3.new(x, 20, z), Color = Color3.fromRGB(40, 130, 50), Material = Enum.Material.Grass, Parent = model })
		end
	end
end

local desertCactusTemplate = ServerStorage:FindFirstChild("Models") and ServerStorage.Models:FindFirstChild("DesertCactusMesh")
local petShopTemplate = ServerStorage:FindFirstChild("Models") and ServerStorage.Models:FindFirstChild("PetShopKiosk")
local desertStatueTemplate = ServerStorage:FindFirstChild("Models") and ServerStorage.Models:FindFirstChild("DesertStatue")

-- ===== EGGS =====
-- Big, bright, speckled procedural eggs (built from parts, not the old re-tinted mesh whose
-- baked-in texture never actually showed the tier color) so every tier reads as a distinct,
-- colorful reward. Basic/Better get a matte speckled shell; Premium glows with a gem crown.
local EGG_TIER_STYLE = {
	Basic = {
		base = Color3.fromRGB(250, 245, 235),
		speckles = { Color3.fromRGB(255, 90, 90), Color3.fromRGB(90, 170, 255), Color3.fromRGB(255, 210, 60), Color3.fromRGB(120, 220, 120) },
		shellMaterial = Enum.Material.SmoothPlastic,
	},
	Better = {
		base = Color3.fromRGB(90, 70, 235),
		speckles = { Color3.fromRGB(150, 220, 255), Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 120, 255) },
		shellMaterial = Enum.Material.SmoothPlastic,
		gemColor = Color3.fromRGB(120, 220, 255),
	},
	Premium = {
		base = Color3.fromRGB(255, 175, 20),
		speckles = { Color3.fromRGB(255, 60, 140), Color3.fromRGB(120, 60, 255), Color3.fromRGB(60, 220, 255), Color3.fromRGB(255, 255, 255) },
		shellMaterial = Enum.Material.Neon,
		gemColor = Color3.fromRGB(255, 255, 255),
		glow = true,
	},
}

local EGG_SHELL_SIZE = Vector3.new(8, 10.5, 8)
local EGG_PIVOT_Y = 7

-- Builds one colorful speckled egg (shell + scattered speckle dots + optional gem crown)
-- parented into `shop`, and returns the shell part so the caller can attach a ProximityPrompt.
local function buildEgg(shop, ex, tierSuffix)
	local style = EGG_TIER_STYLE[tierSuffix] or EGG_TIER_STYLE.Basic
	local center = Vector3.new(ex, EGG_PIVOT_Y, 0)

	local shell = newPart({
		Name = "Egg",
		Shape = Enum.PartType.Ball,
		Size = EGG_SHELL_SIZE,
		Position = center,
		Color = style.base,
		Material = style.shellMaterial,
		CanCollide = true,
		Parent = shop,
	})

	local rx, ry, rz = EGG_SHELL_SIZE.X / 2 * 0.92, EGG_SHELL_SIZE.Y / 2 * 0.92, EGG_SHELL_SIZE.Z / 2 * 0.92
	for i = 1, 14 do
		local dir = Vector3.new(math.random() - 0.5, (math.random() - 0.5) * 0.85, math.random() - 0.5)
		if dir.Magnitude > 0 then
			dir = dir.Unit
		end
		local pos = center + Vector3.new(dir.X * rx, dir.Y * ry, dir.Z * rz)
		local s = 0.8 + math.random() * 0.9
		newPart({
			Name = "Speckle",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(s, s, s),
			Position = pos,
			Color = style.speckles[math.random(1, #style.speckles)],
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = shop,
		})
	end

	if style.gemColor then
		local gem = newPart({
			Name = "EggGem",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.6, 1.6, 1.6),
			Position = center + Vector3.new(0, ry * 0.95, 0),
			Color = style.gemColor,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = shop,
		})
		if style.glow then
			local light = Instance.new("PointLight")
			light.Color = style.gemColor
			light.Range = 16
			light.Brightness = 2
			light.Parent = gem
		end
	end

	return shell
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
end

decorationBuilders.Ocean = function(model, zone, cx)
	local water = newPart({ Name = "Water", Size = Vector3.new(PLATFORM_WIDTH - 20, 3, PLATFORM_DEPTH - 20), Position = Vector3.new(cx, 3, 0), Color = Color3.fromRGB(50, 140, 210), Material = Enum.Material.Glass, Transparency = 0.35, CanCollide = false, Parent = model })
	for i = 1, 8 do
		local x = cx + math.random(-190, 190)
		local z = math.random(-230, 230)
		newPart({ Name = "Rock", Shape = Enum.PartType.Ball, Size = Vector3.new(10, 8, 10), Position = Vector3.new(x, 4, z), Color = Color3.fromRGB(100, 100, 100), Material = Enum.Material.Rock, Parent = model })
	end
end

decorationBuilders.Volcano = function(model, zone, cx)
	local lava = newPart({ Name = "Lava", Size = Vector3.new(160, 1, 160), Position = Vector3.new(cx, 1.5, 0), Color = Color3.fromRGB(255, 90, 20), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	local cone = newPart({ Name = "VolcanoCone", Shape = Enum.PartType.Cylinder, Size = Vector3.new(100, 70, 70), Orientation = Vector3.new(0,0,90), Position = Vector3.new(cx, 35, -170), Color = Color3.fromRGB(50, 35, 35), Material = Enum.Material.Rock, Parent = model })
	for i = 1, 4 do
		local x = cx + math.random(-190, 190)
		local z = math.random(80, 230)
		newPart({ Name = "LavaRock", Shape = Enum.PartType.Ball, Size = Vector3.new(math.random(6,12), math.random(6,12), math.random(6,12)), Position = Vector3.new(x, 6, z), Color = Color3.fromRGB(40, 30, 30), Material = Enum.Material.Rock, Parent = model })
	end
end

decorationBuilders.Moon = function(model, zone, cx)
	for i = 1, 12 do
		local x = cx + math.random(-190, 190)
		local z = math.random(-230, 230)
		newPart({ Name = "Crater", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, math.random(8,20), math.random(8,20)), Orientation = Vector3.new(0,0,90), Position = Vector3.new(x, 1, z), Color = Color3.fromRGB(140,140,145), Material = Enum.Material.Slate, CanCollide = false, Parent = model })
	end
end

decorationBuilders.Mars = function(model, zone, cx)
	for i = 1, 12 do
		local x = cx + math.random(-190, 190)
		local z = math.random(-230, 230)
		newPart({ Name = "MarsRock", Shape = Enum.PartType.Ball, Size = Vector3.new(math.random(6,14), math.random(6,14), math.random(6,14)), Position = Vector3.new(x, 6, z), Color = Color3.fromRGB(150, 70, 50), Material = Enum.Material.Rock, Parent = model })
	end
end

decorationBuilders.Galaxy = function(model, zone, cx)
	for i = 1, 30 do
		local x = cx + math.random(-200, 200)
		local z = math.random(-260, 260)
		local y = math.random(8, 60)
		newPart({ Name = "Star", Shape = Enum.PartType.Ball, Size = Vector3.new(1.5,1.5,1.5), Position = Vector3.new(x, y, z), Color = Color3.fromRGB(255,255,220), Material = Enum.Material.Neon, CanCollide = false, Anchored = true, Parent = model })
	end
end

decorationBuilders.BlackHole = function(model, zone, cx)
	local core = newPart({ Name = "Core", Shape = Enum.PartType.Ball, Size = Vector3.new(50,50,50), Position = Vector3.new(cx, 30, 0), Color = Color3.fromRGB(0,0,0), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	local ring = newPart({ Name = "Ring", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 90, 90), Orientation = Vector3.new(0,0,90), Position = Vector3.new(cx, 30, 0), Color = Color3.fromRGB(140, 60, 200), Material = Enum.Material.Neon, Transparency = 0.3, CanCollide = false, Parent = model })
end

decorationBuilders.Multiverse = function(model, zone, cx)
	local palette = { Color3.fromRGB(255,90,200), Color3.fromRGB(90,200,255), Color3.fromRGB(255,220,90), Color3.fromRGB(150,90,255) }
	for i = 1, 14 do
		local x = cx + math.random(-190, 190)
		local z = math.random(-230, 230)
		newPart({ Name = "Portal", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 22, 22), Orientation = Vector3.new(0,0,90), Position = Vector3.new(x, 14, z), Color = palette[math.random(1,#palette)], Material = Enum.Material.Neon, Transparency = 0.15, CanCollide = false, Parent = model })
	end
end

decorationBuilders.Nebula = function(model, zone, cx)
	local palette = { Color3.fromRGB(200, 120, 255), Color3.fromRGB(120, 180, 255), Color3.fromRGB(255, 150, 220) }
	for i = 1, 18 do
		local x = cx + math.random(-200, 200)
		local z = math.random(-260, 260)
		local y = math.random(6, 70)
		local s = math.random(8, 22)
		newPart({ Name = "GasCloud", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s, s), Position = Vector3.new(x, y, z), Color = palette[math.random(1, #palette)], Material = Enum.Material.Neon, Transparency = 0.55, CanCollide = false, Parent = model })
	end
end

decorationBuilders.Wormhole = function(model, zone, cx)
	for i = 1, 5 do
		local s = 20 + i * 16
		newPart({ Name = "Ring", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, s, s), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(cx, 30, 0), Color = zone.accentColor, Material = Enum.Material.Neon, Transparency = 0.25 + i * 0.1, CanCollide = false, Parent = model })
	end
end

decorationBuilders.QuantumRealm = function(model, zone, cx)
	for i = 1, 24 do
		local x = cx + math.random(-200, 200)
		local z = math.random(-260, 260)
		local y = math.random(4, 50)
		local s = math.random(3, 8)
		newPart({ Name = "QuantumCube", Size = Vector3.new(s, s, s), Orientation = Vector3.new(math.random(0,360), math.random(0,360), math.random(0,360)), Position = Vector3.new(x, y, z), Color = zone.accentColor, Material = Enum.Material.Neon, Transparency = 0.2, CanCollide = false, Parent = model })
	end
end

decorationBuilders.TimeRift = function(model, zone, cx)
	for i = 1, 6 do
		local x = cx + math.random(-190, 190)
		local z = math.random(-230, 230)
		local s = math.random(14, 30)
		newPart({ Name = "ClockRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.5, s, s), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, s * 0.5, z), Color = zone.accentColor, Material = Enum.Material.Glass, Transparency = 0.3, CanCollide = false, Parent = model })
	end
end

decorationBuilders.AntimatterZone = function(model, zone, cx)
	local pool = newPart({ Name = "AntimatterPool", Size = Vector3.new(150, 1, 150), Position = Vector3.new(cx, 1.5, 0), Color = Color3.fromRGB(255, 40, 40), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	for i = 1, 10 do
		local x = cx + math.random(-200, 200)
		local z = math.random(-250, 250)
		local s = math.random(6, 14)
		newPart({ Name = "AntimatterShard", Size = Vector3.new(s, s * 1.4, s), Orientation = Vector3.new(math.random(0,360), math.random(0,360), 0), Position = Vector3.new(x, s * 0.7, z), Color = Color3.fromRGB(30, 10, 10), Material = Enum.Material.Slate, Parent = model })
	end
end

decorationBuilders.DreamDimension = function(model, zone, cx)
	local palette = { Color3.fromRGB(255, 200, 240), Color3.fromRGB(200, 220, 255), Color3.fromRGB(230, 255, 220) }
	for i = 1, 16 do
		local x = cx + math.random(-200, 200)
		local z = math.random(-260, 260)
		local y = math.random(10, 60)
		local s = math.random(10, 24)
		newPart({ Name = "DreamOrb", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s, s), Position = Vector3.new(x, y, z), Color = palette[math.random(1, #palette)], Material = Enum.Material.Neon, Transparency = 0.5, CanCollide = false, Parent = model })
	end
end

decorationBuilders.MirrorUniverse = function(model, zone, cx)
	for i = 1, 12 do
		local x = cx + math.random(-190, 190)
		local z = math.random(-230, 230)
		local s = math.random(10, 20)
		newPart({ Name = "MirrorShard", Size = Vector3.new(1, s, s * 0.6), Orientation = Vector3.new(0, math.random(0,360), 0), Position = Vector3.new(x, s * 0.5, z), Color = zone.accentColor, Material = Enum.Material.Foil, Transparency = 0.1, CanCollide = false, Parent = model })
	end
end

decorationBuilders.VoidExpanse = function(model, zone, cx)
	for i = 1, 10 do
		local x = cx + math.random(-200, 200)
		local z = math.random(-250, 250)
		local y = math.random(8, 50)
		local s = math.random(8, 18)
		newPart({ Name = "VoidShard", Size = Vector3.new(s * 0.4, s, s * 0.4), Orientation = Vector3.new(math.random(0,360), math.random(0,360), 0), Position = Vector3.new(x, y, z), Color = Color3.fromRGB(20, 10, 30), Material = Enum.Material.Neon, Transparency = 0.4, CanCollide = false, Parent = model })
	end
end

decorationBuilders.CelestialThrone = function(model, zone, cx)
	local dais = newPart({ Name = "Dais", Size = Vector3.new(70, 6, 70), Position = Vector3.new(cx, 3, 0), Color = zone.accentColor, Material = Enum.Material.Marble, Parent = model })
	for i = 1, 8 do
		local angle = (i / 8) * math.pi * 2
		local x = cx + math.cos(angle) * 90
		local z = math.sin(angle) * 90
		newPart({ Name = "GoldPillar", Size = Vector3.new(6, 60, 6), Position = Vector3.new(x, 30, z), Color = zone.accentColor, Material = Enum.Material.Neon, Parent = model })
	end
end

decorationBuilders.Singularity = function(model, zone, cx)
	local core = newPart({ Name = "Core", Shape = Enum.PartType.Ball, Size = Vector3.new(36, 36, 36), Position = Vector3.new(cx, 30, 0), Color = Color3.fromRGB(255, 255, 255), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	for i = 1, 3 do
		local s = 70 + i * 25
		newPart({ Name = "Ring", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, s, s), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(cx, 30, 0), Color = zone.accentColor, Material = Enum.Material.Neon, Transparency = 0.2 + i * 0.15, CanCollide = false, Parent = model })
	end
end

decorationBuilders.AbsolutePlane = function(model, zone, cx)
	for i = 1, 10 do
		local angle = (i / 10) * math.pi * 2
		local x = cx + math.cos(angle) * 160
		local z = math.sin(angle) * 160
		newPart({ Name = "LightPillar", Size = Vector3.new(5, 130, 5), Position = Vector3.new(x, 65, z), Color = zone.accentColor, Material = Enum.Material.Neon, Transparency = 0.1, CanCollide = false, Parent = model })
	end
end

function ZoneBuilder.Build()
	local zonesFolder = workspace:FindFirstChild("Zones")
	if not zonesFolder then
		zonesFolder = Instance.new("Folder")
		zonesFolder.Name = "Zones"
		zonesFolder.Parent = workspace
	end

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

			-- Pet Shop: 3 eggs (Basic/Better/Premium) sitting on pedestals in the middle of
			-- the zone. Each egg has its own ProximityPrompt tagged with an EggKey attribute
			-- so PetService can wire purchases fresh on every server start.
			do
				local eggs = GameConfig.GetEggsForZone(zone.key)
				if #eggs > 0 then
					local shop = Instance.new("Model")
					shop.Name = "PetShop"
					shop.Parent = model

					-- central monument behind the egg row, matching the "altar + big EGGS sign"
					-- reference look, topped with a glowing cap in the zone's accent color
					local monument = newPart({ Name = "Monument", Size = Vector3.new(54, 26, 10), Position = Vector3.new(cx, 13, -10), Color = Color3.fromRGB(32, 32, 38), Material = Enum.Material.Metal, Parent = shop })
					newPart({ Name = "MonumentCap", Size = Vector3.new(58, 3, 12), Position = Vector3.new(cx, 26.5, -10), Color = zone.accentColor, Material = Enum.Material.Neon, Parent = shop })
					makeSign(shop, "🥚 EGGS", CFrame.new(cx, 20, -10 + 5.1), UDim2.new(0, 220, 0, 70))

					local spacing = 21
					local startX = cx - spacing * (#eggs - 1) / 2

					for i, egg in ipairs(eggs) do
						local ex = startX + spacing * (i - 1)
						newPart({ Name = "Pedestal", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 8.5, 8.5), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(ex, 1.5, 0), Color = zone.accentColor, Material = Enum.Material.Neon, CanCollide = false, Parent = shop })

						local promptParent = buildEgg(shop, ex, egg.tierSuffix)

						-- price tag standing just in front of the pedestal, like a shop price card
						makeSign(shop, "🏆 " .. egg.cost .. " DNA", CFrame.new(ex, 2.2, 7), UDim2.new(0, 120, 0, 32))

						if promptParent then
							local prompt = Instance.new("ProximityPrompt")
							prompt.ActionText = "Buy Egg"
							prompt.ObjectText = egg.cost .. " DNA"
							prompt.HoldDuration = 0.4
							prompt.MaxActivationDistance = 14
							prompt.RequiresLineOfSight = false
							prompt:SetAttribute("EggKey", egg.key)
							prompt.Parent = promptParent
						end
					end
				end
			end
		end
	end
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
