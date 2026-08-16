-- ProductTiles -- the developer-product tiles in the Robux shop: the DNA packs and the consumables.
--
-- MOVED OUT OF `MainUI` (18.9), byte for byte. It was already a closed
-- `;(function() ... end)()` block -- the shape this file's 200-register ceiling forces
-- every panel into -- so the extraction is a change of wrapper, not of code. See
-- `docs/SPLIT.md` for the `hud` contract and `docs/CODEMAP.md` for where the rest went.

local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))

local Remotes = RS.Remotes

local formatNumber, corner, themeLabel, styleCard = UIKit.formatNumber, UIKit.corner, UIKit.themeLabel, UIKit.styleCard
local styleButton = UIKit.styleButton

return function(hud)
	local robuxGrid = hud.robuxGrid

	-- [key] = the label under the name, the one thing on a tile whose text depends on the player
	local amountLabels = {}

	-- ===== TODAY'S PICK =====
	--
	-- Derived from the calendar day, so it is the same product for every player on every server
	-- without a byte of server state, and it genuinely changes at midnight UTC. That honesty is the
	-- reason it is a PICK and not a "limited offer": nothing here is discounted and nothing expires,
	-- so a countdown to a price going up would be a lie told to hurry someone. What the timer counts
	-- down to is exactly what it says -- when the highlight moves to something else.
	-- ===== WHAT THIS GRID IS ALLOWED TO SHOW (11.7) =====
	--
	-- Two products are in `RobuxProducts` and not on this wall: Boss Revive is `delisted` (withdrawn,
	-- but its row has to survive so a retried receipt still resolves -- see the note there), and the
	-- two Catalysts carry `panel = "fusion"` because they answer a question the player only has while
	-- looking at a pet they cannot fuse yet.
	--
	-- ONE PREDICATE, USED TWICE -- the grid and the refresh loop -- because a product hidden from
	-- the cards but still walked by the refresh would write into a label that was never built.
	-- (It had a third caller until 15.23: the daily "pick", which is gone.)
	local function inGrid(product)
		return not product.delisted and product.panel == nil
	end

	local gridProducts = {}
	for _, product in ipairs(GameConfig.RobuxProducts) do
		if inGrid(product) then table.insert(gridProducts, product) end
	end

	for i, product in ipairs(gridProducts) do
		local card = Instance.new("Frame")
		card.Name = product.key
		card.LayoutOrder = i
		card.Parent = robuxGrid
		-- shell colour follows what the tile actually pays out, so the groups read apart at a glance
		local accent = UITheme.Color.Blue
		if product.grantPotions then
			accent = UITheme.Color.Green
		elseif product.grantDiamonds then
			accent = UITheme.Color.SkyBlue
		elseif product.grantShards then
			-- Sunny, not the SkyBlue the Diamond tiles use: shards and diamonds are both "premium
			-- currency" to a developer and are completely different things to a player -- one buys
			-- twenty-three permanent upgrades, the other buys spins -- so they must not read as one
			-- group with two amounts.
			accent = UITheme.Color.Sunny
		elseif product.grantBossRevives then
			accent = UITheme.Color.Red
		elseif product.grantTierUps then
			accent = UITheme.Color.Pink
		elseif product.grantSpin then
			accent = UITheme.Color.Purple
		elseif product.grantSeasonPremium then
			accent = UITheme.Color.Gold
		end
		styleCard(card, accent, UDim.new(0, 16), 4)

		-- THE ICON IS THE TILE. At 24 px the emoji was punctuation in front of a name; the fastest
		-- thing to recognise in a shop is what kind of thing you are looking at, and that is the icon.
		--
		-- Through UITheme.IconSlot since 9.9, so a product whose emoji has drawn art gets the
		-- drawing and one whose emoji does not keeps the glyph. The 60 px box is unchanged and the
		-- note below is still why it is 60: TextScaled fits the font to the LINE BOX and an emoji's
		-- line box is mostly padding, so a 40 px box drew an icon barely larger than the name under
		-- it. An ImageLabel has no such padding and fills what it is given, which is a small free
		-- improvement on exactly the tiles this was measured against.
		local icon = UITheme.IconSlot(card, {
			name = "Icon", icon = product.emoji, maxTextSize = 40,
			size = UDim2.new(1, -16, 0, 60), position = UDim2.new(0, 8, 0, 8),
		})

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "NameLabel"
		-- TWO LINES OF ROOM, and it is not cosmetic. themeLabel floors text at 14 px
		-- (UITextSizeConstraint.MinTextSize), so TextScaled cannot rescue a wrapped name from a box
		-- shorter than two lines -- it clips instead. "Small DNA Pack" wraps, and at 24 px tall the
		-- second line was cut in half on every DNA tile.
		nameLabel.Size = UDim2.new(1, -12, 0, 32)
		nameLabel.Position = UDim2.new(0, 6, 0, 68)
		nameLabel.BackgroundTransparency = 1
		nameLabel.TextWrapped = true
		nameLabel.Text = product.name
		nameLabel.Parent = card
		themeLabel(nameLabel, 17)

		-- The second line: what you actually receive. Blank for the products whose name already says
		-- it (a diamond count is a diamond count), filled in per player for the DNA packs, whose
		-- payout is scaled to the buyer's stage and is therefore unknowable at build time.
		local amount = Instance.new("TextLabel")
		amount.Name = "AmountLabel"
		amount.Size = UDim2.new(1, -12, 0, 18)
		amount.Position = UDim2.new(0, 6, 0, 100)
		amount.BackgroundTransparency = 1
		amount.Text = ""
		amount.Parent = card
		themeLabel(amount, 16, UITheme.Color.Cream)
		amountLabels[product.key] = amount

		-- THE PRICE IS ON THE BUTTON. Every tile used to read "Buy with R$", which made a 49 and a 999
		-- look like the same decision and forced the player through a Roblox modal to find out which
		-- was which.
		local buyButton = Instance.new("TextButton")
		buyButton.Name = "BuyButton"
		buyButton.Size = UDim2.new(1, -20, 0, 40)
		buyButton.Position = UDim2.new(0.5, 0, 1, -8)
		buyButton.AnchorPoint = Vector2.new(0.5, 1)
		buyButton.Text = product.price and ("R$ " .. product.price) or "Buy with R$"
		buyButton.Parent = card
		styleButton(buyButton, UITheme.Color.Green, UDim.new(1, 0))

		buyButton.MouseButton1Click:Connect(function()
			Remotes.PromptRobuxPurchase:FireServer(product.key)
		end)

		-- THE RIBBON, AND WHY NO TILE CLAIMS TO BE POPULAR.
		--
		-- "MOST POPULAR" is the standard ribbon in this genre and it is a claim about other players
		-- that nothing in this game measures. What is measurable is value: GetTierBonusPct divides
		-- this tier's payout per Robux by the cheapest tier's, so "+48% BONUS" is arithmetic done on
		-- the table three hundred lines up rather than a sentence somebody typed.
		local ribbonText = product.ribbon
		if not ribbonText then
			local bonus = GameConfig.GetTierBonusPct(product)
			if bonus > 0 then ribbonText = ("+%d%% BONUS"):format(bonus) end
		end
		if ribbonText then
			local ribbon = Instance.new("TextLabel")
			ribbon.Name = "Ribbon"
			ribbon.Size = UDim2.new(1, -20, 0, 20)
			ribbon.Position = UDim2.new(0.5, 0, 0, -6)
			ribbon.AnchorPoint = Vector2.new(0.5, 0)
			ribbon.BackgroundColor3 = product.ribbon and UITheme.Color.Gold or UITheme.Color.Purple
			ribbon.BorderSizePixel = 0
			ribbon.Text = ribbonText
			ribbon.ZIndex = card.ZIndex + UITheme.Z.Badge
			ribbon.Parent = card
			corner(ribbon, UDim.new(0, 8))
			themeLabel(ribbon, 14)
			ribbon.ZIndex = card.ZIndex + UITheme.Z.Badge
		end

	end

	-- Re-run on every data push, which is also what makes the countdown in the title tick without a
	-- loop of its own -- the server pushes about every three seconds.
	hud.refreshRobuxShop = function()
		for _, product in ipairs(gridProducts) do
			local label = amountLabels[product.key]
			if label then
				if product.grantDNA and hud.getData() then
					-- WHAT THIS PACK IS WORTH TO YOU, not what it was authored as. The table stores
					-- "1,000" meaning a thousand stage-one clicks; at stage 14 the same pack pays out
					-- billions, and a tile that said "1,000 DNA" there would read as an insult.
					label.Text = "+" .. formatNumber(GameConfig.ScaleReward(product.grantDNA, hud.getData())) .. " DNA"
				elseif product.grantPotions then
					label.Text = ("%d potions"):format(product.grantPotions)
				elseif product.grantTierUps then
					label.Text = ("%d catalyst%s"):format(product.grantTierUps, product.grantTierUps > 1 and "s" or "")
				elseif product.grantSpin then
					label.Text = "1 spin of the wheel"
				elseif product.grantBossRevives then
					label.Text = "keep your boss damage"
				end
			end
		end
		-- 15.23 DELETED THE COUNTDOWN THAT USED TO BE WRITTEN HERE, and the reason is that it counted
		-- down to nothing. "⭐ Today's pick resets in 10h 51m" sat under the title of a shop whose
		-- every tile is on sale permanently, at a fixed Robux price, with the same grant tomorrow as
		-- today -- so the clock promised an expiry that does not exist. A countdown is a claim that
		-- something is about to be lost; putting one over a Robux shop that loses nothing is a lie
		-- the player can check in twelve hours. The daily "pick" it timed was a star drawn on one
		-- rotating tile that carried no discount and no bonus, so it went with it.
		--
		-- What stays is the part that is genuinely per-player and genuinely changes: the DNA amounts
		-- above, which are scaled to the reader's own stage and would otherwise print stage-one
		-- numbers. The ribbons stay too -- +24% BONUS / BEST VALUE are derived from real value per
		-- Robux, i.e. a fact about the tile rather than a clock.
	end
	hud.refreshRobuxShop()
end
