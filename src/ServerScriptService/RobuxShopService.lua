local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS.Remotes

local PlayerDataService = require(script.Parent.PlayerDataService)
local SeasonPassService = require(script.Parent.SeasonPassService)
-- for the Lucky Spin only: the wheel is bent by the buyer's own luck, and GetLuckPercent is the one
-- function that knows what that is. No cycle -- DNAService requires PlayerDataService and PetService
-- and neither of those reaches back here.
local DNAService = require(script.Parent.DNAService)

local RobuxShopService = {}

-- ===== THE LUCKY SPIN, GRANTED SERVER-SIDE OFF THE PLAYER'S OWN LUCK =====
--
-- The client never sees the wheel turn until the server has already decided. That ordering is the
-- whole security model of a paid gamble: if the client picked the segment and told the server, every
-- spin would be a jackpot within a day of launch.
--
-- DNA is SCALED and everything else is not, for exactly the reasons the grant block below states --
-- a DNA figure is authored in stage-one clicks and has to be converted to where the buyer stands,
-- while diamonds, shards and potions are fixed-size objects that do not ride the stage curve.
local function applySpin(player, data)
	local segment = GameConfig.RollSpin(DNAService.GetLuckPercent(data))

	if segment.dna then
		data.DNA += GameConfig.ScaleReward(segment.dna, data)
	end
	if segment.diamonds then
		data.Diamonds = (data.Diamonds or 0) + segment.diamonds
	end
	if segment.shards then
		data.EvolutionShards = (data.EvolutionShards or 0) + segment.shards
	end
	if segment.potions then
		GameConfig.AddPotions(data, segment.potionId, segment.potions)
	end

	return segment
end

local function notifySpin(player, segment)
	Remotes.Notify:FireClient(player, {
		kind = "spin",
		segmentKey = segment.key,
		emoji = segment.emoji,
		name = segment.name,
	})
end

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
	-- cost 25, 40 and 75 with a per-level multiplier, and Stage Mastery is priced the same way. Putting
	-- these through ScaleReward would hand a stage-14 buyer thousands of diamonds and cap every
	-- permanent upgrade in the game in one purchase.
	if product.grantDiamonds then
		data.Diamonds = (data.Diamonds or 0) + product.grantDiamonds
	end
	-- Shards are unscaled for a STRONGER reason than diamonds (11.12): a shard buys exactly one thing
	-- in the whole game, a spin at the flat `SpinCostShards` of 25, so ScaleReward here would sell a
	-- late-stage buyer thousands of spins on one tile.
	if product.grantShards then
		data.EvolutionShards = (data.EvolutionShards or 0) + product.grantShards
	end
	-- The premium pass is a flag, not a payout, and it pushes its own confirmation -- so it is
	-- unlocked here and the generic notify below still fires for the receipt itself.
	if product.grantSeasonPremium then
		SeasonPassService.GrantPremium(player)
	end
	local spinSegment
	if product.grantSpin then
		spinSegment = applySpin(player, data)
	end
	-- A COUNT, not an event, and deliberately NOT put through ScaleReward: a revive is one fixed-size
	-- object like a potion bottle, not a currency riding the stage curve.
	if product.grantBossRevives then
		data.BossRevives = (data.BossRevives or 0) + product.grantBossRevives
	end
	-- same shape, same reasoning: a counted charge, spent later by PetService.HandleTierUp
	if product.grantTierUps then
		data.TierUpTokens = (data.TierUpTokens or 0) + product.grantTierUps
	end

	-- SPEND IT NOW IF THERE IS SOMETHING TO SPEND IT ON. A buyer who paid in the middle of a fight
	-- expects the boss's health back, not an item in a menu -- so the receipt landing is itself the
	-- trigger. When it lands too late (the fight is over, the boss respawned, nothing has healed)
	-- TryConsumeRevive spends nothing and the charge simply waits, which is the entire reason this
	-- product is a counted charge instead of a moment. Required lazily: BossService builds folders and
	-- remotes at module load, and this file has no business forcing that during a receipt.
	local announced = false
	if product.grantBossRevives then
		local BossService = require(script.Parent.BossService)
		if BossService.TryConsumeRevive(player) then
			-- TryConsumeRevive has already told the player what happened to their boss
			announced = true
		else
			Remotes.Notify:FireClient(player, {
				kind = "reward",
				message = ("\u{2694}\u{FE0F} Boss Revive saved -- %d ready for your next attempt."):format(data.BossRevives),
			})
			announced = true
		end
	end

	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.PushToClient(player)
	-- The spin announces ITSELF, and only itself. Firing the generic "Purchased!" card as well would
	-- stack two celebrations on one click and bury the one the player actually paid to see.
	if spinSegment then
		notifySpin(player, spinSegment)
	elseif not announced then
		Remotes.Notify:FireClient(player, { kind = "robuxPurchase", name = product.name })
	end

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

-- PUBLIC ON PURPOSE, for two reasons that both outlive this line. ROADMAP 5.6 wants a free daily
-- spin, which is this same wheel reached by a different trigger and must not become a second copy
-- of the grant logic. And while every productId is still 0 there is no way to make a real receipt
-- arrive, so without a public entry point the paid path could only be READ, never run -- which the
-- ROADMAP does not accept as verification. Grants and announces one spin; returns the segment.
function RobuxShopService.GrantSpin(player)
	local data = PlayerDataService.Get(player)
	if not data then return nil end
	local segment = applySpin(player, data)
	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.PushToClient(player)
	notifySpin(player, segment)
	return segment
end

-- ===== THE SAME WHEEL, PAID FOR IN EVOLUTION SHARDS (9.4) =====
--
-- Shards became a drop off the raised creatures and needed a sink; this is it, and it is
-- deliberately not a second wheel. Same table, same roll, same luck bend, same grant: GrantSpin was
-- already public for the free daily spin, and this is the third door into one implementation rather
-- than a copy that would have to be balanced separately and would drift the first time either was
-- touched. It is also why the 3.3 balance pass still describes this wheel exactly.
--
-- Returns a status string so it is testable without a mouse, the shape CodesService and
-- RewardService.HandleFreeSpin both use.
local SPIN_INTERVAL = 0.5
local lastSpin = {}

function RobuxShopService.SpendShardSpin(player)
	local data = PlayerDataService.Get(player)
	if not data then return "nodata" end

	-- Not an anti-exploit measure -- the price is that -- but a spammed button would fire a spin
	-- notification per frame until the balance ran out, and the wheel is a thing you watch.
	local now = os.clock()
	local previous = lastSpin[player.UserId]
	if previous and (now - previous) < SPIN_INTERVAL then return "throttled" end

	local cost = GameConfig.SpinCostShards
	if (data.EvolutionShards or 0) < cost then
		Remotes.Notify:FireClient(player, {
			kind = "error",
			message = ("You need %d \u{1F31F} Shards to spin -- beat the creatures up on the cliffs!"):format(cost),
		})
		return "poor"
	end

	lastSpin[player.UserId] = now
	-- CHARGED BEFORE THE GRANT, WITH NO YIELD BETWEEN THEM -- the rule the code redemption and the
	-- free spin both follow. GrantSpin reads the same table back out of the cache, rolls, pays,
	-- pushes and notifies; nothing on that path yields, so there is no frame in which a second call
	-- could see these shards still sitting there and spin twice off one balance.
	data.EvolutionShards -= cost
	RobuxShopService.GrantSpin(player)
	return "ok"
end

function RobuxShopService.Init()
	MarketplaceService.ProcessReceipt = processReceipt

	-- created on demand, like every remote added since the place was last saved by hand
	local shardSpin = Remotes:FindFirstChild("SpinWithShards")
	if not shardSpin then
		shardSpin = Instance.new("RemoteEvent")
		shardSpin.Name = "SpinWithShards"
		shardSpin.Parent = Remotes
	end
	shardSpin.OnServerEvent:Connect(function(player)
		RobuxShopService.SpendShardSpin(player)
	end)

	-- the throttle stamp is the only thing this file holds per player, and it is keyed by user id
	-- rather than by the Player object so that a rejoin cannot resurrect a stale entry
	Players.PlayerRemoving:Connect(function(player)
		lastSpin[player.UserId] = nil
	end)

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
