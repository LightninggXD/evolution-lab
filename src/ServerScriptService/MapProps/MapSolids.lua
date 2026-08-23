-- src/ServerScriptService/MapProps/MapSolids.lua
-- WHAT THIS OWNS: The invisible collision boxes for trees and rocks.
-- WHERE THE LINE IS: MapForest plants the visible art; MapSolids decides which
-- items get colliders to prevent trapping the player.
-- WHY A SEPARATE PART: A CanCollide mesh for a tree has a chunky hull that 
-- acts like a huge invisible box. We use a separate upright box for precise collision.
local JungleLayout = require(script.Parent.JungleLayout)

local MapSolids = {}

-- tree heights p25 = 5, p50 = 19 -- 10 excludes the shrub layer and keeps real small trees
local MIN_TREE_HEIGHT = 10
-- the wood is on a 16-stud grid and the median collider is 6.4 wide, so a gap rule of 10 rejected 55% of candidates
local GAP_MIN = 7
-- measured max trunk width
local TRUNK_CAP = 6
-- measured min trunk width
local TRUNK_FLOOR = 2.5
-- rock bounding boxes are typically 80% solid volume
local ROCK_FRACTION = 0.8
-- measured sink into the ground
local SINK = 2
-- minimum clearance from road paths measured in studs
local ROAD_KEEP = 2

-- rock sizes are smaller, only clip if very short
local MIN_ROCK_HEIGHT = 3.5
-- shrink height to 60% so player's head can pass under some branches
local COLLIDER_HEIGHT_FRAC = 0.6
-- the reason a 3.6-stud boulder currently gets an 8-stud wall
local MIN_COLLIDER_HEIGHT = 10

local DEBUG_SHOW = false

MapSolids.DEBUG_SHOW = DEBUG_SHOW

local state = {}

function MapSolids.Begin(zoneKey, segments)
	state = {
		zoneKey = zoneKey,
		segments = segments,
		cells = {},
		treesMade = 0,
		rocksMade = 0,
		skippedShort = 0,
		skippedClumped = 0,
		skippedRoad = 0,
		tightestGap = math.huge,
		tightestRoad = math.huge,
		candidates = {}
	}
end

local function checkGap(x, z, hX, hZ)
	local cx = math.floor(x / 32)
	local cz = math.floor(z / 32)
	local tightest = math.huge
	
	for nx = cx - 1, cx + 1 do
		for nz = cz - 1, cz + 1 do
			local cell = state.cells[nx] and state.cells[nx][nz]
			if cell then
				for _, other in ipairs(cell) do
					local dx = x - other.x
					local dz = z - other.z
					local gapX = math.max(0, math.abs(dx) - (hX + other.hX))
					local gapZ = math.max(0, math.abs(dz) - (hZ + other.hZ))
					if gapX < GAP_MIN and gapZ < GAP_MIN then
						return false
					end
					local trueGap = math.max(gapX, gapZ)
					if trueGap < tightest then
						tightest = trueGap
					end
				end
			end
		end
	end
	
	if tightest < state.tightestGap then
		state.tightestGap = tightest
	end
	return true
end

local function addCell(x, z, hX, hZ)
	local cx = math.floor(x / 32)
	local cz = math.floor(z / 32)
	state.cells[cx] = state.cells[cx] or {}
	state.cells[cx][cz] = state.cells[cx][cz] or {}
	table.insert(state.cells[cx][cz], {x = x, z = z, hX = hX, hZ = hZ})
end

local function checkRoad(x, z, hX, hZ)
	local clearance = JungleLayout.RoadClearance(state.zoneKey, x, z, state.segments)
	local req = ROAD_KEEP + math.max(hX, hZ)
	if clearance < req then
		return false
	end
	if clearance < state.tightestRoad then
		state.tightestRoad = clearance
	end
	return true
end

local function buildBox(name, x, groundY, z, yaw, w, h, d, parent)
	local box = Instance.new("Part")
	box.Name = name
	box.Size = Vector3.new(w, h, d)
	box.CFrame = CFrame.new(x, groundY - SINK + h / 2, z) * CFrame.Angles(0, yaw, 0)
	box.Anchored = true
	box.CanCollide = true
	box.CanQuery = false
	box.CanTouch = false
	box.Transparency = MapSolids.DEBUG_SHOW and 0.55 or 1
	if MapSolids.DEBUG_SHOW then
		box.Color = Color3.new(1, 0, 0)
		box.Material = Enum.Material.Neon
	end
	box.CastShadow = false
	box.Parent = parent
	return box
end

function MapSolids.Offer(inst, parent)
	local isModel = inst:IsA("Model")
	local kind = isModel and "tree" or "rock"
	local cf, bb, height
	
	if isModel then
		cf, bb = inst:GetBoundingBox()
		height = bb.Y
		if height < MIN_TREE_HEIGHT then
			state.skippedShort += 1
			return
		end
	else
		cf = inst.CFrame
		height = inst.Size.Y
		if inst.Size.Y - 0.8 < MIN_ROCK_HEIGHT then
			state.skippedShort += 1
			return
		end
	end
	
	table.insert(state.candidates, {
		inst = inst,
		parent = parent,
		kind = kind,
		cf = cf,
		height = height,
		bb = bb
	})
end

function MapSolids.Commit()
	table.sort(state.candidates, function(a, b)
		return a.height > b.height
	end)
	
	for _, c in ipairs(state.candidates) do
		local x, z = c.cf.X, c.cf.Z
		local groundY = c.cf.Y - (c.height / 2)
		local _, yaw, _ = c.cf:ToEulerAnglesYXZ()
		local w, h, d
		
		if c.kind == "tree" then
			local trunkMinX, trunkMinZ = math.huge, math.huge
			local trunkMaxX, trunkMaxZ = -math.huge, -math.huge
			local hasTrunkParts = false
			
			for _, part in ipairs(c.inst:GetDescendants()) do
				if part:IsA("BasePart") and part.Name ~= "Top" then
					hasTrunkParts = true
					local sX, sY, sZ = part.Size.X / 2, part.Size.Y / 2, part.Size.Z / 2
					local pCf = part.CFrame
					local corners = {
						pCf * Vector3.new(sX, sY, sZ), pCf * Vector3.new(-sX, sY, sZ),
						pCf * Vector3.new(sX, -sY, sZ), pCf * Vector3.new(-sX, -sY, sZ),
						pCf * Vector3.new(sX, sY, -sZ), pCf * Vector3.new(-sX, sY, -sZ),
						pCf * Vector3.new(sX, -sY, -sZ), pCf * Vector3.new(-sX, -sY, -sZ)
					}
					for _, crn in ipairs(corners) do
						local localPos = c.cf:Inverse() * crn
						trunkMinX = math.min(trunkMinX, localPos.X)
						trunkMinZ = math.min(trunkMinZ, localPos.Z)
						trunkMaxX = math.max(trunkMaxX, localPos.X)
						trunkMaxZ = math.max(trunkMaxZ, localPos.Z)
					end
				end
			end
			
			if hasTrunkParts then
				w = math.clamp(trunkMaxX - trunkMinX, TRUNK_FLOOR, TRUNK_CAP)
				d = math.clamp(trunkMaxZ - trunkMinZ, TRUNK_FLOOR, TRUNK_CAP)
			else
				local modelMin = math.min(c.bb.X, c.bb.Z)
				-- fallback derived from 8da2612; 59% of trees take this branch
				w = math.clamp(modelMin * 0.18, TRUNK_FLOOR, TRUNK_CAP)
				d = w
			end
			h = math.max(c.height * COLLIDER_HEIGHT_FRAC, MIN_COLLIDER_HEIGHT)
		else
			w = c.inst.Size.X * ROCK_FRACTION
			d = c.inst.Size.Z * ROCK_FRACTION
			h = math.max(c.height * COLLIDER_HEIGHT_FRAC, MIN_COLLIDER_HEIGHT)
		end
		
		local hX = w / 2
		local hZ = d / 2
		
		if not checkRoad(x, z, hX, hZ) then
			state.skippedRoad += 1
			continue
		end
		
		if not checkGap(x, z, hX, hZ) then
			state.skippedClumped += 1
			continue
		end
		
		addCell(x, z, hX, hZ)
		
		if c.kind == "tree" then
			buildBox("HuntTreeCollider", x, groundY, z, yaw, w, h, d, c.parent)
			state.treesMade += 1
		else
			buildBox("HuntRockCollider", x, groundY, z, yaw, w, h, d, c.parent)
			state.rocksMade += 1
		end
	end
end

function MapSolids.Report(zoneKey)
	local candidates = #state.candidates
	if candidates > 0 then
		local skippedRatio = state.skippedClumped / candidates
		if skippedRatio > 0.25 then
			warn(("[MapSolids] GAP RULE REJECTED %.1f%% OF CANDIDATES"):format(skippedRatio * 100))
		end
	end
	
	local tGap = state.tightestGap == math.huge and 0 or state.tightestGap
	local tRoad = state.tightestRoad == math.huge and 0 or state.tightestRoad
	
	print(("[MapSolids] Forest: %d tree colliders + %d rock colliders (skipped %d short, %d clumped, %d road)"):format(
		state.treesMade, state.rocksMade, state.skippedShort, state.skippedClumped, state.skippedRoad))
	print(("-- tightest collider gap %.1f studs, tightest road clearance %.1f studs"):format(tGap, tRoad))
	
	return state
end

return MapSolids