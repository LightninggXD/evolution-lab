-- MapProps/JungleLayout -- WHERE the jungle is, as data. Nothing here builds or spawns anything.
--
-- The owner, on a screenshot of the ground behind the village: *"do ovog nije prohodno, rasporedi
-- ih tipa ko u league of legends sumi mozemo tako neki vajb uzeti, ne moze se doci do njih, ova
-- stara forrest mapa nam ne treba vise, samo treba ovu novu main model prosiriti i napraviti novu
-- mapu od toga i rasporediti creatures"*.
--
-- ===== WHAT WAS ACTUALLY WRONG, MEASURED =====
-- Not collision. A body-box grid over the whole hunt band -- 29 columns x 16 rows, a 9 x 8.4 x 7
-- box started a stud above the ground at every cell -- came back with **6 blocked cells out of 464**,
-- and all six were single props (a barrel, the fountain, one rock). The band is walkable end to end
-- and has been since 31.2.
--
-- What is missing is every OTHER thing that makes ground reachable. Seventy-four creatures were
-- folded into one 500 x 144 ellipse by `CreatureService.toGlade`, standing on a flat 1250 x 1150
-- green slab with trees sprinkled over it. There is no path to follow, no edge to read a distance
-- against, nothing that says one direction is different from another, and no grouping -- a rig is
-- 40 studs from the next rig in every direction, forever. "You cannot get to them" is what an
-- undifferentiated field feels like from inside it, and no walkability probe can measure that.
--
-- ===== WHY LEAGUE'S JUNGLE IS THE RIGHT REFERENCE =====
-- It solves exactly this problem: a large area with no lanes through it. Its answer is CAMPS -- a
-- fixed, named group of monsters standing in a walled alcove, reached by a path, with the dangerous
-- ones deepest. Three properties fall out of that and all three are what this zone lacks:
--   * a creature is part of a GROUP, so killing one thing means killing a camp;
--   * a camp has a WALL around it, so it is a place rather than a coordinate;
--   * a PATH leads to it, so "over there" is a direction and not a guess.
--
-- ===== THIS FILE IS THE ONE COPY OF THOSE COORDINATES =====
-- `MapJungle` builds the rock alcoves and the paths from this table; `CreatureService` spawns into
-- the same table. The layout that replaced it (`MAP_GLADE` + `toGlade`) carried a comment saying
-- *"IT HAS TO STAY IN STEP WITH ForestMapService.MAPS -- one decision written in two files"*, and
-- 31.5a is the bug that comment predicted: `a`/`b` were read as widths in one of the two files and
-- 74 rigs ended up standing over the void. So the camps live here, alone, and both consumers ask.
--
-- ===== WHY THE NUMBERS ARE ABSOLUTE AND NOT DERIVED FROM THE MAP SCALE =====
-- Every camp sits at |x| >= 160 and, where it is near the centre line, at |z| >= 300. The village
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
--     path below; nothing may stand in it. Nearest camp centre: |x| = 160.
--   * THE ARRIVAL PLAZA, a 110-stud disc at (0, 490). Nearest camp: (360, 110), 570 away.
--   * THE BOSS, a ~132-stud disc at (-400, -430) since 31.4. This is why the south-west is empty of
--     camps and the south-east holds two extra: the boss IS the south-west camp. Nearest is
--     (-300, -310), 156 studs out, which clears the disc plus a camp's own 46-stud ring.
--   * THE PLATFORM EDGE at |x| > 575 / |z| > 500, which already leaves room for the boundary
--     rampart. Every camp centre is inside |x| <= 530 and |z| <= 470, and an escort stands at most
--     34 studs off its leader, so nothing reaches the rampart.
JungleLayout.CAMP_RADIUS = 46      -- the rock ring's radius; the alcove the camp stands in
JungleLayout.ESCORT_RING = 22      -- how far an escort stands from its leader
JungleLayout.OPENING_ARC = 105     -- degrees of the ring left out, so a camp can be walked into

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
	-- in the middle of the village (31.4 found them there); on the ground, in a walled alcove, at
	-- the far end of a path, they are finally the thing the altitude was trying to say.
	raidBrute = { { tier = "Brute",   n = 3, layer = 1 } },
	raidElite = { { tier = "Elite",   n = 2, layer = 1 } },
	apex      = { { tier = "Apex",    n = 1, layer = 2 } },
}

-- ===== THE TWENTY CAMPS =====
-- Zone-relative. Ordered the way you meet them: the two flanks first (they are beside the village
-- and are what the side gates open onto), then the south field, which is the walk to the exit gate.
--
-- FLANK CAMPS STOP AT z = 130 AND THAT IS NOT A ROUNDING. `ForestMapService.MAPS.Forest.clear`
-- clears the map's mountain ring off both flanks only up to z = 150, because north of that the ring
-- is the horizon behind the arrival plaza and is doing scenery work. A camp at z = 250 would be
-- inside a mountain, with nothing errored and nothing logged -- the 30.19 trap exactly.
local CAMPS_FOREST = {
	-- ---- west flank, front to back
	{ id = "W1", kind = "swarm",     x = -360, z =  110 },
	{ id = "W2", kind = "brute",     x = -520, z =   60 },
	{ id = "W3", kind = "swarm",     x = -350, z =  -40 },
	{ id = "W4", kind = "apex",      x = -530, z =  -90 },
	{ id = "W5", kind = "raidBrute", x = -390, z = -170 },
	-- ---- east flank, mirrored
	{ id = "E1", kind = "swarm",     x =  360, z =  110 },
	{ id = "E2", kind = "brute",     x =  520, z =   60 },
	{ id = "E3", kind = "swarm",     x =  350, z =  -40 },
	{ id = "E4", kind = "apex",      x =  530, z =  -90 },
	{ id = "E5", kind = "raidBrute", x =  390, z = -170 },
	-- ---- the south field: the walk from the village to the exit gate
	{ id = "S1", kind = "brute",     x = -170, z = -300 },
	{ id = "S2", kind = "brute",     x =  170, z = -300 },
	{ id = "S3", kind = "raidElite", x = -300, z = -310 },
	{ id = "S4", kind = "raidElite", x =  300, z = -310 },
	{ id = "S5", kind = "elite",     x = -520, z = -320 },
	{ id = "S6", kind = "elite",     x =  520, z = -320 },
	{ id = "S7", kind = "apex",      x = -160, z = -470 },
	{ id = "S8", kind = "apex",      x =  160, z = -470 },
	-- the two the south-WEST would have held. The boss owns that corner, so they are here.
	{ id = "S9",  kind = "brute",    x =  350, z = -450 },
	{ id = "S10", kind = "brute",    x =  520, z = -460 },
}

-- ===== THE PATHS =====
-- Trunk roads only. Every camp gets a SPUR generated off the nearest trunk point (see `SpurFor`),
-- so a camp moved by ten studs does not need a road re-authored under it -- which is the failure
-- mode a hand-drawn path network has.
--
-- The coordinates are chosen to clear the village floor AT EITHER SCALE: the floor's half-width is
-- 341 at 1.45 and 270 at 1.15, so a road at |x| = 360 runs beside the houses in both worlds. The
-- main lane starts at z = -300 for the same reason (the floor reaches z = -290 at 1.45).
local PATHS_FOREST = {
	-- the main lane, village -> exit gate. `CreatureService.insideKeepOut` keeps |x| < 62 empty for
	-- exactly this, so the road is 62 wide and nothing has ever been allowed to stand in it.
	{ x1 =    0, z1 = -240, x2 =    0, z2 = -560, w = 56 },
	-- the two side gates: out of the square, into the flank
	{ x1 = -270, z1 =    0, x2 = -360, z2 =    0, w = 40 },
	{ x1 =  270, z1 =    0, x2 =  360, z2 =    0, w = 40 },
	-- the flank roads, running the depth of both pockets
	{ x1 = -360, z1 =  130, x2 = -360, z2 = -230, w = 40 },
	{ x1 =  360, z1 =  130, x2 =  360, z2 = -230, w = 40 },
	-- ...and back in to the main lane, so the flanks are a loop rather than two dead ends
	{ x1 = -360, z1 = -230, x2 =  -40, z2 = -330, w = 36 },
	{ x1 =  360, z1 = -230, x2 =   40, z2 = -330, w = 36 },
	-- the deep crossing, in front of the last row of camps
	{ x1 =  -40, z1 = -430, x2 = -420, z2 = -470, w = 32 },
	{ x1 =   40, z1 = -430, x2 =  460, z2 = -470, w = 32 },
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
	local z = ZONES[zoneKey]
	return z and z.camps or nil
end

function JungleLayout.Paths(zoneKey)
	local z = ZONES[zoneKey]
	return z and z.paths or nil
end

-- Which way a camp's ring is left open. Toward the village centre for every one of them: that is
-- where the player is walking FROM, so the gap is in the wall you would actually arrive at. A
-- camp opening away from the approach is a camp you walk all the way around.
function JungleLayout.OpeningAngle(camp)
	return math.atan2(-camp.z, -camp.x)
end

-- The closest point on the trunk network to `(x, z)`, as `px, pz, distance`. Used for the spur, and
-- by the connectivity probe to say which road a camp hangs off.
function JungleLayout.NearestPathPoint(zoneKey, x, z)
	local paths = JungleLayout.Paths(zoneKey)
	if not paths then return nil end
	-- Initialised rather than forward-declared, and `bd` starts at infinity rather than nil. Both
	-- are for `tools/luanames.py`: a bare `local a, b, c` is the exact shape its baseline documents
	-- nine false positives of, and one more line a future reader has to decide is harmless is one
	-- line too many (`MapAnchors.measure` carries the same note for the same reason).
	local bx, bz, bd = nil, nil, math.huge
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
		if d < bd then bx, bz, bd = qx, qz, d end
	end
	return bx, bz, bd
end

-- The spur that connects one camp to the network: from the nearest trunk point to the camp's own
-- OPENING, not to its centre, so the path ends at the gap in the rocks instead of running into the
-- back of the wall. Returns nil when the camp is already standing on a road.
function JungleLayout.SpurFor(zoneKey, camp)
	local px, pz, d = JungleLayout.NearestPathPoint(zoneKey, camp.x, camp.z)
	if not px or d < JungleLayout.CAMP_RADIUS then return nil end
	local a = JungleLayout.OpeningAngle(camp)
	local mouthX = camp.x + math.cos(a) * JungleLayout.CAMP_RADIUS
	local mouthZ = camp.z + math.sin(a) * JungleLayout.CAMP_RADIUS
	return { x1 = px, z1 = pz, x2 = mouthX, z2 = mouthZ, w = 26 }
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
			for i, m in ipairs(members) do
				local x, z = camp.x, camp.z
				if i > 1 and escorts > 0 then
					-- Biased AWAY from the opening, so the mouth of the alcove stays clear and you
					-- can see into the camp before you are standing in it.
					local a = JungleLayout.OpeningAngle(camp) + math.pi
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
	return ("%s: %d camps, %d creatures (%s)%s")
		:format(zoneKey, #JungleLayout.Camps(zoneKey), #spawns, table.concat(parts, ", "),
			bad > 0 and "  <-- ROSTER DOES NOT MATCH THE TIER COUNTS" or "")
end

return JungleLayout
