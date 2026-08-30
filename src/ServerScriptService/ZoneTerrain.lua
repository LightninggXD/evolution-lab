-- ZoneTerrain -- the valley walls. The ground a zone is built ON, as opposed to everything that
-- is later stood on top of it.
--
-- Every zone was a flat slab with props on it. What is built here is a VALLEY: flat floor down the
-- middle where you actually play, rising through stacked terraces to cliffs at both edges, with
-- the boundary wall behind them. `buildValleySide` does one side and is called twice.
--
-- WHERE THE LINE IS: this file makes ground. `BiomeDecor` dresses it, `ZoneBuilder` walls it and
-- puts the buildings on it. Nothing here is a prop, which is why this is the one section of the
-- world builder that needed nothing from the rest of it: no reservation table, no zone key, no
-- village palette. Its whole vocabulary is `ZoneKit`.
--
-- IT HOLDS THE BIGGEST FUNCTION IN THE GAME. `buildValleySide` is ~1,270 lines and
-- `docs/CODEMAP.md` is how to read it without opening the file; the tier arithmetic is documented
-- in the block above it, which is worth reading before changing any number in this file. Two rules
-- from it that are load-bearing and easy to undo:
--
--   * NO TIER MAY BE LOWER THAN A MAXED JUMP -- a fully upgraded player's apex is 21.6 studs, so a
--     shelf below that is a shelf players stand on and see the seams of;
--   * a tier's usable tread ends at the NEXT tier's edge, which is the line that stops props being
--     buried in the cliffs.
--
-- WHO MAY REQUIRE IT: `ZoneBuilder`, which calls `buildTerrain` once per zone -- and `crestY`,
-- which is the wall asking the terrain how high the terrace band stands where the two meet. That
-- second one used to be a forward declaration at the top of `ZoneBuilder`, because
-- `addRockRampart` is written far above the table it reads; across a require there is no such
-- line, and the note the declaration carried is not needed any more.
--
-- Where the rest of the world is built: `docs/CODEMAP.md`, `docs/SPLIT.md` §6.

local ServerStorage = game:GetService("ServerStorage")

local ZoneKit = require(script.Parent.ZoneKit)
-- 33.10. Every water surface this file builds is a still slab; `WaterFlow` is the one thing that
-- makes one move, and it is a separate module because the Beam-orientation rule it encodes is worth
-- more than the six calls that use it. See its header before touching a width or a speed.
local WaterFlow = require(script.Parent.WaterFlow)

local newPart, groundColorOf, vivid = ZoneKit.newPart, ZoneKit.groundColorOf, ZoneKit.vivid
local lighten, darken, addLight = ZoneKit.lighten, ZoneKit.darken, ZoneKit.addLight
local TERRAIN_INNER, TERRAIN_OUTER = ZoneKit.TERRAIN_INNER, ZoneKit.TERRAIN_OUTER
local TERRAIN_DEPTH = ZoneKit.TERRAIN_DEPTH

-- NOTHING ELSE IS REQUIRED, AND ONE THING THAT COULD HAVE BEEN IS HANDED IN INSTEAD. The terrace
-- treads want to be made of the same material as the zone floor, which is `GROUND_MATERIAL` in
-- `ZoneBuilder` -- a per-zone table that `ZoneKit`'s header explicitly declines to hold, because a
-- decision about one zone is not a rule every part obeys. It arrives as the fourth argument to
-- `buildTerrain` rather than moving house to suit this file.

-- ============================================================================
-- TERRAIN: the valley walls
-- ============================================================================
-- Every zone was a flat 1250 x 1150 slab with props standing on it. The reference this is built
-- against is a VALLEY -- flat grass down the middle where you actually play, rising through
-- terraced shelves and cliff faces at the sides, with water falling off them into a pool.
--
-- WHY THE MIDDLE STAYS FLAT. Every scattered prop in this file -- trees, rocks, idols, creature
-- spawns, the shops -- is placed at y = 0 and has no idea what the ground beneath it is doing.
-- Raising ground where those land would bury half of them and leave the other half in the air.
-- So DECO_SPREAD_X was pulled in to 400 and the terraces live in the outer band from TERRAIN_INNER
-- to the wall, which nothing else ever touches. The playable valley is unchanged; the horizon is
-- completely different.
--
-- All of it is part-built rather than Roblox Terrain: the world is a 36,000-stud strip with
-- streaming on, and voxel terrain neither streams the same way nor matches the chunky look the
-- rest of the game is cut from.
-- TERRAIN_INNER / TERRAIN_OUTER / TERRAIN_DEPTH are declared in `ZoneKit`, beside PLATFORM_WIDTH
-- -- see the note there. They left this section because `addRockRampart` needs them and it is
-- written 2,400 lines above this point.

-- Per-zone character. Anything absent falls back to the defaults in buildTerrain, so a new zone
-- costs nothing and the twenty here are genuinely different rather than recoloured copies of one
-- profile: tier counts, step heights, whether there is water at the foot, how rocky it is.
-- STEP HEIGHTS ARE ~1.7x WHAT THEY WERE. At 12-20 studs a step was shorter than the props standing
-- on it and the band read as three long ledges mown into a lawn rather than as a valley wall --
-- and a waterfall pouring down a 15-stud riser has no room to look like falling water. Totals now
-- run 66-128 studs against a 180-stud boundary wall, so the terraces climb most of the way up it
-- without ever poking over.
-- ===== NO TIER MAY BE LOWER THAN A MAXED JUMP (item 19, 2026-08-11) =====
--
-- `rise` is not just a look. A Roblox jump reaches `power^2 / (2 * 196.2)`, and GameConfig's
-- MaxJumpPower used to be 92, which put a fully upgraded player's apex at **21.6 studs** -- so every
-- shelf built at or under that was reachable by walking to the cliff and holding space, with the
-- staircase and the whole climb it gates reduced to decoration. Raised creatures are the only
-- Evolution Shard source in the game, so the climb is the price of the currency.
--
-- Five zones were at or under it (DreamDimension 20, Ocean 22, Wormhole 22, Galaxy 24, TimeRift 25)
-- and are now 26. **26 is the floor for any new zone**; if MaxJumpPower ever rises, this number has
-- to rise with it.
--
-- THE CAP CAME DOWN TO 60 ON 2026-08-17 (a 9.2-stud apex), so the margin is 16.8 studs rather than
-- 4.4 and nothing here needed to move. 26 STAYS ANYWAY: it is now the number that keeps the risers
-- taller than the props standing on them (see the step-height note above), and dropping it back to
-- 20 to match the smaller jump would undo that for a margin nobody can see.
local TERRAIN_PROFILE = {
	-- `trees` is the CHANCE (0..1) that a given terrace segment gets a conifer, not a count: the
	-- segments already vary in size and position, so a probability spreads them unevenly where a
	-- count would plant the same number on every shelf. Absent = no trees, which is the right
	-- answer for the moon, the void and everything abstract.
	Forest          = { tiers = 3, rise = 26, water = true,  falls = 2, rocks = 9, rockSize = { 14, 30 }, trees = 0.85 },
	-- an OASIS, not a river: the one dry-looking biome that still earns water, and the only reason
	-- the Desert terraces are not a bare sand shelf from end to end
	Desert          = { tiers = 2, rise = 36, water = true,  falls = 1, rocks = 14, rockSize = { 18, 38 } },
	Ocean           = { tiers = 3, rise = 26, water = true,  falls = 3, rocks = 6, rockSize = { 12, 26 }, trees = 0.4 },
	Volcano         = { tiers = 3, rise = 34, water = true,  falls = 2, rocks = 14, rockSize = { 16, 40 } },
	Moon            = { tiers = 2, rise = 30, water = false, falls = 0, rocks = 16, rockSize = { 20, 44 } },
	Mars            = { tiers = 3, rise = 32, water = false, falls = 0, rocks = 13, rockSize = { 18, 40 } },
	Galaxy          = { tiers = 4, rise = 26, water = true,  falls = 2, rocks = 7, rockSize = { 12, 28 }, trees = 0.3 },
	BlackHole       = { tiers = 2, rise = 46, water = false, falls = 0, rocks = 10, rockSize = { 22, 46 } },
	Multiverse      = { tiers = 4, rise = 26, water = true,  falls = 3, rocks = 8, rockSize = { 14, 30 }, trees = 0.35 },
	Nebula          = { tiers = 3, rise = 28, water = true,  falls = 2, rocks = 9, rockSize = { 14, 32 } },
	Wormhole        = { tiers = 4, rise = 26, water = false, falls = 0, rocks = 11, rockSize = { 16, 34 } },
	QuantumRealm    = { tiers = 3, rise = 30, water = true,  falls = 2, rocks = 8, rockSize = { 12, 30 } },
	TimeRift        = { tiers = 4, rise = 26, water = true,  falls = 3, rocks = 9, rockSize = { 14, 32 } },
	AntimatterZone  = { tiers = 2, rise = 44, water = false, falls = 0, rocks = 15, rockSize = { 20, 44 } },
	DreamDimension  = { tiers = 4, rise = 26, water = true,  falls = 3, rocks = 6, rockSize = { 10, 26 }, trees = 0.5 },
	MirrorUniverse  = { tiers = 3, rise = 30, water = true,  falls = 2, rocks = 8, rockSize = { 14, 32 } },
	VoidExpanse     = { tiers = 2, rise = 50, water = false, falls = 0, rocks = 12, rockSize = { 22, 48 } },
	CelestialThrone = { tiers = 4, rise = 27, water = true,  falls = 3, rocks = 7, rockSize = { 14, 30 }, trees = 0.3 },
	Singularity     = { tiers = 3, rise = 34, water = false, falls = 0, rocks = 13, rockSize = { 18, 40 } },
	AbsolutePlane   = { tiers = 4, rise = 32, water = true,  falls = 4, rocks = 10, rockSize = { 16, 36 } },
}

-- The fallback here is the one buildTerrain uses when a zone has no profile, and the two have to
-- agree: a wall that raised its rampart onto a crest the terrain never built would leave a course
-- of boulders hanging in the air.
local TERRAIN_FALLBACK = { tiers = 3, rise = 26, water = false, falls = 0, rocks = 9, rockSize = { 14, 32 } }
local function terrainCrestY(zoneKey)
	local p = TERRAIN_PROFILE[zoneKey] or TERRAIN_FALLBACK
	return p.rise * p.tiers
end

-- One side of one zone. `side` is -1 or 1; everything is mirrored, and the two sides are given
-- different random seeds by the caller so a zone is not symmetrical.
--
-- ===== WHY THE TIERS ARE STACKED THE WAY THEY ARE (READ BEFORE EDITING) =====
-- The first cut gave every tier a slab that ran from its own inner edge all the way out to the
-- platform rim AND stood on the ground -- so tier 2 physically contained the whole outer half of
-- tier 1, tier 3 contained both, and every pair of tiers shared an exactly coplanar outer face,
-- end face and underside. Coplanar faces ARE z-fighting: the depth buffer cannot separate two
-- surfaces at the same depth, so the renderer flickers between them as the camera moves. That is
-- the striped shimmer that covered the cliffs. The cliff face and the lip had the same defect
-- against their own tier -- both were placed flush with the slab's front face.
--
-- Nothing is stacked inside anything else now. Tier N is a slab exactly `rise` thick sitting ON
-- tier N-1 and reaching the rim, so consecutive tiers TOUCH but never overlap, and every
-- decorative piece bolted to a face is pushed a stud or two PROUD of it. Both rules are
-- load-bearing: undo either one and the shimmer comes straight back.
-- `groundMaterial` is `GROUND_MATERIAL[zone.key]`, handed in by `ZoneBuilder` because that
-- table is a per-zone decision and stays there. See the note at the top of this file.
local function buildValleySide(model, zone, cx, side, p, groundMaterial)
	-- LOOKED UP AGAIN HERE, and it has to be. `addRockRampart` declares a `cliffFace` of its own,
	-- but that is a local inside THAT function -- from here the name resolves to a nil global, the
	-- outcrop block below is skipped in silence and nothing is logged. Exactly the shape of the
	-- villMesh bug: it compiles, it runs, it does nothing.
	local cliffLib = ServerStorage:FindFirstChild("PropMeshes")
	local cliffFace = cliffLib and cliffLib:FindFirstChild("Cliff_" .. zone.key)
	-- the shared water set, same folder. Declared HERE and not at the cascade loop for the reason
	-- written above cliffFace: a local belonging to another function reads as a nil global from
	-- inside this one, silently.
	local waterLib = cliffLib

	local grass = groundColorOf(zone)
	-- The cliff is NOT the ground colour. Rock reads as rock because it is a different material and
	-- a different hue -- a cliff tinted from green grass is a green wall, which is what the first
	-- attempt at this looked like. It carries a quarter of the zone's tint so a Volcano cliff and a
	-- Moon cliff are still recognisably from their own worlds.
	local rock = Color3.fromRGB(150, 128, 104):Lerp(groundColorOf(zone), 0.25)
	local rockLit = lighten(rock, 0.16)
	local rockDark = darken(rock, 0.3)
	local moss = Color3.fromRGB(104, 164, 82):Lerp(groundColorOf(zone), 0.45)
	local accent = vivid(zone.accentColor)
	local ground = groundMaterial or Enum.Material.Grass
	local band = (TERRAIN_OUTER - TERRAIN_INNER) / p.tiers
	-- TERRAIN_DEPTH, not PLATFORM_DEPTH: the Z walls' sealing slabs are WALL_THICK thick centred on
	-- +/- PLATFORM_DEPTH/2, so a terrace cut to the full depth put its two end segments two studs
	-- inside a solid wall on both sides of every zone. (11.23)
	local halfZ = TERRAIN_DEPTH / 2

	-- the two numbers every piece below is placed from: where tier N's riser stands, and how high
	-- you are once you have walked up onto it
	local function riserX(tier) return TERRAIN_INNER + band * (tier - 1) end
	local function treadY(tier) return p.rise * tier end

	-- ---- A BOULDER, AS A PILE OF ROTATED SLABS. The reference art's rocks are big rounded-off
	-- CHUNKS with visible flat faces, not spheres -- a sphere is a marble however large you make it,
	-- and that is what the old single-ball rocks read as. Three or four blocks yawed to different
	-- angles and half-sunk into one another give facets that catch the light separately, which is
	-- what makes a lump of grey read as stone. The dark slab underneath is the contact shadow; it is
	-- the difference between a rock sitting on the ground and one hovering over it.
	local function boulder(x, y, z, s)
		newPart({ Name = "ValleyRockBase", Size = Vector3.new(s * 1.3, s * 0.16, s * 1.16),
			Orientation = Vector3.new(0, math.random(0, 360), 0),
			Position = Vector3.new(x, y + s * 0.05, z), Color = rockDark,
			Material = Enum.Material.Slate, CanCollide = false, CastShadow = false, Parent = model })

		-- the main mass: a wide slab with a tilt, so its top face is never level with the ground
		newPart({ Name = "ValleyRock", Size = Vector3.new(s * 1.04, s * 0.62, s * 0.94),
			CFrame = CFrame.new(x, y + s * 0.3, z)
				* CFrame.Angles(math.rad(math.random(-9, 9)), math.rad(math.random(0, 360)), math.rad(math.random(-9, 9))),
			Color = rock, Material = Enum.Material.Rock, Parent = model })

		-- a smaller block riding on top and off-centre -- this is the piece that turns a slab into a
		-- rock, because it breaks the silhouette's top edge.
		-- SOLID, LIKE THE MASS IT RIDES ON (11.22). This is the top third of the boulder's silhouette
		-- and it was the one third you fell through: a drop-ray onto all 410 of them landed on
		-- `ValleyRock` underneath, every time. A base you cannot walk into with a lid you can is worse
		-- than either choice made consistently.
		newPart({ Name = "ValleyRockCap", Size = Vector3.new(s * 0.72, s * 0.44, s * 0.66),
			CFrame = CFrame.new(x + s * 0.1, y + s * 0.66, z - s * 0.08)
				* CFrame.Angles(math.rad(math.random(-12, 12)), math.rad(math.random(0, 360)), math.rad(math.random(-12, 12))),
			Color = rockLit, Material = Enum.Material.Rock, Parent = model })

		-- two chips fallen off it, out on the ground
		for i = 1, 2 do
			local t = s * (i == 1 and 0.44 or 0.3)
			local a = math.random() * math.pi * 2
			newPart({ Name = "ValleyRockChip", Size = Vector3.new(t, t * 0.56, t * 0.84),
				CFrame = CFrame.new(x + math.cos(a) * s * 0.68, y + t * 0.26, z + math.sin(a) * s * 0.68)
					* CFrame.Angles(0, math.rad(math.random(0, 360)), math.rad(math.random(-22, 22))),
				Color = i == 1 and rock or rockDark, Material = Enum.Material.Rock, CanCollide = false, Parent = model })
		end
	end

	-- ---- three blades from one point. One blade is a spike sticking out of the ground; three at
	-- different heights and leans is a clump, and a clump is the smallest thing that reads as
	-- vegetation from the street.
	local function tuft(x, y, z, h, color, material)
		for i = 1, 3 do
			local bladeH = h * (i == 2 and 1 or math.random(58, 78) / 100)
			newPart({ Name = "TerraceTuft", Size = Vector3.new(2.4, bladeH, 2.4),
				CFrame = CFrame.new(x + (i - 2) * 2.6, y + bladeH * 0.46, z + math.random(-2, 2))
					* CFrame.Angles(0, math.rad(math.random(0, 180)), math.rad(math.random(-26, 26))),
				Color = color, Material = material, CanCollide = false, CastShadow = false, Parent = model })
		end
	end

	-- ---- A MUSHROOM: stem, cap, and pale spots on the cap. In the reference these are the single
	-- most repeated piece of decoration on the hillsides and they are what stops a green shelf
	-- reading as a mown lawn -- they are small, brightly coloured and there are a LOT of them, which
	-- is the opposite of how the rest of this file places props.
	local MUSHROOM_CAPS = {
		Color3.fromRGB(226, 74, 82), Color3.fromRGB(96, 176, 236),
		Color3.fromRGB(232, 158, 88), Color3.fromRGB(214, 106, 196),
	}
	local function mushroom(x, y, z, s)
		local cap = MUSHROOM_CAPS[math.random(1, #MUSHROOM_CAPS)]
		newPart({ Name = "TerraceShroomStem", Size = Vector3.new(s * 0.32, s * 0.8, s * 0.32),
			CFrame = CFrame.new(x, y + s * 0.4, z) * CFrame.Angles(0, 0, math.rad(math.random(-8, 8))),
			Color = Color3.fromRGB(244, 236, 214), Material = Enum.Material.SmoothPlastic,
			CanCollide = false, CastShadow = false, Parent = model })
		local head = newPart({ Name = "TerraceShroomCap", Shape = Enum.PartType.Ball,
			Size = Vector3.new(s * 1.1, s * 0.66, s * 1.1),
			Position = Vector3.new(x, y + s * 0.86, z),
			Color = cap, Material = Enum.Material.SmoothPlastic,
			CanCollide = false, CastShadow = false, Parent = model })
		-- two pale dots. Without them the cap is a coloured pebble; with them it is unmistakably a
		-- toadstool, and it costs two parts.
		for i = 1, 2 do
			local a = math.random() * math.pi * 2
			newPart({ Name = "TerraceShroomDot", Shape = Enum.PartType.Ball,
				Size = Vector3.new(s * 0.26, s * 0.26, s * 0.26),
				Position = Vector3.new(x + math.cos(a) * s * 0.34, y + s * 1.06, z + math.sin(a) * s * 0.34),
				Color = Color3.fromRGB(252, 248, 238), Material = Enum.Material.SmoothPlastic,
				CanCollide = false, CastShadow = false, Parent = model })
		end
		return head
	end

	-- ---- A CONIFER, as a stepped cone. Roblox has no cone primitive and a stack of spheres reads
	-- as a snowman, so this is three shrinking blocks yawed 30 degrees apart -- from any angle the
	-- staggered corners give a ragged conical silhouette, which is what the chunky style wants
	-- anyway. Only zones whose profile asks for trees get them: a pine on the Moon is worse than
	-- bare rock.
	local function conifer(x, y, z, h)
		-- THE ZONE'S OWN TREE, when one is filed. The stepped-block cone below was written when
		-- nothing in this game was a mesh; against the meshed canopies now standing on the valley
		-- floor thirty studs away it reads as a stack of dark green boxes on the skyline -- and the
		-- terraces are exactly where the eye goes, because they are the horizon from the street.
		--
		-- Prop_<zone>_CANOPY is the same tree the floor uses, so the slope and the flat agree.
		local treeLib = ServerStorage:FindFirstChild("PropMeshes")
		local treeMesh = treeLib and treeLib:FindFirstChild("Prop_" .. zone.key .. "_CANOPY")
		if treeMesh then
			local tree = treeMesh:Clone()
			local _, raw = tree:GetBoundingBox()
			-- built to the height the cone was asked for, capped on width: these stand on a shelf
			-- only `band` studs deep and a wide canopy would hang over the drop
			tree:ScaleTo(math.min(h / math.max(raw.Y, 0.1), (h * 0.7) / math.max(raw.X, raw.Z, 0.1)))
			for _, part in ipairs(tree:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Anchored = true
					-- scenery on a ledge the player cannot reach; colliding costs and buys nothing
					part.CanCollide = false
				end
			end
			tree.Name = "TerraceTree"
			tree.Parent = model
			-- PivotTo and not seatModel: seatModel drops to y = 0 and this one stands on a shelf at y.
			-- Measured after scaling so the trunk foot lands on the shelf rather than in it.
			local _, fit = tree:GetBoundingBox()
			tree:PivotTo(CFrame.new(x, y + fit.Y / 2, z) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
			return
		end

		local w = h * 0.46
		newPart({ Name = "TerraceTrunk", Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(h * 0.3, w * 0.22, w * 0.22), Orientation = Vector3.new(0, 0, 90),
			Position = Vector3.new(x, y + h * 0.14, z),
			Color = Color3.fromRGB(112, 76, 48), Material = Enum.Material.Wood,
			CanCollide = false, CastShadow = false, Parent = model })
		local needle = Color3.fromRGB(46, 116, 62):Lerp(groundColorOf(zone), 0.2)
		for i = 1, 3 do
			local f = (i - 1) / 3
			newPart({ Name = "TerraceCanopy", Size = Vector3.new(w * (1 - f * 0.42), h * 0.34, w * (1 - f * 0.42)),
				CFrame = CFrame.new(x, y + h * (0.3 + f * 0.28), z) * CFrame.Angles(0, math.rad(i * 30), 0),
				Color = i == 2 and lighten(needle, 0.1) or needle, Material = Enum.Material.Grass,
				CanCollide = false, CastShadow = false, Parent = model })
		end
	end

	-- ===== THE EDGE MEANDERS: ONE SLAB PER SEGMENT, NOT ONE PER TIER =====
	-- Cut as a single 1150-stud slab per tier, the three terraces were three exactly parallel lines
	-- running the whole depth of the zone -- "one right behind the other, like they are in a row",
	-- which is a staircase and not a hillside. The reference art has no straight edge anywhere: each
	-- shelf bulges and retreats, so from any angle you see a different amount of each one.
	--
	-- So each tier is cut into SEGMENTS along Z and every segment picks its own inner edge. The
	-- jitter is OUTWARD ONLY (`riserX(tier) + j`, j >= 0) and that is not a style choice: the pool
	-- and the valley floor's props are laid out against TERRAIN_INNER, so a segment allowed to creep
	-- inward would stand in the water.
	--
	-- Anything that has to meet the cliff later (the waterfalls) must ask `edgeAt(tier, z)` rather
	-- than `riserX(tier)`, or it hangs in mid-air over whichever segment happens to have pulled back.
	-- SEGMENT COUNT IS PER ZONE, NOT GLOBAL. Five everywhere meant every zone cut its hillside at
	-- the same five places, so the twenty banks were the same shape in twenty colours -- and the
	-- segment boundaries lined up across the whole 36,000-stud strip. Derived from the zone key so
	-- it is stable across rebuilds and needs no entry in TERRAIN_PROFILE.
	local keyHash = 0
	for i = 1, #zone.key do keyHash = (keyHash * 31 + string.byte(zone.key, i)) % 9973 end
	local SEGMENTS = 5 + (keyHash % 4)          -- 5..8
	local segLen = TERRAIN_DEPTH / SEGMENTS

	-- math.random errors outright on an empty interval, and several placements below derive BOTH
	-- ends from the jittered edge -- so on the outermost tier of a 4-tier profile the low end can
	-- overtake the high one. This is what took the whole build down on Wormhole. Collapsing to the
	-- low end is the right answer: it means "there is no room to scatter here, put it at the edge".
	local function span(lo, hi)
		lo, hi = math.floor(lo), math.floor(hi)
		if hi <= lo then return lo end
		return math.random(lo, hi)
	end

	-- ===== EVERY TIER MEANDERS, AND THE OUTER ONES DID NOT =====
	--
	-- The old rule jittered each tier OUTWARD from its own nominal line by up to 40% of a band, then
	-- capped that by `TERRAIN_OUTER - 70 - riserX(tier)` to protect the tread. Work the cap out on a
	-- real profile and it is zero: a 3-tier zone puts riserX(3) at 555, and 625 - 70 - 555 = 0. The
	-- OUTERMOST shelf -- the one on the skyline, the one you actually look at -- was therefore cut
	-- dead straight in all twenty zones, and the second one nearly so. That is the row of ruled
	-- parallel lines running the full depth of every map, and it is most of why the band reads as a
	-- staircase mown into a lawn instead of as a hillside.
	--
	-- Cut per SEGMENT instead of per tier. Walk outward from TERRAIN_INNER and let each riser take a
	-- random share of the room that is left, always reserving MIN_TREAD for itself and for every
	-- tier still to be placed. Three things fall out of that: every tier can bulge or retreat
	-- anywhere in the band, the treads are walkable BY CONSTRUCTION rather than by a cap that only
	-- happens to hold, and the choices compound outward so the top shelf is the most ragged rather
	-- than the straightest.
	--
	-- MIN_TREAD also varies per zone: it is what decides whether a zone reads as a few broad
	-- pastures or as many narrow ledges, and it costs nothing to make that a per-zone difference.
	local MIN_TREAD = 30 + (keyHash % 5) * 6      -- 30..54
	local edges = {}
	for tier = 1, p.tiers do edges[tier] = {} end
	for i = 1, SEGMENTS do
		local x = TERRAIN_INNER
		for tier = 1, p.tiers do
			-- the furthest out this riser may stand and still leave a tread for itself and for every
			-- tier above it
			local ceiling = TERRAIN_OUTER - MIN_TREAD * (p.tiers - tier + 1)
			-- Half the remaining room at most. Letting an inner tier take all of it pins every tier
			-- above it against its own ceiling, which is the straight line this exists to remove.
			local room = math.max(0, math.floor((math.max(x, ceiling) - x) * 0.5))
			edges[tier][i] = x + math.random(0, room)
			x = edges[tier][i] + MIN_TREAD
		end
	end
	local function edgeAt(tier, z)
		local i = math.clamp(math.floor((z + halfZ) / segLen) + 1, 1, SEGMENTS)
		return edges[tier][i]
	end
	local function segZ(i) return -halfZ + segLen * (i - 0.5) end

	-- ===== WHICH SEGMENT EACH FLIGHT OF STAIRS CLIMBS =====
	--
	-- Decided HERE, before a single prop is placed, and that ordering is the whole point: the crags,
	-- boulders and conifers below all have to know where the stairs are going to be. Built later
	-- (which is where this started) they were placed into rock -- a screenshot of the first pass
	-- showed a flight of steps and two rails driven straight through a crag, reading as a pile of
	-- slabs rather than as a way up.
	--
	-- SPREAD ACROSS THE RING, NOT STEPPED BY A CONSTANT. The first version picked `tier * 3 + hash`,
	-- and on a zone with six segments that is 3, 0, 3, 0 -- tiers 1 and 3 landed on the SAME segment
	-- and built two flights at two pitches through each other. Dividing the ring by the tier count
	-- cannot do that: with at most 4 tiers against at least 5 segments, every flight gets its own.
	local stairSeg = {}
	for tier = 1, p.tiers do
		stairSeg[tier] = (math.floor((tier - 1) * SEGMENTS / p.tiers) + keyHash + (side > 0 and 1 or 0)) % SEGMENTS + 1
	end
	-- Half the flight's 30-stud width plus a margin, measured from the middle of its segment.
	--
	-- TWO FLIGHTS TOUCH ANY GIVEN SHELF, and the first version of this only knew about one of them
	-- -- which is why a rebuild still came back with 22 crags, 13 buttresses and 9 boulders standing
	-- in a staircase. Tier N's flight STANDS ON tier N-1's tread and ARRIVES AT tier N's, so
	-- anything placed on tread T has to keep clear of flight T (which lands on it at the inner lip)
	-- and of flight T+1 (which runs right across it). `stairSeg[tier + 1]` is nil on the top shelf,
	-- where there is no flight above -- that is the loop's own terminator, not a special case.
	local STAIR_HALF_Z = 26
	local function inStairwell(tier, z)
		for _, t in ipairs({ tier, tier + 1 }) do
			local i = stairSeg[t]
			if i and math.abs(z - segZ(i)) < STAIR_HALF_Z then return true end
		end
		return false
	end

	-- ===== AND WHERE THE WATER COMES DOWN, FOR EXACTLY THE SAME REASON (11.24) =====
	--
	-- The stairs above are the only keep-out this slope had, and the note over `stairSeg` says why
	-- the ordering is the whole point. The falls were the same shape of problem with none of the
	-- answer: `fz` was picked ~600 lines below, inside `if p.water`, long after every crag, buttress,
	-- boulder, conifer, mushroom and tuft on the hillside had already chosen its spot -- and nothing
	-- tested it. A cascade is not a thin sheet either: `FallSpillway` is a cut across the lip,
	-- `FallHead` runs the full depth of the top tread and `FallBasin` runs the full depth of every
	-- tread below it, so the corridor is the whole shelf at that z, from the riser to the next edge.
	-- Measured before this existed: 2,007 props standing inside a fall corridor across the twenty
	-- zones -- 906 grass tufts, 249 pieces of cliff cladding, 176 buttresses and, in several zones,
	-- an entire flight of stairs with a waterfall running down it.
	--
	-- So the pool and the falls are laid out HERE, before the first prop, on the same pattern: the
	-- numbers are chosen, the corridors are published, and everything placed afterwards tests them.
	-- The pool builder below consumes these instead of rolling its own.
	local cascade = math.min(p.tiers, 3)
	local poolZ = math.random(-260, 260)
	local poolLen = math.random(220, 340)
	-- The widest thing in the corridor is `FallBasinRim` at `wide + 22` = 56 on the bottom step;
	-- half of that is 28, and 10 more absorbs the yaw every prop on the hillside is given -- a 52-stud
	-- slab turned 14 degrees is 58 wide along z, and measuring it as 52 is how 29 pieces of cladding
	-- came back still standing in the water after the first cut of this.
	local FALL_HALF_Z = 38
	local fallZ = {}
	if p.water then
		for i = 1, p.falls do
			local z = poolZ + (i - (p.falls + 1) / 2) * (poolLen / math.max(1, p.falls))
			-- ...and a fall may not land in a stairwell either. The flights were chosen first, so the
			-- water is what moves. Kept inside the pool it has to arrive in, so the bottom step still
			-- lands in water rather than on the grass beside it.
			-- TESTED ON THE CORRIDOR'S OWN WIDTH, not on `inStairwell`'s: a fall centred 30 studs from
			-- a flight passes a 26-stud test and still runs a 38-stud corridor across half of it.
			local lo, hi = poolZ - poolLen / 2 + 20, poolZ + poolLen / 2 - 20
			for _ = 1, 8 do
				local clash = false
				for tier = 1, cascade do
					for _, t in ipairs({ tier, tier + 1 }) do
						local si = stairSeg[t]
						if si and math.abs(z - segZ(si)) < STAIR_HALF_Z + FALL_HALF_Z then clash = true end
					end
				end
				if not clash then break end
				z = z + STAIR_HALF_Z + FALL_HALF_Z + 6
				if z > hi then z = lo end
			end
			fallZ[i] = z
		end
	end

	-- The one question everything on a shelf asks before it puts itself down: is this z spoken for?
	-- `ownHalf` is the prop's own half-width along z, so the test is on its BODY and not on its
	-- centre -- the same correction `halfSize` made to scatterPoint, and the reason a 52-stud crag
	-- that "cleared" a staircase by its middle still stood in it.
	local function claimedZ(tier, z, ownHalf)
		ownHalf = ownHalf or 0
		for _, t in ipairs({ tier, tier + 1 }) do
			local i = stairSeg[t]
			if i and math.abs(z - segZ(i)) < STAIR_HALF_Z + ownHalf then return true end
		end
		-- only the tiers a cascade actually reaches; there is no fall above `cascade`
		if tier <= cascade then
			for _, fz in ipairs(fallZ) do
				if math.abs(z - fz) < FALL_HALF_Z + ownHalf then return true end
			end
		end
		return false
	end

	-- A free z inside this segment, or nil if the corridors have eaten it. Nil means DO NOT BUILD:
	-- the shelves are planted densely and one missing mushroom is invisible, where a mushroom shoved
	-- to a spot chosen by arithmetic rather than by a test is how props ended up in the next segment.
	local function freeZ(tier, zc, lo, hi, ownHalf)
		for _ = 1, 12 do
			local z = zc + span(lo, hi)
			if not claimedZ(tier, z, ownHalf) then return z end
		end
		return nil
	end

	for tier = 1, p.tiers do
		local top = treadY(tier)

		for i = 1, SEGMENTS do
			local innerX = edges[tier][i]
			local width = TERRAIN_OUTER - innerX
			local zc = segZ(i)
			-- ===== WHERE THIS TIER'S TREAD ACTUALLY ENDS =====
			-- Tier N's slab reaches the rim, but so does tier N+1's, sitting exactly `rise` on top of it
			-- and starting at ITS OWN inner edge. So the part of tier N you can stand on -- and the only
			-- part anything may be placed on -- runs from `innerX` out to the NEXT tier's edge, not to
			-- TERRAIN_OUTER. Everything on this shelf used to scatter over the full width, which on a
			-- 3-tier profile buried roughly two thirds of tier 1's mushrooms, grass, boulders and crags
			-- INSIDE the two slabs above it -- props sunk halfway into a cliff with no way to reach them.
			-- That is the single largest source of "everything is inside everything else" out here.
			local treadOut = (tier < p.tiers) and edges[tier + 1][i] or TERRAIN_OUTER

			-- THE SHELF: exactly `rise` thick and standing on the tier below, never on the ground. See
			-- the z-fighting note above -- that is the other half of the shape.
			newPart({ Name = "TerraceTop", Size = Vector3.new(width, p.rise, segLen),
				Position = Vector3.new(cx + side * (innerX + width / 2), top - p.rise / 2, zc),
				Color = grass, Material = ground, Parent = model })

			-- The exposed rock riser, pushed proud of the shelf's own front face and a little taller
			-- than the step, so neither of its large faces is ever coplanar with the slab behind it.
			newPart({ Name = "CliffFace", Size = Vector3.new(4, p.rise + 1.5, segLen),
				Position = Vector3.new(cx + side * (innerX + 1), top - p.rise / 2, zc), Color = rock,
				Material = Enum.Material.Rock, CanCollide = false, Parent = model })

			-- Strata: two horizontal bands of paler and darker stone across the riser, standing proud
			-- of it in turn. A tall rock wall in one flat tone is a painted board; the bands are what
			-- make it look quarried.
			for k = 1, 2 do
				local h = p.rise * (k == 1 and 0.16 or 0.1)
				newPart({ Name = "CliffStrata", Size = Vector3.new(2.6, h, segLen),
					Position = Vector3.new(cx + side * (innerX - 0.4), top - p.rise * (k == 1 and 0.42 or 0.74), zc),
					Color = k == 1 and rockLit or rockDark, Material = Enum.Material.Rock,
					CanCollide = false, CastShadow = false, Parent = model })
			end

			-- a vertical crack, so the strata do not turn the wall into a stack of ruled lines
			newPart({ Name = "CliffCrack", Size = Vector3.new(2.2, p.rise * math.random(45, 85) / 100, math.random(3, 7)),
				Position = Vector3.new(cx + side * (innerX - 0.6), top - p.rise * 0.5, zc + math.random(-30, 30)),
				Color = rockDark, Material = Enum.Material.Rock, CanCollide = false, CastShadow = false, Parent = model })

			-- ===== ROCK OUTCROPS ON THE RISER =====
			--
			-- The riser above is ONE SLAB 4 thick and `segLen` long -- 230 studs of flat wall per
			-- segment. The strata and the crack are paint on it: they break the tone, not the
			-- silhouette, and from any distance the terraces still read as ruled grey steps.
			--
			-- What actually breaks a straight edge is geometry standing PROUD of it, which is exactly
			-- what the rampart cladding already does for the boundary wall. Same library, same rule.
			--
			-- THREE PER SEGMENT, NOT A CONTINUOUS FACING. Covering the whole 230 studs would need ~10
			-- meshes a segment, i.e. 6,000 across the world on top of the 77,000 parts already here.
			-- Three outcrops cover roughly half the run and leave the banded slab showing between them,
			-- which is what a real cliff looks like anyway -- outcrops with weathered rock between.
			-- 3 x 5 segments x 3 tiers x 2 sides = 90 a zone.
			--
			-- Non-colliding, and the slab behind stays: the slab is the walkable surface and the thing
			-- that stops a player seeing through the terrace. A mesh is scenery hung on the front of it.
			if cliffFace then
				for k = 1, 3 do
					-- WHERE IT GOES IS DECIDED BEFORE IT IS CLONED (11.24). The cladding hangs in the riser
					-- plane, which is exactly where a `FallSheet` hangs, so a slot inside a fall corridor is
					-- a rock mesh growing out of the middle of a waterfall -- 249 of them across the world.
					-- 32, not the 26 the 52-stud width cap implies: the clad is yawed by up to 14 degrees
					-- on top of its quarter turn, and a 52 x 30 footprint at 14 degrees spans 58 along z.
					local slotZ = zc + (k - 2) * (segLen / 3) + math.random(-18, 18)
					if claimedZ(tier, slotZ, 32) then continue end
					local clad = cliffFace:Clone()
					local _, raw = clad:GetBoundingBox()
					-- SHORTER THAN THE RISER, NOT TALLER. These were sized at 1.06-1.28x the step so their
					-- crests would break the shelf line above -- and the cliff mesh has GRASS ON TOP OF IT,
					-- so what actually appeared was a second little green terrace punching up through the
					-- real one, three times per segment, ninety times a zone. From the valley that is a field
					-- of grey blocks growing out of the lawn, which is exactly the complaint. Kept under the
					-- tread the same mesh reads as what it is: weathered rock cladding the face.
					-- Width is still capped so a deep mesh cannot swallow its neighbours.
					local want = p.rise * (0.74 + math.random() * 0.2)
					clad:ScaleTo(math.min(want / math.max(raw.Y, 1), 52 / math.max(raw.X, raw.Z, 1)))
					for _, part in ipairs(clad:GetDescendants()) do
						if part:IsA("BasePart") then
							part.Anchored = true
							part.CanCollide = false
						end
					end
					clad.Name = "TerraceRock"
					clad.Parent = model
					-- (`slotZ` is chosen above, before the clone: spread across the segment with jitter, so
					-- three shelves stacked above one another never line their outcrops up into a column)
					-- PivotTo, not seatModel: seatModel drops a model to y = 0, and this one belongs on
					-- the tier's own foot, `p.rise` below the shelf it is facing.
					local _, fit = clad:GetBoundingBox()
					-- HALF OF THEM GET A HALF TURN. One mesh repeated ninety times a zone reads as a row of
					-- identical teeth however much the height is jittered, because the SILHOUETTE never
					-- changes -- and the silhouette is the only thing visible against the sky. Turning a
					-- rock 180 degrees shows its other profile, which is free variety from the same asset.
					-- A small roll on top makes some lean into the slope rather than all standing plumb.
					local flip = (math.random(1, 2) == 1) and math.pi or 0
					-- foot buried two studs into the tier below, crest under the tread above
					clad:PivotTo(CFrame.new(
						cx + side * (innerX - 1.5),
						top - p.rise + fit.Y / 2 - 2,
						slotZ
					) * CFrame.Angles(0, (side > 0 and math.rad(90) or math.rad(-90)) + flip + math.rad(math.random(-14, 14)), math.rad(math.random(-5, 5))))
				end
			end

			-- ROUNDED FRONT. A cylinder lying along Z, its curved side facing out over the drop: this
			-- is what turns the shelf's leading edge from a hard 90-degree corner into the soft
			-- rolled-over lip the reference has. It replaces the flat stone lip, which read as a kerb.
			newPart({ Name = "CliffLip", Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(segLen, 7, 7), Orientation = Vector3.new(0, 90, 0),
				Position = Vector3.new(cx + side * (innerX + 1.5), top - 1.6, zc), Color = grass,
				Material = ground, CanCollide = false, Parent = model })

			-- THE CORNER WHERE TWO SEGMENTS DISAGREE. Segment i sticking out further than i+1 leaves a
			-- notch with a raw slab end showing across it; this closes it with rock, so the meander
			-- reads as an eroded headland instead of as a gap between two boxes.
			-- THICKER, AND WEARING GRASS. At 5 studs deep this was a fin: correct geometry -- it is the
			-- side of a step -- but a bare 27-stud-tall grey panel standing edge-on in the open, and now
			-- that the tiers genuinely meander the gaps it has to close are four times what they were, so
			-- the fins got four times longer. 13 deep with the shelf's own grass on top reads as the end
			-- of a terrace, which is what it is. Capped in length: past ~150 studs the two segments are
			-- not a notch any more, they are two different hillsides, and a wall between them is wrong.
			if i < SEGMENTS then
				local nextX = edges[tier][i + 1]
				local gap = math.min(math.abs(nextX - innerX), 150)
				if gap > 2 then
					local midX = cx + side * ((innerX + nextX) / 2)
					newPart({ Name = "CliffCorner", Size = Vector3.new(gap + 5, p.rise + 1.5, 13),
						Position = Vector3.new(midX, top - p.rise / 2, zc + segLen / 2),
						Color = rockLit, Material = Enum.Material.Rock, CanCollide = false, Parent = model })
					-- proud of the rock on top and to both sides, so no face is coplanar with it
					newPart({ Name = "CliffCornerTurf", Size = Vector3.new(gap + 7, 3.2, 15),
						Position = Vector3.new(midX, top - 0.4, zc + segLen / 2),
						Color = grass, Material = ground, CanCollide = false, Parent = model })
				end
			end

			-- BUTTRESSES broken out of the face. The heights are deliberately scattered ABOVE AND BELOW
			-- the step: every one cut to exactly the step height put its top edge flush with the tread
			-- and the whole row read as grey boxes glued to a wall.
			-- 58-138% of the step was the other half of the punch-through: a buttress cut to 138% stands
			-- a third of a step PROUD of the grass above it, and 26 studs deep at 3 studs out from the
			-- face it hangs 16 studs over the drop. Sixty of those a zone is the row of grey boxes lying
			-- half-sunk in the lawn. Kept below the tread and pulled back against the face, the same part
			-- reads as a buttress broken out of the cliff, which is what it was always meant to be.
			for j = 1, 2 do
				-- A buttress stands at this tier's inner edge and hangs BELOW its tread, which is the
				-- exact volume the top half of this tier's flight occupies -- 13 of them were found
				-- driven through a staircase -- and it stands in the riser plane, which is where the
				-- water comes down: 176 of them were found inside a fall corridor. Its width is drawn
				-- FIRST so the keep-out test is on its body rather than on its centre line.
				local w = math.random(22, 52)
				-- + 5 for the yaw it is about to be given, same lesson as the cladding above
				local z = freeZ(tier, zc, -segLen / 2 + 20, segLen / 2 - 20, w / 2 + 5)
				if not z then continue end
				local h = p.rise * math.random(50, 92) / 100
				local d = math.random(9, 17)
				-- ===== THE BUTTRESS IS THE WALL, SO IT STAYS SOLID -- BUT IT IS NO LONGER A STEP =====
				--
				-- It used to be centred at `innerX - 1.5`, which with a depth of 9-17 left it hanging
				-- 6 to 10 studs PROUD of the tier edge, out over the tread below. Its top sits at up
				-- to 92% of the rise, so it was a ledge you could jump onto and then step off onto the
				-- shelf -- two hops past a staircase that is meant to be the only way up (item 19).
				--
				-- ===== ...AND THE REASON IT HAD TO STAY SOLID WAS ALREADY FALSE (11.23) =====
				--
				-- What used to be written here: "a ray fired horizontally into a riser with the jut
				-- excluded hits only CliffFace, which is CanCollide = false; there is no other collision
				-- at that height, so the jut IS the riser wall." That was true when the risers were thin
				-- facings. It has not been true since the tiers became slabs: `TerraceTop` is `rise`
				-- thick, spans innerX out to the rim, is solid, and is PINNED in the world shell -- its
				-- own front face is the riser wall, and it cannot stream out from behind the jut either.
				--
				-- Measured rather than argued, 224 rays and a player-sized Blockcast per case:
				--   nothing excluded            -> 207 CliffJut, 12 CliffCrag,  5 CliffBlock, 0 through
				--   CliffJut excluded           -> 207 TerraceTop, 12 CliffCrag, 5 CliffBlock, 0 through
				--   CliffJut + TerraceTop out   -> 172 of 224 pass clean through
				-- So nothing opens up, and what closes is 2,621 solid-on-solid intersections with the
				-- terrace slabs (1,568 of them juts buried whole) plus 1,568 parts -- 45% of it -- taken
				-- out of the persistent shell.
				--
				-- It stays exactly where it is, two studs proud of the edge: that is the relief that
				-- keeps the face from reading as a painted board, and intangible it also cannot be the
				-- two-hop shortcut past a staircase that this offset was chosen to prevent.
				local jutX = innerX + d * 0.5 - 2
				newPart({ Name = "CliffJut", Size = Vector3.new(d, h, w),
					CFrame = CFrame.new(cx + side * jutX, top - p.rise + h / 2, z)
						* CFrame.Angles(0, math.rad(math.random(-4, 4)), math.rad(side * math.random(-3, 3))),
					Color = (j % 2 == 0) and rock or rockLit, Material = Enum.Material.Rock,
					CanCollide = false, Parent = model })
				-- a shoulder on the taller ones: an unbroken vertical box is a pillar, and a pillar with
				-- a sloped top is a rock. Kept at the same offset RELATIVE to the jut it caps, so it
				-- travels with the change above instead of being left hanging in the air.
				if h > p.rise * 0.78 then
					newPart({ Name = "CliffJutCap", Size = Vector3.new(d * 0.7, h * 0.22, w * 0.72),
						Position = Vector3.new(cx + side * (jutX - 1.5 - d * 0.14), top - p.rise + h * 1.04, z),
						Color = rockDark, Material = Enum.Material.Rock, CanCollide = false, Parent = model })
				end
			end

			-- ---- PLANTING, and it is deliberately DENSE. Everything else in this file places a
			-- handful of large props; the reference hillsides are covered in small bright things --
			-- mushrooms, grass clumps, crystals -- and that density is most of why they read as a place
			-- rather than as terrain. Kept off the outer strip so nothing grows through the wall.
			-- `treadOut`, NOT TERRAIN_OUTER -- see the note where treadOut is worked out. Scattering to
			-- the rim planted most of every lower shelf's mushrooms and grass inside the cliff above it.
			-- ...and off the stairs and out of the water (11.24). These are the densest thing on the
			-- hillside -- 9 clumps per segment, ~2,300 tufts across the world -- and 906 of them were
			-- standing inside a fall corridor, which is what a stream of water running through a lawn
			-- looks like. `spot` returns nil when the corridors have eaten this z, and the callers
			-- simply skip: one missing tuft out of nine is invisible, and a nudged one lands somewhere
			-- nothing tested.
			local function spot(ownHalf)
				local tz = freeZ(tier, zc, -segLen / 2 + 12, segLen / 2 - 12, ownHalf or 8)
				if not tz then return nil end
				return cx + side * span(innerX + 10, treadOut - 12), tz
			end
			for k = 1, 5 do
				local tx, tz = spot()
				if tz then
					tuft(tx, top, tz, math.random(12, 20), k % 4 == 0 and lighten(moss, 0.2) or moss, Enum.Material.Grass)
				end
			end
			for _ = 1, 3 do
				local tx, tz = spot()
				if tz then mushroom(tx, top, tz, math.random(7, 14)) end
			end
			-- one lit crystal clump per segment, in the zone accent -- the point of focus after dark,
			-- and the only thing up here that carries the zone's own colour
			do
				local tx, tz = spot()
				if tz then tuft(tx, top, tz, math.random(14, 24), accent, Enum.Material.Neon) end
			end
			-- A CONIFER IS THE ONE PLANT BIG ENOUGH TO BLOCK THE WAY UP. The grass, mushrooms and
			-- crystals above are 7 to 24 studs and non-colliding, so a few of them standing beside the
			-- steps is dressing; an 80-stud tree growing out of the middle of a flight is not. Nudged
			-- to the far side of the segment rather than dropped -- the shelves are planted densely on
			-- purpose and a bald segment would read as the one place the world forgot.
			if p.trees and math.random() < p.trees then
				-- 24 covers the widest canopy this call can produce (h * 0.7 / 2 at h = 80, before the
				-- mesh's own width cap), so the test is on the tree and not on its trunk.
				local tx, tz = spot(24)
				if tz then conifer(tx, top, tz, math.random(46, 80)) end
			end

			-- CRAGS: a spire standing on the tread, and the only thing in the band taller than one
			-- step -- so it is what gives the terraces a ragged skyline instead of clean horizontals.
			-- A TAPERING STACK of three, not one slab: a single block on end at this size reads as a
			-- gravestone, which is exactly what the first cut looked like.
			-- Against the BACK of the tread, in its outer third, so a crag reads as rock that has come
			-- down off the face behind it. Dropped in the middle of the shelf -- which is where
			-- `innerX + band * 0.4` put it once the tiers stopped being evenly spaced -- it is a grey
			-- slab standing in a field with nothing to explain it. A dark scree pad underneath is what
			-- makes it sit ON the grass instead of being stabbed into it.
			-- ...and NEVER standing in a flight of stairs. A crag is the biggest thing on a tread and
			-- it is CanCollide, so one in the way is not dressing, it is a wall.
			--
			-- TESTED ON ITS OWN z, NOT ON ITS SEGMENT INDEX, and the difference is not academic: a
			-- crag's z is `zc + span(-segLen/2 + 20, ...)`, so it may wander to within TWENTY studs of
			-- the NEXT segment's centre. Skipping stair segments still left three flights across the
			-- world with a spire in the middle of them, every one of them belonging to the segment
			-- next door. The band is what matters, so the band is what is asked.
			if i % 2 == 1 then
				local h = math.random(math.floor(p.rise * 1.5), math.floor(p.rise * 2.8))
				local w = math.random(22, 40)
				local sx = cx + side * span(innerX + (treadOut - innerX) * 0.55, treadOut - 16)
				-- half the spire's own width on top of the corridor, so it clears both the flight and
				-- the fall by its EDGE rather than by its centre. Not built at all if there is no room:
				-- a crag rerolled onto a spot nothing tested is how the last three ended up in a flight.
				-- `w * 0.72`: the scree pad is the widest thing this block lays (w * 1.24) and it is
				-- yawed, so its half-width along z is a little more than half its nominal size.
				local sz = freeZ(tier, zc, -segLen / 2 + 20, segLen / 2 - 20, w * 0.72)
				if not sz then continue end
				local yaw = math.rad(math.random(0, 360))
				local lean = math.rad(side * -math.random(2, 6))
				-- barely proud of the grass: this is a contact shadow, not a paving slab. At 2.2 studs
				-- of a dark tone it read as a rectangle of tarmac laid under every crag.
				newPart({ Name = "CragScree", Size = Vector3.new(w * 1.24, 1.4, w * 1.1),
					CFrame = CFrame.new(sx, top + 0.5, sz) * CFrame.Angles(0, yaw, 0),
					Color = rock:Lerp(rockDark, 0.5), Material = Enum.Material.Slate,
					CanCollide = false, CastShadow = false, Parent = model })
				newPart({ Name = "CliffCrag", Size = Vector3.new(w, h * 0.52, w * 0.88),
					CFrame = CFrame.new(sx, top + h * 0.24, sz) * CFrame.Angles(0, yaw, lean),
					Color = rock, Material = Enum.Material.Rock, Parent = model })
				-- Both SOLID, like the base course (11.22). A crag is 39-90 studs of stone standing on a
				-- shelf a player now walks along; with only the bottom half of the stack solid, a drop-ray
				-- onto every one of the 426 mids and 426 caps in the world fell through to `CliffCrag`.
				newPart({ Name = "CliffCragMid", Size = Vector3.new(w * 0.68, h * 0.42, w * 0.6),
					CFrame = CFrame.new(sx, top + h * 0.66, sz) * CFrame.Angles(0, yaw + 0.5, lean * 1.6),
					Color = rockLit, Material = Enum.Material.Rock, Parent = model })
				newPart({ Name = "CliffCragCap", Size = Vector3.new(w * 0.36, h * 0.3, w * 0.34),
					CFrame = CFrame.new(sx, top + h * 0.94, sz) * CFrame.Angles(0, yaw + 1.1, lean * 2.4),
					Color = rockDark, Material = Enum.Material.Rock, Parent = model })
			end
		end
	end

	-- ===== A WAY UP. THE SHELVES WERE SCENERY BECAUSE NOTHING COULD REACH THEM =====
	--
	-- The comment further down calls the terraces GROUND rather than scenery, and the collision on
	-- them says the same -- but a riser is 20 to 50 studs of sheer rock and the player's jump clears
	-- about six at stage 1 and thirteen at stage 3. Nobody has ever stood on one. That was survivable
	-- while the band was only a horizon; it stops being survivable the moment anything worth walking
	-- to is put up there, which is what the raised Brutes and Elites in CreatureService now are.
	--
	-- One flight per tier per side, each in its own segment (see `stairSeg`, worked out before any
	-- prop was placed so the crags and boulders could be kept out of the way). Scattering them is
	-- the interesting half: reaching the top shelf means climbing, walking along the tread to find
	-- the next flight, and climbing again. A single stack of flights one above the other would be a
	-- staircase with a view; this is a route.
	--
	-- ===== THE COLLISION IS A RAMP; THE STEPS ARE PAINT =====
	--
	-- Cut as real steps this was 6-18 parts per tier per side -- roughly 1,900 across the strip --
	-- and every one of them would have had to be pinned into WorldShell, because a walkable surface
	-- allowed to stream out is a hole a player falls through while they are standing on it. The
	-- shell is 2,493 parts today; a 76% increase in the set that is replicated to every client at
	-- join, forever, is not worth a staircase.
	--
	-- So the thing you stand on is ONE slab lying at the pitch of the climb -- 1 pinned part per
	-- flight, ~126 across the world -- and the steps are non-colliding faces laid on top of it that
	-- stream like any other decoration. Lose them to streaming and the route still works; you are
	-- walking up the same ramp either way. Humanoid.MaxSlopeAngle is 89 by default, so every pitch
	-- these profiles can produce (25 to 59 degrees) is walked up without a single jump.
	--
	-- The flight runs INWARD from the riser it climbs and stands on the tread below it. `backstop`
	-- is a hard limit and not a style choice: past the inner edge of the shelf underneath, there is
	-- nothing under the ramp but the valley floor thirty studs down.
	do
		for tier = 1, p.tiers do
			local i = stairSeg[tier]
			local outer = edges[tier][i] + 1     -- a stud INTO the riser, so no two faces are coplanar
			local bottom = (tier > 1) and treadY(tier - 1) or 0
			local top = treadY(tier)
			local backstop = (tier > 1) and edges[tier - 1][i] or (TERRAIN_INNER - 46)
			local run = math.max(20, outer - backstop)
			local zc = segZ(i)

			-- world ends of the climb. `side` is which half of the zone this is, so the whole flight
			-- mirrors with it and the maths below never has to know which one it is on.
			local footX = cx + side * (outer - run)
			local headX = cx + side * outer
			local steps = math.clamp(math.floor(run / 5.5), 4, 12)
			local riser = (top - bottom) / steps

			-- ===== A FLIGHT HAS TO BE VISIBLE FROM THE VALLEY (9.6) =====
			--
			-- Measured before this existed: the stair faces and the cliff face were the SAME value --
			-- 0.51 and 0.51, a difference of zero. The steps were painted `rock` and `lighten(rock,
			-- 0.16)`, and `rock` is exactly the colour of the cliff they are cut into, so a flight was
			-- a shape you could only find by walking into it. That is the whole of "you have to hunt
			-- for the route up": the climb worked, it just could not be seen. Six flights per zone sit
			-- 400+ studs off the street, which is precisely the distance at which a zero-contrast
			-- stripe is nothing at all.
			--
			-- Worn steps are PALER than the rock around them, so that is the direction -- but stated as
			-- a fraction of the cliff's own value rather than as a lerp, for the reason the path verge
			-- paid for: "blend toward X then lighten" cancels at some inputs and this file has twenty
			-- of them. On an already-bright cliff it goes the other way, the same contrast flip the
			-- village trim uses.
			local cliffV = select(3, Color3.toHSV(rock))
			local function tread(amount)
				local h, s = Color3.toHSV(rock)
				local v = cliffV > 0.62 and cliffV * (1 - amount) or cliffV + (1 - cliffV) * amount
				return Color3.fromHSV(h, s * 0.82, math.clamp(v, 0.04, 1))
			end
			-- two tones so individual steps stay countable close up; both clear of the cliff so the
			-- flight reads as one pale stripe from across the valley
			local treadA, treadB = tread(0.42), tread(0.26)

			-- ---- THE STEPS, WHICH ARE THE THING YOU SEE. Each one is a solid block standing on the
			-- tread below and reaching its own height, so its top is horizontal, its front face is the
			-- riser, and nothing about it floats -- the first cut laid thin plates along the pitch of
			-- the ramp instead, which from the side read as slats nailed to a plank.
			for k = 1, steps do
				local h = riser * k
				local sx = footX + (headX - footX) * ((k - 0.5) / steps)
				newPart({ Name = "TerraceStairFace", Size = Vector3.new((run / steps) * 1.02, h, 30),
					Position = Vector3.new(sx, bottom + h / 2, zc),
					Color = (k % 2 == 0) and treadA or treadB, Material = Enum.Material.Rock,
					CanCollide = false, CastShadow = false, Parent = model })
			end

			-- ---- AND THE THING YOU STAND ON, SUNK HALF A STEP INTO THEM.
			--
			-- lookAt puts the part's -Z on the top end, so the slab's LENGTH is its Z and the pitch
			-- falls out of the two end points rather than out of a trig call that would need its sign
			-- corrected per side. The slab is 4 thick and both ends are given as its CENTRE line, so
			-- every height below is the surface the player walks MINUS 2.
			--
			-- THE TOP END IS THE ONE THAT HAS TO BE EXACT: `top - 2` puts the walking surface flush
			-- with the shelf, so arriving is a step onto level ground rather than a lip to be jumped.
			-- The bottom end is half a riser up, which sinks the slab into the mass of the steps and
			-- hides it; the six studs of extra length then carry that end down below the tread it
			-- starts from, so setting off is a slope and not a kerb either.
			local from = Vector3.new(footX, bottom + riser * 0.5 - 2, zc)
			local to = Vector3.new(headX, top - 2, zc)
			-- 28 -> 34. THE COLLISION WAS NARROWER THAN THE STAIRCASE YOU CAN SEE. The visible steps
			-- are 30 studs deep and non-colliding paint; this slab is the only thing you actually
			-- stand on. At 28 it left a stud of nothing down each side of the flight, so walking up
			-- the visual edge of the stairs dropped the player off the side of the hill -- which is
			-- most of "you can fall if you snag on certain things" (item 18). 34 covers the painted
			-- tread with two studs to spare on each side, and still passes under the rails at +/-16.
			local ramp = newPart({ Name = "TerraceRamp", Size = Vector3.new(34, 4, (to - from).Magnitude + 6),
				CFrame = CFrame.lookAt(from:Lerp(to, 0.5), to), Color = rock,
				Material = Enum.Material.Rock, Parent = model })

			-- a kerb down each side, so the flight reads as cut into the hill rather than as a stack
			-- of slabs that happens to be climbable. Chunky on purpose: at 3 studs it was a pencil
			-- line, and the outline is what the whole art direction here is carried by.
			for _, sz in ipairs({ -1, 1 }) do
				newPart({ Name = "TerraceStairRail", Size = Vector3.new(4.5, 7, ramp.Size.Z),
					CFrame = ramp.CFrame * CFrame.new(sz * 16, 3, 0),
					Color = rockDark, Material = Enum.Material.Rock,
					CanCollide = false, CastShadow = false, Parent = model })
			end
		end
	end

	-- ---- boulders, sitting ON whichever shelf they land on rather than at y = 0
	for _ = 1, p.rocks do
		local tier = math.random(1, p.tiers)
		local z = math.random(-halfZ + 40, halfZ - 40)
		-- a 48-stud boulder parked on the steps is the same problem the crags had. This one is drawn
		-- from the whole depth rather than from inside a segment, so rerolling is cheaper than
		-- reasoning about where else it could go -- and the edges are tested, not just the centre,
		-- for the same reason the crags are.
		-- ...and out of the fall corridors too (11.24): a 48-stud boulder parked in the middle of a
		-- basin is the same problem as one parked on the steps, and 41 of them were.
		local half = p.rockSize[2] / 2
		for _ = 1, 6 do
			if not claimedZ(tier, z, half) then break end
			z = math.random(-halfZ + 40, halfZ - 40)
		end
		if claimedZ(tier, z, half) then continue end
		-- edgeAt, not riserX: the segment under this z may have pulled back forty studs, and a
		-- boulder placed off the nominal edge would be standing in the air over the tier below.
		-- Bounded on the far side by the NEXT tier's edge for the same reason the plants are -- past
		-- it there is no tread, only the underside of the shelf above.
		local innerX = edgeAt(tier, z)
		local outerX = (tier < p.tiers) and edgeAt(tier + 1, z) or TERRAIN_OUTER
		-- ===== A BOULDER MUST NOT BE A STEP ONTO THE NEXT SHELF (item 19) =====
		--
		-- The outer bound was `outerX - 18`, i.e. a boulder CENTRE 18 studs short of the next riser
		-- -- and `rockSize` reaches 48, so a big one overlapped the cliff above it by six studs and
		-- stood up to 30 studs tall against a rise of 20-26. Climb the boulder, jump, and you are on
		-- the shelf without ever finding the stairs. It was also the likeliest thing in the zone to
		-- wedge a player: a solid tilted slab half-buried in a wall.
		--
		-- The clearance is now derived from the boulder that could actually be rolled here rather
		-- than being a flat 18: half the widest possible rock, plus 24 studs of gap between its edge
		-- and the riser. Jumping the remaining gap while also gaining height is not a step, it is a
		-- stunt -- and unlike the flat number this cannot silently stop working when `rockSize` moves.
		local boulderClear = p.rockSize[2] * 0.5 + 24
		boulder(cx + side * span(innerX + 16, outerX - boulderClear),
			treadY(tier), z, math.random(p.rockSize[1], p.rockSize[2]))
	end

	-- ---- a scree of loose rock spilling from the foot of the first riser out onto the valley
	-- floor, which is what stops the terraces meeting the flat ground on a ruled line
	for _ = 1, 8 do
		local s = math.random(6, 15)
		newPart({ Name = "ValleyScree", Shape = Enum.PartType.Ball,
			Size = Vector3.new(s, s * 0.6, s * 0.88),
			Orientation = Vector3.new(0, math.random(0, 360), math.random(-24, 24)),
			-- ===== SCREE SPILLS FROM THE FOOT, IT DOES NOT LEAN ON IT (item 19) =====
			--
			-- The band ended at `TERRAIN_INNER - 6`, so a 15-stud rock (7.5 of radius) sat hard
			-- against the first riser -- and scree is SOLID (see SOLID_PROPS). Its top is ~4.5 studs
			-- up, which added to the 21.6-stud max-jump apex is 26.1 against a 26-stud rise: enough,
			-- by a tenth of a stud, to hop the first tier beside the stairs. Measured, not guessed --
			-- a shelf was found 9 studs from a scree rock and within jump height.
			-- Pulled back to 22-46 studs from the foot: still a spill that stops the terraces meeting
			-- the flat ground on a ruled line, no longer a step.
			Position = Vector3.new(cx + side * math.random(TERRAIN_INNER - 46, TERRAIN_INNER - 22),
				s * 0.22, math.random(-halfZ + 40, halfZ - 40)),
			Color = (math.random() < 0.5) and rock or rockDark, Material = Enum.Material.Rock,
			CanCollide = false, Parent = model })
	end

	-- ---- water at the foot of the cliff, and the falls that feed it
	if p.water then
		-- `poolZ` / `poolLen` are chosen at the top of this function now, with the falls -- see the
		-- note there. Nothing here rolls its own any more.
		--
		-- ===== 30, NOT 26, AND THE BED IS 46 RATHER THAN 52 (11.26) =====
		--
		-- The rim is 6 studs of solid stone at +/- 27, i.e. it occupied 24..30 from the pool's axis.
		-- The BED is 52 wide, i.e. 0..26 -- so every one of the 52 rims in the world had three studs
		-- of itself inside the slab it was supposed to be sitting beside, both solid. And its OUTER
		-- face landed at TERRAIN_INNER + 4, which is inside the first terrace slab: 20 more.
		--
		-- Cutting the bed to the width of the water it holds (46, the same as `PoolWater`) and moving
		-- the whole pool four studs off the cliff foot gives the kerb its own ground on both sides:
		-- 23.5..29.5 from the axis, outer face at TERRAIN_INNER - 0.5, inner face still well outside
		-- DECO_SPREAD_X. Nothing about how the pool reads changes -- the water is the same size.
		local poolX = cx + side * (TERRAIN_INNER - 30)
		newPart({ Name = "PoolBed", Size = Vector3.new(46, 1.6, poolLen + 12),
			Position = Vector3.new(poolX, 0.8, poolZ), Color = darken(rock, 0.3),
			Material = Enum.Material.Slate, Parent = model })
		local water = newPart({ Name = "PoolWater", Size = Vector3.new(46, 2.4, poolLen),
			Position = Vector3.new(poolX, 1.9, poolZ), Color = Color3.fromRGB(96, 210, 240),
			Material = Enum.Material.Glass, Transparency = 0.35, CanCollide = false, CastShadow = false, Parent = model })
		addLight(water, Color3.fromRGB(120, 220, 250), 30, 0.7)
		-- ===== AND THE SURFACE MOVES (33.10) =====
		-- Along the pool's long axis, slowly -- a pond has a drift, not a current. Everything else
		-- laid on this slab below (ripples, lilies, foam) sits at 3.15 and the sheet at 3.3, so it
		-- passes UNDER the lilies and over the water, which is where a film of moving water belongs.
		WaterFlow.Surface(water, { speed = 0.22, transparency = 0.66 })
		-- a stone rim, so the water is held by something instead of lying on the grass
		for _, dx in ipairs({ -26.5, 26.5 }) do
			newPart({ Name = "PoolRim", Size = Vector3.new(6, 3, poolLen + 12),
				Position = Vector3.new(poolX + dx, 1.5, poolZ), Color = rockLit,
				Material = Enum.Material.Rock, Parent = model })
		end

		-- ===== WHAT MAKES A RECTANGLE READ AS A POND =====
		--
		-- The pool is a 46-stud glass slab: a perfectly flat cyan rectangle with two hard straight
		-- edges. Nothing about it moves or breaks up, so it reads as a swimming pool cut into the
		-- grass. Three things fix that and none of them touches the slab itself.
		--
		-- Ripples ON the surface break the flatness, foam ALONG the rim hides the straight edge where
		-- water meets stone, and lily pads give the eye something with a known size to judge it by.
		-- All three sit just above the water plane at 3.15 -- the slab's own top is 3.1, and anything
		-- level with it z-fights, which is the shimmer that has been chased off this map twice.
		local surfaceY = 3.15
		local ripple = waterLib and waterLib:FindFirstChild("Water_Ripple")
		if ripple then
			for _ = 1, 3 do
				local r = ripple:Clone()
				local _, raw = r:GetBoundingBox()
				r:ScaleTo((16 + math.random() * 14) / math.max(raw.X, raw.Z, 0.1))
				for _, part in ipairs(r:GetDescendants()) do
					if part:IsA("BasePart") then
						part.Anchored = true; part.CanCollide = false; part.CastShadow = false
						part.Material = Enum.Material.Glass
						-- 0.62: at 0.45 a ripple read as a solid disc lying on the pool. It is meant to
						-- disturb the surface, not to be an object floating on it.
						part.Transparency = 0.62
						part.Color = Color3.fromRGB(150, 230, 250)
					end
				end
				r.Name = "PoolRipple"
				r.Parent = model
				local _, fit = r:GetBoundingBox()
				r:PivotTo(CFrame.new(poolX + math.random(-14, 14), surfaceY + fit.Y / 2,
					poolZ + math.random(-poolLen // 2 + 30, poolLen // 2 - 30))
					* CFrame.Angles(0, math.random() * math.pi * 2, 0))
			end
		end

		local lily = waterLib and waterLib:FindFirstChild("Water_Lily")
		-- lilies only where something could actually grow: a lava pool or a void pool with water
		-- lilies floating in it is worse than a bare rectangle
		if lily and (zone.key == "Forest" or zone.key == "Ocean" or zone.key == "DreamDimension"
			or zone.key == "Desert" or zone.key == "TimeRift") then
			for _ = 1, 2 do
				local l = lily:Clone()
				local _, raw = l:GetBoundingBox()
				l:ScaleTo((12 + math.random() * 8) / math.max(raw.X, raw.Z, 0.1))
				for _, part in ipairs(l:GetDescendants()) do
					if part:IsA("BasePart") then
						part.Anchored = true; part.CanCollide = false; part.CastShadow = false
					end
				end
				l.Name = "PoolLily"
				l.Parent = model
				local _, fit = l:GetBoundingBox()
				l:PivotTo(CFrame.new(poolX + math.random(-13, 13), surfaceY + fit.Y / 2,
					poolZ + math.random(-poolLen // 2 + 40, poolLen // 2 - 40))
					* CFrame.Angles(0, math.random() * math.pi * 2, 0))
			end
		end

		local foam = waterLib and waterLib:FindFirstChild("Water_FoamLine")
		if foam then
			-- along BOTH rims, at the waterline. This is the piece that does the most work: the hard
			-- straight edge where a glass slab meets a stone kerb is the single most artificial thing
			-- about the pool, and a broken line of bubbles is exactly what a real shore has there.
			-- 22.5, not 21: the water slab is 46 across, so its lip is at 23. At 21 the whole line sat
			-- two studs INSIDE the pool and read as a causeway floating in it rather than as foam
			-- gathered against the kerb.
			for _, dx in ipairs({ -22.5, 22.5 }) do
				local probe = foam:Clone()
				local _, praw = probe:GetBoundingBox()
				-- 2.2, down from 5. The mesh is authored 5 studs tall and left at that height its
				-- bubbles stand knee-high in a line round the pool -- a snow bank, not foam. Foam is a
				-- detail at the waterline and has to be read as one.
				local fScale = 2.2 / math.max(praw.Y, 0.1)
				local fStep = math.max(praw.X, praw.Z) * fScale * 0.9
				probe:Destroy()
				for fz = poolZ - poolLen / 2 + fStep / 2, poolZ + poolLen / 2, fStep do
					local f = foam:Clone()
					f:ScaleTo(fScale)
					for _, part in ipairs(f:GetDescendants()) do
						if part:IsA("BasePart") then
							part.Anchored = true; part.CanCollide = false; part.CastShadow = false
							part.Transparency = 0.25
							part.Color = Color3.fromRGB(244, 253, 255)
						end
					end
					f.Name = "PoolFoam"
					f.Parent = model
					local _, fit = f:GetBoundingBox()
					-- sunk to its own midline, so the bubbles sit IN the surface rather than on top of it
					f:PivotTo(CFrame.new(poolX + dx, surfaceY - fit.Y * 0.15, fz)
						* CFrame.Angles(0, math.rad(90), 0))
				end
			end
		end

		-- reeds and wet stones along the rims -- the edge of a pool is where the eye goes, and a bare
		-- stone kerb reads as a swimming pool
		for i = 1, 7 do
			local rz = poolZ + (i - 4) * (poolLen / 8)
			tuft(poolX - side * 33, 0, rz, math.random(10, 18), moss, Enum.Material.Grass)
			local s = math.random(7, 14)
			-- ===== THE STONES STAND BESIDE THE KERB, NOT ON IT (11.26) =====
			--
			-- They used to land at `poolX + side * random(20, 30)`, i.e. squarely on top of the rim at
			-- 23.5..29.5 -- and `PoolStone` is in SOLID_PROPS, so `newPart` turns the CanCollide = false
			-- written here straight back on. Two solid bodies interpenetrating exactly where the player
			-- walks up to the water: 161 of them across the twenty zones.
			--
			-- The VALLEY side is the only side with room. Outward of the kerb there are four studs
			-- before the first terrace slab, and a 14-stud stone is a sphere of its smallest axis
			-- (see the Ball note in the codebase memory) -- 4.3 studs of radius. 36 clears the rim's
			-- outer face by two studs at the worst case and still reads as stones along the shore.
			newPart({ Name = "PoolStone", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 0.62, s * 0.9),
				Orientation = Vector3.new(0, math.random(0, 360), math.random(-18, 18)),
				Position = Vector3.new(poolX - side * math.random(36, 48), s * 0.2, rz + math.random(-14, 14)),
				Color = rockDark, Material = Enum.Material.Rock, CanCollide = false, Parent = model })
		end

		-- One emitter for the whole pool. Mist over water is the cheapest possible way to put motion
		-- into a band made entirely of anchored rock.
		-- MIST HUGS THE WATER. It did not: at 34 studs across, rising at 2-6 with another 3 of
		-- upward acceleration under it for up to 4.2 seconds, each puff climbed about FIFTY studs
		-- and ended up level with the terrace tops -- a drift of pale rounded slabs hanging in the
		-- sky over every zone with a pool in it, with nothing under them to explain what they were.
		-- Sized and paced to stay on the water now: peak rise is about eleven studs.
		local mist = Instance.new("ParticleEmitter")
		mist.Color = ColorSequence.new(Color3.fromRGB(226, 248, 255))
		mist.Size = NumberSequence.new(8, 18)
		mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.86), NumberSequenceKeypoint.new(1, 1) })
		mist.Lifetime = NumberRange.new(1.8, 3.0)
		mist.Rate = 5
		mist.Speed = NumberRange.new(1, 2.5)
		mist.SpreadAngle = Vector2.new(40, 40)
		mist.Acceleration = Vector3.new(0, 0.8, 0)
		mist.Parent = water

		-- CASCADES. A fall used to be a single sheet off tier 1, because a sheet starting higher up
		-- would have had to cut through the shelf standing in front of it. The answer is not one tall
		-- sheet but a STAIRCASE of them: one sheet per riser, all at the same z, each landing in a
		-- basin on the tread below and going over the next edge. This is also the second thing the
		-- one-step-tall tiers above bought -- on the old full-height slabs there was no tread to land
		-- on in the first place.
		-- `cascade` and every `fz` were fixed at the top of this function, BEFORE a single prop was
		-- placed, and every prop above tested them. This loop only reads them. (11.24)
		for i = 1, p.falls do
			local fz = fallZ[i]
			for tier = cascade, 1, -1 do
				-- the ACTUAL edge under this fall's z. On the old straight tiers this was riserX(tier);
				-- with a meandering edge that hangs the sheet in mid-air wherever a segment pulled back.
				local innerX = edgeAt(tier, fz)
				local top = treadY(tier)
				local foot = top - p.rise
				-- the sheet hangs on the riser, proud of it, so it is never coplanar with the rock, and
				-- it runs PAST both ends of the drop -- up behind the lip and down into the water -- so
				-- there is no seam where the water starts or stops
				--
				-- ===== 4.2, NOT 1.8 (11.25) =====
				-- `CliffJut` is the one piece of geometry that lives IN the riser plane and it is sunk
				-- into the hill from `innerX - 2` outward. The sheet is 4 wide, so centred at
				-- `innerX - 1.8` it occupied innerX-3.8 .. innerX+0.2 and overlapped the jut by 2.2
				-- studs -- 135 of the 190 sheets in the world were inside one. At 4.2 the sheet ends at
				-- innerX - 2.2 and the two are separated by two tenths of a stud. The gap this opens
				-- behind the sheet is 1.2 studs of rock face that the `FallCurtain` mesh in front of it
				-- covers completely; the corridor reservation above is what keeps a jut out of the
				-- water's z band in the first place, and this is the belt to that pair of braces.
				local fx = cx + side * (innerX - 4.2)
				local wide = 34 - (tier - 1) * 5
				local sheetH = p.rise + 9
				local sheet = newPart({ Name = "FallSheet", Size = Vector3.new(4, sheetH, wide),
					Position = Vector3.new(fx, foot + sheetH / 2 - 3.5, fz), Color = Color3.fromRGB(150, 230, 250),
					Material = Enum.Material.Glass, Transparency = 0.25, CanCollide = false, CastShadow = false, Parent = model })

				-- ===== THE CURTAIN THAT ACTUALLY FALLS (33.10) =====
				-- Three scrolling ribbons hung on the front face of the sheet. `-side` is the front:
				-- `FallStreak` two lines down uses the same sign for the same reason, and a curtain
				-- hung on `+side` is inside the cliff and photographs as nothing at all.
				WaterFlow.Fall(sheet, -side, Color3.fromRGB(206, 244, 255))

				-- WATER THAT IS ACTUALLY MOVING. Everything else here is static geometry, and static
				-- geometry is why the falls read as a striped pane of glass rather than as a waterfall --
				-- the streaks, the lip, the foam and the basin all describe the SHAPE of falling water
				-- without anything ever going down.
			--
				-- One emitter on the sheet itself, spanning its full width and height (EmissionDirection
				-- Top with a box-shaped spread), throwing droplets down the face at the speed gravity
				-- would. It is the cheapest possible motion cue: one instance per sheet, no per-frame
				-- script, and the engine culls it with the part when the chunk streams out.
				local drops = Instance.new("ParticleEmitter")
				drops.Name = "FallDrops"
				drops.Color = ColorSequence.new(Color3.fromRGB(222, 248, 255))
				drops.LightEmission = 0.55
				-- narrow and tall: a droplet is a streak, not a puff, and a round particle on a
				-- waterfall reads as snow
				drops.Size = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 2.2),
					NumberSequenceKeypoint.new(1, 3.4),
				})
				drops.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.25),
					NumberSequenceKeypoint.new(0.75, 0.45),
					NumberSequenceKeypoint.new(1, 1),
				})
				-- lifetime x speed has to land the droplet at the FOOT of the drop and not past it, or
				-- the fall appears to spray straight through its own basin
				drops.Lifetime = NumberRange.new(0.5, 0.8)
				drops.Speed = NumberRange.new(sheetH * 0.9, sheetH * 1.2)
				drops.Rate = 26
				drops.SpreadAngle = Vector2.new(4, 4)
				drops.Acceleration = Vector3.new(0, -46, 0)
				drops.EmissionDirection = Enum.NormalId.Bottom
				drops.Orientation = Enum.ParticleOrientation.VelocityParallel
				drops.Parent = sheet

				-- ===== THE CURTAIN ITSELF, AS GEOMETRY =====
				--
				-- Everything above describes falling water without any of it having a shape: a flat
				-- glass rectangle with three neon strips painted down it, which from any angle reads as
				-- a blue pane with white stripes on it. `Water_FallWide` is a real curtain -- it bulges,
				-- folds, and carries a foam crest -- so it goes in front and the slab behind it drops to
				-- near-invisible rather than being deleted: the slab is what fills the gap between the
				-- mesh and the rock when the tier heights do not divide evenly.
				local fallMesh = waterLib and waterLib:FindFirstChild("Water_FallWide")
				if fallMesh then
					sheet.Transparency = 0.86
					local curtain = fallMesh:Clone()
					local _, raw = curtain:GetBoundingBox()
					-- sized on HEIGHT, then checked on width: the sheet is `wide` across and the mesh is
					-- authored 17 x 16, so a pure height match would leave it too narrow to cover
					local byH = sheetH / math.max(raw.Y, 0.1)
					local byW = (wide * 1.05) / math.max(raw.X, 0.1)
					curtain:ScaleTo(math.max(byH, byW))
					for _, part in ipairs(curtain:GetDescendants()) do
						if part:IsA("BasePart") then
							part.Anchored = true
							part.CanCollide = false
							part.CastShadow = false
							-- tinted to the zone's own water rather than left bone white; the mesh was
							-- generated pale on purpose so this reads honestly in every biome
							part.Color = Color3.fromRGB(186, 240, 255)
							part.Material = Enum.Material.Glass
							part.Transparency = 0.12
						end
					end
					curtain.Name = "FallCurtain"
					curtain.Parent = model
					local _, fit = curtain:GetBoundingBox()
					-- faces the valley: `side` is -1 or +1 across the platform, so the two banks get
					-- opposite quarter turns and both curtains face the middle
					curtain:PivotTo(CFrame.new(fx - side * 1.5, foot + fit.Y / 2 - 3, fz)
						* CFrame.Angles(0, side > 0 and math.rad(90) or math.rad(-90), 0))
					-- ===== ...AND THEN PUSHED OFF THE ROCK (11.25) =====
					--
					-- `ScaleTo(math.max(byH, byW))` is deliberate and stays -- it is what guarantees the
					-- curtain covers the drop on BOTH axes -- but max means one axis is always oversized,
					-- and after the quarter turn the axis that grows is the one pointing INTO the hill.
					-- A 2.1x curtain is ~12 studs deep, so it was reaching several studs past `innerX`
					-- and drawing through the terrace slab and the buttress behind it.
					--
					-- Measured rather than assumed: the true world extent along x is summed from each
					-- part's own rotated box, and the whole model is slid outward until its innermost
					-- face clears the jut. Sliding costs nothing -- a waterfall standing a stud or two
					-- further out over the drop is indistinguishable -- where scaling to `min` would
					-- leave a bare stripe of rock down one side of every fall in the game.
					local reach = -math.huge
					for _, part in ipairs(curtain:GetDescendants()) do
						if part:IsA("BasePart") then
							local pcf, ps = part.CFrame, part.Size
							local hx = 0.5 * (math.abs(pcf.RightVector.X) * ps.X
								+ math.abs(pcf.UpVector.X) * ps.Y
								+ math.abs(pcf.LookVector.X) * ps.Z)
							reach = math.max(reach, side * (pcf.Position.X - cx) + hx)
						end
					end
					-- ...against the FURTHEST-IN edge the curtain's own width covers, not against the edge
					-- under its centre line. A curtain is 34-56 studs across and the segments meander, so
					-- one straddling a boundary was measured drilling into the neighbouring segment's slab
					-- (9 of the 190 falls) while clearing its own perfectly.
					local limit = math.min(edgeAt(tier, fz - wide * 0.6), innerX, edgeAt(tier, fz + wide * 0.6)) - 2.4
					if reach > limit then
						curtain:PivotTo(curtain:GetPivot() - Vector3.new(side * (reach - limit), 0, 0))
					end
				end

				-- and a churned splash where it lands, on the bottom step only -- that is where the
				-- whole cascade arrives, and one per fall beats one per step
				local splashMesh = (tier == 1) and waterLib and waterLib:FindFirstChild("Water_Splash")
				if splashMesh then
					local splash = splashMesh:Clone()
					local _, raw = splash:GetBoundingBox()
					-- 0.7, down from 1.15. At the wider figure a 34-stud fall grew a 39-stud ball of foam
					-- that stood taller than the terrace behind it and read as a cloud parked in the
					-- valley. Foam belongs at the waterline: smaller than the curtain, and mostly in it.
					splash:ScaleTo((wide * 0.7) / math.max(raw.X, raw.Z, 0.1))
					for _, part in ipairs(splash:GetDescendants()) do
						if part:IsA("BasePart") then
							part.Anchored = true
							part.CanCollide = false
							part.CastShadow = false
							part.Color = Color3.fromRGB(240, 253, 255)
							part.Transparency = 0.2
						end
					end
					splash.Name = "FallSplash"
					splash.Parent = model
					local _, fit = splash:GetBoundingBox()
					-- sunk below the waterline, so what shows is churn breaking the surface rather than
					-- the whole ball sitting on top of it
					splash:PivotTo(CFrame.new(fx - side * 7, foot - fit.Y * 0.18, fz)
						* CFrame.Angles(0, math.random() * math.pi * 2, 0))
				end
				-- Vertical banding down the face of the sheet. One flat pane of glass reads as a window,
				-- however blue it is; what actually says "falling water" is streaks running the whole
				-- drop, and they cost three parts.
				--
				-- ===== 0.62, NOT 0.45 -- THE STREAKS STAND DOWN NOW THAT SOMETHING MOVES (33.10) =====
				-- These exist to FAKE motion on a still pane, and at 0.45 they are three hard neon bars
				-- that dominate the face. Photographed against the new scrolling curtain they won: the
				-- eye read the bars, which do not move, and the fall looked exactly as it did before the
				-- beams existed. Backed off, they go back to being what they were meant to be -- the
				-- vertical structure the moving water is read against -- and the plume is what carries
				-- the frame. Deleting them was tried too and is worse: the fall loses its edges and
				-- reads as haze, which is off-style for a world built out of hard shapes.
				for k = -1, 1 do
					newPart({ Name = "FallStreak", Size = Vector3.new(2.4, sheetH * 0.94, wide * 0.15),
						Position = Vector3.new(fx - side * 2.6, foot + sheetH / 2 - 4, fz + k * wide * 0.3),
						Color = Color3.fromRGB(226, 250, 255), Material = Enum.Material.Neon, Transparency = 0.62,
						CanCollide = false, CastShadow = false, Parent = model })
				end
				-- The lip it pours over: a small block sitting ON the edge, half on the tread and half
				-- out over the drop. It used to be a wide flat slab six studs back from the edge, which
				-- read as a sheet of ice lying on the grass and not as the top of a waterfall.
				-- SUNK INTO THE SHELF, NOT LYING ON IT. At `top + 1.2` with a height of 3.2 the lip stood
				-- 2.8 studs clear of the grass -- a pale blue glass brick sitting on a lawn, which is what
				-- it read as from the valley. Water goes over an edge through a cut in it, so it is now
				-- mostly below the surface with a dark stone spillway either side to be the cut.
				newPart({ Name = "FallSpillway", Size = Vector3.new(13, 4.2, wide + 15),
					Position = Vector3.new(fx + side * 3.4, top - 1.1, fz), Color = rockDark,
					Material = Enum.Material.Rock, CanCollide = false, Parent = model })
				newPart({ Name = "FallLip", Size = Vector3.new(9, 3.0, wide + 3),
					Position = Vector3.new(fx + side * 2.6, top + 0.2, fz), Color = Color3.fromRGB(178, 240, 255),
					Material = Enum.Material.Glass, Transparency = 0.2, CanCollide = false, Parent = model })
				-- The header: on the TOP step of the cascade the water arrived at the lip out of nothing.
				-- A short run of the same stream back into the shelf gives it somewhere to have come from.
				if tier == cascade then
					local headOut = (tier < p.tiers) and edgeAt(tier + 1, fz) or TERRAIN_OUTER
					local headLen = math.max(12, (headOut - 6) - (innerX + 4))
					newPart({ Name = "FallHeadBank", Size = Vector3.new(headLen + 8, 3.4, wide + 16),
						Position = Vector3.new(cx + side * (innerX + 4 + headLen / 2), top - 0.8, fz),
						Color = rockDark, Material = Enum.Material.Rock, CanCollide = false, Parent = model })
					local head = newPart({ Name = "FallHead", Size = Vector3.new(headLen, 1.6, wide * 0.8),
						Position = Vector3.new(cx + side * (innerX + 4 + headLen / 2), top + 0.1, fz),
						Color = Color3.fromRGB(120, 220, 245), Material = Enum.Material.Glass,
						Transparency = 0.3, CanCollide = false, CastShadow = false, Parent = model })
					-- ===== THE HEADER RUNS TOWARDS THE LIP, NOT AWAY FROM IT (33.10) =====
					-- The stream is laid out from `innerX + 4` OUTWARD, so its +X end is the far end
					-- and the lip is at its `-side` end. A sheet scrolling the other way is water
					-- running uphill out of the drop, which is worse than water that does not move.
					WaterFlow.Surface(head, { axis = "X", sign = -side, speed = 0.9, transparency = 0.6 })
				end
				-- The basin it lands in. On tier 1 that is the pool itself, so only the upper steps get
				-- one: a second sheet of water lying on top of the pool would z-fight with it, which is
				-- the very thing this pass exists to remove.
				-- ===== THE WATER HAS TO GO SOMEWHERE BETWEEN TWO DROPS =====
				-- It used to land in a 30-stud blue rectangle and stop: a puddle in the middle of a shelf
				-- with a waterfall over it and nothing leading away, so each step read as a separate
				-- object dropped on the grass rather than as one cascade. The basin now RUNS ON across the
				-- tread and arrives at the lip of the step below, so the whole thing is continuous from the
				-- top shelf down into the pool. It is the same two parts, stretched, and the dark bank under
				-- it is what stops a stream reading as blue paint on grass.
				if tier > 1 then
					local belowX = edgeAt(tier - 1, fz)
					local nearX, farX = innerX - 2, belowX
					local runLen = math.max(16, nearX - farX)
					local midX = cx + side * (farX + runLen / 2)
					newPart({ Name = "FallBasinRim", Size = Vector3.new(runLen + 10, 3.4, wide + 22),
						Position = Vector3.new(midX, foot + 1.1, fz), Color = rockDark,
						Material = Enum.Material.Rock, CanCollide = false, Parent = model })
					local basin = newPart({ Name = "FallBasin", Size = Vector3.new(runLen, 1.6, wide + 14),
						Position = Vector3.new(midX, foot + 1.9, fz), Color = Color3.fromRGB(120, 220, 245),
						Material = Enum.Material.Glass, Transparency = 0.3, CanCollide = false, CastShadow = false, Parent = model })
					-- ===== THE BASIN HAS A DOWNHILL AND IT IS `-side` (33.10) =====
					-- It runs from `nearX` (under this drop) out to `belowX` (the lip of the step
					-- below), and `nearX > belowX`, so in world X that is `-side`. Faster than a pool
					-- and slower than the drop itself: it is a shelf of water on its way somewhere.
					WaterFlow.Surface(basin, { axis = "X", sign = -side, speed = 0.9, transparency = 0.6 })
				end
				local foam = newPart({ Name = "FallFoam", Shape = Enum.PartType.Ball,
					Size = Vector3.new(wide, 5, wide), Position = Vector3.new(fx - side * 9, foot + 3.2, fz),
					Color = Color3.fromRGB(235, 252, 255), Material = Enum.Material.Neon,
					Transparency = 0.45, CanCollide = false, CastShadow = false, Parent = model })
				if tier == 1 then
					addLight(foam, Color3.fromRGB(200, 245, 255), 26, 0.8)
					-- Spray, on the bottom step only. That is where the whole cascade lands and it keeps
					-- the emitter count to one per fall rather than one per step.
					local spray = Instance.new("ParticleEmitter")
					spray.Color = ColorSequence.new(Color3.fromRGB(238, 253, 255))
					spray.Size = NumberSequence.new(6, 22)
					spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
					spray.Lifetime = NumberRange.new(0.8, 1.6)
					spray.Rate = 22
					spray.Speed = NumberRange.new(8, 18)
					spray.SpreadAngle = Vector2.new(55, 55)
					spray.Acceleration = Vector3.new(0, -14, 0)
					spray.Parent = foam
				end
				-- two wet boulders flanking the plunge, which is what makes a sheet of glass read as
				-- water that has been falling there for a while
				for _, dz in ipairs({ -(wide * 0.7 + 6), wide * 0.7 + 6 }) do
					local s = math.random(11, 19)
					newPart({ Name = "FallStone", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 0.7, s * 0.9),
						Orientation = Vector3.new(0, math.random(0, 360), math.random(-16, 16)),
						Position = Vector3.new(fx - side * 8, foot + s * 0.24, fz + dz),
						Color = rockDark, Material = Enum.Material.Rock, CanCollide = false, Parent = model })
				end
			end
		end
	end
end

local function buildTerrain(model, zone, cx, groundMaterial)
	-- rise 26, not 16, for the reason given over TERRAIN_PROFILE: anything at or under the 21.6-stud
	-- max-jump apex is a shelf you hop onto instead of climbing to, and a fallback is exactly the
	-- case nobody re-measures.
	local p = TERRAIN_PROFILE[zone.key] or TERRAIN_FALLBACK
	for _, side in ipairs({ -1, 1 }) do
		buildValleySide(model, zone, cx, side, p, groundMaterial)
	end
end

-- `buildValleySide` and `TERRAIN_PROFILE` are deliberately NOT exported: one side of one zone is
-- not a thing anybody outside this file has ever wanted, and the profile is only meaningful
-- alongside the arithmetic that reads it.
return {
	buildTerrain = buildTerrain,
	crestY = terrainCrestY,
}
