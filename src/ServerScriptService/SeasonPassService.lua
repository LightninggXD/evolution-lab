--[[
	SeasonPassService -- the thirty-level pass and the daily/weekly quest board that feeds it.

	THE ONE SOURCE OF SEASON XP IS A CLAIMED QUEST. Nothing grants it passively, so the pass can
	never be finished by idling, and a player who does the board every day lands on level 30 on the
	last day of the season (see the arithmetic in GameConfig.QuestPool).

	Three design notes worth keeping:

	* EVERY RESET IS LAZY. There is no scheduled job and no timer. Which period a moment belongs to
	  is `floor(now / seconds)`, so the first read of a stale period wipes it and moves on -- which
	  means a reset cannot be missed by an offline player, cannot double-fire across two servers,
	  and survives the process being restarted at any point. Same trick for the season itself,
	  keyed off GameConfig.Season.id.

	* TRACKING NEVER PUSHES. Track() mutates the save and returns. Every call site (a creature
	  dying, an egg hatching, a boss falling) already calls PlayerDataService.PushToClient a line
	  or two later, so progress rides along for free. Pushing here would have doubled the traffic
	  of the single most frequent event in the game -- a creature kill at auto-attack speed.
	  The one exception is a quest CROSSING its target, which pushes so the Claim button lights up
	  the moment it is earned rather than on the next kill.

	* CLAIM KEYS ARE STRINGS. `claimedFree["7"]`, never `claimedFree[7]`. A table whose keys are a
	  handful of scattered integers is a sparse array, and Roblox silently drops those crossing a
	  RemoteEvent -- the same failure that once ate EquippedCharacters (see DNAService.RollCharacter).
	  Both claim sets and both progress tables go through tostring() on every read and write.
]]

local RS = game:GetService("ReplicatedStorage")
local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS.Remotes

local PlayerDataService = require(script.Parent.PlayerDataService)
local Telemetry = require(script.Parent.Telemetry)

local SeasonPassService = {}

-- Remotes newer than the authored Remotes folder are created rather than assumed, so the script
-- and the place stay in step without a by-hand Studio step. Same helper as PetService.
local function ensureRemote(name)
	local r = Remotes:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = Remotes
	end
	return r
end

-- ===== SHAPE + LAZY RESETS =====

local function freshSeason()
	return {
		-- DERIVED FROM THE CLOCK now (7.3), not an authored constant. Nothing else in this file
		-- changed to get seasonal rotation: the lazy reset below was already comparing the save's id
		-- against "the current one", and the only thing that was static was the answer.
		id = GameConfig.GetCurrentSeason().id,
		xp = 0,
		premium = false,
		claimedFree = {},
		claimedPremium = {},
	}
end

local function freshPeriod(period)
	return {
		periodId = GameConfig.GetQuestPeriodId(period),
		progress = {},
		claimed = {},
		-- Season XP already handed over per quest. Only HandleClaimQuest writes it now (Track pays
		-- nothing), so a live period fills in one step per claim -- but it is still built here
		-- rather than lazily, because the claim path reads it before it writes it.
		paid = {},
	}
end

-- Call before ANY read of data.Season. Returns the table, having reset it first if the season
-- turned over while this player was away.
function SeasonPassService.GetSeason(data)
	if type(data.Season) ~= "table" or data.Season.id ~= GameConfig.GetCurrentSeason().id then
		data.Season = freshSeason()
	else
		-- a save written by an older build can be missing a sub-table the rest of this file indexes
		data.Season.claimedFree = data.Season.claimedFree or {}
		data.Season.claimedPremium = data.Season.claimedPremium or {}
		data.Season.xp = data.Season.xp or 0
	end
	return data.Season
end

-- Same contract for one quest period. The PREMIUM FLAG DELIBERATELY SURVIVES a period reset but
-- not a season reset: a pass is bought for a season, and the quest board is just this day's work.
function SeasonPassService.GetQuestPeriod(data, period)
	if type(data.Quests) ~= "table" then
		data.Quests = {}
	end
	local held = data.Quests[period]
	if type(held) ~= "table" or held.periodId ~= GameConfig.GetQuestPeriodId(period) then
		held = freshPeriod(period)
		data.Quests[period] = held
	else
		held.progress = held.progress or {}
		held.claimed = held.claimed or {}
		-- how much of each quest's XP has already been handed over. A save carried across the
		-- pro-rata experiment can have a part-paid quest in here; the claim settles the shortfall.
		held.paid = held.paid or {}
	end
	return held
end

-- ===== REWARD PAYOUT =====
-- One shape for season rewards and quest rewards both, so a new payout field is added in one
-- place. Mirrors what RewardService grants for the daily board.
--
-- EXPORTED SINCE 26.1, and the export is the point rather than a convenience: the event ladder pays
-- the same reward shape from EventService, and a second implementation of "what a reward table
-- means" is exactly how one board learns to scale DNA to the player's stage and the other quietly
-- forgets to. `grant` just below is an alias for it, kept because the two call sites in this file
-- read better with the short name.
-- `player` IS NOT OPTIONAL AND EVERY CALLER PASSES IT (20.2). It is third only because `data` is
-- what the function actually works on and moving it would have rewritten every line below. It is
-- here because a reward payout is a faucet, and a faucet with no player attached is a row the
-- dashboard cannot attribute to anybody -- so it would silently not be logged at all.
function SeasonPassService.GrantReward(data, reward, player)
	if not reward then return end
	if reward.dna then
		-- scaled to the player's stage -- see GameConfig.ScaleReward. The season track had this
		-- problem at BOTH ends: its first levels handed a brand-new player one or two whole stages
		-- outright, and its level-30 payout was 0.003 of a single kill by the time anyone got there.
		local paid = GameConfig.ScaleReward(reward.dna, data)
		data.DNA += paid
		Telemetry.Economy(player, "Source", Telemetry.Currency.DNA, paid, data.DNA,
			Telemetry.Tx.TimedReward, "seasonPass")
	end
	if reward.potions then
		GameConfig.AddPotions(data, reward.potionId, reward.potions)
	end
	if reward.diamonds then
		data.Diamonds = (data.Diamonds or 0) + reward.diamonds
		Telemetry.Economy(player, "Source", Telemetry.Currency.Diamonds, reward.diamonds,
			data.Diamonds, Telemetry.Tx.TimedReward, "seasonPass")
	end
	if reward.shards then
		data.EvolutionShards = (data.EvolutionShards or 0) + reward.shards
		Telemetry.Economy(player, "Source", Telemetry.Currency.Shards, reward.shards,
			data.EvolutionShards, Telemetry.Tx.TimedReward, "seasonPass")
	end
end
local grant = SeasonPassService.GrantReward

-- Human-readable line for the toast, built from whatever the reward actually contained.
-- Season DNA reaches the trillions once ScaleReward is applied, and this file has no formatter of
-- its own -- MainUI's is a local in a LocalScript and unreachable from here.
local REWARD_SUFFIX = { "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp" }
local function shortNumber(n)
	n = math.floor(n or 0)
	if n < 1000 then return tostring(n) end
	local mag = 0
	while n >= 1000 and mag < #REWARD_SUFFIX do
		n = n / 1000
		mag += 1
	end
	-- THE ROUNDING CARRIES past the loop, which has already stopped looking: 999,999 divides once to
	-- 999.999, is accepted, and "%.2f" prints "1000.00K" for a number one short of a million. 999.995
	-- and not 999.95 because this prints TWO decimals -- the constant has to match the precision it
	-- guards, or it fires a place too early.
	if n >= 999.995 and mag < #REWARD_SUFFIX then
		n = n / 1000
		mag += 1
	end
	return string.format("%.2f%s", n, REWARD_SUFFIX[mag])
end

-- `data` so the DNA line quotes what was actually paid rather than the authored figure -- a toast
-- saying "+103,000 DNA" after crediting 5.4e10 is a worse readout than no toast at all.
-- Exported alongside GrantReward and for the same reason -- the event ladder's toast has to read
-- the same as a season quest's, and the DNA line has to quote what was actually paid.
function SeasonPassService.RewardText(reward, data)
	local bits = {}
	if reward.dna then
		table.insert(bits, ("+%s DNA"):format(shortNumber(GameConfig.ScaleReward(reward.dna, data))))
	end
	if reward.potions then
		local potion = reward.potionId and GameConfig.GetPotion(reward.potionId)
		table.insert(bits, ("+%d %s"):format(reward.potions, potion and potion.emoji or "\u{1F9EA}"))
	end
	if reward.diamonds then table.insert(bits, ("+%d \u{1F48E}"):format(reward.diamonds)) end
	if reward.shards then table.insert(bits, ("+%d \u{2728} Shards"):format(reward.shards)) end
	if reward.xp then table.insert(bits, ("+%d Season XP"):format(reward.xp)) end
	return table.concat(bits, "  ")
end
local rewardText = SeasonPassService.RewardText

-- ===== PROGRESS =====

-- Called by the gameplay services when something countable happens. `counter` is one of the
-- names in GameConfig.QuestPool ('creatures', 'bosses', 'eggs', 'fuse', 'evolve').
--
-- Cheap on purpose: this runs on every creature kill in the game. It touches two small tables
-- and returns without replicating anything unless a quest actually finished on this call.
function SeasonPassService.Track(player, counter, amount)
	local data = PlayerDataService.Get(player)
	if not data then return end
	amount = amount or 1

	-- NO SEASON XP IS PAID HERE. Progress alone moves nothing on the level bar -- the XP lands in
	-- one lump when the Claim button is pressed (HandleClaimQuest), which is the rule this file's
	-- header states and the one the panel is drawn for.
	--
	-- It WAS paid pro rata for a while, so that the bar moved while the work was being done. That
	-- made the claim itself pay nothing, and a Claim button that visibly does nothing reads worse
	-- than a bar that waits. `held.paid` survives that experiment and still matters: a save written
	-- under the old rule carries a part-paid quest, and the claim settles only the SHORTFALL so
	-- nobody is paid twice for the same quest.
	local completedAny = false

	for period in pairs(GameConfig.QuestPeriods) do
		local held = SeasonPassService.GetQuestPeriod(data, period)
		for _, quest in ipairs(GameConfig.GetQuests(period)) do
			if quest.counter == counter then
				local before = held.progress[quest.key] or 0
				if before < quest.target then
					local after = math.min(before + amount, quest.target)
					held.progress[quest.key] = after

					if after >= quest.target then
						completedAny = true
						Remotes.Notify:FireClient(player, {
							kind = "questComplete",
							emoji = quest.emoji,
							name = quest.name,
							period = period,
						})
					end
				end
			end
		end
	end

	-- THE EVENT LADDER RIDES THE SAME CALL (26.1), AND THAT IS THE WHOLE INTEGRATION.
	--
	-- Four counters, five call sites, one place that knows about all of them -- so the event board
	-- gained no hook into combat, hatching or fusion, and a sixth way to kill something will feed
	-- both boards or neither. The alternative was a second Track with its own call sites, which is
	-- the arrangement where one board silently stops counting and nobody finds out for a weekend.
	--
	-- AdvanceEventQuests is pure over the save and the clock: it advances only LIVE events, grants
	-- nothing and replicates nothing, and hands back whatever crossed its target on this call. Off
	-- a weekend it walks an empty active-event list and returns a shared frozen table, which is
	-- what keeps it honest on the creature-kill path.
	for _, done in ipairs(GameConfig.AdvanceEventQuests(data, counter, amount)) do
		completedAny = true
		Remotes.Notify:FireClient(player, {
			kind = "questComplete",
			-- the EVENT's emoji rather than the rung's, so a ladder step cannot be mistaken for the
			-- daily quest that was very likely counting the same kill
			emoji = done.event.emoji,
			name = done.quest.name,
			period = "event",
			eventKey = done.event.key,
		})
	end

	-- ONLY A COMPLETION PUSHES. This runs on every creature kill in the game, so ordinary progress
	-- rides the caller's own replication -- every Track call site already pushes a line or two
	-- later. A quest CROSSING its target pushes here so the Claim button lights up on the kill that
	-- earned it rather than on the next one.
	if completedAny then
		PlayerDataService.PushToClient(player)
	end
end

-- ===== CLAIMS =====

function SeasonPassService.HandleClaimQuest(player, period, questKey)
	local data = PlayerDataService.Get(player)
	if not data then return end
	if not GameConfig.QuestPeriods[period] then return end

	local quest = GameConfig.GetQuestDef(period, questKey)
	if not quest then return end

	local held = SeasonPassService.GetQuestPeriod(data, period)
	if held.claimed[questKey] then
		Remotes.Notify:FireClient(player, { kind = "error", message = "Already claimed that quest!" })
		return
	end
	if (held.progress[questKey] or 0) < quest.target then
		Remotes.Notify:FireClient(player, { kind = "error", message = "That quest isn't finished yet!" })
		return
	end

	held.claimed[questKey] = true

	-- THE SEASON XP IS PAID HERE AND NOWHERE ELSE -- see Track, which pays none. The bar moves on
	-- the button press, which is the point of the button.
	--
	-- Settled as a SHORTFALL rather than a flat `season.xp += quest.xp`, and that is not
	-- bookkeeping for its own sake: a save written while Track was paying pro rata carries a
	-- part-paid quest in `held.paid`, and a flat add would hand that player the same XP twice.
	local season = SeasonPassService.GetSeason(data)
	local ceiling = GameConfig.Season.maxLevel * GameConfig.Season.xpPerLevel
	local owed = (quest.xp or 0) - (held.paid[questKey] or 0)
	if owed > 0 then
		held.paid[questKey] = quest.xp
		season.xp = math.min(season.xp + owed, ceiling)
	end

	grant(data, quest, player)

	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.PushToClient(player)
	Remotes.Notify:FireClient(player, {
		kind = "reward",
		message = ("%s %s\n%s"):format(quest.emoji, quest.name, rewardText(quest, data)),
	})
end

-- `track` is "free" or "premium". A premium claim needs the pass; everything else is the same
-- check on both rows, which is why they share one handler.
function SeasonPassService.HandleClaimSeasonReward(player, level, track)
	local data = PlayerDataService.Get(player)
	if not data then return end
	if track ~= "free" and track ~= "premium" then return end

	level = math.floor(tonumber(level) or 0)
	local row = GameConfig.GetSeasonReward(level)
	if not row then return end

	local season = SeasonPassService.GetSeason(data)
	if GameConfig.GetSeasonLevel(season.xp) < level then
		Remotes.Notify:FireClient(player, { kind = "error", message = "Reach level " .. level .. " first!" })
		return
	end
	if track == "premium" and not season.premium then
		Remotes.Notify:FireClient(player, { kind = "error", message = "That reward needs the Premium pass!" })
		return
	end

	-- STRING key -- see the header
	local slot = tostring(level)
	local claimedSet = (track == "premium") and season.claimedPremium or season.claimedFree
	if claimedSet[slot] then
		Remotes.Notify:FireClient(player, { kind = "error", message = "Already claimed!" })
		return
	end
	claimedSet[slot] = true

	local reward = (track == "premium") and row.premium or row.free
	grant(data, reward, player)

	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.PushToClient(player)
	Remotes.Notify:FireClient(player, {
		kind = "reward",
		message = ("%s Level %d %s reward\n%s"):format(GameConfig.GetCurrentSeason().emoji, level,
			(track == "premium") and "Premium" or "Free", rewardText(reward, data)),
	})
end

-- Called from RobuxShopService's ProcessReceipt -- the only place a real payment is confirmed.
-- Everything already earned stays claimable, so buying at level 12 does not forfeit twelve levels
-- of premium rewards; they simply become available all at once.
function SeasonPassService.GrantPremium(player)
	local data = PlayerDataService.Get(player)
	if not data then return false end
	local season = SeasonPassService.GetSeason(data)
	if season.premium then return false end
	season.premium = true
	PlayerDataService.PushToClient(player)
	Remotes.Notify:FireClient(player, {
		kind = "reward",
		message = ("%s PREMIUM PASS UNLOCKED!\nEvery premium reward you have already reached is ready to claim.")
			:format(GameConfig.GetCurrentSeason().emoji),
	})
	return true
end

function SeasonPassService.Init()
	ensureRemote("ClaimQuest").OnServerEvent:Connect(function(player, period, questKey)
		if typeof(period) == "string" and typeof(questKey) == "string" then
			SeasonPassService.HandleClaimQuest(player, period, questKey)
		end
	end)

	ensureRemote("ClaimSeasonReward").OnServerEvent:Connect(function(player, level, track)
		if typeof(level) == "number" and typeof(track) == "string" then
			SeasonPassService.HandleClaimSeasonReward(player, level, track)
		end
	end)
end

return SeasonPassService
