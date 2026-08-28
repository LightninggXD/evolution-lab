-- GameConfig.Upgrades -- the four DNA upgrades and the mutation table.
--
-- ONE OF THE SIXTEEN PARTS OF `GameConfig` (18.9), moved byte for byte. It is handed the
-- shared config table and writes into it; see the loader in `GameConfig` itself for why
-- the order of the parts is load-bearing and why nothing here is re-indented.

return function(GameConfig)

-- ===== UPGRADES =====
-- baseCost grows by costMult per level. effect described per stat.
--
-- COST MULTIPLIERS RAISED 2026-08-11 (1.14-1.22 -> 1.28-1.38) on the owner's report that upgrades
-- came far too fast. They are capped now as well -- see GetUpgradeMaxLevel, five levels per unlocked
-- zone -- and the two changes are meant to be read together: the cap decides how FAR you may go,
-- the multiplier decides how long each rung takes.
--
-- Measured against the cap rather than guessed. Full ladder totals at the three points that matter:
--            zone 1 (5 lv)   zone 5 (25 lv)   zone 20 (100 lv)
--   Speed         216            42.7K             4.7T
--   Income        175            40.0K             7.9T
--   Luck          373           129.1K           142.7T
--   AutoCollect   1.1K          826.1K            25.6Qa
-- Cheap enough that a new player can buy the five they are allowed, and a genuine sink at the top
-- against an endgame DNA balance of roughly 1e18.
--
-- `Mutation` ("Mutation Chance") is GONE, not merely delisted (Phase 12): the ambient roll it
-- fed no longer exists -- mutations are bought at the DNA Splicer -- so the upgrade had nothing
-- left to speed up. Paid levels are refunded at their exact geometric sum by the load
-- migration in PlayerDataService, which carries the base 60 / mult 1.35 as literals because
-- this table no longer does.
-- THE `Speed` ROW IS GONE (34.29). Speed comes from the worn Trail now -- her call, *"nema vise
-- speed u shopu da se kupi vec nek bude vise ovih trails i one ce da upgradaju speed"*. Levels
-- already bought are refunded at their exact geometric sum by the load migration in
-- `PlayerDataService`, which carries the base 25 / mult 1.28 as literals because this table no
-- longer does -- the same arrangement the Mutation Chance removal left behind, one row up.
GameConfig.Upgrades = {
	Income = {
		displayName = "Income",
		emoji = "💰",
		baseCost = 20,
		costMult = 1.29,
		description = "+DNA per click and per second",
	},
	Luck = {
		-- Renamed and rewritten with 11.5's split: this is now EGG luck and nothing else, at
		-- +5 points a level (GameConfig.PetLuckPerUpgradeLevel). The old text named crit DNA and
		-- mutations, which stopped being true the moment the upgrade left GetLuckPercent -- see
		-- the note over that function.
		displayName = "Egg Luck",
		emoji = "🍀",
		baseCost = 40,
		costMult = 1.32,
		description = "+5% egg luck a level - rarer pets from every hatch",
	},
	AutoCollect = {
		displayName = "Auto Collect",
		emoji = "⚙️",
		baseCost = 100,
		costMult = 1.38,
		description = "Earns DNA every second, even while you idle",
	},
}

-- ===== MUTATIONS =====
-- Rolled ONLY at the DNA Splicer now. Index order is rarity order -- the pity guarantee, the
-- announce threshold and "which of two is better" all compare indices, so a new entry goes in
-- rank position, never appended out of order. Repriced with the Splicer (was 1.3 .. 30): these
-- are BOUGHT now, and a x30 top end would let one lucky roll outweigh the entire Income
-- upgrade ladder. `speedPct` is a PERCENTAGE OF THAT PLAYER'S WALK CAP (see GetMutationSpeedPct
-- for why it is no longer flat studs) -- whole numbers, because every line that prints it prints
-- `+%d%% speed` and a half percent of a cap is not a difference anyone can feel.
GameConfig.Mutations = {
	{ name = "Common",    weight = 500, incomeMult = 1.05, speedPct = 2,  color = Color3.fromRGB(200,200,200) },
	{ name = "Rare",      weight = 200, incomeMult = 1.10, speedPct = 3,  color = Color3.fromRGB(90,160,255) },
	{ name = "Epic",      weight = 80,  incomeMult = 1.18, speedPct = 5,  color = Color3.fromRGB(170,90,255) },
	{ name = "Legendary", weight = 25,  incomeMult = 1.30, speedPct = 6,  color = Color3.fromRGB(255,180,50) },
	{ name = "Mythic",    weight = 8,   incomeMult = 1.50, speedPct = 8,  color = Color3.fromRGB(255,80,80) },
	{ name = "Secret",    weight = 2,   incomeMult = 1.80, speedPct = 10, color = Color3.fromRGB(20,20,20) },
	{ name = "Godly",     weight = 1,   incomeMult = 2.25, speedPct = 12, color = Color3.fromRGB(255,240,150) },
}

end
