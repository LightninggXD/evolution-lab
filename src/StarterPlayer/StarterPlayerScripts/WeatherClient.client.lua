--[[
	WeatherClient -- rain, ash, dust and motes, drawn around the camera (34.7).

	THE ZONE DECIDES AND THE CAMERA DRAWS. `ZoneBuilder` stamps `Weather` (and an optional
	`WeatherColor`) on each zone model out of `GameConfig.ZoneWeather`, so a rebuild carries the
	decision with it and nothing is hand-placed. This script does the half that only a client can:
	it finds the zone the camera is standing in, and holds one small emitting sheet over the
	camera for as long as it stays there.

	WHY THE SHEET IS SMALL AND FOLLOWS THE CAMERA is written out in `WeatherLibrary` -- the short
	version is that the previous zone-wide sheet spent ~1,000 live particles to put twenty specks
	anywhere in view, and this spends ~340 to fill it.

	ONE RenderStepped, AND ONLY WHILE THERE IS WEATHER. The connection is made when a zone with
	weather is entered and dropped the moment one without is (clear sky is the majority of the
	strip, and nine zones have none at all), so the common case costs a 0.4 s poll and nothing
	else. See the streaming note in memory: one gated frame hook per animated set, never one per
	thing being animated.

	KNOWN LIMIT: particles do not collide, so rain falls through the waterfall grotto's roof and
	through the village stalls. Fixing that means raycasting per particle, which is not what a
	cosmetic layer is allowed to cost.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WeatherLibrary = require(ReplicatedStorage.Modules.WeatherLibrary)

local POLL = 0.4          -- seconds between "which zone am I in" checks
local BAND_X = 700        -- half-width of a zone's air, against ZoneSpacing 1900
local BAND_Z = 720        -- ... and its depth; TERRAIN_OUTER (the wall's inner face) is 623

local player = Players.LocalPlayer

local volume            -- the emitting sheet, parented to the camera
local renderConn
local currentKey        -- the zone whose weather is currently up, nil when clear
local geometry          -- the active kind's height / forward / span

-- ===== THE SHEET =============================================================

local function teardown()
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	if volume then
		volume:Destroy()
		volume = nil
	end
	currentKey = nil
	geometry = nil
end

-- Held over the camera and pushed a little way ahead of it, on the FLAT look direction: taking the
-- LookVector whole would swing the sheet out of the sky the moment the player looked up. Separate
-- from `follow` because `build` needs the sheet placed BEFORE it is parented into the world -- a
-- volume that reaches the camera at its default CFrame emits one frame of weather at the origin
-- first, which in the Forest is a burst of rain inside the village square.
local function place()
	local camera = workspace.CurrentCamera
	if not (camera and volume and geometry) then return end

	local cf = camera.CFrame
	local look = cf.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = (flat.Magnitude > 0.05) and flat.Unit or Vector3.new(0, 0, -1)
	volume.CFrame = CFrame.new(cf.Position + flat * geometry.forward + Vector3.new(0, geometry.height, 0))
end

local function build(kindName, tint)
	local camera = workspace.CurrentCamera
	if not camera then return false end

	volume = Instance.new("Part")
	volume.Name = "WeatherVolume"
	volume.Anchored = true
	volume.CanCollide = false
	-- CanQuery, not just CanCollide. A part with CanCollide false and Transparency 1 is still
	-- found by every downward raycast in the game -- that is exactly how the last weather part
	-- put the egg columns and the adventure board 198 studs into the sky (34.15). This one lives
	-- on the client and rides the camera, so a stray query finding it would be worse still.
	volume.CanQuery = false
	volume.CanTouch = false
	volume.Transparency = 1
	volume.CastShadow = false
	volume.Locked = true
	volume.Massless = true

	local kind = WeatherLibrary.Build(volume, kindName, tint)
	if not kind then
		volume:Destroy()
		volume = nil
		return false
	end
	geometry = kind
	volume.Size = Vector3.new(kind.span, 1, kind.span)
	place()
	volume.Parent = camera
	return true
end

-- Every frame: keep the sheet with the camera, and put it back if a respawn replaced the camera
-- underneath it.
local function follow()
	local camera = workspace.CurrentCamera
	if not (camera and volume and geometry) then return end
	if volume.Parent ~= camera then
		volume.Parent = camera
	end
	place()
end

-- ===== WHICH ZONE THE CAMERA IS IN ===========================================

local function zonesFolder()
	return workspace:FindFirstChild("Zones")
end

-- The zone MODEL is the authority, because ZoneBuilder is what wrote the weather onto it. The
-- position test only picks which model to ask: nearest offset, and inside that zone's own air --
-- the arena, the expedition strips and the space between platforms are all outside every band and
-- correctly get nothing.
local function zoneAtCamera()
	local camera = workspace.CurrentCamera
	local folder = zonesFolder()
	if not (camera and folder) then return nil end

	local pos = camera.CFrame.Position
	if math.abs(pos.Z) > BAND_Z then return nil end

	local best, bestDist = nil, BAND_X
	for _, model in ipairs(folder:GetChildren()) do
		local weather = model:GetAttribute("Weather")
		if weather then
			local cx = model:GetAttribute("WeatherX")
			if cx then
				local d = math.abs(pos.X - cx)
				if d < bestDist then
					best, bestDist = model, d
				end
			end
		end
	end
	return best
end

local function refresh()
	local model = zoneAtCamera()
	local key = model and model.Name or nil

	if key == currentKey then return end

	teardown()
	if not model then return end

	local kindName = model:GetAttribute("Weather")
	local tint = model:GetAttribute("WeatherColor")
	if build(kindName, tint) then
		currentKey = key
		follow()
		renderConn = RunService.RenderStepped:Connect(follow)
	end
end

-- A respawn replaces the camera and takes the sheet with it; drop the stale state so the next poll
-- rebuilds rather than following a destroyed part.
player.CharacterAdded:Connect(function()
	teardown()
end)

task.spawn(function()
	while true do
		local ok, err = pcall(refresh)
		if not ok then
			warn("[WeatherClient] " .. tostring(err))
			teardown()
		end
		task.wait(POLL)
	end
end)
