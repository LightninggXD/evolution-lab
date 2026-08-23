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
-- Nothing here collides. `MapJungle`'s note is the reason and it still holds: the platform already
-- has a 180-stud boundary wall doing the containing, and a second colliding wall inside it is
-- nothing but somewhere to get stuck.

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

-- ===== THE GATE LANE, AND WHY 132 WAS THE WRONG NUMBER TWICE OVER =====
-- A lane is the gap left in a run so a hill does not stand on the portal. The first cut used
-- `PORTAL_CLEAR_HALF` (132) and offset it by the hill's whole half-LENGTH, which put the nearest
-- rock 380 studs from the centre line -- a 760-stud hole in a 1250-stud wall, straight ahead of the
-- player as she walks to the gate. The occlusion probe read it plainly: **the south wall was 48%
-- hidden and the north 41%**, with bare slate visible down to y = 10.
--
-- Both halves of that were wrong. `PORTAL_CLEAR_HALF` is a WALKWAY reservation and these hills do
-- not collide, do not query and are sunk 15 studs -- nothing walks into them. What the lane really
-- has to miss is the portal's own STONEWORK, which is `PORTAL_GAP` 100 wide plus its columns. 90
-- clears that and lets the range close right up to the doorway, which reads as a gate cut through a
-- mountain rather than a gate in a fence.
--
-- And the offset is the rock's half-length (`FILL`), not the bounding box's: a hill's box is mostly
-- air, so offsetting by the box holds the rock back another 110 studs for nothing.
local LANE_PORTAL = 90

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

-- Every hill this file stood up, as a footprint `MapForest` subtracts so no tree grows inside rock.
-- Same shape `MapRidge.Footprints` returns, so the planter merges the two lists rather than growing
-- a second keep-out branch.
function MapHorizon.Footprints(zoneKey)
	return MapHorizon.Placed[zoneKey] or {}
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
local function hill(proto, parent, cx, x, z, yaw, scale)
	local m = proto:Clone()
	local _, raw = m:GetBoundingBox()
	if raw.Y < 1 then m:Destroy() return nil end
	m:ScaleTo(scale)
	m:PivotTo(m:GetPivot() * CFrame.Angles(0, yaw, 0))
	local cf, sz = m:GetBoundingBox()
	m:PivotTo(m:GetPivot() + Vector3.new(cx + x - cf.Position.X,
		-(cf.Position.Y - sz.Y / 2) - SINK, z - cf.Position.Z))
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CastShadow = false
		end
	end
	m.Name = "HorizonHill"
	m.Parent = parent
	return sz
end

-- A run of hills along one axis, placed from a COUNT AND A SPAN rather than by stepping one off the
-- last. `evolution-lab-arc-must-not-close` is the standing note: 31.18 extended an arc by repeating
-- a step and twenty 18.3-degree steps closed a 366-degree ring that sealed the owner inside it. A
-- run built from a count cannot overrun its own end.
--
-- `lane` is the half-width of the gap left in the middle of the run; a run with no gate gets 0.
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
			hills += buildRun(proto, folder, cx, rng, r, out)
			runs += 1
		end
	end

	MapHorizon.Placed[zoneKey] = out

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
		local mcf, msz = m:GetBoundingBox()
		local top = mcf.Position.Y + msz.Y / 2
		lowTop = math.min(lowTop, top)
		highTop = math.max(highTop, top)
		local mx, mz = mcf.Position.X - cx, mcf.Position.Z
		local hx, hz = msz.X * FILL / 2, msz.Z * FILL / 2
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

	local outerVis = s.Y * scaleFor(COVER_OUTER) - SINK
	local needed = WALL_H * AT.outerX / WALL_X
	print(("[MapHorizon] %s: %d hills over %d runs from a %.0f x %.0f x %.0f stock; "
		.. "tops %.0f..%.0f against the wall's %d -- %s; outer peaks %.0f, needs %.0f to clear "
		.. "the wall from mid-zone -- %s; inner row at %.0f/%.0f (pinned %d/%d)%s; "
		.. "tightest rock-to-camp-floor gap %+.1f studs, %s -- %s")
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
			gap > 0 and "clear of every camp" or "*** ROCK IS STANDING IN A CAMP ***"))
	return hills
end

return MapHorizon
