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

-- The map's own furniture, published by role. See MapProps/MapAnchors for why that is a separate
-- module rather than another section of this file: the census has to run between parenting the map
-- and cutting the bands, and every consumer of it lives in a different service.
local MapAnchors = require(script.Parent.MapProps.MapAnchors)
local MapForest = require(script.Parent.MapProps.MapForest)
-- 31.16: the hunting ground stopped being a green slab with trees on it. `MapJungle` builds the
-- rock alcoves, the path network and the ridge line; `JungleLayout` (which it reads, and which
-- `CreatureService` reads too) owns every coordinate involved.
local MapJungle = require(script.Parent.MapProps.MapJungle)
local MapRoad = require(script.Parent.MapProps.MapRoad)

local ForestMapService = {}

-- ===== 31.14: THE SCALE CAME DOWN, AND THE HEADER ABOVE IS NOW HALF TRUE =====
-- 1.45 made a doorway read to our 8.4-stud player exactly as it read to the 5.7-stud avatar the
-- artist drew it for. That was the correct answer to "does the map fit the body" and it is not the
-- answer the owner wanted: *"ostatak mape isto tako dosta dosta manje"*, on a screenshot of the
-- square. A village drawn at the player's own scale is a village the player is merely IN. She is
-- building a game where the player LOOMS -- the reference art is a chunky body among small chunky
-- props -- so the map is deliberately drawn a fifth smaller than the body now, not equal to it.
--
-- 1.15 rather than 1.0: at 1.0 the props are the artist's own size against a body 47% taller than
-- the one they were drawn for, and the gaps between houses, fences and stalls close to about six
-- studs, which is under the player's own 9-stud box. 1.15 is the largest visible step down that
-- keeps every gap the walk probe measured open. If it is still too big the next stop is 1.0 and the
-- probe has to be re-run, not assumed.
--
-- EVERYTHING BELOW THAT USED TO BE A MEASURED CONSTANT NOW HANGS OFF IT. The village floor's half
-- extents scale with the map (it IS part of the map), and the bands were authored against the
-- floor's edge -- so at a new scale a hand-typed -300 leaves a 60-stud ring of bald platform
-- between the last house and the first tree, which is exactly the fault 31.4 was opened to fix.
local SCALE = 1.15

-- The village floor (`MainPart`) measured 682 x 580 in the placed 1.45 map, so its half extents are
-- 235.2 x 200 per unit of scale. Written as a derivation rather than re-measured, because the two
-- numbers below are the only thing every band in this file is positioned against.
local FLOOR_HALF_X = 235.2 * SCALE
local FLOOR_HALF_Z = 200 * SCALE

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
			{ x1 = -620, x2 = 620, z1 = -620, z2 = -(FLOOR_HALF_Z + 10) },
			-- 31.4: THE TWO SIDE POCKETS. The ring also stands down both flanks of the village, on the
			-- ~280 studs of platform beyond the floor's edge at x +/-341. That is the ground the wood is
			-- widened into, so the arcs south of the square go the way the southern arc did. Stopped at
			-- z = +150 so the ring still closes the horizon behind the arrival plaza, which is the one
			-- place it is doing scenery work rather than standing in the way.
			{ x1 = -620, x2 = -(FLOOR_HALF_X + 4), z1 = -620, z2 = 150 },
			{ x1 = FLOOR_HALF_X + 4, x2 = 620, z1 = -620, z2 = 150 },
		},
		-- The forest planted behind the village. `lane` is the half-width of the street kept open
		-- down the middle: the exit gate is at z = -575 and a tree line across it is a wall.
		-- 31.4 PULLED `zNear` FORWARD FROM -335 TO -300 and left the rest alone. The trees now start
		-- where the village floor ends rather than 35 studs behind it, which is what removes the bald
		-- ring the owner's screenshots show between the last house and the first tree.
		hunt = { zNear = -(FLOOR_HALF_Z + 5), zFar = -560, xEdge = 590, lane = 78 },
		-- ===== THE TWO SIDE POCKETS (31.4) =====
		-- The village floor is 682 x 580 and the platform is 1250 x 1150, so beyond the floor's edge
		-- at x +/-341 there is ~280 studs of bare platform down each side, running the whole depth of
		-- the zone. The map's mountain ring was standing on it; the southern arcs are cleared below,
		-- and this is what plants the ground that frees up. It is the owner's *"samo siri mapu sa
		-- njim da stanu svi mobovi i boss"* -- the wood stops being a strip behind the village and
		-- wraps around it, which roughly triples the ground 74 creatures and a boss have to share.
		--
		-- `zNear` stops at +150 rather than at the arrival band: north of that the pockets are beside
		-- the plaza, and a tree wall there closes in the one part of the zone meant to read as sky.
		flanks = { xIn = FLOOR_HALF_X + 18, xOut = 600, zNear = 150, zFar = -560 },
		-- The way IN. See the header: the map's northern half is solid wood and the village square
		-- is behind it, so without this the plaza opens onto a hedge. Tapered, wide end at the
		-- plaza -- a funnel reads as an entrance and a rectangle reads as a firebreak.
		entrance = { zNear = 30, zFar = 312, halfNear = 72, halfFar = 108 },
		-- Published so no consumer ever re-measures the village. `MapJungle`, `JungleLayout` and
		-- `CreatureService` all need to know where the houses stop and the open ground starts, and
		-- `evolution-lab-zone-geometry-constants` is the standing lesson about what happens when
		-- that is one decision written in four files.
		floorHalfX = FLOOR_HALF_X,
		floorHalfZ = FLOOR_HALF_Z,
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

-- `protected` is MapAnchors' set of furniture instances. An anchor is not scenery and is never cut
-- by a band, even standing in one -- the alternative is a service asking for a shop that the band
-- pass deleted eight lines earlier, which surfaces as a nil anchor and reads as a rename.
local function clearBands(map, cx, bands, protected)
	local cleared = 0
	for _, c in ipairs(map:GetChildren()) do
		-- MainPart is the ground the bands are measured over and Terrain is what their far edge is
		-- read against; neither is scenery and neither may be cut.
		if c.Name ~= "MainPart" and c.Name ~= "Terrain" and not (protected and protected[c]) then
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

-- Foliage, as opposed to the village. Two tests, because the source names its greenery two ways:
-- by name (`Pine Tree 02`, `Bush2`, `Rock 01`, `Trunk 01`, `Leaves`) and by shape -- 60 of the
-- trees in the northern wood are called nothing but `Model`, and what identifies them is that every
-- part they own is `Top` / `Bottom` / `Leaves` / `Branch`. A prop with anything else in it is a
-- building, a stall or a pedestal and is never touched by this.
local FOLIAGE_PREFIX = { "Pine Tree", "Tree", "Bush", "Flower", "Rock", "Trunk", "Leaves", "Shrub" }
local FOLIAGE_PART = { Top = true, Bottom = true, Leaves = true, Branch = true }

local function isFoliage(c)
	for _, p in ipairs(FOLIAGE_PREFIX) do
		if c.Name:sub(1, #p) == p then return true end
	end
	if not c:IsA("Model") then return false end
	local leafy, other = 0, 0
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("BasePart") then
			if FOLIAGE_PART[d.Name] then leafy += 1 else other += 1 end
		end
	end
	return leafy > 0 and other == 0
end

-- Cuts the road from the plaza to the village square. THE TEST IS THE PROP'S CENTRE, not its
-- footprint, and that is the difference between a road and a trench: a tree rooted outside the
-- corridor with its canopy hanging over it is what a road through a wood looks like, and clearing
-- by footprint would take every one of them and leave two straight walls.
--
-- Anything under 5 studs tall stays. Flowers and flat rocks do not block a walk and do not hide a
-- doorway, and a road scrubbed down to bare ground reads as a demolition rather than a path.
local function cutEntrance(map, cx, e, protected)
	local cleared = 0
	for _, c in ipairs(map:GetChildren()) do
		-- The protected test is load-bearing HERE in a way it is not in clearBands: the egg row sits
		-- at zone z 91..116, inside this funnel, and `isFoliage` classifies by PART NAME as well as
		-- by prop name -- a prop whose parts are all Top / Bottom / Leaves / Branch is foliage to it
		-- whatever it actually is. Without this, the road is cut straight through the shop.
		if c.Name ~= "MainPart" and c.Name ~= "Terrain"
			and not (protected and protected[c]) and isFoliage(c) then
			local pos, size
			if c:IsA("Model") then
				local cf, s = c:GetBoundingBox()
				pos, size = cf.Position, s
			elseif c:IsA("BasePart") then
				pos, size = c.Position, c.Size
			end
			if pos and size.Y >= 5 and pos.Z >= e.zNear and pos.Z <= e.zFar then
				local t = (pos.Z - e.zNear) / (e.zFar - e.zNear)
				local half = e.halfNear + (e.halfFar - e.halfNear) * t
				if math.abs(pos.X - cx) <= half then
					c:Destroy()
					cleared += 1
				end
			end
		end
	end
	return cleared
end

-- The spec for a mapped zone, so a consumer can read the entrance corridor rather than copying its
-- four numbers. `MapEggs` is the first caller and the reason this exists: the corridor is the one
-- piece of geometry another module has to agree with exactly, and `evolution-lab-zone-geometry-
-- constants` is the standing lesson about one decision written in two files.
function ForestMapService.GetSpec(zoneKey)
	return MAPS[zoneKey]
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
				-- BEFORE the cuts, and that ordering is why the census is one line here rather
				-- than a pass at the end: the cuts need the protected set, and the set does not
				-- exist until the census has walked the placed map.
				local protected = MapAnchors.Collect(zoneKey, map)
				local cleared = spec.clear and clearBands(map, cx, spec.clear, protected) or 0
				local road = spec.entrance and cutEntrance(map, cx, spec.entrance, protected) or 0
				local planted = MapForest.Plant(map, cx, spec)
				-- AFTER the planting, and that ordering matters: the ridge hills and the alcove
				-- rocks are placed against authored coordinates, but the trees are scattered, and a
				-- tree grown where a rock already stands is a tree with a rock in it. Planting first
				-- means the wood is the thing that gets interrupted, which is what a wood does.
				local camps = MapJungle.Build(zoneKey, cx, map)
				-- LAST, and after the cut rather than before it. The approach road is paint laid
				-- over whatever the entrance band left standing, so it has to be drawn on the
				-- finished ground -- `evolution-lab-placement-search-ordering` is the standing note
				-- that a pass only ever knows the world that existed when it ran.
				local paved = MapRoad.Build(zoneKey, cx, map)
				print(("[ForestMapService] %s: dropped %d dressing, laid %d map parts at x%.2f, "
					.. "cut %d props for the arrival and hunt bands, %d for the entrance road, "
					.. "planted %d trees behind the village, built %d jungle camps, "
					.. "paved %d road parts")
					:format(zoneKey, dropped, #map:GetDescendants(), spec.scale, cleared, road,
						planted, camps, paved))
				print("[MapAnchors] " .. MapAnchors.Describe(zoneKey))
			end
		end
	end
end

return ForestMapService
