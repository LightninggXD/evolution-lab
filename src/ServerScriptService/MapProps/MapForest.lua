-- MapProps/MapForest -- the wood behind and beside the village, planted with the map's own trees.
--
-- Split out of `ForestMapService` in 31.4. It is a self-contained job -- take a stock of trees off
-- the map, stand clones of them on the ground -- and it grew a second band (the side pockets) the
-- day it was written, which is exactly the shape that should not live inside a 500-line service.
--
-- WHY THE TREES ARE CLONED FROM THE MAP AND NOT GENERATED. Behind the village is bare platform, and
-- 74 creatures standing on bare platform is the "random shapes on a floor" the whole look pass
-- exists to remove. Cloning the map's own stock means the wood is made of the same art as the
-- village and cannot drift from it.
--
-- NOTHING PLANTED HERE COLLIDES. A `MeshPart` at `CollisionFidelity.Default` is a handful of convex
-- hulls, and a 64-stud canopy's hull is very close to a 64-stud box: a hundred of them in the band
-- the player has to fight in is a hundred chances to repeat the 30.19 mountain trap. They are
-- backdrop, so they are `CanCollide = false` and every band stays walkable.

local MapForest = {}

-- A tree, for the purposes of this file, is a top-level child holding a mesh named `Top` -- the
-- name the source's own foliage uses, 181 of them across the map. Sized 30..110 so the planting
-- draws from real trees and not from the one 123-stud specimen or from a shrub.
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
local function plantOne(proto, parent, x, z, rng)
	local t = proto:Clone()
	t:ScaleTo(rng:NextNumber(0.82, 1.28))
	t:PivotTo(t:GetPivot() * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	local cf, size = t:GetBoundingBox()
	t:PivotTo(t:GetPivot()
		+ Vector3.new(x - cf.Position.X, -(cf.Position.Y - size.Y / 2), z - cf.Position.Z))
	for _, d in ipairs(t:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			-- see the header: planted foliage is backdrop, and backdrop that collides is a trap
			d.CanCollide = false
			d.CastShadow = false
		end
	end
	t.Name = "HuntTree"
	t.Parent = parent
	return t
end

-- The band behind the village: a back wall of trees, two flanks, and clumps in the middle. The
-- middle is deliberately sparse -- this is the ground 74 creatures stand and are fought on, so it
-- is a CLEARING with trees in it rather than a wood, which is the 30.12 rule read from the inside.
-- The band behind the village. Takes the shared stock, folder and rng from `Plant` so the hunt band
-- and the side pockets are one wood grown from one seed rather than two that happen to adjoin.
local function plantHunt(cx, hunt, stock, folder, rng)
	local planted = 0
	local function plant(x, z)
		plantOne(stock[rng:NextInteger(1, #stock)], folder, cx + x, z, rng)
		planted += 1
	end

	-- 1. the back wall, broken for the street down to the exit gate
	local x = -hunt.xEdge
	while x <= hunt.xEdge do
		if math.abs(x) > hunt.lane then
			plant(x + rng:NextNumber(-16, 16), hunt.zFar + rng:NextNumber(-14, 26))
			if rng:NextNumber() < 0.55 then
				plant(x + rng:NextNumber(-24, 24), hunt.zFar + rng:NextNumber(28, 62))
			end
		end
		x += 34
	end

	-- 2. the two flanks, which are what stop the band reading as a corridor
	for _, side in ipairs({ -1, 1 }) do
		local z = hunt.zFar
		while z <= hunt.zNear do
			plant(side * rng:NextNumber(hunt.xEdge - 150, hunt.xEdge), z + rng:NextNumber(-18, 18))
			if rng:NextNumber() < 0.7 then
				plant(side * rng:NextNumber(hunt.xEdge - 240, hunt.xEdge - 120),
					z + rng:NextNumber(-22, 22))
			end
			z += 38
		end
	end

	-- 3. clumps in the open middle -- at the foot of each other, never sprinkled evenly, which is
	--    the one rule that separates a planted wood from scattered decor
	for _ = 1, 16 do
		local ox = rng:NextNumber(-(hunt.xEdge - 190), hunt.xEdge - 190)
		local oz = rng:NextNumber(hunt.zFar + 40, hunt.zNear - 30)
		if math.abs(ox) > hunt.lane + 30 then
			for _ = 1, rng:NextInteger(2, 4) do
				plant(ox + rng:NextNumber(-34, 34), oz + rng:NextNumber(-30, 30))
			end
		end
	end

	return planted
end

-- ===== THE TWO SIDE POCKETS (31.4) =====
-- The village floor is 682 x 580 inside a 1250 x 1150 platform, so there is a ~280-stud strip of
-- bare platform down each side of it running the whole depth of the zone. `ForestMapService` clears
-- the map's mountain ring off the southern two-thirds of both, and this plants what is left.
--
-- IT IS DENSER AT THE OUTER EDGE AND THINNER AT THE INNER ONE, which is the only rule here that
-- matters: the outer edge is the horizon the player reads the zone against and wants to be solid
-- wood, while the inner edge is where she actually walks and fights, and a wall there turns the
-- pocket into a corridor -- the same mistake the hunt band's own middle avoids by being sparse.
local function plantFlanks(cx, flanks, stock, folder, rng)
	local planted = 0
	local function plant(x, z)
		plantOne(stock[rng:NextInteger(1, #stock)], folder, cx + x, z, rng)
		planted += 1
	end

	for _, side in ipairs({ -1, 1 }) do
		local z = flanks.zFar
		while z <= flanks.zNear do
			-- outer third: solid, this is the horizon
			plant(side * rng:NextNumber(flanks.xOut - 90, flanks.xOut), z + rng:NextNumber(-16, 16))
			if rng:NextNumber() < 0.75 then
				plant(side * rng:NextNumber(flanks.xOut - 170, flanks.xOut - 60),
					z + rng:NextNumber(-20, 20))
			end
			-- inner third: sparse, this is fighting ground
			if rng:NextNumber() < 0.42 then
				plant(side * rng:NextNumber(flanks.xIn, flanks.xIn + 110),
					z + rng:NextNumber(-24, 24))
			end
			z += 44
		end
	end
	return planted
end

-- The one entry point. One folder, one stock, one seed, both bands.
--
-- SEEDED OFF THE ZONE RATHER THAN OFF THE CLOCK: two servers of the same place have to grow the
-- same forest, for the same reason `CreatureService` seeds its raised spots that way.
function MapForest.Plant(map, cx, spec)
	local stock = treeStock(map)
	if #stock == 0 then return 0 end

	local folder = Instance.new("Folder")
	folder.Name = "HuntForest"
	folder.Parent = map

	local rng = Random.new(20260822 + math.floor(cx))
	local planted = 0
	if spec.hunt then planted += plantHunt(cx, spec.hunt, stock, folder, rng) end
	if spec.flanks then planted += plantFlanks(cx, spec.flanks, stock, folder, rng) end
	return planted
end

return MapForest
