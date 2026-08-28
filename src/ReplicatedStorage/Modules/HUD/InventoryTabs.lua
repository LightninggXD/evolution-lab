-- InventoryTabs -- the tab strip that swaps the Inventory panel between pets, potions, relics, trails and swords.
--
-- MOVED OUT OF `MainUI` (18.9), byte for byte. It was already a closed
-- `;(function() ... end)()` block -- the shape this file's 200-register ceiling forces
-- every panel into -- so the extraction is a change of wrapper, not of code. See
-- `docs/SPLIT.md` for the `hud` contract and `docs/CODEMAP.md` for where the rest went.

local RS = game:GetService("ReplicatedStorage")

local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))
local IconLibrary = require(RS.Modules:WaitForChild("IconLibrary"))

local themeLabel, styleCard = UIKit.themeLabel, UIKit.styleCard

return function(hud)
	local inventoryPanel, petsPanel, refreshInventoryPanel = hud.inventoryPanel, hud.petsPanel, hud.refreshInventoryPanel
	local toggleOnly = hud.toggleOnly
	-- Built by `Modules.HUD.RelicsPanel`, which MainUI requires on the line above this module. Read
	-- once here rather than per tab: if that require is ever moved below this one the strip loses a
	-- tab instead of erroring 96 lines later on a nil target.
	local relicsPanel = hud.relicsPanel
	local trailsPanel = hud.trailsPanel
	local swordPanel = hud.swordPanel

	-- `topY` is where the strip's own top edge goes. Absent means the old behaviour -- ABOVE the card,
	-- at -34 -- which is still right for the Pets panel: its title is up there too (y = -30), so the
	-- pair reads as one label group sitting on the corner of the board. The Potions panel converted to
	-- a PanelHeader band, so its strip belongs INSIDE, under the band.
	local function buildTabs(panel, activeIndex, topY)
		local row = Instance.new("Frame")
		row.Name = "InventoryTabs"
		-- 358 -> 474 FOR FIVE TABS (S23, 2026-08-28): Pets, Potions, Relics, Trails, Sword.
		-- Usable interior width across a 520 px panel (16 px margin on both sides) is 520 - 32 = 488 px.
		-- 5 tabs of 90 px + 4 gaps of 6 px = 450 + 24 = 474 px, leaving 14 px of margin slack.
		-- Each tab is 90 x 34 px with a 20 px icon at x = 8 and caption starting at x = 30.
		-- At 16 px display font, the longest caption ("Potions") measures ~44 px, ending at x = 74
		-- with 16 px to spare inside the 90 px tab.
		row.Size = UDim2.new(0, 474, 0, 38)
		row.Position = UDim2.new(1, topY and -16 or -18, 0, topY or -34)
		row.AnchorPoint = Vector2.new(1, 0)
		row.BackgroundTransparency = 1
		row.ZIndex = panel.ZIndex + UITheme.Z.Badge
		row.Parent = panel

		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 6)
		layout.Parent = row

		-- FIVE TABS (S23): Pets, Potions, Relics, Trails, Sword.
		-- Each colour is its panel's own header accent, which is the rule the whole HUD follows.
		local defs = {
			{ text = "\u{1F43E} Pets", target = petsPanel, color = UITheme.Color.Bubblegum },
			{ text = "\u{1F9EA} Potions", target = inventoryPanel, color = UITheme.Color.Aqua },
			{ text = "\u{1F52E} Relics", target = relicsPanel, color = UITheme.Color.Gold },
			{ text = "\u{2728} Trails", target = trailsPanel, color = UITheme.Color.Lavender },
			{ text = "\u{2694}\u{FE0F} Sword", target = swordPanel, color = UITheme.Color.Mint },
		}
		for i, def in ipairs(defs) do
			local tab = Instance.new("TextButton")
			tab.Name = "Tab" .. i
			tab.Size = UDim2.new(0, 90, 0, 34)
			tab.LayoutOrder = i
			tab.AutoButtonColor = false
			tab.Text = def.text
			tab.Font = UITheme.Font.Display
			tab.TextSize = 16
			-- the inactive tab is dimmed rather than hidden, so the pair always reads as a pair
			tab.TextColor3 = i == activeIndex and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(236, 238, 248)
			tab.TextTransparency = i == activeIndex and 0 or 0.25
			tab.ZIndex = row.ZIndex + 1
			tab.Parent = row
			styleCard(tab, i == activeIndex and def.color or UITheme.Color.Locked, UDim.new(0, 14), 4)

			local art = IconLibrary.Resolve(def.text)
			local caption = art and IconLibrary.StripLeading(def.text) or def.text

			if art then
				local glyph = Instance.new("ImageLabel")
				glyph.Name = "Glyph"
				glyph.Size = UDim2.new(0, 20, 0, 20)
				glyph.Position = UDim2.new(0, 8, 0.5, -10)
				glyph.BackgroundTransparency = 1
				glyph.Image = art
				glyph.ScaleType = Enum.ScaleType.Fit
				glyph.ImageTransparency = tab.TextTransparency
				glyph.ZIndex = tab.ZIndex + UITheme.Z.Content
				glyph.Parent = tab
			end

			local cap = Instance.new("TextLabel")
			cap.Name = "Label"
			cap.Size = art and UDim2.new(1, -32, 1, 0) or UDim2.new(1, -8, 1, 0)
			cap.Position = art and UDim2.new(0, 30, 0, 0) or UDim2.new(0, 4, 0, 0)
			cap.BackgroundTransparency = 1
			cap.Text = caption
			cap.TextColor3 = tab.TextColor3
			cap.TextTransparency = tab.TextTransparency
			cap.ZIndex = tab.ZIndex + UITheme.Z.Content
			cap.Parent = tab
			themeLabel(cap, 16)
			cap.TextXAlignment = art and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center
			local capStroke = cap:FindFirstChildOfClass("UIStroke")
			if capStroke then capStroke.Transparency = cap.TextTransparency end
			tab.Text = ""
			tab.MouseButton1Click:Connect(function()
				if not def.target or def.target == panel then return end
				if typeof(def.target) == "Instance" then
					toggleOnly(def.target)
				elseif type(def.target) == "table" then
					if def.target.Toggle then
						def.target.Toggle()
					elseif def.target.SetOpen then
						def.target.SetOpen(true)
					end
				end
				if def.target == inventoryPanel and refreshInventoryPanel then
					refreshInventoryPanel()
				end
			end)
		end
	end

	buildTabs(petsPanel, 1, 52)
	buildTabs(inventoryPanel, 2, 52)
	if relicsPanel then
		buildTabs(relicsPanel, 3, 52)
	end
	if trailsPanel then
		local targetFrame = (typeof(trailsPanel) == "table" and (trailsPanel.Panel or trailsPanel.Overlay)) or trailsPanel
		if targetFrame then buildTabs(targetFrame, 4, 52) end
	end
	if swordPanel then
		local targetFrame = (typeof(swordPanel) == "table" and (swordPanel.Panel or swordPanel.Overlay)) or swordPanel
		if targetFrame then buildTabs(targetFrame, 5, 52) end
	end
end
