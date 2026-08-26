-- ===== THE WATERFALL SITS ON THE MOUNTAIN WALL, AND THERE IS A GROTTO UNDER IT =====
--
-- The owner, 2026-08-25: *"treba napraviti secret mesto ispod vodopada ali vodopad mora biti sa
-- neke strane zida kod planina da se uklopi"*. Two halves, and this file is both.
--
-- 👤 WHY THIS IS CODE AND NOT A DRAG IN STUDIO. `workspace.Decorations.Waterfall` is authored
-- scenery -- nothing in `src/` built it and nothing rebuilds it -- so moving it by hand *would*
-- stick. The trees would not: `MapForest.Plant` scatters 5,355 of them over the whole platform on
-- every boot, and the tower's new home is open forest floor. Hand-place it and the next rebuild
-- grows a wood straight through the cliff. The move and the cut have to happen together, in that
-- order, every boot -- which is exactly what `MapGates` does for its lanes.
--
-- ORDER: this runs LAST in `ForestMapService.Init`, after `MapForest.Plant` and `MapJungle.Build`.
-- A pass only ever knows the world that existed when it ran ([[evolution-lab-placement-search-ordering]]),
-- and the thing being cut is the wood, so the wood has to be standing first.

local MapWaterfall = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local MapHorizon = require(script.Parent.MapHorizon)

-- ===== WHERE THE TOWER GOES, AND HOW THE NUMBER WAS ARRIVED AT =====
--
-- Measured, not guessed. The tower is 234 wide, 301 deep and 322 tall, and it used to stand at
-- pivot (-33, 176, -151) -- i.e. in the OPEN, its foot on the village plaza, a grey slab with four
-- flat sides and nothing behind it. That is the complaint.
--
-- The far (-Z) side of the map is a mountain wall whose inner face was measured by casting outward
-- from r 340 at y 30 against the `HorizonHill` / `gora` set:
--
--     x    +133  +200  +260  +300  +340  +380  +420
--   wall z  -422  -422  -344  -348  -363  -369  -389    and from x 380 out the range's own rock
--                                                        already stands at ground level (y 300)
--
-- So the tower is seated at pivot X 282.5 / Z -335.5, giving x 173..407 and z -535..-234:
--
--  * its WEST flank stands in the open with the wall 100-odd studs behind it,
--  * its EAST flank runs into the range's rock at x 380, which is what makes it read as an outcrop
--    of the range rather than a box parked in front of one,
--  * the AABB's back edge is ~100 studs behind the last real part, so "z -535" seats the actual
--    rock at about -435, a dozen studs inside the wall face. Buried, not floating in front of it.
--
-- THE TWO NUMBERS THAT ARE NOT FREE, both measured against the built world:
--  * `NW`-side camp floor at (146, -258) r23 -- the first seating overlapped it and would have
--    buried a camp under the cliff. x moved +40 to clear it.
--  * camp floor at (300, -200) r23 -- z moved -15 so the tower's front edge (-234) clears the
--    disc's north lip (-223) by 11 studs. That camp now stands at the foot of the falls, which is
--    where you want a camp.
local ANCHOR_PIVOT = Vector3.new(282.475830078125, 176.14761352539062, -335.5041198730469)

-- The plan rectangle, zone-local. Used for the prop cut and for the boot line's numbers.
local FOOT_X1, FOOT_X2 = 173, 407
local FOOT_Z1, FOOT_Z2 = -535, -234

-- ===== THE GROTTO =====
--
-- There was no carving to do. The tower's mass starts well above the floor -- a 6x12x6 body box
-- swept over x 240..350 / z -290..-210 at y 8 reports **no tower rock at all**, only scattered
-- trees and hunt rocks -- so the space under the overhang is already walkable open ground, with
-- 119 studs of headroom before the lowest `Plunge` shelf. What it lacked was a reason to be there
-- and anything to make it read as a room.
--
-- So the grotto is five thin slabs (back, two sides, a low roof) around the secret, open on the
-- +Z face, i.e. towards the village and BEHIND the falling water. You walk through the curtain to
-- get in. It is deliberately small: a room you find, not a hall you cross.
local GROTTO_HALF_X = 22
local GROTTO_HALF_Z = 20
local GROTTO_H = 20          -- inside height, floor to roof underside
local GROTTO_T = 3           -- slab thickness
local GROTTO_CLEAR = 34      -- props are cut this far around the grotto centre

local FOLDER_NAME = "WaterfallGrotto"
local RIDGE_FOLDER = "WaterfallRidge"

-- ===== AND WHAT STANDS ON THE PLINTH =====
--
-- The owner, 2026-08-26: *"ubaci nesto na postament u pecini iza vodopada"* -- 33.18 left the
-- pedestal deliberately bare because what goes on it is a decision about the GAME, not about the
-- room, and the game had already made it: `GameConfig.Secrets` has exactly one entry, this one,
-- and it pays `rewardType = "mutation", rewardName = "Godly"`. So the thing on the plinth is not
-- decoration chosen for the cave -- it is the reward, drawn.
--
-- THE COLOUR IS NOT PICKED, IT IS READ. `GameConfig.Mutations` gives Godly `color =
-- Color3.fromRGB(255, 240, 150)` (Upgrades.lua:81, index 7 of 7, weight 1), and that is the aura
-- that lands on the player's own body two seconds after they touch it. A relic in some other
-- colour would be the one prop in the game that promises the wrong prize.
--
-- WHY IT IS LIT GOLD IN A BLUE ROOM. The brow light 33.18 hung under the roof is pale blue at
-- brightness 2.2 / range 46, which in a 44 x 40 room is enough to be the brightest thing in it.
-- A gold relic under a strong blue key reads grey-green -- the same defect as
-- [[evolution-lab-world-look-pass]], one room down: the light, not the paint. So the brow drops to
-- 1.5 / 40 and stays the ROOM light, and the relic carries its own key. Two sources, two jobs.
--
-- EVERY PIECE OF IT IS `CanCollide = false`, AND THAT IS A CONSTRAINT, NOT A STYLE. The secret's
-- trigger stands at (291, 6, -290) with a 12-stud box, and `SecretsService.reportBlocked` asks
-- whether a 4 x 6 x 4 HUMANOID box at that centre overlaps any *collidable* part -- y 3..9, i.e.
-- exactly the air the relic floats in. One solid prop here and the service warns the secret is
-- unreachable on every boot, and the player walks through a shrine that pays nothing.
local RELIC_GOLD = Color3.fromRGB(255, 240, 150)   -- Godly, straight out of GameConfig.Mutations
local PLINTH_TOP = 3                               -- the plinth is 3 studs of cylinder on the floor
local RELIC_Y = PLINTH_TOP + 4                     -- the gem floats 4 studs clear of the stone
local RELIC_OFFSET = Vector3.new(0, 0, -4)         -- the plinth's own offset; the shrine is one stack

-- ===== THE TOWER STOOD ALONE IN THE OPEN, AND THAT IS THE SECOND HALF OF THE ASK =====
--
-- The owner, 2026-08-26, on a screenshot of the falls from the west: *"od ovog vodopada treba da mi
-- napravis tajni prolaz znaci stavi dodatne ploce da povezes vodopad sa zidom pa te strane sakrij
-- drvecem i planinama, a ispod vodopada kad se prodje neka bude neka pecina"*.
--
-- MEASURED IN THE BUILT WORLD (Edit, stamp 138, by raycast out of the tower's own footprint):
-- behind the tower there is **no rock at all** -- a ray from z -415 at y 30, 90 and 180, at five
-- values of x, hits `WorldShell.Wall` at **158 studs** every time and nothing before it. The
-- horizon range is clamped short of this bearing (the boot line says so: *CLAMPED AT THE WALL:
-- north -46 (NW4)*), so the only thing behind the falls is the flat boundary plate. West of the
-- tower a sideways ray finds nothing at all; east it finds a `HorizonHillCollider` 84 studs out.
-- That is exactly the complaint: a 320-stud cliff parked on open forest floor with the bare wall
-- behind it.
--
-- So three things are built here, and each one is a different half of "hide it":
--   * a RIDGE of rock plates from the tower's own back face to the wall, stepping down 300 -> 185
--     so it lands on the wall's measured 180-stud top rather than ending in the air,
--   * MOUNTAINS down both flanks, from the horizon's own mesh stock so they are the same rock the
--     rest of the skyline is made of, and TREES at their feet,
--   * and the cave, which was already here and did not read as one.
--
-- Every number below is measured off the model, not chosen: the tower's parts span x 194..392,
-- z -411..-247, y 6..328, and its biggest slab is Slate (120, 144, 130).
local TOWER_X1, TOWER_X2 = 194, 392
local TOWER_Z_BACK = -400          -- the plates start INSIDE the tower's back face (-411), so the
                                   -- join is buried in rock rather than butted against it
local WALL_Z = -575                -- WorldShell.Wall's inner face
local WALL_TOP = 180               -- and its height, which is what the last plate has to reach
local ROCK = Color3.fromRGB(120, 144, 130)

-- The plates, back to front: {z, depth, top, x1, x2}.
--
-- EVERY ROW STAYS INSIDE THE TOWER'S OWN x SPAN (194..392), AND THAT IS THE SECOND THING THE FIRST
-- CUT GOT WRONG. They flared outward -- 160..428 by the last row -- on the theory that a ridge
-- should widen into the range. From the village that reads as a flat grey slab poking out from
-- behind the cliff at mid height, because the tower is the only thing meant to have a silhouette
-- here: the ridge is a CONNECTOR and its job is to be invisible from the front and solid from
-- above. The flare is the crags' job instead, and they are rock-shaped.
local RIDGE_ROWS = {
	{ z = -420, d = 46, top = 300, x1 = 206, x2 = 380 },
	{ z = -458, d = 40, top = 268, x1 = 202, x2 = 384 },
	{ z = -494, d = 40, top = 236, x1 = 200, x2 = 386 },
	{ z = -530, d = 40, top = 208, x1 = 198, x2 = 388 },
	{ z = -562, d = 34, top = 186, x1 = 198, x2 = 388 },
}
local RIDGE_SEED = 20260826

-- ===== THE FLANKS ARE TWO SCALES, AND THE FIRST CUT GOT THAT WRONG =====
-- One run of full-size mountains at x 148 / 440 was the first attempt and it BURIED THE CAVE: the
-- horizon stock is 160 x 114 x 207 and a hill scaled to 180 studs tall is ~325 across, so a centre
-- line 148 studs out reaches x 311 -- straight over the mouth. A body-box march up the approach
-- found `FlankHill` on every sample from z -140 to -290. Measured, not guessed at again:
--
--   * RANGE, four a side, out at x 40 / 550 and only from z -400 back. They are the thing you see
--     ABOVE the ridge from the village, so they have to be big and they have to be far.
--   * CRAGS, six a side, hugging the plate edges at x 150 / 440 at 40..82 studs. These are what
--     actually hides the seam, and at that size they fit beside the ridge instead of on it.
--   * and a KEEP-OUT that both are tested against, so no future scale change can wall the cave in
--     again -- the corridor in front of the mouth is stated here rather than left to arithmetic.
-- x 40 / 550 was the second cut and it left the fault the row was opened on: a ray out of the
-- village camera at yaw +16 hits `WorldShell.Wall` at (115, 96, -573) -- BARE BOUNDARY PLATE,
-- between the tower's west edge (194) and the first western mountain (136). The range has to stand
-- IN that gap, so it comes in to 130 / 460 and starts far enough back that the keep-out lets it.
local RANGE_X_WEST, RANGE_X_EAST = 130, 460
local RANGE_Z_NEAR, RANGE_Z_FAR = -430, -565
local RANGE_PER_SIDE = 4
local RANGE_H_MIN, RANGE_H_MAX = 150, 245

local CRAG_X_WEST, CRAG_X_EAST = 150, 440
local CRAG_Z_NEAR, CRAG_Z_FAR = -300, -560
local CRAG_PER_SIDE = 6
local CRAG_H_MIN, CRAG_H_MAX = 40, 82

local FLANK_SINK = 12
local FLANK_TREES = 26             -- cloned out of the wood this map already planted

-- Nothing this file raises may stand in here. It is the tower's own span plus a margin, from the
-- back of the rock to well out in front of the mouth -- i.e. the walk from the village, through
-- the falls, into the room.
local KEEP_X1, KEEP_X2 = TOWER_X1 - 14, TOWER_X2 + 14
-- -320 and not -400: the room's back wall is at z -310, so anything that stops short of -320 is
-- BEHIND the cave and cannot block it. The first cut protected as far back as -400, which is inside
-- the tower's own rock -- and that is what destroyed five of the eight range hills for standing in
-- a corridor nobody walks.
local KEEP_Z1, KEEP_Z2 = -320, -60

-- ===== THE WATER HAD TO REACH THE GROUND =====
-- The model's own falls are five Beams and four emitters on transparent `Plunge` pads, and the
-- LOWEST pad sits at (291, 29, -260) -- i.e. the water stops **29 studs in the air**, over the very
-- spot the cave mouth opens onto. You cannot walk through a curtain that ends above your head, so
-- the last drop is built here: a sheet from the pad down to the floor and a pool under it, with the
-- pad's own ParticleEmitter cloned onto the pool so the spray at the bottom is the same spray as
-- the one at the top.
local SPLASH = Vector3.new(291, 29, -260)
-- 40 and not 60, at 0.58 and not 0.42: the first sheet was as wide as the splash pad and half
-- opaque, which from two studs in front of it is a blue glass wall with a cave behind it rather
-- than water you walk through. It has to be narrower than the gap in the cliff and thin enough to
-- read the mouth through.
local CURTAIN_W = 40
local CURTAIN_TRANSPARENCY = 0.58
local WATER = Color3.fromRGB(198, 234, 255)

-- ===== MOVING 1,102 ANCHORED PARTS IS ONE CALL, AND IT MUST BE IDEMPOTENT =====
-- `Init` runs once per server, but a hot reload or a future rebuild hook must not walk the tower
-- 234 studs further east each time. `PivotTo` an ABSOLUTE pivot rather than adding a delta: run it
-- three times and the tower is in the same place three times.
function MapWaterfall.Seat(cx)
	local dec = workspace:FindFirstChild("Decorations")
	local wf = dec and dec:FindFirstChild("Waterfall")
	if not wf or not wf:IsA("Model") then return nil end

	local target = ANCHOR_PIVOT + Vector3.new(cx, 0, 0)
	local pivot = wf:GetPivot()
	wf:PivotTo(CFrame.new(target) * (pivot - pivot.Position))
	return wf
end

-- Does this prop stand inside the tower's rock? Not "is it in the rectangle" -- the rectangle also
-- contains the wood IN FRONT of the cliff, which is meant to be there and looks right. The test is
-- an actual overlap against the tower's own parts.
local function insideTheTower(prop, wf)
	local cf, size
	if prop:IsA("Model") then
		cf, size = prop:GetBoundingBox()
	elseif prop:IsA("BasePart") then
		cf, size = prop.CFrame, prop.Size
	end
	if not cf then return false end
	for _, q in ipairs(workspace:GetPartBoundsInBox(cf, size)) do
		if q:IsDescendantOf(wf) then return true end
	end
	return false
end

-- ===== THE RIDGE, THE FLANKS AND THE WOOD ON THEM =====
-- One folder, destroyed and rebuilt, for the reason `Seat` is idempotent: `Init` runs once per
-- server but a rebuild hook must not stack a second range on the first.
local function buildRidge(zoneKey, cx, map)
	local old = map:FindFirstChild(RIDGE_FOLDER)
	if old then old:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = RIDGE_FOLDER
	folder.Parent = map

	local rng = Random.new(RIDGE_SEED + math.floor(cx))
	local plates = 0

	-- THE PLATES. Three across each row rather than one, with the top jittered per plate: a single
	-- slab per row reads as a wall built by somebody, and the thing this has to read as is rock.
	for _, row in ipairs(RIDGE_ROWS) do
		local span = row.x2 - row.x1
		for i = 1, 3 do
			local w = span / 3
			local x = row.x1 + w * (i - 0.5)
			local top = row.top + rng:NextNumber(-14, 14)
			local p = Instance.new("Part")
			p.Name = "RidgePlate"
			p.Anchored = true
			p.CanCollide = true
			p.CastShadow = false
			p.Material = Enum.Material.Slate
			p.Color = ROCK:Lerp(Color3.new(0, 0, 0), (i % 2) * 0.06)
			-- sunk 6 studs so the plate meets the ground rather than standing on it, and yawed a
			-- little so the run is not three parallel boxes
			p.Size = Vector3.new(w + 8, top + 6, row.d)
			p.CFrame = CFrame.new(cx + x, (top + 6) / 2 - 6, row.z)
				* CFrame.Angles(0, rng:NextNumber(-0.06, 0.06), 0)
			p.Parent = folder
			plates += 1
		end
	end

	-- THE MOUNTAINS AND THE CRAGS. The horizon's own stock, so the flank is the same rock as the
	-- skyline behind it -- `MapPassDress` seats the pass crags out of the same prototype for the
	-- same reason. The order is scale, turn, RE-MEASURE, move: a rotated model is another box
	-- ([[roblox-model-facing-and-scaling]]), and that measure is what the keep-out is tested with.
	local proto = MapHorizon.Stock(map)
	local hills = 0
	local function seat(rng, name, x, z, hMin, hMax, side)
		local m = proto:Clone()
		local _, raw = m:GetBoundingBox()
		if raw.Y < 1 then m:Destroy() return false end
		m:ScaleTo((rng:NextNumber(hMin, hMax) + FLANK_SINK) / raw.Y)
		m:PivotTo(CFrame.new(m:GetPivot().Position)
			* CFrame.Angles(0, math.pi / 2 + rng:NextNumber(-0.25, 0.25), 0))
		local cf, sz = m:GetBoundingBox()
		m:PivotTo(m:GetPivot() + Vector3.new(x - cf.Position.X,
			-(cf.Position.Y - sz.Y / 2) - FLANK_SINK, z - cf.Position.Z))

		-- THE KEEP-OUT, measured off the placed model and not off the number it was asked for.
		-- Pushed straight out along x first, and dropped entirely if that cannot clear it: a hill
		-- standing in the doorway is worse than one hill fewer in the line.
		local rx, rz, _, wx, wz = MapHorizon.WorldBox(m)
		if rx then
			local overZ = (wz - rz) < KEEP_Z2 and (wz + rz) > KEEP_Z1
			if overZ then
				local spill = side > 0
					and math.max(0, (cx + KEEP_X2) - (wx - rx))
					or math.max(0, (wx + rx) - (cx + KEEP_X1))
				if spill > 0 then
					m:PivotTo(m:GetPivot() + Vector3.new(side * spill, 0, 0))
					local nrx, _, _, nwx = MapHorizon.WorldBox(m)
					local clear = nrx and ((side > 0 and (nwx - nrx) >= cx + KEEP_X2)
						or (side < 0 and (nwx + nrx) <= cx + KEEP_X1))
					if not clear then m:Destroy() return false end
				end
			end
		end

		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = true
				d.CanQuery = true
				d.CastShadow = false
			end
		end
		m.Name = name
		m.Parent = folder
		return true
	end

	if proto then
		local hrng = Random.new(RIDGE_SEED + 7 + math.floor(cx))
		for _, run in ipairs({
			{ x = RANGE_X_WEST, side = -1, n = RANGE_PER_SIDE, z1 = RANGE_Z_NEAR, z2 = RANGE_Z_FAR,
			  hMin = RANGE_H_MIN, hMax = RANGE_H_MAX, name = "FlankHill" },
			{ x = RANGE_X_EAST, side = 1, n = RANGE_PER_SIDE, z1 = RANGE_Z_NEAR, z2 = RANGE_Z_FAR,
			  hMin = RANGE_H_MIN, hMax = RANGE_H_MAX, name = "FlankHill" },
			{ x = CRAG_X_WEST, side = -1, n = CRAG_PER_SIDE, z1 = CRAG_Z_NEAR, z2 = CRAG_Z_FAR,
			  hMin = CRAG_H_MIN, hMax = CRAG_H_MAX, name = "FlankCrag" },
			{ x = CRAG_X_EAST, side = 1, n = CRAG_PER_SIDE, z1 = CRAG_Z_NEAR, z2 = CRAG_Z_FAR,
			  hMin = CRAG_H_MIN, hMax = CRAG_H_MAX, name = "FlankCrag" },
		}) do
			for i = 1, run.n do
				local t = (i - 1) / math.max(1, run.n - 1)
				local z = run.z1 + t * (run.z2 - run.z1) + hrng:NextNumber(-14, 14)
				local x = cx + run.x + hrng:NextNumber(-16, 16)
				if seat(hrng, run.name, x, z, run.hMin, run.hMax, run.side) then hills += 1 end
			end
		end
	end

	-- THE WOOD ON THEM. Cloned out of the trees this map has already planted rather than built:
	-- `MapForest.Plant` runs before this pass, so the right prototypes -- this zone's, at this
	-- zone's scale -- are already standing in the world and asking for them by name would be a
	-- second copy of a fact `MapForest` owns.
	local wood = map:FindFirstChild("HuntForest")
	local trees = 0
	if wood then
		local stock = {}
		for _, c in ipairs(wood:GetChildren()) do
			if c:IsA("Model") and #stock < 40 then
				local _, sz = c:GetBoundingBox()
				if sz.Y > 24 then stock[#stock + 1] = c end
			end
		end
		if #stock > 0 then
			local trng = Random.new(RIDGE_SEED + 13 + math.floor(cx))
			for i = 1, FLANK_TREES do
				local side = (i % 2 == 0) and CRAG_X_EAST or CRAG_X_WEST
				local t = trng:NextNumber(0, 1)
				local z = CRAG_Z_NEAR + t * (CRAG_Z_FAR - CRAG_Z_NEAR)
				-- pushed OUT of the corridor, never into it: a tree in the doorway is the same
				-- defect as a mountain in it, one scale down
				local x = cx + side + trng:NextNumber(-46, 46)
				x = (side > TOWER_X2) and math.max(x, cx + KEEP_X2 + 6) or math.min(x, cx + KEEP_X1 - 6)
				local c = stock[trng:NextInteger(1, #stock)]:Clone()
				local cf, sz = c:GetBoundingBox()
				c:PivotTo(c:GetPivot() + Vector3.new(x - cf.Position.X,
					-(cf.Position.Y - sz.Y / 2) - 1, z - cf.Position.Z))
				c.Name = "FlankTree"
				c.Parent = folder
				trees += 1
			end
		end
	end

	return plates, hills, trees
end

-- ===== THE LAST THIRTY STUDS OF THE FALL =====
-- See the note over `SPLASH`. Built into the grotto folder rather than the ridge one because it
-- belongs to the cave: it is the door.
local function buildCurtain(folder, cx, wf)
	local base = Vector3.new(cx + SPLASH.X, 0, SPLASH.Z)

	local sheet = Instance.new("Part")
	sheet.Name = "FallCurtain"
	sheet.Anchored = true
	sheet.CanCollide = false   -- you walk THROUGH it; that is the whole point of the room behind it
	sheet.CanQuery = false
	sheet.CastShadow = false
	sheet.Material = Enum.Material.Glass
	sheet.Color = WATER
	sheet.Transparency = CURTAIN_TRANSPARENCY
	sheet.Reflectance = 0.12
	sheet.Size = Vector3.new(CURTAIN_W, SPLASH.Y + 1, 2.2)
	sheet.Position = base + Vector3.new(0, (SPLASH.Y + 1) / 2, 0)
	sheet.Parent = folder

	local pool = Instance.new("Part")
	pool.Name = "FallPool"
	pool.Anchored = true
	pool.CanCollide = false
	pool.CanQuery = false
	pool.CastShadow = false
	pool.Shape = Enum.PartType.Cylinder
	pool.Material = Enum.Material.Glass
	pool.Color = WATER
	pool.Transparency = 0.35
	pool.Reflectance = 0.2
	pool.Size = Vector3.new(1.2, CURTAIN_W + 10, CURTAIN_W + 10)
	pool.CFrame = CFrame.new(base + Vector3.new(0, 0.6, 4)) * CFrame.Angles(0, 0, math.pi / 2)
	pool.Parent = folder

	-- the spray at the bottom is the model's OWN spray: the lowest `Plunge` pad already carries the
	-- emitter this fall was authored with, and a second one written by hand here would be a
	-- different waterfall from the waist down
	local lowest
	for _, d in ipairs(wf:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "Plunge" and (not lowest or d.Position.Y < lowest.Position.Y) then
			lowest = d
		end
	end
	local emitter = lowest and lowest:FindFirstChildWhichIsA("ParticleEmitter")
	if emitter then
		local e = emitter:Clone()
		e.Parent = pool
	end
	return 2
end

-- ===== THE SHRINE ON THE PLINTH =====
--
-- ENDLESS MOTION WITH NO PER-FRAME LUA, AND A LOCAL COPY OF THE TRICK RATHER THAN `ZoneKit`'S.
-- The kit's `spinForever` / `pulseForever` multiply their goal by `ACTIVE_FRAME`, the module-level
-- placement frame the last zone build happened to leave behind -- that leak is the whole of row
-- 33.17, where it took the eggs apart. Nothing in this file is frame-placed (every prop here takes
-- a raw world `Position`), so the tween goals have to be raw too, and borrowing the kit's versions
-- would teleport the shrine to wherever the frame last pointed on its very first tick.
--
-- A repeating tween snaps back to its start value at the end of every cycle. That is invisible
-- ONLY when the cycle covers exactly one step of the arrangement's ROTATIONAL SYMMETRY, which is
-- why both numbers below are derived from the shape rather than chosen: the gem turns 120 degrees
-- because a cube stood on its corner has a three-fold axis up the body diagonal, and the ring of
-- stones turns 360/8 because there are eight of them.
local function turnForever(part, poseAt, startDeg, stepDeg, seconds)
	part.CFrame = poseAt(startDeg)
	TweenService:Create(part, TweenInfo.new(seconds, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
		CFrame = poseAt(startDeg + stepDeg),
	}):Play()
end

-- Stands a cube on its corner EXACTLY. `CFrame.Angles(45, 35, 0)` gets close enough to look right
-- and is not close enough to spin right: the 120-degree tween only lands on an identical pose if
-- the cube's (1,1,1) diagonal is exactly vertical, and a degree of error shows up as a visible
-- twitch once a second, forever. Rotating (1,1,1) onto +Y about their common perpendicular is the
-- closed form, and `acos(1/sqrt(3))` is the angle between them.
local CORNER_UP = CFrame.fromAxisAngle(Vector3.new(1, 0, -1).Unit, math.acos(1 / math.sqrt(3)))

local GEM_SIZE = 5
local STONE_COUNT = 8
local STONE_RADIUS = 5.8

-- `base` is the grotto's floor-level centre and `reward` is the secret's own `rewardName`, so the
-- shrine is built from what the secret PAYS rather than from a second copy of that decision.
local function buildRelic(folder, base, reward)
	local built = 0
	local centre = base + RELIC_OFFSET
	local heart = centre + Vector3.new(0, RELIC_Y, 0)

	local function newPart(props)
		local part = Instance.new("Part")
		part.Anchored = true
		-- read the comment block over RELIC_GOLD before changing either of these two
		part.CanCollide = false
		part.CanQuery = false
		part.CastShadow = false
		for k, v in pairs(props) do
			part[k] = v
		end
		part.Parent = folder
		built += 1
		return part
	end

	-- THE GEM IS ONE SHAPE, AND THE FIRST CUT OF THIS SHRINE WAS FIVE. That version stacked a
	-- 23-stud floor disc, a pedestal disc, a floor-to-roof shaft and a ball, all Neon and all
	-- part-transparent, and photographed as a lime pancake under an olive pillar --
	-- [[evolution-lab-chunky-look-rules]] rule 3 in both of its clauses at once: *a Cylinder is
	-- solid, so a halo made from one is a dinner plate*, and *fewer, bigger shapes beats more
	-- detail*. What is left is a single bright mass with dark trim at its extremities, which is
	-- the vocabulary the village crates and lamps are already built in.
	--
	-- AND THE GOLD IS DEEPER THAN THE AURA'S. Neon is unlit, so a part painted the mutation's own
	-- rgb(255, 240, 150) draws at very nearly full white and the relic photographs as a bare bulb.
	-- The gem is the same hue two steps down in value; the aura around it, which IS drawn at the
	-- mutation's colour, is what carries the exact promise.
	local gem = newPart({
		Name = "RelicGem",
		Size = Vector3.new(GEM_SIZE, GEM_SIZE, GEM_SIZE),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 196, 64),
	})
	turnForever(gem, function(deg)
		return CFrame.new(heart) * CFrame.Angles(0, math.rad(deg), 0) * CORNER_UP
	end, 0, 120, 9)

	-- Its own key light, and the ROOM's is not it -- see the note over RELIC_GOLD. Range 36 covers
	-- the 44 x 40 floor and dies before the doorway, so the cave still goes dark towards the mouth
	-- and the shrine is the bright end of it.
	local key = Instance.new("PointLight")
	key.Color = RELIC_GOLD
	key.Brightness = 2.8
	key.Range = 36
	-- NO SHADOWS, and that is not a performance note. A point light two studs above a 12-stud
	-- pedestal in a closed 44 x 40 room projects that pedestal onto the back wall at 2.5x, and it
	-- photographs as a dark grey trapezoid hanging in the air behind the shrine -- read as a
	-- floating slab in three captures before it was traced. Nothing in this room is lit well
	-- enough for a cast shadow to add anything.
	key.Shadows = false
	key.Parent = gem

	-- THE RING IS EIGHT BLOCKS, NOT A CYLINDER, for the reason in the memory named above: a ring
	-- built from a Cylinder is a plate. They are dark on purpose -- an outline is a boundary
	-- between two VALUES, and scenery cannot carry a `Highlight` (Roblox draws ~31 at once and
	-- they are spent on characters and pets), so the dark trim at the extremities is how a prop
	-- here gets an edge at all.
	for i = 0, STONE_COUNT - 1 do
		local stone = newPart({
			Name = "RelicStone",
			Size = Vector3.new(1.15, 1.7, 1.15),
			Material = Enum.Material.Slate,
			Color = Color3.fromRGB(58, 64, 70),
		})
		turnForever(stone, function(deg)
			return CFrame.new(heart) * CFrame.Angles(0, math.rad(deg), 0) * CFrame.new(STONE_RADIUS, 0, 0)
		end, i * (360 / STONE_COUNT), 360 / STONE_COUNT, 11)
	end

	-- ===== AND THE AURA IS THE REWARD ITSELF, NOT A COSTUME FOR IT =====
	--
	-- `EvolutionVisuals`' own `MUTATION_VFX` already says what Godly looks like -- `Big/Tornado-01` at
	-- rate 30, span 11, tinted rgb(255, 240, 150) -- and it is the table that dresses the PLAYER
	-- two seconds after they touch the trigger. Hanging the same aura on the relic means the cave
	-- shows the prize and the body wears the prize from ONE definition; a hand-written emitter
	-- here would be a second writer, and the day someone re-tunes Godly the shrine would quietly
	-- start promising the wrong thing.
	--
	-- REQUIRED LAZILY, INSIDE THE BUILD. `EvolutionVisuals` pulls in `PlayerDataService` and the
	-- sword models; a top-level require would put all of that behind a map-prop module that
	-- `ForestMapService` loads while the world is still being laid out. This runs once, at the end
	-- of the Forest map pass, long after those services are up.
	--
	-- AND IT HANGS ON ITS OWN ANCHOR, NOT ON THE GEM OR THE PLINTH. `Attachment.Position` is in
	-- the PARENT's frame: the gem turns, and the plinth is a Cylinder rolled 90 degrees about Z so
	-- its local Y points along world X -- an offset written there goes sideways
	-- ([[evolution-lab-vfx-attach-rules]]). An unrotated 1-stud part costs nothing and cannot lie.
	local anchor = newPart({
		Name = "RelicAnchor",
		Size = Vector3.new(1, 1, 1),
		Transparency = 1,
		-- AT THE STONE, NOT AT THE GEM. `Big/Tornado-01` throws its particles UPWARD from the
		-- attachment over about eleven studs, so an anchor level with the gem puts the whole
		-- vortex above it and the ribbons read as rings around the ceiling lamp -- photographed
		-- exactly that way in Play before this line moved. Starting it at the plinth's face wraps
		-- the gem instead, which is what a relic standing in a column of wind looks like.
		Position = centre + Vector3.new(0, PLINTH_TOP + 0.2, 0),
	})
	local okAura, aura = pcall(function()
		local EvolutionVisuals = require(script.Parent.Parent.Systems.EvolutionVisuals)
		return EvolutionVisuals.AttachMutationAura(anchor, reward, 1)
	end)
	if not (okAura and aura) then
		warn(("[MapWaterfall] the grotto relic has no aura -- %q is not a mutation this build draws")
			:format(tostring(reward)))
	end

	return built
end

function MapWaterfall.Build(zoneKey, cx, map)
	if not map then return 0, 0, 0 end

	local wf = MapWaterfall.Seat(cx)
	if not wf then
		-- Not a warning worth a stack: a place without the scenery model simply has no waterfall,
		-- and everything else in the zone is unaffected.
		print(("[MapWaterfall] %s: no Decorations.Waterfall -- nothing seated"):format(zoneKey))
		return 0, 0, 0
	end

	local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

	-- ===== THE CUT =====
	local x1, x2 = cx + FOOT_X1, cx + FOOT_X2
	local z1, z2 = FOOT_Z1, FOOT_Z2
	local cut = 0
	for _, c in ipairs(map:GetChildren()) do
		if c.Name ~= "MainPart" and c.Name ~= "Terrain" then
			local ok, pos = pcall(function()
				return c:IsA("Model") and c:GetBoundingBox().Position or (c :: BasePart).Position
			end)
			if ok and pos and pos.X >= x1 and pos.X <= x2 and pos.Z >= z1 and pos.Z <= z2 then
				if insideTheTower(c, wf) then
					c:Destroy()
					cut += 1
				end
			end
		end
	end

	-- ===== THE RIDGE TO THE WALL, AND THE RANGE DOWN BOTH FLANKS =====
	-- Before the grotto and after the tower cut: the plates are rock, so the wood standing where
	-- they land has to come out the same way it does inside the tower. The cut runs over the rows
	-- rather than over one big rectangle -- the band between the flanks is meant to stay wooded,
	-- and that is what hides the join.
	local plates, hills, flankTrees = buildRidge(zoneKey, cx, map)
	local ridge = map:FindFirstChild(RIDGE_FOLDER)

	-- ===== AND THE CUT HAS TO REACH THE INVISIBLE PARTS TOO =====
	-- `map:GetChildren()` is the props. The COLLIDERS are one level down -- `HuntForest` holds
	-- `HuntTreeCollider` / `HuntRockCollider`, `Jungle` holds `JungleRockCollider` -- so a cut that
	-- only walks the top level leaves an invisible wall standing exactly where the rock now is, and
	-- inside the room. Measured on the first build of this pass: the approach to the mouth reported
	-- `HuntTreeCollider` at z -250 and -280 and `JungleRockCollider` at -210..-230, i.e. a doorway
	-- you cannot walk through and nothing on screen to say why ([[roblox-canquery-ignored-when-collides]]).
	local COLLIDER_SETS = { "HuntForest", "Jungle", "Horizon" }
	local function clearBox(x1, x2, z1, z2)
		local n = 0
		for _, c in ipairs(map:GetChildren()) do
			if c ~= ridge and c.Name ~= "MainPart" and c.Name ~= "Terrain" then
				local ok, pos = pcall(function()
					return c:IsA("Model") and c:GetBoundingBox().Position or (c :: BasePart).Position
				end)
				if ok and pos and pos.X >= x1 and pos.X <= x2 and pos.Z >= z1 and pos.Z <= z2 then
					c:Destroy()
					n += 1
				end
			end
		end
		for _, setName in ipairs(COLLIDER_SETS) do
			local set = map:FindFirstChild(setName)
			if set then
				for _, c in ipairs(set:GetChildren()) do
					local ok, pos = pcall(function()
						return c:IsA("Model") and c:GetBoundingBox().Position or (c :: BasePart).Position
					end)
					if ok and pos and pos.X >= x1 and pos.X <= x2 and pos.Z >= z1 and pos.Z <= z2 then
						c:Destroy()
						n += 1
					end
				end
			end
		end
		return n
	end

	-- ===== AND A SECOND CUT, BECAUSE `clearBox` ASKS THE WRONG QUESTION FOR THE ROOM =====
	--
	-- `clearBox` tests a prop's CENTRE. That is right for the ridge -- the plates are 174 studs
	-- wide and a prop centred outside them is outside them -- and it is wrong for a 44 x 40 room
	-- with 3-stud walls. Measured in Play, 2026-08-26: a `HuntForest.HuntTree` centred at
	-- (272, -329) has a 43.6-stud canopy reaching z -308, i.e. **two studs through the back wall
	-- and into the cave**, and its centre is five studs outside the cut box, so the cut left it
	-- standing. From the doorway it photographed as a dark grey trapezoid hanging in the air --
	-- traced through four captures before it was named, because it looks like a floating slab and
	-- nothing like a tree. This is the same defect 33.18 fixed for the colliders, one layer out:
	-- the colliders were the half you walk into, this is the half you look at.
	--
	-- THE SIZE GUARD IS NOT OPTIONAL. An extent test over this volume also matches the horizon
	-- range -- `Horizon.HorizonHill`'s stock measures 449 x 307 x 578, and once rotated its
	-- world AABB reaches this box from six hundred studs away -- so an unguarded version would
	-- delete a mountain to tidy a cave. Anything wider than the room in either horizontal axis is
	-- scenery the room stands INSIDE, not clutter standing in it. Trees here measure 24..57.
	local ROOM_MAX_SPAN = 90
	local function clearRoom(lo, hi)
		local n = 0
		-- Both getters are PIVOT-frame, so `size` is measured along the prop's OWN axes and has to
		-- be projected onto the world's before it can be compared with a world-axis box --
		-- [[roblox-model-box-getters-are-pivot-frame]]. A yawed prop whose size is used raw reads
		-- as the wrong shape entirely, and for a 43-stud canopy that is the whole answer.
		local function extentOf(c)
			local ok, cf, size = pcall(function()
				if c:IsA("Model") then return c:GetBoundingBox() end
				return (c :: BasePart).CFrame, (c :: BasePart).Size
			end)
			if not (ok and cf and size) then return nil end
			local e = Vector3.new(
				math.abs(cf.RightVector.X) * size.X + math.abs(cf.UpVector.X) * size.Y + math.abs(cf.LookVector.X) * size.Z,
				math.abs(cf.RightVector.Y) * size.X + math.abs(cf.UpVector.Y) * size.Y + math.abs(cf.LookVector.Y) * size.Z,
				math.abs(cf.RightVector.Z) * size.X + math.abs(cf.UpVector.Z) * size.Y + math.abs(cf.LookVector.Z) * size.Z) / 2
			return cf.Position, e
		end
		local function sweep(list)
			for _, c in ipairs(list) do
				if c ~= ridge and c.Name ~= "MainPart" and c.Name ~= "Terrain" and c.Name ~= FOLDER_NAME then
					local pos, e = extentOf(c)
					if pos and e and e.X * 2 <= ROOM_MAX_SPAN and e.Z * 2 <= ROOM_MAX_SPAN
						and pos.X + e.X > lo.X and pos.X - e.X < hi.X
						and pos.Y + e.Y > lo.Y and pos.Y - e.Y < hi.Y
						and pos.Z + e.Z > lo.Z and pos.Z - e.Z < hi.Z then
						c:Destroy()
						n += 1
					end
				end
			end
		end
		sweep(map:GetChildren())
		for _, setName in ipairs(COLLIDER_SETS) do
			local set = map:FindFirstChild(setName)
			if set then sweep(set:GetChildren()) end
		end
		return n
	end

	for _, row in ipairs(RIDGE_ROWS) do
		cut += clearBox(cx + row.x1 - 4, cx + row.x2 + 4,
			row.z - row.d / 2 - 2, row.z + row.d / 2 + 2)
	end

	-- ===== THE GROTTO, BUILT AROUND THE SECRET RATHER THAN BESIDE IT =====
	--
	-- ONE SOURCE OF TRUTH FOR THE PLACE. The room is built at the coordinates `GameConfig.Secrets`
	-- already names, so the cave and the trigger cannot drift apart -- which is the failure 32.26
	-- was: an offset edited in one file while the thing it described lived in another.
	local folder = map:FindFirstChild(FOLDER_NAME)
	if folder then folder:Destroy() end
	folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = map

	-- A NEUTRAL STONE, AND THE RELIC IS WHY IT CHANGED (33.19). It was rgb(120, 132, 140), a cool
	-- blue-grey, and a room lit by exactly two coloured lights renders a cool grey as whichever
	-- light is winning: under the blue brow the whole cave photographed BLUE, and the moment the
	-- gold key went in the floor came out GREEN. That is not a paint fault, it is the same
	-- diagnosis as [[evolution-lab-world-look-pass]] -- the light, not the paint -- and the fix is
	-- a stone with no cast of its own, so the blue reads blue and the gold reads gold.
	local rock = Color3.fromRGB(126, 122, 116)
	local built = 0
	for _, secret in ipairs(GameConfig.Secrets or {}) do
		if secret.zoneKey == zoneKey and secret.offset then
			local centre = Vector3.new(cx, 0, 0) + secret.offset

			-- Clear the room's own volume AND the walk up to it -- a tree standing in the middle
			-- of the grotto is the same defect as a tree in the cliff, one scale down, and an
			-- invisible collider across the doorway is that defect with nothing on screen to
			-- explain it. The box runs from the mouth out to the falls and 40 studs beyond, which
			-- is the corridor the player actually walks.
			cut += clearBox(centre.X - GROTTO_CLEAR, centre.X + GROTTO_CLEAR,
				centre.Z - GROTTO_CLEAR, SPLASH.Z + 40)

			-- and then the room's own volume by EXTENT -- see the note over `clearRoom`. The box
			-- is the walls plus two studs, which is what a prop has to reach to be seen from
			-- inside, and it runs the full height so a canopy overhead is caught with a trunk.
			local roomHalfX = GROTTO_HALF_X + GROTTO_T + 2
			local roomHalfZ = GROTTO_HALF_Z + GROTTO_T + 2
			cut += clearRoom(
				Vector3.new(centre.X - roomHalfX, -2, centre.Z - roomHalfZ),
				Vector3.new(centre.X + roomHalfX, GROTTO_H + GROTTO_T + 2, centre.Z + roomHalfZ))

			-- THE ROOM IS BUILT OFF THE GROUND, NOT OFF THE TRIGGER. The secret's own offset carries
			-- a Y because a 12-stud touch part centred on the floor is half buried in it; the walls
			-- have to start at the floor regardless, or the room stands on stilts by exactly that
			-- much. So the slabs take the trigger's X and Z and a Y of zero.
			local base = Vector3.new(centre.X, 0, centre.Z)
			local function slab(name, size, offset)
				local p = Instance.new("Part")
				p.Name = name
				p.Anchored = true
				p.CanCollide = true
				p.CastShadow = true
				p.Material = Enum.Material.Slate
				p.Color = rock
				p.Size = size
				p.Position = base + offset
				p.Parent = folder
				built += 1
			end

			local w = GROTTO_HALF_X * 2 + GROTTO_T * 2
			-- Open on +Z: that face is the doorway, and the falling water hangs in front of it.
			slab("GrottoBack", Vector3.new(w, GROTTO_H + GROTTO_T, GROTTO_T),
				Vector3.new(0, GROTTO_H / 2, -GROTTO_HALF_Z - GROTTO_T / 2))
			slab("GrottoSide", Vector3.new(GROTTO_T, GROTTO_H + GROTTO_T, GROTTO_HALF_Z * 2),
				Vector3.new(-GROTTO_HALF_X - GROTTO_T / 2, GROTTO_H / 2, 0))
			slab("GrottoSide", Vector3.new(GROTTO_T, GROTTO_H + GROTTO_T, GROTTO_HALF_Z * 2),
				Vector3.new(GROTTO_HALF_X + GROTTO_T / 2, GROTTO_H / 2, 0))
			slab("GrottoRoof", Vector3.new(w, GROTTO_T, GROTTO_HALF_Z * 2 + GROTTO_T),
				Vector3.new(0, GROTTO_H + GROTTO_T / 2, 0))
			-- A lip over the doorway, so from outside it reads as a mouth in the rock rather than
			-- a box with a missing wall.
			slab("GrottoLip", Vector3.new(w, 4, GROTTO_T),
				Vector3.new(0, GROTTO_H - 1, GROTTO_HALF_Z + GROTTO_T / 2))

			-- ===== AND THE FOUR THINGS THAT MAKE IT READ AS A CAVE (2026-08-26) =====
			-- The room was five slabs standing in the open under an overhang: correct geometry,
			-- and from outside a grey box with a wall missing. What was missing:
			--   * a FLOOR, so it is a room and not a patch of forest floor with a roof over it,
			--   * a MOUTH -- two rock jambs and a brow narrowing the opening to 22 studs, which is
			--     what turns a missing wall into a doorway,
			--   * LIGHT inside, or the room is black from the one angle it can be seen from, and
			--   * somewhere to put the thing she is going to put in it.
			-- THE CAVE HAD A GRASS FLOOR, AND THE SLAB WAS ALWAYS THERE (33.19). Measured:
			-- `WorldShell.Floor` is Grass with its top face at y = 0.00 and this slab was laid with
			-- its own top face at y = 0.00 -- two coplanar surfaces, so which one draws is decided
			-- by the camera angle. It photographed as a stone floor from one seat and as a green
			-- meadow inside a rock cave from the next ([[roblox-coplanar-paint-zfights]] is the
			-- standing note; the striped cliffs of 17.x were the same fault one scale up). 0.2
			-- studs of daylight settles it and is far under a step height, so the walk in is
			-- unchanged.
			slab("GrottoFloor", Vector3.new(w, GROTTO_T, GROTTO_HALF_Z * 2 + GROTTO_T),
				Vector3.new(0, -GROTTO_T / 2 + 0.2, 0))

			local jamb = (w - 22) / 2
			for _, side in ipairs({ -1, 1 }) do
				slab("GrottoJamb", Vector3.new(jamb, GROTTO_H - 3, GROTTO_T * 1.6),
					Vector3.new(side * (22 + jamb) / 2, (GROTTO_H - 3) / 2, GROTTO_HALF_Z + GROTTO_T / 2))
			end

			-- THE PEDESTAL. It was left bare by 33.18 -- *"tu cemo ubaciti nesto"* -- and 33.19
			-- filled it: see the comment block over `RELIC_GOLD` for what stands on it and why the
			-- colour was read out of `GameConfig` rather than chosen.
			local plinth = Instance.new("Part")
			plinth.Name = "GrottoPlinth"
			plinth.Anchored = true
			plinth.CanCollide = true
			plinth.Shape = Enum.PartType.Cylinder
			plinth.Size = Vector3.new(3, 12, 12)
			plinth.CFrame = CFrame.new(base + Vector3.new(0, 1.5, -4)) * CFrame.Angles(0, 0, math.pi / 2)
			plinth.CastShadow = false   -- see the note on the relic's key light
			plinth.Material = Enum.Material.Slate
			plinth.Color = rock:Lerp(Color3.new(0, 0, 0), 0.2)
			plinth.Parent = folder
			built += 1

			local glow = Instance.new("Part")
			glow.Name = "GrottoGlow"
			glow.Anchored = true
			glow.CanCollide = false
			glow.CanQuery = false
			glow.CastShadow = false
			glow.Shape = Enum.PartType.Ball
			glow.Size = Vector3.new(3, 3, 3)
			glow.Position = base + Vector3.new(0, GROTTO_H - 4, -2)
			glow.Material = Enum.Material.Neon
			glow.Color = Color3.fromRGB(150, 220, 255)
			glow.Transparency = 0.35
			glow.Parent = folder
			local lamp = Instance.new("PointLight")
			lamp.Color = Color3.fromRGB(150, 220, 255)
			-- DIMMED FROM 2.2 / 46 BY 33.19, and the relic is the reason. This is the ROOM light --
			-- its job is that the rock is not black -- and at its old strength it was also the
			-- brightest thing in the room, which put a cold blue key on a gold relic and turned it
			-- grey-green. Two sources, two jobs: blue fills, gold focuses.
			lamp.Brightness = 1.5
			lamp.Range = 40
			lamp.Parent = glow
			built += 1

			built += buildRelic(folder, base, secret.rewardName)

			-- the door: the last thirty studs of the fall, hanging in front of the mouth
			built += buildCurtain(folder, cx, wf)
		end
	end

	print(("[MapWaterfall] %s: tower seated at pivot (%.0f, %.0f, %.0f), cut %d props out of the cliff, "
		.. "the ridge and the grotto, built %d grotto parts, %d ridge plates z %d -> %d (tops %d -> %d "
		.. "against the wall's %d), %d flank hills and %d flank trees")
		:format(zoneKey, ANCHOR_PIVOT.X + cx, ANCHOR_PIVOT.Y, ANCHOR_PIVOT.Z, cut, built,
			plates, RIDGE_ROWS[1].z, RIDGE_ROWS[#RIDGE_ROWS].z, RIDGE_ROWS[1].top,
			RIDGE_ROWS[#RIDGE_ROWS].top, WALL_TOP, hills, flankTrees))
	return 1, cut, built
end

return MapWaterfall
