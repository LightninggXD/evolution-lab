-- MapProps/MapSquare -- the village square's furniture stands in a ring around the eggs.
--
-- The owner's drawing of the zone puts a circle at the middle of the cross with the eggs in it and
-- the shop, upgrades and potion buildings in the corners around it -- *"da jaja ne lebde vec da su
-- u centru i okolo ti sopovi"*. 30.24 moved the eggs; this is the "okolo".
--
-- ===== WHAT WAS WRONG WITH LEAVING THEM WHERE THE ARTIST PUT THEM =====
-- Nothing, while the square's centre was a fountain. The map's own arrangement is a market row
-- along the north edge: Shop at (57, 69), Upgrades at (-87, 93), Potions off on its own at
-- (-66, -63). Two of the three doors are in one corner and the third is behind you, which reads as
-- scattered the moment the middle of the square becomes the thing you walk to. A player standing at
-- the eggs should be able to see every door in the village by turning on the spot.
--
-- ===== THE FRONT IS MEASURED OFF THE MAP, NOT GUESSED AND NOT INHERITED (32.2) =====
-- These are hand-authored props and nothing records which way their fronts face, so no yaw is ever
-- computed from a model's own LookVector -- `roblox-model-facing-and-scaling` is the standing note
-- about what that costs, and this map proves it twice over: `Shop`'s building looks straight AT the
-- fountain and `Upgrades`' looks straight AWAY from it, dot +0.987 against -0.993.
--
-- What IS reliable is that `MapAnchors` publishes the PAD and the BUILDING separately, and a pad is
-- by construction the plate you stand on in front of a counter. **`pad - house` is the shopfront's
-- facing**, it agrees with the direction to the fountain for both of this map's paired groups
-- (0.996 / 0.955), and a capture from the eggs confirms both doors face the middle. A lone pad with
-- nothing behind it has no measurable front and falls back to the relative rule below.
--
-- ===== WHAT THE RELATIVE RULE WAS, AND WHY IT MADE HER COMPLAINT INSTEAD OF FIXING IT =====
-- Until 32.2 every prop was turned by *the change in its own bearing about the square's centre* --
-- sound in principle, and wrong in the place, because `CFrame.Angles(0, t, 0)` LOWERS a bearing
-- read as `atan2(z, x)` by `t`. The turn was fed in with the opposite sign, so a group walked D
-- degrees round the ring had its facing turned -D and ended up 2D out. `Arrange` is what made the
-- shops face away; the artist's own arrangement never did.
--
-- ===== IT MOVES INSTANCES, AND THE PROMPTS FOLLOW BECAUSE OF WHAT `MapAnchors` HOLDS =====
-- `MapAnchors.Registry` stores the INSTANCE, and `MapCounters` finds its prompt target by walking
-- to that same instance -- so a prop moved after the census keeps every door it was given. This is
-- exactly the property `MapEggs` relies on for the egg columns, and the reason both files move
-- contents rather than rebuilding anything. **The cached `pos` / `top` on an anchor DO go stale
-- here**, which is why this runs after every consumer of them.

local MapAnchors = require(script.Parent.MapAnchors)
local MapGates = require(script.Parent.MapGates)
local MapRoad = require(script.Parent.MapRoad)
local MapCut = require(script.Parent.MapCut)
local MapPaint = require(script.Parent.MapPaint)

local MapSquare = {}

-- ===== THE RING =====
-- Bearings in degrees, measured the way `math.atan2(z, x)` reads them. The two the square must keep
-- clear are the ROAD MOUTHS: the approach road arrives from the north (+90) and `MapGates`' south
-- lane leaves at -90. The east and west arms of the cross branch off the south lane at z = -100 and
-- never touch the circle, so there are two mouths here, not four.
--
-- 0 / 135 / 225 is where each group is ASKED to go. Whether it lands there is decided by measuring,
-- not by the arithmetic above -- see `clearOfRoads`. The first cut of this file trusted the angles
-- and the owner photographed the result: *"ovaj shop je usao u put od ednom"*, a shop standing in
-- a road. `evolution-lab-relocating-a-prop` is the standing note and its first rule is exactly this
-- -- measure from the CORRIDOR, not from the prop, and validate against EVERY lane rather than the
-- one that objected.
--
-- ===== A SLOT IS A GROUP, NOT A PROP, AND `MapAnchors` IS WHY =====
-- `Shop` is four objects in this map and `Upgrades` is two: the pad you stand on and the building
-- behind it, published as `shop` / `shopHouse` (that file's own header says so). Moving the pad
-- alone would leave its shopfront on the far side of the village with a prompt floating in an empty
-- ring -- the pad carries the door and the house is what tells you the door is there. So a slot
-- names every anchor that has to travel together, and the group moves as ONE RIGID BODY about the
-- FIRST of them, which keeps the counter standing in front of its own shop.
local SLOTS = {
	{ roles = { "shop", "shopHouse" }, bearing = 0 },
	{ roles = { "upgrades", "upgradesHouse" }, bearing = 135 },
	{ roles = { "potions" }, bearing = 225 },
}

-- Where the prop's CENTRE lands, derived rather than typed: the circle's own radius, plus the
-- prop's half-width so it stands beside the paint rather than on it, plus a verge. `MapEggs` paints
-- the circle at 132 diameter, and that number lives there -- this reads the anchor's size and takes
-- the radius as an argument so the two cannot drift apart.
local CIRCLE_R = 66
local VERGE = 10

-- How far round the ring to look when the asked-for bearing is blocked, and in what steps. A ring of
-- candidates rather than a slide along one axis: a one-dimensional search cannot solve a junction,
-- which is the second rule in `evolution-lab-relocating-a-prop`.
local TRY_STEP = 12
local TRY_MAX = 15          -- +/- 180 degrees, so a group can end up anywhere on the ring
-- Clearance a building wants from a road's centre line, on top of the road's own half-width and the
-- building's own half-width. A prop touching the verge is a village; a prop inside the driving line
-- is a roadblock.
local ROAD_VERGE = 12
-- Anything shorter than this is ground clutter a building may stand among -- a flower, a flat rock,
-- a kerb. Same threshold `MapCut` uses to decide what a road cut may ignore.
local BLOCKER_MIN_H = 5
-- How close two colours have to be to call a surface "the artist's dirt". The map's own paths are a
-- flat `UnionOperation` in exactly the colour `MapPaint.DirtColour` reads off it, so this is an
-- equality test with room for a shaded copy.
local DIRT_TOLERANCE = 0.12

-- Perpendicular distance from a point to a lane's centre line, clamped to the segment.
local function distToLane(x, z, lane)
	local dx, dz = lane.x2 - lane.x1, lane.z2 - lane.z1
	local len2 = dx * dx + dz * dz
	local t = 0
	if len2 > 0 then
		t = math.clamp(((x - lane.x1) * dx + (z - lane.z1) * dz) / len2, 0, 1)
	end
	return math.sqrt((x - (lane.x1 + dx * t)) ^ 2 + (z - (lane.z1 + dz * t)) ^ 2)
end

-- Every road that reaches the square, asked of the module that owns it rather than restated here.
-- `MapGates` publishes the three village lanes and `MapRoad` the approach; a lane's `w` is its
-- painted width and `halfA`/`halfB` is what `MapGates` cut, so the wider of the two is what a
-- building has to clear.
local function villageLanes()
	local lanes = {}
	for _, lane in ipairs(MapGates.LANES or {}) do
		lanes[#lanes + 1] = {
			x1 = lane.x1, z1 = lane.z1, x2 = lane.x2, z2 = lane.z2,
			half = math.max(lane.wA or 0, lane.wB or 0) / 2,
		}
	end
	local approach = MapRoad.LANE
	if approach then
		lanes[#lanes + 1] = {
			x1 = approach.x1, z1 = approach.z1, x2 = approach.x2, z2 = approach.z2,
			half = approach.w / 2,
		}
	end
	return lanes
end

-- ===== WHAT ELSE IS STANDING THERE =====
-- The generated lanes were never the whole story. The owner's capture of *"ovaj shop je usao u put"*
-- was measured afterwards and the shop pad was not in a lane at all -- a ray at its spot came back
-- holding `Meshes/house123_Cube`, i.e. it had been moved ON TOP OF A HOUSE. So there are three
-- tests, not one, and the third is what `evolution-lab-relocating-a-prop` means by classifying a
-- blocker: **trees are not an obstruction to a building, they are what it stands in**, while a wall
-- is. Planted foliage never even reaches this query -- `MapForest` marks it `CanQuery = false` --
-- and the map's own foliage is filtered by name through the classifier `MapCut` already owns.
-- ===== A PART'S SIZE IS IN ITS OWN FRAME, AND THAT COST TWO OF THE THREE GROUPS (30.32) =====
-- `Size.Y` is the height of a part ALONG ITS OWN UP AXIS. Turn the part on its side and that number
-- stops being a height. The village square's paving is exactly that case: a `UnionOperation` lying
-- flat at y = 0.1, one stud thick, whose `Size` reads **(1, 143.8, 144)** because the union was
-- authored standing up and rotated down. Read as a height, a 1-stud floor is a 143-stud tower, and
-- the test below called every point on the square occupied.
--
-- What that shipped: `[MapSquare] Forest: 2 props in 1 of 3 groups ... LEFT WHERE THEY WERE (no
-- clear bearing): upgrades, potions`. Two thirds of her *"i okolo ti sopovi"* silently did not
-- happen, and the log said so in a line that reads like a map quirk rather than a bug.
--
-- The world height is the box's support along Y -- the same projection `MapCut.LaneFootprint` takes
-- along a lane's normal, on the vertical axis. Same family as
-- `roblox-ball-part-min-axis` and `roblox-extentsoffset-is-half-size`: a number in the part's frame
-- read as a number in the world's.
local function worldHeight(part)
	local cf, size = part.CFrame, part.Size
	return math.abs(cf.RightVector.Y) * size.X
		+ math.abs(cf.UpVector.Y) * size.Y
		+ math.abs(cf.LookVector.Y) * size.Z
end

local function occupied(x, z, hw, map, params)
	local hits = workspace:GetPartBoundsInBox(CFrame.new(x, 20, z), Vector3.new(hw * 2, 40, hw * 2),
		params)
	for _, part in ipairs(hits) do
		if worldHeight(part) >= BLOCKER_MIN_H then
			-- climb to the top-level child of the map, which is what the classifier reads
			local top = part
			while top.Parent and top.Parent ~= map do top = top.Parent end
			if top.Parent == map then
				if not MapCut.IsFoliage(top) then return true end
			else
				-- ===== AND EVERYTHING THAT IS NOT THE MAP BLOCKS TOO (30.32) =====
				-- This used to be `if top.Parent == map and not IsFoliage(top)`, which reads as
				-- "reject map buildings" and behaves as "**accept everything that is not this map**".
				-- The ring is 88 studs out and the village floor ends near there, so a candidate on
				-- the far side of it is standing in `HubPlaza`'s lamps, or a portal arch, or the
				-- arcade -- none of which are children of `VillageMap`, and every one of which came
				-- back as open ground.
				--
				-- Planted foliage never reaches this query at all: `MapForest` marks its 3,461 trees
				-- `CanQuery = false`, so the one class that would flood this is already filtered by
				-- the engine rather than by a name test that cannot know their conventions.
				return true
			end
		end
	end
	return false
end

-- True when the ground here is the artist's own painted path. A building on it is the same fault as
-- a building in a generated lane; the map's road network simply is not expressed as coordinates
-- anywhere, so it is read off the surface instead.
-- ...and the SAME RAY answers the other question worth asking, which is whether this is ground at
-- all. `occupied` only sees a blocker `BLOCKER_MIN_H` tall; a prop built out of a stack of shorter
-- pieces is invisible to it and a candidate on the roof of one comes back clear. Measured on the
-- live build, a search around the adventure board's spot offered four such candidates in its first
-- clear ring -- ground at 32.1, 23.6, 21.2 and 10.9 studs, every one of them the top of something.
-- That is the fault `MapAdventureBoard` already shipped once, a board standing on a mannequin's hat.
-- The village floor is 0.64 and the bare platform under it 0.00, so anything materially above that
-- is a roof.
local FLAT_MAX = 4
local function groundFault(x, z, ctx)
	local hit = workspace:Raycast(Vector3.new(x, 200, z), Vector3.new(0, -400, 0), ctx.rayParams)
	if not hit then return "void" end
	if hit.Position.Y > FLAT_MAX then return "roof" end
	local c = hit.Instance.Color
	if math.abs(c.R - ctx.dirt.R) + math.abs(c.G - ctx.dirt.G) + math.abs(c.B - ctx.dirt.B)
		< DIRT_TOLERANCE then
		return "road"
	end
	return nil
end

-- True when a group of half-width `hw` standing at (x, z) is clear of every road, of the artist's
-- own paths, of any building, AND of everything already placed this pass. That last one matters as
-- much as the rest: two buildings on one bearing is a building in a road seen from another angle.
--
-- ===== AND `probe` IS WHY AN HONEST FOOTPRINT DOES NOT MEAN A STUCK SHOP (32.2) =====
-- Measuring a group by its whole box rather than by its pad took the shop's `hw` from 15 to 30, and
-- the first run of that left the shop with NOWHERE on the ring: `occupied` rejects a spot when
-- anything non-foliage over `BLOCKER_MIN_H` is inside a box of that half-width, and at 30 the box
-- is 60 studs across in a village whose ring carries fences, barrels, signs, the eight boards and
-- the four egg columns. A 7-stud barrel is not a wall to a building, but a 60-stud box full of them
-- is a wall to the search.
--
-- The two questions are separated rather than compromised. The ROAD test and the `taken` spacing
-- always run at the true `hw`, because a building in a lane and a building inside another building
-- are the two faults this file exists to prevent. Only the BLOCKER PROBE may be narrowed, and only
-- on a second attempt -- see the two-tier walk in `Arrange`.
local function clearOfRoads(x, z, hw, lanes, taken, ctx, probe)
	for _, lane in ipairs(lanes) do
		if distToLane(x, z, lane) < lane.half + hw + ROAD_VERGE then return false end
	end
	for _, t in ipairs(taken) do
		if math.sqrt((x - t.x) ^ 2 + (z - t.z) ^ 2) < t.hw + hw + VERGE then return false end
	end
	if ctx then
		if groundFault(x, z, ctx) then return false end
		if occupied(x, z, probe or hw, ctx.map, ctx.boxParams) then return false end
	end
	return true
end

local function measure(inst)
	if inst:IsA("Model") then
		local cf, size = inst:GetBoundingBox()
		return cf.Position, size
	elseif inst:IsA("BasePart") then
		return inst.Position, inst.Size
	end
	return nil, nil
end

-- ===== A GROUP IS WIDER THAN ITS PAD, AND THAT IS HALF OF "THE OBJECTS OVERLAP" (32.2) =====
-- Every test in this file ran at `max(size.X, size.Z) / 2` OF THE LEAD ANCHOR, and the lead is the
-- PAD -- the 1-stud plate you stand on. Measured on the placed map: the shop's pad is 30.6 wide and
-- its building is 59.5 x 57.8 standing 20.9 studs behind it, so the ring walk, the road test, the
-- `taken` spacing and the `onRing` test every one of them ran at 15.3 for a thing whose own box is
-- 60 wide. Two groups keeping `VERGE` between their PADS can have sixty studs of building inside
-- each other, which is exactly *"da se objekti ne preklapaju koji ne trebaju"*.
--
-- So a group is measured by its own WORLD box and placed by that box's CENTRE rather than by the
-- pad. It still moves as ONE RIGID BODY, so the pad keeps its exact offset from its house; the only
-- thing that changes is which point of the group is the one put on the ring.
--
-- `Size` is in the part's own frame -- the trap `worldHeight` above documents on the vertical axis
-- -- so each horizontal half-extent is the box's SUPPORT along that world axis, never a component
-- of `Size`. `Model:GetBoundingBox()` is no help either: that box is ORIENTED, so its size is in
-- the model's frame for the very same reason.
local function accumulateBox(inst, b)
	local parts = inst:IsA("BasePart") and { inst } or inst:GetDescendants()
	for _, p in ipairs(parts) do
		if p:IsA("BasePart") then
			local cf, s = p.CFrame, p.Size
			local hx = (math.abs(cf.RightVector.X) * s.X + math.abs(cf.UpVector.X) * s.Y
				+ math.abs(cf.LookVector.X) * s.Z) / 2
			local hz = (math.abs(cf.RightVector.Z) * s.X + math.abs(cf.UpVector.Z) * s.Y
				+ math.abs(cf.LookVector.Z) * s.Z) / 2
			b.minX = math.min(b.minX, cf.Position.X - hx)
			b.maxX = math.max(b.maxX, cf.Position.X + hx)
			b.minZ = math.min(b.minZ, cf.Position.Z - hz)
			b.maxZ = math.max(b.maxZ, cf.Position.Z + hz)
			b.n += 1
		end
	end
end

-- Centre and half-width of everything in `group`, read as one world box.
local function groupFootprint(group)
	local b = { minX = math.huge, maxX = -math.huge, minZ = math.huge, maxZ = -math.huge, n = 0 }
	for _, inst in ipairs(group) do accumulateBox(inst, b) end
	if b.n == 0 then return nil end
	return (b.minX + b.maxX) / 2, (b.minZ + b.maxZ) / 2,
		math.max(b.maxX - b.minX, b.maxZ - b.minZ) / 2
end

-- Every instance the map declared, whatever role it was declared under. `companionsOf` needs all of
-- them and a per-slot list is not enough: the four egg columns, the eight boards and the podium
-- stand on this ring too, and a group that swept one up would carry the Mythic egg into the shop.
local function anchorSet(zoneKey)
	local set = {}
	local function add(v)
		if type(v) ~= "table" then return end
		if v.inst then set[v.inst] = true return end
		for _, sub in pairs(v) do add(sub) end
	end
	add(MapAnchors.Registry[zoneKey] or {})
	return set
end

-- ===== WHAT WALKS WITH A SHOPFRONT, AND WHY IT IS NOT `reg.stall` (32.2) =====
-- `MapAnchors` publishes `reg.stall` and nothing has ever consumed it. Naming it in the slot would
-- be wrong on this map, though, and one query says so: the stall stands at bearing -21 and 93 studs
-- from the shop's own pad. It is a market stall of its own, not part of the shopfront, and dragging
-- it across the square would be a new fault rather than a fix. It is not excluded from `occupied`
-- either, so it already behaves as what it is -- a building the ring walk has to go round.
--
-- What IS part of a shopfront here is unnamed. The potion pad has five `Meshes/Sell*` counters
-- standing 2..6 studs behind it, children of the map with no anchor at all, and THEY are what
-- "stays behind when the shopfront walks away" actually looks like. So the rule is PROXIMITY, not a
-- name: a non-foliage map child standing right up against the PAD is that pad's furniture.
--
-- ===== AND IT IS THE PAD, NOT THE GROUP, WHICH IS THE WHOLE DIFFERENCE (measured) =====
-- The first cut of this searched the group's whole footprint -- pad plus building, 60 studs across
-- -- and the boot log said what that costs: **45 props carried**, 37 of them by the potion pad
-- alone, which is not a shopfront but a neighbourhood. Every one of them then joined the group's
-- box, so `hw` grew, so the ring walk got harder, so the group that swept up the most was the one
-- that ended up with nowhere to stand. A counter belongs to a pad because it is AT the pad: the
-- five `Meshes/Sell*` pieces are 2..6 studs from theirs. So the radius is the pad's own.
--
-- Foliage is excluded because foliage is FELLED rather than carried; every declared anchor is
-- excluded because a neighbour is a neighbour; a `SpawnLocation` is excluded because moving one
-- moves where a player arrives; and anything wider than the pad itself is excluded, which is what
-- stops the artist's 83-stud paving union being picked up by the shop standing on it.
local COMPANION_MARGIN = 6
local function companionsOf(map, gx, gz, hw, anchored, claimed)
	local out = {}
	for _, c in ipairs(map:GetChildren()) do
		if not anchored[c] and not claimed[c] and not c:IsA("SpawnLocation")
			and c.Name ~= "MainPart" and c.Name ~= "Terrain" and c.Name ~= "HuntForest"
			and not MapCut.IsFoliage(c) then
			local pos, size = measure(c)
			if pos and math.max(size.X, size.Z) <= hw * 2
				and math.abs(pos.X - gx) <= hw + COMPANION_MARGIN
				and math.abs(pos.Z - gz) <= hw + COMPANION_MARGIN then
				out[#out + 1] = c
			end
		end
	end
	return out
end

-- ===== AND THE OTHER HALF: A BUILDING FELLS THE WOOD IT LANDS IN (32.2) =====
-- `occupied` deliberately lets a group stand among foliage -- *trees are not an obstruction to a
-- building, they are what it stands in* -- and `evolution-lab-relocating-a-prop`'s fourth rule says
-- the same thing with a second half this file never shipped: classify the blockers, and IF THE ONLY
-- BLOCKERS ARE FOLIAGE, take the spot AND FELL THEM. Without the felling, "may stand among" is only
-- a licence to put a 57-stud building inside a 64-stud pine.
--
-- The wood in question is the MAP'S OWN, not `MapForest`'s, and that is worth writing down because
-- the plan for this row named the wrong one. `MapForest.isOpenGround` holds its planting off the
-- village floor by `floorHalfX + 12 = 282.5` and `floorHalfZ + 12 = 242`, while this ring never
-- reaches 150 studs from the fountain -- not one planted tree can be here. Counted on the placed
-- map, the band 60..150 out holds 107 of the ARTIST'S own foliage children: 16 pines, 12 `Leaves`
-- meshes, 21 rocks and 19 unnamed canopy models between 32 and 76 studs tall and up to 60 wide.
--
-- A trunk merely brushing the footprint is left standing. `FELL_BITE` is how far inside a tree has
-- to be before felling it is the smaller of the two uglinesses.
local FELL_BITE = 6
local function fell(map, gx, gz, hw, keep)
	local n = 0
	for _, c in ipairs(map:GetChildren()) do
		if not keep[c] and MapCut.IsFoliage(c) then
			local pos, size = measure(c)
			if pos then
				local reach = hw + math.max(size.X, size.Z) / 2
				if reach - math.abs(pos.X - gx) >= FELL_BITE
					and reach - math.abs(pos.Z - gz) >= FELL_BITE then
					c:Destroy()
					n += 1
				end
			end
		end
	end
	return n
end

-- ===== THE CONTEXT THE TWO WORLD TESTS NEED =====
-- Lifted out of `Arrange` so a LATER pass can run the same tests -- see `MapSquare.FindSpot`. Every
-- slot's anchors are excluded whoever is asking, which is deliberate and older than this split: the
-- inter-group spacing is `taken`'s job, and a prop that measured its neighbour as a wall would find
-- nowhere on a ring three buildings already stand on.
--
-- THE MAP IS TAKEN FROM THE ZONE, NOT FROM AN ANCHOR, and that is a bug this file already shipped:
-- it reached the map through `MapAnchors.Get(zoneKey, "fountain").inst.Parent`, and `MapEggs` --
-- which runs immediately before -- DESTROYS the fountain. A destroyed instance has no parent, so
-- `map` came back nil, `ctx` was never built, and both world tests silently did nothing while the
-- search reported success. The shop went back on top of a house.
local function buildContext(zoneKey, zoneModel, extra)
	local map = zoneModel and zoneModel:FindFirstChild("VillageMap")
	if not map then return nil end

	local exclude = { workspace:FindFirstChild("Creatures"), map:FindFirstChild("HuntForest") }

	-- ===== AND THE MAP'S OWN WOOD IS EXCLUDED TOO, WHICH IS WHY THE RING OPENED UP (32.2) =====
	-- `MapForest` marks its 5,354 planted trees `CanQuery = false` so eight later searches are not
	-- flooded. The ARTIST'S trees carry no such flag, and until this line they broke `groundFault`
	-- in a way no reading of it would suggest: the ray starts 200 studs up, so on a wooded square it
	-- lands on a CANOPY, and `hit.Position.Y > FLAT_MAX` calls a canopy a roof.
	--
	-- Measured on the live build at the three ring radii: of 21 candidate spots probed around
	-- `upgrades`' asked-for bearing, five came back "roof" at y = 25.8, 25.9, 28.8, 34.7 and 38.2 --
	-- every one of them a part named `Top`, which is a tree. That is what pushed the shop onto the
	-- narrow probe at r = 108 and `upgrades` all the way out to r = 152, where the capture from the
	-- eggs cannot see it at all.
	--
	-- Excluding foliage here is not a relaxation, it is the same rule `occupied` already applies one
	-- test later: *trees are not an obstruction to a building, they are what it stands in* -- and
	-- since 32.2 they are also what it FELLS once it gets there. A house, a wall or a mannequin's
	-- hat still reads as a roof, which is the fault `groundFault` was written for.
	for _, c in ipairs(map:GetChildren()) do
		if MapCut.IsFoliage(c) then exclude[#exclude + 1] = c end
	end

	for _, slot in ipairs(SLOTS) do
		for _, role in ipairs(slot.roles) do
			local a = MapAnchors.Get(zoneKey, role)
			if a and a.inst then exclude[#exclude + 1] = a.inst end
		end
	end
	for _, inst in ipairs(extra or {}) do
		if inst then exclude[#exclude + 1] = inst end
	end

	local boxParams = OverlapParams.new()
	boxParams.FilterType = Enum.RaycastFilterType.Exclude
	boxParams.FilterDescendantsInstances = exclude
	-- 24 was enough while `hw` was the pad's 15.3. The group's own box is 30 wide, so the query is
	-- now 60 x 40 x 60 in a village that holds 107 foliage children on this ring alone -- and a
	-- TRUNCATED hit list is a silent "clear", because the one wall in it is the entry that fell off
	-- the end. `occupied` discards foliage only AFTER the engine has spent the budget on it.
	boxParams.MaxParts = 250
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = exclude
	return { map = map, dirt = MapPaint.DirtColour(map),
		boxParams = boxParams, rayParams = rayParams }
end

-- ===== AND THE RING WALK ITSELF =====
-- From the asked-for bearing outward, both ways, and the first spot that is clear wins. A caller
-- that finds nothing gets nil and is expected to leave its prop where the artist put it -- the map's
-- own arrangement is a working arrangement, and moving a building into a road is strictly worse than
-- not moving it.
--
-- `grows` is what the shops never had: if the whole ring is taken, step the RADIUS out and walk it
-- again. A one-dimensional search cannot solve a junction is the second rule in
-- `evolution-lab-relocating-a-prop`, and a ring at one radius is still one dimension.
local GROWS = { 0, 24, 48 }

--
-- ===== AND THE RADIUS IS TRIED BEFORE THE PROBE IS RELAXED, NOT AFTER (32.2) =====
-- `probes` is the full-box half-width followed by the pad's. The first cut of the two-tier walk ran
-- the STRICT probe over all three radii before the narrow one got a turn, and the boot log showed
-- what that buys: the shop settled at r = 108 on the narrow probe while `upgrades` was pushed all
-- the way out to r = 152 to keep the strict one. Two shopfronts 45 studs apart in depth is not a
-- ring, and the player standing at the eggs is the one who has to read it.
--
-- Being CLOSE TO THE CIRCLE is the thing she asked for; whether a barrel sits inside the far corner
-- of a building's own box is not. So the grow is the outer loop and the probe is the inner one. The
-- road test and the `taken` spacing never relax at either tier -- see `clearOfRoads`.
local function ringWalk(cx, cz, bearing, halfWidth, lanes, taken, ctx, probes)
	for _, grow in ipairs(GROWS) do
		local r = CIRCLE_R + halfWidth + VERGE + grow
		for tier, probe in ipairs(probes or { halfWidth }) do
			for step = 0, TRY_MAX do
				for _, dir in ipairs(step == 0 and { 1 } or { 1, -1 }) do
					local a = math.rad(bearing + dir * step * TRY_STEP)
					local tx, tz = cx + math.cos(a) * r, cz + math.sin(a) * r
					if clearOfRoads(tx, tz, halfWidth, lanes, taken, ctx, probe) then
						return a, tx, tz, tier
					end
				end
			end
		end
	end
	return nil
end

-- ===== WHAT THIS PASS PUT ON THE RING, KEPT AFTER IT ENDS =====
-- `MapAdventureBoard` is built long after `Arrange` has returned and stands on the same ring. Its
-- own search has to know where the shops ended up or it will ask for a bearing one of them is
-- already standing on -- which is the `taken` test doing its job, one pass too late.
MapSquare.Placed = {}

function MapSquare.Arrange(zoneKey, zoneModel)
	if not MapAnchors.IsMapped(zoneKey) then return 0 end

	-- The square's centre is the fountain's old spot, which is where the eggs now stand. `MapEggs`
	-- destroys the fountain instance but the registry entry survives with its measured position --
	-- and that is deliberately what both files key off, so "the middle of the square" is one
	-- coordinate the map itself chose rather than a number either file typed.
	local centre = MapAnchors.Get(zoneKey, "fountain")
	if not centre then
		warn("[MapSquare] " .. zoneKey .. ": no fountain anchor -- the square was left as it was")
		return 0
	end
	local cx, cz = centre.pos.X, centre.pos.Z

	local map = zoneModel and zoneModel:FindFirstChild("VillageMap")
	local lanes = villageLanes()

	-- ===== PASS ONE: WHAT EACH GROUP IS, AND WHAT STANDS WITH IT =====
	-- Everything a group carries has to be known BEFORE `ctx` is built, or a shop's own counter
	-- comes back out of `occupied` as the wall blocking its own move. And a companion claimed by one
	-- group must not be claimed by the next, so the map is walked once here rather than per slot.
	local anchored = anchorSet(zoneKey)
	local claimed, carried, plans = {}, {}, {}
	for _, slot in ipairs(SLOTS) do
		-- Every anchor in the group that actually exists. `shopHouse` is absent on a map that ships
		-- no building, and a group of one is still a group.
		local group = {}
		for _, role in ipairs(slot.roles) do
			local anchor = MapAnchors.Get(zoneKey, role)
			if anchor and anchor.inst and anchor.inst.Parent then
				group[#group + 1] = anchor.inst
			end
		end

		-- `local pos, size = lead and measure(lead)` is what this said on its first boot, and it
		-- moved nothing while reporting no error: an `and` expression TRUNCATES a multiple return to
		-- one value, so `size` was always nil and the test below could never pass. Luau compiles it
		-- happily. The guard is a statement now, which is the only shape that keeps both returns.
		local lead = group[1]
		if lead then
			local lx, lz, lhw = groupFootprint({ lead })
			if lx then
				local mates = map and companionsOf(map, lx, lz, lhw, anchored, claimed) or {}
				for _, mate in ipairs(mates) do
					claimed[mate] = true
					carried[#carried + 1] = mate
					group[#group + 1] = mate
				end

				-- ===== THE FRONT IS MEASURABLE, AND IT WAS SITTING UNUSED =====
				-- Nothing records which way a hand-authored prop faces, so this file never computed
				-- an absolute yaw -- see the header. But `MapAnchors` publishes the pad and its
				-- building SEPARATELY, and the pad is by construction the plate you stand on IN
				-- FRONT OF the counter, so `pad - house` is the shopfront's facing MEASURED off the
				-- map rather than guessed at.
				--
				-- Settled with a capture before it was written, because the models' own convention
				-- disagrees with itself: `Upgrades`' building has a LookVector pointing exactly AWAY
				-- from the fountain (dot -0.993) while `Shop`'s points exactly at it (+0.987), and
				-- the screenshot from the eggs shows BOTH DOORS facing the middle. `pad - house`
				-- agrees with the fountain direction for both (0.996 and 0.955); the LookVector is a
				-- coin toss, which is the whole of `roblox-model-facing-and-scaling`'s warning.
				--
				-- AND A LONE PAD IS NOT ALWAYS FRONTLESS. `potions` has no `potionsHouse` -- it is a
				-- pad on its own in `MapAnchors.SINGLE` -- but the proximity pass hands it five
				-- `Meshes/Sell*` counters standing 2..6 studs BEHIND it, further out from the
				-- fountain than the pad is. That is the same geometry as a pad and its building, so
				-- the same rule reads it: the front is the pad minus the centre of what stands with
				-- it. Only when nothing stands with it at all is there no measurable front, and only
				-- then does the relative rule below get used.
				local front = nil
				local houseRole = slot.roles[2]
				local house = houseRole and MapAnchors.Get(zoneKey, houseRole) or nil
				local padPos = measure(lead)
				local behind = nil
				if house and house.inst and house.inst.Parent then
					behind = measure(house.inst)
				elseif #mates > 0 then
					local sx, sz, n = 0, 0, 0
					for _, mate in ipairs(mates) do
						local mp = measure(mate)
						if mp then sx, sz, n = sx + mp.X, sz + mp.Z, n + 1 end
					end
					if n > 0 then behind = Vector3.new(sx / n, 0, sz / n) end
				end
				if padPos and behind then
					local dx, dz = padPos.X - behind.X, padPos.Z - behind.Z
					if dx * dx + dz * dz > 1 then front = math.atan2(dz, dx) end
				end

				-- Re-measured WITH the companions: a counter standing behind a pad is part of what
				-- has to fit on the ring, and the spot is chosen for the whole group or for none.
				local px, pz, phw = groupFootprint(group)
				plans[#plans + 1] = { slot = slot, group = group, front = front, leadHw = lhw,
					x = px, z = pz, hw = phw, mates = #mates }
			end
		end
	end

	-- The felling must never eat a declared anchor or a carried companion. Neither classifies as
	-- foliage today, but `MapCut.IsFoliage` reads PART names -- its own header says a prop whose
	-- parts are all Top / Bottom / Leaves / Branch is foliage to it whatever it actually is -- so
	-- the set that must survive is stated rather than assumed.
	local keep = {}
	for inst in pairs(anchored) do keep[inst] = true end
	for inst in pairs(claimed) do keep[inst] = true end

	local ctx = buildContext(zoneKey, zoneModel, carried)

	local taken = {}
	MapSquare.Placed = taken
	local moved, felled, carriedN, report, stuck = 0, 0, #carried, {}, {}
	for _, plan in ipairs(plans) do
		local hw = plan.hw

		-- ===== A GROUP ALREADY OUT ON THE RING AND CLEAR IS NOT MOVED AGAIN (30.32) =====
		-- Every test below is a test of a SPOT, so the spot the group is standing on can be put to
		-- them like any other. If it passes, the ring walk is not run at all. That is what stops the
		-- village rearranging itself a little differently on each boot -- `Arrange` was not
		-- idempotent, and a pass that reads the world and then changes it has to be, or its own
		-- second run measures a world its first run made.
		--
		-- AND CLEAR IS NOT ENOUGH ON ITS OWN, which is the trap this nearly shipped with. The
		-- artist's own arrangement is mostly clear ground -- that is why she could walk it -- so
		-- "clear, therefore leave it" would quietly cancel the whole file: measured, all three
		-- groups sit 63..67 studs from the middle, INSIDE the circle they are supposed to ring. So
		-- the spot also has to already BE on the ring, and the test for that is the bare radius
		-- rather than the exact one, because `ringWalk` is allowed to step the radius outward and a
		-- group it pushed out to 112 must not be dragged back.
		--
		-- IT IS NO LONGER A `continue`, and that is 32.2's half of it: the kept branch skipped
		-- straight past the rotation, so a group the artist left facing the wood stayed facing the
		-- wood for ever. A kept group is turned in place -- the transform below is the same one,
		-- with the translation cancelling out.
		-- The pad's own half-width, which is the NARROWEST honest probe: it is the part of the group
		-- a player has to be able to walk up to.
		local leadHw = plan.leadHw or hw

		local kept = math.sqrt((plan.x - cx) ^ 2 + (plan.z - cz) ^ 2) >= CIRCLE_R + hw
			and clearOfRoads(plan.x, plan.z, hw, lanes, taken, ctx)

		-- WALK THE RING FROM THE ASKED-FOR BEARING OUTWARD, both ways, and take the first spot that
		-- is clear. A group that finds nowhere is LEFT WHERE THE ARTIST PUT IT and said so in the
		-- log -- the map's own arrangement is a working arrangement, and moving a shop into a road
		-- is strictly worse than not moving it.
		--
		-- TWO PROBES, widest first, and `ringWalk` tries both at each radius before it grows. The
		-- narrow one is what stops an honest footprint reading as "nowhere is clear": the group
		-- still stands clear of every lane and of every other group, it is simply allowed to have a
		-- fence or a barrel inside the far corner of its own box. Being left inside the circle is
		-- strictly worse than that, and 30.32 is the row where that outcome shipped for two groups
		-- out of three.
		local want, wantX, wantZ, tier
		if kept then
			wantX, wantZ = plan.x, plan.z
			want = math.atan2(plan.z - cz, plan.x - cx)
			tier = 0
		else
			local probes = leadHw < hw and { hw, leadHw } or { hw }
			want, wantX, wantZ, tier = ringWalk(cx, cz, plan.slot.bearing, hw, lanes, taken,
				ctx, probes)
		end

		--
		-- ===== A GROUP THAT CANNOT MOVE IS STILL TURNED (32.2) =====
		-- "Nowhere on the ring is clear" is an answer about a SPOT, and it says nothing at all about
		-- which way the thing is facing. Both the old code and the first cut of this one dropped a
		-- stuck group without touching its yaw, so the one group the search could not help stayed
		-- exactly as wrong as it was -- and on this map that group is the potion stall, 37 loose
		-- pieces of counter and its pad.
		--
		-- Turning it in place cannot make the road fault it was being protected from: a yaw about
		-- the group's own box centre leaves every part inside the same circle of radius `hw`, and
		-- `hw` is the radius every lane test above was run at. The move is free; only the position
		-- was ever in question.
		if not want then
			stuck[#stuck + 1] = ("%s (hw %.0f, %d carried)")
				:format(plan.slot.roles[1], hw, plan.mates)
			if plan.front then
				local spin = plan.front - math.atan2(cz - plan.z, cx - plan.x)
				local pivot = CFrame.new(plan.x, 0, plan.z)
					* CFrame.Angles(0, spin, 0)
					* CFrame.new(-plan.x, 0, -plan.z)
				for _, inst in ipairs(plan.group) do
					inst:PivotTo(pivot * inst:GetPivot())
				end
				report[#report + 1] = ("%s x%d(+%d) turned in place %.0f deg")
					:format(plan.slot.roles[1], #plan.group - plan.mates, plan.mates,
						math.deg(spin))
			end
		else
			taken[#taken + 1] = { x = wantX, z = wantZ, hw = hw, id = plan.slot.roles[1] }

			-- ===== THE TURN, AND THE SIGN THAT HAS BEEN INVERTED SINCE THIS FILE SHIPPED =====
			-- `CFrame.Angles(0, t, 0)` LOWERS a bearing read as `atan2(z, x)` by `t`. Measured in
			-- the place rather than reasoned about, because that is the entire question: a point at
			-- bearing 0 turned by +30 comes back at -30, and the identity LookVector's own bearing
			-- goes -90 -> -120. The old line fed `turn = want - atan2(dz, dx)` straight into
			-- `Angles`, so a group walked D degrees round the ring had its facing turned -D. The
			-- facing error is TWICE the distance it travelled, and it IS her *"shops face away"*:
			-- the artist's arrangement already faces the middle, and this file is what broke it.
			--
			-- With a measured front there is no difference to take at all. Turn the front onto the
			-- direction from the group's new spot to the middle and the answer is absolute, which is
			-- also what makes the kept branch worth running. A lone pad with no building behind it
			-- has no measurable front and keeps the relative rule -- correct now the sign is round
			-- the right way, and a no-op for a group that did not move.
			local turn = 0
			if plan.front then
				turn = plan.front - math.atan2(cz - wantZ, cx - wantX)
			else
				local dx, dz = plan.x - cx, plan.z - cz
				if dx * dx + dz * dz > 1 then turn = math.atan2(dz, dx) - want end
			end

			-- ONE TRANSFORM, APPLIED TO THE WHOLE GROUP -- pad, building, and everything the
			-- proximity pass handed it. Built about the group's own box CENTRE so every piece keeps
			-- its exact offset from every other; doing this per prop about each one's own centre
			-- would rotate the house about itself and leave it beside the pad at the wrong angle.
			-- `y` is 0 on both ends of the sandwich, so a yaw cannot lift anything.
			local move = CFrame.new(wantX, 0, wantZ)
				* CFrame.Angles(0, turn, 0)
				* CFrame.new(-plan.x, 0, -plan.z)
			for _, inst in ipairs(plan.group) do
				inst:PivotTo(move * inst:GetPivot())
			end

			local cut = map and fell(map, wantX, wantZ, hw, keep) or 0
			felled += cut
			if not kept then moved += #plan.group end
			report[#report + 1] =
				("%s x%d(+%d)%s %s(%.0f,%.0f)->(%.0f,%.0f) r%.0f turn %.0f hw %.0f fell %d")
				:format(plan.slot.roles[1], #plan.group - plan.mates, plan.mates,
					plan.front and "" or " NOFRONT",
					tier == 0 and "kept " or (tier == 2 and "narrow " or ""),
					plan.x, plan.z, wantX, wantZ,
					math.sqrt((wantX - cx) ^ 2 + (wantZ - cz) ^ 2),
					math.deg(turn), hw, cut)
		end
	end

	print(("[MapSquare] %s: %d props moved in %d of %d groups ringed about (%.0f, %.0f); %d carried, %d felled -- %s%s")
		:format(zoneKey, moved, #SLOTS - #stuck, #SLOTS, cx, cz, carriedN, felled,
			table.concat(report, "; "),
			#stuck > 0 and ("  LEFT WHERE THEY WERE (no clear bearing): "
				.. table.concat(stuck, ", ")) or ""))
	return moved
end

--- Where a NEW thing of half-width `hw` can stand on the square's ring, asking for `bearing` and
--- walking outward from it. Returns `x, z, angle, cx, cz` -- the spot, the bearing it landed on, and
--- the square's centre, which is what a caller needs to turn its prop to face the middle.
---
--- Returns nil when the whole ring is taken, and a caller is expected to fall back to its own
--- authored spot rather than dropping its prop on a road anyway.
---
--- `exclude` is the caller's own instances: a prop must never measure itself as the thing blocking
--- its own move. Anything placed here JOINS `MapSquare.Placed`, so two late callers cannot pick the
--- same bearing.
function MapSquare.FindSpot(zoneKey, zoneModel, bearing, hw, exclude)
	if not MapAnchors.IsMapped(zoneKey) then return nil end
	local centre = MapAnchors.Get(zoneKey, "fountain")
	if not centre then return nil end

	local cx, cz = centre.pos.X, centre.pos.Z
	local ctx = buildContext(zoneKey, zoneModel, exclude)
	local a, x, z = ringWalk(cx, cz, bearing, hw, villageLanes(), MapSquare.Placed, ctx)
	if not a then return nil end

	MapSquare.Placed[#MapSquare.Placed + 1] = { x = x, z = z, hw = hw, id = "found" }
	return x, z, a, cx, cz
end

return MapSquare
