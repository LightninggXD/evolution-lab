-- ForestMapService -- a zone whose ground is a hand-built map instead of ZoneBuilder's valley.
--
-- Kristina inserted a free village map and asked for zone 1 to BE it: *"uzmi taj model i dodaj ga
-- da bude forrest ... samo uzmi odatle i promeni sa forrestom"*. This is that, in code, which is
-- the only form of it that survives -- an Edit-time build is discarded the moment `ZoneBuilder`
-- rebuilds, and it rebuilds on every Play.
--
-- =====================================================================================
-- WHY THIS IS A SERVICE AND NOT A ZoneBuilder BRANCH
-- =====================================================================================
-- `ZoneBuilder` is TWO REGISTERS from Luau's 200-local cap (`evolution-lab-zonebuilder-edit-wall`),
-- and a branch inside `Build()` would want a name for the source, the scale, the glade and the keep
-- list. It also does not need to be in there: this runs AFTER the zone is built and edits it, which
-- is exactly the shape `ExtraProps`, `HubPlaza` and the leaderboards already use. Zero ZoneBuilder
-- edits, and if this file is removed the zone simply comes back as it was.
--
-- =====================================================================================
-- 1.45 IS NOT A FIT. IT IS THE BODY.
-- =====================================================================================
-- The map is drawn around a stock 5.7-stud Roblox avatar. 30.14 froze our player at 1.45x one
-- (`EvolutionVisuals.FIXED_BODY_SCALE` through `PLAYER_SCALE_BOOST`), so scaling the map by that
-- same 1.45 is what makes a doorway, a fence and a market stall read to our player exactly as they
-- read to the avatar the artist drew them for. That the result -- 1208 x 972 -- then lands inside
-- the 1250 x 1150 platform is luck, not design; it is what makes the swap possible at all.
--
-- IF THE BODY EVER CHANGES, THIS NUMBER MOVES WITH IT. They are the same decision written twice,
-- and there is no way to share the constant without a server module reaching into another one at
-- build time, so the rule is written here instead: `SCALE` = whatever `FIXED_BODY_SCALE` x
-- `PLAYER_SCALE_BOOST` is.
--
-- =====================================================================================
-- THE STRIP IS A DROP LIST, NOT A KEEP LIST, AND THAT IS DELIBERATE
-- =====================================================================================
-- The first pass at this was a KEEP list and it destroyed the zone's `Floor` -- which is the
-- model's own `PrimaryPart` -- because "Floor" was not on it. A keep list fails CLOSED: anything
-- it has not heard of is deleted, so every prop any future service stands in a zone would have to
-- be added to a list in this file or silently vanish on the next server start.
--
-- The drop list fails OPEN. It names only ZoneBuilder's own dressing prefixes, taken from a census
-- of the live zone (3,693 children), and anything it does not recognise survives untouched. A new
-- prop from a service written next month is safe by default; the worst this can do is leave a
-- ZoneBuilder tuft standing in the village, which is visible and harmless.
--
-- =====================================================================================
-- THE MAP HAS ONE CLEARING AND A ZONE NEEDS TWO
-- =====================================================================================
-- Everything in the source that is not the village is solid forest, so "mobs on one side" is a CUT
-- rather than a placement. The glade is an ellipse on the -z half -- the half the exit gate and the
-- boss clearing are already on, so the walk through the zone stays village -> hunt -> exit, which
-- is the shape the street always had.
--
-- IT IS CUT BY WHOLE PROPS, NEVER BY PARTS. Half a tree left standing because its trunk fell
-- outside the ellipse and its canopy inside is the thing that reads as broken, and a part-wise cut
-- produces dozens of them.

local ServerStorage = game:GetService("ServerStorage")

local ForestMapService = {}

-- See the header: this is the player's size, not a fitting factor.
local SCALE = 1.45

-- One entry per zone that has a map. The table exists so the second one costs a row rather than a
-- rewrite -- and so the glade, which is the only hand-tuned number here, is visible in one place.
local MAPS = {
	Forest = {
		source = "ForestVillage",
		scale = SCALE,
		-- ellipse, in zone-relative studs, on the far side of the village
		glade = { x = 0, z = -200, a = 300, b = 135 },
	},
}

-- ZoneBuilder's dressing, by name prefix, censused off the live zone. Everything here is scenery
-- the map replaces; everything NOT here survives, which is the whole point (see the header).
--
-- `Idol` and `Titan` are on this list for a different reason from the rest. They are not dressing,
-- they are landmarks -- but they were sized for a body that reached 41 studs, and the Guardian
-- Titan is 486 x 545. Against the fixed 8.3-stud body they are the "everything is enormous next to
-- me" complaint in a single object, so a zone that has a map does not get them.
local DROP_PREFIX = {
	"Terrace", "Cliff", "Backdrop", "Mesa", "Rampart", "Ground", "Path", "Fence", "Pennant",
	"Bunting", "Banner", "Scallop", "Knob", "Column", "Flower", "Vill", "Fall", "Valley",
	"ForestTree", "Pool", "PortalRune", "Tree", "Rock", "Shroom", "Tuft", "Stair", "Step",
	"Lamp", "Bush", "Grass", "Idol",
	-- The furniture the map brings its own of. These are not ZoneBuilder's ground dressing -- they
	-- are the generated VILLAGE (a well, benches, planters, crates, lanterns, banners, an arch)
	-- plus `ExtraProps`' hand-placed pieces, and the first live build left every one of them
	-- standing inside or on top of the map. A village drawn twice reads as a bug, not as detail.
	"Guardian", "Landmark", "Ruin", "Well", "Bench", "Crate", "Glint", "Glow", "Planter",
	"Mushroom", "Arch", "Crag", "Prop",
}

-- ...and the names a prefix cannot reach. `GuardianTitan` is the reason this list exists: the drop
-- rule anchors at the START of the name (see the note below), so "Titan" never matched it and a
-- 486 x 545-stud bear stood over the village on the first live build. Anchoring is still right --
-- a substring "Titan" would be a trap for any future `TitanShrine` a service adds -- so the fix is
-- to name the exceptions rather than to loosen the rule.
local DROP_EXACT = {
	GuardianTitan = true, TitanFigure = true, TitanPlinth = true, TitanPlinthTrim = true,
	TitanBrazier = true, TitanFlame = true,
}

-- The four names that MUST survive whatever the drop list says. Three of them start with a dropped
-- prefix by coincidence and the fourth is the model's PrimaryPart; getting any of them wrong is a
-- zone with no floor or a portal that leads nowhere.
local NEVER_DROP = {
	Floor = true, PortalGate = true, ZonePad = true, SpawnLocation = true,
}

local function isDressing(name)
	if NEVER_DROP[name] then return false end
	if DROP_EXACT[name] then return true end
	for _, p in ipairs(DROP_PREFIX) do
		if name:sub(1, #p) == p then return true end
	end
	return false
end

-- Prefix, not `find`: `PortalNameBoard` and `PortalRune` share eleven characters, and a substring
-- match on "Portal" would take the sign down with the runes. Anchoring at the start is what keeps
-- `GroundPatch` (dressing) apart from nothing else, and `TerraceTree` apart from a future
-- `TreeOfLifeShrine` -- which is also why `Tree` sits in the list rather than `TerraceTree`.

local function sanitise(model)
	-- The SOURCE in ServerStorage is already stripped of Scripts, prompts and SpawnLocations, so
	-- this is a belt-and-braces pass over the clone rather than the real defence. It is kept because
	-- the source is a saved instance in the place file and a re-inserted free model would arrive
	-- with all of it back (30.0: a Script under Workspace EXECUTES, and this one shipped eight
	-- SpawnLocations that would have stolen every arrival in the game).
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
			d:Destroy()
		elseif d:IsA("SpawnLocation") then
			d:Destroy()
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
end

-- Seated by the VILLAGE FLOOR, not by the bounding box. The bounding box takes in a mountain ring
-- that reaches ~100 studs below the ground, so centring on it sinks the whole village by fifty.
local function seat(map, cx)
	local floor
	for _, c in ipairs(map:GetChildren()) do
		if c.Name == "MainPart" then floor = c break end
	end
	if not floor then return nil end
	local top = floor.Position.Y + floor.Size.Y / 2
	map:PivotTo(map:GetPivot()
		+ Vector3.new(cx - floor.Position.X, 0 - top, 0 - floor.Position.Z))
	return floor
end

local function cutGlade(map, cx, glade)
	local cleared = 0
	for _, c in ipairs(map:GetChildren()) do
		-- MainPart is the ground the glade is cut INTO and Terrain is what its far edge is read
		-- against; neither is scenery.
		if c.Name ~= "MainPart" and c.Name ~= "Terrain" then
			local cf
			if c:IsA("Model") then
				cf = c:GetBoundingBox()
			elseif c:IsA("BasePart") then
				cf = c.CFrame
			end
			if cf then
				local dx = (cf.Position.X - (cx + glade.x)) / glade.a
				local dz = (cf.Position.Z - glade.z) / glade.b
				if dx * dx + dz * dz <= 1 then
					c:Destroy()
					cleared += 1
				end
			end
		end
	end
	return cleared
end

function ForestMapService.Init()
	local source = ServerStorage:FindFirstChild("Maps")
	if not source then
		-- Not an error and not a warning worth a stack: a place that has not had the map saved into
		-- it simply gets the zone ZoneBuilder built, which is a working zone.
		print("[ForestMapService] no ServerStorage.Maps -- zones keep their built dressing")
		return
	end

	local zonesFolder = workspace:FindFirstChild("Zones")
	if not zonesFolder then return end

	local GameConfig = require(game:GetService("ReplicatedStorage").Modules.GameConfig)

	for zoneKey, spec in pairs(MAPS) do
		local zoneModel = zonesFolder:FindFirstChild(zoneKey)
		local template = source:FindFirstChild(spec.source)
		if zoneModel and template then
			-- IDEMPOTENT, and it has to be: `Init` runs once per server, but a second call (a
			-- hot-reload, a future rebuild hook) must not stack a second 8,700-part map on the first.
			local already = zoneModel:FindFirstChild("VillageMap")
			if already then
				already:Destroy()
			end

			-- The zone's own centre line, read from config rather than from the model: a zone model
			-- built around a portal gate has a bounding box that is not centred on it.
			local cx = 0
			for _, z in ipairs(GameConfig.Zones) do
				if z.key == zoneKey then cx = z.offset or 0 break end
			end

			local dropped = 0
			for _, c in ipairs(zoneModel:GetChildren()) do
				if isDressing(c.Name) then
					c:Destroy()
					dropped += 1
				end
			end

			local map = template:Clone()
			map.Name = "VillageMap"
			sanitise(map)
			map:ScaleTo(spec.scale)
			local floor = seat(map, cx)
			if not floor then
				map:Destroy()
				warn(("[ForestMapService] %s: source has no MainPart -- left the built zone alone")
					:format(zoneKey))
			else
				map.Parent = zoneModel
				local cleared = spec.glade and cutGlade(map, cx, spec.glade) or 0
				print(("[ForestMapService] %s: dropped %d dressing, laid %d map parts at x%.2f, cut %d for the glade")
					:format(zoneKey, dropped, #map:GetDescendants(), spec.scale, cleared))
			end
		end
	end
end

return ForestMapService
