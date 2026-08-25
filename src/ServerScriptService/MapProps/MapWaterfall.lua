-- ===== THE WATERFALL SITS ON THE MOUNTAIN WALL, AND THERE IS A GROTTO UNDER IT =====
--
-- The owner, 2026-08-25: *"treba napraviti secret mesto ispod vodopada ali vodopad mora biti sa
-- neke strane zida kod planina da se uklopi"*. Two halves, and this file is both.
--
-- 👤 WHY THIS IS CODE AND NOT A DRAG IN STUDIO. `workspace.Decorations.Waterfall` is authored
-- scenery -- nothing in `src/` built it and nothing rebuilds it -- so moving it by hand *would*
-- stick. The trees would not: `MapForest.Plant` scatters 5,355 of them over the whole platform on
-- every boot, and the tower's new home is open forest floor. Hand-place it and the next rebuild
-- grows a wood straight through the cliff. The move and the cut have to happen together, in that
-- order, every boot -- which is exactly what `MapGates` does for its lanes.
--
-- ORDER: this runs LAST in `ForestMapService.Init`, after `MapForest.Plant` and `MapJungle.Build`.
-- A pass only ever knows the world that existed when it ran ([[evolution-lab-placement-search-ordering]]),
-- and the thing being cut is the wood, so the wood has to be standing first.

local MapWaterfall = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ===== WHERE THE TOWER GOES, AND HOW THE NUMBER WAS ARRIVED AT =====
--
-- Measured, not guessed. The tower is 234 wide, 301 deep and 322 tall, and it used to stand at
-- pivot (-33, 176, -151) -- i.e. in the OPEN, its foot on the village plaza, a grey slab with four
-- flat sides and nothing behind it. That is the complaint.
--
-- The far (-Z) side of the map is a mountain wall whose inner face was measured by casting outward
-- from r 340 at y 30 against the `HorizonHill` / `gora` set:
--
--     x    +133  +200  +260  +300  +340  +380  +420
--   wall z  -422  -422  -344  -348  -363  -369  -389    and from x 380 out the range's own rock
--                                                        already stands at ground level (y 300)
--
-- So the tower is seated at pivot X 282.5 / Z -335.5, giving x 173..407 and z -535..-234:
--
--  * its WEST flank stands in the open with the wall 100-odd studs behind it,
--  * its EAST flank runs into the range's rock at x 380, which is what makes it read as an outcrop
--    of the range rather than a box parked in front of one,
--  * the AABB's back edge is ~100 studs behind the last real part, so "z -535" seats the actual
--    rock at about -435, a dozen studs inside the wall face. Buried, not floating in front of it.
--
-- THE TWO NUMBERS THAT ARE NOT FREE, both measured against the built world:
--  * `NW`-side camp floor at (146, -258) r23 -- the first seating overlapped it and would have
--    buried a camp under the cliff. x moved +40 to clear it.
--  * camp floor at (300, -200) r23 -- z moved -15 so the tower's front edge (-234) clears the
--    disc's north lip (-223) by 11 studs. That camp now stands at the foot of the falls, which is
--    where you want a camp.
local ANCHOR_PIVOT = Vector3.new(282.475830078125, 176.14761352539062, -335.5041198730469)

-- The plan rectangle, zone-local. Used for the prop cut and for the boot line's numbers.
local FOOT_X1, FOOT_X2 = 173, 407
local FOOT_Z1, FOOT_Z2 = -535, -234

-- ===== THE GROTTO =====
--
-- There was no carving to do. The tower's mass starts well above the floor -- a 6x12x6 body box
-- swept over x 240..350 / z -290..-210 at y 8 reports **no tower rock at all**, only scattered
-- trees and hunt rocks -- so the space under the overhang is already walkable open ground, with
-- 119 studs of headroom before the lowest `Plunge` shelf. What it lacked was a reason to be there
-- and anything to make it read as a room.
--
-- So the grotto is five thin slabs (back, two sides, a low roof) around the secret, open on the
-- +Z face, i.e. towards the village and BEHIND the falling water. You walk through the curtain to
-- get in. It is deliberately small: a room you find, not a hall you cross.
local GROTTO_HALF_X = 15
local GROTTO_HALF_Z = 13
local GROTTO_H = 14          -- inside height, floor to roof underside
local GROTTO_T = 2           -- slab thickness
local GROTTO_CLEAR = 22      -- props are cut this far around the grotto centre

local FOLDER_NAME = "WaterfallGrotto"

-- ===== MOVING 1,102 ANCHORED PARTS IS ONE CALL, AND IT MUST BE IDEMPOTENT =====
-- `Init` runs once per server, but a hot reload or a future rebuild hook must not walk the tower
-- 234 studs further east each time. `PivotTo` an ABSOLUTE pivot rather than adding a delta: run it
-- three times and the tower is in the same place three times.
function MapWaterfall.Seat(cx)
	local dec = workspace:FindFirstChild("Decorations")
	local wf = dec and dec:FindFirstChild("Waterfall")
	if not wf or not wf:IsA("Model") then return nil end

	local target = ANCHOR_PIVOT + Vector3.new(cx, 0, 0)
	local pivot = wf:GetPivot()
	wf:PivotTo(CFrame.new(target) * (pivot - pivot.Position))
	return wf
end

-- Does this prop stand inside the tower's rock? Not "is it in the rectangle" -- the rectangle also
-- contains the wood IN FRONT of the cliff, which is meant to be there and looks right. The test is
-- an actual overlap against the tower's own parts.
local function insideTheTower(prop, wf)
	local cf, size
	if prop:IsA("Model") then
		cf, size = prop:GetBoundingBox()
	elseif prop:IsA("BasePart") then
		cf, size = prop.CFrame, prop.Size
	end
	if not cf then return false end
	for _, q in ipairs(workspace:GetPartBoundsInBox(cf, size)) do
		if q:IsDescendantOf(wf) then return true end
	end
	return false
end

function MapWaterfall.Build(zoneKey, cx, map)
	if not map then return 0, 0, 0 end

	local wf = MapWaterfall.Seat(cx)
	if not wf then
		-- Not a warning worth a stack: a place without the scenery model simply has no waterfall,
		-- and everything else in the zone is unaffected.
		print(("[MapWaterfall] %s: no Decorations.Waterfall -- nothing seated"):format(zoneKey))
		return 0, 0, 0
	end

	local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

	-- ===== THE CUT =====
	local x1, x2 = cx + FOOT_X1, cx + FOOT_X2
	local z1, z2 = FOOT_Z1, FOOT_Z2
	local cut = 0
	for _, c in ipairs(map:GetChildren()) do
		if c.Name ~= "MainPart" and c.Name ~= "Terrain" then
			local ok, pos = pcall(function()
				return c:IsA("Model") and c:GetBoundingBox().Position or (c :: BasePart).Position
			end)
			if ok and pos and pos.X >= x1 and pos.X <= x2 and pos.Z >= z1 and pos.Z <= z2 then
				if insideTheTower(c, wf) then
					c:Destroy()
					cut += 1
				end
			end
		end
	end

	-- ===== THE GROTTO, BUILT AROUND THE SECRET RATHER THAN BESIDE IT =====
	--
	-- ONE SOURCE OF TRUTH FOR THE PLACE. The room is built at the coordinates `GameConfig.Secrets`
	-- already names, so the cave and the trigger cannot drift apart -- which is the failure 32.26
	-- was: an offset edited in one file while the thing it described lived in another.
	local folder = map:FindFirstChild(FOLDER_NAME)
	if folder then folder:Destroy() end
	folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = map

	local rock = Color3.fromRGB(120, 132, 140)
	local built = 0
	for _, secret in ipairs(GameConfig.Secrets or {}) do
		if secret.zoneKey == zoneKey and secret.offset then
			local centre = Vector3.new(cx, 0, 0) + secret.offset

			-- Clear the room's own volume first -- a tree standing in the middle of the grotto is
			-- the same defect as a tree in the cliff, one scale down.
			for _, c in ipairs(map:GetChildren()) do
				if c.Name ~= "MainPart" and c.Name ~= "Terrain" and c ~= folder then
					local ok, pos = pcall(function()
						return c:IsA("Model") and c:GetBoundingBox().Position or (c :: BasePart).Position
					end)
					if ok and pos then
						local dx, dz = pos.X - centre.X, pos.Z - centre.Z
						if dx * dx + dz * dz < GROTTO_CLEAR * GROTTO_CLEAR then
							c:Destroy()
							cut += 1
						end
					end
				end
			end

			-- THE ROOM IS BUILT OFF THE GROUND, NOT OFF THE TRIGGER. The secret's own offset carries
			-- a Y because a 12-stud touch part centred on the floor is half buried in it; the walls
			-- have to start at the floor regardless, or the room stands on stilts by exactly that
			-- much. So the slabs take the trigger's X and Z and a Y of zero.
			local base = Vector3.new(centre.X, 0, centre.Z)
			local function slab(name, size, offset)
				local p = Instance.new("Part")
				p.Name = name
				p.Anchored = true
				p.CanCollide = true
				p.CastShadow = true
				p.Material = Enum.Material.Slate
				p.Color = rock
				p.Size = size
				p.Position = base + offset
				p.Parent = folder
				built += 1
			end

			local w = GROTTO_HALF_X * 2 + GROTTO_T * 2
			-- Open on +Z: that face is the doorway, and the falling water hangs in front of it.
			slab("GrottoBack", Vector3.new(w, GROTTO_H + GROTTO_T, GROTTO_T),
				Vector3.new(0, GROTTO_H / 2, -GROTTO_HALF_Z - GROTTO_T / 2))
			slab("GrottoSide", Vector3.new(GROTTO_T, GROTTO_H + GROTTO_T, GROTTO_HALF_Z * 2),
				Vector3.new(-GROTTO_HALF_X - GROTTO_T / 2, GROTTO_H / 2, 0))
			slab("GrottoSide", Vector3.new(GROTTO_T, GROTTO_H + GROTTO_T, GROTTO_HALF_Z * 2),
				Vector3.new(GROTTO_HALF_X + GROTTO_T / 2, GROTTO_H / 2, 0))
			slab("GrottoRoof", Vector3.new(w, GROTTO_T, GROTTO_HALF_Z * 2 + GROTTO_T),
				Vector3.new(0, GROTTO_H + GROTTO_T / 2, 0))
			-- A lip over the doorway, so from outside it reads as a mouth in the rock rather than
			-- a box with a missing wall.
			slab("GrottoLip", Vector3.new(w, 4, GROTTO_T),
				Vector3.new(0, GROTTO_H - 1, GROTTO_HALF_Z + GROTTO_T / 2))
		end
	end

	print(("[MapWaterfall] %s: tower seated at pivot (%.0f, %.0f, %.0f), cut %d props out of the cliff and the grotto, built %d grotto parts")
		:format(zoneKey, ANCHOR_PIVOT.X + cx, ANCHOR_PIVOT.Y, ANCHOR_PIVOT.Z, cut, built))
	return 1, cut, built
end

return MapWaterfall
