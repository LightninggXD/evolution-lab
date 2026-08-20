--[[
	LoadingScreen - the cover that hides the world being built and streamed in at join.

	The place is ~60k parts spread over a 36,000-stud strip with StreamingEnabled on, and the
	server BUILDS the world at run time (ZoneService.Init -> ZoneBuilder.Build). Roblox's own
	loading screen goes away the moment the DataModel has replicated, which here is long before
	any of that is true: what a joining player actually saw was the spawn clearing assembling
	itself around them, gaps in the ground, and the HUD popping in a second later.

	So this script owns the join instead. It removes the default screen, covers everything, and
	holds the cover until all of these are true:

		1. game:IsLoaded()                     -- the DataModel is here
		2. the character exists with a root    -- we know WHERE to load around
		3. RequestStreamAroundAsync came back  -- the client asked for that region and got it
		4. there is ground under the player    -- ...and the region actually contains a floor
		5. the HUD (EvolutionLabUI) is built   -- so it does not pop in after the wipe

	Two deliberate choices:

	* It does NOT anchor the character. ZoneService.travel anchors the root and restores whatever
	  it found afterwards, and CharacterAdded fires that path within half a second of spawning --
	  an anchor set here would be read as "was anchored" and never come off.
	* It builds its own chrome instead of requiring UITheme first. ReplicatedFirst runs before
	  ReplicatedStorage has finished replicating, and a WaitForChild at the top would leave the
	  player looking at the very void this exists to hide. The backdrop goes up on line one; the
	  theme is required after, and the panel is built from it only if it turns up in time.
]]

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

local MIN_SHOW = 2.6      -- a join that wipes instantly reads as a glitch, not as a load
local HARD_TIMEOUT = 35   -- nothing traps the player behind this screen, ever
local STREAM_TIMEOUT = 12
local GROUND_TIMEOUT = 12
local HUD_TIMEOUT = 12

-- These are UITheme's own values, hard-copied rather than required. This script runs out of
-- ReplicatedFirst, BEFORE ReplicatedStorage has finished replicating, and the backdrop has to go
-- up on line one -- a WaitForChild here would leave the player looking at the very void this
-- exists to hide. UITheme is required further down and used if it turns up in time.
local OUTLINE = Color3.fromRGB(26, 18, 36)
local ACCENT = Color3.fromRGB(186, 146, 250)   -- Lavender

-- THE COVER IS A BRIGHT SKY, not a dark slab. It used to be rgb(14,11,22) -- near black -- under a
-- purple wash, which is a different game to the one behind it: twenty candy-coloured platforms
-- under an open blue sky. The wipe now reads as a curtain lifting on the same world instead of a
-- cut from black, and every element on top had to be re-picked for a light background, which is
-- what the tip card and the outlined text below are for.
local SKY_TOP = Color3.fromRGB(120, 205, 245)  -- SkyBlue
local SKY_LOW = Color3.fromRGB(255, 248, 235)  -- Cream, the haze at the horizon

-- Big soft shapes drifting up the screen. Fewer, larger and rounder beats many small ones -- the
-- same rule the world itself is built on -- and at this size four of them fill a 1536px screen.
local BLOB_COLORS = {
	Color3.fromRGB(255, 138, 205), -- Bubblegum
	Color3.fromRGB(124, 226, 142), -- Mint
	Color3.fromRGB(255, 214, 92),  -- Sunny
	Color3.fromRGB(186, 146, 250), -- Lavender
	Color3.fromRGB(255, 168, 104), -- Peach
}

local TIPS = {
	"Every creature you defeat pays DNA -- the tougher it is, the more it pays.",
	"Beat a zone's boss to open the gate behind it.",
	"Every egg podium lists exactly what it can hatch, and the odds.",
	"Rarer pets are strictly stronger -- rarity multiplies your tier bonus.",
	"The Colosseum gate is behind the Forest spawn. A giant returns every 30 minutes.",
	"Potions stack their duration instead of overlapping.",
	"Your pets grow with you -- they resize every time you evolve.",
}

-- ===== THE COVER (built with no dependencies, immediately) ====================

local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1000 -- over MainUI (0) and over ZoneTransition (500)
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.new(1, 0, 1, 0)
backdrop.BackgroundColor3 = SKY_TOP
backdrop.BorderSizePixel = 0
backdrop.ZIndex = 1
backdrop.Parent = gui

-- sky at the top fading to a pale haze at the bottom, the same way the world's horizon reads
local skyGradient = Instance.new("UIGradient")
skyGradient.Rotation = 90
skyGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, SKY_TOP),
	ColorSequenceKeypoint.new(0.62, Color3.fromRGB(178, 228, 250)),
	ColorSequenceKeypoint.new(1, SKY_LOW),
})
skyGradient.Parent = backdrop

-- The drifting shapes sit between the sky and the panel. Parented to their own layer rather than
-- to `content` so the wipe can fade them as one instead of walking them individually.
local blobs = Instance.new("Frame")
blobs.Name = "Blobs"
blobs.Size = UDim2.new(1, 0, 1, 0)
blobs.BackgroundTransparency = 1
blobs.ClipsDescendants = true
blobs.ZIndex = 2
blobs.Parent = gui

local content = Instance.new("Frame")
content.Name = "Content"
content.Size = UDim2.new(1, 0, 1, 0)
content.BackgroundTransparency = 1
content.ZIndex = 3
content.Parent = gui

-- Five of them, each on its own slow loop. Deliberately cheap: a tween per blob, started once,
-- never touched again -- this screen is on while the client is at its busiest streaming a
-- 36,000-stud strip, and it must not compete for frames with the thing it is waiting for.
for i, color in ipairs(BLOB_COLORS) do
	local size = 260 + (i % 3) * 130
	local blob = Instance.new("Frame")
	blob.Name = "Blob" .. i
	blob.Size = UDim2.new(0, size, 0, size)
	blob.AnchorPoint = Vector2.new(0.5, 0.5)
	blob.Position = UDim2.new(i / (#BLOB_COLORS + 1), 0, 1.25, 0)
	blob.BackgroundColor3 = color
	blob.BackgroundTransparency = 0.82
	blob.BorderSizePixel = 0
	blob.ZIndex = 2
	blob.Parent = blobs

	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = blob

	local rise = TweenInfo.new(11 + i * 2.5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false, i * 1.7)
	TweenService:Create(blob, rise, { Position = UDim2.new(i / (#BLOB_COLORS + 1), 0, -0.3, 0) }):Play()
end

-- The core gui belongs to the game, not to the load. Restored unconditionally at the end.
local hiddenCore = {}
for _, kind in ipairs({ Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.EmotesMenu }) do
	pcall(function()
		StarterGui:SetCoreGuiEnabled(kind, false)
		table.insert(hiddenCore, kind)
	end)
end

-- The mark, on a chunky white disc. A bare emoji on a bright sky is a small dark smudge; the disc
-- and its thick outline are the same treatment every button in the game gets, so the first thing
-- the player ever sees is already in the game's own language.
local logoHolder = Instance.new("Frame")
logoHolder.Name = "LogoHolder"
logoHolder.Size = UDim2.new(0, 200, 0, 200)
logoHolder.Position = UDim2.new(0.5, 0, 0.5, -168)
logoHolder.AnchorPoint = Vector2.new(0.5, 0.5)
logoHolder.BackgroundTransparency = 1
logoHolder.ZIndex = 4
logoHolder.Parent = content

local logoDisc = Instance.new("Frame")
logoDisc.Name = "LogoDisc"
logoDisc.Size = UDim2.new(1, 0, 1, 0)
logoDisc.BackgroundColor3 = Color3.fromRGB(252, 252, 255)
logoDisc.BorderSizePixel = 0
logoDisc.ZIndex = 4
logoDisc.Parent = logoHolder

local discRound = Instance.new("UICorner")
discRound.CornerRadius = UDim.new(1, 0)
discRound.Parent = logoDisc

local discStroke = Instance.new("UIStroke")
discStroke.Thickness = 6
discStroke.Color = OUTLINE
discStroke.Parent = logoDisc

local logo = Instance.new("TextLabel")
logo.Name = "Logo"
logo.Size = UDim2.new(0, 132, 0, 132)
logo.Position = UDim2.new(0.5, 0, 0.5, 0)
logo.AnchorPoint = Vector2.new(0.5, 0.5)
logo.BackgroundTransparency = 1
logo.Font = Enum.Font.GothamBlack
logo.TextScaled = true
logo.Text = "\u{1F9EC}"
logo.ZIndex = 5
logo.Parent = logoHolder

-- ===== THE PANEL (themed if UITheme arrives, plain if it does not) ============

local UITheme
do
	local modules = ReplicatedStorage:WaitForChild("Modules", 5)
	local moduleScript = modules and modules:WaitForChild("UITheme", 5)
	if moduleScript then
		local ok, result = pcall(require, moduleScript)
		if ok then
			UITheme = result
		end
	end
end

local titleCard, barFill, barLabel

if UITheme then
	logo.Font = UITheme.Font.Display
	titleCard = UITheme.Card(content, {
		name = "Title",
		size = UDim2.new(0, 560, 0, 96),
		position = UDim2.new(0.5, 0, 0.5, 0),
		anchorPoint = Vector2.new(0.5, 0.5),
		color = UITheme.Color.Lavender,
		text = "EVOLUTION LAB",
		maxTextSize = 46,
	})
	titleCard.ZIndex = 4
	local bar
	bar, barFill, barLabel = UITheme.ProgressBar(content, {
		name = "LoadBar",
		size = UDim2.new(0, 560, 0, 46),
		position = UDim2.new(0.5, 0, 0.5, 90),
		anchorPoint = Vector2.new(0.5, 0.5),
		color = UITheme.Color.Mint,
		progress = 0.04,
		text = "Connecting...",
		maxTextSize = 24,
	})
	bar.ZIndex = 4
else
	-- Fallback chrome. Same shapes, hand-rolled, so a UITheme that never replicated cannot leave
	-- the player staring at a bare colour field with no idea anything is happening.
	titleCard = Instance.new("TextLabel")
	titleCard.Name = "Title"
	titleCard.Size = UDim2.new(0, 560, 0, 96)
	titleCard.Position = UDim2.new(0.5, 0, 0.5, 0)
	titleCard.AnchorPoint = Vector2.new(0.5, 0.5)
	titleCard.BackgroundColor3 = ACCENT
	titleCard.Font = Enum.Font.GothamBlack
	titleCard.TextScaled = true
	titleCard.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleCard.Text = "EVOLUTION LAB"
	titleCard.ZIndex = 4
	titleCard.Parent = content
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 18)
	c.Parent = titleCard
	local s = Instance.new("UIStroke")
	s.Thickness = 4
	s.Color = OUTLINE
	s.Parent = titleCard

	local track = Instance.new("Frame")
	track.Name = "LoadBar"
	track.Size = UDim2.new(0, 560, 0, 46)
	track.Position = UDim2.new(0.5, 0, 0.5, 90)
	track.AnchorPoint = Vector2.new(0.5, 0.5)
	track.BackgroundColor3 = Color3.fromRGB(252, 252, 255)
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.ZIndex = 4
	track.Parent = content
	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(1, 0)
	tc.Parent = track
	local ts = Instance.new("UIStroke")
	ts.Thickness = 4
	ts.Color = OUTLINE
	ts.Parent = track

	barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.Size = UDim2.new(0.04, 0, 1, 0)
	barFill.BackgroundColor3 = Color3.fromRGB(124, 226, 142)
	barFill.BorderSizePixel = 0
	barFill.ZIndex = 5
	barFill.Parent = track
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(1, 0)
	fc.Parent = barFill

	barLabel = Instance.new("TextLabel")
	barLabel.Name = "Label"
	barLabel.Size = UDim2.new(1, -12, 1, -6)
	barLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	barLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	barLabel.BackgroundTransparency = 1
	barLabel.Font = Enum.Font.GothamBlack
	barLabel.TextScaled = true
	barLabel.TextColor3 = Color3.fromRGB(40, 32, 56)
	barLabel.Text = "Connecting..."
	barLabel.ZIndex = 7
	barLabel.Parent = track
end

-- The tip lives in a card now. As bare grey text it was legible on the old near-black backdrop
-- and would have been all but invisible on this one -- a light background needs either dark text
-- or a surface to sit on, and a surface is what the rest of the game uses.
local tipCard = Instance.new("Frame")
tipCard.Name = "TipCard"
tipCard.Size = UDim2.new(0, 720, 0, 62)
tipCard.Position = UDim2.new(0.5, 0, 1, -64)
tipCard.AnchorPoint = Vector2.new(0.5, 1)
tipCard.BackgroundColor3 = Color3.fromRGB(48, 42, 72)
tipCard.BackgroundTransparency = 0.12
tipCard.BorderSizePixel = 0
tipCard.ZIndex = 4
tipCard.Parent = content

local tipRound = Instance.new("UICorner")
tipRound.CornerRadius = UDim.new(0, 18)
tipRound.Parent = tipCard

local tipStroke = Instance.new("UIStroke")
tipStroke.Thickness = 4
tipStroke.Color = OUTLINE
tipStroke.Parent = tipCard

local tip = Instance.new("TextLabel")
tip.Name = "Tip"
tip.Size = UDim2.new(1, -32, 1, -14)
tip.Position = UDim2.new(0.5, 0, 0.5, 0)
tip.AnchorPoint = Vector2.new(0.5, 0.5)
tip.BackgroundTransparency = 1
tip.Font = Enum.Font.GothamMedium
tip.TextScaled = true
tip.TextWrapped = true
tip.TextColor3 = Color3.fromRGB(255, 248, 235)
tip.Text = TIPS[math.random(1, #TIPS)]
tip.ZIndex = 5
tip.Parent = tipCard

local tipSizeCap = Instance.new("UITextSizeConstraint")
tipSizeCap.MaxTextSize = 22
tipSizeCap.MinTextSize = 14
tipSizeCap.Parent = tip

-- the tip changes while we wait, so a long load still looks like something is happening
task.spawn(function()
	while gui.Parent do
		task.wait(4)
		if not gui.Parent then return end
		tip.Text = TIPS[math.random(1, #TIPS)]
	end
end)

-- gentle bob on the logo: proof of life even when every wait below is stalled
task.spawn(function()
	local up = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	TweenService:Create(logoHolder, up, { Position = UDim2.new(0.5, 0, 0.5, -192) }):Play()
end)

-- ===== PROGRESS ==============================================================

local currentProgress = 0.04
-- kept so the percentage can be rewritten on a call that only moves the bar, and the step name
-- does not blank out
local currentStep = "Connecting..."
local function setProgress(value, text)
	currentProgress = math.max(currentProgress, math.clamp(value, 0, 1))
	TweenService:Create(barFill, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(currentProgress, 0, 1, 0),
	}):Play()
	if text then
		currentStep = text
	end
	-- the number matters as much as the words: "Streaming the world..." on its own gives no sense
	-- of whether this join is nearly done or has barely started
	barLabel.Text = ("%s   %d%%"):format(currentStep, math.floor(currentProgress * 100 + 0.5))
end

-- ===== THE WAITS =============================================================

local startedAt = os.clock()
local function timeLeft()
	return HARD_TIMEOUT - (os.clock() - startedAt)
end

-- Every wait below is bounded twice: by its own budget and by what is left of HARD_TIMEOUT.
local function waitUntil(predicate, budget, poll)
	local deadline = os.clock() + math.min(budget, math.max(timeLeft(), 0))
	while os.clock() < deadline do
		if predicate() then
			return true
		end
		task.wait(poll or 0.1)
	end
	return predicate()
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true

local function groundHit()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	groundParams.FilterDescendantsInstances = { character, workspace:FindFirstChild("EquippedPets"), workspace:FindFirstChild("Creatures") }
	return workspace:Raycast(root.Position + Vector3.new(0, 8, 0), Vector3.new(0, -400, 0), groundParams)
end

-- The zone model a part belongs to.
--
-- The floor under your feet is usually NOT a descendant of its own zone: ZoneBuilder moves every
-- floor and boundary wall into Workspace.WorldShell, a persistent model, so that the shell of the
-- world can never stream out from under a player. What it leaves behind is a `Zone` attribute
-- naming the platform the part came from, which is the answer here. The walk up is the fallback
-- for anything still sitting inside its zone (a ramp, a prop, the arena's stands).
local function owningZone(inst)
	local zones = workspace:FindFirstChild("Zones")
	if not zones then
		return nil
	end
	local tagged = inst:GetAttribute("Zone")
	if tagged then
		return zones:FindFirstChild(tagged)
	end
	local node = inst
	while node and node.Parent ~= zones do
		node = node.Parent
	end
	return node
end

setProgress(0.1, "Connecting...")
if not game:IsLoaded() then
	game.Loaded:Wait()
end

setProgress(0.25, "Waking the lab...")
waitUntil(function()
	local character = player.Character
	return character ~= nil and character:FindFirstChild("HumanoidRootPart") ~= nil
end, 20, 0.1)

setProgress(0.45, "Streaming the world...")
do
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		pcall(function()
			player:RequestStreamAroundAsync(root.Position, math.min(STREAM_TIMEOUT, math.max(timeLeft(), 1)))
		end)
	end
end

setProgress(0.68, "Building the ground...")
waitUntil(function()
	return groundHit() ~= nil
end, GROUND_TIMEOUT, 0.1)

setProgress(0.82, "Growing the zone...")
do
	-- ...and then wait for the zone that ground belongs to to be more than a floor. A count, not a
	-- name check: with streaming on the model arrives first and fills in afterwards, so "the model
	-- exists" is true a long time before there is anything to look at.
	local hit = groundHit()
	local zone = hit and owningZone(hit.Instance)
	if zone then
		waitUntil(function()
			return #zone:GetDescendants() >= 400
		end, 8, 0.15)
	end
end

setProgress(0.93, "Laying out the HUD...")
waitUntil(function()
	return playerGui:FindFirstChild("EvolutionLabUI") ~= nil
end, HUD_TIMEOUT, 0.1)

setProgress(1, "Ready!")

local held = os.clock() - startedAt
if held < MIN_SHOW then
	task.wait(MIN_SHOW - held)
end

-- ===== WIPE ==================================================================

for _, kind in ipairs(hiddenCore) do
	pcall(function()
		StarterGui:SetCoreGuiEnabled(kind, true)
	end)
end

local FADE = 0.45
local fadeInfo = TweenInfo.new(FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
TweenService:Create(backdrop, fadeInfo, { BackgroundTransparency = 1 }):Play()
-- the blob layer is transparent itself; its children are what is on screen
for _, blob in ipairs(blobs:GetChildren()) do
	if blob:IsA("Frame") then
		TweenService:Create(blob, fadeInfo, { BackgroundTransparency = 1 }):Play()
	end
end
for _, d in ipairs(content:GetDescendants()) do
	local goal = {}
	if d:IsA("TextLabel") or d:IsA("TextButton") then
		goal.TextTransparency = 1
		goal.TextStrokeTransparency = 1
		if d.BackgroundTransparency < 1 then
			goal.BackgroundTransparency = 1
		end
	elseif d:IsA("Frame") or d:IsA("ImageLabel") then
		if d.BackgroundTransparency < 1 then
			goal.BackgroundTransparency = 1
		end
	elseif d:IsA("UIStroke") then
		goal.Transparency = 1
	end
	if next(goal) then
		TweenService:Create(d, fadeInfo, goal):Play()
	end
end
TweenService:Create(logo, fadeInfo, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()

task.wait(FADE)
gui:Destroy()

-- ===== FUNNEL STEP 2 (Phase 20) =====
-- HERE, and not at `setProgress(1)` above: the step means "the player can see the game", and
-- between that line and this one sit MIN_SHOW and a 0.45s fade -- up to three seconds in which
-- the world is ready and the player is still looking at a blue rectangle. The server cannot
-- observe either of them.
--
-- Fire-and-forget, and guarded: this script runs in ReplicatedFirst, before most of the game
-- exists, so the remote is found rather than waited on. A missing one costs a funnel row, and
-- a yield here would hold the wipe open.
pcall(function()
	local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
	local step = remotes and remotes:FindFirstChild("TelemetryStep")
	if step then step:FireServer("loaded") end
end)
