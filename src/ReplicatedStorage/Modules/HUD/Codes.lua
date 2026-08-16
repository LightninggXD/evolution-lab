-- Codes -- the promo-code box on the rewards board and the remote behind it (Phase 5.1).
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

local themeLabel, styleCard = UIKit.themeLabel, UIKit.styleCard

return function(hud)
	local rewardPanel = hud.rewardPanel

	local bar = Instance.new("Frame")
	bar.Name = "CodeBar"
	bar.Size = UDim2.new(1, -50, 0, 44)
	-- directly above the banner: banner sits at 1,-14 and is 44 tall, so its top edge is 1,-58
	bar.Position = UDim2.new(0.5, 0, 1, -66)
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.BackgroundTransparency = 1
	bar.ZIndex = rewardPanel.ZIndex + 1
	bar.Parent = rewardPanel

	local shell = Instance.new("Frame")
	shell.Name = "InputShell"
	shell.Size = UDim2.new(0.60, -6, 1, 0)
	shell.ZIndex = bar.ZIndex
	shell.Parent = bar
	-- PanelWhite, and the text on it is Outline rather than white: this is the one input surface in
	-- the game and a typed code has to be readable while it is being typed
	styleCard(shell, UITheme.Color.PanelWhite, UDim.new(1, 0), 4)

	local box = Instance.new("TextBox")
	box.Name = "CodeInput"
	box.BackgroundTransparency = 1
	box.Size = UDim2.new(1, -28, 1, -12)
	box.Position = UDim2.new(0, 14, 0.5, 0)
	box.AnchorPoint = Vector2.new(0, 0.5)
	box.ClearTextOnFocus = false
	box.Text = ""
	box.PlaceholderText = "\u{1F39F}\u{FE0F}  Enter a code..."
	box.PlaceholderColor3 = Color3.fromRGB(140, 136, 158)
	box.TextColor3 = UITheme.Color.Outline
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Font = UITheme.Font.Display
	box.TextScaled = true
	box.ZIndex = bar.ZIndex + UITheme.Z.Content
	box.Parent = shell
	local boxClamp = Instance.new("UITextSizeConstraint")
	boxClamp.MinTextSize = 14
	boxClamp.MaxTextSize = 22
	boxClamp.Parent = box

	local redeemButton = UITheme.Button(bar, {
		name = "Redeem", text = "REDEEM", color = UITheme.Color.Green,
		size = UDim2.new(0.25, -6, 1, 0), position = UDim2.new(0.60, 6, 0, 0),
		radius = 12, zIndex = bar.ZIndex, maxTextSize = 22, shadow = false,
	})

	local leftLabel = Instance.new("TextLabel")
	leftLabel.Name = "CodesLeft"
	leftLabel.Size = UDim2.new(0.15, -6, 1, 0)
	leftLabel.Position = UDim2.new(0.85, 6, 0, 0)
	leftLabel.BackgroundTransparency = 1
	leftLabel.Text = ""
	leftLabel.ZIndex = bar.ZIndex + UITheme.Z.Content
	leftLabel.Parent = bar
	themeLabel(leftLabel, 20)

	local function submit()
		local typed = box.Text
		if typed:gsub("%s", "") == "" then return end
		-- looked up rather than held, like the audio remote: CodesService creates it in Init and a
		-- WaitForChild at build time would stall the HUD if that ever stopped happening
		local remote = Remotes:FindFirstChild("RedeemCode")
		if remote then
			remote:FireServer(typed)
		end
		-- cleared either way. The server answers with a toast, and leaving a refused code sitting in
		-- the box invites the player to press REDEEM again into the rate limiter.
		box.Text = ""
	end

	redeemButton.MouseButton1Click:Connect(submit)
	-- Enter submits: this is a box people paste into off a web page, and reaching for a button
	-- afterwards is the kind of small friction that makes a code feel broken
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then submit() end
	end)

	-- Counted CLIENT-SIDE off GameConfig and the save the client already holds -- the same arithmetic
	-- CodesService.CountUnused does server-side, but asking for it would be a remote round trip for a
	-- number both sides can already see.
	hud.refreshCodes = function(data)
		local redeemed = (data and data.RedeemedCodes) or {}
		local left = 0
		for _, entry in ipairs(GameConfig.Codes) do
			if not GameConfig.IsCodeExpired(entry)
				and not redeemed[GameConfig.NormaliseCode(entry.code)] then
				left += 1
			end
		end
		-- says nothing at all when there is nothing left to say, rather than printing "0 left" as a
		-- small permanent disappointment on the free-stuff screen
		leftLabel.Text = left > 0 and (left .. " new") or ""
	end
end
