-- ExtraProps -- the hand-placed set dressing: inserted models that were chosen for a particular
-- spot in a particular zone, rather than scattered by rule.
--
-- WHY THIS EXISTS AS A FILE AND NOT AS A PILE OF PARTS IN THE WORLD. Every one of these was first
-- dropped into the zone by hand, which works right up until `ZoneBuilder.BUILD_VERSION` moves: the
-- version guard destroys the Zones folder wholesale and rebuilds it, and anything hand-placed
-- inside a zone model goes with it and is never coming back. A table that the build reads is the
-- only form of "I put a statue there" that survives a rebuild.
--
-- WHERE THE MODELS LIVE: `ServerStorage.SourceProps.Extra`. They are inserted free models with
-- their scripts stripped -- geometry only, nothing in here runs anything it did not build.
--
-- WHAT IS DELIBERATELY NOT IN HERE: anything that needs code to mean something (the treadmills,
-- the coil givers, the scroll tool) and anything whose art fights the zone it would stand in. They
-- stay in ServerStorage until there is a reason to stand them up.

local ServerStorage = game:GetService("ServerStorage")

local EXTRA = ServerStorage:FindFirstChild("SourceProps")
EXTRA = EXTRA and EXTRA:FindFirstChild("Extra")

-- dx is measured from the zone's own centre line, dz is the world Z the zone is laid out on
-- (arrival at +Z, portal onward at -Z), so a positive dz is between the player and the egg stall.
local PLACEMENTS = {
	Forest = {
		-- a treehouse among the trees, off the street on the west side
		{ template = "Treehouse", name = "PropTreehouse", dx = -168, dz = 118, scale = 0.9, yaw = 205 },
		-- the arrival pad is the first ground a player ever sees; the circle goes under it
		{ template = "MysticPad", name = "PropMysticPad", dx = 0, dz = 490, scale = 1.5, yaw = 0, lift = 0.1, noCollide = true },
	},
	Ocean = {
		{ template = "RubberDucky", name = "PropRubberDucky", dx = 132, dz = 128, scale = 5.5, yaw = 215 },
	},
	Volcano = {
		{ template = "DragonStatue", name = "PropDragonStatue", dx = -150, dz = 96, scale = 11, yaw = 150 },
	},
	DreamDimension = {
		-- three fat pastel blobs, which is this zone's entire palette already
		{ template = "Squishies/NeedohBlue", name = "PropSquishy", dx = -168, dz = 205, scale = 3.2, yaw = 47 },
		{ template = "Squishies/NeedohPurple", name = "PropSquishy", dx = -128, dz = 250, scale = 2.6, yaw = 94 },
		{ template = "Squishies/NeedohPink", name = "PropSquishy", dx = 150, dz = 190, scale = 3.0, yaw = 141 },
	},
	VoidExpanse = {
		{ template = "ShroudedStatue", name = "PropShroudedStatue", dx = -148, dz = 96, scale = 5, yaw = 170 },
	},
	CelestialThrone = {
		{ template = "AngelStatue", name = "PropAngelStatue", dx = 148, dz = 96, scale = 3.4, yaw = 200 },
	},
}

-- Forest gets a handful of flowers on top of its list, scattered rather than placed: they are the
-- one prop here small enough that a fixed spot for each would be fourteen lines saying nothing.
local FLOWER_COUNT = 14

local function resolve(path)
	if not EXTRA then return nil end
	local node = EXTRA
	for part in string.gmatch(path, "[^/]+") do
		node = node:FindFirstChild(part)
		if not node then return nil end
	end
	return node
end

local function groundAt(x, z, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -600, 0), params)
	return hit and hit.Position.Y or 0
end

-- The same sweep the egg stall gets in ZoneBuilder, for the same reason: a biome's fixed features
-- never asked scatterPoint for a point, so nothing could have stopped one being drawn through a
-- statue. Only ground-level decoration is taken, and never the floor or the street.
--
-- IT ONLY RUNS FOR THINGS BIG ENOUGH TO BE STOOD IN. A statue that eats the bush it is standing
-- next to is right; a nine-stud flower that eats one is just deleting the zone one prop at a time,
-- which is why anything under 12 studs across is seated and left alone.
local CLEAR_MIN_FOOTPRINT = 12

local function clearFootprint(zoneModel, prop, cf, size, groundY)
	if math.max(size.X, size.Z) < CLEAR_MIN_FOOTPRINT then return end
	local doomed = {}
	for _, part in ipairs(zoneModel:GetDescendants()) do
		if part:IsA("BasePart") and not part:IsDescendantOf(prop) and part ~= prop
			and part.Transparency < 1 and part.Name ~= "Floor"
			and part.Name ~= "PathSlab" and part.Name ~= "PathStone" then
			local p = part.Position
			if math.abs(p.X - cf.Position.X) < size.X * 0.45
				and math.abs(p.Z - cf.Position.Z) < size.Z * 0.45
				and p.Y < cf.Position.Y + size.Y * 0.5 and p.Y > groundY - 6 then
				doomed[#doomed + 1] = part
			end
		end
	end
	for _, part in ipairs(doomed) do
		part:Destroy()
	end
end

local function stand(zoneModel, template, x, z, scale, yaw, name, lift, noCollide)
	local clone = template:Clone()
	clone.Name = name
	clone.Parent = zoneModel

	if clone:IsA("BasePart") then
		clone.Size = clone.Size * scale
		clone.Anchored = true
		if noCollide then clone.CanCollide = false end
		clone.CFrame = CFrame.new(x, groundAt(x, z, { clone }) + clone.Size.Y / 2 + (lift or 0), z)
			* CFrame.Angles(0, math.rad(yaw), 0)
		clearFootprint(zoneModel, clone, clone.CFrame, clone.Size, clone.Position.Y - clone.Size.Y / 2)
		return clone
	end

	pcall(function() clone:ScaleTo(scale) end)
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			-- inserted geometry arrives unanchored: unanchored is a statue that falls through the
			-- world on the first physics step
			d.Anchored = true
			if noCollide then d.CanCollide = false end
		end
	end

	local groundY = groundAt(x, z, { clone })
	-- an inserted model's pivot is wherever its author left it, so the seat is measured off the
	-- bounding box rather than trusted: rotate first, then move the box onto the spot
	clone:PivotTo(CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(yaw), 0))
	local cf, size = clone:GetBoundingBox()
	clone:PivotTo(clone:GetPivot() + Vector3.new(
		x - cf.Position.X,
		groundY + (lift or 0) - (cf.Position.Y - size.Y / 2),
		z - cf.Position.Z))

	local fcf, fsize = clone:GetBoundingBox()
	clearFootprint(zoneModel, clone, fcf, fsize, groundY)
	return clone
end

local ExtraProps = {}

function ExtraProps.place(zoneModel, zoneKey, cx)
	if not EXTRA then return end

	for _, spec in ipairs(PLACEMENTS[zoneKey] or {}) do
		local template = resolve(spec.template)
		if template then
			stand(zoneModel, template, cx + spec.dx, spec.dz, spec.scale, spec.yaw, spec.name, spec.lift, spec.noCollide)
		end
	end

	if zoneKey == "Forest" then
		local flower = resolve("Flower")
		if flower then
			for i = 1, FLOWER_COUNT do
				-- off the street and out of the plaza square: everything inside 70 studs of the
				-- centre belongs to the egg stall and the walk up to it
				local side = (i % 2 == 0) and 1 or -1
				local x = cx + side * math.random(72, 150)
				local z = math.random(-180, 240)
				local f = stand(zoneModel, flower, x, z, 4 + math.random() * 2,
					math.random(0, 360), "PropFlower", nil, true)
				for _, d in ipairs(f:GetDescendants()) do
					if d:IsA("BasePart") then d.CastShadow = false end
				end
			end
		end
	end
end

return ExtraProps
