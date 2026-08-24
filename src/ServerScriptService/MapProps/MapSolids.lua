-- src/ServerScriptService/MapProps/MapSolids.lua
-- WHAT THIS OWNS: The invisible collision boxes for trees and rocks.
-- WHERE THE LINE IS: MapForest plants the visible art and owns every number about it (its sink, its
-- scale, its spacing); MapSolids only decides WHICH of those planted items gets a collider and how
-- big that box is. Anything MapForest already knows is passed in -- see `Offer(inst, parent, sink)`.
-- WHY A SEPARATE PART: a CanCollide mesh tree is a soup of convex hulls close to its own bounding
-- box, so the canopy becomes a wall you cannot walk under. An upright box at the trunk collides
-- with the trunk only.
-- TWO PHASES, AND WHY: `Offer` runs during planting and only RECORDS. `Commit` runs once, sorts
-- every candidate TALLEST FIRST and only then applies the road rule and the gap rule. In plant
-- order the gap rule is won by whatever the loop reached first, which is a shrub as often as an
-- emergent -- measured over the real 4,445 trees:
--   plant-order    minH=18 gap=10 cap=8 -> made  752 | big trees (h>=40) solid: 232/817 = 28%
--   TALLEST-FIRST  minH=10 gap=7  cap=6 -> made 1072 | big trees (h>=40) solid: 585/817 = 72%
-- A ROCK IS NOT A TREE AND DOES NOT RUN THE GAP RULE. The first tallest-first build shipped
-- 1072 tree colliders and **36 rock colliders out of 909** -- the owner's complaint names the rocks
-- and 96% of them stayed walk-through. Measured on the live wood, three ways:
--   rocks first          -> rocks 432/880 but big trees collapse to 251/817 = 31%
--   overlap-is-not-a-gap -> rocks 152/880, big trees 605/817 = 74%
--   ROCKS EXEMPT         -> rocks 880/880, trees and big trees UNCHANGED at 1072 / 585 = 71.6%
-- The reason the exemption is safe and the tree case is not: there are 4,445 trunks in a dense wood
-- and colliding all of them is a wall, while there are 909 boulders on a 46-stud scatter and each
-- one is a landmark you can see. Rocks are therefore committed in a SECOND pass, after every tree,
-- so no tree is displaced by one, and they answer to the road rule only. What that costs is
-- reported: `slots` counts the pairs left with a gap too narrow to walk through, and both walk
-- probes are the veto on that number.
local JungleLayout = require(script.Parent.JungleLayout)

local MapSolids = {}

-- tree heights p25 = 5, p50 = 19 -- 10 excludes the shrub layer and keeps real small trees
local MIN_TREE_HEIGHT = 10
-- the wood is on a 16-stud grid and the median collider is 6.4 wide, so a gap rule of 10 rejected 55% of candidates
local GAP_MIN = 7
-- was 8 at 8da2612; 6 is the swept value -- minH=10/gap=7/cap=6 made 1072 colliders, 72% of big trees
local TRUNK_CAP = 6
-- inherited from 8da2612, never measured
local TRUNK_FLOOR = 2.5
-- inherited from 8da2612, never measured
local ROCK_FRACTION = 0.8
-- inherited from 8da2612, never measured
local SINK = 2
-- inherited from 8da2612, never measured
local ROAD_KEEP = 2

-- inherited from 8da2612, never measured
local MIN_ROCK_HEIGHT = 3.5
-- inherited from 8da2612, never measured
local COLLIDER_HEIGHT_FRAC = 0.6
-- TREES ONLY. A floor that overrides the 0.6 fraction for anything under ~17 studs tall, so a small
-- tree still stops a player instead of being stepped over. It must NOT reach a rock: a 3.6-stud
-- boulder was getting a 10-stud invisible wall (S3.3).
local MIN_COLLIDER_HEIGHT = 10
-- the height the roadmap row's check is stated in -- "at least 70% of trees over 40 studs solid"
local BIG_TREE = 40
-- HOW HIGH A BOX HAS TO STAND BEFORE THIS BODY STOPS AT IT. Not a guess: an invisible wall was
-- driven into with `Humanoid:MoveTo` at five heights, on the road at (0, 180), with the real
-- character (HipHeight 2.97, R15, 9.88 studs tall):
--   2.5 / 3.0 / 3.5 / 4.0 above ground -> WALKED OVER IT
--   4.5                                -> STOPPED
-- The first rock collider that was exactly its rock's own height stood 2.68 studs proud and the
-- character walked straight over it -- which on screen is indistinguishable from walking through
-- it. 14% of the wood's boulders are that low, so the height is floored here rather than left to
-- the art. A tree never reaches this floor: MIN_COLLIDER_HEIGHT already puts its box 8 studs up.
local MIN_STEP_STOP = 4.5

local DEBUG_SHOW = false

MapSolids.DEBUG_SHOW = DEBUG_SHOW

local state = {}

function MapSolids.Begin(zoneKey, segments)
	state = {
		zoneKey = zoneKey,
		segments = segments,
		cells = {},
		candidates = {},
		built = {},
		treesMade = 0,
		rocksMade = 0,
		-- one set per kind: a shared `skippedShort` cannot be attributed, and the two kinds are
		-- rejected by completely different tests (S3.5)
		treeShort = 0,
		treeClumped = 0,
		treeRoad = 0,
		rockShort = 0,
		rockRoad = 0,
		-- 59% of the tree models hold no part except `Top`, so their box is a FRACTION of the
		-- model's own footprint and not a measurement of a trunk. Both halves are reported so no
		-- reader believes every box was measured (S3.2).
		trunkMeasured = 0,
		trunkFallback = 0,
		bigOffered = 0,
		bigSolid = 0,
		tightestRoad = math.huge
	}
end

local function checkGap(x, z, hX, hZ)
	local cx = math.floor(x / 32)
	local cz = math.floor(z / 32)

	for nx = cx - 1, cx + 1 do
		for nz = cz - 1, cz + 1 do
			local cell = state.cells[nx] and state.cells[nx][nz]
			if cell then
				for _, other in ipairs(cell) do
					local gapX = math.max(0, math.abs(x - other.x) - (hX + other.hX))
					local gapZ = math.max(0, math.abs(z - other.z) - (hZ + other.hZ))
					if gapX < GAP_MIN and gapZ < GAP_MIN then
						return false
					end
				end
			end
		end
	end
	return true
end

local function addCell(x, z, hX, hZ)
	local cx = math.floor(x / 32)
	local cz = math.floor(z / 32)
	state.cells[cx] = state.cells[cx] or {}
	state.cells[cx][cz] = state.cells[cx][cz] or {}
	table.insert(state.cells[cx][cz], {x = x, z = z, hX = hX, hZ = hZ})
end

local function checkRoad(x, z, hX, hZ)
	local clearance = JungleLayout.RoadClearance(state.zoneKey, x, z, state.segments)
	local req = ROAD_KEEP + math.max(hX, hZ)
	if clearance < req then
		return false
	end
	if clearance < state.tightestRoad then
		state.tightestRoad = clearance
	end
	return true
end

-- `CanQuery = false` ON A COLLIDING PART IS A LIE, AND IT IS WRITTEN HERE ANYWAY. Measured in this
-- place on 2026-08-24 with three fresh parts:
--   CanCollide = true,  CanQuery = false -> property READS false, a raycast HITS it
--   CanCollide = false, CanQuery = false -> property reads false, the ray MISSES  (honoured)
--   CanCollide = true,  CanQuery = true  -> hit, as expected
-- So a box that stops a player is always visible to raycasts and `GetPartsInPart`, whatever this
-- line says. Two consequences, both real:
--   * the 32.4 walk probe DOES see these boxes, so its reading is a genuine test and not a blind
--     one -- that is the good half;
--   * anything in this file that asks the world where the ground is must EXCLUDE the boxes it has
--     already built, or it measures the top of a tree collider. See `Commit`'s RaycastParams; the
--     first version of the rock branch did not, and read one box as standing 31 studs underground.
-- The line stays because it states the intent and because it starts working the moment a box is
-- ever made non-colliding.
local function buildBox(name, x, bottomY, z, yaw, w, h, d, parent)
	local box = Instance.new("Part")
	box.Name = name
	box.Size = Vector3.new(w, h, d)
	box.CFrame = CFrame.new(x, bottomY + h / 2, z) * CFrame.Angles(0, yaw, 0)
	box.Anchored = true
	box.CanCollide = true
	box.CanQuery = false
	box.CanTouch = false
	box.Transparency = MapSolids.DEBUG_SHOW and 0.55 or 1
	if MapSolids.DEBUG_SHOW then
		box.Color = Color3.new(1, 0, 0)
		box.Material = Enum.Material.Neon
	end
	box.CastShadow = false
	box.Parent = parent
	return box
end

-- `sink` is how far MapForest buried this instance below y = 0. It is MapForest's number and is
-- PASSED IN rather than retyped here -- a second copy of `0.8` is the 31.5a trap (S3.4).
function MapSolids.Offer(inst, parent, sink)
	local isModel = inst:IsA("Model")
	local cf, bb, height

	if isModel then
		cf, bb = inst:GetBoundingBox()
		height = bb.Y
		if height >= BIG_TREE then
			state.bigOffered += 1
		end
		if height < MIN_TREE_HEIGHT then
			state.treeShort += 1
			return
		end
	else
		cf = inst.CFrame
		height = inst.Size.Y
		if height - (sink or 0) < MIN_ROCK_HEIGHT then
			state.rockShort += 1
			return
		end
	end

	table.insert(state.candidates, {
		inst = inst,
		parent = parent,
		kind = isModel and "tree" or "rock",
		cf = cf,
		height = height,
		bb = bb,
		sink = sink or 0
	})
end

-- `gapRule` is false for a rock -- see the header. A rock still enters the cell grid, so a tree
-- placed after one would respect it; there is no such tree, because every tree is committed first.
-- `rp` excludes everything this pipeline planted -- see the note over `buildBox` for why that is
-- not optional.
local function place(c, gapRule, rp)
	do
		local _, yaw, _ = c.cf:ToEulerAnglesYXZ()
		local x, z = c.cf.X, c.cf.Z
		local bottomY, w, h, d

		if c.kind == "tree" then
			local minX, minZ = math.huge, math.huge
			local maxX, maxZ = -math.huge, -math.huge
			local hasTrunk = false

			for _, part in ipairs(c.inst:GetDescendants()) do
				if part:IsA("BasePart") and part.Name ~= "Top" then
					hasTrunk = true
					local sX, sY, sZ = part.Size.X / 2, part.Size.Y / 2, part.Size.Z / 2
					local pCf = part.CFrame
					local corners = {
						pCf * Vector3.new(sX, sY, sZ), pCf * Vector3.new(-sX, sY, sZ),
						pCf * Vector3.new(sX, -sY, sZ), pCf * Vector3.new(-sX, -sY, sZ),
						pCf * Vector3.new(sX, sY, -sZ), pCf * Vector3.new(-sX, sY, -sZ),
						pCf * Vector3.new(sX, -sY, -sZ), pCf * Vector3.new(-sX, -sY, -sZ)
					}
					for _, crn in ipairs(corners) do
						local lp = c.cf:Inverse() * crn
						minX = math.min(minX, lp.X)
						minZ = math.min(minZ, lp.Z)
						maxX = math.max(maxX, lp.X)
						maxZ = math.max(maxZ, lp.Z)
					end
				end
			end

			if hasTrunk then
				state.trunkMeasured += 1
				w = math.clamp(maxX - minX, TRUNK_FLOOR, TRUNK_CAP)
				d = math.clamp(maxZ - minZ, TRUNK_FLOOR, TRUNK_CAP)
				-- STAND THE BOX AT THE TRUNK. The trunk AABB is measured in the model's own frame
				-- and its centre is NOT the model's centre -- median 1.04 studs off, max 2.70. The
				-- offset used to be computed and thrown away, which put the box in the middle of
				-- the canopy instead of around the wood you actually bump into (S3.1).
				local world = c.cf * Vector3.new((minX + maxX) / 2, 0, (minZ + maxZ) / 2)
				x, z = world.X, world.Z
			else
				state.trunkFallback += 1
				-- fallback derived from 8da2612; the model has no part but `Top`, so there is no
				-- trunk to measure and 0.18 of the narrower model axis is a guess at one
				w = math.clamp(math.min(c.bb.X, c.bb.Z) * 0.18, TRUNK_FLOOR, TRUNK_CAP)
				d = w
			end
			h = math.max(c.height * COLLIDER_HEIGHT_FRAC, MIN_COLLIDER_HEIGHT)
			bottomY = (c.cf.Y - c.height / 2) - SINK
		else
			w = c.inst.Size.X * ROCK_FRACTION
			d = c.inst.Size.Z * ROCK_FRACTION
			-- A ROCK'S COLLIDER IS THE ROCK'S OWN ABOVE-GROUND HEIGHT. `MIN_COLLIDER_HEIGHT` is a
			-- tree floor and gave a 3.6-stud boulder a 10-stud wall (S3.3). The `+ SINK` is the
			-- buried skirt below the ground line only: the box TOP lands on the rock's own top.
			--
			-- ASK THE GROUND, DO NOT ASSUME IT. `MapForest` stands every rock against a FIXED
			-- y = 0 plane, which is right for three quarters of the wood and wrong by up to 3 studs
			-- elsewhere, and a box built on the assumed plane is that much shorter than it reads.
			-- `rp` is what makes the answer the FLOOR rather than a neighbour: see `buildBox`. If
			-- the ray finds nothing at all, fall back to the same plane MapForest used rather than
			-- to zero, so the two files still agree.
			local hit = workspace:Raycast(Vector3.new(x, c.cf.Y + 200, z), Vector3.new(0, -400, 0), rp)
			local groundY = hit and hit.Position.Y or (c.cf.Y - c.height / 2 + c.sink)
			local aboveGround = math.max((c.cf.Y + c.height / 2) - groundY, MIN_STEP_STOP)
			h = aboveGround + SINK
			bottomY = groundY - SINK
		end

		local hX = w / 2
		local hZ = d / 2

		if not checkRoad(x, z, hX, hZ) then
			if c.kind == "tree" then state.treeRoad += 1 else state.rockRoad += 1 end
			return
		end

		if gapRule and not checkGap(x, z, hX, hZ) then
			state.treeClumped += 1
			return
		end

		addCell(x, z, hX, hZ)

		-- Recorded for the report ONLY, with the yaw folded in. The gap rule above works on the
		-- box's own axes; a box rotated 45 degrees covers more world-axis ground than that, so the
		-- distance reported below is a genuinely different number from the one the rule enforced --
		-- which is the whole point of reporting it (S3.6).
		local cy, sy = math.abs(math.cos(yaw)), math.abs(math.sin(yaw))
		table.insert(state.built, {
			x = x, z = z,
			hX = hX * cy + hZ * sy,
			hZ = hX * sy + hZ * cy
		})

		if c.kind == "tree" then
			buildBox("HuntTreeCollider", x, bottomY, z, yaw, w, h, d, c.parent)
			state.treesMade += 1
			if c.height >= BIG_TREE then
				state.bigSolid += 1
			end
		else
			buildBox("HuntRockCollider", x, bottomY, z, yaw, w, h, d, c.parent)
			state.rocksMade += 1
		end
	end
end

function MapSolids.Commit()
	-- tallest first: the gap rule is a race, and the emergent must win it
	table.sort(state.candidates, function(a, b)
		return a.height > b.height
	end)

	-- Everything this pipeline plants -- the art AND the boxes built below -- is excluded, so the
	-- rock branch's ground ray answers about the floor. Collected from the candidates rather than
	-- named, so this file still does not know what MapForest calls its folder.
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.IgnoreWater = true
	local seen, excl = {}, {}
	for _, c in ipairs(state.candidates) do
		if c.parent and not seen[c.parent] then
			seen[c.parent] = true
			excl[#excl + 1] = c.parent
		end
	end
	rp.FilterDescendantsInstances = excl

	-- TWO PASSES, IN THIS ORDER. Every tree is placed against the gap rule first, so the tree and
	-- big-tree counts are exactly what they were before rocks were let through; the rocks then fill
	-- in around them under the road rule alone.
	for _, c in ipairs(state.candidates) do
		if c.kind == "tree" then
			place(c, true, rp)
		end
	end
	for _, c in ipairs(state.candidates) do
		if c.kind == "rock" then
			place(c, false, rp)
		end
	end
end

-- The true minimum surface distance between any two built colliders, over their WORLD-axis
-- footprints. `math.max(gapX, gapZ)` over accepted candidates is >= GAP_MIN by construction and
-- therefore says nothing; this walks the finished set instead.
local function tightestBuiltGap()
	local grid = {}
	for _, b in ipairs(state.built) do
		local cx, cz = math.floor(b.x / 32), math.floor(b.z / 32)
		grid[cx] = grid[cx] or {}
		grid[cx][cz] = grid[cx][cz] or {}
		table.insert(grid[cx][cz], b)
	end

	-- `slots` is the price of the rock exemption, and it is counted rather than argued: a pair that
	-- OVERLAPS is one obstacle and costs nothing, a pair GAP_MIN apart is a corridor, and a pair
	-- with a sliver between them is the only shape that can pinch a player. Both walk probes are
	-- the veto -- this number only makes the cost visible in the boot log.
	local tightest, slots = math.huge, 0
	for _, b in ipairs(state.built) do
		local cx, cz = math.floor(b.x / 32), math.floor(b.z / 32)
		for nx = cx - 1, cx + 1 do
			for nz = cz - 1, cz + 1 do
				local cell = grid[nx] and grid[nx][nz]
				if cell then
					for _, o in ipairs(cell) do
						if o ~= b then
							local gx = math.max(0, math.abs(b.x - o.x) - (b.hX + o.hX))
							local gz = math.max(0, math.abs(b.z - o.z) - (b.hZ + o.hZ))
							local dist = math.sqrt(gx * gx + gz * gz)
							if dist < tightest then
								tightest = dist
							end
							if dist > 0.01 and dist < GAP_MIN then
								slots += 1
							end
						end
					end
				end
			end
		end
	end
	-- every pair is walked twice, once from each end
	return tightest, slots // 2
end

function MapSolids.Report(zoneKey)
	-- the gap rule only ever runs on trees now, so the warning is stated over the trees it judged
	local trees = state.treesMade + state.treeClumped + state.treeRoad
	if trees > 0 and state.treeClumped / trees > 0.25 then
		warn(("[MapSolids] GAP RULE REJECTED %.1f%% OF TREE CANDIDATES"):format(
			state.treeClumped / trees * 100))
	end

	local gap, slots = tightestBuiltGap()
	local pct = state.bigOffered > 0 and (state.bigSolid / state.bigOffered * 100) or 0

	print(("[MapSolids] %s: %d tree + %d rock colliders | big trees (h>=%d) solid: %d of %d = %.1f%%"
		.. " | trunk-measured %d / fallback %d | skipped trees %d short %d clumped %d road, rocks"
		.. " %d short %d road (rocks do not run the gap rule) | tightest built gap %.1f studs,"
		.. " %d pairs under %d apart, tightest road clearance %.1f studs"):format(
		tostring(zoneKey), state.treesMade, state.rocksMade,
		BIG_TREE, state.bigSolid, state.bigOffered, pct,
		state.trunkMeasured, state.trunkFallback,
		state.treeShort, state.treeClumped, state.treeRoad,
		state.rockShort, state.rockRoad,
		gap == math.huge and 0 or gap, slots, GAP_MIN,
		state.tightestRoad == math.huge and 0 or state.tightestRoad))

	return state
end

return MapSolids
