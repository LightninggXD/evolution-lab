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
-- THE GAME PASSES ARE HERE NOW, AND THE REASON IS A LIVE REVENUE BUG (19.12).
--
-- This note used to read "they keep their own panel". They did -- `RobuxPanel`, built by
-- `HUD/PassShop` into `hud.robuxGrid` -- and when 18.11 repointed the Robux HUD tile at THIS file,
-- that panel stopped being opened by anything. Nothing errored, nothing warned, and every property
-- on it still read correct: it is simply an orphan. Measured on the live client, the nine passes
-- were sitting in `RobuxPanel.PassScroll` with `Visible = false` and no door in the game --
-- **2,041 R$ of storefront that no player could reach**, three weeks from launch.
--
-- They still are a different purchase and the difference is kept: the door is
-- `PromptGamePassPurchase` (the server holds the pass id, same rule as the products above), and
-- the question is "do I already own it" rather than "what does it cost", so an owned pass shows a
-- pale-green OWNED button rather than a price -- 18.6's rule that a receipt is not a refusal. That
-- state has to be re-read on every payload, which is what `panel.OnRefresh` below is for; the
-- product cards need nothing of the kind, which is why this file had no refresh hook until now.
--
-- The passes sort AFTER the products (`LayoutOrder` 1000+) rather than interleaved: a pass is a
-- permanent multiplier and a product is a one-off grant, and mixing the two ladders is what makes
-- a store hard to read.
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
local UITheme = require(RS.Modules.UITheme)

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

-- The pass wash and the OWNED fill. Gold, because a pass is the permanent purchase on this screen
-- and nothing else here is gold; and a pale green for OWNED that is the same `DoneShade` answer the
-- Season track, Stage Mastery and the Auras row all reached in 18.6 -- a thing already bought is a
-- receipt, and painting it in the kit's refusal grey is what made the old pass column read as a
-- wall of dead rows.
local WASH_PASS = { Color3.fromRGB(255, 214, 120), Color3.fromRGB(228, 150, 20) }
local OWNED_FILL = { Color3.fromRGB(214, 238, 224), Color3.fromRGB(150, 205, 175) }
local RIBBON_PASS = { Color3.fromRGB(255, 226, 130), Color3.fromRGB(240, 165, 20) }

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

--- The same sentence as `grantLine`, in the width a HERO line actually has (21.6).
---
--- MEASURED, NOT GUESSED. `AddHero`'s line label is **340 px** and its text is 20 px, and
--- `grantLine`'s output for the Starter Pack -- "2500 DNA  ·  30 Diamonds  ·  25 Evolution Shards"
--- -- draws at roughly 435. It was silently cut to "... · 25…" on the live card, which a probe
--- cannot see and only the capture found. Note the trap in reading that back: `TextBounds` reported
--- 266, because **TextBounds measures the truncation, not the string**.
---
--- So the two differ in vocabulary and NOT in derivation. Both read the same grant fields off the
--- same product, so a fourth line added to the pack in `RobuxShop` still arrives here on its own;
--- this one just spends fewer characters on each -- "Shards" for "Evolution Shards", a thin
--- separator -- and puts DNA through the game's own suffixes, which is what the join card prints
--- and what every wallet in the HUD shows. Budget: 34 characters at 20 px is ~310 of the 340.
local function bundleLine(p)
	local bits = {}
	if p.grantDNA then bits[#bits + 1] = ("%s DNA"):format(UITheme.FormatNumber(p.grantDNA)) end
	if p.grantDiamonds then bits[#bits + 1] = ("%d Diamonds"):format(p.grantDiamonds) end
	if p.grantShards then bits[#bits + 1] = ("%d Shards"):format(p.grantShards) end
	if p.grantSpins then bits[#bits + 1] = ("%d Spins"):format(p.grantSpins) end
	if p.grantPotions then bits[#bits + 1] = ("%d Potions"):format(p.grantPotions) end
	return table.concat(bits, " \u{00B7} ")
end

-- `ProductTiles`' predicate, copied rather than re-reasoned -- see fault 2 in the header. Boss Revive
-- is withdrawn and the two Catalysts live on the fusion panel; both must stay in the config table
-- (a receipt with no product row is a player charged for nothing) and neither may be sold here.
local function inStore(product)
	return product.productId ~= nil and not product.delisted and product.panel == nil
end

-- Set by `Init`, read by the refresh: pass key -> the card's button handle. A table rather than a
-- rebuild, because a rebuild throws the scroll position away every time a payload lands.
-- ===== THE STOREFRONT (17.15) =====
--
-- Her note was a reference screenshot beside a capture of ours -- *"ovo isto znaci imas ovo u
-- shopu"*. The reference is one big featured card, then a grid of small pass cards under a header.
-- Ours was twenty-six identical wide rows in one scroll, sorted products-then-passes, which put
-- VIP -- the most expensive thing in the game -- SEVENTEEN ROWS BELOW THE FOLD with nothing
-- marking it out from a 49 R$ DNA pack.
--
-- Three shapes, all of them `ScrollingPanelBuilder`'s: `AddHero` for VIP, `AddGrid` for the other
-- nine passes, and `AddSection` for the two headings. The products keep their rows, because a row
-- is the right shape for a LADDER -- five DNA packs differ only by how much and how much for, and
-- a grid of tiles is exactly where that comparison gets harder to make.
--
-- WHAT THE HERO SAYS IS DERIVED, NOT TYPED. `heroLines` reads the pass's own grant fields and the
-- wardrobe's top rung (`GetVipLadderTop`), the same numbers `DNAService` multiplies by and the
-- Forest plaque quotes -- so raising a VIP skin's ladder raises the advertisement with it and the
-- store cannot promise a multiplier the server does not pay. `pass.desc`'s own sentence is not
-- used here for exactly that reason: it is a literal, and it already says "9 exclusive skins"
-- where the table now holds ten.
local function fmtMult(n)
	return (("%.10g"):format(tonumber(n) or 1))
end

--- The hero's three icon lines, in the order a shopper cares about: what is exclusive to it, what
--- it multiplies, and what it hands over daily. Three because the card has room for three -- the
--- fourth would reach the button (see `AddHero`).
local function heroLines(pass)
	local lines = {}
	local top = GameConfig.GetVipLadderTop and GameConfig.GetVipLadderTop("vipDamageMult") or 1
	lines[#lines + 1] = {
		Icon = IconLibrary.Resolve("\u{1F451}") or "",
		Text = ("%d exclusive skins, up to x%s damage"):format(#GameConfig.VipCharacters, fmtMult(top)),
	}

	local always = {}
	if pass.damageMult then always[#always + 1] = ("x%s damage"):format(fmtMult(pass.damageMult)) end
	if pass.incomeMult then always[#always + 1] = ("x%s DNA"):format(fmtMult(pass.incomeMult)) end
	if #always > 0 then
		lines[#lines + 1] = {
			Icon = IconLibrary.Resolve("\u{2694}\u{FE0F}") or "",
			Text = table.concat(always, " and ") .. ", always",
		}
	end

	local daily = {}
	if pass.luckAdd then daily[#daily + 1] = ("+%d%% Luck"):format(pass.luckAdd) end
	if pass.dailyDiamonds then daily[#daily + 1] = ("%d Diamonds a day"):format(pass.dailyDiamonds) end
	if #daily > 0 then
		lines[#lines + 1] = {
			Icon = IconLibrary.Resolve("\u{1F340}") or "",
			Text = table.concat(daily, "  \u{00B7}  "),
		}
	end
	return lines
end

-- The first pack in the list, so the `+` on a currency capsule can land on the packs rather than
-- on the hero. Set while the products are built and read by `FocusPacks`.
local firstProductName = nil

local passButtons = {}
-- Which passes the player already holds, as the callback sees it. The button's own `enabled` flag
-- cannot carry this (see `paintPassButton`), so the guard lives here -- and it is a guard against
-- prompting a second purchase for something already owned, not a security boundary: `PassService`
-- re-checks ownership itself, because a client can fire any remote it likes.
local ownedKeys = {}

--- The one place that decides what a pass button says and what colour it is, so the build and the
--- refresh cannot disagree about it. `owned` comes from `data.Passes`, which `PassService` caches
--- and fails CLOSED on an API error -- so an unreadable ownership check shows a price, never a
--- free OWNED.
local function paintPassButton(handle, pass, owned)
	if owned then
		handle.SetPrice("OWNED")
		-- INERT WITHOUT `SetEnabled(false)`, AND THAT IS NOT A STYLE CHOICE. The builder's
		-- `SetEnabled` reads `enabled and (colors or bOpt.Colors) or DISABLED`, so on the disabled
		-- branch the colour argument is unreachable -- measured: passing `OWNED_FILL` there paints
		-- rgb(178,178,190), the kit's refusal grey. That is 18.6's bug with the kit enforcing it.
		-- So the button stays "enabled" to keep its fill, `AutoButtonColor` is cleared so it does
		-- not pretend to depress, and `ownedKeys` below is what actually stops the purchase.
		handle.SetEnabled(true, OWNED_FILL)
		handle.SetColors(OWNED_FILL)
		handle.Instance.AutoButtonColor = false
	else
		handle.SetPrice("R$ " .. tostring(pass.price or "?"))
		handle.SetEnabled(true, ROBUX)
		handle.SetColors(ROBUX)
		handle.Instance.AutoButtonColor = true
	end
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

	-- ===== THE PASSES COME FIRST NOW, AND VIP COMES FIRST OF THOSE (17.15) =====
	--
	-- The order used to be products (LayoutOrder 1..20) then passes (1000+), on the argument that a
	-- pass and a product are two ladders and mixing them makes a store hard to read. That argument
	-- still holds and the split is still here -- what changed is which end of the list each one is
	-- at. A pass is the permanent purchase and VIP is the one the game earns most on; putting the
	-- consumables above them meant the store opened on its cheapest shelf.
	--
	-- The `+` on a currency capsule is the door that cared, and it is answered rather than ignored:
	-- `FocusPacks` scrolls to the first pack, and `CurrencyPlus` asks for it by pressing
	-- `openStorePacks`. A player who pressed `+` on DNA is asking for DNA, not for VIP.
	-- ===== THE STARTER PACK SITS ABOVE VIP WHILE IT IS STILL OFFERED (21.6) =====
	--
	-- The join card is the interruption and this is the DOOR. Without it a player who closed the card
	-- -- or who was already busy when it would have opened, which `HUD/StarterPack` deliberately
	-- allows -- could never buy the pack at all: the product carries `panel = "starter"`, so `inStore`
	-- keeps it off the packs wall below. That is 34.5's fault exactly (a TRANSFER button nothing ever
	-- assigned) and it is worth one card to not repeat it.
	--
	-- ABOVE VIP, and only for as long as it is honest. LayoutOrder -1 puts it at the top of the store
	-- for a player who has never spent, which is the one shopper for whom a 499 R$ pass is the wrong
	-- first thing to see. It is DRAWN ONCE and hidden by the refresh, never rebuilt: a rebuild throws
	-- the scroll position away on every payload, and the payload this reacts to is the purchase.
	--
	-- BUILT EVEN WHEN IT IS NOT ELIGIBLE, because `Init` runs once and eligibility is a property of
	-- the save that changes underneath it. `Visible` is the whole mechanism, and it is answered by
	-- `GameConfig.IsStarterPackEligible` in the refresh below -- the SAME predicate the server fires
	-- the join card on, so the card and the hero can never disagree about who this is for.
	local starter = GameConfig.GetRobuxProduct("StarterPack")
	local starterHero = nil
	if starter then
		starterHero = panel.AddHero({
			Name = "Product_" .. starter.key,
			LayoutOrder = -1,
			Title = starter.name,
			Icon = IconLibrary.Resolve(starter.emoji) or "",
			IconPlate = true,
			BackgroundColors = { Color3.fromRGB(255, 226, 138), Color3.fromRGB(232, 150, 40) },
			-- The one ribbon in this store that is a fact about the OFFER rather than about value:
			-- it is shown to a player who has never spent and disappears for good when they do.
			Ribbon = { Text = "ONE TIME ONLY", Colors = RIBBON_BEST },
			-- DERIVED, like the hero's VIP lines beside it. `GetBundleValue` prices each grant at the
			-- cheapest rung in this same table that sells the same thing, so the store cannot promise
			-- a saving the receipt does not pay.
			Lines = {
				-- `bundleLine`, not `grantLine`: same fields, same derivation, fewer characters --
				-- a hero line is 340 px and `grantLine`'s wording overruns it. See its own note.
				{ Icon = IconLibrary.Resolve("\u{1F9EC}") or "", Text = bundleLine(starter) },
				{ Icon = IconLibrary.Resolve("\u{1F4B0}") or "", Text = ("Worth R$ %d bought separately"):format(
					GameConfig.GetBundleValue(starter)) },
				{ Icon = IconLibrary.Resolve("\u{1F381}") or "", Text = "Your first purchase, once" },
			},
			Button = {
				Name = "Buy",
				Price = "R$ " .. tostring(starter.price or "?"),
				Icon = "",
				Colors = ROBUX,
				Callback = function()
					Remotes.PromptRobuxPurchase:FireServer(starter.key)
				end,
			},
		})
	end

	local vipPass, gridPasses = nil, {}
	for _, pass in ipairs(GameConfig.GamePasses) do
		-- A pass with no real id cannot be prompted for and must not be drawn: an unbuyable card on
		-- the screen the game earns on is worse than a missing one. `RelicSlots2` is the one sitting
		-- at 0 today, which is 26.4's sentinel for "the dashboard row does not exist yet".
		if pass.passId and pass.passId ~= 0 then
			if pass.vip then
				vipPass = pass
			else
				gridPasses[#gridPasses + 1] = pass
			end
		end
	end

	if vipPass then
		local hero = panel.AddHero({
			Name = "Pass_" .. vipPass.key,
			LayoutOrder = 0,
			Title = vipPass.name,
			Icon = IconLibrary.Resolve(vipPass.emoji) or "",
			IconPlate = true,
			BackgroundColors = WASH_PASS,
			-- "GAME PASS", not "NEW!". The reference's ribbon is a red NEW! and this pass is two
			-- months old -- a flash that says something untrue is worth less than the space. What
			-- the ribbon has to carry here is the one thing a shopper cannot tell from the price:
			-- that this is permanent and not a consumable.
			Ribbon = { Text = "GAME PASS", Colors = RIBBON_PASS },
			Lines = heroLines(vipPass),
			Button = {
				Name = "Buy",
				Price = "R$ " .. tostring(vipPass.price or "?"),
				Icon = "",
				Colors = ROBUX,
				Callback = function()
					if ownedKeys[vipPass.key] then return end
					Remotes.PromptGamePassPurchase:FireServer(vipPass.key)
				end,
			},
		})
		passButtons[vipPass.key] = hero.Button
	end

	panel.AddSection("GAME PASSES", 1)
	local grid = panel.AddGrid(2)
	for i, pass in ipairs(gridPasses) do
		local tile = grid.AddTile({
			Name = "Pass_" .. pass.key,
			LayoutOrder = i,
			-- THE TILE DROPS `pass.desc` AND KEEPS THE NAME, which is the trade a 186 px tile makes:
			-- "Move twice as fast, in every zone." is 300 px at any size worth reading, and eight of
			-- these nine names ARE the effect ("2x Damage", "+3 Pet Slots"). The sentence is not lost
			-- -- the Roblox purchase prompt the button opens carries the pass's own description.
			Title = pass.name,
			Icon = IconLibrary.Resolve(pass.emoji) or "",
			BackgroundColors = WASH_PASS,
			Button = {
				Name = "Buy",
				Price = "R$ " .. tostring(pass.price or "?"),
				Icon = "",
				Colors = ROBUX,
				-- the KEY, never the pass id, for the same reason the products send a key: the
				-- server looks the id up, so a tampered client can only ever name a pass that exists
				Callback = function()
					if ownedKeys[pass.key] then return end
					Remotes.PromptGamePassPurchase:FireServer(pass.key)
				end,
			},
		})
		passButtons[pass.key] = tile.Button
	end

	panel.AddSection("PACKS AND BUNDLES", 3)
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

			-- 10 + i, under the two sections and the grid. It was `i`, from when the products were
			-- the top of the list.
			firstProductName = firstProductName or product.key
			panel.AddCard({
				Name = product.key,
				LayoutOrder = 10 + i,
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

	-- Ownership is the one thing on this panel that changes while the game is running -- a purchase
	-- lands as a `DataUpdate` with `data.Passes` rewritten -- so it is repainted rather than rebuilt.
	panel.OnRefresh(function()
		local data = ShopPanel.getData and ShopPanel.getData()
		local owned = (data and data.Passes) or {}
		-- The hero closes for good the moment `RobuxSpent` moves or a pass is owned. Asked on every
		-- payload rather than once at build, because the payload that matters IS the purchase: the
		-- receipt lands, `data.RobuxSpent` moves, and the card that sold it takes itself off the
		-- screen without the store being reopened.
		if starterHero then
			starterHero.Instance.Visible = GameConfig.IsStarterPackEligible(data)
		end
		for _, pass in ipairs(GameConfig.GamePasses) do
			local handle = passButtons[pass.key]
			local has = owned[pass.key] == true
			ownedKeys[pass.key] = has
			if handle then paintPassButton(handle, pass, has) end
		end
	end)
	panel.Refresh()

	return panel
end

--- Set by MainUI so the refresh above can read the live save. A FUNCTION, not a table: the payload
--- is replaced wholesale on every push, so a cached copy would be frozen at the first one -- or nil,
--- which is exactly the window a new player is looking at the screen in.
function ShopPanel.SetDataSource(fn)
	ShopPanel.getData = fn
	if panel then panel.Refresh() end
end

--- Repaint the pass buttons against the current payload. Safe before `Init` -- a purchase can land
--- while the store has never been opened, and there is nothing to repaint then.
function ShopPanel.Refresh()
	if panel then panel.Refresh() end
end

function ShopPanel.Toggle()
	if panel then panel.Toggle() end
end

--- Open (or close) the store outright, for the doors that are a request rather than a toggle.
---
--- 18.12 gave the four doors that used to open the deleted `RobuxPanel` -- the two currency `+`
--- buttons, the egg panel's Auto Hatch button, and the in-world kiosk counter -- a single way in.
--- Every one of them is a player asking for the store by name at the moment they came up short, so
--- none of them wants `Toggle`, which would close it again on a second press.
function ShopPanel.SetOpen(open)
	if panel then panel.SetOpen(open and true or false) end
end

--- Scroll an already-open store to one card, by the `Name` it was built with.
---
--- ONLY EVER A SCROLL. It cannot open the panel, change what is listed, or change what is buyable
--- -- a caller that gets the name wrong leaves the store exactly where `SetOpen` put it, which is
--- the top. That matters because the one caller today is the Auto Hatch button, i.e. a path a
--- player who owns nothing takes.
---
--- WHY IT IS NEEDED AT ALL: the nine passes sort after the seventeen products (`LayoutOrder`
--- 1000+), so a door opened BY a pass lands on the products with its own subject below the fold.
---
--- DEFERRED BY ONE FRAME, and that is the whole trick. `Builder.SetOpen` rewinds `CanvasPosition`
--- to zero AFTER it runs the refresh -- deliberately, so a panel reopened at the bottom of its own
--- list does not stay there -- so a scroll written in the same tick is overwritten by the rewind
--- that follows it. `AbsolutePosition` also needs a layout pass to be true of a frame that was
--- hidden a moment ago; both are answered by waiting for the same heartbeat.
function ShopPanel.Focus(cardName)
	if not (panel and cardName) then return end
	task.defer(function()
		-- RECURSIVE SINCE 17.15, and it has to be: the nine grid passes are children of the grid
		-- frame, not of the scroll, so a non-recursive lookup found `Pass_AutoHatch` right up to
		-- the moment they moved into a grid and then silently found nothing -- which reads as
		-- "the store opened at the top", i.e. exactly what this function exists to prevent.
		local card = panel.Scroll:FindFirstChild(cardName, true)
		if not (card and panel.IsOpen()) then return end
		-- measured against the scroll's own frame rather than the canvas origin, because the canvas
		-- has a top pad and a list layout between the two and neither is this file's business
		local y = (card.AbsolutePosition.Y - panel.Scroll.AbsolutePosition.Y) + panel.Scroll.CanvasPosition.Y
		-- 12 px of air above the card, and never a negative canvas position
		panel.Scroll.CanvasPosition = Vector2.new(0, math.max(0, y - 12))
	end)
end

--- Scroll an open store to the first DNA / Diamond pack.
---
--- WHY IT EXISTS (17.15): the `+` on a currency capsule is a player saying "I am short of THIS",
--- and until the storefront pass it landed on the top of the list, which was the packs. The top is
--- the VIP hero now, so the door that meant "packs" has to say so. `CurrencyPlus` presses it
--- through `hud.openStorePacks`; every other door still opens at the hero, which is where a player
--- who asked for "the store" should arrive.
function ShopPanel.FocusPacks()
	if firstProductName then ShopPanel.Focus(firstProductName) end
end

return ShopPanel
