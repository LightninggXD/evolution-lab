local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS.Remotes

local PlayerDataService = require(script.Parent.PlayerDataService)
local SeasonPassService = require(script.Parent.SeasonPassService)
local AnnounceService = require(script.Parent.AnnounceService)

local PetService = {}

-- The Remotes folder is authored in the place rather than generated, so a remote that a newer
-- version of this file talks over simply does not exist in an older save of the place. Creating
-- the missing ones here keeps script and place in step without a by-hand Studio step -- and the
-- client waits for them by name, so it does not matter which side wins the race.
local function ensureRemote(name)
	local r = Remotes:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = Remotes
	end
	return r
end

-- ===== BONUS CALCULATION =====
-- Returns the combined multiplier/add contributed by all currently-equipped pets.
-- incomeMult and dnaMult stack multiplicatively across pets, luckAdd stacks additively.
--
-- ===== EXCEPT DAMAGE, WHICH IS A SUM OF CONTRIBUTIONS AND NOT A PRODUCT =====
--
-- This is the third time this codebase has had to make the same correction, and the reasoning is
-- identical each time -- see `GetMutationIncomeMult` (a product over every mutation ever rolled
-- reached x5,000,000) and the idle-income cap. A quantity that multiplies once per item, over a
-- collection that only grows, is not a bonus; it is an exponential in the number of slots.
--
-- MEASURED on the owner's own save, 2026-08-09: five equipped pets, none of them rare or maxed
-- (two Legendary Normals, two Epic Goldens, one Rare Rainbow) at x3.4 to x4.12 each, multiplying
-- out to **x652**. The full 100-step evolution ladder is worth x1394 end to end -- so a mid-game
-- pet loadout was handing over half the game's entire progression, and with the +3 Pet Slots pass
-- and VIP taking it to nine slots the product goes past x20,000. Against that, the 7.6% an evolve
-- pays is invisible, which is the "I evolve and nothing changes" complaint arriving by a second
-- route even after the damage caps were removed.
--
-- Summed, the same five pets are worth x14.3: a real, felt reward for hatching, and one that a
-- tenth slot improves by roughly a tenth rather than by a factor of four.
--
-- ===== AND THE ECONOMY REBALANCE THAT WAS DEFERRED HERE HAS NOW HAPPENED =====
--
-- This note used to end by saying `incomeMult` and `dnaMult` were deliberately left multiplicative
-- because changing them was an economy rebalance rather than a combat fix. That rebalance is done:
-- both are hard 1 in GameConfig.PetBaseBonus and a pet pays DAMAGE and LUCK only.
--
-- They were the larger half of the same bug. One Legendary Normal pet carried incomeMult 4.2 AND
-- dnaMult 9.0, both stacking multiplicatively across the slots, so the first pet a player ever
-- hatched multiplied every click and every kill by **x37.8** -- which is the reported "DNA was
-- about 60, then I got a pet and it was about 1,000", and why no price anywhere in the game could
-- mean anything. The DNA curve is authored for a player with no pets (14-20 kills per stage), so
-- removing this restores the pacing it was tuned for rather than needing a second retune.
--
-- The loop below therefore keeps its `*=` on two constants that are now 1. That is deliberate: the
-- operator is the bug, and leaving it visible next to the `+=` on damage states the rule better
-- than a deleted line would.
-- MOVED TO GameConfig ON 2026-08-11 so the client can reach it (the egg panel shows real odds, and
-- odds need the equipped team's luck). This is now one line pointing at the single implementation --
-- kept under its old name because roughly a dozen call sites across this file, DNAService and the
-- HUD already say `PetService.GetEquippedBonus`, and renaming them would be churn for no gain.
PetService.GetEquippedBonus = GameConfig.GetEquippedBonus

-- A player may only buy an egg while standing near the Pet Shop kiosk that sells it --
-- there is deliberately no way to fire this from the Pets UI tab anymore.
local PET_SHOP_RANGE = 20
function PetService.IsNearPetShop(player, zoneKey)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	local zoneModel = workspace.Zones:FindFirstChild(zoneKey)
	local kiosk = zoneModel and zoneModel:FindFirstChild("PetShopKiosk")
	if not kiosk then return false end
	local kioskPos = kiosk:GetPivot().Position
	return (hrp.Position - kioskPos).Magnitude <= PET_SHOP_RANGE
end

-- ===== ACTIONS =====

-- THREE THINGS THE EGG COUNTER WAS NOT CHECKING.
--
-- The lookup below walks `GameConfig.Eggs` GLOBALLY -- all sixty of them, every zone -- and the
-- only test was whether the key existed and whether the DNA covered it. So a stage-1 player
-- standing in Forest could buy the Absolute Plane's Premium egg by naming it, which is the entire
-- twenty-zone pet progression bypassed in one remote call. There was no cooldown either, and no
-- ceiling on how many pets a save may hold -- and a save that grows past the DataStore's 4 MB
-- limit stops saving, forever, with nothing but a warning in the log.
local function eggByKey(key)
	for _, e in ipairs(GameConfig.Eggs) do
		if e.key == key then return e end
	end
	return nil
end

-- ===== ONE ROLL, SHARED BY THE SINGLE AND THE BULK PATH =====
--
-- Extracted so x10 cannot become a second implementation of what an egg is worth. It is the roll
-- and the insert and nothing else: no cost, no cap check, no notification, no replication -- every
-- one of those differs between buying one and buying ten, and every one of them is the caller's
-- business. Pure in the sense that matters here: it does not yield, so a caller can run it in a
-- loop between a single affordability check and a single deduction with no window in between.
local function rollAndInsert(data, eggDef)
	-- ===== THE EGG ROLL USES THE REAL LUCK NUMBER NOW =====
	--
	-- This used to be `data.Upgrades.Luck * 2 + equipped pet luckAdd + egg luckBonus`, with a comment
	-- claiming it "mirrors DNAService.GetLuckPercent's base term". It mirrored two of that function's
	-- SIX terms: MegaLuck, the Luck Potion, the Lucky pass, VIP and live-event luck were all missing.
	-- So a player who drank a Luck Potion or bought the Lucky pass got **exactly zero** effect on
	-- hatching -- the one place in the game a player expects luck to matter most.
	--
	-- It reads GameConfig rather than DNAService because DNAService requires THIS file, so a require
	-- in the other direction is a cycle -- which is the whole reason the duplicate formula existed.
	-- Moving the total into GameConfig removed the cycle instead of working around it, and the egg
	-- panel on the client now quotes the same number this rolls against.
	local luckPercent = GameConfig.GetLuckPercent(data) + (eggDef.luckBonus or 0)
	-- rolls only within this egg's own pool -- its zone's species, sliced by the egg tier's
	-- rarity window -- and the tier's bias shifts the odds inside that slice on top of luck
	local petDef = GameConfig.RollPetForEgg(eggDef, luckPercent)
	table.insert(data.Pets, { id = HttpService:GenerateGUID(false), key = petDef.key, tier = "Normal" })
	return petDef
end

local EGG_INTERVAL = 0.35   -- comfortably faster than the hatch animation, far slower than a loop
-- One ceiling for the whole game, read from GameConfig so this file, TradeService and the HUD
-- cannot drift apart -- see the note there for why it is 100 and why it stopped being private.
local MAX_PETS = GameConfig.MaxOwnedPets
local lastEgg = {}          -- [userId] = os.clock()

-- `auto` is true only when DriveAutoHatch bought this one. It changes NOTHING about the purchase --
-- same cost, same roll, same cap -- and exists purely so the client knows which presentation to
-- play: a deliberate purchase earns the full-screen reveal, and a pass buying two a second must
-- never take over the screen. See HatchReveal.
function PetService.HandleBuyEgg(player, eggKey, auto)
	local data = PlayerDataService.Get(player)
	if not data then return end

	local now = os.clock()
	if lastEgg[player.UserId] and now - lastEgg[player.UserId] < EGG_INTERVAL then return end

	local eggDef = eggByKey(eggKey)
	if not eggDef then return end

	-- the zone this egg belongs to has to be one the player has actually unlocked
	if eggDef.zone then
		local unlocked = false
		for _, key in ipairs(data.UnlockedZones or {}) do
			if key == eggDef.zone then
				unlocked = true
				break
			end
		end
		if not unlocked then
			Remotes.Notify:FireClient(player, { kind = "error",
				message = "You haven't unlocked " .. eggDef.zone .. " yet!" })
			return
		end
	end

	-- CAPACITY IS CHECKED BEFORE THE DNA IS TOUCHED, and the ordering is load-bearing: the deduction
	-- is 15 lines below, so a full inventory refuses the purchase without ever having charged for it.
	-- That was already true at the old ceiling and is the reason the brief's "never consume currency
	-- and then fail to give the pet" needed no fix here -- it needs only to keep being true, so
	-- nothing that yields may ever be introduced between this check and the deduction.
	if #data.Pets >= MAX_PETS then
		Remotes.Notify:FireClient(player, { kind = "error",
			message = ("Pet inventory full -- %d/%d. Release or fuse one first!"):format(#data.Pets, MAX_PETS) })
		return
	end

	if data.DNA < eggDef.cost then
		Remotes.Notify:FireClient(player, { kind = "error", message = "Not enough DNA for " .. eggDef.name .. "!" })
		return
	end

	-- stamped only once the purchase is actually going through, so a refused buy does not put the
	-- player on cooldown for something they never got
	lastEgg[player.UserId] = now

	data.DNA -= eggDef.cost

	local petDef = rollAndInsert(data, eggDef)

	-- before the push, so quest progress rides out on the same replication the hatch already sends
	SeasonPassService.Track(player, "eggs", 1)

	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.PushToClient(player)
	Remotes.Notify:FireClient(player, {
		kind = "pet",
		-- the KEY, not just the name: HatchReveal rebuilds the actual pet rig out of the egg
		-- (Phase 6.1) and PetModel.Build is keyed, so without this the client would have to search
		-- the zone tables by display name and hope two species never share one
		key = petDef.key,
		name = petDef.name,
		emoji = petDef.emoji,
		tier = "Normal",
		rarity = petDef.rarity,
		-- which presentation the client should play; see the note on the signature above
		auto = auto == true,
	})

	-- After the payout and after the client push, because a beam that goes up before the pet is in
	-- the inventory is announcing something that has not happened yet. Called on EVERY hatch: the
	-- rarity rule and the rate limit both live in AnnounceService, so no publisher has to know what
	-- counts as rare. See its header for why that is a service rather than an `if` here.
	AnnounceService.PetHatched(player, petDef)
end

-- ===== x10 =====
--
-- Opening one egg at a time is the slowest thing in the game, and ten separate `HandleBuyEgg` calls
-- would not fix it: each fires its own `pet` notification, and `HatchReveal.busy` keeps one sequence
-- per egg -- so nine of the ten reveals would be silently dropped and the player would watch one
-- hatch after paying for ten. A bulk buy therefore needs its own payload, and this is it.
--
-- IT BUYS WHAT FITS, RATHER THAN REFUSING THE BATCH. A player with 5 free slots who presses x10 gets
-- 5, and a player who can afford 6 gets 6. Refusing outright would be defensible and is worse in
-- practice: the whole point of the button is not doing arithmetic at the podium, and "you cannot
-- afford ten" leaves them pressing x1 six times to find the edge. The count actually bought is in
-- the payload, so the client reports what happened rather than what was asked for.
--
-- ONE cooldown stamp, ONE deduction, ONE Season counter, ONE push and ONE notification for the whole
-- batch -- ten of each is ten replications of the entire save on the most expensive action in the
-- game. The affordability check and the deduction still bracket a loop that cannot yield, which is
-- the same property `HandleBuyEgg` relies on to never charge for a pet it does not hand over.
local BULK_COUNT = 10

function PetService.HandleBuyEggBulk(player, eggKey)
	local data = PlayerDataService.Get(player)
	if not data then return end

	local now = os.clock()
	if lastEgg[player.UserId] and now - lastEgg[player.UserId] < EGG_INTERVAL then return end

	local eggDef = eggByKey(eggKey)
	if not eggDef then return end

	if eggDef.zone then
		local unlocked = false
		for _, key in ipairs(data.UnlockedZones or {}) do
			if key == eggDef.zone then unlocked = true break end
		end
		if not unlocked then
			Remotes.Notify:FireClient(player, { kind = "error",
				message = "You haven't unlocked " .. eggDef.zone .. " yet!" })
			return
		end
	end

	-- how many the cap allows, and how many the wallet allows -- the smaller of the two, capped at
	-- ten. Computed BEFORE anything is spent, so the answer cannot change under the loop below.
	local room = MAX_PETS - #data.Pets
	if room <= 0 then
		Remotes.Notify:FireClient(player, { kind = "error",
			message = ("Pet inventory full -- %d/%d. Release or fuse one first!"):format(#data.Pets, MAX_PETS) })
		return
	end
	local affordable = eggDef.cost > 0 and math.floor(data.DNA / eggDef.cost) or BULK_COUNT
	local count = math.min(BULK_COUNT, room, affordable)
	if count <= 0 then
		Remotes.Notify:FireClient(player, { kind = "error", message = "Not enough DNA for " .. eggDef.name .. "!" })
		return
	end

	lastEgg[player.UserId] = now
	data.DNA -= eggDef.cost * count

	-- Nothing between here and the end of the loop yields.
	local rolled, best = {}, nil
	for _ = 1, count do
		local petDef = rollAndInsert(data, eggDef)
		table.insert(rolled, {
			key = petDef.key, name = petDef.name, emoji = petDef.emoji,
			tier = "Normal", rarity = petDef.rarity,
		})
		-- the headline of the batch: ten cards with nothing picked out is a list, not a reward
		if not best or GameConfig.GetRarity(petDef.rarity).bonusMult > GameConfig.GetRarity(best.rarity).bonusMult then
			best = rolled[#rolled]
		end
	end

	SeasonPassService.Track(player, "eggs", count)

	PlayerDataService.UpdateLeaderstats(player)
	PlayerDataService.PushToClient(player)
	Remotes.Notify:FireClient(player, {
		kind = "petBulk",
		pets = rolled,
		count = count,
		-- so the client can say "x6 of 10" rather than silently delivering fewer than the button said
		asked = BULK_COUNT,
		best = best,
	})

	-- Per pet, exactly as a single hatch does: the rarity rule and the 6-second per-player cooldown
	-- both live in AnnounceService, so ten Legendaries in one batch still raise one beam and no
	-- publisher here has to know that.
	for _, entry in ipairs(rolled) do
		AnnounceService.PetHatched(player, GameConfig.GetPetDef(entry.key))
	end
end

function PetService.HandleEquip(player, petId)
	local data = PlayerDataService.Get(player)
	if not data then return end

	local owned = false
	for _, p in ipairs(data.Pets) do
		if p.id == petId then
			owned = true
			break
		end
	end
	if not owned then return end

	for _, id in ipairs(data.EquippedPetIds) do
		if id == petId then return end -- already equipped
	end

	local maxEquipped = GameConfig.GetMaxEquippedPets(data)
	if #data.EquippedPetIds >= maxEquipped then
		Remotes.Notify:FireClient(player, { kind = "error", message = "Max " .. maxEquipped .. " pets equipped! Unequip one first." })
		return
	end

	table.insert(data.EquippedPetIds, petId)
	PlayerDataService.PushToClient(player)
end

function PetService.HandleUnequip(player, petId)
	local data = PlayerDataService.Get(player)
	if not data then return end

	for i, id in ipairs(data.EquippedPetIds) do
		if id == petId then
			table.remove(data.EquippedPetIds, i)
			break
		end
	end
	PlayerDataService.PushToClient(player)
end

-- ===== BULK EQUIP =====
-- A collection that runs to hundreds of pets cannot be managed one row at a time: without these
-- two, picking the best three means scrolling the whole list comparing numbers by eye, every
-- single time a better pet hatches.
--
-- Ranking is GameConfig.GetPetPower -- the same number the row prints -- so "Equip Best" can
-- never disagree with what the player is reading. Slots come from GetMaxEquippedPets, not the
-- base constant, so it keeps filling every slot after a Diamond PetSlot upgrade widens it.
function PetService.HandleEquipBest(player)
	local data = PlayerDataService.Get(player)
	if not data then return end

	-- `data` threaded through so the ranking honours the zone axis: without it Equip Best would
	-- keep choosing the pet that was strongest in the zone it hatched in rather than the one that
	-- is strongest where the player is standing now.
	local ranked = GameConfig.SortedPetsByPower(data.Pets or {}, data)
	if #ranked == 0 then
		Remotes.Notify:FireClient(player, { kind = "error", message = "No pets to equip yet!" })
		return
	end

	local maxEquipped = GameConfig.GetMaxEquippedPets(data)
	local chosen = {}
	for i = 1, math.min(maxEquipped, #ranked) do
		table.insert(chosen, ranked[i].id)
	end
	data.EquippedPetIds = chosen

	PlayerDataService.PushToClient(player)
	Remotes.Notify:FireClient(player, {
		kind = "reward",
		message = ("\u{1F43E} Equipped your %d strongest pets!"):format(#chosen),
	})
end

function PetService.HandleUnequipAll(player)
	local data = PlayerDataService.Get(player)
	if not data then return end
	if #data.EquippedPetIds == 0 then return end
	data.EquippedPetIds = {}
	PlayerDataService.PushToClient(player)
end

-- ===== RELEASING PETS =====
--
-- The one system in the pet stack that did not exist at all: with a 600-pet ceiling there was never
-- a reason to remove one, and a save reached 207. At 30 a player must be able to choose, so this is
-- the other half of the cap and neither is shippable without the other.
--
-- TAKES A LIST, ALWAYS -- a single delete is a list of one. The alternative is two handlers with
-- two sets of guards that have to agree about equipped pets, ids that do not exist, and the empty
-- case, and they would agree right up until one of them changed.
--
-- What is guarded, in order:
--   * the payload is a table of strings and no longer than the whole inventory -- an unbounded list
--     from a client is a table walk per entry paid for by the server
--   * every id is resolved against THIS player's own `data.Pets`; unknown ids are dropped silently
--     rather than refusing the batch, because a stale UI naming a pet that was just fused is an
--     ordinary race, not an attack
--   * an EQUIPPED pet is refused, not auto-unequipped. Releasing the team by accident is exactly the
--     mistake this dialog exists to prevent, and unequipping on the player's behalf would make the
--     destructive path the quiet one
--   * nothing is removed unless at least one id survived every check, so a no-op cannot cost a save
--     write or a replication
local MAX_DELETE_BATCH = 60

function PetService.HandleDeletePets(player, petIds)
	local data = PlayerDataService.Get(player)
	if not data then return end
	if type(petIds) ~= "table" then return end

	local wanted, n = {}, 0
	for _, id in ipairs(petIds) do
		if type(id) == "string" and not wanted[id] then
			wanted[id] = true
			n += 1
			if n >= MAX_DELETE_BATCH then break end
		end
	end
	if n == 0 then return end

	local equippedLookup = {}
	for _, id in ipairs(data.EquippedPetIds or {}) do equippedLookup[id] = true end

	local doomed, equippedHits = {}, 0
	for _, p in ipairs(data.Pets) do
		if wanted[p.id] then
			if equippedLookup[p.id] then
				equippedHits += 1
			else
				doomed[p.id] = true
			end
		end
	end

	local count = 0
	for _ in pairs(doomed) do count += 1 end
	if count == 0 then
		if equippedHits > 0 then
			Remotes.Notify:FireClient(player, { kind = "error",
				message = "Unequip a pet before releasing it!" })
		end
		return
	end

	local kept = {}
	for _, p in ipairs(data.Pets) do
		if not doomed[p.id] then table.insert(kept, p) end
	end
	data.Pets = kept

	PlayerDataService.PushToClient(player)
	Remotes.Notify:FireClient(player, {
		kind = "reward",
		message = (count == 1) and "\u{1F43E} Released 1 pet."
			or ("\u{1F43E} Released %d pets."):format(count),
	})
	-- reported separately, because a batch that released four and refused one is not a failure and
	-- must not be announced as one
	if equippedHits > 0 then
		Remotes.Notify:FireClient(player, { kind = "error",
			message = ("Kept %d equipped pet%s -- unequip to release."):format(
				equippedHits, equippedHits == 1 and "" or "s") })
	end
end

function PetService.HandleFuse(player, petKey, tier)
	local data = PlayerDataService.Get(player)
	if not data then return end

	local nextTier = GameConfig.GetNextTier(tier)
	if not nextTier then
		Remotes.Notify:FireClient(player, { kind = "error", message = "That pet is already max tier!" })
		return
	end

	local matches = {}
	for _, p in ipairs(data.Pets) do
		if p.key == petKey and p.tier == tier then
			table.insert(matches, p)
		end
	end
	if #matches < GameConfig.FuseRequirement then
		Remotes.Notify:FireClient(player, { kind = "error", message = "Need " .. GameConfig.FuseRequirement .. " copies to fuse!" })
		return
	end

	local toRemove = {}
	for i = 1, GameConfig.FuseRequirement do
		toRemove[matches[i].id] = true
	end

	local keptPets = {}
	for _, p in ipairs(data.Pets) do
		if not toRemove[p.id] then
			table.insert(keptPets, p)
		end
	end
	data.Pets = keptPets

	-- counted BEFORE the filter, so "did the fuse cost me a slot" is answerable below
	local wasEquipped = #data.EquippedPetIds
	local keptEquipped = {}
	for _, id in ipairs(data.EquippedPetIds) do
		if not toRemove[id] then
			table.insert(keptEquipped, id)
		end
	end
	data.EquippedPetIds = keptEquipped

	local fused = { id = HttpService:GenerateGUID(false), key = petKey, tier = nextTier }
	table.insert(data.Pets, fused)

	-- THE RESULT GOES ON IF THE FUSE JUST EMPTIED A SLOT.
	--
	-- Equipped bonuses MULTIPLY across the three slots, so fusing out of a shallow collection is a
	-- catastrophe the player cannot see coming: owning exactly four pets and fusing them takes the
	-- equipped product from x22.0 to x5.4, and at the Legendary/Rainbow end from 9.4e7 to 1.7e3 --
	-- five orders of magnitude, paid for what the UI calls an upgrade. With a deep pool the same
	-- fuse is a clean x1.9 to x3.8 gain, so the maths is right; what was wrong is that four pets
	-- came OFF and nothing went back on.
	--
	-- The pet that comes out is strictly stronger than any of the four that went in, so refilling a
	-- slot the fuse itself emptied can only improve the loadout. Guarded on `wasEquipped` so it
	-- never displaces a pet the player deliberately chose, and on the cap so it cannot overfill.
	if #keptEquipped < wasEquipped and #keptEquipped < GameConfig.GetMaxEquippedPets(data) then
		table.insert(data.EquippedPetIds, fused.id)
	end

	local petDef = GameConfig.GetPetDef(petKey)

	SeasonPassService.Track(player, "fuse", 1)

	PlayerDataService.PushToClient(player)
	Remotes.Notify:FireClient(player, {
		kind = "fuse",
		name = petDef and petDef.name or petKey,
		emoji = petDef and petDef.emoji or "",
		tier = nextTier,
		rarity = petDef and petDef.rarity,
	})
end

-- ===== SPENDING A RAINBOW CATALYST =====
--
-- The paid cousin of HandleFuse above, and deliberately the SIMPLER of the two. A fuse destroys
-- four pets and builds a fifth, which is why it carries all that machinery about emptied equip
-- slots; a catalyst raises the pet that is already there. The tier is mutated IN PLACE and the pet
-- keeps its id, so it stays equipped, stays in EquippedPetIds, and none of the slot-repair logic in
-- HandleFuse is needed or at risk here.
--
-- The client picks WHICH pet and nothing else. Ownership, the token count and the tier cap are all
-- decided here; a petId naming a pet the player does not own simply falls through.
function PetService.HandleTierUp(player, petId)
	local data = PlayerDataService.Get(player)
	if not data then return end

	if (data.TierUpTokens or 0) <= 0 then
		Remotes.Notify:FireClient(player, { kind = "error", message = "You have no Rainbow Catalyst!" })
		return
	end

	-- Explicitly initialised, for the reason stated over `local best, bestDist` in DriveAutoHatch:
	-- an uninitialised `local` is the one shape tools/luanames.py does not always bind, and a clean
	-- lint baseline is worth more than three characters.
	local pet = nil
	for _, p in ipairs(data.Pets) do
		if p.id == petId then pet = p break end
	end
	if not pet then return end

	-- Two different refusals with two different messages, because they mean different things to the
	-- player: one is "this pet is finished", the other is "this is as far as buying goes".
	if not GameConfig.GetNextTier(pet.tier) then
		Remotes.Notify:FireClient(player, { kind = "error", message = "That pet is already max tier!" })
		return
	end
	local nextTier = GameConfig.GetCatalystNextTier(pet.tier)
	if not nextTier then
		Remotes.Notify:FireClient(player, {
			kind = "error",
			message = GameConfig.CatalystMaxTier .. " is as far as a Catalyst goes -- fuse four to go higher!",
		})
		return
	end

	-- spent only after every check has passed, and with no yield between the check and the spend
	data.TierUpTokens -= 1
	pet.tier = nextTier

	local petDef = GameConfig.GetPetDef(pet.key)
	PlayerDataService.PushToClient(player)
	-- the same payload a fuse sends: the client already knows how to celebrate a new tier, and a
	-- second card that says the same thing in different words is not a feature
	Remotes.Notify:FireClient(player, {
		kind = "fuse",
		name = petDef and petDef.name or pet.key,
		emoji = petDef and petDef.emoji or "",
		tier = nextTier,
		rarity = petDef and petDef.rarity,
	})
end

-- ===== AUTO HATCH =====
-- Every egg prompt in the world, collected once by WireKiosks so the driver below does not walk
-- twenty zone models every tick. Rebuilt from scratch on each wiring pass, like the connections are.
local autoEggPoints = {}

-- What ten of this egg costs, for the x10 prompt's own label. Nil-safe because the prompt is built
-- from an attribute and an egg key that no longer resolves must not stop the kiosk wiring.
local function eggDefCost(key)
	local def = eggByKey(key)
	return def and def.cost or 0
end

-- The single prompt prints a raw "500 DNA", which is fine at 500 and unreadable at ten times a
-- late-zone egg (90,000,000,000,000,000). Same shortening the HUD and the creature plates use.
local DNA_SUFFIX = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp" }
local function shortDNA(n)
	local mag = 1
	while n >= 1000 and mag < #DNA_SUFFIX do
		n /= 1000
		mag += 1
	end
	if mag == 1 then
		return ("%d DNA"):format(n)
	end
	return ("%.1f%s DNA"):format(n, DNA_SUFFIX[mag])
end

-- Half the gap between the two prompts an egg carries, in pixels of the default prompt UI. Each one
-- is pushed this far from the shell's centre in the opposite direction, so the number is HALF the
-- separation, not the separation -- and 36 is therefore the floor, not the target.
--
-- MEASURED, not guessed. The default UI turns UIOffset into `SizeOffset = UIOffset / Size`, and the
-- card it builds for these prompts is 72 px tall (read off PlayerGui.ProximityPrompts in a live
-- session). So separation is 2 * this, and the first value tried -- 34 -- left the two cards
-- overlapping by 4 px, which looks exactly like the bug it was meant to fix. 44 leaves a 16 px gap.
--
-- Distance does not enter into it. A BillboardGui's offset size shrinks as the camera pulls away,
-- but SizeOffset is a FRACTION of that same size, so the two shrink together and the gap stays
-- proportional at every range.
local PROMPT_STACK = 44

-- A ProximityPrompt hangs off either a part or an attachment on one, and which one is ZoneBuilder's
-- business, not this file's.
local function promptAnchor(prompt)
	local parent = prompt.Parent
	if not parent then return nil end
	if parent:IsA("BasePart") then return parent end
	if parent:IsA("Attachment") and parent.Parent and parent.Parent:IsA("BasePart") then
		return parent.Parent
	end
	return nil
end

-- Scans every zone's Pet Shop (3 eggs, each its own ProximityPrompt tagged with an
-- EggKey attribute) and wires purchases. Runs fresh on every server start so it never
-- depends on a stale connection from a previous session.
function PetService.WireKiosks()
	table.clear(autoEggPoints)
	local zonesFolder = workspace:FindFirstChild("Zones")
	if not zonesFolder then return end
	for _, zoneModel in ipairs(zonesFolder:GetChildren()) do
		local shop = zoneModel:FindFirstChild("PetShop")
		if shop then
			for _, prompt in ipairs(shop:GetDescendants()) do
				-- The x10 prompts this function creates are skipped wholesale: they are already
				-- connected, and a pass that walked them would clone its own clones.
				if prompt:IsA("ProximityPrompt") and not prompt:GetAttribute("BulkPrompt") then
					local eggKey = prompt:GetAttribute("EggKey")
					-- ===== TWO JOBS HERE, AND THEY MUST BE GUARDED DIFFERENTLY =====
					--
					-- CONNECTIONS ARE ONCE-ONLY. A second call would connect `Triggered` twice on every
					-- egg in the game: one press, two purchases, two deductions. That hazard predates the
					-- x10 prompt -- cloning is simply what made it visible, since a duplicated prompt can
					-- be SEEN where a duplicated connection cannot. `Wired` is the guard, set on the
					-- prompt itself so the answer travels with the object.
					--
					-- THE ANCHOR LIST IS REBUILT EVERY TIME, and separating the two is not tidiness.
					-- `autoEggPoints` is cleared at the top of this function, so registering it inside the
					-- once-only branch means a SECOND call empties the list and never refills it: Auto
					-- Hatch would find no egg anywhere in the world and silently stop, for the rest of
					-- that server's life. Found by a live test that called WireKiosks twice -- the failure
					-- is invisible on the first call, which is the only one a real server makes today.
					if eggKey then
						if not prompt:GetAttribute("Wired") then
							prompt:SetAttribute("Wired", true)
							prompt.Triggered:Connect(function(player)
								PetService.HandleBuyEgg(player, eggKey)
							end)

							-- ===== THE x10 PROMPT IS BUILT HERE, NOT IN ZoneBuilder =====
							--
							-- ZoneBuilder is 8,000 lines behind a BUILD_VERSION guard that regenerates all
							-- twenty zones when it moves, and this needs neither the world rebuilt nor a
							-- version bump -- it is a second prompt on a shell that already exists. Same
							-- precedent as LeaderboardService building its own signs.
							--
							-- Cloned from the real prompt so reach, line-of-sight and hold all match the one
							-- beside it by construction; a hand-built second prompt would drift the day
							-- PROMPT_REACH changed. `Wired` is stripped from the copy so a clone can never
							-- be mistaken for an already-wired original by a later pass.
							--
							-- ===== AND THE PAIR HAS TO BE PULLED APART =====
							--
							-- Two prompts on ONE part draw at ONE point. Everything that makes the clone
							-- faithful -- same parent, same anchor, same default UIOffset of (0,0) -- also
							-- lands it exactly on top of the original, so "Buy Egg" and "Hatch x10" render
							-- as one smudged card and only the E key is legible. Neither prompt is broken;
							-- they are simply invisible to each other. That is the overlap in the shop.
							--
							-- The single moves up by PROMPT_STACK and the bulk down by the same, so the
							-- pair stays centred on the point the lone prompt used to occupy -- the podium
							-- and the egg's billboard were both composed around it.
							--
							-- Symmetric on purpose. Which way UIOffset's Y points is the default prompt
							-- UI's business, not ours, and a symmetric split cannot overlap whichever way
							-- it resolves: the worst a flipped sign costs is x10 reading above Buy Egg
							-- instead of below.
							prompt.UIOffset = Vector2.new(0, PROMPT_STACK)

							local bulk = prompt:Clone()
							bulk:SetAttribute("Wired", nil)
							bulk.Name = "BulkEggPrompt"
							bulk.ActionText = "Hatch x10"
							bulk.ObjectText = shortDNA(eggDefCost(eggKey) * 10)
							bulk.KeyboardKeyCode = Enum.KeyCode.F
							bulk.GamepadKeyCode = Enum.KeyCode.ButtonY
							-- a touch longer than the single: ten eggs' worth of DNA is not a press to make
							-- by brushing past the podium
							bulk.HoldDuration = 0.6
							bulk.UIOffset = Vector2.new(0, -PROMPT_STACK)
							bulk:SetAttribute("BulkPrompt", true)
							bulk.Parent = prompt.Parent
							bulk.Triggered:Connect(function(player)
								PetService.HandleBuyEggBulk(player, eggKey)
							end)
						end

						local anchor = promptAnchor(prompt)
						if anchor then
							-- The prompt's OWN activation distance, not a constant: it is the distance the
							-- player can see they are in range at, so auto-hatch starting anywhere else
							-- would read as the pass firing at random.
							table.insert(autoEggPoints, {
								part = anchor,
								eggKey = eggKey,
								reach = prompt.MaxActivationDistance,
							})
						end
					end
				end
			end
		end
	end
end

-- The Auto Hatch pass: keep buying from whichever egg the player is standing at.
--
-- ONE loop for the whole server rather than one per player, and it only ever touches players who
-- actually hold the pass -- the same shape the creature and boss drivers use, for the same reason.
--
-- IT GOES THROUGH HandleBuyEgg, which is the entire point: the rate limit, the zone-unlock check,
-- the 600-pet cap, the cost, the roll, the Season Pass counter and the notification are all already
-- there and all still apply. An auto-hatch that bought eggs by its own path would be a second
-- implementation of the shop that could drift from the real one.
--
-- The affordability and capacity checks are REPEATED here, silently, before the call. HandleBuyEgg
-- answers those two with a Notify, which is right for a player pressing a button and wrong two
-- times a second -- an empty wallet would bury the notification stack in "Not enough DNA".
--
-- DriveAutoHatch is public for the same reason PassService.GrantVipDaily is: every passId is still
-- 0, so nothing can make the real loop see the pass as owned, and a feature verified only by
-- reading is not verified.
local AUTO_HATCH_TICK = 0.5

-- ===== WHY AUTO HATCH NEEDS TO BE ABLE TO STOP, AND TO SAY SO =====
--
-- Two things changed under this loop and both make silence the wrong behaviour.
--
-- The inventory ceiling came down from 600 to 30 (10.2), so "full" went from a state almost nobody
-- reached to one every pass owner hits within a session. A loop that quietly does nothing twice a
-- second is indistinguishable from a pass that does not work -- and it is a paid pass.
--
-- And the brief asks for a player-facing OFF switch, which did not exist: the only way to stop it
-- was to walk away from the podium. It is a player ATTRIBUTE, the same mechanism the free
-- auto-attack toggle already uses (`AutoAttack`, CombatClient) -- the client flips it, the server
-- reads it, and neither has to know how the other is implemented. `nil` counts as ON, because a
-- player who bought Auto Hatch and stood at an egg meant to hatch; the toggle is for stopping.
--
-- The reason is reported ONCE PER TRANSITION, not once per tick. `autoStop[userId]` holds the last
-- reason announced, so a full inventory says so once and then stays quiet until something changes
-- -- which is the same problem 2.3 solved by checking silently, now solved without also making the
-- pass mute.
local autoStop = {}

local function reportAutoStop(player, reason, message)
	if autoStop[player.UserId] == reason then return end
	autoStop[player.UserId] = reason
	if message then
		Remotes.Notify:FireClient(player, { kind = "error", message = message })
	end
end

function PetService.DriveAutoHatch()
	for _, player in ipairs(game.Players:GetPlayers()) do
		local data = PlayerDataService.Get(player)
		-- Nothing is reported to a player who does not hold the pass: they have not asked for any of
		-- this and a notification about a feature they do not own is an advert, not feedback.
		if data and GameConfig.OwnsPass(data, "AutoHatch") then
			-- an explicit false is the toggle being off; nil is a pass owner who has never touched it
			if player:GetAttribute("AutoHatch") == false then
				-- silent: they turned it off, so they know
				reportAutoStop(player, "off", nil)
			elseif #data.Pets >= MAX_PETS then
				reportAutoStop(player, "full",
					("Auto Hatch stopped -- pet inventory full (%d/%d)."):format(#data.Pets, MAX_PETS))
			else
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root then
					local here = root.Position
					-- Explicitly initialised: `local a, b` with no `=` registers only the first name with
					-- tools/luanames.py, and a clean lint baseline is worth more than two words of brevity.
					local best, bestDist = nil, nil
					for _, point in ipairs(autoEggPoints) do
						if point.part.Parent then
							local dist = (point.part.Position - here).Magnitude
							if dist <= point.reach and (not bestDist or dist < bestDist) then
								best, bestDist = point, dist
							end
						end
					end
					-- Nearest egg wins. Three stand within a few studs of each other on every podium, so
					-- "the one you walked up to" has to be a distance and not the first match in the list.
					if best then
						local eggDef = eggByKey(best.eggKey)
						if eggDef and data.DNA < eggDef.cost then
							reportAutoStop(player, "broke",
								("Auto Hatch stopped -- not enough DNA for %s."):format(eggDef.name))
						elseif eggDef then
							-- cleared on a successful hatch, so the next time a reason DOES apply it is
							-- announced again rather than being swallowed as "already said that"
							autoStop[player.UserId] = nil
							-- `true` = bought by the pass, not by the player. Keeps the full-screen
							-- reveal off the screen of someone who is standing still farming.
							PetService.HandleBuyEgg(player, best.eggKey, true)
						end
					else
						-- standing nowhere near an egg is not a failure state and says nothing, but it
						-- does clear the last reason: walking away and coming back should re-announce
						autoStop[player.UserId] = nil
					end
				end
			end
		end
	end
end

function PetService.Init()
	PetService.WireKiosks()

	task.spawn(function()
		while true do
			task.wait(AUTO_HATCH_TICK)
			-- pcall'ed because an unattended loop gets no second chance: one error inside it and
			-- auto-hatch is dead for the rest of the server's life with no symptom anyone could name.
			pcall(PetService.DriveAutoHatch)
		end
	end)

	game.Players.PlayerRemoving:Connect(function(player)
		lastEgg[player.UserId] = nil
		-- keyed by UserId like lastEgg, and would otherwise hold a row for every player who has ever
		-- been on this server
		autoStop[player.UserId] = nil
	end)

	Remotes.BuyEgg.OnServerEvent:Connect(function(player, eggKey)
		if typeof(eggKey) == "string" then
			PetService.HandleBuyEgg(player, eggKey)
		end
	end)

	-- A separate remote rather than a count argument on BuyEgg: the count would be a number from the
	-- client on the one call in the game that spends currency in a multiple, and BULK_COUNT is the
	-- server's decision. This way there is nothing to validate and nothing to clamp.
	ensureRemote("BuyEggBulk").OnServerEvent:Connect(function(player, eggKey)
		if typeof(eggKey) == "string" then
			PetService.HandleBuyEggBulk(player, eggKey)
		end
	end)

	-- The Auto Hatch toggle. Mirrors the free auto-attack switch: the client owns the preference, the
	-- server owns whether it means anything (the pass check is in DriveAutoHatch). Set as an attribute
	-- rather than saved -- it is a per-session choice about a podium you are standing at, and a
	-- preference that survived a rejoin would have players logging in already spending.
	ensureRemote("SetAutoHatch").OnServerEvent:Connect(function(player, on)
		if typeof(on) == "boolean" then
			player:SetAttribute("AutoHatch", on)
		end
	end)

	Remotes.EquipPet.OnServerEvent:Connect(function(player, petId)
		if typeof(petId) == "string" then
			PetService.HandleEquip(player, petId)
		end
	end)

	Remotes.UnequipPet.OnServerEvent:Connect(function(player, petId)
		if typeof(petId) == "string" then
			PetService.HandleUnequip(player, petId)
		end
	end)

	Remotes.FusePet.OnServerEvent:Connect(function(player, petKey, tier)
		if typeof(petKey) == "string" and typeof(tier) == "string" then
			PetService.HandleFuse(player, petKey, tier)
		end
	end)

	ensureRemote("UseTierUp").OnServerEvent:Connect(function(player, petId)
		if typeof(petId) == "string" then
			PetService.HandleTierUp(player, petId)
		end
	end)

	-- One remote for one and for many: the client sends a list either way, so there is no second
	-- code path for the "just this one" case to drift down.
	ensureRemote("DeletePets").OnServerEvent:Connect(function(player, petIds)
		if typeof(petIds) == "table" then
			PetService.HandleDeletePets(player, petIds)
		end
	end)

	ensureRemote("EquipBestPets").OnServerEvent:Connect(function(player)
		PetService.HandleEquipBest(player)
	end)

	ensureRemote("UnequipAllPets").OnServerEvent:Connect(function(player)
		PetService.HandleUnequipAll(player)
	end)
end

return PetService
