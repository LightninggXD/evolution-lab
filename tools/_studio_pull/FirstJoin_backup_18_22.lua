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

-- ============================================================================
-- ...AND IT GETS OUT OF THE WAY OF A PANEL (15.20)
-- ============================================================================
-- `DisplayOrder` beats `ZIndex` ACROSS ScreenGuis, and it does so absolutely: this gui is at 110
-- and `EvolutionLabUI` never sets one at all, so it is at 0. No ZIndex a panel can choose will ever
-- put it over this banner. Photographed on both clients of the two-client run: "⚔️ Click a creature
-- to attack it" sat across the trade window covering BOTH offer column headers, and across the
-- trade picker's header.
--
-- Lowering `DisplayOrder` is the wrong fix -- the 110 is deliberate, because the arrow points at
-- the EVOLVE button and the banner has to clear the HUD it is talking about. What is actually true
-- is that a panel is a MODAL surface: while one is open the guide is both wrong and in the way.
--
-- So the whole gui is disabled rather than each piece hidden. One watcher, and none of the
-- visibility logic below it has to learn about panels -- including the two one-shot timed banners
-- (`TutorialDone` and the climb beat), which set `Visible` once and would otherwise each need
-- their own guard.
task.spawn(function()
	local mainGui = player.PlayerGui:WaitForChild("EvolutionLabUI", 30)
	if not mainGui then
		warn("[FirstJoin] EvolutionLabUI never appeared -- the guide cannot yield to panels")
		return
	end
	while true do
		local panelOpen = false
		-- direct children only: `registerPanel` stamps `HudPanel` on the panel itself, and every
		-- one of them is parented straight to the ScreenGui
		for _, child in ipairs(mainGui:GetChildren()) do
			if child:GetAttribute("HudPanel") and child.Visible then
				panelOpen = true
				break
			end
		end
		gui.Enabled = not panelOpen
		task.wait(0.15)
	end
end)

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
-- POINTING AT SOMETHING IN THE WORLD (9.10)
-- ============================================================================
-- The banner could always say "click a creature"; it could never say WHICH. On a street with
-- fourteen of them walking past, an instruction with no target is still a wall of text -- the row's
-- own complaint. So the guide gets one marker it can hang over any object, and one Highlight to
-- pick that object out of the crowd.
--
-- ONE OF EACH, RE-ADORNED, never one per target. Roblox draws about 31 Highlights at once and
-- CreatureService already rents fourteen of them to the creatures nearest the player (see its
-- outline pool); a guide that created its own per candidate would quietly push that budget over and
-- take outlines off the creatures it is pointing at.
--
-- The marker is a BillboardGui rather than a beam or a part: it is always the right way up, it
-- cannot be walked behind, and it needs no per-frame CFrame maths on the client.
local marker = Instance.new("BillboardGui")
marker.Name = "GuideMarker"
marker.Size = UDim2.new(0, 96, 0, 96)
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
markerLabel.TextStrokeColor3 = UITheme.Color.Outline
markerLabel.TextStrokeTransparency = 0
markerLabel.Parent = marker

local pointHL = Instance.new("Highlight")
pointHL.Name = "GuideHighlight"
pointHL.FillTransparency = 0.72
pointHL.FillColor = UITheme.Color.Sunny
pointHL.OutlineColor = UITheme.Color.White
pointHL.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
pointHL.Enabled = false
pointHL.Parent = gui

-- `height` is how far above the target's own top the marker floats, so it clears a Swarmer and a
-- Guardian alike without being told how big either is.
local function pointAt(target, height)
	if not target then
		marker.Enabled = false
		pointHL.Enabled = false
		pointHL.Adornee = nil
		marker.Adornee = nil
		return
	end
	local adornee = target
	if target:IsA("Model") then
		adornee = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
	end
	if not adornee then return end
	local _, size = pcall(function() return target:IsA("Model") and select(2, target:GetBoundingBox()) or target.Size end)
	local top = (typeof(size) == "Vector3" and size.Y or 6) * 0.5
	marker.Adornee = adornee
	marker.StudsOffsetWorldSpace = Vector3.new(0, top + (height or 5), 0)
	marker.Enabled = true
	pointHL.Adornee = target
	pointHL.Enabled = true
end

-- The nearest LIVE creature. Two traps, both already paid for elsewhere in this game and both silent
-- if ignored: `workspace.Creatures` holds loose `Part`s (`DeathBurst`) as well as rigs, so anything
-- that assumes a Model errors on a bare part; and a creature's health is a replicated ATTRIBUTE, not
-- a Humanoid -- asking for `Humanoid.Health` reports zero live creatures in a world holding hundreds,
-- which reads exactly like an empty street rather than like a wrong question.
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

-- The nearest way UP. The flights live in `WorldShell` rather than in the zone folder, because
-- `TerraceRamp` is in ZoneBuilder's ALWAYS_LOADED set -- walkable ground that is allowed to stream
-- out is a hole to fall through. Looking for them in the zone finds nothing and looks exactly like
-- the ramps never having been built.
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
-- WHAT THE PLAYER IS BEING ASKED TO DO
-- ============================================================================
-- Two steps, and which one is showing is derived from the save every tick rather than remembered.
-- A remembered step gets out of step with the world the first time something else moves the numbers
-- -- an offline payout, a code, a gift -- and then the guide is confidently wrong.
local function stepFor(data)
	if not data then return nil end
	local step = GameConfig.GetEvolveStep(data)
	if step.isMax then return nil end
	-- XP alone, because XP alone is what the server checks now -- see DNAService.HandleEvolve. The
	-- DNA half of this test would have told a new player they were not ready while the button they
	-- are being pointed at was already green.
	if (data.XP or 0) >= step.xpCost then
		return "evolve"
	end
	return "fight"
end

local function textFor(which, data)
	if which == "evolve" then
		return "⭐ You are ready! Press EVOLVE"
	end
	-- ONE HINT, BECAUSE THERE IS ONE GATE. This used to branch between "attack" and "collect DNA"
	-- depending on which of the two requirements was short, and the DNA branch is now unreachable
	-- and would be a lie if it fired: an evolve costs XP and nothing else.
	return "⚔️ Click a creature to attack it"
end

-- Forward-declared: `runGuide` calls this and Lua binds an upvalue where a function is WRITTEN, so
-- without the name in scope here the call below would resolve to a nil global.
local runClimbBeat

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

				-- AND THE OTHER HALF OF THE INSTRUCTION (9.10). "Click a creature" names the verb;
				-- the marker names the noun. Re-targeted every tick rather than locked on: the chosen
				-- creature is walking, can be killed by somebody else, and can stream out -- a guide
				-- pinned to one target ends up pointing at nothing and telling the player to hit it.
				if which == "fight" then
					pointAt(nearestCreature(), 6)
				else
					pointAt(nil)
				end
				STEP:Wait()
			end
		end)

		banner.Visible = false
		arrow.Visible = false
		pointAt(nil)
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
				runClimbBeat()
			end)
		end
	end)
end

-- ============================================================================
-- THE FOURTH BEAT: CLIMB (9.10)
-- ============================================================================
-- attack -> reward -> evolve are the first three and were already here. The row asks for a fourth,
-- and it is the one piece of this world nobody discovers on their own: the terraces carry the
-- stronger creatures and the shard drops, and the flights up them stand 400+ studs off the street.
-- A player who is never told looks at a valley and assumes that is the game.
--
-- SHOWN ONCE, AFTER THE EVOLVE, and driven by nothing that persists. There is no save field for it
-- and there should not be: a field means a migration and a repair for every existing save (6.3's
-- `TutorialDone` needed exactly that), for a banner that costs nothing if it is occasionally missed.
-- A session flag is the honest weight for a one-line hint.
local CLIMB_BEAT_TIME = 7.0

runClimbBeat = function()
	if state.climbShown then return end
	state.climbShown = true
	task.spawn(function()
		local ramp = nearestRamp()
		-- No flight within range is a normal answer, not a failure: the arena and the Colosseum have
		-- no terraces at all. Say nothing rather than pointing at the horizon.
		if not ramp then return end
		banner.BackgroundColor3 = UITheme.Color.Aqua
		bannerText.Text = "\u{26F0}\u{FE0F} Climb up there -- tougher creatures, better drops"
		banner.Visible = true
		pointAt(ramp, 10)
		local t0 = os.clock()
		-- the pointer is kept alive on its own loop rather than left adorned: the ramp is persistent
		-- geometry, but the player is walking, and a marker that stops updating while its target
		-- streams in and out flickers
		while os.clock() - t0 < CLIMB_BEAT_TIME do
			STEP:Wait()
		end
		banner.Visible = false
		pointAt(nil)
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
