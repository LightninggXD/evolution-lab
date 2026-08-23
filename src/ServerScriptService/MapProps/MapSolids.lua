-- src/ServerScriptService/MapProps/MapSolids.lua
local JungleLayout = require(script.Parent.JungleLayout)

local MapSolids = {}

local MIN_TREE_HEIGHT = 18
local MIN_ROCK_HEIGHT = 3.5
local TRUNK_FRACTION = 1.0
local TRUNK_CAP = 8
local TRUNK_FLOOR = 2.5
local ROCK_FRACTION = 0.8
local COLLIDER_HEIGHT_FRAC = 0.6
local MIN_COLLIDER_HEIGHT = 10
local SINK = 2
local GAP_MIN = 10
local ROAD_KEEP = 2
local DEBUG_SHOW = false

MapSolids.DEBUG_SHOW = DEBUG_SHOW

local state = {
	zoneKey = nil,
	segments = nil,
	cells = {},
	treesMade = 0,
	rocksMade = 0,
	skippedShort = 0,
	skippedClumped = 0,
	skippedRoad = 0,
	tightestGap = math.huge,
	tightestRoad = math.huge,
	treeCandidates = 0
}

function MapSolids.Begin(zoneKey, segments)
	state.zoneKey = zoneKey
	state.segments = segments
	state.cells = {}
	state.treesMade = 0
	state.rocksMade = 0
	state.skippedShort = 0
	state.skippedClumped = 0
	state.skippedRoad = 0
	state.tightestGap = math.huge
	state.tightestRoad = math.huge
	state.treeCandidates = 0
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
	local req = ROAD_KEEP + math.sqrt(hX * hX + hZ * hZ)
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

function MapSolids.TreeCollider(model, parent)
	local cf, bb = model:GetBoundingBox()
	local height = bb.Y
	
	if height < MIN_TREE_HEIGHT then
		state.skippedShort = state.skippedShort + 1
		return false
	end
	
	state.treeCandidates = state.treeCandidates + 1
	
	local trunkMinX, trunkMinZ = math.huge, math.huge
	local trunkMaxX, trunkMaxZ = -math.huge, -math.huge
	local hasTrunkParts = false
	
	for _, part in ipairs(model:GetDescendants()) do
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
			for _, c in ipairs(corners) do
				local localPos = cf:Inverse() * c
				trunkMinX = math.min(trunkMinX, localPos.X)
				trunkMinZ = math.min(trunkMinZ, localPos.Z)
				trunkMaxX = math.max(trunkMaxX, localPos.X)
				trunkMaxZ = math.max(trunkMaxZ, localPos.Z)
			end
		end
	end
	
	local w, d
	if hasTrunkParts then
		w = trunkMaxX - trunkMinX
		d = trunkMaxZ - trunkMinZ
		w = math.clamp(w * TRUNK_FRACTION, TRUNK_FLOOR, TRUNK_CAP)
		d = math.clamp(d * TRUNK_FRACTION, TRUNK_FLOOR, TRUNK_CAP)
	else
		local modelMin = math.min(bb.X, bb.Z)
		w = math.clamp(modelMin * 0.18, TRUNK_FLOOR, TRUNK_CAP)
		d = w
	end
	
	local hX = w / 2
	local hZ = d / 2
	
	if not checkRoad(cf.X, cf.Z, hX, hZ) then
		state.skippedRoad = state.skippedRoad + 1
		return false
	end
	
	if not checkGap(cf.X, cf.Z, hX, hZ) then
		state.skippedClumped = state.skippedClumped + 1
		return false
	end
	
	addCell(cf.X, cf.Z, hX, hZ)
	
	local _, yaw, _ = cf:ToEulerAnglesYXZ()
	local groundY = cf.Y - (height / 2)
	
	local h = math.max(height * COLLIDER_HEIGHT_FRAC, MIN_COLLIDER_HEIGHT)
	buildBox("HuntTreeCollider", cf.X, groundY, cf.Z, yaw, w, h, d, parent)
	state.treesMade = state.treesMade + 1
	return true
end

function MapSolids.RockCollider(rock, parent)
	if rock.Size.Y - 0.8 < MIN_ROCK_HEIGHT then
		state.skippedShort = state.skippedShort + 1
		return false
	end
	
	local cf = rock.CFrame
	local w = rock.Size.X * ROCK_FRACTION
	local d = rock.Size.Z * ROCK_FRACTION
	local hX = w / 2
	local hZ = d / 2
	
	if not checkRoad(cf.X, cf.Z, hX, hZ) then
		state.skippedRoad = state.skippedRoad + 1
		return false
	end
	
	if not checkGap(cf.X, cf.Z, hX, hZ) then
		state.skippedClumped = state.skippedClumped + 1
		return false
	end
	
	addCell(cf.X, cf.Z, hX, hZ)
	
	local _, yaw, _ = cf:ToEulerAnglesYXZ()
	local h = math.max(rock.Size.Y * COLLIDER_HEIGHT_FRAC, MIN_COLLIDER_HEIGHT)
	local groundY = cf.Y - (rock.Size.Y / 2)
	buildBox("HuntRockCollider", cf.X, groundY, cf.Z, yaw, w, h, d, parent)
	state.rocksMade = state.rocksMade + 1
	return true
end

function MapSolids.Report(zoneKey)
	if state.treeCandidates > 0 then
		local skippedRatio = state.skippedClumped / state.treeCandidates
		if skippedRatio > 0.25 then
			warn("[MapSolids] GAP RULE REJECTED " .. string.format("%.1f%%", skippedRatio * 100) .. " OF TREE CANDIDATES")
		end
	end
	
	local tGap = state.tightestGap == math.huge and 0 or state.tightestGap
	local tRoad = state.tightestRoad == math.huge and 0 or state.tightestRoad
	
	print(string.format("[MapSolids] Forest: %d tree colliders + %d rock colliders (skipped %d short, %d clumped, %d road)",
		state.treesMade, state.rocksMade, state.skippedShort, state.skippedClumped, state.skippedRoad))
	print(string.format("-- tightest collider gap %.1f studs, tightest road clearance %.1f studs", tGap, tRoad))
	
	return state
end

return MapSolids
