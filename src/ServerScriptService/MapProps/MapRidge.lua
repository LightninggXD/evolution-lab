-- MapProps/MapRidge -- no mountain of the map's own stands on ground the player walks.
--
-- It was called "the arrival mountains stand on a ring, not in the road" until 30.23, and the
-- history below is kept because the measurements in it are still the reason the file exists.
--
-- Her note, 2026-08-22, on a capture taken from the arrival plaza: *"sivi planinski prsten koji
-- gura desnu stranu prilaza"*. The asymmetry is real and it is not a matter of taste -- it is one
-- mountain in the wrong place, and the numbers say so before any judgement does.
--
-- MEASURED ON THE LIVE BUILD. The map's ring is down to two mountains after 30.19 cleared three:
--     west   centre (-227, 219)   192 x 137 x 247   footprint x -323..-131
--     east   centre ( 132, 213)   184 x 131 x 238   footprint x   40..224
-- `HubPlaza`'s deck is 344 x 336 spanning x -172..172, z 74..422. The west mountain clips the deck
-- by 41 studs at its corner, which is a horizon standing behind a plaza. The EAST one is centred
-- at x = 132 -- **inside the deck**, 40 studs off the arrival road's own edge -- which is a
-- mountain standing ON the plaza. That is the whole of the complaint, and it is why the left half
-- of every capture is calm and the right half is a grey cliff.
--
--
-- ===== 30.23: MOVING THEM STOPPED BEING ENOUGH, SO THEY GO =====
-- `Reseat` is gone and this file CUTS now. The reason is that the ground it was arranging them on
-- stopped being scenery: 30.23 filled both north quadrants with wood and ten camps, and a body-box
-- walk from the ring road found `Meshes/gora` across the approach to three of them -- 8 blocked
-- cells of 226, which is 30.19 arriving a second time. There is nowhere on this platform left to
-- push a 192 x 247 mountain TO. Every square of it is either village, plaza, road, camp or wood.
--
-- Two of the three went to `ForestMapService`'s flank bands the moment they ran to z = 430. The
-- third did not, and the reason is worth keeping because it is a pure ordering bug: the east
-- mountain is authored at x = 132 and only ever REACHED x = 227 because Reseat put it there --
-- and Reseat runs AFTER the bands. So the bands measured it at 132, scored 0.00 against the flank
-- band, and left it standing on the plaza, where `HubPlaza` immediately went from 14/14 exhibit
-- figures to 8/14 with 8 pieces skipped. A pass that moves a prop into another pass's test is a
-- pass that has to run on the other side of it -- or, as here, stop moving things.
--
-- THE RULE IS ONE LINE: a mountain whose rock reaches inside the ring road is in the way. What is
-- left of the horizon is `MapJungle`'s own ridge, which is built from this same mountain mesh, sunk
-- and scaled, and now runs the flanks from z = 480 down for exactly this reason.
--
-- `Footprints` is the other half of this file and is what `MapForest` asks -- after the cut -- for
-- every mountain still standing, so the wood is never grown inside rock.

local ServerStorage = game:GetService("ServerStorage")

local MapRidge = {}

-- ===== THE LAST MOUNTAIN IS KEPT AS STOCK, AND THAT IS NOT AN OPTIMISATION =====
-- `MapJungle` builds the zone's horizon by cloning the map's own `Meshes/gora` mountain, sunk and
-- scaled. It looks for one INSIDE THE PLACED MAP -- and the first boot after this file started
-- cutting instead of moving printed `0 ridge hills`, because by the time it looked there were none
-- left. The wood had a horizon of empty sky, and nothing errored.
--
-- So the cut parks a clone of the first mountain it takes, at the map's own scale, and `Stock()`
-- hands it back. One module owns "where the mountain mesh comes from", which is the same rule the
-- rock and tree stocks already follow.
local STOCK_NAME = "RidgeStock"

function MapRidge.Stock()
	return ServerStorage:FindFirstChild(STOCK_NAME)
end

-- What counts as a mountain: the ring meshes are the only props in this map that are this tall,
-- this wide AND this deep. Tested against the placed clone, so it follows the map scale for free.
--
-- MIN_THICK IS THE THIRD TEST AND IT WAS ADDED BECAUSE OF A FALSE POSITIVE, not for symmetry: the
-- map ships a 1 x 144 x 144 `Union` at (-18, 9) -- a flat backdrop panel standing in the village --
-- which passes "60 tall" and "100 across" and is not a mountain by any reading. It was being handed
-- to `MapForest` as a keep-out and would have been handed to the cut below as something to delete.
local MIN_HEIGHT = 60
local MIN_SPAN = 100
local MIN_THICK = 40
-- The arrival side. The ring also runs behind the village to the south, and those are not in
-- anybody's way -- this file only ever touches the mountains you look at while walking in.
local ARRIVAL_Z = 60
-- How much of a mountain's bounding box is actually mountain. A cone in a box fills about half of
-- it; 0.55 takes the trees that would be inside the rock and leaves the ones at its foot, which is
-- what the base of a hill looks like.
local FILL = 0.55

local function measure(c)
	if c:IsA("Model") then
		local cf, s = c:GetBoundingBox()
		return cf.Position, s
	elseif c:IsA("BasePart") then
		return c.Position, c.Size
	end
	return nil, nil
end

-- ===== EVERY MOUNTAIN LEFT STANDING, ZONE-RELATIVE (30.23) =====
-- Reseat used to do this scan inline. It is public now because `MapForest` needs the same answer
-- for a different reason: since 30.23 it plants the whole platform, and a mountain is the one thing
-- out there big enough to grow a wood inside. Two definitions of "what counts as a mountain" is
-- exactly the drift `evolution-lab-zone-geometry-constants` is about, so there is one.
--
-- `hx` / `hz` are the FILL'd half extents -- what is actually rock, as opposed to what the bounding
-- box claims. `minZ` is optional and is what makes this the ARRIVAL ring for `Reseat` and the whole
-- ring for the planter.
function MapRidge.Footprints(cx, map, minZ)
	local ring = {}
	if not map then return ring end
	for _, c in ipairs(map:GetChildren()) do
		if c.Name ~= "MainPart" and c.Name ~= "Terrain" then
			local pos, size = measure(c)
			if pos and size and size.Y >= MIN_HEIGHT
				and math.max(size.X, size.Z) >= MIN_SPAN
				and (not minZ or pos.Z > minZ) then
				ring[#ring + 1] = {
					inst = c, x = pos.X - cx, z = pos.Z, size = size,
					hx = size.X * FILL / 2, hz = size.Z * FILL / 2,
				}
			end
		end
	end
	return ring
end

-- ===== THE CUT =====
-- Outside the ring road or gone. `JungleLayout`'s ring runs at |x| = 450 and its camps reach 530,
-- so 470 is the first line a mountain can stand on without reaching into anything the player walks
-- through -- and no mountain in this map is anywhere near it, which is the honest reading of what
-- this function does today: it deletes all of them. It is written as a rule rather than as a
-- `:Destroy()` loop because the second mapped zone will have its own ring and its own answer.
local KEEP_BEYOND_X = 470

function MapRidge.Clear(zoneKey, cx, map)
	if not map then return 0 end
	local removed, kept = 0, 0
	local names = {}
	for _, m in ipairs(MapRidge.Footprints(cx, map, ARRIVAL_Z)) do
		if math.abs(m.x) - m.hx < KEEP_BEYOND_X then
			names[#names + 1] = ("(%.0f, %.0f) %.0f x %.0f"):format(m.x, m.z, m.size.X, m.size.Z)
			if removed == 0 then
				local old = ServerStorage:FindFirstChild(STOCK_NAME)
				if old then old:Destroy() end
				local keep = m.inst:Clone()
				keep:ScaleTo(1)
				keep.Name = STOCK_NAME
				keep.Parent = ServerStorage
			end
			m.inst:Destroy()
			removed += 1
		else
			kept += 1
		end
	end
	print(("[MapRidge] %s: cut %d arrival mountain(s) reaching inside x %d%s, kept %d, stock=%s")
		:format(zoneKey, removed, KEEP_BEYOND_X,
			#names > 0 and (" -- " .. table.concat(names, ", ")) or "", kept,
			tostring(MapRidge.Stock() ~= nil)))
	return removed
end

return MapRidge
