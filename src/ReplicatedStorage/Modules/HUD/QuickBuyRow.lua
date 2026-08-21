-- QuickBuyRow -- the strip of DNA packs under the evolve card, pinned to the bottom edge.
--
-- ===== WHERE IT COMES FROM (2026-08-21) =====
--
-- Kristina sent a capture of another game's HUD and asked for the same one. Under its level bar
-- that game runs three chunky buttons reading `+10K` `+100K` `+1M`, each with a small Robux price
-- in its top corner. They are developer products: the fastest possible route from "I want more of
-- the currency" to a purchase, on screen at all times, priced in view.
--
-- WE ALREADY SELL EXACTLY THIS. `GameConfig.RobuxProducts` has carried DNA_1 through DNA_5 with real
-- `productId`s since Phase 1, and `HUD/ProductTiles` renders all five inside the Robux panel. So
-- this module invents no product, writes no server code and adds no remote -- it is a second, much
-- shorter path to three of the five, and it fires the same `Remotes.PromptRobuxPurchase` that the
-- panel's own buy buttons fire. `RobuxShopService.ProcessReceipt` is the only thing that grants
-- anything, and it is untouched.
--
-- ===== WHY THREE, AND WHY THESE THREE =====
--
-- DNA_1 / DNA_3 / DNA_5, i.e. the 49, the 199 and the 999. Not the first three: a strip whose three
-- prices are 49 / 99 / 199 is three versions of the same decision, and the reference's own strip
-- spans its whole range (+10K to +1M). Taking every other rung gives the widest span the five
-- products can offer while leaving DNA_2 and DNA_4 to the Robux panel, which is still the place
-- that shows all five side by side with their value ribbons.
--
-- ===== THE NUMBER ON THE FACE IS NOT `grantDNA` =====
--
-- It is `GameConfig.ScaleReward(product.grantDNA, data)`, which multiplies by the player's stage.
-- That is not a display convenience -- it is what `RobuxShopService` line 252 ACTUALLY PAYS OUT, so
-- printing the raw 1000 would be a false price tag for everyone past stage one. It is also why the
-- reference's numbers grow as its player progresses (+10K early, +3.5M later, both visible in the
-- captures she sent). The labels are rewritten on every DataUpdate for the same reason.
--
-- ===== GEOMETRY, AND WHAT IT HAD TO CLEAR =====
--
--   * 470 wide, matching `evolveFrame` exactly, so the two read as one stacked block rather than as
--     two centred things of different widths.
--   * pinned at (0.5, 0, 1, -10) so it owns the bottom edge. The evolve card moved 1,-36 -> 1,-84
--     to make room and the world-event bar moved to the top centre (see `PotionTimers`), because
--     that band cannot hold three tenants.
--   * ON A PHONE this is the tightest thing on the screen and it was measured, not eyeballed: at
--     848 px the row leaves (848 - 470) / 2 = 189 px each side, and the tile columns need
--     20 + 2 * 82 + one 26 gap = 210. That overlaps, so the row SHRINKS itself on a narrow viewport
--     (see `fit` below) rather than sliding under the buttons.

local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))

local Remotes = RS.Remotes

local formatNumber, themeLabel, styleCard = UIKit.formatNumber, UIKit.themeLabel, UIKit.styleCard

-- key -> the fill of its button. Sunny / Red / Blue is the reference's own run, and it is the one
-- place in this HUD where three adjacent controls are DELIBERATELY three different hues: they are
-- three sizes of the same purchase and the colour is the only thing separating them at a glance.
local TILES = {
	{ key = "DNA_1", color = UITheme.Color.Sunny },
	{ key = "DNA_3", color = UITheme.Color.Red },
	{ key = "DNA_5", color = UITheme.Color.Blue },
}

local ROW_W, ROW_H = 470, 62
local TILE_W, GAP = 150, 10

return function(hud)
	local screenGui = hud.screenGui

	local row = Instance.new("Frame")
	row.Name = "QuickBuyRow"
	row.Size = UDim2.new(0, ROW_W, 0, ROW_H)
	row.Position = UDim2.new(0.5, 0, 1, -10)
	row.AnchorPoint = Vector2.new(0.5, 1)
	row.BackgroundTransparency = 1
	row.ZIndex = UITheme.Z.Content
	row.Parent = screenGui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, GAP)
	layout.Parent = row

	-- key -> the label on its face, so the DataUpdate loop can rewrite three strings without
	-- rebuilding three buttons. Rebuilding would drop a click landing in the same frame.
	local faces = {}

	for order, spec in ipairs(TILES) do
		-- `GameConfig.GetRobuxProduct` is the accessor the rest of the game looks products up with.
		-- A missing product is not a crash: the table is data and may be edited. The tile simply is
		-- not built, and the layout closes the gap on its own.
		local product = GameConfig.GetRobuxProduct(spec.key)
		if product then
			local btn = Instance.new("TextButton")
			btn.Name = "Buy_" .. spec.key
			btn.Size = UDim2.new(0, TILE_W, 0, 52)
			btn.LayoutOrder = order
			btn.Text = ""
			btn.AutoButtonColor = false
			btn.ZIndex = row.ZIndex
			btn.Parent = row
			styleCard(btn, spec.color, UDim.new(0, 14), 4)

			-- The amount. `styleCard` puts the fill in an `InnerBody` ABOVE the host, and a TextButton
			-- draws its own text below its children -- so a caption written onto `btn.Text` is
			-- invisible. Every text-bearing host in this kit goes through a child label for exactly
			-- that reason (see the block in `UIKit.styleCard`); this one is built directly.
			local face = Instance.new("TextLabel")
			face.Name = "Face"
			face.Size = UDim2.new(1, -16, 1, -12)
			face.Position = UDim2.new(0.5, 0, 0.5, 0)
			face.AnchorPoint = Vector2.new(0.5, 0.5)
			face.BackgroundTransparency = 1
			face.Text = "+" .. formatNumber(product.grantDNA or 0)
			face.ZIndex = btn.ZIndex + UITheme.Z.Content
			face.Parent = btn
			themeLabel(face, 28)
			faces[spec.key] = face

			-- THE PRICE RIDES THE TOP-RIGHT CORNER, half outside the button, which is where the
			-- reference puts it and is also the only place on a 150x52 face that is not already
			-- carrying the amount. Green because that is Robux's own colour and because it is the one
			-- chip in this row whose meaning is "this costs money" -- see the Robux tile in the
			-- right-hand cluster, which is Mint for the same reason.
			local price = Instance.new("TextLabel")
			price.Name = "Price"
			price.Size = UDim2.new(0, 58, 0, 26)
			price.Position = UDim2.new(1, -6, 0, -6)
			price.AnchorPoint = Vector2.new(1, 0)
			price.Text = (product.price or 0) .. "\u{2B22}"
			price.ZIndex = btn.ZIndex + UITheme.Z.Badge
			price.Parent = btn
			styleCard(price, UITheme.Color.Green, UDim.new(1, 0), 3)
			themeLabel(price, 16)

			btn.MouseButton1Click:Connect(function()
				Remotes.PromptRobuxPurchase:FireServer(product.key)
			end)
		end
	end

	-- ===== WHAT THE PLAYER WOULD ACTUALLY RECEIVE =====
	local function refresh()
		local data = hud.getData()
		if not data then return end
		for _, spec in ipairs(TILES) do
			local face = faces[spec.key]
			local product = face and GameConfig.GetRobuxProduct(spec.key)
			if product and product.grantDNA then
				face.Text = "+" .. formatNumber(GameConfig.ScaleReward(product.grantDNA, data))
			end
		end
	end

	Remotes.DataUpdate.OnClientEvent:Connect(refresh)
	refresh()

	-- ===== THE NARROW-VIEWPORT RULE =====
	--
	-- The tile columns are laid out by `Modules.HUD.TileColumnFit` and hug both edges; this row is
	-- centred. They collide below about 890 px of width. Scaling the row down is the right answer
	-- rather than moving it, because the row's whole point is that it sits under the progress bar --
	-- a strip that slid up or sideways on a phone would be a fourth thing in an already busy corner.
	--
	-- `UIScale` rather than resizing the three buttons: the price chips hang off their corners and
	-- are positioned in scale, so scaling the container keeps the whole assembly in proportion.
	local scale = Instance.new("UIScale")
	scale.Name = "FitScale"
	scale.Parent = row

	local cam = workspace.CurrentCamera
	local function fit()
		if not cam then return end
		-- 210 a side for the tile columns (20 margin + two 82 tiles + a 26 gap), 12 of daylight.
		local free = cam.ViewportSize.X - (210 + 12) * 2
		scale.Scale = math.clamp(free / ROW_W, 0.62, 1)
	end
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
		fit()
	end
end
