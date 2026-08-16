-- AudioPanel -- the audio settings panel and its HUD tile: music and SFX volume (Phase 4.6).
--
-- MOVED OUT OF `MainUI` (18.9), byte for byte. It was already a closed
-- `;(function() ... end)()` block -- the shape this file's 200-register ceiling forces
-- every panel into -- so the extraction is a change of wrapper, not of code. See
-- `docs/SPLIT.md` for the `hud` contract and `docs/CODEMAP.md` for where the rest went.

local RS = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local SoundLibrary = require(RS.Modules:WaitForChild("SoundLibrary"))
local UITheme = require(RS.Modules.UITheme)
local UIKit = require(RS.Modules:WaitForChild("UIKit"))

local Remotes = RS.Remotes

local styleCard, PANEL_SHELL = UIKit.styleCard, UIKit.PANEL_SHELL

return function(hud)
	local PANEL_ANCHOR, columnTile, panelClose = hud.PANEL_ANCHOR, hud.columnTile, hud.panelClose
	local registerPanel, screenGui, toggleOnly = hud.registerPanel, hud.screenGui, hud.toggleOnly

	local UIS = game:GetService("UserInputService")

	-- Order 8, the bottom-right corner, which was the one genuinely empty slot in the cluster. NOT 5:
	-- that is the Season Pass tile, built inside its own block further up, and the two overlapped
	-- exactly until a live read of the column caught it.
	local audioButton = columnTile("R", 8, "\u{1F50A}", "Audio", UITheme.Color.Aqua)

	local panel = Instance.new("Frame")
	panel.Name = "AudioPanel"
	panel.Size = UDim2.new(0, 430, 0, 408)
	panel.Position = PANEL_ANCHOR
	panel.ZIndex = 20
	panel.Visible = false
	panel.Parent = screenGui
	styleCard(panel, PANEL_SHELL, UDim.new(0, 22), 5)
	registerPanel(panel)
	panelClose(panel)

	-- Converted to the shared accent band (17.x). Rows moved 64 -> 100 and the panel grew by the same
	-- 36, so the bottom-anchored mute button keeps its gap. Aqua matches the Audio tile that opens it.
	UITheme.PanelHeader(panel, {
		title = "\u{1F50A} Audio",
		subtitle = "Master fades the other three",
		accent = UITheme.Color.Aqua,
	})

	-- `Master` is a fader over the other three rather than a fourth channel, which is why it leads and
	-- why the mute button below drives it and nothing else: muting is one decision, not four.
	local ROWS = {
		{ key = "Master",   label = "Master",    color = UITheme.Color.Gold },
		{ key = "SFX",      label = "Effects",   color = UITheme.Color.Coral },
		{ key = "UI",       label = "Interface", color = UITheme.Color.Aqua },
		{ key = "Ambience", label = "Ambience",  color = UITheme.Color.Mint },
	}

	local values = { Master = 1, SFX = 1, UI = 1, Ambience = 1 }
	local tracks, apply = {}, {}
	local dragging = nil
	local preMute = 1
	local refreshMute -- assigned below; declared here so `apply` can call it

	-- Applied LOCALLY on every frame of a drag, so the fader is audible while it moves, but only SENT
	-- when the drag ends. A remote per mouse-move frame is sixty round trips a second for a preference,
	-- and the server's copy only has to be right by the time the player lets go.
	local function commit()
		-- looked up rather than held: the remote is created by PlayerDataService.Init, and a
		-- WaitForChild at build time would stall the whole HUD if that ever stopped happening
		local remote = Remotes:FindFirstChild("SetAudioVolumes")
		if remote then
			remote:FireServer(values)
		end
	end

	for i, row in ipairs(ROWS) do
		local y = 100 + (i - 1) * 58

		UITheme.Label(panel, {
			name = row.key .. "Name", text = row.label,
			size = UDim2.new(0, 96, 0, 28), position = UDim2.new(0, 20, 0, y),
			xAlign = "Left", maxTextSize = 20, zIndex = 22,
		})

		local track = Instance.new("Frame")
		track.Name = row.key .. "Track"
		-- -216, not -196. The readout is right-anchored at (1, -18) and 60 wide, so it starts at x=352;
		-- at -196 the track ran to 356 and the two boxes overlapped by 4px -- more like 8 once the
		-- track's 4px stroke is counted, since UIStroke draws OUTSIDE the frame. Measured, not guessed.
		track.Size = UDim2.new(1, -216, 0, 26)
		track.Position = UDim2.new(0, 122, 0, y + 1)
		track.ZIndex = 22
		track.Parent = panel
		styleCard(track, UITheme.Color.PanelWhite, UDim.new(1, 0), 4)

		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.new(1, 0, 1, 0)
		fill.BackgroundColor3 = row.color
		fill.BorderSizePixel = 0
		fill.ZIndex = 23
		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(1, 0)
		fillCorner.Parent = fill
		local fillGrad = Instance.new("UIGradient")
		fillGrad.Rotation = 90
		fillGrad.Color = UITheme.GradientFor(row.color)
		fillGrad.Parent = fill
		fill.Parent = track

		local readout = UITheme.Label(panel, {
			name = row.key .. "Value", text = "100%",
			size = UDim2.new(0, 60, 0, 28), position = UDim2.new(1, -18, 0, y),
			anchorPoint = Vector2.new(1, 0), xAlign = "Right", maxTextSize = 20, zIndex = 22,
		})

		tracks[row.key] = track
		apply[row.key] = function(a)
			a = math.clamp(a, 0, 1)
			values[row.key] = a
			fill.Size = UDim2.new(a, 0, 1, 0)
			readout.Text = math.floor(a * 100 + 0.5) .. "%"
			SoundLibrary.SetVolumes(values)
			if refreshMute then refreshMute() end
		end

		-- A transparent TextButton over the track, taller than it, rather than input on the Frame: the
		-- extra 12px of height is what makes a 26px bar catchable with a finger.
		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.AutoButtonColor = false
		hit.Size = UDim2.new(1, 0, 1, 14)
		hit.Position = UDim2.new(0, 0, 0, -7)
		hit.ZIndex = 26
		hit.Parent = track
		hit.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging = row.key
				local t = tracks[row.key]
				apply[row.key]((input.Position.X - t.AbsolutePosition.X) / math.max(t.AbsoluteSize.X, 1))
			end
		end)
	end

	-- Tracked on UserInputService, not on the track: a drag that leaves the bar -- which is exactly
	-- what happens when you pull a fader to 0% or 100% -- would otherwise stop updating at the edge
	-- and strand the value wherever the pointer crossed it.
	UIS.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			local t = tracks[dragging]
			apply[dragging]((input.Position.X - t.AbsolutePosition.X) / math.max(t.AbsoluteSize.X, 1))
		end
	end)
	UIS.InputEnded:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = nil
			if values.Master > 0 then preMute = values.Master end
			commit()
		end
	end)

	local muteButton = UITheme.Button(panel, {
		name = "MuteAll", text = "MUTE ALL", color = UITheme.Color.Red,
		size = UDim2.new(0, 190, 0, 46), position = UDim2.new(0.5, 0, 1, -20),
		anchorPoint = Vector2.new(0.5, 1), radius = 14, zIndex = 22, maxTextSize = 22,
	})

	refreshMute = function()
		local muted = values.Master <= 0
		-- colour AND wording, like the Auto tile: a control that only changes hue is a guess
		UITheme.SetColor(muteButton, muted and UITheme.Color.Green or UITheme.Color.Red)
		UITheme.SetText(muteButton, muted and "UNMUTE" or "MUTE ALL")
	end

	-- Restores what the fader was BEFORE the mute rather than snapping to 100%: a player who set the
	-- game to a quarter volume and then muted it did not ask to be shouted at when they come back.
	muteButton.MouseButton1Click:Connect(function()
		if values.Master > 0 then
			preMute = values.Master
			apply.Master(0)
		else
			apply.Master(preMute > 0 and preMute or 1)
		end
		commit()
	end)

	audioButton.MouseButton1Click:Connect(function()
		toggleOnly(panel)
	end)

	hud.refreshAudioPanel = function(data)
		local saved = (data and data.AudioVolumes) or {}
		for _, row in ipairs(ROWS) do
			local v = tonumber(saved[row.key])
			-- `v == v` rejects NaN, which would otherwise clamp through and paint a "nan%" readout
			apply[row.key]((v ~= nil and v == v) and v or 1)
		end
		if values.Master > 0 then preMute = values.Master end
		refreshMute()
	end
	refreshMute()
end
