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
local BUILD_VERSION = 127

-- The Colosseum carries its own stamp. Bumping BUILD_VERSION drops all 21 zones and rebuilds
-- ~60,000 parts, which takes long enough that Studio regularly loses the connection partway (see
-- the half-built-zone guard in Build). The arena is ~900 parts, it is reached only by teleport,
-- and it has already had to move once -- so it gets a stamp of its own and is rebuilt alone.
local ARENA_VERSION = 2

-- Roughly 2.4x the old 450 x 550. The zone had one street with a shop on it and two market
-- stalls beside it, and that filled the platform -- there was nowhere to put more creatures
-- without them standing in the walkway. Everything below is expressed against these two numbers
-- or against the derived constants further down, so the platform is the only thing to change.
--
-- ONE THING LIVES OUTSIDE THIS FILE AND HAS TO MOVE WITH IT: `GameConfig.ZoneSpacing`, the gap
-- between two zones' centres on X. Widening the platform from 450 to 700 without moving the
-- 630-stud spacing left every pair of neighbouring zones overlapping by 70 studs of floor -- and
-- ~400 studs once the rampart and the two rows of backdrop mesas behind each wall are counted, so
-- the next zone's (pass-through) mesas stood on this zone's platform with creatures spawning
-- inside them. Spacing must stay clear of PLATFORM_WIDTH + 2 * (30 + mesa depth); it is 1900 now.
--
-- The width then went 700 -> 900, because once the spacing was right there was room for it. Only X
-- moved: the street runs down Z and every piece of furniture on it (the arch, the fence, the lamps,
-- the benches, the egg plaza) is placed at a FIXED Z, so a deeper platform would leave the street
-- ending short of the wall. A wider one just puts more ground either side of it -- which is where
-- the creatures, the biome props and the landmark live.
-- WIDENING ON X IS FREE; DEEPENING ON Z IS NOT. The street runs down Z and every piece of
-- furniture on it -- arch, fence, lamps, bunting, planters, benches, arrival sign, landmark -- sits
-- at a hand-written Z, so a deeper platform leaves the whole village stopping short of the wall
-- with a field of nothing behind it. Every one of those numbers was multiplied by 1150/860 = 1.337
-- when this went 860 -> 1150, along with ARRIVAL_Z, BOSS_Z, ARRIVAL_CLEAR and DECO_SPREAD_Z, and
-- with BossService.GATE_APPROACH_Z and CreatureService's Z keep-out in the two files that share
-- this geometry. If it moves again, they all move again.
local PLATFORM_DEPTH = 1150
local PLATFORM_WIDTH = 1250
-- Raised from 140 to make room for the taller gateway below: the old portal's cap topped out at
-- 138.5 and had nowhere left to grow. The rampart spires (150-205) still break the line, which is
-- what they are for.
local WALL_HEIGHT = 180
local WALL_THICK = 4
local PORTAL_GAP = 100

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
	TimeRift = Enum.Material.Neon,
	AntimatterZone = Enum.Material.Slate,
	DreamDimension = Enum.Material.Foil,
	MirrorUniverse = Enum.Material.Glass,
	VoidExpanse = Enum.Material.Slate,
	CelestialThrone = Enum.Material.Neon,
	Singularity = Enum.Material.Foil,
	AbsolutePlane = Enum.Material.Neon,
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

-- While this is set, every part newPart makes is placed *through* it instead of straight into
-- world space, so a builder written for one spot and one orientation can be re-used anywhere.
-- The portal gateway is written entirely in the plane x = wallX with +X pointing at the zone
-- interior; handing it a frame is what lets the same 170 lines stand a gate in a Z wall without
-- re-deriving a single coordinate. spinForever transforms its base the same way, so tweened
-- parts stay in step with the parts they were built from.
local ACTIVE_FRAME = nil

-- WHICH ZONE IS BEING BUILT RIGHT NOW, for the two builders that need a mesh keyed by zone and are
-- handed everything except the zone. Set by the zone loop around the decoration builder; read by
-- addMeshProps and by addLandmark.
--
-- DECLARED UP HERE ON PURPOSE. addLandmark is written ~800 lines above the mesh-prop section where
-- this was first declared, and Lua binds an upvalue where the function is WRITTEN -- so from down
-- there it resolved to a nil global and every landmark silently fell back to its block style with
-- nothing in the log. Same trap, same fix, as the `addLight, scatterPoint` forward declarations.
local ACTIVE_ZONE_KEY = nil

-- ===== SHADOWS ARE DECIDED BY SIZE, IN ONE PLACE =====
--
-- `CastShadow = false` appears at **104 call sites** in this file and `CastShadow = true` at none:
-- the world cast no shadows at all, on purpose, for draw cost. That is the single biggest reason
-- the ground reads as a flat coloured plane -- a shadow is what plants an object ON a surface, and
-- without one every prop hovers over its own footprint. Measured in Forest: 2,430 of 3,904 parts
-- had it off, and **537 of those were big** (volume > 400) -- the stall deck, the barrels, the
-- crates, the signs, exactly the things whose shadow the eye looks for.
--
-- Turning it on wholesale is the wrong answer at 83,000 parts, and turning it on at 104 call sites
-- by hand is 104 chances to disagree. So the decision moves HERE and is made from the part's own
-- dimensions, which is a fact the call site does not have to remember:
--
--   long  >= 3.5   a thing, not a pebble. Below this the shadow is smaller than the softness.
--   short >= 0.5   NOT a decal. Ground rings, painted patches and water planes are flat by design;
--                  their shadow lands inside themselves and is pure cost.
--   vol   <= 200k   NOT the backdrop. A 49x186x99 mesa's shadow is a dark band across a whole
--                  district, and it stands outside the play area anyway.
--
-- Neon and anything half-transparent are skipped: a glow that casts a hard shadow reads as a solid
-- object pretending to be light.
--
-- MEASURED, not assumed: this rule turns on 1,367 parts per zone and leaves ~2,500 off. Verified by
-- eye at ground level -- the fence, the lamp posts and the zone sign all plant properly -- and the
-- wide shot is unchanged, because Roblox stops drawing shadows past its own distance limit long
-- before the far wall.
local SHADOW_MIN_LONG = 3.5
local SHADOW_MIN_SHORT = 0.5
local SHADOW_MAX_VOL = 200000

-- ===== WHAT IS SOLID, AND WHY THIS LIST IS SHORT =====
--
-- `CanCollide = false` appears at 418 sites in this file, and the obvious reading -- that the world
-- is full of props you can walk through by accident -- is WRONG. Auditing them against the running
-- world (ray and box queries against the engine, not a read of the source) put almost all of them
-- in one of three defensible groups:
--
--   * backed by something else that IS solid -- `CliffFace` and `CliffRubble` sit against
--     `CliffJut` / `CliffBlock` / `TerraceTop`, `PoolStone` against `PoolBed`. The drawn rock is
--     scenery on a collision hull, which is the right way round.
--   * deliberate, with the reason already written down -- the `EggShell` is a Block wearing a
--     sphere mesh, so its collision is the BOX and its corners stick out at head height; and the
--     street fence is decoration rather than a pen, which is why the player can leave the road.
--   * correctly intangible -- grass tufts, flowers, mushrooms, coins, waterfall spray.
--
-- What was genuinely wrong is the rocks. A `GroundRock` is a 12-stud boulder standing on open
-- ground with nothing behind it, and you walk straight through. Same for scree, mounds and the well.
-- That is exactly the row's own wording -- "rocks and walls stop the player" -- and it is the whole
-- of the real defect, so this list is deliberately short rather than a sweep.
--
-- The street furniture joins it because walking through a bench reads as the same bug even though
-- nobody would call a bench a wall.
--
-- CHECKED FIRST: none of these sits on the route. The path corridor is 30 studs wide and the
-- closest of any of them to the centre line is 54 studs, so making them solid blocks nothing.
--
-- ===== SECOND PASS, 2026-08-11: "you can walk through half the objects" =====
--
-- Re-run the same way the first audit was done -- `GetPartBoundsInBox` against the LIVE world for
-- every prop name in Forest that had no solid part at all, asking the engine whether anything solid
-- shared its volume. That put 60-odd names in the "backed by solid" column exactly as the note
-- above claims (every cliff skin, the waterfalls, the banners, the planters, the terrace mushrooms),
-- and left a short list of free-standing physical objects with nothing behind them at all.
--
-- Those are the ones below. Each was also checked against the street: the corridor is 30 wide and
-- the closest of these is 48 studs off the centre line, so none of them blocks the route -- the same
-- check the first pass documents.
--
-- NOT added, deliberately: the flowers, pennants, bunting, runes, glints and the loose statue
-- details (Leg, Paw, Eye, Horn, Wing) are correctly intangible; `BackdropMesa` is 196-stud
-- background scenery nobody can reach; and the portal's high stonework sits 138-218 studs up.
local SOLID_PROPS = {
	GroundRock = true, ValleyRock = true, ValleyScree = true, Mound = true,
	PoolStone = true, WellStone = true, WellPost = true,
	BenchSeat = true, BenchLeg = true,
	LampPost = true, LampFoot = true, GlowPost = true,
	-- a log lying across the ground, and two braziers the size of a player -- the three things in
	-- the world most obviously solid to the eye and most obviously not to the feet
	FallenLog = true, IdolBrazier = true, GuardianBrazier = true,
	-- the sibling of GlowPost, which has been solid since 10.13; they are the same object with two
	-- names and only one of them stopped anybody
	GlintPost = true,
	-- ground mushrooms. The TERRACE ones are already backed by their shelf and are left alone.
	MushroomCap = true, MushroomStem = true,
	-- "a player who walks through a crate stack is being told the world is a painting" -- the note
	-- over CrateStack, which was solid while the loose crates beside it were not
	StallCrate = true,
}

local function shouldCastShadow(p)
	if p.Transparency >= 0.5 or p.Material == Enum.Material.Neon then
		return false
	end
	local s = p.Size
	local long = math.max(s.X, s.Y, s.Z)
	local short = math.min(s.X, s.Y, s.Z)
	return long >= SHADOW_MIN_LONG
		and short >= SHADOW_MIN_SHORT
		and (s.X * s.Y * s.Z) <= SHADOW_MAX_VOL
end

local function newPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	if ACTIVE_FRAME then
		-- after the props loop on purpose: Position / Orientation / CFrame have all been applied
		-- by now, whichever of them the caller used
		p.CFrame = ACTIVE_FRAME * p.CFrame
	end
	-- LAST, and deliberately overriding the caller. The 104 `CastShadow = false` props in this file
	-- all predate the rule above and none of them is a considered decision about *that* part -- they
	-- are one blanket policy typed out 104 times. Leaving them to win would mean the rule only
	-- applied to parts nobody had gotten round to.
	p.CastShadow = shouldCastShadow(p)
	-- ...and the same shape of decision for collision (10.13), but from a NAME rather than a size.
	-- Shadows are a property of how big a thing is; solidity is a property of what it IS. A bush and
	-- a boulder are the same size and only one of them should stop you, so no measurement can decide
	-- this and the list above has to be explicit.
	if SOLID_PROPS[p.Name] then
		p.CanCollide = true
	end
	return p
end

-- SEATS A CLONED MODEL ON THE GROUND, whatever its author did with its pivot.
-- Everything in ServerStorage.Models was made by a different hand and their pivots are in
-- different places -- some centred, some at the base -- so the usual
-- `PivotTo(CFrame.new(x, geom.Size.Y / 2, z))` only lands correctly for the ones that happen to be
-- centred, and it guesses the height off ONE CHILD PART of a multi-part model on top of that. The
-- Forest trees were neither: they hovered 8 to 15 studs over the grass.
-- Measure instead of guessing. Put it down at y = 0, read where the bounding box actually ended
-- up, and drop it by exactly that much. `sink` buries it a little for props that should look
-- half-embedded rather than placed.
local function seatModel(inst, x, z, yaw, sink)
	inst:PivotTo(CFrame.new(x, 0, z) * CFrame.Angles(0, yaw or 0, 0))
	local cf, size = inst:GetBoundingBox()
	local bottom = cf.Position.Y - size.Y / 2
	inst:PivotTo(inst:GetPivot() + Vector3.new(0, -bottom - (sink or 0), 0))
	return inst
end

-- Forward-declared. Both are defined in the shared-decoration section far below, but the portal,
-- cliff, titan and prop builders are all written above it, and Lua binds an upvalue where the
-- function is *written* rather than where it runs -- without these names in scope up here every
-- call would silently resolve to a nil global and blow up at world-build time.
local addLight, scatterPoint

-- Same reason, for the soft-prop vocabulary (knobs, scallops, bunting, planters). They are written
-- down in the village section beside the structures that use them most, but addZoneProps -- which
-- is written above it -- dresses the scattered crates and banners out of the same set.
local addKnob, addScallops, addBunting, addPlanter, candy

-- Every name board in the world -- the gate signs, the two direction signs on the walkway, the
-- landmark under the arch, the shop titles and the stall odds -- is one of these.
--
-- It used to be a single flat TextLabel: 35% transparent near-black, white Gotham, one 12px corner.
-- Floating over a bright zone that reads as a chat bubble somebody forgot to delete, and it is the
-- reason the zone names looked worse than the props they were standing next to.
--
-- The rebuild is the sticker shape the rest of the game uses -- ink outline, cream rim, coloured
-- face, gloss, hard shadow, outlined text -- with ONE rule behind every dimension:
--
--   *every layer is sized in SCALE, never in pixels.*
--
-- These billboards are sized in studs (UDim2.new(16, 0, 5.5, 0)), so their pixel size changes with
-- distance. A 4px UIStroke or a 12px UICorner is a hairline up close and a fat crayon border from
-- across the platform. Nested Frames at fractional sizes hold their proportions at every range,
-- which is why the border here is three stacked rounded rectangles rather than a stroke.
--
-- opts (all optional): { color = Color3 face colour, textColor = Color3, bob = false }
local SIGN_INK = Color3.fromRGB(26, 18, 36)
local SIGN_RIM = Color3.fromRGB(255, 247, 230)
local SIGN_FACE = Color3.fromRGB(74, 62, 96)
-- Same probe UITheme uses: FredokaOne is the game's display face but it does not exist on every
-- Studio build, and an unknown Enum.Font would be a hard error at world-build time.
local SIGN_FONT = (function()
	local ok, resolved = pcall(function()
		local probe = Instance.new("TextLabel")
		probe.Font = Enum.Font.FredokaOne
		local f = probe.Font
		probe:Destroy()
		return f
	end)
	if ok and typeof(resolved) == "EnumItem" then return resolved end
	return Enum.Font.GothamBlack
end)()

local function makeSign(parentModel, text, cframe, size, opts)
	opts = opts or {}
	local face = opts.color or SIGN_FACE

	local signPart = newPart({
		Name = "SignPart",
		Size = Vector3.new(1, 1, 1),
		CFrame = cframe,
		Transparency = 1,
		CanCollide = false,
		Parent = parentModel,
	})

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Sign"
	billboard.Size = size or UDim2.new(0, 260, 0, 70)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = false
	-- Half the late zones are lit almost to black. A light-influenced board goes unreadable exactly
	-- where the player most needs to be told which way the exit is.
	billboard.LightInfluence = 0
	-- A SHOP-SIZED BOARD NEEDS SHOP-SIZED REACH. 160 studs is right for a direction sign you
	-- read while walking past it; it is wrong for the board over a shop, which is the one thing
	-- in the village a player is supposed to spot from the far end of the street and walk TO.
	-- At 160 the shop board simply was not drawn from anywhere you would notice the shop from.
	billboard.MaxDistance = opts.maxDistance or 160
	billboard.Parent = signPart

	local RADIUS = UDim.new(0.24, 0)

	local function plate(parent, name, color, inset, dy, z)
		local f = Instance.new("Frame")
		f.Name = name
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.new(0.5, 0, 0.5 + (dy or 0), 0)
		f.Size = UDim2.new(1 - inset * 2, 0, 1 - inset * 2 * 2.6, 0)
		f.ZIndex = z
		local c = Instance.new("UICorner")
		c.CornerRadius = RADIUS
		c.Parent = f
		f.Parent = parent
		return f
	end

	-- hard shadow, ink outline, cream rim, coloured face -- four rectangles, no strokes
	plate(billboard, "Shadow", Color3.fromRGB(16, 10, 24), 0.012, 0.05, 1).BackgroundTransparency = 0.25
	plate(billboard, "Outline", SIGN_INK, 0, 0, 2)
	local rim = plate(billboard, "Rim", SIGN_RIM, 0.022, 0, 3)
	local body = plate(rim, "Face", face, 0.03, 0, 4)

	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, face:Lerp(Color3.new(1, 1, 1), 0.34)),
		ColorSequenceKeypoint.new(0.55, face),
		ColorSequenceKeypoint.new(1, face:Lerp(Color3.new(0, 0, 0), 0.36)),
	})
	grad.Parent = body

	-- the sheen: a rounded strip across the top third. Same invariant as UITheme -- it never gets
	-- close to opaque and it never renders above the text.
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.BackgroundColor3 = Color3.new(1, 1, 1)
	gloss.BackgroundTransparency = 0.8
	gloss.BorderSizePixel = 0
	gloss.Position = UDim2.new(0.5, 0, 0.06, 0)
	gloss.AnchorPoint = Vector2.new(0.5, 0)
	gloss.Size = UDim2.new(0.88, 0, 0.3, 0)
	gloss.ZIndex = 5
	local glossCorner = Instance.new("UICorner")
	glossCorner.CornerRadius = UDim.new(1, 0)
	glossCorner.Parent = gloss
	gloss.Parent = body

	local label = Instance.new("TextLabel")
	label.Name = "TextLabel"
	label.BackgroundTransparency = 1
	-- inset in SCALE so the word can never touch the rim, whatever the board's aspect ratio is.
	-- The old sign ran its text to the very edge of the plate, which is what made "Desert" look
	-- like it had been cut off by the frame it was sitting in.
	label.Size = UDim2.new(0.88, 0, 0.66, 0)
	label.Position = UDim2.new(0.5, 0, 0.5, 0)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Font = SIGN_FONT
	label.TextScaled = true
	label.TextColor3 = opts.textColor or Color3.fromRGB(255, 255, 255)
	label.Text = text
	label.ZIndex = 8
	label.Parent = body

	local textStroke = Instance.new("UIStroke")
	textStroke.Thickness = 2.5
	textStroke.Color = SIGN_INK
	textStroke.LineJoinMode = Enum.LineJoinMode.Round
	textStroke.Parent = label

	return signPart
end

-- Text painted straight onto a prop's own face, for the boards that stand in a fixed direction and
-- so have no use for a billboard's camera-facing. Both broad faces get one, so the board reads from
-- either side of the street. Sized in scale for the same reason makeSign is: a SurfaceGui's canvas
-- is PixelsPerStud x the part, and every fixed offset drifts the moment the board changes size.
-- opts (all optional): { maxDistance = studs, pixelsPerStud = n }. The two zone-name boards need
-- both: they are the labels a player reads from the middle of the platform to know where they are
-- and which way out is, and a board four times the size of a direction sign does not want four
-- times the canvas resolution to go with it.
local function addPlankText(part, text, accent, opts)
	opts = opts or {}
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "PlankText"
		gui.Face = face
		gui.LightInfluence = 0 -- half the late zones are lit almost to black
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = opts.pixelsPerStud or 32
		gui.MaxDistance = opts.maxDistance or 240
		gui.Parent = part

		-- cream rim, ink panel: the same two-shell moulding the HUD tiles use, so a board on the
		-- street and a button on the screen read as the same set of objects. Both are sized in scale
		-- rather than pixels -- a SurfaceGui's canvas is PixelsPerStud x the part, so a fixed-pixel
		-- inset would be a different thickness on every board that is not exactly this size.
		local rim = Instance.new("Frame")
		rim.Name = "Rim"
		rim.AnchorPoint = Vector2.new(0.5, 0.5)
		rim.Position = UDim2.new(0.5, 0, 0.5, 0)
		rim.Size = UDim2.new(0.92, 0, 0.74, 0)
		rim.BackgroundColor3 = SIGN_RIM
		rim.BorderSizePixel = 0
		local rimCorner = Instance.new("UICorner")
		rimCorner.CornerRadius = UDim.new(0.28, 0)
		rimCorner.Parent = rim
		rim.Parent = gui

		local plate = Instance.new("Frame")
		plate.Name = "Plate"
		plate.AnchorPoint = Vector2.new(0.5, 0.5)
		plate.Position = UDim2.new(0.5, 0, 0.5, 0)
		plate.Size = UDim2.new(0.94, 0, 0.9, 0)
		-- a warm dark brown rather than the flat near-black the old floating label used: it reads as
		-- paint on the plank it is on, which is the whole point of moving the text onto the board
		plate.BackgroundColor3 = SIGN_INK:Lerp(Color3.fromRGB(96, 60, 40), 0.34)
		plate.BorderSizePixel = 0
		local plateCorner = Instance.new("UICorner")
		plateCorner.CornerRadius = UDim.new(0.26, 0)
		plateCorner.Parent = plate
		plate.Parent = rim

		-- the accent bar under the word: one stripe in the destination's own colour, which is what
		-- lets a player match the board to the gate it points at without reading it
		local strip = Instance.new("Frame")
		strip.Name = "Strip"
		strip.AnchorPoint = Vector2.new(0.5, 1)
		strip.Position = UDim2.new(0.5, 0, 0.93, 0)
		strip.Size = UDim2.new(0.68, 0, 0.1, 0)
		strip.BackgroundColor3 = accent or SIGN_RIM
		strip.BorderSizePixel = 0
		local stripCorner = Instance.new("UICorner")
		stripCorner.CornerRadius = UDim.new(1, 0)
		stripCorner.Parent = strip
		strip.Parent = plate

		local label = Instance.new("TextLabel")
		label.Name = "TextLabel"
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.new(0.5, 0, 0.44, 0)
		label.Size = UDim2.new(0.86, 0, 0.6, 0)
		label.Font = SIGN_FONT
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 250, 238)
		label.Text = text
		label.Parent = plate
	end
end

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

-- Raw zone accents are muted (Forest's is a dark green) and read as dead paint on a Neon part,
-- so anything meant to actually glow gets the accent pushed up to full saturation first.
local function vivid(c)
	local k = math.min(1 / math.max(c.R, c.G, c.B, 0.001), 3.2)
	return Color3.new(math.min(1, c.R * k), math.min(1, c.G * k), math.min(1, c.B * k))
end

-- Endless motion with no per-frame Lua at all. A repeating tween jumps back to its start value
-- every cycle, which is invisible as long as the tween covers exactly one step of the
-- arrangement's rotational symmetry -- so the blades are always built as a symmetric set and
-- spun by exactly one step of it.
local function spinForever(part, base, stepDeg, seconds)
	-- the part itself was already placed through ACTIVE_FRAME by newPart, so its tween goal has
	-- to go through the same frame or the first tick would teleport it back to world space
	if ACTIVE_FRAME then base = ACTIVE_FRAME * base end
	TweenService:Create(part, TweenInfo.new(seconds, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
		CFrame = base * CFrame.Angles(math.rad(stepDeg), 0, 0),
	}):Play()
end

local function pulseForever(part, to, seconds)
	TweenService:Create(part, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Transparency = to,
	}):Play()
end

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
	local previous = ACTIVE_FRAME
	ACTIVE_FRAME = CFrame.new(cx, 0, wallZ) * CFrame.Angles(0, math.rad(wallZ > 0 and 90 or -90), 0)
	buildPortal(model, 0, target, 1)
	ACTIVE_FRAME = previous
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

-- Rock is the zone's own ground colour pulled toward white in three steps, so a Forest cliff comes
-- out pale green and a Mars cliff pale rust without one hand-picked palette anywhere.
local function stoneTones(zone)
	local g = zone.groundColor
	-- cosmic zones ship a near-black ground; lifting those to a readable stone needs a much
	-- bigger step toward white than a Desert's already-bright sand does
	local lum = g.R * 0.3 + g.G * 0.59 + g.B * 0.11
	-- A near-black ground (Volcano, Black Hole, the void zones) is useless as a rock colour: lift it
	-- toward white and you get flat grey cliffs in a zone that should be glowing orange. Mix the
	-- accent in first -- that is the colour the zone is actually about -- and lift the result.
	local base = lum < 0.28 and g:Lerp(zone.accentColor, 0.62) or g

	-- ...AND THE SAME IS TRUE AT THE OTHER END, WHICH NOTHING HANDLED.
	--
	-- The Absolute Plane's ground is rgb(255,255,255). Lifting white toward white returns white, so
	-- all three tones came back identical to the floor -- measured distance 0.000 -- and the cliffs,
	-- their caps, the lips and the backdrop mesas were literally the same colour as the ground they
	-- stood on. Seventy-one percent of the final zone's surface was within a rounding error of pure
	-- white: the reward for twenty stages of climbing was a blank field with no silhouette in it.
	--
	-- Mirror of the dark rule: mix the accent in to get a colour the zone is actually about, then
	-- step DOWN toward black instead of up toward white, so the shading still separates the three.
	local pale = lum > 0.78
	if pale then
		base = g:Lerp(zone.accentColor, 0.5):Lerp(Color3.new(0, 0, 0), 0.28)
	end

	-- ROCK IS ROCK-COLOURED. THE BIOME IS A TINT ON IT, NOT THE WHOLE OF IT.
	--
	-- Everything above derives the cliff colour from the zone's GROUND, so Forest's cliffs came out
	-- rgb(88,149,88) -- solid green. At 24 x 68 x 60 studs a block that colour does not read as a
	-- rock face at all; it reads as a stacked green slab, which is exactly what the terraces were
	-- reported as looking like. No amount of mesh cladding fixes a colour that is wrong underneath.
	--
	-- 58% toward a warm neutral stone keeps enough of the biome to tell Forest from Mars across the
	-- map -- which is what the note below is protecting -- while putting the cliffs back in the
	-- family of colours actual stone comes in.
	--
	-- The two special cases are deliberately left ALONE and this is why: the dark path (Volcano,
	-- Black Hole, the void zones) has already mixed the accent in to get glowing lava rock rather
	-- than flat grey, and the pale path (Absolute Plane) exists because lifting white toward white
	-- returned white and left 71% of that zone with no silhouette. Greying either of them out would
	-- undo a fix that is documented directly above.
	if not pale and lum >= 0.28 then
		base = base:Lerp(Color3.fromRGB(138, 132, 120), 0.58)
	end

	-- The three steps stay small on purpose. An earlier pass lerped 30/46/62% toward white and
	-- every zone came out the same chalky pastel: the cliffs stopped reading as that biome's rock
	-- and the platform lost its colour identity from a distance.
	if pale then
		return {
			base:Lerp(Color3.new(0, 0, 0), 0.06),
			base:Lerp(Color3.new(1, 1, 1), 0.14),
			base:Lerp(Color3.new(1, 1, 1), 0.30),
		}, base:Lerp(Color3.new(0, 0, 0), 0.42)
	end
	return {
		base:Lerp(Color3.new(1, 1, 1), 0.08),
		base:Lerp(Color3.new(1, 1, 1), 0.22),
		base:Lerp(Color3.new(1, 1, 1), 0.38),
	}, base:Lerp(Color3.new(0, 0, 0), 0.42)
end

-- One course of overlapping boulders standing against a boundary wall. `axis` is the axis the wall
-- runs along, `fixed` the wall's coordinate on the other axis, `inward` which way the zone is.
-- `skipHalf` keeps a stretch centred on 0 clear so a rampart can never bury a portal gateway.
local function addRockRampart(model, zone, axis, fixed, center, halfLen, inward, skipHalf)
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
		local off = inward * (d / 2 - 1)
		local size = (axis == "z") and Vector3.new(d, h, w) or Vector3.new(w, h, d)
		local capSize = (axis == "z") and Vector3.new(d + 4, 7, w + 5) or Vector3.new(w + 5, 7, d + 4)
		local px = (axis == "z") and (fixed + off) or t
		local pz = (axis == "z") and t or (fixed + off)
		local yaw = math.random(-13, 13)
		local orient = Vector3.new(math.random(-3, 3), yaw, math.random(-3, 3))
		newPart({ Name = "CliffBlock", Size = size, Orientation = orient, Position = Vector3.new(px, h / 2 - 4, pz), Color = tones[math.random(1, 3)], Material = mat, Parent = model })
		-- a paler cap so the top edge catches light instead of dying into the sky
		newPart({ Name = "CliffCap", Size = capSize, Orientation = orient, Position = Vector3.new(px, h - 7, pz), Color = tones[3], Material = mat, CanCollide = false, Parent = model })

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
			clad:ScaleTo(math.min((h * 0.94) / math.max(raw.Y, 1), (w + 14) / math.max(raw.X, raw.Z, 1)))
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
		end
		-- a boulder at the foot so the rampart meets the ground in rubble, not a clean seam
		if math.random(1, 2) == 1 then
			local s = math.random(9, 19)
			newPart({ Name = "CliffRubble", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 0.8, s * 1.1), Orientation = Vector3.new(0, math.random(0, 360), 0), Position = Vector3.new(px + (axis == "z" and inward * math.random(12, 22) or math.random(-8, 8)), s * 0.3, pz + (axis == "z" and math.random(-8, 8) or inward * math.random(12, 22))), Color = tones[math.random(1, 2)], Material = mat, CanCollide = false, Parent = model })
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
-- Ground already claimed by something big, in WORLD coordinates. See the longer note further down,
-- beside scatterPoint, for what this is for. Declared here rather than there because the props that
-- register with it are built from this point in the file onwards.
-- WHERE THE SHOP STANDS, down the west side of the street.
--
-- It was 150. At the kiosk's size that put its far corner inside the Ocean shipwreck, which is
-- fixed biome geography and consults no reservation table at all -- the one class of collision
-- scatterPoint can never solve. 175 clears the wreck by 15 studs and costs nothing: it is still
-- the same distance off the walkway, only further up it.
--
-- SHOP_SCALE is declared much further down, next to addStall, and cannot be used up here.
local SHOP_Z = 175
local scatterBlocks = {}
local function reserveScatter(x, z, radius)
	scatterBlocks[#scatterBlocks + 1] = { x = x, z = z, r = radius }
end

local function addGroundDetail(model, zone, cx)
	-- FIRST THING BUILT ON THE ZONE'S GROUND, so this is where the reservation table starts.
	--
	-- It used to be cleared inside buildBiomeBase, which the zone loop does not reach until after
	-- the patches, the crates, the coins and the whole village are already down -- so the idols
	-- placed in there chose their ground with an empty table and dropped 150-stud plinths on top of
	-- everything. Cleared here instead, which is the scope the table actually belongs to.
	table.clear(scatterBlocks)

	-- AND THE VILLAGE GOES IN IMMEDIATELY, before one crate is placed. These coordinates are the
	-- village pass's own, copied from the calls that place them; the shop's radius is derived from
	-- SHOP_SCALE so it cannot fall behind the geometry.
	reserveScatter(cx - 150, SHOP_Z, 114)  -- the kiosk, its forecourt and pylons
	reserveScatter(cx + 150, -168, 46)                      -- the well
	reserveScatter(cx, 426, 60)                             -- the zone name board and its battens
	reserveScatter(cx - 104, 310, 22)                       -- the arrival sign post and its lamp

	local g = zone.groundColor
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
			newPart({ Name = "CrateLid", Size = Vector3.new(sz + 0.9, 1.1, sz + 0.9), CFrame = at * CFrame.new(0, sz / 2, 0), Color = VILLAGE_CREAM, Material = Enum.Material.WoodPlanks, CanCollide = false, Parent = model })
			newPart({ Name = "CrateBatten", Size = Vector3.new(sz * 1.35, 1.2, 0.5), CFrame = at * CFrame.new(0, 0, sz / 2 + 0.1) * CFrame.Angles(0, 0, math.rad(38)), Color = woodDark, Material = Enum.Material.Wood, CanCollide = false, Parent = model })
			-- one corner post, on the face the batten crosses. The second was on the back edge of a
			-- box you can only see one side of.
			newPart({ Name = "CrateCorner", Size = Vector3.new(1.2, sz, 1.2), CFrame = at * CFrame.new(-sz / 2, 0, sz / 2), Color = woodDark, Material = Enum.Material.Wood, CanCollide = false, Parent = model })
			cy += sz
			if s == stack then
				newPart({ Name = "CrateFruit", Shape = Enum.PartType.Ball, Size = Vector3.new(3.4, 3, 3.4), CFrame = at * CFrame.new(0, sz / 2 + 1.8, 0), Color = candy(c), Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = model })
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
		local cloth, trim = candy(b), candy(b + 3)

		newPart({ Name = "BannerPole", Size = Vector3.new(1.6, h, 1.6), CFrame = at * CFrame.new(0, h / 2, 0), Color = woodDark, Material = Enum.Material.Wood, Parent = model })
		newPart({ Name = "BannerCrossbar", Size = Vector3.new(15, 1.1, 1.1), CFrame = at * CFrame.new(0, h - 1.5, 0), Color = woodDark, Material = Enum.Material.Wood, CanCollide = false, Parent = model })
		for _, sx in ipairs({ -1, 1 }) do
			addKnob(model, (at * CFrame.new(sx * 7.5, h - 1.5, 0)).Position, 1.9, VILLAGE_CREAM)
		end

		local clothH = h * 0.42
		local clothY = h - 1.5 - clothH / 2 - 1
		newPart({ Name = "BannerCloth", Size = Vector3.new(13, clothH, 0.5), CFrame = at * CFrame.new(0, clothY, 0), Color = cloth, Material = Enum.Material.Fabric, CanCollide = false, Parent = model })
		-- two stripes across it, so the sheet has structure instead of being one flat fill
		for _, dy in ipairs({ 0.22, -0.22 }) do
			newPart({ Name = "BannerStripe", Size = Vector3.new(13.4, clothH * 0.13, 0.7), CFrame = at * CFrame.new(0, clothY + clothH * dy, 0), Color = trim, Material = Enum.Material.Fabric, CanCollide = false, CastShadow = false, Parent = model })
		end
		newPart({ Name = "BannerEmblem", Shape = Enum.PartType.Ball, Size = Vector3.new(4.6, 4.6, 1.2), CFrame = at * CFrame.new(0, clothY, -0.5), Color = VILLAGE_CREAM, Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = model })
		addScallops(model, at, 12, 4, clothY - clothH / 2, 0, trim, cloth, 3.4)

		local knob = addKnob(model, (at * CFrame.new(0, h + 1.4, 0)).Position, 3.4, accent, Enum.Material.Neon)
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
	local stone = zone.groundColor:Lerp(Color3.fromRGB(232, 228, 220), 0.62)
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
-- ===== THE VILLAGE IS BUILT OF DIFFERENT STUFF IN EVERY ZONE =====
--
-- These four values dress EVERY hand-placed structure in a zone: the street fence, the welcome
-- arch, the name board, the benches, the planters, the well, the stalls and the shop. They were
-- four constants, so all twenty zones were furnished in the same brown pine and the same cream
-- paint -- and that is most of what "every zone is the same template" actually is. The layout was
-- never the loudest part; the MATERIAL was. A pine picket fence with cream caps on the Moon, in
-- the Void and inside a black hole is the same village dropped twenty times.
--
-- They are `local` and REASSIGNED per zone rather than threaded through as parameters: fifty-nine
-- lines across a dozen builders read them, and none of those builders is handed the zone. The
-- write happens in one place -- `applyVillageStyle`, called from the zone loop right where
-- ACTIVE_ZONE_KEY is set -- so the mutation has exactly one owner and one lifetime.
--
-- Material matters as much as colour here: Wood and WoodPlanks are what say "cottage", and a
-- zone whose village is cut from Basalt, Ice, Marble or Neon reads as a different civilisation
-- without a single part moving.
local VILLAGE_WOOD = Color3.fromRGB(154, 108, 62)
local VILLAGE_WOOD_DARK = Color3.fromRGB(101, 69, 40)
local VILLAGE_CLOTH = Color3.fromRGB(240, 235, 222)
local VILLAGE_CREAM = Color3.fromRGB(252, 244, 226)

-- The defaults above are the Forest set, kept as the fallback so a zone with no entry here builds
-- exactly as it always did.
local VILLAGE_DEFAULT = {
	wood = VILLAGE_WOOD, dark = VILLAGE_WOOD_DARK,
	cloth = VILLAGE_CLOTH, cream = VILLAGE_CREAM,
}

-- ===== THE RULE IS CONTRAST WITH THE GROUND, NOT AGREEMENT WITH THE THEME =====
--
-- The obvious way to write this table is to theme each village to its biome: charred timber in the
-- Volcano, pale stone on the Moon, chrome in the Mirror Universe. That was the first cut and it is
-- WRONG, and the Moon proved it in one screenshot -- a silver-grey fence, arch, benches and name
-- board standing on a 170-grey lunar floor under a white sky simply vanished. The zone came back
-- as a white field with nothing built on it, which is worse than the repeated brown village it
-- replaced: repetition is boring, invisibility is broken.
--
-- The village's job is to be the BUILT thing on the natural ground. So it is picked against the
-- ground's luminance and only then tinted toward the biome:
--
--   ground bright (Desert .78, CelestialThrone .70, Moon .67, MirrorUniverse .60,
--                  AbsolutePlane 1.00) -> DARK village
--   ground dark   (VoidExpanse .02, BlackHole .04, Singularity .06, Multiverse .08,
--                  AntimatterZone .10 ... TimeRift .28) -> BRIGHT village
--   ground mid    (Nebula .35, QuantumRealm .39, Forest .44, Mars .46, Ocean .48) -> either,
--                  chosen for hue contrast instead
--
-- The theme then lives in the HUE and in VILLAGE_MATERIAL below, which is where it can be read
-- without costing legibility: a bone-and-ember village in the Volcano, a charcoal-and-cyan one on
-- the Moon, deep blue and gold on the Celestial Throne.
local VILLAGE_STYLE = {
	-- ---- mid ground: brown timber on green is the original and it works
	Forest         = VILLAGE_DEFAULT,
	Ocean          = { wood = Color3.fromRGB(224, 208, 178), dark = Color3.fromRGB(152, 132, 102), cloth = Color3.fromRGB(250, 244, 226), cream = Color3.fromRGB(252, 250, 240) },
	Mars           = { wood = Color3.fromRGB(232, 214, 182), dark = Color3.fromRGB(160, 140, 108), cloth = Color3.fromRGB(250, 236, 210), cream = Color3.fromRGB(252, 244, 226) },
	Nebula         = { wood = Color3.fromRGB(252, 224, 240), dark = Color3.fromRGB(186, 138, 178), cloth = Color3.fromRGB(150, 240, 236), cream = Color3.fromRGB(252, 240, 250) },
	QuantumRealm   = { wood = Color3.fromRGB(206, 246, 252), dark = Color3.fromRGB(124, 190, 210), cloth = Color3.fromRGB(232, 250, 254), cream = Color3.fromRGB(244, 253, 255) },

	-- ---- BRIGHT ground -> DARK village
	Desert         = { wood = Color3.fromRGB(122, 80, 48),   dark = Color3.fromRGB(74, 48, 28),    cloth = Color3.fromRGB(244, 222, 178), cream = Color3.fromRGB(250, 238, 206) },
	-- charcoal and cyan: a moonbase, not a moon rock
	Moon           = { wood = Color3.fromRGB(72, 76, 92),    dark = Color3.fromRGB(40, 44, 56),    cloth = Color3.fromRGB(150, 226, 250), cream = Color3.fromRGB(198, 232, 248) },
	MirrorUniverse = { wood = Color3.fromRGB(58, 64, 84),    dark = Color3.fromRGB(32, 36, 50),    cloth = Color3.fromRGB(196, 216, 244), cream = Color3.fromRGB(214, 230, 250) },
	-- deep royal blue carrying gold. Gold on gold sand is invisible; gold on navy is a throne room.
	CelestialThrone= { wood = Color3.fromRGB(56, 62, 116),   dark = Color3.fromRGB(32, 36, 74),    cloth = Color3.fromRGB(250, 226, 150), cream = Color3.fromRGB(248, 214, 118) },
	-- the only pure-white ground in the game, so the only truly black village
	AbsolutePlane  = { wood = Color3.fromRGB(44, 40, 58),    dark = Color3.fromRGB(22, 20, 32),    cloth = Color3.fromRGB(196, 150, 246), cream = Color3.fromRGB(126, 112, 168) },

	-- ---- DARK ground -> BRIGHT village
	-- bone and ember. The charred-timber version of this was dark-on-dark and disappeared exactly
	-- the way the Moon did.
	Volcano        = { wood = Color3.fromRGB(214, 190, 178), dark = Color3.fromRGB(150, 124, 114), cloth = Color3.fromRGB(255, 148, 92),  cream = Color3.fromRGB(248, 234, 224) },
	Galaxy         = { wood = Color3.fromRGB(200, 186, 250), dark = Color3.fromRGB(142, 126, 200), cloth = Color3.fromRGB(232, 222, 255), cream = Color3.fromRGB(242, 236, 255) },
	BlackHole      = { wood = Color3.fromRGB(186, 176, 214), dark = Color3.fromRGB(124, 116, 156), cloth = Color3.fromRGB(190, 142, 255), cream = Color3.fromRGB(224, 218, 244) },
	Multiverse     = { wood = Color3.fromRGB(220, 200, 244), dark = Color3.fromRGB(158, 136, 190), cloth = Color3.fromRGB(252, 226, 250), cream = Color3.fromRGB(248, 240, 254) },
	Wormhole       = { wood = Color3.fromRGB(154, 240, 222), dark = Color3.fromRGB(92, 176, 166),  cloth = Color3.fromRGB(224, 252, 244), cream = Color3.fromRGB(236, 253, 248) },
	TimeRift       = { wood = Color3.fromRGB(232, 202, 130), dark = Color3.fromRGB(172, 142, 76),  cloth = Color3.fromRGB(250, 238, 194), cream = Color3.fromRGB(252, 244, 214) },
	AntimatterZone = { wood = Color3.fromRGB(230, 226, 236), dark = Color3.fromRGB(164, 160, 178), cloth = Color3.fromRGB(255, 118, 222), cream = Color3.fromRGB(252, 248, 254) },
	DreamDimension = { wood = Color3.fromRGB(230, 210, 252), dark = Color3.fromRGB(172, 150, 208), cloth = Color3.fromRGB(198, 250, 240), cream = Color3.fromRGB(250, 246, 255) },
	VoidExpanse    = { wood = Color3.fromRGB(158, 154, 190), dark = Color3.fromRGB(102, 98, 134),  cloth = Color3.fromRGB(146, 134, 210), cream = Color3.fromRGB(196, 192, 220) },
	Singularity    = { wood = Color3.fromRGB(166, 188, 240), dark = Color3.fromRGB(102, 124, 182), cloth = Color3.fromRGB(210, 228, 255), cream = Color3.fromRGB(228, 240, 255) },
}

-- Which material the "timber" of a village is actually cut from. Absent = Wood/WoodPlanks, i.e.
-- unchanged. Two entries per zone because the code uses Wood for posts and WoodPlanks for boards
-- and boxes, and swapping only one of them leaves a plank fence with metal legs.
local VILLAGE_MATERIAL = {
	Ocean          = { post = Enum.Material.Slate,     board = Enum.Material.Slate },
	Volcano        = { post = Enum.Material.Basalt,    board = Enum.Material.Basalt },
	Moon           = { post = Enum.Material.Metal,     board = Enum.Material.DiamondPlate },
	Mars           = { post = Enum.Material.Sandstone, board = Enum.Material.Sandstone },
	Galaxy         = { post = Enum.Material.Marble,    board = Enum.Material.Marble },
	BlackHole      = { post = Enum.Material.Slate,     board = Enum.Material.Slate },
	Multiverse     = { post = Enum.Material.Marble,    board = Enum.Material.Marble },
	Nebula         = { post = Enum.Material.Marble,    board = Enum.Material.Marble },
	Wormhole       = { post = Enum.Material.Metal,     board = Enum.Material.DiamondPlate },
	QuantumRealm   = { post = Enum.Material.Glass,     board = Enum.Material.Glass },
	TimeRift       = { post = Enum.Material.Metal,     board = Enum.Material.CorrodedMetal },
	AntimatterZone = { post = Enum.Material.Metal,     board = Enum.Material.DiamondPlate },
	DreamDimension = { post = Enum.Material.Marble,    board = Enum.Material.Marble },
	MirrorUniverse = { post = Enum.Material.Metal,     board = Enum.Material.Metal },
	VoidExpanse    = { post = Enum.Material.Slate,     board = Enum.Material.Slate },
	CelestialThrone= { post = Enum.Material.Marble,    board = Enum.Material.Marble },
	Singularity    = { post = Enum.Material.Metal,     board = Enum.Material.Metal },
	AbsolutePlane  = { post = Enum.Material.Marble,    board = Enum.Material.Marble },
}

-- Live values the builders read. Reassigned by applyVillageStyle, never written anywhere else.
local VILLAGE_POST_MAT = Enum.Material.Wood
local VILLAGE_BOARD_MAT = Enum.Material.WoodPlanks

-- ===== THE OUTLINE TIER, AND WHY IT IS NOT SIMPLY "DARKER" =====
--
-- Measured across 443 street-level props in Forest: **not one** was near-ink. The darkest thing on
-- the whole street was a glow post at value 0.35, and the structural colour every prop hangs off
-- (`VILLAGE_WOOD_DARK`) sat at 0.40. So the world had no outline tier at all -- everything from the
-- fence to the lamp to the bench was a mid-tone against a mid-tone ground, which is exactly what
-- "flat and pastel" is made of. The house style's first rule is the dark contour (see the chunky
-- look notes); the HUD has it, the icons have it, the props did not.
--
-- The seventeen sites that read `VILLAGE_WOOD_DARK` are all skeleton -- lamp foot, post, bracket
-- and roof, fence rail, arch pillar, bench leg, planter rim, sign post and batten. Pushing that one
-- colour is therefore a whole-world outline pass for one line, with no new parts anywhere.
--
-- IT IS A CONTRAST TRIM, NOT A DARK TRIM, and that distinction is what keeps it from repeating the
-- mistake the village palette above already paid for: a silver village on the Moon's pale ground
-- vanished, so villages are picked AGAINST THE GROUND. If the trim were unconditionally dark it
-- would vanish the same way -- on the bright-ground zones the village body is itself dark, and
-- ink-on-ink is invisible.
--
-- The trim contrasts with the THING IT OUTLINES rather than with the background, which is the whole
-- point of an outline and is also why it can be decided here from one colour: a light body gets a
-- near-ink trim, and a body already dark gets a bone one. Either way the prop reads as drawn.
-- THE FLIP POINT IS 0.32, AND 0.42 WAS WRONG -- Forest is the case that proves it. Its wood-dark
-- is a mid brown at value 0.396, which is not "already dark" in any useful sense: it carries an ink
-- trim perfectly well. At 0.42 it took the flip instead and every fence rail, bench leg and planter
-- rim in the starting zone came out CREAM. Below 0.32 are the five genuinely dark bodies (Absolute
-- 0.13, Mirror 0.20, Moon 0.22, Desert and Celestial 0.29) -- the bright-ground zones, which is
-- exactly the set the flip exists for.
--
-- The audit that missed this checked all nineteen palettes in `VILLAGE_STYLE` and passed. Forest is
-- not in that table -- it is `VILLAGE_DEFAULT`, the fallback -- so the one zone every player starts
-- in was the one zone the check did not cover. **A table-driven audit has to include the default.**
local function trimFor(body)
	local h, s, v = Color3.toHSV(body)
	if v > 0.32 then
		-- room to go down: genuine ink, hue kept so oak trims brown and marble trims blue-grey
		return Color3.fromHSV(h, math.min(s * 1.08, 1), math.max(v * 0.34, 0.13))
	end
	-- already dark; going darker would erase it, so the outline goes the other way
	return Color3.fromHSV(h, s * 0.5, math.min(v * 2.5 + 0.12, 0.93))
end

local function applyVillageStyle(key)
	local s = VILLAGE_STYLE[key] or VILLAGE_DEFAULT
	VILLAGE_WOOD = s.wood
	-- `s.dark` is the authored mid-tone shade of the body, and it stays available as that; what the
	-- skeleton wants is a step further than "a bit darker", so it is derived rather than authored --
	-- twenty hand-picked ink colours would be twenty chances for one of them to be wrong.
	VILLAGE_WOOD_DARK = trimFor(s.dark)
	VILLAGE_CLOTH, VILLAGE_CREAM = s.cloth, s.cream
	local m = VILLAGE_MATERIAL[key]
	VILLAGE_POST_MAT = m and m.post or Enum.Material.Wood
	VILLAGE_BOARD_MAT = m and m.board or Enum.Material.WoodPlanks
end

-- The candy palette every soft prop below picks from. Deliberately not derived from the zone
-- accent: the accent already colours the neon, the trim and the lights, and when the bunting and
-- the flowers took it too every zone collapsed into one hue. A fixed sweet-shop set of colours
-- against the biome's own greens and rusts is what reads as *decoration* rather than as more biome.
local CANDY = {
	Color3.fromRGB(255, 128, 158), -- bubblegum
	Color3.fromRGB(255, 206, 92),  -- butter
	Color3.fromRGB(126, 220, 232), -- sky
	Color3.fromRGB(180, 152, 255), -- lilac
	Color3.fromRGB(140, 226, 148), -- mint
	Color3.fromRGB(255, 158, 110), -- peach
}

function candy(i)
	return CANDY[((i - 1) % #CANDY) + 1]
end

-- ---- shared soft-prop vocabulary ----
-- Four shapes that turn a box into a toy: a rounded cap, a scalloped skirt, a pennant string and
-- a planter. Everything on the street is built out of these, which is what makes the street read
-- as one set rather than as a pile of unrelated props.

-- A ball sitting on top of a post. One part, and it is the single biggest difference between a
-- fence that looks like a row of stakes and one that looks drawn.
function addKnob(model, pos, size, color, material)
	return newPart({
		Name = "Knob", Shape = Enum.PartType.Ball,
		Size = Vector3.new(size, size, size), Position = pos,
		Color = color, Material = material or Enum.Material.SmoothPlastic,
		CanCollide = false, CastShadow = false, Parent = model,
	})
end

-- The scalloped skirt hanging off an awning or a roof: a row of half-domes, alternating two
-- colours. Squashed balls rather than real semicircles -- at this chunky scale the silhouette is
-- all that carries, and a ball costs one part where a proper scallop costs three.
function addScallops(model, base, width, count, y, z, colorA, colorB, size)
	size = size or 3.4
	for i = 0, count - 1 do
		local t = count > 1 and (i / (count - 1) - 0.5) or 0
		newPart({
			Name = "Scallop", Shape = Enum.PartType.Ball,
			Size = Vector3.new(size, size * 0.85, size * 0.5),
			CFrame = base * CFrame.new(t * width, y, z),
			Color = (i % 2 == 0) and colorA or colorB,
			Material = Enum.Material.Fabric, CanCollide = false, CastShadow = false, Parent = model,
		})
	end
end

-- A string of triangular pennants between two points. Each flag is a single Wedge, mirrored turn
-- and turn about so the row reads as alternating triangles -- one part per flag, because a
-- properly symmetric pennant costs two and this runs the length of the street on both sides.
-- The line sags: `droop` is how far the middle of the run hangs below its ends.
function addBunting(model, fromPos, toPos, count, droop, seed)
	local span = toPos - fromPos
	local dir = span.Unit
	local yaw = math.atan2(-dir.X, -dir.Z)

	-- the cord itself, in two straight segments meeting at the lowest point: a real catenary is
	-- not worth the parts, and two segments already sell the sag
	local mid = fromPos + span * 0.5 - Vector3.new(0, droop, 0)
	for _, seg in ipairs({ { fromPos, mid }, { mid, toPos } }) do
		local a, b = seg[1], seg[2]
		newPart({
			Name = "BuntingCord", Size = Vector3.new(0.3, 0.3, (b - a).Magnitude),
			CFrame = CFrame.lookAt((a + b) / 2, b),
			Color = VILLAGE_WOOD_DARK, Material = Enum.Material.Fabric,
			CanCollide = false, CastShadow = false, Parent = model,
		})
	end

	for i = 1, count do
		local t = i / (count + 1)
		-- height on whichever of the two cord segments this flag hangs from
		local sag = droop * (1 - math.abs(t - 0.5) * 2)
		local at = fromPos + span * t - Vector3.new(0, sag, 0)
		-- A Wedge is a right triangle standing on its long edge -- apex UP, which is a bunting flag
		-- upside down. Rolling it 180 degrees about Z puts the point at the bottom where it belongs
		-- and keeps the height on Y and the width on Z. (Rolling 90, which is what this did first,
		-- laid every flag flat and the street looked strung with coloured drinking straws.)
		newPart({
			Name = "Pennant", Shape = Enum.PartType.Wedge, Size = Vector3.new(0.26, 4.6, 3.4),
			CFrame = CFrame.new(at - Vector3.new(0, 2.3, 0))
				* CFrame.Angles(0, yaw + (i % 2 == 0 and math.pi or 0), 0)
				* CFrame.Angles(0, 0, math.pi),
			Color = candy(i + (seed or 0)), Material = Enum.Material.Fabric,
			CanCollide = false, CastShadow = false, Parent = model,
		})
	end
end

-- A window box of flowers. Three blooms, each a ball on a stem with a paler centre, in a wooden
-- trough. Placed along the street and in front of the stalls.
-- `scale` is for the shop, which is built several times life size: a natural-size window box in
-- front of a 70-stud stall reads as a dropped matchbox. Every other caller passes three arguments
-- and gets exactly what it always got.
function addPlanter(model, base, seed, scale)
	local s = scale or 1
	newPart({ Name = "PlanterBox", Size = Vector3.new(11, 4, 5.4) * s, CFrame = base * CFrame.new(0, 2 * s, 0), Color = VILLAGE_WOOD, Material = Enum.Material.WoodPlanks, Parent = model })
	newPart({ Name = "PlanterRim", Size = Vector3.new(12, 0.9, 6.2) * s, CFrame = base * CFrame.new(0, 4.2 * s, 0), Color = VILLAGE_WOOD_DARK, Material = Enum.Material.WoodPlanks, CanCollide = false, Parent = model })
	newPart({ Name = "PlanterSoil", Size = Vector3.new(10, 1, 4.6) * s, CFrame = base * CFrame.new(0, 4.4 * s, 0), Color = Color3.fromRGB(88, 62, 44), Material = Enum.Material.Ground, CanCollide = false, Parent = model })
	for i = -1, 1 do
		local bloom = candy(i + 2 + (seed or 0))
		newPart({ Name = "FlowerStem", Size = Vector3.new(0.5, 3.2, 0.5) * s, CFrame = base * CFrame.new(i * 3.4 * s, 6.2 * s, 0), Color = Color3.fromRGB(96, 168, 92), Material = Enum.Material.Grass, CanCollide = false, CastShadow = false, Parent = model })
		newPart({ Name = "FlowerHead", Shape = Enum.PartType.Ball, Size = Vector3.new(3.4, 2.6, 3.4) * s, CFrame = base * CFrame.new(i * 3.4 * s, 8.2 * s, 0), Color = bloom, Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = model })
		newPart({ Name = "FlowerHeart", Shape = Enum.PartType.Ball, Size = Vector3.new(1.5, 1.3, 1.5) * s, CFrame = base * CFrame.new(i * 3.4 * s, 8.7 * s, 0), Color = VILLAGE_CREAM, Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = model })
	end
end

-- A lantern on a post, hung off the +Z side of `base`. Used along the street and beside every
-- structure below: a settlement reads as a settlement mostly by being lit.
-- ===== THE VILLAGE PROP LIBRARY =====
--
-- `ServerStorage.PropMeshes.Vill_<Thing>` -- stall, well, cart, lamp, signpost, barrel, planter,
-- fence, bench, crates, anvil, banner post. Twelve models SHARED by all twenty zones, so they are
-- deliberately biome-neutral: wood, stone, cloth and brass, nothing that ties them to one place.
--
-- The street is the one part of the map a player stands right next to, and it was the last thing
-- still made of primitives -- a cube for a crate, a cylinder for a barrel, stacked slabs for a
-- lamp. Next to a meshed boss walking past, that is what read as unfinished.
--
-- Returns nil when nothing is filed, and every caller keeps its primitive path behind that check,
-- so a missing model is a slightly plainer village and never a broken one.
-- `model` IS A PARAMETER, not an upvalue. It was written without one first time round and Lua
-- resolved it to a nil global, so `clone.Parent = nil` -- every lamp in the game silently vanished:
-- the mesh went nowhere AND the primitive path had already been skipped because the mesh "worked".
-- Nothing errored and nothing was logged; the only evidence was a count of zero on both sides.
local function villMesh(model, name, height, base, yawJitter)
	local lib = ServerStorage:FindFirstChild("PropMeshes")
	local template = lib and lib:FindFirstChild("Vill_" .. name)
	if not template then return nil end
	local clone = template:Clone()
	-- measured BEFORE parenting: GetBoundingBox covers every descendant, so measuring after it is
	-- inside the zone model measures the zone
	local _, raw = clone:GetBoundingBox()
	clone:ScaleTo(height / math.max(raw.Y, 0.1))
	for _, part in ipairs(clone:GetDescendants()) do
		if part:IsA("BasePart") then
			-- generated meshes arrive UNANCHORED; newPart anchors what it makes, nothing anchors these
			part.Anchored = true
			part.CanCollide = false
		end
	end
	clone.Name = "Vill" .. name
	-- ACTIVE_FRAME is what lets a builder written for one spot be re-used anywhere (see newPart);
	-- a mesh placed with a raw CFrame would ignore it and land outside the zone that is being built.
	local frame = ACTIVE_FRAME and (ACTIVE_FRAME * base) or base
	clone.Parent = model
	local pos = frame.Position
	-- seatModel, not PivotTo: these were authored by the generator with their pivots wherever they
	-- landed, and guessing the drop is what once left the Forest trees hovering over the grass.
	seatModel(clone, pos.X, pos.Z, math.atan2(-frame.LookVector.X, -frame.LookVector.Z) + math.rad(yawJitter or 0))
	return clone
end

local function addLamp(model, base, color, h)
	h = h or 21

	-- The mesh lamp carries its own post, bracket, housing and glass, so the whole primitive build
	-- below is skipped -- but NOT the light itself. A PointLight is not geometry and the street is
	-- lit by these; dropping it would leave twenty zones dark at the same moment they got prettier.
	local meshLamp = villMesh(model, "Lamp", h + 4, base)
	if meshLamp then
		local glowPart = meshLamp:FindFirstChildWhichIsA("BasePart", true)
		if glowPart then
			addLight(glowPart, color, 20, 0.9)
		end
		return glowPart
	end
	-- a flared foot, so the post meets the ground in something rather than being pushed into it
	newPart({ Name = "LampFoot", Size = Vector3.new(4.2, 1.6, 4.2), CFrame = base * CFrame.new(0, 0.8, 0), Color = VILLAGE_WOOD_DARK, Material = Enum.Material.Metal, Parent = model })
	newPart({ Name = "LampFootTrim", Size = Vector3.new(3, 0.8, 3), CFrame = base * CFrame.new(0, 2, 0), Color = VILLAGE_CREAM, Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
	newPart({ Name = "LampPost", Size = Vector3.new(1.5, h, 1.5), CFrame = base * CFrame.new(0, h / 2, 0), Color = VILLAGE_WOOD_DARK, Material = Enum.Material.Metal, Parent = model })
	newPart({ Name = "LampBracket", Size = Vector3.new(1, 1, 5), CFrame = base * CFrame.new(0, h - 1.2, 2), Color = VILLAGE_WOOD_DARK, Material = Enum.Material.Metal, CanCollide = false, Parent = model })

	-- The lantern head: a tapered stack instead of one flat plate. Three courses shrinking upward
	-- give the roof a pitch, which is the whole difference between a street lamp and a box on a
	-- stick -- and it gets a knob on top, like everything else out here.
	for i, tier in ipairs({ { 5.6, 1.2 }, { 3.4, 1.1 } }) do
		newPart({ Name = "LampRoof", Size = Vector3.new(tier[1], tier[2], tier[1]), CFrame = base * CFrame.new(0, h - 1.4 + (i - 1) * 1.1, 3.4), Color = i == 1 and VILLAGE_WOOD_DARK or VILLAGE_WOOD, Material = Enum.Material.WoodPlanks, CanCollide = false, Parent = model })
	end
	addKnob(model, (base * CFrame.new(0, h + 1.6, 3.4)).Position, 1.8, color, Enum.Material.Neon)

	local glass = newPart({ Name = "LampGlass", Size = Vector3.new(3.8, 4.8, 3.8), CFrame = base * CFrame.new(0, h - 4, 3.4), Color = color, Material = Enum.Material.Neon, Transparency = 0.35, CanCollide = false, CastShadow = false, Parent = model })
	-- a cream collar under the glass, so the light sits in a housing rather than floating
	newPart({ Name = "LampCollar", Size = Vector3.new(4.4, 0.7, 4.4), CFrame = base * CFrame.new(0, h - 6.6, 3.4), Color = VILLAGE_CREAM, Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
	addLight(glass, color, 20, 0.9)
	return glass
end

-- HOW BIG EVERY SHOP IS BUILT.
--
-- The stall was authored at 30 x 20 x 23 studs back when the player was a one-stud creature. The
-- character now runs 1.0 -> 5.0 through the chain and stands ~30 studs tall at the top of it, so
-- the only building in the village that actually SELLS anything had become a knee-high box you
-- walked straight past -- reported as "I cannot even see the shop". Everything in `addStall` and
-- in the counters `buildZoneShop` puts on it is multiplied by this one number, so the shop grows
-- as a single object and nothing drifts out of proportion with anything else on it: deck, posts,
-- awning, sign board, bottles, the lamps beside it and the planters in front.
--
-- 2.6 puts the awning ridge at ~57 studs and the name board at ~59 -- taller than the welcome
-- arch (36) and the zone name board (55), which is deliberate: the shop should be the tallest
-- thing on the street, because it is the only one worth walking to. Raising it further starts
-- pushing the front lip toward the walkway (see the clearance note at the call site).
local SHOP_SCALE = 2.6

-- A MODERN KIOSK, not a market stall.
--
-- This was a wooden market stall -- striped canvas awning, scalloped valance, crates, a barrel and
-- flower boxes -- and scaling it up just made a big rustic stall. The shop is the one piece of the
-- village that should read as BUILT rather than pitched, so it is now a white panel-and-glass
-- kiosk: a flat cantilevered canopy, a dark stone counter on a bright shell, a glass back wall and
-- zone-accent light strips doing the decorating the bunting and the flowers used to do.
--
-- Every number is still authored at the old stall's scale and multiplied by SHOP_SCALE on the way
-- out through `at` and `vs`, so one constant still moves the whole thing.
--
-- THE PALETTE IS DELIBERATELY NOT THE VILLAGE'S. Two fixed tones -- a near-white panel and a
-- near-black frame -- with the zone accent used only as light. That pair reads against every
-- ground in the strip; a dark modern shell would disappear in Void and Singularity and a cream one
-- would disappear on Moon. See the village contrast note.
--
-- Returns the counter, which is what a caller hangs a ProximityPrompt on.
local function addStall(model, base, accent, title, wares)
	local S = SHOP_SCALE
	local function at(x, y, z) return base * CFrame.new(x * S, y * S, z * S) end
	local function vs(x, y, z) return Vector3.new(x * S, y * S, z * S) end
	local function pt(x, y, z) return (base * CFrame.new(x * S, y * S, z * S)).Position end

	local PANEL = Color3.fromRGB(244, 247, 252)
	local FRAME = Color3.fromRGB(41, 45, 58)
	local FRAME_LITE = Color3.fromRGB(88, 96, 118)
	local GLASS = accent:Lerp(Color3.new(1, 1, 1), 0.5)

	-- one light strip: neon, never collides, never casts, and carries its own PointLight. Every
	-- accent-coloured thing on this building is one of these, which is what keeps the kiosk two
	-- tones plus light instead of a third painted colour.
	local function strip(name, size, cf, bright, range)
		local p = newPart({ Name = name, Size = size, CFrame = cf, Color = accent, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false, Parent = model })
		if bright then addLight(p, accent, range or 22, bright) end
		return p
	end

	-- ===== the plinth the whole thing stands on =====
	newPart({ Name = "StallDeck", Size = vs(32, 2, 22), CFrame = at(0, 1, 0), Color = FRAME, Material = Enum.Material.Metal, Parent = model })
	newPart({ Name = "StallDeckTop", Size = vs(30, 0.7, 20), CFrame = at(0, 2.3, 0), Color = PANEL, Material = Enum.Material.SmoothPlastic, Parent = model })
	-- the light line around the base. A glowing seam at floor level is the single cheapest thing
	-- that separates "modern building" from "big white box".
	strip("StallPlinthLight", vs(32.6, 0.5, 0.6), at(0, 2.1, 11.2))
	strip("StallPlinthLight", vs(32.6, 0.5, 0.6), at(0, 2.1, -11.2))
	for _, sx in ipairs({ -1, 1 }) do
		strip("StallPlinthLight", vs(0.6, 0.5, 22.4), at(sx * 16.2, 2.1, 0))
	end
	-- a step, because the plinth lip is over five studs off the ground at this scale
	newPart({ Name = "StallStep", Size = vs(20, 1.2, 3.6), CFrame = at(0, 0.6, 12.4), Color = FRAME_LITE, Material = Enum.Material.Metal, Parent = model })

	-- ===== frame columns =====
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			newPart({ Name = "StallPost", Size = vs(1.4, 20, 1.4), CFrame = at(sx * 14.6, 12.3, sz * 9.6), Color = FRAME, Material = Enum.Material.Metal, Parent = model })
			strip("StallPostLight", vs(1.7, 0.6, 1.7), at(sx * 14.6, 6, sz * 9.6))
		end
	end

	-- ===== glass back wall, and the stock lit behind it =====
	newPart({ Name = "StallBack", Size = vs(31, 18, 0.9), CFrame = at(0, 12.5, -9.9), Color = FRAME, Material = Enum.Material.Metal, CanCollide = false, Parent = model })
	for i = -1, 1 do
		newPart({ Name = "StallGlass", Size = vs(9, 15, 0.4), CFrame = at(i * 9.7, 12.6, -9.3), Color = GLASS, Material = Enum.Material.Glass, Transparency = 0.55, CanCollide = false, CastShadow = false, Parent = model })
	end
	for _, sx in ipairs({ -1, 1 }) do
		newPart({ Name = "StallMullion", Size = vs(0.8, 16, 1), CFrame = at(sx * 4.85, 12.6, -9.2), Color = PANEL, Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
	end
	newPart({ Name = "StallShelf", Size = vs(28, 0.8, 3.2), CFrame = at(0, 10.4, -7.8), Color = PANEL, Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
	strip("StallShelfLight", vs(27, 0.35, 0.5), at(0, 9.9, -6.4), 0.7, 16)
	for i, c in ipairs(wares) do
		-- uniform on all three axes: a Shape=Ball with unequal sides is silently drawn as a sphere
		-- of its SMALLEST one, which is how the old wares came out flatter than they were built
		newPart({ Name = "StallWare", Shape = Enum.PartType.Ball, Size = vs(3.6, 3.6, 3.6), CFrame = at(-11 + (i - 1) * 5.5, 12.6, -7.8), Color = c, Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
		newPart({ Name = "StallWarePad", Shape = Enum.PartType.Cylinder, Size = vs(0.4, 4.2, 4.2), CFrame = at(-11 + (i - 1) * 5.5, 10.9, -7.8) * CFrame.Angles(0, 0, math.rad(90)), Color = c, Material = Enum.Material.Neon, Transparency = 0.3, CanCollide = false, CastShadow = false, Parent = model })
	end

	-- ===== the counter: white body, dark top, one light line along the front =====
	local counter = newPart({ Name = "StallCounter", Size = vs(30, 6.2, 4), CFrame = at(0, 5.8, 9.4), Color = PANEL, Material = Enum.Material.SmoothPlastic, Parent = model })
	newPart({ Name = "StallCounterTop", Size = vs(31.4, 1, 5.4), CFrame = at(0, 9.4, 9.4), Color = FRAME, Material = Enum.Material.Metal, Parent = model })
	strip("StallCounterLight", vs(30.6, 0.8, 0.5), at(0, 7.9, 11.5), 0.9, 20)

	-- ===== the canopy: one flat slab on a dark fascia, lit from underneath =====
	newPart({ Name = "StallCanopy", Size = vs(35, 1.6, 25), CFrame = at(0, 21.4, 1.5), Color = PANEL, Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
	newPart({ Name = "StallFascia", Size = vs(35.6, 2.8, 1.1), CFrame = at(0, 20.6, 13.6), Color = FRAME, Material = Enum.Material.Metal, CanCollide = false, Parent = model })
	strip("StallFasciaLight", vs(33, 0.7, 0.5), at(0, 20.6, 14.3), 1.1, 26)
	for i = -1, 1 do
		strip("StallCanopyLight", vs(24, 0.3, 0.7), at(0, 20.5, i * 6 + 1.5), 0.5, 14)
	end

	-- ===== the pylons, which are what you actually see from the far end of the street =====
	--
	-- The billboard turns to face the camera and is readable from 640 studs, but a sign with no
	-- building under it reads as UI floating over the map. These two lit blades give the shop a
	-- silhouette above every roof in the village, which is what makes it a place rather than a
	-- label.
	for _, sx in ipairs({ -1, 1 }) do
		newPart({ Name = "ShopPylon", Size = vs(1.6, 32, 2.4), CFrame = at(sx * 16.8, 18, 9), Color = FRAME, Material = Enum.Material.Metal, CanCollide = false, Parent = model })
		strip("ShopPylonLight", vs(0.8, 26, 1.4), at(sx * 17.6, 20, 9), 1.4, 30)
		local cap = addKnob(model, pt(sx * 16.8, 34.6, 9), 3 * S, accent, Enum.Material.Neon)
		addLight(cap, accent, 30, 1.6)
	end

	-- ===== the forecourt: lit pads instead of a striped runner, and two bollards =====
	for i = 0, 2 do
		newPart({ Name = "StallPad", Size = vs(26 - i * 3, 0.3, 6.4), CFrame = at(0, 0.2, 15.5 + i * 7), Color = i % 2 == 0 and PANEL or accent, Material = i % 2 == 0 and Enum.Material.SmoothPlastic or Enum.Material.Neon, Transparency = i % 2 == 0 and 0 or 0.35, CanCollide = false, CastShadow = false, Parent = model })
	end
	for _, sx in ipairs({ -1, 1 }) do
		newPart({ Name = "ShopBollard", Size = vs(2.4, 8, 2.4), CFrame = at(sx * 20, 4, 13), Color = FRAME, Material = Enum.Material.Metal, Parent = model })
		strip("ShopBollardLight", vs(2.8, 0.9, 2.8), at(sx * 20, 8.4, 13), 1.2, 22)
	end

	-- CLEAR OF THE CANOPY. The canopy's top face is at 22.2 and the billboard's own StudsOffset is a
	-- fixed 3 studs that does not scale, so the board is placed on the geometry rather than on that
	-- offset: at 28 the whole board sits above the slab at any SHOP_SCALE.
	makeSign(model, title, at(0, 28, 6), UDim2.new(24 * S, 0, 7 * S, 0), { maxDistance = 640 })
	return counter
end

-- The village well: a cobbled rim, a roof on two posts, a bucket on a rope.
local function addWell(model, base, zone)
	local tones = stoneTones(zone)
	for i = 0, 11 do
		local a = i * math.pi / 6
		newPart({ Name = "WellStone", Size = Vector3.new(4.6, 5, 3.2), CFrame = base * CFrame.new(math.cos(a) * 8, 2.5, math.sin(a) * 8) * CFrame.Angles(0, -a, 0), Color = tones[(i % 2) + 1], Material = Enum.Material.Cobblestone, Parent = model })
	end
	newPart({ Name = "WellWater", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 13, 13), CFrame = base * CFrame.new(0, 3.6, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(86, 176, 226), Material = Enum.Material.Glass, Transparency = 0.32, CanCollide = false, Parent = model })
	for _, sx in ipairs({ -1, 1 }) do
		newPart({ Name = "WellPost", Size = Vector3.new(1.8, 17, 1.8), CFrame = base * CFrame.new(sx * 7, 13, 0), Color = VILLAGE_WOOD_DARK, Material = Enum.Material.Wood, Parent = model })
	end
	for _, sz in ipairs({ -1, 1 }) do
		newPart({ Name = "WellRoof", Size = Vector3.new(20, 1.4, 9), CFrame = base * CFrame.new(0, 22, sz * 3.6) * CFrame.Angles(math.rad(sz * 26), 0, 0), Color = VILLAGE_WOOD, Material = Enum.Material.WoodPlanks, CanCollide = false, Parent = model })
	end
	newPart({ Name = "WellRope", Size = Vector3.new(0.4, 8, 0.4), CFrame = base * CFrame.new(0, 16.5, 0), Color = Color3.fromRGB(206, 188, 150), Material = Enum.Material.Fabric, CanCollide = false, Parent = model })
	newPart({ Name = "WellBucket", Size = Vector3.new(4.2, 4.2, 4.2), CFrame = base * CFrame.new(0, 10.5, 0), Color = VILLAGE_WOOD, Material = Enum.Material.Wood, CanCollide = false, Parent = model })
end

-- THE ONE SHOP THIS ZONE HAS, IF IT HAS ONE.
--
-- Every village used to carry the same three potion counters, in all twenty zones, which made the
-- shop the least interesting thing on the street: there was never a reason to walk to a particular
-- zone for one. There are eight in the whole strip now (GameConfig.ZoneShops) -- five Mystery
-- Potion shops one every four zones, two Pet Fusion labs, and one Upgrade Emporium -- so arriving
-- somewhere that has one is an event.
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
	local S = SHOP_SCALE
	local function at(x, y, z) return base * CFrame.new(x * S, y * S, z * S) end
	local function vs(x, y, z) return Vector3.new(x * S, y * S, z * S) end

	local color = shopDef.color or vivid(zone.accentColor)
	local counter = addStall(model, base, color, shopDef.title, {
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
		local kindShare = math.floor(100 / math.max(#GameConfig.PotionKinds, 1) + 0.5)
		makeSign(model, ("ONE RANDOM POTION\n\u{1F9EC} DNA   \u{2B50} XP   \u{1F340} Luck  \u{2022}  %d%% each\n%s"):format(kindShare, GameConfig.GetMysteryOddsText()),
			at(0, 18.2, 15), UDim2.new(23 * S, 0, 4.8 * S, 0), { maxDistance = 360 })

	elseif shopKey == "fusion" then
		-- two pods with a beam between them: the fusion is the only thing this counter does, and a
		-- machine that visibly joins two things is a clearer sign than any amount of text
		for _, sx in ipairs({ -1, 1 }) do
			newPart({ Name = "FusionPodBase", Shape = Enum.PartType.Cylinder, Size = vs(2, 9, 9), CFrame = at(sx * 9, 4, 2) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(58, 54, 72), Material = Enum.Material.Metal, Parent = model })
			local glass = newPart({ Name = "FusionPod", Shape = Enum.PartType.Ball, Size = vs(11, 11, 11), CFrame = at(sx * 9, 10.4, 2), Color = color, Material = Enum.Material.Glass, Transparency = 0.55, CanCollide = false, Parent = model })
			addLight(glass, color, math.min(22 * S, 60), 1.6)
			pulseForever(glass, 0.62, 2.4)
			addKnob(model, (at(sx * 9, 16.6, 2)).Position, 3.4 * S, Color3.fromRGB(244, 247, 252))
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
			addLamp(model, CFrame.new(cx + sx * 32, 0, z) * CFrame.Angles(0, math.rad(sx < 0 and 90 or -90), 0), accent, 20)
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
						part.Color = alt and VILLAGE_WOOD or VILLAGE_CREAM
						part.Material = VILLAGE_POST_MAT
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
				newPart({ Name = "FencePicket", Size = Vector3.new(1.6, 7, 1.6), Position = Vector3.new(px, 3.5, z), Color = picket % 2 == 0 and VILLAGE_CREAM or VILLAGE_WOOD, Material = VILLAGE_POST_MAT, CanCollide = false, Parent = model })
				if picket % 2 == 0 then
					addKnob(model, Vector3.new(px, 7.4, z), 2.4, VILLAGE_WOOD)
				end
			end
		end
		for z = 426, 30, -12 do
			for _, sx in ipairs({ -1, 1 }) do
				newPart({ Name = "FenceRail", Size = Vector3.new(0.7, 1, 12), Position = Vector3.new(cx + sx * 24, 5.4, z), Color = VILLAGE_WOOD_DARK, Material = VILLAGE_POST_MAT, CanCollide = false, Parent = model })
			end
		end
	end

	-- Bunting strung lamp to lamp down both sides of the street, and once across the welcome arch.
	-- This is the cheapest thing in the whole pass and it does more than any of it: a row of little
	-- triangles overhead is the single clearest signal that a place is a shopfront and not terrain.
	for _, sx in ipairs({ -1, 1 }) do
		for z = 420, 60, -30 do
			addBunting(model,
				Vector3.new(cx + sx * 32, 18, z),
				Vector3.new(cx + sx * 32, 18, z - 30), 5, 3.4, z)
		end
	end
	addBunting(model, Vector3.new(cx - 30, 29, 426), Vector3.new(cx + 30, 29, 426), 7, 4, 3)

	-- flower boxes between the lamps, turned to face the walkway
	for i, spot in ipairs({ { -1, 381 }, { 1, 381 }, { -1, 301 }, { 1, 261 }, { -1, 181 }, { 1, 181 }, { -1, 100 }, { 1, 140 }, { -1, 60 }, { 1, 60 } }) do
		addPlanter(model, CFrame.new(cx + spot[1] * 29, 0, spot[2]) * CFrame.Angles(0, math.rad(spot[1] < 0 and 90 or -90), 0), i)
	end

	-- welcome arch where the street starts, so arriving in a zone has a threshold
	for _, sx in ipairs({ -1, 1 }) do
		newPart({ Name = "ArchPillar", Size = Vector3.new(6, 30, 6), Position = Vector3.new(cx + sx * 30, 15, 426), Color = VILLAGE_WOOD_DARK, Material = VILLAGE_POST_MAT, Parent = model })
		-- a cream collar a third of the way up each pillar, and a knob on top
		newPart({ Name = "ArchPillarCollar", Size = Vector3.new(7.4, 2.2, 7.4), Position = Vector3.new(cx + sx * 30, 9, 426), Color = VILLAGE_CREAM, Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
		addKnob(model, Vector3.new(cx + sx * 30, 36.4, 426), 5, VILLAGE_CREAM)
		-- The pennons hanging off the arch. These were one flat 14x8 sheet of raw accent colour each,
		-- and from the arrival gate they were simply two bright rectangles floating beside the
		-- pillars -- the loudest wrong thing in the zone. Now: a rod, two-tone cloth, a stripe, and a
		-- pointed tail, which is what a hanging pennon actually looks like.
		local bx = cx + sx * 25
		local cloth, trim = candy(sx > 0 and 1 or 4), candy(sx > 0 and 4 or 1)
		newPart({ Name = "ArchBannerRod", Size = Vector3.new(0.9, 0.9, 9), Position = Vector3.new(bx, 29, 426), Color = VILLAGE_WOOD_DARK, Material = VILLAGE_POST_MAT, CanCollide = false, Parent = model })
		newPart({ Name = "ArchBanner", Size = Vector3.new(0.6, 13, 8), Position = Vector3.new(bx, 22, 426), Color = cloth, Material = Enum.Material.Fabric, CanCollide = false, Parent = model })
		newPart({ Name = "ArchBannerStripe", Size = Vector3.new(0.9, 2.2, 8.4), Position = Vector3.new(bx, 24.5, 426), Color = trim, Material = Enum.Material.Fabric, CanCollide = false, CastShadow = false, Parent = model })
		newPart({ Name = "ArchBannerEmblem", Shape = Enum.PartType.Ball, Size = Vector3.new(1.1, 4, 4), Position = Vector3.new(bx - sx * 0.5, 20.5, 426), Color = VILLAGE_CREAM, Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false, Parent = model })
		-- the swallow tail: a wedge rolled point-down, the same trick the pennants use
		newPart({ Name = "ArchBannerTail", Shape = Enum.PartType.Wedge, Size = Vector3.new(0.6, 5, 8),
			CFrame = CFrame.new(bx, 13, 426) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.pi),
			Color = cloth, Material = Enum.Material.Fabric, CanCollide = false, Parent = model })
	end
	newPart({ Name = "ArchBeam", Size = Vector3.new(72, 4, 7), Position = Vector3.new(cx, 32, 426), Color = VILLAGE_WOOD, Material = VILLAGE_BOARD_MAT, CanCollide = false, Parent = model })
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
		Position = Vector3.new(cx, 43.5, 426), Color = VILLAGE_WOOD, Material = VILLAGE_BOARD_MAT,
		CanCollide = false, Parent = model })
	for _, sx in ipairs({ -1, 1 }) do
		newPart({ Name = "ZoneNameBatten", Size = Vector3.new(3, 20, 3.4), Position = Vector3.new(cx + sx * 27.5, 43.5, 426), Color = VILLAGE_WOOD_DARK, Material = VILLAGE_POST_MAT, CanCollide = false, Parent = model })
		addKnob(model, Vector3.new(cx + sx * 27.5, 54.6, 426), 4.4, VILLAGE_CREAM)
	end
	-- Coarse on purpose -- see the note on the gate board: a big canvas is what stops a SurfaceGui
	-- being drawn at range, and this is a sign meant to be read from down the street.
	addPlankText(nameBoard, zone.emoji .. " " .. zone.name, accent, { maxDistance = 620, pixelsPerStud = 14 })

	-- THE SHOP, IF THIS ZONE HAS ONE -- west of the street and turned to face it, where the market
	-- row used to stand. Twelve of the twenty zones now have no shop at all, which is the point:
	-- see the note on buildZoneShop and GameConfig.ZoneShops.
	local facing = CFrame.Angles(0, math.rad(90), 0)
	local shopKey, shopDef = GameConfig.GetZoneShop(index)
	if shopDef then
		buildZoneShop(model, zone, cx, shopKey, shopDef, CFrame.new(cx - 150, 0, SHOP_Z) * facing)
	end

	addWell(model, CFrame.new(cx + 150, 0, -168), zone)

	-- benches facing the street, between the lamps
	for _, spot in ipairs({ { -1, 345 }, { 1, 305 }, { -1, 225 }, { 1, 144 }, { -1, 112 }, { 1, 72 } }) do
		local bx = cx + spot[1] * 38
		newPart({ Name = "BenchSeat", Size = Vector3.new(4, 1.2, 14), Position = Vector3.new(bx, 4.4, spot[2]), Color = VILLAGE_WOOD, Material = VILLAGE_BOARD_MAT, Parent = model })
		newPart({ Name = "BenchBack", Size = Vector3.new(1, 6, 14), Position = Vector3.new(bx - spot[1] * 1.6, 7.4, spot[2]), Color = VILLAGE_WOOD, Material = VILLAGE_BOARD_MAT, CanCollide = false, Parent = model })
		for _, sz in ipairs({ -1, 1 }) do
			newPart({ Name = "BenchLeg", Size = Vector3.new(3.4, 4, 1.2), Position = Vector3.new(bx, 2, spot[2] + sz * 5.5), Color = VILLAGE_WOOD_DARK, Material = VILLAGE_POST_MAT, CanCollide = false, Parent = model })
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

	if target then
		local gapHalf = PORTAL_GAP / 2
		local segLen = (PLATFORM_DEPTH - PORTAL_GAP) / 2
		newPart({ Name = "Wall", Size = Vector3.new(WALL_THICK, WALL_HEIGHT, segLen), Position = Vector3.new(wallX, WALL_HEIGHT/2, -(gapHalf + segLen/2)), Color = wallColor, Material = Enum.Material.Slate, Parent = model })
		newPart({ Name = "Wall", Size = Vector3.new(WALL_THICK, WALL_HEIGHT, segLen), Position = Vector3.new(wallX, WALL_HEIGHT/2, (gapHalf + segLen/2)), Color = wallColor, Material = Enum.Material.Slate, Parent = model })
		addRockRampart(model, zone, "z", wallX, 0, halfDepth - 8, inward, PORTAL_CLEAR_HALF)
		buildPortal(model, wallX, target)
	else
		newPart({ Name = "Wall", Size = Vector3.new(WALL_THICK, WALL_HEIGHT, PLATFORM_DEPTH), Position = Vector3.new(wallX, WALL_HEIGHT/2, 0), Color = wallColor, Material = Enum.Material.Slate, Parent = model })
		addRockRampart(model, zone, "z", wallX, 0, halfDepth - 8, inward, nil)
	end

	addBackdropMesas(model, zone, "z", wallX, 0, halfDepth + 30, -inward)
end

local function buildZWall(model, zone, cx, cz, wallColor, target)
	local inward = (cz > 0) and -1 or 1
	if target then
		local gapHalf = PORTAL_GAP / 2
		local segLen = (PLATFORM_WIDTH - PORTAL_GAP) / 2
		newPart({ Name = "Wall", Size = Vector3.new(segLen, WALL_HEIGHT, WALL_THICK), Position = Vector3.new(cx - (gapHalf + segLen/2), WALL_HEIGHT/2, cz), Color = wallColor, Material = Enum.Material.Slate, Parent = model })
		newPart({ Name = "Wall", Size = Vector3.new(segLen, WALL_HEIGHT, WALL_THICK), Position = Vector3.new(cx + (gapHalf + segLen/2), WALL_HEIGHT/2, cz), Color = wallColor, Material = Enum.Material.Slate, Parent = model })
		addRockRampart(model, zone, "x", cz, cx, PLATFORM_WIDTH / 2 - 8, inward, PORTAL_CLEAR_HALF)
		buildPortalInZWall(model, cx, cz, target)
	else
		newPart({ Name = "Wall", Size = Vector3.new(PLATFORM_WIDTH, WALL_HEIGHT, WALL_THICK), Position = Vector3.new(cx, WALL_HEIGHT/2, cz), Color = wallColor, Material = Enum.Material.Slate, Parent = model })
		addRockRampart(model, zone, "x", cz, cx, PLATFORM_WIDTH / 2 - 8, inward, nil)
	end
	addBackdropMesas(model, zone, "x", cz, cx, PLATFORM_WIDTH / 2 + 30, -inward)
	-- the guardian only goes behind the far wall, where it fills the view you get walking in
	if cz < 0 then
		-- far enough back that the whole figure fits in the view from the shop. Parked right
		-- against the wall it was a 500-stud green slab filling the sky with no readable silhouette.
		buildTitan(model, zone, cx, cz - 175, 1)
	end
end

-- ===== shared decoration helpers =====
-- Every zone is dressed in four layers -- a GROUND layer of scattered rocks/mounds, a MID
-- layer of signature biome props, one big LANDMARK silhouette at the back of the platform,
-- and an ATMOSPHERE emitter -- plus LIGHTING ACCENTS, so no platform ever reads as an empty
-- rectangle. The Desert builder was the quality bar; these helpers make it cheap to hit it
-- in all 20 biomes without copy-pasting the same scatter loops twenty times.

-- THE VALLEY FLOOR, not the whole platform. The outer band beyond this is terraced into cliffs
-- and waterfalls (see buildTerrain), and every scattered prop in the game is placed at y = 0 with
-- no idea what the ground under it is doing -- so anything dropped out there would be buried in a
-- terrace or left standing in mid-air. Props keep to the flat middle; the sides become scenery.
-- 350, not 400: the pool at the cliff foot has its inner rim at x = 363, and at 400 the scatter
-- was dropping trees into the water. The number that matters is the POOL's edge, not the
-- terrace's -- measure against the innermost thing terrain builds, never against the band.
local DECO_SPREAD_X = 350 -- was 595. The platform still reaches 625; the last 275 is terrain.
local DECO_SPREAD_Z = 548 -- and |z| <= 575
local CLEAR_HALF = 60     -- centre stays clear: Pet Shop + creature spawns live there
local ARRIVAL_Z = 490     -- players step out of a gate here, at either end (GetZoneSpawnCFrame)
local ARRIVAL_CLEAR = 90  -- ... so keep a clearing around it in every zone
-- THE STREET: the straight walk from the arrival gate at +Z, through the egg plaza in the middle,
-- on to the exit gate at -Z. Reserving only the centre square left the rest of that line open to
-- the scatter, so trees, crates, banner poles and glow posts landed in the walkway and the walk to
-- the eggs was a weave between props. Nothing scattered may stand within this of the centre line,
-- at any depth -- the hand-placed street furniture (fence at +/-24, lamps at +/-32, benches at
-- +/-38) is outside the walkway and stays.
local STREET_HALF = 48
-- BossService parks every boss on the street at zone.offset + (0, 0, BOSS_Z) -- between the shop
-- and the exit gate, so it is the thing standing in front of the next door -- and the biggest rigs
-- are ~290 studs across with their arena. Without a reserved clearing the scatter drops full-height
-- trees straight through the arena and the fight happens inside a hedge.
--
-- BOTH NUMBERS COME FROM GameConfig, because this file and BossService each need them and they had
-- already drifted once: a platform-depth rescale moved the clearing to -320 and left the boss
-- itself at -240, so for two versions the scatter was carefully avoiding empty ground while props
-- grew through the arena 80 studs away. One decision, one home, two readers.
local BOSS_Z = GameConfig.BossStationZ
-- Generous on purpose: several biome builders take one scatterPoint and then stand two or three
-- parts around it at +/-8..12, so a clearance measured tight to the arena still let a lattice post
-- or a cell column end up on the boss's dais.
local BOSS_CLEAR = GameConfig.BossStationClear

local function lighten(c, t)
	return c:Lerp(Color3.new(1, 1, 1), t)
end

local function darken(c, t)
	return c:Lerp(Color3.new(0, 0, 0), t)
end

-- Random point on the platform that is never inside the reserved central square and never
-- inside the arrival clearing. Returns absolute world x (already offset by cx) and z.
-- Most of the seventy-odd biome scatter calls pass their OWN spread, and every one of those
-- numbers was authored against the 450 x 550 platform this game started on (~205 on x, ~255 on z).
-- Taken literally on a 1250 x 860 platform they pack the whole biome into the middle third and
-- leave a bare margin down both sides -- which is exactly what "the zone looks empty" was. They
-- are read as fractions of the platform they were written for and rescaled onto the current one,
-- so the next resize is still one constant and not seventy call sites.
local LEGACY_SPREAD_X, LEGACY_SPREAD_Z = 205, 255

-- `halfSize` is the prop's OWN half-footprint in studs, and passing it is what makes any of the
-- reservations below mean anything for a large prop.
--
-- Every test here is a test on the returned POINT. That is fine for a bush. It is wrong for
-- anything wider than the margin it was cleared by, because the check passes on the centre while
-- the body hangs over the thing being protected -- and it fails silently, because the code that
-- placed it never knew how big it was going to be. The zone idols are the case that exposed it:
-- they doubled to a 150-stud plinth, kept landing at |x| = 48 (STREET_HALF, which they passed
-- honestly), and stood with 27 studs of stone across the middle of the walkway.
--
-- So every clearance is inflated by halfSize, and the spread is pulled IN by it as well, or a big
-- prop simply overhangs the platform's far edge into the terrace band instead.
-- Ground already taken by something big, in WORLD coordinates. Every other reservation
-- scatterPoint honours is fixed geography -- the street, both gate mouths, the boss arena, the
-- centre square -- so nothing it places has ever known about anything it placed a moment earlier.
-- With 130-stud idols on the platform that stopped being survivable: a tree scattered afterwards
-- landed on a plinth and grew out of the statue's chest, and two idols could be dropped on top of
-- one another. Anything big enough that you have to walk around it registers itself here.
-- Cleared once per zone, at the top of addGroundDetail -- which is the first thing the zone loop
-- builds on the ground. Entries are world-space, so a stale one from the previous zone could never
-- match anyway; the clear is for the table's size, not for correctness.
--
-- DECLARED FAR ABOVE THIS COMMENT, next to addGroundDetail. It has to be: addGroundDetail and the
-- crate/coin scatter both run several hundred lines earlier in the file, and a local declared here
-- is simply not in scope up there -- it compiles as a nil global lookup and dies at run time.
-- `scatterPoint` below gets away with being used early only because it is a GLOBAL function.

function scatterPoint(cx, spreadX, spreadZ, halfSize)
	halfSize = halfSize or 0
	spreadX = spreadX and math.floor(math.min(DECO_SPREAD_X, spreadX * (DECO_SPREAD_X / LEGACY_SPREAD_X))) or DECO_SPREAD_X
	spreadZ = spreadZ and math.floor(math.min(DECO_SPREAD_Z, spreadZ * (DECO_SPREAD_Z / LEGACY_SPREAD_Z))) or DECO_SPREAD_Z
	-- Clamped so the band never inverts: a prop bigger than the platform's usable half would
	-- otherwise ask for math.random over an empty range and take the whole build down.
	spreadX = math.max(STREET_HALF + halfSize + 10, spreadX - halfSize)
	spreadZ = math.max(CLEAR_HALF + halfSize + 10, spreadZ - halfSize)
	local street = STREET_HALF + halfSize
	local centre = CLEAR_HALF + halfSize
	local arrival = ARRIVAL_CLEAR + halfSize
	local boss = BOSS_CLEAR + halfSize
	-- The best near-miss seen so far, in case none of the tries comes back completely clear. See
	-- the note on the fallback below for why blind is not good enough.
	local bestX, bestZ, bestGap = nil, nil, -math.huge

	for _ = 1, 40 do
		local x = math.random(-spreadX, spreadX)
		local z = math.random(-spreadZ, spreadZ)
		local outsideCentre = math.abs(x) >= centre or math.abs(z) >= centre
		-- both gate mouths, not just the one you normally walk in through: coming back down the
		-- strip puts you at -Z instead, and a boulder in that doorway is just as bad
		local dz = z - ARRIVAL_Z
		local dzBack = z + ARRIVAL_Z
		local outsideArrival = (x * x + dz * dz) > (arrival * arrival)
			and (x * x + dzBack * dzBack) > (arrival * arrival)
		local bz = z - BOSS_Z
		local outsideBoss = (x * x + bz * bz) > (boss * boss)
		-- and the walkway itself, over the platform's whole depth
		local outsideStreet = math.abs(x) >= street
		if outsideStreet and outsideCentre and outsideArrival and outsideBoss then
			local wx = cx + x
			-- how much room this point has to spare against the NEAREST claim -- positive means it
			-- is clear of everything, negative is how far it overlaps the worst offender
			local gap = math.huge
			for _, b in ipairs(scatterBlocks) do
				local bx, bz = wx - b.x, z - b.z
				gap = math.min(gap, math.sqrt(bx * bx + bz * bz) - (b.r + halfSize))
			end
			if gap >= 0 then
				return wx, z
			end
			if gap > bestGap then
				bestGap, bestX, bestZ = gap, wx, z
			end
		end
	end

	-- THE FALLBACK HAS TO OBEY THE RESERVATIONS TOO, and this is the whole reason the idols kept
	-- landing on things.
	--
	-- It used to return a blind random point that consulted `scatterBlocks` not at all. That was
	-- survivable while almost nothing reserved ground -- but once the crates and coins started
	-- claiming theirs, a 100-stud idol had 40-odd circles to miss and routinely exhausted its
	-- tries, so it took the blind path and dropped a 150-stud plinth wherever that landed. Adding
	-- reservations made the problem WORSE, which is how it was found: the swallowed-prop count went
	-- UP from 320 to 375.
	--
	-- The least-bad candidate already seen beats a fresh guess every time: it is the point that
	-- overlaps the least, and it has already passed the street, centre, gate and arena tests.
	if bestX then
		return bestX, bestZ
	end
	-- and only if literally every try failed the fixed geography as well. Pushed past BOSS_CLEAR
	-- rather than CLEAR_HALF: the boss arena is the widest reservation on the platform.
	local sign = math.random(1, 2) == 1 and -1 or 1
	return cx + sign * math.random(math.min(boss + 12, spreadX), spreadX), math.random(-spreadZ, -centre)
end

function addLight(part, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range or 24
	l.Brightness = brightness or 2
	l.Parent = part
	return l
end

-- The platform went from 700 x 860 to 900 x 860 -- 24% more ground, all of it off the street where
-- the scatter lands. The per-biome counts below were authored against the old area, so without this
-- every zone came out visibly emptier the moment it was widened: same number of rocks, more floor
-- to spread them over. One multiplier rather than 20 edited tables, so the next resize is one line.
local DENSITY = 1.78
local function scaled(count, fallback)
	return math.max(1, math.floor((count or fallback) * DENSITY + 0.5))
end

-- GROUND LAYER: low scattered rocks / shards / debris that break up the flat floor.
local function addGroundLitter(model, cx, cfg)
	local colors = cfg.colors
	local flat = cfg.flat or 0.6
	for _ = 1, scaled(cfg.count, 16) do
		local x, z = scatterPoint(cx)
		local s = math.random(cfg.minSize or 3, cfg.maxSize or 11)
		newPart({
			Name = cfg.name or "GroundRock",
			Shape = cfg.shape or Enum.PartType.Ball,
			Size = Vector3.new(s, s * flat, s * (0.75 + math.random() * 0.5)),
			Orientation = Vector3.new(0, math.random(0, 360), 0),
			Position = Vector3.new(x, s * flat * 0.35, z),
			Color = colors[math.random(1, #colors)],
			Material = cfg.material or Enum.Material.Rock,
			Transparency = cfg.transparency or 0,
			CanCollide = false,
			Parent = model,
		})
	end
end

-- ===== GROUND CLUTTER, FROM THE SHARED MESH LIBRARY =====
--
-- `ServerStorage.PropMeshes.Gnd_<Thing>` -- rocks, log, bush, stump, flowers, tuft, mushroom, fern,
-- crystal, bones. Ten models SHARED by all twenty zones, where CANOPY/BOULDER/FLORA/STRUCTURE are
-- one set per zone. That split is on purpose: a zone's identity comes from its big silhouettes, and
-- a fern is a fern in any biome. Ten shared models cover twenty zones for the price of one set.
--
-- WHICH ONES A ZONE GETS IS THE ONLY PER-BIOME DECISION, and it is what stops the Moon growing
-- bushes. Anything absent from this table takes DEFAULT_CLUTTER, so a new zone needs no entry at
-- all -- the same opt-out shape the idols and the landmark already use.
local DEFAULT_CLUTTER = { "Rocks", "Tuft", "Crystal" }
local ZONE_CLUTTER = {
	Forest         = { "Rocks", "Log", "Bush", "Stump", "Flowers", "Tuft", "Mushroom", "Fern" },
	Desert         = { "Rocks", "Bones", "Tuft", "Stump" },
	Ocean          = { "Rocks", "Tuft", "Bush", "Crystal" },
	Volcano        = { "Rocks", "Bones", "Crystal" },
	Moon           = { "Rocks", "Crystal" },
	Mars           = { "Rocks", "Bones", "Crystal" },
	Galaxy         = { "Rocks", "Crystal" },
	BlackHole      = { "Rocks", "Crystal", "Bones" },
	Multiverse     = { "Rocks", "Crystal", "Tuft" },
	Nebula         = { "Rocks", "Crystal", "Mushroom" },
	Wormhole       = { "Rocks", "Crystal" },
	QuantumRealm   = { "Rocks", "Crystal" },
	TimeRift       = { "Rocks", "Stump", "Tuft", "Bones" },
	AntimatterZone = { "Rocks", "Crystal", "Bones" },
	DreamDimension = { "Flowers", "Mushroom", "Tuft", "Bush" },
	MirrorUniverse = { "Rocks", "Crystal" },
	VoidExpanse    = { "Rocks", "Bones", "Crystal" },
	CelestialThrone= { "Rocks", "Flowers", "Tuft" },
	Singularity    = { "Rocks", "Crystal" },
	AbsolutePlane  = { "Rocks", "Crystal" },
}

local function addGroundClutter(model, cx)
	local lib = ServerStorage:FindFirstChild("PropMeshes")
	if not (lib and ACTIVE_ZONE_KEY) then return end
	local picks = ZONE_CLUTTER[ACTIVE_ZONE_KEY] or DEFAULT_CLUTTER

	-- 26 pieces spread over the valley floor. These are SMALL -- 4 to 11 studs -- so they are what
	-- the player walks past rather than around, which is exactly the layer that was still primitives
	-- while the trees and boulders became meshes.
	for _ = 1, 26 do
		local template = lib:FindFirstChild("Gnd_" .. picks[math.random(1, #picks)])
		if template then
			local clone = template:Clone()
			local _, raw = clone:GetBoundingBox()
			local want = 4 + math.random() * 7
			clone:ScaleTo(want / math.max(raw.Y, 0.1))
			for _, part in ipairs(clone:GetDescendants()) do
				if part:IsA("BasePart") then
					-- generated meshes arrive UNANCHORED, and nothing else here anchors them
					part.Anchored = true
					-- small enough to step over: colliding with these would make the floor sticky
					part.CanCollide = false
					part.CastShadow = false
				end
			end
			clone.Name = "GroundClutter"
			clone.Parent = model
			-- halfSize 6 so a clump never lands inside the street, a gate mouth or the boss arena;
			-- no reserveScatter afterwards, deliberately -- these are ground cover and something
			-- bigger landing over one of them costs nothing, where 26 more reservations a zone would
			-- crowd out the props that actually need the room.
			local x, z = scatterPoint(cx, 320, 400, 6)
			seatModel(clone, x, z, math.random() * math.pi * 2, 0.3)
		end
	end
end

-- GROUND LAYER: wide, very low mounds so the floor has some relief instead of being a plane.
local function addMounds(model, cx, cfg)
	for _ = 1, scaled(cfg.count, 5) do
		-- spread widened with the platform: at 190 every mound in the game sat in the same middle
		-- third of it and the new ground out by the walls was flat
		local x, z = scatterPoint(cx, 300, 260)
		local s = math.random(cfg.minSize or 32, cfg.maxSize or 62)
		newPart({
			Name = cfg.name or "Mound",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(s, s * (cfg.flat or 0.24), s * 0.9),
			Position = Vector3.new(x, s * 0.03, z),
			Color = cfg.color,
			Material = cfg.material or Enum.Material.Slate,
			Transparency = cfg.transparency or 0,
			CanCollide = false,
			Parent = model,
		})
	end
end

-- ATMOSPHERE LAYER: one biome-appropriate particle field drifting over the whole platform.
local function addAtmosphere(model, cx, cfg)
	local anchor = newPart({
		Name = "Atmosphere",
		Size = Vector3.new(PLATFORM_WIDTH - 60, 1, PLATFORM_DEPTH - 60),
		Position = Vector3.new(cx, cfg.height or 30, 0),
		Transparency = 1,
		CanCollide = false,
		-- This is a 640 x 800 invisible sheet lying across the whole platform at head height, and it
		-- was queryable. Every mouse ray cast from a camera above it -- which is every camera in the
		-- game -- struck this first, so Mouse.Target anywhere inside a zone was the atmosphere carrier
		-- and never the thing under the cursor. It carries an emitter and nothing else; it should
		-- never have been in the way of anything.
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = model,
	})
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(cfg.color, cfg.color2 or cfg.color)
	e.Size = NumberSequence.new(cfg.sizeStart or 2, cfg.sizeEnd or 4)
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, cfg.transparency or 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(cfg.lifeMin or 5, cfg.lifeMax or 9)
	e.Rate = cfg.rate or 10
	e.Speed = NumberRange.new(cfg.speedMin or 2, cfg.speedMax or 6)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-25, 25)
	e.LightEmission = cfg.lightEmission or 0
	e.Acceleration = cfg.acceleration or Vector3.new(0, 0, 0)
	e.Parent = anchor
	return anchor
end

-- LIGHTING ACCENTS: scattered lamp posts, each carrying a real PointLight in the biome colour.
local function addGlowPosts(model, cx, cfg)
	local color = cfg.color
	for _ = 1, scaled(cfg.count, 5) do
		local x, z = scatterPoint(cx, 310, 265)
		local h = cfg.height or math.random(10, 20)
		newPart({ Name = "GlowPost", Size = Vector3.new(1.8, h, 1.8), Position = Vector3.new(x, h / 2, z), Color = darken(color, 0.65), Material = Enum.Material.Metal, CanCollide = false, Parent = model })
		local bulb = newPart({ Name = "GlowBulb", Shape = Enum.PartType.Ball, Size = Vector3.new(4.5, 4.5, 4.5), Position = Vector3.new(x, h + 1.5, z), Color = color, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(bulb, color, cfg.range or 28, cfg.brightness or 2)
	end
end

-- LANDMARK: one big silhouette feature near the back of the platform (z ~ -210) so the zone
-- reads from a distance. Every landmark stands on a lit plinth and is framed by two braziers,
-- so it looks like a built site rather than a lone prop dropped on the floor.
-- ONE MONUMENT PER ZONE INSTEAD OF SEVEN STYLES SHARED BETWEEN TWENTY. Same argument as the
-- Guardian Titan: the landmark's whole job is to be the thing you recognise a zone by from the
-- arrival gate, and `arch` was doing that job in three different zones at once. A filed
-- Landmark_<ZoneKey> replaces the block build; a zone without one keeps its style unchanged, so
-- this rolls out one mesh at a time like everything else here.
--
-- 118 tall against the block landmarks' ~110, capped at 96 wide so it stays on its own plinth.
local LANDMARK_HEIGHT = 118
local LANDMARK_WIDTH = 96

local function landmarkFigure()
	local folder = ServerStorage:FindFirstChild("PropMeshes")
	local template = ACTIVE_ZONE_KEY and folder and folder:FindFirstChild("Landmark_" .. ACTIVE_ZONE_KEY)
	if not template then return nil end
	local figure = template:Clone()
	local _, raw = figure:GetBoundingBox()
	figure:ScaleTo(math.min(LANDMARK_HEIGHT / math.max(raw.Y, 1), LANDMARK_WIDTH / math.max(raw.X, raw.Z, 1)))
	figure.Name = "LandmarkFigure"
	for _, d in ipairs(figure:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			-- solid, unlike the props: this one stands at the back of the platform where players do
			-- walk, and the block landmark it replaces was collidable too
			d.CanCollide = true
		end
	end
	return figure
end

local function addLandmark(model, cx, cfg)
	local z = cfg.z or -480
	-- ...but no longer on the centre line. The gate to the next zone opens in the middle of the -Z
	-- wall, and a 104-stud plinth centred on cx stood squarely in its approach. Back-left keeps the
	-- silhouette in shot from the moment you arrive without blocking the walk out.
	cx = cx + (cfg.dx or -210)
	local base = cfg.base
	local accent = cfg.accent
	local mat = cfg.material or Enum.Material.Rock
	local lit = {}

	-- LOOKED UP BEFORE THE PLINTH IS BUILT, because the plinth has to be sized for whatever is
	-- going to stand on it. 96 x 62 was cut for the block builds; a 96-wide mesh on it leaves no
	-- base showing at all, and the two braziers below would be swallowed by their own pedestal.
	local figure = landmarkFigure()
	-- how far out the two braziers stand, and how far forward. Set with the dais below when there
	-- is one, because a post planted inside the plinth is a post you never see.
	local postX, postZ = 60, 12

	if figure then
		-- THE DAIS IS SIZED TO WHAT STANDS ON IT, not to a constant. These twenty monuments run 43 to
		-- 96 studs wide: a base cut for the widest is a parade ground under the narrowest, and the
		-- Forest shrine duly came out standing in the middle of 135 x 99 studs of empty stone.
		-- Measured here, before the figure is parented -- GetBoundingBox covers every descendant, so
		-- once it is inside the zone model it is measuring the zone.
		local _, fs = figure:GetBoundingBox()
		local sw = math.max(fs.X, 52) + 20
		local sd = math.max(fs.Z, 44) + 20
		postX, postZ = (sw + 18) / 2 + 14, 14
		-- THE TRIM IS WIDER THAN THE PLINTH IT TRIMS, and it always was: 104 x 70 of full-bright
		-- Neon laid over a 96 x 62 base covers it completely, so what a player sees at the foot of
		-- every landmark in the game is a flat white rectangle and never the stone underneath. The
		-- block builds hid most of it; a mesh on a base 1.3x wider turned it into a white floor tile
		-- with a monument standing in the middle of it.
		--
		-- A stepped base fixes it the way the idols' two shrinking slabs already do. The accent stays
		-- -- it is what lights the site -- but as a thin band SANDWICHED between the two steps, so
		-- only its edge shows and it reads as a lit rim instead of as the ground.
		newPart({ Name = "LandmarkPlinth", Size = Vector3.new(sw + 18, 5, sd + 18), Position = Vector3.new(cx, 2.5, z), Color = darken(base, 0.5), Material = mat, Parent = model })
		newPart({ Name = "LandmarkPlinthTrim", Size = Vector3.new(sw + 21, 1.4, sd + 21), Position = Vector3.new(cx, 5.7, z), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		newPart({ Name = "LandmarkPlinthStep", Size = Vector3.new(sw, 4, sd), Position = Vector3.new(cx, 8.4, z), Color = darken(base, 0.28), Material = mat, Parent = model })
	else
		newPart({ Name = "LandmarkPlinth", Size = Vector3.new(96, 5, 62), Position = Vector3.new(cx, 2.5, z), Color = darken(base, 0.45), Material = mat, Parent = model })
		newPart({ Name = "LandmarkPlinthTrim", Size = Vector3.new(104, 1.8, 70), Position = Vector3.new(cx, 5.4, z), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	end

	local style = cfg.style
	if figure then
		figure.Parent = model
		-- Half turned: the generator authors facing -Z, and this monument stands at the -Z end of
		-- the platform looking back up the street at the gate you arrive through.
		-- 10.4 is the top of the upper STEP (8.4 centre + 2 half), which is the surface a monument
		-- stands on. Not the plinth top at 5 and not the trim at 6.4 -- both of those are underneath
		-- the step and would bury the figure's feet in it.
		seatModel(figure, cx, z, math.pi)
		figure:PivotTo(figure:GetPivot() + Vector3.new(0, 10.4, 0))
	elseif style == "greattree" then
		newPart({ Name = "GreatTrunk", Size = Vector3.new(20, 76, 20), Position = Vector3.new(cx, 43, z), Color = cfg.trunkColor or Color3.fromRGB(92, 64, 40), Material = Enum.Material.Wood, Parent = model })
		for i = 1, 3 do
			newPart({ Name = "GreatRoot", Size = Vector3.new(8, 13, 28), Orientation = Vector3.new(0, i * 57, 0), Position = Vector3.new(cx + math.random(-12, 12), 9, z + math.random(-10, 10)), Color = cfg.trunkColor or Color3.fromRGB(92, 64, 40), Material = Enum.Material.Wood, Parent = model })
		end
		for i = 1, 6 do
			local s = math.random(36, 58)
			newPart({ Name = "GreatCanopy", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 0.82, s), Position = Vector3.new(cx + math.random(-24, 24), 80 + math.random(-10, 16), z + math.random(-16, 16)), Color = i % 2 == 0 and base or darken(base, 0.22), Material = Enum.Material.Grass, CanCollide = false, Parent = model })
		end
		local fruit = newPart({ Name = "GreatGlow", Shape = Enum.PartType.Ball, Size = Vector3.new(11, 11, 11), Position = Vector3.new(cx, 110, z), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		table.insert(lit, fruit)
	elseif style == "spire" then
		local y = 5
		for i = 0, 5 do
			local w = 42 - i * 5.5
			local h = 17 - i * 1.2
			newPart({ Name = "SpireBlock", Size = Vector3.new(w, h, w * 0.78), Orientation = Vector3.new(0, i * 11, 0), Position = Vector3.new(cx, y + h / 2, z), Color = i % 2 == 0 and base or darken(base, 0.2), Material = mat, Parent = model })
			y = y + h
		end
		local tip = newPart({ Name = "SpireTip", Size = Vector3.new(12, 24, 12), Orientation = Vector3.new(0, 45, 0), Position = Vector3.new(cx, y + 12, z), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		table.insert(lit, tip)
	elseif style == "arch" then
		for _, side in ipairs({ -1, 1 }) do
			newPart({ Name = "ArchLeg", Size = Vector3.new(13, 72, 14), Position = Vector3.new(cx + side * 31, 41, z), Color = base, Material = mat, Parent = model })
			newPart({ Name = "ArchLegTrim", Size = Vector3.new(16, 4, 17), Position = Vector3.new(cx + side * 31, 75, z), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		end
		newPart({ Name = "ArchSpan", Size = Vector3.new(90, 13, 16), Position = Vector3.new(cx, 83, z), Color = base, Material = mat, Parent = model })
		local key = newPart({ Name = "ArchKeystone", Shape = Enum.PartType.Ball, Size = Vector3.new(22, 22, 22), Position = Vector3.new(cx, 96, z), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		table.insert(lit, key)
	elseif style == "ring" then
		newPart({ Name = "RingPylon", Size = Vector3.new(18, 38, 18), Position = Vector3.new(cx, 24, z), Color = base, Material = mat, Parent = model })
		-- the three rings are concentric and were all planted at the same y, which is the same
		-- coplanar-disc problem the arena floor had -- a 100-stud shimmering plate 82 studs up
		for i = 1, 3 do
			local s = 52 + i * 24
			local r = newPart({ Name = "LandmarkRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, s, s), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(cx, 80 + i * 0.02, z), Color = i == 2 and lighten(accent, 0.3) or accent, Material = Enum.Material.Neon, Transparency = 0.1 + i * 0.15, CanCollide = false, Parent = model })
			if i == 1 then
				table.insert(lit, r)
			end
		end
		local core = newPart({ Name = "LandmarkCore", Shape = Enum.PartType.Ball, Size = Vector3.new(26, 26, 26), Position = Vector3.new(cx, 80, z), Color = cfg.coreColor or lighten(accent, 0.4), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		table.insert(lit, core)
	elseif style == "crystal" then
		for i = 1, 7 do
			local h = math.random(38, 92)
			local w = math.random(8, 17)
			local c = newPart({ Name = "LandmarkCrystal", Size = Vector3.new(w, h, w), Orientation = Vector3.new(math.random(-13, 13), math.random(0, 360), math.random(-13, 13)), Position = Vector3.new(cx + math.random(-40, 40), 5 + h / 2, z + math.random(-18, 18)), Color = i % 2 == 0 and accent or lighten(accent, 0.4), Material = Enum.Material.Neon, Transparency = 0.12, Parent = model })
			if i <= 2 then
				table.insert(lit, c)
			end
		end
	elseif style == "tower" then
		local y = 5
		for i = 1, 4 do
			local w = 46 - i * 7
			newPart({ Name = "TowerTier", Size = Vector3.new(w, 19, w * 0.8), Position = Vector3.new(cx, y + 9.5, z), Color = i % 2 == 0 and base or darken(base, 0.18), Material = mat, Parent = model })
			newPart({ Name = "TowerBand", Size = Vector3.new(w + 5, 2.6, w * 0.8 + 5), Position = Vector3.new(cx, y + 19, z), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
			y = y + 19
		end
		local beacon = newPart({ Name = "TowerBeacon", Shape = Enum.PartType.Ball, Size = Vector3.new(17, 17, 17), Position = Vector3.new(cx, y + 10, z), Color = lighten(accent, 0.25), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		table.insert(lit, beacon)
	elseif style == "orb" then
		newPart({ Name = "OrbPylon", Shape = Enum.PartType.Cylinder, Size = Vector3.new(54, 16, 16), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(cx, 32, z), Color = base, Material = mat, Parent = model })
		local orb = newPart({ Name = "LandmarkOrb", Shape = Enum.PartType.Ball, Size = Vector3.new(46, 46, 46), Position = Vector3.new(cx, 82, z), Color = cfg.coreColor or accent, Material = Enum.Material.Neon, Transparency = cfg.orbTransparency or 0, CanCollide = false, Parent = model })
		table.insert(lit, orb)
		for i = 1, 2 do
			local s = 62 + i * 22
			newPart({ Name = "OrbHalo", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, s, s), Orientation = Vector3.new(i * 22, 0, 90), Position = Vector3.new(cx, 82, z), Color = lighten(accent, 0.35), Material = Enum.Material.Neon, Transparency = 0.35 + i * 0.15, CanCollide = false, Parent = model })
		end
	end

	for _, p in ipairs(lit) do
		addLight(p, accent, 42, 3)
	end

	-- two braziers framing the landmark so it reads as a site, not a lone prop
	for _, side in ipairs({ -1, 1 }) do
		newPart({ Name = "LandmarkPost", Size = Vector3.new(3.5, 42, 3.5), Position = Vector3.new(cx + side * postX, 21, z + postZ), Color = darken(base, 0.55), Material = Enum.Material.Metal, CanCollide = false, Parent = model })
		local flame = newPart({ Name = "LandmarkFlame", Shape = Enum.PartType.Ball, Size = Vector3.new(8, 8, 8), Position = Vector3.new(cx + side * postX, 45, z + postZ), Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(flame, accent, 28, 2)
	end
end

-- ===== IDOLS AND RUINS =====
-- The Desert's carved cat was the only figure standing anywhere in twenty zones, and it is the
-- single thing players point at. These two passes give every zone the same kind of company:
-- a couple of chunky animal idols and a cluster of broken pillars.
--
-- CARVED STONE, NOT BIOME COLOUR. Every other decoration layer is tinted from the zone palette,
-- which is right for ground litter (it should belong to the floor) and wrong for a monument -- a
-- green statue on green grass is a lump. These are pale stone everywhere, and the ONLY thing that
-- changes between zones is the painted accent and the glow in the eyes, so a Volcano idol and a
-- Nebula idol read as the same civilisation carving the same figures in different places.
local IDOL_STONE = Color3.fromRGB(228, 218, 198)
local IDOL_STONE_DARK = Color3.fromRGB(178, 168, 150)
local IDOL_SHADE = Color3.fromRGB(112, 105, 94)

-- Three silhouettes, cycled, so twenty zones are not twenty copies of one figure. Proportion does
-- the work rather than part count: a big head on a small body reads as a carved animal at 60 studs
-- and at 600, which is the whole trick the creature rigs use.
-- SIX NOW, NOT THREE, and each zone cycles a different three of them -- see addIdols. The last
-- three have no primitive builder of their own and fall through to "horned"; that only ever
-- happens if their mesh is missing, which is the same graceful-degradation rule the landmarks and
-- the boss rigs follow.
local IDOL_KINDS = { "cat", "owl", "horned", "guardian", "serpent", "totem" }

-- `u` is the HEAD DIAMETER, not the total height -- the head is the thing the eye measures a
-- carved animal by, and hanging every other number off it is what keeps the figure recognisable
-- when the same code is asked for a 60-stud one and a 160-stud one. Total height lands at ~2.4u.
local function buildIdol(model, cx, x, z, u, accent, kind)
	-- Built from a base CFrame rather than raw Positions so the whole figure can be turned. Local
	-- -Z is its face (the same convention the boss rigs use), and it is aimed INWARD -- at the centre
	-- square, which is the ground players actually stand on (Pet Shop, creature spawns, the walk
	-- between the two gates). A statue facing the boundary wall is scenery, not a landmark.
	--
	-- It used to aim at (x, ARRIVAL_Z) -- its OWN x, so straight down the Z axis -- and then turn a
	-- further 24-52 degrees AWAY from the street. Both halves were wrong. The turn was signed by
	-- `x >= 0`, i.e. WORLD x, and every zone but Forest sits at cx 1900, 3800, ... where that is
	-- true for every idol in the zone -- so they all leaned the same way. And outward was the wrong
	-- way to lean at all: a figure already parallel to the street, standing off to one side of a
	-- 1250-wide platform and then rotated further out, has nothing in front of it but wall.
	--
	-- Aiming at a jittered POINT rather than rotating off a fixed heading keeps the variety and
	-- cannot reintroduce the bug: the spread (+/-STREET_HALF across, +/-140 along) still gives every
	-- idol its own three-quarter angle and stops the dead-on stare that made them read as clones,
	-- but because the target is a PLACE, the gaze lands on the square wherever scatterPoint put the
	-- figure -- near side, far side, corner. No sign to get wrong.
	local here = Vector3.new(x, 0, z)
	local facing = Vector3.new(cx + math.random(-STREET_HALF, STREET_HALF), 0, math.random(-140, 140))
	if (facing - here).Magnitude < 1 then
		facing = here + Vector3.new(0, 0, 1)
	end
	local base = CFrame.new(here, facing)

	-- ===== THE STATUES ARE GENERATED MESHES NOW =====
	--
	-- Same argument that moved the bosses, the creatures, the landmarks and all 200 player skins off
	-- primitives: a figure assembled from spheres reads as a snowman however carefully its
	-- proportions are chosen, because a sphere carries no silhouette of its own and silhouette is
	-- the only thing legible at the range these are seen from. ServerStorage.IdolMeshes holds one
	-- generated model per kind (CAT, OWL, HORNED, GUARDIAN, SERPENT, TOTEM), each already sitting on
	-- a carved plinth of its own.
	--
	-- A kind with no mesh filed falls straight through to the block build below, unchanged -- so any
	-- subset can be filed and the world is never broken in between.
	local idolLib = ServerStorage:FindFirstChild("IdolMeshes")
	local idolTemplate = idolLib and idolLib:FindFirstChild("IdolMesh_" .. string.upper(kind))
	if idolTemplate then
		local figure = idolTemplate:Clone()
		local _, raw = figure:GetBoundingBox()
		-- MATCHED TO THE BLOCK BUILD'S HEIGHT, NOT TO `u`. `u` is a head diameter and the primitive
		-- figure lands at ~2.4u overall; scaling a mesh to `u` would leave a meshed zone's monuments
		-- less than half the size of the ones standing in the zone next door while the rollout is
		-- partial. Capped on width so a wide silhouette (the horned idol is the widest of the six)
		-- cannot overhang the footprint addIdols reserved for it.
		figure:ScaleTo(math.min((u * 2.4) / math.max(raw.Y, 1), (u * 1.9) / math.max(raw.X, raw.Z, 1)))
		for _, d in ipairs(figure:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				-- solid: these stand on ground players walk over, and the block build was collidable
				d.CanCollide = true
				-- PALE STONE IN EVERY BIOME, deliberately. A statue tinted to its zone is a green lump
				-- on green grass -- the same finding that made the block idols pale in the first place.
				d.Color = IDOL_STONE
				d.Material = Enum.Material.Sandstone
			end
		end
		figure.Name = "IdolFigure"
		figure.Parent = model
		local _, fit = figure:GetBoundingBox()

		-- A GROUND PAD UNDER IT. The mesh carries its own carved plinth, but a monument this size
		-- standing straight on grass has no contact shadow and reads as pasted onto the photograph.
		-- Two shrinking steps, exactly like the block build's, with the accent as a thin band
		-- SANDWICHED between them: a full-bright slab laid flat on the ground stops being a rim light
		-- and becomes the floor, which is the mistake the landmark plinth had to be rescued from.
		-- Deep enough to be a plinth. At 3.4 + 2.6 the two steps together were six studs under a
		-- 160-stud figure, which from anywhere but directly alongside is a grey rug, not a base.
		local padW = math.max(fit.X, fit.Z) * 1.24
		newPart({ Name = "IdolPad", Size = Vector3.new(padW, 7, padW),
			CFrame = base * CFrame.new(0, 3.5, 0), Color = IDOL_SHADE,
			Material = Enum.Material.Slate, Parent = model })
		newPart({ Name = "IdolPadTrim", Size = Vector3.new(padW * 0.95, 1.6, padW * 0.95),
			CFrame = base * CFrame.new(0, 7.8, 0), Color = accent, Material = Enum.Material.Neon,
			CanCollide = false, Parent = model })
		newPart({ Name = "IdolPadStep", Size = Vector3.new(padW * 0.86, 6, padW * 0.86),
			CFrame = base * CFrame.new(0, 11.6, 0), Color = IDOL_STONE_DARK,
			Material = Enum.Material.Slate, Parent = model })
		-- stood on top of the steps, facing the same way the block build faces (local -Z)
		figure:PivotTo(base * CFrame.new(0, 14.4 + fit.Y / 2, 0))

		-- Two braziers at the front corners. The block idol got its point of focus from lit eyes; a
		-- generated mesh has no lit anything, so without these the statue goes dark at night and the
		-- zone loses the landmark it is navigated by.
		-- SMALL. At u * 0.28 the bowl is a 22-stud ball of full-bright Neon standing at the statue's
		-- feet -- from the street it is a white blob with a monument behind it, which is the wrong way
		-- round. A brazier is a detail that says the site is tended; the statue is the thing being
		-- looked at. The light does the work, not the size of the bulb.
		for _, sx in ipairs({ -1, 1 }) do
			newPart({ Name = "IdolBrazierPost", Size = Vector3.new(u * 0.11, u * 0.4, u * 0.11),
				CFrame = base * CFrame.new(sx * padW * 0.46, u * 0.2, -padW * 0.4),
				Color = IDOL_STONE_DARK, Material = Enum.Material.Slate, CanCollide = false, Parent = model })
			-- UNIFORM on all three axes: a Shape = Ball part is drawn as a sphere of its SMALLEST
			-- axis and silently throws the other two away -- see the note below, which is what that
			-- bug did to this whole figure once already.
			local bowl = newPart({ Name = "IdolBrazier", Shape = Enum.PartType.Ball,
				Size = Vector3.new(u * 0.15, u * 0.15, u * 0.15),
				CFrame = base * CFrame.new(sx * padW * 0.46, u * 0.44, -padW * 0.4),
				Color = accent, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
			addLight(bowl, accent, u * 1.4, 1.8)
		end
		return
	end

	-- A Part with Shape = Ball RENDERS A SPHERE OF ITS SMALLEST AXIS -- it discards a non-uniform
	-- Size without a word, and every proportion in this figure was authored as an ellipsoid. All of
	-- them were being thrown away: the 0.5u muzzle came out as a 0.38u pellet buried in the skull,
	-- the 1.16u mane as a 0.56u ball hidden inside the head, the 0.4u paws as 0.16u stubs. What was
	-- left standing on the plinth was a big ball on a smaller ball -- the exact snowman the comments
	-- below say was designed out. And the ears, tufts and wings are Blocks, so THEY kept their full
	-- size, which is why they read as pale slabs floating around a head too small to reach them.
	-- A Block wearing a SpecialMesh of MeshType Sphere scales on all three axes, so Shape = Ball is
	-- translated here and every number below means what it says again.
	local function piece(name, opts)
		opts.Name = name
		opts.Parent = model
		opts.CFrame = base * opts.CFrame
		if opts.Color == nil then opts.Color = IDOL_STONE end
		if opts.Material == nil then opts.Material = Enum.Material.Sandstone end
		local ball = opts.Shape == Enum.PartType.Ball
		if ball then opts.Shape = nil end
		local p = newPart(opts)
		if ball then
			local m = Instance.new("SpecialMesh")
			m.MeshType = Enum.MeshType.Sphere
			m.Parent = p
		end
		return p
	end

	-- plinth: two shrinking slabs, so the figure reads as placed rather than dropped
	piece("IdolPlinth", { Size = Vector3.new(u * 1.7, u * 0.16, u * 1.7), CFrame = CFrame.new(0, u * 0.08, 0), Color = IDOL_SHADE, Material = Enum.Material.Slate })
	piece("IdolPlinthStep", { Size = Vector3.new(u * 1.36, u * 0.14, u * 1.36), CFrame = CFrame.new(0, u * 0.23, 0), Color = IDOL_STONE_DARK, Material = Enum.Material.Slate })
	local floor = u * 0.3

	-- SEATED, AND SMALLER THAN THE HEAD. The first pass gave body and head almost the same
	-- diameter and the result was a snowman -- three stacked spheres read as a snowman at any size.
	-- The reference carving is a big head on a small crouched body, so the body is 0.72u against
	-- the head's 1.0u and it is half-buried under it.
	piece("IdolBody", { Shape = Enum.PartType.Ball, Size = Vector3.new(u * 0.78, u * 0.66, u * 0.72), CFrame = CFrame.new(0, floor + u * 0.3, 0) })
	for _, side in ipairs({ -1, 1 }) do
		piece("IdolPaw", { Shape = Enum.PartType.Ball, Size = Vector3.new(u * 0.24, u * 0.16, u * 0.4),
			CFrame = CFrame.new(side * u * 0.26, floor + u * 0.08, -u * 0.3), Color = IDOL_STONE_DARK })
	end

	local headY = floor + u * 0.86
	piece("IdolHead", { Shape = Enum.PartType.Ball, Size = Vector3.new(u, u * 0.95, u * 0.92), CFrame = CFrame.new(0, headY, 0) })
	-- The face has to carry at this size or the head is just a boulder: a muzzle that actually
	-- protrudes, a dark nose on the end of it, and a mouth line under that.
	piece("IdolMuzzle", { Shape = Enum.PartType.Ball, Size = Vector3.new(u * 0.5, u * 0.38, u * 0.4),
		CFrame = CFrame.new(0, headY - u * 0.19, -u * 0.42), Color = IDOL_STONE })
	piece("IdolNose", { Shape = Enum.PartType.Ball, Size = Vector3.new(u * 0.16, u * 0.13, u * 0.12),
		CFrame = CFrame.new(0, headY - u * 0.13, -u * 0.58), Color = IDOL_SHADE, CanCollide = false })
	piece("IdolMouth", { Size = Vector3.new(u * 0.04, u * 0.11, u * 0.05),
		CFrame = CFrame.new(0, headY - u * 0.27, -u * 0.56), Color = IDOL_SHADE, CanCollide = false })

	-- eyes: the only lit parts, so the figure keeps a point of focus at range
	for _, side in ipairs({ -1, 1 }) do
		local eye = piece("IdolEye", { Shape = Enum.PartType.Ball, Size = Vector3.new(u * 0.17, u * 0.17, u * 0.12),
			CFrame = CFrame.new(side * u * 0.23, headY + u * 0.08, -u * 0.42),
			Color = accent, Material = Enum.Material.Neon, CanCollide = false })
		if side == 1 then
			addLight(eye, accent, u * 1.2, 1.6)
		end
	end

	-- painted markings: on the FOREHEAD and across the brow, which is where the carving this is
	-- modelled on wears them. The first pass stood the stripe on top of the skull like an aerial.
	piece("IdolMark", { Size = Vector3.new(u * 0.09, u * 0.26, u * 0.06),
		CFrame = CFrame.new(0, headY + u * 0.3, -u * 0.36), Color = accent, Material = Enum.Material.SmoothPlastic, CanCollide = false })
	for _, side in ipairs({ -1, 1 }) do
		piece("IdolStripe", { Size = Vector3.new(u * 0.07, u * 0.19, u * 0.06),
			CFrame = CFrame.new(side * u * 0.15, headY + u * 0.32, -u * 0.32) * CFrame.Angles(0, 0, math.rad(side * 22)),
			Color = accent, Material = Enum.Material.SmoothPlastic, CanCollide = false })
	end
	piece("IdolCollar", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(u * 0.09, u * 0.62, u * 0.62),
		CFrame = CFrame.new(0, floor + u * 0.52, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = accent, Material = Enum.Material.SmoothPlastic, CanCollide = false })

	if kind == "cat" then
		-- Ears are a TAPERED STACK, not a Wedge. A Roblox wedge slopes along its own +Z and lands
		-- somewhere unintended the moment the part is also yawed -- which is what turned the first
		-- pass's ears into flat slabs lying away from the skull. Two blocks and a ball are dumb,
		-- predictable, and read as a pointed ear from every angle.
		-- Sunk into the skull and barely splayed. At 13 degrees they swung apart like a rabbit's and
		-- their lower corners lifted off the sphere, which is what read as two slabs floating over
		-- the head; 6 is enough to stop them looking like a pair of chimneys.
		for _, side in ipairs({ -1, 1 }) do
			local root = CFrame.new(side * u * 0.24, headY + u * 0.3, 0) * CFrame.Angles(0, 0, math.rad(side * -6))
			piece("IdolEar", { Size = Vector3.new(u * 0.28, u * 0.34, u * 0.22), CFrame = root })
			piece("IdolEarTip", { Size = Vector3.new(u * 0.17, u * 0.26, u * 0.15), CFrame = root * CFrame.new(0, u * 0.26, 0) })
			piece("IdolEarInner", { Size = Vector3.new(u * 0.14, u * 0.26, u * 0.05),
				CFrame = root * CFrame.new(0, u * 0.06, -u * 0.1), Color = accent, Material = Enum.Material.SmoothPlastic, CanCollide = false })
		end
		piece("IdolTail", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(u * 0.62, u * 0.13, u * 0.13),
			CFrame = CFrame.new(u * 0.4, floor + u * 0.2, u * 0.28) * CFrame.Angles(0, math.rad(28), math.rad(68)), Color = IDOL_STONE_DARK })
	elseif kind == "owl" then
		for _, side in ipairs({ -1, 1 }) do
			piece("IdolBrow", { Size = Vector3.new(u * 0.34, u * 0.09, u * 0.1),
				CFrame = CFrame.new(side * u * 0.22, headY + u * 0.24, -u * 0.38) * CFrame.Angles(0, 0, math.rad(side * 15)), Color = IDOL_STONE_DARK })
			piece("IdolTuft", { Size = Vector3.new(u * 0.16, u * 0.3, u * 0.14),
				CFrame = CFrame.new(side * u * 0.34, headY + u * 0.5, 0) * CFrame.Angles(0, 0, math.rad(side * -26)) })
			piece("IdolWing", { Size = Vector3.new(u * 0.13, u * 0.56, u * 0.34),
				CFrame = CFrame.new(side * u * 0.42, floor + u * 0.34, u * 0.02) * CFrame.Angles(0, 0, math.rad(side * 10)) })
		end
		piece("IdolBeak", { Size = Vector3.new(u * 0.14, u * 0.2, u * 0.16),
			CFrame = CFrame.new(0, headY - u * 0.16, -u * 0.46) * CFrame.Angles(math.rad(20), 0, 0), Color = accent, Material = Enum.Material.SmoothPlastic })
	else -- "horned"
		for _, side in ipairs({ -1, 1 }) do
			piece("IdolHorn", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(u * 0.46, u * 0.16, u * 0.16),
				CFrame = CFrame.new(side * u * 0.36, headY + u * 0.34, u * 0.04) * CFrame.Angles(0, 0, math.rad(side * -58)), Color = IDOL_STONE_DARK })
			-- carries on from the horn instead of hanging off it -- as a glowing ball at the end of a
			-- gap it read as an orb floating beside the head
			piece("IdolHornTip", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(u * 0.2, u * 0.12, u * 0.12),
				CFrame = CFrame.new(side * u * 0.53, headY + u * 0.5, u * 0.04) * CFrame.Angles(0, 0, math.rad(side * -58)),
				Color = accent, Material = Enum.Material.Neon, CanCollide = false })
			piece("IdolTusk", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(u * 0.22, u * 0.08, u * 0.08),
				CFrame = CFrame.new(side * u * 0.13, headY - u * 0.3, -u * 0.36) * CFrame.Angles(0, 0, math.rad(side * 66)), Color = IDOL_STONE })
		end
		piece("IdolMane", { Shape = Enum.PartType.Ball, Size = Vector3.new(u * 1.16, u * 0.56, u * 0.8),
			CFrame = CFrame.new(0, headY - u * 0.34, u * 0.06), Color = IDOL_STONE_DARK })
	end
end

-- A few of them per zone, well apart. scatterPoint already keeps every reservation on the platform
-- -- the street, both gate mouths, the boss arena and the centre square -- so placement is one call.
local function addIdols(model, cx, cfg)
	local count = cfg.count or 3
	for i = 1, count do
		-- `u` is the head diameter and the finished figure measures ~1.9u, so this puts them at
		-- 133..167 studs -- roughly DOUBLE what they were, and taller than the boss standing in the
		-- same zone. At 57..72 they read as garden ornaments: big next to a player, but a player is
		-- the smallest thing on the platform and everything else out there (the 140-stud walls, the
		-- Guardian Titan, a 75-120 stud boss) dwarfed them, so they registered as clutter rather than
		-- as monuments. The Titan is still the thing you navigate by -- it is several times this.
		--
		-- The plinth is 1.7u, so the footprint goes to ~120-150 studs. That fits: scatterPoint keeps
		-- them off the street, both gate mouths, the boss arena and the centre square, and the scatter
		-- band itself is only 350 studs out of a 625-stud half-platform.
		local u = math.random(70, 88)
		-- The size is picked BEFORE the position because the position depends on it. The plinth is
		-- 1.7u across, so half of it is 0.85u, and the tail/wings/horns reach a little past that --
		-- 0.95u is the honest footprint. Handing it to scatterPoint is what keeps a statue this big
		-- out of the walkway: the reservations are checked against the returned point, so before this
		-- an idol could sit legally at |x| = STREET_HALF and still lay 27 studs of stone across the
		-- middle of the street.
		-- 1.15u, not 0.95u. The plinth is 1.7u across, so its half-width is 0.85u and 0.95 looks like
		-- it clears -- but scatterPoint tests the returned POINT, and the props that land at exactly
		-- that radius have bodies of their own: a crate stack is up to 11 studs across with 3 more of
		-- jitter, which is about 0.1u at these sizes. It overhung by precisely that margin, which is
		-- why 369 props were still ending up inside plinths after the ordering fix.
		--
		-- 1.25u, NOT 1.15u -- THE RESERVATION IS A CIRCLE AND THE PLINTH IS A SQUARE. Every
		-- reservation in this file is a radius, but the sweep at the end of the zone loop tests a
		-- RECTANGLE (`abs(d.X) < size.X / 2 and abs(d.Z) < size.Z / 2`). A circle of 0.85u inscribed
		-- in a square of half-width 0.85u leaves the four corners out to 0.85u * sqrt(2) = 1.202u
		-- unguarded, so anything sitting in a corner passes the placement test honestly and is then
		-- destroyed by the sweep. That is how two zones ended up with an arrival BOARD and no post
		-- underneath it -- the exact "this just hangs in the air" report the post exists to answer.
		-- 1.25u covers the half-diagonal and keeps the 0.1u prop-body margin the note above earned.
		local x, z = scatterPoint(cx, nil, nil, u * 1.25)
		-- claim the ground before the NEXT idol, before the ruins, and before the biome builder
		-- scatters its own trees and rocks -- buildBiomeBase runs first in all twenty of them
		reserveScatter(x, z, u * 1.25)
		-- WHICH THREE, AND NOT THE SAME THREE IN EVERY ZONE. Cycling the list from index 1 everywhere
		-- stood the identical figures in the identical order on all twenty platforms, which is a large
		-- part of why one zone looks like the next. Offsetting the cycle by the zone's own key gives
		-- each zone its own trio out of the six and costs nothing per zone to configure.
		local off = 0
		if ACTIVE_ZONE_KEY then
			for k = 1, #ACTIVE_ZONE_KEY do off = (off * 31 + string.byte(ACTIVE_ZONE_KEY, k)) % 997 end
		end
		buildIdol(model, cx, x, z, u, cfg.accent, IDOL_KINDS[((off + i - 1) % #IDOL_KINDS) + 1])
	end
end

-- Broken pillars. Cheap, reads as history, and being pale stone it works unchanged in all twenty
-- biomes -- which is the point: one pass, no per-zone authoring.
local function addRuins(model, cx, cfg)
	for _ = 1, (cfg.count or 2) do
		-- pillars ring the scatter point out to r = 44, plus their own 13-stud width
		-- same margin as the idols: the pillars ring out to r = 44 plus their own 13-stud width, and
		-- whatever lands against that circle brings its own body with it
		local ox, oz = scatterPoint(cx, nil, nil, 64)
		reserveScatter(ox, oz, 64)
		local pillars = math.random(3, 5)
		for i = 1, pillars do
			local a = (i / pillars) * math.pi * 2 + math.random() * 0.6
			local r = math.random(26, 44)
			local x, z = ox + math.cos(a) * r, oz + math.sin(a) * r
			-- every pillar snapped off at a different height is what makes it read as a ruin rather
			-- than as a colonnade
			local h = math.random(16, 52)
			newPart({ Name = "RuinPillar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, 13, 13),
				Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, h / 2, z),
				Color = i % 2 == 0 and IDOL_STONE or IDOL_STONE_DARK, Material = Enum.Material.Sandstone, Parent = model })
			newPart({ Name = "RuinPillarBase", Size = Vector3.new(18, 3, 18), Position = Vector3.new(x, 1.5, z),
				Color = IDOL_SHADE, Material = Enum.Material.Slate, Parent = model })
		end
		-- one toppled drum on the ground, and a lit rune slab in the middle of the circle
		newPart({ Name = "RuinFallen", Shape = Enum.PartType.Cylinder, Size = Vector3.new(34, 12, 12),
			Orientation = Vector3.new(0, math.random(0, 360), 0), Position = Vector3.new(ox + math.random(-18, 18), 6, oz + math.random(-18, 18)),
			Color = IDOL_STONE_DARK, Material = Enum.Material.Sandstone, Parent = model })
		local rune = newPart({ Name = "RuinRune", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 26, 26),
			Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(ox, 0.7, oz),
			Color = cfg.accent, Material = Enum.Material.Neon, Transparency = 0.15, CanCollide = false, CastShadow = false, Parent = model })
		addLight(rune, cfg.accent, 34, 2)
	end
end

-- ============================================================================
-- TERRAIN: the valley walls
-- ============================================================================
-- Every zone was a flat 1250 x 1150 slab with props standing on it. The reference this is built
-- against is a VALLEY -- flat grass down the middle where you actually play, rising through
-- terraced shelves and cliff faces at the sides, with water falling off them into a pool.
--
-- WHY THE MIDDLE STAYS FLAT. Every scattered prop in this file -- trees, rocks, idols, creature
-- spawns, the shops -- is placed at y = 0 and has no idea what the ground beneath it is doing.
-- Raising ground where those land would bury half of them and leave the other half in the air.
-- So DECO_SPREAD_X was pulled in to 400 and the terraces live in the outer band from TERRAIN_INNER
-- to the wall, which nothing else ever touches. The playable valley is unchanged; the horizon is
-- completely different.
--
-- All of it is part-built rather than Roblox Terrain: the world is a 36,000-stud strip with
-- streaming on, and voxel terrain neither streams the same way nor matches the chunky look the
-- rest of the game is cut from.
local TERRAIN_INNER = 415        -- where the valley floor ends and the first cliff begins
local TERRAIN_OUTER = 625        -- the platform edge, where the boundary wall stands

-- Per-zone character. Anything absent falls back to the defaults in buildTerrain, so a new zone
-- costs nothing and the twenty here are genuinely different rather than recoloured copies of one
-- profile: tier counts, step heights, whether there is water at the foot, how rocky it is.
-- STEP HEIGHTS ARE ~1.7x WHAT THEY WERE. At 12-20 studs a step was shorter than the props standing
-- on it and the band read as three long ledges mown into a lawn rather than as a valley wall --
-- and a waterfall pouring down a 15-stud riser has no room to look like falling water. Totals now
-- run 66-128 studs against a 180-stud boundary wall, so the terraces climb most of the way up it
-- without ever poking over.
-- ===== NO TIER MAY BE LOWER THAN A MAXED JUMP (item 19, 2026-08-11) =====
--
-- `rise` is not just a look. A Roblox jump reaches `power^2 / (2 * 196.2)`, and GameConfig's
-- MaxJumpPower of 92 puts a fully upgraded player's apex at **21.6 studs** -- so every shelf built
-- at or under that was reachable by walking to the cliff and holding space, with the staircase and
-- the whole climb it gates reduced to decoration. Raised creatures are the only Evolution Shard
-- source in the game, so the climb is the price of the currency.
--
-- Five zones were at or under it (DreamDimension 20, Ocean 22, Wormhole 22, Galaxy 24, TimeRift 25)
-- and are now 26, which clears the apex by 4.4 studs. **26 is the floor for any new zone**; if
-- MaxJumpPower ever rises, this number has to rise with it.
local TERRAIN_PROFILE = {
	-- `trees` is the CHANCE (0..1) that a given terrace segment gets a conifer, not a count: the
	-- segments already vary in size and position, so a probability spreads them unevenly where a
	-- count would plant the same number on every shelf. Absent = no trees, which is the right
	-- answer for the moon, the void and everything abstract.
	Forest          = { tiers = 3, rise = 26, water = true,  falls = 2, rocks = 9, rockSize = { 14, 30 }, trees = 0.85 },
	-- an OASIS, not a river: the one dry-looking biome that still earns water, and the only reason
	-- the Desert terraces are not a bare sand shelf from end to end
	Desert          = { tiers = 2, rise = 36, water = true,  falls = 1, rocks = 14, rockSize = { 18, 38 } },
	Ocean           = { tiers = 3, rise = 26, water = true,  falls = 3, rocks = 6, rockSize = { 12, 26 }, trees = 0.4 },
	Volcano         = { tiers = 3, rise = 34, water = true,  falls = 2, rocks = 14, rockSize = { 16, 40 } },
	Moon            = { tiers = 2, rise = 30, water = false, falls = 0, rocks = 16, rockSize = { 20, 44 } },
	Mars            = { tiers = 3, rise = 32, water = false, falls = 0, rocks = 13, rockSize = { 18, 40 } },
	Galaxy          = { tiers = 4, rise = 26, water = true,  falls = 2, rocks = 7, rockSize = { 12, 28 }, trees = 0.3 },
	BlackHole       = { tiers = 2, rise = 46, water = false, falls = 0, rocks = 10, rockSize = { 22, 46 } },
	Multiverse      = { tiers = 4, rise = 26, water = true,  falls = 3, rocks = 8, rockSize = { 14, 30 }, trees = 0.35 },
	Nebula          = { tiers = 3, rise = 28, water = true,  falls = 2, rocks = 9, rockSize = { 14, 32 } },
	Wormhole        = { tiers = 4, rise = 26, water = false, falls = 0, rocks = 11, rockSize = { 16, 34 } },
	QuantumRealm    = { tiers = 3, rise = 30, water = true,  falls = 2, rocks = 8, rockSize = { 12, 30 } },
	TimeRift        = { tiers = 4, rise = 26, water = true,  falls = 3, rocks = 9, rockSize = { 14, 32 } },
	AntimatterZone  = { tiers = 2, rise = 44, water = false, falls = 0, rocks = 15, rockSize = { 20, 44 } },
	DreamDimension  = { tiers = 4, rise = 26, water = true,  falls = 3, rocks = 6, rockSize = { 10, 26 }, trees = 0.5 },
	MirrorUniverse  = { tiers = 3, rise = 30, water = true,  falls = 2, rocks = 8, rockSize = { 14, 32 } },
	VoidExpanse     = { tiers = 2, rise = 50, water = false, falls = 0, rocks = 12, rockSize = { 22, 48 } },
	CelestialThrone = { tiers = 4, rise = 27, water = true,  falls = 3, rocks = 7, rockSize = { 14, 30 }, trees = 0.3 },
	Singularity     = { tiers = 3, rise = 34, water = false, falls = 0, rocks = 13, rockSize = { 18, 40 } },
	AbsolutePlane   = { tiers = 4, rise = 32, water = true,  falls = 4, rocks = 10, rockSize = { 16, 36 } },
}

-- One side of one zone. `side` is -1 or 1; everything is mirrored, and the two sides are given
-- different random seeds by the caller so a zone is not symmetrical.
--
-- ===== WHY THE TIERS ARE STACKED THE WAY THEY ARE (READ BEFORE EDITING) =====
-- The first cut gave every tier a slab that ran from its own inner edge all the way out to the
-- platform rim AND stood on the ground -- so tier 2 physically contained the whole outer half of
-- tier 1, tier 3 contained both, and every pair of tiers shared an exactly coplanar outer face,
-- end face and underside. Coplanar faces ARE z-fighting: the depth buffer cannot separate two
-- surfaces at the same depth, so the renderer flickers between them as the camera moves. That is
-- the striped shimmer that covered the cliffs. The cliff face and the lip had the same defect
-- against their own tier -- both were placed flush with the slab's front face.
--
-- Nothing is stacked inside anything else now. Tier N is a slab exactly `rise` thick sitting ON
-- tier N-1 and reaching the rim, so consecutive tiers TOUCH but never overlap, and every
-- decorative piece bolted to a face is pushed a stud or two PROUD of it. Both rules are
-- load-bearing: undo either one and the shimmer comes straight back.
local function buildValleySide(model, zone, cx, side, p)
	-- LOOKED UP AGAIN HERE, and it has to be. `addRockRampart` declares a `cliffFace` of its own,
	-- but that is a local inside THAT function -- from here the name resolves to a nil global, the
	-- outcrop block below is skipped in silence and nothing is logged. Exactly the shape of the
	-- villMesh bug: it compiles, it runs, it does nothing.
	local cliffLib = ServerStorage:FindFirstChild("PropMeshes")
	local cliffFace = cliffLib and cliffLib:FindFirstChild("Cliff_" .. zone.key)
	-- the shared water set, same folder. Declared HERE and not at the cascade loop for the reason
	-- written above cliffFace: a local belonging to another function reads as a nil global from
	-- inside this one, silently.
	local waterLib = cliffLib

	local grass = zone.groundColor
	-- The cliff is NOT the ground colour. Rock reads as rock because it is a different material and
	-- a different hue -- a cliff tinted from green grass is a green wall, which is what the first
	-- attempt at this looked like. It carries a quarter of the zone's tint so a Volcano cliff and a
	-- Moon cliff are still recognisably from their own worlds.
	local rock = Color3.fromRGB(150, 128, 104):Lerp(zone.groundColor, 0.25)
	local rockLit = lighten(rock, 0.16)
	local rockDark = darken(rock, 0.3)
	local moss = Color3.fromRGB(104, 164, 82):Lerp(zone.groundColor, 0.45)
	local accent = vivid(zone.accentColor)
	local ground = GROUND_MATERIAL[zone.key] or Enum.Material.Grass
	local band = (TERRAIN_OUTER - TERRAIN_INNER) / p.tiers
	local halfZ = PLATFORM_DEPTH / 2

	-- the two numbers every piece below is placed from: where tier N's riser stands, and how high
	-- you are once you have walked up onto it
	local function riserX(tier) return TERRAIN_INNER + band * (tier - 1) end
	local function treadY(tier) return p.rise * tier end

	-- ---- A BOULDER, AS A PILE OF ROTATED SLABS. The reference art's rocks are big rounded-off
	-- CHUNKS with visible flat faces, not spheres -- a sphere is a marble however large you make it,
	-- and that is what the old single-ball rocks read as. Three or four blocks yawed to different
	-- angles and half-sunk into one another give facets that catch the light separately, which is
	-- what makes a lump of grey read as stone. The dark slab underneath is the contact shadow; it is
	-- the difference between a rock sitting on the ground and one hovering over it.
	local function boulder(x, y, z, s)
		newPart({ Name = "ValleyRockBase", Size = Vector3.new(s * 1.3, s * 0.16, s * 1.16),
			Orientation = Vector3.new(0, math.random(0, 360), 0),
			Position = Vector3.new(x, y + s * 0.05, z), Color = rockDark,
			Material = Enum.Material.Slate, CanCollide = false, CastShadow = false, Parent = model })

		-- the main mass: a wide slab with a tilt, so its top face is never level with the ground
		newPart({ Name = "ValleyRock", Size = Vector3.new(s * 1.04, s * 0.62, s * 0.94),
			CFrame = CFrame.new(x, y + s * 0.3, z)
				* CFrame.Angles(math.rad(math.random(-9, 9)), math.rad(math.random(0, 360)), math.rad(math.random(-9, 9))),
			Color = rock, Material = Enum.Material.Rock, Parent = model })

		-- a smaller block riding on top and off-centre -- this is the piece that turns a slab into a
		-- rock, because it breaks the silhouette's top edge
		newPart({ Name = "ValleyRockCap", Size = Vector3.new(s * 0.72, s * 0.44, s * 0.66),
			CFrame = CFrame.new(x + s * 0.1, y + s * 0.66, z - s * 0.08)
				* CFrame.Angles(math.rad(math.random(-12, 12)), math.rad(math.random(0, 360)), math.rad(math.random(-12, 12))),
			Color = rockLit, Material = Enum.Material.Rock, CanCollide = false, Parent = model })

		-- two chips fallen off it, out on the ground
		for i = 1, 2 do
			local t = s * (i == 1 and 0.44 or 0.3)
			local a = math.random() * math.pi * 2
			newPart({ Name = "ValleyRockChip", Size = Vector3.new(t, t * 0.56, t * 0.84),
				CFrame = CFrame.new(x + math.cos(a) * s * 0.68, y + t * 0.26, z + math.sin(a) * s * 0.68)
					* CFrame.Angles(0, math.rad(math.random(0, 360)), math.rad(math.random(-22, 22))),
				Color = i == 1 and rock or rockDark, Material = Enum.Material.Rock, CanCollide = false, Parent = model })
		end
	end

	-- ---- three blades from one point. One blade is a spike sticking out of the ground; three at
	-- different heights and leans is a clump, and a clump is the smallest thing that reads as
	-- vegetation from the street.
	local function tuft(x, y, z, h, color, material)
		for i = 1, 3 do
			local bladeH = h * (i == 2 and 1 or math.random(58, 78) / 100)
			newPart({ Name = "TerraceTuft", Size = Vector3.new(2.4, bladeH, 2.4),
				CFrame = CFrame.new(x + (i - 2) * 2.6, y + bladeH * 0.46, z + math.random(-2, 2))
					* CFrame.Angles(0, math.rad(math.random(0, 180)), math.rad(math.random(-26, 26))),
				Color = color, Material = material, CanCollide = false, CastShadow = false, Parent = model })
		end
	end

	-- ---- A MUSHROOM: stem, cap, and pale spots on the cap. In the reference these are the single
	-- most repeated piece of decoration on the hillsides and they are what stops a green shelf
	-- reading as a mown lawn -- they are small, brightly coloured and there are a LOT of them, which
	-- is the opposite of how the rest of this file places props.
	local MUSHROOM_CAPS = {
		Color3.fromRGB(226, 74, 82), Color3.fromRGB(96, 176, 236),
		Color3.fromRGB(232, 158, 88), Color3.fromRGB(214, 106, 196),
	}
	local function mushroom(x, y, z, s)
		local cap = MUSHROOM_CAPS[math.random(1, #MUSHROOM_CAPS)]
		newPart({ Name = "TerraceShroomStem", Size = Vector3.new(s * 0.32, s * 0.8, s * 0.32),
			CFrame = CFrame.new(x, y + s * 0.4, z) * CFrame.Angles(0, 0, math.rad(math.random(-8, 8))),
			Color = Color3.fromRGB(244, 236, 214), Material = Enum.Material.SmoothPlastic,
			CanCollide = false, CastShadow = false, Parent = model })
		local head = newPart({ Name = "TerraceShroomCap", Shape = Enum.PartType.Ball,
			Size = Vector3.new(s * 1.1, s * 0.66, s * 1.1),
			Position = Vector3.new(x, y + s * 0.86, z),
			Color = cap, Material = Enum.Material.SmoothPlastic,
			CanCollide = false, CastShadow = false, Parent = model })
		-- two pale dots. Without them the cap is a coloured pebble; with them it is unmistakably a
		-- toadstool, and it costs two parts.
		for i = 1, 2 do
			local a = math.random() * math.pi * 2
			newPart({ Name = "TerraceShroomDot", Shape = Enum.PartType.Ball,
				Size = Vector3.new(s * 0.26, s * 0.26, s * 0.26),
				Position = Vector3.new(x + math.cos(a) * s * 0.34, y + s * 1.06, z + math.sin(a) * s * 0.34),
				Color = Color3.fromRGB(252, 248, 238), Material = Enum.Material.SmoothPlastic,
				CanCollide = false, CastShadow = false, Parent = model })
		end
		return head
	end

	-- ---- A CONIFER, as a stepped cone. Roblox has no cone primitive and a stack of spheres reads
	-- as a snowman, so this is three shrinking blocks yawed 30 degrees apart -- from any angle the
	-- staggered corners give a ragged conical silhouette, which is what the chunky style wants
	-- anyway. Only zones whose profile asks for trees get them: a pine on the Moon is worse than
	-- bare rock.
	local function conifer(x, y, z, h)
		-- THE ZONE'S OWN TREE, when one is filed. The stepped-block cone below was written when
		-- nothing in this game was a mesh; against the meshed canopies now standing on the valley
		-- floor thirty studs away it reads as a stack of dark green boxes on the skyline -- and the
		-- terraces are exactly where the eye goes, because they are the horizon from the street.
		--
		-- Prop_<zone>_CANOPY is the same tree the floor uses, so the slope and the flat agree.
		local treeLib = ServerStorage:FindFirstChild("PropMeshes")
		local treeMesh = treeLib and treeLib:FindFirstChild("Prop_" .. zone.key .. "_CANOPY")
		if treeMesh then
			local tree = treeMesh:Clone()
			local _, raw = tree:GetBoundingBox()
			-- built to the height the cone was asked for, capped on width: these stand on a shelf
			-- only `band` studs deep and a wide canopy would hang over the drop
			tree:ScaleTo(math.min(h / math.max(raw.Y, 0.1), (h * 0.7) / math.max(raw.X, raw.Z, 0.1)))
			for _, part in ipairs(tree:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Anchored = true
					-- scenery on a ledge the player cannot reach; colliding costs and buys nothing
					part.CanCollide = false
				end
			end
			tree.Name = "TerraceTree"
			tree.Parent = model
			-- PivotTo and not seatModel: seatModel drops to y = 0 and this one stands on a shelf at y.
			-- Measured after scaling so the trunk foot lands on the shelf rather than in it.
			local _, fit = tree:GetBoundingBox()
			tree:PivotTo(CFrame.new(x, y + fit.Y / 2, z) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
			return
		end

		local w = h * 0.46
		newPart({ Name = "TerraceTrunk", Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(h * 0.3, w * 0.22, w * 0.22), Orientation = Vector3.new(0, 0, 90),
			Position = Vector3.new(x, y + h * 0.14, z),
			Color = Color3.fromRGB(112, 76, 48), Material = Enum.Material.Wood,
			CanCollide = false, CastShadow = false, Parent = model })
		local needle = Color3.fromRGB(46, 116, 62):Lerp(zone.groundColor, 0.2)
		for i = 1, 3 do
			local f = (i - 1) / 3
			newPart({ Name = "TerraceCanopy", Size = Vector3.new(w * (1 - f * 0.42), h * 0.34, w * (1 - f * 0.42)),
				CFrame = CFrame.new(x, y + h * (0.3 + f * 0.28), z) * CFrame.Angles(0, math.rad(i * 30), 0),
				Color = i == 2 and lighten(needle, 0.1) or needle, Material = Enum.Material.Grass,
				CanCollide = false, CastShadow = false, Parent = model })
		end
	end

	-- ===== THE EDGE MEANDERS: ONE SLAB PER SEGMENT, NOT ONE PER TIER =====
	-- Cut as a single 1150-stud slab per tier, the three terraces were three exactly parallel lines
	-- running the whole depth of the zone -- "one right behind the other, like they are in a row",
	-- which is a staircase and not a hillside. The reference art has no straight edge anywhere: each
	-- shelf bulges and retreats, so from any angle you see a different amount of each one.
	--
	-- So each tier is cut into SEGMENTS along Z and every segment picks its own inner edge. The
	-- jitter is OUTWARD ONLY (`riserX(tier) + j`, j >= 0) and that is not a style choice: the pool
	-- and the valley floor's props are laid out against TERRAIN_INNER, so a segment allowed to creep
	-- inward would stand in the water.
	--
	-- Anything that has to meet the cliff later (the waterfalls) must ask `edgeAt(tier, z)` rather
	-- than `riserX(tier)`, or it hangs in mid-air over whichever segment happens to have pulled back.
	-- SEGMENT COUNT IS PER ZONE, NOT GLOBAL. Five everywhere meant every zone cut its hillside at
	-- the same five places, so the twenty banks were the same shape in twenty colours -- and the
	-- segment boundaries lined up across the whole 36,000-stud strip. Derived from the zone key so
	-- it is stable across rebuilds and needs no entry in TERRAIN_PROFILE.
	local keyHash = 0
	for i = 1, #zone.key do keyHash = (keyHash * 31 + string.byte(zone.key, i)) % 9973 end
	local SEGMENTS = 5 + (keyHash % 4)          -- 5..8
	local segLen = PLATFORM_DEPTH / SEGMENTS

	-- math.random errors outright on an empty interval, and several placements below derive BOTH
	-- ends from the jittered edge -- so on the outermost tier of a 4-tier profile the low end can
	-- overtake the high one. This is what took the whole build down on Wormhole. Collapsing to the
	-- low end is the right answer: it means "there is no room to scatter here, put it at the edge".
	local function span(lo, hi)
		lo, hi = math.floor(lo), math.floor(hi)
		if hi <= lo then return lo end
		return math.random(lo, hi)
	end

	-- ===== EVERY TIER MEANDERS, AND THE OUTER ONES DID NOT =====
	--
	-- The old rule jittered each tier OUTWARD from its own nominal line by up to 40% of a band, then
	-- capped that by `TERRAIN_OUTER - 70 - riserX(tier)` to protect the tread. Work the cap out on a
	-- real profile and it is zero: a 3-tier zone puts riserX(3) at 555, and 625 - 70 - 555 = 0. The
	-- OUTERMOST shelf -- the one on the skyline, the one you actually look at -- was therefore cut
	-- dead straight in all twenty zones, and the second one nearly so. That is the row of ruled
	-- parallel lines running the full depth of every map, and it is most of why the band reads as a
	-- staircase mown into a lawn instead of as a hillside.
	--
	-- Cut per SEGMENT instead of per tier. Walk outward from TERRAIN_INNER and let each riser take a
	-- random share of the room that is left, always reserving MIN_TREAD for itself and for every
	-- tier still to be placed. Three things fall out of that: every tier can bulge or retreat
	-- anywhere in the band, the treads are walkable BY CONSTRUCTION rather than by a cap that only
	-- happens to hold, and the choices compound outward so the top shelf is the most ragged rather
	-- than the straightest.
	--
	-- MIN_TREAD also varies per zone: it is what decides whether a zone reads as a few broad
	-- pastures or as many narrow ledges, and it costs nothing to make that a per-zone difference.
	local MIN_TREAD = 30 + (keyHash % 5) * 6      -- 30..54
	local edges = {}
	for tier = 1, p.tiers do edges[tier] = {} end
	for i = 1, SEGMENTS do
		local x = TERRAIN_INNER
		for tier = 1, p.tiers do
			-- the furthest out this riser may stand and still leave a tread for itself and for every
			-- tier above it
			local ceiling = TERRAIN_OUTER - MIN_TREAD * (p.tiers - tier + 1)
			-- Half the remaining room at most. Letting an inner tier take all of it pins every tier
			-- above it against its own ceiling, which is the straight line this exists to remove.
			local room = math.max(0, math.floor((math.max(x, ceiling) - x) * 0.5))
			edges[tier][i] = x + math.random(0, room)
			x = edges[tier][i] + MIN_TREAD
		end
	end
	local function edgeAt(tier, z)
		local i = math.clamp(math.floor((z + halfZ) / segLen) + 1, 1, SEGMENTS)
		return edges[tier][i]
	end
	local function segZ(i) return -halfZ + segLen * (i - 0.5) end

	-- ===== WHICH SEGMENT EACH FLIGHT OF STAIRS CLIMBS =====
	--
	-- Decided HERE, before a single prop is placed, and that ordering is the whole point: the crags,
	-- boulders and conifers below all have to know where the stairs are going to be. Built later
	-- (which is where this started) they were placed into rock -- a screenshot of the first pass
	-- showed a flight of steps and two rails driven straight through a crag, reading as a pile of
	-- slabs rather than as a way up.
	--
	-- SPREAD ACROSS THE RING, NOT STEPPED BY A CONSTANT. The first version picked `tier * 3 + hash`,
	-- and on a zone with six segments that is 3, 0, 3, 0 -- tiers 1 and 3 landed on the SAME segment
	-- and built two flights at two pitches through each other. Dividing the ring by the tier count
	-- cannot do that: with at most 4 tiers against at least 5 segments, every flight gets its own.
	local stairSeg = {}
	for tier = 1, p.tiers do
		stairSeg[tier] = (math.floor((tier - 1) * SEGMENTS / p.tiers) + keyHash + (side > 0 and 1 or 0)) % SEGMENTS + 1
	end
	-- Half the flight's 30-stud width plus a margin, measured from the middle of its segment.
	--
	-- TWO FLIGHTS TOUCH ANY GIVEN SHELF, and the first version of this only knew about one of them
	-- -- which is why a rebuild still came back with 22 crags, 13 buttresses and 9 boulders standing
	-- in a staircase. Tier N's flight STANDS ON tier N-1's tread and ARRIVES AT tier N's, so
	-- anything placed on tread T has to keep clear of flight T (which lands on it at the inner lip)
	-- and of flight T+1 (which runs right across it). `stairSeg[tier + 1]` is nil on the top shelf,
	-- where there is no flight above -- that is the loop's own terminator, not a special case.
	local STAIR_HALF_Z = 26
	local function inStairwell(tier, z)
		for _, t in ipairs({ tier, tier + 1 }) do
			local i = stairSeg[t]
			if i and math.abs(z - segZ(i)) < STAIR_HALF_Z then return true end
		end
		return false
	end

	for tier = 1, p.tiers do
		local top = treadY(tier)

		for i = 1, SEGMENTS do
			local innerX = edges[tier][i]
			local width = TERRAIN_OUTER - innerX
			local zc = segZ(i)
			-- ===== WHERE THIS TIER'S TREAD ACTUALLY ENDS =====
			-- Tier N's slab reaches the rim, but so does tier N+1's, sitting exactly `rise` on top of it
			-- and starting at ITS OWN inner edge. So the part of tier N you can stand on -- and the only
			-- part anything may be placed on -- runs from `innerX` out to the NEXT tier's edge, not to
			-- TERRAIN_OUTER. Everything on this shelf used to scatter over the full width, which on a
			-- 3-tier profile buried roughly two thirds of tier 1's mushrooms, grass, boulders and crags
			-- INSIDE the two slabs above it -- props sunk halfway into a cliff with no way to reach them.
			-- That is the single largest source of "everything is inside everything else" out here.
			local treadOut = (tier < p.tiers) and edges[tier + 1][i] or TERRAIN_OUTER

			-- THE SHELF: exactly `rise` thick and standing on the tier below, never on the ground. See
			-- the z-fighting note above -- that is the other half of the shape.
			newPart({ Name = "TerraceTop", Size = Vector3.new(width, p.rise, segLen),
				Position = Vector3.new(cx + side * (innerX + width / 2), top - p.rise / 2, zc),
				Color = grass, Material = ground, Parent = model })

			-- The exposed rock riser, pushed proud of the shelf's own front face and a little taller
			-- than the step, so neither of its large faces is ever coplanar with the slab behind it.
			newPart({ Name = "CliffFace", Size = Vector3.new(4, p.rise + 1.5, segLen),
				Position = Vector3.new(cx + side * (innerX + 1), top - p.rise / 2, zc), Color = rock,
				Material = Enum.Material.Rock, CanCollide = false, Parent = model })

			-- Strata: two horizontal bands of paler and darker stone across the riser, standing proud
			-- of it in turn. A tall rock wall in one flat tone is a painted board; the bands are what
			-- make it look quarried.
			for k = 1, 2 do
				local h = p.rise * (k == 1 and 0.16 or 0.1)
				newPart({ Name = "CliffStrata", Size = Vector3.new(2.6, h, segLen),
					Position = Vector3.new(cx + side * (innerX - 0.4), top - p.rise * (k == 1 and 0.42 or 0.74), zc),
					Color = k == 1 and rockLit or rockDark, Material = Enum.Material.Rock,
					CanCollide = false, CastShadow = false, Parent = model })
			end

			-- a vertical crack, so the strata do not turn the wall into a stack of ruled lines
			newPart({ Name = "CliffCrack", Size = Vector3.new(2.2, p.rise * math.random(45, 85) / 100, math.random(3, 7)),
				Position = Vector3.new(cx + side * (innerX - 0.6), top - p.rise * 0.5, zc + math.random(-30, 30)),
				Color = rockDark, Material = Enum.Material.Rock, CanCollide = false, CastShadow = false, Parent = model })

			-- ===== ROCK OUTCROPS ON THE RISER =====
			--
			-- The riser above is ONE SLAB 4 thick and `segLen` long -- 230 studs of flat wall per
			-- segment. The strata and the crack are paint on it: they break the tone, not the
			-- silhouette, and from any distance the terraces still read as ruled grey steps.
			--
			-- What actually breaks a straight edge is geometry standing PROUD of it, which is exactly
			-- what the rampart cladding already does for the boundary wall. Same library, same rule.
			--
			-- THREE PER SEGMENT, NOT A CONTINUOUS FACING. Covering the whole 230 studs would need ~10
			-- meshes a segment, i.e. 6,000 across the world on top of the 77,000 parts already here.
			-- Three outcrops cover roughly half the run and leave the banded slab showing between them,
			-- which is what a real cliff looks like anyway -- outcrops with weathered rock between.
			-- 3 x 5 segments x 3 tiers x 2 sides = 90 a zone.
			--
			-- Non-colliding, and the slab behind stays: the slab is the walkable surface and the thing
			-- that stops a player seeing through the terrace. A mesh is scenery hung on the front of it.
			if cliffFace then
				for k = 1, 3 do
					local clad = cliffFace:Clone()
					local _, raw = clad:GetBoundingBox()
					-- SHORTER THAN THE RISER, NOT TALLER. These were sized at 1.06-1.28x the step so their
					-- crests would break the shelf line above -- and the cliff mesh has GRASS ON TOP OF IT,
					-- so what actually appeared was a second little green terrace punching up through the
					-- real one, three times per segment, ninety times a zone. From the valley that is a field
					-- of grey blocks growing out of the lawn, which is exactly the complaint. Kept under the
					-- tread the same mesh reads as what it is: weathered rock cladding the face.
					-- Width is still capped so a deep mesh cannot swallow its neighbours.
					local want = p.rise * (0.74 + math.random() * 0.2)
					clad:ScaleTo(math.min(want / math.max(raw.Y, 1), 52 / math.max(raw.X, raw.Z, 1)))
					for _, part in ipairs(clad:GetDescendants()) do
						if part:IsA("BasePart") then
							part.Anchored = true
							part.CanCollide = false
						end
					end
					clad.Name = "TerraceRock"
					clad.Parent = model
					-- spread across the segment with jitter, so three shelves stacked above one another
					-- never line their outcrops up into a column
					local slotZ = zc + (k - 2) * (segLen / 3) + math.random(-18, 18)
					-- PivotTo, not seatModel: seatModel drops a model to y = 0, and this one belongs on
					-- the tier's own foot, `p.rise` below the shelf it is facing.
					local _, fit = clad:GetBoundingBox()
					-- HALF OF THEM GET A HALF TURN. One mesh repeated ninety times a zone reads as a row of
					-- identical teeth however much the height is jittered, because the SILHOUETTE never
					-- changes -- and the silhouette is the only thing visible against the sky. Turning a
					-- rock 180 degrees shows its other profile, which is free variety from the same asset.
					-- A small roll on top makes some lean into the slope rather than all standing plumb.
					local flip = (math.random(1, 2) == 1) and math.pi or 0
					-- foot buried two studs into the tier below, crest under the tread above
					clad:PivotTo(CFrame.new(
						cx + side * (innerX - 1.5),
						top - p.rise + fit.Y / 2 - 2,
						slotZ
					) * CFrame.Angles(0, (side > 0 and math.rad(90) or math.rad(-90)) + flip + math.rad(math.random(-14, 14)), math.rad(math.random(-5, 5))))
				end
			end

			-- ROUNDED FRONT. A cylinder lying along Z, its curved side facing out over the drop: this
			-- is what turns the shelf's leading edge from a hard 90-degree corner into the soft
			-- rolled-over lip the reference has. It replaces the flat stone lip, which read as a kerb.
			newPart({ Name = "CliffLip", Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(segLen, 7, 7), Orientation = Vector3.new(0, 90, 0),
				Position = Vector3.new(cx + side * (innerX + 1.5), top - 1.6, zc), Color = grass,
				Material = ground, CanCollide = false, Parent = model })

			-- THE CORNER WHERE TWO SEGMENTS DISAGREE. Segment i sticking out further than i+1 leaves a
			-- notch with a raw slab end showing across it; this closes it with rock, so the meander
			-- reads as an eroded headland instead of as a gap between two boxes.
			-- THICKER, AND WEARING GRASS. At 5 studs deep this was a fin: correct geometry -- it is the
			-- side of a step -- but a bare 27-stud-tall grey panel standing edge-on in the open, and now
			-- that the tiers genuinely meander the gaps it has to close are four times what they were, so
			-- the fins got four times longer. 13 deep with the shelf's own grass on top reads as the end
			-- of a terrace, which is what it is. Capped in length: past ~150 studs the two segments are
			-- not a notch any more, they are two different hillsides, and a wall between them is wrong.
			if i < SEGMENTS then
				local nextX = edges[tier][i + 1]
				local gap = math.min(math.abs(nextX - innerX), 150)
				if gap > 2 then
					local midX = cx + side * ((innerX + nextX) / 2)
					newPart({ Name = "CliffCorner", Size = Vector3.new(gap + 5, p.rise + 1.5, 13),
						Position = Vector3.new(midX, top - p.rise / 2, zc + segLen / 2),
						Color = rockLit, Material = Enum.Material.Rock, CanCollide = false, Parent = model })
					-- proud of the rock on top and to both sides, so no face is coplanar with it
					newPart({ Name = "CliffCornerTurf", Size = Vector3.new(gap + 7, 3.2, 15),
						Position = Vector3.new(midX, top - 0.4, zc + segLen / 2),
						Color = grass, Material = ground, CanCollide = false, Parent = model })
				end
			end

			-- BUTTRESSES broken out of the face. The heights are deliberately scattered ABOVE AND BELOW
			-- the step: every one cut to exactly the step height put its top edge flush with the tread
			-- and the whole row read as grey boxes glued to a wall.
			-- 58-138% of the step was the other half of the punch-through: a buttress cut to 138% stands
			-- a third of a step PROUD of the grass above it, and 26 studs deep at 3 studs out from the
			-- face it hangs 16 studs over the drop. Sixty of those a zone is the row of grey boxes lying
			-- half-sunk in the lawn. Kept below the tread and pulled back against the face, the same part
			-- reads as a buttress broken out of the cliff, which is what it was always meant to be.
			for j = 1, 2 do
				local z = zc + span(-segLen / 2 + 20, segLen / 2 - 20)
				-- A buttress stands at this tier's inner edge and hangs BELOW its tread, which is the
				-- exact volume the top half of this tier's flight occupies -- 13 of them were found
				-- driven through a staircase. Pushed clear along z rather than dropped: the buttresses
				-- are what stop the cliff face reading as a painted board, and a bare segment would
				-- undo that everywhere the stairs happen to be.
				local w = math.random(22, 52)
				if inStairwell(tier, z) or inStairwell(tier, z + w / 2) or inStairwell(tier, z - w / 2) then
					z = zc + (z < zc and 1 or -1) * (STAIR_HALF_Z + w / 2 + math.random(6, 20))
				end
				local h = p.rise * math.random(50, 92) / 100
				local d = math.random(9, 17)
				-- ===== THE BUTTRESS IS THE WALL, SO IT STAYS SOLID -- BUT IT IS NO LONGER A STEP =====
				--
				-- It used to be centred at `innerX - 1.5`, which with a depth of 9-17 left it hanging
				-- 6 to 10 studs PROUD of the tier edge, out over the tread below. Its top sits at up
				-- to 92% of the rise, so it was a ledge you could jump onto and then step off onto the
				-- shelf -- two hops past a staircase that is meant to be the only way up (item 19).
				--
				-- Making it intangible was the obvious fix and is WRONG. A ray fired horizontally into
				-- a riser with the jut excluded hits only `CliffFace`, which is `CanCollide = false`:
				-- there is no other collision at that height. The jut IS the riser wall, and removing
				-- it would let players walk into the cliff.
				--
				-- So it is pushed back into the hill instead. `innerX + d/2 - 2` leaves exactly two
				-- studs proud of the edge -- enough to keep the relief that stops the cliff face
				-- reading as a painted board, too little for a character to stand on -- while the rest
				-- of its bulk sits inside the cliff, still spanning the riser plane and still solid.
				local jutX = innerX + d * 0.5 - 2
				newPart({ Name = "CliffJut", Size = Vector3.new(d, h, w),
					CFrame = CFrame.new(cx + side * jutX, top - p.rise + h / 2, z)
						* CFrame.Angles(0, math.rad(math.random(-4, 4)), math.rad(side * math.random(-3, 3))),
					Color = (j % 2 == 0) and rock or rockLit, Material = Enum.Material.Rock, Parent = model })
				-- a shoulder on the taller ones: an unbroken vertical box is a pillar, and a pillar with
				-- a sloped top is a rock. Kept at the same offset RELATIVE to the jut it caps, so it
				-- travels with the change above instead of being left hanging in the air.
				if h > p.rise * 0.78 then
					newPart({ Name = "CliffJutCap", Size = Vector3.new(d * 0.7, h * 0.22, w * 0.72),
						Position = Vector3.new(cx + side * (jutX - 1.5 - d * 0.14), top - p.rise + h * 1.04, z),
						Color = rockDark, Material = Enum.Material.Rock, CanCollide = false, Parent = model })
				end
			end

			-- ---- PLANTING, and it is deliberately DENSE. Everything else in this file places a
			-- handful of large props; the reference hillsides are covered in small bright things --
			-- mushrooms, grass clumps, crystals -- and that density is most of why they read as a place
			-- rather than as terrain. Kept off the outer strip so nothing grows through the wall.
			-- `treadOut`, NOT TERRAIN_OUTER -- see the note where treadOut is worked out. Scattering to
			-- the rim planted most of every lower shelf's mushrooms and grass inside the cliff above it.
			local function spot()
				return cx + side * span(innerX + 10, treadOut - 12),
					zc + span(-segLen / 2 + 12, segLen / 2 - 12)
			end
			for k = 1, 5 do
				local tx, tz = spot()
				tuft(tx, top, tz, math.random(12, 20), k % 4 == 0 and lighten(moss, 0.2) or moss, Enum.Material.Grass)
			end
			for _ = 1, 3 do
				local tx, tz = spot()
				mushroom(tx, top, tz, math.random(7, 14))
			end
			-- one lit crystal clump per segment, in the zone accent -- the point of focus after dark,
			-- and the only thing up here that carries the zone's own colour
			do
				local tx, tz = spot()
				tuft(tx, top, tz, math.random(14, 24), accent, Enum.Material.Neon)
			end
			-- A CONIFER IS THE ONE PLANT BIG ENOUGH TO BLOCK THE WAY UP. The grass, mushrooms and
			-- crystals above are 7 to 24 studs and non-colliding, so a few of them standing beside the
			-- steps is dressing; an 80-stud tree growing out of the middle of a flight is not. Nudged
			-- to the far side of the segment rather than dropped -- the shelves are planted densely on
			-- purpose and a bald segment would read as the one place the world forgot.
			if p.trees and math.random() < p.trees then
				local tx, tz = spot()
				if inStairwell(tier, tz) then
					tz = zc + (tz < zc and 1 or -1) * (STAIR_HALF_Z + math.random(6, 18))
				end
				conifer(tx, top, tz, math.random(46, 80))
			end

			-- CRAGS: a spire standing on the tread, and the only thing in the band taller than one
			-- step -- so it is what gives the terraces a ragged skyline instead of clean horizontals.
			-- A TAPERING STACK of three, not one slab: a single block on end at this size reads as a
			-- gravestone, which is exactly what the first cut looked like.
			-- Against the BACK of the tread, in its outer third, so a crag reads as rock that has come
			-- down off the face behind it. Dropped in the middle of the shelf -- which is where
			-- `innerX + band * 0.4` put it once the tiers stopped being evenly spaced -- it is a grey
			-- slab standing in a field with nothing to explain it. A dark scree pad underneath is what
			-- makes it sit ON the grass instead of being stabbed into it.
			-- ...and NEVER standing in a flight of stairs. A crag is the biggest thing on a tread and
			-- it is CanCollide, so one in the way is not dressing, it is a wall.
			--
			-- TESTED ON ITS OWN z, NOT ON ITS SEGMENT INDEX, and the difference is not academic: a
			-- crag's z is `zc + span(-segLen/2 + 20, ...)`, so it may wander to within TWENTY studs of
			-- the NEXT segment's centre. Skipping stair segments still left three flights across the
			-- world with a spire in the middle of them, every one of them belonging to the segment
			-- next door. The band is what matters, so the band is what is asked.
			if i % 2 == 1 then
				local h = math.random(math.floor(p.rise * 1.5), math.floor(p.rise * 2.8))
				local w = math.random(22, 40)
				local sx = cx + side * span(innerX + (treadOut - innerX) * 0.55, treadOut - 16)
				local sz = zc + span(-segLen / 2 + 20, segLen / 2 - 20)
				-- half the spire's own width on top of the stairwell, so it clears the flight by its
				-- edge rather than by its centre
				if inStairwell(tier, sz) or inStairwell(tier, sz + w / 2) or inStairwell(tier, sz - w / 2) then
					sz = zc + (sz < zc and 1 or -1) * (STAIR_HALF_Z + w / 2 + math.random(4, 16))
				end
				local yaw = math.rad(math.random(0, 360))
				local lean = math.rad(side * -math.random(2, 6))
				-- barely proud of the grass: this is a contact shadow, not a paving slab. At 2.2 studs
				-- of a dark tone it read as a rectangle of tarmac laid under every crag.
				newPart({ Name = "CragScree", Size = Vector3.new(w * 1.24, 1.4, w * 1.1),
					CFrame = CFrame.new(sx, top + 0.5, sz) * CFrame.Angles(0, yaw, 0),
					Color = rock:Lerp(rockDark, 0.5), Material = Enum.Material.Slate,
					CanCollide = false, CastShadow = false, Parent = model })
				newPart({ Name = "CliffCrag", Size = Vector3.new(w, h * 0.52, w * 0.88),
					CFrame = CFrame.new(sx, top + h * 0.24, sz) * CFrame.Angles(0, yaw, lean),
					Color = rock, Material = Enum.Material.Rock, Parent = model })
				newPart({ Name = "CliffCragMid", Size = Vector3.new(w * 0.68, h * 0.42, w * 0.6),
					CFrame = CFrame.new(sx, top + h * 0.66, sz) * CFrame.Angles(0, yaw + 0.5, lean * 1.6),
					Color = rockLit, Material = Enum.Material.Rock, CanCollide = false, Parent = model })
				newPart({ Name = "CliffCragCap", Size = Vector3.new(w * 0.36, h * 0.3, w * 0.34),
					CFrame = CFrame.new(sx, top + h * 0.94, sz) * CFrame.Angles(0, yaw + 1.1, lean * 2.4),
					Color = rockDark, Material = Enum.Material.Rock, CanCollide = false, Parent = model })
			end
		end
	end

	-- ===== A WAY UP. THE SHELVES WERE SCENERY BECAUSE NOTHING COULD REACH THEM =====
	--
	-- The comment further down calls the terraces GROUND rather than scenery, and the collision on
	-- them says the same -- but a riser is 20 to 50 studs of sheer rock and the player's jump clears
	-- about six at stage 1 and thirteen at stage 3. Nobody has ever stood on one. That was survivable
	-- while the band was only a horizon; it stops being survivable the moment anything worth walking
	-- to is put up there, which is what the raised Brutes and Elites in CreatureService now are.
	--
	-- One flight per tier per side, each in its own segment (see `stairSeg`, worked out before any
	-- prop was placed so the crags and boulders could be kept out of the way). Scattering them is
	-- the interesting half: reaching the top shelf means climbing, walking along the tread to find
	-- the next flight, and climbing again. A single stack of flights one above the other would be a
	-- staircase with a view; this is a route.
	--
	-- ===== THE COLLISION IS A RAMP; THE STEPS ARE PAINT =====
	--
	-- Cut as real steps this was 6-18 parts per tier per side -- roughly 1,900 across the strip --
	-- and every one of them would have had to be pinned into WorldShell, because a walkable surface
	-- allowed to stream out is a hole a player falls through while they are standing on it. The
	-- shell is 2,493 parts today; a 76% increase in the set that is replicated to every client at
	-- join, forever, is not worth a staircase.
	--
	-- So the thing you stand on is ONE slab lying at the pitch of the climb -- 1 pinned part per
	-- flight, ~126 across the world -- and the steps are non-colliding faces laid on top of it that
	-- stream like any other decoration. Lose them to streaming and the route still works; you are
	-- walking up the same ramp either way. Humanoid.MaxSlopeAngle is 89 by default, so every pitch
	-- these profiles can produce (25 to 59 degrees) is walked up without a single jump.
	--
	-- The flight runs INWARD from the riser it climbs and stands on the tread below it. `backstop`
	-- is a hard limit and not a style choice: past the inner edge of the shelf underneath, there is
	-- nothing under the ramp but the valley floor thirty studs down.
	do
		for tier = 1, p.tiers do
			local i = stairSeg[tier]
			local outer = edges[tier][i] + 1     -- a stud INTO the riser, so no two faces are coplanar
			local bottom = (tier > 1) and treadY(tier - 1) or 0
			local top = treadY(tier)
			local backstop = (tier > 1) and edges[tier - 1][i] or (TERRAIN_INNER - 46)
			local run = math.max(20, outer - backstop)
			local zc = segZ(i)

			-- world ends of the climb. `side` is which half of the zone this is, so the whole flight
			-- mirrors with it and the maths below never has to know which one it is on.
			local footX = cx + side * (outer - run)
			local headX = cx + side * outer
			local steps = math.clamp(math.floor(run / 5.5), 4, 12)
			local riser = (top - bottom) / steps

			-- ===== A FLIGHT HAS TO BE VISIBLE FROM THE VALLEY (9.6) =====
			--
			-- Measured before this existed: the stair faces and the cliff face were the SAME value --
			-- 0.51 and 0.51, a difference of zero. The steps were painted `rock` and `lighten(rock,
			-- 0.16)`, and `rock` is exactly the colour of the cliff they are cut into, so a flight was
			-- a shape you could only find by walking into it. That is the whole of "you have to hunt
			-- for the route up": the climb worked, it just could not be seen. Six flights per zone sit
			-- 400+ studs off the street, which is precisely the distance at which a zero-contrast
			-- stripe is nothing at all.
			--
			-- Worn steps are PALER than the rock around them, so that is the direction -- but stated as
			-- a fraction of the cliff's own value rather than as a lerp, for the reason the path verge
			-- paid for: "blend toward X then lighten" cancels at some inputs and this file has twenty
			-- of them. On an already-bright cliff it goes the other way, the same contrast flip the
			-- village trim uses.
			local cliffV = select(3, Color3.toHSV(rock))
			local function tread(amount)
				local h, s = Color3.toHSV(rock)
				local v = cliffV > 0.62 and cliffV * (1 - amount) or cliffV + (1 - cliffV) * amount
				return Color3.fromHSV(h, s * 0.82, math.clamp(v, 0.04, 1))
			end
			-- two tones so individual steps stay countable close up; both clear of the cliff so the
			-- flight reads as one pale stripe from across the valley
			local treadA, treadB = tread(0.42), tread(0.26)

			-- ---- THE STEPS, WHICH ARE THE THING YOU SEE. Each one is a solid block standing on the
			-- tread below and reaching its own height, so its top is horizontal, its front face is the
			-- riser, and nothing about it floats -- the first cut laid thin plates along the pitch of
			-- the ramp instead, which from the side read as slats nailed to a plank.
			for k = 1, steps do
				local h = riser * k
				local sx = footX + (headX - footX) * ((k - 0.5) / steps)
				newPart({ Name = "TerraceStairFace", Size = Vector3.new((run / steps) * 1.02, h, 30),
					Position = Vector3.new(sx, bottom + h / 2, zc),
					Color = (k % 2 == 0) and treadA or treadB, Material = Enum.Material.Rock,
					CanCollide = false, CastShadow = false, Parent = model })
			end

			-- ---- AND THE THING YOU STAND ON, SUNK HALF A STEP INTO THEM.
			--
			-- lookAt puts the part's -Z on the top end, so the slab's LENGTH is its Z and the pitch
			-- falls out of the two end points rather than out of a trig call that would need its sign
			-- corrected per side. The slab is 4 thick and both ends are given as its CENTRE line, so
			-- every height below is the surface the player walks MINUS 2.
			--
			-- THE TOP END IS THE ONE THAT HAS TO BE EXACT: `top - 2` puts the walking surface flush
			-- with the shelf, so arriving is a step onto level ground rather than a lip to be jumped.
			-- The bottom end is half a riser up, which sinks the slab into the mass of the steps and
			-- hides it; the six studs of extra length then carry that end down below the tread it
			-- starts from, so setting off is a slope and not a kerb either.
			local from = Vector3.new(footX, bottom + riser * 0.5 - 2, zc)
			local to = Vector3.new(headX, top - 2, zc)
			-- 28 -> 34. THE COLLISION WAS NARROWER THAN THE STAIRCASE YOU CAN SEE. The visible steps
			-- are 30 studs deep and non-colliding paint; this slab is the only thing you actually
			-- stand on. At 28 it left a stud of nothing down each side of the flight, so walking up
			-- the visual edge of the stairs dropped the player off the side of the hill -- which is
			-- most of "you can fall if you snag on certain things" (item 18). 34 covers the painted
			-- tread with two studs to spare on each side, and still passes under the rails at +/-16.
			local ramp = newPart({ Name = "TerraceRamp", Size = Vector3.new(34, 4, (to - from).Magnitude + 6),
				CFrame = CFrame.lookAt(from:Lerp(to, 0.5), to), Color = rock,
				Material = Enum.Material.Rock, Parent = model })

			-- a kerb down each side, so the flight reads as cut into the hill rather than as a stack
			-- of slabs that happens to be climbable. Chunky on purpose: at 3 studs it was a pencil
			-- line, and the outline is what the whole art direction here is carried by.
			for _, sz in ipairs({ -1, 1 }) do
				newPart({ Name = "TerraceStairRail", Size = Vector3.new(4.5, 7, ramp.Size.Z),
					CFrame = ramp.CFrame * CFrame.new(sz * 16, 3, 0),
					Color = rockDark, Material = Enum.Material.Rock,
					CanCollide = false, CastShadow = false, Parent = model })
			end
		end
	end

	-- ---- boulders, sitting ON whichever shelf they land on rather than at y = 0
	for _ = 1, p.rocks do
		local tier = math.random(1, p.tiers)
		local z = math.random(-halfZ + 40, halfZ - 40)
		-- a 48-stud boulder parked on the steps is the same problem the crags had. This one is drawn
		-- from the whole depth rather than from inside a segment, so rerolling is cheaper than
		-- reasoning about where else it could go -- and the edges are tested, not just the centre,
		-- for the same reason the crags are.
		local half = p.rockSize[2] / 2
		for _ = 1, 4 do
			if not (inStairwell(tier, z) or inStairwell(tier, z + half) or inStairwell(tier, z - half)) then break end
			z = math.random(-halfZ + 40, halfZ - 40)
		end
		if inStairwell(tier, z) then continue end
		-- edgeAt, not riserX: the segment under this z may have pulled back forty studs, and a
		-- boulder placed off the nominal edge would be standing in the air over the tier below.
		-- Bounded on the far side by the NEXT tier's edge for the same reason the plants are -- past
		-- it there is no tread, only the underside of the shelf above.
		local innerX = edgeAt(tier, z)
		local outerX = (tier < p.tiers) and edgeAt(tier + 1, z) or TERRAIN_OUTER
		-- ===== A BOULDER MUST NOT BE A STEP ONTO THE NEXT SHELF (item 19) =====
		--
		-- The outer bound was `outerX - 18`, i.e. a boulder CENTRE 18 studs short of the next riser
		-- -- and `rockSize` reaches 48, so a big one overlapped the cliff above it by six studs and
		-- stood up to 30 studs tall against a rise of 20-26. Climb the boulder, jump, and you are on
		-- the shelf without ever finding the stairs. It was also the likeliest thing in the zone to
		-- wedge a player: a solid tilted slab half-buried in a wall.
		--
		-- The clearance is now derived from the boulder that could actually be rolled here rather
		-- than being a flat 18: half the widest possible rock, plus 24 studs of gap between its edge
		-- and the riser. Jumping the remaining gap while also gaining height is not a step, it is a
		-- stunt -- and unlike the flat number this cannot silently stop working when `rockSize` moves.
		local boulderClear = p.rockSize[2] * 0.5 + 24
		boulder(cx + side * span(innerX + 16, outerX - boulderClear),
			treadY(tier), z, math.random(p.rockSize[1], p.rockSize[2]))
	end

	-- ---- a scree of loose rock spilling from the foot of the first riser out onto the valley
	-- floor, which is what stops the terraces meeting the flat ground on a ruled line
	for _ = 1, 8 do
		local s = math.random(6, 15)
		newPart({ Name = "ValleyScree", Shape = Enum.PartType.Ball,
			Size = Vector3.new(s, s * 0.6, s * 0.88),
			Orientation = Vector3.new(0, math.random(0, 360), math.random(-24, 24)),
			-- ===== SCREE SPILLS FROM THE FOOT, IT DOES NOT LEAN ON IT (item 19) =====
			--
			-- The band ended at `TERRAIN_INNER - 6`, so a 15-stud rock (7.5 of radius) sat hard
			-- against the first riser -- and scree is SOLID (see SOLID_PROPS). Its top is ~4.5 studs
			-- up, which added to the 21.6-stud max-jump apex is 26.1 against a 26-stud rise: enough,
			-- by a tenth of a stud, to hop the first tier beside the stairs. Measured, not guessed --
			-- a shelf was found 9 studs from a scree rock and within jump height.
			-- Pulled back to 22-46 studs from the foot: still a spill that stops the terraces meeting
			-- the flat ground on a ruled line, no longer a step.
			Position = Vector3.new(cx + side * math.random(TERRAIN_INNER - 46, TERRAIN_INNER - 22),
				s * 0.22, math.random(-halfZ + 40, halfZ - 40)),
			Color = (math.random() < 0.5) and rock or rockDark, Material = Enum.Material.Rock,
			CanCollide = false, Parent = model })
	end

	-- ---- water at the foot of the cliff, and the falls that feed it
	if p.water then
		local poolZ = math.random(-260, 260)
		local poolLen = math.random(220, 340)
		local poolX = cx + side * (TERRAIN_INNER - 26)
		-- The pool sits just INSIDE the first cliff, in the strip between the valley floor and the
		-- terraces -- 15 studs clear of DECO_SPREAD_X, so no scattered prop can ever land in it.
		newPart({ Name = "PoolBed", Size = Vector3.new(52, 1.6, poolLen + 12),
			Position = Vector3.new(poolX, 0.8, poolZ), Color = darken(rock, 0.3),
			Material = Enum.Material.Slate, Parent = model })
		local water = newPart({ Name = "PoolWater", Size = Vector3.new(46, 2.4, poolLen),
			Position = Vector3.new(poolX, 1.9, poolZ), Color = Color3.fromRGB(96, 210, 240),
			Material = Enum.Material.Glass, Transparency = 0.35, CanCollide = false, CastShadow = false, Parent = model })
		addLight(water, Color3.fromRGB(120, 220, 250), 30, 0.7)
		-- a stone rim, so the water is held by something instead of lying on the grass
		for _, dx in ipairs({ -27, 27 }) do
			newPart({ Name = "PoolRim", Size = Vector3.new(6, 3, poolLen + 12),
				Position = Vector3.new(poolX + dx, 1.5, poolZ), Color = rockLit,
				Material = Enum.Material.Rock, Parent = model })
		end

		-- ===== WHAT MAKES A RECTANGLE READ AS A POND =====
		--
		-- The pool is a 46-stud glass slab: a perfectly flat cyan rectangle with two hard straight
		-- edges. Nothing about it moves or breaks up, so it reads as a swimming pool cut into the
		-- grass. Three things fix that and none of them touches the slab itself.
		--
		-- Ripples ON the surface break the flatness, foam ALONG the rim hides the straight edge where
		-- water meets stone, and lily pads give the eye something with a known size to judge it by.
		-- All three sit just above the water plane at 3.15 -- the slab's own top is 3.1, and anything
		-- level with it z-fights, which is the shimmer that has been chased off this map twice.
		local surfaceY = 3.15
		local ripple = waterLib and waterLib:FindFirstChild("Water_Ripple")
		if ripple then
			for _ = 1, 3 do
				local r = ripple:Clone()
				local _, raw = r:GetBoundingBox()
				r:ScaleTo((16 + math.random() * 14) / math.max(raw.X, raw.Z, 0.1))
				for _, part in ipairs(r:GetDescendants()) do
					if part:IsA("BasePart") then
						part.Anchored = true; part.CanCollide = false; part.CastShadow = false
						part.Material = Enum.Material.Glass
						-- 0.62: at 0.45 a ripple read as a solid disc lying on the pool. It is meant to
						-- disturb the surface, not to be an object floating on it.
						part.Transparency = 0.62
						part.Color = Color3.fromRGB(150, 230, 250)
					end
				end
				r.Name = "PoolRipple"
				r.Parent = model
				local _, fit = r:GetBoundingBox()
				r:PivotTo(CFrame.new(poolX + math.random(-14, 14), surfaceY + fit.Y / 2,
					poolZ + math.random(-poolLen // 2 + 30, poolLen // 2 - 30))
					* CFrame.Angles(0, math.random() * math.pi * 2, 0))
			end
		end

		local lily = waterLib and waterLib:FindFirstChild("Water_Lily")
		-- lilies only where something could actually grow: a lava pool or a void pool with water
		-- lilies floating in it is worse than a bare rectangle
		if lily and (zone.key == "Forest" or zone.key == "Ocean" or zone.key == "DreamDimension"
			or zone.key == "Desert" or zone.key == "TimeRift") then
			for _ = 1, 2 do
				local l = lily:Clone()
				local _, raw = l:GetBoundingBox()
				l:ScaleTo((12 + math.random() * 8) / math.max(raw.X, raw.Z, 0.1))
				for _, part in ipairs(l:GetDescendants()) do
					if part:IsA("BasePart") then
						part.Anchored = true; part.CanCollide = false; part.CastShadow = false
					end
				end
				l.Name = "PoolLily"
				l.Parent = model
				local _, fit = l:GetBoundingBox()
				l:PivotTo(CFrame.new(poolX + math.random(-13, 13), surfaceY + fit.Y / 2,
					poolZ + math.random(-poolLen // 2 + 40, poolLen // 2 - 40))
					* CFrame.Angles(0, math.random() * math.pi * 2, 0))
			end
		end

		local foam = waterLib and waterLib:FindFirstChild("Water_FoamLine")
		if foam then
			-- along BOTH rims, at the waterline. This is the piece that does the most work: the hard
			-- straight edge where a glass slab meets a stone kerb is the single most artificial thing
			-- about the pool, and a broken line of bubbles is exactly what a real shore has there.
			-- 22.5, not 21: the water slab is 46 across, so its lip is at 23. At 21 the whole line sat
			-- two studs INSIDE the pool and read as a causeway floating in it rather than as foam
			-- gathered against the kerb.
			for _, dx in ipairs({ -22.5, 22.5 }) do
				local probe = foam:Clone()
				local _, praw = probe:GetBoundingBox()
				-- 2.2, down from 5. The mesh is authored 5 studs tall and left at that height its
				-- bubbles stand knee-high in a line round the pool -- a snow bank, not foam. Foam is a
				-- detail at the waterline and has to be read as one.
				local fScale = 2.2 / math.max(praw.Y, 0.1)
				local fStep = math.max(praw.X, praw.Z) * fScale * 0.9
				probe:Destroy()
				for fz = poolZ - poolLen / 2 + fStep / 2, poolZ + poolLen / 2, fStep do
					local f = foam:Clone()
					f:ScaleTo(fScale)
					for _, part in ipairs(f:GetDescendants()) do
						if part:IsA("BasePart") then
							part.Anchored = true; part.CanCollide = false; part.CastShadow = false
							part.Transparency = 0.25
							part.Color = Color3.fromRGB(244, 253, 255)
						end
					end
					f.Name = "PoolFoam"
					f.Parent = model
					local _, fit = f:GetBoundingBox()
					-- sunk to its own midline, so the bubbles sit IN the surface rather than on top of it
					f:PivotTo(CFrame.new(poolX + dx, surfaceY - fit.Y * 0.15, fz)
						* CFrame.Angles(0, math.rad(90), 0))
				end
			end
		end

		-- reeds and wet stones along the rims -- the edge of a pool is where the eye goes, and a bare
		-- stone kerb reads as a swimming pool
		for i = 1, 7 do
			local rz = poolZ + (i - 4) * (poolLen / 8)
			tuft(poolX - side * 30, 0, rz, math.random(10, 18), moss, Enum.Material.Grass)
			local s = math.random(7, 14)
			newPart({ Name = "PoolStone", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 0.62, s * 0.9),
				Orientation = Vector3.new(0, math.random(0, 360), math.random(-18, 18)),
				Position = Vector3.new(poolX + side * math.random(20, 30), s * 0.2, rz + math.random(-14, 14)),
				Color = rockDark, Material = Enum.Material.Rock, CanCollide = false, Parent = model })
		end

		-- One emitter for the whole pool. Mist over water is the cheapest possible way to put motion
		-- into a band made entirely of anchored rock.
		-- MIST HUGS THE WATER. It did not: at 34 studs across, rising at 2-6 with another 3 of
		-- upward acceleration under it for up to 4.2 seconds, each puff climbed about FIFTY studs
		-- and ended up level with the terrace tops -- a drift of pale rounded slabs hanging in the
		-- sky over every zone with a pool in it, with nothing under them to explain what they were.
		-- Sized and paced to stay on the water now: peak rise is about eleven studs.
		local mist = Instance.new("ParticleEmitter")
		mist.Color = ColorSequence.new(Color3.fromRGB(226, 248, 255))
		mist.Size = NumberSequence.new(8, 18)
		mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.86), NumberSequenceKeypoint.new(1, 1) })
		mist.Lifetime = NumberRange.new(1.8, 3.0)
		mist.Rate = 5
		mist.Speed = NumberRange.new(1, 2.5)
		mist.SpreadAngle = Vector2.new(40, 40)
		mist.Acceleration = Vector3.new(0, 0.8, 0)
		mist.Parent = water

		-- CASCADES. A fall used to be a single sheet off tier 1, because a sheet starting higher up
		-- would have had to cut through the shelf standing in front of it. The answer is not one tall
		-- sheet but a STAIRCASE of them: one sheet per riser, all at the same z, each landing in a
		-- basin on the tread below and going over the next edge. This is also the second thing the
		-- one-step-tall tiers above bought -- on the old full-height slabs there was no tread to land
		-- on in the first place.
		local cascade = math.min(p.tiers, 3)
		for i = 1, p.falls do
			local fz = poolZ + (i - (p.falls + 1) / 2) * (poolLen / math.max(1, p.falls))
			for tier = cascade, 1, -1 do
				-- the ACTUAL edge under this fall's z. On the old straight tiers this was riserX(tier);
				-- with a meandering edge that hangs the sheet in mid-air wherever a segment pulled back.
				local innerX = edgeAt(tier, fz)
				local top = treadY(tier)
				local foot = top - p.rise
				-- the sheet hangs on the riser, proud of it, so it is never coplanar with the rock, and
				-- it runs PAST both ends of the drop -- up behind the lip and down into the water -- so
				-- there is no seam where the water starts or stops
				local fx = cx + side * (innerX - 1.8)
				local wide = 34 - (tier - 1) * 5
				local sheetH = p.rise + 9
				local sheet = newPart({ Name = "FallSheet", Size = Vector3.new(4, sheetH, wide),
					Position = Vector3.new(fx, foot + sheetH / 2 - 3.5, fz), Color = Color3.fromRGB(150, 230, 250),
					Material = Enum.Material.Glass, Transparency = 0.25, CanCollide = false, CastShadow = false, Parent = model })

				-- WATER THAT IS ACTUALLY MOVING. Everything else here is static geometry, and static
				-- geometry is why the falls read as a striped pane of glass rather than as a waterfall --
				-- the streaks, the lip, the foam and the basin all describe the SHAPE of falling water
				-- without anything ever going down.
			--
				-- One emitter on the sheet itself, spanning its full width and height (EmissionDirection
				-- Top with a box-shaped spread), throwing droplets down the face at the speed gravity
				-- would. It is the cheapest possible motion cue: one instance per sheet, no per-frame
				-- script, and the engine culls it with the part when the chunk streams out.
				local drops = Instance.new("ParticleEmitter")
				drops.Name = "FallDrops"
				drops.Color = ColorSequence.new(Color3.fromRGB(222, 248, 255))
				drops.LightEmission = 0.55
				-- narrow and tall: a droplet is a streak, not a puff, and a round particle on a
				-- waterfall reads as snow
				drops.Size = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 2.2),
					NumberSequenceKeypoint.new(1, 3.4),
				})
				drops.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.25),
					NumberSequenceKeypoint.new(0.75, 0.45),
					NumberSequenceKeypoint.new(1, 1),
				})
				-- lifetime x speed has to land the droplet at the FOOT of the drop and not past it, or
				-- the fall appears to spray straight through its own basin
				drops.Lifetime = NumberRange.new(0.5, 0.8)
				drops.Speed = NumberRange.new(sheetH * 0.9, sheetH * 1.2)
				drops.Rate = 26
				drops.SpreadAngle = Vector2.new(4, 4)
				drops.Acceleration = Vector3.new(0, -46, 0)
				drops.EmissionDirection = Enum.NormalId.Bottom
				drops.Orientation = Enum.ParticleOrientation.VelocityParallel
				drops.Parent = sheet

				-- ===== THE CURTAIN ITSELF, AS GEOMETRY =====
				--
				-- Everything above describes falling water without any of it having a shape: a flat
				-- glass rectangle with three neon strips painted down it, which from any angle reads as
				-- a blue pane with white stripes on it. `Water_FallWide` is a real curtain -- it bulges,
				-- folds, and carries a foam crest -- so it goes in front and the slab behind it drops to
				-- near-invisible rather than being deleted: the slab is what fills the gap between the
				-- mesh and the rock when the tier heights do not divide evenly.
				local fallMesh = waterLib and waterLib:FindFirstChild("Water_FallWide")
				if fallMesh then
					sheet.Transparency = 0.86
					local curtain = fallMesh:Clone()
					local _, raw = curtain:GetBoundingBox()
					-- sized on HEIGHT, then checked on width: the sheet is `wide` across and the mesh is
					-- authored 17 x 16, so a pure height match would leave it too narrow to cover
					local byH = sheetH / math.max(raw.Y, 0.1)
					local byW = (wide * 1.05) / math.max(raw.X, 0.1)
					curtain:ScaleTo(math.max(byH, byW))
					for _, part in ipairs(curtain:GetDescendants()) do
						if part:IsA("BasePart") then
							part.Anchored = true
							part.CanCollide = false
							part.CastShadow = false
							-- tinted to the zone's own water rather than left bone white; the mesh was
							-- generated pale on purpose so this reads honestly in every biome
							part.Color = Color3.fromRGB(186, 240, 255)
							part.Material = Enum.Material.Glass
							part.Transparency = 0.12
						end
					end
					curtain.Name = "FallCurtain"
					curtain.Parent = model
					local _, fit = curtain:GetBoundingBox()
					-- faces the valley: `side` is -1 or +1 across the platform, so the two banks get
					-- opposite quarter turns and both curtains face the middle
					curtain:PivotTo(CFrame.new(fx - side * 1.5, foot + fit.Y / 2 - 3, fz)
						* CFrame.Angles(0, side > 0 and math.rad(90) or math.rad(-90), 0))
				end

				-- and a churned splash where it lands, on the bottom step only -- that is where the
				-- whole cascade arrives, and one per fall beats one per step
				local splashMesh = (tier == 1) and waterLib and waterLib:FindFirstChild("Water_Splash")
				if splashMesh then
					local splash = splashMesh:Clone()
					local _, raw = splash:GetBoundingBox()
					-- 0.7, down from 1.15. At the wider figure a 34-stud fall grew a 39-stud ball of foam
					-- that stood taller than the terrace behind it and read as a cloud parked in the
					-- valley. Foam belongs at the waterline: smaller than the curtain, and mostly in it.
					splash:ScaleTo((wide * 0.7) / math.max(raw.X, raw.Z, 0.1))
					for _, part in ipairs(splash:GetDescendants()) do
						if part:IsA("BasePart") then
							part.Anchored = true
							part.CanCollide = false
							part.CastShadow = false
							part.Color = Color3.fromRGB(240, 253, 255)
							part.Transparency = 0.2
						end
					end
					splash.Name = "FallSplash"
					splash.Parent = model
					local _, fit = splash:GetBoundingBox()
					-- sunk below the waterline, so what shows is churn breaking the surface rather than
					-- the whole ball sitting on top of it
					splash:PivotTo(CFrame.new(fx - side * 7, foot - fit.Y * 0.18, fz)
						* CFrame.Angles(0, math.random() * math.pi * 2, 0))
				end
				-- Vertical banding down the face of the sheet. One flat pane of glass reads as a window,
				-- however blue it is; what actually says "falling water" is streaks running the whole
				-- drop, and they cost three parts.
				for k = -1, 1 do
					newPart({ Name = "FallStreak", Size = Vector3.new(2.4, sheetH * 0.94, wide * 0.15),
						Position = Vector3.new(fx - side * 2.6, foot + sheetH / 2 - 4, fz + k * wide * 0.3),
						Color = Color3.fromRGB(226, 250, 255), Material = Enum.Material.Neon, Transparency = 0.45,
						CanCollide = false, CastShadow = false, Parent = model })
				end
				-- The lip it pours over: a small block sitting ON the edge, half on the tread and half
				-- out over the drop. It used to be a wide flat slab six studs back from the edge, which
				-- read as a sheet of ice lying on the grass and not as the top of a waterfall.
				-- SUNK INTO THE SHELF, NOT LYING ON IT. At `top + 1.2` with a height of 3.2 the lip stood
				-- 2.8 studs clear of the grass -- a pale blue glass brick sitting on a lawn, which is what
				-- it read as from the valley. Water goes over an edge through a cut in it, so it is now
				-- mostly below the surface with a dark stone spillway either side to be the cut.
				newPart({ Name = "FallSpillway", Size = Vector3.new(13, 4.2, wide + 15),
					Position = Vector3.new(fx + side * 3.4, top - 1.1, fz), Color = rockDark,
					Material = Enum.Material.Rock, CanCollide = false, Parent = model })
				newPart({ Name = "FallLip", Size = Vector3.new(9, 3.0, wide + 3),
					Position = Vector3.new(fx + side * 2.6, top + 0.2, fz), Color = Color3.fromRGB(178, 240, 255),
					Material = Enum.Material.Glass, Transparency = 0.2, CanCollide = false, Parent = model })
				-- The header: on the TOP step of the cascade the water arrived at the lip out of nothing.
				-- A short run of the same stream back into the shelf gives it somewhere to have come from.
				if tier == cascade then
					local headOut = (tier < p.tiers) and edgeAt(tier + 1, fz) or TERRAIN_OUTER
					local headLen = math.max(12, (headOut - 6) - (innerX + 4))
					newPart({ Name = "FallHeadBank", Size = Vector3.new(headLen + 8, 3.4, wide + 16),
						Position = Vector3.new(cx + side * (innerX + 4 + headLen / 2), top - 0.8, fz),
						Color = rockDark, Material = Enum.Material.Rock, CanCollide = false, Parent = model })
					newPart({ Name = "FallHead", Size = Vector3.new(headLen, 1.6, wide * 0.8),
						Position = Vector3.new(cx + side * (innerX + 4 + headLen / 2), top + 0.1, fz),
						Color = Color3.fromRGB(120, 220, 245), Material = Enum.Material.Glass,
						Transparency = 0.3, CanCollide = false, CastShadow = false, Parent = model })
				end
				-- The basin it lands in. On tier 1 that is the pool itself, so only the upper steps get
				-- one: a second sheet of water lying on top of the pool would z-fight with it, which is
				-- the very thing this pass exists to remove.
				-- ===== THE WATER HAS TO GO SOMEWHERE BETWEEN TWO DROPS =====
				-- It used to land in a 30-stud blue rectangle and stop: a puddle in the middle of a shelf
				-- with a waterfall over it and nothing leading away, so each step read as a separate
				-- object dropped on the grass rather than as one cascade. The basin now RUNS ON across the
				-- tread and arrives at the lip of the step below, so the whole thing is continuous from the
				-- top shelf down into the pool. It is the same two parts, stretched, and the dark bank under
				-- it is what stops a stream reading as blue paint on grass.
				if tier > 1 then
					local belowX = edgeAt(tier - 1, fz)
					local nearX, farX = innerX - 2, belowX
					local runLen = math.max(16, nearX - farX)
					local midX = cx + side * (farX + runLen / 2)
					newPart({ Name = "FallBasinRim", Size = Vector3.new(runLen + 10, 3.4, wide + 22),
						Position = Vector3.new(midX, foot + 1.1, fz), Color = rockDark,
						Material = Enum.Material.Rock, CanCollide = false, Parent = model })
					newPart({ Name = "FallBasin", Size = Vector3.new(runLen, 1.6, wide + 14),
						Position = Vector3.new(midX, foot + 1.9, fz), Color = Color3.fromRGB(120, 220, 245),
						Material = Enum.Material.Glass, Transparency = 0.3, CanCollide = false, CastShadow = false, Parent = model })
				end
				local foam = newPart({ Name = "FallFoam", Shape = Enum.PartType.Ball,
					Size = Vector3.new(wide, 5, wide), Position = Vector3.new(fx - side * 9, foot + 3.2, fz),
					Color = Color3.fromRGB(235, 252, 255), Material = Enum.Material.Neon,
					Transparency = 0.45, CanCollide = false, CastShadow = false, Parent = model })
				if tier == 1 then
					addLight(foam, Color3.fromRGB(200, 245, 255), 26, 0.8)
					-- Spray, on the bottom step only. That is where the whole cascade lands and it keeps
					-- the emitter count to one per fall rather than one per step.
					local spray = Instance.new("ParticleEmitter")
					spray.Color = ColorSequence.new(Color3.fromRGB(238, 253, 255))
					spray.Size = NumberSequence.new(6, 22)
					spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
					spray.Lifetime = NumberRange.new(0.8, 1.6)
					spray.Rate = 22
					spray.Speed = NumberRange.new(8, 18)
					spray.SpreadAngle = Vector2.new(55, 55)
					spray.Acceleration = Vector3.new(0, -14, 0)
					spray.Parent = foam
				end
				-- two wet boulders flanking the plunge, which is what makes a sheet of glass read as
				-- water that has been falling there for a while
				for _, dz in ipairs({ -(wide * 0.7 + 6), wide * 0.7 + 6 }) do
					local s = math.random(11, 19)
					newPart({ Name = "FallStone", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 0.7, s * 0.9),
						Orientation = Vector3.new(0, math.random(0, 360), math.random(-16, 16)),
						Position = Vector3.new(fx - side * 8, foot + s * 0.24, fz + dz),
						Color = rockDark, Material = Enum.Material.Rock, CanCollide = false, Parent = model })
				end
			end
		end
	end
end

local function buildTerrain(model, zone, cx)
	-- rise 26, not 16, for the reason given over TERRAIN_PROFILE: anything at or under the 21.6-stud
	-- max-jump apex is a shelf you hop onto instead of climbing to, and a fallback is exactly the
	-- case nobody re-measures.
	local p = TERRAIN_PROFILE[zone.key] or { tiers = 3, rise = 26, water = false, falls = 0, rocks = 9, rockSize = { 14, 32 } }
	for _, side in ipairs({ -1, 1 }) do
		buildValleySide(model, zone, cx, side, p)
	end
end

-- ===== THE MESH PROP LAYER ==================================================================
-- The bosses, the creatures, the eggs and all 200 player characters are generated meshes. The MAP
-- was the last thing in the game still made of primitives -- a Ball for a bush, a Cylinder for a
-- log -- and standing a meshed boss on it is what made that impossible to miss. This is the same
-- pipeline pointed at the ground: ServerStorage.PropMeshes holds Prop_<ZoneKey>_<SLOT> models,
-- three slots per zone.
--
--   CANOPY   the tall silhouette piece -- tree, spire, column. What you see from the gate.
--   BOULDER  the mid mass at chest-to-head height that breaks up the floor.
--   FLORA    the small ground cluster that fills in between the other two.
--
-- OPT-OUT BY ABSENCE, and that is the whole reason this is safe to roll out one mesh at a time:
-- a zone with no model filed for a slot simply does not get that slot. The twenty primitive biome
-- builders below are untouched and still draw everything they always drew, so a missing mesh is a
-- slightly emptier zone and never a broken one. (ACTIVE_ZONE_KEY is declared at the top of the
-- file, beside ACTIVE_FRAME -- addLandmark needs it too and is written far above this point.)

-- `count` is CLUMP CENTRES, not props: each centre grows 1..clump instances inside clumpR of it.
-- Scattering singles over 350 x 548 studs reads as evenly-spaced dots however many you place --
-- what reads as a landscape is empty ground with thickets in it, and clumping is most of the
-- difference for none of the part budget.
--
-- `height` is the target height in studs and `widthCap` the widest the thing may get. The scale is
-- the SMALLER of the two ratios: these models are generated to a rough bounding box and some come
-- out long rather than tall, so height-matching alone would blow a wide prop out sideways -- the
-- same mistake that once made a 6.5-stud creature 15.5 studs wide.
local PROP_SLOTS = {
	{ slot = "CANOPY",  count = 5, height = { 34, 62 }, widthCap = 46, spreadX = 300, spreadZ = 380, clump = 3, clumpR = 26, collide = true,  shadow = true,  sink = 0.8 },
	{ slot = "BOULDER", count = 5, height = { 11, 26 }, widthCap = 38, spreadX = 310, spreadZ = 390, clump = 2, clumpR = 20, collide = true,  shadow = true,  sink = 1.2 },
	{ slot = "FLORA",   count = 8, height = { 6,  13 }, widthCap = 18, spreadX = 320, spreadZ = 400, clump = 3, clumpR = 14, collide = false, shadow = false, sink = 0.4 },
	-- BUILT THINGS, not grown ones: a shrine, an obelisk, a wrecked hull, a forge hut. The three
	-- slots above are all nature, and a zone made only of trees and rocks reads as terrain rather
	-- than as somewhere anyone has ever been.
	--
	-- `clump = 1` IS THE POINT. Everything else here grows in thickets because that is what plants
	-- and rubble do; two shrines standing shoulder to shoulder reads as a mistake. One per point,
	-- two per zone, so each one is found rather than come across.
	--
	-- Sized to sit between the boulder (26 max) and the zone's hero landmark (118): tall enough to
	-- break the skyline from across the platform, short enough that it never competes with the
	-- monument. clumpR stays small but non-zero -- it is the jitter AND half of what scatterPoint is
	-- told to keep clear, and the other half is widthCap / 2.
	{ slot = "STRUCTURE", count = 2, height = { 26, 44 }, widthCap = 40, spreadX = 300, spreadZ = 380, clump = 1, clumpR = 8, collide = true, shadow = true, sink = 0.5 },
}

local function addMeshProps(model, cx)
	local folder = ServerStorage:FindFirstChild("PropMeshes")
	if not folder or not ACTIVE_ZONE_KEY then return end

	for _, spec in ipairs(PROP_SLOTS) do
		local template = folder:FindFirstChild("Prop_" .. ACTIVE_ZONE_KEY .. "_" .. spec.slot)
		if template then
			for _ = 1, spec.count do
				-- HOW FAR THIS CLUMP CAN REACH FROM ITS CENTRE, and it is BOTH terms. The wander of
				-- an outlier (clumpR) plus that outlier's own half-width (widthCap / 2) -- scatterPoint
				-- inflates every clearance and pulls the spread in by whatever it is told, and it can
				-- only be told the truth once. Declaring clumpR alone put a fern one stud inside the
				-- boss arena, a canopy four studs into the street and a boulder one stud past the
				-- cliff-foot pool rim: three near-misses out of 670, all of them the same arithmetic,
				-- and all of them silent -- which is exactly the failure the note beside scatterPoint
				-- describes. A prop that overhangs by a stud today is a prop that buries a boss when
				-- someone raises widthCap.
				local x, z = scatterPoint(cx, spec.spreadX, spec.spreadZ, spec.clumpR + spec.widthCap / 2)
				for k = 1, math.random(1, spec.clump) do
					local ox = k == 1 and 0 or math.random(-spec.clumpR, spec.clumpR)
					local oz = k == 1 and 0 or math.random(-spec.clumpR, spec.clumpR)
					local prop = template:Clone()
					-- measured at scale 1, before ScaleTo and before parenting: GetBoundingBox covers
					-- every descendant, so anything measured after it has been put somewhere is
					-- measuring its surroundings as well
					local _, raw = prop:GetBoundingBox()
					local targetH = spec.height[1] + math.random() * (spec.height[2] - spec.height[1])
					prop:ScaleTo(math.min(targetH / math.max(raw.Y, 0.1), spec.widthCap / math.max(raw.X, raw.Z, 0.1)))
					for _, d in ipairs(prop:GetDescendants()) do
						if d:IsA("BasePart") then
							-- generated meshes arrive UNANCHORED. newPart anchors everything it makes;
							-- nothing anchors what comes out of the generator, and an unanchored tree
							-- falls through the floor on the first physics step of the first server.
							d.Anchored = true
							d.CanCollide = spec.collide
							d.CastShadow = spec.shadow
						end
					end
					prop.Name = "Prop" .. spec.slot
					prop.Parent = model
					-- seatModel, not PivotTo: every model in the library was authored by the generator
					-- with its pivot wherever it landed, and guessing the drop off one child part is
					-- what once left the Forest trees hovering 8-15 studs over the grass.
					seatModel(prop, x + ox, z + oz, math.random() * math.pi * 2, spec.sink)
					local _, size = prop:GetBoundingBox()
					reserveScatter(x + ox, z + oz, math.max(size.X, size.Z) * 0.5 + 3)
				end
			end
		end
	end
end

-- Runs the shared GROUND + LANDMARK + ATMOSPHERE + LIGHTING passes for one zone, so each
-- biome builder below only has to add its own signature MID-layer props.
local function buildBiomeBase(model, cx, cfg)
	-- NO table.clear HERE, AND THAT IS THE POINT. It used to clear, and the note at the top of
	-- addGroundDetail says it was moved out for exactly this reason -- but the call itself was
	-- left behind, so the move never took effect. addGroundDetail runs first in the zone loop and
	-- clears the table there; the crates and the glint coins then register their ground; and this
	-- line threw all of it away again a moment before the idols, the ruins and the mesh props
	-- picked their spots. That is why 148 crate stacks still ended up inside idol plinths after
	-- the reservation pass that was supposed to have fixed it.

	-- THE VILLAGE IS ALREADY THERE, AND NOTHING KNEW IT.
	--
	-- `scatterBlocks` only ever held what the scatter itself had placed, so the fixed installations
	-- built by the village pass were invisible to it -- and an idol whose plinth is 150 studs across
	-- was landing on top of them. One zone had an entire potion shop inside a plinth: cauldron,
	-- stand, brew and all, sealed in solid stone.
	--
	-- These coordinates are the village's, copied from the calls that place them (the shop at
	-- cx - 150, 150; the well at cx + 150, -168) and reserved before anything is scattered.
	-- THE SHOP'S CIRCLE HAS TO GROW WITH THE SHOP. 78 was measured against a 30x20 stall; at
	-- SHOP_SCALE the runner alone reaches 71 studs from the base point and the crates reach 55 to
	-- either side, so a scattered mesh prop was landing with its body inside the awning -- which is
	-- exactly the failure this whole list exists to stop, back again at a bigger size. Derived from
	-- the scale rather than re-typed, so it cannot fall behind the geometry a second time.
	-- MOVED TO THE TOP OF addGroundDetail. Reserving here was too late by three passes: the
	-- crates, the fourteen banner poles and the glint coins are all placed inside addGroundDetail,
	-- which runs first in the zone loop and clears the table -- so they picked their ground with
	-- the village invisible to them and a 40-stud banner pole came down 11 studs from the middle
	-- of the Volcano kiosk. The list lives beside the clear now, which is the only place it can be
	-- and cover everything downstream; nothing clears the table again between there and here.
	-- THE ARRIVAL SIGN WAS MISSING FROM THIS LIST, and it is the one that showed. It is built at
	-- the TOP of the zone loop, seven steps before anything scatters, at the hardcoded (cx - 104,
	-- 310) -- so it never asked for ground and nothing ever knew it was there. In Forest a 46-stud
	-- mesh tree came down 2.4 studs from the post's axis and swallowed the board whole; Mars is the
	-- same at 7.1, AntimatterZone grazes it at 20.4.
	--
	-- It also fixes a second bug at the far end of the loop. The idol-plinth sweep destroys loose
	-- decoration that ends up inside a plinth, and in Singularity it ate the post and left the board
	-- hanging in the air with nothing underneath it -- exactly the "this just hangs there" report
	-- that made the sign a physical post in the first place. Reserved here, BEFORE addIdols, an
	-- idol can no longer choose that ground at all.
	--
	-- 22 covers the board's 32-stud span and its two battens at +/-15. It is the sign's own
	-- half-footprint; the clearance a tree needs on top of it is the tree's business, and the CANOPY
	-- slot already demands clumpR + widthCap / 2 = 49 from every entry in this table.

	-- IDOLS AND RUINS FIRST, BEFORE ANY SCATTER.
	--
	-- They used to run after the litter, the mounds and the landmark. Both of them reserve their
	-- ground -- but a reservation made after the fact protects nothing: the crates, flowers, glint
	-- coins, banner poles and well stones had already been placed, and the plinth was then laid over
	-- the top of them. 1,154 props across the twenty zones ended up sealed inside solid stone,
	-- rendering every frame for nobody. Placed first, their reservations are in the table before a
	-- single scattered prop asks for a point.
	--
	-- IDOLS AND RUINS ARE OPT-OUT, NOT OPT-IN. There are twenty biome builders and each already
	-- passes its own palette here; making these two an extra key in every one of those tables would
	-- have meant twenty edits to add the feature and twenty more to change it. The accent is taken
	-- from whatever the zone already declared -- its landmark's accent first, its glow posts second
	-- -- so each zone's statues light up in its own colour with no new configuration at all.
	local accent = (cfg.idols and cfg.idols.accent)
		or (cfg.landmark and cfg.landmark.accent)
		or (cfg.glow and cfg.glow.color)
		or Color3.fromRGB(255, 226, 150)
	-- THE LANDMARK RESERVES BEFORE THE IDOLS AND THE RUINS DO, not after them. It stands at a FIXED
	-- point -- addLandmark is handed a cx and a z and simply builds there -- so it has never had to
	-- ask for ground, and nothing else knew it was coming. Reserved below the idols first time
	-- round, and a ruin duly came down on top of the Forest shrine's dais: two of the three things
	-- in this function that place themselves before the scatter had already chosen by then.
	-- Whatever is immovable goes into the table first.
	--
	-- IT IS ALSO OPT-OUT NOW, LIKE THE IDOLS, and for the same reason that was worth changing: SIX
	-- of the twenty biome builders never declared a landmark, so a third of the game had no monument
	-- at the back of the platform at all. The block build needed a style, a palette, a material and
	-- a trunk colour before it could draw anything -- four decisions per zone that nobody had made.
	-- A filed Landmark_<ZoneKey> needs none of them: the mesh is the whole figure, and only the dais
	-- and the two braziers take colour, which fall back exactly the way the idols' accent does.
	local landmarkCfg = cfg.landmark
	if not landmarkCfg and ACTIVE_ZONE_KEY then
		local folder = ServerStorage:FindFirstChild("PropMeshes")
		if folder and folder:FindFirstChild("Landmark_" .. ACTIVE_ZONE_KEY) then
			landmarkCfg = { base = Color3.fromRGB(150, 146, 138), accent = accent }
		end
	end

	if landmarkCfg then
		-- 100, not 70. The dais is now cut to fit its own monument, so the number here has to cover
		-- the LARGEST it can come out at: a 96 x 95 figure gives a 134 x 133 plinth (half-diagonal
		-- 94) with its braziers standing out at 81. One reservation has to cover both builds, and an
		-- under-reserved monument is props growing out of its steps.
		reserveScatter(cx + (landmarkCfg.dx or -210), landmarkCfg.z or -480, 100)
	end

	if cfg.idols ~= false then
		addIdols(model, cx, { count = (cfg.idols and cfg.idols.count) or 3, accent = accent })
	end
	if cfg.ruins ~= false then
		addRuins(model, cx, { count = (cfg.ruins and cfg.ruins.count) or 2, accent = accent })
	end

	-- MESH PROPS BEFORE THE LITTER AND THE MOUNDS. They are the biggest scattered things in the
	-- zone and every one of them claims its ground, so they have to be in the reservation table
	-- before the small stuff starts asking for points -- the ordering lesson the idols taught.
	addMeshProps(model, cx)
	-- ...and the small ground cover AFTER them, for the same reason in reverse: it reserves nothing,
	-- so it must be the thing that gives way rather than the thing given way to.
	addGroundClutter(model, cx)

	if cfg.litter then
		addGroundLitter(model, cx, cfg.litter)
	end
	if cfg.mounds then
		addMounds(model, cx, cfg.mounds)
	end
	if landmarkCfg then
		addLandmark(model, cx, landmarkCfg)
	end

	if cfg.atmosphere then
		addAtmosphere(model, cx, cfg.atmosphere)
	end
	if cfg.glow then
		addGlowPosts(model, cx, cfg.glow)
	end
end

-- Per-biome decoration builders. Each receives the zone model, zone config, and center X offset.
local decorationBuilders = {}

local forestTreeTemplate = ServerStorage:FindFirstChild("Models") and ServerStorage.Models:FindFirstChild("ForestTree")

decorationBuilders.Forest = function(model, zone, cx)
	local leaf = Color3.fromRGB(52, 132, 58)
	local glow = Color3.fromRGB(150, 255, 160)

	buildBiomeBase(model, cx, {
		litter = { count = 16, colors = { Color3.fromRGB(96, 104, 92), Color3.fromRGB(74, 86, 70), Color3.fromRGB(122, 128, 112) }, minSize = 3, maxSize = 10, material = Enum.Material.Rock },
		mounds = { count = 5, color = Color3.fromRGB(88, 156, 84), material = Enum.Material.Grass, minSize = 34, maxSize = 62 },
		landmark = { style = "greattree", base = leaf, accent = glow, trunkColor = Color3.fromRGB(96, 66, 42), material = Enum.Material.Wood },
		atmosphere = { color = Color3.fromRGB(215, 255, 190), color2 = Color3.fromRGB(255, 240, 160), height = 22, rate = 10, sizeStart = 0.8, sizeEnd = 1.8, transparency = 0.3, lifeMin = 5, lifeMax = 10, speedMin = 1, speedMax = 3, lightEmission = 0.9 },
		glow = { count = 5, color = Color3.fromRGB(255, 218, 130), height = 15, range = 30 },
	})

	-- MID: the tree canopy itself, varied scale + rotation so it never reads as clones.
	-- 15 trees at 0.8-1.6x scattered over 450x550 studs read as a mown lawn with shrubs on it;
	-- the reference forests are dense and the trees are taller than the player by a lot.
	-- 34 trees at up to 3.4x was a wall: from the arrival pad you could not see the shop, the
	-- portal or the boss. 20 at up to 2.3x still reads as a forest and leaves sightlines.
	-- 18 IS THE TREE'S OWN HALF-WIDTH, and passing it is what stops this loop dropping a canopy on
	-- top of something. These clones neither declared their size nor claimed their ground -- a bare
	-- `scatterPoint(cx, 195, 245)` -- so every fixed installation was invisible to them and every
	-- later prop was free to land inside them. That is four crate stacks, a fallen log, a glint coin
	-- and a glow bulb sealed inside Forest trunks, and it is the same arithmetic the mesh props
	-- already got right. The template is 14 studs across at 1x and scales to 2.3x, so 16 is the
	-- worst case and 18 leaves a little air.
	for _ = 1, 20 do
		local x, z = scatterPoint(cx, 195, 245, 18)
		if forestTreeTemplate then
			local tree = forestTreeTemplate:Clone()
			local geom = tree:FindFirstChild("body") and tree.body:FindFirstChild("body_geom")
			local scale = 1.1 + math.random() * 1.2
			tree:ScaleTo(scale)
			-- the mesh ships near-white and gets its green from its texture, which under the new
			-- lighting washed the whole canopy out to a flat mint. Tinting per clone fixes that and
			-- kills the cloned-prop read at the same time.
			if geom then
				geom.Color = Color3.fromRGB(126, 176, 104):Lerp(Color3.fromRGB(66, 124, 70), math.random())
			end
			-- parented BEFORE seating: GetBoundingBox on a model that is not in the datamodel yet
			-- still works, but ScaleTo has to have settled first and parenting is the cheapest way
			-- to be sure of the order
			tree.Parent = model
			seatModel(tree, x, z, math.random() * math.pi * 2)
			-- ...and claim it, measured rather than guessed: the scale is rolled per clone above.
			local _, tsize = tree:GetBoundingBox()
			reserveScatter(x, z, math.max(tsize.X, tsize.Z) * 0.5 + 3)
		else
			local h = math.random(14, 26)
			newPart({ Name = "Trunk", Size = Vector3.new(4, h, 4), Position = Vector3.new(x, h / 2, z), Color = Color3.fromRGB(92, 64, 40), Material = Enum.Material.Wood, Parent = model })
			newPart({ Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.new(21, 18, 21), Position = Vector3.new(x, h + 6, z), Color = leaf, Material = Enum.Material.Grass, CanCollide = false, Parent = model })
		end
	end

	-- MID: undergrowth -- bushes, glowing mushrooms and fallen logs at eye level
	for i = 1, 10 do
		local x, z = scatterPoint(cx)
		local s = math.random(7, 16)
		newPart({ Name = "Bush", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 0.8, s * 0.9), Orientation = Vector3.new(0, math.random(0, 360), 0), Position = Vector3.new(x, s * 0.34, z), Color = i % 2 == 0 and leaf or darken(leaf, 0.2), Material = Enum.Material.Grass, CanCollide = false, Parent = model })
	end
	for i = 1, 6 do
		local x, z = scatterPoint(cx)
		newPart({ Name = "MushroomStem", Size = Vector3.new(1.6, 5, 1.6), Position = Vector3.new(x, 2.5, z), Color = Color3.fromRGB(235, 226, 202), Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
		local cap = newPart({ Name = "MushroomCap", Shape = Enum.PartType.Ball, Size = Vector3.new(7.5, 4.5, 7.5), Position = Vector3.new(x, 5.8, z), Color = Color3.fromRGB(120, 255, 175), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		if i <= 3 then
			addLight(cap, Color3.fromRGB(120, 255, 175), 16, 1.5)
		end
	end
	for _ = 1, 5 do
		local x, z = scatterPoint(cx)
		newPart({ Name = "FallenLog", Shape = Enum.PartType.Cylinder, Size = Vector3.new(math.random(14, 26), 5, 5), Orientation = Vector3.new(0, math.random(0, 360), 0), Position = Vector3.new(x, 2.5, z), Color = Color3.fromRGB(86, 60, 38), Material = Enum.Material.Wood, CanCollide = false, Parent = model })
	end
end

local desertCactusTemplate = ServerStorage:FindFirstChild("Models") and ServerStorage.Models:FindFirstChild("DesertCactusMesh")
local petShopTemplate = ServerStorage:FindFirstChild("Models") and ServerStorage.Models:FindFirstChild("PetShopKiosk")
local desertStatueTemplate = ServerStorage:FindFirstChild("Models") and ServerStorage.Models:FindFirstChild("DesertStatue")

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
		-- that cannot be won. Two decimals only where it takes two.
		chance.Text = entry.chance < 1 and string.format("%.1f%%", entry.chance)
			or string.format(entry.chance < 10 and "%.1f%%" or "%.0f%%", entry.chance)
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

decorationBuilders.Desert = function(model, zone, cx)
	-- dense field of AI-generated cacti, varied scale/rotation so it doesn't read as clones
	if desertCactusTemplate then
		for i = 1, 26 do
			-- scatterPoint, not raw random: it is the one thing that keeps props out of the plaza,
			-- the boss arena and both gate mouths. Cacti were growing on the portal steps.
			local x, z = scatterPoint(cx, 205, 255)
			local cactus = desertCactusTemplate:Clone()
			local geom = cactus:FindFirstChild("body") and cactus.body:FindFirstChild("body_geom")
			local scale = 0.6 + math.random() * 1.1
			cactus:ScaleTo(scale)
			-- same guess, same bug class as the Forest trees -- see seatModel
			seatModel(cactus, x, z, math.random() * math.pi * 2)
			cactus.Parent = model
		end
	else
		for i = 1, 10 do
			local x, z = scatterPoint(cx, 190, 230)
			newPart({ Name = "Cactus", Size = Vector3.new(4, 14, 4), Position = Vector3.new(x, 7, z), Color = Color3.fromRGB(60, 120, 70), Material = Enum.Material.Grass, Parent = model })
			newPart({ Name = "CactusArm", Size = Vector3.new(3, 6, 3), Position = Vector3.new(x + 3, 10, z), Color = Color3.fromRGB(60, 120, 70), Material = Enum.Material.Grass, Parent = model })
		end
	end

	-- scattered sandstone boulders for ground-level variety
	for i = 1, 12 do
		local x, z = scatterPoint(cx, 205, 255)
		local s = math.random(6, 16)
		newPart({ Name = "DesertRock", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 0.7, s), Position = Vector3.new(x, s * 0.35, z), Color = Color3.fromRGB(200, 170, 120), Material = Enum.Material.Sandstone, Parent = model })
	end

	-- low dune mounds break up the flat floor
	for i = 1, 6 do
		local x, z = scatterPoint(cx, 190, 240)
		local s = math.random(30, 55)
		newPart({ Name = "Dune", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 0.28, s), Position = Vector3.new(x, s * 0.05, z), Color = Color3.fromRGB(225, 195, 140), Material = Enum.Material.Sand, CanCollide = false, Parent = model })
	end

	-- big statue landmark so the zone doesn't feel empty from a distance
	if desertStatueTemplate then
		local statue = desertStatueTemplate:Clone()
		-- A landmark has to read from the far end of a 1568-stud zone. Authored, this one is 43 studs
		-- tall -- barely more than the player's own rig at a late stage -- so it sat in the sand as
		-- just another prop instead of the thing you steer by. 2.6x puts it at ~111.
		local STATUE_SCALE = 2.6
		statue:ScaleTo(STATUE_SCALE)
		local geom = statue:FindFirstChild("body") and statue.body:FindFirstChild("body_geom")
		local halfHeight = geom and geom.Size.Y / 2 or 27 * STATUE_SCALE
		-- off the centre line, for the same reason as addLandmark: the -Z gate is behind it.
		-- The yaw matters: the mesh is authored facing -Z, i.e. the boss end, so unrotated it stood
		-- with its back to everyone walking in. Half a turn and it watches the arrival plaza.
		statue:PivotTo(CFrame.new(cx - 128, halfHeight - 3, -210) * CFrame.Angles(0, math.pi, 0))
		statue.Parent = model
	end

	-- small clay pottery scattered around so there's always something nearby to look at
	for i = 1, 10 do
		local x, z = scatterPoint(cx, 200, 250)
		local s = math.random(3, 6)
		newPart({ Name = "Pottery", Shape = Enum.PartType.Cylinder, Size = Vector3.new(s, s * 0.8, s * 0.8), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, s * 0.4, z), Color = Color3.fromRGB(180, 110, 70), Material = Enum.Material.Brick, Parent = model })
	end

	-- drifting sand-dust for atmosphere
	local dustPart = newPart({ Name = "DustAmbience", Size = Vector3.new(PLATFORM_WIDTH - 40, 1, PLATFORM_DEPTH - 40), Position = Vector3.new(cx, 25, 0), Transparency = 1, CanCollide = false, Parent = model })
	local dust = Instance.new("ParticleEmitter")
	dust.Color = ColorSequence.new(Color3.fromRGB(220, 195, 150))
	dust.Size = NumberSequence.new(2, 4)
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(6, 10)
	dust.Rate = 8
	dust.Speed = NumberRange.new(3, 6)
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Parent = dustPart

	-- shared ground litter + lantern accents so Desert matches the layering of the other biomes
	-- (the statue above is already this zone's landmark, so no extra one is added here)
	buildBiomeBase(model, cx, {
		litter = { count = 14, colors = { Color3.fromRGB(205, 175, 125), Color3.fromRGB(178, 145, 100), Color3.fromRGB(158, 130, 96) }, minSize = 3, maxSize = 9, material = Enum.Material.Sandstone },
		glow = { count = 5, color = Color3.fromRGB(255, 200, 110), height = 16, range = 30 },
	})

	-- MID: weathered sandstone pillars, half toppled, for silhouette variety at eye level
	for _ = 1, 8 do
		local x, z = scatterPoint(cx)
		local h = math.random(9, 24)
		newPart({ Name = "BrokenPillar", Size = Vector3.new(6, h, 6), Orientation = Vector3.new(math.random(-9, 9), math.random(0, 360), math.random(-9, 9)), Position = Vector3.new(x, h / 2, z), Color = Color3.fromRGB(198, 168, 118), Material = Enum.Material.Sandstone, Parent = model })
	end
end

decorationBuilders.Ocean = function(model, zone, cx)
	local shallow = Color3.fromRGB(72, 176, 232)
	local kelpColor = Color3.fromRGB(46, 122, 86)
	local coralPalette = { Color3.fromRGB(255, 118, 138), Color3.fromRGB(255, 186, 92), Color3.fromRGB(168, 112, 255), Color3.fromRGB(110, 232, 208) }

	-- No full-platform glass sheets any more. There were two -- one at knee height, one at y = 26 --
	-- and between them every sightline in the zone went through blue glass with a lid over it: the
	-- shop, the eggs, the pets and the player all came out washed grey-blue, and standing in the
	-- middle of it read as swimming rather than as a reef. The seabed is sold by what stands on it
	-- instead, plus tide pools you can see the sand through and walk around.
	for _ = 1, 7 do
		local x, z = scatterPoint(cx, 190, 240)
		local s = math.random(34, 68)
		local aspect = 0.7 + math.random() * 0.5
		newPart({ Name = "TidePoolRim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, s + 9, s * aspect + 9), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 0.2, z), Color = Color3.fromRGB(228, 210, 170), Material = Enum.Material.Sand, CanCollide = false, Parent = model })
		local pool = newPart({ Name = "TidePool", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, s, s * aspect), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 0.45, z), Color = shallow, Material = Enum.Material.Glass, Transparency = 0.45, CanCollide = false, Parent = model })
		addLight(pool, lighten(shallow, 0.4), 18, 0.7)
	end

	buildBiomeBase(model, cx, {
		litter = { count = 22, name = "Shell", colors = { Color3.fromRGB(242, 228, 204), Color3.fromRGB(214, 192, 166), Color3.fromRGB(255, 206, 190) }, minSize = 2, maxSize = 6, flat = 0.42, material = Enum.Material.Sand },
		mounds = { count = 7, name = "Sandbar", color = Color3.fromRGB(236, 216, 172), material = Enum.Material.Sand, minSize = 38, maxSize = 70, flat = 0.18 },
		landmark = { style = "arch", base = Color3.fromRGB(214, 198, 172), accent = Color3.fromRGB(110, 232, 208), material = Enum.Material.Sandstone },
		atmosphere = { color = lighten(shallow, 0.55), color2 = Color3.fromRGB(255, 255, 255), height = 8, rate = 20, sizeStart = 0.6, sizeEnd = 2.4, transparency = 0.45, lifeMin = 5, lifeMax = 9, speedMin = 5, speedMax = 9, lightEmission = 0.7, acceleration = Vector3.new(0, 7, 0) },
		glow = { count = 6, color = Color3.fromRGB(94, 236, 255), height = 11, range = 26 },
	})

	-- MID: kelp forest. Segments that lean a little further with every step up are the one
	-- silhouette that sells "underwater" from across the platform.
	for _ = 1, 22 do
		local x, z = scatterPoint(cx, 200, 250)
		local segments = math.random(3, 6)
		local lean = math.random(-7, 7)
		local y = 0
		for s = 1, segments do
			local h = math.random(9, 15)
			newPart({ Name = "Kelp", Size = Vector3.new(2.4, h, 1.2), Orientation = Vector3.new(lean * s * 0.5, math.random(0, 360), lean * s), Position = Vector3.new(x + s * lean * 0.25, y + h / 2, z), Color = s % 2 == 0 and kelpColor or darken(kelpColor, 0.18), Material = Enum.Material.Grass, CanCollide = false, Parent = model })
			y = y + h - 1
		end
		local bulb = newPart({ Name = "KelpBulb", Shape = Enum.PartType.Ball, Size = Vector3.new(4, 4, 4), Position = Vector3.new(x + segments * lean * 0.25, y + 2, z), Color = Color3.fromRGB(190, 255, 150), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		if math.random(1, 4) == 1 then
			addLight(bulb, Color3.fromRGB(190, 255, 150), 14, 1.2)
		end
	end

	-- MID: coral heads and fans. The hot palette against the blue wash is what stops the seabed
	-- reading as one flat colour -- reefs are loud, not tasteful.
	for _ = 1, 16 do
		local x, z = scatterPoint(cx)
		local c = coralPalette[math.random(1, #coralPalette)]
		for i = 1, math.random(3, 5) do
			local s = math.random(5, 12)
			newPart({ Name = "Coral", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 1.3, s), Orientation = Vector3.new(math.random(-14, 14), math.random(0, 360), math.random(-14, 14)), Position = Vector3.new(x + math.random(-7, 7), s * 0.55, z + math.random(-7, 7)), Color = i % 2 == 0 and c or lighten(c, 0.25), Material = Enum.Material.Foil, CanCollide = false, Parent = model })
		end
	end
	for _ = 1, 12 do
		local x, z = scatterPoint(cx)
		local h = math.random(8, 16)
		newPart({ Name = "CoralFan", Size = Vector3.new(h * 1.2, h, 0.8), Orientation = Vector3.new(0, math.random(0, 360), math.random(-12, 12)), Position = Vector3.new(x, h / 2 + 1, z), Color = coralPalette[math.random(1, #coralPalette)], Material = Enum.Material.Neon, Transparency = 0.25, CanCollide = false, Parent = model })
	end

	-- MID: bubble vents. The drifting atmosphere above needs visible sources on the floor or the
	-- rising motion reads as unexplained fog.
	for _ = 1, 6 do
		local x, z = scatterPoint(cx)
		local vent = newPart({ Name = "BubbleVent", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 7, 7), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 1, z), Color = Color3.fromRGB(70, 70, 80), Material = Enum.Material.Rock, CanCollide = false, Parent = model })
		local bubbles = Instance.new("ParticleEmitter")
		bubbles.Color = ColorSequence.new(Color3.fromRGB(220, 245, 255))
		bubbles.Size = NumberSequence.new(0.6, 1.6)
		bubbles.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
		bubbles.Lifetime = NumberRange.new(3, 5)
		bubbles.Rate = 14
		bubbles.Speed = NumberRange.new(6, 10)
		bubbles.SpreadAngle = Vector2.new(12, 12)
		bubbles.Acceleration = Vector3.new(0, 8, 0)
		bubbles.LightEmission = 0.6
		bubbles.Parent = vent
	end

	-- MID: a half-buried wreck. One large man-made silhouette gives the open mid-field something
	-- to navigate by; parked off to the port side so it clears both the plaza and the arrival pad.
	local wx, wz = cx - 128, 96
	newPart({ Name = "WreckKeel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(74, 12, 12), Orientation = Vector3.new(0, 24, 82), Position = Vector3.new(wx, 5, wz), Color = Color3.fromRGB(84, 62, 46), Material = Enum.Material.Wood, Parent = model })
	for i = -3, 3 do
		newPart({ Name = "WreckRib", Size = Vector3.new(1.8, 22 - math.abs(i) * 3, 26), Orientation = Vector3.new(0, 24, i * 6), Position = Vector3.new(wx + i * 10, 10, wz + i * 4), Color = Color3.fromRGB(96, 72, 52), Material = Enum.Material.Wood, CanCollide = false, Parent = model })
	end
	newPart({ Name = "WreckMast", Size = Vector3.new(3, 46, 3), Orientation = Vector3.new(0, 24, 22), Position = Vector3.new(wx + 6, 24, wz + 2), Color = Color3.fromRGB(76, 56, 40), Material = Enum.Material.Wood, CanCollide = false, Parent = model })
	local lantern = newPart({ Name = "WreckLantern", Shape = Enum.PartType.Ball, Size = Vector3.new(5, 5, 5), Position = Vector3.new(wx + 14, 42, wz + 6), Color = Color3.fromRGB(120, 240, 255), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	addLight(lantern, Color3.fromRGB(120, 240, 255), 30, 2.4)
end

decorationBuilders.Volcano = function(model, zone, cx)
	local lavaColor = Color3.fromRGB(255, 108, 28)
	local hotColor = Color3.fromRGB(255, 196, 70)
	local basalt = Color3.fromRGB(44, 32, 32)
	local coneZ = -196

	-- SIGNATURE LANDMARK: the cone, hand-built instead of routed through addLandmark so it can be
	-- a real stacked mountain with a lit crater. It owns the back of the platform, which is why
	-- this builder never asks buildBiomeBase for a landmark of its own.
	--
	-- Stood 150 studs to port, cone and lava flows together: the mountain is 172 wide and the gate
	-- to the next zone now opens in the middle of the -Z wall, directly under where it used to sit.
	-- Its far skirt runs into the boundary cliffs at that offset, which is how a mountain should
	-- meet a canyon wall anyway.
	ACTIVE_FRAME = CFrame.new(-150, 0, 0)
	local y = 0
	for i = 0, 6 do
		local w = 172 - i * 22
		local h = 15
		newPart({ Name = "VolcanoCone", Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, w, w), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(cx, y + h / 2, coneZ), Color = i % 2 == 0 and basalt or darken(basalt, 0.25), Material = Enum.Material.Basalt, Parent = model })
		y = y + h - 1
	end
	newPart({ Name = "CraterRim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(7, 46, 46), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(cx, y + 2, coneZ), Color = darken(basalt, 0.35), Material = Enum.Material.Basalt, Parent = model })
	local craterGlow = newPart({ Name = "CraterLava", Shape = Enum.PartType.Cylinder, Size = Vector3.new(5, 34, 34), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(cx, y + 5, coneZ), Color = lavaColor, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	addLight(craterGlow, lavaColor, 60, 4)

	-- smoke column plus a spray of embers arcing back down: the crater has to look like it is
	-- doing something, otherwise the mountain is just a grey cone
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(90, 78, 74), Color3.fromRGB(40, 34, 32))
	smoke.Size = NumberSequence.new(14, 42)
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(4, 7)
	smoke.Rate = 12
	smoke.Speed = NumberRange.new(14, 22)
	smoke.SpreadAngle = Vector2.new(18, 18)
	smoke.Acceleration = Vector3.new(0, 6, 0)
	smoke.Parent = craterGlow
	local embers = Instance.new("ParticleEmitter")
	embers.Color = ColorSequence.new(hotColor, lavaColor)
	embers.Size = NumberSequence.new(1.4, 0.3)
	embers.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	embers.Lifetime = NumberRange.new(2.5, 4.5)
	embers.Rate = 24
	embers.Speed = NumberRange.new(28, 46)
	embers.SpreadAngle = Vector2.new(45, 45)
	embers.Acceleration = Vector3.new(0, -22, 0)
	embers.LightEmission = 1
	embers.Parent = craterGlow

	-- SIGNATURE: lava, routed as two flows spilling off the cone toward the outer edges instead
	-- of one slab in the middle -- the plaza has to stay walkable and unlit by it.
	for _, side in ipairs({ -1, 1 }) do
		local px, pz = cx + side * 34, coneZ + 40
		for i = 1, 9 do
			local w = 16 + i * 2.5
			newPart({ Name = "LavaFlow", Size = Vector3.new(w, 1.2, 26), Orientation = Vector3.new(0, side * i * 3, 0), Position = Vector3.new(px + side * i * 12, 0.9, pz + i * 17), Color = i % 3 == 0 and hotColor or lavaColor, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
			newPart({ Name = "LavaBank", Size = Vector3.new(w + 10, 2.4, 26), Orientation = Vector3.new(0, side * i * 3, 0), Position = Vector3.new(px + side * i * 12, 0.6, pz + i * 17), Color = darken(basalt, 0.15), Material = Enum.Material.Basalt, CanCollide = false, Parent = model })
		end
	end
	ACTIVE_FRAME = nil

	-- outlying lava pools with a cooled crust ring, so the far corners glow too
	for _ = 1, 5 do
		local x, z = scatterPoint(cx, 195, 245)
		local s = math.random(22, 40)
		newPart({ Name = "PoolCrust", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, s + 9, s + 9), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 0.6, z), Color = darken(basalt, 0.1), Material = Enum.Material.Basalt, CanCollide = false, Parent = model })
		local pool = newPart({ Name = "LavaPool", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, s, s), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 1.1, z), Color = lavaColor, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(pool, lavaColor, 30, 2.2)
	end

	-- MID: basalt colonnades. Clustered hexagonal-ish pillars are the classic cooled-lava
	-- formation and give the mid-field a jagged skyline the loose boulders never produced.
	for _ = 1, 10 do
		local x, z = scatterPoint(cx)
		for i = 1, math.random(4, 7) do
			local h = math.random(12, 34)
			newPart({ Name = "BasaltColumn", Size = Vector3.new(6, h, 6), Orientation = Vector3.new(0, math.random(0, 360), 0), Position = Vector3.new(x + math.random(-9, 9), h / 2, z + math.random(-9, 9)), Color = i % 2 == 0 and basalt or lighten(basalt, 0.12), Material = Enum.Material.Basalt, Parent = model })
		end
	end

	-- MID: fissures. Cracks of light in the floor make the ground itself look like it is barely
	-- holding, which no amount of dark rock on top of dark rock can do.
	for _ = 1, 16 do
		local x, z = scatterPoint(cx, 200, 250)
		newPart({ Name = "Fissure", Size = Vector3.new(math.random(18, 46), 0.6, math.random(2, 5)), Orientation = Vector3.new(0, math.random(0, 360), 0), Position = Vector3.new(x, 0.4, z), Color = hotColor, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	end

	-- MID: obsidian spikes at eye level, glassy and near-black so they read as silhouette
	for _ = 1, 12 do
		local x, z = scatterPoint(cx)
		local h = math.random(10, 26)
		newPart({ Name = "ObsidianSpike", Size = Vector3.new(5, h, 5), Orientation = Vector3.new(math.random(-16, 16), math.random(0, 360), math.random(-16, 16)), Position = Vector3.new(x, h / 2, z), Color = Color3.fromRGB(22, 16, 22), Material = Enum.Material.Glass, Parent = model })
	end

	buildBiomeBase(model, cx, {
		litter = { count = 20, name = "LavaRock", colors = { Color3.fromRGB(46, 34, 34), Color3.fromRGB(30, 22, 22), Color3.fromRGB(70, 42, 34) }, minSize = 4, maxSize = 13, material = Enum.Material.Basalt },
		mounds = { count = 5, name = "AshMound", color = Color3.fromRGB(58, 48, 46), material = Enum.Material.Slate, minSize = 30, maxSize = 58 },
		atmosphere = { color = Color3.fromRGB(255, 150, 60), color2 = Color3.fromRGB(120, 40, 20), height = 34, rate = 16, sizeStart = 1.2, sizeEnd = 0.4, transparency = 0.3, lifeMin = 4, lifeMax = 8, speedMin = 3, speedMax = 7, lightEmission = 1, acceleration = Vector3.new(0, 5, 0) },
		glow = { count = 5, color = Color3.fromRGB(255, 130, 50), height = 14, range = 30, brightness = 2.5 },
	})
end

decorationBuilders.Moon = function(model, zone, cx)
	local regolith = Color3.fromRGB(178, 178, 184)
	local shadow = Color3.fromRGB(96, 96, 104)

	buildBiomeBase(model, cx, {
		litter = { count = 24, name = "MoonRock", colors = { regolith, shadow, Color3.fromRGB(146, 146, 152) }, minSize = 3, maxSize = 12, material = Enum.Material.Slate },
		mounds = { count = 6, name = "RegolithMound", color = Color3.fromRGB(158, 158, 166), material = Enum.Material.Slate, minSize = 34, maxSize = 64, flat = 0.2 },
		landmark = { style = "orb", base = Color3.fromRGB(120, 120, 130), accent = Color3.fromRGB(150, 200, 255), coreColor = Color3.fromRGB(58, 118, 210), material = Enum.Material.Slate },
		atmosphere = { color = Color3.fromRGB(220, 220, 235), height = 12, rate = 5, sizeStart = 0.5, sizeEnd = 1.6, transparency = 0.75, lifeMin = 7, lifeMax = 12, speedMin = 0.5, speedMax = 2, lightEmission = 0.3 },
		glow = { count = 6, color = Color3.fromRGB(210, 235, 255), height = 13, range = 26 },
	})

	-- the landmark orb is Earth hanging over the horizon; a few continent patches stop it reading
	-- as a plain blue ball, which is the whole reason it works as a "you are on the Moon" cue
	for i = 1, 5 do
		local a = (i / 5) * math.pi * 2
		local s = math.random(11, 19)
		newPart({ Name = "EarthContinent", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 0.5, s), Orientation = Vector3.new(math.random(-40, 40), math.random(0, 360), math.random(-40, 40)), Position = Vector3.new(cx + math.cos(a) * 19, 82 + math.sin(a) * 13, -210 + math.random(-6, 6)), Color = Color3.fromRGB(70, 160, 90), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	end

	-- SIGNATURE: craters, rebuilt as a sunken dark floor ringed by thrown-up rubble. The old flat
	-- disc vanished the moment you stood next to it; a rim you can see edge-on does not.
	for _ = 1, 9 do
		local x, z = scatterPoint(cx, 200, 250)
		local r = math.random(12, 30)
		newPart({ Name = "Crater", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.5, r * 2, r * 2), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 0.4, z), Color = Color3.fromRGB(78, 78, 86), Material = Enum.Material.Slate, CanCollide = false, Parent = model })
		local rimCount = 10 + math.floor(r / 4)
		for i = 1, rimCount do
			local a = (i / rimCount) * math.pi * 2
			local s = math.random(4, 8)
			newPart({ Name = "CraterRim", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 0.55, s), Orientation = Vector3.new(0, math.random(0, 360), 0), Position = Vector3.new(x + math.cos(a) * r, s * 0.2, z + math.sin(a) * r), Color = regolith, Material = Enum.Material.Slate, CanCollide = false, Parent = model })
		end
	end

	-- MID: a landed module and its flag. One built object is worth twenty more rocks here --
	-- it is the only thing that gives the grey plain a sense of scale.
	local lx, lz = cx + 118, 92
	newPart({ Name = "LanderBody", Size = Vector3.new(20, 12, 20), Orientation = Vector3.new(0, 22, 0), Position = Vector3.new(lx, 14, lz), Color = Color3.fromRGB(228, 210, 150), Material = Enum.Material.Foil, Parent = model })
	newPart({ Name = "LanderCabin", Size = Vector3.new(13, 11, 13), Orientation = Vector3.new(0, 22, 0), Position = Vector3.new(lx, 25, lz), Color = Color3.fromRGB(200, 200, 210), Material = Enum.Material.Metal, Parent = model })
	for i = 1, 4 do
		local a = math.rad(45 + i * 90)
		newPart({ Name = "LanderLeg", Size = Vector3.new(1.6, 18, 1.6), Orientation = Vector3.new(math.cos(a) * 22, 0, math.sin(a) * 22), Position = Vector3.new(lx + math.cos(a) * 13, 7, lz + math.sin(a) * 13), Color = Color3.fromRGB(150, 150, 160), Material = Enum.Material.Metal, CanCollide = false, Parent = model })
		newPart({ Name = "LanderFoot", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 7, 7), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(lx + math.cos(a) * 17, 0.8, lz + math.sin(a) * 17), Color = Color3.fromRGB(130, 130, 140), Material = Enum.Material.Metal, CanCollide = false, Parent = model })
	end
	local beacon = newPart({ Name = "LanderBeacon", Shape = Enum.PartType.Ball, Size = Vector3.new(4.5, 4.5, 4.5), Position = Vector3.new(lx, 32, lz), Color = Color3.fromRGB(255, 90, 90), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	addLight(beacon, Color3.fromRGB(255, 90, 90), 26, 2)
	newPart({ Name = "FlagPole", Size = Vector3.new(0.9, 26, 0.9), Position = Vector3.new(lx + 24, 13, lz + 8), Color = Color3.fromRGB(220, 220, 225), Material = Enum.Material.Metal, CanCollide = false, Parent = model })
	newPart({ Name = "Flag", Size = Vector3.new(0.4, 8, 13), Position = Vector3.new(lx + 24, 22, lz + 15), Color = Color3.fromRGB(224, 70, 70), Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })

	-- MID: a dish array pointed at the sky, so the mid-ground carries a second built read
	for i = 1, 3 do
		local dx = cx - 150 + i * 26
		newPart({ Name = "DishMast", Size = Vector3.new(2.2, 20, 2.2), Position = Vector3.new(dx, 10, -108), Color = Color3.fromRGB(140, 140, 150), Material = Enum.Material.Metal, CanCollide = false, Parent = model })
		newPart({ Name = "Dish", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 18, 18), Orientation = Vector3.new(38, 0, 90), Position = Vector3.new(dx, 22, -108), Color = Color3.fromRGB(226, 226, 232), Material = Enum.Material.Foil, CanCollide = false, Parent = model })
	end

	-- MID: pebbles hanging just off the ground. Low gravity costs nothing to imply and it is the
	-- one thing that makes the Moon feel unlike Mars two zones later.
	for _ = 1, 22 do
		local x, z = scatterPoint(cx, 200, 250)
		local s = math.random(2, 5)
		newPart({ Name = "FloatingPebble", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s, s), Orientation = Vector3.new(math.random(0, 360), math.random(0, 360), 0), Position = Vector3.new(x, math.random(4, 16), z), Color = shadow, Material = Enum.Material.Slate, CanCollide = false, Parent = model })
	end

	-- MID: boulder piles at eye level so the horizon is not a perfectly clean line
	for _ = 1, 10 do
		local x, z = scatterPoint(cx)
		for i = 1, math.random(3, 6) do
			local s = math.random(8, 18)
			newPart({ Name = "MoonBoulder", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 0.85, s * 0.95), Orientation = Vector3.new(math.random(-20, 20), math.random(0, 360), math.random(-20, 20)), Position = Vector3.new(x + math.random(-11, 11), s * 0.4, z + math.random(-11, 11)), Color = i % 2 == 0 and regolith or shadow, Material = Enum.Material.Slate, Parent = model })
		end
	end
end

decorationBuilders.Mars = function(model, zone, cx)
	local rust = Color3.fromRGB(178, 88, 56)
	local dark = Color3.fromRGB(112, 54, 38)
	local ember = Color3.fromRGB(255, 148, 84)

	buildBiomeBase(model, cx, {
		litter = { count = 24, name = "MarsRock", colors = { rust, dark, Color3.fromRGB(148, 74, 50) }, minSize = 3, maxSize = 12, material = Enum.Material.Rock },
		mounds = { count = 6, name = "DustRidge", color = Color3.fromRGB(196, 108, 72), material = Enum.Material.Sand, minSize = 36, maxSize = 68, flat = 0.22 },
		landmark = { style = "spire", base = dark, accent = ember, material = Enum.Material.Rock },
		atmosphere = { color = Color3.fromRGB(228, 152, 104), color2 = Color3.fromRGB(150, 82, 58), height = 30, rate = 14, sizeStart = 3, sizeEnd = 7, transparency = 0.55, lifeMin = 6, lifeMax = 11, speedMin = 4, speedMax = 9 },
		glow = { count = 5, color = ember, height = 15, range = 28 },
	})

	-- MID: mesas. Flat-topped stacks with visible strata are the one silhouette that separates
	-- Mars from the Moon two zones back -- rounded boulders alone read identically at distance.
	for _ = 1, 6 do
		local x, z = scatterPoint(cx, 190, 240)
		local y = 0
		local w = math.random(34, 58)
		for i = 1, math.random(3, 5) do
			local h = math.random(7, 13)
			newPart({ Name = "Mesa", Size = Vector3.new(w, h, w * (0.75 + math.random() * 0.4)), Orientation = Vector3.new(0, math.random(0, 360), 0), Position = Vector3.new(x, y + h / 2, z), Color = i % 2 == 0 and rust or dark, Material = Enum.Material.Rock, Parent = model })
			y = y + h
			w = w - math.random(5, 10)
			if w < 12 then break end
		end
	end

	-- MID: dry channels cut into the floor. Long, thin and darker than the ground, so the plain
	-- reads as eroded terrain rather than a poured slab with rocks on it.
	for _ = 1, 14 do
		local x, z = scatterPoint(cx, 200, 250)
		newPart({ Name = "DryChannel", Size = Vector3.new(math.random(30, 80), 0.5, math.random(5, 12)), Orientation = Vector3.new(0, math.random(0, 360), 0), Position = Vector3.new(x, 0.3, z), Color = darken(dark, 0.35), Material = Enum.Material.Rock, CanCollide = false, Parent = model })
	end

	-- MID: dust devils. Thin, tall and moving -- the only vertical motion on an otherwise static
	-- plain, and cheap: one anchored column carrying the emitter.
	for _ = 1, 5 do
		local x, z = scatterPoint(cx, 195, 245)
		local column = newPart({ Name = "DustDevil", Size = Vector3.new(6, 44, 6), Position = Vector3.new(x, 22, z), Transparency = 1, CanCollide = false, Parent = model })
		local swirl = Instance.new("ParticleEmitter")
		swirl.Color = ColorSequence.new(Color3.fromRGB(226, 158, 112), Color3.fromRGB(160, 92, 62))
		swirl.Size = NumberSequence.new(3, 9)
		swirl.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		swirl.Lifetime = NumberRange.new(2.5, 4)
		swirl.Rate = 22
		swirl.Speed = NumberRange.new(2, 5)
		swirl.SpreadAngle = Vector2.new(14, 14)
		swirl.Acceleration = Vector3.new(0, 9, 0)
		swirl.Parent = column
	end

	-- MID: a rover and its solar array. One built object gives the plain a sense of scale that
	-- no amount of extra rock can, and marks Mars as "visited" rather than merely red.
	local rx, rz = cx - 124, 88
	newPart({ Name = "RoverDeck", Size = Vector3.new(22, 5, 13), Orientation = Vector3.new(0, 18, 0), Position = Vector3.new(rx, 8, rz), Color = Color3.fromRGB(228, 222, 208), Material = Enum.Material.Foil, Parent = model })
	newPart({ Name = "RoverMast", Size = Vector3.new(1.8, 13, 1.8), Position = Vector3.new(rx + 6, 17, rz), Color = Color3.fromRGB(150, 150, 158), Material = Enum.Material.Metal, CanCollide = false, Parent = model })
	local cam = newPart({ Name = "RoverEye", Shape = Enum.PartType.Ball, Size = Vector3.new(3.4, 3.4, 3.4), Position = Vector3.new(rx + 6, 24, rz), Color = Color3.fromRGB(120, 220, 255), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	addLight(cam, Color3.fromRGB(120, 220, 255), 22, 2)
	for _, side in ipairs({ -1, 1 }) do
		newPart({ Name = "RoverPanel", Size = Vector3.new(18, 0.7, 11), Orientation = Vector3.new(0, 18, side * 9), Position = Vector3.new(rx, 12, rz + side * 12), Color = Color3.fromRGB(46, 62, 140), Material = Enum.Material.Glass, CanCollide = false, Parent = model })
		for i = -1, 1, 2 do
			newPart({ Name = "RoverWheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 8, 8), Orientation = Vector3.new(0, 108, 0), Position = Vector3.new(rx + i * 8, 4, rz + side * 7), Color = Color3.fromRGB(60, 60, 66), Material = Enum.Material.Metal, CanCollide = false, Parent = model })
		end
	end

	-- MID: frost patches. A cold colour scattered through the rust keeps the palette from going
	-- monochrome, which is what made the old red-ball version look flat.
	for _ = 1, 9 do
		local x, z = scatterPoint(cx, 200, 250)
		local s = math.random(10, 24)
		newPart({ Name = "FrostPatch", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, s, s), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 0.4, z), Color = Color3.fromRGB(214, 236, 255), Material = Enum.Material.Ice, Transparency = 0.2, CanCollide = false, Parent = model })
	end
end

decorationBuilders.Galaxy = function(model, zone, cx)
	local violet = Color3.fromRGB(140, 90, 220)
	local cyan = Color3.fromRGB(120, 200, 255)
	local starPalette = { Color3.fromRGB(255, 255, 225), Color3.fromRGB(190, 215, 255), Color3.fromRGB(255, 200, 170) }

	buildBiomeBase(model, cx, {
		litter = { count = 20, name = "Meteorite", colors = { Color3.fromRGB(52, 40, 78), Color3.fromRGB(78, 58, 118), Color3.fromRGB(34, 26, 54) }, minSize = 3, maxSize = 11, material = Enum.Material.Slate },
		mounds = { count = 5, name = "StardustDrift", color = Color3.fromRGB(84, 58, 130), material = Enum.Material.Foil, minSize = 34, maxSize = 64, flat = 0.2 },
		landmark = { style = "ring", base = Color3.fromRGB(58, 42, 92), accent = violet, coreColor = Color3.fromRGB(255, 240, 200), material = Enum.Material.Foil },
		atmosphere = { color = lighten(violet, 0.4), color2 = cyan, height = 40, rate = 16, sizeStart = 0.5, sizeEnd = 2.2, transparency = 0.35, lifeMin = 7, lifeMax = 13, speedMin = 1, speedMax = 4, lightEmission = 1 },
		glow = { count = 6, color = cyan, height = 16, range = 30 },
	})

	-- SIGNATURE: a dense star field overhead. Small, varied and high, so looking up actually
	-- reads as space -- the old 30 identical dots at head height read as floating litter.
	for _ = 1, 90 do
		local x, z = scatterPoint(cx, 205, 255)
		local s = 1 + math.random() * 2.6
		newPart({ Name = "Star", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s, s), Position = Vector3.new(x, math.random(40, 115), z), Color = starPalette[math.random(1, #starPalette)], Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	end

	-- MID: floating asteroid islands. Rock underside, lit crystal crown -- gives the empty air
	-- between floor and stars something to read, and the zone its "you are in orbit" cue.
	for _ = 1, 9 do
		local x, z = scatterPoint(cx, 190, 240)
		local y = math.random(26, 62)
		local w = math.random(16, 34)
		newPart({ Name = "AsteroidTop", Size = Vector3.new(w, 5, w * 0.85), Orientation = Vector3.new(math.random(-6, 6), math.random(0, 360), math.random(-6, 6)), Position = Vector3.new(x, y, z), Color = Color3.fromRGB(64, 48, 96), Material = Enum.Material.Foil, CanCollide = false, Parent = model })
		newPart({ Name = "AsteroidKeel", Shape = Enum.PartType.Ball, Size = Vector3.new(w * 0.8, w * 0.9, w * 0.7), Position = Vector3.new(x, y - w * 0.4, z), Color = Color3.fromRGB(42, 32, 66), Material = Enum.Material.Slate, CanCollide = false, Parent = model })
		for i = 1, math.random(2, 4) do
			local h = math.random(6, 14)
			local crystal = newPart({ Name = "AsteroidCrystal", Size = Vector3.new(2.6, h, 2.6), Orientation = Vector3.new(math.random(-14, 14), math.random(0, 360), math.random(-14, 14)), Position = Vector3.new(x + math.random(-7, 7), y + 2.5 + h / 2, z + math.random(-7, 7)), Color = i % 2 == 0 and cyan or violet, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
			if i == 1 then
				addLight(crystal, cyan, 24, 2)
			end
		end
	end

	-- MID: nebula ribbons. Long translucent sheets at shallow angles do what a particle field
	-- cannot -- give the sky structure you can navigate by.
	for _ = 1, 10 do
		local x, z = scatterPoint(cx, 195, 245)
		newPart({ Name = "NebulaRibbon", Size = Vector3.new(math.random(60, 130), 1.4, math.random(18, 40)), Orientation = Vector3.new(math.random(-18, 18), math.random(0, 360), math.random(-12, 12)), Position = Vector3.new(x, math.random(30, 80), z), Color = math.random(1, 2) == 1 and violet or Color3.fromRGB(220, 110, 220), Material = Enum.Material.Neon, Transparency = 0.72, CanCollide = false, Parent = model })
	end

	-- MID: a ringed gas giant low at the back. One enormous object fixes the sense of distance
	-- that scattered small props keep destroying.
	local px, pz = cx + 96, -224
	local planet = newPart({ Name = "GasGiant", Shape = Enum.PartType.Ball, Size = Vector3.new(88, 88, 88), Position = Vector3.new(px, 78, pz), Color = Color3.fromRGB(196, 140, 96), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	addLight(planet, Color3.fromRGB(255, 190, 130), 70, 2.4)
	for i = 1, 3 do
		newPart({ Name = "GiantRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 118 + i * 20, 118 + i * 20), Orientation = Vector3.new(16, 0, 90), Position = Vector3.new(px, 78, pz), Color = i == 2 and Color3.fromRGB(255, 226, 180) or Color3.fromRGB(206, 168, 128), Material = Enum.Material.Neon, Transparency = 0.4 + i * 0.12, CanCollide = false, Parent = model })
	end

	-- MID: launch pylons at eye level, so the floor is not just a dark plane under a busy sky
	for _ = 1, 10 do
		local x, z = scatterPoint(cx)
		local h = math.random(12, 28)
		newPart({ Name = "StarPylon", Size = Vector3.new(3.4, h, 3.4), Orientation = Vector3.new(0, math.random(0, 360), 0), Position = Vector3.new(x, h / 2, z), Color = Color3.fromRGB(52, 40, 82), Material = Enum.Material.Metal, Parent = model })
		local tip = newPart({ Name = "StarPylonTip", Shape = Enum.PartType.Ball, Size = Vector3.new(5, 5, 5), Position = Vector3.new(x, h + 2, z), Color = violet, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(tip, violet, 20, 1.6)
	end
end

decorationBuilders.BlackHole = function(model, zone, cx)
	local plasma = Color3.fromRGB(180, 80, 240)
	local hot = Color3.fromRGB(255, 170, 90)
	local shell = Color3.fromRGB(26, 20, 34)
	local coreZ = -196

	-- SIGNATURE LANDMARK: the hole itself, hand-built rather than routed through addLandmark so
	-- the accretion disc can be a real tilted stack of rings around a pure-black sphere. It owns
	-- the back of the platform, which is why buildBiomeBase below is asked for no landmark.
	local core = newPart({ Name = "EventHorizon", Shape = Enum.PartType.Ball, Size = Vector3.new(64, 64, 64), Position = Vector3.new(cx, 86, coreZ), Color = Color3.fromRGB(0, 0, 0), Material = Enum.Material.SmoothPlastic, Reflectance = 0, CanCollide = false, Parent = model })
	for i = 1, 5 do
		local d = 96 + i * 26
		local ring = newPart({ Name = "AccretionRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.4, d, d), Orientation = Vector3.new(22, 0, 90), Position = Vector3.new(cx, 86, coreZ), Color = i <= 2 and hot or plasma, Material = Enum.Material.Neon, Transparency = 0.15 + i * 0.11, CanCollide = false, Parent = model })
		if i == 1 then
			addLight(ring, hot, 80, 4)
		end
	end
	-- photon ring: one bright thin circle right at the horizon is what makes the black sphere
	-- read as a hole rather than as a dark ball
	newPart({ Name = "PhotonRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 74, 74), Orientation = Vector3.new(22, 0, 90), Position = Vector3.new(cx, 86, coreZ), Color = Color3.fromRGB(255, 240, 220), Material = Enum.Material.Neon, CanCollide = false, Parent = model })

	-- twin polar jets, the classic silhouette, plus infalling motes so the core looks like it is
	-- eating rather than just sitting there
	for _, dir in ipairs({ 1, -1 }) do
		newPart({ Name = "PolarJet", Shape = Enum.PartType.Cylinder, Size = Vector3.new(86, 11, 11), Orientation = Vector3.new(0, 0, 90 + dir * 22), Position = Vector3.new(cx - dir * 17, 86 + dir * 62, coreZ), Color = Color3.fromRGB(220, 200, 255), Material = Enum.Material.Neon, Transparency = 0.35, CanCollide = false, Parent = model })
	end
	local infall = Instance.new("ParticleEmitter")
	infall.Color = ColorSequence.new(hot, plasma)
	infall.Size = NumberSequence.new(3.4, 0.2)
	infall.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	infall.Lifetime = NumberRange.new(2, 3.4)
	infall.Rate = 40
	infall.Speed = NumberRange.new(-34, -22)
	infall.SpreadAngle = Vector2.new(180, 180)
	infall.LightEmission = 1
	infall.Parent = core

	buildBiomeBase(model, cx, {
		litter = { count = 22, name = "Debris", colors = { shell, Color3.fromRGB(44, 32, 58), Color3.fromRGB(14, 10, 18) }, minSize = 3, maxSize = 12, material = Enum.Material.Slate },
		mounds = { count = 4, name = "CollapsedRidge", color = Color3.fromRGB(30, 24, 40), material = Enum.Material.Slate, minSize = 32, maxSize = 60, flat = 0.2 },
		atmosphere = { color = plasma, color2 = Color3.fromRGB(60, 20, 90), height = 36, rate = 18, sizeStart = 2.4, sizeEnd = 0.4, transparency = 0.4, lifeMin = 4, lifeMax = 8, speedMin = 6, speedMax = 12, lightEmission = 1 },
		glow = { count = 5, color = plasma, height = 16, range = 30, brightness = 2.6 },
	})

	-- MID: debris streams. Long thin shards all aimed at the core turn the empty floor into
	-- something with a direction -- everything here is falling the same way.
	for _ = 1, 26 do
		local x, z = scatterPoint(cx, 200, 250)
		local dx, dz = cx - x, coreZ - z
		local yaw = math.deg(math.atan2(dx, dz))
		newPart({ Name = "DebrisStreak", Size = Vector3.new(2.2, 2.2, math.random(20, 52)), Orientation = Vector3.new(math.random(-8, 8), yaw, math.random(-30, 30)), Position = Vector3.new(x, math.random(6, 46), z), Color = math.random(1, 3) == 1 and hot or plasma, Material = Enum.Material.Neon, Transparency = 0.3, CanCollide = false, Parent = model })
	end

	-- MID: gravity wells punched into the floor, each a dark disc inside a lit rim
	for _ = 1, 8 do
		local x, z = scatterPoint(cx, 195, 245)
		local r = math.random(14, 30)
		newPart({ Name = "GravityWell", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, r * 2, r * 2), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 0.4, z), Color = Color3.fromRGB(6, 4, 10), Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
		local rim = newPart({ Name = "WellRim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.7, r * 2 + 7, r * 2 + 7), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 0.3, z), Color = plasma, Material = Enum.Material.Neon, Transparency = 0.25, CanCollide = false, Parent = model })
		addLight(rim, plasma, 26, 2)
	end

	-- MID: torn structures. Broken man-made frames make the destruction legible -- bare rock
	-- being pulled apart looks the same as bare rock sitting still.
	for _ = 1, 8 do
		local x, z = scatterPoint(cx)
		for i = 1, math.random(3, 5) do
			local h = math.random(14, 38)
			newPart({ Name = "TornGirder", Size = Vector3.new(2.6, h, 2.6), Orientation = Vector3.new(math.random(-38, 38), math.random(0, 360), math.random(-38, 38)), Position = Vector3.new(x + math.random(-12, 12), h / 2 + math.random(0, 8), z + math.random(-12, 12)), Color = Color3.fromRGB(58, 48, 70), Material = Enum.Material.Metal, Parent = model })
		end
	end

	-- MID: lensing arcs. Thin bright bands stretched around the core are the visual shorthand for
	-- bent light, and they fill the mid-air band the jets leave empty.
	for i = 1, 7 do
		local a = (i / 7) * math.pi * 2
		newPart({ Name = "LensArc", Size = Vector3.new(math.random(70, 130), 1.1, 1.1), Orientation = Vector3.new(0, math.deg(a), math.random(-40, 40)), Position = Vector3.new(cx + math.cos(a) * 84, 60 + math.sin(a) * 34, coreZ + 62), Color = Color3.fromRGB(230, 220, 255), Material = Enum.Material.Neon, Transparency = 0.5, CanCollide = false, Parent = model })
	end
end

decorationBuilders.Multiverse = function(model, zone, cx)
	local pink = Color3.fromRGB(255, 100, 220)
	local palette = { Color3.fromRGB(255, 90, 200), Color3.fromRGB(90, 200, 255), Color3.fromRGB(255, 220, 90), Color3.fromRGB(150, 90, 255), Color3.fromRGB(110, 255, 170) }
	-- fragments of the biomes the player already walked through: the one prop that says
	-- "every world at once" better than any amount of abstract neon
	local fragments = {
		{ color = Color3.fromRGB(88, 156, 84), material = Enum.Material.Grass },
		{ color = Color3.fromRGB(230, 200, 120), material = Enum.Material.Sand },
		{ color = Color3.fromRGB(72, 176, 232), material = Enum.Material.Glass },
		{ color = Color3.fromRGB(255, 108, 28), material = Enum.Material.Neon },
		{ color = Color3.fromRGB(178, 178, 184), material = Enum.Material.Slate },
		{ color = Color3.fromRGB(178, 88, 56), material = Enum.Material.Rock },
	}

	buildBiomeBase(model, cx, {
		litter = { count = 20, name = "RealityChip", colors = palette, minSize = 2, maxSize = 7, shape = Enum.PartType.Block, flat = 1, material = Enum.Material.Neon, transparency = 0.25 },
		mounds = { count = 5, name = "VoidMound", color = Color3.fromRGB(30, 28, 44), material = Enum.Material.Slate, minSize = 32, maxSize = 62, flat = 0.22 },
		landmark = { style = "arch", base = Color3.fromRGB(42, 38, 58), accent = pink, material = Enum.Material.Metal },
		atmosphere = { color = pink, color2 = Color3.fromRGB(110, 200, 255), height = 34, rate = 18, sizeStart = 1, sizeEnd = 3.4, transparency = 0.4, lifeMin = 5, lifeMax = 10, speedMin = 2, speedMax = 6, lightEmission = 1 },
		glow = { count = 6, color = pink, height = 16, range = 30 },
	})

	-- SIGNATURE: free-standing doorways, each opening onto a different colour. A framed door is
	-- read as a way through instantly; the old bare rings read as scenery.
	for _ = 1, 12 do
		local x, z = scatterPoint(cx, 195, 245)
		local c = palette[math.random(1, #palette)]
		local h = math.random(22, 34)
		local w = h * 0.62
		local yaw = math.random(0, 360)
		local rot = CFrame.Angles(0, math.rad(yaw), 0)
		local base = CFrame.new(x, 0, z)
		for _, side in ipairs({ -1, 1 }) do
			local leg = newPart({ Name = "DoorJamb", Size = Vector3.new(2.6, h, 3.4), Color = Color3.fromRGB(46, 40, 62), Material = Enum.Material.Metal, Parent = model })
			leg.CFrame = base * rot * CFrame.new(side * w / 2, h / 2, 0)
		end
		local lintel = newPart({ Name = "DoorLintel", Size = Vector3.new(w + 5, 3, 4), Color = c, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		lintel.CFrame = base * rot * CFrame.new(0, h + 1, 0)
		local fill = newPart({ Name = "DoorPortal", Size = Vector3.new(w - 1, h - 2, 0.6), Color = c, Material = Enum.Material.Neon, Transparency = 0.28, CanCollide = false, Parent = model })
		fill.CFrame = base * rot * CFrame.new(0, h / 2, 0)
		addLight(fill, c, 26, 2.2)
	end

	-- MID: floating fragments of other worlds, drifting at head height and above
	for _ = 1, 16 do
		local x, z = scatterPoint(cx, 195, 245)
		local f = fragments[math.random(1, #fragments)]
		local s = math.random(9, 22)
		newPart({ Name = "WorldFragment", Size = Vector3.new(s, s * (0.5 + math.random() * 0.5), s * 0.9), Orientation = Vector3.new(math.random(-25, 25), math.random(0, 360), math.random(-25, 25)), Position = Vector3.new(x, math.random(14, 58), z), Color = f.color, Material = f.material, CanCollide = false, Parent = model })
	end

	-- MID: reality tears. Jagged bright slits in the air, angled every which way, so the space
	-- itself looks damaged rather than merely decorated.
	for _ = 1, 18 do
		local x, z = scatterPoint(cx, 200, 250)
		newPart({ Name = "RealityTear", Size = Vector3.new(0.6, math.random(12, 34), math.random(2, 5)), Orientation = Vector3.new(math.random(-40, 40), math.random(0, 360), math.random(-40, 40)), Position = Vector3.new(x, math.random(8, 52), z), Color = palette[math.random(1, #palette)], Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	end

	-- MID: a checkerboard of mismatched ground tiles under it all -- the floor is stitched
	-- together from several realities too, not one clean slab
	for _ = 1, 22 do
		local x, z = scatterPoint(cx, 200, 250)
		local f = fragments[math.random(1, #fragments)]
		local s = math.random(14, 32)
		newPart({ Name = "StitchedTile", Size = Vector3.new(s, 0.6, s * (0.7 + math.random() * 0.6)), Orientation = Vector3.new(0, math.random(0, 360), 0), Position = Vector3.new(x, 0.4, z), Color = f.color, Material = f.material, CanCollide = false, Parent = model })
	end
end

decorationBuilders.Nebula = function(model, zone, cx)
	local magenta = Color3.fromRGB(224, 120, 236)
	local azure = Color3.fromRGB(120, 180, 255)
	local palette = { magenta, azure, Color3.fromRGB(200, 120, 255), Color3.fromRGB(255, 170, 210) }

	buildBiomeBase(model, cx, {
		litter = { count = 20, name = "Cinder", colors = { Color3.fromRGB(96, 50, 130), Color3.fromRGB(70, 38, 102), Color3.fromRGB(132, 72, 168) }, minSize = 3, maxSize = 11, material = Enum.Material.Foil },
		mounds = { count = 6, name = "DustBank", color = Color3.fromRGB(112, 58, 152), material = Enum.Material.Foil, minSize = 36, maxSize = 68, flat = 0.22 },
		landmark = { style = "crystal", base = Color3.fromRGB(88, 46, 124), accent = magenta, material = Enum.Material.Foil },
		atmosphere = { color = magenta, color2 = azure, height = 44, rate = 26, sizeStart = 6, sizeEnd = 16, transparency = 0.62, lifeMin = 8, lifeMax = 14, speedMin = 1, speedMax = 4, lightEmission = 0.9 },
		glow = { count = 6, color = azure, height = 16, range = 30 },
	})

	-- SIGNATURE: gas pillars. Stacked translucent columns rising past the wall height are the
	-- one silhouette that says "star nursery" -- loose spheres just read as scattered balloons.
	for _ = 1, 5 do
		local x, z = scatterPoint(cx, 175, 230)
		local y = 0
		local w = math.random(30, 46)
		local c = palette[math.random(1, #palette)]
		for i = 1, math.random(5, 8) do
			local h = math.random(16, 26)
			newPart({ Name = "GasPillar", Shape = Enum.PartType.Ball, Size = Vector3.new(w, h, w * 0.9), Orientation = Vector3.new(0, math.random(0, 360), 0), Position = Vector3.new(x + math.random(-5, 5), y + h / 2, z + math.random(-5, 5)), Color = i % 2 == 0 and c or lighten(c, 0.22), Material = Enum.Material.Neon, Transparency = 0.55, CanCollide = false, Parent = model })
			y = y + h * 0.78
			w = w - math.random(2, 5)
			if w < 10 then break end
		end
		local tip = newPart({ Name = "PillarTip", Shape = Enum.PartType.Ball, Size = Vector3.new(9, 9, 9), Position = Vector3.new(x, y + 5, z), Color = Color3.fromRGB(255, 250, 220), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(tip, c, 46, 3)
	end

	-- MID: protostars. Bright cores wrapped in a shell, hanging at mid height -- the thing the
	-- pillars are supposedly making, so the zone reads as a process rather than a mood.
	for _ = 1, 8 do
		local x, z = scatterPoint(cx, 195, 245)
		local y = math.random(28, 72)
		local c = palette[math.random(1, #palette)]
		local star = newPart({ Name = "Protostar", Shape = Enum.PartType.Ball, Size = Vector3.new(12, 12, 12), Position = Vector3.new(x, y, z), Color = Color3.fromRGB(255, 248, 224), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(star, c, 44, 3)
		for i = 1, 2 do
			newPart({ Name = "ProtostarShell", Shape = Enum.PartType.Ball, Size = Vector3.new(20 + i * 12, 20 + i * 12, 20 + i * 12), Position = Vector3.new(x, y, z), Color = c, Material = Enum.Material.Neon, Transparency = 0.68 + i * 0.1, CanCollide = false, Parent = model })
		end
		newPart({ Name = "ProtostarDisc", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, 54, 54), Orientation = Vector3.new(math.random(-24, 24), 0, 90), Position = Vector3.new(x, y, z), Color = lighten(c, 0.3), Material = Enum.Material.Neon, Transparency = 0.55, CanCollide = false, Parent = model })
	end

	-- MID: filaments. Thin lit strands strung between the clouds give the mid-air a structure
	-- that raw fog never has.
	for _ = 1, 20 do
		local x, z = scatterPoint(cx, 200, 250)
		newPart({ Name = "Filament", Size = Vector3.new(math.random(30, 90), 1, 1), Orientation = Vector3.new(math.random(-30, 30), math.random(0, 360), math.random(-30, 30)), Position = Vector3.new(x, math.random(16, 76), z), Color = palette[math.random(1, #palette)], Material = Enum.Material.Neon, Transparency = 0.35, CanCollide = false, Parent = model })
	end

	-- MID: glowing floor vents feeding the clouds above, so the drift has a visible source
	for _ = 1, 9 do
		local x, z = scatterPoint(cx)
		local vent = newPart({ Name = "GasVent", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.4, 14, 14), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 1.2, z), Color = darken(magenta, 0.45), Material = Enum.Material.Foil, CanCollide = false, Parent = model })
		local mouth = newPart({ Name = "GasVentMouth", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 10, 10), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 2.5, z), Color = magenta, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(mouth, magenta, 24, 2)
		local plume = Instance.new("ParticleEmitter")
		plume.Color = ColorSequence.new(magenta, azure)
		plume.Size = NumberSequence.new(4, 14)
		plume.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
		plume.Lifetime = NumberRange.new(5, 9)
		plume.Rate = 10
		plume.Speed = NumberRange.new(5, 10)
		plume.SpreadAngle = Vector2.new(22, 22)
		plume.Acceleration = Vector3.new(0, 4, 0)
		plume.LightEmission = 0.8
		plume.Parent = mouth
	end
end

decorationBuilders.Wormhole = function(model, zone, cx)
	local violet = Color3.fromRGB(150, 100, 245)
	local pale = Color3.fromRGB(215, 200, 255)

	buildBiomeBase(model, cx, {
		litter = { count = 18, name = "Fragment", colors = { Color3.fromRGB(44, 44, 72), Color3.fromRGB(62, 58, 96), Color3.fromRGB(30, 30, 52) }, minSize = 3, maxSize = 10, material = Enum.Material.Slate },
		mounds = { count = 4, name = "WarpSwell", color = Color3.fromRGB(40, 38, 66), material = Enum.Material.Slate, minSize = 34, maxSize = 62, flat = 0.2 },
		-- no landmark: the throat below already owns the back of the platform, and addLandmark
		-- would place its plinth at z = -210, straight through the far end of the tunnel
		atmosphere = { color = violet, color2 = pale, height = 34, rate = 18, sizeStart = 1, sizeEnd = 3, transparency = 0.42, lifeMin = 4, lifeMax = 8, speedMin = 8, speedMax = 16, lightEmission = 1 },
		glow = { count = 6, color = violet, height = 15, range = 28 },
	})

	-- SIGNATURE: the throat. A receding corridor of rings that shrink and tilt as they go back is
	-- what turns five concentric circles in one spot into an actual tunnel you can look down.
	local tunnelZ = -60
	for i = 1, 16 do
		local d = 84 - i * 3.4
		local zPos = tunnelZ - i * 9
		local ring = newPart({
			Name = "ThroatRing",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2.2, d, d),
			Orientation = Vector3.new(0, 0, 90),
			Position = Vector3.new(cx + math.sin(i * 0.42) * 9, 40 + math.sin(i * 0.3) * 5, zPos),
			Color = i % 3 == 0 and pale or violet,
			Material = Enum.Material.Neon,
			Transparency = 0.18 + i * 0.03,
			CanCollide = false,
			Parent = model,
		})
		if i % 4 == 1 then
			addLight(ring, violet, 40, 2.6)
		end
	end
	local mouth = newPart({ Name = "ThroatMouth", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 34, 34), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(cx + math.sin(17 * 0.42) * 9, 40, tunnelZ - 17 * 9), Color = Color3.fromRGB(255, 255, 255), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	addLight(mouth, pale, 60, 4)

	-- MID: light streaks pulled along the tunnel axis. Everything points the same way, which is
	-- what makes the zone feel like it is moving even though nothing is animated.
	for _ = 1, 30 do
		local x, z = scatterPoint(cx, 200, 250)
		newPart({ Name = "WarpStreak", Size = Vector3.new(1.2, 1.2, math.random(26, 70)), Orientation = Vector3.new(math.random(-6, 6), math.random(-12, 12), math.random(0, 360)), Position = Vector3.new(x, math.random(6, 62), z), Color = math.random(1, 3) == 1 and pale or violet, Material = Enum.Material.Neon, Transparency = 0.3, CanCollide = false, Parent = model })
	end

	-- MID: stabiliser gantries flanking the throat, so the tunnel looks built and maintained
	for _, side in ipairs({ -1, 1 }) do
		for i = 1, 5 do
			local gx = cx + side * (58 + i * 5)
			local gz = tunnelZ - i * 26
			newPart({ Name = "GantryLeg", Size = Vector3.new(4.5, 54, 4.5), Position = Vector3.new(gx, 27, gz), Color = Color3.fromRGB(52, 50, 78), Material = Enum.Material.Metal, Parent = model })
			newPart({ Name = "GantryArm", Size = Vector3.new(22, 3, 3), Orientation = Vector3.new(0, 0, side * -14), Position = Vector3.new(gx - side * 11, 52, gz), Color = Color3.fromRGB(52, 50, 78), Material = Enum.Material.Metal, CanCollide = false, Parent = model })
			local emitter = newPart({ Name = "GantryEmitter", Shape = Enum.PartType.Ball, Size = Vector3.new(6, 6, 6), Position = Vector3.new(gx - side * 21, 51, gz), Color = violet, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
			addLight(emitter, violet, 26, 2)
		end
	end

	-- MID: debris caught in the pull, tumbling at every angle just off the tunnel line
	for _ = 1, 20 do
		local x, z = scatterPoint(cx, 195, 245)
		local s = math.random(5, 15)
		newPart({ Name = "CaughtDebris", Size = Vector3.new(s, s * 0.7, s * 1.3), Orientation = Vector3.new(math.random(0, 360), math.random(0, 360), math.random(0, 360)), Position = Vector3.new(x, math.random(10, 56), z), Color = Color3.fromRGB(58, 54, 88), Material = Enum.Material.Slate, CanCollide = false, Parent = model })
	end

	-- MID: floor conduits running toward the throat, so the ground carries the same direction
	for _ = 1, 14 do
		local x, z = scatterPoint(cx, 200, 250)
		newPart({ Name = "Conduit", Size = Vector3.new(2.6, 0.5, math.random(30, 76)), Orientation = Vector3.new(0, math.random(-16, 16), 0), Position = Vector3.new(x, 0.35, z), Color = violet, Material = Enum.Material.Neon, Transparency = 0.25, CanCollide = false, Parent = model })
	end
end

decorationBuilders.QuantumRealm = function(model, zone, cx)
	local teal = Color3.fromRGB(80, 220, 220)
	local deep = Color3.fromRGB(28, 84, 100)

	buildBiomeBase(model, cx, {
		litter = { count = 22, name = "Quanta", colors = { teal, Color3.fromRGB(150, 255, 245), Color3.fromRGB(60, 170, 190) }, minSize = 2, maxSize = 6, shape = Enum.PartType.Block, flat = 1, material = Enum.Material.Neon, transparency = 0.35 },
		mounds = { count = 5, name = "FieldSwell", color = Color3.fromRGB(38, 104, 122), material = Enum.Material.Glass, minSize = 34, maxSize = 64, flat = 0.2, transparency = 0.35 },
		landmark = { style = "crystal", base = deep, accent = teal, material = Enum.Material.Glass },
		atmosphere = { color = teal, color2 = Color3.fromRGB(190, 255, 250), height = 30, rate = 24, sizeStart = 0.4, sizeEnd = 1.4, transparency = 0.35, lifeMin = 3, lifeMax = 6, speedMin = 6, speedMax = 14, lightEmission = 1 },
		glow = { count = 6, color = teal, height = 14, range = 28 },
	})

	-- SIGNATURE: superposition. Every prop is built twice -- solid, plus a translucent twin
	-- offset a few studs. Two copies of the same object is the only way to draw "it is in both
	-- places" without animation, and it is what makes this zone unmistakable.
	for _ = 1, 16 do
		local x, z = scatterPoint(cx, 195, 245)
		local s = math.random(6, 15)
		local y = math.random(6, 44)
		local orient = Vector3.new(math.random(0, 360), math.random(0, 360), math.random(0, 360))
		newPart({ Name = "QuantumCube", Size = Vector3.new(s, s, s), Orientation = orient, Position = Vector3.new(x, y, z), Color = teal, Material = Enum.Material.Neon, Transparency = 0.15, CanCollide = false, Parent = model })
		newPart({ Name = "QuantumGhost", Size = Vector3.new(s, s, s), Orientation = orient, Position = Vector3.new(x + math.random(-9, 9), y + math.random(-5, 5), z + math.random(-9, 9)), Color = lighten(teal, 0.4), Material = Enum.Material.Neon, Transparency = 0.72, CanCollide = false, Parent = model })
	end

	-- MID: probability platforms. Thin glass slabs at stepped heights, each ringed in neon --
	-- the built element that keeps the zone from being pure floating geometry.
	for _ = 1, 10 do
		local x, z = scatterPoint(cx, 190, 240)
		local y = math.random(8, 40)
		local w = math.random(16, 30)
		newPart({ Name = "PhasePlatform", Size = Vector3.new(w, 1.4, w * 0.85), Orientation = Vector3.new(0, math.random(0, 360), 0), Position = Vector3.new(x, y, z), Color = deep, Material = Enum.Material.Glass, Transparency = 0.4, CanCollide = false, Parent = model })
		newPart({ Name = "PlatformRim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, w + 5, w + 5), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, y - 0.9, z), Color = teal, Material = Enum.Material.Neon, Transparency = 0.3, CanCollide = false, Parent = model })
	end

	-- MID: wave rails. Long low arcs of light skimming the floor read as particles taking every
	-- path at once, and they stop the ground going flat and empty between the platforms.
	for _ = 1, 16 do
		local x, z = scatterPoint(cx, 200, 250)
		local yaw = math.random(0, 360)
		for i = -3, 3 do
			newPart({ Name = "WaveRail", Size = Vector3.new(11, 0.8, 0.8), Orientation = Vector3.new(0, yaw, 0), Position = Vector3.new(x + math.cos(math.rad(yaw)) * i * 10, 1.4 + math.abs(math.sin(i * 0.9)) * 5, z - math.sin(math.rad(yaw)) * i * 10), Color = teal, Material = Enum.Material.Neon, Transparency = 0.2, CanCollide = false, Parent = model })
		end
	end

	-- MID: containment lattices at eye level -- open glass frames with a lit particle suspended
	-- inside, so the mid-field has something built rather than only scattered light
	for _ = 1, 7 do
		local x, z = scatterPoint(cx)
		local h = math.random(16, 28)
		for _, side in ipairs({ -1, 1 }) do
			newPart({ Name = "LatticePost", Size = Vector3.new(1.8, h, 1.8), Position = Vector3.new(x + side * 8, h / 2, z), Color = deep, Material = Enum.Material.Metal, Parent = model })
			newPart({ Name = "LatticePost", Size = Vector3.new(1.8, h, 1.8), Position = Vector3.new(x, h / 2, z + side * 8), Color = deep, Material = Enum.Material.Metal, Parent = model })
		end
		newPart({ Name = "LatticeCap", Size = Vector3.new(19, 1.4, 19), Position = Vector3.new(x, h, z), Color = deep, Material = Enum.Material.Metal, CanCollide = false, Parent = model })
		local held = newPart({ Name = "HeldParticle", Shape = Enum.PartType.Ball, Size = Vector3.new(7, 7, 7), Position = Vector3.new(x, h * 0.6, z), Color = Color3.fromRGB(200, 255, 250), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(held, teal, 26, 2.4)
	end
end

decorationBuilders.TimeRift = function(model, zone, cx)
	local gold = Color3.fromRGB(238, 196, 92)
	local brass = Color3.fromRGB(126, 96, 48)
	local frozen = Color3.fromRGB(190, 214, 236)

	buildBiomeBase(model, cx, {
		litter = { count = 20, name = "Cog", colors = { brass, gold, Color3.fromRGB(96, 74, 40) }, minSize = 3, maxSize = 10, shape = Enum.PartType.Cylinder, flat = 0.3, material = Enum.Material.Metal },
		mounds = { count = 5, name = "SandDrift", color = Color3.fromRGB(176, 148, 96), material = Enum.Material.Sand, minSize = 34, maxSize = 66, flat = 0.22 },
		landmark = { style = "tower", base = brass, accent = gold, material = Enum.Material.Metal },
		atmosphere = { color = gold, color2 = Color3.fromRGB(255, 240, 200), height = 32, rate = 16, sizeStart = 0.6, sizeEnd = 2, transparency = 0.45, lifeMin = 6, lifeMax = 11, speedMin = 2, speedMax = 5, lightEmission = 0.8, acceleration = Vector3.new(0, -3, 0) },
		glow = { count = 5, color = gold, height = 15, range = 28 },
	})

	-- SIGNATURE: clock faces standing in the ground at every angle, each with hands frozen at a
	-- different hour. A ring alone is just a ring; hands are what make it read as time.
	for _ = 1, 12 do
		local x, z = scatterPoint(cx, 195, 245)
		local d = math.random(16, 34)
		local yaw = math.random(0, 360)
		local tilt = math.random(-22, 22)
		local base = CFrame.new(x, d * 0.55, z) * CFrame.Angles(0, math.rad(yaw), math.rad(tilt))

		local face = newPart({ Name = "ClockFace", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, d, d), Color = Color3.fromRGB(238, 230, 208), Material = Enum.Material.Marble, CanCollide = false, Parent = model })
		face.CFrame = base * CFrame.Angles(0, math.rad(90), 0)
		local rim = newPart({ Name = "ClockRim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.2, d + 4, d + 4), Color = brass, Material = Enum.Material.Metal, CanCollide = false, Parent = model })
		rim.CFrame = base * CFrame.Angles(0, math.rad(90), 0)
		for _, hand in ipairs({ { d * 0.4, 1.4, math.random(0, 360) }, { d * 0.28, 2, math.random(0, 360) } }) do
			local h = newPart({ Name = "ClockHand", Size = Vector3.new(hand[1], hand[2], 0.7), Color = Color3.fromRGB(48, 38, 26), Material = Enum.Material.Metal, CanCollide = false, Parent = model })
			h.CFrame = base * CFrame.new(0, 0, 1.2) * CFrame.Angles(0, 0, math.rad(hand[3])) * CFrame.new(hand[1] / 2, 0, 0)
		end
		local pip = newPart({ Name = "ClockPip", Shape = Enum.PartType.Ball, Size = Vector3.new(2.6, 2.6, 2.6), Color = gold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		pip.CFrame = base * CFrame.new(0, 0, 1.6)
		addLight(pip, gold, 18, 1.4)
	end

	-- MID: hourglasses. Two cones and a lit stream, standing taller than a player, so the zone
	-- has a repeating silhouette at eye level instead of only floor clutter.
	for _ = 1, 7 do
		local x, z = scatterPoint(cx)
		for _, side in ipairs({ -1, 1 }) do
			newPart({ Name = "GlassCap", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 15, 15), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 12 + side * 11, z), Color = brass, Material = Enum.Material.Metal, CanCollide = false, Parent = model })
			newPart({ Name = "GlassBulb", Shape = Enum.PartType.Ball, Size = Vector3.new(13, 11, 13), Position = Vector3.new(x, 12 + side * 5.5, z), Color = frozen, Material = Enum.Material.Glass, Transparency = 0.55, CanCollide = false, Parent = model })
		end
		local stream = newPart({ Name = "SandStream", Size = Vector3.new(1.6, 9, 1.6), Position = Vector3.new(x, 12, z), Color = gold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(stream, gold, 20, 1.8)
		for _, side in ipairs({ -1, 1 }) do
			newPart({ Name = "GlassPost", Size = Vector3.new(1.4, 24, 1.4), Position = Vector3.new(x + side * 7, 12, z), Color = brass, Material = Enum.Material.Metal, CanCollide = false, Parent = model })
		end
	end

	-- MID: debris frozen mid-fall. Objects hanging in the air with no support is the cheapest,
	-- clearest way to draw stopped time, and it fills the band above head height.
	for _ = 1, 24 do
		local x, z = scatterPoint(cx, 200, 250)
		local s = math.random(3, 11)
		newPart({ Name = "FrozenDebris", Size = Vector3.new(s, s * 0.8, s * 1.2), Orientation = Vector3.new(math.random(0, 360), math.random(0, 360), math.random(0, 360)), Position = Vector3.new(x, math.random(8, 50), z), Color = math.random(1, 3) == 1 and gold or Color3.fromRGB(104, 84, 54), Material = Enum.Material.Metal, CanCollide = false, Parent = model })
	end

	-- MID: rift seams in the floor -- thin bright cracks where the two eras meet
	for _ = 1, 16 do
		local x, z = scatterPoint(cx, 200, 250)
		newPart({ Name = "RiftSeam", Size = Vector3.new(math.random(20, 56), 0.6, math.random(2, 4)), Orientation = Vector3.new(0, math.random(0, 360), 0), Position = Vector3.new(x, 0.4, z), Color = frozen, Material = Enum.Material.Neon, Transparency = 0.25, CanCollide = false, Parent = model })
	end

	-- MID: gear pillars, half-sunk into the ground, giving the mid-field a mechanical read
	for _ = 1, 9 do
		local x, z = scatterPoint(cx)
		local y = 0
		for i = 1, math.random(2, 4) do
			local d = math.random(14, 26)
			newPart({ Name = "GearDisc", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.4, d, d), Orientation = Vector3.new(0, math.random(0, 360), 90), Position = Vector3.new(x, y + 1.7, z), Color = i % 2 == 0 and brass or Color3.fromRGB(150, 118, 62), Material = Enum.Material.Metal, Parent = model })
			y = y + 3.2
		end
	end
end

decorationBuilders.AntimatterZone = function(model, zone, cx)
	local danger = Color3.fromRGB(255, 62, 62)
	local hot = Color3.fromRGB(255, 176, 120)
	local hull = Color3.fromRGB(58, 42, 42)

	buildBiomeBase(model, cx, {
		litter = { count = 22, name = "SlagChunk", colors = { hull, Color3.fromRGB(34, 22, 22), Color3.fromRGB(84, 52, 46) }, minSize = 3, maxSize = 12, material = Enum.Material.Slate },
		mounds = { count = 5, name = "BlastBerm", color = Color3.fromRGB(72, 40, 38), material = Enum.Material.Slate, minSize = 34, maxSize = 64, flat = 0.22 },
		landmark = { style = "spire", base = hull, accent = danger, material = Enum.Material.Metal },
		atmosphere = { color = danger, color2 = Color3.fromRGB(120, 20, 20), height = 32, rate = 20, sizeStart = 1.4, sizeEnd = 0.3, transparency = 0.35, lifeMin = 3, lifeMax = 6, speedMin = 8, speedMax = 16, lightEmission = 1 },
		glow = { count = 6, color = danger, height = 15, range = 30, brightness = 2.8 },
	})

	-- SIGNATURE: magnetic containment cells. Antimatter cannot touch anything, so the read has to
	-- be "suspended and held" -- a caged core between two emitter plates, never a pool on the
	-- floor. The old 150x150 red slab said the opposite of what this zone is.
	for _ = 1, 8 do
		local x, z = scatterPoint(cx, 190, 240)
		newPart({ Name = "CellBase", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 26, 26), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 2, z), Color = hull, Material = Enum.Material.Metal, Parent = model })
		for _, side in ipairs({ -1, 1 }) do
			newPart({ Name = "CellColumn", Size = Vector3.new(3, 30, 3), Position = Vector3.new(x + side * 10, 19, z), Color = darken(hull, 0.2), Material = Enum.Material.Metal, Parent = model })
		end
		newPart({ Name = "CellCap", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.4, 24, 24), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 35, z), Color = hull, Material = Enum.Material.Metal, CanCollide = false, Parent = model })
		local caged = newPart({ Name = "CagedCore", Shape = Enum.PartType.Ball, Size = Vector3.new(11, 11, 11), Position = Vector3.new(x, 19, z), Color = Color3.fromRGB(255, 240, 230), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(caged, danger, 40, 3.4)
		for i = 1, 3 do
			newPart({ Name = "ContainmentRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, 15 + i * 4, 15 + i * 4), Orientation = Vector3.new(i * 30, 0, 90), Position = Vector3.new(x, 19, z), Color = danger, Material = Enum.Material.Neon, Transparency = 0.35 + i * 0.12, CanCollide = false, Parent = model })
		end
		local arc = Instance.new("ParticleEmitter")
		arc.Color = ColorSequence.new(hot, danger)
		arc.Size = NumberSequence.new(1.6, 0.2)
		arc.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		arc.Lifetime = NumberRange.new(0.5, 1.1)
		arc.Rate = 26
		arc.Speed = NumberRange.new(10, 18)
		arc.SpreadAngle = Vector2.new(180, 180)
		arc.LightEmission = 1
		arc.Parent = caged
	end

	-- MID: hazard pylons with striped bands -- signage is what turns scattered machinery into a
	-- facility, and the yellow/black break is the only warm break in an all-red palette
	for _ = 1, 12 do
		local x, z = scatterPoint(cx)
		local h = math.random(14, 24)
		newPart({ Name = "HazardPylon", Size = Vector3.new(3.2, h, 3.2), Position = Vector3.new(x, h / 2, z), Color = Color3.fromRGB(40, 34, 32), Material = Enum.Material.Metal, Parent = model })
		for i = 1, 3 do
			newPart({ Name = "HazardBand", Size = Vector3.new(4, 2.2, 4), Position = Vector3.new(x, h * 0.25 * i, z), Color = Color3.fromRGB(248, 208, 40), Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
		end
		local top = newPart({ Name = "HazardLamp", Shape = Enum.PartType.Ball, Size = Vector3.new(4.4, 4.4, 4.4), Position = Vector3.new(x, h + 2, z), Color = danger, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(top, danger, 22, 2)
	end

	-- MID: annihilation craters. Where containment already failed: a scorched bowl, a glass-slag
	-- floor and a thrown-up rim, so the zone carries evidence rather than only warnings.
	for _ = 1, 7 do
		local x, z = scatterPoint(cx, 195, 245)
		local r = math.random(16, 34)
		newPart({ Name = "ScorchFloor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, r * 2, r * 2), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 0.4, z), Color = Color3.fromRGB(18, 10, 10), Material = Enum.Material.Slate, CanCollide = false, Parent = model })
		local slag = newPart({ Name = "SlagPool", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, r * 1.2, r * 1.2), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 0.7, z), Color = danger, Material = Enum.Material.Neon, Transparency = 0.2, CanCollide = false, Parent = model })
		addLight(slag, danger, 28, 2.4)
		local rimCount = 9 + math.floor(r / 5)
		for i = 1, rimCount do
			local a = (i / rimCount) * math.pi * 2
			local s = math.random(5, 10)
			newPart({ Name = "CraterSlag", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 0.6, s), Orientation = Vector3.new(0, math.random(0, 360), 0), Position = Vector3.new(x + math.cos(a) * r, s * 0.25, z + math.sin(a) * r), Color = hull, Material = Enum.Material.Slate, CanCollide = false, Parent = model })
		end
	end

	-- MID: buckled pipework running between the cells, so the machinery looks connected
	for _ = 1, 14 do
		local x, z = scatterPoint(cx, 200, 250)
		local yaw = math.random(0, 360)
		newPart({ Name = "Pipe", Shape = Enum.PartType.Cylinder, Size = Vector3.new(math.random(24, 60), 4, 4), Orientation = Vector3.new(0, yaw, 90), Position = Vector3.new(x, 3, z), Color = Color3.fromRGB(74, 58, 56), Material = Enum.Material.Metal, Parent = model })
		newPart({ Name = "PipeGlow", Size = Vector3.new(1.2, 0.5, 1.2), Position = Vector3.new(x, 5.2, z), Color = danger, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	end
end

decorationBuilders.DreamDimension = function(model, zone, cx)
	local lilac = Color3.fromRGB(206, 152, 255)
	local blush = Color3.fromRGB(255, 198, 232)
	local mint = Color3.fromRGB(198, 255, 226)
	local palette = { lilac, blush, mint, Color3.fromRGB(190, 214, 255) }

	buildBiomeBase(model, cx, {
		litter = { count = 18, name = "Pebble", colors = { Color3.fromRGB(150, 112, 190), Color3.fromRGB(186, 148, 220), Color3.fromRGB(122, 88, 160) }, minSize = 3, maxSize = 9, material = Enum.Material.Foil },
		mounds = { count = 8, name = "CloudBank", color = Color3.fromRGB(232, 216, 255), material = Enum.Material.Foil, minSize = 40, maxSize = 76, flat = 0.26, transparency = 0.2 },
		landmark = { style = "greattree", base = blush, accent = Color3.fromRGB(255, 246, 200), trunkColor = Color3.fromRGB(128, 96, 158), material = Enum.Material.Foil },
		atmosphere = { color = blush, color2 = mint, height = 38, rate = 14, sizeStart = 2.4, sizeEnd = 6, transparency = 0.55, lifeMin = 9, lifeMax = 15, speedMin = 0.5, speedMax = 2.5, lightEmission = 0.8 },
		glow = { count = 7, color = lilac, height = 17, range = 30 },
	})

	-- SIGNATURE: staircases that stop in mid-air. Nothing sells "dream" faster than architecture
	-- that clearly cannot work, and stairs are the version of it a player reads instantly.
	for _ = 1, 7 do
		local x, z = scatterPoint(cx, 185, 235)
		local yaw = math.random(0, 360)
		local dir = CFrame.Angles(0, math.rad(yaw), 0)
		local y = 2
		local steps = math.random(8, 16)
		for i = 1, steps do
			-- collidable on purpose: a staircase you fall straight through is worse than one that
			-- goes nowhere, and 16 steps at 3.4 tops out at ~56, far below the 140-stud walls
			local step = newPart({ Name = "DreamStair", Size = Vector3.new(13, 1.4, 6), Color = i % 2 == 0 and blush or Color3.fromRGB(244, 232, 255), Material = Enum.Material.Foil, Parent = model })
			step.CFrame = CFrame.new(x, y, z) * dir * CFrame.new(0, 0, -i * 6)
			y = y + 3.4
		end
		local capstone = newPart({ Name = "StairEndOrb", Shape = Enum.PartType.Ball, Size = Vector3.new(9, 9, 9), Color = Color3.fromRGB(255, 250, 220), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		capstone.CFrame = CFrame.new(x, y + 4, z) * dir * CFrame.new(0, 0, -(steps + 1) * 6)
		addLight(capstone, lilac, 32, 2.4)
	end

	-- MID: soap bubbles at every scale, drifting from ankle height to overhead. Translucent
	-- spheres are the whole palette of this biome; the trick is the spread of sizes, not the count.
	for _ = 1, 26 do
		local x, z = scatterPoint(cx, 200, 250)
		local s = math.random(6, 30)
		local c = palette[math.random(1, #palette)]
		newPart({ Name = "DreamBubble", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s, s), Position = Vector3.new(x, math.random(6, 70), z), Color = c, Material = Enum.Material.Neon, Transparency = 0.68, CanCollide = false, Parent = model })
	end

	-- MID: floating doors standing on nothing. One familiar object out of place does more than
	-- twenty abstract shapes -- it gives the surreal something to be surreal against.
	for _ = 1, 8 do
		local x, z = scatterPoint(cx, 190, 240)
		local y = math.random(6, 40)
		local yaw = math.random(0, 360)
		local rot = CFrame.Angles(0, math.rad(yaw), math.rad(math.random(-14, 14)))
		local frame = newPart({ Name = "DreamDoorFrame", Size = Vector3.new(15, 24, 2.4), Color = Color3.fromRGB(150, 112, 190), Material = Enum.Material.Foil, CanCollide = false, Parent = model })
		frame.CFrame = CFrame.new(x, y, z) * rot
		local leaf = newPart({ Name = "DreamDoor", Size = Vector3.new(11.5, 20, 1), Color = palette[math.random(1, #palette)], Material = Enum.Material.Neon, Transparency = 0.3, CanCollide = false, Parent = model })
		leaf.CFrame = CFrame.new(x, y, z) * rot * CFrame.new(0, 0, 1.4)
		addLight(leaf, lilac, 22, 1.8)
	end

	-- MID: oversized moons low over the platform. Two of them, because one reads as a planet and
	-- two read as a place where the sky does not have to make sense.
	for i, spec in ipairs({ { -132, -206, 62, blush }, { 118, -188, 46, mint } }) do
		local moon = newPart({ Name = "DreamMoon", Shape = Enum.PartType.Ball, Size = Vector3.new(spec[3], spec[3], spec[3]), Position = Vector3.new(cx + spec[1], 70 + i * 12, spec[2]), Color = spec[4], Material = Enum.Material.Neon, Transparency = 0.15, CanCollide = false, Parent = model })
		addLight(moon, spec[4], 70, 2.6)
	end

	-- MID: pastel toadstools at ground level, so the walkable band is not just cloud and air
	for _ = 1, 16 do
		local x, z = scatterPoint(cx)
		local h = math.random(6, 16)
		local c = palette[math.random(1, #palette)]
		newPart({ Name = "DreamStem", Size = Vector3.new(2.6, h, 2.6), Position = Vector3.new(x, h / 2, z), Color = Color3.fromRGB(248, 240, 255), Material = Enum.Material.Foil, CanCollide = false, Parent = model })
		local cap = newPart({ Name = "DreamCap", Shape = Enum.PartType.Ball, Size = Vector3.new(h * 1.1, h * 0.62, h * 1.1), Position = Vector3.new(x, h + h * 0.2, z), Color = c, Material = Enum.Material.Neon, Transparency = 0.15, CanCollide = false, Parent = model })
		if math.random(1, 3) == 1 then
			addLight(cap, c, 18, 1.4)
		end
	end
end

decorationBuilders.MirrorUniverse = function(model, zone, cx)
	local silver = Color3.fromRGB(216, 220, 238)
	local frame = Color3.fromRGB(92, 96, 118)
	local cold = Color3.fromRGB(180, 200, 255)

	buildBiomeBase(model, cx, {
		litter = { count = 24, name = "GlassShard", colors = { silver, Color3.fromRGB(168, 176, 200), cold }, minSize = 2, maxSize = 8, shape = Enum.PartType.Block, flat = 0.9, material = Enum.Material.Glass, transparency = 0.15 },
		mounds = { count = 5, name = "PolishedSwell", color = Color3.fromRGB(168, 172, 194), material = Enum.Material.Foil, minSize = 34, maxSize = 64, flat = 0.2 },
		landmark = { style = "crystal", base = frame, accent = cold, material = Enum.Material.Glass },
		atmosphere = { color = silver, color2 = cold, height = 30, rate = 12, sizeStart = 0.6, sizeEnd = 2, transparency = 0.6, lifeMin = 6, lifeMax = 11, speedMin = 1, speedMax = 4, lightEmission = 0.6 },
		glow = { count = 6, color = cold, height = 15, range = 28 },
	})

	-- SIGNATURE: standing mirrors. Full-height framed panes at high Reflectance actually reflect
	-- the player and the rest of the zone at runtime, which no amount of painted "shiny" can fake.
	for _ = 1, 14 do
		local x, z = scatterPoint(cx, 190, 240)
		local h = math.random(24, 46)
		local w = h * 0.52
		local yaw = math.random(0, 360)
		local rot = CFrame.Angles(0, math.rad(yaw), math.rad(math.random(-5, 5)))
		local base = CFrame.new(x, h / 2, z)

		local border = newPart({ Name = "MirrorFrame", Size = Vector3.new(w + 4, h + 4, 2.4), Color = frame, Material = Enum.Material.Metal, Parent = model })
		border.CFrame = base * rot
		local pane = newPart({ Name = "MirrorPane", Size = Vector3.new(w, h, 1), Color = silver, Material = Enum.Material.Glass, Reflectance = 0.95, CanCollide = false, Parent = model })
		pane.CFrame = base * rot * CFrame.new(0, 0, 1.1)
		local backPane = newPart({ Name = "MirrorPane", Size = Vector3.new(w, h, 1), Color = silver, Material = Enum.Material.Glass, Reflectance = 0.95, CanCollide = false, Parent = model })
		backPane.CFrame = base * rot * CFrame.new(0, 0, -1.1)
		local crest = newPart({ Name = "MirrorCrest", Shape = Enum.PartType.Ball, Size = Vector3.new(5.5, 5.5, 5.5), Color = cold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		crest.CFrame = base * rot * CFrame.new(0, h / 2 + 3, 0)
		addLight(crest, cold, 24, 1.8)
	end

	-- SIGNATURE: the inverted world overhead. A single reflective ceiling plane high above turns
	-- the whole platform into its own reflection -- the cheapest possible "mirror universe".
	newPart({ Name = "MirrorCeiling", Size = Vector3.new(PLATFORM_WIDTH - 30, 2, PLATFORM_DEPTH - 30), Position = Vector3.new(cx, 118, 0), Color = Color3.fromRGB(196, 204, 228), Material = Enum.Material.Glass, Reflectance = 0.85, Transparency = 0.25, CanCollide = false, Parent = model })

	-- MID: shattered panes leaning on the floor, catching light at broken angles
	for _ = 1, 20 do
		local x, z = scatterPoint(cx, 200, 250)
		local h = math.random(8, 22)
		newPart({ Name = "BrokenPane", Size = Vector3.new(math.random(5, 13), h, 0.8), Orientation = Vector3.new(math.random(-40, 40), math.random(0, 360), math.random(-30, 30)), Position = Vector3.new(x, h / 2, z), Color = silver, Material = Enum.Material.Glass, Reflectance = 0.8, Transparency = 0.1, CanCollide = false, Parent = model })
	end

	-- MID: mirrored twins. Every pillar is built with an upside-down copy hanging beneath the
	-- floor line, so even the props obey the reflection rather than only the surfaces.
	for _ = 1, 10 do
		local x, z = scatterPoint(cx)
		local h = math.random(16, 34)
		local w = math.random(5, 9)
		local yaw = math.random(0, 360)
		newPart({ Name = "TwinPillar", Size = Vector3.new(w, h, w), Orientation = Vector3.new(0, yaw, 0), Position = Vector3.new(x, h / 2, z), Color = frame, Material = Enum.Material.Metal, Parent = model })
		newPart({ Name = "TwinPillarInverted", Size = Vector3.new(w, h, w), Orientation = Vector3.new(0, yaw, 0), Position = Vector3.new(x, 118 - h / 2, z), Color = frame, Material = Enum.Material.Metal, Transparency = 0.35, CanCollide = false, Parent = model })
		local cap = newPart({ Name = "TwinCap", Shape = Enum.PartType.Ball, Size = Vector3.new(w + 2, w + 2, w + 2), Position = Vector3.new(x, h + 1, z), Color = cold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(cap, cold, 22, 1.6)
	end

	-- MID: a still reflecting pool at floor level, so looking down works as well as looking up.
	-- Parked off to the left and forward of the plaza: it has to clear both the egg-shop footprint
	-- (x within cx +/- 58) and the arrival clearing at z ~ 174.
	newPart({ Name = "ReflectingPool", Size = Vector3.new(130, 0.8, 70), Position = Vector3.new(cx - 120, 0.6, 96), Color = Color3.fromRGB(206, 214, 240), Material = Enum.Material.Glass, Reflectance = 0.9, Transparency = 0.15, CanCollide = false, Parent = model })
	for _, side in ipairs({ -1, 1 }) do
		newPart({ Name = "PoolKerb", Size = Vector3.new(136, 1.6, 4), Position = Vector3.new(cx - 120, 0.8, 96 + side * 37), Color = frame, Material = Enum.Material.Metal, Parent = model })
	end
end

decorationBuilders.VoidExpanse = function(model, zone, cx)
	local violet = Color3.fromRGB(148, 62, 228)
	local ash = Color3.fromRGB(24, 20, 34)

	buildBiomeBase(model, cx, {
		litter = { count = 16, name = "VoidGrit", colors = { ash, Color3.fromRGB(12, 10, 18), Color3.fromRGB(44, 34, 60) }, minSize = 3, maxSize = 10, material = Enum.Material.Slate },
		mounds = { count = 4, name = "AshSwell", color = Color3.fromRGB(18, 15, 26), material = Enum.Material.Slate, minSize = 34, maxSize = 66, flat = 0.2 },
		landmark = { style = "orb", base = ash, accent = violet, coreColor = Color3.fromRGB(10, 6, 16), orbTransparency = 0.1, material = Enum.Material.Slate },
		atmosphere = { color = violet, color2 = Color3.fromRGB(40, 14, 64), height = 40, rate = 8, sizeStart = 5, sizeEnd = 14, transparency = 0.7, lifeMin = 10, lifeMax = 16, speedMin = 0.5, speedMax = 2, lightEmission = 0.5 },
		glow = { count = 5, color = violet, height = 18, range = 32, brightness = 1.6 },
	})

	-- SIGNATURE: holes with nothing under them. A pure-black disc inside a torn, lit rim reads as
	-- absence; a dark grey disc just reads as a stain, which is why the rim has to glow.
	for _ = 1, 11 do
		local x, z = scatterPoint(cx, 195, 245)
		local r = math.random(14, 36)
		newPart({ Name = "VoidHole", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, r * 2, r * 2), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 0.5, z), Color = Color3.fromRGB(0, 0, 0), Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
		local rimCount = 12 + math.floor(r / 4)
		for i = 1, rimCount do
			local a = (i / rimCount) * math.pi * 2
			local h = math.random(3, 9)
			newPart({ Name = "TornEdge", Size = Vector3.new(3.2, h, 3.2), Orientation = Vector3.new(math.random(-24, 24), math.deg(a), math.random(-24, 24)), Position = Vector3.new(x + math.cos(a) * r, h * 0.4, z + math.sin(a) * r), Color = ash, Material = Enum.Material.Slate, CanCollide = false, Parent = model })
		end
		local glowRim = newPart({ Name = "HoleRim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, r * 2 + 5, r * 2 + 5), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 0.3, z), Color = violet, Material = Enum.Material.Neon, Transparency = 0.35, CanCollide = false, Parent = model })
		addLight(glowRim, violet, 30, 2)
	end

	-- MID: the remains of somewhere else. Broken slabs of grass, sand and stone drifting overhead
	-- are the only way to show what the void ate -- an empty zone with nothing in it is just empty.
	local remains = {
		{ color = Color3.fromRGB(66, 112, 62), material = Enum.Material.Grass },
		{ color = Color3.fromRGB(168, 142, 92), material = Enum.Material.Sand },
		{ color = Color3.fromRGB(96, 96, 104), material = Enum.Material.Slate },
		{ color = Color3.fromRGB(120, 52, 30), material = Enum.Material.Rock },
	}
	for _ = 1, 14 do
		local x, z = scatterPoint(cx, 195, 245)
		local r = remains[math.random(1, #remains)]
		local w = math.random(14, 34)
		local y = math.random(18, 68)
		newPart({ Name = "WorldRemnant", Size = Vector3.new(w, math.random(3, 7), w * (0.6 + math.random() * 0.6)), Orientation = Vector3.new(math.random(-24, 24), math.random(0, 360), math.random(-24, 24)), Position = Vector3.new(x, y, z), Color = r.color, Material = r.material, CanCollide = false, Parent = model })
		newPart({ Name = "RemnantUnderside", Shape = Enum.PartType.Ball, Size = Vector3.new(w * 0.75, w * 0.6, w * 0.6), Position = Vector3.new(x, y - w * 0.28, z), Color = ash, Material = Enum.Material.Slate, CanCollide = false, Parent = model })
	end

	-- MID: unravelling threads. Thin violet strands hanging from the remnants down toward the
	-- holes give the two layers a relationship instead of leaving them as separate clutter.
	for _ = 1, 22 do
		local x, z = scatterPoint(cx, 200, 250)
		newPart({ Name = "UnravelThread", Size = Vector3.new(0.7, math.random(20, 54), 0.7), Orientation = Vector3.new(math.random(-14, 14), math.random(0, 360), math.random(-14, 14)), Position = Vector3.new(x, math.random(16, 50), z), Color = violet, Material = Enum.Material.Neon, Transparency = 0.4, CanCollide = false, Parent = model })
	end

	-- MID: obelisks, the last standing structures. Tall, narrow, unlit except at the tip, so the
	-- eye has something to measure the dark against.
	for _ = 1, 9 do
		local x, z = scatterPoint(cx)
		local h = math.random(26, 52)
		newPart({ Name = "VoidObelisk", Size = Vector3.new(5, h, 5), Orientation = Vector3.new(math.random(-4, 4), math.random(0, 360), math.random(-4, 4)), Position = Vector3.new(x, h / 2, z), Color = Color3.fromRGB(16, 13, 24), Material = Enum.Material.Slate, Parent = model })
		local tip = newPart({ Name = "ObeliskTip", Size = Vector3.new(3.4, 6, 3.4), Orientation = Vector3.new(0, 45, 0), Position = Vector3.new(x, h + 3, z), Color = violet, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(tip, violet, 26, 2)
	end
end

decorationBuilders.CelestialThrone = function(model, zone, cx)
	local gold = Color3.fromRGB(255, 218, 128)
	local deepGold = Color3.fromRGB(186, 148, 68)
	local marble = Color3.fromRGB(246, 240, 224)
	local throneZ = -190

	-- SIGNATURE LANDMARK: the throne itself, hand-built rather than routed through addLandmark --
	-- this is the zone's name, so it has to be a recognisable seat on a stepped dais, not another
	-- abstract tower. buildBiomeBase below is therefore asked for no landmark of its own.
	-- Set to one side like every other landmark, so the gate in the -Z wall keeps its approach.
	ACTIVE_FRAME = CFrame.new(-130, 0, 0)
	local y = 0
	for i = 1, 5 do
		local w = 130 - i * 16
		newPart({ Name = "ThroneStep", Size = Vector3.new(w, 5, w * 0.62), Position = Vector3.new(cx, y + 2.5, throneZ), Color = i % 2 == 0 and marble or lighten(deepGold, 0.45), Material = Enum.Material.Marble, Parent = model })
		newPart({ Name = "ThroneStepTrim", Size = Vector3.new(w + 3, 1, w * 0.62 + 3), Position = Vector3.new(cx, y + 5.2, throneZ), Color = gold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		y = y + 5
	end
	newPart({ Name = "ThroneSeat", Size = Vector3.new(30, 6, 24), Position = Vector3.new(cx, y + 3, throneZ), Color = deepGold, Material = Enum.Material.Metal, Parent = model })
	newPart({ Name = "ThroneBack", Size = Vector3.new(30, 52, 6), Position = Vector3.new(cx, y + 32, throneZ - 9), Color = deepGold, Material = Enum.Material.Metal, Parent = model })
	newPart({ Name = "ThroneBackInlay", Size = Vector3.new(20, 40, 1.4), Position = Vector3.new(cx, y + 30, throneZ - 5.6), Color = gold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	for _, side in ipairs({ -1, 1 }) do
		newPart({ Name = "ThroneArm", Size = Vector3.new(5, 12, 24), Position = Vector3.new(cx + side * 17, y + 10, throneZ), Color = deepGold, Material = Enum.Material.Metal, Parent = model })
		newPart({ Name = "ThroneFinial", Shape = Enum.PartType.Ball, Size = Vector3.new(8, 8, 8), Position = Vector3.new(cx + side * 17, y + 18, throneZ + 9), Color = gold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	end
	-- crown of haloes above the seat: the one element that makes the whole arrangement read as
	-- divine rather than merely expensive
	for i = 1, 3 do
		local halo = newPart({ Name = "ThroneHalo", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 34 + i * 16, 34 + i * 16), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(cx, y + 68 + i * 9, throneZ), Color = gold, Material = Enum.Material.Neon, Transparency = 0.12 + i * 0.16, CanCollide = false, Parent = model })
		if i == 1 then
			addLight(halo, gold, 70, 4)
		end
	end
	ACTIVE_FRAME = nil

	buildBiomeBase(model, cx, {
		litter = { count = 18, name = "GildedStone", colors = { marble, Color3.fromRGB(224, 206, 164), lighten(deepGold, 0.3) }, minSize = 3, maxSize = 10, material = Enum.Material.Marble },
		mounds = { count = 7, name = "CloudBank", color = Color3.fromRGB(252, 246, 230), material = Enum.Material.Foil, minSize = 40, maxSize = 78, flat = 0.24, transparency = 0.18 },
		atmosphere = { color = gold, color2 = Color3.fromRGB(255, 250, 226), height = 42, rate = 16, sizeStart = 1, sizeEnd = 3.4, transparency = 0.45, lifeMin = 7, lifeMax = 13, speedMin = 1, speedMax = 4, lightEmission = 1, acceleration = Vector3.new(0, 2, 0) },
		glow = { count = 6, color = gold, height = 18, range = 32, brightness = 2.6 },
	})

	-- SIGNATURE: the approach. Two colonnades running from the arrival side up to the dais turn
	-- the platform into a hall with a destination, which is what a throne needs to mean anything.
	for _, side in ipairs({ -1, 1 }) do
		for i = 1, 8 do
			local px = cx + side * 54
			local pz = 140 - i * 40
			newPart({ Name = "ColonnadeBase", Size = Vector3.new(16, 3, 16), Position = Vector3.new(px, 1.5, pz), Color = marble, Material = Enum.Material.Marble, Parent = model })
			newPart({ Name = "ColonnadePillar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(58, 11, 11), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(px, 32, pz), Color = marble, Material = Enum.Material.Marble, Parent = model })
			newPart({ Name = "ColonnadeCap", Size = Vector3.new(15, 4, 15), Position = Vector3.new(px, 63, pz), Color = deepGold, Material = Enum.Material.Metal, CanCollide = false, Parent = model })
			local flame = newPart({ Name = "ColonnadeFlame", Shape = Enum.PartType.Ball, Size = Vector3.new(7.5, 7.5, 7.5), Position = Vector3.new(px, 69, pz), Color = gold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
			addLight(flame, gold, 34, 2.6)
			-- banners hung between the pillars, so the gap between them is not dead air
			newPart({ Name = "Banner", Size = Vector3.new(0.6, 26, 13), Position = Vector3.new(px - side * 6, 48, pz), Color = Color3.fromRGB(196, 62, 74), Material = Enum.Material.Fabric, CanCollide = false, Parent = model })
			newPart({ Name = "BannerTrim", Size = Vector3.new(0.8, 2.2, 14), Position = Vector3.new(px - side * 6, 35, pz), Color = gold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		end
	end

	-- MID: a gold carpet down the centre of the hall, edged in neon
	newPart({ Name = "Carpet", Size = Vector3.new(34, 0.5, 300), Position = Vector3.new(cx, 0.4, 10), Color = Color3.fromRGB(176, 48, 62), Material = Enum.Material.Fabric, CanCollide = false, Parent = model })
	for _, side in ipairs({ -1, 1 }) do
		newPart({ Name = "CarpetEdge", Size = Vector3.new(1.6, 0.6, 300), Position = Vector3.new(cx + side * 17, 0.45, 10), Color = gold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	end

	-- MID: floating haloes drifting over the hall, small and many, so the air above the colonnade
	-- carries the same motif as the throne
	for _ = 1, 20 do
		local x, z = scatterPoint(cx, 200, 250)
		local d = math.random(8, 20)
		newPart({ Name = "FloatingHalo", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, d, d), Orientation = Vector3.new(math.random(-25, 25), math.random(0, 360), 90), Position = Vector3.new(x, math.random(20, 72), z), Color = gold, Material = Enum.Material.Neon, Transparency = 0.3, CanCollide = false, Parent = model })
	end

	-- MID: braziers and offering bowls at ground level between the colonnades
	for _ = 1, 10 do
		local x, z = scatterPoint(cx)
		newPart({ Name = "BrazierStem", Size = Vector3.new(3, 11, 3), Position = Vector3.new(x, 5.5, z), Color = deepGold, Material = Enum.Material.Metal, Parent = model })
		newPart({ Name = "BrazierBowl", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 13, 13), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(x, 12.5, z), Color = deepGold, Material = Enum.Material.Metal, CanCollide = false, Parent = model })
		local fire = newPart({ Name = "BrazierFire", Shape = Enum.PartType.Ball, Size = Vector3.new(9, 7, 9), Position = Vector3.new(x, 15.5, z), Color = gold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(fire, gold, 28, 2.4)
	end
end

decorationBuilders.Singularity = function(model, zone, cx)
	local white = Color3.fromRGB(255, 255, 255)
	local pale = Color3.fromRGB(206, 214, 236)
	local shell = Color3.fromRGB(22, 22, 30)
	local coreY, coreZ = 92, -186

	-- SIGNATURE LANDMARK: the point everything is falling into. Hand-built so the shells can be
	-- real concentric rings on three axes around one blinding core; buildBiomeBase gets no
	-- landmark of its own because a second silhouette would break the convergence read.
	local core = newPart({ Name = "SingularityCore", Shape = Enum.PartType.Ball, Size = Vector3.new(30, 30, 30), Position = Vector3.new(cx, coreY, coreZ), Color = white, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	addLight(core, white, 120, 6)
	for i = 1, 5 do
		local d = 52 + i * 24
		for _, axis in ipairs({ Vector3.new(0, 0, 90), Vector3.new(90, 0, 0), Vector3.new(0, 90, 90) }) do
			newPart({ Name = "CollapseShell", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, d, d), Orientation = axis + Vector3.new(i * 7, i * 11, 0), Position = Vector3.new(cx, coreY, coreZ), Color = i <= 2 and white or pale, Material = Enum.Material.Neon, Transparency = 0.4 + i * 0.1, CanCollide = false, Parent = model })
		end
	end
	local suck = Instance.new("ParticleEmitter")
	suck.Color = ColorSequence.new(pale, white)
	suck.Size = NumberSequence.new(4, 0.1)
	suck.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	suck.Lifetime = NumberRange.new(2, 3.5)
	suck.Rate = 60
	suck.Speed = NumberRange.new(-46, -30)
	suck.SpreadAngle = Vector2.new(180, 180)
	suck.LightEmission = 1
	suck.Parent = core

	buildBiomeBase(model, cx, {
		litter = { count = 20, name = "CollapsedGrit", colors = { shell, Color3.fromRGB(12, 12, 18), Color3.fromRGB(46, 46, 60) }, minSize = 2, maxSize = 8, shape = Enum.PartType.Block, flat = 0.8, material = Enum.Material.Foil },
		mounds = { count = 4, name = "DrawnSwell", color = Color3.fromRGB(18, 18, 26), material = Enum.Material.Foil, minSize = 32, maxSize = 62, flat = 0.18 },
		atmosphere = { color = white, color2 = pale, height = 44, rate = 22, sizeStart = 2, sizeEnd = 0.3, transparency = 0.35, lifeMin = 3, lifeMax = 7, speedMin = 10, speedMax = 20, lightEmission = 1 },
		glow = { count = 5, color = pale, height = 17, range = 30, brightness = 2.4 },
	})

	-- SIGNATURE: a floor grid dragged toward the core. Straight lines that visibly bend are the
	-- clearest possible drawing of curved space, and they give the dark floor a readable surface.
	for i = -9, 9 do
		local x = cx + i * 22
		for seg = 0, 11 do
			local z = 250 - seg * 44
			local pull = (1 - math.abs(z - coreZ) / 520) * i * -7
			newPart({ Name = "GridLine", Size = Vector3.new(1.2, 0.4, 46), Orientation = Vector3.new(0, pull * 0.4, 0), Position = Vector3.new(x + pull, 0.3, z), Color = pale, Material = Enum.Material.Neon, Transparency = 0.45, CanCollide = false, Parent = model })
		end
	end

	-- MID: collapsing structures. Blocks stretched along the axis to the core, each leaning the
	-- same way, so the mid-field shows the pull instead of merely sitting under it.
	for _ = 1, 22 do
		local x, z = scatterPoint(cx, 200, 250)
		local dx, dz = cx - x, coreZ - z
		local yaw = math.deg(math.atan2(dx, dz))
		local len = math.random(14, 44)
		newPart({ Name = "StretchedMass", Size = Vector3.new(math.random(4, 10), math.random(4, 10), len), Orientation = Vector3.new(math.random(-14, 14), yaw, math.random(-20, 20)), Position = Vector3.new(x, math.random(4, 40), z), Color = shell, Material = Enum.Material.Foil, CanCollide = false, Parent = model })
	end

	-- MID: light lances running the same line, so the pull is drawn in light as well as in mass
	for _ = 1, 20 do
		local x, z = scatterPoint(cx, 200, 250)
		local dx, dz = cx - x, coreZ - z
		local yaw = math.deg(math.atan2(dx, dz))
		newPart({ Name = "LightLance", Size = Vector3.new(0.8, 0.8, math.random(30, 90)), Orientation = Vector3.new(math.random(-10, 10), yaw, 0), Position = Vector3.new(x, math.random(8, 66), z), Color = white, Material = Enum.Material.Neon, Transparency = 0.42, CanCollide = false, Parent = model })
	end

	-- MID: monoliths still standing, each tipped toward the core -- the last things with a
	-- silhouette, and the only vertical scale reference in an otherwise horizontal zone
	for _ = 1, 10 do
		local x, z = scatterPoint(cx)
		local dx, dz = cx - x, coreZ - z
		local yaw = math.deg(math.atan2(dx, dz))
		local h = math.random(22, 48)
		newPart({ Name = "LeaningMonolith", Size = Vector3.new(6, h, 4), Orientation = Vector3.new(math.random(10, 24), yaw, 0), Position = Vector3.new(x, h / 2, z), Color = Color3.fromRGB(30, 30, 40), Material = Enum.Material.Foil, Parent = model })
		local crown = newPart({ Name = "MonolithCrown", Shape = Enum.PartType.Ball, Size = Vector3.new(5, 5, 5), Position = Vector3.new(x, h + 2, z), Color = white, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(crown, pale, 22, 1.8)
	end
end

decorationBuilders.AbsolutePlane = function(model, zone, cx)
	local gold = Color3.fromRGB(255, 215, 0)
	local paleGold = Color3.fromRGB(255, 240, 178)
	local bone = Color3.fromRGB(248, 248, 244)

	buildBiomeBase(model, cx, {
		litter = { count = 14, name = "AbsoluteChip", colors = { bone, Color3.fromRGB(232, 232, 226), paleGold }, minSize = 2, maxSize = 7, shape = Enum.PartType.Block, flat = 0.9, material = Enum.Material.SmoothPlastic },
		mounds = { count = 4, name = "WhiteSwell", color = Color3.fromRGB(250, 250, 246), material = Enum.Material.SmoothPlastic, minSize = 36, maxSize = 68, flat = 0.18 },
		landmark = { style = "arch", base = bone, accent = gold, material = Enum.Material.Marble },
		atmosphere = { color = paleGold, color2 = bone, height = 46, rate = 12, sizeStart = 1, sizeEnd = 3, transparency = 0.55, lifeMin = 8, lifeMax = 14, speedMin = 0.5, speedMax = 2.5, lightEmission = 1 },
		glow = { count = 6, color = gold, height = 18, range = 32, brightness = 2.6 },
	})

	-- SIGNATURE: the grid. On a white floor a gold lattice is the only thing that establishes
	-- scale and direction at all -- without it the endgame zone reads as an unfinished baseplate.
	for i = -8, 8 do
		newPart({ Name = "GridX", Size = Vector3.new(0.9, 0.4, PLATFORM_DEPTH - 30), Position = Vector3.new(cx + i * 26, 0.3, 0), Color = gold, Material = Enum.Material.Neon, Transparency = 0.45, CanCollide = false, Parent = model })
	end
	for i = -10, 10 do
		newPart({ Name = "GridZ", Size = Vector3.new(PLATFORM_WIDTH - 30, 0.4, 0.9), Position = Vector3.new(cx, 0.3, i * 26), Color = gold, Material = Enum.Material.Neon, Transparency = 0.45, CanCollide = false, Parent = model })
	end

	-- SIGNATURE: a ring of gold monoliths around the plaza, tall enough to be the skyline. Twelve
	-- identical, evenly spaced -- the deliberate symmetry is the point, this is the one zone that
	-- should look designed rather than grown.
	for i = 1, 12 do
		local a = (i / 12) * math.pi * 2
		local x = cx + math.cos(a) * 168
		local z = math.sin(a) * 200
		local h = 96
		-- leave both doorways open: the ring crosses the centre line twice, once at the arrival pad
		-- and once on the walk out to the exit gate, and either way that is a 96-stud slab dropped
		-- in the middle of the street. Dropping both keeps the ring symmetrical, which is the point
		-- of building it in the first place.
		if math.abs(x - cx) >= 80 then
			newPart({ Name = "AbsoluteMonolith", Size = Vector3.new(11, h, 6), Orientation = Vector3.new(0, math.deg(a), 0), Position = Vector3.new(x, h / 2, z), Color = bone, Material = Enum.Material.Marble, Parent = model })
			newPart({ Name = "MonolithInlay", Size = Vector3.new(5, h - 20, 1.4), Orientation = Vector3.new(0, math.deg(a), 0), Position = Vector3.new(x + math.cos(a) * -3.4, h / 2, z + math.sin(a) * -3.4), Color = gold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
			local capstone = newPart({ Name = "MonolithCap", Size = Vector3.new(13, 7, 8), Orientation = Vector3.new(0, math.deg(a), 45), Position = Vector3.new(x, h + 4, z), Color = gold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
			addLight(capstone, gold, 40, 3)
		end
	end

	-- MID: platonic solids turning in the air. Perfect shapes rather than debris -- everything
	-- here is finished, which is what separates this zone from the Void two stops back.
	for _ = 1, 16 do
		local x, z = scatterPoint(cx, 195, 245)
		local s = math.random(9, 22)
		local y = math.random(18, 74)
		local orient = Vector3.new(math.random(0, 360), math.random(0, 360), math.random(0, 360))
		if math.random(1, 2) == 1 then
			newPart({ Name = "AbsoluteSolid", Size = Vector3.new(s, s, s), Orientation = orient, Position = Vector3.new(x, y, z), Color = bone, Material = Enum.Material.Marble, CanCollide = false, Parent = model })
			newPart({ Name = "SolidEdgeGlow", Size = Vector3.new(s + 1.2, s * 0.14, s + 1.2), Orientation = orient, Position = Vector3.new(x, y, z), Color = gold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		else
			local orb = newPart({ Name = "AbsoluteOrb", Shape = Enum.PartType.Ball, Size = Vector3.new(s, s, s), Position = Vector3.new(x, y, z), Color = paleGold, Material = Enum.Material.Neon, Transparency = 0.25, CanCollide = false, Parent = model })
			addLight(orb, gold, 26, 2)
		end
	end

	-- MID: the shaft. One column of light from the floor to well past the wall height, at the
	-- centre of the monolith ring, so the zone has a single unambiguous focal point.
	newPart({ Name = "AbsoluteShaft", Shape = Enum.PartType.Cylinder, Size = Vector3.new(190, 26, 26), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(cx, 95, -150), Color = paleGold, Material = Enum.Material.Neon, Transparency = 0.62, CanCollide = false, Parent = model })
	for i = 1, 4 do
		local ring = newPart({ Name = "ShaftRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 44 + i * 14, 44 + i * 14), Orientation = Vector3.new(0, 0, 90), Position = Vector3.new(cx, 18 + i * 34, -150), Color = gold, Material = Enum.Material.Neon, Transparency = 0.25 + i * 0.1, CanCollide = false, Parent = model })
		if i == 1 then
			addLight(ring, gold, 60, 3.4)
		end
	end

	-- MID: low plinths tracing the grid intersections, so the walkable band has objects at eye
	-- level and the floor pattern is echoed in three dimensions
	for _ = 1, 14 do
		local x, z = scatterPoint(cx)
		local h = math.random(7, 18)
		newPart({ Name = "AbsolutePlinth", Size = Vector3.new(12, h, 12), Position = Vector3.new(x, h / 2, z), Color = bone, Material = Enum.Material.Marble, Parent = model })
		newPart({ Name = "PlinthTrim", Size = Vector3.new(13.4, 1.2, 13.4), Position = Vector3.new(x, h, z), Color = gold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		local votive = newPart({ Name = "PlinthVotive", Shape = Enum.PartType.Ball, Size = Vector3.new(6, 6, 6), Position = Vector3.new(x, h + 4, z), Color = paleGold, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		addLight(votive, gold, 22, 1.8)
	end
end

-- Moves (or creates) the one canonical SpawnLocation onto the Forest arrival clearing. Called at
-- the end of Build(), so the Forest floor it stands on already exists. Any extra SpawnLocations
-- are removed -- Roblox picks between them at random, so a stray one left in the Forest monument
-- footprint would still strand a share of players inside the shop.
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
	local previous = ACTIVE_FRAME
	ACTIVE_FRAME = CFrame.new(centre + Vector3.new(0, 0, -(R + 8))) * CFrame.Angles(0, math.rad(-90), 0)
	buildPortal(model, 0, returnTarget, 1)
	ACTIVE_FRAME = previous

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
				Color = candy(i), Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
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
	CliffJut = true,
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
	Mound = true,               -- 3,460-stud footprint of walkable hillock
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
end

function ZoneBuilder.Build()
	applyDistanceFog()

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
				Color = zone.groundColor,
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
			newPart({ Name = "ArrivalSignPost", Size = Vector3.new(2.6, 21, 2.6), Position = Vector3.new(signX, 10.5, 310), Color = VILLAGE_WOOD_DARK, Material = Enum.Material.Wood, Parent = model })
			local arrivalBoard = newPart({ Name = "ArrivalSignBoard", Size = Vector3.new(32, 12, 1.8), Position = Vector3.new(signX, 27, 310), Color = VILLAGE_WOOD, Material = Enum.Material.WoodPlanks, CanCollide = false, Parent = model })
			for _, sx in ipairs({ -1, 1 }) do
				newPart({ Name = "ArrivalSignBatten", Size = Vector3.new(1.8, 14, 2.4), Position = Vector3.new(signX + sx * 15, 27, 310), Color = VILLAGE_WOOD_DARK, Material = Enum.Material.Wood, CanCollide = false, Parent = model })
				addKnob(model, Vector3.new(signX + sx * 15, 35, 310), 3.2, VILLAGE_CREAM)
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
			-- nineteen zones out of twenty. See the block above VILLAGE_STYLE.
			applyVillageStyle(zone.key)

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
				for i = 1, 16 do
					local edge = math.random(1, 4)
					local rx, rz
					if edge <= 2 then
						-- off the centre line, like everything else: this row runs along the Z walls,
						-- which is exactly where a gate opens at one end and the walk out of it begins
						-- at the other
						rx = cx + (math.random(1, 2) == 1 and -1 or 1) * math.random(STREET_HALF + 12, 200)
						local zSign = edge == 1 and -1 or 1
						rz = zSign * (PLATFORM_DEPTH / 2 - math.random(15, 65))
					else
						local xSign = edge == 3 and -1 or 1
						rx = cx + xSign * (PLATFORM_WIDTH / 2 - math.random(15, 55))
						rz = (math.random(1, 2) == 1) and math.random(80, 320) or math.random(-320, -80)
					end
					local rock = cliffTemplate:Clone()
					local scale = 0.35 + math.random() * 0.35
					rock:ScaleTo(scale)
					local geom = rock:FindFirstChild("body") and rock.body:FindFirstChild("body_geom")
					local halfHeight = (geom and geom.Size.Y / 2 or 65) * scale
					rock:PivotTo(CFrame.new(rx, halfHeight - 3, rz) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
					rock.Parent = model
				end
			end

			-- THE VALLEY WALLS, BEFORE THE DECORATION. Called from here rather than from
			-- buildBiomeBase for one reason: buildBiomeBase takes a config table and not the zone,
			-- and threading `zone` through it would have meant editing all twenty biome builders to
			-- pass something none of them otherwise needs. Here the zone is already in hand, it is one
			-- line, and every zone gets terrain by construction instead of by remembering to opt in.
			buildTerrain(model, zone, cx)

			-- WHICH ZONE'S MESH PROPS TO CLONE. buildBiomeBase is handed a config table and not the
			-- zone -- twenty biome builders call it and not one of them passes anything else -- so the
			-- key is left here for it to pick up, at the one point where the zone is already in hand.
			-- Same reasoning as buildTerrain being called from this loop rather than from inside it.
			ACTIVE_ZONE_KEY = zone.key
			local builder = decorationBuilders[zone.key]
			if builder then
				builder(model, zone, cx)
			end
			ACTIVE_ZONE_KEY = nil

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

