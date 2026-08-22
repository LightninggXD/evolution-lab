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

-- ===== THE BOARD IS AN ORDINARY LIGHT PANEL AGAIN (31.23) =====
--
-- 31.22 painted this board in the mock-up's own purple, reasoning that the mock-up was the
-- reference. Kristina saw it run and reversed that half of it: *"i samo napravi da je i ovde svetla
-- pozadina bela neka kao u ostalim panelima tipa rebirth, svetlija tema znaci"*. The CARDS are the
-- design she asked for; the board under them was never part of it, and one purple screen in a HUD
-- of white ones reads as a different game rather than as a themed panel.
--
-- `PANEL_SHELL` is the white `shopFrame`, `masteryPanel`, `rewardPanel` and the inventory are all
-- painted, and picking it is also what hands this panel the cyan rim: `registerPanel` decides that
-- by testing the shell's own fill for near-white, so a coloured board silently opts out of it. That
-- is the repaint the ordering note under `styleCard` was written against.
--
-- `Color.Cloud` is the kit's token for the well -- "an inset rather than a raised chip: progress-bar
-- tracks, wells, list backings" -- so the list still sits in a groove rather than flat on the board.
--
-- NOTHING ABOUT THE CARDS MOVED, and that is what makes this a two-constant change rather than a
-- redraw: each is painted its own mutation's colour and carries the two-tone halo scheme `AuraCard`
-- documents, which was chosen to survive rgb(20,20,20) through rgb(255,240,150) and therefore never
-- depended on the board behind it being dark.
local BOARD = UIKit.PANEL_SHELL
local WELL = UITheme.Color.Cloud

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
	-- registerPanel off a UIStroke that has to already exist. Since 31.23 this board IS white, so the
	-- rim is live and the ordering has stopped being theoretical -- swapping these two lines would
	-- leave the panel wearing the ordinary dark card outline with nothing to say it had.
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

	-- THE SUBTITLE KEEPS `PanelHeader`'S OWN INK NOW. 31.22 overrode it to near-white and re-armed
	-- the halo `outlineText` had suppressed, because that helper paints `Color.InkSoft` on the stated
	-- assumption that "the board is always a light surface" -- true of the other nineteen panels and
	-- false of a purple one. 31.23 puts this panel back inside the assumption, so the override is
	-- DELETED rather than left sitting there as a no-op the next reader would have to undo.

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
	-- its own. It survived the 31.23 repaint on purpose: `Cloud` is near-white but it is not PANEL
	-- SHELL white, and an unstamped fade would paint the foot of the groove a shade too light -- a
	-- soft horizontal band across the last card rather than a fade into the well's own colour.
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
	-- No `ScrollInk` here any more. 31.22 added one because `ScrollAffordance`'s near-black grip at
	-- 0.35 was invisible on the plum well; on `Cloud` that constant is exactly what it was written
	-- for, and the hook it needed came back out of that file in the same pass (31.23) rather than
	-- being left behind as a branch with no caller.

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
