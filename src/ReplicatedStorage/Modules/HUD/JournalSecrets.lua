-- JournalSecrets -- the Journal's record of what has been FOUND, and deliberately nothing at all
-- about what has not.
--
-- ===== WHY THIS ROW IS NOT A GRID OF LOCKED DISCS (17.6) =====
--
-- Every other section in this panel draws its whole ladder and dims the entries you do not own yet,
-- because that dim disc is the goal -- it is the queue, and seeing it is the point. A secret is the
-- exact opposite. 17.6's own words: *"it must not appear in any list before it is found and must be
-- discoverable without a wiki."* A row of two grey padlocks reading `???` tells the player there are
-- exactly two secrets in Forest and that they have found one, which is most of what a wiki would
-- have told them. So this row renders ONLY the found ones, and when nothing has been found it is not
-- merely empty -- `row.Visible = false`, so the section does not exist on screen at all and the
-- Journal gives away neither the count nor the fact that secrets are a thing.
--
-- That is also why there is no `n / total` caption anywhere in here: the denominator is the leak.
--
-- ===== IT IS NOT A CHARACTER, SO IT DOES NOT REUSE THE DISC BUILDER =====
--
-- `JournalGrid`'s cell wants `entry.key`, `entry.color`, `entry.rarity`, a rig to preview and a
-- damage percentage. A secret has none of those -- it is an id, a zone and a payout -- so feeding it
-- through `sections` would have meant five nil-guards inside the hottest loop in the panel and a
-- `Discovered n / 200` count that silently grew by two. A separate row, in its own module, costs
-- nothing that loop pays.

local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))

local themeLabel, corner = UIKit.themeLabel, UIKit.corner

-- What each reward type actually handed over, in the player's words rather than the config's.
-- `rewardName` is the noun the toast used, so the two screens agree.
local function payoutLine(secret)
	if secret.rewardType == "training" then
		return ("%s  \u{00B7}  +%d training reps"):format(secret.rewardName or "Reward",
			GameConfig.SecretTrainingReps or 0)
	elseif secret.rewardType == "pet" then
		return ("%s  \u{00B7}  a hidden pet"):format(secret.rewardName or "Reward")
	elseif secret.rewardType == "mutation" then
		return ("%s  \u{00B7}  mutation"):format(secret.rewardName or "Reward")
	end
	return secret.rewardName or "Reward"
end

return function(hud)
	local characterScroll = hud.characterScroll
	if not characterScroll then return end

	-- LayoutOrder is far past the last real section (20 stages, then VIP at 21 and Event at 22), so
	-- this always sits at the bottom of the list however many stages the config grows.
	local row = Instance.new("Frame")
	row.Name = "SecretsFound"
	row.LayoutOrder = 999
	row.Size = UDim2.new(1, 0, 0, 26)
	row.BackgroundTransparency = 1
	row.Visible = false
	row.Parent = characterScroll

	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.Size = UDim2.new(1, -8, 0, 22)
	header.Position = UDim2.new(0, 6, 0, 0)
	header.BackgroundTransparency = 1
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Text = "\u{1F5DD}\u{FE0F} Secrets Found"
	header.Parent = row
	themeLabel(header, 20, Color3.fromRGB(46, 54, 74))

	local list = Instance.new("Frame")
	list.Name = "List"
	list.Position = UDim2.new(0, 6, 0, 26)
	list.Size = UDim2.new(1, -12, 0, 0)
	list.BackgroundTransparency = 1
	list.Parent = row

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	-- Built once per secret and shown or hidden on refresh, never created inside the refresh: this
	-- runs on every DataUpdate (~3 s and on every kill) and a section that destroys and rebuilds its
	-- children on that clock is the pattern `PetsGrid` already pays for elsewhere.
	local cells = {}
	for i, secret in ipairs(GameConfig.Secrets or {}) do
		local zone = GameConfig.GetZoneByKey(secret.zoneKey)

		local cell = Instance.new("Frame")
		cell.Name = "Secret_" .. tostring(secret.id)
		cell.LayoutOrder = i
		cell.Size = UDim2.new(1, 0, 0, 44)
		cell.BackgroundColor3 = Color3.fromRGB(242, 238, 252)
		cell.BorderSizePixel = 0
		cell.Visible = false
		cell.Parent = list
		-- A UDim, never a bare number: `UIKit.corner` hands its argument straight to
		-- `UITheme.SnapRadius`, which indexes `.Scale` -- a number throws there.
		corner(cell, UDim.new(0, 10))

		local title = Instance.new("TextLabel")
		title.Name = "CardTitle"
		title.Size = UDim2.new(1, -16, 0, 20)
		title.Position = UDim2.new(0, 8, 0, 3)
		title.BackgroundTransparency = 1
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Text = ("%s %s"):format(zone and zone.emoji or "\u{2728}",
			zone and zone.name or tostring(secret.zoneKey))
		title.Parent = cell
		themeLabel(title, 16, Color3.fromRGB(46, 54, 74))

		local sub = Instance.new("TextLabel")
		sub.Name = "CardSubtitle"
		sub.Size = UDim2.new(1, -16, 0, 18)
		sub.Position = UDim2.new(0, 8, 0, 22)
		sub.BackgroundTransparency = 1
		sub.TextXAlignment = Enum.TextXAlignment.Left
		sub.Text = payoutLine(secret)
		sub.Parent = cell
		themeLabel(sub, 14, Color3.fromRGB(96, 104, 126))

		cells[secret.id] = cell
	end

	--- Show exactly the found ones, and hide the whole section while there are none.
	local function refresh()
		local data = hud.getData and hud.getData()
		local found = (data and type(data.FoundSecrets) == "table") and data.FoundSecrets or nil
		local shown = 0
		for id, cell in pairs(cells) do
			local isFound = found ~= nil and found[id] == true
			cell.Visible = isFound
			if isFound then shown = shown + 1 end
		end
		-- The row carries its own height because the scroll measures rows, not their contents.
		list.Size = UDim2.new(1, -12, 0, shown * 44 + math.max(0, shown - 1) * 6)
		row.Size = UDim2.new(1, 0, 0, 26 + list.Size.Y.Offset + 4)
		row.Visible = shown > 0
	end

	hud.refreshJournalSecrets = refresh
	refresh()
end
