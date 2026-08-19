-- CardKit -- the Rebirth panel's card language, extracted so other panels can speak it.
--
-- WHY THIS EXISTS. `UIComponents.ScrollingPanelBuilder` draws the look the owner picked as the
-- game's panel style: a near-black `UIStroke` around a two-stop gradient, a tiled stud sheet over
-- it, and text in FredokaOne with its own black halo. That look lives INSIDE the builder, and the
-- builder owns a whole panel -- its own overlay, header, close button and scroll frame. The
-- Inventory panel and the Relics panel are not builder panels and cannot become ones cheaply: they
-- are `registerPanel`'d frames sharing one tab strip that is right-aligned inside them, so
-- converting either alone would tear the strip in half.
--
-- So the CARD half of that language moves here, where both kinds of panel can reach it, and the
-- builder keeps drawing panels. This module deliberately does NOT know about scrolling, headers or
-- overlays -- it draws one card, one button, one label, and nothing else.
--
-- THE THREE THINGS THAT MAKE THE LOOK, and all three are load-bearing:
--   * the ink outline (0,0,50 at 4 px) is what makes a pastel card read as a solid object rather
--     than a wash -- without it a light gradient dissolves into a light panel;
--   * the stud sheet at 85% transparency is the texture that keeps a flat gradient from reading as
--     a web page;
--   * every text run carries its own black stroke, because white text over the light end of a
--     gradient is otherwise unreadable at the top of the card.
--
-- It is written against raw Instances rather than `UIKit.styleCard` ON PURPOSE. styleCard is the
-- other, older surface builder -- lip, gloss, InnerBody, ZIndex lifting -- and a card drawn half
-- through each would inherit both stacking schemes. One card, one kit.

local CardKit = {}

CardKit.INK = Color3.fromRGB(0, 0, 50)
CardKit.BLACK = Color3.fromRGB(0, 0, 0)
CardKit.WHITE = Color3.fromRGB(255, 255, 255)
CardKit.STUDS = "rbxassetid://17601461662"

-- A disabled button is not a hidden one: the card still has to say what it would do, or the player
-- cannot tell "you cannot use this" from "this does not exist". Grey, but legible. Same pair the
-- builder uses, so a greyed card is the same grey in both places.
CardKit.DISABLED = { Color3.fromRGB(178, 178, 190), Color3.fromRGB(128, 128, 142) }

local INK, BLACK, WHITE = CardKit.INK, CardKit.BLACK, CardKit.WHITE

function CardKit.Corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
	return c
end

function CardKit.Stroke(inst, color, thickness, mode)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	if mode then s.ApplyStrokeMode = mode end
	s.Parent = inst
	return s
end

function CardKit.Gradient(inst, colors, rotation)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, colors[1]),
		ColorSequenceKeypoint.new(1, colors[2]),
	})
	if rotation then g.Rotation = rotation end
	g.Parent = inst
	return g
end

-- Rewrites an existing gradient in place. Every live panel needs this: a card whose state changed
-- must be repainted, and destroying and rebuilding the card instead loses the scroll position.
function CardKit.SetGradient(g, colors)
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, colors[1]),
		ColorSequenceKeypoint.new(1, colors[2]),
	})
end

-- The tiled stud sheet that gives every surface its texture. Parented last so it sits over the
-- gradient, and ALWAYS non-interactive: it covers the whole surface, so an ImageLabel that ate
-- input would make the button underneath dead.
function CardKit.Studs(inst, tile, transparency, radius, zIndex)
	local s = Instance.new("ImageLabel")
	s.Name = "Studs"
	s.Size = UDim2.new(1, 0, 1, 0)
	s.BackgroundTransparency = 1
	s.Image = CardKit.STUDS
	s.ScaleType = Enum.ScaleType.Tile
	s.TileSize = UDim2.new(0, tile, 0, tile)
	s.ImageTransparency = transparency
	s.ImageColor3 = BLACK
	s.ZIndex = zIndex
	s.Active = false
	CardKit.Corner(s, radius)
	s.Parent = inst
	return s
end

-- White FredokaOne with a black halo -- the only text this kit draws. `xAlign` defaults to Left
-- because these cards carry an icon column, unlike the builder's centred ones.
function CardKit.Text(parent, opts)
	local l = Instance.new("TextLabel")
	l.Name = opts.name or "Label"
	l.Size = opts.size or UDim2.new(1, 0, 0, 24)
	l.Position = opts.position or UDim2.new(0, 0, 0, 0)
	l.BackgroundTransparency = 1
	l.Text = opts.text or ""
	l.Font = Enum.Font.FredokaOne
	l.TextSize = opts.textSize or 22
	l.TextColor3 = opts.color or WHITE
	l.TextXAlignment = Enum.TextXAlignment[opts.xAlign or "Left"]
	l.TextYAlignment = Enum.TextYAlignment[opts.yAlign or "Center"]
	l.TextScaled = false
	-- WRAPPING IS SET BEFORE NOTHING AND AFTER NOTHING HERE, which is the point. `UIKit.themeLabel`
	-- assigns `TextScaled`, and that turns wrapping back ON underneath a caller that set it false --
	-- the trap the potion sub-label already carries a note about. This kit never sets TextScaled, so
	-- the flag means what it says and a caller gets one line or two by asking.
	l.TextWrapped = opts.wrapped and true or false
	l.TextTruncate = opts.truncate == false and Enum.TextTruncate.None or Enum.TextTruncate.AtEnd
	l.ZIndex = opts.zIndex or 1
	CardKit.Stroke(l, BLACK, opts.strokeThickness or 3)
	l.Parent = parent
	return l
end

-- ===== THE CARD =====
--
-- An ink-outlined, studded, gradient panel and nothing else -- no icon, no text, no buttons. Those
-- are the caller's, because the two panels that use this lay their contents out differently (the
-- potion shelf is a left-icon row; a relic slot is a centred tile) and a card builder that tries to
-- own both ends up with a `layout = "row" | "tile"` flag, which is two builders wearing one name.
function CardKit.Card(parent, opts)
	local card = Instance.new("Frame")
	card.Name = opts.name or "Card"
	card.Size = opts.size or UDim2.new(1, 0, 0, 80)
	if opts.position then card.Position = opts.position end
	if opts.anchorPoint then card.AnchorPoint = opts.anchorPoint end
	card.LayoutOrder = opts.layoutOrder or 0
	card.BackgroundColor3 = WHITE
	card.BorderSizePixel = 0
	card.ZIndex = opts.zIndex or 1
	card.Parent = parent

	local radius = opts.radius or 12
	CardKit.Corner(card, radius)
	local grad = CardKit.Gradient(card, opts.colors or { WHITE, WHITE })
	CardKit.Stroke(card, INK, opts.strokeThickness or 4)
	CardKit.Studs(card, opts.studTile or 24, opts.studTransparency or 0.85, radius, card.ZIndex)

	return card, function(colors) CardKit.SetGradient(grad, colors) end
end

-- ===== THE ACTION BUTTON =====
--
-- The builder's card button, to the pixel: gradient fill, ink BORDER stroke plus a black contour,
-- studs, and a caption indented past its icon only when there is one -- a plain word like "USE"
-- sitting behind a 35 px indent with no picture in it reads as off-centre, which it is.
--
-- Returns the button and a handle, because `SetEnabled` has to be able to reach the gradient and
-- the caller must not have to keep three parallel references to do it.
function CardKit.Button(parent, opts)
	local btn = Instance.new("TextButton")
	btn.Name = opts.name or "Action"
	btn.Size = opts.size or UDim2.new(0, 96, 0, 44)
	if opts.position then btn.Position = opts.position end
	if opts.anchorPoint then btn.AnchorPoint = opts.anchorPoint end
	btn.LayoutOrder = opts.layoutOrder or 0
	btn.BackgroundColor3 = WHITE
	btn.AutoButtonColor = true
	btn.Font = Enum.Font.FredokaOne
	btn.TextSize = opts.textSize or 24
	btn.TextColor3 = WHITE
	btn.Text = opts.text or ""
	btn.ZIndex = opts.zIndex or 1
	btn.Parent = parent

	local radius = opts.radius or 8
	local grad = CardKit.Gradient(btn, opts.colors or { WHITE, WHITE })
	CardKit.Corner(btn, radius)
	CardKit.Stroke(btn, INK, 3, Enum.ApplyStrokeMode.Border)
	CardKit.Stroke(btn, BLACK, 2)
	CardKit.Studs(btn, 15, 0.55, radius, btn.ZIndex)

	local baseColors = opts.colors
	local enabled = true
	local handle
	handle = {
		Instance = btn,
		SetText = function(t) btn.Text = tostring(t or "") end,
		SetColors = function(colors) CardKit.SetGradient(grad, colors) end,
		-- disabled is a LOOK plus a guard, never `Visible = false`: a button that vanishes takes its
		-- caption with it and the card stops explaining itself
		SetEnabled = function(on, colors)
			enabled = on and true or false
			btn.AutoButtonColor = enabled
			CardKit.SetGradient(grad, enabled and (colors or baseColors) or CardKit.DISABLED)
		end,
		IsEnabled = function() return enabled end,
	}

	btn.MouseButton1Click:Connect(function()
		if not enabled then return end
		if opts.callback then
			-- one card's bad callback must not take the panel's other buttons down with it
			local ok, err = pcall(opts.callback, handle)
			if not ok then warn(("[CardKit] %s action failed: %s"):format(btn.Name, tostring(err))) end
		end
	end)

	return btn, handle
end

-- ===== THE COUNT PILL =====
--
-- "x6" on a dark capsule rather than as loose white text on the card. A number floating on a
-- gradient has no edge to sit against and reads as part of the sentence beside it; a pill is a
-- separate object, which is what a quantity is.
function CardKit.Pill(parent, opts)
	local pill = Instance.new("Frame")
	pill.Name = opts.name or "Pill"
	pill.Size = opts.size or UDim2.new(0, 56, 0, 32)
	if opts.position then pill.Position = opts.position end
	if opts.anchorPoint then pill.AnchorPoint = opts.anchorPoint end
	pill.BackgroundColor3 = opts.color or Color3.fromRGB(28, 30, 58)
	pill.BackgroundTransparency = opts.transparency or 0.18
	pill.BorderSizePixel = 0
	pill.ZIndex = opts.zIndex or 1
	pill.Parent = parent
	CardKit.Corner(pill, 999)
	CardKit.Stroke(pill, INK, 2)

	local label = CardKit.Text(pill, {
		name = "Value",
		text = opts.text or "",
		size = UDim2.new(1, -8, 1, 0),
		position = UDim2.new(0, 4, 0, 0),
		textSize = opts.textSize or 22,
		xAlign = "Center",
		zIndex = pill.ZIndex + 1,
		strokeThickness = 2,
	})

	return pill, label
end

return CardKit
