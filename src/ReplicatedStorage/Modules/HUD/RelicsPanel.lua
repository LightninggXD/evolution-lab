-- RelicsPanel -- the Relic Forge: four sockets, fifteen relics, one chest button.
--
-- ===== THE ROOM, FINALLY (2026-08-17) =====
--
-- This file shipped twice as a deliberately empty shell. The first version said so in its own
-- header: "the owner asked for the relic opciju u inventoriju pa cemo to posle dodavati -- the DOOR
-- now, the room later ... it owns no data of its own: there is no `GameConfig.Relics`, no remote and
-- no refresh, because inventing a schema before the feature is designed is how a placeholder becomes
-- a thing the real version has to be bent around."
--
-- That was the right call and it is why this file is now mostly additive rather than a rewrite. The
-- shell, the tab, the gold accent, the 520x528 size and the four sockets in a row all survive
-- unchanged; what arrives is `GameConfig.Relics` behind them and a refresh that reads it.
--
-- ===== WHAT THE SHELL ALREADY PROMISED, AND IS NOW KEPT TO =====
--
--   * "Permanent relics that buff your whole lab" -- so no relic is timed, per-zone or per-stage.
--   * "Four relic slots. When the forge opens, this is the shelf they go on." -- FOUR, and the
--     sockets below are the same four 108 px tiles the empty version drew, in the same place.
--   * The name "Relic Forge", which is now literally what the merge button does.
--
-- ===== THE LAYOUT IS THREE BANDS, AND THE MIDDLE ONE IS THE FEATURE =====
--
-- Header (the panel's own accent band) / SOCKETS / the chest button / the collection grid. The
-- sockets stay at the top because what you are WEARING is the answer to "what do my relics do",
-- and a panel that opens on an inventory makes the player hunt for that answer. The grid below is
-- the collection, which is browsing rather than deciding.
--
-- ===== WHY A GRID AND NOT THE CARD LIST THE OTHER PANELS USE =====
--
-- The Potions shelf is a list of rows because a potion needs a sentence -- "x3 DNA from every
-- source, 10 min" does not fit on a tile. A relic needs a picture, a rarity colour and a level pip,
-- which is exactly what a tile is for, and fifteen of them in rows would be a 1,100 px scroll of
-- mostly whitespace. This is the shape the genre uses for the same reason.
--
-- EQUIPPED RELICS STAY IN THE GRID. Removing them would make the collection change size as you
-- equip, and "where did it go" is a worse question than "why is that one ticked".
--
-- ===== ONE REBUILD, THEN ONLY WRITES =====
--
-- Every tile is built ONCE, at Init, and refresh only writes text, colour and visibility. The Pets
-- panel destroys and rebuilds its grid on every `DataUpdate` and carries its own note about the
-- flicker that causes; there is no reason to repeat it here, where the roster is a fixed fifteen.
--
-- See `docs/SPLIT.md` for the `hud` contract; the tab strip that reaches this is
-- `Modules.HUD.InventoryTabs`, which requires nothing from here except `hud.relicsPanel`.

local RS = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("Remotes")

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))
local IconLibrary = require(RS.Modules:WaitForChild("IconLibrary"))
local CardKit = require(RS.Modules:WaitForChild("HUD"):WaitForChild("CardKit"))

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
	local _, _, _, subtitle = UITheme.PanelHeader(panel, {
		title = "\u{1F52E} Relics!",
		subtitle = "Nothing forged yet",
		accent = UITheme.Color.Gold,
		maxTextSize = 34,
	})

	local baseZ = panel.ZIndex + UITheme.Z.Content

	-- ===== THE FOUR SOCKETS =====
	--
	-- Same geometry the empty shell drew and for the same reasons, which are worth keeping written
	-- down: 520 - 32 of margin is 488, and four 108 px tiles with three 16 px gaps is 480, centring
	-- with 4 a side. 108 is the CEILING, not a preference -- (488 - 48) / 4 is 110, and the ink
	-- outline is drawn outside the tile, so 110 would push the two end rims past the panel's margin.
	--
	-- What changed is that a socket is now a BUTTON. Clicking a filled one unequips it; clicking an
	-- empty one does nothing (there is nothing to pick from up here -- you equip from the grid).
	-- That asymmetry is deliberate: the socket row answers "what am I wearing", and the only verb
	-- that belongs to an answer is "take it off".
	local sockets = Instance.new("Frame")
	sockets.Name = "Sockets"
	sockets.Size = UDim2.new(1, -32, 0, 108)
	-- 150 -> 108 (30.10): the whole block came up by the 42 px the tab strip above it gave back --
	-- see the note over `buildTabs`. The 18 px gap under the strip is unchanged; what went is the
	-- empty sheet that used to sit between the subtitle and a strip still parked on the old
	-- content line. Every `y` below moved by the same 42, and the page grew by it.
	sockets.Position = UDim2.new(0, 16, 0, 108)
	sockets.BackgroundTransparency = 1
	sockets.ZIndex = baseZ
	sockets.Parent = panel

	local socketRow = Instance.new("UIListLayout")
	socketRow.FillDirection = Enum.FillDirection.Horizontal
	socketRow.HorizontalAlignment = Enum.HorizontalAlignment.Center
	socketRow.VerticalAlignment = Enum.VerticalAlignment.Center
	socketRow.SortOrder = Enum.SortOrder.LayoutOrder
	socketRow.Padding = UDim.new(0, 16)
	socketRow.Parent = sockets

	local EMPTY_SOCKET = { Color3.fromRGB(96, 100, 130), Color3.fromRGB(52, 56, 84) }
	local LOCKED_SOCKET = { Color3.fromRGB(74, 76, 96), Color3.fromRGB(40, 42, 58) }

	local socketRefs = {}
	for i = 1, GameConfig.RelicMaxSlots do
		local tile, setTileColors = CardKit.Card(sockets, {
			name = "Socket" .. i,
			size = UDim2.new(0, 108, 0, 108),
			layoutOrder = i,
			colors = EMPTY_SOCKET,
			radius = 16,
			studTransparency = 0.78,
			zIndex = baseZ,
		})

		-- The relic's own drawing, hidden until something is worn. An `ImageLabel` with `Image = ""`
		-- is not invisible -- it is a hole the rest of the tile is laid out around -- so it is
		-- explicitly toggled rather than left blank.
		local art = Instance.new("ImageLabel")
		art.Name = "Art"
		art.Size = UDim2.new(0, 74, 0, 74)
		art.Position = UDim2.new(0.5, 0, 0.5, -6)
		art.AnchorPoint = Vector2.new(0.5, 0.5)
		art.BackgroundTransparency = 1
		art.ScaleType = Enum.ScaleType.Fit
		art.Visible = false
		art.ZIndex = baseZ + 2
		art.Parent = tile

		-- The "?" an empty socket shows, and the padlock line a locked one shows instead. Two labels
		-- rather than one retargeted: they are different sizes and sit at different heights, and a
		-- single label that has to be both ends up right for neither.
		local mark = CardKit.Text(tile, {
			name = "Mark",
			text = "?",
			size = UDim2.new(1, 0, 1, 0),
			textSize = 46,
			color = Color3.fromRGB(158, 164, 196),
			xAlign = "Center",
			zIndex = baseZ + 2,
			strokeThickness = 4,
		})

		local lockLine = CardKit.Text(tile, {
			name = "Lock",
			text = "",
			size = UDim2.new(1, -8, 0, 18),
			position = UDim2.new(0, 4, 1, -22),
			textSize = 14,
			color = Color3.fromRGB(206, 210, 232),
			xAlign = "Center",
			zIndex = baseZ + 2,
			strokeThickness = 2,
		})

		-- The level pip, bottom-left, only on a socket wearing something above Lv.1. A pip reading
		-- "Lv.1" on every relic is noise: level 1 is the default and says nothing.
		local pip, pipLabel = CardKit.Pill(tile, {
			name = "Level",
			text = "",
			size = UDim2.new(0, 44, 0, 22),
			position = UDim2.new(0, 6, 1, -28),
			textSize = 14,
			zIndex = baseZ + 3,
		})
		pip.Visible = false

		-- Invisible over the whole tile rather than making the tile itself a TextButton: `CardKit.Card`
		-- returns a Frame, and a transparent button on top is how the rest of this HUD adds a click
		-- target to something already drawn.
		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Size = UDim2.new(1, 0, 1, 0)
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.AutoButtonColor = false
		hit.ZIndex = baseZ + 4
		hit.Parent = tile

		local refs = {
			tile = tile, setColors = setTileColors, art = art, mark = mark,
			lock = lockLine, pip = pip, pipLabel = pipLabel, hit = hit, key = nil,
		}
		hit.MouseButton1Click:Connect(function()
			if refs.key then
				Remotes.UnequipRelic:FireServer(refs.key)
			end
		end)
		socketRefs[i] = refs
	end

	-- ===== THE CHEST BUTTON =====
	--
	-- Two buttons on one row, because there are exactly two doors into a chest and they answer
	-- different questions: "is my free one ready" and "I do not want to wait". The free one carries
	-- its own countdown as its caption -- a timer that lives anywhere other than on the button it
	-- gates is a timer the player has to go and look for.
	--
	-- A BANKED CHEST IS NOT A THIRD DOOR, IT IS THE FIRST ONE ALREADY OPEN. The wheel's relic
	-- segment hands over unopened chests (`RelicService.GiveChest`) and nothing here used to spend
	-- them -- so a player paid 99 R$, was told "open it in the Forge", and found no such thing.
	-- Rather than crowd a third button onto a 48 px row, the free button becomes the banked one
	-- while any are held: same slot, different word, different colour, and it sends "banked".
	-- Spending the bank FIRST is what makes that safe -- the free timer keeps running underneath,
	-- so nothing is thrown away by opening a banked chest at any moment.
	local chestRow = Instance.new("Frame")
	chestRow.Name = "ChestRow"
	chestRow.Size = UDim2.new(1, -32, 0, 48)
	chestRow.Position = UDim2.new(0, 16, 0, 230)   -- 272 - 42, see `sockets` (30.10)
	chestRow.BackgroundTransparency = 1
	chestRow.ZIndex = baseZ
	chestRow.Parent = panel

	local FREE_READY = { Color3.fromRGB(120, 255, 170), Color3.fromRGB(20, 200, 100) }
	local FREE_WAIT = { Color3.fromRGB(178, 184, 204), Color3.fromRGB(120, 126, 150) }
	local DIAMOND_BUY = { Color3.fromRGB(175, 245, 255), Color3.fromRGB(30, 170, 215) }
	-- Gold, because a banked chest is something already won rather than something being waited for,
	-- and the two states share one button: green would make them read as the same event.
	local BANKED = { Color3.fromRGB(255, 226, 130), Color3.fromRGB(228, 158, 20) }

	-- Read by the callback, written by the refresh. The button's own text is not the source of
	-- truth for which remote to send -- a caption is a picture of the state, not the state.
	local bankedChests = 0

	local _, freeChest = CardKit.Button(chestRow, {
		name = "FreeChest",
		text = "FREE CHEST",
		size = UDim2.new(0.62, -6, 1, 0),
		position = UDim2.new(0, 0, 0, 0),
		colors = FREE_READY,
		textSize = 22,
		zIndex = baseZ + 1,
		callback = function()
			Remotes.OpenRelicChest:FireServer(bankedChests > 0 and "banked" or "free")
		end,
	})

	local _, buyChest = CardKit.Button(chestRow, {
		name = "BuyChest",
		text = ("%d \u{1F48E}"):format(GameConfig.RelicChestDiamondCost),
		size = UDim2.new(0.38, -6, 1, 0),
		position = UDim2.new(0.62, 6, 0, 0),
		colors = DIAMOND_BUY,
		textSize = 22,
		zIndex = baseZ + 1,
		callback = function()
			Remotes.OpenRelicChest:FireServer("diamonds")
		end,
	})

	-- ===== THE COLLECTION, WHICH IS NOW TWENTY-ONE COLLECTIONS =====
	--
	-- Until 30.2 this was one section rule reading "Collection" over a grid of fifteen tiles. It is
	-- now a TAB STRIP over a stack of pages, and the reason is arithmetic rather than taste: the
	-- collection layer is 200 relics, and the shape this panel shipped with does not survive them.
	--
	-- WHAT WOULD HAVE BROKEN, MEASURED OFF THE OLD CODE RATHER THAN GUESSED:
	--
	--   * IT BUILT EVERY TILE AT INIT. Fifteen tiles is ~90 instances; 215 is ~1,290, built
	--     synchronously on a `require` that happens while the player is looking at a loading screen.
	--   * IT REWROTE EVERY TILE AT 1 Hz WHILE VISIBLE. Six writes a tile is 90 property writes a
	--     second today and would have been ~1,290 -- forever, for a panel whose contents change a
	--     few times an hour.
	--
	-- So this row buys three things and each one is a separate fix:
	--
	--   1. TABS. One page per zone set plus the Forge's own fifteen. Twenty-one pages of ten to
	--      fifteen tiles is a screen a player can read; 215 tiles in one scroll is a wall.
	--   2. LAZY PAGES. A page is built the first time its tab is opened and never again. A player
	--      who opens the Forge and closes it has built fifteen tiles, exactly as before.
	--   3. A DIRTY FLAG. The 1 Hz ticker now writes ONLY the chest countdown, which is the one thing
	--      no push can tell us about and the only reason the ticker existed. Everything else redraws
	--      when the data actually changed.
	--
	-- And a fourth thing falls out of the tabs for free: only the OPEN page is ever written, so the
	-- cost of a refresh is bounded by what is on screen rather than by what exists.
	local tabs = Instance.new("ScrollingFrame")
	tabs.VerticalScrollBarInset = Enum.ScrollBarInset.Always
	tabs.ScrollBarThickness = 12
	tabs.Name = "SetTabs"
	-- 40 FOR 28 PX TABS, and the 12 is not slack. A CardKit card draws a 3 px border stroke and a
	-- 2 px inner one OUTSIDE its own bounds, so a 28 px tab occupies 38 px of a clipping parent --
	-- the `gap of N shows as N - 15` rule the HUD layout carries, in its smallest form. At 34 the
	-- tabs' outlines were cut off along both edges and the strip read as a row of torn labels.
	tabs.Size = UDim2.new(1, -32, 0, 40)
	tabs.Position = UDim2.new(0, 16, 0, 284)   -- 326 - 42, see `sockets` (30.10)
	tabs.BackgroundTransparency = 1
	tabs.BorderSizePixel = 0
	-- HORIZONTAL ONLY. `AutomaticCanvasSize` on a strip that also has a Y canvas of 0 will happily
	-- report a Y overflow from the tiles' outlines and draw a vertical bar down a 34 px row.
	tabs.ScrollingDirection = Enum.ScrollingDirection.X
	tabs.AutomaticCanvasSize = Enum.AutomaticSize.X
	tabs.CanvasSize = UDim2.new(0, 0, 0, 0)
	tabs.ScrollBarThickness = 12
	-- Grey, not white: 25.4's sweep found nine lists in this game with a white bar on a white sheet,
	-- which is a scrollbar that only exists for people who already know it is there.
	tabs.ScrollBarImageColor3 = Color3.fromRGB(186, 192, 214)
	tabs.ClipsDescendants = true
	tabs.ZIndex = baseZ
	tabs.Parent = panel

	local tabRow = Instance.new("UIListLayout")
	tabRow.FillDirection = Enum.FillDirection.Horizontal
	tabRow.VerticalAlignment = Enum.VerticalAlignment.Center
	tabRow.SortOrder = Enum.SortOrder.LayoutOrder
	tabRow.Padding = UDim.new(0, 6)
	tabRow.Parent = tabs

	-- ===== THE PAGES =====
	--
	-- One `ScrollingFrame` per tab, all stacked in the same place, exactly one visible. A single
	-- grid whose children were swapped would have to destroy and rebuild on every tab press --
	-- which is the flicker the Pets panel carries its own note about -- and would throw away the
	-- lazy build the moment a player looked at two sets.
	-- 370 - 42, and the height is the one number that GAINS the 42 rather than moving by it: the
	-- page still ends where it did (528 - 344 = 184 tall from y = 328, i.e. the same bottom edge at
	-- 512), so the detail strip pinned at `1, -80` still lands fully on the sheet and the grid is
	-- 42 px taller instead of the top of the panel being empty. That is the whole point of 30.10.
	local PAGE_POS = UDim2.new(0, 16, 0, 328)
	local PAGE_SIZE = UDim2.new(1, -32, 1, -344)

	local pages, tabRefs = {}, {}
	local currentTab = "forge"

	local function newPage(name)
		local page = Instance.new("ScrollingFrame")
		page.VerticalScrollBarInset = Enum.ScrollBarInset.Always
		page.ScrollBarThickness = 12
		page.Name = "Page_" .. name
		page.Size = PAGE_SIZE
		page.Position = PAGE_POS
		page.BackgroundTransparency = 1
		page.BorderSizePixel = 0
		page.ScrollBarThickness = 12
		page.ScrollBarImageColor3 = Color3.fromRGB(180, 186, 208)
		page.ClipsDescendants = true
		page.AutomaticCanvasSize = Enum.AutomaticSize.Y
		page.CanvasSize = UDim2.new(0, 0, 0, 0)
		page.Visible = false
		page.ZIndex = baseZ
		page.Parent = panel

		-- 5 x 84 + 4 x 8 of padding = 452 against the 488 the panel's margins leave, and the
		-- scrollbar and the tiles' own outlines take the rest. Five columns puts the fifteen in
		-- exactly three rows and a zone's ten in two.
		local layout = Instance.new("UIGridLayout")
		layout.CellSize = UDim2.new(0, 84, 0, 84)
		layout.CellPadding = UDim2.new(0, 8, 0, 8)
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = page

		-- Room for the tiles' outlines, which are drawn OUTSIDE their bounds against a frame that
		-- clips. Asymmetric on purpose: the scrollbar owns the right edge whatever the padding says.
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 4)
		pad.PaddingBottom = UDim.new(0, 8)
		pad.PaddingLeft = UDim.new(0, 4)
		pad.PaddingRight = UDim.new(0, 12)
		pad.Parent = page
		return page
	end

	-- ===== THE LOCKED PANEL =====
	--
	-- Shown INSTEAD of everything above until stage 10. Not a toast and not a greyed-out panel: a
	-- player who opens a screen full of dark sockets and an unreadable grid has been shown a broken
	-- room, where one line telling them when the door opens is the true statement.
	local locked = Instance.new("Frame")
	locked.Name = "LockedState"
	-- Covers what the sockets and the grid cover, so it moves and grows with them (30.10).
	locked.Size = UDim2.new(1, -32, 1, -124)
	locked.Position = UDim2.new(0, 16, 0, 108)
	locked.BackgroundTransparency = 1
	locked.ZIndex = baseZ + 5
	locked.Visible = false
	locked.Parent = panel

	do
		local stack = Instance.new("UIListLayout")
		stack.FillDirection = Enum.FillDirection.Vertical
		stack.HorizontalAlignment = Enum.HorizontalAlignment.Center
		stack.VerticalAlignment = Enum.VerticalAlignment.Center
		stack.SortOrder = Enum.SortOrder.LayoutOrder
		stack.Padding = UDim.new(0, 8)
		stack.Parent = locked

		local orb = Instance.new("ImageLabel")
		orb.Name = "Orb"
		orb.LayoutOrder = 1
		orb.Size = UDim2.new(0, 84, 0, 84)
		orb.BackgroundTransparency = 1
		orb.Image = IconLibrary.Resolve("\u{1F52E}") or ""
		orb.ImageTransparency = 0.45
		orb.ScaleType = Enum.ScaleType.Fit
		orb.ZIndex = locked.ZIndex
		orb.Parent = locked

		local function line(order, text, size, color, height)
			local label = Instance.new("TextLabel")
			label.Name = "Line" .. order
			label.LayoutOrder = order
			label.Size = UDim2.new(1, -40, 0, height)
			label.BackgroundTransparency = 1
			label.Text = text
			label.TextWrapped = true
			label.ZIndex = locked.ZIndex
			label.Parent = locked
			-- flatText kills the thick dark halo themeLabel adds -- correct over a coloured tile, and
			-- exactly wrong over a near-white sheet, where it draws every word in outline.
			flatText(themeLabel(label, size, color))
			return label
		end

		line(2, "The Relic Forge is sealed", 26, INK_ON_WHITE, 32)
		-- The stage is read off the config rather than typed, so moving the gate moves this sentence.
		line(3, ("Reach stage %d to open it. Relics are permanent bonuses that buff your whole lab."):format(
			GameConfig.RelicUnlockStage), 16, Color3.fromRGB(150, 154, 168), 46)
	end

	-- ===== A TILE =====
	--
	-- One builder for both layers, because a tile is a tile: art, a rarity frame, a dupe badge, a
	-- level pip or a copy count, a tick. What differs between an equippable and a collection relic
	-- is which of those are ever turned on, and that is decided by the refresh rather than here --
	-- two builders would be two places for the tile geometry to drift apart.
	local GHOST = { Color3.fromRGB(206, 210, 224), Color3.fromRGB(150, 155, 175) }

	local function buildTile(parent, def, order, onClick)
		local rarity = def.rarityDef
		local tile, setColors = CardKit.Card(parent, {
			name = "Relic_" .. def.key,
			size = UDim2.new(0, 84, 0, 84),
			layoutOrder = order,
			colors = { rarity.color, rarity.deep },
			radius = 12,
			studTransparency = 0.86,
			zIndex = baseZ + 1,
		})

		local art = Instance.new("ImageLabel")
		art.Name = "Art"
		art.Size = UDim2.new(0, 54, 0, 54)
		art.Position = UDim2.new(0.5, 0, 0.5, -4)
		art.AnchorPoint = Vector2.new(0.5, 0.5)
		art.BackgroundTransparency = 1
		-- RESOLVED THROUGH THE FALLBACK, NEVER `Id[icon]` BARE. An unmapped name gives `Image = ""`,
		-- which is not a blank tile but a HOLE -- and with ten form names that only resolve once
		-- their art has been drawn, rendered and uploaded, that window is real rather than
		-- theoretical. `RelicSetFallbackIcon` is a name that has been in the library since 2026-08-10.
		art.Image = IconLibrary.Id[def.icon]
			or IconLibrary.Id[GameConfig.RelicSetFallbackIcon]
			or ""
		-- The tint is the zone's, and it is the whole reason 200 relics cost 10 uploads. `ImageColor3`
		-- multiplies, so on the fifteen -- which are drawn in their own colours -- it must stay white.
		art.ImageColor3 = def.tint or Color3.new(1, 1, 1)
		art.ScaleType = Enum.ScaleType.Fit
		art.ZIndex = baseZ + 3
		art.Parent = tile

		-- The dupe badge, top-right, and it only appears at two or more. "x1" on everything you own
		-- is the same noise "Lv.1" would be.
		local dupe, dupeLabel = CardKit.Pill(tile, {
			name = "Copies",
			text = "",
			size = UDim2.new(0, 34, 0, 20),
			position = UDim2.new(1, -38, 0, 4),
			textSize = 13,
			zIndex = baseZ + 4,
		})
		dupe.Visible = false

		local levelPip, levelLabel = CardKit.Pill(tile, {
			name = "Level",
			text = "",
			size = UDim2.new(0, 38, 0, 20),
			position = UDim2.new(0, 4, 1, -24),
			textSize = 13,
			zIndex = baseZ + 4,
		})
		levelPip.Visible = false

		-- The equipped tick. A corner mark rather than a border swap, because the border is already
		-- carrying the RARITY and a tile cannot say two things with one edge.
		local tick = CardKit.Text(tile, {
			name = "Tick",
			text = "\u{2714}",
			size = UDim2.new(0, 24, 0, 24),
			position = UDim2.new(1, -26, 1, -26),
			textSize = 20,
			color = Color3.fromRGB(140, 255, 190),
			xAlign = "Center",
			zIndex = baseZ + 4,
			strokeThickness = 3,
		})
		tick.Visible = false

		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Size = UDim2.new(1, 0, 1, 0)
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.AutoButtonColor = false
		hit.ZIndex = baseZ + 5
		hit.Parent = tile
		hit.MouseButton1Click:Connect(onClick)

		return {
			def = def, tile = tile, setColors = setColors, art = art,
			dupe = dupe, dupeLabel = dupeLabel,
			levelPip = levelPip, levelLabel = levelLabel, tick = tick, hit = hit,
		}
	end

	-- Selection is client-only state. `selectedKey` is the key and `selectedSet` says which of the
	-- two layers it belongs to, because the two live in different save fields and a key alone can no
	-- longer say which table to look in.
	local selectedKey, selectedIsSet = nil, false
	local refresh                      -- forward-declared: the tiles' handlers call it

	-- ===== BUILDING A PAGE, ONCE =====
	--
	-- `ensurePage` is the lazy build. It returns the page frame and its tile list, building both the
	-- first time it is asked and never again -- so the cost of the collection layer is paid one zone
	-- at a time, by the player who actually opened that zone.
	local function ensurePage(tabKey)
		local entry = pages[tabKey]
		if entry then return entry end

		local page = newPage(tabKey)
		local tiles = {}
		local defs
		if tabKey == "forge" then
			-- the config's own order, which is rarity ascending, so the grid reads as a ladder and
			-- an unowned Mythic sits alone in the last cell where it is conspicuous
			defs = GameConfig.Relics
		else
			defs = GameConfig.RelicSetsByZone[tabKey].relics
		end

		local isSet = (tabKey ~= "forge")
		for i, def in ipairs(defs) do
			local key = def.key
			tiles[key] = buildTile(page, def, i, function()
				-- A TILE YOU DO NOT OWN IS NOT SELECTABLE on the Forge page, where the strip's whole
				-- job is to equip and forge -- but it IS on a collection page, where "what is this
				-- thing and where does it come from" is the question a player has about the eight
				-- cells they have not filled yet.
				local d = hud.getData and hud.getData()
				if not d then return end
				if not isSet and not (d.Relics and d.Relics[key]) then return end
				-- tapping the selected tile again closes the strip, which is the only way to dismiss it
				if selectedKey == key then
					selectedKey, selectedIsSet = nil, false
				else
					selectedKey, selectedIsSet = key, isSet
				end
				refresh()
			end)
		end

		entry = { page = page, tiles = tiles, isSet = isSet }
		pages[tabKey] = entry
		return entry
	end

	local function showTab(tabKey)
		local entry = ensurePage(tabKey)
		for key, other in pairs(pages) do
			if key ~= tabKey then other.page.Visible = false end
		end
		entry.page.Visible = true
		currentTab = tabKey
		-- A SELECTION DOES NOT SURVIVE A TAB CHANGE. The detail strip sits under the grid and would
		-- otherwise keep describing a relic that is no longer on screen -- which reads as the strip
		-- belonging to whatever tile happens to be under it.
		selectedKey, selectedIsSet = nil, false
		refresh()
	end

	-- ===== THE TAB STRIP =====
	--
	-- The Forge first, then the twenty zones in strip order, which is the order the player unlocked
	-- them in and the order every other list in this game uses. Each tab carries its zone's emoji
	-- and its own count, so the strip doubles as the progress readout -- the alternative is a
	-- "3/20 sets" line somewhere else that the player has to correlate by hand.
	local TAB_ON  = { Color3.fromRGB(255, 214, 120), Color3.fromRGB(240, 165, 20) }
	local TAB_OFF = { Color3.fromRGB(214, 219, 232), Color3.fromRGB(158, 165, 186) }
	local TAB_DONE = { Color3.fromRGB(150, 245, 190), Color3.fromRGB(24, 190, 110) }

	local function addTab(tabKey, order, text, width)
		local tab, setTabColors = CardKit.Card(tabs, {
			name = "Tab_" .. tabKey,
			size = UDim2.new(0, width, 0, 28),
			layoutOrder = order,
			colors = TAB_OFF,
			radius = 8,
			studTransparency = 1,
			zIndex = baseZ + 1,
		})
		local label = CardKit.Text(tab, {
			name = "Label",
			text = text,
			size = UDim2.new(1, -8, 1, 0),
			position = UDim2.new(0, 4, 0, 0),
			textSize = 14,
			xAlign = "Center",
			zIndex = baseZ + 3,
			strokeThickness = 2,
		})
		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Size = UDim2.new(1, 0, 1, 0)
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.AutoButtonColor = false
		hit.ZIndex = baseZ + 4
		hit.Parent = tab
		hit.MouseButton1Click:Connect(function() showTab(tabKey) end)
		tabRefs[tabKey] = { tab = tab, setColors = setTabColors, label = label }
	end

	addTab("forge", 1, "\u{1F52E} Forge", 92)
	for i, set in ipairs(GameConfig.RelicSets) do
		-- The emoji is the ZONE's, which is already drawn everywhere else this zone appears. It is a
		-- glyph rather than an icon on purpose: `IconLibrary` resolves by emoji and returns nil for
		-- most zone glyphs, and a 28 px tab is not where a missing image should be discovered.
		addTab(set.zoneKey, i + 1, ("%s 0/%d"):format(set.emoji, set.total), 78)
	end

	-- ===== THE DETAIL STRIP =====
	--
	-- One row pinned under the grid rather than a modal over it. A modal would cover the sockets --
	-- i.e. cover the thing you are deciding about while you decide -- and on a 520 px panel there is
	-- no room for a side panel. It is empty until a tile is tapped, and it is the ONLY place the
	-- forge button lives, so merging is always a deliberate two-step.
	local detail = Instance.new("Frame")
	detail.Name = "Detail"
	detail.Size = UDim2.new(1, -32, 0, 64)
	detail.Position = UDim2.new(0, 16, 1, -80)
	detail.BackgroundTransparency = 1
	detail.ZIndex = baseZ + 6
	detail.Visible = false
	detail.Parent = panel

	local detailCard, setDetailColors = CardKit.Card(detail, {
		name = "Card",
		size = UDim2.new(1, 0, 1, 0),
		colors = { Color3.fromRGB(176, 184, 208), Color3.fromRGB(104, 112, 140) },
		radius = 12,
		zIndex = baseZ + 6,
	})

	local detailArt = Instance.new("ImageLabel")
	detailArt.Name = "Art"
	detailArt.Size = UDim2.new(0, 46, 0, 46)
	detailArt.Position = UDim2.new(0, 10, 0.5, -23)
	detailArt.BackgroundTransparency = 1
	detailArt.ScaleType = Enum.ScaleType.Fit
	detailArt.ZIndex = baseZ + 8
	detailArt.Parent = detailCard

	local detailName = CardKit.Text(detailCard, {
		name = "Name",
		text = "",
		size = UDim2.new(1, -210, 0, 22),
		position = UDim2.new(0, 64, 0, 8),
		textSize = 19,
		zIndex = baseZ + 8,
		strokeThickness = 3,
	})

	local detailEffect = CardKit.Text(detailCard, {
		name = "Effect",
		text = "",
		size = UDim2.new(1, -210, 0, 30),
		position = UDim2.new(0, 64, 0, 28),
		textSize = 14,
		color = Color3.fromRGB(244, 247, 255),
		wrapped = true,
		yAlign = "Top",
		zIndex = baseZ + 8,
		strokeThickness = 2,
	})

	local FORGE_ON = { Color3.fromRGB(255, 214, 120), Color3.fromRGB(240, 165, 20) }
	local EQUIP_ON = { Color3.fromRGB(120, 255, 170), Color3.fromRGB(20, 200, 100) }

	-- THE INSTANCE AS WELL AS THE HANDLE, because these two buttons are the only ones in the HUD
	-- that have to be able to VANISH. `CardKit.Button`'s handle deliberately has no `SetVisible` and
	-- its own comment says why -- "a button that vanishes takes its caption with it and the card
	-- stops explaining itself", which is exactly right for the DISABLED state it is talking about.
	-- A collection relic is a different case: EQUIP and FORGE are not refused for it, they do not
	-- exist for it, and a greyed-out EQUIP is a statement that the verb exists and is unavailable.
	-- So they are hidden rather than disabled, and the strip carries a sentence instead.
	local equipInst, equipBtn = CardKit.Button(detailCard, {
		name = "Equip",
		text = "EQUIP",
		size = UDim2.new(0, 86, 0, 38),
		position = UDim2.new(1, -186, 0.5, -19),
		colors = EQUIP_ON,
		textSize = 18,
		zIndex = baseZ + 8,
		callback = function()
			if not selectedKey then return end
			-- The button is a toggle on one relic rather than two buttons that swap places: a control
			-- that MOVES between states is a control the player has to re-find every time.
			local data = hud.getData and hud.getData()
			local worn = false
			for _, k in ipairs((data and data.EquippedRelicKeys) or {}) do
				if k == selectedKey then worn = true break end
			end
			if worn then
				Remotes.UnequipRelic:FireServer(selectedKey)
			else
				Remotes.EquipRelic:FireServer(selectedKey)
			end
		end,
	})

	local forgeInst, forgeBtn = CardKit.Button(detailCard, {
		name = "Forge",
		text = "FORGE",
		size = UDim2.new(0, 86, 0, 38),
		position = UDim2.new(1, -94, 0.5, -19),
		colors = FORGE_ON,
		textSize = 18,
		zIndex = baseZ + 8,
		callback = function()
			if selectedKey then Remotes.MergeRelic:FireServer(selectedKey) end
		end,
	})

	-- ===== REFRESH =====
	--
	-- Reads `hud.getData()` and writes; it never builds. Everything it needs to decide is derived
	-- from `GameConfig.Relics` -- the same functions the SERVER uses to roll and to pay the bonuses,
	-- so this panel cannot advertise a number the game is not applying. That rule is why the maths
	-- lives in GameConfig rather than in `RelicService`; see the note over `GetRelicMult`.
	--
	-- IT WRITES ONE PAGE, NEVER TWENTY-ONE. `pages` only contains what has been opened, and of those
	-- only the visible one is written -- so the work here is bounded by what is on the screen rather
	-- than by the 215 relics that exist.
	local function refreshChest(data)
		local ready, remaining = GameConfig.GetRelicChestReady(data, os.time())
		bankedChests = tonumber(data.RelicChests) or 0
		if bankedChests > 0 then
			-- The count is in the caption rather than on a pill: this button is already carrying a
			-- countdown in the other state, so a number in the same place is the one thing a player
			-- is used to reading off it.
			freeChest.SetEnabled(true, BANKED)
			freeChest.SetText(bankedChests > 1
				and ("OPEN CHEST (%d)"):format(bankedChests)
				or "OPEN CHEST")
		else
			freeChest.SetEnabled(ready, FREE_READY)
			freeChest.SetText(ready and "FREE CHEST" or ("%dm %02ds"):format(remaining // 60, remaining % 60))
			if not ready then freeChest.SetColors(FREE_WAIT) end
		end
		buyChest.SetEnabled((data.Diamonds or 0) >= GameConfig.RelicChestDiamondCost, DIAMOND_BUY)
	end

	function refresh()
		local data = hud.getData and hud.getData()
		if not data then return end

		local open = GameConfig.IsRelicForgeUnlocked(data)
		locked.Visible = not open
		sockets.Visible = open
		chestRow.Visible = open
		tabs.Visible = open
		for _, entry in pairs(pages) do
			-- A HIDDEN PANEL'S PAGES ARE ALL HIDDEN, not just the ones that were not current. The
			-- locked state draws over the whole panel and a page left visible under it would show
			-- through the transparent parts of it.
			entry.page.Visible = open and (entry == pages[currentTab])
		end
		if not open then
			detail.Visible = false
			subtitle.Text = ("Sealed until stage %d"):format(GameConfig.RelicUnlockStage)
			return
		end

		local owned = data.Relics or {}
		local equippedLookup = {}
		for _, k in ipairs(data.EquippedRelicKeys or {}) do equippedLookup[k] = true end
		local slots = GameConfig.GetMaxEquippedRelics(data)

		-- --- the sockets
		for i, refs in ipairs(socketRefs) do
			local key = (data.EquippedRelicKeys or {})[i]
			-- A key past the slot cap is NOT drawn even if it is in the list. The cap can fall (it
			-- never does today, but `GetMaxEquippedRelics` is free to change), and a socket showing a
			-- relic that `GetRelicMult` is ignoring would be the panel lying about the bonus.
			if i > slots then key = nil end
			local entry = key and owned[key]
			local relic = key and GameConfig.GetRelic(key)

			if relic and entry then
				refs.key = key
				refs.art.Image = IconLibrary.Id[relic.icon] or ""
				refs.art.Visible = true
				refs.mark.Visible = false
				refs.lock.Text = ""
				refs.setColors({ relic.rarityDef.color, relic.rarityDef.deep })
				local level = (type(entry) == "table" and entry.level) or 1
				refs.pip.Visible = level > 1
				refs.pipLabel.Text = ("Lv.%d"):format(level)
			else
				refs.key = nil
				refs.art.Visible = false
				refs.pip.Visible = false
				if i <= slots then
					refs.mark.Visible = true
					refs.mark.Text = "?"
					refs.lock.Text = ""
					refs.setColors(EMPTY_SOCKET)
				else
					-- A LOCKED SOCKET SAYS WHAT OPENS IT. A padlock alone is a refusal; a padlock with
					-- "Rebirth 1" under it is a goal, and the ladder is read off the config so this
					-- sentence follows a change to the slot rule without being edited.
					refs.mark.Visible = true
					refs.mark.Text = "\u{1F512}"
					refs.lock.Text = GameConfig.GetRelicSlotRequirement(i) or ""
					refs.setColors(LOCKED_SOCKET)
				end
			end
		end

		refreshChest(data)

		-- --- the tab strip. Twenty-one labels is cheap and it is the progress readout, so it is
		-- written every refresh rather than only when its own set changes -- a tab that is stale
		-- about its count is worse than no count.
		for _, set in ipairs(GameConfig.RelicSets) do
			local refs = tabRefs[set.zoneKey]
			local have = GameConfig.CountSetRelicsOwned(data, set.zoneKey)
			refs.label.Text = ("%s %d/%d"):format(set.emoji, have, set.total)
			local done = have >= set.total
			if set.zoneKey == currentTab then
				refs.setColors(TAB_ON)
			else
				refs.setColors(done and TAB_DONE or TAB_OFF)
			end
		end
		tabRefs.forge.setColors(currentTab == "forge" and TAB_ON or TAB_OFF)

		-- --- the open page, and only it
		local entry = pages[currentTab]
		if entry and entry.isSet then
			for key, refs in pairs(entry.tiles) do
				local copies = GameConfig.GetSetRelicCopies(data, key)
				local has = copies > 0
				-- AN UNOWNED RELIC IS A SILHOUETTE, NOT A HIDDEN ONE. The grid doubles as the
				-- reference for what exists -- the same argument the potion shelf makes for listing
				-- bottles you do not hold -- and a collection you cannot see the shape of is not a
				-- collection. It matters more here than on the Forge page: an empty cell is the only
				-- thing telling a player which relic is between them and a completed set.
				refs.setColors(has and { refs.def.rarityDef.color, refs.def.rarityDef.deep } or GHOST)
				refs.art.ImageTransparency = has and 0 or 0.72
				refs.dupe.Visible = copies > 1
				refs.dupeLabel.Text = "x" .. copies
				-- a collection relic has no level and is never worn, so neither mark can ever show
				refs.levelPip.Visible = false
				refs.tick.Visible = false
			end
		elseif entry then
			for key, refs in pairs(entry.tiles) do
				local e = owned[key]
				local copies = (type(e) == "table" and e.copies) or 0
				local level = (type(e) == "table" and e.level) or 1
				local has = copies > 0
				refs.setColors(has and { refs.def.rarityDef.color, refs.def.rarityDef.deep } or GHOST)
				refs.art.ImageTransparency = has and 0 or 0.72
				refs.dupe.Visible = copies > 1
				refs.dupeLabel.Text = "x" .. copies
				refs.levelPip.Visible = level > 1
				refs.levelLabel.Text = ("Lv.%d"):format(level)
				refs.tick.Visible = equippedLookup[key] == true
			end
		end

		-- --- the detail strip
		if selectedKey and selectedIsSet then
			-- A COLLECTION RELIC HAS NO BUTTONS, and that is the promise of the whole layer drawn on
			-- the screen rather than only argued in a config header. It cannot be worn, it cannot be
			-- levelled, and a greyed-out EQUIP would say the opposite -- a disabled control is a
			-- statement that the verb exists.
			local def = GameConfig.GetSetRelic(selectedKey)
			local copies = GameConfig.GetSetRelicCopies(data, selectedKey)
			detail.Visible = def ~= nil
			if def then
				setDetailColors({ def.rarityDef.color, def.rarityDef.deep })
				detailArt.Image = IconLibrary.Id[def.icon]
					or IconLibrary.Id[GameConfig.RelicSetFallbackIcon] or ""
				detailArt.ImageColor3 = def.tint
				detailName.Text = ("%s  \u{00B7}  %s"):format(def.name, def.rarity)
				if copies > 0 then
					detailEffect.Text = ("%s  \u{00B7}  x%d held  \u{00B7}  %s set")
						:format(def.blurb, copies, def.zoneName)
				else
					detailEffect.Text = ("Not found yet  \u{00B7}  %s set"):format(def.zoneName)
				end
				equipInst.Visible = false
				forgeInst.Visible = false
			end
		else
			local relic = selectedKey and GameConfig.GetRelic(selectedKey)
			local entryR = selectedKey and owned[selectedKey]
			if relic and entryR then
				local level = (type(entryR) == "table" and entryR.level) or 1
				detail.Visible = true
				equipInst.Visible = true
				forgeInst.Visible = true
				setDetailColors({ relic.rarityDef.color, relic.rarityDef.deep })
				detailArt.Image = IconLibrary.Id[relic.icon] or ""
				-- the fifteen are drawn in their own colours; a tint would be a second multiply
				detailArt.ImageColor3 = Color3.new(1, 1, 1)
				detailName.Text = ("%s  \u{00B7}  %s"):format(relic.name, relic.rarity)

				-- The LIVE value, not the authored one: a Lv.3 relic pays more than its table row says,
				-- and printing the row would make every levelled relic under-report itself.
				local value = GameConfig.GetRelicValue(relic, level)
				local shown = relic.statDef.add and ("+%d %s"):format(math.floor(value + 0.5), relic.statDef.label)
					or ("+%d%% %s"):format(math.floor(value * 100 + 0.5), relic.statDef.label)
				detailEffect.Text = ("%s  \u{00B7}  %s set  \u{00B7}  Lv.%d"):format(shown, relic.family, level)

				local worn = equippedLookup[selectedKey] == true
				equipBtn.SetText(worn and "UNEQUIP" or "EQUIP")
				equipBtn.SetEnabled(worn or #(data.EquippedRelicKeys or {}) < slots, EQUIP_ON)

				-- THE FORGE BUTTON SAYS WHY IT IS OFF. Four different refusals now -- maxed, not
				-- enough copies AND not enough dust to cover the gap, not enough DNA -- and a single
				-- greyed button that means all of them is a button the player pokes at.
				-- `GetRelicMergePlan` is the config's own test and the same one the server charges
				-- with, so this cannot disagree with what happens when the button IS pressed.
				local plan = GameConfig.GetRelicMergePlan(data, selectedKey)
				if plan.maxed then
					forgeBtn.SetText("MAX")
					forgeBtn.SetEnabled(false)
				elseif not plan.ok then
					-- what is SHORT, in the currency that is short: copies if dust could not cover it
					forgeBtn.SetText(("%d\u{2728}"):format(plan.dustNeed - plan.dustHave))
					forgeBtn.SetEnabled(false)
				else
					local cost = GameConfig.ScaleReward(GameConfig.GetRelicMergeCost(plan.level), data)
					forgeBtn.SetText(plan.dustNeed > 0 and ("FORGE %d\u{2728}"):format(plan.dustNeed) or "FORGE")
					forgeBtn.SetEnabled((data.DNA or 0) >= cost, FORGE_ON)
				end
			else
				detail.Visible = false
			end
		end

		-- --- the header subtitle: what the four sockets are actually paying, right now
		local ownedCount = GameConfig.CountOwnedRelics(data)
		local income = math.floor((GameConfig.GetRelicMult(data, "incomeMult") - 1) * 100 + 0.5)
		local damage = math.floor((GameConfig.GetRelicMult(data, "damageMult") - 1) * 100 + 0.5)
		local luckAdd = math.floor(GameConfig.GetRelicAdd(data, "luckAdd") + 0.5)
		local bits = {}
		if income > 0 then table.insert(bits, ("+%d%% DNA"):format(income)) end
		if damage > 0 then table.insert(bits, ("+%d%% DMG"):format(damage)) end
		if luckAdd > 0 then table.insert(bits, ("+%d Luck"):format(luckAdd)) end
		local familySets = GameConfig.GetRelicFamilySets(data)
		for family in pairs(familySets) do table.insert(bits, family .. " set!") end
		-- The dust is in the subtitle rather than on a pill of its own because it is spent in exactly
		-- one place -- the FORGE button two rows down -- and a currency shown next to the thing it
		-- buys does not need a home in the HUD.
		local dust = math.floor(tonumber(data.RelicDust) or 0)
		if dust > 0 then table.insert(bits, ("%d\u{2728}"):format(dust)) end

		-- TWO COUNTS, and they are deliberately not added together. The fifteen are the stat layer
		-- and the two hundred are the collection; one "37/215" would be a number about nothing.
		local held = GameConfig.CountSetRelicsHeld(data)
		local doneSets = GameConfig.CountCompletedRelicSets(data)
		-- "1 sets" -- caught by the capture, not by a probe, which is the whole reason this row
		-- carries a photograph as its check. Every other count in this subtitle is a ratio and
		-- reads fine at one; this is the only bare noun in the line.
		local head = (doneSets > 0)
			and ("%d/%d  \u{00B7}  %d/%d relics  \u{00B7}  %d %s")
				:format(ownedCount, #GameConfig.Relics, held, GameConfig.SetRelicTotal,
					doneSets, doneSets == 1 and "set" or "sets")
			or ("%d/%d  \u{00B7}  %d/%d relics"):format(ownedCount, #GameConfig.Relics, held, GameConfig.SetRelicTotal)
		subtitle.Text = (#bits > 0) and ("%s  \u{00B7}  %s"):format(head, table.concat(bits, "  \u{00B7}  "))
			or head
	end

	-- ===== HOW THIS PANEL LEARNS THAT SOMETHING CHANGED =====
	--
	-- TWO WAYS IN, and neither is a `DataUpdate` subscription of its own. `MainUI` owns the single
	-- `Remotes.DataUpdate.OnClientEvent` handler for the whole HUD and calls every panel's refresh
	-- from inside it; a second listener here would be a second source of truth about when the data
	-- is current, and the two would drift the first time one of them was reordered. So:
	--
	--   1. `hud.refreshRelicsPanel` -- published for MainUI to call on every push. That is the path
	--      an equip, an unequip, a merge and a chest all arrive by, because every one of them ends
	--      in `PlayerDataService.PushToClient`.
	--   2. the ticker below -- for the ONE thing no push can tell us about, which is a clock.
	--
	-- ===== AND WHY THE TICKER NO LONGER REDRAWS THE PANEL =====
	--
	-- It used to call the full `refresh` once a second while visible, which was defensible at
	-- fifteen tiles and is not at 215: the free-chest caption is the only thing on this panel that
	-- changes without a push, and rewriting every socket, tab and tile to move one countdown is
	-- ~200 property writes a second to update two characters of text.
	--
	-- So the ticker calls `refreshChest` alone, and everything else waits for the data to change.
	-- The dirty flag is what keeps that honest: a push that arrives while the panel is CLOSED sets
	-- the flag instead of drawing, and opening the panel spends it. Without that, a player who
	-- collects three relics with the panel shut opens it onto the state it had when they closed it.
	local dirty = true

	hud.refreshRelicsPanel = function()
		if panel.Visible then
			dirty = false
			refresh()
		else
			dirty = true
		end
	end

	panel:GetPropertyChangedSignal("Visible"):Connect(function()
		if panel.Visible and dirty then
			dirty = false
			refresh()
		end
	end)

	-- The Forge page is built and shown up front, so the panel opens on exactly what it opened on
	-- before this row -- the fifteen. The twenty collection pages cost nothing until one is opened.
	showTab("forge")

	task.spawn(function()
		while true do
			task.wait(1)
			if panel.Visible then
				local data = hud.getData and hud.getData()
				if data and GameConfig.IsRelicForgeUnlocked(data) then refreshChest(data) end
			end
		end
	end)
end
