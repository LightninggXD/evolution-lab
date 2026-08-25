local PathSplines = {}

-- Cubic Catmull-Rom interpolation between p1 and p2 with surrounding p0 and p3
local function catmullRom(p0, p1, p2, p3, t)
	local t2 = t * t
	local t3 = t2 * t
	local v0 = (p2 - p0) * 0.5
	local v1 = (p3 - p1) * 0.5
	return (2 * p1 - 2 * p2 + v0 + v1) * t3
		 + (-3 * p1 + 3 * p2 - 2 * v0 - v1) * t2
		 + v0 * t
		 + p1
end

local function isBlocked(a, b, obstacles)
	local dir = (b - a)
	local dist = dir.Magnitude
	if dist < 0.001 then return false end
	local dx, dz = dir.X, dir.Z
	
	if not obstacles then return false end
	for _, obs in ipairs(obstacles) do
		if obs.type == "rect" then
			local minX, maxX = math.min(a.X, b.X), math.max(a.X, b.X)
			local minZ, maxZ = math.min(a.Z, b.Z), math.max(a.Z, b.Z)
			local rMinX, rMaxX = obs.x - obs.hx, obs.x + obs.hx
			local rMinZ, rMaxZ = obs.z - obs.hz, obs.z + obs.hz
			if not (maxX < rMinX or minX > rMaxX or maxZ < rMinZ or minZ > rMaxZ) then
				local cx = math.clamp((a.X + b.X) * 0.5, rMinX, rMaxX)
				local cz = math.clamp((a.Z + b.Z) * 0.5, rMinZ, rMaxZ)
				local nx = (a.X + b.X) * 0.5 - obs.x
				local nz = (a.Z + b.Z) * 0.5 - obs.z
				local l = math.sqrt(nx*nx + nz*nz)
				if l > 0.001 then nx, nz = nx/l, nz/l else nx, nz = 1, 0 end
				return true, Vector3.new(cx, 0, cz), Vector3.new(nx, 0, nz)
			end
		else
			local ox, oz, orad = obs.x, obs.z, obs.r or obs.radius or 20
			local len2 = dx * dx + dz * dz
			local t = math.clamp(((ox - a.X) * dx + (oz - a.Z) * dz) / len2, 0, 1)
			local qx, qz = a.X + t * dx, a.Z + t * dz
			local d2 = (ox - qx)^2 + (oz - qz)^2
			if d2 < orad * orad then
				local nx, nz = qx - ox, qz - oz
				local d = math.sqrt(nx * nx + nz * nz)
				if d > 0.001 then nx, nz = nx/d, nz/d else nx, nz = 1, 0 end
				return true, Vector3.new(qx, 0, qz), Vector3.new(nx, 0, nz)
			end
		end
	end
	return false
end

function PathSplines.Route(startPos, endPos, rng, options, obstacles)
	options = options or {}
	local maxJitter = options.maxJitter or 10
	local yOffset = options.yOffset or 0
	
	startPos = Vector3.new(startPos.X, yOffset, startPos.Z)
	endPos = Vector3.new(endPos.X, yOffset, endPos.Z)
	
	local dir = endPos - startPos
	local dist = dir.Magnitude
	if dist < 1 then return {} end
	
	local numSegments = math.max(6, math.ceil(dist / 8))
	local right = Vector3.new(-dir.Z, 0, dir.X).Unit
	
	-- Generate natural wandering control points
	local curvatureSign = (rng:NextNumber() > 0.5) and 1 or -1
	local curveOffset1 = right * (curvatureSign * (rng:NextNumber(0.4, 0.9) * maxJitter))
	local curveOffset2 = right * (-curvatureSign * (rng:NextNumber(0.2, 0.7) * maxJitter))
	
	local p1 = startPos
	local p2 = startPos + dir * 0.35 + curveOffset1
	local p3 = startPos + dir * 0.65 + curveOffset2
	local p4 = endPos
	
	if obstacles then
		local blocked, hitPos, hitNorm = isBlocked(startPos, endPos, obstacles)
		if blocked then
			local pushDir = Vector3.new(hitNorm.X, 0, hitNorm.Z).Unit
			if pushDir.Magnitude < 0.1 then pushDir = right end
			local pushMag = 30
			p2 = p2 + pushDir * pushMag
			p3 = p3 + pushDir * pushMag
		end
	end
	
	-- Phantom start and end tangents
	local p0 = p1 - (p2 - p1)
	local p5 = p4 + (p4 - p3)
	
	local pathPoints = {}
	for i = 0, numSegments do
		local globalT = i / numSegments
		local pt
		if globalT <= 0.3333 then
			local localT = globalT / 0.3333
			pt = catmullRom(p0, p1, p2, p3, localT)
		elseif globalT <= 0.6666 then
			local localT = (globalT - 0.3333) / 0.3333
			pt = catmullRom(p1, p2, p3, p4, localT)
		else
			local localT = (globalT - 0.6666) / 0.3334
			pt = catmullRom(p2, p3, p4, p5, math.clamp(localT, 0, 1))
		end
		table.insert(pathPoints, { x = pt.X, z = pt.Z })
	end
	
	return pathPoints
end

return PathSplines
