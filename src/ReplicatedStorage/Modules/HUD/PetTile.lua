-- PetTile -- one pet in the bag grid: a coloured disc with the real rig standing on it, a tick if
-- it is worn, and the damage share underneath.
--
-- ===== WHY THE CARD BECAME A TILE (2026-08-23, Kristina's reference capture) =====
--
-- Her words with the screenshot: *"ovo ovde treba ubaciti kao novi dizajn za pet panel, samo umesto
-- ovih emojia da budu petovi tu kao sto su i sad, ali ovo okolo raspored panela to prisvajamo"* --
-- adopt the arrangement, keep our pets. The reference lays a bag out as a dense grid of small round
-- tiles with one number under each, and puts everything else about the selected pet on a separate
-- board beside the grid.
--
-- The old cell was 232 x 156 and carried the pet's name, its rarity word, its tier, a damage bar, an
-- enchant chip, an enchant price button and a release x -- seven pieces of information per pet, in a
-- panel that can hold a hundred of them. Three fitted across and six on screen. **Everything that
-- came off the tile is on `PetDetail` now**, which is the half of her layout that makes the dense
-- half possible: a tile can afford to say one thing because the board beside it says the rest.
--
-- ===== THE ONE PLACE THIS DELIBERATELY DOES NOT COPY THE REFERENCE =====
--
-- Hers prints `x100`, `x25`, `x11.04`. Ours prints `+98%` and that is not a style choice: a pet's
-- contribution is a SHARE of the player's own damage, summed across the equipped slots, so the
-- percentage is literally what the damage chain adds -- three pets at +80% really do come to +240%.
-- `x` is the old multiplicative reading this game moved away from, and printing it here would put a
-- number on the tile that no formula in the game uses. The reference's placement is copied; its
-- arithmetic is not.
--
-- ===== AND THE TILE IS 92 PX BECAUSE OUR ART IS A RIG, NOT A GLYPH =====
--
-- The reference fits seven across because its pets are emoji, which are legible at any size. Ours
-- is the same `PetModel.Build` that walks around the world -- roughly thirty parts -- and below
-- about 80 px it stops being a species and becomes a coloured blob, which would throw away the one
-- thing her instruction was explicit about. Five across at 92 is the honest translation: fifteen
-- pets on screen where the old card managed six.

local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))
-- `PetModel` is no longer required here: the rig is built by `PetPreview`, which is the only
-- caller now. The comment above still names it because it is still what draws a pet.
local PetPreview = require(script.Parent:WaitForChild("PetPreview"))

local themeLabel, styleCard, styleButton = UIKit.themeLabel, UIKit.styleCard, UIKit.styleButton
local setButtonColor = UIKit.setButtonColor

local PetTile = {}

PetTile.CELL_W = 92
PetTile.CELL_H = 118
PetTile.PAD = 10

--- Builds one tile into `parent`.
---
--- `opts` carries everything the tile cannot work out for itself:
---   pet, info, rarity, isEquipped, damageText, order, selecting, selected, shown
---   onPrimary(pet)  -- the click: opens this pet on the detail board (or ticks it, in select mode)
---
--- `selected` and `shown` are two different things -- see the note over `SelectionPlate`.
---
--- Returns the tile and a `setTicked(bool)` that repaints the select box WITHOUT a grid rebuild --
--- the same reason the old card carried one: a rebuild is ~30 parts per pet and ticking a checkbox
--- must not cost a hundred rigs.
function PetTile.Build(parent, opts)
	local pet, info, rarity = opts.pet, opts.info, opts.rarity
	local isEquipped = opts.isEquipped

	local tile = Instance.new("TextButton")
	tile.Name = "PetTile"
	tile.LayoutOrder = opts.order or 1
	tile.Text = ""
	tile.AutoButtonColor = false
	tile.BackgroundTransparency = 1
	tile.Size = UDim2.new(0, PetTile.CELL_W, 0, PetTile.CELL_H)
	tile.ZIndex = parent.ZIndex + UITheme.Z.Content
	tile.Parent = parent

	-- ===== "THE ONE THE BOARD IS SHOWING" IS A PLATE, NOT A BADGE (2026-08-23) =====
	--
	-- Kristina photographed the action row's ☑ toggle and said these already have a selector -- and
	-- she is right: the bag now has TWO different senses of "selected" and they must not be drawn the
	-- same way. Select mode's corner checkbox means *this pet is in the batch I am about to release*;
	-- the new one means *this is the pet the board is describing*. A second tick in a second corner
	-- would make them one thing at a glance.
	--
	-- So this one is a PLATE BEHIND THE WHOLE TILE rather than a mark on it. It cannot be mistaken
	-- for the checkbox (different shape, different place, no glyph), it cannot be mistaken for the
	-- equipped tick, and it does not compete with the rarity rim -- which is already spoken for,
	-- carrying equipped/not. A highlighted row is also what every list in this game already means by
	-- "the one you are looking at".
	local plate = Instance.new("Frame")
	plate.Name = "SelectionPlate"
	plate.Size = UDim2.new(1, 8, 1, 4)
	plate.Position = UDim2.new(0.5, 0, 0, -4)
	plate.AnchorPoint = Vector2.new(0.5, 0)
	-- BELOW the tile's own contents. `Z.Shell` is the kit's bottom rung, so the disc, the rig, the
	-- tick and the number all keep drawing over it.
	plate.ZIndex = tile.ZIndex - 1
	plate.Visible = opts.shown == true
	plate.Parent = tile
	styleCard(plate, UITheme.Color.Aqua, UDim.new(0, 16), 3)

	-- ===== THE DISC CARRIES THE RARITY, BOLDLY =====
	--
	-- The old card tinted itself `Frost:Lerp(rarity.color, 0.18)` -- nearly white -- and had to,
	-- because it printed three dark captions on its own face and the kit flips ink to white above
	-- `LIGHT_SURFACE`. **This disc prints nothing on itself.** The damage figure is below it on the
	-- panel's white sheet, so the luminance argument that pinned 0.18 does not apply here and the
	-- tile can be as saturated as the reference's are.
	--
	-- 0.22 toward white rather than the raw rarity colour: our rigs are themselves brightly
	-- coloured, and a Legendary rig on a full-strength Legendary disc is one colour twice.
	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.Size = UDim2.new(0, 88, 0, 88)
	disc.Position = UDim2.new(0.5, 0, 0, 0)
	disc.AnchorPoint = Vector2.new(0.5, 0)
	disc.ZIndex = tile.ZIndex
	disc.Parent = tile
	-- A full-radius corner is what makes it the reference's circle. The rim goes green when the pet
	-- is worn -- the same signal the old card's outline carried, kept because it survives at tile
	-- size where a word would not.
	styleCard(disc, rarity.color:Lerp(Color3.fromRGB(255, 255, 255), 0.22), UDim.new(1, 0), 3).Color =
		isEquipped and Color3.fromRGB(62, 196, 86) or UIKit.OUTLINE_COLOR

	-- ===== THE RIG, WHICH IS THE WHOLE POINT OF THE ROW =====
	--
	-- Moved out to `HUD/PetPreview` (34.28) so the transfer picker can draw the same pets rather
	-- than a list of names. What lived here was the viewport, the rig build and a camera solved to
	-- fit it -- four captures' worth of reasoning that must not exist in two copies. The options
	-- below are the tile's own: parented to the TILE and not to the disc so a full-radius corner
	-- cannot clip a tail or an ear, and padded 1.25 because a disc has no corners to put a wing in.
	local preview, rigRoot, rigPieces = PetPreview.Attach(tile, pet, {
		size = 84,
		position = UDim2.new(0.5, 0, 0, 2),
		anchorPoint = Vector2.new(0.5, 0),
		zIndex = disc.ZIndex + UITheme.Z.Content,
		padding = 1.25,
	})

	local rigEntry
	if rigRoot then
		rigEntry = { root = rigRoot, pieces = rigPieces, phase = (opts.order or 1) * 0.7 }
	end

	-- ===== THE TWO CORNERS, AND WHY THEY ARE NOT THE SAME CORNER =====
	--
	-- The old card put the release x AND the select checkbox in its top-right and had to make them
	-- exclusive, because two small controls in one corner -- one of which deletes immediately -- is
	-- the worst possible pairing. **The reference has no per-tile x at all**: releasing is the bin
	-- in the action row and, now, a button on the detail board. That frees the corners, so the tick
	-- and the checkbox each get their own and neither has to hide the other.
	if isEquipped then
		local tick = Instance.new("TextLabel")
		tick.Name = "EquippedTick"
		tick.Size = UDim2.new(0, 30, 0, 30)
		tick.Position = UDim2.new(0, -2, 0, -4)
		tick.BackgroundTransparency = 1
		tick.ZIndex = preview.ZIndex + 2
		tick.Text = "\u{2714}"
		tick.Parent = tile
		themeLabel(tick, 30, Color3.fromRGB(62, 196, 86))
	end

	local setTicked
	if opts.selecting and not isEquipped then
		-- A LABEL, NOT A BUTTON -- the whole tile is the hit area in select mode, and a clickable box
		-- inside it would swallow clicks aimed at the pet, which is the biggest part of the target.
		local box = Instance.new("TextLabel")
		box.Name = "SelectBox"
		box.Size = UDim2.new(0, 26, 0, 26)
		box.Position = UDim2.new(1, 2, 0, -4)
		box.AnchorPoint = Vector2.new(1, 0)
		box.Text = opts.selected and "\u{2714}" or ""
		box.ZIndex = preview.ZIndex + 2
		box.Parent = tile
		styleCard(box, opts.selected and UITheme.Color.Green or Color3.fromRGB(236, 238, 246),
			UDim.new(0, 8), 3)
		themeLabel(box, 18)
		setTicked = function(on)
			box.Text = on and "\u{2714}" or ""
			setButtonColor(box, on and UITheme.Color.Green or Color3.fromRGB(236, 238, 246))
		end
	end

	-- ===== SECRET (12.12), MOVED OFF THE FREE CORNER IT NO LONGER HAS =====
	--
	-- A Secret is a 1-in-50,000 hatch and the first thing a player does with one is show it to
	-- somebody, so it keeps its loud badge. On the old card it lived in the art's top-left; here
	-- that is the equipped tick's corner. It goes across the FOOT of the disc instead, which is the
	-- one edge nothing else uses and is still the widest run of pixels on the tile.
	-- ===== AND `AWAY`, WHICH IS WHY "EQUIP BEST" LOOKED BROKEN (33.26) =====
	--
	-- Her report: *"ne equipa best pets ovde"*, with a capture of the grid -- the third-strongest pet
	-- (+118%) had no tick on it after pressing the button. Measured live on that same save through
	-- the real modules: `HandleEquipBest` chose the top 8 by `SortedPetsByPower` and every one of
	-- them was ALREADY equipped, so the call was correct and changed nothing. **THREE OF HER
	-- HUNDRED PETS WERE AWAY ON AN ADVENTURE**, and 30.5 filters those out BEFORE the ranking on
	-- purpose (see the note over `PetService.HandleEquipBest`) -- a sent pet cannot be worn.
	--
	-- So the button was right and the GRID was lying: a pet that is not eligible looked exactly like
	-- a pet that had been passed over. Nothing else on the tile said otherwise, because `IsPetAway`
	-- had never been asked on the client at all -- all eleven of its callers were server-side.
	--
	-- The badge takes the same foot-of-the-disc slot as SECRET and cannot collide with it: a pet
	-- sent on an adventure is by definition owned and standing in this bag, and if it is BOTH, being
	-- told where it is beats being told how rare it is -- so this one wins the slot and SECRET is
	-- skipped for as long as it is out.
	if opts.away then
		local badge = Instance.new("TextLabel")
		badge.Name = "AwayBadge"
		-- ===== 20 TALL, NOT 18, AND THE TEXT IS NOT WHAT IS WRONG (33.36) =====
		--
		-- `themeLabel(badge, 13, ...)` lands in `UITheme.AutoSize(label, math.min(14, 13), 13)`, so
		-- this caption's `UITextSizeConstraint` FLOORS it at 13 px -- it is `TextScaled` and it is
		-- already as small as it is allowed to get. `styleCard` then mirrors the caption into a
		-- `Label` child inset by 3 px top and bottom, so an 18-tall badge gives that child a **12 px
		-- box for 13 px of text** and `TextFits` is false with the cap-height shaved off.
		--
		-- Measured, not guessed: box 52x12, `TextBounds` 44x13. The fix is the BOX, because the text
		-- has nowhere left to shrink to. 20 gives the child 14 and a pixel of slack.
		--
		-- AND IT MOVES UP BY THE 2 IT GAINS. `ValueLabel` starts at y 92 and this badge ended at 90;
		-- growing downward would have put a rarity chip through the damage number on every secret
		-- pet in the bag. 70..90 keeps the gap exactly where it was.
		badge.Size = UDim2.new(0, 62, 0, 20)
		badge.Position = UDim2.new(0.5, 0, 0, 70)
		badge.AnchorPoint = Vector2.new(0.5, 0)
		badge.ZIndex = preview.ZIndex + 3
		badge.Text = "AWAY"
		badge.Parent = tile
		styleCard(badge, UITheme.Color.SkyBlue, UDim.new(0, 6), 2)
		themeLabel(badge, 13, Color3.fromRGB(255, 255, 255))
		-- Faded as well as labelled, the rule the whole kit follows for "not available": a word is
		-- read second and a tone is read first, and this grid is skimmed rather than read.
		preview.ImageTransparency = 0.55
	elseif info.secret then
		local badge = Instance.new("TextLabel")
		badge.Name = "SecretBadge"
		-- Same 20/70 as `AwayBadge` above and for the same measured reason -- these two share the
		-- foot-of-the-disc slot and must stay the same size, or the tile changes shape depending on
		-- which of them is showing. SECRET is the one the sweep actually caught; AWAY has the
		-- identical defect and was simply not on screen, because it needs a pet out on an adventure.
		badge.Size = UDim2.new(0, 62, 0, 20)
		badge.Position = UDim2.new(0.5, 0, 0, 70)
		badge.AnchorPoint = Vector2.new(0.5, 0)
		badge.ZIndex = preview.ZIndex + 3
		badge.Text = "SECRET"
		badge.Parent = tile
		styleCard(badge, rarity.color, UDim.new(0, 6), 2)
		themeLabel(badge, 13, Color3.fromRGB(255, 255, 255))
	end

	-- The one number, under the disc, on the panel's own sheet -- the reference's `x100` slot.
	local value = Instance.new("TextLabel")
	value.Name = "ValueLabel"
	value.Size = UDim2.new(1, 0, 0, 24)
	value.Position = UDim2.new(0, 0, 0, 92)
	value.BackgroundTransparency = 1
	value.ZIndex = tile.ZIndex + UITheme.Z.Content
	value.Text = opts.damageText
	value.Parent = tile
	themeLabel(value, 20, Color3.fromRGB(62, 196, 86))

	tile.MouseButton1Click:Connect(function()
		if opts.onPrimary then opts.onPrimary(pet) end
	end)

	-- Handed back for the same reason `setTicked` is: moving the highlight from one tile to another
	-- must cost two property writes, not a rebuild of every rig in the bag.
	local function setShown(on)
		plate.Visible = on == true
	end

	return tile, setTicked, rigEntry, setShown
end

return PetTile
