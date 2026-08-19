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

-- `ProductTiles`' predicate, copied rather than re-reasoned -- see fault 2 in the header. Boss Revive
-- is withdrawn and the two Catalysts live on the fusion panel; both must stay in the config table
-- (a receipt with no product row is a player charged for nothing) and neither may be sold here.
local function inStore(product)
	return product.productId ~= nil and not product.delisted and product.panel == nil
end

-- Set by `Init`, read by the refresh: pass key -> the card's button handle. A table rather than a
-- rebuild, because a rebuild throws the scroll position away every time a payload lands.
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

	-- ===== THE PASSES =====
	for i, pass in ipairs(GameConfig.GamePasses) do
		-- A pass with no real id cannot be prompted for and must not be drawn: an unbuyable card on
		-- the screen the game earns on is worse than a missing one. Every pass has had a real id
		-- since 2.11, so this is a guard rather than a filter.
		if pass.passId and pass.passId ~= 0 then
			local card = panel.AddCard({
				Name = "Pass_" .. pass.key,
				LayoutOrder = 1000 + i,
				Title = pass.name,
				Subtitle = pass.desc or "",
				Ribbon = { Text = "GAME PASS", Colors = RIBBON_PASS },
				Icon = IconLibrary.Resolve(pass.emoji) or "",
				IconPlate = true,
				BackgroundColors = WASH_PASS,
				Buttons = {
					{
						Name = "Buy",
						Price = "R$ " .. tostring(pass.price or "?"),
						Icon = "",
						Colors = ROBUX,
						-- the KEY, never the pass id, for the same reason the products above send a
						-- key: the server looks the id up, so a tampered client can only ever name a
						-- pass that exists
						Callback = function()
							if ownedKeys[pass.key] then return end
							Remotes.PromptGamePassPurchase:FireServer(pass.key)
						end,
					},
				},
			})
			passButtons[pass.key] = card.Button
		end
	end

	-- Ownership is the one thing on this panel that changes while the game is running -- a purchase
	-- lands as a `DataUpdate` with `data.Passes` rewritten -- so it is repainted rather than rebuilt.
	panel.OnRefresh(function()
		local data = ShopPanel.getData and ShopPanel.getData()
		local owned = (data and data.Passes) or {}
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
		local card = panel.Scroll:FindFirstChild(cardName)
		if not (card and panel.IsOpen()) then return end
		-- measured against the scroll's own frame rather than the canvas origin, because the canvas
		-- has a top pad and a list layout between the two and neither is this file's business
		local y = (card.AbsolutePosition.Y - panel.Scroll.AbsolutePosition.Y) + panel.Scroll.CanvasPosition.Y
		-- 12 px of air above the card, and never a negative canvas position
		panel.Scroll.CanvasPosition = Vector2.new(0, math.max(0, y - 12))
	end)
end

return ShopPanel
