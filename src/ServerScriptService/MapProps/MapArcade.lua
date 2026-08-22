-- MapProps/MapArcade -- a row of real cabinets in the village, in place of the generated slab.
--
-- The owner asked for it twice: *"negde arcade ubaciti"* here, and back in row 30.18 *"ove arcade
-- masine isto zameniti"* about the four cabinets she inserted into `Workspace` herself.
--
-- ===== WHAT WAS WRONG WITH THE ONE THAT EXISTS =====
-- `MinigameService` builds a terminal per zone out of primitives: a 30 x 34 x 16 `Cabinet` on a
-- plinth. Thirty-four studs is FOUR TIMES the 8.4-stud player -- an arcade machine you could park a
-- bus in. It is also placed by a live overlap query over five authored spots in the ARRIVAL band,
-- which on this zone means it lands on the plaza rather than anywhere a village would put it.
--
-- ===== THE MECHANISM IS NOT REBUILT, ONLY RE-BODIED =====
-- `MinigameService` owns the remotes, the rate limit, the session and the prompt's attributes
-- (`ShopPanel = "minigame"`, `ZoneKey`). None of that is copied here. This runs AFTER its Init,
-- REPARENTS the prompt it already built onto a real cabinet, and destroys the generated model. So
-- there is exactly one prompt in the game for this feature and it is still the service's own -- if
-- MinigameService changes what it puts on that prompt tomorrow, this file needs no edit and cannot
-- disagree with it.
--
-- ===== THE CABINETS ARE HERS, AND THEY ARE LIFTED, NOT UNGROUPED =====
-- `Arcade Machines` is a free model she inserted: four `Arcade Machine` models, 3 x 6 x 3 studs
-- each, and the 30.0 sweep confirmed ZERO scripts inside it. It is moved into `ServerStorage` on
-- first use, because a `Script` under `Workspace` EXECUTES and that is the whole of 30.0 -- this
-- model is clean today, but the folder it sits in is the one a future insert lands in too.
-- It is re-checked on every lift rather than trusted, for the same reason.
--
-- A stock cabinet is 6 studs and the player is 8.4. A real arcade machine stands a little taller
-- than the person at it, so they are scaled to `CABINET_HEIGHT` rather than to the map's 1.45 --
-- the map's factor is right for things drawn around a 5.7-stud avatar, and these were not.

local ServerStorage = game:GetService("ServerStorage")

local MapAnchors = require(script.Parent.MapAnchors)

local MapArcade = {}

local SOURCE_NAME = "Arcade Machines"
local CABINET_HEIGHT = 11        -- studs, against an 8.4-stud player

-- ===== 31.15: TWO CABINETS, AND THE SPOT IS A FRACTION OF THE FLOOR =====
-- The owner, on a screenshot of the row: *"ovde ima previse arcades"*. Four of them along one side
-- of a village square is an arcade hall; the feature is ONE terminal with one prompt, and the other
-- three were never anything but art standing beside it. Two reads as "there is an arcade here"
-- without the row becoming the thing you look at.
local CABINET_COUNT = 2

-- Zone-relative, and expressed as a FRACTION OF THE VILLAGE FLOOR'S HALF-WIDTH rather than as the
-- studs it was measured in. The original -150 came from a real measurement -- a 60 x 20 x 26 box
-- test over a 20-stud grid found 99 clear spots on the floor, and x -100..-240 at z 0 was the
-- longest unbroken run and the closest to the Upgrades house, which is where she asked for it --
-- but that measurement was taken on the 1.45 map. 31.14 took the map to 1.15, which moves every
-- house 21% closer to the centre and leaves a hand-typed -150 standing in open field outside them.
-- -150 / 341 = -0.44 of the floor's half-width, and that fraction is what actually holds.
-- The row runs along Z and faces +X, into the square, so you read the screens on the way past.
local SPOTS = {
	Forest = { xFrac = -0.44, z = 0, step = 22, yaw = math.rad(90) },
}

-- The placed village floor, so `xFrac` can be resolved against the map that actually exists rather
-- than against the one this file was written for. nil when a zone has a registry entry but no
-- MainPart, which is a map that failed to seat and is already warned about by ForestMapService.
local function floorHalfWidth(zoneKey)
	local zones = workspace:FindFirstChild("Zones")
	local zone = zones and zones:FindFirstChild(zoneKey)
	local map = zone and zone:FindFirstChild("VillageMap")
	local main = map and map:FindFirstChild("MainPart")
	return main and main.Size.X / 2 or nil
end

-- Where MinigameService parks its terminals, and what it calls them.
local TERMINAL_FOLDER = "MinigameTerminals"
local TERMINAL_PREFIX = "MinigameTerminal_"
local PROMPT_NAME = "MinigamePrompt"

-- Never trust a free model twice. 30.0 found a `Script` in `Workspace` that would have run on a live
-- server, and `evolution-lab-free-model-backdoor` is why this is checked at the moment of the lift
-- rather than once, historically, in a roadmap row.
local function sanitise(model)
	local stripped = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") or d:IsA("ClickDetector")
			or d:IsA("SpawnLocation") then
			d:Destroy()
			stripped += 1
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	return stripped
end

-- The source, moved out of Workspace on first use. Returns the model or nil.
local function source()
	local parked = ServerStorage:FindFirstChild("ParkedFreeModels")
	if not parked then
		parked = Instance.new("Folder")
		parked.Name = "ParkedFreeModels"
		parked.Parent = ServerStorage
	end
	local found = parked:FindFirstChild(SOURCE_NAME) or ServerStorage:FindFirstChild(SOURCE_NAME)
	if found then return found end
	local loose = workspace:FindFirstChild(SOURCE_NAME)
	if loose then
		loose.Parent = parked
		return loose
	end
	return nil
end

-- One cabinet, standing with its feet on `y`, scaled to CABINET_HEIGHT.
--
-- THE BOX IS RE-READ AFTER THE YAW. A rotated model has a different bounding box, and seating it on
-- the box it had before the turn is how a cabinet ends up half a stud in the ground or floating --
-- the same rule `MapForest.plantOne` follows for exactly the same reason.
local function place(proto, parent, x, y, z, yaw)
	local c = proto:Clone()
	local _, size = c:GetBoundingBox()
	if size.Y > 0 then
		c:ScaleTo(CABINET_HEIGHT / size.Y)
	end
	c:PivotTo(c:GetPivot() * CFrame.Angles(0, yaw, 0))
	local cf, sz = c:GetBoundingBox()
	c:PivotTo(c:GetPivot() + Vector3.new(x - cf.Position.X, y + sz.Y / 2 - cf.Position.Y, z - cf.Position.Z))
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	c.Name = "ArcadeCabinet"
	c.Parent = parent
	return c
end

function MapArcade.Init(zoneKey, zoneOffset)
	if not MapAnchors.IsMapped(zoneKey) then return 0 end
	local spot = SPOTS[zoneKey]
	if not spot then return 0 end

	local proto = source()
	if not proto then
		warn("[MapArcade] no " .. SOURCE_NAME .. " anywhere -- the generated terminal is left alone")
		return 0
	end
	local stripped = sanitise(proto)

	local cabinets = {}
	for _, c in ipairs(proto:GetChildren()) do
		if c:IsA("Model") and #cabinets < CABINET_COUNT then cabinets[#cabinets + 1] = c end
	end
	if #cabinets == 0 then
		warn("[MapArcade] " .. SOURCE_NAME .. " holds no cabinet models")
		return 0
	end

	-- The generated terminal, and the prompt we are taking off it. Finding NEITHER is not an error:
	-- it means MinigameService did not build one for this zone, and a row of cabinets with no prompt
	-- is scenery rather than a broken feature.
	local mapFolder = workspace:FindFirstChild("Map")
	local terminals = mapFolder and mapFolder:FindFirstChild(TERMINAL_FOLDER)
	local generated = terminals and terminals:FindFirstChild(TERMINAL_PREFIX .. zoneKey)
	local prompt = generated and generated:FindFirstChild(PROMPT_NAME, true)

	local row = Instance.new("Model")
	row.Name = "ArcadeRow_" .. zoneKey
	row.Parent = terminals or workspace

	local halfW = floorHalfWidth(zoneKey)
	if not halfW then
		warn("[MapArcade] " .. zoneKey .. ": no placed MainPart -- the generated terminal is left alone")
		return 0
	end
	local spotX = spot.xFrac * halfW

	local cx = zoneOffset or 0
	local span = (#cabinets - 1) * spot.step
	local middle = nil
	for i, proto2 in ipairs(cabinets) do
		local z = spot.z - span / 2 + (i - 1) * spot.step
		local c = place(proto2, row, cx + spotX, 0, z, spot.yaw)
		if i == math.ceil(#cabinets / 2) then middle = c end
	end

	-- Reparent, never rebuild. The prompt keeps every attribute MinigameService stamped on it.
	if prompt and middle then
		local host = middle:FindFirstChildWhichIsA("BasePart", true)
		if host then
			-- The cabinets are ~11 studs and the generated one was 34, so the service's 70-stud reach
			-- is now four bodies away -- you would open the arcade from across the square.
			prompt.MaxActivationDistance = 30
			prompt.Parent = host
		end
	end
	if generated then
		generated:Destroy()
	end

	-- Persistent for the same reason the generated terminal was: this is street furniture a player
	-- walks up to, and a cabinet that streams out is a prompt that vanishes.
	row.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	print(("[MapArcade] %s: %d cabinets at (%d, %d), prompt %s, generated terminal %s%s")
		:format(zoneKey, #cabinets, spotX, spot.z,
			prompt and "moved" or "NOT FOUND", generated and "removed" or "absent",
			stripped > 0 and (", stripped " .. stripped .. " scripts/prompts from the source") or ""))
	return #cabinets
end

return MapArcade
