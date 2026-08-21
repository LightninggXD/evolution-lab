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
-- ===== COLUMNS, NOT PARTS =====
-- The stall's pieces are FLAT children of `PetShop` -- `EggOddsAnchor` and `PriceCardAnchor` are
-- siblings of the egg, not children of it -- so moving "the egg" alone would leave its own odds
-- board and price card hanging in the air over an empty deck. The pieces are grouped into columns by
-- X first (the generated row sits at x = -32, 0, +32) and a column is moved as one thing.

local MapAnchors = require(script.Parent.MapAnchors)

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

-- Which map spot each egg column takes, left to right. The map has FOUR and a zone has three eggs,
-- so the fourth (`King`, the biggest and the one furthest from the road) is left standing as the
-- artist's own scenery rather than filled with a duplicate.
local SPOT_ORDER = { "Crazy", "Mythic", "Basic" }

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

	-- 2. move each column onto its map spot. The DELTA is taken from the egg, not from the column's
	--    average: the egg is the thing that has to land on the spot, and everything else keeps its
	--    offset from it, which is what preserves a price card sitting in front and a feature pet
	--    floating above.
	local moved = 0
	for i, key in ipairs(order) do
		local spotName = SPOT_ORDER[i]
		local anchor = spotName and MapAnchors.Get(zoneKey, "egg", spotName)
		if anchor then
			local pieces = columns[key]
			local eggPos
			for _, c in ipairs(pieces) do
				if c.Name == "Egg" then eggPos = centreOf(c) break end
			end
			if eggPos then
				local delta = anchor.cf.Position - eggPos
				for _, c in ipairs(pieces) do
					moveBy(c, delta)
				end
				-- The map's own egg prop WAS the podium and the display egg both. Ours replaces it
				-- rather than standing on it, because two eggs on one spot is the "village drawn
				-- twice" the whole map pass exists to remove -- and ours is the one carrying the
				-- tier art, the odds board and the skin the player actually bought.
				anchor.inst:Destroy()
				moved += 1
			end
		end
	end

	print(("[MapEggs] %s: dropped %d stall pieces, moved %d egg columns onto the map's own spots")
		:format(zoneKey, dropped, moved))
	return moved
end

return MapEggs
