-- CosmeticsPanel -- the Vanity board: trails, name plates and emotes (34.2, wired 33.26).
--
-- ===== IT WAS BUILT AND NEVER CONNECTED TO ANYTHING =====
--
-- Her words, with a capture of the tile: *"ovde imamo i nesto novo vidi sta je i uvezi da radi"*.
-- What was here was a complete panel and a complete server (`CosmeticService`, wired in
-- `ServerMain:273`, two RemoteFunctions, purchase and equip both authoritative) with **no line
-- anywhere that built the panel or opened it** -- `MainUI` declared `cosmeticsButton` at its tile
-- row and the local was never read again.
--
-- THREE CONTRACT FAULTS WENT WITH IT, and all three are silent rather than loud, which is why a
-- reader would have called this file finished:
--
--   1. it read `hud.currentData`. There is no such field -- MainUI keeps the save in a FILE-LOCAL
--      `currentData` that is REBOUND on every push, and publishes it as the accessor `hud.getData`
--      for exactly that reason (see the note at the top of MainUI). `hud.currentData` is nil
--      forever, so `refresh` returned on its first line and every row would have stayed on its
--      first-frame paint.
--   2. it wrote `hud.hudRefs.cosmeticsPanel`. `hud` IS hudRefs; `hud.hudRefs` is nil, so those two
--      lines were a hard error at build time -- the panel would not have finished being built even
--      if something had required it.
--   3. it had no `DataUpdate` listener at all, so a purchase's own push could not repaint the row
--      that made it. Every other panel in this HUD refreshes on that remote.
--
-- The remotes are `WaitForChild`ed rather than indexed, because `CosmeticService.Init` creates them
-- at server boot and this file is built during the client's -- indexing wins that race on a warm
-- server and loses it on a cold one, which is the worst kind of bug to ship.

local RS = game:GetService("ReplicatedStorage")
local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))
local Remotes = RS.Remotes

local formatNumber, corner, themeLabel, styleCard = UIKit.formatNumber, UIKit.corner, UIKit.themeLabel, UIKit.styleCard
local styleButton, setButtonColor = UIKit.styleButton, UIKit.setButtonColor

return function(hud)
	local screenGui = hud.screenGui
	
	local panel = Instance.new("Frame")
	panel.Name = "CosmeticsPanel"
	panel.Size = UDim2.new(0, 800, 0, 600)
	panel.Position = hud.PANEL_ANCHOR
	panel.ZIndex = 20
	panel.Visible = false
	panel.Parent = screenGui
	
	styleCard(panel, UITheme.Color.PanelWhite, UDim.new(0, 22), 5)
	
	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 44)
	header.Position = UDim2.new(0, 0, 0, -54)
	header.BackgroundTransparency = 1
	header.Text = "\u{1F457} Vanity & Cosmetics"
	header.Parent = panel
	themeLabel(header, 36, Color3.fromRGB(255, 255, 255))
	
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.Size = UDim2.new(1, -24, 1, -24)
	scroll.Position = UDim2.new(0, 12, 0, 12)
	scroll.BackgroundTransparency = 1
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.Parent = panel
	
	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent = scroll
	
	local rows = {}
	
	local function createSection(titleStr, order)
		local sec = Instance.new("TextLabel")
		sec.Size = UDim2.new(1, 0, 0, 30)
		sec.LayoutOrder = order
		sec.BackgroundTransparency = 1
		sec.TextXAlignment = Enum.TextXAlignment.Left
		sec.Text = "  " .. titleStr
		sec.Parent = scroll
		themeLabel(sec, 24, Color3.fromRGB(46, 54, 74))
		return sec
	end
	
	createSection("Trails", 10)
	createSection("Name Plates", 20)
	createSection("Emotes", 30)
	
	for i, c in ipairs(GameConfig.Cosmetics) do
		local row = Instance.new("Frame")
		row.Name = c.key
		row.Size = UDim2.new(1, -12, 0, 60)
		row.LayoutOrder = (c.type == "Trail" and 11 or (c.type == "NamePlate" and 21 or 31))
		row.Parent = scroll
		styleCard(row, Color3.fromRGB(240, 244, 250), UDim.new(0, 8), 2)
		
		local iconLbl = Instance.new("TextLabel")
		iconLbl.Size = UDim2.new(0, 50, 0, 50)
		iconLbl.Position = UDim2.new(0, 5, 0, 5)
		iconLbl.BackgroundTransparency = 1
		iconLbl.Text = c.emoji
		iconLbl.Parent = row
		themeLabel(iconLbl, 32, Color3.fromRGB(46, 54, 74))
		
		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(0.4, 0, 0.4, 0)
		nameLbl.Position = UDim2.new(0, 65, 0, 10)
		nameLbl.BackgroundTransparency = 1
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.Text = c.name
		nameLbl.Parent = row
		themeLabel(nameLbl, 20, Color3.fromRGB(46, 54, 74))
		
		local btnDiamonds = Instance.new("TextButton")
		btnDiamonds.Size = UDim2.new(0, 110, 0, 40)
		btnDiamonds.Position = UDim2.new(1, -240, 0.5, -20)
		btnDiamonds.Parent = row
		styleButton(btnDiamonds, UITheme.Color.Aqua, c.priceDiamonds .. " Gems")
		
		local btnRobux = nil
		if c.productId and c.productId > 0 then
			btnRobux = Instance.new("TextButton")
			btnRobux.Size = UDim2.new(0, 110, 0, 40)
			btnRobux.Position = UDim2.new(1, -120, 0.5, -20)
			btnRobux.Parent = row
			styleButton(btnRobux, UITheme.Color.Mint, "R$ " .. c.priceRobux)
		else
			btnDiamonds.Position = UDim2.new(1, -120, 0.5, -20)
		end
		
		local btnEquip = Instance.new("TextButton")
		btnEquip.Size = UDim2.new(0, 160, 0, 40)
		btnEquip.Position = UDim2.new(1, -170, 0.5, -20)
		btnEquip.Visible = false
		btnEquip.Parent = row
		styleButton(btnEquip, UITheme.Color.Purple, "Equip")
		
		btnDiamonds.MouseButton1Click:Connect(function()
			local rf = Remotes:WaitForChild("CosmeticPurchase", 10)
			if rf then rf:InvokeServer(c.key) end
		end)
		
		if btnRobux then
			btnRobux.MouseButton1Click:Connect(function()
				if c.productId and c.productId > 0 then
					game:GetService("MarketplaceService"):PromptProductPurchase(game.Players.LocalPlayer, c.productId)
				end
			end)
		end
		
		btnEquip.MouseButton1Click:Connect(function()
			local data = hud.getData and hud.getData()
			if not data then return end
			local worn = data.WornCosmetics or {}
			local rf = Remotes:WaitForChild("CosmeticEquip", 10)
			if not rf then return end
			if worn[c.type] == c.key then
				rf:InvokeServer(c.type, "")
			else
				rf:InvokeServer(c.type, c.key)
			end
		end)
		
		rows[c.key] = {
			row = row,
			btnDiamonds = btnDiamonds,
			btnRobux = btnRobux,
			btnEquip = btnEquip,
			c = c
		}
	end
	
	local function refresh()
		local data = hud.getData and hud.getData()
		if not data then return end
		
		local owned = data.CosmeticsOwned or {}
		local worn = data.WornCosmetics or {}
		
		for key, refs in pairs(rows) do
			if owned[key] then
				refs.btnDiamonds.Visible = false
				refs.btnRobux.Visible = false
				refs.btnEquip.Visible = true
				
				if worn[refs.c.type] == key then
					setButtonColor(refs.btnEquip, UITheme.Color.Locked)
					refs.btnEquip.Text = "Unequip"
				else
					setButtonColor(refs.btnEquip, UITheme.Color.Purple)
					refs.btnEquip.Text = "Equip"
				end
			else
				refs.btnDiamonds.Visible = true
				refs.btnRobux.Visible = true
				refs.btnEquip.Visible = false
				
				if (data.Diamonds or 0) >= refs.c.priceDiamonds then
					setButtonColor(refs.btnDiamonds, UITheme.Color.Aqua)
				else
					setButtonColor(refs.btnDiamonds, UITheme.Color.Locked)
				end
			end
		end
		
		scroll.CanvasSize = UDim2.new(0, 0, 0, (#GameConfig.Cosmetics * 68) + (3 * 38) + 16)
	end
	
	hud.registerPanel(panel)
	hud.panelClose(panel)
	
	-- ONTO `hud` ITSELF. `hud` is MainUI's `hudRefs` table -- there is no `hud.hudRefs` -- and
	-- these two lines used to reach for one and throw.
	hud.cosmeticsPanel = panel
	hud.refreshCosmeticsPanel = refresh

	-- THE CHANNEL EVERY OTHER PANEL USES. Both remotes here answer with a `PushToClient`, so this is
	-- what repaints the row that was just bought or worn; without it the board only ever showed the
	-- state it was built in.
	Remotes.DataUpdate.OnClientEvent:Connect(refresh)
	
	return panel
end