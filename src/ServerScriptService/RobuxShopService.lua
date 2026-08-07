local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS.Remotes

local PlayerDataService = require(script.Parent.PlayerDataService)
local SeasonPassService = require(script.Parent.SeasonPassService)

local RobuxShopService = {}

local function getProductByPurchaseId(productId)
	for _, p in ipairs(GameConfig.RobuxProducts) do
		if p.productId == productId then return p end
	end
	return nil
end

-- Grants the reward server-side ONLY from ProcessReceipt (the one place Roblox guarantees
-- the Robux payment actually went through) -- never grant purchases from a RemoteEvent or
-- PromptProductPurchaseFinished alone, both can fire without real payment.
local function processReceipt(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local data = PlayerDataService.Get(player)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local product = getProductByPurchaseId(receiptInfo.ProductId)
	if not product then
		-- NOT granted. This used to acknowledge the receipt so Roblox would stop retrying, which
		-- means a product that exists on the Roblox dashboard but is missing or mistyped in
		-- GameConfig.RobuxProducts took the player's Robux and handed back nothing, permanently and
		-- silently. NotProcessedYet leaves the purchase pending instead: the player is not charged
		-- out of pocket for our configuration mistake, and it is granted the moment it is fixed.
		warn(("[RobuxShopService] receipt for unknown product %s -- left pending"):format(
			tostring(receiptInfo.ProductId)))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if product.grantDNA then
		data.DNA += product.grantDNA
	end
	if product.grantPotions then
		GameConfig.AddPotions(data, product.grantPotionId, product.grantPotions)
	end
	if product.grantDiamonds then
		data.Diamonds = (data.Diamonds or 0) + product.grantDiamonds
	end
	-- The premium pass is a flag, not a payout, and it pushes its own confirmation -- so it is
	-- unlocked here and the generic notify below still fires for the receipt itself.
	if product.grantSeasonPremium then
		SeasonPassService.GrantPremium(player)
	end

	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.PushToClient(player)
	Remotes.Notify:FireClient(player, { kind = "robuxPurchase", name = product.name })

	-- SAVED BEFORE IT IS ACKNOWLEDGED, and only acknowledged if the save actually landed.
	--
	-- Granting into the in-memory table and returning PurchaseGranted tells Roblox the purchase is
	-- complete and consumed -- it is never retried. If the server then goes down before the 60s
	-- autosave, the player has paid real money for something the save has never heard of, and
	-- there is no mechanism anywhere that would ever give it to them. Returning NotProcessedYet on
	-- a failed save costs nothing: Roblox re-delivers the receipt and the grant runs again.
	if PlayerDataService.Save(player) == false then
		warn(("[RobuxShopService] save failed after granting %s to %s -- receipt left pending")
			:format(product.key, player.Name))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function RobuxShopService.Init()
	MarketplaceService.ProcessReceipt = processReceipt

	Remotes.PromptRobuxPurchase.OnServerEvent:Connect(function(player, productKey)
		if typeof(productKey) ~= "string" then return end
		local product = GameConfig.GetRobuxProduct(productKey)
		if not product then return end
		if not product.productId or product.productId <= 0 then
			Remotes.Notify:FireClient(player, { kind = "error", message = "This item isn't set up yet -- check back soon!" })
			return
		end
		MarketplaceService:PromptProductPurchase(player, product.productId)
	end)
end

return RobuxShopService
