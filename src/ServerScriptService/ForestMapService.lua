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
local MapCut = require(script.Parent.MapProps.MapCut)
local MapGates = require(script.Parent.MapProps.MapGates)
local MapRidge = require(script.Parent.MapProps.MapRidge)
local MapHorizon = require(script.Parent.MapProps.MapHorizon)
local MapWaterfall = require(script.Parent.MapProps.MapWaterfall)
-- 32.28: the pass cut runs between Build and Plant below, and MapPortalArt disarms her inserted
-- ad-portal template and seats its island at the same gate.
local MapPass = require(script.Parent.MapProps.MapPass)
-- Review R1 fault 2 (32.28): the hole the cut opens gets its skyline back -- two stock shoulders
-- on the outer row's line behind the wall, plus the mouth crags moved out of `MapPass` so each
-- file keeps one purpose.
local MapPassDress = require(script.Parent.MapProps.MapPassDress)
local MapPortalArt = require(script.Parent.MapProps.MapPortalArt)
-- 32.30: her arch model replaces the built -Z gate art. The gate itself already exists here --
-- `ZoneBuilder.Build()` ran at ServerMain:82, this service at :93 -- so the pass can find the
-- `PortalGate` sheet, resize it into the arch's doorway and keep the teleport the scan wired.
local MapGateArch = require(script.Parent.MapProps.MapGateArch)
-- 32.30: the wall either side of the arch gets the mouth's own treatment -- stock crags leaning
-- on the slate, and two tall back-fills behind the arch so the slot above it reads as rock.
local MapGateFlanks = require(script.Parent.MapProps.MapGateFlanks)

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
			-- widened into, so the arcs south of the square go the way the southern arc did.
			--
			-- 30.23 RAN THEM TO z = 430, WHERE 31.4 STOPPED THEM AT 150. The 150 was correct while the
			-- two north quadrants were bare platform nobody walked on: the ring was closing the horizon
			-- behind the arrival plaza, which is the one place it was doing scenery work. It is not
			-- correct now that those quadrants are wood with ten camps in them. MEASURED, on the boot
			-- this row was opened by: the two arrival mountains span x 135..319 and z 94..343, and a
			-- body-box walk from the ring road to NW1, NE1 and NE3 was stopped by `Meshes/gora` on 8 of
			-- 226 cells -- a mountain across the approach to three camps, which is 30.19 exactly. At
			-- 430 both score 0.25 against `CLEAR_SHARE` and go; the horizon they were holding is
			-- `MapJungle`'s own flank ridge, which now runs north to z = 480 for this reason.
			{ x1 = -620, x2 = -(FLOOR_HALF_X + 4), z1 = -620, z2 = 430 },
			{ x1 = FLOOR_HALF_X + 4, x2 = 620, z1 = -620, z2 = 430 },
		},
		-- ===== THE WOOD IS THE WHOLE PLATFORM NOW (30.23) =====
		-- `hunt` (a band behind the village) and `flanks` (two side pockets) are gone. The owner
		-- asked for trees over the whole map -- *"puno drveca po celoj mapi ... ko u amazonu"* --
		-- and four quadrants of it around a cross of roads, so `MapForest` scatters over this whole
		-- rectangle and subtracts what must stay open rather than being told where wood goes. See
		-- that file's header for why the question is inverted.
		--
		-- `spacing` IS THE ONE DIAL AND IT WAS TURNED TWICE, both times against a capture rather than
		-- an opinion: 30 gave 464 trees over the whole platform and photographs as clumps of wood
		-- with fields of bare green between them, 24 gave 758 and still showed lawn between the
		-- camps, 20 gives ~1,100 on 2 parts each. The trees are `CanCollide` and `CanQuery` false,
		-- so the only cost of another thousand is drawing them.
		--
		-- ===== THE EDGES USED TO BE A GUESS AT THE RIDGE, AND 31.24 ENDED THAT =====
		-- They were 565 / 500 / -505, and the note here said so plainly: the ridge was laid on
		-- x = +/-630 after the planting, so the planter could not ask where it was and had to be
		-- told to stop short of it. A tree planted past those lines was a tree inside a mountain
		-- and nothing would ever have said so.
		--
		-- `MapHorizon` now runs BEFORE this and publishes `Footprints`, which the planter subtracts
		-- per hill -- so the wood no longer has to stop at a line at all. It runs to the platform's
		-- own edge and BREAKS AROUND each mountain, which is what a wood at the foot of a range
		-- looks like and is 45 studs of bare ground per side reclaimed on every flank.
		--
		-- Held 15 short of the boundary wall (|x| 625, |z| 575) rather than run right up to it: a
		-- canopy is planted on its trunk, so a trunk at the wall puts half a crown through it.
		forest = { xEdge = 610, zNorth = 560, zSouth = -560, spacing = 16 },
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
	-- ===== AND THE ONE GROUND NAME THE LIST MISSED, FOUND BY WALKING THE ROADS (32.4) =====
	-- `Ground`, `Rock`, `Tree`, `Bush`, `Grass`, `Tuft`, `Pool`, `Flower` and `Shroom` are all on
	-- this list because the map brings its own. `Mound` is the same thing by the same argument --
	-- `BiomeDecor.addMounds` lays wide low relief so a bare platform is not a plane, and a platform
	-- under a village and 5,354 trees is not bare -- and it was the ONLY one left. Measured after
	-- everything else in this row was fixed: nine of them standing inside the Forest platform, the
	-- only solid non-map thing on it besides the boundary wall, the two portal gates and the eggs.
	--
	-- IT IS A LOTTERY, WHICH IS WHY IT SURVIVED FOUR PHASES OF PROBES. A mound is 36..60 studs
	-- across and 6..9 tall, `ZoneKit.SOLID_PROPS` deliberately makes it collide (11.21: "a player
	-- who walks through a crate stack is being told the world is a painting"), and
	-- `ScatterKit.scatterPoint` places it with an UNSEEDED `math.random` against ZoneBuilder's own
	-- geography -- the street at |x| >= 48, the centre, the arrival gate, the boss. It knows nothing
	-- about the three lanes `MapGates` paints or the twenty-three roads `JungleLayout` owns, because
	-- those did not exist when it was written and it runs before them. So every boot rolls the dice
	-- again: the run this row was measured on put one at (-112, -102), which is 8 studs of invisible
	-- hill sitting on the WEST GATE LANE'S CENTRE LINE, and the run before it put the same nine
	-- somewhere else entirely. A road guarantee that is re-rolled per server is not a guarantee.
	--
	-- Dropping them is the fix rather than teaching the scatter about the roads: this zone's ground
	-- IS the map, the other twenty zones keep their relief (they rename their mounds -- AshMound,
	-- RegolithMound, VoidMound -- and the rule below anchors at the START of the name, so only
	-- Forest's default-named ones go). A second mapped zone would have to add its own name here.
	"Mound",
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

-- Foliage, the entrance corridor, and the cut that opens it all live in `MapProps/MapCut` now.
-- They were three locals here until 31.19 needed the same rule for the village's south, west and
-- east gates, and a second copy of `isFoliage` in `MapGates` is `evolution-lab-zone-geometry-
-- constants` word for word: one decision written in two files. 31.5a is what that costs.
--
-- Moving it out also fixed the classifier twice over -- a LOOSE `Top`/`Leaves` part is a tree, and
-- a paper-thin blank wall inside a lane is scenery with no job -- and both of those now apply to
-- this corridor as well, which is the point of there being one of it. See `MapCut`.
--
-- The `entrance` spec keeps its own four-field shape because `MapForest`, `MapRoad` and `GetSpec`
-- read it; it is converted to a lane here, at the single place that cuts with it.
local ENTRANCE_DRIVE_HALF = 26   -- the strip of the funnel that has to be genuinely walkable
local ENTRANCE_DRIVE_MIN = 2     -- ...and nothing above knee height stands on it

local function cutEntrance(map, cx, e, protected)
	local lane = {
		x1 = 0, z1 = e.zNear, x2 = 0, z2 = e.zFar,
		halfA = e.halfNear, halfB = e.halfFar,
	}
	local cut = MapCut.Lane(map, cx, lane, protected)
	-- And the same narrow footprint pass `MapGates` runs, for the same reason and found the same
	-- way: a body box walked from the spawn to the square was still stopped at (0, 106) by a
	-- `Trunk 01` whose trunk stands outside the funnel and whose canopy hangs into it. 31.9 closed
	-- this corridor on a 32-point walk and the two probes disagree because they sampled different
	-- points -- which is the argument for the rule being structural rather than for a denser grid.
	cut += MapCut.LaneFootprint(map, cx, lane, ENTRANCE_DRIVE_HALF, protected, ENTRANCE_DRIVE_MIN)
	return cut
end

-- The spec for a mapped zone, so a consumer can read the entrance corridor rather than copying its
-- four numbers. `MapEggs` was the first caller and the reason this exists; since 30.24 it no longer
-- needs the corridor (the eggs moved to the square's centre) and `MapForest` is the caller that
-- does -- it holds its wood out of the same funnel this cuts. The corridor is the one piece of
-- geometry another module has to agree with exactly, and `evolution-lab-zone-geometry-constants` is
-- the standing lesson about one decision written in two files.
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

				-- BEFORE the planting, because the planter asks `MapRidge.Footprints` what is left
				-- and would otherwise keep its wood out of rock that is about to be deleted.
				MapRidge.Clear(zoneKey, cx, map)

				-- ===== A FLOATING PROP IS ONE WITH NOTHING UNDER IT, NOT ONE THAT IS HIGH UP =====
				-- Her words, 2026-08-25: trees left hanging in the sky. The cause is the line above --
				-- `MapRidge.Clear` takes the artist's mountains out and whatever was standing on one
				-- stays where it was. So this runs AFTER that cut, not before it: run first it deletes
				-- caps off mountains that are about to be KEPT, and leaves the ones it was written for.
				--
				-- And the test is support, not altitude. `bottomY > 5` on its own condemns every prop
				-- this map legitimately stands up high -- a roof piece, a banner, a lantern on a post,
				-- anything on a terrace shelf -- and this village is scaled 1.15, so "high up" is a
				-- moving line. It cost 87 props on its first run, a quarter of the top-level set.
				-- The height stays only as a cheap pre-filter; the thing that condemns a prop is that a
				-- short ray straight down out of its own footprint hits NOTHING.
				--
				-- Five samples rather than one: a group's bounding-box centre can sit over the hole in
				-- an L-shaped set of parts, and one ray there condemns a prop that is standing on the
				-- ground at both ends. Any hit keeps it.
				local FLOAT_MIN_Y = 5      -- below this it is on the village floor whatever a ray says
				local FLOAT_DROP = 8       -- a prop this far off the ground is not standing on it
				local floatParams = RaycastParams.new()
				floatParams.FilterType = Enum.RaycastFilterType.Exclude
				local floatingCut = 0
				for _, c in ipairs(map:GetChildren()) do
					if c.Name ~= "MainPart" and c.Name ~= "Terrain" and not (protected and protected[c]) then
						local cf, size
						if c:IsA("Model") then
							cf, size = c:GetBoundingBox()
						elseif c:IsA("BasePart") then
							cf, size = c.CFrame, c.Size
						end
						if cf and size then
							local bottomY = cf.Position.Y - size.Y / 2
							if bottomY > FLOAT_MIN_Y then
								floatParams.FilterDescendantsInstances = { c }
								local qx, qz = size.X / 4, size.Z / 4
								local supported = false
								for _, o in ipairs({ Vector3.zero, Vector3.new(qx, 0, qz),
									Vector3.new(-qx, 0, qz), Vector3.new(qx, 0, -qz),
									Vector3.new(-qx, 0, -qz) }) do
									-- Started just BELOW the prop, never inside it: a ray that begins in a
									-- part reports nothing at all (`roblox-raycast-from-inside-a-part`).
									local from = Vector3.new(cf.Position.X + o.X, bottomY - 0.2,
										cf.Position.Z + o.Z)
									if workspace:Raycast(from, Vector3.new(0, -FLOAT_DROP, 0), floatParams) then
										supported = true
										break
									end
								end
								if not supported then
									c:Destroy()
									floatingCut += 1
								end
							end
						end
					end
				end
				-- ===== THE HORIZON IS BUILT BEFORE THE WOOD (31.24) =====
				-- It used to be the other way round -- `MapJungle` raised the ridge AFTER the
				-- planting -- and that ordering is why `spec.forest`'s bounds were fudge factors.
				-- The planter had to be told to stop at x = 565 and z = -505 because it could not
				-- ask where the hills were going to be, so the wood ended in a straight line short
				-- of a range that did not exist yet.
				--
				-- Built first, it publishes `Footprints` and the planter subtracts them the same
				-- way it already subtracts `MapRidge`'s -- a MERGE INTO AN EXISTING KEEP-OUT, not
				-- an eighth branch in `isOpenGround`. The wood can then run to the mountains and
				-- break around each one, which is what a wood at the foot of a range looks like.
				--
				-- `evolution-lab-placement-search-ordering` is the standing note: a pass only ever
				-- knows the world that existed when it ran.
				local hills = MapHorizon.Build(zoneKey, cx, map)
				MapHorizon.TintWall(zoneKey, cx)
				-- 32.28: the cut runs HERE, and the ordering is the whole fix. Build raised the
				-- hills first -- a cut before it cuts nothing -- and `MapForest.Plant` below is
				-- what turns the surviving hills' boxes into `HorizonHillCollider` parts and
				-- wood keep-outs, both read from the tables MapPass purges: a hill deleted here
				-- leaves neither an invisible wall nor a ghost no-tree zone in the pass
				-- ([[evolution-lab-placement-search-ordering]]: a pass only knows the world that
				-- ran before it, and the point is what the NEXT pass sees).
				MapPass.Cut(zoneKey, cx, map)
				-- Immediately after the cut, because it dresses the hole the cut just made and
				-- measures the hills that survived it; before Plant and the arch block below so
				-- the wood and the gate dressing meet the finished rock
				-- ([[evolution-lab-placement-search-ordering]]: a pass only knows what ran before).
				MapPassDress.Init(zoneKey, cx, map)
				MapPortalArt.Init(zoneKey, cx)
				-- LAST of the portal block, and only because it eats what the two above it left
				-- standing: the arch seats onto the cut corridor's gate and strips the built
				-- stonework around it. Before the cut it would seat against hills that are
				-- about to leave; before the art it could inherit an ad unit's island pose.
				MapGateArch.Init(zoneKey)
				MapGateFlanks.Init(zoneKey, cx, map)
				local planted = MapForest.Plant(zoneKey, cx, map, spec)
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
				-- LAST of all, and after MapJungle rather than before it: the three village gates
				-- are the village half of the same network the jungle trunks are the other half of,
				-- and their relocation search is a box test against the finished world. A search
				-- run any earlier is blind to everything placed after it, which is the whole of
				-- `evolution-lab-placement-search-ordering`.
				local gates = MapGates.Build(zoneKey, cx, map, protected)
				-- AFTER EVERYTHING, and that is the whole of why it is here rather than earlier.
				-- The waterfall is seated against the mountain wall and then the wood that was planted
				-- INSIDE the cliff is cut back out of it -- so the wood has to be standing first, and
				-- the hills have to be raised first, or the seat has nothing to be measured against.
				-- `evolution-lab-placement-search-ordering`: a pass only knows the world that ran before it.
				local _wf, wfCut, wfGrotto = MapWaterfall.Build(zoneKey, cx, map)
				print(("[ForestMapService] %s: dropped %d dressing, laid %d map parts at x%.2f, "
					.. "cut %d props for the arrival and hunt bands, %d for the entrance road, "
					.. "%d left floating by the mountain cut, "
					.. "raised %d horizon hills, planted %d trees over the whole platform, "
					.. "built %d jungle camps, paved %d road parts and %d gate parts, "
					.. "cut %d props out of the waterfall cliff and built %d grotto parts")
					:format(zoneKey, dropped, #map:GetDescendants(), spec.scale, cleared, road,
						floatingCut, hills, planted, camps, paved, gates, wfCut, wfGrotto))
				print("[MapAnchors] " .. MapAnchors.Describe(zoneKey))
			end
		end
	end
end

return ForestMapService
