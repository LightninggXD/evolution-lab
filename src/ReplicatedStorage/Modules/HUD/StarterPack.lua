-- StarterPack -- the one-time first-purchase card, shown once per save on a join that has settled.
--
-- ===== WHY THE GAME NEEDED A CARD AT ALL (21.6) =====
--
-- The store sells nineteen products and every one of them is a rung on a ladder: they answer "how
-- much", never "whether". A player who has never spent is not choosing between 199 and 499, they
-- are choosing between 0 and something, and nothing in the game had ever asked them that question.
-- The row's own number is why it is worth asking once: roughly 95% of players who spend once spend
-- again, so this card is not selling 99 Robux of currency, it is selling the first purchase.
--
-- ===== IT IS A CARD, NOT A PANEL, AND THE DIFFERENCE IS THE DOOR =====
--
-- Every other screen in this HUD is reached from a tile the player pressed. This one arrives
-- uninvited, which is a licence that has to be spent carefully and exactly once:
--
--   * The SERVER decides and stamps (`RobuxShopService`, `data.StarterPackShown`). This file cannot
--     re-arm itself, cannot be replayed by a client that stayed quiet, and never writes a save
--     field -- it draws what `StarterPackOffer` hands it.
--   * It waits for the loading screen the same way `WelcomeBack` does, and for the same reason: a
--     card animating open under the wipe is a card nobody saw. Waiting on the OBJECT rather than on
--     a delay, because `LoadingScreen`'s hold is a range and not a number.
--   * It stands down if any panel is already open. Twenty-five seconds is long enough for a player
--     to have opened something themselves, and shoving an offer in front of a screen they chose is
--     the difference between an offer and an advertisement. The store's hero is still there
--     afterwards, so standing down costs the sale nothing.
--
-- ===== EVERY NUMBER ON IT IS DERIVED =====
--
-- The three rows are read off the product's own grant fields and the worth line is
-- `GameConfig.GetBundleValue`, which prices each line at the cheapest rung in the shop that sells
-- the same thing. Nothing here is a literal: repricing `DNA_1` moves the claim on this card, and
-- there is no path by which the card can advertise a bundle the receipt does not pay. That is
-- 11.7's ribbon rule, and it binds harder here because a bundle is the one card in the game whose
-- value a buyer cannot check by eye.
--
-- The BUY button fires `PromptRobuxPurchase` with the product KEY, like every other card in the
-- store -- the server holds the id and refuses a zero one out loud (26.4).

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))

local Remotes = RS.Remotes
local player = Players.LocalPlayer

local themeLabel, styleCard, styleButton, DISPLAY_FONT = UIKit.themeLabel, UIKit.styleCard, UIKit.styleButton, UIKit.DISPLAY_FONT
local PANEL_SHELL, PET_ROW_SHELL = UIKit.PANEL_SHELL, UIKit.PET_ROW_SHELL

-- What each grant field is called on the card, and in what order. A LIST rather than a map, because
-- the order is the argument the pack makes -- the run, then the permanent upgrades, then the wheel
-- -- and a map has no order. `format` exists so DNA can carry the game's own suffixes while a
-- diamond count stays a plain integer.
local ROWS = {
	{
		field = "grantDNA", icon = "\u{1F9EC}", color = UITheme.Color.Aqua,
		title = "%s DNA", note = "A running start in whatever zone you are in",
		format = function(n) return UITheme.FormatNumber(n) end,
	},
	{
		field = "grantDiamonds", icon = "\u{1F48E}", color = UITheme.Color.Lavender,
		title = "%s Diamonds", note = "The permanent upgrades -- these never reset",
		format = function(n) return tostring(n) end,
	},
	{
		field = "grantShards", icon = "\u{1F31F}", color = UITheme.Color.Gold,
		title = "%s Evolution Shards", note = "One spin of the Lucky Wheel, on the house",
		format = function(n) return tostring(n) end,
	},
}

local ROW_H, ROW_GAP = 78, 10

return function(hud)
	local PANEL_ANCHOR, panelClose = hud.PANEL_ANCHOR, hud.panelClose
	local registerPanel, screenGui = hud.registerPanel, hud.screenGui
	local toggleOnly, togglePanels = hud.toggleOnly, hud.togglePanels

	local product = GameConfig.GetRobuxProduct("StarterPack")
	-- No row, no card. This module is required unconditionally by MainUI (a conditional require is a
	-- branch that only one of two worlds ever tests), so the absence of the product is answered here
	-- rather than there -- and it leaves `hud.starterPackOffer` nil, which MainUI's call site guards.
	if not product then return end

	local shown = false

	-- 14 top + 26 subtitle + 12 gap = 52, the `PanelHeader` content line (27.1). Three rows and their
	-- gaps, then the price strip at 64 and 16 of bottom margin. Authored at its FULL height because
	-- `registerPanel` computes the responsive fit from the authored size and this card never grows.
	local rowsH = #ROWS * ROW_H + (#ROWS - 1) * ROW_GAP
	local panel = Instance.new("Frame")
	panel.Name = "StarterPackPanel"
	panel.Size = UDim2.new(0, 580, 0, 52 + rowsH + 14 + 64 + 16)
	panel.Position = PANEL_ANCHOR
	panel.ZIndex = 20
	panel.Visible = false
	panel.Parent = screenGui
	styleCard(panel, PANEL_SHELL, UDim.new(0, 24), 5)
	registerPanel(panel)
	panelClose(panel)

	-- ~50 characters is the safe length for a subtitle on a panel this wide; the label is
	-- `width - (14 + 62)` and a long line clips at the minimum text size rather than shrinking.
	local _, contentTop = UITheme.PanelHeader(panel, {
		title = "\u{1F381} Starter Pack",
		subtitle = "One time only -- this will not be offered again.",
		accent = UITheme.Color.Gold,
		margin = 16,
		top = 14,
		height = 64,
	})

	local rowHost = Instance.new("Frame")
	rowHost.Name = "Rows"
	rowHost.Size = UDim2.new(1, -32, 0, rowsH)
	rowHost.Position = UDim2.new(0, 16, 0, contentTop)
	rowHost.BackgroundTransparency = 1
	rowHost.ZIndex = panel.ZIndex + UITheme.Z.Content
	rowHost.Parent = panel

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.Padding = UDim.new(0, ROW_GAP)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = rowHost

	for order, spec in ipairs(ROWS) do
		local amount = tonumber(product[spec.field])
		-- A row per grant the product actually carries. Dropping the row rather than drawing a zero
		-- is what lets the pack's contents be re-authored in `RobuxShop` without touching this file.
		if amount and amount > 0 then
			local row = Instance.new("Frame")
			row.Name = spec.field
			row.Size = UDim2.new(1, 0, 0, ROW_H)
			row.LayoutOrder = order
			row.ZIndex = rowHost.ZIndex + UITheme.Z.Content
			row.Parent = rowHost
			styleCard(row, PET_ROW_SHELL, UDim.new(0, 16), 3.5)

			local iconBox = Instance.new("Frame")
			iconBox.Name = "IconBox"
			iconBox.Size = UDim2.new(0, 50, 0, 50)
			iconBox.Position = UDim2.new(0, 14, 0.5, 0)
			iconBox.AnchorPoint = Vector2.new(0, 0.5)
			iconBox.ZIndex = row.ZIndex + UITheme.Z.Content
			iconBox.Parent = row
			styleCard(iconBox, UITheme.Shade(spec.color, 0.25), UDim.new(0, 12), 2.5)

			local iconLabel = Instance.new("TextLabel")
			iconLabel.Name = "IconLabel"
			iconLabel.Size = UDim2.new(1, 0, 1, 0)
			iconLabel.BackgroundTransparency = 1
			iconLabel.Text = spec.icon
			iconLabel.Font = DISPLAY_FONT
			iconLabel.ZIndex = iconBox.ZIndex + UITheme.Z.Content
			themeLabel(iconLabel, 26)
			iconLabel.Parent = iconBox

			local head = Instance.new("TextLabel")
			head.Name = "Head"
			head.Size = UDim2.new(1, -90, 0, 26)
			head.Position = UDim2.new(0, 76, 0, 12)
			head.BackgroundTransparency = 1
			head.Text = spec.title:format(spec.format(amount))
			head.TextXAlignment = Enum.TextXAlignment.Left
			head.ZIndex = row.ZIndex + UITheme.Z.Content
			head.Parent = row
			themeLabel(head, 23)

			local note = Instance.new("TextLabel")
			note.Name = "Note"
			-- 30 rather than 26: sized against the LONGEST string this row can hold, not against a
			-- placeholder. At 17px "The permanent upgrades -- these never reset" is one line in the
			-- 414 px it has, but the box has to survive a re-authored sentence wrapping to two.
			note.Size = UDim2.new(1, -90, 0, 30)
			note.Position = UDim2.new(0, 76, 0, 40)
			note.BackgroundTransparency = 1
			note.Text = spec.note
			note.TextXAlignment = Enum.TextXAlignment.Left
			note.ZIndex = row.ZIndex + UITheme.Z.Content
			note.Parent = row
			themeLabel(note, 17, UITheme.Color.Gold)
		end
	end

	-- ===== THE PRICE STRIP =====
	--
	-- The worth on the left, the button on the right. The worth is the whole reason this card can
	-- ask for money without a discount claim it cannot support: `GetBundleValue` sums what the same
	-- three lines cost on the shop's own cheapest rungs, so the figure is arithmetic over
	-- `RobuxProducts` rather than a number somebody liked the look of.
	local strip = Instance.new("Frame")
	strip.Name = "Price"
	strip.Size = UDim2.new(1, -32, 0, 64)
	strip.Position = UDim2.new(0, 16, 0, contentTop + rowsH + 14)
	strip.BackgroundTransparency = 1
	strip.ZIndex = panel.ZIndex + UITheme.Z.Content
	strip.Parent = panel

	local worth = Instance.new("TextLabel")
	worth.Name = "Worth"
	worth.Size = UDim2.new(1, -250, 0, 28)
	worth.Position = UDim2.new(0, 4, 0, 2)
	worth.BackgroundTransparency = 1
	worth.Text = ("WORTH R$ %d"):format(GameConfig.GetBundleValue(product))
	worth.TextXAlignment = Enum.TextXAlignment.Left
	worth.ZIndex = strip.ZIndex + UITheme.Z.Content
	worth.Parent = strip
	themeLabel(worth, 24, UITheme.Color.Gold)

	local savings = Instance.new("TextLabel")
	savings.Name = "Savings"
	savings.Size = UDim2.new(1, -250, 0, 24)
	savings.Position = UDim2.new(0, 4, 0, 32)
	savings.BackgroundTransparency = 1
	-- DERIVED TOO, and printed as a multiple rather than a percentage because a multiple is the
	-- shape a bundle claim is read in. One decimal: "3.2x" is a number, "3.2154x" is a spreadsheet.
	savings.Text = ("%.1fx what it costs separately"):format(
		math.max(GameConfig.GetBundleValue(product), 1) / math.max(product.price or 1, 1))
	savings.TextXAlignment = Enum.TextXAlignment.Left
	savings.ZIndex = strip.ZIndex + UITheme.Z.Content
	savings.Parent = strip
	themeLabel(savings, 17)

	local buy = Instance.new("TextButton")
	buy.Name = "BuyButton"
	buy.Size = UDim2.new(0, 220, 0, 58)
	buy.Position = UDim2.new(1, -4, 0.5, 0)
	buy.AnchorPoint = Vector2.new(1, 0.5)
	buy.Text = ("R$ %d"):format(product.price or 0)
	buy.ZIndex = strip.ZIndex + UITheme.Z.Content
	buy.Parent = strip
	styleButton(buy, UITheme.Color.Green, UDim.new(0, 16))
	buy.MouseButton1Click:Connect(function()
		-- The KEY, never the id: the server looks it up, so a tampered client can only ever name a
		-- product that exists. It also refuses a zero id with a message of its own, which is what
		-- keeps an unbuilt dashboard row visible to the owner instead of silently dead.
		Remotes.PromptRobuxPurchase:FireServer("StarterPack")
	end)

	--- Open the card, once, when the server says this save has been offered it.
	---
	--- PUBLISHED ON `hud` rather than connected here, so the one place that decides when a card may
	--- interrupt stays in MainUI beside the other join-time cards. `WelcomeBack` has the same shape
	--- and for the same reason.
	function hud.starterPackOffer()
		if shown then return end
		shown = true
		task.spawn(function()
			-- Wait for the OBJECT, not for a delay. `LoadingScreen` holds for MIN_SHOW 2.6 s and
			-- fades for another 0.45, but it also waits on the HUD and on preloading, so the real
			-- number is a range. Bounded at 20 s so a screen that never goes cannot park this card
			-- forever.
			local pg = player:FindFirstChild("PlayerGui")
			local screen = pg and pg:FindFirstChild("LoadingScreen")
			local waited = 0
			while screen and screen.Parent and waited < 20 do
				waited += task.wait(0.1)
			end
			task.wait(0.35)
			-- Stand down in front of anything the player opened themselves. The offer is not lost --
			-- the store's hero carries it until they spend -- and an offer that covers a screen
			-- somebody chose is the one thing that would make this card resented.
			for _, p in ipairs(togglePanels) do
				if p.Visible then return end
			end
			toggleOnly(panel)
		end)
	end

	-- The server fires this exactly once per save, having already stamped `StarterPackShown`. There
	-- is no inbound partner: nothing this client does can re-arm it.
	--
	-- `WaitForChild` IN A THREAD, NOT `FindFirstChild`, and `luaremotes.py` is what caught the first
	-- version of this line. `StarterPackOffer` is created by `RobuxShopService` at module load, and
	-- that runs after `ServerMain` spends a minute building the world -- while this file is required
	-- during the HUD's own build. A `FindFirstChild` here is nil on every join that is faster than
	-- the boot, connects to nothing, and the card is then never shown to anybody, silently and
	-- permanently. Spawned because the require chain above must not yield: MainUI builds the HUD
	-- inline, so a wait on this line would hold every panel after it.
	task.spawn(function()
		local offer = Remotes:WaitForChild("StarterPackOffer", 120)
		if not offer then
			warn("[StarterPack] StarterPackOffer never arrived -- the join card cannot be shown")
			return
		end
		offer.OnClientEvent:Connect(function()
			if hud.starterPackOffer then hud.starterPackOffer() end
		end)
	end)
end
