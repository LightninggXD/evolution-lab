-- MapProps/MapGates -- the three roads OUT of the village, and the cut that makes them roads.
--
-- Her words, 2026-08-22: *"samo malo vise napravi da se moze doci do creatura od modela onog tj
-- glavne mape"*. Not the jungle -- 31.16 built that and a BFS reached 20 of 20 camps -- but the
-- step BEFORE it: getting out of the village at all.
--
-- ===== WHAT WAS ACTUALLY WRONG, MEASURED BEFORE ANYTHING WAS BUILT =====
-- The SOUTHERN HALF OF THE VILLAGE IS SOLID WOOD, with collision on, and it is the same fault
-- 30.19 found in the northern half and fixed there and only there. A body box walked south from the
-- fountain is blocked 9 cells of 19; at x = -60 the run z -80..-180 is one unbroken canopy, at
-- x = 140 the run z -40..-120 is another. The north got `cutEntrance`; the south, west and east
-- never got anything, so the village is a room with one door.
--
-- **This is why every walkability probe in the repo passed while the complaint was true.** A BFS
-- winds; 31.18's reached 16,912 cells and called the world open. A player does not wind. A player
-- faces the direction they want to go and walks into a tree, and there is no grid in this project
-- that measures that.
--
-- ===== WHY THE TWO FLANK LANES ARE AT z = -100 AND NOT AT z = 0 =====
-- `JungleLayout` puts its side gates at (+/-270, 0), which is the village's own edge, and running
-- the village half of those lanes along z = 0 was the obvious plan. Measured, it is impossible:
-- the PORTAL RING sits at zone (-201, 15) with a radius of 45, and the LEADERBOARD RING at
-- (137, 7) with a radius of 33.5. Both halls stand INSIDE the village, right where a flank road
-- would run, and both are 31.12 / 31.17 work that is not moving. A lane search over z -200..+80
-- reads it plainly -- at z = 0 a west lane meets 27 props it must not cut, and at z = -100 it meets
-- ZERO. Both flanks are pure foliage at z = -100, so that is where they go, and `JungleLayout`'s
-- two side-gate trunks are moved to meet them rather than the lanes being bent to reach the trunks.
--
-- ===== IT IS A T, NOT THREE SEPARATE ROADS =====
-- One road leaves the square heading south and the flanks branch off it at (0, -100). Three roads
-- that each begin somewhere in the woods are three roads nobody finds; a junction you walk into is
-- a decision you can see. It also means all three share one surface height, so the network cannot
-- develop a step in the middle of itself.
--
-- Nothing here collides -- same rule as the jungle paths and the approach road, and for the reason
-- `MapPaint` gives: a road you can trip on is worse than no road.

local MapPaint = require(script.Parent.MapPaint)
local PathSplines = require(script.Parent.PathSplines)
local MapCut = require(script.Parent.MapCut)
-- 32.4: this file MOVES anchors now, so it has to tell the census it did. See `MapAnchors.Remeasure`.
local MapAnchors = require(script.Parent.MapAnchors)

local MapGates = {}

local FOLDER_NAME = "VillageGates"

-- ===== THE NETWORK =====
-- Zone-relative. `half` is the CUT's half-width (how much wood comes down) and `w` is the PAINT's
-- width, and they are deliberately different: the cut has to be wider than the road or the road is
-- a slot with two walls of canopy leaning into it, which is 30.19's note about why the entrance
-- funnel clears further than it paves.
--
-- South starts at z = -30 and not at the fountain: the Fountain is a 44 x 44 prop whose south face
-- is about z = -22, and paint run under a solid prop is paint nobody sees. It ends at z = -262,
-- past the village floor edge (-230) and overlapping the head of `JungleLayout`'s main lane at
-- -240, so the two networks meet rather than stopping short of each other.
local LANES = {
	{ id = "South", x1 = 0, z1 = -30, x2 = 0, z2 = -262, halfA = 32, halfB = 34, wA = 56, wB = 52 },
	{ id = "West", x1 = 0, z1 = -100, x2 = -286, z2 = -100, halfA = 30, halfB = 30, wA = 46, wB = 44 },
	{ id = "East", x1 = 0, z1 = -100, x2 = 286, z2 = -100, halfA = 30, halfB = 30, wA = 46, wB = 44 },
}

-- The DRIVING LINE: what has to be actually empty, as opposed to what the cut clears. A prop the
-- cut refused to remove is furniture, and furniture at the verge of a road is a village -- the
-- market stalls, the Shop counter and the daily-spin wheel all end up standing along these lanes
-- and every one of them reads better there than where it was. A prop INSIDE this half-width is a
-- building in the middle of the road, and that is the only thing this file relocates.
-- 24 and not 20, and the four studs are measured. At 20 the walk down each finished lane was still
-- stopped by trees whose perpendicular reach reads 20.5, 21.5, 24.0 and 24.5 -- every one of them
-- standing right on the boundary, because a threshold always collects the cases that sit on it.
-- 24 puts 48 studs of guaranteed clear ground under a 9-stud body on a road painted 52 to 56 wide,
-- which leaves the outermost few studs of paint to the leaning canopy that makes it a road.
-- Published, because 30.31 needs it: `MapSquare` moves buildings around the square and has to know
-- where the roads are. A second copy of these three lanes in that file is
-- `evolution-lab-zone-geometry-constants` word for word -- and the fault it would ship is precisely
-- the one the owner photographed, a shop standing in a road.
MapGates.LANES = LANES
MapGates.CLEAR_HALF = 24

local CLEAR_HALF = 24
-- Nothing above knee height stands on the driving line, against the 5-stud floor the verge keeps.
-- See the note on `MapCut.LaneFootprint`: a 3-stud rock on the centre line survived two passes.
local DRIVE_MIN_HEIGHT = 2

local TOP = 0.80       -- clears the map's 0.6-stud ground union, well under the props' feet
local THICK = 1.4      -- depth, not height: the same one-slab-three-floors trick `MapRoad` uses
local EDGE_TOP = 0.72  -- the dark rim: WIDER and LOWER, never taller (a taller shell is a blob)
local EDGE_W = 6
local EDGE_SHADE = 0.42
local QUADS = 8

-- ===== FINDING SOMEWHERE ELSE FOR A BUILDING THAT IS IN THE ROAD =====
-- Searched, not typed. `evolution-lab-placement-search-ordering` is the standing note that a clear
-- spot chosen from a coordinate only knows the world that existed when somebody wrote it down --
-- the Splicer ended up inside the event board that way -- so the offset is measured at build time,
-- after the cut has run, against the map as it actually stands.
--
-- ===== THE FIRST CUT OF THIS FUNCTION MOVED THINGS FROM ONE ROAD INTO ANOTHER =====
-- Kept, because the shape of the mistake is why the rest of the file is written this way, and the
-- boot log is the only thing that ever said so. Three faults, one line each:
--
--   1. IT MEASURED FROM THE PROP, NOT FROM THE LANE. A fence 20 studs east of the centre line was
--      pushed 33 studs west and landed at x = -13 -- still inside a road whose driving line is 20
--      studs wide. An offset applied to where a thing already is only clears the road when the
--      thing started at the edge of it. Candidates are measured from the CENTRE LINE now.
--   2. IT ONLY KNEW ITS OWN LANE. This is a T: the flanks branch off the south road. The east
--      lane's normal is the z axis, so it dutifully moved `Spawn` from (5, -116) to (5, -231) --
--      out of the east lane and 115 studs straight DOWN the south one. A candidate is checked
--      against every lane in the network, not against the one that objected.
--   3. IT REPORTED PER LANE, IN LANE ORDER. South ran first, failed to place five props and
--      printed them as stuck; west and east then moved three of those five. The log named props
--      that were fine by the end of the same boot. Cut everything first, place once, report last.

-- How far off a lane's centre line a prop of half-width `hw` has to stand to be out of the road.
local function reachFor(hw)
	return CLEAR_HALF + hw + 8
end

-- The perpendicular distance from `(x, z)` to `lane`, plus the closest point on it. `t` is CLAMPED
-- here and deliberately NOT clamped in `MapCut.Lane`: the cut asks "is this prop between the two
-- ends", which a clamp answers wrongly for everything past them, while this asks "how far from the
-- road is it", for which the road's own end is the nearest bit of road there is.
local function offsetFrom(lane, x, z)
	local dx, dz = lane.x2 - lane.x1, lane.z2 - lane.z1
	local len2 = dx * dx + dz * dz
	local t = math.clamp(((x - lane.x1) * dx + (z - lane.z1) * dz) / len2, 0, 1)
	local qx, qz = lane.x1 + dx * t, lane.z1 + dz * t
	return math.sqrt((x - qx) ^ 2 + (z - qz) ^ 2), qx, qz
end

-- Which lane, if any, a prop of half-width `hw` standing at `(x, z)` is blocking.
local function roadAt(x, z, hw)
	for _, lane in ipairs(LANES) do
		local d = offsetFrom(lane, x, z)
		if d <= CLEAR_HALF + hw then return lane end
	end
	return nil
end

-- ===== A PERPENDICULAR WALK CANNOT SOLVE A JUNCTION, AND THE BOOT LOG SAID SO =====
-- The version before this one offered candidates along the offending lane's normal only. It placed
-- four props of eight and left three, and the three it left were all standing at or near the T at
-- (0, -100) -- `Spawn` among them, a 33-stud building in the middle of the crossroads. The reason
-- is arithmetic rather than bad luck: sliding a prop sideways out of the SOUTH lane keeps its z at
-- about -116, and every point at that z within 36 studs of z = -100 is inside the two FLANK lanes.
-- There is no offset along one axis that leaves all three roads, so a one-dimensional search can
-- only ever fail there, and it fails exactly where a building is most in the way.
--
-- So the candidates are a RING around the prop, opening at the shortest move that could clear the
-- road and widening in 14-stud steps, and the first angle tried is straight out from the lane on
-- the side the prop is already on -- which is the old behaviour, kept as the preferred answer
-- rather than as the only one. `roadAt` is what actually guarantees the result, so measuring the
-- radius from the prop (the shortest move) is safe in a way that fault 1 above was not.
local function relocate(map, prop, cx, lane, px, pz, size)
	local dx, dz = lane.x2 - lane.x1, lane.z2 - lane.z1
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1 then return nil end
	local nx, nz = -dz / len, dx / len            -- unit normal to the lane
	local hw = math.max(size.X, size.Z) / 2
	local d0, qx, qz = offsetFrom(lane, px, pz)

	local side = 1
	if d0 > 0.5 then
		side = ((px - qx) * nx + (pz - qz) * nz) >= 0 and 1 or -1
	end
	local base = math.atan2(nz * side, nx * side)

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { prop }

	-- radius first, then angle: the nearest spot that works wins, whichever way it lies
	for step = 0, 6 do
		local r = reachFor(hw) + step * 14
		for k = 0, 6 do
			for _, sgn in ipairs(k == 0 and { 1 } or { 1, -1 }) do
				local ang = base + sgn * k * (math.pi / 6)
				local tx, tz = px + math.cos(ang) * r, pz + math.sin(ang) * r
				if not roadAt(tx, tz, hw) then
				-- The box starts a stud above the ground and is the prop's own footprint plus a
				-- margin. `probe-body-box-counts-the-floor` is why it starts above: a box that
				-- spans the deck it stands on counts the deck as an obstacle and calls clear
				-- ground blocked.
				local box = CFrame.new(cx + tx, 2 + size.Y / 2, tz)
				local blocked, wood = false, {}
				for _, hit in ipairs(workspace:GetPartBoundsInBox(box,
					Vector3.new(size.X + 8, size.Y, size.Z + 8), params)) do
					if hit.CanCollide and (hit.Position.Y + hit.Size.Y / 2) > 2.0 then
						-- TREES ARE NOT AN OBSTRUCTION TO A BUILDING, THEY ARE WHAT IT STANDS IN.
						-- The first ring search placed six props of eight and left `Spawn` -- a
						-- 33-stud building on the T at (0, -100) -- with the report saying it had
						-- nowhere to go. It had plenty of somewhere: every candidate that cleared
						-- all three roads landed in the southern wood, and the wood is collidable,
						-- so a plain box test calls the whole village solid. A prop is only really
						-- stuck when something that is NOT foliage is in the way, and the trees it
						-- lands on come down -- the same trade `MapRidge` makes for a mountain.
						local anc = hit
						while anc.Parent and anc.Parent ~= map do anc = anc.Parent end
						if anc.Parent == map and MapCut.IsFoliage(anc) then
							wood[anc] = true
						else
							blocked = true
							break
						end
					end
				end
				if not blocked then
					local felled = 0
					for tree in pairs(wood) do
						tree:Destroy()
						felled += 1
					end
					return tx, tz, felled
				end
				end
			end
		end
	end
	return nil
end

function MapGates.Build(zoneKey, cx, map, protected)
	if not map then return 0 end

	local old = map:FindFirstChild(FOLDER_NAME)
	if old then old:Destroy() end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = map

	local dirt = MapPaint.DirtColour(map)
	local edge = MapPaint.Shade(dirt, EDGE_SHADE)

	-- ===== PASS 1: CUT EVERY LANE =====
	-- All of them, before anything is placed. Fault 3 above is what happens when the passes
	-- interleave: a prop the south lane could not place is a prop the east lane has not looked at
	-- yet, and the two together produce a log that contradicts the world it describes.
	local totalCut = 0
	local leftovers, seen = {}, {}
	for _, lane in ipairs(LANES) do
		local cut, stay = MapCut.Lane(map, cx, lane, protected)
		-- and the narrow footprint pass over the driving line, which is what actually makes the
		-- lane walkable -- see the note on `MapCut.LaneFootprint`. Run second, so the cheap centre
		-- test has already taken the bulk of the wood.
		cut += MapCut.LaneFootprint(map, cx, lane, CLEAR_HALF, protected, DRIVE_MIN_HEIGHT)
		totalCut += cut
		for _, s in ipairs(stay) do
			-- The lanes meet, so the same prop can be reported by two of them. Keyed by instance.
			if not seen[s.inst] then
				seen[s.inst] = true
				leftovers[#leftovers + 1] = s
			end
		end
	end

	-- ===== PASS 2: PLACE ONCE =====
	-- A prop the cut refused is furniture, and furniture at the verge of a road is a village -- the
	-- market stalls, the Shop counter and the daily-spin wheel all end up standing along these
	-- lanes and every one reads better there than where it was. Only what is INSIDE the driving
	-- line moves.
	--
	-- ===== SINCE 32.4 THE FURNITURE IS IN THIS LIST TOO, AND THAT IS THE ROW =====
	-- `MapCut.Lane` used to skip a protected prop outright, so the only things this pass ever saw
	-- were props it was free to delete and had chosen not to. The two that were actually standing in
	-- the road were both anchors -- the Shop market stall 18.2 studs off the south lane's centre with
	-- its footprint reaching 9.0, and the daily-spin wheel 11.1 off it reaching 4.4 -- and neither
	-- was ever a candidate. Protection guards the DESTROY now; see that file.
	--
	-- Two things follow, and both are handled below rather than left to the next reader.
	--   * AN ANCHOR'S MEASURED POSITION GOES STALE THE MOMENT IT MOVES. `MapCounters`, `MapEggs`,
	--     `MapSquare` and `MapSigns` all read `MapAnchors`' cached `pos`, and all four run after
	--     this. 32.3 is the record of what a stale one costs: a signpost aimed at where the zone
	--     doors used to be.
	--   * A SIGNPOST IS TWO PROPS. The pole and its floating label are separate children of the map,
	--     so a pole moved on its own leaves the label in the air.
	local moved, stuck, carried, restated = 0, {}, 0, 0
	for _, s in ipairs(leftovers) do
		if s.inst.Parent then
			local hw = s.w / 2
			local lane = roadAt(s.x, s.z, hw)
			if lane then
				local size = s.inst:IsA("Model") and select(2, s.inst:GetBoundingBox()) or s.inst.Size
				local tx, tz, felled = relocate(map, s.inst, cx, lane, s.x, s.z, size)
				if tx then
					local shift = Vector3.new(tx - s.x, 0, tz - s.z)
					s.inst:PivotTo(s.inst:GetPivot() + shift)
					restated += MapAnchors.Remeasure(zoneKey, s.inst)
					for _, mate in ipairs(MapAnchors.Companions(zoneKey, s.inst)) do
						if mate.Parent then
							mate:PivotTo(mate:GetPivot() + shift)
							restated += MapAnchors.Remeasure(zoneKey, mate)
							carried += 1
						end
					end
					moved += 1
					totalCut += felled or 0
				else
					stuck[#stuck + 1] = ("%s(%.0f,%.0f) in %s"):format(s.name, s.x, s.z, lane.id)
				end
			end
		end
	end

	-- ===== PASS 3: PAINT =====
	local rng = Random.new(99)
	for _, lane in ipairs(LANES) do
		local pts = PathSplines.Route(Vector3.new(lane.x1, 0, lane.z1), Vector3.new(lane.x2, 0, lane.z2), rng, { maxJitter = 12 })
		if #pts >= 2 then
			for i = 1, #pts - 1 do
				local p1 = pts[i]
				local p2 = pts[i+1]
				local t1 = (i - 1) / (#pts - 1)
				local t2 = i / (#pts - 1)
				local w1 = lane.wA + (lane.wB - lane.wA) * t1
				local w2 = lane.wA + (lane.wB - lane.wA) * t2
				local wMid = (w1 + w2) / 2
				local cap = (i == 1) and "both" or "b"
				local segDirt = { x1 = p1.x, z1 = p1.z, x2 = p2.x, z2 = p2.z, w = wMid }
				MapPaint.Segment(segDirt, folder, cx, dirt, TOP - THICK / 2, THICK, cap)
			end
		else
			local a = Vector2.new(lane.x1, lane.z1)
			local b = Vector2.new(lane.x2, lane.z2)
			MapPaint.Taper(a, b, lane.wA, lane.wB, folder, cx, dirt, TOP - THICK / 2, THICK, QUADS, true, true)
		end
	end
	local painted = 0
	for _, p in ipairs(folder:GetChildren()) do
		if p:IsA("BasePart") then
			p.CanQuery = false
			painted += 1
		end
	end

	-- `restated` and `carried` are printed even at zero for the reason `MapJungle`'s dropped count
	-- is: they are the only line that would ever say the census had gone stale under four passes
	-- that read it, or that a signpost had been separated from its own label.
	print(("[MapGates] %s: %d lanes, cut %d props, %d paint parts, moved %d of %d leftovers "
		.. "(%d anchors re-measured, %d companions carried)")
		:format(zoneKey, #LANES, totalCut, painted, moved, #leftovers, restated, carried))
	-- Printed, never swallowed. A building left standing in a lane is the whole defect this file
	-- exists to fix, and it is invisible from every direction except this line and a screenshot.
	if #stuck > 0 then
		warn(("[MapGates] %s: %d prop(s) STILL IN THE ROAD with nowhere to go -- %s")
			:format(zoneKey, #stuck, table.concat(stuck, ", ")))
	end
	return painted
end

return MapGates
