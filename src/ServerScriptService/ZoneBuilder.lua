local RS = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local GameConfig = require(RS.Modules.GameConfig)
local PetModel = require(RS.Modules.PetModel)

local ZoneBuilder = {}

-- ===== WHERE THE WORLD IS BUILT =====
--
-- This file was 9,281 lines and 198 of Luau's 200 top-level registers -- two declarations from not
-- compiling, in the file where crossing that line does not break a panel but stops the world from
-- being built at all. It is eight files now. Each is a `ModuleScript` beside this one with a named
-- surface, NOT a closure over this file's locals: `src/SYNC.md` records what the one attempt at
-- that shape cost.
--
--   ZoneKit      the build vocabulary -- `newPart` and the shadow-and-solidity rules it applies
--                without being asked, the placement frame, the colour verbs, the sign palette,
--                the platform's own dimensions.
--   ScatterKit   where a prop may stand: the reservation table, `scatterPoint`, and the clearance
--                geography (street, centre square, both gate mouths, the boss's dais).
--   ZoneGate     the doorway between two zones, and the arena's way home.
--   ZoneTerrain  the ground itself -- the valley floor, the terraces, the cliffs, the pools.
--   VillageKit   what a village is MADE OF: the per-zone palette and the prop library.
--   BiomeDecor   what a zone is DRESSED IN: the four layers and all twenty zone builders.
--   EggPlaza     the three eggs a zone sells and the stall they stand on.
--   EventArena   the Colosseum, which is not part of a zone.
--
-- WHAT IS LEFT HERE IS THE PLAN: where each piece stands, the walls and the boundaries, the light
-- and the sky, what must never stream out, and `Build()`. Each require below carries the note for
-- its own file; `docs/CODEMAP.md` is how to find a function without opening anything, and
-- `docs/SPLIT.md` §6 is the contract the cuts were made under.

-- Bump this on every change to world geometry. Build() skips any zone that already exists, which
-- on a place that has been played once means *no* decoration change is ever visible again. The
-- stamp on the Zones folder is how Build() tells "already built by this code" from "built by an
-- older version" -- if it does not match, the whole folder is dropped and regenerated.
-- 50: the boss station moved to GameConfig (-320 -> -368) and its reserved clearing grew 116 ->
-- 178 for the larger rigs, so every zone's scatter has to be laid out again.
-- 51: the egg plaza became a wooden market stall -- every Plaza* part is gone and the podiums
-- shrank, so the old geometry has to be dropped rather than added to.
-- 52: every zone gained a terraced valley -- cliffs, boulders, pools and waterfalls in the outer
-- band -- and DECO_SPREAD_X came in from 595 to 350, so the whole scatter is laid out afresh.
-- 53: the terraces were re-cut so no two tiers overlap (that overlap WAS the z-fighting on the
-- cliffs), and the band gained strata, cracks, crags, scree, rock clusters, planting and
-- multi-step cascades. The idols doubled in size, so their old footprints are wrong too.
-- 54: step heights ~1.7x (a 15-stud riser had no room for a waterfall), buttresses and crags
-- rebuilt so they stop reading as boxes and gravestones, and the falls got streaks, a real lip
-- and spray.
-- 55: the terraces are cut into segments with a meandering inner edge (they were three exactly
-- parallel lines), the treads are densely planted with mushrooms/tufts/crystals/conifers, the
-- boulders became faceted chunks instead of spheres, and the egg stall was rebuilt to the
-- reference: slate pedestals, a pill price plate, a white EGGS panel, no crack on the shells.
-- 116: the 26 free-floating "glint coins" a zone got a plinth and a post to stand on, and came
-- down to 12. They were the "something yellow and round hanging in the air" in the bug report.
-- 117: the terraces got a flight of stairs per tier per side, so the shelves are somewhere a
-- player can actually go -- which is what the raised Brutes and Elites in CreatureService need.
-- 126: scree pulled back off the first riser -- the last measured jump shortcut (see ValleyScree).
-- 125: the collision pass (items 15/18/19). Seven more names are solid, ~48 walkable parts a zone
-- are pinned against streaming, the stair slab covers the steps that are drawn on it, and the three
-- ways onto a shelf without using the stairs (a sub-apex rise, the buttress ledge, a boulder against
-- the riser) are closed. Every one of those changes GEOMETRY, so it needs the rebuild this bump
-- forces -- without it Build() skips every zone that already exists and none of it appears.
-- 127 (11.7): the fusion pad's sign prints GameConfig.FuseRequirement, which went 4 -> 3. A sign is
-- baked at build time, so without this bump the world would keep telling players to bring four.
-- 128 (11.21-11.27, the world-geometry pass): the terrace band now stops at the walls' inner faces
-- instead of two studs inside them, the boundary ramparts no longer stand inside the terraces, the
-- buttresses are scenery rather than collision, the waterfalls reserve their corridor before any
-- prop is placed, the pool's kerb has its own ground, and 37 renamed litter/mound props are solid
-- again. All of it is geometry, so none of it appears without this bump.
-- 129 (12.8): the five Mystery Potion kiosks trade their three-line odds paragraph for the egg
-- stall's graphical odds board. A board is baked at build time exactly as a sign is, so without
-- this bump every existing world keeps the paragraph -- including the stale kind line it fixes.
-- 130 (12.8, after looking at 129 through a screen capture): the board's three percentages are
-- inked off a HUE ramp instead of an RGB lerp -- the middle of that lerp is the grey axis, so the
-- medium bottle's number was rendering as pale grey between two saturated neighbours.
-- 131 (12.9): GameConfig.ZoneShops goes 8 entries -> 15, so seven zones that had no counter now
-- build one. A shop is geometry, so none of them appears without this bump.
-- 132 (12.12): every Premium egg's odds board gains a fifth cell -- the "?????" Secret row that
-- `GameConfig.GetEggOdds` now appends. The billboard is baked at build time, so without this bump
-- the twenty Premium podiums keep advertising four species and the rarest thing in the game is
-- sold nowhere. Premium goes 4 cells -> 5, which is the width the Better board already had, so no
-- stall gets wider than it was.
-- 133 (15.8): VILLAGE_CREAM was read by the crate lid, a lamp knob and the banner emblem ~170
-- lines above its own `local`, so those three parts have been painted with a nil colour -- i.e.
-- Roblox's default grey -- in every village in the game since the palette was introduced. The
-- declaration moved above `addZoneProps`; colour is baked into the part at build time, so the
-- fix is invisible without this bump.
-- 138: the world built between 32.31 and this row was laid out through a LEAKED placement frame --
-- every egg stall 575 studs from its own village and each egg split into two halves. The code is
-- fixed (`ZoneKit.withFrame`), but a world already on disk carries the damage and the guard below
-- only rebuilds when the stamp moves, so the stamp moves.
local BUILD_VERSION = 140

-- ================= the build vocabulary =================
-- THE KIT LEFT THIS FILE (18.9). `newPart` -- with the shadow-by-size rule and the
-- solidity-by-name list it applies to every part without being asked -- plus `groundColorOf`,
-- `addPlankText`, `vivid`, `spinForever`, `pulseForever`, the placement frame they all read, the
-- sign palette and the platform's own dimensions are `ServerScriptService.ZoneKit` now, byte for
-- byte, with every comment that explains why they behave the way they do. Nothing about what gets
-- built changed; only where the vocabulary lives.
--
-- AND FOUR MORE FOLLOWED THEM (18.10): `seatModel`, `makeSign`, `stoneTones` and `addLight`.
-- Those went because the VILLAGE leaf needs them -- `villMesh` seats a model, `addWell` tones a
-- rock, `addStall` makes a sign and lights itself -- and because each was already vocabulary
-- rather than a decision about a zone. `makeSign` in particular was reading a SIGN_* palette that
-- had already moved to the kit without it.
--
-- WHY IT WENT FIRST, AND WHY THIS IS NOT THE JOB MainUI WAS: this file was 9,281 lines with 190
-- top-level `local` lines, 48 of them used across spans of 600+ lines, and `newPart` is called at
-- 534 sites spread over the whole of it. There is no line at which a cut leaves the locals behind --
-- which is what made MainUI's split a change of wrapper and makes this one a refactor. So the
-- vocabulary comes out first and the leaves (the village prop library, the ground clutter, the
-- idols and ruins, the mesh prop layer, the egg plaza, the boss arena) move onto it afterwards.
-- `docs/SPLIT.md` §6 is the measured order; `docs/CODEMAP.md` says where everything lives.
--
-- RE-LOCALISED RATHER THAN CALLED AS `ZoneKit.newPart(...)`, deliberately: there are 534 call
-- sites below and rewriting every one of them is 534 chances to break the world in exchange for
-- nothing visible, and a `local x = ZoneKit.x` costs exactly the register the `local function x`
-- it replaces cost. 28 names left and 19 came back.
--
-- AND THAT LAST CLAUSE TURNED OUT TO MATTER MUCH MORE THAN IT READS. Counted the way LUAU counts --
-- names, not `local` lines, so `local addKnob, addScallops, addBunting, addPlanter, candy` is one
-- line and five registers -- this file stood at **198 of the 200 top-level registers** before the
-- move. Two away from the ceiling that MainUI has been pinned against for a year, in the file where
-- crossing it does not break a panel but stops the entire world from building. It is at 189 now.
-- The 190 quoted above and in `docs/SPLIT.md` §6 is the LINE count, which is the number that was
-- measured when this split was planned and is not the number the compiler enforces.
--
-- THE ONE THING THAT COULD NOT BE RE-LOCALISED IS THE FRAME. `ACTIVE_FRAME` is mutable and
-- `newPart` reads it on every call, so a copy taken here would be frozen at nil forever, silently
-- -- the trap `docs/SPLIT.md` §3 rule 2 records. It is reached through `ZoneKit.setFrame` and
-- `ZoneKit.getFrame` at the eight sites that used to assign or read it.
local ZoneKit = require(script.Parent.ZoneKit)

local newPart, groundColorOf, addPlankText = ZoneKit.newPart, ZoneKit.groundColorOf, ZoneKit.addPlankText
local vivid, spinForever, pulseForever = ZoneKit.vivid, ZoneKit.spinForever, ZoneKit.pulseForever
local PLATFORM_DEPTH, PLATFORM_WIDTH = ZoneKit.PLATFORM_DEPTH, ZoneKit.PLATFORM_WIDTH
local WALL_HEIGHT, WALL_THICK, PORTAL_GAP = ZoneKit.WALL_HEIGHT, ZoneKit.WALL_THICK, ZoneKit.PORTAL_GAP
local TERRAIN_INNER, TERRAIN_OUTER = ZoneKit.TERRAIN_INNER, ZoneKit.TERRAIN_OUTER
local TERRAIN_DEPTH = ZoneKit.TERRAIN_DEPTH
local SIGN_INK, SIGN_RIM = ZoneKit.SIGN_INK, ZoneKit.SIGN_RIM
local SIGN_FACE, SIGN_FONT = ZoneKit.SIGN_FACE, ZoneKit.SIGN_FONT
local seatModel, makeSign = ZoneKit.seatModel, ZoneKit.makeSign
local stoneTones, addLight = ZoneKit.stoneTones, ZoneKit.addLight

-- WHERE A PROP MAY STAND LEFT THIS FILE (18.11)
--
-- `ServerScriptService.ScatterKit` -- the reservation table and `reserveScatter`, `scatterPoint`
-- and the legacy-spread rescaling behind it, `DENSITY` / `scaled`, and the platform's whole
-- clearance geography (the street, the centre square, both gate mouths, the boss's dais). Sixteen
-- top-level names, which took this file from **169 of Luau's 200 registers to 159**.
--
-- IT HAS STATE AND `ZoneKit` DOES NOT, which is the whole reason it is a second file rather than
-- more of the first. Read its header.
--
-- RE-LOCALISED, unlike `VillageKit` and for `ZoneKit`'s reason: `scatterPoint` alone has 109 call
-- sites here. Rewriting them would be 109 chances to break the world in a way no lint can see.
local ScatterKit = require(script.Parent.ScatterKit)

local scatterPoint, reserveScatter = ScatterKit.scatterPoint, ScatterKit.reserveScatter
local scaled = ScatterKit.scaled
local STREET_HALF, ARRIVAL_Z = ScatterKit.STREET_HALF, ScatterKit.ARRIVAL_Z

-- ...and the two colour verbs, which went the other way -- to `ZoneKit`, beside `vivid`. Same
-- reason as everything else on this line: 24 call sites below, none of which should have to change.
local lighten, darken = ZoneKit.lighten, ZoneKit.darken

-- How close you have to stand for any shop prompt in the world to offer itself. A player's body
-- scales from 1x at Cell to 9x at The Absolute, and a ProximityPrompt measures to the character's
-- root -- which at the top stages floats close to thirty studs above the counter it is standing
-- at. At the old 17 an endgame player physically could not reach the stalls or the cauldron: the
-- vertical gap alone was outside the radius. Sized for the biggest body in the game.
local PROMPT_REACH = 42

-- Forest arrival clearing. The place ships with its SpawnLocation at (-32, 1, -25), which is
-- inside the Forest egg-plaza footprint -- players spawn wedged against the shop. See EnsureSpawn.
-- Kept level with every other zone's arrival point (ARRIVAL_Z), at the +Z end of the street.
local SPAWN_POSITION = Vector3.new(0, 1, 366)

-- Real Roblox PBR materials per zone instead of flat SmoothPlastic -- free, built-in,
-- actual surface detail (bump/roughness) with no external assets needed.
--
-- NO FLOOR IS NEON, AND THAT IS A RULE RATHER THAN THREE CORRECTIONS (17.7). A `Neon` surface is
-- drawn at full colour with no lighting applied to it at all: no shading across its width, no
-- shadow from anything standing on it, no ambient, nothing for the sun to do. That is a fine thing
-- to ask of a 2-stud trim strip and the wrong thing to ask of a 1250 x 1150 plane -- at that size it
-- stops being a floor and becomes a lightbox, and every prop on it loses its contact shadow in the
-- same stroke. TimeRift, CelestialThrone and AbsolutePlane each had it; they are Foil and Marble
-- now, which are shiny in the way those zones wanted without emitting. The glow in those zones is
-- still there -- it is on the trims and the props, where it now reads AS glow because the ground
-- underneath it no longer does.
local GROUND_MATERIAL = {
	Forest = Enum.Material.Grass,
	Desert = Enum.Material.Sand,
	Ocean = Enum.Material.Sand,
	Volcano = Enum.Material.Basalt,
	Moon = Enum.Material.Slate,
	Mars = Enum.Material.Rock,
	Galaxy = Enum.Material.Foil,
	BlackHole = Enum.Material.Slate,
	Multiverse = Enum.Material.Foil,
	Nebula = Enum.Material.Foil,
	Wormhole = Enum.Material.Slate,
	QuantumRealm = Enum.Material.Glass,
	TimeRift = Enum.Material.Foil,
	AntimatterZone = Enum.Material.Slate,
	DreamDimension = Enum.Material.Foil,
	MirrorUniverse = Enum.Material.Glass,
	VoidExpanse = Enum.Material.Slate,
	CelestialThrone = Enum.Material.Marble,
	Singularity = Enum.Material.Foil,
	AbsolutePlane = Enum.Material.Marble,
}

-- Optional AI-generated cliff/rock formation per zone, cloned repeatedly along a
-- boundary to hide the flat invisible collision wall behind natural-looking terrain
-- instead of a flat slab. Zones with no entry here just keep the plain wall look.
local CLIFF_MESH_NAME = {
	Desert = "DesertCliffMesh",
}

local function getCliffTemplate(zoneKey)
	local name = CLIFF_MESH_NAME[zoneKey]
	return name and ServerStorage:FindFirstChild("Models") and ServerStorage.Models:FindFirstChild(name)
end

-- Clones `template` repeatedly along a line (axis "x" or "z") in front of `wall`,
-- with jitter/rotation/scale variety, then hides the flat wall behind it.
local function addCliffLine(model, wall, template, axis, length, clearHalf)
	-- `clearHalf` keeps boulders off a stretch centred on z = 0 so they cannot bury the portal
	-- gateway. The wall behind them then has to stay opaque, since no rock is left to hide it.
	wall.Transparency = clearHalf and 0 or 1
	-- tight spacing + generous scale so rocks always overlap -- no gaps a player could
	-- see (or peek into the next zone) through, and every stretch reads equally detailed
	local spacing = 26
	local count = math.ceil(length / spacing) + 2
	local start = -length / 2 - spacing
	for i = 0, count - 1 do
		local t = start + spacing * i + math.random(-3, 3)
		if clearHalf and axis == "z" and math.abs(wall.Position.Z + t) < clearHalf then continue end
		local rock = template:Clone()
		local scale = 1.05 + math.random() * 0.5
		rock:ScaleTo(scale)
		local geom = rock:FindFirstChild("body") and rock.body:FindFirstChild("body_geom")
		local halfHeight = (geom and geom.Size.Y / 2 or 65) * scale
		local pos
		if axis == "x" then
			pos = Vector3.new(wall.Position.X + t, halfHeight - 3, wall.Position.Z + math.random(-4, 4))
		else
			pos = Vector3.new(wall.Position.X + math.random(-4, 4), halfHeight - 3, wall.Position.Z + t)
		end
		local rotY = axis == "x" and (math.random(-10, 10)) or (90 + math.random(-10, 10))
		rock:PivotTo(CFrame.new(pos) * CFrame.Angles(0, math.rad(rotY), 0))
		rock.Parent = model
	end
end

-- ===== THE GROUND ITSELF LEFT THIS FILE (18.13) =====
--
-- `ServerScriptService.ZoneTerrain` -- `TERRAIN_PROFILE`, `terrainCrestY`, `buildValleySide` (the
-- largest function in the game at ~1,270 lines) and `buildTerrain`. 1,371 lines, and the cleanest
-- cut this file has taken: terrain is not decoration, so it consults no reservation table, needs no
-- zone key and imported nothing from here that was not already `ZoneKit`'s.
--
-- SPELLED OUT RATHER THAN RE-LOCALISED, unlike `ZoneKit` and `ScatterKit`: there are exactly two
-- call sites. `ZoneTerrain.buildTerrain(...)` in the zone loop, and `ZoneTerrain.crestY(...)` in
-- `addRockRampart` above -- which is the wall asking the ground how high the terrace band stands
-- where the two meet, and is why `terrainCrestY` needed a forward declaration here for so long.
local ZoneTerrain = require(script.Parent.ZoneTerrain)

-- Scatters vertical support pillars + a thin neon light strip along a wall so it never
-- reads as one flat bare slab -- reused by both wall-building helpers below. Must be defined
-- before buildXWall/buildZWall since Lua resolves `local function` upvalues lexically.
local function addWallDecor(model, positions, wallColor, faceOffset)
	local bright = Color3.new(math.min(1, wallColor.R * 4.5), math.min(1, wallColor.G * 4.5), math.min(1, wallColor.B * 4.5))
	for _, pos in ipairs(positions) do
		newPart({ Name = "WallPillar", Size = Vector3.new(6, WALL_HEIGHT + 4, WALL_THICK + 2), Position = pos, Color = bright, Material = Enum.Material.Metal, Parent = model })
		newPart({ Name = "WallLight", Size = Vector3.new(1.6, WALL_HEIGHT - 30, 1), Position = pos + faceOffset, Color = bright, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	end
end

-- ===== THE GATEWAY LEFT THIS FILE (18.15) =====
--
-- `ServerScriptService.ZoneGate` -- `buildPortal`, `buildPortalInZWall` and the seven names behind
-- them, plus `PORTAL_CLEAR_HALF`, which is how far the boundary boulders stay off the centre line
-- and is exported back because `addRockRampart` below reads it. 280 lines.
--
-- IT WENT BECAUSE IT HAS TWO CALLERS, and the second one is not a zone: the boss arena's way home
-- is the same gateway, and an arena in its own file should not have to reach into the zone builder
-- for a door.
local ZoneGate = require(script.Parent.ZoneGate)
local PORTAL_CLEAR_HALF = ZoneGate.PORTAL_CLEAR_HALF

-- The hand-placed set dressing -- one statue here, a treehouse there. It is a table rather than
-- parts left in the world because the version guard above destroys the Zones folder outright, and
-- anything hand-placed inside a zone model does not come back from that. See `ExtraProps`.
local ExtraProps = require(script.Parent.ExtraProps)

-- ===== BOUNDARY CLIFFS, GROUND DRESSING AND GUARDIAN TITANS =====
-- Everything below runs for all twenty zones and takes every colour from the zone itself, so no
-- biome is left as a bare coloured rectangle ringed by a black slab. Three jobs:
--   * a chunky rock rampart in front of every boundary wall, plus taller mesas in the dead gap
--     *outside* the platform, so the skyline above the wall is broken instead of dead flat;
--   * tone patches and a worn path across the floor, so the ground is never one flat colour;
--   * one oversized guardian statue behind each wall -- the giant animal on the horizon that the
--     reference art puts in every area.

local ROCK_MATERIAL = {
	Forest = Enum.Material.Rock,
	Desert = Enum.Material.Sandstone,
	Ocean = Enum.Material.Sandstone,
	Volcano = Enum.Material.Basalt,
	Moon = Enum.Material.Rock,
	Mars = Enum.Material.Rock,
	MirrorUniverse = Enum.Material.Marble,
	CelestialThrone = Enum.Material.Marble,
	AbsolutePlane = Enum.Material.Marble,
}

-- One course of overlapping boulders standing against a boundary wall. `axis` is the axis the wall
-- runs along, `fixed` the wall's coordinate on the other axis, `inward` which way the zone is.
-- `skipHalf` keeps a stretch centred on 0 clear so a rampart can never bury a portal gateway.
--
-- ===== THE RAMPART AND THE TERRACES STAND IN THE SAME GROUND (11.23) =====
--
-- This was written when a zone was a flat slab and the wall was the only relief at the rim. The
-- terrace band now occupies x = TERRAIN_INNER..TERRAIN_OUTER on BOTH sides, i.e. exactly where the
-- X wall's rampart stands and across the outer third of each Z wall -- and both are solid. Measured
-- before this note existed: 5,129 CliffBlock-vs-TerraceTop intersections across the world, 1,308 of
-- them blocks whose CENTRE was inside a terrace slab, i.e. entirely invisible rock rendering forever
-- inside a hill.
--
-- Two options, one per wall, and which one applies falls out of the geometry rather than out of a
-- flag:
--
--   `baseY`      the ground here is not y = 0 but a shelf. Every block STANDS ON that shelf with
--                its top left exactly where it was, and any block that would be swallowed whole is
--                not built at all. That is the X wall, where the crest height is the same at every
--                z (the outermost tread reaches the wall, so it is always `rise * tiers`).
--                Nothing visible changes from the valley -- what is dropped is what was already
--                buried -- and what survives now sits ON the top shelf instead of growing through it.
--
--   `stopAt`     past this distance from `center` along the wall, do not build. That is the Z wall,
--                whose course sweeps straight through the terrace belt at both ends at every
--                elevation the band has; there is no single shelf height to stand on out there, and
--                the terraced hillside is already the boundary's rock. The sealing slab behind is
--                untouched, so nothing opens up.
local function addRockRampart(model, zone, axis, fixed, center, halfLen, inward, skipHalf, baseY, stopAt)
	baseY = baseY or 0
	-- The generated rock face for this biome, if one has been filed. Looked up ONCE per rampart
	-- rather than per block -- this loop runs ~34 times per wall, four walls per zone.
	-- Absent means the zone keeps the plain blocks exactly as before, so the rollout is safe at
	-- every point and a missing mesh is never a broken wall.
	local cliffLib = ServerStorage:FindFirstChild("PropMeshes")
	local cliffFace = cliffLib and cliffLib:FindFirstChild("Cliff_" .. zone.key)
	local tones, deep = stoneTones(zone)
	local mat = ROCK_MATERIAL[zone.key] or Enum.Material.Rock
	-- 25 when the platform was 450 x 550. The perimeter grew by half again, and holding the old
	-- spacing would have paid for the bigger map entirely in boundary rubble nobody walks up to.
	local step = 42
	for i = -halfLen, halfLen, step do
		local t = center + i + math.random(-5, 5)
		if skipHalf and math.abs(t - center) < skipHalf then continue end
		-- every fifth block is a spire that pokes above the 140-stud wall, which is the only
		-- thing that stops the boundary reading as a ruled line across the sky
		local spire = math.random(1, 5) == 1
		local h = spire and math.random(150, 205) or math.random(52, 116)
		local w = step + math.random(8, 20)
		local d = spire and math.random(22, 34) or math.random(18, 32)
		-- OUT OF THE TERRACE BELT ENTIRELY, tested on the block's own footprint and not on its centre
		-- -- a course block is 50-62 studs long, so a centre that clears the band by 20 still puts a
		-- third of the block inside it.
		if stopAt and math.abs(t - center) + w / 2 > stopAt then continue end
		local off = inward * (d / 2 - 1)
		-- The block keeps its TOP where it was and gives up whatever is below `baseY`. `h` still
		-- decides the silhouette; `bh` is what actually gets built.
		local top = h - 4
		local bh = top - baseY
		-- 18 studs is about the point at which a block still reads as rock rather than as a kerb; at
		-- the crest of a four-tier zone that leaves the spires, which are the pieces whose whole job
		-- is to break the line of the wall against the sky.
		if bh < 18 then continue end
		local size = (axis == "z") and Vector3.new(d, bh, w) or Vector3.new(w, bh, d)
		local capSize = (axis == "z") and Vector3.new(d + 4, 7, w + 5) or Vector3.new(w + 5, 7, d + 4)
		local px = (axis == "z") and (fixed + off) or t
		local pz = (axis == "z") and t or (fixed + off)
		local yaw = math.random(-13, 13)
		local orient = Vector3.new(math.random(-3, 3), yaw, math.random(-3, 3))
		newPart({ Name = "CliffBlock", Size = size, Orientation = orient, Position = Vector3.new(px, baseY + bh / 2, pz), Color = tones[math.random(1, 3)], Material = mat, Parent = model })
		-- a paler cap so the top edge catches light instead of dying into the sky. SOLID, like the
		-- block it caps (11.22): it is wider than the block on every side, so it is the thing anything
		-- coming down from above actually meets first, and it used to be walked straight through.
		newPart({ Name = "CliffCap", Size = capSize, Orientation = orient, Position = Vector3.new(px, top - 3, pz), Color = tones[3], Material = mat, Parent = model })

		-- ===== ROCK FACE CLADDING =====
		--
		-- The block behind this stays exactly where it is, and that is deliberate: it is what actually
		-- occludes the neighbouring zone and what the player collides with. A mesh cannot be trusted
		-- with either job -- it has holes, and its collision box is not its silhouette.
		--
		-- So the mesh is scenery hung ON the front of the block: full-height, pushed out past the
		-- block's own face so its crags read against the sky, and non-colliding so it can overhang the
		-- ground without the player catching on it.
		--
		-- EVERY THIRD POSITION, NOT EVERY ONE. Twenty zones x ~34 rampart positions x 4 walls is over
		-- 2,700 meshes if this fires every time, on top of the ~700 prop meshes already in the world.
		-- At one in three the flat faces are broken up everywhere the eye lands and the count stays
		-- near 900. Skipping the spires too: those are the pieces that poke above the wall to break the
		-- skyline, and their whole value is a clean tall silhouette.
		if cliffFace and not spire and (i + halfLen) % (step * 3) < step then
			local clad = cliffFace:Clone()
			local _, raw = clad:GetBoundingBox()
			-- sized on HEIGHT and capped on WIDTH, the same rule the props and the Titan use: these are
			-- authored ~26 wide by 30 tall, and height-matching a 116-stud block alone would throw a
			-- 100-stud-wide slab sideways across three of its neighbours
			-- `bh`, not `h`: on a raised course the block itself is only what stands above the shelf,
			-- and cladding cut to the full nominal height would bury three quarters of itself in it.
			clad:ScaleTo(math.min((bh * 0.94) / math.max(raw.Y, 1), (w + 14) / math.max(raw.X, raw.Z, 1)))
			for _, part in ipairs(clad:GetDescendants()) do
				if part:IsA("BasePart") then
					-- generated meshes arrive UNANCHORED; an unanchored cliff falls through the floor on
					-- the first physics step of the first server
					part.Anchored = true
					part.CanCollide = false
				end
			end
			clad.Name = "CliffFaceMesh"
			clad.Parent = model
			-- seatModel puts it on the ground whatever the generator did with its pivot, then the yaw
			-- turns its authored -Z face toward the zone interior -- `inward` is +1 or -1 along the
			-- axis, so the two opposite walls get opposite half-turns and both face the player.
			local faceYaw
			if axis == "z" then
				faceYaw = (inward > 0) and math.rad(90) or math.rad(-90)
			else
				faceYaw = (inward > 0) and 0 or math.pi
			end
			local outX = (axis == "z") and inward * (d * 0.5 + 4) or 0
			local outZ = (axis == "z") and 0 or inward * (d * 0.5 + 4)
			seatModel(clad, px + outX, pz + outZ, faceYaw + math.rad(math.random(-8, 8)), 2)
			-- seatModel drops to y = 0; on a raised course the ground here is the shelf.
			if baseY > 0 then clad:PivotTo(clad:GetPivot() + Vector3.new(0, baseY, 0)) end
		end
		-- a boulder at the foot so the rampart meets the ground in rubble, not a clean seam
		if math.random(1, 2) == 1 then
			local s = math.random(9, 19)
			newPart({ Name = "CliffRubble", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 0.8, s * 1.1), Orientation = Vector3.new(0, math.random(0, 360), 0), Position = Vector3.new(px + (axis == "z" and inward * math.random(12, 22) or math.random(-8, 8)), baseY + s * 0.3, pz + (axis == "z" and math.random(-8, 8) or inward * math.random(12, 22))), Color = tones[math.random(1, 2)], Material = mat, CanCollide = false, Parent = model })
		end
	end
end

-- The far skyline: fat mesas standing in the dead gap between two platforms. They are never
-- reachable, so they cost nothing but silhouette -- which is exactly what they are for.
local function addBackdropMesas(model, zone, axis, fixed, center, halfLen, outward)
	local tones = stoneTones(zone)
	local mat = ROCK_MATERIAL[zone.key] or Enum.Material.Rock
	-- same reasoning as the rampart step above: silhouette per part, over a longer boundary
	for i = -halfLen, halfLen, 132 do
		for layer = 1, 2 do
			local t = center + i + math.random(-30, 30)
			local dist = outward * (30 + layer * 34 + math.random(0, 16))
			local h = layer == 1 and math.random(165, 235) or math.random(230, 320)
			local w = math.random(56, 104)
			local d = math.random(44, 78)
			-- the far layer is washed out toward the sky, the near one solid: cheap aerial haze
			local col = layer == 2 and tones[3]:Lerp(Color3.fromRGB(186, 212, 240), 0.30) or tones[2]
			local size = (axis == "z") and Vector3.new(d, h, w) or Vector3.new(w, h, d)
			local capSize = (axis == "z") and Vector3.new(d + 9, 12, w + 9) or Vector3.new(w + 9, 12, d + 9)
			local px = (axis == "z") and (fixed + dist) or t
			local pz = (axis == "z") and t or (fixed + dist)
			local orient = Vector3.new(0, math.random(-18, 18), 0)
			newPart({ Name = "BackdropMesa", Size = size, Orientation = orient, Position = Vector3.new(px, h / 2 - 30, pz), Color = col, Material = mat, CanCollide = false, CastShadow = false, Parent = model })
			newPart({ Name = "BackdropMesaCap", Size = capSize, Orientation = orient, Position = Vector3.new(px, h - 34, pz), Color = col:Lerp(Color3.new(1, 1, 1), 0.22), Material = mat, CanCollide = false, CastShadow = false, Parent = model })
		end
	end
end

-- ===== GUARDIAN TITAN =====
-- A blocky animal bust three times the height of the wall, standing outside the platform so only
-- its head and shoulders clear the boundary. Which animal is picked from a hash of the zone key,
-- so a zone always gets the same one, and the whole thing is cut from the zone's own stone with
-- the accent colour saved for the eyes -- it reads as an ancient statue of that biome, and it is
-- the single feature that tells two zones apart from across the map.
local TITAN_KINDS = { "ape", "horned", "beak" }

-- THE ZONE'S OWN BOSS, CAST AS A COLOSSUS.
--
-- Three block kinds shared between twenty zones, and the one job this statue has is to tell zones
-- apart from across the map -- so most zones were sharing their single biggest silhouette with six
-- others. ServerStorage.BossMeshes already holds one generated figure per zone (the same model
-- BossService hangs on the rig you actually fight), so the monument becomes unique by construction
-- for the cost of a clone, and it says what lives here before you have walked in.
--
-- Sized on HEIGHT and capped on WIDTH. These rigs run 51-72 wide against 58-78 tall -- near square,
-- where the block statue was twice as tall as it was wide -- so a pure height match would stand a
-- 480-stud-wide figure on a plinth less than half that. The cap is what keeps it on its base.
local TITAN_HEIGHT = 470
local TITAN_WIDTH = 460
-- ...and the plinth grows with it. 1.3 was sized for the block statue's 224-stud shoulders; under a
-- 460-wide colossus that base reads as a paving slab.
-- 2.15, measured against the WIDEST figure in the library and not against the average: eight of
-- the twenty rigs hit the 460 width cap, and at 1.85 the base under them was 388 -- a colossus
-- standing with both feet over the edge of its own pedestal.
local TITAN_PLINTH_SCALE = 2.15
local TITAN_PLINTH_TOP = 86 -- plinth centre 17 + half 23, all times the scale above

local function titanFigure(zone)
	local folder = ServerStorage:FindFirstChild("BossMeshes")
	local template = folder and folder:FindFirstChild("BossMesh_" .. zone.key)
	if not template then return nil end
	local figure = template:Clone()
	local _, raw = figure:GetBoundingBox()
	figure:ScaleTo(math.min(TITAN_HEIGHT / math.max(raw.Y, 1), TITAN_WIDTH / math.max(raw.X, raw.Z, 1)))
	figure.Name = "TitanFigure"
	for _, d in ipairs(figure:GetDescendants()) do
		if d:IsA("BasePart") then
			-- generated meshes arrive unanchored, and this one is 470 studs of it
			d.Anchored = true
			-- it stands in the dead gap outside the platform where no player can reach it, and the
			-- block statue it replaces was CanCollide false for the same reason
			d.CanCollide = false
			d.CastShadow = false
		end
	end
	return figure
end

local function buildTitan(model, zone, cx, tz, facing)
	-- deliberately NOT the cliff palette: the statue stands directly in front of the mesas, and cut
	-- from the same stone it simply vanished into them. Darker than the rock, with the zone accent
	-- saved for the eyes, is what gives it a silhouette.
	local body = Color3.fromRGB(138, 134, 126):Lerp(zone.accentColor, 0.32)
	local mid = body:Lerp(Color3.new(0, 0, 0), 0.18)
	local lite = body:Lerp(Color3.new(1, 1, 1), 0.24)
	local deep = body:Lerp(Color3.new(0, 0, 0), 0.45)
	local eye = vivid(zone.accentColor)
	local h = 0
	for i = 1, #zone.key do h = (h * 31 + zone.key:byte(i)) % 9973 end
	local kind = TITAN_KINDS[(h % #TITAN_KINDS) + 1]
	local f = facing -- +1 faces toward +z, -1 toward -z

	local titan = Instance.new("Model")
	titan.Name = "GuardianTitan"
	titan.Parent = model
	local function P(props)
		props.Parent = titan
		props.CanCollide = false
		props.CastShadow = false
		return newPart(props)
	end

	-- plinth: the statue stands in the dead gap, where there is no floor, so it brings its own
	P({ Name = "TitanPlinth", Size = Vector3.new(210, 46, 130), Position = Vector3.new(cx, 17, tz), Color = deep, Material = Enum.Material.Concrete })
	P({ Name = "TitanPlinthTrim", Size = Vector3.new(226, 10, 146), Position = Vector3.new(cx, 40, tz), Color = mid, Material = Enum.Material.Concrete })
	for _, sx in ipairs({ -1, 1 }) do
		P({ Name = "TitanBrazier", Size = Vector3.new(14, 40, 14), Position = Vector3.new(cx + sx * 96, 62, tz + f * 52), Color = deep, Material = Enum.Material.Concrete })
		local flame = P({ Name = "TitanFlame", Shape = Enum.PartType.Ball, Size = Vector3.new(24, 24, 24), Position = Vector3.new(cx + sx * 96, 92, tz + f * 52), Color = eye, Material = Enum.Material.Neon })
		addLight(flame, eye, 60, 4)
	end

	-- THE MESH PATH, AND WHY IT LEAVES EVERYTHING ABOVE STANDING. The plinth and the two braziers
	-- are what make this read as a monument rather than as a monster standing in a field, so they
	-- are built either way. Only the block BODY below is replaced.
	--
	-- ORDER MATTERS AND IS EASY TO GET WRONG: the base is scaled here, with what the block statue
	-- gets at the bottom of this function, and the figure is parented AFTERWARDS. Parenting it first
	-- would put it inside the ScaleTo and multiply a figure that is already sized in world studs.
	local figure = titanFigure(zone)
	if figure then
		titan.WorldPivot = CFrame.new(cx, 0, tz)
		titan:ScaleTo(TITAN_PLINTH_SCALE)
		figure.Parent = titan
		-- The rigs are authored facing -Z, which is the boss end of a zone. `facing` +1 means this
		-- monument should look back up the platform toward the arrival gate, so that is the case that
		-- needs the half turn -- the same yaw the desert cat statue needed for the same reason.
		seatModel(figure, cx, tz, f > 0 and math.pi or 0)
		figure:PivotTo(figure:GetPivot() + Vector3.new(0, TITAN_PLINTH_TOP, 0))
		return titan
	end

	local y = 46
	-- legs + torso
	for _, sx in ipairs({ -1, 1 }) do
		P({ Name = "TitanLeg", Size = Vector3.new(46, 74, 52), Position = Vector3.new(cx + sx * 38, y + 37, tz), Color = mid, Material = Enum.Material.Concrete })
		P({ Name = "TitanFoot", Size = Vector3.new(52, 18, 74), Position = Vector3.new(cx + sx * 38, y + 9, tz + f * 12), Color = body, Material = Enum.Material.Concrete })
	end
	y = y + 74
	P({ Name = "TitanTorso", Size = Vector3.new(132, 108, 78), Position = Vector3.new(cx, y + 54, tz), Color = body, Material = Enum.Material.Concrete })
	P({ Name = "TitanChest", Size = Vector3.new(96, 44, 12), Position = Vector3.new(cx, y + 62, tz + f * 44), Color = lite, Material = Enum.Material.Concrete })
	-- arms hang past the torso so the silhouette has a waist
	for _, sx in ipairs({ -1, 1 }) do
		P({ Name = "TitanShoulder", Shape = Enum.PartType.Ball, Size = Vector3.new(58, 54, 58), Position = Vector3.new(cx + sx * 76, y + 92, tz), Color = mid, Material = Enum.Material.Concrete })
		P({ Name = "TitanArm", Size = Vector3.new(44, 104, 48), Orientation = Vector3.new(0, 0, sx * -7), Position = Vector3.new(cx + sx * 80, y + 44, tz), Color = mid, Material = Enum.Material.Concrete })
		P({ Name = "TitanFist", Shape = Enum.PartType.Ball, Size = Vector3.new(52, 48, 52), Position = Vector3.new(cx + sx * 86, y - 8, tz), Color = body, Material = Enum.Material.Concrete })
	end
	y = y + 108
	P({ Name = "TitanNeck", Size = Vector3.new(52, 20, 46), Position = Vector3.new(cx, y + 10, tz), Color = deep, Material = Enum.Material.Concrete })
	y = y + 20

	-- head
	local headY = y + 40
	P({ Name = "TitanHead", Size = Vector3.new(102, 84, 82), Position = Vector3.new(cx, headY, tz), Color = body, Material = Enum.Material.Concrete })
	P({ Name = "TitanBrow", Size = Vector3.new(104, 16, 14), Position = Vector3.new(cx, headY + 22, tz + f * 38), Color = deep, Material = Enum.Material.Concrete })
	for _, sx in ipairs({ -1, 1 }) do
		P({ Name = "TitanSocket", Size = Vector3.new(30, 24, 10), Position = Vector3.new(cx + sx * 24, headY + 6, tz + f * 40), Color = deep, Material = Enum.Material.Concrete })
		local e = P({ Name = "TitanEye", Shape = Enum.PartType.Ball, Size = Vector3.new(20, 20, 20), Position = Vector3.new(cx + sx * 24, headY + 6, tz + f * 44), Color = eye, Material = Enum.Material.Neon })
		addLight(e, eye, 46, 3)
		pulseForever(e, 0.45, 2.2 + (sx > 0 and 0.4 or 0))
	end

	if kind == "ape" then
		P({ Name = "TitanMuzzle", Size = Vector3.new(58, 34, 34), Position = Vector3.new(cx, headY - 22, tz + f * 34), Color = lite, Material = Enum.Material.Concrete })
		for _, sx in ipairs({ -1, 1 }) do
			P({ Name = "TitanNostril", Size = Vector3.new(9, 9, 6), Position = Vector3.new(cx + sx * 12, headY - 18, tz + f * 51), Color = deep, Material = Enum.Material.Concrete })
			P({ Name = "TitanEar", Shape = Enum.PartType.Ball, Size = Vector3.new(14, 34, 30), Position = Vector3.new(cx + sx * 54, headY + 2, tz), Color = mid, Material = Enum.Material.Concrete })
		end
		P({ Name = "TitanCrest", Size = Vector3.new(20, 30, 66), Position = Vector3.new(cx, headY + 50, tz), Color = mid, Material = Enum.Material.Concrete })
	elseif kind == "horned" then
		P({ Name = "TitanSnout", Size = Vector3.new(50, 40, 48), Position = Vector3.new(cx, headY - 20, tz + f * 42), Color = lite, Material = Enum.Material.Concrete })
		for _, sx in ipairs({ -1, 1 }) do
			for seg = 1, 3 do
				local s = 30 - seg * 6
				P({ Name = "TitanHorn", Size = Vector3.new(s, s, s), Orientation = Vector3.new(0, 0, sx * (14 + seg * 9)), Position = Vector3.new(cx + sx * (40 + seg * 15), headY + 36 + seg * 20, tz), Color = seg == 3 and eye or lite, Material = seg == 3 and Enum.Material.Neon or Enum.Material.Concrete })
			end
			P({ Name = "TitanTusk", Size = Vector3.new(11, 30, 11), Orientation = Vector3.new(0, 0, sx * 12), Position = Vector3.new(cx + sx * 18, headY - 42, tz + f * 40), Color = Color3.fromRGB(244, 240, 226), Material = Enum.Material.SmoothPlastic })
		end
	else -- beak
		P({ Name = "TitanBeakTop", Size = Vector3.new(40, 26, 62), Position = Vector3.new(cx, headY - 12, tz + f * 52), Color = eye:Lerp(Color3.new(1, 1, 1), 0.35), Material = Enum.Material.SmoothPlastic })
		P({ Name = "TitanBeakLow", Size = Vector3.new(34, 14, 46), Position = Vector3.new(cx, headY - 30, tz + f * 46), Color = eye:Lerp(Color3.new(0, 0, 0), 0.25), Material = Enum.Material.SmoothPlastic })
		for i = 1, 5 do
			P({ Name = "TitanPlume", Size = Vector3.new(12, 54 - math.abs(3 - i) * 12, 22), Orientation = Vector3.new(0, 0, (i - 3) * 13), Position = Vector3.new(cx + (i - 3) * 22, headY + 62 - math.abs(3 - i) * 8, tz - f * 6), Color = i % 2 == 0 and eye or lite, Material = i % 2 == 0 and Enum.Material.Neon or Enum.Material.Concrete })
		end
	end

	-- built at a readable size, then scaled about its own footprint. At 1x it is barely taller than
	-- the wall and reads as a prop; at 1.6x it clears the boundary by three times and becomes the
	-- thing you look at when you walk into the zone.
	titan.WorldPivot = CFrame.new(cx, 0, tz)
	titan:ScaleTo(1.3)
	return titan
end

-- ===== GROUND DRESSING =====
-- Tone patches, a worn path from the arrival pad to the shop, and scattered set dressing. The
-- floor is one 450x550 slab of flat colour otherwise, and no amount of props on top of it hides
-- that -- the patches are what actually kill the "giant coloured rectangle" read.

-- WHERE THE SHOP STANDS, down the west side of the street.
--
-- It was 150. At the kiosk's size that put its far corner inside the Ocean shipwreck, which is
-- fixed biome geography and consults no reservation table at all -- the one class of collision
-- scatterPoint can never solve. 175 clears the wreck by 15 studs and costs nothing: it is still
-- the same distance off the walkway, only further up it.
--
-- SHOP_SCALE is `VillageKit.SHOP_SCALE` and could be read here, but this number is not derived
-- from it: 175 was measured against the Ocean shipwreck, not against the kiosk's own size.
local SHOP_Z = 175

local function addGroundDetail(model, zone, cx)
	-- FIRST THING BUILT ON THE ZONE'S GROUND, so this is where the reservation table starts.
	--
	-- It used to be cleared inside buildBiomeBase, which the zone loop does not reach until after
	-- the patches, the crates, the coins and the whole village are already down -- so the idols
	-- placed in there chose their ground with an empty table and dropped 150-stud plinths on top of
	-- everything. Cleared here instead, which is the scope the table actually belongs to.
	ScatterKit.clearReservations()

	-- AND THE VILLAGE GOES IN IMMEDIATELY, before one crate is placed. These coordinates are the
	-- village pass's own, copied from the calls that place them; the shop's radius is derived from
	-- SHOP_SCALE so it cannot fall behind the geometry.
	reserveScatter(cx - 150, SHOP_Z, 114)  -- the kiosk, its forecourt and pylons
	reserveScatter(cx + 150, -168, 46)                      -- the well
	reserveScatter(cx, 426, 60)                             -- the zone name board and its battens
	reserveScatter(cx - 104, 310, 22)                       -- the arrival sign post and its lamp

	local g = groundColorOf(zone)
	-- On a white floor `g:Lerp(white, 0.16)` is still white, so half the ground decoration in the
	-- Absolute Plane was invisible against the ground it was decorating -- the same blind spot the
	-- cliffs had. Both patch tones step downward there.
	local gl = g.R * 0.3 + g.G * 0.59 + g.B * 0.11
	-- ===== THE GROUND IS THE BIGGEST SURFACE IN FRAME AND IT WAS DOING NOTHING =====
	--
	-- These were two tones at 0.16 either side of the ground colour, i.e. about +/-0.08 in value.
	-- That is inside the noise of the lighting: measured on Forest's mid-green, the patches came out
	-- 0.46 and 0.62 around a 0.55 floor and simply did not read at any distance. The valley was one
	-- flat colour with faint bruises on it.
	--
	-- Three tones now, and roughly twice the separation. THREE rather than two because two alternate
	-- and alternation is a pattern -- with a third the eye stops being able to predict the next patch
	-- and starts reading it as ground rather than as decoration.
	--
	-- The bright-floor branch is unchanged in spirit and still necessary: on the Absolute Plane's
	-- white floor `Lerp(white)` is still white, so both tones there step DOWN instead. That is the
	-- same blind spot the cliffs had.
	-- The light tone is the WEAKER of the two on purpose. A patch lighter than the floor reads as a
	-- pool of light -- something shining on the ground -- where a darker one reads as earth showing
	-- through, and earth is what this is meant to be. The first pass had them equal at 0.30 and the
	-- valley came out dotted with pale spotlights.
	local light = gl > 0.78 and g:Lerp(zone.accentColor, 0.34) or g:Lerp(Color3.new(1, 1, 1), 0.20)
	local dark = g:Lerp(Color3.new(0, 0, 0), gl > 0.78 and 0.20 or 0.34)
	-- the third is the zone's own accent, heavily muted -- enough to tint, not enough to read as a
	-- painted mark. It is what stops a green field being only lighter and darker green.
	local tinted = g:Lerp(zone.accentColor, 0.22):Lerp(Color3.new(0, 0, 0), 0.06)
	local patchTones = { light, dark, tinted }
	local mat = GROUND_MATERIAL[zone.key] or Enum.Material.SmoothPlastic

	-- more patches over more ground, so the bigger floor does not read as emptier
	--
	-- EVERY PATCH SITS AT ITS OWN HEIGHT. They were all planted at y = 0.14 with the same 0.4
	-- thickness, so any two that overlapped were EXACTLY coplanar -- 2,213 such pairs across the
	-- twenty zones, 608 of them between a light patch and a dark one, which is a shimmering stripe
	-- that flickers as the camera moves. It is the same z-fighting that was chased off the terraces,
	-- reappearing on the valley floor.
	--
	-- A hundredth of a stud between layers is invisible to the eye and decisive to the depth buffer,
	-- and stacking them in draw order means the later patch is always the one on top rather than the
	-- two arguing about it. The whole stack still clears the path slabs at 0.16.
	-- 70, up from 44, and a wider size range. The floor is 640 x 800; forty-four discs averaging 59
	-- studs cover well under half of it, which is why the gaps between them read as "the real ground"
	-- and the patches as marks ON it. Past roughly two-thirds coverage the relationship inverts and
	-- the eye stops seeing patches at all -- it sees ground that varies, which is the goal.
	--
	-- The small end matters as much as the count: a floor of same-sized blobs is a texture, and one
	-- with a few big sweeps and many small breaks is terrain.
	for i = 1, 70 do
		local x, z = scatterPoint(cx, 320, 400)
		local s = math.random(18, 116)
		newPart({
			Name = "GroundPatch",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, s, s * (0.65 + math.random() * 0.6)),
			Orientation = Vector3.new(0, math.random(0, 360), 90),
			-- STILL ONE HUNDREDTH APART, and now the stack is 70 deep rather than 44, so it reaches
			-- 0.75 instead of 0.49. That is fine and deliberately checked: the path sits at 0.16 but
			-- `scatterPoint` reserves the path corridor, so patches do not land on it -- measured, one
			-- patch in the whole zone overlapped a slab and by 0.03 studs.
			Position = Vector3.new(x, 0.05 + i * 0.01, z),
			Color = patchTones[(i % 3) + 1],
			Material = mat,
			CanCollide = false,
			Parent = model,
		})
	end

	-- the path: the arrival gate (z = 216) to the shop steps (z = 26), and then on behind the shop
	-- (z = -34) to the exit gate's own steps (z = -226), so the street reads as one continuous route
	-- from the door you came in by to the door you leave by -- with the boss standing on it. Slabs
	-- shrink and wander so it reads as worn ground rather than a paved road.
	-- ===== THE PATH HAS TO BE A DIFFERENT MATERIAL, NOT A SHADE OF THE GRASS =====
	--
	-- This was a half-lerp toward stone, which on Forest's green produced rgb(112,135,89): still
	-- green, and value 0.53 against a floor of 0.55. The path was the same colour as the ground it
	-- crossed, so no amount of edging stones could make it read as a route -- the slabs looked like
	-- stepping stones dropped on a lawn because that is all they were, chromatically.
	--
	-- 0.85 lands it on the stone almost entirely. The luminance barely moves, which is fine and is
	-- rather the point: what separates a worn path from grass is HUE and saturation -- warm, dull,
	-- trodden -- not brightness. A path made lighter instead just looks like a bleached stripe.
	local pathCol = g:Lerp(Color3.fromRGB(150, 130, 104), 0.85)
	for _, span in ipairs({ { 370, 26 }, { -34, -390 } }) do
		for z = span[1], span[2], -13 do
			local w = 30 - math.abs(math.abs(z) - 180) * 0.03
			newPart({ Name = "PathSlab", Size = Vector3.new(w, 0.3, 13.5), Orientation = Vector3.new(0, math.random(-4, 4), 0), Position = Vector3.new(cx + math.random(-4, 4), 0.16, z), Color = pathCol, Material = mat, CanCollide = false, Parent = model })
		end
	end
	-- ===== THE VERGE: WHAT MAKES A PATH READ AS A PATH =====
	--
	-- A route across grass is not slabs sitting on top of it -- it is ground the grass has been worn
	-- off, which means the edge is a GRADIENT and not a line. Without one the slabs read as stepping
	-- stones dropped on a lawn, which is exactly how this street looked.
	--
	-- Two bands a side, both darker than the ground and both wider than the path, laid UNDER the
	-- slabs (y 0.03 and 0.06, against the slabs' 0.16) so the slabs still sit proudest. The outer
	-- band is the fainter of the two, so the wear fades outward instead of ending.
	--
	-- Deliberately NOT drawn as one long part per side: a 700-stud unbroken strip reads as a road
	-- marking. Segments of varying length with small gaps read as wear.
	-- THE VERGE IS DERIVED FROM THE GROUND, NOT FROM THE PATH, and the first attempt got that
	-- backwards with a result worth recording. Written as "lerp most of the way to the path, then
	-- darken", it CANCELS on a dark floor: Galaxy's ground is 0.39, the stone-tinted path lands at
	-- 0.56, seven tenths of the way there is 0.51, and taking 22% off brings it back to 0.40 -- a
	-- verge one hundredth of a step from the grass it was supposed to edge. Three zones came out
	-- that way (Galaxy 0.04, Time Rift 0.03, Dream 0.03) and no eye would have caught it in the two
	-- zones anybody screenshots.
	--
	-- So it is the ground, mostly, moved decisively in ONE direction -- and which direction depends
	-- on the ground, the same rule the village trim runs on. Five zones here have near-black floors
	-- (Void 0.04, Black Hole 0.05, Singularity 0.08, Multiverse 0.12) and you cannot darken black:
	-- there the worn strip has to be the LIGHTER thing, which is also what real trodden ground does
	-- when the dark surface is dust.
	-- HUE AND SATURATION COME FROM THE BLEND; THE VALUE IS SET OUTRIGHT. Lerping toward the path and
	-- then darkening leaves the two fighting -- the blend raises the value, the darkening lowers it,
	-- and how much of each survives depends on the floor. Fixing the flip threshold alone was not
	-- enough: Time Rift's floor at 0.35 sits just above it and still cancelled to a 0.07 gap. Stating
	-- the value as a fraction of the GROUND's own makes the separation a guarantee at every floor
	-- rather than an outcome, which is the only version that can be checked once and trusted twenty
	-- times.
	local gV = select(3, Color3.toHSV(g))
	local function worn(pathMix, amount)
		local h, s = Color3.toHSV(g:Lerp(pathCol, pathMix))
		local v = gV > 0.30 and gV * (1 - amount) or gV + (1 - gV) * amount * 1.15
		return Color3.fromHSV(h, s, math.clamp(v, 0, 1))
	end
	local vergeInner = worn(0.35, 0.34)
	local vergeOuter = worn(0.22, 0.16)
	for _, span in ipairs({ { 372, 24 }, { -32, -392 } }) do
		for z = span[1], span[2], -46 do
			local len = 40 + math.random(0, 16)
			for _, band in ipairs({ { 34, 0.03, vergeOuter }, { 24, 0.06, vergeInner } }) do
				newPart({
					Name = "PathVerge",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(0.4, band[1], len),
					Orientation = Vector3.new(0, math.random(-3, 3), 90),
					Position = Vector3.new(cx + math.random(-3, 3), band[2], z),
					Color = band[3], Material = mat, CanCollide = false, Parent = model,
				})
			end
		end
	end

	-- edging stones, so the path has a lip instead of dissolving into the grass
	for _, span in ipairs({ { 366, 30 }, { -38, -386 } }) do
		for z = span[1], span[2], -32 do
			for _, sx in ipairs({ -1, 1 }) do
				local s = math.random(4, 8)
				newPart({ Name = "PathStone", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 0.7, s), Position = Vector3.new(cx + sx * (16 + math.random(0, 4)), s * 0.25, z), Color = pathCol:Lerp(Color3.new(1, 1, 1), 0.2), Material = mat, CanCollide = false, Parent = model })
			end
		end
	end
end

-- ===== THE VILLAGE'S MATERIALS LEFT THIS FILE (18.10) =====
--
-- `ServerScriptService.VillageKit` -- the per-zone palette, `applyVillageStyle` and the tables it
-- reads, the soft-prop vocabulary (`candy`, `addKnob`, `addScallops`, `addBunting`, `addPlanter`)
-- and the prop library itself (`addLamp`, `addStall`, `addWell`, `SHOP_SCALE`, and the `villMesh`
-- loader behind them). Twenty-two top-level names, which took this file from **189 of Luau's 200
-- registers to 169**. Read its header for where the line between the two files is drawn.
--
-- WHAT DID NOT MOVE: the layout. `addZoneProps` below, and `addZoneVillage`, `buildZoneShop` and
-- `buildMysteryOddsBoard` further down, still decide where every piece stands, still hang the
-- prompts and still read `GameConfig`. They call the library through this require.
--
-- NOT RE-LOCALISED, unlike `ZoneKit` above -- there are fifteen call sites, not five hundred, and
-- `VillageKit.addKnob(...)` is worth its four extra characters for saying where the thing lives.
--
-- `VILLAGE` IS A REFERENCE, NOT A COPY, and it has to be: `applyVillageStyle` reassigns all six of
-- its fields once per zone, so a value copied here would be frozen on Forest forever and silently
-- (`docs/SPLIT.md` §3 rule 2). The table is shared, so the field reads below always see the zone
-- currently being built.
local VillageKit = require(script.Parent.VillageKit)
local VILLAGE = VillageKit.palette
-- ===== SET DRESSING =====
-- Crates, banners, signposts and spinning pickups. Cheap, but they are what makes a space read as
-- lived-in: the reference art is full of small readable objects at player height.
local function addZoneProps(model, zone, cx)
	local accent = vivid(zone.accentColor)
	local wood = Color3.fromRGB(150, 106, 62)
	local woodDark = Color3.fromRGB(104, 72, 42)

	-- Crates and barrels, stacked in twos and threes near the walkway. Each box gets a lid, a
	-- diagonal batten and corner blocks -- a bare cube reads as a placeholder no matter what colour
	-- it is -- and whatever is on top of a stack gets a piece of fruit sitting in it.
	--
	-- The jitter is rolled ONCE per box. It used to be rolled again for the band, which put the
	-- band up to six studs away from the crate it was supposed to be strapping shut.
	-- The crate MESH, if one is filed. A stack was five primitives a box -- crate, lid, batten,
	-- corner, plus fruit on the top one -- and eighteen stacks a zone came to roughly 165 parts,
	-- 3,300 across the world, for something the player walks past. `Vill_Crates` is one MeshPart
	-- carrying the whole stack including its rope, so it is both better looking and ~40x cheaper.
	local crateLib = ServerStorage:FindFirstChild("PropMeshes")
	local crateMesh = crateLib and crateLib:FindFirstChild("Vill_Crates")

	for c = 1, 18 do
		-- A CRATE STACK CLAIMS ITS GROUND: up to 11 studs of box plus 3 of jitter, and it was the
		-- single most-swallowed prop in the game -- 148 of them ended up inside idol plinths.
		local x, z = scatterPoint(cx, 300, 380, 16)
		reserveScatter(x, z, 16)

		if crateMesh then
			local stackMesh = crateMesh:Clone()
			local _, raw = stackMesh:GetBoundingBox()
			-- 11 to 20 studs tall: the primitive version stacked one to three 7-11 stud boxes, so
			-- this covers the same range of silhouettes from a single crate to a full pile
			stackMesh:ScaleTo((11 + math.random() * 9) / math.max(raw.Y, 0.1))
			for _, part in ipairs(stackMesh:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Anchored = true
					-- solid, like the boxes it replaces: these are chest height and a player who walks
					-- through a crate stack is being told the world is a painting
					part.CanCollide = true
				end
			end
			stackMesh.Name = "CrateStack"
			stackMesh.Parent = model
			seatModel(stackMesh, x, z, math.random() * math.pi * 2)
			continue
		end

		local stack = math.random(1, 3)
		local cy = 0
		for s = 1, stack do
			local sz = math.random(7, 11)
			local jx, jz = math.random(-3, 3), math.random(-3, 3)
			local spin = math.random(0, 90)
			local at = CFrame.new(x + jx, cy + sz / 2, z + jz) * CFrame.Angles(0, math.rad(spin), 0)
			newPart({ Name = "Crate", Size = Vector3.new(sz, sz, sz), CFrame = at, Color = s % 2 == 0 and woodDark or wood, Material = Enum.Material.WoodPlanks, Parent = model })
			-- lid, batten and four corner blocks: the joinery is what sells it as a container
			newPart({ Name = "CrateLid", Size = Vector3.new(sz + 0.9, 1.1, sz + 0.9), CFrame = at * CFrame.new(0, sz / 2, 0), Color = VILLAGE.cream, Material = Enum.Material.WoodPlanks, CanCollide = false, Parent = model })
			newPart({ Name = "CrateBatten", Size = Vector3.new(sz * 1.35, 1.2, 0.5), CFrame = at * CFrame.new(0, 0, sz / 2 + 0.1) * CFrame.Angles(0, 0, math.rad(38)), Color = woodDark, Material = Enum.Material.Wood, CanCollide = false, Parent = model })
			-- one corner post, on the face the batten crosses. The second was on the back edge of a
			-- box you can only see one side of.
			newPart({ Name = "CrateCorner", Size = Vector3.new(1.2, sz, 1.2), CFrame = at * CFrame.new(-sz / 2, 0, sz / 2), Color = woodDark, Material = Enum.Material.Wood, CanCollide = false, Parent = model })
			cy += sz
			if s == stack then
				newPart({ Name = "CrateFruit", Shape = Enum.PartType.Ball, Size = Vector3.new(3.4, 3, 3.4), CFrame = at * CFrame.new(0, sz / 2 + 1.8, 0), Color = VillageKit.candy(c), Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = model })
				newPart({ Name = "CrateFruitLeaf", Size = Vector3.new(1.6, 0.4, 0.9), CFrame = at * CFrame.new(0.7, sz / 2 + 3.2, 0) * CFrame.Angles(0, 0, math.rad(22)), Color = Color3.fromRGB(104, 180, 96), Material = Enum.Material.Grass, CanCollide = false, CastShadow = false, Parent = model })
			end
		end
	end

	-- Banner poles. The cloth used to be one flat untextured slab hung on a stick, which from any
	-- distance was a green rectangle floating in the air -- the single worst-looking thing in a
	-- zone. A real banner is a crossbar, two colours of fabric, a trim stripe and a scalloped
	-- bottom edge, and it is the scallops that do most of the work.
	-- 10 IS THE BANNER'S OWN HALF-WIDTH, and declaring it is what keeps it out of the trees. This
	-- loop asked for a bare point and claimed nothing, so fourteen 40-stud poles per zone were both
	-- invisible to everything placed later and free to land on everything placed earlier -- 70 of
	-- the 94 props found intersecting a tree were this one assembly (pole, crossbar, cloth, stripes,
	-- emblem, scallops and knobs, all counted separately). The crossbar is the widest piece at 15,
	-- so 7.5 is the true half and 10 leaves room for the scallops hanging off the bottom edge.
	--
	-- It survives to the mesh props: nothing clears scatterBlocks between here and buildBiomeBase.
	for b = 1, 14 do
		local x, z = scatterPoint(cx, 310, 390, 10)
		reserveScatter(x, z, 10)
		local h = math.random(26, 40)
		local spin = math.random(0, 360)
		local at = CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(spin), 0)
		local cloth, trim = VillageKit.candy(b), VillageKit.candy(b + 3)

		newPart({ Name = "BannerPole", Size = Vector3.new(1.6, h, 1.6), CFrame = at * CFrame.new(0, h / 2, 0), Color = woodDark, Material = Enum.Material.Wood, Parent = model })
		newPart({ Name = "BannerCrossbar", Size = Vector3.new(15, 1.1, 1.1), CFrame = at * CFrame.new(0, h - 1.5, 0), Color = woodDark, Material = Enum.Material.Wood, CanCollide = false, Parent = model })
		for _, sx in ipairs({ -1, 1 }) do
			VillageKit.addKnob(model, (at * CFrame.new(sx * 7.5, h - 1.5, 0)).Position, 1.9, VILLAGE.cream)
		end

		local clothH = h * 0.42
		local clothY = h - 1.5 - clothH / 2 - 1
		newPart({ Name = "BannerCloth", Size = Vector3.new(13, clothH, 0.5), CFrame = at * CFrame.new(0, clothY, 0), Color = cloth, Material = Enum.Material.Fabric, CanCollide = false, Parent = model })
		-- two stripes across it, so the sheet has structure instead of being one flat fill
		for _, dy in ipairs({ 0.22, -0.22 }) do
			newPart({ Name = "BannerStripe", Size = Vector3.new(13.4, clothH * 0.13, 0.7), CFrame = at * CFrame.new(0, clothY + clothH * dy, 0), Color = trim, Material = Enum.Material.Fabric, CanCollide = false, CastShadow = false, Parent = model })
		end
		newPart({ Name = "BannerEmblem", Shape = Enum.PartType.Ball, Size = Vector3.new(4.6, 4.6, 1.2), CFrame = at * CFrame.new(0, clothY, -0.5), Color = VILLAGE.cream, Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = model })
		VillageKit.addScallops(model, at, 12, 4, clothY - clothH / 2, 0, trim, cloth, 3.4)

		local knob = VillageKit.addKnob(model, (at * CFrame.new(0, h + 1.4, 0)).Position, 3.4, accent, Enum.Material.Neon)
		addLight(knob, accent, 18, 1.4)
	end

	-- ===== SPINNING DNA SPECIMENS -- ON A PLINTH, NOT HANGING IN MID-AIR =====
	--
	-- These were 26 free-floating neon discs a zone, dropped at a random 6 to 11 studs off the
	-- ground with nothing whatsoever underneath them. The intent was right and is kept -- a moving
	-- highlight at eye height everywhere you look is the difference between a diorama and a live
	-- map -- but the read was wrong in two separate ways, and both were reported from a screenshot:
	--
	--   * "there is something yellow and round just hanging in the air". A 7-stud glowing disc with
	--     no support does not read as decoration, it reads as a prop whose stand failed to load.
	--     Nothing in this world may float unless something VISIBLE is holding it up -- the same
	--     rule the zone signs learned when they stopped being billboards.
	--   * a glowing disc at chest height in a game full of collectables promises a pickup. This one
	--     cannot be picked up, so every player walks into it once and learns the world lies.
	--
	-- Now it is a specimen on display: a stone pad, a post, and the coin turning just above the
	-- top of it. The count comes down 26 -> 12 because this is three parts each instead of one and
	-- because 26 of them was never sparkle, it was litter -- twelve on stands read as more.
	local stone = groundColorOf(zone):Lerp(Color3.fromRGB(232, 228, 220), 0.62)
	for i = 1, 12 do
		local x, z = scatterPoint(cx, 310, 390, 9)
		reserveScatter(x, z, 9)
		local color = i % 3 == 0 and accent or Color3.fromRGB(255, 214, 74)
		-- the post is what carries the eye up to the coin, so its height is what varies, not the
		-- coin's distance from nothing
		local postH = math.random(7, 11)

		newPart({ Name = "GlintPlinth", Size = Vector3.new(7, 2.4, 7), CFrame = CFrame.new(x, 1.2, z) * CFrame.Angles(0, math.rad(math.random(0, 45)), 0), Color = stone, Material = Enum.Material.Slate, Parent = model })
		newPart({ Name = "GlintPost", Size = Vector3.new(1.8, postH, 1.8), CFrame = CFrame.new(x, 2.4 + postH / 2, z), Color = woodDark, Material = Enum.Material.Wood, CanCollide = false, Parent = model })

		-- 3.4 clears the coin's own 3.5-stud radius off the top of the post by a hair, so it turns
		-- just above it rather than through it
		local base = CFrame.new(x, 2.4 + postH + 3.4, z) * CFrame.Angles(0, math.rad(math.random(0, 180)), math.rad(90))
		local coin = newPart({ Name = "GlintCoin", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 7, 7), CFrame = base, Color = color, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = model })
		addLight(coin, color, 14, 1.2)
		spinForever(coin, base, 180, 3.2)
	end

	-- Direction signs on the walkway. The first pass was two blank boards at waist height, which
	-- read as picnic tables; these stand at head height and actually name the zone each gate leads
	-- to, which is the one piece of information a player crossing the platform wants.
	local index
	for i, z in ipairs(GameConfig.Zones) do
		if z.key == zone.key then index = i end
	end
	-- Both gates now stand at the ends of the street -- back the way you came at +Z, onward at -Z
	-- -- so the boards point *along* the walkway instead of across it. Post beside the path, plank
	-- turned to face the walker, arrow aimed at the gate it names.
	for _, entry in ipairs({ { -1, 1, GameConfig.Zones[(index or 1) - 1] }, { 1, -1, GameConfig.Zones[(index or 1) + 1] } }) do
		local sx, sz, target = entry[1], entry[2], entry[3]
		if target then
			local px, pz = cx + sx * 36, 200
			newPart({ Name = "SignPost", Size = Vector3.new(2.2, 26, 2.2), Position = Vector3.new(px, 13, pz), Color = woodDark, Material = Enum.Material.Wood, Parent = model })
			-- The plank IS the sign. It used to carry a floating billboard as well: a 35%-black rounded
			-- rectangle hanging a stud in front of the wood, turning to face the camera whatever angle
			-- the board was at, with the word running to the very edge of its own plate -- which is
			-- exactly why "Desert" read as having been cut off. Painting the name onto both faces of
			-- the board removes the second object entirely and the text can never overhang the thing
			-- it is written on.
			local board = newPart({ Name = "SignBoard", Size = Vector3.new(18, 7.6, 1.4), Orientation = Vector3.new(0, 90, 0), Position = Vector3.new(px, 24, pz + sz * 8), Color = wood, Material = Enum.Material.WoodPlanks, CanCollide = false, Parent = model })
			-- a batten across each end, so the board reads as joined boards rather than one slab
			for _, ex in ipairs({ -1, 1 }) do
				newPart({ Name = "SignBatten", Size = Vector3.new(1.1, 8.8, 1.9), Orientation = Vector3.new(0, 90, 0), Position = Vector3.new(px, 24, pz + sz * 8 + ex * 8.2), Color = woodDark, Material = Enum.Material.Wood, CanCollide = false, CastShadow = false, Parent = model })
			end
			addPlankText(board, target.emoji .. " " .. target.name, vivid(target.accentColor))

			-- A real arrowhead instead of the old 45-degree cube, which read as a diamond finial and
			-- pointed nowhere in particular. Two planks meeting at a point, placed with CFrame.lookAt
			-- so each arm aims AT the tip instead of being rotated at by hand.
			-- The tip has to clear the board's own half-length (9 studs) plus the arms' reach, or the
			-- arrowhead is drawn across the word it is meant to be pointing away from.
			local tipPoint = Vector3.new(px, 24, pz + sz * 25)
			for _, ey in ipairs({ -1, 1 }) do
				local dir = Vector3.new(0, ey * 0.64, -sz * 0.77).Unit
				newPart({ Name = "SignArrow", Size = Vector3.new(1.4, 2.3, 10.5), CFrame = CFrame.lookAt(tipPoint + dir * 5, tipPoint), Color = wood, Material = Enum.Material.WoodPlanks, CanCollide = false, CastShadow = false, Parent = model })
			end
			-- The shaft joining the board to the head. It has to REACH INTO the board (whose 18-stud
			-- length spans pz+sz*8 +- 9) at one end and to the chevron at the other -- sized to the gap
			-- alone it hangs between the two with daylight at both ends, which is how the first pass
			-- ended up reading as a plank and a loose arrowhead rather than as an arrow.
			newPart({ Name = "SignArrowShaft", Size = Vector3.new(1.4, 3, 14), Position = Vector3.new(px, 24, pz + sz * 19), Color = wood, Material = Enum.Material.WoodPlanks, CanCollide = false, CastShadow = false, Parent = model })

			local tip = newPart({ Name = "SignLamp", Shape = Enum.PartType.Ball, Size = Vector3.new(3.6, 3.6, 3.6), Position = Vector3.new(px, 27, pz), Color = vivid(target.accentColor), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
			addLight(tip, vivid(target.accentColor), 20, 1.6)
		end
	end
end

-- ===== VILLAGE =====
-- Hand-placed built structures, as opposed to the scattered clutter above. Scatter alone gives a
-- platform *stuff*; it does not give it a plan, and a zone with no plan still reads as a field
-- with objects on it. Everything here is positioned by hand so the walkway becomes a lit street
-- with a market on one side, and so nothing can land on the plaza (|x - cx| < 60), the arrival
-- clearing (z ~ 212), the walkway itself (|x - cx| < 48) or the boss arena (z ~ -132).
--
-- Each piece is built off a base CFrame with local offsets rather than absolute positions, so a
-- structure can be turned to face the street without re-deriving every part's coordinates.
--
-- THE MATERIALS ARE IN `VillageKit`; WHAT IS LEFT HERE IS THE PLAN. The nineteen per-zone palettes
-- and the rule behind them (contrast with the GROUND, not agreement with the theme), the outline
-- tier, the candy set, the four soft shapes and the prop library are all in
-- `ServerScriptService.VillageKit` as of 18.10 -- see the require above `addZoneProps`. What
-- follows is the placement: the odds board, the shop counters and `addZoneVillage`, which is the
-- function that says where a village's pieces actually stand.
-- ===== THE MYSTERY KIOSK'S ODDS BOARD (12.8) =====
--
-- Same job and same shape as `buildEggOddsBoard` over the egg podiums, and deliberately the same
-- object: a wide white pill with one cell per outcome, hung on the shop it belongs to and sized in
-- STUDS so it stays over its own counter instead of growing into the street from a distance.
--
-- What it replaces is a three-line text sign. That sign was the right IDEA -- a gamble has to print
-- its odds where the money is spent -- and the wrong object twice over: the odds were a run of
-- "Small 66%   Medium 27%   Large 7%" in one paragraph with the product above it, which is a menu
-- rather than a board, and its kind line was hand-written and had gone stale (three kinds named
-- beside a share computed over four). Both halves now come out of GameConfig -- `GetMysteryKindsText`
-- and `GetMysterySizeOdds` -- which are read off the tables `RollMysteryPotion` itself rolls against.
--
-- Colour: each size's percentage is inked in that bottle's own tint, taken through HSV rather than
-- by blending toward black. "Blend toward the ink colour, then darken" cancels on the pale mint end
-- of the ramp and gives two sizes the same grey -- take hue and saturation from the tint and SET the
-- value, which is the rule the world look pass paid for.
-- `cf` overrides where the board hangs. The timber kiosk is a different building from the panel
-- kiosk -- taller, deeper, and with an awning where the other one has a flat fascia -- so the one
-- spot that was measured off the panel kiosk's geometry is the one thing this cannot assume.
local function buildMysteryOddsBoard(model, base, S, color, cf)
	local odds = GameConfig.GetMysterySizeOdds()
	if #odds == 0 then return nil end

	local anchor = newPart({
		Name = "MysteryOddsAnchor",
		Size = Vector3.new(1, 1, 1),
		-- where the old odds sign hung: clear of the counter's bottles below and of the canopy
		-- fascia above, on the street side of the stall so it is read from the forecourt
		CFrame = cf or base * CFrame.new(0, 18.4 * S, 15 * S),
		Transparency = 1,
		CanCollide = false,
		Parent = model,
	})

	local gui = Instance.new("BillboardGui")
	gui.Name = "MysteryOdds"
	gui.Size = UDim2.new(21 * S, 0, 8.6 * S, 0)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	-- Wide enough to matter from the forecourt and the pads, and short of the distance the shop's
	-- own title board is drawn from (640) -- the title is what makes you walk over, this is what you
	-- read once you are there.
	gui.MaxDistance = 260
	gui.Parent = anchor

	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.Size = UDim2.new(1, 0, 1, 0)
	pill.BackgroundColor3 = Color3.fromRGB(250, 252, 255)
	pill.BorderSizePixel = 0
	pill.Parent = gui
	local pillCorner = Instance.new("UICorner")
	pillCorner.CornerRadius = UDim.new(0.16, 0)
	pillCorner.Parent = pill
	local pillStroke = Instance.new("UIStroke")
	pillStroke.Thickness = 4
	pillStroke.Color = Color3.fromRGB(28, 38, 58)
	pillStroke.Parent = pill

	-- the shop's own colour along the top edge, so the board belongs to the kiosk it hangs on
	local cap = Instance.new("Frame")
	cap.Name = "Cap"
	cap.Size = UDim2.new(1, 0, 0.20, 0)
	cap.BackgroundColor3 = color
	cap.BorderSizePixel = 0
	cap.Parent = pill
	local capCorner = Instance.new("UICorner")
	capCorner.CornerRadius = UDim.new(0.5, 0)
	capCorner.Parent = cap

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -16, 1, -4)
	title.Position = UDim2.new(0.5, 0, 0.5, 0)
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.Text = "ONE SEALED BOTTLE"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextStrokeColor3 = Color3.fromRGB(28, 38, 58)
	title.TextStrokeTransparency = 0
	title.Parent = cap

	-- WHICH EFFECT, and it is a flat share across every kind that exists
	local kinds = Instance.new("TextLabel")
	kinds.Name = "Kinds"
	kinds.Size = UDim2.new(1, -20, 0.19, 0)
	kinds.Position = UDim2.new(0.5, 0, 0.21, 0)
	kinds.AnchorPoint = Vector2.new(0.5, 0)
	kinds.BackgroundTransparency = 1
	kinds.Font = Enum.Font.FredokaOne
	kinds.TextScaled = true
	kinds.Text = GameConfig.GetMysteryKindsText()
	kinds.TextColor3 = Color3.fromRGB(52, 60, 82)
	-- no stroke: this sits on a white pill, and dark ink in a dark outline renders as a blob (12.3)
	kinds.TextStrokeTransparency = 1
	kinds.Parent = pill

	-- ...and HOW BIG, which is the part the roll actually gambles on
	local strip = Instance.new("Frame")
	strip.Name = "Sizes"
	strip.Size = UDim2.new(1, -12, 0.55, 0)
	strip.Position = UDim2.new(0.5, 0, 0.42, 0)
	strip.AnchorPoint = Vector2.new(0.5, 0)
	strip.BackgroundTransparency = 1
	strip.Parent = pill

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = strip

	for i, entry in ipairs(odds) do
		-- ===== A HUE RAMP, NOT AN RGB LERP, AND A SCREENSHOT IS WHY =====
		--
		-- The first cut took the counter bottles' own ramp -- mint lerped toward pink in RGB -- and
		-- set the value through HSV, which is the world look pass's rule and was still the wrong
		-- instrument here. The MIDDLE of an RGB lerp between two hues sits on the grey axis: the
		-- medium bottle came out at saturation 0.07, so its "27%" rendered as pale grey on a white
		-- pill between a saturated green 66% and a saturated magenta 7%. Every property read correct.
		--
		-- Walking the HUE instead keeps every rung fully coloured however many sizes there are, and
		-- the middle becomes a violet rather than a smudge. Ink and tile take the same hue at two
		-- different saturations, so a cell reads as one object.
		local t = (i - 1) / math.max(#odds - 1, 1)
		local hue = 0.42 + t * (0.94 - 0.42)
		local ink = Color3.fromHSV(hue, 0.85, 0.62)
		local tint = Color3.fromHSV(hue, 0.42, 0.97)

		local cell = Instance.new("Frame")
		cell.Size = UDim2.new(1 / #odds, 0, 1, 0)
		cell.BackgroundTransparency = 1
		cell.LayoutOrder = i
		cell.Parent = strip

		local tile = Instance.new("Frame")
		tile.Name = "Tile"
		tile.Size = UDim2.new(0.34, 0, 0.62, 0)
		tile.Position = UDim2.new(0.04, 0, 0, 0)
		tile.BackgroundColor3 = tint
		tile.BorderSizePixel = 0
		tile.Parent = cell
		local tileCorner = Instance.new("UICorner")
		tileCorner.CornerRadius = UDim.new(0.28, 0)
		tileCorner.Parent = tile
		local tileStroke = Instance.new("UIStroke")
		tileStroke.Thickness = 2
		tileStroke.Color = Color3.fromRGB(28, 38, 58)
		tileStroke.Parent = tile

		local icon = Instance.new("TextLabel")
		icon.Size = UDim2.new(0.84, 0, 0.84, 0)
		icon.Position = UDim2.new(0.08, 0, 0.08, 0)
		icon.BackgroundTransparency = 1
		icon.Font = Enum.Font.FredokaOne
		icon.TextScaled = true
		icon.Text = entry.emoji
		icon.Parent = tile

		local chance = Instance.new("TextLabel")
		chance.Name = "Chance"
		chance.Size = UDim2.new(0.56, 0, 0.56, 0)
		chance.Position = UDim2.new(0.42, 0, 0.03, 0)
		chance.BackgroundTransparency = 1
		chance.Font = Enum.Font.FredokaOne
		chance.TextScaled = true
		chance.TextColor3 = ink
		chance.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
		chance.TextStrokeTransparency = 0
		-- same rule as the egg board: below 1% an integer rounds a real chance to "0%", which
		-- advertises something that cannot be won
		chance.Text = entry.chance < 1 and string.format("%.1f%%", entry.chance)
			or string.format("%.0f%%", entry.chance)
		chance.Parent = cell

		local foot = Instance.new("TextLabel")
		foot.Name = "Foot"
		foot.Size = UDim2.new(0.92, 0, 0.30, 0)
		foot.Position = UDim2.new(0.04, 0, 0.66, 0)
		foot.BackgroundTransparency = 1
		foot.Font = Enum.Font.FredokaOne
		foot.TextScaled = true
		foot.TextXAlignment = Enum.TextXAlignment.Left
		foot.Text = ("%s \u{2022} %d min"):format(entry.name, entry.minutes)
		foot.TextColor3 = Color3.fromRGB(52, 60, 82)
		foot.TextStrokeTransparency = 1
		foot.Parent = cell
	end

	return anchor
end

-- THE ONE SHOP THIS ZONE HAS, IF IT HAS ONE.
--
-- Every village used to carry the same three potion counters, in all twenty zones, which made the
-- shop the least interesting thing on the street: there was never a reason to walk to a particular
-- zone for one. There are fifteen in the whole strip now (GameConfig.ZoneShops) -- seven Mystery
-- Potion shops, four Pet Fusion labs and four Upgrade Emporiums -- and they are deliberately not
-- spread evenly: the first eleven zones carry six of them, and from zone 12 on EVERY zone has one
-- (12.9). Rarity is what makes a shop an event early; by the late game the player has the currency
-- and the missing counter is just a walk. Which one a zone carries is the information now.
--
-- Two ways a counter does its work, and the difference is which side owns the transaction:
--
--   * `MysteryCost` -- the server's business. PotionService wires the prompt on server start and
--     charges the DNA; the price rides on the prompt so the purchase is validated against the
--     counter the player is standing at rather than a number the client sent.
--   * `ShopPanel`   -- the client's business. Fusion and the upgrade counters only need to OPEN a
--     panel the HUD already has, so MainUI listens for the prompt itself and no round trip, no
--     remote and no server handler exist for them at all.
local function buildZoneShop(model, zone, cx, shopKey, shopDef, base)
	-- the counters are built at the same scale as the stall they stand on -- see SHOP_SCALE
	local S = VillageKit.SHOP_SCALE
	local function at(x, y, z) return base * CFrame.new(x * S, y * S, z * S) end
	local function vs(x, y, z) return Vector3.new(x * S, y * S, z * S) end

	local color = shopDef.color or vivid(zone.accentColor)

	-- WHICH SHELL THIS SHOP IS BUILT IN.
	--
	-- All fifteen of them are the timber market kiosk (`VillageKit.addWoodKiosk`): a counter you
	-- walk up to with a shopkeeper's side and a customer's side, which is what every one of these
	-- shops is. The white panel kiosk it replaced is still in VillageKit and is still what
	-- `addWoodKiosk` falls back to if the model is ever missing -- but nothing picks it on purpose
	-- any more. Fusion and Upgrades moved first and the Mystery counter followed, because one
	-- street with two shop shells in it read as two different games.
	local wares = {
		color, color:Lerp(Color3.new(1, 1, 1), 0.4), color:Lerp(Color3.new(0, 0, 0), 0.3),
		color:Lerp(Color3.new(1, 1, 1), 0.7), color,
	}
	local counter = VillageKit.addWoodKiosk(model, base, color, shopDef.title, wares)

	-- The machinery below is placed in RAW STUDS off the shop's base point rather than through
	-- `at`, which multiplies by the panel kiosk's SHOP_SCALE. The timber kiosk is its own building
	-- with its own floor height (1.6), counter top (~21.4) and counter line (z 33.5), and every
	-- fixture is measured off those three numbers.
	local function raw(x, y, z) return base * CFrame.new(x, y, z) end

	local function addPrompt(parent, actionText, objectText, attrs)
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = actionText
		prompt.ObjectText = objectText
		prompt.HoldDuration = 0.4
		-- REACH SCALES WITH THE SHOP, BUT ONLY UP TO ITS OWN FOOTPRINT. The cauldron sits behind a
		-- counter that is now 25 studs deep from the front lip, so the flat 42 leaves a player
		-- standing on the doormat out of range of the only thing in the shop that sells anything.
		-- A straight PROMPT_REACH * S is the other mistake: 109 studs reaches past the fence, and a
		-- potion prompt that lights up while you are standing at the egg stall is worse than one
		-- that needs a step forward. 28 * S covers the deck, the runner and the counter and stops
		-- at the edge of the shop's own ground.
		prompt.MaxActivationDistance = math.max(PROMPT_REACH, 28 * S)
		prompt.RequiresLineOfSight = false
		for k, v in pairs(attrs) do prompt:SetAttribute(k, v) end
		prompt.Parent = parent
		return prompt
	end

	if shopKey == "mystery" then
		local cost = GameConfig.GetMysteryCost(zone.key)

		-- THE DISPENSER, WHERE THE CAULDRON USED TO BE.
		--
		-- A bubbling iron pot on a plinth is the one object that would have dragged the whole kiosk
		-- back into a fantasy market. This is the same silhouette -- a lit column you walk up to,
		-- standing behind the counter -- built as a machine: a metal base, a glass tube with the
		-- brew suspended in it, a light ring at the foot and a capped head under the canopy.
		-- Standing on the kiosk's floor behind the counter, which is where the shopkeeper's machine
		-- belongs. Its head stops at 30 -- the awning's underside is at ~48 -- so the column reads
		-- whole from the forecourt instead of disappearing into the roof.
		newPart({ Name = "DispenserBase", Size = Vector3.new(20, 5, 20), CFrame = raw(0, 4.1, -6), Color = Color3.fromRGB(41, 45, 58), Material = Enum.Material.Metal, Parent = model })
		newPart({ Name = "DispenserRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 23, 23), CFrame = raw(0, 7, -6) * CFrame.Angles(0, 0, math.rad(90)), Color = color, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = model })
		local tube = newPart({ Name = "DispenserTube", Shape = Enum.PartType.Cylinder, Size = Vector3.new(23, 15, 15), CFrame = raw(0, 18, -6) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(228, 236, 248), Material = Enum.Material.Glass, Transparency = 0.82, CanCollide = false, Parent = model })
		newPart({ Name = "DispenserCap", Size = Vector3.new(18, 3, 18), CFrame = raw(0, 30.5, -6), Color = Color3.fromRGB(41, 45, 58), Material = Enum.Material.Metal, CanCollide = false, Parent = model })

		local brew = newPart({ Name = "Brew", Shape = Enum.PartType.Cylinder, Size = Vector3.new(19, 12.6, 12.6), CFrame = raw(0, 17.4, -6) * CFrame.Angles(0, 0, math.rad(90)), Color = color, Material = Enum.Material.Neon, Transparency = 0.12, CanCollide = false, CastShadow = false, Parent = model })
		-- 60 is the engine's ceiling on PointLight.Range, so this is as far as the brew can throw
		-- light however big the shop gets
		addLight(brew, color, math.min(24 * S, 60), 1.6)
		pulseForever(brew, 0.55, 2.1)

		local fumes = Instance.new("ParticleEmitter")
		fumes.Color = ColorSequence.new(color, Color3.fromRGB(226, 196, 255))
		fumes.Size = NumberSequence.new(1.6 * S, 4.5 * S)
		fumes.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		fumes.Lifetime = NumberRange.new(1.6, 3)
		fumes.Rate = 6
		fumes.Speed = NumberRange.new(2 * S, 4 * S)
		fumes.SpreadAngle = Vector2.new(12, 12)
		fumes.Parent = brew

		-- three sealed bottles standing on the counter, one per size, so the product is visible.
		-- The counter's top face is at y 9.9 and they are seated on it rather than on a number that
		-- happened to match the old wooden counter.
		for i, size in ipairs(GameConfig.PotionSizes) do
			-- taller bottle per size, so the three sizes are readable off the counter itself, and
			-- seated on the timber counter's top face (21.4) rather than on the panel kiosk's
			local h = 5 + i * 2
			local tint = Color3.fromRGB(120, 240, 190):Lerp(Color3.fromRGB(255, 108, 168), (i - 1) / math.max(#GameConfig.PotionSizes - 1, 1))
			newPart({ Name = "MysteryBottle_" .. size.key, Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, 4 + i * 0.7, 4 + i * 0.7), CFrame = raw((i - 2) * 12, 21.4 + h / 2, 33.5) * CFrame.Angles(0, 0, math.rad(90)), Color = tint, Material = Enum.Material.Glass, Transparency = 0.2, CanCollide = false, Parent = model })
			newPart({ Name = "MysteryCork", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 2, 2), CFrame = raw((i - 2) * 12, 22.4 + h, 33.5) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(41, 45, 58), Material = Enum.Material.Metal, CanCollide = false, Parent = model })
		end

		addPrompt(tube, "Buy Mystery Potion", cost .. " DNA", { MysteryCost = cost })

		-- WHAT YOU GET AND WHAT THE ODDS ARE, AND NOTHING ELSE.
		--
		-- The board used to open with the name and the price and close with the three durations --
		-- five things in three cramped lines, of which the price is already printed on the prompt
		-- you are standing in front of and the durations are on the bottle you end up holding. What
		-- a player wants off a gamble board is the two facts they cannot get anywhere else: what
		-- comes out, and how likely each one is. Both are read from the tables the roll actually
		-- uses, so the board cannot drift from the odds.
		--
		-- 12.8 MADE IT A BOARD RATHER THAN A PARAGRAPH -- see buildMysteryOddsBoard above, which is
		-- the egg stall's odds strip wearing this shop's colour. The text form it replaces is still
		-- in GameConfig (`GetMysteryOddsText`) for any future sign that wants one line of it.
		-- 41, not 50: the odds board is 22 studs tall and hangs 30 studs nearer the camera than the
		-- shop's title board, so at the same height as the other shops' taglines it drew across the
		-- bottom of "MYSTERY POTIONS" from the forecourt.
		buildMysteryOddsBoard(model, base, S, color, raw(0, 41, 46))

	elseif shopKey == "fusion" then
		-- two pods with a beam between them: the fusion is the only thing this counter does, and a
		-- machine that visibly joins two things is a clearer sign than any amount of text.
		-- Inside the timber kiosk they stand on its floor behind the counter, which is where a
		-- machine the shopkeeper works is; on the panel kiosk they stand on the plinth as before.
		local podX, podZ = 21, -4
		local podY, podD = 19, 20
		local footD, footY, footT = 17, 6, 5
		local knobY = 30
		local beamL, beamD = 22, 3.4
		for _, sx in ipairs({ -1, 1 }) do
			newPart({ Name = "FusionPodBase", Shape = Enum.PartType.Cylinder, Size = Vector3.new(footT, footD, footD), CFrame = raw(sx * podX, footY, podZ) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(58, 54, 72), Material = Enum.Material.Metal, Parent = model })
			local glass = newPart({ Name = "FusionPod", Shape = Enum.PartType.Ball, Size = Vector3.new(podD, podD, podD), CFrame = raw(sx * podX, podY, podZ), Color = color, Material = Enum.Material.Glass, Transparency = 0.55, CanCollide = false, Parent = model })
			addLight(glass, color, math.min(22 * S, 60), 1.6)
			pulseForever(glass, 0.62, 2.4)
			VillageKit.addKnob(model, raw(sx * podX, knobY, podZ).Position, 3.4 * S, Color3.fromRGB(244, 247, 252))
		end
		local beam = newPart({ Name = "FusionBeam", Shape = Enum.PartType.Cylinder, Size = Vector3.new(beamL, beamD, beamD), CFrame = raw(0, podY, podZ), Color = Color3.fromRGB(255, 246, 200), Material = Enum.Material.Neon, Transparency = 0.15, CanCollide = false, CastShadow = false, Parent = model })
		pulseForever(beam, 0.5, 1.3)
		addLight(beam, color, math.min(26 * S, 60), 2)

		-- "fusion", not "pets". The Fusion Lab used to open the PETS panel, which meant the only door
		-- to fusing was a button inside that panel -- so the lab you walked to did not actually do the
		-- thing written on its sign, and the HUD carried a shortcut it should never have needed.
		addPrompt(counter, "Open Pet Fusion", "\u{1F43E} Fuse duplicates", { ShopPanel = "fusion" })
		makeSign(model, ("\u{1F9EC} PET FUSION\nBring %d of the same pet\nand fuse them into the next tier"):format(GameConfig.FuseRequirement or 3),
			-- out in front of the awning, not under it: tucked in at 44/26 the board drew across the
			-- timber canopy and half of it was unreadable from the one angle you walk up from
			raw(0, 50, 46), UDim2.new(23 * S, 0, 4.8 * S, 0), { maxDistance = 360 })

	else -- "upgrades"
		-- ONE SHOP, TWO COUNTERS, one per currency. A single prompt would have had to ask which
		-- currency the player meant, and the answer is a different panel either way -- so the choice
		-- is made by which end of the counter you walk up to.
		local pads = {
			{ dx = -9, icon = "\u{1F48E}", tint = Color3.fromRGB(120, 200, 255) },
			{ dx = 9,  icon = "\u{1F6CD}", tint = Color3.fromRGB(126, 226, 132) },
		}
		-- both counters sit ON the counter top, which is a different height and depth in the two
		-- shells -- see the note by `raw` above
		local padX, padY, padZ = 16, 21.8, 33.5
		local padSz  = Vector3.new(18, 1.6, 8)
		local tokenY = 28
		local gemSz  = Vector3.new(8, 8, 8)
		for i, counterDef in ipairs(GameConfig.ShopKinds.upgrades.counters) do
			local pad = pads[i] or pads[1]
			local plate = newPart({ Name = "UpgradePad", Size = padSz, CFrame = raw(pad.dx / 9 * padX, padY, padZ), Color = pad.tint, Material = Enum.Material.Neon, Transparency = 0.25, CanCollide = false, Parent = model })
			addLight(plate, pad.tint, math.min(18 * S, 60), 1.4)
			pulseForever(plate, 0.6, 2.6)
			-- the floating token over each pad: a gem for Diamonds, a crate for Robux
			if i == 1 then
				local gemFrame = raw(pad.dx / 9 * padX, tokenY, padZ) * CFrame.Angles(math.rad(45), 0, math.rad(45))
				local gem = newPart({ Name = "UpgradeGem", Size = gemSz, CFrame = gemFrame, Color = pad.tint, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
				-- spinForever takes the part's own placed frame back, and re-applies ACTIVE_FRAME itself
				spinForever(gem, gemFrame, 360, 7)
			else
				newPart({ Name = "UpgradeCrate", Size = Vector3.new(9, 7.5, 7.5), CFrame = raw(pad.dx / 9 * padX, tokenY - 0.6, padZ), Color = pad.tint, Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
				newPart({ Name = "UpgradeCrateLid", Size = Vector3.new(10, 1.6, 8.6), CFrame = raw(pad.dx / 9 * padX, tokenY + 4.2, padZ), Color = Color3.fromRGB(244, 247, 252), Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
			end
			addPrompt(plate, counterDef.actionText, counterDef.objectText, { ShopPanel = counterDef.panel })
		end
		makeSign(model, "\u{1F48E} UPGRADE EMPORIUM\nStage Mastery for Diamonds\nBundles and boosts for Robux",
			raw(0, 50, 46), UDim2.new(23 * S, 0, 4.8 * S, 0), { maxDistance = 360 })
	end

	return counter
end

-- Everything above, placed. `index` is the zone's position in GameConfig.Zones, which is what
-- decides whether this village has a shop at all and which one -- see GameConfig.ZoneShops.
local function addZoneVillage(model, zone, cx, index)
	local accent = vivid(zone.accentColor)

	-- the street: lanterns and a picket fence down both sides of the walkway. The runs below all
	-- start at the arch (z = 426) rather than at a hand-typed 150 -- the platform is 1150 deep now
	-- and a street that stopped where it used to left most of the walk in the dark.
	for z = 420, 30, -30 do
		for _, sx in ipairs({ -1, 1 }) do
			VillageKit.addLamp(model, CFrame.new(cx + sx * 32, 0, z) * CFrame.Angles(0, math.rad(sx < 0 and 90 or -90), 0), accent, 20)
		end
	end
	-- the picket fence, now painted cream and capped: a bare stake with a flat top reads as a
	-- construction marker, a rounded one reads as a garden
	-- Pickets every 9 studs with a cap on every other one, not every 6 with a cap on all of them.
	-- The street is more than twice as long as it was and the old spacing spent nearly 200 parts a
	-- zone on a fence -- at this scale the reading is identical and the budget is not.
	-- THE FENCE, IN RUNS RATHER THAN IN STAKES. The primitive build was a picket every 9 studs, a
	-- rail every 12 and a knob on every other picket -- 92 + 68 + 47 = ~207 parts a zone, 4,100
	-- across the world, for the thing that lines the walk a player takes a hundred times. One
	-- `Vill_Fence` mesh is a whole run of five pickets on two rails, so a side of the street costs
	-- 29 meshes instead of 207 parts and reads as joinery rather than as stakes in a row.
	local fenceLib = ServerStorage:FindFirstChild("PropMeshes")
	local fenceMesh = fenceLib and fenceLib:FindFirstChild("Vill_Fence")
	if fenceMesh then
		-- STEP IS MEASURED, NOT ASSUMED. The mesh is authored ~14 studs long but it is scaled to a
		-- fixed HEIGHT here, so its final length depends on its own proportions -- hard-coding 14
		-- would leave gaps on a mesh that came back squarer than expected. Measure one at the size
		-- it will actually be built at, then overlap by 6% so no seam shows.
		local probe = fenceMesh:Clone()
		local _, praw = probe:GetBoundingBox()
		local fenceScale = 8 / math.max(praw.Y, 0.1)
		local step = math.max(praw.X, praw.Z) * fenceScale * 0.94
		probe:Destroy()

		for z = 430, 24, -step do
			for _, sx in ipairs({ -1, 1 }) do
				local run = fenceMesh:Clone()
				run:ScaleTo(fenceScale)
				-- TINTED AND RE-MATERIALLED PER ZONE. One mesh cloned 58 times a zone, 1,160 times in
				-- the world, is the single most repeated object in the game -- and it lines the walk the
				-- player takes most. Left at the mesh's own brown it was the same pine fence on the Moon,
				-- in the Void and inside a black hole. Alternating the two village tones along the run
				-- also gives it the light/dark rhythm the primitive pickets had and the mesh lost.
				local alt = false
				for _, part in ipairs(run:GetDescendants()) do
					if part:IsA("BasePart") then
						part.Anchored = true
						-- non-colliding, exactly as the pickets were: the fence dresses the street, it
						-- does not pen the player into it
						part.CanCollide = false
						alt = not alt
						part.Color = alt and VILLAGE.wood or VILLAGE.cream
						part.Material = VILLAGE.post
					end
				end
				run.Name = "FenceRun"
				run.Parent = model
				-- turned to lie ALONG the street: the mesh is authored across its own X, and the run
				-- goes down Z, so every piece takes a quarter turn.
				seatModel(run, cx + sx * 24, z, math.rad(90))
			end
		end
	else
		local picket = 0
		for z = 430, 24, -9 do
			picket += 1
			for _, sx in ipairs({ -1, 1 }) do
				local px = cx + sx * 24
				newPart({ Name = "FencePicket", Size = Vector3.new(1.6, 7, 1.6), Position = Vector3.new(px, 3.5, z), Color = picket % 2 == 0 and VILLAGE.cream or VILLAGE.wood, Material = VILLAGE.post, CanCollide = false, Parent = model })
				if picket % 2 == 0 then
					VillageKit.addKnob(model, Vector3.new(px, 7.4, z), 2.4, VILLAGE.wood)
				end
			end
		end
		for z = 426, 30, -12 do
			for _, sx in ipairs({ -1, 1 }) do
				newPart({ Name = "FenceRail", Size = Vector3.new(0.7, 1, 12), Position = Vector3.new(cx + sx * 24, 5.4, z), Color = VILLAGE.dark, Material = VILLAGE.post, CanCollide = false, Parent = model })
			end
		end
	end

	-- Bunting strung lamp to lamp down both sides of the street, and once across the welcome arch.
	-- This is the cheapest thing in the whole pass and it does more than any of it: a row of little
	-- triangles overhead is the single clearest signal that a place is a shopfront and not terrain.
	for _, sx in ipairs({ -1, 1 }) do
		for z = 420, 60, -30 do
			VillageKit.addBunting(model,
				Vector3.new(cx + sx * 32, 18, z),
				Vector3.new(cx + sx * 32, 18, z - 30), 5, 3.4, z)
		end
	end
	VillageKit.addBunting(model, Vector3.new(cx - 30, 29, 426), Vector3.new(cx + 30, 29, 426), 7, 4, 3)

	-- flower boxes between the lamps, turned to face the walkway
	for i, spot in ipairs({ { -1, 381 }, { 1, 381 }, { -1, 301 }, { 1, 261 }, { -1, 181 }, { 1, 181 }, { -1, 100 }, { 1, 140 }, { -1, 60 }, { 1, 60 } }) do
		VillageKit.addPlanter(model, CFrame.new(cx + spot[1] * 29, 0, spot[2]) * CFrame.Angles(0, math.rad(spot[1] < 0 and 90 or -90), 0), i)
	end

	-- welcome arch where the street starts, so arriving in a zone has a threshold
	for _, sx in ipairs({ -1, 1 }) do
		newPart({ Name = "ArchPillar", Size = Vector3.new(6, 30, 6), Position = Vector3.new(cx + sx * 30, 15, 426), Color = VILLAGE.dark, Material = VILLAGE.post, Parent = model })
		-- a cream collar a third of the way up each pillar, and a knob on top
		newPart({ Name = "ArchPillarCollar", Size = Vector3.new(7.4, 2.2, 7.4), Position = Vector3.new(cx + sx * 30, 9, 426), Color = VILLAGE.cream, Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
		VillageKit.addKnob(model, Vector3.new(cx + sx * 30, 36.4, 426), 5, VILLAGE.cream)
		-- The pennons hanging off the arch. These were one flat 14x8 sheet of raw accent colour each,
		-- and from the arrival gate they were simply two bright rectangles floating beside the
		-- pillars -- the loudest wrong thing in the zone. Now: a rod, two-tone cloth, a stripe, and a
		-- pointed tail, which is what a hanging pennon actually looks like.
		local bx = cx + sx * 25
		local cloth, trim = VillageKit.candy(sx > 0 and 1 or 4), VillageKit.candy(sx > 0 and 4 or 1)
		newPart({ Name = "ArchBannerRod", Size = Vector3.new(0.9, 0.9, 9), Position = Vector3.new(bx, 29, 426), Color = VILLAGE.dark, Material = VILLAGE.post, CanCollide = false, Parent = model })
		newPart({ Name = "ArchBanner", Size = Vector3.new(0.6, 13, 8), Position = Vector3.new(bx, 22, 426), Color = cloth, Material = Enum.Material.Fabric, CanCollide = false, Parent = model })
		newPart({ Name = "ArchBannerStripe", Size = Vector3.new(0.9, 2.2, 8.4), Position = Vector3.new(bx, 24.5, 426), Color = trim, Material = Enum.Material.Fabric, CanCollide = false, CastShadow = false, Parent = model })
		newPart({ Name = "ArchBannerEmblem", Shape = Enum.PartType.Ball, Size = Vector3.new(1.1, 4, 4), Position = Vector3.new(bx - sx * 0.5, 20.5, 426), Color = VILLAGE.cream, Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = model })
		-- the swallow tail: a wedge rolled point-down, the same trick the pennants use
		newPart({ Name = "ArchBannerTail", Shape = Enum.PartType.Wedge, Size = Vector3.new(0.6, 5, 8),
			CFrame = CFrame.new(bx, 13, 426) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.pi),
			Color = cloth, Material = Enum.Material.Fabric, CanCollide = false, Parent = model })
	end
	newPart({ Name = "ArchBeam", Size = Vector3.new(72, 4, 7), Position = Vector3.new(cx, 32, 426), Color = VILLAGE.wood, Material = VILLAGE.board, CanCollide = false, Parent = model })
	newPart({ Name = "ArchBeamTrim", Size = Vector3.new(76, 1.4, 8), Position = Vector3.new(cx, 34.6, 426), Color = zone.accentColor:Lerp(Color3.new(1, 1, 1), 0.25), Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })

	-- THE ZONE NAME, STANDING ON THE ARCH.
	--
	-- This was the worst-looking object in the game and a player pointed straight at it: a 34-stud
	-- BillboardGui at (cx, 34, 307), which is to say a giant coloured card hanging in the sky over
	-- the street, turning to face the camera from wherever you stood. From the side it had no
	-- thickness, from behind it still faced you, and it never touched the arch it belonged to.
	--
	-- Now it is a board sitting on the beam, with the name painted onto both faces -- the same
	-- treatment the "Desert" walkway sign already got, which is the one that was liked. Its bottom
	-- edge (35) overlaps the beam trim's top (35.3) on purpose: a board resting exactly on a surface
	-- shows daylight under it from any angle that is even slightly below it.
	local nameBoard = newPart({ Name = "ZoneNameBoard", Size = Vector3.new(58, 17, 2.6),
		Position = Vector3.new(cx, 43.5, 426), Color = VILLAGE.wood, Material = VILLAGE.board,
		CanCollide = false, Parent = model })
	for _, sx in ipairs({ -1, 1 }) do
		newPart({ Name = "ZoneNameBatten", Size = Vector3.new(3, 20, 3.4), Position = Vector3.new(cx + sx * 27.5, 43.5, 426), Color = VILLAGE.dark, Material = VILLAGE.post, CanCollide = false, Parent = model })
		VillageKit.addKnob(model, Vector3.new(cx + sx * 27.5, 54.6, 426), 4.4, VILLAGE.cream)
	end
	-- Coarse on purpose -- see the note on the gate board: a big canvas is what stops a SurfaceGui
	-- being drawn at range, and this is a sign meant to be read from down the street.
	addPlankText(nameBoard, zone.emoji .. " " .. zone.name, accent, { maxDistance = 620, pixelsPerStud = 14 })

	-- THE SHOP, IF THIS ZONE HAS ONE -- west of the street and turned to face it, where the market
	-- row used to stand. Five of the twenty zones have no shop at all, and all five are early:
	-- see the note on buildZoneShop and GameConfig.ZoneShops.
	local facing = CFrame.Angles(0, math.rad(90), 0)
	local shopKey, shopDef = GameConfig.GetZoneShop(index)
	if shopDef then
		buildZoneShop(model, zone, cx, shopKey, shopDef, CFrame.new(cx - 150, 0, SHOP_Z) * facing)
	end

	VillageKit.addWell(model, CFrame.new(cx + 150, 0, -168), zone)

	-- benches facing the street, between the lamps
	for _, spot in ipairs({ { -1, 345 }, { 1, 305 }, { -1, 225 }, { 1, 144 }, { -1, 112 }, { 1, 72 } }) do
		local bx = cx + spot[1] * 38
		newPart({ Name = "BenchSeat", Size = Vector3.new(4, 1.2, 14), Position = Vector3.new(bx, 4.4, spot[2]), Color = VILLAGE.wood, Material = VILLAGE.board, Parent = model })
		newPart({ Name = "BenchBack", Size = Vector3.new(1, 6, 14), Position = Vector3.new(bx - spot[1] * 1.6, 7.4, spot[2]), Color = VILLAGE.wood, Material = VILLAGE.board, CanCollide = false, Parent = model })
		for _, sz in ipairs({ -1, 1 }) do
			newPart({ Name = "BenchLeg", Size = Vector3.new(3.4, 4, 1.2), Position = Vector3.new(bx, 2, spot[2] + sz * 5.5), Color = VILLAGE.dark, Material = VILLAGE.post, CanCollide = false, Parent = model })
		end
	end

end

-- Builds a solid wall along the X axis for one zone. If `target` is given, leaves a big
-- glowing portal gap in the middle instead of a full wall -- this is the only way in or out,
-- so you never see the next zone until you actually walk through the gate.

-- Both wall builders now dress the boundary the same way in every zone: an opaque slab that does
-- the actual sealing, a rock rampart standing in front of it on the playable side, and a double
-- row of mesas in the unreachable gap behind. The old neon-pillar treatment is gone -- it made
-- every biome's edge look like the same sci-fi corridor.
local function buildXWall(model, zone, wallX, wallColor, target)
	local inward = (wallX > zone.offset) and -1 or 1
	local halfDepth = PLATFORM_DEPTH / 2
	-- The X wall runs the whole depth of the platform at the OUTER edge of the terrace band, so
	-- every position on this course stands on the outermost tread rather than on the valley floor.
	-- One number for the whole wall, because the top tier reaches TERRAIN_OUTER at every z. (11.23)
	local crest = ZoneTerrain.crestY(zone.key)

	if target then
		local gapHalf = PORTAL_GAP / 2
		local segLen = (PLATFORM_DEPTH - PORTAL_GAP) / 2
		newPart({ Name = "Wall", Size = Vector3.new(WALL_THICK, WALL_HEIGHT, segLen), Position = Vector3.new(wallX, WALL_HEIGHT/2, -(gapHalf + segLen/2)), Color = wallColor, Material = Enum.Material.Slate, Parent = model })
		newPart({ Name = "Wall", Size = Vector3.new(WALL_THICK, WALL_HEIGHT, segLen), Position = Vector3.new(wallX, WALL_HEIGHT/2, (gapHalf + segLen/2)), Color = wallColor, Material = Enum.Material.Slate, Parent = model })
		addRockRampart(model, zone, "z", wallX, 0, halfDepth - 8, inward, PORTAL_CLEAR_HALF, crest, nil)
		ZoneGate.buildPortal(model, wallX, target)
	else
		newPart({ Name = "Wall", Size = Vector3.new(WALL_THICK, WALL_HEIGHT, PLATFORM_DEPTH), Position = Vector3.new(wallX, WALL_HEIGHT/2, 0), Color = wallColor, Material = Enum.Material.Slate, Parent = model })
		addRockRampart(model, zone, "z", wallX, 0, halfDepth - 8, inward, nil, crest, nil)
	end

	addBackdropMesas(model, zone, "z", wallX, 0, halfDepth + 30, -inward)
end

-- How far out along a Z wall the rampart is still standing on the valley floor. The first cliff
-- begins at TERRAIN_INNER, and the six studs of margin cover the yaw the blocks are given. (11.23)
local TERRACE_STOP = TERRAIN_INNER - 6

local function buildZWall(model, zone, cx, cz, wallColor, target)
	local inward = (cz > 0) and -1 or 1
	if target then
		local gapHalf = PORTAL_GAP / 2
		local segLen = (PLATFORM_WIDTH - PORTAL_GAP) / 2
		newPart({ Name = "Wall", Size = Vector3.new(segLen, WALL_HEIGHT, WALL_THICK), Position = Vector3.new(cx - (gapHalf + segLen/2), WALL_HEIGHT/2, cz), Color = wallColor, Material = Enum.Material.Slate, Parent = model })
		newPart({ Name = "Wall", Size = Vector3.new(segLen, WALL_HEIGHT, WALL_THICK), Position = Vector3.new(cx + (gapHalf + segLen/2), WALL_HEIGHT/2, cz), Color = wallColor, Material = Enum.Material.Slate, Parent = model })
		addRockRampart(model, zone, "x", cz, cx, PLATFORM_WIDTH / 2 - 8, inward, PORTAL_CLEAR_HALF, 0, TERRACE_STOP)
		ZoneGate.buildPortalInZWall(model, cx, cz, target)
	else
		newPart({ Name = "Wall", Size = Vector3.new(PLATFORM_WIDTH, WALL_HEIGHT, WALL_THICK), Position = Vector3.new(cx, WALL_HEIGHT/2, cz), Color = wallColor, Material = Enum.Material.Slate, Parent = model })
		addRockRampart(model, zone, "x", cz, cx, PLATFORM_WIDTH / 2 - 8, inward, nil, 0, TERRACE_STOP)
	end
	addBackdropMesas(model, zone, "x", cz, cx, PLATFORM_WIDTH / 2 + 30, -inward)
	-- the guardian only goes behind the far wall, where it fills the view you get walking in
	if cz < 0 then
		-- far enough back that the whole figure fits in the view from the shop. Parked right
		-- against the wall it was a 500-stud green slab filling the sky with no readable silhouette.
		buildTitan(model, zone, cx, cz - 175, 1)
	end
end

-- ===== EVERYTHING A ZONE IS MADE OF LEFT THIS FILE (18.12 - 18.15) =====
--
-- Three requires, and between them they are 4,007 of the 6,500 lines that used to be written out
-- here. They sit together because they are used together: all three are read from `Build()` below
-- and nowhere else in this file.
--
--   `BiomeDecor`   what a zone is DRESSED IN. The four shared layers -- ground litter, clutter,
--                  mounds, landmark, atmosphere, glow posts, plus the idols and the ruins -- the
--                  mesh prop layer and `buildBiomeBase` that arranges them, and all twenty
--                  per-zone builders. 2,443 lines, twenty-six names, ONE escaping: every layer
--                  verb has exactly one caller, which has exactly one set of callers, which are
--                  read by exactly one line below. That is why the cut is here and not in four
--                  places, which is what `docs/SPLIT.md` §6 had planned.
--
--   `EggPlaza`     the three eggs a zone sells and the stall they stand on. 968 lines and
--                  **thirty-four** top-level names -- the biggest register win of the split,
--                  because an egg is a dozen small builders each read only by the next one along.
--
--   `EventArena`   the Colosseum, which is not part of a zone and never was: off the strip,
--                  reached by teleport only, and rebuilt on `ARENA_VERSION` rather than
--                  `BUILD_VERSION` because dropping it costs 900 parts where dropping the zones
--                  costs 60,000. `Build()` still owns the decision of when; it reads
--                  `EventArena.ARENA_VERSION` to make it.
--
-- WHAT DID NOT MOVE: this file still builds the zone. The ground, the walls and their gates, the
-- village and its shop, the light and the sky, the streaming shell, and `Build()` itself, which is
-- the thing that decides what stands where.
--
-- `ACTIVE_ZONE_KEY` WENT WITH `BiomeDecor` AND IS SET THROUGH `BiomeDecor.setZoneKey`. It is
-- reassigned per zone, so it could not be re-localised in either direction -- `docs/SPLIT.md` §3
-- rule 2, the same trap as `ZoneKit`'s placement frame. Both writers are in the zone loop below;
-- all nine readers went with the builders.
local BiomeDecor = require(script.Parent.BiomeDecor)
local decorationBuilders = BiomeDecor.decorationBuilders
local EggPlaza = require(script.Parent.EggPlaza)
local EventArena = require(script.Parent.EventArena)

-- The terraces, the cliffs, the waterfalls and the pools were written here too, and are
-- `ServerScriptService.ZoneTerrain` since 18.13 -- see the require far above, next to the walls
-- that ask it for the crest height. What is below this line is what STANDS on that ground.

-- ===== WHAT MUST NEVER STREAM OUT ===========================================================
-- StreamingEnabled hands a client the world in chunks around them and takes it back when they
-- walk away. That is the only reason a 36,000-stud strip of 60k parts is playable at all, and it
-- is also exactly what players were reporting as "the terrain disappears": stand still while a
-- chunk is being reclaimed, or arrive somewhere before one has been sent, and you are looking at
-- open sky where the floor is -- or falling through it.
--
-- A persistent model is the engine's own answer: replicated to every client at join, never
-- streamed out. The whole art is keeping the set TINY, because persistent means "in memory,
-- everywhere, forever". So only the SHELL of the world goes in -- the slab each zone stands on,
-- the six sheets that seal it, and the arena's disc. Seven parts per zone, ~150 against 60,000,
-- and with them a player can never see through the ground or fall past it whatever the props
-- around them are doing.
--
-- They live in ONE model directly under Workspace rather than one persistent group per zone. A
-- persistent model nested inside an ordinary one is the case with the least certain behaviour --
-- and a streaming setting that is quietly ignored looks exactly like the bug this is here to fix,
-- with nothing in the log to say so. Top level is the case that is unambiguous. Each part keeps a
-- `Zone` attribute so anything that needs to know which platform it came from still can.
local ALWAYS_LOADED = {
	Floor = true,
	Wall = true,
	ArenaGround = true,
	ArenaFloor = true,
	-- The terraces are GROUND, not scenery: a player can walk up onto them, and a walkable surface
	-- that is allowed to stream out is a hole somebody falls through. This is the same reason Floor
	-- is here, and it was easy to miss because the terraces look like decoration in the code.
	-- Two more parts per zone per side; the cliff faces, rocks and water are NOT pinned, because
	-- nothing stands on them.
	TerraceTop = true,
	-- CliffJut was here and is NOT any more (11.23). It became non-colliding once it was measured
	-- that TerraceTop's own front face is what actually walls the riser -- and a part nobody can
	-- stand on has no business in a set whose whole purpose is "never let the floor vanish under
	-- somebody". That is 1,568 parts, 45% of the shell, given back.
	-- and the ramps that reach them, for exactly the same reason: a walkable surface that streams
	-- out while a player is halfway up it drops them off the side of the hill, and it is the ONE
	-- route onto a shelf. This is why the flight's collision is a single slab and its steps are
	-- non-colliding paint (see the note where they are built) -- one part per tier per side, ~126
	-- across the world, against ~1,900 if the steps themselves had had to be pinned.
	TerraceRamp = true,

	-- ===== 2026-08-11: "the player can fall through / snag on things" =====
	--
	-- Measured rather than guessed: 451 SOLID parts per zone were still sitting in the zone folder,
	-- i.e. free to stream out from under somebody. Pinning all of them is not the answer -- that is
	-- ~9,000 more parts on top of 2,617, and most of the 451 are cliff mass, statue geometry and
	-- portal stonework 138-218 studs in the air that nothing ever stands on.
	--
	-- What is pinned below is the intersection of three facts about a part: it is SOLID, it has a
	-- top face a character can be on, and it is at a height a player reaches in ordinary play. That
	-- is ~48 parts per zone, so the shell goes from 2,617 to roughly 3,600 -- a third more, for the
	-- whole class of "the ground vanished while I was standing on it".
	--
	-- NOT pinned, on purpose: `CliffBlock` (104 a zone -- it is the cliff's mass, and the surface
	-- anyone actually walks on is `TerraceTop`, which is already here), `body_geom` (statue meshes),
	-- and everything above the portal's springing line.
	PortalStep = true,          -- the steps into every gate, walked through on every zone change
	PortalColumnBase = true,
	IdolPad = true, IdolPadStep = true, IdolPlinthStep = true,
	LandmarkPlinth = true, LandmarkPlinthStep = true,
	GuardianPlinth = true,
	PoolRim = true, PoolBed = true,
	-- 3,460-stud footprint of walkable hillock -- and the nineteen names below are the SAME PROP.
	-- `addMounds` defaults to "Mound" and every biome but Forest renames it, which is the whole of
	-- 11.21: this entry and the SOLID_PROPS one both matched one zone out of twenty.
	Mound = true,
	Sandbar = true, AshMound = true, RegolithMound = true, DustRidge = true,
	StardustDrift = true, CollapsedRidge = true, VoidMound = true, DustBank = true,
	WarpSwell = true, FieldSwell = true, SandDrift = true, BlastBerm = true,
	CloudBank = true, PolishedSwell = true, AshSwell = true, DrawnSwell = true, WhiteSwell = true,
	StallDeck = true, StallCounter = true, StallStep = true,
	RuinPillarBase = true,
	-- these two belong to zones Forest does not have, and are the same case as the terrace ramp:
	-- a whole staircase and a throne dais that a player stands on
	DreamStair = true, ThroneStep = true,
}

local function keepShellLoaded(zonesFolder)
	-- IDEMPOTENCE IS THE WHOLE PROBLEM HERE, and getting it wrong destroys the world.
	--
	-- Build() runs on every server start, and after the first pass the floors and walls are no
	-- longer IN the zone models -- they are in the shell. So a second pass that simply dropped the
	-- old shell and re-collected from the zone models would delete every floor in the game and
	-- find nothing to replace them with.
	--
	-- The shell and the Zones folder are stamped with the same id. Same id means this is the same
	-- world the shell was built from, so its parts are handed back to their zones and re-collected
	-- below. No id, or a different one, means the Zones folder has been destroyed and regenerated
	-- under it (the BUILD_VERSION guard) -- in which case every part in the shell belongs to a zone
	-- that no longer exists, and handing them back would leave two of every platform.
	local previous = workspace:FindFirstChild("WorldShell")
	if previous then
		local sameWorld = previous:GetAttribute("ShellId") ~= nil
			and previous:GetAttribute("ShellId") == zonesFolder:GetAttribute("ShellId")
		if sameWorld then
			for _, part in ipairs(previous:GetChildren()) do
				local home = zonesFolder:FindFirstChild(part:GetAttribute("Zone") or "")
				if home then
					part.Parent = home
				else
					part:Destroy() -- its zone was rebuilt without it
				end
			end
		end
		previous:Destroy()
	end

	local shellId = HttpService:GenerateGUID(false)
	local shell = Instance.new("Model")
	shell.Name = "WorldShell"
	shell.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	shell:SetAttribute("ShellId", shellId)
	zonesFolder:SetAttribute("ShellId", shellId)

	local moved = 0
	for _, zoneModel in ipairs(zonesFolder:GetChildren()) do
		if zoneModel:IsA("Model") then
			for _, child in ipairs(zoneModel:GetChildren()) do
				if child:IsA("BasePart") and ALWAYS_LOADED[child.Name] then
					child:SetAttribute("Zone", zoneModel.Name)
					child.Parent = shell
					moved += 1
				end
			end
		end
	end

	shell.Parent = workspace
	print(("[ZoneBuilder] %d shell parts pinned against streaming"):format(moved))
	return shell
end

-- ===== WEATHER IS A STAMP ON THE ZONE, NOT A PART IN IT (34.7 / 34.15) =====
--
-- This used to build a 1500 x 1246 stud sheet 120 studs over the crest and hang one
-- ParticleEmitter on it. Two things were wrong with that and both are worth keeping written down.
--
-- THE PART WAS A FLOOR. `CanCollide = false` and `Transparency = 1` make a part you cannot touch
-- and cannot see; they do NOT make one a raycast cannot find, because `CanQuery` defaults to true.
-- Every pass in this game that seats something on the ground rays DOWNWARD from above, so the
-- first thing they met was this sheet and they reported the floor at y 198.50: the egg columns
-- were seated in the sky on every boot (`198.5/+200.1`) and the adventure board with them
-- (`the ray landed on Workspace.Zones.Forest.WeatherEmitter`). It was read as two separate bugs in
-- two separate rows. See [[roblox-canquery-ignored-when-collides]] for the half of that rule which
-- does NOT apply here -- CanQuery is honoured precisely because CanCollide is already false.
--
-- AND IT DREW NOTHING ANYWAY. ~1,000 live particles spread over 1,869,000 square studs is twenty
-- specks anywhere in a 200 x 200 view, and both of its textures (`6327318357`, `243082902`) fail
-- to load in this place at all -- measured on the running client, `IsLoaded = false` for both.
-- The weather is a camera-sized volume on the client now (`WeatherClient` + `WeatherLibrary`), so
-- what the server owes it is the DECISION, not the geometry: the zone model carries the kind and
-- the tint as attributes, and a rebuild carries them with it.
local function buildWeather(model, zone, cx)
	local weather = GameConfig.GetZoneWeather(zone.key)
	if not weather then return end

	model:SetAttribute("Weather", weather.kind)
	if weather.color then
		model:SetAttribute("WeatherColor", weather.color)
	end
	-- The client picks the nearest weather zone by this number rather than by the model's own
	-- bounding box: a zone model runs ~1230 studs wide once the rampart and the backdrop mesas are
	-- counted, and asking for a box costs a walk over every part in it on a client that is still
	-- streaming them in.
	model:SetAttribute("WeatherX", cx)
end

-- Moves (or creates) the one canonical SpawnLocation onto the Forest arrival clearing. Called at
-- the end of Build(), so the Forest floor it stands on already exists. Any extra SpawnLocations
-- are removed -- Roblox picks between them at random, so a stray one left in the Forest monument
-- footprint would still strand a share of players inside the shop.
function ZoneBuilder.EnsureSpawn()
	local spawn
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("SpawnLocation") then
			if spawn then
				d:Destroy()
			else
				spawn = d
			end
		end
	end

	if not spawn then
		spawn = Instance.new("SpawnLocation")
	end
	spawn.Name = "ForestSpawn"
	spawn.Size = Vector3.new(16, 1, 16)
	-- turned to look down the street: a spawn with no rotation drops you facing +Z, i.e. at the
	-- wall behind you, with the whole zone out of shot
	spawn.CFrame = CFrame.lookAt(SPAWN_POSITION, SPAWN_POSITION - Vector3.new(0, 0, 40))
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.Enabled = true -- a disabled spawn silently sends everyone back to (0, 100, 0)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(120, 255, 160)
	spawn.Material = Enum.Material.Neon
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	-- parented to workspace, never into Zones: the folder is destroyed wholesale on a version bump
	spawn.Parent = workspace

	if not spawn:FindFirstChild("SpawnRing") then
		local ring = newPart({
			Name = "SpawnRing",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.8, 26, 26),
			Orientation = Vector3.new(0, 0, 90),
			Position = SPAWN_POSITION - Vector3.new(0, 0.4, 0),
			Color = Color3.fromRGB(120, 255, 160),
			Material = Enum.Material.Neon,
			Transparency = 0.35,
			CanCollide = false,
			Parent = spawn,
		})
		addLight(ring, Color3.fromRGB(120, 255, 160), 34, 2)
	end

	return spawn
end

-- ===== ONE ZONE AT A TIME: THE DISTANCE FOG =====
-- Standing in one zone you could see the NEXT one's scenery over the boundary wall, which broke
-- the illusion that a zone is a place rather than one platform in a row of twenty.
--
-- Raising the walls does not fix it and the arithmetic says why. The wall is 180 studs. From an
-- eye 10 studs up, D studs back from it, the sight line clears the wall at slope (180-10)/D and
-- keeps climbing -- so the FURTHER you stand from a wall, the MORE you see over it. From the far
-- side of a 1250-wide platform that line is only ~353 studs high where the neighbour's Guardian
-- Titan stands, and the Titan is 507 tall. To occlude it the wall would have to be taller than
-- the Titan, and every zone would become a 520-stud canyon.
--
-- So the neighbours are hidden by DEPTH instead of by geometry, which costs nothing and reads as
-- weather rather than as a lid. The two numbers are picked off the actual layout:
--
--   own zone, arrival gate to far wall .... 1065 studs   <- must stay clear
--   own Guardian Titan behind that wall ... 1240 studs   <- may haze; it IS the horizon
--   neighbour's backdrop mesas ............ ~1900 studs   <- must be gone
--   neighbour's Titan ..................... ~2500 studs   <- must be gone
--
-- Fog colour is lifted from the Atmosphere already in the place rather than left on Roblox's grey
-- default, so the far end of a zone fades into its own sky instead of into smoke.
local FOG_START = 1100
local FOG_END = 1900

-- ===== AND THE REST OF THE LIGHT, WHICH USED TO LIVE NOWHERE =====
--
-- Everything below was a PLACE PROPERTY and nothing else: not one line in `src/` set `Ambient`,
-- `OutdoorAmbient`, `Brightness` or the colour grade, so the entire look of the world existed only
-- inside the .rbxl and could be lost by a bad save with no diff to show for it. It is code now for
-- that reason alone, before any question of what the values should be.
--
-- WHAT WAS ACTUALLY WRONG. Measured across Forest's 3,520 solid parts: mean saturation **0.301**,
-- mean value 0.676, with 44% of parts below 0.25 saturation. That is a pastel world, and the first
-- instinct -- push the part colours -- is the wrong lever: it makes the ground, which is the single
-- biggest surface in frame, MORE dominant rather than less. The cause was the light.
--
-- `Ambient` was (104, 110, 122). Ambient is the fill that reaches surfaces the sun does not, so a
-- high ambient means a shadow is barely darker than a lit face -- every object loses its shaded
-- side and the whole world flattens into painted cardboard. Dropping it is what gives all 83,000
-- parts a light side and a dark side at once, without touching a single colour.
--
-- `ClockTime` was 13.6, i.e. the sun almost overhead, which is the one angle that casts no usable
-- shadow at all. 15.8 rakes it low enough to throw a long shadow off every prop.
--
-- The grade (`ToonPunch`) then does the last of it. Contrast and saturation are pushed rather than
-- the part colours, because a grade cannot make one surface louder than another -- it lifts the
-- bunting and the boss and the sky together and leaves their relationship intact.
--
-- Haze came down 1.10 -> 0.55. The distance fog above is what hides the neighbouring zone; haze on
-- top of it was washing out the player's OWN zone at 300 studs, which is inside the platform.
local WORLD_AMBIENT = Color3.fromRGB(52, 56, 72)
local WORLD_OUTDOOR_AMBIENT = Color3.fromRGB(112, 122, 144)
local WORLD_CLOCK = 15.8
local WORLD_HAZE = 0.55
local WORLD_DENSITY = 0.18

-- ===== THE SKY, WHICH DID NOT EXIST =====
--
-- `Lighting` had no `Sky` child at all (checked 2026-08-14), so the world was rendering against
-- Roblox's built-in default. That default is not bad -- it is a soft blue with wispy cloud -- which
-- is exactly why nobody noticed. It is just not OURS: it is the sky every unfinished place ships
-- with, and it is the one part of the frame a player sees behind every zone.
--
-- THE TRAP THAT DECIDED THIS: A SKYBOX IS A LIGHT SOURCE, NOT A BACKDROP.
-- Under ShadowMap/Future the skybox feeds ambient. A texture with big white cloud masses in it
-- therefore floods the scene with fill light and undoes the entire contrast pass above -- with
-- `Ambient`, `OutdoorAmbient` and `ToonPunch` all left untouched and still reading their intended
-- values. Measured on the Forest arrival frame, the Guardian Titan 1240 studs out went from a
-- brown silhouette to a pale smear. Both cloud-painted candidates did this:
--
--   * "clouds skybox" (3146864089) ..... washed out, rejected
--   * "Cartoon SkyBox" (15387348852) ... washed out, rejected -- and this one nearly shipped,
--       because the FIRST capture after applying it still looked crisp. Skybox-derived ambient
--       settles a beat after the Sky is parented, so a capture taken immediately shows the OLD
--       lighting under the NEW sky. It read as the clear winner for exactly that reason.
--       >>> ALWAYS task.wait(~3) BETWEEN PARENTING A SKY AND CAPTURING IT. <<<
--   * "Clear Blue Sky" (18586545848) ... keeps the world crisp                        <- picked
--
-- Which leaves the obvious objection: a cloudless sky is a flat gradient with nothing in it. The
-- answer is that in 2026 clouds are not a skybox texture at all -- they are `Terrain.Clouds`,
-- which is real drifting volumetric geometry and, being geometry, contributes NOTHING to ambient.
-- See WORLD_CLOUDS below. That is the combination that gets both: cloud cover overhead and a
-- Titan that is still brown.
--
-- CelestialBodiesShown stays false -- the texture paints its own sun, and the engine's sun would
-- be a second, brighter one somewhere else in the sky.
--
-- The six ids are READ OFF the inserted asset, never transcribed from a store page. They are not
-- sequential (Up is ...94073, Dn is ...94459) and four of the six faces share one id, which is the
-- asset's own doing -- Lf/Rt/Ft/Bk are genuinely the same horizon image repeated.
local WORLD_SKY = {
	SkyboxUp = "rbxassetid://18586494073",
	SkyboxDn = "rbxassetid://18586494459",
	SkyboxLf = "rbxassetid://18586524369",
	SkyboxRt = "rbxassetid://18586524369",
	SkyboxFt = "rbxassetid://18586524369",
	SkyboxBk = "rbxassetid://18586524369",
	CelestialBodiesShown = false,
	StarCount = 0,
}

-- Cover 0.62 is scattered cloud rather than overcast: enough to break up the gradient from every
-- camera angle on the strip, not so much that the zone sits in permanent shade.
local WORLD_CLOUDS = {
	Cover = 0.62,
	Density = 0.55,
	Color = Color3.fromRGB(255, 255, 255),
	Enabled = true,
}

local function applyDistanceFog()
	local Lighting = game:GetService("Lighting")
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	Lighting.FogColor = atmosphere and atmosphere.Color or Color3.fromRGB(199, 215, 235)
	Lighting.FogStart = FOG_START
	Lighting.FogEnd = FOG_END

	Lighting.Ambient = WORLD_AMBIENT
	Lighting.OutdoorAmbient = WORLD_OUTDOOR_AMBIENT
	Lighting.ClockTime = WORLD_CLOCK
	Lighting.GlobalShadows = true
	if atmosphere then
		atmosphere.Haze = WORLD_HAZE
		atmosphere.Density = WORLD_DENSITY
	end
	-- The grade is created if it is missing, so a place that lost it still comes up looking right.
	local grade = Lighting:FindFirstChild("ToonPunch")
	if not grade then
		grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "ToonPunch"
		grade.TintColor = Color3.fromRGB(255, 252, 246)
		grade.Parent = Lighting
	end
	grade.Contrast = 0.26
	grade.Saturation = 0.38
	grade.Brightness = 0
	grade.Enabled = true

	-- ANY OTHER GRADE IS CLEARED, and for a harder version of the reason the Sky block below
	-- gives. Two Sky objects are merely undefined -- one of them wins. Two ColorCorrectionEffects
	-- do not compete at all: they STACK, both applying in full, and nothing anywhere reports it.
	-- The place shipped with a second, hand-made one simply called "ColorCorrection" (contrast
	-- 0.15, saturation 0.25) sitting on top of this one. Combined that is contrast 0.41 and
	-- saturation 0.63 against the 0.26 / 0.38 measured above, and it blew every lit surface out to
	-- flat white -- grass, stone and skin all clipping to the same colour, which reads as a broken
	-- render rather than as a strong grade. It was invisible to inspection precisely because BOTH
	-- effects read back exactly the values they were set to; only a capture shows it.
	--
	-- The paragraph at the top of this block says the look is code now so it cannot be lost by a
	-- bad save. The same argument applies the other way round: a look the code did not author must
	-- not be able to survive one. Found 2026-08-16.
	for _, other in ipairs(Lighting:GetChildren()) do
		if other:IsA("ColorCorrectionEffect") and other ~= grade then
			warn(("[ZoneBuilder] removing a second colour grade %q -- grades stack, they do not replace"):format(other.Name))
			other:Destroy()
		end
	end

	-- Same create-if-missing shape as the grade. Any OTHER Sky is cleared first: a stray one left
	-- behind by hand in Studio would otherwise sit next to this one, and which of two Sky objects
	-- Lighting actually renders is not defined -- so the look would depend on child order.
	local sky = Lighting:FindFirstChild("WorldSky")
	for _, other in ipairs(Lighting:GetChildren()) do
		if other:IsA("Sky") and other ~= sky then
			other:Destroy()
		end
	end
	if not sky then
		sky = Instance.new("Sky")
		sky.Name = "WorldSky"
		sky.Parent = Lighting
	end
	for prop, value in pairs(WORLD_SKY) do
		sky[prop] = value
	end

	-- Clouds live on Terrain, not in Lighting, and there can only ever be one.
	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	if not clouds then
		clouds = Instance.new("Clouds")
		clouds.Parent = workspace.Terrain
	end
	for prop, value in pairs(WORLD_CLOUDS) do
		clouds[prop] = value
	end
end

-- ===== BUILD() IS ONCE PER SERVER, AND THE SECOND CALL WAS NOT FREE OR SILENT (2026-08-15) =====
--
-- `ServerMain` calls Build() at boot, and `ZoneService.Init` -- which ServerMain calls ten lines
-- later -- called it a SECOND time. By then every zone carried `Complete`, so the second pass built
-- nothing: it swept 105,000 descendants looking for unanchored parts, re-pinned 2,073 shell parts,
-- and ran `auditSolidProps()` against a SOLID_SEEN that `table.clear` had just emptied and nothing
-- had refilled. That is the whole of the
--     "SOLID_PROPS has 52 name(s) nothing in this build ever created"
-- warning that has been printing every playtest: all 52 names HAD just been created, by the first
-- pass, and the audit was reading the second one. The list is not rot -- measured on the live world,
-- GroundRock, MoonRock, LavaRock, Shell, BenchSeat, FallenLog and MushroomCap all exist in it.
--
-- The duplicate call is gone from ZoneService, and this flag is what stops it coming back: an audit
-- is only worth reading for a pass that actually made something.
local built = false

function ZoneBuilder.Build()
	if built then return end
	built = true

	applyDistanceFog()
	ZoneKit.resetSolidSeen()

	local zonesFolder = workspace:FindFirstChild("Zones")

	-- version guard: geometry from an older build is dropped rather than kept, otherwise the
	-- per-zone skip below would preserve it forever and none of the biome work would ever show
	if zonesFolder and zonesFolder:GetAttribute("BuildVersion") ~= BUILD_VERSION then
		warn(("[ZoneBuilder] rebuilding world: stamp %s -> %d")
			:format(tostring(zonesFolder:GetAttribute("BuildVersion")), BUILD_VERSION))
		zonesFolder:Destroy()
		zonesFolder = nil
	end

	if not zonesFolder then
		zonesFolder = Instance.new("Folder")
		zonesFolder.Name = "Zones"
		zonesFolder.Parent = workspace
	end
	zonesFolder:SetAttribute("BuildVersion", BUILD_VERSION)

	for i, zone in ipairs(GameConfig.Zones) do
		-- ===== A LEAKED PLACEMENT FRAME MUST NOT CROSS INTO THE NEXT ZONE (32.32) =====
		-- `ZoneKit.withFrame` is what makes a builder that throws put the frame back, and it covers
		-- the two portals. The two inline blocks in `BiomeDecor` (the Volcano cone, the Celestial
		-- throne) still set and clear it by hand around forty lines of straight-line code, and this
		-- is the backstop for them and for anything added later: a frame that is still set when the
		-- next zone starts is a bug in the zone before it, and every part built through it lands
		-- hundreds of studs from where it was authored. It is stated out loud rather than repaired
		-- silently, because the zone that leaked it is also half-built.
		if ZoneKit.getFrame() ~= nil then
			warn(("[ZoneBuilder] %s: a placement frame was left set by the zone before it (%s) -- "
				.. "clearing it. See the note over ZoneKit.withFrame."):format(zone.key, tostring(ZoneKit.getFrame())))
			ZoneKit.setFrame(nil)
		end

		-- A HALF-BUILT ZONE IS NOT A BUILT ZONE. Studio drops the MCP connection fairly often in the
		-- middle of a full 50k-part Build(), which leaves the zone it was working on truncated -- and
		-- because the egg plaza is the LAST thing built per zone, what a truncated zone is missing is
		-- its eggs. The skip below then trusted the name alone and preserved that forever: one zone in
		-- the strip with no eggs in it and no way to tell from the code. The stamp goes on at the very
		-- end of the loop body, so anything that did not get there is dropped and rebuilt.
		local existing = zonesFolder:FindFirstChild(zone.key)
		if existing and not existing:GetAttribute("Complete") then
			warn(("[ZoneBuilder] %s was left half-built -- rebuilding it"):format(zone.key))
			existing:Destroy()
			existing = nil
		end
		if not existing then
			local model = Instance.new("Model")
			model.Name = zone.key
			model.Parent = zonesFolder

			local cx = zone.offset

			local floor = newPart({
				Name = "Floor",
				Size = Vector3.new(PLATFORM_WIDTH, 4, PLATFORM_DEPTH),
				Position = Vector3.new(cx, -2, 0),
				Color = groundColorOf(zone),
				Material = GROUND_MATERIAL[zone.key] or Enum.Material.SmoothPlastic,
				Parent = model,
			})
			model.PrimaryPart = floor

			local pad = newPart({
				Name = "ZonePad",
				Size = Vector3.new(14, 1, 14),
				Position = Vector3.new(cx, 0.5, ARRIVAL_Z),
				Color = zone.accentColor,
				Material = Enum.Material.Neon,
				Transparency = 1,
				CanCollide = false,
				Parent = model,
			})

			-- THE ARRIVAL SIGN, ON A POST.
			--
			-- Off to the side of the arrival clearing: at (cx, 255) this stood in the mouth of the +Z
			-- gate, exactly where the player now walks out. It was also the sign a player photographed
			-- and said "this just hangs in the air like that" -- and it did: a BillboardGui at y = 12
			-- with nothing whatsoever underneath it, turning to face the camera from every angle.
			--
			-- Now it is a signpost, built the same way as the walkway direction boards and left
			-- unrotated on purpose: its faces look along Z, which is the axis the player is walking
			-- down, so it is read head-on from the gate rather than edge-on.
			local signX = cx - 104
			newPart({ Name = "ArrivalSignPost", Size = Vector3.new(2.6, 21, 2.6), Position = Vector3.new(signX, 10.5, 310), Color = VILLAGE.dark, Material = Enum.Material.Wood, Parent = model })
			local arrivalBoard = newPart({ Name = "ArrivalSignBoard", Size = Vector3.new(32, 12, 1.8), Position = Vector3.new(signX, 27, 310), Color = VILLAGE.wood, Material = Enum.Material.WoodPlanks, CanCollide = false, Parent = model })
			for _, sx in ipairs({ -1, 1 }) do
				newPart({ Name = "ArrivalSignBatten", Size = Vector3.new(1.8, 14, 2.4), Position = Vector3.new(signX + sx * 15, 27, 310), Color = VILLAGE.dark, Material = Enum.Material.Wood, CanCollide = false, Parent = model })
				VillageKit.addKnob(model, Vector3.new(signX + sx * 15, 35, 310), 3.2, VILLAGE.cream)
			end
			addPlankText(arrivalBoard, zone.emoji .. " " .. zone.name, vivid(zone.accentColor), { maxDistance = 420, pixelsPerStud = 18 })
			local signLamp = newPart({ Name = "ArrivalSignLamp", Shape = Enum.PartType.Ball, Size = Vector3.new(3.4, 3.4, 3.4), Position = Vector3.new(signX, 36.4, 310), Color = vivid(zone.accentColor), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
			addLight(signLamp, vivid(zone.accentColor), 22, 1.8)

			-- fully enclose the zone in opaque walls -- the only way in/out is through the
			-- big portal gates below, so you never see a neighboring zone from here
			-- the sealing slab now only ever shows through the gaps between boulders, so it is the
			-- rampart's own shadow tone rather than the near-black accent*0.25 it used to be -- that
			-- colour read as a black void ringing every zone once the world was lit properly
			-- THE VILLAGE PALETTE, BEFORE ANYTHING THAT USES IT. Set here rather than beside
			-- ACTIVE_ZONE_KEY further down, because addZoneVillage runs in this block and the
			-- decoration builders run after it -- setting it there would have furnished every zone in
			-- the PREVIOUS zone's timber, which is a bug that looks exactly like no bug at all in
			-- nineteen zones out of twenty. See the palette note at the top of `VillageKit`.
			VillageKit.applyVillageStyle(zone.key)

			local _, wallColor = stoneTones(zone)
			local prevZone = GameConfig.Zones[i - 1]
			local nextZone = GameConfig.Zones[i + 1]
			local cliffTemplate = getCliffTemplate(zone.key)
			-- Gates go in the Z walls: the one back to the previous zone at +Z, behind where you
			-- land, and the one onward at -Z, past the shop. Arrival, street, eggs and exit are then
			-- one straight line you are already facing down. See GetZoneSpawnCFrame.
			buildXWall(model, zone, cx - PLATFORM_WIDTH/2, wallColor, nil)
			buildXWall(model, zone, cx + PLATFORM_WIDTH/2, wallColor, nil)
			buildZWall(model, zone, cx, -PLATFORM_DEPTH/2, wallColor, nextZone)
			-- Forest has no previous zone, so its +Z wall is the one boundary in the game with nothing
			-- behind it -- which is exactly where the arena gate goes. It stands directly behind the
			-- spawn clearing, so a player who lands in Forest has the street ahead and the Colosseum at
			-- their back, and no other zone has to give up a wall for it.
			local frontTarget = prevZone
			if not frontTarget and zone.key == "Forest" then
				frontTarget = {
					key = GameConfig.EventArena.key,
					name = GameConfig.EventArena.name,
					emoji = GameConfig.EventArena.emoji,
					accentColor = GameConfig.EventArena.accentColor,
					offset = cx,
				}
			end
			buildZWall(model, zone, cx, PLATFORM_DEPTH/2, wallColor, frontTarget)
			addGroundDetail(model, zone, cx)
			addZoneProps(model, zone, cx)
			addZoneVillage(model, zone, cx, i)

			-- extra rock clusters scattered inward from the edges so the walkable area
			-- itself feels like an irregular clearing among rocks, not a clean rectangle
			if cliffTemplate then
				for _ = 1, 16 do
					local edge = math.random(1, 4)
					local rx, rz
					if edge <= 2 then
						-- off the centre line, like everything else: this row runs along the Z walls,
						-- which is exactly where a gate opens at one end and the walk out of it begins
						-- at the other. |x| stays under 200, so this branch is on the valley floor and
						-- never in the terrace band.
						rx = cx + (math.random(1, 2) == 1 and -1 or 1) * math.random(STREET_HALF + 12, 200)
						local zSign = edge == 1 and -1 or 1
						rz = zSign * (PLATFORM_DEPTH / 2 - math.random(15, 65))
					else
						-- ===== "INWARD FROM THE EDGES" MEANS THE EDGE OF THE PLAYABLE GROUND (11.23) =====
						--
						-- This was written when a zone was a flat slab to the wall, and it still said so:
						-- `PLATFORM_WIDTH / 2 - random(15, 55)` puts a 40-stud rock mesh at |dx| 570..610,
						-- which is the third terrace up. Eight of them were measured intersecting a
						-- TerraceTop, six of those buried whole. The walkable edge has been TERRAIN_INNER
						-- since the terraces went in, so that is where the clearing's rim now is.
						local xSign = edge == 3 and -1 or 1
						rx = cx + xSign * math.random(TERRAIN_INNER - 55, TERRAIN_INNER - 18)
						rz = (math.random(1, 2) == 1) and math.random(80, 320) or math.random(-320, -80)
					end
					local rock = cliffTemplate:Clone()
					local scale = 0.35 + math.random() * 0.35
					rock:ScaleTo(scale)
					local geom = rock:FindFirstChild("body") and rock.body:FindFirstChild("body_geom")
					local halfHeight = (geom and geom.Size.Y / 2 or 65) * scale
					rock:PivotTo(CFrame.new(rx, halfHeight - 3, rz) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
					-- EVERY OTHER :Clone() IN THIS FILE DOES THIS AND THIS ONE NEVER DID. Generated
					-- meshes arrive unanchored and colliding: unanchored is a rock that falls through the
					-- world on the first physics step (the loose-part sweep at the end of Build catches
					-- it, which is why nobody noticed), and colliding is a mesh whose collision box is
					-- not its silhouette standing where players walk. Scenery, like every other cliff
					-- mesh in the file.
					for _, part in ipairs(rock:GetDescendants()) do
						if part:IsA("BasePart") then
							part.Anchored = true
							part.CanCollide = false
						end
					end
					rock.Parent = model
				end
			end

			-- THE VALLEY WALLS, BEFORE THE DECORATION. Called from here rather than from
			-- buildBiomeBase for one reason: buildBiomeBase takes a config table and not the zone,
			-- and threading `zone` through it would have meant editing all twenty biome builders to
			-- pass something none of them otherwise needs. Here the zone is already in hand, it is one
			-- line, and every zone gets terrain by construction instead of by remembering to opt in.
			ZoneTerrain.buildTerrain(model, zone, cx, GROUND_MATERIAL[zone.key])
		buildWeather(model, zone, cx)

			-- WHICH ZONE'S MESH PROPS TO CLONE. buildBiomeBase is handed a config table and not the
			-- zone -- twenty biome builders call it and not one of them passes anything else -- so the
			-- key is left here for it to pick up, at the one point where the zone is already in hand.
			-- Same reasoning as buildTerrain being called from this loop rather than from inside it.
			BiomeDecor.setZoneKey(zone.key)
			local builder = decorationBuilders[zone.key]
			if builder then
				builder(model, zone, cx)
			end
			BiomeDecor.setZoneKey(nil)

			-- AFTER the biome, BEFORE the stall: these are the biggest single objects a zone gets
			-- after its landmark, so they claim their ground while there is still ground to claim,
			-- and the stall sweep further down still gets the last word over all of them.
			ExtraProps.place(model, zone.key, cx)

			-- Pet Shop: 3 eggs (Basic/Better/Premium) on a lit podium plaza in the middle of the
			-- zone. Each egg has its own ProximityPrompt tagged with an EggKey attribute so
			-- PetService can wire purchases fresh on every server start.
			do
				local eggs = GameConfig.GetEggsForZone(zone.key)
				if #eggs > 0 then
					local shop = Instance.new("Model")
					shop.Name = "PetShop"
					shop.Parent = model

					local shells = EggPlaza.buildEggPlaza(shop, zone, cx, eggs)
					for i, egg in ipairs(eggs) do
						local promptParent = shells[i]
						if promptParent then
							local prompt = Instance.new("ProximityPrompt")
							prompt.ActionText = "Buy Egg"
							prompt.ObjectText = egg.cost .. " DNA"
							prompt.HoldDuration = 0.4
							-- the podium lifts the shell well above head height, so the old 14
							-- would only trigger from directly underneath it
							prompt.MaxActivationDistance = PROMPT_REACH
							prompt.RequiresLineOfSight = false
							prompt:SetAttribute("EggKey", egg.key)
							prompt.Parent = promptParent
						end
					end
				end
			end

			-- ===== NOTHING STANDS INSIDE AN IDOL PLINTH =====
			--
			-- Placement cannot solve this, and the arithmetic says why. An idol plinth is 150 studs
			-- across, so avoiding a crate means finding a point more than 117 studs from it -- and
			-- there are 44 such circles (18 crate stacks, 26 coins) on a scatter band only ~250 wide.
			-- No such point exists, so every idol exhausts its tries and takes the fallback. Proof it
			-- was unwinnable: ADDING the reservations made it worse, 320 swallowed props to 375.
			--
			-- So the plinths win and the props that lost go away, which is what the eye wants anyway:
			-- a monument standing clear beats a crate sealed invisibly inside one. Same shape as the
			-- stall sweep below, and for the same reason -- one rule at the end of the zone cannot be
			-- forgotten by any of the twenty biome builders.
			do
				local plinths = {}
				for _, p in ipairs(model:GetDescendants()) do
					if p:IsA("BasePart") and p.Name == "IdolPlinth" then
						plinths[#plinths + 1] = p
					end
				end
				if #plinths > 0 then
					local doomed = {}
					for _, p in ipairs(model:GetDescendants()) do
						-- only loose decoration: never the idol's own stonework, never the ground,
						-- never the street, and never an invisible particle carrier
						-- ...and never the arrival sign. It is a fixed installation like the floor and the
						-- path, not loose decoration, and it is the one thing here that BREAKS when it is
						-- half-eaten: the post goes, the board and its two battens do not (they sit above
						-- the plinth top and fail the height test), and what is left is a board hanging in
						-- mid-air. The corner fix above should mean no plinth ever reaches it; this is here
						-- so that if one ever does, the failure is a post standing near a plinth rather
						-- than a floating sign.
						if p:IsA("BasePart") and p.Transparency < 1
							and not string.match(p.Name, "^Idol") and p.Name ~= "Floor"
							and not string.match(p.Name, "^ArrivalSign")
							and p.Name ~= "PathSlab" and p.Name ~= "PathStone" then
							for _, pl in ipairs(plinths) do
								local d = p.Position - pl.Position
								-- inside the footprint and below the top of the plinth: anything
								-- above that is standing ON it, which is fine
								if math.abs(d.X) < pl.Size.X / 2 and math.abs(d.Z) < pl.Size.Z / 2
									and p.Position.Y < pl.Position.Y + pl.Size.Y / 2 then
									doomed[#doomed + 1] = p
									break
								end
							end
						end
					end
					for _, p in ipairs(doomed) do
						p:Destroy()
					end
				end
			end

			-- ===== NOTHING STANDS INSIDE THE EGG STALL =====
			--
			-- The stall is the one building every player walks into in every zone, and each biome's
			-- signature feature was drawing straight through it: Volcano laid a lava bank and a lit
			-- lava flow across the shop's wooden deck at the same height as the planks, VoidExpanse
			-- opened a hole in the floor underneath it, CelestialThrone ran four colonnade pillars and
			-- a carpet through it, Moon put a crater in it, Singularity and AbsolutePlane drew grid
			-- lines over it.
			--
			-- Those are FIXED features, not scattered ones -- they never asked scatterPoint for a
			-- point, so no reservation could have stopped them, and teaching twenty biome builders
			-- about the stall would be twenty edits and twenty chances to forget. A sweep at the end
			-- of the zone is one rule that cannot be forgotten and catches the cases nobody has found
			-- yet as well as the seven above.
			--
			-- Only ground-level decoration is taken: anything whose centre is inside the stall's
			-- footprint and below the top of its board. The shop's own parts are recognised by being
			-- parented under it, so nothing the stall is made of can ever delete itself.
			do
				local shop = model:FindFirstChild("PetShop")
				if shop then
					-- MEASURED OFF THE SHOP, not typed in. The stall is 123 x 45 and sits at z = -6,
					-- not on the centre line, so a hand-written box centred on 0 misses a slice of it
					-- at one end and eats clean ground at the other. A little tighter than the true
					-- extents (0.46 rather than half) because the outermost parts are the sign battens
					-- and posts, and the ground beside them is legitimately decorated.
					local shopCF, shopSize = shop:GetBoundingBox()
					local HALF_X, HALF_Z, TOP = shopSize.X * 0.46, shopSize.Z * 0.46, 30
					local doomed = {}
					for _, part in ipairs(model:GetDescendants()) do
						if part:IsA("BasePart") and not part:IsDescendantOf(shop) then
							local p = part.Position
							if math.abs(p.X - shopCF.Position.X) < HALF_X
								and math.abs(p.Z - shopCF.Position.Z) < HALF_Z
								and p.Y < TOP and p.Y > -6 then
								-- Three exemptions, and each is load-bearing.
								--
								-- The floor and the street are MEANT to run under the stall.
								--
								-- Fully transparent parts are the particle carriers -- the zone
								-- atmosphere sheet is 640 x 800 studs of invisible plate and its
								-- centre lands right here. It draws nothing through the shop and
								-- deleting it would take that zone's whole ambience with it.
								if part.Transparency < 1 and part.Name ~= "Floor"
									and part.Name ~= "PathSlab" and part.Name ~= "PathStone" then
									table.insert(doomed, part)
								end
							end
						end
					end
					for _, part in ipairs(doomed) do
						part:Destroy()
					end
				end
			end

			-- last line of the loop body on purpose: see the note at the top of it
			model:SetAttribute("Complete", true)
		end
	end

	-- the arena hangs off the Zones folder so the version guard drops and rebuilds it with
	-- everything else -- it is world geometry like any other -- but it also has its own stamp, so
	-- moving or redressing it does not cost a full world rebuild
	local arena = zonesFolder:FindFirstChild("EventArena")
	if arena and arena:GetAttribute("ArenaVersion") ~= EventArena.ARENA_VERSION then
		warn(("[ZoneBuilder] rebuilding the Colosseum: stamp %s -> %d")
			:format(tostring(arena:GetAttribute("ArenaVersion")), EventArena.ARENA_VERSION))
		arena:Destroy()
		arena = nil
	end
	if not arena then
		EventArena.buildEventArena(zonesFolder)
	end

	ZoneBuilder.EnsureSpawn()

	-- Every decoration in the world is anchored, unconditionally, as the last thing Build() does.
	-- newPart() anchors what it makes, but the AI-generated meshes in ServerStorage (trees, cacti,
	-- cliffs, the Desert statue) ship unanchored, and cloning + PivotTo does not change that. They
	-- sat still until the first player spawned and woke physics, and then the whole set slid and
	-- toppled. Sweeping the finished folder is cheaper than trusting every future template to be
	-- authored correctly.
	local loose = 0
	for _, d in ipairs(zonesFolder:GetDescendants()) do
		if d:IsA("BasePart") and not d.Anchored then
			d.Anchored = true
			loose += 1
		end
	end
	if loose > 0 then
		warn(("[ZoneBuilder] anchored %d loose decoration parts"):format(loose))
	end

	keepShellLoaded(zonesFolder)
	ZoneKit.auditSolidProps()
end

-- Where a player lands when they enter `zoneKey`, and which way they are turned: ALWAYS at the +Z
-- end, looking down the street, whichever direction they arrived from.
--
-- It used to mirror to -Z when you walked back down the strip, on the reasoning that you should
-- step out of the gate you stepped into. That stopped being true the moment the boss moved onto
-- the street: the -Z arrival point sits at z = -212 and the boss arena is a 116-stud circle around
-- z = -132, so coming back to a zone dropped the player straight onto the boss's dais. Arriving at
-- the front every time also means the walk is always the same one -- gate, village, eggs, boss,
-- exit -- rather than being run backwards half the time.
--
-- `fromZoneKey` is kept in the signature because ZoneService passes it and it is still the right
-- thing to know here; it simply no longer changes the answer.
function ZoneBuilder.GetZoneSpawnCFrame(zoneKey, _fromZoneKey)
	local zone = GameConfig.GetZoneByKey(zoneKey) or GameConfig.Zones[1]
	local pos = Vector3.new(zone.offset, 5, ARRIVAL_Z)
	return CFrame.lookAt(pos, pos - Vector3.new(0, 0, 40))
end

-- Kept for callers that only want the point.
function ZoneBuilder.GetZoneSpawnPosition(zoneKey, fromZoneKey)
	return ZoneBuilder.GetZoneSpawnCFrame(zoneKey, fromZoneKey).Position
end

-- Where a player lands in the event arena: at the near rim, looking across the sand at the dais.
function ZoneBuilder.GetArenaSpawnCFrame()
	local cfg = GameConfig.EventArena
	local pos = Vector3.new(cfg.centre.X, 9, cfg.arrivalZ)
	return CFrame.lookAt(pos, pos + Vector3.new(0, 0, 40))
end

return ZoneBuilder

