local PathSplines = {}

local function catmullRom(p1, p2, p3, p4, t)
	local t2 = t * t
	local t3 = t2 * t
	
	local v1 = (p3 - p1) * 0.5
	local v2 = (p4 - p2) * 0.5
	
	return (2 * p2 - 2 * p3 + v1 + v2) * t3
		 + (-3 * p2 + 3 * p3 - 2 * v1 - v2) * t2
		 + v1 * t
		 + p2
end

local function jitterPoint(p, maxJitter, rng)
	return Vector3.new(
		p.X + (rng:NextNumber() * 2 - 1) * maxJitter,
		p.Y,
		p.Z + (rng:NextNumber() * 2 - 1) * maxJitter
	)
end

local function isBlocked(a, b, obstacles)
	local dir = (b - a)
	local dist = dir.Magnitude
	if dist < 0.001 then return false end
	local dx, dz = dir.X, dir.Z
	
	if not obstacles then return false end
	for _, obs in ipairs(obstacles) do
		-- obs is { x, z, r }
		local ox, oz, orad = obs.x, obs.z, obs.r
		
		-- distance from circle center to segment
		local t = ((ox - a.X) * dx + (oz - a.Z) * dz) / (dx*dx + dz*dz)
		t = math.clamp(t, 0, 1)
		local qx, qz = a.X + t * dx, a.Z + t * dz
		
		local d2 = (ox - qx)^2 + (oz - qz)^2
		if d2 < orad * orad then
			-- collision! normal is from obstacle center to point
			local nx, nz = qx - ox, qz - oz
			local d = math.sqrt(nx*nx + nz*nz)
			if d > 0.001 then
				return true, Vector3.new(qx, 0, qz), Vector3.new(nx/d, 0, nz/d)
			else
				return true, Vector3.new(qx, 0, qz), Vector3.new(1, 0, 0)
			end
		end
	end
	return false
end

function PathSplines.Route(startPos, endPos, rng, options, obstacles)
	options = options or {}
	local maxJitter = options.maxJitter or 6
	local yOffset = options.yOffset or 0
	
	startPos = Vector3.new(startPos.X, yOffset, startPos.Z)
	endPos = Vector3.new(endPos.X, yOffset, endPos.Z)
	
	local dir = endPos - startPos
	local dist = dir.Magnitude
	if dist < 1 then return {} end
	
	local numSegments = math.max(2, math.ceil(dist / 20))
	local right = Vector3.new(-dir.Z, 0, dir.X).Unit
	
	local p1 = startPos
	local p2 = startPos + dir * 0.33
	local p3 = startPos + dir * 0.66
	local p4 = endPos
	
	p2 = jitterPoint(p2, maxJitter, rng)
	p3 = jitterPoint(p3, maxJitter, rng)
	
	if obstacles then
		local blocked, hitPos, hitNorm = isBlocked(startPos, endPos, obstacles)
		if blocked then
			local pushDir = Vector3.new(hitNorm.X, 0, hitNorm.Z).Unit
			if pushDir.Magnitude < 0.1 then pushDir = right end
			local pushMag = 35
			p2 = p2 + pushDir * pushMag
			p3 = p3 + pushDir * pushMag
		end
	end
	
	-- We want the curve to pass through startPos and endPos.
	-- Catmull-Rom from p1 to p4 requires p0 and p5.
	local p0 = p1 - (p2 - p1)
	local p5 = p4 + (p4 - p3)
	
	local pathPoints = {}
	for i = 0, numSegments do
		local t = i / numSegments
		local pt
		if t < 0.3333 then
			pt = catmullRom(p0, p1, p2, p3, t * 3)
		elseif t < 0.6666 then
			pt = catmullRom(p1, p2, p3, p4, (t - 0.3333) * 3)
		else
			pt = catmullRom(p2, p3, p4, p5, (t - 0.6666) * 3)
		end
		table.insert(pathPoints, { x = pt.X, z = pt.Z })
	end
	
	return pathPoints
end

return PathSplines
