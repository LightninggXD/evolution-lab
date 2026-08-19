-- BiomeDecor -- what each of the twenty zones is DRESSED IN, once its ground and its terraces
-- exist. Four shared layers and twenty signature builders that arrange them.
--
-- THE FOUR LAYERS, which is the whole design and is worth stating once: a GROUND layer of
-- scattered rocks and mounds, a MID layer of the zone's own props, one big LANDMARK silhouette at
-- the back of the platform, and an ATMOSPHERE emitter -- plus lighting accents, so no platform
-- ever reads as an empty coloured rectangle. `buildBiomeBase` takes one table describing all four
-- and builds them; a zone's builder is mostly that call plus whatever makes the zone itself.
--
-- WHERE THE LINE IS: this file owns what a zone is decorated WITH. `ZoneBuilder` owns the ground
-- it stands on, the terraces around it, the walls, the gates, the village, the eggs and the boss
-- arena -- and it owns the zone loop that calls in here, once per zone, through
-- `decorationBuilders[zone.key]`.
--
-- WHY IT IS ONE FILE AND NOT THE FOUR `docs/SPLIT.md` §6 ASKED FOR
-- ----------------------------------------------------------------
-- §6 names the ground clutter, the idols and the mesh prop layer as three separate leaves and the
-- decoration builders as a fourth. Measured, they are one thing wearing four section headers:
-- the eight `add*` layer verbs have exactly one caller between them (`buildBiomeBase`),
-- `buildBiomeBase` has exactly one set of callers (the twenty builders), and the twenty are read
-- by exactly one line in `Build()`. **One name escapes this file.** Cutting anywhere else would
-- mean inventing a surface nothing had asked for.
--
-- THE TWENTY WERE NOT IN ONE PLACE BEFORE THIS. `Forest` was written 1,000 lines above `Desert`
-- with the whole egg section and the egg plaza wedged between them -- not a decision, just where
-- the eggs got pasted. They are consecutive here, in zone order.
--
-- `ACTIVE_ZONE_KEY` LIVES HERE NOW AND IS REACHED THROUGH `setZoneKey`. It is reassigned per zone,
-- so a copy taken at require time would be frozen at nil forever and silently -- `docs/SPLIT.md`
-- §3 rule 2, the trap `ACTIVE_FRAME` and the village palette have each already paid for. All nine
-- of its readers are in this file; both of its writers are in `ZoneBuilder`'s zone loop.
--
-- WHO MAY REQUIRE IT: any server script decorating a zone platform. `ZoneBuilder` today. A caller
-- that runs `decorationBuilders[key]` without calling `setZoneKey(key)` first gets a zone with no
-- mesh props and no mesh landmark, and no error -- see `setZoneKey`.
--
-- Where the rest of the world is built: `docs/CODEMAP.md`, `docs/SPLIT.md` §6.

local ServerStorage = game:GetService("ServerStorage")

-- The vocabulary this file is written in. `ZoneKit` is what a part is made of; `ScatterKit` is
-- where a prop may stand and the ground it takes when it does. Both are re-localised for the
-- reason both of them give: `scatterPoint` alone is read 82 times below.
local ZoneKit = require(script.Parent.ZoneKit)
local ScatterKit = require(script.Parent.ScatterKit)

local newPart, addLight, seatModel = ZoneKit.newPart, ZoneKit.addLight, ZoneKit.seatModel
local lighten, darken = ZoneKit.lighten, ZoneKit.darken
local PLATFORM_DEPTH, PLATFORM_WIDTH = ZoneKit.PLATFORM_DEPTH, ZoneKit.PLATFORM_WIDTH
local scatterPoint, reserveScatter = ScatterKit.scatterPoint, ScatterKit.reserveScatter
local scaled, STREET_HALF = ScatterKit.scaled, ScatterKit.STREET_HALF

-- ===== WHICH ZONE IS BEING BUILT RIGHT NOW =====
--
-- Two builders below need a mesh keyed by zone and are handed everything except the zone:
-- `addMeshProps` looks for `Prop_<key>_<slot>` and `addLandmark` for `Landmark_<key>`. Rather than
-- thread a zone through nine layers of table-driven config, the zone loop sets this around the
-- decoration pass and clears it after.
--
-- IT IS REACHED THROUGH `setZoneKey` AND NOT EXPORTED AS A VALUE, and that is not decoration: it
-- is reassigned per zone, so a copy taken at require time on the other side of the boundary would
-- be frozen at nil forever with nothing in the log -- `docs/SPLIT.md` §3 rule 2. `ZoneKit`'s
-- placement frame is the same shape for the same reason.
--
-- WHAT A MISSING CALL COSTS, so it is written down somewhere: nil is a legal value here and both
-- readers treat it as "no mesh available" and fall back to block-built geometry. A zone decorated
-- without `setZoneKey` therefore comes out looking slightly plain and entirely unbroken, which is
-- the failure mode you do not notice for a month.
local ACTIVE_ZONE_KEY = nil

local function setZoneKey(key)
	ACTIVE_ZONE_KEY = key
end

-- ===== shared decoration helpers =====
-- Every zone is dressed in four layers -- a GROUND layer of scattered rocks/mounds, a MID
-- layer of signature biome props, one big LANDMARK silhouette at the back of the platform,
-- and an ATMOSPHERE emitter -- plus LIGHTING ACCENTS, so no platform ever reads as an empty
-- rectangle. The Desert builder was the quality bar; these helpers make it cheap to hit it
-- in all 20 biomes without copy-pasting the same scatter loops twenty times.

-- THE PLACEMENT RULES ARE IN `ScatterKit` and the colour verbs in `ZoneKit`; both arrive
-- re-localised at the top of this file. What follows is the four layers themselves, in the order
-- `buildBiomeBase` builds them.

-- GROUND LAYER: low scattered rocks / shards / debris that break up the flat floor.
local function addGroundLitter(model, cx, cfg)
	local colors = cfg.colors
	local flat = cfg.flat or 0.6
	for _ = 1, scaled(cfg.count, 16) do
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

-- ===== GROUND CLUTTER, FROM THE SHARED MESH LIBRARY =====
--
-- `ServerStorage.PropMeshes.Gnd_<Thing>` -- rocks, log, bush, stump, flowers, tuft, mushroom, fern,
-- crystal, bones. Ten models SHARED by all twenty zones, where CANOPY/BOULDER/FLORA/STRUCTURE are
-- one set per zone. That split is on purpose: a zone's identity comes from its big silhouettes, and
-- a fern is a fern in any biome. Ten shared models cover twenty zones for the price of one set.
--
-- WHICH ONES A ZONE GETS IS THE ONLY PER-BIOME DECISION, and it is what stops the Moon growing
-- bushes. Anything absent from this table takes DEFAULT_CLUTTER, so a new zone needs no entry at
-- all -- the same opt-out shape the idols and the landmark already use.
local DEFAULT_CLUTTER = { "Rocks", "Tuft", "Crystal" }
local ZONE_CLUTTER = {
	Forest         = { "Rocks", "Log", "Bush", "Stump", "Flowers", "Tuft", "Mushroom", "Fern" },
	Desert         = { "Rocks", "Bones", "Tuft", "Stump" },
	Ocean          = { "Rocks", "Tuft", "Bush", "Crystal" },
	Volcano        = { "Rocks", "Bones", "Crystal" },
	Moon           = { "Rocks", "Crystal" },
	Mars           = { "Rocks", "Bones", "Crystal" },
	Galaxy         = { "Rocks", "Crystal" },
	BlackHole      = { "Rocks", "Crystal", "Bones" },
	Multiverse     = { "Rocks", "Crystal", "Tuft" },
	Nebula         = { "Rocks", "Crystal", "Mushroom" },
	Wormhole       = { "Rocks", "Crystal" },
	QuantumRealm   = { "Rocks", "Crystal" },
	TimeRift       = { "Rocks", "Stump", "Tuft", "Bones" },
	AntimatterZone = { "Rocks", "Crystal", "Bones" },
	DreamDimension = { "Flowers", "Mushroom", "Tuft", "Bush" },
	MirrorUniverse = { "Rocks", "Crystal" },
	VoidExpanse    = { "Rocks", "Bones", "Crystal" },
	CelestialThrone= { "Rocks", "Flowers", "Tuft" },
	Singularity    = { "Rocks", "Crystal" },
	AbsolutePlane  = { "Rocks", "Crystal" },
}

local function addGroundClutter(model, cx)
	local lib = ServerStorage:FindFirstChild("PropMeshes")
	if not (lib and ACTIVE_ZONE_KEY) then return end
	local picks = ZONE_CLUTTER[ACTIVE_ZONE_KEY] or DEFAULT_CLUTTER

	-- 26 pieces spread over the valley floor. These are SMALL -- 4 to 11 studs -- so they are what
	-- the player walks past rather than around, which is exactly the layer that was still primitives
	-- while the trees and boulders became meshes.
	for _ = 1, 26 do
		local template = lib:FindFirstChild("Gnd_" .. picks[math.random(1, #picks)])
		if template then
			local clone = template:Clone()
			local _, raw = clone:GetBoundingBox()
			local want = 4 + math.random() * 7
			clone:ScaleTo(want / math.max(raw.Y, 0.1))
			for _, part in ipairs(clone:GetDescendants()) do
				if part:IsA("BasePart") then
					-- generated meshes arrive UNANCHORED, and nothing else here anchors them
					part.Anchored = true
					-- small enough to step over: colliding with these would make the floor sticky
					part.CanCollide = false
					part.CastShadow = false
				end
			end
			clone.Name = "GroundClutter"
			clone.Parent = model
			-- halfSize 6 so a clump never lands inside the street, a gate mouth or the boss arena;
			-- no reserveScatter afterwards, deliberately -- these are ground cover and something
			-- bigger landing over one of them costs nothing, where 26 more reservations a zone would
			-- crowd out the props that actually need the room.
			local x, z = scatterPoint(cx, 320, 400, 6)
			seatModel(clone, x, z, math.random() * math.pi * 2, 0.3)
		end
	end
end

-- GROUND LAYER: wide, very low mounds so the floor has some relief instead of being a plane.
local function addMounds(model, cx, cfg)
	for _ = 1, scaled(cfg.count, 5) do
		-- spread widened with the platform: at 190 every mound in the game sat in the same middle
		-- third of it and the new ground out by the walls was flat
		local x, z = scatterPoint(cx, 300, 260)
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
		-- This is a 640 x 800 invisible sheet lying across the whole platform at head height, and it
		-- was queryable. Every mouse ray cast from a camera above it -- which is every camera in the
		-- game -- struck this first, so Mouse.Target anywhere inside a zone was the atmosphere carrier
		-- and never the thing under the cursor. It carries an emitter and nothing else; it should
		-- never have been in the way of anything.
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
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
	for _ = 1, scaled(cfg.count, 5) do
		local x, z = scatterPoint(cx, 310, 265)
		local h = cfg.height or math.random(10, 20)
		newPart({ Name = "GlowPost", Size = Vector3.new(1.8, h, 1.8), Position = Vector3.new(x, h / 2, z), Color = darken(color, 0.65), Material = Enum.Material.Metal, CanCollide = false, Parent = model })
		local bulb = newPart({ Name = "GlowBulb", Shape = Enum.PartType.Ball, Size = Vector3.new(4.5, 4.5, 4.5), Position = Vector3.new(x, h + 1.5, z), Color = color, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(bulb, color, cfg.range or 28, cfg.brightness or 2)
	end
end

-- LANDMARK: one big silhouette feature near the back of the platform (z ~ -210) so the zone
-- reads from a distance. Every landmark stands on a lit plinth and is framed by two braziers,
-- so it looks like a built site rather than a lone prop dropped on the floor.
-- ONE MONUMENT PER ZONE INSTEAD OF SEVEN STYLES SHARED BETWEEN TWENTY. Same argument as the
-- Guardian Titan: the landmark's whole job is to be the thing you recognise a zone by from the
-- arrival gate, and `arch` was doing that job in three different zones at once. A filed
-- Landmark_<ZoneKey> replaces the block build; a zone without one keeps its style unchanged, so
-- this rolls out one mesh at a time like everything else here.
--
-- 118 tall against the block landmarks' ~110, capped at 96 wide so it stays on its own plinth.
local LANDMARK_HEIGHT = 118
local LANDMARK_WIDTH = 96

local function landmarkFigure()
	local folder = ServerStorage:FindFirstChild("PropMeshes")
	local template = ACTIVE_ZONE_KEY and folder and folder:FindFirstChild("Landmark_" .. ACTIVE_ZONE_KEY)
	if not template then return nil end
	local figure = template:Clone()
	local _, raw = figure:GetBoundingBox()
	figure:ScaleTo(math.min(LANDMARK_HEIGHT / math.max(raw.Y, 1), LANDMARK_WIDTH / math.max(raw.X, raw.Z, 1)))
	figure.Name = "LandmarkFigure"
	for _, d in ipairs(figure:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			-- solid, unlike the props: this one stands at the back of the platform where players do
			-- walk, and the block landmark it replaces was collidable too
			d.CanCollide = true
		end
	end
	return figure
end

local function addLandmark(model, cx, cfg)
	local z = cfg.z or -480
	-- ...but no longer on the centre line. The gate to the next zone opens in the middle of the -Z
	-- wall, and a 104-stud plinth centred on cx stood squarely in its approach. Back-left keeps the
	-- silhouette in shot from the moment you arrive without blocking the walk out.
	cx = cx + (cfg.dx or -210)
	local base = cfg.base
	local accent = cfg.accent
	local mat = cfg.material or Enum.Material.Rock
	local lit = {}

	-- LOOKED UP BEFORE THE PLINTH IS BUILT, because the plinth has to be sized for whatever is
	-- going to stand on it. 96 x 62 was cut for the block builds; a 96-wide mesh on it leaves no
	-- base showing at all, and the two braziers below would be swallowed by their own pedestal.
	local figure = landmarkFigure()
	-- how far out the two braziers stand, and how far forward. Set with the dais below when there
	-- is one, because a post planted inside the plinth is a post you never see.
	local postX, postZ = 60, 12

	if figure then
		-- THE DAIS IS SIZED TO WHAT STANDS ON IT, not to a constant. These twenty monuments run 43 to
		-- 96 studs wide: a base cut for the widest is a parade ground under the narrowest, and the
		-- Forest shrine duly came out standing in the middle of 135 x 99 studs of empty stone.
		-- Measured here, before the figure is parented -- GetBoundingBox covers every descendant, so
		-- once it is inside the zone model it is measuring the zone.
		local _, fs = figure:GetBoundingBox()
		local sw = math.max(fs.X, 52) + 20
		local sd = math.max(fs.Z, 44) + 20
		postX, postZ = (sw + 18) / 2 + 14, 14
		-- THE TRIM IS WIDER THAN THE PLINTH IT TRIMS, and it always was: 104 x 70 of full-bright
		-- Neon laid over a 96 x 62 base covers it completely, so what a player sees at the foot of
		-- every landmark in the game is a flat white rectangle and never the stone underneath. The
		-- block builds hid most of it; a mesh on a base 1.3x wider turned it into a white floor tile
		-- with a monument standing in the middle of it.
		--
		-- A stepped base fixes it the way the idols' two shrinking slabs already do. The accent stays
		-- -- it is what lights the site -- but as a thin band SANDWICHED between the two steps, so
		-- only its edge shows and it reads as a lit rim instead of as the ground.
		newPart({ Name = "LandmarkPlinth", Size = Vector3.new(sw + 18, 5, sd + 18), Position = Vector3.new(cx, 2.5, z), Color = darken(base, 0.5), Material = mat, Parent = model })
		newPart({ Name = "LandmarkPlinthTrim", Size = Vector3.new(sw + 21, 1.4, sd + 21), Position = Vector3.new(cx, 5.7, z), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		newPart({ Name = "LandmarkPlinthStep", Size = Vector3.new(sw, 4, sd), Position = Vector3.new(cx, 8.4, z), Color = darken(base, 0.28), Material = mat, Parent = model })
	else
		newPart({ Name = "LandmarkPlinth", Size = Vector3.new(96, 5, 62), Position = Vector3.new(cx, 2.5, z), Color = darken(base, 0.45), Material = mat, Parent = model })
		newPart({ Name = "LandmarkPlinthTrim", Size = Vector3.new(104, 1.8, 70), Position = Vector3.new(cx, 5.4, z), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	end

	local style = cfg.style
	if figure then
		figure.Parent = model
		-- Half turned: the generator authors facing -Z, and this monument stands at the -Z end of
		-- the platform looking back up the street at the gate you arrive through.
		-- 10.4 is the top of the upper STEP (8.4 centre + 2 half), which is the surface a monument
		-- stands on. Not the plinth top at 5 and not the trim at 6.4 -- both of those are underneath
		-- the step and would bury the figure's feet in it.
		seatModel(figure, cx, z, math.pi)
		figure:PivotTo(figure:GetPivot() + Vector3.new(0, 10.4, 0))
	elseif style == "greattree" then
		newPart({ Name = "GreatTrunk", Size = Vector3.new(20, 76, 20), Position = Vector3.new(cx, 43, z), Color = cfg.trunkColor or Color3.fromRGB(92, 64, 40), Material = Enum.Material.Wood, Parent = model })
		for i = 1, 3 do
			newPart({ Name = "GreatRoot", Size = Vector3.new(8, 13, 28), Orientation = Vector3.new(0, i * 57, 0), Position = Vector3.new(cx + math.random(-12, 12), 9, z + math.random(-10, 10)), Color = cfg.trunkColor or Color3.fromRGB(92, 64, 40), Material = Enum.Material.Wood, Parent = model })
		end
		for i = 1, 6 do
			local s = math.random(36, 58)
			-- solid like the trunk it grows out of (11.22). NOTE: every zone now has a filed
			-- Landmark_<key> mesh, so this whole block-built branch is unreachable in the shipped world
			-- -- measured, 0 GreatCanopy parts across all 20 zones. Kept correct rather than kept true.
			newPart({ Name = "GreatCanopy", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 0.82, s), Position = Vector3.new(cx + math.random(-24, 24), 80 + math.random(-10, 16), z + math.random(-16, 16)), Color = i % 2 == 0 and base or darken(base, 0.22), Material = Enum.Material.Grass, Parent = model })
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
		-- solid like the SpireBlock stack under it (11.22); unreachable today for the reason noted on
		-- GreatCanopy above
		local tip = newPart({ Name = "SpireTip", Size = Vector3.new(12, 24, 12), Orientation = Vector3.new(0, 45, 0), Position = Vector3.new(cx, y + 12, z), Color = accent, Material = Enum.Material.Neon, Parent = model })
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
		-- the three rings are concentric and were all planted at the same y, which is the same
		-- coplanar-disc problem the arena floor had -- a 100-stud shimmering plate 82 studs up
		for i = 1, 3 do
			local s = 52 + i * 24
			local r = newPart({ Name = "LandmarkRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, s, s), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(cx, 80 + i * 0.02, z), Color = i == 2 and lighten(accent, 0.3) or accent, Material = Enum.Material.Neon, Transparency = 0.1 + i * 0.15, CanCollide = false, Parent = model })
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
		newPart({ Name = "LandmarkPost", Size = Vector3.new(3.5, 42, 3.5), Position = Vector3.new(cx + side * postX, 21, z + postZ), Color = darken(base, 0.55), Material = Enum.Material.Metal, CanCollide = false, Parent = model })
		local flame = newPart({ Name = "LandmarkFlame", Shape = Enum.PartType.Ball, Size = Vector3.new(8, 8, 8), Position = Vector3.new(cx + side * postX, 45, z + postZ), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(flame, accent, 28, 2)
	end
end

-- ===== IDOLS AND RUINS =====
-- The Desert's carved cat was the only figure standing anywhere in twenty zones, and it is the
-- single thing players point at. These two passes give every zone the same kind of company:
-- a couple of chunky animal idols and a cluster of broken pillars.
--
-- CARVED STONE, NOT BIOME COLOUR. Every other decoration layer is tinted from the zone palette,
-- which is right for ground litter (it should belong to the floor) and wrong for a monument -- a
-- green statue on green grass is a lump. These are pale stone everywhere, and the ONLY thing that
-- changes between zones is the painted accent and the glow in the eyes, so a Volcano idol and a
-- Nebula idol read as the same civilisation carving the same figures in different places.
local IDOL_STONE = Color3.fromRGB(228, 218, 198)
local IDOL_STONE_DARK = Color3.fromRGB(178, 168, 150)
local IDOL_SHADE = Color3.fromRGB(112, 105, 94)

-- Three silhouettes, cycled, so twenty zones are not twenty copies of one figure. Proportion does
-- the work rather than part count: a big head on a small body reads as a carved animal at 60 studs
-- and at 600, which is the whole trick the creature rigs use.
-- SIX NOW, NOT THREE, and each zone cycles a different three of them -- see addIdols. The last
-- three have no primitive builder of their own and fall through to "horned"; that only ever
-- happens if their mesh is missing, which is the same graceful-degradation rule the landmarks and
-- the boss rigs follow.
local IDOL_KINDS = { "cat", "owl", "horned", "guardian", "serpent", "totem" }

-- `u` is the HEAD DIAMETER, not the total height -- the head is the thing the eye measures a
-- carved animal by, and hanging every other number off it is what keeps the figure recognisable
-- when the same code is asked for a 60-stud one and a 160-stud one. Total height lands at ~2.4u.
local function buildIdol(model, cx, x, z, u, accent, kind)
	-- Built from a base CFrame rather than raw Positions so the whole figure can be turned. Local
	-- -Z is its face (the same convention the boss rigs use), and it is aimed INWARD -- at the centre
	-- square, which is the ground players actually stand on (Pet Shop, creature spawns, the walk
	-- between the two gates). A statue facing the boundary wall is scenery, not a landmark.
	--
	-- It used to aim at (x, ARRIVAL_Z) -- its OWN x, so straight down the Z axis -- and then turn a
	-- further 24-52 degrees AWAY from the street. Both halves were wrong. The turn was signed by
	-- `x >= 0`, i.e. WORLD x, and every zone but Forest sits at cx 1900, 3800, ... where that is
	-- true for every idol in the zone -- so they all leaned the same way. And outward was the wrong
	-- way to lean at all: a figure already parallel to the street, standing off to one side of a
	-- 1250-wide platform and then rotated further out, has nothing in front of it but wall.
	--
	-- Aiming at a jittered POINT rather than rotating off a fixed heading keeps the variety and
	-- cannot reintroduce the bug: the spread (+/-STREET_HALF across, +/-140 along) still gives every
	-- idol its own three-quarter angle and stops the dead-on stare that made them read as clones,
	-- but because the target is a PLACE, the gaze lands on the square wherever scatterPoint put the
	-- figure -- near side, far side, corner. No sign to get wrong.
	local here = Vector3.new(x, 0, z)
	local facing = Vector3.new(cx + math.random(-STREET_HALF, STREET_HALF), 0, math.random(-140, 140))
	if (facing - here).Magnitude < 1 then
		facing = here + Vector3.new(0, 0, 1)
	end
	local base = CFrame.new(here, facing)

	-- ===== THE STATUES ARE GENERATED MESHES NOW =====
	--
	-- Same argument that moved the bosses, the creatures, the landmarks and all 200 player skins off
	-- primitives: a figure assembled from spheres reads as a snowman however carefully its
	-- proportions are chosen, because a sphere carries no silhouette of its own and silhouette is
	-- the only thing legible at the range these are seen from. ServerStorage.IdolMeshes holds one
	-- generated model per kind (CAT, OWL, HORNED, GUARDIAN, SERPENT, TOTEM), each already sitting on
	-- a carved plinth of its own.
	--
	-- A kind with no mesh filed falls straight through to the block build below, unchanged -- so any
	-- subset can be filed and the world is never broken in between.
	local idolLib = ServerStorage:FindFirstChild("IdolMeshes")
	local idolTemplate = idolLib and idolLib:FindFirstChild("IdolMesh_" .. string.upper(kind))
	if idolTemplate then
		local figure = idolTemplate:Clone()
		local _, raw = figure:GetBoundingBox()
		-- MATCHED TO THE BLOCK BUILD'S HEIGHT, NOT TO `u`. `u` is a head diameter and the primitive
		-- figure lands at ~2.4u overall; scaling a mesh to `u` would leave a meshed zone's monuments
		-- less than half the size of the ones standing in the zone next door while the rollout is
		-- partial. Capped on width so a wide silhouette (the horned idol is the widest of the six)
		-- cannot overhang the footprint addIdols reserved for it.
		figure:ScaleTo(math.min((u * 2.4) / math.max(raw.Y, 1), (u * 1.9) / math.max(raw.X, raw.Z, 1)))
		for _, d in ipairs(figure:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				-- solid: these stand on ground players walk over, and the block build was collidable
				d.CanCollide = true
				-- PALE STONE IN EVERY BIOME, deliberately. A statue tinted to its zone is a green lump
				-- on green grass -- the same finding that made the block idols pale in the first place.
				d.Color = IDOL_STONE
				d.Material = Enum.Material.Sandstone
			end
		end
		figure.Name = "IdolFigure"
		figure.Parent = model
		local _, fit = figure:GetBoundingBox()

		-- A GROUND PAD UNDER IT. The mesh carries its own carved plinth, but a monument this size
		-- standing straight on grass has no contact shadow and reads as pasted onto the photograph.
		-- Two shrinking steps, exactly like the block build's, with the accent as a thin band
		-- SANDWICHED between them: a full-bright slab laid flat on the ground stops being a rim light
		-- and becomes the floor, which is the mistake the landmark plinth had to be rescued from.
		-- Deep enough to be a plinth. At 3.4 + 2.6 the two steps together were six studs under a
		-- 160-stud figure, which from anywhere but directly alongside is a grey rug, not a base.
		local padW = math.max(fit.X, fit.Z) * 1.24
		newPart({ Name = "IdolPad", Size = Vector3.new(padW, 7, padW),
			CFrame = base * CFrame.new(0, 3.5, 0), Color = IDOL_SHADE,
			Material = Enum.Material.Slate, Parent = model })
		newPart({ Name = "IdolPadTrim", Size = Vector3.new(padW * 0.95, 1.6, padW * 0.95),
			CFrame = base * CFrame.new(0, 7.8, 0), Color = accent, Material = Enum.Material.Neon,
			CanCollide = false, Parent = model })
		newPart({ Name = "IdolPadStep", Size = Vector3.new(padW * 0.86, 6, padW * 0.86),
			CFrame = base * CFrame.new(0, 11.6, 0), Color = IDOL_STONE_DARK,
			Material = Enum.Material.Slate, Parent = model })
		-- stood on top of the steps, facing the same way the block build faces (local -Z)
		figure:PivotTo(base * CFrame.new(0, 14.4 + fit.Y / 2, 0))

		-- Two braziers at the front corners. The block idol got its point of focus from lit eyes; a
		-- generated mesh has no lit anything, so without these the statue goes dark at night and the
		-- zone loses the landmark it is navigated by.
		-- SMALL. At u * 0.28 the bowl is a 22-stud ball of full-bright Neon standing at the statue's
		-- feet -- from the street it is a white blob with a monument behind it, which is the wrong way
		-- round. A brazier is a detail that says the site is tended; the statue is the thing being
		-- looked at. The light does the work, not the size of the bulb.
		for _, sx in ipairs({ -1, 1 }) do
			newPart({ Name = "IdolBrazierPost", Size = Vector3.new(u * 0.11, u * 0.4, u * 0.11),
				CFrame = base * CFrame.new(sx * padW * 0.46, u * 0.2, -padW * 0.4),
				Color = IDOL_STONE_DARK, Material = Enum.Material.Slate, CanCollide = false, Parent = model })
			-- UNIFORM on all three axes: a Shape = Ball part is drawn as a sphere of its SMALLEST
			-- axis and silently throws the other two away -- see the note below, which is what that
			-- bug did to this whole figure once already.
			local bowl = newPart({ Name = "IdolBrazier", Shape = Enum.PartType.Ball,
				Size = Vector3.new(u * 0.15, u * 0.15, u * 0.15),
				CFrame = base * CFrame.new(sx * padW * 0.46, u * 0.44, -padW * 0.4),
				Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
			addLight(bowl, accent, u * 1.4, 1.8)
		end
		return
	end

	-- A Part with Shape = Ball RENDERS A SPHERE OF ITS SMALLEST AXIS -- it discards a non-uniform
	-- Size without a word, and every proportion in this figure was authored as an ellipsoid. All of
	-- them were being thrown away: the 0.5u muzzle came out as a 0.38u pellet buried in the skull,
	-- the 1.16u mane as a 0.56u ball hidden inside the head, the 0.4u paws as 0.16u stubs. What was
	-- left standing on the plinth was a big ball on a smaller ball -- the exact snowman the comments
	-- below say was designed out. And the ears, tufts and wings are Blocks, so THEY kept their full
	-- size, which is why they read as pale slabs floating around a head too small to reach them.
	-- A Block wearing a SpecialMesh of MeshType Sphere scales on all three axes, so Shape = Ball is
	-- translated here and every number below means what it says again.
	local function piece(name, opts)
		opts.Name = name
		opts.Parent = model
		opts.CFrame = base * opts.CFrame
		if opts.Color == nil then opts.Color = IDOL_STONE end
		if opts.Material == nil then opts.Material = Enum.Material.Sandstone end
		local ball = opts.Shape == Enum.PartType.Ball
		if ball then opts.Shape = nil end
		local p = newPart(opts)
		if ball then
			local m = Instance.new("SpecialMesh")
			m.MeshType = Enum.MeshType.Sphere
			m.Parent = p
		end
		return p
	end

	-- plinth: two shrinking slabs, so the figure reads as placed rather than dropped
	piece("IdolPlinth", { Size = Vector3.new(u * 1.7, u * 0.16, u * 1.7), CFrame = CFrame.new(0, u * 0.08, 0), Color = IDOL_SHADE, Material = Enum.Material.Slate })
	piece("IdolPlinthStep", { Size = Vector3.new(u * 1.36, u * 0.14, u * 1.36), CFrame = CFrame.new(0, u * 0.23, 0), Color = IDOL_STONE_DARK, Material = Enum.Material.Slate })
	local floor = u * 0.3

	-- SEATED, AND SMALLER THAN THE HEAD. The first pass gave body and head almost the same
	-- diameter and the result was a snowman -- three stacked spheres read as a snowman at any size.
	-- The reference carving is a big head on a small crouched body, so the body is 0.72u against
	-- the head's 1.0u and it is half-buried under it.
	piece("IdolBody", { Shape = Enum.PartType.Ball, Size = Vector3.new(u * 0.78, u * 0.66, u * 0.72), CFrame = CFrame.new(0, floor + u * 0.3, 0) })
	for _, side in ipairs({ -1, 1 }) do
		piece("IdolPaw", { Shape = Enum.PartType.Ball, Size = Vector3.new(u * 0.24, u * 0.16, u * 0.4),
			CFrame = CFrame.new(side * u * 0.26, floor + u * 0.08, -u * 0.3), Color = IDOL_STONE_DARK })
	end

	local headY = floor + u * 0.86
	piece("IdolHead", { Shape = Enum.PartType.Ball, Size = Vector3.new(u, u * 0.95, u * 0.92), CFrame = CFrame.new(0, headY, 0) })
	-- The face has to carry at this size or the head is just a boulder: a muzzle that actually
	-- protrudes, a dark nose on the end of it, and a mouth line under that.
	piece("IdolMuzzle", { Shape = Enum.PartType.Ball, Size = Vector3.new(u * 0.5, u * 0.38, u * 0.4),
		CFrame = CFrame.new(0, headY - u * 0.19, -u * 0.42), Color = IDOL_STONE })
	piece("IdolNose", { Shape = Enum.PartType.Ball, Size = Vector3.new(u * 0.16, u * 0.13, u * 0.12),
		CFrame = CFrame.new(0, headY - u * 0.13, -u * 0.58), Color = IDOL_SHADE, CanCollide = false })
	piece("IdolMouth", { Size = Vector3.new(u * 0.04, u * 0.11, u * 0.05),
		CFrame = CFrame.new(0, headY - u * 0.27, -u * 0.56), Color = IDOL_SHADE, CanCollide = false })

	-- eyes: the only lit parts, so the figure keeps a point of focus at range
	for _, side in ipairs({ -1, 1 }) do
		local eye = piece("IdolEye", { Shape = Enum.PartType.Ball, Size = Vector3.new(u * 0.17, u * 0.17, u * 0.12),
			CFrame = CFrame.new(side * u * 0.23, headY + u * 0.08, -u * 0.42),
			Color = accent, Material = Enum.Material.Neon, CanCollide = false })
		if side == 1 then
			addLight(eye, accent, u * 1.2, 1.6)
		end
	end

	-- painted markings: on the FOREHEAD and across the brow, which is where the carving this is
	-- modelled on wears them. The first pass stood the stripe on top of the skull like an aerial.
	piece("IdolMark", { Size = Vector3.new(u * 0.09, u * 0.26, u * 0.06),
		CFrame = CFrame.new(0, headY + u * 0.3, -u * 0.36), Color = accent, Material = Enum.Material.SmoothPlastic, CanCollide = false })
	for _, side in ipairs({ -1, 1 }) do
		piece("IdolStripe", { Size = Vector3.new(u * 0.07, u * 0.19, u * 0.06),
			CFrame = CFrame.new(side * u * 0.15, headY + u * 0.32, -u * 0.32) * CFrame.Angles(0, 0, math.rad(side * 22)),
			Color = accent, Material = Enum.Material.SmoothPlastic, CanCollide = false })
	end
	piece("IdolCollar", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(u * 0.09, u * 0.62, u * 0.62),
		CFrame = CFrame.new(0, floor + u * 0.52, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = accent, Material = Enum.Material.SmoothPlastic, CanCollide = false })

	if kind == "cat" then
		-- Ears are a TAPERED STACK, not a Wedge. A Roblox wedge slopes along its own +Z and lands
		-- somewhere unintended the moment the part is also yawed -- which is what turned the first
		-- pass's ears into flat slabs lying away from the skull. Two blocks and a ball are dumb,
		-- predictable, and read as a pointed ear from every angle.
		-- Sunk into the skull and barely splayed. At 13 degrees they swung apart like a rabbit's and
		-- their lower corners lifted off the sphere, which is what read as two slabs floating over
		-- the head; 6 is enough to stop them looking like a pair of chimneys.
		for _, side in ipairs({ -1, 1 }) do
			local root = CFrame.new(side * u * 0.24, headY + u * 0.3, 0) * CFrame.Angles(0, 0, math.rad(side * -6))
			piece("IdolEar", { Size = Vector3.new(u * 0.28, u * 0.34, u * 0.22), CFrame = root })
			piece("IdolEarTip", { Size = Vector3.new(u * 0.17, u * 0.26, u * 0.15), CFrame = root * CFrame.new(0, u * 0.26, 0) })
			piece("IdolEarInner", { Size = Vector3.new(u * 0.14, u * 0.26, u * 0.05),
				CFrame = root * CFrame.new(0, u * 0.06, -u * 0.1), Color = accent, Material = Enum.Material.SmoothPlastic, CanCollide = false })
		end
		piece("IdolTail", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(u * 0.62, u * 0.13, u * 0.13),
			CFrame = CFrame.new(u * 0.4, floor + u * 0.2, u * 0.28) * CFrame.Angles(0, math.rad(28), math.rad(68)), Color = IDOL_STONE_DARK })
	elseif kind == "owl" then
		for _, side in ipairs({ -1, 1 }) do
			piece("IdolBrow", { Size = Vector3.new(u * 0.34, u * 0.09, u * 0.1),
				CFrame = CFrame.new(side * u * 0.22, headY + u * 0.24, -u * 0.38) * CFrame.Angles(0, 0, math.rad(side * 15)), Color = IDOL_STONE_DARK })
			piece("IdolTuft", { Size = Vector3.new(u * 0.16, u * 0.3, u * 0.14),
				CFrame = CFrame.new(side * u * 0.34, headY + u * 0.5, 0) * CFrame.Angles(0, 0, math.rad(side * -26)) })
			piece("IdolWing", { Size = Vector3.new(u * 0.13, u * 0.56, u * 0.34),
				CFrame = CFrame.new(side * u * 0.42, floor + u * 0.34, u * 0.02) * CFrame.Angles(0, 0, math.rad(side * 10)) })
		end
		piece("IdolBeak", { Size = Vector3.new(u * 0.14, u * 0.2, u * 0.16),
			CFrame = CFrame.new(0, headY - u * 0.16, -u * 0.46) * CFrame.Angles(math.rad(20), 0, 0), Color = accent, Material = Enum.Material.SmoothPlastic })
	else -- "horned"
		for _, side in ipairs({ -1, 1 }) do
			piece("IdolHorn", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(u * 0.46, u * 0.16, u * 0.16),
				CFrame = CFrame.new(side * u * 0.36, headY + u * 0.34, u * 0.04) * CFrame.Angles(0, 0, math.rad(side * -58)), Color = IDOL_STONE_DARK })
			-- carries on from the horn instead of hanging off it -- as a glowing ball at the end of a
			-- gap it read as an orb floating beside the head
			piece("IdolHornTip", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(u * 0.2, u * 0.12, u * 0.12),
				CFrame = CFrame.new(side * u * 0.53, headY + u * 0.5, u * 0.04) * CFrame.Angles(0, 0, math.rad(side * -58)),
				Color = accent, Material = Enum.Material.Neon, CanCollide = false })
			piece("IdolTusk", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(u * 0.22, u * 0.08, u * 0.08),
				CFrame = CFrame.new(side * u * 0.13, headY - u * 0.3, -u * 0.36) * CFrame.Angles(0, 0, math.rad(side * 66)), Color = IDOL_STONE })
		end
		piece("IdolMane", { Shape = Enum.PartType.Ball, Size = Vector3.new(u * 1.16, u * 0.56, u * 0.8),
			CFrame = CFrame.new(0, headY - u * 0.34, u * 0.06), Color = IDOL_STONE_DARK })
	end
end

-- A few of them per zone, well apart. scatterPoint already keeps every reservation on the platform
-- -- the street, both gate mouths, the boss arena and the centre square -- so placement is one call.
local function addIdols(model, cx, cfg)
	local count = cfg.count or 3
	for i = 1, count do
		-- `u` is the head diameter and the finished figure measures ~1.9u, so this puts them at
		-- 133..167 studs -- roughly DOUBLE what they were, and taller than the boss standing in the
		-- same zone. At 57..72 they read as garden ornaments: big next to a player, but a player is
		-- the smallest thing on the platform and everything else out there (the 140-stud walls, the
		-- Guardian Titan, a 75-120 stud boss) dwarfed them, so they registered as clutter rather than
		-- as monuments. The Titan is still the thing you navigate by -- it is several times this.
		--
		-- The plinth is 1.7u, so the footprint goes to ~120-150 studs. That fits: scatterPoint keeps
		-- them off the street, both gate mouths, the boss arena and the centre square, and the scatter
		-- band itself is only 350 studs out of a 625-stud half-platform.
		local u = math.random(70, 88)
		-- The size is picked BEFORE the position because the position depends on it. The plinth is
		-- 1.7u across, so half of it is 0.85u, and the tail/wings/horns reach a little past that --
		-- 0.95u is the honest footprint. Handing it to scatterPoint is what keeps a statue this big
		-- out of the walkway: the reservations are checked against the returned point, so before this
		-- an idol could sit legally at |x| = STREET_HALF and still lay 27 studs of stone across the
		-- middle of the street.
		-- 1.15u, not 0.95u. The plinth is 1.7u across, so its half-width is 0.85u and 0.95 looks like
		-- it clears -- but scatterPoint tests the returned POINT, and the props that land at exactly
		-- that radius have bodies of their own: a crate stack is up to 11 studs across with 3 more of
		-- jitter, which is about 0.1u at these sizes. It overhung by precisely that margin, which is
		-- why 369 props were still ending up inside plinths after the ordering fix.
		--
		-- 1.25u, NOT 1.15u -- THE RESERVATION IS A CIRCLE AND THE PLINTH IS A SQUARE. Every
		-- reservation in this file is a radius, but the sweep at the end of the zone loop tests a
		-- RECTANGLE (`abs(d.X) < size.X / 2 and abs(d.Z) < size.Z / 2`). A circle of 0.85u inscribed
		-- in a square of half-width 0.85u leaves the four corners out to 0.85u * sqrt(2) = 1.202u
		-- unguarded, so anything sitting in a corner passes the placement test honestly and is then
		-- destroyed by the sweep. That is how two zones ended up with an arrival BOARD and no post
		-- underneath it -- the exact "this just hangs in the air" report the post exists to answer.
		-- 1.25u covers the half-diagonal and keeps the 0.1u prop-body margin the note above earned.
		local x, z = scatterPoint(cx, nil, nil, u * 1.25)
		-- claim the ground before the NEXT idol, before the ruins, and before the biome builder
		-- scatters its own trees and rocks -- buildBiomeBase runs first in all twenty of them
		reserveScatter(x, z, u * 1.25)
		-- WHICH THREE, AND NOT THE SAME THREE IN EVERY ZONE. Cycling the list from index 1 everywhere
		-- stood the identical figures in the identical order on all twenty platforms, which is a large
		-- part of why one zone looks like the next. Offsetting the cycle by the zone's own key gives
		-- each zone its own trio out of the six and costs nothing per zone to configure.
		local off = 0
		if ACTIVE_ZONE_KEY then
			for k = 1, #ACTIVE_ZONE_KEY do off = (off * 31 + string.byte(ACTIVE_ZONE_KEY, k)) % 997 end
		end
		buildIdol(model, cx, x, z, u, cfg.accent, IDOL_KINDS[((off + i - 1) % #IDOL_KINDS) + 1])
	end
end

-- Broken pillars. Cheap, reads as history, and being pale stone it works unchanged in all twenty
-- biomes -- which is the point: one pass, no per-zone authoring.
local function addRuins(model, cx, cfg)
	for _ = 1, (cfg.count or 2) do
		-- pillars ring the scatter point out to r = 44, plus their own 13-stud width
		-- same margin as the idols: the pillars ring out to r = 44 plus their own 13-stud width, and
		-- whatever lands against that circle brings its own body with it
		local ox, oz = scatterPoint(cx, nil, nil, 64)
		reserveScatter(ox, oz, 64)
		local pillars = math.random(3, 5)
		for i = 1, pillars do
			local a = (i / pillars) * math.pi * 2 + math.random() * 0.6
			local r = math.random(26, 44)
			local x, z = ox + math.cos(a) * r, oz + math.sin(a) * r
			-- every pillar snapped off at a different height is what makes it read as a ruin rather
			-- than as a colonnade
			local h = math.random(16, 52)
			newPart({ Name = "RuinPillar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, 13, 13),
				Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, h / 2, z),
				Color = i % 2 == 0 and IDOL_STONE or IDOL_STONE_DARK, Material = Enum.Material.Sandstone, Parent = model })
			newPart({ Name = "RuinPillarBase", Size = Vector3.new(18, 3, 18), Position = Vector3.new(x, 1.5, z),
				Color = IDOL_SHADE, Material = Enum.Material.Slate, Parent = model })
		end
		-- one toppled drum on the ground, and a lit rune slab in the middle of the circle
		newPart({ Name = "RuinFallen", Shape = Enum.PartType.Cylinder, Size = Vector3.new(34, 12, 12),
			Orientation = Vector3.new(0, math.random(0, 360), 0), Position = Vector3.new(ox + math.random(-18, 18), 6, oz + math.random(-18, 18)),
			Color = IDOL_STONE_DARK, Material = Enum.Material.Sandstone, Parent = model })
		local rune = newPart({ Name = "RuinRune", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 26, 26),
			Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(ox, 0.7, oz),
			Color = cfg.accent, Material = Enum.Material.Neon, Transparency = 0.15, CanCollide = false, CastShadow = false, Parent = model })
		addLight(rune, cfg.accent, 34, 2)
	end
end

-- ===== THE MESH PROP LAYER ==================================================================
-- The bosses, the creatures, the eggs and all 200 player characters are generated meshes. The MAP
-- was the last thing in the game still made of primitives -- a Ball for a bush, a Cylinder for a
-- log -- and standing a meshed boss on it is what made that impossible to miss. This is the same
-- pipeline pointed at the ground: ServerStorage.PropMeshes holds Prop_<ZoneKey>_<SLOT> models,
-- three slots per zone.
--
--   CANOPY   the tall silhouette piece -- tree, spire, column. What you see from the gate.
--   BOULDER  the mid mass at chest-to-head height that breaks up the floor.
--   FLORA    the small ground cluster that fills in between the other two.
--
-- OPT-OUT BY ABSENCE, and that is the whole reason this is safe to roll out one mesh at a time:
-- a zone with no model filed for a slot simply does not get that slot. The twenty primitive biome
-- builders below are untouched and still draw everything they always drew, so a missing mesh is a
-- slightly emptier zone and never a broken one. (ACTIVE_ZONE_KEY is declared at the top of the
-- file, where ACTIVE_FRAME stood before it became `ZoneKit`'s -- addLandmark needs it too and is
-- written far above this point.)

-- `count` is CLUMP CENTRES, not props: each centre grows 1..clump instances inside clumpR of it.
-- Scattering singles over 350 x 548 studs reads as evenly-spaced dots however many you place --
-- what reads as a landscape is empty ground with thickets in it, and clumping is most of the
-- difference for none of the part budget.
--
-- `height` is the target height in studs and `widthCap` the widest the thing may get. The scale is
-- the SMALLER of the two ratios: these models are generated to a rough bounding box and some come
-- out long rather than tall, so height-matching alone would blow a wide prop out sideways -- the
-- same mistake that once made a 6.5-stud creature 15.5 studs wide.
local PROP_SLOTS = {
	{ slot = "CANOPY",  count = 5, height = { 34, 62 }, widthCap = 46, spreadX = 300, spreadZ = 380, clump = 3, clumpR = 26, collide = true,  shadow = true,  sink = 0.8 },
	{ slot = "BOULDER", count = 5, height = { 11, 26 }, widthCap = 38, spreadX = 310, spreadZ = 390, clump = 2, clumpR = 20, collide = true,  shadow = true,  sink = 1.2 },
	{ slot = "FLORA",   count = 8, height = { 6,  13 }, widthCap = 18, spreadX = 320, spreadZ = 400, clump = 3, clumpR = 14, collide = false, shadow = false, sink = 0.4 },
	-- BUILT THINGS, not grown ones: a shrine, an obelisk, a wrecked hull, a forge hut. The three
	-- slots above are all nature, and a zone made only of trees and rocks reads as terrain rather
	-- than as somewhere anyone has ever been.
	--
	-- `clump = 1` IS THE POINT. Everything else here grows in thickets because that is what plants
	-- and rubble do; two shrines standing shoulder to shoulder reads as a mistake. One per point,
	-- two per zone, so each one is found rather than come across.
	--
	-- Sized to sit between the boulder (26 max) and the zone's hero landmark (118): tall enough to
	-- break the skyline from across the platform, short enough that it never competes with the
	-- monument. clumpR stays small but non-zero -- it is the jitter AND half of what scatterPoint is
	-- told to keep clear, and the other half is widthCap / 2.
	{ slot = "STRUCTURE", count = 2, height = { 26, 44 }, widthCap = 40, spreadX = 300, spreadZ = 380, clump = 1, clumpR = 8, collide = true, shadow = true, sink = 0.5 },
}

local function addMeshProps(model, cx)
	local folder = ServerStorage:FindFirstChild("PropMeshes")
	if not folder or not ACTIVE_ZONE_KEY then return end

	for _, spec in ipairs(PROP_SLOTS) do
		local template = folder:FindFirstChild("Prop_" .. ACTIVE_ZONE_KEY .. "_" .. spec.slot)
		if template then
			for _ = 1, spec.count do
				-- HOW FAR THIS CLUMP CAN REACH FROM ITS CENTRE, and it is BOTH terms. The wander of
				-- an outlier (clumpR) plus that outlier's own half-width (widthCap / 2) -- scatterPoint
				-- inflates every clearance and pulls the spread in by whatever it is told, and it can
				-- only be told the truth once. Declaring clumpR alone put a fern one stud inside the
				-- boss arena, a canopy four studs into the street and a boulder one stud past the
				-- cliff-foot pool rim: three near-misses out of 670, all of them the same arithmetic,
				-- and all of them silent -- which is exactly the failure the note beside scatterPoint
				-- describes. A prop that overhangs by a stud today is a prop that buries a boss when
				-- someone raises widthCap.
				local x, z = scatterPoint(cx, spec.spreadX, spec.spreadZ, spec.clumpR + spec.widthCap / 2)
				for k = 1, math.random(1, spec.clump) do
					local ox = k == 1 and 0 or math.random(-spec.clumpR, spec.clumpR)
					local oz = k == 1 and 0 or math.random(-spec.clumpR, spec.clumpR)
					local prop = template:Clone()
					-- measured at scale 1, before ScaleTo and before parenting: GetBoundingBox covers
					-- every descendant, so anything measured after it has been put somewhere is
					-- measuring its surroundings as well
					local _, raw = prop:GetBoundingBox()
					local targetH = spec.height[1] + math.random() * (spec.height[2] - spec.height[1])
					prop:ScaleTo(math.min(targetH / math.max(raw.Y, 0.1), spec.widthCap / math.max(raw.X, raw.Z, 0.1)))
					for _, d in ipairs(prop:GetDescendants()) do
						if d:IsA("BasePart") then
							-- generated meshes arrive UNANCHORED. newPart anchors everything it makes;
							-- nothing anchors what comes out of the generator, and an unanchored tree
							-- falls through the floor on the first physics step of the first server.
							d.Anchored = true
							d.CanCollide = spec.collide
							d.CastShadow = spec.shadow
						end
					end
					prop.Name = "Prop" .. spec.slot
					prop.Parent = model
					-- seatModel, not PivotTo: every model in the library was authored by the generator
					-- with its pivot wherever it landed, and guessing the drop off one child part is
					-- what once left the Forest trees hovering 8-15 studs over the grass.
					seatModel(prop, x + ox, z + oz, math.random() * math.pi * 2, spec.sink)
					local _, size = prop:GetBoundingBox()
					reserveScatter(x + ox, z + oz, math.max(size.X, size.Z) * 0.5 + 3)
				end
			end
		end
	end
end

-- Runs the shared GROUND + LANDMARK + ATMOSPHERE + LIGHTING passes for one zone, so each
-- biome builder below only has to add its own signature MID-layer props.
local function buildBiomeBase(model, cx, cfg)
	-- NO table.clear HERE, AND THAT IS THE POINT. It used to clear, and the note at the top of
	-- addGroundDetail says it was moved out for exactly this reason -- but the call itself was
	-- left behind, so the move never took effect. addGroundDetail runs first in the zone loop and
	-- clears the table there; the crates and the glint coins then register their ground; and this
	-- line threw all of it away again a moment before the idols, the ruins and the mesh props
	-- picked their spots. That is why 148 crate stacks still ended up inside idol plinths after
	-- the reservation pass that was supposed to have fixed it.

	-- THE VILLAGE IS ALREADY THERE, AND NOTHING KNEW IT.
	--
	-- `scatterBlocks` only ever held what the scatter itself had placed, so the fixed installations
	-- built by the village pass were invisible to it -- and an idol whose plinth is 150 studs across
	-- was landing on top of them. One zone had an entire potion shop inside a plinth: cauldron,
	-- stand, brew and all, sealed in solid stone.
	--
	-- These coordinates are the village's, copied from the calls that place them (the shop at
	-- cx - 150, 150; the well at cx + 150, -168) and reserved before anything is scattered.
	-- THE SHOP'S CIRCLE HAS TO GROW WITH THE SHOP. 78 was measured against a 30x20 stall; at
	-- SHOP_SCALE the runner alone reaches 71 studs from the base point and the crates reach 55 to
	-- either side, so a scattered mesh prop was landing with its body inside the awning -- which is
	-- exactly the failure this whole list exists to stop, back again at a bigger size. Derived from
	-- the scale rather than re-typed, so it cannot fall behind the geometry a second time.
	-- MOVED TO THE TOP OF addGroundDetail. Reserving here was too late by three passes: the
	-- crates, the fourteen banner poles and the glint coins are all placed inside addGroundDetail,
	-- which runs first in the zone loop and clears the table -- so they picked their ground with
	-- the village invisible to them and a 40-stud banner pole came down 11 studs from the middle
	-- of the Volcano kiosk. The list lives beside the clear now, which is the only place it can be
	-- and cover everything downstream; nothing clears the table again between there and here.
	-- THE ARRIVAL SIGN WAS MISSING FROM THIS LIST, and it is the one that showed. It is built at
	-- the TOP of the zone loop, seven steps before anything scatters, at the hardcoded (cx - 104,
	-- 310) -- so it never asked for ground and nothing ever knew it was there. In Forest a 46-stud
	-- mesh tree came down 2.4 studs from the post's axis and swallowed the board whole; Mars is the
	-- same at 7.1, AntimatterZone grazes it at 20.4.
	--
	-- It also fixes a second bug at the far end of the loop. The idol-plinth sweep destroys loose
	-- decoration that ends up inside a plinth, and in Singularity it ate the post and left the board
	-- hanging in the air with nothing underneath it -- exactly the "this just hangs there" report
	-- that made the sign a physical post in the first place. Reserved here, BEFORE addIdols, an
	-- idol can no longer choose that ground at all.
	--
	-- 22 covers the board's 32-stud span and its two battens at +/-15. It is the sign's own
	-- half-footprint; the clearance a tree needs on top of it is the tree's business, and the CANOPY
	-- slot already demands clumpR + widthCap / 2 = 49 from every entry in this table.

	-- IDOLS AND RUINS FIRST, BEFORE ANY SCATTER.
	--
	-- They used to run after the litter, the mounds and the landmark. Both of them reserve their
	-- ground -- but a reservation made after the fact protects nothing: the crates, flowers, glint
	-- coins, banner poles and well stones had already been placed, and the plinth was then laid over
	-- the top of them. 1,154 props across the twenty zones ended up sealed inside solid stone,
	-- rendering every frame for nobody. Placed first, their reservations are in the table before a
	-- single scattered prop asks for a point.
	--
	-- IDOLS AND RUINS ARE OPT-OUT, NOT OPT-IN. There are twenty biome builders and each already
	-- passes its own palette here; making these two an extra key in every one of those tables would
	-- have meant twenty edits to add the feature and twenty more to change it. The accent is taken
	-- from whatever the zone already declared -- its landmark's accent first, its glow posts second
	-- -- so each zone's statues light up in its own colour with no new configuration at all.
	local accent = (cfg.idols and cfg.idols.accent)
		or (cfg.landmark and cfg.landmark.accent)
		or (cfg.glow and cfg.glow.color)
		or Color3.fromRGB(255, 226, 150)
	-- THE LANDMARK RESERVES BEFORE THE IDOLS AND THE RUINS DO, not after them. It stands at a FIXED
	-- point -- addLandmark is handed a cx and a z and simply builds there -- so it has never had to
	-- ask for ground, and nothing else knew it was coming. Reserved below the idols first time
	-- round, and a ruin duly came down on top of the Forest shrine's dais: two of the three things
	-- in this function that place themselves before the scatter had already chosen by then.
	-- Whatever is immovable goes into the table first.
	--
	-- IT IS ALSO OPT-OUT NOW, LIKE THE IDOLS, and for the same reason that was worth changing: SIX
	-- of the twenty biome builders never declared a landmark, so a third of the game had no monument
	-- at the back of the platform at all. The block build needed a style, a palette, a material and
	-- a trunk colour before it could draw anything -- four decisions per zone that nobody had made.
	-- A filed Landmark_<ZoneKey> needs none of them: the mesh is the whole figure, and only the dais
	-- and the two braziers take colour, which fall back exactly the way the idols' accent does.
	local landmarkCfg = cfg.landmark
	if not landmarkCfg and ACTIVE_ZONE_KEY then
		local folder = ServerStorage:FindFirstChild("PropMeshes")
		if folder and folder:FindFirstChild("Landmark_" .. ACTIVE_ZONE_KEY) then
			landmarkCfg = { base = Color3.fromRGB(150, 146, 138), accent = accent }
		end
	end

	if landmarkCfg then
		-- 100, not 70. The dais is now cut to fit its own monument, so the number here has to cover
		-- the LARGEST it can come out at: a 96 x 95 figure gives a 134 x 133 plinth (half-diagonal
		-- 94) with its braziers standing out at 81. One reservation has to cover both builds, and an
		-- under-reserved monument is props growing out of its steps.
		reserveScatter(cx + (landmarkCfg.dx or -210), landmarkCfg.z or -480, 100)
	end

	if cfg.idols ~= false then
		addIdols(model, cx, { count = (cfg.idols and cfg.idols.count) or 3, accent = accent })
	end
	if cfg.ruins ~= false then
		addRuins(model, cx, { count = (cfg.ruins and cfg.ruins.count) or 2, accent = accent })
	end

	-- MESH PROPS BEFORE THE LITTER AND THE MOUNDS. They are the biggest scattered things in the
	-- zone and every one of them claims its ground, so they have to be in the reservation table
	-- before the small stuff starts asking for points -- the ordering lesson the idols taught.
	addMeshProps(model, cx)
	-- ...and the small ground cover AFTER them, for the same reason in reverse: it reserves nothing,
	-- so it must be the thing that gives way rather than the thing given way to.
	addGroundClutter(model, cx)

	if cfg.litter then
		addGroundLitter(model, cx, cfg.litter)
	end
	if cfg.mounds then
		addMounds(model, cx, cfg.mounds)
	end
	if landmarkCfg then
		addLandmark(model, cx, landmarkCfg)
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

	-- MID: the tree canopy itself, varied scale + rotation so it never reads as clones.
	-- 15 trees at 0.8-1.6x scattered over 450x550 studs read as a mown lawn with shrubs on it;
	-- the reference forests are dense and the trees are taller than the player by a lot.
	-- 34 trees at up to 3.4x was a wall: from the arrival pad you could not see the shop, the
	-- portal or the boss. 20 at up to 2.3x still reads as a forest and leaves sightlines.
	-- 18 IS THE TREE'S OWN HALF-WIDTH, and passing it is what stops this loop dropping a canopy on
	-- top of something. These clones neither declared their size nor claimed their ground -- a bare
	-- `scatterPoint(cx, 195, 245)` -- so every fixed installation was invisible to them and every
	-- later prop was free to land inside them. That is four crate stacks, a fallen log, a glint coin
	-- and a glow bulb sealed inside Forest trunks, and it is the same arithmetic the mesh props
	-- already got right. The template is 14 studs across at 1x and scales to 2.3x, so 16 is the
	-- worst case and 18 leaves a little air.
	for _ = 1, 20 do
		local x, z = scatterPoint(cx, 195, 245, 18)
		if forestTreeTemplate then
			local tree = forestTreeTemplate:Clone()
			local geom = tree:FindFirstChild("body") and tree.body:FindFirstChild("body_geom")
			local scale = 1.1 + math.random() * 1.2
			tree:ScaleTo(scale)
			-- the mesh ships near-white and gets its green from its texture, which under the new
			-- lighting washed the whole canopy out to a flat mint. Tinting per clone fixes that and
			-- kills the cloned-prop read at the same time.
			if geom then
				geom.Color = Color3.fromRGB(126, 176, 104):Lerp(Color3.fromRGB(66, 124, 70), math.random())
			end
			-- parented BEFORE seating: GetBoundingBox on a model that is not in the datamodel yet
			-- still works, but ScaleTo has to have settled first and parenting is the cheapest way
			-- to be sure of the order
			tree.Parent = model
			seatModel(tree, x, z, math.random() * math.pi * 2)
			-- ...and claim it, measured rather than guessed: the scale is rolled per clone above.
			local _, tsize = tree:GetBoundingBox()
			reserveScatter(x, z, math.max(tsize.X, tsize.Z) * 0.5 + 3)
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

decorationBuilders.Desert = function(model, zone, cx)
	-- dense field of AI-generated cacti, varied scale/rotation so it doesn't read as clones
	if desertCactusTemplate then
		for i = 1, 26 do
			-- scatterPoint, not raw random: it is the one thing that keeps props out of the plaza,
			-- the boss arena and both gate mouths. Cacti were growing on the portal steps.
			local x, z = scatterPoint(cx, 205, 255)
			local cactus = desertCactusTemplate:Clone()
			local geom = cactus:FindFirstChild("body") and cactus.body:FindFirstChild("body_geom")
			local scale = 0.6 + math.random() * 1.1
			cactus:ScaleTo(scale)
			-- same guess, same bug class as the Forest trees -- see seatModel
			seatModel(cactus, x, z, math.random() * math.pi * 2)
			cactus.Parent = model
		end
	else
		for i = 1, 10 do
			local x, z = scatterPoint(cx, 190, 230)
			newPart({ Name = "Cactus", Size = Vector3.new(4, 14, 4), Position = Vector3.new(x, 7, z), Color = Color3.fromRGB(60, 120, 70), Material = Enum.Material.Grass, Parent = model })
			newPart({ Name = "CactusArm", Size = Vector3.new(3, 6, 3), Position = Vector3.new(x + 3, 10, z), Color = Color3.fromRGB(60, 120, 70), Material = Enum.Material.Grass, Parent = model })
		end
	end

	-- scattered sandstone boulders for ground-level variety
	for i = 1, 12 do
		local x, z = scatterPoint(cx, 205, 255)
		local s = math.random(6, 16)
		newPart({ Name = "DesertRock", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 0.7, s), Position = Vector3.new(x, s * 0.35, z), Color = Color3.fromRGB(200, 170, 120), Material = Enum.Material.Sandstone, Parent = model })
	end

	-- low dune mounds break up the flat floor
	for i = 1, 6 do
		local x, z = scatterPoint(cx, 190, 240)
		local s = math.random(30, 55)
		newPart({ Name = "Dune", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 0.28, s), Position = Vector3.new(x, s * 0.05, z), Color = Color3.fromRGB(225, 195, 140), Material = Enum.Material.Sand, CanCollide = false, Parent = model })
	end

	-- big statue landmark so the zone doesn't feel empty from a distance
	if desertStatueTemplate then
		local statue = desertStatueTemplate:Clone()
		-- A landmark has to read from the far end of a 1568-stud zone. Authored, this one is 43 studs
		-- tall -- barely more than the player's own rig at a late stage -- so it sat in the sand as
		-- just another prop instead of the thing you steer by. 2.6x puts it at ~111.
		local STATUE_SCALE = 2.6
		statue:ScaleTo(STATUE_SCALE)
		local geom = statue:FindFirstChild("body") and statue.body:FindFirstChild("body_geom")
		local halfHeight = geom and geom.Size.Y / 2 or 27 * STATUE_SCALE
		-- off the centre line, for the same reason as addLandmark: the -Z gate is behind it.
		-- The yaw matters: the mesh is authored facing -Z, i.e. the boss end, so unrotated it stood
		-- with its back to everyone walking in. Half a turn and it watches the arrival plaza.
		statue:PivotTo(CFrame.new(cx - 128, halfHeight - 3, -210) * CFrame.Angles(0, math.pi, 0))
		statue.Parent = model
	end

	-- small clay pottery scattered around so there's always something nearby to look at
	for i = 1, 10 do
		local x, z = scatterPoint(cx, 200, 250)
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

	-- No full-platform glass sheets any more. There were two -- one at knee height, one at y = 26 --
	-- and between them every sightline in the zone went through blue glass with a lid over it: the
	-- shop, the eggs, the pets and the player all came out washed grey-blue, and standing in the
	-- middle of it read as swimming rather than as a reef. The seabed is sold by what stands on it
	-- instead, plus tide pools you can see the sand through and walk around.
	for _ = 1, 7 do
		local x, z = scatterPoint(cx, 190, 240)
		local s = math.random(34, 68)
		local aspect = 0.7 + math.random() * 0.5
		newPart({ Name = "TidePoolRim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, s + 9, s * aspect + 9), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 0.2, z), Color = Color3.fromRGB(228, 210, 170), Material = Enum.Material.Sand, CanCollide = false, Parent = model })
		local pool = newPart({ Name = "TidePool", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, s, s * aspect), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 0.45, z), Color = shallow, Material = Enum.Material.Glass, Transparency = 0.45, CanCollide = false, Parent = model })
		addLight(pool, lighten(shallow, 0.4), 18, 0.7)
	end

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
	--
	-- Stood 150 studs to port, cone and lava flows together: the mountain is 172 wide and the gate
	-- to the next zone now opens in the middle of the -Z wall, directly under where it used to sit.
	-- Its far skirt runs into the boundary cliffs at that offset, which is how a mountain should
	-- meet a canyon wall anyway.
	ZoneKit.setFrame(CFrame.new(-150, 0, 0))
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
	ZoneKit.setFrame(nil)

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
	--
	-- ===== IT WAS READING AS A LID OF WATER (2026-08-17) =====
	--
	-- Reported as "ovde neka voda ima gore na mirror zoni", and the capture is unambiguous: the whole
	-- frame is washed pale blue-white, the character included. At **Transparency 0.25** this is a
	-- 95%-opaque pane the size of the entire platform hanging 118 studs up, so any camera pitched even
	-- slightly upward -- which is most of them, because the player is looking at a body that is 13
	-- studs tall at the top stage -- fills with it. Reflectance 0.85 makes that worse rather than
	-- better: the sheet is not just solid, it is BRIGHT, so it blows out everything behind it.
	--
	-- 0.25 -> 0.78 and 118 -> 140. Both halves matter and they fix different things. The transparency
	-- is what stops it being a ceiling; the height is what stops it being a ceiling you can READ as
	-- one -- at 118 it sits close enough to the terraces to look attached to the world, and at 140 it
	-- is clearly sky. Still under the 180-stud boundary wall, so it does not poke out of the box.
	--
	-- REFLECTANCE IS UNTOUCHED at 0.85, because it is the entire feature. A transparent pane still
	-- reflects; what changes is that you now see the reflection INSTEAD OF the pane. That is what the
	-- line above always meant by "the inverted world overhead".
	newPart({ Name = "MirrorCeiling", Size = Vector3.new(PLATFORM_WIDTH - 30, 2, PLATFORM_DEPTH - 30), Position = Vector3.new(cx, 140, 0), Color = Color3.fromRGB(196, 204, 228), Material = Enum.Material.Glass, Reflectance = 0.85, Transparency = 0.78, CanCollide = false, Parent = model })

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
	-- Set to one side like every other landmark, so the gate in the -Z wall keeps its approach.
	ZoneKit.setFrame(CFrame.new(-130, 0, 0))
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
	ZoneKit.setFrame(nil)

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
		-- leave both doorways open: the ring crosses the centre line twice, once at the arrival pad
		-- and once on the walk out to the exit gate, and either way that is a 96-stud slab dropped
		-- in the middle of the street. Dropping both keeps the ring symmetrical, which is the point
		-- of building it in the first place.
		if math.abs(x - cx) >= 80 then
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

-- One name and one verb. Everything above is reached through `decorationBuilders[zone.key]`, which
-- is the single line in `ZoneBuilder.Build()` that reads this file at all -- see the header for why
-- the surface is this small and not eight `add*` verbs wide.
return {
	decorationBuilders = decorationBuilders,
	setZoneKey = setZoneKey,
}
