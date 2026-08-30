-- RelicsPanel -- the Relic Forge: a slot constellation, twenty-one collections, one chest.
--
-- ===== 34.57 REBUILT THIS PANEL TO THE OWNER'S REFERENCE (2026-08-29) =====
--
-- She sent a capture and it is a TWO-COLUMN screen, not the three horizontal bands this file drew
-- for a year. Left: the equipped slots arranged in a ring on a purple field, an extra-slots block
-- under it, and the chest. Right: the owned list filling the height, an action row over it, and a
-- backpack counter in the bottom corner. Everything below follows that division.
--
-- THE PANEL IS STILL 520 x 528 AND THAT IS NOT A PREFERENCE. `Modules.HUD.InventoryTabs` drops the
-- five-tab strip (Pets / Potions / Relics / Trails / Sword) into this panel RIGHT-ALIGNED at
-- `UDim2.new(1, -16, 0, 52)` with a fixed 474 px width. A panel of a different width puts the same
-- five tabs somewhere else on screen, so the strip appears to jump when you change tab -- which is
-- the whole reason this size was matched to the Inventory panel in the first place. So the
-- reference's shape is fitted INTO 520 x 528 rather than the panel being grown to suit it.
--
-- THE STRIP OWNS y 52..90 ACROSS THE FULL WIDTH. Nothing this file draws may start above y = 98.
--
-- ===== THE GEOMETRY, WRITTEN DOWN SO THE NEXT PASS DOES NOT RE-DERIVE IT =====
--
--   left column   x 16,  width 212   (16 .. 228)
--   gutter                     12
--   right column  x 240, width 264   (240 .. 504)
--   content top   y 98,  bottom y 512 (16 px margin, as every other panel)
--
--   LEFT   constellation  98 .. 310   (212 square: a diamond of four 58 px slots round an orb)
--          extra slots   318 .. 400   (two chips: what opens slot 3 and slot 4)
--          chest         408 .. 512   (the 2D chest, OPEN CHEST, and the diamond buy)
--
--   RIGHT  action row     98 .. 132   (EQUIP / FORGE -- they act on the selected tile)
--          set tabs      140 .. 180
--          the list      186 .. 410
--          detail        418 .. 488   (70 tall: MEASURED, see the strip's own note)
--          backpack      492 .. 510
--
-- ===== WHAT MOVED, AND WHERE IT WENT (nothing was dropped) =====
--
--   * THE FORGE DOOR was a button inside the detail strip at the bottom of the panel. It is now the
--     right half of the ACTION ROW over the list, where the reference puts its `Delete`. It still
--     needs a selection first, so forging is still a deliberate two-step -- it is simply no longer
--     hidden under the fold.
--   * THE PER-SET COUNTERS are unchanged: every zone tab still carries its own `1F319 3/10`, which
--     is what makes the strip double as the progress readout.
--   * THE GLOBAL COUNTERS (owned/15, held/200, completed sets, income, damage, luck, dust) are
--     unchanged in the header subtitle.
--   * THE OPEN PAGE'S COUNT is additionally the BACKPACK COUNTER bottom-right -- the reference's
--     `0/100`. It is the page you are looking at, never a sum of the two layers: this file's own
--     rule is that "37/215" would be a number about nothing, because the fifteen are the stat layer
--     and the two hundred are the collection.
--
-- ===== 34.56, AND THE THING THE ROADMAP ROW GOT WRONG =====
--
-- The row says the gate is in this panel and that there is "no per-relic flag" on the server. There
-- IS one, and it is load-bearing:
--
--   * `GameConfig.Relics` -- FIFTEEN relics, saved in `data.Relics`, resolved by `GameConfig.GetRelic`.
--     These are the stat layer. They are worn, levelled and forged.
--   * `GameConfig.SetRelicsByKey` -- TWO HUNDRED relics, saved in `data.SetRelics`, every one of them
--     carrying `collection = true`, resolved by `GameConfig.GetSetRelic`.
--
-- `RelicService.HandleEquip` begins `local relic = GameConfig.GetRelic(key); if not relic then return end`
-- -- and `GetRelic` reads `RelicsByKey`, which the two hundred are not in. So a collection relic sent
-- to `EquipRelic` is dropped SILENTLY, with no refusal toast. Wiring an EQUIP button onto the
-- collection pages would therefore not equip anything; it would draw two hundred buttons that do
-- nothing at all, which is strictly worse than the state that produced the bug report.
--
-- `GameConfig.Relics`' own header states the reason in a balance argument: the pool is its own cap,
-- there is exactly one Mythic, and 200 equippable relics would put four Mythics in four slots and
-- raise the income ceiling about 1.6x. Two save fields is the mechanical guarantee behind that.
--
-- SO WHAT IS ACTUALLY FIXED HERE IS THE SILENCE. Her complaint -- "only the ones in the Forge option
-- can be equipped" -- is a correct observation of a real boundary that the panel never named. Before
-- this row a collection relic simply had NO buttons: they were hidden, and a missing control is
-- indistinguishable from a broken one. Now:
--
--   1. The action row is always present, so the verbs never move or vanish.
--   2. Selecting a collection relic shows EQUIP disabled and captioned `SET BONUS`, with the detail
--      line saying in words that it pays as a set and is never worn.
--   3. Selecting a forge relic while every slot is full captions the button `SLOTS FULL` instead of
--      greying it wordlessly -- the cap is real and deliberate, and a cap that says its own name is
--      not the same experience as a dead button.
--   4. An empty unlocked slot is now a button that jumps to the Forge page, which is the only page
--      holding anything that fits in it.
--
-- Making the two hundred genuinely wearable is a GameConfig + RelicService decision that voids a
-- documented cap. It cannot be done from this file and it should not be done quietly.
--
-- ===== ONE REBUILD, THEN ONLY WRITES =====
--
-- Every socket, chip and tile is built ONCE and refresh only writes text, colour and visibility.
-- Pages are still lazy -- one per tab, built the first time that tab is opened -- so the collection
-- layer costs one zone at a time rather than 215 tiles on a require.
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

	-- See the header: 520 x 528 is fixed by the five-tab strip, not chosen.
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

	-- The two columns and the content band, in one place. Every `y` below is measured against these.
	local LEFT_X, LEFT_W = 16, 212
	local RIGHT_X, RIGHT_W = 240, 264

	-- ===== FORWARD DECLARATIONS =====
	--
	-- Every click handler built below is a closure over these, and several of them are built before
	-- the function they call exists. Declared once here so that `function refresh()` and
	-- `function showTab()` further down ASSIGN to these locals rather than creating new ones -- a
	-- `local function showTab` down there would shadow this and the sockets would call a nil.
	local refresh, showTab
	-- Selection is client-only state. `selectedKey` is the key and `selectedIsSet` says which of the
	-- two layers it belongs to, because the two live in different save fields and a key alone can no
	-- longer say which table to look in.
	local selectedKey, selectedIsSet = nil, false
	local pages, tabRefs = {}, {}
	local currentTab = "forge"

	-- =================================================================================
	-- LEFT COLUMN 1 OF 3: THE SLOT CONSTELLATION
	-- =================================================================================
	--
	-- Her reference draws the equipped relics in a ring around a central motif on a purple field,
	-- and four is exactly the number that shape wants: `GameConfig.RelicMaxSlots` is 4, so the ring
	-- is a DIAMOND -- one slot on each of the four compass points around the orb.
	--
	-- THE ORDER IS left, right, top, bottom AND THAT IS DELIBERATE. `GameConfig.RelicBaseSlots` is 2
	-- and the third and fourth open at Rebirth 1 and Rebirth 2, so slots 1 and 2 are the pair every
	-- player has. Putting them on the horizontal axis makes the starting state a symmetrical pair
	-- that GROWS into a diamond; ordering them clockwise from the top would make a new player's two
	-- slots read as a lopsided corner with two holes in it.
	local FIELD = { Color3.fromRGB(152, 112, 238), Color3.fromRGB(84, 48, 160) }
	-- An empty-but-unlocked slot is drawn PLAIN, which on a purple field means a pale lilac well:
	-- it has to read as "nothing in it yet", not as a second kind of locked.
	local EMPTY_SOCKET = { Color3.fromRGB(200, 182, 248), Color3.fromRGB(128, 100, 202) }
	local LOCKED_SOCKET = { Color3.fromRGB(120, 114, 148), Color3.fromRGB(62, 58, 86) }

	local field = CardKit.Card(panel, {
		name = "Constellation",
		size = UDim2.new(0, LEFT_W, 0, 212),
		position = UDim2.new(0, LEFT_X, 0, 98),
		colors = FIELD,
		radius = 18,
		studTransparency = 0.8,
		zIndex = baseZ,
	})

	-- The central motif. It is the same orb the panel's own title carries, which is what ties the
	-- ring to the screen it is on rather than making it a decoration that could be anything.
	local orb = Instance.new("ImageLabel")
	orb.Name = "Orb"
	orb.Size = UDim2.new(0, 56, 0, 56)
	orb.Position = UDim2.new(0.5, 0, 0.5, 0)
	orb.AnchorPoint = Vector2.new(0.5, 0.5)
	orb.BackgroundTransparency = 1
	orb.Image = IconLibrary.Resolve("\u{1F52E}") or ""
	orb.ScaleType = Enum.ScaleType.Fit
	orb.ZIndex = baseZ + 2
	orb.Parent = field

	-- "2/4" in the corner the diamond leaves empty. The four slots sit on the compass points, so all
	-- four corners of the 212 px square are free and this costs no geometry.
	local _, wornLabel = CardKit.Pill(field, {
		name = "Worn",
		text = "0/4",
		size = UDim2.new(0, 46, 0, 20),
		position = UDim2.new(0, 8, 0, 8),
		textSize = 13,
		zIndex = baseZ + 3,
	})

	-- centre of each slot inside the 212 px field, in the order described above
	local SLOT_SPOTS = {
		{ 38, 106 },    -- 1: left    (base slot)
		{ 174, 106 },   -- 2: right   (base slot)
		{ 106, 38 },    -- 3: top     (Rebirth 1)
		{ 106, 174 },   -- 4: bottom  (Rebirth 2)
	}

	local socketRefs = {}
	for i = 1, GameConfig.RelicMaxSlots do
		local spot = SLOT_SPOTS[i]
		local tile, setTileColors = CardKit.Card(field, {
			name = "Socket" .. i,
			-- 62, NOT 58: the locked slot has to carry "Rebirth 1" along its bottom edge, which at
			-- 10 px FredokaOne measures about 52 px, and a 58 px tile leaves 54 px inside its own
			-- padding. Four pixels of slack is not a margin. At 62 the diamond still clears the
			-- field: a slot centred at x = 38 spans 7..69 and its outline draws to 3..73, inside the
			-- 212 px card, and the orb at the centre still has 9 px of air around it.
			size = UDim2.new(0, 62, 0, 62),
			position = UDim2.new(0, spot[1], 0, spot[2]),
			anchorPoint = Vector2.new(0.5, 0.5),
			colors = EMPTY_SOCKET,
			radius = 14,
			studTransparency = 0.78,
			zIndex = baseZ + 1,
		})

		-- The relic's own drawing, hidden until something is worn. An `ImageLabel` with `Image = ""`
		-- is not invisible -- it is a hole the rest of the tile is laid out around -- so it is
		-- explicitly toggled rather than left blank.
		local art = Instance.new("ImageLabel")
		art.Name = "Art"
		art.Size = UDim2.new(0, 40, 0, 40)
		art.Position = UDim2.new(0.5, 0, 0.5, -3)
		art.AnchorPoint = Vector2.new(0.5, 0.5)
		art.BackgroundTransparency = 1
		art.ScaleType = Enum.ScaleType.Fit
		art.Visible = false
		art.ZIndex = baseZ + 3
		art.Parent = tile

		-- The "?" an empty socket shows, and the padlock a locked one shows instead. One label, two
		-- glyphs: they are the same size and sit in the same place now that the socket is square, and
		-- two labels toggling against each other was one more thing to get out of step.
		local mark = CardKit.Text(tile, {
			name = "Mark",
			text = "?",
			size = UDim2.new(1, 0, 1, 0),
			textSize = 26,
			color = Color3.fromRGB(250, 248, 255),
			xAlign = "Center",
			zIndex = baseZ + 3,
			strokeThickness = 3,
		})

		-- THE PRICE LINE. Her reference shows a locked slot carrying its own price ON the slot, which
		-- is the right instinct: a lock that does not say what opens it is a refusal. In this game
		-- slots are not bought -- `GetMaxEquippedRelics` reads `data.Rebirths` and nothing else -- so
		-- what goes here is the REQUIREMENT, in the same place a price would go, read off the config
		-- so moving the ladder moves this line.
		local costLine = CardKit.Text(tile, {
			name = "Cost",
			text = "",
			size = UDim2.new(1, -4, 0, 13),
			position = UDim2.new(0, 2, 1, -15),
			textSize = 10,
			color = Color3.fromRGB(232, 234, 250),
			xAlign = "Center",
			zIndex = baseZ + 3,
			strokeThickness = 2,
		})

		-- The level pip, only on a socket wearing something above Lv.1. A pip reading "Lv.1" on every
		-- relic is noise: level 1 is the default and says nothing.
		local pip, pipLabel = CardKit.Pill(tile, {
			name = "Level",
			text = "",
			size = UDim2.new(0, 36, 0, 17),
			position = UDim2.new(0.5, -18, 1, -20),
			textSize = 11,
			zIndex = baseZ + 4,
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
		hit.ZIndex = baseZ + 5
		hit.Parent = tile

		local refs = {
			tile = tile, setColors = setTileColors, art = art, mark = mark,
			cost = costLine, pip = pip, pipLabel = pipLabel, hit = hit,
			key = nil, unlocked = false,
		}
		hit.MouseButton1Click:Connect(function()
			if refs.key then
				Remotes.UnequipRelic:FireServer(refs.key)
			elseif refs.unlocked then
				-- 34.56: AN EMPTY SLOT IS A ROUTE, NOT A DEAD TILE. The only relics that fit in it are
				-- the fifteen on the Forge page, so tapping the hole goes there. A player who taps an
				-- empty socket is asking "how do I fill this", and the old panel answered nothing.
				if showTab then showTab("forge") end
			end
		end)
		socketRefs[i] = refs
	end

	-- =================================================================================
	-- LEFT COLUMN 2 OF 3: THE EXTRA-SLOTS BLOCK
	-- =================================================================================
	--
	-- The reference calls this "Premium Relic Slots" and prices the first one in Robux. THERE IS NO
	-- SUCH PRODUCT IN THIS GAME and one cannot be invented from a client module: `GameConfig.RobuxShop`
	-- has no relic row, `GetMaxEquippedRelics` reads `data.Rebirths` alone, and `RelicMaxSlots` is a
	-- hard 4. A Robux price drawn here would be a button with no receipt behind it -- and a product
	-- remote fired at a product that does not exist fails SILENTLY, which is the worst version of
	-- that mistake.
	--
	-- So the block keeps the reference's PLACE and its job -- "here is how the ring gets bigger" --
	-- and states the real currency, which is a rebirth. If a Robux slot product ever ships, this is
	-- the block it lands in and the only thing that changes is the chip's caption.
	local extra = CardKit.Card(panel, {
		name = "ExtraSlots",
		size = UDim2.new(0, LEFT_W, 0, 82),
		position = UDim2.new(0, LEFT_X, 0, 318),
		colors = { Color3.fromRGB(236, 232, 252), Color3.fromRGB(202, 194, 238) },
		radius = 14,
		studTransparency = 0.92,
		zIndex = baseZ,
	})

	CardKit.Text(extra, {
		name = "Title",
		text = "EXTRA RELIC SLOTS",
		size = UDim2.new(1, -12, 0, 18),
		position = UDim2.new(0, 6, 0, 6),
		textSize = 13,
		color = UITheme.Color.Ink,
		xAlign = "Center",
		zIndex = baseZ + 2,
		strokeThickness = 0,
	})

	local CHIP_OPEN = { Color3.fromRGB(150, 245, 190), Color3.fromRGB(24, 190, 110) }
	local CHIP_SHUT = { Color3.fromRGB(198, 200, 220), Color3.fromRGB(140, 144, 172) }

	-- One chip per slot ABOVE the base pair. Two rows inside a 98 px chip rather than one line
	-- reading "1F512 Rebirth 1": that string is twelve characters plus a glyph at 12 px, which
	-- measures within a pixel or two of the chip's inside width -- and a label that is one character
	-- from truncating still reports `TextFits = true`, so the flag would never have caught it.
	local chipRefs = {}
	for i = GameConfig.RelicBaseSlots + 1, GameConfig.RelicMaxSlots do
		local n = i - GameConfig.RelicBaseSlots
		local chip, setChipColors = CardKit.Card(extra, {
			name = "Chip" .. i,
			size = UDim2.new(0, 98, 0, 44),
			position = UDim2.new(0, 4 + (n - 1) * 106, 0, 30),
			colors = CHIP_SHUT,
			radius = 10,
			studTransparency = 0.9,
			zIndex = baseZ + 2,
		})
		local chipMark = CardKit.Text(chip, {
			name = "Mark",
			text = "\u{1F512}",
			size = UDim2.new(1, -6, 0, 18),
			position = UDim2.new(0, 3, 0, 3),
			textSize = 15,
			xAlign = "Center",
			zIndex = baseZ + 3,
			strokeThickness = 2,
		})
		local chipText = CardKit.Text(chip, {
			name = "Cost",
			text = GameConfig.GetRelicSlotRequirement(i) or "",
			size = UDim2.new(1, -6, 0, 16),
			position = UDim2.new(0, 3, 0, 22),
			textSize = 11,
			xAlign = "Center",
			zIndex = baseZ + 3,
			strokeThickness = 2,
		})
		chipRefs[i] = { setColors = setChipColors, mark = chipMark, text = chipText }
	end

	-- =================================================================================
	-- LEFT COLUMN 3 OF 3: THE CHEST
	-- =================================================================================
	--
	-- 34.55 deleted the free-chest timer, so there is no countdown and never will be again: a relic
	-- arrives from a CHEST or from the diamond buy, and nothing else. `"free"` is refused by the
	-- server now, so the left button sends `"banked"` or is simply dark.
	--
	-- ===== AND THIS IS WHERE THE 2D CHEST GOES (34.58, wired in 34.54) =====
	--
	-- She inserted a gold/red chest icon and wanted it drawn on an items-style tab. This card is the
	-- natural home for it -- it is the only place in the game where a chest is opened from a screen
	-- -- and the icon is one `ImageLabel` named `ChestIcon`. It drew the GIFT emoji through
	-- `IconLibrary` as a placeholder until her art had somewhere CLIENT-READABLE to live; 34.54 put
	-- the two decal ids on `GameConfig.RelicChestIcon` (a client cannot require `ChestService`, where
	-- they used to sit) and this is the one line that note was promising.
	--
	-- THE GIFT GLYPH IS STILL THE FALLBACK, not a raw id with no net: an id that fails to resolve
	-- gives an empty Image, which is a HOLE in the middle of a card rather than a blank.
	local chestCard = CardKit.Card(panel, {
		name = "ChestCard",
		size = UDim2.new(0, LEFT_W, 0, 104),
		position = UDim2.new(0, LEFT_X, 0, 408),
		colors = { Color3.fromRGB(255, 226, 150), Color3.fromRGB(232, 160, 32) },
		radius = 14,
		studTransparency = 0.86,
		zIndex = baseZ,
	})

	local chestIcon = Instance.new("ImageLabel")
	chestIcon.Name = "ChestIcon"
	chestIcon.Size = UDim2.new(0, 40, 0, 40)
	chestIcon.Position = UDim2.new(0, 10, 0, 8)
	chestIcon.BackgroundTransparency = 1
	chestIcon.Image = GameConfig.RelicChestIcon or IconLibrary.Resolve("\u{1F381}") or ""
	chestIcon.ScaleType = Enum.ScaleType.Fit
	chestIcon.ZIndex = baseZ + 2
	chestIcon.Parent = chestCard

	CardKit.Text(chestCard, {
		name = "Title",
		text = "RELIC CHEST",
		size = UDim2.new(1, -64, 0, 20),
		position = UDim2.new(0, 56, 0, 10),
		textSize = 16,
		zIndex = baseZ + 2,
		strokeThickness = 3,
	})

	CardKit.Text(chestCard, {
		name = "Blurb",
		text = "Found in the world, or bought.",
		size = UDim2.new(1, -64, 0, 16),
		position = UDim2.new(0, 56, 0, 30),
		textSize = 11,
		color = Color3.fromRGB(252, 248, 236),
		zIndex = baseZ + 2,
		strokeThickness = 2,
	})

	-- Gold, because a banked chest is something already won rather than something being waited for.
	local BANKED = { Color3.fromRGB(255, 246, 190), Color3.fromRGB(238, 176, 30) }
	-- The grey the button wears when there is nothing to open. It is not a COUNTDOWN state -- 34.55
	-- deleted the free timer -- it is "you have no chest", which is a different sentence.
	local NO_CHEST = { Color3.fromRGB(178, 184, 204), Color3.fromRGB(120, 126, 150) }
	local DIAMOND_BUY = { Color3.fromRGB(175, 245, 255), Color3.fromRGB(30, 170, 215) }

	-- Read by the callback, written by the refresh. The button's own text is not the source of
	-- truth for which remote to send -- a caption is a picture of the state, not the state.
	local bankedChests = 0

	local _, openChest = CardKit.Button(chestCard, {
		name = "OpenChest",
		text = "OPEN CHEST",
		size = UDim2.new(0, 118, 0, 40),
		position = UDim2.new(0, 8, 0, 56),
		colors = BANKED,
		textSize = 16,
		zIndex = baseZ + 2,
		callback = function()
			if bankedChests <= 0 then return end
			Remotes.OpenRelicChest:FireServer("banked")
		end,
	})

	-- THE CAPTION IS SET ON ITS OWN LINE AND THE PRICE IS ITS OWN CHILD. `CardKit.Button` takes a
	-- table so it cannot suffer the `styleButton(btn, colour, "40 gem")` fault that blanked every
	-- price in the shop -- but the diamond is drawn rather than typed for the reason `IconLibrary`
	-- exists at all: an emoji in a TextButton is four different pictures on four platforms.
	local buyInst, buyChest = CardKit.Button(chestCard, {
		name = "BuyChest",
		text = "",
		size = UDim2.new(0, 70, 0, 40),
		position = UDim2.new(0, 134, 0, 56),
		colors = DIAMOND_BUY,
		textSize = 16,
		zIndex = baseZ + 2,
		callback = function()
			Remotes.OpenRelicChest:FireServer("diamonds")
		end,
	})

	CardKit.Text(buyInst, {
		name = "Price",
		text = tostring(GameConfig.RelicChestDiamondCost),
		size = UDim2.new(1, -30, 1, 0),
		position = UDim2.new(0, 6, 0, 0),
		textSize = 17,
		xAlign = "Right",
		zIndex = baseZ + 3,
		strokeThickness = 3,
	})

	local gem = Instance.new("ImageLabel")
	gem.Name = "Gem"
	gem.Size = UDim2.new(0, 18, 0, 18)
	gem.Position = UDim2.new(1, -24, 0.5, -9)
	gem.BackgroundTransparency = 1
	gem.Image = IconLibrary.Resolve("\u{1F48E}") or ""
	gem.ScaleType = Enum.ScaleType.Fit
	gem.ZIndex = baseZ + 3
	gem.Parent = buyInst

	-- =================================================================================
	-- RIGHT COLUMN 1 OF 5: THE ACTION ROW
	-- =================================================================================
	--
	-- Her reference puts a `Delete` button over the list. THIS GAME HAS NO DELETE: `RelicService`
	-- exposes exactly four remotes -- `OpenRelicChest`, `EquipRelic`, `UnequipRelic`, `MergeRelic` --
	-- and nothing anywhere destroys a relic a player owns. Drawing a Delete would be a button that
	-- either does nothing or needs a server that has not been written and a confirm that has not
	-- been designed, over a permanent, tradeable, rebirth-proof item. So the row keeps the
	-- reference's PLACE and carries the two verbs this panel actually has.
	--
	-- BOTH ARE ALWAYS PRESENT AND NEVER HIDDEN. That is the 34.56 fix: the old panel hid EQUIP and
	-- FORGE entirely for a collection relic, and a missing control cannot be told apart from a
	-- broken one -- which is exactly the report this row came from. They are disabled and CAPTIONED
	-- instead, so the panel says which rule stopped it.
	local actionRow = Instance.new("Frame")
	actionRow.Name = "ActionRow"
	actionRow.Size = UDim2.new(0, RIGHT_W, 0, 34)
	actionRow.Position = UDim2.new(0, RIGHT_X, 0, 98)
	actionRow.BackgroundTransparency = 1
	actionRow.ZIndex = baseZ
	actionRow.Parent = panel

	local EQUIP_ON = { Color3.fromRGB(120, 255, 170), Color3.fromRGB(20, 200, 100) }
	local FORGE_ON = { Color3.fromRGB(255, 214, 120), Color3.fromRGB(240, 165, 20) }

	local _, equipBtn = CardKit.Button(actionRow, {
		name = "Equip",
		text = "EQUIP",
		size = UDim2.new(0, 128, 0, 34),
		position = UDim2.new(0, 0, 0, 0),
		colors = EQUIP_ON,
		textSize = 16,
		zIndex = baseZ + 1,
		callback = function()
			if not selectedKey or selectedIsSet then return end
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

	local _, forgeBtn = CardKit.Button(actionRow, {
		name = "Forge",
		text = "FORGE",
		size = UDim2.new(0, 128, 0, 34),
		position = UDim2.new(0, 136, 0, 0),
		colors = FORGE_ON,
		textSize = 16,
		zIndex = baseZ + 1,
		callback = function()
			if selectedKey and not selectedIsSet then Remotes.MergeRelic:FireServer(selectedKey) end
		end,
	})

	-- =================================================================================
	-- RIGHT COLUMN 2 OF 5: THE SET TAB STRIP
	-- =================================================================================
	--
	-- One page per zone set plus the Forge's own fifteen. Twenty-one pages of ten to fifteen tiles
	-- is a screen a player can read; 215 tiles in one scroll is a wall. Pages are LAZY -- built the
	-- first time their tab is opened and never again -- and only the OPEN page is ever written, so
	-- both the build cost and the refresh cost are bounded by what is on the screen.
	local tabs = Instance.new("ScrollingFrame")
	tabs.Name = "SetTabs"
	-- 40 FOR 28 PX TABS, and the 12 is not slack. A CardKit card draws a 3 px border stroke and a
	-- 2 px inner one OUTSIDE its own bounds, so a 28 px tab occupies 38 px of a clipping parent --
	-- the `gap of N shows as N - 15` rule the HUD layout carries, in its smallest form.
	tabs.Size = UDim2.new(0, RIGHT_W, 0, 40)
	tabs.Position = UDim2.new(0, RIGHT_X, 0, 140)
	tabs.BackgroundTransparency = 1
	tabs.BorderSizePixel = 0
	-- HORIZONTAL ONLY. `AutomaticCanvasSize` on a strip that also has a Y canvas of 0 will happily
	-- report a Y overflow from the tiles' outlines and draw a vertical bar down a 34 px row.
	tabs.ScrollingDirection = Enum.ScrollingDirection.X
	tabs.AutomaticCanvasSize = Enum.AutomaticSize.X
	tabs.CanvasSize = UDim2.new(0, 0, 0, 0)
	tabs.ScrollBarThickness = 8
	-- Grey, not white: 25.4's sweep found nine lists in this game with a white bar on a white sheet,
	-- which is a scrollbar that only exists for people who already know it is there.
	tabs.ScrollBarImageColor3 = Color3.fromRGB(168, 176, 202)
	tabs.ScrollBarImageTransparency = 0
	tabs.ClipsDescendants = true
	tabs.ZIndex = baseZ
	tabs.Parent = panel

	local tabRow = Instance.new("UIListLayout")
	tabRow.FillDirection = Enum.FillDirection.Horizontal
	tabRow.VerticalAlignment = Enum.VerticalAlignment.Top
	tabRow.SortOrder = Enum.SortOrder.LayoutOrder
	tabRow.Padding = UDim.new(0, 6)
	tabRow.Parent = tabs

	-- =================================================================================
	-- RIGHT COLUMN 3 OF 5: THE PAGES
	-- =================================================================================
	--
	-- One `ScrollingFrame` per tab, all stacked in the same place, exactly one visible. A single
	-- grid whose children were swapped would have to destroy and rebuild on every tab press -- the
	-- flicker the Pets panel carries its own note about -- and would throw away the lazy build the
	-- moment a player looked at two sets.
	local PAGE_POS = UDim2.new(0, RIGHT_X, 0, 186)
	-- 240 -> 224. The fourteen pixels went to the detail strip below, which was clipping the one
	-- line on it that carried facts rather than flavour -- see the note over `detailEffect`. A list
	-- that is one tile-row shorter loses nothing: it scrolls, and it already clipped its last row
	-- mid-tile at 240.
	local PAGE_SIZE = UDim2.new(0, RIGHT_W, 0, 224)

	-- 3 x 74 + 2 x 8 = 238 against the 242 the column leaves once the 12 px scrollbar inset and the
	-- padding are taken off. Three columns puts the fifteen in five rows and a zone's ten in four,
	-- which is one short scroll rather than a wall.
	local TILE = 74

	local function newPage(name)
		local page = Instance.new("ScrollingFrame")
		page.Name = "Page_" .. name
		page.Size = PAGE_SIZE
		page.Position = PAGE_POS
		page.BackgroundTransparency = 1
		page.BorderSizePixel = 0
		page.VerticalScrollBarInset = Enum.ScrollBarInset.Always
		page.ScrollBarThickness = 12
		-- Grey on the panel's white sheet, for the same reason as the strip above.
		page.ScrollBarImageColor3 = Color3.fromRGB(168, 176, 202)
		page.ScrollBarImageTransparency = 0
		page.ClipsDescendants = true
		-- The ENGINE measures this, not this file. Sizing a canvas off `AbsoluteContentSize` would
		-- double-count the `UIScale` that `registerPanel` attaches to every panel for phones.
		page.AutomaticCanvasSize = Enum.AutomaticSize.Y
		page.CanvasSize = UDim2.new(0, 0, 0, 0)
		page.Visible = false
		page.ZIndex = baseZ
		page.Parent = panel

		local layout = Instance.new("UIGridLayout")
		layout.CellSize = UDim2.new(0, TILE, 0, TILE)
		layout.CellPadding = UDim2.new(0, 8, 0, 8)
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = page

		-- Room for the tiles' outlines, which are drawn OUTSIDE their bounds against a frame that
		-- clips. The scrollbar owns the right edge whatever the padding says, so it is asymmetric.
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 4)
		pad.PaddingBottom = UDim.new(0, 8)
		pad.PaddingLeft = UDim.new(0, 4)
		pad.PaddingRight = UDim.new(0, 6)
		pad.Parent = page
		return page
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
			size = UDim2.new(0, TILE, 0, TILE),
			layoutOrder = order,
			colors = { rarity.color, rarity.deep },
			radius = 12,
			studTransparency = 0.86,
			zIndex = baseZ + 1,
		})

		local art = Instance.new("ImageLabel")
		art.Name = "Art"
		art.Size = UDim2.new(0, 46, 0, 46)
		art.Position = UDim2.new(0.5, 0, 0.5, -3)
		art.AnchorPoint = Vector2.new(0.5, 0.5)
		art.BackgroundTransparency = 1
		-- RESOLVED THROUGH THE FALLBACK, NEVER `Id[icon]` BARE. An unmapped name gives `Image = ""`,
		-- which is not a blank tile but a HOLE. `RelicSetFallbackIcon` is a name that has been in the
		-- library since 2026-08-10.
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
			size = UDim2.new(0, 30, 0, 18),
			position = UDim2.new(1, -33, 0, 3),
			textSize = 12,
			zIndex = baseZ + 4,
		})
		dupe.Visible = false

		local levelPip, levelLabel = CardKit.Pill(tile, {
			name = "Level",
			text = "",
			size = UDim2.new(0, 34, 0, 18),
			position = UDim2.new(0, 3, 1, -21),
			textSize = 12,
			zIndex = baseZ + 4,
		})
		levelPip.Visible = false

		-- The equipped tick. A corner mark rather than a border swap, because the border is already
		-- carrying the RARITY and a tile cannot say two things with one edge.
		local tick = CardKit.Text(tile, {
			name = "Tick",
			text = "\u{2714}",
			size = UDim2.new(0, 22, 0, 22),
			position = UDim2.new(1, -24, 1, -24),
			textSize = 18,
			color = Color3.fromRGB(140, 255, 190),
			xAlign = "Center",
			zIndex = baseZ + 4,
			strokeThickness = 3,
		})
		tick.Visible = false

		-- ===== THE SELECTION RING =====
		--
		-- The tile can already be a rarity colour, a ghost and a tick, so being SELECTED is drawn as
		-- a ring rather than as another colour swap -- otherwise the action row above would be acting
		-- on a tile carrying no mark at all, which is what makes a two-step control feel like it
		-- fired on the wrong thing.
		--
		-- IT IS ITS OWN FRAME, NOT A UISTROKE ON THE TILE. `CardKit.Card` already puts a stroke on
		-- this instance and `CardKit.Button` stacks two on its own -- a THIRD on one object is a
		-- rendering order this kit has never asked for, and a stroke that quietly does not draw is
		-- exactly the class of fault that only a capture finds. A transparent frame 3 px proud of the
		-- tile carries its own single stroke and cannot collide with anything.
		local ring = Instance.new("Frame")
		ring.Name = "SelectRing"
		ring.Size = UDim2.new(1, 6, 1, 6)
		ring.Position = UDim2.new(0, -3, 0, -3)
		ring.BackgroundTransparency = 1
		ring.BorderSizePixel = 0
		ring.Visible = false
		ring.ZIndex = baseZ + 4
		ring.Parent = tile
		CardKit.Corner(ring, 14)
		CardKit.Stroke(ring, Color3.fromRGB(255, 255, 255), 3)

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
			levelPip = levelPip, levelLabel = levelLabel, tick = tick, ring = ring, hit = hit,
		}
	end

	-- ===== BUILDING A PAGE, ONCE =====
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
				-- A TILE YOU DO NOT OWN IS NOT SELECTABLE on the Forge page, where the row's whole job
				-- is to equip and forge -- but it IS on a collection page, where "what is this thing
				-- and where does it come from" is the question a player has about the cells they have
				-- not filled yet.
				local d = hud.getData and hud.getData()
				if not d then return end
				if not isSet and not (d.Relics and d.Relics[key]) then return end
				-- tapping the selected tile again clears it, which is the only way to dismiss it
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

	function showTab(tabKey)
		local entry = ensurePage(tabKey)
		for key, other in pairs(pages) do
			if key ~= tabKey then other.page.Visible = false end
		end
		entry.page.Visible = true
		currentTab = tabKey
		-- A SELECTION DOES NOT SURVIVE A TAB CHANGE. The detail strip sits under the list and would
		-- otherwise keep describing a relic that is no longer on screen -- which reads as the strip
		-- belonging to whatever tile happens to be under it.
		selectedKey, selectedIsSet = nil, false
		refresh()
	end

	-- The Forge first, then the twenty zones in strip order, which is the order the player unlocked
	-- them in and the order every other list in this game uses. Each tab carries its zone's emoji
	-- and its own count, so the strip doubles as the per-set progress readout.
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

	-- =================================================================================
	-- RIGHT COLUMN 4 OF 5: THE EMPTY STATE
	-- =================================================================================
	--
	-- Her reference says it in as many words -- "You don't have any Relics!" -- and it is the one
	-- thing this panel never had. A grid of ghosts is a reference for what EXISTS; it is not an
	-- answer to "have I got any", and a player who opens the Forge on day one currently sees fifteen
	-- grey tiles and no sentence.
	--
	-- Parented to the PANEL rather than into the page, so it centres on the page's rectangle rather
	-- than on a canvas whose height is whatever the grid happens to be.
	local emptyState = Instance.new("Frame")
	emptyState.Name = "EmptyState"
	emptyState.Size = PAGE_SIZE
	emptyState.Position = PAGE_POS
	emptyState.BackgroundTransparency = 1
	emptyState.ZIndex = baseZ + 6
	emptyState.Visible = false
	emptyState.Parent = panel

	local emptyLine
	do
		local stack = Instance.new("UIListLayout")
		stack.FillDirection = Enum.FillDirection.Vertical
		stack.HorizontalAlignment = Enum.HorizontalAlignment.Center
		stack.VerticalAlignment = Enum.VerticalAlignment.Center
		stack.SortOrder = Enum.SortOrder.LayoutOrder
		stack.Padding = UDim.new(0, 6)
		stack.Parent = emptyState

		local bag = Instance.new("ImageLabel")
		bag.Name = "Bag"
		bag.LayoutOrder = 1
		bag.Size = UDim2.new(0, 54, 0, 54)
		bag.BackgroundTransparency = 1
		bag.Image = IconLibrary.Resolve("\u{1F392}") or ""
		bag.ImageTransparency = 0.5
		bag.ScaleType = Enum.ScaleType.Fit
		bag.ZIndex = emptyState.ZIndex
		bag.Parent = emptyState

		emptyLine = Instance.new("TextLabel")
		emptyLine.Name = "Line"
		emptyLine.LayoutOrder = 2
		emptyLine.Size = UDim2.new(1, -24, 0, 44)
		emptyLine.BackgroundTransparency = 1
		emptyLine.Text = "You don't have any Relics!"
		emptyLine.TextWrapped = true
		emptyLine.ZIndex = emptyState.ZIndex
		emptyLine.Parent = emptyState
		-- flatText kills the thick dark halo themeLabel adds -- correct over a coloured tile, and
		-- exactly wrong over a near-white sheet, where it draws every word in outline.
		flatText(themeLabel(emptyLine, 19, INK_ON_WHITE))

		local hint = Instance.new("TextLabel")
		hint.Name = "Hint"
		hint.LayoutOrder = 3
		hint.Size = UDim2.new(1, -24, 0, 34)
		hint.BackgroundTransparency = 1
		hint.Text = "Open a Relic Chest to find your first one."
		hint.TextWrapped = true
		hint.ZIndex = emptyState.ZIndex
		hint.Parent = emptyState
		flatText(themeLabel(hint, 13, Color3.fromRGB(150, 154, 168)))
	end

	-- =================================================================================
	-- RIGHT COLUMN 5 OF 5: THE DETAIL STRIP AND THE BACKPACK COUNTER
	-- =================================================================================
	--
	-- The strip is the only place a relic's real numbers are printed, and since 34.57 it carries no
	-- buttons: those moved up to the action row, where the reference puts them and where they cannot
	-- appear and disappear under the player's cursor.
	local detail = Instance.new("Frame")
	detail.Name = "Detail"
	detail.Size = UDim2.new(0, RIGHT_W, 0, 70)
	detail.Position = UDim2.new(0, RIGHT_X, 0, 418)
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
	detailArt.Size = UDim2.new(0, 40, 0, 40)
	detailArt.Position = UDim2.new(0, 8, 0.5, -20)
	detailArt.BackgroundTransparency = 1
	detailArt.ScaleType = Enum.ScaleType.Fit
	detailArt.ZIndex = baseZ + 8
	detailArt.Parent = detailCard

	-- THE NAME IS THE NAME ALONE. It used to read "Wormhole Sigil  .  Legendary", which is 26
	-- characters -- and at 16 px FredokaOne that measures past the 200 px this strip has for it. A
	-- truncated label reports `TextFits = true` and returns bounds that fit its box, so the flag
	-- would never have said so; the rarity moved down to the effect line instead, where it wraps.
	local detailName = CardKit.Text(detailCard, {
		name = "Name",
		text = "",
		size = UDim2.new(1, -60, 0, 18),
		position = UDim2.new(0, 54, 0, 4),
		textSize = 15,
		zIndex = baseZ + 8,
		strokeThickness = 3,
	})

	-- ===== FOUR LINES AT 11 px, AND THE ARITHMETIC THAT SAID THREE WAS THE BUG =====
	--
	-- 34.57 shipped this at 32 px on the reasoning that 204 px of width is about 34 characters a
	-- line and 32 px is three lines. Both halves were wrong by one. Measured live with
	-- `TextService:GetTextBoundsAsync` at width 204, FredokaOne 11, on the real strings this label
	-- is handed:
	--
	--     blurb 52 chars + "Legendary . x99 held . Antimatter Zone set 10/10"  ->  203 x 44  (4 lines)
	--     blurb 48 chars + "Rare . x1 held . Forest set 8/10"                  ->  202 x 33  (3 lines)
	--     a forge relic's one-line effect                                      ->  161 x 11  (1 line)
	--
	-- A collection relic's blurb wraps to two lines on its own, and so does the stat line behind
	-- it. At 32 px the box held TWO, `TextTruncate.AtEnd` cut the rest, and what got cut was always
	-- the SECOND line -- the rarity, the copy count and the set progress. The flavour survived and
	-- the facts did not, which is the wrong way round: measured on the live panel, `Forest Rune`
	-- rendered as "One mark, cut deep enough to outlast the tablet..." and nothing else at all.
	--
	-- `TextFits` DID report false here, and it is still not the thing to size against: it says a
	-- box is too small, never by how much, and `TextBounds` comes back describing the TRUNCATED
	-- render ([[roblox-textbounds-reports-the-truncation]]) -- 202 x 22 for text that needs 33.
	-- The only honest measurement is the one taken off the STRING, before it is put in a label.
	local detailEffect = CardKit.Text(detailCard, {
		name = "Effect",
		text = "",
		size = UDim2.new(1, -60, 0, 44),
		position = UDim2.new(0, 54, 0, 22),
		textSize = 11,
		color = Color3.fromRGB(244, 247, 255),
		wrapped = true,
		yAlign = "Top",
		zIndex = baseZ + 8,
		strokeThickness = 2,
	})

	-- ===== THE BACKPACK COUNTER =====
	--
	-- The reference's `0/100`, bottom right. It is the OPEN PAGE's count -- the fifteen on the Forge
	-- tab, a zone's ten on a set tab -- never a sum of the two layers: the fifteen are the stat layer
	-- and the two hundred are the collection, and one "37/215" would be a number about nothing. The
	-- global totals stay in the header subtitle, which is where they have always been.
	local backpack = Instance.new("Frame")
	backpack.Name = "Backpack"
	backpack.Size = UDim2.new(0, RIGHT_W, 0, 18)
	backpack.Position = UDim2.new(0, RIGHT_X, 0, 492)
	backpack.BackgroundTransparency = 1
	backpack.ZIndex = baseZ
	backpack.Parent = panel

	local bagIcon = Instance.new("ImageLabel")
	bagIcon.Name = "Icon"
	bagIcon.Size = UDim2.new(0, 18, 0, 18)
	bagIcon.Position = UDim2.new(1, -76, 0, 0)
	bagIcon.BackgroundTransparency = 1
	bagIcon.Image = IconLibrary.Resolve("\u{1F392}") or ""
	bagIcon.ScaleType = Enum.ScaleType.Fit
	bagIcon.ZIndex = baseZ + 1
	bagIcon.Parent = backpack

	local backpackLabel = Instance.new("TextLabel")
	backpackLabel.Name = "Count"
	backpackLabel.Size = UDim2.new(0, 54, 0, 18)
	backpackLabel.Position = UDim2.new(1, -54, 0, 0)
	backpackLabel.BackgroundTransparency = 1
	backpackLabel.Text = "0/0"
	backpackLabel.ZIndex = baseZ + 1
	backpackLabel.Parent = backpack
	flatText(themeLabel(backpackLabel, 15, INK_ON_WHITE))
	backpackLabel.TextXAlignment = Enum.TextXAlignment.Right

	-- =================================================================================
	-- THE LOCKED PANEL
	-- =================================================================================
	--
	-- Shown INSTEAD of everything above until stage 10. Not a toast and not a greyed-out panel: a
	-- player who opens a screen full of dark sockets and an unreadable grid has been shown a broken
	-- room, where one line telling them when the door opens is the true statement.
	local locked = Instance.new("Frame")
	locked.Name = "LockedState"
	locked.Size = UDim2.new(1, -32, 1, -114)
	locked.Position = UDim2.new(0, 16, 0, 98)
	locked.BackgroundTransparency = 1
	locked.ZIndex = baseZ + 7
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

		local lockOrb = Instance.new("ImageLabel")
		lockOrb.Name = "Orb"
		lockOrb.LayoutOrder = 1
		lockOrb.Size = UDim2.new(0, 84, 0, 84)
		lockOrb.BackgroundTransparency = 1
		lockOrb.Image = IconLibrary.Resolve("\u{1F52E}") or ""
		lockOrb.ImageTransparency = 0.45
		lockOrb.ScaleType = Enum.ScaleType.Fit
		lockOrb.ZIndex = locked.ZIndex
		lockOrb.Parent = locked

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
			flatText(themeLabel(label, size, color))
			return label
		end

		line(2, "The Relic Forge is sealed", 26, INK_ON_WHITE, 32)
		-- The stage is read off the config rather than typed, so moving the gate moves this sentence.
		line(3, ("Reach stage %d to open it. Relics are permanent bonuses that buff your whole lab."):format(
			GameConfig.RelicUnlockStage), 16, Color3.fromRGB(150, 154, 168), 46)
	end

	-- =================================================================================
	-- REFRESH
	-- =================================================================================
	--
	-- Reads `hud.getData()` and writes; it never builds. Everything it needs to decide is derived
	-- from `GameConfig.Relics` -- the same functions the SERVER uses to roll and to pay the bonuses,
	-- so this panel cannot advertise a number the game is not applying.
	--
	-- IT WRITES ONE PAGE, NEVER TWENTY-ONE. `pages` only contains what has been opened, and of those
	-- only the visible one is written.
	local function refreshChest(data)
		bankedChests = tonumber(data.RelicChests) or 0
		if bankedChests > 0 then
			-- The count is in the caption rather than on a pill, because the caption is where a
			-- player already looks on this button. "OPEN x3" rather than "OPEN CHEST (3)": the long
			-- form is fourteen characters and measures past the 118 px this button has.
			openChest.SetEnabled(true, BANKED)
			openChest.SetText(bankedChests > 1 and ("OPEN x%d"):format(bankedChests) or "OPEN CHEST")
		else
			-- ===== NO COUNTDOWN (34.55) =====
			-- This slot used to tick `14m 56s` toward a free chest. There is no free chest, so the
			-- empty state has to say where one COMES from instead of when -- which is what the card's
			-- own blurb line above the buttons is for.
			openChest.SetEnabled(false, NO_CHEST)
			openChest.SetText("NO CHESTS")
			openChest.SetColors(NO_CHEST)
		end
		buyChest.SetEnabled((data.Diamonds or 0) >= GameConfig.RelicChestDiamondCost, DIAMOND_BUY)
	end

	function refresh()
		local data = hud.getData and hud.getData()
		if not data then return end

		local open = GameConfig.IsRelicForgeUnlocked(data)
		locked.Visible = not open
		field.Visible = open
		extra.Visible = open
		chestCard.Visible = open
		actionRow.Visible = open
		tabs.Visible = open
		backpack.Visible = open
		for _, entry in pairs(pages) do
			-- A HIDDEN PANEL'S PAGES ARE ALL HIDDEN, not just the ones that were not current. The
			-- locked state draws over the whole panel and a page left visible under it would show
			-- through the transparent parts of it.
			entry.page.Visible = open and (entry == pages[currentTab])
		end
		if not open then
			detail.Visible = false
			emptyState.Visible = false
			subtitle.Text = ("Sealed until stage %d"):format(GameConfig.RelicUnlockStage)
			return
		end

		local owned = data.Relics or {}
		local equippedKeys = data.EquippedRelicKeys or {}
		local equippedLookup = {}
		for _, k in ipairs(equippedKeys) do equippedLookup[k] = true end
		local slots = GameConfig.GetMaxEquippedRelics(data)

		-- --- the constellation
		local wornCount = 0
		for i, refs in ipairs(socketRefs) do
			local key = equippedKeys[i]
			-- A key past the slot cap is NOT drawn even if it is in the list. The cap can fall (it
			-- never does today, but `GetMaxEquippedRelics` is free to change), and a socket showing a
			-- relic that `GetRelicMult` is ignoring would be the panel lying about the bonus.
			if i > slots then key = nil end
			local entry = key and owned[key]
			local relic = key and GameConfig.GetRelic(key)
			refs.unlocked = i <= slots

			if relic and entry then
				wornCount = wornCount + 1
				refs.key = key
				refs.art.Image = IconLibrary.Id[relic.icon] or ""
				refs.art.Visible = true
				refs.mark.Visible = false
				refs.cost.Text = ""
				refs.setColors({ relic.rarityDef.color, relic.rarityDef.deep })
				local level = (type(entry) == "table" and entry.level) or 1
				refs.pip.Visible = level > 1
				refs.pipLabel.Text = ("Lv.%d"):format(level)
			else
				refs.key = nil
				refs.art.Visible = false
				refs.pip.Visible = false
				refs.mark.Visible = true
				if refs.unlocked then
					-- PLAIN, as the reference draws it: a pale well with a question mark and nothing
					-- else. It is a hole, not a refusal, and it is a button -- see the socket handler.
					refs.mark.Text = "?"
					refs.cost.Text = ""
					refs.setColors(EMPTY_SOCKET)
				else
					-- A LOCKED SLOT SAYS WHAT OPENS IT, in the place the reference puts a price.
					refs.mark.Text = "\u{1F512}"
					refs.cost.Text = GameConfig.GetRelicSlotRequirement(i) or ""
					refs.setColors(LOCKED_SOCKET)
				end
			end
		end
		wornLabel.Text = ("%d/%d"):format(wornCount, slots)

		-- --- the extra-slots chips
		for i, chip in pairs(chipRefs) do
			local got = i <= slots
			chip.setColors(got and CHIP_OPEN or CHIP_SHUT)
			chip.mark.Text = got and "\u{2714}" or "\u{1F512}"
			chip.text.Text = got and "Unlocked" or (GameConfig.GetRelicSlotRequirement(i) or "")
		end

		refreshChest(data)

		-- --- the tab strip. Twenty-one labels is cheap and it is the per-set progress readout, so it
		-- is written every refresh rather than only when its own set changes -- a tab that is stale
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

		-- --- the open page, and only it. `pageHave` / `pageTotal` feed the backpack counter and the
		-- empty state, so both of those are the count of the page you are looking at.
		local entry = pages[currentTab]
		local pageHave, pageTotal = 0, 0
		if entry and entry.isSet then
			for key, refs in pairs(entry.tiles) do
				local copies = GameConfig.GetSetRelicCopies(data, key)
				local has = copies > 0
				if has then pageHave = pageHave + 1 end
				pageTotal = pageTotal + 1
				-- AN UNOWNED RELIC IS A SILHOUETTE, NOT A HIDDEN ONE. The grid doubles as the
				-- reference for what exists, and an empty cell is the only thing telling a player
				-- which relic is between them and a completed set.
				refs.setColors(has and { refs.def.rarityDef.color, refs.def.rarityDef.deep } or GHOST)
				refs.art.ImageTransparency = has and 0 or 0.72
				refs.dupe.Visible = copies > 1
				refs.dupeLabel.Text = "x" .. copies
				-- a collection relic has no level and is never worn, so neither mark can ever show
				refs.levelPip.Visible = false
				refs.tick.Visible = false
				refs.ring.Visible = (selectedKey == key)
			end
		elseif entry then
			for key, refs in pairs(entry.tiles) do
				local e = owned[key]
				local copies = (type(e) == "table" and e.copies) or 0
				local level = (type(e) == "table" and e.level) or 1
				local has = copies > 0
				if has then pageHave = pageHave + 1 end
				pageTotal = pageTotal + 1
				refs.setColors(has and { refs.def.rarityDef.color, refs.def.rarityDef.deep } or GHOST)
				refs.art.ImageTransparency = has and 0 or 0.72
				refs.dupe.Visible = copies > 1
				refs.dupeLabel.Text = "x" .. copies
				refs.levelPip.Visible = level > 1
				refs.levelLabel.Text = ("Lv.%d"):format(level)
				refs.tick.Visible = equippedLookup[key] == true
				refs.ring.Visible = (selectedKey == key)
			end
		end

		backpackLabel.Text = ("%d/%d"):format(pageHave, pageTotal)
		-- THE EMPTY STATE IS ABOUT THIS PAGE, and the grid of ghosts underneath stays where it is:
		-- it is drawn OVER them, because a player with nothing needs the sentence first and the
		-- catalogue second. The page is left visible so its scrollbar and shape are still there.
		emptyState.Visible = (pageHave == 0)
		if emptyState.Visible then
			emptyLine.Text = entry and entry.isSet
				and "You don't have any Relics from this set!"
				or "You don't have any Relics!"
		end

		-- --- the detail strip and the action row
		--
		-- 34.56: THE ROW IS ALWAYS THERE AND ALWAYS SAYS WHY. Three cases, and every one of them
		-- leaves both buttons on screen with a caption that names the rule that stopped them.
		if selectedKey and selectedIsSet then
			local def = GameConfig.GetSetRelic(selectedKey)
			local copies = GameConfig.GetSetRelicCopies(data, selectedKey)
			detail.Visible = def ~= nil
			if def then
				setDetailColors({ def.rarityDef.color, def.rarityDef.deep })
				detailArt.Image = IconLibrary.Id[def.icon]
					or IconLibrary.Id[GameConfig.RelicSetFallbackIcon] or ""
				detailArt.ImageColor3 = def.tint
				detailName.Text = def.name
				local have, total = GameConfig.CountSetRelicsOwned(data, def.zoneKey)
				-- The blurb stays -- it is the only flavour these two hundred have -- and the rarity
				-- joins it here, because it came off the NAME line above where it was overflowing.
				if copies > 0 then
					detailEffect.Text = ("%s\n%s \u{00B7} x%d held \u{00B7} %s set %d/%d"):format(
						def.blurb, def.rarity, copies, def.zoneName, have, total)
				else
					detailEffect.Text = ("%s\n%s \u{00B7} not found yet \u{00B7} %s set %d/%d"):format(
						def.blurb, def.rarity, def.zoneName, have, total)
				end
			end
			-- A COLLECTION RELIC IS NOT WORN AND NOT FORGED, and the panel now SAYS so instead of
			-- deleting the buttons. `RelicService.HandleEquip` resolves through `GameConfig.GetRelic`,
			-- which does not contain these two hundred keys, so firing `EquipRelic` here would be
			-- dropped in silence -- see this file's header for why that boundary exists.
			equipBtn.SetText("SET BONUS")
			equipBtn.SetEnabled(false)
			forgeBtn.SetText("NO FORGE")
			forgeBtn.SetEnabled(false)
		else
			local relic = selectedKey and GameConfig.GetRelic(selectedKey)
			local entryR = selectedKey and owned[selectedKey]
			if relic and entryR then
				local level = (type(entryR) == "table" and entryR.level) or 1
				detail.Visible = true
				setDetailColors({ relic.rarityDef.color, relic.rarityDef.deep })
				detailArt.Image = IconLibrary.Id[relic.icon] or ""
				-- the fifteen are drawn in their own colours; a tint would be a second multiply
				detailArt.ImageColor3 = Color3.new(1, 1, 1)
				detailName.Text = relic.name

				-- The LIVE value, not the authored one: a Lv.3 relic pays more than its table row says,
				-- and printing the row would make every levelled relic under-report itself.
				local value = GameConfig.GetRelicValue(relic, level)
				local shown = relic.statDef.add and ("+%d %s"):format(math.floor(value + 0.5), relic.statDef.label)
					or ("+%d%% %s"):format(math.floor(value * 100 + 0.5), relic.statDef.label)
				detailEffect.Text = ("%s \u{00B7} %s \u{00B7} %s set \u{00B7} Lv.%d"):format(
					relic.rarity, shown, relic.family, level)

				local worn = equippedLookup[selectedKey] == true
				-- THE CAP IS REAL AND DELIBERATE AND IT NAMES ITSELF. "SLOTS FULL" rather than a
				-- wordlessly greyed EQUIP: 34.56 exists because four different refusals all read as
				-- "this relic cannot be equipped", and the cap is the one of them that is correct.
				if worn then
					equipBtn.SetText("UNEQUIP")
					equipBtn.SetEnabled(true, EQUIP_ON)
				elseif #equippedKeys >= slots then
					equipBtn.SetText("SLOTS FULL")
					equipBtn.SetEnabled(false)
				else
					equipBtn.SetText("EQUIP")
					equipBtn.SetEnabled(true, EQUIP_ON)
				end

				-- THE FORGE BUTTON SAYS WHY IT IS OFF. Four different refusals -- maxed, not enough
				-- copies AND not enough dust to cover the gap, not enough DNA -- and a single greyed
				-- button that means all of them is a button the player pokes at. `GetRelicMergePlan`
				-- is the config's own test and the same one the server charges with, so this cannot
				-- disagree with what happens when the button IS pressed.
				local plan = GameConfig.GetRelicMergePlan(data, selectedKey)
				if plan.maxed then
					forgeBtn.SetText("MAX LEVEL")
					forgeBtn.SetEnabled(false)
				elseif not plan.ok then
					-- what is SHORT, in the currency that is short: copies if dust could not cover it
					forgeBtn.SetText(("NEED %d\u{2728}"):format(plan.dustNeed - plan.dustHave))
					forgeBtn.SetEnabled(false)
				else
					local cost = GameConfig.ScaleReward(GameConfig.GetRelicMergeCost(plan.level), data)
					forgeBtn.SetText(plan.dustNeed > 0 and ("FORGE %d\u{2728}"):format(plan.dustNeed) or "FORGE")
					forgeBtn.SetEnabled((data.DNA or 0) >= cost, FORGE_ON)
				end
			else
				-- NOTHING SELECTED. The buttons stay on screen and say what to do, rather than
				-- vanishing -- a row that appears and disappears is a row the player has to re-find.
				detail.Visible = false
				equipBtn.SetText("PICK A RELIC")
				equipBtn.SetEnabled(false)
				forgeBtn.SetText("FORGE")
				forgeBtn.SetEnabled(false)
			end
		end

		-- --- the header subtitle: the GLOBAL counters, which is where they have always been
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
		-- one place -- the FORGE button -- and a currency shown next to the thing it buys does not
		-- need a home in the HUD.
		local dust = math.floor(tonumber(data.RelicDust) or 0)
		if dust > 0 then table.insert(bits, ("%d\u{2728}"):format(dust)) end

		-- TWO COUNTS, and they are deliberately not added together. The fifteen are the stat layer
		-- and the two hundred are the collection; one "37/215" would be a number about nothing.
		local held = GameConfig.CountSetRelicsHeld(data)
		local doneSets = GameConfig.CountCompletedRelicSets(data)
		-- "1 sets" -- caught by the capture, not by a probe. Every other count in this subtitle is a
		-- ratio and reads fine at one; this is the only bare noun in the line.
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
	--   2. the ticker below, which now only keeps the chest row honest.
	--
	-- The dirty flag is what keeps the push path honest: a push that arrives while the panel is
	-- CLOSED sets the flag instead of drawing, and opening the panel spends it. Without that, a
	-- player who collects three relics with the panel shut opens it onto the state it had when they
	-- closed it.
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

	-- The Forge page is built and shown up front, so the panel opens on the fifteen -- which are the
	-- only relics anything on the left half of this screen can hold. The twenty collection pages
	-- cost nothing until one is opened.
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
