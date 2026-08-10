local RS = game:GetService("ReplicatedStorage")
local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS.Remotes

local PlayerDataService = require(script.Parent.PlayerDataService)
local PetService = require(script.Parent.PetService)

local DNAService = {}
DNAService.OnEvolve = nil -- optional callback(player, data) set by ServerMain to avoid circular requires

-- ===== STAT CALCULATIONS =====
function DNAService.GetIncomeMult(data, excludeEvents)
	local incomeLevel = data.Upgrades.Income
	local mult = 1 + incomeLevel * 0.12
	-- mutation bonus: best-one-applies, NOT the product of every mutation ever rolled -- see
	-- GetMutationIncomeMult in GameConfig for why the old product reached ~5,000,000x
	mult = mult * GameConfig.GetMutationIncomeMult(data.Mutations)
	-- zone bonuses (permanent % boost per unlocked zone)
	local zoneBonusPct = GameConfig.GetTotalZoneBonusPct(data.UnlockedZones)
	mult = mult * (1 + zoneBonusPct / 100)
	-- equipped pet bonuses
	mult = mult * PetService.GetEquippedBonus(data).incomeMult
	-- THE SHARD BALANCE IS DELIBERATELY NOT READ HERE ANY MORE (9.4). It used to be, at +2% each,
	-- which was harmless only while nothing in the game could spend a shard. Now that the wheel takes
	-- them, a line here would mean every spin permanently cut the spinner's income -- so the optimal
	-- play would be to never use the sink at all. See the note in GameConfig where the function used
	-- to live. The rebirth counter below is where the income a rebirth used to pay in Shards lives.
	mult = mult * GameConfig.GetRebirthIncomeMult(data)
	-- temporary DNA Potion (see PotionService). Returns 1 when none is running, and checks its own
	-- expiry, so a boost that ran out while the player was offline needs no cleanup anywhere.
	mult = mult * GameConfig.GetPotionMult(data, "dna")
	-- Diamond-bought Mega Income upgrade
	local megaIncomeLevel = data.DiamondUpgrades and data.DiamondUpgrades.MegaIncome or 0
	mult = mult * (1 + megaIncomeLevel * (GameConfig.DiamondUpgrades.MegaIncome.effectPct / 100))
	-- Robux game passes, LAST so a bought multiplier applies to everything above it rather than to
	-- the bare base. One call covers 2x DNA and VIP together (and anything added later carrying an
	-- `incomeMult` field) -- this function never learns any pass by name. Because this is the single
	-- income multiplier, the pass reaches clicks, kill payouts and idle auto-collect at once.
	mult = mult * GameConfig.GetPassMult(data, "incomeMult")
	-- ...and any live server-wide event, last of all (Phase 7.1). It takes no `data`, which is the
	-- difference between an event and a pass written out: an event is the same for everybody on the
	-- server, so a weekend cannot be something one player has and another does not.
	--
	-- `excludeEvents` has exactly ONE caller and it is not a special case for its own sake: the
	-- offline payout is this rate multiplied by up to eight hours of ABSENCE, so a weekend that
	-- happens to be running at the moment the player logs back in would pay double for hours they
	-- slept through on a Thursday. Everything earned in real time -- clicks, kills, idle collection
	-- while online -- passes nothing and gets the boost, which is the entire point of it.
	if not excludeEvents then
		mult = mult * GameConfig.GetEventMult("incomeMult")
	end
	return mult
end

function DNAService.GetLuckPercent(data)
	local megaLuckLevel = data.DiamondUpgrades and data.DiamondUpgrades.MegaLuck or 0
	local megaLuckAdd = megaLuckLevel * GameConfig.DiamondUpgrades.MegaLuck.effectAdd
	-- Every luck source in the game is additive percentage points, and the Luck Potion is one more
	-- of them: this single function is what eggs, pets, characters, mutations and crit chance all
	-- read, so adding it here reaches every one of them.
	-- The Lucky pass and VIP are ADDED here, in points, for the same reason everything else is: luck
	-- starts at zero, so a multiplier would pay a first-time buyer nothing at all.
	return data.Upgrades.Luck * 2 + PetService.GetEquippedBonus(data).luckAdd + megaLuckAdd
		+ GameConfig.GetPotionLuckAdd(data) -- each upgrade level = +2% luck, plus pets and potions
		+ GameConfig.GetPassAdd(data, "luckAdd")
		-- ...and any live event, in points for the same reason everything else here is. A festival
		-- that multiplied luck would pay nothing at all to the player who has never bought any.
		+ GameConfig.GetEventAdd("luckAdd")
end

function DNAService.GetClickAmount(data)
	-- geometric in the stage index, so it tracks the ~5x evolve-cost curve instead of falling
	-- ~3x behind it every stage -- see the INCOME CURVE block in GameConfig
	local base = GameConfig.GetClickBase(data.StageIndex)
	local amount = base * DNAService.GetIncomeMult(data)
	amount = amount * PetService.GetEquippedBonus(data).dnaMult

	-- critical chance based on luck
	local luck = DNAService.GetLuckPercent(data)
	local critChance = math.clamp(5 + luck * 0.5, 0, 75) -- %
	if math.random(1, 100) <= critChance then
		amount = amount * 5
		return amount, true
	end
	return amount, false
end

-- ===== THE ONE PLACE DAMAGE IS DECIDED =====
--
-- Every blow in the game is this number: creature clicks, auto-attack, boss hits, and the figure
-- the Journal prints under a rung. Nothing anywhere else computes damage, and nothing may clamp
-- what comes out of here -- `CreatureService`'s `tier.damageCap` and `BossService`'s
-- `BOSS_MIN_HITS` both used to, and between them they were the whole "evolving changes nothing"
-- bug: they replaced this number with a constant per target and then the FX drew the constant.
-- See the DAMAGE LADDER block in GameConfig for the measurements.
--
-- The base is the player's rung on the 100-step character ladder, geometric, tuned so that kills
-- per creature stay flat across all twenty zones. Everything below is a multiplier on it, ordered
-- so that anything bought applies to everything climbed rather than to the bare base.
function DNAService.GetCombatDamage(data)
	local base = GameConfig.GetBaseDamage(data)
	local mult = 1 + (data.Upgrades.Income or 0) * 0.01
	mult = mult * PetService.GetEquippedBonus(data).damageMult
	-- permanent Stage Mastery unlocks, bought with Diamonds and kept through Rebirth
	mult = mult * GameConfig.GetStageMasteryBonus(data).damageMult
	-- and every rebirth the player has ever done. This is what a rebirth buys -- see the note over
	-- GameConfig.GetRebirthDamageMult for why it is damage and not income.
	mult = mult * GameConfig.GetRebirthDamageMult(data)
	-- Robux game passes: 2x Damage and VIP. Note this raises damage DEALT only -- the incoming-damage
	-- cap in CreatureService/BossService is a fraction of the player's own health and is untouched,
	-- so a pass makes fights shorter without making the player unkillable.
	mult = mult * GameConfig.GetPassMult(data, "damageMult")
	-- The event hook exists here even though NO event currently sets `damageMult` -- the weekend
	-- deliberately does not, see the note over GameConfig.Events. It is here so that the day one
	-- does, it is a row in that table and not an edit in this file: the same rule the passes follow.
	mult = mult * GameConfig.GetEventMult("damageMult")
	return math.floor(base * mult)
end

-- ===== IDLE INCOME MUST NEVER BEAT PLAYING, AND IT DID BY A FACTOR OF THOUSANDS =====
--
-- This was `level * 1.6 * GetClickBase(stage) * GetIncomeMult(data)`, once a second, forever. The
-- `level * 1.6` is the whole bug: at AutoCollect 50 it paid EIGHTY clicks per second, and it
-- compounded three ways at once -- linearly in the level, geometrically in the stage (GetClickBase),
-- and again through GetIncomeMult, which already contains the Income upgrade's own level.
--
-- Measured on a plausible save at Worm, where evolving costs 2,500 DNA:
--
--   AutoCollect 10 ->    1,264 DNA/sec   (4.5M an hour)
--   AutoCollect 25 ->    5,744 DNA/sec   (20.7M an hour)
--   AutoCollect 50 ->   20,105 DNA/sec   (72.4M an hour)
--
-- Eight evolutions a second, standing still. And the upgrade costs 1.22^level while paying out
-- linearly in level, so it repays itself in about two minutes and prints money after that. That is
-- where "I just started and already have millions" came from: the number was never earned by
-- fighting, so nothing in the game -- egg prices, evolve costs, shop prices -- could mean anything.
--
-- CAPPED IN UNITS OF CLICKS, which is the only unit that keeps it honest. The rate is now a
-- FRACTION of one click per second and tops out at 1.2, so a player who is actually fighting
-- (roughly a kill a second, and a kill pays a full click times the tier and zone multipliers)
-- always out-earns a player who is not. It still scales with the stage and with the income stack,
-- so it never becomes dead weight late on -- that was the real complaint the `level * 1.6` was
-- written to answer, and the stage curve alone answers it.
-- `excludeEvents` is passed straight through to GetIncomeMult and is used by OfflineService alone;
-- the reasoning is written out there and at the hook itself.
function DNAService.GetAutoCollectAmount(data, excludeEvents)
	local level = data.Upgrades.AutoCollect
	if level <= 0 then return 0 end
	-- 0.04 a level, capped at 1.2 -- i.e. levels 1..30 buy the curve and 30 is the ceiling
	local rate = math.min(level * 0.04, 1.2)
	local base = rate * GameConfig.GetClickBase(data.StageIndex)
	return base * DNAService.GetIncomeMult(data, excludeEvents)
end

function DNAService.GetMutationChancePerRoll(data)
	local level = data.Upgrades.Mutation
	return math.clamp(2 + level * 1.5, 0, 60) -- % chance every roll interval
end

-- ===== ACTIONS =====

-- THE CLICK IS THE GAME, WHICH IS EXACTLY WHY IT NEEDS A CEILING.
--
-- `CollectClick` took no arguments and did no checking: one line in an exploit client --
-- `while true do CollectClick:FireServer() end` -- paid out `GetClickAmount` per invocation, at
-- whatever rate the network would carry. That is every upgrade, every Premium egg and every
-- Diamond purchase in the game inside a minute, and because each call also replicated the entire
-- save back down (see PushToClient) it was a way to flatten the server at the same time.
--
-- 0.07s is 14 clicks a second. A person clicks about 8, a mashed mouse about 12; the cap is set
-- above what a human hand can do on purpose, because a legitimate player who is refused a click
-- they actually made is a much worse outcome than an exploiter earning at 14/s instead of 1000/s.
local CLICK_INTERVAL = 0.07
local lastClick = {}   -- [userId] = os.clock()

-- ...and the REPLY is throttled separately. The click itself has to land immediately, but the
-- whole save does not have to cross the wire fourteen times a second to say so -- the leaderstat
-- is already live and the periodic sync below is three seconds away.
local PUSH_INTERVAL = 0.25
local lastPush = {}    -- [userId] = os.clock()

function DNAService.HandleClick(player)
	local data = PlayerDataService.Get(player)
	if not data then return end

	local now = os.clock()
	if lastClick[player.UserId] and now - lastClick[player.UserId] < CLICK_INTERVAL then
		return
	end
	lastClick[player.UserId] = now

	local amount, wasCrit = DNAService.GetClickAmount(data)
	data.DNA += amount
	PlayerDataService.UpdateLeaderstats(player)
	-- a crit pushes regardless: it fires a notification the client draws against this data
	if wasCrit or not lastPush[player.UserId] or now - lastPush[player.UserId] >= PUSH_INTERVAL then
		lastPush[player.UserId] = now
		PlayerDataService.PushToClient(player)
	end
	if wasCrit then
		Remotes.Notify:FireClient(player, { kind = "crit", amount = amount })
	end
end

function DNAService.HandleBuyUpgrade(player, upgradeKey)
	local data = PlayerDataService.Get(player)
	if not data then return end
	if not GameConfig.Upgrades[upgradeKey] then return end

	local level = data.Upgrades[upgradeKey]
	local cost = GameConfig.GetUpgradeCost(upgradeKey, level)
	if data.DNA >= cost then
		data.DNA -= cost
		data.Upgrades[upgradeKey] = level + 1
		-- Speed lives on the Humanoid, which is only written on spawn and on a Mastery purchase --
		-- so without this the upgrade a player just paid for does not arrive until they next die.
		if upgradeKey == "Speed" and DNAService.OnMasteryChanged then
			DNAService.OnMasteryChanged(player, data)
		end
		PlayerDataService.UpdateLeaderstats(player)
		PlayerDataService.PushToClient(player)
		Remotes.Notify:FireClient(player, { kind = "upgrade", upgrade = upgradeKey, level = level + 1 })
	else
		Remotes.Notify:FireClient(player, { kind = "error", message = "Not enough DNA!" })
	end
end

-- ===== THE CHARACTER JOURNAL ==================================================
-- Every stage has five characters (GameConfig.StageCharacters) and evolving INTO a stage rolls one
-- of them. They are skins: a character changes what the body is painted, never what it does, so
-- the twenty evolve steps stay the only thing that decides how strong a player is.
--
-- Rolled on every arrival at a stage, including after a Rebirth, which is what makes the hundred
-- fill in over repeat runs instead of being finished on the first pass.
--
-- A newly rolled character is worn immediately unless the player has already CHOSEN one for that
-- stage in the Journal. Overriding a deliberate choice with a random roll would mean a player who
-- had picked their favourite Wolf loses it every time they pass back through Wolf.
function DNAService.RollCharacter(player, data, stageIndex)
	data.Characters = data.Characters or {}
	-- IN ORDER, NOT AT RANDOM. Every arrival at a stage hands over the next character in that
	-- stage's list, so an evolve always visibly advances the collection. The old weighted roll
	-- could return a duplicate forever, which is what made the Journal read as a wall of padlocks.
	-- nil means this stage is already complete -- there is nothing left here to give.
	local rolled = GameConfig.NextCharacterForStage(data.Characters, stageIndex)
	if not rolled then return nil end

	-- NextCharacterForStage only ever returns something unowned, so this is always a first find
	local isNew = true
	data.Characters[rolled.key] = true
	-- ONE WORN CHARACTER, not one per stage -- see GameConfig.GetWornCharacter. A player with
	-- nothing on gets dressed in the first thing they find; after that the choice is theirs and a
	-- roll never overrides it, which was already the rule and is the reason this is guarded.
	if data.WornCharacter == nil then
		data.WornCharacter = rolled.key
	end

	-- No rarity in the payload any more. With unlocks in order there is nothing rare about the
	-- next one along, and "COMMON!" stamped on a reward reads as a disappointment for something
	-- the player just earned by evolving. What it does is the interesting fact, so that is what
	-- goes out.
	Remotes.Notify:FireClient(player, {
		kind = "character",
		key = rolled.key,   -- the client tints the reveal with the character's own colour
		name = rolled.name,
		emoji = rolled.emoji,
		-- What the rung is worth, as the damage it puts on the body rather than a percentage of a
		-- base nobody can see. The ladder is geometric now, so "+297%" was both unreadable and, once
		-- the rung stopped being a costume stat, untrue -- see GameConfig.GetProgressRank.
		damage = math.floor(GameConfig.GetRankDamage(GameConfig.GetCharacterRank(rolled))),
		isNew = isNew,
	})
	return rolled, isNew
end

-- WEARING ONE FROM THE JOURNAL. Any character you own, at any time, standing anywhere.
--
-- It used to be stored per stage and only took effect while you were standing at that stage, so
-- picking a Wolf while you were an Alien changed nothing you could see -- which is how it was
-- reported: "I selected it and my character didn't change". Ownership is the only gate now. The
-- cost of wearing something from further back is that it hits for less: damage comes from the
-- character's rank in the collection, not from the stage you happen to be at.
function DNAService.HandleEquipCharacter(player, key)
	local data = PlayerDataService.Get(player)
	if not data then return end
	local entry = GameConfig.GetCharacter(key)
	if not entry then return end
	if not (data.Characters and data.Characters[key]) then
		Remotes.Notify:FireClient(player, { kind = "error", message = "You haven't discovered that one yet!" })
		return
	end

	data.WornCharacter = key
	PlayerDataService.PushToClient(player)

	-- always, now: there is no such thing as a choice that does not show
	if DNAService.OnCharacterChanged then
		DNAService.OnCharacterChanged(player, data)
	end

	-- THERE IS NO LONGER A TRADE TO REPORT, AND THAT IS THE CHANGE. This used to append
	-- "(-150% damage, -50% health)" when you picked something from earlier in the collection,
	-- because the rung you WORE was the rung you fought at. With the ladder geometric that same
	-- choice would cost a factor of forty, which no cosmetic is worth -- so damage and health both
	-- read the best rung OWNED (GameConfig.GetProgressRank) and a costume is free.
	Remotes.Notify:FireClient(player, {
		kind = "reward",
		message = ("%s Now wearing %s!"):format(entry.emoji, entry.name),
		color = entry.color or GameConfig.GetRarity(entry.rarity).color,
	})
end

-- ===== EVOLVING IS THE ONLY WAY A SKIN IS EARNED, AND EVERY SKIN IS AN EVOLVE =====
--
-- One press = one character, handed over in collection order. Four presses in five change what the
-- body looks like; the fifth also changes what it IS -- stage, size, income curve and the zone that
-- opens with it. GameConfig.GetEvolveStep decides which of the two this press is and what it costs,
-- and MainUI reads the SAME function, so the button can never promise something this refuses.
--
-- The old shape was the reverse and it read as a wall: characters fell off creatures at 1 in 5 and
-- the evolve was blocked until all five of the stage had dropped, so the thing standing between the
-- player and the button was a dice roll rather than anything they were doing.
function DNAService.HandleEvolve(player)
	local data = PlayerDataService.Get(player)
	if not data then return end
	data.Characters = data.Characters or {}

	local step = GameConfig.GetEvolveStep(data)
	if step.isMax then
		Remotes.Notify:FireClient(player, { kind = "error", message = "You are at max evolution!" })
		return
	end

	-- ===== XP IS THE ONLY GATE, AND DNA IS NOT ASKED FOR AT ALL =====
	--
	-- An evolve used to cost BOTH, and two gates on one button is one gate too many: whichever ran
	-- out first was the real requirement and the other was noise, so the button could refuse for a
	-- reason the player was not watching. Worse, they pull in opposite directions -- DNA is *earned*
	-- by the same kills that pay XP AND by idle collection, so a player who stood still could unblock
	-- an evolve without fighting, which is the exact opposite of what the loop is meant to teach.
	--
	-- One currency, one sentence: **fight -> XP -> evolve -> stronger**. DNA keeps every other sink
	-- it already had (upgrades, eggs, potions, the zone shops), so it is still worth having; it is
	-- simply no longer able to stand between a player and the next rung.
	--
	-- The pacing does not change with it, because XP was already the binding half at every stage:
	-- `xpCost` is 50 * 1.55^(i-1) * (1 + (i-1)*0.06) and `zone.mobXpMult` is 1.55^(i-1), the SAME
	-- constant on purpose -- so kills per evolve stay roughly flat (about 25 Critters at stage 1 and
	-- 54 at stage 20, the drift being the ramp term) instead of exploding the way a cost curve
	-- without a matching income curve does. See the XP block in GameConfig.
	local xp = data.XP or 0
	if xp < step.xpCost then
		Remotes.Notify:FireClient(player, { kind = "error", message = string.format(
			"Not enough XP to evolve! (%d/%d) Fight creatures to earn XP.",
			math.floor(xp), math.floor(step.xpCost)) })
		return
	end

	-- XP IS SPENT, and that is the whole point of it: `xpCost` is what ONE level costs, not a
	-- lifetime total to reach, so the bar empties here and fills again for the next skin.
	-- Subtracted rather than zeroed so overkill carries forward -- a player who banked 90 XP
	-- against a 50 requirement keeps the 40, which is what stops the last kill before an evolve
	-- from being worth nothing.
	data.XP = math.max(0, xp - step.xpCost)

	if step.advancesStage then
		data.StageIndex = step.nextStageIndex
	end
	local newStage = GameConfig.Stages[data.StageIndex]

	local earned = step.entry
	if earned then
		data.Characters[earned.key] = true
		-- AND YOU PUT ON WHAT YOU JUST EARNED -- unless it would downgrade you. Rank is damage, and
		-- a player can be wearing something they picked in the Journal from further up the ladder;
		-- dressing them in a lower rank would make an evolve the thing that took damage away.
		local wornNow = GameConfig.GetWornCharacter(data)
		if not wornNow or GameConfig.GetCharacterRank(earned) > GameConfig.GetCharacterRank(wornNow) then
			data.WornCharacter = earned.key
		end
	end

	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.PushToClient(player)

	Remotes.Notify:FireClient(player, {
		kind = "evolve",
		stage = newStage.name,
		emoji = newStage.emoji,
		character = earned and earned.key or nil,
		-- WHICH OF THE TWO THIS PRESS WAS. The toast says different things for a new skin and a new
		-- stage, and only one of them has earned a stage banner.
		advanced = step.advancesStage,
		step = step.entryIndex,
		steps = step.entryTotal,
	})

	if step.advancesStage then
		if DNAService.OnEvolve then
			-- zone unlocks + the animated size change
			DNAService.OnEvolve(player, data)
		end
	elseif DNAService.OnCharacterChanged then
		-- A step INSIDE a stage changes the body without changing the stage, so nothing else in the
		-- game would rebuild the costume. Not the evolve callback: nothing is changing size here and
		-- a 0.6s scale tween on a skin swap reads as a second evolve.
		DNAService.OnCharacterChanged(player, data)
	end
end


-- ===== EVOLVING IS NO LONGER A BUTTON YOU HAVE TO FIND =====
--
-- The moment the XP bar fills, the evolve happens. The button stays -- it is how a player who is
-- watching makes it happen a beat sooner, and it is what the tutorial points at -- but nothing is
-- gated on pressing it any more.
--
-- WHY THIS IS CHECKED WHERE XP IS PAID, and not on a loop. XP enters a save in exactly two places
-- (a creature kill and a boss kill) and cannot arrive any other way -- there is no idle XP, no
-- offline XP, no XP purchase. So a poll would be a timer asking a question whose answer only ever
-- changes at two call sites, and would land the evolve up to a second late for no benefit. Called
-- from there, the reveal fires on the same frame as the kill that earned it.
--
-- IT LOOPS, and that matters on the first call of an old save: a player who banked XP before this
-- existed, or who is handed a large reward, can cover several rungs at once, and stopping after one
-- would leave them evolving once per kill for the next twenty kills. Bounded hard at 25 -- a
-- non-terminating condition here would hang the server inside a kill handler, and the bound is the
-- difference between "several rungs" and "a bug that eats the frame".
--
-- Each step goes through HandleEvolve, which is the whole point: the XP charge, the character
-- grant, the stage advance, the zone unlock, the costume rebuild and the reveal are all already
-- there and all still apply. An auto-evolve with its own copy of that would be a second
-- implementation of the most important transition in the game.
local AUTO_EVOLVE_MAX_STEPS = 25

function DNAService.AutoEvolveIfReady(player)
	local data = PlayerDataService.Get(player)
	if not data then return 0 end

	local steps = 0
	while steps < AUTO_EVOLVE_MAX_STEPS do
		local step = GameConfig.GetEvolveStep(data)
		-- max rank, or the bar is not full: nothing to do, and this is the common case by far
		if step.isMax or (data.XP or 0) < step.xpCost then break end
		DNAService.HandleEvolve(player)
		-- HandleEvolve refuses on its own terms too (max rank, not enough XP). If the save did not
		-- move, stopping is the only safe answer -- anything else is a loop that cannot end.
		local after = GameConfig.GetEvolveStep(data)
		if after.entry == step.entry and (data.XP or 0) >= step.xpCost then break end
		steps += 1
	end
	return steps
end

function DNAService.RollMutationForPlayer(player)
	local data = PlayerDataService.Get(player)
	if not data then return end
	local chance = DNAService.GetMutationChancePerRoll(data)
	if math.random(1, 1000) <= chance * 10 then
		local luck = DNAService.GetLuckPercent(data)
		local mutation = GameConfig.RollMutation(luck)
		table.insert(data.Mutations, mutation.name)
		PlayerDataService.PushToClient(player)
		-- No toast. Mutations roll every ten seconds on their own and the banner fired over and
		-- over during ordinary play; the multiplier they feed is already visible on the DNA
		-- readout, which is the place it actually matters.
	end
end

function DNAService.HandleBuyDiamondUpgrade(player, upgradeKey)
	local data = PlayerDataService.Get(player)
	if not data then return end
	local def = GameConfig.DiamondUpgrades[upgradeKey]
	if not def then return end

	local level = data.DiamondUpgrades[upgradeKey] or 0
	local cost = GameConfig.GetDiamondUpgradeCost(upgradeKey, level)
	if cost == math.huge then
		Remotes.Notify:FireClient(player, { kind = "error", message = def.displayName .. " is already maxed!" })
		return
	end
	if (data.Diamonds or 0) >= cost then
		data.Diamonds -= cost
		data.DiamondUpgrades[upgradeKey] = level + 1
		PlayerDataService.PushToClient(player)
		Remotes.Notify:FireClient(player, { kind = "diamondUpgrade", upgrade = upgradeKey, level = level + 1 })
	else
		Remotes.Notify:FireClient(player, { kind = "error", message = "Not enough Diamonds!" })
	end
end

-- Buys the one-shot Mastery for a stage the player has already reached. Guards, in order: the
-- stage must exist, must have been reached, must not already be owned, and must be affordable --
-- a client can fire this remote with any number it likes.
function DNAService.HandleBuyStageMastery(player, stageIndex)
	local data = PlayerDataService.Get(player)
	if not data then return end

	stageIndex = math.floor(tonumber(stageIndex) or 0)
	local stage = GameConfig.Stages[stageIndex]
	if not stage then return end

	if stageIndex > (data.StageIndex or 1) then
		Remotes.Notify:FireClient(player, { kind = "error", message = "Reach " .. stage.name .. " before mastering it!" })
		return
	end
	if GameConfig.HasStageMastery(data, stageIndex) then
		Remotes.Notify:FireClient(player, { kind = "error", message = stage.name .. " is already mastered!" })
		return
	end

	local cost = GameConfig.GetStageMasteryCost(stageIndex)
	if (data.Diamonds or 0) < cost then
		Remotes.Notify:FireClient(player, { kind = "error", message = "Not enough Diamonds!" })
		return
	end

	data.Diamonds -= cost
	data.MasteredStages = data.MasteredStages or {}
	table.insert(data.MasteredStages, stageIndex)

	-- walk speed and max health live on the Humanoid, so buying one has to be pushed onto the
	-- character immediately -- otherwise it only takes effect on the next respawn
	if DNAService.OnMasteryChanged then
		DNAService.OnMasteryChanged(player, data)
	end

	PlayerDataService.PushToClient(player)
	Remotes.Notify:FireClient(player, {
		kind = "stageMastery",
		stage = stage.name,
		emoji = stage.emoji,
		owned = #data.MasteredStages,
	})
end

function DNAService.Init()
	Remotes.CollectClick.OnServerEvent:Connect(function(player)
		DNAService.HandleClick(player)
	end)

	-- both tables are keyed by UserId and would otherwise hold an entry for every player who has
	-- ever been on this server
	game.Players.PlayerRemoving:Connect(function(player)
		lastClick[player.UserId] = nil
		lastPush[player.UserId] = nil
	end)

	Remotes.BuyStageMastery.OnServerEvent:Connect(function(player, stageIndex)
		if typeof(stageIndex) == "number" then
			DNAService.HandleBuyStageMastery(player, stageIndex)
		end
	end)

	Remotes.BuyUpgrade.OnServerEvent:Connect(function(player, upgradeKey)
		if typeof(upgradeKey) == "string" then
			DNAService.HandleBuyUpgrade(player, upgradeKey)
		end
	end)

	Remotes.BuyDiamondUpgrade.OnServerEvent:Connect(function(player, upgradeKey)
		if typeof(upgradeKey) == "string" then
			DNAService.HandleBuyDiamondUpgrade(player, upgradeKey)
		end
	end)

	Remotes.Evolve.OnServerEvent:Connect(function(player)
		DNAService.HandleEvolve(player)
	end)

	-- Created on demand for the same reason CombatFx is: the rest of the Remotes folder is saved
	-- instances, and a place that has never run this build would hard-error on the first Journal use.
	local equipCharacter = Remotes:FindFirstChild("EquipCharacter")
	if not equipCharacter then
		equipCharacter = Instance.new("RemoteEvent")
		equipCharacter.Name = "EquipCharacter"
		equipCharacter.Parent = Remotes
	end
	equipCharacter.OnServerEvent:Connect(function(player, key)
		if type(key) ~= "string" then return end
		DNAService.HandleEquipCharacter(player, key)
	end)

	-- Auto collect loop (every second)
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in ipairs(game.Players:GetPlayers()) do
				local data = PlayerDataService.Get(player)
				if data then
					local amt = DNAService.GetAutoCollectAmount(data)
					if amt > 0 then
						data.DNA += amt
						PlayerDataService.UpdateLeaderstats(player)
					end
				end
			end
		end
	end)

	-- Mutation roll loop (every ~10 seconds, decoupled from UI push spam)
	task.spawn(function()
		while true do
			task.wait(10)
			for _, player in ipairs(game.Players:GetPlayers()) do
				DNAService.RollMutationForPlayer(player)
			end
		end
	end)

	-- Periodic UI sync (every 3s) so passive DNA reflects in shop costs client-side
	task.spawn(function()
		while true do
			task.wait(3)
			for _, player in ipairs(game.Players:GetPlayers()) do
				PlayerDataService.PushToClient(player)
			end
		end
	end)
end

return DNAService
