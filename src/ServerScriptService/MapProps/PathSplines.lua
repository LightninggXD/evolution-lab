local PathSplines = {}

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

local function jitterPoint(p, maxJitter)
	return Vector3.new(
		p.X + (math.random() * 2 - 1) * maxJitter,
		p.Y,
		p.Z + (math.random() * 2 - 1) * maxJitter
	)
end

local function isBlocked(a, b, filterDescendantsInstances)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = filterDescendantsInstances or {workspace}
	
	local dir = (b - a)
	local dist = dir.Magnitude
	if dist < 0.001 then return false end
	
	local hit = workspace:Raycast(a, dir.Unit * dist, rp)
	if hit then
		return true, hit.Position, hit.Normal
	end
	return false
end

function PathSplines.Route(startPos, endPos, obstaclesFolder, options)
	options = options or {}
	local numSegments = options.numSegments or 8
	local maxJitter = options.maxJitter or 6
	local yOffset = options.yOffset or 0
	
	startPos = Vector3.new(startPos.X, yOffset, startPos.Z)
	endPos = Vector3.new(endPos.X, yOffset, endPos.Z)
	
	local dir = endPos - startPos
	local dist = dir.Magnitude
	local right = Vector3.new(-dir.Z, 0, dir.X).Unit
	
	local p1 = startPos
	local p2 = startPos + dir * 0.33
	local p3 = startPos + dir * 0.66
	local p4 = endPos
	
	p2 = jitterPoint(p2, maxJitter)
	p3 = jitterPoint(p3, maxJitter)
	
	if obstaclesFolder then
		local blocked, hitPos, hitNorm = isBlocked(startPos, endPos, {obstaclesFolder})
		if blocked then
			local pushDir = Vector3.new(hitNorm.X, 0, hitNorm.Z).Unit
			if pushDir.Magnitude < 0.1 then pushDir = right end
			local pushMag = 35
			
			p2 = p2 + pushDir * pushMag
			p3 = p3 + pushDir * pushMag
		end
	end
	
	local p0 = p1 - (p2 - p1)
	local p5 = p4 + (p4 - p3)
	
	local pathPoints = {}
	for i = 0, numSegments do
		local t = i / numSegments
		local pt
		if t < 0.5 then
			pt = catmullRom(p0, p1, p2, p3, t * 2)
		else
			pt = catmullRom(p1, p2, p3, p5, (t - 0.5) * 2)
		end
		table.insert(pathPoints, { x = pt.X, z = pt.Z })
	end
	
	return pathPoints
end

return PathSplines
