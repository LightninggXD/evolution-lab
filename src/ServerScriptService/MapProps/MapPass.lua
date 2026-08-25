-- MapProps/MapPass -- the walk-and-sight corridor cut through the horizon range to the portal
-- gate, and the rocks that dress the hole it leaves.
-- ===== WHY DEPTH AND NOT WIDTH (32.28) =====
-- The owner, 2026-08-25, with a screenshot: *"otvori ovaj portal da se vidi"*. Measured on the
-- live world, not argued: a ray from the village to the gate at (0, 69, -575) is BLOCKED by
-- `Workspace.Folder.HorizonHill.Meshes/gora` at (0, 69, -571). The offenders are OUTER-row
-- hills -- two of them about 480 x 620 standing at (-105, -785) and (118, -779), whose front
-- faces reach z = -472, i.e. a hundred studs IN FRONT of the door. The `LANE_PORTAL` notch only
-- opens the wall to z -534, so the lane was never too NARROW -- it is 41 studs too SHALLOW.
-- That is why widening it (90 -> 132 -> 240) was tried twice and reverted twice: widening bares
-- the boundary wall and never touches the hill that is actually in the way. A scratch cut in
-- the Edit world proved the shape of this fix: seven hill groups meet a corridor of
-- x +-100, z -660..-460, and removing them clears the walk line.
--
-- `LANE_PORTAL` IS NOT TOUCHED: it is another file's reservation, and the width answer was
-- already taken (and reverted) twice.
--
-- ===== ORDER: BETWEEN BUILD AND PLANT, AND THAT IS THE WHOLE FIX =====
-- The call site runs this after `MapHorizon.Build` + `TintWall` and BEFORE `MapForest.Plant`.
-- Build creates the hills -- a cut before it cuts nothing. And Plant is what turns the
-- survivors' boxes into `HorizonHillCollider` parts (`MapSolids.OfferHill`) and wood keep-outs,
-- BOTH read from the tables this file purges -- so a hill deleted here leaves neither an
-- invisible wall (32.15/32.19 all over again) nor a ghost no-tree patch in the pass.
-- [[evolution-lab-placement-search-ordering]]: a pass only knows the world that ran before it.
--
-- ===== NO RAYCAST DECIDES ANYTHING HERE (rule 5) =====
-- Offenders come from rectangle intersection against the WORLD-AXIS boxes of the models Build
-- stood up -- pure functions of the seeded tables; the dressing rocks sit on the fixed y-plane
-- every horizon hill uses, sunk, not on a cast.
--
-- ===== AND THE HOLE IS DRESSED, BECAUSE A BARE HOLE READS AS A BUG =====
-- Seven hills gone is a canyon with saw-cut faces unless something stands at its mouth: stock
-- mountains come back at outcrop scale (16..30 studs against the range's 294), flanking the
-- mouth in staggered lines -- a pass THROUGH a range, not a corridor punched through one.

local MapPass = {}

local MapHorizon = require(script.Parent.MapHorizon)
local MapRidge = require(script.Parent.MapRidge)

-- ===== THE CORRIDOR, MEASURED (see header) =====
-- x +-100: wider than the walk needs so the SIGHT line from village eye height clears the cut
-- faces too. z -660 reaches PAST the gate (-575) into the void side, so the skyline opens over
-- the pass instead of ending in a cliff face at the door. z -460 stops 115 short of the gate:
-- deeper than that starts eating the inner row's skirt behind the wall, and the boundary wall
-- behind those hills is bare and it shows.
local CORRIDOR_HALF_X = 100
local CORRIDOR_Z_MIN, CORRIDOR_Z_MAX = -660, -460

-- The gate this whole row serves -- only for the boot line's "nearest rock" figure.
local GATE_Z = -575

-- Seeded off the zone like every scatter in these lanes (`MapHorizon` uses 20260823): rule 4.
local SEED = 20260825

-- ===== THE DRESSING =====
-- Ten scaled stock mountains flanking the mouth, turned +90 deg so the stock's long axis runs
-- ALONG the walk -- crags framing a pass, not lumps dropped beside it. Heights 16..30: tall
-- enough to cap the cut faces, a tenth of the peaks either side. |x| held to 70..95 -- outside
-- the 56-wide trunk road, outside the 62-stud creature keep-out, inside the corridor: nothing
-- dressed pinches the walk line it exists to open.
local ROCK_COUNT = 10
local ROCK_X_MIN, ROCK_X_MAX = 70, 95
local ROCK_Z_NEAR, ROCK_Z_FAR = -468, -566
local ROCK_H_MIN, ROCK_H_MAX = 16, 30
local ROCK_SINK = 3

local DRESS_FOLDER = "PortalPassDressing"

-- World-axis extents of a placed model, summed over its parts -- a rotated part's AABB is not
-- its Size, and `Model:GetBoundingBox` answers in the pivot frame (the 32.15 lesson).
local function spanXZ(model)
	local mnx, mxx = math.huge, -math.huge
	local mnz, mxz = math.huge, -math.huge
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local c, sz, p = d.CFrame, d.Size, d.Position
			local hx = (math.abs(c.RightVector.X) * sz.X + math.abs(c.UpVector.X) * sz.Y
				+ math.abs(c.LookVector.X) * sz.Z) / 2
			local hz = (math.abs(c.RightVector.Z) * sz.X + math.abs(c.UpVector.Z) * sz.Y
				+ math.abs(c.LookVector.Z) * sz.Z) / 2
			mnx, mxx = math.min(mnx, p.X - hx), math.max(mxx, p.X + hx)
			mnz, mxz = math.min(mnz, p.Z - hz), math.max(mxz, p.Z + hz)
		end
	end
	if mxx == -math.huge then return nil end
	return mnx, mxx, mnz, mxz
end

-- The map's own mountain stock, the way `MapHorizon.stockOf` looks for it: inside the PLACED
-- map first, then `MapRidge`'s parked clone (there is usually no mountain left to copy).
local function rockStock(map)
	if map then
		for _, c in ipairs(map:GetChildren()) do
			if c:IsA("Model") then
				for _, d in ipairs(c:GetDescendants()) do
					if d:IsA("MeshPart") and d.Name:find("gora") then return c end
				end
			end
		end
	end
	return MapRidge.Stock()
end

-- ===== THE ONE ENTRY POINT =====
function MapPass.Cut(zoneKey, cx, map)
	local removed, gone = {}, {}
	local folder = map and map:FindFirstChild("Horizon")
	if folder then
		for _, m in ipairs(folder:GetChildren()) do
			if m:IsA("Model") and m.Name == "HorizonHill" then
				local mnx, mxx, mnz, mxz = spanXZ(m)
				if mnx and mxx >= cx - CORRIDOR_HALF_X and mnx <= cx + CORRIDOR_HALF_X
					and mxz >= CORRIDOR_Z_MIN and mnz <= CORRIDOR_Z_MAX then
					removed[#removed + 1] = { model = m, wx = (mnx + mxx) / 2, wz = (mnz + mxz) / 2 }
					gone[m] = true
				end
			end
		end
		for _, r in ipairs(removed) do r.model:Destroy() end
	end

	-- Purge the published tables BEFORE the next consumer reads them: `Solid` feeds
	-- `MapHorizon.Colliders`, which `MapForest.Plant` turns into collider boxes; `Placed` feeds
	-- the wood's keep-out. A stale entry is an invisible wall or a bald patch in the pass.
	local solid = MapHorizon.Solid[zoneKey]
	for i = solid and #solid or 0, 1, -1 do
		if gone[solid[i].model] then table.remove(solid, i) end
	end
	local placed = MapHorizon.Placed[zoneKey]
	for i = placed and #placed or 0, 1, -1 do
		local e = placed[i]
		for _, r in ipairs(removed) do
			-- Exact same derivation (`wx - cx`, `wz` off the same model), so a hair's tolerance
			-- is already generous; a wrong match here would unreserve a hill that still stands.
			if math.abs(e.x - (r.wx - cx)) < 0.5 and math.abs(e.z - r.wz) < 0.5 then
				table.remove(placed, i)
				break
			end
		end
	end

	-- ===== DRESS THE MOUTH =====
	local old = map and map:FindFirstChild(DRESS_FOLDER)
	if old then old:Destroy() end
	local dress = Instance.new("Folder")
	dress.Name = DRESS_FOLDER
	dress.Parent = map

	local proto = rockStock(map)
	local dressed, nearest = 0, nil
	if proto then
		local rng = Random.new(SEED + math.floor(cx))
		for i = 1, ROCK_COUNT do
			local side = (i % 2 == 0) and 1 or -1
			local t = (i - 1) / (ROCK_COUNT - 1)
			local x = side * rng:NextNumber(ROCK_X_MIN, ROCK_X_MAX)
			local z = ROCK_Z_NEAR + t * (ROCK_Z_FAR - ROCK_Z_NEAR) + rng:NextNumber(-8, 8)
			local m = proto:Clone()
			local _, raw = m:GetBoundingBox()
			if raw.Y >= 1 then
				-- Scale, turn, RE-MEASURE, move -- in that order and in separate steps, for the
				-- reason `MapHorizon.hill` keeps on record: a rotated model is a different box.
				m:ScaleTo(rng:NextNumber(ROCK_H_MIN, ROCK_H_MAX) / raw.Y)
				m:PivotTo(CFrame.new(m:GetPivot().Position)
					* CFrame.Angles(0, math.pi / 2 + rng:NextNumber(-0.3, 0.3), 0))
				local cf, sz = m:GetBoundingBox()
				m:PivotTo(m:GetPivot() + Vector3.new(x - cf.Position.X,
					-(cf.Position.Y - sz.Y / 2) - ROCK_SINK, z - cf.Position.Z))
				for _, d in ipairs(m:GetDescendants()) do
					if d:IsA("BasePart") then
						d.Anchored = true
						-- These are 16-30 stud crags, not 300-stud peaks: a direct box costs
						-- nothing and means nothing walks through the dressing (owner rule).
						d.CanCollide = true
						d.CanQuery = true
						d.CastShadow = false
					end
				end
				m.Name = "PassRock"
				m.Parent = dress
				dressed += 1
				if not nearest or math.abs(z - GATE_Z) < math.abs(nearest - GATE_Z) then
					nearest = z
				end
			else
				m:Destroy()
			end
		end
	end

	-- A TEST, not a count: nearest-rock-z against gate-z says the mouth is dressed to the door.
	print(("[MapPass] %s: cut %d hills from the portal corridor, dressed %d rocks, "
		.. "nearest rock now z %.1f (gate at %.1f)")
		:format(zoneKey, #removed, dressed, nearest or 0, GATE_Z))
	return #removed, dressed
end

-- Exported for MapGateFlanks, which dresses the wall either side of her arch from the same stock
-- -- a second copy of the placed-map-then-Ridge-fallback lookup would be the
-- [[evolution-lab-zone-geometry-constants]] drift all over again.
MapPass.RockStock = rockStock

return MapPass
