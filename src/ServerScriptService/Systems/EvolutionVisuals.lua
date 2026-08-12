local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local GameConfig = require(RS.Modules.GameConfig)
local StageCostume = require(RS.Modules.StageCostume)
local PlayerDataService = require(script.Parent.Parent.PlayerDataService)

local EvolutionVisuals = {}

-- ===== INTERNALS =====

local function getOrCreate(parent, className, name)
	local existing = parent:FindFirstChild(name)
	if existing then return existing end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = parent
	return inst
end

-- Builds (or fetches) the persistent aura attached to a character's HumanoidRootPart:
-- a soft glow light + a slow-rising particle trail, both tinted to the stage color.
local function setupAura(character, stage, stageIndex)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local light = getOrCreate(root, "PointLight", "EvolutionAuraLight")
	light.Color = stage.color
	light.Range = 6 + stageIndex * 1.2
	light.Brightness = 1 + stageIndex * 0.35
	light.Shadows = false

	local attachment = getOrCreate(root, "Attachment", "EvolutionAuraAttachment")

	local particle = attachment:FindFirstChild("EvolutionAuraParticle")
	if not particle then
		particle = Instance.new("ParticleEmitter")
		particle.Name = "EvolutionAuraParticle"
		particle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		particle.Parent = attachment
	end
	particle.Color = ColorSequence.new(stage.color)
	particle.Lifetime = NumberRange.new(0.6, 1.1)
	particle.Rate = 4 + stageIndex * 2
	particle.Speed = NumberRange.new(1, 2 + stageIndex * 0.3)
	particle.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15 + stageIndex * 0.03),
		NumberSequenceKeypoint.new(1, 0),
	})
	particle.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	particle.SpreadAngle = Vector2.new(180, 180)
	particle.Enabled = true

	return attachment, particle
end

-- One-shot burst of particles + light flash played at the moment of evolving.
local function playEvolveBurst(character, stage, stageIndex)
	local attachment = character:FindFirstChild("HumanoidRootPart") and character.HumanoidRootPart:FindFirstChild("EvolutionAuraAttachment")
	if not attachment then return end
	local particle = attachment:FindFirstChild("EvolutionAuraParticle")
	if particle then
		local burst = particle:Clone()
		burst.Name = "EvolutionBurst"
		burst.Rate = 0
		burst.Lifetime = NumberRange.new(0.5, 0.9)
		burst.Speed = NumberRange.new(6, 12)
		burst.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5 + stageIndex * 0.05),
			NumberSequenceKeypoint.new(1, 0),
		})
		burst.Parent = attachment
		burst:Emit(35 + stageIndex * 6)
		game:GetService("Debris"):AddItem(burst, 2)
	end

	local light = character.HumanoidRootPart:FindFirstChild("EvolutionAuraLight")
	if light then
		local flash = TweenService:Create(light, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Brightness = (1 + stageIndex * 0.35) * 4,
		})
		flash:Play()
		task.delay(0.5, function()
			if light and light.Parent then
				TweenService:Create(light, TweenInfo.new(0.6), { Brightness = 1 + stageIndex * 0.35 }):Play()
			end
		end)
	end
end

-- Tweens (or instantly sets) the Humanoid's body scale values to match the stage.
-- On R15 rigs these live as NumberValue children of the Humanoid (BodyHeightScale,
-- BodyWidthScale, BodyDepthScale, HeadScale) rather than as plain settable properties,
-- so we animate/set the child's .Value instead of indexing the Humanoid directly.
local SCALE_PROPS = { "BodyHeightScale", "BodyWidthScale", "BodyDepthScale", "HeadScale" }

-- ...and NOT all to the same number. Setting the four equal is just a bigger default Roblox avatar:
-- tall, narrow, small-headed. Every other character in this game -- the pets, the creatures, the
-- bosses -- is short, wide and big-headed, so a player standing next to their own pet looked like
-- they had walked in from a different game.
--
-- These are per-axis multipliers ON TOP of the stage's own scale, so the 1x -> 9x growth curve is
-- untouched and only the shape changes. StageCostume's body shells are welded to the limbs, so
-- they inherit all of it for free.
-- Tuned against screenshots. 0.82 / 1.28 / 1.55 was the first pass and overshot: the head ate
-- nearly half the character and the legs vanished under the chest. Short and wide, not squashed.
-- ONE GLOBAL DIAL FOR HOW BIG A PLAYER IS. Stage 1 shipped at scale 1.0 -- a default Roblox
-- avatar -- in a world where the boss is 117 studs, the zone walls are 140 and the Guardian Titan
-- is 507. Everything around the player is authored huge, so the player read as tiny even at Wolf
-- (1.8). Applied here rather than by editing twenty `stage.scale` values because those numbers are
-- the SHAPE of the progression -- the ratios between stages are deliberate, and this moves all of
-- them together without touching a single one of them.
--
-- Everything downstream is derived, so nothing else needs changing: the costume shells are sized
-- off the limbs they hang on, and walk speed already scales with the body.
local PLAYER_SCALE_BOOST = 1.45

local PROPORTION = {
	BodyHeightScale = 0.92,
	BodyWidthScale = 1.22,
	BodyDepthScale = 1.22,
	HeadScale = 1.32,
}

-- Grants more max HP per stage, so evolving makes you tougher to match the harder-hitting
-- creatures in later zones, not just stronger on offense (see DNAService.GetCombatDamage).
-- `healthMult` folds in permanent Stage Mastery unlocks on top of the stage curve.
local function applyMaxHealth(humanoid, stageIndex, heal, healthMult)
	local targetMax = math.floor((100 + (stageIndex - 1) * 40) * (healthMult or 1))
	if humanoid.MaxHealth ~= targetMax then
		local wasFull = humanoid.Health >= humanoid.MaxHealth - 0.5
		humanoid.MaxHealth = targetMax
		if heal or wasFull then
			humanoid.Health = targetMax
		end
	end
end

-- Stage Mastery raises walk speed and max health. Both live on the Humanoid, which is replaced
-- on every respawn with engine defaults, so this has to run on spawn as well as at purchase time.
local function applyMastery(character, data)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not (humanoid and data) then return end
	local bonus = GameConfig.GetStageMasteryBonus(data)

	-- Pace is measured against the body, not in absolute studs. ApplyStage stamps the stage's scale
	-- on the character before calling this; a character that has somehow not been through it yet
	-- (an early respawn frame) falls back to 1 and simply runs at the base speed.
	local bodyScale = character:GetAttribute("BodyScale") or 1
	local sizeMult = GameConfig.GetSizeSpeedMultiplier and GameConfig.GetSizeSpeedMultiplier(bodyScale) or 1

	-- The Speed upgrade is added here, alongside Stage Mastery's own walk bonus -- this is the one
	-- place in the game that writes WalkSpeed, and the client's sprint reads whatever it finds.
	-- The 2x Speed pass multiplies the whole thing AND lifts the ceiling, because against the normal
	-- cap of 150 it would not be a 2x for most of the game: an unbought stage-20 body already runs
	-- 127, so the doubling was landing as 1.18x at the top and was a true 2x only through stage 7 of
	-- 20. MaxWalkSpeed is not a balance number -- it is the speed past which a player outruns
	-- StreamingEnabled -- so the raised ceiling is a measured decision (260 covers the doubled top
	-- stage at 254.5 with a little headroom), not a default. Nobody without the pass moves any faster.
	humanoid.WalkSpeed = math.min(
		(GameConfig.BaseWalkSpeed + bonus.walkSpeed + GameConfig.GetSpeedUpgradeBonus(data))
			* sizeMult * GameConfig.GetPassMult(data, "walkMult"),
		GameConfig.GetPassMax(data, "walkCap", GameConfig.MaxWalkSpeed or 120)
	)
	-- R15 characters default to JumpHeight, not JumpPower, so setting JumpPower alone is silently
	-- ignored -- UseJumpPower has to be flipped first or the jump bonus never lands.
	humanoid.UseJumpPower = true
	-- Jump takes the size boost at a lower power than the walk. Jump HEIGHT goes as the square of
	-- jump power, so scaling power with the body one-for-one makes a giant leap several of its own
	-- heights -- at 0.5 the height stays a roughly constant multiple of the body all the way up.
	humanoid.JumpPower = math.min(
		((GameConfig.BaseJumpPower or 50) + (bonus.jumpPower or 0)) * (sizeMult ^ 0.5),
		GameConfig.MaxJumpPower or 170
	)
	-- THE WORN SKIN CARRIES HEALTH, NOT ONLY DAMAGE. A character's rank in the collection paid
	-- +3% damage a rung and no health at all, so a rank-200 skin was strictly an attack stat and
	-- wearing something you liked from further back cost you damage and bought you nothing. Folded
	-- in MULTIPLICATIVELY with Stage Mastery, exactly the way the damage side stacks.
	--
	-- ...and the health POTION is the fourth term (11.8). It multiplies into the same product rather
	-- than setting MaxHealth itself, which is the whole reason the row chose a multiplier: max health
	-- already climbs with the stage, with Stage Mastery and with the worn skin's rank, and a bottle
	-- that assigned an absolute number would be a downgrade at stage 15 and a cheat at stage 1.
	--
	-- Because the term can go away on its own, THIS FUNCTION IS ALSO THE UNDO. `GetPotionHealthMult`
	-- returns 1 the moment the boost lapses, so re-running this after expiry restores the exact
	-- number the other three terms produce -- nothing has to remember what the bottle added.
	-- PotionService drives both edges; see the transition poll there.
	applyMaxHealth(humanoid, data.StageIndex or 1, false,
		(bonus.healthMult or 1) * GameConfig.GetCharacterHealthMult(data)
			* GameConfig.GetPotionHealthMult(data))
end

local function applyScale(character, targetScale, animate, healthMult)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	applyMaxHealth(humanoid, character:GetAttribute("StageIndexForHealth") or 1, animate, healthMult)
	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then return end

	-- 0 is the "classic" blocky build, 1 is Roblox's slim proportioned one. The whole art direction
	-- here is blocky, and this is free -- it costs one value and reshapes every limb.
	local proportion = humanoid:FindFirstChild("BodyProportionScale")
	if proportion then
		proportion.Value = 0
	end

	for _, propName in ipairs(SCALE_PROPS) do
		local scaleValue = humanoid:FindFirstChild(propName)
		if scaleValue then
			local target = targetScale * PLAYER_SCALE_BOOST * (PROPORTION[propName] or 1)
			if animate then
				TweenService:Create(scaleValue, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Value = target,
				}):Play()
			else
				scaleValue.Value = target
			end
		end
	end
end

-- ===== THE COSTUME CANNOT BE BUILT ON A BODY THAT IS STILL CHANGING SIZE =====
--
-- This is the "I spawn in looking wrong, then I change skin and it is fine, and switching back to
-- the FIRST skin now also looks fine" bug, and the asymmetry is the whole clue: changing a skin
-- happens on a body that has been standing there for minutes, spawning happens on one that is
-- still being assembled.
--
-- Both halves of the wardrobe are sized and welded against the R15 limbs as they measure AT THE
-- MOMENT OF THE CALL. StageCostume reads `torso.Size` / `head.Size` for every shell; SkinMesh
-- scales the whole generated model by the limb bounding box's height and then welds each segment
-- with `C0 = host.CFrame:Inverse() * part.CFrame`. A weld keeps the offset it was given -- so if
-- the limbs move or resize afterwards, the pieces keep the arrangement they were welded at while
-- their hosts travel out from under them. That is exactly what the screenshot shows: the skin's
-- head floating clear of a body it is no longer attached to the top of.
--
-- Two things resize the limbs a few frames AFTER CharacterAdded, and both land on a spawn only:
--
--   * `applyScale` above writes BodyHeightScale / BodyWidthScale / BodyDepthScale / HeadScale.
--     Those are NumberValues -- the engine acts on them on a later simulation step, not on the
--     assignment. At stage 3 that is a 1.0 body becoming a 2.6 one, under a costume already built.
--   * Roblox is still applying the player's own HumanoidDescription (their avatar's body parts and
--     packages), which it finishes at its own pace after the character has been parented in.
--
-- So the fix is not a fixed delay -- it is to WAIT UNTIL THE BODY HAS STOPPED MOVING. Two
-- consecutive Heartbeats with identical limb measurements means whatever was going to resize has
-- resized. In the common case that is three or four frames, which nobody sees; the timeout is
-- there so a character that never settles (an avatar that failed to load) still gets dressed.
local function bodyProbe(character)
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	local head = character:FindFirstChild("Head")
	if not (torso and head) then return nil end
	-- the three axes and both limbs, weighted by primes so two different bodies cannot sum equal
	return torso.Size.X + torso.Size.Y * 3 + torso.Size.Z * 5 + head.Size.X * 7 + head.Size.Y * 11
end

-- SIZE IS ONLY HALF OF "SETTLED", AND THE OTHER HALF IS THE POSE.
--
-- `SkinMesh.Apply` welds with `weld.C0 = host.CFrame:Inverse() * part.CFrame` -- built out of WORLD
-- CFrames, so the offset it stores is the one the limbs happen to hold at that instant. A weld keeps
-- what it was given: dress a character mid-stride and the arms are welded into that stride forever,
-- dress one in the air and the legs stay in the jump. That is one of the two things that reads as
-- "the skins glitch", and no amount of waiting for the SIZE to stop changing catches it -- a running
-- body has a perfectly stable size.
--
-- So the wait is now for size AND pose: no movement input, and not in Freefall. Both from the
-- Humanoid, which is the only thing that knows the difference between standing still and being
-- pushed. `Running` at zero MoveDirection is standing; `Freefall` is a jump, a fall or a ledge.
--
-- ONE TIMEOUT COVERS BOTH, deliberately. A player who holds W through the whole animation still has
-- to be dressed -- a slightly bent skin is a far smaller failure than no skin at all, which is what
-- an unbounded wait would produce for anyone who never stands still.
local function poseSettled(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return true end
	if humanoid.MoveDirection.Magnitude > 1e-3 then return false end
	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Freefall
		or state == Enum.HumanoidStateType.Jumping
		or state == Enum.HumanoidStateType.Landed then
		return false
	end
	return true
end

local function waitForBodySettled(character, timeout)
	local waited, stable, last = 0, 0, nil
	timeout = timeout or 2
	while waited < timeout do
		local probe = bodyProbe(character)
		if not probe then return end
		if last and math.abs(probe - last) < 1e-4 and poseSettled(character) then
			stable += 1
			if stable >= 2 then return end
		else
			stable = 0
		end
		last = probe
		waited += RunService.Heartbeat:Wait()
	end
end

-- ===== PUBLIC API =====

-- Applies the full visual package (scale + aura) for a player's current stage.
-- opts.animate: tween the scale change instead of snapping (use for live evolves)
-- opts.burst: play a one-shot particle/light burst (use for live evolves, not initial spawn)
function EvolutionVisuals.ApplyStage(player, stageIndex, opts)
	opts = opts or {}
	local character = player.Character
	-- BOTH OF THESE USED TO BE SILENT, and between them they are the top of the skin path: nothing
	-- below runs, so the player keeps a stock avatar with no costume and no error to explain it.
	-- See the note on StageCostume.Apply for why that particular silence is expensive.
	if not character then
		warn(("[EvolutionVisuals] %s has no character -- stage %s visuals skipped"):format(player.Name, tostring(stageIndex)))
		return
	end
	local stage = GameConfig.Stages[stageIndex]
	if not stage then
		warn(("[EvolutionVisuals] %s: stage index %s is not in GameConfig.Stages"):format(player.Name, tostring(stageIndex)))
		return
	end

	character:WaitForChild("HumanoidRootPart", 5)
	if not character:FindFirstChild("HumanoidRootPart") then
		warn(("[EvolutionVisuals] %s: no HumanoidRootPart after 5s -- stage %d visuals skipped"):format(player.Name, stageIndex))
		return
	end

	character:SetAttribute("StageIndexForHealth", stageIndex)
	-- Read back by applyMastery (pace scales with the body) and by the client's floating health bar,
	-- which has to hang above a head that is anywhere from 1 to 9 times its default height.
	character:SetAttribute("BodyScale", stage.scale)
	setupAura(character, stage, stageIndex)

	local data = PlayerDataService.Get(player)
	local bonus = data and GameConfig.GetStageMasteryBonus(data)
	-- same product as applyMastery below -- stage mastery times the worn skin's own rank bonus.
	-- Both call sites have to agree or the two paths fight over MaxHealth on every respawn.
	applyScale(character, stage.scale, opts.animate,
		(bonus and bonus.healthMult or 1) * (data and GameConfig.GetCharacterHealthMult(data) or 1))
	if data then
		applyMastery(character, data)
	end

	-- WHICH of the stage's five characters is being worn. A stage's own `color` is the fallback
	-- and stays the look of a player who has not rolled anything for this stage yet -- so a save
	-- from before the Journal existed is unchanged rather than blank.
	-- keyed by tostring(stageIndex): a sparse numeric-keyed table does not survive a RemoteEvent,
	-- so the save uses string keys throughout -- see DNAService.RollCharacter
	local entry = GameConfig.GetWornCharacter(data)

	-- THE LOOK COMES FROM THE SKIN, THE SIZE COMES FROM THE STAGE.
	--
	-- Any character can be worn at any time now, so the two have come apart: a player standing at
	-- Gorilla wearing a Worm looks like a worm -- a Gorilla-sized one. Building the Gorilla's
	-- costume and tinting it worm-coloured, which is what this did when a character was only a
	-- colour, would mean the two hundred characters were still twenty silhouettes.
	local lookIndex = (entry and entry.stage) or stageIndex
	local lookStage = GameConfig.Stages[lookIndex] or stage
	-- Stamped on the character rather than passed only to StageCostume: the client's own rebuilds
	-- (StageCostume runs on every machine) have no access to the owner's save data, and an attribute
	-- replicates to all of them.
	character:SetAttribute("CharacterKey", entry and entry.key or nil)

	-- The stage's costume. Every piece of it is welded and sized off the limb it hangs on, so it
	-- has to be rebuilt AFTER the body has finished changing size -- a weld keeps the offset it
	-- was given, and a costume built mid-tween stays the size the body was passing through.
	-- applyScale tweens over 0.6s (see SCALE_PROPS), hence the delay when animating; the settle
	-- wait above covers the un-animated path, where the resize is instant to us and several frames
	-- away as far as the engine is concerned.
	-- THE GENERATION TOKEN, AND WHY "SAME CHARACTER" WAS NOT ENOUGH.
	--
	-- `dress` sleeps for up to two seconds inside `waitForBodySettled`. The only guard it had was
	-- "is this still the same character", which two overlapping calls both pass -- so equipping skin
	-- A and then skin B within that window started two coroutines against one body, and whichever
	-- woke last won. The evolve path makes it worse rather than better: it delays 0.7s, so against a
	-- live equip the STALE data has a head start and the player ends up wearing the older skin, with
	-- nothing in the console to say so.
	--
	-- A monotonic counter on the character settles it: every ApplyStage claims the next number, and a
	-- coroutine that wakes to find the number has moved is no longer the current dress and stops.
	-- An attribute rather than an upvalue because the state belongs to the BODY -- a fresh character
	-- starts at nil and therefore at 1, with no per-player table to clean up on leave.
	local generation = (character:GetAttribute("DressGeneration") or 0) + 1
	character:SetAttribute("DressGeneration", generation)

	local function dress()
		if not (character.Parent and player.Character == character) then return end
		if character:GetAttribute("DressGeneration") ~= generation then return end
		waitForBodySettled(character)
		if not (character.Parent and player.Character == character) then return end
		if character:GetAttribute("DressGeneration") ~= generation then return end

		-- READ THE WORN SKIN AGAIN, HERE, rather than using the `entry` captured above. The token
		-- above stops a stale dress that a newer ApplyStage has superseded; this covers the other
		-- half -- the save changing during the wait with no second ApplyStage behind it -- and it
		-- costs one table lookup. Between them, what lands on the body is what the save says now.
		local liveData = PlayerDataService.Get(player)
		local liveEntry = liveData and GameConfig.GetWornCharacter(liveData) or entry
		local liveIndex = (liveEntry and liveEntry.stage) or stageIndex
		local liveStage = GameConfig.Stages[liveIndex] or stage
		character:SetAttribute("CharacterKey", liveEntry and liveEntry.key or nil)
		StageCostume.Apply(character, liveIndex, liveStage, liveEntry)
	end

	if opts.animate then
		task.delay(0.7, dress)
	else
		task.spawn(dress)
	end

	if opts.burst then
		playEvolveBurst(character, stage, stageIndex)
	end
end

-- Pushes a freshly bought Stage Mastery onto the live character. Without this the speed and
-- health a player just spent Diamonds on would not show up until they next died.
function EvolutionVisuals.RefreshBonuses(player, data)
	local character = player.Character
	if not character then return end
	applyMastery(character, data or PlayerDataService.Get(player))
end

-- Hooks every player's character spawn to re-apply their current stage's visuals
-- (handles initial join, respawns after death, etc). Also exposes ApplyStage for
-- ServerMain to call directly right after a successful evolve.
function EvolutionVisuals.Init()
	local Players = game:GetService("Players")

	local function onCharacterAdded(player, character)
		task.spawn(function()
			local data
			local waited = 0
			repeat
				data = PlayerDataService.Get(player)
				if not data then
					task.wait(0.2)
					waited += 0.2
				end
			until data or waited > 5 or not player.Parent or character.Parent == nil
			if data and character.Parent then
				EvolutionVisuals.ApplyStage(player, data.StageIndex, { animate = false, burst = false })
			end
		end)
	end

	-- ===== A PLAYER WHO WAS ALREADY HERE GETS NO HOOK AT ALL =====
	--
	-- `PlayerAdded` only fires for players who join AFTER this line runs, and everything that dresses
	-- a character hangs off it -- so a player already in the game when `Init()` is reached never has
	-- `CharacterAdded` connected, and every spawn and respawn they make for the rest of that session
	-- arrives as a bare Roblox avatar. That is exactly the reported "I spawn as my normal avatar".
	--
	-- It is not a theoretical race. `ServerMain` requires and initialises a dozen services in order,
	-- and `ZoneBuilder` rebuilds twenty zones and pins 2,617 parts before this one is reached; the
	-- first player into a fresh server routinely wins that. The player who hits it is the FIRST one,
	-- which is also the one most likely to be a new player.
	--
	-- The standard shape fixes it: connect first, then sweep everyone already present. Connecting
	-- before the sweep rather than after is what makes the two halves not have a gap between them --
	-- a player joining mid-sweep is caught by the connection instead of being missed by both.
	local function hook(player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			onCharacterAdded(player, player.Character)
		end
	end

	Players.PlayerAdded:Connect(hook)
	for _, player in ipairs(Players:GetPlayers()) do
		hook(player)
	end
end

return EvolutionVisuals
