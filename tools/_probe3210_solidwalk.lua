local SSS = game:GetService("ServerScriptService")
local JungleLayout = require(SSS.MapProps.JungleLayout)
local MapGates = require(SSS.MapProps.MapGates)

local CX = 0
local BOX = Vector3.new(9, 8.4, 7)
local STEP = 6
local CLEAR = 1.0
local RISE = 3.0
local HALFW = BOX.X / 2
local BODY_RADIUS = math.sqrt(4.5^2 + 3.5^2)

local segs = {}
for _, s in ipairs(JungleLayout.Segments("Forest")) do segs[#segs + 1] = s end
for _, l in ipairs(MapGates.LANES) do
	segs[#segs + 1] = { id = "gate" .. l.id, x1 = l.x1, z1 = l.z1, x2 = l.x2, z2 = l.z2,
		w = math.min(l.wA, l.wB), tier = "lane" }
end

local colliders = {}
for _, p in ipairs(workspace.Zones.Forest.VillageMap.HuntForest:GetChildren()) do
	if p.Name == "HuntTreeCollider" or p.Name == "HuntRockCollider" then
		colliders[#colliders + 1] = p
	end
end

local rp = RaycastParams.new()
rp.FilterType = Enum.RaycastFilterType.Exclude
rp.FilterDescendantsInstances = { workspace.Zones.Forest.VillageMap.HuntForest } -- Exclude colliders from ground raycast
rp.IgnoreWater = true

local function topOf(p)
	local cf, sz = p.CFrame, p.Size
	return p.Position.Y + (math.abs(cf.RightVector.Y) * sz.X + math.abs(cf.UpVector.Y) * sz.Y
		+ math.abs(cf.LookVector.Y) * sz.Z) / 2
end

local hits, rows, samples, bad = {}, {}, 0, 0
for _, s in ipairs(segs) do
	local dx, dz = s.x2 - s.x1, s.z2 - s.z1
	local len = math.sqrt(dx * dx + dz * dz)
	if len > 0 then
		local ux, uz, px, pz = dx / len, dz / len, -dz / len, dx / len
		local off = math.max(s.w / 2 - HALFW, 0)
		local rec = { id = s.id, w = s.w, len = len, cells = 0, bad = 0, detail = {}, worst = 0 }
		for _, o in ipairs({ -off, 0, off }) do
			local t = 0
			while t <= len + 0.001 do
				local x = CX + s.x1 + ux * t + px * o
				local z = s.z1 + uz * t + pz * o
				local hit = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -500, 0), rp)
				local gy = hit and hit.Position.Y or 0
				local cy = gy + CLEAR + BOX.Y / 2
				local probePos = Vector3.new(x, cy, z)
				
				local wall, wallH = nil, 0
				for _, c in ipairs(colliders) do
					local h = topOf(c) - gy
					if h > RISE then
						local localP = c.CFrame:PointToObjectSpace(probePos)
						local hX, hZ = c.Size.X / 2, c.Size.Z / 2
						if math.abs(localP.X) < hX + BODY_RADIUS and math.abs(localP.Z) < hZ + BODY_RADIUS then
							-- Check Y just in case, though it's tall
							local hY = c.Size.Y / 2
							if math.abs(localP.Y) < hY + (BOX.Y / 2) then
								if h > wallH then wall, wallH = c, h end
							end
						end
					end
				end
				
				rec.cells += 1
				samples += 1
				if wall then
					rec.bad += 1
					bad += 1
					local nm = wall.Name
					hits[nm] = (hits[nm] or 0) + 1
					if wallH > rec.worst then rec.worst = wallH end
					if #rec.detail < 4 then
						rec.detail[#rec.detail + 1] =
							string.format("%s +%.1f @(%.0f,%.0f)off%.0f", nm, wallH, x, z, o)
					end
				end
				t += STEP
			end
		end
		rows[#rows + 1] = rec
	end
end

local out = { string.format("samples %d, blocked %d (%.1f%%)  over %d corridors", samples, bad,
	100 * bad / samples, #segs) }
local arr = {}
for n, c in pairs(hits) do arr[#arr + 1] = { n = n, c = c } end
table.sort(arr, function(a, b) return a.c > b.c end)
for i = 1, #arr do out[#out + 1] = string.format("%5d  %s", arr[i].c, arr[i].n) end
out[#out + 1] = "---"
local ls = {}
for _, r in ipairs(rows) do
	if r.bad > 0 then
		ls[#ls + 1] = string.format("%-11s w=%2d len=%3.0f  %2d/%-3d worst +%.1f | %s",
			r.id, r.w, r.len, r.bad, r.cells, r.worst, table.concat(r.detail, " ; "))
	end
end
table.sort(ls)
for _, l in ipairs(ls) do out[#out + 1] = l end
return table.concat(out, "\n")
