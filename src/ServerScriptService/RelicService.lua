-- RelicService -- the Relic Forge: chests in, relics out, four slots.
--
-- WHAT THIS OWNS: opening a chest (free timer or diamonds), equipping and unequipping, and merging
-- duplicates into levels. What it deliberately does NOT own is any maths -- every number lives in
-- `GameConfig.Relics`, because the panel has to quote the same figures the server rolls and a
-- service-side formula is how a screen ends up advertising a bonus nothing applies. See the note
-- over `GetRelicMult` there.
--
-- ===== THE ORDER OF OPERATIONS IS THE WHOLE SECURITY MODEL =====
--
-- Every handler below is the same five steps in the same order, and the order is what makes them
-- safe: **fetch the save -> validate against the SAVE and the CONFIG -> charge -> grant -> push**.
-- Nothing takes a number off the client. `OpenRelicChest` is sent no arguments at all;
-- `EquipRelic` is sent a key that is looked up in `GameConfig.RelicsByKey` and then checked against
-- `data.Relics` before anything is written. A tampered client can name a relic that exists and can
-- do nothing else with it.
--
-- CHARGE BEFORE GRANT, WITH NO YIELD BETWEEN. The timestamp is stamped and the diamonds are debited
-- BEFORE the roll, in the same synchronous block -- the rule `RewardService`, `CodesService` and
-- `RobuxShopService` all carry their own note about. A yield in the middle is how a double-fired
-- remote pays twice.
--
-- ===== WHY THERE IS NO `GrantRelic` PUBLIC FUNCTION (yet) =====
--
-- `ROADMAP.md` 17.6 wants relics to be FOUND -- hidden passages, not shop shelves -- and the honest
-- shape for that is a chest granted by whatever found it, then opened through this service. So the
-- door that a future boss drop or hidden passage will use is `RelicService.GiveChest(player, n)`,
-- which banks an UNOPENED chest. The reveal always happens here, so there is exactly one place that
-- knows what a chest is worth.

local RS = game:GetService("ReplicatedStorage")
local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS.Remotes

local PlayerDataService = require(script.Parent.PlayerDataService)
local Telemetry = require(script.Parent.Telemetry)

local RelicService = {}

-- The Remotes folder is authored in the place rather than generated, so a remote a newer version of
-- this file talks over simply does not exist in an older save of the place. Creating the missing
-- ones here keeps script and place in step without a by-hand Studio step -- and the client waits for
-- them by name, so it does not matter which side wins the race. (`PetService`'s idiom, copied.)
local function ensureRemote(name)
	local r = Remotes:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = Remotes
	end
	return r
end

local OpenRelicChest = ensureRemote("OpenRelicChest")
local EquipRelic = ensureRemote("EquipRelic")
local UnequipRelic = ensureRemote("UnequipRelic")
local MergeRelic = ensureRemote("MergeRelic")

local function refuse(player, message)
	Remotes.Notify:FireClient(player, { kind = "error", message = message })
end

-- ===== THE GATE =====
--
-- Checked in every handler rather than once at the panel, because the panel is the client's and the
-- client is not the authority on whether the forge is open. It also stamps the flag on the way past:
-- this is the only place that has both the live stage and a reason to look at it, so a player who
-- crosses stage 10 gets the permanent unlock the first time they touch the forge rather than needing
-- a separate watcher somewhere.
local function forgeOpen(player, data)
	if GameConfig.IsRelicForgeUnlocked(data) then
		if not data.RelicForgeUnlocked then
			data.RelicForgeUnlocked = true
		end
		return true
	end
	refuse(player, ("The Relic Forge opens at stage %d!"):format(GameConfig.RelicUnlockStage))
	return false
end

-- ===== BANKING AN UNOPENED CHEST =====
--
-- The seam for every future source -- boss drops, hidden passages, a season reward. Deliberately
-- separate from opening one, so a chest can be handed over by code that knows nothing about relics.
function RelicService.GiveChest(player, count)
	local data = PlayerDataService.Get(player)
	if not data then return end
	data.RelicChests = (tonumber(data.RelicChests) or 0) + (tonumber(count) or 1)
	PlayerDataService.PushToClient(player)
end

-- ===== OPENING =====
--
-- Three ways in, one roll out. `source` is the client's only input and it is a string matched
-- against a closed set -- never a cost, never a bias, never a rarity.
function RelicService.HandleOpenChest(player, source)
	local data = PlayerDataService.Get(player)
	if not data then return end
	if not forgeOpen(player, data) then return end

	local now = os.time()
	local bias = 0

	if source == "diamonds" then
		local cost = GameConfig.RelicChestDiamondCost
		if (data.Diamonds or 0) < cost then
			refuse(player, ("Need %d Diamonds for a Relic Chest!"):format(cost))
			return
		end
		-- CHARGED FIRST, in the same block as the roll below and with nothing that yields between.
		data.Diamonds -= cost
		Telemetry.Economy(player, "Sink", Telemetry.Currency.Diamonds, cost, data.Diamonds,
			Telemetry.Tx.Shop, "relicChest")
		bias = GameConfig.RelicChestDiamondBias

	elseif source == "banked" then
		-- a chest something else already handed over (`GiveChest`)
		if (tonumber(data.RelicChests) or 0) <= 0 then
			refuse(player, "You have no Relic Chests!")
			return
		end
		data.RelicChests -= 1

	else
		-- the free timer, and the default: an unrecognised `source` lands here rather than erroring,
		-- so a stale client cannot get a free diamond chest by sending a word this file has not heard
		local ready, remaining = GameConfig.GetRelicChestReady(data, now)
		if not ready then
			refuse(player, ("Next free Relic Chest in %dm %02ds"):format(remaining // 60, remaining % 60))
			return
		end
		-- STAMPED BEFORE THE GRANT, the rule every timed reward in this game follows.
		data.LastRelicChest = now
	end

	-- Luck bends the tier table exactly the way it bends an egg roll, and it is the SAME luck --
	-- pets, potions, upgrades and passes all feed `GetLuckPercent`, so a relic chest rewards the luck
	-- build a player already has rather than asking them to build a second one.
	-- 20.3: CHEST OPENED. Here, below all three source branches, so the diamond chest, the banked
	-- chest and the free timer all count as the same act -- which is what they are to a player.
	Telemetry.Custom(player, "ChestOpened")

	local luck = GameConfig.GetLuckPercent(data)
	local relic = GameConfig.RollRelic(luck, bias)
	local entry, isNew = GameConfig.AddRelic(data, relic.key, 1)
	data.RelicChestsOpened = (tonumber(data.RelicChestsOpened) or 0) + 1

	-- FIRST COPIES AUTO-EQUIP INTO A FREE SLOT. A relic that arrives doing nothing until the player
	-- finds the panel and drags it is a reward that does not feel like one, and the first chest is
	-- exactly when nobody knows what a socket is. Only ever into an EMPTY slot -- it never displaces
	-- something the player chose, which would be the system playing the game for them.
	local equipped = false
	if isNew and #data.EquippedRelicKeys < GameConfig.GetMaxEquippedRelics(data) then
		table.insert(data.EquippedRelicKeys, relic.key)
		equipped = true
	end

	-- ===== AND THE COLLECTION RELIC (30.2) =====
	--
	-- THE FAUCET, and until it existed the whole collection layer was unreachable: 200 keys, a save
	-- field, twenty panel pages and a set bonus wired into `GetRelicAdd` / `GetRelicMult`, with
	-- nothing anywhere that could put a single one of them in a save. `CountCompletedRelicSets`
	-- said so out loud -- "zero for the whole population until a faucet ships".
	--
	-- ONE CHEST PAYS BOTH LAYERS, and they do not compete. The equippable above is the stat reward
	-- and its odds are untouched by this; the collection relic is a second, separate grant off the
	-- same act. Nothing was taken away from the chest to pay for it.
	--
	-- THE ZONE IS WHERE THE PLAYER IS STANDING, and that is the whole progression gate on this
	-- layer. There is no per-set unlock flag and there does not need to be one: a set only fills
	-- while its zone is the ground under your feet, so the five Mythics -- the capstones of zones
	-- 16 to 20 -- are reachable only by a player who has actually got there. It also means a
	-- diamond chest cannot buy a late-zone relic early, which is the shape 17.6 asked for.
	--
	-- `CurrentZone` SURVIVES THE ARENA AND THE EXPEDITION. Only `HandleTeleportRequest` writes it;
	-- `EnterArena` and the expedition entrance both go through `travel()`, which does not -- so a
	-- chest opened inside either still pays the zone the player came from. The guard below is for
	-- a save carrying a zone key that no longer exists in the strip, not for those two.
	local zoneKey = data.CurrentZone
	if not GameConfig.RelicSetsByZone[zoneKey] then zoneKey = "Forest" end

	-- PREFERS SOMETHING NOT YET OWNED, tier by tier -- `RollUnownedSetRelic`'s own note explains
	-- why: a collection wants the next piece, and only hands back a duplicate once the rolled tier
	-- is complete. Same luck and the same chest bias as the roll above, so a bought chest is
	-- better on both layers at once rather than only on one.
	local setRelic = GameConfig.RollUnownedSetRelic(data, zoneKey, luck, bias)
	local setNew, setDust = false, 0
	if setRelic then
		setRelic, setNew, setDust = GameConfig.AddSetRelic(data, setRelic.key, 1)
	end

	PlayerDataService.PushToClient(player)

	-- AFTER the push, so the toast never arrives before the data that justifies it.
	Remotes.Notify:FireClient(player, {
		kind = "relic",
		relicKey = relic.key,
		rarity = relic.rarity,
		isNew = isNew,
		equipped = equipped,
		copies = entry and entry.copies or 1,
		message = isNew
			and ("%s relic! %s"):format(relic.rarity, relic.name)
			or ("%s  \u{00B7}  copy %d"):format(relic.name, entry and entry.copies or 1),
	})

	-- ITS OWN TOAST, ON THE SAME `relic` KIND. Two grants are two events to a player and folding
	-- them into one line would hide whichever came second. The kind is reused rather than invented
	-- because MainUI's `relic` branch already does everything this needs -- the big card for a
	-- first Legendary or Mythic, the toast for everything else, the rarity-pitched sting -- and it
	-- resolves the key through `GetSetRelic` as well as `RelicsByKey`, so the chip carries the
	-- form's own drawing in its set's tint. `equipped` is deliberately absent: a collection relic
	-- has no socket and never will, which is the promise the separate save field enforces.
	if setRelic then
		local copies = GameConfig.GetSetRelicCopies(data, setRelic.key)
		Remotes.Notify:FireClient(player, {
			kind = "relic",
			relicKey = setRelic.key,
			rarity = setRelic.rarity,
			isNew = setNew,
			copies = copies,
			-- the dust is the entire value of a duplicate, so it is said out loud rather than left
			-- to be discovered as a number that moved on a panel the player may not have open
			message = setNew
				and ("%s relic! %s"):format(setRelic.rarity, setRelic.name)
				or ("%s  \u{00B7}  copy %d  \u{00B7}  +%d Dust"):format(setRelic.name, copies, setDust),
		})
	end
end

-- ===== EQUIP =====
--
-- `PetService.HandleEquip`'s ladder, copied because it is the one that has already been got right:
-- ownership against THIS player's own table, idempotent on something already worn, then the slot
-- cap -- computed from the save, never a constant.
function RelicService.HandleEquip(player, key)
	local data = PlayerDataService.Get(player)
	if not data then return end
	if not forgeOpen(player, data) then return end

	local relic = GameConfig.GetRelic(key)
	if not relic then return end
	if not (data.Relics and data.Relics[key]) then return end

	for _, k in ipairs(data.EquippedRelicKeys) do
		if k == key then return end
	end

	local maxSlots = GameConfig.GetMaxEquippedRelics(data)
	if #data.EquippedRelicKeys >= maxSlots then
		refuse(player, ("All %d relic slots are full! Unequip one first."):format(maxSlots))
		return
	end

	table.insert(data.EquippedRelicKeys, key)
	PlayerDataService.PushToClient(player)
end

function RelicService.HandleUnequip(player, key)
	local data = PlayerDataService.Get(player)
	if not data then return end
	local kept = {}
	for _, k in ipairs(data.EquippedRelicKeys or {}) do
		if k ~= key then table.insert(kept, k) end
	end
	data.EquippedRelicKeys = kept
	PlayerDataService.PushToClient(player)
end

-- ===== MERGE =====
--
-- Three spare copies plus DNA raises a level. "Spare" is the load-bearing word: the check is
-- `copies >= 1 + MergeCopies`, so the copy the player is actually WEARING is never eaten. A merge
-- that unequips you is a merge nobody presses twice.
function RelicService.HandleMerge(player, key)
	local data = PlayerDataService.Get(player)
	if not data then return end
	if not forgeOpen(player, data) then return end

	local relic = GameConfig.GetRelic(key)
	if not relic then return end
	local entry = data.Relics and data.Relics[key]
	if type(entry) ~= "table" then return end

	-- ONE PLAN, READ ONCE, and the panel greys its button off the same call -- so the button and the
	-- charge cannot disagree about what a forge costs. 30.2 is what made that matter: a level is now
	-- payable in two currencies (spare copies, and `RelicDust` standing in for the copies you are
	-- short), and two implementations of a two-currency price is two chances to charge the wrong one.
	local plan = GameConfig.GetRelicMergePlan(data, key)
	local level = plan.level
	if plan.maxed then
		refuse(player, ("%s is already Lv.%d!"):format(relic.name, GameConfig.RelicMaxLevel))
		return
	end
	if not plan.ok then
		refuse(player, ("Need %d more Relic Dust to forge %s!"):format(
			plan.dustNeed - plan.dustHave, relic.name))
		return
	end

	-- SCALED, like every other DNA price in the game, so a level-2 merge does not become free at
	-- stage 20 -- `ScaleReward` is the same function the packs and the upgrades go through.
	local cost = GameConfig.ScaleReward(GameConfig.GetRelicMergeCost(level), data)
	if (data.DNA or 0) < cost then
		refuse(player, "Not enough DNA to forge!")
		return
	end

	data.DNA -= cost
	Telemetry.Economy(player, "Sink", Telemetry.Currency.DNA, cost, data.DNA,
		Telemetry.Tx.Shop, "relicMerge")
	-- SPEND WHAT THE PLAN SAID, in the plan's own order: copies first, dust for the shortfall. The
	-- copy you own is never spent -- `useCopies` is capped at `copies - 1` -- so forging can raise a
	-- relic's level but can never take the relic itself away.
	entry.copies -= plan.useCopies
	-- NOT LOGGED THROUGH `Telemetry.Economy`, deliberately. Its `Currency` enum is DNA / Diamonds /
	-- Robux, and dust is none of the three -- logging a dust sink as a DNA sink of 0 would put a
	-- false row in the one funnel the game has. Row 30.8 owns the dust events.
	if plan.dustNeed > 0 then
		data.RelicDust = (tonumber(data.RelicDust) or 0) - plan.dustNeed
	end
	entry.level = level + 1

	PlayerDataService.PushToClient(player)
	PlayerDataService.UpdateLeaderstats(player)
	Remotes.Notify:FireClient(player, {
		kind = "relic",
		relicKey = key,
		rarity = relic.rarity,
		isNew = false,
		merged = true,
		message = ("%s forged to Lv.%d!"):format(relic.name, entry.level),
	})
end

function RelicService.Init()
	-- Every argument is type-gated at the boundary and then looked up in the config, so nothing
	-- past this line has to wonder whether it is holding a string.
	OpenRelicChest.OnServerEvent:Connect(function(player, source)
		RelicService.HandleOpenChest(player, type(source) == "string" and source or nil)
	end)
	EquipRelic.OnServerEvent:Connect(function(player, key)
		if type(key) == "string" then RelicService.HandleEquip(player, key) end
	end)
	UnequipRelic.OnServerEvent:Connect(function(player, key)
		if type(key) == "string" then RelicService.HandleUnequip(player, key) end
	end)
	MergeRelic.OnServerEvent:Connect(function(player, key)
		if type(key) == "string" then RelicService.HandleMerge(player, key) end
	end)
	print(("[RelicService] forge open from stage %d, %d relics, %d slots max")
		:format(GameConfig.RelicUnlockStage, #GameConfig.Relics, GameConfig.RelicMaxSlots))
end

return RelicService
