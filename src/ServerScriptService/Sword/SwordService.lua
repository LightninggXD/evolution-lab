-- SwordService -- the Diamond door onto the weapon ladder, and nothing else.
--
-- A LEAF (`docs/SPLIT.md` §2). It owns one remote, one save field and one purchase; the numbers
-- live in `GameConfig.Swords`, the geometry lives in `SwordModel`, and the damage term lives in
-- `DNAService.GetCombatDamage` -- which is still the only thing in this game that computes damage.
--
-- `HandleBuy` is `DNAService.HandleBuyDiamondUpgrade` beat for beat -- Get, def, level, price,
-- maxed branch, afford branch, `-=`, write, Telemetry, PushToClient, Notify -- and it is a copy on
-- purpose rather than a shared helper: those two are the only Diamond sinks in the game that are
-- not one-shot, and the day one of them grows a discount or a cap the other must not follow it.

local RS = game:GetService("ReplicatedStorage")
local GameConfig = require(RS.Modules.GameConfig)
local Remotes = RS.Remotes

local PlayerDataService = require(script.Parent.Parent.PlayerDataService)
local Telemetry = require(script.Parent.Parent.Telemetry)
local SwordModel = require(script.Parent.SwordModel)

local SwordService = {}

-- The Remotes folder is authored in the place rather than generated, so a remote a newer version of
-- this file talks over simply does not exist in an older save of the place. Creating the missing
-- one here keeps script and place in step without a by-hand Studio step -- and the client waits for
-- it by name, so it does not matter which side wins the race. (`PetService`'s idiom, copied.)
local function ensureRemote(name)
	local r = Remotes:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = Remotes
	end
	return r
end

local BuySword = ensureRemote("BuySword")

-- ===== PUTTING THE BLADE ON A BODY THAT IS ALREADY STANDING THERE =====
--
-- A purchase has to show immediately or the player is left holding the old sword and reading a
-- panel that says they own a new one -- the same complaint `DNAService.OnMasteryChanged` exists to
-- answer for walk speed and health. The body is settled by definition here (the player has been
-- playing), so this needs no `waitForBodySettled`: that guard is for the frames straight after a
-- CharacterAdded, and `EvolutionVisuals.dress` already owns that path.
function SwordService.Refresh(player, data)
	local character = player and player.Character
	if not character then return end
	data = data or PlayerDataService.Get(player)
	if not data then return end
	SwordModel.Apply(character, GameConfig.GetSwordTier(data), GameConfig.GetSwordLevel(data))
end

-- ===== THE PURCHASE =====
--
-- ONE RUNG AT A TIME AND ALWAYS THE NEXT ONE. The remote carries no argument at all, which is what
-- makes it unspoofable: there is no tier number for a client to lie about, no "buy tier 10 for
-- tier 2's price", and no branch to get wrong. `data.SwordLevel` is the position and `+= 1` is the
-- only move. That is the same reasoning that keeps `data.Rebirths` a bare counter.
function SwordService.HandleBuy(player)
	local data = PlayerDataService.Get(player)
	if not data then return end

	local level = GameConfig.GetSwordLevel(data)
	local cost = GameConfig.GetSwordCost(level)
	if cost == math.huge then
		Remotes.Notify:FireClient(player, { kind = "error", message = "You already carry the last blade!" })
		return
	end

	if (data.Diamonds or 0) < cost then
		Remotes.Notify:FireClient(player, { kind = "error", message = "Not enough Diamonds!" })
		return
	end

	data.Diamonds -= cost
	data.SwordLevel = level + 1
	local tier = GameConfig.Swords[data.SwordLevel]

	Telemetry.Economy(player, "Sink", Telemetry.Currency.Diamonds, cost, data.Diamonds,
		Telemetry.Tx.Shop, "sword:" .. (tier and tier.key or tostring(data.SwordLevel)))

	-- The steel BEFORE the toast. The notification is the thing that makes a player look at their
	-- own hands, and a body still holding the old blade when they do is the whole of "I bought it
	-- and nothing happened".
	SwordService.Refresh(player, data)

	PlayerDataService.PushToClient(player)
	Remotes.Notify:FireClient(player, {
		kind = "sword",
		level = data.SwordLevel,
		name = tier and tier.displayName or "Sword",
		emoji = tier and tier.emoji or "\u{2694}\u{FE0F}",
		mult = tier and tier.damageMult or 1,
	})
end

function SwordService.Init()
	BuySword.OnServerEvent:Connect(function(player)
		SwordService.HandleBuy(player)
	end)
end

-- ===== A REBIRTH DOES NOT TAKE THE SWORD, AND THAT IS STATED HERE RATHER THAN INFERRED =====
--
-- `RebirthService` wipes by naming fields -- DNA, XP, StageIndex, Upgrades, UnlockedZones,
-- CurrentZone, DefeatedBosses, Characters -- so `SwordLevel` survives simply by not being on that
-- list. That is a survival by omission, which is exactly the kind of thing that gets "tidied up"
-- by a later session that reads the wipe list and wonders why the new field is missing from it.
--
-- IT IS DELIBERATE AND IT MATCHES THE RULE ALREADY IN THAT FILE: a rebirth keeps Diamonds,
-- DiamondUpgrades and MasteredStages, i.e. **everything bought with Diamonds is kept and
-- everything climbed to is reset**. The sword is bought with Diamonds. Taking it away would also
-- make the reset cost 20,440 diamonds -- roughly 45 hours of the best measured farm in the game --
-- which is not a rebirth, it is a punishment.
return SwordService
