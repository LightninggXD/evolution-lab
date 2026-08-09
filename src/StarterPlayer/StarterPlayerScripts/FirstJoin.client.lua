--[[
	FirstJoin -- the first two minutes of the game, guided (Phase 6.3).

	Zones 1 and 2 were designed as a tutorial stretch and then nothing ever told the player that.
	A new arrival landed in Forest with twenty-odd buttons, no idea that DNA comes from hitting the
	creatures walking past, and an EVOLVE button that says "not enough DNA" until they work out why.

	Three beats, and they are the roadmap's own: a camera pan that shows the street, an arrow that
	names the next thing to do, and the first evolve -- which `EvolveReveal` already celebrates, so
	this file gets out of the way rather than adding a second card on top of it.

	=========================================================================================
	WHAT DECIDES WHETHER THIS RUNS
	=========================================================================================
	`data.TutorialDone`, a real field in the save, flipped by the SERVER on the first evolve. Not
	"is this player at stage 1": a rebirth resets StageIndex to 1, so that test would replay the
	whole sequence for a veteran every time they reset. And not a client-side "I have finished"
	report, because a client that can say that can say it having never played.

	=========================================================================================
	THE THREE THINGS THAT WOULD LEAVE A PLAYER STUCK
	=========================================================================================
	1. A SCRIPTABLE CAMERA THAT IS NEVER GIVEN BACK. Everything the pan touches is restored in one
	   block that runs whether the pan finished, errored, or was skipped -- and the restore is the
	   `Custom` camera type plus the humanoid as subject, i.e. the state the engine sets up itself,
	   not a CFrame this file guessed. A failure halfway through otherwise leaves that player
	   looking at scenery with no way out but a rejoin.
	2. A GUIDE THAT WILL NOT LET GO. Any input at all skips the pan. Nobody who already knows this
	   game should have to watch three seconds of it, and a player who is pressing keys is telling
	   you exactly that.
	3. HEARTBEAT, NEVER RENDERSTEPPED. `RenderStepped:Wait()` never returns on a client that is not
	   rendering, and the whole sequence would hang inside its own pcall with no error anywhere --
	   see HatchReveal's header, which is where that cost an hour.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS:WaitForChild("Modules"):WaitForChild("GameConfig"))
local UITheme = require(RS.Modules:WaitForChild("UITheme"))

local player = Players.LocalPlayer
local Remotes = RS:WaitForChild("Remotes")

local STEP = RunService.Heartbeat

local PAN_TIME = 3.4
local ARROW_BOB = 10          -- pixels the arrow travels up and down
local DONE_BANNER_TIME = 4.0

local state = {
	data = nil,
	panned = false,           -- once per session, not once per payload
	running = false,
}

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

	-- Framed off the CHARACTER's own facing rather than off world axes: the spawn faces down the
	-- Forest street, and a pan written against +Z would be looking at a wall the day that changes.
	local here = root.Position
	local facing = root.CFrame.LookVector
	local startAt = here + Vector3.new(0, 62, 0) - facing * 78
	local endAt = here + Vector3.new(0, 7, 0) - facing * 18

	local ok, err = pcall(function()
		cam.CameraType = Enum.CameraType.Scriptable
		local t0 = os.clock()
		while os.clock() - t0 < PAN_TIME and not skipped do
			local a = (os.clock() - t0) / PAN_TIME
			-- eased in and out, so it settles into the over-the-shoulder shot instead of stopping
			local eased = a < 0.5 and 2 * a * a or 1 - (-2 * a + 2) ^ 2 / 2
			local at = startAt:Lerp(endAt, eased)
			-- looks at the player the whole way down, which is what makes it read as an introduction
			-- to a character rather than a flyover of some trees
			cam.CFrame = CFrame.lookAt(at, (player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				or root).Position + Vector3.new(0, 2, 0))
			STEP:Wait()
		end
	end)

	conn:Disconnect()

	-- THE RESTORE, on every path. Custom + the humanoid is the state the engine builds for itself;
	-- handing back a CFrame this file invented would leave the camera subtly wrong forever.
	cam.CameraType = Enum.CameraType.Custom
	if humanoid then
		cam.CameraSubject = humanoid
	end
	if not ok then
		warn("[FirstJoin] camera pan failed: " .. tostring(err))
	end
end

-- ============================================================================
-- THE GUIDE
-- ============================================================================
-- Its own ScreenGui: MainUI is at Luau's 200-register ceiling (see its header) and none of this is
-- HUD state. `ResetOnSpawn = false` because dying during the tutorial is the most likely moment of
-- all to still need it.
local gui = Instance.new("ScreenGui")
gui.Name = "FirstJoinGuide"
gui.ResetOnSpawn = false
gui.DisplayOrder = 110        -- over the HUD, under the zone-transition wipe (500)
gui.Parent = player:WaitForChild("PlayerGui")

local banner = Instance.new("Frame")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, 132)
banner.Size = UDim2.new(0, 520, 0, 64)
banner.BackgroundColor3 = UITheme.Color.Purple
banner.BorderSizePixel = 0
banner.Visible = false
banner.Parent = gui
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 16)
	c.Parent = banner
	local s = Instance.new("UIStroke")
	s.Thickness = 4
	s.Color = UITheme.Color.Outline
	s.Parent = banner
end

local bannerText = Instance.new("TextLabel")
bannerText.Size = UDim2.new(1, -24, 1, -14)
bannerText.Position = UDim2.new(0.5, 0, 0.5, 0)
bannerText.AnchorPoint = Vector2.new(0.5, 0.5)
bannerText.BackgroundTransparency = 1
bannerText.Font = UITheme.Font.Display
bannerText.TextScaled = true
bannerText.TextColor3 = UITheme.Color.White
bannerText.TextStrokeColor3 = UITheme.Color.Outline
bannerText.TextStrokeTransparency = 0
bannerText.Text = ""
bannerText.Parent = banner

-- The arrow is a label, not an image: an asset id is one more thing that can be moderated away, and
-- a glyph cannot fail to load. It is pinned to the EVOLVE button's live AbsolutePosition rather than
-- to a coordinate, so the responsive pass can move that button without stranding it.
-- BESIDE THE BUTTON, NOT ABOVE IT, and the capture is what settled that. Above is the obvious place
-- and it is occupied: the evolve frame stacks a stage label, then the DNA/XP progress bar, then the
-- button, so a 64 px arrow hanging over the button covers the bar -- it hid the very "120 / 120 DNA"
-- that explains why the player is being told to press. To the left there is nothing between the
-- evolve frame and the left-hand tile column, so the arrow points across empty screen.
local arrow = Instance.new("TextLabel")
arrow.Name = "Arrow"
arrow.AnchorPoint = Vector2.new(1, 0.5)
arrow.Size = UDim2.new(0, 64, 0, 64)
arrow.BackgroundTransparency = 1
arrow.Font = UITheme.Font.Display
arrow.TextScaled = true
arrow.Text = "➡️"
arrow.TextColor3 = UITheme.Color.White
arrow.TextStrokeColor3 = UITheme.Color.Outline
arrow.TextStrokeTransparency = 0
arrow.Visible = false
arrow.Parent = gui

-- IgnoreGuiInset IS DELIBERATELY LEFT FALSE, and it is the one line here that was measured wrong
-- first. The reasoning that fails: "MainUI ignores the inset, so match it." Matching makes the two
-- render alike but breaks the arithmetic, because the two quantities this file mixes do NOT share an
-- origin -- `AbsolutePosition` is reported below the topbar, while a Position OFFSET inside an
-- inset-ignoring ScreenGui is measured from the very top of the screen. Copying `true` put the arrow
-- exactly one inset (58 px, measured) above the button, which looks like a layout bug and is really a
-- unit mismatch. Left false, the offset and the AbsolutePosition it is computed from share an origin
-- and the arrow lands where the arithmetic says.
gui.IgnoreGuiInset = false

local function findEvolveButton()
	local host = player.PlayerGui:FindFirstChild("EvolutionLabUI")
	return host and host:FindFirstChild("EvolveButton", true)
end

-- ============================================================================
-- WHAT THE PLAYER IS BEING ASKED TO DO
-- ============================================================================
-- Two steps, and which one is showing is derived from the save every tick rather than remembered.
-- A remembered step gets out of step with the world the first time something else moves the numbers
-- -- an offline payout, a code, a gift -- and then the guide is confidently wrong.
local function stepFor(data)
	if not data then return nil end
	local step = GameConfig.GetEvolveStep(data)
	if step.isMax then return nil end
	if (data.DNA or 0) >= step.cost and (data.XP or 0) >= step.xpCost then
		return "evolve"
	end
	return "fight"
end

local function textFor(which, data)
	if which == "evolve" then
		return "⭐ You are ready! Press EVOLVE"
	end
	local step = GameConfig.GetEvolveStep(data)
	-- Names the gate that is actually short. Both are needed to evolve, and being told to collect
	-- DNA while the XP bar is the empty one is the sort of wrong hint that teaches a player to stop
	-- reading them.
	if (data.XP or 0) < step.xpCost then
		return "⚔️ Click a creature to attack it"
	end
	return "🧬 Beat creatures for DNA to evolve"
end

local function runGuide()
	if state.running then return end
	state.running = true
	-- Set on every run, not once at build time. The completion line below repaints this banner green
	-- and never puts it back, so a guide that ever restarts -- a player who quits mid-tutorial and
	-- returns in the same session -- would be given its instructions in the colour that means
	-- "finished". A one-way write to shared state is a bug waiting for a second caller.
	banner.BackgroundColor3 = UITheme.Color.Purple

	task.spawn(function()
		local ok, err = pcall(function()
			local t0 = os.clock()
			while state.data and not state.data.TutorialDone do
				local which = stepFor(state.data)
				if which then
					banner.Visible = true
					bannerText.Text = textFor(which, state.data)
				else
					banner.Visible = false
				end

				-- the arrow belongs to the evolve step only: pointing at a button the player cannot
				-- press yet is an instruction to do something that will fail
				local btn = which == "evolve" and findEvolveButton() or nil
				if btn then
					local pos, size = btn.AbsolutePosition, btn.AbsoluteSize
					-- the bob runs along the axis it points down, so it reads as nudging the player
					-- toward the button rather than bouncing beside it
					local bob = math.abs(math.sin((os.clock() - t0) * 3.4)) * ARROW_BOB
					arrow.Position = UDim2.new(0, pos.X - 8 - bob, 0, pos.Y + size.Y * 0.5)
					arrow.Visible = true
				else
					arrow.Visible = false
				end
				STEP:Wait()
			end
		end)

		banner.Visible = false
		arrow.Visible = false
		state.running = false
		if not ok then
			warn("[FirstJoin] guide failed: " .. tostring(err))
		end

		-- The evolve itself is already celebrated by EvolveReveal's "New X Discovered!" card, so this
		-- adds one line rather than a second card: what to do NEXT, which is the one thing that card
		-- cannot say.
		if state.data and state.data.TutorialDone then
			banner.BackgroundColor3 = UITheme.Color.Green
			bannerText.Text = "🎉 Evolved! Keep fighting -- new zones open as you grow"
			banner.Visible = true
			task.delay(DONE_BANNER_TIME, function()
				banner.Visible = false
			end)
		end
	end)
end

-- ============================================================================
-- WIRING
-- ============================================================================
Remotes:WaitForChild("DataUpdate").OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	state.data = data
	if data.TutorialDone then return end

	if not state.panned then
		state.panned = true
		task.spawn(panCamera)
	end
	runGuide()
end)
