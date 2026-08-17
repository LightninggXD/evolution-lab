-- RelicsPanel -- the third tab of the Inventory strip: Pets / Potions / Relics (2026-08-17).
--
-- ===== THIS PANEL IS DELIBERATELY EMPTY, AND THAT IS THE WHOLE FEATURE =====
--
-- The owner asked for "relic opciju u inventoriju pa cemo to posle dodavati" -- the DOOR now, the
-- room later. So this builds the shell, the header, the section rule and an empty state, and it
-- owns no data of its own: there is no `GameConfig.Relics`, no remote and no refresh, because
-- inventing a schema before the feature is designed is how a placeholder becomes a thing the real
-- version has to be bent around.
--
-- WHAT IT IS NOT: it is not a "coming soon" toast bolted onto the Potions panel. It is a real
-- registered panel with a real tab, so the day relics exist the change is a scroll frame inside
-- this file and nothing else in the HUD moves.
--
-- WHITE SHELL, NOT `PANEL_SHELL`. The three tabs swap between panels that must read as three
-- shelves of one cupboard, and the Inventory panel is `PanelWhite` -- a navy sibling would read as
-- a different screen the moment you clicked across. The gradient removal underneath is the same
-- one that panel carries and for the same reason: `styleCard` hangs a top-to-bottom ramp on
-- everything it builds, which over a white sheet just greys the bottom half of it.
--
-- See `docs/SPLIT.md` for the `hud` contract; the tab strip that reaches this is
-- `Modules.HUD.InventoryTabs`, which requires nothing from here except `hud.relicsPanel`.

local RS = game:GetService("ReplicatedStorage")

local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))

local themeLabel, styleCard = UIKit.themeLabel, UIKit.styleCard

return function(hud)
	local PANEL_ANCHOR, screenGui = hud.PANEL_ANCHOR, hud.screenGui
	local registerPanel, panelClose, flatText = hud.registerPanel, hud.panelClose, hud.flatText

	-- The ink the Inventory panel uses for anything grey on its white sheet. Passed EXPLICITLY to
	-- `themeLabel`, which force-brightens a dark colour to white ONLY when it was given none -- so an
	-- explicit dark one survives, which is the entire point on a light panel.
	local INK_ON_WHITE = Color3.fromRGB(108, 116, 140)

	-- 520 x 528 is the Inventory panel's own size, matched on purpose: the tab strip is right-aligned
	-- inside the panel it sits on, so two panels of different widths put the same three tabs in two
	-- different places and clicking across the strip makes it jump.
	local panel = Instance.new("Frame")
	panel.Name = "RelicsPanel"
	panel.Size = UDim2.new(0, 520, 0, 528)
	panel.Position = PANEL_ANCHOR
	panel.ZIndex = 20
	panel.Visible = false
	panel.Parent = screenGui
	styleCard(panel, UITheme.Color.PanelWhite, UDim.new(0, 22), 5)
	local grad = panel:FindFirstChild("Gradient")
	if grad then grad:Destroy() end
	registerPanel(panel)
	panelClose(panel)

	-- The one thing this module exports. Set BEFORE the contents are built so that a require order
	-- accident shows up as an empty panel rather than as a nil tab target.
	hud.relicsPanel = panel

	-- Gold, because that is the Relics tab's own colour in the strip below -- the rule the Journal
	-- follows with Lavender and the Inventory panel with Aqua: a panel whose accent disagrees with
	-- the button that opened it reads as a different screen.
	UITheme.PanelHeader(panel, {
		title = "\u{1F52E} Relics!",
		subtitle = "Nothing forged yet",
		accent = UITheme.Color.Gold,
		maxTextSize = 34,
	})

	-- Section heading: centred grey word with a rule running out of both sides, built the same way
	-- and at the same y as the Inventory panel's "Potions" -- header band 14 + 68 + gap 12 = 94, then
	-- the 38 px tab row and a 12 gap. Two panels whose headings sit at different heights read as two
	-- layouts, and these are meant to read as one.
	local head = Instance.new("TextLabel")
	head.Name = "Section_Relics"
	head.Size = UDim2.new(1, -32, 0, 30)
	head.Position = UDim2.new(0, 16, 0, 144)
	head.BackgroundTransparency = 1
	head.Text = "Relics"
	head.ZIndex = panel.ZIndex + UITheme.Z.Content
	head.Parent = panel
	themeLabel(head, 26, INK_ON_WHITE)
	for _, side in ipairs({ -1, 1 }) do
		local rule = Instance.new("Frame")
		rule.Name = "Rule"
		rule.Size = UDim2.new(0.32, 0, 0, 3)
		rule.Position = UDim2.new(side < 0 and 0 or 0.68, 0, 0.5, -1)
		rule.BackgroundColor3 = Color3.fromRGB(224, 228, 238)
		rule.BorderSizePixel = 0
		rule.ZIndex = head.ZIndex
		rule.Parent = head
	end

	-- ===== THE EMPTY SHELF =====
	-- An inset tray rather than three labels floating on the sheet. An empty panel with words in the
	-- middle of it reads as a screen that failed to load; an empty panel with a visible EMPTY
	-- CONTAINER in it reads as a shelf with nothing on it, which is the true statement.
	local shelf = Instance.new("Frame")
	shelf.Name = "RelicShelf"
	shelf.Size = UDim2.new(1, -32, 1, -202)
	shelf.Position = UDim2.new(0, 16, 0, 186)
	shelf.ZIndex = panel.ZIndex + UITheme.Z.Content
	shelf.Parent = panel
	styleCard(shelf, Color3.fromRGB(240, 242, 250), UDim.new(0, 16), 3)
	local shelfGrad = shelf:FindFirstChild("Gradient")
	if shelfGrad then shelfGrad:Destroy() end

	-- Stacked and centred as one group, so the block stays put whatever the panel's height ends up
	-- being. The glyph is a plain TextLabel and NOT run through `UITheme.IconifyLabel`: there is no
	-- relic art in IconLibrary yet, and asking for a key that does not exist is how a panel ends up
	-- drawing a fallback square.
	local stack = Instance.new("Frame")
	stack.Name = "EmptyState"
	stack.Size = UDim2.new(1, -40, 0, 170)
	stack.Position = UDim2.new(0.5, 0, 0.5, 0)
	stack.AnchorPoint = Vector2.new(0.5, 0.5)
	stack.BackgroundTransparency = 1
	stack.ZIndex = shelf.ZIndex + UITheme.Z.Content
	stack.Parent = shelf

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 6)
	list.Parent = stack

	local function line(order, text, size, color, height)
		local label = Instance.new("TextLabel")
		label.Name = "Line" .. order
		label.LayoutOrder = order
		label.Size = UDim2.new(1, 0, 0, height)
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextWrapped = true
		label.ZIndex = stack.ZIndex
		label.Parent = stack
		-- flatText kills the thick dark halo themeLabel adds -- correct over a coloured tile, and
		-- exactly wrong over a near-white tray, where it draws every word in outline.
		flatText(themeLabel(label, size, color))
		return label
	end

	line(1, "\u{1F52E}", 64, Color3.fromRGB(168, 140, 236), 74)
	line(2, "No Relics yet", 28, INK_ON_WHITE, 34)
	line(3, "Relics are still being forged. When they land, this is the shelf they go on.", 17,
		Color3.fromRGB(150, 154, 168), 46)
end
