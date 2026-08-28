-- PetDetail -- the board beside the bag that says everything one tile cannot.
--
-- ===== WHY THIS FILE EXISTS (2026-08-23) =====
--
-- It is the other half of Kristina's reference layout. Hers is a grid of small tiles with a separate
-- card standing beside it holding the selected pet's name, its variant, its multiplier and its
-- rarity -- and that card is what BUYS the dense grid: the tile can afford to carry one number
-- because this board carries the other six things the old 232 x 156 card was printing on every pet
-- in the collection, a hundred times over.
--
-- It also collects the two ACTIONS that came off the tile:
--
--   * **Enchant.** It was a button on every card -- a hundred price buttons drawn to be pressed
--     about twice a session. It is a decision about one pet, so it belongs where one pet is.
--   * **Release.** It was a small x in the card's top-right corner, and the reference has no such
--     thing: releasing is the bin in the action row. A destructive control is the one that must be
--     AIMED at, and a 26 px x sitting on the equip target in a grid of a hundred is the opposite.
--
-- ===== IT SITS INSIDE THE PANEL, AND THAT IS A DELIBERATE DEPARTURE =====
--
-- In her capture the card floats OUTSIDE the board's right edge. Ours is a child of the panel and
-- inside its right margin, drawn as its own raised board with a gap so it still reads as a separate
-- thing. The reason is width: the panel is 772 and centred, so an outboard card would put its right
-- edge 250 px past the panel's -- fine on this monitor, off the screen entirely on a 1024-wide
-- window, and there is no viewport this game can refuse to open on. The same class of fault as
-- sizing a canvas off `AbsoluteContentSize`: correct on the machine it was authored on and broken
-- on every phone.
--
-- ===== EMPTY IS A STATE IT DRAWS, NOT A FRAME IT HIDES =====
--
-- Nothing is selected when the panel opens, and a 200 px hole beside the grid would read as a panel
-- that failed to load. It says so instead.

local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))

local themeLabel, styleCard, styleButton = UIKit.themeLabel, UIKit.styleCard, UIKit.styleButton

local Remotes = RS:WaitForChild("Remotes")

local PetDetail = {}

PetDetail.WIDTH = 200

-- ===== ITS HEIGHT IS ITS CONTENT'S, NOT THE GRID'S, AND THE FIRST CUT GOT THAT WRONG =====
--
-- It shipped 394 tall -- the scroll's height -- with its three buttons pinned to the bottom edge, and
-- the capture showed 110 px of empty sheet between the enchant chip and the EQUIP button. That is
-- **exactly the fault 30.10 closed on the Relics panel one commit earlier**, reintroduced on a new
-- surface an hour later: a board sized to its neighbour rather than to what it holds.
--
-- 296 is the sum and nothing else: 12 top + 30 name + 20 sub + 8 + 40 stat + 8 + 26 chip + 14 +
-- 40 equip + 8 + 38 enchant + 8 + 36 release + 12 foot. **A card beside a grid does not have to be
-- as tall as the grid** -- it is not in Kristina's reference either, where the card is visibly the
-- shorter of the two.
PetDetail.HEIGHT = 338

--- Builds the board into `panel` and returns `show(pet, data)` / `clear()`.
--- `hud` supplies `colorTag`, `flatText`, `petDisplayInfo` and `confirmRelease`.
function PetDetail.Build(panel, hud, top)
	local colorTag, flatText = hud.colorTag, hud.flatText

	local board = Instance.new("Frame")
	board.Name = "PetDetail"
	board.Size = UDim2.new(0, PetDetail.WIDTH, 0, PetDetail.HEIGHT)
	-- Right margin 22, matching every other edge of this panel.
	board.Position = UDim2.new(1, -22, 0, top)
	board.AnchorPoint = Vector2.new(1, 0)
	board.ZIndex = panel.ZIndex + UITheme.Z.Content
	board.Parent = panel
	-- Frost rather than the panel's own near-white: two white boards with a gap between them read as
	-- one board with a seam. A half-step of grey is what makes it a separate object.
	styleCard(board, UITheme.Color.Frost, UDim.new(0, 14), 3)

	local baseZ = board.ZIndex + UITheme.Z.Content

	-- ===== EMPTY =====
	local empty = Instance.new("TextLabel")
	empty.Name = "Empty"
	empty.Size = UDim2.new(1, -24, 0, 60)
	empty.Position = UDim2.new(0, 12, 0.5, -30)
	empty.BackgroundTransparency = 1
	empty.TextWrapped = true
	empty.ZIndex = baseZ
	empty.Text = "Tap a pet to see what it does"
	empty.Parent = board
	flatText(themeLabel(empty, 18, UITheme.Color.InkSoft))

	-- ===== THE FILLED STATE, BUILT ONCE AND RE-TARGETED =====
	--
	-- Not rebuilt per selection. A click on a tile is the most frequent thing that happens in this
	-- panel and allocating a board's worth of instances on each one -- with the grid already
	-- rebuilding thirty rigs on every data push -- is how a panel becomes the expensive thing in
	-- the HUD. Every label below is written by `show`.
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Size = UDim2.new(1, 0, 1, 0)
	body.BackgroundTransparency = 1
	body.Visible = false
	body.ZIndex = baseZ
	body.Parent = board

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "PetName"
	nameLabel.Size = UDim2.new(1, -20, 0, 30)
	nameLabel.Position = UDim2.new(0, 10, 0, 12)
	nameLabel.BackgroundTransparency = 1
	nameLabel.ZIndex = baseZ + 1
	nameLabel.Parent = body
	flatText(themeLabel(nameLabel, 26, UITheme.Color.Ink))

	-- Rarity and tier on one line, the rarity word in its own colour -- the same `colorTag` the old
	-- card's sub-line used, so the two never disagree about what an Epic looks like.
	local sub = Instance.new("TextLabel")
	sub.Name = "SubLabel"
	sub.Size = UDim2.new(1, -20, 0, 20)
	sub.Position = UDim2.new(0, 10, 0, 42)
	sub.BackgroundTransparency = 1
	sub.RichText = true
	sub.ZIndex = baseZ + 1
	sub.Parent = body
	flatText(themeLabel(sub, 16, UITheme.Color.InkSoft))

	-- ===== THE NUMBER, IN ITS OWN GROOVE =====
	local statBar = Instance.new("Frame")
	statBar.Name = "StatBar"
	statBar.Size = UDim2.new(1, -20, 0, 40)
	statBar.Position = UDim2.new(0, 10, 0, 70)
	statBar.BackgroundColor3 = UIKit.shade(UITheme.Color.Frost, -0.06)
	statBar.BorderSizePixel = 0
	statBar.ZIndex = baseZ + 1
	statBar.Parent = body
	UIKit.corner(statBar, UDim.new(0, 10))

	local statLabel = Instance.new("TextLabel")
	statLabel.Name = "StatLabel"
	statLabel.Size = UDim2.new(1, -12, 1, -6)
	statLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	statLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	statLabel.BackgroundTransparency = 1
	statLabel.ZIndex = statBar.ZIndex + 1
	statLabel.Parent = statBar
	flatText(themeLabel(statLabel, 18, UITheme.Color.Ink))

	-- ===== THE ENCHANT IT WEARS, WHICH IS THE REFERENCE'S "normal" LINE =====
	local enchantChip = Instance.new("TextLabel")
	enchantChip.Name = "EnchantChip"
	enchantChip.Size = UDim2.new(1, -20, 0, 26)
	enchantChip.Position = UDim2.new(0, 10, 0, 118)
	enchantChip.ZIndex = baseZ + 1
	enchantChip.Parent = body

	-- ===== THE THREE BUTTONS =====
	--
	-- Stacked from the top under the chip rather than pinned to the bottom edge. Bottom-pinning is
	-- what a board with slack does; this one has none by construction (see `PetDetail.HEIGHT`), and
	-- pinning against a bottom that is only 12 px below the last button is the same arithmetic
	-- written twice, in two places that can disagree.
	local function actionButton(name, y, h)
		local b = Instance.new("TextButton")
		b.Name = name
		b.Size = UDim2.new(1, -20, 0, h)
		b.Position = UDim2.new(0, 10, 0, y)
		b.ZIndex = baseZ + 1
		b.Parent = body
		return b
	end

	local equipBtn = actionButton("EquipButton", 158, 40)
	local enchantBtn = actionButton("EnchantButton", 206, 36)
	local transferBtn = actionButton("TransferButton", 248, 36)
	local releaseBtn = actionButton("ReleaseButton", 290, 36)

	local current   -- the pet the three buttons are aimed at

	equipBtn.MouseButton1Click:Connect(function()
		if not current then return end
		-- Read at CLICK time from the flag `show` last wrote, never captured when the board was
		-- built: one board serves every pet in the bag and a captured verb would unequip the pet
		-- that happened to be selected first.
		if current.equipped then
			Remotes.UnequipPet:FireServer(current.pet.id)
		else
			Remotes.EquipPet:FireServer(current.pet.id)
		end
	end)

	enchantBtn.MouseButton1Click:Connect(function()
		if not current then return end
		-- Resolved by name at click time: `PetService.Init` creates this one through `ensureRemote`,
		-- so a client that built its HUD first would have captured a nil.
		local r = Remotes:FindFirstChild("EnchantPet")
		if r then
			r:FireServer(current.pet.id)
		else
			warn("[PetDetail] Remotes.EnchantPet never appeared -- enchanting is disabled")
		end
	end)

	releaseBtn.MouseButton1Click:Connect(function()
		if not current then return end
		if hud.confirmRelease then
			hud.confirmRelease(current.pet.id, current.name, current.rarityName, current.rarityColor)
		end
	end)

	transferBtn.MouseButton1Click:Connect(function()
		if not current or not current.pet.enchant then return end
		if hud.openTransferPicker then
			hud.openTransferPicker(current.pet.id)
		end
	end)

	local api = {}

	function api.Clear()
		current = nil
		body.Visible = false
		empty.Visible = true
	end

	--- Draws `pet` off `data`. Called on every tile click AND on every refresh, so that a pet whose
	--- numbers moved -- an enchant rolled, a zone changed, a slot bought -- is redrawn without the
	--- player having to click it again.
	function api.Show(pet, data)
		if not (pet and data) then api.Clear() return end
		local info = hud.petDisplayInfo(pet.key)
		local rarity = GameConfig.GetRarity(info.rarity)

		local equippedLookup = {}
		for _, id in ipairs(data.EquippedPetIds or {}) do equippedLookup[id] = true end
		local isEquipped = equippedLookup[pet.id] == true

		-- The same five-axis call the tile quotes, so the board and the grid can never print two
		-- different numbers for one pet: tier, rarity, key, the player's own state, and the enchant.
		local bonus = GameConfig.GetPetBonus(pet.tier, info.rarity, pet.key, data, pet.enchant)
		local damageText = ("+%d%%"):format(math.floor((bonus.damageMult - 1) * 100 + 0.5))

		current = {
			pet = pet,
			equipped = isEquipped,
			name = info.name,
			rarityName = rarity.name,
			rarityColor = rarity.color,
		}

		nameLabel.Text = info.name
		sub.Text = colorTag(rarity.name, UIKit.shade(rarity.color, -0.35)) .. "  \u{00B7}  " .. pet.tier
		statLabel.Text = ("\u{1F5E1}\u{FE0F} Damage  %s"):format(damageText)

		-- ===== THE CHIP SAYS "normal" WHEN THERE IS NOTHING TO SAY =====
		--
		-- The reference prints `normal` under an unenchanted pet rather than leaving the line blank,
		-- and it is right to: a blank line reads as a value that failed to load, where the word says
		-- the pet is fine and simply has not been enchanted. The old card had no equivalent -- it
		-- turned the whole row into the offer instead -- and the offer is the button below now.
		local enchantDef = GameConfig.GetEnchantDef(pet.enchant)
		if enchantDef then
			enchantChip.Text = ("\u{2728} %s"):format(enchantDef.name)
			styleCard(enchantChip, enchantDef.color, UDim.new(0, 9), 2)
			-- INK BY LUMINANCE, AND THE STROKE WITH IT. Every rung on this ladder is a saturated
			-- LIGHT fill by design, so the threshold is 0.40 rather than the usual 0.62 -- the two
			-- mid rungs land at 0.611 and took white ink on a fill bright enough to swallow it. And
			-- `themeLabel` outlines every label in near-black, which on the dark-ink branch draws the
			-- glyph inside an outline of its own colour: a fat blob with a lighter core. The light
			-- fill already separates dark ink, so that branch drops the halo.
			local c = enchantDef.color
			local lum = 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
			local dark = lum > 0.40
			themeLabel(enchantChip, 15, dark and Color3.fromRGB(58, 46, 24) or Color3.fromRGB(255, 255, 255))
			if dark then flatText(enchantChip) end
		else
			enchantChip.Text = "no enchant"
			styleCard(enchantChip, Color3.fromRGB(236, 238, 246), UDim.new(0, 9), 2)
			flatText(themeLabel(enchantChip, 15, UITheme.Color.InkSoft))
		end

		equipBtn.Text = isEquipped and "UNEQUIP" or "EQUIP"
		styleButton(equipBtn, isEquipped and UITheme.Color.Orange or UITheme.Color.Green,
			UDim.new(0, 10), 3)
		themeLabel(equipBtn, 20)

		-- The price is `GetEnchantCost`, the same pure function the server charges with, so the
		-- button cannot quote a number the transaction disagrees with.
		local cost = GameConfig.GetEnchantCost(pet)
		local canAfford = (data.Diamonds or 0) >= cost
		enchantBtn.Text = ("\u{2728} ENCHANT  %d \u{1F48E}"):format(cost)
		-- Grey when it cannot be paid for rather than hidden or silently refused: the price IS the
		-- information, and a player two diamonds short should be able to see that.
		styleButton(enchantBtn, canAfford and UITheme.Color.Purple or Color3.fromRGB(176, 180, 192),
			UDim.new(0, 10), 3)
		themeLabel(enchantBtn, 17)

		-- ===== TRANSFER IS ABSENT ON A PET WITH NOTHING TO MOVE =====
		-- Same rule as RELEASE below, and for the same reason: the server refuses a transfer whose
		-- source has no enchant, so drawing the button on a bare pet would be the UI promising
		-- something the transaction then refuses. The chip directly above already says "no enchant".
		local transferCost = GameConfig.EnchantTransferCost
		transferBtn.Visible = pet.enchant ~= nil
		transferBtn.Text = ("\u{27A1}\u{FE0F} TRANSFER  %d \u{1F48E}"):format(transferCost)
		-- Greyed when it cannot be paid for rather than hidden, exactly like ENCHANT above: the
		-- price is the information.
		styleButton(transferBtn, ((data.Diamonds or 0) >= transferCost)
			and UITheme.Color.Blue or Color3.fromRGB(176, 180, 192), UDim.new(0, 10), 3)
		themeLabel(transferBtn, 16)

		-- ===== RELEASE IS ABSENT ON A WORN PET, NOT DISABLED =====
		-- The server refuses to release an equipped pet, so a button that is drawn and then refused
		-- would teach the player the UI is lying to them. Unequipping is one click directly above.
		releaseBtn.Visible = not isEquipped
		releaseBtn.Text = "\u{2715}  RELEASE"
		styleButton(releaseBtn, UITheme.Color.Red, UDim.new(0, 10), 3)
		themeLabel(releaseBtn, 16)

		empty.Visible = false
		body.Visible = true
	end

	--- The id the board is currently aimed at, so a refresh can re-show the same pet off fresh data
	--- (or drop the board when that pet has left the save).
	function api.CurrentId()
		return current and current.pet.id or nil
	end

	api.Clear()
	return api
end

return PetDetail
