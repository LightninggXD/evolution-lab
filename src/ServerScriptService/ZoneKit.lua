-- ZoneKit -- the vocabulary the world is built in: the part factory, the two rules it applies
-- without being asked (shadow by size, solidity by name), the placement frame those rules read,
-- the platform's own dimensions, the sign palette, and the small verbs the scenery is painted,
-- lit, seated, labelled and animated with.
--
-- WHY THIS IS ITS OWN FILE, AND WHY IT IS THE FIRST THING OUT (18.9)
-- -----------------------------------------------------------------
-- `ZoneBuilder` is 9,281 lines -- ~152k tokens to read whole, which is most of a context window
-- spent to move one prop. Splitting it is NOT the job `MainUI` was. MainUI's 23 blocks were
-- already `;(function() ... end)()` closures that escaped nothing, so each one was a module
-- already and the split was a change of wrapper. ZoneBuilder has **190 top-level `local` lines, 48
-- of them used across spans of 600+ lines**, and `newPart` alone is called at **534 sites** spread
-- over the whole file. There is no line at which a cut leaves the locals behind.
--
-- AND THAT 190 IS THE WRONG NUMBER TO BE FRIGHTENED BY -- THE REAL ONE IS 198. The scan that
-- opened this counted *lines*; Luau counts *names*, and `local addKnob, addScallops, addBunting,
-- addPlanter, candy` is one line and five registers. Counted the way the compiler counts,
-- ZoneBuilder stood at **198 of Luau's 200 top-level registers** -- two away from the cliff MainUI
-- has been living on for a year, in a file where one more `local` at column 0 stops the entire
-- world from building. Nobody knew that. This move takes it to 189.
--
-- So the order is inverted: the shared vocabulary comes out FIRST, and the leaves (the village
-- prop library, the ground clutter, the idols and ruins, the mesh prop layer, the egg plaza, the
-- boss arena) move onto it afterwards, each one a section that only reads this. Nothing else
-- could move until this file existed. The measured order is `docs/SPLIT.md` §6.
--
-- WHAT IS AND IS NOT IN HERE. A rule every part in the world obeys is in here; a decision about
-- one zone is not. `GROUND_MATERIAL` -- which material each of the twenty floors is -- stays in
-- `ZoneBuilder`, and `groundColorOf` -- how bright ANY floor is allowed to be -- is here. That is
-- the same line 17.7 drew when it put the luminance ceiling in the builder instead of in the
-- zone's own table: a zone author says what colour the ground IS, the builder knows how bright a
-- floor may BE.
--
-- THE ONE PIECE OF MUTABLE STATE, AND WHY IT HAS ACCESSORS. `ACTIVE_FRAME` is an upvalue that
-- `newPart` reads on every one of those 534 calls and `spinForever` reads on every tween goal, so
-- it can be neither passed nor copied: a `local ACTIVE_FRAME = ZoneKit.ACTIVE_FRAME` in the
-- builder would be frozen at nil forever, silently, with no error anywhere -- exactly the trap
-- `docs/SPLIT.md` §3 rule 2 records from the MainUI split. It is reached through `setFrame` and
-- `getFrame` and nothing else, so the frame has exactly one owner.
--
-- Everything below is byte-for-byte what was at the top of `ZoneBuilder`, comments included. NINE
-- COMMENT LINES WERE REPOINTED and nothing else -- phrases like "104 call sites in this file"
-- meant ZoneBuilder and now say so, because a comment that lies about where a thing lives is the
-- most expensive line in the file to keep (GEMINI.md rule 10).
--
-- WHO MAY REQUIRE IT: any server script that builds world geometry. `HubPlaza`, `RebirthShrine`
-- and `LeaderboardService` all stand their own furniture and all re-derive some of this; they are
-- deliberately NOT changed by this move, because nobody asked for that and each of them is behind
-- its own version stamp.
--
-- Where the rest of ZoneBuilder lives: `docs/CODEMAP.md`.

local TweenService = game:GetService("TweenService")

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

-- ===== WHERE THE TERRACE BAND STARTS AND STOPS (11.23) =====
-- These two used to be declared down beside TERRAIN_PROFILE in `ZoneBuilder`, which is where the
-- long note explaining them still lives. They came up out of it because the WALLS have to know
-- them: `addRockRampart` runs 1,500 lines above the terrain section and it is the one thing in
-- that file that stands in the same ground the terraces occupy, so it cannot be written without
-- them.
-- Read the note over TERRAIN_PROFILE for what the band is FOR; these are just the two numbers.
--
-- 623, NOT 625. The X wall's sealing slab is WALL_THICK thick centred on cx +/- 625, i.e. it
-- occupies 623..627 -- so a terrace slab that ran to 625 put two studs of solid ground inside a
-- solid wall, 1,032 times across the world. The band now stops exactly at the wall's inner face.
local TERRAIN_INNER = 415        -- where the valley floor ends and the first cliff begins
local TERRAIN_OUTER = 623        -- the inner face of the boundary wall
-- ...and the same two studs at each end of the depth, for the Z walls.
local TERRAIN_DEPTH = PLATFORM_DEPTH - WALL_THICK

-- ---- THE GROUND IS NEVER THE BRIGHTEST THING IN ITS OWN ZONE (17.7)
--
-- Reported as "ovi zadnji stagevi su samo bela svetlost i nista zivo se ne vidi", with a capture of
-- The Absolute Plane: a white ground under a white haze with white props on it, the only readable
-- thing in the frame being the black outline round her own body.
--
-- The zone's ground is authored at rgb(255, 255, 255) -- luminance 1.00, where the next brightest
-- ground in the whole game is Desert's 0.79 and every other zone sits below it. Nothing placed on a
-- floor that bright can be lighter than it, so the ground stops being a surface things sit ON and
-- becomes the brightest object in frame; and the outline that carries this game's whole look has
-- nothing left to sit against.
--
-- THE CEILING LIVES HERE RATHER THAN IN THE ZONE'S TABLE, for the same reason 17.1 put the emitter
-- ceiling in `VFXLibrary` beside the tint: a zone author says what colour the ground IS, and the
-- builder is what knows how bright a floor is allowed to BE. It is a ceiling and never an
-- assignment -- nineteen of the twenty zones pass through it untouched.
--
-- The two white-floor workarounds already in `ZoneBuilder` (the patch tones, and the cliffs) are
-- deliberately left alone and still fire: a capped Absolute Plane reads 0.80, which is still the
-- brightest ground in the game and still needs its decoration to step DOWN rather than up.
local GROUND_MAX_LUM = 0.80

local function groundColorOf(zone)
	local c = zone.groundColor
	local l = 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
	if l <= GROUND_MAX_LUM then
		return c
	end
	return c:Lerp(Color3.new(0, 0, 0), 1 - GROUND_MAX_LUM / l)
end

-- While this is set, every part newPart makes is placed *through* it instead of straight into
-- world space, so a builder written for one spot and one orientation can be re-used anywhere.
-- The portal gateway is written entirely in the plane x = wallX with +X pointing at the zone
-- interior; handing it a frame is what lets the same 170 lines stand a gate in a Z wall without
-- re-deriving a single coordinate. spinForever transforms its base the same way, so tweened
-- parts stay in step with the parts they were built from.
local ACTIVE_FRAME = nil

-- ===== SHADOWS ARE DECIDED BY SIZE, IN ONE PLACE =====
--
-- `CastShadow = false` appears at **104 call sites** in `ZoneBuilder` and `CastShadow = true` at
-- none:
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
local SHADOW_MIN_LONG = 1.5
local SHADOW_MIN_SHORT = 0.2
local SHADOW_MAX_VOL = 200000

-- ===== WHAT IS SOLID, AND WHY THIS LIST IS SHORT =====
--
-- `CanCollide = false` appears at 418 sites in `ZoneBuilder`, and the obvious reading -- that the
-- world
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

	-- ===== THE SAME TWO OBJECTS UNDER TWENTY NAMES (11.21) =====
	--
	-- `GroundRock` and `Mound` above are not two props. They are the DEFAULT names of
	-- `addGroundLitter` and `addMounds` -- and eighteen of the twenty litter configs and nineteen of
	-- the twenty mound configs pass a `name` of their own, because a moon rock should not be called
	-- GroundRock in the explorer. Both builders write `CanCollide = false` and rely entirely on this
	-- table to put it back, so the two zones that kept the default were solid and the other eighteen
	-- were not. Measured on a fresh build: 621 litter parts and 169 mounds, 0 of them colliding.
	--
	-- The names are listed rather than pattern-matched on purpose. A rule like "anything ending in
	-- Rock" would have swept up scenery nobody should collide with, and the warn at the end of
	-- Build() is what stops this list rotting again -- see SOLID_SEEN.
	Shell = true, LavaRock = true, MoonRock = true, MarsRock = true, Meteorite = true,
	Debris = true, RealityChip = true, Cinder = true, Fragment = true, Quanta = true,
	Cog = true, SlagChunk = true, Pebble = true, GlassShard = true, VoidGrit = true,
	GildedStone = true, CollapsedGrit = true, AbsoluteChip = true,
	Sandbar = true, AshMound = true, RegolithMound = true, DustRidge = true,
	StardustDrift = true, CollapsedRidge = true, VoidMound = true, DustBank = true,
	WarpSwell = true, FieldSwell = true, SandDrift = true, BlastBerm = true,
	CloudBank = true, PolishedSwell = true, AshSwell = true, DrawnSwell = true, WhiteSwell = true,
}

-- Names in SOLID_PROPS that a build is NOT expected to produce, so the audit below stays worth
-- reading. Both of these belong to `addLamp`'s primitive fallback, which every zone now skips
-- because a `Vill_Lamp` mesh is filed -- they are correct entries guarding a branch that is still
-- reachable if that mesh is ever missing, not rot. Anything else silent is rot.
local SOLID_PROPS_OPTIONAL = { LampPost = true, LampFoot = true }
-- Every SOLID_PROPS name this build actually created. Cleared at the top of Build().
local SOLID_SEEN = {}

-- ===== WHY THIS AUDIT EXISTS (11.21) =====
-- The list above is a set of NAMES, and names are the one thing in the builder that a per-biome
-- config can change without anything noticing. Eighteen zones renamed their ground litter and
-- nineteen renamed their mounds, and the whole solidity rule silently stopped applying to them for
-- as long as it took somebody to walk through a boulder and measure it. A name that never appears
-- is either a typo or a prop that has been renamed out from under this table; either way it is a
-- rule that is not doing anything, and it should say so once per build rather than never.
local function auditSolidProps()
	local unseen = {}
	for name in pairs(SOLID_PROPS) do
		if not SOLID_SEEN[name] and not SOLID_PROPS_OPTIONAL[name] then
			unseen[#unseen + 1] = name
		end
	end
	if #unseen > 0 then
		table.sort(unseen)
		warn(("[ZoneBuilder] SOLID_PROPS has %d name(s) nothing in this build ever created -- "
			.. "either the prop was renamed and is now walk-through, or the entry is dead: %s")
			:format(#unseen, table.concat(unseen, ", ")))
	end
end

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
	-- LAST, and deliberately overriding the caller. The 104 `CastShadow = false` props in `ZoneBuilder`
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
		SOLID_SEEN[p.Name] = true
	end
	return p
end

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

-- ===== FOUR MORE VERBS, MOVED DOWN FOR THE VILLAGE LEAF (18.10) =====
--
-- These four were still `ZoneBuilder`'s when the village prop library came to move, and every one
-- of them was already vocabulary rather than a decision about a zone -- `makeSign` even reads the
-- SIGN_* palette that had been sitting up in this file without it. They are byte-for-byte what was
-- in the builder, except that `addLight` gained the `local` it never needed there (it was filling
-- a forward declaration 2,500 lines above itself, which is a shape that only means anything inside
-- the file that wrote the declaration).
--
-- All four are re-localised on the builder's side, so their 110 call sites read exactly as before.

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

-- Rock is the zone's own ground colour pulled toward white in three steps, so a Forest cliff comes
-- out pale green and a Mars cliff pale rust without one hand-picked palette anywhere.
local function stoneTones(zone)
	local g = groundColorOf(zone)
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

local function addLight(part, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range or 24
	l.Brightness = brightness or 2
	l.Parent = part
	return l
end

-- ===== THE FRAME HAS EXACTLY ONE OWNER =====
-- These two are the whole interface to `ACTIVE_FRAME`. `ZoneBuilder` sets it around a builder that
-- was written for one spot and one orientation -- the portal in a Z wall, the Volcano cone, the
-- Celestial throne, the arena's return gate -- and puts back what was there before. It is never
-- read into a local on the other side of the require, for the reason in the header.
local function setFrame(cf)
	ACTIVE_FRAME = cf
end

local function getFrame()
	return ACTIVE_FRAME
end

-- Cleared at the top of Build(). The note over Build() is why it matters that this is a call and
-- not a `table.clear` from anywhere that fancies one: an audit is only worth reading for a pass
-- that actually made something, and a second pass that made nothing once printed 52 false names.
local function resetSolidSeen()
	table.clear(SOLID_SEEN)
end

return {
	newPart = newPart,
	groundColorOf = groundColorOf,
	addPlankText = addPlankText,
	vivid = vivid,
	spinForever = spinForever,
	pulseForever = pulseForever,

	seatModel = seatModel,
	makeSign = makeSign,
	stoneTones = stoneTones,
	addLight = addLight,

	setFrame = setFrame,
	getFrame = getFrame,
	auditSolidProps = auditSolidProps,
	resetSolidSeen = resetSolidSeen,

	PLATFORM_DEPTH = PLATFORM_DEPTH,
	PLATFORM_WIDTH = PLATFORM_WIDTH,
	WALL_HEIGHT = WALL_HEIGHT,
	WALL_THICK = WALL_THICK,
	PORTAL_GAP = PORTAL_GAP,
	TERRAIN_INNER = TERRAIN_INNER,
	TERRAIN_OUTER = TERRAIN_OUTER,
	TERRAIN_DEPTH = TERRAIN_DEPTH,

	SIGN_INK = SIGN_INK,
	SIGN_RIM = SIGN_RIM,
	SIGN_FACE = SIGN_FACE,
	SIGN_FONT = SIGN_FONT,
}
