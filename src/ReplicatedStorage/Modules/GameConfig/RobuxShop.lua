-- GameConfig.RobuxShop -- the developer products and the nine game passes.
--
-- ONE OF THE SIXTEEN PARTS OF `GameConfig` (18.9), moved byte for byte. It is handed the
-- shared config table and writes into it; see the loader in `GameConfig` itself for why
-- the order of the parts is load-bearing and why nothing here is re-indented.

return function(GameConfig)

-- ===== ROBUX SHOP =====
-- Real-money packages bought with Robux via MarketplaceService Developer Products.
--
-- THE IDS BELOW ARE REAL AS OF 2026-08-11. All seventeen were created on the Creator Dashboard
-- against universe **10675543038 ("Evolution Lab BETA V0.2")** -- the experience the play-testers
-- actually join -- with Managed pricing DISABLED on every one, so the price the dashboard shows is
-- exactly the price in this table and nothing re-prices them per region.
--
-- A PRODUCT ID IS BOUND TO ITS UNIVERSE. If this place is ever published to a different experience
-- these ids stop resolving and every purchase fails, so they have to be re-created and re-pasted
-- there. `productId = 0` is still the "not set up yet" sentinel, and RobuxShopService refuses to
-- prompt on it rather than opening a dialog that cannot complete.
-- ===== FIVE TIERS PER CURRENCY, AND WHY THE LADDER IS SHAPED THIS WAY =====
--
-- There used to be two DNA packs and two Diamond packs. Two price points is not a shop, it is a
-- yes/no question: a player who finds the small one too small and the large one too expensive has
-- nowhere to land, and the whole 199-499 band -- which is where this genre actually earns -- was
-- simply absent. Five tiers at 49 / 99 / 199 / 499 / 999 is the shape every comparable game runs
-- (see the market notes in ROADMAP.md), and it is a LADDER rather than a list: each rung must be
-- better VALUE PER ROBUX than the one below it, never merely bigger. That one rule is what makes
-- trading up read as a discount instead of a bigger bill, and it is not left to trust -- see
-- GetValuePerRobux and GetTierBonusPct below, which the shop UI draws its bonus ribbons from, so a
-- tile can never advertise a discount this table does not actually contain.
--
-- `price` is authored here only so the shop can render a price before Roblox answers, and so the
-- ribbons have something to divide by. It is NOT what the player is charged -- MarketplaceService
-- charges whatever the dashboard says. Keep the two in step when the real ids are pasted in.
--
-- DNA IS SCALED, DIAMONDS ARE NOT. The DNA figures are authored as "what this is worth in stage-one
-- clicks" and RobuxShopService puts them through GameConfig.ScaleReward, so a pack buys the same
-- number of kills at stage 1 and at stage 20. Diamonds are deliberately raw: every diamond sink in
-- the game is a small fixed number (the three DiamondUpgrades at 25 / 40 / 75, Stage Mastery) that
-- does not ride the stage curve, so scaling them would cap every permanent upgrade in one purchase.
-- The full reasoning sits in the grant block of RobuxShopService.
GameConfig.RobuxProducts = {
	{ key = "DNA_1", productId = 3702245508, price = 49,  tierGroup = "DNA", name = "Small DNA Pack",  emoji = "🧬", grantDNA = 1000 },
	{ key = "DNA_2", productId = 3702247541, price = 99,  tierGroup = "DNA", name = "Medium DNA Pack", emoji = "🧬", grantDNA = 2500 },
	{ key = "DNA_3", productId = 3702248045, price = 199, tierGroup = "DNA", name = "Large DNA Pack",  emoji = "🧬", grantDNA = 6000 },
	{ key = "DNA_4", productId = 3702248511, price = 499, tierGroup = "DNA", name = "Huge DNA Pack",   emoji = "🧬", grantDNA = 18000 },
	{ key = "DNA_5", productId = 3702248961, price = 999, tierGroup = "DNA", name = "Mega DNA Pack",   emoji = "🧬", grantDNA = 40000, ribbon = "BEST VALUE" },

	-- Named with their real numbers, unlike the DNA packs above: a diamond count is not scaled, so
	-- "50 Diamonds" is true at every stage, and hiding a true number behind an adjective only costs
	-- the buyer clarity.
	{ key = "Diamonds_1", productId = 3702250279, price = 49,  tierGroup = "Diamonds", name = "10 Diamonds",  emoji = "💎", grantDiamonds = 10 },
	{ key = "Diamonds_2", productId = 3702250748, price = 99,  tierGroup = "Diamonds", name = "22 Diamonds",  emoji = "💎", grantDiamonds = 22 },
	{ key = "Diamonds_3", productId = 3702251204, price = 199, tierGroup = "Diamonds", name = "50 Diamonds",  emoji = "💎", grantDiamonds = 50 },
	{ key = "Diamonds_4", productId = 3702251679, price = 499, tierGroup = "Diamonds", name = "140 Diamonds", emoji = "💎", grantDiamonds = 140 },
	{ key = "Diamonds_5", productId = 3702252142, price = 999, tierGroup = "Diamonds", name = "300 Diamonds", emoji = "💎", grantDiamonds = 300, ribbon = "BEST VALUE" },

	-- ===== EVOLUTION SHARDS (11.12) =====
	--
	-- Named with their real numbers for the same reason the Diamond packs are: a shard is not scaled,
	-- so "125 Evolution Shards" is true at every stage and an adjective would only cost the buyer
	-- clarity.
	--
	-- UNSCALED, LIKE DIAMONDS AND FOR A STRONGER REASON. A shard buys exactly one thing --
	-- `SpinCostShards`, a flat 25 -- so putting these through `ScaleReward` would let a stage-14 buyer
	-- purchase thousands of spins from one tile. The DNA packs are scaled because DNA prices ride the
	-- stage curve; nothing a shard buys does.
	--
	-- THE LADDER IS THE DIAMOND LADDER x2.5, deliberately: 10/22/50/140/300 becomes 25/55/125/350/750
	-- at the same five price points, and only three of those five rungs are cut here. That keeps the
	-- value-per-Robux curve -- which `GetTierBonusPct` derives and the shop's ribbons print -- the
	-- same shape a buyer already learned on the Diamond tiles. 25 is one spin exactly, so the cheapest
	-- rung is legible without arithmetic: it is the wheel, once.
	--
	-- Only 49 / 199 / 999 exist. Five rungs is the right shape for a currency a player spends
	-- continuously; a shard is spent 25 at a time on one machine, and three price points already
	-- cover "one go", "an evening" and "stop thinking about it". Two more rows would be two more ids
	-- to create on the dashboard for a currency with one sink.
	{ key = "Shards_1", productId = 3707419817, price = 49,  tierGroup = "Shards", name = "25 Evolution Shards",  emoji = "\u{1F31F}", grantShards = 25 },
	{ key = "Shards_2", productId = 3707425807, price = 199, tierGroup = "Shards", name = "125 Evolution Shards", emoji = "\u{1F31F}", grantShards = 125 },
	{ key = "Shards_3", productId = 3707431292, price = 999, tierGroup = "Shards", name = "750 Evolution Shards", emoji = "\u{1F31F}", grantShards = 750, ribbon = "BEST VALUE" },

	-- The wheel. Priced against the 99 R$ DNA pack it sits next to -- see the SpinWheel comment for
	-- why its expected DNA is deliberately the lower of the two.
	{ key = "LuckySpin",   productId = 3702253641, price = 99,  name = "Lucky Spin",    emoji = "\u{1F3A1}", grantSpin = true },

	-- A COUNTED CHARGE, not a moment. `grantBossRevives` adds to data.BossRevives and BossService
	-- spends one when there is something to restore; the receipt can therefore arrive late, on
	-- another server, or after a rejoin without the player losing what they paid for. That is not a
	-- nicety -- ProcessReceipt is retried on Roblox's own schedule and does a DataStore write before
	-- it acknowledges, so any design that had to land inside the 34 s heal window would have a tail
	-- of buyers who paid for nothing. Cheapest product in the shop on purpose: it is bought in a
	-- moment of frustration, and a frustrated player will not spend 199.
	--
	-- ===== AND IT IS WITHDRAWN (11.7), WITHOUT DELETING THE RECEIPT =====
	--
	-- `delisted` hides it from every shop surface. The ROW STAYS, and that is the whole point:
	-- ProcessReceipt is retried on Roblox's own schedule until it is acknowledged, so a purchase
	-- already in flight when this shipped -- or one made seconds before the place updated -- still
	-- arrives, and a receipt with no matching product row is a player charged for nothing, forever,
	-- with the retry never stopping. Deleting the row is the one change here that could actually
	-- take money and give nothing back.
	--
	-- `grantDiamonds` instead of `grantBossRevives`, because a charge for a feature whose UI is gone
	-- is worth nothing. 10 diamonds is exactly what Diamonds_1 sells for the same 49 R$, so an
	-- in-flight buyer is made whole at the shop's own rate rather than at a number invented here.
	-- **Turning off the sale on the Creator Dashboard is the owner half** -- see the checklist.
	{ key = "BossRevive",  productId = 3702254100, price = 49,  name = "Boss Revive",   emoji = "\u{2694}\u{FE0F}", grantDiamonds = 10, delisted = true },

	-- ===== THE RAINBOW CATALYST, AND WHY IT IS NOT WHAT THE ROADMAP ASKED FOR =====
	--
	-- ROADMAP 3.5 asked for a "Rainbow Fusion" product, "one tier above the existing Golden fusion".
	-- That premise is simply wrong about this game: PetTiers has run Normal / Golden / Rainbow /
	-- Celestial since long before this phase, GetNextTier has no gate in it, and PetService.HandleFuse
	-- refuses exactly two things -- being at Celestial already, and not holding four copies. A player
	-- with four Goldens gets a Rainbow today, free. Selling it would have been charging 199 R$ for
	-- something already shipped, which is the one thing the GamePasses block above refuses to do (see
	-- the note on auto-attack: sell the RATE, never the thing).
	--
	-- So the product sells the GRIND instead of the tier. The wall is not tier access, it is needing
	-- four identical copies of the same species AND tier: a Rainbow costs 16 Normals of one species
	-- end to end, a Celestial 64. A catalyst raises one owned pet one tier with no copies at all.
	--
	-- IT STOPS BELOW THE TOP. HandleTierUp refuses a step INTO Celestial, and that cap is doing real
	-- work rather than being decoration. Equipped pet bonuses MULTIPLY across slots (up to nine of
	-- them with the PetSlots3 pass), so an unbounded tier-up sold by the token is a compounding
	-- income multiplier priced like a consumable. Capped at Rainbow it sells the tedious middle of the
	-- ladder and leaves the ceiling as something only fusing can reach.
	--
	-- REPRICED AND RE-HOMED (11.7). 99/249 -> 49/129, and `panel = "fusion"` moves both cards out of
	-- the Robux grid and onto the fusion panel. The product ids are untouched -- a price on the
	-- Creator Dashboard is a separate field from the one below, and this number is only what the card
	-- prints; the dashboard is the owner's to match.
	--
	-- Selling it beside the grid was the mistake. A catalyst answers a question the player only has
	-- while looking at "(2/3)" under a pet they cannot fuse yet, and that question is asked on the
	-- fusion panel, not in a wall of currency packs. Cheaper too, because 11.7 also cut the fusion
	-- requirement to three: the grind it shortcuts is now 9 copies rather than 16, so the shortcut
	-- has to cost less than it did when it was worth more.
	--
	-- `panel` hides it from the grid; `panelCard` asks the fusion panel to draw a card of its own.
	-- ONLY THE BUNDLE GETS ONE. The single catalyst is already offered on **every pet row** in that
	-- panel -- that is what `CatalystRow`'s R$ button is -- so a second generic card selling the same
	-- thing two inches below would be the same product twice on one screen. The x3 has nowhere else
	-- to be, because a per-pet row is about one pet and a bundle is not.
	{ key = "TierUp_1", productId = 3702254553, price = 49,  tierGroup = "TierUp", panel = "fusion", name = "Rainbow Catalyst",  emoji = "\u{1F308}", grantTierUps = 1 },
	{ key = "TierUp_3", productId = 3702254989, price = 129, tierGroup = "TierUp", panel = "fusion", panelCard = true, name = "Catalyst x3", emoji = "\u{1F308}", grantTierUps = 3, ribbon = "BEST VALUE" },

	{ key = "Potions_3",   productId = 3702255918, price = 99,  name = "Potion Pack",   emoji = "🧪", grantPotions = 3, grantPotionId = "dna_m" },
	{ key = "Potions_10",  productId = 3702256409, price = 199, name = "Potion Crate",  emoji = "🧪", grantPotions = 4, grantPotionId = "dna_l" },
	-- The Season Pass premium track. `grantSeasonPremium` is read by RobuxShopService's
	-- ProcessReceipt; buying it late is safe, because every premium reward already reached stays
	-- claimable (see SeasonPassService.GrantPremium).
	{ key = "SeasonPremium", productId = 3702256841, price = 399, name = "Premium Season Pass", emoji = "\u{1F39F}\u{FE0F}", grantSeasonPremium = true },
}

function GameConfig.GetRobuxProduct(key)
	for _, p in ipairs(GameConfig.RobuxProducts) do
		if p.key == key then return p end
	end
	return nil
end

-- What one Robux buys on this product, in whatever unit the product pays out. Comparable only
-- WITHIN a tierGroup -- DNA against DNA, Diamonds against Diamonds -- which is exactly how the shop
-- uses it. Returns 0 for products that pay a flag rather than an amount (the Season Pass), so those
-- simply never draw a ribbon.
function GameConfig.GetValuePerRobux(product)
	if not product or not product.price or product.price <= 0 then return 0 end
	-- `grantShards` belongs in this list for the same reason every other grant does: the ribbon a tile
	-- prints is derived here, so a grant field missing from it makes its whole tier group silently
	-- ribbon-less -- which reads as "no bonus", not as "not implemented".
	local amount = product.grantDNA or product.grantDiamonds or product.grantShards
		or product.grantPotions or product.grantTierUps
	if not amount then return 0 end
	return amount / product.price
end

-- How much more this tier pays per Robux than the CHEAPEST tier in its group, as a percentage.
-- DERIVED, never authored: the shop's "+47% BONUS" ribbon comes from here, so the claim on the tile
-- and the numbers in the table cannot drift apart. Returns 0 for the base tier of a group and for
-- anything with no group at all.
function GameConfig.GetTierBonusPct(product)
	if not product or not product.tierGroup then return 0 end
	local base
	for _, p in ipairs(GameConfig.RobuxProducts) do
		if p.tierGroup == product.tierGroup then
			if not base or p.price < base.price then base = p end
		end
	end
	if not base or base == product then return 0 end
	local baseValue = GameConfig.GetValuePerRobux(base)
	if baseValue <= 0 then return 0 end
	return math.floor((GameConfig.GetValuePerRobux(product) / baseValue - 1) * 100 + 0.5)
end

-- THE ONE XP MULTIPLIER. The creature kill and the boss kill each called GetPotionMult(data, "xp")
-- directly, so the 2x XP pass would have had to be added in two places and kept in step with itself
-- forever -- and a third XP source added later would have quietly missed both. Everything that
-- scales XP goes through here now.
function GameConfig.GetXPMult(data)
	-- The event multiplier lands here too, and this is the extraction paying for itself a second
	-- time: the weekend's double XP reached the creature kill AND the boss kill by being written
	-- once, in the one function both of them already went through.
	return GameConfig.GetPotionMult(data, "xp") * GameConfig.GetPassMult(data, "xpMult")
		-- ...and the relics, for the third time the extraction pays for itself: two relic rows carry
		-- an XP line and neither the creature kill nor the boss kill had to learn that relics exist.
		* GameConfig.GetRelicMult(data, "xpMult")
		* GameConfig.GetEventMult("xpMult")
end

-- ===== GAME PASSES =====
-- One-off, permanent, account-wide Robux purchases -- as opposed to the consumable Developer
-- Products above.
--
-- THE IDS BELOW ARE REAL AS OF 2026-08-11. All nine were created against universe
-- **10675543038 ("Evolution Lab BETA V0.2")** and each one was put ON SALE at the price in its row
-- (a pass created without "Item for sale" enabled exists and has an id, but nobody can buy it --
-- that is the single easiest step to miss). Verified through the product-info endpoint: correct
-- name, correct price, `IsForSale = true` on all nine.
--
-- These are **Game Pass ids**, not asset ids. `UserOwnsGamePassAsync` takes the Game Pass id, and
-- an asset id pasted here would make the call return false forever with no error anywhere -- the
-- pass would simply never work for anyone who bought it.
--
-- `passId = 0` remains the "not set up yet" sentinel; PassService refuses to prompt on a zero id
-- rather than opening a dialog that cannot complete.
--
-- EVERY EFFECT IS A FIELD READ BY GetPassMult / GetPassAdd BELOW, never a special case at the call
-- site. That is what lets the 2x DNA pass and the VIP bundle both raise income without either hook
-- knowing the other exists, and it is why a tenth pass needs no new code anywhere -- only a row.
--
-- Three decisions worth not re-litigating:
--
-- 1. LUCK IS ADDITIVE, NOT A MULTIPLIER. Every other luck source in this game adds percentage
--    points (pet `luckAdd`, the Luck potion, the shop's Egg Luck upgrade at +5 a level) and luck
--    starts at ZERO. A "2x Luck" pass would therefore do literally nothing for a new player -- the
--    exact person most likely to buy it. See GameConfig.GetLuckPercent, which mutations, crit
--    chance, the mystery potion and the wheel all read, and GetPetLuckPercent beside it, which is
--    that total plus the shop upgrade and is what an egg rolls against.
--
-- 2. AUTO-ATTACK ITSELF STAYS FREE. It already ships free on the `AutoAttack` attribute and the T
--    key. Paywalling something players already have is the fastest way to lose them, so FastAuto
--    sells the swing RATE instead -- new value rather than confiscated value.
--
-- 3. ORDERED CHEAPEST FIRST, and the cheapest is deliberately a small quality-of-life pass. Across
--    the genre the entry pass is what converts a non-payer into a payer; the multipliers are where
--    the money actually is, but almost nobody buys one first.
GameConfig.GamePasses = {
	-- `walkCap` lifts GameConfig.MaxWalkSpeed for this player. Without it the pass is a lie for most
	-- of the game: the cap is 150, and an unbought stage-20 body already runs 127, so a 2x would have
	-- delivered 1.18x at the top and a true 2x only through stage 7 of 20. 260 covers the doubled
	-- top-stage speed (254.5) with a little headroom. The cap exists to stop a player outrunning
	-- StreamingEnabled, which is why lifting it is a deliberate, measured decision and not a default.
	{ key = "Speed2x",   passId = 1940815736, price = 99,  emoji = "🏃", name = "2x Speed",
	  desc = "Move twice as fast, in every zone.", walkMult = 2, walkCap = 260 },

	{ key = "XP2x",      passId = 1943659639, price = 149, emoji = "⭐", name = "2x XP",
	  desc = "Every kill fills the evolve bar twice as fast.", xpMult = 2 },

	{ key = "AutoHatch", passId = 1940215660, price = 149, emoji = "🥚", name = "Auto Hatch",
	  desc = "Eggs keep hatching while you stand at the stall.", autoHatch = true },

	{ key = "DNA2x",     passId = 1941325697, price = 199, emoji = "🧬", name = "2x DNA",
	  desc = "Double DNA from clicks, kills and idle income.", incomeMult = 2 },

	{ key = "Damage2x",  passId = 1941175630, price = 199, emoji = "⚔️", name = "2x Damage",
	  desc = "Hit twice as hard. Bosses die in half the swings.", damageMult = 2 },

	{ key = "FastAuto",  passId = 1941379666, price = 199, emoji = "⚡", name = "Fast Auto Attack",
	  desc = "Your auto attack swings 70% faster.", autoSpeedMult = 1.7 },

	{ key = "Lucky",     passId = 1940107710, price = 249, emoji = "🍀", name = "Lucky",
	  desc = "+50% Luck on every egg, pet and mutation roll.", luckAdd = 50 },

	{ key = "PetSlots3", passId = 1944156329, price = 299, emoji = "🐾", name = "+3 Pet Slots",
	  desc = "Equip three more pets at once.", petSlots = 3 },

	{ key = "VIP",       passId = 1941409673, price = 499, emoji = "👑", name = "VIP",
	  -- The two figures in this sentence are the last row of GameConfig.VipCharacters. They are
	  -- literals because this table is a plain list of strings that a dozen readers format, and
	  -- GameConfig.GetVipLadderTop is here so a UI that wants the live number never has to trust
	  -- this one. Move the wardrobe's top row and move this line with it.
	  desc = "9 exclusive Roblox skins worth up to x15 damage and x1.5 DNA, 1.5x DNA and damage, +15% Luck, a golden aura, a chat tag and 5 Diamonds a day.",
	  incomeMult = 1.5, damageMult = 1.5, luckAdd = 15, dailyDiamonds = 5, vip = true },
}

function GameConfig.GetGamePass(key)
	for _, p in ipairs(GameConfig.GamePasses) do
		if p.key == key then return p end
	end
	return nil
end

-- `data.Passes` is a RUNTIME cache written by PassService on join and on purchase. It is never
-- trusted out of the save -- PlayerDataService clears it on load -- so a missing or empty table
-- means "owns nothing", which is the correct fail-closed answer when the ownership check could not
-- be completed. Reading it here rather than taking a `player` is the whole reason none of the stat
-- functions had to change signature: GetIncomeMult, GetLuckPercent, GetCombatDamage and
-- GetMaxEquippedPets all already take `data`.
function GameConfig.OwnsPass(data, key)
	return (data and data.Passes and data.Passes[key]) == true
end

-- Product of `field` across every owned pass, or 1 when none of them carries it. Multiplicative on
-- purpose: a player holding both 2x DNA and VIP gets 3x, which is the entire reason to own two.
function GameConfig.GetPassMult(data, field)
	if not (data and data.Passes) then return 1 end
	local mult = 1
	for _, p in ipairs(GameConfig.GamePasses) do
		if data.Passes[p.key] and p[field] then
			mult = mult * p[field]
		end
	end
	return mult
end

-- Highest `field` across every owned pass, or `fallback`. BEST-ONE-APPLIES, the same rule
-- GetMutationIncomeMult uses -- for a value that is a ceiling rather than a contribution, summing
-- two of them would be meaningless and multiplying them would be worse.
function GameConfig.GetPassMax(data, field, fallback)
	local best = fallback or 0
	if not (data and data.Passes) then return best end
	for _, p in ipairs(GameConfig.GamePasses) do
		if data.Passes[p.key] and p[field] and p[field] > best then
			best = p[field]
		end
	end
	return best
end

-- Sum of `field` across every owned pass, or 0. For the stats measured in points rather than in
-- factors -- luck and pet slots today.
function GameConfig.GetPassAdd(data, field)
	if not (data and data.Passes) then return 0 end
	local total = 0
	for _, p in ipairs(GameConfig.GamePasses) do
		if data.Passes[p.key] and p[field] then
			total = total + p[field]
		end
	end
	return total
end

end
