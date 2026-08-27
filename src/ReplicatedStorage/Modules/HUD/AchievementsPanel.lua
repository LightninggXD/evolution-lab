local RS = game:GetService("ReplicatedStorage")
local GameConfig = require(RS.Modules.GameConfig)
local Achievements = require(RS.Modules.GameConfig.Achievements)
local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))
local Remotes = RS.Remotes

local formatNumber, corner, themeLabel, styleCard = UIKit.formatNumber, UIKit.corner, UIKit.themeLabel, UIKit.styleCard
local styleButton, setButtonColor = UIKit.styleButton, UIKit.setButtonColor

return function(hud)
	local screenGui = hud.screenGui
	
	local panel = Instance.new("Frame")
	panel.Name = "AchievementsPanel"
	panel.Size = UDim2.new(0, 720, 0, 560)
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
	header.Text = "\u{1F3C6} Titles & Goals"
	header.Parent = panel
	themeLabel(header, 36, Color3.fromRGB(255, 255, 255))
	
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.Size = UDim2.new(1, -24, 1, -24)
	scroll.Position = UDim2.new(0, 12, 0, 12)
	scroll.BackgroundTransparency = 1
	-- Left at 6 and NOT coloured here: `HUD/ScrollAffordance` polishes every ScrollingFrame
	-- under the HUD's ScreenGui, including one built lazily on first open (it listens to
	-- DescendantAdded), and it is what gives this bar its Outline colour and the fade.
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.Parent = panel
	
	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent = scroll
	
	local rows = {}
	
	for i, ach in ipairs(Achievements) do
		local row = Instance.new("Frame")
		row.Name = ach.key
		-- 76, NOT 60. The reward line below needs a line of its own: at 60 it was parented to the
		-- 80-wide Claim button and hung 4 px off the bottom of the card, so `Title: "Slayer"`
		-- rendered as `Title:` -- the title's NAME is the entire reward, and it was the half that
		-- got cut. The canvas step below moves with this number.
		row.Size = UDim2.new(1, -12, 0, 76)
		row.LayoutOrder = i
		row.Parent = scroll
		styleCard(row, Color3.fromRGB(240, 244, 250), UDim.new(0, 8), 2)
		
		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(0.6, 0, 0.4, 0)
		nameLbl.Position = UDim2.new(0, 12, 0, 8)
		nameLbl.BackgroundTransparency = 1
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.Text = ach.name
		nameLbl.Parent = row
		themeLabel(nameLbl, 20, Color3.fromRGB(46, 54, 74))
		
		local descLbl = Instance.new("TextLabel")
		descLbl.Size = UDim2.new(0.6, 0, 0.4, 0)
		descLbl.Position = UDim2.new(0, 12, 0, 30)
		descLbl.BackgroundTransparency = 1
		descLbl.TextXAlignment = Enum.TextXAlignment.Left
		descLbl.Text = ach.desc
		descLbl.Parent = row
		themeLabel(descLbl, 16, Color3.fromRGB(120, 130, 150))
		
		local progBg = Instance.new("Frame")
		progBg.Size = UDim2.new(0.2, 0, 0, 12)
		-- 0.5 was the middle of a 60-tall row; the row is 76 now and carries the reward line
		-- at the bottom, so the bar and the button hold the middle of the TOP 56.
		progBg.Position = UDim2.new(0.65, 0, 0, 28)
		progBg.Parent = row
		styleCard(progBg, Color3.fromRGB(220, 224, 230), UDim.new(0, 6), 0)
		
		local progFill = Instance.new("Frame")
		progFill.Size = UDim2.new(0, 0, 1, 0)
		progFill.BackgroundColor3 = UITheme.Color.Green
		progFill.Parent = progBg
		corner(progFill, UDim.new(0, 6))
		
		local progTxt = Instance.new("TextLabel")
		progTxt.Size = UDim2.new(1, 0, 1, 16)
		progTxt.Position = UDim2.new(0, 0, 0, -8)
		progTxt.BackgroundTransparency = 1
		if string.sub(ach.key, 1, 5) == "Time_" then
			progTxt.Text = "0h / " .. formatNumber(math.floor(ach.goal / 3600)) .. "h"
		else
			progTxt.Text = "0 / " .. formatNumber(ach.goal)
		end
		progTxt.Parent = progBg
		themeLabel(progTxt, 14, Color3.fromRGB(46, 54, 74))
		
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, 80, 0, 36)
		btn.Position = UDim2.new(1, -92, 0, 16)
		btn.Parent = row
		styleButton(btn, UITheme.Color.Blue, "Claim")
		
		local rewardTxt = ""
		if ach.reward.dna then rewardTxt = "+" .. formatNumber(ach.reward.dna) .. " DNA"
		elseif ach.reward.diamonds then rewardTxt = "+" .. formatNumber(ach.reward.diamonds) .. " Diamonds"
		elseif ach.reward.title then rewardTxt = 'Title: "' .. ach.reward.title .. '"' end
		
		-- ON THE ROW, not on the button. As a child of an 80-wide button it was 80 px wide and
		-- clipped every reward longer than "+50 Diamonds"; `TextBounds` would have reported it as
		-- fitting, because bounds measure the truncation ([[roblox-textbounds-reports-the-truncation]]).
		-- Right-aligned so it lines up under the Claim button, which is the thing it describes.
		local rewLbl = Instance.new("TextLabel")
		rewLbl.Size = UDim2.new(1, -24, 0, 16)
		rewLbl.Position = UDim2.new(0, 12, 1, -20)
		rewLbl.BackgroundTransparency = 1
		rewLbl.TextXAlignment = Enum.TextXAlignment.Right
		rewLbl.Text = rewardTxt
		rewLbl.Parent = row
		themeLabel(rewLbl, 13, Color3.fromRGB(120, 130, 150))
		
		btn.MouseButton1Click:Connect(function()
			local data = hud.getData and hud.getData()
			if not data then return end
			
			local claimed = data.AchievementsClaimed or {}
			if claimed[ach.key] then
				if ach.reward.title then
					local worn = data.WornTitle
					if worn == ach.reward.title then
						Remotes.EquipTitle:InvokeServer("")
					else
						Remotes.EquipTitle:InvokeServer(ach.reward.title)
					end
				end
				return
			end
			
			local ok = Remotes.AchievementClaim:InvokeServer(ach.key)
			if ok then
				-- Server fires DataUpdate, we just wait for refresh
			end
		end)
		
		rows[ach.key] = {
			row = row,
			progFill = progFill,
			progTxt = progTxt,
			btn = btn,
			ach = ach
		}
	end
	
	local function refresh()
		local data = hud.getData and hud.getData()
		if not data then return end
		
		local claimed = data.AchievementsClaimed or {}
		local worn = data.WornTitle
		
		local count = 0
		for key, refs in pairs(rows) do
			count = count + 1
			local val = data[refs.ach.counter] or 0
			local ratio = math.clamp(val / refs.ach.goal, 0, 1)
			refs.progFill.Size = UDim2.new(ratio, 0, 1, 0)
			if string.sub(key, 1, 5) == "Time_" then
				refs.progTxt.Text = formatNumber(math.floor(val / 3600)) .. "h / " .. formatNumber(math.floor(refs.ach.goal / 3600)) .. "h"
			else
				refs.progTxt.Text = formatNumber(val) .. " / " .. formatNumber(refs.ach.goal)
			end
			
			if claimed[key] then
				if refs.ach.reward.title then
					if worn == refs.ach.reward.title then
						setButtonColor(refs.btn, UITheme.Color.Locked)
						refs.btn.Text = "Worn"
					else
						setButtonColor(refs.btn, UITheme.Color.Purple)
						refs.btn.Text = "Equip"
					end
				else
					setButtonColor(refs.btn, UITheme.Color.Locked)
					refs.btn.Text = "Claimed"
				end
			else
				if val >= refs.ach.goal then
					setButtonColor(refs.btn, UITheme.Color.Gold)
					refs.btn.Text = "Claim!"
				else
					setButtonColor(refs.btn, UITheme.Color.Locked)
					refs.btn.Text = "Locked"
				end
			end
		end
		
		scroll.CanvasSize = UDim2.new(0, 0, 0, count * 84 + 8)
	end
	
	Remotes.DataUpdate.OnClientEvent:Connect(function()
		if panel.Visible then refresh() end
	end)
	hud.registerPanel(panel)
	hud.panelClose(panel)
	
	hud.achievementsPanel = panel
	hud.refreshAchievementsPanel = refresh
	
	return panel
end