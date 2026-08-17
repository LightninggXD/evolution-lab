-- ScatterKit -- where a prop may stand, and the ground it takes when it does.
--
-- One question, asked ninety-odd times per zone: give me a point on this platform that is not in
-- the walkway, not in either gate mouth, not on the boss's dais, not in the middle where the pet
-- shop is, and not inside anything that has already been put down. `scatterPoint` answers it and
-- `reserveScatter` is how the answer stays true for the next caller.
--
-- WHY THIS IS NOT IN `ZoneKit`: it has STATE. `ZoneKit` is a vocabulary -- what a part is made of,
-- what a sign looks like, how big the platform is -- and it is stateless but for the placement
-- frame. `scatterBlocks` is a live table of ground already claimed, cleared once per zone and
-- appended to by every prop big enough that you have to walk around it. "Who cleared this table,
-- and when" is a question worth being able to answer in one file.
--
-- THE OWNER OF THE CLEAR IS STILL `ZoneBuilder`. `addGroundDetail` is the first thing built on a
-- zone's ground and it calls `ScatterKit.clearReservations()` there, exactly where it used to call
-- `table.clear(scatterBlocks)`. The scope the table belongs to did not change; only the file did.
--
-- WHAT THE OLD DECLARATION SITE WAS APOLOGISING FOR, kept because it is the trap and not the fix:
--
--   > Ground already claimed by something big, in WORLD coordinates. See the longer note further
--   > down, beside scatterPoint, for what this is for. Declared here rather than there because the
--   > props that register with it are built from this point in the file onwards.
--
-- That is a `local`'s line number leaking into the design: the table sat a thousand lines above
-- the comment that explained it, in the middle of an unrelated section, because Lua binds an
-- upvalue where a function is WRITTEN. Behind a require there is no such line and no such
-- constraint -- the same thing the village palette's move bought in 18.10.
--
-- WHO MAY REQUIRE IT: any server script placing props on a zone platform. `ZoneBuilder` today.
-- Anything that starts calling `scatterPoint` also inherits `clearReservations`, and the zone loop
-- is the only place that may call it.
--
-- Where the rest of the world is built: `docs/CODEMAP.md`, `docs/SPLIT.md` §6.

local RS = game:GetService("ReplicatedStorage")
local GameConfig = require(RS.Modules.GameConfig)

-- THE VALLEY FLOOR, not the whole platform. The outer band beyond this is terraced into cliffs
-- and waterfalls (see buildTerrain), and every scattered prop in the game is placed at y = 0 with
-- no idea what the ground under it is doing -- so anything dropped out there would be buried in a
-- terrace or left standing in mid-air. Props keep to the flat middle; the sides become scenery.
-- 350, not 400: the pool at the cliff foot has its inner rim at x = 355.5 (it was 363 before 11.26
-- moved the pool four studs off the cliff foot), and at 400 the scatter was dropping trees into the
-- water. The number that matters is the POOL's edge, not the terrace's -- measure against the
-- innermost thing terrain builds, never against the band.
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

-- ===== THE RESERVATION TABLE =====
--
-- World coordinates, so an entry left over from the previous zone could never match anything in
-- this one anyway; the clear is for the table's size, not for correctness.
local scatterBlocks = {}

local function reserveScatter(x, z, radius)
	scatterBlocks[#scatterBlocks + 1] = { x = x, z = z, r = radius }
end

-- Called once per zone, by `addGroundDetail`, which is the first thing built on a zone's ground.
-- It is a verb rather than an exported table for one reason: an exported `scatterBlocks` could be
-- cleared by anybody, and the bug this system was built to fix (11.27) was precisely that the
-- clear happened at the wrong point in the build.
local function clearReservations()
	table.clear(scatterBlocks)
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
-- Cleared once per zone, by `clearReservations` at the top of addGroundDetail -- which is the first
-- thing the zone loop builds on the ground. Entries are world-space, so a stale one from the
-- previous zone could never match anyway; the clear is for the table's size, not for correctness.
--
-- IT USED TO BE DECLARED A THOUSAND LINES ABOVE THIS COMMENT, next to addGroundDetail, because a
-- `local` is only in scope below its own line and the crate and coin scatter run far earlier in
-- that file. Behind a require there is no such line. The table is at the top of this one, where it
-- belongs, and the note the old site carried is quoted in the header.

-- ===== THE RESERVATION SYSTEM EXISTED AND ALMOST NOTHING USED IT (11.27) =====
--
-- Counted: 88 calls to this function in the file, NINE of which pass a `halfSize`. Seventy of the
-- remaining seventy-nine are in `decorationBuilders`, i.e. every zone's signature props -- the
-- cacti, the dunes, the crystal clusters, the pottery, the lava vents. They all look like
-- `scatterPoint(cx, 200, 250)`: no size, so the clearance tests are on a dimensionless point, and
-- no `reserveScatter` afterwards, so the ground they take stays advertised as empty and the next
-- call happily picks it again. Measured on a fresh build: 621 props across the twenty zones with
-- their CENTRE inside another solid prop.
--
-- Passing a real half-footprint at all seventy sites is seventy separate judgements about props
-- that are built in loops at random sizes, and each one is a chance to type the wrong number.
-- A FLOOR is the honest version of the same fix: a call that declines to say how big it is gets
-- treated as `DEFAULT_HALF` wide, and -- this is the half that actually matters -- it CLAIMS that
-- much ground on the way out. Nine calls know their size exactly and still do; the other
-- seventy-nine stop pretending they are points.
--
-- 14 is a floor and not a measurement, and it is chosen from below rather than above: it is a
-- little larger than the small stuff (pottery at 3, shards at 6) and a lot smaller than the big
-- stuff (dunes at 55, vents at 40), so it costs the small props nothing they will miss and gives
-- the big ones a partial guard instead of none. A prop that wants the real thing passes it.
local DEFAULT_HALF = 14

local function scatterPoint(cx, spreadX, spreadZ, halfSize)
	-- an undeclared size is the case above: assume the floor AND register it
	local autoClaim = halfSize == nil
	halfSize = halfSize or DEFAULT_HALF
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

	-- Every exit goes through here, so there is no path out of this function that takes ground
	-- without saying so. The claim is a little smaller than the clearance it was tested against --
	-- being asked to stand 14 studs off a neighbour and to reserve 14 for yourself compounds into a
	-- 28-stud exclusion around a prop that may be four studs wide, and twenty zones' worth of that
	-- empties the platform.
	local function claim(x, z)
		if autoClaim then reserveScatter(x, z, halfSize * 0.65) end
		return x, z
	end

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
				return claim(wx, z)
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
		return claim(bestX, bestZ)
	end
	-- and only if literally every try failed the fixed geography as well. Pushed past BOSS_CLEAR
	-- rather than CLEAR_HALF: the boss arena is the widest reservation on the platform.
	local sign = math.random(1, 2) == 1 and -1 or 1
	return claim(cx + sign * math.random(math.min(boss + 12, spreadX), spreadX), math.random(-spreadZ, -centre))
end

-- The platform went from 700 x 860 to 900 x 860 -- 24% more ground, all of it off the street where
-- the scatter lands. The per-biome counts below were authored against the old area, so without this
-- every zone came out visibly emptier the moment it was widened: same number of rocks, more floor
-- to spread them over. One multiplier rather than 20 edited tables, so the next resize is one line.
local DENSITY = 1.78
local function scaled(count, fallback)
	return math.max(1, math.floor((count or fallback) * DENSITY + 0.5))
end

-- `scatterBlocks` itself is deliberately NOT exported -- see `clearReservations` for why. Nor are
-- the geography constants that only `scatterPoint` reads (`DECO_SPREAD_*`, `CLEAR_HALF`,
-- `ARRIVAL_CLEAR`, `BOSS_CLEAR`, `LEGACY_SPREAD_*`, `DEFAULT_HALF`, `DENSITY`); the two below are
-- out because `ZoneBuilder` places hand-built things against them.
return {
	scatterPoint = scatterPoint,
	reserveScatter = reserveScatter,
	clearReservations = clearReservations,
	scaled = scaled,

	STREET_HALF = STREET_HALF,
	ARRIVAL_Z = ARRIVAL_Z,
}
