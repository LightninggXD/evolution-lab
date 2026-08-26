local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local PlayerDataService = require(ServerScriptService.PlayerDataService)
local Remotes = ReplicatedStorage.Remotes

local CosmeticService = {}

function CosmeticService.HandlePurchase(player, cosmeticKey)
	local data = PlayerDataService.Get(player)
	if not data then return false end

	local config = nil
	for _, c in ipairs(GameConfig.Cosmetics) do
		if c.key == cosmeticKey then
			config = c
			break
		end
	end
	if not config then return false end
	
	data.CosmeticsOwned = data.CosmeticsOwned or {}
	if data.CosmeticsOwned[cosmeticKey] then return false end -- Already owned

	local cost = config.priceDiamonds
	if not cost or cost <= 0 then return false end
	
	if (data.Diamonds or 0) < cost then
		return false
	end

	data.Diamonds = data.Diamonds - cost
	data.CosmeticsOwned[cosmeticKey] = true
	
	PlayerDataService.PushToClient(player)
	return true
end

function CosmeticService.HandleEquip(player, cosmeticType, cosmeticKey)
	local data = PlayerDataService.Get(player)
	if not data then return false end

	data.CosmeticsOwned = data.CosmeticsOwned or {}
	data.WornCosmetics = data.WornCosmetics or {}

	if cosmeticKey ~= "" and cosmeticKey ~= nil then
		if not data.CosmeticsOwned[cosmeticKey] then
			return false
		end
		data.WornCosmetics[cosmeticType] = cosmeticKey
		player:SetAttribute("Worn" .. cosmeticType, cosmeticKey)
	else
		data.WornCosmetics[cosmeticType] = nil
		player:SetAttribute("Worn" .. cosmeticType, nil)
	end
	
	PlayerDataService.PushToClient(player)
	return true
end

function CosmeticService.Init()
	if not Remotes:FindFirstChild("CosmeticPurchase") then
		local ev = Instance.new("RemoteFunction")
		ev.Name = "CosmeticPurchase"
		ev.Parent = Remotes
	end
	if not Remotes:FindFirstChild("CosmeticEquip") then
		local ev = Instance.new("RemoteFunction")
		ev.Name = "CosmeticEquip"
		ev.Parent = Remotes
	end

	Remotes.CosmeticPurchase.OnServerInvoke = CosmeticService.HandlePurchase
	Remotes.CosmeticEquip.OnServerInvoke = CosmeticService.HandleEquip
	
	-- Restore attributes on join
	game.Players.PlayerAdded:Connect(function(player)
		-- Wait for data to load
		task.spawn(function()
			local data = nil
			repeat
				task.wait(0.5)
				if not player.Parent then return end
				data = PlayerDataService.Get(player)
			until data
			
			if data.WornCosmetics then
				if data.WornCosmetics["Trail"] then player:SetAttribute("WornTrail", data.WornCosmetics["Trail"]) end
				if data.WornCosmetics["NamePlate"] then player:SetAttribute("WornNamePlate", data.WornCosmetics["NamePlate"]) end
				if data.WornCosmetics["Emote"] then player:SetAttribute("WornEmote", data.WornCosmetics["Emote"]) end
			end
		end)
	end)
end

return CosmeticService