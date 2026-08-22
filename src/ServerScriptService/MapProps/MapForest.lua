-- MapProps/MapForest -- the wood, planted with the map's own trees. Since 30.23 it is the whole
-- platform rather than two bands behind the village.
--
-- Split out of `ForestMapService` in 31.4. It is a self-contained job -- take a stock of trees off
-- the map, stand clones of them on the ground -- and it grew a second band (the side pockets) the
-- day it was written, which is exactly the shape that should not live inside a 500-line service.
--
-- ===== 30.23: THE OWNER ASKED FOR THE AMAZON =====
-- *"puno drveca po celoj mapi, znaci drveca ko u amazonu treba prekopiraj samo drvece od modela
-- kopiraj i pastuj po celoj mapi i onda po toj sumi trebaju biti creatures"*, with a drawing of
-- four quadrants of wood around a cross of roads. What was here before was a back wall, two flanks
-- and sixteen clumps -- 104 trees on the 1.45 build -- all of it south and beside the village, with
-- the two north quadrants left as bare green platform.
--
-- So the two hand-tuned bands are gone and the planter is a SCATTER OVER THE WHOLE PLATFORM with a
-- keep-out list. That inverts the question it answers: it used to be "where does wood go", and the
-- answer had to be re-authored every time the map moved. It is now "what is NOT wood" -- the
-- village, the arrival plaza, the entrance funnel, the boss's clearing, every road (spurs
-- included), and every camp -- and each of those is asked of the module that owns it rather than
-- typed here. `JungleLayout` answers for the roads and the camps, `ForestMapService`'s own spec for
-- the village and the funnel.
--
-- WHY THE TREES ARE CLONED FROM THE MAP AND NOT GENERATED. Behind the village is bare platform, and
-- 74 creatures standing on bare platform is the "random shapes on a floor" the whole look pass
-- exists to remove. Cloning the map's own stock means the wood is made of the same art as the
-- village and cannot drift from it.
--
-- ===== NOTHING PLANTED HERE COLLIDES, AND SINCE 30.23 NOTHING IS QUERYABLE EITHER =====
-- A `MeshPart` at `CollisionFidelity.Default` is a handful of convex hulls, and a 64-stud canopy's
-- hull is very close to a 64-stud box: a hundred of them in the band the player has to fight in is
-- a hundred chances to repeat the 30.19 mountain trap. They are backdrop, so they are
-- `CanCollide = false` and every band stays walkable.
--
-- `CanQuery = false` is the 30.23 half of that and it is not cosmetic. Eight services run AFTER
-- this one and every one of them finds its spot with a box query or a downward ray -- `Splicer`,
-- `HubPlaza`, `MinigameService`, `MapArcade`, `MapAdventureBoard`. 30.17 is the boot log of what
-- happens when they hunt for clear ground and cannot find any, and a wood over the whole platform
-- is the largest possible version of that. A tree nothing can hit and nothing can see is exactly
-- what `evolution-lab-relocating-a-prop` means by *trees are not an obstruction to a building, they
-- are what it stands in*.

local JungleLayout = require(script.Parent.JungleLayout)
local MapRidge = require(script.Parent.MapRidge)

local MapForest = {}

-- A tree, for the purposes of this file, is a top-level child holding a mesh named `Top` -- the
-- name the source's own foliage uses, 162 of them across the map at 30..85 studs. Sized 30..110 so
-- the planting draws from real trees and not from the one 123-stud specimen or from a shrub.
local function treeStock(map)
	local stock = {}
	for _, c in ipairs(map:GetChildren()) do
		if c:IsA("Model") then
			local isTree = false
			for _, d in ipairs(c:GetDescendants()) do
				if d:IsA("MeshPart") and d.Name == "Top" then
					isTree = true
					break
				end
			end
			if isTree then
				local _, size = c:GetBoundingBox()
				if size.Y >= 30 and size.Y <= 110 then
					stock[#stock + 1] = c
				end
			end
		end
	end
	return stock
end

-- Stands one clone with its FEET on y = 0. The bounding box has to be re-read after the yaw,
-- because a rotated tree is a different box and seating it on the box it had before the turn is
-- how a trunk ends up half a stud in the air.
local function plantOne(proto, parent, x, z, rng, scale)
	local t = proto:Clone()
	t:ScaleTo(scale or rng:NextNumber(0.82, 1.28))
	t:PivotTo(t:GetPivot() * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	local cf, size = t:GetBoundingBox()
	t:PivotTo(t:GetPivot()
		+ Vector3.new(x - cf.Position.X, -(cf.Position.Y - size.Y / 2), z - cf.Position.Z))
	for _, d in ipairs(t:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			-- see the header: planted foliage is backdrop, and backdrop that collides -- or that a
			-- placement search can see -- is a trap
			d.CanCollide = false
			d.CanQuery = false
			d.CastShadow = false
		end
	end
	t.Name = "HuntTree"
	t.Parent = parent
	return t
end

-- ===== WHAT IS NOT WOOD =====
-- One predicate, asked at every candidate point. Everything it consults is owned somewhere else:
-- the roads and camps by `JungleLayout`, the village floor and the entrance funnel by the caller's
-- own spec. The one set of numbers that lives here is the arrival end, and it is the one thing on
-- the platform that is NOT part of the map -- `HubPlaza` builds its own 344 x 336 deck at a fixed
-- size regardless of the map scale, so a keep-out derived from the map would miss it.
local PLAZA_HALF_X = 200      -- the deck is 344 wide (|x| <= 172); 200 leaves its kerb a verge
local PLAZA_Z_NEAR = 55       -- ...and it runs from z = 74 to 422, with the portal behind it
local BOSS_CLEAR = 150        -- `insideKeepOut` reserves 132 at (0, -320); a canopy is wider
local BOSS_Z = -320
local ROAD_VERGE = 14         -- how far the first trunk stands back from the paint's own edge
-- ...and the mountains. `MapRidge.Footprints` is asked AFTER `Reseat` has run (see the call order
-- in `ForestMapService.Init`), so what comes back is where the rock actually ended up rather than
-- where the artist left it. A tree poking out of a mountainside is 30.19's own note about what
-- reads as broken, and it is the one keep-out here that cannot be authored: the mountains move.
local RIDGE_MARGIN = 8

local function isOpenGround(zoneKey, x, z, spec, segments, ridges)
	-- the village itself: the map's own props stand here and the wood must not grow through them
	if math.abs(x) <= (spec.floorHalfX or 0) + 12 and math.abs(z) <= (spec.floorHalfZ or 0) + 12 then
		return false
	end
	-- the arrival end, deck and portal both
	if math.abs(x) <= PLAZA_HALF_X and z >= PLAZA_Z_NEAR then return false end
	-- the entrance funnel, which is the road the plaza opens onto (`ForestMapService.cutEntrance`
	-- clears it; growing it back the same boot would be a comedy)
	local e = spec.entrance
	if e and z >= e.zNear and z <= e.zFar then
		local t = (z - e.zNear) / math.max(e.zFar - e.zNear, 1)
		if math.abs(x) <= e.halfNear + (e.halfFar - e.halfNear) * t + 20 then return false end
	end
	-- the boss's clearing
	if math.sqrt(x * x + (z - BOSS_Z) ^ 2) < BOSS_CLEAR then return false end
	-- every road, trunk and spur alike
	if JungleLayout.RoadClearance(zoneKey, x, z, segments) < ROAD_VERGE then return false end
	-- and every camp: this is what makes a clearing a room rather than a coordinate
	if JungleLayout.CampClearance(zoneKey, x, z) < JungleLayout.CLEARING_RADIUS then
		return false
	end
	-- ...and inside the rock itself
	for _, m in ipairs(ridges or {}) do
		if math.abs(x - m.x) <= m.hx + RIDGE_MARGIN and math.abs(z - m.z) <= m.hz + RIDGE_MARGIN then
			return false
		end
	end
	return true
end

-- ===== THE SCATTER =====
-- A jittered grid, not a random sprinkle. `spacing` studs apart with up to two thirds of that in
-- jitter gives a wood with no visible rows and no two trunks in the same place -- a uniform random
-- scatter over an area this size reliably produces both bald patches and pairs standing inside each
-- other, and Poisson sampling is a lot of machinery for a result nobody can tell apart from this.
--
-- The DENSITY RISES WITH DISTANCE FROM THE MIDDLE. The outer edge of the platform is the horizon
-- the player reads the zone against and wants to be solid wood; the inner edge is where she walks
-- and fights, and a wall there turns every quadrant into a corridor. Same rule the old side pockets
-- had, applied to the whole map.
local function density(x, z, f)
	local edge = math.max(math.abs(x) / f.xEdge, math.abs(z) / math.max(-f.zSouth, f.zNorth))
	-- 0.72 at the village's shoulder rising to 1.0 at the rampart. The first build of this row ran
	-- 0.55 at a 30-stud spacing and produced 464 trees over the whole platform -- which the capture
	-- shows as clumps of wood with fields of bare green between them, i.e. not what was asked for.
	-- The spacing is what governs it; the falloff only stops the fighting ground closing over.
	return 0.72 + 0.28 * math.clamp((edge - 0.45) / 0.5, 0, 1)
end

function MapForest.Plant(zoneKey, cx, map, spec)
	local stock = treeStock(map)
	if #stock == 0 then return 0 end

	local folder = Instance.new("Folder")
	folder.Name = "HuntForest"
	folder.Parent = map

	-- SEEDED OFF THE ZONE RATHER THAN OFF THE CLOCK: two servers of the same place have to grow the
	-- same forest, for the same reason `CreatureService` seeds its raised spots that way.
	local rng = Random.new(20260822 + math.floor(cx))

	local f = spec.forest
	if not f then return 0 end
	-- Resolved ONCE and passed down. `Segments` derives a spur per camp, so asking it per candidate
	-- point would rebuild twenty spurs about nine hundred times.
	local segments = JungleLayout.Segments(zoneKey)
	local ridges = MapRidge.Footprints(cx, map)

	local planted, tested = 0, 0
	local half = f.spacing / 2
	local x = -f.xEdge
	while x <= f.xEdge do
		local z = f.zSouth
		while z <= f.zNorth do
			local px = x + rng:NextNumber(-half, half)
			local pz = z + rng:NextNumber(-half, half)
			tested += 1
			if math.abs(px) <= f.xEdge and pz >= f.zSouth and pz <= f.zNorth
				and isOpenGround(zoneKey, px, pz, spec, segments, ridges)
				and rng:NextNumber() < density(px, pz, f)
			then
				plantOne(stock[rng:NextInteger(1, #stock)], folder, cx + px, pz, rng)
				planted += 1
				-- UNDERGROWTH: a smaller tree at the foot of a big one, sometimes two. This is the
				-- single thing that separates a planted wood from scattered decor -- real forest is
				-- clumped, and a grid of evenly sized trunks reads as an orchard however well it is
				-- jittered. They are drawn from the same stock at 0.45..0.7 so they are the same
				-- art, half-grown.
				for _ = 1, rng:NextInteger(0, 2) do
					local ox = px + rng:NextNumber(-22, 22)
					local oz = pz + rng:NextNumber(-22, 22)
					if isOpenGround(zoneKey, ox, oz, spec, segments, ridges) then
						plantOne(stock[rng:NextInteger(1, #stock)], folder, cx + ox, oz, rng,
							rng:NextNumber(0.45, 0.70))
						planted += 1
					end
				end
			end
			z += f.spacing
		end
		x += f.spacing
	end

	print(("[MapForest] %s: planted %d trees over %d grid cells, spacing %d, keep-outs: village, "
		.. "plaza, funnel, boss, %d road segments, %d camps, %d mountains")
		:format(zoneKey or "?", planted, tested, f.spacing, #(segments or {}),
			#(JungleLayout.Camps(zoneKey) or {}), #ridges))
	return planted
end

return MapForest
