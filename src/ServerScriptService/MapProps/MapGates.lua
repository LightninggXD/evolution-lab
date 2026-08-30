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
--
-- ===== `join`: THE TAIL THAT IS A JUNCTION AND NOT AN END (34.36) =====
-- Her capture of this mouth: *"ovde se putevi se preklapaju i vode u zid"*. The south lane runs 22
-- studs past the head of the jungle's main trunk on purpose, so that the two networks MEET instead
-- of stopping short of each other -- and for 22 studs both of them were drawn in full. A lane is
-- painted at 0.72 / 0.80 and a trunk at 0.37 / 0.41, so the lane wins every pixel of that overlap;
-- what the player sees is not the double paint but its BORDER, a dark rim slab and a 64-stud rim
-- CAP lying across the road at the far end of it. Photographed from the lane: a dark curved band
-- straight across an otherwise continuous road.
--
-- So over its last `join` studs a lane draws no rim and no terminal cap. The trunk underneath is
-- wider than the lane's dirt (56 against 52) and carries its own rim, so the border the eye follows
-- simply becomes the trunk's -- which is what a road running into another road looks like. The
-- flanks meet their trunks exactly at |x| = 286 and so need no tail at all; killing the terminal
-- cap is the whole of it there.
--
-- The cap is dropped on the last leg of EVERY lane regardless, which `MapPaint`'s own note asks
-- for: a disc the width of the road on the end of the road is a lollipop, and it is the most
-- visible thing in any picture that contains it.
local LANES = {
	{ id = "South", x1 = 0, z1 = -30, x2 = 0, z2 = -262, halfA = 32, halfB = 34, wA = 56, wB = 52, join = 22 },
	{ id = "West", x1 = 0, z1 = -100, x2 = -286, z2 = -100, halfA = 30, halfB = 30, wA = 46, wB = 44, join = 0 },
	{ id = "East", x1 = 0, z1 = -100, x2 = 286, z2 = -100, halfA = 30, halfB = 30, wA = 46, wB = 44, join = 0 },
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

-- ===== THE LANES BEND NOW, AND EVERY PASS HAS TO BE TOLD THE SAME STORY (33.35) =====
-- 32.11b curved the PAINT and left the cut, the driving line and `MapSquare` measuring the straight
-- chord. Measured on the shipped build: the south road's paint wanders **9.7 studs** off its chord,
-- west **8.2**, east **7.6**. The cut clears 32..34 studs a side and the paint is 26..28 wide, so
-- most of that wander spends the margin and some of it spends more than the margin -- painted road
-- over ground nothing ever cleared. Worse, `CLEAR_HALF` is the band that is GUARANTEED walkable,
-- and it stayed centred on the chord: at the widest part of the bend the clear band runs from
-- -33.7 to +14.3 of the road's actual centre. The road is passable and the guarantee is a fiction.
--
-- So the route is computed ONCE, here, and hung on the lane. `MapCut` is run leg by leg along it,
-- `offsetFrom` measures to it, the paint draws it, and `MapSquare` reads it off `MapGates.LANES`
-- without knowing anything changed. Module load, not `Build`: every input is a constant on this
-- page and the seed is fixed, so the route is a pure function of the file rather than something
-- that only exists once some other pass has run.
--
-- ONE `Random` FOR ALL THREE LANES, in table order -- that is why `PathSplines.Route` takes every
-- draw it will ever need before it starts searching. A search that drew while it looked would make
-- the east road's shape depend on how hard the south road had to work.
local ROUTE_SEED = 99
local ROUTE_JITTER = 12
do
	local rng = Random.new(ROUTE_SEED)
	for _, lane in ipairs(LANES) do
		lane.path = PathSplines.Route(
			Vector3.new(lane.x1, 0, lane.z1), Vector3.new(lane.x2, 0, lane.z2),
			rng, { maxJitter = ROUTE_JITTER })
	end
end

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
--
-- Measured to the lane's CURVE since 33.35. `PathSplines.Clearance` is this same clamped
-- projection, taken over every leg of the polyline instead of over one chord.
local function offsetFrom(lane, x, z)
	local d, qx, qz = PathSplines.Clearance(lane.path, x, z)
	return d, qx, qz
end

-- ===== CUTTING A ROAD THAT BENDS =====
-- `MapCut.Lane` and `MapCut.LaneFootprint` take a straight lane, and there is no reason to teach
-- them curves: a polyline IS a list of straight lanes. Each leg carries the half-widths its own
-- stretch of road wants, interpolated by arc length exactly as the paint interpolates its width,
-- so the taper of the cut still follows the taper of the road.
--
-- The same prop can be reported by two legs. `Build` already keys leftovers by instance -- that
-- dedupe was written for the T-junction, where two LANES see one prop, and it covers this for free.
local function cutAlong(map, cx, lane, protected, clearHalf, minHeight)
	local cut, stay = 0, {}
	local pts = lane.path
	for i = 1, #pts - 1 do
		local p, q = pts[i], pts[i + 1]
		local leg = {
			id = lane.id, x1 = p.x, z1 = p.z, x2 = q.x, z2 = q.z,
			halfA = lane.halfA + (lane.halfB - lane.halfA) * p.t,
			halfB = lane.halfA + (lane.halfB - lane.halfA) * q.t,
		}
		local n, kept = MapCut.Lane(map, cx, leg, protected)
		cut += n
		cut += MapCut.LaneFootprint(map, cx, leg, clearHalf, protected, minHeight)
		for _, s in ipairs(kept) do
			stay[#stay + 1] = s
		end
	end
	return cut, stay
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
		-- Leg by leg along the lane's own curve -- the road that gets painted -- and each leg runs
		-- the narrow footprint pass over the driving line too, which is what actually makes the
		-- lane walkable. See the note on `MapCut.LaneFootprint` and on `cutAlong`.
		local cut, stay = cutAlong(map, cx, lane, protected, CLEAR_HALF, DRIVE_MIN_HEIGHT)
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
	for _, lane in ipairs(LANES) do
		-- The lane's OWN route, the one the cut just ran along. Routing again here is how the two
		-- halves of this file came to disagree in the first place.
		local pts = lane.path
		if #pts >= 2 then
			-- Where the junction starts, as an arc-length fraction. `t` is already arc length (see
			-- below), so the lane's own length is the only extra thing needed and it is measured
			-- off the route rather than off the chord -- the route is 8 to 10 studs longer.
			local laneLen = 0
			for i = 1, #pts - 1 do
				laneLen += math.sqrt((pts[i+1].x - pts[i].x) ^ 2 + (pts[i+1].z - pts[i].z) ^ 2)
			end
			local joinFrom = (laneLen > 0 and (lane.join or 0) > 0)
				and (1 - lane.join / laneLen) or 1.1
			for i = 1, #pts - 1 do
				local p1 = pts[i]
				local p2 = pts[i+1]
				-- ARC LENGTH, not point index: the polyline is decimated by curvature, so its
				-- points are unevenly spaced on purpose and an index fraction tapers the road in
				-- the wrong place.
				local t1 = p1.t
				local t2 = p2.t
				local w1 = lane.wA + (lane.wB - lane.wA) * t1
				local w2 = lane.wA + (lane.wB - lane.wA) * t2
				local wMid = (w1 + w2) / 2
				local last = (i == #pts - 1)
				local cap = (i == 1) and "both" or "b"
				if last then cap = (i == 1) and "a" or "none" end
				-- A leg that reaches into the junction draws no border. Whole legs only: the road
				-- is decimated by curvature and cutting one in half here would put a second seam
				-- exactly where this is removing the first.
				if t2 <= joinFrom then
					local segEdge = { x1 = p1.x, z1 = p1.z, x2 = p2.x, z2 = p2.z, w = wMid + EDGE_W * 2 }
					MapPaint.Segment(segEdge, folder, cx, edge, EDGE_TOP - THICK / 2, THICK, cap)
				end
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

-- ===== WHAT THIS PAINT COVERS, FOR EVERY OTHER ROAD SYSTEM (34.36) =====
-- Three road systems draw on this platform -- these lanes, `MapRoad`'s approach and the jungle's
-- trunks and trails -- and each is on its own height ladder, deliberately. Measured on a live
-- build: 54 cross-system pairs of paint OVERLAPPING, 50 of them a jungle TRAIL crossing a gate
-- lane at the village's south mouth with a 0.23..0.35 stud step between the two surfaces. That is
-- the seam the owner photographed: not a colour and not a width, but one road's dark rim drawn
-- proud across another road.
--
-- The lanes cannot move -- z = -100 for both flanks is measured against the two halls inside the
-- village, and the south lane is the village's only front door -- so the trails have to know where
-- they are. This is the ONE published answer to "how much ground does a gate lane's paint cover",
-- and it is published from the file that draws that paint rather than copied into the file that
-- avoids it: `evolution-lab-zone-geometry-constants` is the standing note about a single decision
-- written down in two files, and a keep-out is only ever as correct as the width it was derived
-- from.
--
-- The half-width is the RIM's, not the road's -- the rim is the wider of the two sheets and the
-- one that reads as a border -- and the route is the lane's own curve, so a keep-out measured
-- against it bends with the road (33.35's whole argument). Point-to-segment distance rounds the
-- ends, which is exactly the terminal cap: a disc of the local width centred on the last point.
function MapGates.PaintKeepOut()
	local out = {}
	for _, lane in ipairs(LANES) do
		local pts = lane.path
		if not pts or #pts < 2 then
			pts = { { x = lane.x1, z = lane.z1 }, { x = lane.x2, z = lane.z2 } }
		end
		out[#out + 1] = {
			id = lane.id,
			pts = pts,
			half = math.max(lane.wA, lane.wB) / 2 + EDGE_W,
			-- ===== HOW FAR A LOWER ROAD MAY REACH UNDER THIS ONE =====
			-- A lane is painted at 0.72 / 0.80 and the jungle's trails at 0.45 / 0.49, so a lane
			-- DRAWS OVER a trail wherever the two meet. That is the whole difference between a
			-- junction and a seam: paint that stops short of a lane leaves a stripe of grass
			-- between two roads, and paint that runs a few studs under the lane's rim disappears
			-- beneath it. `SPUR_OVERSHOOT` is the same trick at the other kind of join -- a trail
			-- ends 14 studs inside a camp floor because the floor is drawn above it.
			-- The rim's own width is the honest limit: reach further and the tuck comes out the
			-- far side of the border it was hiding under.
			tuck = EDGE_W,
		}
	end
	return out
end

return MapGates
