-- SwordSlot -- the blade you are carrying, on the bottom edge, where the DNA packs used to be.
--
-- ===== WHERE IT COMES FROM =====
--
-- Her call, playing 32.7 with the sword already on her body: *"mac mi treba fizicki, napravi da je
-- equipan ovde umesto ova 3 buttona, to cemo skloniti ne trebaju mi"* -- put the equipped sword
-- here instead of those three buttons, which she does not want. The three buttons were
-- `HUD/QuickBuyRow`, the strip of Robux DNA packs added on 2026-08-21 off a reference capture.
--
-- WHAT REMOVING THEM COSTS, STATED RATHER THAN LEFT TO BE FOUND: those three were a shortcut to
-- `DNA_1`, `DNA_3` and `DNA_5` -- three real developer products with real ids. Nothing about the
-- store changes: `HUD/ProductTiles` still renders **all five** inside the Robux panel, and the
-- Robux tile in the right-hand cluster still opens it. What is gone is the always-on-screen path to
-- three of them, which is a real cut in conversion and is her decision to make. `QuickBuyRow.lua`
-- is left on disk and simply not required any more -- see the note at MainUI's require site.
--
-- ===== WHY A SLOT AND NOT A FOURTH TILE =====
--
-- Every other door in this HUD is a tile in one of the two columns, and the sword already HAS one
-- (left column, order 5, built by `HUD/SwordPanel`). This is not a second door -- it is the
-- equipped item, drawn the way a hotbar draws one: what is in your hand, what it is worth, and one
-- click to change it. That is why it takes the band right under the evolve card rather than a slot
-- in a column: it is a readout first and a button second.
--
-- IT INHERITS THE ROW'S GEOMETRY EXACTLY -- 470 x 62 pinned at (0.5, 0, 1, -10), with the same
-- `UIScale` narrow-viewport rule -- so nothing else on the screen moves. `evolveFrame` is still at
-- 1,-84 and `HUD/LevelBar` is still six pixels above that at 1,-226.

local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))

local Remotes = RS.Remotes

local formatNumber, themeLabel, styleCard = UIKit.formatNumber, UIKit.themeLabel, UIKit.styleCard

local ROW_W, ROW_H = 470, 62

return function(hud)
	local screenGui = hud.screenGui

	local slot = Instance.new("TextButton")
	slot.Name = "SwordSlot"
	slot.Size = UDim2.new(0, ROW_W, 0, ROW_H)
	slot.Position = UDim2.new(0.5, 0, 1, -10)
	slot.AnchorPoint = Vector2.new(0.5, 1)
	slot.Text = ""
	slot.AutoButtonColor = false
	slot.ZIndex = UITheme.Z.Content
	slot.Parent = screenGui
	-- Repainted per blade below. Built in the rusty tier's own colour rather than a neutral, so the
	-- first frame is already correct for a save that has never bought a rung.
	local slotStroke = styleCard(slot, GameConfig.Swords[1].color, UDim.new(0, 16), 4)

	-- THE BLADE ITSELF, as a chip on the left. A square plate rather than a bare glyph, because the
	-- slot is repainted the blade's own colour and an emoji sitting directly on Neon green at tier 7
	-- has nothing behind it to read against.
	local chip = Instance.new("Frame")
	chip.Name = "Chip"
	chip.Size = UDim2.new(0, 46, 0, 46)
	chip.Position = UDim2.new(0, 8, 0.5, 0)
	chip.AnchorPoint = Vector2.new(0, 0.5)
	chip.ZIndex = slot.ZIndex + UITheme.Z.Badge
	chip.Parent = slot
	styleCard(chip, UITheme.Color.Frost, UDim.new(0, 12), 3)

	local glyph = Instance.new("TextLabel")
	glyph.Name = "Glyph"
	glyph.Size = UDim2.new(1, -8, 1, -8)
	glyph.Position = UDim2.new(0.5, 0, 0.5, 0)
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.BackgroundTransparency = 1
	glyph.Text = "\u{2694}\u{FE0F}"
	glyph.ZIndex = chip.ZIndex + UITheme.Z.Content
	glyph.Parent = chip
	themeLabel(glyph, 30)

	-- The name, and under it the one number the ladder is about. Two lines rather than one long
	-- string: "3. Bronze Fang -- x1.45 damage -- 160 for the next" is 46 characters in a 300 px box
	-- and `themeLabel` floors text at 14 px, so it would be cut rather than shrunk.
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, -190, 0, 26)
	nameLabel.Position = UDim2.new(0, 62, 0, 6)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = "Sword"
	nameLabel.ZIndex = slot.ZIndex + UITheme.Z.Content
	nameLabel.Parent = slot
	themeLabel(nameLabel, 22)

	local underLabel = Instance.new("TextLabel")
	underLabel.Name = "UnderLabel"
	underLabel.Size = UDim2.new(1, -190, 0, 22)
	underLabel.Position = UDim2.new(0, 62, 1, -28)
	underLabel.BackgroundTransparency = 1
	underLabel.TextXAlignment = Enum.TextXAlignment.Left
	underLabel.Text = ""
	underLabel.ZIndex = slot.ZIndex + UITheme.Z.Content
	underLabel.Parent = slot
	themeLabel(underLabel, 16, UITheme.Color.Cream)

	-- THE PRICE OF THE NEXT RUNG RIDES THE RIGHT-HAND END, and it is the whole reason this is a
	-- button and not a label: *"da je poenta po redu da ides jer ti daju boost"*. The slot says what
	-- you are holding; the chip says what the next one costs; the click opens the ladder.
	local nextChip = Instance.new("TextLabel")
	nextChip.Name = "NextChip"
	nextChip.Size = UDim2.new(0, 120, 0, 34)
	nextChip.Position = UDim2.new(1, -10, 0.5, 0)
	nextChip.AnchorPoint = Vector2.new(1, 0.5)
	nextChip.Text = ""
	nextChip.ZIndex = slot.ZIndex + UITheme.Z.Badge
	nextChip.Parent = slot
	local nextStroke = styleCard(nextChip, UITheme.Color.Locked, UDim.new(1, 0), 3)
	themeLabel(nextChip, 18)

	local function refresh()
		local data = hud.getData()
		if not data then return end

		local level = GameConfig.GetSwordLevel(data)
		local tier = GameConfig.GetSwordTier(data)
		local cost = GameConfig.GetSwordCost(level)
		local diamonds = data.Diamonds or 0

		glyph.Text = tier and tier.emoji or "\u{2694}\u{FE0F}"
		nameLabel.Text = ("%d. %s"):format(level, tier and tier.displayName or "Sword")
		underLabel.Text = ("EQUIPPED  \u{2022}  \u{2694}\u{FE0F} x%.2f damage")
			:format(tier and tier.damageMult or 1)
		UIKit.setButtonColor(slot, tier and tier.color or UITheme.Color.Locked)

		if cost == math.huge then
			-- THE LAST BLADE IS A STATE, NOT A MISSING PRICE. A blank chip on a maxed ladder reads
			-- as the readout having broken.
			nextChip.Text = "MAX"
			UIKit.setButtonColor(nextChip, UITheme.Color.Gold)
			nextStroke.Color = UIKit.OUTLINE_COLOR
			slotStroke.Color = UIKit.READY_RIM
			return
		end

		local affordable = diamonds >= cost
		nextChip.Text = "\u{1F48E} " .. formatNumber(cost)
		-- Green when it can be bought right now, grey when it cannot. Grey and not red, the rule the
		-- whole kit follows: "not yet" is not an error, and a red chip on a fresh save reads as
		-- something being broken.
		UIKit.setButtonColor(nextChip, affordable and UITheme.Color.Green or UITheme.Color.Locked)
		nextStroke.Color = affordable and UIKit.READY_RIM or UIKit.OUTLINE_COLOR
		slotStroke.Color = UIKit.OUTLINE_COLOR
	end

	-- ONE CLICK, AND IT OPENS THE LADDER RATHER THAN BUYING. Buying straight off the slot would be
	-- a 10,240-Diamond purchase behind a control the player's thumb rests on -- the panel is where
	-- the price, the boost and the rung above it are all readable before the press.
	slot.MouseButton1Click:Connect(function()
		if hud.showSwordPanel then hud.showSwordPanel() end
	end)

	Remotes.DataUpdate.OnClientEvent:Connect(refresh)
	refresh()

	-- The narrow-viewport rule, copied from the row this replaces because it occupies the identical
	-- band: the tile columns hug both edges and collide with a centred 470 below about 890 px. The
	-- container is scaled rather than the parts resized, so the chips keep their proportions.
	local scale = Instance.new("UIScale")
	scale.Name = "FitScale"
	scale.Parent = slot

	local cam = workspace.CurrentCamera
	local function fit()
		if not cam then return end
		-- 210 a side for the tile columns (20 margin + two 82 tiles + a 26 gap), 12 of daylight.
		local free = cam.ViewportSize.X - (210 + 12) * 2
		scale.Scale = math.clamp(free / ROW_W, 0.62, 1)
	end
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
		fit()
	end
end
