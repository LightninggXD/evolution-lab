-- GameConfig.Helpers -- the shared accessors, the upgrade caps and the DNA Splicer.
--
-- ONE OF THE SIXTEEN PARTS OF `GameConfig` (18.9), moved byte for byte. It is handed the
-- shared config table and writes into it; see the loader in `GameConfig` itself for why
-- the order of the parts is load-bearing and why nothing here is re-indented.

return function(GameConfig)

-- ===== HELPER FUNCTIONS =====

-- A FIXED DNA REWARD IS MEANINGLESS IN AN ECONOMY THAT SPANS 1e2 TO 1e17.
--
-- The daily login track tops out at 23,000 DNA and the playtime ladder at 35,000. One Mars
-- creature pays 24,150 -- so from stage 6, about fifteen minutes in, the ENTIRE seven-day login
-- cycle is worth less than a single kill, and every login reward after that is a rounding error
-- dressed up as a prize. The Season track has the opposite half of the same problem: its early
-- levels hand a brand-new player one or two whole stages instantly, and its level-30 payout is
-- 0.003 of one creature by the time anyone reaches it.
--
-- The authored numbers are not wrong -- they are a well-shaped ladder AT STAGE ONE, and each
-- reward's size relative to the others is the design. What is missing is the same growth curve
-- everything else in the game is on. So the authored figure is read as "how many stage-1 clicks
-- this is worth" and converted to what that is worth where the player actually stands.
--
-- Scaled RELATIVE TO STAGE ONE, which is what the tables were authored against: at stage 1 the
-- multiplier is exactly 1 and every reward pays precisely what its card says, and from there it
-- rides the same GetClickBase curve the rest of the income does. A reward is therefore worth the
-- same number of KILLS at stage 20 as it was at stage 1, which is the property that was missing.
--
-- A square root was tried first and is wrong: it decays against the curve it is meant to follow,
-- so the day-7 login still fell from 1,681 kills to 0.1 across the twenty stages -- a smaller
-- version of the same bug rather than a fix for it.
--
-- Floored at 1 so nothing can ever pay LESS than it says on the card.
function GameConfig.ScaleReward(amount, data)
	local stageIndex = (data and data.StageIndex) or 1
	local mult = math.max(GameConfig.GetClickBase(stageIndex) / GameConfig.GetClickBase(1), 1)
	return math.floor((amount or 0) * mult)
end

-- WHAT THE SPEED UPGRADE DOES. Until this existed: nothing.
--
-- `Speed` is the cheapest upgrade in the game (25 DNA) and the first one in the shop's order, so
-- it is the first purchase almost every new player makes -- and no line anywhere in the game ever
-- read `data.Upgrades.Speed`. The level went up, the cost went up, and the character moved at
-- exactly the same pace. The first thing a player buys cannot be the thing that teaches them
-- buying does nothing.
--
-- Flat studs per level rather than a multiplier: it is applied BEFORE the body-size multiplier in
-- EvolutionVisuals.applyMastery, so a level bought at Cell is worth proportionally more later,
-- which is the same shape every other early upgrade in this game has.
GameConfig.SpeedPerLevel = 1.5

function GameConfig.GetSpeedUpgradeBonus(data)
	local level = data and data.Upgrades and data.Upgrades.Speed or 0
	return level * GameConfig.SpeedPerLevel
end

-- ===== UPGRADES ARE CAPPED BY HOW FAR YOU HAVE ACTUALLY GOT =====
--
-- Five levels per unlocked zone (owner's decision, 2026-08-11): 5 at the start, 100 with all twenty
-- zones open. Before this there was **no ceiling at all** -- not in the price function, which had no
-- cap path unlike the Diamond upgrades, and not in `HandleBuyUpgrade`, which checked only that the
-- key existed and that the player could pay. A player who parked in zone 1 could buy Speed to
-- level 400 and outrun the entire progression the zones are supposed to gate.
--
-- Tied to ZONES rather than to stage or rebirth because a zone is the thing the player visibly
-- earns and can count, and it is already the gate on every other kind of power in the game.
GameConfig.UpgradeLevelsPerZone = 5

function GameConfig.GetUpgradeMaxLevel(data)
	local zones = (data and data.UnlockedZones) and #data.UnlockedZones or 1
	return math.max(zones, 1) * GameConfig.UpgradeLevelsPerZone
end

-- `data` is optional: without it this is the raw price of the next level, which is what a tool or a
-- test wants. With it, a level at or past the cap costs `math.huge` -- the same sentinel the Diamond
-- upgrades already use for a maxed row, so every "can I afford it" check in the game refuses it for
-- free without a single new branch.
function GameConfig.GetUpgradeCost(upgradeKey, currentLevel, data)
	local def = GameConfig.Upgrades[upgradeKey]
	if not def then return math.huge end
	if data and currentLevel >= GameConfig.GetUpgradeMaxLevel(data) then
		return math.huge
	end
	return math.floor(def.baseCost * (def.costMult ^ currentLevel))
end

function GameConfig.RollMutation(luckPercent)
	-- luckPercent: 0 = base, higher = better odds for rare mutations
	local totalWeight = 0
	local weights = {}
	for i, m in ipairs(GameConfig.Mutations) do
		-- luck boosts rarer (later) entries more
		local boost = 1 + (luckPercent / 100) * (i - 1) * 0.5
		local w = m.weight * boost
		weights[i] = w
		totalWeight = totalWeight + w
	end
	local roll = math.random() * totalWeight
	local acc = 0
	for i, w in ipairs(weights) do
		acc = acc + w
		if roll <= acc then
			return GameConfig.Mutations[i]
		end
	end
	return GameConfig.Mutations[1]
end

-- ===== THE DNA SPLICER (Phase 12) =====
-- The machine on the Forest plaza that mutations are rolled at, and DNA's late-game sink.
--
-- PRICED IN KILLS, NOT THROUGH ScaleReward. ScaleReward grows 2.85x a stage while real
-- per-kill income grows ~5x (the click base times the zone income bonus times mobDnaMult --
-- the same product the income-curve comment above GetClickBase says to verify against), so a
-- ScaleReward-priced roll would get ~44% cheaper IN KILLS every stage and be free by stage 20.
-- Costing the roll as a multiple of the player's own per-kill income keeps it the same number
-- of kills at every stage, which is the property a sink has to have.
--
-- The ramp is per LIFETIME roll (`data.SplicerRolls`) and is deliberately NOT reset by a
-- rebirth -- a reset would turn rebirth into a cost-reset coupon: roll 1 is ~5 kills at any
-- stage, roll 25 is ~49, and from roll ~56 the cap holds every further roll at a flat 1,000
-- kills -- 45-90 minutes of active play per roll, forever. At stage 20 that is ~1.1e17 DNA a
-- roll, 12x the most expensive egg, against an endgame balance of roughly 1e18.
GameConfig.Splicer = {
	baseKills = 5,        -- roll 1, in kills of the player's newest zone
	ramp = 1.10,          -- per lifetime roll
	rampCap = 200,        -- ramp^n stops here: baseKills * 200 = 1,000 kills a roll
	pityEvery = 10,       -- every Nth lifetime roll is "charged"...
	pityMinIndex = 2,     -- ...guaranteed at least Mutations[2] (Rare)...
	pityLuckAdd = 150,    -- ...and rolled with this much extra luck
	luckScale = 0.25,     -- fraction of GetLuckPercent that reaches RollMutation
	luckCap = 400,        -- luck points considered before scaling
	announceMinIndex = 5, -- Mutations[5]+ (Mythic, Secret, Godly) go server-wide
}

-- Pure over `data` for the same reason GetPetLuckPercent is: the client panel must quote the
-- price the server will charge, and two implementations would drift. `4.5` is the same tier
-- constant the income-curve comment uses -- an average kill against the Forest-baseline mix.
-- The newest unlocked zone is found by index, not by #UnlockedZones, so a save whose list is
-- ever out of order still prices against the furthest zone it has actually opened.
function GameConfig.GetSplicerRollCost(data)
	local stageIndex = (data and data.StageIndex) or 1
	local zoneKeys = (data and data.UnlockedZones) or { "Forest" }
	local zi = 1
	for _, k in ipairs(zoneKeys) do
		local i = GameConfig.GetZoneIndex(k)
		if i > zi then zi = i end
	end
	local zone = GameConfig.Zones[zi] or GameConfig.Zones[1]
	local perKill = GameConfig.GetClickBase(stageIndex)
		* (1 + GameConfig.GetTotalZoneBonusPct(zoneKeys) / 100)
		* 4.5 * (zone.mobDnaMult or 1)
	local S = GameConfig.Splicer
	local ramp = math.min(S.ramp ^ ((data and data.SplicerRolls) or 0), S.rampCap)
	return math.max(math.ceil(perKill * S.baseKills * ramp), 1)
end

-- The luck a Splicer roll is made with -- shared by the server handler and the client's odds
-- table, again so the promise and the roll cannot drift. `charged` is "this is the pity roll";
-- the caller decides that from `SplicerRolls`, because the SERVER increments the counter and
-- the client only predicts it.
function GameConfig.GetSplicerLuck(data, charged)
	local S = GameConfig.Splicer
	local luck = math.min(GameConfig.GetLuckPercent(data), S.luckCap) * S.luckScale
	if charged then luck += S.pityLuckAdd end
	return luck
end

end
