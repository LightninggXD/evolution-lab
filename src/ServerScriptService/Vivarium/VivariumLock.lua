--[==[
	VivariumLock -- the grille across a case's open front, how long it takes to break, and who is
	allowed to try (24.2).

	===== WHAT THE ROW ACTUALLY ASKS FOR, AND THE READING IT TURNS ON =====

	The row is one line: *"The lock -- 60 s, +10 s per rebirth, visible from a distance. The numbers
	are the reference's because they are proven"*. Sixty seconds of WHAT is not stated, and the two
	readings build different features:

	  * how long the lock STAYS on after the owner arms it, or
	  * how long a THIEF has to stand there to get through it.

	**It is the second, and `+10 s per rebirth` is what settles it.** A lock that merely lasts
	longer as you rebirth is a timer; a lock that takes longer to BREAK as you rebirth is a defence
	that grows with the account, which is the only reading under which the number is a progression
	reward. It is also the reference's own mechanic -- a thief stands at the door and waits out a
	bar while the owner is told about it. 24.3 carries the specimen out; this is the door it has to
	get through first.

	    strength = LOCK_BASE + LOCK_PER_REBIRTH * rebirths
	    R0 -> 60 s      R5 -> 110 s     R10 -> 160 s     R20 -> 260 s (GameConfig.MaxRebirths)

	**Four and a bit minutes at the top of the ladder is not an accident and must not be "balanced"
	down without saying so** -- it is the row's stated intent that a maxed account is close to
	unrobbable, and 24.5's anti-grief clauses lean on it.

	===== A GRILLE, NOT A PANE, AND THE REASON IS 24.1'S OWN HEADER =====

	`VivariumCase` refused a glass front because three transparencies compound and a pane in front of
	a tinted rig reads as fog. A lock has the same problem twice over: it has to say "shut" while
	still showing the collection, because the collection is the entire point of the case and hiding
	it would undo 24.1. So it is **six opaque vertical bars** with 0.81 of a stud between them --
	narrower than a humanoid, so it is a real barrier -- and the case behind it stays legible.
	Nothing here is transparent at all.

	===== VISIBLE FROM A DISTANCE MEANS A PIXEL-SIZED CHIP, NOT A BIGGER BAR =====

	23.2 measured this and it is the standing rule: a world-sized marker is a few pixels at 300
	studs, so **the only thing that survives distance is a pixel-sized `BillboardGui`**. The bars
	say "locked" from inside the aisle; the chip is what lets somebody scan a bank of cases from the
	spawn and pick a target. It states the STRENGTH, because that is the number a thief is choosing
	on, and it turns red with a live percentage while a break is running.

	===== THE PROMPT IS THE DOOR, AND IT SAYS ONE THING TO EVERYBODY =====

	`ProximityPrompt.ActionText` is a property of the PART, so there is no per-player version of it
	(`PartyStand` writes this out). One prompt, therefore, and the ANSWER differs per player: the
	owner resets their own lock, anybody else starts breaking it. What actually happened is said
	back through `Remotes.Notify`, which is per-player and can afford to be specific.

	An agent can press a `ProximityPrompt` and cannot press a `BillboardGui`
	(`evolution-lab-agent-cannot-click-billboards`), so the whole row is verifiable solo -- and the
	prompt hangs on an `Attachment` at head height because reach is only half the rule
	(`roblox-a-prompt-off-screen-is-a-dead-prompt`).

	===== WHAT IS DELIBERATELY NOT HERE =====

	`CanTarget` is the seam **24.5** fills in: today it refuses only the owner, and every
	anti-grief clause the roadmap lists (new-player immunity, one steal per target per N minutes, a
	per-thief cooldown, a rebirth floor, an opt-out) belongs in that one function rather than
	scattered through this file.

	The owner IS notified when a break starts and when it lands, and that is one clause of **24.4**
	arriving early on purpose: a lock that can be broken with no signal to its owner is not a
	defence, it is a delay. 24.4 still owns the rest of the clip -- the speed drop, the disabled
	items, anyone being able to hit the thief, and the kill feed.
]==]

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = RS.Remotes
local UITheme = require(RS.Modules.UITheme)
local VivariumCase = require(script.Parent.VivariumCase)

local VivariumLock = {}

-- ============================================================================
-- THE NUMBERS
-- ============================================================================
local LOCK_BASE = 60
local LOCK_PER_REBIRTH = 10

-- How long the case stays open once a break lands. Short on purpose: the open window is the thief's
-- opportunity, not a state the case sits in. It re-arms at full strength afterwards, so a second
-- thief pays the same price as the first rather than walking into a door somebody else already
-- opened.
local OPEN_WINDOW = 45

-- How far a thief may drift from the case before the break stops counting, and how long they may
-- stay away before it is cancelled outright. Measured against the case's pad centre, so it is
-- generous enough to fight in and tight enough that you cannot start one and walk off.
local BREAK_RADIUS = 18
local BREAK_GRACE = 5

local PROMPT_DISTANCE = 22
local PROMPT_HEIGHT = 6 -- studs over the bar's base; the same number every door in this game uses

-- ============================================================================
-- GEOMETRY -- local to the case's frame, front is -Z
-- ============================================================================
local PAD_W = VivariumCase.Width
local PAD_D = VivariumCase.Depth
local PAD_TOP = VivariumCase.PadTop
local WALL_H = VivariumCase.WallHeight

local BAR_X = { -3.75, -2.25, -0.75, 0.75, 2.25, 3.75 }
local BAR_W, BAR_T = 0.55, 0.45
local BAR_BASE = PAD_TOP + 0.4                -- clears the sill
local BAR_H = WALL_H - 0.4
local FRONT_Z = -(PAD_D * 0.5 - 0.35)         -- the sill's plane

local BRASS = Color3.fromRGB(214, 168, 74)
local ALARM = Color3.fromRGB(226, 88, 74)
local OUTLINE = Color3.fromRGB(26, 22, 42)
local OPEN_INK = Color3.fromRGB(110, 200, 130)

-- ============================================================================
-- STATE
-- ============================================================================
-- [caseIndex] = { bars, rails, chip, prompt, centre, ownerId, strength, openUntil, break = {...} }
local locks = {}
local heartbeat = nil

local function newPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	for k, v in pairs(props) do
		p[k] = v
	end
	return p
end

function VivariumLock.StrengthFor(rebirths)
	return LOCK_BASE + LOCK_PER_REBIRTH * (rebirths or 0)
end

--- Who may start a break on this case. **This is 24.5's seam** -- see the header.
function VivariumLock.CanTarget(player, ownerId)
	if player.UserId == ownerId then
		return false, "This is your own case."
	end
	return true
end

-- ============================================================================
-- THE CHIP
-- ============================================================================
local function drawChip(lock)
	local label = lock.chipLabel
	local br = lock.breaking
	if br then
		local pct = math.clamp(br.progress / math.max(lock.strength, 1), 0, 1)
		label.Text = ("\u{1F513} %d%%"):format(math.floor(pct * 100 + 0.5))
		label.TextColor3 = ALARM
		lock.chipStroke.Color = ALARM
	elseif lock.openUntil then
		label.Text = ("\u{1F513} OPEN %ds"):format(math.max(0, math.ceil(lock.openUntil - os.clock())))
		label.TextColor3 = OPEN_INK
		lock.chipStroke.Color = OPEN_INK
	else
		label.Text = ("\u{1F512} %ds"):format(lock.strength)
		label.TextColor3 = BRASS
		lock.chipStroke.Color = BRASS
	end
end

local function paintBars(lock)
	local open = lock.openUntil ~= nil
	local colour = lock.breaking and ALARM or BRASS
	for _, bar in ipairs(lock.bars) do
		bar.Transparency = open and 1 or 0
		bar.CanCollide = not open
		bar.Color = colour
	end
	for _, rail in ipairs(lock.rails) do
		rail.Transparency = open and 1 or 0
		rail.CanCollide = not open
	end
	lock.prompt.ActionText = open and "Case is open" or "Break the lock"
	lock.prompt.Enabled = true
end

-- ============================================================================
-- BUILD
-- ============================================================================
--- Hang a locked grille across `case.model`'s front. Called by `VivariumPlaza` on every claim.
function VivariumLock.Attach(index, model, frame, ownerId, rebirths)
	VivariumLock.Detach(index)

	local function at(x, y, z)
		return frame * CFrame.new(x, y, z)
	end

	local lock = {
		bars = {}, rails = {},
		ownerId = ownerId,
		strength = VivariumLock.StrengthFor(rebirths),
		centre = frame.Position,
		openUntil = nil,
		breaking = nil,
	}

	for i, bx in ipairs(BAR_X) do
		lock.bars[i] = newPart({
			Name = "LockBar" .. i, Size = Vector3.new(BAR_W, BAR_H, BAR_T),
			CFrame = at(bx, BAR_BASE + BAR_H * 0.5, FRONT_Z),
			Color = BRASS, CanCollide = true, Parent = model,
		})
	end
	for i, by in ipairs({ BAR_BASE, BAR_BASE + BAR_H }) do
		lock.rails[i] = newPart({
			Name = "LockRail" .. i, Size = Vector3.new(PAD_W, 0.5, BAR_T + 0.1),
			CFrame = at(0, by, FRONT_Z),
			Color = OUTLINE, CanCollide = true, Parent = model,
		})
	end

	-- ===== THE CHIP IS PIXEL-SIZED, WHICH IS THE ONLY KIND THAT SURVIVES DISTANCE (23.2) =====
	-- The case's own board is stud-sized because it is a sign you walk up to read; this is a marker
	-- you have to be able to pick out of a bank of cases from the spawn, which is the other job.
	local chipAnchor = newPart({
		Name = "LockChipAnchor", Size = Vector3.new(1, 1, 1),
		CFrame = at(0, BAR_BASE + BAR_H + 1.6, FRONT_Z),
		Transparency = 1, CanCollide = false, CanQuery = false, Parent = model,
	})
	local chip = Instance.new("BillboardGui")
	chip.Name = "LockChip"
	chip.Size = UDim2.fromOffset(104, 36)
	chip.AlwaysOnTop = false
	chip.LightInfluence = 0
	chip.MaxDistance = 520
	chip.Adornee = chipAnchor
	chip.Parent = chipAnchor

	local shell = Instance.new("Frame")
	shell.Size = UDim2.fromScale(1, 1)
	shell.BackgroundColor3 = Color3.fromRGB(20, 17, 28)
	shell.BackgroundTransparency = 0.1
	shell.BorderSizePixel = 0
	shell.Parent = chip
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = shell
	lock.chipStroke = Instance.new("UIStroke")
	lock.chipStroke.Thickness = 2
	lock.chipStroke.Color = BRASS
	lock.chipStroke.Parent = shell

	lock.chipLabel = Instance.new("TextLabel")
	lock.chipLabel.Size = UDim2.fromScale(0.9, 0.72)
	lock.chipLabel.Position = UDim2.fromScale(0.05, 0.14)
	lock.chipLabel.BackgroundTransparency = 1
	lock.chipLabel.Font = UITheme.Font.Display
	lock.chipLabel.TextScaled = true
	lock.chipLabel.TextStrokeColor3 = Color3.fromRGB(14, 10, 22)
	lock.chipLabel.TextStrokeTransparency = 0.2
	lock.chipLabel.Parent = shell

	-- On an Attachment at head height, never on the part: reach is necessary and not sufficient,
	-- and a prompt anchored at ankle level is measured dead from 14 studs.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LockPrompt"
	prompt.ObjectText = "Vivarium Case"
	prompt.ActionText = "Break the lock"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	local promptAt = Instance.new("Attachment")
	promptAt.Name = "PromptAnchor"
	promptAt.Position = Vector3.new(0, PROMPT_HEIGHT - BAR_H * 0.5, 0)
	promptAt.Parent = lock.bars[3]
	prompt.Parent = promptAt
	lock.prompt = prompt

	locks[index] = lock
	paintBars(lock)
	drawChip(lock)

	prompt.Triggered:Connect(function(player)
		VivariumLock.Press(index, player)
	end)

	model:SetAttribute("LockStrength", lock.strength)
	model:SetAttribute("LockOpen", false)
	return lock
end

function VivariumLock.Detach(index)
	local lock = locks[index]
	if not lock then return end
	-- the parts are children of the case model and go with it; only the state has to be dropped,
	-- and it has to be dropped even when the model is already gone
	locks[index] = nil
end

--- Re-derive the strength from a save that may have rebirthed since the claim. Never shortens a
--- break already in progress below what has been earned -- see the note in `tick`.
function VivariumLock.SetStrength(index, rebirths)
	local lock = locks[index]
	if not lock then return end
	local want = VivariumLock.StrengthFor(rebirths)
	if want ~= lock.strength then
		lock.strength = want
		local model = lock.prompt and lock.prompt:FindFirstAncestorOfClass("Model")
		if model then model:SetAttribute("LockStrength", want) end
		drawChip(lock)
	end
end

--- For 24.3: is this case's grille open right now, and for how much longer?
function VivariumLock.IsOpen(index)
	local lock = locks[index]
	if not lock or not lock.openUntil then return false, 0 end
	return true, math.max(0, lock.openUntil - os.clock())
end

-- ============================================================================
-- THE BREAK
-- ============================================================================
local function notify(userId, kind, message)
	local player = Players:GetPlayerByUserId(userId)
	if player then
		Remotes.Notify:FireClient(player, { kind = kind, message = message })
	end
end

local function ensureLoop()
	if heartbeat then return end
	heartbeat = RunService.Heartbeat:Connect(function(dt)
		VivariumLock.Step(dt)
	end)
end

local function stopBreak(lock, index, reason)
	local br = lock.breaking
	if not br then return end
	lock.breaking = nil
	paintBars(lock)
	drawChip(lock)
	if reason then
		notify(br.thiefId, "error", reason)
	end
end

function VivariumLock.Press(index, player)
	local lock = locks[index]
	if not lock then return end

	-- The owner's half of the one shared prompt: cancel whatever is happening to their own case.
	if player.UserId == lock.ownerId then
		if lock.breaking then
			local thief = Players:GetPlayerByUserId(lock.breaking.thiefId)
			stopBreak(lock, index, "The owner reset the lock.")
			notify(lock.ownerId, "party", ("You reset the lock -- %s was %d%% through it."):format(
				thief and thief.DisplayName or "somebody", 0))
		elseif lock.openUntil then
			lock.openUntil = nil
			-- ===== THE ATTRIBUTE IS THE DOOR, NOT A DECORATION (found by 24.3's verification) =====
			-- Every other exit from the open state stamps `LockOpen` and this one did not, because
			-- while 24.2 stood alone nothing READ it -- the bars carried the whole meaning. 24.3
			-- gates its take prompt on the attribute, so an owner who re-locked their own case left
			-- a door that was shut and said it was open: solid bars, and a specimen still liftable
			-- through them. A state written in two places is a state that will disagree.
			local model = lock.prompt and lock.prompt:FindFirstAncestorOfClass("Model")
			if model then model:SetAttribute("LockOpen", false) end
			paintBars(lock)
			drawChip(lock)
			notify(lock.ownerId, "party", ("Case re-locked -- %ds to break."):format(lock.strength))
		else
			notify(lock.ownerId, "party", ("Your lock holds for %ds."):format(lock.strength))
		end
		return
	end

	local allowed, why = VivariumLock.CanTarget(player, lock.ownerId)
	if not allowed then
		notify(player.UserId, "error", why or "You cannot target this case.")
		return
	end
	if lock.openUntil then
		notify(player.UserId, "error", "This case is already open.")
		return
	end
	if lock.breaking then
		if lock.breaking.thiefId == player.UserId then
			stopBreak(lock, index, "You stopped breaking the lock.")
		else
			notify(player.UserId, "error", "Somebody else is already working on this lock.")
		end
		return
	end

	lock.breaking = { thiefId = player.UserId, progress = 0, outSince = nil }
	paintBars(lock)
	drawChip(lock)
	ensureLoop()

	notify(player.UserId, "party", ("Breaking in -- %ds, and you have to stay within %d studs."):format(
		lock.strength, BREAK_RADIUS))
	-- ONE CLAUSE OF 24.4, ARRIVING HERE ON PURPOSE: see the header. A lock that can be broken with
	-- no signal to its owner is a delay, not a defence.
	notify(lock.ownerId, "error", ("\u{1F513} %s is breaking into your case!"):format(player.DisplayName))
end

local function distanceTo(player, centre)
	local char = player.Character
	local root = char and (char.PrimaryPart or char:FindFirstChild("HumanoidRootPart"))
	if not root then return math.huge end
	local p = root.Position
	return math.sqrt((p.X - centre.X) ^ 2 + (p.Z - centre.Z) ^ 2)
end

--- One frame of every running break and every open window. Exposed so a probe can drive it with a
--- synthetic dt instead of waiting out a real 60 seconds.
function VivariumLock.Step(dt)
	local busy = false
	for index, lock in pairs(locks) do
		if lock.openUntil then
			busy = true
			if os.clock() >= lock.openUntil then
				lock.openUntil = nil
				local model = lock.prompt and lock.prompt:FindFirstAncestorOfClass("Model")
				if model then model:SetAttribute("LockOpen", false) end
				paintBars(lock)
				notify(lock.ownerId, "party", "Your case re-locked.")
			end
			drawChip(lock)
		end

		local br = lock.breaking
		if br then
			busy = true
			local thief = Players:GetPlayerByUserId(br.thiefId)
			if not thief then
				stopBreak(lock, index, nil)
			else
				local d = distanceTo(thief, lock.centre)
				if d <= BREAK_RADIUS then
					br.outSince = nil
					-- ===== THE STRENGTH IS READ EVERY FRAME, NOT CAPTURED AT THE START =====
					-- A rebirth landing mid-break raises the bar under the thief, which is correct:
					-- the lock is a fact about the account, not a contract struck when the prompt
					-- was pressed. Progress already earned is never taken away.
					br.progress += dt
					if br.progress >= lock.strength then
						lock.breaking = nil
						lock.openUntil = os.clock() + OPEN_WINDOW
						local model = lock.prompt and lock.prompt:FindFirstAncestorOfClass("Model")
						if model then model:SetAttribute("LockOpen", true) end
						paintBars(lock)
						notify(br.thiefId, "reward", ("Lock broken -- the case is open for %ds."):format(OPEN_WINDOW))
						notify(lock.ownerId, "error", "\u{1F513} Your case has been broken open!")
					end
				else
					br.outSince = br.outSince or os.clock()
					if os.clock() - br.outSince > BREAK_GRACE then
						stopBreak(lock, index, "You left the case -- the lock reset.")
					end
				end
				drawChip(lock)
			end
		end
	end

	-- ONE GATED LOOP. It disconnects the moment nothing is breaking and nothing is open, so a
	-- gallery of sixty idle cases costs no per-frame work at all.
	if not busy and heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
end

VivariumLock.Base = LOCK_BASE
VivariumLock.PerRebirth = LOCK_PER_REBIRTH
VivariumLock.OpenWindow = OPEN_WINDOW
VivariumLock.BreakRadius = BREAK_RADIUS
VivariumLock.Locks = locks -- the probe seam, for the reason `VivariumPlaza.Anchors` is one

return VivariumLock
