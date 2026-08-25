local PathSplines = require(script.Parent.PathSplines)
-- MapProps/MapRoad -- the approach road, from the arrival plaza into the village square.
--
-- ===== WHAT WAS ACTUALLY WRONG, WHICH IS NOT WHAT 31.10 WAS OPENED FOR =====
-- The row was written against a map at 1.45 and says the funnel "is not PAVED -- a cleared strip of
-- grass reads as a firebreak". Measured at 1.15, after 31.14 shrank the village, that is no longer
-- true and it is worth writing down rather than quietly building the thing anyway: HubPlaza's stone
-- deck runs south to **z = 74 across the entire width**, and the map's own dirt road starts at
-- **z = 72** for x -50..+20. The two surfaces are TWO STUDS APART. There was never a strip of grass
-- to pave; the walk from the spawn has been on pavement the whole way.
--
-- What the capture shows instead is a **hard black line drawn across the entrance**. HubPlaza edges
-- its deck with a deliberately dark kerb -- the outline tier, which is the first rule in
-- `evolution-lab-chunky-look-rules` and is doing exactly its job everywhere else -- and that kerb
-- runs the full 356 studs, straight, right where the plaza meets the village. So the road does not
-- arrive anywhere. It stops at a black band, and a second, differently-coloured surface starts on
-- the other side of it. That reads as a boundary between two games, which is the same complaint the
-- row was opened for and a completely different cause.
--
-- ===== SO THE FIX IS A ROAD THAT CROSSES THE SEAM, NOT A ROAD THAT MEETS IT =====
-- One continuous ribbon of the village's OWN dirt, starting well inside the plaza and running past
-- the kerb into the square. It is the village reaching out rather than the plaza reaching in, and
-- that is the direction her *"sav dizajm ... treba prilagoditi ovoj zoni novoj"* points: the map is
-- the thing everything else is being adapted to, so where the two palettes meet, the map's wins.
--
-- ===== ONE SLAB, THREE FLOORS =====
-- The ribbon crosses a 1.04-stud stone deck, a 0.6-stud ground union and bare lawn at 0.0 inside
-- eighty studs. A thin sheet at one height is buried under the first and floating over the last, so
-- the road is given DEPTH instead: 1.4 studs of it, hanging down past the lowest floor it meets,
-- with its top -- the only face anybody sees -- at one height the whole way. Over the deck that is
-- paint; over the lawn the 1.3 studs of exposed side is a kerb, which is what a road has anyway.
-- See `MapPaint.Segment`.
--
-- Nothing here collides. Same rule as the jungle paths and for the same reason.

local MapPaint = require(script.Parent.MapPaint)

local MapRoad = {}

local FOLDER_NAME = "ApproachRoad"

-- ===== THE LINE =====
-- Measured, not drawn by eye. The plaza end sits on x = 0 because that is where the spawn is and
-- because HubPlaza reserves |x| < 30 as its walking corridor, so a 40-wide road there stands in
-- ground its own neighbour has promised to keep clear. The village end sits on x = -15, the middle
-- of the 70-stud mouth (x -50..+20) where the map's dirt actually starts -- so the ribbon joins the
-- artist's road network instead of crossing it.
--
-- It stops at z = 40 and not at the square itself: the Fountain is a 44 x 44 prop whose north face
-- is z = 30, and paint run under a solid prop is paint nobody sees.
--
-- The plaza end is SQUARE and the village end is round, which is not symmetry for its own sake. A
-- disc on the end of a road as wide as the disc is a lollipop -- the first capture of this road is
-- a warm blob parked on the plaza -- whereas at the village end the round cap is what fans the road
-- out into the square instead of stopping it at a straight line, which is the fault this whole file
-- exists to fix.
local FROM = Vector2.new(0, 150)
local TO = Vector2.new(-15, 40)
local W_PLAZA, W_VILLAGE = 44, 58
local QUADS = 10

-- The approach road as one segment, for anything that has to keep off it. Same reason `MapGates`
-- publishes its lanes: the alternative is a second copy of these coordinates somewhere else.
MapRoad.LANE = { x1 = FROM.X, z1 = FROM.Y, x2 = TO.X, z2 = TO.Y, w = math.max(W_PLAZA, W_VILLAGE) }

-- The top face, and every number here is against a floor measured on the live build. HubPlaza draws
-- on four planes -- kerb 0.66, deck 1.04, inlay 1.14, cross band 1.18 -- and its own `GROUND_CLEAR`
-- is 1.40: anything topping out below that it treats as floor rather than as an obstruction. So the
-- road's top has to clear 1.18 and stay under 1.40, which leaves very little room and exactly one
-- sensible answer.
-- ===== 30.26: IT IS TWO HEIGHTS NOW, AND THE OWNER PHOTOGRAPHED WHY =====
-- 1.30 is still right AT THE PLAZA and was never right at the other end. The village half of this
-- road runs over the map's own 0.6-stud ground union, where `MapGates` paints the three village
-- lanes at 0.80 -- so a ribbon held at 1.30 the whole way stands half a stud proud of the roads it
-- joins, and its dark rim at 1.22 is drawn straight OVER their bright surface. That is the hard
-- brown band across the entrance in her capture: not a texture, an outline tier winning a fight it
-- should never have been in.
--
-- So the road DESCENDS -- `MapPaint.Taper`'s `y2`, added for this. 1.30 at the plaza clears
-- HubPlaza's 1.18 cross band under its own 1.40 `GROUND_CLEAR` ceiling; 0.80 at the village is
-- `MapGates.TOP` exactly, so the two surfaces meet flush and neither has an edge over the other.
-- The 1.4 studs of depth are what let it do that without leaving a hole: the slab's underside is
-- below every floor it crosses at both ends.
-- ===== AND ITS OWN PLANE IN THE VILLAGE LADDER (30.26) =====
-- `MapGates` tops its three lanes at 0.80 and this used to top out there too, which is flush and
-- ALSO coplanar -- the same z-fight as the jungle junctions, in the one place every player walks
-- through. The village ladder, lowest first, is: egg circle rim 0.64, egg circle 0.72, approach
-- road 0.76, gate lanes 0.80. Four surfaces, 0.16 of a stud apart end to end, each one drawn over
-- the one it should be read as lying on.
local TOP = 1.30
local TOP_VILLAGE = 0.76
local THICK = 1.4
-- The dark rim, drawn first and wider, with its top BELOW the road's. A shell bigger on all three
-- axes encloses a shape instead of outlining it -- that is HubPlaza's own note about what made the
-- Splicer a black blob -- so this one is wider and LOWER, never taller.
local EDGE_TOP = 1.22
local EDGE_TOP_VILLAGE = 0.68   -- the rim descends with the road it edges, a step under it
-- 4, not 7. A rim is an OUTLINE and 7 studs of it at the mouth of a 58-stud road is a band. The
-- village lanes use 6 and are 46 wide; this one is the widest road in the zone and wants the
-- thinnest proportion, not the thickest.
local EDGE_W = 4
local EDGE_SHADE = 0.42

function MapRoad.Build(zoneKey, cx, map)
	if not map then return 0 end

	local old = map:FindFirstChild(FOLDER_NAME)
	if old then old:Destroy() end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = map

	local dirt = MapPaint.DirtColour(map)
	local edge = MapPaint.Shade(dirt, EDGE_SHADE)
	
	-- We want a curved, scribbled, realistic path instead of a straight taper
	local rng = Random.new(42) -- fixed seed so it doesn't change every boot
	local pts = PathSplines.Route(Vector3.new(FROM.X, 0, FROM.Y), Vector3.new(TO.X, 0, TO.Y), rng, { maxJitter = 18 })
	
	local made = 0
	if #pts >= 2 then
		for i = 1, #pts - 1 do
			local p1 = pts[i]
			local p2 = pts[i+1]
			
			local t1 = (i - 1) / (#pts - 1)
			local t2 = i / (#pts - 1)
			
			local w1 = W_PLAZA + (W_VILLAGE - W_PLAZA) * t1
			local w2 = W_PLAZA + (W_VILLAGE - W_PLAZA) * t2
			local wMid = (w1 + w2) / 2
			
			local y1 = TOP + (TOP_VILLAGE - TOP) * t1
			local y2 = TOP + (TOP_VILLAGE - TOP) * t2
			local yMid = (y1 + y2) / 2
			
			local ey1 = EDGE_TOP + (EDGE_TOP_VILLAGE - EDGE_TOP) * t1
			local ey2 = EDGE_TOP + (EDGE_TOP_VILLAGE - EDGE_TOP) * t2
			local eyMid = (ey1 + ey2) / 2
			
			local cap = "none"
			if i == 1 then cap = "both" else cap = "b" end
			
			local segEdge = { x1 = p1.x, z1 = p1.z, x2 = p2.x, z2 = p2.z, w = wMid + EDGE_W * 2 }
			made += MapPaint.Segment(segEdge, folder, cx, edge, eyMid - THICK / 2, THICK, cap)
			local seg2 = { x1 = p1.x, z1 = p1.z, x2 = p2.x, z2 = p2.z, w = wMid }
			made += MapPaint.Segment(seg2, folder, cx, dirt, yMid - THICK / 2, THICK, cap)
		end
	else
		-- fallback to taper if spline fails
		made = MapPaint.Taper(FROM, TO, W_PLAZA + EDGE_W * 2, W_VILLAGE + EDGE_W * 2,
			folder, cx, edge, EDGE_TOP - THICK / 2, THICK, QUADS, false, true,
			EDGE_TOP_VILLAGE - THICK / 2)
		made += MapPaint.Taper(FROM, TO, W_PLAZA, W_VILLAGE,
			folder, cx, dirt, TOP - THICK / 2, THICK, QUADS, false, true,
			TOP_VILLAGE - THICK / 2)
	end

	for _, p in ipairs(folder:GetChildren()) do
		if p:IsA("BasePart") then p.CanQuery = false end
	end

	print(("[MapRoad] %s: %d parts, %.0f -> %.0f studs wide, z %.0f -> %.0f, top y %.2f -> %.2f")
		:format(zoneKey, made, W_PLAZA, W_VILLAGE, FROM.Y, TO.Y, TOP, TOP_VILLAGE))
	return made
end

return MapRoad