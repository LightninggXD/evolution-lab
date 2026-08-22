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
-- The extras are CLONED, not squeezed. The thirteen sit on a real circle (verified: a circumcircle
-- through three of them fits the other ten to a tenth of a stud), so a clone is another door on
-- that same circle. The alternative -- twenty doors in the space of thirteen -- overlaps them, and
-- the alternative to that -- dropping seven zones off the wall -- is a hall that lies by omission.
--
-- ===== ...AND THE ARC MUST NOT CLOSE. IT DID, AND IT SEALED THE OWNER IN =====
-- The first cut continued the arc by rotating the last door one more step, seven times, and shipped
-- a TRAP: the artist's step is 18.3 degrees and twenty of them is 366, so the hall wrapped past its
-- own first door and became a solid wall of stone 88 studs across with a player standing inside it.
-- The owner's report was three words -- *"ne moze se izaci odavde"* -- and no probe in the repo
-- would ever have said it, because every one of them asks "can I reach this door", which you can,
-- from the inside, forever.
--
-- So the doors are not extended one at a time any more. THE WHOLE RING IS LAID OUT AT ONCE, from
-- the circle the artist drew, across a span that stops `OPENING_DEG` short of a full turn -- and
-- the opening faces the village, so the mouth is on the side you arrive from. That is the same rule
-- `MapJungle.OPENING_ARC` follows for a camp, for the same reason written down there: a wall that
-- seals a player away is indistinguishable, from inside, from a wall that does not.
--
-- ===== TWENTY DOORS ONLY FIT IF THEY SHRINK =====
-- The circle is fixed art -- 44 studs of radius, i.e. 280 of circumference -- and twenty doors at
-- their authored 13.2 studs is 263 of it. There is no opening to be had at that size; the geometry
-- is what closed the ring, not the loop that placed them. Two ways out, and only one is honest at
-- this point in the phase: push the circle out to a radius of 61 (a hall 121 studs across, in the
-- middle of a village square that 31.14 just shrank, standing on 16 studs of ground nothing has
-- measured), or bring the door down to the body like the eggs and the map already came down.
-- So the scale is DERIVED, never typed: one step's chord, less a gap, over the door's own measured
-- width. At twenty doors that lands near 0.72 -- an 11.6-stud door against an 8.4-stud player,
-- the same 1.4x the eggs settled on in 31.13 -- and a hall of thirteen would leave them alone.

local ZoneService = require(script.Parent.Parent.ZoneService)
local MapAnchors = require(script.Parent.MapAnchors)
local MapRing = require(script.Parent.MapRing)
local GameConfig = require(game:GetService("ReplicatedStorage").Modules.GameConfig)

local MapPortals = {}

local LABEL_PART = "LabelUI"
local TOUCH_PART = "Touch"
local PROMPT_NAME = "ZonePortalPrompt"
-- The free model's own per-door state, read by scripts that were stripped at insert. Left standing
-- it is a BoolValue in the tree that looks authoritative and is not; `evolution-lab-free-model-
-- backdoor` is the reason nothing from a free model is ever assumed to be inert.
local DEAD_STATE = "Unlocked"

-- ===== THE MOUTH =====
-- The arc the doors are laid across is a full turn LESS this, and the gap faces the village. 72
-- degrees is a fifth of the ring, which on this circle is 55 studs of clear ground -- six times the
-- player's own 9-stud box, so it reads as the way in from across the square rather than as a seam
-- somebody forgot to close. It is an ANGLE and not a stud count on purpose: a re-themed map with a
-- wider ring gets a proportionally wider mouth, and can never get a mouth narrower than a body.
local OPENING_DEG = 72
-- Studs of daylight between two neighbouring doors. Non-zero because two slabs that touch are one
-- wall with a line drawn on it, and this hall is meant to be read as twenty separate places.
local DOOR_GAP = 2.2
-- A floor under the shrink. Below this the requirement panel stops being legible from the middle of
-- the ring, and a hall that needs more than this many doors wants a bigger circle, not smaller art.
local MIN_DOOR_SCALE = 0.55

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
	for i, d in ipairs(doors) do p[i] = MapRing.Flat(d) end

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


-- How wide a door is ACROSS the wall it stands in. `Model:GetBoundingBox` with no argument is
-- oriented to the model's own pivot, not to the world, so the door's three numbers arrive as
-- (thickness, height, width) whatever bearing it currently sits at -- and the width is simply the
-- larger of the two horizontal ones, because a portal slab is wider than it is thick. Measured
-- rather than typed so a different map's door prop sizes its own ring.
local function doorSpan(door)
	local _, size = door:GetBoundingBox()
	return math.max(size.X, size.Z), size.Y
end

-- ===== LAYING THE WHOLE RING AT ONCE =====
-- Every door is placed from the count, never from its neighbour -- which is the difference between
-- this and the loop that sealed the ring. An arc built by repeated "one more step" has no idea how
-- far round it has come; an arc built from `span / (n - 1)` cannot overrun by construction.
--
-- `ScaleTo` scales a model about its PIVOT, and on these props the pivot is the bounding box centre
-- -- so a shrunk door hangs in the air by half of what it lost. The base is read before and put back
-- after, which also makes the pass idempotent: `ScaleTo` is absolute, so a second call scales
-- nothing and moves nothing.
--
-- AND `ScaleTo` SCALES `ProximityPrompt.MaxActivationDistance` TOO. That is not a documented corner
-- this file guessed at -- it was measured, on a throwaway model, after the walk-up test reported all
-- twenty doors out of reach at once: a prompt set to 18 reads 9.0 after `ScaleTo(0.5)`. It is why
-- `Init` lays the ring out BEFORE it dresses the doors and not after, which looks like an arbitrary
-- ordering and is the only one that ships the reach `dressDoor` asks for. A door you can see, walk
-- to and stand in front of, whose prompt never appears, is the hardest kind of dead end to report.
local function layOut(doors, centre, radius, openBearing)
	local n = #doors
	local span = math.rad(360 - OPENING_DEG)
	local step = span / (n - 1)

	-- one step's chord is all the room a door has; the gap comes out of it before the door does
	local width, height = doorSpan(doors[1])
	local chord = 2 * radius * math.sin(step / 2)
	local scale = math.clamp((chord - DOOR_GAP) / width, MIN_DOOR_SCALE, 1)

	local first = openBearing + math.rad(OPENING_DEG) / 2
	for i, door in ipairs(doors) do
		local cf, size = door:GetBoundingBox()
		local base = cf.Position.Y - size.Y / 2
		MapRing.PlaceAt(door, centre, first + (i - 1) * step)
		door:ScaleTo(scale)
		local cf2, size2 = door:GetBoundingBox()
		local dy = base - (cf2.Position.Y - size2.Y / 2)
		if math.abs(dy) > 0.01 then door:PivotTo(door:GetPivot() + Vector3.new(0, dy, 0)) end
	end
	return scale, math.rad(OPENING_DEG) * radius, width * scale, height * scale
end

-- Which way the mouth faces: at the village floor, so you meet the hall head-on walking in off the
-- square. `MainPart` is the floor `ForestMapService.seat` seats the whole map by, so it is the one
-- name already load-bearing for this map's position. Without it the ring keeps its own facing and
-- the opening lands wherever the artist's chain happened to start, which is a coin toss.
local function villageBearing(map, centre)
	local floor = map:FindFirstChild("MainPart")
	if not floor then return nil end
	local d = Vector2.new(floor.Position.X, floor.Position.Z) - centre
	if d.Magnitude < 1 then return nil end
	return math.atan2(d.Y, d.X)
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
		-- Literal studs, and it only stays literal because the ring is already laid out and scaled
		-- by the time this runs -- see `layOut`'s header. Measured against the walk-up test: a
		-- player standing 8 studs in front of any of the twenty is 8.0 from its `Touch`.
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

	-- ---- the ring the artist drew, before anything is added to it or moved on it
	local centre, radius = MapRing.Fit(doors)
	local facing = centre and villageBearing(map, centre)
	if not centre or not facing then
		-- A straight colonnade, or a map with no floor to face. Nothing here can lay out a ring it
		-- cannot find, and guessing one is how a hall ends up sealed -- so the doors are dressed
		-- where they already stand and the hall is however long the artist drew it.
		warn(("[MapPortals] %s: the doors do not sit on a findable circle -- left where they are")
			:format(zoneKey))
	end

	-- ---- one clone per zone the hall is short of. Placed nowhere in particular: `layOut` below
	-- puts every door, original and clone alike, at a bearing computed from the COUNT. That is the
	-- whole fix for the sealed ring -- there is no "one more step" left to overrun.
	local cloned = 0
	if #doors < #wanted then
		local proto = doors[#doors]
		for _ = #doors + 1, #wanted do
			local clone = proto:Clone()
			for _, d in ipairs(clone:GetDescendants()) do
				if d:IsA("BasePart") then d.Anchored = true end
			end
			clone.Parent = map
			doors[#doors + 1] = clone
			cloned += 1
		end
	end

	-- ---- and lay all of them across an arc that stops short of closing
	local scale, mouth, dw, dh = 1, 0, 0, 0
	if centre and facing then
		scale, mouth, dw, dh = layOut(doors, centre, radius, facing)
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

	print(("[MapPortals] %s: %d doors (%d cloned), %d wired, %d scenery -- ring r=%.0f, "
		.. "door %.1f x %.1f at %.2f, mouth %.0f studs facing the village")
		:format(zoneKey, #doors, cloned, wired, spare, radius or 0, dw, dh, scale, mouth))
	return wired
end

return MapPortals
