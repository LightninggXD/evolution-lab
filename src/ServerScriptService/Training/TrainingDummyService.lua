-- TrainingDummyService -- the grotto dummy, and the only thing that banks training reps off a blow
-- (33.21).
--
-- A LEAF. The curve and every constant live in `GameConfig.Training`; the geometry lives in
-- `TrainingDummyModel` beside this file; the damage the reps eventually buy is computed in exactly
-- one place, `DNAService.GetCombatDamage`, as it has always been. This file counts hits and pays for
-- them.
--
-- ===== WHAT THE OWNER ASKED FOR, AND THE FORK IT WAITED ON =====
--
-- *"u vodopadu treba biti dummy za udaranje ... ovde ce biti +1 damage, a damage dobijas kad tuces
-- mobove i udaras ovaj dummy (dummy ce zahtevati 1 rebirth i davati dupli damage playeru dok
-- trenira)"* -- the `+1 Strength` loop, in the room 33.18/33.19 built behind the falls.
--
-- Roadmap 33.21 refused to be implemented for a day because the request does not say what the reward
-- IS, and the wrong answer here is expensive: a permanent stat handed out by a one-time secret is a
-- free rebirth, and a session buff is not a collection. She answered it on 2026-08-27 -- a capped
-- multiplier, reset by a rebirth, with the fill rate climbing per rebirth -- and the reasoning is
-- written out at the top of `GameConfig/Training.lua` rather than repeated here.
--
-- ===== THIS FILE REPLACED AN EARLIER ONE THAT NEVER RAN, AND ITS DEFECTS ARE THE TEST LIST =====
--
-- `GrottoDummyService.lua` was written on the unanswered fork, was never wired into `ServerMain`,
-- and is deleted. Four of its six recorded defects (`agent-board/CLAUDE-REVIEW.md` R32/R34) were
-- still live in it, and each one is a thing this file does deliberately:
--
--   1. it fired `CombatFx:FireClient(player, "hit", pos, 1)` -- FOUR POSITIONAL ARGUMENTS, where
--      `CombatClient` opens with `if type(fx) ~= "table" then return end`. Nothing drew, silently.
--      Every payload here is a table.
--   2. it sent `Notify` with `{ kind = "error", text = ... }`, and MainUI reads `payload.message`.
--      The player saw a toast reading "nil". The key is `message`.
--   3. it seated the dummy at `Secrets[1].offset + (7, 3, -4)` -- inside the plinth, three studs
--      from the secret trigger, colliding. `TrainingDummyModel` derives the seat and it was measured
--      against a body box.
--   4. it parented into `workspace.Map.Props` and listened for auto-attack anyway -- but
--      `nearestTarget()` only ever scans the folders in its own `AUTO_REACH` table, and the model
--      carried no `Health` attribute, so that listener could not fire. Both halves are fixed: this
--      folder is named in `AUTO_REACH`, and the model publishes `Health`.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local PlayerDataService = require(script.Parent.Parent.PlayerDataService)
local TrainingDummyModel = require(script.Parent.TrainingDummyModel)

local Remotes = RS.Remotes

local TrainingDummyService = {}

-- ===== REACH =====
--
-- A DUMMY IS NOT A CREATURE AND THE NUMBERS ARE SMALLER FOR ONE REASON: it stands still. 15.21's
-- measurement is the one that matters -- a max-stage character's box is 30.7 studs wide, so its
-- half-width from the HumanoidRootPart this is measured FROM is 15.4 -- and the dummy's own scaled
-- silhouette is 9.5 wide, i.e. ~5 from its centre. 30 leaves a max-stage player standing 9 studs
-- clear of the body; the creature reaches are 60/70 because a creature can walk away mid-swing.
--
-- The server gate is LOOSER than the detector's own reach, exactly as `CreatureService`'s
-- `clickGate = clickReach + 6` is: the click reach is enforced client-side, so a blow that arrives
-- from a player who has taken one step since is a real blow and not an exploit.
local CLICK_REACH = 30
local CLICK_GATE = CLICK_REACH + 6
-- Above the client's own `AUTO_REACH.Training` (45), for the reason written over that table: a
-- server gate at or under the client's reach silently drops every auto-attack thrown at the edge of
-- it, and the feature then looks dead rather than tight.
local AUTO_GATE = 48

-- Faster than any creature (`tier.hitCooldown` runs 0.35..0.8) and that is the point -- it is a
-- training dummy, and the feel of the `+1` family is a fast, even drum. Four reps a second is also
-- what sets the honest cost of the whole ladder: 1000 reps is ~2 minutes of solid punching at rest,
-- which is why the cap exists at all.
local HIT_COOLDOWN = 0.25

-- One line every few seconds, not one per swing. Auto-attack fires at the client's tick rate, so an
-- ungated notify is ~4 toasts a second for as long as the player stands there -- the same reason
-- `CreatureService.LOCK_NOTICE_COOLDOWN` exists, and the same number.
local NOTICE_COOLDOWN = 4

local dummy = nil          -- the Model
local dummyBody = nil      -- the part reach is measured to
local recoil = nil         -- closure from TrainingDummyModel.Recoil
local lastHitAt = {}       -- per player, the cooldown
local lastNoticeAt = {}    -- per player, the toast throttle

Players.PlayerRemoving:Connect(function(player)
	-- Both tables are keyed by UserId and neither is weak, so without this a busy server leaks one
	-- number per visitor for the life of the process.
	lastHitAt[player.UserId] = nil
	lastNoticeAt[player.UserId] = nil
end)

local function notify(player, kind, message)
	local last = lastNoticeAt[player.UserId]
	if last and os.clock() - last < NOTICE_COOLDOWN then return end
	lastNoticeAt[player.UserId] = os.clock()
	local ev = Remotes:FindFirstChild("Notify")
	-- `message`, NOT `text`. See defect 2 in this file's header.
	if ev then ev:FireClient(player, { kind = kind, message = message }) end
end

-- ===== THE BLOW =====
--
-- One function for both inputs, the shape `CreatureService.onHit` uses, and for the same reason: the
-- ClickDetector path and the remote path have to be held to the same rules, and two copies of those
-- rules is two chances for one of them to lose a check.
local function onHit(player, viaAuto)
	if not dummy or not dummy.Parent or not dummyBody then return end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	-- A corpse does not train. Checked here rather than trusted from the client, which cannot be
	-- authoritative about anything on this path.
	if not humanoid or humanoid.Health <= 0 then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	if (hrp.Position - dummyBody.Position).Magnitude > (viaAuto and AUTO_GATE or CLICK_GATE) then return end

	local data = PlayerDataService.Get(player)
	if not data then return end

	-- ===== THE GATE, AND THIS IS THE REAL ONE =====
	-- The model publishes `MinRebirths` and the client greys it out and drops it from auto-attack on
	-- the strength of that -- none of which is authoritative, because a ClickDetector's reach is
	-- enforced client-side and a hand-fired remote reaches this line with no UI involved at all.
	-- Same split as the raised creatures and the rebirth shrine: the paint is a courtesy, this is
	-- the check.
	--
	-- Refused BEFORE the cooldown is stamped, so a locked player is not silently put on cooldown.
	if not GameConfig.CanUseTrainingDummy(data) then
		local need = GameConfig.TrainingDummyMinRebirths
		notify(player, "error", ("The dummy is sealed -- it takes %d %s to train here")
			:format(need, need == 1 and "rebirth" or "rebirths"))
		return
	end

	local now = os.clock()
	if lastHitAt[player.UserId] and now - lastHitAt[player.UserId] < HIT_COOLDOWN then return end
	lastHitAt[player.UserId] = now

	-- The recoil and the spark fire whatever happens next, INCLUDING at the cap. A blow that
	-- produces no feedback at all reads as a broken dummy rather than as a full one -- which is the
	-- distinction the toast below draws in words.
	if recoil then recoil() end

	local capped = GameConfig.IsTrainingCapped(data)
	local gain = 0
	if not capped then
		gain = GameConfig.GetTrainingGain(data, GameConfig.TrainingDummyReps)
		local before = GameConfig.GetTrainingReps(data)
		data.TrainingReps = math.min(before + gain, GameConfig.TrainingRepCap)
		-- The gain that is DRAWN is the gain that was BANKED, even at the last rep before the cap,
		-- where the clamp above may have taken part of it. Anything else prints a number the HUD
		-- immediately contradicts.
		gain = GameConfig.GetTrainingReps(data) - before

		-- Straight onto the attribute, so the HUD bar moves on the swing rather than up to 0.4 s
		-- later. `LevelService.Publish` owns this attribute and keeps sweeping it -- writing it here
		-- too is safe precisely because that sweep is idempotent (an attribute written with the value
		-- it already holds fires no Changed), so the two can never fight.
		player:SetAttribute("TrainingReps", GameConfig.GetTrainingReps(data))

		if GameConfig.IsTrainingCapped(data) then
			-- The one moment the ANSWER changes rather than the number: the rebirth panel and the
			-- HUD read the cap, so this is where the whole save is pushed. Same rule
			-- `LevelService` follows for a level-up, and the reason it does not push per blow.
			PlayerDataService.PushToClient(player)
			notify(player, "reward", "\u{1F4AA} Training complete -- x3.00 damage. Rebirth to train again.")
		end
	else
		notify(player, "error", "\u{1F4AA} Fully trained -- a rebirth resets the ladder, and it fills faster.")
	end

	-- ===== THE FEEDBACK, IN THE WORLD =====
	-- `evolution-lab-feedback-placement`: drawn where the thing happened, never as a screen banner.
	-- A TABLE, and the whole contract is that it is one -- see defect 1 in this file's header.
	-- Fired only to the player who threw the blow: a second player's rep count is not their business
	-- and four numbers a second from a stranger is noise.
	local fx = Remotes:FindFirstChild("CombatFx")
	if fx then
		fx:FireClient(player, {
			k = "train",
			p = dummyBody.Position + Vector3.new(0, 4, 0),
			a = player.UserId,
			tr = gain,
			s = 8,
		})
	end
end

-- ===== INIT =====
--
-- EVERY connection is made in here and none at require time. R32's defect 4 was an
-- `OnServerEvent:Connect` at module top level, which fires before the model it dereferences exists.
function TrainingDummyService.Init()
	local folder = workspace:FindFirstChild(TrainingDummyModel.FolderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = TrainingDummyModel.FolderName
		folder.Parent = workspace
	end

	-- ITS OWN FOLDER, and the two folders it is deliberately NOT in:
	--   * `map.WaterfallGrotto` is wiped and rebuilt by every `MapWaterfall.Build`, so a dummy in it
	--     survives exactly until the next rebuild.
	--   * `map.Secrets` is destroyed wholesale by `SecretsService` on a `SECRETS_VERSION` bump --
	--     R32's defect 2, and 33.13's before it.
	-- The name is also the contract with the client: `CombatClient.AUTO_REACH` keys off it.
	local model, hitbox, seated = TrainingDummyModel.Build("Forest", 0, folder)
	if not model then
		warn(("[TrainingDummyService] no dummy built -- %s"):format(tostring(hitbox)))
		return
	end

	dummy = model
	dummyBody = model.PrimaryPart
	recoil = TrainingDummyModel.Recoil(model)

	-- DRESSED AFTER THE SCALE, which `TrainingDummyModel.Build` has already applied. `ScaleTo`
	-- multiplies a ClickDetector's MaxActivationDistance, so a detector created before it would have
	-- silently doubled its own reach (`roblox-scaleto-scales-prompt-reach`).
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = CLICK_REACH
	click.Parent = hitbox
	click.MouseClick:Connect(function(player)
		onHit(player, false)
	end)

	-- The shared auto-attack remote. `CreatureService` opens it, `BossService` opens it, and each
	-- listener ignores every model it does not itself own -- so a third listener is the established
	-- pattern here rather than a new one. It is NOT re-created if absent: a dummy that quietly mints
	-- a second `AutoAttack` would leave the creature stack listening on a different instance
	-- (R32's defect 5).
	local auto = Remotes:FindFirstChild("AutoAttack")
	if auto then
		auto.OnServerEvent:Connect(function(player, target)
			if typeof(target) ~= "Instance" then return end
			if target ~= dummy then return end
			onHit(player, true)
		end)
	else
		warn("[TrainingDummyService] no AutoAttack remote -- the dummy is click-only this boot")
	end

	print(("[TrainingDummyService] dummy seated at (%.0f, %.1f, %.0f), %.1f x %.1f x %.1f at x%.1f, "
		.. "gate %d rebirth, +%d reps a blow, cap %d (x%.2f)")
		:format(seated.seat.X, seated.seat.Y, seated.seat.Z,
			seated.size.X, seated.size.Y, seated.size.Z, seated.scale,
			GameConfig.TrainingDummyMinRebirths, GameConfig.TrainingDummyReps,
			GameConfig.TrainingRepCap,
			GameConfig.GetTrainingDamageMult({ TrainingReps = GameConfig.TrainingRepCap })))
end

-- ===== THE OTHER SOURCE =====
--
-- Creature kills bank reps too -- her spec is *"damage dobijas kad tuces mobove i udaras ovaj
-- dummy"*, mobs AND the dummy -- and `CreatureService` calls this on a kill rather than reaching into
-- the save itself. One writer, one clamp, one place the popup number comes from.
--
-- ON A KILL, NOT ON A BLOW, and that is what keeps the two sources honest against each other: a
-- creature takes 2.4 to 14 blows to fell, so paying per blow would make farming a Swarmer a better
-- trainer than the dummy she gated behind a rebirth.
function TrainingDummyService.AwardKill(player, data)
	if not player or not data then return 0 end
	if GameConfig.IsTrainingCapped(data) then return 0 end
	local gain = GameConfig.GetTrainingGain(data, GameConfig.TrainingMobReps)
	local before = GameConfig.GetTrainingReps(data)
	data.TrainingReps = math.min(before + gain, GameConfig.TrainingRepCap)
	local banked = GameConfig.GetTrainingReps(data) - before
	if banked > 0 then
		player:SetAttribute("TrainingReps", GameConfig.GetTrainingReps(data))
	end
	if GameConfig.IsTrainingCapped(data) then
		PlayerDataService.PushToClient(player)
	end
	return banked
end

return TrainingDummyService
