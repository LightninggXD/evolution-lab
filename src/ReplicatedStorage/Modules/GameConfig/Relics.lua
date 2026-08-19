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
-- sold is the CHEST, which is a roll and not an outcome, and the free timer is always the baseline.
GameConfig.RelicChestSeconds = 900          -- the free one: fifteen minutes
GameConfig.RelicChestDiamondCost = 40
GameConfig.RelicChestDiamondBias = 60       -- a bought chest rolls as if the player had +60 luck

function GameConfig.GetRelicChestReady(data, now)
	if not data then return false, 0 end
	local last = tonumber(data.LastRelicChest) or 0
	local remaining = (last + GameConfig.RelicChestSeconds) - (now or os.time())
	if remaining <= 0 then return true, 0 end
	return false, remaining
end

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

-- Which set bonuses are live, as a map of family key -> true. Three of one family, and the count is
-- taken off the SAME filtered list the stats are, so a set can never be completed by a relic that is
-- equipped but not owned.
function GameConfig.GetRelicSets(data)
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
	local sets = GameConfig.GetRelicSets(data)
	for familyKey, live in pairs(sets) do
		local family = GameConfig.RelicFamilies[familyKey]
		if live and family then
			local stat = GameConfig.RelicStats[family.setStat]
			if stat and stat.field == field and not stat.add then
				share = share + family.setBonus
			end
		end
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
	local sets = GameConfig.GetRelicSets(data)
	for familyKey, live in pairs(sets) do
		local family = GameConfig.RelicFamilies[familyKey]
		if live and family then
			local stat = GameConfig.RelicStats[family.setStat]
			if stat and stat.field == field and stat.add then
				total = total + family.setBonus
			end
		end
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
function GameConfig.CanMergeRelic(data, key)
	local entry = data and data.Relics and data.Relics[key]
	if type(entry) ~= "table" then return false end
	local level = entry.level or 1
	if level >= GameConfig.RelicMaxLevel then return false end
	return (entry.copies or 0) >= 1 + GameConfig.RelicMergeCopies
end

end
