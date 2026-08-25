-- MapProps/MapPass -- the walk-and-sight corridor CUT through the horizon range to the portal
-- gate. The DRESSING of the hole it leaves lives in `MapPassDress` -- split at review R1, because
-- one file was growing two purposes and this half alone is already a scan, a purge and a boot
-- contract.
-- ===== WHY DEPTH AND NOT WIDTH (32.28) =====
-- The owner, 2026-08-25, with a screenshot: *"otvori ovaj portal da se vidi"*. Measured on the
-- live world: a ray from the village to the gate at (0, 69, -575) is BLOCKED by
-- `Workspace.Folder.HorizonHill.Meshes/gora` at (0, 69, -571). The offenders are OUTER-row hills,
-- hundreds of studs wide, whose front faces reach z = -472 -- a hundred studs IN FRONT of the
-- door. The `LANE_PORTAL` notch only opens the wall to z -534, so the lane was never too NARROW,
-- it is 41 studs too SHALLOW. That is why widening it (90 -> 132 -> 240) was tried twice and
-- reverted twice: widening bares the boundary wall and never touches the hill in the way.
-- `LANE_PORTAL` IS NOT TOUCHED here -- it is another file's reservation.
--
-- ===== THE SCAN IS WORKSPACE-WIDE, NOT ONE FOLDER (review R1, fault 1) =====
-- The first cut scanned `map.Horizon` and missed the hill the row NAMED. `Workspace.Folder`
-- holds an orphaned copy of the whole horizon range -- 61 `HorizonHill` models plus 32
-- `HorizonHillCollider` parts at the previous build's coordinates -- and one of them survived
-- every rebuild standing in the corridor (`S1 corridor offenders remaining: 1`). No build pass
-- clears that folder, so the cut cannot learn where hills live from the map; it walks
-- `workspace` and judges every `HorizonHill` by its own world box. Other zones' hills fail the
-- rectangle test on distance (`ZoneSpacing` 1900), so the wide net costs nothing.
--
-- ===== AND EACH ORPHAN TAKES ITS COLLIDER WITH IT =====
-- The real hills get their boxes LATER, from `MapForest.Plant` reading the tables purged below.
-- The orphaned copies shipped with their colliders already BUILT -- a deleted orphan whose
-- `HorizonHillCollider` survives is an invisible wall at the pass, complaint 32.15/32.19 in its
-- purest form. Containment decides, not naming: a collider belongs to the orphan when its centre
-- falls inside the orphan's box (+COLLIDER_SLACK -- those colliders were sized at ROCK_FOOT of
-- these very boxes at these very coordinates, so slack only absorbs float drift).
--
-- NO RAYCAST DECIDES ANYTHING HERE (rule 5): offenders come from rectangle intersection against
-- world-axis boxes -- pure functions of what Build stood up.

local MapPass = {}

local MapHorizon = require(script.Parent.MapHorizon)

-- ===== THE CORRIDOR, MEASURED (see header; identical numbers in `MapPassDress`) =====
local CORRIDOR_HALF_X = 100
local CORRIDOR_Z_MIN, CORRIDOR_Z_MAX = -660, -460

local COLLIDER_SLACK = 4

-- ===== THE ONE ENTRY POINT =====
-- Returns the number of in-map hills cut. `MapPassDress.Init` runs after this and measures the
-- survivors itself, so each file's boot line stays an independent test.
function MapPass.Cut(zoneKey, cx, map)
	local xMin, xMax = cx - CORRIDOR_HALF_X, cx + CORRIDOR_HALF_X
	local found = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("Model") and d.Name == "HorizonHill" then
			local rx, rz, _, wx, wz = MapHorizon.WorldBox(d)
			if rx and wx + rx >= xMin and wx - rx <= xMax
				and wz + rz >= CORRIDOR_Z_MIN and wz - rz <= CORRIDOR_Z_MAX then
				found[#found + 1] = {
					model = d, wx = wx, wz = wz,
					mnx = wx - rx, mxx = wx + rx, mnz = wz - rz, mxz = wz + rz,
					inMap = d:IsDescendantOf(map or workspace),
				}
			end
		end
	end

	-- Collect-then-destroy: nothing dies mid-scan (`MapPortalArt` keeps the same habit).
	local cutInMap, orphaned, colliders = 0, 0, 0
	for _, o in ipairs(found) do
		if o.inMap then
			cutInMap += 1
		else
			orphaned += 1
			local parent = o.model.Parent
			if parent then
				for _, sib in ipairs(parent:GetChildren()) do
					if sib:IsA("BasePart") and sib.Name == "HorizonHillCollider"
						and sib.Position.X >= o.mnx - COLLIDER_SLACK
						and sib.Position.X <= o.mxx + COLLIDER_SLACK
						and sib.Position.Z >= o.mnz - COLLIDER_SLACK
						and sib.Position.Z <= o.mxz + COLLIDER_SLACK then
						sib:Destroy()
						colliders += 1
					end
				end
			end
		end
		o.model:Destroy()
	end

	-- Purge the published tables BEFORE the next consumer reads them, unchanged from the first
	-- cut: `Solid` feeds `Colliders`, which `MapForest.Plant` turns into collider boxes;
	-- `Placed` feeds the wood's keep-out. A stale entry is an invisible wall or a bald patch.
	local gone = {}
	for _, o in ipairs(found) do
		if o.inMap then gone[o.model] = true end
	end
	local solid = MapHorizon.Solid[zoneKey]
	for i = solid and #solid or 0, 1, -1 do
		if gone[solid[i].model] then table.remove(solid, i) end
	end
	local placed = MapHorizon.Placed[zoneKey]
	for i = placed and #placed or 0, 1, -1 do
		local e = placed[i]
		for _, o in ipairs(found) do
			-- Exact same derivation as the build used (`wx - cx`, `wz` off the same model), so a
			-- hair's tolerance is already generous; a wrong match would unreserve a standing hill.
			if o.inMap and math.abs(e.x - (o.wx - cx)) < 0.5 and math.abs(e.z - o.wz) < 0.5 then
				table.remove(placed, i)
				break
			end
		end
	end

	-- A TEST, not a count: `orphaned` > 0 says the wider scan caught what the folder scan missed
	-- (R1 fault 1); once the orphaned copy leaves the place it reads 0, honestly.
	print(("[MapPass] %s: cut %d hills (%d orphaned) and %d stray collider(s) out of the portal corridor")
		:format(zoneKey, cutInMap, orphaned, colliders))
	return cutInMap
end

-- Alias kept for `MapGateFlanks`, which dresses the arch's wall from the same stock; the lookup
-- itself is exported from `MapHorizon` since R1 rejected the verbatim copy that lived here.
MapPass.RockStock = MapHorizon.Stock

return MapPass
