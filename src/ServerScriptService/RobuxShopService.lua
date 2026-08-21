local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS.Remotes

local PlayerDataService = require(script.Parent.PlayerDataService)
local BoardStats = require(script.Parent.MapProps.BoardStats)
local Telemetry = require(script.Parent.Telemetry)
local SeasonPassService = require(script.Parent.SeasonPassService)
-- for the Lucky Spin only: the wheel is bent by the buyer's own luck, and GetLuckPercent is the one
-- function that knows what that is. No cycle -- DNAService requires PlayerDataService and PetService
-- and neither of those reaches back here.
local DNAService = require(script.Parent.DNAService)
-- Both added 2026-08-17 for the two new wheel segments, and both are CALLS INTO THE OWNING SERVICE
-- rather than reimplementations. `RelicService.GiveChest` is the seam that file's own header names
-- for exactly this ("a future boss drop or hidden passage"); `PetService.GrantWheelPet` is the door
-- onto `insertPet`, which is the one place in the game a pet is created.
--
-- NEITHER IS A CYCLE, and it is worth stating which way the arrows point because a require loop here
-- would break the receipt handler rather than fail loudly. `RelicService` requires GameConfig and
-- PlayerDataService and nothing else. `PetService` requires GameConfig, PlayerDataService,
-- SeasonPassService and AnnounceService -- and is ALREADY in this file's require graph anyway, since
-- `DNAService` above requires it. Nothing in either reaches back to this file.
local RelicService = require(script.Parent.RelicService)
local PetService = require(script.Parent.PetService)

local RobuxShopService = {}

-- The wheel's own remote, created on demand like every other one added since the place was last
-- saved by hand. See the long note over `notifySpin` for why the reveal does not ride on `Notify`.
local function ensureRemote(name)
	local r = Remotes:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = Remotes
	end
	return r
end

local SpinResult = ensureRemote("SpinResult")

-- ===== THE LUCKY SPIN, GRANTED SERVER-SIDE OFF THE PLAYER'S OWN LUCK =====
--
-- The client never sees the wheel turn until the server has already decided. That ordering is the
-- whole security model of a paid gamble: if the client picked the segment and told the server, every
-- spin would be a jackpot within a day of launch. The animation the player watches is a LIE THAT
-- ARRIVES AT A PREDETERMINED TRUTH -- it is handed the winning index and works backwards to a
-- rotation that lands there, which is how every case-opener and prize wheel worth copying is built.
--
-- DNA is SCALED and everything else is not, for exactly the reasons the grant block below states --
-- a DNA figure is authored in stage-one clicks and has to be converted to where the buyer stands,
-- while diamonds, shards and potions are fixed-size objects that do not ride the stage curve.
--
-- ===== EVERY SEGMENT THE ROLL CAN RETURN MUST BE PAYABLE HERE =====
--
-- This function and `GameConfig.SpinWheel` are one thing wearing two files. A row the roll can
-- produce and this cannot pay is not a bug that throws -- it is a player who watched the wheel stop
-- on a prize and received nothing, silently, with the money already gone. So the twelve rows map
-- onto exactly five branches plus the two below them, and adding a row means adding its branch in
-- the same edit or the row does not go in.
--
-- Returns the segment AND a `detail` table the reveal quotes: the actual DNA figure after scaling,
-- the pet's real species, the potion's real name. The client cannot compute any of those -- scaling
-- needs the save and the pet is rolled here -- and a reveal that says "Mystery Pet" where the player
-- actually got a Trilobite is a worse reveal than one that names it.
local function applySpin(player, data)
	local segment = GameConfig.RollSpin(DNAService.GetLuckPercent(data))
	local detail = {}

	if segment.dna then
		-- kept, not recomputed: this is the number that actually landed in the save, and it is the
		-- number the card should read
		local paid = GameConfig.ScaleReward(segment.dna, data)
		data.DNA += paid
		detail.dna = paid
		Telemetry.Economy(player, "Source", Telemetry.Currency.DNA, paid, data.DNA,
			Telemetry.Tx.TimedReward, "spin")
	end
	if segment.diamonds then
		data.Diamonds = (data.Diamonds or 0) + segment.diamonds
		detail.diamonds = segment.diamonds
		Telemetry.Economy(player, "Source", Telemetry.Currency.Diamonds, segment.diamonds,
			data.Diamonds, Telemetry.Tx.TimedReward, "spin")
	end
	if segment.shards then
		data.EvolutionShards = (data.EvolutionShards or 0) + segment.shards
		detail.shards = segment.shards
	end
	if segment.potions then
		GameConfig.AddPotions(data, segment.potionId, segment.potions)
		local potion = GameConfig.GetPotion(segment.potionId)
		detail.potion = potion and potion.shortName or nil
		detail.potions = segment.potions
	end
	-- Banked UNOPENED, which is the whole point of `GiveChest` existing separately from opening one.
	-- The reveal on this wheel is "you won a chest"; what is inside it is the Relic Forge's reveal,
	-- and stacking the two would spend the forge's moment on a wheel that has already had one.
	--
	-- It re-fetches the same cached save table this function was handed -- same object, so the write
	-- lands where we expect -- and pushes to the client itself. That extra push is a few hundred
	-- bytes and it is not worth an argument to `GiveChest` to suppress: the caller below pushes again
	-- straight after and a duplicate DataUpdate is idempotent on the client.
	if segment.relicChests then
		RelicService.GiveChest(player, segment.relicChests)
		detail.relicChests = segment.relicChests
	end
	if segment.pet then
		local petDef, why = PetService.GrantWheelPet(data)
		if petDef then
			detail.petKey = petDef.key
			detail.petName = petDef.name
			detail.petEmoji = petDef.emoji
			detail.petRarity = petDef.rarity
		else
			-- A FULL BAG MUST NOT MEAN AN EMPTY SPIN. The player has already paid -- Robux, 25 Shards,
			-- or their one free spin of the day -- and `GrantWheelPet` refuses rather than silently
			-- dropping the pet precisely so this branch can exist. 25 Shards is the substitute because
			-- it is a real row on this same wheel at a comparable weight, so nobody is being fobbed
			-- off with a token, and because shards are the one currency a player with 200 pets
			-- certainly still wants (they buy more spins).
			--
			-- `detail.substituted` carries the reason to the reveal, which says so out loud. A prize
			-- quietly swapped for a different prize is how a player concludes the wheel is rigged.
			data.EvolutionShards = (data.EvolutionShards or 0) + 25
			detail.shards = 25
			detail.substituted = (why == "full") and "Pet inventory full" or "No pet available"
		end
	end

	return segment, detail
end

-- ===== ONE PRESS, A CHAIN OF SPINS =====
--
-- `respin` is a segment that pays another spin, so a press is not one roll any more, it is a LIST of
-- rolls terminated by the first non-respin. Rolled to the end here, server-side, before the client
-- is told anything -- the client is then handed the finished list and plays it as a sequence of
-- animations. It must never be handed one segment at a time and asked to come back for the next: a
-- client that stopped asking after the respin would have been paid for a spin it never watched, and
-- one that asked twice would want paying twice.
--
-- Bounded by `GameConfig.SpinMaxChain` -- see the note there for why a fuse rather than a balance
-- number. On the last allowed iteration a respin is REPLACED by the wheel's first segment rather
-- than dropped, so even the impossible case pays something.
local function rollSpinChain(player, data)
	local chain = {}
	local cap = GameConfig.SpinMaxChain or 12

	for i = 1, cap do
		local segment, detail = applySpin(player, data)

		if segment.respin and i == cap then
			-- the fuse blowing. Pay the commonest row instead and stop; `applySpin` has already been
			-- run for the respin, which grants nothing, so there is nothing to unwind.
			local fallback = GameConfig.SpinWheel[1]
			local paid = fallback.dna and GameConfig.ScaleReward(fallback.dna, data) or 0
			data.DNA += paid
			Telemetry.Economy(player, "Source", Telemetry.Currency.DNA, paid, data.DNA,
				Telemetry.Tx.TimedReward, "spinFallback")
			table.insert(chain, { segment = fallback, detail = { dna = paid } })
			break
		end

		table.insert(chain, { segment = segment, detail = detail })
		if not segment.respin then break end
	end

	return chain
end

-- ===== TELLING THE CLIENT, ON ITS OWN REMOTE =====
--
-- This used to fire `Remotes.Notify` with `kind = "spin"` and MainUI drew a toast. It now fires a
-- dedicated `SpinResult` and `SpinReveal.client.lua` draws the wheel, and the reason for a separate
-- remote rather than a richer notify is not tidiness:
--
--   1. `Notify` IS A TOAST BUS. `SoundLibrary.PlayNotify` plays a sound for every `kind` in its
--      table -- `spin` maps to `purchase` -- and MainUI's handler draws a card for it. Both of those
--      would fire the instant the server paid out, i.e. roughly five seconds before the wheel
--      actually stops on the prize, announcing the answer over the top of its own suspense.
--   2. A CHAIN IS NOT A NOTIFICATION. The payload is now an ordered list of spins with a detail
--      table each; that is a shape the twenty-branch notify handler has no business growing.
--
-- **MainUI's `kind == "spin"` branch is therefore now dead code**, deliberately and in exactly the
-- way `crit` and `machine` in `SoundLibrary.NOTIFY_SOUND` are dead: nothing sends that kind any more.
-- It is left alone rather than deleted because that file is at Luau's register ceiling and a branch
-- nobody reaches costs nothing. If the wheel ever needs a silent fallback again, sending `spin`
-- brings the old toast straight back.
local function notifySpin(player, chain)
	local spins = {}
	for _, entry in ipairs(chain) do
		table.insert(spins, {
			-- THE INDEX IS THE WHOLE POINT OF THIS PAYLOAD. The client lands the pointer by position
			-- in `GameConfig.SpinWheel`, and it is computed here off the same table rather than
			-- matched by key on the far side -- a client running an older GameConfig would otherwise
			-- silently animate to the wrong pod. `GetSpinIndex` returns nil for a key this build has
			-- never heard of and the client treats nil as "do not animate, just show the card".
			index = GameConfig.GetSpinIndex(entry.segment.key),
			key = entry.segment.key,
			emoji = entry.segment.emoji,
			name = entry.segment.name,
			detail = entry.detail,
		})
	end
	SpinResult:FireClient(player, { spins = spins })
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
		local paidDna = GameConfig.ScaleReward(product.grantDNA, data)
		data.DNA += paidDna
		Telemetry.Economy(player, "Source", Telemetry.Currency.DNA, paidDna, data.DNA,
			Telemetry.Tx.IAP, "product:" .. tostring(product.key))
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
		Telemetry.Economy(player, "Source", Telemetry.Currency.Diamonds, product.grantDiamonds,
			data.Diamonds, Telemetry.Tx.IAP, "product:" .. tostring(product.key))
	end
	-- Shards are unscaled for a STRONGER reason than diamonds (11.12): a shard buys exactly one thing
	-- in the whole game, a spin at the flat `SpinCostShards` of 25, so ScaleReward here would sell a
	-- late-stage buyer thousands of spins on one tile.
	if product.grantShards then
		data.EvolutionShards = (data.EvolutionShards or 0) + product.grantShards
		Telemetry.Economy(player, "Source", Telemetry.Currency.Shards, product.grantShards,
			data.EvolutionShards, Telemetry.Tx.IAP, "product:" .. tostring(product.key))
	end
	-- The premium pass is a flag, not a payout, and it pushes its own confirmation -- so it is
	-- unlocked here and the generic notify below still fires for the receipt itself.
	if product.grantSeasonPremium then
		SeasonPassService.GrantPremium(player)
	end
	local spinChain
	if product.grantSpin then
		spinChain = rollSpinChain(player, data)
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

	-- The map's Robux Spent board (31.5). BEFORE the save below, so the figure rides out on the
	-- same write the grant does -- a counter saved separately is a counter that can disagree with
	-- the thing it counted. `CurrencySpent` is the price Roblox actually charged, which is the only
	-- honest number here: the authored price can change between a purchase and a retry.
	BoardStats.RobuxSpent(data, receiptInfo.CurrencySpent)

	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.PushToClient(player)
	-- The spin announces ITSELF, and only itself. Firing the generic "Purchased!" card as well would
	-- stack two celebrations on one click and bury the one the player actually paid to see.
	if spinChain then
		notifySpin(player, spinChain)
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
-- ROADMAP does not accept as verification.
--
-- Grants and announces one PRESS, which since the `respin` segment landed is a chain of one or more
-- spins rather than a single roll. It still returns the segment the press finally paid out on -- the
-- LAST link, never the respins on the way there -- because that is what its two callers
-- (`SpendShardSpin` and `RewardService.HandleFreeSpin`) mean by "what did I win", and because both
-- of them are tested by reading that return value rather than by watching a screen.
function RobuxShopService.GrantSpin(player)
	local data = PlayerDataService.Get(player)
	if not data then return nil end
	local chain = rollSpinChain(player, data)
	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.PushToClient(player)
	notifySpin(player, chain)
	local last = chain[#chain]
	return last and last.segment or nil
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
	Telemetry.Economy(player, "Sink", Telemetry.Currency.Shards, cost, data.EvolutionShards,
		Telemetry.Tx.Shop, "shardSpin")
	Telemetry.Custom(player, "SpinTaken", 1)   -- 1 = paid with shards, 0 = the free daily
	RobuxShopService.GrantSpin(player)
	return "ok"
end

function RobuxShopService.Init()
	MarketplaceService.ProcessReceipt = processReceipt

	-- created on demand, like every remote added since the place was last saved by hand. `SpinResult`
	-- is made at module load rather than here, because `notifySpin` closes over it and a receipt can
	-- in principle arrive before `Init` runs.
	local shardSpin = ensureRemote("SpinWithShards")
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
