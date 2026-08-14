--[[
	SplicerService -- the DNA Splicer: the machine mutations are bought at, and the sink DNA
	needed (Phase 12.2).

	=========================================================================================
	WHAT THIS REPLACED, WHICH IS THE REASON IT EXISTS
	=========================================================================================
	Mutations were not a feature before this: they were a loop in DNAService that fired every ten
	seconds for as long as a player was online, appended a name to a list nothing ever pruned, and
	multiplied income by a ladder topping at x30. No screen in the game named it, no action
	triggered it, and nobody ever chose to have one. The whole system was a faucet.

	It is a machine you walk up to and pay for now. The roll itself is unchanged
	(`GameConfig.RollMutation`) -- what is new is that it costs something, that exactly one
	mutation is worn at a time, and that the rare end of the ladder is worth telling the server
	about.

	=========================================================================================
	THE PRICE IS IN KILLS, AND THAT IS NOT A FIGURE OF SPEECH
	=========================================================================================
	`GameConfig.GetSplicerRollCost` is the one implementation and this file does not do its own
	arithmetic anywhere -- the client panel quotes the same function, so the number on the screen
	and the number charged cannot drift. See the block over it in GameConfig for why it is priced
	off per-kill income rather than through `ScaleReward`.

	=========================================================================================
	THREE THINGS THE SERVER DOES NOT TRUST THE CLIENT FOR
	=========================================================================================
	* THE PRICE. Recomputed here from the save, never read off the request.
	* THE PITY. `SplicerRolls` is incremented on the server and the charged roll is decided from
	  the incremented value. The client PREDICTS which roll is charged so it can draw the meter;
	  a client that predicts wrong gets a correct roll and a wrong meter, which is the right way
	  round for a disagreement.
	* THE RATE. One roll per `ROLL_INTERVAL` per player. The reveal alone is longer than that, so
	  it never fires for an honest player and always fires for a loop.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local SplicerService = {}

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Bump to force the machine to be rebuilt on the next server start. Stamped on the model, the
-- same trick RebirthShrine and ZoneBuilder use -- without it no change to the geometry below
-- would ever appear on a place that has already been played.
local MACHINE_VERSION = 1

-- Seconds between two rolls from one player. The client's own reveal runs ~2.4 s.
local ROLL_INTERVAL = 1.2

-- ===== WHERE IT STANDS =====
-- Forest, whose platform is centred on x = 0 with its top face at y = 0. The street runs down Z
-- at x = +-38 (lamps, benches, planters), the three leaderboard boards stand at x = -130 over
-- z = 140..300, and the rebirth plaza occupies x = 225..375. This is the gap between the street
-- and that plaza, in plain sight of the spawn walk-down and standing on nothing.
--
-- The exact spot is SEARCHED rather than asserted (see `findClearSpot`): Forest's scatter props
-- are placed by a builder that does not know this file exists, and a machine standing inside a
-- conifer is the kind of thing that only ever gets noticed in a screenshot.
local PREFERRED = Vector3.new(120, 0, 215)
local FOOTPRINT = Vector3.new(30, 26, 30)

-- How close a player has to be for the helix to turn. Squared, because this is compared in a
-- loop and a square root per player per tick buys nothing.
local ANIMATE_RANGE_SQ = 90 * 90

local STEEL      = Color3.fromRGB(126, 132, 148)
local STEEL_DARK = Color3.fromRGB(70, 74, 88)
local STEEL_LITE = Color3.fromRGB(178, 184, 200)
local GLASS_TINT = Color3.fromRGB(150, 225, 255)
local ACCENT     = Color3.fromRGB(120, 210, 255)

local lastRoll = {}
-- every part of the helix, with the offset it sits at when the machine is unturned
local helix = {}
local helixPivot = nil
local machineModel = nil

-- ===== PART VOCABULARY =====
-- A local copy rather than a require of ZoneBuilder's, for the reason RebirthShrine gives for
-- having its own: that module is thousands of lines and rebuilds tens of thousands of parts
-- behind a version stamp of its own. This one builds under a hundred and owns them.
local function newPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	return p
end

-- ===== FINDING GROUND NOTHING IS STANDING ON =====
-- Steps out from `PREFERRED` along a widening ring and takes the first spot whose footprint is
-- empty of anything solid. Returns the preferred spot if every candidate is occupied, because a
-- machine in the wrong place is recoverable and no machine at all is not.
local function findClearSpot()
	local candidates = { Vector3.new(0, 0, 0) }
	for ring = 1, 6 do
		local step = ring * 26
		table.insert(candidates, Vector3.new(step, 0, 0))
		table.insert(candidates, Vector3.new(-step, 0, 0))
		table.insert(candidates, Vector3.new(0, 0, step))
		table.insert(candidates, Vector3.new(0, 0, -step))
		table.insert(candidates, Vector3.new(step, 0, step))
		table.insert(candidates, Vector3.new(-step, 0, step))
	end

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { machineModel }

	for _, offset in ipairs(candidates) do
		local centre = PREFERRED + offset
		local box = CFrame.new(centre + Vector3.new(0, FOOTPRINT.Y / 2, 0))
		local hits = workspace:GetPartBoundsInBox(box, FOOTPRINT, params)
		local blocked = false
		for _, part in ipairs(hits) do
			-- The floor is not an obstruction; everything standing ON it is.
			if part.CanCollide and part.Position.Y > 0.5 then
				blocked = true
				break
			end
		end
		if not blocked then
			return centre, offset.Magnitude
		end
	end
	return PREFERRED, -1
end

-- ===== THE MACHINE =====
local function buildMachine(centre)
	local model = Instance.new("Model")
	model.Name = "DNASplicer"

	-- ---- plinth. Two slabs so the machine has an edge you can see you are standing at.
	local rim = newPart({ Name = "PlinthRim", Size = Vector3.new(26, 1.4, 26),
		Position = centre + Vector3.new(0, 0.7, 0), Color = STEEL_DARK,
		Material = Enum.Material.DiamondPlate, Parent = model })
	local deck = newPart({ Name = "Plinth", Size = Vector3.new(22, 1.6, 22),
		Position = centre + Vector3.new(0, 1.9, 0), Color = STEEL,
		Material = Enum.Material.DiamondPlate, Parent = model })
	model.PrimaryPart = deck

	-- a ring of lit floor tiles, so the machine has a footprint at night
	for i = 0, 7 do
		local a = (i / 8) * math.pi * 2
		newPart({ Name = "DeckLamp", Size = Vector3.new(2.4, 0.4, 2.4),
			Position = centre + Vector3.new(math.cos(a) * 8.6, 2.8, math.sin(a) * 8.6),
			Color = ACCENT, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	end

	-- ---- the two pillars the tube stands between
	for _, sx in ipairs({ -7.5, 7.5 }) do
		newPart({ Name = "Pillar", Size = Vector3.new(5, 19, 7),
			Position = centre + Vector3.new(sx, 12.2, 0), Color = STEEL,
			Material = Enum.Material.Metal, Parent = model })
		newPart({ Name = "PillarTrim", Size = Vector3.new(5.6, 1.6, 7.6),
			Position = centre + Vector3.new(sx, 21.6, 0), Color = ACCENT,
			Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		newPart({ Name = "PillarFoot", Size = Vector3.new(6.4, 1.8, 8.4),
			Position = centre + Vector3.new(sx, 3.6, 0), Color = STEEL_DARK,
			Material = Enum.Material.Metal, Parent = model })
	end

	-- ---- canopy
	newPart({ Name = "Canopy", Size = Vector3.new(23, 2, 10),
		Position = centre + Vector3.new(0, 23.4, 0), Color = STEEL_DARK,
		Material = Enum.Material.Metal, Parent = model })
	newPart({ Name = "CanopyLip", Size = Vector3.new(24.4, 0.9, 11.4),
		Position = centre + Vector3.new(0, 22.3, 0), Color = ACCENT,
		Material = Enum.Material.Neon, CanCollide = false, Parent = model })

	-- ---- the glass tube. Shape = Cylinder is drawn along its X axis, so it is turned upright
	-- rather than sized as if the axis were Y -- sizing it the other way makes a flat disc and is
	-- the same class of mistake as a non-uniform Ball.
	local tube = newPart({ Name = "Tube", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(17, 9.4, 9.4), Color = GLASS_TINT, Material = Enum.Material.Glass,
		Transparency = 0.62, CanCollide = false, CastShadow = false,
		CFrame = CFrame.new(centre + Vector3.new(0, 12.6, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Parent = model })
	newPart({ Name = "TubeCapLower", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.6, 10.6, 10.6), Color = STEEL_LITE, Material = Enum.Material.Metal,
		CFrame = CFrame.new(centre + Vector3.new(0, 4.4, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Parent = model })
	newPart({ Name = "TubeCapUpper", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.6, 10.6, 10.6), Color = STEEL_LITE, Material = Enum.Material.Metal,
		CFrame = CFrame.new(centre + Vector3.new(0, 20.8, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Parent = model })

	-- ---- the helix. Two strands and the rungs between them, which is the thing that makes the
	-- machine legible as a DNA splicer from across the plaza rather than as a lamp.
	local BEADS, TURNS, RADIUS, SPAN = 13, 2.1, 2.9, 14.4
	helix = {}
	helixPivot = CFrame.new(centre + Vector3.new(0, 12.6, 0))
	for i = 0, BEADS - 1 do
		local t = i / (BEADS - 1)
		local a = t * math.pi * 2 * TURNS
		local y = (t - 0.5) * SPAN
		for strand = 0, 1 do
			local ang = a + strand * math.pi
			local bead = newPart({ Name = "HelixBead", Shape = Enum.PartType.Ball,
				Size = Vector3.new(1.7, 1.7, 1.7),
				Color = strand == 0 and ACCENT or Color3.fromRGB(255, 150, 220),
				Material = Enum.Material.Neon, CanCollide = false, CastShadow = false,
				Parent = model })
			-- Stored as an OFFSET from the pivot, not as a world CFrame: the driver below rebuilds
			-- every frame from `pivot * turn * offset`, which is an exact rotation. A tween would
			-- lerp the position and walk each bead across the chord instead of around the axis.
			local offset = CFrame.new(math.cos(ang) * RADIUS, y, math.sin(ang) * RADIUS)
			bead.CFrame = helixPivot * offset
			table.insert(helix, { part = bead, offset = offset })
		end
		-- a rung every other bead pair, or the tube fills up with bars
		if i % 2 == 0 then
			local rung = newPart({ Name = "HelixRung", Size = Vector3.new(RADIUS * 2, 0.42, 0.42),
				Color = STEEL_LITE, Material = Enum.Material.Neon, CanCollide = false,
				CastShadow = false, Parent = model })
			local offset = CFrame.new(0, y, 0) * CFrame.Angles(0, -a, 0)
			rung.CFrame = helixPivot * offset
			table.insert(helix, { part = rung, offset = offset })
		end
	end

	-- ---- the console you actually walk up to
	local console = newPart({ Name = "Console", Size = Vector3.new(11, 4.6, 5),
		Position = centre + Vector3.new(0, 5.2, 8.6), Color = STEEL,
		Material = Enum.Material.Metal, Parent = model })
	newPart({ Name = "ConsoleLip", Size = Vector3.new(11.8, 0.8, 5.8),
		Position = centre + Vector3.new(0, 7.6, 8.6), Color = ACCENT,
		Material = Enum.Material.Neon, CanCollide = false, Parent = model })

	local screen = newPart({ Name = "Screen", Size = Vector3.new(9.4, 3.2, 0.4),
		Position = centre + Vector3.new(0, 5.6, 11.2), Color = Color3.fromRGB(16, 20, 30),
		Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = model })
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.CanvasSize = Vector2.new(360, 120)
	sg.LightInfluence = 0
	sg.Parent = screen
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -12, 0.62, 0)
	title.Position = UDim2.new(0, 6, 0, 4)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.Text = "DNA SPLICER"
	title.TextColor3 = ACCENT
	title.TextScaled = true
	title.Parent = sg
	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, -12, 0.34, 0)
	sub.Position = UDim2.new(0, 6, 0.62, 0)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamMedium
	sub.Text = "Splice a mutation into your DNA"
	sub.TextColor3 = Color3.fromRGB(210, 226, 245)
	sub.TextScaled = true
	sub.Parent = sg

	local light = Instance.new("PointLight")
	light.Color = ACCENT
	light.Range = 34
	light.Brightness = 1.6
	light.Shadows = false
	light.Parent = tube

	-- ---- the prompt. `ShopPanel` is the same grammar every other counter in the game uses, and
	-- MainUI's handler looks the key up in a table that has no "splicer" row, so it falls through
	-- there and is picked up by SplicerUI instead.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SplicerPrompt"
	prompt.ActionText = "Splice"
	prompt.ObjectText = "DNA Splicer"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("ShopPanel", "splicer")
	prompt.Parent = console

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	model:SetAttribute("MachineVersion", MACHINE_VERSION)
	return model
end

-- ===== THE HELIX TURNS, ON ONE HEARTBEAT, ONLY WHEN SOMEBODY IS THERE =====
-- One connection for the whole machine rather than one per part, and it does nothing at all while
-- the plaza is empty -- the rule every animated set in this game is held to.
local function driveHelix()
	local angle = 0
	local sinceCheck = 0
	local nearby = false
	RunService.Heartbeat:Connect(function(dt)
		sinceCheck += dt
		if sinceCheck >= 0.5 then
			sinceCheck = 0
			nearby = false
			for _, plr in ipairs(Players:GetPlayers()) do
				local char = plr.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if root and helixPivot and (root.Position - helixPivot.Position).Magnitude ^ 2 <= ANIMATE_RANGE_SQ then
					nearby = true
					break
				end
			end
		end
		if not nearby or not helixPivot then return end
		angle = (angle + dt * 0.9) % (math.pi * 2)
		local turn = CFrame.Angles(0, angle, 0)
		for _, entry in ipairs(helix) do
			entry.part.CFrame = helixPivot * turn * entry.offset
		end
	end)
end

-- ===== THE ROLL =====
-- The ONE place a mutation is written onto a save, for the reason `insertPet` is the one place a
-- pet is created: two writers is how two rules drift apart.
local function applyMutation(data, mutation)
	data.SplicerFound = data.SplicerFound or {}
	data.SplicerFound[mutation.name] = (data.SplicerFound[mutation.name] or 0) + 1

	local current = data.SplicerMutation and GameConfig.GetMutationByName(data.SplicerMutation)
	local equipped = false
	-- Index order IS rarity order in GameConfig.Mutations, so "better" is a plain index compare.
	local newIdx, curIdx = 0, 0
	for i, m in ipairs(GameConfig.Mutations) do
		if m.name == mutation.name then newIdx = i end
		if current and m.name == current.name then curIdx = i end
	end
	if newIdx > curIdx then
		data.SplicerMutation = mutation.name
		equipped = true
	end
	return equipped
end

function SplicerService.HandleRoll(player)
	local PlayerDataService = require(script.Parent.PlayerDataService)
	local EvolutionVisuals = require(script.Parent.Systems.EvolutionVisuals)
	local AnnounceService = require(script.Parent.AnnounceService)

	local data = PlayerDataService.Get(player)
	if not data then return end

	local now = os.clock()
	local last = lastRoll[player.UserId]
	if last and now - last < ROLL_INTERVAL then return end
	lastRoll[player.UserId] = now

	local cost = GameConfig.GetSplicerRollCost(data)
	if (data.DNA or 0) < cost then
		-- Two messages, deliberately: the toast is the WORDING and goes through the same Notify
		-- stack every refusal in the game uses (so it queues, ranks and sounds like the others),
		-- while SpliceResult tells the panel to re-read itself. Neither does the other's job.
		Remotes.Notify:FireClient(player, { kind = "error", message = "Not enough DNA to splice!" })
		Remotes.SpliceResult:FireClient(player, { ok = false, reason = "poor", cost = cost })
		return
	end

	data.DNA -= cost
	data.SplicerRolls = (data.SplicerRolls or 0) + 1

	-- The pity roll is decided from the INCREMENTED count, so the tenth roll is charged rather
	-- than the eleventh -- the client's meter counts the same way.
	local S = GameConfig.Splicer
	local charged = (data.SplicerRolls % S.pityEvery) == 0
	local mutation = GameConfig.RollMutation(GameConfig.GetSplicerLuck(data, charged))
	if charged then
		-- A charged roll is a floor, not a reroll: it cannot make a result worse than it landed.
		local idx = 0
		for i, m in ipairs(GameConfig.Mutations) do
			if m.name == mutation.name then idx = i end
		end
		if idx < S.pityMinIndex then
			mutation = GameConfig.Mutations[S.pityMinIndex]
		end
	end

	local equipped = applyMutation(data, mutation)
	if equipped then
		-- The one replication channel the aura and the walk speed both read.
		player:SetAttribute("Mutation", mutation.name)
		EvolutionVisuals.RefreshBonuses(player)
	end
	PlayerDataService.PushToClient(player)

	local idx = 0
	for i, m in ipairs(GameConfig.Mutations) do
		if m.name == mutation.name then idx = i end
	end

	Remotes.SpliceResult:FireClient(player, {
		ok = true,
		name = mutation.name,
		color = mutation.color,
		index = idx,
		incomeMult = mutation.incomeMult,
		speedBonus = mutation.speedBonus,
		equipped = equipped,
		spent = cost,
		rollIndex = data.SplicerRolls,
		charged = charged,
		nextCost = GameConfig.GetSplicerRollCost(data),
	})

	if idx >= S.announceMinIndex then
		AnnounceService.MutationRolled(player, mutation)
	end
end

function SplicerService.Init()
	local PlayerDataService = require(script.Parent.PlayerDataService)

	for _, name in ipairs({ "SpliceRoll", "SpliceResult" }) do
		if not Remotes:FindFirstChild(name) then
			local r = Instance.new("RemoteEvent")
			r.Name = name
			r.Parent = Remotes
		end
	end

	local map = workspace:FindFirstChild("Map")
	if not map then
		map = Instance.new("Folder")
		map.Name = "Map"
		map.Parent = workspace
	end

	-- Rebuilt by replacement rather than patched in place: a stamped model whose version has moved
	-- is not the same machine, and reconciling it piece by piece is how half-old geometry survives.
	local existing = map:FindFirstChild("DNASplicer")
	if existing and existing:GetAttribute("MachineVersion") ~= MACHINE_VERSION then
		existing:Destroy()
		existing = nil
	end

	if existing then
		machineModel = existing
		local pivot = existing:FindFirstChild("Plinth")
		if pivot then
			helixPivot = CFrame.new(pivot.Position + Vector3.new(0, 10.7, 0))
		end
		helix = {}
		for _, d in ipairs(existing:GetDescendants()) do
			if d.Name == "HelixBead" or d.Name == "HelixRung" then
				table.insert(helix, { part = d, offset = helixPivot:Inverse() * d.CFrame })
			end
		end
	else
		local centre, moved = findClearSpot()
		machineModel = buildMachine(centre)
		machineModel.Parent = map
		if moved > 0 then
			warn(("[SplicerService] preferred spot was occupied; machine moved %.0f studs to (%d, %d)")
				:format(moved, centre.X, centre.Z))
		end
	end

	-- Never streamed out: the machine is a landmark and a player who walked to it must find it
	-- there, not arriving a second later.
	machineModel.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	local prompt = machineModel:FindFirstChild("SplicerPrompt", true)
	if prompt then
		prompt.Triggered:Connect(function() end) -- the panel is opened client-side off the same prompt
	end

	Remotes.SpliceRoll.OnServerEvent:Connect(function(player)
		local ok, err = pcall(SplicerService.HandleRoll, player)
		if not ok then
			warn("[SplicerService] roll failed for " .. player.Name .. ": " .. tostring(err))
		end
	end)

	driveHelix()

	-- ===== THE ONE-TIME REFUND NOTICE =====
	-- PlayerDataService refunds the deleted Mutation Chance upgrade during load and leaves the
	-- amount in memory (never on the save -- it would be persisted and re-announced forever).
	-- This is its only reader, and it clears the entry so a rejoin on the same server says nothing.
	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			player.CharacterAdded:Wait()
			task.wait(3) -- the HUD and SplicerUI are both up well inside this
			local refund = PlayerDataService.SplicerRefunds[player.UserId]
			if refund and refund > 0 then
				PlayerDataService.SplicerRefunds[player.UserId] = nil
				-- Through the ordinary Notify stack rather than a card of its own: it is news, not
				-- an event, and MainUI already owns how news is worded, ranked and sounded.
				Remotes.Notify:FireClient(player, { kind = "reward",
					message = ("🧬 Mutation Chance was replaced by the DNA Splicer -- refunded %d DNA")
						:format(refund) })
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastRoll[player.UserId] = nil
		PlayerDataService.SplicerRefunds[player.UserId] = nil
	end)
end

return SplicerService
