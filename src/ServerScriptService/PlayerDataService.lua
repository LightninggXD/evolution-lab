local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS.Remotes

local DataStore = DataStoreService:GetDataStore("EvolutionLab_v1")

local PlayerDataService = {}
PlayerDataService.Cache = {} -- [userId] = dataTable

-- ===== THE TWO WAYS A SAVE GETS DESTROYED, AND WHAT STOPS THEM =====
--
-- 1. A FAILED READ THAT LOOKS LIKE A NEW PLAYER. `GetAsync` was pcall'd, the failure only warned,
--    and the very next line handed back `defaultData()` -- so a routine DataStore blip during a
--    traffic spike logged the player in at Stage 1 with 0 DNA, and sixty seconds later the
--    autosave wrote that blank table over everything they owned. It is silent, permanent, and it
--    happens to exactly the players you least want it to happen to. A read is now retried, and a
--    player whose data genuinely cannot be read is sent away rather than allowed to play a
--    session that will overwrite them.
--
-- 2. TWO SERVERS HOLDING THE SAME SAVE. Leaving one server and joining another takes less time
--    than the first server's leave-save, so the second server can read the state from before the
--    session that just ended -- and then both write. Each save stamps which server wrote it and
--    when; a load that finds a stamp from ANOTHER server less than SESSION_STALE old waits for
--    that server's leave-save to land instead of reading through it.
--
--    Deliberately a soft lock: after SESSION_RETRIES it loads anyway. A hard lock turns a crashed
--    server into a player who cannot get into their own save at all, which is a worse failure
--    than the one it prevents.
local LOAD_ATTEMPTS = 5
local SESSION_STALE = 90      -- seconds before another server's claim is treated as abandoned
local SESSION_RETRIES = 5
local SESSION_WAIT = 2        -- seconds between re-reads while another server still holds it

-- This server. In Studio JobId is empty, which would make every Studio session look like the same
-- server -- fine, because there is only ever one of them.
local JOB_ID = game.JobId ~= "" and game.JobId or "studio"

-- [userId] = true for a player whose data could not be read. Nothing about them is ever written.
local loadFailed = {}

local function defaultData()
	return {
		DNA = 0,
		XP = 0, -- the level bar: filled by fighting, SPENT on every evolve, then filled again
		StageIndex = 1,
		Upgrades = {
			Speed = 0,
			Income = 0,
			Luck = 0,
			Mutation = 0,
			AutoCollect = 0,
		},
		Mutations = {}, -- list of mutation names owned
		Pets = {}, -- list of { id, key, tier } owned pet instances
		EquippedPetIds = {}, -- list of pet ids currently equipped (max GameConfig.MaxEquippedPets)
		Rebirths = 0,
		EvolutionShards = 0,
		LastRewardClaim = 0,
		RewardStreak = 0,
		-- Both string-keyed. `Potions` is potion id -> how many bottles held ('dna_s' -> 3);
		-- `PotionBoosts` is potion KIND -> { untilTs, mult | luckAdd } for the one bottle of that
		-- kind currently running. See the POTIONS block in GameConfig.
		Potions = {},
		PotionBoosts = {},
		Diamonds = 0,
		-- Counted Boss Revive charges. A COUNT rather than a flag on purpose: a receipt can arrive
		-- late, on another server or after a rejoin, and a charge that simply waits in the save is
		-- what makes that harmless. Spent by BossService.TryConsumeRevive, and only when a restore
		-- actually happens. Unlike data.Passes this IS trusted out of the save -- it is something the
		-- player owns, not a cached answer from a web call.
		BossRevives = 0,
		-- Rainbow Catalyst charges, counted for the same reason BossRevives is: the receipt that pays
		-- for one can arrive on another server or after a rejoin, and a token that simply waits in the
		-- save makes that harmless. Spent by PetService.HandleTierUp.
		TierUpTokens = 0,
		DiamondUpgrades = {
			MegaIncome = 0,
			MegaLuck = 0,
			PetSlot = 0,
		},
		UnlockedZones = { "Forest" },
		CurrentZone = "Forest",
		DefeatedBosses = {}, -- list of zone keys whose boss this player has personally defeated
		-- list of stage indices whose Stage Mastery has been bought. Survives Rebirth on purpose --
		-- RebirthService clears stages and bosses but deliberately leaves this alone.
		MasteredStages = {},
		-- The character Journal. `Characters` is a SET (key -> true) of the two hundred characters
		-- unlocked so far, one handed over on every evolve.
		--
		-- `WornCharacter` is the single key on the body right now. It used to be `EquippedCharacters`,
		-- a stage index -> key map, because a character could only be worn at its own stage; any
		-- character can be worn anywhere now, so there is one of them and it needs no stage in the
		-- key. The old field is still read once, as a fallback, when migrating a save that has it.
		Characters = {},
		WornCharacter = nil,
		EquippedCharacters = {},
		-- The Season Pass and its quest board. Both are shaped and RESET by SeasonPassService rather
		-- than here: which season and which day a save belongs to is decided by the clock at read
		-- time, so an empty table is the correct starting value and the service fills it in on first
		-- touch. Claim sets inside are keyed by tostring(level) -- see the note in that file.
		Season = {},
		Quests = {},
		-- Which playtime gifts have been taken, and the day they belong to. In the save rather than
		-- in memory because a table cleared on leave hands the whole ladder back on every rejoin --
		-- see PlaytimeGiftService. Shaped and reset by that service, so {} is the right start.
		PlaytimeClaims = {},
		-- Game pass ownership, as a set of pass keys. RUNTIME ONLY: PassService writes it from the
		-- Roblox ownership API on join, and Load below clears it unconditionally, so whatever ends up
		-- in the DataStore is never read back. Declared here only so nothing ever indexes a nil.
		Passes = {},
	}
end

function PlayerDataService.Get(player)
	return PlayerDataService.Cache[player.UserId]
end

-- One read, retried. Returns the stored table, `nil` for a player who has genuinely never played,
-- and `false` for a read that could not be completed -- which is the distinction the old code did
-- not make and the reason it destroyed saves.
local function fetch(player)
	local key = "Player_" .. player.UserId
	local lastErr
	for attempt = 1, LOAD_ATTEMPTS do
		local ok, result = pcall(function()
			return DataStore:GetAsync(key)
		end)
		if ok then
			return result
		end
		lastErr = result
		-- backing off rather than hammering: a DataStore that is refusing calls is usually
		-- throttling, and five immediate retries are five more throttled calls
		task.wait(attempt * 0.6)
	end
	warn(("[PlayerDataService] read failed %d times for %s: %s"):format(
		LOAD_ATTEMPTS, player.Name, tostring(lastErr)))
	return false
end

function PlayerDataService.Load(player)
	local data = fetch(player)

	-- Someone else's server still has it. Wait for their leave-save rather than reading through it.
	local tries = 0
	while type(data) == "table" and data.__sessionJobId and data.__sessionJobId ~= JOB_ID
		and (os.time() - (data.__sessionAt or 0)) < SESSION_STALE and tries < SESSION_RETRIES do
		tries += 1
		task.wait(SESSION_WAIT)
		if not player.Parent then return nil end
		data = fetch(player)
	end

	if data == false then
		-- Not recoverable. Playing on would mean playing a blank save that overwrites the real one
		-- at the next autosave, so the session does not start. Marked before the kick because the
		-- kick is not instantaneous and the autosave loop must not catch them in between.
		loadFailed[player.UserId] = true
		player:Kick("We couldn't load your save just now. Nothing has been lost -- please rejoin in a moment.")
		return nil
	end

	if not data then
		data = defaultData()
	else
		local def = defaultData()
		for k, v in pairs(def) do
			if data[k] == nil then
				data[k] = v
			end
		end
		for k, v in pairs(def.Upgrades) do
			if data.Upgrades[k] == nil then
				data.Upgrades[k] = v
			end
		end
		-- Sub-tables added after launch need the same nil guard the top level gets, or the first
		-- write to one on an existing save indexes nil.
		-- POTIONS WENT FROM A COUNTER TO AN INVENTORY. Every save written before that holds a plain
		-- number here, and every read of it after this point indexes a table -- so the whole balance
		-- is handed over as bottles of the default kind rather than being silently dropped. The
		-- number form can never come back, so this is a one-way migration and needs no version flag.
		if type(data.Potions) ~= "table" then
			local owned = tonumber(data.Potions) or 0
			data.Potions = {}
			if owned > 0 then
				data.Potions[GameConfig.DefaultPotionId] = owned
			end
		end
		if type(data.PotionBoosts) ~= "table" then data.PotionBoosts = {} end
		-- an old single-timer boost still running is carried over as a DNA boost, which is what it was
		if (tonumber(data.PotionBoostUntil) or 0) > os.time() and not data.PotionBoosts.dna then
			data.PotionBoosts.dna = { untilTs = data.PotionBoostUntil, mult = 2 }
		end
		data.PotionBoostUntil = nil
		if not data.Characters then data.Characters = {} end
		if not data.EquippedCharacters then data.EquippedCharacters = {} end
		-- ONE WORN CHARACTER instead of one per stage. A save from before the change wears whatever
		-- it had chosen for the stage it was standing at, which is exactly what was on its body when
		-- it last logged out -- so nobody's appearance changes under them on the update.
		if data.WornCharacter == nil then
			data.WornCharacter = data.EquippedCharacters[tostring(data.StageIndex or 1)]
		end
	-- ===== HEALING A SAVE WRITTEN UNDER THE OLD RULE =====
	--
	-- A STAGE YOU HAVE LEFT IS A STAGE YOU COLLECTED. That is the rule now -- every character is an
	-- evolve (GameConfig.GetEvolveStep), and the only way past a stage is through all five of it --
	-- so any hole BELOW the stage a save is standing at is a hole the new rule says cannot exist.
	--
	-- It is also a hole nothing could ever fill. GetEvolveStep only ever looks at the stage the
	-- player is on, so a save that reached Worm holding Cell 2/5 (which is what the old 1-in-5 kill
	-- drop routinely produced) would carry those eight missing skins forever and its Journal could
	-- never read 100/100. Backfilling only each stage's FIRST character -- what this used to do --
	-- leaves exactly the same dead ends, four per stage instead of five.
	--
	-- Everything strictly below the current stage is granted; the current stage is left alone,
	-- because that one is still being walked and its remaining steps are what the player is paying
	-- for right now. Runs on load, so it repairs itself once, silently.
	data.Characters = data.Characters or {}
	for stageIndex = 1, math.min((data.StageIndex or 1) - 1, #GameConfig.Stages) do
		for _, entry in ipairs(GameConfig.GetCharactersForStage(stageIndex)) do
			data.Characters[entry.key] = true
		end
	end
	-- and the stage they ARE on always owes them its first: it was handed over by the evolve that
	-- brought them here, and a save from before that rule can be standing at a stage it owns
	-- nothing of.
	do
		local base = GameConfig.GetBaseCharacterForStage(math.clamp(data.StageIndex or 1, 1, #GameConfig.Stages))
		if base then data.Characters[base.key] = true end
	end
	-- and a save that has never worn anything gets dressed in the best thing it owns, rather than
	-- spawning as the undressed stage default next to a full Journal
	if data.WornCharacter == nil then
		local best
		for key in pairs(data.Characters) do
			local entry = GameConfig.GetCharacter(key)
			if entry and (not best or GameConfig.GetCharacterRank(entry) > GameConfig.GetCharacterRank(best)) then
				best = entry
			end
		end
		data.WornCharacter = best and best.key or nil
	end
		-- no field-by-field migration for these two: SeasonPassService rebuilds either one whenever
		-- its stamp does not match the current season/period, which covers a save that predates them
		if type(data.Season) ~= "table" then data.Season = {} end
		if type(data.Quests) ~= "table" then data.Quests = {} end
		if not data.DiamondUpgrades then data.DiamondUpgrades = {} end
		for k, v in pairs(def.DiamondUpgrades) do
			if data.DiamondUpgrades[k] == nil then
				data.DiamondUpgrades[k] = v
			end
		end
	end
	-- ===== PASS OWNERSHIP IS NEVER READ OUT OF THE SAVE =====
	--
	-- `data.Passes` is a runtime cache of what Roblox's ownership API says this player owns, and
	-- PassService rebuilds it on every join. It is cleared HERE, unconditionally and for both a fresh
	-- and a returning save, because the alternative is a permanently free pass: if a `true` survived
	-- in the save and the later UserOwnsGamePassAsync check failed -- or the pass had been refunded
	-- or revoked -- that stale value is the answer every stat function in the game would get, and
	-- nothing anywhere would ever take it back.
	--
	-- Cleared on load rather than stripped before the write on purpose. SetAsync yields, and blanking
	-- the field across that yield would leave a paying player's multipliers switched off for the
	-- duration of every autosave.
	data.Passes = {}

	-- Reads yield, and a player can leave during one. Caching them then leaves an entry for
	-- somebody who is gone -- which never gets cleared (PlayerRemoving already ran) and is handed
	-- to them stale if they rejoin this same server.
	if not player.Parent then return nil end

	PlayerDataService.Cache[player.UserId] = data
	return data
end

-- `release` is the leave-save: it drops this server's claim so the player's next server does not
-- have to wait out SESSION_STALE before it can read them.
function PlayerDataService.Save(player, release)
	local data = PlayerDataService.Cache[player.UserId]
	if not data then return end
	-- the whole point of the flag: a session that never loaded must never write
	if loadFailed[player.UserId] then return end

	data.__sessionJobId = release and nil or JOB_ID
	data.__sessionAt = os.time()

	local ok, err = pcall(function()
		DataStore:SetAsync("Player_" .. player.UserId, data)
	end)
	if not ok then
		warn("DataStore save failed for", player.Name, err)
	end
	return ok
end

function PlayerDataService.PushToClient(player)
	local data = PlayerDataService.Cache[player.UserId]
	if not data then return end
	Remotes.DataUpdate:FireClient(player, data)
end

function PlayerDataService.UpdateLeaderstats(player)
	local data = PlayerDataService.Cache[player.UserId]
	if not data then return end
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		leaderstats.DNA.Value = math.floor(data.DNA)
		leaderstats.Stage.Value = GameConfig.Stages[data.StageIndex].name
	end
end

function PlayerDataService.Init()
	Players.PlayerAdded:Connect(function(player)
		local data = PlayerDataService.Load(player)
		-- nil means the player was kicked or left during the read. Everything below would index it.
		if not data then return end

		local leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player

		local dnaStat = Instance.new("NumberValue")
		dnaStat.Name = "DNA"
		dnaStat.Value = data.DNA
		dnaStat.Parent = leaderstats

		local stageStat = Instance.new("StringValue")
		stageStat.Name = "Stage"
		stageStat.Value = GameConfig.Stages[data.StageIndex].name
		stageStat.Parent = leaderstats

		task.wait(0.3)
		PlayerDataService.PushToClient(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		PlayerDataService.Save(player, true)
		PlayerDataService.Cache[player.UserId] = nil
		loadFailed[player.UserId] = nil
	end)

	-- IN PARALLEL, AND WAITED ON. Roblox allows roughly 30 seconds here; thirty blocking SetAsyncs
	-- one after another under throttling do not fit in that, and the players at the end of the
	-- loop simply lose their session every time the game is updated.
	game:BindToClose(function()
		local players = Players:GetPlayers()
		local remaining = #players
		if remaining == 0 then return end
		for _, player in ipairs(players) do
			task.spawn(function()
				PlayerDataService.Save(player, true)
				remaining -= 1
			end)
		end
		local deadline = os.clock() + 25
		while remaining > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in ipairs(Players:GetPlayers()) do
				PlayerDataService.Save(player)
			end
		end
	end)
end

return PlayerDataService
