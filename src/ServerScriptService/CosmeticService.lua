local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Telemetry = require(ServerScriptService.Telemetry)
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
	Telemetry.Economy(player, "Sink", Telemetry.Currency.Diamonds, cost, data.Diamonds, Telemetry.Tx.Shop, "Cosmetic")
	
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
		local config = nil
		for _, c in ipairs(GameConfig.Cosmetics) do
			if c.key == cosmeticKey then
				config = c
				break
			end
		end
		if not config then return false end
		
		data.WornCosmetics[config.type] = cosmeticKey
		player:SetAttribute("Worn" .. config.type, cosmeticKey)
	else
		local validTypes = {}
		for _, c in ipairs(GameConfig.Cosmetics) do
			validTypes[c.type] = true
		end
		if not validTypes[cosmeticType] then return false end

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
	local function onPlayerAdded(player)
		task.spawn(function()
			local data = nil
			local tries = 0
			repeat
				task.wait(0.5)
				tries = tries + 1
				if not player.Parent or tries > 20 then return end
				data = PlayerDataService.Get(player)
			until data
			
			if data.WornCosmetics then
				for cType, cKey in pairs(data.WornCosmetics) do
					player:SetAttribute("Worn" .. cType, cKey)
				end
			end
		end)
	end
	game.Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in ipairs(game.Players:GetPlayers()) do
		onPlayerAdded(p)
	end
end

return CosmeticService