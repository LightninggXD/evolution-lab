-- GameConfig.Potions -- the three potion kinds in three sizes, and the health bottle's two numbers.
--
-- ONE OF THE SIXTEEN PARTS OF `GameConfig` (18.9), moved byte for byte. It is handed the
-- shared config table and writes into it; see the loader in `GameConfig` itself for why
-- the order of the parts is load-bearing and why nothing here is re-indented.

return function(GameConfig)

-- ===== POTIONS =====
-- There used to be ONE potion: a five-minute x2 on income, held as a single integer on the save.
-- Three effects in three sizes now -- nine bottles -- because a consumable with no choice in it is
-- just a delayed number, and because the three things a player actually wants to hurry are not the
-- same thing: DNA is the currency, XP is the evolve gate, and Luck is the whole egg/pet economy.
--
-- ONE ACTIVE BOTTLE PER KIND. Drinking a second DNA potion while one is running does not stack the
-- multiplier -- it takes the HIGHER of the two and adds the remaining time -- but a DNA, an XP and
-- a Luck potion all run at once. Stacking multipliers is how a consumable economy turns into a
-- single 'drink everything at hour three' decision; running three different effects together is a
-- choice about what to hurry.
--
-- `data.Potions` is a table keyed by potion id ('dna_s'), and `data.PotionBoosts` is keyed by KIND
-- ('dna'). Both are string-keyed on purpose: a table whose only keys are integers is a sparse array
-- and Roblox silently drops those crossing a RemoteEvent -- the bug that ate EquippedCharacters.
GameConfig.PotionKinds = {
	{ key = "dna",  name = "DNA",  emoji = "\u{1F9EC}", color = Color3.fromRGB(96, 200, 255),  blurb = "DNA from every source" },
	{ key = "xp",   name = "XP",   emoji = "\u{2B50}",   color = Color3.fromRGB(255, 206, 92),  blurb = "Evolution XP" },
	{ key = "luck", name = "Luck", emoji = "\u{1F340}", color = Color3.fromRGB(126, 226, 132), blurb = "egg, pet, character and mutation luck" },
	-- ===== THE FOURTH KIND (11.8) =====
	--
	-- Nine potions become twelve without a single new potion being written, because the loop below
	-- builds every kind x size combination itself -- which is the property the row was protecting:
	-- a size added later cannot be given to three kinds and forgotten on the fourth.
	--
	-- It multiplies MAX HEALTH, and deliberately not by `size.mult`. Max health already scales with
	-- the stage and with Stage Mastery and with the worn skin's rank; a x5 on top of that product for
	-- twenty minutes is not a consumable, it is a different game. `healthMult` is its own column on
	-- the sizes table so the numbers can be gentle (1.5 / 2 / 2.5) while the table still refuses to
	-- let a new size skip it.
	{ key = "health", name = "Health", emoji = "\u{2764}\u{FE0F}", color = Color3.fromRGB(255, 104, 118), blurb = "max health, and faster regeneration" },
}

-- Luck is an ADDITIVE percentage everywhere else in the game (upgrades give +2 a level, pets give
-- luckAdd), so a luck potion has to add too -- a multiplier on a stat that starts at zero does
-- nothing at all for a new player, which is exactly who buys the first one.
GameConfig.PotionSizes = {
	{ key = "s", name = "Small",  emoji = "\u{1F9EA}", minutes = 5,  mult = 2, luckAdd = 25,  healthMult = 1.5, regenMult = 3, costMult = 1 },
	{ key = "m", name = "Medium", emoji = "\u{2697}\u{FE0F}", minutes = 10, mult = 3, luckAdd = 55,  healthMult = 2.0, regenMult = 5, costMult = 2.8 },
	{ key = "l", name = "Large",  emoji = "\u{1F36F}", minutes = 20, mult = 5, luckAdd = 120, healthMult = 2.5, regenMult = 8, costMult = 7 },
}

-- The nine, built from the two lists above so a size or an effect can never be added to one and
-- forgotten in the other.
GameConfig.Potions = {}
GameConfig.PotionsById = {}
for _, kind in ipairs(GameConfig.PotionKinds) do
	for _, size in ipairs(GameConfig.PotionSizes) do
		local potion = {
			id = kind.key .. "_" .. size.key,
			kind = kind.key,
			size = size.key,
			name = size.name .. " " .. kind.name .. " Potion",
			shortName = size.name .. " " .. kind.name,
			emoji = kind.emoji,
			sizeEmoji = size.emoji,
			color = kind.color,
			minutes = size.minutes,
			seconds = size.minutes * 60,
			-- Each kind carries exactly the field it acts through and nils the rest: luck is additive
			-- points, health has its own gentler multiplier plus a regen rate, and DNA and XP take
			-- the shared `size.mult`. `applyBoost` keeps the STRONGER of each field when a second
			-- bottle is drunk, so a field that is nil for a kind simply never enters that comparison.
			mult = (kind.key == "dna" or kind.key == "xp") and size.mult
				or (kind.key == "health") and size.healthMult
				or nil,
			luckAdd = (kind.key == "luck") and size.luckAdd or nil,
			regenMult = (kind.key == "health") and size.regenMult or nil,
			costMult = size.costMult,
			blurb = kind.blurb,
		}
		-- %.15g rather than %d, since 11.8's health multipliers are fractional (1.5) and %d on a
		-- float is an error in Luau, not a rounding. It still prints "x2" for the whole ones.
		potion.effectText = potion.mult
			and ("x%.15g %s"):format(potion.mult, kind.blurb)
			or ("+%d%% %s"):format(potion.luckAdd, kind.blurb)
		table.insert(GameConfig.Potions, potion)
		GameConfig.PotionsById[potion.id] = potion
	end
end

-- What a grant with no id attached hands over (old saves, Daily Rewards, Robux bundles).
GameConfig.DefaultPotionId = "dna_s"

function GameConfig.GetPotion(id)
	return GameConfig.PotionsById[id]
end

-- The live boost for one kind, or nil. Expiry is checked HERE rather than by a timer, so a boost
-- that ran out while the player was offline is simply never returned and nothing has to clean up.
function GameConfig.GetPotionBoost(data, kind)
	local boost = data and data.PotionBoosts and data.PotionBoosts[kind]
	if not boost then return nil end
	if (boost.untilTs or 0) <= os.time() then return nil end
	return boost
end

-- 1 when nothing is running, so every caller can multiply unconditionally.
function GameConfig.GetPotionMult(data, kind)
	local boost = GameConfig.GetPotionBoost(data, kind)
	return (boost and boost.mult) or 1
end

-- ===== THE HEALTH BOTTLE'S TWO NUMBERS (11.8) =====
--
-- Kept as their own accessors rather than letting call sites reach for `GetPotionMult(data,
-- "health")`, because the max-health one is multiplied into a product that already has three terms
-- in it (stage, Stage Mastery, worn skin rank) and the regen one is a rate, not a multiplier on
-- anything. Both return the neutral value when nothing is running, so both are safe to apply
-- unconditionally -- the same contract `GetPotionMult` has.
function GameConfig.GetPotionHealthMult(data)
	return GameConfig.GetPotionMult(data, "health")
end

function GameConfig.GetPotionRegenMult(data)
	local boost = GameConfig.GetPotionBoost(data, "health")
	return (boost and boost.regenMult) or 1
end

-- Additive percentage points, matching every other luck source.
function GameConfig.GetPotionLuckAdd(data)
	local boost = GameConfig.GetPotionBoost(data, "luck")
	return (boost and boost.luckAdd) or 0
end

-- The one place a potion is added to a save. Every grant path -- shop, Daily Reward, playtime
-- gift, Robux bundle -- goes through it, so the number->table migration only had to be got right
-- once and an unknown id can never quietly create a bottle that does not exist.
function GameConfig.AddPotions(data, potionId, count)
	local potion = GameConfig.PotionsById[potionId] or GameConfig.PotionsById[GameConfig.DefaultPotionId]
	if type(data.Potions) ~= "table" then data.Potions = {} end
	data.Potions[potion.id] = (data.Potions[potion.id] or 0) + (count or 1)
	return potion
end

-- How many of everything a player is holding, for the HUD badge.
function GameConfig.CountPotions(data)
	local n = 0
	for _, count in pairs((data and data.Potions) or {}) do
		if type(count) == "number" then n += count end
	end
	return n
end

end
