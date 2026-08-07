--[[
	ZoneTransition - the loading screen between one place and the next.

	This exists because of StreamingEnabled. The zone strip is 12,000 studs long and the arena is
	off the end of it, so a player moved across it arrives well before their client has the
	destination: what they actually saw was a grey void filling in around them over a second or
	two. The teleport worked, it just never read as *going* anywhere.

	The server drives it (see ZoneService.travel) and this side does the two things only a client
	can: it asks for the destination to be streamed in, and it decides when the world is actually
	there to look at.

		start   -> cover the screen, RequestStreamAroundAsync on the destination, answer when in
		           (the server does NOT move the character until that answer arrives)
		arrived -> hold the cover until there is ground under the player, then wipe

	The minimum on-screen time is deliberate. Streaming a neighbouring zone can finish in under a
	tenth of a second, and a cover that appears and vanishes inside two frames reads as a glitch
	rather than as a transition -- so it always plays for at least MIN_SHOW.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local UITheme = require(ReplicatedStorage.Modules.UITheme)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local TransitionRemote = Remotes:WaitForChild("ZoneTransition")
local ReadyRemote = Remotes:WaitForChild("ZoneTransitionReady")

local FADE_IN = 0.22
local FADE_OUT = 0.38
local MIN_SHOW = 1.15      -- the cover never flashes past faster than this
local STREAM_TIMEOUT = 8   -- give up asking and let the server move us anyway
local GROUND_TIMEOUT = 4   -- ... and give up waiting for a floor rather than trapping the player

local TIPS = {
	"Rarer pets are strictly stronger -- rarity multiplies your tier bonus.",
	"Beat a zone's boss to open the gate behind it.",
	"Five zones have a Mystery Potions kiosk. One bottle, and you find out what it is when you drink it.",
	"Every egg podium lists exactly what it can hatch, and the odds.",
	"The Colosseum gate is behind the Forest spawn. A giant returns every 30 minutes.",
	"Potions stack their duration instead of overlapping.",
	"Your pets grow with you -- they resize every time you evolve.",
}

-- ===== THE SCREEN ============================================================

local gui = Instance.new("ScreenGui")
gui.Name = "ZoneTransition"
gui.ResetOnSpawn = false      -- a transition must survive the respawn it might be covering
gui.IgnoreGuiInset = true
gui.DisplayOrder = 500        -- over MainUI and over the Roblox topbar inset
-- Sibling, explicitly: the theme builds its panels out of a shell, a gloss and a stroke at small
-- ZIndex values, and under Global behaviour those would sort against the backdrop rather than
-- inside their own card.
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false
gui.Parent = playerGui

-- Backdrop. Two layers: a near-black base that does the actual hiding, and a tinted wash in the
-- destination's colour on top of it, so arriving in the Volcano and arriving in the Ocean do not
-- look like the same screen.
local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.new(1, 0, 1, 0)
backdrop.BackgroundColor3 = Color3.fromRGB(14, 11, 22)
backdrop.BackgroundTransparency = 1
backdrop.BorderSizePixel = 0
backdrop.ZIndex = 1
backdrop.Parent = gui

local wash = Instance.new("Frame")
wash.Name = "Wash"
wash.Size = UDim2.new(1, 0, 1, 0)
wash.BackgroundColor3 = Color3.fromRGB(60, 40, 90)
wash.BackgroundTransparency = 1
wash.BorderSizePixel = 0
wash.ZIndex = 2
wash.Parent = gui

local washGradient = Instance.new("UIGradient")
washGradient.Rotation = 90
washGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.35),
	NumberSequenceKeypoint.new(0.55, 0.8),
	NumberSequenceKeypoint.new(1, 0.3),
})
washGradient.Parent = wash

-- everything readable lives in here, so one transparency tween fades the whole lot together
local content = Instance.new("Frame")
content.Name = "Content"
content.Size = UDim2.new(1, 0, 1, 0)
content.BackgroundTransparency = 1
content.ZIndex = 3
content.Parent = gui

local emoji = Instance.new("TextLabel")
emoji.Name = "Emoji"
emoji.Size = UDim2.new(0, 190, 0, 190)
emoji.Position = UDim2.new(0.5, 0, 0.5, -132)
emoji.AnchorPoint = Vector2.new(0.5, 0.5)
emoji.BackgroundTransparency = 1
emoji.Font = Enum.Font.FredokaOne
emoji.TextScaled = true
emoji.Text = "\u{1F300}"
emoji.ZIndex = 4
emoji.Parent = content

local nameCard = UITheme.Card(content, {
	name = "ZoneName",
	size = UDim2.new(0, 520, 0, 92),
	position = UDim2.new(0.5, 0, 0.5, 0),
	anchorPoint = Vector2.new(0.5, 0.5),
	color = UITheme.Color.Lavender,
	text = "Travelling...",
	maxTextSize = 42,
})
nameCard.ZIndex = 4

local barFrame, barFill, barLabel = UITheme.ProgressBar(content, {
	name = "StreamBar",
	size = UDim2.new(0, 520, 0, 42),
	position = UDim2.new(0.5, 0, 0.5, 82),
	anchorPoint = Vector2.new(0.5, 0.5),
	color = UITheme.Color.Mint,
	progress = 0,
	text = "Loading world...",
	maxTextSize = 22,
})
barFrame.ZIndex = 4

local tip = Instance.new("TextLabel")
tip.Name = "Tip"
tip.Size = UDim2.new(0, 720, 0, 40)
tip.Position = UDim2.new(0.5, 0, 1, -70)
tip.AnchorPoint = Vector2.new(0.5, 1)
tip.BackgroundTransparency = 1
tip.Font = Enum.Font.GothamMedium
tip.TextScaled = true
tip.TextWrapped = true
tip.TextColor3 = Color3.fromRGB(226, 220, 240)
tip.TextTransparency = 0.25
tip.Text = ""
tip.ZIndex = 4
tip.Parent = content

-- ===== FADING ================================================================
-- Collected once rather than walked every time: UITheme.Card and ProgressBar build a shell, a
-- gloss layer, a stroke and labels, and every one of them needs its own transparency driven or
-- the panel fades in pieces.
local function collectFaders(root, out)
	out = out or {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			table.insert(out, { inst = d, props = { TextTransparency = d.TextTransparency, TextStrokeTransparency = d.TextStrokeTransparency, BackgroundTransparency = d.BackgroundTransparency } })
		elseif d:IsA("Frame") or d:IsA("ImageLabel") then
			table.insert(out, { inst = d, props = { BackgroundTransparency = d.BackgroundTransparency } })
		elseif d:IsA("UIStroke") then
			table.insert(out, { inst = d, props = { Transparency = d.Transparency } })
		end
	end
	return out
end

-- Captured while everything is still at its built-in transparency, which is why nothing above is
-- created pre-hidden: a piece created invisible would record 1 as its "visible" value and never
-- come back. setContentAlpha(1, 0) below is what actually hides the panel to start with.
local faders = collectFaders(content)

local function setContentAlpha(alpha, seconds)
	-- alpha 0 = fully visible, 1 = fully gone. Each piece fades from its OWN base value, so a label
	-- that is meant to sit at 0.25 never tweens up to full opacity on the way in.
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, entry in ipairs(faders) do
		local goal = {}
		for prop, base in pairs(entry.props) do
			goal[prop] = base + (1 - base) * alpha
		end
		TweenService:Create(entry.inst, info, goal):Play()
	end
end

-- start hidden
setContentAlpha(1, 0)

-- ===== READINESS =============================================================

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true

-- "Is the world actually here yet?" -- a downward ray from where the player now stands. With
-- streaming on, the parts under a freshly moved character can genuinely not exist yet, and this is
-- the cheapest honest answer to whether they do.
local function groundIsThere()
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	groundParams.FilterDescendantsInstances = { character, workspace:FindFirstChild("EquippedPets") }
	return workspace:Raycast(hrp.Position + Vector3.new(0, 6, 0), Vector3.new(0, -260, 0), groundParams) ~= nil
end

-- ===== THE TRANSITION ========================================================

local active = nil -- token of the transition currently on screen
local shownAt = 0

local function setProgress(value, text)
	barFill:TweenSize(UDim2.new(math.clamp(value, 0, 1), 0, 1, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.3, true)
	if text then barLabel.Text = text end
end

local function beginTransition(payload)
	active = payload.token
	shownAt = os.clock()

	local tint = payload.color or Color3.fromRGB(120, 100, 200)
	emoji.Text = payload.emoji or "\u{1F300}"
	UITheme.SetText(nameCard, payload.name or "Travelling...")
	UITheme.SetColor(nameCard, tint)
	wash.BackgroundColor3 = tint
	tip.Text = TIPS[math.random(1, #TIPS)]
	setProgress(0.06, "Loading world...")

	gui.Enabled = true
	TweenService:Create(backdrop, TweenInfo.new(FADE_IN), { BackgroundTransparency = 0 }):Play()
	TweenService:Create(wash, TweenInfo.new(FADE_IN), { BackgroundTransparency = 0.55 }):Play()
	setContentAlpha(0, FADE_IN)

	-- Cover the screen BEFORE asking for the region: RequestStreamAroundAsync yields for as long as
	-- it takes, and doing it first would leave the player looking at the void it is there to hide.
	task.wait(FADE_IN)
	setProgress(0.35, "Streaming terrain...")

	if payload.position then
		pcall(function()
			player:RequestStreamAroundAsync(payload.position, STREAM_TIMEOUT)
		end)
	end

	if active ~= payload.token then return end -- a newer transition started while we waited
	setProgress(0.72, "Almost there...")
	ReadyRemote:FireServer(payload.token)
end

local function finishTransition(payload)
	if active ~= payload.token then return end

	-- the character has just been moved; wait for something to stand on before showing it
	local t0 = os.clock()
	while not groundIsThere() and os.clock() - t0 < GROUND_TIMEOUT do
		task.wait(0.05)
	end
	setProgress(1, "Ready!")

	-- ...and never blink past: a neighbouring zone can stream in inside a single frame
	local held = os.clock() - shownAt
	if held < MIN_SHOW then
		task.wait(MIN_SHOW - held)
	end
	if active ~= payload.token then return end

	TweenService:Create(backdrop, TweenInfo.new(FADE_OUT), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(wash, TweenInfo.new(FADE_OUT), { BackgroundTransparency = 1 }):Play()
	setContentAlpha(1, FADE_OUT * 0.7)
	task.wait(FADE_OUT)
	if active == payload.token then
		gui.Enabled = false
		active = nil
	end
end

TransitionRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then return end
	if payload.phase == "start" then
		task.spawn(beginTransition, payload)
	elseif payload.phase == "arrived" then
		task.spawn(finishTransition, payload)
	end
end)

-- A safety net, not a feature. If the server dies mid-handshake, or a arrived-packet is lost, the
-- player would be left staring at a cover with no way out -- so any transition older than the
-- server's own timeout plus its slack wipes itself.
RunService.Heartbeat:Connect(function()
	if active and os.clock() - shownAt > 14 then
		active = nil
		gui.Enabled = false
		backdrop.BackgroundTransparency = 1
		wash.BackgroundTransparency = 1
		setContentAlpha(1, 0)
	end
end)
