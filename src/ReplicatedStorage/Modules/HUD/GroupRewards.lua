-- GroupRewards -- the Group & Community Rewards modal (Phase 5.5): join-the-group check, the reward list and its claim.
--
-- MOVED OUT OF `MainUI` (18.9), byte for byte. It was already a closed
-- `;(function() ... end)()` block -- the shape this file's 200-register ceiling forces
-- every panel into -- so the extraction is a change of wrapper, not of code. See
-- `docs/SPLIT.md` for the `hud` contract and `docs/CODEMAP.md` for where the rest went.

local RS = game:GetService("ReplicatedStorage")

local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))

local Remotes = RS.Remotes

local styleCard, PANEL_SHELL = UIKit.styleCard, UIKit.PANEL_SHELL

return function(hud)
	local panelClose, registerPanel, screenGui = hud.panelClose, hud.registerPanel, hud.screenGui
	local toggleOnly = hud.toggleOnly

	local groupPanel = Instance.new("Frame")
	groupPanel.Name = "GroupRewardsPanel"
	groupPanel.Size = UDim2.new(0, 580, 0, 430)
	groupPanel.Visible = false
	groupPanel.ZIndex = 40
	groupPanel.Parent = screenGui
	-- shell first, same as every other panel -- this one was an unstyled grey rectangle too
	styleCard(groupPanel, PANEL_SHELL, UDim.new(0, 22), 5)
	registerPanel(groupPanel)
	panelClose(groupPanel)

	local header, topY = UITheme.PanelHeader(groupPanel, {
		title = "👥 Group & Community",
		subtitle = "Join our group & support the game for permanent buffs and free gifts!",
		accent = UITheme.Color.PanelBlue,
		maxTextSize = 28,
		margin = 16,
		top = 14,
	})

	local scroll = Instance.new("ScrollingFrame")
	scroll.VerticalScrollBarInset = Enum.ScrollBarInset.Always
	scroll.ScrollBarThickness = 12
	scroll.Name = "RewardsList"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.new(0, 16, 0, topY)
	scroll.Size = UDim2.new(1, -32, 1, -topY - 14)
	scroll.ZIndex = groupPanel.ZIndex + UITheme.Z.Content
	scroll.ScrollBarThickness = 12
	scroll.ScrollBarImageColor3 = Color3.fromRGB(60, 70, 90)
	scroll.CanvasSize = UDim2.new(0, 0, 0, 310)
	scroll.Parent = groupPanel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = scroll

	local function makeRewardCard(order, iconEmoji, titleText, descText, buttonAction)
		local card = Instance.new("Frame")
		card.Name = "Card_" .. order
		card.Size = UDim2.new(1, 0, 0, 90)
		card.LayoutOrder = order
		card.ZIndex = scroll.ZIndex
		-- `styleCard`, NOT `UITheme.applyShell`: applyShell is a LOCAL function inside UITheme and is
		-- never exported, so `UITheme.applyShell` is nil and calling it threw here, taking the whole
		-- rewards panel down with it. styleCard is this file's half of the same pair -- see the note
		-- over its definition, which says in as many words that the two routes must build the same
		-- object.
		styleCard(card, UITheme.Color.PanelWhite, UDim.new(0, 14), 3)
		card.Parent = scroll

		UITheme.IconSlot(card, {
			icon = iconEmoji,
			size = UDim2.new(0, 54, 0, 54),
			position = UDim2.new(0, 12, 0.5, 0),
			anchorPoint = Vector2.new(0, 0.5),
			zIndex = card.ZIndex + UITheme.Z.Content,
		})

		UITheme.Label(card, {
			name = "Title",
			text = titleText,
			size = UDim2.new(1, -210, 0, 24),
			position = UDim2.new(0, 76, 0, 14),
			xAlign = "Left",
			maxTextSize = 20,
			minTextSize = 14,
			color = Color3.fromRGB(30, 35, 45),
			zIndex = card.ZIndex + UITheme.Z.Content,
		})

		UITheme.Label(card, {
			name = "Desc",
			text = descText,
			-- -210 -> -245, handing the width to the action button beside it (15.17). The card is
			-- 548 wide; at -210 this description ended at 414 and the 115px button started at 421,
			-- so the seven pixels between them were the only slack on the row.
			size = UDim2.new(1, -245, 0, 42),
			position = UDim2.new(0, 76, 0, 38),
			xAlign = "Left",
			maxTextSize = 14,
			minTextSize = 11,
			color = Color3.fromRGB(80, 95, 115),
			wrapped = true,
			zIndex = card.ZIndex + UITheme.Z.Content,
		})

		local btn = UITheme.Button(card, {
			name = "ActionBtn",
			text = "🎁 Claim",
			-- 115 -> 150 (15.17). `UITheme.Button` reserves the icon's width on both sides of the
			-- label, computed from the button's HEIGHT -- 36px a side here -- so at 115 the label
			-- was 27px and "Claim Chest" could not be drawn. The cap added in UITheme keeps this
			-- readable at any width; the extra 35px is what lets it stay on ONE line.
			size = UDim2.new(0, 150, 0, 42),
			position = UDim2.new(1, -12, 0.5, 0),
			anchorPoint = Vector2.new(1, 0.5),
			color = UITheme.Color.Green,
			radius = 12,
			maxTextSize = 18,
			zIndex = card.ZIndex + UITheme.Z.Content,
		})

		btn.MouseButton1Click:Connect(function()
			buttonAction(btn)
		end)

		return card, btn
	end

	local _, btn1 = makeRewardCard(1, "👥", "Official Roblox Group", "• +10% Permanent DNA on all kills & clicks\n• Daily Group Chest (+1K DNA, 💎25, 🧪Potion)", function(btn)
		local rem = Remotes:FindFirstChild("ClaimGroupChest")
		if rem then rem:FireServer() end
	end)

	local _, btn2 = makeRewardCard(2, "👍", "Like The Game", "• 💎 15 Free Diamonds\n• 🍀 1x Medium Luck Potion", function(btn)
		local rem = Remotes:FindFirstChild("ClaimLikeReward")
		if rem then rem:FireServer() end
	end)

	local _, btn3 = makeRewardCard(3, "⭐", "Favorite The Game", "• 💎 15 Free Diamonds\n• 🌟 2x Evolution Shards", function(btn)
		local rem = Remotes:FindFirstChild("ClaimFavoriteReward")
		if rem then rem:FireServer() end
	end)

	local function refreshGroupRewards()
		if not hud.getData() then return end
		local data = hud.getData()
		-- Card 1: Group
		local inGroup = data.InGroup == true
		local today = math.floor(os.time() / 86400)
		local lastClaim = math.floor((data.ClaimedGroupChest or 0) / 86400)
		local chestReady = inGroup and (today > lastClaim)

		if inGroup then
			if chestReady then
				UITheme.SetText(btn1, "🎁 Claim Chest")
				UITheme.SetColor(btn1, UITheme.Color.Green)
				btn1.Active = true
			else
				UITheme.SetText(btn1, "✅ Claimed")
				UITheme.SetColor(btn1, UITheme.Color.Locked)
				btn1.Active = false
			end
		else
			UITheme.SetText(btn1, "🔗 Join Group")
			UITheme.SetColor(btn1, UITheme.Color.Blue)
			btn1.Active = true
		end

		-- Card 2: Like
		if data.ClaimedLikeReward then
			UITheme.SetText(btn2, "✅ Claimed")
			UITheme.SetColor(btn2, UITheme.Color.Locked)
			btn2.Active = false
		else
			UITheme.SetText(btn2, "🎁 Claim")
			UITheme.SetColor(btn2, UITheme.Color.Green)
			btn2.Active = true
		end

		-- Card 3: Favorite
		if data.ClaimedFavoriteReward then
			UITheme.SetText(btn3, "✅ Claimed")
			UITheme.SetColor(btn3, UITheme.Color.Locked)
			btn3.Active = false
		else
			UITheme.SetText(btn3, "🎁 Claim")
			UITheme.SetColor(btn3, UITheme.Color.Green)
			btn3.Active = true
		end
	end

	hud.showGroupRewards = function()
		refreshGroupRewards()
		toggleOnly(groupPanel)
	end

	-- Spawned + WaitForChild, the same shape as the ZoneTransition connect near the top of the file
	-- and for the same reason: the service creates this remote at run time, so a BUILD-TIME
	-- FindFirstChild is a race. Losing it does not raise -- `if openRemote then` simply skips, the
	-- connect never happens and is never retried, and the chest is silently unopenable for the whole
	-- session. That is the dead-button shape 15.x already paid for once. Not blocking, so a service
	-- that is slow to arrive cannot hold up the HUD being built.
	task.spawn(function()
		local openRemote = Remotes:WaitForChild("OpenGroupRewards", 30)
		if not openRemote then return end
		openRemote.OnClientEvent:Connect(function()
			hud.showGroupRewards()
		end)
	end)

	Remotes.DataUpdate.OnClientEvent:Connect(function(data)
		if groupPanel.Visible then
			refreshGroupRewards()
		end
	end)
end
