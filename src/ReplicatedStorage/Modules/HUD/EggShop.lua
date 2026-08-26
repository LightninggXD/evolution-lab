-- EggShop -- the egg stall panel: the three eggs, their odds table and the hatch buttons (10.19).
--
-- MOVED OUT OF `MainUI` (18.9), byte for byte. It was already a closed
-- `;(function() ... end)()` block -- the shape this file's 200-register ceiling forces
-- every panel into -- so the extraction is a change of wrapper, not of code. See
-- `docs/SPLIT.md` for the `hud` contract and `docs/CODEMAP.md` for where the rest went.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))

local Remotes = RS.Remotes
local player = Players.LocalPlayer

local formatNumber, themeLabel, styleCard, styleButton = UIKit.formatNumber, UIKit.themeLabel, UIKit.styleCard, UIKit.styleButton
local setButtonColor, PANEL_SHELL = UIKit.setButtonColor, UIKit.PANEL_SHELL

return function(hud)
	local PANEL_ANCHOR, panelClose, registerPanel = hud.PANEL_ANCHOR, hud.panelClose, hud.registerPanel
	-- `hud.robuxPanel` was the third name on this line until 18.12 deleted the panel behind it; the
	-- one place that used it now calls `hud.openStore` at press time. `toggleOnly` stays -- this
	-- module still owns a panel of its own.
	local screenGui, toggleOnly = hud.screenGui, hud.toggleOnly

	-- ===== NO HUD TILE OF ITS OWN (11.18), BUT A DOOR AGAIN (12.8) =====
	--
	-- 12.8 did not put the ninth tile back. `hud.showEggPanel` is reachable from the Market
	-- flyout now (one tile, two buttons, built near the layout pass at the bottom of this file), and
	-- it is called with NO egg key from there -- so the panel opens on Basic in the player's own
	-- zone, prices and odds live, and the hatch buttons stay locked until they are standing at a
	-- podium. The paragraph below is why the dedicated tile is not coming back, and it still holds:
	-- a HUD button that cannot say which egg you are looking at should not be the one people use.
	--
	--
	-- "The egg screen belongs on the egg." This panel used to be reachable only from a tile in the
	-- corner of the screen -- the ninth in the right column -- while the podium the player had
	-- actually walked to carried two prompts that bought eggs and showed nothing. The two halves of
	-- the feature were in the two places the other one was not.
	--
	-- The prompt on the egg opens it now (PetService stamps `ShopPanel = "eggs"` on it, so it
	-- arrives through the one ProximityPromptService handler at the bottom of this file, beside the
	-- fusion lab and the upgrade counters). The tile is deleted rather than kept as a second route,
	-- for the reason the fusion lab already documents: two ways in means the one that cannot show
	-- you which egg you are standing at is the one people use. RIGHT_COUNT went 9 -> 8 with it.
	--
	-- The panel itself is unchanged, and `hud.refreshEggPanel` is still called from refreshUI.

	local panel = Instance.new("Frame")
	panel.Name = "EggPanel"
	panel.Size = UDim2.new(0, 470, 0, 556)
	panel.Position = PANEL_ANCHOR
	panel.ZIndex = 20
	panel.Visible = false
	panel.Parent = screenGui
	styleCard(panel, PANEL_SHELL, UDim.new(0, 22), 5)
	registerPanel(panel)
	panelClose(panel)

	-- Converted to the shared accent band (17.x). Every child below moved down 36 and the panel grew
	-- by the same 36. The TITLE handle is kept because `refreshEggPanel` rewrites it per stall
	-- ("Forest Eggs"), which is exactly the case PanelHeader's third return value exists for --
	-- anything that TICKS belongs in the subtitle, but a name that changes with the place you are
	-- standing is still a name. Sunny because an egg stall is the gold-rush corner of the game.
	local title = select(3, UITheme.PanelHeader(panel, {
		title = "\u{1F95A} Eggs",
		subtitle = "Odds are per hatch",
		accent = UITheme.Color.Sunny,
	}))

	-- WHICH STALL THE PLAYER IS STANDING AT, or nil. Read off the same ProximityPrompts PetService
	-- wired -- their `EggKey` attribute is already the authority on which egg a podium sells, so
	-- this needs no new attribute, no new remote and no second source of truth. Distance is measured
	-- against the prompt's OWN MaxActivationDistance for the reason PetService gives for Auto Hatch:
	-- it is the range the player can SEE they are in, so anything else reads as arbitrary.
	local function nearestEggZone()
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local zones = workspace:FindFirstChild("Zones")
		if not (hrp and zones) then return nil end
		local bestZone, bestDist = nil, nil
		for _, zoneModel in ipairs(zones:GetChildren()) do
			local shop = zoneModel:FindFirstChild("PetShop")
			if shop then
				for _, prompt in ipairs(shop:GetDescendants()) do
					if prompt:IsA("ProximityPrompt") and prompt:GetAttribute("EggKey") then
						local anchor = prompt.Parent
						if anchor and anchor:IsA("BasePart") then
							local d = (anchor.Position - hrp.Position).Magnitude
							if d <= prompt.MaxActivationDistance and (not bestDist or d < bestDist) then
								bestZone, bestDist = zoneModel.Name, d
							end
						end
					end
				end
			end
		end
		return bestZone
	end

	-- Which zone's three eggs are on show. Falls back to the zone the save says the player is in, so
	-- the panel is a useful price/odds list from anywhere -- only the BUY is gated on standing there.
	local shownZone = nil
	local selectedTier = "Basic"

	local tierRow = Instance.new("Frame")
	tierRow.Name = "TierRow"
	tierRow.Size = UDim2.new(1, -36, 0, 54)
	tierRow.Position = UDim2.new(0, 18, 0, 94)
	tierRow.BackgroundTransparency = 1
	tierRow.ZIndex = panel.ZIndex + UITheme.Z.Content
	tierRow.Parent = panel

	local tierButtons = {}
	for i, suffix in ipairs({ "Basic", "Better", "Premium" }) do
		local btn = Instance.new("TextButton")
		btn.Name = suffix
		btn.Size = UDim2.new(0.32, 0, 1, 0)
		btn.Position = UDim2.new((i - 1) * 0.34, 0, 0, 0)
		btn.Text = suffix
		btn.ZIndex = tierRow.ZIndex
		btn.Parent = tierRow
		styleButton(btn, UITheme.Color.Locked, UDim.new(0, 14))
		tierButtons[suffix] = btn
	end

	local costLabel = Instance.new("TextLabel")
	costLabel.Name = "Cost"
	costLabel.Size = UDim2.new(1, -36, 0, 26)
	costLabel.Position = UDim2.new(0, 18, 0, 154)
	costLabel.BackgroundTransparency = 1
	costLabel.TextXAlignment = Enum.TextXAlignment.Left
	costLabel.Text = ""
	costLabel.ZIndex = panel.ZIndex + UITheme.Z.Content
	costLabel.Parent = panel
	themeLabel(costLabel, 22, Color3.fromRGB(46, 34, 66))

	local oddsScroll = Instance.new("ScrollingFrame")
	oddsScroll.VerticalScrollBarInset = Enum.ScrollBarInset.Always
	oddsScroll.ScrollBarThickness = 12
	oddsScroll.Name = "OddsScroll"
	oddsScroll.Size = UDim2.new(1, -36, 0, 232)
	oddsScroll.Position = UDim2.new(0, 18, 0, 186)
	oddsScroll.BackgroundTransparency = 1
	oddsScroll.BorderSizePixel = 0
	oddsScroll.ScrollBarThickness = 12
	oddsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	oddsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	oddsScroll.ZIndex = panel.ZIndex + UITheme.Z.Content
	oddsScroll.Parent = panel

	local oddsLayout = Instance.new("UIListLayout")
	oddsLayout.Padding = UDim.new(0, 6)
	oddsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	oddsLayout.Parent = oddsScroll

	-- ===== TWO BUTTONS, ONE ROW, AND NO HAND ARITHMETIC (11.3) =====
	--
	-- THE OVERLAPPING PAIR IS HATCH AND HATCH x10, not Hatch and Auto Hatch as the report reads it.
	-- Auto Hatch is on its own full-width line 60 px below and never touched anything. Measured, on
	-- a 470-wide panel: both of these were `0.48` (225.6 px each), one placed from x=18 and the
	-- other anchored to the right edge at 452 -- so they ran into each other by 17.2 px, and looked
	-- like more because styleCard's UIStroke draws OUTSIDE the frame, adding 5 px to each side of
	-- both. 225.6 + 225.6 + 36 of margin is 487 in a panel 470 wide; the two fractions were the bug.
	--
	-- A horizontal UIListLayout divides the row it is given instead of each button being told a
	-- fraction of the PANEL, so the gap is stated once as padding and neither one can be sized into
	-- its neighbour again -- including after the height shrink in `styleButton`, which is the sort
	-- of global change that turns hand arithmetic like this into a defect somewhere else.
	local actionRow = Instance.new("Frame")
	actionRow.Name = "ActionRow"
	-- 44, the shrunk primary height, written here rather than left at 50: both children fill the
	-- row (`1, 0` on Y), so the row owns their height and `styleButton`'s shrink -- which only ever
	-- rewrites an OFFSET height -- correctly does not touch them.
	actionRow.Size = UDim2.new(1, -36, 0, 44)
	actionRow.Position = UDim2.new(0, 18, 0, 432)
	actionRow.BackgroundTransparency = 1
	actionRow.ZIndex = panel.ZIndex + UITheme.Z.Content
	actionRow.Parent = panel

	local actionLayout = Instance.new("UIListLayout")
	actionLayout.FillDirection = Enum.FillDirection.Horizontal
	-- 24, NOT the 12 this was first written with, and the difference is the outline. `styleCard`'s
	-- UIStroke is 5 px and draws OUTSIDE the frame it belongs to, so the two buttons each spend 5
	-- of the gap before any daylight appears between them: a 12 px frame gap measured 2 px of
	-- actual space and the pair read as one merged bar, which is the crowding this row exists to
	-- remove rather than the overlap arithmetic it was reported as. 24 leaves 14 visible.
	--
	-- GENERAL RULE FOR THIS UI: a gap of N between two stroked siblings shows as N - 10.
	actionLayout.Padding = UDim.new(0, 24)
	actionLayout.SortOrder = Enum.SortOrder.LayoutOrder
	actionLayout.Parent = actionRow

	local hatchButton = Instance.new("TextButton")
	hatchButton.Name = "Hatch"
	-- half the row minus half the padding, which is the one arithmetic left and it cannot drift:
	-- 24 of padding split between two children is 12 each
	hatchButton.Size = UDim2.new(0.5, -12, 1, 0)
	hatchButton.LayoutOrder = 1
	hatchButton.Text = "HATCH"
	hatchButton.ZIndex = actionRow.ZIndex + UITheme.Z.Content
	hatchButton.Parent = actionRow
	styleButton(hatchButton, UITheme.Color.Green, UDim.new(0, 14))

	local bulkButton = Instance.new("TextButton")
	bulkButton.Name = "HatchBulk"
	bulkButton.Size = UDim2.new(0.5, -12, 1, 0)
	bulkButton.LayoutOrder = 2
	bulkButton.Text = "HATCH x10"
	bulkButton.ZIndex = actionRow.ZIndex + UITheme.Z.Content
	bulkButton.Parent = actionRow
	styleButton(bulkButton, UITheme.Color.Blue, UDim.new(0, 14))

	local autoButton = Instance.new("TextButton")
	autoButton.Name = "AutoHatch"
	autoButton.Size = UDim2.new(1, -36, 0, 46)
	autoButton.Position = UDim2.new(0, 18, 0, 492)
	autoButton.Text = "AUTO HATCH"
	autoButton.ZIndex = panel.ZIndex + UITheme.Z.Content
	autoButton.Parent = panel
	styleButton(autoButton, UITheme.Color.Locked, UDim.new(0, 14))

	-- ===== REFRESH =====
	local rows = {}
	local function refresh()
		local data = hud.getData()
		if not data then return end

		local nearZone = nearestEggZone()
		shownZone = nearZone or data.CurrentZone or "Forest"
		title.Text = ("\u{1F95A} %s Eggs"):format(shownZone)

		-- the egg being described, and the honest luck it would actually be rolled at
		local egg = nil
		for _, e in ipairs(GameConfig.Eggs) do
			if e.zone == shownZone and e.tierSuffix == selectedTier then egg = e end
		end
		for suffix, btn in pairs(tierButtons) do
			setButtonColor(btn, suffix == selectedTier and UITheme.Color.Purple or UITheme.Color.Locked)
		end
		if not egg then return end

		-- `GetPetLuckPercent` is the egg-side total (shared luck + the shop's Luck upgrade at +5 a
		-- level, 11.5). It is what `rollAndInsert` rolls against, which is the whole point of this
		-- panel quoting a number at all.
		local luck = GameConfig.GetPetLuckPercent(data) + (egg.luckBonus or 0)
		local affordable = (data.DNA or 0) >= egg.cost
		costLabel.Text = ("%s  \u{2022}  \u{1F340} %d%% luck"):format(formatNumber(egg.cost), math.floor(luck))

		-- ONE ROW PER SPECIES, REBUILT ONLY WHEN THE POOL CHANGES. The odds themselves are rewritten
		-- every refresh (luck moves with potions and pets), but the rows are reused -- rebuilding a
		-- dozen cards on every DataUpdate is what made the pet list flicker.
		local odds = GameConfig.GetEggOdds(egg, luck)
		local key = egg.key
		if rows.key ~= key then
			for _, r in ipairs(rows) do r:Destroy() end
			table.clear(rows)
			rows.key = key
			for i, entry in ipairs(odds) do
				local rarity = GameConfig.GetRarity(entry.def.rarity)
				local row = Instance.new("Frame")
				row.Name = entry.def.key
				row.Size = UDim2.new(1, -10, 0, 52)
				row.LayoutOrder = i
				row.ZIndex = oddsScroll.ZIndex
				row.Parent = oddsScroll
				styleCard(row, rarity.color, UDim.new(0, 12), 3)

				UITheme.IconSlot(row, {
					name = "Icon", icon = entry.def.emoji, maxTextSize = 28,
					size = UDim2.new(0, 42, 1, -10), position = UDim2.new(0, 8, 0, 5),
				})

				local nameLabel = Instance.new("TextLabel")
				nameLabel.Name = "NameLabel"
				nameLabel.Size = UDim2.new(1, -160, 0, 24)
				nameLabel.Position = UDim2.new(0, 58, 0, 5)
				nameLabel.BackgroundTransparency = 1
				nameLabel.TextXAlignment = Enum.TextXAlignment.Left
				nameLabel.Text = entry.def.name
				nameLabel.Parent = row
				themeLabel(nameLabel, 20)

				local rarityLabel = Instance.new("TextLabel")
				rarityLabel.Name = "Rarity"
				rarityLabel.Size = UDim2.new(1, -160, 0, 20)
				rarityLabel.Position = UDim2.new(0, 58, 0, 27)
				rarityLabel.BackgroundTransparency = 1
				rarityLabel.TextXAlignment = Enum.TextXAlignment.Left
				rarityLabel.Text = rarity.name
				rarityLabel.Parent = row
				themeLabel(rarityLabel, 16, UITheme.Color.Cream)

				local pct = Instance.new("TextLabel")
				pct.Name = "Chance"
				pct.Size = UDim2.new(0, 96, 1, -10)
				pct.Position = UDim2.new(1, -10, 0, 5)
				pct.AnchorPoint = Vector2.new(1, 0)
				pct.BackgroundTransparency = 1
				pct.TextXAlignment = Enum.TextXAlignment.Right
				pct.Text = ""
				pct.Parent = row
				themeLabel(pct, 24)

				table.insert(rows, row)
			end
		end
		for i, entry in ipairs(odds) do
			local row = rows[i]
			local pct = row and row:FindFirstChild("Chance")
			if pct then
				-- `entry.text` when the entry brought its own (the 12.12 Secret row, quoted as
				-- "1 in 50,000"): two decimals cannot express a 0.002% chance and would print
				-- "0.00%", which is the same lie one order of magnitude further down.
				-- Otherwise two decimals under 1%, because "0%" on a Legendary is a lie the player
				-- can disprove.
				pct.Text = entry.text or (entry.chance < 1
					and ("%.2f%%"):format(entry.chance)
					or ("%.1f%%"):format(entry.chance))
			end
		end

		-- ===== THE BUY IS GATED ON STANDING AT THE STALL, AND SAYS SO =====
		--
		-- Not because the server enforces it -- it does NOT, see the note in STATUS.md about the
		-- unused IsNearPetShop -- but because the podium is where the hatch animation plays and
		-- where the prompts are. A button that silently works from across the map would make the
		-- stall pointless; one that greys out with no reason given is the "claim buttons do nothing"
		-- complaint all over again. So it states the requirement.
		if not nearZone then
			setButtonColor(hatchButton, UITheme.Color.Locked)
			setButtonColor(bulkButton, UITheme.Color.Locked)
			hatchButton.Text = "GO TO A PET SHOP"
			bulkButton.Text = "\u{1F512}"
		else
			setButtonColor(hatchButton, affordable and UITheme.Color.Green or UITheme.Color.Locked)
			setButtonColor(bulkButton, ((data.DNA or 0) >= egg.cost * 10) and UITheme.Color.Blue or UITheme.Color.Locked)
			hatchButton.Text = affordable and "HATCH" or "NEED DNA"
			bulkButton.Text = "HATCH x10"
		end

		-- Auto Hatch: owned or not, on or off. `nil` counts as ON, exactly as DriveAutoHatch reads it
		-- (only an explicit `false` stops it) -- so a pass owner who has never touched this sees the
		-- true state rather than an OFF that does not match what the server is doing.
		if GameConfig.OwnsPass(data, "AutoHatch") then
			local on = player:GetAttribute("AutoHatch") ~= false
			setButtonColor(autoButton, on and UITheme.Color.Green or UITheme.Color.Locked)
			autoButton.Text = on and "\u{1F504} AUTO HATCH: ON" or "\u{1F504} AUTO HATCH: OFF"
		else
			setButtonColor(autoButton, UITheme.Color.Gold)
			autoButton.Text = "\u{1F512} AUTO HATCH \u{2014} GAME PASS"
		end
	end

	for suffix, btn in pairs(tierButtons) do
		btn.MouseButton1Click:Connect(function()
			selectedTier = suffix
			refresh()
		end)
	end

	hatchButton.MouseButton1Click:Connect(function()
		local egg = nil
		for _, e in ipairs(GameConfig.Eggs) do
			if e.zone == shownZone and e.tierSuffix == selectedTier then egg = e end
		end
		-- Fired unconditionally when in range rather than gated on the local affordability check:
		-- the client's copy of the save is up to a push behind, and the server's own "Not enough
		-- DNA" toast is better than a button that silently does nothing. Same rule as the spins.
		if egg and nearestEggZone() then
			Remotes.BuyEgg:FireServer(egg.key)
		end
	end)

	bulkButton.MouseButton1Click:Connect(function()
		local egg = nil
		for _, e in ipairs(GameConfig.Eggs) do
			if e.zone == shownZone and e.tierSuffix == selectedTier then egg = e end
		end
		local bulk = Remotes:FindFirstChild("BuyEggBulk")
		if egg and bulk and nearestEggZone() then
			bulk:FireServer(egg.key)
		end
	end)

	autoButton.MouseButton1Click:Connect(function()
		if not (hud.getData() and GameConfig.OwnsPass(hud.getData(), "AutoHatch")) then
			-- Sends them to the shop rather than doing nothing at all: this is the one control in
			-- the panel a player can press without owning what it needs.
			--
			-- ===== AND IT NAMES THE PASS IT WANTS (18.12) =====
			--
			-- This used to be `selectRobuxTab(true)` + `toggleOnly(hud.robuxPanel)` -- the old
			-- 640 x 640 store had a Passes tab and this asked for it. That panel is deleted;
			-- `UIComponents.ShopPanel` is one list with the nine passes sorted after the seventeen
			-- products (`LayoutOrder` 1000+), so opening it bare would land the player at the top
			-- of the products with the thing they actually pressed for below the fold. The key is
			-- a SCROLL HINT and nothing else -- it cannot change what is sold or what is buyable,
			-- and `PassService` re-checks ownership server-side however the card was reached.
			if hud.openStore then hud.openStore("AutoHatch") end
			return
		end
		local remote = Remotes:FindFirstChild("SetAutoHatch")
		if remote then
			remote:FireServer(player:GetAttribute("AutoHatch") == false)
		end
	end)

	player:GetAttributeChangedSignal("AutoHatch"):Connect(refresh)

	-- ===== OPENED BY THE EGG IN FRONT OF YOU (11.18) =====
	--
	-- `eggKey` is the attribute PetService already keeps on every podium prompt for Auto Hatch, so
	-- the panel can open ON THE EGG THE PLAYER PRESSED rather than always on Basic. That is the
	-- difference between "the egg screen" and "a shop that happens to be near an egg": press the
	-- Premium podium and the odds table you get is Premium's.
	--
	-- Falls back to Basic when the key does not resolve, which is also what happens for any future
	-- caller with nothing to say -- the same "selected fresh on every open" rule the HUD tile had,
	-- and for the same reason: the player has almost certainly walked to a different stall since
	-- last time, and reopening on a zone they have left is the same class of bug as a panel
	-- reopening at yesterday's scroll position.
	hud.showEggPanel = function(eggKey)
		selectedTier = "Basic"
		if eggKey then
			for _, e in ipairs(GameConfig.Eggs) do
				if e.key == eggKey and e.tierSuffix then
					selectedTier = e.tierSuffix
					break
				end
			end
		end
		refresh()
		toggleOnly(panel)
	end

	-- Ticked while the panel is open so walking up to a stall unlocks the buttons without the
	-- player having to close and reopen it. One second is plenty for "am I standing there".
	task.spawn(function()
		while true do
			task.wait(1)
			if panel.Visible then
				refresh()
			end
		end
	end)

	hud.refreshEggPanel = refresh
end
