--[==[
	HeraldService -- the world boss that stands in the village, on the arena giant's own clock
	(22.4).

	===== WHAT THIS IS FOR =====

	Phase 22 is co-play, and its argument is that nothing in this game is a reason for two players
	to be on the same server. The Colosseum giant is the one thing that is -- it is far too much
	health for one player and it pays everybody who landed a blow rather than whoever finished it --
	and it is invisible: a teleport gate behind the spawn, into a separate map, on a half-hour
	timer. A player who has never walked through that gate has no idea it happens.

	So the giant gets a sibling standing where everybody already is. Same shared-target rules, same
	pay-everyone rule, no aura, no stage gate, and a live contribution board beside it.

	===== ONE CLOCK, NOT TWO =====

	The Herald does not keep a timer. It reads `BossService.EventSecondsToSpawn()` and arrives when
	the arena's next spawn is half an interval away, which makes the two exactly antiphase for as
	long as the server lives, with no second clock to drift and nothing to keep in step. The village
	therefore gets a world boss every fifteen minutes, alternating between the lawn and the
	Colosseum, and `BossLedger` -- which holds one fight -- is never asked about two.

	`ForceSpawn` exists for the same reason `BossService.ForceEventBoss` does: a fifteen-minute wait
	is not a test.

	===== THE FIGHT IS COUNTED IN BLOWS =====

	See `GameConfig.HubBoss`. Every blow is clamped into `health/maxBlows .. health/minBlows`, so
	the strongest player in the game and the newest are within 3.7x of each other on this one
	target, and the number of blows needed grows with the number of players present when it lands.
	That is what makes it a village fight rather than a race, and it is what makes the board's
	percentages mean "who turned up" instead of "who is furthest ahead".

	===== IT BORROWS THE RIG, IT DOES NOT COPY IT =====

	`BossService.Rig` is a small seam exposing the pieces this needs -- the rig factory, the idle
	driver, the VFX pass, the death burst, the damage cap and the auto-attack handler table. The
	alternative was a second copy of `spawnEventBoss`'s 250 lines, which would then have to be kept
	in step with it for ever. Registering in the same `hitHandlers` table is also what gives this
	boss auto-attack for free: `BossService.Init` already routes that remote through it.
]==]

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = RS.Remotes

local GameConfig = require(RS.Modules.GameConfig)
local UITheme = require(RS.Modules.UITheme)
local VFXLibrary = require(RS.Modules.VFXLibrary)

local PlayerDataService = require(script.Parent.Parent.PlayerDataService)
local DNAService = require(script.Parent.Parent.DNAService)
local Telemetry = require(script.Parent.Parent.Telemetry)
local SeasonPassService = require(script.Parent.Parent.SeasonPassService)
local CommunityGoalService = require(script.Parent.Parent.CommunityGoalService)
local AnnounceService = require(script.Parent.Parent.AnnounceService)
-- No cycle: `BossService` requires this file's siblings (`BossLedger`) but never this one.
local BossService = require(script.Parent.Parent.BossService)

local BossLedger = require(script.Parent.BossLedger)
local HeraldStation = require(script.Parent.HeraldStation)
local HeraldBoard = require(script.Parent.HeraldBoard)

local HeraldService = {}

local LEDGER_KEY = "hub"
local MODEL_NAME = "Boss_Herald"

local state = {
	model = nil,
	station = nil,
	armed = false,   -- true once the arena clock has passed the half-interval mark again
	blows = 0,       -- how many blows this Herald needs, fixed at spawn from the player count
}

-- ============================================================================
-- THE SYNTHETIC ZONE
-- ============================================================================
-- All a rig needs is a table with a palette, an offset and a boss on it -- the same trick
-- `eventZone` plays for the Colosseum. `offset` is what the edge clamp and the palette read.
local function heraldZone()
	local cfg = GameConfig.HubBoss
	return {
		key = "HubBoss",
		name = cfg.name,
		emoji = cfg.emoji,
		offset = 0,
		accentColor = cfg.accentColor,
		groundColor = cfg.groundColor,
		unlockStageIndex = cfg.minStageIndex,
		boss = cfg,
		rigKey = cfg.rigKey,
	}
end

-- ============================================================================
-- REWARD
-- ============================================================================
-- What one contributor is paid: their OWN zone's boss reward, once. See the note in
-- `GameConfig.HubBoss` for why it is not a flat figure. The event multiplier applies for the same
-- reason it applies to the giant -- the weekend Colosseum window doubles both siblings, and a
-- window that only pays out in the room nobody can see is the failure this row exists to fix.
local function payoutFor(data)
	local index = math.clamp(data.StageIndex or 1, 1, #GameConfig.Zones)
	local zone = GameConfig.Zones[index]
	local boss = zone and zone.boss
	if not boss then return 0, 0 end
	return boss.dnaReward or 0, boss.xpReward or 25
end

-- ============================================================================
-- SPAWN
-- ============================================================================
local function despawn()
	if state.model then
		BossService.Rig.ClearHit(state.model)
		if state.model.Parent then state.model:Destroy() end
	end
	state.model = nil
end

local function announce(headline, subline, colour, sound)
	AnnounceService.Broadcast({
		kind = "colosseum",
		color = colour or GameConfig.HubBoss.accentColor,
		headline = headline,
		subline = subline or "",
		sound = sound,
	})
end

function HeraldService.Spawn()
	despawn()

	-- The station is normally built by `Init`. Re-`Ensure`d rather than refused if it is missing,
	-- because `Ensure` is idempotent and a boss with nowhere to stand is a worse answer than a
	-- rebuilt plinth -- a stamp bump or a deleted model would otherwise silently end the feature.
	local station = state.station
	if not station or not station.model or not station.model.Parent then
		station = HeraldStation.Ensure()
		state.station = station
	end
	if not station then return nil end

	local cfg = GameConfig.HubBoss
	local zone = heraldZone()
	local Rig = BossService.Rig

	-- MORE CHALLENGERS, A BIGGER BOSS. Fixed at spawn rather than recomputed per blow: a player
	-- joining mid-fight must not make the bar the others are watching jump backwards.
	local present = math.max(#Players:GetPlayers(), 1)
	state.blows = cfg.minBlows * (1 + cfg.perPlayerBlows * (present - 1))

	local centre = station.centre
	-- The rig is lifted the same way `spawnBoss` lifts one: its own arena furniture is authored
	-- against `-size * 0.55` so that the dais lands on the floor the boss is standing on.
	local position = centre + Vector3.new(0, cfg.size * 0.55, 0)
	-- Facing the spawn pad, which is due south of here. A boss that arrives with its back to the
	-- village is a boss nobody can see the face of from the one place everybody stands.
	local origin = CFrame.lookAt(position, position + Vector3.new(0, 0, -1))

	local model = Instance.new("Model")
	model.Name = MODEL_NAME

	local body, atts, top = Rig.Build(model, origin, zone, cfg)

	local outline = Instance.new("Highlight")
	outline.Name = "Outline"
	outline.FillTransparency = 1
	outline.OutlineColor = Color3.fromRGB(20, 14, 28)
	outline.OutlineTransparency = 0
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Enabled = false
	outline.Parent = model
	Rig.Register(model, origin, atts, outline)

	-- Squared off and unrotated, the same reason every other boss's hit box is: a box that follows
	-- the rig's yaw makes the reach a function of which way it happens to be looking.
	local boxCF, boxSize = model:GetBoundingBox()
	local span = math.max(boxSize.X, boxSize.Z)
	local hitbox = Instance.new("Part")
	hitbox.Name = "HitBox"
	hitbox.Size = Vector3.new(span, boxSize.Y, span)
	hitbox.CFrame = CFrame.new(boxCF.Position)
	hitbox.Transparency = 1
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanTouch = false
	hitbox.CanQuery = true
	hitbox.Parent = model

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BossPlate"
	billboard.Size = UDim2.new(0, 228, 0, 84)
	billboard.StudsOffset = Vector3.new(0, top + cfg.size * 0.2, 0)
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.MaxDistance = 620
	billboard.Parent = body

	UITheme.Card(billboard, {
		name = "NamePlate",
		size = UDim2.new(1, -10, 0, 66),
		position = UDim2.new(0.5, 0, 0, 0),
		anchorPoint = Vector2.new(0.5, 0),
		color = cfg.accentColor,
		icon = "\u{2694}\u{FE0F}",
		text = cfg.emoji .. " " .. cfg.name,
		maxTextSize = 28,
	})

	local _, barFill, barLabel = UITheme.ProgressBar(billboard, {
		name = "HealthBar",
		size = UDim2.new(1, -26, 0, 42),
		position = UDim2.new(0.5, 0, 1, -4),
		anchorPoint = Vector2.new(0.5, 1),
		color = cfg.accentColor,
		progress = 1,
		text = Rig.Format(cfg.health) .. " / " .. Rig.Format(cfg.health),
		maxTextSize = 22,
	})

	local clickDetector = Instance.new("ClickDetector")
	clickDetector.MaxActivationDistance = math.max(60, cfg.size * 1.1)
	clickDetector.Parent = hitbox

	model:SetAttribute("Health", cfg.health)
	model.Parent = Rig.Folder
	state.model = model

	local vfxAtts = Rig.VFX(body, { key = zone.rigKey, accentColor = cfg.accentColor }, cfg, top)

	BossLedger.Open({
		key = LEDGER_KEY,
		name = cfg.name,
		emoji = cfg.emoji,
		where = "here in the village",
		max = cfg.health,
	})

	local dead = false
	local lastHitByPlayer = {}
	local contributors = {}
	local restSize = body.Size
	local strikeReach = math.max(80, cfg.size * 1.3)

	local function onHit(player)
		if dead or not model.Parent then return end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not (humanoid and hrp) or humanoid.Health <= 0 then return end
		if (hrp.Position - body.Position).Magnitude > strikeReach then return end
		local data = PlayerDataService.Get(player)
		if not data then return end
		if (data.StageIndex or 1) < cfg.minStageIndex then return end

		local now = os.clock()
		if lastHitByPlayer[player.UserId] and now - lastHitByPlayer[player.UserId] < 0.25 then return end
		lastHitByPlayer[player.UserId] = now
		contributors[player.UserId] = true

		-- The clamp that is the whole fight. Floor and ceiling both, and both derived from the
		-- blow counts rather than typed: see `GameConfig.HubBoss`.
		local ceiling = cfg.health / math.max(state.blows, 1)
		local floor = cfg.health / math.max(cfg.maxBlows * (state.blows / cfg.minBlows), 1)
		local playerDamage = math.clamp(DNAService.GetCombatDamage(data), floor, ceiling)

		local health = math.max((model:GetAttribute("Health") or cfg.health) - playerDamage, 0)
		model:SetAttribute("Health", health)
		barFill.Size = UDim2.new(math.clamp(health / cfg.health, 0, 1), 0, 1, 0)
		barLabel.Text = Rig.Format(health) .. " / " .. Rig.Format(cfg.health)

		BossLedger.Hit(LEDGER_KEY, player, playerDamage)
		BossLedger.SetHealth(LEDGER_KEY, health)

		Rig.Fx:FireClient(player, {
			k = "bossBar",
			name = cfg.emoji .. " " .. cfg.name,
			hp = health,
			max = cfg.health,
		})

		TweenService:Create(body, TweenInfo.new(0.08), { Size = restSize * 1.05 }):Play()
		task.delay(0.08, function()
			if body and body.Parent then
				TweenService:Create(body, TweenInfo.new(0.1), { Size = restSize }):Play()
			end
		end)
		for _, att in ipairs(vfxAtts) do
			VFXLibrary.Burst(att, 8)
		end

		-- the swing, the spark and the damage number on every nearby client, exactly as both other
		-- boss paths draw them
		local knockDir = Vector3.new(0, 0, 1)
		local flat = Vector3.new(body.Position.X - hrp.Position.X, 0, body.Position.Z - hrp.Position.Z)
		if flat.Magnitude > 0.1 then knockDir = flat.Unit end
		Rig.Broadcast({
			k = health > 0 and "hit" or "kill",
			p = body.Position - knockDir * (cfg.size * 0.4),
			d = math.floor(playerDamage + 0.5),
			a = player.UserId,
			s = math.min(cfg.size * 0.5, 34),
			c = UITheme.Color.Gold,
			n = knockDir,
		})

		if health > 0 and math.random() < cfg.retaliateChance then
			-- `state.blows` is the honest denominator here: it is what this player is actually
			-- being asked to land, so the incoming cap is measured against the real fight length.
			Rig.Hurt(player, math.random(cfg.retaliateDamage[1], cfg.retaliateDamage[2]),
				math.max(1, math.ceil(state.blows)))
		end

		if health <= 0 and not dead then
			dead = true
			local paid = 0
			local eventMult = GameConfig.GetEventMult("bossMult")
			for _, plr in ipairs(Players:GetPlayers()) do
				if contributors[plr.UserId] then
					local d = PlayerDataService.Get(plr)
					if d then
						local dna, xp = payoutFor(d)
						dna = math.floor(dna * eventMult)
						d.DNA += dna
						Telemetry.Accrue(plr, "Source", Telemetry.Currency.DNA, dna,
							Telemetry.Tx.Gameplay, "hubBoss")
						d.XP = (d.XP or 0) + math.floor(xp * GameConfig.GetXPMult(d))
						local gems = math.floor(GameConfig.RollBossDiamonds(false) * eventMult)
						d.Diamonds = (d.Diamonds or 0) + gems
						Telemetry.Accrue(plr, "Source", Telemetry.Currency.Diamonds, gems,
							Telemetry.Tx.Gameplay, "hubBoss")
						-- 20.3's co-play metric, one event per CONTRIBUTOR: the question it answers
						-- is "how many people took part", and this boss is the half of it that the
						-- Colosseum could never measure because nobody could see the Colosseum.
						Telemetry.Custom(plr, "WorldBossContribution", gems)
						SeasonPassService.Track(plr, "bosses", 1)
						d.Kills = (d.Kills or 0) + 1
						CommunityGoalService.AddProgress(1)
						DNAService.AutoEvolveIfReady(plr)
						PlayerDataService.UpdateLeaderstats(plr)
						PlayerDataService.PushToClient(plr)
						Remotes.Notify:FireClient(plr, {
							kind = "bossDefeated", name = cfg.name, amount = dna, diamonds = gems,
						})
						paid += 1
					end
				end
			end

			BossLedger.SetHealth(LEDGER_KEY, 0)
			BossLedger.Close(LEDGER_KEY, ("%d challenger%s paid"):format(paid, paid == 1 and "" or "s"))
			announce(
				("%s %s HAS FALLEN!"):format(cfg.emoji, cfg.name:upper()),
				("%d challenger%s paid"):format(paid, paid == 1 and "" or "s"),
				UITheme.Color.Coral)

			Rig.Burst(Rig.Folder, zone, cfg, body.Position)
			despawn()
		end
	end

	clickDetector.MouseClick:Connect(function(player)
		-- 24.4: a thief carrying a specimen has no free hand for the sword (`VivariumSteal`)
		if player:GetAttribute("HandsFull") then return end
		onHit(player)
	end)
	Rig.SetHit(model, { fn = onHit, body = body, reach = strikeReach })

	announce(
		("%s %s IS IN THE VILLAGE!"):format(cfg.emoji, cfg.name:upper()),
		"By the Colosseum gate -- every hit is paid",
		cfg.accentColor, "levelUp")

	task.delay(cfg.despawnSeconds, function()
		if state.model == model and not dead then
			despawn()
			BossLedger.Close(LEDGER_KEY, "nobody finished it")
			announce(
				("%s %s HAS WITHDRAWN"):format(cfg.emoji, cfg.name:upper()),
				"The Colosseum is next -- watch the board",
				UITheme.Color.Locked)
		end
	end)

	return model
end

-- Exposed for testing, exactly as `BossService.ForceEventBoss` is: a fifteen-minute wait is not a
-- test. It does NOT disarm the cycle -- the next natural arrival still happens on the arena's
-- clock -- because a forced spawn is an extra Herald, not a replacement for one.
function HeraldService.ForceSpawn()
	return HeraldService.Spawn()
end

-- ============================================================================
-- THE TICK
-- ============================================================================
-- One second, the same cadence `BossService.driveCountdown` runs at and for the same reason: the
-- board draws mm:ss and nothing here needs to be smoother than the smallest thing it shows.
local function tick()
	local cfg = GameConfig.HubBoss
	local interval = GameConfig.EventBoss.intervalSeconds
	local arenaLeft = BossService.EventSecondsToSpawn()
	local half = interval * 0.5

	-- ANTIPHASE, WITHOUT A SECOND CLOCK. `armed` goes true while the arena's next spawn is still
	-- more than half an interval away, and the Herald lands the moment it is not. One boolean is
	-- what stops a spawn every second for the whole of the second half of the cycle.
	if arenaLeft > half then
		state.armed = true
	elseif state.armed and not state.model then
		state.armed = false
		local ok, err = pcall(HeraldService.Spawn)
		if not ok then warn("[HeraldService] spawn failed: " .. tostring(err)) end
	elseif state.armed and state.model then
		-- A Herald that is still standing when its slot comes round again does not get a second
		-- one; the slot is simply spent.
		state.armed = false
	end

	if state.station and (not state.station.model or not state.station.model.Parent) then
		state.station = HeraldStation.Ensure()
	end

	local snap = BossLedger.Snapshot()
	local nextUp
	if not snap then
		-- Whichever of the two arrives next, named. The Herald's own arrival is half an interval
		-- before the arena's, so `arenaLeft - half` is its countdown while it is still to come.
		local heraldLeft = arenaLeft - half
		if heraldLeft > 0 then
			nextUp = { emoji = cfg.emoji, name = cfg.name, where = "here, by the Colosseum gate", seconds = heraldLeft }
		else
			local boss = GameConfig.EventBoss
			nextUp = { emoji = boss.emoji, name = boss.name, where = "in the Colosseum, through the gate", seconds = arenaLeft }
		end
	end
	HeraldBoard.Draw(state.station and state.station.board, snap, nextUp)
end

function HeraldService.Init()
	state.station = HeraldStation.Ensure()
	print(("[HeraldService] station at %d, %d, %d (v%d)"):format(
		HeraldStation.Centre.X, HeraldStation.Centre.Y, HeraldStation.Centre.Z, HeraldStation.Version))

	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(tick)
			if not ok then warn("[HeraldService] tick failed: " .. tostring(err)) end
		end
	end)
end

return HeraldService
