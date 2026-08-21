-- ExpeditionService -- the door into an Expedition, the run itself, and the one place a run is paid.
--
-- =====================================================================================
-- WHAT IS HERE AND WHAT IS NOT
-- =====================================================================================
-- The GAMES are not here, and neither is the map. The three stations play the Phase 28 arcade games
-- unchanged, drawn by `StarterPlayerScripts.MinigameUI`; the four chambers are built by
-- `ExpeditionMap`. This file owns exactly three things:
--   * the entrance in the Forest hub, and the travel in and out;
--   * the RUN -- who is where, which seals they hold, what they have scored -- which is the only
--     reason a score arriving over a remote can be judged at all;
--   * the payout, which is the ONE place an expedition credits anything.
--
-- =====================================================================================
-- THE MAP IS SHARED AND THE RUN IS NOT, AND THE DOOR IS WHERE THAT COSTS SOMETHING
-- =====================================================================================
-- There is no instancing in this game (see the long note in `GameConfig.Expeditions`), so two
-- players can stand in chamber 2 at the same time holding different seals. Everything in this file
-- is keyed on `userId`, so progress never mixes. The one thing that cannot be per-player on the
-- server is the sealed door: it is one part, and a part is either solid or it is not.
--
-- **So the server never moves it.** It builds the door solid and leaves it alone for ever. A client
-- told it holds all three seals sets `CanCollide = false` on its OWN copy and fades it -- which
-- works because an anchored part's collision against your character is resolved on your machine,
-- where you own that character's physics. Nothing replicates; the player beside you still walks
-- into a wall.
--
-- **Stated plainly, in the register Phase 28 used: an exploiter can walk through that door.** It
-- gains them nothing. `HandleOpenChest` below re-checks the seals on the server, so the far chamber
-- is an empty room to anybody who has not earned it. This is bounded, not proven, and the bound is
-- the run itself.
--
-- =====================================================================================
-- THE RUN IS SPENT AT THE DOOR, NOT AT THE CHEST
-- =====================================================================================
-- The same decision the arcade makes, for the same reason: bill on completion and a player enters,
-- sees a station they dislike, walks out and re-enters for ever. The cost is that a disconnect
-- mid-run costs a run -- one of two a day, farmable in neither direction.
--
-- Which is also why **dying ends the run and keeps the DNA**: the stations have already paid for
-- themselves the moment they were cleared, and what is forfeited is the completion bonus and the
-- chest. That is what makes the last chamber worth walking into, and it needs no code at all --
-- `ZoneService.ReturnToCurrentZone` is wired to `CharacterAdded` and ejects the new body to the
-- player's real zone, because entering an expedition deliberately never changed `CurrentZone`.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local ZoneKit = require(script.Parent.ZoneKit)
local ExpeditionMap = require(script.Parent.ExpeditionMap)

local newPart, addLight = ZoneKit.newPart, ZoneKit.addLight

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Find-or-create rather than a plain index. `CombatFx` and `AutoAttack` belong to the combat
-- services and are created at THEIR require time, so whether they exist when this file loads is a
-- fact about `ServerMain`'s ordering -- which is a thing that gets re-ordered. Both sides land on
-- the same instance whichever runs first, and an unconnected RemoteEvent does nothing.
local function ensureRemote(name)
	local existing = Remotes:FindFirstChild(name)
	if existing then return existing end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = Remotes
	return remote
end

local CombatFx = ensureRemote("CombatFx")
local AutoAttack = ensureRemote("AutoAttack")

local ExpeditionService = {}

local ENTRANCE_VERSION = 2

-- `reach > structure half-width + player half-width` -- the rule `CombatClient` carries for bosses
-- and `SplicerService` had to be rescued by on 2026-08-17. A stage-20 body is ~22 studs of half
-- width; these structures are 30-40 across. 70 clears both with room to spare.
local PROMPT_DISTANCE = 70

-- =====================================================================================
-- THE CORE, AND WHY IT IS NOT A BOSS
-- =====================================================================================
-- `BossService` is 3,062 lines. `spawnBoss` is private and derives its position from `zone.offset`,
-- `spawnEventBoss` is a private template with a hardcoded one, and the kill block does about a dozen
-- things -- including writing `data.DefeatedBosses`, which `zone.requiresBossKey` reads to decide
-- whether a player may walk into the next zone. Generalising the largest file in the project to
-- stand something in a chamber 2,300 studs off the strip, two weeks before launch, is the single
-- riskiest thing available; and doing it would put an expedition kill into the array that gates the
-- map. So the Core is built here, it is about 130 lines, and it reaches nothing.
--
-- WHAT IT REUSES INSTEAD -- AND WHY THERE IS NO NEW CLIENT INPUT CODE FOR IT.
-- `CombatClient` already fights anything that is a Model in `workspace.Bosses` carrying a `Health`
-- attribute above zero and a `PrimaryPart` (that is its auto-attack picker), and it already plays a
-- swing at anything in that folder the mouse is pointing at (that is its raycast). A creature
-- reaches the server by two doors -- a `ClickDetector` on the body for the click, the `AutoAttack`
-- remote for the loop -- and both land in one function. The Core is built the same way and both of
-- its doors land in `strikeCore`. Nothing on the client had to learn what an expedition is.
--
-- ===== THE `Health` ATTRIBUTE IS A TARGETING FLAG, NOT THE HEALTH =====
-- The map is shared and the run is not (see the header), so the Core's real health is per-run --
-- `run.coreHp`, on the server -- and two players in the last chamber are each fighting their own. An
-- attribute is ONE replicated number and cannot say that. So it is written once, as 1, and means
-- only "this is a thing you may swing at", which is the only thing the client reads it for. What the
-- player SEES is the `CombatFx {k = "bossBar"}` payload, which is `FireClient` and therefore already
-- per-player -- row 29.7 named it for exactly that reason.
--
-- The client's own reach for a boss is `CombatClient.AUTO_REACH.Bosses` = 70, and the two must stay
-- in step: a server gate looser than the client's own picker accepts blows an honest client can
-- never nominate, which is the difference between slack and a hole. The slack below is for the body
-- moving between the frame that nominated the target and the frame the remote lands on.
local CORE_REACH = 70
local CORE_SLACK = 30
-- A little under `CombatClient.AUTO_INTERVAL` (0.34), so a client running exactly at the interval is
-- never refused for arriving one frame early. It is a floor on the fight's length either way: 120
-- swings cannot be delivered faster than 120 x this.
local CORE_STRIKE_INTERVAL = 0.27
local CORE_SIZE = 34
local CORE_VERSION = 2
-- The pulse. 15 Hz rather than every frame because nothing here moves far enough in 16 ms for the
-- difference to be visible, and 6% either side of full size because a Core that throbs hard reads as
-- a thing about to explode -- it stands there unbreakable for most of the run.
local PULSE_STEP = 1 / 15
local PULSE_RATE = 1.6
local PULSE_DEPTH = 0.06

-- Where the door stands in the Forest hub. Beside the arrival pad at (0, 490) and out along the same
-- row as the arcade terminal, because that pad is where every player entering Forest lands and this
-- feature has no HUD tile -- the door IS the discovery surface.
local ENTRANCE_SPOT = Vector3.new(210, 0, 440)

-- ===== THE RUN =====
-- userId -> { key, expedition, startedAt, symbols = {i -> true}, scores = {i -> n}, total,
--             station = {token, index, kind, startedAt} | nil,
--             coreHp, coreMax, coreDown, lastStrike }
-- In memory only, and it must be: a run does not survive a rejoin, and the whole point of
-- `startedAt` is that THIS server watched the clock.
local runs = {}
local nextToken = 0

local lastEnter = {}
local ENTER_INTERVAL = 1.0

local entrance = nil
local maps = {} -- expeditionKey -> Model
-- expeditionKey -> Model, and these live in `workspace.Bosses` rather than in the map, because
-- `CombatClient`'s picker walks that folder's DIRECT children. See the note above PROMPT_DISTANCE.
local cores = {}

-- ============================================================================
-- WORLD
-- ============================================================================
local function buildEntrance(expedition)
	local model = Instance.new("Model")
	model.Name = "ExpeditionDoor"
	model:SetAttribute("EntranceVersion", ENTRANCE_VERSION)

	local accent = expedition.core and expedition.core.color or Color3.fromRGB(120, 235, 150)
	local shell = Color3.fromRGB(46, 40, 64)

	local plinth = newPart({
		Name = "Plinth",
		Size = Vector3.new(48, 3, 20),
		Position = ENTRANCE_SPOT + Vector3.new(0, 1.5, 0),
		Color = shell,
		Material = Enum.Material.Metal,
		Parent = model,
	})

	-- Two posts and a lintel: a doorway rather than a cabinet, so it does not read as a second
	-- arcade terminal standing next to the first one.
	for _, side in ipairs({ -1, 1 }) do
		newPart({
			Name = "DoorPost",
			Size = Vector3.new(6, 44, 8),
			Position = ENTRANCE_SPOT + Vector3.new(side * 19, 25, 0),
			Color = shell,
			Material = Enum.Material.Metal,
			Parent = model,
		})
	end

	local lintel = newPart({
		Name = "DoorLintel",
		Size = Vector3.new(48, 8, 8),
		Position = ENTRANCE_SPOT + Vector3.new(0, 51, 0),
		Color = shell,
		Material = Enum.Material.Metal,
		Parent = model,
	})

	local veil = newPart({
		Name = "DoorVeil",
		Size = Vector3.new(32, 42, 2),
		Position = ENTRANCE_SPOT + Vector3.new(0, 24, 0),
		Color = accent,
		Material = Enum.Material.Neon,
		Transparency = 0.4,
		CanCollide = false,
		Parent = model,
	})
	addLight(veil, accent, 70, 2.6)

	-- A BillboardGui rather than paint on the lintel: this is read from the arrival pad 60 studs
	-- away and at an angle, where a SurfaceGui is a smear. Same call the arcade terminals make.
	local sign = Instance.new("BillboardGui")
	sign.Name = "EntranceSign"
	sign.Size = UDim2.new(0, 280, 0, 96)
	-- THE SIGN SAT 68 STUDS IN THE SKY AND NOBODY SAW IT (measured 2026-08-21, by capture).
	-- `ExtentsOffsetWorldSpace` was copied here from 21.1, where it is correct: the thing it hangs
	-- over there is a PLAYER, whose body runs 1x to 9x across the twenty stages, so an offset that
	-- scales with the adornee is the only one that works at both ends. A door lintel is authored geometry
	-- and never changes size, so that reason does not apply -- and the copy brought the trap with
	-- it: the unit is HALF the adornee's extent, so `4` is not 4 studs, it is 4 x 4 = 16, which
	-- put the sign in the open sky beside the terminal it names. A fixed prop wants a plain stud
	-- value, where the number in the source is the number on the screen.
	sign.StudsOffsetWorldSpace = Vector3.new(0, 13, 0)
	sign.MaxDistance = 300
	sign.LightInfluence = 0
	sign.AlwaysOnTop = false
	sign.Adornee = lintel
	sign.Parent = lintel

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0.58, 0)
	title.Font = ZoneKit.SIGN_FONT
	title.Text = expedition.emoji .. " " .. expedition.name
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextScaled = true
	title.Parent = sign
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Thickness = 3
	titleStroke.Color = ZoneKit.SIGN_INK
	titleStroke.Parent = title

	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Size = UDim2.new(1, 0, 0.42, 0)
	sub.Position = UDim2.new(0, 0, 0.58, 0)
	sub.Font = ZoneKit.SIGN_FONT
	sub.Text = "EXPEDITION"
	sub.TextColor3 = accent
	sub.TextScaled = true
	sub.Parent = sign
	local subStroke = Instance.new("UIStroke")
	subStroke.Thickness = 3
	subStroke.Color = ZoneKit.SIGN_INK
	subStroke.Parent = sub

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ExpeditionPrompt"
	prompt.ActionText = "Expedition"
	prompt.ObjectText = expedition.name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	-- The attribute contract SplicerUI established and the arcade reused: the client decides from
	-- the attribute whose panel this is. A remote round trip to open a panel the client already has
	-- every number for would be a quarter second of nothing.
	prompt:SetAttribute("ShopPanel", "expedition")
	prompt:SetAttribute("ExpeditionKey", expedition.key)
	prompt.Parent = veil

	model.PrimaryPart = plinth
	return model
end

local function buildStationTerminal(map, expedition, index)
	local station = expedition.stations[index]
	local kind = GameConfig.GetStationKind(expedition, index)
	if not kind then return nil end

	local centre = ExpeditionMap.GetStationPosition(index)
	local model = Instance.new("Model")
	model.Name = "Station" .. index
	model:SetAttribute("StationIndex", index)

	local body = newPart({
		Name = "StationBody",
		Size = Vector3.new(16, 34, 30),
		Position = centre + Vector3.new(0, 17, 0),
		Color = Color3.fromRGB(38, 34, 54),
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})

	local face = newPart({
		Name = "StationFace",
		Size = Vector3.new(1.6, 18, 24),
		Position = centre + Vector3.new(8, 24, 0),
		Color = station.color,
		Material = Enum.Material.Neon,
		Parent = model,
	})
	addLight(face, station.color, 50, 2.4)

	local sign = Instance.new("BillboardGui")
	sign.Name = "StationSign"
	sign.Size = UDim2.new(0, 240, 0, 88)
	-- A stud value for the same reason the entrance sign above uses one: the station body is
	-- authored geometry, and `ExtentsOffsetWorldSpace` counts in HALF-extents (17 here), so the
	-- 4 this was written with meant 68 studs.
	sign.StudsOffsetWorldSpace = Vector3.new(0, 26, 0)
	sign.MaxDistance = 260
	sign.LightInfluence = 0
	sign.Adornee = body
	sign.Parent = body

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0.58, 0)
	title.Font = ZoneKit.SIGN_FONT
	title.Text = station.symbol .. " " .. kind.name
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextScaled = true
	title.Parent = sign
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = ZoneKit.SIGN_INK
	stroke.Parent = title

	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Size = UDim2.new(1, 0, 0.42, 0)
	sub.Position = UDim2.new(0, 0, 0.58, 0)
	sub.Font = ZoneKit.SIGN_FONT
	sub.Text = station.symbolName
	sub.TextColor3 = station.color
	sub.TextScaled = true
	sub.Parent = sign
	local subStroke = Instance.new("UIStroke")
	subStroke.Thickness = 3
	subStroke.Color = ZoneKit.SIGN_INK
	subStroke.Parent = sub

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StationPrompt"
	prompt.ActionText = "Play " .. kind.name
	prompt.ObjectText = station.symbolName
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("ShopPanel", "expedition_station")
	prompt:SetAttribute("StationIndex", index)
	prompt.Parent = body

	model.PrimaryPart = body
	model.Parent = map
	return model
end

local function buildVaultChest(map, expedition)
	local chamber = ExpeditionMap.GetChamberCentre(#expedition.stations + 1)
	local accent = expedition.core and expedition.core.color or Color3.fromRGB(120, 235, 150)

	local model = Instance.new("Model")
	model.Name = "VaultChest"

	local base = newPart({
		Name = "ChestBase",
		Size = Vector3.new(40, 26, 30),
		Position = chamber + Vector3.new(0, 13, 40),
		Color = Color3.fromRGB(58, 48, 74),
		Material = Enum.Material.Metal,
		Parent = model,
	})

	local lid = newPart({
		Name = "ChestLid",
		Size = Vector3.new(42, 8, 32),
		Position = chamber + Vector3.new(0, 30, 40),
		Color = accent,
		Material = Enum.Material.Neon,
		Parent = model,
	})
	addLight(lid, accent, 80, 3)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ChestPrompt"
	prompt.ActionText = "Open the vault"
	prompt.ObjectText = "Expedition Cache"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("ShopPanel", "expedition_chest")
	prompt.Parent = base

	model.PrimaryPart = base
	model.Parent = map
	return model
end

-- The Core stands opposite the vault chest in the last chamber -- the chest is at +40 on Z from the
-- chamber centre, this is at -60 -- so walking in puts both in frame and the room reads as a fight
-- with a prize behind it rather than as a corridor with a button.
local function buildCore(expedition)
	local chamber = ExpeditionMap.GetChamberCentre(#expedition.stations + 1)
	local core = expedition.core or {}
	local accent = core.color or Color3.fromRGB(190, 130, 255)

	local model = Instance.new("Model")
	model.Name = "ExpeditionCore_" .. expedition.key
	model:SetAttribute("ExpeditionKey", expedition.key)
	model:SetAttribute("CoreVersion", CORE_VERSION)
	-- ONE, for ever. This is the targeting flag, not the health -- see the note above CORE_REACH.
	model:SetAttribute("Health", 1)

	newPart({
		Name = "CorePlinth",
		Size = Vector3.new(52, 6, 52),
		Position = chamber + Vector3.new(0, 3, -60),
		Color = Color3.fromRGB(38, 34, 54),
		Material = Enum.Material.Metal,
		Parent = model,
	})

	-- ===== THE BODY IS PAINTED DARKER THAN THE ACCENT, AND THAT IS NOT A TYPO =====
	-- Neon ignores the scene's lighting and emits its Color at full strength, so a light colour on a
	-- Neon part has nowhere left to go: photographed at the authored accent (190,130,255, whose blue
	-- channel is already maxed) the Core rendered as a WHITE ball with a purple halo -- the halo was
	-- the only thing carrying the colour, and the object itself read as a bug. A PointLight at
	-- Brightness 4 sitting INSIDE it finished the job. The two levers move together: paint the body
	-- a third of the way to black so the emission has somewhere to sit, and let the light describe
	-- the room rather than the sphere. Re-photographed: a solid magenta orb on its plinth.
	local body = newPart({
		Name = "Body",
		Size = Vector3.new(CORE_SIZE, CORE_SIZE, CORE_SIZE),
		Position = chamber + Vector3.new(0, 6 + CORE_SIZE * 0.5, -60),
		Color = accent:Lerp(Color3.new(0, 0, 0), 0.34),
		Material = Enum.Material.Neon,
		Parent = model,
	})
	-- A Block with a Sphere `SpecialMesh`, never `Shape = Ball`: a non-uniform Ball is silently drawn
	-- as a sphere of its SMALLEST axis, so only a cube reads correctly and anything else lies about
	-- its own size. This one is uniform, and it is written this way so it stays right if it is not.
	-- The mesh is also what the pulse below scales -- Size would drag the collision box with it.
	local mesh = Instance.new("SpecialMesh")
	mesh.Name = "CoreMesh"
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = body
	addLight(body, accent, 90, 2)

	local sign = Instance.new("BillboardGui")
	sign.Name = "CoreSign"
	sign.Size = UDim2.new(0, 260, 0, 88)
	-- A STUD offset, not `ExtentsOffsetWorldSpace`. That unit is HALF the adornee's extent, which is
	-- how every sign in Phases 28 and 29 ended up 68 studs into the sky (29.10). The body's top is at
	-- 40; 26 from its centre puts the sign's own centre about 9 studs clear of it, which is what a
	-- two-line sign needs or its second line is drawn behind the prop.
	sign.StudsOffsetWorldSpace = Vector3.new(0, 26, 0)
	sign.MaxDistance = 300
	sign.LightInfluence = 0
	sign.Adornee = body
	sign.Parent = body

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0.58, 0)
	title.Font = ZoneKit.SIGN_FONT
	title.Text = (core.emoji or "") .. " " .. (core.name or "Core")
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextScaled = true
	title.Parent = sign
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = ZoneKit.SIGN_INK
	stroke.Parent = title

	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Size = UDim2.new(1, 0, 0.42, 0)
	sub.Position = UDim2.new(0, 0, 0.58, 0)
	sub.Font = ZoneKit.SIGN_FONT
	sub.Text = "Break it to open the vault"
	sub.TextColor3 = accent
	sub.TextScaled = true
	sub.Parent = sign
	local subStroke = Instance.new("UIStroke")
	subStroke.Thickness = 3
	subStroke.Color = ZoneKit.SIGN_INK
	subStroke.Parent = sub

	-- The click half of the two doors. `MaxActivationDistance` is the client's own boss reach, so a
	-- click and the auto-attack loop are held to the same range on the way in, and to the same gate
	-- on the way out.
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = CORE_REACH
	click.Parent = body

	model.PrimaryPart = body
	return model
end

-- ============================================================================
-- STATE
-- ============================================================================
-- What the client is told about a live run. One shape, pushed on every change, so the HUD never has
-- to work anything out from a delta -- the same reason `PlayerDataService.PushToClient` sends the
-- whole payload rather than a diff.
local function statePayload(run)
	if not run then
		return { running = false }
	end
	local symbols = {}
	local scores = {}
	for index in ipairs(run.expedition.stations) do
		symbols[index] = run.symbols[index] == true
		scores[index] = run.scores[index] or 0
	end
	return {
		running = true,
		key = run.key,
		symbols = symbols,
		scores = scores,
		total = run.total,
		stations = #run.expedition.stations,
		par = GameConfig.GetExpeditionPar(run.expedition),
		-- The client dissolves the sealed door off this one boolean. It is computed here rather
		-- than counted there so the server stays the only thing that decides what "all of them"
		-- means -- a station added to the route later needs no client change.
		sealed = run.sealsHeld >= #run.expedition.stations,
		-- The client fades and stops targeting its OWN copy of the Core off this one boolean -- the
		-- same trick as the sealed door and for the same reason: one model, two players, different
		-- progress. The server never touches the Core after it builds it.
		coreDown = run.coreDown == true,
	}
end

local function pushState(player)
	Remotes.ExpeditionState:FireClient(player, statePayload(runs[player.UserId]))
end

local function endRun(player, reason)
	local run = runs[player.UserId]
	if not run then return end
	runs[player.UserId] = nil
	if player.Parent then
		pushState(player)
	end
	return run, reason
end

-- ============================================================================
-- ENTERING
-- ============================================================================
function ExpeditionService.HandleEnter(player, key)
	local PlayerDataService = require(script.Parent.PlayerDataService)
	local ZoneService = require(script.Parent.ZoneService)

	if type(key) ~= "string" then return end

	local now = os.clock()
	local last = lastEnter[player.UserId]
	if last and now - last < ENTER_INTERVAL then return end
	lastEnter[player.UserId] = now

	local data = PlayerDataService.Get(player)
	if not data then return end

	local expedition = GameConfig.GetExpedition(key)
	if not expedition or not maps[key] then return end

	-- Already inside. Not an error and not worth a toast -- the panel simply re-reads itself.
	if runs[player.UserId] then
		pushState(player)
		return
	end

	local status = GameConfig.GetExpeditionStatus(data, key)
	if not status.ready then
		-- The WORDING is the server's here rather than the panel's, because the refusal is what
		-- stops the panel acting. Through the ordinary Notify stack so it queues, ranks and sounds
		-- like every other refusal in the game.
		local message
		if status.reason == "capped" then
			message = ("\u{1F5FA} That is both expeditions for today -- come back tomorrow!")
		elseif status.reason == "stage" then
			message = ("\u{1F512} %s opens at stage %d.")
				:format(expedition.name, expedition.minStageIndex or 1)
		else
			message = "That expedition is not available."
		end
		Remotes.Notify:FireClient(player, { kind = "error", message = message })
		Remotes.ExpeditionState:FireClient(player, { running = false, refused = status.reason })
		return
	end

	-- SPENT HERE. See the header note on why this is the door and not the chest.
	local ledger = GameConfig.GetExpeditionLedger(data)
	ledger.DayRuns += 1
	PlayerDataService.PushToClient(player)

	runs[player.UserId] = {
		key = key,
		expedition = expedition,
		startedAt = os.clock(),
		symbols = {},
		scores = {},
		sealsHeld = 0,
		total = 0,
		station = nil,
		-- `coreMax` is nil until the first blow lands: the Core is priced against the damage of the
		-- player who is standing in front of it, not against the player who walked in four minutes
		-- ago. A potion drunk in chamber 2 therefore counts toward the fight it was drunk for.
		coreHp = nil,
		coreMax = nil,
		coreDown = false,
		lastStrike = nil,
	}

	local Telemetry = require(script.Parent.Telemetry)
	Telemetry.Custom(player, "ExpeditionStarted", 1)

	ZoneService.SendToExpedition(player, ExpeditionMap.GetSpawnCFrame(), {
		name = expedition.name,
		emoji = expedition.emoji,
		color = expedition.core and expedition.core.color or Color3.fromRGB(120, 235, 150),
	})
	pushState(player)
end

function ExpeditionService.HandleLeave(player)
	local ZoneService = require(script.Parent.ZoneService)
	endRun(player, "left")
	ZoneService.SendHomeFromExpedition(player)
end

-- ============================================================================
-- STATIONS
-- ============================================================================
function ExpeditionService.HandleStationStart(player, index)
	local PlayerDataService = require(script.Parent.PlayerDataService)

	index = tonumber(index)
	if not index then return end

	local run = runs[player.UserId]
	if not run then return end

	local data = PlayerDataService.Get(player)
	if not data then return end

	local station = run.expedition.stations[index]
	local kind = GameConfig.GetStationKind(run.expedition, index)
	if not station or not kind then return end

	-- Already cleared. A seal is taken once; replaying for a better score would make the run's total
	-- a grind rather than a result, and the daily cap is sized against one pass.
	if run.symbols[index] then
		Remotes.Notify:FireClient(player, {
			kind = "error",
			message = ("\u{2705} %s is already sealed."):format(station.symbolName),
		})
		return
	end

	-- One station at a time. Without this a client could open three and submit the best.
	if run.station then
		-- ...but a station that can no longer be banked is not a station any more. `run.station` is
		-- cleared by a finish and by nothing else, so a client that never submits -- a disconnect
		-- mid-game, a panel that was closed by something other than itself -- used to lock the rest
		-- of the expedition out IN SILENCE: every later prompt returned here and the player was
		-- given no reason. The window is the same one `HandleStationFinish` refuses on, so nothing
		-- is ever released that the other end could still bank.
		if os.clock() - run.station.startedAt <= run.station.kind.seconds + 60 then
			return
		end
		warn(("[ExpeditionService] %s abandoned station %d; releasing it")
			:format(player.Name, run.station.index))
		run.station = nil
	end

	-- THE BODY HAS TO BE AT THE STATION. The prompt already enforces this for an honest client;
	-- this is the same check on the side that cannot be edited. Generous on purpose -- the prompt
	-- fires at 70 and a player who took two steps while the panel opened is not a cheat.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local terminal = ExpeditionMap.GetStationPosition(index)
	if (root.Position - terminal).Magnitude > PROMPT_DISTANCE * 2 then
		warn(("[ExpeditionService] %s started station %d from %.0f studs away")
			:format(player.Name, index, (root.Position - terminal).Magnitude))
		return
	end

	nextToken += 1
	run.station = {
		token = nextToken,
		index = index,
		kind = kind,
		startedAt = os.clock(),
	}

	Remotes.ExpeditionStation:FireClient(player, {
		ok = true,
		token = nextToken,
		kindKey = kind.key,
		-- The seam that lets `MinigameUI` play this run without knowing anything about expeditions:
		-- it submits to `StationFinish` instead of `MinigameFinish` on the strength of this word.
		channel = "expedition",
		stationIndex = index,
		symbol = station.symbol,
		symbolName = station.symbolName,
		seed = math.random(1, 2 ^ 30),
	})
end

function ExpeditionService.HandleStationFinish(player, payload)
	local PlayerDataService = require(script.Parent.PlayerDataService)

	if type(payload) ~= "table" then return end

	local run = runs[player.UserId]
	if not run or not run.station then return end
	if payload.token ~= run.station.token then return end

	local station = run.station
	run.station = nil

	local data = PlayerDataService.Get(player)
	if not data then return end

	local kind = station.kind
	local elapsed = os.clock() - station.startedAt

	-- Too fast to be a run of this game at all. The seal is NOT given and the station stays open --
	-- unlike the arcade, where the play is already spent, here the run's own clock is the cost.
	if elapsed < kind.minSeconds then
		warn(("[ExpeditionService] %s returned station %d after %.1fs (floor %ds)")
			:format(player.Name, station.index, elapsed, kind.minSeconds))
		Remotes.ExpeditionStation:FireClient(player, { ok = false, reason = "tooFast" })
		return
	end
	if elapsed > kind.seconds + 60 then
		Remotes.ExpeditionStation:FireClient(player, { ok = false, reason = "expired" })
		return
	end

	-- The arcade's own curve, quoted rather than copied -- a station and a terminal pay identically
	-- for identical play, which is what makes this feel like the same game.
	local reward = GameConfig.GetStationReward(run.expedition, station.index, payload.score, data)

	run.symbols[station.index] = true
	run.sealsHeld += 1
	run.scores[station.index] = reward.score
	run.total += reward.score

	local Telemetry = require(script.Parent.Telemetry)
	data.DNA = (data.DNA or 0) + reward.dna
	Telemetry.Economy(player, "Source", Telemetry.Currency.DNA, reward.dna, data.DNA,
		Telemetry.Tx.Gameplay, "expedition_" .. kind.key)
	Telemetry.Custom(player, "ExpeditionStationCleared", reward.score)

	PlayerDataService.PushToClient(player)

	local def = run.expedition.stations[station.index]
	Remotes.ExpeditionStation:FireClient(player, {
		ok = true,
		finished = true,
		stationIndex = station.index,
		kindKey = kind.key,
		score = reward.score,
		par = kind.par,
		beatPar = reward.beatPar,
		dna = reward.dna,
		symbol = def.symbol,
		symbolName = def.symbolName,
	})
	pushState(player)
end

-- ============================================================================
-- THE CORE
-- ============================================================================
-- Both doors -- the `ClickDetector` on the body and the `AutoAttack` remote -- land here, so the
-- cooldown, the reach, the bar and the death are identical whether the player clicked or the loop
-- did. That is the shape `CreatureService` uses for exactly the same pair, and the reason it uses
-- it: two entry points with two copies of the rules is two sets of rules.
function ExpeditionService.HandleCoreStrike(player, model)
	if typeof(model) ~= "Instance" then return end

	local run = runs[player.UserId]
	if not run then return end
	-- The model must be the Core of the expedition THIS player is running. Not merely a Core: a
	-- second expedition adds a second one, and hitting the wrong map's would otherwise count.
	if cores[run.key] ~= model then return end
	if run.coreDown then return end

	-- Nobody reaches this room without the seals except somebody who walked through a door their own
	-- client dissolved for them. Silent rather than a toast: they know what they did, and a refusal
	-- message fired at 3 Hz is worse than nothing.
	if run.sealsHeld < #run.expedition.stations then return end

	local now = os.clock()
	if run.lastStrike and now - run.lastStrike < CORE_STRIKE_INTERVAL then return end

	local body = model.PrimaryPart
	if not body or not body.Parent then return end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	if (root.Position - body.Position).Magnitude > CORE_REACH + CORE_SLACK then return end

	local PlayerDataService = require(script.Parent.PlayerDataService)
	local DNAService = require(script.Parent.DNAService)
	local data = PlayerDataService.Get(player)
	if not data then return end

	run.lastStrike = now

	-- The one damage number the whole game swings with -- pets, passes, rebirths, potions and the
	-- evolution ladder are all already inside it. Floored at 1 so a save that somehow reports zero
	-- damage cannot make the Core immortal.
	local damage = math.max(DNAService.GetCombatDamage(data), 1)
	if not run.coreMax then
		run.coreMax = damage * GameConfig.ExpeditionCoreHits
		run.coreHp = run.coreMax
	end

	run.coreHp = math.max((run.coreHp or 0) - damage, 0)

	local core = run.expedition.core or {}
	local coreName = ((core.emoji or "") .. " " .. (core.name or "Core")):gsub("^%s+", "")
	CombatFx:FireClient(player, {
		k = "bossBar",
		name = coreName,
		hp = run.coreHp,
		max = run.coreMax,
	})

	if run.coreHp > 0 then return end

	run.coreDown = true

	-- Authored in stage-1 clicks and paid through `ScaleReward`, like every other number in this
	-- feature: the Core is worth the same count of kills at stage 1 and at stage 20.
	local reward = GameConfig.ScaleReward(GameConfig.ExpeditionCoreClicks, data)
	local Telemetry = require(script.Parent.Telemetry)
	data.DNA = (data.DNA or 0) + reward
	Telemetry.Economy(player, "Source", Telemetry.Currency.DNA, reward, data.DNA,
		Telemetry.Tx.Gameplay, "expedition_core_" .. run.key)
	Telemetry.Custom(player, "ExpeditionCoreKilled", 1)
	PlayerDataService.PushToClient(player)

	Remotes.Notify:FireClient(player, {
		kind = "success",
		message = ("\u{1F4A5} %s destroyed -- the vault is open!"):format(core.name or "The Core"),
	})
	pushState(player)
end

-- ============================================================================
-- THE VAULT
-- ============================================================================
function ExpeditionService.HandleOpenChest(player)
	local PlayerDataService = require(script.Parent.PlayerDataService)
	local RelicService = require(script.Parent.RelicService)

	local run = runs[player.UserId]
	if not run then return end

	local data = PlayerDataService.Get(player)
	if not data then return end

	-- THE SEALS ARE RE-CHECKED HERE, ON THE SERVER, and this line is the entire reason the sealed
	-- door is allowed to be a client-side illusion. Walking through it early lands you in a room
	-- with a chest that refuses you.
	local needed = #run.expedition.stations
	if run.sealsHeld < needed then
		Remotes.Notify:FireClient(player, {
			kind = "error",
			message = ("\u{1F510} The vault needs all %d seals -- you have %d.")
				:format(needed, run.sealsHeld),
		})
		return
	end

	-- ...AND SO IS THE CORE, for the same reason and in the same place. The seals get you into the
	-- room; the fight is what the room is for. Checked here rather than only being drawn as a locked
	-- prompt, because a prompt is a client and a client is not a proof.
	if not run.coreDown then
		local core = run.expedition.core or {}
		Remotes.Notify:FireClient(player, {
			kind = "error",
			message = ("\u{1F6D1} %s is still standing."):format(core.name or "The Core"),
		})
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local chamber = ExpeditionMap.GetChamberCentre(needed + 1)
	if (root.Position - (chamber + Vector3.new(0, 13, 40))).Magnitude > PROMPT_DISTANCE * 2 then
		return
	end

	local finish = GameConfig.GetExpeditionFinishReward(run.expedition, run.total, data)
	local ledger = GameConfig.GetExpeditionLedger(data)
	local Telemetry = require(script.Parent.Telemetry)

	RelicService.GiveChest(player, finish.chests)

	if finish.diamonds > 0 then
		data.Diamonds = (data.Diamonds or 0) + finish.diamonds
		Telemetry.Economy(player, "Source", Telemetry.Currency.Diamonds, finish.diamonds,
			data.Diamonds, Telemetry.Tx.Gameplay, "expedition_" .. run.key)
	end

	local previousBest = ledger.Best[run.key] or 0
	local isBest = run.total > previousBest
	if isBest then
		ledger.Best[run.key] = run.total
	end
	ledger.Cleared[run.key] = (ledger.Cleared[run.key] or 0) + 1

	Telemetry.Custom(player, "ExpeditionCleared", run.total)
	PlayerDataService.PushToClient(player)

	local total = run.total
	local key = run.key
	endRun(player, "cleared")

	Remotes.ExpeditionResult:FireClient(player, {
		ok = true,
		key = key,
		total = total,
		par = finish.par,
		beatPar = finish.beatPar,
		best = ledger.Best[key],
		newBest = isBest,
		chests = finish.chests,
		diamonds = finish.diamonds,
		cleared = ledger.Cleared[key],
		runsLeft = math.max(GameConfig.ExpeditionDailyRuns - ledger.DayRuns, 0),
	})
end

-- ============================================================================
function ExpeditionService.Init()
	for _, name in ipairs({
		"ExpeditionEnter", "ExpeditionState", "ExpeditionLeave", "ExpeditionChest",
		"StationStart", "ExpeditionStation", "StationFinish", "ExpeditionResult",
	}) do
		if not Remotes:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = Remotes
		end
	end

	-- INTO `workspace.Zones`, and that is load-bearing rather than tidy: `ZoneService.Init` scans
	-- that folder ONCE at startup for parts named `PortalGate` and wires their Touched handlers.
	-- A map built anywhere else -- or built after that scan -- has an exit gate that does nothing.
	-- This is why `ExpeditionService.Init()` is called BEFORE `ZoneService.Init()` in `ServerMain`.
	local zonesFolder = workspace:FindFirstChild("Zones")
	if not zonesFolder then
		warn("[ExpeditionService] workspace.Zones does not exist -- ZoneBuilder.Build() must run first")
		return
	end

	for _, expedition in ipairs(GameConfig.ExpeditionList) do
		local map = ExpeditionMap.EnsureBuilt(zonesFolder, expedition)
		maps[expedition.key] = map
		if not map:FindFirstChild("Station1") then
			for index in ipairs(expedition.stations) do
				buildStationTerminal(map, expedition, index)
			end
			buildVaultChest(map, expedition)
		end
	end

	local map = workspace:FindFirstChild("Map")
	if not map then
		map = Instance.new("Folder")
		map.Name = "Map"
		map.Parent = workspace
	end

	-- Rebuilt by replacement rather than patched in place: a stamped model whose version has moved
	-- is not the same structure, and reconciling it piece by piece is how half-old geometry lives on.
	local existing = map:FindFirstChild("ExpeditionDoor")
	if existing and existing:GetAttribute("EntranceVersion") ~= ENTRANCE_VERSION then
		existing:Destroy()
		existing = nil
	end
	if not existing then
		existing = buildEntrance(GameConfig.ExpeditionList[1])
		existing.Parent = map
	end
	entrance = existing
	-- Never streamed out: the door is a landmark and a player who walked to it must find it there.
	entrance.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	Remotes.ExpeditionEnter.OnServerEvent:Connect(function(player, key)
		local ok, err = pcall(ExpeditionService.HandleEnter, player, key)
		if not ok then
			warn("[ExpeditionService] enter failed for " .. player.Name .. ": " .. tostring(err))
		end
	end)

	Remotes.ExpeditionLeave.OnServerEvent:Connect(function(player)
		local ok, err = pcall(ExpeditionService.HandleLeave, player)
		if not ok then
			warn("[ExpeditionService] leave failed for " .. player.Name .. ": " .. tostring(err))
		end
	end)

	Remotes.StationStart.OnServerEvent:Connect(function(player, index)
		local ok, err = pcall(ExpeditionService.HandleStationStart, player, index)
		if not ok then
			warn("[ExpeditionService] station start failed for " .. player.Name .. ": " .. tostring(err))
		end
	end)

	Remotes.StationFinish.OnServerEvent:Connect(function(player, payload)
		local ok, err = pcall(ExpeditionService.HandleStationFinish, player, payload)
		if not ok then
			warn("[ExpeditionService] station finish failed for " .. player.Name .. ": " .. tostring(err))
		end
	end)

	Remotes.ExpeditionChest.OnServerEvent:Connect(function(player)
		local ok, err = pcall(ExpeditionService.HandleOpenChest, player)
		if not ok then
			warn("[ExpeditionService] chest failed for " .. player.Name .. ": " .. tostring(err))
		end
	end)

	-- A run is server memory and the body is somewhere it cannot stay. Dying already ejects the
	-- player (see the header); this drops the run that body was in, so a respawn inside the map is
	-- never a half-run with a live token.
	Players.PlayerAdded:Connect(function(player)
		player.CharacterRemoving:Connect(function()
			endRun(player, "died")
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		runs[player.UserId] = nil
		lastEnter[player.UserId] = nil
	end)
end

-- ============================================================================
-- THE CORES -- A SECOND ENTRY POINT, AND WHY IT HAS TO BE ONE
-- ============================================================================
-- `BossService.Init` opens by destroying EVERY child of `workspace.Bosses` (BossService.lua:2943),
-- which is correct for it -- a rebuild must not leave the previous run's rigs standing -- and fatal
-- for anything else that has already put a model there. `ExpeditionService.Init` runs at
-- ServerMain:92 and `BossService.Init` at :104, so a Core built in Init is created, parented, made
-- Persistent, wired to its ClickDetector... and then silently deleted twelve lines later. Measured:
-- the folder held 20 bosses and no Cores, with no warning in the log, because nothing had failed.
--
-- The ordering constraint on `Init` cannot move to fix this: it must stay ahead of `ZoneService.Init`,
-- which scans `workspace.Zones` for `PortalGate` exactly once (see the note there). So the Cores get
-- their own call, made AFTER `BossService.Init`, and BossService is not touched -- generalising its
-- wipe to spare a foreign model would put expedition knowledge into the largest file in the project
-- for no gain.
--
-- ===== AND WHY THEY GO IN THAT FOLDER AT ALL, GIVEN THE ABOVE =====
-- `CombatClient`'s auto-attack picker walks the DIRECT children of the folders named in its own
-- `AUTO_REACH` table -- `Creatures` and `Bosses`, nothing else -- and its swing raycast filters on
-- the same two. A Core parented into the chamber model, or into a folder of its own, would be
-- invisible to both, and this whole fight would need a client that knows what an expedition is.
-- Sharing the folder is what buys that, and the price is this second call.
function ExpeditionService.BuildCores()
	-- Found-or-created rather than indexed: it belongs to `BossService` and this must not depend on
	-- which of the two ran first, only on this having run second.
	local bossesFolder = workspace:FindFirstChild("Bosses")
	if not bossesFolder then
		bossesFolder = Instance.new("Folder")
		bossesFolder.Name = "Bosses"
		bossesFolder.Parent = workspace
	end

	for _, expedition in ipairs(GameConfig.ExpeditionList) do
		-- Rebuilt by replacement on a version bump, like the entrance and the map: a stamped model
		-- whose version has moved is not the same structure, and reconciling it part by part is how
		-- half-old geometry survives.
		local existingCore = bossesFolder:FindFirstChild("ExpeditionCore_" .. expedition.key)
		if existingCore and existingCore:GetAttribute("CoreVersion") ~= CORE_VERSION then
			existingCore:Destroy()
			existingCore = nil
		end
		if not existingCore then
			existingCore = buildCore(expedition)
			existingCore.Parent = bossesFolder
		end
		-- Two parts, and they must be there the moment a player walks into the last chamber 2,300
		-- studs off the strip -- the same call the map and the entrance make.
		existingCore.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		cores[expedition.key] = existingCore

		local click = existingCore.PrimaryPart
			and existingCore.PrimaryPart:FindFirstChildOfClass("ClickDetector")
		if click then
			-- Wrapped rather than connected straight through, for the reason `CreatureService` wraps
			-- its own: `MouseClick`'s signature is (player), and connecting a two-argument handler to
			-- it would leave `model` nil.
			click.MouseClick:Connect(function(who)
				local ok, err = pcall(ExpeditionService.HandleCoreStrike, who, existingCore)
				if not ok then
					warn("[ExpeditionService] core click failed: " .. tostring(err))
				end
			end)
		else
			warn("[ExpeditionService] core for " .. expedition.key .. " has no ClickDetector")
		end
	end

	-- The auto-attack half. `CreatureService` and `BossService` both listen on this same remote and
	-- both answer only for models in their own handler table; this one answers only for a model in
	-- `cores`, so the three never see each other's.
	AutoAttack.OnServerEvent:Connect(function(player, model)
		local ok, err = pcall(ExpeditionService.HandleCoreStrike, player, model)
		if not ok then
			warn("[ExpeditionService] core strike failed for " .. player.Name .. ": " .. tostring(err))
		end
	end)

	-- ===== ONE HEARTBEAT FOR EVERY CORE IN THE GAME =====
	-- Not one per Core. The standing rule for this project is a single gated Heartbeat per animated
	-- SET, because the cost of an animation here is the number of connections, not the number of
	-- things moved -- and this set grows by one with every expedition added.
	--
	-- The gate is the two lines at the top: this loop is stepping a handful of meshes 15 times a
	-- second in a room 2,300 studs off the strip that is empty for almost the whole life of a
	-- server. `runs` is empty exactly then, so the work is skipped without even walking `cores`.
	local pulseAt = 0
	local pulsing = false
	RunService.Heartbeat:Connect(function()
		if next(runs) == nil then
			-- A GATE THAT ONLY SKIPS WORK LEAVES THE LAST FRAME ON SCREEN. Whatever scale the wave
			-- happened to be at when the last player left is what the Core keeps until somebody
			-- enters again -- a sphere frozen 6% off its authored size, for the rest of the server's
			-- life. One flag and one settle pass, run once on the way down rather than every frame.
			if pulsing then
				pulsing = false
				for _, core in pairs(cores) do
					local body = core.PrimaryPart
					local mesh = body and body:FindFirstChild("CoreMesh")
					if mesh then mesh.Scale = Vector3.new(1, 1, 1) end
					local light = body and body:FindFirstChildOfClass("PointLight")
					if light then light.Brightness = 2 end
				end
			end
			return
		end
		local now = os.clock()
		if now - pulseAt < PULSE_STEP then return end
		pulseAt = now
		pulsing = true

		-- Slow, shallow and in one direction: a Core that throbs hard reads as a thing about to go
		-- off, and this one stands there for the whole run before anybody is allowed to touch it.
		local wave = 1 + math.sin(now * PULSE_RATE) * PULSE_DEPTH
		for _, core in pairs(cores) do
			local body = core.PrimaryPart
			local mesh = body and body:FindFirstChild("CoreMesh")
			if mesh then
				mesh.Scale = Vector3.new(wave, wave, wave)
			end
			local light = body and body:FindFirstChildOfClass("PointLight")
			if light then
				light.Brightness = 2 * wave
			end
		end
	end)

	print(("[ExpeditionService] %d core%s standing in workspace.Bosses (v%d)")
		:format(#GameConfig.ExpeditionList, #GameConfig.ExpeditionList == 1 and "" or "s", CORE_VERSION))
end

return ExpeditionService
