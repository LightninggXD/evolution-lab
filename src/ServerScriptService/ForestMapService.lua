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
-- THE ZONE IS THREE BANDS, AND THE MAP IS ONLY THE MIDDLE ONE
-- =====================================================================================
-- The first cut of this file cut the hunting glade INTO the map, and that was wrong twice over.
-- The village floor is 682 x 580 and the ellipse took a bite out of its southern quarter, so the
-- thing the owner asked to have in the game was the thing being deleted; and the map's own mountain
-- ring reaches z = 438, which is 72 studs PAST the spawn -- so the arrival end of the zone was
-- inside a mountain. Measured live, not argued: the player stood at (-28, 5, 329) on the HubPlaza
-- deck with `Meshes/gora` 106 studs over her head and no way out, because a raycast started inside
-- a part does not hit it and every probe therefore reported open ground.
--
-- The zone is 1250 x 1150 and it now runs, +z to -z, in three bands:
--
--     z  575 .. 300   ARRIVAL   portal in, ZonePad, the one SpawnLocation at z = 366, HubPlaza
--     z  300 .. -330  VILLAGE   the map, whole and uncut -- this is the zone
--     z -330 .. -575  HUNT      forest planted behind the village, and every creature in it
--
-- So the walk is arrive -> village -> hunt -> exit gate, which is the shape the street always had,
-- and the player spawns ON ONE SIDE of the map looking into it rather than under it.
--
-- WHAT THE MAP LOSES IS THREE MOUNTAINS AND NOTHING ELSE. The clear list is checked by FOOTPRINT
-- OVERLAP, not by centre: a mountain centred at z = 268 reaches z = 418, and a centre test keeps it
-- standing over the plaza. It is also a fraction rather than a touch -- the western mountain pokes
-- 7 studs into the plaza's corner out at x = -407 and is scenery there, so the rule is "a fifth of
-- your footprint is in the band" and that number is what separates the two.
--
-- IT IS CUT BY WHOLE PROPS, NEVER BY PARTS. Half a tree left standing because its trunk fell
-- outside the band and its canopy inside is the thing that reads as broken, and a part-wise cut
-- produces dozens of them.
--
-- =====================================================================================
-- THE HUNT FOREST IS PLANTED, AND IT IS PLANTED WITH THE MAP'S OWN TREES
-- =====================================================================================
-- Behind the village is bare platform, and 74 creatures standing on bare platform is the "random
-- shapes on a floor" the whole look pass exists to remove. The trees are cloned out of the map's
-- own stock -- 119 of its children are tree-shaped -- so the hunt band is made of the same art as
-- the village and cannot drift from it.
--
-- NOTHING PLANTED HERE COLLIDES. A `MeshPart` at `CollisionFidelity.Default` is a handful of convex
-- hulls, and a 64-stud canopy's hull is very close to a 64-stud box: a hundred of them in the band
-- the player has to fight in is a hundred chances to repeat the mountain. They are backdrop, so
-- they are `CanCollide = false` and the band stays walkable.

local ServerStorage = game:GetService("ServerStorage")

-- Only for PLATFORM_WIDTH / PLATFORM_DEPTH, which is where a zone's share of the shell is defined.
-- ZoneKit is a live sibling module and this runs after `ZoneBuilder.Build()`, so it is already
-- required and cached by the time anything here calls it.
local ZoneKit = require(script.Parent.ZoneKit)

local ForestMapService = {}

-- See the header: this is the player's size, not a fitting factor.
local SCALE = 1.45

-- One entry per zone that has a map. The table exists so the second one costs a row rather than a
-- rewrite -- and so the bands, which are the only hand-tuned numbers here, are visible in one place.
local MAPS = {
	Forest = {
		source = "ForestVillage",
		scale = SCALE,
		-- Bands, in zone-relative studs, the map may not stand in. See the header: the first is the
		-- arrival end (spawn is at z = 366) and the second is the hunting ground behind the village.
		clear = {
			{ x1 = -230, x2 = 230, z1 = 300, z2 = 620 },
			-- -300 rather than -330, and the 30 studs are load-bearing: two of the ring's mountains
			-- reach z = -378 and -394 with their feet, which at -330 scored 0.147 and stayed --
			-- a wall across the mouth of the hunting ground at x = -250, -120 and 250, measured by
			-- walking a grid over it. At -300 they score 0.24 and go, and the only village prop that
			-- goes with them is one tree on the southern fringe.
			{ x1 = -620, x2 = 620, z1 = -620, z2 = -300 },
		},
		-- The forest planted behind the village. `lane` is the half-width of the street kept open
		-- down the middle: the exit gate is at z = -575 and a tree line across it is a wall.
		hunt = { zNear = -335, zFar = -560, xEdge = 590, lane = 78 },
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

-- THE ZONE'S DRESSING IS NOT ALL IN THE ZONE. `WorldShell` pins ~2,000 parts against streaming by
-- REPARENTING them out of the zone model, so the drop pass above -- which walks `zoneModel` -- never
-- sees them. Sixty-eight of Forest's were still standing after the map went in: 36 `TerraceTop`
-- shelves (the ones `CreatureService.raisedSpots` kept finding, invisible under the map), 6
-- `TerraceRamp` flights, a landmark plinth colonnade down the hunting ground's western side and two
-- pool beds. Same names, same rules, same `NEVER_DROP` -- so `Floor` is safe, and it has to be,
-- because the shell's `Floor` IS this zone's ground.
--
-- Bounded by the platform rather than by the map: the shell is one flat folder for the whole world
-- and a zone's share of it is "everything standing on my platform".
local function dropShellDressing(cx)
	local shell = workspace:FindFirstChild("WorldShell")
	if not shell then return 0 end
	local halfX, halfZ = ZoneKit.PLATFORM_WIDTH / 2, ZoneKit.PLATFORM_DEPTH / 2
	local dropped = 0
	for _, c in ipairs(shell:GetChildren()) do
		local pos
		if c:IsA("BasePart") then
			pos = c.Position
		elseif c:IsA("Model") then
			pos = c:GetBoundingBox().Position
		end
		if pos and math.abs(pos.X - cx) <= halfX and math.abs(pos.Z) <= halfZ and isDressing(c.Name) then
			c:Destroy()
			dropped += 1
		end
	end
	return dropped
end

-- A prop's footprint against one band, as a fraction of the prop's own footprint. Two overlaps
-- multiplied is the shared AREA, which is what makes the west mountain (deep overlap in z, seven
-- studs of it in x) score 0.06 and stay standing while the one over the plaza scores 0.49 and goes.
local function overlapFraction(pos, size, cx, band)
	local function span(lo1, hi1, lo2, hi2)
		return math.max(math.min(hi1, hi2) - math.max(lo1, lo2), 0)
	end
	if size.X <= 0 or size.Z <= 0 then return 0 end
	local fx = span(pos.X - size.X / 2, pos.X + size.X / 2, cx + band.x1, cx + band.x2) / size.X
	local fz = span(pos.Z - size.Z / 2, pos.Z + size.Z / 2, band.z1, band.z2) / size.Z
	return fx * fz
end

local CLEAR_SHARE = 0.2

local function clearBands(map, cx, bands)
	local cleared = 0
	for _, c in ipairs(map:GetChildren()) do
		-- MainPart is the ground the bands are measured over and Terrain is what their far edge is
		-- read against; neither is scenery and neither may be cut.
		if c.Name ~= "MainPart" and c.Name ~= "Terrain" then
			local pos, size
			if c:IsA("Model") then
				local cf, s = c:GetBoundingBox()
				pos, size = cf.Position, s
			elseif c:IsA("BasePart") then
				pos, size = c.Position, c.Size
			end
			if pos then
				for _, band in ipairs(bands) do
					if overlapFraction(pos, size, cx, band) >= CLEAR_SHARE then
						c:Destroy()
						cleared += 1
						break
					end
				end
			end
		end
	end
	return cleared
end

-- A tree, for the purposes of this file, is a top-level child holding a mesh named `Top` -- the
-- name the source's own foliage uses, 181 of them across the map. Sized 30..110 so the planting
-- draws from real trees and not from the one 123-stud specimen or from a shrub.
local function treeStock(map)
	local stock = {}
	for _, c in ipairs(map:GetChildren()) do
		if c:IsA("Model") then
			local isTree = false
			for _, d in ipairs(c:GetDescendants()) do
				if d:IsA("MeshPart") and d.Name == "Top" then
					isTree = true
					break
				end
			end
			if isTree then
				local _, size = c:GetBoundingBox()
				if size.Y >= 30 and size.Y <= 110 then
					stock[#stock + 1] = c
				end
			end
		end
	end
	return stock
end

-- Stands one clone with its FEET on y = 0. The bounding box has to be re-read after the yaw,
-- because a rotated tree is a different box and seating it on the box it had before the turn is
-- how a trunk ends up half a stud in the air.
local function plantOne(proto, parent, x, z, rng)
	local t = proto:Clone()
	t:ScaleTo(rng:NextNumber(0.82, 1.28))
	t:PivotTo(t:GetPivot() * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	local cf, size = t:GetBoundingBox()
	t:PivotTo(t:GetPivot()
		+ Vector3.new(x - cf.Position.X, -(cf.Position.Y - size.Y / 2), z - cf.Position.Z))
	for _, d in ipairs(t:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			-- see the header: planted foliage is backdrop, and backdrop that collides is a trap
			d.CanCollide = false
			d.CastShadow = false
		end
	end
	t.Name = "HuntTree"
	t.Parent = parent
	return t
end

-- The band behind the village: a back wall of trees, two flanks, and clumps in the middle. The
-- middle is deliberately sparse -- this is the ground 74 creatures stand and are fought on, so it
-- is a CLEARING with trees in it rather than a wood, which is the 30.12 rule read from the inside.
local function plantForest(map, cx, hunt)
	local stock = treeStock(map)
	if #stock == 0 then return 0 end

	local folder = Instance.new("Folder")
	folder.Name = "HuntForest"
	folder.Parent = map

	-- Seeded off the zone rather than off the clock: two servers of the same place have to grow the
	-- same forest, for the same reason `CreatureService` seeds its raised spots that way.
	local rng = Random.new(20260822 + math.floor(cx))
	local planted = 0
	local function plant(x, z)
		plantOne(stock[rng:NextInteger(1, #stock)], folder, cx + x, z, rng)
		planted += 1
	end

	-- 1. the back wall, broken for the street down to the exit gate
	local x = -hunt.xEdge
	while x <= hunt.xEdge do
		if math.abs(x) > hunt.lane then
			plant(x + rng:NextNumber(-16, 16), hunt.zFar + rng:NextNumber(-14, 26))
			if rng:NextNumber() < 0.55 then
				plant(x + rng:NextNumber(-24, 24), hunt.zFar + rng:NextNumber(28, 62))
			end
		end
		x += 34
	end

	-- 2. the two flanks, which are what stop the band reading as a corridor
	for _, side in ipairs({ -1, 1 }) do
		local z = hunt.zFar
		while z <= hunt.zNear do
			plant(side * rng:NextNumber(hunt.xEdge - 150, hunt.xEdge), z + rng:NextNumber(-18, 18))
			if rng:NextNumber() < 0.7 then
				plant(side * rng:NextNumber(hunt.xEdge - 240, hunt.xEdge - 120),
					z + rng:NextNumber(-22, 22))
			end
			z += 38
		end
	end

	-- 3. clumps in the open middle -- at the foot of each other, never sprinkled evenly, which is
	--    the one rule that separates a planted wood from scattered decor
	for _ = 1, 16 do
		local ox = rng:NextNumber(-(hunt.xEdge - 190), hunt.xEdge - 190)
		local oz = rng:NextNumber(hunt.zFar + 40, hunt.zNear - 30)
		if math.abs(ox) > hunt.lane + 30 then
			for _ = 1, rng:NextInteger(2, 4) do
				plant(ox + rng:NextNumber(-34, 34), oz + rng:NextNumber(-30, 30))
			end
		end
	end

	return planted
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
			dropped += dropShellDressing(cx)

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
				local cleared = spec.clear and clearBands(map, cx, spec.clear) or 0
				local planted = spec.hunt and plantForest(map, cx, spec.hunt) or 0
				print(("[ForestMapService] %s: dropped %d dressing, laid %d map parts at x%.2f, "
					.. "cut %d props for the arrival and hunt bands, planted %d trees behind the village")
					:format(zoneKey, dropped, #map:GetDescendants(), spec.scale, cleared, planted))
			end
		end
	end
end

return ForestMapService
