-- MapProps/MapEggs -- the egg row moves onto the map's own egg spots, and the stall around it goes.
--
-- The owner, with a screenshot: *"a ova jaja su ogromna naspram ovog modela i mene"*. Measured, the
-- eggs are not the problem: ours are 18 studs and the map's own egg props are 17.2, against an
-- 8.4-stud player. THE STALL IS. `EggPlaza` builds a 123 x 47 x 45 market stand -- deck, planks,
-- posts, counter, sign board, crates, barrels, baskets, lanterns and three lit podiums -- and drops
-- it at (0, -6), which is the middle of the village square. That is what makes the eggs read as
-- enormous: they are standing on a structure five houses wide.
--
-- This is row 30.20, which 30.19 left open with the note "the PetShop is still standing in the map's
-- own market row".
--
-- ===== WHAT IT DOES =====
-- Keeps the eggs and everything welded to their meaning -- the shell, its ProximityPrompt, the
-- feature pet, the odds board and the price card -- and moves each of them, as a column, onto one of
-- the four egg spots the map's artist already chose along the northern edge of the square, where the
-- entrance road arrives. Then it deletes the stall and our podiums, because the map's egg prop was
-- the podium all along.
--
-- ===== THE ONE THING THAT MUST NOT CHANGE, AND WHY =====
-- `PetService.WireKiosks` finds the eggs by walking `zoneModel.PetShop` BY NAME and rewrites every
-- prompt it finds there. Rename that model, or reparent the eggs out of it, and egg buying and Auto
-- Hatch both die silently -- no error, no log, just a prompt that opens nothing. So the model keeps
-- its name and its parent, and only its CONTENTS move. Everything here is a `PivotTo` or a
-- `Destroy`; nothing is created and nothing is renamed.
--
-- ===== 30.24: AND THEN THE FOUNTAIN WENT AND THEY TOOK THE MIDDLE =====
-- *"i fontana nam ne treba tu nek jaja stoje umesto fontane znaci"*, and it is the centre circle in
-- the owner's own drawing of the zone: a round plaza where the four roads meet, with the eggs
-- standing in it. So the three columns move a second time -- off the artist's egg row on the
-- northern edge and onto a 32-stud ring around the `fountain` anchor -- the fountain is destroyed,
-- and the four map egg props go with it, because three real eggs and four decorative ones in two
-- different places is a player walking up to the wrong egg.
--
-- THE MOVE IS XZ ONLY. 31.7 took a full 3D delta because it was landing a column on another prop's
-- own spot; the fountain's centre is 12 studs up inside a 52-stud basin, and a 3D delta onto it
-- would hang all three eggs in the air. Their height is already right -- it was measured in 31.7
-- and the square is one flat floor -- so only two of the three axes move.
--
-- ===== COLUMNS, NOT PARTS =====
-- The stall's pieces are FLAT children of `PetShop` -- `EggOddsAnchor` and `PriceCardAnchor` are
-- siblings of the egg, not children of it -- so moving "the egg" alone would leave its own odds
-- board and price card hanging in the air over an empty deck. The pieces are grouped into columns by
-- X first (the generated row sits at x = -32, 0, +32) and a column is moved as one thing.

local MapAnchors = require(script.Parent.MapAnchors)
local MapPaint = require(script.Parent.MapPaint)

local MapEggs = {}

-- Stall furniture: scenery the map replaces. Prefix-matched, and anchored at the START of the name
-- for the same reason `ForestMapService.isDressing` is -- a substring match on "Egg" would take
-- `Egg` itself, which is the one thing here that must survive.
local STALL_PREFIX = {
	"Stall", "Podium", "EggDisc", "EggOrbGem",
}

-- ...and the names that must never be dropped whatever a prefix says. `Egg` is the shell and the
-- model's own meaning; the other three ride with it.
local KEEP = {
	Egg = true, FeaturePet = true, EggOddsAnchor = true, PriceCardAnchor = true,
}

-- ===== THE CENTRE CIRCLE =====
-- The eggs stand on a ring inside it, the first of them facing NORTH -- the way the entrance road
-- arrives -- so a player walking in from the plaza meets an egg head on with the other two behind
-- it to either side, rather than three in profile.
local EGG_RING = 32
local EGG_ANGLES = { math.pi / 2, math.pi * 7 / 6, math.pi * 11 / 6 }
-- The paint under them. The disc is what makes the junction a roundabout instead of a hole where a
-- fountain used to be -- `MapGates` deliberately stops its south lane at z = -30 and `MapRoad` its
-- approach at z = 40, both to avoid painting under the fountain, and this is what now joins them.
--
-- ITS PLANE IS THE VILLAGE'S, NOT THE JUNGLE'S, and that is the one number here that cannot be
-- guessed: `MapPaint.Y` (0.25, top at 0.45) is drawn on bare platform at y = 0 and would be BURIED
-- under the map's own 0.6-stud ground union. `MapGates` paints the village at top 0.80 with 1.4 of
-- depth, i.e. a centre of 0.10, and the rim below it at 0.72. Same two planes, same reason.
local CIRCLE_D = 132
local CIRCLE_Y = 0.10
local CIRCLE_THICK = 1.4
local RIM_EXTRA = 14
local RIM_Y = 0.02
local RIM_SHADE = 0.42

local function isStall(name)
	if KEEP[name] then return false end
	for _, p in ipairs(STALL_PREFIX) do
		if name:sub(1, #p) == p then return true end
	end
	return false
end

local function centreOf(inst)
	if inst:IsA("Model") then
		return inst:GetBoundingBox().Position
	elseif inst:IsA("BasePart") then
		return inst.Position
	end
	return nil
end

local function moveBy(inst, delta)
	if inst:IsA("Model") then
		inst:PivotTo(inst:GetPivot() + delta)
	elseif inst:IsA("BasePart") then
		inst.CFrame = inst.CFrame + delta
	end
end

function MapEggs.Reseat(zoneKey, zoneModel)
	if not MapAnchors.IsMapped(zoneKey) then return 0 end
	local shop = zoneModel and zoneModel:FindFirstChild("PetShop")
	if not shop then return 0 end

	-- 1. group what survives into columns by X. Rounded to the nearest 4 studs because the pieces of
	--    one column are not all exactly on its centre line -- a price card sits forward of its egg.
	local columns, order = {}, {}
	local dropped = 0
	for _, c in ipairs(shop:GetChildren()) do
		if isStall(c.Name) then
			c:Destroy()
			dropped += 1
		else
			local pos = centreOf(c)
			if pos then
				local key = math.floor(pos.X / 4 + 0.5) * 4
				if not columns[key] then
					columns[key] = {}
					order[#order + 1] = key
				end
				table.insert(columns[key], c)
			end
		end
	end
	table.sort(order)

	-- 2. move each column onto its place on the ring. The DELTA is taken from the egg, not from the
	--    column's average: the egg is the thing that has to land on the spot, and everything else
	--    keeps its offset from it, which is what preserves a price card sitting in front and a
	--    feature pet floating above. XZ only -- see the header.
	local fountain = MapAnchors.Get(zoneKey, "fountain")
	local moved = 0
	if fountain then
		for i, key in ipairs(order) do
			local a = EGG_ANGLES[i]
			if a then
				local pieces = columns[key]
				local eggPos = nil
				for _, c in ipairs(pieces) do
					if c.Name == "Egg" then eggPos = centreOf(c) break end
				end
				if eggPos then
					local want = fountain.pos + Vector3.new(math.cos(a) * EGG_RING, 0,
						math.sin(a) * EGG_RING)
					local delta = Vector3.new(want.X - eggPos.X, 0, want.Z - eggPos.Z)
					for _, c in ipairs(pieces) do
						moveBy(c, delta)
					end
					moved += 1
				end
			end
		end
	else
		warn("[MapEggs] " .. zoneKey .. ": no fountain anchor -- the eggs were left where they were")
	end

	-- 3. THE FOUNTAIN GOES, AND SO DO THE MAP'S OWN EGG PROPS.
	-- The fountain is the one landmark in this village nothing is wired to: no prompt, no anchor
	-- consumer but this line, no service that walks it by name (checked across `src/` --
	-- `evolution-lab-repointing-a-door` is the standing note that one grep over the instance NAME is
	-- what separates a move from a silent breakage). The four egg props are the artist's incubators;
	-- 31.7 stood our columns on three of them and left `King` as scenery. With the real eggs in the
	-- middle of the square, all four are a second egg row for a player to walk to by mistake.
	local removed = 0
	if fountain and fountain.inst then
		fountain.inst:Destroy()
		removed += 1
	end
	for _, name in ipairs(MapAnchors.EGGS) do
		local anchor = MapAnchors.Get(zoneKey, "egg", name)
		if anchor and anchor.inst and anchor.inst.Parent then
			anchor.inst:Destroy()
			removed += 1
		end
	end

	-- 4. the circle itself, painted where the fountain stood. Parented into the map so a rebuild
	--    takes it with everything else.
	local circle = 0
	if fountain then
		local map = zoneModel:FindFirstChild("VillageMap")
		if map then
			local old = map:FindFirstChild("EggCircle")
			if old then old:Destroy() end
			local folder = Instance.new("Folder")
			folder.Name = "EggCircle"
			folder.Parent = map
			local dirt = MapPaint.DirtColour(map)
			-- outline first, mass second: `evolution-lab-world-look-pass`
			circle += MapPaint.Disc(fountain.pos.X, fountain.pos.Z, CIRCLE_D + RIM_EXTRA, folder, 0,
				MapPaint.Shade(dirt, RIM_SHADE), RIM_Y, CIRCLE_THICK)
			circle += MapPaint.Disc(fountain.pos.X, fountain.pos.Z, CIRCLE_D, folder, 0, dirt,
				CIRCLE_Y, CIRCLE_THICK)
			for _, part in ipairs(folder:GetChildren()) do
				part.CanQuery = false
			end
		end
	end

	print(("[MapEggs] %s: dropped %d stall pieces, moved %d egg columns onto the %d-stud ring at "
		.. "the square's centre, removed %d props (fountain + the map's egg row), painted %d circle "
		.. "parts")
		:format(zoneKey, dropped, moved, EGG_RING, removed, circle))
	return moved
end

return MapEggs
