-- RebirthBeacon -- the arrow that appears on the Rebirth tile only when a rebirth is actually affordable.
--
-- MOVED OUT OF `MainUI` (18.9), byte for byte. It was already a closed
-- `;(function() ... end)()` block -- the shape this file's 200-register ceiling forces
-- every panel into -- so the extraction is a change of wrapper, not of code. See
-- `docs/SPLIT.md` for the `hud` contract and `docs/CODEMAP.md` for where the rest went.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local themeLabel, styleCard = UIKit.themeLabel, UIKit.styleCard

return function(hud)
	local rebirthButton = hud.rebirthButton

	local beaconGui = Instance.new("ScreenGui")
	beaconGui.Name = "RebirthBeacon"
	beaconGui.ResetOnSpawn = false
	beaconGui.IgnoreGuiInset = false
	beaconGui.DisplayOrder = 90
	beaconGui.Enabled = false
	beaconGui.Parent = playerGui

	-- A ring that pulses AROUND the tile rather than a badge on top of it: the tile already carries
	-- an icon and a caption, and covering either to say "press me" hides what is being pressed.
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.BackgroundTransparency = 1
	ring.Parent = beaconGui
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(0, 22)
	ringCorner.Parent = ring
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Thickness = 4
	ringStroke.Color = UITheme.Color.Gold
	ringStroke.Transparency = 0.15
	ringStroke.Parent = ring

	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.Size = UDim2.new(0, 62, 0, 62)
	arrow.AnchorPoint = Vector2.new(0, 0.5)
	arrow.BackgroundTransparency = 1
	arrow.Text = "\u{27A1}\u{FE0F}"
	arrow.TextScaled = true
	arrow.Parent = beaconGui

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(0, 186, 0, 34)
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Text = "REBIRTH READY"
	label.Parent = beaconGui
	styleCard(label, UITheme.Color.Gold, UDim.new(0, 12), 3)
	themeLabel(label, 19)

	local conn
	local function stop()
		if conn then conn:Disconnect() conn = nil end
		beaconGui.Enabled = false
	end

	hud.setRebirthReady = function(ready)
		if not ready then stop() return end
		if conn then return end -- already running; never stack a second Heartbeat
		beaconGui.Enabled = true
		local t0 = os.clock()
		conn = RunService.Heartbeat:Connect(function()
			-- the tile can be gone for a frame during a respawn or a layout pass
			if not rebirthButton.Parent then return end
			local pos, size = rebirthButton.AbsolutePosition, rebirthButton.AbsoluteSize
			if size.X < 1 then return end
			local t = os.clock() - t0
			local pulse = 0.5 + 0.5 * math.sin(t * 3.2)

			-- the ring breathes OUTWARD from the tile, so it never covers the icon
			local grow = 10 + pulse * 8
			ring.Position = UDim2.fromOffset(pos.X + size.X * 0.5, pos.Y + size.Y * 0.5)
			ring.Size = UDim2.fromOffset(size.X + grow * 2, size.Y + grow * 2)
			ringStroke.Transparency = 0.1 + pulse * 0.45

			-- and the arrow nudges toward the tile from its right, the one side the tile column
			-- never occupies (the left column is pinned at x = 20)
			local nudge = math.abs(math.sin(t * 3.2)) * 10
			local ax = pos.X + size.X + 16 + nudge
			arrow.Position = UDim2.fromOffset(ax, pos.Y + size.Y * 0.5)
			label.Position = UDim2.fromOffset(ax + 66, pos.Y + size.Y * 0.5)
		end)
	end

	-- the panel is what decides; this is only ever told. Start hidden so a save that arrives locked
	-- never flashes it.
	stop()
end
