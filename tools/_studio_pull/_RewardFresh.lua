local RS = game:GetService("ReplicatedStorage")
local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS.Remotes

local PlayerDataService = require(script.Parent.PlayerDataService)
-- for the free daily spin only. No cycle: RobuxShopService reaches PlayerDataService, SeasonPass
-- Service and DNAService, and none of those reaches back here.
local RobuxShopService = require(script.Parent.RobuxShopService)

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

-- ===== THE FREE DAILY SPIN (Phase 5.6) =====
--
-- Revenue from players who never buy, and it costs nothing to build because Phase 3 already made
-- `RobuxShopService.GrantSpin` public for exactly this. That matters for more than tidiness: the
-- wheel is bent by the spinner's own luck, its weights are normalised by segment count, and its
-- expected value was deliberately set below the flat 99 R$ DNA pack. A second copy of that here
-- would be a second thing to keep balanced, and it would drift the first time either was touched.
--
-- Same day boundary as the login reward above -- `dayNumber` on the UTC clock -- so a player has
-- one free spin and one login reward per day and both roll over together, rather than the game
-- keeping two different ideas of when tomorrow starts.

-- Returns (isReady, secondsUntilReady). The countdown is to the next day boundary rather than 24h
-- from the last spin, which is what makes "tomorrow" mean the same thing to everyone.
function RewardService.GetFreeSpinStatus(data)
	local now = os.time()
	local today = dayNumber(now)
	local ready = today > dayNumber(data and data.LastFreeSpin)
	if ready then return true, 0 end
	return false, math.max((today + 1) * SECONDS_PER_DAY - now, 0)
end

-- Returns a status string, so this is testable without a mouse -- see CodesService for the same
-- reasoning.
function RewardService.HandleFreeSpin(player)
	local data = PlayerDataService.Get(player)
	if not data then return "nodata" end

	if not RewardService.GetFreeSpinStatus(data) then
		Remotes.Notify:FireClient(player, { kind = "error", message = "Your free spin isn't ready yet!" })
		return "notready"
	end

	-- STAMPED BEFORE THE GRANT, and nothing between them yields -- the same rule the code redemption
	-- follows. GrantSpin rolls, pays, pushes and notifies; if the stamp came after it, two clicks on
	-- consecutive frames would both find the spin ready.
	data.LastFreeSpin = os.time()
	RobuxShopService.GrantSpin(player)
	return "ok"
end

function RewardService.Init()
	Remotes.ClaimDailyReward.OnServerEvent:Connect(function(player)
		RewardService.HandleClaim(player)
	end)

	-- created on demand, like every remote added since the place was last saved by hand
	local freeSpin = Remotes:FindFirstChild("ClaimFreeSpin")
	if not freeSpin then
		freeSpin = Instance.new("RemoteEvent")
		freeSpin.Name = "ClaimFreeSpin"
		freeSpin.Parent = Remotes
	end
	freeSpin.OnServerEvent:Connect(function(player)
		RewardService.HandleFreeSpin(player)
	end)
end

return RewardService
