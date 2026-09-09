-- FriendBonusService -- who, of the people in this server right now, is on your friends list (22.1).
--
-- It owns one live map and nothing else. `DNAService.GetIncomeMult` reads the count through
-- `GameConfig.GetFriendBonusMult`, and `DNAService`'s auto-collect tick stamps it onto the save
-- table as `__friendCount` so the HUD pill and the invite button's badge draw the SAME number the
-- server is paying. Nothing here is saved: it is a fact about right now, and a save field would pay
-- a player forever for a friend who logged off in June.

local Players = game:GetService("Players")

local PlayerJoin = require(script.Parent.Systems.PlayerJoin)

local FriendBonusService = {}
local friendGraph = {} -- [UserId] = { [FriendUserId] = true }
local checked = {}     -- ["lowId:highId"] = true -- pairs whose web call has already been made

local function pairKey(a, b)
	if a < b then return a .. ":" .. b end
	return b .. ":" .. a
end

--- Resolve `player` against everyone else in the server, once per pair.
local function scan(player)
	friendGraph[player.UserId] = friendGraph[player.UserId] or {}

	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and other.Parent then
			local key = pairKey(player.UserId, other.UserId)
			if not checked[key] then
				checked[key] = true
				-- `IsFriendsWith` is a WEB CALL, per pair. It yields and it can throw, so it runs
				-- off the join thread (PlayerJoin.onEach gives us one) and inside a pcall -- the
				-- same shape `Telemetry` uses for the same call.
				local ok, isFriend = pcall(function()
					return player:IsFriendsWith(other.UserId)
				end)
				-- Both sides can have left while that call was in flight.
				if ok and isFriend and player.Parent and other.Parent then
					-- Friendship is symmetric, so one call fills both directions and neither side
					-- has to re-ask.
					if friendGraph[player.UserId] then friendGraph[player.UserId][other.UserId] = true end
					if friendGraph[other.UserId] then friendGraph[other.UserId][player.UserId] = true end
				end
			end
		end
	end
end

function FriendBonusService.Init()
	-- ===== `PlayerJoin.onEach`, NOT A BARE `PlayerAdded:Connect` -- THE TENTH VICTIM (22.1) =====
	--
	-- `ServerMain` reaches this Init at line 281, long after `ZoneBuilder.Build()`, so in Studio and
	-- in the first minute of every real shard the player is ALREADY in `Players` and their join
	-- event has fired into nothing. What that cost here is worse than a missed bonus, because the
	-- map was never even created for them:
	--
	--   * `GetFriendCount` returned 0 for that player for the whole session -- no bonus, ever, and
	--     a HUD pill that stays hidden;
	--   * a later joiner B who IS their friend wrote `friendGraph[B][A] = true` and then found
	--     `friendGraph[A]` nil, so only B was paid -- the bonus was asymmetric between two people
	--     looking at each other;
	--   * and on A's `PlayerRemoving` the handler found nothing to unwind, so **B kept being paid
	--     for a friend who had left**, for the rest of the server's life. That is the exact trap
	--     this row was warned about.
	--
	-- See `Systems/PlayerJoin` for why every join handler in this game goes through that helper.
	PlayerJoin.onEach(scan)

	Players.PlayerRemoving:Connect(function(player)
		local leaving = player.UserId

		-- AUTHORITATIVE, not bookkeeping off the leaver's own list. Walking `friendGraph[leaving]`
		-- only works if that entry exists and is complete; sweeping every list cannot leave a stale
		-- entry behind whatever happened on the way in, and the graph is at most one server's worth
		-- of players.
		for _, friends in pairs(friendGraph) do
			friends[leaving] = nil
		end
		friendGraph[leaving] = nil

		-- Forget the pairs too, so a rejoin is re-resolved rather than answered from a cache of a
		-- friendship that may have been removed since.
		for _, other in ipairs(Players:GetPlayers()) do
			checked[pairKey(leaving, other.UserId)] = nil
		end
	end)
end

function FriendBonusService.GetFriendCount(userId)
	local friends = friendGraph[userId]
	if not friends then return 0 end

	local count = 0
	for _ in pairs(friends) do
		count += 1
	end
	return count
end

return FriendBonusService
