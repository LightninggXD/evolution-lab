-- PlayerJoin -- the one shape a service is allowed to use to say "do this for every player".
--
-- ===== WHY THIS MODULE EXISTS: A PLAYER WHO IS ALREADY HERE NEVER FIRES `PlayerAdded` (35.13) =====
--
-- 35.2 found this in `PlayerDataService` and fixed it there, in that one file, with a named handler
-- and a replay over `Players:GetPlayers()`. **It is not one file's bug.** `ServerMain` builds the
-- world at line 99 and that takes about a minute; every service initialised after it -- which is
-- all of them -- connects `PlayerAdded` long after the player is already sitting in `Players`, and
-- their join event has already fired into nothing. Studio does it on every Play, and a real server
-- does it to anybody who joins during a restart or a fresh shard's first minute.
--
-- Swept 2026-09-06 (20th) and it had eight live victims: no game passes at all for the session
-- (`PassService`), no offline earnings and no Welcome Back card (`OfflineService`), no zone unlock
-- check and no legacy-collection top-up (`ServerMain`), event skins never synced onto the save
-- (`EventService`), never returned to your own zone when you respawn (`ZoneService`), an expedition
-- run that never ends when you die (`ExpeditionService`), an adventure counter that runs forever
-- past a respawn (`AdventureService`), and a refund the player is never told about
-- (`SplicerService`).
--
-- ===== THE THREE THINGS THE CALLER MUST NOT HAVE TO REMEMBER =====
--
-- 1. **Connect BEFORE replaying.** The other order drops anybody who joins in the gap.
-- 2. **Exactly once per player**, because the two halves overlap by construction -- that is what
--    `handled` is for, and it is the same guard 35.2 wrote by hand. Running a join handler twice on
--    one save is how `OfflineService` would pay offline earnings twice.
-- 3. **Its own thread**, because most of these handlers yield on a DataStore read and one that
--    blocked the replay loop would stall every player behind it.
--
-- The entry is cleared on `PlayerRemoving`, so a rejoin is a new join and runs again -- which is
-- what `PlayerAdded` would have done.

local Players = game:GetService("Players")

local PlayerJoin = {}

--- Run `handler(player)` for every player who joins AND for every player already in the server.
-- Returns the `RBXScriptConnection` so a caller that needs to stop listening can.
function PlayerJoin.onEach(handler)
	local handled = {}

	local function run(player)
		if handled[player.UserId] then return end
		handled[player.UserId] = true
		task.spawn(handler, player)
	end

	-- One shared forget-connection per call. It is cheap and it keeps `handled` from growing over
	-- the life of a server, which matters on a shard that cycles a few hundred players a day.
	Players.PlayerRemoving:Connect(function(player)
		handled[player.UserId] = nil
	end)

	local conn = Players.PlayerAdded:Connect(run)
	for _, player in ipairs(Players:GetPlayers()) do
		run(player)
	end
	return conn
end

return PlayerJoin
