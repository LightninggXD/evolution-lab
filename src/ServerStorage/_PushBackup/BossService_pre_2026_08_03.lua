local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS.Remotes

local PlayerDataService = require(script.Parent.PlayerDataService)
local DNAService = require(script.Parent.DNAService)

local BossService = {}

local bossesFolder = workspace:FindFirstChild("Bosses")
if not bossesFolder then
	bossesFolder = Instance.new("Folder")
	bossesFolder.Name = "Bosses"
	bossesFolder.Parent = workspace
end

-- Relative position from each zone's center where its boss stands guard -- near the exit
-- portal (positive X side) so it visibly blocks the way to the next zone.
local BOSS_RELATIVE_OFFSET = Vector3.new(175, 0, 0)

local function hurtPlayer(player, amount)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	humanoid:TakeDamage(amount)
	Remotes.Notify:FireClient(player, { kind = "playerHurt", amount = math.floor(amount) })
end

local function hasDefeated(data, zoneKey)
	for _, k in ipairs(data.DefeatedBosses) do
		if k == zoneKey then return true end
	end
	return false
end

-- Marks this zone's boss as defeated for the player, syncs their data/leaderstats, and
-- re-checks zone unlocks (ZoneService.CheckUnlocks handles the "new zone!" notification).
local function markDefeated(player, data, zoneKey)
	if not hasDefeated(data, zoneKey) then
		table.insert(data.DefeatedBosses, zoneKey)
	end
	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.PushToClient(player)
	-- required lazily to avoid a circular require with ZoneService
	local ZoneService = require(script.Parent.ZoneService)
	ZoneService.CheckUnlocks(player, data)
end

local function spawnBoss(zone)
	local boss = zone.boss
	if not boss then return end

	local position = Vector3.new(zone.offset, 0, 0) + BOSS_RELATIVE_OFFSET + Vector3.new(0, boss.size * 0.55, 0)

	local model = Instance.new("Model")
	model.Name = "Boss_" .. zone.key

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(boss.size, boss.size, boss.size)
	body.Material = Enum.Material.Neon
	body.Color = zone.accentColor
	body.Anchored = true
	body.CanCollide = true
	body.CFrame = CFrame.new(position)
	body.Parent = model
	model.PrimaryPart = body

	-- crown marks it visually as a boss, distinct from regular creatures
	local crown = Instance.new("Part")
	crown.Name = "Crown"
	crown.Shape = Enum.PartType.Cylinder
	crown.Size = Vector3.new(1.4, boss.size * 0.4, boss.size * 0.4)
	crown.Orientation = Vector3.new(0, 0, 90)
	crown.Color = Color3.fromRGB(255, 215, 60)
	crown.Material = Enum.Material.Metal
	crown.Anchored = true
	crown.CanCollide = false
	crown.CFrame = body.CFrame * CFrame.new(0, boss.size * 0.62, 0)
	crown.Parent = model

	local eyeSize = boss.size * 0.16
	for _, side in ipairs({ -1, 1 }) do
		local eye = Instance.new("Part")
		eye.Name = side == -1 and "EyeL" or "EyeR"
		eye.Shape = Enum.PartType.Ball
		eye.Size = Vector3.new(eyeSize, eyeSize, eyeSize)
		eye.Color = Color3.fromRGB(255, 30, 30)
		eye.Material = Enum.Material.Neon
		eye.Anchored = true
		eye.CanCollide = false
		eye.CFrame = body.CFrame * CFrame.new(side * boss.size * 0.22, boss.size * 0.15, -boss.size * 0.46)
		eye.Parent = model
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 240, 0, 64)
	billboard.StudsOffset = Vector3.new(0, boss.size * 0.85, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 75
	billboard.Parent = body

	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.new(1, 0, 0, 14)
	barBg.Position = UDim2.new(0, 0, 1, -14)
	barBg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	barBg.BorderSizePixel = 0
	barBg.Parent = billboard

	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.Size = UDim2.new(1, 0, 1, 0)
	barFill.BackgroundColor3 = Color3.fromRGB(220, 40, 40)
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0, 28)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextSize = 16
	nameLabel.TextColor3 = Color3.fromRGB(255, 215, 60)
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.Text = "👑 " .. boss.emoji .. " " .. boss.name
	nameLabel.Parent = billboard

	local clickDetector = Instance.new("ClickDetector")
	clickDetector.MaxActivationDistance = 22
	clickDetector.Parent = body

	model:SetAttribute("Health", boss.health)
	model.Parent = bossesFolder

	local dead = false
	local lastHitByPlayer = {}
	local auraConnection

	if boss.auraRange and boss.auraRange > 0 then
		local accum = 0
		auraConnection = RunService.Heartbeat:Connect(function(dt)
			if dead or not model.Parent then return end
			accum += dt
			if accum < boss.auraInterval then return end
			accum = 0
			for _, plr in ipairs(Players:GetPlayers()) do
				local character = plr.Character
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				if hrp and (hrp.Position - body.Position).Magnitude <= boss.auraRange then
					hurtPlayer(plr, math.random(boss.auraDamage[1], boss.auraDamage[2]))
				end
			end
		end)
	end

	clickDetector.MouseClick:Connect(function(player)
		if dead or not model.Parent then return end
		local data = PlayerDataService.Get(player)
		if not data then return end
		if data.StageIndex < zone.unlockStageIndex then
			Remotes.Notify:FireClient(player, { kind = "error", message = "You're too weak for " .. boss.name .. " yet!" })
			return
		end
		local now = os.clock()
		if lastHitByPlayer[player.UserId] and now - lastHitByPlayer[player.UserId] < 0.25 then
			return
		end
		lastHitByPlayer[player.UserId] = now

		local playerDamage = DNAService.GetCombatDamage(data)
		local health = math.max((model:GetAttribute("Health") or boss.health) - playerDamage, 0)
		model:SetAttribute("Health", health)
		barFill.Size = UDim2.new(math.clamp(health / boss.health, 0, 1), 0, 1, 0)

		local grow = TweenService:Create(body, TweenInfo.new(0.08), { Size = Vector3.new(boss.size, boss.size, boss.size) * 1.06 })
		grow:Play()
		task.delay(0.08, function()
			if body and body.Parent then
				TweenService:Create(body, TweenInfo.new(0.1), { Size = Vector3.new(boss.size, boss.size, boss.size) }):Play()
			end
		end)

		if health > 0 and math.random() < boss.retaliateChance then
			hurtPlayer(player, math.random(boss.retaliateDamage[1], boss.retaliateDamage[2]))
		end

		if health <= 0 and not dead then
			dead = true
			if auraConnection then auraConnection:Disconnect() end

			data.DNA += boss.dnaReward
			data.XP = (data.XP or 0) + 25
			markDefeated(player, data, zone.key)
			Remotes.Notify:FireClient(player, { kind = "bossDefeated", name = boss.name, amount = boss.dnaReward })

			model:Destroy()
			task.delay(boss.respawnDelay or 45, function()
				spawnBoss(zone)
			end)
		end
	end)

	return model
end

function BossService.Init()
	for _, existing in ipairs(bossesFolder:GetChildren()) do
		existing:Destroy()
	end
	for _, zone in ipairs(GameConfig.Zones) do
		if zone.boss then
			spawnBoss(zone)
		end
	end
end

return BossService
