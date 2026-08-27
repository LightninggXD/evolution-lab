local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Achievements = require(ReplicatedStorage.Modules.GameConfig.Achievements)
local Telemetry = require(ServerScriptService.Telemetry)
local PlayerDataService = require(ServerScriptService.PlayerDataService)
local Remotes = ReplicatedStorage.Remotes

local AchievementService = {}

function AchievementService.HandleClaim(player, achievementKey)
	local data = PlayerDataService.Get(player)
	if not data then return false end

	-- Find the achievement config
	local config = nil
	for _, ach in ipairs(Achievements) do
		if ach.key == achievementKey then
			config = ach
			break
		end
	end

	if not config then return false end
	
	-- Verify not already claimed
	data.AchievementsClaimed = data.AchievementsClaimed or {}
	if data.AchievementsClaimed[achievementKey] then return false end

	-- Verify requirement is met
	local currentValue = data[config.counter] or 0
	if currentValue < config.goal then return false end

	-- Mark claimed
	data.AchievementsClaimed[achievementKey] = true

	-- Give reward
	if config.reward.dna then
		data.DNA = (data.DNA or 0) + config.reward.dna
		Telemetry.Economy(player, "Source", Telemetry.Currency.DNA, config.reward.dna, data.DNA, Telemetry.Tx.Gameplay, "Achievement")
	end
	if config.reward.diamonds then
		data.Diamonds = (data.Diamonds or 0) + config.reward.diamonds
		Telemetry.Economy(player, "Source", Telemetry.Currency.Diamonds, config.reward.diamonds, data.Diamonds, Telemetry.Tx.Gameplay, "Achievement")
	end
	
	-- Note: Titles are not "given" to an inventory, they are simply unlocked by the claim
	-- Clients will know they have the title if the achievement is in AchievementsClaimed

	PlayerDataService.PushToClient(player)
	return true
end

function AchievementService.HandleEquipTitle(player, titleKey)
	local data = PlayerDataService.Get(player)
	if not data then return false end

	-- Verify they own the title
	local ownsTitle = false
	if titleKey == "" or titleKey == nil then
		ownsTitle = true -- they can unequip
	else
		for _, ach in ipairs(Achievements) do
			if ach.reward.title == titleKey then
				if data.AchievementsClaimed and data.AchievementsClaimed[ach.key] then
					ownsTitle = true
					break
				end
			end
		end
	end

	if not ownsTitle then return false end

	data.WornTitle = titleKey ~= "" and titleKey or nil
	player:SetAttribute("WornTitle", data.WornTitle)
	
	PlayerDataService.PushToClient(player)
	return true
end

function AchievementService.Init()
	local function onPlayerAdded(player)
		task.spawn(function()
			local data = nil
			local tries = 0
			repeat
				task.wait(0.5)
				tries = tries + 1
				if not player.Parent or tries > 10 then return end
				data = PlayerDataService.Get(player)
			until data
			
			if data.WornTitle then
				player:SetAttribute("WornTitle", data.WornTitle)
			end
		end)
	end
	game.Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in ipairs(game.Players:GetPlayers()) do
		onPlayerAdded(p)
	end

	if not Remotes:FindFirstChild("AchievementClaim") then
		local ev = Instance.new("RemoteFunction")
		ev.Name = "AchievementClaim"
		ev.Parent = Remotes
	end
	if not Remotes:FindFirstChild("EquipTitle") then
		local ev = Instance.new("RemoteFunction")
		ev.Name = "EquipTitle"
		ev.Parent = Remotes
	end

	Remotes.AchievementClaim.OnServerInvoke = AchievementService.HandleClaim
	Remotes.EquipTitle.OnServerInvoke = AchievementService.HandleEquipTitle
end

return AchievementService