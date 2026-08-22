-- AdventureDispatch -- sending a pet out, bringing it back, and paying for the wait to end.
--
-- 30.5 SCOPE. Three entry points and nothing else: `Send`, `Claim`, `FinishNow`. The payout is
-- `AdventureReward`'s (30.4) and the course is `AdventureService`'s (30.3); this file owns only the
-- LEDGER ENTRY -- the thing on the save that says a pet is not here.
--
-- =====================================================================================
-- THE DISPATCH IS ON THE SAVE, AND THAT IS THE WHOLE RETENTION ARGUMENT
-- =====================================================================================
-- `ExpeditionService` keeps its run in memory and it dies on rejoin, which is correct for a run you
-- are standing inside. A dispatch must not: the point of sending a pet for eight to twenty minutes
-- is that you close the game and it is waiting when you come back. So the list is `data.Adventures
-- .Dispatch`, `os.time()` rather than `os.clock()` -- a wall clock survives a server, a monotonic
-- one does not -- and `GetAdventureLedger` deliberately does NOT roll `Dispatch` over at midnight
-- (a pet sent at 23:58 is still away at 00:02).
--
-- =====================================================================================
-- "THE PET IS AWAY" IS ONE FUNCTION, AND EIGHT PLACES ASK IT
-- =====================================================================================
-- `GameConfig.IsPetAway` (30.1) is the only test, and the eight callers are `PetService`'s fuse,
-- release, equip, equip-best, tier-up and enchant, `TradeService.SetOffer`, and the save trim in
-- `PlayerDataService`. None of them holds a private copy, because the failure mode of a private
-- copy here is not a wrong screen -- it is a pet that is destroyed while it is out on a route, and
-- a dispatch entry pointing at a pet that no longer exists.
--
-- REMOVING IT FROM `EquippedPetIds` IS THE OTHER HALF, and it is what makes the rig disappear with
-- no change to `PetFollowService` at all: that service rebuilds a player's followers from the
-- equipped list every 0.5 s, so a pet dropped from the list is picked up as gone on the next tick.

local RS = game:GetService("ReplicatedStorage")
local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS.Remotes

local PlayerDataService = require(script.Parent.PlayerDataService)
local AdventureReward = require(script.Parent.AdventureReward)

local AdventureDispatch = {}

local function refuse(player, message)
	Remotes.Notify:FireClient(player, { kind = "error", message = message })
end

-- Minutes and seconds, because a dispatch is 8-20 minutes and "1140s" is not a length of time
-- anybody reads. Shared by the two refusals that have to quote a remainder.
local function clock(seconds)
	seconds = math.max(math.floor(seconds + 0.5), 0)
	return ("%dm %02ds"):format(seconds // 60, seconds % 60)
end

-- ===== SENDING =====
--
-- The refusal wording is the server's, out of `GetAdventureStatus`'s `sendReason` -- the SAME
-- function the panel greys its button with, so the two can never disagree about why.
function AdventureDispatch.Send(player, routeKey, petId)
	local data = PlayerDataService.Get(player)
	if not data then return false, "no data" end

	local route = GameConfig.GetAdventure(routeKey)
	if not route then return false, "no such route" end

	local pet = GameConfig.GetPetById(data, petId)
	local status = GameConfig.GetAdventureStatus(data, route.key, pet)
	if not status.canSend then
		if status.sendReason == "nopet" then
			refuse(player, "Pick a pet to send!")
		elseif status.sendReason == "away" then
			refuse(player, "That pet is already out on an adventure!")
		elseif status.sendReason == "power" then
			refuse(player, ("\u{1F512} %s wants a pet of power %.2f -- yours is %.2f.")
				:format(route.name, route.minPetPower, status.petPower))
		elseif status.sendReason == "slots" then
			refuse(player, ("All %d adventure slots are full -- rebirth for another!"):format(status.slots))
		elseif status.sendReason == "capped" then
			refuse(player, "\u{1F5FA} That is every pet you can send today -- come back tomorrow!")
		else
			refuse(player, "That adventure is not available.")
		end
		return false, status.sendReason
	end

	local now = os.time()
	local ledger = GameConfig.GetAdventureLedger(data, now)
	table.insert(ledger.Dispatch, {
		petId = pet.id,
		routeKey = route.key,
		-- The tier is COPIED onto the entry rather than looked up from the route on claim. It is
		-- what the panel draws while the pet is away, and a route's tier is derived from the zone
		-- strip at load -- so an entry that outlives a change to the strip still describes the
		-- adventure the player actually sent their pet on.
		tier = route.tier,
		startedAt = now,
		endsAt = now + route.autoMinutes * 60,
	})
	ledger.DayDispatch += 1

	-- ===== AND IT COMES OFF THE TEAM =====
	-- Not a cosmetic tidy-up: an equipped pet pays a bonus through `GetEquippedBonus`, and a pet
	-- that is somewhere else paying full damage is the exploit this whole feature would otherwise
	-- be. The rig follows on its own -- see the header.
	local kept = {}
	for _, id in ipairs(data.EquippedPetIds or {}) do
		if id ~= pet.id then table.insert(kept, id) end
	end
	data.EquippedPetIds = kept

	PlayerDataService.PushToClient(player)

	local def = GameConfig.GetPetDef(pet.key)
	Remotes.Notify:FireClient(player, {
		kind = "reward",
		message = ("%s %s set out on %s -- back in %d min"):format(
			route.emoji, def and def.name or pet.key, route.name, route.autoMinutes),
	})
	print(("[AdventureDispatch] %s sent %s on %s for %d min (%d away, %d/%d today)")
		:format(player.Name, pet.key, route.key, route.autoMinutes,
			#ledger.Dispatch, ledger.DayDispatch, GameConfig.AdventureDailyDispatch))
	return true
end

-- ===== CLAIMING =====
--
-- THE ENTRY IS REMOVED BEFORE THE PAYOUT, AND IN THE SAME BLOCK. `PayFinish` pushes to the client
-- and fires toasts; if the entry were still standing at that moment a second claim arriving in the
-- gap would pay twice for one pet.
--
-- A PET THAT IS GONE STILL CLAIMS. Eight guards exist to stop a pet being destroyed while it is
-- away, and if one of them is ever missed the player must not be left holding an entry that can
-- never be cleared -- so a nil pet pays the route without the pet's luck term and drops the entry.
-- The alternative is a permanently occupied slot, which is worse than a slightly smaller reward.
function AdventureDispatch.Claim(player, petId)
	local data = PlayerDataService.Get(player)
	if not data then return false, "no data" end

	local now = os.time()
	local ledger = GameConfig.GetAdventureLedger(data, now)

	local index, entry = nil, nil
	for i, e in ipairs(ledger.Dispatch) do
		if tostring(e.petId) == tostring(petId) then
			index, entry = i, e
			break
		end
	end
	if not entry then
		refuse(player, "That pet is not away on an adventure.")
		return false, "notaway"
	end

	local remaining = GameConfig.GetDispatchRemaining(entry, now)
	if remaining > 0 then
		refuse(player, ("Still exploring -- back in %s"):format(clock(remaining)))
		return false, "early"
	end

	table.remove(ledger.Dispatch, index)

	local route = GameConfig.GetAdventure(entry.routeKey)
	local pet = GameConfig.GetPetById(data, entry.petId)
	local summary
	if route then
		summary = AdventureReward.PayFinish(player, route, nil, pet, "dispatch")
	else
		-- The route's zone left the strip while the pet was out. Nothing to roll against, but the
		-- entry is already gone and the slot is free, which is the part that must not leak.
		PlayerDataService.PushToClient(player)
	end

	print(("[AdventureDispatch] %s claimed %s (%d roll(s), %d still away)")
		:format(player.Name, tostring(entry.routeKey), summary and summary.rolls or 0, #ledger.Dispatch))
	return true, summary
end

-- ===== SKIPPING THE WAIT =====
--
-- FLAT DIAMONDS, never scaled: 21.2's rule is that diamonds buy fixed-price things, because a
-- scaled diamond price is meaningless to the player who has twelve of them.
--
-- CHARGED, THEN THE CLOCK IS MOVED, THEN THE CLAIM RUNS -- and the claim is the ordinary one, so
-- there is exactly one path that pays a dispatch out. A separate "pay and reward" branch here
-- would be the second implementation this file's header refuses.
function AdventureDispatch.FinishNow(player, petId)
	local data = PlayerDataService.Get(player)
	if not data then return false, "no data" end

	local now = os.time()
	local entry = GameConfig.GetPetDispatch(data, petId)
	if not entry then
		refuse(player, "That pet is not away on an adventure.")
		return false, "notaway"
	end
	if GameConfig.GetDispatchRemaining(entry, now) <= 0 then
		-- Already home. Charging for a wait that is over is the one shape of this button nobody
		-- forgives, so it claims for free instead of refusing -- the player pressed the button that
		-- means "bring my pet back" and that is what happens.
		return AdventureDispatch.Claim(player, petId)
	end

	local cost = GameConfig.AdventureFinishNowDiamonds
	if (data.Diamonds or 0) < cost then
		refuse(player, ("Finishing early costs %d Diamonds!"):format(cost))
		return false, "diamonds"
	end

	data.Diamonds -= cost
	local Telemetry = require(script.Parent.Telemetry)
	Telemetry.Economy(player, "Sink", Telemetry.Currency.Diamonds, cost, data.Diamonds,
		Telemetry.Tx.Shop, "adventureFinishNow")

	entry.endsAt = now
	return AdventureDispatch.Claim(player, petId)
end

return AdventureDispatch
