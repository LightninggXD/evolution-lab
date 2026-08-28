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

local APRON_VERSION = 2

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

-- tier = { half-depth in Z, the Y its underside reaches }
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

	local floors, parts = 0, 0
	for _, floor in ipairs(shell:GetChildren()) do
		if floor:IsA("BasePart") and floor.Name == "Floor" then
			floors += 1
			local cx = floor.Position.X
			local colour = darken(floor.Color)
			local shelfH = SHELF_TOP - SHELF_BOTTOM
			slab(model, "ApronShelf", cx, 0,
				HALF_X * 2, shelfH, TIERS[1].halfZ * 2,
				SHELF_TOP - shelfH * 0.5, floor.Color, floor.Material)
			parts += 1

			local top = SHELF_BOTTOM
			for i, tier in ipairs(TIERS) do
				local height = top - tier.bottom
				slab(model, "ApronTier" .. i, cx, 0,
					HALF_X * 2, height, tier.halfZ * 2,
					top - height * 0.5, colour)
				parts += 1
				top = tier.bottom
			end
		end
	end

	model.Parent = workspace

	print(("[WorldApron] built v%d: %d parts under %d zone floors, x half %d, z reach %d, keel y %d")
		:format(APRON_VERSION, parts, floors, HALF_X, TIERS[1].halfZ, TIERS[#TIERS].bottom))

	return model
end

function WorldApron.Init()
	WorldApron.Build()
end

return WorldApron
