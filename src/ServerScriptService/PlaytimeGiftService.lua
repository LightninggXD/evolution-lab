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

--- Bank everything since the last tick and hand back today's row, plus whether that row is a NEW
--- day. THE ONLY WAY to read the daily total: every caller that compares it against a milestone
--- has to see the seconds that have passed since the last tick too, or a player who reaches thirty
--- minutes is told to keep playing for up to another thirty seconds by a number that is out of date.
---
--- THE SECOND RETURN IS WHAT KEEPS THE BOARD HONEST AT MIDNIGHT. `pushStatus` fires on join and on
--- claim and nowhere else, so before this the rollover was invisible to the client: the server had
--- handed the ladder back while the panel still showed yesterday's rungs greyed to `DONE`. Nothing
--- on that panel is then claimable, so no claim is ever fired, so no push ever happens -- the
--- ladder stayed shut for the rest of the session for the one player who was there to see it turn
--- over. Measured, not reasoned about: the panel sat on a stale payload reading `4h 3m played` with
--- all five rungs `DONE` for minutes after the server's row had gone back to zero.
--- Only the TICK acts on this. `pushStatus` calls accrue itself and must not push from inside it.
local function accrue(player, data)
	local userId = player.UserId
	local now = os.time()
	local st = data.DailyPlaytime
	local rolled = false
	if type(st) ~= "table" or st.day ~= dayStamp() then
		-- a save with no row yet is not a rollover -- there is no board state to correct, and the
		-- join push is already on its way
		rolled = type(st) == "table" and st.day ~= nil
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
	return st, rolled
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
	-- THROUGH `GetDailyPlaytimeGift`, NOT AN INDEX INTO THE LIST (21.4). The daily ladder no longer
	-- ends at its fifth entry: past 240 minutes it repeats hourly, for ever, so that there is always
	-- exactly one rung ahead of every player -- which is the whole of 21.4's guarantee. That makes
	-- the index unbounded and a raw `list[i]` nil past five, which would have silently refused every
	-- repeat rung the panel drew. The session ladder is a plain list and stays one; it deliberately
	-- does not repeat (see the note over `GameConfig.DailyPlaytimeRepeat`).
	--
	-- The accessor also does the argument checking this remote needs -- non-numbers, fractions and
	-- anything below 1 come back nil -- and it deliberately has no UPPER bound. It does not need
	-- one: the clock check below is the real gate, and a rung at 900 minutes is one nobody has
	-- played long enough to take.
	--
	-- WRITTEN AS AN `if`, NOT AS `isDaily and a or b`. That idiom falls through to its second branch
	-- whenever the first one is falsy, so a daily claim with a bad index would have been answered
	-- with a SESSION milestone and paid into the daily claim set. Both sides happen to return nil
	-- for every index that reaches it today, which is exactly what makes it the kind of line that
	-- stays wrong until something else changes underneath it.
	local milestone
	if isDaily then
		milestone = GameConfig.GetDailyPlaytimeGift(milestoneIndex)
	else
		milestone = GameConfig.PlaytimeGifts[milestoneIndex]
	end
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

	-- The bank. Every player, every TICK_SECONDS, for as long as the server is up. It is also the
	-- only thing that notices midnight, which is why the rollover push lives here: see `accrue`.
	-- The session claim set resets on the same stamp, so the one push corrects both ladders.
	task.spawn(function()
		while true do
			task.wait(TICK_SECONDS)
			for _, player in ipairs(Players:GetPlayers()) do
				local data = PlayerDataService.Get(player)
				-- no save yet means no row to bank into; lastTick is untouched, so nothing is lost
				if data then
					local _, rolled = accrue(player, data)
					if rolled then pushStatus(player) end
				end
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
