--[[
	HubPlaza -- the Forest arrival square: one paved deck that ties together the things that were
	already standing on that lawn but had nothing between them.

	WHAT WAS WRONG. Forest's spawn end grew four separate features over four different roadmap rows,
	each of which searched the same empty lawn for a spot and found one: the three leaderboard boards
	at x = -130 (5.3), the event board at x = 150 (7.1), the Splicer at roughly (68, 215) (12.2) and
	the spawn clearing itself at (0, 366). Each is fine on its own and none of them knows the others
	exist, so the arrival end of the game reads as four objects dropped on a field. A hub is not more
	objects; it is a FLOOR that says the objects belong to each other.

	WHY THIS DOES NOT TOUCH ZoneBuilder. Same reason LeaderboardService and RebirthShrine do not:
	that file is 560 KB, its BUILD_VERSION guard regenerates all twenty zones when it moves, and a
	plaza is scenery rather than terrain. This owns its own PLAZA_VERSION and its own folder, and
	sets ModelStreamingMode.Persistent on the model instead of adding names to ALWAYS_LOADED.

	=========================================================================================
	THE THREE CONSTRAINTS, ALL MEASURED AGAINST THE LIVE WORLD RATHER THAN ASSUMED
	=========================================================================================
	1. THE STREET CORRIDOR STAYS EMPTY. ZoneBuilder's street runs down x = -20..20 with fence runs
	   at x = +-24, planters at +-29, lamp posts at +-32 every 30 studs and benches at +-38 -- the
	   whole of |x| < 40 is already furnished, and it is also the line every player walks. Nothing
	   this file builds that STANDS UP may enter |x| <= CORRIDOR_HALF; `standAt` refuses the
	   placement outright rather than trusting the caller. Flat paving may cross it, because a
	   painted floor is not an obstruction -- the medallion and the arrival dais are both flush.
	2. EVERY UPRIGHT PIECE IS SEARCHED, NOT ASSERTED. `standAt` box-queries its own footprint and
	   steps along a widening offset list until it finds ground nothing is standing on. This is not
	   defensive coding: the leaderboards, the event sign and the Splicer are built by three other
	   services minutes earlier in the same boot, two of them into positions that are themselves
	   searched -- so their exact coordinates are not knowable from here at edit time.
	   A cell-occupancy scan cannot see a big part whose centre is in the next cell (7.1's finding),
	   so the query is a box over the real footprint and the test is a world-space AABB, computed
	   from the part's own rotation rather than from Size.Y.
	3. CREATURES ARE NOT OBSTRUCTIONS. They walk. A clearance measured against a `body_geom` is a
	   fact about one instant, not about a place, so the Creatures / EquippedPets / Eggs folders are
	   filtered out of the query along with this model's own parts.

	HEIGHTS, AND WHY THEY ARE ALL DIFFERENT. Forest's floor tops out at y = 0. Coplanar faces ARE
	z-fighting (the terrace shimmer was exactly this), so every layer here gets its own plane:
	kerb 0.66, deck 1.04, inlay 1.14, cross bands 1.18, medallion 1.24/1.31/1.38, dais 1.26/1.33,
	photo spot 1.28/1.42/1.52. The deck buries the path and the lawn patches inside its footprint --
	which is the point, a plaza replaces the lawn -- and everything taller (fences, planters, lamps,
	benches, flowers, the street's verge boulders) keeps standing, now on stone instead of grass.

	THE DECK HEIGHT IS DERIVED, NOT CHOSEN, AND THE FIRST CUT GOT IT WRONG BY SAMPLING. It was 0.78,
	picked off a reading of "the ground patches sit at 0.47" taken from one boot -- but Forest's
	patches are a STACK, laid by `for i = 1, 70` at `y = 0.05 + i * 0.01` with a half-thickness of
	0.2, so their top face runs from 0.26 to a hard ceiling of **0.95**. Which of them land inside
	this footprint is down to `scatterPoint`'s math.random and changes every rebuild, so a deck at
	0.78 is not "usually fine", it is a coin toss re-thrown on every boot: measured on one such boot,
	one 23 x 24 patch stood 0.07 proud and read as a green pond in the middle of the pavement, and
	the inlay at 0.90 was inside the same band. The deck clears the derived ceiling by 0.09 now.
	Do not lower these numbers to match a height you measured on one world.

	NOTHING IS EVER DELETED. ZoneBuilder rebuilds its own decor behind its own version stamp; a
	plaza that removed the flowers it paves around would have them back the next time that stamp
	moved, and would then be a plaza with a hole in it. Paving over is idempotent, deleting is not.
--]]

local RS = game:GetService("ReplicatedStorage")

local UITheme = require(RS.Modules.UITheme)
local GameConfig = require(RS.Modules.GameConfig)
-- The Exhibit stands the real wardrobe up: `SkinMesh.TemplateFor` is the same lookup the
-- costume path uses, so a statue is the skin rather than a model of it.
local SkinMesh = require(RS.Modules.SkinMesh)
-- Only for the photo reward at the bottom of this file; the plaza itself touches no save.
local PlayerDataService = require(script.Parent.PlayerDataService)
local Telemetry = require(script.Parent.Telemetry)

local HubPlaza = {}

-- Bumping this rebuilds the plaza on the next server start, the same shape as LeaderboardService's
-- BOARD_VERSION, EventService's SIGN_VERSION and ZoneBuilder's BUILD_VERSION. Editing anything
-- below WITHOUT moving this number is a silent no-op on a world that already has a plaza in it.
-- 3: the photo spot gained the prompt it had been missing since it was built (17.3).
-- 4: the Exhibit -- fourteen locked-but-visible skins flanking the walk from the spawn (26.5).
local PLAZA_VERSION = 4

-- What the first photo pays, once per save, ever. Diamonds rather than DNA because DNA is
-- stage-scaled and a fixed figure means nothing across twenty zones -- the same reasoning the
-- Robux products and the codes table already use. 25 is one diamond upgrade's base price, i.e.
-- enough to be worth walking onto the pad for and nowhere near enough to be a reason to.
local PHOTO_REWARD_DIAMONDS = 25

-- ============================================================================
-- GEOMETRY
-- ============================================================================
-- The deck. Chosen to reach every anchor: the leaderboards at x = -130 (z 140..280), the #1 statue
-- on its plinth at (-130, 95), the event board at x = 150, the Splicer at roughly x = 94, and the
-- spawn at z = 366 -- and to stop short of both the terrace band (|x| > 200) and the rebirth plaza
-- (x 225..375). The south edge went 96 -> 80 for the statue alone: at 96 its plinth stood ONE stud
-- off the pavement, which is the sort of near-miss that only ever shows up in a measurement.
local DECK_X = 344            -- x -172..172
local DECK_Z = 336            -- z 80..416
local DECK_CZ = 248

-- Every plane the plaza draws on, all distinct, all above the 0.95 ground-patch ceiling derived in
-- the header. `BANDX_TOP` is the one that is not merely tidiness: the cross bands genuinely CROSS
-- the long ones, so they cannot share the inlay plane -- see `buildDeck`.
local KERB_TOP  = 0.66
local DECK_TOP  = 1.04
local INLAY_TOP = 1.14
local BANDX_TOP = 1.18

-- Half-width of the strip that has to stay walkable. The street furniture already occupies
-- |x| < 40; this is the clear lane down the middle of it.
local CORRIDOR_HALF = 30

-- Anything whose world AABB tops out below this is floor, not an obstruction. It has to sit ABOVE
-- the deck (or every piece would think it was standing on something) and above the ground-patch
-- ceiling of 0.95, and below the shortest real prop -- the smallest GroundRock measured here tops
-- out at 1.53. A lamp plinth occupies DECK_TOP..DECK_TOP+1.6, so a boulder inside that band would
-- come through the plinth rather than stand beside it.
local GROUND_CLEAR = 1.4

local SPAWN_POS = Vector3.new(0, 0, 366)     -- ZoneBuilder's one SpawnLocation
local MEDALLION_POS = Vector3.new(0, 0, 267) -- the gap in the street fence, measured

-- ============================================================================
-- PALETTE
-- ============================================================================
-- Warm stone against Forest's bright green lawn, and a dark kerb around all of it. The two rules
-- the world look pass paid for both apply: the outline comes FIRST, and it only works if the mass
-- inside it is bright. The accents are the Splicer's own violet and cyan, so the centrepiece reads
-- as belonging to the floor it stands on rather than as a machine parked on a field.
--
-- THE FIRST CUT WAS TOO PALE AND THE SCREENSHOT IS THE ONLY THING THAT SAID SO. Stone at
-- (232, 224, 206) is a perfectly reasonable warm off-white on paper; under Forest's very bright
-- key light a 344 x 336 sheet of it clips to flat white and the plaza read as a frozen lake, with
-- the inlay one shade under it invisible. The rule the world look pass wrote down is that the LIGHT
-- decides, not the paint -- so the whole ramp came down about 20 points of value and the spread
-- between its three tones was widened, which is what makes a pattern survive being lit.
-- It took TWO steps down, photographed each time: at (212, 199, 174) the inlay finally read but the
-- field was still washing out, so the authored value and the rendered one are roughly 40 points
-- apart here. Do not "correct" these numbers back toward what looks like stone in a colour picker.
-- ===== A THIRD STEP DOWN, AND A TURN TOWARD THE MAP -- 31.19 =====
-- The note above ends "do not correct these numbers back toward what looks like stone in a colour
-- picker", and this is not that. It is the other half of the same argument. When those two steps
-- were taken the plaza's only neighbour was Forest's green lawn; since 31.10 it butts directly
-- against the VILLAGE MAP, whose ground union is a warm rgb(213, 160, 116), and a capture from the
-- arrival end reads the deck as a sheet of ice laid beside a dirt road. Her words: *"kamen se pod
-- ovim svetlom cita skoro belo pored tople zemlje mape"*.
--
-- So the ramp comes down ONE more step, and -- new, and the reason a step alone would not have
-- done it -- it turns WARM. 196,180,148 has a blue-ward channel spread of 48; the map's dirt has
-- 97. A neutral grey-beige beside a saturated warm brown reads as the cold one whatever its value
-- is, which is why the two previous steps helped and did not fix it. The deck is now warm stone
-- that the road is a darker, redder version of, instead of two unrelated floors meeting at a kerb.
--
-- STONE_DARK WAS THE PURPLE. It is the colour of the inlay BANDS -- the grid across the deck --
-- and 104,92,108 is a mauve: on a near-white field under this key light it renders as distinctly
-- blue-violet stripes, which is *"ljubicaste trake na trgu"* and reads as another game's floor.
-- The Splicer's violet is NOT touched (`ACCENT`, below) -- it is on the medallion, the lamp collars
-- and the frame sheet, where it is the centrepiece's own colour doing the job the palette note
-- describes. It was never the stripes.
--
-- The SPREAD is preserved deliberately: STONE - STONE_MID is (36, 38, 36) before and after, which
-- is the gap the note above says had to be widened to survive being lit.
local OUTLINE    = Color3.fromRGB(26, 22, 42)     -- near-black, never pure black
local STONE      = Color3.fromRGB(178, 152, 116)  -- the deck: the bright mass, warm
local STONE_MID  = Color3.fromRGB(142, 114, 80)   -- inlay bands and the perimeter frame
local STONE_DARK = Color3.fromRGB(104, 76, 52)    -- the deck grid: earth, not mauve
local ACCENT     = Color3.fromRGB(146, 116, 240)  -- Splicer violet
local ACCENT2    = Color3.fromRGB(90, 240, 255)   -- Splicer cyan
local LAMP_GLOW  = Color3.fromRGB(255, 236, 176)
local GOLD       = UITheme.Color.Gold

local ARENA = GameConfig.EventArena
local ARENA_ACCENT = ARENA.accentColor            -- rgb(255, 96, 72)

local plazaModel = nil

-- ============================================================================
-- PART VOCABULARY
-- ============================================================================
-- A local copy rather than a require of ZoneBuilder's, for the reason RebirthShrine and
-- SplicerService both give for having their own: that module is thousands of lines and rebuilds
-- tens of thousands of parts behind a version stamp of its own. This one builds about a hundred.
local function newPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	for k, v in pairs(props) do
		p[k] = v
	end
	return p
end

-- A flat slab whose TOP is the number you care about. Every paving layer is stated this way and
-- grown downward from its own top face to a common buried bottom, so no two of them can ever share
-- a horizontal plane -- the same trick the arena floor discs use, and for the same reason.
local function pave(model, name, cx, cz, sx, sz, top, colour)
	local bottom = -1.2
	local thickness = top - bottom
	return newPart({
		Name = name,
		Size = Vector3.new(sx, thickness, sz),
		Position = Vector3.new(cx, top - thickness * 0.5, cz),
		Color = colour,
		CanCollide = true,
		Parent = model,
	})
end

-- Same, round. Orientation (0, 0, 90) stands a cylinder on its flat face.
local function paveDisc(model, name, centre, radius, top, colour)
	local bottom = -1.2
	local thickness = top - bottom
	return newPart({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thickness, radius * 2, radius * 2),
		Orientation = Vector3.new(0, 0, 90),
		Position = Vector3.new(centre.X, top - thickness * 0.5, centre.Z),
		Color = colour,
		CanCollide = true,
		Parent = model,
	})
end

-- ============================================================================
-- FINDING GROUND NOTHING IS STANDING ON
-- ============================================================================
-- The world-space height of a part's top, computed from its own rotation. `Position.Y + Size.Y/2`
-- is only correct for an unrotated part, and Forest is full of rotated rubble.
local function worldTop(part)
	local cf = part.CFrame
	local sz = part.Size
	local halfY = 0.5 * (
		math.abs(cf.RightVector.Y) * sz.X +
		math.abs(cf.UpVector.Y) * sz.Y +
		math.abs(cf.LookVector.Y) * sz.Z
	)
	return cf.Position.Y + halfY
end

local function queryParams()
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.MaxParts = 400
	local exclude = { plazaModel }
	for _, name in ipairs({ "Creatures", "EquippedPets", "Eggs", "Bosses" }) do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(exclude, folder)
		end
	end
	-- a player standing on the spot is not a reason to move a lamp post
	for _, plr in ipairs(game:GetService("Players"):GetPlayers()) do
		if plr.Character then
			table.insert(exclude, plr.Character)
		end
	end
	params.FilterDescendantsInstances = exclude
	return params
end

-- True when anything solid and taller than the floor stands inside `footprint` at `centre`.
local function occupied(centre, footprint)
	local box = CFrame.new(centre.X, footprint.Y * 0.5, centre.Z)
	local hits = workspace:GetPartBoundsInBox(box, footprint, queryParams())
	for _, part in ipairs(hits) do
		if part.CanCollide and worldTop(part) > GROUND_CLEAR then
			return true
		end
	end
	return false
end

-- The offsets a blocked piece is allowed to slide through, nearest first. Deliberately short and
-- deliberately local: a lamp that has moved 60 studs is no longer the lamp that was designed, and
-- the honest answer at that point is not to build it.
local NUDGE = {
	Vector3.new(0, 0, 0),
	Vector3.new(0, 0, 14), Vector3.new(0, 0, -14),
	Vector3.new(14, 0, 0), Vector3.new(-14, 0, 0),
	Vector3.new(0, 0, 28), Vector3.new(0, 0, -28),
	Vector3.new(24, 0, 0), Vector3.new(-24, 0, 0),
	Vector3.new(20, 0, 20), Vector3.new(-20, 0, 20),
	Vector3.new(20, 0, -20), Vector3.new(-20, 0, -20),
}

local skipped = 0
local moved = 0

-- The one gate every standing piece goes through. Returns a position, or nil when there is nowhere
-- honest to put it -- callers must handle nil, because a lamp inside a leaderboard is worse than no
-- lamp, and both are far better than a build that stops halfway.
local function standAt(preferred, footprint)
	for _, offset in ipairs(NUDGE) do
		local centre = preferred + offset
		local halfX = footprint.X * 0.5
		-- CONSTRAINT 1: never in the walking lane, whatever the search says about the ground
		if math.abs(centre.X) - halfX >= CORRIDOR_HALF then
			if not occupied(centre, footprint) then
				if offset.Magnitude > 0.5 then
					moved = moved + 1
				end
				return centre
			end
		end
	end
	skipped = skipped + 1
	return nil
end

-- ============================================================================
-- THE FLOOR
-- ============================================================================
local function buildDeck(model)
	-- The kerb reads as the deck's outline, and it is the one shape that works from above: bigger
	-- in X and Z but with its top BELOW the deck's, so what you see is a dark rim around a bright
	-- field. A shell that is bigger on all three axes encloses the body instead of outlining it --
	-- that is what made the Splicer a black blob for two builds.
	pave(model, "Kerb", 0, DECK_CZ, DECK_X + 12, DECK_Z + 12, KERB_TOP, OUTLINE)
	pave(model, "Deck", 0, DECK_CZ, DECK_X, DECK_Z, DECK_TOP, STONE)

	-- THE PERIMETER FRAME, which replaced four corner pads. The pads were meant to stop a
	-- 344 x 336 rectangle reading as one enormous blank slab and they did not: four squares in the
	-- far corners of a field that big are four separate objects, not a composition. A drawn border
	-- is one shape, it states the whole edge at once, and it is what a paved square actually has.
	--
	-- EVERY BAND HERE BUTTS, NOTHING OVERLAPS, and that is not tidiness -- these are all on the same
	-- plane, so two of them crossing would be a pair of coplanar faces, which is the terrace shimmer
	-- again. The X bands run the full inset width and the Z bands stop short by their own width.
	local hx, hz = DECK_X * 0.5, DECK_Z * 0.5
	local FRAME_INSET, FRAME_W = 16, 10
	local frameMid = FRAME_INSET + FRAME_W * 0.5
	for _, sz in ipairs({ -1, 1 }) do
		pave(model, "FrameX", 0, DECK_CZ + sz * (hz - frameMid), DECK_X - FRAME_INSET * 2, FRAME_W, INLAY_TOP, STONE_MID)
	end
	for _, sx in ipairs({ -1, 1 }) do
		pave(model, "FrameZ", sx * (hx - frameMid), DECK_CZ, FRAME_W,
			DECK_Z - (FRAME_INSET + FRAME_W) * 2, INLAY_TOP, STONE_MID)
	end

	-- Two bands down Z frame the boulevard the street furniture already stands on. The cross bands
	-- run from x = 34 (clear of the corridor and of the street's own planters) outward in two
	-- separate segments each, so the pattern reads as a square rather than as a grid, and nothing
	-- crosses the walking lane. Both stop clear of the frame, for the reason above.
	--
	-- THE CROSS BANDS GET THEIR OWN PLANE, AND THE "nothing overlaps" CLAIM ABOVE IS WHY THEY NEED
	-- ONE. It is true of the frame, whose four bands butt exactly at their corners -- and it was
	-- asserted rather than checked for these, which do not butt: BandX spans x 34..140 while BandZ
	-- stands at x = +-58, so the two cross, four times, in a 7 x 7 square each. Measured on the live
	-- build both tops read 0.9000, delta 0.0000 -- the terrace shimmer exactly, in the file that
	-- documents it. Draw order settles it (ZoneBuilder's own patch stack works this way): the cross
	-- band is 0.04 over the long one, so it reads as laid ON it rather than arguing with it.
	local BAND_IN, BAND_OUT = 34, 140
	for _, sx in ipairs({ -1, 1 }) do
		pave(model, "BandZ", sx * 58, DECK_CZ, 7, DECK_Z - (FRAME_INSET + FRAME_W) * 2 - 32, INLAY_TOP, STONE_DARK)
		for _, cz in ipairs({ 152, 360 }) do
			pave(model, "BandX", sx * (BAND_IN + BAND_OUT) * 0.5, cz, BAND_OUT - BAND_IN, 7, BANDX_TOP, STONE_DARK)
		end
	end

	-- The medallion sits in the measured gap in the street fence (z 241..290 carries no fence run),
	-- and its radius keeps it inside the fence line at x = +-24. It is flush, so the corridor rule
	-- does not apply to it: you walk over a floor, you walk around a lamp post.
	paveDisc(model, "Medallion", MEDALLION_POS, 21, 1.24, STONE_MID)
	paveDisc(model, "MedallionRing", MEDALLION_POS, 14, 1.31, ACCENT)
	paveDisc(model, "MedallionEye", MEDALLION_POS, 6, 1.38, ACCENT2)

	-- The arrival dais. "Spawn lands on pavement" is this row's own check, and the SpawnLocation
	-- ZoneBuilder places has its top face at y = 1.5 -- so the dais stops well under it and the
	-- spawn pad reads as the centre stone rather than fighting it for the same plane.
	paveDisc(model, "ArrivalDais", SPAWN_POS, 21, 1.26, STONE_MID)
	paveDisc(model, "ArrivalDaisEye", SPAWN_POS, 13, 1.33, ACCENT)
end

-- ============================================================================
-- LAMPS
-- ============================================================================
-- ZoneBuilder already lamps the street at x = +-32 every 30 studs, so these are not a second row
-- of the same thing: they mark the PLAZA's own outer rim, which had nothing on it at all.
local LAMP_FOOT = Vector3.new(10, 26, 10)

local function buildLamp(model, centre)
	local pos = standAt(centre, LAMP_FOOT)
	if not pos then return nil end

	local base = newPart({
		Name = "LampBase", Size = Vector3.new(7, 1.6, 7),
		Position = Vector3.new(pos.X, DECK_TOP + 0.8, pos.Z),
		Color = OUTLINE, CanCollide = true, Parent = model,
	})
	newPart({
		Name = "LampPlinth", Size = Vector3.new(5, 1.2, 5),
		Position = Vector3.new(pos.X, DECK_TOP + 2.0, pos.Z),
		Color = STONE_MID, CanCollide = true, Parent = model,
	})
	newPart({
		Name = "LampPost", Size = Vector3.new(1.8, 20, 1.8),
		Position = Vector3.new(pos.X, DECK_TOP + 12.6, pos.Z),
		Color = OUTLINE, CanCollide = true, Parent = model,
	})
	newPart({
		Name = "LampCollar", Size = Vector3.new(3.4, 1.6, 3.4),
		Position = Vector3.new(pos.X, DECK_TOP + 22.4, pos.Z),
		Color = ACCENT, CanCollide = false, Parent = model,
	})
	local bulb = newPart({
		Name = "LampBulb", Shape = Enum.PartType.Ball, Size = Vector3.new(4.6, 4.6, 4.6),
		Position = Vector3.new(pos.X, DECK_TOP + 25.2, pos.Z),
		Color = LAMP_GLOW, Material = Enum.Material.Neon, CanCollide = false, Parent = model,
	})
	newPart({
		Name = "LampCap", Size = Vector3.new(6, 1.4, 6),
		Position = Vector3.new(pos.X, DECK_TOP + 28.2, pos.Z),
		Color = OUTLINE, CanCollide = false, Parent = model,
	})

	local light = Instance.new("PointLight")
	light.Color = LAMP_GLOW
	light.Brightness = 1.4
	light.Range = 34
	light.Shadows = false
	light.Parent = bulb

	return base
end

-- ============================================================================
-- BANNERS TOWARD THE COLOSSEUM GATE
-- ============================================================================
-- The gate to the Colosseum is in Forest's +Z wall, directly behind the spawn -- which means a
-- player who lands here is FACING AWAY FROM IT. That is the one thing this dressing is for: the
-- banners are the Colosseum's own red, they stand only on the north half of the deck, and their
-- cloth faces -Z so it is the first thing in shot when you turn round.
local POLE_FOOT = Vector3.new(9, 32, 9)

local function buildBannerPole(model, centre)
	local pos = standAt(centre, POLE_FOOT)
	if not pos then return nil end

	newPart({
		Name = "PoleBase", Size = Vector3.new(6, 1.8, 6),
		Position = Vector3.new(pos.X, DECK_TOP + 0.9, pos.Z),
		Color = OUTLINE, CanCollide = true, Parent = model,
	})
	newPart({
		Name = "Pole", Size = Vector3.new(1.7, 30, 1.7),
		Position = Vector3.new(pos.X, DECK_TOP + 16.8, pos.Z),
		Color = OUTLINE, CanCollide = true, Parent = model,
	})
	newPart({
		Name = "PoleFinial", Shape = Enum.PartType.Ball, Size = Vector3.new(3.4, 3.4, 3.4),
		Position = Vector3.new(pos.X, DECK_TOP + 33.4, pos.Z),
		Color = GOLD, CanCollide = false, Parent = model,
	})
	-- The cloth hangs on the -Z face of the pole, so the pole is behind it from the walker's side
	-- and the banner is never seen edge-on from the spawn.
	newPart({
		Name = "Banner", Size = Vector3.new(13, 19, 0.9),
		Position = Vector3.new(pos.X, DECK_TOP + 22.0, pos.Z - 1.2),
		Color = ARENA_ACCENT, CanCollide = false, Parent = model,
	})
	newPart({
		Name = "BannerBar", Size = Vector3.new(15, 1.4, 1.6),
		Position = Vector3.new(pos.X, DECK_TOP + 32.2, pos.Z - 1.2),
		Color = OUTLINE, CanCollide = false, Parent = model,
	})
	-- A gold hem rather than a wedge tail. A Wedge would need an orientation nobody can check
	-- without a screenshot, and one flat bar reads as the bottom of a banner from every angle.
	newPart({
		Name = "BannerHem", Size = Vector3.new(13, 1.6, 1.1),
		Position = Vector3.new(pos.X, DECK_TOP + 11.9, pos.Z - 1.2),
		Color = GOLD, CanCollide = false, Parent = model,
	})
	return true
end

-- A signpost that says where the gate goes. A BillboardGui rather than a SurfaceGui because this
-- has to be legible from the spawn pad forty studs away and from any angle -- and it is parented
-- to an ANCHORED part, which is the row's own requirement.
local SIGN_FOOT = Vector3.new(10, 20, 10)

local function buildGateSign(model, centre)
	local pos = standAt(centre, SIGN_FOOT)
	if not pos then return nil end

	newPart({
		Name = "SignBase", Size = Vector3.new(6, 1.6, 6),
		Position = Vector3.new(pos.X, DECK_TOP + 0.8, pos.Z),
		Color = OUTLINE, CanCollide = true, Parent = model,
	})
	local post = newPart({
		Name = "SignPost", Size = Vector3.new(2, 16, 2),
		Position = Vector3.new(pos.X, DECK_TOP + 9.6, pos.Z),
		Color = OUTLINE, CanCollide = true, Parent = model,
	})
	local board = newPart({
		Name = "SignBoard", Size = Vector3.new(19, 8, 1.4),
		Position = Vector3.new(pos.X, DECK_TOP + 19.5, pos.Z),
		Color = ARENA_ACCENT, CanCollide = false, Parent = model,
	})
	newPart({
		Name = "SignBoardLip", Size = Vector3.new(21, 1.6, 2.2),
		Position = Vector3.new(pos.X, DECK_TOP + 15.0, pos.Z),
		Color = OUTLINE, CanCollide = false, Parent = model,
	})

	local gui = Instance.new("BillboardGui")
	gui.Name = "GateSign"
	gui.Size = UDim2.fromScale(26, 9)          -- scale on a BillboardGui is STUDS, not pixels
	gui.StudsOffsetWorldSpace = Vector3.new(0, 8, 0)
	gui.MaxDistance = 260
	gui.AlwaysOnTop = false
	gui.Adornee = board
	gui.Parent = board

	local shell = Instance.new("Frame")
	shell.Size = UDim2.fromScale(1, 1)
	shell.BackgroundColor3 = UITheme.Color.PanelWhite
	shell.BorderSizePixel = 0
	shell.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = shell
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = OUTLINE
	stroke.Parent = shell

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.56)
	title.Position = UDim2.fromScale(0, 0.04)
	title.BackgroundTransparency = 1
	title.Font = UITheme.Font.Display
	title.Text = ARENA.emoji .. "  " .. ARENA.name:upper()
	title.TextColor3 = ARENA_ACCENT
	title.TextScaled = true
	title.Parent = shell

	-- Dark ink on a white sheet needs no stroke, and UITheme's default outline is the same near
	-- black as the glyph -- which renders as a blob. 12.3 and 12.6 both paid for this one twice.
	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.fromScale(1, 0.36)
	sub.Position = UDim2.fromScale(0, 0.58)
	sub.BackgroundTransparency = 1
	sub.Font = UITheme.Font.Body
	sub.Text = "through the gate behind you"
	sub.TextColor3 = Color3.fromRGB(70, 78, 98)
	sub.TextScaled = true
	sub.Parent = shell

	return post
end

-- ============================================================================
-- THE PHOTO SPOT
-- ============================================================================
-- A marked square with a frame standing on its west side, so a player on the pad has the frame
-- behind them and the whole plaza -- boards, machine, banners -- in the shot in front.
local PHOTO_FOOT = Vector3.new(40, 30, 40)

-- `side` is -1 for a frame on the pad's west face and 1 for its east, and it is always the OUTBOARD
-- side: the frame stands between the pad and the edge of the deck, so whoever is on the pad has it
-- at their back and the plaza -- boards, machine, banners -- in front of them. Get this backwards
-- and the photo spot points a camera at the lawn.
local function buildPhotoSpot(model, pos, side)
	pave(model, "PhotoRim", pos.X, pos.Z, 38, 38, 1.28, OUTLINE)
	-- Lighter than the deck, not the same as it: a pad you are meant to stand on has to be findable
	-- from across the plaza, and it is the one place here that wants to be brighter than its floor.
	local pad = pave(model, "PhotoPad", pos.X, pos.Z, 32, 32, 1.42, UITheme.Color.Cream)

	-- ===== 17.3: THE PAD NOW HAS SOMETHING BEHIND IT =====
	--
	-- The report was *"photo spot nista ne radi"* and it was exactly right: this function laid a
	-- rim, a pad, an eye, two posts, a beam, a sheet, a crest and a sign reading PHOTO SPOT, and a
	-- sweep of the whole source tree found no prompt, no `Touched`, no `ClickDetector` and no client
	-- listener for any of them. A sign that names a feature the game does not have is worse than no
	-- sign, because the player goes looking for the thing that does not exist.
	--
	-- A PROMPT RATHER THAN A `Touched`: the pad is 32 studs across and every player crosses this
	-- plaza on the way to the gate, so a touch trigger would fire the camera at people walking past.
	-- The prompt also gives the standard E affordance the rest of this game already uses (the egg
	-- podiums, the potion stalls, the Splicer), which is the answer to "how would anyone know".
	--
	-- `RequiresLineOfSight = false` because the frame's own sheet stands between the pad and most of
	-- the plaza, and the whole camera path lives on the client -- see `PhotoSpot.client`.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PhotoPrompt"
	prompt.ActionText = "Take a photo"
	prompt.ObjectText = "Photo Spot"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	-- Half the pad plus the height of a last-stage body: a 39-stud character standing in the middle
	-- of a 32-stud pad has its root well over 20 studs from the pad's centre.
	prompt.MaxActivationDistance = 46
	prompt.Parent = pad
	pave(model, "PhotoPadEye", pos.X, pos.Z, 14, 14, 1.52, ACCENT2)

	local fx = pos.X + side * 15
	for _, dz in ipairs({ -13, 13 }) do
		newPart({
			Name = "FramePost", Size = Vector3.new(2.6, 24, 2.6),
			Position = Vector3.new(fx, DECK_TOP + 12.6, pos.Z + dz),
			Color = OUTLINE, CanCollide = true, Parent = model,
		})
	end
	newPart({
		Name = "FrameBeam", Size = Vector3.new(2.6, 3, 31),
		Position = Vector3.new(fx, DECK_TOP + 26.1, pos.Z),
		Color = OUTLINE, CanCollide = false, Parent = model,
	})
	newPart({
		Name = "FrameSheet", Size = Vector3.new(1.2, 22, 26),
		Position = Vector3.new(fx - side * 1.4, DECK_TOP + 13.4, pos.Z),
		Color = ACCENT, Transparency = 0.35, CanCollide = false, Parent = model,
	})
	local crest = newPart({
		Name = "FrameCrest", Size = Vector3.new(2.4, 4, 12),
		Position = Vector3.new(fx, DECK_TOP + 29.3, pos.Z),
		Color = GOLD, CanCollide = false, Parent = model,
	})

	local gui = Instance.new("BillboardGui")
	gui.Name = "PhotoSign"
	gui.Size = UDim2.fromScale(22, 7)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
	gui.MaxDistance = 220
	gui.Adornee = crest
	gui.Parent = crest

	local shell = Instance.new("Frame")
	shell.Size = UDim2.fromScale(1, 1)
	shell.BackgroundColor3 = UITheme.Color.PanelWhite
	shell.BorderSizePixel = 0
	shell.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = shell
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = OUTLINE
	stroke.Parent = shell

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 0.86)
	label.Position = UDim2.fromScale(0, 0.07)
	label.BackgroundTransparency = 1
	label.Font = UITheme.Font.Display
	label.Text = "\u{1F4F8}  PHOTO SPOT"
	label.TextColor3 = Color3.fromRGB(70, 78, 98)
	label.TextScaled = true
	label.Parent = shell

	return pos
end

-- ============================================================================
-- THE EXHIBIT (26.5)
-- ============================================================================
-- The owner's instruction, in as many words: "da stoje likovi izlozeni negde na pocetku igre".
-- Two ranks of plinths flanking the walk down from the spawn -- the nine VIP bundles on the east
-- side, the five event skins on the west -- each figure on a stone plinth with a plaque naming what
-- it costs or which ladder pays it out.
--
-- LOCKED-BUT-VISIBLE IS THE WHOLE MECHANISM, and it is the one thing every game in 26's research
-- does with the character you cannot have today. A skin nobody can see is not a goal; a skin
-- standing in the road with a price under it is. So an unowned figure is SILHOUETTED rather than
-- hidden -- same body, same size, same plaque, painted out to a dark slate.
--
-- THE SILHOUETTE IS DRAWN ON THE CLIENT AND HAS TO BE. Ownership differs per player and this model
-- is one shared set of parts, so the server builds every figure in its true colours and
-- `Exhibit.client` paints out the ones the local player does not own. That is also why each stand
-- carries `CharacterKey` and `ExhibitKind` attributes: they are the whole contract between this
-- file and that one.
--
-- THE FIGURE IS THE SAME TEMPLATE THE PLAYER WEARS -- `ReplicatedStorage.Assets.SkinMeshes` --
-- cloned, scaled to a single display height so the rank reads as a rank, and turned by the SAME
-- yaw rule SkinMesh.Apply uses, `FaceFlip` included. Ten of the 214 templates were generated
-- backwards and that attribute is the only record of which; re-deriving the rule here would mean
-- ten statues showing the plaza the back of their heads.
local EXHIBIT_X = 56          -- outside the street furniture (|x| < 40) and inboard of the lamps (84)
local EXHIBIT_Z = 330         -- one plinth south of the banner poles at z = 352
local EXHIBIT_STEP = 24       -- 13-stud plinths, so an 11-stud gap: a colonnade, not a wall
local EXHIBIT_FOOT = Vector3.new(20, 22, 18)
local FIGURE_HEIGHT = 9       -- a stage-1 player is about 6, so a figure looms without being scenery
local PLINTH_TOP = DECK_TOP + 6.5
-- Dead-inward would show the spawn nothing but shoulders; a fifth of a right angle toward the
-- north end means the row is three-quarters-on from the arrival pad and square-on from the walk.
local EXHIBIT_TURN = math.rad(20)

-- Where each rank looks. `side` is the sign of x, and it is also which way the figure faces.
local function exhibitLook(side)
	return Vector3.new(-side * math.cos(EXHIBIT_TURN), 0, math.sin(EXHIBIT_TURN))
end

-- WHERE THE RANKS ACTUALLY STOOD, because the plaza's own searches cannot see each other: nothing
-- is parented into workspace until the end of `build`, so every piece up to now has been AUTHORED
-- not to collide. The photo spot is the one piece whose position is not authored -- its last-resort
-- scan walks x = +-76 with a 40-stud clearance, which reaches the east rank -- so it is given this
-- to read. Deliberately narrower than a general reservation list: PHOTO_FOOT is a clearance rather
-- than a solid, and the four authored photo spots already overlap a lamp's clearance without either
-- of them being wrong.
local exhibitSpots = {}
local function nearExhibit(centre, footprint)
	for _, spot in ipairs(exhibitSpots) do
		if math.abs(centre.X - spot.X) < (footprint.X + EXHIBIT_FOOT.X) * 0.5
			and math.abs(centre.Z - spot.Z) < (footprint.Z + EXHIBIT_FOOT.Z) * 0.5 then
			return true
		end
	end
	return false
end

-- A colour a player can read off a white plaque. The nine VIP discs include a cream (228, 220, 176)
-- and the ladder is free to add another, so the hue is kept and the VALUE is pulled down until it
-- clears the sheet -- the same decision `inkOn` makes inside UITheme, taken here against a fixed
-- white rather than against a caller's fill.
local PLAQUE_INK_MAX = 0.52
local function plaqueInk(colour)
	local lum = UITheme.Luminance(colour)
	if lum <= PLAQUE_INK_MAX then return colour end
	return UITheme.Shade(colour, PLAQUE_INK_MAX / lum - 1)
end

-- A RANK KEEPS ITS RHYTHM, WHICH IS WHY THIS IS NOT JUST `standAt`. The shared gate's nudge list
-- tries z first, and z is the axis the spacing is measured along: measured on the live world, the
-- Forest group chest at (48, 335) blocks the first VIP plinth, `standAt` slid it 14 studs down the
-- rank, and two 13-stud bases 10 studs apart overlapped into one lump of stone. Stepping OUTWARD in
-- x instead keeps every plinth on its own z and costs the rank nothing but a slightly ragged edge.
-- `standAt` is still the floor under it -- it is the piece that owns the corridor rule and the
-- skipped counter, and a plinth with nowhere honest to stand must still not be built.
local RANK_NUDGE = { 0, 12, 24, -10 }
local function standInRank(preferred, side)
	for _, dx in ipairs(RANK_NUDGE) do
		local centre = preferred + Vector3.new(dx * side, 0, 0)
		if math.abs(centre.X) - EXHIBIT_FOOT.X * 0.5 >= CORRIDOR_HALF and not occupied(centre, EXHIBIT_FOOT) then
			if dx ~= 0 then moved = moved + 1 end
			return centre
		end
	end
	return standAt(preferred, EXHIBIT_FOOT)
end

-- A museum label, not a floating billboard. A BillboardGui over a statue's head reads as a HUD
-- element that happens to be in the world -- the signage note this game has paid for twice -- and
-- this one has a real slab to sit on, angled with the figure so the walk sees both square-on.
local function buildPlaque(stand, centre, side, entry, earnLine, tint)
	local look = exhibitLook(side)
	-- CLEAR OF THE PLINTH, WHICH THE FIRST CUT WAS NOT AND ONLY A CAPTURE SAID SO. At 4.9 the slab
	-- was inside the base's own 13-stud footprint: every property read correct, `TextFits` was true,
	-- and the plinth stood in front of the middle third of the label -- the plaque photographed as
	-- "Cybe        un / VIP Pass - R$      ll 9". The offset now clears the base's boundary along
	-- the facing (6.5 / cos 20 = 6.9) with both far corners of a 9-stud slab outside it, and the
	-- bottom edge sits ON the deck so it reads as a planted label rather than a floating card.
	local pos = Vector3.new(centre.X, DECK_TOP + 1.9, centre.Z) + look * 8.4
	local plaque = newPart({
		Name = "Plaque",
		Size = Vector3.new(9.0, 3.8, 0.7),
		CFrame = CFrame.lookAt(pos, pos + look),
		Color = OUTLINE,
		CanCollide = false,
		Parent = stand,
	})

	local gui = Instance.new("SurfaceGui")
	gui.Name = "PlaqueSign"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 48
	-- The plaza is lit by Forest's very bright key light and the plaque faces the walk, not the sky.
	-- LightInfluence 0 is what keeps the ink black instead of a mid grey in its own shadow.
	gui.LightInfluence = 0
	gui.MaxDistance = 250
	gui.Adornee = plaque
	gui.Parent = plaque

	local shell = Instance.new("Frame")
	shell.Name = "Shell"
	shell.Size = UDim2.new(1, -12, 1, -12)
	shell.Position = UDim2.fromOffset(6, 6)
	shell.BackgroundColor3 = UITheme.Color.PanelWhite
	shell.BorderSizePixel = 0
	shell.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = shell

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(1, 0.40)
	title.Position = UDim2.fromScale(0, 0.03)
	title.BackgroundTransparency = 1
	title.Font = UITheme.Font.Display
	title.Text = (entry.emoji or "") .. "  " .. entry.name
	title.TextColor3 = plaqueInk(tint)
	title.TextScaled = true
	title.Parent = shell

	-- Dark ink on a white sheet takes NO stroke. UITheme's outline is the same near-black as the
	-- glyph, so a halo here renders as a blob -- 12.3, 12.6 and 26.3 have each paid for this once.
	local earn = Instance.new("TextLabel")
	earn.Name = "Earn"
	earn.Size = UDim2.fromScale(1, 0.29)
	earn.Position = UDim2.fromScale(0, 0.42)
	earn.BackgroundTransparency = 1
	earn.Font = UITheme.Font.Body
	earn.Text = earnLine
	earn.TextColor3 = Color3.fromRGB(70, 78, 98)
	earn.TextScaled = true
	earn.Parent = shell

	-- Written by the server so a plaque is never blank, and OWNED BY THE CLIENT from its first
	-- DataUpdate: whether this player has it, and for an event skin how long its window has left.
	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.Size = UDim2.fromScale(1, 0.26)
	status.Position = UDim2.fromScale(0, 0.72)
	status.BackgroundTransparency = 1
	status.Font = UITheme.Font.Display
	status.Text = "\u{1F512} LOCKED"
	status.TextColor3 = Color3.fromRGB(126, 134, 156)
	status.TextScaled = true
	status.Parent = shell

	return plaque
end

-- The statue. Returns nil when the template is missing, and the caller then builds no plinth at
-- all: an empty plinth with a price on it is a bug report, where a rank of eight is a rank.
local function buildFigure(stand, key, centre, side)
	local template = SkinMesh.TemplateFor(key)
	if not template then
		warn(("[HubPlaza] no SkinMesh template for '%s' -- exhibit stand skipped"):format(tostring(key)))
		return nil
	end

	local clone = template:Clone()
	local _, rawSize = clone:GetBoundingBox()
	if rawSize.Y > 0.001 then
		-- ScaleTo is ABSOLUTE and the templates are authored at 1, so this is the factor itself.
		clone:ScaleTo(FIGURE_HEIGHT / rawSize.Y)
	end

	local meshCF, size = clone:GetBoundingBox()
	local look = exhibitLook(side)
	-- The same arithmetic as SkinMesh.Apply, and for the same reason: the templates are authored
	-- facing -Z, and the ones that are not carry `FaceFlip`.
	local yaw = math.atan2(-look.X, -look.Z)
	if template:GetAttribute("FaceFlip") then
		yaw = yaw + math.pi
	end
	local localPivot = CFrame.new(meshCF.Position):Inverse() * clone:GetPivot()
	clone:PivotTo(CFrame.new(centre.X, PLINTH_TOP + size.Y * 0.5, centre.Z)
		* CFrame.Angles(0, yaw, 0) * localPivot)

	for _, part in ipairs(clone:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			-- NOT collidable and NOT queryable: the plinth under it is the obstruction, and a statue
			-- a later service's box query could see would push that service's own piece away for a
			-- shape nothing can walk into.
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
		end
	end

	clone.Name = "Figure"
	clone.Parent = stand
	return clone
end

-- One plinth, one figure, one plaque. `entry` is the GameConfig character row; `kind` is what the
-- client branches on.
local function buildStand(parent, preferred, side, entry, kind, earnLine, tint)
	local pos = standInRank(preferred, side)
	if not pos then return nil end

	local stand = Instance.new("Model")
	stand.Name = "Stand_" .. entry.key
	stand:SetAttribute("CharacterKey", entry.key)
	stand:SetAttribute("ExhibitKind", kind)
	stand.Parent = parent

	if not buildFigure(stand, entry.key, pos, side) then
		stand:Destroy()
		return nil
	end

	-- TALLER THAN IT IS WIDE, and the first cut was the other way round: a 13-stud base under a
	-- 3-stud column read as a low table with somebody standing on it, which is what the first
	-- capture showed. The taper is what makes it a plinth -- 11.6 down at the deck, 8.8 through the
	-- shaft, and the coloured cap back out to 10.2 so it reads as a lid rather than as a tabletop.
	newPart({
		Name = "Base", Size = Vector3.new(11.6, 1.4, 11.6),
		Position = Vector3.new(pos.X, DECK_TOP + 0.7, pos.Z),
		Color = OUTLINE, CanCollide = true, Parent = stand,
	})
	newPart({
		Name = "Column", Size = Vector3.new(8.8, 4.2, 8.8),
		Position = Vector3.new(pos.X, DECK_TOP + 3.5, pos.Z),
		Color = STONE_MID, CanCollide = true, Parent = stand,
	})
	-- The one coloured piece of the plinth, and it is what tells the two ranks apart from the far
	-- end of the plaza: gold for the pass, the event's own colour for an event skin.
	newPart({
		Name = "Cap", Size = Vector3.new(10.2, 0.9, 10.2),
		Position = Vector3.new(pos.X, DECK_TOP + 6.05, pos.Z),
		Color = tint, CanCollide = true, Parent = stand,
	})

	buildPlaque(stand, pos, side, entry, earnLine, tint)
	return pos
end

-- The two ranks, ordered the way they are walked: the VIP row escalates away from the spawn, so
-- the top of the wardrobe stands at the far end of the avenue. Returns the count and the footprints
-- it took, which is what stops the photo spot's last-resort scan landing on top of one.
local function buildExhibit(model)
	local exhibit = Instance.new("Model")
	exhibit.Name = "Exhibit"
	exhibit.Parent = model

	local spots, built = {}, 0

	local pass = GameConfig.GetGamePass("VIP")
	-- READ, NEVER WRITTEN: a tenth bundle or a re-price needs no edit in this file. `passId <= 0`
	-- is the same guard 26.4's Journal door uses -- an unset pass advertises no price.
	local vipLine = (pass and pass.passId and pass.passId > 0)
		and ("VIP Pass \u{2022} R$ %d for all %d"):format(pass.price, #GameConfig.VipCharacters)
		or "VIP Pass"
	for index, entry in ipairs(GameConfig.VipCharacters) do
		local preferred = Vector3.new(EXHIBIT_X, 0, EXHIBIT_Z - (index - 1) * EXHIBIT_STEP)
		local pos = buildStand(exhibit, preferred, 1, entry, "vip", vipLine, GOLD)
		if pos then
			built += 1
			table.insert(spots, pos)
		end
	end

	for index, entry in ipairs(GameConfig.EventCharacters) do
		local event = GameConfig.GetEvent(entry.event)
		local rungs = #GameConfig.GetEventQuests(entry.event)
		-- The ladder is COUNTED, not quoted: 26.1 pays the skin on the last rung, and a fifth rung
		-- must not have to be remembered in this file.
		-- SHORT ENOUGH TO STAY ON ONE LINE, which is a capture finding rather than a preference:
		-- "finish its 4-step ladder" wrapped to two rows inside a TextScaled label, and a label that
		-- wraps shrinks -- the event row came out about half the height of the VIP row beside it.
		local line = rungs > 0
			and ("%s \u{2022} %d-step ladder"):format(event and event.name or "Event", rungs)
			or ("%s \u{2022} event exclusive"):format(event and event.name or "Event")
		local preferred = Vector3.new(-EXHIBIT_X, 0, EXHIBIT_Z - (index - 1) * EXHIBIT_STEP)
		local pos = buildStand(exhibit, preferred, -1, entry, "event", line, entry.color)
		if pos then
			built += 1
			table.insert(spots, pos)
		end
	end

	return built, spots
end

-- ============================================================================
-- THE BUILD
-- ============================================================================
-- Where each standing piece WANTS to be. Every one of these is a preference, not a placement --
-- `standAt` is what decides, against the world as it actually is at boot.
--
-- THE PREFERENCES ARE SYMMETRIC ON PURPOSE, AND THAT COST A MEASUREMENT PASS. The first cut put
-- the lamps on the deck's outer rim at x = +-158 and let `standAt` sort it out; it did, and the
-- result was a row with two holes and four pieces nudged to four different offsets, because
-- Forest's north-west and east rims carry a 100-stud IDOL PAD each and its own trees and crates.
-- A search is the right safety net and the wrong way to choose a composition: an avenue whose
-- spacing is decided by whichever prop happened to be nearest reads as an accident. So every pair
-- below was probed at the SAME z on both sides against the live world first, and `standAt` is left
-- as what it should be -- the thing that catches a prop that moved since.
local LAMP_SPOTS = {
	Vector3.new(-84, 0, 112), Vector3.new(84, 0, 112),
	Vector3.new(-84, 0, 208), Vector3.new(84, 0, 208),
	Vector3.new(-84, 0, 256), Vector3.new(84, 0, 256),
	Vector3.new(-84, 0, 364), Vector3.new(84, 0, 364),
}

-- Nearer the axis than the lamps, because these frame the WALK to the gate rather than the deck.
local BANNER_SPOTS = {
	Vector3.new(-62, 0, 352), Vector3.new(62, 0, 352),
	Vector3.new(-62, 0, 376), Vector3.new(62, 0, 376),
	Vector3.new(-62, 0, 400), Vector3.new(62, 0, 400),
}

local GATE_SIGN_SPOTS = {
	Vector3.new(-44, 0, 404), Vector3.new(44, 0, 404),
}

-- THE PHOTO SPOT IS THE ONE PIECE THAT MAY NOT BE SKIPPED, AND THE FIRST BUILD SKIPPED IT.
-- Everything else here comes in pairs, so a missing lamp is a gap in a row of eight; the photo spot
-- is a feature of the plaza and there is either one or there is not. It had a single preference,
-- (-104, 344), and on the very first live build every one of `standAt`'s thirteen offsets was
-- refused -- a generated `ForestTree` 28 studs across at (-110, 357) covers the preference and
-- reaches past the +-28 the nudge list can travel. That tree is `math.random`-placed, so this was
-- never "a bad coordinate", it was a coordinate whose luck is re-rolled on every world rebuild.
--
-- So the composition is a LIST rather than a point, and there is a floor under the list. The four
-- authored spots are real choices, mirrored either side of the boulevard at the plaza's two open
-- quarters; the scan underneath them is not a choice at all, it is the promise that the feature
-- exists on a world where all four are unlucky. Sign of x picks the outboard side for the frame.
local PHOTO_SPOTS = {
	Vector3.new(-104, 0, 344),
	Vector3.new(104, 0, 344),
	Vector3.new(-104, 0, 168),
	Vector3.new(104, 0, 168),
}

-- Last resort. Walks the deck from the middle outward and takes the first clear pad, staying off the
-- corridor, off the frame border and off the two discs. Nearest-to-the-spawn first, because a photo
-- spot nobody walks past is only technically built.
local function scanForPhotoSpot()
	for _, z in ipairs({ 344, 312, 376, 280, 200, 168, 232, 136 }) do
		for _, x in ipairs({ -104, 104, -76, 76, -132, 132 }) do
			local centre = Vector3.new(x, 0, z)
			if math.abs(x) - PHOTO_FOOT.X * 0.5 >= CORRIDOR_HALF
				and not nearExhibit(centre, PHOTO_FOOT)
				and not occupied(centre, PHOTO_FOOT) then
				return centre
			end
		end
	end
	return nil
end

local function placePhotoSpot(model)
	-- A refused candidate is not a skipped piece -- there are four of them and only one spot is
	-- wanted -- so the counter the log reports is held still across the attempts. Without this the
	-- build line reads "3 skipped" on a plaza that has its photo spot.
	local before = skipped
	for _, spot in ipairs(PHOTO_SPOTS) do
		local pos = standAt(spot, PHOTO_FOOT)
		if pos and nearExhibit(pos, PHOTO_FOOT) then pos = nil end
		if pos then
			skipped = before
			buildPhotoSpot(model, pos, pos.X < 0 and -1 or 1)
			return pos
		end
	end
	skipped = before
	local pos = scanForPhotoSpot()
	if pos then
		buildPhotoSpot(model, pos, pos.X < 0 and -1 or 1)
		return pos
	end
	return nil
end

local function build()
	local existing = workspace:FindFirstChild("HubPlaza")
	if existing then
		-- IDEMPOTENT BY REPLACEMENT, not by skipping. A half-built plaza from an interrupted run
		-- would otherwise survive forever behind an "already there" check -- the failure mode that
		-- left a zone permanently truncated once already.
		if existing:GetAttribute("PlazaVersion") == PLAZA_VERSION then
			return existing
		end
		existing:Destroy()
	end

	skipped = 0
	moved = 0

	local model = Instance.new("Model")
	model.Name = "HubPlaza"
	plazaModel = model

	buildDeck(model)

	-- The model is parented to workspace at the very END of this function, so every search below
	-- runs against a world that does not yet contain any of this -- no self-blocking, and no need
	-- for the exclusion list to carry parts that are not in the datamodel yet. (The list still
	-- carries the model, because a REBUILD destroys the old one first and the destroy is not
	-- guaranteed to have been processed by the time the first query runs.)
	local lamps = 0
	for _, spot in ipairs(LAMP_SPOTS) do
		if buildLamp(model, spot) then lamps = lamps + 1 end
	end

	local banners = 0
	for _, spot in ipairs(BANNER_SPOTS) do
		if buildBannerPole(model, spot) then banners = banners + 1 end
	end

	local signs = 0
	for _, spot in ipairs(GATE_SIGN_SPOTS) do
		if buildGateSign(model, spot) then signs = signs + 1 end
	end

	-- Before the photo spot, because the photo spot is the only piece here whose position is
	-- not authored and it is the one that has to give way.
	local figures, spots = buildExhibit(model)
	exhibitSpots = spots

	local photo = placePhotoSpot(model)

	model:SetAttribute("PlazaVersion", PLAZA_VERSION)
	model.Parent = workspace
	-- Persistent, so the floor under a player's feet does not stream out when they walk to the far
	-- end of it. Set on the Model rather than by adding names to ZoneBuilder's ALWAYS_LOADED list,
	-- which is the whole point of building this outside that file.
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)

	print(("[HubPlaza] built v%d: %d parts, %d lamps, %d banners, %d gate signs, %d/%d exhibit figures, photo spot %s (%d pieces nudged, %d skipped)")
		:format(PLAZA_VERSION, #model:GetDescendants(), lamps, banners, signs,
			figures, #GameConfig.VipCharacters + #GameConfig.EventCharacters,
			photo and ("at %d,%d"):format(photo.X, photo.Z) or "SKIPPED", moved, skipped))

	return model
end

-- ============================================================================
-- THE PHOTO ITSELF (17.3)
-- ============================================================================
-- The camera work is entirely on the client -- posing a camera, hiding the HUD and drawing a frame
-- are all local, and a server that took part in any of it would only be adding a round trip to
-- something that has to feel instant. What the server owns is the one thing a client may never be
-- trusted with: the payout.
--
-- ONE REWARD, ONCE, FOREVER. `data.PhotoTaken` is a new save field whose default is `false`, which
-- `Load`'s generic backfill hands to every existing save -- and unlike 6.3's `TutorialDone` this one
-- needs no repair beside it, because "has not happened yet" is true for everybody: nobody has ever
-- been able to take a photo. A rebirth does not clear it either; it is a first-time-ever gift, not
-- a per-run one.
--
-- STAMPED BEFORE THE GRANT, WITH NO YIELD BETWEEN, exactly as CodesService and the free spin do.
-- The prompt is a client-fired remote, so two Es half a frame apart are two calls into this
-- function, and the gap between "read the flag" and "write the flag" is the whole exploit.
local function grantPhotoReward(player)
	local data = PlayerDataService.Get(player)
	if not data then return end
	if data.PhotoTaken then return end

	data.PhotoTaken = true

	data.Diamonds = (data.Diamonds or 0) + PHOTO_REWARD_DIAMONDS
	Telemetry.Economy(player, "Source", Telemetry.Currency.Diamonds, PHOTO_REWARD_DIAMONDS,
		data.Diamonds, Telemetry.Tx.TimedReward, "photoPad")
	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.PushToClient(player)
	RS.Remotes.Notify:FireClient(player, {
		kind = "reward",
		message = ("\u{1F4F8} Say cheese!\n+%d \u{1F48E} for your first photo"):format(PHOTO_REWARD_DIAMONDS),
		color = GameConfig.GetRarity("Epic").color,
	})
end

function HubPlaza.Init()
	build()

	-- Find-or-create, the shape every service here uses: ServerMain's boot order is not something
	-- this file should depend on for a remote it owns.
	local remotes = RS:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = RS
	end
	local taken = remotes:FindFirstChild("PhotoTaken")
	if not taken then
		taken = Instance.new("RemoteEvent")
		taken.Name = "PhotoTaken"
		taken.Parent = remotes
	end
	-- No payload is read at all. The client is saying "I finished a photo", nothing more -- there is
	-- no number, no position and no id here that a crafted call could bend, and the flag on the save
	-- is what stops it being worth firing twice.
	taken.OnServerEvent:Connect(function(player)
		grantPhotoReward(player)
	end)
end

-- Exposed for probes: the plaza's own numbers, so a check does not have to re-derive them.
HubPlaza.Bounds = {
	minX = -DECK_X * 0.5, maxX = DECK_X * 0.5,
	minZ = DECK_CZ - DECK_Z * 0.5, maxZ = DECK_CZ + DECK_Z * 0.5,
	deckTop = DECK_TOP,
	corridorHalf = CORRIDOR_HALF,
	version = PLAZA_VERSION,
}

return HubPlaza
