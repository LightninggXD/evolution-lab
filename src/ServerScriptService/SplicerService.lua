--[[
	SplicerService -- the DNA Splicer: the machine mutations are bought at, and the sink DNA
	needed (Phase 12.2).

	=========================================================================================
	WHAT THIS REPLACED, WHICH IS THE REASON IT EXISTS
	=========================================================================================
	Mutations were not a feature before this: they were a loop in DNAService that fired every ten
	seconds for as long as a player was online, appended a name to a list nothing ever pruned, and
	multiplied income by a ladder topping at x30. No screen in the game named it, no action
	triggered it, and nobody ever chose to have one. The whole system was a faucet.

	It is a machine you walk up to and pay for now. The roll itself is unchanged
	(`GameConfig.RollMutation`) -- what is new is that it costs something, that exactly one
	mutation is worn at a time, and that the rare end of the ladder is worth telling the server
	about.

	=========================================================================================
	THE PRICE IS IN KILLS, AND THAT IS NOT A FIGURE OF SPEECH
	=========================================================================================
	`GameConfig.GetSplicerRollCost` is the one implementation and this file does not do its own
	arithmetic anywhere -- the client panel quotes the same function, so the number on the screen
	and the number charged cannot drift. See the block over it in GameConfig for why it is priced
	off per-kill income rather than through `ScaleReward`.

	=========================================================================================
	THREE THINGS THE SERVER DOES NOT TRUST THE CLIENT FOR
	=========================================================================================
	* THE PRICE. Recomputed here from the save, never read off the request.
	* THE PITY. `SplicerRolls` is incremented on the server and the charged roll is decided from
	  the incremented value. The client PREDICTS which roll is charged so it can draw the meter;
	  a client that predicts wrong gets a correct roll and a wrong meter, which is the right way
	  round for a disagreement.
	* THE RATE. One roll per `ROLL_INTERVAL` per player. The reveal alone is longer than that, so
	  it never fires for an honest player and always fires for a loop.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local SplicerService = {}

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Bump to force the machine to be rebuilt on the next server start. Stamped on the model, the
-- same trick RebirthShrine and ZoneBuilder use -- without it no change to the geometry below
-- would ever appear on a place that has already been played.
-- 1 -> 2: the look pass (dark outline geometry, indigo body, two-hue helix). A version that does
-- not move means the machine already standing in a played world is never replaced, so the change
-- is invisible -- the same silent no-op ZoneBuilder's BUILD_VERSION exists to prevent.
-- 4 -> 5 (12.13): NOT a geometry change. The machine was standing INSIDE the event board -- its
-- bounding box spanned x 132..160 against a sign panel at x 148.5..151.5 on the same z -- because
-- SplicerService.Init ran BEFORE EventService.Init, so `findClearSpot` searched a Forest that did
-- not have the sign in it yet. The ordering is fixed in ServerMain; this bump is what makes an
-- already-built world re-run the search instead of keeping the machine where it is. A placement
-- search only ever answers about the world that exists at the moment it runs, so moving the call
-- and moving the version are ONE change -- either alone does nothing.
-- 5 -> 6 (2026-08-17): the machine is TWICE THE SIZE and its prompt reaches four times as far.
-- Both halves are the same bug and it is a bug about the PLAYER, not about this file. A max-stage
-- body is BodyScale 5, i.e. a bounding box of 45 x 42 x 35 studs -- bigger than the whole machine,
-- which measured 27 x 25 x 27. Standing next to it the player could not see it, and could not reach
-- it either: `MaxActivationDistance` was 16 while the character's own half-width is ~22, so its
-- collision stopped it further out than the prompt could ever fire. The machine was not broken; it
-- had simply become unreachable as the bodies around it grew. Same rule as the boss reach note in
-- `CombatClient`: reach > (structure half-width + player half-width).
-- 6 -> 7 (2026-08-19, roadmap 19.9): the placement search was siting the machine against creatures.
-- `body_geom` walks, so a mob standing on the preferred spot at `Init()` pushed the build a whole
-- ring -- and to a different ring every boot: measured at (120, 30), (328, 498), (-192, 290) and
-- (380, 290) on four consecutive starts, 260 to 312 studs from home. Creatures are excluded by
-- folder and the occupancy test now also requires `Anchored`. A played world keeps the model it
-- already has, so this bump is the half of the fix that makes the other half happen at all.
-- 7 -> 8 (same row, after the capture): 7 was not enough and the screenshot is what said so. The
-- authored spot it chose, (-72, 312), passed every test in this file and stood 11.4 studs THROUGH
-- the Forest arrival board -- because a board is `CanCollide = false` and an occupancy test only
-- sees solids. Signage is now rejected by shape, and the spot list was re-probed against that rule.
local MACHINE_VERSION = 8

-- ===== HOW BIG =====
-- Applied with `Model:ScaleTo` at the end of `buildMachine` rather than by rewriting the sixty-odd
-- authored dimensions below, so the geometry stays readable and the outline lips keep their exact
-- proportion to the masses they rim. Everything downstream that cares about the size reads it back
-- off the model with `:GetScale()` instead of assuming 1.
--
-- 2 puts it at 55 x 50 x 55 -- a head taller than a max-stage player rather than knee-high to one --
-- and keeps the footprint clear of both the street (STREET_HALF) and the rebirth plaza at x 225.
local MACHINE_SCALE = 2

-- Seconds between two rolls from one player. The client's own reveal runs ~2.4 s.
local ROLL_INTERVAL = 1.2

-- ===== WHERE IT STANDS =====
-- Forest, whose platform is centred on x = 0 with its top face at y = 0. The street runs down Z
-- at x = +-38 (lamps, benches, planters), the three leaderboard boards stand at x = -130 over
-- z = 140..300, and the rebirth plaza occupies x = 225..375. This is the gap between the street
-- and that plaza, in plain sight of the spawn walk-down and standing on nothing.
--
-- The exact spot is SEARCHED rather than asserted (see `findClearSpot`): Forest's scatter props
-- are placed by a builder that does not know this file exists, and a machine standing inside a
-- conifer is the kind of thing that only ever gets noticed in a screenshot.
-- z MOVED 215 -> 290 (12.13). 215 is the event sign's own z, so the preferred spot was on the one
-- line the sign is read along -- see SIGN_CLEAR below, which now rejects it outright. Left at 215
-- the search would still find somewhere legal, but every legal answer inside two rings is either
-- behind the sign or 52 studs out, and neither is a spot anybody chose. 290 is the same east verge,
-- 75 studs nearer the spawn at (0, 1, 366): more of the walk-down, not less, which is the reason
-- this machine is on this side of the street in the first place.
--
-- IT IS A LIST NOW, AND ONE POINT WAS NEVER ENOUGH (19.9). Forest's props are `math.random`-placed
-- and re-rolled on every world rebuild, so no single coordinate is ever "the clear one" -- it is a
-- coordinate whose luck is re-rolled with the world. Measured on this world: (120, 290) is covered
-- by a `ForestTree` and two `PropBOULDER`s, and a grid scan of the whole plaza deck at the
-- machine's real footprint found **23 clear spots and every one of them on the WEST verge** -- the
-- east side was full from x = 40 to x = 180. So the ring search did what it was told, walked
-- between 221 and 312 studs, and landed somewhere different on all four boots it was watched on.
--
-- Same answer HubPlaza reached for the same reason (see its `PHOTO_SPOTS`): a composition is a
-- LIST of real choices, and the search is the floor under it rather than the thing that decides.
-- Every spot below was probed against the live world at the full footprint. All four sit on the
-- plaza deck (x -172..172, z 80..416), outside the 30-stud corridor and inboard of the lamp line
-- at x = +-84 -- which is the verge, and is where this machine has always belonged.
local PREFERRED_SPOTS = {
	-- The authored east-verge spot, kept FIRST because the argument above is still the right one on
	-- any world where it is clear: it faces the walk-down and it is the side the machine was sited
	-- on. It is simply not clear on every world.
	Vector3.new(120, 0, 290),
	-- West outer verge near the gate end. The nearest spot to the spawn walk-down that survives
	-- every rule below, signage included.
	Vector3.new(-156, 0, 384),
	-- West verge, south. Open on every world probed.
	Vector3.new(-72, 0, 168),
	Vector3.new(-84, 0, 160),
}
-- The ring search still steps out from here when every authored spot is unlucky at once.
local PREFERRED = PREFERRED_SPOTS[1]
-- The footprint the placement search has to find empty, and it has to grow WITH the machine or the
-- search happily clears a 30-stud box and then a 60-stud machine is built through a conifer.
local FOOTPRINT = Vector3.new(30, 26, 30) * MACHINE_SCALE

-- ===== THE GROUND THIS MACHINE MAY CLAIM, PUBLISHED FOR THE FILES THAT DRAW ROADS (34.65) =====
-- `JungleTrails` opens the village's only north doors on `HubPlaza`'s deck, and one of them stood
-- at (-150, 390) -- INSIDE this machine's 60-stud footprint at the second authored spot. A trail
-- did not merely cross the machine, it BEGAN inside it, and every camp that hung off that door
-- radiated another sheet of paint through the same box: measured on a live build, 29 road sheets
-- through the machine's solid 52 x 52, nearest sheet centre 8.5 studs. The other three authored
-- spots carry 4, 0 and 0.
--
-- THE DOOR MOVES, NOT THE LANDMARK, and the measurement is what decides that. A grid of the whole
-- plaza deck at this footprint answers: 25 spots clear of props, signs, the street and the event
-- sightline -- and NOT ONE of them clear of road paint, not even against a 12-stud driving line.
-- `MapForest` keeps its trees out of the road segments, so on this deck *clear of props* and *on a
-- road* are the same ground. A road veto in `findClearSpot` therefore has nowhere to send this
-- machine but off the deck, which is exactly what it did when it was tried: 294 studs, to (-88,
-- 498). A plaza is paved; standing on paint is not the fault. A road STARTING inside the machine is.
--
-- So the ground is published from the file that owns the machine, the same shape and for the same
-- reason as `MapGates.PaintKeepOut()`: one file decides where this thing may stand. ALL FOUR spots
-- are published, not the one in use -- Forest's props are `math.random`-placed and re-rolled on
-- every world build, so which spot wins is re-rolled with them, and a door that is only clear of
-- today's answer is clear by luck.
--
-- Callable WITHOUT `Init`: it reads nothing but the two constants above, so the road files may ask
-- it while the world is still being built and this service has not started.
function SplicerService.PlacementKeepOut()
	local out = {}
	for i, spot in ipairs(PREFERRED_SPOTS) do
		out[#out + 1] = {
			id = "Splicer" .. i,
			x = spot.X, z = spot.Z,
			hx = FOOTPRINT.X * 0.5, hz = FOOTPRINT.Z * 0.5,
		}
	end
	return out
end

-- How close a player has to be for the helix to turn. Squared, because this is compared in a
-- loop and a square root per player per tick buys nothing. Scaled too: this is a distance to a
-- landmark, and a bigger landmark is legible from further away.
local ANIMATE_RANGE_SQ = (90 * MACHINE_SCALE) * (90 * MACHINE_SCALE)

-- ===== PALETTE =====
-- The first build of this machine was pale steel and light blue, and against Forest's bright green
-- lawn it read as a flat pastel box -- the exact failure the world look pass was run to fix. Two
-- things were wrong and they are the project's own rules: the body had no dark value anywhere in
-- it, and nothing carried an outline.
--
-- Scenery CANNOT use a Highlight for that outline. Roblox draws about 31 at once and the running
-- game already spends them on the player's own pets and characters, so a machine that took one
-- would silently steal it from the one place it matters (the note over `buildEggPlaza` in
-- ZoneBuilder says exactly this). Scenery outlines are built from GEOMETRY -- see `edged` in
-- buildMachine for the shape that actually works, and for the two that did not.
--
-- AND THE OUTLINE ONLY WORKS IF THE BODY IS BRIGHT. The dark build got this backwards: a deep
-- indigo body (56, 52, 104) against a near-black edge are the same VALUE, so the two merged and
-- the machine read as one black blob -- worse than the pale version it replaced. An outline is a
-- boundary between two values; it needs something light on the other side of it. The body is a
-- vivid violet from the same candy family the HUD tiles use.
local OUTLINE    = Color3.fromRGB(18, 16, 34)    -- near-black, never pure black
local BODY       = Color3.fromRGB(146, 116, 240) -- vivid violet: the mass the outline draws around
local BODY_LITE  = Color3.fromRGB(186, 160, 250)
local STEEL_LITE = Color3.fromRGB(198, 202, 224)
local GLASS_TINT = Color3.fromRGB(150, 225, 255)
local ACCENT     = Color3.fromRGB(90, 240, 255)  -- cyan strand + trim
local ACCENT2    = Color3.fromRGB(255, 96, 205)  -- magenta strand, the other half of the helix

local lastRoll = {}
-- every part of the helix, with the offset it sits at when the machine is unturned
local helix = {}
local helixPivot = nil
local machineModel = nil

-- ===== PART VOCABULARY =====
-- A local copy rather than a require of ZoneBuilder's, for the reason RebirthShrine gives for
-- having its own: that module is thousands of lines and rebuilds tens of thousands of parts
-- behind a version stamp of its own. This one builds under a hundred and owns them.
local function newPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	return p
end

-- ===== FINDING GROUND NOTHING IS STANDING ON =====
-- Steps out from `PREFERRED` along a widening ring and takes the first spot whose footprint is
-- empty of anything solid. Returns the preferred spot if every candidate is occupied, because a
-- machine in the wrong place is recoverable and no machine at all is not.
--
-- EMPTY IS NOT THE SAME AS AVAILABLE (found 12.10, on a rebuilt world). Forest's props are placed
-- with math.random, so a rebuild moves them and this search answers differently each time -- and on
-- one of those worlds every candidate inside four rings was occupied and the machine walked 104
-- studs to x = 16, i.e. into the middle of the street. It was a legal answer: the path slabs are
-- 0.16 high and the fence run has gaps, so that footprint really was clear of anything solid. The
-- street is not clear GROUND, it is the line every player walks, so it is ruled out by name rather
-- than left to the occupancy test. Same constant and same reasoning as HubPlaza's CORRIDOR_HALF.
local STREET_HALF = 30

-- A SIGN IS NOT ITS PANEL, IT IS ITS PANEL PLUS THE LINE YOU READ IT ALONG (12.13). Fixing the
-- init order stopped the machine from being built INSIDE the event board, and the very next build
-- put it 30 studs west of the board instead -- on the board's own -X reading face, between the sign
-- and the street it was sited to be read from. The occupancy test cannot object: standing in front
-- of something is not touching it, and every part of both structures is exactly where it was asked
-- to go.
--
-- So the sightline is reserved BY NAME, the same way the street is above and for the same reason:
-- some space is unavailable for a reason no geometric test can discover. x stops at the panel
-- because behind the sign is not in front of it, and the z band is the panel's own 34-stud width
-- pulled in two studs at each end -- clipping the far corner of a sign you are reading head-on
-- costs nothing, and a rule that rejects that too pushes the machine 52 studs for no gain.
local SIGN_CLEAR = { xMin = 40, xMax = 150, zMin = 200, zMax = 230 }

-- ===== WHAT COUNTS AS A ROAD, AND HOW WIDE THE PART OF IT PEOPLE WALK DOWN IS (34.65) =====
-- The three part names `MapPaint` draws a road with. Named rather than measured, for the same
-- reason the street and the sightline are: road paint is `CanCollide = false`, so no occupancy
-- test in this file can ever object to it, and a rule about traffic cannot be discovered from
-- geometry.
--
-- `DRIVING_LINE` is deliberately far narrower than a trail (30) or a lane (46..56). The whole
-- point of this row's measurement is that on the plaza deck a road's PAINT is under everything --
-- 0 of 25 prop-clear spots are free of it -- so touching paint cannot be the test. Standing in the
-- middle of the lane can be, and 12 studs is a stud and a half either side of an 8.4-stud body.
local ROAD_PAINT = { PaintRoad = true, PaintCap = true, PaintDisc = true }
local DRIVING_LINE = 12

-- ===== THE TWO QUESTIONS THE PLACEMENT ASKS, BUILT ONCE OFF THE WORLD AS IT STANDS (34.66) =====
-- They used to be locals inside the search. They are lifted out because the search is no longer the
-- only thing that asks them: before it runs, `reserveAuthoredSpot` has to know which authored spot
-- is worth clearing -- an occupied spot with a road through it is worth nothing, since the search
-- would refuse it after the clearing exactly as it refuses it now.
--
-- Built once and shared, because `signage` walks every descendant of `workspace` and this world has
-- forty thousand parts in it. Neither closure caches its ANSWER -- `spotIsClear` queries the live
-- world on every call, which is what lets the same predicate be asked again after props have moved.
local function placementRules()
	-- CREATURES ARE NOT OBSTRUCTIONS, AND LEAVING THEM IN HERE IS WHY THIS MACHINE MOVED HOUSE ON
	-- EVERY BOOT. Measured 2026-08-19 on a live server: the only things this test found standing on
	-- the preferred spot were two `body_geom` parts -- a creature, mid-walk. Four consecutive boots
	-- sent the machine to (120, 30), (328, 498), (-192, 290) and (380, 290), between 260 and 312
	-- studs away and never twice to the same place, because the blocker was somewhere different
	-- each time. A landmark the player is meant to FIND cannot be sited by where a mob happened to
	-- be standing at `Init()`.
	--
	-- Excluded by folder, and then the loop below also requires `Anchored`. The folder is the cheap
	-- explicit half; the anchored test is the general rule, and it is the one that matters: a part
	-- that is not anchored is not a fact about the place, it is a fact about this instant. Same
	-- reasoning as the creature filter the 12.13 sightline measurement needed.
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { machineModel, workspace:FindFirstChild("Creatures") }

	-- A SIGN IS INVISIBLE TO AN OCCUPANCY TEST, BECAUSE A SIGN IS NOT SOLID. Found the honest way
	-- (19.9): the first cut of this list put the machine at (-72, 312), the occupancy test called
	-- it clear, and the capture showed it standing THROUGH the Forest arrival board -- measured, an
	-- 11.4-stud intersection. `ArrivalSignBoard` is `CanCollide = false`, like every board, banner
	-- and plank surface in this game, so the test above could never have objected.
	--
	-- This is 12.13's rule one step further out. That row reserved the event sign's SIGHTLINE by
	-- name; this reserves every sign's own BODY by shape, which needs no name and no coordinates.
	-- Raised, because "Board" and "Plank" are also what the deck underfoot is made of, and a thing
	-- you read is a thing at eye height.
	local signage = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("BasePart") and d.Anchored and d.Position.Y > 8
			and (d.Name:find("Sign") or d.Name:find("Board") or d.Name:find("Banner")) then
			table.insert(signage, d)
		end
	end

	-- ===== THE ROAD SHEETS, ASKED OF THE WORLD RATHER THAN OF A SECOND MODEL OF IT (34.65) =====
	-- `JungleLayout` owns where the roads are, but it requires `SplicerService.PlacementKeepOut`
	-- above, so requiring it back from here would be a cycle. It is not needed: this runs long
	-- after `ForestMapService.Init`, so the paint is standing in the world and can be measured
	-- where it lies. That is the better source anyway -- it is the sheets the player walks on and
	-- not a plan of the sheets that were meant to be drawn.
	local roads = {}
	for _, root in ipairs({ workspace:FindFirstChild("Zones"), workspace:FindFirstChild("Map") }) do
		if root then
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("BasePart") and ROAD_PAINT[d.Name] then
					local cf = d.CFrame
					local u = Vector2.new(cf.RightVector.X, cf.RightVector.Z)
					local v = Vector2.new(cf.LookVector.X, cf.LookVector.Z)
					table.insert(roads, {
						c = Vector2.new(cf.Position.X, cf.Position.Z),
						u = (u.Magnitude > 1e-4) and u.Unit or Vector2.new(1, 0),
						v = (v.Magnitude > 1e-4) and v.Unit or Vector2.new(0, 1),
						hu = d.Size.X * 0.5, hv = d.Size.Z * 0.5,
					})
				end
			end
		end
	end

	-- Does any road's DRIVING LINE cross this footprint? Separating axes, because a trail sheet is
	-- rotated to its bearing and its world bounding box reaches well past its corners -- an
	-- axis-picked box test lies exactly there. The sheet's short side is pulled in to
	-- `DRIVING_LINE` first: the question is not whether the machine touches paint (on this deck
	-- everything does) but whether it stands in the part of the road people walk down.
	local function roadsThrough(centre)
		local h = FOOTPRINT.X * 0.5
		local p = Vector2.new(centre.X, centre.Z)
		local n = 0
		for _, r in ipairs(roads) do
			local hu, hv = r.hu, r.hv
			if hu < hv then
				hu = math.min(hu, DRIVING_LINE * 0.5)
			else
				hv = math.min(hv, DRIVING_LINE * 0.5)
			end
			local d = p - r.c
			local sep = false
			for _, a in ipairs({ { r.u, hu }, { r.v, hv } }) do
				if math.abs(d:Dot(a[1])) > a[2] + h * (math.abs(a[1].X) + math.abs(a[1].Y)) then
					sep = true
					break
				end
			end
			if not sep then
				for _, axis in ipairs({ Vector2.new(1, 0), Vector2.new(0, 1) }) do
					if math.abs(d:Dot(axis)) > h + hu * math.abs(r.u:Dot(axis)) + hv * math.abs(r.v:Dot(axis)) then
						sep = true
						break
					end
				end
			end
			if not sep then n += 1 end
		end
		return n
	end

	-- Returns `clear, why`. The reason exists for 34.66: only a spot refused for something STANDING
	-- on it is worth asking the map to clear, and moving the artist's trees off a spot that the
	-- street or the event sign's sightline would refuse anyway is work done for nothing.
	local function spotIsClear(centre)
		local blocked = math.abs(centre.X) - FOOTPRINT.X * 0.5 < STREET_HALF
		local why = blocked and "the street" or nil
		-- the event sign's sightline, rejected before the occupancy test because no occupancy test
		-- can see it -- see SIGN_CLEAR
		if not blocked then
			local x0, x1 = centre.X - FOOTPRINT.X * 0.5, centre.X + FOOTPRINT.X * 0.5
			local z0, z1 = centre.Z - FOOTPRINT.Z * 0.5, centre.Z + FOOTPRINT.Z * 0.5
			blocked = x0 < SIGN_CLEAR.xMax and x1 > SIGN_CLEAR.xMin
				and z0 < SIGN_CLEAR.zMax and z1 > SIGN_CLEAR.zMin
			if blocked then why = "the event sign's sightline" end
		end
		if not blocked then
			local box = CFrame.new(centre + Vector3.new(0, FOOTPRINT.Y / 2, 0))
			local hits = workspace:GetPartBoundsInBox(box, FOOTPRINT, params)
			for _, part in ipairs(hits) do
				-- The floor is not an obstruction; everything standing ON it is -- as long as it is
				-- STILL there a minute from now. `Anchored` is the general form of the creature
				-- filter above: a part that can move is a fact about this instant, not about the
				-- place, and siting a landmark against one gives a different answer every boot.
				if part.CanCollide and part.Anchored and part.Position.Y > 0.5 then
					blocked = true
					why = "a prop"
					break
				end
			end
		end
		-- and the signage the box test cannot see -- compared in plan view, because a machine and a
		-- sign that share ground share it at every height a player looks from
		if not blocked then
			for _, s in ipairs(signage) do
				local sh = s.Size / 2
				if (FOOTPRINT.X * 0.5 + sh.X) - math.abs(s.Position.X - centre.X) > 0
					and (FOOTPRINT.Z * 0.5 + sh.Z) - math.abs(s.Position.Z - centre.Z) > 0 then
					blocked = true
					why = "a sign"
					break
				end
			end
		end
		return not blocked, why
	end

	return spotIsClear, roadsThrough
end

-- ===== WHERE THE MACHINE MAY STAND, GIVEN THE WORLD THAT WAS BUILT AROUND IT =====
local function findClearSpot(spotIsClear, roadsThrough)
	-- The authored spots first, in order, each one a real choice. Only when all four are unlucky at
	-- once does the ring search step out from the first -- and then it is a safety net rather than
	-- the thing choosing where a landmark stands.
	local candidates = {}
	for _, spot in ipairs(PREFERRED_SPOTS) do
		table.insert(candidates, spot - PREFERRED)
	end
	for ring = 1, 6 do
		-- the step is one footprint wide, so consecutive rings do not overlap each other
		local step = ring * 26 * MACHINE_SCALE
		table.insert(candidates, Vector3.new(step, 0, 0))
		table.insert(candidates, Vector3.new(-step, 0, 0))
		table.insert(candidates, Vector3.new(0, 0, step))
		table.insert(candidates, Vector3.new(0, 0, -step))
		table.insert(candidates, Vector3.new(step, 0, step))
		table.insert(candidates, Vector3.new(-step, 0, step))
	end

	-- ===== A ROAD IS A PREFERENCE HERE AND NEVER A VETO (34.65) =====
	-- Two passes over the SAME list, and the difference between them is the whole row. The first
	-- asks for an authored spot with no road driving through it; the second is exactly the search
	-- this file has always run. A veto was built instead, once, and it is why this is a preference:
	-- with 0 of 25 prop-clear spots on the deck free of road paint, "reject and keep looking" is a
	-- rejection of the entire deck, and the ring search then walked 294 studs to (-88, 498) --
	-- off the plaza, off the composition, somewhere nobody chose. A landmark in the wrong place is
	-- worse than a landmark on a paved street.
	--
	-- THE AUTHORED SPOTS COME FIRST EVEN WHEN A RING SPOT WOULD BE CLEANER, which is why this is
	-- three passes and not a score. Being where somebody put it is worth more than being road-free
	-- -- the ring is a safety net, and a net that outranks the composition is not a net.
	for index = 1, #PREFERRED_SPOTS do
		local centre = PREFERRED + candidates[index]
		if spotIsClear(centre) and roadsThrough(centre) == 0 then
			return centre, candidates[index].Magnitude, true, 0
		end
	end
	-- Then the same question of the ring. Worth its own pass and not folded into the last one,
	-- because the whole deck is paved and a search that takes the FIRST empty box takes a road
	-- corridor by default: measured on a live build, of 6,000 grid positions across the deck at
	-- this footprint, exactly FOUR are clear of both props and a driving line -- one 12-stud pocket
	-- at z = 290. The old search found it by luck on the boot this was written on. This finds it
	-- because it is looking.
	for index = #PREFERRED_SPOTS + 1, #candidates do
		local centre = PREFERRED + candidates[index]
		if spotIsClear(centre) and roadsThrough(centre) == 0 then
			return centre, candidates[index].Magnitude, false, 0
		end
	end
	-- And then exactly what this file has always done. Reached when the deck has no road-free
	-- ground the machine fits on at all, which is a real state on some world rolls and not a fault:
	-- a landmark standing on a paved street is what a plaza looks like.
	for index, offset in ipairs(candidates) do
		local centre = PREFERRED + offset
		if spotIsClear(centre) then
			return centre, offset.Magnitude, index <= #PREFERRED_SPOTS, roadsThrough(centre)
		end
	end
	return PREFERRED, -1, false, roadsThrough(PREFERRED)
end

-- ===== ASKING THE MAP TO GIVE AN AUTHORED SPOT BACK (34.66) =====
--
-- 34.65 closed with the machine standing 52 studs off its first authored spot, on ground the ring
-- search picked, because on that world roll ALL FOUR authored spots were occupied: a camp's
-- backstop rocks on the first, a horizon collider's corner on the second, and the artist's own
-- trees on the third and fourth. The two collider systems now keep off this machine's ground
-- (`JungleLayout.FixtureClearance`, honoured by `MapJungle` and `MapHorizon`), which leaves the
-- village's trees -- and a tree is not a thing this file may simply refuse around: it was placed by
-- the map's author and `evolution-lab-map-owns-the-furniture` is why we do not delete it.
--
-- So it is MOVED, by the file whose whole job is moving a village prop out of the way, and only
-- when doing so actually buys the spot:
--
--   * a spot with a road driving through it is skipped, because the search would refuse it after
--     the clearing exactly as it refuses it now -- clearing it would move trees for nothing;
--   * a spot refused by the street or by the event sign's sightline is skipped for the same reason,
--     which is what `spotIsClear`'s second return value is for;
--   * `MapClearance.Reserve` is all-or-nothing: it refuses before it touches anything if the box
--     holds architecture or a collider it may not move, so a half-cleared spot cannot happen;
--   * and the answer is verified against the world afterwards rather than trusted. `Reserve` sees
--     only the map's own top-level props; `spotIsClear` sees everything.
--
-- THE FIRST ROAD-FREE SPOT WINS, NOT THE FIRST SPOT. The list is a composition and its order is a
-- preference, but a spot the search will not take is not worth clearing -- so this walks the same
-- list in the same order and stops at the first one that clearing can actually deliver.
local ZONE_KEY = "Forest"

local function reserveAuthoredSpot(spotIsClear, roadsThrough)
	-- Nothing to do when the list already offers what the search wants.
	for _, spot in ipairs(PREFERRED_SPOTS) do
		if spotIsClear(spot) and roadsThrough(spot) == 0 then return nil end
	end

	-- Lazily required, and that is not a style choice: `ForestMapService` requires `MapJungle`,
	-- which requires `JungleLayout`, which requires THIS file -- so a require at the top of the page
	-- would be a load-time cycle. By the time `Init` runs, that module has long since been loaded
	-- and this is a registry lookup.
	local ForestMapService = require(script.Parent.ForestMapService)

	for i, spot in ipairs(PREFERRED_SPOTS) do
		local clear, why = spotIsClear(spot)
		if not clear and why == "a prop" and roadsThrough(spot) == 0 then
			local report = ForestMapService.ClearGround(ZONE_KEY, {
				x = spot.X, z = spot.Z,
				hx = FOOTPRINT.X * 0.5, hz = FOOTPRINT.Z * 0.5,
			}, ("the DNA Splicer's authored spot %d at (%d, %d)"):format(i, spot.X, spot.Z))
			if report and report.cleared and spotIsClear(spot) then
				print(("[SplicerService] authored spot %d at (%d, %d) was reserved: "
					.. "%d of the map's props carried off it")
					:format(i, spot.X, spot.Z, report.moved))
				return spot
			end
		end
	end
	return nil
end

-- ===== THE MACHINE =====
local function buildMachine(centre)
	local model = Instance.new("Model")
	model.Name = "DNASplicer"

	-- The outline helper: a near-black slab `grow` studs bigger on the two axes that face the
	-- camera, sitting exactly where the mass does. One call per mass, so nothing can be added
	-- later without one and quietly read as flat.
	-- ===== HOW A DARK EDGE IS ACTUALLY DRAWN ON A ROBLOX PART =====
	-- NOT by wrapping the mass in a bigger dark shell. That was the second attempt and it is
	-- geometrically hopeless: a part 0.4 studs bigger on all three axes ENCLOSES the one it is
	-- meant to outline, so every face you can see belongs to the shell and the body colour is
	-- never drawn at all. Both dark builds of this machine were that mistake -- the palette was
	-- fine and invisible.
	--
	-- The village crates and lamps do it the way that works: a bright mass with dark TRIM at its
	-- extremities -- a lip wider than the body under it, a cap over it. The dark reads as an edge
	-- because it is at the boundary, and the body keeps every face in between.
	local function edged(props, lip)
		local body = newPart(props)
		local g = lip or 0.9
		-- the lip: wider in X and Z, thin in Y, sunk just under the mass so it peeks out as a rim
		newPart({
			Name = (props.Name or "Part") .. "Lip",
			Size = Vector3.new(props.Size.X + g, 0.7, props.Size.Z + g),
			Position = props.Position - Vector3.new(0, props.Size.Y / 2, 0),
			Color = OUTLINE, Material = Enum.Material.SmoothPlastic,
			CanCollide = false, CastShadow = false, Parent = props.Parent,
		})
		return body
	end
	-- a matching cap, for masses that want an edge on top as well as underneath
	local function capped(props, lip)
		local body = edged(props, lip)
		local g = lip or 0.9
		newPart({
			Name = (props.Name or "Part") .. "Cap",
			Size = Vector3.new(props.Size.X + g, 0.7, props.Size.Z + g),
			Position = props.Position + Vector3.new(0, props.Size.Y / 2, 0),
			Color = OUTLINE, Material = Enum.Material.SmoothPlastic,
			CanCollide = false, CastShadow = false, Parent = props.Parent,
		})
		return body
	end

	-- ---- plinth: a wide violet base with a dark rim under it, then the lit deck stepped in on top
	edged({ Name = "PlinthRim", Size = Vector3.new(26, 1.4, 26),
		Position = centre + Vector3.new(0, 0.7, 0), Color = BODY,
		Material = Enum.Material.Metal, Parent = model }, 1.4)
	local deck = edged({ Name = "Plinth", Size = Vector3.new(22, 1.6, 22),
		Position = centre + Vector3.new(0, 1.9, 0), Color = BODY_LITE,
		Material = Enum.Material.Metal, Parent = model }, 1.0)
	model.PrimaryPart = deck

	-- a ring of lit floor tiles, so the machine has a footprint at night
	for i = 0, 7 do
		local a = (i / 8) * math.pi * 2
		newPart({ Name = "DeckLamp", Size = Vector3.new(2.6, 0.5, 2.6),
			Position = centre + Vector3.new(math.cos(a) * 8.6, 2.9, math.sin(a) * 8.6),
			Color = ACCENT, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	end

	-- ---- the two pillars the tube stands between
	for _, sx in ipairs({ -7.5, 7.5 }) do
		capped({ Name = "Pillar", Size = Vector3.new(5, 19, 7),
			Position = centre + Vector3.new(sx, 12.2, 0), Color = BODY,
			Material = Enum.Material.Metal, Parent = model }, 1.0)
		newPart({ Name = "PillarTrim", Size = Vector3.new(5.4, 1.8, 7.4),
			Position = centre + Vector3.new(sx, 21.6, 0), Color = ACCENT,
			Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		newPart({ Name = "PillarBand", Size = Vector3.new(5.4, 1.2, 7.4),
			Position = centre + Vector3.new(sx, 14.0, 0), Color = ACCENT2,
			Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		edged({ Name = "PillarFoot", Size = Vector3.new(6.4, 1.8, 8.4),
			Position = centre + Vector3.new(sx, 3.6, 0), Color = BODY_LITE,
			Material = Enum.Material.Metal, Parent = model }, 1.0)
	end

	-- ---- canopy
	capped({ Name = "Canopy", Size = Vector3.new(23, 2, 10),
		Position = centre + Vector3.new(0, 23.4, 0), Color = BODY,
		Material = Enum.Material.Metal, Parent = model }, 1.2)
	newPart({ Name = "CanopyLip", Size = Vector3.new(24.4, 1.1, 11.4),
		Position = centre + Vector3.new(0, 22.2, 0), Color = ACCENT,
		Material = Enum.Material.Neon, CanCollide = false, Parent = model })

	-- ---- the glass tube. Shape = Cylinder is drawn along its X axis, so it is turned upright
	-- rather than sized as if the axis were Y -- sizing it the other way makes a flat disc and is
	-- the same class of mistake as a non-uniform Ball.
	local tube = newPart({ Name = "Tube", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(17, 9.4, 9.4), Color = GLASS_TINT, Material = Enum.Material.Glass,
		Transparency = 0.62, CanCollide = false, CastShadow = false,
		CFrame = CFrame.new(centre + Vector3.new(0, 12.6, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Parent = model })
	newPart({ Name = "TubeCapLower", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.6, 10.6, 10.6), Color = STEEL_LITE, Material = Enum.Material.Metal,
		CFrame = CFrame.new(centre + Vector3.new(0, 4.4, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Parent = model })
	newPart({ Name = "TubeCapUpper", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.6, 10.6, 10.6), Color = STEEL_LITE, Material = Enum.Material.Metal,
		CFrame = CFrame.new(centre + Vector3.new(0, 20.8, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Parent = model })

	-- ---- the helix. Two strands and the rungs between them, which is the thing that makes the
	-- machine legible as a DNA splicer from across the plaza rather than as a lamp.
	-- Beads at 2.4 rather than 1.7: at the smaller size they vanished inside the tinted glass from
	-- more than a few studs away, which took the one shape that says "DNA" out of the silhouette.
	local BEADS, TURNS, RADIUS, SPAN = 13, 2.1, 3.0, 14.4
	helix = {}
	helixPivot = CFrame.new(centre + Vector3.new(0, 12.6, 0))
	for i = 0, BEADS - 1 do
		local t = i / (BEADS - 1)
		local a = t * math.pi * 2 * TURNS
		local y = (t - 0.5) * SPAN
		for strand = 0, 1 do
			local ang = a + strand * math.pi
			local bead = newPart({ Name = "HelixBead", Shape = Enum.PartType.Ball,
				Size = Vector3.new(2.4, 2.4, 2.4),
				-- two strongly separated hues, so the double helix reads as two strands rather
				-- than as a column of beads
				Color = strand == 0 and ACCENT or ACCENT2,
				Material = Enum.Material.Neon, CanCollide = false, CastShadow = false,
				Parent = model })
			-- Stored as an OFFSET from the pivot, not as a world CFrame: the driver below rebuilds
			-- every frame from `pivot * turn * offset`, which is an exact rotation. A tween would
			-- lerp the position and walk each bead across the chord instead of around the axis.
			local offset = CFrame.new(math.cos(ang) * RADIUS, y, math.sin(ang) * RADIUS)
			bead.CFrame = helixPivot * offset
			table.insert(helix, { part = bead, offset = offset })
		end
		-- a rung every other bead pair, or the tube fills up with bars
		if i % 2 == 0 then
			local rung = newPart({ Name = "HelixRung", Size = Vector3.new(RADIUS * 2, 0.42, 0.42),
				Color = STEEL_LITE, Material = Enum.Material.Neon, CanCollide = false,
				CastShadow = false, Parent = model })
			local offset = CFrame.new(0, y, 0) * CFrame.Angles(0, -a, 0)
			rung.CFrame = helixPivot * offset
			table.insert(helix, { part = rung, offset = offset })
		end
	end

	-- ---- the console you actually walk up to
	local console = edged({ Name = "Console", Size = Vector3.new(11, 4.6, 5),
		Position = centre + Vector3.new(0, 5.2, 8.6), Color = BODY,
		Material = Enum.Material.Metal, Parent = model }, 1.0)
	newPart({ Name = "ConsoleLip", Size = Vector3.new(11.6, 1.0, 5.6),
		Position = centre + Vector3.new(0, 7.6, 8.6), Color = ACCENT,
		Material = Enum.Material.Neon, CanCollide = false, Parent = model })

	-- The screen takes NO lip: it is already near-black, so it is its own dark edge against the
	-- violet console it is mounted on, and anything laid in front of its face hides the SurfaceGui.
	local screen = newPart({ Name = "Screen", Size = Vector3.new(9.4, 3.2, 0.4),
		Position = centre + Vector3.new(0, 5.6, 11.2), Color = Color3.fromRGB(16, 20, 30),
		Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.CanvasSize = Vector2.new(360, 120)
	sg.LightInfluence = 0
	sg.Parent = screen
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -12, 0.62, 0)
	title.Position = UDim2.new(0, 6, 0, 4)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.Text = "DNA SPLICER"
	title.TextColor3 = ACCENT
	title.TextScaled = true
	title.Parent = sg
	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, -12, 0.34, 0)
	sub.Position = UDim2.new(0, 6, 0.62, 0)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamMedium
	sub.Text = "Splice a mutation into your DNA"
	sub.TextColor3 = Color3.fromRGB(210, 226, 245)
	sub.TextScaled = true
	sub.Parent = sg

	local light = Instance.new("PointLight")
	light.Color = ACCENT
	light.Range = 34
	light.Brightness = 1.6
	light.Shadows = false
	light.Parent = tube

	-- ---- the prompt. `ShopPanel` is the same grammar every other counter in the game uses, and
	-- MainUI's handler looks the key up in a table that has no "splicer" row, so it falls through
	-- there and is picked up by SplicerUI instead.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SplicerPrompt"
	prompt.ActionText = "Splice"
	prompt.ObjectText = "DNA Splicer"
	prompt.HoldDuration = 0
	-- ===== 16 -> 70, AND 70 IS MEASURED, NOT PICKED =====
	-- `MaxActivationDistance` is NOT scaled by `Model:ScaleTo` -- prompts are not geometry -- so it
	-- has to be written here. The plinth rim is 27.4 studs across as authored, so 54.8 at scale 2 --
	-- a half-width of 27.4. A max-stage player's own half-width is ~22 and the rim's collision stops
	-- it before it can stand any closer than the sum, so nothing under 49.4 can EVER fire, which is
	-- exactly how 16 came to be unreachable. 70 clears that with margin and shows the prompt while
	-- the player is still walking in rather than snapping on at the last step. The other landmark
	-- prompts in this game sit in the same band (Pet Shop 42, PhotoPad 46) for smaller structures.
	prompt.MaxActivationDistance = 70
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("ShopPanel", "splicer")
	prompt.Parent = console

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end

	-- ===== THE SCALE PASS, AND THE THREE THINGS IT HAS TO PUT BACK =====
	--
	-- `Model:ScaleTo` does the geometry -- every part's Size, every offset between them, the light
	-- range and the particle sizes -- and that is the only reason the sixty-odd authored dimensions
	-- above are still written at their true scale-1 proportions instead of being multiplied by hand.
	--
	-- 1. IT DOES NOT LEAVE THE MACHINE ON THE GROUND. It scales about the model's pivot, and setting
	--    `WorldPivot` to the ground square under the machine was NOT enough on its own -- measured
	--    afterwards, the whole model came out 1.9 studs low and its base was 2.6 studs under the
	--    lawn. So the drop is MEASURED and undone rather than reasoned about: whatever the pivot
	--    turns out to be, the bottom of the bounding box ends up exactly where it started.
	-- 2. THE HELIX OFFSETS ARE STALE. They were captured above as `pivot:Inverse() * world`, from a
	--    world the scale has just moved. Left alone, the first heartbeat of `driveHelix` slams every
	--    bead back to its unscaled offset and the strands sit in a tight knot inside a tube twice
	--    their size. They are re-read from the geometry that now exists, which is exact.
	--    `helixPivot` IS the tube's centre -- that is what the authored 12.6 was -- so it is taken
	--    from the part instead of from an arithmetic that a future edit could silently invalidate.
	-- 3. IT DOES SCALE `MaxActivationDistance`, which was a surprise: prompts are not geometry, but
	--    the engine scales this one anyway, and the 70 set above came out as 140. Written again here,
	--    after the scale, so the number in the source is the number in the world.
	if MACHINE_SCALE ~= 1 then
		local cfBefore, sizeBefore = model:GetBoundingBox()
		local groundedAt = cfBefore.Position.Y - sizeBefore.Y * 0.5

		model.WorldPivot = CFrame.new(centre.X, 0, centre.Z)
		model:ScaleTo(MACHINE_SCALE)

		local cfAfter, sizeAfter = model:GetBoundingBox()
		local drop = (cfAfter.Position.Y - sizeAfter.Y * 0.5) - groundedAt
		if math.abs(drop) > 0.001 then
			model:TranslateBy(Vector3.new(0, -drop, 0))
		end

		local tube = model:FindFirstChild("Tube")
		helixPivot = CFrame.new(tube.Position)
		for _, entry in ipairs(helix) do
			entry.offset = helixPivot:Inverse() * entry.part.CFrame
		end

		prompt.MaxActivationDistance = 70
	end

	model:SetAttribute("MachineVersion", MACHINE_VERSION)
	return model
end

-- ===== THE HELIX TURNS, ON ONE HEARTBEAT, ONLY WHEN SOMEBODY IS THERE =====
-- One connection for the whole machine rather than one per part, and it does nothing at all while
-- the plaza is empty -- the rule every animated set in this game is held to.
local function driveHelix()
	local angle = 0
	local sinceCheck = 0
	local nearby = false
	RunService.Heartbeat:Connect(function(dt)
		sinceCheck += dt
		if sinceCheck >= 0.5 then
			sinceCheck = 0
			nearby = false
			for _, plr in ipairs(Players:GetPlayers()) do
				local char = plr.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if root and helixPivot and (root.Position - helixPivot.Position).Magnitude ^ 2 <= ANIMATE_RANGE_SQ then
					nearby = true
					break
				end
			end
		end
		if not nearby or not helixPivot then return end
		angle = (angle + dt * 0.9) % (math.pi * 2)
		local turn = CFrame.Angles(0, angle, 0)
		for _, entry in ipairs(helix) do
			entry.part.CFrame = helixPivot * turn * entry.offset
		end
	end)
end

-- ===== THE ROLL =====
-- The ONE place a mutation is written onto a save, for the reason `insertPet` is the one place a
-- pet is created: two writers is how two rules drift apart.
local function applyMutation(data, mutation)
	data.SplicerFound = data.SplicerFound or {}
	data.SplicerFound[mutation.name] = (data.SplicerFound[mutation.name] or 0) + 1

	local current = data.SplicerMutation and GameConfig.GetMutationByName(data.SplicerMutation)
	local equipped = false
	-- Index order IS rarity order in GameConfig.Mutations, so "better" is a plain index compare.
	local newIdx, curIdx = 0, 0
	for i, m in ipairs(GameConfig.Mutations) do
		if m.name == mutation.name then newIdx = i end
		if current and m.name == current.name then curIdx = i end
	end
	if newIdx > curIdx then
		data.SplicerMutation = mutation.name
		equipped = true
	end
	return equipped
end

-- ===== WEARING ONE YOU HAVE ALREADY FOUND (15.27) =====
--
-- The roll is best-kept-wins and was the ONLY writer of `data.SplicerMutation`, so a collection of
-- seven auras had exactly one reachable state: the best one you had ever rolled. The Auras panel
-- adds the other six, and it is a real choice rather than a downgrade button -- both stats rise
-- together with rarity, so the reason to wear a weaker one is the LOOK of it (the particle aura on
-- the body is the mutation's colour). The cost of that choice is never hidden: the row prints the
-- multiplier it is about to cost you, and 15.24's boost card keeps printing the one you are on.
--
-- Best-kept-wins is untouched by this. A later roll still compares against whatever is worn, so a
-- player wearing Common for the look is auto-upgraded by the next Rare -- which is the correct
-- reading of "a roll that lands better than what you have on".
local lastEquip = {}
local EQUIP_INTERVAL = 0.25
function SplicerService.HandleEquipMutation(player, mutationName)
	local PlayerDataService = require(script.Parent.PlayerDataService)
	local EvolutionVisuals = require(script.Parent.Systems.EvolutionVisuals)

	if type(mutationName) ~= "string" then return end
	local now = os.clock()
	local last = lastEquip[player.UserId]
	if last and now - last < EQUIP_INTERVAL then return end
	lastEquip[player.UserId] = now

	local data = PlayerDataService.Get(player)
	if not data then return end

	-- OWNERSHIP IS THE WHOLE GUARD, and it is a count rather than a truthiness test: `SplicerFound`
	-- holds how many of each have been rolled, and a 0 left behind by any future write is "not
	-- found" while `not 0` is false in Luau.
	local found = data.SplicerFound
	if not found or (found[mutationName] or 0) <= 0 then
		warn(("[SplicerService] %s tried to wear an unfound mutation: %s"):format(player.Name, mutationName))
		return
	end
	local mut = GameConfig.GetMutationByName(mutationName)
	if not mut then return end
	if data.SplicerMutation == mutationName then return end

	data.SplicerMutation = mutationName

	-- THE SAME THREE LINES HandleRoll RUNS WHEN A ROLL EQUIPS ITSELF, and each one is load-bearing:
	--  * the ATTRIBUTE is the replication channel, not the save. `EvolutionVisuals.WornMutation`
	--    reads `player:GetAttribute("Mutation")` FIRST and only falls back to the save when it is
	--    nil -- and the join path stamps it -- so writing the save alone leaves the old aura burning
	--    on the body for the rest of the session. Stamping it also fires the attribute hook in
	--    EvolutionVisuals.Init, which is what rebuilds the aura without a respawn.
	--  * RefreshBonuses is the walk speed: `speedPct` is applied by applyMastery, which recomputes
	--    the whole product rather than adding a delta.
	--  * PushToClient is what redraws the Auras panel and 15.24's boost card. Without it the panel
	--    still catches up on the next periodic push, seconds after a button the player just pressed.
	player:SetAttribute("Mutation", mutationName)
	EvolutionVisuals.RefreshBonuses(player, data)
	PlayerDataService.PushToClient(player)

	Remotes.Notify:FireClient(player, {
		kind = "reward",
		message = ("\u{1F9EC} Now wearing the %s aura! x%.2f DNA, +%d%% speed")
			:format(mut.name, mut.incomeMult, mut.speedPct),
	})
end

function SplicerService.HandleRoll(player)
	local PlayerDataService = require(script.Parent.PlayerDataService)
	local EvolutionVisuals = require(script.Parent.Systems.EvolutionVisuals)
	local AnnounceService = require(script.Parent.AnnounceService)

	local data = PlayerDataService.Get(player)
	if not data then return end

	local now = os.clock()
	local last = lastRoll[player.UserId]
	if last and now - last < ROLL_INTERVAL then return end
	lastRoll[player.UserId] = now

	local cost = GameConfig.GetSplicerRollCost(data)
	if (data.DNA or 0) < cost then
		-- Two messages, deliberately: the toast is the WORDING and goes through the same Notify
		-- stack every refusal in the game uses (so it queues, ranks and sounds like the others),
		-- while SpliceResult tells the panel to re-read itself. Neither does the other's job.
		Remotes.Notify:FireClient(player, { kind = "error", message = "Not enough DNA to splice!" })
		Remotes.SpliceResult:FireClient(player, { ok = false, reason = "poor", cost = cost })
		return
	end

	data.DNA -= cost
	local Telemetry = require(script.Parent.Telemetry)
	Telemetry.Economy(player, "Sink", Telemetry.Currency.DNA, cost, data.DNA,
		Telemetry.Tx.Shop, "splice")
	data.SplicerRolls = (data.SplicerRolls or 0) + 1

	-- The pity roll is decided from the INCREMENTED count, so the tenth roll is charged rather
	-- than the eleventh -- the client's meter counts the same way.
	local S = GameConfig.Splicer
	local charged = (data.SplicerRolls % S.pityEvery) == 0
	local mutation = GameConfig.RollMutation(GameConfig.GetSplicerLuck(data, charged))
	if charged then
		-- A charged roll is a floor, not a reroll: it cannot make a result worse than it landed.
		local idx = 0
		for i, m in ipairs(GameConfig.Mutations) do
			if m.name == mutation.name then idx = i end
		end
		if idx < S.pityMinIndex then
			mutation = GameConfig.Mutations[S.pityMinIndex]
		end
	end

	-- 20.3: the roll, not the equip -- a mutation the player already had a better copy of is still
	-- a roll they paid for, and the interesting number is how often the machine is used.
	Telemetry.Custom(player, "MutationRolled", charged and 1 or 0)
	local equipped = applyMutation(data, mutation)
	if equipped then
		-- The one replication channel the aura and the walk speed both read.
		player:SetAttribute("Mutation", mutation.name)
		EvolutionVisuals.RefreshBonuses(player)
	end
	PlayerDataService.PushToClient(player)

	local idx = 0
	for i, m in ipairs(GameConfig.Mutations) do
		if m.name == mutation.name then idx = i end
	end

	Remotes.SpliceResult:FireClient(player, {
		ok = true,
		name = mutation.name,
		color = mutation.color,
		index = idx,
		incomeMult = mutation.incomeMult,
		speedPct = mutation.speedPct,
		equipped = equipped,
		spent = cost,
		rollIndex = data.SplicerRolls,
		charged = charged,
		nextCost = GameConfig.GetSplicerRollCost(data),
	})

	if idx >= S.announceMinIndex then
		AnnounceService.MutationRolled(player, mutation)
	end
end

function SplicerService.Init()
	local PlayerDataService = require(script.Parent.PlayerDataService)

	for _, name in ipairs({ "SpliceRoll", "SpliceResult", "EquipMutation" }) do
		if not Remotes:FindFirstChild(name) then
			local r = Instance.new("RemoteEvent")
			r.Name = name
			r.Parent = Remotes
		end
	end

	local map = workspace:FindFirstChild("Map")
	if not map then
		map = Instance.new("Folder")
		map.Name = "Map"
		map.Parent = workspace
	end

	-- Rebuilt by replacement rather than patched in place: a stamped model whose version has moved
	-- is not the same machine, and reconciling it piece by piece is how half-old geometry survives.
	local existing = map:FindFirstChild("DNASplicer")
	if existing and existing:GetAttribute("MachineVersion") ~= MACHINE_VERSION then
		existing:Destroy()
		existing = nil
	end

	if existing then
		machineModel = existing
		-- WAS `Plinth.Position + 10.7`, which is the tube's centre expressed as an authored offset
		-- from a different part -- correct at scale 1 and wrong at every other scale, and wrong again
		-- the first time anything moves the plinth. The tube IS the axis the helix turns on, so it is
		-- read directly and the machine's own size never enters into it.
		local pivot = existing:FindFirstChild("Tube")
		if pivot then
			helixPivot = CFrame.new(pivot.Position)
		end
		helix = {}
		for _, d in ipairs(existing:GetDescendants()) do
			if d.Name == "HelixBead" or d.Name == "HelixRung" then
				table.insert(helix, { part = d, offset = helixPivot:Inverse() * d.CFrame })
			end
		end
	else
		-- Built once and handed to both steps -- see `placementRules`. The reservation may move
		-- village props; neither closure holds a cached answer, so the search below re-reads the
		-- world it changed.
		local spotIsClear, roadsThrough = placementRules()
		reserveAuthoredSpot(spotIsClear, roadsThrough)
		local centre, moved, authored, roads = findClearSpot(spotIsClear, roadsThrough)
		machineModel = buildMachine(centre)
		machineModel.Parent = map
		-- Landing on the second or third AUTHORED spot is not a fault and must not be reported as
		-- one -- that is the list doing its job. Only the ring search having to step out is worth a
		-- warn, because that is the case where nobody chose where this machine ended up.
		if moved > 0 and authored then
			print(("[SplicerService] first spot taken; machine stands at authored spot (%d, %d)")
				:format(centre.X, centre.Z))
		elseif moved > 0 then
			warn(("[SplicerService] every authored spot was occupied; machine searched %.0f studs to (%d, %d)")
				:format(moved, centre.X, centre.Z))
		end
		-- ===== THE ROW'S OWN QUESTION, ASKED WHERE THE MACHINE ACTUALLY ENDED UP (34.65) =====
		-- `JungleTrails` can only report against the four spots the machine MIGHT take, which is a
		-- watch number by construction. This one knows which spot won, so it is allowed to be an
		-- alarm -- and it is the sentence the row was opened by: *the DNA Splicer stands in a road*.
		-- Zero is the answer the two-pass search above is trying to reach; anything else says the
		-- deck had no road-free authored ground on this world roll, which is a real state and not a
		-- bug, so it is a `print` with the number in it rather than a warn with a verdict in it.
		print(("[SplicerService] %d road driving line(s) through the machine at (%d, %d)")
			:format(roads or -1, centre.X, centre.Z))
	end

	-- Never streamed out: the machine is a landmark and a player who walked to it must find it
	-- there, not arriving a second later.
	machineModel.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	local prompt = machineModel:FindFirstChild("SplicerPrompt", true)
	if prompt then
		prompt.Triggered:Connect(function() end) -- the panel is opened client-side off the same prompt
	end

	Remotes.SpliceRoll.OnServerEvent:Connect(function(player)
		local ok, err = pcall(SplicerService.HandleRoll, player)
		if not ok then
			warn("[SplicerService] roll failed for " .. player.Name .. ": " .. tostring(err))
		end
	end)

	Remotes.EquipMutation.OnServerEvent:Connect(function(player, mutationName)
		local ok, err = pcall(SplicerService.HandleEquipMutation, player, mutationName)
		if not ok then
			warn("[SplicerService] equip failed for " .. player.Name .. ": " .. tostring(err))
		end
	end)

	driveHelix()

	-- ===== THE ONE-TIME REFUND NOTICE =====
	-- PlayerDataService refunds the deleted Mutation Chance upgrade during load and leaves the
	-- amount in memory (never on the save -- it would be persisted and re-announced forever).
	-- This is its only reader, and it clears the entry so a rejoin on the same server says nothing.
	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			player.CharacterAdded:Wait()
			task.wait(3) -- the HUD and SplicerUI are both up well inside this
			local refund = PlayerDataService.SplicerRefunds[player.UserId]
			if refund and refund > 0 then
				PlayerDataService.SplicerRefunds[player.UserId] = nil
				-- Through the ordinary Notify stack rather than a card of its own: it is news, not
				-- an event, and MainUI already owns how news is worded, ranked and sounded.
				Remotes.Notify:FireClient(player, { kind = "reward",
					message = ("🧬 Mutation Chance was replaced by the DNA Splicer -- refunded %d DNA")
						:format(refund) })
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastRoll[player.UserId] = nil
		lastEquip[player.UserId] = nil
		PlayerDataService.SplicerRefunds[player.UserId] = nil
	end)
end

return SplicerService
