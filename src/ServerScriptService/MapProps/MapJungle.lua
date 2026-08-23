-- MapProps/MapJungle -- the hunting ground, built out of the village map's own rock and mountain.
--
-- `JungleLayout` says WHERE. This is the WHAT: a clearing under every camp, a dirt path network
-- joining them, and a ridge line along the south and both flanks so the zone has a horizon that is
-- not a grey slab.
--
-- ===== 30.23: THE ALCOVE WALL CAME DOWN =====
-- 31.16 built each camp as a ring of nine boulders with a gap in it. The ring was meant to say
-- *this is a place*; the owner's next screenshot says it read as *you cannot get in there*, which
-- is the complaint the camps were built to answer, arriving a second time by a different route.
-- Nine rocks at chest height around a creature is a pen however wide the gap is.
--
-- A camp is now a CLEARING: a round floor of the village's own dirt, a handful of low stones along
-- its far edge, and dense wood all around it that `MapForest` holds back by
-- `JungleLayout.CLEARING_RADIUS`. The wall is the forest. Nothing rings the creature, the road
-- arrives at the floor's edge, and from outside you see into the camp before you are standing in
-- it -- which is the thing the ring was for and never managed.
--
-- Nothing here decides a coordinate -- every number it stands a prop on comes out of
-- `JungleLayout`, which is the one copy (see that file's header for why that matters here).
--
-- ===== IT IS THE MAP'S OWN ART, FOR THE SAME REASON THE TREES ARE =====
-- `MapForest` clones the village's trees rather than generating any, because a wood made of
-- different art from the village it stands behind reads as two games stitched together. Same rule:
-- the clearing's stones are the map's `Rock 01` / `Rock 02` meshes, the ridges are its own `Meshes/gora`
-- mountain, and the paths are painted in the colour of the village's own dirt ground -- READ OFF
-- the placed map at build time, not typed here, so a re-themed map repaints its own roads.
--
-- ===== NOTHING CHUNKY COLLIDES, AND THE STONES COLLIDE ANYWAY =====
-- `roblox-raycast-from-inside-a-part` and 30.19 are the same lesson twice: a MeshPart at
-- CollisionFidelity.Default is a soup of convex hulls, a rock's hull is very nearly its bounding
-- box, and every probe in the repo reports a body standing INSIDE one as standing on open ground.
-- So the rocks are `CanCollide = false` art and each one carries an invisible BOX that does the
-- colliding -- a convex primitive, at 80% of the rock's footprint, which is a shape a raycast, an
-- overlap query and a walking player all agree about.
--
-- No arc of stone stands anywhere near the way in. That is the one thing this file must never get
-- wrong, whatever shape a camp takes: a wall that seals a creature away from the player is
-- indistinguishable, from the outside, from a creature that is not there.
--
-- ===== THE PATHS ARE PAINT, NOT GEOMETRY, AND `MapPaint` IS WHERE THAT LIVES =====
-- 0.4 studs thick, `CanCollide = false`, sitting a fifth of a stud above the floor. A road you can
-- trip on is worse than no road, and `roblox-moving-platform-needs-velocity` / the terrace-stair
-- work are both records of what happens when scenery is allowed to carry the player.
--
-- The slab, the end caps and the dirt colour moved to `MapProps/MapPaint` when the VILLAGE needed a
-- road too (31.10). They are the same road at two ends -- the trunk lane runs south out of the
-- square and the approach road runs north out of it -- so a second copy of "how wide, what colour,
-- what plane" would have them meeting at the gate in two different browns.

local JungleLayout = require(script.Parent.JungleLayout)
local MapPaint = require(script.Parent.MapPaint)

local MapJungle = {}

local FOLDER_NAME = "Jungle"

-- ===== SIZING A ROCK: THE FOOTPRINT IS THE CONSTRAINT, NOT THE HEIGHT =====
-- The first cut of this sized every rock by HEIGHT alone -- `k = h / size.Y`, applied to all three
-- axes -- and the capture is the whole argument against it. `Rock 02` is 13 x 6 x 16 in the source,
-- i.e. FLAT, so asking for 19 studs of height multiplies its footprint by 3.2 as well: measured on
-- the live build, the widest alcove rock came out **27 x 21 x 75** and the mean footprint was
-- **30 studs**. Twenty rings of that read as pods of sleeping whales, not as walls.
--
-- So the horizontal scale is set FIRST, to a real target width, and the height is a SEPARATE
-- factor on top of it. Five stones over the far half of a 46-stud clearing stand about 29 studs
-- apart, so a 22-stud footprint leaves daylight between them -- which is what a lip of stone looks
-- like, as opposed to the continuous wall a 24-stud footprint on a full ring produced.
local ROCK_WIDTH = 22        -- studs, on the rock's larger horizontal axis
-- LOWER THAN THE 13..20 THE RING USED, and that is the whole difference between furniture and a
-- fence: 8..13 studs against an 8.4-stud player is a rock you see over. The ring's rocks were
-- taller than the player looking at them, which is what made twenty clearings read as twenty pens.
local ROCK_MIN_H, ROCK_MAX_H = 8, 13
-- ...and the vertical stretch that gets there is CLAMPED, because the stock is not one shape. The
-- map ships flat `Rock 02`s (6 studs tall) and tall `Rock 01`s (37), so an unclamped factor makes
-- the first into a pillar and the second into a pancake. Inside the clamp both land near the target
-- height; outside it, a tall rock stays a tall standing stone, which is variety rather than a fault.
local ROCK_STRETCH_MIN, ROCK_STRETCH_MAX = 0.4, 2.6
-- Five, on the FAR half of the clearing only -- see `buildCamp`. A backstop, not a ring.
local ROCKS_PER_CAMP = 5
local ROCK_SINK = 1.5        -- how far a rock is buried, so it reads as planted rather than dropped

-- The map's rocks are authored rgb(108, 108, 108) -- a NEUTRAL grey, which under this zone's blue
-- sky and blue ambient renders visibly blue. Against green grass and a tan path that reads as ice.
-- Warmed by about eight points on red and cooled on blue: it is the same value, tilted toward
-- stone, and `evolution-lab-world-look-pass` is the standing note that what looks like a paint
-- problem is usually the light -- so this is the smallest correction that survives it.
local ROCK_TINT = Color3.fromRGB(138, 126, 116)

-- ===== THE HORIZON LEFT THIS FILE (31.24) =====
-- `RIDGE_SCALE_SOUTH`, `RIDGE_SCALE_FLANK`, `RIDGE_SINK`, `RIDGE_Z`, `RIDGE_X`, `RIDGE_LANE`,
-- `mountainStock` and `buildRidge` all moved to `MapProps/MapHorizon`, whole. They were answering a
-- question this file should never have owned -- what the player sees at the EDGE of the zone -- and
-- they were answering it wrongly: 24 hills of 72 visible studs against a 180-stud boundary wall,
-- with no north run at all. See that file's header for the measurement and for the two rows that
-- replaced them. This file keeps the camps and the paint, which is what it is for.

-- The village's own dirt and the plane the roads are drawn on both live in `MapPaint` now -- the
-- village's approach road needs the same two and they cannot be two answers. See that file's header.

-- ===== STOCK =====

-- The rocks the map ships, as top-level MeshParts. They are `Rock 01` (8 of them) and `Rock 02`
-- (30), and after the band cuts 38 survive -- which is stock enough that no two clearings repeat.
local function rockStock(map)
	local stock = {}
	for _, c in ipairs(map:GetChildren()) do
		if c:IsA("BasePart") and c.Name:sub(1, 4) == "Rock" and c.Size.Y > 2 then
			stock[#stock + 1] = c
		end
	end
	return stock
end

-- Published for `MapForest`, which scatters the same stock through the wood as ground clutter
-- (30.31, the owner's *"da drveca i ovih stena sto vise ima po mapi, znaci jungle vibe"*). One
-- definition of "what is a rock in this map", two consumers.
MapJungle.RockStock = rockStock

-- ===== BUILDERS =====

-- One rock, resized to `h` studs tall on its own proportions, turned, tilted and half-buried, with
-- an invisible box beside it doing the colliding. See the header for why those are two objects.
local function standRock(proto, parent, x, z, h, rng, collide, width)
	local rock = proto:Clone()
	local s = proto.Size
	-- horizontal first (see the header), then the height as a clamped stretch on top of it
	local k = (width or ROCK_WIDTH) / math.max(s.X, s.Z, 0.01)
	local ky = math.clamp(h / math.max(s.Y * k, 0.01), ROCK_STRETCH_MIN, ROCK_STRETCH_MAX)
	-- jittered per axis so the same mesh twice is not the same silhouette twice
	rock.Size = Vector3.new(s.X * k * rng:NextNumber(0.85, 1.25), s.Y * k * ky,
		s.Z * k * rng:NextNumber(0.85, 1.25))
	rock.Color = ROCK_TINT
	rock.Material = Enum.Material.Slate
	rock.Anchored = true
	rock.CanCollide = false
	rock.CastShadow = false
	rock.CFrame = CFrame.new(x, rock.Size.Y / 2 - ROCK_SINK, z)
		* CFrame.Angles(rng:NextNumber(-0.14, 0.14), rng:NextNumber(0, math.pi * 2),
			rng:NextNumber(-0.14, 0.14))
	rock.Name = "JungleRock"
	rock.Parent = parent

	if collide then
		local box = Instance.new("Part")
		box.Name = "JungleRockCollider"
		-- 80% of the footprint and the rock's full height. Narrower than the art on purpose: the
		-- silhouette should overlap its neighbours so the ring reads as one wall, while the thing
		-- the player's shoulder actually meets stays a clean convex box with gaps between the
		-- boxes -- which is what stops a body wedging in a corner it cannot see.
		box.Size = Vector3.new(rock.Size.X * 0.8, rock.Size.Y, rock.Size.Z * 0.8)
		box.CFrame = CFrame.new(x, rock.Size.Y / 2 - ROCK_SINK, z)
			* CFrame.Angles(0, rock.Orientation.Y * math.pi / 180, 0)
		box.Anchored = true
		box.CanCollide = true
		box.Transparency = 1
		box.CastShadow = false
		box.Parent = parent
	end
	return rock
end

-- ===== THE CLEARING (30.23) =====
-- A floor, a backstop and some scree. In that order, because the floor is the outline tier's
-- ground and everything else stands on it.
--
-- THE FLOOR IS WHAT MAKES IT A PLACE. It is the same dirt the roads are painted in, read off the
-- map, so a spur arriving at a camp arrives at more of itself rather than stopping on grass -- and
-- a round patch of bare earth in a wood is the oldest possible way of saying somebody uses this
-- spot. Drawn dark-first and wider, the rule from `evolution-lab-chunky-look-rules` that every
-- other painted surface in this map follows.
--
-- THE ROCKS ARE ON THE FAR HALF ONLY, and the half is measured from the ROAD (`OpeningAngle` now
-- resolves to the nearest path point, not to the village). So the player always approaches across
-- open floor with the stones behind the creatures, framing them. They still collide -- they are the
-- only solid thing in a camp and a 10-stud boulder you walk through is worse than none -- but there
-- is no arc of them anywhere near the way in.
local function buildCamp(zoneKey, camp, stock, parent, cx, rng, dirt, yRim, yFloor)
	local open = JungleLayout.OpeningAngle(zoneKey, camp)
	local built = 0

	-- 1. the floor, and its rim.
	--
	-- THE RIM IS 3 STUDS ON THE RADIUS AND IT USED TO BE 5, which the owner photographed as a dark
	-- band lying across the way in. The arithmetic is the whole of 30.26: the rim is drawn WIDER and
	-- LOWER than the floor, and `SpurFor` used to end the road exactly at the floor's edge -- so
	-- between the last of the road paint and the outside of the rim there were five studs of dark
	-- ground, right at the mouth, twenty times over. The spur runs INTO the floor now (see
	-- `JungleLayout.SpurFor`) and the rim is thin enough to read as an outline rather than a step.
	local d = JungleLayout.CAMP_RADIUS * 2
	built += MapPaint.Disc(camp.x, camp.z, d + 6, parent, cx, MapPaint.Shade(dirt, 0.42), yRim)
	built += MapPaint.Disc(camp.x, camp.z, d, parent, cx, dirt, yFloor)

	-- 2. the backstop: five low stones spread over the far 180 degrees, standing just off the
	--    floor's edge so they read as the lip of the clearing rather than as an obstacle in it
	for i = 0, ROCKS_PER_CAMP - 1 do
		local a = open + math.pi / 2 + math.pi * ((i + 0.5) / ROCKS_PER_CAMP)
			+ rng:NextNumber(-0.12, 0.12)
		local r = JungleLayout.CAMP_RADIUS + rng:NextNumber(2, 12)
		local h = rng:NextNumber(ROCK_MIN_H, ROCK_MAX_H)
		standRock(stock[rng:NextInteger(1, #stock)], parent,
			cx + camp.x + math.cos(a) * r, camp.z + math.sin(a) * r, h, rng, true)
		built += 1
	end

	-- 3. scree on the floor: three flat stones, no collider, a third of the backstop's footprint.
	--    They must stay small enough to walk over and around: a chunky mesh in the middle of the
	--    ground the player fights on is 30.19.
	for _ = 1, 3 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(10, JungleLayout.CAMP_RADIUS - 16)
		standRock(stock[rng:NextInteger(1, #stock)], parent,
			cx + camp.x + math.cos(a) * r, camp.z + math.sin(a) * r,
			rng:NextNumber(2.2, 4.0), rng, false, 8)
		built += 1
	end
	return built
end


-- ===== THE ONE ENTRY POINT =====
--
-- Idempotent, and it has to be for the same reason `ForestMapService.Init` is: a second call must
-- not stand a second ring of rocks inside the first.
function MapJungle.Build(zoneKey, cx, map)
	local camps = JungleLayout.Camps(zoneKey)
	if not camps or not map then return 0 end

	local old = map:FindFirstChild(FOLDER_NAME)
	if old then old:Destroy() end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = map

	local stock = rockStock(map)
	if #stock == 0 then
		warn("[MapJungle] " .. zoneKey .. ": the map has no Rock meshes -- no alcoves built")
	end

	-- Seeded off the zone, never off the clock: two servers of the same place have to grow the same
	-- jungle, which is the rule `MapForest`, `raisedSpots` and `JungleLayout.Spawns` all follow.
	local rng = Random.new(20260822 + math.floor(cx))

	local colour = MapPaint.DirtColour(map)
	-- ===== A PLANE PER KIND, LOWEST FIRST (30.26) =====
	-- Everything the jungle paints overlaps something else it paints: spurs run onto camp floors by
	-- design since this row, trunk roads cross at junctions, and a floor's rim is under both. Drawn
	-- at one Y they z-fight into the patchwork the owner photographed. The order is what the eye
	-- should see from the bottom up -- rim, trunk, spur, floor -- and the whole ladder spans 0.16 of
	-- a stud, which is nothing to walk on and everything to a depth buffer.
	local Y_RIM = MapPaint.Y - MapPaint.STEP * 2
	local Y_TRUNK = MapPaint.Y
	local Y_SPUR = MapPaint.Y + MapPaint.STEP
	local Y_FLOOR = MapPaint.Y + MapPaint.STEP * 2
	-- ONE list of trunks and spurs, from `JungleLayout.Segments` -- the same list `MapForest` keeps
	-- its wood out of. Before 30.23 the spurs were derived here and the planter knew only the
	-- trunks, so every spur was a road with a wood grown across it.
	local segments = JungleLayout.Segments(zoneKey) or {}
	-- ===== THE HEIGHT COMES OFF THE SEGMENT'S OWN TIER, NOT OFF ITS INDEX (32.1) =====
	-- This used to read `i <= trunks`, because `Segments` returned every trunk and then one spur per
	-- camp. 32.1 appends the trails to the trunk list, so that ordering stopped being true and the
	-- test would have painted every trail at the trunk's height. Two things go wrong when it does,
	-- and both are `roblox-coplanar-paint-zfights`: a trail JOINS a trunk, so the two overlap on
	-- exactly one plane and shimmer down the join, and two trails meeting inside one camp do the
	-- same. A step apiece and the ladder draws in the order the eye should read it.
	local Y_FOR = { trunk = Y_TRUNK, trail = Y_SPUR, spur = Y_SPUR }
	local trunks, trails, spurs = 0, 0, 0
	local paved = 0
	for _, seg in ipairs(segments) do
		paved += MapPaint.Segment(seg, folder, cx, colour, Y_FOR[seg.tier] or Y_TRUNK)
		if seg.tier == "trail" then trails += 1
		elseif seg.tier == "spur" then spurs += 1
		else trunks += 1 end
	end

	local rocks = 0
	if #stock > 0 then
		for _, camp in ipairs(camps) do
			rocks += buildCamp(zoneKey, camp, stock, folder, cx, rng, colour, Y_RIM, Y_FLOOR)
		end
	end

	-- SPURS READING ZERO IS THE FIX, NOT THE FAULT, and the wording says so because 31.24's boot
	-- log killed a build on that exact number meaning the opposite (every camp had landed ON the
	-- ring). Since 32.1 a trail ends inside each camp's floor, so `SpurFor` has nothing left to
	-- connect. See `JungleLayout`'s note above `PATHS_FOREST`.
	print(("[MapJungle] %s: %d clearings with %d rocks and floors, %d path parts "
		.. "(%d cross + %d trails + %d spurs) -- the horizon is `MapHorizon` since 31.24")
		:format(zoneKey, #camps, rocks, paved, trunks, trails, spurs))
	return #camps
end

return MapJungle
