--[==[
	VivariumGuard -- who may raid whom, and what it costs to opt out (24.5).

	===== THE ROW, CLAUSE BY CLAUSE =====

	*"Anti-grief, non-negotiable -- a new-player immunity window, one steal per target per N minutes, a
	per-thief cooldown, nothing stealable below a rebirth threshold, and an opt-out that costs the
	contested bonus rather than being free."* Five clauses, and all of them land in `CanTarget`,
	which `VivariumLock.CanTarget` delegates to -- and that one function is checked at the lock AND at
	the take (24.3's seam), so no clause has a second copy anywhere.

	    immunity          TimePlayed < IMMUNITY (3600 s, lifetime -- the "Tourist" achievement line)
	    rebirth floor     Rebirths < REBIRTH_FLOOR (2)
	    per target        TARGET_COOLDOWN (1200 s) after a steal LANDS on you
	    per thief         THIEF_COOLDOWN (600 s) after you LIFT a specimen, whatever happens next
	    opt-out           `data.VivariumShield`, switched at the Raid Warden (`VivariumWarden`)

	===== "THE CONTESTED BONUS" DID NOT EXIST, SO THIS ROW HAD TO DEFINE IT =====

	Nothing in 24.1-24.4 pays anybody for having a case that can be robbed -- `grep contested` finds
	the word once, in a comment. So the bonus is built here, and its size is not a taste call; it is
	the one number that makes "the opt-out costs something" true without making staying in a loss:

	    worst case for a contested owner = one landed steal per TARGET_COOLDOWN
	                                     = SHARE 0.25 x WINDOW 300 s / 1200 s  = 6.25% of passive DNA
	    CONTESTED_BONUS 0.10 on the same stream, taken BEFORE the split:
	        1.10 x (1 - 0.0625) = 1.031   -- robbed at the maximum legal rate, still ahead of shielded

	So the shield buys certainty and costs about 3-10% of passive DNA, and a player who stays in is
	never worse off in expectation, however hard they are targeted. It is paid in `DNAService`'s own
	per-second loop and nowhere else -- in particular NOT in `GetAutoCollectAmount`, because
	`OfflineService` pays out of that and an offline player's case does not exist to be contested.

	===== THE RULES ARE SYMMETRIC: A PLAYER NOTHING CAN BE TAKEN FROM TAKES NOTHING =====

	Every exemption that protects a target also bars the same player from raiding. Otherwise the
	shield is exactly the free opt-out the row forbids -- raise it, rob everyone, never be robbed
	back -- and immunity and the floor are the same hole for anybody who stays under them on
	purpose. The shield also switches at most once every `SHIELD_SWITCH` (1800 s), persisted in the
	save, which is what closes "lower it, raid, raise it again": a raider is exposed for half an hour
	for every raid, and earns the bonus for that half hour, which is the trade the row describes.

	===== WHAT IS NOT PERSISTED, AND WHY THAT IS ENOUGH =====

	The two cooldowns live in this server's memory, keyed by userId (so a rejoin to the SAME server
	keeps them). A server hop clears them -- but a case is released on leave, and a hop moves both
	players' state apart; there is nothing to protect across servers because nobody can reach you
	there. The shield and its switch time ARE in the save, because those are the player's choice.

	===== SEAMS =====

	`Clock` and `DataOf` are FIELDS, the 22.5 / 24.1 precedent: a probe with one client plays the
	other player by handing `DataOf` a synthetic save, and ages a cooldown by moving `Clock`, instead
	of waiting twenty real minutes. `Landed`, `Lifted` and `Present` are fields for the same reason.
]==]

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDataService = require(ServerScriptService.PlayerDataService)

local VivariumGuard = {}

-- ============================================================================
-- THE NUMBERS -- see the header for the arithmetic that ties BONUS to the two cooldowns
-- ============================================================================
local IMMUNITY = 3600
local REBIRTH_FLOOR = 2
local TARGET_COOLDOWN = 1200
local THIEF_COOLDOWN = 600
local CONTESTED_BONUS = 0.10
local SHIELD_SWITCH = 1800

-- ============================================================================
-- STATE
-- ============================================================================
local landed = {}  -- [ownerUserId] = Clock() of the last steal that LANDED on them
local lifted = {}  -- [thiefUserId] = Clock() of their last lift
local present = {} -- [userId] = true while they hold a case on this server

VivariumGuard.Clock = os.time
VivariumGuard.DataOf = function(userId)
	local player = Players:GetPlayerByUserId(userId)
	return player and PlayerDataService.Get(player) or nil
end

local function minutes(seconds)
	return math.max(1, math.ceil(seconds / 60))
end

local function nameOf(userId)
	local player = Players:GetPlayerByUserId(userId)
	return player and player.DisplayName or "This case's owner"
end

--- Why this save cannot take part in a raid right now, or nil when it can. The second value is how
--- long the reason has left, where it runs out on its own.
function VivariumGuard.Exemption(data)
	if not data then return "loading", 0 end
	if data.VivariumShield == true then return "shield", 0 end
	local played = tonumber(data.TimePlayed) or 0
	if played < IMMUNITY then return "new", IMMUNITY - played end
	if (tonumber(data.Rebirths) or 0) < REBIRTH_FLOOR then return "floor", 0 end
	return nil, 0
end

--- Seconds left on the per-target cooldown, 0 when there is none.
function VivariumGuard.TargetCooldown(ownerId)
	local t = landed[ownerId]
	if not t then return 0 end
	return math.max(0, TARGET_COOLDOWN - (VivariumGuard.Clock() - t))
end

--- Seconds left on the per-thief cooldown, 0 when there is none.
function VivariumGuard.ThiefCooldown(thiefId)
	local t = lifted[thiefId]
	if not t then return 0 end
	return math.max(0, THIEF_COOLDOWN - (VivariumGuard.Clock() - t))
end

-- ============================================================================
-- THE ONE GATE -- `VivariumLock.CanTarget` delegates here, and the lock and the take both call it
-- ============================================================================
--- May `player` raid the case owned by `ownerId`? Returns allowed, the sentence to say, and a short
--- code a probe can assert on. The RAIDER is checked first: a refusal that names your own state is
--- the one you can do something about.
function VivariumGuard.CanTarget(player, ownerId)
	local mine, mineLeft = VivariumGuard.Exemption(VivariumGuard.DataOf(player.UserId))
	if mine == "loading" then
		return false, "Your save is still loading.", "thiefLoading"
	elseif mine == "shield" then
		return false, "Your raid shield is up -- lower it at the Raid Warden to raid.", "thiefShield"
	elseif mine == "new" then
		return false, ("Raiding opens after your first hour -- %dm to go."):format(minutes(mineLeft)), "thiefNew"
	elseif mine == "floor" then
		return false, ("Raiding opens at Rebirth %d."):format(REBIRTH_FLOOR), "thiefFloor"
	end
	local wait = VivariumGuard.ThiefCooldown(player.UserId)
	if wait > 0 then
		return false, ("You raided recently -- %dm until your next."):format(minutes(wait)), "thiefCooldown"
	end

	local theirs, theirsLeft = VivariumGuard.Exemption(VivariumGuard.DataOf(ownerId))
	local name = nameOf(ownerId)
	if theirs == "loading" then
		return false, "This case is still loading.", "targetLoading"
	elseif theirs == "shield" then
		return false, ("%s has their raid shield up."):format(name), "targetShield"
	elseif theirs == "new" then
		return false, ("%s is new here -- protected for %dm."):format(name, minutes(theirsLeft)), "targetNew"
	elseif theirs == "floor" then
		return false, ("%s is below Rebirth %d -- nothing here can be taken."):format(name, REBIRTH_FLOOR), "targetFloor"
	end
	wait = VivariumGuard.TargetCooldown(ownerId)
	if wait > 0 then
		return false, ("%s was robbed recently -- protected for %dm."):format(name, minutes(wait)), "targetCooldown"
	end
	return true, nil, "ok"
end

--- What the lock chip should say instead of its strength, or nil while the case can be raided.
--- Only the TARGET's state: the chip is one BillboardGui for everybody, so a reason that belongs to
--- the viewer (their own shield, their own cooldown) is said through `Notify` on the press instead.
function VivariumGuard.ChipFor(ownerId)
	local why, left = VivariumGuard.Exemption(VivariumGuard.DataOf(ownerId))
	if why == "shield" then
		return "\u{1F6E1}\u{FE0F} SHIELD"
	elseif why == "new" then
		return ("\u{1F6E1}\u{FE0F} NEW %dm"):format(minutes(left))
	elseif why == "floor" then
		return ("\u{1F6E1}\u{FE0F} <R%d"):format(REBIRTH_FLOOR)
	elseif why == "loading" then
		return "\u{1F6E1}\u{FE0F} \u{2026}"
	end
	local wait = VivariumGuard.TargetCooldown(ownerId)
	if wait > 0 then
		return ("\u{1F6E1}\u{FE0F} %dm"):format(minutes(wait))
	end
	return nil
end

-- ============================================================================
-- THE CONTESTED BONUS -- called once a second by DNAService, for every player
-- ============================================================================
--- The multiplier on this player's passive DNA. Only a player who HOLDS a case on this server and
--- could be raided right now is paid it; see the header for why its size is 0.10.
function VivariumGuard.BonusMult(player, data)
	if not player or not present[player.UserId] then return 1 end
	if VivariumGuard.Exemption(data) ~= nil then return 1 end
	return 1 + CONTESTED_BONUS
end

-- ============================================================================
-- THE SHIELD -- the Warden's press
-- ============================================================================
--- Flip the shield. `busy` is true while the player's own case is mid-break, open, carried or
--- drained, or while their hands are full: raising it then would turn a raid already under way into
--- nothing, which is the free opt-out by the side door.
function VivariumGuard.ToggleShield(player, busy)
	local data = VivariumGuard.DataOf(player.UserId)
	if not data then return false, "Your save is still loading.", "loading" end
	local now = VivariumGuard.Clock()
	local since = now - (tonumber(data.VivariumShieldAt) or 0)
	if since < SHIELD_SWITCH then
		return false, ("Your shield can change again in %dm."):format(minutes(SHIELD_SWITCH - since)), "switchCooldown"
	end
	local raising = data.VivariumShield ~= true
	if raising and busy then
		return false, "Not while a raid on you -- or by you -- is under way.", "busy"
	end
	data.VivariumShield = raising
	data.VivariumShieldAt = now
	if raising then
		return true, ("Shield up -- nobody can raid you, you cannot raid, and your +%d%% contested bonus stops."):format(
			CONTESTED_BONUS * 100), "raised"
	end
	return true, ("Shield down -- your case is contested: +%d%% passive DNA, and raiding is open to you."):format(
		CONTESTED_BONUS * 100), "lowered"
end

-- ============================================================================
-- EVENTS -- reported by VivariumSteal and VivariumPlaza
-- ============================================================================
function VivariumGuard.NoteLift(thiefId)
	lifted[thiefId] = VivariumGuard.Clock()
end

function VivariumGuard.NoteLanded(ownerId)
	landed[ownerId] = VivariumGuard.Clock()
end

function VivariumGuard.SetPresent(userId, holding)
	present[userId] = holding or nil
end

VivariumGuard.Immunity = IMMUNITY
VivariumGuard.RebirthFloor = REBIRTH_FLOOR
VivariumGuard.TargetCooldownSeconds = TARGET_COOLDOWN
VivariumGuard.ThiefCooldownSeconds = THIEF_COOLDOWN
VivariumGuard.Bonus = CONTESTED_BONUS
VivariumGuard.ShieldSwitch = SHIELD_SWITCH
VivariumGuard.Landed = landed -- probe seams, for the reason `VivariumPlaza.Anchors` is one
VivariumGuard.Lifted = lifted
VivariumGuard.Present = present

return VivariumGuard
