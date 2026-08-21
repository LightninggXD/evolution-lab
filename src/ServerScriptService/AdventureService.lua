-- AdventureService -- who is on a course, where their last checkpoint was, and the one Heartbeat
-- that moves every platform in the feature.
--
-- 30.3 SCOPE, AND WHAT IS DELIBERATELY NOT HERE YET. This file owns the COURSE: building it on
-- demand, wiring its pads, catching a fall, and getting a player in and out. It owns none of the
-- economy -- no daily run is spent, no relic is rolled, no par bonus is paid, and there is NO
-- RemoteEvent. 30.4 adds the billing and the payout, 30.5 the dispatch, 30.6 the panel.
--
-- **The missing remote is the point, not an omission.** An entry that costs nothing and pays
-- nothing is harmless; an entry wired to the client before it is billed is a free faucet, and this
-- game has shipped one of those before. `HandleEnter` is a server function until 30.4 gives it a
-- price.
--
-- =====================================================================================
-- THE GATE TRAP, AND WHY THIS FILE HAS TO WIRE ITS OWN
-- =====================================================================================
-- `ZoneService.Init` scans `workspace.Zones` for parts named `PortalGate` EXACTLY ONCE, at startup
-- (`ZoneService.lua:334-338`). Everything that relies on that scan -- every zone boundary, the
-- Colosseum, all four expedition maps -- exists before it runs, and `ExpeditionService.Init` is
-- ordered ahead of `ZoneService.Init` in `ServerMain` for precisely this reason.
--
-- A course is built when somebody enters it, which is minutes or hours after that scan. So the scan
-- can never see it, the map is parented into `workspace.Adventures` rather than `workspace.Zones`
-- (nothing for a zone enumerator to trip over), and every gate, checkpoint and finish pad in this
-- feature is connected HERE, at build time, in `wireMap`.
--
-- =====================================================================================
-- ONE HEARTBEAT FOR EVERY MOVING PART IN THE FEATURE, AND IT IS GATED ON `runs`
-- =====================================================================================
-- Not one per platform and not one per course. The standing rule for this project is a single gated
-- Heartbeat per animated SET, because the cost is the number of connections rather than the number
-- of things moved -- and this set grows by fifteen or so with every route built.
--
-- The gate is `runs`: twenty empty courses 4,000 studs off the strip are the normal state of a
-- server, and the loop does nothing at all while nobody is on one.
--
-- IT DOES SETTLE ON THE WAY DOWN, and for a harder reason than the cosmetic one `ExpeditionService`
-- settles for. A mover frozen mid-span is a platform sitting somewhere legal, which would be fine
-- -- but a mover also carries a `AssemblyLinearVelocity`, and an anchored part with a velocity is a
-- CONVEYOR that never stops being one. Skipping the work without clearing that leaves a stationary
-- slab that shoves anything standing on it, forever, at whatever speed the last runner left it at.
-- So the settle pass zeroes the velocities and nothing else: the position it keeps.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS.Remotes

local PlayerDataService = require(script.Parent.PlayerDataService)
local ZoneService = require(script.Parent.ZoneService)
local AdventureMap = require(script.Parent.AdventureMap)

local AdventureService = {}

-- [player] = { key, tier, checkpoint = <part>, index = n, startedAt = os.clock(), map = <Model> }
local runs = {}
-- Every part the Heartbeat moves, gathered once at build time. It holds the MODEL beside each part
-- rather than a key, because the gate is "is anybody on THIS course" and a rebuilt course is a
-- different model -- one that must not leave the old one still being driven.
local animated = {}

local folder -- workspace.Adventures

-- ===== THE MOVEMENT PROFILE =====
-- See the header of `AdventureMap`: the course geometry is cut against a FIXED walk and jump, so
-- the same course is playable by a stage-one body and a stage-twenty one. Applying it is two lines;
-- putting it back is one call, and it is `EvolutionVisuals.RefreshBonuses` rather than a remembered
-- pair of numbers -- the player's real speed is a product of stage, Mastery, the Speed upgrade, the
-- 2x pass and a worn mutation, and any of those can change while they are out here.
--
-- Required LAZILY. `EvolutionVisuals` is a Systems module that requires half the server, and this
-- file is required by `ServerMain` beside services that load before it.
local function applyCourseProfile(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	-- R15 characters default to JumpHeight, so setting JumpPower alone is silently ignored --
	-- the same trap `EvolutionVisuals.applyMastery` documents.
	humanoid.UseJumpPower = true
	humanoid.WalkSpeed = AdventureMap.WALK_SPEED
	humanoid.JumpPower = AdventureMap.JUMP_POWER
end

local function restoreProfile(player)
	local EvolutionVisuals = require(script.Parent.Systems.EvolutionVisuals)
	EvolutionVisuals.RefreshBonuses(player, PlayerDataService.Get(player))
end

-- ===== PUTTING A BODY SOMEWHERE =====
--
-- A checkpoint respawn does NOT go through `ZoneService.travel`. That handshake exists because a
-- teleport across the 12,000-stud strip arrives before the destination has streamed, and it costs a
-- screen cover plus a client round trip -- neither of which is wanted forty studs from where the
-- player already is, on a model marked `ModelStreamingMode.Persistent` that is streamed in by
-- definition. Entering and leaving a course DO go through it, because those cross the map.
local function placeAt(player, cframe)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	hrp.CFrame = cframe
	-- Velocity survives a CFrame write. Without this, a player who fell 110 studs is put back on
	-- the pad still travelling downward at terminal speed and goes straight through it.
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
	return true
end

local function checkpointCFrame(run)
	local pad = run.checkpoint
	if not (pad and pad.Parent) then return nil end
	-- Above the pad, not on it: the pad is a 1-stud sheet lying on the platform, and the biggest
	-- body in the game is 42 studs tall from the feet.
	return CFrame.new(pad.Position + Vector3.new(0, 26, 0))
end

-- A claimed checkpoint lights up. Half a second, on the pad itself, and it is the only thing a
-- 30.3 run says out loud. Two runners on one course see each other's flashes, which is honest --
-- the pad IS shared, there is no instancing in this game, and a light that means "somebody just
-- got here" is not a lie about who.
local FLASH_IN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FLASH_OUT = TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function flashPad(pad)
	local light = pad:FindFirstChildOfClass("PointLight")
	TweenService:Create(pad, FLASH_IN, { Transparency = 0.02 }):Play()
	if light then
		TweenService:Create(light, FLASH_IN, { Brightness = 7, Range = 120 }):Play()
	end
	task.delay(0.16, function()
		if not pad.Parent then return end
		TweenService:Create(pad, FLASH_OUT, { Transparency = 0.35 }):Play()
		if light then
			TweenService:Create(light, FLASH_OUT, { Brightness = 2.2, Range = 70 }):Play()
		end
	end)
end

-- ===== BUILDING AND WIRING =====

local function registerAnimated(model)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local base = part:GetAttribute("BaseCFrame")
			if base then
				if part.Name == "Mover" then
					table.insert(animated, {
						part = part,
						base = base,
						model = model,
						span = part:GetAttribute("MoveSpan") or 0,
						period = math.max(part:GetAttribute("MovePeriod") or 6, 1),
						phase = part:GetAttribute("MovePhase") or 0,
					})
				elseif part.Name == "Spinner" then
					table.insert(animated, {
						part = part,
						base = base,
						model = model,
						spin = part:GetAttribute("SpinSpeed") or 45,
					})
				end
			end
		end
	end
end

local function wireMap(model)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			if part.Name == "Checkpoint" then
				local index = part:GetAttribute("CheckpointIndex")
				part.Touched:Connect(function(hit)
					local character = hit.Parent
					local player = character and Players:GetPlayerFromCharacter(character)
					local run = player and runs[player]
					if not (run and run.map == model and index) then return end
					-- THE DEBOUNCE IS THE COMPARISON. A pad fires dozens of times a second while a
					-- body stands on it, and a run that is put back on checkpoint 3 walks over pads
					-- 1 and 2 on its way forward -- so a checkpoint only ever moves UP, and there is
					-- no per-player timer to keep.
					if index <= run.index then return end
					run.index = index
					run.checkpoint = part
					-- THE FEEDBACK IS THE PAD, NOT A BANNER. The standing rule on this project is
					-- that a thing that happened somewhere is drawn there; `Remotes.Notify` has no
					-- kind between "silent" and `celebratePurchase`'s screen-centre card, and a
					-- full celebration on every checkpoint of a twenty-checkpoint feature is the
					-- mutation toast all over again. 30.6 owns the run HUD; this is what the world
					-- says on its own.
					flashPad(part)
				end)
			elseif part.Name == "FinishPad" then
				part.Touched:Connect(function(hit)
					local character = hit.Parent
					local player = character and Players:GetPlayerFromCharacter(character)
					if not (player and runs[player] and runs[player].map == model) then return end
					local ok, err = pcall(AdventureService.HandleFinish, player)
					if not ok then
						warn("[AdventureService] finish failed for " .. player.Name .. ": " .. tostring(err))
					end
				end)
			elseif part.Name == "PortalGate" then
				part.Touched:Connect(function(hit)
					local character = hit.Parent
					local player = character and Players:GetPlayerFromCharacter(character)
					if not (player and runs[player] and runs[player].map == model) then return end
					local ok, err = pcall(AdventureService.HandleLeave, player)
					if not ok then
						warn("[AdventureService] leave failed for " .. player.Name .. ": " .. tostring(err))
					end
				end)
			end
		end
	end
end

-- The lazy build. Idempotent and safe to call from anywhere: the version stamp decides whether the
-- existing model is still the right shape, and only a model that was actually BUILT gets wired --
-- connecting a second set of Touched handlers to the same pads is how one checkpoint fires twice.
function AdventureService.EnsureMap(route)
	if not folder then return nil end
	local model, built = AdventureMap.EnsureBuilt(folder, route)
	if built then
		registerAnimated(model)
		wireMap(model)
		print(("[AdventureService] built %s (tier %d, %d sections, %d parts)")
			:format(model.Name, route.tier, route.sections, #model:GetDescendants()))
	end
	return model
end

-- ===== IN, OUT, AND FINISHED =====

-- 30.3: no price and no reward. See the header. `HandleEnter` is deliberately not reachable from a
-- client until 30.4 has given it both.
function AdventureService.HandleEnter(player, routeKey)
	local route = GameConfig.GetAdventure(routeKey)
	if not route then return false, "no such route" end
	local data = PlayerDataService.Get(player)
	if not data then return false, "no data" end
	if runs[player] then return false, "already running" end

	local model = AdventureService.EnsureMap(route)
	if not model then return false, "no adventures folder" end

	-- Checkpoint ONE by its attribute, never by `FindFirstChild("Checkpoint", true)`. That call
	-- returns whichever pad the descendant walk reaches first, which is creation order today and
	-- is not a promise -- and the pad it would be wrong about is the one every fall on the first
	-- beat lands on.
	local start = nil
	for _, part in ipairs(model:GetChildren()) do
		if part.Name == "Checkpoint" and part:GetAttribute("CheckpointIndex") == 1 then
			start = part
			break
		end
	end
	runs[player] = {
		key = route.key,
		tier = route.tier,
		sections = route.sections,
		map = model,
		index = 1,
		checkpoint = start,
		startedAt = os.clock(),
		-- PER RUN, because the twenty lanes sit on five different decks (`AdventureMap`'s lane
		-- block). One `voidY` read once at Init would catch route 1's fall 1,280 studs above
		-- route 5's floor -- i.e. it would teleport a player who had not fallen at all.
		voidY = AdventureMap.GetVoidY(route),
	}

	local moved = ZoneService.SendToAdventure(player, AdventureMap.GetSpawnCFrame(route), {
		name = route.name,
		emoji = route.emoji,
		color = route.accentColor,
	})
	if not moved then
		runs[player] = nil
		return false, "could not travel"
	end
	-- AFTER the travel, not before: `travel` anchors the root part and hands it back at the end, and
	-- a character that is mid-handshake has not necessarily got its Humanoid where we can see it.
	applyCourseProfile(player)
	return true
end

local function endRun(player)
	local run = runs[player]
	runs[player] = nil
	restoreProfile(player)
	return run
end

function AdventureService.HandleLeave(player)
	if not runs[player] then return false end
	endRun(player)
	ZoneService.SendHomeFromAdventure(player)
	return true
end

-- THE SEAM 30.4 OPENS. Everything the finish line is worth -- the par bonus, the two relic rolls,
-- the best-time write into `data.Adventures.Best` and the telemetry beat -- belongs to that row.
-- What 30.3 owes is the other half: the line is reachable, it knows who crossed it and how long
-- they took, and it does not leave the player standing on a platform in the void.
function AdventureService.HandleFinish(player)
	local run = runs[player]
	if not run then return false end
	local seconds = os.clock() - run.startedAt
	local route = GameConfig.GetAdventure(run.key)
	local par = route and route.parSeconds or 0

	endRun(player)
	ZoneService.SendHomeFromAdventure(player)

	Remotes.Notify:FireClient(player, {
		kind = "reward",
		message = ("\u{1F3C1} %s finished in %.1fs (par %ds)"):format(
			route and route.name or run.key, seconds, par),
	})
	print(("[AdventureService] %s finished %s in %.1fs (par %d)")
		:format(player.Name, run.key, seconds, par))
	return true, seconds
end

-- ===== INIT =====
function AdventureService.Init()
	folder = workspace:FindFirstChild("Adventures")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Adventures"
		folder.Parent = workspace
	end

	-- A player who dies out here -- and there is nothing on a course that can kill one, so this is
	-- the disconnect-and-reconnect case and the admin case -- has their run ended rather than being
	-- left registered on a map they are not standing on. `ZoneService` already owns the respawn: it
	-- puts every character back at `CurrentZone`, which a course deliberately never writes.
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			if runs[player] then
				runs[player] = nil
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		runs[player] = nil
	end)

	-- One flag and one pass, run once on the way down rather than every frame -- see the header.
	local settled = true
	local function settle()
		for _, item in ipairs(animated) do
			item.driving = false
			if not item.spin and item.part.Parent then
				item.part.AssemblyLinearVelocity = Vector3.zero
			end
		end
	end

	RunService.Heartbeat:Connect(function()
		if next(runs) == nil then
			if not settled then
				settled = true
				settle()
			end
			return
		end
		settled = false

		-- Which courses have somebody on them. Built per frame from `runs`, which is at most a
		-- handful of entries -- cheaper than keeping a second table in step with it, and it cannot
		-- disagree with the truth the way a cached count can.
		local live = {}
		for _, run in pairs(runs) do
			live[run.map] = true
		end

		local t = os.clock()
		for _, item in ipairs(animated) do
			-- A course that nobody is on while somebody is on ANOTHER one gets the same treatment
			-- as the whole set does on the way down: stopped once, not stopped every frame.
			if item.driving and not live[item.model] then
				item.driving = false
				if not item.spin and item.part.Parent then
					item.part.AssemblyLinearVelocity = Vector3.zero
				end
			end
			if live[item.model] and item.part.Parent then
				item.driving = true
				if item.spin then
					item.part.CFrame = item.base * CFrame.Angles(0, math.rad(t * item.spin), 0)
				else
					-- TWO WRITES, AND THE SECOND ONE IS THE WHOLE BEAT. Position alone moves the
					-- platform and leaves the player standing in the air where it used to be --
					-- measured at 87 studs of drift on a 98-stud sweep, i.e. the rider falls off
					-- every time. An anchored part with a velocity is a conveyor, so the velocity
					-- is what carries them; it is the analytic derivative of the line above, not a
					-- difference between frames, because a difference is one frame stale and goes
					-- to zero the moment the gate skips a frame. See `AdventureMap`'s `mover`.
					local w = math.pi * 2 / item.period
					local phase = (t / item.period + item.phase) * math.pi * 2
					item.part.CFrame = item.base + Vector3.new(0, 0, math.sin(phase) * item.span / 2)
					item.part.AssemblyLinearVelocity =
						Vector3.new(0, 0, math.cos(phase) * w * item.span / 2)
				end
			end
		end

		-- ...and the fall catch, in the same pass. There are no kill bricks on a course: the drop is
		-- open air, and this is what turns it into a checkpoint respawn rather than a death at the
		-- game's single SpawnLocation 4,000 studs away.
		for player, run in pairs(runs) do
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if hrp and hrp.Position.Y < run.voidY then
				local cf = checkpointCFrame(run)
				if cf then
					placeAt(player, cf)
					-- `error` is the one kind in `MainUI`'s handler that draws a plain toast with
					-- the message it is given, and a fall IS the failure it reads as. Every other
					-- kind carries its own fixed wording.
					Remotes.Notify:FireClient(player, {
						kind = "error",
						message = ("Fell \u{2014} back to checkpoint %d"):format(run.index),
					})
				else
					-- The map went away underneath a live run (a version bump mid-session). Nothing
					-- to put them on, so send them home rather than leave them falling.
					AdventureService.HandleLeave(player)
				end
			end
		end
	end)
end

return AdventureService
