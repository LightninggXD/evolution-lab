-- MapProps/MapPortals -- the map's zone doors stop advertising somebody else's game.
--
-- The owner, on a screenshot of the arc: *"ovde ce se zone otkljucavat al mi nemamo toliko
-- rebirts"*. She is reading them as a mechanic, which is exactly right -- they look like one. They
-- are thirteen finished portal props with a name plate, a requirement panel, a padlock and a slab
-- you walk into, standing in a neat arc in the western half of the square.
--
-- And every word on them is the free model's demo data: **1K REBIRTHS**, **30K REBIRTHS**, **700K**,
-- **12M**, on up to **500Qd REBIRTHS**, over zone names that are the ASSET's zone names and not
-- ours -- Cave, Magic, Nuclear, Heaven, Spooky. This game's zones do not cost rebirths at all: a
-- zone opens when you reach its `unlockStageIndex` and have beaten the boss named in
-- `requiresBossKey`. Thirteen signs in the middle of the village quoting a currency price that does
-- not exist is `evolution-lab-map-owns-the-furniture`'s fourth trap, in its purest form.
--
-- ===== WHY THEY BECOME REAL RATHER THAN GETTING DELETED =====
-- Deleting them is one line and it throws away a finished piece of art that does a job this game
-- has never had a world object for. The Zones panel is a HUD button; the strip itself is a twelve
-- thousand stud walk through twenty gates. A portal hall in the first village is the shortcut, and
-- the props for it were already standing there with the right shape.
--
-- ===== THE DOOR IS A DOOR. IT IS NOT A SECOND SET OF RULES =====
-- `ZoneService.HandleTeleportRequest` is the whole mechanism: it checks `hasZone`, refuses with a
-- Notify that NAMES the missing stage or the undefeated boss, and does the streaming handshake that
-- stops a player landing in an unloaded void. This file connects a ProximityPrompt to it and
-- nothing else. No second unlock test, no second travel path, no remote of its own -- a door that
-- decided for itself who may pass would be a second copy of a rule the server already owns, and
-- `evolution-lab-repointing-a-door` is the standing note about what that costs.
--
-- ===== THE PANEL STATES THE REQUIREMENT, NOT YOUR PROGRESS =====
-- A SurfaceGui on a shared part is one object for the whole server, so it cannot say "locked" to
-- one player and "open" to another without a client script per door. What it CAN say, truthfully,
-- to everybody at once, is what the zone costs: the stage you must reach and the boss you must
-- beat. That is a poster, and a poster is what this prop is. Who may walk through is answered at
-- the moment somebody tries, by the server, in a message that names what is missing.
--
-- ===== THIRTEEN DOORS, TWENTY ZONES =====
-- The extras are CLONED AND THE ARC IS CONTINUED, not squeezed. The thirteen sit on a real circle
-- (verified: a circumcircle through three of them fits the other ten to a tenth of a stud), so a
-- clone is the last door rotated about that circle's centre by the same angular step the artist
-- used. The alternative -- twenty doors in the space of thirteen -- overlaps them, and the
-- alternative to that -- dropping seven zones off the wall -- is a hall that lies by omission.

local ZoneService = require(script.Parent.Parent.ZoneService)
local MapAnchors = require(script.Parent.MapAnchors)
local GameConfig = require(game:GetService("ReplicatedStorage").Modules.GameConfig)

local MapPortals = {}

local LABEL_PART = "LabelUI"
local TOUCH_PART = "Touch"
local PROMPT_NAME = "ZonePortalPrompt"
-- The free model's own per-door state, read by scripts that were stripped at insert. Left standing
-- it is a BoolValue in the tree that looks authoritative and is not; `evolution-lab-free-model-
-- backdoor` is the reason nothing from a free model is ever assumed to be inert.
local DEAD_STATE = "Unlocked"

-- ===== FINDING THE DOORS =====
-- By SHAPE, never by name. The asset's door names are its own zone names and the whole point of
-- this file is that those are wrong; matching on them would mean this file carried a list of
-- somebody else's zones forever. A door is a top-level Model holding both a `LabelUI` and a
-- `Touch`, and nothing else in the map has either.
local function findDoors(map)
	local doors = {}
	for _, c in ipairs(map:GetChildren()) do
		if c:IsA("Model") and c:FindFirstChild(LABEL_PART) and c:FindFirstChild(TOUCH_PART) then
			doors[#doors + 1] = c
		end
	end
	return doors
end

local function pos2(model)
	local cf = model:GetBoundingBox()
	return Vector2.new(cf.Position.X, cf.Position.Z)
end

-- ===== ORDERING THEM ALONG THE ARC =====
-- Sorting by angle about the CENTROID does not work and it is worth writing down why, because it
-- looks like it should: the centroid of a 143-degree arc lies off to one side of it, so the angles
-- run 16 deg, 143 deg, -87 deg across the chain and the sort scrambles the middle.
--
-- A nearest-neighbour walk does work, and the only hard part is picking an end to start from. On an
-- evenly spaced chain every point has a neighbour at the same distance, so nearest-neighbour
-- distance says nothing -- but an INTERIOR point has TWO of them and an END has one, so the two
-- ends are the points whose SECOND-nearest neighbour is furthest away.
local function chainOrder(doors)
	if #doors < 3 then return doors end
	local p = {}
	for i, d in ipairs(doors) do p[i] = pos2(d) end

	local startIdx, startScore = 1, -1
	for i = 1, #doors do
		local d1, d2 = math.huge, math.huge
		for j = 1, #doors do
			if j ~= i then
				local d = (p[i] - p[j]).Magnitude
				if d < d1 then d1, d2 = d, d1 elseif d < d2 then d2 = d end
			end
		end
		if d2 > startScore then startIdx, startScore = i, d2 end
	end

	local used, out = { [startIdx] = true }, { doors[startIdx] }
	local cur = startIdx
	while #out < #doors do
		local best, bestD = nil, math.huge
		for j = 1, #doors do
			if not used[j] then
				local d = (p[cur] - p[j]).Magnitude
				if d < bestD then best, bestD = j, d end
			end
		end
		if not best then break end
		used[best] = true
		out[#out + 1] = doors[best]
		cur = best
	end
	return out
end

-- The circle through three points, in XZ. nil when they are collinear, which is the caller's cue to
-- extend the row in a straight line instead.
local function circleThrough(a, b, c)
	local d = 2 * (a.X * (b.Y - c.Y) + b.X * (c.Y - a.Y) + c.X * (a.Y - b.Y))
	if math.abs(d) < 1e-4 then return nil end
	local a2, b2, c2 = a.X ^ 2 + a.Y ^ 2, b.X ^ 2 + b.Y ^ 2, c.X ^ 2 + c.Y ^ 2
	local ux = (a2 * (b.Y - c.Y) + b2 * (c.Y - a.Y) + c2 * (a.Y - b.Y)) / d
	local uy = (a2 * (c.X - b.X) + b2 * (a.X - c.X) + c2 * (b.X - a.X)) / d
	return Vector2.new(ux, uy)
end

-- The signed angle from `u` to `v` about the origin, in XZ. Signed, because which way the arc runs
-- is the whole of where the next door goes and a magnitude would put it back on top of door twelve.
local function signedAngle(u, v)
	return math.atan2(u.X * v.Y - u.Y * v.X, u.X * v.X + u.Y * v.Y)
end

-- ===== WHAT A DOOR SAYS =====
-- Two lines: the stage that opens the zone, and the boss standing in front of it. Both come from
-- `GameConfig` at build time, so a re-tuned ladder re-letters the whole hall on the next boot and
-- can never disagree with what `HandleTeleportRequest` enforces.
local function requirementText(zone)
	if zone.unlockStageIndex and zone.unlockStageIndex <= 1 and not zone.requiresBossKey then
		return "YOU ARE HERE"
	end
	local lines = {}
	if zone.unlockStageIndex then
		lines[#lines + 1] = "STAGE " .. zone.unlockStageIndex
	end
	local guard = zone.requiresBossKey and GameConfig.GetZoneByKey(zone.requiresBossKey)
	if guard and guard.boss then
		lines[#lines + 1] = "BEAT " .. string.upper(guard.boss.name)
	end
	if #lines == 0 then return "OPEN" end
	return table.concat(lines, "\n")
end

-- Writes one zone onto one door: the name plate, the requirement panel, the accent on the slab, and
-- the prompt. Everything it touches already existed on the prop -- nothing is created except the
-- ProximityPrompt, which is the one thing a poster cannot be.
local function dressDoor(door, zone)
	door.Name = "ZonePortal_" .. zone.key

	local dead = door:FindFirstChild(DEAD_STATE)
	if dead then dead:Destroy() end

	local label = door:FindFirstChild(LABEL_PART)
	local gui = label and label:FindFirstChildOfClass("SurfaceGui")
	local text = gui and gui:FindFirstChild("Label")
	if text and text:IsA("TextLabel") then
		text.Text = requirementText(zone)
		-- The asset ships one line; ours can be two. TextScaled with wrapping is what keeps "BEAT
		-- MULTIVERSE SOVEREIGN" inside a 12-stud panel instead of clipping it -- and a clipped
		-- label reports `TextFits` true, which is the whole of `roblox-textbounds-reports-the-
		-- truncation` and why this is set rather than assumed.
		text.TextWrapped = true
		text.TextScaled = true
	end

	local touch = door:FindFirstChild(TOUCH_PART)
	local bb = touch and touch:FindFirstChildOfClass("BillboardGui")
	local nameLabel = bb and bb:FindFirstChild("Name")
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = zone.emoji .. " " .. zone.name
	end

	-- The coloured slab, tinted to the zone's accent -- the same swatch the zone's own lights, signs
	-- and gate use, so a portal is recognisably the place it leads to.
	--
	-- FOUND BY SATURATION, NOT BY CHILD ORDER. The asset gives each door two `Rock 02` meshes: a
	-- grey frame (0.36, 0.36, 0.41) and the coloured face behind it, which is the one that carries
	-- the door's identity. "the second one" is true of the copies in this map and is a property of
	-- how they happened to be saved, not of what they are -- and a clone whose children came back in
	-- a different order would silently paint the frame and leave the face demo-coloured.
	local slab, slabSat = nil, 0.08
	for _, d in ipairs(door:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:sub(1, 4) == "Rock" then
			local _, sat = Color3.toHSV(d.Color)
			if sat > slabSat then slab, slabSat = d, sat end
		end
	end
	if slab then slab.Color = zone.accentColor end

	if touch then
		local prompt = touch:FindFirstChild(PROMPT_NAME)
		if not prompt then
			prompt = Instance.new("ProximityPrompt")
			prompt.Name = PROMPT_NAME
			prompt.Parent = touch
		end
		prompt.ActionText = "Travel"
		prompt.ObjectText = zone.name
		prompt.HoldDuration = 0.4      -- a zone change is not a thing to trip into
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = 18
		prompt:SetAttribute("ZoneKey", zone.key)
		return prompt
	end
	return nil
end

-- ===== THE ONE ENTRY POINT =====
function MapPortals.Init(zoneKey)
	if not MapAnchors.IsMapped(zoneKey) then return 0 end
	local zones = workspace:FindFirstChild("Zones")
	local zone = zones and zones:FindFirstChild(zoneKey)
	local map = zone and zone:FindFirstChild("VillageMap")
	if not map then return 0 end

	local doors = chainOrder(findDoors(map))
	if #doors < 3 then
		warn(("[MapPortals] %s: found %d door props -- the hall needs at least three to fit its arc")
			:format(zoneKey, #doors))
		return 0
	end

	-- The zone list, in travel order. `GameConfig.Zones` is already ordered by `offset`, which is
	-- the order they stand in along the strip, so the hall reads the way the world does.
	local wanted = GameConfig.Zones

	-- ---- extend the arc, if the hall is short of doors
	local cloned = 0
	if #doors < #wanted then
		local n = #doors
		local pLast, pPrev = pos2(doors[n]), pos2(doors[n - 1])
		local centre = circleThrough(pos2(doors[1]), pos2(doors[math.ceil(n / 2)]), pLast)
		local proto = doors[n]
		for _ = n + 1, #wanted do
			local clone = proto:Clone()
			if centre then
				-- rotate the WHOLE door about the ring's centre by one step, so it keeps the
				-- artist's own facing rule instead of being turned by a number typed here
				local step = signedAngle(pPrev - centre, pLast - centre)
				local c3 = Vector3.new(centre.X, 0, centre.Y)
				local rot = CFrame.new(c3) * CFrame.Angles(0, -step, 0) * CFrame.new(-c3)
				clone:PivotTo(rot * proto:GetPivot())
			else
				-- collinear: the artist drew a straight colonnade, so carry on down it
				local stepV = pLast - pPrev
				clone:PivotTo(proto:GetPivot() + Vector3.new(stepV.X, 0, stepV.Y))
			end
			for _, d in ipairs(clone:GetDescendants()) do
				if d:IsA("BasePart") then d.Anchored = true end
			end
			clone.Parent = map
			doors[#doors + 1] = clone
			pPrev, pLast = pLast, pos2(clone)
			proto = clone
			cloned += 1
		end
	end

	local wired, spare = 0, 0
	for i, door in ipairs(doors) do
		local z = wanted[i]
		if z then
			local prompt = dressDoor(door, z)
			if prompt then
				prompt.Triggered:Connect(function(player)
					-- No unlock test here on purpose -- see the header. The server owns that rule
					-- and refuses with a message that names the missing stage or boss.
					ZoneService.HandleTeleportRequest(player, z.key)
				end)
				wired += 1
			end
		else
			-- More doors than zones. Left standing rather than destroyed: an unlabelled portal is
			-- scenery, and a hole in a colonnade is a bug report.
			spare += 1
		end
	end

	-- Persistent for the same reason every other counter in the village is: this is street furniture
	-- with a prompt on it, and a prop that streams out is a door that vanishes.
	for _, door in ipairs(doors) do
		door.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end

	print(("[MapPortals] %s: %d doors (%d cloned to extend the arc), %d wired to real zones, "
		.. "%d left as scenery -- the REBIRTHS demo prices are gone")
		:format(zoneKey, #doors, cloned, wired, spare))
	return wired
end

return MapPortals
