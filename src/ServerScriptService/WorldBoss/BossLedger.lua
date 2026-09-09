--[==[
	BossLedger -- who is hitting the world boss, how hard, and what the board says about it (22.4).

	WHY THIS IS A MODULE AND NOT A LOCAL TABLE. The Colosseum giant already tracked contributors,
	as `contributors[userId] = true` inside `spawnEventBoss` -- a set, thrown away on death, which
	is exactly enough to pay everybody and not nearly enough to SHOW anything. 22.4 asks for a live
	contribution board, and a board needs three things the set does not have: how much each player
	did, in what order they arrived, and a name that survives the player leaving mid-fight.

	IT IS ONE LEDGER FOR BOTH WORLD BOSSES, and that is the point rather than a convenience. The
	Devourer stands in the Colosseum and the Herald stands in the village; the board in the hub is
	the one window onto both, and it can only ask one object which fight is happening.

	IT KEEPS A ROW PER BOSS, THOUGH, AND THAT IS NOT DEFENSIVE CODING -- IT IS A MEASUREMENT. The
	first cut held exactly one fight, on the argument that the two are staggered half an interval
	apart and can never overlap. They can: the giant's window (900 s) and the Herald's offset
	(900 s) are the same number, so the two touch at the boundary, `ForceSpawn` exists for testing
	either of them, and a config change to `intervalSeconds` or `despawnSeconds` breaks the
	assumption silently. Live on 2026-09-09 a forced Herald was being hit for 71,429 a blow while
	the board read `THE DEVOURER 25.00M / 25.00M` -- the giant's `Open` had taken the single slot
	and every one of the Herald's `Hit` calls was being dropped on the key check, with nothing
	saying so. One table, keyed, and `Snapshot` decides which to show.

	WHAT IT DELIBERATELY DOES NOT DO. It never pays anybody and it never reads a save. The payout
	lives beside the boss that died, because that is where the boss's own reward table is; this
	only answers "who was in it". `Contributors()` hands back the user ids in the order they first
	landed a blow, which is what both payout loops iterate.

	THE FIGHT SURVIVES ITS OWN DEATH FOR A FEW SECONDS. `Close` does not clear the ledger: it
	stamps a result and a `showUntil`, so the board can say "THE HERALD HAS FALLEN -- 4 challengers
	paid" instead of blinking straight back to a countdown. A player who lands the last blow and
	looks up should see what just happened.
]==]

local BossLedger = {}

-- How long the board keeps showing a finished fight before it goes back to the countdown.
local RESULT_SECONDS = 18

-- [key] = fight. `key` is also what tells a caller whether the fight it is looking at is still its
-- own -- a stale `Close` from a despawned boss must not touch the one that replaced it.
local fights = {}

-- Which fight the board speaks for when there is a choice. The Herald wins a tie because it is
-- the one standing next to the board; a finished fight only shows while nothing is live.
local PREFER = { "hub", "arena" }

--- Opens a fight. `spec` = { key, name, emoji, where, max }.
-- `where` is the words the board puts under the name ("in the Colosseum", "here in the village").
function BossLedger.Open(spec)
	fights[spec.key] = {
		key = spec.key,
		name = spec.name,
		emoji = spec.emoji,
		where = spec.where,
		max = math.max(spec.max or 1, 1),
		hp = math.max(spec.max or 1, 1),
		live = true,
		startedAt = os.clock(),
		-- [userId] = { name, damage }, plus `order` so the board can break ties by who was first
		by = {},
		order = {},
		result = nil,
		showUntil = nil,
	}
end

--- Records a landed blow. Amount is the damage the boss actually lost, not the raw swing.
function BossLedger.Hit(key, player, amount)
	local fight = fights[key]
	if not fight or not fight.live then return end
	local row = fight.by[player.UserId]
	if not row then
		-- The NAME is copied now, on purpose: a player who leaves mid-fight is still on the board
		-- and still gets paid, and `Players:GetNameFromUserIdAsync` is a web call nobody should
		-- make from a boss's hit handler.
		row = { name = player.DisplayName ~= "" and player.DisplayName or player.Name, damage = 0 }
		fight.by[player.UserId] = row
		table.insert(fight.order, player.UserId)
	end
	row.damage += math.max(amount, 0)
end

function BossLedger.SetHealth(key, hp)
	local fight = fights[key]
	if not fight then return end
	fight.hp = math.max(hp, 0)
end

--- Ends the fight and leaves the result on the board for RESULT_SECONDS.
-- `result` is one line: "4 challengers paid", "nobody finished it".
function BossLedger.Close(key, result)
	local fight = fights[key]
	if not fight then return end
	fight.live = false
	fight.result = result
	fight.showUntil = os.clock() + RESULT_SECONDS
end

--- The user ids that landed at least one blow, in arrival order. Both payout loops use this.
function BossLedger.Contributors(key)
	local fight = fights[key]
	return fight and fight.order or {}
end

function BossLedger.Count(key)
	local fight = fights[key]
	return fight and #fight.order or 0
end

--- Everything the board draws, or nil when there is nothing to say. Sorted here rather than in
-- the drawing code because the ranking IS the information -- a board is a view of this table.
function BossLedger.Snapshot()
	local fight = nil
	-- a live fight first, in preference order; otherwise the most recently finished one that is
	-- still inside its result window
	for _, key in ipairs(PREFER) do
		local f = fights[key]
		if f and f.live then fight = f break end
	end
	if not fight then
		local newest = nil
		for _, f in pairs(fights) do
			if f.showUntil and os.clock() <= f.showUntil and (not newest or f.showUntil > newest.showUntil) then
				newest = f
			end
		end
		fight = newest
	end
	if not fight then return nil end

	local ranked = {}
	local total = 0
	for _, userId in ipairs(fight.order) do
		local row = fight.by[userId]
		total += row.damage
		table.insert(ranked, { name = row.name, damage = row.damage, userId = userId })
	end
	table.sort(ranked, function(a, b)
		if a.damage == b.damage then return a.userId < b.userId end
		return a.damage > b.damage
	end)
	for _, row in ipairs(ranked) do
		row.share = total > 0 and (row.damage / total) or 0
	end

	return {
		key = fight.key,
		name = fight.name,
		emoji = fight.emoji,
		where = fight.where,
		live = fight.live,
		hp = fight.hp,
		max = fight.max,
		count = #fight.order,
		result = fight.result,
		ranked = ranked,
	}
end

return BossLedger
