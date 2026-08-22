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

local GameConfig = require(game:GetService("ReplicatedStorage").Modules.GameConfig)
local JungleLayout = require(script.Parent.JungleLayout)
local MapRidge = require(script.Parent.MapRidge)

local MapForest = {}

-- ===== 30.28: THE WOOD IS THREE LAYERS, NOT ONE BAND =====
-- 1,124 trees at one size band (0.82..1.28) photographs as an orchard however tight the spacing --
-- evenly sized trunks in a jittered grid, with bare green between them. Her note was
-- *"hocu da bas bude ko amazon suma pa da se prolazi kroz nju"*, and what makes rainforest read as
-- rainforest is the vertical structure: a few EMERGENTS standing clear above everything, a closed
-- CANOPY at one height, and a floor of UNDERGROWTH dense enough that you cannot see far through it.
-- All three are drawn from the map's own stock at different scales, so the wood is still made of
-- the village's art and cannot drift from it.
-- ===== "RAZDVOJI DRVECE": THE CLUMPS ARE PUSHED APART (30.28, second pass) =====
-- The first cut clumped undergrowth within 24 studs of a canopy tree whose own crown is 30..85
-- studs across, so a clump was one merged green mass rather than several trees -- her *"samo
-- razdvoji drvece i copy paste po mapi"*. The spread is wider than the crown now, so a neighbour
-- stands BESIDE a tree instead of inside it, and the emergent band came down from 2.15 (a 183-stud
-- tree, taller than the village is wide) to something that still breaks the canopy line without
-- becoming the thing you look at.
local EMERGENT_CHANCE = 0.05
local EMERGENT_SCALE = { 1.35, 1.7 }
local CANOPY_SCALE = { 0.80, 1.20 }
local UNDER_SCALE = { 0.38, 0.62 }
local UNDER_PER_TREE = { 0, 2 }
local UNDER_SPREAD = 40
-- ...and the shrub layer, which is the one thing here NOT made of trees. The map ships bushes and
-- flowers and they are what stops the forest floor being flat green between the trunks.
local SHRUB_PER_TREE = { 1, 2 }
local SHRUB_SCALE = { 0.7, 1.4 }
local SHRUB_SPREAD = 44

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

-- The floor layer's stock: the map's own bushes, shrubs and flowers, by the same prefixes
-- `MapCut.FOLIAGE_PREFIX` uses to decide what a road may cut. Capped at 20 studs so a "Bush" that
-- is really a tree does not join the undergrowth, and it is fine for this to come back EMPTY -- a
-- map with no shrubs still gets a three-layer wood, just without a floor.
local SHRUB_NAMES = { "Bush", "Shrub", "Flower" }
local function shrubStock(map)
	local stock = {}
	for _, c in ipairs(map:GetChildren()) do
		local size
		if c:IsA("Model") then
			size = select(2, c:GetBoundingBox())
		elseif c:IsA("BasePart") then
			size = c.Size
		end
		if size and size.Y >= 2 and size.Y <= 20 then
			for _, prefix in ipairs(SHRUB_NAMES) do
				if c.Name:sub(1, #prefix) == prefix then
					stock[#stock + 1] = c
					break
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
-- The boss's ground, ASKED rather than restated (30.27). `BOSS_Z = -320` was typed here while the
-- boss actually stood at (-400, -430), so for a whole phase the wood was held off an empty disc and
-- planted straight through the arena. `GameConfig.GetBossStation` is the one answer now.
local BOSS_CLEAR = 150        -- `insideKeepOut` reserves 132; a canopy is wider than a footprint
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
	-- the boss's clearing, wherever it actually is
	local boss = GameConfig.GetBossStation(zoneKey)
	if math.sqrt((x - boss.X) ^ 2 + (z - boss.Z) ^ 2) < BOSS_CLEAR then return false end
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

	local shrubs = shrubStock(map)

	-- One counter per layer, because "planted 2,900 trees" says nothing about whether the wood has
	-- any structure and a boot log that cannot tell an emergent from a bush cannot catch the day one
	-- of the three layers silently stops being planted.
	local tall, canopy, under, floorBits, tested = 0, 0, 0, 0, 0
	local half = f.spacing / 2

	-- Drawn from the same generator as the trees so the whole wood is one seed: two servers of the
	-- same place must grow the same forest.
	local function scatter(px, pz, n, spread, stockList, lo, hi)
		local made = 0
		if #stockList == 0 then return 0 end
		for _ = 1, n do
			local ox = px + rng:NextNumber(-spread, spread)
			local oz = pz + rng:NextNumber(-spread, spread)
			if isOpenGround(zoneKey, ox, oz, spec, segments, ridges) then
				plantOne(stockList[rng:NextInteger(1, #stockList)], folder, cx + ox, oz, rng,
					rng:NextNumber(lo, hi))
				made += 1
			end
		end
		return made
	end

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
				-- LAYER 1, the emergent: one tree in sixteen, half again as tall as the canopy it
				-- stands out of. Sparse on purpose -- an emergent that is common is just a canopy at
				-- a bigger scale, and the whole job of this layer is to break the flat green ceiling
				-- a single size band draws against the sky.
				local isTall = rng:NextNumber() < EMERGENT_CHANCE
				local band = isTall and EMERGENT_SCALE or CANOPY_SCALE
				plantOne(stock[rng:NextInteger(1, #stock)], folder, cx + px, pz, rng,
					rng:NextNumber(band[1], band[2]))
				if isTall then tall += 1 else canopy += 1 end

				-- LAYER 2, the undergrowth: young trees clumped at the foot of the one just
				-- planted, never sprinkled evenly. Clumping is the single rule that separates a
				-- planted wood from scattered decor.
				under += scatter(px, pz, rng:NextInteger(UNDER_PER_TREE[1], UNDER_PER_TREE[2]),
					UNDER_SPREAD, stock, UNDER_SCALE[1], UNDER_SCALE[2])

				-- LAYER 3, the floor: the map's own bushes and flowers, so the ground between the
				-- trunks is not flat green. This is what you actually walk past.
				floorBits += scatter(px, pz, rng:NextInteger(SHRUB_PER_TREE[1], SHRUB_PER_TREE[2]),
					SHRUB_SPREAD, shrubs, SHRUB_SCALE[1], SHRUB_SCALE[2])
			end
			z += f.spacing
		end
		x += f.spacing
	end

	local planted = tall + canopy + under + floorBits

	print(("[MapForest] %s: planted %d over %d cells at spacing %d -- %d emergent / %d canopy / "
		.. "%d undergrowth / %d shrub (of %d tree and %d shrub protos); keep-outs: village, plaza, "
		.. "funnel, boss, %d road segments, %d camps, %d mountains")
		:format(zoneKey or "?", planted, tested, f.spacing, tall, canopy, under, floorBits,
			#stock, #shrubs, #(segments or {}), #(JungleLayout.Camps(zoneKey) or {}), #ridges))
	return planted
end

return MapForest
