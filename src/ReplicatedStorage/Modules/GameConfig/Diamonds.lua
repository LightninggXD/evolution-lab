-- GameConfig.Diamonds -- the premium currency: what it costs, and every way playing earns it.
--
-- ONE OF THE SIXTEEN PARTS OF `GameConfig` (18.9), moved byte for byte. It is handed the
-- shared config table and writes into it; see the loader in `GameConfig` itself for why
-- the order of the parts is load-bearing and why nothing here is re-indented.

return function(GameConfig)

-- ===== DIAMONDS =====
-- Premium currency, separate from DNA and Evolution Shards. Earned from Daily Rewards
-- (Day 6+) and spent on the 3 Diamond Upgrades below -- permanent, powerful, and priced
-- in Diamonds instead of DNA so they stay a long-term grind, not an early-game shortcut.
--
-- ===== THE PRICES WERE WRITTEN BEFORE DIAMONDS HAD A GAMEPLAY SOURCE (11.11) =====
--
-- `baseCost = 5, costMult = 1.6` for "+10% permanent income per level, forever" was authored when
-- the only diamonds in the game came from a daily login, a playtime milestone or a Robux product
-- whose id was still 0. Under those rules five diamonds was several days of showing up. Then 10.x
-- made a KILL the source -- see DiamondDropChance below -- and none of these three numbers moved.
--
-- MEASURED, not estimated (2026-08-12), by driving the real AutoAttack remote at the client's own
-- 0.34 s cadence in Galaxy and reading the diamond balance off the real DataUpdate payload:
--
--   * ROAMING the whole valley with no travel cost -- 254 kills in 180 s, 85 a minute -- pays
--     **13 diamonds, i.e. ~260 an hour**. That total is not a lucky sample: the observed tier mix
--     (177 Swarmer / 59 Critter / 16 Brute / 2 Elite) predicts 12.05 against DiamondDropChance
--     below, so the source and the table agree to within noise.
--   * PARKED in the densest valley cluster and letting the respawns come back -- which is what
--     auto-attack farming actually looks like -- pays **4 diamonds in 176 s, ~82 an hour**, with
--     74% of the swing budget spent with nothing alive inside the 60-stud auto-attack reach.
--
-- The band is therefore 80-260 an hour and the only variable is how much the player roams; the
-- kills themselves are not the constraint, since a player standing in their own zone one-shots
-- valley creatures (the minHits damage cap came off in the damage-ladder pass). Everything below
-- is priced against **~120 an hour**, near the bottom of that band. Against it
-- the OLD first level of Mega Income cost about two and a half minutes of play, for a permanent
-- multiplier on every click, every kill, every idle tick and every offline payout in the game --
-- and the whole first ten levels, +100% income forever, cost 903 diamonds, i.e. seven and a half
-- hours. A permanent upgrade that pays for itself before the player has finished reading its card
-- is not a purchase, it is a formality.
--
-- THE FIX IS PRICES ONLY. Nothing about what these grant changes, no cap is added, and PetSlot
-- keeps its maxLevel of 3. Bases go up ~5x and the multipliers up a step:
--
--     Mega Income  5 -> 25   x1.6 -> x1.75    first 10 levels:   903 ->  8,942
--     Mega Luck    8 -> 40   x1.6 -> x1.75    first 10 levels: 1,447 -> 14,310
--     Pet Slot    15 -> 75   x2.2 -> x2.50    all 3 levels:      120 ->    730
--
-- At the measured 120/hour that is: a first Mega Income level in ~12 minutes instead of ~2, five
-- levels (+50% income) in ~4 hours, and the tenth level alone costing ~32 hours -- so the geometric
-- curve, not a `maxLevel`, is still what caps these. That is deliberate and is why the two
-- uncapped upgrades stay uncapped: a cap says "you are finished", a price says "not yet".
--
-- WHY THE MULTIPLIER MOVES TOO AND NOT JUST THE BASE. Raising only the base shifts the whole ladder
-- sideways and leaves the shape alone -- the tenth level would still cost 12x the first, and a
-- player who reached it would still be buying the eleventh the same evening. The effect is LINEAR
-- in the level (+10% each, +5 luck each) while the price is geometric, so the multiplier is the
-- only term that decides where the upgrade stops being worth buying. 1.75 puts that wall somewhere
-- around level 10-12 for a dedicated player, which is where an "endgame" permanent upgrade belongs.
--
-- STAGE MASTERY IS DELIBERATELY NOT REPRICED alongside this. It is twenty ONE-SHOT purchases each
-- gated on reaching its stage, so its ceiling is the climb rather than the wallet; a player cannot
-- rush it with diamonds however many they hold. These three are the unbounded sink and are the
-- ones a diamond income can outrun.
--
-- EXISTING SAVES KEEP EVERY LEVEL THEY BOUGHT. `GetDiamondUpgradeCost` reads the level out of the
-- save and prices the NEXT one, so a reprice is never retroactive and never refunds -- a beta
-- player who bought ten cheap levels keeps them and pays the new rate for the eleventh.
GameConfig.DiamondUpgrades = {
	MegaIncome = { displayName = "Mega Income", emoji = "💎", baseCost = 25, costMult = 1.75, effectPct = 10, description = "+10% permanent income per level" },
	MegaLuck   = { displayName = "Mega Luck",   emoji = "🍀", baseCost = 40, costMult = 1.75, effectAdd = 5,  description = "+5% Luck per level" },
	PetSlot    = { displayName = "Pet Slot",    emoji = "🐾", baseCost = 75, costMult = 2.5,  effectAdd = 1, maxLevel = 3, description = "+1 equipped pet slot per level (max 3)" },
}

-- ===== DIAMONDS FROM PLAYING =====
--
-- Until now Diamonds had no gameplay source at all. Every one of them came from a time gate --
-- the daily reward, a playtime milestone, a Season Pass tier -- or from a Robux product, and at the
-- time every RobuxProducts entry still had `productId = 0`, so that route did not work either. (The
-- ids are real since 2026-08-11, but that does not change the argument below: a player who simply
-- plays must be able to earn the currency that three permanent upgrades and twenty Stage Masteries
-- are priced in, without paying.)
--
-- A per-kill roll fixes that without touching any existing balance: it adds a currency rather than
-- multiplying an existing one.
--
-- WEIGHTED BY TIER, NOT BY STAGE. Deliberately: kill RATE already rises steeply with stage, so a
-- flat per-kill chance pays out faster and faster on its own. Tying the odds to the target instead
-- makes the tougher creature the one worth hunting and keeps the curve honest.
--
-- ===== THESE ODDS WERE TOO LOW TO BE A FEATURE =====
--
-- The first cut was sized purely against the sink: 0.003-0.040 by tier, an expected 0.0068 diamonds
-- a kill, "one every five minutes". The arithmetic was right and the design was wrong, and the
-- report was the flat sentence "I never get diamonds, I cannot earn them at all".
--
-- A 0.3% drop is invisible. A player kills two hundred Swarmers, sees nothing, and correctly
-- concludes the mechanic does not exist -- there is no partial credit and no counter ticking up, so
-- below some floor a random drop is indistinguishable from a bug. The floor is roughly "often
-- enough to happen inside one session at one spot", and 0.3% is nowhere near it.
--
-- 10x across the board. At the same 30 kills a minute and the same tier mix that is ~0.068 a kill,
-- i.e. **two a minute**: a Swarmer pays about one time in thirty, an Elite one time in three. The
-- mechanic is now legible from the first few minutes of play, which is what it has to be to read as
-- a reward at all. The sink is what should absorb this, not the source -- see DiamondUpgrades.
--
-- ===== AND THE APEX WAS WORTH LESS THAN A SWARMER (11.31) =====
--
-- This table is keyed by tier NAME and had four rows. 11.6 added a fifth tier -- the Apex, on the
-- highest shelf of every zone, behind three rebirths, with 1.25x an Elite's health, hitting back on
-- 95% of blows -- and did not add a row here, so `RollDiamondDrop("Apex")` fell through the `or 0`
-- and returned zero. Measured: 200,000 rolls per tier came back 0.0302 / 0.0604 / 0.1510 / 0.4016
-- and **0.0000**. The hardest creature in the game paid nothing in the currency every permanent
-- upgrade is priced in, while the Critter standing at the bottom of the same cliff paid 6%.
--
-- The exclusive pet is not an answer to that: it is a 5% roll, so 95% of the fight paid a
-- rebirth-gated player strictly less than a Swarmer.
--
-- 0.60, above the Elite's 0.40, because it must not merely match the tier below it -- but it is a
-- 120-second respawn and four per zone, so this is 2.4 diamonds a sweep and not a farm.
--
-- THE REAL DEFENCE IS THE ASSERT, NOT THE ROW. See `GameConfig.AssertTierCoverage`, called by
-- CreatureService at load with the tier list it actually spawns: a table keyed by name, read
-- through `or 0`, cannot report its own gaps, and a sixth tier would be silently free again.
GameConfig.DiamondDropChance = {
	Swarmer = 0.03,
	Critter = 0.06,
	Brute    = 0.15,
	Elite    = 0.40,
	Apex     = 0.60,
}

-- ===== BOSSES ALWAYS PAY, AND THEY PAY A HANDFUL =====
--
-- A boss had NO diamond source at all -- neither the zone bosses nor the Colosseum giant -- so the
-- one fight in the game that takes real effort was worth less in this currency than farming
-- Swarmers. That is backwards, and it is the other half of what was reported.
--
-- A boss is not a roll. It is a rare, scheduled, expensive fight, so it is a GUARANTEED payout and
-- the variance lives in the amount. Zone bosses give 3-6; the Colosseum giant, which is on a
-- 30-minute timer and shared between everyone present, gives 12-20.
GameConfig.BossDiamondReward = { 3, 6 }
GameConfig.EventBossDiamondReward = { 12, 20 }

function GameConfig.RollDiamondDrop(tierName)
	local chance = GameConfig.DiamondDropChance[tierName or ""] or 0
	return math.random() < chance and 1 or 0
end

-- ===== EVOLUTION SHARDS: THE ONE DROP YOU HAVE TO CLIMB FOR (9.4) =====
--
-- Shards had no gameplay source at all once 9.2 took them off the rebirth reward. What was left was
-- three time gates (the Day 6/7 login reward, the Season Pass premium track, a 7% segment of the
-- wheel) and a code -- not one of which is something a player can go and DO. They are a drop now.
--
-- And they are deliberately the only drop in this game with a PLACE attached: nothing standing on
-- the valley floor ever pays one, however long it is farmed. Only the Brutes and Elites up on the
-- terrace shelves do -- CreatureService's `raisedSpots`, which already ranks those spots by
-- altitude and puts the Elites on the highest ground there is. So the currency is earned by
-- climbing, which is the one thing the terraces were built for and the one thing nothing else in
-- the game rewards.
--
-- Sized against its sink exactly the way DiamondDropChance was sized against the upgrades. A zone
-- carries 4 raised Elites and 6 raised Brutes, so one full sweep of its shelves pays
-- 4*0.25 + 6*0.12 = 1.72 shards, and one spin of the wheel costs 25 (SpinCostShards) -- roughly a
-- quarter of an hour of deliberate cliff work per spin, against a 55-second Elite respawn. That is
-- above the "is this mechanic even real" floor the diamond note describes and far enough below a
-- diamond's rate that the two can never read as the same reward.
--
-- ===== THE APEX WAS MISSING FROM HERE TOO (11.31) =====
--
-- Same gap as DiamondDropChance, same cause -- a table keyed by tier name that 11.6's new tier was
-- never added to -- and it is worse here, because this is the currency the shelves exist to mint
-- and the Apex stands on the highest shelf of the lot. A player who spent three rebirths to be
-- allowed to fight it was paid less for it than for the Brute two terraces below.
--
-- 0.40 against the Elite's 0.25. The sweep arithmetic above becomes, for a 3-rebirth player,
-- 4*0.40 + 4*0.25 + 6*0.12 = 3.32 shards -- so a spin (25) is about seven and a half sweeps
-- instead of fifteen. That is the gate paying out, which is what a gate is for; and the roster
-- figures are 11.29's, not 9.4's, because the raised set went 10 -> 14 per zone.
GameConfig.ShardDropChance = {
	Brute = 0.12,
	Elite = 0.25,
	Apex  = 0.40,
}

-- `raised` is PASSED IN rather than inferred from anything on the creature. A Brute on the valley
-- floor and a Brute on a shelf are the same tier, the same rig and the same table of stats; the
-- only thing that tells them apart is which loop the spawner placed them from.
function GameConfig.RollShardDrop(tierName, raised)
	if not raised then return 0 end
	local chance = GameConfig.ShardDropChance[tierName or ""] or 0
	return math.random() < chance and 1 or 0
end

-- ===== A TABLE KEYED BY NAME CANNOT REPORT ITS OWN GAPS (11.31) =====
--
-- Both drop tables above are read through `... or 0`, and that fallback is right at the call site:
-- a boss, a loose `DeathBurst` part and a tier that genuinely pays nothing all have to fall through
-- it without throwing. It is also exactly why a MISSING tier is indistinguishable from a deliberate
-- zero -- 11.6 added the Apex, neither table heard about it, and nothing anywhere said so until
-- 200,000 Monte Carlo rolls were run against the tier list by hand.
--
-- So the check is inverted rather than the fallback removed. CreatureService owns the list of tiers
-- it actually spawns and hands it here at load; this file cannot go and read `TIERS` itself, because
-- GameConfig is required BY CreatureService and would be a require cycle.
--
-- Deliberately a `warn` and not an `error`: a missing drop row must never stop a server booting, and
-- the failure it guards against is silence, not a crash. Naming the table and the tier is the whole
-- difference. Returns the list so a probe can assert on it instead of reading the output log.
function GameConfig.AssertTierCoverage(allTiers, raisedTiers)
	local missing = {}
	for _, name in ipairs(allTiers or {}) do
		if GameConfig.DiamondDropChance[name] == nil then
			missing[#missing + 1] = "DiamondDropChance." .. name
		end
	end
	-- Only tiers that can actually stand on a shelf need a shard row -- `RollShardDrop` returns 0 for
	-- anything not raised, so a Swarmer row here would be dead weight that reads as a promise.
	for _, name in ipairs(raisedTiers or {}) do
		if GameConfig.ShardDropChance[name] == nil then
			missing[#missing + 1] = "ShardDropChance." .. name
		end
	end
	if #missing > 0 then
		warn("[GameConfig] no drop row for " .. table.concat(missing, ", ")
			.. " -- those kills pay nothing. See the 11.31 block in GameConfig.")
	end
	return missing
end

-- `event` picks the Colosseum giant's band instead of a zone boss's. Guaranteed, never zero.
function GameConfig.RollBossDiamonds(event)
	local band = event and GameConfig.EventBossDiamondReward or GameConfig.BossDiamondReward
	return math.random(band[1], band[2])
end

function GameConfig.GetDiamondUpgradeCost(key, level)
	local def = GameConfig.DiamondUpgrades[key]
	if not def then return math.huge end
	if def.maxLevel and level >= def.maxLevel then return math.huge end
	return math.floor(def.baseCost * (def.costMult ^ level))
end

function GameConfig.GetMaxEquippedPets(data)
	local petSlotLevel = data.DiamondUpgrades and data.DiamondUpgrades.PetSlot or 0
	-- The +3 Pet Slots pass stacks ON TOP of the diamond upgrade rather than replacing it: the
	-- upgrade is capped at 3 levels, so a player who bought all three and then bought the pass has
	-- spent in both currencies and should get both. 3 base + 3 diamond + 3 pass = 9.
	return GameConfig.MaxEquippedPets + petSlotLevel + GameConfig.GetPassAdd(data, "petSlots")
end

end
