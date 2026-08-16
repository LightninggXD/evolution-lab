-- RebirthRungs -- the four rebirth milestones drawn as rungs, so 4/4 is not an empty amber box (18.4).
--
-- MOVED OUT OF `MainUI` (18.9), byte for byte. It was already a closed
-- `;(function() ... end)()` block -- the shape this file's 200-register ceiling forces
-- every panel into -- so the extraction is a change of wrapper, not of code. See
-- `docs/SPLIT.md` for the `hud` contract and `docs/CODEMAP.md` for where the rest went.

local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))

local themeLabel, styleCard = UIKit.themeLabel, UIKit.styleCard

return function(hud)
	local rebirthReqCard, rebirthReqLabel = hud.rebirthReqCard, hud.rebirthReqLabel

	-- Full chroma, one per rung; wrapped rather than indexed directly so a ladder longer than the
	-- palette (17.14 is open on exactly that) repeats colours instead of handing `DoneShade` a nil.
	local hues = { UITheme.Color.Aqua, UITheme.Color.Mint, UITheme.Color.Lavender, UITheme.Color.Gold }
	local count = math.max(GameConfig.MaxRebirths, 1)

	-- MEASURED OFF THE CARD, NOT TYPED. The card is 176 tall; 7 px of margin top and bottom and a
	-- 6 px gutter leaves 36 px a row at four rungs and 27 at five, so the block always fills the box
	-- it was added to fill and a fifth rebirth cannot push a row out of the bottom of it.
	local gap = 6
	local inset = 7
	local rowH = math.floor(((rebirthReqCard.Size.Y.Offset - inset * 2) - gap * (count - 1)) / count)
	local rungs = {}

	for tier = 1, count do
		local hue = hues[((tier - 1) % #hues) + 1]

		local row = Instance.new("Frame")
		row.Name = "Rung" .. tier
		row.Size = UDim2.new(1, -24, 0, rowH)
		row.Position = UDim2.new(0, 12, 0, inset + (tier - 1) * (rowH + gap))
		row.Visible = false
		-- A CHIP LYING ON A CARD, NOT A RAISED OBJECT (18.5). Without this the soft sprite would
		-- draw a second shadow inside the one the gold card already casts, which is what makes a
		-- stack of nested surfaces look like fog rather than like layers.
		row:SetAttribute("NoShadow", true)
		row.Parent = rebirthReqCard
		styleCard(row, UITheme.DoneShade(hue), UDim.new(0, 10), 3)

		-- The rank disc is the one thing on the row at full chroma: the row says "spent", the disc
		-- says "and this is which one". Radius Pill, so `DropShadow` declines it on shape alone.
		local disc = Instance.new("Frame")
		disc.Name = "Rank"
		disc.Size = UDim2.new(0, rowH - 10, 0, rowH - 10)
		disc.Position = UDim2.new(0, 7, 0.5, 0)
		disc.AnchorPoint = Vector2.new(0, 0.5)
		disc.ZIndex = row.ZIndex + UITheme.Z.Badge
		disc.Parent = row
		styleCard(disc, hue, UDim.new(1, 0), 2)

		local rank = Instance.new("TextLabel")
		rank.Name = "RankLabel"
		rank.Size = UDim2.new(1, 0, 1, 0)
		rank.BackgroundTransparency = 1
		rank.Text = tostring(tier)
		rank.ZIndex = disc.ZIndex + UITheme.Z.Content
		rank.Parent = disc
		-- white on a 0.64-0.78 pastel (Lavender through Gold), all of it under UITheme's 0.86
		-- light-surface cut, so the chunky halo is the right answer and `themeLabel` keeps it
		themeLabel(rank, math.max(rowH - 18, 14))

		local where = Instance.new("TextLabel")
		where.Name = "StageLabel"
		where.Size = UDim2.new(0, 96, 1, -8)
		where.Position = UDim2.new(0, rowH + 4, 0, 4)
		where.BackgroundTransparency = 1
		where.TextXAlignment = Enum.TextXAlignment.Left
		where.Text = ("Stage %d"):format(GameConfig.GetRebirthTierStageIndex(tier))
		where.ZIndex = row.ZIndex + UITheme.Z.Content
		where.Parent = row
		-- Ink, not white: a DoneShade is a light surface BY CONSTRUCTION (luminance 0.90), so this is
		-- the `inkOn` answer rather than a taste call, and themeLabel drops the halo with it.
		themeLabel(where, 16, UITheme.Color.Ink)

		-- WHAT THIS RUNG PAID, as the running totals it left behind rather than as its own increment.
		-- "+1.5x income" is a number nobody can act on; "you permanently earn x4.00 from here" is the
		-- shape the info card above already uses and the only one in which a spent milestone reads as
		-- a gain.
		local paid = Instance.new("TextLabel")
		paid.Name = "PaidLabel"
		paid.Size = UDim2.new(1, -(rowH + 106), 1, -8)
		paid.Position = UDim2.new(1, -10, 0, 4)
		paid.AnchorPoint = Vector2.new(1, 0)
		paid.BackgroundTransparency = 1
		paid.TextXAlignment = Enum.TextXAlignment.Right
		paid.Text = ("\u{2694}\u{FE0F} x%.2f    \u{1F9EC} x%.2f"):format(
			GameConfig.GetRebirthDamageMult({ Rebirths = tier }),
			GameConfig.GetRebirthIncomeMult({ Rebirths = tier }))
		paid.ZIndex = row.ZIndex + UITheme.Z.Content
		paid.Parent = row
		themeLabel(paid, 16, UITheme.Color.Ink)

		rungs[tier] = row
	end

	-- One handle out, called from `refreshRebirthPanel` below. The sentence and the rungs are the two
	-- halves of one switch and are never both on: the card is 176 px and either fills with prose or
	-- fills with rows.
	hud.setRebirthRungs = function(show)
		rebirthReqLabel.Visible = not show
		for _, row in ipairs(rungs) do
			row.Visible = show
		end
	end
end
