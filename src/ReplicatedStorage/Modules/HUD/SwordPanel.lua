-- SwordPanel -- the weapon ladder as ten rows, and the tile that opens it (32.6).
--
-- A HUD MODULE, i.e. a FUNCTION and not a table (`docs/SPLIT.md` §2). It builds its own tile, its
-- own panel and its own DataUpdate hook, so **MainUI gains exactly one line and zero top-level
-- locals** -- which is the whole constraint that file lives under
-- ([[evolution-lab-mainui-register-limit]]).
--
-- Laid out as a CHECKLIST, the same shape as the Stage Mastery panel and for the same reason: the
-- rungs are bought strictly in order and only one of them is ever purchasable, so what the player
-- is reading is "where am I on this ladder and what does the next rung cost" -- not a shelf of
-- alternatives. A grid of ten cards would be a lie about the choice on offer.

local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))

local Remotes = RS.Remotes

local formatNumber, themeLabel = UIKit.formatNumber, UIKit.themeLabel
local styleCard, styleButton, setButtonColor = UIKit.styleCard, UIKit.styleButton, UIKit.setButtonColor
local OUTLINE_COLOR, PANEL_SHELL, READY_RIM = UIKit.OUTLINE_COLOR, UIKit.PANEL_SHELL, UIKit.READY_RIM

local ROW_H, ROW_GAP = 70, 6

return function(hud)
	local screenGui = hud.screenGui
	local swords = GameConfig.Swords
	local maxLevel = GameConfig.MaxSwordLevel

	-- ===== THE DOOR =====
	--
	-- Left column, order 5. The left block was a 2x2 of four since 16.2 and becomes a 2x3 with one
	-- empty slot; `TileColumnFit` drives the whole layout off the tile COUNT it finds, so nothing
	-- else has to be told about the fifth tile and the right cluster does not move.
	--
	-- BUILT HERE AND HELD BY NOBODY -- the Auras tile's shape (15.27), for the two reasons written
	-- over it: this module is required from inside MainUI's own body, so the tile exists before
	-- `TileColumnFit` walks `screenGui` (a tile created after that walk is never laid out at all and
	-- keeps its authored pixel position on every viewport), and MainUI cannot afford the register a
	-- handle would cost.
	--
	-- ⚔️ RESOLVES TO THE SAME ART THE AUTO TILE DRAWS, and that is accepted rather than worked
	-- around: `IconLibrary` has one sword and this is the tile that IS a sword. The two sit on
	-- opposite edges of the screen, this one is captioned "Sword" against "Auto ON/OFF", and the
	-- Auto tile is green-or-grey against this one's gold -- so nothing on screen is ambiguous.
	-- Gold, because it is the only tile colour not already spoken for and because the ladder's own
	-- end is gilded.
	--
	-- THE BADGE IS AUTHORED HERE AND HIDDEN BY THE FIRST REFRESH. `UITheme.IconTile` only builds a
	-- Badge child when it is handed badge text, so it has to be asked for at construction; `refresh`
	-- below owns whether it is ever seen, exactly as `refreshRewardPanel` owns the Daily tile's.
	local tile = hud.columnTile("L", 5, "\u{2694}\u{FE0F}", "Sword", UITheme.Color.Gold,
		"BUY!", UITheme.Color.Green)

	-- ===== THE PANEL =====
	local panel = Instance.new("Frame")
	panel.Name = "SwordPanel"
	-- 520 tall: header 52 + summary 40 + gap 12 + a 400 px list (five and a half rows of 76, so the
	-- cut always falls THROUGH a row and the list is visibly scrollable) + 16 of bottom margin.
	panel.Size = UDim2.new(0, 480, 0, 520)
	panel.Position = hud.PANEL_ANCHOR
	panel.ZIndex = 20
	panel.Visible = false
	panel.Parent = screenGui
	styleCard(panel, PANEL_SHELL, UDim.new(0, 22), 5)
	hud.registerPanel(panel)
	hud.panelClose(panel)

	-- The subtitle carries the two facts no row states on its own: what the currency is, and that a
	-- rebirth does not take it. The second one matters more than it looks -- a player deciding
	-- whether to spend 10,240 Diamonds an hour before a reset needs to know that, and the only
	-- other place it is written down is a comment in `SwordService`.
	local _, contentTop = UITheme.PanelHeader(panel, {
		title = "\u{2694}\u{FE0F} Weapon",
		subtitle = "Bought with Diamonds -- a rebirth never takes it",
		accent = UITheme.Color.Gold,
		maxTextSize = 30,
	})

	-- ONE RATIO, DRAWN. Ten rows collapse into "which rung am I on", which is the one number the
	-- ladder is about; the same argument the Stage Mastery panel's summary bar makes, and the same
	-- reason a bar per ROW would be wrong (a two-state bar is a tick box drawn the long way).
	local summaryFill, summaryLabel = select(2, UITheme.ProgressBar(panel, {
		name = "SummaryCard",
		size = UDim2.new(1, -32, 0, 40),
		position = UDim2.new(0, 16, 0, contentTop),
		color = UITheme.Color.Gold,
		radius = UITheme.Radius.Pill,
		thickness = 3,
		text = "Blade 1 / " .. maxLevel,
		maxTextSize = 20,
		zIndex = panel.ZIndex + UITheme.Z.Content,
	}))

	local listTop = contentTop + 52
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "SwordScroll"
	scroll.Size = UDim2.new(1, -32, 1, -(listTop + 16))
	scroll.Position = UDim2.new(0, 16, 0, listTop)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	-- Thickness and colour are both overwritten by `HUD/ScrollAffordance`, which sweeps every
	-- ScrollingFrame under the ScreenGui and also hooks DescendantAdded -- so this list gets the
	-- visible grip and the bottom fade whichever order the two modules happen to run in.
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.new(0, 0, 0, maxLevel * (ROW_H + ROW_GAP))
	scroll.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, ROW_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	local rows = {}

	for i, tier in ipairs(swords) do
		local row = Instance.new("Frame")
		row.Name = "Blade" .. i
		row.LayoutOrder = i
		row.Size = UDim2.new(1, 0, 0, ROW_H)
		row.Parent = scroll
		local rowStroke = styleCard(row, tier.color, UDim.new(0, 14), 4)

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "NameLabel"
		nameLabel.Size = UDim2.new(0.64, 0, 0, 28)
		nameLabel.Position = UDim2.new(0, 12, 0, 6)
		nameLabel.BackgroundTransparency = 1
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Text = i .. ". " .. tier.displayName
		nameLabel.Parent = row
		themeLabel(nameLabel, 22)

		local statusLabel = Instance.new("TextLabel")
		statusLabel.Name = "StatusLabel"
		statusLabel.Size = UDim2.new(0.64, 0, 0, 24)
		statusLabel.Position = UDim2.new(0, 12, 1, -30)
		statusLabel.BackgroundTransparency = 1
		statusLabel.TextXAlignment = Enum.TextXAlignment.Left
		statusLabel.Text = ""
		statusLabel.Parent = row
		themeLabel(statusLabel, 17, UITheme.Color.Cream)

		local buyButton = Instance.new("TextButton")
		buyButton.Name = "BuyButton"
		buyButton.Size = UDim2.new(0, 112, 0, 46)
		buyButton.Position = UDim2.new(1, -124, 0.5, -23)
		buyButton.Text = "\u{1F512}"
		buyButton.Parent = row
		styleButton(buyButton, UITheme.Color.Locked, UDim.new(1, 0))

		-- THE REMOTE CARRIES NO ARGUMENT, which is what makes it unspoofable: the server buys the
		-- NEXT rung and there is no tier number for a client to lie about. So every row's button
		-- fires the same thing, and a row that is not the next one is simply not clickable -- the
		-- refresh below is what decides that, and the server refuses it a second time regardless.
		buyButton.MouseButton1Click:Connect(function()
			Remotes.BuySword:FireServer()
		end)

		-- `nameLabel` rides along for the same reason the Mastery rows carry theirs: the fill is
		-- repainted three different ways below and one of them is a pale surface, so the caption's
		-- ink is state rather than a build-time decision.
		rows[i] = { row = row, nameLabel = nameLabel, statusLabel = statusLabel,
			buyButton = buyButton, stroke = rowStroke }
	end

	local function refresh()
		local data = hud.getData()
		if not data then return end

		local level = GameConfig.GetSwordLevel(data)
		local diamonds = data.Diamonds or 0
		local nextCost = GameConfig.GetSwordCost(level)
		local maxed = (nextCost == math.huge)

		summaryLabel.Text = maxed
			and string.format("Blade %d / %d -- x%.2f damage, fully forged", level, maxLevel, GameConfig.GetSwordDamageMult(data))
			or string.format("Blade %d / %d -- x%.2f damage", level, maxLevel, GameConfig.GetSwordDamageMult(data))
		-- a Scale, not an offset: the responsive UIScale shrinks the panel, and an offset width
		-- would be right on one screen only
		summaryFill.Size = UDim2.new(level / math.max(1, maxLevel), 0, 1, 0)

		for i, tier in ipairs(swords) do
			local refs = rows[i]
			if refs then
				if i < level then
					-- OWNED AND SUPERSEDED. Painted as a receipt rather than as a refusal (18.6):
					-- these are rungs the player PAID for, and greying them out is the fault that
					-- made a maxed Mastery save look like a wall of locked rows.
					refs.statusLabel.Text = string.format("\u{2713} Forged  \u{2022}  x%.2f", tier.damageMult)
					refs.buyButton.Text = "\u{2713}"
					setButtonColor(refs.buyButton, UITheme.Color.Green)
					setButtonColor(refs.row, UITheme.DoneShade(UITheme.Color.Green))
					refs.stroke.Color = OUTLINE_COLOR
				elseif i == level then
					-- THE ONE IN HIS HANDS. Full chroma, its own colour, and the bright rim -- this
					-- is the row the panel exists to point at, and the only one whose colour is the
					-- blade's own so the shelf reads back against the steel on screen.
					refs.statusLabel.Text = string.format("EQUIPPED  \u{2022}  x%.2f damage", tier.damageMult)
					refs.buyButton.Text = "\u{2694}\u{FE0F}"
					setButtonColor(refs.buyButton, UITheme.Color.Gold)
					setButtonColor(refs.row, tier.color)
					refs.stroke.Color = READY_RIM
				elseif i == level + 1 then
					local affordable = diamonds >= tier.cost
					refs.statusLabel.Text = string.format("x%.2f damage  \u{2022}  %s",
						tier.damageMult,
						affordable and "yours now" or ("need " .. formatNumber(tier.cost - diamonds) .. " more"))
					refs.buyButton.Text = "\u{1F48E} " .. formatNumber(tier.cost)
					-- grey, not red: "not yet" is not an error, and a red button on a fresh save
					-- reads as something being broken
					setButtonColor(refs.buyButton, affordable and UITheme.Color.Green or UITheme.Color.Locked)
					setButtonColor(refs.row, tier.color)
					refs.stroke.Color = affordable and READY_RIM or OUTLINE_COLOR
				else
					-- STILL PRICED, THOUGH IT CANNOT BE BOUGHT. A locked row that hides its cost
					-- turns the whole ladder into a surprise, and the doubling curve is the single
					-- most useful thing a player can know when deciding whether to bank Diamonds.
					refs.statusLabel.Text = string.format("\u{1F48E} %s  \u{2022}  x%.2f damage",
						formatNumber(tier.cost), tier.damageMult)
					refs.buyButton.Text = "\u{1F512}"
					setButtonColor(refs.buyButton, UITheme.Color.Locked)
					setButtonColor(refs.row, UITheme.Color.Locked)
					refs.stroke.Color = OUTLINE_COLOR
				end
			end
		end

		-- THE TILE CARRIES THE "YOU CAN AFFORD THE NEXT ONE" FLAG, and it is the same signal the
		-- Daily and Gifts tiles use: something to take right now, hidden the moment there is not.
		-- Without it a player who has been farming has no reason to ever open this panel again.
		local badge = tile:FindFirstChild("Badge")
		if badge then
			badge.Visible = (not maxed) and diamonds >= nextCost
		end
	end

	tile.MouseButton1Click:Connect(function()
		hud.toggleOnly(panel)
		refresh()
	end)

	-- Refreshed on every push while the panel is open (the balance moves on every kill), and ALWAYS
	-- when it is shut -- because the badge above is the only thing telling a player the next blade
	-- has come into reach, and a badge that only lights while the panel is already open is a badge
	-- nobody ever sees.
	Remotes.DataUpdate.OnClientEvent:Connect(function()
		refresh()
	end)
	refresh()
end
