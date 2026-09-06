--[==[
	SprintTrack -- the running strip in Forest, and the one thing in this game that is about moving
	(17.5).

	===== THE ROW =====

	Kristina, 2026-08-16: *"pogledaj malo +1 ili evolution roblox igre pa iskopiraj speed ima i one
	trake za trcanje"*. Two halves. The SPEED half shipped under 34.29 -- the Speed upgrade is gone
	and the five trails are the speed ladder now -- and the economics of why this pays that ladder's
	currency rather than paying speed directly are written at the top of `GameConfig/Sprint.lua`,
	beside the numbers. This file is the other half: the PLACE.

	===== WHY A DASH AND NOT A LAP CIRCUIT =====

	The lane is measured, not chosen. `WorldShell.Floor` north of the plaza gate is dead flat at
	y = 0 and the only clear rectangle of any size in the whole of Forest -- the village map, the
	plaza's own furniture, the arcade terminal at (-96, 452) and the zone portal's approach at
	x +/- 17, z 470..570 take everything else. Probed live 2026-09-06: x -66..174 by z 418..452 is
	252 x 34 studs with ZERO parts in it.

	An oval was designed and rejected on that measurement plus one other. 240 x 56 gives turns of
	about a 22-stud radius, and a Roblox humanoid at 124 studs/s does not corner in 22 studs -- it
	slides off the lane, which would mean walling the track in and making the walls the feature.
	So: a straight dash, the same shape a real 60-metre sprint is, run repeatedly.

	===== AND WHY IT IS NOT A FIXED-TIME RACE =====

	The trap in a straight lane with a forced speed is that the time is DETERMINISTIC -- every run
	posts the same number, and a personal best nobody can beat is not a hook. So the ramp is EARNED:
	six boost strips lie alternately against the two outer lanes, each worth +14 studs/s, and the
	player has to weave to collect them. A perfect run and a lazy one differ by about a third of the
	clock, which is what makes the board worth walking back to.

	The strips are also the literal thing she asked for -- *"one trake za trcanje"*.

	===== WHAT OWNS THE HUMANOID, AND FOR HOW LONG =====

	`WalkSpeed` has exactly one true writer, `EvolutionVisuals.applyMastery`, and exactly one other
	service allowed to take it: `AdventureService`, which forces a fixed profile "for a bounded
	window" between a gate and a finish line. `WaterfallParkour`'s header records why it refused to
	do the same -- the falls are open world, so there is nowhere to put the restore, and a player who
	logged out mid-climb would keep the boost for ever.

	A dash HAS both ends, so this file may do what the courses do. Every exit from a run goes through
	one function, `endRun`, and it restores through `EvolutionVisuals.RefreshBonuses` rather than a
	remembered pair of numbers -- the player's real speed is a product of stage, Mastery, the 2x
	pass, a worn aura and a worn trail, and any of those can change while they are out here. The
	exits are: finished, left the box, died, timed out, left the server, and a rebuild of the track
	underneath them.

	THE CLIENT SPRINT IS NOT FOUGHT, ON PURPOSE. `CombatClient` multiplies whatever the server sets
	by 1.4 while Shift is held, and re-reads the base whenever the server moves it. Everyone has
	Shift, it is free, and the bands below were measured with it -- so it is part of running well
	rather than a hole in the race. 124 x 1.4 = 174, which is under the 260 the 2x Speed pass already
	puts on the same humanoid, on a 252-stud lane standing on a Persistent floor.

	===== BUILT LIKE THE PLAZA, NOT LIKE A ZONE =====

	Its own version stamp and its own model at the top of Workspace, which is the arrangement
	`RebirthShrine`, `WaterfallParkour` and `WorldApron` all use and all give the same reason for: a
	scenery change here must never drag `ZoneBuilder`'s BUILD_VERSION and its 105,000 parts along
	with it, and a zone rebuild must not be able to take the track with it. Idempotent BY
	REPLACEMENT and not by skipping -- a half-built track from an interrupted run would otherwise
	survive for ever behind an "already there" check, which is the failure that left a zone
	permanently truncated once already.
]==]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")

local Remotes = RS:WaitForChild("Remotes")

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local ZoneKit = require(script.Parent.ZoneKit)
local PlayerDataService = require(script.Parent.PlayerDataService)
local Telemetry = require(script.Parent.Telemetry)

local SprintTrack = {}

-- Bumped whenever the geometry below changes, exactly like `PLAZA_VERSION`. A server that boots
-- against an older stamp destroys what is there and builds again.
local TRACK_VERSION = 1

-- ============================================================================
-- THE LANE -- every number here is measured against the live world, not chosen
-- ============================================================================
-- Probed 2026-09-06 on a booted server: `GetPartBoundsInBox` over
-- (x 50 +/- 126, y 1.4..19.4, z 435 +/- 17) returned 0 parts, and a raycast grid across the whole
-- footprint hit `WorldShell.Floor` at y = 0.00 at every sample. The neighbours that decide these
-- bounds, so a later session knows what it would be walking into if it widened them:
--
--   Map.MinigameTerminals.MinigameTerminal_Forest  plinth (-96, 452), 24 x 17  -- west
--   Zones.Forest.ZonePad                           (0, 490), 14 x 14           -- the portal, north
--   Zones.Forest.PortalMat                         (0, 519), 34 x 98           -- its approach
--   Map.ExpeditionDoor                             (210, 440), 48 wide         -- east
--   HubPlaza gate signs                            z 404, deck edge z 416      -- south
local LANE_Z = 435          -- the lane's centre line
local LANE_HALF = 16        -- so the running surface is z 419..451
local START_X = -66         -- the start line: the clock starts on the far side of it
local FINISH_X = 174        -- the finish line
local LANE_LENGTH = FINISH_X - START_X   -- 240

-- The surface sits just proud of the lawn. `HubPlaza` states every paving layer by its TOP face and
-- grows it downward to a common buried bottom so no two layers can share a horizontal plane; the
-- same trick, and the same reason -- coplanar paint z-fights.
local GROUND_Y = 0
local KERB_TOP = 0.30
local TRACK_TOP = 0.44
local STRIPE_TOP = 0.52
local PAD_TOP = 0.68

-- ===== THE SIX BOOST STRIPS =====
-- Evenly spaced down the lane and alternating between the two OUTER lanes, so collecting them all
-- is a weave rather than a straight line. 36 studs apart along x, 24 apart across z: at the speeds
-- involved that is a real steering input and not a formality, which is the entire source of the
-- spread between a good run and a bad one.
local PAD_COUNT = 6
local PAD_FIRST_X = -30
local PAD_STEP_X = 36
local PAD_Z = { LANE_Z - 12, LANE_Z + 12 }
local PAD_LEN = 12          -- along x
local PAD_WIDE = 10         -- along z

-- How close counts as taking one. Checked on Heartbeat rather than by `Touched`, and the radius is
-- sized off the worst frame this can see: at the top speed of 124 -- 174 with the client's sprint
-- multiplier -- a body moves 2.9 studs in a 60 Hz frame, so a half-length of 8 cannot be stepped
-- over. `Touched` would have been the obvious choice and is exactly the one that drops a hit at
-- these speeds.
local PAD_REACH_X = 8
local PAD_REACH_Z = 7

-- The leash. Deliberately much bigger than the lane: this is "has clearly left the track", not
-- "wandered a stud wide". A player who steps off the paint is still racing.
local BOX_Z = 40
local BOX_BACK = 40         -- studs behind the start line
local BOX_FORWARD = 60      -- studs past the finish line
local BOX_UP = 40

local PROMPT_DISTANCE = 26

-- ============================================================================
-- PALETTE
-- ============================================================================
-- A clay-red athletics track against Forest's green lawn. The village contrast rule applies: theme
-- the HUE and pick the TONE against the ground it stands on. Forest's ground union is a mid green
-- (74, 140, 74) -- a warm red at a similar value would read as mud, so the surface is lifted well
-- above the lawn's tone and the lane paint is near-white, which is what makes the stripes survive
-- this zone's very bright key light.
local OUTLINE = Color3.fromRGB(26, 18, 36)
local TRACK_RED = Color3.fromRGB(206, 96, 68)
local TRACK_DARK = Color3.fromRGB(168, 70, 50)
local LANE_PAINT = Color3.fromRGB(248, 240, 228)
local PAD_CYAN = Color3.fromRGB(90, 240, 255)
local GOLD = UITheme.Color.Gold

-- ============================================================================
-- PART VOCABULARY
-- ============================================================================
-- A local copy rather than a require of `ZoneBuilder`'s, for the reason `HubPlaza`, `RebirthShrine`
-- and `SplicerService` all give for having their own: that module is thousands of lines and
-- rebuilds tens of thousands of parts behind a version stamp of its own. This one builds about
-- forty.
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

-- A flat slab stated by its TOP face and grown down to a common buried bottom. See KERB_TOP above.
local function pave(model, name, cx, cz, sx, sz, top, colour)
	local bottom = -1.2
	local thickness = top - bottom
	return newPart({
		Name = name,
		Size = Vector3.new(sx, thickness, sz),
		Position = Vector3.new(cx, top - thickness * 0.5, cz),
		Color = colour,
		CanCollide = true,
		Parent = model,
	})
end

-- ============================================================================
-- THE BUILD
-- ============================================================================
local trackModel = nil
local padParts = {}         -- [1..PAD_COUNT] -> Part, in run order
local archLabel = nil       -- the arch board's second line
local startPart = nil

-- Where a runner is put before the countdown. Being placed rather than merely standing near the
-- prompt is what makes two players' times comparable at all -- a race started from wherever
-- somebody happened to be leaning is not a race.
--
-- THE HEIGHT IS THE RUNNER'S OWN AND NOT A CONSTANT, and that is the whole reason this takes an
-- argument. A body in this game runs 1x to 5x and a max-stage one is about 39 studs tall, so its
-- HumanoidRootPart stands far higher over the same floor than a Cell's does -- an authored y would
-- bury the big body in the lane and drop the small one out of the sky. The player is already
-- standing on this floor when they press E, so their current y is the right one by construction.
local function startCFrame(y)
	-- Facing +X, which is down the lane. `CFrame.lookAt` from the line toward the finish rather
	-- than an authored Orientation, so moving FINISH_X can never leave the runner facing a wall.
	return CFrame.lookAt(
		Vector3.new(START_X - 6, y, LANE_Z),
		Vector3.new(FINISH_X, y, LANE_Z))
end

local function padPosition(i)
	return Vector3.new(
		PAD_FIRST_X + (i - 1) * PAD_STEP_X,
		PAD_TOP,
		PAD_Z[(i % 2 == 1) and 1 or 2])
end

local function buildSign(parent, adornee, offsetY, title, sub, subColour)
	local sign = Instance.new("BillboardGui")
	sign.Name = "TrackSign"
	sign.Size = UDim2.new(0, 300, 0, 104)
	-- A PLAIN STUD VALUE, not `ExtentsOffsetWorldSpace`. That one is in HALF-EXTENT units and put
	-- the arcade's sign 68 studs into the sky when it was copied from a place where the adornee was
	-- a player -- see the note at `MinigameService`'s terminal sign. This adornee is authored
	-- geometry that never changes size, so the number in the source is the number on the screen.
	sign.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	sign.MaxDistance = 320
	sign.LightInfluence = 0
	sign.AlwaysOnTop = false
	sign.Adornee = adornee
	sign.Parent = parent

	local top = Instance.new("TextLabel")
	top.Name = "Title"
	top.BackgroundTransparency = 1
	top.Size = UDim2.new(1, 0, 0.56, 0)
	top.Font = ZoneKit.SIGN_FONT
	top.Text = title
	top.TextColor3 = Color3.fromRGB(255, 255, 255)
	top.TextScaled = true
	top.Parent = sign
	local topStroke = Instance.new("UIStroke")
	topStroke.Thickness = 3
	topStroke.Color = ZoneKit.SIGN_INK
	topStroke.Parent = top

	local bottom = Instance.new("TextLabel")
	bottom.Name = "Sub"
	bottom.BackgroundTransparency = 1
	bottom.Size = UDim2.new(1, 0, 0.44, 0)
	bottom.Position = UDim2.new(0, 0, 0.56, 0)
	bottom.Font = ZoneKit.SIGN_FONT
	bottom.Text = sub
	bottom.TextColor3 = subColour
	bottom.TextScaled = true
	bottom.Parent = sign
	local bottomStroke = Instance.new("UIStroke")
	bottomStroke.Thickness = 3
	bottomStroke.Color = ZoneKit.SIGN_INK
	bottomStroke.Parent = bottom

	return bottom
end

local function build()
	local existing = workspace:FindFirstChild("SprintTrack")
	if existing then
		if existing:GetAttribute("TrackVersion") == TRACK_VERSION then
			return existing
		end
		existing:Destroy()
	end

	local model = Instance.new("Model")
	model.Name = "SprintTrack"

	local cx = (START_X + FINISH_X) * 0.5

	-- Outline first. The chunky look rule this world is built to says the dark edge is drawn before
	-- the bright mass, not added to it afterwards.
	pave(model, "Kerb", cx, LANE_Z, LANE_LENGTH + 24, LANE_HALF * 2 + 8, KERB_TOP, OUTLINE)
	pave(model, "Surface", cx, LANE_Z, LANE_LENGTH + 16, LANE_HALF * 2, TRACK_TOP, TRACK_RED)

	-- Four lanes, so three dividers plus the two edges. Thin and near-white: at this zone's key
	-- light a mid tone here would vanish into the clay.
	for _, z in ipairs({ LANE_Z - 8, LANE_Z, LANE_Z + 8 }) do
		pave(model, "LaneLine", cx, z, LANE_LENGTH + 16, 0.7, STRIPE_TOP, LANE_PAINT)
	end

	-- The two lines that matter. Wider than a lane divider so they read as gates from the ground.
	pave(model, "StartLine", START_X, LANE_Z, 2.4, LANE_HALF * 2, STRIPE_TOP, LANE_PAINT)
	pave(model, "FinishLine", FINISH_X, LANE_Z, 2.4, LANE_HALF * 2, STRIPE_TOP, LANE_PAINT)

	-- ===== THE START BLOCK, AND ITS DOOR =====
	startPart = newPart({
		Name = "StartBlock",
		Size = Vector3.new(10, 7, LANE_HALF * 2 + 8),
		Position = Vector3.new(START_X - 13, GROUND_Y + 3.5, LANE_Z),
		Color = TRACK_DARK,
		CanCollide = true,
		Parent = model,
	})
	newPart({
		Name = "StartBlockCap",
		Size = Vector3.new(12, 1.2, LANE_HALF * 2 + 10),
		Position = Vector3.new(START_X - 13, GROUND_Y + 7.6, LANE_Z),
		Color = OUTLINE,
		CanCollide = false,
		Parent = model,
	})

	-- MOUNTED ON AN ATTACHMENT AT A SANE HEIGHT, which is 35.8 / 35.9's whole lesson: a prompt
	-- whose origin is metres above the camera never fires, and the fix at `ZoneBuilder.addPrompt`
	-- was to hang it on an Attachment near the ground rather than on the host's centre. This block
	-- is 7 tall, so its centre is already low enough -- the Attachment is here so the reach is
	-- measured from the FACE a player walks up to and not from the middle of the box.
	local promptAt = Instance.new("Attachment")
	promptAt.Name = "PromptAt"
	promptAt.Position = Vector3.new(5, 0.5, 0)
	promptAt.Parent = startPart

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SprintPrompt"
	prompt.ActionText = "Run the track"
	prompt.ObjectText = "Sprint Track"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = promptAt

	buildSign(startPart, startPart, 15,
		"\u{1F3C3} SPRINT TRACK",
		"hit the strips \u{2022} beat the clock",
		PAD_CYAN)

	-- ===== THE FINISH ARCH =====
	local archY = 26
	for _, side in ipairs({ -1, 1 }) do
		newPart({
			Name = "ArchPost",
			Size = Vector3.new(4, archY, 4),
			Position = Vector3.new(FINISH_X, GROUND_Y + archY * 0.5, LANE_Z + side * (LANE_HALF + 2)),
			Color = OUTLINE,
			CanCollide = true,
			Parent = model,
		})
	end
	local lintel = newPart({
		Name = "ArchLintel",
		Size = Vector3.new(6, 5, LANE_HALF * 2 + 12),
		Position = Vector3.new(FINISH_X, GROUND_Y + archY + 2, LANE_Z),
		Color = TRACK_DARK,
		CanCollide = false,
		Parent = model,
	})
	newPart({
		Name = "ArchLintelCap",
		Size = Vector3.new(7.4, 1.2, LANE_HALF * 2 + 13.4),
		Position = Vector3.new(FINISH_X, GROUND_Y + archY + 5.1, LANE_Z),
		Color = OUTLINE,
		CanCollide = false,
		Parent = model,
	})
	archLabel = buildSign(lintel, lintel, 11, "\u{1F3C1} FINISH", "no time set yet", GOLD)

	-- ===== THE SIX STRIPS =====
	padParts = {}
	for i = 1, PAD_COUNT do
		local at = padPosition(i)
		pave(model, "PadOutline", at.X, at.Z, PAD_LEN + 3, PAD_WIDE + 3, PAD_TOP - 0.06, OUTLINE)
		local pad = pave(model, "Pad" .. i, at.X, at.Z, PAD_LEN, PAD_WIDE, PAD_TOP, PAD_CYAN)
		pad.Material = Enum.Material.Neon
		padParts[i] = pad
	end

	model:SetAttribute("TrackVersion", TRACK_VERSION)
	model.Parent = workspace
	-- Persistent, so the lane under a sprinting player's feet cannot stream out from under them --
	-- which is the same reason the plaza sets it, and it matters more here than anywhere else in
	-- the game because this is the one place a player is deliberately moving at 174 studs/s.
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)

	trackModel = model
	print(("[SprintTrack] built v%d: %d parts, lane %d studs, %d strips, x %d..%d at z %d")
		:format(TRACK_VERSION, #model:GetDescendants(), LANE_LENGTH, PAD_COUNT, START_X, FINISH_X, LANE_Z))
	return model
end

-- ============================================================================
-- THE REMOTE
-- ============================================================================
-- CREATED AT MODULE LOAD, NOT AT `Init()`, and that is 35.7 / 35.12's lesson applied before it can
-- bite: `ServerMain:99` is the map build and it takes about a minute, so any client script that
-- reaches for a remote created by a later `Init()` either yields for a minute or -- if it INDEXES
-- the name instead -- throws and takes the rest of itself with it. `ServerMain` requires this
-- module in its first frames, so creating it here closes the window rather than shortening it.
local function remote()
	-- created on demand, like every remote added since the place was last saved by hand
	local r = Remotes:FindFirstChild("SprintRun")
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = "SprintRun"
		r.Parent = Remotes
	end
	return r
end
remote()

-- Refusals go through the ordinary stack so they queue, rank and sound like every other refusal in
-- the game, rather than this feature inventing its own way of saying no.
local function notify(player, kind, message)
	Remotes.Notify:FireClient(player, { kind = kind, message = message })
end

-- ============================================================================
-- THE SERVER BEST, AND THE ARCH THAT PRINTS IT
-- ============================================================================
-- In memory and per server, deliberately. An OrderedDataStore board for a race with no anti-cheat
-- beyond "you were on the lane" is an invitation, and `LeaderboardService` already owns the global
-- boards. What this is for is the thing that makes a dash worth a second go: somebody else's number
-- standing over the finish line.
local serverBest = nil      -- seconds
local serverBestName = nil

local function refreshArch()
	if not (archLabel and archLabel.Parent) then return end
	if serverBest then
		archLabel.Text = ("%s by %s"):format(GameConfig.FormatSprintTime(serverBest), serverBestName)
		archLabel.TextColor3 = GOLD
	else
		archLabel.Text = "no time set yet"
		archLabel.TextColor3 = GOLD
	end
end

-- ============================================================================
-- A RUN
-- ============================================================================
-- One per player, keyed by UserId. Several players may race at once and never see each other's
-- state -- the only shared thing is the arch.
local runs = {}
local heartbeat = nil

local function humanoidOf(player)
	local character = player.Character
	return character, character and character:FindFirstChildOfClass("Humanoid")
end

-- Putting it back is one call and NOT a remembered pair of numbers, which is `AdventureService`'s
-- note verbatim: the player's real speed is a product of stage, Mastery, the 2x pass, a worn aura
-- and a worn trail, and any of those can change while they are out here.
--
-- Required LAZILY. `EvolutionVisuals` is a Systems module that requires half the server, and this
-- file is required by `ServerMain` beside services that load before it.
local function restoreProfile(player)
	local EvolutionVisuals = require(script.Parent.Systems.EvolutionVisuals)
	EvolutionVisuals.RefreshBonuses(player, PlayerDataService.Get(player))
end

local function paintPads(taken)
	for i, pad in ipairs(padParts) do
		if pad and pad.Parent then
			pad.Color = (taken and taken[i]) and TRACK_DARK or PAD_CYAN
		end
	end
end

-- THE ONE EXIT. Every way a run can end comes through here, which is what makes "the humanoid is
-- always given back" a property of the file rather than of six call sites remembering to.
local function endRun(player, reason, payload)
	local run = runs[player.UserId]
	if not run then return end
	runs[player.UserId] = nil

	local _, humanoid = humanoidOf(player)
	if humanoid then
		pcall(restoreProfile, player)
	end
	-- The pads are shared geometry, so they only go back to their unlit colour once NOBODY is
	-- running. Two racers at once would otherwise re-light each other's strips.
	if next(runs) == nil then
		paintPads(nil)
	end

	local msg = payload or {}
	msg.state = reason
	remote():FireClient(player, msg)
end

local function statusFor(player)
	local data = PlayerDataService.Get(player)
	return GameConfig.GetSprintStatus(data), data
end

local function insideBox(position)
	return position.X > START_X - BOX_BACK
		and position.X < FINISH_X + BOX_FORWARD
		and math.abs(position.Z - LANE_Z) < BOX_Z
		and position.Y < GROUND_Y + BOX_UP
end

local function applySpeed(run, humanoid)
	humanoid.UseJumpPower = true
	humanoid.JumpPower = GameConfig.SprintJumpPower
	humanoid.WalkSpeed = math.min(
		GameConfig.SprintBaseSpeed + run.pads * GameConfig.SprintPadStep,
		GameConfig.SprintMaxSpeed)
end

local function finish(player, run, seconds)
	local data = PlayerDataService.Get(player)
	if not data then
		endRun(player, "cancelled", { reason = "nodata" })
		return
	end

	local ledger = GameConfig.GetSprintLedger(data)
	local band = GameConfig.GetSprintBand(seconds)
	local shards = band.shards
	local firstEver = (ledger.Finishes or 0) == 0
	if firstEver then
		shards = shards + GameConfig.SprintFirstFinishShards
	end
	ledger.Finishes = (ledger.Finishes or 0) + 1

	local best = ledger.Best or 0
	local newBest = (best <= 0) or (seconds < best)
	if newBest then
		ledger.Best = seconds
	end

	data.EvolutionShards = (data.EvolutionShards or 0) + shards
	Telemetry.Economy(player, "Source", Telemetry.Currency.Shards, shards,
		data.EvolutionShards, Telemetry.Tx.Gameplay, "sprintTrack")
	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.PushToClient(player)

	if (not serverBest) or seconds < serverBest then
		serverBest = seconds
		serverBestName = player.DisplayName
		refreshArch()
	end

	endRun(player, "finished", {
		seconds = seconds,
		band = band.key,
		bandName = band.name,
		bandEmoji = band.emoji,
		bandColor = band.color,
		shards = shards,
		pads = run.pads,
		padTotal = PAD_COUNT,
		newBest = newBest,
		best = ledger.Best,
		firstEver = firstEver,
		runsLeft = math.max(GameConfig.SprintDailyRuns - (ledger.DayRuns or 0), 0),
	})

	if firstEver then
		notify(player, "reward", ("\u{1F3C3} First run home in %s!\n\u{1F31F} +%d Shards -- spend them on a Trail")
			:format(GameConfig.FormatSprintTime(seconds), shards))
	end
end

-- ONE Heartbeat for the whole feature, connected at Init and never per-run. It walks at most a
-- handful of live runs and does nothing at all when the table is empty, which is the shape the
-- streaming note asks for: one gated Heartbeat per set, not one per member.
local function step()
	for userId, run in pairs(runs) do
		local player = Players:GetPlayerByUserId(userId)
		if not player then
			runs[userId] = nil
		else
			local character, humanoid = humanoidOf(player)
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not (humanoid and root) or humanoid.Health <= 0 then
				endRun(player, "cancelled", { reason = "died" })
			elseif run.startClock == nil then
				-- still counting down; hold them on the line
				humanoid.WalkSpeed = 0
				humanoid.JumpPower = 0
			elseif os.clock() - run.startClock > GameConfig.SprintTimeout then
				endRun(player, "cancelled", { reason = "timeout" })
			elseif not insideBox(root.Position) then
				endRun(player, "cancelled", { reason = "left" })
			else
				local pos = root.Position
				for i = 1, PAD_COUNT do
					if not run.taken[i] then
						local at = padPosition(i)
						if math.abs(pos.X - at.X) <= PAD_REACH_X
							and math.abs(pos.Z - at.Z) <= PAD_REACH_Z then
							run.taken[i] = true
							run.pads += 1
							applySpeed(run, humanoid)
							local pad = padParts[i]
							if pad and pad.Parent then pad.Color = TRACK_DARK end
							remote():FireClient(player, {
								state = "pad",
								index = i,
								pads = run.pads,
								padTotal = PAD_COUNT,
								speed = humanoid.WalkSpeed,
								step = GameConfig.SprintPadStep,
							})
						end
					end
				end
				if pos.X >= FINISH_X then
					finish(player, run, os.clock() - run.startClock)
				end
			end
		end
	end
end

-- ============================================================================
-- STARTING ONE
-- ============================================================================
local lastStart = {}
local START_INTERVAL = 1.0

-- PUBLIC, and the prompt handler at the bottom is a one-line call to it. Every other door-driven
-- service in this game is shaped this way -- `MinigameService`, `ExpeditionService` and
-- `AdventureRemotes` all put the work behind a named function and leave the listener holding only
-- the routing -- and it is the shape that keeps "what a press does" readable without reading the
-- listener. It is also the only entry a probe can reach, which matters here more than usual: see
-- the row for the session the engine stopped offering prompts to its own client.
function SprintTrack.Begin(player)
	local now = os.clock()
	local last = lastStart[player.UserId]
	if last and now - last < START_INTERVAL then return end
	lastStart[player.UserId] = now

	if runs[player.UserId] then return end
	if not (trackModel and trackModel.Parent) then return end

	local character, humanoid = humanoidOf(player)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root) or humanoid.Health <= 0 then return end

	-- THE BODY HAS TO BE AT THE BLOCK. The prompt already enforces this for an honest client; this
	-- is the same check on the side that cannot be edited, and it is generous on purpose -- the
	-- prompt fires at 26 and a player who took two steps is not a cheat.
	if startPart and (root.Position - startPart.Position).Magnitude > PROMPT_DISTANCE * 2 then
		warn(("[SprintTrack] %s started from %.0f studs away")
			:format(player.Name, (root.Position - startPart.Position).Magnitude))
		return
	end

	local status, data = statusFor(player)
	if not data then return end
	if not status.ready then
		notify(player, "error", ("\u{1F3C3} That is all %d runs for today -- come back tomorrow!")
			:format(GameConfig.SprintDailyRuns))
		remote():FireClient(player, { state = "refused", reason = status.reason, status = status })
		return
	end

	-- SPENT HERE, at the start. See the note over `GetSprintStatus` for why a time trial in
	-- particular cannot bill at the finish.
	local ledger = GameConfig.GetSprintLedger(data)
	ledger.DayRuns += 1
	PlayerDataService.PushToClient(player)

	-- On the line, facing the finish, with the velocity killed. Velocity survives a CFrame write --
	-- `AdventureService`'s checkpoint respawn learned that the hard way -- and a runner arriving on
	-- the block still carrying their approach would be given a free head start.
	root.CFrame = startCFrame(root.Position.Y)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	local run = { pads = 0, taken = {}, startClock = nil }
	local wasEmpty = next(runs) == nil
	runs[player.UserId] = run
	-- Only when this is the ONLY run. The strips are shared world geometry, so relighting them for
	-- an arriving racer would wipe the state the one already out there is reading.
	if wasEmpty then paintPads(nil) end

	humanoid.UseJumpPower = true
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0

	remote():FireClient(player, {
		state = "countdown",
		seconds = GameConfig.SprintCountdown,
		padTotal = PAD_COUNT,
		best = ledger.Best or 0,
		serverBest = serverBest,
		serverBestName = serverBestName,
		runsLeft = math.max(GameConfig.SprintDailyRuns - ledger.DayRuns, 0),
	})

	task.delay(GameConfig.SprintCountdown, function()
		-- The run may already be gone: they died, walked off, or the track was rebuilt. Anything
		-- that is not still THIS run must not be handed a profile.
		if runs[player.UserId] ~= run then return end
		local _, h = humanoidOf(player)
		if not h or h.Health <= 0 then
			endRun(player, "cancelled", { reason = "died" })
			return
		end
		run.startClock = os.clock()
		applySpeed(run, h)
		remote():FireClient(player, { state = "go", padTotal = PAD_COUNT })
	end)
end

-- ============================================================================
-- INIT
-- ============================================================================
function SprintTrack.Init()
	build()
	remote()
	refreshArch()

	local ProximityPromptService = game:GetService("ProximityPromptService")
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if prompt.Name == "SprintPrompt" then
			SprintTrack.Begin(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		runs[player.UserId] = nil
		lastStart[player.UserId] = nil
		if next(runs) == nil then paintPads(nil) end
	end)

	-- A respawn is a cancelled run, and it has to be caught here as well as in `step`: a character
	-- that is replaced between two frames never reports Health <= 0 to us.
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			if runs[player.UserId] then
				endRun(player, "cancelled", { reason = "died" })
			end
		end)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(function()
			if runs[player.UserId] then
				endRun(player, "cancelled", { reason = "died" })
			end
		end)
	end

	if not heartbeat then
		heartbeat = RunService.Heartbeat:Connect(step)
	end
end

return SprintTrack
