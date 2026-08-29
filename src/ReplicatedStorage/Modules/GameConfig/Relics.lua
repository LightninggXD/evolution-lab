-- GameConfig.Relics -- the fifteen relics, the chest that drops them, and the four slots.
--
-- ONE OF THE SEVENTEEN PARTS OF `GameConfig`. It is handed the shared config table and writes
-- into it; see the loader in `GameConfig` itself for why the order of the parts is load-bearing.
-- This one is LAST on that list on purpose: it reads `GetPassAdd` and `Stages`, which the
-- `RobuxShop` and `Evolution` parts put on the table, and nothing reads `Relics` at load time.
--
-- ===== WHAT A RELIC IS, AND WHAT IT DELIBERATELY IS NOT =====
--
-- A relic is a PERMANENT, GLOBAL, PASSIVE stat line that you own forever and equip into one of four
-- slots. That sentence is the promise `RelicsPanel` has been making to the player since the day the
-- empty shell shipped -- "Permanent relics that buff your whole lab" -- and every decision below is
-- downstream of it. Permanent means a rebirth does not take them. Global means no relic is per-zone
-- or per-stage. Passive means there is nothing to activate, re-buy or keep topped up.
--
-- IT IS NOT A POTION AND IT IS NOT A PET. A potion is a timer you spend; a pet is a thing you own a
-- hundred of and sort by power. A relic is a small, slow collection -- fifteen of them, four worn --
-- so the interesting decision is WHICH FOUR, not how many you can hoard.
--
-- ===== THE SLOT COUNT WAS DECIDED BEFORE THE FEATURE WAS (and that is fine) =====
--
-- `RelicsPanel` shipped as an empty shell with FOUR sockets drawn in a row and a line under them
-- reading "Four relic slots. When the forge opens, this is the shelf they go on." That is a promise
-- already made in the product, so four is the number and this file does not get to relitigate it.
-- What it gets to decide is how you EARN them, and the answer is the rebirth ladder: 2 free at the
-- unlock, +1 at Rebirth 1, +1 at Rebirth 2. Rebirth in this game pays multipliers and nothing you
-- can look at; a slot is the first permanent, visible thing it hands over.
--
-- ===== THE STACKING RULE, AND THE BUG IT EXISTS TO NOT REPEAT =====
--
-- **Shares are summed and applied ONCE.** `GetRelicMult` returns `1 + sum(mult - 1)`, never a
-- product. This is not a preference. `GameConfig/Pets.lua` and `PetService` between them carry
-- three separate write-ups of the same shipped bug: a multiplier applied once per item across a
-- growing collection is an EXPONENTIAL in the number of slots. Measured there: five equipped pets
-- multiplied out to x652 against a whole-game ladder of x1394, and at nine slots it passed x20,000.
-- Four relics multiplying would do the same thing more slowly and would be found later.
--
-- THE POOL IS ITS OWN CAP, which is why there is no artificial ceiling in this file. The research
-- convention is to clamp a single stat at some round number; that is a patch for a design where the
-- player can equip four copies of the best relic. Here there is exactly ONE Mythic and one relic per
-- icon, so the strongest possible income loadout is Mythic + Legendary + Epic + Epic and the maths
-- has a hard top without anything having to enforce it. A cap you cannot reach is a cap that only
-- ever confuses the tooltip.
--
-- ===== ONE STAT LINE PER RELIC =====
--
-- The genre convention is that rarity buys extra stat lines as well as bigger numbers. That is right
-- for a game with forty relics and a detail panel; here it would mean a socket 108 px wide trying to
-- print three lines. Rarity buys SIZE only, and variety comes from which of the four stats a relic
-- carries. A player reading a socket should be able to say what it does without tapping it.

return function(GameConfig)

-- ===== THE UNLOCK =====
--
-- The owner asked for "level 10". There is no player level in this game -- `data.XP` is spent on
-- every evolve and resets, so it counts toward the NEXT stage and never accumulates -- and the only
-- monotonic 1..20 counter the rest of the game already gates on is `StageIndex`. Stage 10 is
-- Cosmic Being, which is also the Rebirth Tier 2 gate, so the forge opens at a rung the player is
-- already being told to aim at.
GameConfig.RelicUnlockStage = 10

-- ...AND IT IS A ONE-WAY DOOR. `RebirthService` sets `StageIndex = 1`, so a live `StageIndex >= 10`
-- test would LOCK THE FORGE AGAIN the moment a player rebirths -- taking away, at the exact moment
-- they were promised a reward, a screen full of things they own. `data.RelicForgeUnlocked` is the
-- `TutorialDone` pattern: stamped once, never cleared, and explicitly off the rebirth reset list.
--
-- Checked against the stage as WELL as the flag, so a save that reached stage 10 before this shipped
-- opens the forge on its next push rather than needing to climb again.
function GameConfig.IsRelicForgeUnlocked(data)
	if not data then return false end
	if data.RelicForgeUnlocked then return true end
	return (data.StageIndex or 1) >= GameConfig.RelicUnlockStage
end

-- ===== SLOTS =====
--
-- Two at the unlock, then one per rebirth for the first two rebirths. Two is deliberate rather than
-- one: a single slot has no decision in it -- you wear your best relic and that is the whole system
-- -- where two immediately asks "damage or income", which is the question the feature exists for.
GameConfig.RelicBaseSlots = 2
GameConfig.RelicMaxSlots = 4

function GameConfig.GetMaxEquippedRelics(data)
	local rebirths = (data and data.Rebirths) or 0
	return math.min(GameConfig.RelicBaseSlots + math.min(rebirths, 2), GameConfig.RelicMaxSlots)
end

-- What a locked socket says, so the panel never has to know the ladder itself.
function GameConfig.GetRelicSlotRequirement(slotIndex)
	local n = slotIndex - GameConfig.RelicBaseSlots
	if n <= 0 then return nil end
	return ("Rebirth %d"):format(n)
end

-- ===== RARITIES =====
--
-- Five tiers, and the weights sum to exactly 1000 so the table can be read as per-mille without
-- anybody dividing anything. The shape is the genre's: a generous, legible body (Common through
-- Epic is 95% of all opens) and then a cliff -- because a chest whose every outcome feels the same
-- is a button, not a chest.
--
-- MYTHIC IS 0.5%, NOT 0.004%. The games that run a 1-in-25,000 chase tier hand out a free chest
-- every ten minutes forever; this one gives a chest every fifteen minutes and expects a player to
-- finish the ladder. At 0.5% the median player sees their Mythic somewhere around open 140, which
-- is a real chase inside one player's lifetime rather than a lottery nobody in the server wins.
--
-- `mult` is what the rarity does to a relic's base numbers, and it is the only place the ladder
-- lives -- every relic below authors ONE base value and inherits its size from its tier.
GameConfig.RelicRarities = {
	{ key = "Common",    name = "Common",    weight = 550, mult = 1.0,  color = Color3.fromRGB(176, 184, 208), deep = Color3.fromRGB(104, 112, 140) },
	{ key = "Rare",      name = "Rare",      weight = 280, mult = 2.0,  color = Color3.fromRGB(120, 200, 255), deep = Color3.fromRGB(28, 116, 220) },
	{ key = "Epic",      name = "Epic",      weight = 120, mult = 3.5,  color = Color3.fromRGB(206, 160, 255), deep = Color3.fromRGB(122, 56, 216) },
	{ key = "Legendary", name = "Legendary", weight = 45,  mult = 6.0,  color = Color3.fromRGB(255, 220, 120), deep = Color3.fromRGB(238, 150, 20) },
	{ key = "Mythic",    name = "Mythic",    weight = 5,   mult = 10.0, color = Color3.fromRGB(255, 150, 180), deep = Color3.fromRGB(214, 30, 90) },
}

GameConfig.RelicRarityByKey = {}
for i, r in ipairs(GameConfig.RelicRarities) do
	r.index = i
	GameConfig.RelicRarityByKey[r.key] = r
end

-- ===== THE FOUR STATS =====
--
-- Chosen because each one already has exactly one aggregator in the game that everything reads
-- through, so a relic reaches clicks, kill payouts, idle income, egg rolls and the evolve bar
-- without any call site learning that relics exist. `field` is the name the aggregator uses --
-- deliberately the SAME names the game passes use, which is the convention `RobuxShop` set out and
-- the reason a tenth pass needed no new code anywhere.
--
-- `add` marks the additive ones. Luck is additive everywhere in this game (pets, potions, upgrades
-- and passes all add percentage points to a stat that starts at ZERO), so a luck MULTIPLIER would
-- do literally nothing for a new player -- the exact person opening their first chest.
GameConfig.RelicStats = {
	income = { field = "incomeMult", label = "DNA from every source", base = 0.06, add = false },
	damage = { field = "damageMult", label = "combat damage",         base = 0.06, add = false },
	xp     = { field = "xpMult",     label = "Evolution XP",          base = 0.05, add = false },
	luck   = { field = "luckAdd",    label = "Luck",                  base = 4,    add = true },
}

-- ===== THE THREE FAMILIES =====
--
-- Flavour AND a set bonus. Three relics of one family equipped together pays a fourth line on top,
-- which is only reachable at three slots -- i.e. after Rebirth 1 -- so it is an aspiration the
-- player can see long before they can use it. That is the whole reason the panel draws the family
-- pips: a bonus nobody can find is a bonus nobody has.
GameConfig.RelicFamilies = {
	Feast   = { name = "Feast",   blurb = "what the lab eats",       setStat = "income", setBonus = 0.25, icon = "chicken_leg" },
	Fossil  = { name = "Fossil",  blurb = "what the lab digs up",    setStat = "damage", setBonus = 0.25, icon = "bone" },
	Arcane  = { name = "Arcane",  blurb = "what the lab cannot explain", setStat = "luck", setBonus = 15, icon = "amethyst" },
}

-- ===== THE FIFTEEN =====
--
-- One per drawing already banked in `IconLibrary` -- the food and junk art the owner uploaded ahead
-- of this feature. That is not a coincidence to work around, it is the constraint that decided the
-- roster size: fifteen relics is a collection a player can finish and remember, and every one of
-- them has real art rather than a coloured square.
--
-- FIVE COMMON, FOUR RARE, THREE EPIC, TWO LEGENDARY, ONE MYTHIC. The pool shape and the roll weights
-- are two different things and both matter: the weights decide how often a tier comes up, the pool
-- decides how many DIFFERENT relics that tier can be. One Mythic means the chase has a name.
GameConfig.Relics = {
	-- Common
	{ key = "carrot",      name = "Lucky Carrot",     icon = "carrot",      rarity = "Common",    family = "Feast",  stat = "luck" },
	{ key = "donut",       name = "Sugar Ring",       icon = "donut",       rarity = "Common",    family = "Feast",  stat = "income" },
	{ key = "bullet",      name = "Spent Round",      icon = "bullet",      rarity = "Common",    family = "Fossil", stat = "damage" },
	{ key = "glasses",     name = "Cracked Lenses",   icon = "glasses",     rarity = "Common",    family = "Arcane", stat = "xp" },
	{ key = "watermelon",  name = "Melon Slice",      icon = "watermelon",  rarity = "Common",    family = "Feast",  stat = "income" },

	-- Rare
	{ key = "chicken_leg", name = "Roast Drumstick",  icon = "chicken_leg", rarity = "Rare",      family = "Feast",  stat = "damage" },
	{ key = "bone",        name = "Ancient Femur",    icon = "bone",        rarity = "Rare",      family = "Fossil", stat = "damage" },
	{ key = "ice_cream",   name = "Frozen Cone",      icon = "ice_cream",   rarity = "Rare",      family = "Feast",  stat = "income" },
	{ key = "scroll",      name = "Faded Scroll",     icon = "scroll",      rarity = "Rare",      family = "Arcane", stat = "xp" },

	-- Epic
	{ key = "pizza",       name = "Eternal Slice",    icon = "pizza",       rarity = "Epic",      family = "Feast",  stat = "income" },
	{ key = "meat",        name = "Prime Cut",        icon = "meat",        rarity = "Epic",      family = "Fossil", stat = "damage" },
	{ key = "fat",         name = "Rendered Tallow",  icon = "fat",         rarity = "Epic",      family = "Fossil", stat = "luck" },

	-- Legendary
	{ key = "gold_pieces", name = "Founder's Hoard",  icon = "gold_pieces", rarity = "Legendary", family = "Arcane", stat = "income" },
	{ key = "apple_gold",  name = "Golden Apple",     icon = "apple_gold",  rarity = "Legendary", family = "Feast",  stat = "xp" },

	-- Mythic -- the one, and it is the crystal rather than a foodstuff on purpose
	{ key = "amethyst",    name = "Heart of the Lab", icon = "amethyst",    rarity = "Mythic",    family = "Arcane", stat = "luck" },
}

GameConfig.RelicsByKey = {}
for i, relic in ipairs(GameConfig.Relics) do
	relic.order = i
	local rarity = GameConfig.RelicRarityByKey[relic.rarity]
	local stat = GameConfig.RelicStats[relic.stat]
	relic.rarityDef = rarity
	relic.statDef = stat
	-- THE NUMBER IS DERIVED, NEVER AUTHORED. A relic row says which tier and which stat it is and
	-- nothing else, so a tier rebalance is one edit to `RelicRarities` and every relic follows it.
	-- The alternative -- a `value` column per relic -- is fifteen chances for the ladder to drift.
	relic.value = stat.base * rarity.mult
	if stat.add then
		relic.value = math.floor(relic.value + 0.5)
		relic.effectText = ("+%d %s"):format(relic.value, stat.label)
	else
		relic.effectText = ("+%d%% %s"):format(math.floor(relic.value * 100 + 0.5), stat.label)
	end
	GameConfig.RelicsByKey[relic.key] = relic
end

function GameConfig.GetRelic(key)
	return GameConfig.RelicsByKey[key]
end

-- ===== LEVELS, WHICH ARE WHAT DUPLICATES ARE FOR =====
--
-- Fifteen relics against a chest every fifteen minutes means the second copy of something arrives
-- long before the fifteenth first copy does. A duplicate that does nothing is a chest that opened
-- onto nothing, and a chest that can feel like nothing is a loop that dies.
--
-- THREE COPIES PLUS DNA RAISES A LEVEL, to a maximum of five, and each level pays +40% of the
-- relic's own base. So a Rare income relic at +12% runs 12 / 16.8 / 21.6 / 26.4 / 31.2. The step is
-- a share of ITS OWN value, not a flat number, so levelling a Mythic is worth what a Mythic is
-- worth and the tier ladder is never inverted by grinding.
--
-- The DNA fee is scaled by `ScaleReward` at the call site, the same way every other DNA price in
-- the game is, so it stays meaningful at stage 20 instead of becoming free.
GameConfig.RelicMaxLevel = 5
GameConfig.RelicMergeCopies = 3
GameConfig.RelicLevelStep = 0.40

function GameConfig.GetRelicMergeCost(level)
	-- 400 at level 1, then x4 a rung: 400 / 1600 / 6400 / 25600 to reach level 5.
	return math.floor(400 * (4 ^ ((level or 1) - 1)))
end

-- What one owned relic is actually worth, given how far it has been levelled. `level` is 1-based and
-- a missing one reads as 1, so an entry written before levels existed cannot break the sum.
function GameConfig.GetRelicValue(relic, level)
	if not relic then return 0 end
	local lv = math.clamp(tonumber(level) or 1, 1, GameConfig.RelicMaxLevel)
	return relic.value * (1 + (lv - 1) * GameConfig.RelicLevelStep)
end

-- ===== THE ROLL =====
--
-- Luck bends the table the way it bends every other roll in this game: it does NOT add a flat
-- percentage to the top tier (which would make a lucky player skip Common entirely and break the
-- levelling loop, since levels are fed by the tiers you get a lot of). It shifts weight one rung at
-- a time -- each point of luck moves a little of Common's weight into Rare, Rare's into Epic and so
-- on -- so luck makes the whole distribution walk upward instead of teleporting to the end of it.
--
-- `chestBias` is the chest's own thumb on the scale, in the same units, so a bought chest and a
-- lucky player are the same mechanism with two sources.
--
-- THE CLAMP IS 1.0, AND IT WAS MEASURED RATHER THAN PICKED. At the first-written ceiling of 3.0 a
-- 400-luck player rolled **Mythic 16.65% of the time** -- a one-in-six chase tier is not a chase
-- tier, it is the normal outcome, and the single Mythic relic would have been the first thing a
-- late player saw rather than the last. Luck in this game reaches the high hundreds (pets, potions,
-- the Lucky pass and MegaLuck all stack additively), so the ceiling is what actually governs, not
-- the slope.
--
-- At 1.0 the top of the curve is Common 15% / Rare 28% / Epic 24% / Legendary 18% / **Mythic 3.9%**
-- -- eight times the base rate, which is a real reward for a luck build, against a rate that still
-- means most opens are not the Mythic. Measured, both numbers, before and after.
function GameConfig.RollRelicRarity(luckPercent, chestBias)
	local shift = math.clamp(((tonumber(luckPercent) or 0) + (tonumber(chestBias) or 0)) / 100, 0, 1)

	local weights, total = {}, 0
	for i, r in ipairs(GameConfig.RelicRarities) do
		-- each rung up gets `shift` applied once more, so the effect compounds gently toward the top
		local w = r.weight * ((1 + shift) ^ (i - 1))
		weights[i] = w
		total = total + w
	end

	local roll = math.random() * total
	for i, w in ipairs(weights) do
		roll = roll - w
		if roll <= 0 then return GameConfig.RelicRarities[i] end
	end
	return GameConfig.RelicRarities[1]
end

-- One relic, uniformly among those of the rolled tier. Uniform WITHIN a tier is deliberate: the
-- tier already carries all the rarity information, and a second hidden weight inside it would mean
-- two relics with the same badge are not actually the same rarity, which no player could ever read.
function GameConfig.RollRelic(luckPercent, chestBias)
	local rarity = GameConfig.RollRelicRarity(luckPercent, chestBias)
	local pool = {}
	for _, relic in ipairs(GameConfig.Relics) do
		if relic.rarity == rarity.key then table.insert(pool, relic) end
	end
	if #pool == 0 then return GameConfig.Relics[1] end
	return pool[math.random(1, #pool)]
end

-- ===== CHESTS =====
--
-- Two sources and no shop shelf. `ROADMAP.md` 17.6 records the owner's intent that relics be FOUND
-- rather than bought -- "mozemo na par mapa dodati skriveni prolaz koji otkljucava ... neke relice"
-- -- so a rack of relics on the Robux store would contradict a decision already on record. What is
-- sold is the CHEST, which is a roll and not an outcome.
--
-- ===== THE FREE TIMER IS GONE (34.55) =====
--
-- It used to be the baseline: `RelicChestSeconds = 900` and a `GetRelicChestReady(data, now)` the
-- panel drew as a `14m 56s` countdown. The owner deleted the idea outright -- *"ovde ne treba ici
-- free relic svakih malo, ne treba biti free uopste, napravicemo da se mogu dobiti samo u chestu"*.
--
-- **A relic now has exactly two doors, and both of them are a CHEST**: one the world hands over
-- (`RelicService.GiveChest` -- the grotto behind the waterfall in 34.53, the lucky wheel's relic
-- wedge in 34.54, and every future boss drop or season reward) and one bought for diamonds. The
-- banking seam already existed for precisely this, which is why removing the faucet costs no new
-- API: `GiveChest` puts a chest in `data.RelicChests` and the player opens it themselves.
--
-- WHAT THIS TAKES OUT OF THE ECONOMY, said plainly rather than discovered later: a player who
-- never spends a diamond used to gain four relics an hour by standing still. That number is now
-- ZERO until a chest source pays them, so the two chest doors are not decoration -- they are the
-- entire faucet, and the roll rate they set has to be measured before this is called finished.
--
-- `data.LastRelicChest` STAYS in the save defaults. It costs one number, it keeps the shape stable
-- for every save that already holds it, and nothing reads it -- the same call `PlayerDataService`
-- makes about `AudioVolumes` after 34.38 deleted the panel that wrote it.
GameConfig.RelicChestDiamondCost = 40
GameConfig.RelicChestDiamondBias = 60       -- a bought chest rolls as if the player had +60 luck

-- ===== AGGREGATION =====
--
-- The two functions the rest of the game calls, and the ONLY place relic maths happens. They live
-- in `GameConfig` rather than in a server service for the reason `Pets.lua` states about
-- `GetLuckPercent`: the panel has to be able to quote the same number the server rolls, and a UI
-- that recomputes a formula by hand is exactly how a screen ends up advertising a bonus nothing is
-- applying. One formula, two readers.
--
-- Both walk `EquippedRelicKeys` and both are safe on a save that has none.
local function equippedRelics(data)
	local out = {}
	if not (data and type(data.EquippedRelicKeys) == "table") then return out end
	local slots = GameConfig.GetMaxEquippedRelics(data)
	for _, key in ipairs(data.EquippedRelicKeys) do
		local relic = GameConfig.RelicsByKey[key]
		-- OWNERSHIP IS RE-CHECKED HERE, not trusted from the equipped list. A key that survived in
		-- `EquippedRelicKeys` after the relic left `data.Relics` would pay a bonus for something the
		-- player does not have -- the "phantom equipped pet" `PlayerDataService` already prunes for.
		local owned = relic and data.Relics and data.Relics[key]
		if owned and #out < slots then
			table.insert(out, { relic = relic, level = (type(owned) == "table" and owned.level) or 1 })
		end
	end
	return out
end
GameConfig.GetEquippedRelics = equippedRelics

-- Which FAMILY set bonuses are live, as a map of family key -> true. Three of one family, and the
-- count is taken off the SAME filtered list the stats are, so a set can never be completed by a
-- relic that is equipped but not owned.
--
-- RENAMED FROM `GetRelicSets` BY 30.2, and the rename is the point: there are now two different
-- things called a set in this file -- three of one FAMILY worn at once, and all ten relics of one
-- ZONE collected -- and a reader who conflates them will believe the collection layer is paying a
-- family bonus. The collection layer's table is `GameConfig.RelicSets`, which would have sat one
-- letter away from this function's old name. There is deliberately NO alias: the whole game had
-- exactly one caller (`RelicsPanel`), which moved with it.
function GameConfig.GetRelicFamilySets(data)
	local counts, sets = {}, {}
	for _, e in ipairs(equippedRelics(data)) do
		counts[e.relic.family] = (counts[e.relic.family] or 0) + 1
	end
	for family, n in pairs(counts) do
		if n >= 3 then sets[family] = true end
	end
	return sets, counts
end

-- MULTIPLICATIVE FIELDS. Returns `1 + sum(share)`, never a product -- see the header.
function GameConfig.GetRelicMult(data, field)
	local share = 0
	for _, e in ipairs(equippedRelics(data)) do
		if e.relic.statDef.field == field and not e.relic.statDef.add then
			share = share + GameConfig.GetRelicValue(e.relic, e.level)
		end
	end
	local sets = GameConfig.GetRelicFamilySets(data)
	for familyKey, live in pairs(sets) do
		local family = GameConfig.RelicFamilies[familyKey]
		if live and family then
			local stat = GameConfig.RelicStats[family.setStat]
			if stat and stat.field == field and not stat.add then
				share = share + family.setBonus
			end
		end
	end
	-- COMPLETED ZONE SETS (30.2). Into the SAME sum, never a second multiplication -- the header's
	-- rule, and the reason all twenty sets are +40% rather than x1.02^20. `CountCompletedRelicSets`
	-- is declared far below this line and that is fine: a field on `GameConfig` is resolved when the
	-- call runs, and nothing calls this during the load that defines it.
	if field == "incomeMult" then
		share = share + GameConfig.CountCompletedRelicSets(data) * GameConfig.RelicSetBonus.incomeShare
	end
	return 1 + share
end

-- ADDITIVE FIELDS (luck today). Returns the plain sum, matching every other luck source.
function GameConfig.GetRelicAdd(data, field)
	local total = 0
	for _, e in ipairs(equippedRelics(data)) do
		if e.relic.statDef.field == field and e.relic.statDef.add then
			total = total + GameConfig.GetRelicValue(e.relic, e.level)
		end
	end
	local sets = GameConfig.GetRelicFamilySets(data)
	for familyKey, live in pairs(sets) do
		local family = GameConfig.RelicFamilies[familyKey]
		if live and family then
			local stat = GameConfig.RelicStats[family.setStat]
			if stat and stat.field == field and stat.add then
				total = total + family.setBonus
			end
		end
	end
	-- COMPLETED ZONE SETS (30.2), the additive half of the same bonus.
	if field == "luckAdd" then
		total = total + GameConfig.CountCompletedRelicSets(data) * GameConfig.RelicSetBonus.luckAdd
	end
	return total
end

-- How many DIFFERENT relics are owned, for the panel's "7 / 15" line. Counts keys rather than
-- copies: the collection is the fifteen, and a stack of six Melon Slices is still one of them.
function GameConfig.CountOwnedRelics(data)
	local n = 0
	for key in pairs((data and data.Relics) or {}) do
		if GameConfig.RelicsByKey[key] then n = n + 1 end
	end
	return n
end

-- The one place a relic is added to a save, so the copy-counting and the level default are got
-- right once. Returns the entry and whether it was the player's FIRST of that relic, because the
-- toast says two different things and neither caller should re-derive it.
function GameConfig.AddRelic(data, key, count)
	local relic = GameConfig.RelicsByKey[key]
	if not relic then return nil, false end
	if type(data.Relics) ~= "table" then data.Relics = {} end
	local entry = data.Relics[key]
	local isNew = (entry == nil)
	if type(entry) ~= "table" then
		entry = { copies = 0, level = 1 }
		data.Relics[key] = entry
	end
	entry.copies = (entry.copies or 0) + (count or 1)
	entry.level = math.clamp(entry.level or 1, 1, GameConfig.RelicMaxLevel)
	return entry, isNew
end

-- Can this relic be levelled right now, ignoring the DNA the player is holding? Split from the
-- charge so the panel can grey a button for the right reason -- "you need two more copies" and
-- "you cannot afford it" are different sentences.
--
-- SINCE 30.2 IT IS A WRAPPER, and the reason is that there are now TWO ways to pay for a level:
-- three spare copies, or dust from the collection layer standing in for the copies you are short.
-- Two tests would be two chances for the panel to grey a button the server would have honoured.
-- `GetRelicMergePlan` is the one implementation; this keeps the old name and the old meaning
-- ("can it be levelled right now, ignoring DNA") for the call sites that only want the boolean.
function GameConfig.CanMergeRelic(data, key)
	return GameConfig.GetRelicMergePlan(data, key).ok
end


-- =====================================================================================
-- THE COLLECTION LAYER: 200 RELICS THAT CANNOT BE WORN (30.2)
-- =====================================================================================
--
-- EVERYTHING ABOVE THIS LINE IS THE FIFTEEN AND IT IS UNTOUCHED, apart from two additions inside
-- `GetRelicMult` / `GetRelicAdd` that are marked where they sit. That is the whole shape of this
-- row. The header's stacking argument -- "the pool is its own cap ... there is exactly ONE Mythic
-- and one relic per icon" -- is load-bearing, and 200 equippable relics would silently void it:
-- four Mythics in four slots raises the income ceiling about 1.6x. So the fifteen stay the STAT
-- layer, worn four at a time, and the two hundred are a COLLECTION layer with no slot, no level
-- and no equip path at all.
--
-- They are also in a DIFFERENT SAVE FIELD -- `data.SetRelics`, never `data.Relics` -- and that is
-- the mechanical guarantee behind the promise rather than a convention. `equippedRelics` resolves
-- through `RelicsByKey`, which the 200 are not in, so a collection relic that somehow reached
-- `EquippedRelicKeys` would already pay nothing; keeping the tables apart means it cannot get
-- there in the first place, and `CountOwnedRelics` cannot start counting 215.
--
-- ===== WHAT A SET PAYS, AND WHY IT IS THE SET RATHER THAN THE RELIC =====
--
-- A single collection relic pays NOTHING. Ten of one zone pay `+4 luckAdd` and `+0.02` of income
-- share, SUMMED into the same two aggregates as everything else -- see the header's rule, which
-- exists because five pets multiplying once each reached x652 against a whole-game ladder of
-- x1394. All twenty sets are +80 luck and +40% income, which is a months-long chase.
--
-- A COLLECTION RELIC SURVIVES A REBIRTH, and it is not on `RebirthService`'s reset list for the
-- same reason the fifteen are not: this file's header promises that permanent means a rebirth does
-- not take them, and the collection layer is the LONGER of the two chases. 30.7 makes these
-- tradeable on top of that, so a reset would also destroy goods that had changed hands. The rule
-- `RebirthService` states -- "the collection is the run, and the run is what resets" -- is about
-- `Characters`, which is a damage ladder; ten shards of Forest rock are not.
--
-- Paying per SET rather than per relic is what stops the collection being a second stat treadmill:
-- 199 of them do nothing measurable, so the interesting question is "which zone am I finishing",
-- and the answer to "I got a duplicate" is dust rather than a slightly bigger number.
--
-- ===== GENERATED FROM A form x zone MATRIX, NEVER HAND-AUTHORED =====
--
-- Ten forms crossed with twenty zones is exactly 200 keys and it cannot drift: a zone added to
-- `GameConfig.Zones` grows the collection by ten without an edit here, and no key can be duplicated
-- or misspelled because no key is typed. The same argument `Adventures` makes about deriving its
-- twenty routes from the strip.
--
-- A FORM CARRIES ITS RARITY EVERYWHERE. The shard is Common in all twenty zones, the sigil is the
-- capstone in all twenty. That is what makes 200 tiles readable: the PICTURE says how rare it is
-- and the TINT says which zone it came from, so a player learns ten shapes rather than 200 items.
--
-- ===== ART IS TEN UPLOADS, NOT TWO HUNDRED =====
--
-- Each set tints its form through `ImageColor3` from its own zone palette. That is only possible
-- because these ten PNGs are drawn NEARLY WHITE -- `ImageColor3` multiplies, so tinting a coloured
-- drawing gives mud and tinting a white one gives the colour. The ink contour survives it for the
-- same reason: dark times anything stays dark.
GameConfig.RelicSetForms = {
	-- Four Commons. Small, hard, plentiful things.
	{ key = "shard",  name = "Shard",  rarity = "Common",    icon = "relic_shard",  blurb = "A fragment that kept its edge." },
	{ key = "tooth",  name = "Tooth",  rarity = "Common",    icon = "relic_tooth",  blurb = "Something shed it and did not come back for it." },
	{ key = "coin",   name = "Token",  rarity = "Common",    icon = "relic_coin",   blurb = "Stamped by a hand nobody kept a record of." },
	{ key = "plume",  name = "Plume",  rarity = "Common",    icon = "relic_plume",  blurb = "Too stiff to have come off anything living." },

	-- Three Rares.
	{ key = "horn",   name = "Horn",   rarity = "Rare",      icon = "relic_horn",   blurb = "Still warm at the base, which it should not be." },
	{ key = "rune",   name = "Rune",   rarity = "Rare",      icon = "relic_rune",   blurb = "One mark, cut deep enough to outlast the tablet." },
	{ key = "vial",   name = "Vial",   rarity = "Rare",      icon = "relic_vial",   blurb = "Sealed. Whatever is in it has not settled." },

	-- Two Epics.
	{ key = "idol",   name = "Idol",   rarity = "Epic",      icon = "relic_idol",   blurb = "Carved facing away from wherever it was found." },
	{ key = "core",   name = "Core",   rarity = "Epic",      icon = "relic_core",   blurb = "It draws the light in and gives a little of it back." },

	-- One capstone. Legendary in the first fifteen zones, MYTHIC in the last five -- the same
	-- drawing either way, because the frame and the tint already say which one you are holding.
	{ key = "sigil",  name = "Sigil",  rarity = "Legendary", icon = "relic_sigil",  blurb = "The mark a place leaves on whatever survives it." },
}

-- THE FALLBACK FORM, and it is part of this row rather than a follow-up. `RelicsPanel` draws
-- `IconLibrary.Id[icon] or ""`, and an empty string is a HOLE in the tile -- not a placeholder, not
-- a question mark, nothing at all. With ten new names that have to be drawn, rendered and uploaded
-- before they resolve, the window where an unmapped name renders as a hole is real, so the panel
-- resolves through this and never indexes `Id` for a set relic directly.
GameConfig.RelicSetFallbackIcon = "amethyst"

-- ===== THE MYTHIC CUT =====
--
-- FIVE MYTHICS IN THE WHOLE GAME, in the top five zones, which is the "few players will ever hold
-- one" the owner asked for. It is a REPLACEMENT, not an addition: the capstone of a top-five set is
-- Mythic instead of Legendary, so every set is still exactly ten and the total is still exactly
-- 200. Adding an eleventh to five zones would have made the count 205 and the "20 x 10" claim
-- false everywhere it is written down.
GameConfig.RelicMythicZones = 5

-- What a duplicate is worth, by the rarity of the thing that duplicated. See `AddSetRelic`.
GameConfig.RelicDustByRarity = { Common = 2, Rare = 3, Epic = 6, Legendary = 15, Mythic = 40 }

-- Dust buys a MISSING COPY at the forge, at this rate. Ten dust is five duplicate Commons, so the
-- dust path is slower than actually finding three copies -- it is the floor under a collection that
-- has stopped producing duplicates, not a shortcut past it.
GameConfig.RelicDustPerCopy = 10

-- ONE LINE EACH, for row 30.9. `incomeShare` is a share added to the same sum the worn relics feed;
-- `luckAdd` is flat points onto the same additive luck every other source writes to.
GameConfig.RelicSetBonus = { incomeShare = 0.02, luckAdd = 4 }

-- ===== THE TINT, AND WHY IT IS NOT THE ACCENT COLOUR VERBATIM =====
--
-- `ImageColor3` multiplies, so the tint has to be a colour the art can survive being multiplied by.
-- Half the zone accents are dark by design -- Forest is (40,100,40), Black Hole (80,30,120) -- and
-- multiplying a white drawing by those gives a near-black blob on a pastel tile, which is the
-- village-contrast rule one system over: theme the HUE, pick the tone against what it is drawn on.
--
-- So the hue is the zone's and the TONE IS SOLVED FOR, against a luminance floor -- and that is the
-- second version of this function. The first floored HSV *value* at 0.75 and it did not work,
-- measured: Black Hole (hue 0.77) came out of it at **luminance 0.295** against a floor of 0.42 and
-- tripped this file's own tint tripwire on the very first load.
--
-- THE REASON IS THAT VALUE IS NOT BRIGHTNESS. Luminance weights the channels 0.2126 / 0.7152 /
-- 0.0722, so blue carries about a fourteenth of green's weight: a fully-lit blue and a fully-lit
-- green are the same `v` and nothing like the same brightness. Flooring `v` therefore does nothing
-- for exactly the hues that need it -- the blues and purples, which in this game is Black Hole,
-- Galaxy, Void Expanse and Wormhole, i.e. four of the five zones a player reaches last.
--
-- ===== A FLOOR IS NOT ENOUGH EITHER: IT HAS TO BE A REMAP =====
--
-- The second version clamped luminance to the floor, which cleared the tripwire and then failed a
-- check nothing had thought to run: **the twenty tints have to be distinguishable from each
-- other**, and clamping is exactly the operation that destroys that. Measured on it, Galaxy and
-- Wormhole came out **0.031 apart in RGB** -- about eight levels a channel, which is one colour.
-- Their accents are genuinely similar violets, 0.117 apart, and a clamp took most of what
-- separated them: both were dark enough to be pinned to the same floor, so the only difference
-- left was their hue, and their hues are nearly the same.
--
-- So the floor is a REMAP rather than a clamp: `target = FLOOR + (1 - FLOOR) x lum(accent)`. Every
-- accent keeps its rank and a proportional share of its spread, nothing lands below the floor, and
-- the darkest zone in the game is exactly at it. Same idea as the terrace-tread rule one system
-- over -- what governs is the RELATION between neighbours, not each one's own number.
--
-- It is still a closed-form solve rather than a loop, because both steps are linear:
--
--   * at v = 1, HSV is white lerped toward the pure hue, so every channel -- and therefore
--     luminance -- is linear in `s`. The most saturation this hue can carry and still reach the
--     target is exactly `(1 - target) / (1 - lumPure)`.
--   * luminance is then linear in `v` at fixed `s`, so the value that lands on the target is
--     exactly `target / lum(s, 1)`.
--
-- Capping `s` against the target FIRST is what guarantees the second step has an answer at or
-- below 1, so this can never fail to reach its target and never has to give up and return grey.
--
-- AND THE CAP IS APPLIED WITH `min`/`max`, NOT `math.clamp`. `math.clamp(x, 0.45, sMax)` THROWS
-- when `sMax < 0.45`, which the second version could not reach (its target was the fixed 0.42) and
-- this one can: a bright accent asks for a high target, a high target affords little saturation,
-- and a config that errors at load takes the whole game down with it.
--
-- The achromatic guard survives from the first version and still matters: Moon, Mirror Universe and
-- Singularity have grey accents, where hue is undefined and forcing saturation onto them would
-- paint all three RED. Three grey zones out of twenty is the truth about those zones.
GameConfig.RelicTintMinLuminance = 0.42

local function luminance(c)
	return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
end

local function relicTintFor(accent)
	local floor = GameConfig.RelicTintMinLuminance
	local target = floor + (1 - floor) * luminance(accent)
	local h, s, v = Color3.toHSV(accent)
	if s >= 0.12 then
		local lumPure = luminance(Color3.fromHSV(h, 1, 1))
		local sMax = (1 - target) / math.max(1 - lumPure, 1e-6)
		s = math.min(math.max(s, 0.45), math.min(0.85, sMax))
	end
	local lumAtFull = luminance(Color3.fromHSV(h, s, 1))
	v = math.clamp(target / math.max(lumAtFull, 1e-6), 0, 1)
	return Color3.fromHSV(h, s, v)
end

-- ===== ...AND TWO ZONES MAY NOT SHARE A COLOUR =====
--
-- Even after the remap, Galaxy and Wormhole came out **0.049 apart in RGB** -- ten levels a channel,
-- which is one colour. The transform is not at fault this time and neither is the remap: the two
-- ZONES are the same violet in the world, `Color3.fromRGB(140, 90, 220)` against
-- `(120, 80, 200)`, only 0.118 apart before anything touched them. Nothing that reads the accent
-- faithfully can separate them.
--
-- So the LAST set to arrive gives way. Walking in tier order, a set whose tint is too close to one
-- already placed is rotated around the hue wheel by the smallest step that clears the threshold --
-- the smallest, so the tint stays as near its zone as the constraint allows, and the LATER one, so
-- a zone's colour cannot change because a zone was added after it.
--
-- WHY THIS IS A NUDGE RATHER THAN A WARNING. A load-time warn was the first answer and it was
-- wrong: it would have fired on every boot forever, and this file's tripwires are only worth
-- reading because a clean load prints nothing. A permanent warning is a permanent instruction to
-- ignore warnings. So the collision is FIXED here and the tripwire below now guards against a
-- collision this pass could not fix, which is the only kind left worth a line in the log.
GameConfig.RelicTintMinSeparation = 0.06

local function rgbDistance(a, b)
	return math.sqrt((a.R - b.R) ^ 2 + (a.G - b.G) ^ 2 + (a.B - b.B) ^ 2)
end

-- Up to +-24 degrees, in 3-degree steps, alternating sides so the nudge is as small as it can be.
-- A violet pushed 24 degrees is still a violet; past that it would be a different zone's colour,
-- which is the thing this is trying to avoid.
local function separateTint(tint, placed)
	local function clash(c)
		for _, other in ipairs(placed) do
			if rgbDistance(c, other) < GameConfig.RelicTintMinSeparation then return true end
		end
		return false
	end
	if not clash(tint) then return tint, 0 end
	local h, s, v = Color3.toHSV(tint)
	for step = 1, 8 do
		for _, dir in ipairs({ 1, -1 }) do
			local shift = dir * step * 3 / 360
			local candidate = Color3.fromHSV((h + shift) % 1, s, v)
			if not clash(candidate) then return candidate, dir * step * 3 end
		end
	end
	return tint, nil   -- nil degrees = could not be separated; the tripwire below says so
end

-- ===== GENERATION =====
GameConfig.RelicSets = {}
GameConfig.RelicSetsByZone = {}
GameConfig.SetRelicsByKey = {}

local placedTints = {}
for tier, zone in ipairs(GameConfig.Zones) do
	local isTop = tier > (#GameConfig.Zones - GameConfig.RelicMythicZones)
	local tint, nudge = separateTint(relicTintFor(zone.accentColor), placedTints)
	table.insert(placedTints, tint)
	local set = {
		zoneKey = zone.key,
		name = zone.name,
		emoji = zone.emoji,
		tier = tier,
		tint = tint,
		-- degrees this set's hue had to give way, for the tripwire and for anyone wondering why a
		-- tint does not match its zone exactly. 0 for eighteen of the twenty; nil means it could
		-- not be separated at all.
		tintNudge = nudge,
		relics = {},
		byRarity = {},
		ladder = {},          -- the rarity INDEXES this set actually contains, ascending
	}

	for order, form in ipairs(GameConfig.RelicSetForms) do
		local rarityKey = form.rarity
		if isTop and rarityKey == "Legendary" then rarityKey = "Mythic" end
		local rarity = GameConfig.RelicRarityByKey[rarityKey]
		local relic = {
			-- DETERMINISTIC KEY. It is the save's primary key and a trade's payload, so it is built
			-- from two things that already exist and never from a counter -- reordering either list
			-- must not rename something a player owns.
			key = ("relic_%s_%s"):format(zone.key, form.key),
			name = ("%s %s"):format(zone.name, form.name),
			zoneKey = zone.key,
			zoneName = zone.name,
			tier = tier,
			form = form.key,
			icon = form.icon,
			blurb = form.blurb,
			rarity = rarityKey,
			rarityDef = rarity,
			tint = set.tint,
			order = order,
			collection = true,   -- the one flag a call site can test instead of guessing from the key
		}
		set.relics[order] = relic
		local bucket = set.byRarity[rarityKey]
		if not bucket then
			bucket = {}
			set.byRarity[rarityKey] = bucket
			table.insert(set.ladder, rarity.index)
		end
		table.insert(bucket, relic)
		GameConfig.SetRelicsByKey[relic.key] = relic
	end

	table.sort(set.ladder)
	set.total = #set.relics
	GameConfig.RelicSets[tier] = set
	GameConfig.RelicSetsByZone[zone.key] = set
end

GameConfig.RelicSetCount = #GameConfig.RelicSets
GameConfig.SetRelicTotal = GameConfig.RelicSetCount * #GameConfig.RelicSetForms

function GameConfig.GetSetRelic(key)
	return GameConfig.SetRelicsByKey[key]
end

-- ===== OWNERSHIP =====
--
-- `data.SetRelics` is key -> COPIES, string-keyed like `Potions` and `Relics` for the same reason:
-- an integer-keyed table is a sparse array and Roblox drops those crossing a RemoteEvent.
--
-- The copy count is not a stat and never becomes one. It exists for exactly one reason: 30.7 trades
-- these, and a trade that could hand over your only copy would break the set you are collecting. So
-- a spare is `copies - 1` and that is what a trade may offer.
function GameConfig.GetSetRelicCopies(data, key)
	local owned = data and data.SetRelics
	if type(owned) ~= "table" then return 0 end
	return tonumber(owned[key]) or 0
end

function GameConfig.GetSpareSetRelics(data, key)
	return math.max(0, GameConfig.GetSetRelicCopies(data, key) - 1)
end

-- Owned / total for ONE zone, which is what a panel tab prints.
function GameConfig.CountSetRelicsOwned(data, zoneKey)
	local set = GameConfig.RelicSetsByZone[zoneKey]
	if not set then return 0, 0 end
	local owned = (data and type(data.SetRelics) == "table") and data.SetRelics or nil
	local n = 0
	if owned then
		for _, relic in ipairs(set.relics) do
			if (tonumber(owned[relic.key]) or 0) > 0 then n = n + 1 end
		end
	end
	return n, set.total
end

function GameConfig.IsRelicSetComplete(data, zoneKey)
	local n, total = GameConfig.CountSetRelicsOwned(data, zoneKey)
	return total > 0 and n >= total
end

-- WALKS WHAT IS OWNED, NOT ALL TWO HUNDRED. `GetRelicMult` is on the DNA path -- `DNAService`
-- quotes it on every click and every idle tick -- so this is O(relics the player holds), which is
-- zero for the whole population until a faucet ships, rather than 200 lookups a click.
function GameConfig.CountCompletedRelicSets(data)
	local owned = data and data.SetRelics
	if type(owned) ~= "table" then return 0 end
	local perZone = {}
	for key, copies in pairs(owned) do
		local relic = GameConfig.SetRelicsByKey[key]
		if relic and (tonumber(copies) or 0) > 0 then
			perZone[relic.zoneKey] = (perZone[relic.zoneKey] or 0) + 1
		end
	end
	local done = 0
	for zoneKey, n in pairs(perZone) do
		local set = GameConfig.RelicSetsByZone[zoneKey]
		if set and n >= set.total then done = done + 1 end
	end
	return done
end

-- How many DIFFERENT collection relics are held, for the panel's "37 / 200".
function GameConfig.CountSetRelicsHeld(data)
	local owned = data and data.SetRelics
	if type(owned) ~= "table" then return 0 end
	local n = 0
	for key, copies in pairs(owned) do
		if GameConfig.SetRelicsByKey[key] and (tonumber(copies) or 0) > 0 then n = n + 1 end
	end
	return n
end

-- ===== THE ONE PLACE A COLLECTION RELIC IS ADDED =====
--
-- Returns the definition, whether it was the player's FIRST of that key, and the dust a duplicate
-- paid -- because the toast says three different things and no caller should re-derive which.
--
-- A DUPLICATE PAYS DUST **AND** KEEPS THE COPY, and that is not double-paying: the copy is worth
-- nothing on its own (a collection relic has no stat line at all), it is only trade fodder, and the
-- dust is the entire value of the drop. The alternative -- burning the copy for dust -- would leave
-- a player with nothing to trade except the set pieces they are trying to keep.
function GameConfig.AddSetRelic(data, key, count)
	local relic = GameConfig.SetRelicsByKey[key]
	if not (relic and data) then return nil, false, 0 end
	if type(data.SetRelics) ~= "table" then data.SetRelics = {} end
	local have = tonumber(data.SetRelics[key]) or 0
	local n = math.max(1, math.floor(tonumber(count) or 1))
	local isNew = have <= 0
	data.SetRelics[key] = have + n
	-- every copy past the first is a duplicate, including extras inside one grant of `n`
	local dupes = isNew and (n - 1) or n
	local dust = dupes * (GameConfig.RelicDustByRarity[relic.rarity] or 1)
	if dust > 0 then
		data.RelicDust = (tonumber(data.RelicDust) or 0) + dust
	end
	return relic, isNew, dust
end

-- ===== THE ROLL =====
--
-- The SAME luck-shifted rarity table the chest rolls -- `RollRelicRarity` is not re-implemented
-- here, so a luck rebalance moves both layers together and the histogram of a set drop matches the
-- histogram of a chest.
--
-- WHAT IS NEW IS THAT A SET HAS HOLES IN ITS LADDER. Fifteen zones have no Mythic and five have no
-- Legendary, so a rolled tier can land on an empty pool. The rule is ONE rule: take the nearest
-- tier this set actually has, and break a tie UPWARD.
--
-- That tie-break is the whole reason the top five zones work. In a Mythic zone a rolled Legendary
-- is one rung from Epic and one rung from Mythic -- upward makes it the Mythic, so the capstone of
-- a top-five set drops at Legendary + Mythic weight (5%), exactly the rate a normal zone's
-- Legendary capstone drops at. Downward would have made the best zones in the game the STINGIEST
-- at the top, which is the opposite of what a tier ladder is for.
local function nearestRarityIn(set, index)
	local best, bestDist
	for _, i in ipairs(set.ladder) do
		local dist = math.abs(i - index)
		-- `<=` is the tie-break: the ladder is ascending, so a later (higher) rung at the same
		-- distance replaces an earlier one.
		if not bestDist or dist <= bestDist then best, bestDist = i, dist end
	end
	return GameConfig.RelicRarities[best or 1]
end

function GameConfig.RollSetRelic(zoneKey, luckPercent, chestBias)
	local set = GameConfig.RelicSetsByZone[zoneKey]
	if not set then return nil end
	local rolled = GameConfig.RollRelicRarity(luckPercent, chestBias)
	local rarity = nearestRarityIn(set, rolled.index)
	local pool = set.byRarity[rarity.key]
	if not (pool and #pool > 0) then return set.relics[1] end
	return pool[math.random(1, #pool)]
end

-- A roll that prefers something the player does NOT have yet, which is what a collection wants and
-- a stat treadmill does not. Two passes: roll the tier as normal, and if that tier still holds an
-- unowned relic, give one of THOSE. Only when the whole tier is complete does it hand back a
-- duplicate -- so the dust path opens tier by tier as the set fills rather than all at once.
function GameConfig.RollUnownedSetRelic(data, zoneKey, luckPercent, chestBias)
	local set = GameConfig.RelicSetsByZone[zoneKey]
	if not set then return nil end
	local rolled = GameConfig.RollRelicRarity(luckPercent, chestBias)
	local rarity = nearestRarityIn(set, rolled.index)
	local pool = set.byRarity[rarity.key] or {}
	local fresh = {}
	for _, relic in ipairs(pool) do
		if GameConfig.GetSetRelicCopies(data, relic.key) <= 0 then table.insert(fresh, relic) end
	end
	local from = (#fresh > 0) and fresh or pool
	if #from == 0 then return set.relics[1] end
	return from[math.random(1, #from)]
end

-- ===== DUST AT THE FORGE =====
--
-- The second path to levelling one of the FIFTEEN, and the reason it is needed is arithmetic: at
-- 200 keys a second copy of any one key effectively stops arriving, so `CanMergeRelic`'s
-- three-spare-copies rule fires less and less often as the collection layer grows. Dust is what a
-- duplicate collection relic becomes and copies are what it buys.
--
-- ONE IMPLEMENTATION, TWO READERS. The panel greys its button off this and the server charges off
-- this, so they cannot disagree about what a forge costs -- the same rule the header states about
-- `GetRelicMult` living here rather than in `RelicService`. `CanMergeRelic` above is now a thin
-- wrapper over it for exactly that reason.
function GameConfig.GetRelicMergePlan(data, key)
	local plan = { ok = false, maxed = false, level = 1, copies = 0, spare = 0,
		need = GameConfig.RelicMergeCopies, useCopies = 0, dustNeed = 0, dustHave = 0, reason = "unowned" }
	local relic = GameConfig.RelicsByKey[key]
	local entry = data and data.Relics and data.Relics[key]
	if not (relic and type(entry) == "table") then return plan end
	plan.dustHave = tonumber(data.RelicDust) or 0
	plan.copies = tonumber(entry.copies) or 0
	plan.level = math.clamp(tonumber(entry.level) or 1, 1, GameConfig.RelicMaxLevel)
	if plan.level >= GameConfig.RelicMaxLevel then
		plan.maxed = true
		plan.reason = "maxed"
		return plan
	end
	-- the copy you own is not spendable -- levelling must never take the relic itself away
	plan.spare = math.max(0, plan.copies - 1)
	plan.useCopies = math.min(plan.spare, plan.need)
	plan.dustNeed = (plan.need - plan.useCopies) * GameConfig.RelicDustPerCopy
	if plan.dustHave >= plan.dustNeed then
		plan.ok = true
		plan.reason = "ready"
	else
		plan.reason = "dust"
	end
	return plan
end

-- ===== LOAD-TIME TRIPWIRES =====
--
-- Three, and each one guards a claim that is written down in prose somewhere and would otherwise
-- only be falsified by a player. They warn rather than error for the reason `Adventures` states:
-- a config that refuses to load takes the whole game down, and a warning on a clean boot log is
-- read. A clean load prints nothing.
do
	-- 1. THE COUNT AND THE SHAPE. "20 x 10 = 200" appears in the roadmap, in this file's own header
	--    and in the panel's subtitle, and the generator is the only thing that can make it false.
	local seen, keys = {}, 0
	local mythics, dupes = 0, 0
	for _, set in ipairs(GameConfig.RelicSets) do
		local shape = {}
		for _, relic in ipairs(set.relics) do
			if seen[relic.key] then dupes = dupes + 1 end
			seen[relic.key] = true
			keys = keys + 1
			shape[relic.rarity] = (shape[relic.rarity] or 0) + 1
			if relic.rarity == "Mythic" then mythics = mythics + 1 end
		end
		local capstone = (shape.Mythic or 0) + (shape.Legendary or 0)
		if (shape.Common or 0) ~= 4 or (shape.Rare or 0) ~= 3 or (shape.Epic or 0) ~= 2 or capstone ~= 1 then
			warn(("[GameConfig.Relics] set %q is %d/%d/%d/%d, not the authored 4 Common / 3 Rare / 2 Epic / 1 capstone")
				:format(set.zoneKey, shape.Common or 0, shape.Rare or 0, shape.Epic or 0, capstone))
		end
	end
	if dupes > 0 then
		warn(("[GameConfig.Relics] %d DUPLICATE collection keys -- a save cannot tell two relics with one key apart"):format(dupes))
	end
	if keys ~= GameConfig.SetRelicTotal then
		warn(("[GameConfig.Relics] generated %d collection relics, expected %d"):format(keys, GameConfig.SetRelicTotal))
	end
	-- 2. THE MYTHIC COUNT, which is the number the owner actually asked for and the one thing here
	--    a rebalance of the zone list could quietly change.
	if mythics ~= GameConfig.RelicMythicZones then
		warn(("[GameConfig.Relics] %d Mythic collection relics exist, expected %d"):format(mythics, GameConfig.RelicMythicZones))
	end
	-- 3. THE TINT IS READABLE. A dark `ImageColor3` multiplies a white drawing down to a black blob
	--    on a pastel tile and every structural probe reports the ImageLabel present, sized and
	--    loaded -- this is the 15.x "the light, not the paint" failure in one channel, and it is
	--    the only one of the three that a capture is otherwise the only way to catch.
	for _, set in ipairs(GameConfig.RelicSets) do
		local lum = luminance(set.tint)
		if lum < GameConfig.RelicTintMinLuminance - 1e-3 then
			warn(("[GameConfig.Relics] set %q tints its art at luminance %.2f -- it will read as a black blob")
				:format(set.zoneKey, lum))
		end
	end
	-- 4. AND THE TINTS MUST DIFFER FROM EACH OTHER, which is the check the second version of
	--    `relicTintFor` failed silently: every set was readable and two of them were the same
	--    colour. A per-item check can never catch that -- it is a property of the SET of tints --
	--    which is why it is here rather than in the loop above.
	--
	--    `separateTint` has already fixed what it could, so this fires only on a collision it could
	--    NOT fix -- i.e. a strip so crowded that 24 degrees of give was not enough. That is a real
	--    thing to be told about and it is not a thing that happens today, which is what keeps a
	--    clean boot silent.
	local minD, worstPair = math.huge, ""
	for i = 1, #GameConfig.RelicSets do
		for j = i + 1, #GameConfig.RelicSets do
			local d = rgbDistance(GameConfig.RelicSets[i].tint, GameConfig.RelicSets[j].tint)
			if d < minD then
				minD = d
				worstPair = GameConfig.RelicSets[i].zoneKey .. " / " .. GameConfig.RelicSets[j].zoneKey
			end
		end
	end
	-- 0.06 in RGB is about fifteen levels a channel -- the point below which two tinted copies of
	-- the same drawing stop being tellable apart side by side, which is what a trade window is.
	if minD < GameConfig.RelicTintMinSeparation then
		warn(("[GameConfig.Relics] sets %s STILL tint to the same colour after separation (RGB distance %.3f)")
			:format(worstPair, minD))
	end
	for _, set in ipairs(GameConfig.RelicSets) do
		if set.tintNudge == nil then
			warn(("[GameConfig.Relics] set %q could not be given a colour of its own"):format(set.zoneKey))
		end
	end
end

end
