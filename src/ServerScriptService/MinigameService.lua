-- MinigameService -- the arcade terminal that stands in every zone, and the one place a minigame
-- run is paid for (Phase 28).
--
-- =====================================================================================
-- WHAT IS HERE AND WHAT IS NOT
-- =====================================================================================
-- The GAMES are not here. All four are drawn and played in `StarterPlayerScripts.MinigameUI`,
-- because all four are screen games -- see the long note at the top of `GameConfig.Minigames` for
-- why a world arena was the wrong shape for a body that is 45 studs across at stage 20.
--
-- This file owns three things and nothing else:
--   * the terminal, one per zone, built once and stamped with its own version;
--   * the session -- who is playing what, since when -- which is the only reason the score coming
--     back over a remote can be judged at all;
--   * the payout, which is the ONE place `data.DNA` is credited for a minigame.
--
-- =====================================================================================
-- THE PLAY IS SPENT AT START, NOT AT FINISH
-- =====================================================================================
-- Deliberate, and the alternative is worse: bill on finish and a player can open a terminal, see a
-- bad first board, walk away and open it again, for ever. The cooldown would then only ever punish
-- somebody who played to the end. The cost of this choice is that a disconnect mid-run costs a play,
-- which is one of twelve a day and cannot be farmed in either direction.
--
-- =====================================================================================
-- WHAT THE SERVER ACTUALLY KNOWS ABOUT A SCORE, STATED PLAINLY
-- =====================================================================================
-- It is a screen game. The score arrives over a remote and this service cannot re-simulate the run,
-- so the score is BOUNDED, not proven:
--   * `GameConfig.ClampMinigameScore` caps it at what the game can physically produce;
--   * a run that comes back faster than `kind.minSeconds` is refused;
--   * a finish with no live session, or for a session that has expired, is refused;
--   * and the terminal has to be within reach of the body when the run STARTS, so a run cannot be
--     opened from across the map.
-- Past that, the ceiling is the cooldown and the daily cap: the very best a forged score can win is
-- the same twelve runs an honest player is given. That is the whole security model and it is sized
-- against what a minigame pays, which is about a day-6 login for a full day of play.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local ZoneKit = require(script.Parent.ZoneKit)

local newPart, addLight = ZoneKit.newPart, ZoneKit.addLight

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local MinigameService = {}

-- Rebuilt by replacement rather than patched in place, the rule `SplicerService` states: a stamped
-- model whose version has moved is not the same machine, and reconciling it piece by piece is how
-- half-old geometry survives. Bump this when the terminal's SHAPE changes.
local TERMINAL_VERSION = 3

-- ===== HOW BIG, AND THE RULE THAT DECIDES IT =====
--
-- `reach > structure half-width + player half-width`, the same sum that had to be written into
-- `CombatClient` for bosses and into `SplicerService` for the Splicer. A stage-20 body is a
-- 45 x 42 x 35 stud box, so its half-width is ~22 studs, and a machine authored at human scale is
-- one the player cannot see over and whose prompt can never fire. The cabinet below is 30 studs
-- across and the prompt is 70, which clears 15 + 22 with room for the player to be standing on the
-- far side of their own pet.
local CAB_W, CAB_H, CAB_D = 30, 34, 16
local PROMPT_DISTANCE = 70

-- Where a terminal stands, in ZONE-LOCAL coordinates (x is offset from the zone centre, z is the
-- world z the whole strip shares). Every zone is the same 1250 x 1150 platform, so one local
-- position is twenty world positions.
--
-- BESIDE THE ARRIVAL PAD ON PURPOSE. `ZonePad` is at local (0, 490) and is where every player
-- entering a zone lands, so a terminal at (-96, 452) is in the first thing they look at. A feature
-- nobody can find is a feature nobody plays, and the twenty terminals are the whole discovery
-- surface for this system -- there is no HUD tile.
--
-- The list is candidates, not a position: the first one nothing is standing on wins. Zones are
-- decorated by a scatter pass that does not know this exists, so a fixed point would eventually
-- land a terminal inside a tree.
local SPOTS = {
	Vector2.new(-96, 452),
	Vector2.new(96, 452),
	Vector2.new(-150, 408),
	Vector2.new(150, 408),
	Vector2.new(-96, 360),
}

-- ===== THE SESSION =====
-- userId -> { kind, zoneKey, startedAt, token }. In memory only: a run does not survive a rejoin,
-- and it must not -- the whole point of `startedAt` is that this server watched the clock.
local sessions = {}
local nextToken = 0

-- Rate limit on the START remote. The finish remote needs none: it is answered only against a live
-- session and it clears that session, so it is self-limiting.
local lastStart = {}
local START_INTERVAL = 0.5

local terminals = {} -- zoneKey -> Model

-- ===== THE TERMINAL =====
--
-- An arcade cabinet: a plinth, a body, a raked screen with the game's name painted on it, and a
-- light in the zone's own accent so it reads at a distance from the pad. Built out of `ZoneKit`
-- parts like every other structure in the world, so it inherits the shadow and collision policy
-- rather than restating it.
local function buildTerminal(zone, kind, centre)
	local model = Instance.new("Model")
	model.Name = "MinigameTerminal_" .. zone.key
	model:SetAttribute("TerminalVersion", TERMINAL_VERSION)
	model:SetAttribute("ZoneKey", zone.key)

	local accent = zone.accentColor or Color3.fromRGB(80, 200, 255)
	local shell = Color3.fromRGB(38, 34, 54)

	local plinth = newPart({
		Name = "Plinth",
		Size = Vector3.new(CAB_W + 8, 3, CAB_D + 8),
		Position = centre + Vector3.new(0, 1.5, 0),
		Color = shell,
		Material = Enum.Material.Metal,
		Parent = model,
	})

	local body = newPart({
		Name = "Cabinet",
		Size = Vector3.new(CAB_W, CAB_H, CAB_D),
		Position = centre + Vector3.new(0, 3 + CAB_H / 2, 0),
		Color = shell,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})

	-- The raked screen. Tilted back 20 degrees so it faces a player standing at the pad rather than
	-- the sky, and it is the part the name is painted on.
	local screen = newPart({
		Name = "Screen",
		Size = Vector3.new(CAB_W - 6, 18, 1.6),
		CFrame = CFrame.new(centre + Vector3.new(0, 3 + CAB_H - 6, CAB_D / 2 - 1.4))
			* CFrame.Angles(math.rad(-20), 0, 0),
		Color = accent,
		Material = Enum.Material.Neon,
		Parent = model,
	})
	addLight(screen, accent, 46, 2.4)

	-- The name and the game, on a BillboardGui rather than painted on the face: the terminal is read
	-- from the pad, 40+ studs away and at an angle, and a SurfaceGui at that distance is a smear.
	local sign = Instance.new("BillboardGui")
	sign.Name = "TerminalSign"
	sign.Size = UDim2.new(0, 260, 0, 92)
	-- THE SIGN SAT 68 STUDS IN THE SKY AND NOBODY SAW IT (measured 2026-08-21, by capture).
	-- `ExtentsOffsetWorldSpace` was copied here from 21.1, where it is correct: the thing it hangs
	-- over there is a PLAYER, whose body runs 1x to 9x across the twenty stages, so an offset that
	-- scales with the adornee is the only one that works at both ends. A cabinet is authored geometry
	-- and never changes size, so that reason does not apply -- and the copy brought the trap with
	-- it: the unit is HALF the adornee's extent, so `4` is not 4 studs, it is 4 x 17 = 68, which
	-- put the sign in the open sky beside the terminal it names. A fixed prop wants a plain stud
	-- value, where the number in the source is the number on the screen.
	sign.StudsOffsetWorldSpace = Vector3.new(0, 26, 0)
	sign.MaxDistance = 260
	sign.LightInfluence = 0
	sign.AlwaysOnTop = false
	sign.Adornee = body
	sign.Parent = body

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0.56, 0)
	title.Font = ZoneKit.SIGN_FONT
	title.Text = kind.emoji .. " " .. kind.name
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextScaled = true
	title.Parent = sign
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Thickness = 3
	titleStroke.Color = ZoneKit.SIGN_INK
	titleStroke.Parent = title

	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Size = UDim2.new(1, 0, 0.44, 0)
	sub.Position = UDim2.new(0, 0, 0.56, 0)
	sub.Font = ZoneKit.SIGN_FONT
	sub.Text = "ARCADE"
	sub.TextColor3 = accent
	sub.TextScaled = true
	sub.Parent = sign
	local subStroke = Instance.new("UIStroke")
	subStroke.Thickness = 3
	subStroke.Color = ZoneKit.SIGN_INK
	subStroke.Parent = sub

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "MinigamePrompt"
	prompt.ActionText = "Play " .. kind.name
	prompt.ObjectText = "Arcade Terminal"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	-- The attribute contract SplicerUI opens on: the client listens to ONE
	-- `ProximityPromptService.PromptTriggered` and decides from the attribute whose panel this is.
	-- A remote round trip to open a panel the client already has every number for would be a
	-- quarter-second of nothing.
	prompt:SetAttribute("ShopPanel", "minigame")
	prompt:SetAttribute("ZoneKey", zone.key)
	prompt.Parent = body

	model.PrimaryPart = body
	return model
end

-- ===== HOW TALL A THING ACTUALLY IS, WHICH IS NOT `part.Size.Y` (measured 2026-08-21) =====
--
-- `Size` is in the part's OWN axes, and the first version of this search read `Size.Y > 4` as
-- "something is standing here". It reported every authored spot in fourteen of the twenty zones as
-- occupied, and the thing occupying them was **the ground**: `GroundPatch` is a disc laid flat, so
-- its 0.4-stud thickness is its local X and its 77-stud diameter is its local Y. Size.Y said 77;
-- its real top is 0.9 studs above the floor.
--
-- The world-space half-height is the size projected onto world Y through the part's own axes, which
-- is the same arithmetic an axis-aligned bounding box is built from. A rotated part is then measured
-- as what it looks like rather than as what it was authored as.
local function worldTop(part)
	local cf, size = part.CFrame, part.Size
	local halfY = 0.5 * (math.abs(cf.RightVector.Y) * size.X
		+ math.abs(cf.UpVector.Y) * size.Y
		+ math.abs(cf.LookVector.Y) * size.Z)
	return part.Position.Y + halfY
end

-- Ground nothing is standing on. The same idea as `SplicerService.findClearSpot` and deliberately
-- much smaller: that machine searches rings because it must land on ONE specific plaza, while this
-- one has five authored candidates in a corner of the platform the decor pass rarely reaches. If
-- all five are taken the first is used anyway -- a terminal clipping a bush is worth more than a
-- zone with no terminal, and it says so in the console.
local function findSpot(zone)
	local base = Vector3.new(zone.offset, 0, 0)
	local probe = Vector3.new(CAB_W + 14, 40, CAB_D + 14)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { workspace:FindFirstChild("Terrain") }

	for index, spot in ipairs(SPOTS) do
		local centre = base + Vector3.new(spot.X, 0, spot.Y)
		local hits = workspace:GetPartBoundsInBox(CFrame.new(centre + Vector3.new(0, 20, 0)), probe, params)
		local blocked = false
		for _, part in ipairs(hits) do
			-- UNANCHORED IS NEVER AN OBSTACLE, and that is not a shortcut: everything unanchored on
			-- this ground is a creature, a pet or a player, all of which walk away. A terminal placed
			-- once at world-build time must not be positioned by where a Critter happened to stand.
			-- Four studs of clearance covers the floor, the plaza deck, a kerb and a buried patch,
			-- and rejects a lamp post (23), a ruin pillar (26) and a tree.
			if part.Anchored and worldTop(part) > 4 then
				blocked = true
				break
			end
		end
		if not blocked then
			return centre, index
		end
	end

	warn(("[MinigameService] every authored spot in %s was occupied; using the first anyway")
		:format(zone.key))
	return base + Vector3.new(SPOTS[1].X, 0, SPOTS[1].Y), 1
end

-- ===== STARTING A RUN =====
function MinigameService.HandleStart(player, zoneKey)
	local PlayerDataService = require(script.Parent.PlayerDataService)

	if type(zoneKey) ~= "string" then return end

	local now = os.clock()
	local last = lastStart[player.UserId]
	if last and now - last < START_INTERVAL then return end
	lastStart[player.UserId] = now

	local data = PlayerDataService.Get(player)
	if not data then return end

	local kind = GameConfig.GetMinigame(zoneKey)
	if not kind then return end

	-- THE BODY HAS TO BE AT THE TERMINAL. The prompt already enforces this for an honest client;
	-- this is the same check on the side that cannot be edited. Generous on purpose -- the prompt
	-- fires at 70 and a player who took two steps while the panel opened is not a cheat.
	local terminal = terminals[zoneKey]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not terminal or not root then return end
	if (root.Position - terminal.PrimaryPart.Position).Magnitude > PROMPT_DISTANCE * 2 then
		warn(("[MinigameService] %s started %s from %.0f studs away")
			:format(player.Name, zoneKey, (root.Position - terminal.PrimaryPart.Position).Magnitude))
		return
	end

	local status = GameConfig.GetMinigameStatus(data, zoneKey)
	if not status.ready then
		-- The WORDING is the server's here rather than the panel's, because the panel is not open
		-- yet -- this refusal is what stops it opening. Through the ordinary Notify stack so it
		-- queues, ranks and sounds like every other refusal in the game.
		local message
		if status.reason == "capped" then
			message = ("\u{1F3AE} That is all %d arcade runs for today -- come back tomorrow!")
				:format(GameConfig.MinigameDailyPlays)
		else
			message = ("\u{23F3} This terminal is cooling down -- %s left")
				:format(GameConfig.FormatDuration(status.secondsLeft))
		end
		Remotes.Notify:FireClient(player, { kind = "error", message = message })
		Remotes.MinigameSession:FireClient(player, { ok = false, reason = status.reason, status = status })
		return
	end

	-- SPENT HERE. See the header note on why this is the start and not the finish.
	local ledger = GameConfig.GetMinigameLedger(data)
	ledger.DayPlays += 1
	-- `os.time()`, not `GameConfig.UtcTimestamp()` -- that one is a spec converter, see the note in
	-- `GameConfig.MinigameDayNumber`. This is a wall-clock stamp the cooldown is measured from, and
	-- it is deliberately NOT `os.clock()`: a cooldown has to survive the player leaving the server.
	ledger.Plays[zoneKey] = os.time()
	PlayerDataService.PushToClient(player)

	nextToken += 1
	sessions[player.UserId] = {
		token = nextToken,
		kind = kind,
		zoneKey = zoneKey,
		startedAt = os.clock(),
	}

	local Telemetry = require(script.Parent.Telemetry)
	Telemetry.Custom(player, "MinigameStarted", 1)

	Remotes.MinigameSession:FireClient(player, {
		ok = true,
		token = nextToken,
		kindKey = kind.key,
		zoneKey = zoneKey,
		-- The seed is the client's, not a shared random stream: nothing about a board layout is
		-- worth hiding, and a client that draws its own board cannot desync from a server that is
		-- not drawing one.
		seed = math.random(1, 2 ^ 30),
	})
end

-- ===== FINISHING A RUN =====
function MinigameService.HandleFinish(player, payload)
	local PlayerDataService = require(script.Parent.PlayerDataService)

	if type(payload) ~= "table" then return end

	local session = sessions[player.UserId]
	if not session then return end
	if payload.token ~= session.token then return end
	sessions[player.UserId] = nil

	local data = PlayerDataService.Get(player)
	if not data then return end

	local kind = session.kind
	local elapsed = os.clock() - session.startedAt

	-- Too fast to be a run of this game at all. No reward, no toast beyond the refusal -- and the
	-- play is already spent, which is the part that makes retrying pointless.
	if elapsed < kind.minSeconds then
		warn(("[MinigameService] %s returned %s after %.1fs (floor %ds)")
			:format(player.Name, kind.key, elapsed, kind.minSeconds))
		Remotes.MinigameResult:FireClient(player, { ok = false, reason = "tooFast" })
		return
	end

	-- Expired. A panel left open while the player went to make tea is not a score.
	if elapsed > kind.seconds + 60 then
		Remotes.MinigameResult:FireClient(player, { ok = false, reason = "expired" })
		return
	end

	local reward = GameConfig.GetMinigameReward(kind, payload.score, data)
	local ledger = GameConfig.GetMinigameLedger(data)

	local Telemetry = require(script.Parent.Telemetry)

	data.DNA = (data.DNA or 0) + reward.dna
	Telemetry.Economy(player, "Source", Telemetry.Currency.DNA, reward.dna, data.DNA,
		Telemetry.Tx.Gameplay, "minigame_" .. kind.key)

	local diamonds = 0
	if reward.beatPar and ledger.DayDiamonds < GameConfig.MinigameDailyDiamonds then
		diamonds = 1
		ledger.DayDiamonds += 1
		data.Diamonds = (data.Diamonds or 0) + diamonds
		Telemetry.Economy(player, "Source", Telemetry.Currency.Diamonds, diamonds, data.Diamonds,
			Telemetry.Tx.Gameplay, "minigame_" .. kind.key)
	end

	local previousBest = ledger.Best[kind.key] or 0
	local isBest = reward.score > previousBest
	if isBest then
		ledger.Best[kind.key] = reward.score
	end

	Telemetry.Custom(player, "MinigameFinished", reward.score)
	PlayerDataService.PushToClient(player)

	Remotes.MinigameResult:FireClient(player, {
		ok = true,
		kindKey = kind.key,
		score = reward.score,
		par = kind.par,
		beatPar = reward.beatPar,
		best = ledger.Best[kind.key],
		newBest = isBest,
		dna = reward.dna,
		diamonds = diamonds,
		-- What the terminal will say the moment the panel closes, quoted from the same function the
		-- panel reads -- so the cooldown the player sees is the one that was just written.
		status = GameConfig.GetMinigameStatus(data, session.zoneKey),
	})
end

function MinigameService.Init()
	for _, name in ipairs({ "MinigameStart", "MinigameSession", "MinigameFinish", "MinigameResult" }) do
		if not Remotes:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = Remotes
		end
	end

	local map = workspace:FindFirstChild("Map")
	if not map then
		map = Instance.new("Folder")
		map.Name = "Map"
		map.Parent = workspace
	end

	-- UNDER `Map`, NOT UNDER THE ZONE MODEL, and that is the whole reason this builds its own
	-- furniture instead of going through `ZoneBuilder`: a zone stamped `Complete = true` is skipped
	-- on every boot and only rebuilds on a `BUILD_VERSION` bump, which drops ~105k parts. A terminal
	-- parented into the zone would therefore need that bump to ever change. Here it is stamped and
	-- rebuilt on its own version, exactly as the Splicer and the Colosseum are.
	local folder = map:FindFirstChild("MinigameTerminals")
	if folder and folder:GetAttribute("TerminalVersion") ~= TERMINAL_VERSION then
		folder:Destroy()
		folder = nil
	end
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "MinigameTerminals"
		folder:SetAttribute("TerminalVersion", TERMINAL_VERSION)
		folder.Parent = map
	end

	local built = 0
	for _, zone in ipairs(GameConfig.Zones) do
		local kind = GameConfig.GetMinigame(zone.key)
		if kind then
			local existing = folder:FindFirstChild("MinigameTerminal_" .. zone.key)
			if not existing then
				local centre = findSpot(zone)
				existing = buildTerminal(zone, kind, centre)
				existing.Parent = folder
				built += 1
			end
			-- Never streamed out: a terminal is a landmark and a player who walked to it must find
			-- it there, not arriving a second later. Same call the Splicer makes, same reason.
			existing.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
			terminals[zone.key] = existing
		end
	end
	if built > 0 then
		print(("[MinigameService] built %d arcade terminals (v%d)"):format(built, TERMINAL_VERSION))
	end

	Remotes.MinigameStart.OnServerEvent:Connect(function(player, zoneKey)
		local ok, err = pcall(MinigameService.HandleStart, player, zoneKey)
		if not ok then
			warn("[MinigameService] start failed for " .. player.Name .. ": " .. tostring(err))
		end
	end)

	Remotes.MinigameFinish.OnServerEvent:Connect(function(player, payload)
		local ok, err = pcall(MinigameService.HandleFinish, player, payload)
		if not ok then
			warn("[MinigameService] finish failed for " .. player.Name .. ": " .. tostring(err))
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		sessions[player.UserId] = nil
		lastStart[player.UserId] = nil
	end)
end

return MinigameService
