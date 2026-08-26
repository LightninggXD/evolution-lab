local GrottoDummyService = {}

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local PlayerDataService = require(script.Parent.PlayerDataService)
local LevelService = require(script.Parent.Level.LevelService)
local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS.Remotes

local dummyModel = nil
local dummyBody = nil
local lastHit = {} -- debounce per player
local HIT_COOLDOWN = 0.25 -- faster than default mob hits, it's a dummy!

local function onHit(player, isAuto)
	if not dummyBody then return end
	local now = os.clock()
	if now - (lastHit[player.UserId] or 0) < HIT_COOLDOWN then return end
	
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	
	local dist = (hrp.Position - dummyBody.Position).Magnitude
	local maxReach = isAuto and 20 or 25
	if dist > maxReach then return end
	
	lastHit[player.UserId] = now
	
	local data = PlayerDataService.Get(player)
	if not data then return end
	
		-- Task 33.21: Dummy grants a session buff to avoid breaking permanent mob curves
	-- Up to 50 hits, max +50% damage
	local currentHits = data.GrottoHits or 0
	if currentHits >= 50 then
		Remotes.Notify:FireClient(player, { kind = "error", text = "You feel you can learn no more today!" })
		return
	end
	
	data.GrottoHits = currentHits + 1
	data.GrottoSessionDamage = 1 + (data.GrottoHits * 0.01)
	
	-- Play hit effect locally
	-- Play hit effect locally
-- Play hit effect locally
	local CombatFx = Remotes:FindFirstChild("CombatFx")
	if CombatFx then
		CombatFx:FireClient(player, "hit", dummyBody.Position, 1)
	end
	
	-- Notify client of floating combat text for +1 XP
	Remotes.Notify:FireClient(player, { kind = "creature", amount = 1 })
end

local function ensureRemote(name)
	local existing = Remotes:FindFirstChild(name)
	if existing then return existing end
	local ev = Instance.new("RemoteEvent")
	ev.Name = name
	ev.Parent = Remotes
	return ev
end

function GrottoDummyService.Init()
	-- Defect 5 Fix: Remotes created inside Init
	local AutoAttack = ensureRemote("AutoAttack")
	ensureRemote("CombatFx")
	
	-- Defect 4 Fix: Connection inside Init
	AutoAttack.OnServerEvent:Connect(function(player, model)
		if model ~= dummyModel then return end
		onHit(player, true)
	end)

	-- Defect 6 Fix: Derive position from Secrets instead of hardcoding
	local secretOffset = Vector3.new(291, 6, -290)
	if GameConfig.Secrets and GameConfig.Secrets[1] then
		secretOffset = GameConfig.Secrets[1].offset
	end
	local dummyPos = secretOffset + Vector3.new(7, 3, -4)
	
	dummyModel = Instance.new("Model")
	dummyModel.Name = "TrainingDummy"
	
	dummyBody = Instance.new("Part")
	dummyBody.Name = "HumanoidRootPart"
	dummyBody.Size = Vector3.new(3, 6, 3)
	dummyBody.Position = dummyPos
	dummyBody.Anchored = true
	dummyBody.CanCollide = true
	dummyBody.Color = Color3.fromRGB(150, 100, 50)
	dummyBody.Material = Enum.Material.Wood
	dummyBody.Parent = dummyModel
	
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2, 2, 2)
	head.Position = dummyPos + Vector3.new(0, 4, 0)
	head.Anchored = true
	head.CanCollide = false
	head.Color = Color3.fromRGB(180, 150, 100)
	head.Material = Enum.Material.Wood
	head.Parent = dummyModel
	
	local hum = Instance.new("Humanoid")
	hum.MaxHealth = math.huge
	hum.Health = math.huge
	hum.Parent = dummyModel
	
	local clickDetector = Instance.new("ClickDetector")
	clickDetector.MaxActivationDistance = 25
	clickDetector.Parent = dummyBody
	
	clickDetector.MouseClick:Connect(function(player)
		onHit(player, false)
	end)
	
	task.defer(function()
		local map = workspace:WaitForChild("Map", 10)
		if map then
			-- Defect 2 Fix: Parent to Props instead of Secrets so it survives Secret bumps
			local props = map:FindFirstChild("Props")
			if not props then
				props = Instance.new("Folder")
				props.Name = "Props"
				props.Parent = map
			end
			dummyModel.Parent = props
		end
	end)
end

return GrottoDummyService