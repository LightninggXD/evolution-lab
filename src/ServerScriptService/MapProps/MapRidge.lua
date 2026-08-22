-- MapProps/MapRidge -- the arrival mountains stand on a ring, not in the road.
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
-- ===== THE RING'S RADIUS IS THE RADIUS OF THE MOUNTAIN THAT IS ALREADY RIGHT =====
-- The move is DERIVED and not typed. Taking "push it out by 95" from a measurement made today is
-- how the five hand-typed band coordinates in 31.14 ended up stale the moment the map scale
-- changed -- so instead the furthest arrival mountain defines the ring, and every other one is
-- pushed out along its own side until it stands on that ring. Add a third mountain, or change
-- `ForestMapService.MAPS.Forest.clear`, and the rule still holds with no number to re-measure.
--
-- ===== A MOVED MOUNTAIN LANDS ON TREES =====
-- Five props over 8 studs tall stand where the east one is going. A tree poking out of a
-- mountainside is 30.19's own note about what reads as broken, so the foliage under the new
-- footprint comes down -- by CENTRE and at a FRACTION of the bounding box, because a `Meshes/gora`
-- cone fills nothing like its own box and clearing the whole box would take a quarter of the wood
-- behind the plaza for no reason.

local MapCut = require(script.Parent.MapCut)

local MapRidge = {}

-- What counts as a mountain: the ring meshes are the only props in this map that are both this
-- tall and this wide. Tested against the placed clone, so it follows the map scale for free.
local MIN_HEIGHT = 60
local MIN_SPAN = 100
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

function MapRidge.Reseat(zoneKey, cx, map)
	if not map then return 0 end

	local ring = {}
	for _, c in ipairs(map:GetChildren()) do
		if c.Name ~= "MainPart" and c.Name ~= "Terrain" then
			local pos, size = measure(c)
			if pos and size and size.Y >= MIN_HEIGHT
				and math.max(size.X, size.Z) >= MIN_SPAN and pos.Z > ARRIVAL_Z then
				ring[#ring + 1] = { inst = c, x = pos.X - cx, z = pos.Z, size = size }
			end
		end
	end
	if #ring < 2 then
		-- One mountain is not a ring and there is nothing to be symmetric with. Better to leave the
		-- map as the artist drew it than to invent a radius out of a single sample.
		print(("[MapRidge] %s: %d arrival mountain(s) -- nothing to reseat")
			:format(zoneKey, #ring))
		return 0
	end

	local radius = 0
	for _, m in ipairs(ring) do radius = math.max(radius, math.abs(m.x)) end

	local movedCount, cleared = 0, 0
	for _, m in ipairs(ring) do
		local want = radius * (m.x < 0 and -1 or 1)
		local shift = want - m.x
		if math.abs(shift) >= 10 then
			m.inst:PivotTo(m.inst:GetPivot() + Vector3.new(shift, 0, 0))
			movedCount += 1

			-- and the wood it landed in
			local hx, hz = m.size.X * FILL / 2, m.size.Z * FILL / 2
			for _, c in ipairs(map:GetChildren()) do
				if c ~= m.inst and c.Name ~= "MainPart" and c.Name ~= "Terrain"
					and MapCut.IsFoliage(c) then
					local pos, size = measure(c)
					if pos and size and size.Y >= MapCut.MIN_HEIGHT
						and math.abs(pos.X - cx - want) <= hx
						and math.abs(pos.Z - m.z) <= hz then
						c:Destroy()
						cleared += 1
					end
				end
			end
			print(("[MapRidge] %s: mountain x %.0f -> %.0f (ring r=%.0f), %d trees cleared under it")
				:format(zoneKey, m.x, want, radius, cleared))
		end
	end

	print(("[MapRidge] %s: %d arrival mountains, ring r=%.0f, moved %d, cleared %d")
		:format(zoneKey, #ring, radius, movedCount, cleared))
	return movedCount
end

return MapRidge
