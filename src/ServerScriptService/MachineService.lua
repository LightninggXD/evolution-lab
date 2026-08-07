local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local PlayerDataService = require(script.Parent.PlayerDataService)
local Remotes = RS.Remotes

local MachineService = {}

-- ===== THE STARTER TRICKLE =====
-- There is ONE machine in the world and it stands next to the Forest spawn, which is the whole
-- design: it exists so a brand-new player who has not worked out how to fight yet still sees a
-- number go up in their first minute. It is not an income source and must never become one.
--
-- The payout is therefore pinned to an EARLY-GAME click and does not follow the player. It used to
-- be `GetClickAmount(data) * 0.6` every 3 seconds -- GetClickAmount carries the stage curve, every
-- upgrade, every pet and the mutation multiplier, so at stage 15 a machine that was meant to be a
-- tutorial prop was paying out at a rate that competed with fighting. Fighting is what the game is
-- about and it is also the ONLY source of XP, so anything that beats it on DNA is a trap.
--
-- Capped at the stage-2 click base, so it stops growing almost immediately: roughly 11 DNA a use at
-- best, against ~6 for a single Forest creature kill that takes about as long. Fighting wins from
-- the first minute and keeps winning.
local COOLDOWN = 5
local MACHINE_CLICKS = 3     -- machine use = this many early-game clicks
local MACHINE_STAGE_CAP = 2  -- ...and the click never counts as later than this stage

local lastUse = {} -- [userId] = os.clock()

local function buildMachine()
	local existing = workspace:FindFirstChild("DNAMachine")
	if existing then existing:Destroy() end

	local model = Instance.new("Model")
	model.Name = "DNAMachine"

	-- BESIDE THE FOREST SPAWN, not behind the egg stall. It used to sit at (-32, -48), which is 24
	-- studs behind the stall's back board: a player standing at the counter had a humming green
	-- machine growing out of the shop, and a player who spawned never saw it at all. The spawn pad
	-- is at (0, 366); this is off to one side of it, clear of the walkway (STREET_HALF is 48) and
	-- clear of the arrival gate's own reserved circle.
	local anchor = CFrame.new(-62, 0, 348)
	local housingTop = 7

	local template = ServerStorage:FindFirstChild("Models") and ServerStorage.Models:FindFirstChild("DNAMachineMesh")
	if template then
		local housing = template:Clone()
		local geom = housing:FindFirstChild("body") and housing.body:FindFirstChild("body_geom")
		local halfHeight = geom and geom.Size.Y / 2 or 4.5
		housing:PivotTo(anchor * CFrame.new(0, halfHeight, 0))
		housing.Parent = model
		housingTop = halfHeight * 2
	else
		local base = Instance.new("Part")
		base.Name = "Base"
		base.Size = Vector3.new(7, 1, 7)
		base.Anchored = true
		base.CanCollide = true
		base.Material = Enum.Material.DiamondPlate
		base.Color = Color3.fromRGB(70, 70, 80)
		base.CFrame = anchor * CFrame.new(0, 0.5, 0)
		base.Parent = model

		local column = Instance.new("Part")
		column.Name = "Column"
		column.Size = Vector3.new(3, 6, 3)
		column.Anchored = true
		column.CanCollide = true
		column.Material = Enum.Material.Metal
		column.Color = Color3.fromRGB(50, 50, 60)
		column.CFrame = base.CFrame * CFrame.new(0, 3.5, 0)
		column.Parent = model
	end

	local core = Instance.new("Part")
	core.Name = "Core"
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.new(3.4, 3.4, 3.4)
	core.Anchored = true
	core.CanCollide = false
	core.Material = Enum.Material.Neon
	core.Color = Color3.fromRGB(90, 230, 150)
	core.CFrame = anchor * CFrame.new(0, housingTop + 1.5, 0)
	core.Parent = model

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(120, 255, 170)
	light.Range = 18
	light.Brightness = 2.5
	light.Parent = core

	task.spawn(function()
		while core.Parent do
			TweenService:Create(core, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
				Size = Vector3.new(3.8, 3.8, 3.8),
			}):Play()
			task.wait(2.4)
		end
	end)

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 180, 0, 44)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 35
	billboard.Parent = core

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 18
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.4
	label.Text = "🧬 DNA Machine"
	label.Parent = billboard

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Collect DNA"
	prompt.ObjectText = "DNA Machine"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 13
	prompt.RequiresLineOfSight = false
	prompt.Parent = core

	model.PrimaryPart = core
	model.Parent = workspace

	return model, prompt, core
end

function MachineService.Init()
	local DNAService = require(script.Parent.DNAService)
	local model, prompt, core = buildMachine()

	prompt.Triggered:Connect(function(player)
		local now = os.clock()
		if lastUse[player.UserId] and now - lastUse[player.UserId] < COOLDOWN then
			return -- still on cooldown, ignore
		end
		lastUse[player.UserId] = now

		local data = PlayerDataService.Get(player)
		if not data then return end

		-- Pinned to an early-game click rather than to THIS player's click -- see the note on the
		-- constants. Still floored at 2 so it never *feels* like it did nothing.
		local GameConfig = require(RS.Modules.GameConfig)
		local stage = math.min(data.StageIndex or 1, MACHINE_STAGE_CAP)
		local amount = math.max(2, math.ceil(GameConfig.GetClickBase(stage) * MACHINE_CLICKS))
		data.DNA += amount
		PlayerDataService.UpdateLeaderstats(player)
		PlayerDataService.PushToClient(player)
		Remotes.Notify:FireClient(player, { kind = "machine", amount = amount })

		local pulse = TweenService:Create(core, TweenInfo.new(0.15), { Size = core.Size + Vector3.new(1, 1, 1) })
		pulse:Play()
		task.delay(0.15, function()
			if core and core.Parent then
				TweenService:Create(core, TweenInfo.new(0.15), { Size = Vector3.new(3.4, 3.4, 3.4) }):Play()
			end
		end)

		-- THE COOLDOWN IS PER PLAYER; THE PROMPT IS NOT.
		--
		-- `lastUse` is keyed by UserId and does the real work above. Disabling the prompt on top of
		-- that turned a five-second personal cooldown into a five-second GLOBAL one -- there is
		-- exactly one DNA Machine in the world, so on a busy spawn one player using it switched the
		-- tutorial prop off for everybody standing round it, and a new player watching "Collect DNA"
		-- flicker on and off has no way to know it is not simply broken.
		--
		-- The visible feedback that was wanted here is the core pulse above, which the triggering
		-- player sees and which costs nobody else anything.
		prompt.ActionText = "Collect DNA"
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastUse[player.UserId] = nil
	end)
end

return MachineService
