-- ScrollingPanelBuilder
-- Generates standardized panels with scrollable card lists.
--
-- WHAT THIS IS: the drawing kit for the new panel design -- a bordered card with a gradient header,
-- an icon, a title, a close button, and a scrolling list of cards. A card is an icon, up to three
-- lines of text, and one or two action buttons down its right-hand side.
--
-- WHAT CHANGED WHEN THE PANELS WERE MADE FUNCTIONAL (18.16), because all of it is the same fault:
-- the first version could only ever DRAW a panel once. Every one of these is what a live panel
-- needs and a mockup does not.
--
--   * `AddCard` RETURNS A HANDLE. Without one there is no way to say "this zone is unlocked now"
--     without tearing the panel down and rebuilding it, and a rebuild loses the scroll position
--     every three seconds -- which is how often the server pushes a DataUpdate.
--   * `Clear()`, for the lists whose LENGTH changes (the potion bag empties as you drink it).
--   * `SetOpen`/`IsOpen` beside `Toggle`, because a panel that refreshes on a timer must be able
--     to ask whether anyone is looking at it. Refreshing a hidden panel is the cost this game has
--     twenty of.
--   * `AutomaticCanvasSize` replaces a hand-set `CanvasSize`. The old line read
--     `layout.AbsoluteContentSize.Y` in the same frame the card was created in, and that property
--     does not update until the layout runs -- so every list was one card short of scrollable and
--     the last card could not be reached.
--   * `ClipsDescendants` on the scroll frame. Cards carry a 4 px `UIStroke` drawn OUTSIDE their
--     own bounds, so without it the top card's outline paints over the header's bottom rule.
--   * a `Refresh` hook the owner can register, called on open, so a panel is never shown with the
--     numbers it had when it was built.
--
-- THE STUD TEXTURE AND THE INK OUTLINE ARE THE LOOK. Both are deliberate and both are load-bearing:
-- the near-black `UIStroke` is what makes a pastel card read as a solid object rather than a wash,
-- and every text run carries its own stroke because white text on a light gradient is otherwise
-- unreadable at the top of the card.

local Builder = {}

local INK = Color3.fromRGB(0, 0, 50)
local BLACK = Color3.fromRGB(0, 0, 0)
local WHITE = Color3.fromRGB(255, 255, 255)
local STUDS = "rbxassetid://17601461662"

-- A disabled button is not a hidden one: the card still has to say what it would cost, or the
-- player cannot tell "you cannot afford this" from "this does not exist". Grey, but legible.
local DISABLED = { Color3.fromRGB(178, 178, 190), Color3.fromRGB(128, 128, 142) }

local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
	return c
end

local function stroke(inst, color, thickness, mode)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	if mode then s.ApplyStrokeMode = mode end
	s.Parent = inst
	return s
end

local function gradient(inst, colors)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, colors[1]),
		ColorSequenceKeypoint.new(1, colors[2]),
	})
	g.Parent = inst
	return g
end

-- The tiled stud sheet that gives every surface its texture. Parented last so it sits over the
-- gradient, and always non-interactive: it covers the whole button, so an ImageLabel that ate
-- input would make the button under it dead.
local function studs(inst, tile, transparency, radius, zIndex)
	local s = Instance.new("ImageLabel")
	s.Name = "Studs"
	s.Size = UDim2.new(1, 0, 1, 0)
	s.BackgroundTransparency = 1
	s.Image = STUDS
	s.ScaleType = Enum.ScaleType.Tile
	s.TileSize = UDim2.new(0, tile, 0, tile)
	s.ImageTransparency = transparency
	s.ImageColor3 = BLACK
	s.ZIndex = zIndex
	s.Active = false
	corner(s, radius)
	s.Parent = inst
	return s
end

local function outlinedText(parent, text, size, height, zIndex, thickness)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, height)
	l.BackgroundTransparency = 1
	l.Text = text
	l.Font = Enum.Font.FredokaOne
	l.TextSize = size
	l.TextColor3 = WHITE
	l.ZIndex = zIndex
	stroke(l, BLACK, thickness)
	l.Parent = parent
	return l
end

function Builder.CreatePanel(options)
	local screenGui = options.Parent

	local overlay = Instance.new("Frame")
	overlay.Name = options.Name .. "Overlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = BLACK
	overlay.BackgroundTransparency = 0.5
	overlay.Visible = false
	overlay.ZIndex = 50
	-- THE STAMP IS THE CONTRACT (18.21). MainUI keeps its panels in `togglePanels`, a local it
	-- cannot export, and marks each one with this attribute so another script can still find them.
	-- These overlays never pass through its `registerPanel` -- they are full-screen dims, and that
	-- function centres the frame and gives it a UIScale pop, neither of which suits one. Wearing the
	-- stamp is what lets the exclusion work in both directions without either file importing the
	-- other: MainUI's `closeAllPanels` sweeps for it, and `SetOpen` below sweeps for it too.
	overlay:SetAttribute("HudPanel", true)
	overlay.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.Name = options.Name .. "Panel"
	panel.Size = UDim2.new(0, 650, 0, 450)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = WHITE
	panel.ZIndex = 51
	panel.Parent = overlay
	corner(panel, 12)
	stroke(panel, INK, 6)

	-- ---- header
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 70)
	header.BackgroundColor3 = WHITE
	header.ZIndex = 52
	header.Parent = panel
	corner(header, 12)
	gradient(header, options.HeaderColors)

	-- the header is rounded and the panel body under it is not, so the bottom two corners have to
	-- be filled back in or the gradient shows a notch either side of the rule below it
	local hBlock = Instance.new("Frame")
	hBlock.Name = "HeaderFoot"
	hBlock.Size = UDim2.new(1, 0, 0, 15)
	hBlock.Position = UDim2.new(0, 0, 1, -15)
	hBlock.BackgroundColor3 = WHITE
	hBlock.BorderSizePixel = 0
	hBlock.ZIndex = 51
	hBlock.Parent = header
	gradient(hBlock, options.HeaderColors)

	local hLine = Instance.new("Frame")
	hLine.Name = "HeaderRule"
	hLine.Size = UDim2.new(1, 0, 0, 6)
	hLine.Position = UDim2.new(0, 0, 1, -6)
	hLine.BackgroundColor3 = INK
	hLine.BorderSizePixel = 0
	hLine.ZIndex = 53
	hLine.Parent = header

	local hIcon = Instance.new("ImageLabel")
	hIcon.Name = "HeaderIcon"
	hIcon.Size = UDim2.new(0, 80, 0, 80)
	hIcon.Position = UDim2.new(0, 10, 0.5, -5)
	hIcon.AnchorPoint = Vector2.new(0, 0.5)
	hIcon.BackgroundTransparency = 1
	hIcon.Image = options.HeaderIcon or ""
	hIcon.ZIndex = 54
	hIcon.Parent = header

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	-- to the close button, not a fixed 300: a long title used to run underneath it
	title.Size = UDim2.new(1, -175, 1, 0)
	title.Position = UDim2.new(0, 100, 0, 0)
	title.BackgroundTransparency = 1
	title.Text = options.Title
	title.Font = Enum.Font.FredokaOne
	title.TextSize = 40
	title.TextColor3 = WHITE
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.ZIndex = 54
	title.Parent = header
	stroke(title, BLACK, 5)

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "Close"
	closeBtn.Size = UDim2.new(0, 50, 0, 50)
	closeBtn.Position = UDim2.new(1, -10, 0.5, 0)
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.BackgroundColor3 = WHITE
	closeBtn.Text = "X"
	closeBtn.Font = Enum.Font.FredokaOne
	closeBtn.TextSize = 35
	closeBtn.TextColor3 = WHITE
	closeBtn.ZIndex = 55
	closeBtn.Parent = header
	gradient(closeBtn, { Color3.fromRGB(255, 150, 50), Color3.fromRGB(255, 80, 0) })
	corner(closeBtn, 8)
	stroke(closeBtn, BLACK, 4, Enum.ApplyStrokeMode.Border)
	stroke(closeBtn, BLACK, 3)
	studs(closeBtn, 15, 0.5, 8, 55)

	-- ---- the list
	local isHorizontal = options.ScrollDirection == "Horizontal"
	local footerHeight = options.FooterHeight or 0
	
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.Size = UDim2.new(1, -20, 1, -(85 + footerHeight))
	scroll.Position = UDim2.new(0, 10, 0, 75)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = Color3.fromRGB(120, 120, 140)
	scroll.ClipsDescendants = true
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = isHorizontal and Enum.AutomaticSize.X or Enum.AutomaticSize.Y
	scroll.ZIndex = 52
	scroll.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 15)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.FillDirection = isHorizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
	if not isHorizontal then
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	else
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
	end
	layout.Parent = scroll
	
	local footerFrame = nil
	if footerHeight > 0 then
		footerFrame = Instance.new("Frame")
		footerFrame.Name = "Footer"
		footerFrame.Size = UDim2.new(1, -20, 0, footerHeight - 10)
		footerFrame.Position = UDim2.new(0, 10, 1, -footerHeight)
		footerFrame.BackgroundTransparency = 1
		footerFrame.ZIndex = 52
		footerFrame.Parent = panel
	end

	-- ROOM FOR THE STROKE ON ALL FOUR SIDES, and the horizontal half of this is not optional.
	-- A card's `UIStroke` is 4 px drawn OUTSIDE its bounds and the scroll clips. Sized `1, -10` in
	-- a 630 px frame the card is 620 wide, but the 6 px scrollbar leaves 624 of usable width, so
	-- centring left 2 px a side and the right-hand outline was sliced off down the whole list --
	-- visible in the first Teleport capture as cards with no right border.
	-- 10 a side plus the narrower card below is 4 px of clearance and one scrollbar's worth.
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = scroll

	local empty = outlinedText(scroll, options.EmptyText or "Nothing here yet", 24, 60, 54, 3)
	empty.Name = "EmptyNotice"
	empty.LayoutOrder = 999999
	empty.Visible = false

	local cardCount = 0

	local function AddCard(cardOptions)
		cardCount = cardCount + 1
		empty.Visible = false

		local card = Instance.new("Frame")
		card.Name = cardOptions.Name or ("Card" .. cardCount)
		card.LayoutOrder = cardOptions.LayoutOrder or cardCount
		-- full width of the padded frame: the clearance is the padding above, not a margin here
		card.Size = UDim2.new(1, -6, 0, 140)
		card.BackgroundColor3 = WHITE
		card.ZIndex = 53
		card.Parent = scroll
		corner(card, 8)
		local cardGradient = gradient(card, cardOptions.BackgroundColors)
		stroke(card, INK, 4)
		studs(card, 24, 0.85, 8, 53)
		
		if cardOptions.CustomLayout then
			return {
				Instance = card,
				SetColors = function(colors)
					cardGradient.Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, colors[1]),
						ColorSequenceKeypoint.new(1, colors[2]),
					})
				end,
				Destroy = function() card:Destroy() end,
			}
		end

		-- ===== THE PLATE, AND THE PROBLEM IT SOLVES (2026-08-17) =====
		--
		-- Optional, off by default, and the Store is the first caller. A card is a coloured gradient
		-- and an icon is a flat drawing, so an icon whose art shares the card's hue DISAPPEARS into
		-- it -- photographed on the DNA packs, where a pale-blue helix sat on a blue card and read as
		-- a watermark rather than as the product. That is not a colour-picking mistake anyone can fix
		-- per card either: the DNA icon is blue because DNA is blue, and so is the card.
		--
		-- A dark, slightly inset well behind the icon separates the two without touching either. It is
		-- opt-in rather than automatic because the panels whose art is BRIGHT on a PASTEL card -- the
		-- rebirth arrows, the zone landscapes -- do not have the problem and a well under those would
		-- be a box drawn for no reason.
		if cardOptions.IconPlate then
			local plate = Instance.new("Frame")
			plate.Name = "IconPlate"
			plate.Size = UDim2.new(0, 116, 0, 116)
			plate.Position = UDim2.new(0, 12, 0.5, 0)
			plate.AnchorPoint = Vector2.new(0, 0.5)
			plate.BackgroundColor3 = Color3.fromRGB(18, 20, 46)
			plate.BackgroundTransparency = 0.62
			plate.BorderSizePixel = 0
			plate.ZIndex = 54
			plate.Parent = card
			corner(plate, 14)
			stroke(plate, INK, 3)
		end

		local cIcon = Instance.new("ImageLabel")
		cIcon.Name = "Icon"
		cIcon.Size = UDim2.new(0, 120, 0, 120)
		cIcon.Position = UDim2.new(0, 10, 0.5, 0)
		cIcon.AnchorPoint = Vector2.new(0, 0.5)
		cIcon.BackgroundTransparency = 1
		cIcon.Image = cardOptions.Icon or ""
		cIcon.ScaleType = Enum.ScaleType.Fit
		cIcon.ZIndex = 55
		cIcon.Parent = card

		-- THE ICON COLUMN COLLAPSES WHEN THERE IS NO ICON. Not every list has art -- the Store's
		-- products and the zones have none uploaded yet -- and an `ImageLabel` with `Image = ""` is
		-- not invisible, it is a 120 px hole the text is indented past. Measured off the two fixed
		-- columns (icon 130, buttons 170) rather than a 0.6 scale, which overlapped the buttons on
		-- any card carrying two of them.
		local hasIcon = (cardOptions.Icon or "") ~= ""
		cIcon.Visible = hasIcon
		local leftGutter = hasIcon and 140 or 20

		local txtFrame = Instance.new("Frame")
		txtFrame.Name = "Text"
		txtFrame.Size = UDim2.new(1, -(leftGutter + 170), 1, -20)
		txtFrame.Position = UDim2.new(0, leftGutter, 0.5, 0)
		txtFrame.AnchorPoint = Vector2.new(0, 0.5)
		txtFrame.BackgroundTransparency = 1
		txtFrame.ZIndex = 55
		txtFrame.Parent = card

		local tl = Instance.new("UIListLayout")
		tl.SortOrder = Enum.SortOrder.LayoutOrder
		tl.HorizontalAlignment = Enum.HorizontalAlignment.Center
		tl.VerticalAlignment = Enum.VerticalAlignment.Center
		tl.Padding = UDim.new(0, 5)
		tl.Parent = txtFrame

		-- ===== THE RIBBON (2026-08-17), AND WHY IT IS IN THE STACK RATHER THAN ON THE CORNER =====
		--
		-- The old Robux grid hung its "+48% BONUS" ribbon 6 px ABOVE the tile, which is what makes a
		-- ribbon read as a ribbon -- and it cost that file a bug it still carries a note about: a
		-- ScrollingFrame clips at canvas y = 0, so the top row's overhang was simply gone until a top
		-- pad was added to give it somewhere to be. A corner badge has the mirror problem here, because
		-- these cards are ROWS: the right-hand 170 px is the button column, so a top-right badge either
		-- overlaps the button or constrains how many buttons a card may have.
		--
		-- As the first item of the text stack it needs neither trick. It is auto-width, so it is as
		-- long as its words and no longer, and the layout centres it over the title like a kicker --
		-- which is what a "BEST VALUE" flash actually is on a wide card.
		--
		-- Optional and absent by default: four of the five panels built on this file have nothing to
		-- flash, and a nil `Ribbon` builds no instance at all rather than an invisible one.
		local ribbon, ribbonLabel, ribbonGradient
		if cardOptions.Ribbon then
			ribbon = Instance.new("Frame")
			ribbon.Name = "CardRibbon"
			ribbon.LayoutOrder = 0
			ribbon.Size = UDim2.new(0, 0, 0, 24)
			ribbon.AutomaticSize = Enum.AutomaticSize.X
			ribbon.BackgroundColor3 = WHITE
			ribbon.BorderSizePixel = 0
			ribbon.ZIndex = 55
			ribbon.Parent = txtFrame
			corner(ribbon, 6)
			ribbonGradient = gradient(ribbon, cardOptions.Ribbon.Colors or { Color3.fromRGB(255, 214, 120), Color3.fromRGB(240, 165, 20) })
			stroke(ribbon, INK, 3, Enum.ApplyStrokeMode.Border)

			local rPad = Instance.new("UIPadding")
			rPad.PaddingLeft = UDim.new(0, 10)
			rPad.PaddingRight = UDim.new(0, 10)
			rPad.Parent = ribbon

			ribbonLabel = Instance.new("TextLabel")
			ribbonLabel.Name = "Text"
			ribbonLabel.Size = UDim2.new(0, 0, 1, 0)
			ribbonLabel.AutomaticSize = Enum.AutomaticSize.X
			ribbonLabel.BackgroundTransparency = 1
			ribbonLabel.Text = cardOptions.Ribbon.Text or ""
			ribbonLabel.Font = Enum.Font.FredokaOne
			ribbonLabel.TextSize = 16
			ribbonLabel.TextColor3 = WHITE
			ribbonLabel.ZIndex = 56
			stroke(ribbonLabel, BLACK, 2)
			ribbonLabel.Parent = ribbon
		end

		local ct = outlinedText(txtFrame, cardOptions.Title or "", 32, 38, 55, 4)
		ct.Name = "CardTitle"
		ct.LayoutOrder = 1
		ct.TextTruncate = Enum.TextTruncate.AtEnd

		local sub = outlinedText(txtFrame, cardOptions.Subtitle or "", 22, 25, 55, 3)
		sub.Name = "CardSubtitle"
		sub.LayoutOrder = 2
		sub.TextTruncate = Enum.TextTruncate.AtEnd
		sub.Visible = (cardOptions.Subtitle or "") ~= ""

		local desc = outlinedText(txtFrame, cardOptions.Description or "", 18, 20, 55, 2)
		desc.Name = "CardDescription"
		desc.LayoutOrder = 3
		desc.TextTruncate = Enum.TextTruncate.AtEnd
		desc.Visible = (cardOptions.Description or "") ~= ""

		local btnFrame = Instance.new("Frame")
		btnFrame.Name = "Actions"
		btnFrame.Size = UDim2.new(0, 160, 1, -20)
		btnFrame.Position = UDim2.new(1, -10, 0.5, 0)
		btnFrame.AnchorPoint = Vector2.new(1, 0.5)
		btnFrame.BackgroundTransparency = 1
		btnFrame.ZIndex = 55
		btnFrame.Parent = card

		local bl = Instance.new("UIListLayout")
		bl.SortOrder = Enum.SortOrder.LayoutOrder
		bl.VerticalAlignment = Enum.VerticalAlignment.Center
		bl.HorizontalAlignment = Enum.HorizontalAlignment.Right
		bl.Padding = UDim.new(0, 8)
		bl.Parent = btnFrame

		local buttons = {}
		for i, bOpt in ipairs(cardOptions.Buttons or {}) do
			local btn = Instance.new("TextButton")
			btn.Name = bOpt.Name or ("Action" .. i)
			btn.LayoutOrder = i
			btn.Size = UDim2.new(1, 0, 0, 45)
			btn.BackgroundColor3 = WHITE
			btn.AutoButtonColor = true
			btn.Font = Enum.Font.FredokaOne
			btn.TextSize = 25
			btn.TextColor3 = WHITE
			btn.ZIndex = 56
			btn.Parent = btnFrame
			local btnGradient = gradient(btn, bOpt.Colors)
			corner(btn, 6)
			stroke(btn, INK, 3, Enum.ApplyStrokeMode.Border)
			stroke(btn, BLACK, 2)

			local bIcon = Instance.new("ImageLabel")
			bIcon.Name = "ButtonIcon"
			bIcon.Size = UDim2.new(0, 35, 0, 35)
			bIcon.Position = UDim2.new(0, 5, 0.5, 0)
			bIcon.AnchorPoint = Vector2.new(0, 0.5)
			bIcon.BackgroundTransparency = 1
			bIcon.Image = bOpt.Icon or ""
			bIcon.ScaleType = Enum.ScaleType.Fit
			bIcon.ZIndex = 57
			bIcon.Active = false
			bIcon.Parent = btn

			-- the label is indented past the icon only when there IS one, or a plain word like
			-- "USE" sits visibly off-centre
			local function setPrice(text)
				btn.Text = (bIcon.Image ~= "" and "    " or "") .. tostring(text)
			end
			setPrice(bOpt.Price)

			local enabled = true
			local handle
			handle = {
				Instance = btn,
				SetPrice = setPrice,
				SetIcon = function(img)
					bIcon.Image = img or ""
					setPrice((btn.Text:gsub("^%s+", "")))
				end,
				SetColors = function(colors)
					btnGradient.Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, colors[1]),
						ColorSequenceKeypoint.new(1, colors[2]),
					})
				end,
				-- disabled is a LOOK plus a guard, never `Visible = false`: a button that vanishes
				-- takes the price with it and the card stops explaining itself
				SetEnabled = function(on, colors)
					enabled = on and true or false
					btn.AutoButtonColor = enabled
					handle.SetColors(enabled and (colors or bOpt.Colors) or DISABLED)
				end,
				IsEnabled = function() return enabled end,
				SetVisible = function(on) btn.Visible = on and true or false end,
			}

			btn.MouseButton1Click:Connect(function()
				if not enabled then return end
				if bOpt.Callback then
					-- one card's bad callback must not take the panel's other buttons down with it
					local ok, err = pcall(bOpt.Callback, handle)
					if not ok then warn(("[%s] card action failed: %s"):format(options.Name, tostring(err))) end
				end
			end)

			buttons[i] = handle
			if bOpt.Name then buttons[bOpt.Name] = handle end
		end

		return {
			Instance = card,
			Buttons = buttons,
			Button = buttons[1],
			SetTitle = function(t) ct.Text = t or "" end,
			SetSubtitle = function(t)
				sub.Text = t or ""
				sub.Visible = (t or "") ~= ""
			end,
			SetDescription = function(t)
				desc.Text = t or ""
				desc.Visible = (t or "") ~= ""
			end,
			-- keeps the gutter in step: giving a card art later must also move its text back over
			SetIcon = function(img)
				cIcon.Image = img or ""
				local on = (img or "") ~= ""
				cIcon.Visible = on
				local g = on and 140 or 20
				txtFrame.Size = UDim2.new(1, -(g + 170), 1, -20)
				txtFrame.Position = UDim2.new(0, g, 0.5, 0)
			end,
			SetColors = function(colors)
				cardGradient.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, colors[1]),
					ColorSequenceKeypoint.new(1, colors[2]),
				})
			end,
			SetVisible = function(on) card.Visible = on and true or false end,
			SetOrder = function(n) card.LayoutOrder = n end,
			-- Text and colour only, never "grow one later": a card built without a ribbon has no frame
			-- to fill, and returning a no-op is the honest answer rather than silently building one
			-- into a layout whose heights were measured without it.
			SetRibbon = function(text, colors)
				if not ribbon then return false end
				ribbonLabel.Text = text or ""
				ribbon.Visible = (text or "") ~= ""
				if colors and ribbonGradient then
					ribbonGradient.Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, colors[1]),
						ColorSequenceKeypoint.new(1, colors[2]),
					})
				end
				return true
			end,
			Destroy = function() card:Destroy() end,
		}
	end

	-- For the lists whose LENGTH changes rather than their contents -- the potion bag, which empties
	-- as it is drunk. A list of fixed membership (the twenty zones) should keep its handles and
	-- update them instead: rebuilding throws the scroll position away.
	local function Clear()
		for _, c in ipairs(scroll:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		cardCount = 0
		empty.Visible = true
	end

	local refreshFn = nil
	local api = nil

	local function SetOpen(open)
		-- BEFORE the panel is shown, so the screen never holds two open panels for even a frame. See
		-- the note on the `HudPanel` stamp above for why this is swept by attribute.
		if open then
			for _, other in ipairs(screenGui:GetChildren()) do
				if other ~= overlay and other:IsA("GuiObject") and other.Visible
					and other:GetAttribute("HudPanel") then
					other.Visible = false
				end
			end
		end

		overlay.Visible = open and true or false
		-- refresh on the way IN, never on the way out: a panel is opened seconds or minutes after
		-- the data it shows last changed
		if overlay.Visible and refreshFn then
			local ok, err = pcall(refreshFn, api)
			if not ok then warn(("[%s] refresh failed: %s"):format(options.Name, tostring(err))) end
		end

		-- REWOUND AFTER THE REFRESH, NOT BEFORE. `refreshFn` clears the list and rebuilds every card,
		-- and a canvas zeroed first is left wherever regrowing the content puts it -- which is how a
		-- panel reopened at the bottom of its own list stayed there. MainUI's `animatePanel` does the
		-- same thing for the panels IT owns; this is that rule for the ones built here.
		if overlay.Visible then
			scroll.CanvasPosition = Vector2.zero
		end
	end

	closeBtn.MouseButton1Click:Connect(function() SetOpen(false) end)

	api = {
		Overlay = overlay,
		Panel = panel,
		Scroll = scroll,
		Footer = footerFrame,
		AddCard = AddCard,
		Clear = Clear,
		Toggle = function() SetOpen(not overlay.Visible) end,
		SetOpen = SetOpen,
		IsOpen = function() return overlay.Visible end,
		SetTitle = function(t) title.Text = t or "" end,
		SetEmptyText = function(t) empty.Text = t or "" end,
		ShowEmpty = function(on) empty.Visible = on and true or false end,
		-- called every time the panel is opened, and by the owner on a DataUpdate
		OnRefresh = function(fn) refreshFn = fn end,
		Refresh = function()
			if refreshFn then
				local ok, err = pcall(refreshFn, api)
				if not ok then warn(("[%s] refresh failed: %s"):format(options.Name, tostring(err))) end
			end
		end,
	}
	return api
end

return Builder
