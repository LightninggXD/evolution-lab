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

local SEED = 20260826

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

function MapGateFlanks.Init(zoneKey, cx, map)
	local zones = workspace:FindFirstChild("Zones")
	local zoneModel = zones and zones:FindFirstChild(zoneKey)
	local sheet = zoneModel and MapGateArch.FindSheet(zoneModel)
	if not sheet then
		warn(("[MapGateFlanks] %s: no PortalGate to dress against -- skipped"):format(zoneKey))
		return 0
	end

	local old = map and map:FindFirstChild(DRESS_FOLDER)
	if old then old:Destroy() end
	local dress = Instance.new("Folder")
	dress.Name = DRESS_FOLDER
	dress.Parent = map

	local proto = (map and MapPass.RockStock(map)) or MapRidge.Stock()
	local dressed = 0
	if proto then
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

	print(("[MapGateFlanks] %s: dressed %d crags against the wall at z %.0f "
		.. "(%d flanks %d..%d tall a side-step of the arch, %d back-fill %d..%d tall in the slot)")
		:format(zoneKey, dressed, sheet.Position.Z, FLANK_COUNT, FLANK_H_MIN, FLANK_H_MAX,
			BACK_COUNT, BACK_H_MIN, BACK_H_MAX))
	return dressed
end

return MapGateFlanks
