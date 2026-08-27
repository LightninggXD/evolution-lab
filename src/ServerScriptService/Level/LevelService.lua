-- LevelService -- the bar that fills from damage dealt, and nothing else (32.7).
--
-- A LEAF (`docs/SPLIT.md` §2). It owns two save fields and one loop; the curve lives in
-- `GameConfig.Levels`, the damage term it pays for lives in `DNAService.GetCombatDamage` -- still
-- the only thing in this game that computes damage -- and the rebirth gate it unlocks lives in
-- `GameConfig.CanRebirthNow`. This file decides nothing; it counts.
--
-- IT HAS NO REMOTE OF ITS OWN, and that is worth stating because every other service in this
-- folder has one. There is nothing here for a player to press: the bar fills as a side effect of
-- the two blows that already existed, so a remote would only be a door onto a faucet.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS.Remotes

local PlayerDataService = require(script.Parent.Parent.PlayerDataService)
-- Module scope, and the direction is the load-bearing half -- see the note in `Publish` over the
-- `CombatDamage` attribute. Nothing DNAService requires requires this file back.
local DNAService = require(script.Parent.Parent.DNAService)

local LevelService = {}

-- ===== THE LIVE CHANNEL IS TWO PLAYER ATTRIBUTES, NOT A REMOTE AND NOT DataUpdate =====
--
-- The bar has to move on every blow -- that is the entire feel of the mechanic -- and there are
-- two channels in this game that could carry it. `PlayerDataService.PushToClient` sends the WHOLE
-- save table, so firing it three times a second would be the most expensive thing on the wire by a
-- wide margin. A player attribute replicates one number, server to client, to everybody, for free,
-- and it is the channel `AutoSpeedMult` and `IsVIP` already use for exactly this reason.
--
-- `PushToClient` is still fired, but only on a LEVEL-UP: `data.Level` is what the rebirth panel and
-- the shrine read to decide whether the door is open, and those are the moments that answer
-- changes. Between levels they have nothing to redraw.
local PUBLISH_INTERVAL = 0.4

-- Publishing is a sweep over the players rather than a dirty set, and the simplicity is the point:
-- writing an attribute that already holds that value does not fire Changed, so a sweep costs
-- nothing for an idle player and cannot miss one. It also means join, load, rebirth and a probe
-- writing the save directly all publish themselves with no event wiring at all.
function LevelService.Publish(player, data)
	data = data or PlayerDataService.Get(player)
	if not data then return end
	player:SetAttribute("Level", GameConfig.GetLevel(data))
	player:SetAttribute("LevelXp", GameConfig.GetLevelXp(data))
	-- ===== AND THE TRAINING REPS, ON THIS SWEEP RATHER THAN A SECOND ONE (33.21) =====
	--
	-- The training bar has the identical requirement to the level bar above it -- it must move on
	-- every blow -- so it takes the identical channel, for the reason this file's header states:
	-- `PushToClient` sends the WHOLE save table and firing it three times a second would be the
	-- most expensive thing on the wire.
	--
	-- It rides THIS sweep instead of publishing its own, and the sweep's own property is what makes
	-- that free: writing an attribute that already holds its value does not fire `Changed`, so an
	-- untrained or capped player costs exactly nothing here. `TrainingDummyService` therefore has no
	-- publisher of its own and cannot drift from this one.
	player:SetAttribute("TrainingReps", GameConfig.GetTrainingReps(data))

	-- ===== AND THE DAMAGE ITSELF, ON THE SAME SWEEP AGAIN (33.26) =====
	--
	-- Her call, refusing 33.21's gold training bar: *"dmg se ne skuplja ovako vec samo da pise
	-- damage: pa koliko imam i kako skupljam povecava se"*. `HUD/DamageStat` draws that figure in
	-- the wallet, and this is the only channel it has.
	--
	-- IT RIDES THIS SWEEP FOR THE THIRD TIME AND FOR THE THIRD TIME THAT IS THE CHEAP CHOICE: the
	-- number moves on an evolve, a level, a blade, a pet, a mastery rung and a training rep -- six
	-- writers -- so a dirty flag would need six call sites and would still miss the seventh. The
	-- sweep costs nothing for an idle player because writing an attribute that already holds its
	-- value fires no `Changed`, and it cannot drift from the save by construction.
	--
	-- `DNAService` is required at MODULE SCOPE and that is safe in this direction only: DNAService
	-- requires GameConfig, PlayerDataService, Telemetry and PetService, and none of those four
	-- requires this file. `CreatureService` and `BossService` DO require this file, which is exactly
	-- why the arrow may not be turned round.
	--
	-- `GetCombatDamage` stays the ONE PLACE DAMAGE IS DECIDED. Nothing is recomputed here and
	-- nothing is recomputed on the client -- a second formula for this number is the whole shape of
	-- the "evolving changes nothing" bug the damage ladder was unwound to fix.
	player:SetAttribute("CombatDamage", DNAService.GetCombatDamage(data))
end

-- ===== THE AWARD =====
--
-- `damage` is the health the target actually LOST, never the swing that was thrown at it. That one
-- choice is what makes the ladder honest at both ends: overkill pays nothing, so the optimal farm
-- is the toughest creature you can fell rather than the weakest one you can hit, and the XP a
-- creature is worth is a property of the CREATURE (its blows-to-fell for a bare player) rather
-- than of whoever happened to kill it. See the block at the top of `GameConfig.Levels`.
--
-- `zoneIndex` is the denominator. It is passed in rather than looked up here because both callers
-- already hold their zone and `GetZoneIndex` is a linear scan of twenty rows -- which would be
-- fine once and is not fine three times a second per player.
function LevelService.AwardDamage(player, data, damage, zoneIndex)
	if not player or not data then return end

	local level = GameConfig.GetLevel(data)
	-- AT THE CEILING THE BAR STOPS COUNTING, rather than accumulating a number nothing will ever
	-- spend. `GetLevelXpCost` answers `math.huge` up here, so the roll below could never fire; what
	-- this guard adds is that `LevelXp` cannot grow without bound in the save file.
	if level >= GameConfig.MaxLevel then
		if (data.LevelXp or 0) ~= 0 then
			data.LevelXp = 0
		end
		return
	end

	local gained = GameConfig.GetLevelXpForDamage(damage, zoneIndex, data)
	if gained <= 0 then return end

	local xp = GameConfig.GetLevelXp(data) + gained
	local gainedLevels = 0

	-- SUBTRACTED, NEVER ZEROED -- the same correction the evolve bar took in 11.x ("skupim 10 xpa
	-- upgradeam se i onda ispocetka"). Overkill carries into the next rung, so the last blow before
	-- a level is never worth nothing. The loop is bounded by `MaxLevel` because the cost is
	-- `math.huge` at the top, so a single enormous grant cannot spin.
	while level < GameConfig.MaxLevel do
		local cost = GameConfig.GetLevelXpCost(level)
		if cost == math.huge or xp < cost then break end
		xp -= cost
		level += 1
		gainedLevels += 1
	end

	data.Level = level
	data.LevelXp = xp

	if gainedLevels > 0 then
		LevelService.Publish(player, data)
		-- The panels that decide whether the rebirth door is open read `data.Level` off the save
		-- table, not off the attribute, so this is the push that opens it.
		PlayerDataService.PushToClient(player)

		-- ONE TOAST FOR THE WHOLE ROLL, not one per rung. A boss blow can carry several levels at
		-- once and four identical cards stacking up would evict everything else in the tray -- see
		-- the NotifyRank block in UITheme for why that matters.
		local nextLevel = GameConfig.GetNextRebirthLevel(data)
		Remotes.Notify:FireClient(player, {
			kind = "level",
			level = level,
			mult = GameConfig.GetLevelDamageMult(data),
			-- nil once the ladder is finished, and the client prints the damage line alone then --
			-- naming a rung that does not exist is the "8 / 4" fault one system over.
			nextRebirthLevel = (nextLevel and level < nextLevel) and nextLevel or nil,
		})
	end
end

function LevelService.Init()
	task.spawn(function()
		while true do
			task.wait(PUBLISH_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				LevelService.Publish(player)
			end
		end
	end)
end

-- ===== A REBIRTH TAKES THE LEVEL, AND THAT IS STATED HERE RATHER THAN INFERRED =====
--
-- `RebirthService` wipes by naming fields, so `Level` and `LevelXp` are on that list explicitly --
-- the opposite of `SwordLevel`, which survives by NOT being on it. Both are the same rule read
-- from the same side: everything bought with Diamonds is kept, everything climbed to is reset.
--
-- It also has to be this way for the ladder to work at all. The next rung asks for a HIGHER level
-- than the one just spent; a rebirth that kept the level would hand the following rung over in the
-- same breath, and twenty rungs would fall in a row the moment the first one did.
return LevelService
