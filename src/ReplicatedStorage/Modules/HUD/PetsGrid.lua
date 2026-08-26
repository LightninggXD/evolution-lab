-- PetsGrid -- the bag itself: the scroll, the tiles in it, and the one turntable that turns them.
--
-- ===== WHAT MOVED HERE, AND WHY IT LEFT MainUI (2026-08-23) =====
--
-- The pets grid was ~470 lines inside `MainUI.client.lua`, which is Kristina's standing objection to
-- god files -- *"ne pravi god script ... sve buduce fajlove pravi u vise manjih celina"* -- and also
-- a register problem: that file's top level is one Luau function with a 200-register ceiling it has
-- already crossed once, taking the entire HUD down with it. The redesign added a detail board and a
-- tile builder, so the block was going to grow rather than shrink.
--
-- Three files rather than one, split where the SEAMS actually are:
--   * `PetTile`   -- one pet, drawn. Knows nothing about the collection.
--   * `PetDetail` -- one pet, described, plus the two actions that came off the tile.
--   * this file   -- the collection: what order, what is worn, what is selected, what to rebuild.
--
-- ===== THE CLICK SELECTS; THE BOARD'S BUTTON EQUIPS (KRISTINA, 2026-08-23) =====
--
-- Asked before building, her first answer was that the click should equip. **She reversed it after
-- seeing it run** -- *"kad ga kliknem automatski se equipa a ima pored equip opcija desno"* -- and
-- the objection is exact: with an EQUIP button on the board, a click that also equips makes the
-- button a second control for a thing that has already happened. One of the two had to go, and the
-- one she kept is the button.
--
-- So a tile click **opens the pet on the board and does nothing else**. It costs the main verb a
-- second click, which is the real price of the choice, and buys two things: browsing a hundred pets
-- can no longer re-equip your team by accident, and every verb in the panel now lives in exactly one
-- place -- equip, enchant and release are all buttons on the board, and the grid is for choosing
-- what to look at.
--
-- **AND "SELECTED" NOW MEANS TWO THINGS, WHICH IS ITS OWN TRAP.** Select mode's corner checkbox
-- means *in the batch I am about to release*; this new one means *the pet the board is describing*.
-- They are drawn differently on purpose -- see `SelectionPlate` in `PetTile`.
--
-- ===== SHUT MEANS SKIPPED (11.32), AND IT IS WHY THIS IS AFFORDABLE =====
--
-- Every refresh destroys and rebuilds each tile, and each tile builds a real `PetModel` rig -- about
-- thirty parts, so a full hundred-pet bag is ~3,000 parts. This used to run on every `DataUpdate`,
-- which the server sends roughly every three seconds AND on every kill, almost always into a panel
-- nobody was looking at. The guard is paired with the `Visible` listener at the bottom, hung on the
-- PROPERTY rather than on the open handlers, because there are three ways into this panel and a
-- fourth would silently open stale.

local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))
local PetModel = require(RS.Modules:WaitForChild("PetModel"))
local PetTile = require(RS.Modules:WaitForChild("HUD"):WaitForChild("PetTile"))
local PetDetail = require(RS.Modules:WaitForChild("HUD"):WaitForChild("PetDetail"))

local themeLabel = UIKit.themeLabel

-- ===== THE GEOMETRY, WHICH IS ONE DECISION IN FOUR NUMBERS =====
--
-- The panel is 772 wide with 22 of margin, so 728 of usable width. The detail board takes 200 and a
-- 16 gap, leaving 512 for the scroll. Five columns of 92 on 10 of padding is 5*92 + 4*10 = 500,
-- with 12 spare for the 6 px scrollbar and its own outline.
--
-- **The panel's width did not change, and that is deliberate.** `PetsActions` derives its header
-- pill's position from a 772-wide board in a written-out comment ("the X owns x 742..794 of a
-- 772-wide board"), and narrowing the panel to fit an outboard card would have silently invalidated
-- that reasoning along with the action row's own layout.
local SCROLL_W = 512
local GRID_TOP = 120     -- clear of the tab strip at 52..90 and the odds line at 94
local BOTTOM = 194       -- the action row sits on the bottom edge; 30.10's number, unchanged

return function(hud)
	local petsPanel = hud.petsPanel
	local flatText, colorTag = hud.flatText, hud.colorTag

	local petsScroll = Instance.new("ScrollingFrame")
	petsScroll.VerticalScrollBarInset = Enum.ScrollBarInset.Always
	petsScroll.ScrollBarThickness = 12
	petsScroll.Name = "PetsScroll"
	petsScroll.Size = UDim2.new(0, SCROLL_W, 1, -BOTTOM)
	petsScroll.Position = UDim2.new(0, 22, 0, GRID_TOP)
	petsScroll.BackgroundTransparency = 1
	petsScroll.BorderSizePixel = 0
	petsScroll.ScrollBarThickness = 12
	-- Grey, not white: 25.4's sweep found nine lists in this game wearing a white bar on a white
	-- sheet, which is a scrollbar that only exists for people who already know it is there.
	petsScroll.ScrollBarImageColor3 = Color3.fromRGB(186, 192, 214)
	petsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	petsScroll.ZIndex = petsPanel.ZIndex + UITheme.Z.Content
	petsScroll.Parent = petsPanel

	do
		local grid = Instance.new("UIGridLayout")
		-- THREE NUMBERS EXPRESSING ONE DECISION: this, `PetTile.CELL_*`, and the row height in the
		-- CanvasSize line at the end of `refresh`. A grid cell shorter than the tile inside it
		-- silently overlaps the row below -- which is how the old 126/156 pair was found.
		grid.CellSize = UDim2.new(0, PetTile.CELL_W, 0, PetTile.CELL_H)
		grid.CellPadding = UDim2.new(0, PetTile.PAD, 0, PetTile.PAD)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = petsScroll
	end

	-- Parented to the PANEL, not to the scroll: inside a `UIGridLayout` it would be laid out as a
	-- cell and push the first pet out of place.
	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.Name = "EmptyLabel"
	emptyLabel.Size = UDim2.new(0, SCROLL_W - 40, 0, 60)
	emptyLabel.Position = UDim2.new(0, 42, 0, 154)
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.TextWrapped = true
	emptyLabel.ZIndex = petsPanel.ZIndex + UITheme.Z.Content
	emptyLabel.Text = "No pets yet \u{2014} visit a Pet Shop in any zone to buy an egg!"
	emptyLabel.Parent = petsPanel
	flatText(themeLabel(emptyLabel, 22, Color3.fromRGB(150, 154, 168)))

	-- Top-aligned with the grid and as tall as its own content -- see `PetDetail.HEIGHT` for why it
	-- is deliberately NOT the scroll's height.
	local detail = PetDetail.Build(petsPanel, hud, GRID_TOP)

	-- ===== THE ODDS, WHERE THE MONEY IS SPENT (13.4) =====
	--
	-- Built from `GameConfig.Enchants` itself, never typed out: the weights sum to 100 by contract
	-- (`AssertEnchantWeights` warns if they stop), so a weight IS a percentage and this line cannot
	-- drift from what `RollEnchant` actually does. Every rung prints in its own colour -- the same
	-- colour its chip wears on the detail board -- so the strip doubles as that chip's legend.
	--
	-- ONE STRIP FOR THE WHOLE PANEL rather than a line per pet: the odds are a property of the
	-- ladder, not of the pet, and with a hundred tiles on screen there is nowhere to put them twice.
	do
		local odds = Instance.new("TextLabel")
		odds.Name = "EnchantOdds"
		-- Full inner width, above the grid. Measured at 689 px for the authored 16 px, which is why
		-- it may not share a row with anything: at 360 px it hit `themeLabel`'s 8 px floor and STILL
		-- overflowed, i.e. an unreadable line that also lied about the odds by cutting its tail off.
		odds.Size = UDim2.new(1, -44, 0, 22)
		odds.Position = UDim2.new(0, 22, 0, 94)
		odds.BackgroundTransparency = 1
		odds.RichText = true
		odds.TextXAlignment = Enum.TextXAlignment.Left
		odds.ZIndex = petsPanel.ZIndex + UITheme.Z.Content
		local parts = {}
		for _, e in ipairs(GameConfig.Enchants) do
			-- shade(-0.35) because these sit on a white sheet: the chip colours are chosen to read
			-- as FILLS, not as ink.
			table.insert(parts, colorTag(("%s %g%%"):format(e.name, e.weight),
				UIKit.shade(e.color, -0.35)))
		end
		odds.Text = "\u{2728} Enchant odds:  " .. table.concat(parts, "  \u{00B7}  ")
		odds.Parent = petsPanel
		flatText(themeLabel(odds, 16, Color3.fromRGB(150, 154, 168)))
	end

	-- Live rigs shown in the tiles, kept in a list so ONE RenderStepped turns all of them.
	local rigs = {}

	-- The tile currently wearing the selection plate. Held as a SETTER rather than as the tile, so
	-- moving the highlight cannot accidentally reach for anything else on a destroyed instance.
	local clearShown

	local function refresh()
		local data = hud.getData and hud.getData()
		if not data then return end
		if not petsPanel.Visible then return end

		for _, child in ipairs(petsScroll:GetChildren()) do
			-- Matched on NAME alone. The old clear tested `IsA("Frame")` after the cell had become a
			-- TextButton, so it silently stopped clearing anything and every refresh stacked another
			-- full copy of the collection into the grid.
			if child.Name == "PetTile" then child:Destroy() end
		end
		table.clear(rigs)   -- the rigs went with the tiles they were parented to

		emptyLabel.Visible = (#data.Pets == 0)

		local equippedLookup = {}
		for _, id in ipairs(data.EquippedPetIds) do equippedLookup[id] = true end

		-- Strongest first. `data` IS THE SECOND ARGUMENT and its absence was a real bug once: without
		-- it `GetPetPower` drops the zone axis and quotes every pet at its own home zone's strength,
		-- so the drawn order stopped matching the one Equip Best acted on.
		local ranked = GameConfig.SortedPetsByPower(data.Pets, data)

		-- ===== PRUNE THE SELECTION AGAINST WHAT STILL EXISTS (11.17) =====
		--
		-- The set is keyed by pet id and outlives the tiles, which is what makes it survive this
		-- rebuild -- but it also means a pet that left the save by some other route while select mode
		-- was open (a fusion, a release, a trade) would stay ticked in a set nobody can see, and the
		-- RELEASE button's count would exceed the ticks on screen. Which is the one thing a confirm
		-- dialog must never be.
		local sel = hud.petSelect
		if sel and sel.n > 0 then
			local alive, dropped = {}, false
			for _, p in ipairs(data.Pets) do alive[p.id] = true end
			for id in pairs(sel.ids) do
				if not alive[id] then
					sel.ids[id] = nil
					sel.n -= 1
					dropped = true
				end
			end
			if dropped and hud.petSelectRepaint then hud.petSelectRepaint() end
		end

		hud.petSlotCount.Text = ("%d/%d"):format(#data.EquippedPetIds, GameConfig.GetMaxEquippedPets(data))
		-- "17 / 30" rather than "17": a bare number cannot tell a player they are one hatch from
		-- being refused, and being refused at the podium with no warning is how the cap read as a
		-- bug. `>=` rather than `==` because a grandfathered save can sit above it.
		local owned, cap = #data.Pets, GameConfig.MaxOwnedPets
		hud.petOwnedCount.Text = ("%d/%d"):format(owned, cap)
		local capsule = hud.petOwnedCount.Parent
		if capsule then
			capsule.BackgroundColor3 = (owned >= cap) and UITheme.Color.Red
				or (owned >= cap - 3) and UITheme.Color.Orange
				or UITheme.Color.Blue
		end

		local selecting = sel and sel.on
		-- ===== THE BOARD FOLLOWS THE SAVE, NOT THE LAST CLICK =====
		--
		-- Re-shown off the pet's CURRENT row rather than the table captured when it was clicked: an
		-- enchant rolled from the board's own button changes `pet.enchant`, and a board still drawing
		-- the pre-roll copy would quote the old multiplier beside the new one on the tile. If the pet
		-- has left the save entirely the board clears rather than describing something gone.
		local shownId, stillThere = detail.CurrentId(), nil

		for i, pet in ipairs(ranked) do
			local info = hud.petDisplayInfo(pet.key)
			local rarity = GameConfig.GetRarity(info.rarity)
			local isEquipped = equippedLookup[pet.id] == true
			if pet.id == shownId then stillThere = pet end

			-- `pet.key` and `data` are what make this honest about the zone axis, and `pet.enchant` is
			-- the fifth. The tile quotes exactly the share the damage chain sums.
			local bonus = GameConfig.GetPetBonus(pet.tier, info.rarity, pet.key, data, pet.enchant)
			local damageText = ("+%d%%"):format(math.floor((bonus.damageMult - 1) * 100 + 0.5))

			local _, setTicked, rigEntry, setShown = PetTile.Build(petsScroll, {
				pet = pet,
				info = info,
				rarity = rarity,
				isEquipped = isEquipped,
				damageText = damageText,
				order = i,
				selecting = selecting,
				selected = selecting and sel.ids[pet.id] == true or false,
				-- survives the rebuild: the board's own pet keeps its plate through every push
				shown = (pet.id == shownId),
				onPrimary = function(p)
					-- Read at CLICK time, not captured: the mode can be toggled between a refresh and
					-- a click, and a captured flag would leave a grid still equipping while the bar
					-- says RELEASE.
					local s = hud.petSelect
					if s and s.on then
						-- An equipped pet is not offered: the server refuses to delete one, so
						-- ticking it would build a selection whose count and whose outcome disagree.
						if isEquipped then return end
						if hud.petSelectToggleId then hud.petSelectToggleId(p.id) end
						-- ONE TILE REPAINTED, NOT THE WHOLE GRID -- a rebuild is a hundred rigs, and
						-- ticking ten boxes must not cost a thousand.
						if setTicked then setTicked(s.ids[p.id] == true) end
						return
					end
					-- ===== AND THAT IS ALL A CLICK DOES NOW =====
					-- No remote. See the header: the EQUIP button on the board is the only thing
					-- that equips, because two controls for one verb is what she objected to.
					if clearShown then clearShown(false) end
					setShown(true)
					clearShown = setShown
					detail.Show(p, hud.getData and hud.getData() or data)
				end,
			})
			if rigEntry then table.insert(rigs, rigEntry) end
			-- The old tiles were destroyed at the top of this function, so a `clearShown` captured
			-- before the rebuild points at a dead plate. Re-pointed at the tile that inherited the
			-- highlight, or dropped below if that pet is gone.
			if pet.id == shownId then clearShown = setShown end
		end

		if shownId then
			if stillThere then
				detail.Show(stillThere, data)
			else
				detail.Clear()
				clearShown = nil
			end
		end

		-- Five to a row, cell + padding tall.
		petsScroll.CanvasSize = UDim2.new(0, 0, 0,
			math.ceil(#data.Pets / 5) * (PetTile.CELL_H + PetTile.PAD) + 12)
	end

	hud.refreshPetsPanel = refresh

	-- The other half of the skip-while-shut guard: the grid is rebuilt the moment the panel becomes
	-- visible, off whatever the last push left behind. One connection on the property rather than a
	-- call in each open path, and it cannot fire on a close.
	petsPanel:GetPropertyChangedSignal("Visible"):Connect(function()
		if petsPanel.Visible then refresh() end
	end)

	-- One turntable for every tile, and only while the panel is open: a ViewportFrame costs nothing
	-- when nobody is looking at it, and a pet standing dead still in a box looks like a screenshot of
	-- a pet.
	RunService.RenderStepped:Connect(function()
		if not petsPanel.Visible then return end
		local t = os.clock()
		for _, rig in ipairs(rigs) do
			if rig.root.Parent then
				PetModel.Place(rig.root, rig.pieces,
					CFrame.new(0, math.sin(t * 1.7 + rig.phase) * 0.07, 0)
					* CFrame.Angles(0, math.sin(t * 0.55 + rig.phase) * 0.55, 0))
			end
		end
	end)
end
