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

	-- ===== THREE CURRENCIES AND A FREE ROW (34.29) =====
	--
	-- This read `config.priceDiamonds` and refused anything costing `<= 0`. Both halves are now
	-- wrong: the trails are priced in Evolution Shards (they carry the speed ladder, and shards had
	-- exactly one sink before this), and the three emotes are FREE -- so that `<= 0` guard made
	-- every free row unbuyable and therefore unequippable, which would have shipped as "the emotes
	-- do nothing".
	--
	-- The price comes from `GameConfig.GetCosmeticPrice`, the one function the panel prints from,
	-- so a button and this charge cannot quote different numbers -- the same rule the enchant price
	-- and the transfer price are held to.
	local cost, currency = GameConfig.GetCosmeticPrice(config)

	if currency == "Shards" then
		if (data.EvolutionShards or 0) < cost then return false end
		data.EvolutionShards -= cost
		Telemetry.Economy(player, "Sink", Telemetry.Currency.Shards, cost, data.EvolutionShards,
			Telemetry.Tx.Shop, "Cosmetic")
	elseif currency == "Diamonds" then
		if (data.Diamonds or 0) < cost then return false end
		data.Diamonds -= cost
		Telemetry.Economy(player, "Sink", Telemetry.Currency.Diamonds, cost, data.Diamonds,
			Telemetry.Tx.Shop, "Cosmetic")
	end
	-- currency == nil is a FREE row: nothing is charged and nothing is logged as a sink, because no
	-- currency left the economy. It still has to be claimed once so `CosmeticsOwned` gates the
	-- equip the same way for every row.

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

	-- ===== A TRAIL MOVES THE PLAYER, SO EQUIPPING ONE HAS TO RE-APPLY THE WALK SPEED (34.29) =====
	--
	-- `WalkSpeed` is written in exactly one place -- `EvolutionVisuals.applyMastery` -- and until
	-- now nothing on this path had any reason to run it: a trail was paint. It is the speed ladder
	-- now, so without this the new trail's studs would not arrive until the next respawn, evolve or
	-- potion, and the player would equip a 20% trail and feel nothing.
	--
	-- `RefreshBonuses` rather than a remembered delta, for the reason `PotionService`'s note gives:
	-- it recomputes the whole product -- stage, mastery, worn skin, potion, mutation, trail -- so
	-- two sources can never drift. Guarded, because it is a cross-system call and a player equipping
	-- during a respawn has no character for a frame.
	if not player.Character then return true end
	local ok, EvolutionVisuals = pcall(require, script.Parent:WaitForChild("Systems"):WaitForChild("EvolutionVisuals"))
	if ok and EvolutionVisuals and EvolutionVisuals.RefreshBonuses then
		EvolutionVisuals.RefreshBonuses(player, data)
	end
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