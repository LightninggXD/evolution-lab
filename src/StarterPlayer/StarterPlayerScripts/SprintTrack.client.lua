--[==[
	SprintTrack.client -- the countdown, the clock and the result card for the Forest sprint (17.5).

	The server owns the race entirely: it places the body, holds it on the line, times the run, reads
	the boost strips and pays out. This file draws it. Nothing here is authoritative and nothing here
	is asked for a number -- every payload it renders came from `ServerScriptService.SprintTrack`.

	WHY THE CLOCK RUNS LOCALLY ANYWAY. A timer replicated at 60 Hz for one player would be a remote
	call a frame, and one replicated at 10 Hz visibly stutters on a display that is counting
	hundredths. So the client starts its own clock on the `go` payload and the SERVER'S time is what
	lands in the result card -- the running number is a readout, the finishing number is the record,
	and the two can differ by the one round trip without either being wrong.

	AND IT IS DRIVEN BY `Heartbeat`, NOT `RenderStepped`. The first cut used `RenderStepped` -- the
	obvious signal for something that only exists on screen -- and the clock read a frozen `0.00`
	for a whole verified run. Counted in the same session, over one second: `Heartbeat` 60,
	`Stepped` 61, **`RenderStepped` 0**.

	BE PRECISE ABOUT WHAT THAT PROVES, because the honest version is the useful one: a Studio Play
	client does not paint, so `RenderStepped` never firing THERE is a sandbox condition and not a
	bug an ordinary rendering player would ever have hit. It is not a reason to distrust
	`RenderStepped` in general. The reason the clock lives on `Heartbeat` is the other three: a
	minimised or backgrounded real client is the same condition; a stopwatch is the one thing that
	must not silently stop (the same family as `RarityBeam.client`'s note about TweenService
	"running and moving nothing on a client that is not rendering"); and a clock has nothing to say
	to the renderer that 60 Hz simulation cannot say. It also costs nothing.

	IT WAITS ON ITS REMOTE WITH A TIMEOUT AND CARRIES ON. 35.7's three client scripts INDEXED a
	remote that a later `Init()` had not created yet and the index threw, taking the rest of each
	script with it; 35.12's fourth yielded for a minute instead. The remote this one wants is created
	at the server module's LOAD, so the window is closed at the other end -- but a bounded wait plus
	a warn is what the file should look like regardless, because the failure mode of getting it wrong
	is a dead script rather than a missing feature.
]==]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")

local UITheme = require(RS.Modules.UITheme)
local GameConfig = require(RS.Modules.GameConfig)

local player = Players.LocalPlayer

local remotes = RS:WaitForChild("Remotes", 30)
local runRemote = remotes and remotes:WaitForChild("SprintRun", 30)
if not runRemote then
	warn("[SprintTrack.client] Remotes.SprintRun never arrived -- the sprint HUD is off")
	return
end

local OUTLINE = UITheme.Color.Outline
local WHITE = UITheme.Color.White
local CYAN = Color3.fromRGB(90, 240, 255)

-- ============================================================================
-- THE SURFACE
-- ============================================================================
local gui, clockLabel, speedLabel, pipRow, bigLabel, card
local pips = {}

local function label(parent, size, position, anchor, font, colour)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = size
	t.Position = position
	t.AnchorPoint = anchor
	t.Font = font
	t.TextScaled = true
	t.TextColor3 = colour
	t.TextStrokeColor3 = OUTLINE
	t.TextStrokeTransparency = 0
	t.Text = ""
	t.Parent = parent
	return t
end

local function ensureGui()
	if gui and gui.Parent then return end

	gui = Instance.new("ScreenGui")
	gui.Name = "SprintTrackHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Over the HUD, because the countdown is a modal moment and a number half behind a currency
	-- pill is the thing 27.x spent a phase fixing everywhere else.
	gui.DisplayOrder = 40
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- The running clock, top-centre and clear of the wallet on the left and the tile column on the
	-- right. Both of those are anchored to their own edges, so the centre is the one lane that is
	-- free at every viewport width.
	clockLabel = label(gui, UDim2.new(0, 300, 0, 74), UDim2.new(0.5, 0, 0, 74), Vector2.new(0.5, 0),
		UITheme.Font.Display, WHITE)
	speedLabel = label(gui, UDim2.new(0, 300, 0, 34), UDim2.new(0.5, 0, 0, 150), Vector2.new(0.5, 0),
		UITheme.Font.Display, CYAN)

	-- One pip per boost strip, so the ramp has a shape on screen and not only underfoot.
	pipRow = Instance.new("Frame")
	pipRow.BackgroundTransparency = 1
	pipRow.Size = UDim2.new(0, 300, 0, 18)
	pipRow.Position = UDim2.new(0.5, 0, 0, 190)
	pipRow.AnchorPoint = Vector2.new(0.5, 0)
	pipRow.Parent = gui
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0, 8)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = pipRow

	-- The 3 / 2 / 1 / GO, and the "+14" that pops on a strip. One label for both: they never
	-- overlap in time, and a second one would only be a second thing to hide.
	bigLabel = label(gui, UDim2.new(0, 420, 0, 190), UDim2.new(0.5, 0, 0.42, 0), Vector2.new(0.5, 0.5),
		UITheme.Font.Display, WHITE)

	card = Instance.new("Frame")
	card.Name = "Result"
	card.Size = UDim2.new(0, 460, 0, 190)
	card.Position = UDim2.new(0.5, 0, 0.36, 0)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	card.BorderSizePixel = 0
	card.Visible = false
	card.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 20)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = OUTLINE
	stroke.Parent = card

	label(card, UDim2.new(1, -24, 0, 46), UDim2.new(0.5, 0, 0, 12), Vector2.new(0.5, 0),
		UITheme.Font.Display, OUTLINE).Name = "Band"
	label(card, UDim2.new(1, -24, 0, 62), UDim2.new(0.5, 0, 0, 60), Vector2.new(0.5, 0),
		UITheme.Font.Display, OUTLINE).Name = "Time"
	label(card, UDim2.new(1, -24, 0, 32), UDim2.new(0.5, 0, 0, 124), Vector2.new(0.5, 0),
		UITheme.Font.Display, OUTLINE).Name = "Reward"
	label(card, UDim2.new(1, -24, 0, 28), UDim2.new(0.5, 0, 0, 156), Vector2.new(0.5, 0),
		UITheme.Font.Body, OUTLINE).Name = "Note"
end

local function buildPips(total)
	for _, p in ipairs(pips) do p:Destroy() end
	pips = {}
	for i = 1, (total or 6) do
		local pip = Instance.new("Frame")
		pip.Size = UDim2.new(0, 26, 0, 12)
		pip.LayoutOrder = i
		pip.BackgroundColor3 = Color3.fromRGB(120, 118, 138)
		pip.BorderSizePixel = 0
		pip.Parent = pipRow
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 6)
		c.Parent = pip
		local s = Instance.new("UIStroke")
		s.Thickness = 2
		s.Color = OUTLINE
		s.Parent = pip
		pips[i] = pip
	end
end

-- ============================================================================
-- STATE
-- ============================================================================
local running = false
local localStart = 0
local tickConn = nil
local popToken = 0

local function showRace(on)
	clockLabel.Visible = on
	speedLabel.Visible = on
	pipRow.Visible = on
end

local function stopTick()
	if tickConn then
		tickConn:Disconnect()
		tickConn = nil
	end
end

local function hideAll()
	stopTick()
	running = false
	if gui then
		gui.Enabled = false
		card.Visible = false
		bigLabel.Text = ""
		showRace(false)
	end
end

-- A pop that never leaves text on the screen if a second one lands on top of it: each call takes a
-- token, and only the call whose token is still current is allowed to clear the label. Without it a
-- fast pair of strips leaves "+14" standing for the rest of the run.
local function pop(text, colour, seconds)
	popToken += 1
	local mine = popToken
	bigLabel.Text = text
	bigLabel.TextColor3 = colour
	task.delay(seconds, function()
		if popToken == mine then bigLabel.Text = "" end
	end)
end

runRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	ensureGui()
	local state = payload.state

	if state == "countdown" then
		gui.Enabled = true
		card.Visible = false
		buildPips(payload.padTotal)
		showRace(true)
		clockLabel.Text = "0.00"
		speedLabel.Text = ("BEST  %s"):format(GameConfig.FormatSprintTime(payload.best))
		running = false
		stopTick()
		local n = payload.seconds or 3
		task.spawn(function()
			for i = n, 1, -1 do
				if running then return end
				pop(tostring(i), WHITE, 1.05)
				task.wait(1)
			end
		end)

	elseif state == "go" then
		running = true
		localStart = os.clock()
		pop("GO!", CYAN, 0.7)
		stopTick()
		tickConn = RunService.Heartbeat:Connect(function()
			if not running then return end
			clockLabel.Text = ("%.2f"):format(os.clock() - localStart)
		end)

	elseif state == "pad" then
		local pip = pips[payload.index]
		if pip then pip.BackgroundColor3 = CYAN end
		speedLabel.Text = ("SPEED  %d"):format(math.floor(payload.speed or 0))
		pop(("+%d"):format(payload.step or 0), CYAN, 0.45)

	elseif state == "finished" then
		running = false
		stopTick()
		local seconds = payload.seconds or 0
		clockLabel.Text = ("%.2f"):format(seconds)
		showRace(false)
		bigLabel.Text = ""
		card.Visible = true
		card.Band.Text = ("%s %s"):format(payload.bandEmoji or "", payload.bandName or "FINISH")
		card.Band.TextColor3 = payload.bandColor or OUTLINE
		card.Time.Text = GameConfig.FormatSprintTime(seconds)
		card.Reward.Text = ("\u{1F31F} +%d Shards   \u{2022}   %d/%d strips")
			:format(payload.shards or 0, payload.pads or 0, payload.padTotal or 0)
		if payload.newBest then
			card.Note.Text = "\u{1F3C6} NEW PERSONAL BEST"
		else
			card.Note.Text = ("best %s   \u{2022}   %d runs left today")
				:format(GameConfig.FormatSprintTime(payload.best), payload.runsLeft or 0)
		end
		task.delay(5, function()
			if not running then hideAll() end
		end)

	elseif state == "cancelled" then
		running = false
		stopTick()
		showRace(false)
		card.Visible = false
		local why = payload.reason
		local text = "RUN CANCELLED"
		if why == "left" then text = "OFF THE TRACK"
		elseif why == "timeout" then text = "TOO SLOW"
		end
		pop(text, UITheme.Color.Red, 1.6)
		task.delay(1.7, function()
			if not running then hideAll() end
		end)

	elseif state == "refused" then
		-- The server already sent the wording through the ordinary Notify stack, which queues and
		-- ranks with every other refusal in the game. Nothing to draw here.
		hideAll()
	end
end)
