--[[
	StatsService -- how many players own each character, so the Journal can say how rare one is.

	"0.3% of players own this" is the line that turns a grid of skins into a collection. It is also
	the only number in the game that cannot be computed from one player's save, so it needs a global
	counter -- and global counters are where a Roblox game usually starts writing to a DataStore once
	per event and quietly exhausts its request budget.

	=========================================================================================
	WHAT IS COUNTED, AND WHY IT IS NOT COUNTED AT THE GRANT
	=========================================================================================
	The obvious design is to bump a counter wherever a character is handed over. There are several
	such places -- the evolve step, the roll, the Load backfill that heals old saves, the VIP skin
	sync -- and the next one added would silently not count. Worse, `RebirthService` clears
	`data.Characters` wholesale and the collection is then re-granted, so anything diffing "what do
	they own now" against "what did they own last time" would count the same player again on every
	rebirth.

	So ownership is reconciled instead. `data.CountedCharacters` is a permanent, never-cleared record
	of what this save has ALREADY been counted for. A sweep compares it against `data.Characters`,
	reports the difference, and marks it. Every grant path is covered without knowing any of them
	exist, and a rebirth cannot double-count because the record survives it.

	=========================================================================================
	WRITES ARE BATCHED, AND THE BATCH SURVIVES A FAILED FLUSH
	=========================================================================================
	Deltas accumulate in memory and go out as ONE `UpdateAsync` on a single key. `UpdateAsync` is the
	read-modify-write that is safe against other servers doing the same thing at the same time --
	`SetAsync` here would mean the last server to write wins and everyone else's counts vanish.

	The batch is taken and `pending` cleared BEFORE the call, so increments arriving during the write
	are not lost; if the write then fails, the batch is added back. Dropping it on failure is the
	easy version and it silently loses counts every time the DataStore hiccups.

	=========================================================================================
	THE AGGREGATE REACHES CLIENTS WITHOUT A REMOTE
	=========================================================================================
	It is published as JSON into a `StringValue` in ReplicatedStorage, which replicates by itself --
	the same trick the VIP badge uses with an attribute. No remote, no request handler, and a client
	that joins late gets the current value for free.

	A MINIMUM SAMPLE IS ENFORCED. With four players on the board every character anyone owns reads
	"100% of players own this", which is true and worthless. Below `MIN_SAMPLE` the Journal is told
	nothing and shows nothing.
--]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent.PlayerDataService)

local StatsService = {}

local STORE_KEY = "collection_v1"
local SWEEP_INTERVAL = 45    -- how often owned-vs-counted is reconciled per player
local FLUSH_INTERVAL = 120   -- how often the accumulated deltas go to the DataStore
local MIN_SAMPLE = 25        -- below this the percentages are noise and are not published

local store = DataStoreService:GetDataStore("EvolutionLab_Stats_v1")

-- deltas waiting to go out
local pending = { players = 0, chars = {} }
-- last known aggregate, as read back from the store
local aggregate = { players = 0, chars = {} }

local valueObject

local function publish()
	if not valueObject or not valueObject.Parent then return end
	-- Below the sample floor the payload is deliberately empty rather than small-but-wrong: a
	-- client that receives nothing draws nothing, which is the honest state on a young game.
	local payload = (aggregate.players >= MIN_SAMPLE) and aggregate or { players = 0, chars = {} }
	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(payload)
	end)
	if ok then
		valueObject.Value = encoded
	end
end

-- ============================================================================
-- RECONCILE
-- ============================================================================
-- Compares what a save owns against what it has already been counted for, and returns how many new
-- characters were reported. Cheap: two table walks over at most 201 keys, once every 45 seconds.
local function sweepPlayer(data)
	if type(data) ~= "table" then return 0 end
	data.CountedCharacters = data.CountedCharacters or {}

	local added = 0
	for key, owned in pairs(data.Characters or {}) do
		if owned == true and not data.CountedCharacters[key] then
			data.CountedCharacters[key] = true
			pending.chars[key] = (pending.chars[key] or 0) + 1
			added += 1
		end
	end

	-- one per save, ever. This is the denominator, so it has to be "players who have a collection",
	-- not "sessions" -- counting joins would make every percentage fall over time on its own.
	if not data.CountedPlayer then
		data.CountedPlayer = true
		pending.players += 1
	end
	return added
end

function StatsService.SweepAll()
	local total = 0
	for _, player in ipairs(Players:GetPlayers()) do
		local data = PlayerDataService.Get(player)
		if data then
			total += sweepPlayer(data)
		end
	end
	return total
end

-- ============================================================================
-- FLUSH
-- ============================================================================
local function hasPending()
	if pending.players ~= 0 then return true end
	for _ in pairs(pending.chars) do return true end
	return false
end

-- Returns true if the aggregate was refreshed. Public so a test does not have to wait out the timer.
function StatsService.Flush()
	if not hasPending() then
		-- nothing to add, but still worth reading so a server with no new unlocks does not sit on a
		-- stale aggregate forever
		local ok, stored = pcall(function()
			return store:GetAsync(STORE_KEY)
		end)
		if ok and type(stored) == "table" then
			aggregate = { players = tonumber(stored.players) or 0, chars = stored.chars or {} }
			publish()
			return true
		end
		return false
	end

	-- taken and cleared BEFORE the write, so anything arriving mid-flight lands in the next batch
	local batch = pending
	pending = { players = 0, chars = {} }

	local ok, result = pcall(function()
		return store:UpdateAsync(STORE_KEY, function(old)
			old = (type(old) == "table") and old or { players = 0, chars = {} }
			old.players = (tonumber(old.players) or 0) + batch.players
			old.chars = old.chars or {}
			for key, delta in pairs(batch.chars) do
				old.chars[key] = (tonumber(old.chars[key]) or 0) + delta
			end
			return old
		end)
	end)

	if not ok then
		-- put it back. Dropping the batch here loses real counts every time the DataStore hiccups,
		-- and nothing would ever report that it had happened.
		pending.players += batch.players
		for key, delta in pairs(batch.chars) do
			pending.chars[key] = (pending.chars[key] or 0) + delta
		end
		return false
	end

	if type(result) == "table" then
		aggregate = { players = tonumber(result.players) or 0, chars = result.chars or {} }
		publish()
	end
	return true
end

-- ============================================================================
-- READING (server side; the client reads the StringValue instead)
-- ============================================================================
-- Returns a percentage 0..100, or nil when the sample is too small to mean anything.
function StatsService.GetOwnershipPct(characterKey)
	if aggregate.players < MIN_SAMPLE then return nil end
	local owners = tonumber(aggregate.chars[characterKey]) or 0
	return math.clamp(owners / aggregate.players * 100, 0, 100)
end

function StatsService.GetAggregate()
	return { players = aggregate.players, chars = aggregate.chars }
end

function StatsService.Init()
	valueObject = RS:FindFirstChild("GlobalStats")
	if not valueObject then
		valueObject = Instance.new("StringValue")
		valueObject.Name = "GlobalStats"
		valueObject.Value = ""
		valueObject.Parent = RS
	end

	-- a leaving player's last unlocks are swept before their save closes
	Players.PlayerRemoving:Connect(function(player)
		local data = PlayerDataService.Get(player)
		if data then
			sweepPlayer(data)
		end
	end)

	task.spawn(function()
		-- read once at boot so a fresh server is not showing nothing for its first two minutes
		StatsService.Flush()
		while true do
			task.wait(SWEEP_INTERVAL)
			StatsService.SweepAll()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(FLUSH_INTERVAL)
			StatsService.Flush()
		end
	end)
end

return StatsService
