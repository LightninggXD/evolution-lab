--[[
	UITheme - shared "chunky comic" design system for Evolution Lab.

	Every interactive surface = thick dark outline + rounded corners + vertical body
	gradient + hard drop shadow + faint glossy sheen + outlined display text.

	HARD INVARIANT (this is the bug that started the redesign):
		Gloss BackgroundTransparency >= 0.72 AND every text/content child renders at a
		strictly HIGHER ZIndex than the gloss.
		Layering: Shadow(-1) < Shell(0) < Gloss(+1) < Content(+3) < Badge(+5)
]]

local UITheme = {}

-- ============================================================================
-- PALETTE
-- ============================================================================
local Color = {
	Outline    = Color3.fromRGB(26, 18, 36),
	Shadow     = Color3.fromRGB(18, 12, 26),
	White      = Color3.fromRGB(255, 255, 255),
	Cream      = Color3.fromRGB(255, 248, 235),
	PanelWhite = Color3.fromRGB(252, 252, 255),
	PanelBlue  = Color3.fromRGB(86, 178, 232),
	Gold       = Color3.fromRGB(255, 205, 70),
	Orange     = Color3.fromRGB(247, 150, 35),
	Blue       = Color3.fromRGB(74, 164, 224),
	SkyBlue    = Color3.fromRGB(120, 205, 245),
	Green      = Color3.fromRGB(95, 205, 105),
	Red        = Color3.fromRGB(232, 72, 72),
	Purple     = Color3.fromRGB(170, 110, 240),
	Pink       = Color3.fromRGB(255, 110, 200),
	Grey       = Color3.fromRGB(150, 150, 165),
	-- "unavailable", on ~28 call sites: a claimed daily card, an unaffordable buy button, an
	-- inactive tab, a locked pet slot. It was rgb(110,110,124), which was a step DOWN from the old
	-- near-black panel and read correctly as dimmed. Against the light panel shell the same colour
	-- reads as a hole punched in the card -- so it lifts with the panel and stays muted relative to
	-- it rather than relative to nothing. Still far enough above Outline for white text to hold.
	Locked     = Color3.fromRGB(163, 161, 180),

	-- Bright pastel set -- used by the HUD tiles so the columns read as candy
	-- buttons rather than the darker panel chrome.
	Mint       = Color3.fromRGB(124, 226, 142),
	Sunny      = Color3.fromRGB(255, 214, 92),
	Bubblegum  = Color3.fromRGB(255, 138, 205),
	Lavender   = Color3.fromRGB(186, 146, 250),
	Aqua       = Color3.fromRGB(114, 202, 245),
	Peach      = Color3.fromRGB(255, 168, 104),
	Coral      = Color3.fromRGB(255, 124, 124),
}
UITheme.Color = Color

-- ============================================================================
-- Z ORDER CONTRACT
-- ============================================================================
local Z = {
	Shadow  = -1,
	Shell   = 0,
	Gloss   = 1,
	Content = 3,
	Badge   = 5,
	Overlay = 7,
}
UITheme.Z = Z

-- ============================================================================
-- FONTS (guarded: FredokaOne may not exist on older Studio builds)
-- ============================================================================
local function probeFont(name, fallback)
	local ok, resolved = pcall(function()
		local probe = Instance.new("TextLabel")
		probe.Font = Enum.Font[name]
		local f = probe.Font
		probe:Destroy()
		return f
	end)
	if ok and typeof(resolved) == "EnumItem" and resolved.Name == name then
		return resolved
	end
	return fallback
end

local DisplayFont = probeFont("FredokaOne", Enum.Font.GothamBlack)
local BodyFont = probeFont("GothamBold", Enum.Font.GothamBlack)

UITheme.Font = {
	Display = DisplayFont,
	Body = BodyFont,
}

-- ============================================================================
-- INTERNAL HELPERS
-- ============================================================================

-- amt > 0 lightens toward white, amt < 0 darkens. (Same maths as MainUI.)
local function shade(c, amt)
	if amt >= 0 then
		return Color3.new(
			math.clamp(c.R + (1 - c.R) * amt, 0, 1),
			math.clamp(c.G + (1 - c.G) * amt, 0, 1),
			math.clamp(c.B + (1 - c.B) * amt, 0, 1)
		)
	end
	local k = 1 + amt
	return Color3.new(math.clamp(c.R * k, 0, 1), math.clamp(c.G * k, 0, 1), math.clamp(c.B * k, 0, 1))
end
UITheme.Shade = shade

-- ============================================================================
-- THE BUTTON GRADIENT -- ONE CURVE, EVERY SURFACE IN THE GAME
-- ============================================================================
-- This function is the single lever for the whole UI's look: UITheme's own applyShell, the
-- progress bars, the icon tiles AND MainUI's `styleCard` (via UITheme.GradientFor) all read it.
-- Change the four numbers here and every button, card, panel and tile changes together.
--
-- The curve is measured off the reference art rather than invented: the top edge is a strong
-- lighten toward white, the middle sits just above the base colour, and the bottom is a DEEPER
-- version of the same hue -- not a dark one.
--
-- That last stop is the whole difference. It used to be shade(c, -0.70), i.e. 30% of the colour,
-- which is nearly black: every button faded from candy at the top to mud at the bottom and read as
-- plastic lit from above rather than as a painted toy. -0.28 keeps the bottom recognisably blue,
-- yellow, green -- the button stays one colour with a light and a shadow side, which is what the
-- reference does.
--
-- The stops are also weighted toward the top (0.42 rather than 0.55) so the light half is slightly
-- larger than the dark half. Even split reads as a two-tone stripe; uneven reads as a curved
-- surface.
local function gradientFor(c)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, shade(c, 0.62)),
		ColorSequenceKeypoint.new(0.42, shade(c, 0.10)),
		ColorSequenceKeypoint.new(1.00, shade(c, -0.28)),
	})
end

-- There used to be a second, softer curve here for the HUD tiles, because the main one was too
-- dark for them. Now that gradientFor IS the soft curve, keeping two would mean two subtly
-- different button looks in one screen -- which is exactly what "every button identical" rules
-- out. Kept as a name so the four call sites that ask for it still read as intentional.
local pastelGradientFor = gradientFor

local function toUDim(radius, default)
	if typeof(radius) == "UDim" then
		return radius
	end
	if type(radius) == "number" then
		return UDim.new(0, radius)
	end
	return default or UDim.new(0, 16)
end

-- Thick dark outline + rounded corners + moulded vertical gradient.
local function applyShell(inst, color, radius, thickness)
	inst.BackgroundColor3 = color
	inst.BackgroundTransparency = 0
	inst.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = toUDim(radius)
	corner.Parent = inst

	-- 5, not 4. The border is the loudest thing about the reference style -- it is what makes a
	-- button read as a sticker laid on the screen rather than as a coloured rectangle -- and at 4px
	-- against these brighter gradients it had started to look like an accident.
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness or 5
	stroke.Color = Color.Outline
	stroke.Transparency = 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = inst

	local grad = Instance.new("UIGradient")
	grad.Name = "Gradient"
	grad.Rotation = 90
	grad.Color = gradientFor(color)
	grad.Parent = inst

	inst:SetAttribute("BaseColor", color)
	return corner, stroke, grad
end

--[[
	Hard drop shadow.
	A shadow cannot be a CHILD of the element it sits behind and still render behind
	it reliably, so it is parented as a SIBLING. If the parent runs a UIListLayout a
	sibling frame would become a layout item and break the row, so in that case we
	fall back to an inner bottom "lip" which reads as the same moulded depth.

	Returns: shadowInstance, pressFn(isPressed)
]]
local function addShadow(inst, radius)
	local parent = inst.Parent
	if not parent then
		return nil, function() end
	end

	local cornerRadius = toUDim(radius)

	if parent:FindFirstChildOfClass("UIListLayout")
		or parent:FindFirstChildOfClass("UIGridLayout")
		or parent:FindFirstChildOfClass("UIPageLayout")
		or parent:FindFirstChildOfClass("UITableLayout") then
		-- inner bottom lip variant
		local base = inst:GetAttribute("BaseColor") or inst.BackgroundColor3
		local lip = Instance.new("Frame")
		lip.Name = "Shadow"
		-- -0.38, not -0.55. The lip is the shadowed underside of the SAME painted surface, so it has
		-- to sit one step below the gradient's bottom stop (-0.28). At -0.55 it was far darker than
		-- the gradient and read as a black bar stuck across the bottom of the button -- doubly wrong
		-- now that the gradient itself no longer goes dark.
		lip.BackgroundColor3 = shade(base, -0.38)
		lip.BackgroundTransparency = 0
		lip.BorderSizePixel = 0
		lip.AnchorPoint = Vector2.new(0.5, 1)
		lip.Position = UDim2.new(0.5, 0, 1, 0)
		lip.Size = UDim2.new(1, 0, 0, 6)
		lip.ZIndex = inst.ZIndex
		local lipCorner = Instance.new("UICorner")
		lipCorner.CornerRadius = cornerRadius
		lipCorner.Parent = lip
		lip.Parent = inst
		lip:SetAttribute("IsLip", true)

		local function press(down)
			lip.Size = UDim2.new(1, 0, 0, down and 3 or 6)
		end
		return lip, press
	end

	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.BackgroundColor3 = Color.Shadow
	shadow.BackgroundTransparency = 0
	shadow.BorderSizePixel = 0
	shadow.AnchorPoint = inst.AnchorPoint
	shadow.Size = inst.Size
	shadow.ZIndex = inst.ZIndex + Z.Shadow
	shadow.Visible = inst.Visible

	local shCorner = Instance.new("UICorner")
	shCorner.CornerRadius = cornerRadius
	shCorner.Parent = shadow

	local offset = 5
	local function sync()
		shadow.AnchorPoint = inst.AnchorPoint
		shadow.Size = inst.Size
		shadow.Position = inst.Position + UDim2.new(0, 0, 0, offset)
		shadow.Visible = inst.Visible
		shadow.ZIndex = inst.ZIndex + Z.Shadow
	end
	sync()
	shadow.Parent = parent

	inst:GetPropertyChangedSignal("Position"):Connect(sync)
	inst:GetPropertyChangedSignal("Size"):Connect(sync)
	inst:GetPropertyChangedSignal("Visible"):Connect(sync)
	inst:GetPropertyChangedSignal("AnchorPoint"):Connect(sync)
	inst:GetPropertyChangedSignal("ZIndex"):Connect(sync)
	inst.Destroying:Connect(function()
		shadow:Destroy()
	end)

	local function press(down)
		-- button sinks into its own shadow: shell +3px, shadow gap 5 -> 2
		offset = down and 2 or 5
		sync()
	end

	return shadow, press
end

-- Faint top sheen. NEVER opaque, NEVER above content.
-- Sits at the documented FLOOR of 0.72 and is a little wider and taller than it was, because the
-- reference's top highlight covers most of the upper half of the button. It does not go below
-- 0.72: that number is a contract, not a preference -- a gloss any stronger starts washing out the
-- white label underneath it, which is the bug this invariant exists to prevent.
local function addGloss(inst, radius)
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.BackgroundColor3 = Color.White
	gloss.BackgroundTransparency = 0.72 -- invariant: >= 0.72
	gloss.BorderSizePixel = 0
	gloss.Size = UDim2.new(0.88, 0, 0.4, 0)
	gloss.Position = UDim2.new(0.06, 0, 0.06, 0)
	gloss.ZIndex = inst.ZIndex + Z.Gloss

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = gloss

	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.7, 0.92),
		NumberSequenceKeypoint.new(1, 1),
	})
	grad.Parent = gloss

	gloss.Parent = inst
	return gloss
end

-- The single most recognisable feature of the reference art. 4px to match the thicker shell
-- border above -- a heavy button frame around a thinly outlined word reads as two different
-- drawings sharing a rectangle.
local function outlineText(label, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness or 4
	stroke.Color = Color.Outline
	stroke.Transparency = 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	return stroke
end

-- Big text, always. Never an 11-13px fixed TextSize on the HUD.
local function autoSize(label, minSize, maxSize)
	label.TextScaled = true
	local c = Instance.new("UITextSizeConstraint")
	c.MinTextSize = minSize or 14
	c.MaxTextSize = maxSize or 28
	c.Parent = label
	return c
end

UITheme.GradientFor = gradientFor
UITheme.OutlineText = outlineText
UITheme.AutoSize = autoSize

-- Shared body used by Button and Card.
local function buildSurface(inst, parent, opts, defaultRadius)
	opts = opts or {}
	local color = opts.color or Color.Blue
	local base = opts.zIndex or Z.Shell

	inst.Name = opts.name or inst.Name
	inst.Size = opts.size or UDim2.new(0, 180, 0, 56)
	inst.ZIndex = base
	if opts.anchorPoint then
		inst.AnchorPoint = opts.anchorPoint
	end
	if opts.position then
		inst.Position = opts.position
	end
	if opts.layoutOrder then
		inst.LayoutOrder = opts.layoutOrder
	end
	if opts.visible ~= nil then
		inst.Visible = opts.visible
	end

	local radius = toUDim(opts.radius, defaultRadius or UDim.new(0, 16))
	applyShell(inst, color, radius, opts.thickness)
	inst.Parent = parent

	local shadow, press = nil, function() end
	if opts.shadow ~= false then
		shadow, press = addShadow(inst, radius)
	end

	if opts.gloss ~= false then
		addGloss(inst, radius)
	end

	return color, base, press
end

local function buildLabelChild(inst, opts, base, text, maxText)
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -16, 1, -12)
	label.Position = UDim2.new(0.5, 0, 0.5, 0)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Font = DisplayFont
	label.TextColor3 = Color.White
	label.Text = text
	label.TextWrapped = opts.wrapped == true
	label.ZIndex = base + Z.Content -- strictly above the gloss
	outlineText(label)
	autoSize(label, opts.minTextSize or 14, opts.maxTextSize or opts.textSize or maxText or 26)
	label.Parent = inst
	return label
end

-- ============================================================================
-- PUBLIC: Button
-- ============================================================================
function UITheme.Button(parent, opts)
	opts = opts or {}
	local button = Instance.new("TextButton")
	button.Name = opts.name or "Button"
	button.AutoButtonColor = false
	button.Text = "" -- visible text lives in the child Label (own stroke, above gloss)
	button.TextTransparency = 1

	local color, base, press = buildSurface(button, parent, opts, UDim.new(0, 16))

	local text = opts.text or ""
	if opts.icon and opts.icon ~= "" then
		text = opts.icon .. " " .. text
	end
	buildLabelChild(button, opts, base, text, 26)

	-- press feedback
	local pressed = false
	local restPos = button.Position
	local function down()
		if pressed then
			return
		end
		pressed = true
		restPos = button.Position
		button.Position = restPos + UDim2.new(0, 0, 0, 3)
		press(true)
	end
	local function up()
		if not pressed then
			return
		end
		pressed = false
		button.Position = restPos
		press(false)
	end
	button.MouseButton1Down:Connect(down)
	button.MouseButton1Up:Connect(up)
	button.MouseLeave:Connect(up)

	if opts.badge then
		UITheme.Badge(button, opts.badge, opts.badgeColor)
	end

	return button
end

-- ============================================================================
-- PUBLIC: Card (Button without the interaction)
-- ============================================================================
function UITheme.Card(parent, opts)
	opts = opts or {}
	local card = Instance.new("Frame")
	card.Name = opts.name or "Card"

	local color, base = buildSurface(card, parent, opts, UDim.new(0, 16))

	if opts.text and opts.text ~= "" then
		local text = opts.text
		if opts.icon and opts.icon ~= "" then
			text = opts.icon .. " " .. text
		end
		buildLabelChild(card, opts, base, text, 26)
	end

	if opts.badge then
		UITheme.Badge(card, opts.badge, opts.badgeColor)
	end

	return card
end

-- ============================================================================
-- PUBLIC: IconTile - square tile, big icon on top, caption inside the bottom strip
-- ============================================================================
function UITheme.IconTile(parent, opts)
	opts = opts or {}
	local tile = Instance.new("TextButton")
	tile.Name = opts.name or "IconTile"
	tile.AutoButtonColor = false
	tile.Text = ""
	tile.TextTransparency = 1

	local color = opts.color or Color.Blue
	local radius = toUDim(opts.radius, UDim.new(0, 18))

	-- TWO EDGES, NOT THREE. A tile is the dark outline and the coloured face, and nothing between.
	--
	-- It has been wrong twice in the same place. First the rim between them was Cream, which put a
	-- white ring around every HUD button; replacing that with a darker shade of the tile's own hue
	-- fixed the colour and kept the fault -- the ring was still a third edge, just a dark one, and
	-- against the bright zones it read as a border somebody had left half-finished.
	--
	-- The outer shell still exists because it is the TextButton: it owns the click, the stroke and
	-- the shadow. It is simply the SAME colour as the body and inset by nothing, so the two are one
	-- surface. Anything that recolours a tile has to keep them in step -- see UITheme.SetColor.
	local tileOpts = {}
	for k, v in pairs(opts) do
		tileOpts[k] = v
	end
	tileOpts.size = opts.size or UDim2.new(0, 82, 0, 82)
	tileOpts.color = color
	tileOpts.radius = radius
	tileOpts.gloss = false -- the gloss belongs to the body, which is what is actually visible

	local _, base, press = buildSurface(tile, parent, tileOpts, UDim.new(0, 18))
	tile.ClipsDescendants = false -- the badge still hangs outside the tile

	local ringGrad = tile:FindFirstChild("Gradient")
	if ringGrad and ringGrad:IsA("UIGradient") then
		-- matched to the body's, so the corners cannot show a seam where the two roundings differ
		ringGrad.Color = pastelGradientFor(color)
	end

	local INSET = 0
	local bodyRadius = UDim.new(radius.Scale, math.max(radius.Offset - INSET, 6))
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Size = UDim2.new(1, -INSET * 2, 1, -INSET * 2)
	body.Position = UDim2.new(0, INSET, 0, INSET)
	body.ZIndex = base + 1
	applyShell(body, color, bodyRadius, 0)
	local bodyGrad = body:FindFirstChild("Gradient")
	if bodyGrad and bodyGrad:IsA("UIGradient") then
		bodyGrad.Color = pastelGradientFor(color)
	end
	body.Parent = tile
	addGloss(body, bodyRadius)

	local hasCaption = opts.caption ~= nil and opts.caption ~= ""

	local icon = Instance.new("TextLabel")
	icon.Name = "Label"
	icon.BackgroundTransparency = 1
	icon.Font = DisplayFont
	icon.TextColor3 = Color.White
	icon.Text = opts.icon or opts.text or ""
	icon.ZIndex = body.ZIndex + Z.Content
	if hasCaption then
		-- 0.54, down from 0.60. The icon was taking six tenths of the tile and the word underneath it
		-- was taking three, and the word is the half a player actually reads -- an emoji at 38pt is
		-- legible at any size, "Inventory" at 10pt is not. See the caption block below.
		icon.Size = UDim2.new(1, -12, 0.54, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 5)
		icon.AnchorPoint = Vector2.new(0.5, 0)
	else
		icon.Size = UDim2.new(1, -14, 1, -14)
		icon.Position = UDim2.new(0.5, 0, 0.5, 0)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
	end
	outlineText(icon)
	autoSize(icon, 20, opts.maxTextSize or 38)
	icon.Parent = body

	if hasCaption then
		local caption = Instance.new("TextLabel")
		caption.Name = "Caption"
		caption.BackgroundTransparency = 1
		-- THE THREE NUMBERS THAT MADE THE HUD CAPTIONS UNREADABLE, and why each one moved.
		--
		-- TextScaled picks the largest size that fits BOTH the band's height and its width, then the
		-- UITextSizeConstraint clamps the result. The old band was 0.30 of the tile with 8px of
		-- horizontal padding, and the clamp floor was 10 -- so a long word like "Inventory" or
		-- "Auto OFF" bound on WIDTH and dropped all the way to that floor while the icon above it sat
		-- at 38. On a short viewport the tile itself shrinks toward 40px, the band with it, and every
		-- caption in the HUD pinned at 10pt.
		--
		--   0.30 -> 0.34   a taller band, paid for out of the icon's 0.60 -> 0.54 above
		--   -8   -> -4     4px of padding instead of 8, which is 8px of extra width for the word
		--                  that is binding on width in the first place
		--   10   -> 13     the floor. Worth checking against the smallest tile the responsive pass
		--                  will build: at its 40px minimum the band is 0.34 * 40 = 13.6px, so 13 is
		--                  the largest floor that still fits inside its own band there.
		caption.Size = UDim2.new(1, -4, 0.34, 0)
		caption.Position = UDim2.new(0.5, 0, 1, -4)
		caption.AnchorPoint = Vector2.new(0.5, 1)
		caption.Font = DisplayFont
		caption.TextColor3 = Color.White
		caption.Text = opts.caption
		caption.ZIndex = body.ZIndex + Z.Content
		-- 3.5, up from 2.5. These sit on saturated pastel tiles and the caption is the one label in
		-- the kit small enough for a thin outline to stop separating it from what is behind it.
		outlineText(caption, 3.5)
		autoSize(caption, 13, 22)
		caption.Parent = body
	end

	if opts.badge then
		UITheme.Badge(tile, opts.badge, opts.badgeColor)
	end

	local pressed = false
	local restPos = tile.Position
	tile.MouseButton1Down:Connect(function()
		if pressed then
			return
		end
		pressed = true
		restPos = tile.Position
		tile.Position = restPos + UDim2.new(0, 0, 0, 3)
		press(true)
	end)
	local function up()
		if not pressed then
			return
		end
		pressed = false
		tile.Position = restPos
		press(false)
	end
	tile.MouseButton1Up:Connect(up)
	tile.MouseLeave:Connect(up)

	return tile
end

-- ============================================================================
-- PUBLIC: Label
-- ============================================================================
function UITheme.Label(parent, opts)
	opts = opts or {}
	local label = Instance.new("TextLabel")
	label.Name = opts.name or "Label"
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Size = opts.size or UDim2.new(1, 0, 0, 28)
	label.Font = DisplayFont
	label.TextColor3 = opts.color or Color.White
	label.Text = opts.text or ""
	label.TextWrapped = opts.wrapped == true
	label.ZIndex = opts.zIndex or Z.Content
	if opts.position then
		label.Position = opts.position
	end
	if opts.anchorPoint then
		label.AnchorPoint = opts.anchorPoint
	end
	if opts.layoutOrder then
		label.LayoutOrder = opts.layoutOrder
	end
	if opts.visible ~= nil then
		label.Visible = opts.visible
	end

	if opts.xAlign == "Left" then
		label.TextXAlignment = Enum.TextXAlignment.Left
	elseif opts.xAlign == "Right" then
		label.TextXAlignment = Enum.TextXAlignment.Right
	elseif typeof(opts.xAlign) == "EnumItem" then
		label.TextXAlignment = opts.xAlign
	else
		label.TextXAlignment = Enum.TextXAlignment.Center
	end

	outlineText(label, opts.strokeThickness)
	autoSize(label, opts.minTextSize or 14, opts.maxTextSize or opts.textSize or 30)
	label.Parent = parent
	return label
end

-- ============================================================================
-- PUBLIC: Pill - currency readout, NO panel behind it
-- ============================================================================
function UITheme.Pill(parent, opts)
	opts = opts or {}
	local frame = Instance.new("Frame")
	frame.Name = opts.name or "Pill"
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = opts.size or UDim2.new(0, 210, 0, 42)
	frame.ZIndex = opts.zIndex or Z.Content
	if opts.position then
		frame.Position = opts.position
	end
	if opts.anchorPoint then
		frame.AnchorPoint = opts.anchorPoint
	end
	if opts.layoutOrder then
		frame.LayoutOrder = opts.layoutOrder
	end
	if opts.visible ~= nil then
		frame.Visible = opts.visible
	end
	frame.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Padding = UDim.new(0, 6)
	layout.Parent = frame

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.new(0, 40, 1, 0)
	icon.LayoutOrder = 1
	icon.Font = DisplayFont
	icon.TextColor3 = Color.White
	icon.Text = opts.icon or ""
	icon.ZIndex = frame.ZIndex
	outlineText(icon)
	autoSize(icon, 16, opts.maxTextSize or 34)
	icon.Parent = frame

	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.BackgroundTransparency = 1
	value.Size = UDim2.new(1, -46, 1, 0)
	value.LayoutOrder = 2
	value.Font = DisplayFont
	value.TextColor3 = opts.color or Color.White
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.Text = opts.text or "0"
	value.ZIndex = frame.ZIndex
	outlineText(value)
	autoSize(value, 16, opts.maxTextSize or 34)
	value.Parent = frame

	return frame
end

-- ============================================================================
-- PUBLIC: Modal
-- ============================================================================
function UITheme.Modal(parent, opts)
	opts = opts or {}
	local base = opts.zIndex or 50

	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.BorderSizePixel = 0
	dim.Size = UDim2.new(1, 0, 1, 0)
	dim.Position = UDim2.new(0, 0, 0, 0)
	dim.ZIndex = base - 1
	dim.Visible = false
	dim.Parent = parent

	local modal = Instance.new("Frame")
	modal.Name = opts.name or "Modal"
	modal.Size = opts.size or UDim2.new(0, 520, 0, 380)
	modal.Position = opts.position or UDim2.new(0.5, 0, 0.5, 0)
	modal.AnchorPoint = opts.anchorPoint or Vector2.new(0.5, 0.5)
	modal.ZIndex = base
	modal.Visible = false

	local radius = toUDim(opts.radius, UDim.new(0, 22))
	applyShell(modal, opts.color or Color.PanelWhite, radius, 5)
	modal.Parent = parent

	if opts.shadow ~= false then
		addShadow(modal, radius)
	end

	-- white frame around a coloured inner area
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -28, 1, -28)
	content.Position = UDim2.new(0, 14, 0, 14)
	content.ZIndex = base + Z.Content
	applyShell(content, opts.accent or Color.PanelBlue, UDim.new(0, 16), 4)
	content.Parent = modal

	if opts.gloss ~= false then
		local gloss = addGloss(content, UDim.new(0, 16))
		gloss.ZIndex = content.ZIndex + Z.Gloss
	end

	local title = UITheme.Label(modal, {
		name = "Title",
		text = opts.title or "",
		size = UDim2.new(0.62, 0, 0, 44),
		position = UDim2.new(0, 22, 0, -12),
		xAlign = "Left",
		maxTextSize = 40,
		zIndex = base + Z.Badge,
	})
	title.ZIndex = base + Z.Badge

	local closeButton = UITheme.Button(modal, {
		name = "Close",
		text = "X",
		color = Color.Red,
		radius = 12,
		size = UDim2.new(0, 44, 0, 44),
		position = UDim2.new(1, -6, 0, -6),
		anchorPoint = Vector2.new(1, 0),
		zIndex = base + Z.Badge,
		maxTextSize = 30,
	})

	modal:GetPropertyChangedSignal("Visible"):Connect(function()
		dim.Visible = modal.Visible
	end)
	modal.Destroying:Connect(function()
		dim:Destroy()
	end)

	return modal, content, closeButton
end

-- ============================================================================
-- PUBLIC: ProgressBar
-- ============================================================================
function UITheme.ProgressBar(parent, opts)
	opts = opts or {}
	local base = opts.zIndex or Z.Shell
	local radius = toUDim(opts.radius, UDim.new(1, 0))

	local bar = Instance.new("Frame")
	bar.Name = opts.name or "ProgressBar"
	bar.Size = opts.size or UDim2.new(1, 0, 0, 30)
	bar.ZIndex = base
	if opts.position then
		bar.Position = opts.position
	end
	if opts.anchorPoint then
		bar.AnchorPoint = opts.anchorPoint
	end
	if opts.layoutOrder then
		bar.LayoutOrder = opts.layoutOrder
	end
	if opts.visible ~= nil then
		bar.Visible = opts.visible
	end
	applyShell(bar, Color.PanelWhite, radius, opts.thickness or 4)
	bar.ClipsDescendants = true
	bar.Parent = parent

	if opts.shadow ~= false then
		addShadow(bar, radius)
	end

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(opts.progress or 0, 0, 1, 0)
	fill.Position = UDim2.new(0, 0, 0, 0)
	fill.ZIndex = base + 1
	fill.BackgroundColor3 = opts.color or Color.Green
	fill.BorderSizePixel = 0
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = radius
	fillCorner.Parent = fill
	local fillGrad = Instance.new("UIGradient")
	fillGrad.Name = "Gradient"
	fillGrad.Rotation = 90
	fillGrad.Color = gradientFor(opts.color or Color.Green)
	fillGrad.Parent = fill
	fill:SetAttribute("BaseColor", opts.color or Color.Green)
	fill.Parent = bar

	if opts.gloss ~= false then
		local gloss = addGloss(bar, radius)
		gloss.ZIndex = base + 2 -- above the fill, still below the label
	end

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -12, 1, -6)
	label.Position = UDim2.new(0.5, 0, 0.5, 0)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Font = DisplayFont
	label.TextColor3 = Color.White
	label.Text = opts.text or ""
	label.ZIndex = base + Z.Content
	outlineText(label)
	autoSize(label, opts.minTextSize or 14, opts.maxTextSize or 22)
	label.Parent = bar

	return bar, fill, label
end

-- ============================================================================
-- PUBLIC: Badge
-- ============================================================================
function UITheme.Badge(parent, text, color)
	local base = (parent and parent:IsA("GuiObject") and parent.ZIndex) or Z.Shell
	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.Size = UDim2.new(0, 46, 0, 22)
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position = UDim2.new(1, 6, 0, -8)
	badge.ZIndex = base + Z.Badge
	applyShell(badge, color or Color.Red, UDim.new(0, 8), 3)
	badge.Parent = parent

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -6, 1, -4)
	label.Position = UDim2.new(0.5, 0, 0.5, 0)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Font = DisplayFont
	label.TextColor3 = Color.White
	label.Text = text or ""
	label.ZIndex = badge.ZIndex + Z.Content
	outlineText(label, 2)
	autoSize(label, 10, 15)
	label.Parent = badge

	return badge
end

-- ============================================================================
-- PUBLIC: SetColor / SetText
-- ============================================================================
function UITheme.SetColor(inst, color)
	if not inst or not color then
		return
	end
	-- An IconTile is two shells of the SAME colour (see IconTile: the outer one is the button, the
	-- inner one is the face). Both have to move together, or a recoloured tile shows the old hue in
	-- the one pixel of corner where the two roundings do not exactly coincide.
	local isTileBody = false
	local tileBody = inst:FindFirstChild("Body")
	if tileBody and tileBody:IsA("Frame") and tileBody:GetAttribute("BaseColor") then
		local shell = inst
		inst = tileBody
		isTileBody = true
		shell.BackgroundColor3 = color
		shell:SetAttribute("BaseColor", color)
		local shellGrad = shell:FindFirstChild("Gradient")
		if shellGrad and shellGrad:IsA("UIGradient") then
			shellGrad.Color = pastelGradientFor(color)
		end
	end
	inst.BackgroundColor3 = color
	local grad = inst:FindFirstChild("Gradient")
	if not grad or not grad:IsA("UIGradient") then
		grad = inst:FindFirstChildOfClass("UIGradient")
	end
	if grad then
		grad.Color = isTileBody and pastelGradientFor(color) or gradientFor(color)
	end
	local lip = inst:FindFirstChild("Shadow")
	if lip and lip:IsA("Frame") and lip:GetAttribute("IsLip") then
		lip.BackgroundColor3 = shade(color, -0.38) -- must match addShadow's lip; see the note there
	end
	inst:SetAttribute("BaseColor", color)
end

function UITheme.SetText(inst, text)
	if not inst then
		return
	end
	local host = inst:FindFirstChild("Body") or inst
	local label = host:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = text
		return
	end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		inst.Text = text
	end
end

return UITheme
