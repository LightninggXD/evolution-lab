local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")
local RS = game:GetService("ReplicatedStorage")
local UITheme = require(RS.Modules:WaitForChild("UITheme"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local FriendInviteButton = {}
local btn = nil

function FriendInviteButton.Init(screenGui)
	if btn then return btn end

	-- Rebuild using UITheme standard kit
	btn = UITheme.Button("Invite\nFriends")
	btn.Name = "FriendInviteButton"
	btn.Size = UDim2.new(0, 72, 0, 72)
	btn.Position = UDim2.new(0, 20, 1, -90) -- Middle bottom, above hotbar
	btn.Parent = screenGui

	-- The pill for showing live count and bonus percentage
	local badge = Instance.new("TextLabel")
	badge.Name = "Badge"
	badge.Size = UDim2.new(0, 24, 0, 24)
	badge.Position = UDim2.new(1, -12, 0, -12)
	badge.BackgroundColor3 = UITheme.Color.Action
	badge.Text = "+0%"
	badge.Font = UITheme.Font.Display
	badge.TextSize = 12
	badge.TextColor3 = UITheme.Color.TextLight
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
		local data = PlayerData.Get()
		if not data then return end
		-- Server stamped figure from DNAService
		local count = data.__friendCount or 0
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

	-- We listen to data updates to redraw, not PlayerAdded, since the server tells us when it's real
	PlayerData.Changed:Connect(updateBadge)
	task.spawn(updateBadge)
	return btn
end

return FriendInviteButton
