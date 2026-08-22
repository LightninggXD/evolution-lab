-- AuraCard -- one row of the Auras panel, drawn in the chunky card style Kristina photographed.
--
-- WHY THIS IS A FILE OF ITS OWN. The panel it belongs to is a shell, a list and a refresh; the card
-- is 150 lines of pure drawing that never reads a save, a remote or `hud`. Splitting on that seam
-- is the standing rule for new work (2026-08-22: a big file costs its whole length in tokens every
-- time anything in it is read) and it means the card can be re-tuned without opening the panel.
--
-- THE REFERENCE, AND WHAT IS TAKEN FROM IT. The mock-up that was sitting in `StarterGui.AurasGui`
-- was six hand-typed cards with invented names and invented prices -- a picture, not a panel. What
-- is real about it is the SHAPE, and that is what this file reproduces, measured off the mock-up
-- rather than guessed: a 96 px card painted the item's own colour, a 3.5 px near-black outline, the
-- stud sheet at 0.93, the name in white with a heavy halo at the top left, the stats under it in
-- dark ink with a WHITE halo, a round translucent glow behind the artwork in the middle, and the
-- action column pinned to the right-hand edge.
--
-- THE TWO-TONE TEXT SCHEME IS THE ONE THING HERE THAT IS NOT DECORATION. A card is painted the
-- mutation's own colour, and `GameConfig.Mutations` runs from Secret at rgb(20,20,20) to Godly at
-- rgb(255,240,150) -- near-black and near-white, four rows apart in the same column. White-on-black
-- halo for the name and black-on-white halo for the stats read on BOTH ends of that range, which is
-- why neither line branches on luminance the way the rest of the game's ink does.

local RS = game:GetService("ReplicatedStorage")

local IconLibrary = require(RS.Modules.IconLibrary)

local AuraCard = {}

-- Measured off the mock-up. `HEIGHT` is exported because the panel sizes its own board against it.
AuraCard.HEIGHT = 96

local INK = Color3.fromRGB(20, 20, 20)
local WHITE = Color3.fromRGB(255, 255, 255)
local STUDS = "rbxassetid://17601461662"

-- The grey a locked card is mixed towards. Not `UITheme.Color.Locked`: this is a BLEND target, not
-- a fill, and the kit's swatch is light enough that Secret (near-black) would come out lighter
-- locked than found.
local LOCK_GREY = Color3.fromRGB(118, 112, 130)
local LOCK_MIX = 0.45

local function blend(a, b, t)
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

-- Rec. 601, the same weights `UITheme.Luminance` uses. Written out rather than imported for the
-- reason `ScrollingPanelBuilder` writes out its own constants: this file draws and does not depend
-- on the kit, so one require here would pull the whole 3,100-line module in for three multiplies.
local function luminance(c)
	return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
end

local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
	return c
end

-- `mode` matters and is easy to get wrong: `ApplyStrokeMode.Contextual` -- the default -- puts the
-- stroke on the TEXT of a TextLabel/TextButton and on the BORDER of anything else. So a button that
-- wants both an outline and a halo needs two, and the outline one has to say `Border` explicitly or
-- both land on the caption and the shape is left with no edge at all.
local function stroke(inst, color, thickness, mode)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.LineJoinMode = Enum.LineJoinMode.Round
	if mode then s.ApplyStrokeMode = mode end
	s.Parent = inst
	return s
end

-- The tiled sheet that gives a flat fill its texture. Always `Active = false`: it covers the whole
-- card, and an ImageLabel that eats input would make the button under it dead -- the same trap
-- `ScrollingPanelBuilder` documents for its own copy of this helper.
local function studs(inst, radius, zIndex)
	local s = Instance.new("ImageLabel")
	s.Name = "StudTile"
	s.Size = UDim2.new(1, 0, 1, 0)
	s.BackgroundTransparency = 1
	s.Image = STUDS
	s.ImageColor3 = INK
	s.ImageTransparency = 0.93
	s.ScaleType = Enum.ScaleType.Tile
	s.TileSize = UDim2.new(0, 32, 0, 32)
	s.ZIndex = zIndex
	s.Active = false
	corner(s, radius)
	s.Parent = inst
	return s
end

local function text(parent, name, size, height, y, textSize, color, haloColor, haloWidth, zIndex)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = UDim2.new(0, size, 0, height)
	l.Position = UDim2.new(0, 20, 0, y)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextSize = textSize
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	-- Truncate rather than shrink: the three lines are a fixed ladder (26 / 16 / 14) and a label
	-- that resizes itself breaks the ladder the moment one mutation gets a longer name than the
	-- rest. Every string drawn here is authored, so truncation is a guard, not a layout.
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.ZIndex = zIndex
	stroke(l, haloColor, haloWidth)
	l.Parent = parent
	return l
end

-- ============================================================================
-- New(parent, mut, order, onWear) -> handle
-- ============================================================================
--
-- `onWear` is called with the mutation's name when the button is pressed AND the card is in a state
-- where pressing means something. The guard lives here rather than at the call site for the reason
-- the Journal's Equip button already documents: a greyed button that still fires a remote and gets
-- a refusal back says the press FAILED rather than that there was nothing to press.
function AuraCard.New(parent, mut, order, onWear)
	local base = parent.ZIndex + 1
	-- 0.55 rather than the kit's 0.86: that constant answers "is this surface white enough to need
	-- dark ink", and this question is the softer "which side of mid-grey is it". Common at rgb(200)
	-- is 0.78 and has to come out LIGHT here; under 0.86 it would not.
	local onLight = luminance(mut.color) > 0.55

	local card = Instance.new("Frame")
	card.Name = "Aura_" .. mut.name
	card.Size = UDim2.new(1, -6, 0, AuraCard.HEIGHT)
	card.LayoutOrder = order
	card.BackgroundColor3 = mut.color
	card.BorderSizePixel = 0
	card.ZIndex = base
	card.Parent = parent
	corner(card, 14)
	stroke(card, INK, 3.5)
	studs(card, 14, base)

	local title = text(card, "AuraTitle", 225, 32, 8, 26, WHITE, INK, 3, base + 3)
	title.Text = mut.name

	local stats = text(card, "Stats", 225, 22, 40, 16, INK, WHITE, 1.5, base + 3)
	stats.Text = ("\u{1F48E} x%.2f DNA  \u{26A1} +%d%% speed"):format(mut.incomeMult, mut.speedPct)

	-- The third line is the only place in the game that says where a mutation COMES FROM, which is
	-- why it survives the redraw: without it a locked row is a thing you cannot have and cannot find
	-- out how to get. When the aura IS found it turns into the roll count, so the line is never
	-- blank and the card's height never changes.
	local source = text(card, "Source", 225, 22, 62, 14, INK, WHITE, 1.5, base + 3)

	-- ---- the artwork, centred, with its own glow behind it
	local graphic = Instance.new("Frame")
	graphic.Name = "AuraGraphic"
	graphic.Size = UDim2.new(0, 120, 1, 0)
	graphic.Position = UDim2.new(0.52, 0, 0.5, 0)
	graphic.AnchorPoint = Vector2.new(0.5, 0.5)
	graphic.BackgroundTransparency = 1
	graphic.ZIndex = base + 2
	graphic.Parent = card

	-- ===== THE DISC IS PICKED AGAINST THE AURA, NOT AUTHORED (photographed 31.22) =====
	--
	-- The mock-up's disc is a flat white glow, and it works there because the mock-up drew a dark
	-- figure on it. Here what sits on the disc is the AURA'S OWN DRAWING, on a card painted the AURA'S
	-- OWN COLOUR -- so a fixed white disc is the wrong answer at both ends of the rarity ladder at
	-- once: Common's near-white artwork vanished into it (photographed as an empty white blob) and a
	-- fixed dark one would do the same to Secret at rgb(20,20,20).
	--
	-- One test, taken on the mutation's colour, serves both surfaces, because the card and the artwork
	-- are that same colour: a light aura gets a dark disc, a dark aura gets a light one. Nothing else
	-- here branches on luminance -- the two text lines are deliberately halo'd so they do not have to.
	local wave = Instance.new("Frame")
	wave.Name = "AuraWave"
	wave.Size = UDim2.new(0, 96, 0, 86)
	wave.Position = UDim2.new(0.5, 0, 0.5, 0)
	wave.AnchorPoint = Vector2.new(0.5, 0.5)
	wave.BackgroundColor3 = onLight and Color3.fromRGB(34, 26, 54) or WHITE
	wave.BackgroundTransparency = 0.45
	wave.BorderSizePixel = 0
	wave.ZIndex = base + 2
	wave.Parent = graphic
	local waveCorner = Instance.new("UICorner")
	waveCorner.CornerRadius = UDim.new(0.5, 0)
	waveCorner.Parent = wave

	-- `AuraIcon`, not `Resolve`: the lookup key for a mutation is its NAME, not an emoji -- see the
	-- note over that function. It answers nil for a mutation the drawing table has never heard of,
	-- so a row added to GameConfig next year gets the emoji fallback rather than an empty square.
	local art, artIsImage = nil, false
	local artId = IconLibrary.AuraIcon(mut.name)
	if artId then
		art = Instance.new("ImageLabel")
		art.Image = artId
		art.ScaleType = Enum.ScaleType.Fit
		art.BackgroundTransparency = 1
		artIsImage = true
	else
		art = Instance.new("TextLabel")
		art.Text = "\u{1F9EC}"
		art.Font = Enum.Font.FredokaOne
		art.TextSize = 52
		art.TextColor3 = WHITE
		art.BackgroundTransparency = 1
		stroke(art, INK, 3)
	end
	art.Name = "AuraArt"
	art.Size = UDim2.new(0, 72, 0, 72)
	art.Position = UDim2.new(0.5, 0, 0.5, 0)
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.ZIndex = base + 3
	art.Parent = graphic

	-- ---- the action column
	local actions = Instance.new("Frame")
	actions.Name = "Actions"
	actions.Size = UDim2.new(0, 170, 1, -16)
	actions.Position = UDim2.new(1, -12, 0.5, 0)
	actions.AnchorPoint = Vector2.new(1, 0.5)
	actions.BackgroundTransparency = 1
	actions.ZIndex = base + 3
	actions.Parent = card

	local btn = Instance.new("TextButton")
	btn.Name = "Wear"
	btn.Size = UDim2.new(1, 0, 0, 48)
	btn.Position = UDim2.new(0.5, 0, 0.5, 0)
	btn.AnchorPoint = Vector2.new(0.5, 0.5)
	btn.BackgroundColor3 = WHITE
	btn.AutoButtonColor = true
	btn.Font = Enum.Font.FredokaOne
	btn.TextSize = 24
	btn.TextColor3 = WHITE
	btn.Text = "Wear"
	btn.ZIndex = base + 4
	btn.Parent = actions
	corner(btn, 8)
	stroke(btn, INK, 3, Enum.ApplyStrokeMode.Border)   -- the shape's outline
	stroke(btn, INK, 2)                                -- the caption's own halo
	local btnGradient = Instance.new("UIGradient")
	btnGradient.Rotation = 90
	btnGradient.Parent = btn

	local enabled = false
	btn.MouseButton1Click:Connect(function()
		if not enabled then return end
		onWear(mut.name)
	end)

	local function setButton(caption, top, bottom, live)
		btn.Text = caption
		btnGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, top),
			ColorSequenceKeypoint.new(1, bottom),
		})
		enabled = live
		btn.AutoButtonColor = live
	end

	local handle = {}
	handle.Instance = card

	-- SetState is the whole of the card's public surface. It is called on every DataUpdate, so it
	-- only ever writes properties -- it never builds or destroys an instance, which is what lets the
	-- panel refresh three times a minute without losing the scroll position.
	function handle.SetState(count, worn)
		local owned = count > 0
		-- ===== A LOCKED CARD IS DESATURATED FIRST, THEN GREYED (photographed 31.22) =====
		--
		-- Blending the mutation's colour straight towards grey keeps its HUE and only drains it, which
		-- is fine for six of the seven and wrong for the one that matters: Godly is rgb(255,240,150),
		-- so 62% of the way to a mauve grey is rgb(170,161,138) -- a khaki card, which reads as a
		-- different, muddier object rather than as the same object switched off. Dropping to the
		-- colour's own LUMINANCE first throws the hue away, so every locked row is a neutral grey of
		-- the right weight: Secret stays the darkest of them and Godly the lightest, which is the one
		-- thing about the ladder worth keeping while it is switched off.
		local g = luminance(mut.color)
		card.BackgroundColor3 = owned and mut.color
			or blend(Color3.new(g, g, g), LOCK_GREY, LOCK_MIX)
		title.TextTransparency = owned and 0 or 0.25
		stats.TextTransparency = owned and 0 or 0.35
		wave.BackgroundTransparency = owned and 0.45 or 0.78
		if artIsImage then
			-- An unfound aura keeps its drawing but shows it as a silhouette, so the row still reads
			-- as "this exists and you have not got it" rather than as a blank square.
			art.ImageTransparency = owned and 0 or 0.72
		else
			art.TextTransparency = owned and 0 or 0.72
		end

		if not owned then
			source.Text = "\u{1F512} Roll it at the DNA Splicer"
			setButton("\u{1F512} Locked",
				Color3.fromRGB(178, 178, 190), Color3.fromRGB(128, 128, 142), false)
		elseif worn then
			source.Text = ("\u{1F9EC} Rolled x%d"):format(count)
			-- WORN IS A RECEIPT, NOT A REFUSAL. The button is correctly inert -- there is nothing to
			-- press on the aura you are already wearing -- but painting it the same grey as the rows
			-- you have NOT found puts the one row you achieved in the "you cannot have this" colour.
			-- Pale green of the tick's own hue instead, the split the Season track and the Daily
			-- board already use.
			setButton("\u{2713} Wearing",
				Color3.fromRGB(176, 226, 190), Color3.fromRGB(132, 194, 150), false)
		else
			source.Text = ("\u{1F9EC} Rolled x%d"):format(count)
			setButton("Wear",
				Color3.fromRGB(94, 224, 140), Color3.fromRGB(34, 168, 88), true)
		end
	end

	handle.SetState(0, false)
	return handle
end

return AuraCard
