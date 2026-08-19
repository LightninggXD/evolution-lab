--[[
	FirstJoin -- Modern guided first-time player experience (Phase 6.3 + Phase 18.23).

	Features:
	  - Cinematic smooth camera pan showing the starting Forest and player character
	  - Marching 3D neon chevron trail leading directly to the nearest creature
	  - Overhead animated floating target beacon and bounding highlight
	  - Pulsing UI glow halo and directional bouncing arrow pointing directly at the EVOLVE button
	  - Responsive floating guide banner with animated step progression (● ○ ○) and audio cues
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS:WaitForChild("Modules"):WaitForChild("GameConfig"))
local UITheme = require(RS.Modules:WaitForChild("UITheme"))
local CardKit = require(RS.Modules:WaitForChild("HUD"):WaitForChild("CardKit"))
local IconLibrary = require(RS.Modules:WaitForChild("IconLibrary"))
local SoundLibrary = require(RS.Modules:WaitForChild("SoundLibrary"))

local player = Players.LocalPlayer
local Remotes = RS:WaitForChild("Remotes")

local STEP = RunService.Heartbeat

local PAN_TIME = 3.4
local ARROW_BOB = 12
local DONE_BANNER_TIME = 4.2
local CLIMB_BEAT_TIME = 7.0

local state = {
	data = nil,
	panned = false,
	running = false,
}

-- ============================================================================
-- THE STEP TABLE
-- ============================================================================
local STEPS = {
	fight = {
		key = "fight",
		icon = "\u{2694}\u{FE0F}",
		headline = "Attack a creature",
		subline = "Click one to fight it and earn XP",
		tone = { UITheme.Color.Lavender, UITheme.Color.Purple },
	},
	evolve = {
		key = "evolve",
		icon = "\u{2B50}",
		headline = "You are ready to EVOLVE!",
		subline = "Press the shiny EVOLVE button",
		tone = { UITheme.Color.Sunny, UITheme.Color.Orange },
	},
	done = {
		key = "done",
		icon = "\u{1F389}",
		headline = "Evolved!",
		subline = "Keep fighting -- new zones open as you grow",
		tone = { UITheme.Color.Mint, UITheme.Color.Green },
	},
	climb = {
		key = "climb",
		icon = "\u{26F0}\u{FE0F}",
		headline = "Climb to the next terrace",
		subline = "Tougher creatures, higher XP drops",
		tone = { UITheme.Color.Aqua, UITheme.Color.Blue },
	},
}

local DOT_ORDER = { "fight", "evolve", "climb" }

-- ============================================================================
-- THE CAMERA PAN
-- ============================================================================
local function panCamera()
	local character = player.Character or player.CharacterAdded:Wait()
	local root = character:WaitForChild("HumanoidRootPart", 10)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local cam = workspace.CurrentCamera
	if not root or not cam then return end

	local skipped = false
	local conn = UserInputService.InputBegan:Connect(function()
		skipped = true
	end)

	local here = root.Position
	local facing = root.CFrame.LookVector
	local startAt = here + Vector3.new(0, 62, 0) - facing * 78
	local endAt = here + Vector3.new(0, 7, 0) - facing * 18

	local ok, err = pcall(function()
		cam.CameraType = Enum.CameraType.Scriptable
		local t0 = os.clock()
		while os.clock() - t0 < PAN_TIME and not skipped do
			local a = (os.clock() - t0) / PAN_TIME
			local eased = a < 0.5 and 2 * a * a or 1 - (-2 * a + 2) ^ 2 / 2
			local at = startAt:Lerp(endAt, eased)
			local targetPos = (player.Character and player.Character:FindFirstChild("HumanoidRootPart") or root).Position + Vector3.new(0, 2, 0)
			cam.CFrame = CFrame.lookAt(at, targetPos)
			STEP:Wait()
		end
	end)

	conn:Disconnect()

	cam.CameraType = Enum.CameraType.Custom
	if humanoid then
		cam.CameraSubject = humanoid
	end
	if not ok then
		warn("[FirstJoin] camera pan failed: " .. tostring(err))
	end
end

-- ============================================================================
-- THE GUIDE GUI
-- ============================================================================
local gui = Instance.new("ScreenGui")
gui.Name = "FirstJoinGuide"
gui.ResetOnSpawn = false
gui.DisplayOrder = 110
gui.Parent = player:WaitForChild("PlayerGui")

local trailSuspended = false
task.spawn(function()
	local mainGui = player.PlayerGui:WaitForChild("EvolutionLabUI", 30)
	if not mainGui then return end
	while true do
		local panelOpen = false
		for _, child in ipairs(mainGui:GetChildren()) do
			if child:GetAttribute("HudPanel") and child.Visible then
				panelOpen = true
				break
			end
		end
		gui.Enabled = not panelOpen
		trailSuspended = panelOpen
		task.wait(0.15)
	end
end)

-- ============================================================================
-- THE FLOATING BANNER CARD
-- ============================================================================
local banner = Instance.new("Frame")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, 128)
banner.Size = UDim2.new(0, 560, 0, 104)
banner.BackgroundTransparency = 1
banner.Visible = false
banner.ZIndex = 2
banner.Parent = gui

local card, setCardTone = CardKit.Card(banner, {
	name = "Card",
	size = UDim2.new(1, 0, 1, 0),
	colors = STEPS.fight.tone,
	radius = 22,
	studTile = 26,
	studTransparency = 0.86,
	zIndex = 2,
})

pcall(UITheme.DropShadow, card, UDim.new(0, 22))

local iconChip = Instance.new("Frame")
iconChip.Name = "IconChip"
iconChip.AnchorPoint = Vector2.new(0, 0.5)
iconChip.Position = UDim2.new(0, 14, 0.5, 0)
iconChip.Size = UDim2.new(0, 72, 0, 72)
iconChip.BackgroundColor3 = CardKit.WHITE
iconChip.BackgroundTransparency = 0.80
iconChip.BorderSizePixel = 0
iconChip.ZIndex = 4
iconChip.Parent = card
CardKit.Corner(iconChip, 999)
CardKit.Stroke(iconChip, CardKit.INK, 3)

local iconImage = Instance.new("ImageLabel")
iconImage.Name = "IconImage"
iconImage.AnchorPoint = Vector2.new(0.5, 0.5)
iconImage.Position = UDim2.new(0.5, 0, 0.5, 0)
iconImage.Size = UDim2.new(0, 48, 0, 48)
iconImage.BackgroundTransparency = 1
iconImage.ScaleType = Enum.ScaleType.Fit
iconImage.Visible = false
iconImage.ZIndex = 5
iconImage.Parent = iconChip

local iconGlyph = Instance.new("TextLabel")
iconGlyph.Name = "IconGlyph"
iconGlyph.AnchorPoint = Vector2.new(0.5, 0.5)
iconGlyph.Position = UDim2.new(0.5, 0, 0.5, 0)
iconGlyph.Size = UDim2.new(0, 48, 0, 48)
iconGlyph.BackgroundTransparency = 1
iconGlyph.Font = UITheme.Font.Display
iconGlyph.TextScaled = true
iconGlyph.Text = ""
iconGlyph.TextColor3 = CardKit.WHITE
iconGlyph.ZIndex = 5
iconGlyph.Parent = iconChip
CardKit.Stroke(iconGlyph, CardKit.INK, 3)

local headline = CardKit.Text(card, {
	name = "Headline",
	text = STEPS.fight.headline,
	size = UDim2.new(1, -170, 0, 36),
	position = UDim2.new(0, 96, 0, 16),
	textSize = 24,
	xAlign = "Left",
	zIndex = 4,
	strokeThickness = 3,
})

local subline = CardKit.Text(card, {
	name = "Subline",
	text = STEPS.fight.subline,
	size = UDim2.new(1, -170, 0, 26),
	position = UDim2.new(0, 96, 0, 54),
	textSize = 17,
	color = UITheme.Color.Cream,
	xAlign = "Left",
	zIndex = 4,
	strokeThickness = 2,
})

local dotStrip = Instance.new("Frame")
dotStrip.Name = "Dots"
dotStrip.AnchorPoint = Vector2.new(1, 0.5)
dotStrip.Position = UDim2.new(1, -18, 0.5, 0)
dotStrip.Size = UDim2.new(0, 20, 0, 60)
dotStrip.BackgroundTransparency = 1
dotStrip.ZIndex = 4
dotStrip.Parent = card

local dotLayout = Instance.new("UIListLayout")
dotLayout.FillDirection = Enum.FillDirection.Vertical
dotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
dotLayout.VerticalAlignment = Enum.VerticalAlignment.Center
dotLayout.Padding = UDim.new(0, 6)
dotLayout.Parent = dotStrip

local dots = {}
for i = 1, #DOT_ORDER do
	local dot = Instance.new("Frame")
	dot.Name = "Dot" .. i
	dot.Size = UDim2.new(0, 12, 0, 12)
	dot.BackgroundColor3 = CardKit.WHITE
	dot.BackgroundTransparency = 0.5
	dot.BorderSizePixel = 0
	dot.ZIndex = 5
	dot.Parent = dotStrip
	CardKit.Corner(dot, 999)
	CardKit.Stroke(dot, CardKit.INK, 2)
	dots[i] = dot
end

local function paint(key)
	local def = STEPS[key] or STEPS.fight
	setCardTone(def.tone)
	headline.Text = def.headline
	subline.Text = def.subline

	local asset = IconLibrary.Resolve(def.icon)
	if asset then
		iconImage.Image = asset
		iconImage.Visible = true
		iconGlyph.Visible = false
	else
		iconGlyph.Text = def.icon or ""
		iconGlyph.Visible = true
		iconImage.Visible = false
	end

	local reached = 0
	if key == "done" then
		reached = #DOT_ORDER
	else
		for i, name in ipairs(DOT_ORDER) do
			if name == key then
				reached = i
				break
			end
		end
	end
	for i, d in ipairs(dots) do
		d.BackgroundTransparency = (i <= reached) and 0 or 0.6
		d.BackgroundColor3 = (i == reached) and UITheme.Color.Sunny or CardKit.WHITE
	end
end

local paintedKey = nil
local function paintIfChanged(key)
	if key == paintedKey then return end
	paintedKey = key
	paint(key)
	if key == "evolve" or key == "done" then
		SoundLibrary.PlayLocal("levelUp", { volume = 0.45 })
	end
end

-- ============================================================================
-- 2D ARROW & PULSING UI HALO FOR EVOLVE BUTTON
-- ============================================================================
local arrow = Instance.new("TextLabel")
arrow.Name = "Arrow"
arrow.AnchorPoint = Vector2.new(1, 0.5)
arrow.Size = UDim2.new(0, 76, 0, 76)
arrow.BackgroundTransparency = 1
arrow.Font = UITheme.Font.Display
arrow.TextScaled = true
arrow.Text = "\u{27A1}\u{FE0F}"
arrow.TextColor3 = UITheme.Color.White
arrow.TextStrokeColor3 = CardKit.INK
arrow.TextStrokeTransparency = 0
arrow.Visible = false
arrow.ZIndex = 4
arrow.Parent = gui
CardKit.Stroke(arrow, CardKit.INK, 4)

-- Pulsing Target Halo over the evolve button
local buttonHalo = Instance.new("Frame")
buttonHalo.Name = "ButtonHalo"
buttonHalo.BackgroundTransparency = 1
buttonHalo.BorderSizePixel = 0
buttonHalo.Visible = false
buttonHalo.ZIndex = 3
buttonHalo.Parent = gui

local haloStroke = Instance.new("UIStroke")
haloStroke.Thickness = 4.5
haloStroke.Color = UITheme.Color.Sunny
haloStroke.Transparency = 0.2
haloStroke.Parent = buttonHalo
CardKit.Corner(buttonHalo, 14)

gui.IgnoreGuiInset = false

local function findEvolveButton()
	local host = player.PlayerGui:FindFirstChild("EvolutionLabUI")
	return host and host:FindFirstChild("EvolveButton", true)
end

-- ============================================================================
-- 3D WORLD BEACON MARKER & HIGHLIGHT
-- ============================================================================
local marker = Instance.new("BillboardGui")
marker.Name = "GuideMarker"
marker.Size = UDim2.new(0, 100, 0, 100)
marker.AlwaysOnTop = true
marker.LightInfluence = 0
marker.Enabled = false
marker.Parent = gui

local markerLabel = Instance.new("TextLabel")
markerLabel.Size = UDim2.new(1, 0, 1, 0)
markerLabel.BackgroundTransparency = 1
markerLabel.Font = UITheme.Font.Display
markerLabel.TextScaled = true
markerLabel.Text = "\u{2B07}\u{FE0F}"
markerLabel.TextColor3 = UITheme.Color.White
markerLabel.TextStrokeColor3 = CardKit.INK
markerLabel.TextStrokeTransparency = 0
markerLabel.Parent = marker
CardKit.Stroke(markerLabel, CardKit.INK, 4)

local pointHL = Instance.new("Highlight")
pointHL.Name = "GuideHighlight"
pointHL.FillTransparency = 0.70
pointHL.FillColor = UITheme.Color.Sunny
pointHL.OutlineColor = UITheme.Color.White
pointHL.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
pointHL.Enabled = false
pointHL.Parent = gui

-- ============================================================================
-- 3D CHEVRON TRAIL
-- ============================================================================
local CHEVRON_COUNT = 8
local CHEVRON_GAP = 7
local CHEVRON_START = 9
local CHEVRON_ARRIVED = 14
local CHEVRON_SPEED = 9

local trailFolder = Instance.new("Folder")
trailFolder.Name = "FirstJoinTrail"
trailFolder.Parent = workspace

local chevrons = {}
do
	for i = 1, CHEVRON_COUNT do
		local p = Instance.new("Part")
		p.Name = "Chevron" .. i
		p.Size = Vector3.new(3.2, 3.2, 3.2)
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Locked = true
		p.Material = Enum.Material.Neon
		p.Color = UITheme.Color.Sunny
		p.Transparency = 1
		p.Parent = trailFolder

		local mesh = Instance.new("SpecialMesh")
		local okMesh = pcall(function() mesh.MeshType = Enum.MeshType.Pyramid end)
		if not okMesh then
			mesh.MeshType = Enum.MeshType.Brick
		end
		mesh.Scale = Vector3.new(1, 1, 1)
		mesh.Parent = p

		chevrons[i] = p
	end
end

local function hideTrail()
	for _, p in ipairs(chevrons) do
		p.Transparency = 1
	end
end

local function updateTrail(toPos, tone)
	if trailSuspended or not toPos then
		hideTrail()
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		hideTrail()
		return
	end

	local from = root.Position
	local flat = Vector3.new(toPos.X - from.X, 0, toPos.Z - from.Z)
	local dist = flat.Magnitude
	if dist < CHEVRON_ARRIVED then
		hideTrail()
		return
	end
	local dir = flat.Unit

	local phase = (os.clock() * CHEVRON_SPEED) % CHEVRON_GAP
	for i, p in ipairs(chevrons) do
		local along = CHEVRON_START + (i - 1) * CHEVRON_GAP + phase
		if along >= dist - 2 then
			p.Transparency = 1
		else
			local at = from + dir * along + Vector3.new(0, 3.4, 0)
			p.CFrame = CFrame.lookAt(at, at + dir) * CFrame.Angles(-math.pi / 2, 0, 0)
			local fade = (i - 1) / CHEVRON_COUNT
			p.Transparency = 0.12 + fade * 0.55
			if tone then
				p.Color = tone
			end
		end
	end
end

local function pointAt(target, height)
	if not target then
		marker.Enabled = false
		pointHL.Enabled = false
		pointHL.Adornee = nil
		marker.Adornee = nil
		return nil
	end
	local adornee = target
	if target:IsA("Model") then
		adornee = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
	end
	if not adornee then return nil end
	local _, size = pcall(function() return target:IsA("Model") and select(2, target:GetBoundingBox()) or target.Size end)
	local top = (typeof(size) == "Vector3" and size.Y or 6) * 0.5
	marker.Adornee = adornee
	marker.StudsOffsetWorldSpace = Vector3.new(0, top + (height or 5) + math.sin(os.clock() * 4) * 0.8, 0)
	marker.Enabled = true
	pointHL.Adornee = target
	pointHL.Enabled = true
	return adornee.Position
end

local function nearestCreature()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local folder = workspace:FindFirstChild("Creatures")
	if not root or not folder then return nil end
	local best, bestD = nil, 260
	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("Model") and (m:GetAttribute("Health") or 0) > 0 then
			local part = m.PrimaryPart
			if part then
				local d = (part.Position - root.Position).Magnitude
				if d < bestD then best, bestD = m, d end
			end
		end
	end
	return best
end

local function nearestRamp()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local shell = workspace:FindFirstChild("WorldShell")
	if not root or not shell then return nil end
	local best, bestD = nil, 900
	for _, d in ipairs(shell:GetChildren()) do
		if d.Name == "TerraceRamp" then
			local dist = (d.Position - root.Position).Magnitude
			if dist < bestD then best, bestD = d, dist end
		end
	end
	return best
end

-- ============================================================================
-- RUNTIME GUIDE LOOP
-- ============================================================================
local function stepFor(data)
	if not data then return nil end
	local step = GameConfig.GetEvolveStep(data)
	if step.isMax then return nil end
	if (data.XP or 0) >= step.xpCost then
		return "evolve"
	end
	return "fight"
end

local runClimbBeat

local function runGuide()
	if state.running then return end
	state.running = true
	paintedKey = nil
	paintIfChanged("fight")

	task.spawn(function()
		local ok, err = pcall(function()
			local t0 = os.clock()
			while state.data and not state.data.TutorialDone do
				local which = stepFor(state.data)
				if which then
					banner.Visible = true
					paintIfChanged(which)
				else
					banner.Visible = false
				end

				local btn = which == "evolve" and findEvolveButton() or nil
				if btn then
					local pos, size = btn.AbsolutePosition, btn.AbsoluteSize
					local bob = math.abs(math.sin((os.clock() - t0) * 3.6)) * ARROW_BOB
					arrow.Position = UDim2.new(0, pos.X - 10 - bob, 0, pos.Y + size.Y * 0.5)
					arrow.Visible = true

					-- Pulsing halo around the EVOLVE button
					buttonHalo.Position = UDim2.new(0, pos.X - 4, 0, pos.Y - 4)
					buttonHalo.Size = UDim2.new(0, size.X + 8, 0, size.Y + 8)
					haloStroke.Transparency = 0.15 + 0.45 * math.abs(math.sin((os.clock() - t0) * 4))
					buttonHalo.Visible = true
				else
					arrow.Visible = false
					buttonHalo.Visible = false
				end

				if which == "fight" then
					local at = pointAt(nearestCreature(), 6)
					updateTrail(at, UITheme.Color.Sunny)
				else
					pointAt(nil)
					updateTrail(nil)
				end
				STEP:Wait()
			end
		end)

		banner.Visible = false
		arrow.Visible = false
		buttonHalo.Visible = false
		pointAt(nil)
		updateTrail(nil)
		state.running = false
		if not ok then
			warn("[FirstJoin] guide failed: " .. tostring(err))
		end

		if state.data and state.data.TutorialDone then
			paintIfChanged("done")
			banner.Visible = true
			task.delay(DONE_BANNER_TIME, function()
				banner.Visible = false
				runClimbBeat()
			end)
		end
	end)
end

runClimbBeat = function()
	paintIfChanged("climb")
	banner.Visible = true
	local t0 = os.clock()
	task.spawn(function()
		while os.clock() - t0 < CLIMB_BEAT_TIME do
			local at = pointAt(nearestRamp(), 10)
			updateTrail(at, UITheme.Color.Aqua)
			STEP:Wait()
		end
		banner.Visible = false
		pointAt(nil)
		updateTrail(nil)
	end)
end

-- ============================================================================
-- BOOTSTRAP
-- ============================================================================
local function onData(data)
	if type(data) ~= "table" then return end
	state.data = data
	if data.TutorialDone then return end

	if not state.panned then
		state.panned = true
		task.spawn(panCamera)
	end
	runGuide()
end

Remotes:WaitForChild("DataUpdate").OnClientEvent:Connect(onData)

local getRemote = Remotes:FindFirstChild("GetData") or Remotes:WaitForChild("GetData", 10)
if getRemote then
	task.spawn(function()
		local d = getRemote:InvokeServer()
		if d then onData(d) end
	end)
end
