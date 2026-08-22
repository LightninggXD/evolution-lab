-- AurasPanel -- the seven Splicer mutations, what you have rolled of each, and which one you wear.
--
-- REPLACES `HUD/Quests.lua` (31.22), which despite its name held this panel and nothing else -- the
-- name was inherited from the IIFE it was extracted out of in 18.9 and had been wrong ever since.
-- The behaviour is carried over unchanged; what is new is the drawing, which moved to the card
-- style Kristina photographed (see `HUD/AuraCard`), and the split into two files.
--
-- WHAT A MUTATION ACTUALLY IS, because two of the three facts here are not visible from this file:
--   * it is ROLLED at the DNA Splicer, never bought -- so this panel has no price and no purchase
--     button, whatever the mock-up's borrowed trophy/Robux row suggested;
--   * `data.SplicerFound` has counted every roll since Phase 12, which is why a collection screen is
--     seven rows and a button rather than a feature: the save already knew the collection;
--   * WEARING one is `Remotes.EquipMutation`, and the server-side half of that has to set the
--     `Mutation` attribute as well as the save field or the aura on the body never changes. See
--     `SplicerService.HandleEquipMutation`.
--
-- WEARING A WEAKER AURA IS ALLOWED ON PURPOSE. Both stats rise together with rarity, so it is never
-- an optimisation -- it is the look, because the particles on the body take the mutation's colour.
-- Each card prints the multiplier it costs and the header keeps printing the one in effect, so the
-- trade is stated twice before it is made.

local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))
local AuraCard = require(script.Parent:WaitForChild("AuraCard"))

local Remotes = RS.Remotes

local styleCard = UIKit.styleCard

-- Measured off the mock-up in `StarterGui.AurasGui`: a lilac board with a sunken plum well cut into
-- it. This is the one panel in the game that is not `PanelLilac`, and that is deliberate -- it is
-- the panel Kristina drew the reference for.
--
-- BOTH ARE DEEPER THAN THE MOCK-UP'S OWN NUMBERS, AND THAT IS NOT A DEVIATION. The mock-up painted
-- a flat `BackgroundColor3`; `PanelSurface` paints a MOULDED one -- `gradientFor` runs the fill from
-- `shade(c, 0.4)` at the top edge to `shade(c, -0.1)` at the bottom. Handing it the mock-up's
-- rgb(162,124,202) put the top third of the board at rgb(199,176,223), which photographed as a pale
-- lilac panel with a purple foot rather than as the purple board in the reference. rgb(126,78,178)
-- is that colour solved backwards: the gradient's own mid-band lands on the reference's shade.
local BOARD = Color3.fromRGB(126, 78, 178)
local WELL = Color3.fromRGB(58, 32, 88)

local PANEL_W, PANEL_H = 680, 520
local CARD_GAP = 10

return function(hud)
	local panelClose, registerPanel, screenGui = hud.panelClose, hud.registerPanel, hud.screenGui
	local toggleOnly = hud.toggleOnly

	local panel = Instance.new("Frame")
	panel.Name = "AurasPanel"
	panel.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
	panel.Visible = false
	panel.ZIndex = 40
	panel.Parent = screenGui
	-- SHELL BEFORE registerPanel, and that order is load-bearing: the cyan panel rim is chosen inside
	-- registerPanel off a UIStroke that has to already exist. (This board is coloured, so it keeps
	-- the ordinary dark outline rather than taking the rim -- but the ordering rule still holds, and
	-- a later repaint to a white board would need it.)
	styleCard(panel, BOARD, UDim.new(0, 22), 5)
	registerPanel(panel)
	panelClose(panel)

	local _, topY, _, headerSub = UITheme.PanelHeader(panel, {
		title = "\u{1F9EC} Auras",
		subtitle = "Rolled at the DNA Splicer -- one is worn at a time",
		surfaceColor = BOARD,
		accent = UITheme.Color.Purple,
		maxTextSize = 28,
		margin = 16,
		top = 14,
	})

	-- ===== THE SUBTITLE'S INK HAS TO BE RE-DECIDED HERE, AND ONLY HERE =====
	--
	-- `PanelHeader` paints its subtitle `Color.InkSoft` unconditionally, and the comment where it
	-- does so says why: "the board is always a light surface since PanelSurface paints it". That is
	-- true of the other nineteen panels and false of this one. Dark ink on a mid-purple board is the
	-- exact failure the probe cannot see and a capture always can -- every property reads correct.
	--
	-- The halo has to be re-armed as well as the colour. `outlineText` suppresses a stroke by setting
	-- BOTH thickness 0 and transparency 1 (so a later width-only sweep cannot re-arm it by accident),
	-- so writing thickness alone would leave an invisible one.
	if headerSub then
		headerSub.TextColor3 = Color3.fromRGB(246, 238, 255)
		local halo = headerSub:FindFirstChildOfClass("UIStroke")
		if halo then
			halo.Thickness = 2.5
			halo.Transparency = 0
		end
	end

	-- ---- the sunken well the list sits in
	local well = Instance.new("Frame")
	well.Name = "AuraWell"
	well.Position = UDim2.new(0, 16, 0, topY)
	well.Size = UDim2.new(1, -32, 1, -topY - 16)
	well.BackgroundColor3 = WELL
	well.BorderSizePixel = 0
	well.ZIndex = panel.ZIndex + UITheme.Z.Content
	well.Parent = panel
	local wellCorner = Instance.new("UICorner")
	wellCorner.CornerRadius = UDim.new(0, 18)
	wellCorner.Parent = well
	local wellStroke = Instance.new("UIStroke")
	wellStroke.Color = UITheme.Color.Outline
	wellStroke.Thickness = 3.5
	wellStroke.LineJoinMode = Enum.LineJoinMode.Round
	wellStroke.Parent = well
	-- ===== THE ATTRIBUTE IS WHAT KEEPS THE SCROLL FADE FROM BEING A WHITE SMEAR =====
	--
	-- `HUD/ScrollAffordance` sweeps every ScrollingFrame under the HUD and hangs a fade at the cut,
	-- painted with `scroll.Parent:GetAttribute("BaseColor")` and falling back to PANEL_SHELL -- WHITE
	-- -- when there is none. Every other list in the game hangs off a shelled panel, which carries
	-- that attribute because `applyShell` stamps it. This well is drawn by hand, so it has to stamp
	-- its own or it gets a white gradient down the bottom of a plum box.
	well:SetAttribute("BaseColor", WELL)

	local list = Instance.new("ScrollingFrame")
	list.Name = "AuraList"
	list.Position = UDim2.new(0, 8, 0, 8)
	list.Size = UDim2.new(1, -16, 1, -16)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ClipsDescendants = true
	-- `AutomaticCanvasSize`, never a hand-computed one. The old panel multiplied out row heights,
	-- which was right until it wasn't: a card whose height is decided in another file is a canvas
	-- that goes stale the moment that file is re-tuned.
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 10
	list.ZIndex = well.ZIndex + UITheme.Z.Content
	list.Parent = well
	-- The bar `ScrollAffordance` would otherwise give this list is `Color.Outline` at 0.35 -- a
	-- near-black grip chosen for a near-white board, and invisible on a plum one. The attribute is
	-- read by that pass; see the note there.
	list:SetAttribute("ScrollInk", Color3.fromRGB(196, 160, 240))

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, CARD_GAP)
	layout.Parent = list

	-- Room for the stroke on all four sides. A card's UIStroke is 3.5 px drawn OUTSIDE its bounds and
	-- the list clips, so without the horizontal half the outline is sliced off down the whole column.
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = list

	-- The remote is created by SplicerService.Init at server boot, so it is there long before a
	-- player can open this -- but it is waited for rather than looked up, because a FindFirstChild at
	-- build time on a remote created anywhere else is a permanently dead button.
	local equipRemote
	task.spawn(function()
		equipRemote = Remotes:WaitForChild("EquipMutation", 30)
	end)

	local function wear(name)
		if not equipRemote then return end
		equipRemote:FireServer(name)
	end

	-- `GameConfig.Mutations` is RANK-ORDERED and that order is load-bearing everywhere else in the
	-- game -- the pity floor, the announce threshold and "which of two is better" all compare
	-- indices. A new entry goes in rank position and is never appended, and this panel inherits the
	-- order for free by walking it.
	local cards = {}
	for i, mut in ipairs(GameConfig.Mutations) do
		cards[mut.name] = AuraCard.New(list, mut, i, wear)
	end

	local function refreshAurasPanel()
		local data = hud.getData()
		local found = (data and data.SplicerFound) or {}
		local worn = data and data.SplicerMutation
		local ownedCount = 0

		for _, mut in ipairs(GameConfig.Mutations) do
			local n = tonumber(found[mut.name]) or 0
			if n > 0 then ownedCount += 1 end
			cards[mut.name].SetState(n, worn == mut.name)
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
			toggleOnly(panel)
			refreshAurasPanel()
		end)
	end

	refreshAurasPanel()
end
