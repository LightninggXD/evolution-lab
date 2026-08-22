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
local PetModel = require(RS.Modules:WaitForChild("PetModel"))

local themeLabel, styleCard, styleButton = UIKit.themeLabel, UIKit.styleCard, UIKit.styleButton
local setButtonColor = UIKit.setButtonColor

local PetTile = {}

PetTile.CELL_W = 92
PetTile.CELL_H = 118
PetTile.PAD = 10

--- Builds one tile into `parent`.
---
--- `opts` carries everything the tile cannot work out for itself:
---   pet, info, rarity, isEquipped, damageText, order, selecting, selected
---   onPrimary(pet)  -- the click: equip/unequip AND select into the detail board
---   onPick(pet)     -- select mode's tick
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
	-- Same build as the world rig, no nameplate, no outline, no sparkle -- at 88 px an outline is a
	-- smear and a sparkle is noise. Parented to the TILE and not to the disc so that the disc's
	-- circular corner cannot clip a tail or an ear.
	local preview = Instance.new("ViewportFrame")
	preview.Name = "Preview"
	preview.Size = UDim2.new(0, 84, 0, 84)
	preview.Position = UDim2.new(0.5, 0, 0, 2)
	preview.AnchorPoint = Vector2.new(0.5, 0)
	preview.BackgroundTransparency = 1
	preview.BorderSizePixel = 0
	preview.Ambient = Color3.fromRGB(206, 206, 220)
	preview.LightColor = Color3.fromRGB(255, 255, 255)
	preview.LightDirection = Vector3.new(-0.4, -1, -0.55)
	preview.ZIndex = disc.ZIndex + UITheme.Z.Content
	preview.Parent = tile

	local rigEntry
	local def = GameConfig.GetPetDef(pet.key)
	if def then
		local rig, rigRoot, rigPieces = PetModel.Build(def, pet.tier, {
			scale = 1,
			nameplate = false,
			outline = false,
			sparkle = false,
		})
		PetModel.Place(rigRoot, rigPieces, CFrame.new())
		rig.Parent = preview

		-- ===== THE CAMERA IS FITTED TO THE RIG, AND A FIXED ONE CANNOT BE RIGHT =====
		--
		-- Three captures were spent moving a hard-coded camera in and out -- 40° at 6.9 studs cropped
		-- every pet through the head, 44° at 10.4 shrank them to a speck, and the card's own proven
		-- 45° at 8.3 landed somewhere in between and STILL read wrong. The fourth capture is what
		-- named the real fault: **there is no single right distance, because the hundred species are
		-- not one size.** `Absolon` is a wide flat rig and `TheFirst` is a tall one; the same camera
		-- makes one a stripe across the disc and the other a dot in the middle of it, and the old
		-- 232 px card hid that only because its viewport was big enough for both to look acceptable.
		--
		-- So the distance is SOLVED from the rig instead. `FieldOfView` is the vertical angle and the
		-- viewport is square, so the horizontal one matches it and a single solve covers both:
		--     distance = (extent / 2) / tan(fov / 2)
		--
		-- **The extent is the LARGEST axis, not the height**, because the turntable below spins this
		-- rig a full ±0.55 rad on Y -- a fit taken on the depth axis would let a long tail swing
		-- outside the frame a second after it was measured. And it is padded by 1.25 for the circle:
		-- a disc has no corners for a wing to occupy, so the subject must sit inside the inscribed
		-- circle rather than the square the maths solves for.
		--
		-- `GetExtentsSize` IS TAKEN AFTER `Place` AND AFTER PARENTING, which is not fussiness -- a
		-- bounding box read one frame too early is the exact fault [[roblox-model-facing-and-scaling]]
		-- records, and it reads as a camera that is right for some pets and wrong for others.
		local extents = rig:GetExtentsSize()
		local span = math.max(extents.X, extents.Y, extents.Z)
		local fov = 45
		local dist = (span * 0.5) / math.tan(math.rad(fov) * 0.5) * 1.25
		-- A floor, because a genuinely tiny rig would otherwise pull the camera inside itself and
		-- render the inside of its own head.
		dist = math.max(dist, 3.5)
		local centre = rig:GetPivot().Position

		local cam = Instance.new("Camera")
		cam.FieldOfView = fov
		-- Off-axis by the same proportions the card used (a touch right, a touch above), so the rig
		-- reads as three-dimensional rather than as a mugshot -- scaled to whatever distance the fit
		-- asked for rather than typed as three more magic numbers.
		cam.CFrame = CFrame.new(centre + Vector3.new(0.36, 0.32, -0.88).Unit * dist, centre)
		cam.Parent = preview
		preview.CurrentCamera = cam

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
	if info.secret then
		local badge = Instance.new("TextLabel")
		badge.Name = "SecretBadge"
		badge.Size = UDim2.new(0, 62, 0, 18)
		badge.Position = UDim2.new(0.5, 0, 0, 72)
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

	return tile, setTicked, rigEntry
end

return PetTile
