-- MapProps/MapSquare -- the village square's furniture stands in a ring around the eggs.
--
-- The owner's drawing of the zone puts a circle at the middle of the cross with the eggs in it and
-- the shop, upgrades and potion buildings in the corners around it -- *"da jaja ne lebde vec da su
-- u centru i okolo ti sopovi"*. 30.24 moved the eggs; this is the "okolo".
--
-- ===== WHAT WAS WRONG WITH LEAVING THEM WHERE THE ARTIST PUT THEM =====
-- Nothing, while the square's centre was a fountain. The map's own arrangement is a market row
-- along the north edge: Shop at (57, 69), Upgrades at (-87, 93), Potions off on its own at
-- (-66, -63). Two of the three doors are in one corner and the third is behind you, which reads as
-- scattered the moment the middle of the square becomes the thing you walk to. A player standing at
-- the eggs should be able to see every door in the village by turning on the spot.
--
-- ===== THE ROTATION IS RELATIVE, AND THAT IS THE WHOLE TRICK =====
-- These are hand-authored props and nothing records which way their fronts face. A yaw computed
-- from scratch is a guess, and `roblox-model-facing-and-scaling` is the standing note about what
-- guessing costs -- a quarter turn faces -X, not +X. So no absolute facing is ever computed here.
-- Each prop is turned by **the change in its own bearing about the square's centre**: if it faced
-- the middle before it faces the middle after, and if it did not, it is no worse than it was. That
-- is true whatever the artist's convention was, without this file knowing it.
--
-- ===== IT MOVES INSTANCES, AND THE PROMPTS FOLLOW BECAUSE OF WHAT `MapAnchors` HOLDS =====
-- `MapAnchors.Registry` stores the INSTANCE, and `MapCounters` finds its prompt target by walking
-- to that same instance -- so a prop moved after the census keeps every door it was given. This is
-- exactly the property `MapEggs` relies on for the egg columns, and the reason both files move
-- contents rather than rebuilding anything. **The cached `pos` / `top` on an anchor DO go stale
-- here**, which is why this runs after every consumer of them.

local MapAnchors = require(script.Parent.MapAnchors)

local MapSquare = {}

-- ===== THE RING =====
-- Bearings in degrees, measured the way `math.atan2(z, x)` reads them. The two the square must keep
-- clear are the ROAD MOUTHS: the approach road arrives from the north (+90) and `MapGates`' south
-- lane leaves at -90. The east and west arms of the cross branch off the south lane at z = -100 and
-- never touch the circle, so there are two mouths here, not four.
--
-- 0 / 135 / 225 puts every prop 45 degrees off the nearest road -- 78 studs of arc at this radius,
-- against a 56-stud lane -- so nothing stands in a road and nothing hides one.
--
-- ===== A SLOT IS A GROUP, NOT A PROP, AND `MapAnchors` IS WHY =====
-- `Shop` is four objects in this map and `Upgrades` is two: the pad you stand on and the building
-- behind it, published as `shop` / `shopHouse` (that file's own header says so). Moving the pad
-- alone would leave its shopfront on the far side of the village with a prompt floating in an empty
-- ring -- the pad carries the door and the house is what tells you the door is there. So a slot
-- names every anchor that has to travel together, and the group moves as ONE RIGID BODY about the
-- FIRST of them, which keeps the counter standing in front of its own shop.
local SLOTS = {
	{ roles = { "shop", "shopHouse" }, bearing = 0 },
	{ roles = { "upgrades", "upgradesHouse" }, bearing = 135 },
	{ roles = { "potions" }, bearing = 225 },
}

-- Where the prop's CENTRE lands, derived rather than typed: the circle's own radius, plus the
-- prop's half-width so it stands beside the paint rather than on it, plus a verge. `MapEggs` paints
-- the circle at 132 diameter, and that number lives there -- this reads the anchor's size and takes
-- the radius as an argument so the two cannot drift apart.
local CIRCLE_R = 66
local VERGE = 10

local function measure(inst)
	if inst:IsA("Model") then
		local cf, size = inst:GetBoundingBox()
		return cf.Position, size
	elseif inst:IsA("BasePart") then
		return inst.Position, inst.Size
	end
	return nil, nil
end

function MapSquare.Arrange(zoneKey)
	if not MapAnchors.IsMapped(zoneKey) then return 0 end

	-- The square's centre is the fountain's old spot, which is where the eggs now stand. `MapEggs`
	-- destroys the fountain instance but the registry entry survives with its measured position --
	-- and that is deliberately what both files key off, so "the middle of the square" is one
	-- coordinate the map itself chose rather than a number either file typed.
	local centre = MapAnchors.Get(zoneKey, "fountain")
	if not centre then
		warn("[MapSquare] " .. zoneKey .. ": no fountain anchor -- the square was left as it was")
		return 0
	end
	local cx, cz = centre.pos.X, centre.pos.Z

	local moved, report = 0, {}
	for _, slot in ipairs(SLOTS) do
		-- Every anchor in the group that actually exists. `shopHouse` is absent on a map that ships
		-- no building, and a group of one is still a group.
		local group = {}
		for _, role in ipairs(slot.roles) do
			local anchor = MapAnchors.Get(zoneKey, role)
			if anchor and anchor.inst and anchor.inst.Parent then
				group[#group + 1] = anchor.inst
			end
		end

		-- `local pos, size = lead and measure(lead)` is what this said on its first boot, and it
		-- moved nothing while reporting no error: an `and` expression TRUNCATES a multiple return to
		-- one value, so `size` was always nil and the test below could never pass. Luau compiles it
		-- happily. The guard is a statement now, which is the only shape that keeps both returns.
		local lead = group[1]
		if lead then
			local pos, size = measure(lead)
			if pos and size then
				local halfWidth = math.max(size.X, size.Z) / 2
				local r = CIRCLE_R + halfWidth + VERGE
				local want = math.rad(slot.bearing)
				local wantX = cx + math.cos(want) * r
				local wantZ = cz + math.sin(want) * r

				-- The bearing the group currently sits at, so the turn is the DIFFERENCE. A prop
				-- standing on the centre has no bearing and is left unturned rather than spun by a
				-- meaningless angle.
				local dx, dz = pos.X - cx, pos.Z - cz
				local turn = 0
				if dx * dx + dz * dz > 1 then
					turn = want - math.atan2(dz, dx)
				end

				-- ONE TRANSFORM, APPLIED TO THE WHOLE GROUP. Built about the lead prop's own position
				-- so the house keeps its exact offset from the pad: take everything into the lead's
				-- frame, turn it, and put it down at the target. Doing this per prop with each one's own
				-- centre would rotate the house about itself and leave it beside the pad at the wrong
				-- angle.
				local move = CFrame.new(wantX, pos.Y, wantZ)
					* CFrame.Angles(0, turn, 0)
					* CFrame.new(-pos.X, -pos.Y, -pos.Z)
				for _, inst in ipairs(group) do
					inst:PivotTo(move * inst:GetPivot())
				end

				moved += #group
				report[#report + 1] = ("%s x%d (%.0f,%.0f)->(%.0f,%.0f) turned %.0f deg")
					:format(slot.roles[1], #group, pos.X, pos.Z, wantX, wantZ, math.deg(turn))
			end
		end
	end

	print(("[MapSquare] %s: %d props in %d groups ringed about (%.0f, %.0f) -- %s")
		:format(zoneKey, moved, #SLOTS, cx, cz, table.concat(report, "; ")))
	return moved
end

return MapSquare
