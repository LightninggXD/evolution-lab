-- ============================================================================
-- ZONE DECOR -- the terrain band, the biome builders and the egg stall
-- ============================================================================
-- Split out of ZoneBuilder, which had reached 357 KB. That is not a tidiness complaint: past
-- ~200 KB a script can no longer have its Source written at all through the Studio bridge, and
-- multi_edit against a file that size times out and -- worse -- applies NON-ATOMICALLY, so a
-- two-edit call can land the second edit and drop the first. That is how a call to a function
-- that did not exist got into buildEgg. Both halves are now comfortably under the limit.
--
-- IT IS A FUNCTION MODULE, NOT A TABLE MODULE. Everything in here was written as a closure over
-- ZoneBuilder's top-level locals -- newPart, scatterPoint, lighten, the platform constants -- and
-- rewriting several thousand lines to qualify every one of those was not on. Instead ZoneBuilder
-- hands its helpers in and they are re-bound to the SAME NAMES on the first line, so every body
-- below resolves exactly as it did when it lived in the other file.
--
-- The helper list is not hand-written: it is every top-level name ZoneBuilder declares before this
-- point that the code below actually mentions. Add a call to a new helper and you must add it to
-- both lists, or it arrives as nil.
return function(H)
local ACTIVE_FRAME, CLEAR_HALF, CollectionService, DECO_SPREAD_X, GROUND_MATERIAL, GameConfig, PLATFORM_DEPTH, PLATFORM_WIDTH, PetModel, SIGN_FONT, ServerStorage, TweenService, addAtmosphere, addGlowPosts, addGroundLitter, addIdols, addLandmark, addLight, addMounds, addRuins, darken, lighten, makeSign, newPart, pulseForever, scaled, scatterPoint, spinForever, vivid
	= H.ACTIVE_FRAME, H.CLEAR_HALF, H.CollectionService, H.DECO_SPREAD_X, H.GROUND_MATERIAL, H.GameConfig, H.PLATFORM_DEPTH, H.PLATFORM_WIDTH, H.PetModel, H.SIGN_FONT, H.ServerStorage, H.TweenService, H.addAtmosphere, H.addGlowPosts, H.addGroundLitter, H.addIdols, H.addLandmark, H.addLight, H.addMounds, H.addRuins, H.darken, H.lighten, H.makeSign, H.newPart, H.pulseForever, H.scaled, H.scatterPoint, H.spinForever, H.vivid

local TERRAIN_INNER = 415        -- where the valley floor ends and the first cliff begins
local TERRAIN_OUTER = 625        -- the platform edge, where the boundary wall stands

-- Per-zone character. Anything absent falls back to the defaults in buildTerrain, so a new zone
-- costs nothing and the twenty here are genuinely different rather than recoloured copies of one
-- profile: tier counts, step heights, whether there is water at the foot, how rocky it is.
-- STEP HEIGHTS ARE ~1.7x WHAT THEY WERE. At 12-20 studs a step was shorter than the props standing
-- on it and the band read as three long ledges mown into a lawn rather than as a valley wall --
-- and a waterfall pouring down a 15-stud riser has no room to look like falling water. Totals now
-- run 66-128 studs against a 180-stud boundary wall, so the terraces climb most of the way up it
-- without ever poking over.
local TERRAIN_PROFILE = {
	-- `trees` is the CHANCE (0..1) that a given terrace segment gets a conifer, not a count: the
	-- segments already vary in size and position, so a probability spreads them unevenly where a
	-- count would plant the same number on every shelf. Absent = no trees, which is the right
	-- answer for the moon, the void and everything abstract.
	Forest          = { tiers = 3, rise = 26, water = true,  falls = 2, rocks = 9, rockSize = { 14, 30 }, trees = 0.85 },
	-- an OASIS, not a river: the one dry-looking biome that still earns water, and the only reason
	-- the Desert terraces are not a bare sand shelf from end to end
	Desert          = { tiers = 2, rise = 36, water = true,  falls = 1, rocks = 14, rockSize = { 18, 38 } },
	Ocean           = { tiers = 3, rise = 22, water = true,  falls = 3, rocks = 6, rockSize = { 12, 26 }, trees = 0.4 },
	Volcano         = { tiers = 3, rise = 34, water = true,  falls = 2, rocks = 14, rockSize = { 16, 40 } },
	Moon            = { tiers = 2, rise = 30, water = false, falls = 0, rocks = 16, rockSize = { 20, 44 } },
	Mars            = { tiers = 3, rise = 32, water = false, falls = 0, rocks = 13, rockSize = { 18, 40 } },
	Galaxy          = { tiers = 4, rise = 24, water = true,  falls = 2, rocks = 7, rockSize = { 12, 28 }, trees = 0.3 },
	BlackHole       = { tiers = 2, rise = 46, water = false, falls = 0, rocks = 10, rockSize = { 22, 46 } },
	Multiverse      = { tiers = 4, rise = 26, water = true,  falls = 3, rocks = 8, rockSize = { 14, 30 }, trees = 0.35 },
	Nebula          = { tiers = 3, rise = 28, water = true,  falls = 2, rocks = 9, rockSize = { 14, 32 } },
	Wormhole        = { tiers = 4, rise = 22, water = false, falls = 0, rocks = 11, rockSize = { 16, 34 } },
	QuantumRealm    = { tiers = 3, rise = 30, water = true,  falls = 2, rocks = 8, rockSize = { 12, 30 } },
	TimeRift        = { tiers = 4, rise = 25, water = true,  falls = 3, rocks = 9, rockSize = { 14, 32 } },
	AntimatterZone  = { tiers = 2, rise = 44, water = false, falls = 0, rocks = 15, rockSize = { 20, 44 } },
	DreamDimension  = { tiers = 4, rise = 20, water = true,  falls = 3, rocks = 6, rockSize = { 10, 26 }, trees = 0.5 },
	MirrorUniverse  = { tiers = 3, rise = 30, water = true,  falls = 2, rocks = 8, rockSize = { 14, 32 } },
	VoidExpanse     = { tiers = 2, rise = 50, water = false, falls = 0, rocks = 12, rockSize = { 22, 48 } },
	CelestialThrone = { tiers = 4, rise = 27, water = true,  falls = 3, rocks = 7, rockSize = { 14, 30 }, trees = 0.3 },
	Singularity     = { tiers = 3, rise = 34, water = false, falls = 0, rocks = 13, rockSize = { 18, 40 } },
	AbsolutePlane   = { tiers = 4, rise = 32, water = true,  falls = 4, rocks = 10, rockSize = { 16, 36 } },
}

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
local function buildValleySide(model, zone, cx, side, p)
	local grass = zone.groundColor
	-- The cliff is NOT the ground colour. Rock reads as rock because it is a different material and
	-- a different hue -- a cliff tinted from green grass is a green wall, which is what the first
	-- attempt at this looked like. It carries a quarter of the zone's tint so a Volcano cliff and a
	-- Moon cliff are still recognisably from their own worlds.
	local rock = Color3.fromRGB(150, 128, 104):Lerp(zone.groundColor, 0.25)
	local rockLit = lighten(rock, 0.16)
	local rockDark = darken(rock, 0.3)
	local moss = Color3.fromRGB(104, 164, 82):Lerp(zone.groundColor, 0.45)
	local accent = vivid(zone.accentColor)
	local ground = GROUND_MATERIAL[zone.key] or Enum.Material.Grass
	local band = (TERRAIN_OUTER - TERRAIN_INNER) / p.tiers
	local halfZ = PLATFORM_DEPTH / 2

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
		-- rock, because it breaks the silhouette's top edge
		newPart({ Name = "ValleyRockCap", Size = Vector3.new(s * 0.72, s * 0.44, s * 0.66),
			CFrame = CFrame.new(x + s * 0.1, y + s * 0.66, z - s * 0.08)
				* CFrame.Angles(math.rad(math.random(-12, 12)), math.rad(math.random(0, 360)), math.rad(math.random(-12, 12))),
			Color = rockLit, Material = Enum.Material.Rock, CanCollide = false, Parent = model })

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
		local w = h * 0.46
		newPart({ Name = "TerraceTrunk", Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(h * 0.3, w * 0.22, w * 0.22), Orientation = Vector3.new(0, 0, 90),
			Position = Vector3.new(x, y + h * 0.14, z),
			Color = Color3.fromRGB(112, 76, 48), Material = Enum.Material.Wood,
			CanCollide = false, CastShadow = false, Parent = model })
		local needle = Color3.fromRGB(46, 116, 62):Lerp(zone.groundColor, 0.2)
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
	local SEGMENTS = 5
	local segLen = PLATFORM_DEPTH / SEGMENTS

	-- math.random errors outright on an empty interval, and several placements below derive BOTH
	-- ends from the jittered edge -- so on the outermost tier of a 4-tier profile the low end can
	-- overtake the high one. This is what took the whole build down on Wormhole. Collapsing to the
	-- low end is the right answer: it means "there is no room to scatter here, put it at the edge".
	local function span(lo, hi)
		lo, hi = math.floor(lo), math.floor(hi)
		if hi <= lo then return lo end
		return math.random(lo, hi)
	end

	local edges = {}
	for tier = 1, p.tiers do
		edges[tier] = {}
		for i = 1, SEGMENTS do
			-- Jitter is capped so a shelf always keeps 70 studs of walkable tread, however many tiers
			-- the profile asks for. Without the cap a 4-tier zone's top shelf could pull back to a
			-- 15-stud ribbon -- which is not a terrace, it is a kerb.
			local room = math.max(0, math.min(band * 0.4, TERRAIN_OUTER - 70 - riserX(tier)))
			edges[tier][i] = riserX(tier) + math.random(0, math.floor(room))
		end
	end
	local function edgeAt(tier, z)
		local i = math.clamp(math.floor((z + halfZ) / segLen) + 1, 1, SEGMENTS)
		return edges[tier][i]
	end
	local function segZ(i) return -halfZ + segLen * (i - 0.5) end

	for tier = 1, p.tiers do
		local top = treadY(tier)

		for i = 1, SEGMENTS do
			local innerX = edges[tier][i]
			local width = TERRAIN_OUTER - innerX
			local zc = segZ(i)

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
			if i < SEGMENTS then
				local nextX = edges[tier][i + 1]
				local gap = math.abs(nextX - innerX)
				if gap > 2 then
					newPart({ Name = "CliffCorner", Size = Vector3.new(gap + 5, p.rise + 1.5, 5),
						Position = Vector3.new(cx + side * ((innerX + nextX) / 2), top - p.rise / 2, zc + segLen / 2),
						Color = rockLit, Material = Enum.Material.Rock, CanCollide = false, Parent = model })
				end
			end

			-- BUTTRESSES broken out of the face. The heights are deliberately scattered ABOVE AND BELOW
			-- the step: every one cut to exactly the step height put its top edge flush with the tread
			-- and the whole row read as grey boxes glued to a wall.
			for j = 1, 2 do
				local z = zc + span(-segLen / 2 + 20, segLen / 2 - 20)
				local w = math.random(22, 52)
				local h = p.rise * math.random(58, 138) / 100
				local d = math.random(12, 26)
				newPart({ Name = "CliffJut", Size = Vector3.new(d, h, w),
					CFrame = CFrame.new(cx + side * (innerX - 3), top - p.rise + h / 2, z)
						* CFrame.Angles(0, math.rad(math.random(-4, 4)), math.rad(side * math.random(-3, 3))),
					Color = (j % 2 == 0) and rock or rockLit, Material = Enum.Material.Rock, Parent = model })
				-- a shoulder on the taller ones: an unbroken vertical box is a pillar, and a pillar with
				-- a sloped top is a rock
				if h > p.rise then
					newPart({ Name = "CliffJutCap", Size = Vector3.new(d * 0.7, h * 0.22, w * 0.72),
						Position = Vector3.new(cx + side * (innerX - 3 - d * 0.14), top - p.rise + h * 1.04, z),
						Color = rockDark, Material = Enum.Material.Rock, CanCollide = false, Parent = model })
				end
			end

			-- ---- PLANTING, and it is deliberately DENSE. Everything else in this file places a
			-- handful of large props; the reference hillsides are covered in small bright things --
			-- mushrooms, grass clumps, crystals -- and that density is most of why they read as a place
			-- rather than as terrain. Kept off the outer strip so nothing grows through the wall.
			local function spot()
				return cx + side * span(innerX + 10, TERRAIN_OUTER - 14),
					zc + span(-segLen / 2 + 12, segLen / 2 - 12)
			end
			for k = 1, 5 do
				local tx, tz = spot()
				tuft(tx, top, tz, math.random(12, 20), k % 4 == 0 and lighten(moss, 0.2) or moss, Enum.Material.Grass)
			end
			for _ = 1, 3 do
				local tx, tz = spot()
				mushroom(tx, top, tz, math.random(7, 14))
			end
			-- one lit crystal clump per segment, in the zone accent -- the point of focus after dark,
			-- and the only thing up here that carries the zone's own colour
			do
				local tx, tz = spot()
				tuft(tx, top, tz, math.random(14, 24), accent, Enum.Material.Neon)
			end
			if p.trees and math.random() < p.trees then
				local tx, tz = spot()
				conifer(tx, top, tz, math.random(46, 80))
			end

			-- CRAGS: a spire standing on the tread, and the only thing in the band taller than one
			-- step -- so it is what gives the terraces a ragged skyline instead of clean horizontals.
			-- A TAPERING STACK of three, not one slab: a single block on end at this size reads as a
			-- gravestone, which is exactly what the first cut looked like.
			if i % 2 == 1 then
				local h = math.random(math.floor(p.rise * 1.5), math.floor(p.rise * 2.8))
				local w = math.random(22, 40)
				local sx = cx + side * span(innerX + band * 0.4, TERRAIN_OUTER - 16)
				local sz = zc + span(-segLen / 2 + 20, segLen / 2 - 20)
				local yaw = math.rad(math.random(0, 360))
				local lean = math.rad(side * -math.random(2, 6))
				newPart({ Name = "CliffCrag", Size = Vector3.new(w, h * 0.52, w * 0.88),
					CFrame = CFrame.new(sx, top + h * 0.24, sz) * CFrame.Angles(0, yaw, lean),
					Color = rock, Material = Enum.Material.Rock, Parent = model })
				newPart({ Name = "CliffCragMid", Size = Vector3.new(w * 0.68, h * 0.42, w * 0.6),
					CFrame = CFrame.new(sx, top + h * 0.66, sz) * CFrame.Angles(0, yaw + 0.5, lean * 1.6),
					Color = rockLit, Material = Enum.Material.Rock, CanCollide = false, Parent = model })
				newPart({ Name = "CliffCragCap", Size = Vector3.new(w * 0.36, h * 0.3, w * 0.34),
					CFrame = CFrame.new(sx, top + h * 0.94, sz) * CFrame.Angles(0, yaw + 1.1, lean * 2.4),
					Color = rockDark, Material = Enum.Material.Rock, CanCollide = false, Parent = model })
			end
		end
	end

	-- ---- boulders, sitting ON whichever shelf they land on rather than at y = 0
	for _ = 1, p.rocks do
		local tier = math.random(1, p.tiers)
		local z = math.random(-halfZ + 40, halfZ - 40)
		-- edgeAt, not riserX: the segment under this z may have pulled back forty studs, and a
		-- boulder placed off the nominal edge would be standing in the air over the tier below
		local innerX = edgeAt(tier, z)
		boulder(cx + side * span(innerX + 16, TERRAIN_OUTER - 18),
			treadY(tier), z, math.random(p.rockSize[1], p.rockSize[2]))
	end

	-- ---- a scree of loose rock spilling from the foot of the first riser out onto the valley
	-- floor, which is what stops the terraces meeting the flat ground on a ruled line
	for _ = 1, 8 do
		local s = math.random(6, 15)
		newPart({ Name = "ValleyScree", Shape = Enum.PartType.Ball,
			Size = Vector3.new(s, s * 0.6, s * 0.88),
			Orientation = Vector3.new(0, math.random(0, 360), math.random(-24, 24)),
			Position = Vector3.new(cx + side * math.random(TERRAIN_INNER - 40, TERRAIN_INNER - 6),
				s * 0.22, math.random(-halfZ + 40, halfZ - 40)),
			Color = (math.random() < 0.5) and rock or rockDark, Material = Enum.Material.Rock,
			CanCollide = false, Parent = model })
	end

	-- ---- water at the foot of the cliff, and the falls that feed it
	if p.water then
		local poolZ = math.random(-260, 260)
		local poolLen = math.random(220, 340)
		local poolX = cx + side * (TERRAIN_INNER - 26)
		-- The pool sits just INSIDE the first cliff, in the strip between the valley floor and the
		-- terraces -- 15 studs clear of DECO_SPREAD_X, so no scattered prop can ever land in it.
		newPart({ Name = "PoolBed", Size = Vector3.new(52, 1.6, poolLen + 12),
			Position = Vector3.new(poolX, 0.8, poolZ), Color = darken(rock, 0.3),
			Material = Enum.Material.Slate, Parent = model })
		local water = newPart({ Name = "PoolWater", Size = Vector3.new(46, 2.4, poolLen),
			Position = Vector3.new(poolX, 1.9, poolZ), Color = Color3.fromRGB(96, 210, 240),
			Material = Enum.Material.Glass, Transparency = 0.35, CanCollide = false, CastShadow = false, Parent = model })
		addLight(water, Color3.fromRGB(120, 220, 250), 30, 0.7)
		-- a stone rim, so the water is held by something instead of lying on the grass
		for _, dx in ipairs({ -27, 27 }) do
			newPart({ Name = "PoolRim", Size = Vector3.new(6, 3, poolLen + 12),
				Position = Vector3.new(poolX + dx, 1.5, poolZ), Color = rockLit,
				Material = Enum.Material.Rock, Parent = model })
		end

		-- reeds and wet stones along the rims -- the edge of a pool is where the eye goes, and a bare
		-- stone kerb reads as a swimming pool
		for i = 1, 7 do
			local rz = poolZ + (i - 4) * (poolLen / 8)
			tuft(poolX - side * 30, 0, rz, math.random(10, 18), moss, Enum.Material.Grass)
			local s = math.random(7, 14)
			newPart({ Name = "PoolStone", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 0.62, s * 0.9),
				Orientation = Vector3.new(0, math.random(0, 360), math.random(-18, 18)),
				Position = Vector3.new(poolX + side * math.random(20, 30), s * 0.2, rz + math.random(-14, 14)),
				Color = rockDark, Material = Enum.Material.Rock, CanCollide = false, Parent = model })
		end

		-- One emitter for the whole pool. Mist over water is the cheapest possible way to put motion
		-- into a band made entirely of anchored rock.
		local mist = Instance.new("ParticleEmitter")
		mist.Color = ColorSequence.new(Color3.fromRGB(226, 248, 255))
		mist.Size = NumberSequence.new(14, 34)
		mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.75), NumberSequenceKeypoint.new(1, 1) })
		mist.Lifetime = NumberRange.new(2.4, 4.2)
		mist.Rate = 6
		mist.Speed = NumberRange.new(2, 6)
		mist.SpreadAngle = Vector2.new(40, 40)
		mist.Acceleration = Vector3.new(0, 3, 0)
		mist.Parent = water

		-- CASCADES. A fall used to be a single sheet off tier 1, because a sheet starting higher up
		-- would have had to cut through the shelf standing in front of it. The answer is not one tall
		-- sheet but a STAIRCASE of them: one sheet per riser, all at the same z, each landing in a
		-- basin on the tread below and going over the next edge. This is also the second thing the
		-- one-step-tall tiers above bought -- on the old full-height slabs there was no tread to land
		-- on in the first place.
		local cascade = math.min(p.tiers, 3)
		for i = 1, p.falls do
			local fz = poolZ + (i - (p.falls + 1) / 2) * (poolLen / math.max(1, p.falls))
			for tier = cascade, 1, -1 do
				-- the ACTUAL edge under this fall's z. On the old straight tiers this was riserX(tier);
				-- with a meandering edge that hangs the sheet in mid-air wherever a segment pulled back.
				local innerX = edgeAt(tier, fz)
				local top = treadY(tier)
				local foot = top - p.rise
				-- the sheet hangs on the riser, proud of it, so it is never coplanar with the rock, and
				-- it runs PAST both ends of the drop -- up behind the lip and down into the water -- so
				-- there is no seam where the water starts or stops
				local fx = cx + side * (innerX - 1.8)
				local wide = 34 - (tier - 1) * 5
				local sheetH = p.rise + 9
				newPart({ Name = "FallSheet", Size = Vector3.new(4, sheetH, wide),
					Position = Vector3.new(fx, foot + sheetH / 2 - 3.5, fz), Color = Color3.fromRGB(150, 230, 250),
					Material = Enum.Material.Glass, Transparency = 0.25, CanCollide = false, CastShadow = false, Parent = model })
				-- Vertical banding down the face of the sheet. One flat pane of glass reads as a window,
				-- however blue it is; what actually says "falling water" is streaks running the whole
				-- drop, and they cost three parts.
				for k = -1, 1 do
					newPart({ Name = "FallStreak", Size = Vector3.new(2.4, sheetH * 0.94, wide * 0.15),
						Position = Vector3.new(fx - side * 2.6, foot + sheetH / 2 - 4, fz + k * wide * 0.3),
						Color = Color3.fromRGB(226, 250, 255), Material = Enum.Material.Neon, Transparency = 0.45,
						CanCollide = false, CastShadow = false, Parent = model })
				end
				-- The lip it pours over: a small block sitting ON the edge, half on the tread and half
				-- out over the drop. It used to be a wide flat slab six studs back from the edge, which
				-- read as a sheet of ice lying on the grass and not as the top of a waterfall.
				newPart({ Name = "FallLip", Size = Vector3.new(9, 3.2, wide + 3),
					Position = Vector3.new(fx + side * 2.6, top + 1.2, fz), Color = Color3.fromRGB(178, 240, 255),
					Material = Enum.Material.Glass, Transparency = 0.2, CanCollide = false, Parent = model })
				-- The basin it lands in. On tier 1 that is the pool itself, so only the upper steps get
				-- one: a second sheet of water lying on top of the pool would z-fight with it, which is
				-- the very thing this pass exists to remove.
				if tier > 1 then
					newPart({ Name = "FallBasinRim", Size = Vector3.new(36, 2.6, wide + 22),
						Position = Vector3.new(fx - side * 15, foot + 0.9, fz), Color = rockDark,
						Material = Enum.Material.Rock, CanCollide = false, Parent = model })
					newPart({ Name = "FallBasin", Size = Vector3.new(30, 2, wide + 16),
						Position = Vector3.new(fx - side * 15, foot + 2.4, fz), Color = Color3.fromRGB(120, 220, 245),
						Material = Enum.Material.Glass, Transparency = 0.3, CanCollide = false, CastShadow = false, Parent = model })
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

local function buildTerrain(model, zone, cx)
	local p = TERRAIN_PROFILE[zone.key] or { tiers = 3, rise = 16, water = false, falls = 0, rocks = 9, rockSize = { 14, 32 } }
	for _, side in ipairs({ -1, 1 }) do
		buildValleySide(model, zone, cx, side, p)
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


	-- IDOLS AND RUINS ARE OPT-OUT, NOT OPT-IN. There are twenty biome builders and each already
	-- passes its own palette here; making these two an extra key in every one of those tables would
	-- have meant twenty edits to add the feature and twenty more to change it. The accent is taken
	-- from whatever the zone already declared -- its landmark's accent first, its glow posts second
	-- -- so each zone's statues light up in its own colour with no new configuration at all.
	local accent = (cfg.idols and cfg.idols.accent)
		or (cfg.landmark and cfg.landmark.accent)
		or (cfg.glow and cfg.glow.color)
		or Color3.fromRGB(255, 226, 150)
	if cfg.idols ~= false then
		addIdols(model, cx, { count = (cfg.idols and cfg.idols.count) or 3, accent = accent })
	end
	if cfg.ruins ~= false then
		addRuins(model, cx, { count = (cfg.ruins and cfg.ruins.count) or 2, accent = accent })
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
	for _ = 1, 20 do
		local x, z = scatterPoint(cx, 195, 245)
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
-- ONE SPOT COLOUR PER EGG, and that is the whole difference between this and what was here before.
-- `speckles` used to be a list of four colours and every patch picked from it at random, so each
-- shell came out covered in red, blue, yellow and green blotches of differing size -- which does
-- not read as a pattern, it reads as a rash. The reference eggs are one clean shell colour plus
-- one strong accent, five or six patches, all the same size.
local EGG_TIER_STYLE = {
	Basic = {
		base = Color3.fromRGB(244, 250, 255),
		spot = Color3.fromRGB(126, 42, 226),
		shellMaterial = Enum.Material.SmoothPlastic,
	},
	Better = {
		base = Color3.fromRGB(250, 226, 200),
		spot = Color3.fromRGB(126, 214, 76),
		shellMaterial = Enum.Material.SmoothPlastic,
	},
	Premium = {
		-- The top tier is not a painted egg at all in the reference -- it is a faceted CRYSTAL, gold
		-- shards with a green base. Silhouette is what separates it from the other two, not a crown
		-- bolted onto the same shape, so `crystal` switches buildEgg to a different body entirely.
		base = Color3.fromRGB(255, 206, 40),
		spot = Color3.fromRGB(255, 240, 150),
		shellMaterial = Enum.Material.SmoothPlastic,
		crystal = true,
		crystalDark = Color3.fromRGB(240, 158, 26),
		crystalBase = Color3.fromRGB(96, 196, 84),
	},
}

-- One number drives the whole shell. The eggs were sized for a plaza you walk past, but they are
-- the thing the shop exists to sell and the reference art makes them the biggest object on the
-- counter -- so the rig is scaled as a unit instead of hand-retuning fifteen offsets.
local EGG_SCALE = 1.4
local EGG_SHELL_SIZE = Vector3.new(8, 10.5, 8) * EGG_SCALE
local EGG_PIVOT_Y = 7

-- Two parts, and the second one barely shows. Roblox balls are true ellipsoids, so one stretched
-- ball is a perfectly smooth shell -- but an ellipsoid is symmetric top to bottom and an egg is
-- not. The cap fixes that: a sphere sitting high enough that its equator is *inside* the main
-- shell and only its dome pokes out, which is exactly the pointed end.
-- (Four stacked lobes were tried first. Each junction showed as a ridge and the thing read as a
-- beehive; two lobes read as a snowman. The eye catches any waist, so do not add one.)
local EGG_BODY = Vector3.new(8.2, 10.6, 8.2) * EGG_SCALE
local EGG_CAP = Vector3.new(4.0, 4.0, 4.0) * EGG_SCALE
local EGG_CAP_Y = 3.4 * EGG_SCALE

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
-- The top tier is a faceted CRYSTAL, not a painted egg: in the reference it is a gold gem growing
-- out of a green rocky base. A different SILHOUETTE is what separates it from the other two at a
-- glance -- the old design bolted a glowing ball onto the same smooth shell, so from more than a
-- few studs away all three eggs were one object in three colours.
--
-- Blades lean out from a common point near the base, each yawed by the golden angle so no two line
-- up and the cluster reads as grown rather than as a fan. `piece` is buildEgg's own helper: it
-- records the PetOffset attribute the client animates against, so every shard turns and bobs with
-- the egg for free.
local function buildCrystalEgg(piece, center, style)
	local BLADES = 7
	local GOLD_ANGLE = math.pi * (3 - math.sqrt(5))
	for i = 1, BLADES do
		local f = (i - 1) / BLADES
		-- middle blades tallest, so the cluster has a peak instead of a flat top
		local h = (7.5 + math.sin(f * math.pi) * 4.5) * EGG_SCALE
		local w = (2.6 - f * 0.5) * EGG_SCALE
		local off = CFrame.Angles(0, i * GOLD_ANGLE, 0) * CFrame.Angles(math.rad(9 + f * 16), 0, 0)
			* CFrame.new(0, h * 0.5 - 3.4 * EGG_SCALE, 0)
		piece({ Name = "EggShard", Size = Vector3.new(w, h, w), CFrame = CFrame.new(center) * off,
			Color = (i % 2 == 0) and style.base or style.crystalDark,
			Material = Enum.Material.SmoothPlastic }, off)
		-- a paler tip: the one thing that makes a plain tapered block read as a faceted crystal
		local tip = off * CFrame.new(0, h * 0.42, 0)
		piece({ Name = "EggShardTip", Size = Vector3.new(w * 0.62, h * 0.26, w * 0.62),
			CFrame = CFrame.new(center) * tip, Color = style.spot,
			Material = Enum.Material.SmoothPlastic }, tip)
	end
	-- the green rock it grows out of. Three lumps rather than one ring, or it reads as a collar.
	for i = 1, 3 do
		local ang = i * (math.pi * 2 / 3) + 0.4
		local cf = CFrame.new(Vector3.new(math.cos(ang) * 2.4 * EGG_SCALE, -3.6 * EGG_SCALE,
			math.sin(ang) * 2.4 * EGG_SCALE)) * CFrame.Angles(0, ang, math.rad(12))
		piece({ Name = "EggCrystalBase", Size = Vector3.new(4.6, 3.2, 4.2) * EGG_SCALE,
			CFrame = CFrame.new(center) * cf, Color = style.crystalBase,
			Material = Enum.Material.SmoothPlastic }, cf)
	end
end

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

	-- THE BAND AND THE DARK UNDERSIDE ARE GONE. Between them, the crack and two gloss blobs, the
	-- shell was carrying five separate decorations and read as cluttered -- "like a disease" was the
	-- verdict. The reference eggs are ONE clean colour and a handful of large dots, and everything
	-- removed here was competing with those dots for the same small surface.

	-- THE CRACK IS GONE. It was a zig-zag of six shards across the front upper third, meant to say
	-- "something hatches out of this" -- but the reference eggs are unbroken, and at six studs of
	-- shell the shards read as dirt on the paint rather than as a fracture. What actually says
	-- "egg" here is the silhouette and the spots, so the six parts went to making those bigger.

	-- ===== THE DOTS =====
	-- FIVE, ALL THE SAME SIZE, ALL THE SAME COLOUR, EVENLY SPREAD. Every one of those four words was
	-- previously the opposite, and together they were the "disease" look: six patches of random size
	-- picked from a four-colour list at random directions, which clumps on one side of the shell and
	-- leaves the other bare.
	--
	-- Placement is a FIBONACCI SPIRAL rather than random directions. Random unit vectors clump --
	-- that is what random does -- and no amount of retrying fixes it; the golden angle is the
	-- standard construction for points that are provably never close together. `y` walks the
	-- hemisphere evenly and the golden angle turns 137.5 degrees between each one, so the five dots
	-- are spread over the shell no matter which way it has turned.
	--
	-- The eggs now SPIN (see PetFollowClient), which is exactly why this had to be even: a pattern
	-- biased to one face was acceptable on a static egg and is obviously wrong on a turning one.
	if style.crystal and buildCrystalEgg then
		buildCrystalEgg(piece, center, style)
		shell.Transparency = 1 -- still the PrimaryPart, the collider and the prompt's host
	end

	local GOLDEN = math.pi * (3 - math.sqrt(5))
	local DOTS = (style.crystal and buildCrystalEgg) and 0 or 5
	for i = 1, DOTS do
		-- -0.55..0.75 of the height: off the very bottom (nobody sees it) and off the very top (a dot
		-- centred on the crown reads as a hat, not as a spot)
		local y = 0.75 - (i - 0.5) * (1.3 / DOTS)
		local r = math.sqrt(math.max(0, 1 - y * y))
		local a = i * GOLDEN
		local offset = Vector3.new(
			math.cos(a) * r * EGG_BODY.X / 2,
			y * EGG_BODY.Y / 2,
			math.sin(a) * r * EGG_BODY.Z / 2
		) * 0.86
		-- Flattened on the axis it sticks out along so it lies ON the shell like paint instead of
		-- bulging off it like a berry. A ball sunk half-in bulges; a squashed one reads as a patch.
		local s = 4.2 * EGG_SCALE
		piece({
			Name = "EggSpot",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(s, s, s * 0.55),
			CFrame = CFrame.new(center + offset, center + offset * 2),
			Color = style.spot,
			Material = Enum.Material.SmoothPlastic,
		}, CFrame.new(offset, offset * 2))
	end

	-- ONE soft highlight, high on the shoulder. There were two, and on a shell this clean the second
	-- one just read as a smudge. Kept subtle: the shells are already bright, and a strong white blob
	-- competes with the dots.
	piece({
		Name = "EggGloss",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.6, 3.4, 2.0) * EGG_SCALE,
		Position = center + Vector3.new(-1.9, 2.4, 2.8) * EGG_SCALE,
		Color = Color3.fromRGB(255, 255, 255),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.62,
	}, Vector3.new(-1.9, 2.4, 2.8) * EGG_SCALE)

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
	-- three eggs turning at the same rate look mechanical; a few percent apart they never line up
	model:SetAttribute("SpinSpeed", 0.5 + (ex % 3) * 0.09)
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
	local model, root, pieces = PetModel.Build(def, "Normal", { scale = 1.5, plateDistance = 110, outline = false })
	model.Name = "FeaturePet"
	PetModel.Place(root, pieces, CFrame.new(ex, y, 0))
	model:SetAttribute("SpinAnchor", CFrame.new(ex, y, 0))
	model:SetAttribute("SpinSpeed", 0.7)
	model:SetAttribute("BobHeight", 0.45)
	CollectionService:AddTag(model, "PetDisplay")
	model.Parent = shop
	return model
end

-- Orbit a part around an arbitrary pivot with no per-frame Lua, by the same trick spinForever
-- uses: the repeating tween covers exactly one step of the arrangement's rotational symmetry, so
-- the jump back to the start value at the end of each cycle lands on an identical pose.
local function orbitForever(part, pivot, radius, startDeg, stepDeg, seconds)
	local function poseAt(deg)
		return pivot * CFrame.Angles(0, math.rad(deg), 0) * CFrame.new(radius, 0, 0)
	end
	part.CFrame = poseAt(startDeg)
	TweenService:Create(part, TweenInfo.new(seconds, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
		CFrame = poseAt(startDeg + stepDeg),
	}):Play()
end

-- Everything around the shell that is NOT part of the shell: the light column it stands in, a
-- turning starburst behind it, orbiting gems and sparkle. It is parented to the shop rather than
-- to the egg model, so the egg can bob and rock on the client without dragging its own halo
-- around, and none of it needs a PetOffset attribute.
local function addEggShowcase(shop, ex, eggY, accent, style)
	local ring = style.band or accent
	local core = style.gemColor or lighten(ring, 0.35)

	-- No light column here any more. A neon cylinder wrapped round the shell blew out to solid
	-- white the moment bloom touched it, and in a bright zone the egg -- the one thing the player
	-- came to look at -- was the least visible object on the podium.
	-- podium top derived from the egg height rather than read from PLAZA_PODIUM_TOP: that constant
	-- is declared below this function, so naming it here would resolve to a nil global
	local podiumTop = eggY - EGG_SHELL_SIZE.Y / 2
	local disc = newPart({ Name = "EggDisc", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 17, 17), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(ex, podiumTop + 0.5, 0), Color = ring, Material = Enum.Material.Neon, Transparency = 0.6, CanCollide = false, CastShadow = false, Parent = shop })
	addLight(disc, ring, 17, 0.9)

	-- starburst behind the shell: four crossed blades on a 45 degree symmetry, so a 45 degree
	-- tween loops seamlessly. This is the "shiny thing on a pedestal" cue the reference leans on.
	for i = 0, 3 do
		-- behind the shell, not around it: at z = -8 the blades poked out of the egg like spikes
		local base = CFrame.new(ex, eggY + 1, -13) * CFrame.Angles(0, 0, math.rad(i * 45))
		local blade = newPart({ Name = "EggStarBlade", Size = Vector3.new(0.8, 28, 0.4), CFrame = base, Color = core, Material = Enum.Material.Neon, Transparency = 0.9, CanCollide = false, CastShadow = false, Parent = shop })
		TweenService:Create(blade, TweenInfo.new(14, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
			CFrame = base * CFrame.Angles(0, 0, math.rad(45)),
		}):Play()
	end

	-- three gems on one orbit -- a 120 degree step is one full symmetry of the set
	local pivot = CFrame.new(ex, eggY + 1, 0)
	for i = 0, 2 do
		local gem = newPart({ Name = "EggOrbGem", Shape = Enum.PartType.Ball, Size = Vector3.new(2.8, 3.6, 2.8), Color = i == 1 and core or ring, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = shop })
		orbitForever(gem, pivot, 11.5, i * 120, 120, 6)
		pulseForever(gem, 0.5, 1.4 + i * 0.3)
	end

	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Color = ColorSequence.new(Color3.new(1, 1, 1), core)
	sparkle.Size = NumberSequence.new(1.5, 0)
	sparkle.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	sparkle.Lifetime = NumberRange.new(1.2, 2.2)
	sparkle.Rate = 9
	sparkle.Speed = NumberRange.new(1, 4)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.LightEmission = 1
	sparkle.Acceleration = Vector3.new(0, 3, 0)
	sparkle.Parent = disc
end

-- THE PRICE PLATE, and it is a PLATE ON THE PEDESTAL, not a card floating in front of it.
-- The reference art puts one small rounded tile on the face of each stand carrying nothing but an
-- icon and a number -- no tier name, no second row, no header bar. That is the whole design, and
-- it is why the eggs above it are what the eye lands on: the previous card was 14 studs wide and 7
-- tall with a colour-filled header, i.e. a poster, and three of them across the front of the stall
-- competed with the shells they were advertising.
--
-- Dropping the tier name here loses nothing -- it is the title of the odds board directly above
-- each egg, which is where somebody asking "what IS this one" is already looking.
local PRICE_PLATE_FACE = Color3.fromRGB(226, 232, 240)
local PRICE_PLATE_INK = Color3.fromRGB(28, 38, 58)

local function makePriceCard(shop, ex, y, egg, tierColor)
	-- Sized in studs, not pixels. A pixel-sized billboard keeps its screen size at range, so three
	-- of them 32 studs apart grew into each other -- and into the eggs -- from the plaza steps.
	local anchor = newPart({ Name = "PriceCardAnchor", Size = Vector3.new(1, 1, 1), Position = Vector3.new(ex, y, 7.4), Transparency = 1, CanCollide = false, CastShadow = false, Parent = shop })

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(11, 0, 4, 0) -- BillboardGui scale is studs; offset would be pixels
	bb.StudsOffset = Vector3.new(0, 0.6, 0)
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0 -- half the zones are lit near-black; a price must never go unreadable
	bb.MaxDistance = 95
	bb.Parent = anchor

	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 1, 0)
	card.BackgroundColor3 = PRICE_PLATE_FACE
	card.BorderSizePixel = 0
	card.Parent = bb
	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0.34, 0) -- in SCALE, so the pill survives any board size
	cardCorner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = PRICE_PLATE_INK
	stroke.Parent = card

	-- A hairline of the tier's own colour down the left edge. The reference plate is plain grey,
	-- but three identical grey pills say nothing about which egg is the expensive one; this is the
	-- smallest cue that keeps them apart without turning the plate back into a poster.
	local tab = Instance.new("Frame")
	tab.Size = UDim2.new(0.05, 0, 0.56, 0)
	tab.Position = UDim2.new(0.05, 0, 0.5, 0)
	tab.AnchorPoint = Vector2.new(0, 0.5)
	tab.BackgroundColor3 = tierColor
	tab.BorderSizePixel = 0
	tab.Parent = card
	local tabCorner = Instance.new("UICorner")
	tabCorner.CornerRadius = UDim.new(1, 0)
	tabCorner.Parent = tab

	local cost = Instance.new("TextLabel")
	cost.Size = UDim2.new(0.8, 0, 0.62, 0)
	cost.Position = UDim2.new(0.56, 0, 0.5, 0)
	cost.AnchorPoint = Vector2.new(0.5, 0.5)
	cost.BackgroundTransparency = 1
	cost.Font = Enum.Font.FredokaOne
	cost.TextScaled = true
	cost.TextColor3 = PRICE_PLATE_INK
	cost.Text = "🧬 " .. egg.cost
	cost.Parent = card

	return anchor
end

-- ===== EGG PLAZA =====
-- The shop is the first thing a player walks into in every zone, so it gets a built stage instead
-- of the old flat 54x26 slab: a two-step lit dais, a back wall carrying the EGGS banner and one
-- nameplate per tier, four pylons holding a canopy beam, and a spotlit podium under every egg.
-- Everything is laid out from the egg row on z = 0 outward, and stays inside the reserved centre
-- square (CLEAR_HALF), so no biome decoration can land on top of it.

-- A WOODEN MARKET STALL, NOT A CIVIC PLAZA. This had grown into a 138-stud stage: a two-step dais
-- with walk-up stairs, a 42-stud back wall, four 45-stud pylons carrying a canopy beam, four lamps
-- and a pair of bollards. That is a monument, and it read as one -- the three eggs the whole thing
-- exists to sell were the smallest objects in it.
--
-- The reference is a stall you walk up to: planks on the ground, a leaning board behind them, a
-- painted EGGS sign, and the eggs big and forward on little pedestals. The eggs are the tallest
-- thing on the stall now, which is the entire point of the stall.
local PLAZA_Z = -4            -- deck centre; the egg row sits 4 studs forward of it
local PLAZA_DECK_TOP = 1.2    -- the planks lie ON the ground now: no dais, no stairs
local PLAZA_PODIUM_TOP = 4.4  -- what each egg actually rests on
local EGG_SPACING = 32 -- was 21; the shells are 40% bigger and their haloes were overlapping

-- Warm timber, deliberately NOT tinted per zone: a wooden stall says "shop" in every biome, where
-- a Volcano-red or a Void-black one says nothing at all.
local STALL_WOOD = Color3.fromRGB(178, 126, 76)
local STALL_WOOD_DARK = Color3.fromRGB(139, 94, 54)
local STALL_PLANK = Color3.fromRGB(198, 148, 96)

-- The pedestals are a FIXED SLATE BLUE, not the zone accent. They used to be tinted from
-- zone.accentColor like everything else on the stall, which meant a Volcano stand was orange under
-- an orange egg and a Desert one was sand under a cream egg -- the stand and the thing it displays
-- disappeared into each other exactly where the player is meant to be comparing three of them.
-- The reference uses one cool dark stone under every egg for that reason: it is the neutral the
-- shells read against, in all twenty biomes. Same argument as STALL_WOOD above.
local PODIUM_STONE = Color3.fromRGB(64, 82, 104)
local PODIUM_STONE_DARK = Color3.fromRGB(42, 56, 74)
local PODIUM_STONE_LIT = Color3.fromRGB(124, 146, 170)

local function buildEggPlaza(shop, zone, cx, eggs)
	local accent = zone.accentColor
	-- Was rgb(38,38,46). Under its own canopy that read as a black hole in the middle of a bright
	-- zone: every darken() below starts from this, so the deck, the wall and the pylons all went
	-- near-black together. A mid slate keeps the neon trim and the eggs popping without the shop
	-- swallowing the light.
	-- Was rgb(92,88,112). Once the world was lit properly that mid-slate was the darkest thing in
	-- any zone -- the shop read as a black box parked in a bright biome. A warm near-white tinted
	-- toward the zone accent keeps it bright and still tells the zones apart.
	local stone = Color3.fromRGB(226, 219, 205):Lerp(accent, 0.24)
	local deckW = EGG_SPACING * (#eggs - 1) + 56
	local halfW = deckW / 2
	local backZ = PLAZA_Z - 20
	local frontZ = PLAZA_Z + 20

	-- ---- the deck: planks laid ON the ground. No dais and no stairs -- the reference stall is
	-- something you walk onto without noticing, and four rises of stair in front of a shop is three
	-- more decisions than buying an egg deserves.
	newPart({ Name = "StallDeck", Size = Vector3.new(deckW, 1.2, 40), Position = Vector3.new(cx, 0.6, PLAZA_Z), Color = STALL_WOOD_DARK, Material = Enum.Material.Wood, Parent = shop })
	-- individual boards, so it reads as carpentry instead of one brown rectangle
	local boards = math.max(6, math.floor(deckW / 9))
	local boardW = deckW / boards
	for i = 0, boards - 1 do
		newPart({ Name = "StallPlank", Size = Vector3.new(boardW - 0.8, 0.5, 39),
			Position = Vector3.new(cx - deckW / 2 + boardW * (i + 0.5), PLAZA_DECK_TOP, PLAZA_Z),
			Color = i % 2 == 0 and STALL_PLANK or STALL_WOOD, Material = Enum.Material.Wood, CanCollide = false, Parent = shop })
	end
	-- the glowing lip around the edge -- the one piece of neon the stall keeps, because it is what
	-- says "this patch of ground is a shop" from fifty studs out
	for _, dz in ipairs({ -20, 20 }) do
		newPart({ Name = "StallTrim", Size = Vector3.new(deckW + 2, 0.7, 1.8), Position = Vector3.new(cx, PLAZA_DECK_TOP, PLAZA_Z + dz), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = shop })
	end
	for _, side in ipairs({ -1, 1 }) do
		newPart({ Name = "StallTrim", Size = Vector3.new(1.8, 0.7, 40), Position = Vector3.new(cx + side * halfW, PLAZA_DECK_TOP, PLAZA_Z), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = shop })
	end

	-- ---- the counter the eggs stand behind, and the leaning display board above it. The board is
	-- TILTED BACK ~12 degrees like a market stall's panel; upright it is a wall, and a wall is
	-- exactly what this used to be.
	newPart({ Name = "StallCounter", Size = Vector3.new(deckW, 2.4, 9), Position = Vector3.new(cx, 2, backZ + 4.5), Color = STALL_WOOD_DARK, Material = Enum.Material.Wood, Parent = shop })
	local boardCF = CFrame.new(cx, 13, backZ) * CFrame.Angles(math.rad(-12), 0, 0)
	newPart({ Name = "StallBoard", Size = Vector3.new(deckW, 22, 1.6), CFrame = boardCF, Color = STALL_WOOD, Material = Enum.Material.Wood, Parent = shop })
	newPart({ Name = "StallBoardCap", Size = Vector3.new(deckW + 3, 2, 2.8), CFrame = boardCF * CFrame.new(0, 11.6, 0), Color = STALL_WOOD_DARK, Material = Enum.Material.Wood, CanCollide = false, Parent = shop })
	for _, side in ipairs({ -1, 1 }) do
		newPart({ Name = "StallPost", Size = Vector3.new(2.8, 27, 2.8), Position = Vector3.new(cx + side * (halfW - 1.4), 13.5, backZ + 1), Color = STALL_WOOD_DARK, Material = Enum.Material.Wood, Parent = shop })
		newPart({ Name = "StallPostCap", Shape = Enum.PartType.Ball, Size = Vector3.new(4.2, 4.2, 4.2), Position = Vector3.new(cx + side * (halfW - 1.4), 27.4, backZ + 1), Color = STALL_WOOD, Material = Enum.Material.Wood, CanCollide = false, Parent = shop })
	end

	-- ---- THE EGGS PANEL: A REAL PART, NOT A BILLBOARD.
	-- It was a makeSign BillboardGui, and a billboard always turns to face the camera and always
	-- draws in front of whatever is behind it in screen space -- so from the front of the stall the
	-- sign sat squarely across the middle egg, which is the one object it exists to advertise. As
	-- two slabs bolted to the board it occludes correctly: walk round and the eggs pass in front of
	-- it, exactly as the reference shows.
	--
	-- WHITE FACE, DARK BORDER, in every biome. makeSign defaults to the zone's colour, which put a
	-- dark purple plate on a dark purple board in half the strip. This is the one piece of the stall
	-- that has to be readable from the arrival gate, so it takes the highest contrast available and
	-- no zone tinting at all -- same argument as the timber and the pedestals.
	-- 10.2, not 7.6: the shells top out around 19-20 studs and the panel's lower half was sitting
	-- right behind the middle egg's crown, so from dead-on the word was half eaten. This lands the
	-- panel at ~23 and its text clear of everything on the counter.
	local signCF = boardCF * CFrame.new(0, 10.2, 1.6)
	-- Proportion matters here and it is not free to pick: a SurfaceGui TextLabel with TextScaled
	-- fits by whichever axis binds first, and on a 5:1 panel that is always the HEIGHT -- so the
	-- word came out as a small line floating in a wide white bar. About 3:1 is where the text
	-- actually fills the panel, which is the proportion the reference sign uses.
	newPart({ Name = "StallSignFrame", Size = Vector3.new(40, 14, 1.2), CFrame = signCF,
		Color = Color3.fromRGB(28, 38, 58), Material = Enum.Material.SmoothPlastic,
		CanCollide = false, Parent = shop })
	local signFace = newPart({ Name = "StallSignFace", Size = Vector3.new(35.5, 10, 1.2),
		CFrame = signCF * CFrame.new(0, 0, 0.5), Color = Color3.fromRGB(248, 250, 252),
		Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = shop })

	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "StallSignText"
		gui.Face = face
		gui.LightInfluence = 0 -- half the late zones are lit almost to black
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 36
		gui.MaxDistance = 260
		gui.Parent = signFace

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.new(0.5, 0, 0.5, 0)
		label.Size = UDim2.new(0.88, 0, 0.72, 0)
		label.Font = SIGN_FONT
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(28, 38, 58)
		label.Text = "\u{1F95A} EGGS"
		label.Parent = gui
	end

	-- ---- one podium per egg, each lit from above so the shell reads against the dark deck
	local startX = cx - EGG_SPACING * (#eggs - 1) / 2
	local built = {}
	for i, egg in ipairs(eggs) do
		local ex = startX + EGG_SPACING * (i - 1)

		-- THE PEDESTAL, built to the reference: a wide dark plinth, a narrow waisted column, and a
		-- pale cap wider than the column it stands on. The waist is the part that matters -- three
		-- discs each narrower than the last is a wedding cake, and a wedding cake reads as scenery.
		-- A column that pinches in and flares back out reads as a STAND, i.e. as something whose only
		-- job is to hold the thing above it, which is exactly what it is.
		-- Everything stays narrower than the egg, so the shell overhangs its stand and keeps the
		-- silhouette -- the old 19-stud podium was wider than the egg and stole it.
		newPart({ Name = "PodiumBase", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 15, 15), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(ex, PLAZA_DECK_TOP + 0.8, 0), Color = PODIUM_STONE_DARK, Material = Enum.Material.Slate, Parent = shop })
		newPart({ Name = "PodiumStep", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.1, 12.6, 12.6), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(ex, PLAZA_DECK_TOP + 2.1, 0), Color = PODIUM_STONE, Material = Enum.Material.Slate, Parent = shop })
		newPart({ Name = "PodiumWaist", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, 9.4, 9.4), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(ex, PLAZA_DECK_TOP + 3.2, 0), Color = PODIUM_STONE, Material = Enum.Material.Slate, Parent = shop })
		newPart({ Name = "PodiumTop", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.5, 12, 12), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(ex, PLAZA_PODIUM_TOP - 0.5, 0), Color = PODIUM_STONE_LIT, Material = Enum.Material.Slate, Parent = shop })
		-- a thin accent ring under the cap, so the egg does not float on grey. This is the ONE place
		-- the zone's colour is allowed onto the stand -- a lit line, not a surface.
		newPart({ Name = "PodiumGlow", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 12.9, 12.9), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(ex, PLAZA_PODIUM_TOP - 1.4, 0), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = shop })

		local eggY = PLAZA_PODIUM_TOP + EGG_SHELL_SIZE.Y / 2
		local shell = buildEgg(shop, ex, egg.tierSuffix, eggY)
		local style = EGG_TIER_STYLE[egg.tierSuffix] or EGG_TIER_STYLE.Basic
		-- addEggShowcase: REMOVED, not disabled by accident. It drew three orbiting gems and twelve
		-- 28-stud blades per egg in the zone accent -- in Forest, nine green balls and a thicket of
		-- spokes across the shells. The reference stall has nothing around its eggs, and that empty
		-- space is most of what makes it read as clean. The function is left in place: the arena and
		-- any future showcase can still use it.

		-- the rarest pet this egg can give, hovering between the shell and the halo, with the
		-- full five-species list above it. Together they are the whole answer to "what is in
		-- this egg", which is the question the three eggs on a podium exist to ask.
		-- RAISED TO CLEAR THE EGGS SIGN. These two are BillboardGuis: they always face the camera and
		-- always draw over whatever is behind them in screen space, so at their old heights the middle
		-- egg's featured pet sat squarely across the painted panel on the board -- from the front, the
		-- one angle the stall is designed to be seen from, the word EGGS was simply gone. The sign is
		-- a physical part and cannot be moved above them without floating off the board, so the
		-- billboards move instead. (They also had to clear the shells, which grew 40% earlier.)
		buildEggFeaturePet(shop, egg, ex, eggY + 19)
		buildEggOddsBoard(shop, egg, ex, eggY + 27)

		-- halo above the egg doubles as the spotlight source: a bare PointLight with nothing
		-- visible making it reads as the shell glowing on its own. It sits above the featured
		-- pet so the pet reads as lit from over its head rather than clipping through the disc.
		local halo = newPart({ Name = "PodiumHalo", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.7, 13, 13), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(ex, eggY + 33, 0), Color = lighten(accent, 0.3), Material = Enum.Material.Neon, Transparency = 0.55, CanCollide = false, Parent = shop })
		addLight(halo, lighten(accent, 0.3), 20, 1.1)

		-- one price card per podium, tier and cost on two lines. Both were nearly put on the back
		-- wall, but a billboard 21 studs behind the egg renders *behind* it in screen space and
		-- the shell hides the tier name -- in front of the podium it reads like a real price tag.
		makePriceCard(shop, ex, PLAZA_DECK_TOP + 1.6, egg, (EGG_TIER_STYLE[egg.tierSuffix] or EGG_TIER_STYLE.Basic).base)

		built[i] = shell
	end

	-- The canopy, the pylons and the back wall were dropping the whole shop into shadow at every
	-- ClockTime -- and this is the one spot in a zone where players stand still and look at
	-- things. Nothing structural here casts a shadow any more, and two warm fills under the beam
	-- lift the eggs off the deck -- gently: at 1.9 they blew the shells out to flat white and the
	-- speckles disappeared, which is the opposite of the point.
	-- The name prefix changed with the rebuild (Plaza* -> Stall*), and a shadow flag that silently
	-- matches nothing is worse than no flag at all -- the board and posts would have started
	-- casting again with nothing in the diff to say why.
	for _, d in ipairs(shop:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name:sub(1, 5) == "Stall" or d.Name:sub(1, 6) == "Podium") then
			d.CastShadow = false
		end
	end
	for _, side in ipairs({ -1, 1 }) do
		local fill = newPart({
			Name = "StallFill",
			Size = Vector3.new(1, 1, 1),
			Position = Vector3.new(cx + side * 14, 27, PLAZA_Z + 6),
			Transparency = 1,
			CanCollide = false,
			CastShadow = false,
			Parent = shop,
		})
		addLight(fill, Color3.fromRGB(255, 246, 220), 40, 0.4)
	end

	return built
end

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
			local halfHeight = (geom and geom.Size.Y / 2 or 7) * scale
			cactus:PivotTo(CFrame.new(x, halfHeight, z) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
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
	ACTIVE_FRAME = CFrame.new(-150, 0, 0)
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
	ACTIVE_FRAME = nil

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
	-- Set to one side like every other landmark, so the gate in the -Z wall keeps its approach.
	ACTIVE_FRAME = CFrame.new(-130, 0, 0)
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
	ACTIVE_FRAME = nil

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

-- Moves (or creates) the one canonical SpawnLocation onto the Forest arrival clearing. Called at
-- the end of Build(), so the Forest floor it stands on already exists. Any extra SpawnLocations
-- are removed -- Roblox picks between them at random, so a stray one left in the Forest monument
-- footprint would still strand a share of players inside the shop.
-- ===== BOSS EVENT ARENA =====
-- A round sand pit with a raised dais in the middle, ringed by a stepped stand, torch pylons and
-- banners. It sits straight through the gate at the Forest spawn (GameConfig.EventArena.centre) and
-- is reached no other way, which is why it can be this far off the zone strip and cost nothing.
--
-- Everything is laid out from the centre outward by angle, so the whole thing is four loops rather
-- than a hand-placed floor plan -- and it stays perfectly circular at any radius.


return {
	buildTerrain = buildTerrain,
	buildBiomeBase = buildBiomeBase,
	decorationBuilders = decorationBuilders,
	buildEggPlaza = buildEggPlaza,
}
end