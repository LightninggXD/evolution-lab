--[==[
	PartyStand -- the door into a party, and the board that shows the ones that exist (22.5).

	===== WHY A STAND IN THE WORLD AND NOT A HUD TILE =====

	Three reasons, in the order they decided it:

	  1. `MainUI` is at Luau's 200-local cap (`evolution-lab-mainui-register-limit`) -- one more
	     top-level local there deletes the whole HUD. A feature that can live outside it should.
	  2. A party is a thing you form with people who are STANDING WITH YOU, and this game already
	     has a place for that: 30.7's trading floor, the marked circle whose entire purpose is
	     "meet me here". The stand goes fifteen studs off its rim, so the plaza's social corner is
	     one place rather than two.
	  3. An agent can press a `ProximityPrompt` and cannot press a `BillboardGui`
	     (`evolution-lab-agent-cannot-click-billboards`), so a door built this way is a door this
	     project can actually test.

	===== WHERE =====

	(-88, 0, 278), measured on a booted server 2026-09-09: an 18 x 18 raycast grid comes back at
	y 0.00 on `WorldShell.Floor` at every sample with ZERO parts standing in a 20 x 24 x 20 box.
	Its neighbours, so a later session knows what it would be walking into: the trading floor's rim
	is a 58-stud disc centred (-132, 278), the trade sign stands at (-132, 312), and the jungle
	rocks that take everything north and west of the circle start about seven studs up.

	===== THE PROMPT HANGS ON AN ATTACHMENT AT HEAD HEIGHT =====

	`ProximityPromptService` only shows a prompt whose ANCHOR IS ON SCREEN, which is the other half
	of the rule nobody writes down (`roblox-a-prompt-off-screen-is-a-dead-prompt`): reach is
	necessary and not sufficient. The first cut parented it to the plinth, whose centre is 1.6 studs
	up -- ankle height on a body whose eyes are at 6 -- and it was measured dead from 14 studs with
	the follow camera sitting on top of the stand: `PlayerGui.ProximityPrompts` empty,
	`InputHoldBegin()` doing nothing at all. It is on an `Attachment` 6 studs over the plinth's own
	base now, the same `PROMPT_HEIGHT` `ExpeditionService.promptAnchor` and `ZoneBuilder.addPrompt`
	both use.

	===== ONE PROMPT, NOT TWO =====

	`ProximityPrompt.ActionText` is a property of the PART, so it says the same thing to everybody
	looking at it -- there is no per-player version of it. So this is one toggle rather than a
	"Join" and a "Leave" prompt standing next to each other: press it in a party and you leave,
	press it out of one and you join the smallest party with a free slot. What actually happened is
	said back through `Remotes.Notify`, which is per-player and can afford to be specific.
]==]

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local Remotes = RS.Remotes
local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local PartyService = require(script.Parent.PartyService)

local PartyStand = {}

-- Bumped whenever the geometry below changes, the same stamp shape as `PLAZA_VERSION`,
-- `TRACK_VERSION` and `STATION_VERSION`: an older number is destroyed and rebuilt.
local STAND_VERSION = 2
local MODEL_NAME = "PartyStand"

PartyStand.Centre = Vector3.new(-88, 0, 278)

local PROMPT_DISTANCE = 26
-- Studs above the plinth's BASE, not its centre -- measured from the host the way the expedition
-- doors' fix measures it. See the header.
local PROMPT_HEIGHT = 6
local BOARD_W, BOARD_H = 26, 17
local POST_H = 12
local ROW_COUNT = 4

local OUTLINE = Color3.fromRGB(26, 18, 36)
local STONE = Color3.fromRGB(150, 140, 132)
local ACCENT = Color3.fromRGB(96, 176, 255)

local state = { model = nil, board = nil, prompt = nil }

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

local function styleText(label, colour, align)
	label.BackgroundTransparency = 1
	label.Font = UITheme.Font.Display
	label.TextColor3 = colour or Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.TextStrokeColor3 = Color3.fromRGB(14, 10, 22)
	label.TextStrokeTransparency = 0.15
	label.TextXAlignment = align or Enum.TextXAlignment.Left
end

-- ============================================================================
-- BUILD
-- ============================================================================
-- The panel hangs on posts with NOTHING behind it, for the reason 22.4's board records: a
-- BillboardGui turns to face the camera and a slab does not, so any solid part the size of the
-- panel comes apart the moment you look at it off-axis.
local function build()
	local centre = PartyStand.Centre
	local model = Instance.new("Model")
	model.Name = MODEL_NAME
	model:SetAttribute("StandVersion", STAND_VERSION)

	-- A flush pad, stated by its top face and grown down to a buried bottom so it cannot share a
	-- plane with the lawn -- the rule `HubPlaza` and `SprintTrack` both write out.
	local padTop = 0.34
	newPart({
		Name = "StandPad", Size = Vector3.new(20, padTop + 1.2, 20),
		Position = Vector3.new(centre.X, padTop - (padTop + 1.2) * 0.5, centre.Z),
		Color = STONE, CanCollide = true, Parent = model,
	})

	local plinth = newPart({
		Name = "StandPlinth", Size = Vector3.new(7, 3.2, 7),
		Position = Vector3.new(centre.X, 1.6, centre.Z),
		Color = OUTLINE, CanCollide = true, Parent = model,
	})
	for _, dx in ipairs({ -6, 6 }) do
		newPart({
			Name = "BoardPost", Size = Vector3.new(1.6, POST_H, 1.6),
			Position = Vector3.new(centre.X + dx, POST_H * 0.5 + 3.2, centre.Z),
			Color = OUTLINE, CanCollide = true, Parent = model,
		})
	end
	newPart({
		Name = "BoardBar", Size = Vector3.new(BOARD_W + 3, 1.4, 1.4),
		Position = Vector3.new(centre.X, 3.2 + POST_H + BOARD_H + 0.7, centre.Z),
		Color = OUTLINE, CanCollide = false, Parent = model,
	})
	local anchor = newPart({
		Name = "BoardAnchor", Size = Vector3.new(2, 2, 2),
		Position = Vector3.new(centre.X, 3.2 + POST_H + BOARD_H * 0.5, centre.Z),
		Transparency = 1, CanCollide = false, CanQuery = false, Parent = model,
	})

	local gui = Instance.new("BillboardGui")
	gui.Name = "PartyBoard"
	gui.Size = UDim2.new(BOARD_W, 0, BOARD_H, 0) -- studs: the panel keeps its size at range
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = 320
	gui.Adornee = anchor
	gui.Parent = anchor

	local shell = Instance.new("Frame")
	shell.Name = "Shell"
	shell.Size = UDim2.fromScale(1, 1)
	shell.BackgroundColor3 = Color3.fromRGB(24, 22, 34)
	shell.BackgroundTransparency = 0.08
	shell.BorderSizePixel = 0
	shell.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = shell
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = ACCENT
	stroke.Parent = shell

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(0.94, 0.19)
	title.Position = UDim2.fromScale(0.03, 0.05)
	styleText(title, ACCENT, Enum.TextXAlignment.Center)
	title.Text = "\u{1F389} PARTY STAND"
	title.Parent = shell

	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.Size = UDim2.fromScale(0.94, 0.12)
	sub.Position = UDim2.fromScale(0.03, 0.25)
	styleText(sub, Color3.fromRGB(212, 208, 226), Enum.TextXAlignment.Center)
	sub.Text = ""
	sub.Parent = shell

	local rows = {}
	for i = 1, ROW_COUNT do
		local row = Instance.new("TextLabel")
		row.Name = "Row" .. i
		row.Size = UDim2.fromScale(0.7, 0.125)
		row.Position = UDim2.fromScale(0.03, 0.42 + (i - 1) * 0.135)
		styleText(row, Color3.fromRGB(240, 238, 250))
		row.Text = ""
		row.Parent = shell

		local pct = Instance.new("TextLabel")
		pct.Name = "Pct"
		pct.Size = UDim2.fromScale(0.4, 1)
		pct.Position = UDim2.fromScale(1.0, 0)
		styleText(pct, ACCENT, Enum.TextXAlignment.Right)
		pct.Text = ""
		pct.Parent = row

		rows[i] = { name = row, pct = pct }
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PartyPrompt"
	prompt.ActionText = "Join or leave a party"
	prompt.ObjectText = "Party Stand"
	prompt.HoldDuration = 0
	-- Written, not scaled: `MaxActivationDistance` is not geometry and `Model:ScaleTo` would not
	-- touch it. Nothing scales this model today.
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	-- On an Attachment at head height, never on the part: see the header. A `ProximityPrompt` may
	-- be parented to an Attachment, which is what makes this possible without moving the art.
	local promptAt = Instance.new("Attachment")
	promptAt.Name = "PromptAnchor"
	promptAt.Position = Vector3.new(0, PROMPT_HEIGHT - plinth.Size.Y * 0.5, 0)
	promptAt.Parent = plinth
	prompt.Parent = promptAt

	model.Parent = workspace
	-- Persistent for the reason the plaza and the track are: it stands in the arrival zone and a
	-- door that streams out is a door that is not there.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	return { model = model, prompt = prompt, board = {
		shell = shell, title = title, sub = sub, rows = rows,
	} }
end

-- ============================================================================
-- THE BOARD
-- ============================================================================
local function draw()
	local board = state.board
	if not board then return end
	local parties = PartyService.All()

	if #parties == 0 then
		board.sub.Text = ("nobody has started one -- press E  (+%d%% each, up to %d)"):format(
			GameConfig.PartyBonusPct, GameConfig.PartyBonusCap)
	else
		board.sub.Text = ("+%d%% DNA per party member within %d studs"):format(
			GameConfig.PartyBonusPct, GameConfig.PartyRadiusStuds)
	end

	for i, row in ipairs(board.rows) do
		local party = parties[i]
		if party then
			row.name.Text = ("%s  %d/%d"):format(party.name, #party.members, GameConfig.PartySize)
			row.name.TextColor3 = party.colour
			-- What the party is WORTH to a member standing with all of them, which is the number
			-- somebody deciding whether to press the prompt actually wants.
			row.pct.Text = ("+%d%%"):format(GameConfig.GetPartyBonusPct(#party.members - 1))
			row.pct.TextColor3 = party.colour
		else
			row.name.Text = ""
			row.pct.Text = ""
		end
	end
	if #parties > ROW_COUNT then
		board.rows[ROW_COUNT].name.Text = ("... and %d more"):format(#parties - ROW_COUNT + 1)
		board.rows[ROW_COUNT].pct.Text = ""
	end
end

-- ============================================================================
-- INIT
-- ============================================================================
function PartyStand.Init()
	local existing = workspace:FindFirstChild(MODEL_NAME)
	if existing then existing:Destroy() end
	-- Idempotent BY REPLACEMENT rather than by skipping, for the reason `SprintTrack` gives: a
	-- half-built stand from an interrupted run would otherwise survive behind an "already there".
	state = build()

	state.prompt.Triggered:Connect(function(player)
		local party = PartyService.GetParty(player.UserId)
		if party then
			PartyService.Leave(player)
			Remotes.Notify:FireClient(player, {
				kind = "party",
				message = ("You left %s"):format(party.name),
			})
		else
			local joined, created = PartyService.Join(player)
			Remotes.Notify:FireClient(player, {
				-- Its own toast kind (see the branch in `MainUI`): `reward` would group these with
				-- every cash register in the game, and the grouping key is the kind plus the body.
				kind = "party",
				message = created
					and ("Party started -- bring people to it! +%d%% DNA each"):format(GameConfig.PartyBonusPct)
					or ("You joined %s (%d/%d)"):format(joined.name, #joined.members, GameConfig.PartySize),
			})
		end
		draw()
	end)

	print(("[PartyStand] built v%d at %d, %d, %d -- party of %d, +%d%% a member within %d studs"):format(
		STAND_VERSION, PartyStand.Centre.X, PartyStand.Centre.Y, PartyStand.Centre.Z,
		GameConfig.PartySize, GameConfig.PartyBonusPct, GameConfig.PartyRadiusStuds))

	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(draw)
			if not ok then warn("[PartyStand] draw failed: " .. tostring(err)) end
		end
	end)
end

PartyStand.Version = STAND_VERSION

return PartyStand
