local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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

-- ============================================================================
-- GROUP & COMMUNITY REWARDS (Phase 5.5)
-- ============================================================================
function RewardService.CheckGroup(player, data)
	if not player then return false end
	data = data or PlayerDataService.Get(player)
	local inGroup = false
	if RunService:IsStudio() then
		inGroup = true
	elseif GameConfig.RobloxGroupId and GameConfig.RobloxGroupId > 0 then
		local ok, res = pcall(function()
			return player:IsInGroup(GameConfig.RobloxGroupId)
		end)
		if ok and res then inGroup = true end
	end
	if data then data.InGroup = inGroup end
	return inGroup
end

function RewardService.GetGroupStatus(player, data)
	data = data or PlayerDataService.Get(player)
	if not data then
		return { inGroup = false, chestReady = false, chestSeconds = 0, likeClaimed = false, favClaimed = false }
	end
	local inGroup = RewardService.CheckGroup(player, data)
	local now = os.time()
	local today = dayNumber(now)
	local lastClaim = dayNumber(data.ClaimedGroupChest or 0)
	local chestReady = inGroup and (today > lastClaim)
	local chestSeconds = (not chestReady and inGroup) and math.max((today + 1) * SECONDS_PER_DAY - now, 0) or 0
	return {
		inGroup = inGroup,
		chestReady = chestReady,
		chestSeconds = chestSeconds,
		likeClaimed = data.ClaimedLikeReward == true,
		favClaimed = data.ClaimedFavoriteReward == true,
	}
end

function RewardService.HandleClaimGroupChest(player)
	local data = PlayerDataService.Get(player)
	if not data then return "nodata" end

	local status = RewardService.GetGroupStatus(player, data)
	if not status.inGroup then
		Remotes.Notify:FireClient(player, { kind = "error", message = "Join our Roblox Group to open the Group Chest!" })
		return "not_in_group"
	end
	if not status.chestReady then
		Remotes.Notify:FireClient(player, { kind = "error", message = "Group Chest is not ready yet!" })
		return "not_ready"
	end

	data.ClaimedGroupChest = os.time()
	local dnaReward = GameConfig.ScaleReward(GameConfig.GroupChestReward.dna, data)
	data.DNA = (data.DNA or 0) + dnaReward
	data.Diamonds = (data.Diamonds or 0) + (GameConfig.GroupChestReward.diamonds or 25)
	GameConfig.AddPotions(data, GameConfig.GroupChestReward.potionId or "dna_m", GameConfig.GroupChestReward.potions or 1)

	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.PushToClient(player)
	Remotes.Notify:FireClient(player, {
		kind = "reward",
		message = ("🎁 Claimed Daily Group Chest! +%s DNA, 💎 +%d, 🧪 +%d Potion"):format(
			GameConfig.FormatNumber(dnaReward),
			GameConfig.GroupChestReward.diamonds or 25,
			GameConfig.GroupChestReward.potions or 1
		),
	})
	return "ok"
end

function RewardService.HandleClaimLikeReward(player)
	local data = PlayerDataService.Get(player)
	if not data then return "nodata" end

	if data.ClaimedLikeReward then
		Remotes.Notify:FireClient(player, { kind = "error", message = "You have already claimed your Like reward!" })
		return "already_claimed"
	end

	data.ClaimedLikeReward = true
	data.Diamonds = (data.Diamonds or 0) + (GameConfig.LikeReward.diamonds or 15)
	GameConfig.AddPotions(data, GameConfig.LikeReward.potionId or "luck_m", GameConfig.LikeReward.potions or 1)

	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.PushToClient(player)
	Remotes.Notify:FireClient(player, {
		kind = "reward",
		message = ("👍 Claimed Like Reward! 💎 +%d Diamonds, 🧪 +%d Luck Potion"):format(
			GameConfig.LikeReward.diamonds or 15,
			GameConfig.LikeReward.potions or 1
		),
	})
	return "ok"
end

function RewardService.HandleClaimFavoriteReward(player)
	local data = PlayerDataService.Get(player)
	if not data then return "nodata" end

	if data.ClaimedFavoriteReward then
		Remotes.Notify:FireClient(player, { kind = "error", message = "You have already claimed your Favorite reward!" })
		return "already_claimed"
	end

	data.ClaimedFavoriteReward = true
	data.Diamonds = (data.Diamonds or 0) + (GameConfig.FavoriteReward.diamonds or 15)
	data.EvolutionShards = (data.EvolutionShards or 0) + (GameConfig.FavoriteReward.shards or 2)

	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.PushToClient(player)
	Remotes.Notify:FireClient(player, {
		kind = "reward",
		message = ("⭐ Claimed Favorite Reward! 💎 +%d Diamonds, 🌟 +%d Shards"):format(
			GameConfig.FavoriteReward.diamonds or 15,
			GameConfig.FavoriteReward.shards or 2
		),
	})
	return "ok"
end

local function buildChestModel()
	local existing = workspace:FindFirstChild("GroupChest")
	if existing then existing:Destroy() end

	local model = Instance.new("Model")
	model.Name = "GroupChest"

	local basePos = Vector3.new(48, 1.04, 335)

	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(4, 2.2, 3)
	base.CFrame = CFrame.new(basePos + Vector3.new(0, 1.1, 0))
	base.Material = Enum.Material.WoodPlanks
	base.Color = Color3.fromRGB(110, 68, 38)
	base.Anchored = true
	base.CanCollide = true
	base.Parent = model

	local trim = Instance.new("Part")
	trim.Name = "Trim"
	trim.Size = Vector3.new(4.2, 0.4, 3.2)
	trim.CFrame = CFrame.new(basePos + Vector3.new(0, 2.3, 0))
	trim.Material = Enum.Material.Metal
	trim.Color = Color3.fromRGB(245, 195, 45)
	trim.Anchored = true
	trim.CanCollide = true
	trim.Parent = model

	local lid = Instance.new("Part")
	lid.Name = "Lid"
	lid.Size = Vector3.new(4.1, 1.2, 3.1)
	lid.CFrame = CFrame.new(basePos + Vector3.new(0, 3.0, 0))
	lid.Material = Enum.Material.WoodPlanks
	lid.Color = Color3.fromRGB(130, 78, 44)
	lid.Anchored = true
	lid.CanCollide = true
	lid.Parent = model

	local lock = Instance.new("Part")
	lock.Name = "Lock"
	lock.Size = Vector3.new(0.8, 1.0, 0.4)
	lock.CFrame = CFrame.new(basePos + Vector3.new(0, 2.2, 1.6))
	lock.Material = Enum.Material.Neon
	lock.Color = Color3.fromRGB(255, 215, 60)
	lock.Anchored = true
	lock.CanCollide = false
	lock.Parent = model

	-- Prompt & Billboard
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ChestPrompt"
	prompt.ActionText = "Group Rewards"
	prompt.ObjectText = "Group Chest"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 15
	prompt.RequiresLineOfSight = false
	prompt.Parent = base

	prompt.Triggered:Connect(function(player)
		local openRemote = Remotes:FindFirstChild("OpenGroupRewards")
		if openRemote then
			openRemote:FireClient(player)
		end
	end)

	local bb = Instance.new("BillboardGui")
	bb.Name = "ChestLabel"
	bb.Size = UDim2.new(0, 220, 0, 60)
	bb.StudsOffset = Vector3.new(0, 3.2, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 60
	bb.Parent = base

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0.55, 0)
	title.Font = Enum.Font.FredokaOne
	title.Text = "👥 GROUP REWARDS"
	title.TextColor3 = Color3.fromRGB(255, 220, 70)
	title.TextScaled = true
	title.Parent = bb

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.fromRGB(20, 20, 30)
	stroke.Parent = title

	local sub = Instance.new("TextLabel")
	sub.Name = "Subtitle"
	sub.BackgroundTransparency = 1
	sub.Size = UDim2.new(1, 0, 0.45, 0)
	sub.Position = UDim2.new(0, 0, 0.55, 0)
	sub.Font = Enum.Font.FredokaOne
	sub.Text = "+10% DNA & Daily Chest"
	sub.TextColor3 = Color3.fromRGB(255, 255, 255)
	sub.TextScaled = true
	sub.Parent = bb

	local subStroke = Instance.new("UIStroke")
	subStroke.Thickness = 2
	subStroke.Color = Color3.fromRGB(20, 20, 30)
	subStroke.Parent = sub

	model.PrimaryPart = base
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)
	model.Parent = workspace
	return model
end

local function ensureRemote(name, class)
	class = class or "RemoteEvent"
	local r = Remotes:FindFirstChild(name)
	if not r then
		r = Instance.new(class)
		r.Name = name
		r.Parent = Remotes
	end
	return r
end

function RewardService.Init()
	Remotes.ClaimDailyReward.OnServerEvent:Connect(function(player)
		RewardService.HandleClaim(player)
	end)

	local freeSpin = ensureRemote("ClaimFreeSpin")
	freeSpin.OnServerEvent:Connect(function(player)
		RewardService.HandleFreeSpin(player)
	end)

	local claimGroup = ensureRemote("ClaimGroupChest")
	claimGroup.OnServerEvent:Connect(function(player)
		RewardService.HandleClaimGroupChest(player)
	end)

	local claimLike = ensureRemote("ClaimLikeReward")
	claimLike.OnServerEvent:Connect(function(player)
		RewardService.HandleClaimLikeReward(player)
	end)

	local claimFav = ensureRemote("ClaimFavoriteReward")
	claimFav.OnServerEvent:Connect(function(player)
		RewardService.HandleClaimFavoriteReward(player)
	end)

	ensureRemote("OpenGroupRewards")

	buildChestModel()
end

return RewardService
