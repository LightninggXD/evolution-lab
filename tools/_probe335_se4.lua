-- 33.5 -- WHERE SE4 CAN STAND SO THE S TRUNK STOPS LYING ACROSS ITS CLEARING.
--
-- The alarm is live and it is `JungleLayout.Describe`'s own last line:
--     tightest road across a floor it does not serve: S vs SE4 at -32.1 studs
--       <-- A ROAD IS LYING ACROSS A CLEARING
--
-- SE4 is authored at (33, -650), i.e. essentially ON the zone's centre line, and the S trunk IS
-- the centre line (x = 0, z -240..-555, 56 wide). After the shrink SE4 lands 15.9 studs off it,
-- against a road half-width of 28 and a camp radius of 20 -- so the paint overlaps the clearing by
-- 32.1 studs.
--
-- ===== WHY THIS REPLICATES THE PLACEMENT INSTEAD OF EDITING AND REBUILDING PER CANDIDATE =====
-- Moving one camp is not a local edit. `pullCamp` places camps INNER-FIRST and clamps each against
-- the ones already standing, so a camp that moves outward can push the ones behind it -- which is
-- exactly how 32.18's "move SE2 alone" ended at an east edge of 403.5 with SE5 next in the chain.
-- The only honest search re-runs the whole placement per candidate.
--
-- ===== AND IT PROVES ITSELF FIRST =====
-- `PullIn` is the real exported function; `villageGap`, `campGap`, `campClear` and `pullCamp` are
-- replicated here from the module, and a replica that has drifted is worse than no probe at all.
-- So S0 re-runs the CURRENT table through the replica and compares every camp against the live
-- `JungleLayout.Camps` to 0.01 studs. If S0 does not print MATCH, nothing below it means anything.
--
-- What it cannot answer: the TRAILS. `Segments` includes a per-camp trail grown by `JungleTrails`,
-- and a moved camp gets a different trail which could itself lie across another camp. Trails are
-- not replicated here, so this probe scores against the TRUNKS only and the winner has to be
-- confirmed by an actual rebuild reading `Describe`'s real line. That is stated in the output.

local JL = require(game:GetService("ServerScriptService").MapProps.JungleLayout)

local VILLAGE_HALF_X, VILLAGE_HALF_Z = 270.5, 230
local R = JL.CAMP_RADIUS
local MIN_VILLAGE_CLEAR = R + 8
local MIN_CAMP_SEPARATION = R * 2 + 20
local DIAL = JL.HUNT_SHRINK

-- The authored table, transcribed. Kept here rather than read off the module because the module
-- OVERWRITES `camp.x/.z` with the pulled values at load (it keeps `x0/z0`), so reading it back
-- gives the answer, not the question.
local AUTHORED = {
	{ id = "NW1", x = -411, z = 179 }, { id = "NW2", x = -622, z = 460 },
	{ id = "NW3", x = -241, z = 370 }, { id = "NW4", x = -212, z = 650 },
	{ id = "NW5", x = -551, z = 159 },
	{ id = "NE1", x = 411, z = 209 },  { id = "NE2", x = 283, z = 650 },
	{ id = "NE3", x = 411, z = 80 },   { id = "NE4", x = 564, z = 555 },
	{ id = "NE5", x = 410, z = 302 },
	{ id = "SW1", x = -84, z = -370 }, { id = "SW2", x = -174, z = -650 },
	{ id = "SW3", x = -174, z = -370 }, { id = "SW4", x = -371, z = -638 },
	{ id = "SW5", x = -551, z = -229 },
	{ id = "SE1", x = 209, z = -370 }, { id = "SE2", x = 417, z = -278 },
	{ id = "SE3", x = 115, z = -370 }, { id = "SE4", x = 33, z = -650 },
	{ id = "SE5", x = 410, z = -11 },
}

local TRUNKS = {
	{ id = "S", x1 = 0, z1 = -240, x2 = 0, z2 = -555, w = 56 },
	{ id = "W", x1 = -286, z1 = -100, x2 = -450, z2 = -100, w = 46 },
	{ id = "E", x1 = 286, z1 = -100, x2 = 450, z2 = -100, w = 46 },
}

local function villageGap(x, z)
	local dx = math.max(math.abs(x) - VILLAGE_HALF_X, 0)
	local dz = math.max(math.abs(z) - VILLAGE_HALF_Z, 0)
	return math.sqrt(dx * dx + dz * dz)
end

-- One full placement over a table of authored camps. Returns the placed list.
local function placeAll(list)
	local order = {}
	for i = 1, #list do order[i] = i end
	table.sort(order, function(a, b)
		local ga, gb = villageGap(list[a].x, list[a].z), villageGap(list[b].x, list[b].z)
		if ga ~= gb then return ga < gb end
		return a < b
	end)
	local placed, byId = {}, {}
	local function campGap(x, z)
		local best = math.huge
		for _, p in ipairs(placed) do
			local d = math.sqrt((x - p.x) ^ 2 + (z - p.z) ^ 2)
			if d < best then best = d end
		end
		return best
	end
	local function campClear(c, x, z)
		if campGap(x, z) < MIN_CAMP_SEPARATION then return false end
		if villageGap(c.x, c.z) < MIN_VILLAGE_CLEAR then return true end
		return villageGap(x, z) >= MIN_VILLAGE_CLEAR
	end
	for _, i in ipairs(order) do
		local c = list[i]
		local x, z = JL.PullIn(c.x, c.z, DIAL)
		if not campClear(c, x, z) then
			local lo, hi = DIAL, 1
			for _ = 1, 12 do
				local mid = (lo + hi) / 2
				local mx, mz = JL.PullIn(c.x, c.z, mid)
				if campClear(c, mx, mz) then hi = mid else lo = mid end
			end
			x, z = JL.PullIn(c.x, c.z, hi)
		end
		local e = { id = c.id, x = x, z = z }
		placed[#placed + 1] = e
		byId[c.id] = e
	end
	return placed, byId
end

-- The three metrics the row and its neighbours are judged on.
local function score(placed)
	local road, roadId = math.huge, "-"
	for _, s in ipairs(TRUNKS) do
		for _, c in ipairs(placed) do
			local dx, dz = s.x2 - s.x1, s.z2 - s.z1
			local len2 = dx * dx + dz * dz
			local t = len2 > 0 and math.clamp(((c.x - s.x1) * dx + (c.z - s.z1) * dz) / len2, 0, 1) or 0
			local qx, qz = s.x1 + dx * t, s.z1 + dz * t
			local d = math.sqrt((c.x - qx) ^ 2 + (c.z - qz) ^ 2) - s.w / 2 - R
			if d < road then road, roadId = d, s.id .. " vs " .. c.id end
		end
	end
	local camp, campId = math.huge, "-"
	for i = 1, #placed do
		for j = i + 1, #placed do
			local d = math.sqrt((placed[i].x - placed[j].x) ^ 2 + (placed[i].z - placed[j].z) ^ 2) - 2 * R
			if d < camp then camp, campId = d, placed[i].id .. "/" .. placed[j].id end
		end
	end
	local near, nearId, mx, mz = math.huge, "-", 0, 0
	for _, c in ipairs(placed) do
		local g = villageGap(c.x, c.z)
		if g < near then near, nearId = g, c.id end
		mx = math.max(mx, math.abs(c.x))
		mz = math.max(mz, math.abs(c.z))
	end
	return road, roadId, camp, campId, near, nearId, mx, mz
end

local out = {}
local function p(s) out[#out + 1] = s end

-- ===== S0: the replica must reproduce the live module =====
local _, mine = placeAll(AUTHORED)
local live = JL.Camps("Forest")
local worstErr, worstWho = 0, "-"
for _, c in ipairs(live) do
	local m = mine[c.id]
	if m then
		local e = math.max(math.abs(m.x - c.x), math.abs(m.z - c.z))
		if e > worstErr then worstErr, worstWho = e, c.id end
	end
end
p(("S0 replica vs live: worst disagreement %.4f studs (%s) -- %s")
	:format(worstErr, worstWho, worstErr < 0.01 and "MATCH" or "*** DRIFTED, IGNORE EVERYTHING BELOW ***"))
local base = placeAll(AUTHORED)
local r0, rid0, c0, cid0, n0, nid0, mx0, mz0 = score(base)
p(("S1 today: road %+.1f (%s) | camp gap %+.1f (%s) | closest village %.1f (%s) | max |x| %.0f |z| %.0f")
	:format(r0, rid0, c0, cid0, n0, nid0, mx0, mz0))

-- ===== EVERY OFFENDER, NOT THE WORST ONE =====
-- `Describe` prints a single `tightest road across a floor` and that is how a second violation
-- hides behind the first: the search below could only ever reach -7.3 no matter where SE4 went,
-- because SE4 was never the only camp under a trunk. Listing them all is half of what row 33.5
-- means by "make the alarm unmissable".
local offenders = {}
for _, sg in ipairs(TRUNKS) do
	for _, c in ipairs(base) do
		local dx, dz = sg.x2 - sg.x1, sg.z2 - sg.z1
		local len2 = dx * dx + dz * dz
		local t = len2 > 0 and math.clamp(((c.x - sg.x1) * dx + (c.z - sg.z1) * dz) / len2, 0, 1) or 0
		local qx, qz = sg.x1 + dx * t, sg.z1 + dz * t
		local d = math.sqrt((c.x - qx) ^ 2 + (c.z - qz) ^ 2) - sg.w / 2 - R
		if d < 0 then
			offenders[#offenders + 1] = ("%s vs %s %+.1f (camp at %.0f, %.0f)")
				:format(sg.id, c.id, d, c.x, c.z)
		end
	end
end
table.sort(offenders)
p(("S1b every trunk lying across a floor it does not serve: %d -- %s")
	:format(#offenders, #offenders > 0 and table.concat(offenders, " | ") or "none"))

-- ===== S2: THE SEARCH, AND IT HAS TO BE BOTH CAMPS =====
-- S1b is why: SE4 could go anywhere on a 585-point grid and the metric still bottomed out at
-- -7.3, because SW5 is under the W trunk too and `Describe` only ever prints the worse of the two.
--
-- The two are swept SEPARATELY and then the winning pair is re-scored TOGETHER. They sit in
-- different quadrants 400 studs apart, so the separation clamp cannot couple them -- but "cannot"
-- is a prediction, and S3 below is the measurement that replaces it.
local function sweep(id, xs, xe, xstep, zs, ze, zstep, others)
	local rows = {}
	for ax = xs, xe, xstep do
		for az = zs, ze, zstep do
			local trial = {}
			for i, c in ipairs(AUTHORED) do
				if c.id == id then
					trial[i] = { id = id, x = ax, z = az }
				elseif others and others[c.id] then
					trial[i] = { id = c.id, x = others[c.id].x, z = others[c.id].z }
				else
					trial[i] = c
				end
			end
			local placed = placeAll(trial)
			local road, roadId, camp, campId, near, _, mxx, mzz = score(placed)
			rows[#rows + 1] = { ax = ax, az = az, road = road, roadId = roadId, camp = camp,
				campId = campId, near = near, mx = mxx, mz = mzz }
		end
	end
	-- Ranked by the metric the row is judged on, then by staying as close to the authored drawing
	-- as the metric allows -- a camp that solves the road by fleeing to the map edge is 32.18's
	-- problem, not a fix.
	table.sort(rows, function(a, b)
		if math.abs(a.road - b.road) > 0.5 then return a.road > b.road end
		return (a.mx + a.mz) < (b.mx + b.mz)
	end)
	return rows
end

local function report(label, rows, n)
	p(("%s -- %d positions, best %d:"):format(label, #rows, math.min(n, #rows)))
	for i = 1, math.min(n, #rows) do
		local b = rows[i]
		p(("   (%5d, %5d) road %+6.1f (%s) | camp %+5.1f (%s) | village %.0f | max |x| %.0f |z| %.0f")
			:format(b.ax, b.az, b.road, b.roadId, b.camp, b.campId, b.near, b.mx, b.mz))
	end
	return rows[1]
end

local bestSW5 = report("S2a SW5 swept (SE4 left where it is)",
	sweep("SW5", -640, -380, 20, -320, -180, 10, nil), 6)
-- SE4 is swept with SW5 already at its winner, so the number it is ranked on is the real one.
local fixSW5 = { SW5 = { x = bestSW5.ax, z = bestSW5.az } }
local bestSE4 = report("S2b SE4 swept (SW5 at its winner)",
	sweep("SE4", 40, 420, 10, -700, -420, 20, fixSW5), 6)

-- ===== S3: the pair, scored together =====
local both = {}
for i, c in ipairs(AUTHORED) do
	if c.id == "SW5" then both[i] = { id = "SW5", x = bestSW5.ax, z = bestSW5.az }
	elseif c.id == "SE4" then both[i] = { id = "SE4", x = bestSE4.ax, z = bestSE4.az }
	else both[i] = c end
end
local placedBoth = placeAll(both)
local rB, ridB, cB, cidB, nB, nidB, mxB, mzB = score(placedBoth)
p(("S3 BOTH moved -- SW5 (%d, %d), SE4 (%d, %d):"):format(
	bestSW5.ax, bestSW5.az, bestSE4.ax, bestSE4.az))
p(("   road %+.1f (%s) | camp gap %+.1f (%s) | closest village %.1f (%s) | max |x| %.0f |z| %.0f")
	:format(rB, ridB, cB, cidB, nB, nidB, mxB, mzB))
p(("   vs today: road %+.1f -> %+.1f | camp %+.1f -> %+.1f | village %.1f -> %.1f")
	:format(r0, rB, c0, cB, n0, nB))
local off2 = {}
for _, sg in ipairs(TRUNKS) do
	for _, c in ipairs(placedBoth) do
		local dx, dz = sg.x2 - sg.x1, sg.z2 - sg.z1
		local len2 = dx * dx + dz * dz
		local t = len2 > 0 and math.clamp(((c.x - sg.x1) * dx + (c.z - sg.z1) * dz) / len2, 0, 1) or 0
		local qx, qz = sg.x1 + dx * t, sg.z1 + dz * t
		local d = math.sqrt((c.x - qx) ^ 2 + (c.z - qz) ^ 2) - sg.w / 2 - R
		if d < 0 then off2[#off2 + 1] = ("%s vs %s %+.1f"):format(sg.id, c.id, d) end
	end
end
p(("   trunks still lying across a floor: %d %s"):format(#off2,
	#off2 > 0 and ("-- " .. table.concat(off2, " | ")) or ""))
-- Where the two actually END UP, which is what the table's comment column has to say.
for _, c in ipairs(placedBoth) do
	if c.id == "SW5" or c.id == "SE4" then
		p(("   %s final (%.1f, %.1f) village gap %.1f"):format(c.id, c.x, c.z, villageGap(c.x, c.z)))
	end
end

-- ===== S4: THE SHORTLIST, CHOSEN BY THE DRAWING AND SCORED BY THE PROBE =====
-- S2/S3 tie at +10.6 across dozens of positions -- once both camps are off the trunks the binding
-- constraint becomes `S vs SW1`, which is pre-existing and not this row's. So the metric stops
-- discriminating and the DRAWING has to choose, which is the right way round: 30.23 put the deep
-- end of the walk in the south and made SE4/SW5 apex camps, and an apex that lands on the inner
-- band beside the village is exactly the oddity row 33.3 is already complaining about (SE5 at a
-- village gap of 28). S3's own winner puts SE4 at a gap of 38 -- metric-perfect and wrong.
local SHORTLIST = {
	{ SW5 = { -551, -290 }, SE4 = { 300, -560 }, why = "both keep their authored bearing; z pushed out" },
	{ SW5 = { -551, -300 }, SE4 = { 260, -600 }, why = "SE4 stays deeper south" },
	{ SW5 = { -580, -290 }, SE4 = { 300, -560 }, why = "SW5 also stepped out in x" },
	{ SW5 = { -551, -280 }, SE4 = { 340, -520 }, why = "SE4 further round the quadrant" },
}
p("S4 shortlist -- chosen by the drawing, scored here:")
for _, cand in ipairs(SHORTLIST) do
	local t = {}
	for i, c in ipairs(AUTHORED) do
		if cand[c.id] then t[i] = { id = c.id, x = cand[c.id][1], z = cand[c.id][2] }
		else t[i] = c end
	end
	local placed = placeAll(t)
	local road, roadId, camp, campId, near, nearId, mxx, mzz = score(placed)
	local n = 0
	for _, sg in ipairs(TRUNKS) do
		for _, c in ipairs(placed) do
			local dx, dz = sg.x2 - sg.x1, sg.z2 - sg.z1
			local len2 = dx * dx + dz * dz
			local tt = len2 > 0 and math.clamp(((c.x - sg.x1) * dx + (c.z - sg.z1) * dz) / len2, 0, 1) or 0
			local qx, qz = sg.x1 + dx * tt, sg.z1 + dz * tt
			if math.sqrt((c.x - qx) ^ 2 + (c.z - qz) ^ 2) - sg.w / 2 - R < 0 then n += 1 end
		end
	end
	local fin = {}
	for _, c in ipairs(placed) do
		if cand[c.id] then
			fin[#fin + 1] = ("%s -> (%.0f, %.0f) gap %.0f"):format(c.id, c.x, c.z, villageGap(c.x, c.z))
		end
	end
	table.sort(fin)
	p(("   SW5 (%d,%d) SE4 (%d,%d): road %+.1f (%s) | camp %+.1f | village %.1f | across %d | %s")
		:format(cand.SW5[1], cand.SW5[2], cand.SE4[1], cand.SE4[2], road, roadId, camp, near, n,
			table.concat(fin, "; ")))
	p(("      %s"):format(cand.why))
end

p("NOTE: scored against the THREE TRUNKS only -- trails are not replicated here, so the winner")
p("      must be confirmed by a rebuild reading Describe's own road line.")
return table.concat(out, "\n")
