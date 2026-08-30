local PathSplines = require(script.Parent.PathSplines)
local MapPaint = require(script.Parent.MapPaint)
-- MapProps/JungleTrails -- the roads that actually reach the camps. Data only; nothing here builds
-- or paints anything. `JungleLayout` owns WHERE the camps are and calls this to work out how a
-- player gets to them; `MapJungle` paints what comes back and `MapForest` keeps its wood out of it.
--
-- ===== THE ROW THIS FILE IS (32.1) =====
-- Her complaint, walking Forest: *"the road does not take you to the mobs"*. 31.24's commit
-- promised a `JungleRings` pass that would re-place the ring against the shrunken camps, and the
-- ring was measured to be impossible: the inner camp column sits at |x| 313..325 and the outer at
-- 400..436, and their 46-stud floors leave FIVE studs of corridor between them. There is nowhere
-- to thread a road, so the ring rows are deleted rather than moved.
--
-- ===== WHAT REPLACES IT, AND WHY IT IS A TREE AND NOT A CHAIN =====
-- The approved design was a per-quadrant CHAIN: greedy nearest-neighbour from the quadrant's
-- village anchor, through its five camps, out to its cross anchor. It was built that way first and
-- **measured worse than what it replaced** -- mean detour 4.18x against today's 3.51x -- and the
-- reason is structural rather than a bad chain: a chain is SERIAL. `SW3` stands 45 studs off the
-- village wall and is fourth in its quadrant's chain, so reaching it meant walking the whole loop
-- out to `SW2`/`SW4` and back. Every camp after the second pays for every camp before it.
--
-- So the shape is a TREE grown from the village outward, and the chains fall out of it by
-- themselves: an outer camp connects through its inner neighbour because that really is the
-- shortest way to it, while a camp beside the village connects straight to the cross. Same
-- rim-to-rim links, same "the road stops at the mouth" rule -- different root.
--
-- MEASURED over the same network model, before and after:
--     mean walk to a camp   395 -> 215 studs
--     worst walk            795 -> 349 studs
--     mean detour          3.51x -> 2.30x
--     paved                2944 -> 1778 studs
--
-- ===== THE 1.6x TARGET IS NOT REACHABLE FROM THIS VILLAGE, AND THAT IS A MEASUREMENT =====
-- 32.1 asks for a mean detour under ~1.6x. The remainder is not road design, it is DOORS: the
-- village has four ways out (the two plaza corners, the two flank gates at z = -100, the south
-- lane) and nothing on its north or west faces. `SW3` is 45 studs of grass from the village wall
-- and 191 studs of road, because the nearest door is 200 studs away.
--
-- The obvious answer -- a belt road hugging the village, joining the plaza corners to the flank
-- gates -- was worked out and does not fit. The inner camps stand 43..54 studs off the village
-- wall, so a belt clear of their floors by a road's half-width would have to run at |x| <= 263,
-- and the village floor reaches 270.5. It is the ring problem again, one ring in. Widening the
-- walk is a village-exit row, not a road-network one.
--
-- ===== WHY A LINK STOPS AT THE RIM AND RESUMES AT THE NEXT ONE =====
-- This is what dissolves the corridor problem the ring died of. A road that runs from camp A's
-- MOUTH to camp B's MOUTH never has to pass BETWEEN two camps -- it ends at one floor and begins
-- again at the other, and the 92-stud dirt disc in between is the road. It also means the paint
-- never lies across a clearing: `MapJungle` draws the floor above the trail, so the 14 studs a link
-- overshoots into the floor are covered by it (`SPUR_OVERSHOOT`'s own rule, at the other kind of
-- join).
--
-- A GRAPH PROBE THAT DOES NOT KNOW THIS CALLS THE NETWORK DISCONNECTED. Two consecutive links are
-- 60+ studs apart across a camp, so a reachability check that joins nodes within a road's width
-- reports every quadrant unreachable -- which is the same trap the roadmap already records for
-- querying a camp CENTRE. The floor is walkable ground and has to be a node.

local JungleTrails = {}

-- ===== THE VILLAGE'S ONLY NORTH DOORS =====
-- `HubPlaza`'s deck is 344 x 336 spanning x -172..172, z 74..422, so both of these stand ON it --
-- a player who has just spawned can turn either way into the wood without walking through the
-- village first. This is the half of the network that did not exist: the measurement that opened
-- this row found NW1/NE1 at a 13.9x detour for exactly this reason, 54 studs of grass against 749
-- studs of road, because the north side had no exit but the plaza itself.
JungleTrails.HEADS = {
	{ x = -150, z = 390 },
	{ x =  150, z = 390 },
}

-- Narrower than any cross trunk (56/46) and wider than the spurs it replaces (26). A trail is not
-- a main road and should not read as one; against an 8.4-stud body 30 studs is two abreast, which
-- is what a path through a wood looks like.
JungleTrails.WIDTH = 30

-- How far OUTSIDE the village rectangle a trail must stay. The road's own half-width is added on
-- top, so this is clearance between the paint and the village floor rather than centre lines.
local VILLAGE_MARGIN = 10

-- ===== A TRAIL MAY NOT BE PAINTED ON TOP OF A GATE LANE (34.36) =====
-- Her capture of the village's south mouth: *"ovde se putevi se preklapaju i vode u zid"*. Measured
-- on a live build, three road systems draw 320 sheets of paint on this platform and **54 pairs of
-- them overlap across systems -- 50 of those a trail lying over a `MapGates` lane**, with a 0.23 to
-- 0.35 stud step between the two surfaces. Each system is on its own height ladder and every rung
-- of it is deliberate (`MapPaint.STEP` is what stops two coplanar sheets z-fighting), so what the
-- player sees is not a shimmer: it is one road's dark rim standing proud across another road, which
-- is exactly what "the roads overlap" means from eye height.
--
-- The lanes cannot move -- both flanks are at z = -100 because the portal hall and the leaderboard
-- hall stand where z = 0 would run, and the south lane is the village's front door -- so the TRAILS
-- have to know where the lanes are. `MapGates.PaintKeepOut()` is the one published answer to how
-- much ground a lane's paint covers, derived in the file that draws it.
--
-- ===== A JUNCTION IS A TUCK, NOT A GAP =====
-- The first build of this rule refused every intrusion outright, and it was measurably worse than
-- the fault: mean walk 132 -> 187 studs, worst 244 -> 448, because the south mouth is exactly where
-- the camps nearest the village wanted to hang their trails. It also leaves a stripe of bare grass
-- between two roads wherever a trail does stop beside a lane, which reads as badly as the overlap.
--
-- A lane is painted at 0.72 / 0.80 and a trail at 0.45 / 0.49, so THE LANE DRAWS OVER THE TRAIL.
-- A trail that reaches a few studs under the lane's rim is therefore invisible under it, and that
-- is what a junction looks like: the two sheets meet with nothing between them and nothing proud.
-- `MapGates` publishes how far that is (`tuck`, its own rim width) beside the keep-out, because it
-- is the file that decides both. It is `SPUR_OVERSHOOT` at the other kind of join -- a trail ends
-- 14 studs inside a camp floor because `MapJungle` draws the floor above it.
--
-- So: an anchor may sit ON the lane's edge, tucked one rim under it, and a link is refused only
-- when it reaches DEEPER than the tuck -- which a trail crossing a lane always does, by the whole
-- width of the lane. Three rules: the anchor slide along the cross, a lane-edge anchor of its own
-- so a camp by the mouth still gets a short road, and the refusal. The bend is covered too -- the
-- lanes go into `PathSplines`' obstacle list as a chain of circles, which is a capsule the route
-- can be pushed around, and `info.blocked` then says so honestly if it cannot be.
--
-- CIRCLES AND NOT RECTS, deliberately: `PathSplines`' rect is axis-aligned, so the box around a
-- lane leg reaches past the leg's own rounded end at the corners -- and a trail that legitimately
-- starts one stud outside the lane's cap would begin INSIDE that box, where no amount of bending
-- can help it.
local ANCHOR_STEP = 6      -- how far the anchor slides per try, along the road it is sliding on
local ANCHOR_TRIES = 6     -- and how far off a lane's edge a junction may be pushed before it is
                           -- not a junction with that lane any more

-- ===== GEOMETRY =====

local function distToSegment(px, pz, x1, z1, x2, z2)
	local dx, dz = x2 - x1, z2 - z1
	local len2 = dx * dx + dz * dz
	local t = 0
	if len2 > 0 then
		t = math.clamp(((px - x1) * dx + (pz - z1) * dz) / len2, 0, 1)
	end
	local qx, qz = x1 + dx * t, z1 + dz * t
	return math.sqrt((px - qx) ^ 2 + (pz - qz) ^ 2), qx, qz
end

-- The closest the two segments come to each other in XZ. Crossing counts as zero, which is the
-- case that matters here: a trail laid straight across a lane has both its endpoints far from the
-- lane's centre line, so a test built only on endpoint distances calls the worst overlap in the
-- build the widest gap.
local function segSegDist(ax, az, bx, bz, cx, cz, dx, dz)
	local rx, rz = bx - ax, bz - az
	local sx, sz = dx - cx, dz - cz
	local denom = rx * sz - rz * sx
	if math.abs(denom) > 1e-9 then
		local qx, qz = cx - ax, cz - az
		local t = (qx * sz - qz * sx) / denom
		local u = (qx * rz - qz * rx) / denom
		if t >= 0 and t <= 1 and u >= 0 and u <= 1 then return 0 end
	end
	return math.min(
		(distToSegment(ax, az, cx, cz, dx, dz)),
		(distToSegment(bx, bz, cx, cz, dx, dz)),
		(distToSegment(cx, cz, ax, az, bx, bz)),
		(distToSegment(dx, dz, ax, az, bx, bz)))
end

-- How far apart two roads' centre lines have to be for their paint not to touch: both rims, added.
local function laneClear(lane, o)
	return lane.half + o.width / 2 + MapPaint.EDGE_W
end

-- The nearest point on a lane's centre line to `(px, pz)`, and how far away it is.
local function nearestOnLane(px, pz, lane)
	local bd, bx, bz = math.huge, nil, nil
	for i = 1, #lane.pts - 1 do
		local p, q = lane.pts[i], lane.pts[i + 1]
		local d, qx, qz = distToSegment(px, pz, p.x, p.z, q.x, q.z)
		if d < bd then bd, bx, bz = d, qx, qz end
	end
	return bd, bx, bz
end

-- How much DEEPER than the allowed tuck a trail drawn along this segment would reach into the
-- nearest gate lane. Zero is a junction -- the trail's rim ends under the lane's rim and the lane
-- covers it -- and anything positive is a trail painted out the far side of that border. Negative
-- is daylight. Both roads are measured at their RIM, because the rim is the wider sheet.
local function laneExcess(sx, sz, ex, ez, o)
	local worst = -math.huge
	for _, lane in ipairs(o.lanes) do
		local limit = laneClear(lane, o) - (lane.tuck or 0)
		for i = 1, #lane.pts - 1 do
			local p, q = lane.pts[i], lane.pts[i + 1]
			local d = segSegDist(sx, sz, ex, ez, p.x, p.z, q.x, q.z)
			if limit - d > worst then worst = limit - d end
		end
	end
	return worst
end

-- Does the segment touch the axis-aligned box `|x| <= hx, |z| <= hz`? Liang-Barsky, so it is exact
-- rather than sampled -- a sampler with a 40-step stride walks straight through a corner clip, and
-- a corner clip is the case that actually happens here (the first build of this file ran a link
-- from SW1 to SW5 across the village's south-west corner and four samples caught it by luck).
local function hitsBox(x1, z1, x2, z2, hx, hz)
	local t0, t1 = 0, 1
	local d = { x2 - x1, z2 - z1 }
	local p0 = { x1, z1 }
	local h = { hx, hz }
	for i = 1, 2 do
		if math.abs(d[i]) < 1e-9 then
			if p0[i] < -h[i] or p0[i] > h[i] then return false end
		else
			local a = (-h[i] - p0[i]) / d[i]
			local b = (h[i] - p0[i]) / d[i]
			if a > b then a, b = b, a end
			t0 = math.max(t0, a)
			t1 = math.min(t1, b)
			if t0 > t1 then return false end
		end
	end
	return true
end

-- ===== ONE LINK, RIM TO RIM =====
-- `from` is either a point on the cross (or a plaza head), in which case the road starts there, or
-- another camp's centre, in which case it starts at that camp's mouth. It always ENDS at the mouth
-- of `camp`. `mouth` is `CAMP_RADIUS - SPUR_OVERSHOOT`, so both ends run under the floor's rim and
-- onto the dirt rather than stopping on the grass beside it.
local function link(fx, fz, fromCamp, camp, o)
	local a = math.atan2(camp.z - fz, camp.x - fx)
	local sx, sz = fx, fz
	if fromCamp then
		sx = fx + math.cos(a) * o.mouth
		sz = fz + math.sin(a) * o.mouth
	end
	local ex = camp.x - math.cos(a) * o.mouth
	local ez = camp.z - math.sin(a) * o.mouth
	return sx, sz, ex, ez
end

-- Everything a link is not allowed to do. All three are faults a screenshot finds days later and
-- no per-camp check ever sees, which is why they are one function called on every candidate rather
-- than an assertion at the end.
local function usable(sx, sz, ex, ez, aId, bId, camps, o)
	--   1. it must not lie across a camp floor it does not serve. This is the ring's own fault --
	--      creatures standing in the traffic -- and it is the reason the ring rows are gone.
	for _, c in ipairs(camps) do
		if c.id ~= aId and c.id ~= bId then
			local d = distToSegment(c.x, c.z, sx, sz, ex, ez)
			if d - o.width / 2 - o.campRadius < 0 then return false end
		end
	end
	--   2. it must not run over the village. The village floor is the map, with its own roads,
	--      squares and buildings on it; a jungle trail painted across it is a dirt stripe through
	--      the shops.
	if hitsBox(sx, sz, ex, ez,
		o.villageHalfX + VILLAGE_MARGIN + o.width / 2,
		o.villageHalfZ + VILLAGE_MARGIN + o.width / 2) then
		return false
	end
	--   3. it must not be painted over a gate lane (34.36). The lanes are the village's three
	--      doors and they are drawn 0.31..0.43 studs higher than the jungle's paint, so a trail
	--      crossing one puts its dark rim proud across the busiest road in the zone. A trail joins
	--      a lane at its edge -- which is what the anchor slide below arranges -- or it does not
	--      touch it at all.
	if #o.lanes > 0 and laneExcess(sx, sz, ex, ez, o) > 0 then
		JungleTrails.LaneRefusals += 1
		return false
	end
	--   4. it must stay on the platform. Both ends is enough -- the keep-out is convex, so a
	--      segment with both ends inside it is inside it.
	if math.abs(sx) > o.edgeX or math.abs(ex) > o.edgeX
		or math.abs(sz) > o.edgeZ or math.abs(ez) > o.edgeZ then
		return false
	end
	return true
end

-- ===== WHERE ON THE CROSS A TRAIL IS ALLOWED TO START (34.36) =====
-- The nearest point on a trunk to the camp, then PUSHED ALONG THAT TRUNK until a trail beginning
-- there can be drawn clear of every gate lane. That push is the row's fix in one line: the trunks
-- and the lanes deliberately overlap where they meet (`MapGates`' south lane runs 22 studs past the
-- head of the jungle's main lane so the two networks join rather than stopping short of each
-- other), so the geometric nearest point on the cross is very often INSIDE a lane -- and every
-- trail hung off it began by crossing the lane's paint.
--
-- It slides BOTH WAYS from the nearest point and takes the first clear one, rather than walking
-- outward from the village end. The cross is authored village-end-first today and that is the kind
-- of fact a table edit changes silently; a search that does not depend on it cannot be broken by
-- one.
--
-- ===== IT TESTS THE ROAD, NOT THE SPOT, AND THAT IS WORTH 365 STUDS =====
-- The first build asked only whether the ANCHOR was clear of the lanes. `SE5` stands at (299, -8),
-- north of the east lane and just outside the village keep-out, so its road leaves the east trunk
-- and immediately ANGLES BACK toward the lane's tip: the anchor at (329, -100) was clear and the
-- road it started passed **40.8 studs** from the lane where 41 is asked -- refused by two tenths of
-- a stud. The tree then hung `SE5` off `NE3` on the far side of the map and its walk went from 83
-- studs to **448**. A slide that cannot see the road it is starting is answering a different
-- question from the one `usable` asks.
--
-- `nil` when no point on the trunk starts a legal road, which is not an error: `Build` simply has
-- one fewer anchor to choose from, and a camp that ends up with none at all is already named by
-- `Unreachable`.
local function anchorOn(p, camp, o)
	local _, qx, qz = distToSegment(camp.x, camp.z, p.x1, p.z1, p.x2, p.z2)
	if #o.lanes == 0 then return qx, qz end
	local dx, dz = p.x2 - p.x1, p.z2 - p.z1
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1 then return qx, qz end
	local ux, uz = dx / len, dz / len
	local t0 = (qx - p.x1) * ux + (qz - p.z1) * uz
	for step = 0, math.ceil(len / ANCHOR_STEP) do
		for _, sgn in ipairs({ 1, -1 }) do
			local t = t0 + sgn * step * ANCHOR_STEP
			if t >= 0 and t <= len then
				local ax, az = p.x1 + ux * t, p.z1 + uz * t
				local sx, sz, ex, ez = link(ax, az, nil, camp, o)
				if laneExcess(sx, sz, ex, ez, o) <= 0 then return ax, az end
			end
			if step == 0 then break end
		end
	end
	return nil
end

-- ===== A DOOR ON THE SIDE OF A LANE (34.36) =====
-- The point on each lane's edge closest to the camp, tucked one rim under the lane so the two
-- sheets meet with nothing between them. This is what keeps the walk short once the crossing rule
-- goes in: `SE5` and its neighbours stand by the village's south mouth, and every road they had ran
-- across the lane there. A lane is a road the player is already standing on, so joining it is worth
-- exactly what joining the cross is worth -- `base = 0`, the same as a plaza head.
--
-- Pushed PERPENDICULAR, from the nearest point toward the camp. A camp lying along the lane's own
-- axis pushes past the end cap instead, which is the same junction seen end-on. A camp that is
-- already further off than the tuck gets no anchor from this lane at all -- the geometric nearest
-- point is then simply where the trail would have started anyway, and pulling it in to the lane
-- would lengthen the road to reach a door it does not need.
local function laneAnchors(camp, o, out)
	for _, lane in ipairs(o.lanes) do
		local d, qx, qz = nearestOnLane(camp.x, camp.z, lane)
		if qx then
			local vx, vz = camp.x - qx, camp.z - qz
			local m = math.sqrt(vx * vx + vz * vz)
			local reach = laneClear(lane, o) - (lane.tuck or 0)
			if m > 1e-3 and d > reach then
				-- Walked out along the same ray until the ROAD is legal and not just the spot, for
				-- the reason written over `anchorOn`. The first try is the tuck itself, which is
				-- the junction the row asked for; a second lane in the way is what moves it.
				local ux, uz = vx / m, vz / m
				for step = 0, ANCHOR_TRIES do
					local at = reach + step * ANCHOR_STEP
					if at >= d then break end
					local ax, az = qx + ux * at, qz + uz * at
					local sx, sz, ex, ez = link(ax, az, nil, camp, o)
					if laneExcess(sx, sz, ex, ez, o) <= 0 then
						out[#out + 1] = { x = ax, z = az, from = nil, base = 0 }
						break
					end
				end
			end
		end
	end
end

-- ===== THE NETWORK =====
-- Grown outward from the village, cheapest camp first: at every step, of every camp not yet on the
-- network, connect the one whose total walk from a village door is least. That is Dijkstra with the
-- cross as the source, and it is what makes the walk short BY CONSTRUCTION rather than by a lucky
-- ordering -- which is the whole difference between this and the chain it replaced.
--
-- Crossing a parent camp costs `campRadius`, because that is what the player actually walks: a link
-- ends at one mouth and the next begins at another, and the floor between them is the road.
--
-- `opts` carries every constant from `JungleLayout` rather than this file re-deriving any of them.
-- One copy of the camp radius, one copy of the village rectangle -- the fault that comment is
-- guarding against is 31.5a, where `a`/`b` were read as widths in one of two files and 74 rigs
-- ended up over the void.
function JungleTrails.Build(camps, cross, opts)
	local o = {
		width = opts.width or JungleTrails.WIDTH,
		mouth = opts.mouth,
		campRadius = opts.campRadius,
		villageHalfX = opts.villageHalfX,
		villageHalfZ = opts.villageHalfZ,
		edgeX = opts.edgeX,
		edgeZ = opts.edgeZ,
		-- `MapGates.PaintKeepOut()`, handed in rather than required, for the same reason every
		-- other constant on this table is: one file decides how wide a gate lane is painted.
		lanes = opts.lanes or {},
	}

	local cost, connected, out = {}, {}, {}
	local left = #camps
	-- Reset per build, like `Unreachable`. A list that accumulates across calls reports the last
	-- five boots at once, which is how a fixed fault goes on being printed.
	JungleTrails.Crossing = {}
	JungleTrails.LaneRefusals = 0

	while left > 0 do
		local best = nil
		for _, camp in ipairs(camps) do
			if not connected[camp.id] then
				-- every place this camp could hang off: the cross, a plaza head, or a camp that is
				-- already on the network
				local anchors = {}
				for _, p in ipairs(cross) do
					local ax, az = anchorOn(p, camp, o)
					if ax then anchors[#anchors + 1] = { x = ax, z = az, from = nil, base = 0 } end
				end
				for _, h in ipairs(JungleTrails.HEADS) do
					if laneExcess(h.x, h.z, h.x, h.z, o) <= 0 then
						anchors[#anchors + 1] = { x = h.x, z = h.z, from = nil, base = 0 }
					end
				end
				laneAnchors(camp, o, anchors)
				for _, c in ipairs(camps) do
					if connected[c.id] then
						anchors[#anchors + 1] = { x = c.x, z = c.z, from = c, base = cost[c.id] + o.campRadius }
					end
				end
				for _, a in ipairs(anchors) do
					local sx, sz, ex, ez = link(a.x, a.z, a.from, camp, o)
					local aId = a.from and a.from.id or nil
					if usable(sx, sz, ex, ez, aId, camp.id, camps, o) then
						local len = math.sqrt((ex - sx) ^ 2 + (ez - sz) ^ 2)
						local total = a.base + len
						if best == nil or total < best.total then
							best = {
								total = total, camp = camp, from = a.from,
								sx = sx, sz = sz, ex = ex, ez = ez, len = len,
							}
						end
					end
				end
			end
		end

		-- ===== A CAMP NOTHING CAN REACH IS NAMED, NOT SKIPPED =====
		-- Every candidate for some camp was rejected. That is not a road problem -- it means the
		-- camp is boxed in by other camps' floors or by the village -- and it is exactly the class
		-- of fault that 31.24's "0 spurs" line caught by accident. Stop, say which, and let
		-- `Describe` print it: a network quietly one camp short is a camp nobody can walk to.
		if best == nil then
			local stuck = {}
			for _, c in ipairs(camps) do
				if not connected[c.id] then stuck[#stuck + 1] = c.id end
			end
			JungleTrails.Unreachable = stuck
			break
		end

		cost[best.camp.id] = best.total
		connected[best.camp.id] = true
		left -= 1
		local startPos = Vector3.new(best.sx, 0, best.sz)
		local endPos = Vector3.new(best.ex, 0, best.ez)
		local obs = {}
		for _, c in ipairs(camps) do
			if c.id ~= best.camp.id and (not best.from or c.id ~= best.from.id) then
				-- ===== THE BEND IS HELD TO THE SAME RULE AS THE CHORD (34.36) =====
				-- This was `campRadius + 5`, which is a CENTRE LINE five studs off a floor -- and a
				-- trail is painted 18 studs wide to its rim, so a route the search called clear put
				-- 13 studs of road on the clearing. `usable` has always refused that on the chord;
				-- the bend was measured against a different number, and the first build of the lane
				-- rule pushed three trails onto `SE1` through exactly this gap.
				table.insert(obs, { type="circle", x = c.x, z = c.z,
					r = o.campRadius + o.width / 2 + MapPaint.EDGE_W })
			end
		end
		table.insert(obs, { type="rect", x = 0, z = 0, hx = o.villageHalfX + 15, hz = o.villageHalfZ + 15 })
		-- The lane keep-out as a chain of circles -- a capsule the bend can be pushed around. The
		-- chord was already refused if it intruded, so this is only here to stop a 15-stud jitter
		-- putting a legal trail back on top of a lane.
		for _, lane in ipairs(o.lanes) do
			local r = laneClear(lane, o) - (lane.tuck or 0)
			for i = 1, #lane.pts - 1 do
				local a, b = lane.pts[i], lane.pts[i + 1]
				local segLen = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
				local n = math.max(1, math.ceil(segLen / (r / 2)))
				for k = 0, n do
					local f = k / n
					table.insert(obs, { type = "circle",
						x = a.x + (b.x - a.x) * f, z = a.z + (b.z - a.z) * f, r = r })
				end
			end
		end
		
		local rng = opts.rng or Random.new(math.floor(math.abs(best.sx + best.sz)))
		local pts, info = PathSplines.Route(startPos, endPos, rng, { maxJitter = 15 }, obs)

		-- ===== A TRAIL THAT COULD NOT GET ROUND A CAMP IS NAMED, NOT SHIPPED QUIETLY =====
		-- Same rule as the unreachable camp above, and it is new with 33.35 for a reason: until the
		-- route was re-tested after bending, "avoided" was an assumption. Now the search either
		-- finds a curve that clears every other camp's floor and the village, or it says so.
		if info and info.blocked then
			JungleTrails.Crossing[#JungleTrails.Crossing + 1] = best.camp.id
		end

		-- ===== ONE CHAIN OF LEGS IS ONE TRAIL, AND ONLY THE HEAD CARRIES THE WALK =====
		-- The `head` flag is written rather than inferred. `Describe` used to count segments with
		-- `tier == "trail"`, which was the same thing as counting trails right up until 32.11b split
		-- each one into legs -- and then the boot log read "259 trails, walk to a camp: mean 10
		-- studs" for a twenty-camp zone whose real mean is ~146. It was averaging one real distance
		-- against 239 zeroes. A count that only happens to be right is a count that will go wrong
		-- silently.
		if #pts >= 2 then
			for i = 1, #pts - 1 do
				out[#out + 1] = {
					id = best.camp.id .. "trail" .. (i > 1 and "_"..i or ""),
					x1 = pts[i].x, z1 = pts[i].z, x2 = pts[i+1].x, z2 = pts[i+1].z,
					w = o.width,
					tier = "trail",
					head = (i == 1),
					caps = (i == 1) and "both" or "b",
					serves = { [best.camp.id] = true, [best.from and best.from.id or ""] = true },
					parent = best.from and best.from.id or nil,
					walk = (i == 1) and best.total or 0,
				}
			end
		else
			out[#out + 1] = {
				id = best.camp.id .. "trail",
				x1 = best.sx, z1 = best.sz, x2 = best.ex, z2 = best.ez,
				w = o.width,
				tier = "trail",
				head = true,
				serves = { [best.camp.id] = true, [best.from and best.from.id or ""] = true },
				parent = best.from and best.from.id or nil,
				walk = best.total,
			}
		end
	end

	JungleTrails.Unreachable = JungleTrails.Unreachable or {}
	JungleTrails.Cost = cost
	return out
end

-- One line for the boot log. The MEAN and WORST walk are the row's complaint in two numbers -- a
-- ratio is not enough on its own, because the camps with the worst ratios (`SW3` at 4.2x) are the
-- ones standing 45 studs from the village wall, where a short road still looks like a long detour.
-- ===== COUNT TRAILS, NOT PAINT (33.35) =====
-- A trail is one chain of legs from an anchor to a camp mouth, and exactly one leg per chain -- the
-- HEAD -- carries the walk distance. This counted `tier == "trail"` segments, which was the same
-- number until 32.11b started splitting each trail into legs, and then the line read
-- `259 trails, walk to a camp: mean 10 studs` for twenty camps whose real mean is 146: one true
-- distance averaged against 239 zeroes. Both halves of that line were wrong and neither was
-- obviously wrong, which is the whole problem with a metric that is right by coincidence.
--
-- `legs` is printed beside it because it is the number that decides the part count -- four parts a
-- leg, once for the rim and once for the dirt -- and it is the first thing to look at if the zone
-- ever gets heavy again.
function JungleTrails.Describe(segments)
	local n, legs, total, worst, worstId = 0, 0, 0, 0, "-"
	for _, s in ipairs(segments) do
		if s.tier == "trail" then
			legs += 1
			if s.head then
				n += 1
				total += s.walk
				if s.walk > worst then worst, worstId = s.walk, s.id end
			end
		end
	end
	local crossing = JungleTrails.Crossing or {}
	-- `laneRefusals` is printed even at zero. It is the only number that says whether 34.36's rule
	-- is still reaching anything: at zero on a build whose lanes moved, the keep-out is being
	-- derived from the wrong place and every trail is legal by accident.
	return ("%d trails (%d legs), walk to a camp: mean %.0f studs, worst %s at %.0f"
		.. " (%d link(s) refused for lying on a gate lane)%s%s")
		:format(n, legs, n > 0 and total / n or 0, worstId, worst,
			JungleTrails.LaneRefusals or 0,
			#crossing > 0
				and ("  <-- COULD NOT BEND CLEAR: " .. table.concat(crossing, ", ")) or "",
			#JungleTrails.Unreachable > 0
				and ("  <-- NO ROAD REACHES " .. table.concat(JungleTrails.Unreachable, ", ")) or "")
end

return JungleTrails
