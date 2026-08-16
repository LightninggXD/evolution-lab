--[[
	UITheme - shared "chunky comic" design system for Evolution Lab.

	Every interactive surface = thick dark outline + rounded corners + vertical body
	gradient + hard drop shadow + faint glossy sheen + outlined display text.

	HARD INVARIANT (this is the bug that started the redesign):
		Gloss BackgroundTransparency >= 0.72 AND every text/content child renders at a
		strictly HIGHER ZIndex than the gloss.
		Layering: Shadow(-1) < Shell(0) < Gloss(+1) < Content(+3) < Badge(+5)
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundLibrary = require(script.Parent:WaitForChild("SoundLibrary"))
local IconLibrary = require(script.Parent:WaitForChild("IconLibrary"))

local UITheme = {}

-- ============================================================================
-- MICRO-INTERACTION TWEEN CONFIGURATIONS
-- ============================================================================
local HOVER_TWEEN_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local LEAVE_TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_DOWN_INFO  = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_UP_INFO    = TweenInfo.new(0.20, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PULSE_TWEEN_INFO = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out)


-- THE CLICK, IN THE ONE PLACE EVERY BUTTON ALREADY GOES THROUGH.
--
-- Every interactive surface in the game is a UITheme.Button or a UITheme.IconTile, so Phase 4.4 is
-- two lines here rather than a Play() beside a couple of hundred separate MouseButton1Click
-- connections -- and a button added next year gets its click without anyone remembering to ask.
--
-- Guarded on IsClient, and that guard is not defensive padding: this module is NOT client-only.
-- CreatureService and BossService both require it on the server for colours and label styling, and
-- a Sound created on the server REPLICATES -- so an unguarded click here would fire a button press
-- into every player's ears at once, from a server that never pressed anything.
local function clickSound()
	if RunService:IsClient() then
		SoundLibrary.PlayLocal("click")
	end
end

-- ============================================================================
-- PALETTE
-- ============================================================================
local Color = {
	Outline    = Color3.fromRGB(26, 18, 36),
	Shadow     = Color3.fromRGB(18, 12, 26),
	White      = Color3.fromRGB(255, 255, 255),
	Cream      = Color3.fromRGB(255, 248, 235),
	PanelWhite  = Color3.fromRGB(255, 255, 255),
	PanelBorder = Color3.fromRGB(0, 180, 255),
	PanelBlue   = Color3.fromRGB(80, 168, 245),
	Gold        = Color3.fromRGB(255, 198, 45),
	Orange      = Color3.fromRGB(250, 148, 38),
	Blue        = Color3.fromRGB(68, 162, 235),
	SkyBlue     = Color3.fromRGB(105, 205, 250),
	Green       = Color3.fromRGB(46, 204, 113),
	Red         = Color3.fromRGB(245, 68, 85),
	Purple      = Color3.fromRGB(165, 105, 245),
	Pink        = Color3.fromRGB(255, 105, 195),
	Grey        = Color3.fromRGB(150, 150, 165),
	Locked      = Color3.fromRGB(163, 161, 180),

	-- Bright pastel set -- used by the HUD tiles so the columns read as candy
	-- buttons rather than the darker panel chrome.
	Mint       = Color3.fromRGB(68, 225, 145),
	Sunny      = Color3.fromRGB(255, 212, 75),
	Bubblegum  = Color3.fromRGB(255, 130, 200),
	Lavender   = Color3.fromRGB(175, 138, 250),
	Aqua       = Color3.fromRGB(105, 205, 250),
	Peach      = Color3.fromRGB(255, 160, 95),
	Coral      = Color3.fromRGB(255, 95, 105),
}
UITheme.Color = Color

-- ============================================================================
-- Z ORDER CONTRACT
-- ============================================================================
local Z = {
	Shadow  = -1,
	Shell   = 0,
	Body    = 1,
	Gloss   = 2,
	Content = 4,
	Badge   = 6,
	Overlay = 8,
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
		ColorSequenceKeypoint.new(0.00, shade(c, 0.4)),
		ColorSequenceKeypoint.new(0.35, shade(c, 0.05)),
		ColorSequenceKeypoint.new(1.00, shade(c, -0.1)),
	})
end

-- There used to be a second, softer curve here for the HUD tiles, because the main one was too
-- dark for them. Now that gradientFor IS the soft curve, keeping two would mean two subtly
-- different button looks in one screen -- which is exactly what "every button identical" rules
-- out. Kept as a name so the four call sites that ask for it still read as intentional.
local pastelGradientFor = gradientFor

-- ============================================================================
-- THE SHAPE SCALE (10.18)
-- ============================================================================
-- Measured on the live HUD before this existed: **ten distinct corner radii** and **eight stroke
-- widths**. Not ten deliberate shapes -- 14, 16, 12, 20, 10 and 22 px alongside two scale-based
-- pills, each one whatever the person writing that panel happened to type. A radius is the main
-- thing that says what KIND of object you are looking at, so ten of them says nothing at all: the
-- eye cannot learn a vocabulary with ten words that differ by two pixels.
--
-- Four steps, named for what they are FOR rather than how big they are:
--
--   Pill  a capsule -- progress bars, currency capsules, anything read as a single value
--   Tile  the big pressable things: HUD tiles, action buttons
--   Card  a surface that holds content: panels, rows, list cells
--   Chip  small inline marks: badges, counters, tags
--
-- SNAPPED RATHER THAN ENFORCED. Three hundred call sites pass their own number and rewriting them
-- all would be a very large diff for a two-pixel change, with a real chance of breaking a layout
-- that depends on its radius. Instead every radius entering the theme is rounded to the nearest
-- step, so the vocabulary becomes true without a single call site changing. A caller that wants
-- 14 gets Card's 16 and looks the same; the HUD as a whole gains a system.
UITheme.Radius = {
	Pill = UDim.new(1, 0),
	Tile = UDim.new(0, 20),
	Card = UDim.new(0, 16),
	Chip = UDim.new(0, 10),
}

local RADIUS_STEPS = { 10, 16, 20 }

-- The same argument for the outline. Measured: **eight distinct stroke widths** -- 4, 3, 5, 0, 3.5,
-- 2, 2.5 and 6. The border is the loudest thing about this style, so half-pixel differences in it
-- are not subtlety, they are noise. Three weights, and zero stays zero because "no outline at all"
-- is a real choice rather than a thin one.
--
--   Heavy  panels and anything that frames other content
--   Base   buttons, cards, tiles -- the overwhelming majority
--   Fine   small inline marks where Base would swallow the fill
UITheme.Stroke = { Heavy = 5, Base = 4, Fine = 3 }

local STROKE_STEPS = { 3, 4, 5 }

local function snapStroke(t)
	if type(t) ~= "number" or t <= 0 then
		return t
	end
	local best, bestD = STROKE_STEPS[1], math.huge
	for _, step in ipairs(STROKE_STEPS) do
		local d = math.abs(t - step)
		if d < bestD then best, bestD = step, d end
	end
	return best
end
UITheme.SnapStroke = snapStroke

local function snapRadius(u)
	-- a scale-based radius is already a pill and has no pixel value to snap
	if u.Scale > 0 then
		return u
	end
	local px = u.Offset
	if px <= 0 then
		return u
	end
	local best, bestD = RADIUS_STEPS[1], math.huge
	for _, step in ipairs(RADIUS_STEPS) do
		local d = math.abs(px - step)
		if d < bestD then best, bestD = step, d end
	end
	-- anything far above the scale is a deliberate large shape (a panel corner) and is left alone;
	-- snapping a 40 px panel down to 20 would be the system overriding a real decision.
	if px > RADIUS_STEPS[#RADIUS_STEPS] + 6 then
		return u
	end
	return UDim.new(0, best)
end
UITheme.SnapRadius = snapRadius

local function toUDim(radius, default)
	if typeof(radius) == "UDim" then
		return snapRadius(radius)
	end
	if type(radius) == "number" then
		return snapRadius(UDim.new(0, radius))
	end
	return default or UITheme.Radius.Card
end

local LIP_DEPTH = 6

-- Thick dark outline + rounded corners + moulded vertical gradient.
local function applyShell(inst, color, radius, thickness)
	local cornerRadius = toUDim(radius)
	
	inst.BackgroundTransparency = 1
	inst.BorderSizePixel = 0

	local oldCorner = inst:FindFirstChild("UICorner")
	if oldCorner then oldCorner:Destroy() end
	local oldStroke = inst:FindFirstChild("UIStroke")
	if oldStroke then oldStroke:Destroy() end

	local strokeT = snapStroke(thickness or UITheme.Stroke.Heavy)

	local shadowBody = inst:FindFirstChild("ShadowBody") or Instance.new("Frame")
	shadowBody.Name = "ShadowBody"
	shadowBody.Size = UDim2.new(1, 0, 1, 0)
	shadowBody.Position = UDim2.new(0, 0, 0, LIP_DEPTH)
	shadowBody.BackgroundColor3 = shade(color, -0.4)
	shadowBody.BackgroundTransparency = 0
	shadowBody.BorderSizePixel = 0
	shadowBody.ZIndex = inst.ZIndex + Z.Shell
	
	local shadowCorner = shadowBody:FindFirstChild("UICorner") or Instance.new("UICorner")
	shadowCorner.Name = "UICorner"
	shadowCorner.CornerRadius = cornerRadius
	shadowCorner.Parent = shadowBody

	local shadowStroke = shadowBody:FindFirstChild("UIStroke") or Instance.new("UIStroke")
	shadowStroke.Name = "UIStroke"
	shadowStroke.Thickness = strokeT
	shadowStroke.Color = Color.Outline
	shadowStroke.Transparency = 0
	shadowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	shadowStroke.LineJoinMode = Enum.LineJoinMode.Round
	shadowStroke.Parent = shadowBody
	shadowBody.Parent = inst

	local body = inst:FindFirstChild("InnerBody") or Instance.new("Frame")
	body.Name = "InnerBody"
	body.Size = UDim2.new(1, 0, 1, 0)
	body.Position = UDim2.new(0, 0, 0, 0)
	body.BackgroundColor3 = color
	body.BackgroundTransparency = 0
	body.BorderSizePixel = 0
	body.ClipsDescendants = true
	body.ZIndex = inst.ZIndex + Z.Body
	
	local bodyCorner = body:FindFirstChild("UICorner") or Instance.new("UICorner")
	bodyCorner.Name = "UICorner"
	bodyCorner.CornerRadius = cornerRadius
	bodyCorner.Parent = body

	local bodyStroke = body:FindFirstChild("UIStroke") or Instance.new("UIStroke")
	bodyStroke.Name = "UIStroke"
	bodyStroke.Thickness = strokeT
	bodyStroke.Color = Color.Outline
	bodyStroke.Transparency = 0
	bodyStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bodyStroke.LineJoinMode = Enum.LineJoinMode.Round
	bodyStroke.Parent = body
	body.Parent = inst

	local grad = body:FindFirstChild("Gradient") or Instance.new("UIGradient")
	grad.Name = "Gradient"
	grad.Rotation = 90
	grad.Color = gradientFor(color)
	grad.Parent = body

	inst:SetAttribute("BaseColor", color)
	return bodyCorner, bodyStroke, grad
end

--[[
	THE DROP SHADOW IS GONE, ON PURPOSE (2026-08-11 play-test feedback).

	It had two variants and both drew outside the shell they belonged to:

	  * the SIBLING variant was a full-size opaque `Color.Shadow` rectangle parented next to the
	    button and offset 5px down. On a rounded shell that leaves a hard dark crescent poking out
	    of the bottom corners, and on the HUD tiles it is the "ugly line at the bottom of the
	    button that even sticks out" in the report. It also never shrank with the press: the squash
	    is a UIScale on the BUTTON, and the shadow is not a child of the button, so pressing made
	    the button smaller and left the shadow at full size popping out around it.
	  * the LIP variant was a full-width 6px bar anchored at the bottom carrying the shell's FULL
	    corner radius. A bar as wide as the shell, at a height where the shell has already curved
	    inwards, is wider than the shell is there -- so it stuck out of both bottom corners, and on
	    a circular shell (the Journal discs) it stuck out badly.

	Nothing replaces them. The moulded depth now comes entirely from the shell's own vertical
	gradient (see `gradientFor`: bright top, -0.28 bottom) plus the heavy dark outline, which is
	what actually carries the sticker look -- and neither of those can cross an edge, because they
	ARE the edge. Press feedback is the UIScale squash in `styleButton`, which was always the thing
	doing the visible work.

	Kept as a function with its old signature so the four call sites and their `opts.shadow ~= false`
	guards keep working. Returns: nil, no-op pressFn.
]]
local function addShadow(_inst, _radius)
	return nil, function() end
end

-- Faint top sheen. NEVER opaque, NEVER above content, and since 2026-08-11 never outside the
-- shell either.
--
-- ===== WHY IT USED TO STICK OUT, AND WHY IT CANNOT NOW =====
--
-- The old geometry was a fixed 0.88 x 0.4 box at (0.06, 0.06) with its corner radius HARDCODED to
-- `UDim.new(1, 0)` -- the function took a `radius` argument and ignored it. `ClipsDescendants` is
-- deliberately false on themed surfaces (badges are meant to hang outside an IconTile), so nothing
-- caught the overflow: on a low-radius button the pill's ends bulged past the shell's corners, and
-- on a CIRCULAR shell a rectangle inset only 6% from the bounding box has its top corners outside
-- the circle entirely. That is half of "the buttons look cut off at the sides".
--
-- The fix is geometric rather than a clip, so it holds at every size and needs no extra instance.
-- The sheen is inset by the shell's OWN corner radius, which is exactly where the shell's straight
-- top edge begins -- so a box inset by `r` (plus a little) spans only the part of the shell that is
-- flat, and cannot reach a curve. Two cases, because the two radius kinds mean different things:
--
--   * ROUND (Scale >= 0.5 -- a circle or a pill): inset to the middle 56% and start 10% down. A
--     circle's half-width at 10% of its height is 0.30 of its diameter, i.e. a 0.60 span, so a 0.56
--     span centred on it clears the rim with room at the tightest point and more everywhere below.
--   * RECTANGULAR: inset `r + 4` on each side and 5px from the top, with its own corner radius one
--     step under the shell's.
--
-- Transparency floor RAISED 0.72 -> 0.78. 0.72 is still the documented invariant and this respects
-- it; the sheen was reading as a white pill painted on the button rather than as light falling on
-- it, which is the other half of the complaint. It must never go BELOW 0.72 -- that number is a
-- contract, not a preference: any stronger and it starts washing out the white label under it.
local function addGloss(inst, radius)
	local cornerRadius = toUDim(radius)
	local round = cornerRadius.Scale >= 0.5

	local body = inst:FindFirstChild("InnerBody")
	
	local gloss = inst:FindFirstChild("Gloss") or Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.BackgroundColor3 = Color.White
	gloss.BackgroundTransparency = 0.72 -- invariant: >= 0.72
	gloss.BorderSizePixel = 0
	gloss.ZIndex = inst.ZIndex + Z.Gloss

	local corner = gloss:FindFirstChild("UICorner")
	if corner then corner:Destroy() end

	gloss.AnchorPoint = Vector2.new(0, 0)
	gloss.Position = UDim2.new(0, 0, 0, 0)
	
	if round then
		gloss.Size = UDim2.new(1, 0, 0.40, 0)
	else
		gloss.Size = UDim2.new(1, 0, 0.35, 0)
	end

	local grad = gloss:FindFirstChild("UIGradient") or Instance.new("UIGradient")
	grad.Name = "UIGradient"
	grad.Rotation = 90
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(0.7, 0.85),
		NumberSequenceKeypoint.new(1, 1),
	})
	grad.Parent = gloss

	gloss.Parent = body or inst
	return gloss
end

-- The single most recognisable feature of the reference art. 4px to match the thicker shell
-- border above -- a heavy button frame around a thinly outlined word reads as two different
-- drawings sharing a rectangle.
-- DARK INK AND ITS HALO ARE ONE DECISION, AND THIS IS WHERE THE THRESHOLD LIVES (15.15).
--
-- `outlineText` always draws in `Color.Outline`, rgb(26,18,36). That is right for the white-on-
-- colour text this HUD is mostly made of and it is a solid blob around anything dark: the glyph and
-- its halo are then the same colour, and every property reads correct while it happens (`Text`,
-- `TextColor3`, `TextFits`), so it survives any probe and is only visible in a capture.
--
-- Phase 15.1 fixed this once, in `MainUI`'s own `themeLabel`, and the codebase then had the rule in
-- one of the two constructors that apply a halo. `UITheme.Label` is the other one, and the Group &
-- Community panel -- three card titles at ink 0.14 and three descriptions at 0.36, each inside a
-- 4px stroke at 0.09 -- is what that cost. The threshold belongs to a PALETTE rather than to a
-- file, so it is published here and both constructors read it instead of each carrying a copy.
--
-- 0.45 because this palette's dark ink sits at 0.077 and its greys at 0.48-0.60.
local function isDarkInk(color)
	return (0.299 * color.R + 0.587 * color.G + 0.114 * color.B) < 0.45
end

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
-- ⚠ `TextScaled = true` TURNS `TextWrapped` ON, and it does it silently. Measured on a live client
-- (15.16): a fresh TextLabel reads `TextWrapped = false`, setting `TextScaled = true` makes it read
-- **true**, and only an assignment placed AFTER that one sticks. So any caller that turns wrapping
-- off and then reaches a helper that scales has had its decision reversed one line later, with
-- every property still reading correct.
--
-- That is not hypothetical: the potion rows in `MainUI` carry a ten-line comment explaining that
-- their sub-label must never stack two lines into a 22px box, set `TextWrapped = false`, and then
-- called `themeLabel` -- which lands here. The three Luck bottles and the large Health bottle wrap
-- to 28px inside 22 and have their second line cut. `UITheme.Label`'s own `wrapped` option was
-- inert for the same reason, being applied before this call rather than after it.
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
UITheme.IsDarkInk = isDarkInk

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

-- ============================================================================
-- ICONS (ROADMAP 9.9)
-- ============================================================================
--
-- FOUR CALL SITES DECIDE WHAT AN ICON IS in this whole game -- Button, Card, IconTile and Pill --
-- which is why 9.9 is one abstraction rather than a hundred and fifty edits. Every one of them
-- routes through the two helpers below.
--
-- The contract is that an icon is DRAWN IF WE HAVE ONE and rendered as its emoji if we do not, so
-- nothing can ever come out as an empty square. See the IconLibrary header for why the lookup key
-- is the emoji itself.
--
-- `Image` is a property of TextLabel too, but a TextLabel cannot show one -- so an icon slot is an
-- ImageLabel when there is art and a TextLabel when there is not, and `iconSlot` hands back
-- whichever it built. Callers only ever set position and size on it, never `.Text`.

-- Rendered a shade darker than the plate so a white icon on a pale tile still has a body. Not a
-- UIStroke: an ImageLabel's stroke traces the IMAGE BOX, not the drawing inside it, so it would
-- put a rectangle round every icon. The PNGs carry their own contour instead (see make_icons.py).
local function iconSlot(parent, emoji, zIndex, minText, maxText)
	local asset = IconLibrary.Resolve(emoji)
	if asset then
		local img = Instance.new("ImageLabel")
		img.Name = "Icon"
		img.BackgroundTransparency = 1
		img.Image = asset
		img.ScaleType = Enum.ScaleType.Fit -- never distort: the art is square and the slot may not be
		img.ZIndex = zIndex
		img.Parent = parent

		-- ===== THE SAME-HUE PROBLEM, SOLVED ONCE INSTEAD OF PER TILE =====
		--
		-- Every icon carries its own dark contour, which is enough on a tile of a different colour
		-- and is NOT enough when the two match: the gold shard on the gold Day 7 card came out as a
		-- pale ghost, which is exactly the mistake 6.4 made with gold chips on a gold card. Tinting
		-- an icon to fit its background would mean 44 icons x every tile colour they can land on.
		--
		-- A drop shadow fixes all of it with one instance and no knowledge of either colour: the
		-- SAME image, tinted flat to the outline colour and offset down-right behind the real one.
		-- Because it is the same PNG it is exactly the icon's silhouette, so the icon reads as a
		-- solid object sitting ON the tile whatever the tile happens to be -- which is also the
		-- hard-shadow rule every other surface in this kit already follows.
		-- ...UNLESS THE PARENT IS RUNNING A LAYOUT. A UIListLayout or UIGridLayout gives every child
		-- a cell, so a shadow sibling would not sit behind the icon -- it would be handed the NEXT
		-- CELL and push everything after it along. That is the currency pills (icon then value in a
		-- horizontal list), and they sit on the dark HUD backdrop where the contour is already
		-- enough. Detected rather than passed in, so a layout added to some parent later cannot
		-- quietly break its row.
		local laidOut = parent:FindFirstChildWhichIsA("UIListLayout")
			or parent:FindFirstChildWhichIsA("UIGridLayout")
			or parent:FindFirstChildWhichIsA("UIPageLayout")
			or parent:FindFirstChildWhichIsA("UITableLayout")
		if laidOut then
			return img, true
		end

		-- A SIBLING, NOT A CHILD, and that is forced rather than chosen: this ScreenGui runs
		-- `ZIndexBehavior.Sibling`, under which a child ALWAYS draws above its parent whatever its
		-- ZIndex -- so a shadow parented to the icon would cover the icon it is shadowing. As a
		-- sibling one ZIndex lower it lands where it belongs, at the cost of having to mirror the
		-- layout the caller sets afterwards.
		local shade = Instance.new("ImageLabel")
		shade.Name = "IconShadow"
		shade.BackgroundTransparency = 1
		shade.Image = asset
		shade.ScaleType = Enum.ScaleType.Fit
		shade.ImageColor3 = Color.Outline
		shade.ImageTransparency = 0.55
		shade.ZIndex = zIndex - 1
		shade.Parent = parent

		-- Every caller sets Size/Position on the slot AFTER it is handed back, so the mirror is a
		-- subscription rather than a copy. The offset is in SCALE, so it stays proportional as the
		-- responsive pass drives a tile from 82 px down toward its 40 px floor.
		local function mirror()
			shade.Size = img.Size
			shade.SizeConstraint = img.SizeConstraint
			shade.AnchorPoint = img.AnchorPoint
			shade.LayoutOrder = img.LayoutOrder
			shade.Visible = img.Visible
			shade.Image = img.Image -- SetIcon can swap the drawing; the shadow has to follow it
			shade.Position = img.Position + UDim2.new(0.05, 0, 0.055, 0)
		end
		for _, prop in ipairs({ "Size", "Position", "AnchorPoint", "SizeConstraint", "LayoutOrder", "Visible", "Image" }) do
			img:GetPropertyChangedSignal(prop):Connect(mirror)
		end
		mirror()

		return img, true
	end

	local label = Instance.new("TextLabel")
	label.Name = "Icon"
	label.BackgroundTransparency = 1
	label.Font = DisplayFont
	label.TextColor3 = Color.White
	label.Text = emoji or ""
	label.ZIndex = zIndex
	outlineText(label)
	autoSize(label, minText or 16, maxText or 34)
	label.Parent = parent
	return label, false
end

-- PUBLIC, because the four kit surfaces are not the only places an icon appears. Panel CONTENT --
-- the 17 shop cards, the 9 pass rows, the potion bottles, the boost chips -- is built directly out
-- of Instance.new in MainUI rather than through Button/Card/IconTile/Pill, so those sites need the
-- same either-kind slot without being rewritten into kit components.
--
-- It lives here rather than in MainUI on purpose: MainUI is at Luau's 200-local register cap (see
-- its own header), and a helper declared there would cost one of the last registers. Declared here
-- it costs none -- MainUI already holds a reference to this module.
function UITheme.IconSlot(parent, opts)
	opts = opts or {}
	local slot = iconSlot(parent, opts.icon or "", opts.zIndex or Z.Content,
		opts.minTextSize or 16, opts.maxTextSize or 34)
	if opts.size then
		slot.Size = opts.size
	end
	if opts.position then
		slot.Position = opts.position
	end
	if opts.anchorPoint then
		slot.AnchorPoint = opts.anchorPoint
	end
	if opts.layoutOrder then
		slot.LayoutOrder = opts.layoutOrder
	end
	if opts.name then
		slot.Name = opts.name
	end
	return slot
end

-- Turns an EXISTING left-aligned label whose text begins with a mapped emoji into an icon plus
-- text: the glyph is stripped, a drawing is placed at the label's left edge, and the label is
-- inset to clear it. Returns true when it did something.
--
-- This shape exists for the panel HEADERS, which are a dozen plain TextLabels built individually
-- and positioned by hand across MainUI ("\u{1F4C5} Daily Rewards!", "\u{1F6CD}\u{FE0F} Robux
-- Shop"). Rewriting each into a kit component would move every panel's title by a few pixels and
-- risk the layout of twelve screens; adjusting one that is already correct costs one line and
-- moves nothing but the glyph.
--
-- LEFT-ALIGNED ONLY, and it refuses rather than guessing otherwise: a centred title has no fixed
-- left edge to hang an icon off -- the text starts wherever its own width puts it -- so an icon
-- placed at the frame's left would float away from the words it belongs to.
function UITheme.IconifyLabel(label, gap)
	if not label or not label:IsA("TextLabel") then
		return false
	end
	if label.TextXAlignment ~= Enum.TextXAlignment.Left then
		return false
	end
	local asset = IconLibrary.Resolve(label.Text)
	if not asset then
		return false
	end
	local stripped = IconLibrary.StripLeading(label.Text)
	if stripped == label.Text then
		return false
	end

	gap = gap or 6
	-- CAPTURED BEFORE ANYTHING MOVES, and this is the whole trick. The icon goes where the label
	-- USED to start; the label then steps right to clear it. A resize handler that re-read
	-- `label.Position` would read the position after that step and walk the icon onto the words --
	-- which is exactly what the first version did, and what a screen capture caught: the panel
	-- title rendered as "[icon]ily Rewards!" with the "Da" underneath the drawing.
	local basePos = label.Position
	local baseSize = label.Size

	local img = iconSlot(label.Parent, label.Text, label.ZIndex)
	img.Name = "TitleIcon"
	img.AnchorPoint = label.AnchorPoint

	local function fit()
		-- square, off the label's rendered height -- a title box is 28..44 px depending on the panel
		local d = label.AbsoluteSize.Y
		if d < 4 then return end
		img.Size = UDim2.new(0, d, 0, d)
		img.Position = basePos
		-- The label keeps its own anchor and simply starts further along. Offset only -- a scale
		-- term here would make the inset depend on the parent's width, which an icon's width is not.
		label.Position = basePos + UDim2.new(0, d + gap, 0, 0)
		label.Size = baseSize - UDim2.new(0, d + gap, 0, 0)
	end
	label:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

	label.Text = stripped
	fit()
	return true
end

-- Re-exported so a call site that has to branch on "is there art for this" does not have to
-- require IconLibrary itself. That matters for exactly one caller and it is the important one:
-- MainUI is at the 200-local register cap, and a second `local X = require(...)` there costs a
-- register this phase has promised not to spend.
function UITheme.HasIcon(emoji)
	return IconLibrary.Has(emoji)
end

-- ============================================================================
-- PUBLIC: NotifyRank - how much a toast is worth keeping (11.15)
-- ============================================================================
--
-- The toast stack holds four. Everything past that is destroyed, and until now the victim was
-- simply the OLDEST -- which during a fight means the newest four are all `crit` and `diamond`,
-- because those fire several times a second while a NEW ZONE UNLOCKED fires once in an hour. The
-- one message a player cannot afford to miss was reliably the one thrown away.
--
-- Ranked by WHAT IS LOST IF IT SCROLLS PAST, not by how exciting the event is:
--
--   3  An answer to something the player just pressed. A refusal is the only message whose absence
--      is itself a bug report -- "I clicked and nothing happened" is what an evicted error looks
--      like from the outside. Never dropped.
--   2  One-off progress, and anything that was paid for. A zone unlock, an evolve, a rebirth, a
--      Robux purchase, a daily claim: none of these will be said again.
--   1  The default, and what an unlisted kind gets. Repeatable but deliberate -- an upgrade
--      bought, a potion drunk.
--   0  Combat chatter. `crit` and `diamond` are the two kinds that fire on a timer rather than on
--      a decision, and they are the reason this table exists at all.
--
-- Keyed by notify `kind`, the same key `SoundLibrary.NOTIFY_SOUND` uses, so a new kind is a row in
-- two tables rather than an edit inside MainUI's twenty-branch handler. It lives here rather than
-- there for the register reason every shared table in this file cites.
local NOTIFY_RANK = {
	error = 3,
	zone = 2,          evolve = 2,          character = 2,       rebirth = 2,
	bossDefeated = 2,  robuxPurchase = 2,   dailyReward = 2,     playtimeGift = 2,
	offline = 2,       reward = 2,          questComplete = 2,   stageMastery = 2,
	fuse = 2,          spin = 2,            bossRevive = 2,
	upgrade = 1,       diamondUpgrade = 1,  potion = 1,
	crit = 0,          diamond = 0,
}

function UITheme.NotifyRank(kind)
	return NOTIFY_RANK[kind] or 1
end

-- ============================================================================
-- PUBLIC: FormatNumber -- 1.23M, and the carry that is easy to get wrong
-- ============================================================================
-- ⚠️ MainUI HAS AN IDENTICAL LOCAL COPY OF THIS (`formatNumber`, near the top of that file) AND
-- CANNOT DELEGATE TO IT. That copy is written ABOVE MainUI's `require` of this module, and Lua
-- binds an upvalue where a function is WRITTEN -- so a body calling `UITheme.FormatNumber` there
-- would resolve `UITheme` as a nil global and error on the first number the HUD prints. It is the
-- same trap the comment beside MainUI's `corner` describes. **Change one, change the other**:
-- moving MainUI's declaration below its require is the fix and is a row of its own, not a
-- side-effect of whatever is being built today.
--
-- The threshold is 999.995 rather than 999.95 because this prints TWO decimals: 999,999 divides
-- once to 999.999, which is under the loop's own test and so is accepted, and "%.2f" then renders
-- it "1000.00K" -- a number one short of a million printed as a thousand thousand. The constant
-- has to match the precision beside it.
function UITheme.FormatNumber(n)
	n = math.floor(n)
	if n < 1000 then return tostring(n) end
	local suffixes = { "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp" }
	local mag = 0
	while n >= 1000 and mag < #suffixes do
		n = n / 1000
		mag += 1
	end
	if n >= 999.995 and mag < #suffixes then
		n = n / 1000
		mag += 1
	end
	return string.format("%.2f%s", n, suffixes[mag])
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

	-- ===== THE SAME SIX PIXELS MainUI's `styleButton` TAKES OFF (11.3) =====
	--
	-- Two builders make every button in this game and a shrink applied to only one of them is a
	-- HUD where half the buttons are 44 tall and half are 50 -- which is worse than leaving both
	-- alone. The rule is identical and deliberately narrow: the two authored action-button heights
	-- (50 primary, 46 secondary) become 44 and 40, and nothing else is touched, because everything
	-- else built through here -- a 42 close button, a 68 HUD tile, a 60+ Robux card -- is sized
	-- against its own grid rather than against "an action button".
	--
	-- AFTER buildSurface, not inside it: Card, IconTile and Modal all go through that function and
	-- none of them is an action button. Doing it there would resize the tile columns.
	if button.Size.Y.Scale == 0 then
		local h = button.Size.Y.Offset
		if h == 50 or h == 46 then
			button.Size = UDim2.new(button.Size.X.Scale, button.Size.X.Offset, 0, h == 50 and 44 or 40)
		end
	end

	local text = opts.text or ""
	-- ICON AND TEXT ARE STILL ONE LABEL WHEN THERE IS NO ART FOR THE ICON, and that is deliberate:
	-- a button's text is centred, so splitting the row unconditionally would move every existing
	-- caption a few pixels right for the ~90 emojis this game will never draw. When there IS art,
	-- the glyph comes out of the string and a square ImageLabel takes the left end of the button.
	local iconAsset = (opts.icon and opts.icon ~= "") and IconLibrary.Resolve(opts.icon) or nil
	if opts.icon and opts.icon ~= "" and not iconAsset then
		text = opts.icon .. " " .. text
	end
	-- MOST BUTTONS IN THIS GAME PUT THE EMOJI IN THE TEXT, not in `icon` -- "\u{1F3A1} FREE SPIN",
	-- "\u{2694}\u{FE0F} REVIVE". Those are the same thing written a different way, so a LEADING
	-- mapped glyph is promoted to the icon slot and stripped from the string. Only leading: a
	-- trailing glyph is part of a sentence ("SPIN 25\u{1F31F}" is a price) and has no slot to go to.
	if not iconAsset then
		iconAsset = IconLibrary.Resolve(text)
		if iconAsset then
			text = IconLibrary.StripLeading(text)
		end
	end
	local label = buildLabelChild(button, opts, base, text, 26)

	if iconAsset then
		local img = iconSlot(button, opts.icon or opts.text, base + Z.Content)
		-- Sized off the button's own height, so one rule covers a 42px shop row and a 68px HUD
		-- button. 0.62 leaves the icon visually the same weight as the cap height beside it.
		--
		-- BOTH SCALES ARE 0.62, and that is what RelativeYY means: it makes the X scale relative to
		-- the parent's HEIGHT as well, which is the whole point (a square, whatever the aspect of
		-- the button). Writing the X term as 0 -- the obvious way to say "take the height and let
		-- the constraint work it out" -- gives a slot 0 pixels wide, and an ImageLabel that is
		-- loaded, positioned, correct in every structural probe, and invisible on screen.
		img.Size = UDim2.new(0.62, 0, 0.62, 0)
		img.SizeConstraint = Enum.SizeConstraint.RelativeYY
		img.Position = UDim2.new(0, 10, 0.5, 0)
		img.AnchorPoint = Vector2.new(0, 0.5)
		-- and the text gives up exactly the room the icon took, on BOTH sides -- a label inset only
		-- on the left is still centred on the whole button, so its text would sit under the icon
		label.Size = UDim2.new(1, -16 - 2 * (label.AbsoluteSize.Y * 0.62 + 10), 1, -12)
		-- AbsoluteSize is 0 for a frame that has not been laid out yet, which is every frame on the
		-- first pass. Bind the real measurement to the button's own resize instead of guessing.
		local function fit()
			local d = button.AbsoluteSize.Y * 0.62 + 10
			-- ...AND THE RESERVATION IS CAPPED, BECAUSE IT IS COMPUTED FROM THE HEIGHT (15.17).
			--
			-- `d` is the icon's own width plus its margin, taken off BOTH sides so the text stays
			-- centred on the button rather than centred under the icon. On a wide button that is
			-- free. On a SHORT, TALL one it is most of the button: the Group & Community cards
			-- carry a 115 x 42 action button, where d is 36 and the label was left **27px** -- too
			-- narrow for any word in the language, so "Claim" rendered as "Clai" over "m" and
			-- "Claim Chest" lost its second line entirely. Every property read correct
			-- (`TextFits` was **true**, because two 14px lines do fit a 30px box); only the capture
			-- showed it.
			--
			-- The floor is 55% of the button. Below that the inset gives way instead of the words:
			-- the text may then sit a little closer to the icon than the symmetric rule wanted,
			-- which is a cosmetic loss where the alternative is an unreadable button.
			local w = button.AbsoluteSize.X
			local floor = w * 0.55
			if w - 16 - 2 * d < floor then
				d = math.max(0, (w - 16 - floor) / 2)
			end
			label.Size = UDim2.new(1, -16 - 2 * d, 1, -12)
		end
		button:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		fit()
	end

	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Scale = 1
	scale.Parent = button

	-- press and hover feedback
	local pressed = false
	local hovered = false
	local restPos = button.Position
	local function down()
		if pressed then
			return
		end
		pressed = true
		restPos = button.Position
		button.Position = restPos + UDim2.new(0, 0, 0, 2)
		press(true)
		if RunService:IsClient() then
			TweenService:Create(scale, PRESS_DOWN_INFO, { Scale = 0.94 }):Play()
		end
		-- on DOWN, with the sink, not on the click release: the sound is feedback for the press and
		-- has to land on the same frame the button visibly moves
		clickSound()
	end
	local function up()
		if not pressed then
			return
		end
		pressed = false
		button.Position = restPos
		press(false)
		if RunService:IsClient() then
			local targetScale = hovered and 1.04 or 1.0
			TweenService:Create(scale, PRESS_UP_INFO, { Scale = targetScale }):Play()
		end
	end
	local function enter()
		hovered = true
		if not pressed and RunService:IsClient() and button.Active and button.Selectable ~= false then
			TweenService:Create(scale, HOVER_TWEEN_INFO, { Scale = 1.04 }):Play()
		end
	end
	local function leave()
		hovered = false
		if pressed then
			up()
		end
		if RunService:IsClient() then
			TweenService:Create(scale, LEAVE_TWEEN_INFO, { Scale = 1.0 }):Play()
		end
	end
	button.MouseButton1Down:Connect(down)
	button.MouseButton1Up:Connect(up)
	button.MouseEnter:Connect(enter)
	button.MouseLeave:Connect(leave)

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
		-- same split as Button, and the same reason it is conditional -- see the note there
		local iconAsset = (opts.icon and opts.icon ~= "") and IconLibrary.Resolve(opts.icon) or nil
		if opts.icon and opts.icon ~= "" and not iconAsset then
			text = opts.icon .. " " .. text
		end
		local label = buildLabelChild(card, opts, base, text, 26)
		if iconAsset then
			local img = iconSlot(card, opts.icon, base + Z.Content)
			-- both scales 0.62 -- see the note in Button
			img.Size = UDim2.new(0.62, 0, 0.62, 0)
			img.SizeConstraint = Enum.SizeConstraint.RelativeYY
			img.Position = UDim2.new(0, 10, 0.5, 0)
			img.AnchorPoint = Vector2.new(0, 0.5)
			local function fit()
				local d = card.AbsoluteSize.Y * 0.62 + 10
				label.Size = UDim2.new(1, -16 - 2 * d, 1, -12)
			end
			card:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
			fit()
		end
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

	-- KEPT AS "Label", whichever kind it turns out to be. Six places outside this module reach into
	-- a tile by that name (the responsive pass, refreshAutoTile, the potion strip and others), and
	-- renaming it because the class changed would break all of them silently -- a FindFirstChild
	-- that misses returns nil, and every one of those call sites is nil-guarded.
	local icon, isImage = iconSlot(body, opts.icon or opts.text or "", body.ZIndex + Z.Content,
		20, opts.maxTextSize or 38)
	icon.Name = "Label"
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
	-- A DRAWN ICON GETS A SQUARE SLOT, and this is the one place it matters most. `ScaleType.Fit`
	-- keeps the art's aspect inside whatever box it is given, so a 1.0-wide by 0.54-high slot draws
	-- the icon at 54% of the tile height and leaves the rest as empty margin -- correct, but small.
	-- Constraining the WIDTH to the height instead gives the drawing the whole band it was allotted.
	-- A TextLabel needs the opposite (its glyph is already centred in a wide box), so this only
	-- applies to the image case.
	if isImage and hasCaption then
		-- both scales 0.60 -- see the note in Button about what RelativeYY does to the X term
		icon.Size = UDim2.new(0.60, 0, 0.60, 0)
		icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
	end

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

	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Scale = 1
	scale.Parent = tile

	local pressed = false
	local hovered = false
	local restPos = tile.Position
	local function down()
		if pressed then
			return
		end
		pressed = true
		restPos = tile.Position
		tile.Position = restPos + UDim2.new(0, 0, 0, 3)
		press(true)
		if RunService:IsClient() then
			TweenService:Create(scale, PRESS_DOWN_INFO, { Scale = 0.92 }):Play()
		end
		clickSound()
	end
	local function up()
		if not pressed then
			return
		end
		pressed = false
		tile.Position = restPos
		press(false)
		if RunService:IsClient() then
			local targetScale = hovered and 1.06 or 1.0
			TweenService:Create(scale, PRESS_UP_INFO, { Scale = targetScale }):Play()
		end
	end
	local function enter()
		hovered = true
		if not pressed and RunService:IsClient() and tile.Active and tile.Selectable ~= false then
			TweenService:Create(scale, HOVER_TWEEN_INFO, { Scale = 1.06 }):Play()
		end
	end
	local function leave()
		hovered = false
		if pressed then
			up()
		end
		if RunService:IsClient() then
			TweenService:Create(scale, LEAVE_TWEEN_INFO, { Scale = 1.0 }):Play()
		end
	end
	tile.MouseButton1Down:Connect(down)
	tile.MouseButton1Up:Connect(up)
	tile.MouseEnter:Connect(enter)
	tile.MouseLeave:Connect(leave)

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

	-- The colour is set above, so the decision can be made here rather than guessed at. A caller
	-- that asked for a thickness on dark ink still loses it: `strokeThickness` says how thick the
	-- halo should be, never that a blob is wanted.
	outlineText(label, isDarkInk(label.TextColor3) and 0 or opts.strokeThickness)
	autoSize(label, opts.minTextSize or 14, opts.maxTextSize or opts.textSize or 30)
	-- AFTER `autoSize`, because that is the only position where it survives -- see the note over it.
	-- Only an EXPLICIT `wrapped = false` is honoured: `TextScaled` has been turning wrapping on for
	-- all 23 call sites since this constructor was written, three of which ask for it by name and
	-- none of which asks for it off, so defaulting to "off" here would silently unwrap twenty
	-- labels that are laid out around wrapping today. The option is now real without being a change.
	if opts.wrapped ~= nil then
		label.TextWrapped = opts.wrapped == true
	end
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

	-- The pill is a UIListLayout, so the slot only has to declare its size and order -- the layout
	-- puts the value beside it either way, and a drawn icon and an emoji occupy the same 40px box.
	local icon = iconSlot(frame, opts.icon or "", frame.ZIndex, 16, opts.maxTextSize or 34)
	icon.Size = UDim2.new(0, 40, 1, 0)
	icon.LayoutOrder = 1

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
	-- same rule as UITheme.Label: a Pill takes its colour from the caller, so a dark one would
	-- otherwise be a currency readout inside a halo of its own darkness
	outlineText(value, isDarkInk(value.TextColor3) and 0 or nil)
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
	local _, modalStroke = applyShell(modal, opts.color or Color.PanelWhite, radius, 5)
	-- The cyan rim, asked for explicitly. A modal IS a panel, so this is one of the two places
	-- entitled to it -- see the note in applyShell about why it cannot be decided from the fill.
	if modalStroke and (opts.color == nil or opts.color == Color.PanelWhite) then
		modalStroke.Thickness = 6
		modalStroke.Color = Color.PanelBorder
	end
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

	local modalScale = Instance.new("UIScale")
	modalScale.Name = "ModalScale"
	modalScale.Scale = 1
	modalScale.Parent = modal

	modal:GetPropertyChangedSignal("Visible"):Connect(function()
		dim.Visible = modal.Visible
		if modal.Visible and RunService:IsClient() then
			modalScale.Scale = 0.88
			TweenService:Create(modalScale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.0 }):Play()
		end
	end)
	modal.Destroying:Connect(function()
		dim:Destroy()
	end)

	return modal, content, closeButton
end

-- ============================================================================
-- PUBLIC: PanelHeader - the accent bar every shop-side panel opens with (11.13)
-- ============================================================================
--
-- Every floating panel in MainUI used to open with a bare left-aligned TextLabel sitting on the
-- panel's own cream shell: no band, no rule, no subtitle, and side margins of 14, 16, 18 and 24
-- depending on which panel was written on which day. That reads as a document with a heading rather
-- than a shop with a counter, and it is most of what "the shops look plain" is describing.
--
-- One accent band, drawn with the same `applyShell` + `addGloss` every button and card in the game
-- already uses, so it inherits the chunky look wholesale -- thick outline, hard shadow, glossy top --
-- rather than restating it. That is also why this is NOT a new visual language: the reference kit
-- (`ui_kits/evolution-lab/RobuxShopModal.jsx`) is a cream card with a 3 px outline and
-- `--shadow-panel`, which is exactly what `applyShell` draws.
--
-- THE SUBTITLE IS THE POINT, not the band. A shop panel has to answer "what am I spending, and on
-- what" before the player reads a single tile, and none of the four did -- "Upgrades" over a row of
-- DNA tiles and a row of Diamond tiles says nothing about which currency buys which. The band is
-- what gives the subtitle somewhere to live.
--
-- `closeGap` reserves the top-right corner for `panelClose`'s 42 px X. The title is clipped to that
-- width rather than the header being shortened, so the band still runs the full width of the panel
-- and the X sits ON it -- shortening the band instead leaves a notch that reads as a mistake.
--
-- Returns the header AND the y offset content should start at, because the caller's next line is
-- always positioning something under it and computing that by hand is how the four panels drifted
-- apart in the first place.
function UITheme.PanelHeader(panel, opts)
	opts = opts or {}
	local base = panel.ZIndex or 20
	local margin = opts.margin or 16
	local top = opts.top or 14
	local subtitle = opts.subtitle
	local height = opts.height or (subtitle and 68 or 52)
	local closeGap = opts.closeGap or 62

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, -(margin * 2), 0, height)
	header.Position = UDim2.new(0, margin, 0, top)
	header.ZIndex = base + Z.Content
	applyShell(header, opts.accent or Color.PanelBlue, UDim.new(0, 16), 4)
	header.Parent = panel

	local gloss = addGloss(header, UDim.new(0, 16))
	gloss.ZIndex = header.ZIndex + Z.Gloss

	local title = UITheme.Label(header, {
		name = "Title",
		text = opts.title or "",
		size = UDim2.new(1, -(14 + closeGap), 0, subtitle and 32 or (height - 12)),
		position = UDim2.new(0, 14, 0, subtitle and 6 or 6),
		xAlign = "Left",
		maxTextSize = opts.maxTextSize or 30,
		zIndex = header.ZIndex + Z.Content,
	})
	-- 9.9's pipeline, unchanged: a mapped leading emoji becomes a drawing at the label's left edge
	-- and everything else stays a glyph. Called on the header's own title so a panel converted to
	-- this component keeps the icon it already had.
	UITheme.IconifyLabel(title)

	local sub
	if subtitle then
		sub = UITheme.Label(header, {
			name = "Subtitle",
			text = subtitle,
			size = UDim2.new(1, -(14 + closeGap), 0, 22),
			position = UDim2.new(0, 14, 0, 38),
			xAlign = "Left",
			maxTextSize = 18,
			minTextSize = 12,
			color = Color.Cream,
			zIndex = header.ZIndex + Z.Content,
		})
	end

	return header, top + height + (opts.gap or 12), title, sub
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
	-- A recolour of the bottom lip used to live here. There is no lip any more (see addShadow), and
	-- the guard is kept only because a surface built before this change can still be on screen in a
	-- session that hot-reloaded UITheme -- recolouring it keeps that one consistent instead of
	-- leaving a bar in the old colour. New surfaces never have the child, so this never runs.
	local lip = inst:FindFirstChild("Shadow")
	if lip and lip:IsA("Frame") and lip:GetAttribute("IsLip") then
		lip.BackgroundColor3 = shade(color, -0.30)
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
		-- THE GLYPH COMES OUT WHEN THERE IS ALREADY A DRAWING OF IT (9.9). Dozens of call sites
		-- rewrite a caption with the emoji baked into the new string -- `SetText(btn, "🎡 SPIN 25🌟")`
		-- -- and on a button whose icon is now an ImageLabel that would put the emoji back beside
		-- the picture of itself. Stripping only a LEADING mapped glyph is deliberate: the trailing
		-- 🌟 in that same string is part of a price and has no icon slot to move into.
		local slot = inst:FindFirstChild("Icon")
		if slot and slot:IsA("ImageLabel") then
			-- ...AND THE PICTURE FOLLOWS THE WORDS. A control's leading glyph is not decoration, it
			-- is part of what the control currently SAYS: the shard spin button reads
			-- "🎡 SPIN 25🌟" when it can be pressed and "🌟 4 / 25" when it cannot. An icon frozen
			-- at build time would keep offering a wheel next to a progress count. Only updated when
			-- the new text actually leads with a mapped glyph -- otherwise the existing icon stands,
			-- because "REVIVE  (2 left)" is the same button as "⚔️ REVIVE" with a different caption.
			local nextAsset = IconLibrary.Resolve(text)
			if nextAsset then
				slot.Image = nextAsset
			end
			text = IconLibrary.StripLeading(text)
		end
		label.Text = text
		return
	end
	-- An IconTile whose icon is drawn has an ImageLabel called "Label" and no text at all. Setting
	-- `.Text` on it would error, and the caption is a different child anyway -- so this is a no-op
	-- by design rather than by accident.
	if label and label:IsA("ImageLabel") then
		return
	end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		inst.Text = text
	end
end

-- Swaps the drawing in an icon slot, for the handful of places that change what a control MEANS
-- rather than what it says -- the potion strip's kind, a tab's state. Takes an emoji, like
-- everything else in this system, and falls back to writing the glyph when there is no art.
function UITheme.SetIcon(inst, emoji)
	if not inst then
		return
	end
	local host = inst:FindFirstChild("Body") or inst
	local slot = host:FindFirstChild("Icon") or host:FindFirstChild("Label")
	if not slot then
		return
	end
	local asset = IconLibrary.Resolve(emoji)
	if slot:IsA("ImageLabel") then
		-- An unmapped emoji cannot be shown by an ImageLabel, so it clears rather than leaving the
		-- PREVIOUS icon standing -- a stale picture is a worse answer than an empty slot, because it
		-- is the one a player would believe.
		slot.Image = asset or ""
	elseif slot:IsA("TextLabel") then
		slot.Text = emoji or ""
	end
end

-- ============================================================================
-- A BUTTON THAT IS SOMETIMES A PICTURE AND SOMETIMES A WORD (10.20)
-- ============================================================================
-- The zone list's Go button is the case this exists for: locked it is a padlock, unlocked it is
-- the word "Go". Both cannot be shown at once and neither can be built lazily -- a slot created on
-- first use leaves the very first draw of a fresh save showing whatever the other state left
-- behind.
--
-- So the caller builds the ImageLabel once, at construction, and flips between the two here. The
-- icon is HIDDEN rather than blanked: clearing `Image` would make the next flip re-fetch the
-- texture, and a texture that is re-fetched is a texture that can be missing for a frame.
--
-- IN UITheme RATHER THAN IN MainUI, deliberately. MainUI's top level is one Luau function with a
-- 200-register ceiling and this would be one more named local there for no benefit -- the same
-- reason IconSlot, IconifyLabel and SetIcon all live here. See the register note in MainUI.
function UITheme.ShowIconOrText(button, useIcon, text, iconName)
	if not button then return end
	local icon = button:FindFirstChild(iconName or "LockIcon", true)
	if icon then
		icon.Visible = useIcon
	end
	-- When there is no icon slot at all -- an unmapped emoji, or a build that skipped it -- fall
	-- back to text in BOTH states rather than showing an empty button. An icon that does not exist
	-- must never be able to produce a button with nothing on it.
	button.Text = (useIcon and icon) and "" or (text or "")
end

-- ============================================================================
-- JUICY INTERACTION HELPERS: Pulse & SetProgress
-- ============================================================================
function UITheme.Pulse(inst, maxScale)
	if not inst or not RunService:IsClient() then
		return
	end
	local scale = inst:FindFirstChild("Scale")
	if not scale or not scale:IsA("UIScale") then
		scale = inst:FindFirstChildOfClass("UIScale")
	end
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "Scale"
		scale.Scale = 1
		scale.Parent = inst
	end
	scale.Scale = maxScale or 1.15
	TweenService:Create(scale, PULSE_TWEEN_INFO, { Scale = 1.0 }):Play()
end

function UITheme.SetProgress(bar, progress, animated)
	if not bar then
		return
	end
	local fill = bar:FindFirstChild("Fill")
	if not fill or not fill:IsA("Frame") then
		return
	end
	local target = math.clamp(progress or 0, 0, 1)
	if animated ~= false and RunService:IsClient() then
		TweenService:Create(fill, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(target, 0, 1, 0)
		}):Play()
	else
		fill.Size = UDim2.new(target, 0, 1, 0)
	end
end

return UITheme
