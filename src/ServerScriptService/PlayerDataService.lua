local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")

local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS.Remotes
local Telemetry = require(script.Parent.Telemetry)

local DataStore = DataStoreService:GetDataStore("EvolutionLab_v1")

local PlayerDataService = {}
PlayerDataService.Cache = {} -- [userId] = dataTable

-- [userId] = seconds of absence this session is owed a payout for, already capped by
-- GameConfig.GetOfflineSeconds. IN MEMORY, NEVER IN THE SAVE -- see the note where it is written.
PlayerDataService.OfflineSeconds = {}

-- [userId] = DNA refunded to this player this session by the Phase 12 Mutation Chance conversion,
-- for SplicerService to tell them about once. IN MEMORY FOR THE SAME REASON OfflineSeconds is:
-- written onto `data` it would be persisted by the next autosave and re-announced on every join
-- for the rest of that save's life. (Measured, not predicted -- the first version of the migration
-- did put it on `data`, and the second load of the probe save read the field straight back.)
PlayerDataService.SplicerRefunds = {}

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
			AutoCollect = 0,
		},
		-- THE DNA SPLICER (Phase 12). `SplicerMutation` is the ONE mutation being worn (absent
		-- until the first roll -- DataStore drops an explicit nil anyway, so every reader
		-- nil-guards); `SplicerRolls` is the lifetime roll count that both prices the next roll
		-- and drives the pity counter, and it is deliberately NOT on the rebirth reset list --
		-- resetting it would make a rebirth a way to buy cheap rolls again. `SplicerFound` is
		-- the collection log, name -> how many of that mutation have been rolled.
		SplicerRolls = 0,
		SplicerFound = {},
		Pets = {}, -- list of { id, key, tier } owned pet instances
		EquippedPetIds = {}, -- list of pet ids currently equipped (max GameConfig.MaxEquippedPets)
		Rebirths = 0,
		-- Lifetime creatures and bosses killed, for the global leaderboard (5.3). NOT reset by a
		-- rebirth: a lifetime board that a rebirth zeroed would rank players by how recently they
		-- reset rather than by how much they have played. Starts at 0 for everyone, including saves
		-- that predate it -- there is nothing in an old save to reconstruct it from.
		Kills = 0,
		EvolutionShards = 0,
		LastRewardClaim = 0,
		RewardStreak = 0,
		-- os.time() of the last free daily spin (5.6). Compared by UTC day number, the same boundary
		-- LastRewardClaim uses, so the login reward and the free spin roll over together.
		LastFreeSpin = 0,
		-- ===== RELICS (2026-08-17) =====
		-- `Relics` is relic KEY -> { copies, level }, string-keyed like `Potions` and for the same
		-- reason: a table whose only keys are integers is a sparse array and Roblox silently drops
		-- those crossing a RemoteEvent. `EquippedRelicKeys` is the ordered list of what is worn, the
		-- `EquippedPetIds` shape exactly -- a list of ids, never a slot-indexed array, so a slot lost
		-- to a rebirth reset cannot leave a hole in the middle of it.
		--
		-- `RelicForgeUnlocked` IS OFF THE REBIRTH RESET LIST ON PURPOSE, like `TutorialDone`. It is
		-- stamped the first time the player reaches stage 10 and never cleared; a live
		-- `StageIndex >= 10` test would shut the forge the instant they rebirthed, taking a screen
		-- full of owned things away at the exact moment they were promised a reward.
		Relics = {},
		EquippedRelicKeys = {},
		RelicForgeUnlocked = false,
		LastRelicChest = 0,
		RelicChestsOpened = 0,
		-- UNOPENED chests, banked by `RelicService.GiveChest` -- today only the Lucky Wheel's relic
		-- segment, which is why this field existed for a while without being declared here: the
		-- service incremented it, `Load`'s generic backfill never saw a default to hand to anyone,
		-- and the Forge had no button that spent one. A wheel segment a player pays Robux for was
		-- landing in a number nothing could read.
		RelicChests = 0,
		-- Group and Community status and claim timestamps (5.5)
		InGroup = false,
		ClaimedGroupChest = 0,
		ClaimedLikeReward = false,
		ClaimedFavoriteReward = false,
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
		-- Codes already redeemed, as a SET of normalised code strings (GameConfig.NormaliseCode). A set
		-- rather than a list because the only question ever asked of it is "has this one been used",
		-- and a list would be a linear scan over something that only ever grows.
		RedeemedCodes = {},
		-- os.time() of the last save. Written by Save on every autosave and on the leave-save, and read
		-- exactly once -- by Load, before it is overwritten -- to work out how long the player was away.
		-- See OfflineService.
		LastSeen = 0,
		-- What StatsService has ALREADY counted this save for (5.7), and whether it has counted the
		-- save itself toward the denominator. Permanent and never cleared -- that is the whole point:
		-- a rebirth wipes `Characters` and the collection is re-granted, and without a separate record
		-- the same player would be counted again on every rebirth. Written by StatsService, read by
		-- nothing else.
		CountedCharacters = {},
		CountedPlayer = false,
		-- Event-exclusive skins this save has EARNED (7.1). Permanent and never cleared, for the same
		-- reason CountedCharacters above is: a rebirth wipes `Characters`, and an event skin has no
		-- live source to be re-granted from once its window has shut. `Characters` is the working
		-- copy; this is the record. See GameConfig.SyncEventCharacters.
		--
		-- An empty table is the right default for every save ever written -- "has earned none" is
		-- true of all of them -- so unlike TutorialDone (6.3) this one needs no repair beside it.
		EventCharacters = {},
		-- The event quest ladders (26.1) -- `EventQuests[eventKey] = { window, progress, claimed }`,
		-- one board per event, bucketed by the START TIMESTAMP of the occurrence it belongs to.
		--
		-- Shaped and RESET by GameConfig.GetEventBoard rather than here, for the same reason `Season`
		-- and `Quests` above are: which occurrence a save belongs to is decided by the clock at read
		-- time, so an empty table is the correct starting value and the first touch fills it in. A
		-- board whose stamp does not match the live window is thrown away and rebuilt, which is what
		-- makes each weekend of ColosseumClash its own board rather than a running total.
		--
		-- It is bounded by the number of events that carry a ladder (two today), NOT by how many
		-- occurrences the save has lived through -- the stamp is overwritten, never appended to.
		EventQuests = {},
		-- Per-player audio levels (4.6): a master fader plus one per SoundGroup, each 0..1, pushed
		-- onto the groups by SoundLibrary.Init on the client's first data payload. In the SAVE rather
		-- than in a client-side setting for the obvious reason -- a player who turned the music off did
		-- not ask for it back on their next join -- and it is the one field in here the client is
		-- allowed to set directly, because nothing about it is worth anything to cheat.
		AudioVolumes = { Master = 1, SFX = 1, UI = 1, Ambience = 1 },
		-- Has this save been walked through the first-join sequence (6.3)? Flipped to true by the
		-- FIRST EVOLVE, on the server, in ServerMain's OnEvolve hook -- never by the client, and never
		-- by the client reporting that it finished. A player who quits halfway through gets the guide
		-- again on their next join, which is the behaviour that costs nothing and helps somebody.
		--
		-- A REBIRTH MUST NEVER CLEAR THIS. It resets StageIndex to 1, so any tutorial gate written as
		-- "is this player at stage 1" would replay the whole sequence for a veteran on every rebirth --
		-- which is why this is a field of its own and not an inference. RebirthService resets a named
		-- list and this is deliberately not on it.
		TutorialDone = false,
		-- Has this save ever stood on the plaza's photo pad (17.3)? One diamond gift, once, ever --
		-- so `false` is the correct default for every save already written, and this needs none of
		-- the repair TutorialDone above does: nobody has taken a photo, because until 17.3 the pad
		-- had no code behind it at all. Not on RebirthService's reset list on purpose; a first photo
		-- is a first photo.
		PhotoTaken = false,
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
		-- ===== BORN INSTRUMENTED (Phase 20) =====
		-- An empty table means "follow this save through the onboarding funnel". It is set HERE and
		-- not in `defaultData` on purpose: the backfill loop in the other branch copies every default
		-- onto every existing save, which would hand a veteran an empty funnel and enter them at
		-- whatever step they happened to trip first. This is the one field where the fresh branch and
		-- the returning branch must disagree. See the funnel header in Telemetry.
		data.Funnel = {}
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
		-- The other half of the funnel stamp above. A save that already existed when Phase 20 shipped
		-- is marked `pre` and is never logged again -- it has no step 1 under it and never will, so
		-- entering it now would only bend the drop-off curve every later phase is measured against.
		-- A save that was born instrumented keeps the table it already has.
		data.Funnel = (type(data.Funnel) == "table") and data.Funnel or { pre = true }
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
		-- EVERY EXISTING SAVE HAS ALREADY DONE THE TUTORIAL, and the generic backfill above cannot
		-- know that: it copies the default `TutorialDone = false` onto every save written before the
		-- field existed, which would hand the first-join sequence to players with a thousand hours.
		-- Progress is the evidence -- past stage 1, or having rebirthed at all, means the player has
		-- evolved and needs no arrow pointing at the button they used to do it. Written as a repair
		-- rather than a one-time flag so it is idempotent: a fresh save is stage 1 with no rebirths
		-- and correctly stays false.
		if not data.TutorialDone and ((data.StageIndex or 1) > 1 or (data.Rebirths or 0) > 0) then
			data.TutorialDone = true
		end
		-- ===== THE SPLICER TAKES THE MUTATIONS OVER (Phase 12) =====
		--
		-- Mutations used to roll themselves every ten seconds and pile up in a list; they are
		-- bought at the DNA Splicer now and exactly one is worn. Two one-way conversions, and
		-- both are written so that running them twice changes nothing -- an autosave can land
		-- between a load and the next read, and a refund paid twice is free DNA forever.
		if type(data.SplicerFound) ~= "table" then data.SplicerFound = {} end
		data.SplicerRolls = tonumber(data.SplicerRolls) or 0
		-- (a) The "Mutation Chance" upgrade no longer exists -- there is no ambient roll left for
		-- it to speed up -- so every level ever bought is refunded at the exact geometric sum
		-- that was paid for it. 60 and 1.35 were that upgrade's own baseCost/costMult and are
		-- literals here because GameConfig.Upgrades.Mutation is gone. The credit and the zeroing
		-- are the SAME write, which is what makes a second pass a no-op.
		local mutationLevel = tonumber(data.Upgrades and data.Upgrades.Mutation) or 0
		-- The KEY goes whatever the level was. Refunding only a bought level was the first version
		-- and it left `Upgrades.Mutation = 0` sitting in every save that never bought one -- inert
		-- (nothing reads a key `GameConfig.Upgrades` no longer has) but permanent, and a field that
		-- outlives the feature it belonged to is what the next reader has to work out from scratch.
		if data.Upgrades then data.Upgrades.Mutation = nil end
		if mutationLevel > 0 then
			local refund = math.floor(60 * ((1.35 ^ mutationLevel) - 1) / 0.35)
			data.DNA = (data.DNA or 0) + refund
			-- The Phase 12 Mutation Chance refund. Logged like any other faucet: it is real DNA
			-- entering the economy, it happens once per affected save, and leaving it out would
			-- make the DNA supply chart disagree with the saves by exactly this amount.
			Telemetry.Economy(player, "Source", Telemetry.Currency.DNA, refund, data.DNA,
				Telemetry.Tx.Onboarding, "mutationRefund")
			-- NOT on `data` -- see SplicerRefunds at the top of this file. SplicerService reads it
			-- to tell the player once, because a silent refund reads as a save that lost an upgrade.
			PlayerDataService.SplicerRefunds[player.UserId] = refund
			warn(("[PlayerDataService] %d (%s): Mutation Chance L%d refunded %d DNA")
				:format(player.UserId, player.Name, mutationLevel, refund))
		end
		-- (b) The old rolled list becomes the collection log plus the one worn mutation -- the
		-- BEST one, so nobody's income falls further than the capped tail this replaces. Guarded
		-- on SplicerMutation being unset, or a second pass would count every name again.
		if data.SplicerMutation == nil and type(data.Mutations) == "table" and #data.Mutations > 0 then
			local bestIdx = 0
			for _, owned in ipairs(data.Mutations) do
				for i, m in ipairs(GameConfig.Mutations) do
					if m.name == owned then
						data.SplicerFound[owned] = (data.SplicerFound[owned] or 0) + 1
						if i > bestIdx then bestIdx = i end
						break
					end
				end
			end
			if bestIdx > 0 then data.SplicerMutation = GameConfig.Mutations[bestIdx].name end
		end
		-- Cleared rather than kept: the conversion above is complete and the list form can never
		-- come back, the same reasoning the Potions counter migration is written on. The legacy
		-- branch in GetMutationIncomeMult covers only the window where a save is already in a
		-- running server's memory when this code arrives.
		data.Mutations = nil
		-- ===== THE ONE WORN IS BY DEFINITION ONE FOUND (15.27) =====
		-- Both writers above set the pair together, so this repairs nothing that exists today -- it
		-- is here because the Auras panel now DRAWS the difference. A save whose `SplicerMutation`
		-- is not in `SplicerFound` would show the aura burning on the player's own body as an entry
		-- they have never found, with its Wear button refused by `HandleEquipMutation`'s ownership
		-- check. Idempotent, and it can only ever add the name the save is already wearing.
		if type(data.SplicerMutation) == "string"
			and (data.SplicerFound[data.SplicerMutation] or 0) <= 0 then
			data.SplicerFound[data.SplicerMutation] = 1
		end
	-- ===== TRIMMING A COLLECTION TO THE NEW 30-PET CEILING =====
	--
	-- The cap was 600 and a live save reached 207. The owner's decision (2026-08-10) is to keep the
	-- 30 strongest and release the rest, so the inventory is never in the impossible 207/30 state
	-- that a grandfathering rule would leave on screen for the rest of that save's life.
	--
	-- FOUR THINGS THIS HAS TO GET RIGHT, and each one is a way to destroy a save quietly:
	--
	-- * IT RUNS ONCE. `PetsTrimmedAt` is the flag, and it stores the ceiling it trimmed to rather
	--   than `true` -- so if the cap is ever raised, an old stamp is visibly from a different rule
	--   instead of silently blocking a re-trim that a lower cap would need.
	-- * EQUIPPED PETS SURVIVE UNCONDITIONALLY. Ranking already puts them near the top, but "near"
	--   is not a guarantee, and a player logging in to find the team they built dismantled would
	--   have no way to tell a trim from a bug. They are seeded first and the rest fills behind them.
	-- * IT IS RANKED WITH `data`, so the zone axis applies (10.1) -- otherwise the trim would keep
	--   whatever was strongest in the zone it hatched in rather than what is strongest now.
	-- * IT NEVER RUNS ON A SAVE THAT IS ALREADY UNDER THE CAP, so the overwhelming majority of
	--   players pay nothing for this and no flag is written into their save at all.
	--
	-- `PetsReleased` is left on the table for the session so PetService can tell the player what
	-- happened. It is a count, not the pets: keeping the discarded list would defeat the point of a
	-- ceiling that exists to bound the save.
	if type(data.Pets) == "table" and #data.Pets > GameConfig.MaxOwnedPets
		and data.PetsTrimmedAt ~= GameConfig.MaxOwnedPets then
		local before = #data.Pets
		local equippedLookup = {}
		for _, id in ipairs(data.EquippedPetIds or {}) do equippedLookup[id] = true end

		local kept, keptLookup = {}, {}
		for _, p in ipairs(data.Pets) do
			if equippedLookup[p.id] and #kept < GameConfig.MaxOwnedPets then
				table.insert(kept, p)
				keptLookup[p.id] = true
			end
		end
		for _, p in ipairs(GameConfig.SortedPetsByPower(data.Pets, data)) do
			if #kept >= GameConfig.MaxOwnedPets then break end
			if not keptLookup[p.id] then
				table.insert(kept, p)
				keptLookup[p.id] = true
			end
		end
		data.Pets = kept

		-- an equipped id whose pet did not survive would leave a phantom paying bonuses forever
		local liveEquipped = {}
		for _, id in ipairs(data.EquippedPetIds or {}) do
			if keptLookup[id] then table.insert(liveEquipped, id) end
		end
		data.EquippedPetIds = liveEquipped

		data.PetsTrimmedAt = GameConfig.MaxOwnedPets
		data.PetsReleased = before - #kept
		warn(("[PlayerDataService] trimmed %d (%s): %d pets -> %d (released %d)")
			:format(player.UserId, player.Name, before, #kept, data.PetsReleased))
	end
		-- no field-by-field migration for these two: SeasonPassService rebuilds either one whenever
		-- its stamp does not match the current season/period, which covers a save that predates them
		if type(data.Season) ~= "table" then data.Season = {} end
		if type(data.Quests) ~= "table" then data.Quests = {} end
		-- ...and the same for the event ladders, for the same reason: GameConfig.GetEventBoard
		-- rebuilds any board whose window stamp does not match the live occurrence, so a save from
		-- before 26.1 needs nothing but a table to write the first one into
		if type(data.EventQuests) ~= "table" then data.EventQuests = {} end
		-- the top-level nil-fill above already hands a save from before 4.6 the whole default table;
		-- this is the guard for one written as something else, and it restores every fader at once
		-- rather than leaving a half-populated table for the client to index
		if type(data.AudioVolumes) ~= "table" then data.AudioVolumes = def.AudioVolumes end
		if type(data.RedeemedCodes) ~= "table" then data.RedeemedCodes = {} end
		-- THE TOP-LEVEL NIL-FILL DOES NOT DESCEND, which is the warning this block's own header
		-- carries -- so both relic tables need their own guard or the first write to one on a save
		-- written as something else indexes nil. Empty is the correct answer for an old save here,
		-- unlike `TutorialDone` below: a player who has never opened a chest owns no relics.
		if type(data.Relics) ~= "table" then data.Relics = {} end
		if type(data.EquippedRelicKeys) ~= "table" then data.EquippedRelicKeys = {} end
		-- ...and a save that reached stage 10 before relics existed gets the forge on this load
		-- rather than being asked to climb again for a door that was not there the first time.
		if (data.StageIndex or 1) >= (GameConfig.RelicUnlockStage or 10) then
			data.RelicForgeUnlocked = true
		end
		if not data.DiamondUpgrades then data.DiamondUpgrades = {} end
		for k, v in pairs(def.DiamondUpgrades) do
			if data.DiamondUpgrades[k] == nil then
				data.DiamondUpgrades[k] = v
			end
		end
	end

	-- ===== EVERY SAVE OWNS THE FIRST CHARACTER OF THE STAGE IT IS STANDING ON =====
	--
	-- THIS BLOCK LIVES OUTSIDE THE if/else ON PURPOSE, and that is the whole of the "Cell 1 is not
	-- unlocked" report. It used to sit *inside* the `else` above -- de-indented to one tab, so it
	-- read as top-level while the parser had it in the returning-save branch, which does not close
	-- until the `end` a hundred lines further down. A brand new profile therefore took
	-- `data = defaultData()` and skipped all of it: it spawned owning nothing, wearing nothing, and
	-- the HUD read "Cell (0/5)" with "Speck (1/5) -- needs 19 more XP" as the next thing to earn,
	-- for a character the player is supposed to already be.
	--
	-- Everything here is idempotent and cheap on a fresh save (the backfill loop runs zero times at
	-- stage 1, and the dress picks the one key the grant just wrote), so running it unconditionally
	-- costs nothing and removes the entire class of bug.

	-- A STAGE YOU HAVE LEFT IS A STAGE YOU COLLECTED. Every character is an evolve
	-- (GameConfig.GetEvolveStep) and the only way past a stage is through all five of it, so any
	-- hole BELOW the stage a save stands at is a hole the current rule says cannot exist -- and one
	-- nothing could ever fill, because GetEvolveStep only ever looks at the stage you are on.
	-- Everything strictly below the current stage is granted; the current stage is left alone,
	-- because that one is still being walked and its remaining steps are what is being paid for now.
	data.Characters = data.Characters or {}
	for stageIndex = 1, math.min((data.StageIndex or 1) - 1, #GameConfig.Stages) do
		for _, entry in ipairs(GameConfig.GetCharactersForStage(stageIndex)) do
			data.Characters[entry.key] = true
		end
	end
	-- and the stage they ARE on always owes them its first: it was handed over by the evolve that
	-- brought them here, and at stage 1 it is the character the game starts you as.
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

	-- ===== HOW LONG THEY WERE GONE, MEASURED BEFORE ANYTHING OVERWRITES IT =====
	--
	-- Held in memory rather than written onto `data`, and that is the whole point: the autosave loop
	-- runs every 60 seconds and would cheerfully persist a pending-payout field, so a crash between
	-- that write and the payout becomes a payout the player collects again on their next join. A
	-- number that only ever describes THIS session has no business in a DataStore.
	--
	-- A negative elapsed (two servers whose clocks disagree, or a save stamped in the future) clamps
	-- to zero inside GetOfflineSeconds rather than paying out backwards.
	local lastSeen = tonumber(data.LastSeen) or 0
	PlayerDataService.OfflineSeconds[player.UserId] =
		GameConfig.GetOfflineSeconds(lastSeen > 0 and (os.time() - lastSeen) or 0)

	-- Reads yield, and a player can leave during one. Caching them then leaves an entry for
	-- somebody who is gone -- which never gets cleared (PlayerRemoving already ran) and is handed
	-- to them stale if they rejoin this same server.
	if not player.Parent then return nil end

	-- Group membership check (Phase 5.5)
	if RunService:IsStudio() then
		data.InGroup = true
	elseif GameConfig.RobloxGroupId and GameConfig.RobloxGroupId > 0 then
		local ok, inGroup = pcall(function()
			return player:IsInGroup(GameConfig.RobloxGroupId)
		end)
		data.InGroup = (ok and inGroup) or false
	else
		data.InGroup = false
	end

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
	-- Stamped on EVERY save, not just the leave-save: a server that crashes never gets to run its
	-- leave-save, and a LastSeen that only moved on a clean exit would pay that player eight hours
	-- for a crash they did not choose.
	data.LastSeen = os.time()

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

-- ===== THE ONE SETTING THE CLIENT IS ALLOWED TO WRITE =====
--
-- Every other write to `data` in this game is server-authoritative. Audio levels are the deliberate
-- exception: a volume fader is worth nothing to cheat, and routing four numbers through a service
-- would be ceremony around a preference.
--
-- Validated anyway, because "worth nothing to cheat" is not the same as "safe to store". Anything at
-- all can come down a RemoteEvent, and this table goes into a DataStore -- unchecked, that is how a
-- save ends up holding a megabyte of string under a key nobody looks at, or a NaN the client later
-- multiplies a SoundGroup by. Note `value == value`: that is the NaN test, and math.clamp passes NaN
-- straight through.
local AUDIO_KEYS = { Master = true, SFX = true, UI = true, Ambience = true }

local function handleSetAudio(player, payload)
	local data = PlayerDataService.Cache[player.UserId]
	if not data or type(payload) ~= "table" then return end
	if type(data.AudioVolumes) ~= "table" then
		data.AudioVolumes = { Master = 1, SFX = 1, UI = 1, Ambience = 1 }
	end
	for key, value in pairs(payload) do
		if AUDIO_KEYS[key] and type(value) == "number" and value == value then
			data.AudioVolumes[key] = math.clamp(value, 0, 1)
		end
	end
	-- deliberately NOT pushed back to the client: it is the client's own value coming home, and a
	-- DataUpdate landing mid-drag would fight the fader the player is still holding
end

function PlayerDataService.Init()
	local setAudio = Remotes:FindFirstChild("SetAudioVolumes")
	if not setAudio then
		setAudio = Instance.new("RemoteEvent")
		setAudio.Name = "SetAudioVolumes"
		setAudio.Parent = Remotes
	end
	setAudio.OnServerEvent:Connect(handleSetAudio)

	Players.PlayerAdded:Connect(function(player)
		local data = PlayerDataService.Load(player)
		-- nil means the player was kicked or left during the read. Everything below would index it.
		if not data then return end

		-- FUNNEL STEP 1. "Joined" means the server is holding their save, not that the Player
		-- instance appeared -- a join that fails its DataStore read is a kick, and counting it as
		-- an arrival would put a phantom at the top of every funnel chart.
		Telemetry.Funnel(player, "joined", data)

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

		-- THE JOIN PUSH IS A RACE AND IT IS ONE THE CLIENT CANNOT WIN RELIABLY. Every client script
		-- that draws from `data` -- MainUI, FirstJoin, the panels -- has to have reached its
		-- `DataUpdate` connect before this fires, and each of them gets there only after a string
		-- of `WaitForChild`s, several `require`s and a whole ScreenGui built out of thousands of
		-- instances. A `RemoteEvent` fired at a client that is not listening yet is simply gone.
		--
		-- Nothing was broken by that, because `DNAService`'s periodic sync pushes every 3 seconds
		-- and any listener that missed the first payload catches the next one. But three seconds
		-- is a very long time to spend at the start of a first session: it is a HUD with no
		-- numbers in it and, for a brand-new player, the guided tutorial not having started yet.
		--
		-- Three pushes over ~1.5 s close it for every listener at once, which is why this is here
		-- rather than in any one client. It costs two extra payloads per join and no new remote.
		task.wait(0.3)
		PlayerDataService.PushToClient(player)
		task.spawn(function()
			for _, delay in ipairs({ 0.5, 1.0 }) do
				task.wait(delay)
				-- Re-checked each time: a player can leave inside this window, and `PushToClient`
				-- would then be firing at a Player that is no longer in the game.
				if player.Parent then PlayerDataService.PushToClient(player) end
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		PlayerDataService.Save(player, true)
		PlayerDataService.Cache[player.UserId] = nil
		PlayerDataService.OfflineSeconds[player.UserId] = nil
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
