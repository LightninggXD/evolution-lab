-- 32.28 / board OX -- prove the portal pass is actually OPEN, in one paste.
--
-- Paste into Studio's command bar (edit or run), it returns a report string.
--
-- THREE CHECKS, because no single one can lie honestly here:
--   S1 GEOMETRY -- the authoritative hill check. The horizon hills' meshes are
--      `CanQuery = false` AND `CanCollide = false` (MapHorizon.hill sets both), so NO ray or
--      bounds query can see them at all -- a walk/ray probe alone would report CLEAR over a
--      mountain and call that proof. This check enumerates every `HorizonHill` model left in
--      the world whose body still meets the corridor (x gate.x +-100, z -660..-460) and lists
--      it by full path. Expected after MapPass.Cut: 0 offenders.
--   S2 WALK -- a body-sized box (her measured 9 x 8.4 x 7) stepped 4 studs up the lane from
--      the spawn to the gate, against everything that CAN collide. Box bottom held CLEAR above
--      the per-sample ground cast (`probe-body-box-counts-the-floor`); a hit counts as a wall
--      only if its top stands more than RISE above that ground, i.e. a kerb steps, a wall does
--      not.
--   S3 SIGHT -- one eye-height ray from the village to the door, printing what it hit by full
--      instance path -- the whole point of 32.28 is that this used to be a hill nobody
--      expected. With the hills invisible to rays, this answers "wall / collider / tree", and
--      S1 answers "hill"; read them together.
--
-- READ-ONLY: no Destroy, no property writes, no instance creation.

local BOX_W, BOX_H, BOX_L = 9, 8.4, 7    -- her measured body
local STEP = 4
local CLEAR = 1.0                        -- box bottom this far off the per-sample ground
local RISE = 3.0                         -- taller than this is a wall, shorter is a step
local EYE = 7                            -- eye height for the 8.4-stud body

local CORRIDOR_HALF_X = 100              -- 32.28's cut, verbatim: x +-100, z -660..-460
local CORRIDOR_Z_MIN, CORRIDOR_Z_MAX = -660, -460

local out = {}
local function p(s) out[#out + 1] = s end

local function topOf(part)
	local cf, sz = part.CFrame, part.Size
	return part.Position.Y + (math.abs(cf.RightVector.Y) * sz.X + math.abs(cf.UpVector.Y) * sz.Y
		+ math.abs(cf.LookVector.Y) * sz.Z) / 2
end

-- ===== locate the -Z gate and the spawn =====
local gx, gz, gy, gatePath = 0, -575, 69, "(fallback 0, 69, -575)"
for _, d in ipairs(workspace:GetDescendants()) do
	if d:IsA("Model") and d.Name:find("ZonePortal_", 1, true) then
		local cf = d:GetBoundingBox()
		if cf.Position.Z < gz then
			gx, gz, gy, gatePath = cf.Position.X, cf.Position.Z, cf.Position.Y,
				d:GetFullName()
		end
	end
end
local spawn = workspace:FindFirstChild("ForestSpawn")
	or workspace:FindFirstChildWhichIsA("SpawnLocation")
if not spawn then p("!! no ForestSpawn / SpawnLocation found -- cannot walk"); return table.concat(out, "\n") end
p(("gate %s at (%.1f, %.1f, %.1f)"):format(gatePath, gx, gy, gz))
p(("spawn %s at (%.1f, %.1f, %.1f)"):format(spawn.Name,
	spawn.Position.X, spawn.Position.Y, spawn.Position.Z))

-- ===== S1: who still meets the corridor =====
local offenders = 0
for _, d in ipairs(workspace:GetDescendants()) do
	if d:IsA("Model") and d.Name == "HorizonHill" then
		local mnx, mxx = math.huge, -math.huge
		local mnz, mxz = math.huge, -math.huge
		for _, q in ipairs(d:GetDescendants()) do
			if q:IsA("BasePart") then
				local c, sz, pp = q.CFrame, q.Size, q.Position
				local hx = (math.abs(c.RightVector.X) * sz.X + math.abs(c.UpVector.X) * sz.Y
					+ math.abs(c.LookVector.X) * sz.Z) / 2
				local hz = (math.abs(c.RightVector.Z) * sz.X + math.abs(c.UpVector.Z) * sz.Y
					+ math.abs(c.LookVector.Z) * sz.Z) / 2
				mnx, mxx = math.min(mnx, pp.X - hx), math.max(mxx, pp.X + hx)
				mnz, mxz = math.min(mnz, pp.Z - hz), math.max(mxz, pp.Z + hz)
			end
		end
		if mxx ~= -math.huge and mxx >= gx - CORRIDOR_HALF_X and mnx <= gx + CORRIDOR_HALF_X
			and mxz >= CORRIDOR_Z_MIN and mnz <= CORRIDOR_Z_MAX then
			offenders += 1
			p(("S1 OFFENDER: %s  box x %.0f..%.0f  z %.0f..%.0f")
				:format(d:GetFullName(), mnx, mxx, mnz, mxz))
		end
	end
end
p(("S1 corridor offenders remaining: %d %s"):format(offenders,
	offenders == 0 and "-- CLEAR" or "-- STILL WALLING THE PASS"))

-- ===== S2: the body walk =====
local rp = RaycastParams.new()
rp.IgnoreWater = true
local params = OverlapParams.new()
params.MaxParts = 200

local tx, tz = gx, gz + 10              -- stand-off one prompt-reach short of the door
local dx, dz = tx - spawn.Position.X, tz - spawn.Position.Z
local len = math.sqrt(dx * dx + dz * dz)
local ux, uz = dx / len, dz / len
local samples, blocked = 0, 0
local t = 0
while t <= len + 0.001 do
	local x, z = spawn.Position.X + ux * t, spawn.Position.Z + uz * t
	local hit = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -600, 0), rp)
	local gyy = hit and hit.Position.Y or 0
	local cf = CFrame.lookAt(Vector3.new(x, gyy + CLEAR + BOX_H / 2, z),
		Vector3.new(x + ux, gyy + CLEAR + BOX_H / 2, z + uz))
	local worst, worstH = nil, 0
	for _, part in ipairs(workspace:GetPartBoundsInBox(cf, Vector3.new(BOX_W, BOX_H, BOX_L), params)) do
		if part.CanCollide then
			local h = topOf(part) - gyy
			if h > RISE and part.Position.Y - part.Size.Y / 2 < gyy + BOX_H and h > worstH then
				worst, worstH = part, h
			end
		end
	end
	samples += 1
	if worst then
		blocked += 1
		if blocked <= 5 then
			p(("S2 BLOCKED %d/%d @(%.0f, %.0f) +%.1f by %s")
				:format(blocked, samples, x, z, worstH, worst:GetFullName()))
		end
	end
	t += STEP
end
p(("S2 walk spawn->gate: len %.0f, samples %d, BLOCKED %d %s"):format(len, samples, blocked,
	blocked == 0 and "-- CLEAR" or ""))

-- ===== S3: the sight line =====
local sHit = workspace:Raycast(Vector3.new(spawn.Position.X, spawn.Position.Y + EYE, spawn.Position.Z),
	Vector3.new(gx - spawn.Position.X, (gy + 12) - (spawn.Position.Y + EYE),
		gz - spawn.Position.Z), rp)
p(("S3 sight ray village-eye -> door: %s"):format(
	sHit and ("hit %s at (%.0f, %.0f, %.0f)")
		:format(sHit.Instance:GetFullName(), sHit.Position.X, sHit.Position.Y, sHit.Position.Z)
		or "CLEAR"))

p(("VERDICT: geometry %s, walk %s, sight %s"):format(
	offenders == 0 and "CLEAR" or "BLOCKED",
	blocked == 0 and "CLEAR" or ("BLOCKED x" .. blocked),
	sHit and "hit (see S3)" or "CLEAR"))
return table.concat(out, "\n")
