local MessagingService = game:GetService("MessagingService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local PlayerDataService = require(ServerScriptService.PlayerDataService)
local Telemetry = require(ServerScriptService.Telemetry)

local goalDataStore = DataStoreService:GetDataStore("CommunityGoalStore")

local CommunityGoalService = {}

local SYNC_INTERVAL = 30
local TOPIC = "CommunityGoal_Kills"

local currentWindowStart = nil
local localDelta = 0
local globalTotal = 0
local targetGoal = 5000000

local progressValue = Instance.new("NumberValue")
progressValue.Name = "GlobalKillsProgress"
progressValue.Parent = ReplicatedStorage

local isPaidOutThisWindow = false

local function getLiveGoal()
	local now = GameConfig.EventNow()
	local active = GameConfig.GetActiveEvents(now)
	for _, a in ipairs(active) do
		if a.event.key == "GlobalGoal" then
			return a
		end
	end
	return nil
end

local function onGlobalUpdate(message)
	local data = message.Data
	if data.jobId == game.JobId then return end
	if data.window == currentWindowStart and type(data.delta) == "number" then
		globalTotal = globalTotal + data.delta
		progressValue.Value = globalTotal
		
		if globalTotal >= targetGoal and not isPaidOutThisWindow then
			isPaidOutThisWindow = true
			CommunityGoalService.PayoutAll()
		end
	end
end

function CommunityGoalService.Init()
	-- Load initial state
	local live = getLiveGoal()
	if live then
		currentWindowStart = live.window.startTs
		targetGoal = live.event.target or 5000000
		
		local key = "GlobalGoal_" .. currentWindowStart
		local success, val = pcall(function()
			return goalDataStore:GetAsync(key)
		end)
		if success and type(val) == "number" then
			globalTotal = val
			progressValue.Value = globalTotal
			if globalTotal >= targetGoal then
				isPaidOutThisWindow = true
			end
		end
	end
	
	-- Subscribe to updates
	pcall(function()
		MessagingService:SubscribeAsync(TOPIC, onGlobalUpdate)
	end)
	
	-- Listen for local kills (Assume bindable or just poll a metric if we can't hook easily)
	-- The best way is to expose a function that StatsService or ZoneService calls, 
	-- or just wait for Remotes.NotifyKills if any. Let's create an AddKills method.
	
	-- Sync loop
	task.spawn(function()
		while true do
			task.wait(SYNC_INTERVAL)
			local live = getLiveGoal()
			if not live then
				currentWindowStart = nil
				localDelta = 0
				continue
			end
			
			if live.window.startTs ~= currentWindowStart then
				currentWindowStart = live.window.startTs
				targetGoal = live.event.target or 5000000
				localDelta = 0
				globalTotal = 0
				isPaidOutThisWindow = false
				progressValue.Value = 0
			end
			
			if localDelta > 0 then
				local deltaToSync = localDelta
				localDelta = 0
				
				local key = "GlobalGoal_" .. currentWindowStart
				local success, newTotal = pcall(function()
					return goalDataStore:UpdateAsync(key, function(oldValue)
						return (oldValue or 0) + deltaToSync
					end)
				end)
				
				if success then
					pcall(function()
						MessagingService:PublishAsync(TOPIC, {
							window = currentWindowStart,
							delta = deltaToSync,
							jobId = game.JobId
						})
					end)
					-- Update local approximation with authoritative total
					if newTotal > globalTotal then
						globalTotal = newTotal
						progressValue.Value = globalTotal
					end
					
					if globalTotal >= targetGoal and not isPaidOutThisWindow then
						isPaidOutThisWindow = true
						CommunityGoalService.PayoutAll()
					end
				else
					-- Restore local delta if sync failed
					localDelta = localDelta + deltaToSync
				end
			end
		end
	end)
	-- When a player joins, pay them if the goal is already met and they haven't claimed it yet
	local function onPlayerAdded(player)
		task.spawn(function()
			local data = nil
			local tries = 0
			repeat
				task.wait(0.5)
				tries = tries + 1
				if not player.Parent then return end
				data = PlayerDataService.Get(player)
			until data or tries > 20
			
			if not data then
				warn(("[CommunityGoalService] join payout gave up waiting for data for %s"):format(player.Name))
				return
			end
			
			if not isPaidOutThisWindow then return end
			local live = getLiveGoal()
			if not live then return end
			
			data.GlobalGoalsClaimed = data.GlobalGoalsClaimed or {}
			local windowKey = tostring(currentWindowStart)
			if not data.GlobalGoalsClaimed[windowKey] then
				local reward = live.event.reward
				data.GlobalGoalsClaimed[windowKey] = true
				if reward.diamonds then
					data.Diamonds = (data.Diamonds or 0) + reward.diamonds
					Telemetry.Economy(player, "Source", Telemetry.Currency.Diamonds, reward.diamonds,
						data.Diamonds, Telemetry.Tx.EventReward, "GlobalGoal")
				end
				PlayerDataService.PushToClient(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayerAdded(p)
	end
end

function CommunityGoalService.AddProgress(amount)
	if not currentWindowStart then return end
	if isPaidOutThisWindow then return end
	localDelta = localDelta + amount
end

function CommunityGoalService.PayoutAll()
	local live = getLiveGoal()
	if not live then return end
	
	local reward = live.event.reward
	if not reward then return end
	
	for _, player in ipairs(Players:GetPlayers()) do
		local data = PlayerDataService.Get(player)
		if data then
			data.GlobalGoalsClaimed = data.GlobalGoalsClaimed or {}
			local windowKey = tostring(currentWindowStart)
			
			if not data.GlobalGoalsClaimed[windowKey] then
				data.GlobalGoalsClaimed[windowKey] = true
				if reward.diamonds then
					data.Diamonds = (data.Diamonds or 0) + reward.diamonds
					Telemetry.Economy(player, "Source", Telemetry.Currency.Diamonds, reward.diamonds,
						data.Diamonds, Telemetry.Tx.EventReward, "GlobalGoal")
				end
				PlayerDataService.PushToClient(player)
			end
		end
	end
end



return CommunityGoalService