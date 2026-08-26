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
		
		local btnRobux = Instance.new("TextButton")
		btnRobux.Size = UDim2.new(0, 110, 0, 40)
		btnRobux.Position = UDim2.new(1, -120, 0.5, -20)
		btnRobux.Parent = row
		styleButton(btnRobux, UITheme.Color.Mint, "R$ " .. c.priceRobux)
		
		local btnEquip = Instance.new("TextButton")
		btnEquip.Size = UDim2.new(0, 160, 0, 40)
		btnEquip.Position = UDim2.new(1, -170, 0.5, -20)
		btnEquip.Visible = false
		btnEquip.Parent = row
		styleButton(btnEquip, UITheme.Color.Purple, "Equip")
		
		btnDiamonds.MouseButton1Click:Connect(function()
			Remotes.CosmeticPurchase:InvokeServer(c.key)
		end)
		
		btnRobux.MouseButton1Click:Connect(function()
			if c.productId and c.productId > 0 then
				game:GetService("MarketplaceService"):PromptProductPurchase(game.Players.LocalPlayer, c.productId)
			end
		end)
		
		btnEquip.MouseButton1Click:Connect(function()
			local data = hud.currentData
			if not data then return end
			local worn = data.WornCosmetics or {}
			if worn[c.type] == c.key then
				Remotes.CosmeticEquip:InvokeServer(c.type, "")
			else
				Remotes.CosmeticEquip:InvokeServer(c.type, c.key)
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
		local data = hud.currentData
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
	
	hud.hudRefs.cosmeticsPanel = panel
	hud.hudRefs.refreshCosmeticsPanel = refresh
	
	return panel
end