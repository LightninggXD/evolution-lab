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
-- Every entry point below used to test `player.Parent`, and that test is RIGHT for the calls it was
-- written for: a reward that lands after the player has gone is a call at nobody. It was WRONG for
-- the two paths this module runs at the door, and it silently deleted both of them.
--
-- `Players.PlayerRemoving` hands over a player who has ALREADY been unparented, so `player.Parent`
-- is nil for the whole of that handler -- which is where `flush()` drains the Accrue buckets and
-- where `SessionEnd` sends its four events. Every one of those calls returned at the guard. Nothing
-- errored, nothing landed in `Stats.failed`, and `sent` did not move: the instrumentation reported
-- perfect health while sending nothing at all. Measured 2026-08-20 (see ROADMAP 20.6): at the stop,
-- `sent` was identical to its value before it and `custom` held no `Session*` key.
--
-- So the departure is made explicit rather than the guard being deleted. A player is reachable if
-- they are still parented OR if we are inside their own PlayerRemoving, and nowhere else -- which
-- leaves the protection intact for the async callers that rely on it (the friend count below tests
-- `player.Parent` itself, on purpose, and keeps doing so).
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
	if okCfg and GameConfig and GameConfig.GetEvolveStep then
		local okStep, step = pcall(GameConfig.GetEvolveStep, data)
		if okStep and step and not step.isMax and (step.xpCost or 0) > 0 then
			local pct = math.clamp(math.floor(((data.XP or 0) / step.xpCost) * 100), 0, 100)
			Telemetry.Custom(player, "SessionEndEvolveBarPct", pct)
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
