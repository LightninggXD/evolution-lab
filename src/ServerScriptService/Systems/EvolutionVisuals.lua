local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local GameConfig = require(RS.Modules.GameConfig)
local StageCostume = require(RS.Modules.StageCostume)
local VFXLibrary = require(RS.Modules.VFXLibrary)
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

-- ===== THE STAGE LIGHT IS AN INTENSITY, NOT A SIZE (17.19) ===================
--
-- `1 + stageIndex * 0.35` reaches **8.0** at stage 20 -- with `Range` 30 and `Shadows = false`, i.e.
-- a lamp three times brighter than the brightest thing ZoneBuilder puts in the world (4), shining
-- straight THROUGH the body it is parented inside and lighting all 39 studs of it from the middle
-- out. Every surface saturates, so the creature loses its shading and reads as one flat blob before
-- a single particle is drawn. This line has never been touched since the place was first extracted:
-- it was written when a player was a 1x Roblox avatar, and PLAYER_SCALE_BOOST plus twenty stages
-- have happened to it since.
--
-- The ladder is kept, the ceiling is new, and WHICH property carries the growth is the actual point:
--   * `Range` still climbs with the stage (6 -> 30) and should -- a bigger creature needs a bigger
--     pool of light around it, and at stage 20 the range only just reaches the feet (23.6 studs
--     below the root).
--   * `Brightness` does NOT, past 2.5. It is how hard a surface one stud away is lit; a surface does
--     not need to be lit harder because the creature carrying the lamp got taller. 2.5 sits above
--     VipFlair's own body light (1.6) and below ZoneBuilder's brightest scenery lamp (4), so the
--     max-stage flourish is still the brightest thing worn on a player in this game.
-- Stages 1-4 are untouched by the clamp (they were already under it); this only bites where the
-- report is.
-- 2.5 -> 1.8 with 31.11. Brightness is how hard the pool is painted and range is how far it
-- reaches; the range above is what fixes the flood, and this is what stops the smaller pool simply
-- being the same white in a tighter circle.
local AURA_LIGHT_MAX_BRIGHTNESS = 1.8

-- One formula, three call sites. It used to be written out three times -- here and twice inside
-- playEvolveBurst, which tweens UP from it and then back DOWN to it -- so changing it in one place
-- would have left an evolve permanently parking the light at the old value.
local function auraBrightness(stageIndex)
	return math.min(1 + stageIndex * 0.35, AURA_LIGHT_MAX_BRIGHTNESS)
end

-- ===== 31.11: THE LIGHT IS AN AURA, NOT A FLOODLIGHT =====
-- Every capture taken in the village on 2026-08-22 has the ground washed near-white for roughly
-- eighty studs around the player, and the roadmap row parked it as hers to decide. She decided:
-- *"smanji domet svetla"*, keep the colour and the sparkle.
--
-- THE PARTICLES WERE NEVER THE FAULT. `roblox-particle-tint-clipping` is the standing note that
-- Brightness and LightEmission are two different levers and that capping both ruins an effect, and
-- the emitters here are 5-9 studs, which is right against an 8.4-stud body. The wash is this
-- PointLight: `6 + stageIndex * 1.2` reaches Range 30 at the last stage, and a Range-30 light at
-- Brightness 2.5 lays a lit pool about sixty studs across on a flat green floor. Nothing about the
-- aura's SIZE says that -- a light's range is not its sprite's size, and only a screenshot connects
-- the two.
--
-- The ramp is NOT capped flat, for the reason 15.22 wrote down about Auto Collect: a curve that
-- stops a third of the way up sells eleven stages that buy nothing. It CONTINUES at a quarter of
-- the rate past stage 8, so the light still grows the whole way and lands at 17 instead of 30 --
-- about two body-heights of glow, which is a character who is lit rather than a lamp post.
local AURA_LIGHT_KNEE = 8

local function auraRange(stageIndex)
	local fast = math.min(stageIndex, AURA_LIGHT_KNEE)
	local slow = math.max(stageIndex - AURA_LIGHT_KNEE, 0)
	return 6 + fast * 1.0 + slow * 0.25
end

-- Builds (or fetches) the persistent aura attached to a character's HumanoidRootPart:
-- a soft glow light + a slow-rising particle trail.
--
-- `color` is the WORN CHARACTER's colour, with the stage's own as the fallback -- the same
-- `entry.color or stage.color` expression StageCostume.Apply uses to paint the body, and it has to
-- stay the same one or the light and the costume disagree about what the player is. They did:
-- `GameConfig.Stages[20].color` is rgb(255, 255, 255), so the last stage in the game lit every skin
-- with a pure-white lamp regardless of which of its five characters was being worn.
local function setupAura(character, stage, stageIndex, color)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	color = color or stage.color

	local light = getOrCreate(root, "PointLight", "EvolutionAuraLight")
	light.Color = color
	light.Range = auraRange(stageIndex)
	light.Brightness = auraBrightness(stageIndex)
	light.Shadows = false

	local attachment = getOrCreate(root, "Attachment", "EvolutionAuraAttachment")

	local particle = attachment:FindFirstChild("EvolutionAuraParticle")
	if not particle then
		particle = Instance.new("ParticleEmitter")
		particle.Name = "EvolutionAuraParticle"
		particle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		particle.Parent = attachment
	end
	particle.Color = ColorSequence.new(color)
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

-- ===== THE MUTATION AURA (12.5) =============================================
--
-- What the Splicer bought has to be visible on the body, or a x2.25 income multiplier is a line of
-- text in a panel nobody has open. One rung, one effect, escalating -- the pack ships an `Auras`
-- category authored for exactly this and the three RNG auras are the middle of the ladder.
--
-- COLOUR TRACKS THE LADDER SWATCH, WITH ONE DELIBERATE EXCEPTION. `Secret` is authored
-- rgb(20,20,20) because it reads as "black" on a UI card; tinting a particle system with it makes
-- an aura you cannot see against a dark world, on the second-rarest rung in the game. It gets the
-- violet its portal effect already implies instead. Same reasoning as the Secret odds row in
-- SplicerUI, arrived at twice independently: a swatch chosen for a white panel is not a colour.
--
-- `span` is how many studs the biggest particle should measure ON A 1x BODY, resolved through
-- VFXLibrary's `targetSize` -- NOT a multiplier on the pack's own size. The pack's authored sizes
-- run from 1.1 studs to 19.6, so a shared multiplier sizes each effect against itself instead of
-- against the player, and the first cut of this table did exactly that: a 10-stud sprite at the
-- centre of a 16-stud-wide body, rendering perfectly, entirely inside an opaque torso. The body is
-- about 5.9 studs wide per unit of BodyScale, so a span of 7-11 puts the aura outside the
-- silhouette at every stage without swallowing the player.
--
-- Two effects the pack ships as "auras" are deliberately NOT here: `Fire-Aura-01` and
-- `Water-Aura-01` are six emitters of 1.1-stud particles whose shape comes entirely from where
-- those emitters sit on the source part -- and `Attach` lifts them all onto ONE attachment, which
-- is exactly the information it throws away. They collapse to a dot. Prefer an effect whose
-- emitters are already at the origin (`maxEmitterOffset` 0) or the lift changes what you chose.
--
-- THE RATES WERE CUT AT THE TOP OF THE LADDER (15.31), not across the board. The owner's report is
-- "nista se ne vidi" at max stage -- and it is the top three rungs that are worn there, on the one
-- body that is also five times the size, so the same rate is emitting into five times the volume
-- and the player is inside the result. Common and Rare are untouched because nobody has ever
-- complained about them and they are what most of the game sees. The ladder still climbs.
local MUTATION_VFX = {
	Common    = { path = "Anime/Smoke-01",    rate = 6,  span =  7.0, color = Color3.fromRGB(200, 200, 200) },
	Rare      = { path = "Anime/Stars-01",    rate = 10, span =  7.6, color = Color3.fromRGB( 90, 160, 255) },
	Epic      = { path = "Auras/RNG-Aura-01", rate = 14, span =  8.2, color = Color3.fromRGB(170,  90, 255) },
	Legendary = { path = "Auras/RNG-Aura-02", rate = 18, span =  8.8, color = Color3.fromRGB(255, 180,  50) },
	Mythic    = { path = "Auras/RNG-Aura-03", rate = 22, span =  9.4, color = Color3.fromRGB(255,  80,  80) },
	Secret    = { path = "Anime/Portal-01",   rate = 26, span = 10.2, color = Color3.fromRGB(120,  60, 200) },
	Godly     = { path = "Big/Tornado-01",    rate = 30, span = 11.0, color = Color3.fromRGB(255, 240, 150) },
}

-- How the aura grows with the body. NOT 1:1 (15.31): `span * scale` made Mythic's 9.4 studs into 47
-- at BodyScale 5 -- a particle wall wider than the character standing in it, which is the "nothing
-- is visible at the last stage" report. The body is ~5.9 studs wide per unit of BodyScale, so at 5
-- it measures about 29.5: an exponent of 0.6 lands the aura at ~26 studs, i.e. at the silhouette's
-- own edge rather than seventeen studs beyond it, and leaves 1x bodies exactly as they were
-- (1^0.6 = 1). Do not take it much lower: 0.5 gives 21 studs, which puts a top-rung aura INSIDE a
-- 29-stud body -- the bug the `span` note above already describes.
local AURA_SCALE_EXP = 0.6

-- ===== YOU HAVE TO BE ABLE TO SEE THE CREATURE THROUGH IT (17.19) ============
--
-- "ne vidim lika koliko svetli" -- the max-stage body photographs as a solid white silhouette with a
-- red fringe around the outside and a halo several studs past it.
--
-- The fringe is the whole diagnosis. The pack ships these emitters at a minimum Transparency of
-- **0.00** and they draw additively (LightEmission 1, which 17.18 established has to stay there), so
-- layers ADD: Mythic's rgb(255, 80, 80) is (1.00, 0.31, 0.31) once, pink twice, white by three. The
-- middle of the frame is three or four sprites deep and the rim is one -- white body, red edge.
-- Neither of the two properties this bug family has already been fixed through can help. Brightness
-- is what the layer's colour is (17.1, capped at 1 and correct), LightEmission is whether the
-- texture's black background gets drawn (17.18, must stay at the authored value). Transparency is
-- the only one that scales HOW MUCH a layer contributes, and nobody had touched it.
--
-- 0.5 halves what every layer adds, which doubles the depth of stacking the aura tolerates before it
-- clips: three layers now land at (1.00, 0.47, 0.47), still visibly red. It is a floor under the
-- curve, not an assignment -- the fade-out still reaches full transparency -- and it cannot bring
-- 17.18's black slab back, because an additive layer drawn less hard moves toward the world behind
-- it rather than toward black.
local AURA_MIN_TRANSPARENCY = 0.5

-- ...AND THE SPRITES ARE FLOOR SPRITES HUNG AT EYE LEVEL. The pack names them `Floor1/2/3`: they are
-- a ground ring, and `Attach` puts them at the HumanoidRootPart, which on a 5x body is 23.6 studs
-- above the feet with the camera 15.9 studs away -- i.e. INSIDE the ring. A 24.7-stud quad drawn
-- between the camera and the creature is not an aura around the character, it is a filter over the
-- lens, and that is most of why there is no detail left in the body.
--
-- So the effect is dropped toward the feet. HALFWAY, not all the way: 17.2 tried the feet and
-- measured the cost -- the view clears completely and the wearer can then no longer see the aura at
-- all at the default zoom, which is the thing they paid for. Half clears the camera plane (12 studs
-- of separation at max stage, against a ring radius of 12) while leaving the aura inside a frame the
-- camera is standing in the middle of.
--
-- MEASURED IN THE BODY, NOT IN THE AURA. 17.2 read the feet at 23.64 studs below the root on a 5x
-- body, i.e. ~4.73 studs of body per unit of stage scale, and that is the constant below. It is
-- deliberately NOT derived from the aura's own span (the span is sublinear in scale, so it would
-- drift), and deliberately NOT read off `root.Size.Y` -- the body settles several frames after this
-- runs, so live geometry here is the [[evolution-lab-body-settles-late]] trap and would size the
-- drop to a default 2-stud avatar on every spawn.
--
-- It is also why the drop is passed IN rather than computed here: the pet rigs come through this
-- same function with a `scale` in completely different units (petScale 2.45 beside a max-stage
-- player, on a rig about six studs tall), so a shared formula would bury their auras underground.
-- They pass nothing and keep today's placement, which nobody has complained about and where no
-- camera ever sits.
local ROOT_TO_FEET = 4.73
local AURA_DROP = 0.5

local MUTATION_AURA_NAME = "MutationAura"

-- Hangs (or removes) the worn mutation's aura on a root part.
--
-- THE ROOT PART, NEVER A COSTUME SHELL. Every limb a player appears to have is a welded shell that
-- `StageCostume.Apply` DESTROYS and rebuilds on every evolve and every skin change -- an aura
-- parented to one of those is gone the first time the wearer changes anything, which is the moment
-- they are most likely to be looking. The HumanoidRootPart survives a re-dress; it only dies with
-- the character, and a fresh character comes back through ApplyStage.
--
-- Idempotent by destroy-then-build rather than by patching in place: the attachment carries a
-- variable number of emitters copied out of the pack, so "same aura, different rung" has no safe
-- in-place edit and the whole unit is cheap to replace.
--
-- Takes the PART rather than the character, because the equipped pet rigs need exactly the same
-- thing hung on their own roots and a second copy of this table is how the two drift apart.
--
-- `drop` is how many studs below the root the effect hangs, and it is the CALLER's number because
-- only the caller knows how tall the thing wearing it is -- see AURA_DROP. Omitted means 0, i.e.
-- on the root, which is where every wearer had it before.
function EvolutionVisuals.AttachMutationAura(root, mutationName, scale, drop)
	if not (root and root:IsA("BasePart")) then return nil end

	-- THE SCALE IS PART OF THE IDENTITY, not just the name. An evolve keeps the mutation and triples
	-- the body, so a name-only check would leave a Cell-sized aura on a Gorilla forever; it also makes
	-- the call order-independent, which matters because the attribute hook can reach a character
	-- before ApplyStage has stamped `BodyScale`.
	local wanted = ("%s@%.2f"):format(tostring(mutationName), scale or 1)
	local existing = root:FindFirstChild(MUTATION_AURA_NAME)
	if existing and existing:GetAttribute("AuraKey") == wanted then
		return existing -- already wearing exactly this, at this size; leave the running emitters alone
	end
	if existing then existing:Destroy() end

	local spec = mutationName and MUTATION_VFX[mutationName]
	if not spec or not VFXLibrary.Exists(spec.path) then return nil end

	-- sized against the BODY, not against the pack -- see the note on `span`, and sublinear in the
	-- body's own scale -- see AURA_SCALE_EXP
	local span = spec.span * math.pow(math.max(scale or 1, 0.01), AURA_SCALE_EXP)

	local att = VFXLibrary.Attach(root, spec.path, {
		name = MUTATION_AURA_NAME,
		-- Normalised, not multiplied: this table spans Smoke-01 at 5 particles/second to
		-- Fire-Aura-01 at 120, so a raw multiplier would make the low rungs bare and the top ones a
		-- wall. Well under the boss aura's 55 -- a boss is one thing you walk up to, a player aura is
		-- on every player on the server at once.
		targetRate = spec.rate,
		targetSize = span,
		-- down off the camera plane, because these are ground sprites -- see AURA_DROP
		offset = Vector3.new(0, -(drop or 0), 0),
		-- and see-through, because the creature is behind them -- see AURA_MIN_TRANSPARENCY
		minTransparency = AURA_MIN_TRANSPARENCY,
		color = spec.color,
	})
	if att then
		att:SetAttribute("AuraKey", wanted)
		att:SetAttribute("Mutation", mutationName)
	end
	return att
end

-- The worn mutation's name, from the attribute SplicerService stamps -- with the save as a fallback
-- for the join path, where a character can be ready before the stamp lands. Public because
-- PetFollowService needs the same answer for the rigs.
function EvolutionVisuals.WornMutation(player)
	local name = player:GetAttribute("Mutation")
	if name == nil then
		local data = PlayerDataService.Get(player)
		name = data and data.SplicerMutation
	end
	return name
end

function EvolutionVisuals.ApplyMutationAura(player)
	local character = player.Character
	if not character then return end
	-- `BodyScale` is the stage's TARGET scale, stamped by ApplyStage -- deliberately not the
	-- Humanoid's live BodyHeightScale, which is mid-tween for 0.6s after an evolve and would size
	-- the aura to a body the player is only passing through. See [[evolution-lab-body-settles-late]].
	local scale = character:GetAttribute("BodyScale") or 1
	return EvolutionVisuals.AttachMutationAura(
		character:FindFirstChild("HumanoidRootPart"),
		EvolutionVisuals.WornMutation(player),
		scale,
		-- halfway to this body's own feet -- the same stamped scale, for the same reason
		ROOT_TO_FEET * scale * AURA_DROP)
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
		-- x4 of the CLAMPED resting value, so the evolve flash tops out at 10 for half a second
		-- instead of the 32 the unclamped formula reached at stage 20 -- and it returns to exactly
		-- what setupAura set, because both ends now read the same function.
		local flash = TweenService:Create(light, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Brightness = auraBrightness(stageIndex) * 4,
		})
		flash:Play()
		task.delay(0.5, function()
			if light and light.Parent then
				TweenService:Create(light, TweenInfo.new(0.6), { Brightness = auraBrightness(stageIndex) }):Play()
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

-- ===== THE PLAYER DOES NOT GROW ANY MORE (30.14) =====
--
-- Kristina's call, 2026-08-21: *"nemoj da igrac raste, nek bude iste velicine uvek, pa da se uklopi
-- sve u mapu"* -- the body is one fixed size for the whole game, so a map can be authored around it.
--
-- WHY THIS IS ONE CONSTANT AND NOT TWENTY EDITS. `stage.scale` (1.0 -> 5.0 across the twenty stages)
-- stays exactly as authored in `Evolution.lua`, because those numbers are the SHAPE of the
-- progression and other things may yet want to read them. What changes is that the BODY stops
-- listening to them: both the `BodyScale` stamp and the `applyScale` call below take this instead.
--
-- AND EVERYTHING DOWNSTREAM IS ALREADY CORRECT, because none of it reads `stage.scale` -- it reads
-- the `BodyScale` ATTRIBUTE. `CameraFit`, `CombatClient`'s reach, `VipFlair`'s aura, `MainUI`'s
-- health bar, `applyMastery`'s pace (`GetSizeSpeedMultiplier`) and the costume shells all keep
-- working untouched; they simply stop being told the number changed. That is the whole reason this
-- is a two-line change rather than a sweep.
--
-- 1.0 IS TODAY'S STAGE-ONE BODY, not a new size. Through `PLAYER_SCALE_BOOST` it is 1.45x a stock
-- avatar (~8.3 studs), which is what every player already spawns as -- so nothing in the existing
-- world regresses: every zone, shop, egg stall, arena and obby course is already walkable at it.
-- Raising it is one number here; the thing to check first is `AdventureMap`'s fixed WALK_SPEED /
-- JUMP_POWER, which was cut against a body that used to reach 41 studs.
local FIXED_BODY_SCALE = 1.0

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
	-- THE WORN MUTATION IS ADDED AFTER THE CLAMP, AS A SHARE OF THE CEILING (15.30). It used to ride
	-- inside the parenthesis beside the Speed upgrade, and for most of the game that was fine -- but
	-- the term inside the clamp reaches 581 on a max-stage body against a cap of 260, so everything
	-- in there is 2.24x past the ceiling and the aura's studs were sawn off entirely: seven rungs of
	-- ladder, zero studs of difference, while the Auras panel and the boost card both went on
	-- printing the bonus. `speedPct` is now a percentage of THIS player's cap, added on top, so it
	-- lands in full whether the body is at 1x or clamped at the top. This is the owner's call between
	-- three options (2026-08-16); the other two were raising the cap with the body and printing less.
	--
	-- YES, THIS DELIBERATELY EXCEEDS THE CAP -- by at most 12% (Godly), which is 31 studs on the 260
	-- of the 2x Speed pass and 18 on the standard 150. The cap is a streaming number, not a balance
	-- number (see the note above), and its own headroom comment already budgets a little slack; a
	-- bounded 12% overshoot is the price of the aura being worth wearing at the stage people wear it.
	-- It is NOT `cap * sizeMult`: multiplying the ceiling by the body would put a max-stage player at
	-- ~580 studs/s, which is the speed the cap exists to prevent.
	local walkCap = GameConfig.GetPassMax(data, "walkCap", GameConfig.MaxWalkSpeed or 120)
	humanoid.WalkSpeed = math.min(
		(GameConfig.BaseWalkSpeed + bonus.walkSpeed + GameConfig.GetSpeedUpgradeBonus(data))
			* sizeMult * GameConfig.GetPassMult(data, "walkMult"),
		walkCap
	) + walkCap * GameConfig.GetMutationSpeedPct(data) / 100
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

-- THE INPUT STOPS INSTANTLY AND THE LIMBS DO NOT, AND THE CHECK ABOVE ONLY WATCHES THE INPUT.
--
-- Measured on the running game (2026-08-13, stage 13, walking then stopping): the arms are
-- **59.7 degrees** from their resting pose two hundredths of a second after `MoveDirection` reaches
-- zero, 33.0 at 0.15 s, 10.3 at 0.22 s, and only at **~0.28 s** do they reach the 2.7 degrees that is
-- the idle animation's own sway. `poseSettled` alone releases the dress two frames after the input
-- stops -- i.e. at the top of that curve -- so the weld set built there was measured **45.6 degrees**
-- off the standing baseline, against 44.5 for dressing mid-stride with no wait at all. The gate was
-- firing exactly as designed and buying almost nothing, because it was gating on the wrong signal.
--
-- So the wait watches the limbs themselves. The separation is not a judgement call, it is measured:
-- per-frame limb movement is at most **0.125 deg standing** (breathing, and it never stops, which is
-- why this cannot be an equality test like the size probe above), averages **1.12 deg walking**, and
-- runs above **4 deg** through the blend-out. POSE_EPS at 0.5 sits four times over the idle ceiling
-- and eight times under the motion it has to catch.
--
-- The four limbs are read RELATIVE TO THE ROOT, so walking in a straight line and turning on the spot
-- both cancel out -- what is left is only the limb's pose on the body, which is exactly what a weld
-- freezes. R6 has none of these parts: the table comes back empty, the delta is 0, and such a body
-- falls through to the input check exactly as it did before.
local POSE_LIMBS = { "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg" }
local POSE_EPS = 0.5

local function limbPose(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local inv = root.CFrame:Inverse()
	local pose = {}
	for _, name in ipairs(POSE_LIMBS) do
		local part = character:FindFirstChild(name)
		if part then pose[name] = inv * part.CFrame end
	end
	return pose
end

-- worst per-limb angular movement between two samples, in degrees
local function poseDelta(a, b)
	if not (a and b) then return math.huge end
	local worst = 0
	for name, cfA in pairs(a) do
		local cfB = b[name]
		if cfB then
			local _, ang = (cfA:Inverse() * cfB):ToAxisAngle()
			ang = math.abs(math.deg(ang))
			if ang > worst then worst = ang end
		end
	end
	return worst
end

local function waitForBodySettled(character, timeout)
	local waited, stable, last, lastPose = 0, 0, nil, nil
	timeout = timeout or 2
	while waited < timeout do
		local probe = bodyProbe(character)
		if not probe then return end
		local pose = limbPose(character)
		if last and math.abs(probe - last) < 1e-4
			and poseSettled(character)
			and poseDelta(lastPose, pose) < POSE_EPS then
			stable += 1
			if stable >= 2 then return end
		else
			stable = 0
		end
		last = probe
		lastPose = pose
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
	-- FIXED_BODY_SCALE, not `stage.scale` -- see the note over the constant. The attribute is still
	-- stamped, and still on every spawn and every evolve: half a dozen client scripts wait on it and
	-- a character that never gets it falls back to 1 and sizes its aura, camera and reach wrong.
	character:SetAttribute("BodyScale", FIXED_BODY_SCALE)

	local data = PlayerDataService.Get(player)
	local bonus = data and GameConfig.GetStageMasteryBonus(data)
	-- same product as applyMastery below -- stage mastery times the worn skin's own rank bonus.
	-- Both call sites have to agree or the two paths fight over MaxHealth on every respawn.
	-- The health multiplier is UNCHANGED and still stage-driven: evolving stops making you bigger,
	-- it does not stop making you tougher. Only the size argument is frozen.
	applyScale(character, FIXED_BODY_SCALE, opts.animate,
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

	-- After `entry`, and that is the whole reason it moved down here from beside the BodyScale stamp:
	-- the stage light has to be the colour of the character being WORN, not of the stage. Nothing
	-- between the two positions touches the root part's light or attachment.
	setupAura(character, stage, stageIndex, entry and entry.color)

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

	-- After the scale, so the aura is sized to the stage the player is arriving at. It sits on the
	-- HumanoidRootPart and so survives `dress` destroying every costume shell below.
	EvolutionVisuals.ApplyMutationAura(player)

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
				-- Stamp the worn mutation on the JOIN path too. SplicerService only sets it at the
				-- moment of a roll, so without this a returning player's attribute is nil all session
				-- and anything reading the channel rather than the save sees no mutation at all.
				-- Before ApplyStage, so the attribute hook and ApplyStage cannot disagree about which
				-- of them built the aura -- they are idempotent against the same key either way.
				if data.SplicerMutation and player:GetAttribute("Mutation") ~= data.SplicerMutation then
					player:SetAttribute("Mutation", data.SplicerMutation)
				end
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
		-- A splice must show up WITHOUT a respawn -- the whole sequence is a card, a flash and then
		-- your own body changing. `Mutation` is the attribute SplicerService stamps, so this is the
		-- only hook needed and it costs nothing when nobody splices.
		player:GetAttributeChangedSignal("Mutation"):Connect(function()
			EvolutionVisuals.ApplyMutationAura(player)
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
