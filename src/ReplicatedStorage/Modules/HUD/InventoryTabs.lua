-- InventoryTabs -- the tab strip that swaps the Inventory panel between pets, potions and relics.
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

	-- `topY` is where the strip's own top edge goes. Absent means the old behaviour -- ABOVE the card,
	-- at -34 -- which is still right for the Pets panel: its title is up there too (y = -30), so the
	-- pair reads as one label group sitting on the corner of the board. The Potions panel converted to
	-- a PanelHeader band, so its strip belongs INSIDE, under the band.
	local function buildTabs(panel, activeIndex, topY)
		local row = Instance.new("Frame")
		row.Name = "InventoryTabs"
		-- 262 -> 358 FOR THE THIRD TAB (2026-08-17). The tabs came 124 -> 112 at the same time rather
		-- than letting the row grow the full 132: this strip is right-aligned inside the panel, and on
		-- the Pets panel it shares its row with the enchant-odds line, whose width is `1, -412` and is
		-- derived from THIS number (358 + a 16 gap + the 22 margin + a little). 112 still clears the
		-- longest caption, "\u{1F9EA} Potions", at the authored 19 px with no shrink.
		-- 3 * 112 + 2 * 8 of padding = 352, and the 6 spare are the same slack the two-tab row had.
		row.Size = UDim2.new(0, 358, 0, 38)
		-- above the card, not inside it: both panels fill their own interior with content that was
		-- laid out before this existed, and squeezing a row in at the top would have meant moving
		-- every scroll frame in both of them
		-- -18 stays -18 while the strip is outside: the Pets panel is untouched by this and its
		-- margin is not the converted panels' 16.
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
		layout.Padding = UDim.new(0, 8)
		layout.Parent = row

		-- RELICS IS THE THIRD SHELF (2026-08-17), and the tile that used to open potions from the left
		-- column went at the same time. Pets, potions and relics are three kinds of thing you own, so
		-- they are three tabs behind one \u{1F392} rather than three doors on the HUD -- see the note
		-- where that tile used to be in `MainUI`. Its panel is deliberately empty for now; the tab
		-- exists so the room can be furnished without the navigation changing again.
		-- Each colour is its panel's own header accent, which is the rule the whole HUD follows.
		local defs = {
			{ text = "\u{1F43E} Pets", target = petsPanel, color = UITheme.Color.Bubblegum },
			{ text = "\u{1F9EA} Potions", target = inventoryPanel, color = UITheme.Color.Aqua },
			{ text = "\u{1F52E} Relics", target = relicsPanel, color = UITheme.Color.Gold },
		}
		for i, def in ipairs(defs) do
			local tab = Instance.new("TextButton")
			tab.Name = "Tab" .. i
			tab.Size = UDim2.new(0, 112, 0, 34)
			tab.LayoutOrder = i
			tab.AutoButtonColor = false
			tab.Text = def.text
			tab.Font = UITheme.Font.Display
			tab.TextSize = 19
			-- the inactive tab is dimmed rather than hidden, so the pair always reads as a pair
			tab.TextColor3 = i == activeIndex and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(236, 238, 248)
			tab.TextTransparency = i == activeIndex and 0 or 0.25
			tab.ZIndex = row.ZIndex + 1
			tab.Parent = row
			styleCard(tab, i == activeIndex and def.color or UITheme.Color.Locked, UDim.new(0, 14), 4)
			-- ===== BOTH TABS WERE BLANK PILLS, AND THE OUTLINE WAS NOT THE REASON (16.6) =====
			--
			-- A TextButton draws its own text at its OWN ZIndex, and `styleCard` puts the fill in an
			-- `InnerBody` child one rung ABOVE it (`Z.Body`) -- so since 15.28 the shell has been
			-- painted straight over the caption. Photographed: a grey pill and a blue pill with no
			-- words on either.
			--
			-- The first reading of this row was wrong in an instructive way. A contrast sweep said
			-- the text was 1.13:1 against its own fill and the conclusion was "it needs the missing
			-- outline" -- true (these were the only 4 of 942 visible runs with no `UIStroke`) and
			-- not the fault. A colour probe cannot see occlusion; the capture can. Adding the halo
			-- to a glyph nothing draws changed nothing, which is what the second capture showed.
			--
			-- So the caption moves onto its own label at `Z.Content`, the way `styleButton` mirrors
			-- every other button in this file into a proxy. `themeLabel` gives it the chunky halo
			-- for free, and the stroke is then matched to the glyph's own transparency: an outline
			-- left opaque under a dimmed label draws the word in outline only, the trap the `+1`
			-- popup and the notification fade both already carry notes about.
			-- ===== AND THE GLYPH BECOMES A DRAWING (2026-08-17) =====
			--
			-- These three captions were the last emoji in the HUD still rendering as FONT. Every other
			-- surface -- the panel headers, the tiles, the toasts, the shop rows -- goes through
			-- `IconifyLabel` or `IconSlot` and gets the game's own art; this strip did not, so the
			-- three shelves of one cupboard were labelled in a different visual language from the
			-- panels they open, and the emoji rendered at whatever the player's device decided.
			--
			-- `IconifyLabel` CANNOT BE USED HERE and refuses by design: it takes a LEFT-aligned label
			-- and hangs the icon off its left edge, and a centred one has no fixed left edge to hang
			-- anything off -- the text starts wherever its own width puts it. This caption is centred.
			-- So the pair is laid out by hand: a fixed icon column, then the word beside it.
			--
			-- 12 / 24 / 42 is arithmetic on the 112 px tab. The icon is 24 at x = 12, the word starts at
			-- 42, and the longest of the three ("Potions") measures ~62 px at 19 px of FredokaOne, so it
			-- ends at 104 with 8 to spare. Left-aligned rather than centred in the remainder, so the
			-- three words start at the same x down the strip -- three captions each centred in its own
			-- leftover space would step left and right by a few pixels per tab and read as misaligned.
			local art = IconLibrary.Resolve(def.text)
			local caption = art and IconLibrary.StripLeading(def.text) or def.text

			if art then
				local glyph = Instance.new("ImageLabel")
				glyph.Name = "Glyph"
				glyph.Size = UDim2.new(0, 24, 0, 24)
				glyph.Position = UDim2.new(0, 12, 0.5, -12)
				glyph.BackgroundTransparency = 1
				glyph.Image = art
				glyph.ScaleType = Enum.ScaleType.Fit
				-- matched to the caption's own fade, or the dimmed tab keeps a full-brightness icon
				-- beside a ghosted word -- the mismatch this file already carries a note about for the
				-- text stroke, one element along.
				glyph.ImageTransparency = tab.TextTransparency
				glyph.ZIndex = tab.ZIndex + UITheme.Z.Content
				glyph.Parent = tab
			end

			local cap = Instance.new("TextLabel")
			cap.Name = "Label"
			cap.Size = art and UDim2.new(1, -46, 1, 0) or UDim2.new(1, -10, 1, 0)
			cap.Position = art and UDim2.new(0, 42, 0, 0) or UDim2.new(0, 5, 0, 0)
			cap.BackgroundTransparency = 1
			cap.Text = caption
			cap.TextColor3 = tab.TextColor3
			cap.TextTransparency = tab.TextTransparency
			cap.ZIndex = tab.ZIndex + UITheme.Z.Content
			cap.Parent = tab
			themeLabel(cap, 19)
			-- AFTER themeLabel, which sets TextScaled and would otherwise stomp the alignment on a
			-- label it thinks it owns. Same ordering trap the potion sub-label paid for.
			cap.TextXAlignment = art and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center
			local capStroke = cap:FindFirstChildOfClass("UIStroke")
			if capStroke then capStroke.Transparency = cap.TextTransparency end
			tab.Text = ""
			tab.MouseButton1Click:Connect(function()
				if not def.target or def.target == panel then return end
				toggleOnly(def.target)
				if def.target == inventoryPanel then
					refreshInventoryPanel()
				end
			end)
		end
	end

	buildTabs(petsPanel, 1, 94)
	-- 94 is the band's own bottom edge: top 14 + height 68 + gap 12, written out rather than read
	-- off PanelHeader's second return value, which would cost a top-level register this file has not
	-- got. The row is 38 tall carrying 34 px tabs, so it ends at 132 and the rule below clears it.
	buildTabs(inventoryPanel, 2, 94)
	-- Guarded, unlike the two above: those two panels are built in MainUI itself and cannot be
	-- absent, where this one comes from a sibling module that a future split could reorder.
	if relicsPanel then
		buildTabs(relicsPanel, 3, 94)
	end
end
