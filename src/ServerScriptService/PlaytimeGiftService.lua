local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS.Remotes

local PlayerDataService = require(script.Parent.PlayerDataService)
local Telemetry = require(script.Parent.Telemetry)

local PlaytimeGiftService = {}

local sessionStart = {} -- [userId] = os.time() when they joined this session

-- WHAT WAS CLAIMED, KEPT IN THE SAVE AND STAMPED WITH A DAY.
--
-- This used to be a module-level table cleared on PlayerRemoving, so the entire gift ladder came
-- back every time a player rejoined. The time gate reset with it, which throttled the exploit
-- rather than stopping it -- but the early milestones are cheap, so a rejoin loop was a free and
-- repeatable DNA and Diamond faucet with no daily cap anywhere.
--
-- Kept in `data.PlaytimeClaims` instead: a set of claimed indices plus the day it belongs to.
-- Rejoining the same day changes nothing; a new day hands the ladder back, which is the intent --
-- these are DAILY playtime gifts, not once-per-account ones.
local function dayStamp()
	return math.floor(os.time() / 86400)
end

local function claimSet(data)
	if type(data.PlaytimeClaims) ~= "table" or data.PlaytimeClaims.day ~= dayStamp() then
		data.PlaytimeClaims = { day = dayStamp() }
	end
	return data.PlaytimeClaims
end

-- ===== THE DAILY ACCUMULATOR (21.3) =====
--
-- `sessionStart` above answers "how long has this sitting been"; nothing answered "how long today",
-- so a player who visits three times for twenty minutes cleared the 10 and the 20 on their first
-- visit and then found every reachable rung already spent for the rest of the day. This is the
-- other clock: seconds played today, added across sessions, kept in the save.
--
-- WHY A TICK AND NOT A LEAVE FLUSH. The obvious shape -- add the session's length on
-- PlayerRemoving -- cannot work here and it fails silently. `PlayerDataService` connects its own
-- PlayerRemoving first (its Init runs first) and that handler SAVES and then drops the cache, so
-- anything this service wrote afterwards would be written to a table nothing reads again. A tick
-- also survives the two ways a session actually ends most often -- a crash and a timeout -- neither
-- of which runs a leave handler at all. The cost is bounded and small: at most TICK_SECONDS of the
-- final minute is lost, against a ladder whose finest rung is thirty minutes.
local TICK_SECONDS = 30

-- When each player's seconds were last banked. In memory, not in the save: it is a mark on the
-- server's clock, and a stale one restored from a save read a week later would bank a week.
local lastTick = {}

--- Bank everything since the last tick and hand back today's row. THE ONLY WAY to read the daily
--- total: every caller that compares it against a milestone has to see the seconds that have
--- passed since the last tick too, or a player who reaches thirty minutes is told to keep playing
--- for up to another thirty seconds by a number that is simply out of date.
local function accrue(player, data)
	local userId = player.UserId
	local now = os.time()
	local st = data.DailyPlaytime
	if type(st) ~= "table" or st.day ~= dayStamp() then
		st = { day = dayStamp(), seconds = 0, claims = {} }
		data.DailyPlaytime = st
		-- The delta being banked straddles midnight and part of it belongs to yesterday. It is at
		-- most one tick, and the day it belongs to is already over, so it is dropped rather than
		-- split -- splitting it would buy nothing but a rung nobody is awake to claim.
		lastTick[userId] = now
	end
	if type(st.claims) ~= "table" then st.claims = {} end
	-- clamped at zero: os.time() can step backwards over an NTP correction, and a negative delta
	-- would take time OFF a total that is only ever supposed to grow
	st.seconds = (st.seconds or 0) + math.max(0, now - (lastTick[userId] or now))
	lastTick[userId] = now
	return st
end

--- A claim set keyed by tostring(index), as the LIST the client wants.
--- Keys are strings because a table whose only key is [3] is a sparse array and Roblox silently
--- drops those crossing a RemoteEvent -- the bug that once ate EquippedCharacters. The session
--- set's `day`, and the daily row's `seconds`, fall out here on tonumber.
local function claimedList(set)
	local out = {}
	for k in pairs(set) do
		local idx = tonumber(k)
		if idx then table.insert(out, idx) end
	end
	return out
end

local function pushStatus(player)
	local data = PlayerDataService.Get(player)
	local payload = {
		sessionStart = sessionStart[player.UserId],
		claimed = {},
		dailyClaimed = {},
	}
	if data then
		payload.claimed = claimedList(claimSet(data))
		local st = accrue(player, data)
		payload.dailyClaimed = claimedList(st.claims)
		-- A VIRTUAL START TIME RATHER THAN A DURATION, and that is what lets the client tick this
		-- ladder with the exact expression it already ticks the session one: `os.time() - start`.
		-- Sending `seconds` instead would need a second, different countdown on the client plus a
		-- record of when the payload landed -- two more things to get wrong for no gain. It is also
		-- self-correcting: this fires again after every claim, so any drift is one payload wide.
		payload.dailyStart = os.time() - (st.seconds or 0)
	end
	Remotes.PlaytimeStatus:FireClient(player, payload)
end

--- `ladder` is "daily" for GameConfig.DailyPlaytimeGifts and anything else for the session ladder.
--- ONE FUNCTION FOR BOTH, because everything after the gate -- the grants, the telemetry, the two
--- pushes and the toast -- is identical, and a second copy of it is a second place for a payout to
--- drift out of step with the board that advertises it. Only the clock and the claim set differ.
function PlaytimeGiftService.HandleClaim(player, milestoneIndex, ladder)
	local data = PlayerDataService.Get(player)
	if not data then return end
	local isDaily = ladder == "daily"
	local milestone = (isDaily and GameConfig.DailyPlaytimeGifts or GameConfig.PlaytimeGifts)[milestoneIndex]
	if not milestone then return end

	local claims, elapsedMinutes
	if isDaily then
		-- accrue, not a read: the banked total is up to TICK_SECONDS stale, and the player standing
		-- in front of a button that has just turned green is exactly the case that would trip on it
		local st = accrue(player, data)
		claims = st.claims
		elapsedMinutes = st.seconds / 60
	else
		claims = claimSet(data)
		elapsedMinutes = (os.time() - (sessionStart[player.UserId] or os.time())) / 60
	end

	local slot = tostring(milestoneIndex)
	if claims[slot] then
		Remotes.Notify:FireClient(player, { kind = "error", message = "Already claimed that gift today!" })
		return
	end

	if elapsedMinutes < milestone.minutes then
		Remotes.Notify:FireClient(player, { kind = "error", message = "Keep playing! Not ready yet." })
		return
	end

	claims[slot] = true

	-- see GameConfig.ScaleReward: a flat 35,000 stops being a gift about fifteen minutes in
	if milestone.dna then
		local paid = GameConfig.ScaleReward(milestone.dna, data)
		data.DNA += paid
		Telemetry.Economy(player, "Source", Telemetry.Currency.DNA, paid, data.DNA,
			Telemetry.Tx.TimedReward, "playtimeGift")
	end
	if milestone.potions then GameConfig.AddPotions(data, milestone.potionId, milestone.potions) end
	if milestone.diamonds then
		data.Diamonds = (data.Diamonds or 0) + milestone.diamonds
		Telemetry.Economy(player, "Source", Telemetry.Currency.Diamonds, milestone.diamonds,
			data.Diamonds, Telemetry.Tx.TimedReward, "playtimeGift")
	end

	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.PushToClient(player)
	Remotes.Notify:FireClient(player, {
		kind = "playtimeGift", minutes = milestone.minutes, daily = isDaily or nil,
	})
	pushStatus(player)
end

function PlaytimeGiftService.Init()
	Players.PlayerAdded:Connect(function(player)
		sessionStart[player.UserId] = os.time()
		-- BEFORE the wait, and before the save is necessarily loaded. Whatever the load costs is
		-- time the player spent in the game, and the first accrue that finds a save banks it.
		lastTick[player.UserId] = os.time()
		-- the save may still be loading; pushStatus reads it and simply reports nothing claimed
		-- until it is there, and the client re-reads on its next DataUpdate
		task.wait(0.5)
		pushStatus(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		sessionStart[player.UserId] = nil
		-- NOT flushed here, on purpose -- see TICK_SECONDS. PlayerDataService has already saved and
		-- dropped the cache by the time this runs, so a bank now would be written to nothing.
		lastTick[player.UserId] = nil
	end)

	-- The bank. Every player, every TICK_SECONDS, for as long as the server is up.
	task.spawn(function()
		while true do
			task.wait(TICK_SECONDS)
			for _, player in ipairs(Players:GetPlayers()) do
				local data = PlayerDataService.Get(player)
				-- no save yet means no row to bank into; lastTick is untouched, so nothing is lost
				if data then accrue(player, data) end
			end
		end
	end)

	Remotes.ClaimPlaytimeGift.OnServerEvent:Connect(function(player, milestoneIndex, ladder)
		-- the second argument is optional, and every value that is not the string "daily" means the
		-- session ladder, so a payload of one number still claims exactly what it always did
		if typeof(milestoneIndex) == "number" then
			PlaytimeGiftService.HandleClaim(player, milestoneIndex, typeof(ladder) == "string" and ladder or nil)
		end
	end)
end

return PlaytimeGiftService
