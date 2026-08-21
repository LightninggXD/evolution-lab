-- MapProps/MapAnchors -- the map declares its own furniture, and every service asks it where.
--
-- Row 30.17 found eight services printing "every authored spot was occupied" on the mapped zone and
-- named the fix: *a mapped zone must DECLARE its free ground rather than leaving eight services to
-- hunt for it*. 30.19 closed the symptom -- the arrival end stopped being under a mountain, so the
-- searches started succeeding again -- and left the cause standing. This is the cause.
--
-- The map is not scenery with a gap in it. It is a VILLAGE, and it already owns every piece of
-- furniture the game generates somewhere else: eight leaderboard boards, a three-step podium with
-- name and rank labels on it, a daily-spin wheel with a countdown, shop / upgrades / potion pads
-- with signs over them, an egg row, an index board. Six of the owner's screenshots on 2026-08-22 are
-- photographs of those props standing unused while our generated copies stand somewhere else in
-- world coordinates.
--
-- ===== THREE RULES THAT KEEP THIS HONEST =====
--
-- 1. READ THE CLONE, NEVER THE SOURCE. The clone is scaled 1.45, seated on its own floor and cut by
--    the bands; the source in ServerStorage is none of those. An anchor taken off the source is
--    wrong by a factor of 1.45 and by whatever the seat moved.
--
-- 2. A MISSING ANCHOR IS nil, AND EVERY CALLER FALLS BACK TO ITS AUTHORED COORDINATE. That is what
--    keeps the other twenty zones building exactly as they do today, and what keeps
--    ForestMapService's promise that deleting it gives the zone back.
--
-- 3. AN ANCHOR IS FURNITURE, NOT SCENERY, SO THE BAND CUTS SKIP IT. Every anchor measured today
--    sits in the VILLAGE band -- but the egg row lands at zone z 91..116, which is INSIDE the
--    entrance funnel (z 30..312, half-width ~80), and cutEntrance deletes by shape as well as by
--    name: a prop whose parts are all called Top / Bottom / Leaves / Branch is foliage to that test
--    whatever it actually is. Collect returns a protected set for exactly this, which is why it must
--    run BEFORE the cuts.
--
-- ===== WHY A NAME IS NOT ENOUGH FOR TWO OF THEM =====
-- Shop is FOUR different objects in this map and Upgrades is TWO: the pad you stand on, the building
-- behind it, and for Shop a pair of market stalls. THICKNESS is what tells them apart -- a pad is
-- one stud thick and a building is not. tools/mapdemo_build.lua separates the same asset by
-- descendant count, which works for house-vs-stall but not for pad-vs-either.

local MapAnchors = {}

-- The eight boards along the eastern side of the square, in the order they stand. THE NAME IS THE
-- STAT, and that is the spec: LeaderboardService ships three boards and the map asked for eight.
MapAnchors.BOARDS = {
	"SecretsHatched", "TotalGems", "TimePlayed", "TotalClicks",
	"Rebirths", "RobuxSpent", "EggsOpened", "Suffixes",
}

-- The egg row on the northern edge -- what the entrance road arrives past.
MapAnchors.EGGS = { "Basic", "Crazy", "Mythic", "King" }

-- Roles that are exactly one child and can be found by name alone.
local SINGLE = { wheel = "DailySpin", index = "Index", potions = "Potions", fountain = "Fountain" }

-- ...and the two that are not. Resolved into <role> (the pad) and <role>House (the building).
local PAIRED = { shop = "Shop", upgrades = "Upgrades" }

-- A pad is 1 stud thick before the 1.45, so 1.45 after. Nothing else in the map is under 4.
local PAD_MAX_Y = 4

-- zoneKey -> role table. Written by Collect, read by Get.
MapAnchors.Registry = {}

-- A prop's world CFrame, its size and the height of the surface a player would stand on. Models are
-- measured by bounding box: none of the map's props has a PrimaryPart.
local function pack(inst, cf, size)
	return { inst = inst, cf = cf, size = size, pos = cf.Position,
		top = cf.Position.Y + size.Y / 2 }
end

-- Written as two returns rather than a forward-declared `local cf, size` because that shape is the
-- exact false positive `tools/luanames.py` documents nine of in its baseline, and one more of them
-- is one more line a future reader has to decide is harmless.
local function measure(inst)
	if inst:IsA("Model") then return pack(inst, inst:GetBoundingBox()) end
	if inst:IsA("BasePart") then return pack(inst, inst.CFrame, inst.Size) end
	return nil
end
MapAnchors.Measure = measure

local function tally(t)
	local n = 0
	for _ in pairs(t) do n += 1 end
	return n
end

-- Walks the PLACED map once. Returns `protected`, a set of instances the band cuts must not touch,
-- and stores the registry under zoneKey. Call it after the map is parented and before any cut.
function MapAnchors.Collect(zoneKey, map)
	local byName = {}
	for _, c in ipairs(map:GetChildren()) do
		local list = byName[c.Name]
		if not list then list = {} byName[c.Name] = list end
		list[#list + 1] = c
	end

	local reg, protected = {}, {}
	local function take(name)
		local list = byName[name]
		local inst = list and list[1]
		if not inst then return nil end
		local m = measure(inst)
		if m then protected[inst] = true end
		return m
	end

	reg.board = {}
	for _, name in ipairs(MapAnchors.BOARDS) do
		reg.board[name] = take(name)
	end

	reg.podium = {}
	for rank = 1, 3 do
		reg.podium[rank] = take(tostring(rank))
	end

	reg.egg = {}
	for _, name in ipairs(MapAnchors.EGGS) do
		reg.egg[name] = take(name)
	end

	for role, name in pairs(SINGLE) do
		reg[role] = take(name)
	end

	for role, name in pairs(PAIRED) do
		local pad, house
		for _, c in ipairs(byName[name] or {}) do
			local m = measure(c)
			if m then
				if m.size.Y <= PAD_MAX_Y then
					if not pad then pad = m end
				elseif not house or m.size.Y > house.size.Y then
					house = m
				end
			end
		end
		if pad then reg[role] = pad protected[pad.inst] = true end
		if house then reg[role .. "House"] = house protected[house.inst] = true end
	end

	-- The two market stalls: the Shop children that are neither the pad nor the house. They are the
	-- size every counter and cabinet in this zone is measured against.
	reg.stall = {}
	for _, c in ipairs(byName.Shop or {}) do
		local m = measure(c)
		if m and m.size.Y > PAD_MAX_Y and (not reg.shopHouse or c ~= reg.shopHouse.inst) then
			reg.stall[#reg.stall + 1] = m
			protected[c] = true
		end
	end

	MapAnchors.Registry[zoneKey] = reg
	return protected
end

-- The one accessor. `slot` keys the multi-valued roles (board by stat name, podium by rank 1..3, egg
-- by tier, stall by index); omit it to get the whole table. nil for any zone with no map, which is
-- every zone but the mapped one and is the caller's cue to build as it always did.
function MapAnchors.Get(zoneKey, role, slot)
	local reg = MapAnchors.Registry[zoneKey]
	if not reg then return nil end
	local r = reg[role]
	if r == nil or slot == nil then return r end
	return r[slot]
end

-- True when this zone is a mapped zone at all -- the one test a service needs before deciding
-- whether to build its own furniture.
function MapAnchors.IsMapped(zoneKey)
	return MapAnchors.Registry[zoneKey] ~= nil
end

-- One line for the boot log. COUNTS, not a boolean: a count is the only thing that tells a silent
-- rename in the source apart from a working census, and a rename is what this file is exposed to.
function MapAnchors.Describe(zoneKey)
	local reg = MapAnchors.Registry[zoneKey]
	if not reg then return zoneKey .. ": not mapped" end
	return ("%s: %d/%d boards, %d/3 podium, %d/%d eggs, %d stalls, shop=%s upgrades=%s wheel=%s potions=%s index=%s")
		:format(zoneKey, tally(reg.board), #MapAnchors.BOARDS, tally(reg.podium),
			tally(reg.egg), #MapAnchors.EGGS, #reg.stall,
			reg.shop and "y" or "MISSING", reg.upgrades and "y" or "MISSING",
			reg.wheel and "y" or "MISSING", reg.potions and "y" or "MISSING",
			reg.index and "y" or "MISSING")
end

return MapAnchors
