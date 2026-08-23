-- MapProps/MapCut -- what counts as foliage, and how a lane is cut through it.
--
-- This is `ForestMapService`'s own entrance cutter, lifted out so that a SECOND road can use it.
-- 31.19 opened three more corridors (the village's south, west and east gates) and the alternative
-- was a second copy of `isFoliage` in `MapGates` -- which is `evolution-lab-zone-geometry-constants`
-- exactly: one decision written in two files. The lesson 31.5a paid for is that the two copies do
-- not drift loudly, they drift silently, and the thing you find afterwards is 74 rigs standing over
-- the void.
--
-- It is a module and not a function argument because `ForestMapService` requires `MapGates` and
-- `MapGates` needs the cutter: passing it down as a parameter works, but a shared leaf module is
-- what stops the next caller inventing a third route to the same rule.
--
-- ===== TWO THINGS CHANGED WHEN THE SOUTH GATE WAS MEASURED =====
-- Both were found by scanning candidate lanes and reading what the scan REFUSED to cut, which is
-- the only way either of them was ever going to surface.
--
--   1. A LOOSE `Top` / `Bottom` / `Leaves` / `Branch` BASEPART IS A TREE. The old rule read those
--      four names only inside a Model, so the fourteen leaf and trunk parts that sit directly under
--      this map -- trees that lost their Model somewhere in the asset's own history -- classified as
--      buildings and were never cut. Two of them are standing in the south lane, 75 and 45 studs
--      tall, and the lane report called them furniture.
--   2. A PAPER-THIN OPAQUE WALL INSIDE A LANE IS SCENERY WITH NO JOB. The map ships three of them,
--      all 0.5 studs thick and 60-100 studs long: two are the backing walls the portal ring and the
--      leaderboard ring are mounted on, and the third stands alone at zone (8, -123) with nothing
--      on it at all -- the third hall this asset had, whose props we have since repurposed. The
--      shape rule only ever fires INSIDE a lane, which is what keeps the two that are doing a job.

local MapCut = {}

-- Foliage, as opposed to the village. The source names its greenery two ways: by name
-- (`Pine Tree 02`, `Bush2`, `Rock 01`, `Trunk 01`) and by shape -- 60 of the trees in the northern
-- wood are called nothing but `Model`, and what identifies them is that every part they own is
-- `Top` / `Bottom` / `Leaves` / `Branch`. A prop with anything else in it is a building, a stall or
-- a pedestal and is never touched by this.
-- "Stump" joined the list the way every other name on it did: a body box stopped on one. A
-- 7 x 4 x 6 stump on the south lane's centre line is not a name anybody would have thought to add.
local FOLIAGE_PREFIX = { "Pine Tree", "Tree", "Bush", "Flower", "Rock", "Trunk", "Leaves", "Shrub",
	"Stump" }
local FOLIAGE_PART = { Top = true, Bottom = true, Leaves = true, Branch = true }

function MapCut.IsFoliage(c)
	for _, p in ipairs(FOLIAGE_PREFIX) do
		if c.Name:sub(1, #p) == p then return true end
	end
	-- See note 1 above. A bare part carrying one of the four leaf names is a tree that lost its
	-- Model, and there are fourteen of them in this map.
	if c:IsA("BasePart") then return FOLIAGE_PART[c.Name] == true end
	if not c:IsA("Model") then return false end
	local leafy, other = 0, 0
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("BasePart") then
			if FOLIAGE_PART[d.Name] then leafy += 1 else other += 1 end
		end
	end
	return leafy > 0 and other == 0
end

-- See note 2 above. Thin on one horizontal axis, long on the other, and tall enough to stop a
-- player: that is a backdrop, not a building. Measured on this map's three: 0.49 / 0.71 studs thick
-- against 60 / 95 / 96 studs long.
function MapCut.IsBlankWall(c)
	if not c:IsA("BasePart") then return false end
	local s = c.Size
	local thin = math.min(s.X, s.Z)
	local long = math.max(s.X, s.Z)
	return thin <= 1.5 and long >= 40 and s.Y >= 20
end

-- Nothing under this stays a decision the whole file depends on: flowers and flat rocks do not
-- block a walk and do not hide a doorway, and a road scrubbed to bare ground reads as a demolition
-- rather than a path.
MapCut.MIN_HEIGHT = 5

-- Cuts one lane. `lane` is `{ x1, z1, x2, z2, halfA, halfB }` in ZONE-RELATIVE studs -- `cx` shifts
-- x onto the zone's platform, exactly as `ForestMapService.seat` placed the map.
--
-- THE TEST IS THE PROP'S CENTRE, NOT ITS FOOTPRINT, and that is the difference between a road and
-- a trench: a tree rooted outside the corridor with its canopy hanging over it is what a road
-- through a wood looks like, and clearing by footprint takes every one of them and leaves two
-- straight walls. `t` is NOT clamped -- a prop past either end of the lane is past the lane.
--
-- Returns `cut, stay`. **`stay` is the point of the second return value**: it is every prop the
-- lane found and refused to remove, and the caller is expected to PRINT it. A lane with a house in
-- the middle of it is a lane that does not work, and there is no probe in this repo that would ever
-- ask the question -- 31.16's own note is that a walkability grid measures collision and says
-- nothing at all about whether a route can be followed.
function MapCut.Lane(map, cx, lane, protected)
	local cut, stay = 0, {}
	local dx, dz = lane.x2 - lane.x1, lane.z2 - lane.z1
	local len2 = dx * dx + dz * dz
	if len2 <= 0 then return 0, stay end

	for _, c in ipairs(map:GetChildren()) do
		if c.Name ~= "MainPart" and c.Name ~= "Terrain" then
			-- Initialised, not forward-declared. A bare `local a, b` is the exact shape
			-- `tools/luanames.py` documents nine false positives of, and `JungleLayout` carries
			-- the same note for the same reason: one more line a future reader has to decide is
			-- harmless is one line too many.
			local pos, size = nil, nil
			if c:IsA("Model") then
				local cf, s = c:GetBoundingBox()
				pos, size = cf.Position, s
			elseif c:IsA("BasePart") then
				pos, size = c.Position, c.Size
			end
			if pos and size.Y >= MapCut.MIN_HEIGHT then
				local rx, rz = pos.X - cx, pos.Z
				local t = ((rx - lane.x1) * dx + (rz - lane.z1) * dz) / len2
				if t >= 0 and t <= 1 then
					local qx, qz = lane.x1 + dx * t, lane.z1 + dz * t
					local d = math.sqrt((rx - qx) ^ 2 + (rz - qz) ^ 2)
					if d <= lane.halfA + (lane.halfB - lane.halfA) * t then
						-- ===== PROTECTION MEANS "NEVER DESTROY", NOT "NEVER LOOK AT" (32.4) =====
						-- The protected test is load-bearing on the DESTROY: the egg row sits inside
						-- the entrance funnel and `IsFoliage` classifies by PART NAME as well as by
						-- prop name, so a prop whose parts are all Top / Bottom / Leaves / Branch is
						-- foliage to it whatever it actually is. Without it the road is cut straight
						-- through the shop.
						--
						-- It used to guard the whole prop, and that is the second half of "props in
						-- the road". A protected prop never reached `stay`, so `MapGates`' relocation
						-- pass -- the one thing in this codebase whose entire job is moving a
						-- building out of a lane -- could not see one. Measured on the live map: the
						-- Shop market stall stands 18.2 studs off the south lane's centre line with
						-- its own footprint reaching to 9.0, and the daily-spin wheel stands 11.1 off
						-- it reaching to 4.4. Both are inside a driving line that is 24 studs to a
						-- side, on the main road out of the village, and a body-box walk down the
						-- lane is stopped by both. Neither was ever a candidate to be moved.
						--
						-- So the guard moved onto the branch it was written for. Everything the lane
						-- finds and refuses to remove is reported, which is what `stay` says it is.
						if not (protected and protected[c])
							and (MapCut.IsFoliage(c) or MapCut.IsBlankWall(c)) then
							c:Destroy()
							cut += 1
						else
							stay[#stay + 1] = { name = c.Name, x = rx, z = rz,
								w = math.max(size.X, size.Z), inst = c }
						end
					end
				end
			end
		end
	end
	return cut, stay
end

-- ===== AND A SECOND, NARROWER PASS THAT CUTS BY FOOTPRINT =====
-- `Lane` above tests a prop's CENTRE, and that is right for the shape of a road: a tree rooted
-- outside the corridor leaning over it is what a road through a wood looks like, and a footprint
-- test at the full width takes every one of them and leaves two straight walls.
--
-- It is NOT right for the strip you actually walk on, and a body-box walk down the three finished
-- village lanes is what said so -- 8, 8 and 3 blocked cells, every one of them a `Model.Top` or a
-- `Trunk 01` whose trunk stands outside the lane and whose canopy hangs into it. **The map's own
-- trees collide** (unlike the ones `MapForest` plants, which are deliberately `CanCollide = false`
-- for the 30.19 reason), so an overhanging branch is a wall you cannot see the bottom of.
--
-- So the rule is split, and the split is the useful part: cut by CENTRE at the road's half-width,
-- then cut by FOOTPRINT over the DRIVING LINE only. The verge keeps its leaning trees and the
-- middle is clear, which is both of the things a road is supposed to be.
--
-- `minHeight` is the other half of the same split, and it defaults to `MIN_HEIGHT` so no existing
-- caller changes. The 5-stud floor is written for a VERGE -- "flowers and flat rocks do not block a
-- walk and a road scrubbed to bare ground reads as a demolition" -- and on the driving line it is
-- simply false: a body-box walk down the finished lanes was still blocked by `Rock 02` and
-- `Stump01`, three and four studs tall, sitting exactly on the centre line. Knee-high scenery is
-- charming beside a road and is a stubbed toe in the middle of one, so the caller that owns the
-- driving line passes 2 and the verge keeps its 5.
--
-- The perpendicular reach is the exact support of an axis-aligned box along the lane's normal --
-- `|nx| * sx/2 + |nz| * sz/2` -- and not the bounding radius, because a 48-stud canopy has a
-- 34-stud radius and would swallow the verge again by a different route.
function MapCut.LaneFootprint(map, cx, lane, clearHalf, protected, minHeight)
	local cut = 0
	local dx, dz = lane.x2 - lane.x1, lane.z2 - lane.z1
	local len2 = dx * dx + dz * dz
	if len2 <= 0 then return 0 end
	local len = math.sqrt(len2)
	local nx, nz = math.abs(-dz / len), math.abs(dx / len)

	for _, c in ipairs(map:GetChildren()) do
		if c.Name ~= "MainPart" and c.Name ~= "Terrain" and not (protected and protected[c])
			and MapCut.IsFoliage(c) then
			local pos, size = nil, nil
			if c:IsA("Model") then
				local cf, sz = c:GetBoundingBox()
				pos, size = cf.Position, sz
			elseif c:IsA("BasePart") then
				pos, size = c.Position, c.Size
			end
			if pos and size and size.Y >= (minHeight or MapCut.MIN_HEIGHT) then
				local rx, rz = pos.X - cx, pos.Z
				-- CLAMPED here, unlike `Lane`: the question is "does this canopy touch the
				-- corridor", and for a prop past the end the nearest corridor is its end cap.
				local t = math.clamp(((rx - lane.x1) * dx + (rz - lane.z1) * dz) / len2, 0, 1)
				local qx, qz = lane.x1 + dx * t, lane.z1 + dz * t
				local d = math.sqrt((rx - qx) ^ 2 + (rz - qz) ^ 2)
				local reach = nx * size.X / 2 + nz * size.Z / 2
				if d - reach <= clearHalf then
					c:Destroy()
					cut += 1
				end
			end
		end
	end
	return cut
end

return MapCut
