-- PetsActions -- the Pets panel's bulk action row: equip best, release duplicates, and the way out to Fusion.
--
-- MOVED OUT OF `MainUI` (18.9), byte for byte. It was already a closed
-- `;(function() ... end)()` block -- the shape this file's 200-register ceiling forces
-- every panel into -- so the extraction is a change of wrapper, not of code. See
-- `docs/SPLIT.md` for the `hud` contract and `docs/CODEMAP.md` for where the rest went.

local RS = game:GetService("ReplicatedStorage")

local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))

local Remotes = RS.Remotes

local themeLabel, styleCard, styleButton, setButtonColor = UIKit.themeLabel, UIKit.styleCard, UIKit.styleButton, UIKit.setButtonColor

return function(hud)
	local petsPanel, shopFrame, toggleOnly = hud.petsPanel, hud.shopFrame, hud.toggleOnly

	-- THE BAR SITS ON THE BOTTOM EDGE OF THE BOARD, half in and half out, the way the reference
	-- does it: two wide buttons, then the two counters.
	local actionRow = Instance.new("Frame")
	actionRow.Name = "PetsActionRow"
	actionRow.Size = UDim2.new(1, -28, 0, 52)
	actionRow.Position = UDim2.new(0.5, 0, 1, -26)
	actionRow.AnchorPoint = Vector2.new(0.5, 0.5)
	actionRow.BackgroundTransparency = 1
	actionRow.ZIndex = petsPanel.ZIndex + UITheme.Z.Badge
	actionRow.Parent = petsPanel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = actionRow

	local function actionButton(order, text, color, width)
		local btn = Instance.new("TextButton")
		btn.Name = "Action" .. order
		btn.Size = UDim2.new(0, width or 178, 0, 46)
		btn.LayoutOrder = order
		btn.Text = text
		btn.ZIndex = actionRow.ZIndex
		btn.Parent = actionRow
		styleButton(btn, color, UDim.new(1, 0))
		return btn
	end

	-- 146 -> 178, i.e. back to what they were authored at. The squeeze to 146 existed to fit the two
	-- counter capsules into this row; they live in the header pill above the board now (see
	-- `counterCapsule` below), so the row is three controls wide instead of five:
	-- 178 + 178 + 46 + 2 gaps of 10 = 422, inside the row's 744, with room to spare.
	local equipBestButton = actionButton(1, "Equip Best Pets", UITheme.Color.Green, 178)
	local unequipAllButton = actionButton(2, "Unequip All Pets", UITheme.Color.Red, 178)

	-- ===== SELECT MODE (11.17) =====
	--
	-- The server has taken a LIST since 10.3; this is the client half that was never built, and
	-- releasing a hundred pets one confirm at a time is the reason the cap reads as a chore.
	--
	-- THE ROW SWAPS, IT DOES NOT GROW. While selecting, the two action buttons are hidden and one
	-- wide red button stands in their place at exactly their combined width (178 + 10 + 178 = 366),
	-- so nothing in the row moves by a pixel when the mode changes -- a bar that reflows on a toggle
	-- makes the player re-find every control. The counters stay visible throughout: "how many do I
	-- own" is the question that got them here.
	--
	-- The selection lives on `hud`, not in a local, because `refreshPetsPanel` DESTROYS AND
	-- REBUILDS EVERY CELL ON EVERY DataUpdate -- roughly every three seconds, and on every kill.
	-- State held on the cards would be wiped mid-selection by an unrelated creature dying. The set is
	-- keyed by pet id and the rebuild reads it, so the ticks come back exactly where they were.
	local selectToggle = actionButton(3, "\u{2611}", UITheme.Color.Blue, 46)
	local releaseButton = actionButton(0, "RELEASE", UITheme.Color.Red, 366)
	releaseButton.Visible = false

	hud.petSelect = { on = false, ids = {}, n = 0 }
	-- `sel.n` is also decremented by refreshPetsPanel when a selected pet stops existing, and that
	-- function is 200 lines below and cannot name anything in here -- so the repaint is handed over.

	-- One place that redraws the bar, called by every path that can change either the mode or the
	-- count -- so "the button says 3 and the grid shows 4 ticks" cannot happen.
	local function paintSelectBar()
		local sel = hud.petSelect
		equipBestButton.Visible = not sel.on
		unequipAllButton.Visible = not sel.on
		releaseButton.Visible = sel.on
		-- plain `.Text`, the way every other call site in this file writes a button: styleButton
		-- subscribes a proxy label to it, so the visible text follows
		releaseButton.Text = sel.n > 0 and ("RELEASE %d"):format(sel.n) or "SELECT PETS TO RELEASE"
		setButtonColor(releaseButton, sel.n > 0 and UITheme.Color.Red or UITheme.Color.Locked)
		setButtonColor(selectToggle, sel.on and UITheme.Color.Green or UITheme.Color.Blue)
	end
	hud.petSelectRepaint = paintSelectBar

	-- Leaving select mode always clears the set. A selection that survived the toggle would be
	-- invisible -- no ticks are drawn outside the mode -- and the next RELEASE press would act on
	-- pets the player picked minutes ago and cannot see.
	hud.petSelectExit = function()
		local sel = hud.petSelect
		sel.on, sel.ids, sel.n = false, {}, 0
		paintSelectBar()
		if hud.refreshPetsPanel then hud.refreshPetsPanel() end
	end

	hud.petSelectToggleId = function(petId)
		local sel = hud.petSelect
		if sel.ids[petId] then
			sel.ids[petId] = nil
			sel.n -= 1
		else
			sel.ids[petId] = true
			sel.n += 1
		end
		paintSelectBar()
	end

	selectToggle.MouseButton1Click:Connect(function()
		local sel = hud.petSelect
		if sel.on then
			hud.petSelectExit()
		else
			sel.on, sel.ids, sel.n = true, {}, 0
			paintSelectBar()
			if hud.refreshPetsPanel then hud.refreshPetsPanel() end
		end
	end)

	releaseButton.MouseButton1Click:Connect(function()
		local sel = hud.petSelect
		if sel.n <= 0 then return end
		local list = {}
		for id in pairs(sel.ids) do table.insert(list, id) end
		if hud.confirmReleaseMany then hud.confirmReleaseMany(list) end
	end)

	paintSelectBar()

	-- ===== THE COUNTERS CAME OFF THE BOTTOM BAR (2026-08-21) =====
	--
	-- Kristina's reference capture of a pet screen puts them in ONE capsule floating above the top
	-- edge, beside the panel's name, and the bottom edge holds nothing but the actions. That split is
	-- worth copying because it is a split by KIND: the bar is things you press that change your
	-- collection, the pill is two facts about it. Mixed into one row, "Unequip All Pets" and "3/3"
	-- read as four buttons of which two do nothing when pressed -- and the [+] discs, which ARE
	-- pressable, were the least prominent thing in a row of five wide controls.
	--
	-- IT CLEARS THE CLOSE DISC BY CONSTRUCTION. The X is centred ON the top-right corner now and is
	-- 52 across, so it owns x 742..794 of a 772-wide board. The pill is right-anchored 60 in from the
	-- edge, which puts its right edge at 712 -- 30 px of daylight before the disc's left flank.
	local headerPill = Instance.new("Frame")
	headerPill.Name = "PetsHeaderPill"
	headerPill.Size = UDim2.new(0, 274, 0, 46)
	headerPill.Position = UDim2.new(1, -60, 0, -6)
	headerPill.AnchorPoint = Vector2.new(1, 1)
	headerPill.BackgroundTransparency = 1
	headerPill.ZIndex = petsPanel.ZIndex + UITheme.Z.Badge
	headerPill.Parent = petsPanel

	local pillLayout = Instance.new("UIListLayout")
	pillLayout.FillDirection = Enum.FillDirection.Horizontal
	pillLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	pillLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	pillLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pillLayout.Padding = UDim.new(0, 10)
	pillLayout.Parent = headerPill

	-- The two blue counter capsules. The reference puts a green [+] on each of them -- an upsell for
	-- more slots -- and ours is not decoration: the equipped cap really is buyable, it is the PetSlot
	-- Diamond upgrade in the Shop, so the [+] opens that. See GameConfig.GetMaxEquippedPets.
	-- 150 -> 132: two of them plus a 10 gap is 274, which is the pill's width above.
	local function counterCapsule(order, emoji, onPlus)
		local capsule = Instance.new("Frame")
		capsule.Name = "Counter" .. order
		capsule.Size = UDim2.new(0, 132, 0, 46)
		capsule.LayoutOrder = order
		capsule.ZIndex = headerPill.ZIndex
		capsule.Parent = headerPill
		styleCard(capsule, UITheme.Color.Blue, UDim.new(1, 0), 4)

		local plus = Instance.new("TextButton")
		plus.Name = "Plus"
		plus.Size = UDim2.new(0, 34, 0, 34)
		plus.Position = UDim2.new(0, 7, 0.5, 0)
		plus.AnchorPoint = Vector2.new(0, 0.5)
		plus.Text = "+"
		plus.ZIndex = capsule.ZIndex + UITheme.Z.Content
		plus.Parent = capsule
		styleButton(plus, UITheme.Color.Green, UDim.new(0, 10), 3)
		plus.MouseButton1Click:Connect(onPlus)

		local count = Instance.new("TextLabel")
		count.Name = "Count"
		-- 62 -> 48 and the icon slot came in 8 px with the capsule: 7 + 34 (plus) + 5 + 48 (count)
		-- + 4 + 26 (icon) + 8 = 132. `themeLabel` auto-shrinks, so "12/50" still fits at the floor.
		count.Size = UDim2.new(0, 48, 0, 34)
		count.Position = UDim2.new(0, 46, 0.5, 0)
		count.AnchorPoint = Vector2.new(0, 0.5)
		count.BackgroundTransparency = 1
		count.ZIndex = capsule.ZIndex + UITheme.Z.Content
		count.Text = "0"
		count.Parent = capsule
		themeLabel(count, 24)

		UITheme.IconSlot(capsule, {
			name = "Icon", icon = emoji, maxTextSize = 26,
			size = UDim2.new(0, 26, 0, 26), position = UDim2.new(1, -8, 0.5, 0),
			anchorPoint = Vector2.new(1, 0.5), zIndex = capsule.ZIndex + UITheme.Z.Content,
		})

		return count
	end

	-- read back by refreshPetsPanel, which is the only thing that knows the numbers
	hud.petSlotCount = counterCapsule(3, "\u{1F43E}", function()
		toggleOnly(shopFrame)
	end)
	hud.petOwnedCount = counterCapsule(4, "\u{1F392}", function()
		toggleOnly(shopFrame)
	end)

	-- These two remotes are newer than the authored Remotes folder, so they are fetched by name
	-- rather than indexed -- PetService creates whichever is missing when the server starts.
	task.spawn(function()
		local equipBest = Remotes:WaitForChild("EquipBestPets", 30)
		local unequipAll = Remotes:WaitForChild("UnequipAllPets", 30)
		if equipBest then
			equipBestButton.MouseButton1Click:Connect(function()
				equipBest:FireServer()
			end)
		end
		if unequipAll then
			unequipAllButton.MouseButton1Click:Connect(function()
				unequipAll:FireServer()
			end)
		end
	end)
end
