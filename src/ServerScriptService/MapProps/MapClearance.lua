-- MapProps/MapClearance -- the walk-up and the sight line in front of every piece of furniture (34.51).
--
-- The owner, on a capture of the Forest square: *"stvari ne smiju biti tako jedne u drugima, moraju
-- biti dostupne i vidljive ... da ima prostora, da nisu stvari natrpane i jedne u drugima"*.
--
-- ===== WHAT 34.51 MEASURED, AND WHY THAT MEASUREMENT DECIDED THE SHAPE OF THIS FILE =====
--
-- The row swept 43 trees against 71 furniture models and found **10 overlaps, worst 2.7 studs**
-- (`Bush2` into `Fence1`); the `Easterportal` is clipped by a `Pine Tree 02` by **0.9**. Nothing in
-- this village is meaningfully INSIDE anything else. What the capture actually shows is the second
-- half of her sentence -- the Easter portal at (-125, 12, -13) and the west shopfronts stand behind
-- a **wall of eight pines between z -37 and -69**, which from the square hides them completely.
--
-- So this pass is NOT an intersection fixer. A de-intersection pass would have moved ten props by
-- three studs and changed nothing she can see. It clears the space a player walks through to reach
-- a thing, and the space they look through to find it. Two zones, two different rules:
--
--   * THE WALK-UP, 0 .. `CLEAR_NEAR` studs out from the frontage's own front face: nothing above
--     knee height stands here at all. This is "dostupne".
--   * THE SIGHT LINE, `CLEAR_NEAR` .. `SIGHT_FAR`, and only down the narrow middle: a prop is moved
--     only if it is TALLER than the frontage it stands in front of. This is "vidljive", and the
--     height test is what keeps it from felling the whole square: a bush forty studs away does not
--     hide a shopfront, and eight pines do.
--
-- ===== IT MOVES. IT ONLY DROPS WHEN THERE IS NOWHERE TO GO =====
--
-- Row 34.47 is the record of the pass that got this wrong the other way round: `ForestMapService`'s
-- float sweep DESTROYED 46 of the artist's trees where it should have put them back on the ground,
-- and the owner objected. So the verb here is `PivotTo`, the search is `MapGates.relocate`'s ring
-- (the one thing in this codebase whose whole job is moving a prop out of a corridor), and a
-- `Destroy` happens only after the entire search has failed -- counted and NAMED in the boot line,
-- because a silent deletion is exactly what 34.47 was.
--
-- ===== IT MEASURES FROM THE CORRIDOR, NOT FROM THE PROP =====
--
-- `MapGates`' first cut of its own relocation pushed a fence 33 studs and landed it back in the same
-- road, because it measured the move from where the prop already was. The same mistake is available
-- here in a nastier form -- push whatever happens to be nearest and you have moved a tree from in
-- front of the shop to in front of the portal. So a candidate is only accepted when it clears EVERY
-- frontage in the village, every one of `MapGates.LANES`, and the entrance funnel; and the world it
-- is tested against is UPDATED the moment a prop lands, which is
-- `evolution-lab-keepout-pushes-into-the-next-corridor` (the cave guard that buried the arrival gate)
-- written as a loop invariant rather than as a warning.
--
-- ===== WHERE A FRONTAGE'S FRONT IS, AND WHY IT IS TWO DIFFERENT ANSWERS =====
--
-- `evolution-lab-shopfront-facing`: **pad-house is the front**. For the two paired anchors (`shop`,
-- `upgrades`) `MapAnchors` already holds both halves, so the approach bearing is house -> pad and it
-- is MEASURED rather than guessed. Everything else -- the boards, the podium, the eggs, the wheel,
-- the stalls, the signposts, the portals -- has no pad, and for those the bearing is the prop to the
-- VILLAGE FLOOR'S CENTRE: a player comes at the furniture round the edge of the square from the open
-- middle of it. The centre is read off `MainPart` rather than typed, because `ForestMapService.seat`
-- is what decides where that is.
--
-- ===== WHAT IT WILL AND WILL NOT PICK UP =====
--
-- Only `MapCut.IsFoliage` / `MapCut.IsBlankWall` props are ever moved -- the same classifier every
-- road cut in this map already trusts. A BUILDING standing in front of a portal is reported and left
-- exactly where it is, the way `MapCut.Lane` returns its `stay` list: relocating the village's own
-- architecture is `MapSquare`'s job and a second file doing it is
-- `evolution-lab-zone-geometry-constants` again.
--
-- ===== ONE ORDERING DEBT, STATED PLAINLY =====
--
-- `ServerMain` runs `MapEggs.Reseat`, `MapSquare.Arrange` and `MapSigns.Init` AFTER
-- `ForestMapService.Init`, and the square's arrange carries whole shop groups across the village
-- (34.47 measured the potions stall going (-55, -55) -> (70, 42)). A frontage this pass cleared can
-- therefore be somewhere else a moment later -- `evolution-lab-placement-search-ordering` exactly.
-- This is written IDEMPOTENT for that reason: it reads the live map every time, moves only what is
-- in the way now, and a second run on a finished world reports 0 moved. A second call at the true
-- end of the build (beside `MapSettle`'s second call, which exists for the same reason) is owed and
-- costs one line in `ServerMain`.

local MapCut = require(script.Parent.MapCut)
local MapGates = require(script.Parent.MapGates)
local MapAnchors = require(script.Parent.MapAnchors)
local PathSplines = require(script.Parent.PathSplines)

local MapClearance = {}

-- ===== THE TWO ZONES =====
-- 24 is `MapGates.CLEAR_HALF`'s own number and it is the same decision: 24 studs is what a 9-stud
-- body needs in front of it to read as room rather than as a gap. `SIGHT_FAR` is the depth the
-- capture actually complained about -- the portal sits at z -13 and the pines at z -37..-69, so a
-- sight line that stops short of 56 leaves the far half of that wall standing.
local CLEAR_NEAR = 24
local SIGHT_FAR = 56

-- The corridor. It TAPERS OPEN over the walk-up (a doorway you approach widens as you get to it)
-- and then narrows back to the near half for the sight line, because a 36-stud-wide view cone over
-- 25 frontages is the whole square and this pass would then be a demolition.
local CONE_HALF_NEAR = 10
local CONE_HALF_FAR = 15

-- Knee height on the 8.4-stud body. `MapCut.MIN_HEIGHT` is 5 and is written for a VERGE; the
-- driving-line callers already pass 2 for the same reason a walk-up wants less than a verge. 4 is
-- between them: a flat rock in front of a shop is scenery, a 4-stud stump is a stubbed toe.
local MIN_HEIGHT = 4

-- The ring search, in the shape `MapGates.relocate` uses: radius first (the nearest spot that works
-- wins), then angle, opening straight out of the corridor on the side the prop already stands.
--
-- ===== THE FIRST BOOT'S NUMBERS ARE WHY THESE ARE NOT 7 AND 12 ANY MORE =====
-- The ring was 7 x 12 studs and 7 arcs: **91 candidates**, reaching 82 studs. The pass then reported
-- `could not place 18` and the refusal line reported **1638 candidates refused over 18 props** --
-- which is 18 x 91 exactly. Not one prop had a candidate left over: the search was not choosing
-- badly, it was RUNNING OUT.
--
-- And 82 studs is the wrong distance for this village on the geometry this file already computes.
-- Every frontage's corridor points at the square's centre, so the free ground is BEHIND the ring of
-- furniture -- the furniture stands about 100 studs out from (-19, 8) and the village floor reaches
-- 270 x 230. A prop standing in the middle of the square therefore has to be carried past the whole
-- ring before it is out of everyone's way, and 82 studs does not reach it. 180 does, and the ring
-- order still hands back the NEAREST spot that works, so nothing is carried further than it needs.
local MIN_MOVE = 10
local MOVE_STEP = 10
local MOVE_RINGS = 18         -- so the furthest a prop is ever carried is 10 + 17*10 = 180 studs

-- ===== A FIXED NUMBER OF BEARINGS IS A SEARCH THAT GETS BLINDER THE FURTHER OUT IT LOOKS =====
-- It was 23 bearings on every ring. At 10 studs out that is a candidate every 1.4 studs; at 180 it
-- is a candidate every **47 studs** -- wider than most of this village's props, so whole clearings
-- were being stepped straight over. The bearing count is derived from an arc LENGTH instead, so the
-- candidates stay about a body's width apart at every radius: 7 bearings on the inner ring, 121 on
-- the outer one. `MAX_ARCS` is only there to bound the cost.
local ARC_STEP = 9
local MAX_ARCS = 60

-- Daylight between two props after a move. This is the owner's own sentence as a number: nothing
-- lands touching anything.
local GAP = 3

-- ===== AND A GRID, BECAUSE THE OVERLAP TEST IS NOW THE WHOLE COST OF THE PASS =====
-- Every candidate has to be checked against every prop that could be standing on it, and the ring
-- above offers about 1,200 candidates per prop. Walked as a flat list of 400 that is ~500k box
-- tests for a single unplaced tree, and this pass runs twice a boot. The map is indexed once into
-- 40-stud cells and a candidate only ever reads the handful of cells its own box covers.
--
-- A prop is inserted into every cell its box (plus the gap) touches, so a 400-stud ground union
-- appears in many cells and a bush in one. When a prop MOVES it is re-inserted rather than removed:
-- the entry is the same table `props` holds, so every listing reads its live position, and a stale
-- listing can only cost a repeated test -- never a missed one.
local CELL = 40

local function cellKey(gx, gz)
	return gx * 100000 + gz
end

local function gridInsert(grid, entry)
	local p, sz = entry.pos, entry.size
	local x0 = math.floor((p.X - sz.X / 2 - GAP) / CELL)
	local x1 = math.floor((p.X + sz.X / 2 + GAP) / CELL)
	local z0 = math.floor((p.Z - sz.Z / 2 - GAP) / CELL)
	local z1 = math.floor((p.Z + sz.Z / 2 + GAP) / CELL)
	for gx = x0, x1 do
		for gz = z0, z1 do
			local key = cellKey(gx, gz)
			local list = grid[key]
			if not list then
				list = {}
				grid[key] = list
			end
			list[#list + 1] = entry
		end
	end
end

-- The destination has to have ground under it, and the prop lands ON that ground -- but it is only
-- ever DROPPED, never lifted, which is `MapSettle`'s rule and for its reason: half of this map's
-- rocks and stumps are deliberately seated with a bite into the floor and lifting them out is a
-- second bug wearing the first one's clothes.
local GROUND_UP = 6
local GROUND_DOWN = 30
local GROUND_MAX = 10

-- A runaway pass is the failure mode 34.47 shipped. If this ever wants to move more than 80 props it
-- is not clearing approaches any more, so it stops and says so rather than rearranging the village.
local MAX_MOVES = 80

-- Portals and doors are furniture nothing has ever declared. `MapAnchors` knows the shop, the eggs,
-- the boards and the wheel because a service asks it for them; nothing asks for the `Easterportal`,
-- which is the one prop 34.51 photographed. Matched on the NAME, case-folded and by substring
-- rather than by prefix, because the map's author wrote `Easterportal` as one word.
local DOOR_WORDS = { "portal", "door", "gate", "entrance" }

local function isDoorway(name)
	local lower = name:lower()
	for _, w in ipairs(DOOR_WORDS) do
		if lower:find(w, 1, true) then return true end
	end
	return false
end

-- ===== A PROP'S WORLD-AXIS BOX, AND IT REALLY HAS TO BE THE WORLD'S AXES =====
--
-- This used to hand back `Part.Size` and `GetBoundingBox`'s size unchanged, which are both in the
-- part's OWN frame (`roblox-part-size-is-in-its-own-frame`,
-- `roblox-model-box-getters-are-pivot-frame`), and the note here argued that measuring truer than
-- `MapCut` would put the two files on different geometry. **The village says otherwise, and it says
-- it in numbers:** 177 of this map's 394 top-level children read more than 5 studs different once
-- the rotation is applied, and the three worst are the square's own FLOOR --
--
--     Union at (-18, 0, 9)    own 1 x 144 x 144   ->   world 144 x 1 x 144
--     Part  at (-193, 0, 14)  own 1 x 106 x 97    ->   world 106 x 1 x 97
--     Union at (-37, 0, -28)  own 255 x 1 x 398   ->   world 419 x 1 x 288
--
-- -- flat paving, authored standing up and rotated flat. Read in its own frame, the paving in the
-- middle of the square is a **144-stud tower** standing at (-18, 9): it passes `MIN_HEIGHT`, it
-- stands in every frontage's corridor, it is what the `tightest` line has been naming (`-67.5 studs
-- at Upgrades (Union)` is a floor), and in the overlap test it makes a 144 x 144 stud block of the
-- village unreachable to any prop this pass is trying to place. The two rules that care most about
-- a box -- *is it taller than the frontage it hides* and *is something already standing there* --
-- were both being answered about a shape that does not exist.
--
-- The rotation is applied the standard way: each world extent is the row of |R| against the size.
-- 34.62 MOVED THIS INTO `MapCut` AND THIS FILE CALLS IT. `MapCut` had three readers of its own that
-- each took `Part.Size` and `GetBoundingBox()`'s size straight -- the prop's own frame -- and on a
-- live Forest build that made four flat floors read as blank walls, which is a class a road cut is
-- allowed to delete. One implementation is the fix; two that agree today are the same bug waiting.
-- The long note about what a rotated box does to a frontage test stays above, because this is the
-- file that paid for it.
-- Only the box getter is aliased. `MapCut.WorldSize` is the piece underneath it and this file has
-- no caller for it on its own, so it is left where it lives -- an unused local is one more name a
-- future reader has to decide is harmless.
local boxOf = MapCut.WorldBox

-- The half-width of the corridor `near` studs out from the front face.
local function halfAt(near)
	local f = math.clamp(near / CLEAR_NEAR, 0, 1)
	return CONE_HALF_NEAR + (CONE_HALF_FAR - CONE_HALF_NEAR) * f
end

-- How a box at `pos` sits against one frontage's corridor. Returns the gap from the front face to
-- the NEAREST point of the box (negative when the box is already past the face), and how far the
-- box reaches into the corridor's edge -- both measured with the exact support of an axis-aligned
-- box along the two axes, the same formula `MapCut.LaneFootprint` uses and for the same reason: a
-- 48-stud canopy has a 34-stud bounding radius and a radius test swallows the whole square.
local function project(front, pos, size)
	local px, pz = pos.X - front.ox, pos.Z - front.oz
	local along = px * front.dx + pz * front.dz
	local side = math.abs(-px * front.dz + pz * front.dx)
	local reachAlong = math.abs(front.dx) * size.X / 2 + math.abs(front.dz) * size.Z / 2
	local reachSide = math.abs(front.dz) * size.X / 2 + math.abs(front.dx) * size.Z / 2
	return along - reachAlong, side - reachSide, along + reachAlong
end

-- Is this box standing in the corridor at all, ignoring the height rule? This is what the boot
-- line's "tightest remaining" is measured with -- the honest question is *how close does the
-- nearest thing stand in front of this shop*, and answering it with the move rule would report
-- infinity the moment the pass succeeded.
local function corridorGap(front, pos, size)
	local near, edge, far = project(front, pos, size)
	if far <= 0 then return nil end
	if near > SIGHT_FAR then return nil end
	if edge > halfAt(math.max(near, 0)) then return nil end
	return near
end

-- ...and the move rule, which is that gap plus the two zones. Returns nil when the prop may stay.
local function inTheWay(front, pos, size)
	local near, edge, far = project(front, pos, size)
	if far <= 0 then return nil end
	if near > SIGHT_FAR then return nil end
	if near <= CLEAR_NEAR then
		if edge <= halfAt(math.max(near, 0)) then return near end
		return nil
	end
	-- THE SIGHT LINE. Only what stands over the frontage's own head hides it, and only down the
	-- middle -- see the header for why this half is not the walk-up's half.
	if (pos.Y + size.Y / 2) <= front.top then return nil end
	if edge <= CONE_HALF_NEAR then return near end
	return nil
end

-- ===== THE FRONTAGES =====
-- Everything `MapAnchors` protected (which IS the map's declared furniture -- the boards, the
-- podium, the eggs, the stalls, the signposts, the shop and upgrades pads and houses, the wheel,
-- the index, the potions) plus the doorways nothing declares.
--
-- SORTED, and that is load-bearing rather than tidy: `protected` is a set and `pairs` over it has
-- no order, while the relocation search resolves ties by which frontage it saw first. An unordered
-- frontage list is a village that comes out slightly different on every boot.
local function frontagesFor(zoneKey, map, cx, protected)
	local list = {}
	local floor = map:FindFirstChild("MainPart")
	local centreX = floor and floor.Position.X or cx
	local centreZ = floor and floor.Position.Z or 0

	-- pad-house is the front, and for these two the map ships both halves
	local faceOf = {}
	for _, role in ipairs({ "shop", "upgrades" }) do
		local pad = MapAnchors.Get(zoneKey, role)
		local house = MapAnchors.Get(zoneKey, role .. "House")
		if pad and house then
			local d = Vector2.new(pad.pos.X - house.pos.X, pad.pos.Z - house.pos.Z)
			if d.Magnitude > 1 then
				faceOf[pad.inst] = d.Unit
				faceOf[house.inst] = d.Unit
			end
		end
	end

	local function add(inst)
		-- A SECOND CALL RUNS AFTER `MapSquare` HAS FELLED PROPS, and `protected` is the set the
		-- build censused: an instance in it may have been destroyed since. A destroyed Model still
		-- answers `GetBoundingBox` with its last box, so without this the second pass would clear
		-- the approach to a shop that is no longer there.
		if not inst.Parent then return end
		local pos, size = boxOf(inst)
		if not pos then return end
		local dir = faceOf[inst]
		if not dir then
			local d = Vector2.new(centreX - pos.X, centreZ - pos.Z)
			-- A prop standing ON the centre has open ground on every side and no front to clear.
			if d.Magnitude < 1 then return end
			dir = d.Unit
		end
		local reach = math.abs(dir.X) * size.X / 2 + math.abs(dir.Y) * size.Z / 2
		list[#list + 1] = {
			name = inst.Name,
			inst = inst,
			dx = dir.X,
			dz = dir.Y,
			ox = pos.X + dir.X * reach,
			oz = pos.Z + dir.Y * reach,
			top = pos.Y + size.Y / 2,
		}
	end

	for inst in pairs(protected or {}) do
		add(inst)
	end
	for _, c in ipairs(map:GetChildren()) do
		if not MapCut.NEVER_CUT[c.Name] and not (protected and protected[c]) and isDoorway(c.Name) then
			add(c)
		end
	end

	table.sort(list, function(a, b)
		if a.name ~= b.name then return a.name < b.name end
		if a.ox ~= b.ox then return a.ox < b.ox end
		return a.oz < b.oz
	end)
	return list
end

-- Would a box of `size` centred at (tx, tz) be standing in a road? Zone-relative, exactly as
-- `MapGates` measures its own driving line -- the lanes BEND since 33.35 and `PathSplines.Clearance`
-- is the clamped projection over the polyline rather than over its chord.
local function onRoad(rx, tz, hw)
	for _, lane in ipairs(MapGates.LANES) do
		if lane.path and PathSplines.Clearance(lane.path, rx, tz) <= MapGates.CLEAR_HALF + hw then
			return true
		end
	end
	return false
end

-- ...and the funnel the arrival road comes down, which is not one of those three. `entrance` is
-- `ForestMapService`'s own four-field spec, passed in rather than required, because this file lives
-- under `MapProps` and that one requires it.
local function inEntrance(entrance, rx, tz, hw)
	if not entrance then return false end
	local lo = math.min(entrance.zNear, entrance.zFar)
	local hi = math.max(entrance.zNear, entrance.zFar)
	if tz < lo or tz > hi then return false end
	local t = (tz - entrance.zNear) / (entrance.zFar - entrance.zNear)
	local half = entrance.halfNear + (entrance.halfFar - entrance.halfNear) * math.clamp(t, 0, 1)
	return math.abs(rx) - hw <= half
end

-- ===== WHY A CANDIDATE WAS REFUSED =====
-- The first live boot reported `moved 3, could not place 18` and the line could not say WHICH of the
-- six rules was doing the refusing -- so the fix for it would have been a guess. `why` is a plain
-- count per rule over every candidate the ring offered, kept only for the props whose search FAILED
-- (a search that succeeded on ring 0 rejects nothing worth reading). It is what turns "the search
-- does not work" into a name.
local function note(why, reason)
	if why then why[reason] = (why[reason] or 0) + 1 end
end

-- ===== THE TWO STANDARDS A DESTINATION CAN BE HELD TO =====
--
-- `relaxed = false` is the one this file was written with: the spot has to be clear of EVERY
-- frontage, both zones. `relaxed = true` keeps every hard rule -- no road, no entrance funnel, no
-- landing inside another prop, and never in anybody's WALK-UP -- and gives up only the sight line.
--
-- It exists because of what the first two boots measured. The ring offers 414 spots and all 414
-- were refused for 8 of the props, which is the pass saying there is nowhere in this village that
-- satisfies 45 converging view cones at once. The choice then is between leaving a pine standing
-- across a shop door and standing it somewhere that is out of every doorway but still in somebody's
-- distant view -- and the first is the fault the owner reported. A tier that is *strictly better
-- than not moving it* is not a compromise of the rule, it is the rule applied to a village that
-- cannot satisfy it, and the boot line says how many were placed that way so it can never quietly
-- become the normal path (which is exactly how the deleting version of this pass went wrong).
local function fits(job, tx, tz, fronts, grid, cx, entrance, why, relaxed)
	local size = job.size
	local hw = math.max(size.X, size.Z) / 2

	local rx = tx - cx
	if onRoad(rx, tz, hw) then note(why, "in a road") return nil end
	if inEntrance(entrance, rx, tz, hw) then note(why, "in the entrance funnel") return nil end

	-- Ground first, because the height it lands at is what the overlap test below has to use.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { job.inst }
	local foot = job.pos.Y - size.Y / 2
	local hit = workspace:Raycast(Vector3.new(tx, foot + GROUND_UP, tz),
		Vector3.new(0, -GROUND_DOWN, 0), params)
	if not hit then note(why, "no ground under it") return nil end
	-- only ever down -- see the note over GROUND_UP
	local dy = math.min(hit.Position.Y - foot, 0)
	if dy < -GROUND_MAX then note(why, "ground drops away") return nil end

	local ty = job.pos.Y + dy
	local at = Vector3.new(tx, ty, tz)
	for _, front in ipairs(fronts) do
		if front.inst ~= job.inst then
			local near = inTheWay(front, at, size)
			-- On the relaxed tier only the walk-up counts: `inTheWay` returns the gap to the front
			-- face, and a gap over `CLEAR_NEAR` is the sight-line half of the rule.
			if near and (not relaxed or near <= CLEAR_NEAR) then
				note(why, "in front of " .. front.name)
				return nil
			end
		end
	end

	-- ...and nothing already standing there. Every entry carries its CURRENT box and is rewritten
	-- the instant one moves, which is the whole of the re-measure rule; the grid only decides which
	-- entries are worth asking.
	local x0 = math.floor((tx - size.X / 2 - GAP) / CELL)
	local x1 = math.floor((tx + size.X / 2 + GAP) / CELL)
	local z0 = math.floor((tz - size.Z / 2 - GAP) / CELL)
	local z1 = math.floor((tz + size.Z / 2 + GAP) / CELL)
	for gx = x0, x1 do
		for gz = z0, z1 do
			local list = grid[cellKey(gx, gz)]
			if list then
				for _, other in ipairs(list) do
					if other ~= job and other.pos then
						if math.abs(other.pos.X - tx) < (other.size.X + size.X) / 2 + GAP
							and math.abs(other.pos.Z - tz) < (other.size.Z + size.Z) / 2 + GAP
							and math.abs(other.pos.Y - ty) < (other.size.Y + size.Y) / 2 then
							note(why, "another prop is there")
							return nil
						end
					end
				end
			end
		end
	end

	return dy
end

-- The ring, opening straight out of the corridor on the side the prop is already on: the shortest
-- move that could possibly clear it, which is `MapGates.relocate`'s own opening bid. Everything past
-- that is tried in growing rings so the NEAREST spot that works wins, whichever way it lies.
local function findSpot(job, front, fronts, grid, cx, entrance, why, relaxed)
	local px, pz = job.pos.X - front.ox, job.pos.Z - front.oz
	local side = (-px * front.dz + pz * front.dx) >= 0 and 1 or -1
	local base = math.atan2(front.dx * side, -front.dz * side)

	for ring = 0, MOVE_RINGS - 1 do
		local r = MIN_MOVE + ring * MOVE_STEP
		local arcs = math.clamp(math.floor(math.pi * r / ARC_STEP), 1, MAX_ARCS)
		for k = 0, arcs do
			for _, sgn in ipairs(k == 0 and { 1 } or { 1, -1 }) do
				local ang = base + sgn * k * (math.pi / arcs)
				local tx = job.pos.X + math.cos(ang) * r
				local tz = job.pos.Z + math.sin(ang) * r
				local dy = fits(job, tx, tz, fronts, grid, cx, entrance, why, relaxed)
				if dy then return tx, tz, dy end
			end
		end
	end
	return nil
end

local function tally(counts)
	local out = {}
	for name, n in pairs(counts) do
		out[#out + 1] = ("%s x%d"):format(name, n)
	end
	table.sort(out)
	return #out > 0 and table.concat(out, ", ") or "none"
end

-- ===== THE PASS =====
--
-- `spec` is `ForestMapService`'s own zone spec; only `entrance` is read off it, and a nil spec
-- simply means the funnel is not defended. Returns the summary it printed, so a caller that wants
-- the numbers does not have to parse the line.
function MapClearance.Open(zoneKey, cx, map, protected, spec)
	local fronts = frontagesFor(zoneKey, map, cx, protected)
	local entrance = spec and spec.entrance

	-- Every top-level prop, furniture included: the furniture is what a moved prop must not land
	-- inside, so it belongs in this list even though it is never a candidate.
	local props = {}
	for _, c in ipairs(map:GetChildren()) do
		if not MapCut.NEVER_CUT[c.Name] then
			local pos, size = boxOf(c)
			if pos then
				props[#props + 1] = {
					inst = c,
					pos = pos,
					size = size,
						-- FOLIAGE ONLY, and `MapCut.IsBlankWall` is deliberately NOT on this line even
					-- though every road cut in this map treats the two the same. A blank wall is 60
					-- to 96 studs long (measured, in that file's own note): carrying one ten studs
					-- sideways moves a backdrop into open view and fixes nothing. It falls through
					-- to `held` below and gets named, which is the honest outcome for it.
					movable = not (protected and protected[c]) and MapCut.IsFoliage(c),
				}
			end
		end
	end

	local grid = {}
	for _, p in ipairs(props) do
		gridInsert(grid, p)
	end

	-- ===== FURNITURE IS NEVER IN FURNITURE'S WAY =====
	-- Eight leaderboard boards stand in a row and every one of them is inside its neighbour's
	-- corridor; a signpost is TWO instances, a `Sign1` pole with a `ThreeDTextObject` floating 7.3
	-- studs over it and under one stud away in plan, so each is permanently in the other's. Counting
	-- those would fill `held` with the map's own arrangement and make the tightest-clearance number
	-- report a sign standing on its own post forever. The author arranged this furniture and
	-- `MapSquare` rearranges it; this pass clears what has grown up AROUND it.
	local isFront = {}
	for _, front in ipairs(fronts) do
		isFront[front.inst] = true
	end

	-- What is in the way, and which frontage objects loudest. A prop can block three frontages; the
	-- one it is DEEPEST into is the one its move opens away from.
	local jobs, held = {}, {}
	for _, p in ipairs(props) do
		if p.size.Y >= MIN_HEIGHT and not isFront[p.inst] then
			local worst, worstNear = nil, math.huge
			for _, front in ipairs(fronts) do
				if front.inst ~= p.inst then
					local near = inTheWay(front, p.pos, p.size)
					if near and near < worstNear then
						worst, worstNear = front, near
					end
				end
			end
			if worst then
				if p.movable then
					jobs[#jobs + 1] = { prop = p, front = worst, near = worstNear }
				else
					-- Reported, never moved. See the header: the village's own architecture is
					-- `MapSquare`'s to arrange, and this file naming what it refused is the same
					-- contract `MapCut.Lane`'s `stay` list carries.
					held[p.inst.Name] = (held[p.inst.Name] or 0) + 1
				end
			end
		end
	end

	-- Deepest first, ties by name so a boot is reproducible.
	table.sort(jobs, function(a, b)
		if a.near ~= b.near then return a.near < b.near end
		return a.prop.inst.Name < b.prop.inst.Name
	end)

	local moved, dropped, capped = 0, 0, false
	local droppedNames = {}
	-- Placed on the second tier: out of every doorway, still in somebody's distant view. See `fits`.
	local relaxedMoves = 0
	-- How far the pass actually carried things. The ring hands back the nearest spot that works, so
	-- a long carry is the search reporting that the near ground was taken -- and a pass that quietly
	-- posts the village's trees to the far edge is a thing the line has to be able to say.
	local carriedFar, carriedSum = 0, 0
	-- Every rule that refused a candidate, over the props whose search failed. See `note`.
	local refused, refusedCandidates = {}, 0
	for _, job in ipairs(jobs) do
		if moved + dropped >= MAX_MOVES then
			capped = true
			break
		end
		local p = job.prop
		if p.inst.Parent then
			local why = {}
			local tx, tz, dy = findSpot(p, job.front, fronts, grid, cx, entrance, why)
			local onSightLine = false
			if not tx then
				-- Second tier, and it is only ever reached when the first found nothing at all.
				tx, tz, dy = findSpot(p, job.front, fronts, grid, cx, entrance, nil, true)
				onSightLine = tx ~= nil
			end
			if tx then
				p.inst:PivotTo(p.inst:GetPivot() + Vector3.new(tx - p.pos.X, dy, tz - p.pos.Z))
				-- RE-MEASURED FROM THE INSTANCE, not assumed from the shift: a Model's box is
				-- pivot-frame and reading it back is the only thing that makes the next prop's
				-- overlap test true (`probe-restore-must-be-read-back`, one scale down).
				local np, ns = boxOf(p.inst)
				local carried = math.sqrt((tx - job.prop.pos.X) ^ 2 + (tz - job.prop.pos.Z) ^ 2)
				p.pos, p.size = np, ns
				gridInsert(grid, p)
				moved += 1
				if onSightLine then relaxedMoves += 1 end
				carriedSum += carried
				if carried > carriedFar then carriedFar = carried end
			else
				-- ===== NOTHING IS EVER DELETED HERE, AND THE FIRST BOOT IS WHY =====
				--
				-- This branch used to `Destroy()` a prop the ring search could not place, as a last
				-- resort. On the very first live boot the last resort was not the exception, it was
				-- the RULE: `moved 3, dropped 18` -- eighteen of the artist's props deleted to open
				-- twenty-one sight lines, including twelve unnamed `Model`s and two `Pine Tree 02`.
				--
				-- That is precisely the fault 34.47 is the record of, and the owner objected to it in
				-- her own words: the trees are to be RELOCATED, not felled. A pass whose search
				-- fails four times out of five has a search problem; answering it with a delete
				-- turns a weak pass into a destructive one, and the map is the one thing here that
				-- cannot be regenerated.
				--
				-- So a prop that cannot be placed is LEFT STANDING and named in the boot line, which
				-- is the same contract `MapCut.Lane`'s `stay` return has and what `held` already
				-- does for buildings. The line then reports honestly that the pass could not do its
				-- job for that prop, instead of reporting a success it bought by deleting the
				-- evidence.
				-- NAMED, and it was not before: `droppedNames` was written by the `Destroy()` branch
				-- this replaced and nothing has filled it since, so the boot line's own
				-- "could not place N (...)" parenthetical has never once printed a name
				-- (`optional-arg-nothing-passes`, one scale down). The unplaced are the pass's own
				-- failures and they are the list worth reading; `held` is the list it refused to
				-- touch on purpose, and mixing the two hid both.
				droppedNames[p.inst.Name] = (droppedNames[p.inst.Name] or 0) + 1
				dropped += 1
				for reason, n in pairs(why) do
					refused[reason] = (refused[reason] or 0) + n
					refusedCandidates += n
				end
			end
		end
	end

	-- ===== WHAT IS STILL IN THE WAY, WHICH IS THE PASS'S OWN SCORE =====
	-- The same rule the jobs were chosen with, run again over the finished world. `24 in the way ->
	-- 5 still in the way` is the sentence this pass exists to be able to say.
	--
	-- MOVABLE PROPS ONLY, so the two halves of that sentence count the same thing. The first cut
	-- counted every prop and reported `27 in the way -> 50 still in the way`, which reads as a pass
	-- that made the village worse and was really two different questions: `#jobs` is what this pass
	-- may move, while the 50 included all the architecture it has never been allowed to touch (ten
	-- `Fence1`, the shop's own `Meshes/Sell*` stall pieces, three `Barrel1`). That list is worth
	-- printing -- it is `held`, on the same line -- but not as this number.
	--
	-- It is also a different question from `tightest` below: that one is the closest anything STANDS
	-- to a frontage and is dominated by the size of the box (a 90-stud canopy centred 20 studs away
	-- reports a large negative and is not necessarily hiding anything).
	--
	-- Its interesting failure is not the unplaced. It is a prop that was clear and got BLOCKED by a
	-- later move in the same pass -- the search tests a candidate against every frontage, so that
	-- should never happen, and this is the number that would say so.
	local residual, residualNames = 0, {}
	for _, p in ipairs(props) do
		if p.pos and p.movable and p.size.Y >= MIN_HEIGHT and not isFront[p.inst] and p.inst.Parent then
			for _, front in ipairs(fronts) do
				if front.inst ~= p.inst and inTheWay(front, p.pos, p.size) then
					residual += 1
					residualNames[p.inst.Name] = (residualNames[p.inst.Name] or 0) + 1
					break
				end
			end
		end
	end

	-- ===== AND THE ONE NUMBER THAT SAYS WHETHER IT WORKED =====
	-- Not "how many did I move" -- a pass that moved forty props and left one pine across the portal
	-- has failed at the only thing it was written for. This is the closest any prop still stands in
	-- front of any frontage, measured over the finished world.
	local tightest, tightFront, tightProp = math.huge, "-", "-"
	for _, front in ipairs(fronts) do
		for _, p in ipairs(props) do
			if p.pos and p.size.Y >= MIN_HEIGHT and not isFront[p.inst] then
				local gap = corridorGap(front, p.pos, p.size)
				if gap and gap < tightest then
					tightest, tightFront, tightProp = gap, front.name, p.inst.Name
				end
			end
		end
	end

	local summary = {
		residual = residual,
		relaxed = relaxedMoves,
		fronts = #fronts,
		considered = #props,
		inTheWay = #jobs,
		moved = moved,
		dropped = dropped,
		held = held,
		tightest = tightest,
		tightestFront = tightFront,
		tightestProp = tightProp,
		capped = capped,
	}

	-- `could not place` rather than `dropped`, because nothing is dropped any more (see the branch
	-- above). It is the pass's own failure count and it is printed FIRST among the failures, so a
	-- search that stops working is visible in the line rather than hidden behind a move count.
	print(("[MapClearance] %s: %d frontages, %d props considered, %d in the way -> %d still in the "
		.. "way (%s), moved %d, could not place %d%s, left standing %s, tightest %s%s")
		:format(zoneKey, summary.fronts, summary.considered, summary.inTheWay, residual,
			tally(residualNames), moved, dropped,
			next(droppedNames) and (" (" .. tally(droppedNames) .. ")") or "", tally(held),
			tightest == math.huge and ("clear to %d studs"):format(SIGHT_FAR)
				or ("%.1f studs at %s (%s)"):format(tightest, tightFront, tightProp),
			capped and (" -- STOPPED AT THE %d-PROP CAP"):format(MAX_MOVES) or ""))

	if moved > 0 then
		print(("[MapClearance] %s: carried a mean %.1f studs, furthest %.1f of a possible %d; "
			.. "%d of the %d placed had to give up a sight line")
			:format(zoneKey, carriedSum / moved, carriedFar, MIN_MOVE + (MOVE_RINGS - 1) * MOVE_STEP,
				relaxedMoves, moved))
	end

	-- ===== AND WHY THE SEARCH FAILED, WHEN IT FAILED =====
	-- Printed only when something could not be placed, and it is the line the fix is read off: the
	-- rules are named in the order they refused, biggest first, so the binding constraint is the
	-- first thing on it rather than something to be inferred from six numbers.
	if dropped > 0 then
		local rows = {}
		for reason, n in pairs(refused) do
			rows[#rows + 1] = { reason = reason, n = n }
		end
		table.sort(rows, function(a, b)
			if a.n ~= b.n then return a.n > b.n end
			return a.reason < b.reason
		end)
		local parts = {}
		for i = 1, math.min(#rows, 8) do
			parts[#parts + 1] = ("%s x%d"):format(rows[i].reason, rows[i].n)
		end
		print(("[MapClearance] %s: %d candidates refused over %d unplaced props -- %s")
			:format(zoneKey, refusedCandidates, dropped, table.concat(parts, ", ")))
	end
	summary.refused = refused

	return summary
end

return MapClearance
