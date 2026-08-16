-- Quests -- the daily quest board: three rotating goals, their progress and their claim.
--
-- MOVED OUT OF `MainUI` (18.9), byte for byte. It was already a closed
-- `;(function() ... end)()` block -- the shape this file's 200-register ceiling forces
-- every panel into -- so the extraction is a change of wrapper, not of code. See
-- `docs/SPLIT.md` for the `hud` contract and `docs/CODEMAP.md` for where the rest went.

local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))

local Remotes = RS.Remotes

local styleCard, PANEL_SHELL = UIKit.styleCard, UIKit.PANEL_SHELL

return function(hud)
	local panelClose, registerPanel, screenGui = hud.panelClose, hud.registerPanel, hud.screenGui
	local toggleOnly = hud.toggleOnly

	local ROW_H, ROW_GAP = 56, 8
	local PANEL_W = 620

	local aurasPanel = Instance.new("Frame")
	aurasPanel.Name = "AurasPanel"
	aurasPanel.Size = UDim2.new(0, PANEL_W, 0, 550)
	aurasPanel.Visible = false
	aurasPanel.ZIndex = 40
	aurasPanel.Parent = screenGui
	-- SHELL BEFORE registerPanel, and that order is the whole of 15.1: the cyan panel rim is chosen
	-- inside registerPanel off a UIStroke that has to already exist. Styling afterwards leaves the
	-- panel with the plain dark outline every card in the game wears and nothing marks it as a panel.
	styleCard(aurasPanel, PANEL_SHELL, UDim.new(0, 22), 5)
	registerPanel(aurasPanel)
	panelClose(aurasPanel)

	local _, topY, _, headerSub = UITheme.PanelHeader(aurasPanel, {
		title = "\u{1F9EC} Auras",
		subtitle = "Rolled at the DNA Splicer -- one is worn at a time",
		accent = UITheme.Color.Purple,
		maxTextSize = 28,
		margin = 16,
		top = 14,
	})

	local list = Instance.new("ScrollingFrame")
	list.Name = "AuraList"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.new(0, 16, 0, topY)
	list.Size = UDim2.new(1, -32, 1, -topY - 16)
	list.ZIndex = aurasPanel.ZIndex + UITheme.Z.Content
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = Color3.fromRGB(60, 70, 90)
	-- Seven rows fit without scrolling today; the canvas is computed rather than authored so an
	-- eighth mutation added to GameConfig.Mutations arrives as a scroll instead of as a row nobody
	-- can reach. (`Mutations` is rank-ordered, so a new one goes in rank position -- see the note
	-- over that table -- and this panel inherits the order for free.)
	list.CanvasSize = UDim2.new(0, 0, 0,
		#GameConfig.Mutations * ROW_H + (#GameConfig.Mutations - 1) * ROW_GAP)
	list.Parent = aurasPanel

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, ROW_GAP)
	listLayout.Parent = list

	local rows = {}
	local equipRemote
	-- The remote is created by SplicerService.Init at server boot, so it is there long before a
	-- player can open this -- but it is waited for rather than looked up, which is the 15.5 lesson:
	-- a FindFirstChild at build time on a remote created anywhere else is a permanently dead button.
	task.spawn(function()
		equipRemote = Remotes:WaitForChild("EquipMutation", 30)
	end)

	for i, mut in ipairs(GameConfig.Mutations) do
		local row = Instance.new("Frame")
		row.Name = "Aura_" .. mut.name
		row.Size = UDim2.new(1, 0, 0, ROW_H)
		row.LayoutOrder = i
		row.ZIndex = list.ZIndex
		styleCard(row, UITheme.Color.PanelWhite, UDim.new(0, 14), 3)
		row.Parent = list

		-- THE COLOUR IS THE AURA. This chip is painted the exact Color3 the particles on the body
		-- take, so the panel and the player are the same object seen twice.
		local chip = Instance.new("Frame")
		chip.Name = "Chip"
		chip.Size = UDim2.new(0, 44, 0, 44)
		chip.Position = UDim2.new(0, 10, 0.5, 0)
		chip.AnchorPoint = Vector2.new(0, 0.5)
		chip.ZIndex = row.ZIndex + UITheme.Z.Content
		styleCard(chip, mut.color, UDim.new(0, 12), 3)
		chip.Parent = row

		-- Inked by luminance, not by rarity name: Godly is near-white and Secret is near-black, and
		-- the two sit four rows apart in the same column.
		local bright = (0.299 * mut.color.R + 0.587 * mut.color.G + 0.114 * mut.color.B) > 0.55
		local count = UITheme.Label(chip, {
			name = "Count",
			text = "",
			size = UDim2.new(1, -4, 1, -4),
			position = UDim2.new(0, 2, 0, 2),
			maxTextSize = 20,
			minTextSize = 12,
			color = bright and Color3.fromRGB(46, 40, 30) or UITheme.Color.White,
			zIndex = chip.ZIndex + UITheme.Z.Content,
		})

		local name = UITheme.Label(row, {
			name = "Name",
			text = mut.name,
			size = UDim2.new(1, -240, 0, 24),
			position = UDim2.new(0, 66, 0, 7),
			xAlign = "Left",
			maxTextSize = 22,
			minTextSize = 15,
			color = Color3.fromRGB(30, 35, 45),
			zIndex = row.ZIndex + UITheme.Z.Content,
		})

		local effect = UITheme.Label(row, {
			name = "Effect",
			text = "",
			size = UDim2.new(1, -240, 0, 20),
			position = UDim2.new(0, 66, 0, 30),
			xAlign = "Left",
			maxTextSize = 15,
			minTextSize = 11,
			color = Color3.fromRGB(80, 95, 115),
			zIndex = row.ZIndex + UITheme.Z.Content,
		})

		local wear = UITheme.Button(row, {
			name = "Wear",
			text = "Wear",
			size = UDim2.new(0, 140, 0, 40),
			position = UDim2.new(1, -12, 0.5, 0),
			anchorPoint = Vector2.new(1, 0.5),
			color = UITheme.Color.Green,
			radius = 12,
			maxTextSize = 18,
			zIndex = row.ZIndex + UITheme.Z.Content,
		})
		wear.MouseButton1Click:Connect(function()
			-- Dimmed AND dead, the Journal's rule for its own Equip button: a greyed button that
			-- still fires a remote and gets a refusal back says the press failed rather than that
			-- there was nothing to press.
			if not wear.Active or not equipRemote then return end
			equipRemote:FireServer(mut.name)
		end)

		rows[mut.name] = { row = row, count = count, name = name, effect = effect, wear = wear }
	end

	local function refreshAurasPanel()
		local found = (hud.getData() and hud.getData().SplicerFound) or {}
		local worn = hud.getData() and hud.getData().SplicerMutation
		local ownedCount = 0

		for _, mut in ipairs(GameConfig.Mutations) do
			local r = rows[mut.name]
			local n = tonumber(found[mut.name]) or 0
			local isOwned = n > 0
			local isWorn = isOwned and worn == mut.name
			if isOwned then ownedCount += 1 end

			r.count.Text = isOwned and ("x" .. n) or "?"
			r.name.TextTransparency = isOwned and 0 or 0.35
			if isOwned then
				r.effect.Text = ("\u{1F48E} x%.2f DNA   \u{26A1} +%d%% speed"):format(mut.incomeMult, mut.speedPct)
				r.effect.TextTransparency = 0
			else
				-- The locked row is the only line in the game that says where a mutation comes from.
				r.effect.Text = ("\u{1F512} Roll at the DNA Splicer \u{2022} x%.2f DNA, +%d%% speed"):format(
					mut.incomeMult, mut.speedPct)
				r.effect.TextTransparency = 0.15
			end

			-- `UITheme.SetText` / `UITheme.SetColor`, never `.Text` and `setButtonColor`: a
			-- UITheme.Button draws its caption into a child called "Label" and its fill into a
			-- child "Body", so writing the button's own properties changes a surface nobody sees.
			r.wear.Visible = isOwned
			if isWorn then
				UITheme.SetText(r.wear, "\u{2713} Wearing")
				UITheme.SetColor(r.wear, UITheme.Color.Locked)
				r.wear.Active = false
				r.wear.AutoButtonColor = false
			else
				UITheme.SetText(r.wear, "Wear")
				UITheme.SetColor(r.wear, UITheme.Color.Green)
				r.wear.Active = true
				r.wear.AutoButtonColor = true
			end
		end

		if headerSub then
			local m = worn and GameConfig.GetMutationByName(worn)
			headerSub.Text = m
				and ("%d of %d found \u{2022} wearing %s (x%.2f DNA, +%d%% speed)")
					:format(ownedCount, #GameConfig.Mutations, m.name, m.incomeMult, m.speedPct)
				or ("%d of %d found \u{2022} nothing worn -- roll one at the DNA Splicer")
					:format(ownedCount, #GameConfig.Mutations)
		end
	end

	hud.refreshAurasPanel = refreshAurasPanel

	local aurasButton = screenGui:FindFirstChild("AurasButton")
	if aurasButton then
		aurasButton.MouseButton1Click:Connect(function()
			toggleOnly(aurasPanel)
			refreshAurasPanel()
		end)
	end

	refreshAurasPanel()
end
