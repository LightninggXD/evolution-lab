-- WorldApron -- the ground UNDER the world, so the map reads as a solid landmass instead of
-- scenery hanging in the air.
--
-- ===== THE BUG THIS EXISTS FOR =====
--
-- `MapHorizon` states its own intent at `SINK = 15`: "Buried, so a hill's flat underside never
-- shows." It seats every horizon hill 15 studs into the ground and that is the whole guarantee.
-- But the rule only holds where there IS ground. `AT.outerX` is 812 and `AT.outerZ` is 776, and
-- `WorldShell.Floor` is 1250 x 1150 -- it stops at x 625 / z 575. Measured on the Forest zone,
-- 2026-08-28: **47 of 61 HorizonHill models stand entirely off the floor**, sunk 15 studs into
-- nothing, flat underside and all.
--
-- Nobody saw it for as long as the only camera was inside the walls, because the 180-stud wall
-- hides everything beyond it from a player on the ground. Then the Colosseum was built at
-- z 1145..1736 -- **570 studs BEYOND the map's edge** -- and `Lighting.FogEnd` is 1900, so from
-- the arena you look back at the whole outer ring side-on, in clear air, and the hills float.
--
-- ===== WHY A SLAB AND NOT A BIGGER FLOOR =====
--
-- Growing `WorldShell.Floor` is one number in `ZoneBuilder`, and it is the wrong number to touch:
-- that file's `BUILD_VERSION` guard drops all twenty-one zones and rebuilds ~105,000 parts, and
-- the floor is walkable, collidable, and the surface every ground raycast in the repo expects to
-- hit at y = 0. This is scenery. It carries its own stamp for the same reason `EventArena`,
-- `MinigameTerminals` and `ExpeditionMap` carry theirs.
--
-- EVERY PART IS `CanCollide = false` AND `CanQuery = false`. Nothing stands on it and no ray may
-- find it: `MapSettle`, `MapSolids`, `HubPlaza` and the leaderboards all drop rays looking for the
-- real ground, and a query-able slab under the floor is a second answer to that question.
--
-- ===== THE SHAPE, AND WHY IT IS CONTINUOUS ALONG X =====
--
-- `ZoneSpacing` is 1900, so a half-width of 950 makes each zone's apron meet its neighbour's
-- exactly: twenty zones become one 38,000-stud landmass rather than twenty floating tiles. The
-- taper is in Z only, which is the axis the arena looks along -- three tiers, so the underside
-- reads as a keel rather than as a table.
--
-- Z reaches 1100. The Colosseum's near edge is 1145, so the land stops 45 studs short of it and
-- the arena reads as an island just off the coast rather than as a tile in a void.

local WorldApron = {}

local APRON_VERSION = 3

local FOLDER_NAME = "WorldApron"

-- Half a stud INTO the floor slab (its underside is y = -4), never flush with it: two coplanar
-- faces z-fight, and the fight is only visible at the distance this whole file exists to fix.
-- ===== THE TOP TIER IS GROUND, NOT ROCK, AND THAT IS THE WHOLE READ =====
--
-- The first build made every tier one darkened rock colour, and from the arena it read as a flat
-- grey SHELF -- a table the mountains were standing on. Ground does not do that: it continues,
-- and then it breaks off. So the top tier wears the zone's own floor colour AND its material
-- (Forest is Grass, MirrorUniverse is Glass -- both read off the part, neither typed here), and
-- only the tiers under it are rock.
--
-- -0.5 rather than -3.5: the floor slab spans y -4..0, so a shelf topping out half a stud under
-- its top face is hidden wherever the two overlap and leaves a half-stud lip at the floor's edge,
-- which is nothing at this distance. -3.5 left a three-and-a-half stud step all the way round.
local SHELF_TOP = -0.5

local SHELF_BOTTOM = -14   -- clears MapHorizon's SINK of 15: a hill's foot ends up in the rock

local HALF_X = 950   -- ZoneSpacing / 2: adjacent aprons meet, so the strip has no seams

-- ===== 2026-08-28 [34.45] THE SILENT 2048 CLAMP =====
--
-- She looked again the next day: "sad je bolje ali ovde i dalje malo lebdi, ne treba da ih kivis,
-- mogu i ravni da budu samo da ne lebde" -- better, but here it STILL floats a bit; you don't
-- need to TILT them, they can be flat, just so long as they don't float. So: no `CFrame.Angles`
-- anywhere in this file, ever. The only allowed move is bringing ground up under the thing.
--
-- And v2 was short. It asked for a shelf 2200 studs deep (halfZ 1100, doubled). Roblox caps
-- `BasePart.Size` at 2048 per axis and does it SILENTLY -- no error, no warning, `Size.Z` simply
-- comes back 2048. So the shelf and the first tier stopped at z +-1024, seventy-six studs short
-- of the 1100 this file believed it had, on both sides. Measured 2026-08-28: 30 `HorizonHill`
-- mesh parts and 2 `PassShoulder` parts hang past that lip, worst 89 studs, flat undersides at
-- y = -15 in open air. That is the "malo" in "malo lebdi".
--
-- Anything deeper than this cap has to be laid down as several parts. Never assume the Size you
-- asked for is the Size you got.
local MAX_SPAN = 2000   -- 48 studs under the 2048 hard cap, so no layer is ever clamped again

-- ===== WHY THE KEEL IS LONGER TO THE SOUTH =====
--
-- North (z+) is the Colosseum's side, and 1100 is a deliberate number v2 chose so the land stops
-- short of the arena and the arena reads as an island just off the coast. Left exactly as it was.
-- South (z-) faces nothing at all, and the horizon ring reaches z = -1113 there, so the keel just
-- runs on until it is under the hills. Asymmetric on purpose: land is not a tile.
local SOUTH_EXTRA = 60

-- ===== AND WHY THE TWO OUTER ENDS GET A CAP =====
--
-- HALF_X is ZoneSpacing/2 so every apron meets its neighbour -- but the first and last zone have
-- no neighbour on one side. Forest is westernmost and its horizon hills reach x = -1186, which is
-- 236 studs past the apron's west edge at -950; those were the worst floaters in the whole sweep.
-- The cap is its own part rather than a wider slab because 1900 + 300 = 2200 is over the clamp.
-- The east end gets the same cap even though nothing hangs off it: a landmass that tapers at one
-- end and is sliced flat at the other looks like a bug, and eight parts is nothing.
local END_CAP = 300

-- tier = { half-depth in Z northward (south gets SOUTH_EXTRA more), the Y its underside reaches }
local TIERS = {
	{ halfZ = 1100, bottom = -170 },
	{ halfZ = 1000, bottom = -260 },
	{ halfZ =  860, bottom = -330 },
}

-- The rock is the zone's own floor colour taken down hard. Reading it off the floor rather than
-- typing a palette here is what keeps the Desert's apron sand and the Void's black without this
-- file knowing either fact.
local DARKEN = 0.42

local function darken(c)
	return Color3.new(c.R * DARKEN, c.G * DARKEN, c.B * DARKEN)
end

local function slab(model, name, cx, cz, sx, sy, sz, cy, colour, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = material or Enum.Material.Slate
	p.Color = colour
	p.Size = Vector3.new(sx, sy, sz)
	p.Position = Vector3.new(cx, cy, cz)
	p.Parent = model
	return p
end

-- 2026-08-28 [34.45] One horizontal layer, laid as however many parts it takes to reach from
-- zSouth to zNorth without any of them exceeding MAX_SPAN. Segments abut exactly -- they share a
-- plane but face opposite ways, so there is nothing for the depth buffer to fight over, unlike
-- the coplanar TOP faces that SHELF_TOP = -0.5 exists to avoid.
local function band(model, name, cx, sx, yTop, yBottom, zNorth, zSouth, colour, material)
	local depth = zNorth - zSouth
	local n = math.ceil(depth / MAX_SPAN)
	local seg = depth / n
	local height = yTop - yBottom
	for i = 1, n do
		local z0 = zSouth + seg * (i - 1)
		slab(model, name, cx, z0 + seg * 0.5,
			sx, height, seg,
			yTop - height * 0.5, colour, material)
	end
	return n
end

function WorldApron.Build()
	local shell = workspace:FindFirstChild("WorldShell")
	if not shell then
		warn("[WorldApron] no WorldShell -- the apron is skipped (ZoneBuilder has not run)")
		return nil
	end

	local previous = workspace:FindFirstChild(FOLDER_NAME)
	if previous then
		if previous:GetAttribute("ApronVersion") == APRON_VERSION then
			return previous
		end
		previous:Destroy()
	end

	local model = Instance.new("Model")
	model.Name = FOLDER_NAME
	-- the same pin ZoneBuilder puts on the shell: a landmass that streams out at range is the one
	-- thing worse than no landmass, because it pops.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model:SetAttribute("ApronVersion", APRON_VERSION)

	-- One column of ground -- grass shelf on top wearing the zone's own floor colour AND material,
	-- three rock tiers under it. Used for the zone strips and for the two end caps alike, so an
	-- end cap can never drift out of step with the strip it continues.
	local function column(cx, sx, colour, material)
		local n = band(model, "ApronShelf", cx, sx, SHELF_TOP, SHELF_BOTTOM,
			TIERS[1].halfZ, -(TIERS[1].halfZ + SOUTH_EXTRA), colour, material)
		local rock = darken(colour)
		local top = SHELF_BOTTOM
		for i, tier in ipairs(TIERS) do
			n += band(model, "ApronTier" .. i, cx, sx, top, tier.bottom,
				tier.halfZ, -(tier.halfZ + SOUTH_EXTRA), rock)
			top = tier.bottom
		end
		return n
	end

	local floors, parts = 0, 0
	local west, east
	for _, floor in ipairs(shell:GetChildren()) do
		if floor:IsA("BasePart") and floor.Name == "Floor" then
			floors += 1
			parts += column(floor.Position.X, HALF_X * 2, floor.Color, floor.Material)
			if not west or floor.Position.X < west.Position.X then west = floor end
			if not east or floor.Position.X > east.Position.X then east = floor end
		end
	end

	-- The open ends. Each wears its own end zone's ground, read off the part exactly as the strips
	-- are, so the cap is the same landmass and not a grey lid stuck on it.
	if west then
		parts += column(west.Position.X - HALF_X - END_CAP * 0.5, END_CAP, west.Color, west.Material)
	end
	if east then
		parts += column(east.Position.X + HALF_X + END_CAP * 0.5, END_CAP, east.Color, east.Material)
	end

	model.Parent = workspace

	print(("[WorldApron] built v%d: %d parts under %d zone floors, x %d..%d, z %d..%d, keel y %d")
		:format(APRON_VERSION, parts, floors,
			(west and west.Position.X or 0) - HALF_X - END_CAP,
			(east and east.Position.X or 0) + HALF_X + END_CAP,
			-(TIERS[1].halfZ + SOUTH_EXTRA), TIERS[1].halfZ, TIERS[#TIERS].bottom))

	return model
end

function WorldApron.Init()
	WorldApron.Build()
end

return WorldApron
