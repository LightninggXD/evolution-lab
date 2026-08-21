-- OfferRail -- the stack of standing offers up the right edge, above the tile cluster.
--
-- ===== WHERE IT COMES FROM (2026-08-21) =====
--
-- Both games Kristina sent run a short column of bright offer cards down the right edge -- "2x
-- Followers ONLY 2", "2x Wins ONLY 35", "2x WalkSpeed" -- above their button cluster. They are game
-- passes, sold from the HUD rather than from inside a shop screen.
--
-- WE ALREADY SELL THESE. All nine passes in `GameConfig.GamePasses` have had real `passId`s since
-- Phase 1 and are listed in the Robux panel's Passes tab (`HUD/PassShop`). This module invents
-- nothing: it is a shortcut to two of the nine, firing the same `Remotes.PromptGamePassPurchase`
-- that the tab's own buttons fire, and the server re-validates every prompt.
--
-- ===== WHY TWO, AND IT IS A MEASUREMENT RATHER THAN A TASTE =====
--
-- The right-hand cluster is eight tiles in two columns, i.e. four rows, and it FILLS UPWARD from
-- the bottom: 4 * 82 + 3 * 26 = 406 px of edge. `TileColumnFit` reserves TOP_CLEAR = 121 above it.
-- On a 720p viewport that leaves 720 - 406 - 46 - 121 = 147 px of genuinely free right edge, which
-- is two 64 px cards and their gap with 9 px to spare. A third card would be drawn under the
-- Journal tile on the most common viewport in the game.
--
-- DNA2x and Damage2x, of the nine. They are the two the reference makes loudest (its own rail is
-- "2x currency" and "2x wins"), they are the two passes that touch every minute of play rather than
-- one system, and at 199 each they are the middle of the price ladder rather than the top of it.
-- The other seven keep the Passes tab, which is still the place that shows all nine with their
-- full descriptions.
--
-- ===== IT PARKS ITSELF, AND THAT IS THE WHOLE DESIGN =====
--
-- A fixed position cannot work here. `TileColumnFit` re-lays the cluster on every viewport change,
-- shrinking tiles from 82 toward a 40 px floor and closing the gap from 26 to 8 -- so where the top
-- of the cluster IS depends on the screen. The rail therefore measures it: it reads the
-- `AbsolutePosition` of the tile the cluster's own registry calls order 1 (the top-left of the two
-- columns) and sits 14 px above it. Re-measured on a timer, because AbsolutePosition settles a
-- frame or two after a layout and there is no signal that says "the cluster has finished moving".
--
-- The tile is found by the SAME attributes `TileColumnFit` sorts on -- `ColumnSide` / `ColumnOrder`
-- -- rather than by name, so a tile renamed or reordered later moves the rail with it instead of
-- silently stranding it. See the note in MainUI's `columnTile` for why those attributes exist.

local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))

local Remotes = RS.Remotes

local themeLabel, styleCard = UIKit.themeLabel, UIKit.styleCard

local OFFERS = {
	{ key = "DNA2x",    label = "2x DNA",    color = UITheme.Color.Coral },
	{ key = "Damage2x", label = "2x Damage", color = UITheme.Color.Sunny },
}

local CARD_W, CARD_H, GAP = 168, 64, 10

return function(hud)
	local screenGui = hud.screenGui

	local rail = Instance.new("Frame")
	rail.Name = "OfferRail"
	rail.Size = UDim2.new(0, CARD_W, 0, #OFFERS * CARD_H + (#OFFERS - 1) * GAP)
	-- The authored position, for the frames before the first measurement lands. Right edge, above
	-- where a 720p cluster's top row sits -- so even if the measurement never ran, the rail would be
	-- roughly right rather than in the middle of the screen.
	rail.Position = UDim2.new(1, -20, 0, 200)
	rail.AnchorPoint = Vector2.new(1, 0)
	rail.BackgroundTransparency = 1
	rail.ZIndex = UITheme.Z.Content
	rail.Parent = screenGui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, GAP)
	layout.Parent = rail

	local cards = {}

	for order, offer in ipairs(OFFERS) do
		local pass = GameConfig.GetGamePass(offer.key)
		if pass then
			local card = Instance.new("TextButton")
			card.Name = "Offer_" .. offer.key
			card.Size = UDim2.new(0, CARD_W, 0, CARD_H)
			card.LayoutOrder = order
			card.Text = ""
			card.AutoButtonColor = false
			card.ZIndex = rail.ZIndex
			card.Parent = rail
			styleCard(card, offer.color, UDim.new(0, 16), 4)

			-- The name, big, on the top line -- and the price under it in the reference's own words
			-- ("ONLY 199"). Two labels rather than one two-line string because they are two different
			-- sizes and the kit's labels auto-shrink: one wrapped string would shrink BOTH halves to
			-- fit the smaller one.
			local nameLabel = Instance.new("TextLabel")
			nameLabel.Name = "OfferName"
			nameLabel.Size = UDim2.new(1, -16, 0, 30)
			nameLabel.Position = UDim2.new(0.5, 0, 0, 6)
			nameLabel.AnchorPoint = Vector2.new(0.5, 0)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = offer.label
			nameLabel.ZIndex = card.ZIndex + UITheme.Z.Content
			nameLabel.Parent = card
			themeLabel(nameLabel, 26)

			local priceLabel = Instance.new("TextLabel")
			priceLabel.Name = "OfferPrice"
			priceLabel.Size = UDim2.new(1, -16, 0, 22)
			priceLabel.Position = UDim2.new(0.5, 0, 1, -6)
			priceLabel.AnchorPoint = Vector2.new(0.5, 1)
			priceLabel.BackgroundTransparency = 1
			priceLabel.Text = "ONLY " .. (pass.price or 0) .. "\u{2B22}"
			priceLabel.ZIndex = card.ZIndex + UITheme.Z.Content
			priceLabel.Parent = card
			-- Green ink on the price line, matching the Robux hexagon it ends with and matching what
			-- the reference does with the same line.
			themeLabel(priceLabel, 18, UITheme.Color.Mint)

			card.MouseButton1Click:Connect(function()
				local prompt = Remotes:FindFirstChild("PromptGamePassPurchase")
				-- Created on demand by `PassService.Init`, so it may not have replicated yet on a
				-- fast client. A missing remote is a no-op, never an error thrown at a button press.
				if prompt then prompt:FireServer(offer.key) end
			end)

			cards[offer.key] = card
		end
	end

	-- ===== A PASS YOU OWN IS NOT AN OFFER =====
	--
	-- Same source of truth the Passes tab reads: `data.Passes[key]`. The card is hidden rather than
	-- destroyed, because ownership arrives on a DataUpdate that can be a second or two after join and
	-- a destroyed card cannot come back if the read was ever wrong.
	--
	-- The rail hides ENTIRELY when both are owned -- `Visible` on the container, so the measurement
	-- loop below stops mattering too. A rail with one card left would otherwise float alone with a
	-- gap under it where the other used to be.
	local function refresh()
		local data = hud.getData()
		local owned = (data and data.Passes) or {}
		local anyVisible = false
		for key, card in pairs(cards) do
			card.Visible = not owned[key]
			if card.Visible then anyVisible = true end
		end
		rail.Visible = anyVisible
	end

	Remotes.DataUpdate.OnClientEvent:Connect(refresh)
	refresh()

	-- ===== SITTING ABOVE THE CLUSTER =====
	local function topOfCluster()
		local best = nil
		for _, child in ipairs(screenGui:GetChildren()) do
			if child:GetAttribute("ColumnSide") == "R" then
				local y = child.AbsolutePosition.Y
				if best == nil or y < best then best = y end
			end
		end
		return best
	end

	task.spawn(function()
		while rail.Parent do
			local top = topOfCluster()
			if top then
				-- AbsolutePosition is in screen pixels and this ScreenGui is IgnoreGuiInset, so the
				-- two share an origin and the value can be used directly. 14 px of daylight above the
				-- cluster's top row, matching the gap the cluster keeps between its own rows.
				rail.Position = UDim2.new(1, -20, 0, math.max(top - 14, 40))
				rail.AnchorPoint = Vector2.new(1, 1)
			end
			task.wait(0.5)
		end
	end)
end
