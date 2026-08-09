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
function PetService.GetEquippedBonus(data)
	local incomeMult, luckAdd, dnaMult, damageMult = 1, 0, 1, 1
	if not data.EquippedPetIds or not data.Pets then
		return { incomeMult = incomeMult, luckAdd = luckAdd, dnaMult = dnaMult, damageMult = damageMult }
	end
	local equippedLookup = {}
	for _, id in ipairs(data.EquippedPetIds) do
		equippedLookup[id] = true
	end
	for _, pet in ipairs(data.Pets) do
		if equippedLookup[pet.id] then
			-- rarity is a property of the species, not of the save, so it is looked up rather
			-- than stored -- pets hatched before rarities existed still resolve correctly
			local def = GameConfig.GetPetDef(pet.key)
			local bonus = GameConfig.GetPetBonus(pet.tier, def and def.rarity)
			incomeMult *= bonus.incomeMult
			luckAdd += bonus.luckAdd
			dnaMult *= bonus.dnaMult
			damageMult *= bonus.damageMult
		end
	end
	return { incomeMult = incomeMult, luckAdd = luckAdd, dnaMult = dnaMult, damageMult = damageMult }
end

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

local EGG_INTERVAL = 0.35   -- comfortably faster than the hatch animation, far slower than a loop
local MAX_PETS = 600
local lastEgg = {}          -- [userId] = os.clock()

function PetService.HandleBuyEgg(player, eggKey)
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

	if #data.Pets >= MAX_PETS then
		Remotes.Notify:FireClient(player, { kind = "error",
			message = ("Your collection is full (%d pets) -- fuse some first!"):format(MAX_PETS) })
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

	-- luck formula mirrors DNAService.GetLuckPercent's base term (kept local to avoid a circular require)
	local luckPercent = data.Upgrades.Luck * 2 + PetService.GetEquippedBonus(data).luckAdd + (eggDef.luckBonus or 0)
	-- rolls only within this egg's own pool -- its zone's species, sliced by the egg tier's
	-- rarity window -- and the tier's bias shifts the odds inside that slice on top of luck
	local petDef = GameConfig.RollPetForEgg(eggDef, luckPercent)

	local newPet = { id = HttpService:GenerateGUID(false), key = petDef.key, tier = "Normal" }
	table.insert(data.Pets, newPet)

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
	})

	-- After the payout and after the client push, because a beam that goes up before the pet is in
	-- the inventory is announcing something that has not happened yet. Called on EVERY hatch: the
	-- rarity rule and the rate limit both live in AnnounceService, so no publisher has to know what
	-- counts as rare. See its header for why that is a service rather than an `if` here.
	AnnounceService.PetHatched(player, petDef)
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

	local ranked = GameConfig.SortedPetsByPower(data.Pets or {})
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

	local pet
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
				if prompt:IsA("ProximityPrompt") then
					local eggKey = prompt:GetAttribute("EggKey")
					if eggKey then
						prompt.Triggered:Connect(function(player)
							PetService.HandleBuyEgg(player, eggKey)
						end)
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

function PetService.DriveAutoHatch()
	for _, player in ipairs(game.Players:GetPlayers()) do
		local data = PlayerDataService.Get(player)
		if data and GameConfig.OwnsPass(data, "AutoHatch") and #data.Pets < MAX_PETS then
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
					if eggDef and data.DNA >= eggDef.cost then
						PetService.HandleBuyEgg(player, best.eggKey)
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
	end)

	Remotes.BuyEgg.OnServerEvent:Connect(function(player, eggKey)
		if typeof(eggKey) == "string" then
			PetService.HandleBuyEgg(player, eggKey)
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

	ensureRemote("EquipBestPets").OnServerEvent:Connect(function(player)
		PetService.HandleEquipBest(player)
	end)

	ensureRemote("UnequipAllPets").OnServerEvent:Connect(function(player)
		PetService.HandleUnequipAll(player)
	end)
end

return PetService
