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

	-- SCALED, because a fixed DNA figure is meaningless in an economy spanning 1e2 to 1e17.
	--
	-- The packs are authored as 1,000 and 10,000 DNA. That is a real boost at stage one and less
	-- than a SINGLE KILL from stage six on -- a player paying real money for a rounding error, which
	-- is a refund and a one-star review rather than a sale. GameConfig.ScaleReward reads the authored
	-- figure as "what this is worth in stage-one clicks" and converts it to where the buyer actually
	-- stands, so a pack is worth the same number of kills at every stage. This is the same treatment
	-- RewardService, PlaytimeGiftService and SeasonPassService.grant already give their tables; the
	-- paid route was the one that was missed.
	if product.grantDNA then
		data.DNA += GameConfig.ScaleReward(product.grantDNA, data)
	end
	if product.grantPotions then
		GameConfig.AddPotions(data, product.grantPotionId, product.grantPotions)
	end
	-- DIAMONDS ARE DELIBERATELY NOT SCALED, and this is not an oversight. Every diamond sink in the
	-- game is a small fixed number that does NOT move with the stage curve: the three DiamondUpgrades
	-- cost 5, 8 and 15 with a per-level multiplier, and Stage Mastery is priced the same way. Putting
	-- these through ScaleReward would hand a stage-14 buyer thousands of diamonds and cap every
	-- permanent upgrade in the game in one purchase.
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
