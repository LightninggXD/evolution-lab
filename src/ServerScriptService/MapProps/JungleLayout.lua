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

local JungleTrails = require(script.Parent.JungleTrails)

local JungleLayout = {}

-- ===== THE FOUR KEEP-OUTS THE CAMPS ARE PLACED AGAINST =====
-- These are `CreatureService.insideKeepOut`'s own rules, restated so the placement can be checked
-- by reading rather than by running. They are NOT enforced here -- CreatureService still applies
-- them to its own scatter, and a camp that broke one would simply be wrong.
-- The camp figures below are AFTER 31.24's shrink, which is what `Camps()` returns -- see the
-- pull-in block above the table. The authored coordinates are kept per camp as `x0`/`z0`.
-- Re-measured at 32.17's 28 / 40 / 18 / 0.35; the figures 31.24 left here are in brackets.
--   * THE STREET at |x| < 62. It is the lane from the village to the exit gate and it is the main
--     path below; nothing may stand in it. Nearest camp centre: |x| = 139 (SW5), so 49 studs of
--     clear ground beyond the camp's own 28-stud floor  [was |x| 151, 105 studs, a 46-stud floor].
--   * THE ARRIVAL PLAZA, a 110-stud disc at (0, 490). Nearest camp NW1, 382 away  [386].
--   * THE BOSS, a 132-stud disc at (0, -470) -- NOT (0, -320), which is what this list said for two
--     whole phases while the boss stood elsewhere (`GameConfig.GetBossStation` is the one answer,
--     and its own comment is the record of that bug). Nearest camp is SW5, 231 studs out, which
--     clears the disc plus a camp's own floor with 71 to spare  [220 out, 42 to spare].
--   * THE PLATFORM EDGE at |x| > 575 / |z| > 500, which already leaves room for the boundary
--     rampart. Every camp centre is now inside |x| <= 380 and |z| <= 309  [400 / 343] -- the shrink
--     made this one trivially true where it used to be the binding constraint at |x| <= 530.
-- ===== THE FLOOR IS THE LEVER NOW, NOT THE DIAL (32.17) =====
-- These were 46 / 66 / 22 and they are the reason `HUNT_SHRINK` stopped working. Every camp sits on
-- `MIN_CAMP_SEPARATION` (= `CAMP_RADIUS * 2 + 20`), so turning the dial down only made `pullCamp`
-- bisect `k` straight back up: 0.50 -> 0.20 moved the furthest camp 170.4 -> 165.8 and then stopped
-- dead. The camps could not come closer together because THEIR OWN FLOORS were in the way. Measured,
-- over the real twenty, with the dial held at 0.35 and the ring scaled with the floor:
--
--     campR clear esc | furthest  max|x| | floor edge  a hill needs  vs the wall at 625
--        46    66  22 |    170.4     435 |       481           685  OVER   <- what shipped
--        32    46  22 |    122.4     392 |       424           628  OVER
--        30    43  20 |    116.1     386 |       416           620  ok
--        28    40  18 |    113.9     380 |       408           612  ok    <- this
--
-- **28 AND NOT 32, AND THE REASON IS THE MOUNTAINS.** 32.15 measured that a hill tall enough to
-- clear the boundary wall reaches 164 studs across, and 32.18 needs `camp floor edge + 164 + 40` to
-- fall INSIDE the wall at 625 or the range has nowhere to stand that is off the camps. At 32 that
-- sum is 628 -- over by three studs, which is a pass by luck in the other direction. At 28 it is
-- 612, with 13 to spare, and that is what unblocks 32.18 and then 32.19.
--
-- Below 0.35 the dial is spent again (0.20 buys four more studs), and the map cannot get smaller
-- than this by moving camps: no camp may come within 54 studs of the 270.5 x 230 VILLAGE, so the
-- mean camp radius bottoms out at 378. The next lever after this one is the player's own scale,
-- and that is an owner call.
JungleLayout.CAMP_RADIUS = 20      -- the dirt floor a camp stands on
JungleLayout.CLEARING_RADIUS = 28  -- how far back the WOOD is held: the camp's wall, since 30.23
-- Scaled WITH the floor, and it has to be: `Spawns` puts the outermost escort at
-- `ESCORT_RING + NextNumber(-5, 7)`, measured at 28.9 studs (camp NE2) while the ring was 22. On a
-- 28-stud floor that creature stands off the dirt. At 18 the same measurement is 24.9 and every one
-- of the 74 is on its own floor.
JungleLayout.ESCORT_RING = 12      -- how far an escort stands from its leader

-- ===== HOW FAR A ROAD RUNS ONTO A CAMP FLOOR, AND THAT IS 30.26 =====
-- Declared here rather than beside `SpurFor` because since 32.1 it has TWO callers: the spur
-- (which nothing triggers any more) and every trail link, both of which end at a camp's mouth.
-- It used to end at exactly `CAMP_RADIUS`, which is where the clearing's floor disc ends -- and the
-- floor's dark rim is drawn WIDER than the floor. So the road stopped, the rim carried on for five
-- more studs, and every one of the twenty camps had a dark band lying across its mouth. The owner
-- photographed it. `SPUR_OVERSHOOT` runs the road under the rim and onto the floor proper, so the
-- two dirt surfaces overlap instead of abutting -- which is the same rule `MapPaint`'s end caps
-- follow, applied at the other kind of join.
--
-- It stops short of the leader, not at it: the road ends at `CAMP_RADIUS - SPUR_OVERSHOOT`, which
-- has to stay outside the creature standing at the centre.
--
-- **14 WAS A NUMBER FOR A 46-STUD FLOOR AND 32.17 MOVED THE FLOOR.** Left at 14 the mouth would be
-- 28 - 14 = 14 studs from the centre, i.e. INSIDE `ESCORT_RING`, with road paint drawn under the
-- creatures. 8 holds the mouth at 20 -- the same fraction of the floor 14 was of 46 -- and still
-- runs 5 studs past the rim's inner edge, which is the whole of 30.26 (the rim is 3 studs on the
-- radius, `MapJungle` line 246).
JungleLayout.SPUR_OVERSHOOT = 8

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

-- ===== THE HUNTING GROUND CLOSED UP BY HALF (31.24) =====
-- Her words, 2026-08-23: *"mapa je sad prevelika u odnosu na mene mozemo je smanjiti upola"*.
--
-- ASKED BEFORE ANY CODE, BECAUSE THERE ARE TWO READINGS AND THEY NEED DIFFERENT LEVERS. "Too big
-- next to me" can mean the BUILDINGS are too tall -- which is `ForestMapService.SCALE` -- or it can
-- mean the WALK is too long, which is this. She confirmed it is the walk. The scale is deliberately
-- untouched: 31.14 already took the map 1.45 -> 1.15, and 1.45 was the value at which a doorway fit
-- the 8.4-stud body, so at 1.15 the player is already fractionally taller than a door. Halving it
-- again gives 4-stud doorways and a village she cannot walk into.
--
-- ===== WHY IT IS NOT `x * 0.5`, WHICH IS WHAT "UPOLA" LITERALLY ASKS FOR =====
-- Multiplying the coordinates pulls the inner camps INTO THE VILLAGE. SW5 is authored at
-- (-190, -390); halved it is (-95, -195), and the village floor's half-depth is 230 -- so that camp,
-- its five creatures and its 46-stud dirt floor would be standing in the square among the shops.
--
-- What halves is the distance measured OUTWARD FROM THE VILLAGE EDGE. The village keeps its
-- footprint, every camp keeps its bearing, and only the band around it closes up. Three worked by
-- hand against the whole keep-out set before this was written:
--     NW2 (-530, 300)  -> (-400, 227)
--     SW4 (-520, -455) -> (-391, -342)
--     SW5 (-190, -390) -> (-151, -310)
-- What the boot log prints is not those three but the ENVELOPE they sit in -- the furthest camp
-- from the village and the closest -- because that is the pair that can go wrong. See `Describe`.
--
-- ===== THE VILLAGE RECTANGLE IS WRITTEN HERE AND NOT READ FROM `ForestMapService` =====
-- It would be one `require` away, and taking it would be wrong. Read the file header forty lines
-- up: this table is absolute ON PURPOSE, so that a change to the map scale can never walk a camp
-- into the boss's arena. The pull-in anchor is an AUTHORING REFERENCE FRAME -- "where the village
-- edge was when these coordinates were chosen" -- not a live measurement, and if the map is ever
-- rescaled we want the camps to stay exactly where the captures showed them. Derived once, from
-- `ForestMapService`'s own published `floorHalfX = 235.2 * 1.15` and `floorHalfZ = 200 * 1.15`.
local VILLAGE_HALF_X = 270.5
local VILLAGE_HALF_Z = 230

-- The dial, and it is NOT the only number that moves any more -- see the block above `CAMP_RADIUS`.
-- It is armed again only because the floor shrank with it: at `CAMP_RADIUS` 46 the whole range
-- 0.50..0.20 was worth 4.6 studs, and at 28 the same range is worth 55 (165.2 -> 109.8). 0.35 and
-- not 0.20 because the last 0.15 of it buys four studs.
JungleLayout.HUNT_SHRINK = 0.35

-- How close a camp's FLOOR may come to the village. `CAMP_RADIUS` is the floor itself, so the
-- margin is what stops a clearing's dirt lapping over the map's own grass -- a camp is a room in
-- the forest, and a room sharing a wall with the square is not one.
--
-- 8 and not something rounder because the authored layout is already tight: NW1 and NE1 sit 63.6
-- studs off the village corner as drawn, so a margin of 24 would have re-derived camps the owner
-- has already walked and approved. This clamp exists to catch the pull-in, not to re-author 30.23.
--
-- ===== EIGHT OF THE TWENTY HIT THIS CLAMP, AND THAT IS THE RIGHT ANSWER, NOT A NEAR MISS =====
-- Measured: NW1 NW3 NW5 NE1 NE3 NE5 SW1 SE1 all stop at the 54-stud line. A safety net catching
-- 40% of its cases normally means the net is doing the design's job -- here it means the INNER RING
-- WAS NEVER FAR AWAY. Those eight are authored 54..64 studs off the village edge; there is no
-- outward distance to halve, so they move 5..20 studs and stay where she walked them.
--
-- That is the complaint being answered rather than dodged. "Too far to walk" is about the far
-- things: the outer camps close up by 130 studs each and the furthest camp in the zone goes from
-- 336 studs off the village to 165. The near ones were never the walk.
--
-- **32.17 MOVED THE LINE THIS DRAWS, BECAUSE IT IS DERIVED.** `CAMP_RADIUS` 46 -> 28 takes the
-- clamp from a 54-stud line to a 36-stud one, and the eight camps it catches are still eight:
-- NW1 NW3 NW5 NE1 NE3 NE5 SW1 SE1, now stopping at 36.0 (NW5 is the closest camp in the zone).
-- The paragraph above still holds -- the inner ring was never far away, and a smaller floor lets it
-- sit nearer the square without the dirt lapping over the grass.
local MIN_VILLAGE_CLEAR = JungleLayout.CAMP_RADIUS + 8

-- ===== 31.24's SHRINK COLLIDED THE CAMPS INTO EACH OTHER, AND NOTHING CHECKED IT (32.1a) =====
-- The pull-in was checked against the village and against the roads. It was never checked against
-- ANOTHER CAMP, and the measurement is ugly: FOUR PAIRS OF FLOORS OVERLAP. NW3/NW4 and NE3/NE4 by
-- **13.7 studs**, SW1/SE1 against SW2/SE2 by **9.5**, with NW1/NE1 and NW2/NE2 touching at +3.2.
-- The authored layout's tightest pair was +68.7, so this is entirely something the shrink did.
--
-- THE CAUSE IS THE VILLAGE CLAMP, NOT THE DIAL. The eight camps the clamp catches hold still while
-- their outer neighbours are pulled 130+ studs INTO them -- NW3 moved 5 studs and NW4 moved 137.
-- It is not only the clamp either: unclamped, NW3/NW4 still land 100.6 apart against the 92 studs
-- two floors need.
--
-- So a camp is now placed against the camps already standing as well as against the village, and
-- the clamp is bisected upward from the dial in exactly the same way -- k only ever moves toward 1,
-- which walks the camp back OUT along its own bearing until it clears. **Inner camps are placed
-- first**, so the ones the village has already pinned are the fixed points and the outer ones give
-- way, which is the only order in which this converges.
--
-- 112 AND NOT SOMETHING ROUNDER: two floors are 92 studs of dirt, and 20 studs of grass between
-- them is the least that reads as two clearings rather than one bent one. 132 was tried and
-- rejected -- it gives back a third of the shrink she approved (envelope 220 against 170).
--
-- WHAT IT COSTS, MEASURED: five studs. The furthest camp goes 165 -> 170 (it was 336 authored) and
-- the worst floor gap in the zone goes -13.7 -> +20.0. The outer column moves to |x| 436, which is
-- why the ring rows below had to go regardless -- the ring was authored at 450, INSIDE those
-- floors -- and why `MapHorizon` derives its camp edge from this table instead of holding a copy.
--
-- **AND THIS IS THE CLAMP 32.17 UNJAMMED.** It is `CAMP_RADIUS * 2 + 20`, so it shrank with the
-- floor: 112 -> **76** (56 studs of dirt, the same 20 of grass -- the 20 is the number that was
-- ever a judgement, and it does not move). That is the whole reason the dial works again: the camps
-- were all sitting ON this clamp, and the 36 studs it gave back are what the dial now has to spend.
-- Four camps need separating where eight did: NW4, NE4, SW2, SE2. Tightest floor gap NW3/NW4 at
-- +20.0, i.e. exactly the clamp, unchanged.
local MIN_CAMP_SEPARATION = JungleLayout.CAMP_RADIUS * 2 + 20

-- Distance from a point to the village rectangle. Zero inside it. NOT `max(|x|-VX, |z|-VZ)`, which
-- is the cheap version and is wrong at the corners: a point outside a rectangle is outside in
-- EITHER axis, so the diagonal case needs both terms.
local function villageGap(x, z)
	local dx = math.max(math.abs(x) - VILLAGE_HALF_X, 0)
	local dz = math.max(math.abs(z) - VILLAGE_HALF_Z, 0)
	return math.sqrt(dx * dx + dz * dz)
end

-- Where the ray from the origin through `(x, z)` crosses the village rectangle, then `k` of the way
-- from there back out to the point. Algebraically this is a radial scale about the origin, which is
-- exactly the property wanted: the BEARING is preserved to the last decimal, so the four quadrants
-- stay four quadrants and no camp changes which side of a road it is on.
function JungleLayout.PullIn(x, z, k)
	local sx = math.abs(x) > 1e-6 and VILLAGE_HALF_X / math.abs(x) or math.huge
	local sz = math.abs(z) > 1e-6 and VILLAGE_HALF_Z / math.abs(z) or math.huge
	local s = math.min(sx, sz)
	-- Already inside the village: there is no "outward distance" to halve, so leave it alone rather
	-- than inventing one. Nothing in the authored table hits this; it is here so that a camp added
	-- carelessly one day moves zero studs instead of being flung across the map.
	if s >= 1 then return x, z end
	local f = s + k * (1 - s)
	return x * f, z * f
end

-- The pull-in, clamped so no camp lands against the village. `k` only ever moves UP from the dial
-- toward 1 (= don't move), and `villageGap` rises monotonically with it, so twelve bisections is a
-- tighter answer than anything a hand-typed exception table could hold. A camp the clamp catches is
-- NAMED IN THE BOOT LOG -- a silent exception is how a layout stops being the layout that was
-- drawn.
JungleLayout.Clamped = {}
JungleLayout.Separated = {}

-- The camps already standing, in placement order. A camp is placed against these and never against
-- the ones still to come: an outer camp gives way to an inner one, which is what "inner-first"
-- buys and why this list is built as it goes rather than read off the table.
local placed = {}

local function campGap(x, z)
	local best = math.huge
	for _, p in ipairs(placed) do
		local d = math.sqrt((x - p.x) ^ 2 + (z - p.z) ^ 2)
		if d < best then best = d end
	end
	return best
end

-- Both clamps in one predicate, because they are bisected on the same dial and a camp can be
-- caught by either. The village test has an exception the separation test does not need: a camp
-- AUTHORED inside the clamp band is left where 30.23 drew it rather than shoved outward by a net
-- that exists to catch the pull-in.
local function campClear(camp, x, z)
	if campGap(x, z) < MIN_CAMP_SEPARATION then return false end
	if villageGap(camp.x, camp.z) < MIN_VILLAGE_CLEAR then return true end
	return villageGap(x, z) >= MIN_VILLAGE_CLEAR
end

-- The pull-in, clamped so no camp lands against the village OR against another camp. `k` only ever
-- moves UP from the dial toward 1 (= don't move), and both gaps rise monotonically with it, so
-- twelve bisections is a tighter answer than anything a hand-typed exception table could hold. A
-- camp either clamp catches is NAMED IN THE BOOT LOG -- a silent exception is how a layout stops
-- being the layout that was drawn.
local function pullCamp(camp, k)
	local x, z = JungleLayout.PullIn(camp.x, camp.z, k)
	if campClear(camp, x, z) then return x, z end
	-- which of the two caught it, read at the dial's own answer rather than after the bisection
	if villageGap(x, z) < MIN_VILLAGE_CLEAR and villageGap(camp.x, camp.z) >= MIN_VILLAGE_CLEAR then
		JungleLayout.Clamped[#JungleLayout.Clamped + 1] = camp.id
	end
	if campGap(x, z) < MIN_CAMP_SEPARATION then
		JungleLayout.Separated[#JungleLayout.Separated + 1] = camp.id
	end
	local lo, hi = k, 1
	for _ = 1, 12 do
		local mid = (lo + hi) / 2
		local mx, mz = JungleLayout.PullIn(camp.x, camp.z, mid)
		if campClear(camp, mx, mz) then hi = mid else lo = mid end
	end
	return JungleLayout.PullIn(camp.x, camp.z, hi)
end

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

-- The table above stays readable AS AUTHORED and the shrink is applied over it here, rather than
-- twenty coordinates being retyped. Two reasons, and the second is the one that matters: the
-- drawing 30.23 was built from is still legible in the numbers, and when she asks for another round
-- the dial moves instead of the table. `x0`/`z0` are kept so the boot log can print both.
--
-- ===== THE PLACEMENT ORDER IS INNER-FIRST, AND THE TABLE ORDER IS UNTOUCHED (32.1a) =====
-- Only the order they are POSITIONED in changes; `CAMPS_FOREST` keeps the order it is authored in,
-- because that is what the boot log, the rosters and every consumer read. Sorted on the AUTHORED
-- village gap rather than the pulled one -- the pull is radial and monotone, so the two orders
-- agree, and the authored one does not depend on the answer being computed.
--
-- The tie-break is the authored index and it is not decoration: `table.sort` is not stable, so two
-- camps at the same distance would otherwise swap between boots and the layout would stop being
-- reproducible -- which is the same reason `GetActiveEvents` carries one (12.13).
local placeOrder = {}
for i, camp in ipairs(CAMPS_FOREST) do
	camp.x0, camp.z0 = camp.x, camp.z
	placeOrder[i] = i
end
table.sort(placeOrder, function(a, b)
	local ca, cb = CAMPS_FOREST[a], CAMPS_FOREST[b]
	local ga, gb = villageGap(ca.x0, ca.z0), villageGap(cb.x0, cb.z0)
	if ga ~= gb then return ga < gb end
	return a < b
end)
for _, i in ipairs(placeOrder) do
	local camp = CAMPS_FOREST[i]
	camp.x, camp.z = pullCamp(camp, JungleLayout.HUNT_SHRINK)
	placed[#placed + 1] = { id = camp.id, x = camp.x, z = camp.z }
end

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
-- ===== THE ROADS DID NOT MOVE WITH THE CAMPS (31.24), AND IT WAS TRIED THE OTHER WAY FIRST =====
-- The obvious reading of the shrink is that the ring is part of the hunting ground and comes in on
-- the same dial. It was built that way, pushed to Studio, and the boot log killed it in two lines:
--
--     furthest camp from a road: SW4 at 42 studs
--     segments: 9 (9 trunk + 0 spurs)
--
-- **ZERO SPURS.** `SpurFor` returns nil inside `CAMP_RADIUS`, so "no spurs" means every one of the
-- twenty camps had ended up sitting ON the ring. That is the arithmetic, not bad luck: the camps
-- are authored at |x| 320..530 and the ring at 450, so pulling both toward the same village edge
-- makes them CONVERGE. Camps landed at 325 and 400 with the ring between them at 360 -- a 46-stud
-- camp floor 35 studs from a 40-wide road is a clearing with a road through the middle of it, and
-- the creatures stand in the traffic.
--
-- The relationship the ring has always had is that it threads BETWEEN the two rings of camps
-- (inner ~330, ring 450, outer ~530). After the shrink the two camp rings are 325 and 400 and
-- their 46-stud floors overlap in 354..371 -- there is no corridor left to thread. So the ring
-- stays where it was authored: every camp is now INSIDE it with 50 studs of verge, which is the
-- same "camps in a field, road round the outside" arrangement 30.23 drew, only tighter.
--
-- ===== AND 32.1 MEASURED THAT THERE IS NO RING TO PLACE AT ALL =====
-- 31.24 left this as *"`JungleRings` is the pass that owns ring geometry against the shrunken
-- positions"*. That pass took the measurement and the measurement killed the shape: after 32.1a's
-- separation clamp the inner camp column stands at |x| 313..325 and the outer at 400..436, and
-- their 46-stud floors leave **five studs of corridor**. A ring cannot be threaded between them at
-- any radius, and outside them it is the road nobody has a reason to be on that she complained
-- about in the first place -- the old |x| = 450 ring is now INSIDE the outer camps' floors.
--
-- **So the six ring rows are deleted rather than moved**, and what reaches the camps is a per-camp
-- TRAIL grown out from the cross by `MapProps/JungleTrails` -- rim to rim, so a road never has to
-- pass BETWEEN two camps. Measured over the same network: the mean walk to a camp 395 -> 215 studs,
-- the worst 795 -> 349, and 2944 studs of ring paint replaced by 1778 of trail.
--
-- The cross stays exactly as it was. It is the village's own four doors and it is not this row's
-- to move; the trails hang off it.
local PATHS_FOREST = {
	-- ---- the cross
	-- the main lane, village -> exit gate. `CreatureService.insideKeepOut` keeps |x| < 62 empty for
	-- exactly this, so the road is 56 wide and nothing has ever been allowed to stand in it.
	{ id = "S",  x1 =    0, z1 = -240, x2 =    0, z2 = -555, w = 56, tier = "trunk" },
	-- The two side gates: out of the village, into the flank. **z = -100, NOT z = 0**, and that is
	-- measured rather than chosen. At z = 0 the village half of these two roads runs straight
	-- through the PORTAL RING (zone (-201, 15), r = 45) on one side and the LEADERBOARD RING
	-- ((137, 7), r = 33.5) on the other -- both halls stand inside the village and both are 31.12 /
	-- 31.17 work. A lane search over z -200..+80 found z = -100 clear of non-foliage on BOTH flanks
	-- and z = 0 carrying 27 props on the west alone. `MapGates` cuts the village half at the same
	-- z; the two are one road and this comment is the other end of the one written there.
	{ id = "W",  x1 = -286, z1 = -100, x2 = -450, z2 = -100, w = 46, tier = "trunk" },
	{ id = "E",  x1 =  286, z1 = -100, x2 =  450, z2 = -100, w = 46, tier = "trunk" },
	-- ===== THE SIX RING ROWS STOOD HERE UNTIL 32.1 =====
	-- `RW`/`RE` at |x| 450, `RNW`/`RNE` out to the plaza corners and `RSW`/`RSE` in to the main lane.
	-- They are GONE, not moved -- see the block above the table for the measurement that killed the
	-- shape. Two things they knew are kept, because deleting a road must not delete its reasoning:
	--
	--   * THE PLAZA CORNERS ARE DOORS. `RNW`/`RNE` ended at (-/+150, 390), and that is the only exit
	--     the village's north side has. Both stand on `HubPlaza`'s deck (x -172..172, z 74..422), so
	--     a player who has just spawned can turn either way into the wood instead of walking through
	--     the village first. They are `JungleTrails.HEADS` now, and two trails start there.
	--
	--   * THE BOSS DID NOT MOVE WITH THE CAMPS, AND THAT IS DELIBERATE. `RSW`/`RSE` stopped at
	--     (+/-30, -400) and not at -470 because the arena's solid geometry is ~110 studs across and a
	--     road at -470 vanishes under it. The station is `GATE_Z + GATE_STANDOFF` -- anchored to the
	--     SOUTH GATE, a feature of the boundary wall that belongs to all twenty-one zones -- and
	--     30.27 is explicit about why: *"a boss standing AT the door is the door's guard"*. What the
	--     shrink does for the boss is give it ROOM: the camps used to crowd down to z = -455, 15
	--     studs off the arena, and they stop at -343 now, so the last 130 studs of the main lane is a
	--     clear approach to the fight instead of a corridor between two Apex camps. Nothing may be
	--     built across that approach, which is why `JungleTrails` GROWS its links out from the cross
	--     rather than being handed a fixed point down there to aim at.
}

-- ===== THE TRAILS ARE GROWN ONCE, HERE, AND THEN THEY ARE JUST MORE PATHS (32.1) =====
-- Appended to `PATHS_FOREST` rather than kept in a second list, so every consumer gets them for
-- free: `NearestPathPoint` (and through it `OpeningAngle`, which turns each clearing's mouth to
-- face the road that arrives), `RoadClearance`, `Segments`, `MapForest`'s planter and `MapJungle`'s
-- paint. A separate list would be a second definition of "where the roads are", which is the fault
-- this file's own header opens with.
--
-- `JungleTrails` is handed every constant instead of re-deriving any of them -- the camp radius,
-- the mouth overshoot, the village rectangle and the platform edge all live here.
--
-- **`SpurFor` NOW RETURNS nil FOR EVERY CAMP, AND THAT IS THE FIX RATHER THAN THE FAULT.** 31.24's
-- boot log killed a build with the line `segments: 9 (9 trunk + 0 spurs)`, because a camp sitting
-- ON the ring meant creatures standing in the traffic. Here the same zero means the opposite: every
-- camp has a trail ending 32 studs inside its own floor, so there is nothing left for a spur to
-- connect. The alarm that used to read "furthest camp from a road" is worthless now -- it would
-- read ~32 for all twenty -- so `Describe` asks the question that can still go wrong instead:
-- DOES ANY ROAD LIE ACROSS A CAMP FLOOR IT DOES NOT SERVE.
local trails = JungleTrails.Build(CAMPS_FOREST, PATHS_FOREST, {
	campRadius = JungleLayout.CAMP_RADIUS,
	mouth = JungleLayout.CAMP_RADIUS - JungleLayout.SPUR_OVERSHOOT,
	villageHalfX = VILLAGE_HALF_X,
	villageHalfZ = VILLAGE_HALF_Z,
	edgeX = 575,
	edgeZ = 500,
})
for _, t in ipairs(trails) do
	PATHS_FOREST[#PATHS_FOREST + 1] = t
end

local ZONES = {
	Forest = { camps = CAMPS_FOREST, paths = PATHS_FOREST, trails = trails },
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
-- OPENING, so the path arrives at the way in rather than at the back of the camp. Returns nil when
-- the camp is already standing on a road.
--
-- It overshoots the floor's edge by `SPUR_OVERSHOOT`; the measurement is up beside the constant.

function JungleLayout.SpurFor(zoneKey, camp)
	local px, pz, d = JungleLayout.NearestPathPoint(zoneKey, camp.x, camp.z)
	if not px or d < JungleLayout.CAMP_RADIUS then return nil end
	local a = JungleLayout.OpeningAngle(zoneKey, camp)
	local r = JungleLayout.CAMP_RADIUS - JungleLayout.SPUR_OVERSHOOT
	local mouthX = camp.x + math.cos(a) * r
	local mouthZ = camp.z + math.sin(a) * r
	return { id = camp.id .. "spur", x1 = px, z1 = pz, x2 = mouthX, z2 = mouthZ, w = 26,
		tier = "spur", serves = { [camp.id] = true } }
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
-- ===== THE ROAD ALARM CHANGED WITH THE ROADS (32.1) =====
-- It used to print THE WORST CAMP'S DISTANCE TO A ROAD, which was the right question while every
-- camp hung off a spur. Since the trails it is worthless: each one ends 32 studs inside its camp's
-- own floor, so the answer is ~32 for all twenty whatever else is wrong.
--
-- What replaces it is the question that can still go wrong, and it is the fault the deleted ring
-- actually had: DOES ANY ROAD LIE ACROSS A CAMP FLOOR IT DOES NOT SERVE. A road through a clearing
-- is creatures standing in the traffic, and `serves` is what keeps a trail's own deliberate 14-stud
-- overshoot from reporting itself as that fault.
--
-- Beside it, 32.1a's number: THE TIGHTEST GAP BETWEEN TWO CAMP FLOORS. 31.24 checked camp/village
-- and camp/road and never camp/camp, and four pairs were overlapping by up to 13.7 studs with
-- nothing in any boot log to say so.
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

	-- ROADS ACROSS A FLOOR. Measured over `Segments`, so trunks, trails and any spur are all asked
	-- the same question, and negative means paint is lying on a clearing that road does not serve.
	local segs = JungleLayout.Segments(zoneKey) or {}
	local worst, worstId = math.huge, "-"
	for _, seg in ipairs(segs) do
		for _, camp in ipairs(JungleLayout.Camps(zoneKey)) do
			if not (seg.serves and seg.serves[camp.id]) then
				local dx, dz = seg.x2 - seg.x1, seg.z2 - seg.z1
				local len2 = dx * dx + dz * dz
				local t = 0
				if len2 > 0 then
					t = math.clamp(((camp.x - seg.x1) * dx + (camp.z - seg.z1) * dz) / len2, 0, 1)
				end
				local qx, qz = seg.x1 + dx * t, seg.z1 + dz * t
				local d = math.sqrt((camp.x - qx) ^ 2 + (camp.z - qz) ^ 2)
					- seg.w / 2 - JungleLayout.CAMP_RADIUS
				if d < worst then worst, worstId = d, seg.id .. " vs " .. camp.id end
			end
		end
	end

	-- CAMP AGAINST CAMP (32.1a). The floor gap, not the centre distance, because 92 of the 112 the
	-- clamp holds is dirt and only what is left is somewhere to stand.
	local tight, tightId = math.huge, "-"
	local camps = JungleLayout.Camps(zoneKey)
	for i = 1, #camps do
		for j = i + 1, #camps do
			local a, b = camps[i], camps[j]
			local d = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2) - JungleLayout.CAMP_RADIUS * 2
			if d < tight then tight, tightId = d, a.id .. "/" .. b.id end
		end
	end

	-- ===== THE SHRINK PRINTS ITS OWN ARITHMETIC (31.24) =====
	-- The two numbers that can go wrong here are invisible from any capture. The FURTHEST camp is
	-- the walk she complained about, in one number, and it is only meaningful beside what it used to
	-- be -- so both are printed. The CLOSEST GAP is the failure the pull-in can cause and the clamp
	-- exists to prevent: a camp whose 46-stud floor laps over the village square. It must never read
	-- below 46, and the camps the clamp had to catch are named, because a silent exception is how a
	-- layout stops being the layout that was drawn.
	local far, farId, near, nearId = 0, "-", math.huge, "-"
	for _, camp in ipairs(JungleLayout.Camps(zoneKey)) do
		local d = villageGap(camp.x, camp.z)
		if d > far then far, farId = d, camp.id end
		if d < near then near, nearId = d, camp.id end
	end

	return ("%s: %d camps, %d creatures (%s), %s%s"
		.. "\n         shrink %.2f: furthest camp from the village %s at %.0f studs, "
		.. "closest %s at %.0f (floor is %d, must not go under)%s%s"
		.. "\n         tightest gap between two camp floors: %s at %+.1f studs%s"
		.. "\n         tightest road across a floor it does not serve: %s at %+.1f studs%s")
		:format(zoneKey, #camps, #spawns, table.concat(parts, ", "),
			JungleTrails.Describe(segs),
			bad > 0 and "  <-- ROSTER DOES NOT MATCH THE TIER COUNTS" or "",
			JungleLayout.HUNT_SHRINK, farId, far, nearId, near, JungleLayout.CAMP_RADIUS,
			#JungleLayout.Clamped > 0
				and ("  [village-clamped: " .. table.concat(JungleLayout.Clamped, ", ") .. "]") or "",
			#JungleLayout.Separated > 0
				and ("  [separated: " .. table.concat(JungleLayout.Separated, ", ") .. "]") or "",
			tightId, tight,
			tight < 0 and "  <-- TWO CAMP FLOORS OVERLAP" or "",
			worstId, worst,
			worst < 0 and "  <-- A ROAD IS LYING ACROSS A CLEARING" or "")
end

return JungleLayout

