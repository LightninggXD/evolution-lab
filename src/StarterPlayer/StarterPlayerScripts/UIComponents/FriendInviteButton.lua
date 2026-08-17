local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")
local RS = game:GetService("ReplicatedStorage")
local UITheme = require(RS.Modules:WaitForChild("UITheme"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local FriendInviteButton = {}
local btn = nil

local function getFriendCount()
	local count = 0
	local localPlayer = Players.LocalPlayer
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= localPlayer and localPlayer:IsFriendsWith(p.UserId) then
			count = count + 1
		end
	end
	return count
end

function FriendInviteButton.Init(screenGui)
	if btn then return btn end

	btn = Instance.new("ImageButton")
	btn.Name = "FriendInviteButton"
	btn.Size = UDim2.new(0, 64, 0, 64)
	btn.Position = UDim2.new(0, 20, 1, -80) -- Middle bottom, above hotbar
	btn.BackgroundColor3 = UITheme.Color.Cream
	btn.Image = "" -- REPLACE WITH UPLOADED ICON
	btn.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Color = UITheme.Color.Outline
	stroke.Thickness = 3
	stroke.Parent = btn

	local badge = Instance.new("TextLabel")
	badge.Name = "Badge"
	badge.Size = UDim2.new(0, 24, 0, 24)
	badge.Position = UDim2.new(1, -12, 0, -12)
	badge.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
	badge.Text = "+0%"
	badge.Font = UITheme.Font.Display
	badge.TextSize = 12
	badge.TextColor3 = Color3.fromRGB(255, 255, 255)
	badge.Visible = false
	badge.Parent = btn

	local bCorner = Instance.new("UICorner")
	bCorner.CornerRadius = UDim.new(1, 0)
	bCorner.Parent = badge
	
	local bStroke = Instance.new("UIStroke")
	bStroke.Color = UITheme.Color.Outline
	bStroke.Thickness = 2
	bStroke.Parent = badge

	local function updateBadge()
		local count = getFriendCount()
		if count > 0 then
			badge.Text = "+" .. (count * 5) .. "%"
			badge.Visible = true
		else
			badge.Visible = false
		end
	end

	btn.MouseButton1Click:Connect(function()
		local ok, err = pcall(function()
			SocialService:PromptGameInvite(Players.LocalPlayer)
		end)
		if not ok then
			warn("Failed to prompt game invite:", err)
		end
	end)

	Players.PlayerAdded:Connect(function() task.wait(1) updateBadge() end)
	Players.PlayerRemoving:Connect(function() task.wait(1) updateBadge() end)
	
	task.spawn(updateBadge)
	return btn
end

return FriendInviteButton

