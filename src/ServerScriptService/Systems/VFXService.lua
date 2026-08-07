-- VFXService -- ambient particle decor for the 20 zone platforms, plus the one proximity gate
-- every other system's world effects hang off.
--
-- Why the gate exists: the zone strip is 12,000 studs long and a player only ever stands in one
-- zone of it, but ParticleEmitters simulate whether or not anybody can see them. Twenty zones of
-- decor plus twenty boss auras left running is a few hundred emitters burning CPU for nobody.
-- Register() files an effect group under a world position; a single 0.75s loop enables only the
-- groups with a player inside their radius. Everything else sits at Enabled = false.

local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local GameConfig = require(RS.Modules.GameConfig)
local VFXLibrary = require(RS.Modules.VFXLibrary)

local VFXService = {}

-- ===== proximity gate ========================================================

local GATE_INTERVAL = 0.75
local registry = {} -- { root = Instance, pos = Vector3, radiusSq = number, on = boolean }

-- Files an effect group to be switched on only when somebody is near `position`. Groups start
-- disabled, so callers do not have to remember to switch them off themselves.
function VFXService.Register(root, position, radius)
	VFXLibrary.SetEnabled(root, false)
	table.insert(registry, {
		root = root,
		pos = position,
		radiusSq = radius * radius,
		on = false,
	})
end

local function runGate()
	local positions = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local character = plr.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp then
			table.insert(positions, hrp.Position)
		end
	end

	for i = #registry, 1, -1 do
		local entry = registry[i]
		if not entry.root.Parent then
			-- boss auras die with their boss; drop the entry rather than leak it
			table.remove(registry, i)
		else
			local near = false
			for _, p in ipairs(positions) do
				if (p - entry.pos).Magnitude ^ 2 <= entry.radiusSq then
					near = true
					break
				end
			end
			if near ~= entry.on then
				entry.on = near
				VFXLibrary.SetEnabled(entry.root, near)
			end
		end
	end
end

-- ===== zone decor ============================================================
-- Platforms are 450 wide (X) by 550 deep (Z), centred on zone.offset. Three areas are already
-- spoken for and must stay clear: the middle 60 studs (pet shop + creature spawns), the arrival
-- clearing around z = 174, and the boss standing at cx + 175. The four anchors below sit in the
-- leftover corners.
local ANCHORS = {
	Vector3.new(-165, 0, -175),
	Vector3.new(165, 0, -175),
	Vector3.new(-165, 0, 95),
	Vector3.new(165, 0, 95),
}

-- Two effects per zone, one of each kind, because they do different jobs:
--   ground -- mist/dust/fire pooling on the platform, read from eye level
--   air    -- sparkles and rifts overhead, read from across the zone
-- Heights are deliberately low. The first pass hung these at 26-40 studs and they registered as
-- specks against the skybox; at 12 they sit in the same frame as the player.
--
-- Only the generic white effects (stars, sparkles, charge, mist) get a colour forced on them.
-- Fire and water keep the pack's own gradients, which beat any flat tint.
-- Densities are combined particles/second for the whole effect, not multipliers: the pack ranges
-- from Smoke-01 at 5/s to Big-Crack-01 at 530/s, so a multiplier gives a different answer for
-- every zone. Ground mist wants some body; overhead glimmer wants to stay sparse.
local GROUND_Y, AIR_Y = 3, 12
local GROUND_SCALE, AIR_SCALE = 4, 3
local GROUND_RATE, AIR_RATE = 20, 9

-- The Beams pack (Waterfall/Lava/Wind) is deliberately unused here. Those effects span two
-- attachments and only make sense strung between real geometry -- placed on an anchor they hang
-- in mid-air with nothing above or below and read as a bug rather than scenery.
local ZONE_DECOR = {
	Forest          = { ground = { "Anime/Smoke-01", color = Color3.fromRGB(170, 220, 170) },     air = { "Anime/Stars-01", color = Color3.fromRGB(130, 230, 130) } },
	-- rate overrides below are for the few effects whose look depends on their own density:
	-- a tornado or an explosion normalised down to ambient level stops reading as either.
	Desert          = { ground = { "Anime/Wind-02", color = Color3.fromRGB(226, 200, 140) },      air = { "Anime/Shiny-01", color = Color3.fromRGB(240, 215, 150) } },
	Ocean           = { ground = { "Anime/Splash-01" },                                           air = { "Anime/Stars-01", color = Color3.fromRGB(90, 200, 255) } },
	Volcano         = { ground = { "Anime/Fire-01" },                                             air = { "Anime/Smoke-01", color = Color3.fromRGB(80, 55, 50) } },
	Moon            = { ground = { "Anime/Smoke-01", color = Color3.fromRGB(200, 200, 215) },     air = { "Anime/Stars-01", color = Color3.fromRGB(225, 225, 240) } },
	Mars            = { ground = { "Anime/Wind-02", color = Color3.fromRGB(200, 110, 70) },       air = { "Anime/Smoke-01", color = Color3.fromRGB(170, 90, 60) } },
	Galaxy          = { ground = { "Anime/Charge-01", color = Color3.fromRGB(150, 100, 230) },    air = { "Anime/Stars-01", color = Color3.fromRGB(160, 110, 240) } },
	BlackHole       = { ground = { "Anime/Portal-01", color = Color3.fromRGB(110, 40, 160) },     air = { "Big/Ball-01", scale = 1.6, color = Color3.fromRGB(70, 20, 110) } },
	Multiverse      = { ground = { "Anime/Portal-Enter-01", color = Color3.fromRGB(255, 100, 220) }, air = { "Anime/Stars-01", color = Color3.fromRGB(255, 140, 235) } },
	Nebula          = { ground = { "Anime/Shiny-01", color = Color3.fromRGB(210, 140, 245) },     air = { "Anime/Stars-01", color = Color3.fromRGB(190, 110, 230) } },
	Wormhole        = { ground = { "Anime/Portal-01", color = Color3.fromRGB(130, 90, 210) },     air = { "Big/Tornado-01", scale = 1.4, rate = 0.08, color = Color3.fromRGB(110, 70, 190) } },
	QuantumRealm    = { ground = { "Anime/ForceField-01", color = Color3.fromRGB(90, 230, 230) }, air = { "Anime/Lighting-02", color = Color3.fromRGB(120, 240, 240) } },
	TimeRift        = { ground = { "Anime/Charge-01", color = Color3.fromRGB(235, 195, 90) },     air = { "Anime/Shiny-01", color = Color3.fromRGB(245, 215, 130) } },
	AntimatterZone  = { ground = { "Anime/Fire-01", color = Color3.fromRGB(255, 70, 70) },        air = { "Big/Explosion-01", scale = 1.5, rate = 0.06, color = Color3.fromRGB(255, 100, 90) } },
	DreamDimension  = { ground = { "Anime/Smoke-01", color = Color3.fromRGB(160, 110, 220) },     air = { "Anime/Stars-01", color = Color3.fromRGB(205, 145, 255) } },
	MirrorUniverse  = { ground = { "Anime/ForceField-01", color = Color3.fromRGB(225, 225, 255) },air = { "Anime/Shiny-01", color = Color3.fromRGB(240, 240, 255) } },
	VoidExpanse     = { ground = { "Anime/Smoke-01", color = Color3.fromRGB(60, 30, 90) },        air = { "Anime/Portal-01", color = Color3.fromRGB(140, 60, 220) } },
	CelestialThrone = { ground = { "Anime/Shiny-01", color = Color3.fromRGB(255, 225, 140) },     air = { "Anime/Stars-01", color = Color3.fromRGB(255, 235, 170) } },
	Singularity     = { ground = { "Big/Ball-01", scale = 1.8, color = Color3.fromRGB(255, 255, 255) }, air = { "Anime/Portal-01", color = Color3.fromRGB(230, 230, 255) } },
	AbsolutePlane   = { ground = { "Anime/Charge-01", color = Color3.fromRGB(255, 215, 0) },      air = { "Anime/Shiny-01", color = Color3.fromRGB(255, 235, 130) } },
}

-- Anchors alternate ground/air so every corner has something and no two neighbours match:
-- two pools of mist on one diagonal, two glimmers overhead on the other.
local function buildZoneDecor(parent, zone)
	local decor = ZONE_DECOR[zone.key]
	if not decor then return end

	local cx = zone.offset
	local folder = Instance.new("Folder")
	folder.Name = zone.key
	folder.Parent = parent

	for i, anchor in ipairs(ANCHORS) do
		local isGround = (i % 2 == 1)
		local spec = isGround and decor.ground or decor.air
		local path = spec[1]
		if VFXLibrary.Exists(path) then
			local position = Vector3.new(cx + anchor.X, isGround and GROUND_Y or AIR_Y, anchor.Z)
			VFXLibrary.Place(folder, path, CFrame.new(position), {
				name = zone.key .. "_" .. i,
				scale = spec.scale or (isGround and GROUND_SCALE or AIR_SCALE),
				-- an explicit `rate` opts out of normalising, see the note on the table
				rate = spec.rate,
				targetRate = not spec.rate and (isGround and GROUND_RATE or AIR_RATE) or nil,
				color = spec.color,
			})
		else
			warn(("[VFXService] zone %s wants missing effect '%s'"):format(zone.key, path))
		end
	end

	-- one radius for the whole zone: the platform half-diagonal plus the road gap, so decor is
	-- already running by the time a player walks in off the road rather than popping on around them
	VFXService.Register(folder, Vector3.new(cx, 0, 0), 420)
end

function VFXService.Init()
	local existing = workspace:FindFirstChild("ZoneVFX")
	if existing then existing:Destroy() end

	local root = Instance.new("Folder")
	root.Name = "ZoneVFX"
	root.Parent = workspace

	for _, zone in ipairs(GameConfig.Zones) do
		buildZoneDecor(root, zone)
	end

	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < GATE_INTERVAL then return end
		accum = 0
		runGate()
	end)
end

return VFXService
