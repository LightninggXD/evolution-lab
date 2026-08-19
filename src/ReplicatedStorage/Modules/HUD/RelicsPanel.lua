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
	sockets.Position = UDim2.new(0, 16, 0, 150)
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
	chestRow.Position = UDim2.new(0, 16, 0, 272)
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

	-- ===== THE COLLECTION =====
	--
	-- A section rule, then the grid. The rule is the same centred-grey-word-between-two-lines the
	-- Potions panel uses, built the same way, so the two shelves read as one cupboard.
	local head = Instance.new("TextLabel")
	head.Name = "Section_Collection"
	head.Size = UDim2.new(1, -32, 0, 26)
	head.Position = UDim2.new(0, 16, 0, 330)
	head.BackgroundTransparency = 1
	head.Text = "Collection"
	head.ZIndex = baseZ
	head.Parent = panel
	themeLabel(head, 22, INK_ON_WHITE)
	for _, side in ipairs({ -1, 1 }) do
		local rule = Instance.new("Frame")
		rule.Name = "Rule"
		rule.Size = UDim2.new(0.30, 0, 0, 3)
		rule.Position = UDim2.new(side < 0 and 0 or 0.70, 0, 0.5, -1)
		rule.BackgroundColor3 = Color3.fromRGB(224, 228, 238)
		rule.BorderSizePixel = 0
		rule.ZIndex = head.ZIndex
		rule.Parent = head
	end

	local grid = Instance.new("ScrollingFrame")
	grid.Name = "RelicGrid"
	grid.Size = UDim2.new(1, -32, 1, -378)
	grid.Position = UDim2.new(0, 16, 0, 362)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 6
	grid.ScrollBarImageColor3 = Color3.fromRGB(180, 186, 208)
	grid.ClipsDescendants = true
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new(0, 0, 0, 0)
	grid.ZIndex = baseZ
	grid.Parent = panel

	-- 5 x 84 + 4 x 8 of padding = 452 against the 488 the panel's margins leave, and the scrollbar
	-- and the tiles' own outlines take the rest. Five columns puts the fifteen in exactly three
	-- rows, which is the whole roster visible at once on a desktop -- the collection should not need
	-- scrolling to be understood, only to be reached on a phone.
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0, 84, 0, 84)
	gridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid

	do
		-- Room for the tiles' outlines, which are drawn OUTSIDE their bounds against a frame that
		-- clips -- the fault `ScrollingPanelBuilder` and the potion shelf both carry the same padding
		-- for. Asymmetric on purpose: the scrollbar owns the right edge whatever the padding says.
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 4)
		pad.PaddingBottom = UDim.new(0, 8)
		pad.PaddingLeft = UDim.new(0, 4)
		pad.PaddingRight = UDim.new(0, 12)
		pad.Parent = grid
	end

	-- ===== THE LOCKED PANEL =====
	--
	-- Shown INSTEAD of everything above until stage 10. Not a toast and not a greyed-out panel: a
	-- player who opens a screen full of dark sockets and an unreadable grid has been shown a broken
	-- room, where one line telling them when the door opens is the true statement.
	local locked = Instance.new("Frame")
	locked.Name = "LockedState"
	locked.Size = UDim2.new(1, -32, 1, -166)
	locked.Position = UDim2.new(0, 16, 0, 150)
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

	-- ===== THE TILES =====
	--
	-- Fifteen, built once, in the config's own order -- which is rarity ascending, so the grid reads
	-- as a ladder left-to-right and top-to-bottom and an unowned Mythic sits alone in the last cell
	-- where it is conspicuous. Sorting by owned-first was considered and rejected: a collection whose
	-- cells MOVE as you fill it never becomes a shape you can remember.
	local tileRefs = {}
	for i, relic in ipairs(GameConfig.Relics) do
		local rarity = relic.rarityDef
		local tile, setColors = CardKit.Card(grid, {
			name = "Relic_" .. relic.key,
			size = UDim2.new(0, 84, 0, 84),
			layoutOrder = i,
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
		art.Image = IconLibrary.Id[relic.icon] or ""
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

		tileRefs[relic.key] = {
			relic = relic, tile = tile, setColors = setColors, art = art,
			dupe = dupe, dupeLabel = dupeLabel,
			levelPip = levelPip, levelLabel = levelLabel, tick = tick, hit = hit,
		}
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

	local selectedKey = nil

	local _, equipBtn = CardKit.Button(detailCard, {
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

	local _, forgeBtn = CardKit.Button(detailCard, {
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
	local function refresh()
		local data = hud.getData and hud.getData()
		if not data then return end

		local open = GameConfig.IsRelicForgeUnlocked(data)
		locked.Visible = not open
		sockets.Visible = open
		chestRow.Visible = open
		head.Visible = open
		grid.Visible = open
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

		-- --- the chest buttons
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

		-- --- the grid
		for key, refs in pairs(tileRefs) do
			local entry = owned[key]
			local copies = (type(entry) == "table" and entry.copies) or 0
			local level = (type(entry) == "table" and entry.level) or 1
			local has = copies > 0

			-- AN UNOWNED RELIC IS A SILHOUETTE, NOT A HIDDEN ONE. The grid doubles as the reference
			-- for what exists -- the same argument the potion shelf makes for listing bottles you do
			-- not hold -- and a collection you cannot see the shape of is not a collection.
			refs.setColors(has and { refs.relic.rarityDef.color, refs.relic.rarityDef.deep }
				or { Color3.fromRGB(206, 210, 224), Color3.fromRGB(150, 155, 175) })
			refs.art.ImageTransparency = has and 0 or 0.72
			refs.dupe.Visible = copies > 1
			refs.dupeLabel.Text = "x" .. copies
			refs.levelPip.Visible = level > 1
			refs.levelLabel.Text = ("Lv.%d"):format(level)
			refs.tick.Visible = equippedLookup[key] == true
		end

		-- --- the detail strip
		local relic = selectedKey and GameConfig.GetRelic(selectedKey)
		local entry = selectedKey and owned[selectedKey]
		if relic and entry then
			local level = (type(entry) == "table" and entry.level) or 1
			local copies = (type(entry) == "table" and entry.copies) or 0
			detail.Visible = true
			setDetailColors({ relic.rarityDef.color, relic.rarityDef.deep })
			detailArt.Image = IconLibrary.Id[relic.icon] or ""
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

			-- THE FORGE BUTTON SAYS WHY IT IS OFF. Three different refusals -- maxed, not enough
			-- copies, not enough DNA -- and a single greyed button that means all three is a button
			-- the player pokes at. `CanMergeRelic` is the config's own test, so this cannot disagree
			-- with what the server will do when the button IS pressed.
			if level >= GameConfig.RelicMaxLevel then
				forgeBtn.SetText("MAX")
				forgeBtn.SetEnabled(false)
			elseif not GameConfig.CanMergeRelic(data, selectedKey) then
				forgeBtn.SetText(("%d/%d"):format(copies, 1 + GameConfig.RelicMergeCopies))
				forgeBtn.SetEnabled(false)
			else
				local cost = GameConfig.ScaleReward(GameConfig.GetRelicMergeCost(level), data)
				forgeBtn.SetText("FORGE")
				forgeBtn.SetEnabled((data.DNA or 0) >= cost, FORGE_ON)
			end
		else
			detail.Visible = false
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
		local sets = GameConfig.GetRelicSets(data)
		for family in pairs(sets) do table.insert(bits, family .. " set!") end
		subtitle.Text = (#bits > 0)
			and ("%d/%d  \u{00B7}  %s"):format(ownedCount, #GameConfig.Relics, table.concat(bits, "  \u{00B7}  "))
			or ("%d/%d collected  \u{00B7}  nothing equipped"):format(ownedCount, #GameConfig.Relics)
	end

	-- Selecting is client-only state, so it writes `selectedKey` and re-runs the same refresh
	-- everything else does rather than having its own draw path -- one function that renders the
	-- panel, however it was provoked.
	for key, refs in pairs(tileRefs) do
		refs.hit.MouseButton1Click:Connect(function()
			local data = hud.getData and hud.getData()
			if not (data and data.Relics and data.Relics[key]) then return end
			-- tapping the selected tile again closes the strip, which is the only way to dismiss it
			selectedKey = (selectedKey == key) and nil or key
			refresh()
		end)
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
	-- The free-chest caption counts down, and nothing fires while it does. Guarded on
	-- `panel.Visible`, which is the rule this HUD follows everywhere: refreshing a hidden panel is
	-- the cost this game already has twenty of, and this one would otherwise re-render fifteen tiles
	-- once a second forever behind a closed door.
	hud.refreshRelicsPanel = refresh

	task.spawn(function()
		while true do
			task.wait(1)
			if panel.Visible then refresh() end
		end
	end)
end
