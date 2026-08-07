local RS = game:GetService("ReplicatedStorage")
local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS.Remotes

local PlayerDataService = require(script.Parent.PlayerDataService)

local RewardService = {}
local SECONDS_PER_DAY = 86400

local function dayNumber(timestamp)
	return math.floor((timestamp or 0) / SECONDS_PER_DAY)
end

-- Returns whether the player can claim right now, and which day-index (1-7) they'd receive.
function RewardService.GetStatus(data)
	local today = dayNumber(os.time())
	local lastDay = dayNumber(data.LastRewardClaim)
	local canClaim = today > lastDay
	local streak = data.RewardStreak or 0
	local upcomingStreak = canClaim and (streak + (today == lastDay + 1 and 1 or 0)) or streak
	if canClaim and today > lastDay + 1 then
		upcomingStreak = 1 -- streak broken by a missed day
	end
	if upcomingStreak < 1 then upcomingStreak = 1 end
	local rewardIndex = ((upcomingStreak - 1) % #GameConfig.DailyRewards) + 1
	return canClaim, rewardIndex
end

function RewardService.HandleClaim(player)
	local data = PlayerDataService.Get(player)
	if not data then return end

	local today = dayNumber(os.time())
	local lastDay = dayNumber(data.LastRewardClaim)
	if today <= lastDay then
		Remotes.Notify:FireClient(player, { kind = "error", message = "Already claimed today's reward!" })
		return
	end

	if today == lastDay + 1 then
		data.RewardStreak = (data.RewardStreak or 0) + 1
	else
		data.RewardStreak = 1 -- missed a day, streak resets
	end

	local rewardIndex = ((data.RewardStreak - 1) % #GameConfig.DailyRewards) + 1
	local reward = GameConfig.DailyRewards[rewardIndex]

	-- scaled to where the player stands: a flat 23,000 is worth less than one kill from stage 6 on
	-- (see GameConfig.ScaleReward)
	data.DNA += GameConfig.ScaleReward(reward.dna, data)
	if reward.shards then
		data.EvolutionShards += reward.shards
	end
	if reward.potions then
		-- `potionId` names which of the nine the day gives; GameConfig.AddPotions falls back to the
		-- default bottle for a row that does not name one
		GameConfig.AddPotions(data, reward.potionId, reward.potions)
	end
	if reward.diamonds then
		data.Diamonds = (data.Diamonds or 0) + reward.diamonds
	end
	data.LastRewardClaim = os.time()

	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.PushToClient(player)
	Remotes.Notify:FireClient(player, {
		kind = "dailyReward",
		day = rewardIndex,
		dna = reward.dna,
		shards = reward.shards or 0,
		potions = reward.potions or 0,
		diamonds = reward.diamonds or 0,
		streak = data.RewardStreak,
	})
end

function RewardService.Init()
	Remotes.ClaimDailyReward.OnServerEvent:Connect(function(player)
		RewardService.HandleClaim(player)
	end)
end

return RewardService
