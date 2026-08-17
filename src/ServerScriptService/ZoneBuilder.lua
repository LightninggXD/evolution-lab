local RS = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local GameConfig = require(RS.Modules.GameConfig)
local PetModel = require(RS.Modules.PetModel)

local ZoneBuilder = {}

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
local BUILD_VERSION = 135

-- The Colosseum carries its own stamp. Bumping BUILD_VERSION drops all 21 zones and rebuilds
-- ~60,000 parts, which takes long enough that Studio regularly loses the connection partway (see
-- the half-built-zone guard in Build). The arena is ~900 parts, it is reached only by teleport,
-- and it has already had to move once -- so it gets a stamp of its own and is rebuilt alone.
local ARENA_VERSION = 2

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

-- ===== portal gateway =====
-- The gate is the landmark on every zone boundary, so it is built as real stonework instead of
-- a lit hole in the wall: two flanking columns with diamond inlays and a stepped capital, a
-- rune-studded frame hugging the opening, a lintel under an overhanging cap, and a swirling
-- energy sheet. It all lives in the YZ plane at x = wallX, so "width" runs along Z and "depth"
-- along X, and detail parts are only built on the one face a player can ever stand in front of.
local PORTAL_OPEN_H = 138     -- height of the energy sheet; its width is PORTAL_GAP
local PORTAL_CLEAR_HALF = 132 -- how far boulders stay off the centre line, see addCliffLine
local PORTAL_STONE = Color3.fromRGB(129, 154, 184)
local PORTAL_STONE_DARK = Color3.fromRGB(92, 114, 145)
local PORTAL_STONE_LITE = Color3.fromRGB(163, 185, 211)
local PORTAL_FRAME = Color3.fromRGB(45, 84, 145)
local PORTAL_DEEP = Color3.fromRGB(20, 38, 74)

-- One gateway, centred on (wallX, 0) in the wall plane. `target` is the zone it leads to, and its
-- accent colour drives every glowing element so the gate still tells you where it goes.
local function buildPortal(model, wallX, target, faceOverride)
	-- the far side of a boundary wall is the empty gap between platforms and is never walkable,
	-- so only the interior face needs runes and inlays -- that halves the part count per gate.
	-- A gate stood through ACTIVE_FRAME passes its facing in, since in that case the target's
	-- world offset says nothing about which side of the *local* plane the zone is on.
	local face = faceOverride or ((target.offset < wallX) and 1 or -1)
	local accent = vivid(target.accentColor)
	local glow = accent:Lerp(Color3.new(1, 1, 1), 0.4)
	local gapHalf = PORTAL_GAP / 2
	local openH = PORTAL_OPEN_H
	local midY = openH / 2

	-- Every gate used to be cut from the same blue stone, so from across a zone the two exits were
	-- indistinguishable and neither told you where it went. Tinting the masonry toward the
	-- destination's accent keeps it reading as stone while making the gate itself the signpost.
	local stone = PORTAL_STONE:Lerp(accent, 0.3)
	local stoneDark = PORTAL_STONE_DARK:Lerp(accent, 0.3)
	local stoneLite = PORTAL_STONE_LITE:Lerp(accent, 0.22)
	local frame = PORTAL_FRAME:Lerp(target.accentColor, 0.55)

	-- ENERGY: the sheet you walk into. Opaque neon, so it hints at the destination colour
	-- without ever showing the zone behind it.
	local gate = newPart({
		Name = "PortalGate",
		Size = Vector3.new(2, openH, PORTAL_GAP),
		Position = Vector3.new(wallX, midY, 0),
		Color = accent,
		Material = Enum.Material.Neon,
		Transparency = 0.05,
		-- Solid, not a curtain. Walking into the sheet fires Touched and ZoneService teleports you --
		-- but it refuses while the destination is still locked, and with the sheet passable that same
		-- step carried the player straight on through the opening and off the world: there is no
		-- floor at all in the gap between two platforms. A blocked contact still fires Touched, so
		-- an open gate works exactly as before.
		CanCollide = true,
		CanTouch = true,
		CastShadow = false,
		Parent = model,
	})
	gate:SetAttribute("TargetZone", target.key)

	-- two counter-rotating pinwheels in front of the sheet give it the swirl. Each blade is a
	-- diameter through the centre, so a set at 0/60/120 deg is unchanged by a 60 deg turn.
	-- Thin and mostly transparent on purpose. The first pass used five fat opaque blades and the
	-- gate read as a white asterisk painted on a yellow board rather than as moving light.
	for i = 0, 2 do
		local base = CFrame.new(wallX + face * 1.6, midY, 0) * CFrame.Angles(math.rad(i * 60), 0, 0)
		local blade = newPart({ Name = "PortalBlade", Size = Vector3.new(0.6, 2.4, 74), CFrame = base, Color = glow, Material = Enum.Material.Neon, Transparency = 0.74, CanCollide = false, CastShadow = false, Parent = model })
		spinForever(blade, base, 60, 13)
	end
	for i = 0, 1 do
		local base = CFrame.new(wallX + face * 2.3, midY, 0) * CFrame.Angles(math.rad(45 + i * 90), 0, 0)
		local blade = newPart({ Name = "PortalBlade", Size = Vector3.new(0.6, 4.5, 50), CFrame = base, Color = Color3.new(1, 1, 1), Material = Enum.Material.Neon, Transparency = 0.85, CanCollide = false, CastShadow = false, Parent = model })
		spinForever(blade, base, -90, 8)
	end

	-- the eye of the vortex: three nested discs, each brighter and smaller, so the blades read as
	-- spinning *into* something instead of crossing in empty space
	for i, d in ipairs({ 34, 21, 11 }) do
		local core = newPart({ Name = "PortalCore", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, d, d), Orientation = Vector3.new(0, 90, 0), Position = Vector3.new(wallX + face * (1.2 + i * 0.35), midY, 0), Color = i == 3 and Color3.new(1, 1, 1) or glow, Material = Enum.Material.Neon, Transparency = 0.62 - i * 0.14, CanCollide = false, CastShadow = false, Parent = model })
		pulseForever(core, 0.82 - i * 0.16, 2.4 + i * 0.7)
	end

	-- vertical streaks breathing out of phase: the "liquid light" read of the reference art
	for i, z in ipairs({ -27, -10, 10, 27 }) do
		local streak = newPart({ Name = "PortalStreak", Size = Vector3.new(0.5, openH - 18, 3.4), Position = Vector3.new(wallX + face * 3, midY, z), Color = glow, Material = Enum.Material.Neon, Transparency = 0.42, CanCollide = false, CastShadow = false, Parent = model })
		pulseForever(streak, 0.85, 1.5 + i * 0.5)
	end

	-- LIP: a dark rebate right against the glow so the sheet has a crisp edge instead of
	-- bleeding straight into the stonework
	local lipT, lipD = 6, 16
	newPart({ Name = "PortalLip", Size = Vector3.new(lipD, openH + lipT, lipT), Position = Vector3.new(wallX, midY + lipT / 2, -(gapHalf + lipT / 2)), Color = PORTAL_DEEP, Material = Enum.Material.SmoothPlastic, Parent = model })
	newPart({ Name = "PortalLip", Size = Vector3.new(lipD, openH + lipT, lipT), Position = Vector3.new(wallX, midY + lipT / 2, gapHalf + lipT / 2), Color = PORTAL_DEEP, Material = Enum.Material.SmoothPlastic, Parent = model })
	newPart({ Name = "PortalLip", Size = Vector3.new(lipD, lipT, PORTAL_GAP + lipT * 2), Position = Vector3.new(wallX, openH + lipT / 2, 0), Color = PORTAL_DEEP, Material = Enum.Material.SmoothPlastic, Parent = model })
	-- ... and a sill, because the sheet never touches the floor in the reference art. It has to
	-- be non-colliding: it stands in the walkway, and the gate must stay reachable by a player.
	newPart({ Name = "PortalSill", Size = Vector3.new(lipD + 2, 9, PORTAL_GAP + lipT * 2), Position = Vector3.new(wallX, 4.5, 0), Color = PORTAL_DEEP, Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })

	-- FRAME: the blue band that carries the runes. Its top piece doubles as the wall above the
	-- opening, so there is never a line of sight between the sheet and the lintel.
	local bandT, bandD = 14, 22
	local bandZ = gapHalf + lipT + bandT / 2
	local bandH = openH + lipT + bandT
	local bandTopY = bandH - bandT / 2
	newPart({ Name = "PortalFrame", Size = Vector3.new(bandD, bandH, bandT), Position = Vector3.new(wallX, bandH / 2, -bandZ), Color = frame, Material = Enum.Material.SmoothPlastic, Parent = model })
	newPart({ Name = "PortalFrame", Size = Vector3.new(bandD, bandH, bandT), Position = Vector3.new(wallX, bandH / 2, bandZ), Color = frame, Material = Enum.Material.SmoothPlastic, Parent = model })
	newPart({ Name = "PortalFrame", Size = Vector3.new(bandD, bandT, PORTAL_GAP + (lipT + bandT) * 2), Position = Vector3.new(wallX, bandTopY, 0), Color = frame, Material = Enum.Material.SmoothPlastic, Parent = model })

	-- Runes, not rivets. Square neon tiles in a near-white glow read as a row of light bulbs
	-- around a cinema sign; a rotated diamond with a darker keeper behind it reads as carved.
	local runeX = wallX + face * (bandD / 2 + 0.4)
	local function rune(y, z)
		newPart({ Name = "PortalRuneKeeper", Size = Vector3.new(1, 9, 9), Orientation = Vector3.new(45, 0, 0), Position = Vector3.new(runeX, y, z), Color = PORTAL_DEEP, Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = model })
		newPart({ Name = "PortalRune", Size = Vector3.new(1.6, 5.4, 5.4), Orientation = Vector3.new(45, 0, 0), Position = Vector3.new(runeX + face * 0.5, y, z), Color = accent, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = model })
	end
	for _, z in ipairs({ -bandZ, bandZ }) do
		for row = 0, 5 do
			rune(16 + row * 22, z)
		end
	end
	for _, z in ipairs({ -30, 0, 30 }) do
		rune(bandTopY, z)
	end

	-- LINTEL + CAP: the heavy beam that makes the gate read as built rather than carved
	local lintelY = bandH + 8
	newPart({ Name = "PortalLintel", Size = Vector3.new(bandD + 4, 17, 150), Position = Vector3.new(wallX, lintelY, 0), Color = PORTAL_STONE, Material = Enum.Material.Concrete, Parent = model })
	newPart({ Name = "PortalCap", Size = Vector3.new(bandD + 12, 9, 164), Position = Vector3.new(wallX, lintelY + 13, 0), Color = PORTAL_STONE_LITE, Material = Enum.Material.Concrete, Parent = model })

	-- KEYSTONE: a cut gem sitting in the middle of the lintel. A gateway this wide needs a centre
	-- or the eye slides straight off the beam -- and it is the one piece that is pure jewellery.
	newPart({ Name = "PortalKeystoneSetting", Size = Vector3.new(bandD + 6, 26, 26), Orientation = Vector3.new(45, 0, 0), Position = Vector3.new(wallX, lintelY, 0), Color = stoneDark, Material = Enum.Material.Concrete, Parent = model })
	local keystone = newPart({ Name = "PortalKeystone", Size = Vector3.new(bandD + 9, 15, 15), Orientation = Vector3.new(45, 0, 0), Position = Vector3.new(wallX + face * 1.5, lintelY, 0), Color = accent, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = model })
	addLight(keystone, accent, 40, 3)
	pulseForever(keystone, 0.35, 2.6)

	-- DRAPES: two banners hanging off the lintel, either side of the keystone. Cloth against all
	-- that stone is what stops the gate reading as a tomb entrance.
	for _, sz in ipairs({ -52, 52 }) do
		newPart({ Name = "PortalDrape", Size = Vector3.new(1.2, 46, 26), Position = Vector3.new(wallX + face * (bandD / 2 + 1), lintelY - 30, sz), Color = frame, Material = Enum.Material.Fabric, CanCollide = false, Parent = model })
		newPart({ Name = "PortalDrapeTrim", Size = Vector3.new(1.6, 5, 27), Position = Vector3.new(wallX + face * (bandD / 2 + 1.4), lintelY - 12, sz), Color = accent, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = model })
		newPart({ Name = "PortalDrapeTail", Shape = Enum.PartType.Wedge, Size = Vector3.new(1.2, 12, 26),
			CFrame = CFrame.new(wallX + face * (bandD / 2 + 1), lintelY - 59, sz) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.pi),
			Color = frame, Material = Enum.Material.Fabric, CanCollide = false, Parent = model })
	end

	-- COLUMNS: free-standing either side with a visible reveal, so the silhouette reads as
	-- column / gate / column rather than one slab
	local colW, colD, colH = 30, 26, 146
	local colZ = bandZ + bandT / 2 + 4 + colW / 2
	for _, sz in ipairs({ -colZ, colZ }) do
		newPart({ Name = "PortalColumnBase", Size = Vector3.new(colD + 6, 9, colW + 6), Position = Vector3.new(wallX, 4.5, sz), Color = stoneDark, Material = Enum.Material.Concrete, Parent = model })
		newPart({ Name = "PortalColumn", Size = Vector3.new(colD, colH, colW), Position = Vector3.new(wallX, colH / 2 + 4, sz), Color = stone, Material = Enum.Material.Concrete, Parent = model })
		newPart({ Name = "PortalColumnCap", Size = Vector3.new(colD + 6, 12, colW + 6), Position = Vector3.new(wallX, colH + 10, sz), Color = stoneDark, Material = Enum.Material.Concrete, Parent = model })
		newPart({ Name = "PortalColumnCap", Size = Vector3.new(colD + 11, 6, colW + 11), Position = Vector3.new(wallX, colH + 19, sz), Color = stoneLite, Material = Enum.Material.Concrete, Parent = model })
		-- diamond inlays: a dark lozenge with a lighter core, the signature detail of the art
		for row = 0, 3 do
			local y = 28 + row * 34
			newPart({ Name = "ColumnInlay", Size = Vector3.new(1.6, 13, 13), Orientation = Vector3.new(45, 0, 0), Position = Vector3.new(wallX + face * (colD / 2 + 0.5), y, sz), Color = stoneDark, Material = Enum.Material.Concrete, CanCollide = false, Parent = model })
			newPart({ Name = "ColumnInlay", Size = Vector3.new(1.6, 7, 7), Orientation = Vector3.new(45, 0, 0), Position = Vector3.new(wallX + face * (colD / 2 + 1.4), y, sz), Color = row == 1 and accent or stoneLite, Material = row == 1 and Enum.Material.Neon or Enum.Material.Concrete, CanCollide = false, Parent = model })
		end
		-- a lit brazier on each capital, so the gate is legible at any ClockTime and from the far
		-- side of the platform
		local flame = newPart({ Name = "PortalFlame", Shape = Enum.PartType.Ball, Size = Vector3.new(13, 15, 13), Position = Vector3.new(wallX, colH + 28, sz), Color = accent, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = model })
		addLight(flame, accent, 52, 4)
		pulseForever(flame, 0.4, 1.9)
	end

	-- CRYSTALS: four shards turning slowly in the mouth of the gate, two either side. They are the
	-- only moving thing at the boundary that is not the sheet itself, and they sell the gate as
	-- charged rather than merely lit.
	for i, spec in ipairs({ { -1, 34, 74 }, { 1, 34, 74 }, { -1, 96, 58 }, { 1, 96, 58 } }) do
		local base = CFrame.new(wallX + face * 7, spec[2], spec[1] * spec[3]) * CFrame.Angles(0, 0, math.rad(spec[1] * 16))
		local shard = newPart({ Name = "PortalCrystal", Size = Vector3.new(5, 19, 5), CFrame = base, Color = glow, Material = Enum.Material.Neon, Transparency = 0.22, CanCollide = false, CastShadow = false, Parent = model })
		addLight(shard, accent, 26, 2)
		spinForever(shard, base, 360, 9 + i)
	end

	-- GUARDIANS: a squat statue on a plinth either side of the steps. Two of them turn a doorway
	-- into a threshold somebody built and meant, which is the whole difference between a gate and
	-- a hole in a wall.
	for _, sz in ipairs({ -1, 1 }) do
		local gz = sz * (PORTAL_GAP / 2 + 46)
		local gx = wallX + face * 46
		newPart({ Name = "GuardianPlinth", Size = Vector3.new(26, 12, 26), Position = Vector3.new(gx, 6, gz), Color = stoneDark, Material = Enum.Material.Concrete, Parent = model })
		newPart({ Name = "GuardianPlinthTrim", Size = Vector3.new(29, 2.4, 29), Position = Vector3.new(gx, 13, gz), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		newPart({ Name = "GuardianBody", Size = Vector3.new(19, 26, 17), Orientation = Vector3.new(0, face * -90, 0), Position = Vector3.new(gx, 26, gz), Color = stone, Material = Enum.Material.Concrete, Parent = model })
		newPart({ Name = "GuardianHead", Size = Vector3.new(15, 14, 14), Orientation = Vector3.new(0, face * -90, 0), Position = Vector3.new(gx, 45, gz), Color = stoneLite, Material = Enum.Material.Concrete, Parent = model })
		for _, ex in ipairs({ -1, 1 }) do
			newPart({ Name = "GuardianEye", Size = Vector3.new(2, 3, 3), Position = Vector3.new(gx + face * 7.4, 47, gz + ex * 3.6), Color = accent, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = model })
		end
		-- folded arms, and a horn either side of the head: a readable silhouette at four parts
		newPart({ Name = "GuardianArms", Size = Vector3.new(21, 6, 12), Orientation = Vector3.new(0, face * -90, 0), Position = Vector3.new(gx + face * 2, 24, gz), Color = stoneDark, Material = Enum.Material.Concrete, CanCollide = false, Parent = model })
		for _, ex in ipairs({ -1, 1 }) do
			newPart({ Name = "GuardianHorn", Size = Vector3.new(4, 12, 4), Orientation = Vector3.new(0, 0, ex * 24), Position = Vector3.new(gx, 55, gz + ex * 6), Color = stoneDark, Material = Enum.Material.Concrete, CanCollide = false, Parent = model })
		end
		local bowl = newPart({ Name = "GuardianBrazier", Shape = Enum.PartType.Ball, Size = Vector3.new(11, 12, 11), Position = Vector3.new(gx, 64, gz), Color = accent, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = model })
		addLight(bowl, accent, 44, 3)
		pulseForever(bowl, 0.4, 2.2 + (sz > 0 and 0.5 or 0))
	end

	-- APPROACH: a lit mat and three steps in front of the opening. Without them the gate is a door
	-- with no doorstep -- the ground just runs into it and there is nothing telling you to walk in.
	-- tallest against the wall, shortest furthest out, so the run actually climbs toward the gate
	for i = 1, 4 do
		local h = 6.4 - (i - 1) * 1.6
		newPart({ Name = "PortalStep", Size = Vector3.new(12, h, PORTAL_GAP + 34 - i * 6), Position = Vector3.new(wallX + face * (9 + (i - 1) * 11), h / 2, 0), Color = i == 1 and stoneLite or stone, Material = Enum.Material.Concrete, Parent = model })
	end
	newPart({ Name = "PortalMat", Size = Vector3.new(34, 0.4, PORTAL_GAP - 2), Position = Vector3.new(wallX + face * 56, 0.4, 0), Color = accent, Material = Enum.Material.Neon, Transparency = 0.5, CanCollide = false, CastShadow = false, Parent = model })

	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Color = ColorSequence.new(Color3.new(1, 1, 1), accent)
	sparkle.Rate = 14
	sparkle.Lifetime = NumberRange.new(1.4, 2.6)
	sparkle.Speed = NumberRange.new(3, 7)
	sparkle.SpreadAngle = Vector2.new(14, 14)
	sparkle.Size = NumberSequence.new(1.6, 0.2)
	sparkle.Transparency = NumberSequence.new(0.15, 1)
	sparkle.LightEmission = 1
	sparkle.Parent = gate

	local light = Instance.new("PointLight")
	light.Color = accent
	light.Range = 46
	light.Brightness = 4
	light.Parent = gate

	-- THE NAME BOARD, BOLTED TO THE GATE.
	--
	-- It was a BillboardGui hanging 26 studs over the lintel, and a billboard turns to face the
	-- camera: from anywhere except straight on it read as a sign hovering in mid-air beside the
	-- gate rather than as part of it, and from behind the wall it still faced you, through solid
	-- stone. A player asked for exactly this and was right -- it should sit ON the gateway, the way
	-- the walkway direction signs sit on their posts.
	--
	-- So: a real board standing on the cap, with the name painted onto both broad faces. Built with
	-- a 90-degree yaw because buildPortal works in the plane x = wallX -- the board's own length has
	-- to run along Z (the wall) and its faces have to look along X (out of the zone and into it).
	-- 104 x 34 rather than the full 164 of the cap it stands on. A board matched to the stonework
	-- came out five times wider than it was tall, and the name is one short word: TextScaled fills
	-- by HEIGHT, so all the extra width bought was empty plate either side of a small word.
	local boardY = lintelY + 33
	local boardHalf = 52
	local boardWood = Color3.fromRGB(122, 84, 50)
	local boardTurn = CFrame.Angles(0, math.rad(90), 0)
	local board = newPart({ Name = "PortalNameBoard", Size = Vector3.new(boardHalf * 2, 34, 4),
		CFrame = CFrame.new(wallX + face * 2, boardY, 0) * boardTurn,
		Color = boardWood, Material = Enum.Material.WoodPlanks, CanCollide = false, Parent = model })
	-- a batten across each end, so it reads as joined boards rather than one slab -- the same
	-- detail the walkway signs use, which is what makes the two read as the same set of objects
	for _, sz in ipairs({ -1, 1 }) do
		newPart({ Name = "PortalNameBatten", Size = Vector3.new(5, 39, 5.4),
			CFrame = CFrame.new(wallX + face * 2, boardY, sz * (boardHalf - 2)) * boardTurn,
			Color = stoneDark, Material = Enum.Material.Wood, CanCollide = false, Parent = model })
		newPart({ Name = "PortalNameKnob", Shape = Enum.PartType.Ball, Size = Vector3.new(8, 8, 8),
			Position = Vector3.new(wallX + face * 2, boardY + 19.5, sz * (boardHalf - 2)),
			Color = stoneLite, Material = Enum.Material.Concrete, CanCollide = false, Parent = model })
	end
	-- Long reach and a MUCH coarser canvas than the walkway signs get. Both halves of that matter,
	-- and the second one is not an optimisation -- it is the difference between the board having
	-- text on it and not. A SurfaceGui's canvas is PixelsPerStud x the part, so on a board this size
	-- the walkway's 32 px/stud is a 3,300 x 1,000 texture for one word, and a canvas that large
	-- stops being drawn well before MaxDistance -- measured: blank from 250 studs, which is exactly
	-- the range this sign exists to be read at. 8 still leaves the word ~670 px wide.
	addPlankText(board, "🌀 " .. target.emoji .. " " .. target.name, vivid(target.accentColor),
		{ maxDistance = 700, pixelsPerStud = 8 })
end

-- The same gateway, stood in a Z wall. buildPortal is written in the plane x = wallX with +X
-- pointing into the zone, so all this does is hand it that plane: yaw +90 for the far (+Z) wall,
-- -90 for the near one, and the interior is local +X in both cases.
--
-- The gates moved off the X walls for one reason: arriving in a zone, walking the street, buying
-- an egg and leaving by the next gate now happen along one straight line down the middle of the
-- platform. On the X walls they sat at right angles to that line, so the shop and its walkway
-- read as rotated ninety degrees from the way the player was actually facing.
local function buildPortalInZWall(model, cx, wallZ, target)
	local previous = ZoneKit.getFrame()
	ZoneKit.setFrame(CFrame.new(cx, 0, wallZ) * CFrame.Angles(0, math.rad(wallZ > 0 and 90 or -90), 0))
	buildPortal(model, 0, target, 1)
	ZoneKit.setFrame(previous)
end

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
local function buildMysteryOddsBoard(model, base, S, color)
	local odds = GameConfig.GetMysterySizeOdds()
	if #odds == 0 then return nil end

	local anchor = newPart({
		Name = "MysteryOddsAnchor",
		Size = Vector3.new(1, 1, 1),
		-- where the old odds sign hung: clear of the counter's bottles below and of the canopy
		-- fascia above, on the street side of the stall so it is read from the forecourt
		CFrame = base * CFrame.new(0, 18.4 * S, 15 * S),
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
	local counter = VillageKit.addStall(model, base, color, shopDef.title, {
		color, color:Lerp(Color3.new(1, 1, 1), 0.4), color:Lerp(Color3.new(0, 0, 0), 0.3),
		color:Lerp(Color3.new(1, 1, 1), 0.7), color,
	})

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
		newPart({ Name = "DispenserBase", Size = vs(11, 2.4, 11), CFrame = at(0, 3.85, 1), Color = Color3.fromRGB(41, 45, 58), Material = Enum.Material.Metal, Parent = model })
		newPart({ Name = "DispenserRing", Shape = Enum.PartType.Cylinder, Size = vs(0.8, 13, 13), CFrame = at(0, 5.2, 1) * CFrame.Angles(0, 0, math.rad(90)), Color = color, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = model })
		local tube = newPart({ Name = "DispenserTube", Shape = Enum.PartType.Cylinder, Size = vs(13, 8.6, 8.6), CFrame = at(0, 11.8, 1) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(228, 236, 248), Material = Enum.Material.Glass, Transparency = 0.82, CanCollide = false, Parent = model })
		newPart({ Name = "DispenserCap", Size = vs(10.4, 1.8, 10.4), CFrame = at(0, 19.3, 1), Color = Color3.fromRGB(41, 45, 58), Material = Enum.Material.Metal, CanCollide = false, Parent = model })

		local brew = newPart({ Name = "Brew", Shape = Enum.PartType.Cylinder, Size = vs(10.5, 7.2, 7.2), CFrame = at(0, 11, 1) * CFrame.Angles(0, 0, math.rad(90)), Color = color, Material = Enum.Material.Neon, Transparency = 0.12, CanCollide = false, CastShadow = false, Parent = model })
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
			-- taller bottle per size, so the three sizes are readable off the counter itself
			local h = 3.2 + i * 1.3
			local tint = Color3.fromRGB(120, 240, 190):Lerp(Color3.fromRGB(255, 108, 168), (i - 1) / math.max(#GameConfig.PotionSizes - 1, 1))
			newPart({ Name = "MysteryBottle_" .. size.key, Shape = Enum.PartType.Cylinder, Size = vs(h, 2.6 + i * 0.3, 2.6 + i * 0.3), CFrame = at((i - 2) * 6.5, 9.9 + h / 2, 9.4) * CFrame.Angles(0, 0, math.rad(90)), Color = tint, Material = Enum.Material.Glass, Transparency = 0.2, CanCollide = false, Parent = model })
			newPart({ Name = "MysteryCork", Shape = Enum.PartType.Cylinder, Size = vs(1.3, 1.3, 1.3), CFrame = at((i - 2) * 6.5, 10.6 + h, 9.4) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(41, 45, 58), Material = Enum.Material.Metal, CanCollide = false, Parent = model })
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
		buildMysteryOddsBoard(model, base, S, color)

	elseif shopKey == "fusion" then
		-- two pods with a beam between them: the fusion is the only thing this counter does, and a
		-- machine that visibly joins two things is a clearer sign than any amount of text
		for _, sx in ipairs({ -1, 1 }) do
			newPart({ Name = "FusionPodBase", Shape = Enum.PartType.Cylinder, Size = vs(2, 9, 9), CFrame = at(sx * 9, 4, 2) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(58, 54, 72), Material = Enum.Material.Metal, Parent = model })
			local glass = newPart({ Name = "FusionPod", Shape = Enum.PartType.Ball, Size = vs(11, 11, 11), CFrame = at(sx * 9, 10.4, 2), Color = color, Material = Enum.Material.Glass, Transparency = 0.55, CanCollide = false, Parent = model })
			addLight(glass, color, math.min(22 * S, 60), 1.6)
			pulseForever(glass, 0.62, 2.4)
			VillageKit.addKnob(model, (at(sx * 9, 16.6, 2)).Position, 3.4 * S, Color3.fromRGB(244, 247, 252))
		end
		local beam = newPart({ Name = "FusionBeam", Shape = Enum.PartType.Cylinder, Size = vs(18, 2.2, 2.2), CFrame = at(0, 10.4, 2), Color = Color3.fromRGB(255, 246, 200), Material = Enum.Material.Neon, Transparency = 0.15, CanCollide = false, CastShadow = false, Parent = model })
		pulseForever(beam, 0.5, 1.3)
		addLight(beam, color, math.min(26 * S, 60), 2)

		-- "fusion", not "pets". The Fusion Lab used to open the PETS panel, which meant the only door
		-- to fusing was a button inside that panel -- so the lab you walked to did not actually do the
		-- thing written on its sign, and the HUD carried a shortcut it should never have needed.
		addPrompt(counter, "Open Pet Fusion", "\u{1F43E} Fuse duplicates", { ShopPanel = "fusion" })
		makeSign(model, ("\u{1F9EC} PET FUSION\nBring %d of the same pet\nand fuse them into the next tier"):format(GameConfig.FuseRequirement or 3),
			at(0, 18.2, 15), UDim2.new(23 * S, 0, 4.8 * S, 0), { maxDistance = 360 })

	else -- "upgrades"
		-- ONE SHOP, TWO COUNTERS, one per currency. A single prompt would have had to ask which
		-- currency the player meant, and the answer is a different panel either way -- so the choice
		-- is made by which end of the counter you walk up to.
		local pads = {
			{ dx = -9, icon = "\u{1F48E}", tint = Color3.fromRGB(120, 200, 255) },
			{ dx = 9,  icon = "\u{1F6CD}", tint = Color3.fromRGB(126, 226, 132) },
		}
		for i, counterDef in ipairs(GameConfig.ShopKinds.upgrades.counters) do
			local pad = pads[i] or pads[1]
			local plate = newPart({ Name = "UpgradePad", Size = vs(9, 1.2, 4.4), CFrame = at(pad.dx, 10.5, 9.4), Color = pad.tint, Material = Enum.Material.Neon, Transparency = 0.25, CanCollide = false, Parent = model })
			addLight(plate, pad.tint, math.min(18 * S, 60), 1.4)
			pulseForever(plate, 0.6, 2.6)
			-- the floating token over each pad: a gem for Diamonds, a crate for Robux
			if i == 1 then
				local gemFrame = at(pad.dx, 15.4, 9.4) * CFrame.Angles(math.rad(45), 0, math.rad(45))
				local gem = newPart({ Name = "UpgradeGem", Size = vs(5, 5, 5), CFrame = gemFrame, Color = pad.tint, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
				-- spinForever takes the part's own placed frame back, and re-applies ACTIVE_FRAME itself
				spinForever(gem, gemFrame, 360, 7)
			else
				newPart({ Name = "UpgradeCrate", Size = vs(6, 5, 5), CFrame = at(pad.dx, 15, 9.4), Color = pad.tint, Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
				newPart({ Name = "UpgradeCrateLid", Size = vs(6.8, 1.1, 5.8), CFrame = at(pad.dx, 17.8, 9.4), Color = Color3.fromRGB(244, 247, 252), Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
			end
			addPrompt(plate, counterDef.actionText, counterDef.objectText, { ShopPanel = counterDef.panel })
		end
		makeSign(model, "\u{1F48E} UPGRADE EMPORIUM\nStage Mastery for Diamonds\nBundles and boosts for Robux",
			at(0, 18.2, 15), UDim2.new(23 * S, 0, 4.8 * S, 0), { maxDistance = 360 })
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
		buildPortal(model, wallX, target)
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
		buildPortalInZWall(model, cx, cz, target)
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

-- ===== WHAT A ZONE IS DECORATED WITH LEFT THIS FILE (18.12) =====
--
-- `ServerScriptService.BiomeDecor` -- the four shared layers (`addGroundLitter`,
-- `addGroundClutter`, `addMounds`, `addLandmark`, `addAtmosphere`, `addGlowPosts`, plus the idols
-- and the ruins), the mesh prop layer and `buildBiomeBase` that arranges them, and all twenty
-- per-zone `decorationBuilders`. 2,443 lines and twenty-six top-level names, which took this file
-- from **159 of Luau's 200 registers to 134**.
--
-- ONE NAME COMES BACK, and that is the reason the cut is here and not in four places: every layer
-- verb has exactly one caller (`buildBiomeBase`), which has exactly one set of callers (the twenty
-- builders), which are read by exactly one line in `Build()` below.
--
-- WHAT DID NOT MOVE: the ground itself, the terraces, the walls and gates, the village, the eggs,
-- the egg plaza and the boss arena. This file still builds the zone; it no longer dresses it.
--
-- `ACTIVE_ZONE_KEY` WENT WITH IT AND IS SET THROUGH `BiomeDecor.setZoneKey`. It is reassigned per
-- zone, so it could not be re-localised in either direction -- `docs/SPLIT.md` §3 rule 2, the same
-- trap as `ZoneKit`'s placement frame. Both writers are in the zone loop at the bottom of this
-- file; all nine readers went with the builders.
local BiomeDecor = require(script.Parent.BiomeDecor)
local decorationBuilders = BiomeDecor.decorationBuilders

-- ============================================================================
-- TERRAIN: the valley walls -- IN `ZoneTerrain` SINCE 18.13
-- ============================================================================
-- The terraces, the cliffs, the waterfalls and the pools are all built by
-- `ServerScriptService.ZoneTerrain` now; see the require above `addWallDecor`. `buildTerrain` is
-- still called once per zone from the loop at the bottom of this file, in the same place, and
-- `addRockRampart` still asks it for the crest height. Its one new argument is the zone's floor
-- material: `GROUND_MATERIAL` is a per-zone decision and stays here, so the terrace treads are
-- handed the one value they wanted rather than the table moving house. What is below this line is
-- what STANDS on that ground.

-- ===== EGGS =====
-- Big, bright, speckled procedural eggs (built from parts, not the old re-tinted mesh whose
-- baked-in texture never actually showed the tier color) so every tier reads as a distinct,
-- colorful reward. Basic/Better get a matte speckled shell; Premium glows with a gem crown.
-- `band` is the stripe around the waist. It is the single strongest cue that this is a toy egg
-- and not a boulder, so every tier gets one, in a colour that fights its own shell rather than
-- blending into it -- Better's first speckle set was three pale blues on a violet shell and the
-- pattern simply vanished.
-- ONE SPOT COLOUR PER EGG, and that is the whole difference between this and what was here before.
-- `speckles` used to be a list of four colours and every patch picked from it at random, so each
-- shell came out covered in red, blue, yellow and green blotches of differing size -- which does
-- not read as a pattern, it reads as a rash. The reference eggs are one clean shell colour plus
-- one strong accent, five or six patches, all the same size.
local EGG_TIER_STYLE = {
	-- One saturated shell colour and ONE accent for its marks, in a clean rarity ladder:
	-- blue -> purple -> gold. The old set was near-white for Basic and near-cream for Better, so on
	-- a bright wooden deck two of the three eggs read as grey blobs and the spot colour was left
	-- carrying the whole tier on its own. Not tinted per zone, same argument as PODIUM_STONE below.
	Basic = {
		base = Color3.fromRGB(72, 178, 246),
		spot = Color3.fromRGB(255, 255, 255),
		shellMaterial = Enum.Material.SmoothPlastic,
	},
	Better = {
		base = Color3.fromRGB(168, 96, 255),
		spot = Color3.fromRGB(255, 222, 104),
		shellMaterial = Enum.Material.SmoothPlastic,
	},
	Premium = {
		-- THE TOP TIER IS AN EGG. It used to be a cluster of gold blades on a green rock, on the
		-- theory that a different silhouette is what separates it at a glance -- and it did, but it
		-- separated it right out of the set: three podiums under an EGGS sign with two eggs and a
		-- crystal on them reads as a bug, not as a rarity.
		-- What carries the tier instead, without touching the shape:
		--   `facet` turns the round marks into cut DIAMONDS, so the pattern reads as gemstone,
		--   `nest`  grows short amber shards round the foot, so it sits in crystal rather than
		--           being made of it.
		base = Color3.fromRGB(255, 206, 40),
		-- Light AMBER, not near-white. At (255,246,190) the facets read as white paper squares
		-- taped onto a gold egg: a cut face catches more light than the body it is cut into, it does
		-- not change material. Staying inside the gold family is what makes them read as cuts.
		spot = Color3.fromRGB(255, 234, 128),
		shellMaterial = Enum.Material.SmoothPlastic,
		facet = true,
		nest = true,
		crystalDark = Color3.fromRGB(238, 150, 20),
	},
}

-- ===== WHY THE SHELL IS A MESH AND NOT A BALL PART =====
-- A Part with Shape = Ball IGNORES a non-uniform Size: it renders a SPHERE of the SMALLEST axis.
-- Every egg here used to be a Ball sized (11.5, 14.8, 11.5) and was therefore drawn as an 11.5
-- sphere -- which is why the shells read as blobs, and why a cap sphere had to be stacked on top to
-- fake a point, and that cap is what read as a snowman head. The flattened "paint" spots had the
-- same problem: sized (5.4, 5.4, 2.2) they were drawn as 2.2 pellets, not as patches.
-- A Block carrying a SpecialMesh of MeshType Sphere DOES scale on all three axes, so the shell is a
-- true ellipsoid and the marks are true flat discs. Anything round in here goes through eggBall().
local EGG_A, EGG_B = 5.9, 9.0         -- body ellipsoid: half width, half height
local EGG_CAP_A, EGG_CAP_B = 4.2, 6.8 -- the taper that turns an ellipsoid into an egg
local EGG_CAP_Y = 4.4                 -- it is narrower than the body below +6.6 and wider above it,
                                      -- so it takes over the silhouette exactly where an egg points
-- 11.8 wide by 20.2 tall, i.e. 1 : 1.71. It was 1 : 1.44 and read as rounded rather than as an egg;
-- the width came DOWN as well as the height going up, because at a fixed width a taller shell just
-- reads as a bigger egg.
local EGG_BODY = Vector3.new(EGG_A * 2, EGG_B * 2, EGG_A * 2)
local EGG_CAP = Vector3.new(EGG_CAP_A * 2, EGG_CAP_B * 2, EGG_CAP_A * 2)
-- What the plaza measures the egg by: eggY = podiumTop + Y/2 stands the shell on the stone, and
-- addEggShowcase runs the same subtraction backwards to find the podium again.
local EGG_SHELL_SIZE = Vector3.new(EGG_A * 2, EGG_B * 2, EGG_A * 2)
local EGG_PIVOT_Y = 13

-- Shape stays Block: the sphere comes from the mesh, which is the only thing here that scales on
-- all three axes.
local function eggBall(props, parent)
	props.Parent = parent
	local p = newPart(props)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

-- Point and outward normal on the body ellipsoid: u walks -1..1 up the axis, a turns around it.
-- The NORMAL is what makes a mark lie flush. Pushing a disc in along the radius instead leaves it
-- tilted everywhere except the equator, and a tilted disc on a shell reads as a chip knocked out
-- of the paint rather than as a mark on it.
local function eggSurface(u, a)
	local r = math.sqrt(math.max(0, 1 - u * u))
	local p = Vector3.new(EGG_A * r * math.cos(a), EGG_B * u, EGG_A * r * math.sin(a))
	return p, Vector3.new(p.X / (EGG_A * EGG_A), p.Y / (EGG_B * EGG_B), p.Z / (EGG_A * EGG_A)).Unit
end

-- The Premium foot: short amber blades leaning out from around the base, each yawed by the golden
-- angle so no two line up and the ring reads as grown rather than as a collar. Short on purpose --
-- they stop below the widest point of the shell, so the egg's outline is never broken by them, and
-- the pale tip is the one thing that makes a plain tapered block read as a faceted crystal.
-- `piece` is buildEgg's helper: it records the PetOffset attribute the client animates against, so
-- every shard rises and turns with the egg.
local function buildCrystalNest(piece, center, style)
	local BLADES = 7
	local GOLD_ANGLE = math.pi * (3 - math.sqrt(5))
	for i = 1, BLADES do
		local f = (i - 1) / BLADES
		local h = 5.4 + math.sin(f * math.pi) * 2.6
		local w = 2.4 - f * 0.5
		local off = CFrame.Angles(0, i * GOLD_ANGLE, 0)
			* CFrame.new(0, -EGG_B + 2.2, 0)
			* CFrame.Angles(math.rad(26 + f * 12), 0, 0)
			* CFrame.new(0, h * 0.5, 0)
		piece({ Name = "EggShard", Size = Vector3.new(w, h, w), CFrame = CFrame.new(center) * off,
			Color = (i % 2 == 0) and style.base or style.crystalDark,
			Material = Enum.Material.SmoothPlastic }, off)
		local tip = off * CFrame.new(0, h * 0.40, 0)
		piece({ Name = "EggShardTip", Size = Vector3.new(w * 0.6, h * 0.26, w * 0.6),
			CFrame = CFrame.new(center) * tip, Color = style.spot,
			Material = Enum.Material.SmoothPlastic }, tip)
	end
end

-- Builds one egg as a Model and returns the shell, which is what the caller hangs the
-- ProximityPrompt on.
--
-- Every piece carries its offset from the shell as a PetOffset attribute and the model is tagged
-- EggIdle, so PetFollowClient can float, rock and spin it on each client without the server sending
-- a CFrame per frame. See the note at the top of PetFollowService.
--
-- NO Highlight and NO PointLight are created here, both on purpose. Roblox draws about 31
-- Highlights at once and a running game already carries 42 of them before a single egg, so an
-- outline baked in here would silently steal the outline off the player's own pets -- the one place
-- it actually matters. The outline is added CLIENT-SIDE to the nearest stall only; see the
-- egg-outline block at the end of PetFollowClient. The light is already there too: addEggShowcase
-- lights the disc the egg stands on.
-- A GENERATED EGG, when one exists for this tier.
--
-- Same idea as the bosses and the player skins: the shell below is a sphere-meshed block with
-- spots laid on a Fibonacci spiral, which is a good painted egg and still reads as a primitive
-- next to a generated boss. Three meshes -- Basic / Better / Premium -- live in
-- ReplicatedStorage.Assets.EggMeshes and stand in for the whole assembly when present.
--
-- Falls through to the built shell when a mesh is missing, so nothing breaks mid-rollout.
--
-- The PetOffset attribute is what the client's hatch animation reads to fly pieces apart; a
-- generated egg is one piece, so it carries a single zero offset and simply rises and spins.
-- ONE SET OF THREE EGGS FOR THE WHOLE GAME WAS THE PROBLEM. Every zone's stall showed the same
-- Basic, Better and Premium shells, so walking twenty platforms you passed the same three objects
-- twenty times -- and the stall is one of the few things a player stands still in front of.
--
-- `EggMesh_<ZoneKey>_<Tier>` wins when it is filed and `EggMesh_<Tier>` is the fallback, which is
-- the same graceful-degradation rule the landmarks, the boss rigs and the idols follow: a zone
-- with no set of its own keeps the shared three and nothing anywhere reports an error. That also
-- means the sixty zone eggs can be filed a few at a time without the world ever being half-built.
local function buildEggMesh(shop, ex, tierSuffix, pivotY, style, zoneKey)
	local assets = RS:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("EggMeshes")
	if not folder then return nil end
	local template = (zoneKey and folder:FindFirstChild("EggMesh_" .. zoneKey .. "_" .. tierSuffix))
		or folder:FindFirstChild("EggMesh_" .. tierSuffix)
	if not template then return nil end

	local model = Instance.new("Model")
	model.Name = "Egg"
	local clone = template:Clone()
	clone.Parent = model

	-- scaled to the shell it replaces, so the podium, the sign clearance and the showcase pet all
	-- keep measuring the same egg they were laid out against
	local _, tSize = clone:GetBoundingBox()
	if tSize.Y < 0.01 then
		model:Destroy()
		return nil
	end
	clone:ScaleTo(EGG_SHELL_SIZE.Y / tSize.Y)

	local center = Vector3.new(ex, pivotY or EGG_PIVOT_Y, 0)
	local cf = clone:GetBoundingBox()
	clone:TranslateBy(center - cf.Position)

	-- One invisible shell part carrying the name and the collision rules the rest of the system
	-- expects, with the mesh pieces parented beside it. CanCollide false for the reason written on
	-- the primitive shell below: the corners of the collision box stick out at head height right
	-- where a player walks past the podium.
	local shell = newPart({
		Name = "EggShell",
		Size = EGG_SHELL_SIZE,
		Position = center,
		Transparency = 1,
		CanCollide = false,
		Parent = model,
	})
	model.PrimaryPart = shell

	for _, p in ipairs(clone:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			-- offsets are relative to the SHELL, because the shell is the part the client moves
			-- and everything else hangs off it -- see the note on the primitive egg's `piece`
			p:SetAttribute("PetOffset", CFrame.new(p.Position - center))
			p.Parent = model
		end
	end
	clone:Destroy()

	-- THE SAME FOUR ATTRIBUTES AND THE SAME TAG THE BUILT EGG CARRIES.
	--
	-- PetFollowClient drives every egg in the game off `EggIdle` -- the bob, the rock, the spin and
	-- the proximity outline all key off it. A generated egg without this tag is a rock sitting on a
	-- podium: correct geometry, completely dead, and nothing anywhere would report an error.
	model:SetAttribute("IdleAnchor", shell.CFrame)
	model:SetAttribute("IdlePhase", (ex % 7) * 0.9)
	model:SetAttribute("SpinSpeed", 0.5 + (ex % 3) * 0.09)
	model:SetAttribute("BobHeight", 0.45)
	CollectionService:AddTag(model, "EggIdle")

	model.Parent = shop
	return shell
end

local function buildEgg(shop, ex, tierSuffix, pivotY, zoneKey)
	local style = EGG_TIER_STYLE[tierSuffix] or EGG_TIER_STYLE.Basic
	local center = Vector3.new(ex, pivotY or EGG_PIVOT_Y, 0)

	local meshShell = buildEggMesh(shop, ex, tierSuffix, pivotY, style, zoneKey)
	if meshShell then return meshShell end

	local model = Instance.new("Model")
	model.Name = "Egg"

	-- CanCollide = false, and that is a consequence of the mesh. A Ball part collides as a sphere,
	-- but this is a Block wearing a sphere mesh, so its collision is the BOX -- and the corners of
	-- that box stick two and a half studs out of the shell at head height, right where a player
	-- walks past the podium. The ProximityPrompt does not need collision to be reachable.
	local shell = eggBall({
		Name = "EggShell",
		Size = EGG_BODY,
		Position = center,
		Color = style.base,
		Material = style.shellMaterial,
		CanCollide = false,
	}, model)
	model.PrimaryPart = shell

	-- offsets are relative to the shell, because the shell is what the client moves and everything
	-- else hangs off it. `offset` may be a Vector3 or a full CFrame (marks and shards are both
	-- rotated, and the rotation has to survive into the attribute too).
	local function piece(props, offset, ball)
		props.CanCollide = false
		local p
		if ball then
			p = eggBall(props, model)
		else
			props.Parent = model
			p = newPart(props)
		end
		p:SetAttribute("PetOffset", typeof(offset) == "CFrame" and offset or CFrame.new(offset))
		return p
	end

	piece({
		Name = "EggCap",
		Size = EGG_CAP,
		Position = center + Vector3.new(0, EGG_CAP_Y, 0),
		Color = style.base,
		Material = style.shellMaterial,
	}, Vector3.new(0, EGG_CAP_Y, 0), true)

	-- ===== THE MARKS =====
	-- ONE colour, TWO sizes, laid on a FIBONACCI SPIRAL. Random directions clump -- that is what
	-- random does, and retrying does not fix it -- while the golden angle is the standard
	-- construction for points that are provably never close together. That matters here because the
	-- eggs SPIN (see PetFollowClient): a pattern biased to one face was survivable on a static egg
	-- and is obviously wrong on a turning one. Seven large marks keep three or four facing the
	-- street at any moment; the five small ones ride a second spiral offset from the first, and two
	-- deliberate sizes read as a pattern where one size reads as a golf ball.
	--
	-- `style.facet` swaps the round disc for a square block turned 45 degrees IN THE SURFACE PLANE
	-- (the mark's local Z is the surface normal, so the roll happens flat against the shell). That
	-- is the whole of what makes the Premium shell read as cut gemstone instead of as paint.
	local GOLDEN = math.pi * (3 - math.sqrt(5))
	local function mark(u, ang, d, thick)
		local p, n = eggSurface(u, ang)
		p = p - n * (thick * 0.34) -- sunk, so it reads as paint rather than as a berry
		local off = CFrame.new(p, p + n)
		if style.facet then
			off = off * CFrame.Angles(0, 0, math.rad(45))
			d = d * 0.70 -- a square across its diagonal covers more shell than a disc of the same width
		end
		piece({
			Name = "EggSpot",
			Size = Vector3.new(d, d, thick),
			CFrame = CFrame.new(center) * off,
			Color = style.spot,
			Material = Enum.Material.SmoothPlastic,
		}, off, not style.facet)
	end
	for i = 1, 7 do
		mark(0.68 - (i - 0.5) * (1.32 / 7), i * GOLDEN, 5.0, 2.2)
	end
	for i = 1, 5 do
		mark(0.48 - (i - 0.5) * (1.04 / 5), i * GOLDEN + GOLDEN * 0.5 + 1.2, 2.7, 1.5)
	end

	if style.nest then
		buildCrystalNest(piece, center, style)
	end

	-- The cartoon shine: one long streak high on the shoulder, one small dot below it. Both are flush
	-- discs on the same surface the marks use -- a ball sunk into the shell bulges, and a bulge on a
	-- highlight reads as a bubble stuck to the paint instead of as light on it.
	local function gloss(u, ang, w, h, tr)
		local p, n = eggSurface(u, ang)
		p = p - n * 0.4
		local off = CFrame.new(p, p + n)
		piece({
			Name = "EggGloss",
			Size = Vector3.new(w, h, 1.6),
			CFrame = CFrame.new(center) * off,
			Color = Color3.fromRGB(255, 255, 255),
			Material = Enum.Material.SmoothPlastic,
			Transparency = tr,
		}, off, true)
	end
	gloss(0.42, 2.45, 3.0, 5.6, 0.22)
	gloss(0.05, 2.05, 1.7, 2.4, 0.30)

	-- Twinkle. ONE camera-facing emitter, not a ring of little neon blocks: a block only reads as a
	-- sparkle from the angle it was rotated for, and from every other angle it is a scrap of paper
	-- floating beside the egg. Parented to the shell so it rides the bob.
	local twinkle = Instance.new("ParticleEmitter")
	twinkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	twinkle.Rate = style.nest and 9 or 5
	twinkle.Lifetime = NumberRange.new(0.7, 1.3)
	twinkle.Speed = NumberRange.new(0.5, 1.6)
	twinkle.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.35, 3.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	twinkle.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	twinkle.Color = ColorSequence.new(Color3.fromRGB(255, 252, 214))
	twinkle.LightEmission = 1
	twinkle.LightInfluence = 0
	twinkle.Rotation = NumberRange.new(0, 360)
	twinkle.RotSpeed = NumberRange.new(-60, 60)
	twinkle.SpreadAngle = Vector2.new(180, 180)
	twinkle.Parent = shell

	-- the egg floats, and without a shadow it reads as pasted onto the sky rather than resting over
	-- its podium. Parented to the shop, not to the model, so it stays put while the egg rocks.
	-- ON TOP OF THE PODIUM CAP, NOT INSIDE IT. This disc spanned y 4.42-4.62 while PodiumTop spans
	-- 3.15-4.65 -- so the shadow ended a third of a stud BELOW the surface it was supposed to be
	-- cast on, and either vanished or flickered against the cap. Sixty of them, one per podium in
	-- the game, on the prop the player stands closest to.
	--
	-- `pivotY - EGG_SHELL_SIZE.Y/2` IS the podium's rest height (that is how the caller computes
	-- eggY), so the clearance is expressed against it rather than against PLAZA_PODIUM_TOP -- that
	-- constant is declared three hundred lines below this function and would be nil here.
	-- 0.37 clears the cap, whose top face is a quarter of a stud above the rest height.
	newPart({
		Name = "EggShadow",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 11, 11),
		Orientation = Vector3.new(0, 0, 90),
		Position = Vector3.new(ex, (pivotY or EGG_PIVOT_Y) - EGG_SHELL_SIZE.Y / 2 + 0.37, 0),
		Color = Color3.fromRGB(12, 10, 20),
		Transparency = 0.62,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CastShadow = false,
		Parent = shop,
	})

	model:SetAttribute("IdleAnchor", shell.CFrame)
	model:SetAttribute("IdlePhase", (ex % 7) * 0.9)
	-- three eggs turning at the same rate look mechanical; a few percent apart they never line up
	model:SetAttribute("SpinSpeed", 0.5 + (ex % 3) * 0.09)
	model:SetAttribute("BobHeight", 0.45)
	CollectionService:AddTag(model, "EggIdle")

	model.Parent = shop
	return shell
end

-- ===== WHAT IS INSIDE AN EGG =====
-- Every zone hatches its own five species, so the only thing that tells two eggs apart is that
-- list -- which means it belongs on the egg itself, not buried in a menu. The percentages come
-- from GameConfig.GetEggOdds, the same weights the roll uses, so the board can never advertise
-- odds the roll does not honour. Luck is passed as 0: this is the shop's baseline, and a player's
-- own luck only ever moves it in their favour.
local function buildEggOddsBoard(shop, egg, ex, y)
	local anchor = newPart({
		Name = "EggOddsAnchor",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(ex, y, 0),
		Transparency = 1,
		CanCollide = false,
		Parent = shop,
	})

	local odds = GameConfig.GetEggOdds(egg, 0)

	local gui = Instance.new("BillboardGui")
	gui.Name = "EggOdds"
	-- Sized in STUDS, not pixels: a pixel-sized billboard keeps its screen size at any range, so
	-- from the far end of the plaza the three boards grew into each other and covered the eggs.
	-- In studs each strip stays over its own podium, and MaxDistance does the rest -- you get the
	-- odds when you walk up to the egg and the stall reads clean from the street.
	-- WIDE AND SHORT, one cell per species. The old board was a portrait card with a title line and
	-- five full-width rows of "name .... 12%", i.e. a menu -- three of them side by side across the
	-- stall was more text than the whole rest of the zone put together, and none of it was legible
	-- until you were standing under it anyway. The only thing a shopper actually compares between
	-- two eggs is WHICH FIVE and HOW LIKELY, and both fit on one line each.
	gui.Size = UDim2.new(3.7 * #odds, 0, 5.3, 0)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = 52
	gui.Parent = anchor

	-- The pill is WHITE. Every earlier board in this place was dark navy on the theory that it
	-- matches the HUD, and it does -- but it is hung in the open air over a bright wooden stall,
	-- where a dark slab reads as a hole punched in the scene. White with a heavy outline is the
	-- shape a price tag has.
	local pill = Instance.new("Frame")
	pill.Size = UDim2.new(1, 0, 1, 0)
	pill.BackgroundColor3 = Color3.fromRGB(250, 252, 255)
	pill.BorderSizePixel = 0
	pill.Parent = gui
	local pillCorner = Instance.new("UICorner")
	pillCorner.CornerRadius = UDim.new(0.42, 0)
	pillCorner.Parent = pill
	local pillStroke = Instance.new("UIStroke")
	pillStroke.Thickness = 4
	pillStroke.Color = Color3.fromRGB(28, 38, 58)
	pillStroke.Parent = pill

	local strip = Instance.new("Frame")
	strip.Size = UDim2.new(1, 0, 1, 0)
	strip.BackgroundTransparency = 1
	strip.Parent = pill
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = strip

	for i, entry in ipairs(odds) do
		local rarity = GameConfig.GetRarity(entry.def.rarity)

		local cell = Instance.new("Frame")
		cell.Size = UDim2.new(1 / #odds, 0, 0.82, 0)
		cell.BackgroundTransparency = 1
		cell.LayoutOrder = i
		cell.Parent = strip

		-- the species, on its own rounded tile. A pale tile behind the emoji is what stops five
		-- glyphs in a row reading as one word.
		local tile = Instance.new("Frame")
		tile.Size = UDim2.new(0.40, 0, 0.88, 0)
		tile.Position = UDim2.new(0.03, 0, 0.06, 0)
		tile.BackgroundColor3 = Color3.fromRGB(206, 232, 252)
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
		icon.Size = UDim2.new(0.86, 0, 0.86, 0)
		icon.Position = UDim2.new(0.07, 0, 0.07, 0)
		icon.BackgroundTransparency = 1
		icon.Font = Enum.Font.FredokaOne
		icon.TextScaled = true
		icon.Text = entry.def.emoji
		icon.Parent = tile

		-- The percentage is in the RARITY colour, not in one house colour. It is the only number on
		-- the stall and its job is to say "this one basically never happens" before it is read.
		local chance = Instance.new("TextLabel")
		chance.Size = UDim2.new(0.50, 0, 0.66, 0)
		chance.Position = UDim2.new(0.46, 0, 0.17, 0)
		chance.BackgroundTransparency = 1
		chance.Font = Enum.Font.FredokaOne
		chance.TextScaled = true
		chance.TextXAlignment = Enum.TextXAlignment.Center
		chance.TextColor3 = rarity.color
		-- White stroke, not the usual dark one: these sit on a white pill, and a dark outline on a
		-- yellow Legendary number turns it into a smudge at the size a 3-stud cell allows.
		chance.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
		chance.TextStrokeTransparency = 0
		-- Below 1% the integer form rounds a real 0.5 chance to "0%", which advertises something
		-- that cannot be won. Two decimals only where it takes two. `textShort` overrides both for
		-- the 12.12 Secret cell, whose real figure (0.002%) no percentage form can print here.
		chance.Text = entry.textShort or (entry.chance < 1 and string.format("%.1f%%", entry.chance)
			or string.format(entry.chance < 10 and "%.1f%%" or "%.0f%%", entry.chance))
		chance.Parent = cell
	end

	return anchor
end

-- The rarest species of the five, floating over the podium: the pet people are actually buying
-- the egg for. Tagged rather than animated here -- a server that CFrames it every frame would
-- replicate the spin to every client at a throttled rate and stutter; PetFollowClient spins it
-- locally instead. See the note at the top of PetFollowService.
local function buildEggFeaturePet(shop, egg, ex, y)
	local pool = GameConfig.GetEggPool(egg)
	if not pool or #pool == 0 then return nil end

	local def = pool[#pool]
	local model, root, pieces = PetModel.Build(def, "Normal", { scale = 1.5, plateDistance = 110, outline = false })
	model.Name = "FeaturePet"
	PetModel.Place(root, pieces, CFrame.new(ex, y, 0))
	model:SetAttribute("SpinAnchor", CFrame.new(ex, y, 0))
	model:SetAttribute("SpinSpeed", 0.7)
	model:SetAttribute("BobHeight", 0.45)
	CollectionService:AddTag(model, "PetDisplay")
	model.Parent = shop
	return model
end

-- Orbit a part around an arbitrary pivot with no per-frame Lua, by the same trick spinForever
-- uses: the repeating tween covers exactly one step of the arrangement's rotational symmetry, so
-- the jump back to the start value at the end of each cycle lands on an identical pose.
local function orbitForever(part, pivot, radius, startDeg, stepDeg, seconds)
	local function poseAt(deg)
		return pivot * CFrame.Angles(0, math.rad(deg), 0) * CFrame.new(radius, 0, 0)
	end
	part.CFrame = poseAt(startDeg)
	TweenService:Create(part, TweenInfo.new(seconds, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
		CFrame = poseAt(startDeg + stepDeg),
	}):Play()
end

-- Everything around the shell that is NOT part of the shell: the light column it stands in, a
-- turning starburst behind it, orbiting gems and sparkle. It is parented to the shop rather than
-- to the egg model, so the egg can bob and rock on the client without dragging its own halo
-- around, and none of it needs a PetOffset attribute.
local function addEggShowcase(shop, ex, eggY, accent, style)
	local ring = style.band or accent
	local core = style.spot or style.gemColor or lighten(ring, 0.35)

	-- No light column here any more. A neon cylinder wrapped round the shell blew out to solid
	-- white the moment bloom touched it, and in a bright zone the egg -- the one thing the player
	-- came to look at -- was the least visible object on the podium.
	-- podium top derived from the egg height rather than read from PLAZA_PODIUM_TOP: that constant
	-- is declared below this function, so naming it here would resolve to a nil global
	local podiumTop = eggY - EGG_SHELL_SIZE.Y / 2
	-- NARROWER than the podium top (12) and nearly clear. At 17 studs and 0.6 it overhung the stone
	-- and painted the whole pedestal in the zone accent -- on Mars that is orange, so every stand
	-- read as a raw slab under a blue egg. It is a glow on the stone, not a plate on top of it.
	local disc = newPart({ Name = "EggDisc", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 11.5, 11.5), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(ex, podiumTop + 0.5, 0), Color = ring, Material = Enum.Material.Neon, Transparency = 0.82, CanCollide = false, CastShadow = false, Parent = shop })
	addLight(disc, ring, 17, 0.9)

	-- THE STARBURST IS GONE. Four crossed neon blades behind the shell is the "shiny thing on a
	-- pedestal" cue, and it works against a dark backdrop -- which is what the old plaza was. The
	-- stall that replaced it puts a bright wooden BOARD 11 studs behind the eggs, and four dark
	-- spokes drawn across grain read as cracks in the plank, not as light behind the egg.

	-- Three gems on one orbit -- a 120 degree step is one full symmetry of the set. Pale, and small:
	-- at 3.6 studs in the zone accent they read as red stickers parked beside the shell rather than
	-- as sparkle, and three of them at egg height competed with the spots for the same glance.
	local pivot = CFrame.new(ex, eggY + 3, 0)
	for i = 0, 2 do
		local gem = newPart({ Name = "EggOrbGem", Shape = Enum.PartType.Ball, Size = Vector3.new(1.7, 1.7, 1.7), Color = i == 1 and Color3.fromRGB(255, 255, 255) or core, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = shop })
		orbitForever(gem, pivot, 12.5, i * 120, 120, 6)
		pulseForever(gem, 0.5, 1.4 + i * 0.3)
	end

	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Color = ColorSequence.new(Color3.new(1, 1, 1), core)
	sparkle.Size = NumberSequence.new(1.5, 0)
	sparkle.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	sparkle.Lifetime = NumberRange.new(1.2, 2.2)
	sparkle.Rate = 9
	sparkle.Speed = NumberRange.new(1, 4)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.LightEmission = 1
	sparkle.Acceleration = Vector3.new(0, 3, 0)
	sparkle.Parent = disc
end

-- THE PRICE PLATE, and it is a PLATE ON THE PEDESTAL, not a card floating in front of it.
-- The reference art puts one small rounded tile on the face of each stand carrying nothing but an
-- icon and a number -- no tier name, no second row, no header bar. That is the whole design, and
-- it is why the eggs above it are what the eye lands on: the previous card was 14 studs wide and 7
-- tall with a colour-filled header, i.e. a poster, and three of them across the front of the stall
-- competed with the shells they were advertising.
--
-- Dropping the tier name here loses nothing -- it is the title of the odds board directly above
-- each egg, which is where somebody asking "what IS this one" is already looking.
local PRICE_PLATE_FACE = Color3.fromRGB(226, 232, 240)
local PRICE_PLATE_INK = Color3.fromRGB(28, 38, 58)

local function makePriceCard(shop, ex, y, egg, tierColor)
	-- Sized in studs, not pixels. A pixel-sized billboard keeps its screen size at range, so three
	-- of them 32 studs apart grew into each other -- and into the eggs -- from the plaza steps.
	local anchor = newPart({ Name = "PriceCardAnchor", Size = Vector3.new(1, 1, 1), Position = Vector3.new(ex, y, 7.4), Transparency = 1, CanCollide = false, CastShadow = false, Parent = shop })

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(11, 0, 4, 0) -- BillboardGui scale is studs; offset would be pixels
	bb.StudsOffset = Vector3.new(0, 0.6, 0)
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0 -- half the zones are lit near-black; a price must never go unreadable
	bb.MaxDistance = 95
	bb.Parent = anchor

	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 1, 0)
	card.BackgroundColor3 = PRICE_PLATE_FACE
	card.BorderSizePixel = 0
	card.Parent = bb
	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0.34, 0) -- in SCALE, so the pill survives any board size
	cardCorner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = PRICE_PLATE_INK
	stroke.Parent = card

	-- A hairline of the tier's own colour down the left edge. The reference plate is plain grey,
	-- but three identical grey pills say nothing about which egg is the expensive one; this is the
	-- smallest cue that keeps them apart without turning the plate back into a poster.
	local tab = Instance.new("Frame")
	tab.Size = UDim2.new(0.05, 0, 0.56, 0)
	tab.Position = UDim2.new(0.05, 0, 0.5, 0)
	tab.AnchorPoint = Vector2.new(0, 0.5)
	tab.BackgroundColor3 = tierColor
	tab.BorderSizePixel = 0
	tab.Parent = card
	local tabCorner = Instance.new("UICorner")
	tabCorner.CornerRadius = UDim.new(1, 0)
	tabCorner.Parent = tab

	local cost = Instance.new("TextLabel")
	cost.Size = UDim2.new(0.8, 0, 0.62, 0)
	cost.Position = UDim2.new(0.56, 0, 0.5, 0)
	cost.AnchorPoint = Vector2.new(0.5, 0.5)
	cost.BackgroundTransparency = 1
	cost.Font = Enum.Font.FredokaOne
	cost.TextScaled = true
	cost.TextColor3 = PRICE_PLATE_INK
	cost.Text = "🧬 " .. egg.cost
	cost.Parent = card

	return anchor
end

-- ===== EGG PLAZA =====
-- The shop is the first thing a player walks into in every zone, so it gets a built stage instead
-- of the old flat 54x26 slab: a two-step lit dais, a back wall carrying the EGGS banner and one
-- nameplate per tier, four pylons holding a canopy beam, and a spotlit podium under every egg.
-- Everything is laid out from the egg row on z = 0 outward, and stays inside the reserved centre
-- square (CLEAR_HALF), so no biome decoration can land on top of it.

-- A WOODEN MARKET STALL, NOT A CIVIC PLAZA. This had grown into a 138-stud stage: a two-step dais
-- with walk-up stairs, a 42-stud back wall, four 45-stud pylons carrying a canopy beam, four lamps
-- and a pair of bollards. That is a monument, and it read as one -- the three eggs the whole thing
-- exists to sell were the smallest objects in it.
--
-- The reference is a stall you walk up to: planks on the ground, a leaning board behind them, a
-- painted EGGS sign, and the eggs big and forward on little pedestals. The eggs are the tallest
-- thing on the stall now, which is the entire point of the stall.
local PLAZA_Z = -4            -- deck centre; the egg row sits 4 studs forward of it
local PLAZA_DECK_TOP = 1.2    -- the planks lie ON the ground now: no dais, no stairs
local PLAZA_PODIUM_TOP = 4.4  -- what each egg actually rests on
local EGG_SPACING = 32 -- was 21; the shells are 40% bigger and their haloes were overlapping

-- Warm timber, deliberately NOT tinted per zone: a wooden stall says "shop" in every biome, where
-- a Volcano-red or a Void-black one says nothing at all.
local STALL_WOOD = Color3.fromRGB(178, 126, 76)
local STALL_WOOD_DARK = Color3.fromRGB(139, 94, 54)
local STALL_PLANK = Color3.fromRGB(198, 148, 96)

-- The pedestals are a FIXED SLATE BLUE, not the zone accent. They used to be tinted from
-- zone.accentColor like everything else on the stall, which meant a Volcano stand was orange under
-- an orange egg and a Desert one was sand under a cream egg -- the stand and the thing it displays
-- disappeared into each other exactly where the player is meant to be comparing three of them.
-- The reference uses one cool dark stone under every egg for that reason: it is the neutral the
-- shells read against, in all twenty biomes. Same argument as STALL_WOOD above.
local PODIUM_STONE = Color3.fromRGB(64, 82, 104)
local PODIUM_STONE_DARK = Color3.fromRGB(42, 56, 74)
local PODIUM_STONE_LIT = Color3.fromRGB(124, 146, 170)

-- ---- WHAT MAKES IT A MARKET STALL AND NOT A DISPLAY CASE.
-- The deck is 120 studs wide and holds three podiums 32 apart, which leaves about 14 studs of bare
-- plank at each end and a bare strip along the front. Bare deck reads as an unfinished set, so both
-- get dressed: a crate stack and a barrel at the ends, a basket of loose eggs where a shopper
-- stands, and a lantern hung off each post.
--
-- Fixed timber and stone colours, no zone tinting, for the same reason STALL_WOOD has one -- and
-- the mini eggs in the basket take the three TIER colours, which is the one place the stall says
-- what it sells without a word on it.
--
-- Everything here is CanCollide = false on purpose. It sits on the walkway a player crosses to
-- reach a ProximityPrompt, and a crate you can get wedged behind is worse than no crate at all.
local function addStallDressing(shop, cx, halfW, backZ, accent)
	local CRATE = Color3.fromRGB(170, 122, 70)
	local CRATE_DARK = Color3.fromRGB(126, 86, 48)
	local IRON = Color3.fromRGB(74, 66, 62)
	local MINI = {
		EGG_TIER_STYLE.Basic.base,
		EGG_TIER_STYLE.Better.base,
		EGG_TIER_STYLE.Premium.base,
	}

	for _, side in ipairs({ -1, 1 }) do
		local ex = cx + side * (halfW - 11)

		-- Crate stack: two boxes, the upper one turned off-axis and set back. Two boxes squared up
		-- read as one tall box; a few degrees of yaw is the whole difference between cargo and
		-- furniture.
		local crateCF = CFrame.new(ex, PLAZA_DECK_TOP + 4.5, -12) * CFrame.Angles(0, math.rad(side * 9), 0)
		newPart({ Name = "StallCrate", Size = Vector3.new(9, 9, 9), CFrame = crateCF,
			Color = CRATE, Material = Enum.Material.WoodPlanks, CanCollide = false, CastShadow = false, Parent = shop })
		newPart({ Name = "StallCrateBand", Size = Vector3.new(9.4, 1.5, 9.4), CFrame = crateCF,
			Color = CRATE_DARK, Material = Enum.Material.Wood, CanCollide = false, CastShadow = false, Parent = shop })
		newPart({ Name = "StallCrate", Size = Vector3.new(6.6, 6.6, 6.6),
			CFrame = CFrame.new(ex - side * 1.4, PLAZA_DECK_TOP + 12.3, -13.2) * CFrame.Angles(0, math.rad(-side * 22), 0),
			Color = CRATE_DARK, Material = Enum.Material.WoodPlanks, CanCollide = false, CastShadow = false, Parent = shop })

		-- Barrel standing on its end. A Cylinder is extruded along X, so the roll of 90 degrees is
		-- what stands it up; its Y and Z are the cross-section.
		local barrelX = cx + side * (halfW - 5.5)
		newPart({ Name = "StallBarrel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(8.6, 7.4, 7.4),
			CFrame = CFrame.new(barrelX, PLAZA_DECK_TOP + 4.3, 2) * CFrame.Angles(0, 0, math.rad(90)),
			Color = CRATE, Material = Enum.Material.WoodPlanks, CanCollide = false, CastShadow = false, Parent = shop })
		for _, dy in ipairs({ -2.2, 2.2 }) do
			newPart({ Name = "StallBarrelHoop", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.1, 7.8, 7.8),
				CFrame = CFrame.new(barrelX, PLAZA_DECK_TOP + 4.3 + dy, 2) * CFrame.Angles(0, 0, math.rad(90)),
				Color = IRON, Material = Enum.Material.Metal, CanCollide = false, CastShadow = false, Parent = shop })
		end

		-- A basket of loose eggs, at the front where a shopper stands. Mini shells go through
		-- eggBall for the same reason the big ones do: a Ball part would draw each one as a sphere
		-- of its smallest axis, i.e. as a pea.
		local bx = cx + side * (halfW - 18)
		newPart({ Name = "StallBasket", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.6, 12, 12),
			CFrame = CFrame.new(bx, PLAZA_DECK_TOP + 1.8, 9) * CFrame.Angles(0, 0, math.rad(90)),
			Color = CRATE_DARK, Material = Enum.Material.WoodPlanks, CanCollide = false, CastShadow = false, Parent = shop })
		newPart({ Name = "StallBasketRim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, 12.8, 12.8),
			CFrame = CFrame.new(bx, PLAZA_DECK_TOP + 3.4, 9) * CFrame.Angles(0, 0, math.rad(90)),
			Color = CRATE, Material = Enum.Material.Wood, CanCollide = false, CastShadow = false, Parent = shop })
		for i = 1, 3 do
			local ang = i * (math.pi * 2 / 3) + side
			eggBall({
				Name = "StallBasketEgg",
				Size = Vector3.new(4.2, 5.4, 4.2),
				CFrame = CFrame.new(bx + math.cos(ang) * 2.9, PLAZA_DECK_TOP + 5.1, 9 + math.sin(ang) * 2.9)
					* CFrame.Angles(math.rad(16), ang, math.rad(11)),
				Color = MINI[i],
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
				CastShadow = false,
			}, shop)
		end

		-- Lantern hung off the inside face of each post, level with the sign.
		local px = cx + side * (halfW - 1.4) - side * 2.6
		newPart({ Name = "StallLanternRope", Size = Vector3.new(0.5, 3.2, 0.5),
			Position = Vector3.new(px, 24.4, backZ + 1), Color = IRON, Material = Enum.Material.Metal,
			CanCollide = false, CastShadow = false, Parent = shop })
		local lamp = newPart({ Name = "StallLantern", Size = Vector3.new(3.4, 4.4, 3.4),
			Position = Vector3.new(px, 20.6, backZ + 1), Color = Color3.fromRGB(255, 226, 150),
			Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = shop })
		for _, dy in ipairs({ -2.5, 2.5 }) do
			newPart({ Name = "StallLanternCap", Size = Vector3.new(4.2, 1.0, 4.2),
				Position = Vector3.new(px, 20.6 + dy, backZ + 1), Color = IRON, Material = Enum.Material.Metal,
				CanCollide = false, CastShadow = false, Parent = shop })
		end
		addLight(lamp, Color3.fromRGB(255, 220, 150), 24, 1.1)
	end
end

local function buildEggPlaza(shop, zone, cx, eggs)
	local accent = zone.accentColor
	-- Was rgb(38,38,46). Under its own canopy that read as a black hole in the middle of a bright
	-- zone: every darken() below starts from this, so the deck, the wall and the pylons all went
	-- near-black together. A mid slate keeps the neon trim and the eggs popping without the shop
	-- swallowing the light.
	-- Was rgb(92,88,112). Once the world was lit properly that mid-slate was the darkest thing in
	-- any zone -- the shop read as a black box parked in a bright biome. A warm near-white tinted
	-- toward the zone accent keeps it bright and still tells the zones apart.
	local stone = Color3.fromRGB(226, 219, 205):Lerp(accent, 0.24)
	local deckW = EGG_SPACING * (#eggs - 1) + 56
	local halfW = deckW / 2
	local backZ = PLAZA_Z - 20
	local frontZ = PLAZA_Z + 20

	-- ---- the deck: planks laid ON the ground. No dais and no stairs -- the reference stall is
	-- something you walk onto without noticing, and four rises of stair in front of a shop is three
	-- more decisions than buying an egg deserves.
	newPart({ Name = "StallDeck", Size = Vector3.new(deckW, 1.2, 40), Position = Vector3.new(cx, 0.6, PLAZA_Z), Color = STALL_WOOD_DARK, Material = Enum.Material.Wood, Parent = shop })
	-- individual boards, so it reads as carpentry instead of one brown rectangle
	local boards = math.max(6, math.floor(deckW / 9))
	local boardW = deckW / boards
	for i = 0, boards - 1 do
		newPart({ Name = "StallPlank", Size = Vector3.new(boardW - 0.8, 0.5, 39),
			Position = Vector3.new(cx - deckW / 2 + boardW * (i + 0.5), PLAZA_DECK_TOP, PLAZA_Z),
			Color = i % 2 == 0 and STALL_PLANK or STALL_WOOD, Material = Enum.Material.Wood, CanCollide = false, Parent = shop })
	end
	-- the glowing lip around the edge -- the one piece of neon the stall keeps, because it is what
	-- says "this patch of ground is a shop" from fifty studs out
	for _, dz in ipairs({ -20, 20 }) do
		newPart({ Name = "StallTrim", Size = Vector3.new(deckW + 2, 0.7, 1.8), Position = Vector3.new(cx, PLAZA_DECK_TOP, PLAZA_Z + dz), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = shop })
	end
	for _, side in ipairs({ -1, 1 }) do
		newPart({ Name = "StallTrim", Size = Vector3.new(1.8, 0.7, 40), Position = Vector3.new(cx + side * halfW, PLAZA_DECK_TOP, PLAZA_Z), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = shop })
	end

	-- ---- the counter the eggs stand behind, and the leaning display board above it. The board is
	-- TILTED BACK ~12 degrees like a market stall's panel; upright it is a wall, and a wall is
	-- exactly what this used to be.
	newPart({ Name = "StallCounter", Size = Vector3.new(deckW, 2.4, 9), Position = Vector3.new(cx, 2, backZ + 4.5), Color = STALL_WOOD_DARK, Material = Enum.Material.Wood, Parent = shop })
	local boardCF = CFrame.new(cx, 13, backZ) * CFrame.Angles(math.rad(-12), 0, 0)
	newPart({ Name = "StallBoard", Size = Vector3.new(deckW, 22, 1.6), CFrame = boardCF, Color = STALL_WOOD, Material = Enum.Material.Wood, Parent = shop })
	newPart({ Name = "StallBoardCap", Size = Vector3.new(deckW + 3, 2, 2.8), CFrame = boardCF * CFrame.new(0, 11.6, 0), Color = STALL_WOOD_DARK, Material = Enum.Material.Wood, CanCollide = false, Parent = shop })
	for _, side in ipairs({ -1, 1 }) do
		newPart({ Name = "StallPost", Size = Vector3.new(2.8, 27, 2.8), Position = Vector3.new(cx + side * (halfW - 1.4), 13.5, backZ + 1), Color = STALL_WOOD_DARK, Material = Enum.Material.Wood, Parent = shop })
		newPart({ Name = "StallPostCap", Shape = Enum.PartType.Ball, Size = Vector3.new(4.2, 4.2, 4.2), Position = Vector3.new(cx + side * (halfW - 1.4), 27.4, backZ + 1), Color = STALL_WOOD, Material = Enum.Material.Wood, CanCollide = false, Parent = shop })
	end

	addStallDressing(shop, cx, halfW, backZ, accent)

	-- ---- THE EGGS PANEL: A REAL PART, NOT A BILLBOARD.
	-- It was a makeSign BillboardGui, and a billboard always turns to face the camera and always
	-- draws in front of whatever is behind it in screen space -- so from the front of the stall the
	-- sign sat squarely across the middle egg, which is the one object it exists to advertise. As
	-- two slabs bolted to the board it occludes correctly: walk round and the eggs pass in front of
	-- it, exactly as the reference shows.
	--
	-- WHITE FACE, DARK BORDER, in every biome. makeSign defaults to the zone's colour, which put a
	-- dark purple plate on a dark purple board in half the strip. This is the one piece of the stall
	-- that has to be readable from the arrival gate, so it takes the highest contrast available and
	-- no zone tinting at all -- same argument as the timber and the pedestals.
	-- 10.2, not 7.6: the shells top out around 19-20 studs and the panel's lower half was sitting
	-- right behind the middle egg's crown, so from dead-on the word was half eaten. This lands the
	-- panel at ~23 and its text clear of everything on the counter.
	local signCF = boardCF * CFrame.new(0, 10.2, 1.6)
	-- Proportion matters here and it is not free to pick: a SurfaceGui TextLabel with TextScaled
	-- fits by whichever axis binds first, and on a 5:1 panel that is always the HEIGHT -- so the
	-- word came out as a small line floating in a wide white bar. About 3:1 is where the text
	-- actually fills the panel, which is the proportion the reference sign uses.
	newPart({ Name = "StallSignFrame", Size = Vector3.new(40, 14, 1.2), CFrame = signCF,
		Color = Color3.fromRGB(28, 38, 58), Material = Enum.Material.SmoothPlastic,
		CanCollide = false, Parent = shop })
	local signFace = newPart({ Name = "StallSignFace", Size = Vector3.new(35.5, 10, 1.2),
		CFrame = signCF * CFrame.new(0, 0, 0.5), Color = Color3.fromRGB(248, 250, 252),
		Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = shop })

	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "StallSignText"
		gui.Face = face
		gui.LightInfluence = 0 -- half the late zones are lit almost to black
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 36
		gui.MaxDistance = 260
		gui.Parent = signFace

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.new(0.5, 0, 0.5, 0)
		label.Size = UDim2.new(0.88, 0, 0.72, 0)
		label.Font = SIGN_FONT
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(28, 38, 58)
		label.Text = "\u{1F95A} EGGS"
		label.Parent = gui
	end

	-- ---- one podium per egg, each lit from above so the shell reads against the dark deck
	local startX = cx - EGG_SPACING * (#eggs - 1) / 2
	local built = {}
	for i, egg in ipairs(eggs) do
		local ex = startX + EGG_SPACING * (i - 1)

		-- THE PEDESTAL, built to the reference: a wide dark plinth, a narrow waisted column, and a
		-- pale cap wider than the column it stands on. The waist is the part that matters -- three
		-- discs each narrower than the last is a wedding cake, and a wedding cake reads as scenery.
		-- A column that pinches in and flares back out reads as a STAND, i.e. as something whose only
		-- job is to hold the thing above it, which is exactly what it is.
		-- Everything stays narrower than the egg, so the shell overhangs its stand and keeps the
		-- silhouette -- the old 19-stud podium was wider than the egg and stole it.
		newPart({ Name = "PodiumBase", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 15, 15), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(ex, PLAZA_DECK_TOP + 0.8, 0), Color = PODIUM_STONE_DARK, Material = Enum.Material.Slate, Parent = shop })
		newPart({ Name = "PodiumStep", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.1, 12.6, 12.6), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(ex, PLAZA_DECK_TOP + 2.1, 0), Color = PODIUM_STONE, Material = Enum.Material.Slate, Parent = shop })
		newPart({ Name = "PodiumWaist", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, 9.4, 9.4), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(ex, PLAZA_DECK_TOP + 3.2, 0), Color = PODIUM_STONE, Material = Enum.Material.Slate, Parent = shop })
		newPart({ Name = "PodiumTop", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.5, 12, 12), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(ex, PLAZA_PODIUM_TOP - 0.5, 0), Color = PODIUM_STONE_LIT, Material = Enum.Material.Slate, Parent = shop })
		-- a thin accent ring under the cap, so the egg does not float on grey. This is the ONE place
		-- the zone's colour is allowed onto the stand -- a lit line, not a surface.
		newPart({ Name = "PodiumGlow", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 12.9, 12.9), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(ex, PLAZA_PODIUM_TOP - 1.4, 0), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = shop })

		local eggY = PLAZA_PODIUM_TOP + EGG_SHELL_SIZE.Y / 2
		-- the zone is threaded through so the stall can show this zone's own eggs; buildEggPlaza is
		-- called after ACTIVE_ZONE_KEY has been cleared, so the global is not available here
		local shell = buildEgg(shop, ex, egg.tierSuffix, eggY, zone and zone.key or nil)
		local style = EGG_TIER_STYLE[egg.tierSuffix] or EGG_TIER_STYLE.Basic
		addEggShowcase(shop, ex, eggY, accent, style)

		-- the rarest pet this egg can give, hovering between the shell and the halo, with the
		-- full five-species list above it. Together they are the whole answer to "what is in
		-- this egg", which is the question the three eggs on a podium exist to ask.
		-- RAISED TO CLEAR THE EGGS SIGN. These two are BillboardGuis: they always face the camera and
		-- always draw over whatever is behind them in screen space, so at their old heights the middle
		-- egg's featured pet sat squarely across the painted panel on the board -- from the front, the
		-- one angle the stall is designed to be seen from, the word EGGS was simply gone. The sign is
		-- a physical part and cannot be moved above them without floating off the board, so the
		-- billboards move instead. (They also had to clear the shells, which grew 40% earlier.)
		-- The odds strip goes ABOVE the featured pet, not between it and the egg. The pet is a real
		-- model about seven studs tall, so anything hung at +22 gets stood in front of by it.
		buildEggFeaturePet(shop, egg, ex, eggY + 19)
		buildEggOddsBoard(shop, egg, ex, eggY + 29)

		-- halo above the egg doubles as the spotlight source: a bare PointLight with nothing
		-- visible making it reads as the shell glowing on its own. It sits above the featured
		-- pet so the pet reads as lit from over its head rather than clipping through the disc.
		local halo = newPart({ Name = "PodiumHalo", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.7, 13, 13), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(ex, eggY + 33, 0), Color = lighten(accent, 0.3), Material = Enum.Material.Neon, Transparency = 0.55, CanCollide = false, Parent = shop })
		addLight(halo, lighten(accent, 0.3), 20, 1.1)

		-- one price card per podium, tier and cost on two lines. Both were nearly put on the back
		-- wall, but a billboard 21 studs behind the egg renders *behind* it in screen space and
		-- the shell hides the tier name -- in front of the podium it reads like a real price tag.
		makePriceCard(shop, ex, PLAZA_DECK_TOP + 1.6, egg, (EGG_TIER_STYLE[egg.tierSuffix] or EGG_TIER_STYLE.Basic).base)

		built[i] = shell
	end

	-- The canopy, the pylons and the back wall were dropping the whole shop into shadow at every
	-- ClockTime -- and this is the one spot in a zone where players stand still and look at
	-- things. Nothing structural here casts a shadow any more, and two warm fills under the beam
	-- lift the eggs off the deck -- gently: at 1.9 they blew the shells out to flat white and the
	-- speckles disappeared, which is the opposite of the point.
	-- The name prefix changed with the rebuild (Plaza* -> Stall*), and a shadow flag that silently
	-- matches nothing is worse than no flag at all -- the board and posts would have started
	-- casting again with nothing in the diff to say why.
	for _, d in ipairs(shop:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name:sub(1, 5) == "Stall" or d.Name:sub(1, 6) == "Podium") then
			d.CastShadow = false
		end
	end
	for _, side in ipairs({ -1, 1 }) do
		local fill = newPart({
			Name = "StallFill",
			Size = Vector3.new(1, 1, 1),
			Position = Vector3.new(cx + side * 14, 27, PLAZA_Z + 6),
			Transparency = 1,
			CanCollide = false,
			CastShadow = false,
			Parent = shop,
		})
		addLight(fill, Color3.fromRGB(255, 246, 220), 40, 0.4)
	end

	return built
end

-- ===== BOSS EVENT ARENA =====
-- A round sand pit with a raised dais in the middle, ringed by a stepped stand, torch pylons and
-- banners. It sits straight through the gate at the Forest spawn (GameConfig.EventArena.centre) and
-- is reached no other way, which is why it can be this far off the zone strip and cost nothing.
--
-- Everything is laid out from the centre outward by angle, so the whole thing is four loops rather
-- than a hand-placed floor plan -- and it stays perfectly circular at any radius.
-- ---- COLOSSEUM DRESSING HELPERS. They live here rather than up with the shared soft-prop
-- vocabulary because nothing else in the world is a circular amphitheatre: every one of them is
-- stated in the arena's own polar terms (an angle and a radius out from one centre).

-- Generated hero props are harvested into ServerStorage.ColosseumMeshes and cloned from there.
-- NIL IS A VALID ANSWER. A mesh that was never generated, or a folder nobody made, has to cost
-- the build exactly nothing -- an arena with no statues must come out as complete as one with
-- them, rather than stopping halfway through the arcade with an index error.
local function coloMesh(key)
	local folder = ServerStorage:FindFirstChild("ColosseumMeshes")
	local src = folder and folder:FindFirstChild(key)
	return src and src:Clone() or nil
end

-- One flat disc of the arena floor. Every ring of the floor pattern is one of these laid over a
-- slightly larger one, so a "ring" costs two parts and can never come out off-centre.
--
-- THE ONLY THING KEEPING THEM APART IS `top`. Each disc is grown DOWNWARD from its own top face
-- to a common buried bottom at y = -0.6, so two discs never share a horizontal plane and the
-- depth buffer is never asked to choose between them. Coplanar discs on this exact floor are
-- what produced the shimmer the raked rings were rewritten to cure; this is that fix, generalised.
local function coloDisc(model, name, centre, radius, top, colour, material)
	local thickness = top + 0.6
	return newPart({
		Name = name, Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thickness, radius * 2, radius * 2),
		Orientation = Vector3.new(0, 0, 90),
		Position = centre + Vector3.new(0, top - thickness / 2, 0),
		Color = colour, Material = material or Enum.Material.Sand,
		CanCollide = false, CastShadow = false, Parent = model,
	})
end

local function buildEventArena(parent)
	local cfg = GameConfig.EventArena
	local centre = cfg.centre
	local R = cfg.radius
	local accent = vivid(cfg.accentColor)
	local sand = cfg.groundColor
	local stone = Color3.fromRGB(206, 194, 172)
	local stoneDark = Color3.fromRGB(148, 136, 116)
	local stoneLite = Color3.fromRGB(238, 230, 212)

	-- ---- THE STONE LADDER. The arena read as a grey blockout for one reason above all others:
	-- every ring of it was cut from the same two tones in the same material, so a bowl three
	-- storeys deep came back to the eye as one flat value. Four tones and four materials, warmest
	-- and palest at the sand and cooling as it climbs, is what lets the tiers read as separate
	-- rings of masonry from outside the building as well as from the middle of it.
	local TIER_TONE = {
		Color3.fromRGB(240, 226, 196),
		Color3.fromRGB(214, 198, 170),
		Color3.fromRGB(182, 172, 158),
		Color3.fromRGB(150, 142, 134),
	}
	local TIER_MAT = {
		Enum.Material.Sandstone,
		Enum.Material.Concrete,
		Enum.Material.Slate,
		Enum.Material.Marble,
	}
	-- the ink the whole building is drawn with. Every lip, plinth, band and cornice is this one
	-- colour, and a dark rim on each horizontal is the single thing that turns a stack of pale
	-- boxes into something that looks drawn rather than merely modelled.
	local ink = Color3.fromRGB(72, 60, 52)
	local trim = Color3.fromRGB(112, 96, 82)
	-- the cold half of the bunting. One accent repeated 60 times is wallpaper; two alternating
	-- ones is a decorated building.
	local accent2 = Color3.fromRGB(96, 188, 232)
	local sandLite = sand:Lerp(Color3.new(1, 1, 1), 0.22)
	local sandDark = sand:Lerp(Color3.new(0, 0, 0), 0.30)

	local model = Instance.new("Model")
	model.Name = "EventArena"
	model.Parent = parent

	-- ---- The ground. Everything here stands on ONE disc, and it has to reach past the outermost
	-- thing built on it: the stand's third tier sits at radius R + 54 and the return gate at R + 8.
	-- Sized to the pit alone first time round, both of those hung over the void -- and a player who
	-- walked toward the way home simply stopped at the sand's edge with the gate out of reach.
	--
	-- R + 92 was sized for the four seating tiers and the return gate. The outer arcade stands at
	-- tierRadius[TIERS] + 26 = R + 93 and the towers 4 further out again, so at the old figure the
	-- entire exterior wall of the building was hanging over the edge of its own island with nothing
	-- under it. Kept in step with the arcade rather than written out twice: the arcade radius is
	-- derived from tierRadius further down and both come from the same three constants.
	local GROUND_R = R + 132
	local ground = newPart({ Name = "ArenaGround", Shape = Enum.PartType.Cylinder, Size = Vector3.new(8, GROUND_R * 2, GROUND_R * 2),
		Orientation = Vector3.new(0, 0, 90), Position = centre + Vector3.new(0, -4, 0),
		Color = stoneDark, Material = Enum.Material.Slate, Parent = model })
	model.PrimaryPart = ground
	newPart({ Name = "ArenaGroundTrim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, GROUND_R * 2 + 8, GROUND_R * 2 + 8),
		Orientation = Vector3.new(0, 0, 90), Position = centre + Vector3.new(0, -0.6, 0),
		Color = accent, Material = Enum.Material.Neon, Transparency = 0.5, CanCollide = false, Parent = model })

	-- the pit itself: a shallow disc of sand laid on the ground, so the fighting floor reads as a
	-- different surface from the concourse the stand sits on
	local floor = newPart({ Name = "ArenaFloor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, R * 2, R * 2),
		Orientation = Vector3.new(0, 0, 90), Position = centre + Vector3.new(0, 0.6, 0),
		Color = sand, Material = Enum.Material.Sand, Parent = model })

	-- ---- THE FLOOR PATTERN. One flat disc of sand is what a blockout looks like; three raked
	-- rings of almost the same colour on top of it is what one looks like from further away. Read
	-- from the middle outward it is now a marked-out fighting floor: the apron round the dais, a
	-- painted ring line, the combat circle, a kerb, and a darker packed track round the outside
	-- where nobody fights and everything has been worn or dropped.
	--
	-- ALL THREE RAKES STOOD AT THE SAME HEIGHT once -- y = 1.5, thickness 0.4 -- so they were three
	-- exactly coplanar discs of different colours fighting over 59,000 square studs on the game's
	-- showpiece arena. coloDisc is the general fix: every disc grows down to one buried bottom from
	-- its own unique top face, so no two of them can ever share a plane again.
	local FLOOR_RINGS = {
		{ r = R - 1,  top = 2.00, c = sandDark, m = Enum.Material.Concrete },  -- the outer track
		{ r = R - 26, top = 2.10, c = accent,   m = Enum.Material.Slate },     -- its painted kerb
		{ r = R - 32, top = 2.20, c = sandLite, m = Enum.Material.Sand },      -- the combat circle
		{ r = 108,    top = 2.30, c = accent,   m = Enum.Material.Slate },     -- inner ring line
		{ r = 102,    top = 2.40, c = sand,     m = Enum.Material.Sand },
		{ r = 80,     top = 2.50, c = sandDark, m = Enum.Material.Concrete },  -- the dais apron
	}
	for i, ring in ipairs(FLOOR_RINGS) do
		coloDisc(model, "ArenaFloorRing" .. i, centre, ring.r, ring.top, ring.c, ring.m)
	end

	-- radial dividing lines across the track, long and short by turns, so the pattern has a
	-- direction as well as a centre. They stop short of the ring line at r = 108: the middle of
	-- the pit is where a 124-stud boss lands and it stays plain on purpose.
	for i = 0, 23 do
		local a = i * math.pi * 2 / 24
		local long = (i % 2 == 0)
		local len = long and 72 or 38
		newPart({ Name = "ArenaFloorSpoke", Size = Vector3.new(long and 4.5 or 3, 0.7, len),
			CFrame = CFrame.new(centre + Vector3.new(0, 2.55, 0)) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -(R - 30 - len / 2)),
			Color = sandDark, Material = Enum.Material.Concrete, CanCollide = false, CastShadow = false, Parent = model })
	end

	-- ---- WEAR. Cracks running in from the rim and chips of the stand's own stone lying where they
	-- fell. Both are kept out on the track: rubble underfoot in the middle is noise in the one
	-- place the eye has to stay clear, and it is also where the players a giant is chasing run.
	-- The cracks are 2 studs thick and sunk to y = 1, so they read as splits in the floor rather
	-- than as decals floating a fraction above it.
	for i = 0, 17 do
		local a = (i + 0.5) * math.pi * 2 / 18 + math.rad((i % 5) * 3)
		local len = 26 + (i % 4) * 11
		newPart({ Name = "ArenaCrack", Size = Vector3.new(1.6 + (i % 3) * 0.7, 2, len),
			CFrame = CFrame.new(centre + Vector3.new(0, 2, 0)) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -(R - 6 - len / 2)),
			Color = sandDark:Lerp(Color3.new(0, 0, 0), 0.4), Material = Enum.Material.Slate,
			CanCollide = false, CastShadow = false, Parent = model })
	end
	for i = 0, 21 do
		local a = (i * 0.61) * math.pi * 2
		local rr = R - 8 - (i % 6) * 9
		local s = 3.4 + (i % 4) * 1.8
		newPart({ Name = "ArenaChip", Size = Vector3.new(s * 1.4, s * 0.7, s),
			CFrame = CFrame.new(centre + Vector3.new(0, 1.8 + s * 0.35, 0)) * CFrame.Angles(0, a, 0)
				* CFrame.new(0, 0, -rr) * CFrame.Angles(0, i * 0.9, 0),
			Color = (i % 3 == 0) and stoneLite or stone, Material = Enum.Material.Slate,
			CanCollide = false, CastShadow = false, Parent = model })
	end

	-- ---- the dais the boss stands on
	newPart({ Name = "ArenaDaisBase", Shape = Enum.PartType.Cylinder, Size = Vector3.new(5, 150, 150),
		Orientation = Vector3.new(0, 0, 90), Position = centre + Vector3.new(0, 4, 0),
		Color = stoneDark, Material = Enum.Material.Slate, Parent = model })
	newPart({ Name = "ArenaDais", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 132, 132),
		Orientation = Vector3.new(0, 0, 90), Position = centre + Vector3.new(0, 7.5, 0),
		Color = stone, Material = Enum.Material.Slate, Parent = model })
	local glowRing = newPart({ Name = "ArenaDaisGlow", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 140, 140),
		Orientation = Vector3.new(0, 0, 90), Position = centre + Vector3.new(0, 6.7, 0),
		Color = accent, Material = Enum.Material.Neon, Transparency = 0.35, CanCollide = false, CastShadow = false, Parent = model })
	addLight(glowRing, accent, 90, 2.4)
	pulseForever(glowRing, 0.62, 3.2)

	-- sigils burned into the dais, alternating long and short so the ring reads as writing
	for i = 1, 16 do
		local a = (i - 1) * math.pi / 8
		newPart({ Name = "ArenaSigil", Size = Vector3.new(5, 0.5, i % 2 == 0 and 22 or 12),
			CFrame = CFrame.new(centre + Vector3.new(0, 9.1, 0)) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -52),
			Color = accent, Material = Enum.Material.Neon, Transparency = 0.25, CanCollide = false, CastShadow = false, Parent = model })
	end

	-- ---- the stand: FOUR stepped tiers of seating around the pit, broken by the entrance.
	-- Blocks are placed at `Angles(0, a, 0) * (0, 0, -rr)`, so a = 0 IS the gate direction (-Z) and
	-- the gap is the wrapped angular distance from zero. Every tier has to open, not just the inner
	-- ones: the gate's own columns stand in the rim and an unbroken ring would bury them.
	--
	-- FOUR rings rather than three, each with its own tone and its own material off the ladder
	-- above. Three identical grey steps read as a kerb around a pit; four that visibly change
	-- colour as they climb read as an amphitheatre, and they do it from OUTSIDE the building too,
	-- which is the half that was missing. The radii and tops are published into two arrays because
	-- the crowd, the outer arcade and the aisles all have to land exactly on them -- every one of
	-- those was a hand-copied magic number before, and they went stale the moment a tier moved.
	local ENTRY_HALF = math.rad(34)
	local TIERS = 4
	local tierRadius, tierTop = {}, {}
	for tier = 1, TIERS do
		tierRadius[tier] = R + 13 + (tier - 1) * 18
		tierTop[tier] = 7 + (tier - 1) * 11
	end
	for tier = 1, TIERS do
		local rr = tierRadius[tier]
		local h = tierTop[tier] + 4
		local tone = TIER_TONE[tier]
		for i = 0, 47 do
			local a = i * math.pi * 2 / 48
			local fromGate = math.abs(((a + math.pi) % (math.pi * 2)) - math.pi)
			if fromGate >= ENTRY_HALF then
				-- six aisles cut straight up the bowl. They cost nothing but a colour: the steps are
				-- already there, and a darker stair run climbing all four rings is what stops the
				-- seating being one undifferentiated band of stone all the way round.
				local aisle = (i % 8 == 4)
				local block = newPart({ Name = "StandBlock", Size = Vector3.new(30, h, 22),
					CFrame = CFrame.new(centre + Vector3.new(0, h / 2 - 4, 0)) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -rr),
					Color = aisle and trim or ((i % 2 == 0) and tone or tone:Lerp(Color3.new(1, 1, 1), 0.12)),
					Material = aisle and Enum.Material.Cobblestone or TIER_MAT[tier], Parent = model })
				-- the ink lip. It is the tread a player actually stands on AND it is the outline that
				-- separates one ring of seats from the next at any distance -- the same dark rim that
				-- makes every other shape in this game read as drawn rather than as geometry.
				newPart({ Name = "StandLip", Size = Vector3.new(31, 1.8, 23.4),
					CFrame = block.CFrame * CFrame.new(0, h / 2, 0),
					Color = ink, Material = Enum.Material.Slate, CanCollide = false, Parent = model })
			end
		end
	end

	-- ===== THE OUTER ARCADE: WHAT THE BUILDING LOOKS LIKE FROM OUTSIDE =====
	--
	-- Everything above this point is the INSIDE of the bowl. From the approach -- which is how every
	-- player first meets the place, walking at it through the portal -- the arena was the outer face
	-- of the top tier: one unbroken ring of identical pale slabs, 48 of them, all the same height.
	-- That is the row of grey rectangles in the report, and no amount of work on the seating touches
	-- it, because the seating is not what you are looking at.
	--
	-- A real amphitheatre's exterior is an ARCADE: piers carrying arches, in a repeating order, with
	-- a cornice over it. Three things make that read at this scale and all three are cheap:
	--
	--   * a PIER-ARCH-PIER rhythm, so the wall has holes in it and the eye can measure its depth;
	--   * alternating BAY HEIGHTS on a period that does not divide the bay count, so the skyline is
	--     never a straight line and never an obvious repeat;
	--   * a continuous dark CORNICE over the whole thing, which is the outline rule again -- the one
	--     horizontal that turns a stack of pale boxes into a drawn building.
	--
	-- Radius is taken off `tierRadius[TIERS]`, not written out: the arcade is the skin on the
	-- outermost tier and a hand-copied number goes stale the moment a tier moves.
	local BAYS = 32
	local arcadeR = tierRadius[TIERS] + 26
	-- A SKIRT OF STEPS from the arcade's foot out to the rim. Without it the building ends on a
	-- vertical drop into the void and reads as a model standing on a plate; three shallow rings
	-- stepping down give it a base, and they are what the approach actually walks up.
	for s = 1, 3 do
		coloDisc(model, "ArenaSkirt", centre, arcadeR + 8 + (3 - s) * 11, -1 + s * 1.6,
			(s % 2 == 0) and stoneDark or trim, Enum.Material.Slate)
	end
	local bayStep = math.pi * 2 / BAYS
	for i = 0, BAYS - 1 do
		local a = i * bayStep
		-- the gate mouth stays open, same rule and the same constant the stands and the pylons use
		if math.abs(((a + math.pi) % (math.pi * 2)) - math.pi) < ENTRY_HALF then
			continue
		end
		local at = CFrame.new(centre) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -arcadeR)
		-- 3 does not divide 32, so the tall bays walk round the ring instead of landing in the same
		-- place every time -- 32 bays of one height is wallpaper however well each one is modelled
		local tall = (i % 3 == 0)
		local H = tall and 74 or 58
		local pierW = 13
		local bayW = 2 * math.pi * arcadeR / BAYS

		-- THE PIER. Plinth, shaft, capital -- three parts, each wider or narrower than the one below,
		-- because a column that is one box from floor to roof reads as a post and a column with a
		-- foot and a head reads as masonry.
		newPart({ Name = "ArcadePlinth", Size = Vector3.new(pierW + 7, 6, 21),
			CFrame = at * CFrame.new(0, -1, 0), Color = ink, Material = Enum.Material.Slate, Parent = model })
		newPart({ Name = "ArcadePier", Size = Vector3.new(pierW, H, 17),
			CFrame = at * CFrame.new(0, 2 + H / 2, 0), Color = TIER_TONE[2],
			Material = Enum.Material.Sandstone, Parent = model })
		-- a fluting stripe down the front, proud of the shaft so it is never coplanar with it
		newPart({ Name = "ArcadeFlute", Size = Vector3.new(4, H - 12, 2),
			CFrame = at * CFrame.new(0, 2 + H / 2, -9.4), Color = stoneLite,
			Material = Enum.Material.Sandstone, CanCollide = false, CastShadow = false, Parent = model })
		newPart({ Name = "ArcadeCapital", Size = Vector3.new(pierW + 6, 6, 21),
			CFrame = at * CFrame.new(0, 4 + H, 0), Color = trim, Material = Enum.Material.Slate,
			CanCollide = false, Parent = model })

		-- THE ARCH between this pier and the next. Roblox has no arc primitive, so it is five short
		-- voussoirs swung across the opening on their own angles -- which at this size reads as a
		-- round-headed arch and, unlike a wedge, cannot land somewhere unintended when the whole bay
		-- is also yawed. The middle one is the keystone and it is a different tone on purpose: it is
		-- the only thing that says "arch" rather than "hole" at a hundred studs.
		local midA = a + bayStep / 2
		local springY = 2 + H * 0.66
		local rise = H * 0.2
		local VOUSSOIRS = 5
		for v = 1, VOUSSOIRS do
			local t = (v - 0.5) / VOUSSOIRS               -- 0..1 across the opening
			local off = (t - 0.5) * (bayW - pierW)        -- sideways, in studs along the chord
			local lift = math.sin(t * math.pi) * rise     -- a half sine IS the arch curve
			local tilt = math.cos(t * math.pi) * 0.5      -- each stone rolled to sit on the curve
			local key = (v == (VOUSSOIRS + 1) / 2)
			newPart({ Name = key and "ArcadeKeystone" or "ArcadeVoussoir",
				Size = Vector3.new((bayW - pierW) / VOUSSOIRS + 2, key and 15 or 11, 17),
				CFrame = CFrame.new(centre) * CFrame.Angles(0, midA, 0)
					* CFrame.new(off, springY + lift, -arcadeR) * CFrame.Angles(0, 0, tilt),
				Color = key and stoneLite or TIER_TONE[2]:Lerp(Color3.new(1, 1, 1), 0.1),
				Material = Enum.Material.Sandstone, CanCollide = false, Parent = model })
		end
		-- the dark void behind the opening. Without it you see straight through the arcade to the
		-- seating behind, and an arch you can see daylight through reads as a gap in a fence.
		newPart({ Name = "ArcadeShadow", Size = Vector3.new(bayW - pierW, springY - 4, 3),
			CFrame = CFrame.new(centre) * CFrame.Angles(0, midA, 0) * CFrame.new(0, 2 + (springY - 4) / 2, -arcadeR + 7),
			Color = ink, Material = Enum.Material.Slate, CanCollide = false, CastShadow = false, Parent = model })

		-- THE CORNICE. One dark band running the whole ring at the pier head, and a paler attic course
		-- sitting on it. This is the single piece that ties 32 separate bays into one building.
		newPart({ Name = "ArcadeCornice", Size = Vector3.new(bayW + 3, 5, 24),
			CFrame = CFrame.new(centre) * CFrame.Angles(0, midA, 0) * CFrame.new(0, 9 + H, -arcadeR),
			Color = ink, Material = Enum.Material.Slate, CanCollide = false, Parent = model })
		newPart({ Name = "ArcadeAttic", Size = Vector3.new(bayW + 1, 9, 18),
			CFrame = CFrame.new(centre) * CFrame.Angles(0, midA, 0) * CFrame.new(0, 16 + H, -arcadeR),
			Color = TIER_TONE[4], Material = Enum.Material.Marble, CanCollide = false, Parent = model })
		-- merlons on the attic, every other bay, so the roofline is toothed rather than ruled
		if i % 2 == 0 then
			newPart({ Name = "ArcadeMerlon", Size = Vector3.new(10, 9, 18),
				CFrame = CFrame.new(centre) * CFrame.Angles(0, midA, 0) * CFrame.new(0, 25 + H, -arcadeR),
				Color = TIER_TONE[4], Material = Enum.Material.Marble, CanCollide = false, Parent = model })
		end
	end

	-- ---- SIX CORNER TOWERS, taller than the arcade, each with a banner and a lit finial. The
	-- arcade above gives the wall texture but its skyline is still a band of near-constant height,
	-- and a circular building with a constant skyline reads as a drum. Six verticals break it, and
	-- six is chosen against the twelve pylons and the 32 bays so nothing lines up into a pattern.
	for i = 0, 5 do
		local a = (i + 0.5) * math.pi / 3
		if math.abs(((a + math.pi) % (math.pi * 2)) - math.pi) < ENTRY_HALF then
			continue
		end
		local at = CFrame.new(centre) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -(arcadeR + 4))
		local cloth = (i % 2 == 0) and accent or accent2
		newPart({ Name = "ArenaTowerBase", Size = Vector3.new(38, 8, 34),
			CFrame = at * CFrame.new(0, 0, 0), Color = ink, Material = Enum.Material.Slate, Parent = model })
		newPart({ Name = "ArenaTower", Size = Vector3.new(30, 106, 26),
			CFrame = at * CFrame.new(0, 55, 0), Color = TIER_TONE[3],
			Material = Enum.Material.Sandstone, Parent = model })
		-- two string courses, both proud of the shaft, so a 106-stud tower has storeys
		for _, y in ipairs({ 38, 74 }) do
			newPart({ Name = "ArenaTowerBand", Size = Vector3.new(34, 5, 30),
				CFrame = at * CFrame.new(0, y, 0), Color = trim, Material = Enum.Material.Slate,
				CanCollide = false, Parent = model })
		end
		-- a lit window slot on each storey -- the cheapest way to say "there is an inside"
		for _, y in ipairs({ 52, 88 }) do
			newPart({ Name = "ArenaTowerWindow", Size = Vector3.new(8, 16, 3),
				CFrame = at * CFrame.new(0, y, -14), Color = accent, Material = Enum.Material.Neon,
				Transparency = 0.25, CanCollide = false, CastShadow = false, Parent = model })
		end
		newPart({ Name = "ArenaTowerCap", Size = Vector3.new(38, 7, 34),
			CFrame = at * CFrame.new(0, 110, 0), Color = ink, Material = Enum.Material.Slate,
			CanCollide = false, Parent = model })
		-- the roof: two shrinking blocks rather than a cone, for the reason written on the idols'
		-- ears -- a stack of tapering boxes reads as a pointed roof from every angle and a Wedge
		-- does not survive being yawed
		newPart({ Name = "ArenaTowerRoof", Size = Vector3.new(28, 16, 25),
			CFrame = at * CFrame.new(0, 121, 0), Color = cloth, Material = Enum.Material.Slate,
			CanCollide = false, Parent = model })
		newPart({ Name = "ArenaTowerSpire", Size = Vector3.new(14, 18, 13),
			CFrame = at * CFrame.new(0, 137, 0), Color = cloth:Lerp(ink, 0.35),
			Material = Enum.Material.Slate, CanCollide = false, Parent = model })
		local finial = newPart({ Name = "ArenaTowerFinial", Size = Vector3.new(11, 11, 11),
			CFrame = at * CFrame.new(0, 150, 0), Color = accent, Material = Enum.Material.Neon,
			CanCollide = false, CastShadow = false, Parent = model })
		local fm = Instance.new("SpecialMesh")
		fm.MeshType = Enum.MeshType.Sphere
		fm.Parent = finial
		addLight(finial, accent, 84, 3)
		pulseForever(finial, 0.34, 2.2 + (i % 3) * 0.5)
		-- a long banner down the tower's face, which is what gives it a colour at range
		newPart({ Name = "ArenaTowerBanner", Size = Vector3.new(20, 62, 1.4),
			CFrame = at * CFrame.new(0, 66, -14.4), Color = cloth, Material = Enum.Material.Fabric,
			CanCollide = false, Parent = model })
		newPart({ Name = "ArenaTowerBannerBar", Size = Vector3.new(24, 3, 4),
			CFrame = at * CFrame.new(0, 98, -14.4), Color = ink, Material = Enum.Material.Slate,
			CanCollide = false, CastShadow = false, Parent = model })
	end

	-- ---- BUNTING between the towers, strung round the outside at cornice height. Two colours
	-- alternating, because one accent repeated round a ring is wallpaper -- the same note the pylon
	-- banners carry. Purely decorative and non-colliding: this hangs outside the wall.
	for i = 0, 59 do
		local a = i * math.pi * 2 / 60
		if math.abs(((a + math.pi) % (math.pi * 2)) - math.pi) < ENTRY_HALF then
			continue
		end
		newPart({ Name = "ArenaBunting", Shape = Enum.PartType.Wedge, Size = Vector3.new(9, 11, 1),
			CFrame = CFrame.new(centre) * CFrame.Angles(0, a, 0)
				* CFrame.new(0, 84 + math.sin(i * 0.7) * 4, -(arcadeR + 12)) * CFrame.Angles(0, 0, math.pi),
			Color = (i % 2 == 0) and accent or accent2, Material = Enum.Material.Fabric,
			CanCollide = false, CastShadow = false, Parent = model })
	end

	-- ---- torch pylons around the rim, and a banner between every pair.
	-- The stands above open a gap of +-ENTRY_HALF around a = 0 for the gate, and the pylons have to
	-- respect the SAME gap. They did not: i = 0 planted a 62-stud slate column, its torch and its
	-- banner dead centre in the portal's mouth, so the way in was a doorway with a post in it.
	for i = 0, 11 do
		local a = i * math.pi / 6
		if math.abs(((a + math.pi) % (math.pi * 2)) - math.pi) < ENTRY_HALF then
			continue
		end
		local at = CFrame.new(centre) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -(R + 2))
		local cloth = (i % 2 == 0) and accent or accent2
		newPart({ Name = "ArenaPylonFoot", Size = Vector3.new(17, 7, 17), CFrame = at * CFrame.new(0, 0, 0),
			Color = ink, Material = Enum.Material.Slate, Parent = model })
		newPart({ Name = "ArenaPylon", Size = Vector3.new(10, 64, 10), CFrame = at * CFrame.new(0, 30, 0), Color = TIER_TONE[3], Material = Enum.Material.Sandstone, Parent = model })
		-- two bands round the shaft, both proud of it, so a 64-stud post has a middle and a top
		newPart({ Name = "ArenaPylonBand", Size = Vector3.new(13, 4, 13), CFrame = at * CFrame.new(0, 20, 0), Color = trim, Material = Enum.Material.Slate, CanCollide = false, Parent = model })
		newPart({ Name = "ArenaPylonCap", Size = Vector3.new(15, 5, 15), CFrame = at * CFrame.new(0, 61, 0), Color = ink, Material = Enum.Material.Slate, CanCollide = false, Parent = model })
		-- A NON-UNIFORM `Shape = Ball` IS DRAWN AS A SPHERE OF ITS SMALLEST AXIS. This flame was
		-- authored 12 x 15 x 12 and rendered as a 12-ball -- the taller flame shape it was asking
		-- for never once appeared. Block plus a Sphere SpecialMesh is the only way to get an
		-- ellipsoid, and it is the same fix the eggs and the boss armour needed.
		local flame = newPart({ Name = "ArenaTorch", Size = Vector3.new(13, 18, 13),
			CFrame = at * CFrame.new(0, 70, 0), Color = accent, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = model })
		local flameMesh = Instance.new("SpecialMesh")
		flameMesh.MeshType = Enum.MeshType.Sphere
		flameMesh.Parent = flame
		addLight(flame, accent, 70, 3)
		pulseForever(flame, 0.42, 1.7 + (i % 3) * 0.4)
		-- banner hanging on the pylon, facing the pit, alternating warm and cold round the ring
		newPart({ Name = "ArenaBanner", Size = Vector3.new(16, 36, 1.2), CFrame = at * CFrame.new(0, 36, 6.2), Color = cloth, Material = Enum.Material.Fabric, CanCollide = false, Parent = model })
		newPart({ Name = "ArenaBannerBar", Size = Vector3.new(19, 2.4, 3), CFrame = at * CFrame.new(0, 55, 6.2), Color = ink, Material = Enum.Material.Slate, CanCollide = false, CastShadow = false, Parent = model })
		newPart({ Name = "ArenaBannerCrest", Size = Vector3.new(9, 9, 1.4), CFrame = at * CFrame.new(0, 40, 7.1) * CFrame.Angles(0, 0, math.pi / 4), Color = stoneLite, Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = model })
		newPart({ Name = "ArenaBannerTail", Shape = Enum.PartType.Wedge, Size = Vector3.new(16, 10, 1.2),
			CFrame = at * CFrame.new(0, 13, 6.2) * CFrame.Angles(0, 0, math.pi),
			Color = cloth, Material = Enum.Material.Fabric, CanCollide = false, Parent = model })
	end

	-- ---- the countdown board. High over the dais rather than over the entrance: hung on the rim
	-- it was outside the gate and the gate's own stonework stood in front of it from every seat in
	-- the house. Above the middle it is readable from anywhere on the sand, and it clears the boss's
	-- own name plate (which tops out around y = 150 on a 124-stud rig).
	local boardAnchor = newPart({ Name = "ArenaBoard", Size = Vector3.new(4, 4, 4),
		Position = centre + Vector3.new(0, 232, 0), Transparency = 1, CanCollide = false, Parent = model })
	local board = Instance.new("BillboardGui")
	board.Name = "CountdownBoard"
	board.Size = UDim2.new(96, 0, 30, 0) -- in studs: a pixel-sized board keeps its screen size at range
	board.AlwaysOnTop = false
	board.LightInfluence = 0
	board.MaxDistance = 700
	board.Parent = boardAnchor
	local label = Instance.new("TextLabel")
	label.Name = "Countdown"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundColor3 = Color3.fromRGB(24, 18, 30)
	label.BackgroundTransparency = 0.15
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeColor3 = Color3.fromRGB(16, 12, 26)
	label.TextStrokeTransparency = 0
	label.Text = "\u{2694}\u{FE0F} COLOSSEUM"
	label.Parent = board
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = label
	local edge = Instance.new("UIStroke")
	edge.Thickness = 4
	edge.Color = accent
	edge.Parent = label
	CollectionService:AddTag(boardAnchor, "ArenaCountdown")

	-- ---- the way home. Built through the same buildPortal as every boundary gate, stood in the
	-- -Z rim facing the pit, and tagged with a target ZoneService knows how to read.
	local returnTarget = {
		key = "ReturnFromArena", name = "Back", emoji = "\u{1F3E0}",
		accentColor = Color3.fromRGB(120, 220, 140), offset = 0,
	}
	-- yaw -90, not 180. buildPortal is written with local +X pointing at the interior, and a yaw of
	-- 180 sends that to world -X -- the gate stood correctly in the rim but its steps, mat, runes
	-- and guardians all faced sideways out of the arena instead of in across the sand.
	local previous = ZoneKit.getFrame()
	ZoneKit.setFrame(CFrame.new(centre + Vector3.new(0, 0, -(R + 8))) * CFrame.Angles(0, math.rad(-90), 0))
	buildPortal(model, 0, returnTarget, 1)
	ZoneKit.setFrame(previous)

	-- ---- WHAT IT STANDS ON. Seen from anywhere but directly overhead the whole Colosseum was a
	-- coin on edge: an 8-stud disc with 600 studs of empty sky under it. Two stepped drums beneath
	-- the ground read as the rock it was cut out of, and cost two parts to say it.
	newPart({ Name = "ArenaBed", Shape = Enum.PartType.Cylinder, Size = Vector3.new(46, GROUND_R * 2 - 26, GROUND_R * 2 - 26),
		Orientation = Vector3.new(0, 0, 90), Position = centre + Vector3.new(0, -31, 0),
		Color = stoneDark, Material = Enum.Material.Slate, Parent = model })
	newPart({ Name = "ArenaBedDeep", Shape = Enum.PartType.Cylinder, Size = Vector3.new(74, GROUND_R * 2 - 100, GROUND_R * 2 - 100),
		Orientation = Vector3.new(0, 0, 90), Position = centre + Vector3.new(0, -80, 0),
		Color = stoneDark:Lerp(Color3.new(0, 0, 0), 0.32), Material = Enum.Material.Slate, Parent = model })

	-- ---- THE OUTSIDE. The stand's top step was the last thing in every direction, so from the
	-- sand the building simply stopped at head height and from outside it had no face at all. A ring
	-- of thick piers standing past the top tier gives it one, and closes the horizon behind the
	-- seats. It breaks at the entrance on the same angle the stand does -- one opening, not two.
	local OUTER_R = GROUND_R - 16
	for i = 0, 23 do
		local a = i * math.pi * 2 / 24
		local fromGate = math.abs(((a + math.pi) % (math.pi * 2)) - math.pi)
		if fromGate >= ENTRY_HALF then
			local at = CFrame.new(centre) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -OUTER_R)
			newPart({ Name = "ArenaPier", Size = Vector3.new(46, 74, 22), CFrame = at * CFrame.new(0, 33, 0),
				Color = (i % 2 == 0) and stone or stoneLite, Material = Enum.Material.Slate, Parent = model })
			newPart({ Name = "ArenaPierCap", Size = Vector3.new(54, 9, 28), CFrame = at * CFrame.new(0, 74, 0),
				Color = stoneDark, Material = Enum.Material.Slate, CanCollide = false, Parent = model })
			-- a recessed arch on the inner face, so the ring reads as an arcade rather than a fence
			newPart({ Name = "ArenaPierArch", Size = Vector3.new(24, 34, 5), CFrame = at * CFrame.new(0, 24, -10),
				Color = stoneDark, Material = Enum.Material.Slate, CanCollide = false, Parent = model })
			-- every fourth pier carries a lamp. Every pier carrying one would be nineteen more lights
			-- in a scene that already runs twelve torches and fifteen runes.
			if i % 4 == 0 then
				newPart({ Name = "ArenaPierLamp", Shape = Enum.PartType.Ball, Size = Vector3.new(11, 11, 11),
					CFrame = at * CFrame.new(0, 84, 0), Color = accent, Material = Enum.Material.Neon,
					CanCollide = false, CastShadow = false, Parent = model })
			end
		end
	end

	-- ---- THE CROWD. Two blocks each and no faces: at this scale a spectator is a colour and a
	-- silhouette, and it is the thing that turns a ring of empty steps into a full house. They sit
	-- on the two outer tiers only -- the inner step is where the pylons and banners are.
	local SKIN = { Color3.fromRGB(248, 214, 180), Color3.fromRGB(226, 176, 132), Color3.fromRGB(168, 118, 82), Color3.fromRGB(112, 78, 58) }
	for i = 0, 43 do
		local a = (i + 0.5) * math.pi * 2 / 44
		local fromGate = math.abs(((a + math.pi) % (math.pi * 2)) - math.pi)
		if fromGate >= ENTRY_HALF + math.rad(5) then
			-- alternating tiers: the third step (top y 34, radius R+54) and the second (21, R+34).
			-- Both numbers come straight out of the stand loop above -- h = 12 + (tier-1)*13 sitting
			-- at h/2 - 4, so its top face is h - 4.
			local outer = (i % 2 == 0)
			local rr = outer and (R + 54) or (R + 34)
			local top = outer and 34 or 21
			local at = CFrame.new(centre + Vector3.new(0, top, 0)) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -rr)
			newPart({ Name = "Spectator", Size = Vector3.new(7.5, 9, 5), CFrame = at * CFrame.new(0, 4.5, 0),
				Color = VillageKit.candy(i), Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
			newPart({ Name = "SpectatorHead", Size = Vector3.new(6, 6, 5), CFrame = at * CFrame.new(0, 12, 0),
				Color = SKIN[(i % #SKIN) + 1], Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
		end
	end

	-- ---- THE ENTRANCE. The gap in the stand was only ever a gap -- three tiers stopping in
	-- mid-air on either side of the way home. A tower on each shoulder makes it a gateway.
	--
	-- Nothing is built ACROSS the opening on purpose. An arch over it is the obvious next move and
	-- it is the wrong one: the portal's own frame reaches y = 166 with its name board above that,
	-- and anything spanning the towers stands in front of it. The gate is what the player is
	-- walking at; it does not share its airspace.
	for _, side in ipairs({ -1, 1 }) do
		local a = side * (ENTRY_HALF + math.rad(3.4))
		local at = CFrame.new(centre) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -(R + 36))
		newPart({ Name = "ArenaGateTower", Size = Vector3.new(42, 100, 60), CFrame = at * CFrame.new(0, 46, 0),
			Color = stone, Material = Enum.Material.Slate, Parent = model })
		newPart({ Name = "ArenaGateTowerCap", Size = Vector3.new(50, 10, 68), CFrame = at * CFrame.new(0, 100, 0),
			Color = stoneDark, Material = Enum.Material.Slate, CanCollide = false, Parent = model })
		newPart({ Name = "ArenaGateBanner", Size = Vector3.new(26, 52, 1.4), CFrame = at * CFrame.new(0, 58, -30.8),
			Color = accent, Material = Enum.Material.Fabric, CanCollide = false, Parent = model })
		newPart({ Name = "ArenaGateBannerTail", Shape = Enum.PartType.Wedge, Size = Vector3.new(26, 12, 1.4),
			CFrame = at * CFrame.new(0, 26, -30.8) * CFrame.Angles(0, 0, math.pi),
			Color = accent, Material = Enum.Material.Fabric, CanCollide = false, Parent = model })
		local bowl = newPart({ Name = "ArenaGateFlame", Shape = Enum.PartType.Ball, Size = Vector3.new(17, 20, 17),
			CFrame = at * CFrame.new(0, 112, 0), Color = accent, Material = Enum.Material.Neon,
			CanCollide = false, CastShadow = false, Parent = model })
		addLight(bowl, accent, 90, 3.2)
		pulseForever(bowl, 0.46, 2.1)
	end

	-- ---- broken columns out on the sand. Six pieces, all near the rim: the middle of the pit is
	-- where a 124-stud boss lands and where the players it lands on have to be able to run.
	for i = 0, 5 do
		local a = (i + 0.35) * math.pi * 2 / 6
		local at = CFrame.new(centre) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -(R * 0.87))
		local h = 9 + (i % 3) * 7
		newPart({ Name = "ArenaRubble", Size = Vector3.new(15, h, 15),
			CFrame = at * CFrame.new(0, h / 2 + 1.4, 0) * CFrame.Angles(0, math.rad(i * 19), 0),
			Color = stoneLite, Material = Enum.Material.Slate, Parent = model })
		newPart({ Name = "ArenaRubbleCap", Size = Vector3.new(18, 3, 18),
			CFrame = at * CFrame.new(0, h + 2.9, 0) * CFrame.Angles(0, math.rad(i * 19), 0),
			Color = stoneDark, Material = Enum.Material.Slate, CanCollide = false, Parent = model })
	end

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and not d.Anchored then d.Anchored = true end
	end
	model:SetAttribute("ArenaVersion", ARENA_VERSION)
	return model
end

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

			-- Pet Shop: 3 eggs (Basic/Better/Premium) on a lit podium plaza in the middle of the
			-- zone. Each egg has its own ProximityPrompt tagged with an EggKey attribute so
			-- PetService can wire purchases fresh on every server start.
			do
				local eggs = GameConfig.GetEggsForZone(zone.key)
				if #eggs > 0 then
					local shop = Instance.new("Model")
					shop.Name = "PetShop"
					shop.Parent = model

					local shells = buildEggPlaza(shop, zone, cx, eggs)
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
	if arena and arena:GetAttribute("ArenaVersion") ~= ARENA_VERSION then
		warn(("[ZoneBuilder] rebuilding the Colosseum: stamp %s -> %d")
			:format(tostring(arena:GetAttribute("ArenaVersion")), ARENA_VERSION))
		arena:Destroy()
		arena = nil
	end
	if not arena then
		buildEventArena(zonesFolder)
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

