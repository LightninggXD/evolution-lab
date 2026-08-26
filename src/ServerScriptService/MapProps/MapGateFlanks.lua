-- MapProps/MapGateFlanks -- the wall either side of her arch stops reading as four flat walls.
--
-- The owner, on the first live look at the seated arch: *"malo ti izviruje ova crvena i sad se
-- bas vidi zid, mora nekako izgledati kao da si u prirodi zatvoren a ne u 4 zida"*. The red
-- overhang was MapGateArch's to fix; the BARE WALL is this file's. The built gate used to put
-- frame, lintel, cap, columns and guardians across a hundred studs of slate; her arch replaced
-- them with a hundred and seven studs of arch, and what is left is the flat 180-tall wall
-- segment each side -- which `addRockRampart` deliberately keeps clear, because
-- `PORTAL_CLEAR_HALF` (132) holds its rocks that far off the gate centre. Nothing natural has
-- stood near the door since the arch replaced the stonework.
--
-- ===== WHAT GOES WHERE =====
-- FLANKS: the map's own mountain stock at outcrop scale (40..75 against the range's ~294), two
-- staggered pairs a side, |x| 56..126 -- outside the arch's legs (+-54), inside the rampart's
-- keep-clear, sunk 7 so each crag reads as grown against the wall rather than parked on it, and
-- turned +90 so the stock's long axis runs ALONG the wall -- a buttress, not a lump.
--
-- BACK-FILL: the wall gap runs the FULL 180 up and the arch tops out at 138, so a slot of sky
-- hung above the red door. Two taller crags stand BEHIND the arch (130..165 tall, tops under the
-- wall's 180): through the slot, and through the arch's open crown above the film, the eye lands
-- on rock instead of sky. They are past the sheet's plane, where the 32.28 cut already removed
-- every hill, so nothing is buried and nothing new blocks the corridor.
--
-- ===== 33.4: AND THE FLANKS WERE NEVER TALL ENOUGH TO DO THE JOB THE HEADER CLAIMS =====
-- Everything above is about the WALL, and every crag it stands is 40..75 tall against a wall that
-- is 180. Measured 2026-08-26 from the eye the captures were taken at, by marching the segment from
-- the camera to a grid of points on the wall's own face and asking what is in the way (the rocks
-- are `CanQuery = false`, so a raycast answers about an empty world -- R31's standing warning):
--
--   SOUTH eye(0,25,-240)   125 of 972 wall cells VISIBLE   one unbroken band x -200..+200
--   NORTH eye(0,25, 250)    89 of 972 wall cells VISIBLE   x -200..-120 and +110..+210
--
-- Every visible cell is in the TOP band, y 130..175. That is the whole shape of the fault: the
-- crags cap the wall's FOOT and its top edge runs on bare above them, which is R1's fault 2 again,
-- one tier up. The owner's words for it, twice: *"mora nekako izgledati kao da si u prirodi zatvoren
-- a ne u 4 zida"*.
--
-- ===== AND WHY THE ANSWER IS NOT A TALLER SHOULDER BEHIND THE WALL =====
-- `MapPassDress` fills the sky over the pass with two 338-stud shoulders at z -780, and they do not
-- touch this: a rock BEHIND the wall cannot hide the wall's FACE, it can only stand above its top
-- edge. The survey marches from the eye and STOPS at the wall for exactly that reason. What covers
-- a wall face is rock in front of it, and nothing tall has ever stood there.
--
-- ===== THE RAMPART =====
-- A run of the map's own rock hugging the wall on the village side of it, either side of each gate,
-- tall enough that the wall's top edge is behind rock from the village eye. Three things are
-- derived rather than chosen:
--
--  * THE HEIGHT, from `MapPassDress.NeedToClear` -- the same similar-triangles line of sight that
--    sizes the pass shoulders, exported there rather than retyped here (31.5a). Standing in FRONT
--    of the wall it asks for LESS than the wall's 180, not more, which is why a rampart is a
--    reasonable rock and a shoulder is a mountain.
--  * THE FOOTPRINT, from a uniform scale, and then the height alone is stretched to the target on
--    Y. `ScaleTo` is uniform and this stock is twice as wide as it is tall, so a crag scaled to 200
--    is 400 across and buries the door it is framing -- 33.20's fault exactly. The Y-only stretch is
--    `MapHorizon.hill`'s `riseTo`, and it is exact rather than approximate for the reason recorded
--    there: every part of this stock stands upright, so a part's local Y IS world Y.
--  * THE INNER EDGE, from the gate's OWN measured stonework, per gate. The two gates are not alike
--    -- the arch is 108 wide and 118 tall, the +Z gate is 230 wide and 222 tall -- so a typed |x|
--    would be wrong at one of them. `MapGateArch.FindSheet` deliberately answers for the -Z gate
--    only, so the +Z gate has never had any dressing at all; it gets a rampart and nothing else,
--    because its own stonework already does the framing an arch needed crags for.
--
-- NO COLLIDER AND NO QUERY, and that is the same call `MapPassDress` makes for its shoulders: the
-- boundary wall is the barrier here and it is 12 studs behind them, so a collider adds nothing a
-- player can reach and a 200-stud mesh's collision box in front of a gate is an invisible wall in
-- waiting (the 30.19 trap, and 32.15/32.19 are what it costs). The flanks below keep theirs -- they
-- are outcrops on open ground at the mouth, which is a different question.
--
-- ===== THE STANDING RULES THIS FILE LIVES BY =====
-- Seeded off the zone (`SEED + floor(cx)`) -- rule 4, the same draw twice problem that has
-- shipped broken twice. No raycast decides a position (rule 5) -- every coordinate here is a
-- constant or a seeded draw against the sheet's own measured plane. Direct `CanCollide = true`
-- parts rather than MapSolids boxes -- these are 40..165 stud solids, not invisible walls, and
-- nothing that walks may pass through the dressing (owner rule, 32.10).

local MapGateFlanks = {}

local MapPass = require(script.Parent.MapPass)
local MapRidge = require(script.Parent.MapRidge)
local MapGateArch = require(script.Parent.MapGateArch)
local MapHorizon = require(script.Parent.MapHorizon)
local MapPassDress = require(script.Parent.MapPassDress)

local SEED = 20260826

-- ===== THE RAMPART, 33.4 (see the header block) =====
-- The wall is READ, never retyped -- `MapPassDress` records what retyping it cost.
local WALL = MapHorizon.Wall
-- The eye the survey in the header was taken from, and the eye both captures were taken from: on
-- the road, a little back from the gate. A walking eye (y 6) at the same z asks for two studs less,
-- so this is the demanding one of the pair and RAMPART_RISE covers the difference either way.
local VIEW_Y, VIEW_Z_ABS = 25, 240
local RAMPART_SEED = 20260828      -- its OWN seed: adding a rampart must not re-roll the flanks
-- A CEILING on the count, not a target: the run is stepped off each crag's own measured width and
-- stops at RAMPART_X_MAX. The cap is here only so a pathological stock cannot loop forever
-- ([[evolution-lab-arc-must-not-close]] -- a run built by stepping needs a bound that is not the
-- step itself).
local RAMPART_MAX_PER_SIDE = 6
-- The next crag's centre stands this fraction of the last one's half-width further out. Under 1.0
-- so they overlap into one ridge rather than standing as separate lumps -- `MapHorizon.OVERLAP` is
-- the same judgement, and 0.70 is what lets KNIT below solve to a top inside RAMPART_TOP_MAX.
local RAMPART_STEP = 0.70
local RAMPART_IN_FRONT = 12        -- studs on the village side of the wall plane
local RAMPART_Z_JITTER = 5
-- The UNIFORM scale, i.e. the footprint budget. At this stock's measured aspect (half-width ~= its
-- own height) a 70..110 crag is 140..220 across, so three a side overlap into a ridge across the
-- band the survey found bare instead of standing as separate lumps -- `MapHorizon.OVERLAP` is the
-- same judgement one scale up.
-- 130..190 and not 70..110, and the first build is why. At 70..110 the knit equation solved to
-- tops of 259..326 on half-widths of 66..97 -- ten rocks TALLER than they were wide, and the
-- capture read them as a picket fence rather than as a range. The survey passed on that build
-- (0 of 840) and the picture refused it, which is this row's whole history in one pass. A wider
-- base buys the same cover at a lower top, because KNIT is solved and not chosen.
local RAMPART_BASE_MIN, RAMPART_BASE_MAX = 130, 190
-- Over the line of sight, so the peak stands ABOVE the wall's top edge rather than grazing it --
-- MapPassDress's SHOULDER_RISE exists for the same reason and says so: bare clearance reads as
-- nothing. 1.15 and not 1.35 because this rock is 30 studs from the camera's wall, not 200.
local RAMPART_RISE = 1.15
-- ===== AND WHY "TALL ENOUGH TO CLEAR THE WALL" IS STILL NOT TALL ENOUGH =====
-- The first build of this rampart stood 6 crags to y 204 against a 180 wall and the survey still
-- read 64 of 972 south cells visible, every one of them in the top band. `MapHorizon.OVERLAP`
-- already records why, one scale up: **a mountain is a cone and its bounding box is a box**, so
-- what matters is the rock's width AT THE WALL'S HEIGHT, not at its base. A crag of half-width 90
-- stretched to 204 is 220 studs across on the ground and **25 across at y 180** -- a spire, with
-- daylight either side of it exactly where the wall's top edge runs.
--
-- So the target top is SOLVED rather than chosen. For a cone of peak `T` sunk by `SINK`, the
-- half-width surviving at height `h` is `halfX * (1 - (h + SINK) / (T + SINK))`; setting that equal
-- to half the spacing between neighbours and inverting gives the `T` at which the run knits into
-- one silhouette along the wall's top edge. KNIT > 1 is the overlap, the same judgement (and for
-- the same reason) as `OVERLAP` being under 1.0 in `MapHorizon`.
local RAMPART_KNIT = 1.15
-- A ceiling, so a narrow crag cannot solve the equation by becoming a needle: the range's own hills
-- measure 265..391 here, so a rampart is allowed to be a peer of the range and no more. A crag that
-- cannot knit under this cap leaves its gap and the boot line says the target was capped.
local RAMPART_TOP_MAX = 340
-- ... and never shorter than the gate it flanks, by this much: a rampart under the gate's own top
-- reads as a fence beside a doorway. 32.19 settled the look at 274 of rock against 222 of gate.
local RAMPART_FRAME_RISE = 1.12
local RAMPART_X_MAX = 320          -- the band ends where the survey's bare run ends (+-200) + margin
-- Clear of the gate's OWN measured stonework, per gate -- and it is applied to the crag's measured
-- INNER EDGE, never to its centre. The first build spent it on the centre and stood two 180-stud
-- rocks with inner edges at x -33 and +41 straight across an arch that spans -53..53: the gate
-- vanished, which is the owner's 33.20 complaint reproduced by the file that exists to prevent it.
-- Same measure-then-shift guarantee as `keepClearOfLane` below, and for the same reason.
local RAMPART_GATE_MARGIN = 14
local RAMPART_SINK = 10

-- ===== FLANKS =====
local FLANK_COUNT = 8                     -- four a side, staggered near-to-far
local FLANK_X_MIN, FLANK_X_MAX = 56, 126  -- outside the arch legs, inside the 132 keep-clear
local FLANK_Z_JITTER = 7                  -- the wall line is z = sheetZ; crags breathe around it
local FLANK_H_MIN, FLANK_H_MAX = 40, 75
-- ===== BACK-FILL =====
local BACK_COUNT = 2
local BACK_X_MIN, BACK_X_MAX = 6, 26
local BACK_Z_MIN, BACK_Z_MAX = -596, -618 -- past the sheet, inside the 32.28 cut
local BACK_H_MIN, BACK_H_MAX = 130, 165   -- seen THROUGH the 138..180 slot; under the wall's 180

local SINK = 7
local DRESS_FOLDER = "PortalArchFlanks"

-- Measured guarantees, applied to each PLACED crag. The stock is a wide, squat mass -- the
-- first live build placed by CENTRE alone and a "150-tall" crag came out 217 x 279 in
-- footprint, spilling 105 studs in front of the gate and across the walk line (17 blocked
-- samples), while a flank buried the arch's left leg. Both guarantees re-measure the placed
-- box and shift the whole crag once -- pure extents, no raycasts (rule 5).
local LANE_CLEAR_X = 54    -- crag edge stays outside the arch's legs (+-53.5)
local WALL_BACK_MARGIN = 2 -- back-fill front edge stays behind the wall's back face

local function keepClearOfLane(m, side)
	local cf, sz = m:GetBoundingBox()
	if side > 0 then
		local inner = cf.Position.X - sz.X / 2
		if inner < LANE_CLEAR_X then
			m:PivotTo(m:GetPivot() + Vector3.new(LANE_CLEAR_X - inner, 0, 0))
		end
	else
		local inner = cf.Position.X + sz.X / 2
		if inner > -LANE_CLEAR_X then
			m:PivotTo(m:GetPivot() + Vector3.new(-LANE_CLEAR_X - inner, 0, 0))
		end
	end
end

local function keepBehindWall(m, gz)
	local cf, sz = m:GetBoundingBox()
	local front = cf.Position.Z + sz.Z / 2
	local limit = gz - WALL_BACK_MARGIN
	if front > limit then
		m:PivotTo(m:GetPivot() + Vector3.new(0, 0, limit - front))
	end
end

-- The gate's own stonework, measured: world x span and top, over every part of THIS gate. Taken
-- from the parts rather than typed because the two gates differ by a factor of two in both, and a
-- typed number would be wrong at one of them (33.4). Yawed parts are handled the way every probe in
-- MapProps handles them -- abs-of-components, not `Size` (`roblox-part-size-is-in-its-own-frame`).
--
-- ===== AND THE NAME TEST ALONE MISSES THE ONE THING THAT MATTERS MOST =====
-- Her arch is a MODEL, `PortalArch`, whose parts are named `Meshes/Portal_Plane` and `Part` -- so
-- a sweep for BaseParts named `Portal*` measured the teleport sheet at x -37..37 and reported that
-- as the gate, when the arch around it spans **x -53..53 and stands 137 tall**. Every rampart
-- placed off that number stood 16 studs too far in. Models whose NAME matches are measured whole,
-- by their own bounding box, which is also the only honest way to measure a mesh model
-- ([[roblox-model-box-getters-are-pivot-frame]]).
local function gateSpan(zoneModel, sign)
	local mnx, mxx, top = math.huge, -math.huge, 0
	for _, d in ipairs(zoneModel:GetChildren()) do
		if d:IsA("Model") and d.Name:match("^Portal") then
			local cf, sz = d:GetBoundingBox()
			if cf.Position.Z * sign > 0 then
				mnx = math.min(mnx, cf.Position.X - sz.X / 2)
				mxx = math.max(mxx, cf.Position.X + sz.X / 2)
				top = math.max(top, cf.Position.Y + sz.Y / 2)
			end
		end
	end
	for _, d in ipairs(zoneModel:GetDescendants()) do
		if d:IsA("BasePart") and d.Position.Z * sign > 0
			and (d.Name:match("^Portal") or d.Name:match("^Arrival")) then
			local cf, sz = d.CFrame, d.Size
			local hx = (math.abs(cf.RightVector.X) * sz.X + math.abs(cf.UpVector.X) * sz.Y
				+ math.abs(cf.LookVector.X) * sz.Z) / 2
			local hy = (math.abs(cf.RightVector.Y) * sz.X + math.abs(cf.UpVector.Y) * sz.Y
				+ math.abs(cf.LookVector.Y) * sz.Z) / 2
			mnx = math.min(mnx, cf.Position.X - hx)
			mxx = math.max(mxx, cf.Position.X + hx)
			top = math.max(top, cf.Position.Y + hy)
		end
	end
	if mnx == math.huge then return nil end
	return mnx, mxx, top
end

-- The Y-ONLY stretch, `MapHorizon.hill`'s `riseTo` applied to a crag this file seated. It is exact
-- and not an approximation for the reason recorded there: every part of this stock stands perfectly
-- upright (`UpVector` (0, 1, 0) on all of them, only the yaw varies), so a part's local Y is world
-- Y and the mesh cannot shear. `base` is the crag's own sunk floor, so the stretch pivots on the
-- ground rather than on the model's centre.
local function stretchTo(m, base, target)
	local _, _, top = MapHorizon.WorldBox(m)
	if not top or top >= target then return end
	local k = (target - base) / (top - base)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Size = Vector3.new(d.Size.X, d.Size.Y * k, d.Size.Z)
			d.Position = Vector3.new(d.Position.X, base + (d.Position.Y - base) * k, d.Position.Z)
		end
	end
end

-- One gate's rampart. Returns how many crags stood up and the top they were asked for, so the boot
-- line can carry both -- a count alone cannot tell a rampart that is too short from one that is
-- absent, which is the exact failure `MapPassDress`'s dead skyline test used to hide.
local function rampart(dress, proto, rng, zoneModel, sign)
	local mnx, mxx, gateTop = gateSpan(zoneModel, sign)
	if not mnx then return 0, 0, "no gate parts" end
	local z = sign * (WALL.z - RAMPART_IN_FRONT)
	-- The line of sight is judged from the village side of THIS gate, hence the sign on VIEW_Z_ABS.
	local need = MapPassDress.NeedToClear(VIEW_Y, sign * -VIEW_Z_ABS, z)
	local floor = math.max(need * RAMPART_RISE, gateTop * RAMPART_FRAME_RISE)
	local made, capped, tallest = 0, 0, 0
	for _, side in ipairs({ -1, 1 }) do
		-- Inner edge off the gate's OWN measured stonework on THIS side, not off a symmetric
		-- assumption: the +Z gate measures x -120..110 and is 10 studs off centre.
		local limit = math.abs(side > 0 and mxx or mnx) + RAMPART_GATE_MARGIN
		-- `edge` is where the NEXT crag's inner face may begin. It starts at the gate and is walked
		-- outward by each crag that actually stands up, so the run is stepped off measured rock rather
		-- than off a count -- and it is bounded by RAMPART_X_MAX and RAMPART_MAX_PER_SIDE, either of
		-- which ends it, so a stepped run cannot overrun the way 31.18's arc did.
		local edge = limit
		for _ = 1, RAMPART_MAX_PER_SIDE do
			if edge > RAMPART_X_MAX then break end
			local m = proto:Clone()
			local _, raw = m:GetBoundingBox()
			if raw.Y < 1 then m:Destroy() break end
			m:ScaleTo(rng:NextNumber(RAMPART_BASE_MIN, RAMPART_BASE_MAX) / raw.Y)
			-- Scale, turn, RE-MEASURE, move -- a rotated model is a different box.
			m:PivotTo(CFrame.new(m:GetPivot().Position)
				* CFrame.Angles(0, math.pi / 2 + rng:NextNumber(-0.25, 0.25), 0))
			local cf, sz = m:GetBoundingBox()
			local zz = z + rng:NextNumber(-RAMPART_Z_JITTER, RAMPART_Z_JITTER)
			-- Seated by its INNER EDGE: the box is measured first and the centre solved from it, so
			-- the crag stands beside the gate however wide the draw came out.
			local x = side * (edge + sz.X / 2)
			m:PivotTo(m:GetPivot() + Vector3.new(x - cf.Position.X,
				-(cf.Position.Y - sz.Y / 2) - RAMPART_SINK, zz - cf.Position.Z))
			local rx = MapHorizon.WorldBox(m)
			if not rx or rx <= 0 then m:Destroy() break end
			-- The placed box, not the pre-rotation one: the guarantee is made against the rock that
			-- is standing there (`MapPassDress.seat` and `keepClearOfLane` both work this way).
			local spill = math.max(0, limit - (math.abs(x) - rx))
			if spill > 0 then m:PivotTo(m:GetPivot() + Vector3.new(side * spill, 0, 0)) end
			-- The step, and the top that knits at it, both come from THIS crag's own half-width, so a
			-- narrow draw is stretched further and stepped less. See RAMPART_KNIT.
			local step = rx * RAMPART_STEP
			local want = floor
			local k = math.min((step / 2 * RAMPART_KNIT) / rx, 0.95)
			local knit = (WALL.h + RAMPART_SINK) / (1 - k) - RAMPART_SINK
			if knit > want then want = knit end
			if want > RAMPART_TOP_MAX then want, capped = RAMPART_TOP_MAX, capped + 1 end
			-- The stretch happens AFTER seating, so it works on the rock standing there --
			-- `MapHorizon.hill` keeps the same ordering for the same reason.
			stretchTo(m, -RAMPART_SINK, want)
			tallest = math.max(tallest, want)
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = true
					-- Skyline, not floor -- see the header. The wall behind it is the barrier.
					d.CanCollide = false
					d.CanQuery = false
					d.CastShadow = false
				end
			end
			m.Name = "GateRampart"
			m.Parent = dress
			made += 1
			-- The next crag begins one step out from where THIS one's inner face actually ended,
			-- push included -- `x` is the centre before the guarantee ran, so it is not the answer.
			edge = (math.abs(x) + spill - rx) + step
		end
	end
	return made, tallest, ("gate x %.0f..%.0f top %.0f; sight line asks %.0f, %d capped at %d")
		:format(mnx, mxx, gateTop, need, capped, RAMPART_TOP_MAX)
end

function MapGateFlanks.Init(zoneKey, cx, map)
	local zones = workspace:FindFirstChild("Zones")
	local zoneModel = zones and zones:FindFirstChild(zoneKey)
	if not zoneModel then
		warn(("[MapGateFlanks] %s: no zone model to dress against -- skipped"):format(zoneKey))
		return 0
	end
	-- The arch's own sheet, and it may legitimately be missing: `FindSheet` answers for the -Z gate
	-- alone, so the rampart below is NOT gated on it (33.4 -- the +Z gate has no arch and is exactly
	-- the gate this whole file had never reached).
	local sheet = MapGateArch.FindSheet(zoneModel)

	local old = map and map:FindFirstChild(DRESS_FOLDER)
	if old then old:Destroy() end
	local dress = Instance.new("Folder")
	dress.Name = DRESS_FOLDER
	dress.Parent = map

	local proto = (map and MapPass.RockStock(map)) or MapRidge.Stock()

	-- ===== THE RAMPART, BOTH GATES (33.4) =====
	-- Its own Random, off its own seed: rule 4 says the same draw on every server, and a shared
	-- generator would mean adding a rampart silently re-rolls every flank below it.
	local ramparts, rWhy = 0, {}
	if proto then
		local rrng = Random.new(RAMPART_SEED + math.floor(cx))
		for _, sign in ipairs({ -1, 1 }) do
			local n, target, why = rampart(dress, proto, rrng, zoneModel, sign)
			ramparts += n
			rWhy[#rWhy + 1] = ("%s %d crags to y %.0f (%s)")
				:format(sign < 0 and "-Z" or "+Z", n, target, why)
		end
	end

	local dressed = 0
	if proto and sheet then
		local rng = Random.new(SEED + math.floor(cx))
		local gz = sheet.Position.Z

		for i = 1, FLANK_COUNT do
			local side = (i % 2 == 0) and 1 or -1
			local t = math.floor((i - 1) / 2) / (FLANK_COUNT / 2 - 1)
			local m = proto:Clone()
			local _, raw = m:GetBoundingBox()
			if raw.Y >= 1 then
				m:ScaleTo(rng:NextNumber(FLANK_H_MIN, FLANK_H_MAX) / raw.Y)
				-- Scale, turn, RE-MEASURE, move -- a rotated model is a different box
				-- (MapHorizon.hill's standing note).
				m:PivotTo(CFrame.new(m:GetPivot().Position)
					* CFrame.Angles(0, math.pi / 2 + rng:NextNumber(-0.25, 0.25), 0))
				local cf, sz = m:GetBoundingBox()
				-- near pair hugs the arch, far pair walks out toward the rampart's keep-clear
				local x = side * (FLANK_X_MIN + t * (FLANK_X_MAX - FLANK_X_MIN) + rng:NextNumber(-6, 6))
				local z = gz + rng:NextNumber(-FLANK_Z_JITTER, FLANK_Z_JITTER)
				m:PivotTo(m:GetPivot() + Vector3.new(x - cf.Position.X,
					-(cf.Position.Y - sz.Y / 2) - SINK, z - cf.Position.Z))
				for _, d in ipairs(m:GetDescendants()) do
					if d:IsA("BasePart") then
						d.Anchored = true
						d.CanCollide = true
						d.CanQuery = true
						d.CastShadow = false
					end
				end
				m.Name = "GateFlank"
				keepClearOfLane(m, side)
				m.Parent = dress
				dressed += 1
			else
				m:Destroy()
			end
		end

		for i = 1, BACK_COUNT do
			local side = (i % 2 == 0) and 1 or -1
			local m = proto:Clone()
			local _, raw = m:GetBoundingBox()
			if raw.Y >= 1 then
				m:ScaleTo(rng:NextNumber(BACK_H_MIN, BACK_H_MAX) / raw.Y)
				m:PivotTo(CFrame.new(m:GetPivot().Position)
					* CFrame.Angles(0, math.pi / 2 + rng:NextNumber(-0.25, 0.25), 0))
				local cf, sz = m:GetBoundingBox()
				local x = side * rng:NextNumber(BACK_X_MIN, BACK_X_MAX)
				local z = rng:NextNumber(BACK_Z_MIN, BACK_Z_MAX)
				m:PivotTo(m:GetPivot() + Vector3.new(x - cf.Position.X,
					-(cf.Position.Y - sz.Y / 2), z - cf.Position.Z))
				for _, d in ipairs(m:GetDescendants()) do
					if d:IsA("BasePart") then
						d.Anchored = true
						d.CanCollide = true
						d.CanQuery = true
						d.CastShadow = false
					end
				end
				m.Name = "GateBackfill"
				keepBehindWall(m, gz)
				m.Parent = dress
				dressed += 1
			else
				m:Destroy()
			end
		end
	end

	-- The rampart half of this line carries the TARGET TOP and the sight line's demand beside the
	-- count, because a count alone cannot tell a rampart that is too short from one that is missing
	-- -- which is precisely how a 210-stud shoulder shipped behind a 180-stud wall (`MapPassDress`).
	print(("[MapGateFlanks] %s: dressed %d crags against the wall at z %s "
		.. "(%d flanks %d..%d tall a side-step of the arch, %d back-fill %d..%d tall in the slot); "
		.. "rampart %d crags over the wall's %d -- %s")
		:format(zoneKey, dressed, sheet and ("%.0f"):format(sheet.Position.Z) or "no arch",
			FLANK_COUNT, FLANK_H_MIN, FLANK_H_MAX, BACK_COUNT, BACK_H_MIN, BACK_H_MAX,
			ramparts, WALL.h, table.concat(rWhy, " | ")))
	return dressed + ramparts
end

return MapGateFlanks
