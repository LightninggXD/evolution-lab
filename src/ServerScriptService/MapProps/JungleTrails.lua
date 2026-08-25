local PathSplines = require(script.Parent.PathSplines)
-- MapProps/JungleTrails -- the roads that actually reach the camps. Data only; nothing here builds
-- or paints anything. `JungleLayout` owns WHERE the camps are and calls this to work out how a
-- player gets to them; `MapJungle` paints what comes back and `MapForest` keeps its wood out of it.
--
-- ===== THE ROW THIS FILE IS (32.1) =====
-- Her complaint, walking Forest: *"the road does not take you to the mobs"*. 31.24's commit
-- promised a `JungleRings` pass that would re-place the ring against the shrunken camps, and the
-- ring was measured to be impossible: the inner camp column sits at |x| 313..325 and the outer at
-- 400..436, and their 46-stud floors leave FIVE studs of corridor between them. There is nowhere
-- to thread a road, so the ring rows are deleted rather than moved.
--
-- ===== WHAT REPLACES IT, AND WHY IT IS A TREE AND NOT A CHAIN =====
-- The approved design was a per-quadrant CHAIN: greedy nearest-neighbour from the quadrant's
-- village anchor, through its five camps, out to its cross anchor. It was built that way first and
-- **measured worse than what it replaced** -- mean detour 4.18x against today's 3.51x -- and the
-- reason is structural rather than a bad chain: a chain is SERIAL. `SW3` stands 45 studs off the
-- village wall and is fourth in its quadrant's chain, so reaching it meant walking the whole loop
-- out to `SW2`/`SW4` and back. Every camp after the second pays for every camp before it.
--
-- So the shape is a TREE grown from the village outward, and the chains fall out of it by
-- themselves: an outer camp connects through its inner neighbour because that really is the
-- shortest way to it, while a camp beside the village connects straight to the cross. Same
-- rim-to-rim links, same "the road stops at the mouth" rule -- different root.
--
-- MEASURED over the same network model, before and after:
--     mean walk to a camp   395 -> 215 studs
--     worst walk            795 -> 349 studs
--     mean detour          3.51x -> 2.30x
--     paved                2944 -> 1778 studs
--
-- ===== THE 1.6x TARGET IS NOT REACHABLE FROM THIS VILLAGE, AND THAT IS A MEASUREMENT =====
-- 32.1 asks for a mean detour under ~1.6x. The remainder is not road design, it is DOORS: the
-- village has four ways out (the two plaza corners, the two flank gates at z = -100, the south
-- lane) and nothing on its north or west faces. `SW3` is 45 studs of grass from the village wall
-- and 191 studs of road, because the nearest door is 200 studs away.
--
-- The obvious answer -- a belt road hugging the village, joining the plaza corners to the flank
-- gates -- was worked out and does not fit. The inner camps stand 43..54 studs off the village
-- wall, so a belt clear of their floors by a road's half-width would have to run at |x| <= 263,
-- and the village floor reaches 270.5. It is the ring problem again, one ring in. Widening the
-- walk is a village-exit row, not a road-network one.
--
-- ===== WHY A LINK STOPS AT THE RIM AND RESUMES AT THE NEXT ONE =====
-- This is what dissolves the corridor problem the ring died of. A road that runs from camp A's
-- MOUTH to camp B's MOUTH never has to pass BETWEEN two camps -- it ends at one floor and begins
-- again at the other, and the 92-stud dirt disc in between is the road. It also means the paint
-- never lies across a clearing: `MapJungle` draws the floor above the trail, so the 14 studs a link
-- overshoots into the floor are covered by it (`SPUR_OVERSHOOT`'s own rule, at the other kind of
-- join).
--
-- A GRAPH PROBE THAT DOES NOT KNOW THIS CALLS THE NETWORK DISCONNECTED. Two consecutive links are
-- 60+ studs apart across a camp, so a reachability check that joins nodes within a road's width
-- reports every quadrant unreachable -- which is the same trap the roadmap already records for
-- querying a camp CENTRE. The floor is walkable ground and has to be a node.

local JungleTrails = {}

-- ===== THE VILLAGE'S ONLY NORTH DOORS =====
-- `HubPlaza`'s deck is 344 x 336 spanning x -172..172, z 74..422, so both of these stand ON it --
-- a player who has just spawned can turn either way into the wood without walking through the
-- village first. This is the half of the network that did not exist: the measurement that opened
-- this row found NW1/NE1 at a 13.9x detour for exactly this reason, 54 studs of grass against 749
-- studs of road, because the north side had no exit but the plaza itself.
JungleTrails.HEADS = {
	{ x = -150, z = 390 },
	{ x =  150, z = 390 },
}

-- Narrower than any cross trunk (56/46) and wider than the spurs it replaces (26). A trail is not
-- a main road and should not read as one; against an 8.4-stud body 30 studs is two abreast, which
-- is what a path through a wood looks like.
JungleTrails.WIDTH = 30

-- How far OUTSIDE the village rectangle a trail must stay. The road's own half-width is added on
-- top, so this is clearance between the paint and the village floor rather than centre lines.
local VILLAGE_MARGIN = 10

-- ===== GEOMETRY =====

local function distToSegment(px, pz, x1, z1, x2, z2)
	local dx, dz = x2 - x1, z2 - z1
	local len2 = dx * dx + dz * dz
	local t = 0
	if len2 > 0 then
		t = math.clamp(((px - x1) * dx + (pz - z1) * dz) / len2, 0, 1)
	end
	local qx, qz = x1 + dx * t, z1 + dz * t
	return math.sqrt((px - qx) ^ 2 + (pz - qz) ^ 2), qx, qz
end

-- Does the segment touch the axis-aligned box `|x| <= hx, |z| <= hz`? Liang-Barsky, so it is exact
-- rather than sampled -- a sampler with a 40-step stride walks straight through a corner clip, and
-- a corner clip is the case that actually happens here (the first build of this file ran a link
-- from SW1 to SW5 across the village's south-west corner and four samples caught it by luck).
local function hitsBox(x1, z1, x2, z2, hx, hz)
	local t0, t1 = 0, 1
	local d = { x2 - x1, z2 - z1 }
	local p0 = { x1, z1 }
	local h = { hx, hz }
	for i = 1, 2 do
		if math.abs(d[i]) < 1e-9 then
			if p0[i] < -h[i] or p0[i] > h[i] then return false end
		else
			local a = (-h[i] - p0[i]) / d[i]
			local b = (h[i] - p0[i]) / d[i]
			if a > b then a, b = b, a end
			t0 = math.max(t0, a)
			t1 = math.min(t1, b)
			if t0 > t1 then return false end
		end
	end
	return true
end

-- ===== ONE LINK, RIM TO RIM =====
-- `from` is either a point on the cross (or a plaza head), in which case the road starts there, or
-- another camp's centre, in which case it starts at that camp's mouth. It always ENDS at the mouth
-- of `camp`. `mouth` is `CAMP_RADIUS - SPUR_OVERSHOOT`, so both ends run under the floor's rim and
-- onto the dirt rather than stopping on the grass beside it.
local function link(fx, fz, fromCamp, camp, o)
	local a = math.atan2(camp.z - fz, camp.x - fx)
	local sx, sz = fx, fz
	if fromCamp then
		sx = fx + math.cos(a) * o.mouth
		sz = fz + math.sin(a) * o.mouth
	end
	local ex = camp.x - math.cos(a) * o.mouth
	local ez = camp.z - math.sin(a) * o.mouth
	return sx, sz, ex, ez
end

-- Everything a link is not allowed to do. All three are faults a screenshot finds days later and
-- no per-camp check ever sees, which is why they are one function called on every candidate rather
-- than an assertion at the end.
local function usable(sx, sz, ex, ez, aId, bId, camps, o)
	--   1. it must not lie across a camp floor it does not serve. This is the ring's own fault --
	--      creatures standing in the traffic -- and it is the reason the ring rows are gone.
	for _, c in ipairs(camps) do
		if c.id ~= aId and c.id ~= bId then
			local d = distToSegment(c.x, c.z, sx, sz, ex, ez)
			if d - o.width / 2 - o.campRadius < 0 then return false end
		end
	end
	--   2. it must not run over the village. The village floor is the map, with its own roads,
	--      squares and buildings on it; a jungle trail painted across it is a dirt stripe through
	--      the shops.
	if hitsBox(sx, sz, ex, ez,
		o.villageHalfX + VILLAGE_MARGIN + o.width / 2,
		o.villageHalfZ + VILLAGE_MARGIN + o.width / 2) then
		return false
	end
	--   3. it must stay on the platform. Both ends is enough -- the keep-out is convex, so a
	--      segment with both ends inside it is inside it.
	if math.abs(sx) > o.edgeX or math.abs(ex) > o.edgeX
		or math.abs(sz) > o.edgeZ or math.abs(ez) > o.edgeZ then
		return false
	end
	return true
end

-- ===== THE NETWORK =====
-- Grown outward from the village, cheapest camp first: at every step, of every camp not yet on the
-- network, connect the one whose total walk from a village door is least. That is Dijkstra with the
-- cross as the source, and it is what makes the walk short BY CONSTRUCTION rather than by a lucky
-- ordering -- which is the whole difference between this and the chain it replaced.
--
-- Crossing a parent camp costs `campRadius`, because that is what the player actually walks: a link
-- ends at one mouth and the next begins at another, and the floor between them is the road.
--
-- `opts` carries every constant from `JungleLayout` rather than this file re-deriving any of them.
-- One copy of the camp radius, one copy of the village rectangle -- the fault that comment is
-- guarding against is 31.5a, where `a`/`b` were read as widths in one of two files and 74 rigs
-- ended up over the void.
function JungleTrails.Build(camps, cross, opts)
	local o = {
		width = opts.width or JungleTrails.WIDTH,
		mouth = opts.mouth,
		campRadius = opts.campRadius,
		villageHalfX = opts.villageHalfX,
		villageHalfZ = opts.villageHalfZ,
		edgeX = opts.edgeX,
		edgeZ = opts.edgeZ,
	}

	local cost, connected, out = {}, {}, {}
	local left = #camps

	while left > 0 do
		local best = nil
		for _, camp in ipairs(camps) do
			if not connected[camp.id] then
				-- every place this camp could hang off: the cross, a plaza head, or a camp that is
				-- already on the network
				local anchors = {}
				for _, p in ipairs(cross) do
					local _, qx, qz = distToSegment(camp.x, camp.z, p.x1, p.z1, p.x2, p.z2)
					anchors[#anchors + 1] = { x = qx, z = qz, from = nil, base = 0 }
				end
				for _, h in ipairs(JungleTrails.HEADS) do
					anchors[#anchors + 1] = { x = h.x, z = h.z, from = nil, base = 0 }
				end
				for _, c in ipairs(camps) do
					if connected[c.id] then
						anchors[#anchors + 1] = { x = c.x, z = c.z, from = c, base = cost[c.id] + o.campRadius }
					end
				end
				for _, a in ipairs(anchors) do
					local sx, sz, ex, ez = link(a.x, a.z, a.from, camp, o)
					local aId = a.from and a.from.id or nil
					if usable(sx, sz, ex, ez, aId, camp.id, camps, o) then
						local len = math.sqrt((ex - sx) ^ 2 + (ez - sz) ^ 2)
						local total = a.base + len
						if best == nil or total < best.total then
							best = {
								total = total, camp = camp, from = a.from,
								sx = sx, sz = sz, ex = ex, ez = ez, len = len,
							}
						end
					end
				end
			end
		end

		-- ===== A CAMP NOTHING CAN REACH IS NAMED, NOT SKIPPED =====
		-- Every candidate for some camp was rejected. That is not a road problem -- it means the
		-- camp is boxed in by other camps' floors or by the village -- and it is exactly the class
		-- of fault that 31.24's "0 spurs" line caught by accident. Stop, say which, and let
		-- `Describe` print it: a network quietly one camp short is a camp nobody can walk to.
		if best == nil then
			local stuck = {}
			for _, c in ipairs(camps) do
				if not connected[c.id] then stuck[#stuck + 1] = c.id end
			end
			JungleTrails.Unreachable = stuck
			break
		end

		cost[best.camp.id] = best.total
		connected[best.camp.id] = true
		left -= 1
		local startPos = Vector3.new(best.sx, 0, best.sz)
		local endPos = Vector3.new(best.ex, 0, best.ez)
		local obs = {}
		for _, c in ipairs(camps) do
			if c.id ~= best.camp.id and (not best.from or c.id ~= best.from.id) then
				table.insert(obs, { type="circle", x = c.x, z = c.z, r = o.campRadius + 5 })
			end
		end
		table.insert(obs, { type="rect", x = 0, z = 0, hx = o.villageHalfX + 15, hz = o.villageHalfZ + 15 })
		
		local rng = opts.rng or Random.new(math.floor(math.abs(best.sx + best.sz)))
		local pts = PathSplines.Route(startPos, endPos, rng, { maxJitter = 15 }, obs)
		
		if #pts >= 2 then
			for i = 1, #pts - 1 do
				out[#out + 1] = {
					id = best.camp.id .. "trail" .. (i > 1 and "_"..i or ""),
					x1 = pts[i].x, z1 = pts[i].z, x2 = pts[i+1].x, z2 = pts[i+1].z,
					w = o.width,
					tier = "trail",
					caps = (i == 1) and "both" or "b",
					serves = { [best.camp.id] = true, [best.from and best.from.id or ""] = true },
					parent = best.from and best.from.id or nil,
					walk = (i == 1) and best.total or 0,
				}
			end
		else
			out[#out + 1] = {
				id = best.camp.id .. "trail",
				x1 = best.sx, z1 = best.sz, x2 = best.ex, z2 = best.ez,
				w = o.width,
				tier = "trail",
				serves = { [best.camp.id] = true, [best.from and best.from.id or ""] = true },
				parent = best.from and best.from.id or nil,
				walk = best.total,
			}
		end
	end

	JungleTrails.Unreachable = JungleTrails.Unreachable or {}
	JungleTrails.Cost = cost
	return out
end

-- One line for the boot log. The MEAN and WORST walk are the row's complaint in two numbers -- a
-- ratio is not enough on its own, because the camps with the worst ratios (`SW3` at 4.2x) are the
-- ones standing 45 studs from the village wall, where a short road still looks like a long detour.
function JungleTrails.Describe(segments)
	local n, total, worst, worstId = 0, 0, 0, "-"
	for _, s in ipairs(segments) do
		if s.tier == "trail" then
			n += 1
			total += s.walk
			if s.walk > worst then worst, worstId = s.walk, s.id end
		end
	end
	return ("%d trails, walk to a camp: mean %.0f studs, worst %s at %.0f%s")
		:format(n, n > 0 and total / n or 0, worstId, worst,
			#JungleTrails.Unreachable > 0
				and ("  <-- NO ROAD REACHES " .. table.concat(JungleTrails.Unreachable, ", ")) or "")
end

return JungleTrails
