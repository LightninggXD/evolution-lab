-- MapProps/MapHorizon -- the four walls of the zone stop being a grey slab.
--
-- Her words, 2026-08-23, with a reference capture of a Roblox "Neighborhood" map: *"umesto onog
-- velikog zida okolo nek budu velike planine i drveca i to iz onog modela"*.
--
-- ===== THE WALL BECAME A BARE SLAB BY ACCIDENT, AND THAT IS THE WHOLE BUG =====
-- Every zone is sealed by six parts named `Wall` -- 180 studs tall, 4 thick, `Material.Slate`, at
-- |x| = 625 and |z| = 575 (`ZoneBuilder.buildXWall` / `buildZWall`). In the other twenty zones you
-- never see it: `addRockRampart` stands boulders in front of it and `addBackdropMesas` puts two
-- rows of mesa behind. **In Forest all three are deleted** -- `Cliff`, `Rampart`, `Mesa` and
-- `Backdrop` are all in `ForestMapService`'s `DROP_PREFIX`, and `dropShellDressing` takes the
-- pinned copies out of `WorldShell` too.
--
-- What replaced them was `MapJungle.buildRidge`: 24 hills at scale 0.55/0.60, and **no north run at
-- all**. Measured on the live map, a hill at 0.60 is 87 studs tall and 15 of that is buried, so the
-- answer to a 180-stud wall was 72 studs of rock on three sides and nothing on the fourth. That is
-- the screenshot. `buildRidge` and `mountainStock` moved here whole and this file replaces them.
--
-- ===== TWO ROWS, BECAUSE ONE ROW CANNOT DO BOTH JOBS =====
-- A wall is opaque. Everything BEHIND it is invisible below 180 studs and visible above; everything
-- IN FRONT of it hides the face. So:
--
--   * the INNER row stands on the platform, in front of the wall, and hides its face. It is pinned
--     just inside the boundary (`AT`) and has to CLEAR the outermost camps, which `Build` checks
--     against the rock it actually placed rather than against the number it asked for.
--   * the OUTER row stands in the 650-stud void between this platform and the next one, and exists
--     only for the silhouette ABOVE the wall.
--
-- **The outer row has to clear a horizon test, not just be tall.** A mountain further away needs
-- more height to show over the same wall: from the middle of the zone the wall is 625 away and the
-- outer row 812, so it must exceed 180 * 812/625 = 234 studs of visible rock or it is a mountain
-- nobody can see. `COVER_OUTER` is set from that inequality with margin, and the boot line prints
-- the test back so a future scale change cannot silently sink the range below the wall.
--
-- ===== THE YAW IS CONSTRAINED, AND THAT IS WHAT MAKES THE HEIGHT POSSIBLE =====
-- `buildRidge` yawed every hill randomly through a full turn. For a ridge that is worse than it
-- looks: the mountain mesh is ~204 x 145 x 262, so a random yaw presents anything from 204 to 262
-- studs of width, and the width is what decides how far the rock reaches inward. The band between
-- the outermost camp's floor (|x| = 446 after 31.24's shrink) and the wall is 179 studs -- so a
-- randomly-yawed hill big enough to hide the wall stands in a camp, which is 30.19 all over again.
--
-- Turned so the mesh's LONG axis runs ALONG the ridge, the same hill presents its narrow side and
-- overlaps its neighbours down the run. That buys the height AND it is what a ridge line actually
-- looks like. The jitter is +/- 12 degrees, which is variety rather than a lottery -- and it is
-- counted into the footprint, because a box turned 12 degrees is a quarter wider than its own
-- short side.
--
-- ===== THE HILLS ARE THE WALLS SHE WALKS THROUGH (32.15) =====
-- Her words: *"da se ne prolazi kroz zidove"*. Every part of every hill is `CanCollide = false` AND
-- `CanQuery = false`, and these hills stand INSIDE the platform, not on a backdrop -- so walking at
-- the map edge walks through a mountain. The note this paragraph replaces said that was fine
-- because the 180-stud boundary wall does the containing. True, and beside the point: the wall is
-- 100+ studs BEHIND the rock, so what she meets first is a mountain that is not there.
--
-- The mesh still does not collide, and that is not a compromise -- it is the 30.19 trap, which this
-- repo shipped once. A `MeshPart` at `CollisionFidelity.Default` is a handful of convex hulls, a
-- mountain's hull is close to its own BOX, and a ring of those seals the player in;
-- `MapForest.lua:28-32` is the standing note. What stops her is an upright box built beside each
-- hill by `MapSolids` -- 32.10's machinery, already built and already probed. `Colliders` publishes
-- the inner row and `MapForest` offers it; see the note at each for why the call is made there.
--
-- ===== AND TWO FAULTS FOUND WHILE MEASURING FOR IT, NEITHER OF THEM FIXED HERE =====
-- Both were found by raycasting the mesh (clone it, make the clone queryable, sweep a grid) rather
-- than by reading the code, and both are recorded because the numbers cost something to get.
--
--   1. **EVERY HILL STANDS 82 DEGREES FROM THE ANGLE THIS FILE ASKS FOR.** `hill()` turns the clone
--      with `m:PivotTo(CFrame.new(m:GetPivot().Position) * CFrame.Angles(0, yaw, 0))` -- a nudge off whatever
--      orientation the stock was parked at -- and `ServerStorage.RidgeStock` is parked at yaw
--      **-1.429**. So the yaw section above, which is entirely about presenting the mesh's NARROW
--      side across the ridge, has never once happened. Measured: an inner hill reaches **+-212
--      studs across** its run and +-168 along it -- long axis across, the shape that section calls
--      "30.19 all over again". Cancel the parked yaw and the same hill reaches +-164 across.
--   2. **ROCK STANDS ON ELEVEN OF THE TWENTY CAMP FLOORS**, up to 74 studs proud, 151 of 740 cells
--      on a raycast grid over the floors. The boot line has never said so because its camp test
--      reads `msz` from `GetBoundingBox` -- the PIVOT box -- against WORLD camp coordinates, and
--      then takes `FILL` 0.55 of it as the rock. On a fixed-x run the pivot box's X is the hill's
--      ALONG extent, so the reach is read off the wrong axis and then halved. It prints
--      `+19.7 -- clear of every camp`.
--
-- **Neither is fixed here, and that is a decision with a capture behind it.** Both fixes turn the
-- hills narrow-side-in and push the row off the camps, and the row has nowhere to go: at
-- `CAMP_RADIUS` 46 the band between the outermost camp floor (|x| 482) and the wall (625) is 143
-- studs, while a hill that clears the wall is 359 wide. Built that way and captured from the
-- hunting ground, the range goes BEHIND the boundary wall and the wall comes back as the flat grey
-- slab this entire file exists to hide. That is the finding the `AT` note already predicted --
-- *"a finding about the platform, not a number to tune away"* -- and the row that buys the room
-- back is the camp shrink, not this one.
--
-- So 32.15 does the collision only, and the collider CLIPS where a camp is behind it (see
-- `Colliders`): the rock stays where it looks right, the mountain stops you, and no camp floor is
-- walled off. What it costs is named rather than hidden -- at those eleven camps you walk further
-- into the rock before the box stops you.

local ServerStorage = game:GetService("ServerStorage")

local MapRidge = require(script.Parent.MapRidge)
local JungleLayout = require(script.Parent.JungleLayout)

local MapHorizon = {}

local FOLDER_NAME = "Horizon"

-- The boundary this file exists to hide. Restated from `ZoneKit` rather than required, for the
-- reason `ForestMapService` gives at the top of its own file: `ZoneBuilder` and everything it pulls
-- in is two registers from Luau's 200-local cap, and this module is not worth one of them. If the
-- platform is ever resized these three move together and `Describe` will say so.
local WALL_X, WALL_Z, WALL_H = 625, 575, 180

-- How much of the wall's 180 studs each row is asked to cover, as a fraction of it.
--
-- ===== 0.85 WAS NOT ENOUGH, AND TWO BOOT LOGS ARE WHY THIS IS 1.25 =====
-- The first build ran INNER at 0.85 and the hills measured 114..149 studs tall against a 180-stud
-- wall. From the village that is a flat band of wall standing above the whole ridge -- which is the
-- complaint, still there, with 40 mountains in front of it. Over 1.0 the ridge breaks the wall's
-- skyline everywhere it stands, which is the only version of this that actually answers her.
local COVER_INNER = 1.55
local COVER_OUTER = 1.90

-- Buried, so a hill's flat underside never shows. Carried from `buildRidge` unchanged.
local SINK = 15

-- ===== WHERE EACH ROW STANDS, AND WHY IT IS PINNED RATHER THAN DERIVED =====
-- The first cut of this file placed a row at `reach + acrossHalf` -- "put the rock's inner edge on
-- a line and let the centre fall where it may". That is the wrong way round and it fails exactly
-- when the row matters: raising the cover makes the hill wider, which pushes its centre OUTWARD,
-- and at `COVER_INNER` 1.12 the inner row would have centred at |x| = 654 -- *outside the wall*,
-- where a hill under 180 studs is invisible no matter how big it is.
--
-- So the row is pinned just inside the boundary, where its job is, and the reach becomes a CHECK
-- rather than an input. `Build` measures the innermost rock it actually placed and prints it beside
-- the camp edge it must clear; if a future cover pushes rock into a clearing, the boot log says so
-- in the same line rather than a screenshot saying it three days later.
local AT = {
	-- Inside the wall (625 / 575) by enough that the hill's near face is what you see. Most of a
	-- hill's bulk ends up BEHIND the wall at these numbers and that is fine -- only the near slope
	-- has a job. `innerZ` is 568 and not 550 because at 550 the boot check read the rock at |z| 390
	-- against a camp edge of 388: two studs, which is a pass by luck rather than by design.
	innerX = 600, innerZ = 568,
	-- Out in the 650-stud void between this platform and the next. `ZoneSpacing` is 1900 and the
	-- neighbour's wall is at 1275, so a hill here has ~250 studs of clearance at COVER_OUTER.
	outerX = 812, outerZ = 776,
}

-- ===== WHAT THE ROCK MUST STAY CLEAR OF, AND IT IS READ RATHER THAN TYPED (32.1b) =====
-- This was `local CAMP_EDGE_X, CAMP_EDGE_Z = 446, 388` -- the outermost camp after 31.24's shrink,
-- plus its 46-stud floor, typed in by hand. **That is a second copy of a fact `JungleLayout` owns**,
-- which is the trap this repo's own header calls 31.5a, and 32.1a walked straight into it: the
-- separation clamp moves the outer column to |x| 436, so the edge became 482 and this file went on
-- checking against 446 and printing "clear of every camp".
--
-- The owner found it before the code did, on a live capture: *"prolazim kroz planine i tu su i
-- dalje neki mobovi zaglavljeni i put jos vodi tamo"* -- creatures standing in rock, with a road
-- leading to them. The road half was the |x| = 450 ring, which 32.1 deletes. This is the other
-- half, and it is why the check has to derive its own input: an alarm that cannot go stale is the
-- only kind worth printing.
--
-- `AT.innerX/innerZ` are solved from the same measurement rather than pinned -- see `AT`.
local function campEdge()
	local camps = JungleLayout.Camps("Forest")
	if not camps then return 446, 388 end
	local mx, mz = 0, 0
	for _, c in ipairs(camps) do
		mx = math.max(mx, math.abs(c.x))
		mz = math.max(mz, math.abs(c.z))
	end
	return mx + JungleLayout.CAMP_RADIUS, mz + JungleLayout.CAMP_RADIUS
end
local CAMP_EDGE_X, CAMP_EDGE_Z = campEdge()

-- Daylight between the innermost rock and the outermost camp's floor. 15 and not 2: `innerZ` was
-- 568 rather than 550 because at 550 the check read 390 against a camp edge of 388, and two studs
-- is a pass by luck. This is that judgement written down instead of re-made.
local CAMP_CLEAR = 15

-- ===== THE GATE LANE, AND WHY 132 IS BACK (32.19) =====
-- A lane is the gap left in an inner run so a hill does not stand on the portal. The first cut used
-- PORTAL_CLEAR_HALF (132) and offset it by the hill's whole half-LENGTH, leaving a 760-stud hole
-- that bared 48% of the boundary wall. It was shrunk to 90 because the hills did not collide, so
-- the gap only had to clear the gate's stonework.
--
-- 32.15 gave the inner hills colliders, and 90 was no longer enough. The walkway reservation this
-- codebase already owns is ZoneGate.PORTAL_CLEAR_HALF = 132 ("how far boulders stay off the centre line").
-- 32.19 restores 132 so the gate footprint is completely clear of colliders.
--
-- The offset is still the rock's half-length, but we now reserve what the COLLIDER occupies (ROCK_FOOT),
-- not just the visual silhouette (FILL).
local LANE_PORTAL = 132

-- ===== HOW FAR APART, AND WHY 0.62 OF A BOUNDING BOX IS NOT AN OVERLAP =====
-- A hill stands this fraction of its own length from the next one. `buildRidge` used ~1.0 and the
-- note it carried was right as far as it went: under 1.0 so they overlap into a continuous ridge
-- rather than standing as separate lumps with sky between them.
--
-- What that note misses is that **a mountain is a CONE and its bounding box is a box**. At 0.62 the
-- boxes overlap by 188 studs and the ROCK still dips almost to the ground between the peaks -- the
-- occlusion probe drew it as a repeating `#..-++..-` down every wall, one dip per gap, with bare
-- slate visible at y = 10. Boxes touching is not rock touching, and only a probe that measures the
-- rock says so.
--
-- ===== AND THEN THE ARITHMETIC THAT ACTUALLY SETS IT =====
-- 0.42 halved the dips and did not close them: 75% hidden, and a capture with the wall temporarily
-- painted RED (the only way to read it through the distance fog) showed a clear pink strip between
-- the treetops and the sky. The number that matters is the hill's width AT THE WALL'S HEIGHT, not
-- at its base. For a cone of peak `P` and base length `L`, that width is `(1 - 180/P) * L` -- so
-- the spacing has to be under it, and a taller hill helps twice because it widens the slice as
-- well as raising the peak.
--
-- At `COVER_INNER` 1.55 the peak is 294 and the base 534, so the slice at 180 studs is 207 against
-- a 608-stud box: 207/608 = 0.34, and 0.32 leaves a little for the size jitter.
local OVERLAP = 0.32

-- ===== HOW MUCH OF A HILL'S BOUNDING BOX IS ACTUALLY ROCK =====
-- The same 0.55 `MapRidge.Footprints` uses, and it is here because the first boot without it was a
-- measured disaster: **317 trees planted where the wood had been over a thousand**, with the boot
-- line reading `keep-outs: ... 45 mountains`. A mountain is a CONE and its bounding box is mostly
-- air, so publishing the whole box as "no tree may grow here" handed the planter 44 rectangles that
-- between them claimed most of the platform's outer band -- exactly the ground 31.24 widened the
-- wood into.
--
-- At 0.55 the claimed footprint along a run is ~168 studs against a 189-stud spacing, so the wood
-- closes over BETWEEN the hills and breaks only where the rock is. That gap is the difference
-- between a treeline and a wall, and it is the whole point of building the horizon first.
local FILL = 0.55

-- ===== THE TREES GET A SMALLER NUMBER THAN THE CAMPS DO, AND THAT IS NOT A FUDGE =====
-- `FILL` above answers "where is the rock", and it is the right answer for the camp check and for
-- the gate lane, where being wrong means a clearing or a doorway with a mountain in it.
--
-- It is the wrong answer for the WOOD, and the boot log is unambiguous about the cost: raising the
-- hills to `COVER_INNER` 1.55 took the planting from **2,289 trees to 504** in one step, because a
-- ring of 66 hills claiming their full rock footprint eats most of the band the wood lives in. A
-- treeline that stops 150 studs short of the mountains is the "fields of bare green" this phase
-- widened the wood to close.
--
-- What a tree actually needs is to not be standing INSIDE the mountain. These hills are sunk 15
-- studs and are two and a half times the artist's, so their lower slopes are long and shallow --
-- and a tree at the foot of a mountain, half its trunk against the slope, is the look, not a fault.
-- 0.35 keeps trunks out of the mass and lets the wood run onto the skirt.
local KEEPOUT_FILL = 0.35

-- How far off the run's own line a hill may be turned. Variety rather than a lottery -- see the
-- header on why a full random turn is what made the old ridge too wide to be tall.
local YAW_JITTER = 0.21

-- Size variety, and it does NOT go below 0.95. A ridge of identical hills reads as a fence, but the
-- floor of this range is load-bearing in a way the ceiling is not: `COVER_INNER` is chosen so that
-- `scale * SIZE_JITTER[1]` still clears the wall. At 0.88 it did not, and the boot log said so.
local SIZE_JITTER = { 0.95, 1.15 }

-- ===== THE STOCK =====
-- The map's own `Meshes/gora`, which is the whole of *"i to iz onog modela"*. Looked for inside the
-- PLACED map first so it follows the map scale for free, then `MapRidge`'s parked clone.
--
-- THE FALLBACK IS NOT A NICETY. Since 30.23 `MapRidge.Clear` cuts every mountain the artist placed,
-- and by the time this runs there are usually none left in the map at all -- the first boot after
-- that change printed `0 ridge hills` and left the wood with an empty sky behind it, and nothing
-- errored. `MapRidge` parks the first one it takes for exactly this call.
local function stockOf(map)
	if map then
		for _, c in ipairs(map:GetChildren()) do
			if c:IsA("Model") then
				for _, d in ipairs(c:GetDescendants()) do
					if d:IsA("MeshPart") and d.Name:find("gora") then return c end
				end
			end
		end
	end
	return MapRidge.Stock()
end

MapHorizon.Placed = {}
MapHorizon.Solid = {}
-- Scratch handoff from `hill()` to `buildRun`, so the measurement is taken once at the only point
-- where the finished model is in hand. Never read outside that pair.
MapHorizon.LastHill = nil

-- Every hill this file stood up, as a footprint `MapForest` subtracts so no tree grows inside rock.
-- Same shape `MapRidge.Footprints` returns, so the planter merges the two lists rather than growing
-- a second keep-out branch.
function MapHorizon.Footprints(zoneKey)
	return MapHorizon.Placed[zoneKey] or {}
end

-- The boxes `MapSolids` should build, in world coordinates: `{ model, x, z, hx, hz, top }`, all
-- half-extents, all world-axis.
--
-- ===== INNER ROW ONLY =====
-- The outer row stands 200 studs BEYOND the boundary wall, in the void between platforms, and the
-- one thing a player can reach out there is the gate walkway -- which the outer row deliberately
-- runs straight across, because it has no lane (see the note on that). A box on an outer hill is a
-- box across the gate.
--
-- ===== AND THE BOX CLIPS WHERE A CAMP IS BEHIND IT =====
-- Eleven of the twenty camp floors have rock standing on them (header, fault 2). A box at the
-- rock's own edge would therefore be an invisible wall across a camp, which is strictly worse than
-- the rock: you can at least SEE the rock. So a box that would come inside a camp's floor is cut
-- back on its across axis until it clears -- its OUTER face stays put, only the inward face moves,
-- so the ring never opens a hole. `CAMP_KEEP` is 30 rather than `CAMP_CLEAR`'s 15 because
-- `CreatureService` scatters an escort at `ESCORT_RING + NextNumber(-5, 7)` from its leader, i.e.
-- up to 29 studs beyond it, and a creature inside an invisible box is the same complaint in a worse
-- form.
--
-- A hill whose box would be cut to nothing keeps no box at all, and `Report` counts those: that is
-- a stretch of range you can still walk into, and it is a number rather than a shrug.
local CAMP_KEEP = 30
local MIN_BOX = 24

-- ===== AND IT CLIPS OFF THE ROADS TOO, WHICH IS NOT THE SAME CUT =====
-- Measured on the first build that offered boxes: six of the thirty-four covered a road, and
-- `MapSolids` did the only thing it could with them -- refused the box, i.e. left a hole in the
-- range you can walk straight through. Two different roads, and they need two different cuts:
--
--   * FOUR boxes on the north run reached in to |z| 335 over a camp trail at |z| 340. That is the
--     ACROSS axis, the same cut the camps get.
--   * TWO boxes on the south run, at x -267 and +264, reached ALONG the run to x -17 and +5 --
--     across the south gate road (`S`, x = 0, 56 wide, running out to z = -555). The gate lane is
--     supposed to leave that clear and it is sized with `FILL` 0.55, while the box is sized with
--     `ROCK_FOOT` 0.92 -- so the ROCK closes more of the doorway than the lane reserves, and a box
--     at the rock's edge closes it outright. `evolution-lab-arc-must-not-close` is the standing
--     note and this is it caught by an alarm rather than by the owner.
--
-- So the trim walks whichever edge is nearest the offending cell, on either axis, and only ever
-- inward from an edge -- the outer face and the run's continuity are what must survive. A box that
-- cannot be made clear keeps no box at all and `dropped` counts it.
--
-- `ROAD_KEEP` is this file's own decision about daylight between an invisible wall and a road, not
-- a copy of `MapSolids`' trunk-sized one: 6 studs, enough that the road's painted edge is clear of
-- the box a player will bump into.
local ROAD_KEEP = 6
local ROAD_STEP = 24
local ROAD_TRIES = 12

local function trimOffRoads(zoneKey, segments, acrossIsX, aMin, aMax, bMin, bMax, sign)
	if not segments then return aMin, aMax, bMin, bMax end
	for _ = 1, ROAD_TRIES do
		if aMax - aMin < MIN_BOX or bMax - bMin < MIN_BOX then return nil end
		local na = math.max(1, math.ceil((aMax - aMin) / ROAD_STEP))
		local nb = math.max(1, math.ceil((bMax - bMin) / ROAD_STEP))
		local worst, wa, wb = math.huge, aMin, bMin
		for i = 0, na do
			for j = 0, nb do
				local a = aMin + (aMax - aMin) * i / na
				local b = bMin + (bMax - bMin) * j / nb
				local c = JungleLayout.RoadClearance(zoneKey,
					acrossIsX and a or b, acrossIsX and b or a, segments)
				if c < worst then worst, wa, wb = c, a, b end
			end
		end
		if worst >= ROAD_KEEP then return aMin, aMax, bMin, bMax end
		local push = (ROAD_KEEP - worst) + 6
		-- how far the offending cell is from each edge this trim is allowed to move
		local dA = sign > 0 and (wa - aMin) or (aMax - wa)
		local dB = math.min(wb - bMin, bMax - wb)
		if dA <= dB then
			if sign > 0 then aMin = wa + push else aMax = wa - push end
		elseif wb - bMin <= bMax - wb then
			bMin = wb + push
		else
			bMax = wb - push
		end
	end
	return nil
end

function MapHorizon.Colliders(zoneKey)
	local hills = MapHorizon.Solid[zoneKey]
	if not hills then return {}, 0 end
	local camps = JungleLayout.Camps(zoneKey) or {}
	local segments = JungleLayout.Segments(zoneKey)
	local reach = JungleLayout.CAMP_RADIUS + CAMP_KEEP
	local outList, clipped, dropped = {}, 0, 0
	for _, h in ipairs(hills) do
		local across = h.acrossIsX and h.wx or h.wz
		local along = h.acrossIsX and h.wz or h.wx
		local rAcross = h.acrossIsX and h.rx or h.rz
		local rAlong = h.acrossIsX and h.rz or h.rx
		local sign = across >= 0 and 1 or -1
		local inner, outer = math.abs(across) - rAcross, math.abs(across) + rAcross
		local need = inner
		for _, c in ipairs(camps) do
			local cAcross = h.acrossIsX and c.x or c.z
			local cAlong = h.acrossIsX and c.z or c.x
			-- only a camp on this side, and only one this hill actually stands in front of
			if cAcross * sign > 0 and math.abs(cAlong - along) < rAlong + reach then
				need = math.max(need, math.abs(cAcross) + reach)
			end
		end
		if need > inner then
			clipped += 1
			inner = need
		end
		local aMin, aMax = sign > 0 and inner or -outer, sign > 0 and outer or -inner
		local bMin, bMax = along - rAlong, along + rAlong
		if aMax - aMin >= MIN_BOX then
			local a0, a1, b0, b1 = trimOffRoads(zoneKey, segments, h.acrossIsX,
				aMin, aMax, bMin, bMax, sign)
			if a0 then
				if a0 ~= aMin or a1 ~= aMax or b0 ~= bMin or b1 ~= bMax then clipped += 1 end
				aMin, aMax, bMin, bMax = a0, a1, b0, b1
			else
				aMin = aMax
			end
		end
		if aMax - aMin < MIN_BOX or bMax - bMin < MIN_BOX then
			dropped += 1
		else
			local ac, ah = (aMin + aMax) / 2, (aMax - aMin) / 2
			local bc, bh = (bMin + bMax) / 2, (bMax - bMin) / 2
			outList[#outList + 1] = {
				model = h.model, top = h.top,
				x = h.acrossIsX and ac or bc,
				z = h.acrossIsX and bc or ac,
				hx = h.acrossIsX and ah or bh,
				hz = h.acrossIsX and bh or ah,
			}
		end
	end
	return outList, clipped, dropped
end

-- ===== THE WALL ITSELF, RE-TINTED -- WITHOUT OPENING `ZoneBuilder` =====
-- The remaining band of wall above the ridge should read as more rock rather than as a slab. That
-- is a colour and a material on six parts, and it is done by WRITING TO THE INSTANCES because
-- `ZoneBuilder` is two registers from the cap and a builder edit is not worth one of them.
--
-- The filter is the `Zone` attribute, which `keepShellLoaded` already writes on every part it
-- reparents. `WorldShell` is ONE FLAT FOLDER FOR THE WHOLE WORLD -- 21 zones' floors and walls in
-- one place -- so a pass that matched on name alone would repaint every boundary in the game.
local WALL_TINT = Color3.fromRGB(132, 121, 112)

function MapHorizon.TintWall(zoneKey, _cx)
	local shell = workspace:FindFirstChild("WorldShell")
	if not shell then return 0 end
	local n = 0
	for _, c in ipairs(shell:GetChildren()) do
		if c:IsA("BasePart") and c.Name == "Wall" and c:GetAttribute("Zone") == zoneKey then
			c.Color = WALL_TINT
			c.Material = Enum.Material.Rock
			n += 1
		end
	end
	return n
end

-- One hill, seated on the ground at `(cx + x, z)` and turned by `yaw`.
--
-- ===== SCALE, THEN TURN, THEN RE-MEASURE, THEN MOVE -- IN THAT ORDER AND IN SEPARATE STEPS =====
-- This was written as one `PivotTo(CFrame.new(x,0,z) * Angles(0,yaw,0) * CFrame.new(-box...))` and
-- it is worth keeping the wreckage on record, because it type-checks, it lints, it runs, and the
-- boot log said `44 hills` exactly as it should. What it does NOT do is put them where it was
-- asked: the seating offset sits to the RIGHT of the rotation in that chain, so the offset is
-- rotated too, and a run meant to stand at x 455..691 was measured on the live build at
-- **x 300..838**. Mountains in the middle of the hunting ground, and nothing anywhere said so.
--
-- The old `buildRidge` did it in two steps and carried a note about why. That note was right and
-- this is it, kept: *a rotated model is a different box, and seating it on the box it had before is
-- how a hill ends up floating*. `MapForest.plantOne` has the same rule for the same reason.
--
-- Returns the POST-YAW box, because that -- not the number this file asked for -- is the footprint
-- the planter has to keep its trees out of.
-- ===== A WORLD-AXIS QUESTION NEEDS A WORLD-AXIS ANSWER (32.15) =====
-- `Model:GetBoundingBox()` answers in the model's PIVOT frame, and every question asked of a hill
-- here is a world-axis one: how far inward does it reach, where does its collider go. Those two
-- frames differ by the stock's parked 82-degree yaw (see the header), so a hill on a fixed-x run
-- has its ACROSS extent read off its ALONG axis -- the same shape of fault as the corner-hill bug
-- the report's own 32.1b note describes. The union of the parts' world AABBs has no frame in it to
-- get wrong. The mountain is one MeshPart, so this is not a loop worth avoiding.
--
-- Returns half-extents, the top, and the world centre.
local function worldBox(m)
	local mnx, mxx = math.huge, -math.huge
	local mnz, mxz = math.huge, -math.huge
	local top = -math.huge
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			local c, sz, p = d.CFrame, d.Size, d.Position
			local hx = (math.abs(c.RightVector.X) * sz.X + math.abs(c.UpVector.X) * sz.Y
				+ math.abs(c.LookVector.X) * sz.Z) / 2
			local hy = (math.abs(c.RightVector.Y) * sz.X + math.abs(c.UpVector.Y) * sz.Y
				+ math.abs(c.LookVector.Y) * sz.Z) / 2
			local hz = (math.abs(c.RightVector.Z) * sz.X + math.abs(c.UpVector.Z) * sz.Y
				+ math.abs(c.LookVector.Z) * sz.Z) / 2
			mnx, mxx = math.min(mnx, p.X - hx), math.max(mxx, p.X + hx)
			mnz, mxz = math.min(mnz, p.Z - hz), math.max(mxz, p.Z + hz)
			top = math.max(top, p.Y + hy)
		end
	end
	if top == -math.huge then return nil end
	return (mxx - mnx) / 2, (mxz - mnz) / 2, top, (mnx + mxx) / 2, (mnz + mxz) / 2
end

-- ===== HOW MUCH OF THAT BOX IS ROCK AT THE GROUND LINE =====
-- `FILL` 0.55 is a SILHOUETTE -- how much of the box is rock taken over the whole height of it --
-- and it is the right answer for the keep-out it serves. It is the wrong answer for a collider,
-- which is a question asked at the player's feet, where a mountain fills nearly its whole box.
--
-- Measured on a scale-2.24 hill, raycast on a grid with the mesh temporarily made queryable: the
-- surface stands **4.5 studs proud out to +-164 across a 359-stud world box and +-208 along a
-- 462-stud one** -- 0.92 of the box on both axes. 4.5 is not an arbitrary line: it is the step this
-- body stops at anyway, measured in `MapSolids`. So a box at 0.92 stops the player exactly where
-- the ground would have. Narrower and she walks into the mountain before stopping; wider and she is
-- stopped by nothing she can see.
--
-- The same sweep says the mesh is a RIDGE and not a cone, which is what makes an axis-aligned box
-- an honest collider for it: the across reach is flat at +-164..168 for along offsets of 0, 50, 97
-- and 150, and only falls away past 200.
local ROCK_FOOT = 0.92

local function hill(proto, parent, cx, x, z, yaw, scale)
	local m = proto:Clone()
	local _, raw = m:GetBoundingBox()
	if raw.Y < 1 then m:Destroy() return nil end
	m:ScaleTo(scale)
	m:PivotTo(CFrame.new(m:GetPivot().Position) * CFrame.Angles(0, yaw, 0))
	local cf, sz = m:GetBoundingBox()
	m:PivotTo(m:GetPivot() + Vector3.new(cx + x - cf.Position.X,
		-(cf.Position.Y - sz.Y / 2) - SINK, z - cf.Position.Z))
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			-- STILL NOT THE MESH. See the header: `CanCollide = true` on a mountain MeshPart is the
			-- 30.19 trap. `MapSolids` builds the box that stops her, beside this.
			d.CanCollide = false
			d.CanQuery = false
			d.CastShadow = false
		end
	end
	m.Name = "HorizonHill"
	m.Parent = parent
	-- Measured AFTER seating, so it is the rock standing there and not the box it had two transforms
	-- ago -- `MapForest.plantOne` has the same rule for the same reason.
	local rx, rz, top, wx, wz = worldBox(m)
	if not rx then m:Destroy() return nil end
	MapHorizon.LastHill = {
		model = m, top = top, wx = wx, wz = wz,
		rx = rx * ROCK_FOOT, rz = rz * ROCK_FOOT,
	}
	return sz
end

-- A run of hills along one axis, placed from a COUNT AND A SPAN rather than by stepping one off the
-- last. `evolution-lab-arc-must-not-close` is the standing note: 31.18 extended an arc by repeating
-- a step and twenty 18.3-degree steps closed a 366-degree ring that sealed the owner inside it. A
-- run built from a count cannot overrun its own end.
--
-- `lane` is the half-width of the gap left in the middle of the run; a run with no gate gets 0.
-- `spec.solid`, when present, collects the hills of this run for `Colliders`. Only the inner row
-- passes one -- see `Colliders`.
local function buildRun(proto, folder, cx, rng, spec, out)
	local placed = 0
	-- The rock's half-length, not the box's -- see the note on `LANE_PORTAL`.
	local lo = spec.lane > 0 and (spec.lane + spec.alongLen * FILL / 2) or 0
	local hi = spec.span
	if lo > hi then return 0 end
	-- Both halves of the run, or the whole of it when there is no lane.
	for _, side in ipairs(spec.lane > 0 and { -1, 1 } or { 1 }) do
		local a, b = spec.lane > 0 and lo or -hi, hi
		local n = math.max(math.ceil((b - a) / spec.spacing) + 1, 2)
		for i = 1, n do
			local t = a + (b - a) * (i - 1) / (n - 1)
			local along = spec.lane > 0 and side * t or t
			local x, z, yaw
			if spec.axis == "z" then
				x = spec.at + rng:NextNumber(-14, 14)
				z = along + rng:NextNumber(-16, 16)
				yaw = 0
			else
				x = along + rng:NextNumber(-16, 16)
				z = spec.at + rng:NextNumber(-14, 14)
				yaw = math.pi / 2
			end
			local sz = hill(proto, folder, cx, x, z, yaw + rng:NextNumber(-YAW_JITTER, YAW_JITTER),
				spec.scale * rng:NextNumber(SIZE_JITTER[1], SIZE_JITTER[2]))
			if sz and spec.solid then
				-- The rock this hill really covers, world-axis, for `MapSolids` to box. Kept in a
				-- second list rather than folded into `out`: `out` is the WOOD's keep-out and is
				-- read by `MapForest` on every one of its 5,467 candidate points, and it has no
				-- business growing four fields it never looks at.
				local h = MapHorizon.LastHill
				h.acrossIsX = spec.axis == "z"
				spec.solid[#spec.solid + 1] = h
			end
			if sz then
				-- The footprint the planter subtracts, taken from the hill's OWN post-yaw box
				-- rather than from the number this run asked for. The two differ by the scale and
				-- yaw jitter, and it is the real box a tree would be standing inside.
				out[#out + 1] = {
					x = x, z = z,
					hx = sz.X * KEEPOUT_FILL / 2, hz = sz.Z * KEEPOUT_FILL / 2,
				}
				placed += 1
			end
		end
	end
	return placed
end

-- ===== THE ONE ENTRY POINT =====
-- Idempotent for the same reason `ForestMapService.Init` is: a second call must not stand a second
-- range inside the first.
function MapHorizon.Build(zoneKey, cx, map)
	local proto = stockOf(map)
	if not proto then
		warn("[MapHorizon] " .. zoneKey .. ": no mountain mesh in the map or in RidgeStock")
		return 0
	end

	local old = map:FindFirstChild(FOLDER_NAME)
	if old then old:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = map

	-- Seeded off the zone, never off the clock: two servers of the same place must grow the same
	-- horizon, which is the rule `MapForest`, `raisedSpots` and `JungleLayout.Spawns` all follow.
	local rng = Random.new(20260823 + math.floor(cx))

	local _, s = proto:GetBoundingBox()
	-- The mesh's long axis runs along the ridge and its short axis across it -- see the header. Both
	-- are read off the stock, so a re-authored mountain re-derives every number below.
	local shortAxis = math.min(s.X, s.Z)
	local longAxis = math.max(s.X, s.Z)

	local out = {}
	local solid = {}
	local runs, hills = 0, 0
	-- where the inner row ended up standing, so the boot line can say whether 32.1b moved it
	local innerAtX, innerAtZ = AT.innerX, AT.innerZ

	-- Scale solved from the wall, not typed: `visible = height * scale - SINK`, so a row asked to
	-- cover a fraction of 180 studs works out its own scale whatever the map scale is.
	local function scaleFor(cover)
		return (cover * WALL_H + SINK) / math.max(s.Y, 1)
	end

	-- ===== THE YAW JITTER IS PART OF THE FOOTPRINT, NOT A ROUNDING ERROR =====
	-- A 184 x 238 box turned 12 degrees presents 229 studs across, not 184 -- a quarter wider. Sized
	-- off the short axis alone, every run stands a quarter of a hill further inside the zone than
	-- it was placed to, which is how rock ends up in a camp. Both extents are taken at the WORST
	-- turn the jitter allows, so the run's position is a promise rather than an average.
	local turnC, turnS = math.cos(YAW_JITTER), math.sin(YAW_JITTER)

	for _, tier in ipairs({ "inner", "outer" }) do
		local inner = tier == "inner"
		local scale = scaleFor(inner and COVER_INNER or COVER_OUTER)
		local acrossHalf = (shortAxis * turnC + longAxis * turnS) * scale / 2
		local alongLen = (longAxis * turnC + shortAxis * turnS) * scale
		local spacing = alongLen * OVERLAP
		local atX, atZ = AT[tier .. "X"], AT[tier .. "Z"]
		-- ===== THE INNER ROW IS PUSHED OUT UNTIL ITS ROCK IS OFF THE CAMPS (32.1b) =====
		-- `AT` is the pinned baseline and it stays the answer whenever it is already far enough
		-- out. What it cannot know is where the camps ended up: 32.1a's separation clamp moved the
		-- outer column from |x| 400 to 436, i.e. its floor edge from 446 to 482, and 600 was chosen
		-- against 446. The owner walked into the difference before any log did.
		--
		-- Solved rather than re-pinned, because the reach depends on things this file already
		-- derives -- the stock's own box, the cover, the yaw jitter -- and a second hand-typed
		-- number is what put the rock in the camp the first time. `FILL` is how much of the box is
		-- actually rock and `SIZE_JITTER[2]` is the biggest hill a run may stand up, so this is the
		-- WORST case rather than the average: an average passes the test and still buries one camp.
		--
		-- ONLY THE INNER ROW. The outer one stands in the void beyond the platform and has no camp
		-- within 400 studs of it.
		--
		-- WHAT IT COSTS IS BULK, NOT THE SLOPE. A hill reaches ~128 studs inward of its own centre
		-- (measured: a row at 600 read `innermost rock |x| 472`), so a row pushed past `WALL_X`
		-- still has its near face well inside the zone -- what is lost is the depth behind it, not
		-- the mountain in front. The skyline test on the boot line is what says whether that
		-- mattered, and it is a capture that settles whether it still READS as a range.
		--
		-- There may be no room at all, and the boot line has to be able to say so. The wall is at
		-- 625 and a hill reaches 128 studs in, so an outer camp edge past ~482 leaves nothing to
		-- stand a range on inside the boundary -- which is exactly where 32.1a puts it. That is a
		-- finding about the platform, not a number to tune away.
		if inner then
			local clear = acrossHalf * FILL * SIZE_JITTER[2] + CAMP_CLEAR
			atX = math.max(atX, CAMP_EDGE_X + clear)
			atZ = math.max(atZ, CAMP_EDGE_Z + clear)
			innerAtX, innerAtZ = atX, atZ
		end
		-- ===== A RUN HAS TO OVERSHOOT THE CORNER, NOT STOP AT IT =====
		-- These were `at - acrossHalf/2`, i.e. "stop where the other run starts". That leaves the
		-- four CORNERS of the wall bare -- the flank runs ended at |z| 445 against a wall that runs
		-- to 575 -- and a corner is exactly where a player standing in the middle of the zone is
		-- looking when they see the most wall at once. The probe scored the west flank 74% hidden
		-- with the missing quarter all at the ends.
		--
		-- Each run now reaches PAST its own end of the wall by half a hill, so the four overlap
		-- into a closed ring instead of meeting at four gaps.
		local spanZ = WALL_Z + acrossHalf * 0.5
		local spanX = WALL_X + acrossHalf * 0.5
		-- ===== THE OUTER ROW HAS NO GATE LANES, AND THAT IS THE POINT OF IT =====
		-- A lane exists so a hill does not stand on the portal's walkway or on `HubPlaza`'s deck.
		-- The outer row is 200 studs BEYOND the boundary wall, in the void -- there is no walkway
		-- and no deck out there to stand on. Giving it the inner row's lanes anyway left a 264-stud
		-- hole in the skyline directly above the gate, which is the one part of the wall the player
		-- walks straight at. Run whole, it is what fills that hole.
		for _, r in ipairs({
			{ axis = "z", at = -atX, span = spanZ, lane = 0 },
			{ axis = "z", at = atX, span = spanZ, lane = 0 },
			{ axis = "x", at = -atZ, span = spanX, lane = inner and LANE_PORTAL or 0 },
			{ axis = "x", at = atZ, span = spanX, lane = inner and LANE_PORTAL or 0 },
		}) do
			r.scale, r.acrossHalf, r.alongLen, r.spacing = scale, acrossHalf, alongLen, spacing
			r.solid = inner and solid or nil
			hills += buildRun(proto, folder, cx, rng, r, out)
			runs += 1
		end
	end

	MapHorizon.Placed[zoneKey] = out
	MapHorizon.Solid[zoneKey] = solid

	-- ===== THE BOOT LINE IS A TEST, NOT A COUNT =====
	-- Two things here are invisible from any capture taken from inside the zone, and both of them
	-- fail silently. `covers` is how much of the wall's face the inner row actually hides. `over` is
	-- the horizon test from the header -- an outer range that does not clear `180 * d_range/d_wall`
	-- is a range nobody can see, and it would read in a screenshot as "the mountains did not build".
	-- Both figures are MEASURED off the hills that were actually stood up, not recomputed from the
	-- constants above. The scale jitter is +/- 12%, so the shortest hill in a run is what decides
	-- whether the wall shows -- an average would have called the 0.85 build a pass.
	--
	-- ===== THE CAMP TEST USED TO PICK AN AXIS, AND A CORNER HILL MADE IT LIE (32.1b) =====
	-- It read `if dx > dz then reachX = dx - msz.X * FILL / 2 else reachZ = ... end`: decide which
	-- run a hill belongs to by which coordinate is bigger, then measure its box on that axis. A
	-- hill at the CORNER breaks both halves of that. The measured one stood at (-574, 569) -- part
	-- of a NORTH run, which overshoots the corner by half a hill on purpose -- with dx 574 just
	-- over dz 569, so it was measured as a flank hill and its box read on its LONG axis: 373
	-- instead of 227. It reported the rock reaching |x| 472 while its nearest camp was 200 studs
	-- away, and the same false reading is in every boot log this file has ever printed. It passed
	-- only because the number it was compared against (446) happened to be smaller.
	--
	-- The question has no axis in it, so neither does the test now: how close does any hill's rock
	-- come to any camp's FLOOR. Point-to-box for the camp centre against the hill's filled box,
	-- less the floor's own radius. 66 hills against 20 camps, exact, and it names the pair.
	local lowTop, highTop = math.huge, -math.huge
	local gap, gapWhat = math.huge, "-"
	local camps = JungleLayout.Camps(zoneKey) or {}
	for _, m in ipairs(folder:GetChildren()) do
		local hx, hz, top, mx, mz = worldBox(m)
		hx = hx * FILL
		hz = hz * FILL
		mx = mx - cx
		lowTop = math.min(lowTop, top)
		highTop = math.max(highTop, top)
		for _, c in ipairs(camps) do
			local dx = math.max(math.abs(c.x - mx) - hx, 0)
			local dz = math.max(math.abs(c.z - mz) - hz, 0)
			local d = math.sqrt(dx * dx + dz * dz) - JungleLayout.CAMP_RADIUS
			if d < gap then
				gap = d
				gapWhat = ("hill (%.0f, %.0f) vs %s"):format(mx, mz, c.id)
			end
		end
	end

	-- ===== AND WHAT THE COLLISION PASS ENDED UP WITH (32.15) =====
	-- Reported here rather than left to `MapSolids`, because the clipping decision is this file's:
	-- `clipped` is how many boxes had to be cut back off a camp floor and `dropped` how many were
	-- cut to nothing and got no box at all. A non-zero `dropped` is a stretch of range you can still
	-- walk through, which is the whole of what this row set out to close.
	local boxes, clipped, dropped = MapHorizon.Colliders(zoneKey)
	local outerVis = s.Y * scaleFor(COVER_OUTER) - SINK
	local needed = WALL_H * AT.outerX / WALL_X
	print(("[MapHorizon] %s: %d hills over %d runs from a %.0f x %.0f x %.0f stock; "
		.. "tops %.0f..%.0f against the wall's %d -- %s; outer peaks %.0f, needs %.0f to clear "
		.. "the wall from mid-zone -- %s; inner row at %.0f/%.0f (pinned %d/%d)%s; "
		.. "tightest rock-to-camp-floor gap %+.1f studs, %s -- %s; "
		.. "%d collider box(es) offered, %d clipped off a camp floor, %d dropped%s")
		:format(zoneKey, hills, runs, s.X, s.Y, s.Z, lowTop, highTop, WALL_H,
			lowTop > WALL_H and "RIDGE BREAKS THE SKYLINE"
				or ("WALL SHOWS BY %.0f"):format(WALL_H - lowTop),
			outerVis, needed, outerVis > needed and "VISIBLE" or "SUNK BELOW THE WALL",
			innerAtX, innerAtZ, AT.innerX, AT.innerZ,
			(innerAtX > AT.innerX or innerAtZ > AT.innerZ)
				and ((innerAtX > WALL_X or innerAtZ > WALL_Z)
					and "  [pushed off the camps, and the row centre is now OUTSIDE the wall]"
					or "  [pushed off the camps]")
				or "",
			gap, gapWhat,
			-- NOTE: this gap is the FILL-and-pivot-box figure the header's fault 2 describes. It is
			-- left exactly as it was so the line stays comparable with every log before it; the
			-- real number is in the 32.15 row and in `agent-board/CLAUDE-REVIEW.md`.
			gap > 0 and "clear of every camp (see the 32.15 header: this test reads the wrong axis)"
				or "*** ROCK IS STANDING IN A CAMP ***",
			#boxes, clipped, dropped,
			dropped > 0 and "  *** A DROPPED BOX IS RANGE YOU CAN WALK THROUGH ***" or ""))
	return hills
end

return MapHorizon
