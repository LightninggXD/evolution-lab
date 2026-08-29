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
local MIN_MOVE = 10
local MOVE_STEP = 12
local MOVE_RINGS = 7          -- so the furthest a prop is ever carried is 10 + 6*12 = 82 studs
local MOVE_ARCS = 7           -- +/- 6 steps of pi/7 either side of straight out, i.e. the full half-plane

-- Daylight between two props after a move. This is the owner's own sentence as a number: nothing
-- lands touching anything.
local GAP = 3

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

-- A prop's world-axis box. `GetBoundingBox` is PIVOT-frame
-- (`roblox-model-box-getters-are-pivot-frame`) and every cut in this map family measures with it
-- anyway; a second, truer measurement here would put this pass and `MapCut` on different geometry,
-- which is the fault `evolution-lab-zone-geometry-constants` is about.
local function boxOf(inst)
	if inst:IsA("Model") then
		local cf, size = inst:GetBoundingBox()
		return cf.Position, size
	elseif inst:IsA("BasePart") then
		return inst.Position, inst.Size
	end
	return nil, nil
end

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

-- Everything a destination has to satisfy. Returns the Y shift to apply, or nil.
local function fits(job, tx, tz, fronts, props, cx, entrance)
	local size = job.size
	local hw = math.max(size.X, size.Z) / 2

	local rx = tx - cx
	if onRoad(rx, tz, hw) then return nil end
	if inEntrance(entrance, rx, tz, hw) then return nil end

	-- Ground first, because the height it lands at is what the overlap test below has to use.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { job.inst }
	local foot = job.pos.Y - size.Y / 2
	local hit = workspace:Raycast(Vector3.new(tx, foot + GROUND_UP, tz),
		Vector3.new(0, -GROUND_DOWN, 0), params)
	if not hit then return nil end
	-- only ever down -- see the note over GROUND_UP
	local dy = math.min(hit.Position.Y - foot, 0)
	if dy < -GROUND_MAX then return nil end

	local ty = job.pos.Y + dy
	local at = Vector3.new(tx, ty, tz)
	for _, front in ipairs(fronts) do
		if front.inst ~= job.inst and inTheWay(front, at, size) then return nil end
	end

	-- ...and nothing already standing there. `props` carries every top-level prop's CURRENT box and
	-- is rewritten the instant one moves, which is the whole of the re-measure rule.
	for _, other in ipairs(props) do
		if other ~= job and other.pos then
			if math.abs(other.pos.X - tx) < (other.size.X + size.X) / 2 + GAP
				and math.abs(other.pos.Z - tz) < (other.size.Z + size.Z) / 2 + GAP
				and math.abs(other.pos.Y - ty) < (other.size.Y + size.Y) / 2 then
				return nil
			end
		end
	end

	return dy
end

-- The ring, opening straight out of the corridor on the side the prop is already on: the shortest
-- move that could possibly clear it, which is `MapGates.relocate`'s own opening bid. Everything past
-- that is tried in growing rings so the NEAREST spot that works wins, whichever way it lies.
local function findSpot(job, front, fronts, props, cx, entrance)
	local px, pz = job.pos.X - front.ox, job.pos.Z - front.oz
	local side = (-px * front.dz + pz * front.dx) >= 0 and 1 or -1
	local base = math.atan2(front.dx * side, -front.dz * side)

	for ring = 0, MOVE_RINGS - 1 do
		local r = MIN_MOVE + ring * MOVE_STEP
		for k = 0, MOVE_ARCS - 1 do
			for _, sgn in ipairs(k == 0 and { 1 } or { 1, -1 }) do
				local ang = base + sgn * k * (math.pi / MOVE_ARCS)
				local tx = job.pos.X + math.cos(ang) * r
				local tz = job.pos.Z + math.sin(ang) * r
				local dy = fits(job, tx, tz, fronts, props, cx, entrance)
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
	for _, job in ipairs(jobs) do
		if moved + dropped >= MAX_MOVES then
			capped = true
			break
		end
		local p = job.prop
		if p.inst.Parent then
			local tx, tz, dy = findSpot(p, job.front, fronts, props, cx, entrance)
			if tx then
				p.inst:PivotTo(p.inst:GetPivot() + Vector3.new(tx - p.pos.X, dy, tz - p.pos.Z))
				-- RE-MEASURED FROM THE INSTANCE, not assumed from the shift: a Model's box is
				-- pivot-frame and reading it back is the only thing that makes the next prop's
				-- overlap test true (`probe-restore-must-be-read-back`, one scale down).
				local np, ns = boxOf(p.inst)
				p.pos, p.size = np, ns
				moved += 1
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
				held[p.inst.Name] = (held[p.inst.Name] or 0) + 1
				dropped += 1
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
	print(("[MapClearance] %s: %d frontages, %d props considered, %d in the way, moved %d, "
		.. "could not place %d%s, left standing %s, tightest %s%s")
		:format(zoneKey, summary.fronts, summary.considered, summary.inTheWay, moved, dropped,
			next(droppedNames) and (" (" .. tally(droppedNames) .. ")") or "", tally(held),
			tightest == math.huge and ("clear to %d studs"):format(SIGHT_FAR)
				or ("%.1f studs at %s (%s)"):format(tightest, tightFront, tightProp),
			capped and (" -- STOPPED AT THE %d-PROP CAP"):format(MAX_MOVES) or ""))

	return summary
end

return MapClearance
