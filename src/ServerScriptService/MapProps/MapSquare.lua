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
-- ===== THE ROTATION IS RELATIVE, AND THAT IS THE WHOLE TRICK =====
-- These are hand-authored props and nothing records which way their fronts face. A yaw computed
-- from scratch is a guess, and `roblox-model-facing-and-scaling` is the standing note about what
-- guessing costs -- a quarter turn faces -X, not +X. So no absolute facing is ever computed here.
-- Each prop is turned by **the change in its own bearing about the square's centre**: if it faced
-- the middle before it faces the middle after, and if it did not, it is no worse than it was. That
-- is true whatever the artist's convention was, without this file knowing it.
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
local function clearOfRoads(x, z, hw, lanes, taken, ctx)
	for _, lane in ipairs(lanes) do
		if distToLane(x, z, lane) < lane.half + hw + ROAD_VERGE then return false end
	end
	for _, t in ipairs(taken) do
		if math.sqrt((x - t.x) ^ 2 + (z - t.z) ^ 2) < t.hw + hw + VERGE then return false end
	end
	if ctx then
		if groundFault(x, z, ctx) then return false end
		if occupied(x, z, hw, ctx.map, ctx.boxParams) then return false end
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
	boxParams.MaxParts = 24
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

local function ringWalk(cx, cz, bearing, halfWidth, lanes, taken, ctx)
	for _, grow in ipairs(GROWS) do
		local r = CIRCLE_R + halfWidth + VERGE + grow
		for step = 0, TRY_MAX do
			for _, dir in ipairs(step == 0 and { 1 } or { 1, -1 }) do
				local a = math.rad(bearing + dir * step * TRY_STEP)
				local tx, tz = cx + math.cos(a) * r, cz + math.sin(a) * r
				if clearOfRoads(tx, tz, halfWidth, lanes, taken, ctx) then
					return a, tx, tz
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

	local lanes = villageLanes()

	local ctx = buildContext(zoneKey, zoneModel)

	local taken = {}
	MapSquare.Placed = taken
	local moved, report, stuck = 0, {}, {}
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
			local pos, size = measure(lead)
			if pos and size then
				local halfWidth = math.max(size.X, size.Z) / 2

				-- ===== A GROUP ALREADY OUT ON THE RING AND CLEAR IS NOT MOVED AGAIN (30.32) =====
				-- Every test below is a test of a SPOT, so the spot the prop is standing on can be
				-- put to them like any other. If it passes, the ring walk is not run at all. That is
				-- what stops the village rearranging itself a little differently on each boot --
				-- `Arrange` was not idempotent, and a pass that reads the world and then changes it
				-- has to be, or its own second run measures a world its first run made.
				--
				-- AND CLEAR IS NOT ENOUGH ON ITS OWN, which is the trap this nearly shipped with.
				-- The artist's own arrangement is mostly clear ground -- that is why she could walk
				-- it -- so "clear, therefore leave it" would quietly cancel the whole file: measured,
				-- all three groups sit 63..67 studs from the middle, INSIDE the circle they are
				-- supposed to ring. So the spot also has to already BE on the ring, and the test for
				-- that is the bare radius rather than the exact one, because `ringWalk` is allowed to
				-- step the radius outward and a prop it pushed out to 112 must not be dragged back.
				local onRing = math.sqrt((pos.X - cx) ^ 2 + (pos.Z - cz) ^ 2) >= CIRCLE_R + halfWidth
				if onRing and clearOfRoads(pos.X, pos.Z, halfWidth, lanes, taken, ctx) then
					taken[#taken + 1] = { x = pos.X, z = pos.Z, hw = halfWidth, id = slot.roles[1] }
					report[#report + 1] = ("%s x%d kept (%.0f,%.0f)")
						:format(slot.roles[1], #group, pos.X, pos.Z)
					continue
				end

				-- WALK THE RING FROM THE ASKED-FOR BEARING OUTWARD, both ways, and take the first
				-- spot that is clear. A group that finds nowhere is LEFT WHERE THE ARTIST PUT IT and
				-- said so in the log -- the map's own arrangement is a working arrangement, and
				-- moving a shop into a road is strictly worse than not moving it.
				local want, wantX, wantZ = ringWalk(cx, cz, slot.bearing, halfWidth, lanes, taken, ctx)

				if not want then
					stuck[#stuck + 1] = slot.roles[1]
				else
					taken[#taken + 1] = { x = wantX, z = wantZ, hw = halfWidth, id = slot.roles[1] }

				-- The bearing the group currently sits at, so the turn is the DIFFERENCE. A prop
				-- standing on the centre has no bearing and is left unturned rather than spun by a
				-- meaningless angle.
				local dx, dz = pos.X - cx, pos.Z - cz
				local turn = 0
				if dx * dx + dz * dz > 1 then
					turn = want - math.atan2(dz, dx)
				end

				-- ONE TRANSFORM, APPLIED TO THE WHOLE GROUP. Built about the lead prop's own position
				-- so the house keeps its exact offset from the pad: take everything into the lead's
				-- frame, turn it, and put it down at the target. Doing this per prop with each one's own
				-- centre would rotate the house about itself and leave it beside the pad at the wrong
				-- angle.
				local move = CFrame.new(wantX, pos.Y, wantZ)
					* CFrame.Angles(0, turn, 0)
					* CFrame.new(-pos.X, -pos.Y, -pos.Z)
				for _, inst in ipairs(group) do
					inst:PivotTo(move * inst:GetPivot())
				end

				moved += #group
				report[#report + 1] = ("%s x%d (%.0f,%.0f)->(%.0f,%.0f) at %.0f deg")
					:format(slot.roles[1], #group, pos.X, pos.Z, wantX, wantZ, math.deg(want))
				end
			end
		end
	end

	print(("[MapSquare] %s: %d props in %d of %d groups ringed about (%.0f, %.0f) -- %s%s")
		:format(zoneKey, moved, #SLOTS - #stuck, #SLOTS, cx, cz,
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
