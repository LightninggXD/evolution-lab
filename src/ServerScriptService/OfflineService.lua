--[[
	OfflineService -- what the player earned while they were away.

	The strongest single reason to come back in this genre, and the one that is easiest to get
	catastrophically wrong: an offline rate that is not bounded against the online one is a game
	where the optimal move is to stop playing.

	It is safe to build HERE, on this codebase, for one specific reason. `DNAService.GetAutoCollect
	Amount` is already expressed as a FRACTION OF ONE CLICK PER SECOND, capped at 1.2 -- that cap
	exists because idle income once paid eighty clicks a second and broke every price in the game
	(the long note over that function is worth reading before touching any number in here). Offline
	income is that same capped rate times a bounded number of seconds times a factor below 1, so the
	ordering it has to preserve holds by construction:

	    playing  >  idling online  >  being offline

	THREE THINGS THAT WOULD EACH PAY TWICE, and what stops them:

	  * The seconds live in `PlayerDataService.OfflineSeconds`, in memory, and are CONSUMED (set to
	    nil) before the payout is computed. Not after -- a yield between reading and clearing is a
	    double payout, and there is no reason to leave that door open even though nothing here yields.
	  * They are never written to the save. A pending-payout field in a DataStore survives a crash,
	    and a payout that survives a crash is a payout collected twice. See the note in Load.
	  * `LastSeen` is stamped on every autosave rather than only on the leave-save, so a server that
	    dies without running its leave-save cannot leave a player looking eight hours idle.

	A player with no AutoCollect levels earns nothing, and that is correct rather than an oversight:
	this feature IS the auto-collect upgrade continuing while you are away. It gives that upgrade a
	second reason to exist and it means offline income can never appear before the player has bought
	anything.
--]]

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS.Remotes

local PlayerDataService = require(script.Parent.PlayerDataService)
local DNAService = require(script.Parent.DNAService)

local OfflineService = {}

-- "8h 20m", "45m", "3m" -- never "8h 0m", and never seconds, because the card is a headline and
-- the exact figure is not what the player is reading it for.
local function humanise(seconds)
	seconds = math.floor(seconds)
	local hours = seconds // 3600
	local minutes = (seconds % 3600) // 60
	if hours > 0 then
		if minutes > 0 then
			return ("%dh %dm"):format(hours, minutes)
		end
		return ("%dh"):format(hours)
	end
	if minutes > 0 then
		return ("%dm"):format(minutes)
	end
	return ("%ds"):format(seconds)
end

-- Pays whatever this player is owed and returns (amount, creditedSeconds). Public so it can be
-- driven in a test rather than only by a rejoin -- the same reason PassService.GrantVipDaily is.
function OfflineService.Grant(player)
	local data = PlayerDataService.Get(player)
	if not data then return 0, 0 end

	-- CONSUMED FIRST. Everything below is arithmetic on locals, so a second call -- a double
	-- PlayerAdded, a retry, a test -- finds nothing left to pay rather than paying again.
	local seconds = PlayerDataService.OfflineSeconds[player.UserId] or 0
	PlayerDataService.OfflineSeconds[player.UserId] = nil
	if seconds <= 0 then return 0, 0 end

	local perSecond = DNAService.GetAutoCollectAmount(data)
	if perSecond <= 0 then return 0, seconds end

	local amount = math.floor(perSecond * seconds * GameConfig.OfflineRate)
	if amount <= 0 then return 0, seconds end

	data.DNA += amount
	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.PushToClient(player)
	Remotes.Notify:FireClient(player, {
		kind = "offline",
		amount = amount,
		seconds = seconds,
		-- pre-formatted rather than sent raw: the client would have to write this function again,
		-- and the two copies would drift the first time either was edited
		away = humanise(seconds),
		-- so the card can say "(capped at 8h)" honestly when it is, and say nothing when it is not
		capped = seconds >= GameConfig.OfflineMaxHours * 3600,
	})
	return amount, seconds
end

function OfflineService.Init()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			-- The same wait-for-data shape ServerMain uses. It has to wait: Load yields on a
			-- DataStore read, and GetAutoCollectAmount needs the upgrades that read brings back.
			local data
			repeat
				task.wait(0.2)
				data = PlayerDataService.Get(player)
			until data or not player.Parent
			if not data or not player.Parent then return end
			-- a beat behind the join so the welcome-back card does not land underneath the loading
			-- screen it would otherwise be drawn behind
			task.wait(1.5)
			if player.Parent then
				OfflineService.Grant(player)
			end
		end)
	end)
end

return OfflineService
