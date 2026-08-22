-- UIComponents/AdventureRunHud -- the capsule you read while you are on the course (30.6).
--
-- =====================================================================================
-- IT IS NOT A PANEL, AND THAT IS THE WHOLE POINT
-- =====================================================================================
-- The same argument `ExpeditionUI`'s seal tracker makes: everything on this capsule is information
-- you need WHILE MOVING, which is exactly when a modal is shut. So it is a fixed strip in the band
-- 16.2 established as idle -- top centre, under the currencies -- and it is never a screen-centre
-- card. `evolution-lab-feedback-placement` is the standing rule; the checkpoint flash in
-- `AdventureService.wireMap` is the other half of it, drawn on the pad where it happened.
--
-- It shares that band with the expedition's tracker, and the two can never be up together: a player
-- on a course has been teleported off the expedition map, and neither run survives the other's
-- entry.
--
-- =====================================================================================
-- THE CLOCK IS THE SERVER'S, SUBTRACTED ON THE CLIENT
-- =====================================================================================
-- `pushState` sends `startedAt` as `workspace:GetServerTimeNow()` and nothing else about time --
-- deliberately, per the note over it: a HUD counting up has to survive the trip, and that is the
-- one clock both machines can subtract from. The run's OWN authority is still `os.clock()` on the
-- server (`HandleFinish` reads it before anything yields), so this display is a mirror and is
-- allowed to be a few frames out; it can never decide a par bonus.
--
-- =====================================================================================
-- PAR IS A TARGET AND THE COLOUR SAYS SO
-- =====================================================================================
-- Mint under, amber over -- and it goes amber rather than red, because missing par still finishes
-- the run and still pays a relic. `GetAdventureRolls` is the authority (2 rolls at or under par,
-- 1 over), and it is INCLUSIVE at par, which is why the comparison here is `>` and not `>=`: 30.4
-- checked both sides of that line and ON it for exactly this reason.

local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Remotes = RS:WaitForChild("Remotes")
local GameConfig = require(RS.Modules.GameConfig)
local SoundLibrary = require(RS.Modules.SoundLibrary)

local Common = require(script.Parent:WaitForChild("AdventureCommon"))

local AdventureRunHud = {}

local INK = Color3.fromRGB(0, 0, 50)
local UNDER = Color3.fromRGB(150, 255, 200)
local OVER = Color3.fromRGB(255, 206, 120)

local capsule = nil
local titleLine = nil
local stepLine = nil
local timeLine = nil
local barFill = nil
local state = nil

local function build(screenGui)
	capsule = Instance.new("Frame")
	capsule.Name = "AdventureRun"
	capsule.AnchorPoint = Vector2.new(0.5, 0)
	capsule.Position = UDim2.new(0.5, 0, 0, 148)
	capsule.Size = UDim2.new(0, 340, 0, 158)
	capsule.BackgroundColor3 = Color3.fromRGB(26, 24, 40)
	capsule.BackgroundTransparency = 0.15
	capsule.BorderSizePixel = 0
	capsule.ZIndex = 40
	capsule.Visible = false
	-- NOT stamped `HudPanel`. That attribute means "a panel one of the close-all sweeps may shut",
	-- and this is a run indicator: `ScrollingPanelBuilder.SetOpen` closes every stamped frame in
	-- this ScreenGui when a panel opens, which would blank the capsule the moment the player opened
	-- anything at all.
	capsule.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = capsule

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = INK
	stroke.Parent = capsule

	titleLine = Common.Line(capsule, {
		name = "Route",
		size = UDim2.new(1, -16, 0, 28),
		position = UDim2.new(0, 8, 0, 8),
		textSize = 24,
		zIndex = 42,
	})

	stepLine = Common.Line(capsule, {
		name = "Step",
		size = UDim2.new(1, -16, 0, 22),
		position = UDim2.new(0, 8, 0, 38),
		textSize = 20,
		color = Color3.fromRGB(214, 214, 240),
		zIndex = 42,
	})

	local barTrack = Instance.new("Frame")
	barTrack.Name = "Bar"
	barTrack.Size = UDim2.new(1, -32, 0, 12)
	barTrack.Position = UDim2.new(0, 16, 0, 64)
	barTrack.BackgroundColor3 = Color3.fromRGB(52, 48, 72)
	barTrack.BorderSizePixel = 0
	barTrack.ZIndex = 41
	barTrack.Parent = capsule

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = barTrack

	barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFill.BackgroundColor3 = UNDER
	barFill.BorderSizePixel = 0
	barFill.ZIndex = 42
	barFill.Parent = barTrack

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = barFill

	timeLine = Common.Line(capsule, {
		name = "Timer",
		size = UDim2.new(1, -16, 0, 32),
		position = UDim2.new(0, 8, 0, 82),
		textSize = 28,
		color = UNDER,
		zIndex = 42,
	})

	local leave = Common.Button(capsule, {
		name = "Leave",
		text = "LEAVE",
		size = UDim2.new(0, 160, 0, 36),
		position = UDim2.new(0.5, 0, 0, 116),
		anchorPoint = Vector2.new(0.5, 0),
		colors = Common.Color.Leave,
		textSize = 22,
		zIndex = 43,
	})
	-- LEAVING IS A DOOR AND NOT DECORATION. A course has a `PortalGate` you can walk back into, but
	-- a player who has fallen behind it -- or cannot find it on a five-section course -- has no other
	-- way home, and the game's single SpawnLocation is 4,000 studs away. `AdventureRemotes` opens
	-- this one for that reason and `HandleLeave` refuses anybody not on a course.
	leave.MouseButton1Click:Connect(function()
		SoundLibrary.PlayLocal("close")
		Remotes.AdventureLeave:FireServer()
	end)

	-- ONE CONNECTION, and it returns on the first line while nothing is running. A run is the only
	-- time anything here changes per frame.
	RunService.Heartbeat:Connect(function()
		if not state then return end
		local route = GameConfig.GetAdventure(state.key)
		local par = route and route.parSeconds or 0
		local elapsed = workspace:GetServerTimeNow() - (state.startedAt or 0)
		local over = par > 0 and elapsed > par
		timeLine.Text = ("%s  /  par %s"):format(Common.ClockTenths(elapsed), Common.Clock(par))
		timeLine.TextColor3 = over and OVER or UNDER
		barFill.BackgroundColor3 = over and OVER or UNDER
	end)
end

--- The `AdventureState` payload, or `{ running = false }`. This is the only way in.
function AdventureRunHud.Apply(payload)
	if type(payload) ~= "table" or not payload.running then
		state = nil
		if capsule then capsule.Visible = false end
		return
	end

	state = payload
	local route = GameConfig.GetAdventure(payload.key)
	local sections = math.max(payload.sections or 1, 1)
	local index = math.clamp(payload.index or 1, 1, sections)

	titleLine.Text = ((route and route.emoji) or "\u{1F5FA}") .. "  "
		.. ((route and route.name) or tostring(payload.key))
	-- "2 / 4", the SAME words the course paints on its own checkpoint banners
	-- (`AdventureMap` line 384). Two vocabularies for one number is how a player decides the HUD is
	-- counting something else.
	stepLine.Text = ("Checkpoint %d / %d"):format(index, sections)
	barFill.Size = UDim2.new(index / sections, 0, 1, 0)
	capsule.Visible = true

	-- A run has started (or a checkpoint moved, which can only happen during one), so nothing that
	-- opens off the board belongs on the screen. Cheap, and it closes the window where a player
	-- presses PLAY on a second route from a panel left open behind the travel cover.
	Common.CloseAll()
end

function AdventureRunHud.Init(screenGui)
	if capsule then return AdventureRunHud end
	build(screenGui)
	return AdventureRunHud
end

--- True while the player is on a course. `AdventureUI` asks before it opens the board, because a
--- prompt is still reachable from inside a map that happens to be near one.
function AdventureRunHud.IsRunning()
	return state ~= nil
end

return AdventureRunHud
