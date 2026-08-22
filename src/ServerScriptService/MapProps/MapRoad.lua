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

-- The top face, and every number here is against a floor measured on the live build. HubPlaza draws
-- on four planes -- kerb 0.66, deck 1.04, inlay 1.14, cross band 1.18 -- and its own `GROUND_CLEAR`
-- is 1.40: anything topping out below that it treats as floor rather than as an obstruction. So the
-- road's top has to clear 1.18 and stay under 1.40, which leaves very little room and exactly one
-- sensible answer.
local TOP = 1.30
local THICK = 1.4
-- The dark rim, drawn first and wider, with its top BELOW the road's. A shell bigger on all three
-- axes encloses a shape instead of outlining it -- that is HubPlaza's own note about what made the
-- Splicer a black blob -- so this one is wider and LOWER, never taller.
local EDGE_TOP = 1.22
local EDGE_W = 7
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

	-- outline first, mass second: `evolution-lab-world-look-pass`
	local made = MapPaint.Taper(FROM, TO, W_PLAZA + EDGE_W * 2, W_VILLAGE + EDGE_W * 2,
		folder, cx, edge, EDGE_TOP - THICK / 2, THICK, QUADS, false, true)
	made += MapPaint.Taper(FROM, TO, W_PLAZA, W_VILLAGE,
		folder, cx, dirt, TOP - THICK / 2, THICK, QUADS, false, true)

	-- The road is street furniture with no prompt on it, but it is the thing that tells a player
	-- arriving for the first time which way the village is -- so it does not stream out.
	for _, p in ipairs(folder:GetChildren()) do
		if p:IsA("BasePart") then p.CanQuery = false end
	end

	print(("[MapRoad] %s: %d parts, %.0f -> %.0f studs wide, z %.0f -> %.0f, top y=%.2f")
		:format(zoneKey, made, W_PLAZA, W_VILLAGE, FROM.Y, TO.Y, TOP))
	return made
end

return MapRoad
