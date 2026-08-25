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
--      not. EVERY blocker is reported, GROUPED by instance with its z-range (review R3: five
--      identical lines that hide the rest made this probe run twice; x5 inkubator | x12 Fountain
--      says it once).
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
-- R3: the old finder looked only for `ZonePortal_` and NEVER matched, so every run ran on the
-- fallback silently. A fallback that still fires announces itself loudly.
--
-- SECOND REWRITE, 2026-08-25 (33.1): MapGateArch (32.30) turned the built gate into her arch and
-- left the teleport as a BasePart named `PortalGate` -- the probe's Model-only match then took the
-- LOWEST-Z model it could find, which is a village-ring door (`ZonePortal_VoidExpanse`, z -29.7),
-- and one whole run walked a diagonal across the village against furniture. The locator now
-- takes BOTH classes and always the MOST-NEGATIVE-Z candidate: the arrival gate is the thing at
-- the -Z edge by definition, and MapGateArch.findSheet is the same rule over parts.
--
-- THIRD REWRITE, 2026-08-25: and the search ROOT is the fault that rewrite left behind. Every one
-- of the 21 zones has a `PortalGate` at z -575 -- they differ only in x, by `ZoneSpacing` 1900 --
-- so "most negative z over all of `workspace`" is a tie between 21 gates broken by traversal
-- order, and it picked `Zones.CelestialThrone.PortalGate` at **x = 32300**. The probe then walked
-- 32,313 studs across every zone in the game and reported `BLOCKED 852` against furniture in
-- worlds this row has never been about. THE SEARCH IS SCOPED TO FOREST, because that is the zone
-- this probe walks -- `ForestSpawn` is already its other end.
local zoneRoot = (workspace:FindFirstChild("Zones") and workspace.Zones:FindFirstChild("Forest"))
	or workspace
local gx, gz, gy, gatePath = 0, -575, 69, "(fallback 0, 69, -575)"
local gateFound = false
for _, d in ipairs(zoneRoot:GetDescendants()) do
	local isModel = d:IsA("Model") and (d.Name == "PortalGate" or d.Name == "PortalCore"
		or d.Name:find("ZonePortal_", 1, true))
	local isSheet = d:IsA("BasePart") and d.Name == "PortalGate"
	if isModel or isSheet then
		local px, py, pz
		if d:IsA("Model") then
			local cf = d:GetBoundingBox()
			px, py, pz = cf.Position.X, cf.Position.Y, cf.Position.Z
		else
			px, py, pz = d.Position.X, d.Position.Y, d.Position.Z
		end
		if not gateFound or pz < gz then
			gateFound = true
			gx, gz, gy, gatePath = px, pz, py, d:GetFullName()
		end
	end
end
if not gateFound then
	p("!! GATE FALLBACK: nothing matched inside " .. zoneRoot:GetFullName()
		.. " -- using (0, 69, -575). Fix the locator before trusting any S3 line.")
end
local spawn = workspace:FindFirstChild("ForestSpawn")
	or workspace:FindFirstChildWhichIsA("SpawnLocation")
if not spawn then p("!! no ForestSpawn / SpawnLocation found -- cannot walk"); return table.concat(out, "\n") end
p(("gate %s at (%.1f, %.1f, %.1f)"):format(gatePath, gx, gy, gz))
if math.abs(gx) > 400 then
	p(("!! GATE IS NOT IN FOREST: x %.0f is a neighbouring zone's gate (ZoneSpacing 1900). "):format(gx)
		.. "Every number below is measured across the void -- do not read them.")
end
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

-- Every blocker is kept, grouped by instance (R3): count plus the z-range it blocked over.
local groups, order = {}, {}
local function bump(inst, z)
	local g = groups[inst]
	if not g then
		g = { n = 0, zmin = math.huge, zmax = -math.huge,
			tag = inst.Parent and inst.Parent.Name ~= inst.Name
				and (inst.Parent.Name .. "." .. inst.Name) or inst.Name }
		groups[inst] = g
		order[#order + 1] = g
	end
	g.n += 1
	if z < g.zmin then g.zmin = z end
	if z > g.zmax then g.zmax = z end
end

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
		bump(worst, z)
	end
	t += STEP
end
p(("S2 walk spawn->gate: len %.0f, samples %d, BLOCKED %d %s"):format(len, samples, blocked,
	blocked == 0 and "-- CLEAR" or ""))
if blocked > 0 then
	table.sort(order, function(a, b) return a.n > b.n end)
	local bits = {}
	for _, g in ipairs(order) do
		bits[#bits + 1] = ("x%d %s (z %.0f..%.0f)"):format(g.n, g.tag, g.zmin, g.zmax)
	end
	p("S2 blockers, grouped: " .. table.concat(bits, " | "))
end

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
