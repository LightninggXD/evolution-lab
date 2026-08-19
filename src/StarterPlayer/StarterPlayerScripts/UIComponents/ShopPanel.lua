-- ShopPanel -- the Robux store, in the new panel design.
--
-- WHAT IT REPLACED, and this is the one that mattered most: the first version drew two hard-coded
-- cards ("OP Magic" at 899 and "GM Commond" at 1999) whose buy buttons called
-- `print("Prompt Purchase OP Magic")`. Neither product exists in `GameConfig.RobuxProducts`,
-- neither has a `productId`, and nothing in the file could ever have taken a payment. This is the
-- screen the game earns on, so it is wired to the real ladder.
--
-- THE CARDS ARE `GameConfig.RobuxProducts`, and the button fires `Remotes.PromptRobuxPurchase`,
-- which is the same door `ProductTiles` in the old HUD uses. **The client never prompts
-- MarketplaceService directly**: the server holds the product id, and `ProcessReceipt` is what
-- grants. A client that picked its own id could be made to prompt for the wrong product.
--
-- THE PRICE GOES ON THE BUTTON, which is a rule the old shop already paid for: every tile once read
-- "Buy with R$", so a 49 and a 999 looked like the same decision and the player had to open a
-- Roblox modal to find out which was which.
--
-- THE RIBBON IS ARITHMETIC, NOT A CLAIM. `GetTierBonusPct` divides this tier's payout per Robux by
-- the cheapest tier's, so "+48% BONUS" is something this table actually contains. Nothing here says
-- "most popular" -- that is a claim about other players and nothing in this game measures it.
--
-- WHAT IS NOT HERE: the game passes, which are a different purchase with a different door
-- (`PromptGamePassPurchase`) and a different question -- "do I already own it" rather than "what
-- does it cost". They keep their own panel.
--
-- ===== THE THREE THINGS THE 2026-08-17 PASS FIXED, ALL OF THEM THE SAME OMISSION =====
--
-- This file was written as a straight port of the product ladder and it skipped every one of the
-- old grid's *signals*. Photographed side by side, the store was a wall of identical pale-blue
-- rectangles with a name and a price -- the one screen in the game where the player has to tell
-- twenty things apart, and the only one with nothing to tell them apart BY.
--
--   1. **NO ICONS.** It asked for `product.imageId`, and not one row in `GameConfig.RobuxProducts`
--      has that field -- they carry `emoji`. So `Icon` was always `""`, the builder collapsed the
--      icon column on every card, and twenty products drew as twenty blank cards. Every one of
--      those emojis resolves to real art through `IconLibrary`, which is what the old grid used.
--
--   2. **NO FILTER.** It listed all twenty, including `BossRevive`, which is `delisted` -- a
--      WITHDRAWN product whose row survives only so a retried receipt still resolves -- and the two
--      Catalysts, which carry `panel = "fusion"` because they answer a question you only have while
--      looking at a pet you cannot fuse. The store was selling a product the game had stopped
--      selling. `ProductTiles` has had the predicate for this since 11.7; it is copied, not invented.
--
--   3. **NO RIBBON.** `product.ribbon` ("BEST VALUE") was read by nothing, and the derived bonus was
--      printed as a grey third line of body text -- the same weight as the payout above it.
--
-- AND THE HEADER WORE THE WRONG LOGO. `HeaderIcon` was a hard-coded shopping basket, which is the
-- drawing this game uses for the DNA UPGRADES shop -- a different screen, bought with a different
-- currency. `IconLibrary` has mapped 🛍️ to the Robux logo since the icon pass; this now asks it
-- rather than pasting an id, so the store and the HUD tile that opens it cannot drift apart.

local RS = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("Remotes")
local GameConfig = require(RS.Modules.GameConfig)
local IconLibrary = require(RS.Modules:WaitForChild("IconLibrary"))

local Builder = require(script.Parent:WaitForChild("ScrollingPanelBuilder"))

local ShopPanel = {}
local panel = nil

local WHITE = Color3.fromRGB(255, 255, 255)
local ROBUX = { Color3.fromRGB(120, 255, 170), Color3.fromRGB(20, 200, 100) }

-- The two ribbon fills. Gold is the AUTHORED flash (`product.ribbon`, "BEST VALUE" -- the top rung
-- of a ladder); violet is the DERIVED one (+N% BONUS, computed from the table). Two colours because
-- they are two different claims: one is the shop pointing at its best deal, the other is arithmetic.
local RIBBON_BEST = { Color3.fromRGB(255, 226, 130), Color3.fromRGB(240, 165, 20) }
local RIBBON_BONUS = { Color3.fromRGB(214, 176, 255), Color3.fromRGB(140, 70, 230) }

-- ===== ONE HUE PER THING-YOU-RECEIVE, NOT PER PRICE TIER =====
--
-- Keyed off the GRANT rather than off `tierGroup`, because three of the products have no group at
-- all (the wheel, the two potion bundles, the season pass) and the old table dropped every one of
-- them into a single neutral lavender -- so the four one-offs read as one family that does not
-- exist. What a card pays out is the only thing a shopper is actually sorting by.
--
-- Each is a light stop and a deep stop, the ramp `CardKit` and the potion shelf use: a flat pastel
-- reads as paper, and this is the screen that has to look like it is worth money.
--
-- GREEN IS RESERVED AND DOES NOT APPEAR HERE. Every BUY button is green, and the potion shelf
-- already paid for that lesson -- a green card under a green button makes the button vanish into it.
local WASH = {
	dna      = { Color3.fromRGB(120, 212, 255), Color3.fromRGB(30, 118, 232) },
	diamond  = { Color3.fromRGB(175, 245, 255), Color3.fromRGB(30, 170, 215) },
	shard    = { Color3.fromRGB(255, 222, 120), Color3.fromRGB(240, 150, 20) },
	potion   = { Color3.fromRGB(255, 180, 235), Color3.fromRGB(215, 50, 160) },
	spin     = { Color3.fromRGB(210, 170, 255), Color3.fromRGB(120, 60, 220) },
	season   = { Color3.fromRGB(255, 195, 130), Color3.fromRGB(235, 115, 25) },
	other    = { Color3.fromRGB(200, 200, 225), Color3.fromRGB(130, 132, 165) },
}

local function washFor(p)
	if p.grantDNA then return WASH.dna end
	if p.grantDiamonds then return WASH.diamond end
	if p.grantShards then return WASH.shard end
	if p.grantPotions then return WASH.potion end
	if p.grantSpin then return WASH.spin end
	if p.grantSeasonPremium then return WASH.season end
	return WASH.other
end

--- What this product actually hands over, as a sentence. Read off the grant fields rather than
--- written per product, so a product added to the config cannot arrive here with no description.
local function grantLine(p)
	local bits = {}
	if p.grantDNA then bits[#bits + 1] = ("%s DNA"):format(p.grantDNA) end
	if p.grantDiamonds then bits[#bits + 1] = ("%d Diamonds"):format(p.grantDiamonds) end
	if p.grantShards then bits[#bits + 1] = ("%d Evolution Shards"):format(p.grantShards) end
	if p.grantPotions then bits[#bits + 1] = ("%d Potions"):format(p.grantPotions) end
	if p.grantSpin then bits[#bits + 1] = "1 Lucky Spin" end
	return #bits > 0 and table.concat(bits, "  ·  ") or (p.blurb or "")
end

-- `ProductTiles`' predicate, copied rather than re-reasoned -- see fault 2 in the header. Boss Revive
-- is withdrawn and the two Catalysts live on the fusion panel; both must stay in the config table
-- (a receipt with no product row is a player charged for nothing) and neither may be sold here.
local function inStore(product)
	return product.productId ~= nil and not product.delisted and product.panel == nil
end

function ShopPanel.Init(screenGui)
	if panel then return panel end

	panel = Builder.CreatePanel({
		Parent = screenGui,
		Name = "Store",
		Title = "STORE",
		-- ASKED FOR, NOT PASTED. 🛍️ is the game's Robux glyph everywhere -- the HUD tile, the purchase
		-- toast, the zone shop sign -- so resolving it here is what keeps this header and the button
		-- that opens it showing one logo. The fallback is the same id the library holds, so a future
		-- edit to that mapping cannot leave this header blank.
		HeaderIcon = IconLibrary.Resolve("\u{1F6CD}\u{FE0F}") or "rbxassetid://79711214319288",
		-- Green, because the HUD tile that opens this panel is green. A panel whose accent disagrees
		-- with its own door reads as a different screen -- the rule the Journal follows with Lavender
		-- and the Items panel with Aqua. It was violet, which belonged to nothing on this route.
		HeaderColors = { Color3.fromRGB(130, 240, 165), Color3.fromRGB(20, 155, 90) },
		EmptyText = "The store is unavailable right now",
	})

	for i, product in ipairs(GameConfig.RobuxProducts) do
		if inStore(product) then
			-- THE RIBBON, AND WHY NO CARD CLAIMS TO BE POPULAR. "MOST POPULAR" is the standard flash in
			-- this genre and it is a claim about other players that nothing in this game measures.
			-- What IS measurable is value: `GetTierBonusPct` divides this tier's payout per Robux by
			-- the cheapest tier's in its group, so "+48% BONUS" is something the table contains.
			local ribbon
			if product.ribbon then
				ribbon = { Text = product.ribbon, Colors = RIBBON_BEST }
			else
				local bonus = GameConfig.GetTierBonusPct and GameConfig.GetTierBonusPct(product) or 0
				if bonus > 0 then
					ribbon = { Text = ("+%d%% BONUS"):format(math.floor(bonus)), Colors = RIBBON_BONUS }
				end
			end

			panel.AddCard({
				Name = product.key,
				LayoutOrder = i,
				Title = product.name,
				Subtitle = grantLine(product),
				Ribbon = ribbon,
				-- Through the library, not off the product: `RobuxProducts` rows carry `emoji` and have
				-- never carried an `imageId`, which is exactly why this column was empty. A product whose
				-- glyph has no drawing gets `nil` and the card collapses its icon column, which is the
				-- honest fallback and the one the builder already implements.
				Icon = IconLibrary.Resolve(product.emoji) or "",
				-- The DNA helix is blue and so is the DNA card; the diamond is cyan and so is the
				-- diamond card. Every family here has that collision by construction, because the
				-- card is coloured after the thing the icon draws. The well is what keeps them apart.
				IconPlate = true,
				BackgroundColors = washFor(product),
				Buttons = {
					{
						Name = "Buy",
						Price = "R$ " .. tostring(product.price or "?"),
						Icon = "",
						Colors = ROBUX,
						-- the KEY, never the product id: the server looks the id up itself, so a
						-- tampered client can only ever name a product that exists
						Callback = function()
							Remotes.PromptRobuxPurchase:FireServer(product.key)
						end,
					},
				},
			})
		end
	end

	return panel
end

function ShopPanel.Toggle()
	if panel then panel.Toggle() end
end

return ShopPanel
