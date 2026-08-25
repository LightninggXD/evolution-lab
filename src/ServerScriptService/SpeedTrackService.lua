local RS = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS.Remotes

local PlayerDataService = require(ServerScriptService.PlayerDataService)

local SpeedTrackService = {}
local trackTimers = {} -- [player] = { trackId = timeInSeconds }

function SpeedTrackService.Init()
	local mapFolder = workspace:FindFirstChild("Map")
	if not mapFolder then return end

	local secretsFolder = mapFolder:FindFirstChild("Secrets")
	if not secretsFolder then
		secretsFolder = Instance.new("Folder")
		secretsFolder.Name = "Secrets"
		secretsFolder.Parent = mapFolder
	end

	for _, trackDef in ipairs(GameConfig.SpeedTracks or {}) do
		local zoneData = GameConfig.GetZone(trackDef.zoneKey)
		if not zoneData then continue end

		-- Create physical track
		local trackPart = Instance.new("Part")
		trackPart.Name = "SpeedTrack_" .. trackDef.id
		trackPart.Size = Vector3.new(trackDef.width or 20, 1, trackDef.length or 60)
		trackPart.Position = Vector3.new(zoneData.offset, 0, 0) + trackDef.offset
		trackPart.Anchored = true
		trackPart.CanCollide = false
		trackPart.BrickColor = BrickColor.new("Bright yellow")
		trackPart.Material = Enum.Material.Neon
		trackPart.Transparency = 0.5
		
		-- Create a visual base
		local trackBase = Instance.new("Part")
		trackBase.Name = "SpeedTrackBase"
		trackBase.Size = Vector3.new(trackDef.width or 20, 1, trackDef.length or 60)
		trackBase.Position = trackPart.Position - Vector3.new(0, 0.9, 0)
		trackBase.Anchored = true
		trackBase.CanCollide = true
		trackBase.BrickColor = BrickColor.new("Dark stone grey")
		trackBase.Material = Enum.Material.DiamondPlate
		trackBase.Parent = trackPart

		trackPart:SetAttribute("SecretsVersion", 1)
		trackPart.Parent = secretsFolder

		-- Track players standing on it
		trackPart.Touched:Connect(function(hit)
			local character = hit.Parent
			local player = Players:GetPlayerFromCharacter(character)
			if player then
				SpeedTrackService.PlayerOnTrack(player, trackDef)
			end
		end)
		
		trackPart.TouchEnded:Connect(function(hit)
			local character = hit.Parent
			local player = Players:GetPlayerFromCharacter(character)
			if player then
				SpeedTrackService.PlayerOffTrack(player, trackDef)
			end
		end)
	end
end

function SpeedTrackService.PlayerOnTrack(player, trackDef)
	if not trackTimers[player] then
		trackTimers[player] = {}
	end
	
	if not trackTimers[player][trackDef.id] then
		trackTimers[player][trackDef.id] = true
		
		-- Start reward loop
		task.spawn(function()
			while trackTimers[player] and trackTimers[player][trackDef.id] do
				task.wait(trackDef.interval or 1)
				if not trackTimers[player] or not trackTimers[player][trackDef.id] then break end
				
				local data = PlayerDataService.Get(player)
				if data then
					local currentLevel = data.Upgrades.Speed or 0
					local maxLevel = GameConfig.GetUpgradeMaxLevel(data)
					
					if currentLevel < maxLevel then
						data.Upgrades.Speed = currentLevel + 1
						
						-- Need to trigger Mastery update for WalkSpeed
						local DNAService = require(ServerScriptService.DNAService)
						if DNAService.OnMasteryChanged then
							DNAService.OnMasteryChanged(player, data)
						end
						
						PlayerDataService.UpdateLeaderstats(player)
						PlayerDataService.PushToClient(player)
						
						Remotes.Notify:FireClient(player, { kind = "upgrade", upgrade = "Speed", level = currentLevel + 1 })
					end
				end
			end
		end)
	end
end

function SpeedTrackService.PlayerOffTrack(player, trackDef)
	if trackTimers[player] then
		trackTimers[player][trackDef.id] = nil
	end
end

Players.PlayerRemoving:Connect(function(player)
	trackTimers[player] = nil
end)

return SpeedTrackService
