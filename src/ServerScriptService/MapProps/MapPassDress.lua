-- MapProps/MapPassDress -- the hole `MapPass.Cut` opens in the horizon range gets dressed, or it
-- reads as a bug: seven hills gone is a canyon with saw-cut faces.
--
-- ===== REVIEW R1, FAULT 2: THE SKYLINE IS THE HALF THIS FILE EXISTS FOR =====
-- The first dressing stopped at outcrop scale: ten 16..30-stud crags capped the ground at the
-- mouth while the boundary wall ran on bare above them -- measured on the rebuilt world,
-- `nearest rock edge x=-166 / +182 -> BARE SPAN 348 | dressing top y=27 | boundary wall ~180`.
-- From the village camera the opened gate framed edge-to-edge flat slate, which is the outcome
-- the owner rejected twice when the lane was widened instead of deepened. What fills that frame
-- is a SHOULDER: one stock mountain a side, scaled until its top clears the wall, so the pass
-- reads as a gap BETWEEN peaks rather than a notch punched in a fence.
--
-- ===== WHY RELOCATE LOST TO DELETE-PLUS-SHOULDER =====
-- R1 preferred relocating each offender outward. Tried arithmetically against the measured
-- boxes first: the two east hills clear the corridor only at centres ~445 and ~449, two 500-stud
-- mountains landing 5 studs apart -- the stacked-lump outcome R1's own "re-check against its new
-- neighbour" forbids -- and the west side collapses the same way into a 65-stud slot. Full
-- working in `agent-board/OX-LOG.md`, T1-fix.
--
-- ===== WHY BEHIND THE WALL, ON THE OUTER ROW'S LINE =====
-- The cut tore its hole in the outer row (measured offender centres z -776..-785; `AT.outerZ`
-- is 776). A shoulder seated THERE refills the torn line: its skirt hides behind the boundary
-- wall like every outer hill's, its peak rises over the pass, and the surviving neighbours
-- overlap it back into one silhouette. Seated IN FRONT of the wall instead, the same mountain
-- buries the near-mouth crags R1 said to keep exactly as they are, and crowds `MapGateFlanks`'s
-- work at the arch.
--
-- ===== AND THE PRICE OF STANDING BEHIND IT: "CLEARS THE WALL" IS NOT A HEIGHT =====
-- A shoulder on that line is 205 studs FARTHER from the village than the wall, so the first
-- build's "wall 180 + 30" stood a 210-stud mountain 40 studs BELOW the skyline -- invisible, and
-- no line said so. The height is derived from `needToClear` below instead.
--
-- ===== AND WHY IT CANNOT PINCH THE PASS EVEN SO =====
-- Turned with the run (yaw pi/2) a shoulder's long axis lies ALONG the range, ~400 studs of it;
-- seeded at |x| SHOULDER_X its near face can still cross into the corridor, so the placed box is
-- MEASURED and the whole model pushed out until it clears cx +- (CORRIDOR_HALF_X + LANE_MARGIN)
-- -- the same measure-then-shift guarantee `MapGateFlanks.keepClearOfLane` applies at the arch.
-- Pure extents, no raycast (rule 5); seeded draws (rule 4); re-derived from whatever stock the
-- map carries.
--
-- Skyline, not floor: like every outer-row hill these carry NO collider and NO query --
-- unreachable behind the wall, and a collider there would be an invisible wall in waiting.

local MapPassDress = {}

local MapHorizon = require(script.Parent.MapHorizon)

-- The corridor numbers are `MapPass.Cut`'s own, repeated because this file measures the SAME
-- opening it dresses -- if the cut ever moves, both files move together.
local CORRIDOR_HALF_X = 100
local CORRIDOR_Z_MIN, CORRIDOR_Z_MAX = -660, -460

-- ===== THE CRAGS (kept verbatim from the first dressing -- R1: "that part works") =====
local CRAG_SEED = 20260825
local CRAG_COUNT = 10
local CRAG_X_MIN, CRAG_X_MAX = 70, 95
local CRAG_Z_NEAR, CRAG_Z_FAR = -468, -566
local CRAG_H_MIN, CRAG_H_MAX = 16, 30
local CRAG_SINK = 3

-- ===== WHAT THE VILLAGE CAN ACTUALLY SEE OVER THE WALL =====
-- The wall is read from `MapHorizon.Wall`, never retyped -- retyping it is what produced the
-- invisible shoulder. VIEW is the camera R1 judged the last build from, (0, 45, -180); the same
-- formula at a walking eye (y 6) asks for 270, which the RISE margin below also covers.
local WALL = MapHorizon.Wall
local VIEW_Y, VIEW_Z = 45, -180

-- How tall a peak standing at `z` must be for its top to appear ABOVE the wall's top edge from a
-- camera at (`viewY`, `viewZ`). Similar triangles: the wall's top edge and the peak are read on the
-- same line of sight, so a peak farther away than the wall has to be taller by the ratio of the two
-- distances. That is the whole reason a 210-stud shoulder once stood 40 studs BELOW the skyline.
--
-- EXPORTED, because `MapGateFlanks` needs the same answer for the rampart it stands behind the wall
-- at each gate (33.4) and a second copy of this is the 31.5a trap -- one fact, two files, drifting.
-- Which of the zone's two walls is in the way is taken from the SIGN of the look direction, so it
-- serves the +Z gate as well as the -Z pass this file was written for.
function MapPassDress.NeedToClear(viewY, viewZ, z)
	local wallZ = (z > viewZ) and WALL.z or -WALL.z
	return viewY + (WALL.h - viewY) * (z - viewZ) / (wallZ - viewZ)
end

local function needToClear(z)
	return MapPassDress.NeedToClear(VIEW_Y, VIEW_Z, z)
end

-- ===== THE SHOULDERS =====
-- Z -780 sits on the outer row's line (AT.outerZ 776; offender centres measured -779/-785), so
-- the shoulder refills the line the cut tore rather than standing somewhere new. RISE 1.35 over
-- `needToClear` is the reading margin: bare clearance is a peak that GRAZES the wall line and
-- still reads as nothing. The arithmetic is checked against the world rather than trusted --
-- measured live on the BETA place, the surviving hills on this same line stand 299..391 tall,
-- so a derived 338 comes out a peer of the row it refills instead of a new class of peak.
-- Sunk with the range's own 15. X 305 is the SEED, solved from the turned stock's length so the
-- seed already clears the lane, and the nudge below is the guarantee rather than the hope.
-- Separate seeds: the crags' draw must not shift because a shoulder joined the pass (rule 4 --
-- same numbers on every server).
local SHOULDER_SEED = 20260827
local SHOULDER_SINK = 15
local SHOULDER_Z = -780
local SHOULDER_RISE = 1.35
local SHOULDER_TOP = math.floor(needToClear(SHOULDER_Z) * SHOULDER_RISE)
local SHOULDER_X = 305
local LANE_MARGIN = 8

-- The frame the village camera actually holds at the gate: the bare span R1 measured ran
-- -166..+182, so a skyline test narrower than that cannot see the rock it is asking about.
local FRAME_HALF_X = 340
local YAW_JITTER = 0.21 -- the range's own turn limit, so shoulders sit in the line like natives

local DRESS_FOLDER = "PortalPassDressing"

function MapPassDress.Init(zoneKey, cx, map)
	local old = map and map:FindFirstChild(DRESS_FOLDER)
	if old then old:Destroy() end
	local dress = Instance.new("Folder")
	dress.Name = DRESS_FOLDER
	dress.Parent = map

	local proto = MapHorizon.Stock(map)

	-- One seating routine for both scales of dressing: scale, turn, RE-MEASURE, move -- in that
	-- order, for the reason `MapHorizon.hill` keeps on record (a rotated model is another box).
	local function seat(rng, spec)
		local m = proto:Clone()
		local _, raw = m:GetBoundingBox()
		if raw.Y < 1 then m:Destroy() return nil end
		m:ScaleTo((spec.topTarget and spec.topTarget + spec.sink
			or rng:NextNumber(spec.hMin, spec.hMax)) / raw.Y)
		m:PivotTo(CFrame.new(m:GetPivot().Position) * CFrame.Angles(0, spec.yaw, 0))
		local cf, sz = m:GetBoundingBox()
		m:PivotTo(m:GetPivot() + Vector3.new(spec.x - cf.Position.X,
			-(cf.Position.Y - sz.Y / 2) - spec.sink, spec.z - cf.Position.Z))
		if spec.side then
			local rx, _, _, wx = MapHorizon.WorldBox(m)
			if not rx then m:Destroy() return nil end
			local limit = CORRIDOR_HALF_X + LANE_MARGIN
			local spill = spec.side > 0
				and math.max(0, cx + limit - (wx - rx))
				or math.max(0, (wx + rx) - (cx - limit))
			if spill > 0 then m:PivotTo(m:GetPivot() + Vector3.new(spec.side * spill, 0, 0)) end
		end
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = spec.collide
				d.CanQuery = spec.collide
				d.CastShadow = false
			end
		end
		m.Name = spec.name
		m.Parent = dress
		local rx, rz, top, wx, wz = MapHorizon.WorldBox(m)
		return rx and { mnx = wx - rx, mxx = wx + rx, mnz = wz - rz, mxz = wz + rz, top = top }
	end

	local crags, shoulders = 0, 0
	if proto then
		local rng = Random.new(CRAG_SEED + math.floor(cx))
		for i = 1, CRAG_COUNT do
			local side = (i % 2 == 0) and 1 or -1
			local t = (i - 1) / (CRAG_COUNT - 1)
			if seat(rng, {
				x = side * rng:NextNumber(CRAG_X_MIN, CRAG_X_MAX),
				z = CRAG_Z_NEAR + t * (CRAG_Z_FAR - CRAG_Z_NEAR) + rng:NextNumber(-8, 8),
				sink = CRAG_SINK, hMin = CRAG_H_MIN, hMax = CRAG_H_MAX,
				yaw = math.pi / 2 + rng:NextNumber(-0.3, 0.3),
				name = "PassRock", collide = true,
			}) then crags += 1 end
		end

		local srng = Random.new(SHOULDER_SEED + math.floor(cx))
		for _, side in ipairs({ -1, 1 }) do
			if seat(srng, {
				x = side * SHOULDER_X, z = SHOULDER_Z, sink = SHOULDER_SINK,
				topTarget = SHOULDER_TOP, side = side,
				yaw = math.pi / 2 + srng:NextNumber(-YAW_JITTER, YAW_JITTER),
				name = "PassShoulder", collide = false,
			}) then shoulders += 1 end
		end
	end

	-- ===== THE BOOT LINE IS THE TEST R1 ASKED FOR, AND THE SECOND HALF OF IT USED TO BE DEAD ====
	-- Edges: the nearest RANGE rock either side of the lane (surviving hills + these shoulders --
	-- the low mouth crags are excluded, the exact figure R1 called meaningless at y 27).
	--
	-- Skyline: the tallest rock in the FRAME the village camera holds, judged against
	-- `needToClear` at that rock's own z, so the line says whether the peak is SEEN and not merely
	-- whether it is tall. The first version asked for the tallest rock inside x +-100 -- the very
	-- rectangle `MapPass.Cut` empties and the nudge above keeps empty -- so on a correct build it
	-- was arithmetically guaranteed to print nothing -- and a test that cannot pass is exactly how
	-- a 210-stud shoulder shipped behind a 180-stud wall without a single line complaining.
	local west, east, tallest
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("Model") and (d.Name == "HorizonHill" or d.Name == "PassShoulder") then
			local rx, rz, top, wx, wz = MapHorizon.WorldBox(d)
			if rx and wz + rz >= CORRIDOR_Z_MIN and wz - rz <= CORRIDOR_Z_MAX then
				local mnx, mxx = wx - rx, wx + rx
				if mxx <= cx + 1 and (not west or mxx > west) then west = mxx end
				if mnx >= cx - 1 and (not east or mnx < east) then east = mnx end
				-- CENTRE south of the wall, not merely a box that reaches the band: the fixed-x
				-- runs are 800 studs long, so an overlap test alone lets a hill standing beside
				-- the VILLAGE into a measurement about the skyline over the pass. It read
				-- `tallest in frame y 295 -- SHOWS BY 257` on the first build of this line, which
				-- is a hill 400 studs nearer the camera answering a question about one 600 away.
				if wz <= -WALL.z and mxx >= cx - FRAME_HALF_X and mnx <= cx + FRAME_HALF_X
					and (not tallest or top > tallest) then tallest = top end
			end
		end
	end
	-- The shoulders answer for THEMSELVES, against the line of sight at their own z -- the two
	-- numbers that make "is the skyline dressed rock or bare wall" a question with an answer.
	local need = needToClear(SHOULDER_Z)
	print(("[MapPassDress] %s: dressed %d crags + %d shoulders; range rock edges x %s / %s "
		.. "(bare span %s); shoulders y %d vs %.0f needed to clear the wall -- %s; "
		.. "tallest rock over the pass y %s")
		:format(zoneKey, crags, shoulders,
			west and ("%.0f"):format(west) or "-",
			east and ("%+.0f"):format(east) or "-",
			(west and east) and ("%.0f"):format(east - west) or "-",
			SHOULDER_TOP, need,
			shoulders == 0 and "NONE STANDING"
				or (SHOULDER_TOP > need and ("SHOW BY %.0f"):format(SHOULDER_TOP - need)
					or ("HIDDEN BY %.0f"):format(need - SHOULDER_TOP)),
			tallest and ("%.0f"):format(tallest) or "NOTHING"))
	return crags + shoulders
end

return MapPassDress
