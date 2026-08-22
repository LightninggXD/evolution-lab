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
local function occupied(x, z, hw, map, params)
	local hits = workspace:GetPartBoundsInBox(CFrame.new(x, 20, z), Vector3.new(hw * 2, 40, hw * 2),
		params)
	for _, part in ipairs(hits) do
		if part.Size.Y >= BLOCKER_MIN_H then
			-- climb to the top-level child of the map, which is what the classifier reads
			local top = part
			while top.Parent and top.Parent ~= map do top = top.Parent end
			if top.Parent == map and not MapCut.IsFoliage(top) then return true end
		end
	end
	return false
end

-- True when the ground here is the artist's own painted path. A building on it is the same fault as
-- a building in a generated lane; the map's road network simply is not expressed as coordinates
-- anywhere, so it is read off the surface instead.
local function onArtistDirt(x, z, dirt, rayParams)
	local hit = workspace:Raycast(Vector3.new(x, 200, z), Vector3.new(0, -400, 0), rayParams)
	if not hit then return false end
	local c = hit.Instance.Color
	return math.abs(c.R - dirt.R) + math.abs(c.G - dirt.G) + math.abs(c.B - dirt.B)
		< DIRT_TOLERANCE
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
		if onArtistDirt(x, z, ctx.dirt, ctx.rayParams) then return false end
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

	-- Everything the two world tests need, resolved once. The shop's own group is excluded from both
	-- -- a prop must never measure itself as the thing blocking its own move.
	--
	-- THE MAP IS TAKEN FROM THE ZONE, NOT FROM AN ANCHOR, and that is a bug this file already
	-- shipped: it reached the map through `MapAnchors.Get(zoneKey, "fountain").inst.Parent`, and
	-- `MapEggs` -- which runs immediately before -- DESTROYS the fountain. A destroyed instance has
	-- no parent, so `map` came back nil, `ctx` was never built, and both world tests silently did
	-- nothing while the search reported success. The shop went back on top of a house.
	local map = zoneModel and zoneModel:FindFirstChild("VillageMap")
	local ctx = nil
	if map then
		local exclude = { workspace.Creatures, map:FindFirstChild("HuntForest") }
		for _, slot in ipairs(SLOTS) do
			for _, role in ipairs(slot.roles) do
				local a = MapAnchors.Get(zoneKey, role)
				if a and a.inst then exclude[#exclude + 1] = a.inst end
			end
		end
		local boxParams = OverlapParams.new()
		boxParams.FilterType = Enum.RaycastFilterType.Exclude
		boxParams.FilterDescendantsInstances = exclude
		boxParams.MaxParts = 24
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = exclude
		ctx = { map = map, dirt = MapPaint.DirtColour(map),
			boxParams = boxParams, rayParams = rayParams }
	end

	local taken = {}
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
				local r = CIRCLE_R + halfWidth + VERGE

				-- WALK THE RING FROM THE ASKED-FOR BEARING OUTWARD, both ways, and take the first
				-- spot that is clear. A group that finds nowhere is LEFT WHERE THE ARTIST PUT IT and
				-- said so in the log -- the map's own arrangement is a working arrangement, and
				-- moving a shop into a road is strictly worse than not moving it.
				local want, wantX, wantZ = nil, nil, nil
				for step = 0, TRY_MAX do
					for _, dir in ipairs(step == 0 and { 1 } or { 1, -1 }) do
						local a = math.rad(slot.bearing + dir * step * TRY_STEP)
						local tx, tz = cx + math.cos(a) * r, cz + math.sin(a) * r
						if clearOfRoads(tx, tz, halfWidth, lanes, taken, ctx) then
							want, wantX, wantZ = a, tx, tz
							break
						end
					end
					if want then break end
				end

				if not want then
					stuck[#stuck + 1] = slot.roles[1]
				else
					taken[#taken + 1] = { x = wantX, z = wantZ, hw = halfWidth }

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

return MapSquare
