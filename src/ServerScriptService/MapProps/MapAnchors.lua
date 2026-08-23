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

-- How far, in plan, a `ThreeDTextObject` may stand from the `Sign1` post it belongs to. Measured on
-- the placed map: 0.5 and 0.9 studs for the two surviving pairs, against 84 studs to the next
-- nearest post.
local SIGN_PAIR_MAX = 12

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

	-- ===== THE SIGNPOSTS (32.3) =====
	-- Three carved arrows on poles, and they are furniture by the same argument as everything above
	-- it: `MapSigns` aims each one at the thing it names, and a sign a band cut took between the
	-- census and the aim is a nil the aiming pass would report as a rename. They were nobody's until
	-- this row -- which is what "orphans" meant -- so nothing protected them.
	--
	-- PAIRED BY PROXIMITY, because there is no reference either way: a `ThreeDTextObject` carries
	-- its own text in a StringValue and a `Sign1` knows nothing about the label standing on it. They
	-- are separate TOP-LEVEL children of the map, 7.3 studs apart in Y and under one stud apart in
	-- plan, and the nearest other sign is 84 studs away -- so the pairing is not a close call and
	-- SIGN_PAIR_MAX is set well clear of both numbers rather than tuned between them.
	reg.sign = {}
	for _, text in ipairs(byName.ThreeDTextObject or {}) do
		local tm = measure(text)
		if tm then
			local post, gap = nil, SIGN_PAIR_MAX
			for _, candidate in ipairs(byName.Sign1 or {}) do
				local pm = measure(candidate)
				if pm then
					local d = (Vector2.new(pm.pos.X, pm.pos.Z) - Vector2.new(tm.pos.X, tm.pos.Z)).Magnitude
					if d < gap then post, gap = pm, d end
				end
			end
			reg.sign[#reg.sign + 1] = { text = tm, post = post }
			protected[text] = true
			if post then protected[post.inst] = true end
		end
	end

	MapAnchors.Registry[zoneKey] = reg
	return protected
end

-- ===== MOVING AN ANCHOR STALES ITS MEASURED POSITION, SO THERE IS A WAY TO SAY SO (32.4) =====
-- Every entry in the registry carries a `pos` and a `top` taken once, at `Collect`, and ServerMain
-- already carries the warning that follows from it: *"IT MUST RUN AFTER EVERY READER OF MapAnchors'
-- CACHED pos"*. Until 32.4 nothing moved an anchor, so the caution was enough. `MapGates` moves one
-- now -- the shop stall and the spin wheel were standing in the village's own south and east lanes
-- -- and a stale `pos` is exactly the fault 32.3 spent a row on, where a re-laid door ring left a
-- signpost aiming at where the doors used to be.
--
-- Walks the registry rather than taking a role, because the caller has an INSTANCE and not a role:
-- `MapGates` is handed a leftover off a lane cut and has no idea whether it is a stall, a wheel or
-- a signpost. Returns how many entries were refreshed, which is 0 for a prop that is not an anchor
-- and is worth printing.
function MapAnchors.Remeasure(zoneKey, inst)
	local reg = MapAnchors.Registry[zoneKey]
	if not reg then return 0 end
	local n = 0
	local function walk(t)
		for k, v in pairs(t) do
			if type(v) == "table" then
				if v.inst == inst then
					local m = measure(inst)
					if m then
						t[k] = m
						n += 1
					end
				else
					walk(v)
				end
			end
		end
	end
	walk(reg)
	return n
end

-- ===== WHAT TRAVELS WITH AN ANCHOR WHEN SOMETHING MOVES IT (32.4) =====
-- A signpost is TWO top-level children of the map -- a `Sign1` pole and the `ThreeDTextObject`
-- floating 7.3 studs above it -- and neither knows about the other; `Collect` pairs them by
-- proximity above. Move the pole on its own and the label hangs in the air over nothing, which is a
-- fault no probe in this repo would ever ask about and a screenshot would find weeks later.
--
-- IT RETURNS AN EMPTY LIST TODAY AND IS STILL WORTH HAVING. The one signpost standing in a lane is
-- the `Chest` arrow, which `MapSigns` deletes for naming nothing this game has -- so the pairing is
-- reachable by an ordinary change to the map (a sign that DOES name something, standing in a road)
-- rather than by a hypothetical. `MapGates` prints the count it carried, so this cannot become a
-- safety net nobody has ever seen fire (`optional-arg-nothing-passes`).
function MapAnchors.Companions(zoneKey, inst)
	local reg = MapAnchors.Registry[zoneKey]
	local out = {}
	if not reg then return out end
	for _, pair in ipairs(reg.sign or {}) do
		local text = pair.text and pair.text.inst
		local post = pair.post and pair.post.inst
		if text and post then
			if inst == post then out[#out + 1] = text
			elseif inst == text then out[#out + 1] = post end
		end
	end
	return out
end

-- The one accessor. `slot` keys the multi-valued roles (board by stat name, podium by rank 1..3, egg
-- by tier, stall and sign by index); omit it to get the whole table. nil for any zone with no map, which is
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
	return ("%s: %d/%d boards, %d/3 podium, %d/%d eggs, %d stalls, %d signs, shop=%s upgrades=%s wheel=%s potions=%s index=%s")
		:format(zoneKey, tally(reg.board), #MapAnchors.BOARDS, tally(reg.podium),
			tally(reg.egg), #MapAnchors.EGGS, #reg.stall, #reg.sign,
			reg.shop and "y" or "MISSING", reg.upgrades and "y" or "MISSING",
			reg.wheel and "y" or "MISSING", reg.potions and "y" or "MISSING",
			reg.index and "y" or "MISSING")
end

return MapAnchors
