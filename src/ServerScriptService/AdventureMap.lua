-- AdventureMap -- the twenty obby courses a Pet Adventure is run on, and nothing else.
--
-- WHY IT IS ITS OWN FILE, and it is the third time this argument is made (`EventArena`,
-- `ExpeditionMap`): this is geometry that is not part of a zone. It carries its own version stamp
-- for the reason those do -- bumping `ZoneBuilder.BUILD_VERSION` drops all twenty-one zones and
-- rebuilds ~105,000 parts, and a course is about two hundred. Re-cutting a jump must not cost a
-- full world rebuild.
--
-- =====================================================================================
-- THE COURSES ARE BUILT LAZILY, AND THAT IS THE ONE STRUCTURAL DIFFERENCE FROM THE EXPEDITION
-- =====================================================================================
-- All four expedition maps are built at `ExpeditionService.Init`, before anybody joins. Twenty
-- courses is five times that geometry for a feature most of a server never opens, so a course is
-- built on FIRST ENTRY and kept for the life of the server. The cost of that decision is paid in
-- `AdventureService`: `ZoneService.Init` scans `workspace.Zones` for parts named `PortalGate`
-- exactly ONCE at startup (`ZoneService.lua:334-338`), so a map built later has an exit gate that
-- is a decorative slab. `AdventureService` therefore wires every gate, pad and finish line itself,
-- at build time, and these maps are deliberately parented into `workspace.Adventures` rather than
-- `workspace.Zones` -- there is nothing for that scan to find and no zone-shaped model sitting in
-- the folder the zone services enumerate.
--
-- =====================================================================================
-- THE COURSE IS SIZED AGAINST A FIXED MOVEMENT PROFILE, NOT AGAINST THE PLAYER'S BODY
-- =====================================================================================
-- THIS IS THE DECISION THE WHOLE FILE HANGS ON, and it was forced by arithmetic rather than taste.
-- A player's movement in this game is a function of their stage (`Mastery.lua`):
--
--   stage 1   WalkSpeed 34,  JumpPower 44  ->  4.9 studs of apex, 0.45 s of air, ~15 studs of leap
--   stage 20  WalkSpeed 150, JumpPower 52  ->  6.9 studs of apex, 0.53 s of air, ~148 studs of leap
--
-- ...and the BODY runs from about 5 studs across to **45 x 42 x 35** at the top. So a course cut for
-- the stage-one player is a floor with cracks in it to everybody else (a 12-stud gap against a
-- 148-stud leap), and a course cut for the stage-twenty player cannot be entered at all by the
-- player the first route is aimed at. There is no single geometry that answers both, and there is
-- no instancing in this codebase to cut two.
--
-- So the profile is FIXED while a player is on a course -- `AdventureService` writes these two on
-- entry and calls `EvolutionVisuals.RefreshBonuses` to put the player's real numbers back on exit:
--
--   WALK_SPEED 80, JUMP_POWER 74  ->  13.9 studs of apex, 0.75 s of air, ~60 studs of leap
--
-- Every gap below is quoted as a share of that 60, and none of them exceeds 42 (70%). The pads are
-- 72 studs square or more because the biggest body in the game is 45 across, and a platform it
-- cannot stand on with margin is a platform it falls off while standing still.
--
-- The jump is deliberately BIGGER than anything the strip allows (the world caps at 52 / 6.9 studs,
-- because a player who can jump the zone walls lands in the gap between two platforms). Nothing out
-- here is a zone wall, so the cap that protects the strip is exactly the cap that would make an
-- obby unplayable.
--
-- =====================================================================================
-- FALLING IS A TELEPORT, NEVER A DEATH
-- =====================================================================================
-- Roblox respawns only at a `SpawnLocation` and this game deliberately has exactly ONE, in Forest
-- (the engine picks between multiple at random). A death mid-course would therefore eject the
-- player to the start of the strip, and `ReturnToCurrentZone` would then move them again. There are
-- no kill bricks here and no lava: the drop is empty air, and `AdventureService`'s Heartbeat
-- catches anyone below `GetVoidY()` and puts them back on their checkpoint.
--
-- =====================================================================================
-- ...AND SO IS BEING ZAPPED (34.50)
-- =====================================================================================
-- The owner, on a capture of route 12: *"ovaj lobby prelak, tj sve jedno je prelak, ovo sve to
-- plavo moze biti kao laser ako ga pipnes ubije te"*. She is right about the shape of the problem:
-- until this row every obstacle on a course was a GAP or a PUSH, and against the fixed profile
-- above the biggest gap in the game is 42 studs of a 60-stud reach. Nothing could fail you except
-- walking off an edge, so a course was a scenic walk with a clock on it.
--
-- "Ubije te" cannot be a kill brick, for exactly the reason written directly above: the death would
-- eject the player to Forest, 4,000 studs down the strip. So a laser does what the void already
-- does -- puts you back on your last checkpoint -- and it is the SAME code path in
-- `AdventureService`'s Heartbeat, one loop further down.
--
-- THE CURTAIN IS TIMED AND NEVER JUMPED, and that is what makes it fair at both ends of the body
-- ladder. It spans the beat wall to wall and stands 34 studs tall against a 13.9-stud apex, so
-- there is no route round it and no route over it -- there is only waiting for it to go dark. That
-- is the one obstacle shape whose difficulty does not depend on how big the player is, which is
-- the property the whole file is built around.
--
-- AND IT IS VISIBLE WHILE IT IS HARMLESS. A curtain that vanishes when it is off is a trap you can
-- only learn by dying in it; dark is `Transparency = 0.72` with its light out -- a ghost of where
-- the beam will be -- and lit is 0.1 with the light on.
--
-- =====================================================================================
-- WHERE IT SITS
-- =====================================================================================
-- The zone strip runs +Z from Forest at `ZoneSpacing` 1900 and is 1250 studs wide about x = 0; the
-- Colosseum is at z +1400 and the expedition chambers at z -1250..-2500. All of that lives inside
-- x = +/-625. The courses take the empty half-plane out past x = -4200, one lane each, and run
-- along +Z. Nothing in the strip is ever out there, so nothing can collide with it.

local ZoneKit = require(script.Parent.ZoneKit)

local newPart, addLight = ZoneKit.newPart, ZoneKit.addLight
local addPlankText = ZoneKit.addPlankText
local lighten, darken, vivid = ZoneKit.lighten, ZoneKit.darken, ZoneKit.vivid

local AdventureMap = {}

-- Bump when the SHAPE changes. `AdventureService` compares this against the model's own attribute
-- and rebuilds that ONE course, leaving the other nineteen and the twenty-one zones untouched.
AdventureMap.MAP_VERSION = 2

-- ===== THE MOVEMENT PROFILE (see the header -- this is not a preference) =====
AdventureMap.WALK_SPEED = 80
AdventureMap.JUMP_POWER = 74
-- apex = power^2 / (2 * 196.2) = 13.96 studs; air = 2 * power / 196.2 = 0.754 s
-- reach = air * speed = 60.3 studs. Every gap below is a share of this.

-- ===== THE FLOOR PLAN, AND THE LANES ARE FAR APART AND AT DIFFERENT HEIGHTS, AND A SCREENSHOT IS WHY =====
-- The first capture of this file had all twenty courses 440 studs apart on one deck, and standing
-- on route 1 you could see nineteen identical obbies receding to the horizon in a neat grid. It
-- read as a debug scene rather than as a place -- the same failure `ZoneBuilder` had before the
-- zones got their walls. Two cheap changes fix it and neither costs anything but empty coordinates:
-- the pitch is now 1,400 studs (the world's own fog swallows a neighbour at that range) and the
-- deck height steps through five levels, so an adjacent lane is never in the eyeline either. The
-- multiplier is 3 against a modulus of 5 so consecutive tiers can never land on the same level.
local DECK_Y = 220 -- the lowest deck; the courses float in open air
local DECK_STEP = 320 -- how far apart the five levels are
local DECK_LEVELS = 5
local VOID_DROP = 110 -- how far below its own deck a player has to be to count as fallen
local LANE_X0 = -4200 -- lane of route 1
local LANE_PITCH = 1400 -- centre to centre
local START_Z = -1300 -- the centre of every course's start platform

local SLAB_T = 6 -- how thick a walking surface is
local LIP_T = 5 -- the darker slab under it -- the outline tier every chunky prop in this game has
local LIP_OUT = 5 -- how far that slab sticks out past the surface, per side

local PAD = 72 -- the standard platform: clears a 45-stud body with 13 studs to spare
-- BIGGER THAN A PAD, AND THE 16 STUDS ARE MEASURED. A rider on a conveyor-driven platform does not
-- track it perfectly: the body lags at each end of the sweep, where the platform reverses and the
-- humanoid's own ground friction has to catch up. Measured on the live server at the authored span
-- and period, the worst drift is **12.4 studs** off centre -- so a 72-stud platform would put a
-- 45-stud body's edge 3 studs from the lip at every turn. 88 leaves it 10.
local MOVER = 88
local BIG = 130 -- start and finish
local CHECK = 96 -- a checkpoint platform
local STONE = 48 -- a stepping stone
local BEAM_W = 36 -- the narrow bridge -- narrower than a pad, wider than the body's shoulders

local GAP_EASY = 26 -- 43% of reach
local GAP_MED = 34 -- 57%
local GAP_HARD = 42 -- 70%, and the largest gap in the game

local BEATS_PER_SECTION = 3

-- ===== ACCESSORS =====
-- Read by `AdventureService`, and all of them are pure arithmetic on the route's tier -- so they
-- answer for a course that does not exist yet, which is what makes the lazy build possible.
function AdventureMap.GetLaneX(route)
	return LANE_X0 - (route.tier - 1) * LANE_PITCH
end

-- PER ROUTE, not a constant, since the lanes are staggered (see the block above). Anything that
-- catches a fall has to ask the route, or it catches route 1's fall at route 5's altitude.
function AdventureMap.GetDeckY(route)
	return DECK_Y + ((route.tier * 3) % DECK_LEVELS) * DECK_STEP
end

function AdventureMap.GetVoidY(route)
	return AdventureMap.GetDeckY(route) - VOID_DROP
end

-- Where a run starts: on the start platform, looking down the course. The first thing on screen is
-- the route, which is what `ExpeditionMap.GetSpawnCFrame` is arranged to do as well.
function AdventureMap.GetSpawnCFrame(route)
	local pos = Vector3.new(AdventureMap.GetLaneX(route), AdventureMap.GetDeckY(route) + 8,
		START_Z - BIG / 2 + 34)
	return CFrame.lookAt(pos, pos + Vector3.new(0, 0, 40))
end

-- ===== THE PIECES =====
--
-- One helper builds every walking surface in the file, and it builds TWO parts: the surface and a
-- darker slab under it that sticks out five studs on every side. That second part is the outline
-- tier -- the rule the whole world is drawn to: a shape with no darker edge under it reads as a
-- flat sticker, and out here there is no ground behind the platform to read it against at all.
--
-- `y` is the WALKING SURFACE, never the centre, because every number in a course is a height a
-- player stands at. `noLip` exists for exactly one caller: a platform that is about to move must
-- not leave a stationary outline behind it, which reads as the platform sliding out of its own
-- shadow.
local function slab(ctx, name, x, y, z, sx, sz, colour, material, noLip)
	local top = newPart({
		Name = name,
		Size = Vector3.new(sx, SLAB_T, sz),
		Position = Vector3.new(x, y - SLAB_T / 2, z),
		Color = colour,
		Material = material or Enum.Material.SmoothPlastic,
		Parent = ctx.model,
	})
	if not noLip then
		newPart({
			Name = "Lip",
			Size = Vector3.new(sx + LIP_OUT * 2, LIP_T, sz + LIP_OUT * 2),
			Position = Vector3.new(x, y - SLAB_T - LIP_T / 2, z),
			Color = darken(colour, 0.5),
			Material = Enum.Material.Slate,
			Parent = ctx.model,
		})
	end
	return top
end

-- A platform that MOVES, and there is exactly one way it moves: back and forth along the course.
-- Anchored, and driven by `AdventureService`'s single Heartbeat rather than by a tween per part --
-- the standing rule for this project is one gated Heartbeat per animated SET, and this set grows by
-- four or five parts with every route added.
--
-- The base CFrame is stamped on the part as an attribute rather than held in a table beside it, so
-- a course that is rebuilt re-registers itself completely by being walked: the driver needs no
-- memory of a map it did not build.
--
-- ===== AN ANCHORED PLATFORM MOVED BY CFrame DOES NOT CARRY THE PLAYER, AND IT WAS MEASURED =====
-- The obvious implementation -- anchored, `part.CFrame` rewritten every Heartbeat -- was written,
-- shipped into a live server, and stood on. **The body drifted 87 of the platform's 98 studs and
-- fell off the back**, because a teleported part has no velocity and friction has nothing to
-- transmit: the floor slides out from under the rider at the platform's full speed.
--
-- The fix is one extra line in `AdventureService`'s Heartbeat, not a physics rig. An ANCHORED part
-- with a non-zero `AssemblyLinearVelocity` is a CONVEYOR in this engine -- it moves what stands on
-- it without moving itself -- so the driver writes the analytic derivative of the sweep beside the
-- position. Same measurement afterwards: **12.4 studs of drift**, and that number is what sized
-- `MOVER` above. Nothing here may be driven by position alone.
local function mover(ctx, x, y, z, span, period, phase)
	local part = slab(ctx, "Mover", x, y, z, MOVER, MOVER, vivid(ctx.accent), Enum.Material.Metal, true)
	part:SetAttribute("BaseCFrame", part.CFrame)
	part:SetAttribute("MoveSpan", span)
	part:SetAttribute("MovePeriod", period)
	part:SetAttribute("MovePhase", phase or 0)
	-- The edge a `Lip` would have given it, carried on the part itself instead.
	local rim = newPart({
		Name = "MoverRim",
		Size = Vector3.new(MOVER + 6, 3, MOVER + 6),
		Position = Vector3.new(x, y - SLAB_T - 1.5, z),
		Color = darken(ctx.accent, 0.55),
		Material = Enum.Material.Metal,
		CanCollide = false,
		Parent = ctx.model,
	})
	-- Welded to the platform rather than driven separately: the Heartbeat moves one part per mover,
	-- and a rim on its own attribute list is a second thing to keep in step and a second way to
	-- fall out of it.
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part
	weld.Part1 = rim
	weld.Parent = part
	rim.Anchored = false
	addLight(part, ctx.accent, 40, 1.6)
	return part
end

-- A bar that sweeps the platform it stands on. Same driver, same reason, and it is a BAR rather
-- than a blade because an anchored part that a 45-stud body walks into has to push it, not cut it.
--
-- IT STARTS ONE STUD OFF THE DECK, and that is the fixed-geometry problem in miniature. The first
-- version put the bar's underside 7.5 studs up, which is a shin height for the 45-stud body at the
-- top of the game and a clean miss OVER THE HEAD of the ~5-stud body at the bottom of it -- so the
-- one obstacle in the set that is not a gap did nothing at all for the players route 1 is aimed at.
-- Spanning y+1 to y+15 catches both: it sweeps a small body off entirely and shoves a large one.
local function spinner(ctx, x, y, z, length, degPerSecond)
	newPart({
		Name = "SpinnerHub",
		Size = Vector3.new(10, 20, 10),
		Position = Vector3.new(x, y + 10, z),
		Color = darken(ctx.accent, 0.35),
		Material = Enum.Material.Metal,
		Parent = ctx.model,
	})
	local bar = newPart({
		Name = "Spinner",
		Size = Vector3.new(length, 14, 8),
		Position = Vector3.new(x, y + 8, z),
		Color = vivid(ctx.accent),
		Material = Enum.Material.Neon,
		Parent = ctx.model,
	})
	bar:SetAttribute("BaseCFrame", bar.CFrame)
	bar:SetAttribute("SpinSpeed", degPerSecond)
	addLight(bar, ctx.accent, 50, 2)
	return bar
end

-- ===== A LASER CURTAIN (34.50) =====
--
-- Neon in the route's own accent, spanning the beat it stands on, blinking on a cadence the route's
-- tier sets. Nothing here moves and nothing here collides: the part is a marker, and
-- `AdventureService` owns both the blink and the hit test, in the Heartbeat it already runs.
--
-- IT IS NOT DRIVEN BY `Touched`, and that is a decision rather than an oversight. A curtain that
-- lights up around a player who is standing still fires no `Touched` at all -- the contact is not
-- new -- so the one case the timing puzzle is built to punish is the one case the event misses.
-- `CanTouch = false` says so out loud rather than leaving a live event nobody reads.
--
-- 34 STUDS TALL, STARTING ONE STUD OFF THE DECK, and both numbers are the same measurement the
-- `spinner` bar records: the bodies on a course run from about 5 studs to 45, so an obstacle sized
-- for either one is nothing at all to the other. A curtain that reaches from the deck to above the
-- tallest body's root, on a course whose jump apex is 13.9, cannot be cleared by anybody.
local LASER_H = 34
local LASER_T = 3
AdventureMap.LASER_LIT = 0.1
AdventureMap.LASER_DARK = 0.72

-- Period and duty from the tier, as one function, because the two placements below must not drift
-- into two different difficulty curves. `duty` is the share of the cycle the beam is LIT -- under a
-- half at every tier, so the gap is always the longer half of the cycle.
--   tier 1  -> 2.84 s, 41% lit (1.68 s of gap)      tier 20 -> 2.00 s, 52% lit (0.96 s of gap)
function AdventureMap.LaserCadence(tier)
	return 2.9 - math.min(tier, 15) * 0.06, 0.40 + math.min(tier, 20) * 0.006
end

local function laser(ctx, x, y, z, width, period, phase, duty)
	local bar = newPart({
		Name = "Laser",
		Size = Vector3.new(width, LASER_H, LASER_T),
		Position = Vector3.new(x, y + 1 + LASER_H / 2, z),
		Color = vivid(ctx.accent),
		Material = Enum.Material.Neon,
		Transparency = AdventureMap.LASER_DARK,
		CanCollide = false,
		CanTouch = false,
		Parent = ctx.model,
	})
	bar:SetAttribute("LaserPeriod", period)
	bar:SetAttribute("LaserPhase", phase)
	bar:SetAttribute("LaserDuty", duty)
	local light = addLight(bar, ctx.accent, 52, 2.4)
	light.Enabled = false

	-- The two emitters it hangs between. Without them the beam is a coloured sheet floating over the
	-- deck with nothing to explain it -- the same "flat sticker" fault the `Lip` under every slab is
	-- there to answer, and the posts are what make a dark curtain readable as a thing that is off.
	for _, side in ipairs({ -1, 1 }) do
		newPart({
			Name = "LaserPost",
			Size = Vector3.new(8, LASER_H + 8, 8),
			Position = Vector3.new(x + side * (width / 2 + 4), y + (LASER_H + 8) / 2, z),
			Color = darken(ctx.accent, 0.45),
			Material = Enum.Material.Metal,
			Parent = ctx.model,
		})
	end
	return bar
end

-- ===== THE BEATS =====
--
-- Five of them, and each one takes the far edge of what came before and returns the far edge of
-- what it left. That contract is the whole reason a course can be assembled by a loop: no beat
-- knows what is on either side of it, and every beat ENDS on something solid, so the next one can
-- always take off from a floor.
local BEATS = {}

-- Four stepping stones, stepped left and right of the centre line so the run is not a straight
-- sprint.
function BEATS.stones(ctx, z)
	for i = 1, 4 do
		-- The last one is the only `GAP_HARD` in the game: 42 studs against a 60-stud reach. Every
		-- other gap here is 26 or 34, so a stepping-stone run ends on a jump the player has to
		-- commit to rather than on a fourth identical hop.
		local cz = z + (i == 4 and GAP_HARD or GAP_MED) + STONE / 2
		local dx = (i % 2 == 0) and 26 or -26
		slab(ctx, "Stone", ctx.x + dx, ctx.y, cz, STONE, STONE, ctx.ground)
		z = cz + STONE / 2
	end
	return z
end

-- A long narrow bridge. Half the width of a pad, so a body that is 45 across is standing on
-- something it can see the edges of -- which is the entire difficulty.
function BEATS.beam(ctx, z)
	local length = 200
	local cz = z + GAP_EASY + length / 2
	slab(ctx, "Beam", ctx.x, ctx.y, cz, BEAM_W, length, lighten(ctx.ground, 0.15))
	-- A lit strip down the middle: from the far end of a 200-stud bridge in open air, an unlit deck
	-- and the void behind it are the same colour.
	newPart({
		Name = "BeamStripe",
		Size = Vector3.new(4, 1, length - 8),
		Position = Vector3.new(ctx.x, ctx.y + 0.5, cz),
		Color = vivid(ctx.accent),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = ctx.model,
	})

	-- ===== THE CURTAINS, AND THE PHASE STEP IS THE WHOLE PUZZLE (34.50) =====
	-- Two to four gates evenly along the bridge, each one a whole phase-step behind the last, so the
	-- dark half travels down the bridge at about the speed a player crosses it: at WalkSpeed 80 a
	-- (gates + 1) spacing of ~66 studs is 0.83 s and the step at tier 12 is 0.73 s. A player who
	-- keeps moving threads all of them; one who stops has to re-time from a standstill, which is
	-- this beat costing par time rather than lives.
	--
	-- ON THE BEAM RATHER THAN OVER A GAP, and that is the fairness rule for placing any of these: a
	-- curtain you meet in mid-air is a coin toss, because a jump cannot be aborted. Every laser in
	-- this file stands on ground the player can stop on.
	local gates = 2 + math.min(math.floor(ctx.tier / 7), 2)
	local period, duty = AdventureMap.LaserCadence(ctx.tier)
	for i = 1, gates do
		laser(ctx, ctx.x, ctx.y, cz - length / 2 + length * i / (gates + 1),
			BEAM_W + 16, period, (i - 1) / gates, duty)
	end
	return cz + length / 2
end

-- A wide pad with a bar sweeping it. Wide on purpose: the bar is what makes this hard, and a narrow
-- pad under a sweeping bar is not a harder beat, it is a coin toss.
function BEATS.spin(ctx, z)
	local size = 118
	local cz = z + GAP_MED + size / 2
	slab(ctx, "SpinPad", ctx.x, ctx.y, cz, size, size, ctx.ground)
	spinner(ctx, ctx.x, ctx.y, cz, size + 22, 42 + ctx.tier * 3)
	return cz + size / 2
end

-- A gap nothing can jump, crossed by a platform that comes to fetch you. The only beat in the set
-- with a wait in it, which is what makes it the one that costs par time rather than lives.
function BEATS.slide(ctx, z)
	local gap = 190
	local far = z + gap
	-- The period floor is 6 s rather than 5, and that is the conveyor again: peak sweep speed is
	-- `2*pi/period * span/2`, the rider's lag grows with it, and 6 s keeps the fastest route's
	-- platform at 43 studs/s -- the speed the 12.4-stud drift above was measured at.
	mover(ctx, ctx.x, ctx.y, z + gap / 2, gap - MOVER - 20,
		7.5 - math.min(ctx.tier, 15) * 0.10, (ctx.beat % 2) * 0.5)
	local cz = far + PAD / 2
	slab(ctx, "Landing", ctx.x, ctx.y, cz, PAD, PAD, ctx.ground)
	return cz + PAD / 2
end

-- Up two steps and down two. Nine studs a step against a 13.9-stud apex -- a real climb with the
-- margin a player needs when they are 45 studs wide and the step is 56.
function BEATS.climb(ctx, z)
	local rises = { 9, 18, 9, 0 }
	local period, duty = AdventureMap.LaserCadence(ctx.tier)
	for i, rise in ipairs(rises) do
		local cz = z + (i == 1 and GAP_EASY or 22) + 28
		slab(ctx, "Step", ctx.x, ctx.y + rise, cz, 56, 56, lighten(ctx.ground, 0.08 * i))
		-- ONE curtain, on the TOP step, and it is the only obstacle in the beat. The step is 56
		-- square, so there is somewhere to stand and wait -- the fairness rule from `beam` -- and
		-- it turns the climb from four hops into a hold at the summit. A second curtain lower down
		-- was refused for the same reason: two waits in one beat is a corridor, not a climb.
		if i == 2 then
			laser(ctx, ctx.x, ctx.y + rise, cz, 56 + 16, period, 0.5, duty)
		end
		z = cz + 28
	end
	return z
end

-- The order is rotated by tier, so route 7 and route 8 are not the same course in different
-- colours. Deterministic, because a course rebuilt at a version bump has to come back the same
-- shape or every best time in `data.Adventures.Best` is a time on a course that no longer exists.
local ORDER = { "stones", "beam", "spin", "slide", "climb" }

-- ===== THE FURNITURE =====

local function checkpointPlatform(ctx, z, index)
	local cz = z + GAP_MED + CHECK / 2
	slab(ctx, "CheckPlatform", ctx.x, ctx.y, cz, CHECK, CHECK, lighten(ctx.ground, 0.22))

	-- The pad itself is a thin non-colliding sheet lying on the platform: the player walks over it
	-- rather than into it, and `Touched` is what `AdventureService` connects at build time. It is
	-- named `Checkpoint` and carries its own index, so the service needs no table of positions.
	local pad = newPart({
		Name = "Checkpoint",
		Size = Vector3.new(CHECK - 16, 1, CHECK - 16),
		Position = Vector3.new(ctx.x, ctx.y + 0.6, cz),
		Color = vivid(ctx.accent),
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
		Parent = ctx.model,
	})
	pad:SetAttribute("CheckpointIndex", index)
	addLight(pad, ctx.accent, 70, 2.2)

	local pole = newPart({
		Name = "FlagPole",
		Size = Vector3.new(3, 34, 3),
		Position = Vector3.new(ctx.x - CHECK / 2 + 8, ctx.y + 17, cz),
		Color = Color3.fromRGB(58, 48, 74),
		Material = Enum.Material.Metal,
		Parent = ctx.model,
	})
	local banner = newPart({
		Name = "FlagBanner",
		Size = Vector3.new(34, 16, 2),
		Position = Vector3.new(ctx.x - CHECK / 2 + 25, ctx.y + 28, cz),
		Color = darken(ctx.accent, 0.3),
		Material = Enum.Material.SmoothPlastic,
		Parent = ctx.model,
	})
	addPlankText(banner, index .. " / " .. ctx.sections, Color3.fromRGB(255, 247, 230),
		{ pixelsPerStud = 16, maxDistance = 500 })
	addLight(banner, ctx.accent, 44, 1.6)
	addLight(pole, ctx.accent, 24, 1)

	return cz + CHECK / 2, pad
end

local function startPlatform(ctx)
	local cz = START_Z
	slab(ctx, "StartPlatform", ctx.x, ctx.y, cz, BIG, BIG, lighten(ctx.ground, 0.3))

	-- The arrival pad, so a player who has just been teleported knows they landed rather than fell.
	-- Same cylinder the expedition map uses, and the same reason.
	local pad = newPart({
		Name = "ArrivalPad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.6, 62, 62),
		CFrame = CFrame.new(Vector3.new(ctx.x, ctx.y + 0.8, cz - BIG / 2 + 34))
			* CFrame.Angles(0, 0, math.rad(90)),
		Color = vivid(ctx.accent),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = ctx.model,
	})
	addLight(pad, ctx.accent, 70, 2.4)

	-- Checkpoint ONE is the start platform. A player who falls off the first beat has not reached a
	-- pad yet, and the only place to put them that is not a bug is where they came in.
	local first = newPart({
		Name = "Checkpoint",
		Size = Vector3.new(BIG - 20, 1, BIG - 20),
		Position = Vector3.new(ctx.x, ctx.y + 0.4, cz),
		Color = vivid(ctx.accent),
		Material = Enum.Material.Neon,
		Transparency = 0.85,
		CanCollide = false,
		Parent = ctx.model,
	})
	first:SetAttribute("CheckpointIndex", 1)

	-- The board, and it is the only place the route's name is ever read in the world. This game
	-- creates zero Humanoids server-side and has no dialogue system, so signs are it.
	local post = newPart({
		Name = "BoardPost",
		Size = Vector3.new(5, 30, 5),
		Position = Vector3.new(ctx.x + BIG / 2 - 14, ctx.y + 15, cz),
		Color = Color3.fromRGB(58, 48, 74),
		Material = Enum.Material.Metal,
		Parent = ctx.model,
	})
	local board = newPart({
		Name = "RouteBoard",
		Size = Vector3.new(96, 34, 2),
		Position = Vector3.new(ctx.x + BIG / 2 - 14, ctx.y + 46, cz),
		Color = darken(ctx.accent, 0.35),
		Material = Enum.Material.SmoothPlastic,
		Parent = ctx.model,
	})
	addPlankText(board, ctx.route.emoji .. " " .. ctx.route.name, Color3.fromRGB(255, 247, 230),
		{ pixelsPerStud = 14, maxDistance = 600 })
	addLight(board, ctx.accent, 60, 2)
	addLight(post, ctx.accent, 30, 1.2)

	-- THE WAY OUT, and it is a `PortalGate` by name only for the family resemblance -- nothing in
	-- `ZoneService` will ever see this one, because that file's scan ran before this model existed.
	-- `AdventureService` connects it itself, at build time. The attribute is set anyway so the part
	-- is self-describing to anyone reading it in the explorer.
	--
	-- IT STANDS ON ITS OWN SPUR BEHIND THE START PLATFORM, and the first capture of this file is
	-- why. Built flush with the platform's near edge it was a 68 x 60 sheet filling the whole
	-- arrival view, nine studs behind the back of a stage-twenty body -- so the way OUT of a run
	-- was the biggest thing on screen at the start of one, and a player who stepped backwards on
	-- arrival was ejected without touching anything. Leaving is now a deliberate walk: turn round,
	-- cross the platform, step onto the spur.
	local spurZ = cz - BIG / 2 - 30
	slab(ctx, "ExitSpur", ctx.x, ctx.y, spurZ, 60, 60, lighten(ctx.ground, 0.18))
	local frame = newPart({
		Name = "ExitFrame",
		Size = Vector3.new(56, 6, 6),
		Position = Vector3.new(ctx.x, ctx.y + 48, spurZ - 26),
		Color = Color3.fromRGB(58, 48, 74),
		Material = Enum.Material.Metal,
		Parent = ctx.model,
	})
	local gate = newPart({
		Name = "PortalGate",
		Size = Vector3.new(48, 44, 3),
		Position = Vector3.new(ctx.x, ctx.y + 22, spurZ - 26),
		Color = vivid(ctx.accent),
		Material = Enum.Material.Neon,
		Transparency = 0.4,
		CanCollide = false,
		Parent = ctx.model,
	})
	gate:SetAttribute("TargetZone", "ReturnFromAdventure")
	addLight(gate, ctx.accent, 80, 3)
	addPlankText(frame, "LEAVE", Color3.fromRGB(255, 247, 230), { pixelsPerStud = 10, maxDistance = 400 })

	return cz + BIG / 2, gate
end

local function finishPlatform(ctx, z)
	local cz = z + GAP_MED + BIG / 2
	slab(ctx, "FinishPlatform", ctx.x, ctx.y, cz, BIG, BIG, lighten(ctx.ground, 0.3))

	local pad = newPart({
		Name = "FinishPad",
		Size = Vector3.new(BIG - 24, 1, BIG - 24),
		Position = Vector3.new(ctx.x, ctx.y + 0.6, cz),
		Color = Color3.fromRGB(255, 214, 92),
		Material = Enum.Material.Neon,
		Transparency = 0.25,
		CanCollide = false,
		Parent = ctx.model,
	})
	addLight(pad, Color3.fromRGB(255, 214, 92), 90, 3)

	-- A gantry over the line, because a finish that is a pad on the floor is a thing a player runs
	-- past without noticing they have won.
	for _, side in ipairs({ -1, 1 }) do
		newPart({
			Name = "FinishPost",
			Size = Vector3.new(6, 54, 6),
			Position = Vector3.new(ctx.x + side * (BIG / 2 - 10), ctx.y + 27, cz),
			Color = Color3.fromRGB(58, 48, 74),
			Material = Enum.Material.Metal,
			Parent = ctx.model,
		})
	end
	local banner = newPart({
		Name = "FinishBanner",
		Size = Vector3.new(BIG - 20, 22, 2),
		Position = Vector3.new(ctx.x, ctx.y + 62, cz),
		Color = Color3.fromRGB(72, 58, 40),
		Material = Enum.Material.SmoothPlastic,
		Parent = ctx.model,
	})
	addPlankText(banner, "\u{1F3C1} FINISH", Color3.fromRGB(255, 236, 170),
		{ pixelsPerStud = 14, maxDistance = 600 })
	addLight(banner, Color3.fromRGB(255, 214, 92), 70, 2.4)

	return cz + BIG / 2, pad
end

-- ===== THE BUILD =====
function AdventureMap.Build(parent, route)
	local model = Instance.new("Model")
	model.Name = "Adventure_" .. route.key
	model:SetAttribute("MapVersion", AdventureMap.MAP_VERSION)
	model:SetAttribute("AdventureKey", route.key)
	model:SetAttribute("Tier", route.tier)

	local ctx = {
		model = model,
		route = route,
		tier = route.tier,
		sections = route.sections,
		x = AdventureMap.GetLaneX(route),
		y = AdventureMap.GetDeckY(route),
		-- The course paints itself out of the zone it is themed on -- the same rule 30.1 wrote the
		-- two colours onto the route for.
		ground = route.groundColor or Color3.fromRGB(120, 130, 150),
		accent = route.accentColor or Color3.fromRGB(120, 235, 150),
		beat = 0,
	}

	local z = startPlatform(ctx)

	for section = 1, route.sections do
		for _ = 1, BEATS_PER_SECTION do
			ctx.beat += 1
			local kind = ORDER[((route.tier - 1 + ctx.beat - 1) % #ORDER) + 1]
			z = BEATS[kind](ctx, z)
		end
		-- A checkpoint at the END of every section except the last, which is followed by the finish
		-- line instead. `sections` checkpoints in total: the start platform is number one.
		if section < route.sections then
			z = checkpointPlatform(ctx, z, section + 1)
		end
	end

	finishPlatform(ctx, z)

	model:SetAttribute("EndZ", z)
	model.Parent = parent
	-- Never streamed out, for the reason the expedition map is not: it is entered by teleport rather
	-- than walked up to, and a player who arrives before the floor does falls out of the world --
	-- which out here means falling forever, because there is no ground under any of it.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	return model
end

-- Rebuilt by REPLACEMENT rather than patched in place, which is `ExpeditionMap`'s rule and the same
-- argument: a stamped model whose version has moved is not the same structure, and reconciling it
-- piece by piece is how half-old geometry lives on.
function AdventureMap.EnsureBuilt(parent, route)
	local name = "Adventure_" .. route.key
	local existing = parent:FindFirstChild(name)
	if existing and existing:GetAttribute("MapVersion") ~= AdventureMap.MAP_VERSION then
		warn(("[AdventureMap] rebuilding %s: stamp %s -> %d")
			:format(name, tostring(existing:GetAttribute("MapVersion")), AdventureMap.MAP_VERSION))
		existing:Destroy()
		existing = nil
	end
	local built = false
	if not existing then
		existing = AdventureMap.Build(parent, route)
		built = true
	end
	return existing, built
end

return AdventureMap
