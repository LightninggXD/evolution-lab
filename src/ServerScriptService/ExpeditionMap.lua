-- ExpeditionMap -- the four chambers an Expedition is walked through, and nothing else.
--
-- WHY IT IS ITS OWN FILE, and it is the same argument `EventArena` makes: this is the second thing
-- `ZoneBuilder` builds that is not part of a zone. It carries its own version stamp for the reason
-- that one does -- bumping `BUILD_VERSION` drops all twenty-one zones and rebuilds ~105,000 parts,
-- and this map is about 400. Redressing a chamber must not cost a full world rebuild.
--
-- =====================================================================================
-- WHERE IT SITS
-- =====================================================================================
-- Mirrored to the Colosseum. That one is at z +1400; this runs from z -1250 back toward -2500,
-- off the opposite edge of the Forest platform (which ends at z 575). Reached only by teleport, so
-- the distance costs nothing -- the same trade `GameConfig.EventArena` is authored on.
--
-- =====================================================================================
-- THE SHAPE IS FOUR ROOMS IN A LINE, AND THAT IS THE WHOLE FLOOR PLAN
-- =====================================================================================
-- Chamber 1 arrival + station 1, chamber 2 station 2, chamber 3 station 3, chamber 4 the vault.
-- Every wall between them carries a three-piece doorway -- left jamb, right jamb, lintel -- which is
-- the same construction every zone boundary in this world uses.
--
-- The wall into the LAST chamber additionally carries a `SymbolDoor`: a solid slab that the client
-- dissolves for its own player once the server says they hold all three seals. It is one part and
-- the server never moves it. See `ExpeditionService` for why that is a client-side act.
--
-- =====================================================================================
-- SIZED AGAINST THE BODY, NOT AGAINST A HUMAN
-- =====================================================================================
-- A stage-20 player is a 45 x 42 x 35 stud box. Every opening here is `ZoneKit.PORTAL_GAP` wide and
-- `DOOR_H` tall, which are the dimensions the zone gates already pass that body through, and every
-- chamber is 300 across so there is room to fight in one. Authoring this at human scale is the
-- mistake `SplicerService` had to be rescued from on 2026-08-17.

local ServerStorage = game:GetService("ServerStorage")

local ZoneKit = require(script.Parent.ZoneKit)

local newPart, addLight = ZoneKit.newPart, ZoneKit.addLight
local addPlankText = ZoneKit.addPlankText

local ExpeditionMap = {}

-- Bump when the SHAPE changes. `ZoneBuilder` compares this against the folder's own attribute and
-- rebuilds the map alone, leaving the twenty zones untouched.
ExpeditionMap.MAP_VERSION = 1

-- ===== THE FLOOR PLAN, IN ONE BLOCK =====
local CHAMBER = 300 -- square, x and z
local WALL_T = 8
local WALL_H = 150
local DOOR_H = 96 -- clears a 42-stud body with room for the camera
local FIRST_Z = -1400 -- centre of chamber 1
local PITCH = CHAMBER + WALL_T -- centre-to-centre

-- Where a run starts. Just inside chamber 1's near wall, looking down the line of chambers so the
-- first thing on screen is the route.
function ExpeditionMap.GetSpawnCFrame()
	local pos = Vector3.new(0, 6, FIRST_Z + CHAMBER / 2 - 40)
	return CFrame.lookAt(pos, pos - Vector3.new(0, 0, 40))
end

function ExpeditionMap.GetChamberCentre(index)
	return Vector3.new(0, 0, FIRST_Z - (index - 1) * PITCH)
end

-- Where a station terminal stands in its chamber: against the left wall, clear of the walking line
-- down the middle, and clear of the doorway at either end.
function ExpeditionMap.GetStationPosition(index)
	return ExpeditionMap.GetChamberCentre(index) + Vector3.new(-96, 0, 0)
end

local function floorSlab(model, centre, colour)
	return newPart({
		Name = "ChamberFloor",
		Size = Vector3.new(CHAMBER, 4, CHAMBER),
		Position = centre + Vector3.new(0, -2, 0),
		Color = colour,
		Material = Enum.Material.Slate,
		Parent = model,
	})
end

-- A plain solid wall run. `axis` is "x" for a wall lying across the route (a front or back wall) and
-- "z" for one running along it.
local function wall(model, name, centre, axis, length, colour)
	local size = axis == "x"
		and Vector3.new(length, WALL_H, WALL_T)
		or Vector3.new(WALL_T, WALL_H, length)
	return newPart({
		Name = name,
		Size = size,
		Position = centre + Vector3.new(0, WALL_H / 2, 0),
		Color = colour,
		Material = Enum.Material.Concrete,
		Parent = model,
	})
end

-- A wall across the route with a doorway punched through it: two jambs and a lintel. Three parts
-- rather than one with a hole, because a Part cannot have a hole -- this is the same three-piece
-- construction the zone boundaries are built from.
local function doorwayWall(model, zCentre, gap, colour, accent)
	local jamb = (CHAMBER - gap) / 2
	local offset = gap / 2 + jamb / 2

	for _, side in ipairs({ -1, 1 }) do
		newPart({
			Name = "DoorJamb",
			Size = Vector3.new(jamb, WALL_H, WALL_T),
			Position = Vector3.new(side * offset, WALL_H / 2, zCentre),
			Color = colour,
			Material = Enum.Material.Concrete,
			Parent = model,
		})
	end

	local lintel = newPart({
		Name = "DoorLintel",
		Size = Vector3.new(gap, WALL_H - DOOR_H, WALL_T),
		Position = Vector3.new(0, DOOR_H + (WALL_H - DOOR_H) / 2, zCentre),
		Color = colour,
		Material = Enum.Material.Concrete,
		Parent = model,
	})

	-- A lit strip on the underside of the lintel, so a doorway reads as a doorway from the far end
	-- of a 300-stud room rather than as a gap in a grey wall.
	local strip = newPart({
		Name = "DoorStrip",
		Size = Vector3.new(gap, 1.4, 3),
		Position = Vector3.new(0, DOOR_H - 1, zCentre),
		Color = accent,
		Material = Enum.Material.Neon,
		Parent = model,
	})
	addLight(strip, accent, 60, 2)

	return lintel
end

-- ===== THE SEALED DOOR =====
-- One part, filling the last doorway. The server builds it solid and NEVER touches it again; the
-- client that holds all three seals sets `CanCollide = false` on its own copy and fades it. That is
-- why it is a single named part rather than a model: the client has to find exactly one thing.
local function sealedDoor(model, zCentre, gap, accent)
	local door = newPart({
		Name = "SymbolDoor",
		Size = Vector3.new(gap, DOOR_H, 3),
		Position = Vector3.new(0, DOOR_H / 2, zCentre),
		Color = accent,
		Material = Enum.Material.Glass,
		Transparency = 0.25,
		Parent = model,
	})
	addLight(door, accent, 70, 2.4)
	return door
end

local function storyBoard(model, centre, text, accent)
	local post = newPart({
		Name = "StoryPost",
		Size = Vector3.new(4, 26, 4),
		Position = centre + Vector3.new(96, 13, 0),
		Color = Color3.fromRGB(58, 48, 74),
		Material = Enum.Material.Metal,
		Parent = model,
	})

	local board = newPart({
		Name = "StoryBoard",
		Size = Vector3.new(72, 26, 2),
		Position = centre + Vector3.new(96, 40, 0),
		Color = Color3.fromRGB(44, 38, 60),
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
	-- The same painted-plank text every sign in the world uses, so a board in here and a board in
	-- the Forest read as the same object. There is no NPC to say any of this -- see the note in
	-- `GameConfig.Expeditions` about why the walls do the talking.
	addPlankText(board, text, accent, { pixelsPerStud = 12, maxDistance = 420 })
	addLight(board, accent, 40, 1.4)
	return post, board
end

-- The way home. A `PortalGate` by NAME, because that is what `ZoneService.Init`'s one-shot scan of
-- `workspace.Zones` looks for -- which is the whole reason this map is parented in there. The
-- `TargetZone` attribute is read once at scan time and answered by a branch in that file.
local function exitGate(model, centre, accent)
	local frame = newPart({
		Name = "ExitFrame",
		Size = Vector3.new(84, 8, 8),
		Position = centre + Vector3.new(0, DOOR_H, -CHAMBER / 2 + 12),
		Color = Color3.fromRGB(58, 48, 74),
		Material = Enum.Material.Metal,
		Parent = model,
	})

	local gate = newPart({
		Name = "PortalGate",
		Size = Vector3.new(76, DOOR_H, 3),
		Position = centre + Vector3.new(0, DOOR_H / 2, -CHAMBER / 2 + 12),
		Color = accent,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
		Parent = model,
	})
	gate:SetAttribute("TargetZone", "ReturnFromExpedition")
	addLight(gate, accent, 80, 3)

	addPlankText(frame, "RETURN", accent, { pixelsPerStud = 10, maxDistance = 400 })
	return gate
end

-- ===== THE BUILD =====
function ExpeditionMap.Build(parent, expedition)
	local model = Instance.new("Model")
	model.Name = "Expedition_" .. expedition.key
	model:SetAttribute("MapVersion", ExpeditionMap.MAP_VERSION)
	model:SetAttribute("ExpeditionKey", expedition.key)

	local accent = expedition.core and expedition.core.color or Color3.fromRGB(120, 235, 150)
	local shell = Color3.fromRGB(48, 42, 66)
	local floorColour = Color3.fromRGB(34, 30, 48)
	local gap = ZoneKit.PORTAL_GAP

	local chamberCount = #expedition.stations + 1 -- one per station, plus the vault

	for index = 1, chamberCount do
		local centre = ExpeditionMap.GetChamberCentre(index)
		floorSlab(model, centre, floorColour)

		-- Side walls, both chambers' full depth.
		for _, side in ipairs({ -1, 1 }) do
			wall(model, "SideWall",
				centre + Vector3.new(side * (CHAMBER / 2), 0, 0), "z", CHAMBER, shell)
		end

		-- The near wall of chamber 1 and the far wall of the last chamber are solid: the route has
		-- two ends and neither of them is a hole.
		if index == 1 then
			wall(model, "EndWall", centre + Vector3.new(0, 0, CHAMBER / 2), "x", CHAMBER, shell)
		end
		if index == chamberCount then
			wall(model, "EndWall", centre + Vector3.new(0, 0, -CHAMBER / 2), "x", CHAMBER, shell)
		else
			-- The doorway into the NEXT chamber, punched in the shared wall.
			local zCentre = centre.Z - CHAMBER / 2 - WALL_T / 2
			doorwayWall(model, zCentre, gap, shell, accent)
			-- The last doorway before the vault is the sealed one.
			if index == chamberCount - 1 then
				sealedDoor(model, zCentre, gap, accent)
			end
		end

		local line = expedition.story and expedition.story[index]
		if line then
			storyBoard(model, centre, line, accent)
		end

		-- A lamp per chamber, so the rooms are lit from within rather than by the skybox.
		local lamp = newPart({
			Name = "ChamberLamp",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(10, 10, 10),
			Position = centre + Vector3.new(0, WALL_H - 22, 0),
			Color = accent,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = model,
		})
		addLight(lamp, accent, 180, 3)
	end

	-- The arrival pad, so a player who has just been teleported knows they landed rather than fell.
	local spawnCentre = ExpeditionMap.GetChamberCentre(1)
	local pad = newPart({
		Name = "ArrivalPad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.6, 56, 56),
		CFrame = CFrame.new(spawnCentre + Vector3.new(0, 0.8, CHAMBER / 2 - 40))
			* CFrame.Angles(0, 0, math.rad(90)),
		Color = accent,
		Material = Enum.Material.Neon,
		Parent = model,
	})
	addLight(pad, accent, 60, 2)

	exitGate(model, ExpeditionMap.GetChamberCentre(chamberCount), accent)

	model.Parent = parent
	-- Never streamed out. The map is small, it is entered by teleport rather than walked up to, and
	-- a player who arrives before the floor does falls out of the world -- which is exactly what
	-- `StreamingIntegrityMode` was set to guard against everywhere else.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	return model
end

-- Kept out of `ZoneBuilder` for the reason the whole file is: it stamps and rebuilds ITSELF.
function ExpeditionMap.EnsureBuilt(parent, expedition)
	local name = "Expedition_" .. expedition.key
	local existing = parent:FindFirstChild(name)
	if existing and existing:GetAttribute("MapVersion") ~= ExpeditionMap.MAP_VERSION then
		warn(("[ExpeditionMap] rebuilding %s: stamp %s -> %d")
			:format(name, tostring(existing:GetAttribute("MapVersion")), ExpeditionMap.MAP_VERSION))
		existing:Destroy()
		existing = nil
	end
	if not existing then
		existing = ExpeditionMap.Build(parent, expedition)
		print(("[ExpeditionMap] built %s v%d (%d parts)")
			:format(name, ExpeditionMap.MAP_VERSION, #existing:GetDescendants()))
	end
	return existing
end

return ExpeditionMap
