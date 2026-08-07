local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local PlayerDataService = require(script.Parent.PlayerDataService)
local DNAService = require(script.Parent.DNAService)
local Remotes = RS.Remotes

local CreatureService = {}

-- ===== base tier definitions (Forest baseline -- scaled per zone by mobHealthMult/
-- mobDamageMult/mobDnaMult in GameConfig.Zones, so creatures get stronger zone by zone) =====
local TIERS = {
	Critter = {
		health = 30,
		hitCooldown = 0.22,
		respawnDelay = 9,
		dnaMult = 4.5,
		size = 7,
		colors = { Color3.fromRGB(210, 70, 70), Color3.fromRGB(90, 170, 90), Color3.fromRGB(200, 150, 60) },
		label = "👾 Critter",
		retaliateChance = 0, -- doesn't fight back
		retaliateDamage = { 0, 0 },
		auraRange = 0, -- doesn't passively attack
	},
	Brute = {
		health = 70,
		hitCooldown = 0.22,
		respawnDelay = 16,
		dnaMult = 9,
		size = 10,
		colors = { Color3.fromRGB(90, 30, 110), Color3.fromRGB(40, 40, 50) },
		label = "💀 Brute",
		retaliateChance = 0.55, -- 55% chance to hit back when you attack it
		retaliateDamage = { 6, 12 },
		auraRange = 9, -- also periodically attacks anyone who lingers close
		auraDamage = { 4, 8 },
		auraInterval = 1.6,
	},
}

-- Relative (dx, dz) offsets from each zone's center (zone.offset) -- reused for every
-- zone so every zone gets the same layout of creatures, just shifted and scaled up.
local RELATIVE_SPAWN_POINTS = {
	Critter = {
		Vector3.new(70, 3.6, 60),
		Vector3.new(-100, 3.6, 100),
		Vector3.new(110, 3.6, -90),
		Vector3.new(-70, 3.6, -150),
		Vector3.new(20, 3.6, 180),
	},
	Brute = {
		Vector3.new(160, 5.1, -160),
		Vector3.new(-160, 5.1, 160),
		Vector3.new(0, 5.1, 220),
	},
}

local creaturesFolder = workspace:FindFirstChild("Creatures")
if not creaturesFolder then
	creaturesFolder = Instance.new("Folder")
	creaturesFolder.Name = "Creatures"
	creaturesFolder.Parent = workspace
end

local function hurtPlayer(player, amount)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	humanoid:TakeDamage(amount)
	Remotes.Notify:FireClient(player, { kind = "playerHurt", amount = math.floor(amount) })
end

-- ===== CREATURE RIG FACTORY ===================================================
-- Every creature used to be one coloured ball. Now each biome gets a hand-built rig
-- of anchored primitives (Block / Ball / Cylinder / Wedge) with its own silhouette,
-- tinted from that zone's palette so a Forest wolf and a Volcano wolf read as two
-- completely different animals. Rigs stay at or under 14 parts and are driven by
-- exactly one animation loop per creature (see the idle loop inside spawnCreature).

local IDENTITY = CFrame.new()
local INK = Color3.fromRGB(26, 18, 36) -- the same near-black the UI outlines use

local function lighten(c, f) return c:Lerp(Color3.fromRGB(255, 255, 255), f) end
local function darken(c, f) return c:Lerp(INK, f) end

-- zone.accentColor + zone.groundColor -> a small chunky palette. The dark "outline"
-- parts (joints, hooves, plates) are what stop a rig reading as a flat colour blob.
local function buildPalette(zone, tierName, tierColors)
	local accent = zone.accentColor
	local ground = zone.groundColor
	local isBrute = tierName == "Brute"
	local skin
	if isBrute then
		-- Brutes are the darker, meaner take on the same zone colour
		skin = darken(accent, 0.34)
	else
		skin = lighten(accent:Lerp(tierColors[math.random(1, #tierColors)], 0.3), 0.12)
	end
	return {
		skin = skin,
		belly = lighten(skin, 0.34),
		dark = darken(skin, 0.6),
		trim = darken(ground:Lerp(accent, 0.5), 0.25),
		glow = isBrute and Color3.fromRGB(255, 74, 58) or lighten(accent, 0.5),
		isBrute = isBrute,
	}
end

-- which archetype each of the 20 zones spawns
local ZONE_ARCHETYPE = {
	Forest          = "BEAST",
	Desert          = "ARACHNID",
	Ocean           = "AQUATIC",
	Volcano         = "MAGMA",
	Moon            = "DRIFTER",
	Mars            = "MECH",
	Galaxy          = "WRAITH",
	BlackHole       = "WRAITH",
	Multiverse      = "WRAITH",
	Nebula          = "DRIFTER",
	Wormhole        = "WRAITH",
	QuantumRealm    = "MECH",
	TimeRift        = "WRAITH",
	AntimatterZone  = "ARACHNID",
	DreamDimension  = "DRIFTER",
	MirrorUniverse  = "AQUATIC",
	VoidExpanse     = "WRAITH",
	CelestialThrone = "MAGMA",
	Singularity     = "MECH",
	AbsolutePlane   = "WRAITH",
}

local function mk(ctx, name, shape, size, color, material, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = ctx.model
	return p
end

-- pivot = the JOINT (pure translation from the body centre); rest = the part's own
-- offset/rotation out from that joint. The animation is applied BETWEEN the two, so a
-- leg swings around its hip instead of spinning around its own middle.
local function att(ctx, part, pivot, rest, motion, amp, speed, phase)
	rest = rest or IDENTITY
	local a = {
		part = part,
		pivot = pivot,
		rest = rest,
		offset = pivot * rest,
		motion = motion,
		amp = amp or 0,
		speed = speed or 1,
		phase = phase or 0,
	}
	table.insert(ctx.atts, a)
	part.CFrame = ctx.origin * a.offset
	return part
end

-- shared Brute dressing: a symmetric pair of shoulder spikes
local function bruteSpikes(ctx, x, y, z, len)
	local u, pal = ctx.u, ctx.pal
	for _, side in ipairs({ -1, 1 }) do
		local spike = mk(ctx, "Spike", Enum.PartType.Wedge, Vector3.new(u * 0.09, len, u * 0.16), pal.dark, Enum.Material.Slate)
		att(ctx, spike, CFrame.new(side * x, y, z), CFrame.Angles(math.rad(-18), 0, math.rad(side * 26)), "float", u * 0.015, 1.9, 0.4)
	end
end

local RIGS = {}

-- BEAST (Forest) -- wolf-like: four swinging legs, snout, ears, tail. 12 parts (13 Brute).
function RIGS.BEAST(ctx)
	local u, pal = ctx.u, ctx.pal
	local body = mk(ctx, "Body", Enum.PartType.Block, Vector3.new(u * 0.56, u * 0.44, u * 0.92), pal.skin)

	local head = mk(ctx, "Head", Enum.PartType.Block, Vector3.new(u * 0.42, u * 0.40, u * 0.40), pal.skin)
	att(ctx, head, CFrame.new(0, u * 0.26, -u * 0.56), IDENTITY, "float", u * 0.02, 1.9, 0.4)

	local snout = mk(ctx, "Snout", Enum.PartType.Block, Vector3.new(u * 0.24, u * 0.20, u * 0.30), pal.belly)
	att(ctx, snout, CFrame.new(0, u * 0.20, -u * 0.86), IDENTITY, "float", u * 0.02, 1.9, 0.4)

	for _, side in ipairs({ -1, 1 }) do
		local eye = mk(ctx, "Eye", Enum.PartType.Ball, Vector3.new(u * 0.12, u * 0.12, u * 0.12), pal.glow, Enum.Material.Neon)
		att(ctx, eye, CFrame.new(side * u * 0.13, u * 0.34, -u * 0.73), IDENTITY, "float", u * 0.02, 1.9, 0.4)

		if pal.isBrute then
			local horn = mk(ctx, "Horn", Enum.PartType.Wedge, Vector3.new(u * 0.10, u * 0.34, u * 0.15), pal.dark, Enum.Material.Slate)
			att(ctx, horn, CFrame.new(side * u * 0.17, u * 0.48, -u * 0.50), CFrame.Angles(math.rad(-22), 0, math.rad(side * 20)), "float", u * 0.02, 1.9, 0.4)
		else
			local ear = mk(ctx, "Ear", Enum.PartType.Wedge, Vector3.new(u * 0.08, u * 0.20, u * 0.14), pal.dark)
			att(ctx, ear, CFrame.new(side * u * 0.15, u * 0.46, -u * 0.50), CFrame.Angles(0, 0, math.rad(side * 12)), "float", u * 0.02, 1.9, 0.4)
		end
	end

	-- diagonal gait: front-left + back-right swing together
	local legPhase = { 0, math.pi, math.pi, 0 }
	local i = 0
	for _, dz in ipairs({ -u * 0.30, u * 0.32 }) do
		for _, dx in ipairs({ -u * 0.20, u * 0.20 }) do
			i += 1
			local leg = mk(ctx, "Leg", Enum.PartType.Block, Vector3.new(u * 0.14, u * 0.34, u * 0.15), pal.dark)
			att(ctx, leg, CFrame.new(dx, -u * 0.16, dz), CFrame.new(0, -u * 0.17, 0), "swing", 0.5, 3.2, legPhase[i])
		end
	end

	local tail = mk(ctx, "Tail", Enum.PartType.Block, Vector3.new(u * 0.11, u * 0.11, u * 0.44), pal.belly)
	att(ctx, tail, CFrame.new(0, u * 0.10, u * 0.46), CFrame.Angles(math.rad(-30), 0, 0) * CFrame.new(0, 0, u * 0.22), "trail", 0.45, 2.6, 0)

	if pal.isBrute then
		local plate = mk(ctx, "Plate", Enum.PartType.Wedge, Vector3.new(u * 0.30, u * 0.22, u * 0.34), pal.trim, Enum.Material.Slate)
		att(ctx, plate, CFrame.new(0, u * 0.24, u * 0.08), CFrame.Angles(0, math.rad(180), 0), nil)
	end

	return body
end

-- ARACHNID (Desert, AntimatterZone) -- low body, angled legs, raised stinger tail.
-- 12 parts (14 Brute: 8 legs instead of 6).
function RIGS.ARACHNID(ctx)
	local u, pal = ctx.u, ctx.pal
	local body = mk(ctx, "Body", Enum.PartType.Ball, Vector3.new(u * 0.58, u * 0.58, u * 0.58), pal.skin)

	local head = mk(ctx, "Head", Enum.PartType.Ball, Vector3.new(u * 0.38, u * 0.38, u * 0.38), pal.dark)
	att(ctx, head, CFrame.new(0, -u * 0.02, -u * 0.46), IDENTITY, "float", u * 0.015, 2.2, 0.6)

	for _, side in ipairs({ -1, 1 }) do
		local eye = mk(ctx, "Eye", Enum.PartType.Ball, Vector3.new(u * 0.11, u * 0.11, u * 0.11), pal.glow, Enum.Material.Neon)
		att(ctx, eye, CFrame.new(side * u * 0.11, u * 0.07, -u * 0.60), IDENTITY, "float", u * 0.015, 2.2, 0.6)
	end

	local rows = pal.isBrute and { -u * 0.30, -u * 0.10, u * 0.10, u * 0.30 } or { -u * 0.22, 0, u * 0.22 }
	local n = 0
	for _, dz in ipairs(rows) do
		for _, side in ipairs({ -1, 1 }) do
			n += 1
			local leg = mk(ctx, "Leg", Enum.PartType.Block, Vector3.new(u * 0.07, u * 0.62, u * 0.07), pal.dark)
			att(ctx, leg, CFrame.new(side * u * 0.24, u * 0.04, dz),
				CFrame.Angles(0, 0, math.rad(side * 32)) * CFrame.new(0, -u * 0.31, 0),
				"swing", 0.3, 3.6, n * 0.8)
		end
	end

	-- scorpion tail arching up over the back, stinger riding the same joint
	local tail = mk(ctx, "Tail", Enum.PartType.Block, Vector3.new(u * 0.11, u * 0.44, u * 0.11), pal.skin)
	att(ctx, tail, CFrame.new(0, u * 0.22, u * 0.24), CFrame.Angles(math.rad(-40), 0, 0) * CFrame.new(0, u * 0.22, 0), "trail", 0.28, 1.8, 0)

	local stinger = mk(ctx, "Stinger", Enum.PartType.Wedge, Vector3.new(u * 0.12, u * 0.22, u * 0.12), pal.glow, Enum.Material.Neon)
	att(ctx, stinger, CFrame.new(0, u * 0.22, u * 0.24),
		CFrame.Angles(math.rad(-40), 0, 0) * CFrame.new(0, u * 0.52, 0) * CFrame.Angles(math.rad(-55), 0, 0),
		"trail", 0.28, 1.8, 0)

	return body
end

-- AQUATIC (Ocean, MirrorUniverse) -- teardrop body, dorsal fin, forked tail, side fins.
-- 10 parts (12 Brute).
function RIGS.AQUATIC(ctx)
	local u, pal = ctx.u, ctx.pal
	local body = mk(ctx, "Body", Enum.PartType.Ball, Vector3.new(u * 0.62, u * 0.62, u * 0.62), pal.skin)

	local jaw = mk(ctx, "Head", Enum.PartType.Block, Vector3.new(u * 0.34, u * 0.09, u * 0.24), pal.dark)
	att(ctx, jaw, CFrame.new(0, -u * 0.10, -u * 0.28), IDENTITY, "float", u * 0.02, 2.4, 0.5)

	for _, side in ipairs({ -1, 1 }) do
		local eye = mk(ctx, "Eye", Enum.PartType.Ball, Vector3.new(u * 0.13, u * 0.13, u * 0.13), pal.glow, Enum.Material.Neon)
		att(ctx, eye, CFrame.new(side * u * 0.16, u * 0.10, -u * 0.22), IDENTITY, "float", u * 0.02, 2.4, 0.5)

		local fin = mk(ctx, "SideFin", Enum.PartType.Wedge, Vector3.new(u * 0.05, u * 0.20, u * 0.26), pal.trim)
		att(ctx, fin, CFrame.new(side * u * 0.26, -u * 0.04, -u * 0.04),
			CFrame.Angles(0, 0, math.rad(side * 70)) * CFrame.new(0, u * 0.13, 0),
			"flap", 0.4, 3.4, side > 0 and 0 or math.pi)
	end

	local dorsal = mk(ctx, "Dorsal", Enum.PartType.Wedge, Vector3.new(u * 0.06, u * 0.30, u * 0.36), pal.trim)
	att(ctx, dorsal, CFrame.new(0, u * 0.30, u * 0.04), CFrame.Angles(0, math.rad(180), 0), "float", u * 0.02, 2.4, 0.5)

	local stalk = mk(ctx, "Stalk", Enum.PartType.Block, Vector3.new(u * 0.18, u * 0.20, u * 0.40), pal.skin)
	att(ctx, stalk, CFrame.new(0, 0, u * 0.26), CFrame.new(0, 0, u * 0.20), "trail", 0.3, 3.0, 0)

	for _, dir in ipairs({ 1, -1 }) do
		local tailFin = mk(ctx, "TailFin", Enum.PartType.Wedge, Vector3.new(u * 0.06, u * 0.30, u * 0.26), pal.trim)
		att(ctx, tailFin, CFrame.new(0, 0, u * 0.26),
			CFrame.new(0, dir * u * 0.14, u * 0.50) * CFrame.Angles(0, 0, dir > 0 and 0 or math.rad(180)),
			"trail", 0.3, 3.0, 0)
	end

	if pal.isBrute then
		bruteSpikes(ctx, u * 0.18, u * 0.28, -u * 0.02, u * 0.26)
	end

	return body
end

-- MAGMA (Volcano, CelestialThrone) -- hunched rocky torso, glowing Neon cracks,
-- heavy swinging arms, stubby legs. 10 parts (12 Brute).
function RIGS.MAGMA(ctx)
	local u, pal = ctx.u, ctx.pal
	local body = mk(ctx, "Body", Enum.PartType.Block, Vector3.new(u * 0.72, u * 0.58, u * 0.52), pal.dark, Enum.Material.Slate)

	local head = mk(ctx, "Head", Enum.PartType.Block, Vector3.new(u * 0.38, u * 0.32, u * 0.36), pal.dark, Enum.Material.Slate)
	att(ctx, head, CFrame.new(0, u * 0.42, -u * 0.06), IDENTITY, "float", u * 0.02, 1.7, 0.3)

	for _, side in ipairs({ -1, 1 }) do
		local eye = mk(ctx, "Eye", Enum.PartType.Ball, Vector3.new(u * 0.11, u * 0.11, u * 0.11), pal.glow, Enum.Material.Neon)
		att(ctx, eye, CFrame.new(side * u * 0.11, u * 0.44, -u * 0.23), IDENTITY, "float", u * 0.02, 1.7, 0.3)

		local arm = mk(ctx, "Arm", Enum.PartType.Block, Vector3.new(u * 0.22, u * 0.44, u * 0.22), pal.skin, Enum.Material.Slate)
		att(ctx, arm, CFrame.new(side * u * 0.44, u * 0.18, 0), CFrame.new(0, -u * 0.22, 0), "swing", 0.45, 2.4, side > 0 and 0 or math.pi)

		local leg = mk(ctx, "Leg", Enum.PartType.Block, Vector3.new(u * 0.22, u * 0.26, u * 0.24), pal.skin, Enum.Material.Slate)
		att(ctx, leg, CFrame.new(side * u * 0.22, -u * 0.24, 0), CFrame.new(0, -u * 0.13, 0), "swing", 0.22, 2.4, side > 0 and math.pi or 0)
	end

	for i, dy in ipairs({ u * 0.10, -u * 0.10 }) do
		local crack = mk(ctx, "Crack", Enum.PartType.Block, Vector3.new(u * 0.48, u * 0.07, u * 0.03), pal.glow, Enum.Material.Neon)
		att(ctx, crack, CFrame.new(0, dy, -u * 0.27), CFrame.Angles(0, 0, math.rad(i == 1 and 9 or -12)), nil)
	end

	if pal.isBrute then
		bruteSpikes(ctx, u * 0.40, u * 0.36, 0, u * 0.30)
	end

	return body
end

-- DRIFTER (Moon, Nebula, DreamDimension) -- floating orb core with orbiting shards,
-- no legs at all. 10 parts (12 Brute).
function RIGS.DRIFTER(ctx)
	local u, pal = ctx.u, ctx.pal
	local body = mk(ctx, "Body", Enum.PartType.Ball, Vector3.new(u * 0.54, u * 0.54, u * 0.54), pal.skin, Enum.Material.SmoothPlastic, 0.3)

	local coreGlow = mk(ctx, "Head", Enum.PartType.Ball, Vector3.new(u * 0.30, u * 0.30, u * 0.30), pal.glow, Enum.Material.Neon)
	att(ctx, coreGlow, IDENTITY, IDENTITY, "float", u * 0.03, 1.4, 0)

	for _, side in ipairs({ -1, 1 }) do
		local eye = mk(ctx, "Eye", Enum.PartType.Ball, Vector3.new(u * 0.12, u * 0.12, u * 0.12), pal.glow, Enum.Material.Neon)
		att(ctx, eye, CFrame.new(side * u * 0.11, u * 0.06, -u * 0.24), IDENTITY, "float", u * 0.03, 1.4, 0)
	end

	-- shards revolve around the core: pivot is the core centre, rest pushes them out
	local shardCount = pal.isBrute and 8 or 6
	for i = 1, shardCount do
		local shard = mk(ctx, "Shard", Enum.PartType.Wedge, Vector3.new(u * 0.10, u * 0.26, u * 0.10), pal.trim, Enum.Material.Metal)
		local ring = (i % 2 == 0) and u * 0.15 or -u * 0.15
		att(ctx, shard, IDENTITY,
			CFrame.new(u * 0.46, ring, 0) * CFrame.Angles(0, 0, math.rad(i % 2 == 0 and 26 or -26)),
			"orbit", 0, (i % 2 == 0) and 0.9 or -0.7, (i - 1) * (math.pi * 2 / shardCount))
	end

	return body
end

-- MECH (Mars, QuantumRealm, Singularity) -- boxy torso, piston legs, antenna,
-- glowing visor. 11 parts (13 Brute).
function RIGS.MECH(ctx)
	local u, pal = ctx.u, ctx.pal
	local body = mk(ctx, "Body", Enum.PartType.Block, Vector3.new(u * 0.58, u * 0.54, u * 0.40), pal.skin, Enum.Material.Metal)

	local head = mk(ctx, "Head", Enum.PartType.Block, Vector3.new(u * 0.34, u * 0.26, u * 0.30), pal.dark, Enum.Material.Metal)
	att(ctx, head, CFrame.new(0, u * 0.42, 0), IDENTITY, "float", u * 0.015, 2.0, 0.2)

	local visor = mk(ctx, "Visor", Enum.PartType.Block, Vector3.new(u * 0.30, u * 0.09, u * 0.04), pal.glow, Enum.Material.Neon)
	att(ctx, visor, CFrame.new(0, u * 0.44, -u * 0.16), IDENTITY, "float", u * 0.015, 2.0, 0.2)

	-- Cylinder length runs along X, so roll it 90 degrees to stand it upright
	local rod = mk(ctx, "Antenna", Enum.PartType.Cylinder, Vector3.new(u * 0.26, u * 0.05, u * 0.05), pal.dark, Enum.Material.Metal)
	att(ctx, rod, CFrame.new(0, u * 0.56, 0), CFrame.new(0, u * 0.13, 0) * CFrame.Angles(0, 0, math.rad(90)), "trail", 0.22, 2.2, 0)

	local tip = mk(ctx, "AntennaTip", Enum.PartType.Ball, Vector3.new(u * 0.10, u * 0.10, u * 0.10), pal.glow, Enum.Material.Neon)
	att(ctx, tip, CFrame.new(0, u * 0.56, 0), CFrame.new(0, u * 0.30, 0), "trail", 0.22, 2.2, 0)

	for _, side in ipairs({ -1, 1 }) do
		local pad = mk(ctx, "Shoulder", Enum.PartType.Block, Vector3.new(u * 0.16, u * 0.14, u * 0.26), pal.dark, Enum.Material.Metal)
		att(ctx, pad, CFrame.new(side * u * 0.36, u * 0.24, 0), IDENTITY, nil)

		local arm = mk(ctx, "Arm", Enum.PartType.Block, Vector3.new(u * 0.14, u * 0.38, u * 0.16), pal.trim, Enum.Material.Metal)
		att(ctx, arm, CFrame.new(side * u * 0.36, u * 0.14, 0), CFrame.new(0, -u * 0.19, 0), "swing", 0.4, 2.8, side > 0 and 0 or math.pi)

		local leg = mk(ctx, "Leg", Enum.PartType.Block, Vector3.new(u * 0.16, u * 0.28, u * 0.18), pal.dark, Enum.Material.Metal)
		att(ctx, leg, CFrame.new(side * u * 0.18, -u * 0.22, 0), CFrame.new(0, -u * 0.14, 0), "swing", 0.35, 2.8, side > 0 and math.pi or 0)
	end

	if pal.isBrute then
		bruteSpikes(ctx, u * 0.34, u * 0.34, 0, u * 0.28)
	end

	return body
end

-- WRAITH (Galaxy, BlackHole, Multiverse, Wormhole, TimeRift, VoidExpanse,
-- AbsolutePlane) -- tapered semi-transparent body, trailing tendrils, Neon eyes.
-- 10 parts (12 Brute).
function RIGS.WRAITH(ctx)
	local u, pal = ctx.u, ctx.pal
	local body = mk(ctx, "Body", Enum.PartType.Ball, Vector3.new(u * 0.60, u * 0.60, u * 0.60), pal.skin, Enum.Material.SmoothPlastic, 0.4)

	local cowl = mk(ctx, "Head", Enum.PartType.Ball, Vector3.new(u * 0.46, u * 0.46, u * 0.46), pal.dark, Enum.Material.SmoothPlastic, 0.2)
	att(ctx, cowl, CFrame.new(0, u * 0.22, -u * 0.06), IDENTITY, "float", u * 0.035, 1.3, 0)

	local core = mk(ctx, "Core", Enum.PartType.Ball, Vector3.new(u * 0.24, u * 0.24, u * 0.24), pal.glow, Enum.Material.Neon)
	att(ctx, core, IDENTITY, IDENTITY, "float", u * 0.04, 1.1, 1.2)

	for _, side in ipairs({ -1, 1 }) do
		local eye = mk(ctx, "Eye", Enum.PartType.Ball, Vector3.new(u * 0.13, u * 0.13, u * 0.13), pal.glow, Enum.Material.Neon)
		att(ctx, eye, CFrame.new(side * u * 0.12, u * 0.24, -u * 0.26), IDENTITY, "float", u * 0.035, 1.3, 0)
	end

	local tendrils = pal.isBrute and 7 or 5
	for i = 1, tendrils do
		local a = (i - 1) * (math.pi * 2 / tendrils)
		local tendril = mk(ctx, "Tendril", Enum.PartType.Block, Vector3.new(u * 0.09, u * 0.40, u * 0.09), pal.skin, Enum.Material.SmoothPlastic, 0.25)
		att(ctx, tendril, CFrame.new(math.cos(a) * u * 0.18, -u * 0.10, math.sin(a) * u * 0.18),
			CFrame.new(0, -u * 0.20, 0), "trail", 0.5, 2.0 + i * 0.13, i * 0.9)
	end

	return body
end

-- Builds the rig for a zone and returns the primary body plus the flat attachments
-- list the idle loop drives. Every rig keeps its body part at the model origin so
-- body.Position stays the spawn position (aura range + billboard depend on that).
local function buildRig(model, position, tierName, zone, tier)
	local ctx = {
		model = model,
		origin = CFrame.new(position),
		u = tier.size,
		pal = buildPalette(zone, tierName, tier.colors),
		atts = {},
	}
	local archetype = ZONE_ARCHETYPE[zone.key] or "BEAST"
	local builder = RIGS[archetype] or RIGS.BEAST
	local body = builder(ctx)
	body.Name = "Body"
	body.CanCollide = true
	body.CFrame = ctx.origin
	model.PrimaryPart = body
	model:SetAttribute("Archetype", archetype)
	return body, ctx.atts
end

local function spawnCreature(position, tierName, zone)
	local base = TIERS[tierName]
	-- effective (zone-scaled) stats for this specific spawn
	local tier = {
		health = math.floor(base.health * zone.mobHealthMult),
		hitCooldown = base.hitCooldown,
		respawnDelay = base.respawnDelay,
		dnaMult = base.dnaMult * zone.mobDnaMult,
		size = base.size,
		colors = base.colors,
		label = base.label .. " (" .. zone.name .. ")",
		retaliateChance = base.retaliateChance,
		retaliateDamage = { math.floor(base.retaliateDamage[1] * zone.mobDamageMult), math.floor(base.retaliateDamage[2] * zone.mobDamageMult) },
		auraRange = base.auraRange,
		auraDamage = base.auraDamage and { math.floor(base.auraDamage[1] * zone.mobDamageMult), math.floor(base.auraDamage[2] * zone.mobDamageMult) } or nil,
		auraInterval = base.auraInterval,
	}

	local model = Instance.new("Model")
	model.Name = tierName

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(tier.size, tier.size, tier.size)
	body.Material = tierName == "Brute" and Enum.Material.Slate or Enum.Material.SmoothPlastic
	body.Color = tier.colors[math.random(1, #tier.colors)]
	body.Anchored = true
	body.CanCollide = true
	body.CFrame = CFrame.new(position)
	body.Parent = model
	model.PrimaryPart = body

	local eyeSize = tierName == "Brute" and 1.2 or 0.9
	local eyeL = Instance.new("Part")
	eyeL.Name = "EyeL"
	eyeL.Shape = Enum.PartType.Ball
	eyeL.Size = Vector3.new(eyeSize, eyeSize, eyeSize)
	eyeL.Color = tierName == "Brute" and Color3.fromRGB(255, 40, 40) or Color3.fromRGB(20, 20, 20)
	eyeL.Material = tierName == "Brute" and Enum.Material.Neon or Enum.Material.SmoothPlastic
	eyeL.Anchored = true
	eyeL.CanCollide = false
	local eyeLOffset = CFrame.new(-tier.size * 0.22, tier.size * 0.13, -tier.size * 0.44)
	eyeL.CFrame = body.CFrame * eyeLOffset
	eyeL.Parent = model

	local eyeR = eyeL:Clone()
	eyeR.Name = "EyeR"
	local eyeROffset = CFrame.new(tier.size * 0.22, tier.size * 0.13, -tier.size * 0.44)
	eyeR.CFrame = body.CFrame * eyeROffset
	eyeR.Parent = model

	-- simple mouth so the face reads as a creature, not a bare ball
	local mouth = Instance.new("Part")
	mouth.Name = "Mouth"
	mouth.Size = Vector3.new(tier.size * 0.5, tier.size * 0.08, tier.size * 0.06)
	mouth.Color = Color3.fromRGB(15, 15, 15)
	mouth.Material = Enum.Material.SmoothPlastic
	mouth.Anchored = true
	mouth.CanCollide = false
	local mouthOffset = CFrame.new(0, -tier.size * 0.14, -tier.size * 0.46)
	mouth.CFrame = body.CFrame * mouthOffset
	mouth.Parent = model

	local attachments = {
		{ part = eyeL, offset = eyeLOffset },
		{ part = eyeR, offset = eyeROffset },
		{ part = mouth, offset = mouthOffset },
	}

	-- Brutes get small horns for a tougher, more monstrous silhouette
	if tierName == "Brute" then
		for _, side in ipairs({ -1, 1 }) do
			local horn = Instance.new("Part")
			horn.Name = "Horn"
			horn.Shape = Enum.PartType.Wedge
			horn.Size = Vector3.new(tier.size * 0.16, tier.size * 0.42, tier.size * 0.16)
			horn.Color = Color3.fromRGB(25, 25, 28)
			horn.Material = Enum.Material.Slate
			horn.Anchored = true
			horn.CanCollide = false
			local hornOffset = CFrame.new(side * tier.size * 0.28, tier.size * 0.44, -tier.size * 0.05) * CFrame.Angles(math.rad(-70), 0, 0)
			horn.CFrame = body.CFrame * hornOffset
			horn.Parent = model
			table.insert(attachments, { part = horn, offset = hornOffset })
		end
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 130, 0, 34)
	billboard.StudsOffset = Vector3.new(0, tier.size * 0.8, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 45
	billboard.Parent = body

	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.new(1, 0, 0, 8)
	barBg.Position = UDim2.new(0, 0, 1, -8)
	barBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	barBg.BorderSizePixel = 0
	barBg.Parent = billboard

	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.Size = UDim2.new(1, 0, 1, 0)
	barFill.BackgroundColor3 = tierName == "Brute" and Color3.fromRGB(200, 60, 60) or Color3.fromRGB(90, 220, 100)
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0, 20)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextStrokeTransparency = 0.5
	nameLabel.Text = tier.label
	nameLabel.Parent = billboard

	local clickDetector = Instance.new("ClickDetector")
	clickDetector.MaxActivationDistance = 14
	clickDetector.Parent = body

	model:SetAttribute("Health", tier.health)
	model.Parent = creaturesFolder

	-- gentle idle bob + sway so creatures read as alive instead of frozen statues
	task.spawn(function()
		local t0 = os.clock() - (position.X % 6.28)
		while body.Parent do
			local t = os.clock() - t0
			local bob = math.sin(t * 1.6) * (tier.size * 0.05)
			local sway = math.sin(t * 0.6) * 0.12
			local base = CFrame.new(position.X, position.Y + bob, position.Z) * CFrame.Angles(0, sway, 0)
			body.CFrame = base
			for _, att in ipairs(attachments) do
				if att.part.Parent then
					att.part.CFrame = base * att.offset
				end
			end
			task.wait(0.05)
		end
	end)

	local lastHitByPlayer = {}
	local dead = false
	local auraConnection

	if tier.auraRange and tier.auraRange > 0 then
		local lastAuraHit = {}
		local accum = 0
		auraConnection = RunService.Heartbeat:Connect(function(dt)
			if dead or not model.Parent then return end
			accum += dt
			if accum < tier.auraInterval then return end
			accum = 0
			for _, plr in ipairs(Players:GetPlayers()) do
				local character = plr.Character
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				if hrp and (hrp.Position - body.Position).Magnitude <= tier.auraRange then
					hurtPlayer(plr, math.random(tier.auraDamage[1], tier.auraDamage[2]))
				end
			end
		end)
	end

	clickDetector.MouseClick:Connect(function(player)
		if dead or not model.Parent then return end
		local data = PlayerDataService.Get(player)
		if not data then return end
		local now = os.clock()
		if lastHitByPlayer[player.UserId] and now - lastHitByPlayer[player.UserId] < tier.hitCooldown then
			return
		end
		lastHitByPlayer[player.UserId] = now

		-- player's outgoing damage scales with their evolution stage -- stronger stage,
		-- stronger hits, which is what lets them keep pace with tougher zone creatures
		local playerDamage = DNAService.GetCombatDamage(data)
		local health = math.max((model:GetAttribute("Health") or tier.health) - playerDamage, 0)
		model:SetAttribute("Health", health)
		barFill.Size = UDim2.new(math.clamp(health / tier.health, 0, 1), 0, 1, 0)

		local grow = TweenService:Create(body, TweenInfo.new(0.07), { Size = Vector3.new(tier.size, tier.size, tier.size) * 1.08 })
		grow:Play()
		task.delay(0.07, function()
			if body and body.Parent then
				TweenService:Create(body, TweenInfo.new(0.09), { Size = Vector3.new(tier.size, tier.size, tier.size) }):Play()
			end
		end)

		-- retaliation: tougher creatures can hit back when attacked
		if health > 0 and tier.retaliateChance > 0 and math.random() < tier.retaliateChance then
			hurtPlayer(player, math.random(tier.retaliateDamage[1], tier.retaliateDamage[2]))
		end

		if health <= 0 and not dead then
			dead = true
			if auraConnection then auraConnection:Disconnect() end
			local amount = DNAService.GetClickAmount(data) * tier.dnaMult
			data.DNA += amount
			data.XP = (data.XP or 0) + (tierName == "Brute" and 2 or 1)
			PlayerDataService.UpdateLeaderstats(player)
			PlayerDataService.PushToClient(player)
			Remotes.Notify:FireClient(player, { kind = "creature", amount = math.floor(amount) })

			model:Destroy()
			task.delay(tier.respawnDelay, function()
				spawnCreature(position, tierName, zone)
			end)
		end
	end)

	return model
end

function CreatureService.Init()
	for _, existing in ipairs(creaturesFolder:GetChildren()) do
		existing:Destroy()
	end
	for _, zone in ipairs(GameConfig.Zones) do
		for _, rel in ipairs(RELATIVE_SPAWN_POINTS.Critter) do
			local pos = Vector3.new(zone.offset + rel.X, rel.Y, rel.Z)
			spawnCreature(pos, "Critter", zone)
		end
		for _, rel in ipairs(RELATIVE_SPAWN_POINTS.Brute) do
			local pos = Vector3.new(zone.offset + rel.X, rel.Y, rel.Z)
			spawnCreature(pos, "Brute", zone)
		end
	end
end

return CreatureService
