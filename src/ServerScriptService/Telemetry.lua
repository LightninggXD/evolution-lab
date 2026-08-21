-- ===== TELEMETRY (Phase 20) ===================================================================
--
-- Every analytics call in the game goes through this file and nothing else calls
-- `AnalyticsService` directly. That is not tidiness -- it is what makes the instrumentation
-- testable at all. Roblox's analytics service RECORDS NOTHING IN STUDIO: the calls validate their
-- arguments and then return, and the dashboard is the only place the result ever appears, 24 hours
-- later, in a published place. So a wrapper that only forwarded would be code no agent could ever
-- verify -- "it compiles" would be the whole check.
--
-- Instead every call is counted here, into `Telemetry.Stats`, BEFORE it is forwarded, and the
-- forward itself is wrapped so a rejected argument is counted separately from an accepted one.
-- That turns "does the funnel fire" into a question a probe can answer in Play in one second:
-- drive the game, read the table, compare. See the Phase 20 rows in ROADMAP.md for what each row
-- was actually checked against.
--
-- ===== WHY HALF THE ECONOMY IS BATCHED AND HALF IS NOT =======================================
--
-- `LogEconomyEvent` is a per-transaction call, and this game has two faucets that are not
-- transactions in any useful sense:
--
--   * the kill reward (`CreatureService`), described in its own comments as "the most frequent
--     event in the game";
--   * auto-collect (`DNAService`), which pays EVERY PLAYER EVERY SECOND, forever.
--
-- Auto-collect alone is 3,600 events per player per hour. A 30-player server would be pushing
-- 108,000 economy events an hour for one faucet, which is both far past what the service will
-- accept and useless when it arrives -- nobody reads a histogram of one second of income.
--
-- So there are two entry points, and the choice between them is about FREQUENCY, never importance:
--
--   Telemetry.Economy(...)  one event, sent now.  Discrete decisions: a purchase, an upgrade,
--                           a claim, a hatch, a rebirth refund. These are the rows a designer
--                           reads one at a time.
--   Telemetry.Accrue(...)   added to a per-player bucket keyed by flow/currency/type/sku and
--                           flushed once a minute (and on leave, and on shutdown). The TOTAL is
--                           exact -- nothing is sampled or dropped -- only the granularity is
--                           coarser. The ending balance stamped on a flush is the balance at
--                           flush time, which is the correct one: it is where the player actually
--                           stands when the aggregate lands.
--
-- Getting this backwards is the trap. Batching a purchase would make the one event that pays for
-- the game arrive up to a minute late and merged with other purchases; sending every kill would
-- silently exceed the service's limit and lose ALL of them, including the ones that mattered.
--
-- ===== THE FUNNEL ONLY EVER RUNS FOR A SAVE THAT WAS BORN INSTRUMENTED =======================
--
-- `LogOnboardingFunnelStepEvent` is a lifetime funnel: it answers "of everyone who ever reached
-- step 3, how many reached step 4". Firing it for a player with a thousand hours would enter them
-- at whatever step they happened to trip first -- a veteran opening an egg is a step-8 event with
-- no steps 1-7 under it -- and the drop-off curve every later phase is measured against would be
-- reading a mixture of first sessions and thousandth ones.
--
-- So `PlayerDataService.Load` stamps the save (see `data.Funnel` there): a NEW save gets an empty
-- table and is followed step by step for the rest of its life; a save that already existed when
-- this shipped gets `{ pre = true }` and is never logged. `Telemetry.Funnel` refuses anything
-- with that marker. The cost is that the funnel is empty on the day it ships and fills from the
-- first genuinely new player onwards, which is exactly what it should measure.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")

local Telemetry = {}

-- ===== THE COUNTERS ARE THE TEST SURFACE ======================================================
-- `sent` counts a call the service accepted, `failed` one it threw on, and the per-key tables are
-- what a probe reads to prove a specific event fired with specific arguments. Kept forever (they
-- are a handful of integers) and never pushed anywhere -- nothing in the game reads them.
Telemetry.Stats = {
	sent = 0,
	failed = 0,
	lastError = nil,
	funnel = {},   -- [stepName] = count
	economy = {},  -- ["Source/DNA/Gameplay/kill"] = { count = n, amount = n }
	custom = {},   -- [eventName] = count
}

-- ===== THE EIGHT STEPS (20.1) =================================================================
-- The numbers are the funnel's identity on the dashboard and MUST NOT BE REORDERED -- step 4 in a
-- chart drawn next week is compared against step 4 recorded today. Adding a step means appending
-- a number, never inserting one.
Telemetry.FunnelSteps = {
	joined       = 1,  -- the server has their save
	loaded       = 2,  -- the loading screen has handed the world over
	firstSwing   = 3,  -- they have attacked something
	firstKill    = 4,  -- something died
	firstEvolve  = 5,  -- the core loop closed once
	tutorialDone = 6,  -- the guided sequence finished
	firstZone    = 7,  -- they went somewhere new
	firstEgg     = 8,  -- they spent on the shop side of the game
}

local ECONOMY_FLOW = {
	Source = Enum.AnalyticsEconomyFlowType.Source,
	Sink   = Enum.AnalyticsEconomyFlowType.Sink,
}

-- The five transaction types this game actually uses, as the strings the API wants. Named here so
-- a typo is a nil at the call site rather than a string the dashboard silently accepts and buckets
-- under its own name forever.
Telemetry.Tx = {
	IAP         = Enum.AnalyticsEconomyTransactionType.IAP.Name,          -- Robux
	Shop        = Enum.AnalyticsEconomyTransactionType.Shop.Name,         -- spent in-game
	Gameplay    = Enum.AnalyticsEconomyTransactionType.Gameplay.Name,     -- earned by playing
	TimedReward = Enum.AnalyticsEconomyTransactionType.TimedReward.Name,  -- daily, playtime, offline
	Onboarding  = Enum.AnalyticsEconomyTransactionType.Onboarding.Name,
}

Telemetry.Currency = { DNA = "DNA", Diamonds = "Diamonds", Shards = "EvolutionShards" }

-- ===== WHO COUNTS AS A REACHABLE PLAYER (20.6) ================================================
--
-- Every entry point below asks `reachable(player)` rather than testing `player.Parent` directly,
-- and the comment that used to stand here gave the wrong reason for it. It said `PlayerRemoving`
-- hands over an already-unparented player, so the parent guard refused every call this module
-- makes at the door. THAT IS MEASURED FALSE. On 2026-08-20 a probe was placed INSIDE
-- `Telemetry.Custom` and `Telemetry.Economy` -- not in an outside hook choosing its own moment --
-- and it printed the parent on the exact calls `SessionEnd` and `flush` make. All four: parent is
-- `Players`, `typeof` is `Instance`, from the first call of the removal sequence to the last. The
-- old guard would have PASSED every one of them. **The parent never goes nil while this handler
-- runs, and `reachable` is a no-op on this path.**
--
-- What actually deleted both reports was the SHAPE OF THE HANDLER. `flush(player)` was a bare call
-- sitting directly above `Telemetry.SessionEnd`, so a throw anywhere inside it stopped the drain
-- part-way AND propagated out of the handler before `SessionEnd` was ever reached -- one cause for
-- both halves of the symptom, nothing sent at the door and no `Session*` event in existence. It
-- also explains why `Stats.failed` stayed at 0 while this was happening: `send()`'s pcall is the
-- only thing that raises that counter, and the throw was above `send`. So the two calls below are
-- separately wrapped, and that is not defensive habit -- they are two independent reports about one
-- departure and neither may be allowed to cancel the other.
--
-- WHICH statement in the old `flush` threw cannot be recovered: this file enters git history
-- already patched, so that body exists nowhere on disk or in Studio. The split is what fixed the
-- outcome and is also what would have named the culprit had it been there at the time.
--
-- `reachable` is KEPT rather than reverted, for one reason that survives the correction:
-- `BindToClose` opens the same door, and a server tearing down genuinely can unparent before that
-- callback runs, with nothing left afterwards to observe it. It costs one table lookup. The async
-- callers keep their own `player.Parent` test on purpose -- see the friend count in `Init`, where a
-- reward landing after the player has gone really is a call at nobody.
local leaving = {}   -- [userId] = true only for the duration of that player's departure

local function reachable(player)
	if not player then return false end
	if player.Parent then return true end
	return leaving[player.UserId] == true
end

-- ===== THE FORWARD ============================================================================
-- One pcall for the whole file. Every argument this game passes is built from a constant table
-- above or from a number it just wrote into the save, so a throw here means a genuine mistake --
-- a nil player, a negative amount, a currency name over the length limit -- and `lastError` is
-- how a probe sees it instead of the output window scrolling past.
local function send(fn, ...)
	local ok, err = pcall(fn, ...)
	if ok then
		Telemetry.Stats.sent += 1
	else
		Telemetry.Stats.failed += 1
		Telemetry.Stats.lastError = tostring(err)
	end
	return ok
end

local function bump(tbl, key, amount)
	local row = tbl[key]
	if not row then
		row = { count = 0, amount = 0 }
		tbl[key] = row
	end
	row.count += 1
	row.amount += (amount or 0)
	return row
end

-- ===== 20.1  ONBOARDING FUNNEL ================================================================

function Telemetry.Funnel(player, stepKey, data)
	local step = Telemetry.FunnelSteps[stepKey]
	if not step then return end
	if not reachable(player) then return end

	-- No save, no funnel. Every step below step 2 can fire before the load has finished on a slow
	-- read, and a funnel row with no player state behind it is worse than a missing one.
	if not data then return end
	local seen = data.Funnel
	-- `pre = true` is a save that predates the instrumentation -- see the header. `nil` is a save
	-- that has not been through Load yet, which can only happen in a probe.
	if type(seen) ~= "table" or seen.pre then return end
	if seen[stepKey] then return end
	seen[stepKey] = true

	Telemetry.Stats.funnel[stepKey] = (Telemetry.Stats.funnel[stepKey] or 0) + 1
	send(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepKey)
	end)
end

-- ===== 20.2  ECONOMY ==========================================================================

-- One transaction, sent now. `amount` is always POSITIVE -- the direction is `flow`, not the sign,
-- and a negative amount is one of the two things the service rejects outright.
function Telemetry.Economy(player, flow, currency, amount, endingBalance, txType, sku)
	if not reachable(player) then return end
	amount = math.floor(math.abs(tonumber(amount) or 0))
	if amount <= 0 then return end
	local flowEnum = ECONOMY_FLOW[flow]
	if not flowEnum then return end
	endingBalance = math.max(0, math.floor(tonumber(endingBalance) or 0))

	bump(Telemetry.Stats.economy, table.concat({ flow, currency, txType, sku or "-" }, "/"), amount)
	send(function()
		AnalyticsService:LogEconomyEvent(player, flowEnum, currency, amount, endingBalance, txType, sku)
	end)
end

-- The batched half. Nothing is sent here; the bucket is drained by `flush` below.
local buckets = {}    -- [userId] = { [key] = { flow, currency, txType, sku, amount } }

function Telemetry.Accrue(player, flow, currency, amount, txType, sku)
	if not player then return end
	amount = math.abs(tonumber(amount) or 0)
	if amount <= 0 then return end
	if not ECONOMY_FLOW[flow] then return end

	local mine = buckets[player.UserId]
	if not mine then
		mine = {}
		buckets[player.UserId] = mine
	end
	local key = table.concat({ flow, currency, txType, sku or "-" }, "/")
	local row = mine[key]
	if not row then
		row = { flow = flow, currency = currency, txType = txType, sku = sku, amount = 0 }
		mine[key] = row
	end
	row.amount += amount
end

-- Drains one player's bucket. The balance is read at flush time on purpose -- see the header.
-- `PlayerDataService` is required lazily: this module is required BY several services that
-- PlayerDataService does not require, and taking it at the top would close a cycle.
local function flush(player)
	local mine = buckets[player.UserId]
	if not mine then return end
	buckets[player.UserId] = nil

	local ok, PlayerDataService = pcall(function()
		return require(game:GetService("ServerScriptService").PlayerDataService)
	end)
	local data = ok and PlayerDataService.Get(player) or nil
	if not data then return end

	local balanceOf = {
		[Telemetry.Currency.DNA] = data.DNA or 0,
		[Telemetry.Currency.Diamonds] = data.Diamonds or 0,
		[Telemetry.Currency.Shards] = data.EvolutionShards or 0,
	}
	for _, row in pairs(mine) do
		Telemetry.Economy(player, row.flow, row.currency, row.amount,
			balanceOf[row.currency] or 0, row.txType, row.sku)
	end
end

Telemetry.Flush = flush

-- ===== 20.3  CUSTOM EVENTS ====================================================================

function Telemetry.Custom(player, eventName, value)
	if not reachable(player) then return end
	if type(eventName) ~= "string" or eventName == "" then return end
	value = tonumber(value)

	Telemetry.Stats.custom[eventName] = (Telemetry.Stats.custom[eventName] or 0) + 1
	send(function()
		AnalyticsService:LogCustomEvent(player, eventName, value)
	end)
end

-- ===== 20.4  SESSION-END STATE ================================================================
--
-- The question this answers is "did the session end with unfinished business", because that is
-- what brings a player back tomorrow. Four separate custom events rather than one with three
-- fields, so each arrives as its own DISTRIBUTION on the dashboard -- an average of "how full was
-- the bar" tells you nothing; the shape of it tells you whether the game is producing near-misses
-- or leaving people at zero.
--
-- Every read below is defensive. This runs inside `PlayerRemoving`, where a save can be half
-- migrated, a service can be mid-require, and the player's character is already gone.

local sessionStart = {}   -- [userId] = os.clock()

--- ===== 21.4  THE PLAYTIME LADDERS AS SESSION-END CARRIERS ====================================
---
--- Returns (readyRungs, minutesToNextRung). `readyRungs` is how many unclaimed rungs are already
--- due across both ladders; `minutesToNextRung` is how far the nearest running countdown is from
--- paying, or nil if there is no countdown at all -- which, since 21.4 gave the daily ladder an
--- endless repeating rung, should never happen for a loaded save. It is 0 whenever something is
--- already due, because "the nearest unfinished thing" is then on the table rather than ahead.
---
--- READ OFF `data` AND `GameConfig` AND NOTHING ELSE. The obvious shape -- ask `PlaytimeGiftService`
--- -- cannot be written here: that service requires this file, so requiring it back is a cycle, and
--- this runs inside `PlayerRemoving` where a mid-require service is exactly the hazard every other
--- read in `SessionEnd` is already defensive about. Both claim sets and the daily accumulator live
--- in the save, so nothing is lost by reading them directly.
---
--- The daily row is up to one 30-second tick stale by construction (see `PlaytimeGiftService`'s
--- note over `TICK_SECONDS`), which on a ladder whose finest rung is thirty minutes moves a
--- reported "next rung" by at most half a minute.
local function playtimeCarriers(data, sessionSeconds)
	local ok, GameConfig = pcall(function()
		return require(game:GetService("ReplicatedStorage").Modules.GameConfig)
	end)
	-- The same defensiveness every other read in `SessionEnd` carries, and for the same reason: this
	-- runs inside `PlayerRemoving`. A missing list or a missing accessor means a build mismatch, not
	-- a player state, and it must cost this report rather than the three above it.
	if not ok or not GameConfig then return 0, nil end
	if type(GameConfig.PlaytimeGifts) ~= "table"
		or type(GameConfig.DailyPlaytimeGifts) ~= "table"
		or type(GameConfig.GetDailyPlaytimeGift) ~= "function" then
		return 0, nil
	end

	local today = math.floor(os.time() / 86400)
	local ready, nearest = 0, nil

	--- One ladder. `claims` is keyed by `tostring(index)` -- the string keys `PlaytimeGiftService`
	--- uses so a sparse array is never handed to a RemoteEvent -- and `extraIndex`, when given, is
	--- the daily ladder's next repeating rung, which has no entry in any list.
	local function walk(list, claims, elapsed, extraIndex)
		local function consider(index, milestone)
			if not milestone or claims[tostring(index)] then return end
			local remaining = milestone.minutes * 60 - elapsed
			if remaining <= 0 then
				ready += 1
			elseif not nearest or remaining < nearest then
				nearest = remaining
			end
		end
		for i, milestone in ipairs(list) do
			consider(i, milestone)
		end
		if extraIndex then
			consider(extraIndex, GameConfig.GetDailyPlaytimeGift(extraIndex))
		end
	end

	-- THE SESSION LADDER, against this file's own session clock rather than `PlaytimeGiftService`'s.
	-- They are two marks on the same sitting, stamped one `PlayerAdded` apart, and the difference
	-- is milliseconds against rungs measured in tens of minutes.
	local sessionClaims = data.PlaytimeClaims
	if sessionSeconds and type(sessionClaims) == "table" and sessionClaims.day == today then
		walk(GameConfig.PlaytimeGifts, sessionClaims, sessionSeconds, nil)
	elseif sessionSeconds then
		-- no claim set for today means nothing has been taken, not that the ladder is missing
		walk(GameConfig.PlaytimeGifts, {}, sessionSeconds, nil)
	end

	-- THE DAILY LADDER, plus the one repeating rung past it -- which is the rung the guarantee
	-- rests on. Its index is the lowest past the authored list this player has not taken, found the
	-- same way the panel finds it.
	local daily = data.DailyPlaytime
	if type(daily) == "table" and daily.day == today then
		local claims = type(daily.claims) == "table" and daily.claims or {}
		local list = GameConfig.DailyPlaytimeGifts
		local nextRepeat = #list + 1
		while claims[tostring(nextRepeat)] do
			nextRepeat += 1
		end
		walk(list, claims, daily.seconds or 0, nextRepeat)
	end

	if ready > 0 then return ready, 0 end
	return ready, nearest and math.floor(nearest / 60) or nil
end

function Telemetry.SessionEnd(player, data)
	if not player then return end
	local started = sessionStart[player.UserId]
	sessionStart[player.UserId] = nil
	if started then
		-- minutes, floored -- the dashboard buckets integers and a session is never interesting
		-- to the second
		Telemetry.Custom(player, "SessionMinutes", math.floor((os.clock() - started) / 60))
	end
	if not data then return end

	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local okCfg, GameConfig = pcall(function()
		return require(ReplicatedStorage.Modules.GameConfig)
	end)

	-- (a) THE BAR. `GetEvolveStep` is the one function that knows what the next press costs, so it
	-- is also the only honest denominator -- the HUD draws this exact ratio.
	-- HOISTED OUT OF THE `if` BY 21.4, which reads it back at the bottom of this function. It stays
	-- 0 for a maxed save, and that is the right answer rather than a missing one: a player with no
	-- next evolve has no bar, so the bar is not one of their carriers. The EVENT is still skipped in
	-- that case -- a 0 in that distribution would read as "nowhere near" instead of "not applicable".
	local barPct = 0
	if okCfg and GameConfig and GameConfig.GetEvolveStep then
		local okStep, step = pcall(GameConfig.GetEvolveStep, data)
		if okStep and step and not step.isMax and (step.xpCost or 0) > 0 then
			barPct = math.clamp(math.floor(((data.XP or 0) / step.xpCost) * 100), 0, 100)
			Telemetry.Custom(player, "SessionEndEvolveBarPct", barPct)
		end
	end

	-- (b) CLAIMABLE THINGS LEFT ON THE TABLE, as a count. Each one is a reason to open the game
	-- tomorrow, and a player who logs out with three of them pending is a different player from
	-- one who logged out having swept the board.
	local claimable = 0
	local ServerScriptService = game:GetService("ServerScriptService")
	local okReward, RewardService = pcall(function()
		return require(ServerScriptService.RewardService)
	end)
	if okReward and RewardService then
		if RewardService.GetStatus then
			local okS, can = pcall(RewardService.GetStatus, data)
			if okS and can then claimable += 1 end
		end
		if RewardService.GetFreeSpinStatus then
			local okS, ready = pcall(RewardService.GetFreeSpinStatus, data)
			if okS and ready then claimable += 1 end
		end
	end
	Telemetry.Custom(player, "SessionEndClaimable", claimable)

	-- (c) A RUNNING TIMER. A potion still ticking when the session ends is time the player paid
	-- for and did not spend, which is the single strongest reason to come straight back.
	local timers = 0
	local now = os.time()
	if type(data.PotionBoosts) == "table" then
		for _, boost in pairs(data.PotionBoosts) do
			if type(boost) == "table" and (tonumber(boost.untilTs) or 0) > now then
				timers += 1
			end
		end
	end
	Telemetry.Custom(player, "SessionEndTimers", timers)

	-- ===== 21.4  DID THE GUARANTEE HOLD, AND HOW HARD WAS IT PULLING =========================
	--
	-- 20.4 asks whether a session ended with unfinished business. 21.4 is the row that makes the
	-- answer always yes, and these two events are how that claim is checked against reality rather
	-- than asserted in a comment.
	--
	-- THE READ IS WIDER THAN THE THREE EVENTS ABOVE, AND DELIBERATELY SO. (b) counts only the daily
	-- login reward and the free spin, and (c) only potion boosts, because those were the numbers
	-- 20.4 was opened to shape and they must keep meaning exactly what they meant on the day they
	-- started arriving -- a widened `SessionEndTimers` would silently rebase its own distribution
	-- and make every figure from before this row uncomparable. So nothing above changes. What the
	-- PLAYER has pending is a bigger set than either, and the two playtime ladders are most of the
	-- difference: they are running clocks with a reward on the end, which is the definition the row
	-- uses, and since 21.4 the daily one never runs out.
	local ready, nextMinutes = playtimeCarriers(data, started and (os.clock() - started) or nil)

	-- SENT AS AN ALARM, NOT AS A DISTRIBUTION, and that distinction is worth stating because a
	-- metric that is 1 by construction looks like a broken metric. After this row a running daily
	-- countdown always exists, so this should be 1 on every session that ever ends. It is here
	-- precisely so that the day it is not -- a config edited to a finite ladder, a save whose
	-- `DailyPlaytime` row never loaded, a rollover that left the board empty -- the dashboard says so
	-- instead of the guarantee quietly becoming untrue.
	local unfinished = 0
	if barPct >= 80 or claimable > 0 or timers > 0 or ready > 0 or nextMinutes then
		unfinished = 1
	end
	Telemetry.Custom(player, "SessionEndUnfinished", unfinished)

	-- AND THIS ONE IS THE DISTRIBUTION, which is what 20.4 was still owed. "Is there something
	-- pending" stops being interesting once the answer is always yes; "how close was it" does not.
	-- A cohort that leaves three minutes from a reward and a cohort that leaves fifty-five minutes
	-- from one are the same 1 above and completely different games, and the difference is what says
	-- whether the rung spacing is right. Zero means something was ON THE TABLE when they left --
	-- the strongest pull there is, and the one the tile badge exists to make visible.
	if nextMinutes then
		Telemetry.Custom(player, "SessionEndNextRungMins", nextMinutes)
	end
end

-- ===== THE TWO STEPS ONLY THE CLIENT CAN SEE ==================================================
--
-- Six of the eight funnel steps are server facts and are fired from the service that owns them.
-- Two are not, and no amount of server-side inference recovers them:
--
--   `loaded`       -- the loading screen has finished its wipe and handed the world over. The
--                     server knows when it PUSHED the data, not when the client stopped covering
--                     the screen with it, and the gap between those is the entire question the
--                     step exists to answer.
--   `tutorialDone` -- FirstJoin's guided sequence reached its last beat. `data.TutorialDone` is
--                     set by the first evolve, seconds earlier; this is the client actually
--                     getting to the end of the card.
--
-- ===== A CLIENT MAY ONLY REPORT THOSE TWO, AND THE WHITELIST IS WHY THIS IS A TABLE ==========
--
-- Everything else in the funnel is a claim about the world -- a kill, an egg, a zone change --
-- and a client that could report those could report never having played, or having finished the
-- funnel on the join frame. The remote below refuses any key not in `CLIENT_STEPS`, so the worst
-- a modified client can do is lie about how fast its own loading screen went away.
local CLIENT_STEPS = { loaded = true, tutorialDone = true }

-- ===== INIT ===================================================================================

function Telemetry.Init()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end
	local reportStep = remotes:FindFirstChild("TelemetryStep")
	if not reportStep then
		reportStep = Instance.new("RemoteEvent")
		reportStep.Name = "TelemetryStep"
		reportStep.Parent = remotes
	end
	reportStep.OnServerEvent:Connect(function(player, stepKey)
		if type(stepKey) ~= "string" or not CLIENT_STEPS[stepKey] then return end
		local ok, PlayerDataService = pcall(function()
			return require(game:GetService("ServerScriptService").PlayerDataService)
		end)
		local data = ok and PlayerDataService.Get(player) or nil
		-- `Telemetry.Funnel` is idempotent per step, so a client that fires this in a loop
		-- records exactly one step and then costs a table lookup a call.
		Telemetry.Funnel(player, stepKey, data)
	end)

	Players.PlayerAdded:Connect(function(player)
		sessionStart[player.UserId] = os.clock()

		-- 20.3: FRIEND IN SERVER. `IsFriendsWith` is a web call per pair, so this runs off the join
		-- thread and is fired ONCE with a count rather than once per friend -- what Phase 22 needs
		-- to know is whether co-play happens at all, and a count is a distribution while a stream of
		-- ones is not. Only the arriving player is measured: doing it from both sides would double
		-- every pair, and the joiner is the one whose session the answer belongs to.
		task.spawn(function()
			local friends = 0
			for _, other in ipairs(Players:GetPlayers()) do
				if other ~= player then
					local ok, isFriend = pcall(function()
						return player:IsFriendsWith(other.UserId)
					end)
					if ok and isFriend then friends += 1 end
				end
			end
			-- Fired even at zero, on purpose: "joined alone" is the baseline every later phase is
			-- trying to move, and an event that only exists when the answer is good measures nothing.
			if player.Parent then
				Telemetry.Custom(player, "FriendsInServer", friends)
			end
		end)
	end)

	-- Flush BEFORE the save runs, not after: `PlayerDataService`'s own PlayerRemoving clears the
	-- cache, and `flush` reads the balance out of that cache to stamp it on the aggregate. This
	-- connects first because `Telemetry.Init()` runs before `PlayerDataService.Init()` in
	-- ServerMain, and RBXScriptSignal handlers run in connection order.
	Players.PlayerRemoving:Connect(function(player)
		-- 20.6: opens the guard for THIS player, for the length of this handler only.
		leaving[player.UserId] = true

		local ok, PlayerDataService = pcall(function()
			return require(game:GetService("ServerScriptService").PlayerDataService)
		end)
		local data = ok and PlayerDataService.Get(player) or nil

		-- SEPARATELY WRAPPED, and that is not defensive habit. `flush` was a bare call directly
		-- above `SessionEnd`, so anything it threw took the session-end events with it and left no
		-- trace beyond one console line -- the same silent-hole shape 20.6 is about. They are two
		-- independent reports about one departure and neither may be able to cancel the other.
		local okFlush, flushErr = pcall(flush, player)
		if not okFlush then
			Telemetry.Stats.failed += 1
			Telemetry.Stats.lastError = "flush: " .. tostring(flushErr)
		end
		local okEnd, endErr = pcall(Telemetry.SessionEnd, player, data)
		if not okEnd then
			Telemetry.Stats.failed += 1
			Telemetry.Stats.lastError = "sessionEnd: " .. tostring(endErr)
		end

		sessionStart[player.UserId] = nil
		buckets[player.UserId] = nil
		leaving[player.UserId] = nil
	end)

	-- Sixty seconds is chosen against the SHORTEST thing being batched, not the longest: at one
	-- auto-collect tick a second it merges 60 payments into one row, which is the whole point,
	-- and it is short enough that a player who plays for two minutes still lands two rows rather
	-- than being flushed once at the door with everything in a single lump.
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in ipairs(Players:GetPlayers()) do
				flush(player)
			end
		end
	end)

	-- The last chance. A server shutting down for an update takes every bucket with it otherwise,
	-- and a game update is exactly when a session is most likely to be cut short.
	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			-- 20.6: a shutdown can unparent before this runs, and this is the LAST chance to
			-- send anything, so it opens the same door PlayerRemoving does.
			leaving[player.UserId] = true
			pcall(flush, player)
			leaving[player.UserId] = nil
		end
	end)
end

return Telemetry
