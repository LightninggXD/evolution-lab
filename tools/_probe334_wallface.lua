-- 33.4 -- HOW MUCH OF THE BOUNDARY WALL'S FACE THE VILLAGE CAN SEE BESIDE A GATE.
--
-- WHY IT IS NOT A RAYCAST. Every rock in the range is `CanQuery = false` (`MapHorizon.hill` sets it
-- deliberately -- the colliders are separate parts and are not the silhouette), so a cast with
-- `RespectCanCollide = false` goes straight through every mountain in the zone and lands on the
-- wall behind it. R31 measured a 40-ray fan reporting `21 Wall` both before and after a fix that
-- changed everything, i.e. identical numbers for opposite worlds. So occlusion here is computed
-- from geometry: each rock is a CONE, and the segment from the eye to a point on the wall is
-- marched and tested against those cones.
--
-- ===== AND THE TWO WAYS THIS PROBE HAS ALREADY LIED =====
-- 1. A first version tested every rock in the band including the ones BEHIND the wall, and
--    reported 0 bare columns on a wall that was visibly bare edge to edge. A rock behind a wall
--    cannot hide the wall's FACE -- it can only stand above its top edge. The march therefore
--    STOPS at the wall and anything past it is irrelevant by construction.
-- 2. A second version matched gate parts by the name pattern `^Meshes` -- to catch her arch, whose
--    parts are `Meshes/Portal_Plane` -- and swept in **`Meshes/gora`, of which this place holds
--    220**: the mountain mesh itself, entered as a solid box occluder. Everything read as blocked
--    and it reported a perfect 0 on a wall that a drawing of the same geometry showed bare. Gate
--    parts are decided by ANCESTRY here, never by a name pattern.
--
-- The doorway is counted separately and never against the verdict: the gate is supposed to be a
-- hole, and wall seen THROUGH it is the far side of the world, not bare plate beside the arch.

local MapHorizon = require(game:GetService("ServerScriptService").MapProps.MapHorizon)

local ROCK = {
	HorizonHill = true, PassShoulder = true, PassRock = true, GateFlank = true,
	GateBackfill = true, GateRampart = true, FlankHill = true, FlankCrag = true, RidgePlate = true,
}
local SINK = 15          -- the range's own sink; a cone's base sits this far under the ground line
local STEP = 4           -- march resolution, studs
local DOOR_HALF = 55     -- everything inside this is the doorway and is reported, not judged

local WALL = MapHorizon.Wall

local function cones(zLo, zHi)
	local t = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("Model") and ROCK[d.Name] then
			local rx, rz, top, wx, wz = MapHorizon.WorldBox(d)
			if rx and wz + rz >= zLo and wz - rz <= zHi and top > 5 then
				t[#t + 1] = { wx = wx, wz = wz, rx = rx, rz = rz, top = top, h = top + SINK }
			end
		end
	end
	return t
end

-- Gate pieces, by ancestry: every BasePart under a `Portal*` MODEL of this zone (her arch), plus
-- the loose `Portal*` / `Arrival*` parts the built gate is made of. See fault 2 in the header.
local function gateBoxes(sign)
	local forest = workspace.Zones.Forest
	local parts = {}
	for _, d in ipairs(forest:GetChildren()) do
		if d:IsA("Model") and d.Name:match("^Portal") then
			for _, q in ipairs(d:GetDescendants()) do
				if q:IsA("BasePart") then parts[#parts + 1] = q end
			end
		end
	end
	for _, d in ipairs(forest:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name:match("^Portal") or d.Name:match("^Arrival")) then
			parts[#parts + 1] = d
		end
	end
	local t = {}
	for _, q in ipairs(parts) do
		if q.Position.Z * sign > 0 then
			local cf, s = q.CFrame, q.Size
			t[#t + 1] = {
				p = cf.Position,
				hx = (math.abs(cf.RightVector.X) * s.X + math.abs(cf.UpVector.X) * s.Y
					+ math.abs(cf.LookVector.X) * s.Z) / 2,
				hy = (math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y
					+ math.abs(cf.LookVector.Y) * s.Z) / 2,
				hz = (math.abs(cf.RightVector.Z) * s.X + math.abs(cf.UpVector.Z) * s.Y
					+ math.abs(cf.LookVector.Z) * s.Z) / 2,
			}
		end
	end
	return t
end

local function survey(label, eye, sign)
	local wallZ = sign * WALL.z
	local cs = cones(sign > 0 and 430 or -760, sign > 0 and 800 or -430)
	local gs = gateBoxes(sign)
	local judged, seen, door, cols = 0, 0, 0, {}
	for x = -400, 400, 10 do
		local colSeen = 0
		for y = 10, 175, 15 do
			local target = Vector3.new(x, y, wallZ)
			local dir = target - eye
			local n = math.floor(dir.Magnitude / STEP)
			local blocked = false
			for i = 1, n - 1 do
				local p = eye + dir * (i / n)
				for _, c in ipairs(cs) do
					if p.Y <= c.top and p.Y >= -SINK then
						local k = 1 - (p.Y + SINK) / c.h
						if k > 0 and math.abs(p.X - c.wx) <= c.rx * k
							and math.abs(p.Z - c.wz) <= c.rz * k then
							blocked = true break
						end
					end
				end
				if not blocked then
					for _, b in ipairs(gs) do
						if math.abs(p.X - b.p.X) <= b.hx and math.abs(p.Y - b.p.Y) <= b.hy
							and math.abs(p.Z - b.p.Z) <= b.hz then blocked = true break end
					end
				end
				if blocked then break end
			end
			if math.abs(x) <= DOOR_HALF then
				if not blocked then door += 1 end
			else
				judged += 1
				if not blocked then seen += 1 colSeen += 1 end
			end
		end
		if colSeen > 0 then cols[#cols + 1] = ("%+d:%d"):format(x, colSeen) end
	end
	return ("%s | %d cones, %d gate parts | WALL FACE VISIBLE %d of %d judged cells (%.0f%%) | "
		.. "through the doorway %d | columns: %s")
		:format(label, #cs, #gs, seen, judged, seen / judged * 100, door,
			#cols > 0 and table.concat(cols, " ") or "NONE")
end

local out = {}
out[#out + 1] = survey("SOUTH eye(0,25,-240)", Vector3.new(0, 25, -240), -1)
out[#out + 1] = survey("SOUTH walk(0, 6,-320)", Vector3.new(0, 6, -320), -1)
out[#out + 1] = survey("NORTH eye(0,25, 250)", Vector3.new(0, 25, 250), 1)
out[#out + 1] = survey("NORTH walk(0, 6, 330)", Vector3.new(0, 6, 330), 1)
return table.concat(out, "\n")
