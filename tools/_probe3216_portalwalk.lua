-- 32.16 / board S10 -- can a player walk from the village spawn to the portal hall?
--
-- Two legs, both walked with the REAL body box: spawn -> the ring's mouth, then mouth -> the
-- nearest door. A sample is BLOCKED when a colliding part overlaps the body box AND its top
-- stands more than RISE above the ground at that sample, i.e. it is a wall and not a kerb or a
-- ramp the humanoid steps over. The ground is raycast per sample (the village is terraced), and
-- the box bottom is held CLEAR above it, because a body box that reaches the floor counts the
-- floor (`probe-body-box-counts-the-floor`).
local BOX_W, BOX_H = 9, 8.4          -- her measured body: 9 x 8.4 x 7
local BOX_L = 7
local STEP = 4
local CLEAR = 1.0
local RISE = 3.0

local out = {}
local function p(s) out[#out + 1] = s end

-- ===== the ring, measured from the doors themselves =====
local doors = {}
for _, d in ipairs(workspace:GetDescendants()) do
	if d:IsA("ProximityPrompt") and d.Name == "ZonePortalPrompt" and d.Parent:IsA("BasePart") then
		doors[#doors + 1] = d.Parent
	end
end
local cx, cz = 0, 0
for _, d in ipairs(doors) do cx += d.Position.X; cz += d.Position.Z end
cx, cz = cx / #doors, cz / #doors
local angs = {}
for _, d in ipairs(doors) do
	local dx, dz = d.Position.X - cx, d.Position.Z - cz
	angs[#angs + 1] = { a = math.deg(math.atan2(dz, dx)), r = math.sqrt(dx * dx + dz * dz), d = d }
end
table.sort(angs, function(a, b) return a.a < b.a end)
local best, bi, rsum = -1, 1, 0
for i = 1, #angs do
	rsum += angs[i].r
	local j = (i % #angs) + 1
	local g = angs[j].a - angs[i].a
	if g < 0 then g += 360 end
	if g > best then best, bi = g, i end
end
local rmean = rsum / #angs
local mouthDeg = angs[bi].a + best / 2
local mouthX = cx + rmean * math.cos(math.rad(mouthDeg))
local mouthZ = cz + rmean * math.sin(math.rad(mouthDeg))

local spawn = workspace:FindFirstChild("ForestSpawn")
local sx, sz = spawn.Position.X, spawn.Position.Z

-- the door nearest the mouth bearing, and a stand-off point one prompt-reach in front of it
local target = angs[bi].d
local bestD = math.huge
for _, e in ipairs(angs) do
	local dd = math.abs(((e.a - mouthDeg + 180) % 360) - 180)
	if dd < bestD then bestD, target = dd, e.d end
end

local params = OverlapParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = { workspace:FindFirstChild("Bosses") or Instance.new("Folder") }
params.MaxParts = 200

local rp = RaycastParams.new()
rp.IgnoreWater = true

local function topOf(part)
	local cf, sz2 = part.CFrame, part.Size
	return part.Position.Y + (math.abs(cf.RightVector.Y) * sz2.X + math.abs(cf.UpVector.Y) * sz2.Y
		+ math.abs(cf.LookVector.Y) * sz2.Z) / 2
end

local function walk(label, x1, z1, x2, z2)
	local dx, dz = x2 - x1, z2 - z1
	local len = math.sqrt(dx * dx + dz * dz)
	local ux, uz = dx / len, dz / len
	local px, pz = -uz, ux
	local blocked, cells, hits, detail = 0, 0, {}, {}
	local t = 0
	while t <= len + 0.001 do
		local x, z = x1 + ux * t, z1 + uz * t
		local hit = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -600, 0), rp)
		local gy = hit and hit.Position.Y or 0
		local cf = CFrame.lookAt(Vector3.new(x, gy + CLEAR + BOX_H / 2, z),
			Vector3.new(x + ux, gy + CLEAR + BOX_H / 2, z + uz))
		local worst, worstH = nil, 0
		for _, part in ipairs(workspace:GetPartBoundsInBox(cf, Vector3.new(BOX_W, BOX_H, BOX_L), params)) do
			if part.CanCollide and not part:IsDescendantOf(workspace:FindFirstChild("Bosses") or workspace) then
				local h = topOf(part) - gy
				if h > RISE and part.Position.Y - part.Size.Y / 2 < gy + BOX_H then
					if h > worstH then worst, worstH = part, h end
				end
			end
		end
		cells += 1
		if worst then
			blocked += 1
			local n = worst:GetFullName():gsub("^Workspace%.", "")
			hits[n] = (hits[n] or 0) + 1
			if #detail < 6 then
				detail[#detail + 1] = string.format("%s +%.1f @(%.0f,%.0f) t=%.0f", worst.Name, worstH, x, z, t)
			end
		end
		t += STEP
	end
	p(string.format("%s: (%.0f,%.0f) -> (%.0f,%.0f)  len %.0f  samples %d  BLOCKED %d",
		label, x1, z1, x2, z2, len, cells, blocked))
	local arr = {}
	for n, c in pairs(hits) do arr[#arr + 1] = { n = n, c = c } end
	table.sort(arr, function(a, b) return a.c > b.c end)
	for i = 1, math.min(#arr, 8) do p(string.format("      %3d x %s", arr[i].c, arr[i].n)) end
	if #detail > 0 then p("      first: " .. table.concat(detail, " ; ")) end
	return blocked
end

p(string.format("ring centre (%.1f, %.1f) r_mean %.1f | mouth gap %.1f deg at bearing %.1f -> (%.1f, %.1f)",
	cx, cz, rmean, best, mouthDeg, mouthX, mouthZ))
p(string.format("spawn %s (%.1f, %.1f, %.1f) | nearest door %s at (%.1f, %.1f) prompt reach %.1f",
	spawn.Name, spawn.Position.X, spawn.Position.Y, spawn.Position.Z, target.Name,
	target.Position.X, target.Position.Z, target:FindFirstChild("ZonePortalPrompt").MaxActivationDistance))

local a = walk("LEG A spawn->mouth", sx, sz, mouthX, mouthZ)
local b = walk("LEG B mouth->door ", mouthX, mouthZ, target.Position.X, target.Position.Z)
p(string.format("TOTAL BLOCKED %d", a + b))
return table.concat(out, "\n")
