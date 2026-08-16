--[[
	PhotoSpot -- the plaza's photo pad, which until 17.3 was a sign and no code.

	THE REPORT: *"photo spot nista ne radi"*. It was exactly right. `HubPlaza.buildPhotoSpot` laid a
	rim, a pad, an eye, two posts, a beam, a translucent sheet, a gold crest and a BillboardGui
	reading 📸 PHOTO SPOT -- and a sweep of every script in the place found no ProximityPrompt, no
	`Touched`, no `ClickDetector` and no listener of any kind for `PhotoPad`, `PhotoRim`, `PhotoSign`
	or `FrameSheet`. Furniture wearing a feature's label.

	WHY THE WHOLE SEQUENCE IS LOCAL. Posing a camera, hiding the HUD and drawing a border are all
	client-side by nature, and the one thing that is not -- the first-photo reward -- is a single
	`PhotoTaken` fire at the end, with the server owning the flag and the grant (see `HubPlaza`).
	Nothing here is worth cheating: firing the remote by hand pays the same 25 diamonds once, which
	is what standing on the pad pays anyway.

	THE FRAMING IS THE FEATURE, and it is arithmetic rather than taste:

	  * The camera stands on the PLAZA side of the player, so the arch is behind them and the deck,
	    the boards and the gate are behind the camera -- which is what `buildPhotoSpot`'s own comment
	    says the composition is for ("get this backwards and the photo spot points a camera at the
	    lawn"). The side is read off the frame posts at run time rather than assumed, because the
	    pad is placed by a search and can end up on either side of the boulevard.
	  * The distance is fitted to the DRAWN body, exactly like `CameraFit`: this game's characters
	    run from under 8 studs tall to nearly 40, so a fixed distance is a portrait of a Cell and a
	    close-up of an Absolute's knee.
	  * The player is turned to face the camera. A photo of the back of somebody's head is the one
	    outcome this whole feature cannot afford, and rotating the root in place is safe under
	    StreamingEnabled in a way that moving it is not.

	WHAT IT DOES NOT DO: take an actual image. Roblox gives no script a screenshot, so what this
	builds is the MOMENT -- the pose, the countdown, the flash, the border and the caption -- and the
	player's own screenshot key takes the picture. That is how every photo spot in the genre works.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UITheme = require(RS.Modules.UITheme)
local SoundLibrary = require(RS.Modules.SoundLibrary)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- How long the finished shot is held before the HUD comes back. Long enough to press a screenshot
-- key without hurrying, short enough that it never feels like the game has taken the controls away.
local HOLD = 3.0
local COUNT_FROM = 3

-- 1.55x the body's height, wider than CameraFit's 1.15 -- a portrait wants air around it where a
-- play camera wants reach. Measured on the first real photo at 1.35: a 40.3-stud body filled about
-- three fifths of the frame and sat low in it, which is a body in a rectangle rather than a
-- portrait. The lift below is the other half of that -- see AIM.
local FRAME_FIT = 1.55

-- WHERE THE CAMERA LOOKS, AND WHY IT IS THE MIDDLE. The first cut aimed at 55% of the body's height
-- with the camera lifted 30% of it, i.e. looking DOWN at the subject -- and a camera that looks down
-- pushes what it is looking at toward the bottom of the frame, which is exactly what the capture
-- showed. Aiming at the middle with a gentler lift puts the whole character in the rectangle and
-- keeps enough height to see the pad it is standing on.
local AIM = 0.50
local LIFT = 0.20

local busy = false
-- The ScreenGuis this file switched off, so the restore puts back exactly what it took and never
-- enables one that was already down for a reason of its own. File-level because the emergency
-- restore on respawn is outside the function that fills it.
local hidden = {}

-- ============================================================================
-- MEASURING THE SUBJECT
-- ============================================================================
-- Drawn parts only, for the reason CameraFit gives: the R15 limbs under a generated skin are all at
-- Transparency 1 and the HumanoidRootPart is 13 studs of nothing, so counting them frames a body
-- nobody can see.
local function drawnExtents(character)
	local lo, hi = math.huge, -math.huge
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			lo = math.min(lo, d.Position.Y - d.Size.Y / 2)
			hi = math.max(hi, d.Position.Y + d.Size.Y / 2)
		end
	end
	if lo == math.huge then return nil, nil end
	return lo, hi
end

-- ============================================================================
-- THE OVERLAY
-- ============================================================================
-- Built fresh per photo and destroyed after. It is on screen for five seconds every few hours; a
-- cached one would be five seconds of use for the cost of sitting in the PlayerGui forever, and a
-- rebuild cannot go stale after a theme change.
local function buildOverlay()
	local gui = Instance.new("ScreenGui")
	gui.Name = "PhotoOverlay"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 500
	gui.Parent = player:WaitForChild("PlayerGui")

	-- The border. Four bars rather than a frame with a hole in it, because a Frame cannot have a
	-- transparent middle and a stroked one draws its line INSIDE the rectangle it is given.
	local bars = {}
	local BAR = 0.045
	local edges = {
		{ UDim2.fromScale(1, BAR), UDim2.fromScale(0, 0) },
		{ UDim2.fromScale(1, BAR), UDim2.fromScale(0, 1 - BAR) },
		{ UDim2.fromScale(BAR * 0.56, 1), UDim2.fromScale(0, 0) },
		{ UDim2.fromScale(BAR * 0.56, 1), UDim2.fromScale(1 - BAR * 0.56, 0) },
	}
	for _, e in ipairs(edges) do
		local bar = Instance.new("Frame")
		bar.Size = e[1]
		bar.Position = e[2]
		bar.BackgroundColor3 = UITheme.Color.PanelWhite
		bar.BorderSizePixel = 0
		bar.ZIndex = 2
		bar.Parent = gui
		table.insert(bars, bar)
	end

	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.Size = UDim2.fromScale(0.6, 0.038)
	caption.Position = UDim2.fromScale(0.2, 0.958)
	caption.BackgroundTransparency = 1
	caption.Font = UITheme.Font.Display
	caption.TextScaled = true
	caption.TextColor3 = Color3.fromRGB(70, 78, 98)
	caption.Text = ""
	caption.ZIndex = 3
	caption.Parent = gui

	local centre = Instance.new("TextLabel")
	centre.Name = "Centre"
	centre.Size = UDim2.fromScale(0.5, 0.22)
	centre.Position = UDim2.fromScale(0.25, 0.30)
	centre.BackgroundTransparency = 1
	centre.Font = UITheme.Font.Display
	centre.TextScaled = true
	centre.TextColor3 = UITheme.Color.PanelWhite
	centre.Text = ""
	centre.ZIndex = 3
	centre.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 6
	stroke.Color = Color3.fromRGB(38, 42, 58)
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = centre

	-- The flash. Full screen, above everything, transparent until the shutter.
	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 10
	flash.Parent = gui

	return gui, caption, centre, flash
end

-- ============================================================================
-- THE SEQUENCE
-- ============================================================================
local function takePhoto(pad)
	if busy then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local lo, hi = drawnExtents(character)
	if not lo then return end
	busy = true

	-- WHICH SIDE THE ARCH IS ON, read off the world rather than assumed. `buildPhotoSpot` puts the
	-- posts at pad.X + side * 15 and the sign of `side` depends on which of four candidate spots the
	-- placement search accepted, so it is only knowable here.
	local model = pad.Parent
	local post = model and model:FindFirstChild("FramePost")
	local side = 1
	if post then
		side = (post.Position.X >= pad.Position.X) and 1 or -1
	end

	local height = hi - lo
	local dist = math.max(14, height * FRAME_FIT)
	local subject = Vector3.new(root.Position.X, lo + height * AIM, root.Position.Z)
	-- Opposite the arch, lifted a fifth of the body: a camera level with the feet of a 40-stud
	-- character photographs its shins, and one much higher photographs the floor.
	local camPos = subject + Vector3.new(-side * dist * 0.90, height * LIFT, dist * 0.26)

	-- Face the camera. Rotation only -- the position is untouched, which is what makes this safe
	-- under StreamingEnabled where a teleport is not.
	root.CFrame = CFrame.lookAt(root.Position, Vector3.new(camPos.X, root.Position.Y, camPos.Z))

	-- Every ScreenGui that is currently up, remembered so the restore cannot guess. The overlay is
	-- built after this list is taken, so it can never hide itself.
	table.clear(hidden)
	for _, g in ipairs(player.PlayerGui:GetChildren()) do
		if g:IsA("ScreenGui") and g.Enabled then
			table.insert(hidden, g)
			g.Enabled = false
		end
	end

	local gui, caption, centre, flash = buildOverlay()
	caption.Text = ("\u{1F4F8}  EVOLUTION LAB  \u{2022}  %s"):format(player.DisplayName)

	local oldType, oldCF = camera.CameraType, camera.CFrame
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(camPos, subject)

	for n = COUNT_FROM, 1, -1 do
		centre.Text = tostring(n)
		SoundLibrary.PlayLocal("click", { volume = 0.5, speed = 0.9 })
		task.wait(0.75)
	end
	centre.Text = ""

	-- The shutter: a hard white frame that falls away over a fifth of a second. Snapping to opaque
	-- and tweening out is what reads as a flash; tweening both ways reads as a fade.
	SoundLibrary.PlayLocal("click", { volume = 0.85, speed = 1.35 })
	flash.BackgroundTransparency = 0
	TweenService:Create(flash, TweenInfo.new(0.22), { BackgroundTransparency = 1 }):Play()

	RS.Remotes:WaitForChild("PhotoTaken"):FireServer()

	task.wait(HOLD)

	camera.CameraType = oldType
	camera.CFrame = oldCF
	gui:Destroy()
	for _, g in ipairs(hidden) do
		if g.Parent then
			g.Enabled = true
		end
	end
	busy = false
end

ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	-- PromptTriggered fires on every client for every player -- the same trap MainUI's own handler
	-- documents -- so somebody else pressing E on the pad must not pose this camera.
	if who ~= player then return end
	if prompt.Name ~= "PhotoPrompt" then return end
	task.spawn(takePhoto, prompt.Parent)
end)

-- A character that dies or is rebuilt mid-photo would otherwise leave the camera scriptable and
-- every ScreenGui off, which is a soft-locked client with no way back -- and an evolve rebuilds the
-- character, so this is not a hypothetical. Cheap insurance: the flag is released, the ordinary
-- camera restored, and exactly the GUIs this file hid are put back.
player.CharacterAdded:Connect(function()
	if not busy then return end
	busy = false
	camera.CameraType = Enum.CameraType.Custom
	local gui = player:FindFirstChild("PlayerGui")
	local overlay = gui and gui:FindFirstChild("PhotoOverlay")
	if overlay then
		overlay:Destroy()
	end
	for _, g in ipairs(hidden) do
		if g.Parent then
			g.Enabled = true
		end
	end
	table.clear(hidden)
end)
