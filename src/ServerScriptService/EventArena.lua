-- EventArena -- the Colosseum, which is not in a zone and never was.
--
-- A round sand pit with a raised dais in the middle, ringed by a stepped stand, torch pylons and
-- banners. It sits straight through the gate at the Forest spawn (`GameConfig.EventArena.centre`)
-- and is reached by teleport and no other way, which is why it can be that far off the zone strip
-- and cost nothing.
--
-- WHY IT IS ITS OWN FILE: it is the one thing `ZoneBuilder` builds that is not part of a zone. It
-- has its own version stamp for the same reason -- bumping `BUILD_VERSION` drops all twenty-one
-- zones and rebuilds ~60,000 parts, and the arena is ~900. It has been separate in every sense but
-- the physical one since it was written.
--
-- EVERYTHING IS LAID OUT FROM THE CENTRE OUTWARD BY ANGLE, so the whole thing is four loops rather
-- than a hand-placed floor plan, and it stays perfectly circular at any radius. The dressing
-- helpers below are stated in the arena's own polar terms (an angle and a radius out from one
-- centre), which is why they are here and not in `ZoneKit`: nothing else in the world is a circular
-- amphitheatre.
--
-- THE WAY HOME IS A `ZoneGate`, the same gateway every zone boundary is built from. That shared
-- door is why `ZoneGate` came out as a file of its own in the same commit as this one.
--
-- Where the rest of the world is built: `docs/CODEMAP.md`, `docs/SPLIT.md` §6.

local RS = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local GameConfig = require(RS.Modules.GameConfig)

local ZoneKit = require(script.Parent.ZoneKit)
local VillageKit = require(script.Parent.VillageKit)
local ZoneGate = require(script.Parent.ZoneGate)

local newPart, addLight = ZoneKit.newPart, ZoneKit.addLight
local pulseForever, vivid = ZoneKit.pulseForever, ZoneKit.vivid

-- The Colosseum carries its own stamp. Bumping BUILD_VERSION drops all 21 zones and rebuilds
-- ~60,000 parts, which takes long enough that Studio regularly loses the connection partway (see
-- the half-built-zone guard in Build). The arena is ~900 parts, it is reached only by teleport,
-- and it has already had to move once -- so it gets a stamp of its own and is rebuilt alone.
local ARENA_VERSION = 2

-- ===== BOSS EVENT ARENA =====
-- A round sand pit with a raised dais in the middle, ringed by a stepped stand, torch pylons and
-- banners. It sits straight through the gate at the Forest spawn (GameConfig.EventArena.centre) and
-- is reached no other way, which is why it can be this far off the zone strip and cost nothing.
--
-- Everything is laid out from the centre outward by angle, so the whole thing is four loops rather
-- than a hand-placed floor plan -- and it stays perfectly circular at any radius.
-- ---- COLOSSEUM DRESSING HELPERS. They live here rather than up with the shared soft-prop
-- vocabulary because nothing else in the world is a circular amphitheatre: every one of them is
-- stated in the arena's own polar terms (an angle and a radius out from one centre).

-- Generated hero props are harvested into ServerStorage.ColosseumMeshes and cloned from there.
-- NIL IS A VALID ANSWER. A mesh that was never generated, or a folder nobody made, has to cost
-- the build exactly nothing -- an arena with no statues must come out as complete as one with
-- them, rather than stopping halfway through the arcade with an index error.
local function coloMesh(key)
	local folder = ServerStorage:FindFirstChild("ColosseumMeshes")
	local src = folder and folder:FindFirstChild(key)
	return src and src:Clone() or nil
end

-- One flat disc of the arena floor. Every ring of the floor pattern is one of these laid over a
-- slightly larger one, so a "ring" costs two parts and can never come out off-centre.
--
-- THE ONLY THING KEEPING THEM APART IS `top`. Each disc is grown DOWNWARD from its own top face
-- to a common buried bottom at y = -0.6, so two discs never share a horizontal plane and the
-- depth buffer is never asked to choose between them. Coplanar discs on this exact floor are
-- what produced the shimmer the raked rings were rewritten to cure; this is that fix, generalised.
local function coloDisc(model, name, centre, radius, top, colour, material)
	local thickness = top + 0.6
	return newPart({
		Name = name, Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thickness, radius * 2, radius * 2),
		Orientation = Vector3.new(0, 0, 90),
		Position = centre + Vector3.new(0, top - thickness / 2, 0),
		Color = colour, Material = material or Enum.Material.Sand,
		CanCollide = false, CastShadow = false, Parent = model,
	})
end

local function buildEventArena(parent)
	local cfg = GameConfig.EventArena
	local centre = cfg.centre
	local R = cfg.radius
	local accent = vivid(cfg.accentColor)
	local sand = cfg.groundColor
	local stone = Color3.fromRGB(206, 194, 172)
	local stoneDark = Color3.fromRGB(148, 136, 116)
	local stoneLite = Color3.fromRGB(238, 230, 212)

	-- ---- THE STONE LADDER. The arena read as a grey blockout for one reason above all others:
	-- every ring of it was cut from the same two tones in the same material, so a bowl three
	-- storeys deep came back to the eye as one flat value. Four tones and four materials, warmest
	-- and palest at the sand and cooling as it climbs, is what lets the tiers read as separate
	-- rings of masonry from outside the building as well as from the middle of it.
	local TIER_TONE = {
		Color3.fromRGB(240, 226, 196),
		Color3.fromRGB(214, 198, 170),
		Color3.fromRGB(182, 172, 158),
		Color3.fromRGB(150, 142, 134),
	}
	local TIER_MAT = {
		Enum.Material.Sandstone,
		Enum.Material.Concrete,
		Enum.Material.Slate,
		Enum.Material.Marble,
	}
	-- the ink the whole building is drawn with. Every lip, plinth, band and cornice is this one
	-- colour, and a dark rim on each horizontal is the single thing that turns a stack of pale
	-- boxes into something that looks drawn rather than merely modelled.
	local ink = Color3.fromRGB(72, 60, 52)
	local trim = Color3.fromRGB(112, 96, 82)
	-- the cold half of the bunting. One accent repeated 60 times is wallpaper; two alternating
	-- ones is a decorated building.
	local accent2 = Color3.fromRGB(96, 188, 232)
	local sandLite = sand:Lerp(Color3.new(1, 1, 1), 0.22)
	local sandDark = sand:Lerp(Color3.new(0, 0, 0), 0.30)

	local model = Instance.new("Model")
	model.Name = "EventArena"
	model.Parent = parent

	-- ---- The ground. Everything here stands on ONE disc, and it has to reach past the outermost
	-- thing built on it: the stand's third tier sits at radius R + 54 and the return gate at R + 8.
	-- Sized to the pit alone first time round, both of those hung over the void -- and a player who
	-- walked toward the way home simply stopped at the sand's edge with the gate out of reach.
	--
	-- R + 92 was sized for the four seating tiers and the return gate. The outer arcade stands at
	-- tierRadius[TIERS] + 26 = R + 93 and the towers 4 further out again, so at the old figure the
	-- entire exterior wall of the building was hanging over the edge of its own island with nothing
	-- under it. Kept in step with the arcade rather than written out twice: the arcade radius is
	-- derived from tierRadius further down and both come from the same three constants.
	local GROUND_R = R + 132
	local ground = newPart({ Name = "ArenaGround", Shape = Enum.PartType.Cylinder, Size = Vector3.new(8, GROUND_R * 2, GROUND_R * 2),
		Orientation = Vector3.new(0, 0, 90), Position = centre + Vector3.new(0, -4, 0),
		Color = stoneDark, Material = Enum.Material.Slate, Parent = model })
	model.PrimaryPart = ground
	newPart({ Name = "ArenaGroundTrim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, GROUND_R * 2 + 8, GROUND_R * 2 + 8),
		Orientation = Vector3.new(0, 0, 90), Position = centre + Vector3.new(0, -0.6, 0),
		Color = accent, Material = Enum.Material.Neon, Transparency = 0.5, CanCollide = false, Parent = model })

	-- the pit itself: a shallow disc of sand laid on the ground, so the fighting floor reads as a
	-- different surface from the concourse the stand sits on
	local floor = newPart({ Name = "ArenaFloor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, R * 2, R * 2),
		Orientation = Vector3.new(0, 0, 90), Position = centre + Vector3.new(0, 0.6, 0),
		Color = sand, Material = Enum.Material.Sand, Parent = model })

	-- ---- THE FLOOR PATTERN. One flat disc of sand is what a blockout looks like; three raked
	-- rings of almost the same colour on top of it is what one looks like from further away. Read
	-- from the middle outward it is now a marked-out fighting floor: the apron round the dais, a
	-- painted ring line, the combat circle, a kerb, and a darker packed track round the outside
	-- where nobody fights and everything has been worn or dropped.
	--
	-- ALL THREE RAKES STOOD AT THE SAME HEIGHT once -- y = 1.5, thickness 0.4 -- so they were three
	-- exactly coplanar discs of different colours fighting over 59,000 square studs on the game's
	-- showpiece arena. coloDisc is the general fix: every disc grows down to one buried bottom from
	-- its own unique top face, so no two of them can ever share a plane again.
	local FLOOR_RINGS = {
		{ r = R - 1,  top = 2.00, c = sandDark, m = Enum.Material.Concrete },  -- the outer track
		{ r = R - 26, top = 2.10, c = accent,   m = Enum.Material.Slate },     -- its painted kerb
		{ r = R - 32, top = 2.20, c = sandLite, m = Enum.Material.Sand },      -- the combat circle
		{ r = 108,    top = 2.30, c = accent,   m = Enum.Material.Slate },     -- inner ring line
		{ r = 102,    top = 2.40, c = sand,     m = Enum.Material.Sand },
		{ r = 80,     top = 2.50, c = sandDark, m = Enum.Material.Concrete },  -- the dais apron
	}
	for i, ring in ipairs(FLOOR_RINGS) do
		coloDisc(model, "ArenaFloorRing" .. i, centre, ring.r, ring.top, ring.c, ring.m)
	end

	-- radial dividing lines across the track, long and short by turns, so the pattern has a
	-- direction as well as a centre. They stop short of the ring line at r = 108: the middle of
	-- the pit is where a 124-stud boss lands and it stays plain on purpose.
	for i = 0, 23 do
		local a = i * math.pi * 2 / 24
		local long = (i % 2 == 0)
		local len = long and 72 or 38
		newPart({ Name = "ArenaFloorSpoke", Size = Vector3.new(long and 4.5 or 3, 0.7, len),
			CFrame = CFrame.new(centre + Vector3.new(0, 2.55, 0)) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -(R - 30 - len / 2)),
			Color = sandDark, Material = Enum.Material.Concrete, CanCollide = false, CastShadow = false, Parent = model })
	end

	-- ---- WEAR. Cracks running in from the rim and chips of the stand's own stone lying where they
	-- fell. Both are kept out on the track: rubble underfoot in the middle is noise in the one
	-- place the eye has to stay clear, and it is also where the players a giant is chasing run.
	-- The cracks are 2 studs thick and sunk to y = 1, so they read as splits in the floor rather
	-- than as decals floating a fraction above it.
	for i = 0, 17 do
		local a = (i + 0.5) * math.pi * 2 / 18 + math.rad((i % 5) * 3)
		local len = 26 + (i % 4) * 11
		newPart({ Name = "ArenaCrack", Size = Vector3.new(1.6 + (i % 3) * 0.7, 2, len),
			CFrame = CFrame.new(centre + Vector3.new(0, 2, 0)) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -(R - 6 - len / 2)),
			Color = sandDark:Lerp(Color3.new(0, 0, 0), 0.4), Material = Enum.Material.Slate,
			CanCollide = false, CastShadow = false, Parent = model })
	end
	for i = 0, 21 do
		local a = (i * 0.61) * math.pi * 2
		local rr = R - 8 - (i % 6) * 9
		local s = 3.4 + (i % 4) * 1.8
		newPart({ Name = "ArenaChip", Size = Vector3.new(s * 1.4, s * 0.7, s),
			CFrame = CFrame.new(centre + Vector3.new(0, 1.8 + s * 0.35, 0)) * CFrame.Angles(0, a, 0)
				* CFrame.new(0, 0, -rr) * CFrame.Angles(0, i * 0.9, 0),
			Color = (i % 3 == 0) and stoneLite or stone, Material = Enum.Material.Slate,
			CanCollide = false, CastShadow = false, Parent = model })
	end

	-- ---- the dais the boss stands on
	newPart({ Name = "ArenaDaisBase", Shape = Enum.PartType.Cylinder, Size = Vector3.new(5, 150, 150),
		Orientation = Vector3.new(0, 0, 90), Position = centre + Vector3.new(0, 4, 0),
		Color = stoneDark, Material = Enum.Material.Slate, Parent = model })
	newPart({ Name = "ArenaDais", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 132, 132),
		Orientation = Vector3.new(0, 0, 90), Position = centre + Vector3.new(0, 7.5, 0),
		Color = stone, Material = Enum.Material.Slate, Parent = model })
	local glowRing = newPart({ Name = "ArenaDaisGlow", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 140, 140),
		Orientation = Vector3.new(0, 0, 90), Position = centre + Vector3.new(0, 6.7, 0),
		Color = accent, Material = Enum.Material.Neon, Transparency = 0.35, CanCollide = false, CastShadow = false, Parent = model })
	addLight(glowRing, accent, 90, 2.4)
	pulseForever(glowRing, 0.62, 3.2)

	-- sigils burned into the dais, alternating long and short so the ring reads as writing
	for i = 1, 16 do
		local a = (i - 1) * math.pi / 8
		newPart({ Name = "ArenaSigil", Size = Vector3.new(5, 0.5, i % 2 == 0 and 22 or 12),
			CFrame = CFrame.new(centre + Vector3.new(0, 9.1, 0)) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -52),
			Color = accent, Material = Enum.Material.Neon, Transparency = 0.25, CanCollide = false, CastShadow = false, Parent = model })
	end

	-- ---- the stand: FOUR stepped tiers of seating around the pit, broken by the entrance.
	-- Blocks are placed at `Angles(0, a, 0) * (0, 0, -rr)`, so a = 0 IS the gate direction (-Z) and
	-- the gap is the wrapped angular distance from zero. Every tier has to open, not just the inner
	-- ones: the gate's own columns stand in the rim and an unbroken ring would bury them.
	--
	-- FOUR rings rather than three, each with its own tone and its own material off the ladder
	-- above. Three identical grey steps read as a kerb around a pit; four that visibly change
	-- colour as they climb read as an amphitheatre, and they do it from OUTSIDE the building too,
	-- which is the half that was missing. The radii and tops are published into two arrays because
	-- the crowd, the outer arcade and the aisles all have to land exactly on them -- every one of
	-- those was a hand-copied magic number before, and they went stale the moment a tier moved.
	local ENTRY_HALF = math.rad(34)
	local TIERS = 4
	local tierRadius, tierTop = {}, {}
	for tier = 1, TIERS do
		tierRadius[tier] = R + 13 + (tier - 1) * 18
		tierTop[tier] = 7 + (tier - 1) * 11
	end
	for tier = 1, TIERS do
		local rr = tierRadius[tier]
		local h = tierTop[tier] + 4
		local tone = TIER_TONE[tier]
		for i = 0, 47 do
			local a = i * math.pi * 2 / 48
			local fromGate = math.abs(((a + math.pi) % (math.pi * 2)) - math.pi)
			if fromGate >= ENTRY_HALF then
				-- six aisles cut straight up the bowl. They cost nothing but a colour: the steps are
				-- already there, and a darker stair run climbing all four rings is what stops the
				-- seating being one undifferentiated band of stone all the way round.
				local aisle = (i % 8 == 4)
				local block = newPart({ Name = "StandBlock", Size = Vector3.new(30, h, 22),
					CFrame = CFrame.new(centre + Vector3.new(0, h / 2 - 4, 0)) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -rr),
					Color = aisle and trim or ((i % 2 == 0) and tone or tone:Lerp(Color3.new(1, 1, 1), 0.12)),
					Material = aisle and Enum.Material.Cobblestone or TIER_MAT[tier], Parent = model })
				-- the ink lip. It is the tread a player actually stands on AND it is the outline that
				-- separates one ring of seats from the next at any distance -- the same dark rim that
				-- makes every other shape in this game read as drawn rather than as geometry.
				newPart({ Name = "StandLip", Size = Vector3.new(31, 1.8, 23.4),
					CFrame = block.CFrame * CFrame.new(0, h / 2, 0),
					Color = ink, Material = Enum.Material.Slate, CanCollide = false, Parent = model })
			end
		end
	end

	-- ===== THE OUTER ARCADE: WHAT THE BUILDING LOOKS LIKE FROM OUTSIDE =====
	--
	-- Everything above this point is the INSIDE of the bowl. From the approach -- which is how every
	-- player first meets the place, walking at it through the portal -- the arena was the outer face
	-- of the top tier: one unbroken ring of identical pale slabs, 48 of them, all the same height.
	-- That is the row of grey rectangles in the report, and no amount of work on the seating touches
	-- it, because the seating is not what you are looking at.
	--
	-- A real amphitheatre's exterior is an ARCADE: piers carrying arches, in a repeating order, with
	-- a cornice over it. Three things make that read at this scale and all three are cheap:
	--
	--   * a PIER-ARCH-PIER rhythm, so the wall has holes in it and the eye can measure its depth;
	--   * alternating BAY HEIGHTS on a period that does not divide the bay count, so the skyline is
	--     never a straight line and never an obvious repeat;
	--   * a continuous dark CORNICE over the whole thing, which is the outline rule again -- the one
	--     horizontal that turns a stack of pale boxes into a drawn building.
	--
	-- Radius is taken off `tierRadius[TIERS]`, not written out: the arcade is the skin on the
	-- outermost tier and a hand-copied number goes stale the moment a tier moves.
	local BAYS = 32
	local arcadeR = tierRadius[TIERS] + 26
	-- A SKIRT OF STEPS from the arcade's foot out to the rim. Without it the building ends on a
	-- vertical drop into the void and reads as a model standing on a plate; three shallow rings
	-- stepping down give it a base, and they are what the approach actually walks up.
	for s = 1, 3 do
		coloDisc(model, "ArenaSkirt", centre, arcadeR + 8 + (3 - s) * 11, -1 + s * 1.6,
			(s % 2 == 0) and stoneDark or trim, Enum.Material.Slate)
	end
	local bayStep = math.pi * 2 / BAYS
	for i = 0, BAYS - 1 do
		local a = i * bayStep
		-- the gate mouth stays open, same rule and the same constant the stands and the pylons use
		if math.abs(((a + math.pi) % (math.pi * 2)) - math.pi) < ENTRY_HALF then
			continue
		end
		local at = CFrame.new(centre) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -arcadeR)
		-- 3 does not divide 32, so the tall bays walk round the ring instead of landing in the same
		-- place every time -- 32 bays of one height is wallpaper however well each one is modelled
		local tall = (i % 3 == 0)
		local H = tall and 74 or 58
		local pierW = 13
		local bayW = 2 * math.pi * arcadeR / BAYS

		-- THE PIER. Plinth, shaft, capital -- three parts, each wider or narrower than the one below,
		-- because a column that is one box from floor to roof reads as a post and a column with a
		-- foot and a head reads as masonry.
		newPart({ Name = "ArcadePlinth", Size = Vector3.new(pierW + 7, 6, 21),
			CFrame = at * CFrame.new(0, -1, 0), Color = ink, Material = Enum.Material.Slate, Parent = model })
		newPart({ Name = "ArcadePier", Size = Vector3.new(pierW, H, 17),
			CFrame = at * CFrame.new(0, 2 + H / 2, 0), Color = TIER_TONE[2],
			Material = Enum.Material.Sandstone, Parent = model })
		-- a fluting stripe down the front, proud of the shaft so it is never coplanar with it
		newPart({ Name = "ArcadeFlute", Size = Vector3.new(4, H - 12, 2),
			CFrame = at * CFrame.new(0, 2 + H / 2, -9.4), Color = stoneLite,
			Material = Enum.Material.Sandstone, CanCollide = false, CastShadow = false, Parent = model })
		newPart({ Name = "ArcadeCapital", Size = Vector3.new(pierW + 6, 6, 21),
			CFrame = at * CFrame.new(0, 4 + H, 0), Color = trim, Material = Enum.Material.Slate,
			CanCollide = false, Parent = model })

		-- THE ARCH between this pier and the next. Roblox has no arc primitive, so it is five short
		-- voussoirs swung across the opening on their own angles -- which at this size reads as a
		-- round-headed arch and, unlike a wedge, cannot land somewhere unintended when the whole bay
		-- is also yawed. The middle one is the keystone and it is a different tone on purpose: it is
		-- the only thing that says "arch" rather than "hole" at a hundred studs.
		local midA = a + bayStep / 2
		local springY = 2 + H * 0.66
		local rise = H * 0.2
		local VOUSSOIRS = 5
		for v = 1, VOUSSOIRS do
			local t = (v - 0.5) / VOUSSOIRS               -- 0..1 across the opening
			local off = (t - 0.5) * (bayW - pierW)        -- sideways, in studs along the chord
			local lift = math.sin(t * math.pi) * rise     -- a half sine IS the arch curve
			local tilt = math.cos(t * math.pi) * 0.5      -- each stone rolled to sit on the curve
			local key = (v == (VOUSSOIRS + 1) / 2)
			newPart({ Name = key and "ArcadeKeystone" or "ArcadeVoussoir",
				Size = Vector3.new((bayW - pierW) / VOUSSOIRS + 2, key and 15 or 11, 17),
				CFrame = CFrame.new(centre) * CFrame.Angles(0, midA, 0)
					* CFrame.new(off, springY + lift, -arcadeR) * CFrame.Angles(0, 0, tilt),
				Color = key and stoneLite or TIER_TONE[2]:Lerp(Color3.new(1, 1, 1), 0.1),
				Material = Enum.Material.Sandstone, CanCollide = false, Parent = model })
		end
		-- the dark void behind the opening. Without it you see straight through the arcade to the
		-- seating behind, and an arch you can see daylight through reads as a gap in a fence.
		newPart({ Name = "ArcadeShadow", Size = Vector3.new(bayW - pierW, springY - 4, 3),
			CFrame = CFrame.new(centre) * CFrame.Angles(0, midA, 0) * CFrame.new(0, 2 + (springY - 4) / 2, -arcadeR + 7),
			Color = ink, Material = Enum.Material.Slate, CanCollide = false, CastShadow = false, Parent = model })

		-- THE CORNICE. One dark band running the whole ring at the pier head, and a paler attic course
		-- sitting on it. This is the single piece that ties 32 separate bays into one building.
		newPart({ Name = "ArcadeCornice", Size = Vector3.new(bayW + 3, 5, 24),
			CFrame = CFrame.new(centre) * CFrame.Angles(0, midA, 0) * CFrame.new(0, 9 + H, -arcadeR),
			Color = ink, Material = Enum.Material.Slate, CanCollide = false, Parent = model })
		newPart({ Name = "ArcadeAttic", Size = Vector3.new(bayW + 1, 9, 18),
			CFrame = CFrame.new(centre) * CFrame.Angles(0, midA, 0) * CFrame.new(0, 16 + H, -arcadeR),
			Color = TIER_TONE[4], Material = Enum.Material.Marble, CanCollide = false, Parent = model })
		-- merlons on the attic, every other bay, so the roofline is toothed rather than ruled
		if i % 2 == 0 then
			newPart({ Name = "ArcadeMerlon", Size = Vector3.new(10, 9, 18),
				CFrame = CFrame.new(centre) * CFrame.Angles(0, midA, 0) * CFrame.new(0, 25 + H, -arcadeR),
				Color = TIER_TONE[4], Material = Enum.Material.Marble, CanCollide = false, Parent = model })
		end
	end

	-- ---- SIX CORNER TOWERS, taller than the arcade, each with a banner and a lit finial. The
	-- arcade above gives the wall texture but its skyline is still a band of near-constant height,
	-- and a circular building with a constant skyline reads as a drum. Six verticals break it, and
	-- six is chosen against the twelve pylons and the 32 bays so nothing lines up into a pattern.
	for i = 0, 5 do
		local a = (i + 0.5) * math.pi / 3
		if math.abs(((a + math.pi) % (math.pi * 2)) - math.pi) < ENTRY_HALF then
			continue
		end
		local at = CFrame.new(centre) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -(arcadeR + 4))
		local cloth = (i % 2 == 0) and accent or accent2
		newPart({ Name = "ArenaTowerBase", Size = Vector3.new(38, 8, 34),
			CFrame = at * CFrame.new(0, 0, 0), Color = ink, Material = Enum.Material.Slate, Parent = model })
		newPart({ Name = "ArenaTower", Size = Vector3.new(30, 106, 26),
			CFrame = at * CFrame.new(0, 55, 0), Color = TIER_TONE[3],
			Material = Enum.Material.Sandstone, Parent = model })
		-- two string courses, both proud of the shaft, so a 106-stud tower has storeys
		for _, y in ipairs({ 38, 74 }) do
			newPart({ Name = "ArenaTowerBand", Size = Vector3.new(34, 5, 30),
				CFrame = at * CFrame.new(0, y, 0), Color = trim, Material = Enum.Material.Slate,
				CanCollide = false, Parent = model })
		end
		-- a lit window slot on each storey -- the cheapest way to say "there is an inside"
		for _, y in ipairs({ 52, 88 }) do
			newPart({ Name = "ArenaTowerWindow", Size = Vector3.new(8, 16, 3),
				CFrame = at * CFrame.new(0, y, -14), Color = accent, Material = Enum.Material.Neon,
				Transparency = 0.25, CanCollide = false, CastShadow = false, Parent = model })
		end
		newPart({ Name = "ArenaTowerCap", Size = Vector3.new(38, 7, 34),
			CFrame = at * CFrame.new(0, 110, 0), Color = ink, Material = Enum.Material.Slate,
			CanCollide = false, Parent = model })
		-- the roof: two shrinking blocks rather than a cone, for the reason written on the idols'
		-- ears -- a stack of tapering boxes reads as a pointed roof from every angle and a Wedge
		-- does not survive being yawed
		newPart({ Name = "ArenaTowerRoof", Size = Vector3.new(28, 16, 25),
			CFrame = at * CFrame.new(0, 121, 0), Color = cloth, Material = Enum.Material.Slate,
			CanCollide = false, Parent = model })
		newPart({ Name = "ArenaTowerSpire", Size = Vector3.new(14, 18, 13),
			CFrame = at * CFrame.new(0, 137, 0), Color = cloth:Lerp(ink, 0.35),
			Material = Enum.Material.Slate, CanCollide = false, Parent = model })
		local finial = newPart({ Name = "ArenaTowerFinial", Size = Vector3.new(11, 11, 11),
			CFrame = at * CFrame.new(0, 150, 0), Color = accent, Material = Enum.Material.Neon,
			CanCollide = false, CastShadow = false, Parent = model })
		local fm = Instance.new("SpecialMesh")
		fm.MeshType = Enum.MeshType.Sphere
		fm.Parent = finial
		addLight(finial, accent, 84, 3)
		pulseForever(finial, 0.34, 2.2 + (i % 3) * 0.5)
		-- a long banner down the tower's face, which is what gives it a colour at range
		newPart({ Name = "ArenaTowerBanner", Size = Vector3.new(20, 62, 1.4),
			CFrame = at * CFrame.new(0, 66, -14.4), Color = cloth, Material = Enum.Material.Fabric,
			CanCollide = false, Parent = model })
		newPart({ Name = "ArenaTowerBannerBar", Size = Vector3.new(24, 3, 4),
			CFrame = at * CFrame.new(0, 98, -14.4), Color = ink, Material = Enum.Material.Slate,
			CanCollide = false, CastShadow = false, Parent = model })
	end

	-- ---- BUNTING between the towers, strung round the outside at cornice height. Two colours
	-- alternating, because one accent repeated round a ring is wallpaper -- the same note the pylon
	-- banners carry. Purely decorative and non-colliding: this hangs outside the wall.
	for i = 0, 59 do
		local a = i * math.pi * 2 / 60
		if math.abs(((a + math.pi) % (math.pi * 2)) - math.pi) < ENTRY_HALF then
			continue
		end
		newPart({ Name = "ArenaBunting", Shape = Enum.PartType.Wedge, Size = Vector3.new(9, 11, 1),
			CFrame = CFrame.new(centre) * CFrame.Angles(0, a, 0)
				* CFrame.new(0, 84 + math.sin(i * 0.7) * 4, -(arcadeR + 12)) * CFrame.Angles(0, 0, math.pi),
			Color = (i % 2 == 0) and accent or accent2, Material = Enum.Material.Fabric,
			CanCollide = false, CastShadow = false, Parent = model })
	end

	-- ---- torch pylons around the rim, and a banner between every pair.
	-- The stands above open a gap of +-ENTRY_HALF around a = 0 for the gate, and the pylons have to
	-- respect the SAME gap. They did not: i = 0 planted a 62-stud slate column, its torch and its
	-- banner dead centre in the portal's mouth, so the way in was a doorway with a post in it.
	for i = 0, 11 do
		local a = i * math.pi / 6
		if math.abs(((a + math.pi) % (math.pi * 2)) - math.pi) < ENTRY_HALF then
			continue
		end
		local at = CFrame.new(centre) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -(R + 2))
		local cloth = (i % 2 == 0) and accent or accent2
		newPart({ Name = "ArenaPylonFoot", Size = Vector3.new(17, 7, 17), CFrame = at * CFrame.new(0, 0, 0),
			Color = ink, Material = Enum.Material.Slate, Parent = model })
		newPart({ Name = "ArenaPylon", Size = Vector3.new(10, 64, 10), CFrame = at * CFrame.new(0, 30, 0), Color = TIER_TONE[3], Material = Enum.Material.Sandstone, Parent = model })
		-- two bands round the shaft, both proud of it, so a 64-stud post has a middle and a top
		newPart({ Name = "ArenaPylonBand", Size = Vector3.new(13, 4, 13), CFrame = at * CFrame.new(0, 20, 0), Color = trim, Material = Enum.Material.Slate, CanCollide = false, Parent = model })
		newPart({ Name = "ArenaPylonCap", Size = Vector3.new(15, 5, 15), CFrame = at * CFrame.new(0, 61, 0), Color = ink, Material = Enum.Material.Slate, CanCollide = false, Parent = model })
		-- A NON-UNIFORM `Shape = Ball` IS DRAWN AS A SPHERE OF ITS SMALLEST AXIS. This flame was
		-- authored 12 x 15 x 12 and rendered as a 12-ball -- the taller flame shape it was asking
		-- for never once appeared. Block plus a Sphere SpecialMesh is the only way to get an
		-- ellipsoid, and it is the same fix the eggs and the boss armour needed.
		local flame = newPart({ Name = "ArenaTorch", Size = Vector3.new(13, 18, 13),
			CFrame = at * CFrame.new(0, 70, 0), Color = accent, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = model })
		local flameMesh = Instance.new("SpecialMesh")
		flameMesh.MeshType = Enum.MeshType.Sphere
		flameMesh.Parent = flame
		addLight(flame, accent, 70, 3)
		pulseForever(flame, 0.42, 1.7 + (i % 3) * 0.4)
		-- banner hanging on the pylon, facing the pit, alternating warm and cold round the ring
		newPart({ Name = "ArenaBanner", Size = Vector3.new(16, 36, 1.2), CFrame = at * CFrame.new(0, 36, 6.2), Color = cloth, Material = Enum.Material.Fabric, CanCollide = false, Parent = model })
		newPart({ Name = "ArenaBannerBar", Size = Vector3.new(19, 2.4, 3), CFrame = at * CFrame.new(0, 55, 6.2), Color = ink, Material = Enum.Material.Slate, CanCollide = false, CastShadow = false, Parent = model })
		newPart({ Name = "ArenaBannerCrest", Size = Vector3.new(9, 9, 1.4), CFrame = at * CFrame.new(0, 40, 7.1) * CFrame.Angles(0, 0, math.pi / 4), Color = stoneLite, Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = model })
		newPart({ Name = "ArenaBannerTail", Shape = Enum.PartType.Wedge, Size = Vector3.new(16, 10, 1.2),
			CFrame = at * CFrame.new(0, 13, 6.2) * CFrame.Angles(0, 0, math.pi),
			Color = cloth, Material = Enum.Material.Fabric, CanCollide = false, Parent = model })
	end

	-- ---- the countdown board. High over the dais rather than over the entrance: hung on the rim
	-- it was outside the gate and the gate's own stonework stood in front of it from every seat in
	-- the house. Above the middle it is readable from anywhere on the sand, and it clears the boss's
	-- own name plate (which tops out around y = 150 on a 124-stud rig).
	local boardAnchor = newPart({ Name = "ArenaBoard", Size = Vector3.new(4, 4, 4),
		Position = centre + Vector3.new(0, 232, 0), Transparency = 1, CanCollide = false, Parent = model })
	local board = Instance.new("BillboardGui")
	board.Name = "CountdownBoard"
	board.Size = UDim2.new(96, 0, 30, 0) -- in studs: a pixel-sized board keeps its screen size at range
	board.AlwaysOnTop = false
	board.LightInfluence = 0
	board.MaxDistance = 700
	board.Parent = boardAnchor
	local label = Instance.new("TextLabel")
	label.Name = "Countdown"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundColor3 = Color3.fromRGB(24, 18, 30)
	label.BackgroundTransparency = 0.15
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeColor3 = Color3.fromRGB(16, 12, 26)
	label.TextStrokeTransparency = 0
	label.Text = "\u{2694}\u{FE0F} COLOSSEUM"
	label.Parent = board
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = label
	local edge = Instance.new("UIStroke")
	edge.Thickness = 4
	edge.Color = accent
	edge.Parent = label
	CollectionService:AddTag(boardAnchor, "ArenaCountdown")

	-- ---- the way home. Built through the same buildPortal as every boundary gate, stood in the
	-- -Z rim facing the pit, and tagged with a target ZoneService knows how to read.
	local returnTarget = {
		key = "ReturnFromArena", name = "Back", emoji = "\u{1F3E0}",
		accentColor = Color3.fromRGB(120, 220, 140), offset = 0,
	}
	-- yaw -90, not 180. buildPortal is written with local +X pointing at the interior, and a yaw of
	-- 180 sends that to world -X -- the gate stood correctly in the rim but its steps, mat, runes
	-- and guardians all faced sideways out of the arena instead of in across the sand.
	-- `withFrame` and not setFrame/restore, for the reason written over it: a builder that throws
	-- between the two hand-written lines leaves the frame set and moves the rest of the world.
	ZoneKit.withFrame(CFrame.new(centre + Vector3.new(0, 0, -(R + 8))) * CFrame.Angles(0, math.rad(-90), 0),
		ZoneGate.buildPortal, model, 0, returnTarget, 1)

	-- ---- WHAT IT STANDS ON. Seen from anywhere but directly overhead the whole Colosseum was a
	-- coin on edge: an 8-stud disc with 600 studs of empty sky under it. Two stepped drums beneath
	-- the ground read as the rock it was cut out of, and cost two parts to say it.
	newPart({ Name = "ArenaBed", Shape = Enum.PartType.Cylinder, Size = Vector3.new(46, GROUND_R * 2 - 26, GROUND_R * 2 - 26),
		Orientation = Vector3.new(0, 0, 90), Position = centre + Vector3.new(0, -31, 0),
		Color = stoneDark, Material = Enum.Material.Slate, Parent = model })
	newPart({ Name = "ArenaBedDeep", Shape = Enum.PartType.Cylinder, Size = Vector3.new(74, GROUND_R * 2 - 100, GROUND_R * 2 - 100),
		Orientation = Vector3.new(0, 0, 90), Position = centre + Vector3.new(0, -80, 0),
		Color = stoneDark:Lerp(Color3.new(0, 0, 0), 0.32), Material = Enum.Material.Slate, Parent = model })

	-- ---- THE OUTSIDE. The stand's top step was the last thing in every direction, so from the
	-- sand the building simply stopped at head height and from outside it had no face at all. A ring
	-- of thick piers standing past the top tier gives it one, and closes the horizon behind the
	-- seats. It breaks at the entrance on the same angle the stand does -- one opening, not two.
	local OUTER_R = GROUND_R - 16
	for i = 0, 23 do
		local a = i * math.pi * 2 / 24
		local fromGate = math.abs(((a + math.pi) % (math.pi * 2)) - math.pi)
		if fromGate >= ENTRY_HALF then
			local at = CFrame.new(centre) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -OUTER_R)
			newPart({ Name = "ArenaPier", Size = Vector3.new(46, 74, 22), CFrame = at * CFrame.new(0, 33, 0),
				Color = (i % 2 == 0) and stone or stoneLite, Material = Enum.Material.Slate, Parent = model })
			newPart({ Name = "ArenaPierCap", Size = Vector3.new(54, 9, 28), CFrame = at * CFrame.new(0, 74, 0),
				Color = stoneDark, Material = Enum.Material.Slate, CanCollide = false, Parent = model })
			-- a recessed arch on the inner face, so the ring reads as an arcade rather than a fence
			newPart({ Name = "ArenaPierArch", Size = Vector3.new(24, 34, 5), CFrame = at * CFrame.new(0, 24, -10),
				Color = stoneDark, Material = Enum.Material.Slate, CanCollide = false, Parent = model })
			-- every fourth pier carries a lamp. Every pier carrying one would be nineteen more lights
			-- in a scene that already runs twelve torches and fifteen runes.
			if i % 4 == 0 then
				newPart({ Name = "ArenaPierLamp", Shape = Enum.PartType.Ball, Size = Vector3.new(11, 11, 11),
					CFrame = at * CFrame.new(0, 84, 0), Color = accent, Material = Enum.Material.Neon,
					CanCollide = false, CastShadow = false, Parent = model })
			end
		end
	end

	-- ---- THE CROWD. Two blocks each and no faces: at this scale a spectator is a colour and a
	-- silhouette, and it is the thing that turns a ring of empty steps into a full house. They sit
	-- on the two outer tiers only -- the inner step is where the pylons and banners are.
	local SKIN = { Color3.fromRGB(248, 214, 180), Color3.fromRGB(226, 176, 132), Color3.fromRGB(168, 118, 82), Color3.fromRGB(112, 78, 58) }
	for i = 0, 43 do
		local a = (i + 0.5) * math.pi * 2 / 44
		local fromGate = math.abs(((a + math.pi) % (math.pi * 2)) - math.pi)
		if fromGate >= ENTRY_HALF + math.rad(5) then
			-- alternating tiers: the third step (top y 34, radius R+54) and the second (21, R+34).
			-- Both numbers come straight out of the stand loop above -- h = 12 + (tier-1)*13 sitting
			-- at h/2 - 4, so its top face is h - 4.
			local outer = (i % 2 == 0)
			local rr = outer and (R + 54) or (R + 34)
			local top = outer and 34 or 21
			local at = CFrame.new(centre + Vector3.new(0, top, 0)) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -rr)
			newPart({ Name = "Spectator", Size = Vector3.new(7.5, 9, 5), CFrame = at * CFrame.new(0, 4.5, 0),
				Color = VillageKit.candy(i), Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
			newPart({ Name = "SpectatorHead", Size = Vector3.new(6, 6, 5), CFrame = at * CFrame.new(0, 12, 0),
				Color = SKIN[(i % #SKIN) + 1], Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
		end
	end

	-- ---- THE ENTRANCE. The gap in the stand was only ever a gap -- three tiers stopping in
	-- mid-air on either side of the way home. A tower on each shoulder makes it a gateway.
	--
	-- Nothing is built ACROSS the opening on purpose. An arch over it is the obvious next move and
	-- it is the wrong one: the portal's own frame reaches y = 166 with its name board above that,
	-- and anything spanning the towers stands in front of it. The gate is what the player is
	-- walking at; it does not share its airspace.
	for _, side in ipairs({ -1, 1 }) do
		local a = side * (ENTRY_HALF + math.rad(3.4))
		local at = CFrame.new(centre) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -(R + 36))
		newPart({ Name = "ArenaGateTower", Size = Vector3.new(42, 100, 60), CFrame = at * CFrame.new(0, 46, 0),
			Color = stone, Material = Enum.Material.Slate, Parent = model })
		newPart({ Name = "ArenaGateTowerCap", Size = Vector3.new(50, 10, 68), CFrame = at * CFrame.new(0, 100, 0),
			Color = stoneDark, Material = Enum.Material.Slate, CanCollide = false, Parent = model })
		newPart({ Name = "ArenaGateBanner", Size = Vector3.new(26, 52, 1.4), CFrame = at * CFrame.new(0, 58, -30.8),
			Color = accent, Material = Enum.Material.Fabric, CanCollide = false, Parent = model })
		newPart({ Name = "ArenaGateBannerTail", Shape = Enum.PartType.Wedge, Size = Vector3.new(26, 12, 1.4),
			CFrame = at * CFrame.new(0, 26, -30.8) * CFrame.Angles(0, 0, math.pi),
			Color = accent, Material = Enum.Material.Fabric, CanCollide = false, Parent = model })
		local bowl = newPart({ Name = "ArenaGateFlame", Shape = Enum.PartType.Ball, Size = Vector3.new(17, 20, 17),
			CFrame = at * CFrame.new(0, 112, 0), Color = accent, Material = Enum.Material.Neon,
			CanCollide = false, CastShadow = false, Parent = model })
		addLight(bowl, accent, 90, 3.2)
		pulseForever(bowl, 0.46, 2.1)
	end

	-- ---- broken columns out on the sand. Six pieces, all near the rim: the middle of the pit is
	-- where a 124-stud boss lands and where the players it lands on have to be able to run.
	for i = 0, 5 do
		local a = (i + 0.35) * math.pi * 2 / 6
		local at = CFrame.new(centre) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -(R * 0.87))
		local h = 9 + (i % 3) * 7
		newPart({ Name = "ArenaRubble", Size = Vector3.new(15, h, 15),
			CFrame = at * CFrame.new(0, h / 2 + 1.4, 0) * CFrame.Angles(0, math.rad(i * 19), 0),
			Color = stoneLite, Material = Enum.Material.Slate, Parent = model })
		newPart({ Name = "ArenaRubbleCap", Size = Vector3.new(18, 3, 18),
			CFrame = at * CFrame.new(0, h + 2.9, 0) * CFrame.Angles(0, math.rad(i * 19), 0),
			Color = stoneDark, Material = Enum.Material.Slate, CanCollide = false, Parent = model })
	end

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and not d.Anchored then d.Anchored = true end
	end
	model:SetAttribute("ArenaVersion", ARENA_VERSION)
	return model
end

-- `ARENA_VERSION` is exported because `ZoneBuilder.Build()` reads it to decide whether the arena
-- standing in the world was built by this code. It is the arena's own answer to the question
-- `BUILD_VERSION` answers for the zones, and it belongs beside the thing it stamps.
return {
	buildEventArena = buildEventArena,
	ARENA_VERSION = ARENA_VERSION,
}
