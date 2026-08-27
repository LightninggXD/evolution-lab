-- MapProps/PathSplines -- the one curved line between two points, returned as the POLYLINE that
-- every other pass measures against.
--
-- 32.11b asked for roads that curve instead of roads that are drawn with a ruler. The first cut of
-- this file delivered the curve and three faults with it, and all three are the same mistake in
-- different clothes: THE CURVE WAS NEVER THE THING THAT GOT CHECKED.
--
--   1. Avoidance was tested ONCE, on the straight chord, before any bending happened. If the test
--      said "blocked" both control points were pushed a fixed 30 studs and the bent curve was
--      returned unexamined. A push of 30 either overshoots or falls short; nobody ever found out
--      which, because nothing looked again.
--   2. The rect test was an AABB overlap -- does the SEGMENT'S OWN BOX touch the rect -- which is
--      true for every road that passes near a corner of the village without ever crossing it. Roads
--      were bent away from ground they were never standing on.
--   3. Points were emitted every 8 studs whatever the shape. A 216-stud trail carrying 9 studs of
--      total wander came out as 28 points, and each point costs FOUR parts downstream (rim slab,
--      rim cap, dirt slab, dirt cap). Twenty trails made 1,094 path parts where the straight
--      network made 69, on a place that ships with StreamingEnabled. The wander did not grow. Only
--      the bill did.
--
-- ===== SO THE CONTRACT IS: WHAT IS RETURNED IS WHAT WAS TESTED =====
-- The curve is sampled densely, the SAMPLED POLYLINE is tested against the obstacles leg by leg,
-- and the search moves on until a sampled polyline passes. The points handed back are a decimation
-- of that same polyline, never of some other curve, so a caller that paints them is painting the
-- line that was cleared.
--
-- ===== AND THE POLYLINE IS PUBLISHED, BECAUSE A CURVED ROAD IS STILL A ROAD =====
-- `MapGates` cut its lanes along the straight chord and painted them along the curve, which put up
-- to 9.7 studs of never-cleared ground under the south road's paint and left the guaranteed-clear
-- driving band lying beside the road rather than under it. `MapRoad` was worse: the approach road
-- wanders 15.4 studs off the `MapRoad.LANE` that `MapSquare` keeps the village buildings clear of.
-- `Clearance` is what lets those passes ask the curve the question they were asking the chord, so
-- there is ONE geometry per road instead of two that disagree.

local PathSplines = {}

-- How finely the curve is sampled INTERNALLY, before decimation. These points are thrown away, so
-- the number is not a cost -- it only has to be fine enough that the flatness test below measures
-- the curve rather than measuring its own sampling.
local SAMPLES = 96

-- ===== THE PART COUNT LIVES IN THIS NUMBER =====
-- A point is worth its four parts only where the road actually BENDS. A point survives decimation
-- if dropping it would move the drawn road more than TOLERANCE studs off the curve it is meant to
-- be drawing. One stud on a road 14 to 56 studs wide is narrower than its own dark rim: nobody can
-- see it, and the cap disc at every join exists precisely to cover the corner notch that longer
-- straight pieces leave -- see `MapPaint.Segment`.
local TOLERANCE = 1.0
-- A ceiling as well as a tolerance, because a tolerance alone has no worst case. If a shape needs
-- more than this the tolerance is relaxed until it fits, rather than the road being truncated.
local MAX_POINTS = 24

-- Cubic Catmull-Rom between p1 and p2, with p0 and p3 setting the tangents.
local function catmullRom(p0, p1, p2, p3, t)
	local t2 = t * t
	local t3 = t2 * t
	local v0 = (p2 - p0) * 0.5
	local v1 = (p3 - p1) * 0.5
	return (2 * p1 - 2 * p2 + v0 + v1) * t3
		 + (-3 * p1 + 3 * p2 - 2 * v0 - v1) * t2
		 + v0 * t
		 + p1
end

-- The six control points evaluated as one curve over 0..1.
--
-- THE LAST PIECE IS (p2, p3, p4, p5) AND NOT (p1, p2, p3, p4), AND THAT IS LOAD-BEARING. A
-- Catmull-Rom at t = 1 returns its THIRD control point, so this shape ends exactly on p4 -- the
-- caller's `endPos`. Roads that stopped short of their own ends were R15's fourth fault; this is
-- the arrangement that fixed it. Do not "simplify" the three pieces into one.
local function evalAt(c, g)
	if g <= 1 / 3 then
		return catmullRom(c[1], c[2], c[3], c[4], g * 3)
	elseif g <= 2 / 3 then
		return catmullRom(c[2], c[3], c[4], c[5], (g - 1 / 3) * 3)
	end
	return catmullRom(c[3], c[4], c[5], c[6], math.clamp((g - 2 / 3) * 3, 0, 1))
end

-- ===== OBSTACLES: TWO HONEST TESTS =====
-- Both answer "does this LEG cross the shape", never "are the two boxes near each other".

local function segCircle(ax, az, bx, bz, o)
	local r = o.r or o.radius or 20
	local dx, dz = bx - ax, bz - az
	local len2 = dx * dx + dz * dz
	local t = 0
	if len2 > 0 then
		t = math.clamp(((o.x - ax) * dx + (o.z - az) * dz) / len2, 0, 1)
	end
	local qx, qz = ax + dx * t, az + dz * t
	return (o.x - qx) ^ 2 + (o.z - qz) ^ 2 < r * r
end

-- One Liang-Barsky slab. Returns the narrowed span, or nil when the leg is outside this slab.
local function clip(p, q, t0, t1)
	if p == 0 then
		if q < 0 then return nil end
		return t0, t1
	end
	local r = q / p
	if p < 0 then
		if r > t1 then return nil end
		if r > t0 then t0 = r end
	elseif r < t0 then
		return nil
	elseif r < t1 then
		t1 = r
	end
	return t0, t1
end

-- Segment against an axis-aligned rect, by slab clipping.
--
-- CLIPPED AND NOT AXIS-PICKED, deliberately. `geometry-axis-picked-box-test-lies-at-corners` is the
-- standing note that `if dx > dz` names the wrong face at a corner; a road bent toward the village
-- because a corner test picked the wrong side is worse than a road that was never bent.
local function segRect(ax, az, bx, bz, o)
	local dx, dz = bx - ax, bz - az
	local t0, t1 = 0, 1
	t0, t1 = clip(-dx, ax - (o.x - o.hx), t0, t1)
	if not t0 then return false end
	t0, t1 = clip(dx, (o.x + o.hx) - ax, t0, t1)
	if not t0 then return false end
	t0, t1 = clip(-dz, az - (o.z - o.hz), t0, t1)
	if not t0 then return false end
	t0, t1 = clip(dz, (o.z + o.hz) - az, t0, t1)
	return t0 ~= nil
end

-- Every leg of a sampled polyline against every obstacle. This is the test the old file ran on the
-- straight chord and then never re-ran.
local function polylineHits(pts, obstacles)
	if not obstacles or #obstacles == 0 then return false end
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		for _, o in ipairs(obstacles) do
			local hit
			if o.type == "rect" then
				hit = segRect(a.X, a.Z, b.X, b.Z, o)
			else
				hit = segCircle(a.X, a.Z, b.X, b.Z, o)
			end
			if hit then return true end
		end
	end
	return false
end

-- ===== DECIMATION BY FLATNESS (Douglas-Peucker) =====
-- The two ends are always kept, so the endpoint guarantee above survives decimation by
-- construction: nothing here can move the first or last point.
local function decimate(pts, i, j, tol, keep)
	local ax, az = pts[i].X, pts[i].Z
	local dx, dz = pts[j].X - ax, pts[j].Z - az
	local len2 = dx * dx + dz * dz
	local worst, at = -1, nil
	for k = i + 1, j - 1 do
		local px, pz = pts[k].X, pts[k].Z
		local t = 0
		if len2 > 0 then
			t = math.clamp(((px - ax) * dx + (pz - az) * dz) / len2, 0, 1)
		end
		local qx, qz = ax + dx * t, az + dz * t
		local d = (px - qx) ^ 2 + (pz - qz) ^ 2
		if d > worst then worst, at = d, k end
	end
	if at and worst > tol * tol then
		decimate(pts, i, at, tol, keep)
		keep[at] = true
		decimate(pts, at, j, tol, keep)
	end
end

-- ===== THE ROUTE =====
-- `options`: maxJitter (lateral wander, studs) · yOffset · tolerance · maxPoints
-- `obstacles`: `{ type = "circle", x, z, r }` and `{ type = "rect", x, z, hx, hz }`
--
-- Returns `points, info`. A point is `{ x, z, t }` where `t` is the ARC-LENGTH fraction along the
-- road, 0 at the start and 1 at the end. Callers that ramp a width or a height MUST use `t` and not
-- the point index: decimated points are deliberately unevenly spaced, so `(i - 1) / (#pts - 1)`
-- puts the widening in the wrong place -- badly on a road that is straight at one end and bent at
-- the other, which is every road here.
function PathSplines.Route(startPos, endPos, rng, options, obstacles)
	options = options or {}
	local maxJitter = options.maxJitter or 10
	local yOffset = options.yOffset or 0
	local tol = options.tolerance or TOLERANCE
	local maxPoints = options.maxPoints or MAX_POINTS

	local a = Vector3.new(startPos.X, yOffset, startPos.Z)
	local b = Vector3.new(endPos.X, yOffset, endPos.Z)
	local dir = b - a
	local dist = dir.Magnitude
	if dist < 1 then
		return {}, { points = 0, length = 0, push = 0, blocked = false }
	end
	local right = Vector3.new(-dir.Z, 0, dir.X).Unit

	-- ===== EVERY RANDOM DRAW HAPPENS HERE, BEFORE THE SEARCH =====
	-- `MapGates` runs three lanes off ONE `Random`, so a search that drew while it looked would
	-- make each lane's shape depend on how hard the previous lane had to work. Same map, different
	-- roads, depending on nothing the map can see. Determinism is the rule (OX-BRIEF §3.4).
	local sign = (rng:NextNumber() > 0.5) and 1 or -1
	local o1 = rng:NextNumber(0.4, 0.9) * maxJitter
	local o2 = rng:NextNumber(0.2, 0.7) * maxJitter

	local function sampleAt(pushSide, pushMag)
		local p1 = a
		local p2 = a + dir * 0.35 + right * (sign * o1 + pushSide * pushMag)
		local p3 = a + dir * 0.65 + right * (-sign * o2 + pushSide * pushMag)
		local p4 = b
		local c = { p1 - (p2 - p1), p1, p2, p3, p4, p4 + (p4 - p3) }
		local s = table.create(SAMPLES + 1)
		for i = 0, SAMPLES do
			s[i + 1] = evalAt(c, i / SAMPLES)
		end
		return s
	end

	-- ===== THE SEARCH IS OVER SIDE AND MAGNITUDE, AND IT IS PERPENDICULAR ON PURPOSE =====
	-- The old file pushed along the obstacle's own surface normal, which needs the box test to name
	-- the right face -- the corner trap again. The control points can only move laterally anyway,
	-- so the only real question is WHICH SIDE and HOW FAR, and both are cheap to search directly.
	-- The natural side is tried first at every magnitude, so a road only crosses to the other side
	-- of an obstacle when its own side genuinely cannot get past it.
	local tries = { { sign, 0 } }
	for _, mag in ipairs({ 15, 30, 45, 60, 80 }) do
		tries[#tries + 1] = { sign, mag }
		tries[#tries + 1] = { -sign, mag }
	end

	local chosen, push, blocked = nil, 0, true
	for _, try in ipairs(tries) do
		local s = sampleAt(try[1], try[2])
		if not chosen then chosen = s end
		if not polylineHits(s, obstacles) then
			chosen, push, blocked = s, try[2] * try[1], false
			break
		end
	end

	-- Relax rather than truncate. A shape that cannot be drawn inside `maxPoints` at one stud gets
	-- drawn at two; it never gets cut short, because a road that stops early is the fault this file
	-- was rewritten to stop shipping.
	local keep, kept = nil, 0
	local t = tol
	repeat
		keep = { [1] = true, [#chosen] = true }
		decimate(chosen, 1, #chosen, t, keep)
		kept = 0
		for _ in pairs(keep) do kept += 1 end
		t *= 1.6
	until kept <= maxPoints or t > 100

	local idx = {}
	for i = 1, #chosen do
		if keep[i] then idx[#idx + 1] = i end
	end

	local pts, run = {}, 0
	for k, i in ipairs(idx) do
		if k > 1 then
			run += (chosen[i] - chosen[idx[k - 1]]).Magnitude
		end
		pts[k] = { x = chosen[i].X, z = chosen[i].Z, t = run }
	end
	for _, p in ipairs(pts) do
		p.t = run > 0 and p.t / run or 0
	end

	return pts, { points = #pts, length = run, chord = dist, push = push, blocked = blocked }
end

-- ===== WHAT EVERY OTHER PASS ASKS A CURVED ROAD =====
-- Perpendicular distance from `(x, z)` to the polyline, the closest point on it, and how far along
-- the road that point is (0..1). This is `offsetFrom` in `MapGates` and the `t` in `MapCut.Lane`,
-- generalised from one straight chord to the line that actually got painted.
function PathSplines.Clearance(pts, x, z)
	local best, bx, bz, bt = math.huge, x, z, 0
	for i = 1, #pts - 1 do
		local p, q = pts[i], pts[i + 1]
		local dx, dz = q.x - p.x, q.z - p.z
		local len2 = dx * dx + dz * dz
		local t = 0
		if len2 > 0 then
			t = math.clamp(((x - p.x) * dx + (z - p.z) * dz) / len2, 0, 1)
		end
		local qx, qz = p.x + dx * t, p.z + dz * t
		local d = math.sqrt((x - qx) ^ 2 + (z - qz) ^ 2)
		if d < best then
			best, bx, bz = d, qx, qz
			bt = (p.t or 0) + ((q.t or 1) - (p.t or 0)) * t
		end
	end
	return best, bx, bz, bt
end

return PathSplines
