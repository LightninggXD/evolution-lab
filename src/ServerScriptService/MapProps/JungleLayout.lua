-- MapProps/JungleLayout -- WHERE the wood and its creatures are, as data. Nothing here builds or
-- spawns anything.
--
-- The owner, on a screenshot of the ground behind the village: *"do ovog nije prohodno, rasporedi
-- ih tipa ko u league of legends sumi mozemo tako neki vajb uzeti, ne moze se doci do njih, ova
-- stara forrest mapa nam ne treba vise, samo treba ovu novu main model prosiriti i napraviti novu
-- mapu od toga i rasporediti creatures"*.
--
-- ===== WHAT WAS ACTUALLY WRONG, MEASURED (31.16) =====
-- Not collision. A body-box grid over the whole hunt band -- 29 columns x 16 rows, a 9 x 8.4 x 7
-- box started a stud above the ground at every cell -- came back with **6 blocked cells out of 464**,
-- and all six were single props (a barrel, the fountain, one rock). The band is walkable end to end
-- and has been since 31.2.
--
-- What was missing is every OTHER thing that makes ground reachable. Seventy-four creatures were
-- folded into one 500 x 144 ellipse by `CreatureService.toGlade`, standing on a flat 1250 x 1150
-- green slab with trees sprinkled over it. There is no path to follow, no edge to read a distance
-- against, nothing that says one direction is different from another, and no grouping -- a rig is
-- 40 studs from the next rig in every direction, forever. "You cannot get to them" is what an
-- undifferentiated field feels like from inside it, and no walkability probe can measure that.
--
-- ===== AND THEN THE FIRST ANSWER WAS WRONG TOO (30.23) =====
-- 31.16 answered it with League's own answer: CAMPS -- a named group of monsters in a walled
-- alcove, reached by a path, the dangerous ones deepest. The grouping and the paths were right and
-- they stay. **The WALL was wrong**, and her next screenshot is the proof: a ring of nine boulders
-- around a creature reads, from outside, as exactly the thing she complained about the first time.
-- *"ovi patjovi ne valjaju, ne moze se preko patha doci do creatura, takodje trebaju svi biti u
-- sumi ... puno drveca po celoj mapi, znaci drveca ko u amazonu"*, with a drawing: a cross of roads,
-- a circle in the middle holding the eggs, and all four quadrants filled with trees and creatures.
--
-- So the wall becomes the WOOD. A camp is now a CLEARING -- a floor of dirt with a few low stones
-- on it, standing in dense forest, with a road arriving at its mouth. The rosters, the tiers and
-- the layer gates are untouched; what changed is where the twenty of them stand and what stands
-- around them.
--
-- ===== THIS FILE IS THE ONE COPY OF THOSE COORDINATES =====
-- `MapJungle` builds the clearings and paints the paths from this table, `MapForest` leaves its
-- wood out of both, and `CreatureService` spawns into the same table. The layout that preceded all
-- of it (`MAP_GLADE` + `toGlade`) carried a comment saying *"IT HAS TO STAY IN STEP WITH
-- ForestMapService.MAPS -- one decision written in two files"*, and 31.5a is the bug that comment
-- predicted: `a`/`b` were read as widths in one of the two files and 74 rigs ended up standing over
-- the void. So the layout lives here, alone, and all three consumers ask.
--
-- ===== WHY THE NUMBERS ARE ABSOLUTE AND NOT DERIVED FROM THE MAP SCALE =====
-- Every camp sits at |x| >= 190 and, where it is near the centre line, at |z| >= 390. The village
-- floor is 341 x 290 at scale 1.45 and 270 x 230 at 1.15, so the whole table is outside the
-- village at either scale and does not have to move when the scale does. That is deliberate: a
-- coordinate that follows the scale is a coordinate that silently walks into the boss's arena the
-- day somebody changes it.

local JungleLayout = {}

-- ===== THE FOUR KEEP-OUTS THE CAMPS ARE PLACED AGAINST =====
-- These are `CreatureService.insideKeepOut`'s own rules, restated so the placement can be checked
-- by reading rather than by running. They are NOT enforced here -- CreatureService still applies
-- them to its own scatter, and a camp that broke one would simply be wrong.
--   * THE STREET at |x| < 62. It is the lane from the village to the exit gate and it is the main
--     path below; nothing may stand in it. Nearest camp centre: |x| = 190.
--   * THE ARRIVAL PLAZA, a 110-stud disc at (0, 490). Nearest camp: (-320, 300), 396 away.
--   * THE BOSS, a 132-stud disc at (0, -320). Nearest camp is (-190, -390), 202 studs out, which
--     clears the disc plus a camp's own 46-stud floor.
--   * THE PLATFORM EDGE at |x| > 575 / |z| > 500, which already leaves room for the boundary
--     rampart. Every camp centre is inside |x| <= 530 and |z| <= 455, and an escort stands at most
--     34 studs off its leader, so nothing reaches the rampart.
JungleLayout.CAMP_RADIUS = 46      -- the dirt floor a camp stands on
JungleLayout.CLEARING_RADIUS = 66  -- how far back the WOOD is held: the camp's wall, since 30.23
JungleLayout.ESCORT_RING = 22      -- how far an escort stands from its leader

-- ===== WHAT STANDS IN A CAMP =====
-- The roster is the whole of the tuning. Six archetypes, and between them they account for EVERY
-- creature the zone spawns -- 22 Critters, 30 Swarmers, 6 flat Brutes, 2 flat Elites, and the
-- fourteen that used to be "raised" (4 Apex on layer 2, 4 Elite and 6 Brute on layer 1). The sum is
-- asserted in `Describe` rather than trusted, because the counts live in `CreatureService.TIERS`
-- and `RAISED_LAYOUT` and a camp table that quietly spawns 71 of 74 is invisible.
--
-- `layer` is the rebirth gate a creature carries (11.6): nil for the open ground, 1 for what used
-- to stand on the terraces, 2 for the Apexes. It is the only difference between the two spawn loops
-- in `CreatureService.Init`, and it survives the move to camps unchanged -- which is what keeps the
-- drop tables and the rebirth ladder honest.
JungleLayout.ROSTERS = {
	-- the easy camps: a knot of little things, the first thing you meet leaving the village
	swarm     = { { tier = "Critter", n = 4 }, { tier = "Swarmer", n = 3 } },
	-- one real target with a guard on it
	brute     = { { tier = "Brute",   n = 1 }, { tier = "Swarmer", n = 3 } },
	elite     = { { tier = "Elite",   n = 1 }, { tier = "Critter", n = 3 } },
	-- the three gated camps. These are the fourteen that used to stand on invisible terrace shelves
	-- in the middle of the village (31.4 found them there); on the ground, in a clearing, at the far
	-- end of a path, they are finally the thing the altitude was trying to say.
	raidBrute = { { tier = "Brute",   n = 3, layer = 1 } },
	raidElite = { { tier = "Elite",   n = 2, layer = 1 } },
	apex      = { { tier = "Apex",    n = 1, layer = 2 } },
}

-- ===== THE TWENTY CAMPS, FIVE TO A QUADRANT (30.23) =====
-- Zone-relative. The owner's drawing divides the whole platform into four quadrants around a cross
-- of roads, and asks for trees and creatures in all four -- so the twenty camps that used to sit in
-- one band behind the village are now spread over the whole map.
--
-- THE KIND MULTISET IS UNCHANGED, and that is not tidiness: `Describe` sums the rosters against
-- `CreatureService`'s own tier counts and a redistribution that quietly dropped a `brute` would
-- spawn 70 creatures where the drop tables and the zone's income both assume 74. It is still
-- 4 swarm, 6 brute, 2 elite, 2 raidBrute, 2 raidElite, 4 apex.
--
-- THE DIFFICULTY GRADIENT RUNS NORTH TO SOUTH, because that is the way the player walks: she
-- arrives at the plaza in the north and the exit gate and the boss are in the south. The two north
-- quadrants hold the swarms, the brutes and the two flat elites; the two south quadrants hold every
-- gated camp and all four Apexes.
--
-- EVERY CAMP IS 52 TO 120 STUDS OFF A ROAD and that number is CHECKED AT BOOT, not trusted --
-- `Describe` prints the nearest-road distance for the worst camp in the table. A camp further than
-- a spur's length from the network is the exact fault this row was opened for, and it is invisible
-- from any single screenshot.
local CAMPS_FOREST = {
	-- ---- north-west quadrant, front (plaza end) to back
	{ id = "NW1", kind = "swarm",     x = -320, z =  270 },
	{ id = "NW2", kind = "swarm",     x = -530, z =  300 },
	{ id = "NW3", kind = "brute",     x = -330, z =  120 },
	{ id = "NW4", kind = "brute",     x = -530, z =  130 },
	{ id = "NW5", kind = "elite",     x = -350, z =  -20 },
	-- ---- north-east quadrant, mirrored
	{ id = "NE1", kind = "swarm",     x =  320, z =  270 },
	{ id = "NE2", kind = "swarm",     x =  530, z =  300 },
	{ id = "NE3", kind = "brute",     x =  330, z =  120 },
	{ id = "NE4", kind = "brute",     x =  530, z =  130 },
	{ id = "NE5", kind = "elite",     x =  350, z =  -20 },
	-- ---- south-west quadrant: everything gated, and the deep end of the walk
	{ id = "SW1", kind = "brute",     x = -345, z = -190 },
	{ id = "SW2", kind = "raidBrute", x = -530, z = -280 },
	{ id = "SW3", kind = "raidElite", x = -360, z = -350 },
	{ id = "SW4", kind = "apex",      x = -520, z = -455 },
	{ id = "SW5", kind = "apex",      x = -190, z = -390 },
	-- ---- south-east quadrant, mirrored
	{ id = "SE1", kind = "brute",     x =  345, z = -190 },
	{ id = "SE2", kind = "raidBrute", x =  530, z = -280 },
	{ id = "SE3", kind = "raidElite", x =  360, z = -350 },
	{ id = "SE4", kind = "apex",      x =  520, z = -455 },
	{ id = "SE5", kind = "apex",      x =  190, z = -390 },
}

-- ===== THE PATHS: THE CROSS, AND ONE RING THROUGH ALL FOUR QUADRANTS =====
-- Trunk roads only. Every camp gets a SPUR generated off the nearest trunk point (see `SpurFor`),
-- so a camp moved by ten studs does not need a road re-authored under it -- which is the failure
-- mode a hand-drawn path network has.
--
-- THE CROSS IS THE OWNER'S DRAWING and three of its four arms already existed: the approach road
-- north to the plaza (`MapRoad` plus the entrance funnel), the main lane south to the exit gate,
-- and the two side gates east and west (`MapGates`). What this table adds is the fourth thing the
-- drawing has and the map did not: **a ring**, so each arm of the cross ends somewhere rather than
-- stopping in the trees, and so every quadrant has a road running through it.
--
-- WHY THE RING IS BROKEN AT THE SOUTH AND NOT AT THE NORTH. A straight south leg at z = -400 passes
-- 80 studs from the boss's own 132-stud clearing, i.e. through it. The two legs angle IN to meet
-- the main lane instead, which puts their closest approach at 153 studs and gives the deep camps a
-- road in front of them rather than behind. The north legs run to the plaza's western and eastern
-- corners (the deck spans |x| <= 172), so a player who has just spawned can turn either way into
-- the wood without walking through the village first.
--
-- The coordinates clear the village floor AT EITHER SCALE: the floor's half-width is 341 at 1.45
-- and 270 at 1.15, so a ring at |x| = 450 runs well outside the houses in both worlds.
local PATHS_FOREST = {
	-- ---- the cross
	-- the main lane, village -> exit gate. `CreatureService.insideKeepOut` keeps |x| < 62 empty for
	-- exactly this, so the road is 56 wide and nothing has ever been allowed to stand in it.
	{ id = "S",  x1 =    0, z1 = -240, x2 =    0, z2 = -555, w = 56 },
	-- The two side gates: out of the village, into the flank. **z = -100, NOT z = 0**, and that is
	-- measured rather than chosen. At z = 0 the village half of these two roads runs straight
	-- through the PORTAL RING (zone (-201, 15), r = 45) on one side and the LEADERBOARD RING
	-- ((137, 7), r = 33.5) on the other -- both halls stand inside the village and both are 31.12 /
	-- 31.17 work. A lane search over z -200..+80 found z = -100 clear of non-foliage on BOTH flanks
	-- and z = 0 carrying 27 props on the west alone. `MapGates` cuts the village half at the same
	-- z; the two are one road and this comment is the other end of the one written there.
	{ id = "W",  x1 = -286, z1 = -100, x2 = -450, z2 = -100, w = 46 },
	{ id = "E",  x1 =  286, z1 = -100, x2 =  450, z2 = -100, w = 46 },
	-- ---- the ring
	{ id = "RW", x1 = -450, z1 =  350, x2 = -450, z2 = -400, w = 40 },
	{ id = "RE", x1 =  450, z1 =  350, x2 =  450, z2 = -400, w = 40 },
	{ id = "RNW", x1 = -450, z1 = 350, x2 = -150, z2 =  390, w = 38 },
	{ id = "RNE", x1 =  450, z1 = 350, x2 =  150, z2 =  390, w = 38 },
	{ id = "RSW", x1 = -450, z1 = -400, x2 = -30, z2 = -470, w = 38 },
	{ id = "RSE", x1 =  450, z1 = -400, x2 =  30, z2 = -470, w = 38 },
}

local ZONES = {
	Forest = { camps = CAMPS_FOREST, paths = PATHS_FOREST },
}

-- nil for every zone that is still ZoneBuilder's valley, which is twenty of the twenty-one, and is
-- every caller's cue to lay its creatures out exactly as it does today.
function JungleLayout.Get(zoneKey)
	return ZONES[zoneKey]
end

function JungleLayout.Camps(zoneKey)
	return ZONES[zoneKey] and ZONES[zoneKey].camps or nil
end

function JungleLayout.Paths(zoneKey)
	return ZONES[zoneKey] and ZONES[zoneKey].paths or nil
end

-- The closest point on the trunk network to `(x, z)`, as `px, pz, distance, segment`. Used for the
-- spur, for the opening angle, and by `MapForest` to keep the wood out of the road.
function JungleLayout.NearestPathPoint(zoneKey, x, z)
	local paths = JungleLayout.Paths(zoneKey)
	if not paths then return nil end
	-- Initialised rather than forward-declared, and `bd` starts at infinity rather than nil. Both
	-- are for `tools/luanames.py`: a bare `local a, b, c` is the exact shape its baseline documents
	-- nine false positives of, and one more line a future reader has to decide is harmless is one
	-- line too many (`MapAnchors.measure` carries the same note for the same reason).
	local bx, bz, bd, bseg = nil, nil, math.huge, nil
	for _, p in ipairs(paths) do
		local dx, dz = p.x2 - p.x1, p.z2 - p.z1
		local len2 = dx * dx + dz * dz
		local t = 0
		if len2 > 0 then
			t = ((x - p.x1) * dx + (z - p.z1) * dz) / len2
			t = math.clamp(t, 0, 1)
		end
		local qx, qz = p.x1 + dx * t, p.z1 + dz * t
		local d = math.sqrt((x - qx) ^ 2 + (z - qz) ^ 2)
		if d < bd then bx, bz, bd, bseg = qx, qz, d, p end
	end
	return bx, bz, bd, bseg
end

-- Which way a camp's clearing opens, and since 30.23 it is derived rather than assumed. It used to
-- point at the village centre, which was right when every camp stood in one band south of it and
-- wrong the moment they were spread over four quadrants: a camp in the north-west is approached
-- from the ring beside it, not from the square behind it. The opening faces the nearest road, which
-- is by construction the way the player arrives -- her spur ends there.
function JungleLayout.OpeningAngle(zoneKey, camp)
	local px, pz = JungleLayout.NearestPathPoint(zoneKey, camp.x, camp.z)
	if px and (px ~= camp.x or pz ~= camp.z) then
		return math.atan2(pz - camp.z, px - camp.x)
	end
	-- a camp standing exactly on its own road, or a zone with no roads: face the village
	return math.atan2(-camp.z, -camp.x)
end

-- The spur that connects one camp to the network: from the nearest trunk point to the camp's own
-- OPENING, not to its centre, so the path ends at the mouth of the clearing rather than in the
-- middle of the creatures. Returns nil when the camp is already standing on a road.
function JungleLayout.SpurFor(zoneKey, camp)
	local px, pz, d = JungleLayout.NearestPathPoint(zoneKey, camp.x, camp.z)
	if not px or d < JungleLayout.CAMP_RADIUS then return nil end
	local a = JungleLayout.OpeningAngle(zoneKey, camp)
	local mouthX = camp.x + math.cos(a) * JungleLayout.CAMP_RADIUS
	local mouthZ = camp.z + math.sin(a) * JungleLayout.CAMP_RADIUS
	return { id = camp.id .. "spur", x1 = px, z1 = pz, x2 = mouthX, z2 = mouthZ, w = 26 }
end

-- ===== EVERY PIECE OF ROAD IN THE ZONE, TRUNKS AND SPURS, IN ONE LIST (30.23) =====
-- `MapJungle` paints this and `MapForest` keeps its trees out of it, and before this function
-- existed the second of those two knew about the trunks only -- so a spur was a road with a wood
-- planted across it. One list, two consumers, no second copy of how a spur is derived.
function JungleLayout.Segments(zoneKey)
	local paths = JungleLayout.Paths(zoneKey)
	if not paths then return nil end
	local out = {}
	for _, p in ipairs(paths) do out[#out + 1] = p end
	for _, camp in ipairs(JungleLayout.Camps(zoneKey) or {}) do
		local spur = JungleLayout.SpurFor(zoneKey, camp)
		if spur then out[#out + 1] = spur end
	end
	return out
end

-- Perpendicular distance from `(x, z)` to the nearest road SURFACE (its edge, not its centre
-- line), spurs included. Negative means the point is on the road. This is what a planter asks.
function JungleLayout.RoadClearance(zoneKey, x, z, segments)
	segments = segments or JungleLayout.Segments(zoneKey)
	if not segments then return math.huge end
	local best = math.huge
	for _, p in ipairs(segments) do
		local dx, dz = p.x2 - p.x1, p.z2 - p.z1
		local len2 = dx * dx + dz * dz
		local t = 0
		if len2 > 0 then
			t = math.clamp(((x - p.x1) * dx + (z - p.z1) * dz) / len2, 0, 1)
		end
		local qx, qz = p.x1 + dx * t, p.z1 + dz * t
		local d = math.sqrt((x - qx) ^ 2 + (z - qz) ^ 2) - p.w / 2
		if d < best then best = d end
	end
	return best
end

-- Distance from `(x, z)` to the nearest camp CENTRE. The planter holds the wood back by
-- `CLEARING_RADIUS`, which is what makes a camp a room in the forest rather than a coordinate.
function JungleLayout.CampClearance(zoneKey, x, z)
	local camps = JungleLayout.Camps(zoneKey)
	if not camps then return math.huge end
	local best = math.huge
	for _, c in ipairs(camps) do
		local d = math.sqrt((x - c.x) ^ 2 + (z - c.z) ^ 2)
		if d < best then best = d end
	end
	return best
end

-- Every creature this layout asks for, flattened: `{ x, z, tier, layer, camp }`. ONE function, so
-- the builder and the spawner cannot disagree about how a roster becomes positions.
--
-- The leader stands at the centre and the escorts on a ring, spread evenly and jittered off it. The
-- jitter is drawn from a generator SEEDED OFF THE ZONE rather than off the clock, for the reason
-- `raisedSpots` and `MapForest` both are: two servers of the same place have to lay their creatures
-- out identically or a screenshot from one does not describe the other.
function JungleLayout.Spawns(zoneKey)
	local camps = JungleLayout.Camps(zoneKey)
	if not camps then return nil end
	local rng = Random.new(20260822)
	local out = {}
	for _, camp in ipairs(camps) do
		local roster = JungleLayout.ROSTERS[camp.kind]
		if roster then
			-- flatten the roster first so the ring can be shared out across every escort in the
			-- camp rather than restarting per row -- two rows of three on the same ring at the same
			-- angles is two creatures in one spot.
			local members = {}
			for _, row in ipairs(roster) do
				for _ = 1, row.n do
					members[#members + 1] = { tier = row.tier, layer = row.layer }
				end
			end
			-- The leader is whatever the roster names first. The remaining members ring it.
			local escorts = #members - 1
			local open = JungleLayout.OpeningAngle(zoneKey, camp)
			for i, m in ipairs(members) do
				local x, z = camp.x, camp.z
				if i > 1 and escorts > 0 then
					-- Biased AWAY from the opening, so the mouth of the clearing stays clear and you
					-- can see into the camp before you are standing in it.
					local a = open + math.pi
						+ (i - 2 - (escorts - 1) / 2) * (math.pi * 1.4 / math.max(escorts, 1))
					local r = JungleLayout.ESCORT_RING + rng:NextNumber(-5, 7)
					x = camp.x + math.cos(a) * r
					z = camp.z + math.sin(a) * r
				end
				out[#out + 1] = {
					x = x, z = z, tier = m.tier, layer = m.layer, camp = camp.id,
				}
			end
		end
	end
	return out
end

-- One line for the boot log, and it is a CENSUS rather than a boolean: the only thing that catches
-- a roster that quietly stopped covering every tier is a count printed beside the count it should
-- equal. Pass the table `CreatureService` actually holds and this says whether they agree.
--
-- Since 30.23 it also prints THE WORST CAMP'S DISTANCE TO A ROAD. That is the row's own complaint
-- in one number: a camp whose spur is 300 studs long is a camp nobody walks to, and no capture of
-- any other part of the map shows it.
function JungleLayout.Describe(zoneKey, expected)
	local spawns = JungleLayout.Spawns(zoneKey)
	if not spawns then return zoneKey .. ": no jungle" end
	local got = {}
	for _, s in ipairs(spawns) do got[s.tier] = (got[s.tier] or 0) + 1 end
	local parts, bad = {}, 0
	local names = {}
	for t in pairs(got) do names[#names + 1] = t end
	if expected then
		for t in pairs(expected) do if got[t] == nil then names[#names + 1] = t end end
	end
	table.sort(names)
	for _, t in ipairs(names) do
		local want = expected and expected[t]
		local have = got[t] or 0
		if want and want ~= have then
			parts[#parts + 1] = ("%s %d/WANT %d"):format(t, have, want)
			bad += 1
		else
			parts[#parts + 1] = ("%s %d"):format(t, have)
		end
	end

	local worst, worstId = 0, "-"
	for _, camp in ipairs(JungleLayout.Camps(zoneKey)) do
		local _, _, d = JungleLayout.NearestPathPoint(zoneKey, camp.x, camp.z)
		if d and d > worst then worst, worstId = d, camp.id end
	end

	return ("%s: %d camps, %d creatures (%s), furthest camp from a road: %s at %.0f studs%s")
		:format(zoneKey, #JungleLayout.Camps(zoneKey), #spawns, table.concat(parts, ", "),
			worstId, worst, bad > 0 and "  <-- ROSTER DOES NOT MATCH THE TIER COUNTS" or "")
end

return JungleLayout
