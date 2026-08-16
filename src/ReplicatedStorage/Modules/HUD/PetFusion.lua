-- PetFusion -- the Pet Fusion panel: the slots, the odds and the fuse button.
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

local corner, themeLabel, styleCard, styleButton = UIKit.corner, UIKit.themeLabel, UIKit.styleCard, UIKit.styleButton
local PANEL_SHELL, PET_ROW_SHELL, READY_RIM = UIKit.PANEL_SHELL, UIKit.PET_ROW_SHELL, UIKit.READY_RIM

return function(hud)
	local PANEL_ANCHOR, colorTag, panelClose = hud.PANEL_ANCHOR, hud.colorTag, hud.panelClose
	local petDisplayInfo, registerPanel, screenGui = hud.petDisplayInfo, hud.registerPanel, hud.screenGui
	local toggleOnly = hud.toggleOnly

	local panel = Instance.new("Frame")
	panel.Name = "FusionPanel"
	panel.Size = UDim2.new(0, 500, 0, 520)
	panel.Position = PANEL_ANCHOR
	panel.ZIndex = 20
	panel.Visible = false
	panel.Parent = screenGui
	styleCard(panel, PANEL_SHELL, UDim.new(0, 22), 5)
	registerPanel(panel)
	panelClose(panel)

	-- This panel already had the closest thing to what 11.13 asks for -- a purple hint card under the
	-- title -- and that card is exactly what the header band generalises. The card STAYS, because it
	-- carries a number (`FuseRequirement`) that has already changed once; the subtitle carries the
	-- part that never does.
	UITheme.PanelHeader(panel, {
		title = "\u{1F9EC} Pet Fusion",
		subtitle = "Trade duplicates upward -- Rainbow, then Celestial",
		accent = UITheme.Color.Purple,
		maxTextSize = 28,
	})

	local hint = Instance.new("Frame")
	hint.Size = UDim2.new(1, -32, 0, 44)
	hint.Position = UDim2.new(0, 16, 0, 94)
	hint.Parent = panel
	styleCard(hint, UITheme.Color.Purple, UDim.new(0, 14), 4)

	local hintLabel = Instance.new("TextLabel")
	hintLabel.Size = UDim2.new(1, -20, 1, -8)
	hintLabel.Position = UDim2.new(0, 10, 0, 2)
	hintLabel.BackgroundTransparency = 1
	hintLabel.TextWrapped = true
	hintLabel.Text = ("Fuse %d of the same pet at the same tier into one of the next tier.")
		:format(GameConfig.FuseRequirement)
	hintLabel.Parent = hint
	themeLabel(hintLabel, 18)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "FusionScroll"
	-- header 14+68, gap 12, hint 44, gap 12 => 150; bottom margin 16, so 166 short.
	scroll.Size = UDim2.new(1, -32, 1, -166)
	scroll.Position = UDim2.new(0, 16, 0, 150)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.Parent = panel

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = scroll

	-- ===== THE CATALYST CARDS LIVE HERE NOW (11.7) =====
	--
	-- They used to be two tiles in the Robux grid, between a DNA pack and a potion crate. A catalyst
	-- answers exactly one question -- "I have two of these and I need three" -- and that question is
	-- asked here, looking at a row that says (2/3), not while scrolling a wall of currency packs.
	--
	-- Built ONCE, outside `refresh`, with negative LayoutOrder so they sit above the fusion rows and
	-- survive every rebuild of the list below. Driven off `GameConfig.RobuxProducts` rather than
	-- hand-written, so the price on the button is the price in the table and the two cannot drift --
	-- which is the same reason the grid prints its own price rather than a typed string.
	local catalystRows = 0
	for _, product in ipairs(GameConfig.RobuxProducts) do
		if product.panelCard and not product.delisted then
			catalystRows += 1
			local row = Instance.new("Frame")
			row.Name = product.key
			row.Size = UDim2.new(1, -10, 0, 66)
			row.LayoutOrder = -100 + catalystRows
			row.Parent = scroll
			styleCard(row, UITheme.Color.Pink, UDim.new(0, 12), 3)

			UITheme.IconSlot(row, {
				name = "Icon", icon = product.emoji, maxTextSize = 30,
				size = UDim2.new(0, 48, 0, 48), position = UDim2.new(0, 10, 0, 9),
			})

			local title = Instance.new("TextLabel")
			title.Name = "NameLabel"
			title.Size = UDim2.new(1, -210, 0, 26)
			title.Position = UDim2.new(0, 66, 0, 10)
			title.BackgroundTransparency = 1
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.Text = product.name
			title.ZIndex = row.ZIndex + UITheme.Z.Content
			title.Parent = row
			themeLabel(title, 20)

			local sub = Instance.new("TextLabel")
			sub.Name = "SubLabel"
			sub.Size = UDim2.new(1, -210, 0, 22)
			sub.Position = UDim2.new(0, 66, 0, 34)
			sub.BackgroundTransparency = 1
			sub.TextXAlignment = Enum.TextXAlignment.Left
			-- says what it SKIPS, in the unit this panel is already counting in -- and SHORT, because
			-- the label is 226 px wide next to the price button and the first version of this
			-- sentence clipped at the minimum text size (found by 11.13's sweep, not by reading it)
			sub.Text = ("%d pets up a tier, no copies"):format(product.grantTierUps or 1)
			sub.ZIndex = row.ZIndex + UITheme.Z.Content
			sub.Parent = row
			themeLabel(sub, 16, UITheme.Color.Cream)

			local buy = Instance.new("TextButton")
			buy.Name = "BuyButton"
			buy.Size = UDim2.new(0, 118, 0, 44)
			buy.Position = UDim2.new(1, -12, 0.5, -22)
			buy.AnchorPoint = Vector2.new(1, 0)
			buy.Text = "R$ " .. product.price
			buy.ZIndex = row.ZIndex + UITheme.Z.Content
			buy.Parent = row
			styleButton(buy, UITheme.Color.Green, UDim.new(1, 0))
			buy.MouseButton1Click:Connect(function()
				Remotes.PromptRobuxPurchase:FireServer(product.key)
			end)
		end
	end

	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.Name = "EmptyLabel"
	emptyLabel.Size = UDim2.new(1, 0, 0, 66)
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.TextWrapped = true
	emptyLabel.LayoutOrder = 0
	emptyLabel.Text = ("Nothing to fuse yet \u{2014} you need %d copies of one pet at the same tier.")
		:format(GameConfig.FuseRequirement)
	emptyLabel.Parent = scroll
	themeLabel(emptyLabel, 20, UITheme.Color.Cream)

	-- GetPetPower is a SHARE OF THE PLAYER'S DAMAGE now, not the old 1..64 tier x rarity product, so
	-- it runs about 0.03 to 3.4 -- and "x0.1" as a power chip says nothing to anybody. Rendered as
	-- the percentage of damage the pet adds, which is the same unit the pet rows and the catalyst
	-- rows already print, so one pet reads the same number everywhere in the UI.
	local function powerText(p)
		return ("+%d%%"):format(math.floor(p * 100 + 0.5))
	end

	local function refresh()
		if not hud.getData() then return end
		local data = hud.getData()

		for _, child in ipairs(scroll:GetChildren()) do
			if child:IsA("Frame") and (child.Name == "FuseRow" or child.Name == "CatalystRow") then
				child:Destroy()
			end
		end

		-- one entry per species+tier, because that pairing is exactly what HandleFuse consumes
		local groups, order = {}, {}
		for _, pet in ipairs(data.Pets) do
			local groupKey = pet.key .. "|" .. pet.tier
			local g = groups[groupKey]
			if not g then
				-- firstId is what a Catalyst is spent on: a catalyst raises ONE pet, so the row needs a
				-- specific id, where a fuse only needs the species and tier
				g = { key = pet.key, tier = pet.tier, count = 0, firstId = pet.id, firstEnchant = pet.enchant }
				groups[groupKey] = g
				table.insert(order, g)
			end
			g.count += 1
			-- ===== THE GROUP'S BEST ENCHANT, AND WHY IT IS THE HONEST ONE TO QUOTE (13.1) =====
			--
			-- A group is many pets and they can carry different enchants, so there is no single
			-- "the" enchant for a fuse row -- but there is one the player can count on: HandleFuse
			-- consumes the STRONGEST-enchanted copies and carries the best of them onto the
			-- result, so the best in the group is exactly what comes out the other side. Client and
			-- server therefore agree by construction rather than by keeping two rules in step.
			if GameConfig.IsEnchantBetter(pet.enchant, g.bestEnchant) then
				g.bestEnchant = pet.enchant
			end
		end

		-- Groups that CANNOT fuse are dropped, not greyed out. A maxed-tier pet or a lone copy is
		-- not a choice the player has, and a hundred dead rows hide the four live ones.
		local ready = {}
		for _, g in ipairs(order) do
			g.nextTier = GameConfig.GetNextTier(g.tier)
			if g.nextTier and g.count >= GameConfig.FuseRequirement then
				-- `data` carries the zone axis into the ranking, so the fusion list is ordered by what
				-- these pets are worth to this player now rather than by what they were worth in the
				-- zone they hatched in
				-- the enchant rides BOTH sides, so the ratio the row prints is untouched by it and the
				-- two absolute figures are the ones the surviving pet actually carries
				g.power = GameConfig.GetPetPower({ key = g.key, tier = g.tier, enchant = g.bestEnchant }, data)
				g.nextPower = GameConfig.GetPetPower({ key = g.key, tier = g.nextTier, enchant = g.bestEnchant }, data)
				table.insert(ready, g)
			end
		end
		table.sort(ready, function(a, b)
			if a.nextPower ~= b.nextPower then return a.nextPower > b.nextPower end
			return a.key < b.key
		end)

		-- ===== THE CATALYST ROWS =====
		--
		-- They sit at the top of the same scroll rather than in a panel of their own, because they are
		-- the same decision as the rows below -- "make this pet stronger" -- reached by paying instead
		-- of by grinding. A player comparing the two should not have to hold one in their head while
		-- they go and look at the other. (It is also the only option: this file is at Luau's 200-local
		-- register cap and everything here lives inside one immediately-called function.)
		--
		-- Unlike the fuse rows, a group with ONE copy is a perfectly good catalyst target -- not needing
		-- four copies is the entire product -- so these are filtered only by the tier cap.
		local catalysts = {}
		for _, g in ipairs(order) do
			local step = GameConfig.GetCatalystNextTier(g.tier)
			if step then
				g.catalystTier = step
				table.insert(catalysts, g)
			end
		end
		table.sort(catalysts, function(a, b)
			-- `firstEnchant`, not `bestEnchant`: a catalyst is spent on `firstId`, one specific pet,
			-- and it mutates that pet's tier in place -- so the enchant that survives is that pet's
			local pa = GameConfig.GetPetPower({ key = a.key, tier = a.catalystTier, enchant = a.firstEnchant }, data)
			local pb = GameConfig.GetPetPower({ key = b.key, tier = b.catalystTier, enchant = b.firstEnchant }, data)
			if pa ~= pb then return pa > pb end
			return a.key < b.key
		end)

		local tokens = (hud.getData() and hud.getData().TierUpTokens) or 0
		local shown = 0
		for _, g in ipairs(catalysts) do
			if shown >= 6 then break end
			shown += 1
			local info = petDisplayInfo(g.key)

			local row = Instance.new("Frame")
			row.Name = "CatalystRow"
			row.LayoutOrder = -1000 + shown
			row.Size = UDim2.new(1, 0, 0, 72)
			row.Parent = scroll
			styleCard(row, UITheme.Color.Pink or PET_ROW_SHELL, UDim.new(0, 14), 4)

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(0, 250, 0, 28)
			nameLabel.Position = UDim2.new(0, 16, 0, 8)
			nameLabel.BackgroundTransparency = 1
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.Text = ("\u{1F308} %s %s"):format(info.emoji, info.name)
			nameLabel.Parent = row
			themeLabel(nameLabel, 23)

			-- THE GAIN IS QUOTED IN DAMAGE, BECAUSE DAMAGE IS NOW THE ONLY THING A PET PAYS.
			--
			-- This read `incomeMult` until the pet rebalance, and that field is a hard 1 today -- so
			-- left alone this row would have advertised "income x1.00 -> x1.00 (+0%)" on a card the
			-- player is about to spend Robux against. A stat that no longer exists cannot be the
			-- headline of a purchase.
			--
			-- Still read off GetPetBonus rather than GetPetPower for the original reason: the tier
			-- ladder divides out to a constant ratio, but what the player actually gains is the
			-- share ON TOP of 1, so only the bonus itself can quote the real step. Both calls pass
			-- `pet key` and `data`, so the quote is what this player gets at their current rung.
			local fromBonus = GameConfig.GetPetBonus(g.tier, info.rarity, g.key, data, g.firstEnchant).damageMult
			local toBonus = GameConfig.GetPetBonus(g.catalystTier, info.rarity, g.key, data, g.firstEnchant).damageMult
			local gainLabel = Instance.new("TextLabel")
			gainLabel.Size = UDim2.new(0, 290, 0, 24)
			gainLabel.Position = UDim2.new(0, 16, 1, -32)
			gainLabel.BackgroundTransparency = 1
			gainLabel.TextXAlignment = Enum.TextXAlignment.Left
			gainLabel.RichText = true
			gainLabel.Text = ("%s \u{2192} %s   damage x%.2f \u{2192} %s"):format(
				g.tier,
				colorTag(g.catalystTier, GameConfig.PetTierColor[g.catalystTier] or UITheme.Color.White),
				fromBonus,
				colorTag(("x%.2f (+%.0f%%)"):format(toBonus, (toBonus / fromBonus - 1) * 100), READY_RIM))
			gainLabel.Parent = row
			themeLabel(gainLabel, 17, UITheme.Color.Cream)

			local btn = Instance.new("TextButton")
			btn.Name = "CatalystButton"
			btn.Size = UDim2.new(0, 118, 0, 46)
			btn.Position = UDim2.new(1, -12, 0.5, -23)
			btn.AnchorPoint = Vector2.new(1, 0)
			-- With no token in hand the row is not hidden, it becomes the offer. Hiding it would make a
			-- product nobody has heard of, and the moment a player is looking at their pets is the one
			-- moment they care what a tier is worth.
			-- THE PRICE IS READ, NOT TYPED (11.7). This said "R$ 99" as a literal, and 11.7 moved the
			-- product to 49 -- so the row would have advertised one number and charged another. The
			-- grid has always read `product.price` for exactly this reason; this row had been missed.
			btn.Text = tokens > 0 and ("USE (%d)"):format(tokens)
				or ("R$ " .. tostring(GameConfig.GetRobuxProduct("TierUp_1").price))
			btn.Parent = row
			styleButton(btn, tokens > 0 and UITheme.Color.Green or UITheme.Color.Gold, UDim.new(1, 0))
			btn.MouseButton1Click:Connect(function()
				if tokens > 0 then
					Remotes.UseTierUp:FireServer(g.firstId)
				else
					Remotes.PromptRobuxPurchase:FireServer("TierUp_1")
				end
			end)
		end

		emptyLabel.Visible = (#ready == 0 and shown == 0)

		for i, g in ipairs(ready) do
			local info = petDisplayInfo(g.key)
			local rarity = GameConfig.GetRarity(info.rarity)

			local row = Instance.new("Frame")
			row.Name = "FuseRow"
			row.LayoutOrder = i
			row.Size = UDim2.new(1, 0, 0, 72)
			row.Parent = scroll
			styleCard(row, PET_ROW_SHELL, UDim.new(0, 14), 4)

			local stripe = Instance.new("Frame")
			stripe.Size = UDim2.new(0, 7, 1, -20)
			stripe.Position = UDim2.new(0, 8, 0.5, 0)
			stripe.AnchorPoint = Vector2.new(0, 0.5)
			stripe.BackgroundColor3 = rarity.color
			stripe.BorderSizePixel = 0
			stripe.ZIndex = row.ZIndex + UITheme.Z.Content
			stripe.Parent = row
			corner(stripe, UDim.new(1, 0))

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(0, 250, 0, 28)
			nameLabel.Position = UDim2.new(0, 26, 0, 8)
			nameLabel.BackgroundTransparency = 1
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.RichText = true
			nameLabel.Text = ("%s %s  %s"):format(info.emoji, info.name,
				colorTag(("(%d/%d)"):format(g.count, GameConfig.FuseRequirement), READY_RIM))
			nameLabel.Parent = row
			themeLabel(nameLabel, 23)

			-- THE ANSWER TO "how much stronger": both sides of the trade and the ratio between them,
			-- on one line. Printing only the result would leave the player doing the division.
			local gainLabel = Instance.new("TextLabel")
			gainLabel.Size = UDim2.new(0, 260, 0, 24)
			gainLabel.Position = UDim2.new(0, 26, 1, -32)
			gainLabel.BackgroundTransparency = 1
			gainLabel.TextXAlignment = Enum.TextXAlignment.Left
			gainLabel.RichText = true
			gainLabel.Text = ("%s %s  \u{2192}  %s %s"):format(
				g.tier, powerText(g.power),
				colorTag(g.nextTier, GameConfig.PetTierColor[g.nextTier] or UITheme.Color.White),
				colorTag(powerText(g.nextPower) .. ((" (+%.0f%%)"):format((g.nextPower / g.power - 1) * 100)), READY_RIM))
			gainLabel.Parent = row
			themeLabel(gainLabel, 17, UITheme.Color.Cream)

			-- THE WARNING THE RATIO ABOVE DOES NOT COVER.
			--
			-- "+92%" is true of the PET and can be false of the PLAYER. Equipped bonuses multiply
			-- across three slots, so a player who owns four pets and fuses all four goes from three
			-- equipped to one -- their actual damage falls even though every number on this row went
			-- up. The server now re-equips the result, which recovers most of it, but a shallow
			-- collection still ends the trade with emptier slots and the player deserves to know
			-- before pressing rather than after.
			if hud.getData() and #hud.getData().Pets - GameConfig.FuseRequirement + 1
				< #hud.getData().EquippedPetIds then
				local warn_ = Instance.new("TextLabel")
				warn_.Size = UDim2.new(0, 300, 0, 20)
				warn_.Position = UDim2.new(0, 26, 1, -12)
				warn_.BackgroundTransparency = 1
				warn_.TextXAlignment = Enum.TextXAlignment.Left
				warn_.Text = "\u{26A0}\u{FE0F} You'll have fewer pets equipped after this"
				warn_.ZIndex = row.ZIndex + UITheme.Z.Content
				warn_.Parent = row
				themeLabel(warn_, 15, Color3.fromRGB(255, 186, 120))
			end

			local fuseBtn = Instance.new("TextButton")
			fuseBtn.Name = "FuseButton"
			fuseBtn.Size = UDim2.new(0, 108, 0, 46)
			fuseBtn.Position = UDim2.new(1, -12, 0.5, -23)
			fuseBtn.AnchorPoint = Vector2.new(1, 0)
			fuseBtn.Text = ("FUSE %d"):format(GameConfig.FuseRequirement)
			fuseBtn.Parent = row
			styleButton(fuseBtn, UITheme.Color.Purple, UDim.new(1, 0))
			fuseBtn.MouseButton1Click:Connect(function()
				Remotes.FusePet:FireServer(g.key, g.tier)
			end)
		end

		-- + the catalyst cards, which are not in `ready` or `shown` because they are built once above
		-- and never rebuilt. Leaving them out of this sum is how the last two fusion rows become
		-- unreachable behind the bottom of the scroll.
		scroll.CanvasSize = UDim2.new(0, 0, 0, (#ready + shown) * 78 + catalystRows * 72 + 40)
	end

	hud.refreshFusionPanel = refresh
	hud.showFusionPanel = function()
		toggleOnly(panel)
		refresh()
	end
end
