-- AdventureReward -- what a finished adventure pays, and the only place that pays it.
--
-- 30.4 SCOPE. `AdventureService` owns the course; this file owns the money. They are split because
-- the payout has TWO callers and only one of them is a course: the manual run finishes here, and
-- 30.5's dispatch claim -- a pet that ran the route while the player was offline -- lands on the
-- same table. A second copy of the roll would be two relic economies wearing one name, and the
-- first thing that would drift is the luck, which is the one number the panel promises out loud.
--
-- =====================================================================================
-- THE COLLECTION RELIC IS THE REWARD, NOT THE EQUIPPABLE ONE
-- =====================================================================================
-- A relic chest pays both layers (`RelicService.HandleOpenChest`): an equippable off the flat
-- 200-relic table, and a collection relic out of the zone the player is standing in. An adventure
-- pays only the second, and that is the design in 30.1's one-line loop -- "the pet comes back with
-- a relic -> the relic completes a zone SET". The equippable layer already has a faucet with its
-- own timer and its own diamond price; adding a second one here would quietly double the rate at
-- which sockets fill, which is the half of the relic economy 17.6 argued must stay slow.
--
-- THE ZONE IS THE ROUTE'S, NOT THE PLAYER'S. `RelicService` rolls against `data.CurrentZone`
-- because a chest is opened wherever you happen to be standing; a route IS a zone -- one per zone,
-- derived from the strip (`GameConfig.Adventures`) -- so the Reef Descent pays Ocean pieces even
-- though the player runs it four thousand studs off the strip and `CurrentZone` still says Forest.
-- That is what makes the routes worth choosing between rather than a list of names.
--
-- =====================================================================================
-- WHY THE ROLLS LOOP INSTEAD OF ROLLING TWICE INLINE
-- =====================================================================================
-- `RollUnownedSetRelic` prefers a piece the player does not own yet, so it reads the save it is
-- about to be changed by. Two rolls therefore have to be SEQUENTIAL -- roll, grant, roll again --
-- or a par bonus would hand out the same first copy twice and the second one would be dust. It is
-- a loop rather than two calls so that a future rung (a third roll on a route record, say) cannot
-- reintroduce that.

local RS = game:GetService("ReplicatedStorage")
local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS.Remotes

local PlayerDataService = require(script.Parent.PlayerDataService)

local AdventureReward = {}

-- `source` is "run" or "dispatch" -- it changes the wording and nothing else, because the two are
-- worth the same relic. A dispatch trades the player's time for their attention; it is not a worse
-- reward, it is a slower one, and the par bonus is what pays the person who was actually there.
--
-- Returns a summary the caller can print and telemetry can read later:
--   { rolls = n, underPar = bool, luck = %, relics = { {key, rarity, isNew, copies, dust}, ... } }
function AdventureReward.PayFinish(player, route, seconds, pet, source)
	local data = PlayerDataService.Get(player)
	if not (data and route) then return nil end

	local rolls, underPar = GameConfig.GetAdventureRolls(route, seconds)
	local luck = GameConfig.GetAdventureLuck(data, route, pet)
	local summary = { rolls = rolls, underPar = underPar, luck = luck, relics = {} }

	for _ = 1, rolls do
		-- No chest bias: a bias is what a DIAMOND chest buys (`RelicChestDiamondBias`), and an
		-- adventure is bought with a daily run. The route's ladder is already inside `luck`.
		local rolled = GameConfig.RollUnownedSetRelic(data, route.zoneKey, luck, 0)
		if rolled then
			local relic, isNew, dust = GameConfig.AddSetRelic(data, rolled.key, 1)
			if relic then
				table.insert(summary.relics, {
					key = relic.key,
					name = relic.name,
					rarity = relic.rarity,
					isNew = isNew,
					dust = dust,
					copies = GameConfig.GetSetRelicCopies(data, relic.key),
				})
			end
		end
	end

	-- ===== THE LEDGER, AND THE ONE THING A CLOCK MUST NOT DO TO IT =====
	--
	-- `Cleared` counts finishes and `Best` keeps the fastest. `Best` is written ONLY for a run
	-- somebody actually ran: a dispatch has no time (`seconds` is nil for it), and a claim that
	-- stamped one would put a fictitious record on a leaderboard the player never raced for.
	local ledger = GameConfig.GetAdventureLedger(data)
	ledger.Cleared[route.key] = (tonumber(ledger.Cleared[route.key]) or 0) + 1
	if seconds then
		local best = tonumber(ledger.Best[route.key]) or 0
		if best <= 0 or seconds < best then
			ledger.Best[route.key] = seconds
			summary.record = true
		end
	end

	PlayerDataService.PushToClient(player)

	-- AFTER the push, the standing rule: a toast must never arrive before the data that justifies
	-- it. One toast per relic, on the `relic` kind, because MainUI's `relic` branch already draws
	-- the big card for a first Mythic and the plain toast for a duplicate, and it resolves a
	-- collection key through `GetSetRelic` -- see the note in `RelicService.HandleOpenChest`.
	for _, entry in ipairs(summary.relics) do
		Remotes.Notify:FireClient(player, {
			kind = "relic",
			relicKey = entry.key,
			rarity = entry.rarity,
			isNew = entry.isNew,
			copies = entry.copies,
			message = entry.isNew
				and ("%s relic! %s"):format(entry.rarity, entry.name)
				or ("%s  \u{00B7}  copy %d  \u{00B7}  +%d Dust"):format(entry.name, entry.copies, entry.dust),
		})
	end

	-- The par bonus is said out loud, and only when it was earned. A player who beat par by half a
	-- second and got two duplicates has no way to tell the second roll happened at all -- the two
	-- toasts look like one grant of two copies -- and an unremarked bonus is a bonus that does not
	-- change what anybody does next time.
	if underPar and source ~= "dispatch" then
		Remotes.Notify:FireClient(player, {
			kind = "reward",
			message = ("\u{26A1} Under par! %s in %.1fs -- second relic rolled")
				:format(route.name, seconds or 0),
		})
	end

	return summary
end

return AdventureReward
